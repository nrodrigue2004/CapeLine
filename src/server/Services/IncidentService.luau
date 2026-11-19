-- IncidentService: the incident spawner (spec: Schedulers "Every hero keeps 2 incidents within 300 studs. A
-- new one appears within 10 s of one clearing. Max 90 active per server"; Incidents table; Incident.Spawn,
-- Incident.Update). IncidentPlan picks and tracks; IncidentSpots finds the place; SiteKit builds it.
-- * Each player's hero keeps 2 incidents of their side near them. Anyone may help with any incident; the
--   heroes who helped (beat its robots, hit its object, carried a citizen, stood in its ring) share the
--   reward when it clears: Credits and Renown at its zone level and a 12% gear roll (Drops "Incident
--   clear"). Each rescue also pays the carrier (Earn "Rescue").
-- * Out of time: it fails with no reward (the sign falls, the tram rolls off the end of the line, the
--   runner gets away); nobody near it for 45 s, or its hero flew 600 studs off: it quietly goes.
-- * Raid prep incidents run while a world boss counts down; each clear weakens the boss (Cleared signal).
-- * Players within 450 studs get Incident.Spawn once and Incident.Update at 2 Hz until it ends.
-- * 2026-11-17 (more activities): 24 templates and six new step kinds (nest, leader, find, convoy, barrage,
--   tug; Config.Incidents). Templates whose robot types are off or not unlocked at the level are skipped
--   (IncidentPlan.available). From level 40 an incident may roll Heroic (Shared.HeroicRules): robots 5
--   levels up, one more in each squad, x1.5 pay and a higher gear roll. A step's big moments send a "beat"
--   toast (a line plus an existing juice action) to the heroes nearby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local ZoneLevel = require(Shared:WaitForChild("ZoneLevel"))
local WorldClock = require(Shared:WaitForChild("WorldClock"))
local EventPlan = require(Shared:WaitForChild("EventPlan"))
local HeroicRules = require(Shared:WaitForChild("HeroicRules"))
local Progress = require(Shared:WaitForChild("Progress"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local DataService = require(script.Parent.DataService)
local CitizenService = require(script.Parent.CitizenService)
local PerfMonitor = require(script.Parent.PerfMonitor)
local SiteKit = require(script.Parent.SiteKit)
local SetPieceMeshes = require(script.Parent.SetPieceMeshes)

local IncidentService = {}

local IC = Config.Incidents
local S = IC.spawner
IncidentService.Cleared = Signal.new() -- (incident) an incident was cleared (Raid prep weakens the boss)
IncidentService.Rescued = Signal.new() -- (hero) a citizen reached safety (the boss counts it as support)
-- WP5: (incident, heroId?) a Suspicious Hero's mask cracked (the news and the Fake Spotter badge count it)
IncidentService.FakeUnmasked = Signal.new()
IncidentService.prep = false -- a world boss is counting down: Raid prep incidents
IncidentService.clockStart = 0 -- the world clock's cycle start (ClockService sets it)
-- M10 squads set this: (helpers, position) adds squadmates near a cleared incident to its helpers
IncidentService.share = nil :: (({ [number]: boolean }, Vector3) -> ())?

export type Live = {
	id: number,
	owner: number, -- hero id
	side: string,
	plan: IncidentPlan.Incident,
	pos: Vector3,
	spot: IncidentSpots.Spot,
	things: { any }, -- what SiteKit built (cleared at the end)
	enemies: { [number]: boolean },
	helpers: { [number]: boolean },
	known: { [Player]: boolean },
	lastNear: number,
	stepStarted: number,
	ring: Model?,
	object: any?,
	runner: { id: number, idx: number, t: number }?,
	sign: Model?,
	ended: number?,
	medal: string?,
	builtStep: number,
	-- 2026-11-17 step kinds
	targets: { [number]: boolean }, -- the robots that count for the current step
	stepThings: { any }, -- what the current step built that goes when it ends (crowds, huddles, rings)
	stepPos: Vector3?, -- where the current step stands (a hold in front of a building)
	focus: Vector3?, -- where the next rescue waits (the towed car)
	leaderId: number?,
	convoy: { ids: { number }, path: { Vector3 }, length: number, travelled: number }?,
	tug: { car: Model, rope: BasePart, path: { Vector3 }, length: number, moved: number }?,
	barrage: { huddles: { Vector3 }, nextAt: number, shell: { at: Vector3, lands: number, ring: Model }? }?,
	-- a fight step whose squad the server cap stopped completely: try again every few seconds
	retry: { rows: { any }, at: Vector3, ring: number, nextAt: number }?,
	-- WP5 (the Suspicious Hero): its costumed fake, who last hit it, a spawn retry, the next panic wave
	fake: { id: number?, by: number?, retryAt: number, at: Vector3, awake: boolean, cracked: boolean }?,
	panicAt: number?,
}

local live: { [number]: Live } = {}
local byEnemy: { [number]: number } = {} -- robot id -> incident id
local meta: { [number]: { next: number, last: string? } } = {}
local nextId = 0
local rng = Rng.new(Rng.hash(os.time(), 31))

local MEDAL = { gold = 1, silver = 2, bronze = 3 }
local STATE = { active = 0, done = 1, failed = 2, gone = 3 }

local function count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

local function ownedBy(heroId: number): number
	local n = 0
	for _, inc in live do
		if inc.owner == heroId and not inc.ended then
			n += 1
		end
	end
	return n
end

local function tooClose(x: number, z: number): boolean
	for _, inc in live do
		if (inc.pos.X - x) ^ 2 + (inc.pos.Z - z) ^ 2 < 70 * 70 then
			return true
		end
	end
	return false
end

local function night(): boolean
	return WorldClock.isNight(Config.World.clock, os.time() - IncidentService.clockStart)
end

---------------------------------------------------------------------------
-- Building each step
---------------------------------------------------------------------------

local function fireProps(inc: Live, at: Vector3)
	local m = SiteKit.model("Blaze")
	local p = SiteKit.part(
		m,
		Vector3.new(3, 1, 3),
		CFrame.new(at - Vector3.new(0, 1.5, 0)),
		Color3.fromRGB(80, 70, 66)
	)
	p.Transparency = 1
	local fire = Instance.new("Fire")
	fire.Size = 9
	fire.Heat = 12
	fire.Parent = p
	local smoke = Instance.new("Smoke")
	smoke.Size = 6
	smoke.RiseVelocity = 6
	smoke.Opacity = 0.25
	smoke.Color = Color3.fromRGB(80, 80, 84)
	smoke.Parent = p
	table.insert(inc.things, m)
end

local function tramModel(m: Model)
	local body = Color3.fromRGB(240, 196, 60)
	SiteKit.part(m, Vector3.new(9, 6, 34), CFrame.new(0, 4, 0), body)
	SiteKit.part(
		m,
		Vector3.new(9.2, 3, 33),
		CFrame.new(0, 6.5, 0),
		Color3.fromRGB(150, 200, 230),
		Enum.Material.Glass
	)
	SiteKit.part(m, Vector3.new(6, 0.8, 30), CFrame.new(0, 10, 0), Color3.fromRGB(60, 60, 70))
	SiteKit.part(m, Vector3.new(0.4, 4, 0.4), CFrame.new(0, 12, -6), Color3.fromRGB(40, 40, 48))
end

local function relayModel(m: Model)
	SiteKit.part(m, Vector3.new(4, 2, 4), CFrame.new(0, 1, 0), Color3.fromRGB(60, 70, 90))
	SiteKit.part(
		m,
		Vector3.new(1, 18, 1),
		CFrame.new(0, 10, 0),
		Color3.fromRGB(150, 160, 175),
		Enum.Material.Metal
	)
	local dish = SiteKit.part(
		m,
		Vector3.new(0.6, 7, 7),
		CFrame.new(0, 17, 0) * CFrame.Angles(0, 0, math.rad(60)),
		Color3.fromRGB(220, 230, 240),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	dish.Name = "Dish"
	SiteKit.part(
		m,
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(0, 19.5, 0),
		Color3.fromRGB(80, 160, 255),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
end

local function propAt(inc: Live, kind: string)
	local p = inc.pos
	local m = SiteKit.model(kind)
	if kind == "Vault" then
		SiteKit.part(
			m,
			Vector3.new(14, 12, 4),
			CFrame.new(p + Vector3.new(0, 6, 8)),
			Color3.fromRGB(110, 115, 125),
			Enum.Material.Metal
		)
		local door = SiteKit.part(
			m,
			Vector3.new(1.2, 9, 9),
			CFrame.new(p + Vector3.new(0, 6, 5.6)) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(200, 170, 80),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		door.Name = "Door"
	elseif kind == "Crate" then
		SiteKit.part(
			m,
			Vector3.new(6, 5, 6),
			CFrame.new(p + Vector3.new(0, 2.5, 0)),
			Color3.fromRGB(70, 60, 110),
			Enum.Material.Metal
		)
		SiteKit.part(
			m,
			Vector3.new(6.2, 1, 6.2),
			CFrame.new(p + Vector3.new(0, 4, 0)),
			Color3.fromRGB(150, 120, 255),
			Enum.Material.Neon
		)
	end
	table.insert(inc.things, m)
end

local function valveModel(m: Model)
	-- PLACEHOLDER ART: a burst pipe and its valve wheel with a column of spray
	SiteKit.part(
		m,
		Vector3.new(3, 3, 3),
		CFrame.new(0, 1.5, 0),
		Color3.fromRGB(90, 96, 104),
		Enum.Material.Metal
	)
	SiteKit.part(
		m,
		Vector3.new(0.6, 4, 4),
		CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(220, 60, 50),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	local spray = SiteKit.part(
		m,
		Vector3.new(2.4, 16, 2.4),
		CFrame.new(1.5, 9, 0),
		Color3.fromRGB(120, 190, 255),
		Enum.Material.Glass,
		Enum.PartType.Block
	)
	spray.Name = "Spray"
	spray.Transparency = 0.45
end

local OBJECT_MODELS: { [string]: (Model) -> () } = {
	Tram = tramModel,
	Relay = relayModel,
	Valve = valveModel,
}

-- PLACEHOLDER ART: what a hold step stands under (a scaffold frame, a swinging crate, a pile of crates)
local function holdProp(inc: Live, kind: string, at: Vector3)
	local m = SiteKit.model(kind)
	if kind == "Scaffold" then
		for _, o in { { -5, -5 }, { 5, -5 }, { -5, 5 }, { 5, 5 } } do
			SiteKit.part(
				m,
				Vector3.new(0.6, 22, 0.6),
				CFrame.new(at + Vector3.new(o[1], 11, o[2])) * CFrame.Angles(math.rad(o[1] * 0.8), 0, 0),
				Color3.fromRGB(200, 170, 70),
				Enum.Material.Metal
			)
		end
		for h = 1, 3 do
			SiteKit.part(
				m,
				Vector3.new(11, 0.5, 11),
				CFrame.new(at + Vector3.new(0, h * 7, 0)) * CFrame.Angles(math.rad(6 * h), 0, 0),
				Color3.fromRGB(150, 120, 80),
				Enum.Material.WoodPlanks
			)
		end
	elseif kind == "Load" then
		SiteKit.part(
			m,
			Vector3.new(0.3, 30, 0.3),
			CFrame.new(at + Vector3.new(0, 34, 0)),
			Color3.fromRGB(40, 40, 46),
			Enum.Material.Metal
		)
		SiteKit.part(
			m,
			Vector3.new(7, 5, 7),
			CFrame.new(at + Vector3.new(0, 16, 0)) * CFrame.Angles(math.rad(12), 0, math.rad(8)),
			Color3.fromRGB(70, 120, 180),
			Enum.Material.Metal
		)
	elseif kind == "Crates" then
		for i = 0, 3 do
			SiteKit.part(
				m,
				Vector3.new(4, 4, 4),
				CFrame.new(at + Vector3.new(-6 + i * 4.2, 2, 6)),
				Color3.fromRGB(150, 110, 60),
				Enum.Material.WoodPlanks
			)
		end
	end
	table.insert(inc.things, m)
end

-- The towed car: the hub's sedan look in red (Art.Vehicles) over its two boxes once imported; the boxes before
local TOWED_TINT = { CarSedanBody = { 200, 70, 60 } }
local function carModel(m: Model)
	local body = SiteKit.part(
		m,
		Vector3.new(6, 3, 11),
		CFrame.new(0, 2, 0),
		Color3.fromRGB(200, 70, 60),
		Enum.Material.Metal
	)
	local glass = SiteKit.part(
		m,
		Vector3.new(5.6, 2.2, 6),
		CFrame.new(0, 4.4, 0.5),
		Color3.fromRGB(150, 200, 230),
		Enum.Material.Glass
	)
	if SetPieceMeshes.ready("CarSedan") then
		SetPieceMeshes.hide(body)
		SetPieceMeshes.hide(glass)
		SetPieceMeshes.add(
			m,
			{ look = "CarSedan", x = 0, y = 0, z = 0, ry = 0, tint = TOWED_TINT },
			CFrame.new()
		)
	end
end

-- A step's big moment: a toast line and its juice action for the heroes near it (Config.Incidents.beats)
local function beat(key: string, at: Vector3)
	if not IC.beats[key] then
		return
	end
	for _, h in SiteKit.heroesIn(at, IC.beatRadius) do
		if h.player then
			Net.fire("Toast", h.player, { id = "beat", beat = key, x = at.X, y = at.Y, z = at.Z })
		end
	end
end

local function robotLevel(inc: Live): number
	return HeroicRules.robotLevel(Config, inc.plan.level, inc.plan.heroic)
end

-- Spawn a squad for the incident; target: these count for the current step
local function squad(inc: Live, rows: { any }, at: Vector3, ring: number, target: boolean): { number }
	local ids = SiteKit.squad(rows, at, robotLevel(inc), inc.id, ring)
	for _, id in ids do
		inc.enemies[id] = true
		byEnemy[id] = inc.id
		if target then
			inc.targets[id] = true
		end
		table.insert(inc.things, id)
	end
	return ids
end

-- A street route of Vector3 points from (x, z): legs of `leg` studs over open ground
local function route(x: number, z: number, legs: number, leg: number): ({ Vector3 }, number)
	local pts = IncidentSpots.streetPath(Config, CityBuilder.world, x, z, legs, leg, rng)
	local path, length = {}, 0
	for i, p in pts do
		table.insert(path, Vector3.new(p[1], Config.City.ground.y + 0.5, p[3]))
		if i > 1 then
			length += (path[i] - path[i - 1]).Magnitude
		end
	end
	return path, length
end

-- The point `d` studs along a path, and the yaw facing along it
local function along(path: { Vector3 }, d: number): (Vector3, number)
	local left = math.max(0, d)
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local seg = (b - a).Magnitude
		if left <= seg then
			return a:Lerp(b, left / math.max(seg, 1e-3)), math.atan2(-(b.X - a.X), -(b.Z - a.Z))
		end
		left -= seg
	end
	return path[#path], 0
end

local function endStep(inc: Live)
	if inc.tug then
		-- the driver waits by the car where it stopped
		inc.focus = inc.tug.car:GetPivot().Position
		inc.tug.rope.Transparency = 1 -- the cable snaps
		inc.tug = nil
	end
	if inc.stepPos and next(inc.stepThings) then
		CitizenService.danger(inc.stepPos.X, inc.stepPos.Z, 30, 4) -- the crowd runs off
	end
	SiteKit.clear(inc.stepThings)
	table.clear(inc.targets)
	inc.convoy = nil
	inc.barrage = nil
	inc.retry = nil
end

-- A fight step that got no robots at all (the server cap): its goal comes when there is room, instead of
-- the step waiting with nothing to beat until the deadline fails it (2026-11-18 fix)
local function retryLater(inc: Live, rows: { any }, at: Vector3, ring: number)
	inc.retry = { rows = rows, at = at, ring = ring, nextAt = os.clock() + IC.capRetry }
end

---------------------------------------------------------------------------
-- WP5: the Suspicious Hero (gap G13). A costumed fake (Config.Incidents.dress over a fake's suit) poses in
-- a crowd until someone hits it; at the fakes' 50% crack its mask goes (the unmask step). Then the Vigil
-- scraps it (a defeat row with `keep`) and the Syndicate holds the square while the panic spreads (a hold
-- row with `panic`). Kept in these functions so the step code above stays as it was.
---------------------------------------------------------------------------

-- Put the fake out (false: the server cap or no costume; the step tries again)
local function spawnFake(inc: Live, row: any, at: Vector3): boolean
	local ids = IncidentPlan.dresses(Config, row, inc.plan.level)
	if #ids == 0 then
		return false
	end
	local dressId = ids[rng:int(1, #ids)]
	local id = EnemyService.spawnAt(IC.dress[dressId].suit, at, robotLevel(inc), inc.id, true)
	if not id then
		return false
	end
	if not EnemyService.dress(id, dressId) then
		EnemyService.remove(id) -- never a famous fake's own look out in the street
		return false
	end
	EnemyService.tune(id, { hpMult = row.hpMult, dmgMult = row.dmgMult })
	inc.enemies[id] = true
	byEnemy[id] = inc.id
	inc.targets[id] = true
	table.insert(inc.things, id)
	local f = inc.fake :: any
	f.id = id
	return true
end

-- The unmask step's crowd and fake, or the keep step's target (the same fake)
local function startFake(inc: Live, step: IncidentPlan.Step, here: Vector3)
	local row = step.def
	if row.keep then
		local id = inc.fake and inc.fake.id
		if id and not EnemyService.gone(id) then
			inc.targets[id] = true
			step.need = 1
		else
			-- it fell with the blow that cracked it: nothing left to scrap
			IncidentPlan.advance(inc.plan, step.kind, step.need)
		end
		return
	end
	for i = 1, row.crowd or 6 do
		local a = i / (row.crowd or 6) * math.pi * 2 + rng:range(-0.3, 0.3)
		local r = rng:range(5, 11)
		table.insert(
			inc.stepThings,
			SiteKit.bystander(Vector3.new(here.X + math.cos(a) * r, here.Y, here.Z + math.sin(a) * r))
		)
	end
	inc.fake = { id = nil, by = nil, retryAt = 0, at = here, awake = false, cracked = false }
	if not spawnFake(inc, row, here) then
		(inc.fake :: any).retryAt = os.clock() + IC.capRetry
	end
end

-- The mask cracked (or the fake fell before the crack was seen): the step is done, the crowd runs
local function fakeCracked(inc: Live, at: Vector3)
	local f = inc.fake
	if not f or f.cracked then
		return
	end
	f.cracked = true
	IncidentPlan.advance(inc.plan, "unmask", 1)
	beat("fakeCracked", at)
	CitizenService.danger(at.X, at.Z, 40, 5)
	IncidentService.FakeUnmasked:Fire(inc, f.by)
end

-- Each tick of the unmask step: the spawn retry, and the crack (EnemySim marks it unmasked)
local function stepFake(inc: Live, now: number)
	local f = inc.fake
	if not f then
		return
	end
	if not f.id then
		if now >= f.retryAt and not spawnFake(inc, (IncidentPlan.current(inc.plan) :: any).def, f.at) then
			f.retryAt = now + IC.capRetry
		end
		return
	end
	local e = EnemyService.get(f.id)
	if e and e.unmasked then
		fakeCracked(inc, Vector3.new(e.x, e.y, e.z))
	end
end

-- A hit on the fake: it stops posing and fights back; the hitter is who cracked it
local function fakeHit(inc: Live, enemyId: number, heroId: number?)
	local f = inc.fake
	if not f or f.id ~= enemyId then
		return
	end
	f.by = heroId or f.by
	if not f.awake then
		f.awake = true
		local e = EnemyService.get(enemyId)
		if e then
			e.scripted = false
		end
	end
end

-- The fake fell: in the unmask step that is the crack too; in the keep step the fake is scrapped
local function fakeFell(inc: Live, step: IncidentPlan.Step, by: number?, pos: Vector3)
	local f = inc.fake :: any
	f.by = by or f.by
	if step.kind == "unmask" then
		fakeCracked(inc, pos)
	elseif step.kind == "defeat" and IncidentPlan.advance(inc.plan, "defeat", 1) then
		beat("fakeScrapped", pos)
	end
end

-- The Syndicate's hold: the crowd scatters again every few seconds while the square is held
local function panicWave(inc: Live, step: IncidentPlan.Step, now: number)
	local at = inc.stepPos or inc.pos
	if inc.panicAt == nil then
		beat("panicSpread", at)
	elseif now < inc.panicAt then
		return
	end
	inc.panicAt = now + step.def.panic
	CitizenService.danger(at.X, at.Z, 45, 3)
end

local function startStep(inc: Live)
	local step = IncidentPlan.current(inc.plan)
	if not step then
		return
	end
	if inc.builtStep > 0 then
		endStep(inc)
	end
	inc.stepStarted = os.clock()
	inc.builtStep = inc.plan.step
	local level = inc.plan.level
	local row = step.def
	local tid = inc.plan.tid
	local sx, sy, sz = IncidentSpots.stepAt(Config, CityBuilder.world, inc.spot, row.at, rng)
	local here = Vector3.new(sx, sy, sz)
	inc.stepPos = here
	if step.kind == "unmask" or row.keep then
		startFake(inc, step, here) -- WP5
	elseif step.kind == "defeat" or step.kind == "nest" then
		local ring = if tid == "ShardCrate" then 10 else 16
		if step.kind == "nest" then
			-- up on the roof: the ring fits inside it
			local b = inc.spot.building and CityBuilder.world.buildings[inc.spot.building]
			ring = if b then math.clamp(math.min(b.sx, b.sz) / 2 - 6, 4, 12) else 8
		end
		local ids = squad(inc, step.spawn :: any, here, ring, true)
		-- the server cap may spawn fewer, a Swarmer brings its pack: every robot there counts
		step.need = math.max(1, #ids)
		if #ids == 0 then
			retryLater(inc, step.spawn :: any, here, ring)
		end
		if tid == "VaultBreach" then
			propAt(inc, "Vault")
		elseif tid == "ShardCrate" then
			propAt(inc, "Crate")
		end
	elseif step.kind == "leader" then
		local lead = squad(inc, { { kind = step.leader :: string, n = 1 } }, here, 6, true)
		local escort = squad(inc, step.spawn :: any, here, 16, false)
		if #lead > 0 then
			inc.leaderId = lead[1]
			-- a Captain's own company is part of the warband, not the goal
			for i = 2, #lead do
				inc.targets[lead[i]] = nil
			end
		else
			-- no leader could spawn (the server cap): the warband itself is the goal
			for _, id in escort do
				inc.targets[id] = true
			end
			step.need = math.max(1, #escort)
			if #escort == 0 then
				-- nobody came at all: the leader and the warband try again, every robot the goal
				local rows = { { kind = step.leader :: string, n = 1 } }
				for _, r in step.spawn :: any do
					table.insert(rows, r)
				end
				retryLater(inc, rows, here, 16)
			end
		end
	elseif step.kind == "find" then
		-- the crowd: citizens standing about, the Mimic among them looking just like one
		for i = 1, row.crowd or 5 do
			local a = i / (row.crowd or 5) * math.pi * 2 + rng:range(-0.3, 0.3)
			local r = rng:range(4, 11)
			local at = Vector3.new(here.X + math.cos(a) * r, here.Y, here.Z + math.sin(a) * r)
			table.insert(inc.stepThings, SiteKit.bystander(at))
		end
		local ids = squad(inc, step.spawn :: any, here, 7, true)
		step.need = math.max(1, #ids)
		if #ids == 0 then
			retryLater(inc, step.spawn :: any, here, 7)
		end
	elseif step.kind == "convoy" then
		local path, length = route(here.X, here.Z, row.legs or 6, IC.convoyLeg)
		local spec = (step.spawn :: any)[1]
		local ids = {}
		for i = 1, spec.n do
			local at = along(path, -(i - 1) * IC.convoyGap)
			local id = EnemyService.spawnAt(spec.kind, at, robotLevel(inc), inc.id, true)
			if id then
				inc.enemies[id] = true
				inc.targets[id] = true
				byEnemy[id] = inc.id
				table.insert(inc.things, id)
				table.insert(ids, id)
			end
		end
		step.need = math.max(1, #ids)
		if #ids == 0 or length < 40 then
			inc.plan.failed = true
			return
		end
		-- the squad it is heading for waits at the end of the route (the next step's robots)
		inc.convoy = { ids = ids, path = path, length = length, travelled = 0 }
		local goal = SiteKit.ring(path[#path], 8, Color3.fromRGB(120, 255, 170))
		table.insert(inc.stepThings, goal)
		inc.spot.x, inc.spot.z = path[#path].X, path[#path].Z
	elseif step.kind == "barrage" then
		local huddles = {}
		for i = 1, row.huddles or 3 do
			local a = i / (row.huddles or 3) * math.pi * 2
			local hx, hy, hz = IncidentSpots.groundNear(
				Config,
				CityBuilder.world,
				here.X + math.cos(a) * 16,
				here.Z + math.sin(a) * 16,
				8,
				rng
			)
			local at = Vector3.new(hx, hy, hz)
			table.insert(huddles, at)
			for k = 1, 2 do
				table.insert(inc.stepThings, SiteKit.bystander(at + Vector3.new(k * 2 - 3, 0, 0)))
			end
		end
		squad(inc, step.spawn :: any, here, 42, true)
		if next(inc.targets) == nil then
			IncidentPlan.endBarrage(inc.plan) -- no Bombers could come: nothing to shield from
			return
		end
		inc.barrage = { huddles = huddles, nextAt = os.clock() + 2, shell = nil }
		CitizenService.danger(here.X, here.Z, 50, IC.templates[tid].time)
	elseif step.kind == "tug" then
		local path, length = route(here.X, here.Z, 4, row.dist / 3)
		local car = SiteKit.prop("TowedCar", carModel)
		SiteKit.place(car, path[1])
		table.insert(inc.things, car) -- the car stays for the driver's rescue
		local rope = SiteKit.part(
			car,
			Vector3.new(0.3, 0.3, 1),
			CFrame.new(path[1]),
			Color3.fromRGB(60, 60, 66),
			Enum.Material.Metal
		)
		rope.Name = "Cable"
		local ahead = along(path, 14)
		local ids = squad(inc, step.spawn :: any, ahead, 3, true)
		step.need = math.max(1, #ids)
		if #ids == 0 or length < 30 then
			inc.plan.failed = true
			return
		end
		inc.tug = { car = car, rope = rope, path = path, length = math.min(length, row.dist), moved = 0 }
	elseif step.kind == "rescue" then
		local spot = inc.spot
		local points = spot.points or { { inc.pos.X, inc.pos.Y, inc.pos.Z } }
		if inc.focus and not (spot.kind == "tower") then
			points = { { inc.focus.X, inc.focus.Y, inc.focus.Z } }
		end
		local cx, cz = spot.x, spot.z
		if inc.focus then
			cx, cz = inc.focus.X, inc.focus.Z
		end
		local px, py, pz = IncidentSpots.groundNear(Config, CityBuilder.world, cx, cz, 50, rng)
		if spot.kind == "tower" then
			local b = CityBuilder.world.buildings[spot.building :: number]
			px, py, pz =
				IncidentSpots.groundNear(Config, CityBuilder.world, b.x + b.sx / 2 + 14, b.z, 40, rng)
		end
		local pad = SiteKit.pad(Vector3.new(px, py - 0.5, pz), "Rescue")
		table.insert(inc.things, pad)
		for i = 1, step.need do
			local pt = points[(i - 1) % #points + 1]
			local at = Vector3.new(pt[1], pt[2], pt[3])
			if spot.kind == "tower" then
				if tid == "TowerFire" then
					fireProps(inc, at + Vector3.new(0, 4, 0))
				end
				-- a ledge to stand on
				local ledge = SiteKit.model("Balcony")
				SiteKit.part(
					ledge,
					Vector3.new(6, 0.6, 6),
					CFrame.new(at - Vector3.new(0, 0.3, 0)),
					Color3.fromRGB(150, 150, 160)
				)
				table.insert(inc.things, ledge)
			end
			local c = SiteKit.citizen(at, {
				cat = row.cat,
				pads = { pad },
				onPick = function(hero)
					inc.helpers[hero.id] = true
				end,
				onSafe = function(hero)
					inc.helpers[hero.id] = true
					if hero.player then
						EconomyService.reward(hero.player, "rescue", level)
						local profile = DataService.get(hero.player)
						if profile then
							profile.stats.rescues += 1
						end
					end
					IncidentService.Rescued:Fire(hero)
					IncidentPlan.advance(inc.plan, "rescue", 1)
				end,
			})
			table.insert(inc.things, c)
		end
		CitizenService.danger(inc.pos.X, inc.pos.Z, 60, IC.templates[tid].time)
	elseif step.kind == "hold" then
		local radius = row.radius or 10
		inc.ring = SiteKit.ring(here, radius)
		table.insert(inc.things, inc.ring :: Model)
		if row.prop then
			holdProp(inc, row.prop, here)
		end
		if tid == "FallingSign" then
			local top = (inc.spot.points :: any)[1]
			local dir = inc.spot.dir :: any
			local m = SiteKit.model("Billboard")
			local face = CFrame.lookAt(
				Vector3.new(top[1], top[2], top[3]),
				Vector3.new(top[1] + dir[1], top[2], top[3] + dir[2])
			)
			SiteKit.part(
				m,
				Vector3.new(16, 8, 0.6),
				face * CFrame.new(0, 0, -1) * CFrame.Angles(math.rad(-20), 0, 0),
				Color3.fromRGB(240, 90, 90)
			)
			SiteKit.part(
				m,
				Vector3.new(14, 6, 0.7),
				face * CFrame.new(0, 0, -1.1) * CFrame.Angles(math.rad(-20), 0, 0),
				Color3.fromRGB(255, 230, 120),
				Enum.Material.Neon
			)
			inc.sign = m
			table.insert(inc.things, m)
			CitizenService.danger(inc.pos.X, inc.pos.Z, 30, IC.templates[tid].time)
		end
	elseif step.kind == "object" then
		local hp = IncidentPlan.objectHp(Config, row.hits, robotLevel(inc))
		local isTram = tid == "RunawayTram"
		local pos = if isTram then Vector3.new(inc.spot.x, inc.spot.y, inc.spot.z) else here
		local yaw = if isTram then math.rad(90) else 0
		inc.object = SiteKit.object(
			row.label or "Object",
			pos,
			if isTram then 5 else 8,
			if isTram then 9 else 5,
			hp,
			OBJECT_MODELS[row.label or ""] or relayModel,
			function(heroId)
				if heroId then
					inc.helpers[heroId] = true
				end
			end,
			function(heroId)
				if heroId then
					inc.helpers[heroId] = true
				end
				IncidentPlan.advance(inc.plan, "object", 1)
			end
		)
		SiteKit.moveObject(inc.object, pos, yaw)
		table.insert(inc.things, inc.object)
	elseif step.kind == "runner" then
		local path = inc.spot.points :: any
		local p0 = path[1]
		local id =
			EnemyService.spawnAt(row.enemy, Vector3.new(p0[1], p0[2], p0[3]), robotLevel(inc), inc.id, true)
		if id then
			inc.enemies[id] = true
			inc.targets[id] = true
			byEnemy[id] = inc.id
			table.insert(inc.things, id)
			inc.runner = { id = id, idx = 1, t = 0 }
		else
			inc.plan.failed = true
		end
	end
end

---------------------------------------------------------------------------
-- Life of an incident
---------------------------------------------------------------------------

local function findSpot(t: any, pos: Vector3, minD: number, maxD: number): IncidentSpots.Spot?
	return IncidentSpots.find(Config, CityBuilder.world, t.where, pos.X, pos.Z, minD, maxD, rng, {
		hops = t.steps[1].hops,
		run = (t.steps[1].moving or 7) * t.time * 0.95,
	})
end

local function newLive(hero: any, tid: string, spot: IncidentSpots.Spot, level: number, heroic: boolean): Live
	nextId += 1
	local at = Vector3.new(spot.x, spot.y, spot.z)
	return {
		id = nextId,
		owner = hero.id,
		side = hero.side,
		plan = IncidentPlan.new(
			IC,
			rng,
			tid,
			level,
			os.clock(),
			{ config = Config, heroic = heroic, side = hero.side }
		),
		pos = at,
		spot = spot,
		things = {},
		enemies = {},
		helpers = {},
		known = {},
		lastNear = os.clock(),
		stepStarted = os.clock(),
		builtStep = 0,
		targets = {},
		stepThings = {},
	}
end

local function spawnFor(hero: any, pos: Vector3): boolean
	local hm = meta[hero.id] or { next = 0, last = nil }
	meta[hero.id] = hm
	local world = CityBuilder.world
	local valid = IncidentSpots.kinds(Config, world, pos.X, pos.Z, S.radius)
	local here = ZoneLevel.at(Config, pos.X, pos.Z, hero.level, world.tiles)
	local tid = IncidentPlan.pick(
		IC,
		rng,
		hero.side,
		valid,
		hm.last,
		night(),
		IncidentService.prep,
		Config.World.clock.nightVillain,
		Config,
		here
	)
	if not tid then
		return false
	end
	local t = IC.templates[tid]
	local spot = findSpot(t, pos, S.minDistance, S.radius)
	if not spot then
		return false
	end
	if tooClose(spot.x, spot.z) then
		return false
	end
	local level = ZoneLevel.at(Config, spot.x, spot.z, hero.level, world.tiles)
	-- the site's own level must still have its robots (a zone edge between two floors)
	if not IncidentPlan.available(IC, Config, tid, level) then
		return false
	end
	local heroic = IncidentPlan.canHeroic(IC, tid) and HeroicRules.roll(Config, "incident", hero.level, rng)
	local inc = newLive(hero, tid, spot, level, heroic)
	live[inc.id] = inc
	hm.last = tid
	startStep(inc)
	if heroic then
		beat("heroic", inc.pos)
	end
	return true
end

local function wire(inc: Live, now: number, state: number): { number }
	local step = IncidentPlan.current(inc.plan)
	return {
		inc.id,
		math.floor(IncidentPlan.fraction(inc.plan) * 1000),
		inc.plan.step,
		if step then math.floor(step.have * 10) / 10 else 0,
		if step then step.need else 0,
		math.max(0, math.floor(inc.plan.deadline - now)),
		state,
		MEDAL[inc.medal or ""] or 0,
	}
end

local function spawnPacket(inc: Live, player: Player, now: number): { [string]: any }
	local hero = HeroService.get(player)
	return {
		id = inc.id,
		num = inc.plan.num,
		x = inc.pos.X,
		y = inc.pos.Y,
		z = inc.pos.Z,
		side = if inc.side == "villain" then 2 else 1,
		level = inc.plan.level,
		left = math.max(0, inc.plan.deadline - now),
		own = if hero and hero.id == inc.owner then 1 else 0,
		steps = #inc.plan.steps,
		kind = inc.spot.kind,
		heroic = if inc.plan.heroic then 1 else 0,
	}
end

-- The clear's Credits and Renown: the Economy "incident" row with the usual bonuses, then Heroic x1.5
local function payClear(player: Player, inc: Live)
	local credits, renown = Progress.earn(Config, "incident", inc.plan.level, EconomyService.bonus(player))
	credits, renown = HeroicRules.pay(Config, credits, renown, inc.plan.heroic)
	EconomyService.addCredits(player, credits)
	EconomyService.addRenown(player, renown)
	Net.fire("Toast", player, { id = "reward", credits = credits, renown = renown, action = "incident" })
	EconomyService.Earned:Fire(player, "incident")
end

local function finish(inc: Live, ok: boolean, now: number)
	inc.ended = now
	if ok then
		inc.medal = IncidentPlan.medal(IC, inc.plan, now)
		if IncidentService.share then
			IncidentService.share(inc.helpers, inc.pos)
		end
		for heroId in inc.helpers do
			local hero = HeroService.byId(heroId)
			if hero and hero.player then
				payClear(hero.player, inc)
				GearService.grant(
					hero.player,
					"incident",
					HeroicRules.gearLevel(Config, inc.plan.level, inc.plan.heroic)
				)
				local name = IncidentPlan.title(IC, inc.plan.tid, hero.side)
				Net.fire(
					"Toast",
					hero.player,
					{ id = "incident", name = name, medal = inc.medal, heroic = inc.plan.heroic or nil }
				)
			end
		end
		IncidentService.Cleared:Fire(inc)
	else
		if inc.sign then
			-- the billboard drops into the empty street (the citizens already ran)
			for _, p in inc.sign:GetDescendants() do
				if p:IsA("BasePart") then
					TweenService
						:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							CFrame = CFrame.new(inc.pos + Vector3.new(0, 0.5, 0))
								* CFrame.Angles(math.rad(90), 0, 0),
						})
						:Play()
				end
			end
		end
		if inc.object and inc.plan.tid == "RunawayTram" then
			CitizenService.danger(inc.object.pos.X, inc.object.pos.Z, 40, 6)
		end
	end
	for id in inc.enemies do
		byEnemy[id] = nil
	end
	local owner = meta[inc.owner]
	if owner then
		owner.next = now + rng:range(S.refill[1], S.refill[2])
	end
	local things, stepThings = inc.things, inc.stepThings
	task.delay(if ok then 2 else 3, function()
		SiteKit.clear(stepThings)
		SiteKit.clear(things)
	end)
end

-- Convoy robots drive their route; one reaching the end with the others is a fail
local function stepConvoy(inc: Live, dt: number)
	local c = inc.convoy :: any
	local lead = c.ids[1] and EnemyService.get(c.ids[1])
	local at = if lead then Vector3.new(lead.x, lead.y, lead.z) else c.path[1]
	local spotted = #SiteKit.heroesIn(at, 120) > 0
	local step = IncidentPlan.current(inc.plan) :: any
	c.travelled += step.def.speed * (if spotted then 1 else IC.convoyWait) * dt
	for i, id in c.ids do
		if EnemyService.alive(id) then
			local d = c.travelled - (i - 1) * IC.convoyGap
			if d >= c.length then
				inc.plan.failed = true -- a Medic Unit got through
				return
			end
			EnemyService.place(id, (along(c.path, d)))
		end
	end
end

-- The car follows the Grappler's haul while it lives
local function stepTug(inc: Live, dt: number)
	local t = inc.tug :: any
	local step = IncidentPlan.current(inc.plan) :: any
	t.moved += step.def.speed * dt
	local pos, yaw = along(t.path, t.moved)
	SiteKit.place(t.car, pos, yaw)
	-- the cable from the car to the nearest Grappler
	local best: Vector3? = nil
	for id in inc.targets do
		local e = EnemyService.get(id)
		if e and e.alive then
			best = Vector3.new(e.x, e.y, e.z)
			break
		end
	end
	if best then
		local from = pos + Vector3.new(0, 2.5, 0)
		local len = (best - from).Magnitude
		t.rope.Size = Vector3.new(0.3, 0.3, math.max(1, len))
		t.rope.CFrame = CFrame.lookAt(from:Lerp(best, 0.5), best)
	end
	if t.moved >= t.length then
		inc.plan.failed = true -- the car is gone
	end
end

-- Shells fall on the huddles in turn: a red ring first, then the landing
local function stepBarrage(inc: Live, now: number)
	local b = inc.barrage :: any
	local row = (IncidentPlan.current(inc.plan) :: any).def
	if b.shell then
		if now >= b.shell.lands then
			local at = b.shell.at
			b.shell.ring:Destroy()
			b.shell = nil
			local guards = SiteKit.heroesIn(at, row.cover + 3)
			for _, h in guards do
				inc.helpers[h.id] = true
			end
			local blocked = #guards > 0
			local r = IncidentPlan.shell(inc.plan, blocked)
			if blocked then
				beat(if r == "done" or r == "step" then "barrageOver" else "shellBlocked", at)
			else
				beat("shellMissed", at)
				CitizenService.danger(at.X, at.Z, 30, 6)
			end
			b.nextAt = now + row.every
		end
	elseif now >= b.nextAt then
		local at = b.huddles[rng:int(1, #b.huddles)]
		local ring = SiteKit.ring(at, row.cover, Color3.fromRGB(255, 70, 60))
		table.insert(inc.stepThings, ring)
		b.shell = { at = at, lands = now + row.warn, ring = ring }
	end
end

local function stepIncident(inc: Live, now: number, dt: number)
	local plan = inc.plan
	if inc.ended then
		return
	end
	if plan.done then
		finish(inc, true, now)
		return
	end
	if plan.failed or IncidentPlan.expired(plan, now) then
		plan.failed = true
		finish(inc, false, now)
		return
	end
	local step = IncidentPlan.current(plan)
	if not step then
		return
	end
	-- the next step began since the last tick: build it
	if inc.builtStep ~= plan.step then
		startStep(inc)
		step = IncidentPlan.current(plan)
		if not step or plan.failed or plan.done then
			return
		end
	end
	local rt = inc.retry
	if rt and now >= rt.nextAt then
		local ids = squad(inc, rt.rows, rt.at, rt.ring, true)
		if #ids > 0 then
			inc.retry = nil
			step.need = #ids
		else
			rt.nextAt = now + IC.capRetry
		end
	end
	if step.kind == "unmask" then
		stepFake(inc, now) -- WP5
	elseif step.kind == "hold" then
		if step.def.panic then
			panicWave(inc, step, now) -- WP5
		end
		local radius = step.def.radius or 10
		local inRing = SiteKit.heroesIn(inc.stepPos or inc.pos, radius + 3)
		for _, h in inRing do
			inc.helpers[h.id] = true
		end
		IncidentPlan.advance(plan, "hold", IncidentPlan.holdRate(IC, #inRing) * dt)
	elseif step.kind == "object" and step.def.moving and inc.object then
		local dir = inc.spot.dir :: any
		local o = inc.object
		local start = Vector3.new(inc.spot.x, inc.spot.y, inc.spot.z)
		-- slows as it takes damage: brake it to a stop
		local speed = step.def.moving * (0.35 + 0.65 * (o.hp / o.maxHp))
		local nextPos = o.pos + Vector3.new(dir[1], 0, dir[2]) * speed * dt
		SiteKit.moveObject(o, nextPos, math.rad(90))
		if (nextPos - start).Magnitude >= dir[3] then
			plan.failed = true
		end
	elseif step.kind == "convoy" and inc.convoy then
		stepConvoy(inc, dt)
	elseif step.kind == "tug" and inc.tug then
		stepTug(inc, dt)
	elseif step.kind == "barrage" and inc.barrage then
		stepBarrage(inc, now)
	elseif step.kind == "runner" and inc.runner then
		local r = inc.runner
		local path = inc.spot.points :: any
		if not EnemyService.alive(r.id) then
			return
		end
		local e = EnemyService.get(r.id)
		local a, b = path[r.idx], path[r.idx + 1]
		if not b then
			plan.failed = true -- it got away
			return
		end
		local from = Vector3.new(a[1], a[2], a[3])
		local to = Vector3.new(b[1], b[2], b[3])
		local seg = (to - from).Magnitude
		-- it waits for the chasers a little: slow while nobody is close
		local chasers = SiteKit.heroesIn(Vector3.new(e.x, e.y, e.z), 120)
		local speed = step.def.speed * (if #chasers > 0 then 1 else 0.3)
		r.t += speed * dt / math.max(seg, 1)
		if r.t >= 1 then
			r.t = 0
			r.idx += 1
		else
			local p = from:Lerp(to, r.t)
			EnemyService.place(r.id, p)
		end
	end
end

-- Robots beaten: count the ones that are the current step's goal
local function onKilled(_kind: string, by: number?, pos: Vector3, enemyId: number?)
	local incId = enemyId and byEnemy[enemyId]
	local inc = incId and live[incId]
	if not inc then
		return
	end
	local id = enemyId :: number
	byEnemy[id] = nil
	inc.enemies[id] = nil
	if by then
		inc.helpers[by] = true
	end
	local step = IncidentPlan.current(inc.plan)
	if not step or not inc.targets[id] then
		return
	end
	inc.targets[id] = nil
	local k = step.kind
	if inc.fake and id == inc.fake.id then
		fakeFell(inc, step, by, pos) -- WP5
	elseif k == "leader" then
		if inc.leaderId == nil or id == inc.leaderId then
			if IncidentPlan.advance(inc.plan, "leader", 1) and inc.leaderId then
				beat("leaderDown", pos)
			end
		end
	elseif k == "barrage" then
		-- every Bomber down: the shelling stops
		if next(inc.targets) == nil and IncidentPlan.endBarrage(inc.plan) then
			beat("barrageOver", pos)
		end
	else
		local r = IncidentPlan.advance(inc.plan, k, 1)
		if k == "find" then
			beat("found", pos)
			CitizenService.danger(pos.X, pos.Z, 40, 5)
		elseif r and k == "nest" then
			beat("nestCleared", pos)
		elseif r and k == "convoy" then
			beat("convoyStopped", pos)
		elseif r and k == "tug" then
			beat("towStopped", pos)
		end
	end
end

-- Any hit on an incident's robots marks the attacker as a helper
local function onHit(enemyId: number, heroId: number?)
	local incId = byEnemy[enemyId]
	local inc = incId and live[incId]
	if inc and heroId then
		inc.helpers[heroId] = true
	end
	if inc and inc.fake then
		fakeHit(inc, enemyId, heroId) -- WP5
	end
end

function IncidentService.list(): { [number]: Live }
	return live
end

-- Studio: start a template next to a hero (at least at the level its robots unlock, so every template can
-- be tried; heroic forces the Heroic tier)
function IncidentService.force(hero: any, tid: string, heroic: boolean?): boolean
	local pos = HeroService.position(hero)
	if not pos or not IC.templates[tid] then
		return false
	end
	local hm = meta[hero.id] or { next = 0, last = nil }
	meta[hero.id] = hm
	local t = IC.templates[tid]
	local spot = findSpot(t, pos, 30, 300)
	if not spot then
		return false
	end
	local level = math.max(
		ZoneLevel.at(Config, spot.x, spot.z, hero.level, CityBuilder.world.tiles),
		IncidentPlan.levelFor(IC, Config, tid)
	)
	local inc = newLive(hero, tid, spot, level, heroic == true)
	live[inc.id] = inc
	startStep(inc)
	if inc.plan.heroic then
		beat("heroic", inc.pos)
	end
	return true
end

function IncidentService.clearAll()
	for _, inc in live do
		if not inc.ended then
			inc.plan.failed = true
		end
	end
end

local function tick(dt: number)
	local now = os.clock()
	local t0 = now
	local positions: { [Player]: Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local pos = hero and hero.alive and HeroService.position(hero)
		if pos then
			positions[player] = pos
		end
	end
	-- keep 2 incidents near every player's hero
	for player, pos in positions do
		local hero = HeroService.get(player)
		if
			hero
			and hero.loaded
			and not hero.traveling
			and not hero.scene
			and not EventPlan.inPocket(Config.Events, pos.Y)
		then
			local hm = meta[hero.id] or { next = now + 2, last = nil }
			meta[hero.id] = hm
			if now >= hm.next and ownedBy(hero.id) < S.perHero and count() < S.maxActive then
				if not spawnFor(hero, pos) then
					hm.next = now + 1
				else
					hm.next = now + 1.5
				end
			end
		end
	end
	for id, inc in live do
		if inc.ended then
			if now - inc.ended > 4 then
				for player in inc.known do
					if player.Parent then
						Net.fire("IncidentUpdate", player, { wire(inc, now, STATE.gone) })
					end
				end
				live[id] = nil
			end
		else
			stepIncident(inc, now, dt)
			-- nobody near, or its hero flew far away: replace it quietly
			local ownerHero = HeroService.byId(inc.owner)
			local ownerPos = ownerHero and HeroService.position(ownerHero)
			local someone = false
			for _, pos in positions do
				if (pos - inc.pos).Magnitude <= S.ownerFar then
					someone = true
					break
				end
			end
			if someone then
				inc.lastNear = now
			end
			local ownerGone = not ownerPos or (ownerPos - inc.pos).Magnitude > S.ownerFar
			if not inc.ended and (now - inc.lastNear > S.abandonAfter or (ownerGone and not someone)) then
				inc.plan.failed = true
				finish(inc, false, now)
			end
		end
	end
	PerfMonitor.add("schedulers", (os.clock() - t0) * 1000)
end

local sendClock = 0
local function send()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local pos = hero and HeroService.position(hero)
		local batch = {}
		for _, inc in live do
			local near = pos and (pos - inc.pos).Magnitude <= S.sendRadius
			if near and not inc.known[player] and not inc.ended then
				inc.known[player] = true
				Net.fire("IncidentSpawn", player, spawnPacket(inc, player, now))
			end
			if inc.known[player] then
				local state = if inc.ended
					then (if inc.plan.done then STATE.done else STATE.failed)
					else STATE.active
				if not near and not inc.ended and pos and (pos - inc.pos).Magnitude > S.sendRadius + 150 then
					inc.known[player] = nil
					state = STATE.gone
				end
				table.insert(batch, wire(inc, now, state))
			end
		end
		if #batch > 0 then
			Net.fire("IncidentUpdate", player, batch)
		end
	end
end

function IncidentService.init()
	SiteKit.safehouses = CityBuilder.world.safehouses
	EnemyService.Killed:Connect(onKilled)
	EnemyService.Hit:Connect(onHit)
	HeroService.Removed:Connect(function(hero)
		meta[hero.id] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, inc in live do
			inc.known[player] = nil
		end
	end)
	PerfMonitor.watch("incidents", count)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("IncidentService", function(dt)
		acc += dt
		sendClock += dt
		if acc >= 0.2 then
			tick(acc)
			acc = 0
		end
		if sendClock >= 1 / S.updateRate then
			sendClock = 0
			send()
		end
	end))
end

return IncidentService
