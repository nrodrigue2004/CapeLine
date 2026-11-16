-- LoadBots: the 30-player load test (spec: M1 "30-player test place", M4 gate "30 bots hold the server
-- frame"). Studio only, started from the Dev panel. Each bot is a full Hero on the server: drones target it,
-- it flies across the whole map (hub and outskirts, the M4 gate) at cruise speed and fires Zap Bolt and Chain Lightning through the same
-- CombatService path players use, and its body replicates to every client like a player's would.
-- PLACEHOLDER ART: the bot body is the R15 person rig in plain colours (NpcRig).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local AbilityRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityRules"))
local Cooldowns = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Cooldowns"))
local RigMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RigMath"))
local NpcRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcRig"))
local HeroService = require(script.Parent.HeroService)
local CombatService = require(script.Parent.CombatService)
local EnemyService = require(script.Parent.EnemyService)
local CityBuilder = require(script.Parent.CityBuilder)
local PerfMonitor = require(script.Parent.PerfMonitor)

local LoadBots = {}

type Bot = {
	hero: any,
	model: Model,
	parts: { BasePart },
	offsets: { CFrame },
	position: Vector3,
	velocity: Vector3,
	waypoint: Vector3,
	nextFire: number,
	seq: number,
}

local bots: { Bot } = {}
local folder: Folder? = nil
local nextId = 2000000000
local rng = Random.new()

local function randomWaypoint(): Vector3
	-- half the bots' legs stay over the hub, half cross the outskirts, so streaming is tested everywhere
	local half = if rng:NextNumber() < 0.5 then Config.City.hub.max else Config.City.mapSize / 2 - 100
	local x = rng:NextNumber(-half, half)
	local z = rng:NextNumber(-half, half)
	local y = CityBuilder.heightAt(x, z) + rng:NextNumber(15, 90)
	return Vector3.new(x, y, z)
end

-- Each bot is a hero on the heroes' blocky R15 rig (nate, 2026-11-16: "literally everyone should be r15") in
-- its own suit colour with a cape; only the root moves, the rig follows it
local botLayout = RigMath.layout(Config.HeroRig, nil, 1)
local function makeBody(index: number): (Model, { BasePart }, { CFrame })
	local hue = (index * 0.137) % 1
	local suit = Color3.fromHSV(hue, 0.7, 0.9)
	local rig = NpcRig.person(
		botLayout,
		"LoadBot" .. index,
		suit,
		suit:Lerp(Color3.new(0, 0, 0), 0.4),
		Color3.fromRGB(240, 200, 170),
		Color3.fromRGB(40, 32, 28)
	)
	local ut = rig.parts.UpperTorso
	local cape = Instance.new("Part")
	cape.Name = "Cape"
	cape.Size = Vector3.new(ut.Size.X * 0.9, 2.8, 0.2)
	cape.Color = Color3.fromHSV((hue + 0.5) % 1, 0.8, 0.8)
	cape.Material = Enum.Material.SmoothPlastic
	cape.CastShadow = false
	NpcRig.fix(rig, "UpperTorso", cape, CFrame.new(0, ut.Size.Y * 0.5 - 1.4, ut.Size.Z * 0.5 + 0.12))
	for _, p in rig.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CastShadow = false
		end
	end
	return rig.model, { rig.root }, { CFrame.identity }
end

function LoadBots.count(): number
	return #bots
end

function LoadBots.spawn(n: number)
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "LoadBots"
		f.Parent = Workspace
		folder = f
	end
	local max = Config.Dev.loadBots.max
	for _ = 1, math.min(n, max - #bots) do
		nextId += 1
		local index = #bots + 1
		local model, parts, offsets = makeBody(index)
		local start = randomWaypoint()
		local bot: Bot = {
			hero = nil,
			model = model,
			parts = parts,
			offsets = offsets,
			position = start,
			velocity = Vector3.zero,
			waypoint = randomWaypoint(),
			nextFire = os.clock() + rng:NextNumber(0, 1),
			seq = 0,
		}
		bot.hero = HeroService.addBot(nextId, model.Name, bot)
		-- bots spread over every path so the load test exercises every kind of ability
		local ready = {}
		for _, s in Config.Abilities.sets do
			if AbilityRules.pathReady(Config, s) then
				table.insert(ready, s)
			end
		end
		local set = ready[(nextId % #ready) + 1]
		local ranks, loadout = AbilityRules.starter(Config, set)
		bot.hero.ranks, bot.hero.loadout, bot.hero.setId = ranks, loadout, set
		bot.hero.startSet = set
		bot.hero.classId = AbilityRules.archetypeOf(Config, set) or Config.Classes.default
		model.Parent = folder
		table.insert(bots, bot)
	end
	PerfMonitor.logToOutput = #bots > 0
end

function LoadBots.clear()
	for _, bot in bots do
		HeroService.remove(bot.hero)
		bot.model:Destroy()
	end
	table.clear(bots)
	PerfMonitor.logToOutput = false
end

local function nearestEnemy(pos: Vector3, range: number): any
	local best, bestD = nil, range
	for _, c in EnemyService.candidates() do
		local d = (Vector3.new(c.x, c.y, c.z) - pos).Magnitude
		if d < bestD then
			best, bestD = c, d
		end
	end
	return best
end

local function step(dt: number)
	local now = os.clock()
	local speed = Config.Dev.loadBots.flySpeed
	local partList, cframes = {}, {}
	for _, bot in bots do
		local hero = bot.hero
		if hero.alive then
			local to = bot.waypoint - bot.position
			if to.Magnitude < 10 then
				bot.waypoint = randomWaypoint()
			else
				local want = to.Unit * speed
				bot.velocity = bot.velocity:Lerp(want, math.min(1, dt * 2))
				bot.position += bot.velocity * dt
				local floor = CityBuilder.heightAt(bot.position.X, bot.position.Z) + 4
				if bot.position.Y < floor then
					bot.position = Vector3.new(bot.position.X, floor, bot.position.Z)
				end
			end
			if now >= bot.nextFire then
				bot.nextFire = now + Config.Dev.loadBots.fireEvery
				local target = nearestEnemy(bot.position, 45)
				if target then
					bot.seq += 1
					local aim = (
						Vector3.new(target.x, target.y, target.z) - (bot.position + Vector3.new(0, 1.5, 0))
					)
					local l = hero.loadout
					local pick = l.basic
					for _, id in l.skills do
						if Cooldowns.ready(hero.cooldowns, id, now, 0) then
							pick = id
							break
						end
					end
					local num = Config.Abilities.list[pick].num
					CombatService.use(hero, num, aim, target.id, bot.seq, rng:NextNumber(0.03, 0.12))
				end
			end
		end
		local facing = if bot.velocity.Magnitude > 1 then bot.velocity.Unit else Vector3.new(0, 0, -1)
		local base = CFrame.lookAt(
			bot.position,
			bot.position + Vector3.new(facing.X, 0, facing.Z) + Vector3.new(0, 0, 1e-3)
		) * CFrame.Angles(math.rad(-60) * math.clamp(bot.velocity.Magnitude / speed, 0, 1), 0, 0)
		for i, p in bot.parts do
			table.insert(partList, p)
			table.insert(cframes, base * bot.offsets[i])
		end
	end
	if #partList > 0 then
		Workspace:BulkMoveTo(partList, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function LoadBots.init()
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("LoadBots", function(dt)
		if #bots == 0 then
			return
		end
		acc += dt
		if acc < 1 / 20 then
			return
		end
		local t0 = os.clock()
		step(acc)
		acc = 0
		PerfMonitor.add("bots", (os.clock() - t0) * 1000)
	end))
	PerfMonitor.watch("bots", LoadBots.count)
end

return LoadBots
