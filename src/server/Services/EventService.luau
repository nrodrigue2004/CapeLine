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
-- * Your double (nate's lore A2, build plan step 9): the rare tier (Config.Events.scheduler.rare) may give a due
--   slot to the evil twin's return: one eligible hero (EventPlan.doubleOk: past The Copy, in the open city, not
--   in the Crater, the prologue or a mission, not AFK, 3 h of play since their last) meets their own twin
--   (EnemyService.spawnTwin) nearby, with a news flash for everyone and a name card and Patch's radio line on
--   their device; nearby heroes help and share x3 pay. profile.stats.doubleAt keeps the play time of the last.
-- * Side-vs-side events (nate's lore, build plan step 12): the side tier (Config.Events.scheduler.side) may give a
--   due slot to one of 3 events where one side defends and the other steals, when both sides are on the server:
--   the armoured Crane data truck across Downtown (float: the Vigil escort it, only the Syndicate's hits crack
--   it), the Uptown vault (hold: the Syndicate crack it only while they outnumber the Vigil in its ring) and the
--   Syndicate's Spark crystal shipment at the Docks (shards: each crystal counts for the side that grabs it).
--   PvP rules are untouched: only flagged heroes fight each other; everyone fights the robot waves. Everyone
--   who took part is paid as for any event plus own-side reputation (Paid signal, RepService), the winners a
--   little more; a news flash and a name card open it and the news names a hero of the winning side.
-- * Zone level: the median level of the heroes in the server, raised to the area floor (ZoneLevel).
-- * Event.State goes to everyone at 1 Hz while events run: { num, x, z, left, have, need, state, heroic,
--   defend (0, or 1 the Vigil / 2 the Syndicate for a side event), Vigil score, Syndicate score }.

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
local PassRules = require(Shared:WaitForChild("PassRules")) -- H8: the weekly episode tilts the mix
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local ZoneLevel = require(Shared:WaitForChild("ZoneLevel"))
local Progress = require(Shared:WaitForChild("Progress"))
local HeroicRules = require(Shared:WaitForChild("HeroicRules"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

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
local OpeningService = require(script.Parent.OpeningService)
local MissionService = require(script.Parent.MissionService)
local NewsService = require(script.Parent.NewsService)

local EventService = {}

-- (player, id, result, rep) every hero an event paid; result is the winning side or "draw" for a side event
-- (nil for the rest). RepService pays own-side reputation from it (lore step 12).
EventService.Paid = Signal.new()

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
	target: Player?, -- Your double: the hero it copies
	twin: number?, -- Your double: the twin's robot id
	side: EventPlan.SideState?, -- lore step 12: a side-vs-side event's score
	result: string?, -- lore step 12: "hero", "villain" or "draw" once it is over
	top: { [string]: { [number]: number } }?, -- lore step 12: each side's heroes' share (for the news)
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

-- lore step 12: the armoured Crane data truck (PLACEHOLDER ART: a navy box truck with the Crane C on its sides)
local function truckModel(m: Model)
	local navy = Color3.fromRGB(36, 48, 92)
	SiteKit.part(
		m,
		Vector3.new(9, 3, 22),
		CFrame.new(0, 2, 0),
		Color3.fromRGB(40, 42, 50),
		Enum.Material.Metal
	)
	SiteKit.part(m, Vector3.new(9, 8, 14), CFrame.new(0, 7.5, 3), navy, Enum.Material.DiamondPlate)
	SiteKit.part(m, Vector3.new(8.6, 5, 6), CFrame.new(0, 6, -7.5), navy, Enum.Material.Metal)
	SiteKit.part(
		m,
		Vector3.new(7.8, 2.2, 0.3),
		CFrame.new(0, 7, -10.6),
		Color3.fromRGB(140, 190, 230),
		Enum.Material.Glass
	)
	for _, s in { -1, 1 } do
		-- the Crane C: three white bars on each side
		local x = s * 4.6
		SiteKit.part(m, Vector3.new(0.2, 0.8, 4), CFrame.new(x, 10, 3), Color3.fromRGB(245, 245, 250))
		SiteKit.part(m, Vector3.new(0.2, 4, 0.8), CFrame.new(x, 8, 4.6), Color3.fromRGB(245, 245, 250))
		SiteKit.part(m, Vector3.new(0.2, 0.8, 4), CFrame.new(x, 6, 3), Color3.fromRGB(245, 245, 250))
		for _, z in { -7, 7 } do
			SiteKit.part(
				m,
				Vector3.new(1.4, 3.2, 3.2),
				CFrame.new(s * 4.4, 1.6, z) * CFrame.Angles(0, 0, math.rad(90)),
				Color3.fromRGB(20, 20, 24),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			)
		end
	end
	SiteKit.part(
		m,
		Vector3.new(4, 0.5, 1),
		CFrame.new(0, 11.8, 3),
		Color3.fromRGB(255, 80, 60),
		Enum.Material.Neon
	)
end

local OBJECT_MODELS: { [string]: (Model) -> () } = {
	Airship = airshipModel,
	Float = floatModel,
	Clamp = clampModel,
	Truck = truckModel,
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
				local s = ev.side
				if s then
					-- lore step 12: a crystal counts for the grabber's side (the pay's gear roll comes at the end)
					local k = if hero.side == "villain" then "villain" else "hero"
					s[k] += 1
					local top = ev.top :: any
					top[k][hero.id] = (top[k][hero.id] or 0) + 1
				elseif hero.player then
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
		if ev.side then
			-- lore step 12: only the stealing side's hits crack the truck (the defenders guard it)
			ev.object.allow = function(heroId: number?): boolean
				local h = heroId and HeroService.byId(heroId)
				local ok = h ~= nil and EventPlan.canCrack(d, h.side)
				if ok and h then
					local k = if h.side == "villain" then "villain" else "hero"
					local top = ev.top :: any
					top[k][h.id] = (top[k][h.id] or 0) + 1
				end
				return ok
			end
		end
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
	if def.side then
		-- lore step 12: a side-vs-side event keeps each side's score
		ev.side = { goal = def.goal, hero = 0, villain = 0, need = def.shards }
		ev.top = { hero = {}, villain = {} }
	end
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
			side = def.side or nil, -- lore step 12: the name card shows for everyone
		})
	end
	if def.side and ev.state == STATE.active then
		NewsService.post("sideStart", nil, def.num)
	end
end

---------------------------------------------------------------------------
-- Your double (lore step 9): the rare tier's evil twin, aimed at one hero
---------------------------------------------------------------------------

local DOUBLE = EC.events.YourDouble
local moved: { [number]: { pos: Vector3, at: number } } = {} -- hero id -> last spot that counted as a move
local idledAt: { [Player]: number } = {} -- os.clock of the last Player.Idled (Roblox: 2 minutes without input)
local doubleFor: number? = nil -- the hero the rare tier just picked

-- Watch who is moving (AFK check), once a second
local function watchMoves(now: number)
	for id, h in HeroService.all() do
		local p = h.player and HeroService.position(h)
		if p then
			local m = moved[id]
			if not m or (p - m.pos).Magnitude >= DOUBLE.afkMove then
				moved[id] = { pos = p, at = now }
			end
		end
	end
	for id in moved do
		if not HeroService.byId(id) then
			moved[id] = nil
		end
	end
end

-- What EventPlan.doubleOk reads about a hero (nil for a bot or a hero not loaded yet)
local function doubleInfo(h: any, now: number): EventPlan.DoubleInfo?
	local player = h.player
	local pos = player and h.loaded and HeroService.position(h)
	local profile = player and DataService.get(player)
	local char = profile and ProfileSchema.active(profile)
	if not pos or not profile or not char then
		return nil
	end
	local m = moved[h.id]
	local still = if m then now - m.at else 0
	local idle = idledAt[player]
	if idle and (not m or idle > m.at) then
		still = math.max(still, DOUBLE.afk)
	end
	local last = profile.stats.doubleAt or 0
	return {
		level = h.level,
		copyDone = type(char.story) == "table" and StoryPlan.cleared(char.story, DOUBLE.mission),
		prologue = OpeningService.running(player),
		mission = MissionService.runOf(player) ~= nil,
		y = pos.Y,
		crater = player:GetAttribute("InCrater") == true,
		busy = not h.alive or h.downed == true or h.scene ~= nil or h.traveling == true,
		still = still,
		played = profile.stats.playSeconds or 0,
		lastAt = if last > 0 then last else nil,
	}
end

-- The rare tier asks: may a rare event start now? (picks the double's hero)
local function rareAllowed(id: string): boolean
	if id ~= "YourDouble" or not Config.Enemies.EvilTwin.on then
		return false
	end
	local now = os.clock()
	local list = {}
	for hid, h in HeroService.all() do
		local info = doubleInfo(h, now)
		if info then
			list[hid] = info
		end
	end
	doubleFor = EventPlan.doublePick(EC, list, rng)
	return doubleFor ~= nil
end

-- Start the double on this hero. Returns false when the twin could not spawn (switched off, server full).
local function startDouble(h: any): boolean
	local player: Player? = h.player
	local at = player and HeroService.position(h)
	if not player or not at then
		return false
	end
	local a = rng:range(0, 2 * math.pi)
	local d = rng:range(DOUBLE.spawnAt[1], DOUBLE.spawnAt[2])
	local near = Vector3.new(at.X + math.cos(a) * d, at.Y, at.Z + math.sin(a) * d)
	local spot = groundSpot(near, 0, 30)
	nextTag += 1
	local twin = EnemyService.spawnTwin(player, spot + Vector3.new(0, 2, 0), h.level, nextTag)
	if not twin then
		return false
	end
	EnemyService.tune(twin, { hpMult = DOUBLE.hpMult })
	local now = os.clock()
	local ev: Live = {
		id = "YourDouble",
		def = DOUBLE,
		goal = "twin",
		level = h.level,
		heroic = false,
		pos = spot,
		tag = nextTag,
		started = now,
		ends = now + DOUBLE.length,
		have = 0,
		need = 1,
		state = STATE.active,
		things = { twin },
		robots = { [twin] = true },
		helpers = { [h.id] = true },
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
	ev.target = player
	ev.twin = twin
	byRobot[twin] = ev.id
	live[ev.id] = ev
	local profile = DataService.get(player)
	if profile then
		profile.stats.doubleAt = math.max(1, profile.stats.playSeconds or 0)
	end
	-- the hero hears it on their device (name card, Patch on the radio); heroes near them get the call to help
	Net.fire(
		"Toast",
		player,
		{ id = "event", num = DOUBLE.num, name = DOUBLE.name, text = DOUBLE.text, mine = true }
	)
	for _, other in SiteKit.heroesIn(at, DOUBLE.notify) do
		if other.player and other.player ~= player then
			Net.fire("Toast", other.player, {
				id = "event",
				num = DOUBLE.num,
				name = DOUBLE.name,
				text = DOUBLE.helpText,
			})
		end
	end
	NewsService.post("double", player)
	return true
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
			if table.find(EC.rare, ev.id) then
				credits, renown = EventPlan.rarePay(EC, credits, renown)
			end
			EconomyService.addCredits(player, credits)
			EconomyService.addRenown(player, renown)
			-- the meteor shower's roll is the shard itself (a side event's crystals are not: it rolls here)
			if ev.goal ~= "shards" or ev.side then
				GearService.grant(player, "event", HeroicRules.gearLevel(Config, ev.level, ev.heroic))
			end
			local villain = hero.side == "villain"
			-- lore step 12: own-side reputation for taking part (RepService pays it), the winners a little more
			local E = Config.Remembers.earn
			local rep = if ev.side then EventPlan.sideRep(E, ev.result, hero.side) else E.event
			local mine = if villain then "villain" else "hero"
			Net.fire("Toast", player, {
				id = "eventDone",
				num = ev.def.num,
				name = if villain and ev.def.villainName then ev.def.villainName else ev.def.name,
				credits = credits,
				renown = renown,
				heroic = ev.heroic or nil,
				winner = if ev.side then ev.result else nil,
				result = if not ev.side
					then nil
					elseif ev.result == "draw" then "draw"
					elseif ev.result == mine then "win"
					else "lose",
				rep = rep,
				track = if villain then "syndicate" else "vigil",
			})
			EventService.Paid:Fire(player, ev.id, ev.result, rep)
		end
	end
end

-- Lore step 12: the hero the news names for a side event's winners (the most crystals, hits or ring time;
-- any helper of that side when nobody scored)
local function sideTop(ev: Live, winner: string): Player?
	local best, bestN = nil, -1
	for heroId, n in (ev.top and ev.top[winner]) or {} do
		local h = HeroService.byId(heroId)
		if h and h.player and n > bestN then
			best, bestN = h.player, n
		end
	end
	if best then
		return best
	end
	for heroId in ev.helpers do
		local h = HeroService.byId(heroId)
		if h and h.player and (if h.side == "villain" then "villain" else "hero") == winner then
			return h.player
		end
	end
	return nil
end

local function finish(ev: Live, ok: boolean)
	ev.state = if ok then STATE.done else STATE.failed
	if ok then
		pay(ev)
		if ev.goal == "twin" and ev.target and ev.target.Parent then
			NewsService.post("doubleDown", ev.target)
		end
		-- lore step 12: the side event's result on the news, naming a hero of the winning side
		if ev.side and ev.result then
			if ev.result == "draw" then
				NewsService.post("sideDraw", nil, ev.def.num)
			else
				NewsService.post(
					if ev.result == "hero" then "sideVigil" else "sideSyndicate",
					sideTop(ev, ev.result),
					ev.def.num
				)
			end
		end
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

-- Lore step 12: a side-vs-side event's step. Each side does its own part on the same objective (EventPlan's
-- rules); PvP is untouched (only flagged heroes may hit each other, as everywhere).
local function sideOf(h: any): string
	return if h.side == "villain" then "villain" else "hero"
end

local function stepSide(ev: Live, now: number, dt: number)
	local d, s = ev.def, ev.side :: EventPlan.SideState
	local top = ev.top :: any
	local defend, steal = EventPlan.roles(d)
	if ev.goal == "float" and ev.object and ev.path then
		-- the truck rolls at full speed while a defender is near it, else it crawls; damage never slows it
		local o = ev.object
		local escorted = false
		for _, h in SiteKit.heroesIn(o.pos, d.escort) do
			ev.helpers[h.id] = true
			if sideOf(h) == defend then
				escorted = true
				top[defend][h.id] = (top[defend][h.id] or 0) + dt
			end
		end
		ev.travelled = math.min(ev.length, ev.travelled + d.speed * (if escorted then 1 else d.crawl) * dt)
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
		if ev.have < 1 then
			SiteKit.moveObject(o, at, yaw)
			ev.pos = at
			CitizenService.danger(at.X, at.Z, 40, 2)
		end
		s.broken = ev.have >= 1
		s.arrived = ev.travelled >= ev.length
		s[defend] = math.floor(ev.travelled / math.max(ev.length, 1) * 100)
		s[steal] = math.floor((1 - math.max(0, o.hp) / math.max(o.maxHp, 1)) * 100)
	elseif ev.goal == "hold" then
		-- the stealers crack the vault only while they outnumber the defenders in its ring
		local nD, nS = 0, 0
		for _, h in SiteKit.heroesIn(ev.pos, (d.ring or 14) + 3) do
			ev.helpers[h.id] = true
			local k = sideOf(h)
			if k == defend then
				nD += 1
			else
				nS += 1
			end
			top[k][h.id] = (top[k][h.id] or 0) + dt
		end
		ev.held += EventPlan.crackRate(Config.Incidents, nS, nD) * dt
		ev.have = math.min(ev.need, math.floor(ev.held * 10) / 10)
		s.cracked = ev.held >= ev.need
		s[steal] = math.floor(math.min(1, ev.held / math.max(ev.need, 1)) * 100)
		s[defend] = math.floor(math.min(1, (now - ev.started) / d.length) * 100)
	end
	-- shards: the pickups add to each side's count as they are grabbed
	s.timeUp = now >= ev.ends
	local r = EventPlan.sideResult(d, s)
	if r then
		ev.result = r
		finish(ev, true) -- both sides are paid for taking part, the winners a little more
	end
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
	if ev.side then
		stepSide(ev, now, dt)
		return
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
	elseif goal == "twin" and ev.twin and ev.have < 1 then
		-- the marker and the help radius follow the twin; a twin removed some other way ends it
		local e = EnemyService.get(ev.twin)
		if e and e.alive then
			ev.pos = Vector3.new(e.x, e.y, e.z)
		else
			finish(ev, false)
			return
		end
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
	if ev.goal == "robots" or ev.goal == "twin" then
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
			-- lore step 12: a side event's defending side (1 the Vigil, 2 the Syndicate) and each side's score
			if ev.side then (if ev.def.defend == "villain" then 2 else 1) else 0,
			if ev.side then ev.side.hero else 0,
			if ev.side then ev.side.villain else 0,
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

-- Studio: start side event n (1 to 3, Config.Events.side) now, ignoring the side tier's odds and gap and who
-- is on the server (lore step 12)
function EventService.forceSide(n: number): boolean
	local id = EC.side and EC.side[n]
	if not id or live[id] then
		return false
	end
	plan.active[id] = os.clock() + EC.events[id].length
	plan.last = id
	start(id)
	return true
end

-- The side tier asks: may this side event start now? (both sides in the open city, lore step 12)
local function sideAllowed(_id: string): boolean
	local heroes, villains = 0, 0
	for _, h in HeroService.all() do
		if h.player then
			if h.side == "villain" then
				villains += 1
			else
				heroes += 1
			end
		end
	end
	return EventPlan.sideOk(EC, heroes, villains)
end

-- Studio: your double on you now, ignoring the rare tier's odds, cooldowns and who may get it (the twin must
-- still spawn); false when one is already running or the twin is switched off
function EventService.forceDouble(player: Player): boolean
	local h = HeroService.get(player)
	if not h or live.YourDouble then
		return false
	end
	plan.active.YourDouble = os.clock() + DOUBLE.length
	if not startDouble(h) then
		plan.active.YourDouble = nil
		return false
	end
	return true
end

-- Studio: why the rare tier would or would not pick this hero now (EventPlan.doubleOk's reason)
function EventService.doubleWhy(player: Player): string
	local h = HeroService.get(player)
	local info = h and doubleInfo(h, os.clock())
	if not info then
		return "not loaded"
	end
	local ok, why = EventPlan.doubleOk(EC, info)
	return if ok then "eligible" else (why or "?")
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
	local function watchIdle(player: Player)
		player.Idled:Connect(function()
			idledAt[player] = os.clock()
		end)
	end
	for _, p in Players:GetPlayers() do
		watchIdle(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		idledAt[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		watchIdle(player)
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
			local id = EventPlan.due(
				EC,
				plan,
				now,
				rng,
				PassRules.eventWeights(Config, os.time()),
				rareAllowed,
				sideAllowed
			)
			if id == "YourDouble" then
				local h = doubleFor and HeroService.byId(doubleFor)
				if not h or not startDouble(h) then
					EventPlan.finish(plan, id)
				end
				doubleFor = nil
			elseif id then
				start(id)
			end
		end
		for _, ev in live do
			stepEvent(ev, now, acc)
		end
		acc = 0
		if sendAcc >= 1 then
			sendAcc = 0
			watchMoves(now)
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
