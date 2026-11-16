-- LoadBots: the 30-player load test (spec: M1 "30-player test place", M4 gate "30 bots hold the server
-- frame"). Studio only, started from the Dev panel. Each bot is a full Hero on the server: drones target it,
-- it flies around Downtown at cruise speed and fires Zap Bolt and Chain Lightning through the same
-- CombatService path players use, and its body replicates to every client like a player's would.
-- PLACEHOLDER ART: the bot body is a few plain parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

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
	local d = Config.City.districts.Downtown
	local x = rng:NextNumber(d.minX, d.maxX)
	local z = rng:NextNumber(d.minZ, d.maxZ)
	local y = CityBuilder.heightAt(x, z) + rng:NextNumber(15, 90)
	return Vector3.new(x, y, z)
end

local function makeBody(index: number): (Model, { BasePart }, { CFrame })
	local model = Instance.new("Model")
	model.Name = "LoadBot" .. index
	local hue = (index * 0.137) % 1
	local suit = Color3.fromHSV(hue, 0.7, 0.9)
	local specs = {
		{ "Torso", Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), suit },
		{ "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.7, 0), Color3.fromRGB(240, 200, 170) },
		{ "Legs", Vector3.new(2, 2, 1), CFrame.new(0, -2, 0), suit:Lerp(Color3.new(0, 0, 0), 0.4) },
		{
			"Cape",
			Vector3.new(1.8, 2.8, 0.2),
			CFrame.new(0, -0.3, 0.65),
			Color3.fromHSV((hue + 0.5) % 1, 0.8, 0.8),
		},
	}
	local parts, offsets = {}, {}
	for _, s in specs do
		local p = Instance.new("Part")
		p.Name = s[1]
		p.Size = s[2]
		p.Color = s[4]
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = model
		table.insert(parts, p)
		table.insert(offsets, s[3])
	end
	model.PrimaryPart = parts[1]
	return model, parts, offsets
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
					local num = if bot.seq % 12 == 0 then Config.Abilities.list.ChainLightning.num else 1
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
	RunService.Heartbeat:Connect(function(dt)
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
	end)
	PerfMonitor.watch("bots", LoadBots.count)
end

return LoadBots
