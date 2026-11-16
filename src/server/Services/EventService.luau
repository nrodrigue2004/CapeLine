-- EventService: the 6 random events (spec: Schedulers > Random events "One every 4 to 6 minutes, max 2 at
-- once, never the same type twice in a row, never inside a mission pocket"; Opening and story > Random
-- events; Event.State). EventPlan says when and which; SiteKit builds the pieces.
-- * Meteor shower: 6 shards fall across the hub (a warning ring first); the first hero to touch each gets
--   a gear roll. Robot rampage: 4 waves of robots at a hub street. Tidal surge: 12 citizens at the Docks
--   carried to 2 rescue boats while the water rises (the water is client-side). Vault breach: hold the
--   vault ring for 30 s (everyone's time adds up) while robbers come in waves; villains play it as a vault
--   rush. Train hijack: stop a runaway train on a Downtown tram line before the end of the line.
--   Blackout: Old Town goes dark; clear the drones at 4 generators and hold each one for 5 s.
-- * Everyone who took part (hit its robots, carried, held, hit the train, grabbed a shard) or stood within
--   150 studs when it cleared gets the event's Credits and Renown at its zone level and one gear roll from
--   the "event" source. A failed event pays nothing.
-- * Zone level: the median level of the heroes in the server, raised to the area floor (ZoneLevel).
-- * Event.State goes to everyone at 1 Hz while events run: { num, x, z, left, have, need, state }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local EventPlan = require(Shared:WaitForChild("EventPlan"))
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local ZoneLevel = require(Shared:WaitForChild("ZoneLevel"))
local Progress = require(Shared:WaitForChild("Progress"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local DataService = require(script.Parent.DataService)
local CitizenService = require(script.Parent.CitizenService)
local IncidentService = require(script.Parent.IncidentService)
local PerfMonitor = require(script.Parent.PerfMonitor)
local SiteKit = require(script.Parent.SiteKit)

local EventService = {}

local EC = Config.Events
local STATE = { active = 0, done = 1, failed = 2 }

type Live = {
	id: string,
	def: any,
	level: number,
	pos: Vector3,
	tag: number,
	started: number,
	ends: number,
	have: number,
	need: number,
	state: number,
	things: { any },
	robots: { [number]: boolean },
	helpers: { [number]: boolean },
	wave: number,
	nextWave: number,
	-- per event
	ring: Model?,
	held: number,
	object: any?,
	dir: { number }?,
	start: Vector3?,
	generators: { { pos: Vector3, guards: { [number]: boolean }, held: number, done: boolean, ring: Model } },
	reported: boolean,
}

local plan: EventPlan.State
local live: { [string]: Live } = {}
local byRobot: { [number]: string } = {}
local rng = Rng.new(Rng.hash(os.time(), 47))
local nextTag = 2000000

local function heroLevels(): { number }
	local out = {}
	for _, h in HeroService.all() do
		if h.player and h.loaded then
			table.insert(out, h.level)
		end
	end
	return out
end

local function levelAt(pos: Vector3): number
	local levels = heroLevels()
	local med = if #levels > 0 then ZoneLevel.median(levels) else 1
	return ZoneLevel.at(Config, pos.X, pos.Z, math.floor(med + 0.5), CityBuilder.world.tiles)
end

-- A hero in the city to centre an event on (never one in a mission pocket)
local function anchor(): Vector3?
	local list = {}
	for _, h in HeroService.all() do
		local p = h.player and h.alive and HeroService.position(h)
		if p and not EventPlan.inPocket(EC, p.Y) and not h.traveling and not h.scene then
			table.insert(list, p)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[rng:int(1, #list)]
end

local function hubCentre(): Vector3
	local bt = CityBuilder.world.downtown.beacon
	return Vector3.new(bt.x, Config.City.ground.y + 0.5, bt.z)
end

local function districtCentre(name: string): Vector3
	local d = Config.City.districts[name]
	return Vector3.new((d.minX + d.maxX) / 2, Config.City.ground.y + 0.5, (d.minZ + d.maxZ) / 2)
end

local function groundSpot(near: Vector3, minD: number, maxD: number): Vector3
	local s = IncidentSpots.find(Config, CityBuilder.world, "street", near.X, near.Z, minD, maxD, rng)
	if s then
		return Vector3.new(s.x, s.y, s.z)
	end
	local x, y, z = IncidentSpots.groundNear(Config, CityBuilder.world, near.X, near.Z, maxD, rng)
	return Vector3.new(x, y, z)
end

local function addRobots(ev: Live, list: { any }, at: Vector3, ring: number?): { [number]: boolean }
	local set = {}
	for _, id in SiteKit.squad({ { kind = list[1], n = list[2] } }, at, ev.level, ev.tag, ring) do
		set[id] = true
		ev.robots[id] = true
		byRobot[id] = ev.id
		table.insert(ev.things, id)
	end
	return set
end

local function markNear(ev: Live, at: Vector3, r: number)
	for _, h in SiteKit.heroesIn(at, r) do
		ev.helpers[h.id] = true
	end
end

---------------------------------------------------------------------------
-- Building each event
---------------------------------------------------------------------------

local function trainModel(m: Model)
	local body = Color3.fromRGB(70, 80, 100)
	SiteKit.part(m, Vector3.new(10, 8, 40), CFrame.new(0, 5, 0), body, Enum.Material.Metal)
	SiteKit.part(
		m,
		Vector3.new(10.2, 3, 30),
		CFrame.new(0, 7, 4),
		Color3.fromRGB(150, 200, 230),
		Enum.Material.Glass
	)
	SiteKit.part(
		m,
		Vector3.new(8, 3, 6),
		CFrame.new(0, 10, -16),
		Color3.fromRGB(220, 60, 60),
		Enum.Material.Metal
	)
	SiteKit.part(
		m,
		Vector3.new(2, 2, 0.4),
		CFrame.new(0, 6, -20.2),
		Color3.fromRGB(255, 230, 120),
		Enum.Material.Neon
	)
end

local function generatorModel(at: Vector3): Model
	local m = SiteKit.model("Generator")
	SiteKit.part(
		m,
		Vector3.new(6, 6, 6),
		CFrame.new(at + Vector3.new(0, 3, 0)),
		Color3.fromRGB(70, 75, 85),
		Enum.Material.Metal
	)
	local core = SiteKit.part(
		m,
		Vector3.new(2, 2, 2),
		CFrame.new(at + Vector3.new(0, 7, 0)),
		Color3.fromRGB(60, 60, 70),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	core.Name = "Core"
	return m
end

local function build(ev: Live)
	local d = ev.def
	local id = ev.id
	if id == "MeteorShower" then
		ev.need = d.shards
		local centre = ev.pos
		for i = 1, d.shards do
			local at = groundSpot(centre, if i == 1 then 0 else 60, d.spread / 2)
			local warn = SiteKit.ring(at, d.grab, Color3.fromRGB(255, 120, 60))
			table.insert(ev.things, warn)
			local h = SiteKit.pickup(at, d.grab, Color3.fromRGB(150, 120, 255), function(hero)
				ev.helpers[hero.id] = true
				ev.have += 1
				if hero.player then
					GearService.grant(hero.player, "event", ev.level)
				end
			end, os.clock() + d.fallTime)
			table.insert(ev.things, h)
			task.delay(d.fallTime, function()
				if warn.Parent then
					warn:Destroy()
				end
			end)
		end
	elseif id == "RobotRampage" then
		ev.need = 0
		for _, w in d.waves do
			ev.need += w[2]
		end
		ev.wave = 1
		addRobots(ev, d.waves[1], ev.pos, 18)
		ev.nextWave = os.clock() + d.waveGap
		CitizenService.danger(ev.pos.X, ev.pos.Z, 90, d.length)
	elseif id == "TidalSurge" then
		ev.need = d.citizens
		local pads = {}
		for i = 1, d.pads do
			local at = groundSpot(ev.pos, 120 + i * 30, 220)
			local pad = SiteKit.pad(at - Vector3.new(0, 0.5, 0), "Rescue boat")
			table.insert(pads, pad)
			table.insert(ev.things, pad)
		end
		for _ = 1, d.citizens do
			local at = groundSpot(ev.pos, 0, 110)
			local c = SiteKit.citizen(at, {
				pads = pads,
				onPick = function(hero)
					ev.helpers[hero.id] = true
				end,
				onSafe = function(hero)
					ev.helpers[hero.id] = true
					ev.have += 1
					if hero.player then
						EconomyService.reward(hero.player, "rescue", ev.level)
						local profile = DataService.get(hero.player)
						if profile then
							profile.stats.rescues += 1
						end
					end
					IncidentService.Rescued:Fire(hero)
				end,
			})
			table.insert(ev.things, c)
		end
		CitizenService.danger(ev.pos.X, ev.pos.Z, 160, d.length)
	elseif id == "VaultBreach" then
		ev.need = d.hold
		local m = SiteKit.model("CityVault")
		SiteKit.part(
			m,
			Vector3.new(22, 16, 5),
			CFrame.new(ev.pos + Vector3.new(0, 8, 12)),
			Color3.fromRGB(110, 115, 125),
			Enum.Material.Metal
		)
		SiteKit.part(
			m,
			Vector3.new(1.4, 12, 12),
			CFrame.new(ev.pos + Vector3.new(0, 8, 9)) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(220, 180, 80),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		table.insert(ev.things, m)
		ev.ring = SiteKit.ring(ev.pos, 14, Color3.fromRGB(255, 210, 90))
		table.insert(ev.things, ev.ring)
		ev.wave = 1
		addRobots(ev, d.waves[1], ev.pos, 26)
		ev.nextWave = os.clock() + d.waveGap
	elseif id == "TrainHijack" then
		ev.need = 1
		local spot = IncidentSpots.find(
			Config,
			CityBuilder.world,
			"tram",
			ev.pos.X,
			ev.pos.Z,
			0,
			2000,
			rng,
			{ run = d.speed * d.length * 0.9 }
		)
		if not spot then
			ev.state = STATE.failed
			return
		end
		ev.start = Vector3.new(spot.x, spot.y, spot.z)
		ev.pos = ev.start
		ev.dir = spot.dir
		local hp = IncidentPlan.objectHp(Config, d.hits, ev.level)
		ev.object = SiteKit.object("Train", ev.start, 6, 11, hp, trainModel, function(heroId)
			if heroId then
				ev.helpers[heroId] = true
			end
		end, function(heroId)
			if heroId then
				ev.helpers[heroId] = true
			end
			ev.have = 1
		end)
		SiteKit.moveObject(ev.object, ev.start, math.rad(if (spot.dir :: any)[1] > 0 then -90 else 90))
		table.insert(ev.things, ev.object)
		addRobots(ev, d.guards, ev.start, 20)
	elseif id == "Blackout" then
		ev.need = d.generators
		for i = 1, d.generators do
			local at = groundSpot(ev.pos, if i == 1 then 30 else 80, 260)
			local m = generatorModel(at)
			table.insert(ev.things, m)
			local ring = SiteKit.ring(at, d.radius, Color3.fromRGB(120, 200, 255))
			table.insert(ev.things, ring)
			local guards = addRobots(ev, d.guards, at, 12)
			table.insert(ev.generators, { pos = at, guards = guards, held = 0, done = false, ring = ring })
		end
	end
end

local function start(id: string)
	local def = EC.events[id]
	local pos: Vector3
	if id == "TidalSurge" then
		pos = groundSpot(districtCentre("Docks"), 0, 150)
	elseif id == "Blackout" then
		pos = groundSpot(districtCentre("OldTown"), 0, 120)
	elseif id == "TrainHijack" then
		pos = districtCentre("Downtown")
	elseif id == "MeteorShower" then
		pos = hubCentre()
	else
		local a = anchor() or hubCentre()
		pos = groundSpot(a, 60, 220)
	end
	nextTag += 1
	local now = os.clock()
	local ev: Live = {
		id = id,
		def = def,
		level = levelAt(pos),
		pos = pos,
		tag = nextTag,
		started = now,
		ends = now + def.length,
		have = 0,
		need = 1,
		state = STATE.active,
		things = {},
		robots = {},
		helpers = {},
		wave = 0,
		nextWave = math.huge,
		ring = nil,
		held = 0,
		object = nil,
		dir = nil,
		start = nil,
		generators = {},
		reported = false,
	}
	live[id] = ev
	build(ev)
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local villain = hero and hero.side == "villain"
		Net.fire("Toast", player, {
			id = "event",
			num = def.num,
			name = if villain and def.villainName then def.villainName else def.name,
			text = if villain and def.villainText then def.villainText else def.text,
		})
	end
end

local function pay(ev: Live)
	markNear(ev, ev.pos, EC.helpRadius)
	for _, g in ev.generators do
		markNear(ev, g.pos, EC.helpRadius)
	end
	local r = EC.reward
	for heroId in ev.helpers do
		local hero = HeroService.byId(heroId)
		local player = hero and hero.player
		if player then
			local m = Progress.multiplier(Config, EconomyService.bonus(player))
			local credits = math.floor((r.credits[1] + r.credits[2] * ev.level) * m + 0.5)
			local renown = math.floor((r.renown[1] + r.renown[2] * ev.level) * m + 0.5)
			EconomyService.addCredits(player, credits)
			EconomyService.addRenown(player, renown)
			-- the meteor shower's roll is the shard itself
			if ev.id ~= "MeteorShower" then
				GearService.grant(player, "event", ev.level)
			end
			local villain = hero.side == "villain"
			Net.fire("Toast", player, {
				id = "eventDone",
				num = ev.def.num,
				name = if villain and ev.def.villainName then ev.def.villainName else ev.def.name,
				credits = credits,
				renown = renown,
			})
		end
	end
end

local function finish(ev: Live, ok: boolean)
	ev.state = if ok then STATE.done else STATE.failed
	if ok then
		pay(ev)
	end
	for rid in ev.robots do
		byRobot[rid] = nil
	end
	EventPlan.finish(plan, ev.id)
	local things = ev.things
	task.delay(3, function()
		SiteKit.clear(things)
	end)
end

local function stepEvent(ev: Live, now: number, dt: number)
	local d = ev.def
	if ev.state ~= STATE.active then
		return
	end
	-- waves: the next one comes on time, or early once the last is beaten
	if d.waves and ev.wave > 0 and ev.wave < #d.waves then
		if now >= ev.nextWave or next(ev.robots) == nil then
			ev.wave += 1
			addRobots(ev, d.waves[ev.wave], ev.pos, if ev.id == "VaultBreach" then 26 else 18)
			ev.nextWave = now + d.waveGap
		end
	end
	if ev.id == "VaultBreach" then
		local inRing = SiteKit.heroesIn(ev.pos, 17)
		for _, h in inRing do
			ev.helpers[h.id] = true
		end
		ev.held += IncidentPlan.holdRate(Config.Incidents, #inRing) * dt
		ev.have = math.min(ev.need, math.floor(ev.held * 10) / 10)
	elseif ev.id == "TrainHijack" and ev.object and ev.start and ev.dir then
		local o = ev.object
		local speed = d.speed * (0.3 + 0.7 * (o.hp / o.maxHp))
		local nextPos = o.pos + Vector3.new(ev.dir[1], 0, ev.dir[2]) * speed * dt
		SiteKit.moveObject(o, nextPos, math.rad(if ev.dir[1] > 0 then -90 else 90))
		ev.pos = nextPos
		if ev.have < 1 and (nextPos - ev.start).Magnitude >= ev.dir[3] then
			finish(ev, false)
			return
		end
	elseif ev.id == "Blackout" then
		local done = 0
		for _, g in ev.generators do
			if not g.done and next(g.guards) == nil then
				local inRing = SiteKit.heroesIn(g.pos, d.radius + 3)
				for _, h in inRing do
					ev.helpers[h.id] = true
				end
				g.held += IncidentPlan.holdRate(Config.Incidents, #inRing) * dt
				if g.held >= d.hold then
					g.done = true
					g.ring:Destroy()
				end
			end
			if g.done then
				done += 1
			end
		end
		ev.have = done
	end
	if ev.have >= ev.need then
		finish(ev, true)
	elseif now >= ev.ends then
		-- the meteor shower simply ends; whoever grabbed shards still took part
		finish(ev, ev.id == "MeteorShower" and ev.have > 0)
	end
end

local function onKilled(_kind: string, by: number?, _pos: Vector3, enemyId: number?)
	local evId = enemyId and byRobot[enemyId]
	local ev = evId and live[evId]
	if not ev then
		return
	end
	byRobot[enemyId :: number] = nil
	ev.robots[enemyId :: number] = nil
	if by then
		ev.helpers[by] = true
	end
	for _, g in ev.generators do
		g.guards[enemyId :: number] = nil
	end
	if ev.id == "RobotRampage" then
		ev.have += 1
	end
end

local function onHit(enemyId: number, heroId: number?)
	local evId = byRobot[enemyId]
	local ev = evId and live[evId]
	if ev and heroId then
		ev.helpers[heroId] = true
	end
end

local function packet(): { any }
	local now = os.clock()
	local list = {}
	for _, ev in live do
		table.insert(list, {
			ev.def.num,
			math.floor(ev.pos.X),
			math.floor(ev.pos.Z),
			math.max(0, math.floor(ev.ends - now)),
			ev.have,
			ev.need,
			ev.state,
		})
	end
	return list
end

-- Studio: start an event now (n = 1 to 6), ignoring the schedule
function EventService.force(n: number): boolean
	local id = EC.order[n]
	if not id or live[id] then
		return false
	end
	plan.active[id] = os.clock() + EC.events[id].length
	plan.last = id
	start(id)
	return true
end

function EventService.active(): { [string]: any }
	return live
end

function EventService.init()
	plan = EventPlan.new(EC, os.clock())
	EnemyService.Killed:Connect(onKilled)
	EnemyService.Hit:Connect(onHit)
	PerfMonitor.watch("events", function()
		return EventPlan.activeCount(plan)
	end)
	Players.PlayerAdded:Connect(function(player)
		task.delay(5, function()
			if player.Parent and next(live) then
				Net.fire("EventState", player, { list = packet() })
			end
		end)
	end)
	local acc, sendAcc = 0, 0
	RunService.Heartbeat:Connect(FrameProf.wrap("EventService", function(dt)
		acc += dt
		sendAcc += dt
		if acc < 0.2 then
			return
		end
		local now = os.clock()
		local t0 = now
		if #Players:GetPlayers() > 0 then
			local id = EventPlan.due(EC, plan, now, rng)
			if id then
				start(id)
			end
		end
		for _, ev in live do
			stepEvent(ev, now, acc)
		end
		acc = 0
		if sendAcc >= 1 then
			sendAcc = 0
			if next(live) then
				Net.fireAll("EventState", { list = packet() })
			end
			-- ended events stay one send so every client sees the result
			for id, ev in live do
				if ev.state ~= STATE.active then
					if ev.reported then
						live[id] = nil
					else
						ev.reported = true
					end
				end
			end
		end
		PerfMonitor.add("schedulers", (os.clock() - t0) * 1000)
	end))
end

return EventService
