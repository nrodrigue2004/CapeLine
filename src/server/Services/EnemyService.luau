-- EnemyService: runs EnemySim on the server (spec: Enemies; caps 90 per server, 6 per hero, 40 AI updates
-- per frame) and replicates it: Enemy.Delta positions at 10 Hz (unreliable, only nearby enemies per player)
-- and CombatEvents for shots, hero hits and deaths (10 Hz batches, only to players near them).
-- Until the incident spawner (M6) a mix of the 6 humanoid robots is kept near every hero.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local EnemySim = require(Shared:WaitForChild("EnemySim"))
local EnemyBuffer = require(Shared:WaitForChild("EnemyBuffer"))
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local HeroService = require(script.Parent.HeroService)
local PerfMonitor = require(script.Parent.PerfMonitor)

local EnemyService = {}
EnemyService.Killed = Signal.new() -- (enemyKind, attackerHeroId, position)
EnemyService.populate = true -- DevService can pause the M1 spawner

local sim: EnemySim.Sim
local seq = 0
local EVENT_RANGE = 220

-- Event kinds on the wire (arrays keep the payload small)
EnemyService.SHOT, EnemyService.HERO_HIT, EnemyService.DIE = 1, 2, 3
EnemyService.WARN, EnemyService.SLAM, EnemyService.SWING, EnemyService.BLOCKED = 4, 5, 6, 7

function EnemyService.candidates(): { any }
	return EnemySim.candidates(sim)
end

-- Returns killed, the enemy, damage dealt, and the hit flag (EnemySim.HIT, BLOCKED, BROKE)
function EnemyService.damage(
	id: number,
	amount: number,
	attackerId: number?,
	from: Vector3?
): (boolean, any, number, number)
	return EnemySim.damage(sim, id, amount, attackerId, from and from.X, from and from.Z)
end

function EnemyService.applyStatus(id: number, kind: string, duration: number, opts: any?): number
	return EnemySim.applyStatus(sim, id, kind, duration, opts)
end

-- Lose track of a hero (Smoke Bomb): the machine drops it as a target
function EnemyService.forget(id: number, heroId: number)
	local e = sim and sim.byId[id]
	if e and e.target == heroId then
		e.target = nil
	end
end

function EnemyService.knock(id: number, dir: Vector3, distance: number): boolean
	return EnemySim.knock(sim, id, dir.X, dir.Z, distance)
end

function EnemyService.addBlocker(pos: Vector3, radius: number, untilT: number)
	EnemySim.addBlocker(sim, pos.X, pos.Y, pos.Z, radius, untilT)
end

function EnemyService.now(): number
	return sim.now
end

-- Move an enemy to a spot (Lift and Throw landing)
function EnemyService.place(id: number, pos: Vector3)
	local e = sim.byId[id]
	if e and e.alive then
		e.x, e.z = pos.X, pos.Z
		e.y = if e.ai == "flyer" then pos.Y + 3 else sim.heightAt(pos.X, pos.Z) + EnemySim.halfHeight(e.cfg)
		e.liftBase = nil
	end
end

function EnemyService.get(id: number): any
	return sim.byId[id]
end

function EnemyService.push(id: number, offset: Vector3)
	EnemySim.push(sim, id, offset.X, offset.Y, offset.Z)
end

function EnemyService.count(): number
	return EnemySim.count(sim)
end

-- Dev: spawn n robots of a kind in a ring around a point
function EnemyService.spawnAround(pos: Vector3, n: number, kind: string?)
	local k = kind or "SparkDrone"
	for i = 1, n do
		local ang = i / n * math.pi * 2
		local x, z = pos.X + math.cos(ang) * 40, pos.Z + math.sin(ang) * 40
		local y = math.max(pos.Y + 15, sim.heightAt(x, z) + 15)
		EnemySim.spawn(sim, k, x, y, z, 1)
	end
end

function EnemyService.clear()
	for i = #sim.enemies, 1, -1 do
		local e = sim.enemies[i]
		EnemySim.damage(sim, e.id, math.huge, nil)
	end
end

local function playerPositions(): { [Player]: Vector3 }
	local out = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			out[player] = root.Position
		end
	end
	return out
end

local function broadcast(events: { any })
	if #events == 0 then
		return
	end
	local positions = playerPositions()
	local per: { [Player]: { any } } = {}
	local r2 = EVENT_RANGE * EVENT_RANGE
	for _, ev in events do
		local ex, ey, ez = ev[3], ev[4], ev[5]
		for player, pos in positions do
			local include = false
			if ev[1] == EnemyService.HERO_HIT then
				include = ev[2] == player.UserId -- your own hits always; others' only nearby
				if not include and ex then
					local dx, dy, dz = ex - pos.X, ey - pos.Y, ez - pos.Z
					include = dx * dx + dy * dy + dz * dz <= r2
				end
			else
				local dx, dy, dz = ex - pos.X, ey - pos.Y, ez - pos.Z
				include = dx * dx + dy * dy + dz * dz <= r2
			end
			if include then
				local list = per[player]
				if not list then
					list = {}
					per[player] = list
				end
				table.insert(list, ev)
			end
		end
	end
	for player, list in per do
		Net.fire("CombatEvents", player, list)
	end
end

local function handleEvents()
	local out = {}
	for _, ev in EnemySim.drainEvents(sim) do
		if ev.k == "shot" then
			table.insert(out, { EnemyService.SHOT, ev.e, ev.x, ev.y, ev.z, ev.vx, ev.vy, ev.vz })
		elseif ev.k == "hit" then
			local hero = HeroService.byId(ev.hero)
			if hero then
				local taken = HeroService.damage(hero, ev.damage, { enemy = ev.e, melee = ev.melee })
				local pos = HeroService.position(hero)
				local dmg = math.floor(taken + 0.5)
				if pos then
					table.insert(out, { EnemyService.HERO_HIT, ev.hero, pos.X, pos.Y, pos.Z, dmg })
				end
			end
		elseif ev.k == "die" then
			local cfg = Config.Enemies[ev.kind]
			table.insert(
				out,
				{ EnemyService.DIE, ev.e, ev.x, ev.y, ev.z, cfg and cfg.typeId or 1, ev.by or 0 }
			)
			EnemyService.Killed:Fire(ev.kind, ev.by, Vector3.new(ev.x, ev.y, ev.z))
		elseif ev.k == "warn" then
			table.insert(
				out,
				{ EnemyService.WARN, ev.e, ev.x, ev.y, ev.z, ev.r, ev.t, ev.arc or 360, ev.yaw or 0 }
			)
		elseif ev.k == "slam" then
			table.insert(out, { EnemyService.SLAM, ev.e, ev.x, ev.y, ev.z, ev.r })
		elseif ev.k == "swing" then
			local e = sim.byId[ev.e]
			if e then
				table.insert(out, { EnemyService.SWING, ev.e, e.x, e.y, e.z, if ev.back then 1 else 0 })
			end
		elseif ev.k == "blocked" then
			table.insert(out, { EnemyService.BLOCKED, 0, ev.x, ev.y, ev.z })
		end
	end
	return out
end

local function sendDeltas()
	seq += 1
	local now = Workspace:GetServerTimeNow()
	local radius = Config.Net.enemyRelevance
	local maxDrawn = Config.Presets.high.enemiesDrawn
	for player, pos in playerPositions() do
		local b = EnemyBuffer.encodeFor(seq, now, sim.enemies, pos.X, pos.Y, pos.Z, radius, maxDrawn)
		Net.fire("EnemyDelta", player, b)
	end
end

function EnemyService.init(world: any)
	local rng = Random.new()
	sim = EnemySim.new(Config, {
		heightAt = function(x, z)
			return WorldMap.heightAt(world, x, z)
		end,
		random = function()
			return rng:NextNumber()
		end,
	})
	HeroService.Removed:Connect(function(hero)
		EnemySim.forgetHero(sim, hero.id)
	end)
	PerfMonitor.watch("enemies", function()
		return EnemySim.count(sim)
	end)
	PerfMonitor.watch("aiTicks", function()
		return sim.ticksLastStep
	end)

	local acc = 0
	local interval = 1 / Config.Enemies.tickRate
	RunService.Heartbeat:Connect(function(dt)
		local t0 = os.clock()
		local heroes = HeroService.simHeroes()
		EnemySim.step(sim, os.clock(), heroes, Config.Enemies.caps.aiTicksPerFrame)
		acc += dt
		local events
		if acc >= interval then
			acc = 0
			if EnemyService.populate then
				EnemySim.populate(sim, heroes, os.clock())
			end
			events = handleEvents()
		end
		PerfMonitor.add("enemies", (os.clock() - t0) * 1000)
		if events then
			local t1 = os.clock()
			broadcast(events)
			sendDeltas()
			PerfMonitor.add("replication", (os.clock() - t1) * 1000)
		end
	end)
end

return EnemyService
