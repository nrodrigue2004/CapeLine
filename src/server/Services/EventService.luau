-- EventService: the 12 random events (spec: Schedulers > Random events "One every 4 to 6 minutes, max 2
-- at once, never the same type twice in a row, never inside a mission pocket"; Opening and story > Random
-- events; Event.State). EventPlan says when, which and where; SiteKit builds the pieces. Each event has a
-- goal (Config.Events), and the waves of robots work the same for every event that has them.
-- * Meteor shower: 6 shards fall across the hub (a warning ring first); the first hero to touch each gets
--   a gear roll. Robot rampage: 4 waves of robots at a hub street. Tidal surge: 12 citizens at the Docks
--   carried to 2 rescue boats while the water rises (the water is client-side). Vault breach: hold the
--   vault ring for 30 s (everyone's time adds up) while robbers come in waves; villains play it as a vault
--   rush. Train hijack: stop a runaway train on a Downtown tram line before the end of the line.
--   Blackout: Old Town goes dark; clear the drones at 4 generators and hold each one for 5 s.
-- * 2026-11-17: Robot airship (break the airship over a downtown while it drops squads), Bridge siege (hold
--   the Old Town bridge against waves), Stadium lockdown (open 3 guarded arena gates), Power plant overload
--   (break 4 guarded clamps at the Docks), Parade gone wrong (stop a hijacked float on its route), Harbour
--   fog ambush (carry 8 citizens to the boats in the fog while robots ambush). Places come from district
--   names (EventPlan.place), so a bigger or second downtown needs no change here.
-- * Everyone who took part (hit its robots, carried, held, hit a target, grabbed a shard) or stood within
--   150 studs when it cleared gets the event's Credits and Renown at its zone level and one gear roll from
--   the "event" source. A failed event pays nothing. From level 40 an event may roll Heroic
--   (Shared.HeroicRules): robots 5 levels up, one more in each wave and guard row, x1.5 pay.
-- * Zone level: the median level of the heroes in the server, raised to the area floor (ZoneLevel).
-- * Event.State goes to everyone at 1 Hz while events run: { num, x, z, left, have, need, state, heroic }.

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
local HeroicRules = require(Shared:WaitForChild("HeroicRules"))

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

type Site = {
	pos: Vector3,
	guards: { [number]: boolean },
	held: number,
	done: boolean,
	ring: Model?,
	object: any?,
}

type Live = {
	id: string,
	def: any,
	goal: string,
	level: number,
	heroic: boolean,
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
	-- per goal
	ring: Model?,
	held: number,
	object: any?,
	dir: { number }?,
	start: Vector3?,
	path: { Vector3 }?,
	length: number,
	travelled: number,
	generators: { Site },
	reported: boolean,
}

local plan: EventPlan.State
local live: { [string]: Live } = {}
local byRobot: { [number]: string } = {}
local rng = Rng.new(Rng.hash(os.time(), 47))
local nextTag = 2000000
EventService.forceHeroic = false -- Studio: the next forced event is Heroic

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

local function groundSpot(near: Vector3, minD: number, maxD: number): Vector3
	local s = IncidentSpots.find(Config, CityBuilder.world, "street", near.X, near.Z, minD, maxD, rng)
	if s then
		return Vector3.new(s.x, s.y, s.z)
	end
	local x, y, z = IncidentSpots.groundNear(Config, CityBuilder.world, near.X, near.Z, maxD, rng)
	return Vector3.new(x, y, z)
end

local function ready(kind: string, level: number): boolean
	return IncidentPlan.kindReady(Config, kind, level)
end

local function robotLevel(ev: Live): number
	return HeroicRules.robotLevel(Config, ev.level, ev.heroic)
end

-- Robots of one { kind, n, fallback } row (a type that is off or not unlocked yet uses its fallback)
local function addRobots(ev: Live, row: { any }, at: Vector3, ring: number?): { [number]: boolean }
	local set = {}
	local r = EventPlan.row(Config, row, ev.level, ev.heroic, ready)
	if not r then
		return set
	end
	for _, id in SiteKit.squad({ r }, at, robotLevel(ev), ev.tag, ring) do
		set[id] = true
		ev.robots[id] = true
		byRobot[id] = ev.id
		table.insert(ev.things, id)
	end
	return set
end

local function addGuards(ev: Live, at: Vector3, ring: number): { [number]: boolean }
	local set = {}
	for _, row in EventPlan.guardRows(ev.def) do
		for id in addRobots(ev, row, at, ring) do
			set[id] = true
		end
	end
	return set
end

local function markNear(ev: Live, at: Vector3, r: number)
	for _, h in SiteKit.heroesIn(at, r) do
		ev.helpers[h.id] = true
	end
end

---------------------------------------------------------------------------
-- Models (PLACEHOLDER ART: plain parts)
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

local function airshipModel(m: Model)
	SiteKit.part(
		m,
		Vector3.new(60, 16, 16),
		CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(80, 84, 96),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	SiteKit.part(
		m,
		Vector3.new(10, 5, 16),
		CFrame.new(0, -10, 4),
		Color3.fromRGB(50, 52, 60),
		Enum.Material.Metal
	)
	for _, x in { -6, 6 } do
		SiteKit.part(
			m,
			Vector3.new(2, 8, 8),
			CFrame.new(x, 0, 30),
			Color3.fromRGB(255, 90, 60),
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
	end
end

local function floatModel(m: Model)
	SiteKit.part(m, Vector3.new(12, 4, 22), CFrame.new(0, 2.5, 0), Color3.fromRGB(240, 200, 60))
	SiteKit.part(
		m,
		Vector3.new(10, 10, 10),
		CFrame.new(0, 9.5, 2),
		Color3.fromRGB(240, 90, 160),
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	SiteKit.part(m, Vector3.new(0.6, 14, 0.6), CFrame.new(4, 11, -8), Color3.fromRGB(240, 240, 240))
	SiteKit.part(
		m,
		Vector3.new(6, 4, 0.3),
		CFrame.new(7, 16, -8),
		Color3.fromRGB(90, 200, 255),
		Enum.Material.Neon
	)
end

local function clampModel(m: Model)
	SiteKit.part(
		m,
		Vector3.new(6, 10, 6),
		CFrame.new(0, 5, 0),
		Color3.fromRGB(90, 96, 110),
		Enum.Material.Metal
	)
	SiteKit.part(
		m,
		Vector3.new(7, 2, 7),
		CFrame.new(0, 7, 0),
		Color3.fromRGB(255, 140, 40),
		Enum.Material.Neon
	)
end

local OBJECT_MODELS: { [string]: (Model) -> () } = {
	Airship = airshipModel,
	Float = floatModel,
	Clamp = clampModel,
}

local function siteModel(kind: string?, at: Vector3): Model
	if kind == "Gate" then
		local m = SiteKit.model("Gate")
		for _, x in { -7, 7 } do
			SiteKit.part(
				m,
				Vector3.new(2, 14, 2),
				CFrame.new(at + Vector3.new(x, 7, 6)),
				Color3.fromRGB(80, 84, 96)
			)
		end
		local bar = SiteKit.part(
			m,
			Vector3.new(14, 10, 0.6),
			CFrame.new(at + Vector3.new(0, 5, 6)),
			Color3.fromRGB(255, 90, 60),
			Enum.Material.Neon
		)
		bar.Name = "Core"
		bar.Transparency = 0.4
		return m
	end
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

local function holdProp(ev: Live, kind: string?)
	if kind == "Vault" then
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
	elseif kind == "Barricade" then
		local m = SiteKit.model("Barricade")
		for i = -2, 2 do
			SiteKit.part(
				m,
				Vector3.new(5, 3, 1.2),
				CFrame.new(ev.pos + Vector3.new(i * 5.5, 1.5, -18)) * CFrame.Angles(0, math.rad(i * 4), 0),
				if i % 2 == 0 then Color3.fromRGB(240, 200, 60) else Color3.fromRGB(40, 40, 46)
			)
		end
		table.insert(ev.things, m)
	end
end

-- A breakable target for the event; broken sets have to 1 (one target) or adds 1 (one of many)
local function target(
	ev: Live,
	model: string,
	at: Vector3,
	lift: number,
	radius: number,
	hits: number,
	count: boolean
): any
	local hp = IncidentPlan.objectHp(Config, hits, robotLevel(ev))
	local h = SiteKit.object(model, at, lift, radius, hp, OBJECT_MODELS[model] or clampModel, function(heroId)
		if heroId then
			ev.helpers[heroId] = true
		end
	end, function(heroId)
		if heroId then
			ev.helpers[heroId] = true
		end
		if count then
			ev.have += 1
		else
			ev.have = 1
		end
	end)
	table.insert(ev.things, h)
	return h
end

---------------------------------------------------------------------------
-- Building each event
---------------------------------------------------------------------------

local function waveTotal(ev: Live): number
	local n = 0
	for _, w in ev.def.waves or {} do
		local r = EventPlan.row(Config, w, ev.level, ev.heroic, ready)
		n += if r then r.n else 0
	end
	return n
end

local function build(ev: Live)
	local d = ev.def
	local goal = ev.goal
	if goal == "shards" then
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
					GearService.grant(
						hero.player,
						"event",
						HeroicRules.gearLevel(Config, ev.level, ev.heroic)
					)
				end
			end, os.clock() + d.fallTime)
			table.insert(ev.things, h)
			task.delay(d.fallTime, function()
				if warn.Parent then
					warn:Destroy()
				end
			end)
		end
	elseif goal == "robots" then
		ev.need = math.max(1, waveTotal(ev))
		CitizenService.danger(ev.pos.X, ev.pos.Z, 90, d.length)
	elseif goal == "rescue" then
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
	elseif goal == "hold" then
		ev.need = d.hold
		holdProp(ev, d.prop)
		ev.ring = SiteKit.ring(ev.pos, d.ring or 14, Color3.fromRGB(255, 210, 90))
		table.insert(ev.things, ev.ring :: Model)
	elseif goal == "train" then
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
		ev.pos = ev.start :: Vector3
		ev.dir = spot.dir
		local hp = IncidentPlan.objectHp(Config, d.hits, robotLevel(ev))
		ev.object = SiteKit.object("Train", ev.pos, 6, 11, hp, trainModel, function(heroId)
			if heroId then
				ev.helpers[heroId] = true
			end
		end, function(heroId)
			if heroId then
				ev.helpers[heroId] = true
			end
			ev.have = 1
		end)
		SiteKit.moveObject(ev.object, ev.pos, math.rad(if (spot.dir :: any)[1] > 0 then -90 else 90))
		table.insert(ev.things, ev.object)
		addGuards(ev, ev.pos, 20)
	elseif goal == "generators" then
		ev.need = d.generators
		for i = 1, d.generators do
			local at = groundSpot(ev.pos, if i == 1 then 30 else 80, 260)
			table.insert(ev.things, siteModel(d.model, at))
			local ring = SiteKit.ring(at, d.radius, Color3.fromRGB(120, 200, 255))
			table.insert(ev.things, ring)
			local guards = addGuards(ev, at, 12)
			table.insert(ev.generators, { pos = at, guards = guards, held = 0, done = false, ring = ring })
		end
	elseif goal == "object" then
		ev.need = 1
		ev.object = target(ev, d.model or "Airship", ev.pos, d.lift or 40, 14, d.hits, false)
		SiteKit.moveObject(ev.object, ev.pos, 0)
		CitizenService.danger(ev.pos.X, ev.pos.Z, 120, d.length)
	elseif goal == "objects" then
		ev.need = d.objects
		for i = 1, d.objects do
			local at = groundSpot(ev.pos, if i == 1 then 20 else 70, d.spread)
			local h = target(ev, d.model or "Clamp", at, 6, 5, d.hits, true)
			SiteKit.moveObject(h, at, 0)
			local guards = addGuards(ev, at, 12)
			table.insert(ev.generators, { pos = at, guards = guards, held = 0, done = false, object = h })
		end
	elseif goal == "float" then
		ev.need = 1
		local pts =
			IncidentSpots.streetPath(Config, CityBuilder.world, ev.pos.X, ev.pos.Z, d.legs, d.leg, rng)
		local path, length = {}, 0
		for i, p in pts do
			table.insert(path, Vector3.new(p[1], Config.City.ground.y + 0.2, p[3]))
			if i > 1 then
				length += (path[i] - path[i - 1]).Magnitude
			end
		end
		if length < 60 then
			ev.state = STATE.failed
			return
		end
		ev.path, ev.length, ev.travelled = path, length, 0
		ev.object = target(ev, d.model or "Float", path[1], 5, 10, d.hits, false)
		SiteKit.moveObject(ev.object, path[1], 0)
	end
	-- the first wave comes at once
	if d.waves and ev.state == STATE.active then
		ev.wave = 1
		addRobots(ev, d.waves[1], ev.pos, if goal == "hold" then (d.ring or 14) + 12 else 18)
		ev.nextWave = os.clock() + d.waveGap
	end
end

local function start(id: string)
	local def = EC.events[id]
	local pos: Vector3
	local x, z = EventPlan.place(Config, def, rng)
	if def.where == "hub" then
		pos = hubCentre()
	elseif x and z then
		pos = if def.goal == "train"
			then Vector3.new(x, Config.City.ground.y + 0.5, z)
			else groundSpot(Vector3.new(x, Config.City.ground.y, z), 0, 150)
	else
		local a = anchor() or hubCentre()
		pos = groundSpot(a, 60, 220)
	end
	nextTag += 1
	local now = os.clock()
	local level = levelAt(pos)
	local heroic = HeroicRules.roll(Config, "event", level, rng)
	if EventService.forceHeroic then
		heroic, EventService.forceHeroic = true, false
	end
	local ev: Live = {
		id = id,
		def = def,
		goal = def.goal,
		level = level,
		heroic = heroic,
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
		path = nil,
		length = 1,
		travelled = 0,
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
			heroic = heroic or nil,
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
			credits, renown = HeroicRules.pay(Config, credits, renown, ev.heroic)
			EconomyService.addCredits(player, credits)
			EconomyService.addRenown(player, renown)
			-- the meteor shower's roll is the shard itself
			if ev.goal ~= "shards" then
				GearService.grant(player, "event", HeroicRules.gearLevel(Config, ev.level, ev.heroic))
			end
			local villain = hero.side == "villain"
			Net.fire("Toast", player, {
				id = "eventDone",
				num = ev.def.num,
				name = if villain and ev.def.villainName then ev.def.villainName else ev.def.name,
				credits = credits,
				renown = renown,
				heroic = ev.heroic or nil,
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
	local goal = ev.goal
	if ev.state ~= STATE.active then
		return
	end
	-- waves: the next one comes on time, or early once the last is beaten
	if d.waves and ev.wave > 0 and ev.wave < #d.waves then
		if now >= ev.nextWave or next(ev.robots) == nil then
			ev.wave += 1
			addRobots(ev, d.waves[ev.wave], ev.pos, if goal == "hold" then (d.ring or 14) + 12 else 18)
			ev.nextWave = now + d.waveGap
		end
	end
	if goal == "hold" then
		local inRing = SiteKit.heroesIn(ev.pos, (d.ring or 14) + 3)
		for _, h in inRing do
			ev.helpers[h.id] = true
		end
		ev.held += IncidentPlan.holdRate(Config.Incidents, #inRing) * dt
		ev.have = math.min(ev.need, math.floor(ev.held * 10) / 10)
	elseif goal == "train" and ev.object and ev.start and ev.dir then
		local o = ev.object
		local speed = d.speed * (0.3 + 0.7 * (o.hp / o.maxHp))
		local nextPos = o.pos + Vector3.new(ev.dir[1], 0, ev.dir[2]) * speed * dt
		SiteKit.moveObject(o, nextPos, math.rad(if ev.dir[1] > 0 then -90 else 90))
		ev.pos = nextPos
		if ev.have < 1 and (nextPos - ev.start).Magnitude >= ev.dir[3] then
			finish(ev, false)
			return
		end
	elseif goal == "float" and ev.object and ev.path then
		local o = ev.object
		-- it slows as it takes damage, and crawls while nobody is near
		local near = #SiteKit.heroesIn(o.pos, 150) > 0
		local speed = d.speed * (0.3 + 0.7 * (o.hp / o.maxHp)) * (if near then 1 else 0.3)
		ev.travelled += speed * dt
		local left = ev.travelled
		local at, yaw = ev.path[#ev.path], 0
		for i = 1, #ev.path - 1 do
			local a, b = ev.path[i], ev.path[i + 1]
			local seg = (b - a).Magnitude
			if left <= seg then
				at = a:Lerp(b, left / math.max(seg, 1e-3))
				yaw = math.atan2(-(b.X - a.X), -(b.Z - a.Z))
				break
			end
			left -= seg
		end
		SiteKit.moveObject(o, at, yaw)
		ev.pos = at
		CitizenService.danger(at.X, at.Z, 40, 2)
		if ev.have < 1 and ev.travelled >= ev.length then
			finish(ev, false)
			return
		end
	elseif goal == "generators" then
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
					if g.ring then
						g.ring:Destroy()
					end
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
		finish(ev, goal == "shards" and ev.have > 0)
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
	if ev.goal == "robots" then
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
			if ev.heroic then 1 else 0,
		})
	end
	return list
end

-- Studio: start an event now (n = 1 to 12), ignoring the schedule; heroic makes it Heroic
function EventService.force(n: number, heroic: boolean?): boolean
	local id = EC.order[n]
	if not id or live[id] then
		return false
	end
	plan.active[id] = os.clock() + EC.events[id].length
	plan.last = id
	EventService.forceHeroic = heroic == true
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
