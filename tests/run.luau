-- Unit and sim tests for the pure modules, run outside Studio with Lune:  lune run tests/run.luau
-- Optional: pass a built place file to also check the Rojo layout:
--   lune run tests/run.luau build/Capeline.rbxl
-- ONLY=M1 lune run tests/run.luau  runs just the tests whose name contains "M1"

local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../src/config")
local Rng = require("../src/shared/Rng")
local Formulas = require("../src/shared/Formulas")
local NetSchema = require("../src/shared/NetSchema")
local Remotes = require("../src/shared/Remotes")
local MoveMath = require("../src/shared/MoveMath")
local MoveCheck = require("../src/shared/MoveCheck")
local PosHistory = require("../src/shared/PosHistory")
local HitQuery = require("../src/shared/HitQuery")
local Cooldowns = require("../src/shared/Cooldowns")
local FrameProf = require("../src/shared/FrameProf")
local FunnelKit = require("../src/shared/FunnelKit")
local FunnelDef = require("../src/shared/FunnelDef")
local EnemySim = require("../src/shared/EnemySim")
local EnemyBuffer = require("../src/shared/EnemyBuffer")
local CityLayout = require("../src/shared/CityLayout")
local WorldGen = require("../src/shared/WorldGen")
local WorldMap = require("../src/shared/WorldMap")
local Travel = require("../src/shared/Travel")
local BoxKit = require("../src/shared/BoxKit")
local HeightMap = require("../src/shared/HeightMap")
local Chunker = require("../src/shared/Chunker")
local BuildingState = require("../src/shared/BuildingState")
local Vehicles = require("../src/shared/Vehicles")
local CitizenSim = require("../src/shared/CitizenSim")
local CitizenBuffer = require("../src/shared/CitizenBuffer")
local ZoneLevel = require("../src/shared/ZoneLevel")
local WorldClock = require("../src/shared/WorldClock")
local IncidentPlan = require("../src/shared/IncidentPlan")
local ContractPlan = require("../src/shared/ContractPlan")
local EventPlan = require("../src/shared/EventPlan")
local BossMath = require("../src/shared/BossMath")
local BossSim = require("../src/shared/BossSim")
local DeepLayout = require("../src/shared/DeepLayout")

local passed, failed = 0, 0
local current = ""

local function check(condition: boolean, message: string)
	if condition then
		passed += 1
	else
		failed += 1
		print(string.format("  FAIL [%s] %s", current, message))
	end
end

local function near(a: number, b: number, tolerance: number, message: string)
	check(
		math.abs(a - b) <= tolerance,
		string.format("%s (got %.4f, want %.4f +- %.4f)", message, a, b, tolerance)
	)
end

local only = process.env.ONLY
local function test(name: string, fn: () -> ())
	if only and not string.find(name, only, 1, true) then
		return
	end
	current = name
	local ok, err = pcall(fn)
	if not ok then
		failed += 1
		print(string.format("  ERROR [%s] %s", name, tostring(err)))
	end
end

local M = Config.Move

---------------------------------------------------------------------------
-- Config and basics
---------------------------------------------------------------------------

test("config: every module loads; 136 abilities (17 paths) with unique network ids", function()
	check(#Config.Abilities.order == 136, "136 abilities")
	local perSet = {}
	for num, id in Config.Abilities.order do
		local a = Config.Abilities.list[id]
		check(a.num == num, id .. " num matches its order")
		check(a.coeff ~= nil and a.cd ~= nil and a.pts ~= nil, id .. " has coeff, cd and pts")
		perSet[a.set] = (perSet[a.set] or 0) + 1
	end
	for _, set in Config.Abilities.sets do
		check(perSet[set] == 8, set .. " has 8 abilities")
	end
	for _, cls in Config.Classes.order do
		check(Config.Classes[cls].healthMult ~= nil, cls .. " has a health mult")
	end
	local ids = {}
	for _, kind in Config.Enemies.order do
		local t = Config.Enemies[kind].typeId
		check(t >= 1 and t <= 31 and not ids[t], kind .. " typeId unique in 1..31")
		ids[t] = true
	end
end)

test("rng: same seed, same numbers", function()
	local a, b = Rng.new(42), Rng.new(42)
	local same = true
	for _ = 1, 100 do
		if a:next() ~= b:next() then
			same = false
		end
	end
	check(same, "repeatable")
end)

test("formulas: power, health, damage, caps", function()
	check(Formulas.power(Config, 1) == 36, "Power(1) = 36")
	check(Formulas.power(Config, 40, 170) == 440, "Power(40) with Might 170 = 440")
	check(
		Formulas.health(Config, 1, 0, "Powerhouse") == math.floor(425 * 1.35 + 0.5),
		"Bruiser health at level 1"
	)
	check(
		Formulas.health(Config, 1, 0, "Elemental") == math.floor(425 * 0.95 + 0.5),
		"Elemental health at level 1"
	)
	near(Formulas.damage(Config, 36, 0.6, "Elemental"), 36 * 0.6 * 1.1, 1e-6, "Zap Bolt damage")
	near(
		Formulas.damage(Config, 100, 1, "Rogue", true, 0.4),
		100 * 1.15 * 1.5 * 0.6,
		1e-6,
		"crit and mitigation"
	)
	near(Formulas.cooldownReduction(Config, 1e9), 0.40, 1e-6, "cooldown reduction caps at 40%")
	near(Formulas.critChance(Config, 600), 0.5, 1e-6, "crit chance 600 Precision = 50% (cap)")
	near(Formulas.ccMultiplier(Config, 1e9), 0.5, 1e-6, "CC floor 0.5")
	check(Formulas.enemyHealth(Config, "SparkDrone", 1) == 100, "Spark Drone 100 HP at level 1")
	check(Formulas.enemyHealth(Config, "SparkDrone", 11) == 200, "Spark Drone doubles at zone level 11")
	near(Formulas.enemyDamage(Config, "SparkDrone", 1), 12, 1e-6, "Spark Drone shot = (20 + 4) x 0.5")
end)

test("remotes: every schema is valid and checks its arguments", function()
	for name, def in Remotes do
		check(def.dir == "C2S" or def.dir == "S2C", name .. " has a direction")
		if def.dir == "C2S" then
			check(def.schema ~= nil and def.rate ~= nil, name .. " has a schema and a rate")
		end
	end
	local s = Remotes.CombatUse.schema
	check(NetSchema.validate(s, { 1, nil, 0, 1 }, 4) == false, "CombatUse rejects a missing aim")
	check(NetSchema.validate(s, { 1, 0 / 0, 0, 1 }, 4) == false, "CombatUse rejects NaN")
	check(NetSchema.validate(s, { 1.5, 1, 0, 1 }, 4) == false, "CombatUse rejects a fractional ability")
	check(NetSchema.validate(s, { 1, 1, 0, 1, 9 }, 5) == false, "CombatUse rejects extra arguments")
end)

---------------------------------------------------------------------------
-- M1: movement
---------------------------------------------------------------------------

-- Simulate a leap from the ground and return apex height, distance travelled and air time
local function simLeap(charge: number): (number, number, number)
	local vx, vy, vz = MoveMath.leapLaunch(M, 1, 0, charge)
	local x, y, t, top = 0, 0, 0, 0
	local dt = 1 / 240
	repeat
		vx, vy, vz = MoveMath.airStep(M, vx, vy, vz, dt)
		x += vx * dt
		y += vy * dt
		t += dt
		top = math.max(top, y)
	until y <= 0 or t > 10
	return top, x, t
end

test("M1: a full leap peaks at 40 studs and lands 80 away", function()
	local top, dist = simLeap(1)
	near(top, M.leap.apex, 0.6, "apex")
	near(dist, M.leap.range, 1.2, "range")
	local topShort = simLeap(0)
	near(topShort, M.leap.apex * M.leap.minCharge, 0.6, "a released early leap keeps the minimum height")
	local vx, vy, vz = MoveMath.leapLaunch(M, 0, 0, 1)
	check(vx == 0 and vz == 0 and vy > 0, "no stick: straight up")
end)

test("M1: glide falls at 12 studs/s and drifts forward at 50, never over 60", function()
	local vx, vy, vz = 30, 20, 0
	for _ = 1, 240 * 3 do
		vx, vy, vz = MoveMath.glideStep(M, vx, vy, vz, 1, 0, 1 / 240)
	end
	near(vy, -M.glide.fall, 0.3, "settles at the glide fall rate")
	near(vx, M.glide.forward, 0.6, "settles at the glide forward speed")
	vx, vy, vz = 100, -80, 0
	vx, vy, vz = MoveMath.glideStep(M, vx, vy, vz, 1, 0, 1 / 60)
	check(MoveMath.len3(vx, vy, vz) <= M.glide.cap + 1e-6, "speed capped at 60")
	-- steering: turning the stick 90 degrees turns at no more than the glide turn rate
	vx, vy, vz = 50, -12, 0
	vx, vy, vz = MoveMath.glideStep(M, vx, vy, vz, 0, 1, 0.1)
	local ang = math.deg(math.atan2(vz, vx))
	check(ang > 0 and ang <= M.glide.turnRate * 0.1 + 0.5, "glide turns toward the stick at the turn rate")
end)

local function flyFor(
	seconds: number,
	input: any,
	vx: number?,
	vy: number?,
	vz: number?,
	stamina: number?,
	y: number?
)
	local x, z = 0, 0
	local hy = y or 100
	local s = stamina or 100
	local cvx, cvy, cvz = vx or 0, vy or 0, vz or 0
	local boosting = false
	local dt = 1 / 60
	for _ = 1, math.floor(seconds * 60) do
		cvx, cvy, cvz, boosting = MoveMath.flightStep(M, cvx, cvy, cvz, hy, s, input, dt)
		s = MoveMath.staminaStep(M, s, false, boosting, dt)
		x += cvx * dt
		hy += cvy * dt
		z += cvz * dt
	end
	return cvx, cvy, cvz, s, hy, boosting
end

test("M1: flight cruises at 60, boosts at 110 for about 7 s, climbs 40 and dives 55", function()
	local fwd = { wishX = 1, wishY = 0, wishZ = 0, vertical = 0, boost = false }
	local vx, vy = flyFor(3, fwd)
	near(vx, M.flight.cruise, 0.5, "cruise speed")
	near(vy, 0, 0.5, "level")
	local boost = { wishX = 1, wishY = 0, wishZ = 0, vertical = 0, boost = true }
	local bvx, _, _, s1 = flyFor(3, boost)
	near(bvx, M.flight.boost, 0.5, "boost speed")
	near(s1, 100 - 14 * 3, 1.5, "boost drains 14 per second")
	-- boost runs out after about 7 s (100 / 14) and drops back to cruise
	local evx, _, _, s2, _, boosting = flyFor(9, boost)
	check(s2 <= 1 and not boosting, "stamina empty after 9 s of boost")
	check(evx <= M.flight.boost and evx >= M.flight.cruise - 1, "back to cruise when empty")
	local _, upVy = flyFor(2, { wishX = 0, wishY = 0, wishZ = 0, vertical = 1, boost = false })
	near(upVy, M.flight.up, 0.5, "climb rate")
	local _, downVy = flyFor(2, { wishX = 0, wishY = 0, wishZ = 0, vertical = -1, boost = false })
	near(downVy, -M.flight.down, 0.5, "dive rate")
end)

test("M1: flight auto-levels into a hover and turns at 120 degrees/s at speed", function()
	local hvx, hvy, hvz =
		flyFor(3, { wishX = 0, wishY = 0, wishZ = 0, vertical = 0, boost = false }, 60, 30, 0)
	check(MoveMath.len3(hvx, hvy, hvz) < 1, "lets go: slows to a hover")
	-- at cruise, ask for a 180-degree turn; after 0.5 s the heading has turned 60 degrees at most
	local vx, _, vz = flyFor(0.5, { wishX = -1, wishY = 0, wishZ = 0, vertical = 0, boost = false }, 60, 0, 0)
	local ang = math.abs(math.deg(math.atan2(vz, vx)))
	check(ang <= 61 and ang >= 50, string.format("turn limited to 120 degrees/s (turned %.1f)", ang))
end)

test("M1: the ceiling pushes back above 560 and never lets a hero past 600", function()
	local _, _, _, _, y =
		flyFor(20, { wishX = 0, wishY = 1, wishZ = 0, vertical = 1, boost = true }, 0, 0, 0, 100, 500)
	check(y <= M.ceiling.hard + 1, string.format("ends below the hard ceiling (y = %.1f)", y))
end)

test("M1: stamina regenerates 15/s on the ground and 8/s in the air", function()
	near(MoveMath.staminaStep(M, 50, true, false, 1), 65, 1e-6, "ground regen")
	near(MoveMath.staminaStep(M, 50, false, false, 1), 58, 1e-6, "air regen")
	check(MoveMath.staminaStep(M, 99, true, false, 1) == 100, "caps at 100")
end)

---------------------------------------------------------------------------
-- M1: server speed check
---------------------------------------------------------------------------

test("M1: the speed check passes honest flight with jitter and catches teleports and speed hacks", function()
	local S = Config.Safety
	local cap = MoveMath.speedCap(M, { flight = true }, true)
	check(cap == M.caps.flight, "flight cap with boost is 125")
	-- honest boost at 110 studs/s, samples arriving in bursts (0, 0.2, 0.2, 0 s gaps)
	local st = MoveCheck.new(0, 100, 0, 0)
	local t, x = 0, 0
	local fails = 0
	local gaps = { 0.02, 0.18, 0.1, 0.2, 0.0, 0.1 }
	for i = 1, 300 do
		local gap = gaps[(i % #gaps) + 1]
		t += 0.1
		x += 110 * 0.1
		local ok = MoveCheck.sample(st, x, 100, 0, t + gap - 0.1, cap, M, S)
		if not ok then
			fails += 1
		end
	end
	check(fails == 0, string.format("honest boost never fails (%d fails)", fails))
	-- a 300 stud teleport fails and counts as a strike
	local ok, strike = MoveCheck.sample(st, x + 300, 100, 0, t + 0.1, cap, M, S)
	check(not ok and strike, "teleport fails with a strike")
	-- a sustained 200 studs/s speed hack fails within a second
	local hack = MoveCheck.new(0, 10, 0, 0)
	local caught = false
	for i = 1, 20 do
		if not MoveCheck.sample(hack, i * 20, 10, 0, i * 0.1, MoveMath.speedCap(M, {}, false), M, S) then
			caught = true
		end
	end
	check(caught, "200 studs/s on foot is caught")
	-- falling from the ceiling is free up to terminal speed
	local fall = MoveCheck.new(0, 600, 0, 0)
	local y, vy, fallFails = 600, 0, 0
	for i = 1, 30 do
		vy = math.min(220, vy + 196.2 * 0.1)
		y -= vy * 0.1
		if not MoveCheck.sample(fall, 0, y, 0, i * 0.1, MoveMath.speedCap(M, {}, false), M, S) then
			fallFails += 1
		end
	end
	check(fallFails == 0, "free fall never fails")
	-- a granted dash passes
	local dash = MoveCheck.new(0, 10, 0, 0)
	MoveCheck.sample(dash, 0, 10, 0, 1, 28, M, S)
	MoveCheck.grant(dash, 30)
	check((MoveCheck.sample(dash, 30, 10, 0, 1.2, 28, M, S)), "a granted 30 stud dash passes")
	-- 3 strikes in 10 minutes kicks
	local k = MoveCheck.new(0, 0, 0, 0)
	check(not MoveCheck.addStrike(k, 1, S) and not MoveCheck.addStrike(k, 2, S), "2 strikes: no kick")
	check(MoveCheck.addStrike(k, 3, S), "3rd strike in 10 minutes: kick")
	local k2 = MoveCheck.new(0, 0, 0, 0)
	MoveCheck.addStrike(k2, 0, S)
	MoveCheck.addStrike(k2, 300, S)
	check(not MoveCheck.addStrike(k2, 700, S), "strikes older than 10 minutes drop off")
end)

---------------------------------------------------------------------------
-- M1: combat
---------------------------------------------------------------------------

test("M1: position history rewinds up to 150 ms", function()
	local h = PosHistory.new(1)
	for i = 0, 60 do
		PosHistory.push(h, i / 30, i, 0, 0)
	end
	local x = PosHistory.rewind(h, 2, 0.1, 0.15)
	near(x :: number, 57, 0.01, "100 ms back")
	local x2 = PosHistory.rewind(h, 2, 0.5, 0.15)
	near(x2 :: number, 55.5, 0.01, "clamped to 150 ms")
	check(#h.times <= 32, "keeps about one second")
end)

test("M1: bolt, cone, chain and dash find the right targets", function()
	local cands = {
		{ id = 1, x = 20, y = 0, z = 0, r = 2.5 },
		{ id = 2, x = 40, y = 0, z = 1, r = 2.5 },
		{ id = 3, x = 30, y = 0, z = 30, r = 2.5 },
		{ id = 4, x = 52, y = 0, z = 10, r = 2.5 },
	}
	local hit = HitQuery.bolt(0, 0, 0, 1, 0, 0, 45, 3, 0, 15, cands)
	check(hit ~= nil and hit.id == 1, "bolt hits the first enemy on the line")
	local hinted = HitQuery.bolt(0, 0, 0, 1, 0, 0.05, 45, 3, 2, 15, cands)
	check(hinted ~= nil and hinted.id == 2, "bolt takes a valid hint")
	local farHint = HitQuery.bolt(0, 0, 0, 1, 0, 0, 45, 3, 3, 15, cands)
	check(farHint ~= nil and farHint.id == 1, "a hint 45 degrees off the aim is ignored")
	local blocked = HitQuery.bolt(0, 0, 0, 1, 0, 0, 45, 3, 0, 15, cands, function()
		return false
	end)
	check(blocked == nil, "line of sight blocks the bolt")
	local first = HitQuery.cone(0, 0, 0, 1, 0, 0, 50, 30, cands)
	check(first ~= nil and first.id == 1, "cone picks the nearest")
	local chain = HitQuery.chain(first :: any, cands, 3, 18)
	check(#chain == 3 and chain[2].id == 2 and chain[3].id == 4, "chain jumps 1 -> 2 -> 4")
	local path = HitQuery.capsule(0, 0, 0, 30, 0, 0, 6, cands)
	check(#path == 1 and path[1].id == 1, "dash path hits only what it passes")
end)

test("M1: cooldowns with 100 ms leeway", function()
	local b = Cooldowns.new()
	check(Cooldowns.ready(b, "ChainLightning", 0, 0.1), "ready at first")
	Cooldowns.start(b, "ChainLightning", 0, 6)
	check(not Cooldowns.ready(b, "ChainLightning", 5.8, 0.1), "not ready at 5.8 s")
	check(Cooldowns.ready(b, "ChainLightning", 5.95, 0.1), "ready 50 ms early (lag leeway)")
	near(Cooldowns.fraction(b, "ChainLightning", 3, 6), 0.5, 1e-6, "sweep half way")
end)

---------------------------------------------------------------------------
-- M1: drones and the city
---------------------------------------------------------------------------

local layout = CityLayout.downtown(Config.City)
local function heightAt(x: number, z: number): number
	return CityLayout.heightAt(layout, x, z)
end

test("M1: Downtown greybox fits its district and part budget, and builds the same twice", function()
	local d = Config.City.districts.Downtown
	check(#layout.buildings >= 60, string.format("%d buildings", #layout.buildings))
	check(
		layout.parts <= Config.City.partBudget.downtown,
		string.format("%d parts within budget", layout.parts)
	)
	for _, b in layout.buildings do
		if b.x < d.minX or b.x > d.maxX or b.z < d.minZ or b.z > d.maxZ then
			check(false, "building outside Downtown")
			break
		end
	end
	check(#layout.spawns == 4, "4 spawns on the plaza")
	check(
		heightAt(layout.beacon.x, layout.beacon.z) >= Config.City.downtown.beacon.height,
		"Beacon Tower is the tallest"
	)
	local tallest = 0
	for _, b in layout.buildings do
		tallest = math.max(tallest, b.h)
	end
	check(tallest < Config.Move.ceiling.soft, "every roof is under the flight ceiling")
	local again = CityLayout.downtown(Config.City)
	local same = #again.boxes == #layout.boxes
	for i, b in layout.boxes do
		local o = again.boxes[i]
		if not o or o.cx ~= b.cx or o.sy ~= b.sy or o.color ~= b.color then
			same = false
			break
		end
	end
	check(same, "same seed, same city")
	check(heightAt(5000, 0) == 0, "outside the hub is sea level")
end)

local function droneWorld(_heroes: { any })
	local seed = 7
	local sim = EnemySim.new(Config, {
		heightAt = heightAt,
		random = function()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end,
	})
	return sim
end

test("M1: drones find a hero, strafe at orbit range and fire 3-shot bursts that can hit", function()
	local hero = { id = 1, x = 1500, y = 20, z = 1500, alive = true }
	local heroes = { hero }
	local sim = droneWorld(heroes)
	local e = EnemySim.spawn(sim, "SparkDrone", hero.x + 70, 40, hero.z, 1)
	check(e ~= nil, "spawned")
	local shots, hits, attacked = 0, 0, false
	local minD, maxD = math.huge, 0
	for i = 1, 150 do
		EnemySim.step(sim, i / 10, heroes)
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "shot" then
				shots += 1
			elseif ev.k == "hit" then
				hits += 1
			end
		end
		local en = sim.byId[(e :: any).id]
		if en.state == EnemySim.ATTACK then
			attacked = true
			if i > 60 then
				local dx, dz = en.x - hero.x, en.z - hero.z
				local d = math.sqrt(dx * dx + dz * dz)
				minD, maxD = math.min(minD, d), math.max(maxD, d)
			end
		end
	end
	check(attacked, "reaches the attack state")
	check(shots >= 12, string.format("fires bursts (%d shots in 15 s)", shots))
	check(hits > 0, "a standing hero gets hit")
	check(minD > 10 and maxD < 60, string.format("strafes at orbit range (%.0f to %.0f studs)", minD, maxD))
end)

test("M1: a hero moving fast across a drone's line dodges most shots", function()
	local hero = { id = 1, x = 0, y = 150, z = 0, alive = true }
	local heroes = { hero }
	local sim = droneWorld(heroes)
	-- open air above the sea, far from the city
	hero.x, hero.z = 1500, 1500
	EnemySim.spawn(sim, "SparkDrone", hero.x + 35, 150, hero.z, 1)
	local shots, hits = 0, 0
	for i = 1, 200 do
		hero.z = 1500 + math.sin(i / 10 * 1.6) * 40 -- weaving at about 60 studs/s
		EnemySim.step(sim, i / 20, heroes)
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "shot" then
				shots += 1
			elseif ev.k == "hit" then
				hits += 1
			end
		end
	end
	check(shots > 0 and hits < shots * 0.6, string.format("dodged: %d of %d shots hit", hits, shots))
end)

test("M1: damage kills a drone with a die event; Zap Bolt needs 5 hits at level 1 as a Blaster", function()
	local heroes = { { id = 1, x = 0, y = 0, z = 0, alive = true } }
	local sim = droneWorld(heroes)
	local e = EnemySim.spawn(sim, "SparkDrone", 1500, 50, 1500, 1) :: any
	local dmg =
		Formulas.damage(Config, Formulas.power(Config, 1), Config.Abilities.list.ZapBolt.coeff, "Elemental")
	local hits = 0
	local killed = false
	while not killed and hits < 20 do
		hits += 1
		killed = EnemySim.damage(sim, e.id, dmg, 1)
	end
	check(killed and hits == 5, string.format("%d Zap Bolts", hits))
	check(sim.byId[e.id] == nil and EnemySim.count(sim) == 0, "removed")
	local ev = EnemySim.drainEvents(sim)
	check(ev[#ev].k == "die" and ev[#ev].by == 1, "die event names the attacker")
	check(not EnemySim.damage(sim, e.id, 10, 1), "a dead drone takes no more damage")
end)

test("M1: populate keeps 3 drones near each hero, out of sight, under the server cap", function()
	local heroes = {}
	for i = 1, 30 do
		table.insert(
			heroes,
			{ id = i, x = (i % 6) * 300 - 750, y = 30, z = (i // 6) * 300 - 750, alive = true }
		)
	end
	local sim = droneWorld(heroes)
	for i = 1, 600 do
		local now = i / 10
		EnemySim.populate(sim, heroes, now)
		EnemySim.step(sim, now, heroes)
		EnemySim.drainEvents(sim)
	end
	check(
		EnemySim.count(sim) <= Config.Enemies.caps.perServer,
		string.format("%d drones, cap 90", EnemySim.count(sim))
	)
	check(EnemySim.count(sim) >= 60, "about 3 per hero")
	-- no more than 6 attack one hero
	local per = {}
	for _, e in sim.enemies do
		if e.target and e.state == EnemySim.ATTACK then
			per[e.target] = (per[e.target] or 0) + 1
		end
	end
	local worst = 0
	for _, c in per do
		worst = math.max(worst, c)
	end
	check(worst <= Config.Enemies.caps.attackingOneHero, "at most 6 attackers per hero")
end)

test("M1: 90 drones and 30 heroes step inside the enemy budget (2.5 ms a frame)", function()
	local heroes = {}
	for i = 1, 30 do
		table.insert(
			heroes,
			{ id = i, x = (i % 6) * 60 - 400, y = 60, z = (i // 6) * 60 - 150, alive = true }
		)
	end
	local sim = droneWorld(heroes)
	for i = 1, 90 do
		EnemySim.spawn(sim, "SparkDrone", (i % 10) * 30 - 450, 80, (i // 10) * 30 - 150, 1)
	end
	local worst, total, frames = 0, 0, 0
	for f = 1, 600 do
		local t0 = os.clock()
		EnemySim.step(sim, f / 60, heroes)
		local ms = (os.clock() - t0) * 1000
		EnemySim.drainEvents(sim)
		if f > 60 then
			worst = math.max(worst, ms)
			total += ms
			frames += 1
		end
	end
	local avg = total / frames
	check(avg < 2.5, string.format("average %.2f ms a frame (budget 2.5)", avg))
	print(
		string.format(
			"  info: enemy step avg %.3f ms, worst %.3f ms (90 drones, 30 heroes, Lune)",
			avg,
			worst
		)
	)
end)

test("M1: Enemy.Delta round trip in 10 bytes per enemy, only nearby enemies", function()
	local heroes = { { id = 1, x = 0, y = 0, z = 0, alive = true } }
	local sim = droneWorld(heroes)
	EnemySim.spawn(sim, "SparkDrone", 100.25, 3000.5, -2399.9, 1)
	EnemySim.spawn(sim, "SparkDrone", 10, 20, 30, 1)
	sim.enemies[2].health = 50
	local b = EnemyBuffer.encodeFor(7, 12.5, sim.enemies, 0, 0, 0, 4000, 60)
	check(buffer.len(b) == EnemyBuffer.HEADER + 2 * EnemyBuffer.PER, "10 bytes each")
	local seq, time, rows = EnemyBuffer.decode(b)
	check(seq == 7 and math.abs(time - 12.5) < 1e-3 and #rows == 2, "header")
	near(rows[1].x, 100.3, 0.06, "x")
	near(rows[1].y, 3000.5, 0.06, "y reaches the mission pockets")
	near(rows[1].z, -2399.9, 0.06, "z reaches the map edge")
	near(rows[2].health, 0.5, 0.01, "health fraction")
	check(rows[2].typeId == 1 and rows[2].state == EnemySim.PATROL, "type and state")
	local nearOnly = EnemyBuffer.encodeFor(8, 0, sim.enemies, 0, 0, 0, 100, 60)
	check(buffer.len(nearOnly) == EnemyBuffer.HEADER + EnemyBuffer.PER, "relevance radius drops far enemies")
	-- the 60-enemy worst case fits one unreliable packet (under 900 bytes)
	check(EnemyBuffer.HEADER + 60 * EnemyBuffer.PER < 900, "60 enemies fit one packet")
end)

---------------------------------------------------------------------------
-- M2: classes, abilities, Awakening, enemies
---------------------------------------------------------------------------

local Status = require("../src/shared/Status")
local AbilityRules = require("../src/shared/AbilityRules")
local CastPlan = require("../src/shared/CastPlan")
local Awakening = require("../src/shared/Awakening")
local AB = Config.Abilities

local SHAPES = {
	bolt = true,
	chain = true,
	dash = true,
	cone = true,
	arc = true,
	nova = true,
	field = true,
	line = true,
	leap = true,
	throw = true,
	buff = true,
	wall = true,
	ramp = true,
	ride = true,
	launch = true,
	place = true,
}

test(
	"M2: 17 paths x 8 abilities; every skill and super has 2 mods and a capstone; shapes are known",
	function()
		check(
			#AB.sets == 17 and AB.sets[1] == "Volt" and AB.sets[17] == "Light",
			"17 paths, Storm first, Light last"
		)
		for _, id in AB.order do
			local a = AB.list[id]
			check(SHAPES[a.shape] == true, id .. " shape " .. tostring(a.shape))
			if a.slot ~= "basic" then
				check(a.mods ~= nil and #a.mods == 2, id .. " has 2 mods")
				check(a.cap ~= nil, id .. " has a capstone")
			end
		end
		local per = {}
		for _, id in AB.order do
			local a = AB.list[id]
			per[a.set] = per[a.set] or { basic = 0, skill = 0, super = 0 }
			per[a.set][a.slot] += 1
		end
		for _, set in AB.sets do
			check(
				per[set].basic == 1 and per[set].skill == 6 and per[set].super == 1,
				set .. ": 1 basic, 6 skills, 1 super"
			)
			check(AB.starter[set] ~= nil and #AB.starter[set] == 2, set .. " has 2 starter skills")
			check(AB.setName[set] ~= nil and AB.setColor[set] ~= nil, set .. " name and colour")
			local travel = 0
			for _, id in AB.order do
				local a = AB.list[id]
				if a.set == set and a.travel then
					travel += 1
					check(a.slot == "skill", id .. " travel power is a skill")
				end
			end
			check(travel == 1, set .. " has exactly one travel power")
			for _, id in AB.starter[set] do
				check(
					AB.list[id] and AB.list[id].set == set and AB.list[id].slot == "skill",
					id .. " starter of " .. set
				)
			end
			local arch = AbilityRules.archetypeOf(Config, set)
			check(arch ~= nil, set .. " belongs to an archetype")
		end
		check(#AB.combos.pairs == 10, "10 team-up combos")
	end
)

test("M2: ranks: +10% coeff at 2, mod at 3, -8% cooldown at 4, capstone at 5; supers rank 3", function()
	local base = AB.list.ChainLightning
	local r1 = AbilityRules.effective(Config, "ChainLightning", 1, 1)
	near(r1.coeff, base.coeff, 1e-9, "rank 1 is the base")
	check(r1.targets == 3, "no mod at rank 1")
	local r2 = AbilityRules.effective(Config, "ChainLightning", 2, 1)
	near(r2.coeff, base.coeff * 1.1, 1e-9, "rank 2 +10%")
	local r3 = AbilityRules.effective(Config, "ChainLightning", 3, 1)
	check(r3.targets == 5, "rank 3 mod 1: five targets")
	local r3b = AbilityRules.effective(Config, "ChainLightning", 3, 2)
	check(
		r3b.targets == 3 and r3b.status == "stun" and r3b.firstOnly == true,
		"rank 3 mod 2: first target stunned"
	)
	local r4 = AbilityRules.effective(Config, "ChainLightning", 4, 1)
	near(r4.cd, base.cd * 0.92, 1e-9, "rank 4 -8% cooldown")
	local r5 = AbilityRules.effective(Config, "ChainLightning", 5, 1)
	check(r5.capstone == true and r5.jump == base.jump + 8, "rank 5 capstone")
	near(r5.coeff, base.coeff * 1.1 * 1.25, 1e-9, "capstone multiplies the coeff")
	check(AB.list.ChainLightning.targets == 3, "the config row is never changed")
	local s2 = AbilityRules.effective(Config, "ThunderDrop", 2, 1)
	near(s2.radius, AB.list.ThunderDrop.radius * 1.2, 1e-9, "super mod at rank 2")
	local s3 = AbilityRules.effective(Config, "ThunderDrop", 3, 1)
	check(s3.capstone == true and s3.echo == 0.5, "super capstone at rank 3")
	check(
		AbilityRules.maxRank(AB.list.ZapBolt) == 1 and AbilityRules.maxRank(AB.list.ThunderDrop) == 3,
		"max ranks"
	)
end)

test(
	"M2: skill points: ranks cost 1,1,2,2,3 and 2,3,4; starters are free; 48 points cannot max everything",
	function()
		local sum = 0
		for r = 1, 5 do
			sum += (AbilityRules.rankCost(Config, "StaticField", r))
		end
		check(sum == 9, "a skill costs 9 points to max")
		local sup = 0
		for r = 1, 3 do
			sup += (AbilityRules.rankCost(Config, "ThunderDrop", r))
		end
		check(sup == 9, "a super costs 9 points to max")
		local ranks = AbilityRules.starter(Config, "Volt")
		check(AbilityRules.pointsSpent(Config, ranks) == 0, "the starter kit is free")
		local hero = { level = 1, ranks = ranks, bonusPoints = 0 }
		local ok = AbilityRules.canRank(Config, hero, "StaticField", true)
		check(ok, "level 1 has 1 point to learn a skill")
		ranks.StaticField = 1
		local ok2, reason = AbilityRules.canRank(Config, hero, "ArcFlash", true)
		check(not ok2 and reason == "points", "out of points")
		local ok3, reason3 = AbilityRules.canRank(Config, hero, "IceShard", true)
		check(not ok3 and reason3 == "no ranks", "basics have no ranks")
		local ok4, reason4 = AbilityRules.canRank(Config, hero, "FreezeBeam", true)
		check(not ok4 and reason4 == "set locked", "another path is locked before level 15")
		local ok5, reason5, pts5 =
			AbilityRules.canRank(Config, { level = 15, ranks = ranks, startSet = "Volt" }, "FreezeBeam", true)
		check(
			ok5 and reason5 == nil and pts5 == 1,
			"a borrowed path's starter costs a point (only the main path's are free)"
		)
		local okA, reasonA = AbilityRules.canRank(Config, { level = 40, ranks = ranks }, "FlashStep", true)
		check(not okA and reasonA == "set locked", "a path from another archetype is never open")
		local okB, reasonB = AbilityRules.canRank(Config, { level = 40, ranks = ranks }, "BlizzardDome", true)
		check(not okB and reasonB == "main path only", "the super is the main path's")
		local five = table.clone(ranks)
		for _, id in { "FreezeBeam", "FrostNova", "FlameJets", "FireWhip", "RockRide" } do
			five[id] = 1
		end
		local okC, reasonC = AbilityRules.canRank(Config, { level = 40, ranks = five }, "MudWave", true)
		check(not okC and reasonC == "borrow limit", "at most 5 borrowed skills")
		local okD = AbilityRules.canRank(Config, { level = 40, ranks = five }, "FrostNova", true)
		check(okD, "a borrowed skill already learned can still rank up")
		local ok6, reason6 =
			AbilityRules.canRank(Config, { level = 30, ranks = ranks, credits = 0 }, "StaticField", false)
		check(not ok6 and reason6 == "credits", "ranks cost Credits when the wallet is on")
		local everything = 0
		for _, id in AB.order do
			if AB.list[id].slot ~= "basic" and not AbilityRules.isStarter(Config, id) then
				everything += 9
			end
		end
		check(everything > 48, string.format("maxing all %d points is out of reach of 48", everything))
	end
)

test("M2: loadout rules: budget 52, slots by level, learned only, unlocked sets, super at 20", function()
	local ranks = {}
	for _, id in AB.order do
		ranks[id] = 1
	end
	local function v(level: number, set: string, skills: { string }, super: string?)
		return AbilityRules.validate(
			Config,
			{ level = level, ranks = ranks },
			{ set = set, skills = skills, super = super }
		)
	end
	check((v(1, "Volt", { "ChainLightning", "DashStrike" })), "the starter loadout is fine")
	local _, r1 = v(1, "Volt", { "ChainLightning", "DashStrike", "StaticField" })
	check(r1 == "too many skills", "slot 3 opens at level 5")
	check((v(5, "Volt", { "ChainLightning", "DashStrike", "StaticField" })), "level 5 has 3 slots")
	local _, r2 = v(40, "Volt", { "Shatter", "Flashpoint", "PhoenixDive", "FrostNova" })
	check(r2 == "over budget", "14+13+13+13 (53) is over 52")
	check((v(40, "Volt", { "Shatter", "Flashpoint", "PhoenixDive", "GroundSpark" })), "14+13+13+8 = 48 fits")
	local _, r3 = v(40, "Volt", { "ChainLightning", "ChainLightning" })
	check(r3 == "duplicate", "no duplicates")
	local _, r4 = v(40, "Volt", { "ThunderDrop" })
	check(r4 == "not a skill", "a super is not a skill")
	local _, r5 = v(19, "Volt", { "ChainLightning" }, "ThunderDrop")
	check(r5 == "super locked", "supers open at 20")
	check((v(20, "Volt", { "ChainLightning" }, "ThunderDrop")), "super at 20")
	local _, r6 = v(14, "Volt", { "FreezeBeam" })
	check(r6 == "set locked", "a borrowed Elemental skill waits for level 15")
	check((v(15, "Volt", { "FreezeBeam" })), "from 15 a Storm hero can slot a Frost skill")
	local _, r7 = v(40, "Volt", { "FlashStep" })
	check(r7 == "set locked", "a Swordsman skill never goes on a Storm hero")
	local _, r7b = v(40, "Frost", { "FreezeBeam" })
	check(r7b == "not the main path", "the loadout's path is the hero's main path")
	ranks.StaticField = 0
	local _, r8 = v(5, "Volt", { "StaticField" })
	check(r8 == "not learned", "not learned")
	local _, r9 = v(1, "Volt", {}, nil)
	check(r9 == nil, "an empty loadout is allowed")
	local _, r10 = AbilityRules.validate(
		Config,
		{ level = 40, ranks = ranks },
		{ set = "Volt", basic = "IceShard", skills = {} }
	)
	check(r10 == "basic not of the set", "the basic follows the primary set")
end)

test("M2: forged loadouts never pass over 52 points (every 4-skill combination)", function()
	local skills = {}
	local ranks = {}
	for _, id in AB.order do
		ranks[id] = 1
		if AB.list[id].slot == "skill" then
			table.insert(skills, id)
		end
	end
	local hero = { level = 40, ranks = ranks }
	local n, accepted, bad = #skills, 0, 0
	for a = 1, n - 3 do
		for b = a + 1, n - 2 do
			for c = b + 1, n - 1 do
				for d = c + 1, n do
					local pick = { skills[a], skills[b], skills[c], skills[d] }
					local ok = AbilityRules.validate(Config, hero, { set = "Volt", skills = pick })
					if ok then
						accepted += 1
						if AbilityRules.loadoutPoints(Config, pick) > AB.loadoutCap then
							bad += 1
						end
					end
				end
			end
		end
	end
	check(bad == 0, "no accepted loadout is over budget")
	check(accepted > 1000, string.format("plenty of builds fit (%d)", accepted))
end)

test("M2: cooldowns: attack speed, Awakening, recasts and combo strings", function()
	local zap = AbilityRules.effective(Config, "ZapBolt", 1)
	near(AbilityRules.cooldown(Config, Formulas, zap, { classId = "Elemental" }), 0.5, 1e-9, "basic 0.5 s")
	near(
		AbilityRules.cooldown(Config, Formulas, zap, { classId = "Elemental", attackSpeed = 0.25 }),
		0.4,
		1e-9,
		"Overcharge +25% attack speed"
	)
	local chain = AbilityRules.effective(Config, "ChainLightning", 1)
	local base = AbilityRules.cooldown(Config, Formulas, chain, { classId = "Elemental" })
	near(base, 6, 1e-9, "Chain 6 s")
	near(
		AbilityRules.cooldown(Config, Formulas, chain, { classId = "Elemental", awakened = true }),
		6 / 1.35,
		1e-9,
		"awakened skills 35% faster"
	)
	near(
		AbilityRules.cooldown(Config, Formulas, chain, { classId = "Rogue" }),
		6 * 0.95,
		1e-9,
		"Speedster -5%"
	)
	local td = AbilityRules.effective(Config, "ThunderDrop", 1)
	near(
		AbilityRules.cooldown(Config, Formulas, td, { classId = "Elemental", awakened = true }),
		45,
		1e-9,
		"awakened super half cooldown"
	)
	-- recast (Double Back)
	local dash = AbilityRules.effective(Config, "DashStrike", 5, 1)
	local st = {}
	check(dash.recast == true, "capstone gives the recast")
	near(AbilityRules.afterUse(st, "DashStrike", dash, 10, 7), 0.35, 1e-9, "first use: a short lock")
	check(not AbilityRules.blocked(st, "DashStrike", 11), "the window is open")
	near(AbilityRules.afterUse(st, "DashStrike", dash, 11, 7), 7, 1e-9, "the recast starts the full cooldown")
	AbilityRules.afterUse(st, "DashStrike", dash, 30, 7)
	check(AbilityRules.blocked(st, "DashStrike", 34), "a lapsed window still owes its cooldown")
	check(not AbilityRules.blocked(st, "DashStrike", 37.1), "then it is free again")
	local plain = AbilityRules.effective(Config, "DashStrike", 1)
	near(AbilityRules.afterUse({}, "DashStrike", plain, 0, 8), 8, 1e-9, "no capstone, no recast")
	check(AbilityRules.comboStep(nil, nil, 0, 3) == 1, "combo starts at 1")
	check(
		AbilityRules.comboStep(0, 1, 0.5, 3) == 2 and AbilityRules.comboStep(0, 2, 0.5, 3) == 3,
		"combo goes on"
	)
	check(AbilityRules.comboStep(0, 3, 0.5, 3) == 1, "combo wraps after the finisher")
	check(AbilityRules.comboStep(0, 2, 1.5, 3) == 1, "a pause resets it")
end)

test(
	"M2: status effects: strongest wins, never shortened, resist, immunity, PvP diminishing returns",
	function()
		local b = Status.new()
		check(Status.apply(b, "slow", 2, 0, { value = 0.6 }) == 2, "slow applied")
		Status.apply(b, "slow", 1, 0.5, { value = 0.8 })
		near(Status.speedMult(b, 1), 0.6, 1e-9, "a weaker slow does not replace a stronger one")
		near(b.list.slow.untilT, 2, 1e-9, "and does not shorten it")
		Status.apply(b, "slow", 3, 1, { value = 0.7 })
		near(b.list.slow.untilT, 4, 1e-9, "a longer one extends it")
		check(Status.canMove(b, 1) and Status.canAct(b, 1), "slowed can move and act")
		Status.apply(b, "root", 1, 1)
		check(not Status.canMove(b, 1.5) and Status.canAct(b, 1.5), "rooted can act")
		Status.apply(b, "stun", 1, 1)
		check(not Status.canAct(b, 1.5), "stunned cannot act")
		check(Status.apply(b, "stun", 1, 2, { resist = 0.5 }) == 0.5, "ccResist halves")
		check(Status.apply(b, "float", 3, 2, { immune = { "float" } }) == 0, "immune")
		local p = Status.new()
		check(Status.apply(p, "stun", 2, 0, { pvp = true }) == 2, "PvP first stun full")
		check(Status.apply(p, "stun", 2, 3, { pvp = true }) == 0, "immune for 3 s after it ends")
		check(Status.apply(p, "stun", 2, 5.5, { pvp = true }) == 1, "a repeat within 8 s is halved")
		local k = Status.new()
		Status.apply(k, "knockup", 1, 0)
		near(Status.liftHeight(k, 0.5, 8, 6), 8, 1e-6, "knockup peaks halfway")
		near(Status.liftHeight(k, 1.1, 8, 6), 0, 1e-6, "and lands")
		local s = Status.new()
		Status.apply(s, "shield", 5, 0, { value = 100 })
		near(Status.absorb(s, 60, 1), 0, 1e-9, "shield soaks")
		near(Status.absorb(s, 60, 1), 20, 1e-9, "then breaks")
		check(not Status.has(s, "shield", 1), "a broken shield is gone")
		local f = Status.new()
		Status.apply(f, "stun", 1, 0)
		Status.apply(f, "slow", 1, 0, { value = 0.5 })
		check(Status.flags(f, 0.5) == Status.BITS.stun + Status.BITS.slow, "wire flags")
		local ended = Status.clean(f, 2)
		check(ended ~= nil and #ended == 2, "clean returns what ended")
	end
)

test("M2: Awakening meter, 15 s window, damage, and team-up combos", function()
	local m = Awakening.new()
	for _ = 1, 10 do
		Awakening.gain(Config, m, "skillHit", 1, 0)
	end
	near(m.value, 40, 1e-9, "10 skill hits = 40")
	Awakening.gain(Config, m, "basicHit", 3, 0)
	near(m.value, 40 + 1.5 * 2, 1e-9, "extra targets count half")
	Awakening.hurt(Config, m, 0.2, 0)
	near(m.value, 53, 1e-9, "losing 20% health adds 10")
	check(not Awakening.ready(Config, m, 0), "not full yet")
	for _ = 1, 20 do
		Awakening.gain(Config, m, "kill", 1, 0)
	end
	check(m.value == 100 and Awakening.ready(Config, m, 0), "capped at 100 and ready")
	check(Awakening.start(Config, m, 10), "awaken")
	check(m.value == 0 and Awakening.active(m, 24.9) and not Awakening.active(m, 25.1), "15 s")
	near(Awakening.damageMult(Config, m, 12), 1.2, 1e-9, "+20% damage")
	near(Awakening.damageMult(Config, m, 12, true), 1.1, 1e-9, "+10% in PvP")
	Awakening.gain(Config, m, "kill", 1, 12)
	check(m.value == 0, "no meter while awake")
	check(not Awakening.start(Config, m, 12), "cannot stack")
	-- combos: Frost + Volt within 3 s and 30 studs
	local cb = Awakening.comboBook()
	local p1 = Awakening.noteSuper(Config, cb, { hero = 1, set = "Volt", x = 0, y = 0, z = 0, t = 0 })
	check(p1 == nil, "one super alone")
	local p2 = Awakening.noteSuper(Config, cb, { hero = 1, set = "Frost", x = 0, y = 0, z = 0, t = 1 })
	check(p2 == nil, "the same hero cannot pair with itself")
	local p3, other =
		Awakening.noteSuper(Config, cb, { hero = 2, set = "Frost", x = 10, y = 0, z = 0, t = 2 })
	check(p3 ~= nil and p3.id == "Storm" and other ~= nil and other.hero == 1, "Frost + Volt = Storm")
	local p4 = Awakening.noteSuper(Config, cb, { hero = 3, set = "Pulse", x = 80, y = 0, z = 0, t = 2.5 })
	check(p4 == nil, "too far")
	local p5 = Awakening.noteSuper(Config, cb, { hero = 4, set = "Titan", x = 80, y = 0, z = 0, t = 6 })
	check(p5 == nil, "too late (the Pulse super expired)")
	local p6 = Awakening.noteSuper(
		Config,
		cb,
		{ hero = 5, set = "Blade", x = 82, y = 0, z = 0, t = 7 },
		function()
			return false
		end
	)
	check(p6 == nil, "flagged opponents never pair")
end)

-- A flat world with one wall at x = 40 (for range and line-of-sight)
local flatWorld: CastPlan.World = {
	los = function(ox, _, _, tx)
		return not ((ox < 40 and tx > 40) or (ox > 40 and tx < 40))
	end,
	rayDist = function(ox, _, _, dx, _, _, max)
		if dx > 0 and ox < 40 then
			return math.min(max, (40 - ox) / dx)
		end
		return max
	end,
	groundY = function()
		return 0
	end,
}

local function cand(id: number, x: number, y: number, z: number, flags: number?)
	return { id = id, x = x, y = y, z = z, r = 2.5, flags = flags }
end

local function ids(plan: any): { [number]: number }
	local out = {}
	for _, h in plan.hits do
		out[h.c.id] = h.coeff
	end
	return out
end

test("M2: cast plans: bolt, chain, dash, cone, arc, nova, line, splash and bonus", function()
	local E = function(id: string, rank: number?, mod: number?)
		return AbilityRules.effective(Config, id, rank or 1, mod)
	end
	local cands = { cand(1, 0, 2, -20), cand(2, 6, 2, -24), cand(3, 0, 2, 20), cand(4, 60, 2, -20) }
	local bolt = CastPlan.build(E("ZapBolt"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
	check(bolt.hits[1].c.id == 1 and #bolt.hits == 1, "bolt: the first along the aim")
	local chain = CastPlan.build(E("ChainLightning"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
	local c = ids(chain)
	check(c[1] and c[2] and not c[3], "chain jumps to the near one, not behind")
	check(chain.hits[1].primary and not chain.hits[2].primary, "only the first is primary")
	local dashCands = { cand(1, 0, 2, -10), cand(2, 0, 2, -40) }
	local dash = CastPlan.build(E("DashStrike"), 0, 2, 0, 0, 0, -1, 0, dashCands, flatWorld) :: any
	check(
		dash.moveHero and math.abs(dash.ez + 30) < 0.01 and ids(dash)[1] and not ids(dash)[2],
		"dash 30 studs, hits on the path"
	)
	local wallDash = CastPlan.build(E("DashStrike"), 30, 2, 0, 1, 0, 0, 0, {}, flatWorld) :: any
	check(wallDash.ex <= 37.01, "a dash stops 3 studs before a wall")
	local cone = CastPlan.build(E("ArcFlash"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
	check(ids(cone)[1] ~= nil and ids(cone)[3] == nil, "cone in front only")
	local punchCands = { cand(1, 0, 2, -6), cand(2, 3, 2, -7) }
	local p1 =
		CastPlan.build(E("PunchCombo"), 0, 2, 0, 0, 0, -1, 0, punchCands, flatWorld, { comboStep = 1 }) :: any
	local p3 =
		CastPlan.build(E("PunchCombo"), 0, 2, 0, 0, 0, -1, 0, punchCands, flatWorld, { comboStep = 3 }) :: any
	near(p1.hits[1].coeff, 0.7, 1e-9, "punch 1 = 0.7")
	near(p3.hits[1].coeff, 1.1, 1e-9, "the finisher = 1.1")
	check(#p1.hits == 2, "a punch hits everything in the arc")
	local hay = CastPlan.build(E("Haymaker"), 0, 2, 0, 0, 0, -1, 0, punchCands, flatWorld) :: any
	check(#hay.hits == 1, "Haymaker hits one")
	local far = { cand(1, 0, 2, -30), cand(2, 25, 2, 0) }
	local nova = CastPlan.build(E("FrostNova"), 0, 2, 0, 0, 0, -1, 0, far, flatWorld) :: any
	check(#nova.hits == 0, "nobody within 18")
	local near1 = { cand(1, 10, 2, 0), cand(2, -12, 2, 5), cand(3, 30, 2, 0) }
	nova = CastPlan.build(E("FrostNova"), 0, 2, 0, 0, 0, -1, 0, near1, flatWorld) :: any
	check(#nova.hits == 2, "nova hits all within 18")
	local slam = CastPlan.build(E("ThunderDrop"), 0, 60, 0, 0, 0, -1, 0, near1, flatWorld) :: any
	check(slam.moveHero and slam.cy < 3, "Thunder Drop dives to the ground first")
	local spark = CastPlan.build(E("GroundSpark"), 0, 2, 0, 0, -0.5, -0.8, 0, cands, flatWorld) :: any
	check(math.abs(spark.ey - 2) < 0.01, "Ground Spark runs flat along the street")
	local twin = CastPlan.build(E("GroundSpark", 5, 1), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
	check(twin.twin ~= nil, "Twin Spark adds a second line")
	local wave =
		CastPlan.build(E("CrescentWave"), 20, 2, -20, 1, 0, 0, 0, { cand(9, 70, 2, -20) }, flatWorld) :: any
	check(#wave.hits == 0 and wave.ex <= 40.01, "a line stops at a building")
	-- Shatter bonus vs slowed, splash capstone
	local slowed = { cand(1, 0, 2, -20, Status.BITS.slow), cand(2, 4, 2, -24) }
	local sh = CastPlan.build(E("Shatter", 5, 1), 0, 2, 0, 0, 0, -1, 0, slowed, flatWorld) :: any
	local m = ids(sh)
	local eff5 = E("Shatter", 5, 1)
	near(m[1], eff5.coeff * (1 + eff5.bonus), 1e-9, "Shatter hits a slowed target harder")
	check(m[2] ~= nil and m[2] < m[1], "Splinters splash the one next to it")
end)

test(
	"Paths: ride, launch and place plans; Trick Shot curves; field buffs; recasts and borrowed starters",
	function()
		local E = function(id: string, rank: number?, mod: number?)
			return AbilityRules.effective(Config, id, rank or 1, mod)
		end
		local cands = { cand(1, 0, 2, -5), cand(2, 0, 2, -30), cand(3, 60, 2, 0) }
		local ride = CastPlan.build(E("RockRide"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
		check(ride.ride == true, "Rock Ride rides")
		check(
			ids(ride)[1] ~= nil and ids(ride)[2] == nil,
			"its start burst hits only what is next to the hero"
		)
		local surf = CastPlan.build(E("WaveSurf"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
		check(surf.ride == true and #surf.hits == 0, "Wave Surf has no start burst")
		local pillar = CastPlan.build(E("StonePillar"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
		check(
			pillar.moveHero and pillar.ey == 2 + 55 and pillar.ex == 0 and pillar.ez == 0,
			"Stone Pillar goes straight up"
		)
		check(ids(pillar)[1] ~= nil, "and tosses the robot beside it")
		local stride = CastPlan.build(E("GiantStride"), 0, 2, 0, 1, 0, 0, 0, cands, flatWorld) :: any
		near(stride.ex, 40, 1e-6, "Giant Stride stops at the wall (70 forward, wall at 40)")
		local holo = CastPlan.build(E("HoloDecoy"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
		check(
			holo.cx == 0 and holo.cz == -30 and holo.cy == 1 and #holo.hits == 0,
			"Holo Decoy is set down 30 ahead"
		)
		-- Trick Shot ignores the wall between the hero and robot 3; a plain bolt does not
		local blocked = CastPlan.build(E("FlareShot"), 20, 2, 0, 1, 0, 0, 3, { cands[3] }, flatWorld) :: any
		check(#blocked.hits == 0, "a plain bolt is blocked by the wall")
		local trick = CastPlan.build(E("TrickShot"), 20, 2, 0, 1, 0, 0, 3, { cands[3] }, flatWorld) :: any
		check(#trick.hits == 1, "Trick Shot curves around it")
		local mech = CastPlan.build(E("MechSuit"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
		check(
			mech.field and mech.field.follow and mech.buff,
			"Mech Suit is a following field that also buffs"
		)
		local ring = CastPlan.build(E("EmberRing"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
		check(ring.field and not ring.buff, "a plain field does not buff")
		-- recasts: Sky Step has 4 steps before the cooldown
		local st = {}
		local sky = E("SkyStep")
		local got = {}
		for i = 1, 4 do
			table.insert(got, AbilityRules.afterUse(st, "SkyStep", sky, i * 0.5, 7))
		end
		check(
			got[1] == 0.35 and got[2] == 0.35 and got[3] == 0.35 and got[4] == 7,
			"Sky Step: 3 quick steps, then 7 s"
		)
		-- rank 2 scales the delayed burst, the hit field and the ride trail too
		near(E("Flashpoint", 2).delayCoeff, AB.list.Flashpoint.delayCoeff * 1.1, 1e-9, "delayed burst scales")
		near(E("Override", 2).hfCoeff, AB.list.Override.hfCoeff * 1.1, 1e-9, "Override's area scales")
		near(E("FlameJets", 2).trail, AB.list.FlameJets.trail * 1.1, 1e-9, "the ride trail scales")
		check(AbilityRules.isStarter(Config, "FreezeBeam"), "Freeze Beam is Frost's starter")
		check(not AbilityRules.isStarter(Config, "FreezeBeam", "Volt"), "but not free for a Storm hero")
		local ranks = { ChainLightning = 1, DashStrike = 1, FreezeBeam = 1 }
		check(AbilityRules.pointsSpent(Config, ranks, "Volt") == 1, "a borrowed starter counts a point")
		check(AbilityRules.pointsSpent(Config, ranks, "Frost") == 2, "on a Frost hero the Storm skills cost")
	end
)

test("M2: cast plans: channel, field, leap, throw, buff, wall, ramp", function()
	local E = function(id: string, rank: number?, mod: number?)
		return AbilityRules.effective(Config, id, rank or 1, mod)
	end
	local cands = { cand(1, 0, 2, -20) }
	local beam = CastPlan.build(E("FreezeBeam"), 0, 2, 0, 0, 0, -1, 0, cands, flatWorld) :: any
	check(
		beam.channel ~= nil and beam.channel.ids[1] == 1 and beam.channel.ticks == 12 and #beam.hits == 0,
		"Freeze Beam: 12 ticks on the target"
	)
	local cuts =
		CastPlan.build(E("ThousandCuts"), 0, 2, 0, 0, 0, -1, 0, { cand(1, 0, 2, -6) }, flatWorld) :: any
	check(cuts.channel ~= nil and cuts.channel.ticks == 8, "Thousand Cuts: 8 cuts")
	local well = CastPlan.build(E("GravityWell"), 0, 2, 0, 0, 0, -1, 0, {}, flatWorld) :: any
	check(
		well.field ~= nil and math.abs(well.field.z + 50) < 0.01 and not well.field.follow,
		"Gravity Well lands at the aim"
	)
	local storm = CastPlan.build(E("BladeStorm"), 0, 2, 0, 0, 0, -1, 0, {}, flatWorld) :: any
	check(storm.field.follow == true, "Blade Storm follows the hero")
	local leap = CastPlan.build(E("MeteorLeap"), 0, 2, 0, 0, 0, -1, 0, {}, flatWorld) :: any
	check(
		leap.moveHero and leap.delay == 1.1 and math.abs(leap.cz + 97) < 0.01,
		"Meteor Leap lands up to 100 away"
	)
	local throw =
		CastPlan.build(E("LiftAndThrow"), 0, 2, 0, 0, 0, -1, 0, { cand(7, 5, 2, 0) }, flatWorld) :: any
	check(throw.thrown == 7 and throw.delay == 0.5, "Lift and Throw lifts the robot next to the hero")
	local noGrab =
		CastPlan.build(E("LiftAndThrow"), 0, 2, 0, 0, 0, -1, 0, { cand(7, 50, 2, 0) }, flatWorld) :: any
	check(noGrab.thrown == nil, "nothing within 12: a placeholder crate")
	local buff = CastPlan.build(E("GlacierArmor"), 0, 2, 0, 0, 0, -1, 0, {}, flatWorld) :: any
	check(buff.buff == true, "buffs")
	local wall = CastPlan.build(E("SnowWall"), 0, 2, 0, 0, 0, -1, 0, {}, flatWorld) :: any
	check(#wall.pieces == 3, "3 wall pieces")
	local wall5 = CastPlan.build(E("SnowWall", 3, 1), 0, 2, 0, 0, 0, -1, 0, {}, flatWorld) :: any
	check(#wall5.pieces == 5, "Five Pieces mod")
	local ramp = CastPlan.build(E("IceSlide"), 0, 2, 0, 0, 0, -1, 0, {}, flatWorld) :: any
	check(#ramp.pieces == 1, "one ramp")
end)

-- A street grid for robots: buildings fill x 20..40 (height 30); everything else is street
local function cityHeight(x: number, z: number): number
	if x >= 20 and x <= 40 and z >= -100 and z <= 100 then
		return 30
	end
	return 0
end

local function robotSim()
	return EnemySim.new(Config, { heightAt = cityHeight })
end

local function run(sim: any, heroes: { any }, from: number, to: number, onEvent: ((any) -> ())?)
	local t = from
	while t < to do
		t += 0.05
		EnemySim.step(sim, t, heroes)
		for _, ev in EnemySim.drainEvents(sim) do
			if onEvent then
				onEvent(ev)
			end
		end
	end
	return t
end

test("M2: robots: every kind spawns as the right brain; ground robots stand on the street", function()
	local sim = robotSim()
	for i, kind in Config.Enemies.order do
		local e = EnemySim.spawn(sim, kind, -50 - i * 10, 30, 0, 1) :: any
		check(e ~= nil and e.ai == Config.Enemies[kind].ai, kind .. " brain")
		if e.ai ~= "flyer" then
			near(e.y, EnemySim.halfHeight(e.cfg), 1e-6, kind .. " stands on the ground")
		end
		check(Config.Enemies[kind].body ~= nil, kind .. " has a humanoid robot body")
	end
end)

test("Body sets: 8 sets keyed by gender and build, Blender in step with the creator's factors", function()
	local BodyShape = require("../src/shared/BodyShape")
	local RigMath = require("../src/shared/RigMath")
	local B = Config.Creator.body
	check(#B.builds == 4 and #B.genders == 2, "4 builds and 2 genders: 8 body sets")
	local keys = {}
	for g = 1, 2 do
		for b = 1, #B.builds do
			local key = BodyShape.setKey(Config, { gender = g, build = b, height = 3 })
			check(keys[key] == nil, key .. " is its own set")
			keys[key] = true
			check(key == B.genders[g] .. B.builds[b].name, key .. " names its gender and build")
		end
	end
	check(BodyShape.setKey(Config, {}) == "MaleMedium", "a look with no body is the hero body (MaleMedium)")
	check(
		BodyShape.setKey(Config, { gender = 2, build = 9 }) == "FemaleMedium",
		"a bad build falls back to Medium"
	)
	-- art/blender/bodies.py sizes its preview with the same numbers (width, depth, limbs, hands, head, tall)
	local py = require("@lune/fs").readFile("art/blender/bodies.py")
	for _, b in B.builds do
		local row = string.match(py, '"' .. b.name .. '": %(([^)]*)%)')
		check(row ~= nil, "bodies.py has the " .. b.name .. " factors")
		local nums = {}
		for n in string.gmatch(row or "", "[%d%.]+") do
			table.insert(nums, tonumber(n))
		end
		local want = { b.width, b.depth, b.limbs, b.hands, b.head, b.tall }
		for i, v in want do
			near(nums[i] or -1, v, 1e-9, b.name .. " factor " .. i .. " matches Config.Creator")
		end
	end
	local waist = tonumber(string.match(py, "FEMALE_WAIST = ([%d%.]+)"))
	near(waist or -1, B.femaleWaist, 1e-9, "bodies.py female waist matches Config.Creator")
	-- citizens wear sets too: every citizen body is a real gender and build, and its rig stands
	local C = Config.Destruction.citizens
	check(#C.bodies >= 2, "citizens come in more than one body")
	local women = 0
	for i, b in C.bodies do
		check(b[1] == 1 or b[1] == 2, "citizen body " .. i .. " has a gender")
		check(B.builds[b[2]] ~= nil, "citizen body " .. i .. " has a build")
		women += if b[1] == 2 then 1 else 0
		local lay = RigMath.layout(
			Config.HeroRig,
			BodyShape.factors(Config, { gender = b[1], build = b[2], height = 3 }),
			1
		)
		check(lay.ground > 0 and lay.ground < lay.height, "citizen body " .. i .. " stands on its feet")
	end
	check(women * 2 == #C.bodies, "half the citizen bodies are women")
end)

test("Everyone on R15: robots and citizens use the heroes' rig, joints and attachments", function()
	local RigMath = require("../src/shared/RigMath")
	local BodyShape = require("../src/shared/BodyShape")
	local hero = RigMath.layout(Config.HeroRig, nil, 1)
	check(#hero.joints == 15, "the 15 R15 Motor6Ds")
	local seen = {}
	for _, j in hero.joints do
		seen[j.part1] = true
	end
	for _, part in BodyShape.PARTS do
		check(seen[part] == true and hero.parts[part] ~= nil, part .. " is jointed")
	end
	near(hero.ground, Config.HeroRig.root.centre[2], 1e-6, "the standard root stands where the hero's does")
	near(hero.hip, Config.HeroRig.root.centre[2] - 2, 1e-6, "the hips under the root")
	for name, def in Config.HeroRig.parts do
		for k = 1, 3 do
			local rest = hero.centres[name][k] + Config.HeroRig.root.centre[k]
			near(rest, def.centre[k], 1e-3, name .. " rests where the hero body has it")
		end
	end
	local L = Config.Enemies.look
	for _, kind in Config.Enemies.order do
		local body = Config.Enemies[kind].body
		check(L.builds[body.build] ~= nil, kind .. " build has a creator build")
		local f = BodyShape.factors(Config, { gender = 1, build = L.builds[body.build], height = 3 })
		local base = RigMath.layout(Config.HeroRig, f, 1)
		local lay = RigMath.layout(Config.HeroRig, f, body.height / base.height)
		near(lay.height, body.height, 1e-6, kind .. " is drawn its height")
		check(lay.ground > 0 and lay.ground < lay.height, kind .. " root sits inside the body")
	end
end)

test("Robots: the shell breaks off with damage, the same way on every device", function()
	local RobotDamage = require("../src/shared/RobotDamage")
	local L = Config.Enemies.look
	local pieces = {}
	for name, tier in L.tiers do
		table.insert(pieces, { name = name, tier = tier })
	end
	table.sort(pieces, function(a, b)
		return a.name < b.name
	end)
	local a = RobotDamage.order(42, pieces, L.spread)
	local b = RobotDamage.order(42, pieces, L.spread)
	check(#a == #pieces, "every piece is in the order")
	check(table.concat(a, ",") == table.concat(b, ","), "the same id breaks the same way")
	local differ = false
	for id = 1, 20 do
		if table.concat(RobotDamage.order(id, pieces, L.spread), ",") ~= table.concat(a, ",") then
			differ = true
		end
	end
	check(differ, "robots break in different orders")
	-- the head goes late: the Head (tier 3.5) never before a limb (tier 1) with spread 1.5
	for id = 1, 200 do
		local o = RobotDamage.order(id, pieces, L.spread)
		local at = {}
		for i, n in o do
			at[n] = i
		end
		check(at.Head > at.LeftUpperArm and at.Head > at.RightLowerLeg, "the head goes after the limbs")
	end
	-- the shell is the R15 body: every one of its 15 parts can break, plus the hair and cape
	for _, part in require("../src/shared/BodyShape").PARTS do
		check(L.tiers[part] ~= nil, part .. " is a shell piece")
	end
	local n = #pieces
	check(RobotDamage.count(1, n, L.stripBy) == 0, "full health: shell whole")
	check(RobotDamage.count(0.97, n, L.stripBy) == 0, "a scratch breaks nothing")
	check(RobotDamage.count(0.9, n, L.stripBy) >= 1, "a few hits show the first metal")
	check(RobotDamage.count(1 - L.stripBy, n, L.stripBy) == n, "nearly beaten: all endoskeleton")
	check(RobotDamage.count(0, n, L.stripBy) == n, "defeated: all gone")
	local last = 0
	for h = 100, 0, -1 do
		local c = RobotDamage.count(h / 100, n, L.stripBy)
		check(c >= last, "never grows back as health falls")
		last = c
	end
	local br = RobotDamage.broken(a, 0.5, L.stripBy)
	local k = 0
	for _ in br do
		k += 1
	end
	check(k == RobotDamage.count(0.5, n, L.stripBy), "broken set matches the count")
	for _, kind in Config.Enemies.order do
		local body = Config.Enemies[kind].body
		check(body.suit ~= nil and body.trim ~= nil, kind .. " wears a uniform")
	end
	check(#L.skins >= 4 and #L.hair >= 3, "skin and hair variety")
end)

test("M2: Burglar Bot runs, then turns and fires when cornered", function()
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "BurglarBot", 0, 0, 0, 1) :: any
	local hero = { id = 1, x = -40, y = 3, z = 0, alive = true }
	run(sim, { hero }, 0, 1)
	check(e.state == EnemySim.FLEE and e.x > 0, "runs away from the hero")
	check(e.x <= 20, "never walks into the building")
	local shots = 0
	hero.x = e.x - 10
	run(sim, { hero }, 1, 5, function(ev)
		if ev.k == "shot" then
			shots += 1
		end
	end)
	check(shots >= 2, string.format("cornered against the wall it fires (%d)", shots))
end)

test("M2: Sneak Bot cloaks, circles behind and backstabs for more", function()
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "SneakBot", -60, 0, 0, 1) :: any
	local hero = { id = 1, x = -60, y = 3, z = -40, alive = true, lx = 0, lz = 1 } -- facing the sneak
	local sawCloak, stabs, back = false, 0, 0
	run(sim, { hero }, 0, 12, function(ev)
		if ev.k == "swing" then
			stabs += 1
			if ev.back then
				back += 1
			end
		end
	end)
	sawCloak = e.nextCloak > 0
	check(sawCloak, "cloaked on the approach")
	check(stabs >= 2, string.format("it stabs (%d)", stabs))
	check(back >= 1, "at least one from behind")
	local front = EnemySim.spawn(sim, "SneakBot", 0, 0, 0, 1) :: any
	local h2 = { id = 2, x = 0, y = 3, z = -4, alive = true, lx = 0, lz = 1 }
	local dmgBack, dmgFront = 0, 0
	front.nextMelee = 0
	front.nextCloak = math.huge
	run(sim, { h2 }, 12, 12.2, function(ev)
		if ev.k == "hit" and ev.hero == 2 then
			dmgFront = ev.damage
		end
	end)
	h2.lz = -1 -- now its back is to the robot
	front.nextMelee = 0
	run(sim, { h2 }, 12.2, 12.4, function(ev)
		if ev.k == "hit" and ev.hero == 2 then
			dmgBack = ev.damage
		end
	end)
	check(
		dmgBack > dmgFront * 2,
		string.format("a backstab (%.0f) beats a front stab (%.0f)", dmgBack, dmgFront)
	)
end)

test("M2: Brute Bot warns 0.8 s, then slams; stepping out or a stun beats it", function()
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "BruteBot", -60, 0, 0, 1) :: any
	local hero = { id = 1, x = -66, y = 3, z = 0, alive = true }
	local warned, hits = nil, 0
	run(sim, { hero }, 0, 2.2, function(ev)
		if ev.k == "warn" then
			warned = ev
		elseif ev.k == "hit" then
			hits += 1
		end
	end)
	check(
		warned ~= nil and warned.r == 8 and math.abs(warned.t - 0.8) < 1e-9,
		"a 0.8 s warning ring of radius 8"
	)
	check(hits == 1, "standing in it gets slammed")
	-- dodge: leave during the windup
	e.nextMelee = 0
	hits = 0
	local t = run(sim, { hero }, 2.2, 2.35)
	check(e.windupUntil > 0, "winding up again")
	hero.x = -90
	run(sim, { hero }, t, t + 1, function(ev)
		if ev.k == "hit" then
			hits += 1
		end
	end)
	check(hits == 0, "stepping out of the ring dodges")
	-- a stun interrupts
	hero.x = -66
	e.x, e.z = -60, 0
	e.nextMelee = 0
	t = run(sim, { hero }, 5, 5.15)
	EnemySim.applyStatus(sim, e.id, "stun", 1)
	check(e.windupUntil == 0, "a stun cancels the slam")
	local killed, _, dealt = EnemySim.damage(sim, e.id, 100, 1)
	check(not killed and math.abs(dealt - 80) < 1e-6, "Brute takes 20% less")
	check(EnemySim.applyStatus(sim, e.id, "root", 1) < 1, "Brute resists crowd control")
end)

test("M2: Sentry turns 90 degrees/s, fires when lined up, its shield blocks", function()
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "Turret", 0, 0, 0, 1) :: any
	e.yaw = 0 -- facing -Z
	e.nextShield = math.huge
	local hero = { id = 1, x = 0, y = 3, z = 40, alive = true } -- behind it
	local shots = 0
	run(sim, { hero }, 0, 1, function(ev)
		if ev.k == "shot" then
			shots += 1
		end
	end)
	check(shots == 0, "it needs 2 s to turn around")
	run(sim, { hero }, 1, 3, function(ev)
		if ev.k == "shot" then
			shots += 1
		end
	end)
	check(shots >= 1, "then it fires")
	check(e.x == 0 and e.z == 0, "planted")
	check(not EnemySim.knock(sim, e.id, 1, 0, 10) and e.x == 0, "cannot be knocked back")
	check(EnemySim.applyStatus(sim, e.id, "float", 2) == 0, "cannot be floated")
	e.shieldUntil = sim.now + 1
	local _, _, dealt, flag = EnemySim.damage(sim, e.id, 50, 1)
	check(dealt == 0 and flag == EnemySim.BLOCKED, "the shield blocks")
end)

test("M2: Null Sentinel blocks from the front; a flank hit breaks the guard", function()
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "NullSentinel", 0, 0, 0, 1) :: any
	e.yaw = 0 -- facing -Z
	local _, _, front, f1 = EnemySim.damage(sim, e.id, 100, 1, 0, -20)
	check(f1 == EnemySim.BLOCKED and math.abs(front - 20) < 1e-6, "front hits lose 80%")
	local _, _, side, f2 = EnemySim.damage(sim, e.id, 100, 1, 20, 0)
	check(f2 == EnemySim.BROKE and math.abs(side - 100) < 1e-6, "a flank hit breaks it")
	check(Status.has(e.status, "stun", sim.now), "and staggers it")
	local _, _, after, f3 = EnemySim.damage(sim, e.id, 100, 1, 0, -20)
	check(f3 == EnemySim.HIT and math.abs(after - 100) < 1e-6, "broken: front hits land in full")
end)

test(
	"M2: crowd control on robots: knockback stops at walls, pull, knockup, taunt, blind, blockers",
	function()
		local sim = robotSim()
		local e = EnemySim.spawn(sim, "BurglarBot", 10, 0, 0, 1) :: any
		check(EnemySim.knock(sim, e.id, 1, 0, 30), "knocked into the building: hit a wall")
		check(e.x < 20, "stopped at the wall")
		local d = EnemySim.spawn(sim, "SparkDrone", -60, 30, 0, 1) :: any
		EnemySim.applyStatus(sim, d.id, "pull", 2, { x = -100, y = 30, z = 0, speed = 40 })
		run(sim, {}, 0, 1)
		check(d.x < -90, "pulled toward the point")
		local g = EnemySim.spawn(sim, "BruteBot", -60, 0, 40, 1) :: any
		EnemySim.applyStatus(sim, g.id, "knockup", 1)
		local t = run(sim, {}, 1, 1.35)
		check(g.y > EnemySim.halfHeight(g.cfg) + 2, "knocked up into the air")
		run(sim, {}, t, 3)
		near(g.y, EnemySim.halfHeight(g.cfg), 1e-6, "and back on the ground")
		-- taunt beats distance
		local h1 = { id = 1, x = -60, y = 3, z = 45, alive = true }
		local h2 = { id = 2, x = -60, y = 3, z = 80, alive = true }
		EnemySim.applyStatus(sim, g.id, "taunt", 3, { src = 2 })
		run(sim, { h1, h2 }, 3, 3.3)
		check(g.target == 2, "taunted onto the Bruiser")
		-- Snow Wall blocks a shot
		local s2 = robotSim()
		local shooter = EnemySim.spawn(s2, "SparkDrone", -100, 20, 0, 1) :: any
		shooter.nextBurst = 0
		local hero = { id = 1, x = -140, y = 18, z = 0, alive = true }
		EnemySim.addBlocker(s2, -120, 20, 0, 5, 100)
		local hits, blocked = 0, 0
		run(s2, { hero }, 0, 3, function(ev)
			if ev.k == "hit" then
				hits += 1
			elseif ev.k == "blocked" then
				blocked += 1
			end
		end)
		check(blocked >= 1, string.format("the wall stops shots (%d blocked, %d hit)", blocked, hits))
	end
)

test("M2: Enemy.Delta carries status flags and facing (12 bytes each)", function()
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "NullSentinel", -60, 0, 0, 1) :: any
	e.yaw = 1.0
	EnemySim.applyStatus(sim, e.id, "slow", 2, { value = 0.5 })
	run(sim, {}, 0, 0.2)
	local b = EnemyBuffer.encodeFor(1, 0, sim.enemies, -60, 0, 0, 100, 60)
	check(buffer.len(b) == EnemyBuffer.HEADER + 12, "12 bytes")
	local _, _, rows = EnemyBuffer.decode(b)
	local r = rows[1]
	check(bit32.band(r.flags, Status.BITS.slow) ~= 0, "slow flag")
	check(bit32.band(r.flags, Status.BITS.shield) ~= 0, "guard up shows as shield")
	check(math.abs(r.yaw - (e.yaw % (2 * math.pi))) < 0.03, "facing survives")
	check(r.typeId == 6, "type")
end)

test("M2: populate mixes the robot kinds and keeps ground robots on streets", function()
	local sim = robotSim()
	local heroes = {}
	for i = 1, 20 do
		table.insert(heroes, { id = i, x = -200 + i * 3, y = 5, z = -150 + i * 15, alive = true })
	end
	local now = 0
	for _ = 1, 400 do
		now += 0.1
		EnemySim.populate(sim, heroes, now)
		EnemySim.step(sim, now, heroes)
		EnemySim.drainEvents(sim)
	end
	local kinds, onRoof = {}, 0
	for _, e in sim.enemies do
		kinds[e.kind] = true
		if e.ai ~= "flyer" and cityHeight(e.x, e.z) > 1 then
			onRoof += 1
		end
	end
	local n = 0
	for _ in kinds do
		n += 1
	end
	check(n >= 4, string.format("a mix of kinds (%d)", n))
	check(onRoof == 0, "no ground robot inside a building")
	check(EnemySim.count(sim) <= Config.Enemies.caps.perServer, "cap holds")
end)

test("M2: balance: classes keep their roles; a level 10 Burglar Bot falls in 2 to 3 s", function()
	local hp = Formulas.enemyHealth(Config, "BurglarBot", 10)
	local power = Formulas.power(Config, 10)
	for _, set in AB.sets do
		local basic = AbilityRules.basicOf(Config, set) :: string
		local a = AB.list[basic]
		local avg = if a.hits
			then (function()
				local s = 0
				for _, h in a.hits do
					s += h
				end
				return s / #a.hits
			end)()
			else a.coeff
		local function dps(classId: string): number
			return Formulas.damage(Config, power, avg, classId) / a.cd
		end
		check(dps("Elemental") > dps("Powerhouse"), set .. ": a Bruiser never out-damages a Blaster")
		for _, cls in Config.Classes.order do
			local t = hp / dps(cls)
			-- Push Wave is a cone that hits a crowd, so it is the slowest on one target
			local most = if a.shape == "cone" then 3.8 else 3.2
			check(t >= 1.6 and t <= most, string.format("%s %s kills a L10 Burglar in %.1f s", set, cls, t))
		end
	end
	check(
		Formulas.health(Config, 10, 0, "Powerhouse") > Formulas.health(Config, 10, 0, "Elemental"),
		"a Blaster never out-tanks a Bruiser"
	)
	local zapT = hp / (Formulas.damage(Config, power, AB.list.ZapBolt.coeff, "Elemental") / 0.5)
	check(zapT >= 2 and zapT <= 3, string.format("Blaster Zap: %.2f s (spec 2 to 3)", zapT))
	-- total coefficient of one use (channels and fields add up their ticks)
	local function total(a: any): number
		local n = 1
		if a.channel then
			n = a.channel -- channel is a tick count
		elseif a.shape == "field" and a.duration then
			n = math.floor(a.duration / (a.tick or 1) + 0.5)
		elseif a.hits then
			local sum = 0
			for _, h in a.hits do
				sum += h
			end
			return sum * a.coeff
		end
		return a.coeff * n + (a.endCoeff or 0)
	end
	-- supers are the big moments: at least 3.5x power in total, on a long cooldown
	for _, set in AB.sets do
		local sup = AB.list[AbilityRules.superOf(Config, set) :: string]
		check(
			total(sup) >= 3.5 and sup.cd >= 80,
			string.format("%s super deals %.1f in total every %d s", set, total(sup), sup.cd)
		)
	end
end)

---------------------------------------------------------------------------
-- M3: gear, loot, saves, levels, Renown, Credits
---------------------------------------------------------------------------

local GearMath = require("../src/shared/GearMath")
local LootTable = require("../src/shared/LootTable")
local Progress = require("../src/shared/Progress")
local ProfileSchema = require("../src/shared/ProfileSchema")
local Inventory = require("../src/shared/Inventory")
local GC = Config.Gear

test("M3: piece budget, main stat share, upgrades and costs match the spec", function()
	check(GearMath.baseBudget(Config, "hands", "Common", 40) == 60, "Common ilvl 40 = 60")
	check(GearMath.baseBudget(Config, "hands", "Legendary", 40) == 105, "Legendary ilvl 40 = 105")
	check(GearMath.baseBudget(Config, "gadget", "Epic", 40) == 0, "gadgets have no stats")
	local rng = Rng.new(7)
	local c = GearMath.roll(Config, rng, "Common", 20, { slot = "hands" })
	check(#c.bonus == 0 and c.main == 30, "Common: main stat only, the whole budget")
	local r = GearMath.roll(Config, rng, "Rare", 40, { slot = "head" })
	check(#r.bonus == 2 and r.main == 55, "Rare: main 70% of 78 = 55, plus 2 bonus stats")
	check(r.bonus[1][2] + r.bonus[2][2] == 78 - 55, "bonus stats split the rest exactly")
	check(r.bonus[1][1] ~= r.bonus[2][1], "two different bonus stats")
	local mainIdx = table.find(GC.stats, "Precision")
	check(r.bonus[1][1] ~= mainIdx and r.bonus[2][1] ~= mainIdx, "bonus never repeats the main stat")
	check(GearMath.stats(Config, r).Precision == 55, "head main stat is Precision")
	local common = GearMath.roll(Config, rng, "Common", 10, { slot = "belt" })
	common.up = 4
	check(GearMath.upgradeCost(Config, common) == 134, "+5 on a Common costs 134")
	common.up = 9
	-- round(12 x 10^1.5) = 379; the spec's text says 380 (Decisions.md: the formula wins)
	check(GearMath.upgradeCost(Config, common) == 379, "+10 on a Common costs 379")
	common.up = 10
	check(GearMath.upgradeCost(Config, common) == nil, "no step past +10")
	local s = GearMath.roll(Config, rng, "Common", 40, { slot = "feet" })
	s.up = 10
	check(GearMath.budget(Config, s) == 84, "+10 is +40% budget")
	check(GearMath.stats(Config, s).Focus == 84, "and +40% stats")
	local legend = GearMath.roll(Config, rng, "Legendary", 40, { slot = "chest" })
	check(GearMath.salvageValue(Config, legend) == 160, "Legendary ilvl 40 salvages for 80 x 2 = 160 Dust")
	check(GearMath.retuneCost(Config, legend) == 1400, "retune 800 x 1.75")
	check(legend.perk > 0 and legend.set == 0, "Legendary has a perk, no set")
	local epic = GearMath.roll(Config, rng, "Epic", 30, { slot = "hands" })
	check(epic.set > 0 and epic.perk == 0, "Epic hands belong to a set")
	local epicBack = GearMath.roll(Config, rng, "Epic", 30, { slot = "back" })
	check(epicBack.set == 0, "sets are head, chest, hands and feet only")
	local gadget = GearMath.roll(Config, rng, "Rare", 30, { gadget = true })
	check(
		gadget.gadget > 0 and gadget.main == 0 and #gadget.bonus == 0,
		"a gadget piece holds a gadget, no stats"
	)
	-- a full level 40 Legendary kit is about 840 points with a few upgrades (spec), Might ~ +63% Power
	local kit = {}
	for _, slot in { "head", "chest", "hands", "legs", "feet", "back", "belt" } do
		local p = GearMath.roll(Config, Rng.new(#kit + 1), "Legendary", 42, { slot = slot })
		p.up = 4
		table.insert(kit, p)
	end
	local t = GearMath.totals(Config, kit)
	check(
		t.gearScore > 780 and t.gearScore < 920,
		string.format("full Legendary at 42 +4 = %d gear score", t.gearScore)
	)
	check(t.stats.Might >= 150, string.format("Might %d from hands and belt", t.stats.Might))
end)

test("M3: item level, wear level, retune rules", function()
	local rng = Rng.new(3)
	local lo, hi = 99, 0
	for _ = 1, 500 do
		local il = GearMath.itemLevel(Config, rng, 20)
		lo, hi = math.min(lo, il), math.max(hi, il)
	end
	check(lo == 18 and hi == 22, "ilvl = zone level +- 2")
	check(GearMath.itemLevel(Config, Rng.new(1), 1) >= 1, "never below 1")
	local p = GearMath.roll(Config, rng, "Rare", 25, { slot = "legs" })
	check(
		GearMath.canWear(Config, 20, p) and not GearMath.canWear(Config, 19, p),
		"wear up to hero level + 5"
	)
	local before = p.bonus[1][1]
	local value = p.bonus[1][2]
	for _ = 1, 3 do
		check(GearMath.retune(Config, rng, p, 1), "retune works")
		check(
			p.bonus[1][1] ~= p.bonus[2][1] and p.bonus[1][1] ~= table.find(GC.stats, "Resolve"),
			"still distinct"
		)
		check(p.bonus[1][2] == value, "the value stays")
	end
	check(not GearMath.retune(Config, rng, p, 1), "locked after 3 retunes")
	check(before ~= nil, "had a bonus")
end)

test("M3: sets and perks: 2-piece damage, 4-piece ability change, perks listed", function()
	local rng = Rng.new(11)
	local worn = {}
	for _, slot in GC.setSlots do
		local p = GearMath.roll(Config, rng, "Epic", 30, { slot = slot })
		p.set = 1 -- Stormcaller
		table.insert(worn, p)
	end
	local two = GearMath.totals(Config, { worn[1], worn[2] })
	check(two.setDamage.Volt == 0.08 and two.abilityMods.ChainLightning == nil, "2 pieces: Volt +8%")
	local four = GearMath.totals(Config, worn)
	check(four.abilityMods.ChainLightning ~= nil, "4 pieces change Chain Lightning")
	local eff = AbilityRules.effective(Config, "ChainLightning", 1, nil, four.abilityMods.ChainLightning)
	check(eff.targets == 5, "Chain Lightning hits 2 more")
	local leg = GearMath.roll(Config, rng, "Legendary", 30, { slot = "back" })
	leg.perk = table.find(GC.perkOrder, "LuckyStrike") :: number
	local t = GearMath.totals(Config, { leg })
	check(t.perks.LuckyStrike == true, "perk listed")
	for _, name in GC.setOrder do
		local row = GC.sets[name]
		check(Config.Abilities.list[row.four.ability] ~= nil, name .. " 4-piece names a real ability")
		check(
			Config.Abilities.list[row.four.ability].set == row.power,
			name .. " 4-piece is its own set's power"
		)
	end
	check(#GC.perkOrder == 8 and #GC.gadgetOrder == 4, "8 perks, 4 gadgets")
end)

test("M3: styles: ids are unique, every piece gets one of its slot, collection list", function()
	local seen = {}
	for _, id in GearMath.allStyles(Config) do
		check(not seen[id], "unique style " .. id)
		seen[id] = true
		check(id > 0 and id < 512, "fits the 512-bit set")
		check(GearMath.styleRow(Config, id) ~= nil, "style row " .. id)
	end
	local rng = Rng.new(5)
	for i = 1, 300 do
		local tier = GC.tierOrder[1 + i % 5]
		local p = GearMath.roll(Config, rng, tier, 30)
		if p.style > 0 then
			check((GearMath.styleParts(p.style)) == p.slot, "style matches the slot")
			check(seen[p.style] == true, "a known style")
		end
	end
end)

local function oddsCheck(source: string, n: number)
	local rng = Rng.new(Rng.hash(#source, 99))
	local counts, pieces, dropped = {}, 0, 0
	for _ = 1, n do
		local tiers = LootTable.roll(Config, rng, source, { level = 40, noPity = true })
		if #tiers > 0 then
			dropped += 1
		end
		for _, t in tiers do
			counts[t] = (counts[t] or 0) + 1
			pieces += 1
		end
	end
	return counts, pieces, dropped
end

test("M3: every drop source matches its table over 10,000 rolls (within 1%)", function()
	for _, source in Config.Loot.order do
		local src = Config.Loot.sources[source]
		local counts, pieces, dropped = oddsCheck(source, 10000)
		if src.chance then
			near(dropped / 10000, src.chance, 0.01, source .. " drop chance")
		end
		if src.odds then
			local total = 0
			for _, w in src.odds do
				total += w
			end
			for tier, w in src.odds do
				local want = w / total
				local got = (counts[tier] or 0) / pieces
				near(
					got,
					want,
					0.01,
					string.format("%s %s %.1f%% (table %.1f%%)", source, tier, got * 100, want * 100)
				)
			end
		end
		if src.mvp then
			near((counts.Legendary or 0) / pieces, src.legendary, 0.01, "MVP Legendary 8%")
			check((counts.Epic or 0) + (counts.Legendary or 0) == pieces, "MVP always Epic or better")
		end
		if src.fixed then
			check(pieces == 10000 * #src.fixed, source .. " fixed pieces")
		end
	end
end)

test("M3: pity: the 5th boss with no Epic gives one; the 15th MVP roll gives a Legendary", function()
	-- a generator that never rolls high: every boss piece would be Rare and no MVP Legendary
	local low = {
		next = function()
			return 0.0
		end,
		int = function(_, lo, _)
			return lo
		end,
	}
	local pity = { epic = 0, legendary = 0 }
	for i = 1, 4 do
		local t = LootTable.roll(Config, low, "bossParticipant", { level = 40, pity = pity })
		check(t[1] == "Rare", "boss " .. i .. ": Rare")
	end
	check(pity.epic == 4, "4 misses counted")
	local t5 = LootTable.roll(Config, low, "bossParticipant", { level = 40, pity = pity })
	check(t5[1] == "Epic" and pity.epic == 0, "the 5th is Epic and resets")
	-- and one that never hits the 8% Legendary roll
	local high = {
		next = function()
			return 0.99
		end,
		int = function(_, _, hi)
			return hi
		end,
	}
	for i = 1, 14 do
		local t = LootTable.roll(Config, high, "bossMvp", { level = 40, pity = pity })
		check(t[1] == "Epic", "MVP " .. i .. ": Epic")
	end
	local t15 = LootTable.roll(Config, high, "bossMvp", { level = 40, pity = pity })
	check(t15[1] == "Legendary" and pity.legendary == 0, "the 15th MVP roll is Legendary")
end)

test("M3: level gates: Epic from 20, Legendary from 30; fixed story rewards skip the gate", function()
	check(
		LootTable.gate(Config, "Epic", 19) == "Rare" and LootTable.gate(Config, "Epic", 20) == "Epic",
		"Epic gate"
	)
	check(LootTable.gate(Config, "Legendary", 25) == "Epic", "Legendary falls to Epic")
	check(LootTable.gate(Config, "Legendary", 10) == "Rare", "and to Rare below 20")
	local t = LootTable.roll(Config, Rng.new(1), "storyFinale", { level = 12 })
	check(t[1] == "Rare" and t[2] == "Epic", "the Act 1 finale Epic is not gated")
	local mvp = LootTable.roll(Config, Rng.new(1), "bossMvp", { level = 15 })
	check(mvp[1] == "Rare", "a level 15 MVP gets a Rare")
	check(
		#LootTable.infoRows(Config) == #Config.Loot.order + 2,
		"Loot Info lists every source plus pity and gates"
	)
end)

test("M3: levels: xpToNext, cumulative 68,400 to 40, level ups and the cap", function()
	check(Progress.xpToNext(Config, 1) == 100 and Progress.xpToNext(Config, 2) == 112, "100, 112")
	local total = Progress.totalTo(Config, 40)
	near(total, 68400, 68400 * 0.01, string.format("level 40 takes %d Renown", total))
	local lv, xp, gained = Progress.addRenown(Config, 1, 0, 250)
	check(lv == 3 and xp == 38 and gained == 2, "250 Renown: level 3 with 38 over")
	local cap, capXp = Progress.addRenown(Config, 39, 0, 1e7)
	check(cap == 40 and capXp == 0, "stops at 40")
	check(select(1, Progress.nextUnlock(1)) == 3, "next unlock after 1 is Flight at 3")
	check(Progress.nextUnlock(40) == nil, "nothing after 40")
end)

test("M3: earnings: zone level formulas, bonuses multiply, the stack caps at x4", function()
	local sc = Config.Economy.scale -- the M9 balance knobs over the spec formulas
	local function round(x: number): number
		return math.floor(x + 0.5)
	end
	local c, r = Progress.earn(Config, "incident", 10)
	check(
		c == round(35 * sc.credits) and r == round(45 * sc.renown),
		"incident at zone 10: 35 Credits, 45 Renown"
	)
	local c2, r2 = Progress.earn(Config, "incident", 10, { friends = 5 })
	check(
		c2 == round(35 * 1.3 * sc.credits) and r2 == round(45 * 1.3 * sc.renown),
		"friend boost caps at +30%"
	)
	near(
		Progress.multiplier(
			Config,
			{ friends = 3, legacy = 5, faction = 5, firstContract = true, doublePass = true }
		),
		4,
		1e-9,
		"x4 cap"
	)
	near(Progress.multiplier(Config, { legacy = 2, faction = 1 }), 1.2 * 1.02, 1e-9, "bonuses multiply")
	local cur = { credits = 50, banked = 100, dust = 0 }
	check(Progress.spend(cur, 120) and cur.credits == 0 and cur.banked == 30, "on hand first, then banked")
	check(not Progress.spend(cur, 31) and cur.banked == 30, "short: nothing taken")
	-- a fully ranked 5-skill build costs about 35,000 Credits (spec)
	local skill, super = 0, 0
	for _, v in Config.Abilities.rankCredits do
		skill += v
	end
	for _, v in Config.Abilities.superRankCredits do
		super += v
	end
	check(skill == 5550 and super == 3600, "5,550 per skill, 3,600 per super")
	near(skill * 5 + super, 35000, 4000, "a ranked 5-skill build plus super is about 35,000")
end)

test("M3: profile: defaults, migrations, repair of bad data, size under 60 KB", function()
	local p = ProfileSchema.default()
	check(p.version == ProfileSchema.VERSION and #p.characters == 1, "default has one character")
	local loaded = ProfileSchema.load(nil)
	check(loaded.version == ProfileSchema.VERSION, "nil loads a fresh profile")
	local old = { stash = { { id = 4, slot = 3, tier = 2, ilvl = 10, main = 9, bonus = { { 2, 3 } } } } }
	local m = ProfileSchema.load(old)
	check(m.version == ProfileSchema.VERSION, "a version 0 save migrates")
	check(
		#m.stash == 1 and m.stash[1].up == 0 and m.nextPieceId == 5,
		"pieces repaired, next id past the max"
	)
	check(#m.characters == 1 and m.characters[1].level == 1, "missing characters get a fresh one")
	local bad = {
		version = 1,
		currency = { credits = "lots", banked = -5, dust = 0 / 0 },
		characters = {
			{ level = 99, ranks = { ZapBolt = 9, [5] = 1 }, equipment = { 77, 0, 0 }, fxStyle = "x" },
			"junk",
		},
		stash = { { id = 1, slot = 1 }, { id = 1, slot = 1 }, "junk", { id = -3 } },
		active = 7,
	}
	local r = ProfileSchema.load(bad)
	check(
		r.currency.credits == 0 and r.currency.banked == 0 and r.currency.dust == 0,
		"bad wallet values fixed"
	)
	check(r.characters[1].level == 40 and r.characters[1].ranks.ZapBolt == 5, "clamped")
	check(r.characters[1].ranks[5] == nil, "junk rank keys dropped")
	check(
		r.characters[1].equipment[1] == 0 and #r.characters[1].equipment == 8,
		"a missing worn piece is cleared"
	)
	check(r.characters[1].fxStyle == "Comic", "style fixed")
	check(#r.stash == 1, "duplicates and junk pieces dropped")
	check(#r.characters == 1 and r.active == 1, "junk characters dropped, active fixed")
	-- full profile: 150 pieces, 4 characters, every style
	local full = ProfileSchema.default()
	local rng = Rng.new(2)
	for _ = 1, 150 do
		local piece = GearMath.roll(Config, rng, "Legendary", 40)
		Inventory.add(Config, full, piece)
	end
	for _ = 2, 4 do
		table.insert(full.characters, ProfileSchema.newCharacter("villain", "Powerhouse"))
	end
	for _, c in full.characters do
		for _, id in Config.Abilities.order do
			c.ranks[id] = 5
			c.mods[id] = 2
		end
	end
	for i = 1, 511 do
		ProfileSchema.Bits.set(full.styles, i)
	end
	local json = serde.encode("json", full)
	check(#json < Config.Data.targetBytes, string.format("a full profile is %d bytes (target 60 KB)", #json))
	local back = ProfileSchema.load(serde.decode("json", json))
	check(#back.stash == 150 and #back.characters == 4, "survives a JSON round trip")
	check(#ProfileSchema.Bits.list(back.styles) == 511, "every style bit kept")
	local view = ProfileSchema.clientView(full)
	check(#view.stash == 150 and #view.styles == 511 and view.currency ~= nil, "full client view")
	local small = ProfileSchema.clientView(full, true)
	check(
		small.stash == nil and small.currency ~= nil and small.level ~= nil,
		"wallet-only view skips the stash"
	)
	check(#serde.encode("json", small) < 200, "a wallet sync is tiny")
end)

test(
	"M3: inventory: drops unlock styles, equip rules, salvage of worn gear is refused, upgrade, retune",
	function()
		local p = ProfileSchema.default()
		local c = p.characters[1]
		c.level = 20
		local rng = Rng.new(9)
		local kind, piece =
			Inventory.add(Config, p, GearMath.roll(Config, rng, "Rare", 22, { slot = "hands" }))
		check(kind == "stashed" and piece.id == 1, "stashed with id 1")
		check(Inventory.hasStyle(p, piece.style), "its style unlocked")
		local ok, why = Inventory.equip(Config, p, c, piece.id, 1)
		check(not ok and why == "wrong slot", "hands piece in the head slot is refused")
		check((Inventory.equip(Config, p, c, piece.id, 3)), "worn")
		local high =
			select(2, Inventory.add(Config, p, GearMath.roll(Config, rng, "Rare", 30, { slot = "head" })))
		local ok2, why2 = Inventory.equip(Config, p, c, high.id, 1)
		check(not ok2 and why2 == "level", "ilvl 30 needs level 25")
		local okS, whyS = Inventory.salvage(Config, p, { piece.id })
		check(not okS and whyS == "worn", "salvaging a worn piece is refused")
		local style = piece.style
		check((Inventory.equip(Config, p, c, 0, 3)), "unequip")
		local okS2, _, dust = Inventory.salvage(Config, p, { piece.id })
		check(
			okS2 and dust == GearMath.salvageValue(Config, piece) and p.currency.dust == dust,
			"salvaged for Dust"
		)
		check(Inventory.hasStyle(p, style), "the style stays unlocked")
		check(not (Inventory.salvage(Config, p, { 999 })), "unknown piece refused")
		-- another character cannot wear what this one wears
		table.insert(p.characters, ProfileSchema.newCharacter())
		local c2 = p.characters[2]
		c2.level = 40
		local belt =
			select(2, Inventory.add(Config, p, GearMath.roll(Config, rng, "Common", 10, { slot = "belt" })))
		check((Inventory.equip(Config, p, c, belt.id, 7)), "belt on hero 1")
		local okO, whyO = Inventory.equip(Config, p, c2, belt.id, 7)
		check(not okO and whyO == "worn by another hero", "one piece, one hero")
		-- upgrade
		p.currency.dust = 0
		local okU, whyU = Inventory.upgrade(Config, p, belt.id)
		check(not okU and whyU == "dust", "needs Dust (" .. tostring(whyU) .. ")")
		p.currency.dust = 1000
		check(
			(Inventory.upgrade(Config, p, belt.id)) and belt.up == 1 and p.currency.dust == 988,
			"+1 costs 12"
		)
		-- retune
		local okR, whyR = Inventory.retune(Config, rng, p, high.id, 1)
		check(not okR and whyR == "credits", "retune needs Credits")
		p.currency.credits = 5000
		check(
			(Inventory.retune(Config, rng, p, high.id, 1)) and p.currency.credits == 5000 - 1040,
			"retune 800 x 1.3"
		)
		-- styles over gear
		local okSt, whySt = Inventory.showStyle(Config, p, c, 7, 9999 % 512)
		check(not okSt and (whySt == "locked" or whySt == "wrong slot"), "a locked style is refused")
		local headStyle = GearMath.styleId(1, 1)
		ProfileSchema.Bits.set(p.styles, headStyle)
		check(not (Inventory.showStyle(Config, p, c, 7, headStyle)), "a head style cannot go on the belt")
		check((Inventory.showStyle(Config, p, c, 1, headStyle)), "any unlocked head style over any head gear")
		local shown = Inventory.shownStyles(p, c)
		check(shown[1] == headStyle and shown[7] == belt.style, "shown: chosen style, else the worn piece's")
		-- a full stash turns new drops into Dust
		for _ = #p.stash + 1, Config.Gear.stashCap do
			Inventory.add(Config, p, GearMath.roll(Config, rng, "Common", 5))
		end
		local before = p.currency.dust
		local kind2 = Inventory.add(Config, p, GearMath.roll(Config, rng, "Epic", 30, { slot = "feet" }))
		check(kind2 == "salvaged" and p.currency.dust > before and #p.stash == 150, "stash full: salvaged")
	end
)

---------------------------------------------------------------------------
-- M4: world generator, weekly seed, safehouses, beacons
---------------------------------------------------------------------------

local W = Config.World
local function utc(y: number, mo: number, d: number, h: number?): number
	return WorldGen.daysFromCivil(y, mo, d) * 86400 + (h or 0) * 3600
end

test("M4: the weekly seed is ISO year x 100 + ISO week and turns over Monday 00:00 UTC", function()
	local function week(t: number): string
		local y, w = WorldGen.isoWeek(t)
		return string.format("%d-W%02d", y, w)
	end
	check(WorldGen.daysFromCivil(1970, 1, 1) == 0, "the epoch is day 0")
	local y, m, d = WorldGen.civilFromDays(WorldGen.daysFromCivil(2028, 2, 29))
	check(y == 2028 and m == 2 and d == 29, "a leap day round trips")
	check(week(utc(2026, 11, 16, 12)) == "2026-W47", "2026-11-16 is 2026-W47")
	check(week(utc(2021, 1, 1)) == "2020-W53", "2021-01-01 belongs to 2020-W53")
	check(week(utc(2024, 12, 30)) == "2025-W01", "2024-12-30 belongs to 2025-W01")
	check(week(utc(2026, 1, 1)) == "2026-W01", "2026-01-01 is 2026-W01")
	check(week(utc(2027, 1, 3, 23)) == "2026-W53", "2027-01-03 is 2026-W53 (a 53-week year)")
	check(WorldGen.weekSeed(utc(2026, 11, 16)) == 202647, "seed 202647")
	check(
		WorldGen.weekSeed(utc(2026, 11, 22, 23) + 3599) == 202647
			and WorldGen.weekSeed(utc(2026, 11, 23)) == 202648,
		"Sunday 23:59:59 keeps the week; Monday 00:00 UTC moves it on"
	)
	-- every day for 3 years: the week moves by one exactly on Mondays
	local last = WorldGen.weekSeed(utc(2026, 1, 5))
	local ok = true
	for day = 1, 365 * 3 do
		local t = utc(2026, 1, 5) + day * 86400
		local seed = WorldGen.weekSeed(t)
		local monday = (math.floor(t / 86400) + 3) % 7 == 0
		if monday == (seed == last) then
			ok = false
		end
		last = seed
	end
	check(ok, "the seed changes on every Monday and on no other day")
end)

local world = WorldMap.build(Config, 202647)

test("M4: same seed, same tile hash on two servers; other seeds differ; the hub never changes", function()
	local again = WorldMap.build(Config, 202647)
	check(buffer.len(world.tiles) == W.tiles * W.tiles * 2 and buffer.len(world.tiles) == 4608, "4,608 bytes")
	check(again.hash == world.hash and #world.hash == 8, "same seed, same hash: " .. world.hash)
	check(again.parts.total == world.parts.total, "same seed, same part count")
	local other = WorldMap.build(Config, 202648)
	check(other.hash ~= world.hash, "the next week's seed gives a different map")
	local sameHub, outskirtsDiffer = true, 0
	for tz = 0, W.tiles - 1 do
		for tx = 0, W.tiles - 1 do
			local a = buffer.readu16(world.tiles, (tz * W.tiles + tx) * 2)
			local b = buffer.readu16(other.tiles, (tz * W.tiles + tx) * 2)
			if WorldGen.ring(W, tx, tz) == 0 then
				sameHub = sameHub and a == b
			elseif a ~= b then
				outskirtsDiffer += 1
			end
		end
	end
	check(sameHub, "hub tiles are the same every week")
	check(outskirtsDiffer > 1000, string.format("most outskirts tiles change (%d)", outskirtsDiffer))
	local hubSame = #again.hubBoxes == #other.hubBoxes
	check(hubSame, "the hub has the same parts every week")
	-- a one-bit change in the array changes the hash
	local copy = buffer.create(buffer.len(world.tiles))
	buffer.copy(copy, 0, world.tiles)
	buffer.writeu8(copy, 1000, bit32.bxor(buffer.readu8(copy, 1000), 1))
	check(WorldGen.hash(copy) ~= world.hash, "one bit changes the hash")
end)

test("M4: zones: hub 16 to 31, suburbs then farmland, a 2-tile coast, 3 landmarks on fixed tiles", function()
	local Z = W.zones
	local counts = {}
	local outside = 0
	local ringsOk, roadsOk = true, true
	for tz = 0, W.tiles - 1 do
		for tx = 0, W.tiles - 1 do
			local t = WorldGen.get(W, world.tiles, tx, tz)
			counts[t.zone] = (counts[t.zone] or 0) + 1
			local ring = WorldGen.ring(W, tx, tz)
			if ring > 0 then
				outside += 1
			end
			if ring == 0 and t.zone ~= Z.hub and t.zone ~= Z.hubFill then
				ringsOk = false
			end
			if ring >= 15 and t.zone ~= Z.coast then
				ringsOk = false
			end
			if ring >= 1 and ring <= 6 and t.zone ~= Z.suburbs and t.zone ~= Z.landmark then
				ringsOk = false
			end
			if ring >= 9 and ring <= 14 and t.zone ~= Z.farmland and t.zone ~= Z.landmark then
				ringsOk = false
			end
			if (t.zone == Z.suburbs or t.zone == Z.farmland) and t.variant ~= W.special then
				if (tx % 6 == 0) ~= t.hwyNS or (tx % 3 == 0) ~= t.roadNS or (tz % 3 == 0) ~= t.roadEW then
					roadsOk = false
				end
			elseif t.roadNS or t.roadEW then
				roadsOk = false
			end
		end
	end
	check(outside == 2048, "2,048 non-hub tiles")
	check(ringsOk, "zones follow the rings (the suburb edge may wobble one tile)")
	check(roadsOk, "highways every 6 tiles, local roads every 3, none on the coast or hub")
	check(counts[Z.landmark] == 48, "3 landmarks of 4 x 4 tiles")
	check(
		(counts[Z.suburbs] or 0) > 400 and (counts[Z.farmland] or 0) > 700,
		"suburbs and farmland both fill"
	)
	for i, lm in W.landmarks do
		local t = WorldGen.get(W, world.tiles, lm.tx + 1, lm.tz + 2)
		check(t.zone == Z.landmark and t.variant == i, lm.id .. " sits on its tiles")
	end
	check(#world.landmarks == 3, "3 landmarks built")
end)

test("M4: parts: 25 or fewer per outskirts tile on average, every part legal, budgets met", function()
	local outskirtsParts, outskirtsTiles = 0, 0
	for _, plan in world.tilePlans do
		if WorldGen.ring(W, plan.tx, plan.tz) > 0 then
			outskirtsParts += #plan.boxes
		end
	end
	outskirtsParts += world.parts.landmarks
	outskirtsTiles = 2048
	local avg = outskirtsParts / outskirtsTiles
	check(avg <= W.partsPerTile, string.format("%.1f parts per outskirts tile (max %d)", avg, W.partsPerTile))
	check(
		outskirtsParts + world.parts.base <= 51000,
		string.format("outskirts %d parts within 51,000", outskirtsParts)
	)
	check(world.parts.hub <= 55000, string.format("hub %d parts within 55,000", world.parts.hub))
	local legal = true
	local function scan(list: { any })
		for _, b in list do
			for _, v in { b.sx, b.sy, b.sz } do
				if not (v > 0 and v <= 2048) then
					legal = false
				end
			end
			if not Config.City.palette[b.color] then
				legal = false
			end
		end
	end
	scan(world.hubBoxes)
	scan(world.baseBoxes)
	for _, plan in world.tilePlans do
		scan(plan.boxes)
	end
	for _, lm in world.landmarks do
		scan(lm.boxes)
	end
	check(legal, "every part is between 0 and 2,048 studs on each axis with a palette colour")
	-- every lot kind and variant exists and builds
	for zone, list in WorldGen.VARIANTS do
		check(#list == (W.variants[zone] or 0), zone .. " has its variant count")
		for _, kinds in list do
			for _, kind in kinds do
				check(WorldGen.LOT_KINDS[kind] ~= nil, "lot kind " .. kind)
			end
		end
	end
	local t0 = os.clock()
	WorldMap.build(Config, 202650)
	local took = os.clock() - t0
	check(took < 2, string.format("the whole world as data in %.2f s", took))
end)

test("M4: heights: roofs, the Beacon Tower, the outskirts, the sea past the edge", function()
	local bt = world.downtown.beacon
	check(WorldMap.heightAt(world, bt.x, bt.z) >= Config.City.downtown.beacon.height, "Beacon Tower")
	check(WorldMap.heightAt(world, 9999, 0) == W.coast.waterY, "past the edge is the sea")
	check(WorldMap.heightAt(world, -2399, -2399) < 2, "the coast corner is low")
	local roofs = 0
	for tz = 0, 47 do
		for tx = 0, 47 do
			if WorldGen.ring(W, tx, tz) >= 1 then
				local x0, z0 = WorldGen.tileOrigin(Config.City, tx, tz)
				for k = 1, 9 do
					if WorldMap.heightAt(world, x0 + k * 10, z0 + k * 10) > 8 then
						roofs += 1
						break
					end
				end
			end
		end
	end
	check(roofs > 500, string.format("buildings stand in the outskirts (%d tiles)", roofs))
	local crater = world.landmarks[1]
	check(
		WorldMap.heightAt(world, crater.spot.x, crater.spot.z) >= W.crater.rimHeight - 1,
		"the crater rim is high"
	)
	local tallest = 0
	for _, b in world.hubBoxes do
		tallest = math.max(tallest, b.cy + b.sy / 2)
	end
	check(
		tallest < Config.Move.ceiling.soft,
		string.format("everything is under the flight ceiling (%d)", tallest)
	)
end)

test("M4: 16 safehouses with 3 terminals and 3 respawn points, nothing built on their pads", function()
	local hub, out = 0, 0
	for _, s in world.safehouses do
		if s.district == "Outskirts" then
			out += 1
		else
			hub += 1
		end
		check(s.terminals.bank and s.terminals.loadout and s.terminals.respawn ~= nil, s.name .. " terminals")
		check(#s.respawn == 3, s.name .. " respawn points")
		local half = Config.City.mapSize / 2
		check(math.abs(s.x) < half and math.abs(s.z) < half, s.name .. " is on the map")
	end
	check(hub == 12 and out == 4, "12 in the hub and 4 in the outskirts")
	-- no building, roof or prop touches a pad
	local blocked = {}
	local function scan(list: { any })
		for _, b in list do
			if (b.kind == "building" or b.kind == "roof" or b.kind == "ledge") and b.tag == nil then
				local fx, fz = BoxKit.footprint(b)
				for _, s in world.safehouses do
					local pad = W.safehouse.pad / 2
					if math.abs(b.cx - s.x) < fx / 2 + pad and math.abs(b.cz - s.z) < fz / 2 + pad then
						-- the safehouse's own shelter sits on its pad
						if not (math.abs(b.cx - s.x) < 15 and math.abs(b.cz - (s.z - pad + 10)) < 10) then
							blocked[s.name] = true
						end
					end
				end
			end
		end
	end
	scan(world.hubBoxes)
	for _, plan in world.tilePlans do
		scan(plan.boxes)
	end
	local names = {}
	for name in blocked do
		table.insert(names, name)
	end
	check(#names == 0, "pads are clear: " .. table.concat(names, ", "))
	-- the Downtown lots kept for safehouses leave every other Downtown building where it was
	local plain = CityLayout.downtown(Config.City)
	check(#plain.buildings == #world.downtown.buildings + 4, "4 Downtown lots became safehouses")
	local same = 0
	local spots = {}
	for _, b in world.downtown.buildings do
		spots[string.format("%.1f,%.1f,%.1f", b.x, b.z, b.h)] = true
	end
	for _, b in plain.buildings do
		if spots[string.format("%.1f,%.1f,%.1f", b.x, b.z, b.h)] then
			same += 1
		end
	end
	check(same == #world.downtown.buildings, "the rest of Downtown is unchanged")
end)

test("M4: 12 beacons on their roofs and landmarks, under the ceiling, reachable", function()
	-- heights of everything but the beacons themselves
	local bare = HeightMap.new(Config.City.mapSize, W.heightCell, W.coast.waterY)
	local function stampAll(list: { any })
		for _, b in list do
			if b.tag ~= "beacon" and b.tag ~= "beaconPost" and b.tag ~= "beam" then
				HeightMap.stamp(bare, b)
			end
		end
	end
	stampAll(world.hubBoxes)
	for _, plan in world.tilePlans do
		stampAll(plan.boxes)
	end
	for _, lm in world.landmarks do
		stampAll(lm.boxes)
	end
	local n = 0
	for id, b in world.beacons do
		n += 1
		check(b.y > 0 and b.y < Config.Move.ceiling.soft, b.name .. " height")
		local h = HeightMap.at(bare, b.x, b.z)
		check(math.abs(h - b.y) < 3, string.format("%s stands on top (%.0f vs %.0f)", b.name, b.y, h))
		check(W.beacons[id].name == b.name, b.name .. " id")
	end
	check(n == 12, "12 beacons")
	check(world.beacons[1].y > Config.City.downtown.beacon.height, "Beacon Tower's beacon is on its top")
	check(world.beacons[5].y >= W.crater.rimHeight, "the Crater beacon is on the rim")
end)

test("M4: fast travel rules, the flight arc, the bank and respawn choices", function()
	local mask = Travel.add(Travel.add(0, 3), 12)
	check(Travel.has(mask, 3) and Travel.has(mask, 12) and not Travel.has(mask, 4), "bit masks")
	check(Travel.count(mask) == 2 and Travel.add(mask, 3) == mask, "count and idempotent add")
	local base = { beacons = mask, inCombat = false, traveling = false, readyAt = 0, now = 100 }
	check((Travel.canTravel(W, base, 3)), "a discovered beacon out of combat")
	local function why(over: { [string]: any }, id: number): string?
		local s = table.clone(base)
		for k, v in over do
			s[k] = v
		end
		local _, reason = Travel.canTravel(W, s, id)
		return reason
	end
	check(why({}, 4) == "undiscovered", "undiscovered")
	check(why({}, 13) == "no beacon", "no such beacon")
	check(why({ inCombat = true }, 3) == "combat", "not in combat")
	check(why({ readyAt = 110 }, 3) == "cooldown", "20 s cooldown")
	check(why({ traveling = true }, 3) == "traveling", "one trip at a time")
	local x0, y0, z0 = Travel.flightPath(0, 10, 0, 1000, 50, 0, 0)
	local x1, y1, z1 = Travel.flightPath(0, 10, 0, 1000, 50, 0, 1)
	local _, ym = Travel.flightPath(0, 10, 0, 1000, 50, 0, 0.5)
	check(
		x0 == 0 and y0 == 10 and z0 == 0 and x1 == 1000 and math.abs(y1 - 50) < 1e-6 and z1 == 0,
		"starts and ends right"
	)
	check(ym > 50 + 40, "the flight climbs above both ends")
	local cur = { credits = 740, banked = 100, dust = 3 }
	check(Travel.deposit(cur) == 740 and cur.credits == 0 and cur.banked == 840, "deposit banks all on-hand")
	check(Travel.deposit(cur) == 0, "nothing on hand banks nothing")
	local houses = world.safehouses
	check(Travel.respawnAt(houses, 0, 0, 1) == 1, "a new hero's home is safehouse 1")
	check(Travel.respawnAt(houses, 0, 7, 1) == 7, "a returning hero joins at the last chosen safehouse")
	local far = houses[16]
	check(
		Travel.respawnAt(houses, Travel.add(0, 16), 0, 1, far.x + 5, far.z) == 16,
		"a defeat respawns at the nearest visited safehouse"
	)
	check(Travel.respawnAt(houses, 0, 0, 1, far.x + 5, far.z) == 1, "unvisited safehouses are not used")
end)

test("M4: profile version 2 adds beacons and safehouses; a v1 save keeps its last safehouse", function()
	check(ProfileSchema.VERSION >= 2, "version 2 or later")
	local v1 = { version = 1, characters = { { level = 12, lastSafehouse = 5 } } }
	local p = ProfileSchema.load(v1)
	local c = p.characters[1]
	check(p.version == ProfileSchema.VERSION and c.beacons == 0, "beacons start undiscovered")
	check(Travel.has(c.safehouses, 5) and c.lastSafehouse == 5, "the last safehouse counts as visited")
	local bad = ProfileSchema.load({
		version = 2,
		characters = { { beacons = -4, safehouses = 2 ^ 40, lastSafehouse = 99 } },
	})
	local b = bad.characters[1]
	check(b.beacons == 0 and b.safehouses == 65535 and b.lastSafehouse == 16, "bad masks are clamped")
	local view = ProfileSchema.clientView(p)
	check(view.beacons == 0 and view.lastSafehouse == 5, "the client sees beacons and safehouses")
end)

---------------------------------------------------------------------------
-- M5: destruction v1 (buildings, chunks, repair, vehicles, citizens)
---------------------------------------------------------------------------

local DS = Config.Destruction

test("M5: 220 wreckable hub buildings, ids 1 to 220, HP by size class", function()
	local list = world.buildings
	check(#list == DS.hubBuildings, "220 buildings (got " .. #list .. ")")
	local per: { [string]: number } = {}
	for i, b in list do
		check(b.id == i, "ids run 1 to 220")
		local h = b.top - b.base
		local want = if h <= DS.smallMax then "small" elseif h <= DS.mediumMax then "medium" else "tower"
		check(b.size == want and b.hp == DS.hp[want], "building " .. i .. " has the HP of its size")
		check(b.sx > 0 and b.sz > 0 and h > 0, "building " .. i .. " has a body")
		per[b.district] = (per[b.district] or 0) + 1
	end
	check((per.Downtown or 0) > 0 and (per.Docks or 0) > 0 and (per.OldTown or 0) > 0, "all three districts")
	local again = WorldMap.build(Config, 202650)
	check(
		#again.buildings == #list and again.buildings[200].x == list[200].x,
		"the hub list never changes by seed"
	)
	local tagged: { [number]: boolean } = {}
	for _, b in world.hubBoxes do
		if b.bid then
			tagged[b.bid] = true
		end
	end
	for i = 1, #list do
		check(tagged[i] == true, "building " .. i .. " has parts tagged with its id")
	end
end)

test("M5: the Chunker splits every building into 10 to 40 chunks that fill it exactly", function()
	for _, b in world.buildings do
		local chunks = Chunker.split(DS, b)
		check(
			#chunks >= DS.chunks.min and #chunks <= DS.chunks.max,
			"chunk count for " .. b.id .. ": " .. #chunks
		)
		local vol = 0
		for _, c in chunks do
			vol += c.sx * c.sy * c.sz
			check(
				math.abs(c.cx - b.x) <= b.sx / 2 + 1e-6 and math.abs(c.cz - b.z) <= b.sz / 2 + 1e-6,
				"inside the footprint"
			)
			check(c.cy - c.sy / 2 >= b.base - 1e-6 and c.cy + c.sy / 2 <= b.top + 1e-6, "inside the height")
		end
		near(vol, b.sx * b.sz * (b.top - b.base), 1e-3 * vol, "chunks fill building " .. b.id)
		local gone = Chunker.fallen(DS, chunks, b.id)
		local n, rows = 0, 0
		for _, c in chunks do
			rows = math.max(rows, c.row)
		end
		for i in gone do
			n += 1
			check(chunks[i].row > rows / 2, "only upper chunks fall")
		end
		check(
			n >= math.min(DS.chunks.fallMin, #chunks - 1) and n <= DS.chunks.fallMax,
			"4 to 8 chunks fall (" .. n .. ")"
		)
		local again = Chunker.fallen(DS, chunks, b.id)
		for i in gone do
			check(again[i] == true, "every device drops the same chunks")
		end
		local rubble = Chunker.rubble(DS, b, b.id)
		check(#rubble >= DS.rubble.min and #rubble <= DS.rubble.max, "6 to 10 rubble pieces")
		for _, r in rubble do
			check(r.cy + r.sy / 2 <= b.base + DS.rubble.height, "the heap is low")
			check(
				math.abs(r.cx - b.x) <= b.sx / 2 and math.abs(r.cz - b.z) <= b.sz / 2,
				"the heap stays on the lot"
			)
		end
	end
end)

local function testBook(n: number)
	local list = {}
	for i = 1, n do
		table.insert(list, { id = i, hp = 10000, district = if i % 2 == 0 then "B" else "A" })
	end
	return BuildingState.new(DS, list)
end

test("M5: Damaged at 40% lost, warning at 75%, Collapsed at 100%; a 4th collapse is cut", function()
	local book = testBook(8)
	local s, changed, cut, warn = BuildingState.hit(DS, book, 1, 3999, 0)
	check(s == 0 and not changed and not warn, "39.99% lost stays Intact")
	s, changed = BuildingState.hit(DS, book, 1, 1, 0)
	check(s == BuildingState.DAMAGED and changed, "40% lost is Damaged")
	s, changed, cut, warn = BuildingState.hit(DS, book, 1, 3500, 0)
	check(s == 1 and warn and not changed, "75% lost warns the citizens once")
	_, _, _, warn = BuildingState.hit(DS, book, 1, 100, 0)
	check(not warn, "the warning fires once")
	s, changed = BuildingState.hit(DS, book, 1, 5000, 1)
	check(s == BuildingState.COLLAPSED and changed, "100% lost collapses")
	s = BuildingState.hit(DS, book, 2, 99999, 2)
	check(s == 2, "second collapse")
	s = BuildingState.hit(DS, book, 3, 99999, 3)
	check(s == 2, "third collapse")
	s, changed, cut = BuildingState.hit(DS, book, 4, 99999, 4)
	check(
		s == BuildingState.DAMAGED and cut and book.hp[4] == 1,
		"a 4th collapse inside 6 s is cut to Damaged at 1 HP"
	)
	s = BuildingState.hit(DS, book, 4, 1, 1 + DS.collapseTime + 0.01)
	check(s == 2, "once the first collapse is over, the cut building can fall")
	s, changed = BuildingState.hit(DS, book, 1, 5000, 9)
	check(s == 2 and not changed, "a collapsed building takes no more hits")
	check(
		BuildingState.force(DS, book, 5, 10) and book.state[5] == 1,
		"a knockback through a wall makes it Damaged"
	)
	check(not BuildingState.force(DS, book, 5, 11), "forcing it again changes nothing")
	local diffs = BuildingState.takeDiffs(book)
	check(
		#diffs == 10 and #BuildingState.takeDiffs(book) == 0,
		"five changed buildings in one diff, then none"
	)
end)

test(
	"M5: repair drones fix quiet buildings: Damaged after 180 s, Collapsed after 240 s, 20 s each",
	function()
		local book = testBook(4)
		check(#book.drones == 2 * DS.repair.dronesPerDistrict, "3 drones in each district")
		BuildingState.hit(DS, book, 1, 5000, 0) -- Damaged
		BuildingState.hit(DS, book, 3, 99999, 0) -- Collapsed (also district A)
		local _, started = BuildingState.stepDrones(DS, book, 179)
		check(#started == 0, "nothing before 180 quiet seconds")
		_, started = BuildingState.stepDrones(DS, book, 180)
		check(#started == 1 and started[1].target == 1, "a drone takes the Damaged building at 180 s")
		local repaired = BuildingState.stepDrones(DS, book, 199)
		check(#repaired == 0, "the job takes 20 s")
		repaired = BuildingState.stepDrones(DS, book, 200)
		check(
			#repaired == 1 and repaired[1] == 1 and book.state[1] == 0 and book.hp[1] == 10000,
			"repaired whole"
		)
		_, started = BuildingState.stepDrones(DS, book, 239)
		check(#started == 0, "the collapsed one waits 240 s")
		_, started = BuildingState.stepDrones(DS, book, 240)
		check(#started == 1 and started[1].target == 3, "then a drone starts on it")
		BuildingState.hit(DS, book, 3, 1, 250) -- no effect on a collapsed building, but a Damaged one:
		BuildingState.hit(DS, book, 2, 5000, 0)
		BuildingState.stepDrones(DS, book, 180)
		BuildingState.hit(DS, book, 2, 10, 190) -- hit again during its job
		repaired = BuildingState.stepDrones(DS, book, 200)
		check(
			table.find(repaired, 2) == nil and book.state[2] == 1,
			"a building hit during the job stays broken"
		)
	end
)

test("M5: 2 bits a building: the hub's 220 states pack into 55 bytes and back", function()
	local list = {}
	for i = 1, 220 do
		table.insert(list, { id = i, hp = 6000, district = "A" })
	end
	local book = BuildingState.new(DS, list)
	local rng = Rng.new(5)
	for i = 1, 220 do
		book.state[i] = rng:int(0, 2)
	end
	local b = BuildingState.pack(book)
	check(buffer.len(b) == 55, "55 bytes")
	local back = BuildingState.unpack(b, 220)
	for i = 1, 220 do
		check(back[i] == book.state[i], "state " .. i .. " survives")
	end
end)

test("M5: 40 vehicles on the streets, never inside a building, 6 flips a district at most", function()
	local list = Vehicles.place(Config)
	check(#list == DS.vehicles.count, "40 vehicles (got " .. #list .. ")")
	local trams, kinds = 0, {}
	for i, v in list do
		check(v.id == i, "ids run 1 to 40")
		kinds[v.kind] = true
		if v.kind == "tram" then
			trams += 1
		end
		for _, b in world.buildings do
			local hx = (if v.ry == 90 then v.sz else v.sx) / 2
			local hz = (if v.ry == 90 then v.sx else v.sz) / 2
			local overlap = math.abs(v.x - b.x) < hx + b.sx / 2 and math.abs(v.z - b.z) < hz + b.sz / 2
			check(not overlap, string.format("vehicle %d (%s) clear of building %d", v.id, v.kind, b.id))
		end
		for j = i + 1, #list do
			local o = list[j]
			check(math.abs(v.x - o.x) > 2 or math.abs(v.z - o.z) > 2, "vehicles do not stack")
		end
	end
	check(trams == DS.vehicles.trams and kinds.car and kinds.truck, "cars, 8 trams and trucks")
	check(
		DS.vehicles.perDistrict == 6 and DS.vehicles.flipTime == 1 and DS.vehicles.resetAfter == 30,
		"flip rules"
	)
	local v = list[1]
	local x0, y0, z0, r0 = Vehicles.flipPose(DS, v, 0, 1, 0)
	check(x0 == 0 and y0 == 0 and z0 == 0 and r0 == 0, "the arc starts at home")
	local x1, y1, _, r1 = Vehicles.flipPose(DS, v, 1, 1, 0)
	near(x1, DS.vehicles.flipTravel, 1e-6, "it lands pushed away from the hit")
	near(y1, 0, 1e-6, "it lands on the ground")
	near(r1, math.pi, 1e-6, "on its roof")
	local _, yMid = Vehicles.flipPose(DS, v, 0.5, 1, 0)
	check(yMid > DS.vehicles.flipHeight * 0.9, "it arcs up on the way")
end)

local function citizenSim(seed: number)
	local shelters = {}
	for _, s in world.safehouses do
		if s.district == "Downtown" or s.district == "OldTown" then
			table.insert(shelters, { x = s.x, z = s.z })
		end
	end
	return CitizenSim.new(Config, shelters, seed)
end

test(
	"M5: 60 citizens walk the sidewalks, flee danger to a shelter outside it, hide, then come back",
	function()
		local sim = citizenSim(11)
		check(#sim.shelters >= 5, "Downtown and Old Town shelters (" .. #sim.shelters .. ")")
		CitizenSim.populate(sim, 500)
		check(#sim.citizens == DS.citizens.max, "capped at 60")
		for _, n in sim.nodes do
			check(#n.links >= 2, "every sidewalk corner joins at least two others")
		end
		local t = 0
		for _ = 1, 50 do
			t += 0.1
			CitizenSim.step(sim, 0.1, t)
		end
		local c = sim.citizens[1]
		local dx, dz = c.x, c.z
		CitizenSim.danger(sim, dx, dz, DS.citizens.fleeRadius, 10)
		local fled = {}
		for _, o in sim.citizens do
			if o.state == CitizenSim.FLEE then
				table.insert(fled, o)
				check(o.goal ~= nil, "a fleeing citizen has somewhere to go")
				local g = o.goal :: any
				check(
					(g.x - dx) ^ 2 + (g.z - dz) ^ 2 >= DS.citizens.fleeRadius ^ 2,
					"the shelter is outside the danger"
				)
			end
		end
		check(#fled >= 1 and c.state == CitizenSim.FLEE, "the citizen at the danger runs")
		for _ = 1, 900 do
			t += 0.1
			CitizenSim.step(sim, 0.1, t)
			local all = true
			for _, o in fled do
				if o.state ~= CitizenSim.HIDDEN then
					all = false
				end
			end
			if all then
				break
			end
		end
		for _, o in fled do
			check(o.state == CitizenSim.HIDDEN, "every runner made it inside")
		end
		check(CitizenSim.visible(sim) == 60 - #fled, "hidden citizens are not drawn")
		for _ = 1, 420 do
			t += 0.1
			CitizenSim.step(sim, 0.1, t)
		end
		check(CitizenSim.visible(sim) == 60, "after 20 to 40 s they come back out")
		for _, o in sim.citizens do
			check(o.health == nil and o.hp == nil, "citizens have no health: nothing can hurt them")
		end
	end
)

test("M5: Citizen.Delta packs the citizens near a player, 9 bytes each, and decodes the same", function()
	local sim = citizenSim(12)
	CitizenSim.populate(sim)
	local px, pz = sim.citizens[1].x, sim.citizens[1].z
	sim.citizens[2].state = CitizenSim.HIDDEN
	sim.citizens[3].fx, sim.citizens[3].fz = 1, 0
	local b = CitizenBuffer.encodeFor(77, sim.citizens, px, pz, DS.citizens.relevance)
	local seq, rows = CitizenBuffer.decode(b)
	check(seq == 77, "sequence")
	local want = 0
	for _, c in sim.citizens do
		if c.state ~= CitizenSim.HIDDEN and (c.x - px) ^ 2 + (c.z - pz) ^ 2 <= DS.citizens.relevance ^ 2 then
			want += 1
		end
	end
	check(#rows == want and buffer.len(b) == 6 + 9 * want, "only visible citizens in range")
	for _, r in rows do
		check(r.id ~= 2, "hidden citizens are left out")
		local c = sim.citizens[r.id]
		near(r.x, c.x, 0.051, "x")
		near(r.z, c.z, 0.051, "z")
		check(r.state == c.state and r.color == c.color, "state and colour set")
		if r.id == 3 then
			near(r.yaw, 3 * math.pi / 2, 2 * math.pi / 256, "facing +x is Roblox yaw 270 degrees")
		end
	end
end)

test("M5: destruction remotes exist with the right direction; citizens are unreliable", function()
	check(
		Remotes.BuildingSync.dir == "C2S" and Remotes.BuildingSync.rate ~= nil,
		"BuildingSync is rate-limited"
	)
	for _, name in { "BuildingSnapshot", "BuildingDiff", "BuildingImpact", "VehicleFlip", "VehicleReset" } do
		check(Remotes[name] ~= nil and Remotes[name].dir == "S2C", name)
	end
	check(Remotes.CitizenDelta.unreliable == true, "CitizenDelta unreliable")
	local abilities = 0
	for _, row in Config.Abilities.list do
		if row.structDmg then
			abilities += 1
		end
	end
	check(abilities >= 4, "slams and heavy abilities carry structDmg")
end)

---------------------------------------------------------------------------
-- M6: incidents, contracts, events, world boss
---------------------------------------------------------------------------

test("M6: zone level is the hero's level raised to the area floor, capped at 40", function()
	check(ZoneLevel.area(Config, 0, 0, world.tiles) == "hub", "the plaza is hub")
	check(ZoneLevel.at(Config, 0, 0, 3, world.tiles) == 3, "hub: the hero's own level")
	local sx = -Config.City.mapSize / 2 + (Config.World.hubFirst - 3) * Config.City.tile + 50
	check(ZoneLevel.area(Config, sx, 0, world.tiles) == "suburbs", "3 tiles out is suburbs")
	check(ZoneLevel.at(Config, sx, 0, 1, world.tiles) == 5, "the suburbs floor is 5")
	check(ZoneLevel.at(Config, sx, 0, 30, world.tiles) == 30, "a higher hero keeps their level")
	local cr = Config.World.landmarks[1]
	local cx = -Config.City.mapSize / 2 + (cr.tx + 2) * Config.City.tile
	local cz = -Config.City.mapSize / 2 + (cr.tz + 2) * Config.City.tile
	check(ZoneLevel.area(Config, cx, cz, world.tiles) == "CometCrater", "the crater is its own area")
	check(ZoneLevel.at(Config, cx, cz, 2, world.tiles) == 10, "crater floor 10")
	check(ZoneLevel.at(Config, 0, 0, 99) == 40, "capped at 40")
	check(ZoneLevel.area(Config, 2300, 2300) == "coast", "the map corner is coast without tiles too")
	check(
		ZoneLevel.median({ 4, 20, 9 }) == 9 and ZoneLevel.median({ 2, 4 }) == 3 and ZoneLevel.median({}) == 1,
		"median"
	)
end)

test("M6: the world clock runs 24 minutes: 16 day, 3 dusk, 4 night, 1 dawn", function()
	local c = Config.World.clock
	check(c.day + c.dusk + c.night + c.dawn == c.cycle and c.cycle == 1440, "24 minutes")
	check((WorldClock.phase(c, 0)) == "day" and (WorldClock.phase(c, 959)) == "day", "day first")
	check((WorldClock.phase(c, 960)) == "dusk" and (WorldClock.phase(c, 1140)) == "night", "dusk then night")
	check(
		(WorldClock.phase(c, 1380)) == "dawn" and (WorldClock.phase(c, 1440)) == "day",
		"dawn, then day again"
	)
	near(WorldClock.clockTime(c, 0), 7, 1e-6, "day starts at 7:00")
	near(WorldClock.clockTime(c, 960), 17, 1e-6, "dusk at 17:00")
	near(WorldClock.clockTime(c, 1140 + 120), 0, 1e-6, "midnight halfway through the night")
	check(WorldClock.isNight(c, 1200) and not WorldClock.isNight(c, 1000), "night only in the night part")
	check(WorldClock.lampsOn(c, 1000) and not WorldClock.lampsOn(c, 100), "lamps from dusk")
end)

local IC = Config.Incidents
local ALL_WHERE = { street = true, tower = true, tram = true, sign = true, roof = true, crane = true }

test("M6: 10 incident templates; each side gets its own and the shared ones", function()
	check(#IC.order == 10, "10 templates")
	local nums = {}
	for _, tid in IC.order do
		local t = IC.templates[tid]
		check(t ~= nil and not nums[t.num] and t.num >= 1 and t.num <= 10, tid .. " has a unique number")
		nums[t.num] = true
		check(t.time >= 30 and t.time <= 120, tid .. " takes 30 s to 2 min")
		check(#t.steps >= 1, tid .. " has steps")
		if t.side == "both" then
			check(t.villainName ~= nil, tid .. " has a villain banner")
		end
	end
	local hero = IncidentPlan.choices(IC, "hero", ALL_WHERE, false)
	local villain = IncidentPlan.choices(IC, "villain", ALL_WHERE, false)
	check(
		#hero == 6 and table.find(hero, "RobotHeist") and not table.find(hero, "VaultBreach"),
		"hero: 6 without a boss"
	)
	check(
		#villain == 8 and table.find(villain, "ShardCrate") and not table.find(villain, "RobotHeist"),
		"villain: 8"
	)
	check(not table.find(hero, "RaidPrep"), "Raid prep only while a boss counts down")
	local bare = IncidentPlan.choices(IC, "hero", { street = true }, false)
	check(
		table.find(bare, "TowerFire") == nil and table.find(bare, "RobotHeist") ~= nil,
		"templates need their spot"
	)
	local rng = Rng.new(3)
	check(
		IncidentPlan.pick(IC, rng, "hero", ALL_WHERE, nil, false, true) == "RaidPrep",
		"a countdown prefers Raid prep"
	)
	for _ = 1, 200 do
		local a = IncidentPlan.pick(IC, rng, "hero", ALL_WHERE, "TowerFire", false, false)
		check(a ~= "TowerFire", "never the same template twice in a row")
	end
	local day, night = 0, 0
	for _ = 1, 4000 do
		if
			IC.templates[IncidentPlan.pick(IC, rng, "villain", ALL_WHERE, nil, false, false) :: string].side
			== "villain"
		then
			day += 1
		end
		if
			IC.templates[IncidentPlan.pick(IC, rng, "villain", ALL_WHERE, nil, true, false) :: string].side
			== "villain"
		then
			night += 1
		end
	end
	check(night > day * 1.06, string.format("villain incidents more often at night (%d vs %d)", night, day))
end)

test("M6: an incident rolls its robots, advances step by step, and earns a medal by time", function()
	local rng = Rng.new(9)
	local inc = IncidentPlan.new(IC, rng, "VaultBreach", 12, 100)
	check(
		#inc.steps == 2 and inc.level == 12 and inc.deadline == 100 + IC.templates.VaultBreach.time,
		"two steps, a deadline"
	)
	local need = inc.steps[1].need
	check(need >= 3 and need <= 5, "1 to 2 turrets and 2 to 3 burglars")
	check(IncidentPlan.advance(inc, "hold", 1) == nil, "progress only counts on the current step")
	for _ = 1, need - 1 do
		check(IncidentPlan.advance(inc, "defeat", 1) == nil, "not yet")
	end
	near(IncidentPlan.fraction(inc), (need - 1) / need / 2, 1e-6, "halfway through step 1")
	check(IncidentPlan.advance(inc, "defeat", 1) == "step", "step 1 done")
	check(
		IncidentPlan.advance(inc, "hold", 3) == nil and IncidentPlan.advance(inc, "hold", 3) == "done",
		"6 s of holding"
	)
	check(inc.done and IncidentPlan.fraction(inc) == 1, "done")
	check(IncidentPlan.medal(IC, inc, 100 + 50) == "gold", "under half the limit: gold")
	check(IncidentPlan.medal(IC, inc, 100 + 80) == "silver", "under 80%: silver")
	check(IncidentPlan.medal(IC, inc, 100 + 105) == "bronze", "late: bronze")
	local late = IncidentPlan.new(IC, rng, "FallingSign", 1, 0)
	check(IncidentPlan.expired(late, 40) and not IncidentPlan.expired(late, 39), "the sign falls at 40 s")
	check(IncidentPlan.holdRate(IC, 0) == 0 and IncidentPlan.holdRate(IC, 1) == 1, "one hero holds at 1x")
	check(IncidentPlan.holdRate(IC, 2) == 1.5 and IncidentPlan.holdRate(IC, 5) == 2, "more heroes, up to 2x")
	check(IncidentPlan.objectHp(Config, 10, 10) == 900, "10 hits of Power 90")
	local name, text = IncidentPlan.title(IC, "TowerFire", "villain")
	check(name == "Smoke cover" and text ~= IC.templates.TowerFire.text, "villains see their banner")
	for _, tid in IC.order do
		local t = IncidentPlan.new(IC, rng, tid, 5, 0)
		for _, st in t.steps do
			check(st.need >= 1, tid .. " steps need something")
		end
	end
end)

local CC = Config.Contracts

test("M6: contract boards offer 3 for your side, the same until they change; max 3 accepted", function()
	check(#CC.order == 6, "6 contract types")
	for w = 1, 60 do
		local h = ContractPlan.offers(CC, 7, "hero", w, 10)
		local v = ContractPlan.offers(CC, 7, "villain", w, 10)
		check(#h == 3 and #v == 3, "3 offers")
		local seen = {}
		for _, o in h do
			check(o.type ~= "VaultJob" and not seen[o.type], "heroes never see the Vault job; no repeats")
			seen[o.type] = true
		end
		for _, o in v do
			check(o.type ~= "Stakeout", "villains never see the Stakeout")
		end
	end
	local a, b = ContractPlan.offers(CC, 7, "hero", 5, 10), ContractPlan.offers(CC, 7, "hero", 5, 10)
	check(a[1].type == b[1].type and a[3].seed == b[3].seed, "the same window shows the same offers")
	local offer = a[1]
	check(not ContractPlan.canAccept(CC, 3, "hero", {}, offer), "the board opens at level 4")
	check(ContractPlan.canAccept(CC, 4, "hero", {}, offer), "level 4 can accept")
	local full = {
		{ type = "A", seed = 1, level = 1, got = 0 },
		{ type = "B", seed = 1, level = 1, got = 0 },
		{ type = "C", seed = 1, level = 1, got = 0 },
	}
	local ok, why = ContractPlan.canAccept(CC, 10, "hero", full, offer)
	check(not ok and why == "full", "at most 3")
	ok, why =
		ContractPlan.canAccept(CC, 10, "hero", { { type = offer.type, seed = 1, level = 1, got = 0 } }, offer)
	check(not ok and why == "same", "one of each type at a time")
	ok, why = ContractPlan.canAccept(CC, 10, "hero", {}, { type = "VaultJob", seed = 1, level = 1, got = 0 })
	check(not ok and why == "side", "a hero cannot take the Vault job")
	local c = { type = "RescueRun", seed = 1, level = 1, got = 0 }
	check(
		not ContractPlan.progress(CC, c, 4) and ContractPlan.progress(CC, c, 9) and c.got == 5,
		"5 rescues, clamped"
	)
end)

test("M6: contract pay follows the table, the first 5 each day pay double", function()
	local sc = Config.Economy.scale -- the M9 balance knobs over the spec formulas
	local function round(x: number): number
		return math.floor(x + 0.5)
	end
	local cr, rn, m = ContractPlan.pay(Config, "DroneSweep", 10, 0)
	check(
		cr == round((40 + 40) * 2 * sc.credits) and rn == round((60 + 50) * 2 * sc.renown) and m == 2,
		"Drone sweep L10, first of the day: x2"
	)
	cr, rn, m = ContractPlan.pay(Config, "DroneSweep", 10, 5)
	check(cr == round(80 * sc.credits) and rn == round(110 * sc.renown) and m == 1, "the 6th pays the base")
	local _, rn2 = ContractPlan.pay(Config, "Escort", 10, 9)
	check(rn2 == round((60 + 5 * 10) * sc.renown), "types without their own Renown use the contract row")
	local fixed = ContractPlan.repair(
		CC,
		{ { type = "Escort", got = 9999, level = 99 }, { type = "Escort" }, { type = "Nope" }, 5 }
	)
	check(#fixed == 1 and fixed[1].got == 600 and fixed[1].level == 40, "repair clamps and drops junk")
	check(#ContractPlan.repair(CC, "bad") == 0, "repair of junk is empty")
end)

test("M6: random events every 4 to 6 minutes, max 2, never the same twice in a row, all 6 turn up", function()
	local EV = Config.Events
	check(#EV.order == 6, "6 events")
	local st = EventPlan.new(EV, 0)
	local rng = Rng.new(21)
	local last, starts, seen, lastStart = nil, 0, {}, nil
	for t = 0, 7200, 1 do
		local id = EventPlan.due(EV, st, t, rng)
		check(EventPlan.activeCount(st) <= 2, "never more than 2 at once")
		if id then
			check(id ~= last, "never the same type twice in a row")
			if lastStart then
				check(t - lastStart >= 240 - 1e-6 and t - lastStart <= 360 + 1, "4 to 6 minutes apart")
			else
				check(t == EV.scheduler.firstAfter, "the first comes 90 s after boot")
			end
			last, lastStart = id, t
			starts += 1
			seen[id] = true
		end
	end
	local kinds = 0
	for _ in seen do
		kinds += 1
	end
	check(starts >= 19 and kinds == 6, string.format("about one every 5 minutes (%d), all 6 kinds", starts))
	check(EventPlan.inPocket(EV, 3000) and not EventPlan.inPocket(EV, 100), "no events in mission pockets")
end)

test("M6: boss HP scales with heroes and the median level, minus Raid prep (at most 15%)", function()
	check(BossMath.maxHp(Config, 1, 20, 0) == 64000, "one hero at level 20")
	check(BossMath.maxHp(Config, 10, 20, 0) == 100000, "ten heroes")
	near(BossMath.maxHp(Config, 10, 30, 0), 100000 * 3.9 / 2.9, 1, "level 30 scales like robots")
	check(BossMath.maxHp(Config, 10, 20, 2) == 94000, "2 prep clears: -6%")
	check(BossMath.maxHp(Config, 10, 20, 9) == 85000, "capped at -15%")
	check(
		BossMath.phase(Config, 0.9) == 1
			and BossMath.phase(Config, 0.5) == 2
			and BossMath.phase(Config, 0.2) == 3,
		"phases"
	)
	check(BossMath.clampForNewPlayer(Config, 5000, 100) == 460, "a new player clamps the wait to 6 minutes")
	check(BossMath.clampForNewPlayer(Config, 200, 100) == 200, "never later than it was")
	local rng = Rng.new(4)
	for _ = 1, 50 do
		local d = BossMath.nextDelay(Config, rng)
		check(d >= 1200 and d <= 1800, "20 to 30 minutes")
	end
end)

test(
	"M6: contribution tiers: MVP top 3, Contributor top 50%, healers count, late joiners get the floor",
	function()
		local ledger = {}
		for id = 1, 10 do
			ledger[id] = { damage = 10000 + id * 1000, support = 0, objectives = 0 }
		end
		ledger[11] = { damage = 0, support = 5000, objectives = 0 } -- only heals and revives
		ledger[12] = { damage = 300, support = 0, objectives = 0 } -- joined at the very end
		ledger[13] = { damage = 4000, support = 0, objectives = 2000 } -- broke the cannons
		local scores = BossMath.scores(Config, ledger)
		local tiers, ranked = BossMath.tiers(Config, scores)
		check(#ranked == 13, "13 took part")
		check(tiers[11] == "mvp" or tiers[11] == "contributor", "the healer reaches Contributor or better")
		check(tiers[13] == "mvp", "objectives count")
		check(tiers[12] == "floor", "the late joiner gets the floor")
		local mvps, contributors = 0, 0
		for _, t in tiers do
			if t == "mvp" then
				mvps += 1
			elseif t == "contributor" then
				contributors += 1
			end
		end
		check(mvps == 3 and mvps + contributors == 7, "3 MVPs, top 50% (7 of 13) Contributor or better")
		local floor = BossMath.reward(Config, "floor", true)
		check(floor.share == 0.25 and #floor.drops == 0, "the floor is 25% of the Participant pay, no gear")
		local mvp = BossMath.reward(Config, "mvp", true)
		check(
			mvp.share == 1 and #mvp.drops == 2 and mvp.drops[2] == "bossMvp" and mvp.style and mvp.page,
			"MVP rewards"
		)
		local retreat = BossMath.reward(Config, "contributor", false)
		check(
			retreat.share == 0.25 and #retreat.drops == 0 and not retreat.page,
			"a retreat pays 25% of the Credits only"
		)
		local got, shiny = 0, 0
		local styleRng = Rng.new(1)
		for _ = 1, 4000 do
			local s, sh = BossMath.styleRoll(Config, "mvp", styleRng)
			if s then
				got += 1
			end
			if sh then
				shiny += 1
			end
		end
		check(got == 4000, "MVPs always get the boss look")
		check(shiny > 100 and shiny < 320, "1 in 20 is shiny (" .. shiny .. ")")
		check(
			GearMath.bossStyle(Config, "RustjawPrime", false)
				~= GearMath.bossStyle(Config, "RustjawPrime", true),
			"two looks a boss"
		)
		check(GearMath.bossStyle(Config, "LumenMaw", true) ~= nil, "the Maw's shiny exists")
		local rngR = Rng.new(5)
		for _ = 1, 500 do
			local piece = GearMath.roll(Config, rngR, "Rare", 20, { slot = "head" })
			local row = GearMath.styleRow(Config, piece.style)
			check(row == nil or row.tier ~= "Boss", "loot never rolls a boss look")
		end
	end
)

local function bossHeroes(list)
	local out = {}
	for i, p in list do
		table.insert(out, { id = i, x = p[1], y = p[2], z = p[3], alive = true })
	end
	return out
end

test(
	"M6: Rustjaw lands, takes hits (weak points x2), changes phase, shells and stomps, dies or retreats",
	function()
		local rng = Rng.new(8)
		local sim = BossSim.new(Config, "RustjawPrime", 0, 0, 0, 64000, 20, 0, rng)
		check(#BossSim.targets(sim) == 0, "nothing to hit while it lands")
		BossSim.step(sim, 6, {})
		check(sim.state == "fight", "fighting after the landing")
		local t = BossSim.targets(sim)
		check(#t == 9, "7 body targets and 2 cannons")
		check(select(1, BossSim.damage(sim, "body", 1000)) == 1000, "body hit")
		check(select(1, BossSim.damage(sim, "core", 1000)) == 2000, "the core takes double")
		BossSim.damage(sim, "head", 64000 * 0.34 - 3000 - 10)
		check(sim.phase == 1, "still phase 1 above 66%")
		BossSim.damage(sim, "head", 100)
		check(sim.phase == 2, "phase 2 under 66%")
		local _, objDealt, broke = BossSim.damage(sim, "obj1", 1e9)
		check(objDealt > 0 and broke == 1 and not sim.objectives[1].alive, "a cannon breaks")
		BossSim.drain(sim)
		-- a hero standing at its feet gets stomped within a few attacks; one flying 30 up dodges stomps
		local heroes = bossHeroes({ { 10, 0, 0 }, { 0, 30, 10 } })
		local hitGround, hitAir, warned = 0, 0, 0
		for step = 1, 400 do
			BossSim.step(sim, 6 + step * 0.1, heroes)
			for _, ev in BossSim.drain(sim) do
				if ev.k == "warn" then
					warned += 1
				elseif ev.k == "strike" and ev.a == "Stomp" then
					for _, h in ev.hits do
						if h[1] == 1 then
							hitGround += 1
							near(h[2], (20 + 4 * 20) * 2.0, 1e-6, "stomp damage = (20 + 4L) x 2.0")
						else
							hitAir += 1
						end
					end
					check(ev.struct == 45, "stomps hit buildings")
				end
			end
		end
		check(warned > 5 and hitGround > 0 and hitAir == 0, "attacks are warned; stomps hit the ground only")
		BossSim.damage(sim, "head", 1e9)
		check(sim.state == "dead" and sim.hp == 0, "it falls at 0 HP")
		local sim2 = BossSim.new(Config, "RustjawPrime", 0, 0, 0, 64000, 20, 0, rng)
		BossSim.step(sim2, 6, {})
		BossSim.step(sim2, 5 + Config.Boss.schedule.lifespan + 1, {})
		check(sim2.state == "retreat", "after 8 minutes it retreats")
	end
)

test("M6: the Lumen Maw's generators heal it while they stand; it stays in its pit", function()
	local sim = BossSim.new(Config, "LumenMaw", 100, 10, 200, 50000, 20, 0, Rng.new(2))
	BossSim.step(sim, 6, {})
	check(#sim.objectives == 3, "3 generators")
	BossSim.damage(sim, "body", 20000)
	local hp0 = sim.hp
	local heroes = bossHeroes({ { 160, 10, 200 } })
	for i = 1, 100 do
		BossSim.step(sim, 6 + i * 0.1, heroes)
	end
	near(sim.hp - hp0, 50000 * 0.004 * 3 * 10, 200, "3 generators heal 1.2% a second")
	check(sim.x == 100 and sim.z == 200, "it does not walk")
	for i = 1, 3 do
		BossSim.damage(sim, "obj" .. i, 1e9)
	end
	local hp1 = sim.hp
	for i = 101, 150 do
		BossSim.step(sim, 6 + i * 0.1, heroes)
	end
	check(sim.hp == hp1, "no healing once they are broken")
	check(sim.phase == 2, "phase stays at 2 even after healing")
end)

test("M6: incident, contract and event spots are real places in the world", function()
	local IncidentSpots = require("../src/shared/IncidentSpots")
	local rng = Rng.new(11)
	local function open(x: number, z: number): boolean
		return WorldMap.heightAt(world, x, z) <= 1.5
	end
	local bt = world.downtown.beacon
	-- streets: open ground, inside the distance band, from all over the map
	local streets = 0
	for i = 1, 120 do
		local x, z = rng:range(-1400, 1400), rng:range(-1400, 1400)
		local s = IncidentSpots.find(Config, world, "street", x, z, 60, 300, rng)
		if s then
			streets += 1
			local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
			check(open(s.x, s.z) and d >= 60 - 1e-6 and d <= 300 + 1e-6, "street spot " .. i)
		end
	end
	check(streets >= 100, string.format("streets found almost everywhere (%d / 120)", streets))
	-- towers near the plaza: tall buildings with balconies just outside a face
	local tower = IncidentSpots.find(Config, world, "tower", bt.x, bt.z, 40, 400, rng)
	check(tower ~= nil, "a tower near the plaza")
	if tower then
		local b = world.buildings[tower.building :: number]
		check(b.top - b.base >= 60, "the tower is tall")
		for _, p in tower.points :: any do
			local out = math.abs(p[1] - b.x) > b.sx / 2 or math.abs(p[3] - b.z) > b.sz / 2
			check(out and p[2] > b.base and p[2] < b.top, "a balcony on the outside of its face")
		end
	end
	local sign = IncidentSpots.find(Config, world, "sign", bt.x, bt.z, 40, 400, rng)
	check(sign ~= nil, "a billboard near the plaza")
	if sign then
		local b = world.buildings[sign.building :: number]
		check(b.district == "Downtown" or b.district == "OldTown", "billboards are in town")
	end
	-- roof chases hop between nearby roofs; out in the fields they run the streets
	local roof = IncidentSpots.find(Config, world, "roof", bt.x, bt.z, 40, 300, rng, { hops = 6 })
	check(roof ~= nil and #(roof.points :: any) >= 3, "a roof chase near the plaza")
	if roof then
		local pts = roof.points :: any
		for i = 2, #pts do
			local d = math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][3] - pts[i - 1][3]) ^ 2)
			check(d <= 70, "each hop is under 70 studs")
		end
	end
	local farStart = IncidentSpots.find(Config, world, "street", 0, 1800, 0, 200, rng) :: any
	local path = IncidentSpots.streetPath(Config, world, farStart.x, farStart.z, 12, 45, rng)
	for i, p in path do
		check(open(p[1], p[3]), "street path point " .. i .. " is open ground")
	end
	-- the escort truck's route from a street near a safehouse
	for id = 1, 4 do
		local sh = world.safehouses[id]
		local s = IncidentSpots.find(Config, world, "street", sh.x, sh.z, 150, 450, rng)
		if s then
			local route = IncidentSpots.streetPath(Config, world, s.x, s.z, 16, 45, rng)
			check(#route >= 4, "safehouse " .. id .. " escort route has legs (" .. #route .. ")")
			for i = 2, #route do
				local mx, mz = (route[i][1] + route[i - 1][1]) / 2, (route[i][3] + route[i - 1][3]) / 2
				check(open(mx, mz), "route legs stay off buildings")
			end
		end
	end
	-- the tram runs along a Downtown tram line toward the end of it
	local d = Config.City.districts.Downtown
	local tram =
		IncidentSpots.find(Config, world, "tram", (d.minX + d.maxX) / 2, 0, 0, 2000, rng, { run = 300 })
	check(tram ~= nil, "a tram line downtown")
	if tram then
		local dir = tram.dir :: any
		local ex = tram.x + dir[1] * dir[3]
		check(ex >= d.minX and ex <= d.maxX, "the tram's run ends inside Downtown")
		check(
			open(tram.x, tram.z) and open(ex, tram.z) and open((tram.x + ex) / 2, tram.z),
			"the line is open street"
		)
	end
	-- the cat's crane is at the Docks
	local crane =
		IncidentSpots.find(Config, world, "crane", world.spots.crane.x, world.spots.crane.z, 0, 50, rng)
	check(crane ~= nil and crane.y > 20, "the cat sits up a Docks crane")
	local kinds = IncidentSpots.kinds(Config, world, bt.x, bt.z, 300)
	check(
		kinds.tower and kinds.sign and kinds.street and kinds.roof,
		"the plaza has towers, signs and streets"
	)
	-- the world boss arenas
	local found = false
	for _, lm in world.landmarks do
		if lm.id == Config.Boss.bosses.LumenMaw.arena then
			found = true
		end
	end
	check(found, "the Lumen Maw's Old Quarry is on the map")
	local ax, _, az = IncidentSpots.groundNear(Config, world, bt.x, bt.z + 84, 50, rng)
	check(open(ax, az), "Rustjaw Prime lands on open street by the plaza")
end)

test("M6: a new account sees a boss within 8 minutes; heroes and villains share one bar", function()
	-- a fresh server waits 10 minutes, but a never-fought player joining at 60 s pulls it to 6 minutes later
	local startAt = Config.Boss.schedule.firstAfterBoot
	local joined = 60
	startAt = BossMath.clampForNewPlayer(Config, startAt, joined)
	check(startAt - joined <= 8 * 60, "within 8 minutes of joining")
	-- a hero (id 1) and a villain (id 2) hit the same boss: both land in one ledger and one HP pool
	local sim = BossSim.new(Config, "RustjawPrime", 0, 0, 0, 64000, 20, 0, Rng.new(3))
	BossSim.step(sim, 6, {})
	local dealt1 = BossSim.damage(sim, "body", 1000)
	local dealt2 = BossSim.damage(sim, "body", 1000)
	check(sim.hp == 62000 and dealt1 == 1000 and dealt2 == 1000, "one shared bar")
	local tiers = BossMath.tiers(
		Config,
		BossMath.scores(Config, {
			[1] = { damage = 1000, support = 0, objectives = 0 },
			[2] = { damage = 1000, support = 0, objectives = 0 },
		})
	)
	check(tiers[1] ~= nil and tiers[2] ~= nil, "both sides earn a tier")
end)

---------------------------------------------------------------------------
-- M7: opening, Act 1, missions, side quests
---------------------------------------------------------------------------

test("M7: Act 1 has 6 missions in order with level gates; replays pay once", function()
	local StoryPlan = require("../src/shared/StoryPlan")
	local S = Config.Story
	check(#S.missions == 6 and S.missions[1].opening, "6 missions, the first is the opening")
	local story = ProfileSchema.newCharacter().story
	check(StoryPlan.state(Config, story, 1, 2) == "locked", "mission 2 waits for the opening")
	check(not StoryPlan.canEnter(Config, story, 40, 1), "mission 1 is not entered from the board")
	check(StoryPlan.clear(story, 1) and not StoryPlan.clear(story, 1), "a first clear counts once")
	check(StoryPlan.state(Config, story, 2, 2) == "level", "mission 2 needs level 3")
	check(StoryPlan.canEnter(Config, story, 3, 2), "level 3 opens mission 2")
	check(StoryPlan.state(Config, story, 40, 3) == "locked", "mission 3 waits for mission 2")
	for n = 2, 6 do
		StoryPlan.clear(story, n)
	end
	check(StoryPlan.nextMission(Config, story) == nil, "Act 1 done")
	check(StoryPlan.canEnter(Config, story, 40, 4), "cleared missions can be replayed")
	check(StoryPlan.actSkillPoints(Config) == 8, "Act 1 grants 8 Skill Points in all")
	for n = 2, 6 do
		local m = S.missions[n]
		check(m.layout ~= nil and #m.hero > 0 and #m.villain == #m.hero, m.id .. ": both routes, same length")
	end
end)

test("M7: choices pick once, pay once, and change one step of a mission", function()
	local StoryPlan = require("../src/shared/StoryPlan")
	local story = ProfileSchema.newCharacter().story
	local before = StoryPlan.steps(Config, 2, "hero", story.choices)
	check(#before == 2, "the branch waits for its choice")
	check(StoryPlan.pendingBranch(Config, 2, "hero", 3) == 1, "step 3 is choice 1's branch")
	local ok, fx = StoryPlan.pick(Config, story, 1, 1, "hero")
	check(ok and fx.skillPoints == 2 and fx.rep[1] == "city" and fx.gadget == "Decoy", "Save the Train")
	check(not StoryPlan.pick(Config, story, 1, 2, "hero"), "a choice is picked only once")
	local after = StoryPlan.steps(Config, 2, "hero", story.choices)
	check(#after == 3 and after[3].train, "the train branch goes in")
	local villain = ProfileSchema.newCharacter("villain").story
	local _, vfx = StoryPlan.pick(Config, villain, 1, 2, "villain")
	check(vfx.rep[1] == "syndicate" and vfx.credits == 600, "a villain's own-side rep is the Syndicate")
	check(StoryPlan.labels(Config, 1, "villain")[2] == "Chase the Rival", "villain button labels")
	-- Trust Her: the mission 5 gauntlet loses 2 turrets; Test Her: an ambush step in mission 4
	local trust = ProfileSchema.newCharacter().story
	StoryPlan.pick(Config, trust, 2, 1, "hero")
	local m5 = StoryPlan.steps(Config, 5, "hero", trust.choices)
	check(m5[2].turrets == 2, "a shortcut through the gauntlet")
	check(#StoryPlan.steps(Config, 4, "hero", trust.choices) == 3, "trust: no ambush")
	local test2 = ProfileSchema.newCharacter().story
	StoryPlan.pick(Config, test2, 2, 2, "hero")
	check(#StoryPlan.steps(Config, 4, "hero", test2.choices) == 4, "test: an ambush")
	check(StoryPlan.steps(Config, 5, "hero", test2.choices)[2].turrets == 4, "no shortcut")
	local spare = ProfileSchema.newCharacter().story
	StoryPlan.pick(Config, spare, 3, 1, "hero")
	check(StoryPlan.bit(spare.perks, 1), "Spare the Core unlocks Null Echo")
end)

test("M7: 8 side quest arcs of 3 steps; steps advance to done; the journal pins one step", function()
	local StoryPlan = require("../src/shared/StoryPlan")
	local S = Config.Story
	check(#S.quests == 8, "8 arcs")
	for _, q in S.quests do
		check(#q.steps == 3 and #q.lines == 3 and q.reward ~= nil, q.id .. ": 3 steps, 3 lines, a reward")
		for _, st in q.steps do
			check(StoryPlan.need(st) >= 1, q.id .. " " .. st.kind .. " needs something")
		end
	end
	local story = ProfileSchema.newCharacter().story
	check(StoryPlan.startQuest(story, 2) and not StoryPlan.startQuest(story, 2), "start once")
	story.pinned = 2
	check(StoryPlan.pinnedText(Config, story, "hero") == S.quests[2].steps[1].text, "pinned quest step")
	check(
		StoryPlan.advanceQuest(story, 2) == "next" and StoryPlan.advanceQuest(story, 2) == "next",
		"steps 2, 3"
	)
	check(StoryPlan.advanceQuest(story, 2) == "done" and story.quests[2] == 4, "then done")
	check(StoryPlan.advanceQuest(story, 2) == nil, "a done arc stays done")
	story.pinned = 0
	check(StoryPlan.pinnedText(Config, story, "villain") == "Mission 1: Shardfall", "else the next mission")
	check(StoryPlan.npcName(Config, 4, "villain") == "The Velvet Paw", "villains train with the Velvet Paw")
	check(
		GearMath.questStyle(Config, "MayorsSash") ~= nil and GearMath.questStyle(Config, "DockCoat") ~= nil,
		"quest styles"
	)
	check(StoryPlan.repRank(Config, 0) == 0 and StoryPlan.repRank(Config, 650) == 3, "rep ranks")
	check(StoryPlan.repRank(Config, 99999) == 5, "rank 5 is the top")
end)

test("M7: save version 3: returning heroes skip the opening; story numbers are repaired", function()
	check(ProfileSchema.VERSION >= 3, "version 3 or later")
	local old =
		ProfileSchema.load({ version = 2, characters = { { level = 7, xp = 10 }, { level = 1, xp = 0 } } })
	check(old.characters[1].story.opening == 1 and old.characters[1].story.missions == 1, "a played hero")
	check(old.characters[2].story.opening == 0, "a fresh hero still gets the opening")
	local bad = ProfileSchema.load({
		version = 3,
		characters = { { story = { missions = 999, quests = { 9, -1 }, choices = { 5 }, pinned = 40 } } },
	})
	local st = bad.characters[1].story
	check(st.missions == 63 and st.quests[1] == 4 and st.quests[2] == 0 and st.quests[8] == 0, "clamped")
	check(st.choices[1] == 2 and st.choices[3] == 0 and st.pinned == 8, "choices and pin clamped")
	check(
		#bad.frames == ProfileSchema.SMALL_WORDS and #bad.props == ProfileSchema.SMALL_WORDS,
		"new unlock words"
	)
end)

test("M7: the opening's drones: the first never fires and falls in 2 hits; the second hits weakly", function()
	local sim = EnemySim.new(Config, {
		random = function()
			return 0.5
		end,
	})
	local a = EnemySim.spawn(sim, "SparkDrone", 0, 20, 0, 1) :: any
	local b = EnemySim.spawn(sim, "SparkDrone", 10, 20, 0, 1) :: any
	a.dmgMult, a.hitLife = 0, 2
	b.dmgMult, b.hitLife = Config.Story.opening.secondDamage, 4
	local killed = EnemySim.damage(sim, a.id, 1, 1)
	check(not killed and a.health > 0, "1 hit: still up")
	killed = EnemySim.damage(sim, a.id, 1, 1)
	check(killed, "2 hits: down")
	for _ = 1, 3 do
		check(not (EnemySim.damage(sim, b.id, 1, 1)), "the second takes 4")
	end
	check((EnemySim.damage(sim, b.id, 1, 1)), "4 hits: down")
	-- a harmless drone near a hero for 20 s fires nothing
	local c = EnemySim.spawn(sim, "SparkDrone", 0, 20, 0, 1) :: any
	c.dmgMult, c.hitLife = 0, 2
	EnemySim.drainEvents(sim)
	local shots = 0
	for i = 1, 200 do
		EnemySim.step(sim, i * 0.1, { { id = 1, x = 0, y = 18, z = 12, alive = true } })
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "shot" or ev.k == "hit" then
				shots += 1
			end
		end
	end
	check(shots == 0, "the first drone never attacks back")
end)

test(
	"M7: the opening route is real for every seed: roofs within one Leap, a tram, the shard, a pad, the Docks",
	function()
		local OpeningPlan = require("../src/shared/OpeningPlan")
		local O = Config.Story.opening
		local gy = Config.City.ground.y
		for _, seed in { 202647, 11, 777, 31337 } do
			local w = if seed == 202647 then world else WorldMap.build(Config, seed)
			for k = 1, 5 do
				local r = OpeningPlan.route(Config, w, Rng.new(seed + k))
				check(r ~= nil, "a route for seed " .. seed)
				if r then
					local h = r.start[2] - gy
					check(h >= O.startRoof.minH and h <= O.startRoof.maxH + 2, "start roof height " .. h)
					local px, pz = OpeningPlan.plaza(w)
					check(
						math.sqrt((r.start[1] - px) ^ 2 + (r.start[3] - pz) ^ 2) <= O.startRoof.near,
						"near the plaza"
					)
					local gap = math.sqrt((r.leap[1] - r.start[1]) ^ 2 + (r.leap[3] - r.start[3]) ^ 2)
					check(
						gap >= O.leapRoof.minGap and gap <= Config.Move.leap.range,
						"the next roof is one Leap away"
					)
					check(r.leap[2] <= r.start[2] + 12, "not higher than a Leap climbs")
					check(
						HeightMap.at(w.heights, r.tram[1], r.tram[3]) <= gy + 1.5,
						"the tram is on the street"
					)
					check(
						HeightMap.at(w.heights, r.shard[1], r.shard[3]) <= gy + 1.5,
						"the shard is on open ground"
					)
					local pg = math.sqrt((r.pad[1] - r.shard[1]) ^ 2 + (r.pad[3] - r.shard[3]) ^ 2)
					check(pg >= O.rescueGap[1] and pg <= O.rescueGap[2], "the rescue pad gap")
					local eg = math.sqrt((r.escape[1] - r.shard[1]) ^ 2 + (r.escape[3] - r.shard[3]) ^ 2)
					check(eg >= O.escape[1] and eg <= O.escape[2], "the escape run")
					check(r.beacon > 0 and w.beacons[r.beacon] ~= nil, "a first beacon")
					check(
						OpeningPlan.at(Config, r.leap, r.leap[1] + 5, r.leap[2], r.leap[3]),
						"standing on the roof counts"
					)
					check(
						not OpeningPlan.at(Config, r.leap, r.leap[1], r.leap[2] - 30, r.leap[3]),
						"the street below does not"
					)
				end
			end
		end
	end
)

test("M7: 7 sealed pockets at y 3,000; every layout has its points", function()
	local PocketLayout = require("../src/shared/PocketLayout")
	local S = Config.Story
	local seen = {}
	for i = 1, S.pockets.count do
		local x, y, z = PocketLayout.centre(Config, i)
		check(
			y == 3000 and math.abs(x) < Config.City.mapSize / 2 and math.abs(z) < Config.City.mapSize / 2,
			"pocket " .. i .. " in the map"
		)
		check(PocketLayout.at(Config, x + 150, y + 10, z - 150) == i, "points inside pocket " .. i)
		for j = 1, i - 1 do
			local ox, _, oz = PocketLayout.centre(Config, j)
			check(
				math.abs(ox - x) >= S.pockets.size or math.abs(oz - z) >= S.pockets.size,
				"pockets do not overlap"
			)
		end
	end
	check(PocketLayout.at(Config, 0, 50, 0) == nil, "the city is not a pocket")
	local need = {
		station = { points = { "spawn", "trainStart" }, lists = { stations = 3, crates = 3, path = 3 } },
		tower = { points = { "spawn", "top", "mast", "boss" }, lists = {} },
		rooftops = { points = { "spawn", "contact" }, lists = { path = 8 } },
		dungeon = { points = { "spawn", "gauntletEnd", "boss" }, lists = { rooms = 3, turrets = 4 } },
		arena = { points = { "spawn", "boss" }, lists = { pillars = 6 } },
	}
	for n = 2, 6 do
		local m = S.missions[n]
		local l = PocketLayout.build(Config, n, m.layout)
		seen[m.layout] = true
		local want = need[m.layout]
		for _, p in want.points do
			check(l.points[p] ~= nil, m.layout .. " has " .. p)
		end
		for list, count in want.lists do
			check(
				l.lists[list] ~= nil and #l.lists[list] >= count,
				m.layout .. " has " .. count .. " " .. list
			)
		end
		check(#l.boxes < 400, m.layout .. " stays under 400 parts (" .. #l.boxes .. ")")
		local sp = l.points.spawn
		check(PocketLayout.at(Config, sp[1], sp[2], sp[3]) == n, m.layout .. " spawn is inside its pocket")
	end
	check(seen.station and seen.tower and seen.rooftops and seen.dungeon and seen.arena, "5 layouts")
	-- robots stand on the pocket's own boxes: the tower top, a roof, the floor, never the dungeon ceiling
	local tower = PocketLayout.build(Config, 3, "tower")
	local top = tower.points.top
	near(PocketLayout.heightAt(tower, top[1], top[3]), top[2] - 1, 1.5, "the tower deck")
	near(PocketLayout.heightAt(tower, tower.cx + 150, tower.cz + 150), tower.floorY, 0.01, "the pocket floor")
	local dungeon = PocketLayout.build(Config, 5, "dungeon")
	local room = dungeon.lists.rooms[2]
	near(PocketLayout.heightAt(dungeon, room[1], room[3]), dungeon.floorY, 0.01, "not the ceiling")
	check(
		PocketLayout.heightAt(dungeon, dungeon.cx, dungeon.cz + 60) > dungeon.floorY + 20,
		"the dungeon walls block"
	)
end)

test(
	"M7: the War-Frame: cannons, a phase 2 shield broken by 3 back hits, drones, pillars block the laser",
	function()
		check(BossMath.warframeHp(Config, 20) == 36000, "36,000 HP at level 20")
		check(BossMath.warframeHp(Config, 10) < 36000, "scaled by the party's level")
		local sim = BossSim.new(Config, "NullWarFrame", 0, 0, 0, 36000, 20, 0, Rng.new(5))
		BossSim.step(sim, 6, {})
		check(#sim.objectives == 2, "2 shoulder cannons")
		BossSim.damage(sim, "body", 36000 * 0.35)
		local ev = BossSim.drain(sim)
		local summon, shield = false, false
		for _, e in ev do
			summon = summon or (e.k == "summon" and e.n == 6)
			shield = shield or (e.k == "shield" and e.left == 3)
		end
		check(sim.phase == 2 and summon and shield, "phase 2 calls 6 drones and raises the shield")
		local hp = sim.hp
		BossSim.damage(sim, "body", 5000)
		check(sim.hp == hp, "the shield stops body damage")
		for _ = 1, 3 do
			BossSim.damage(sim, "back", 10)
		end
		check(sim.shield == 0, "3 back hits break it")
		BossSim.damage(sim, "body", 1000)
		check(sim.hp < hp, "damage gets through again")
		-- the charged laser: a pillar between the boss and a hero blocks it
		sim.cover = { { 0, -40, 7 } }
		BossSim.damage(sim, "body", sim.hp - 36000 * 0.2)
		check(sim.phase == 3, "phase 3")
		-- the laser aims at the nearest hero: behind the pillar it never lands, in the open it does
		local heroes = bossHeroes({ { 0, 0, -80 } })
		local t = 6
		local function laserHits(): (number, number)
			local fired, hit = 0, 0
			for _ = 1, 400 do
				t += 0.1
				BossSim.step(sim, t, heroes)
				for _, e in BossSim.drain(sim) do
					if e.k == "strike" and e.a == "ChargeLaser" then
						fired += 1
						hit += #e.hits
					end
				end
			end
			return fired, hit
		end
		local f1, h1 = laserHits()
		check(f1 > 0 and h1 == 0, "the hero behind the pillar is safe from the laser")
		sim.cover = {}
		local f2, h2 = laserHits()
		check(f2 > 0 and h2 > 0, "the hero in the open is hit")
		check(sim.state == "fight", "it never retreats")
	end
)

---------------------------------------------------------------------------
-- M8: PvP, death, anti-exploit
---------------------------------------------------------------------------

test(
	"M8: the flag: level 10, 5 s between switches, 60 s after PvP damage, never off in the Crater",
	function()
		local PvpRules = require("../src/shared/PvpRules")
		local f = PvpRules.newFlag()
		check(not PvpRules.flagged(Config, f, 30), "off by default")
		check(
			select(2, PvpRules.canSet(Config, f, true, { level = 9, safe = false, now = 100 })) == "level",
			"level 9 has no flag"
		)
		check(
			select(2, PvpRules.canSet(Config, f, true, { level = 12, safe = true, now = 100 })) == "safe",
			"not in a safe area"
		)
		check(PvpRules.canSet(Config, f, true, { level = 12, safe = false, now = 100 }), "on at once")
		PvpRules.set(f, true, 100)
		check(PvpRules.flagged(Config, f, 12), "flagged")
		check(
			select(2, PvpRules.canSet(Config, f, false, { level = 12, safe = false, now = 103 })) == "rate",
			"5 s rule"
		)
		PvpRules.notePvp(f, 104)
		check(
			select(2, PvpRules.canSet(Config, f, false, { level = 12, safe = false, now = 160 })) == "combat",
			"60 s after PvP damage"
		)
		near(PvpRules.offIn(Config, f, 160), 4, 0.01, "4 s left")
		check(
			PvpRules.canSet(Config, f, false, { level = 12, safe = false, now = 164.5 }),
			"off after 60 quiet seconds"
		)
		-- the Crater: a 5 s warning, then forced; never off inside; level 9 is never forced
		f.pvpAt = -1e9
		check(PvpRules.craterStep(Config, f, true, 12, 200) == "warn", "warning ring")
		check(PvpRules.craterStep(Config, f, true, 12, 203) == nil, "still warning at 3 s")
		check(PvpRules.craterStep(Config, f, true, 12, 205.1) == "in", "forced after 5 s")
		check(
			select(2, PvpRules.canSet(Config, f, false, { level = 12, safe = false, now = 300 })) == "crater",
			"never off in the Crater"
		)
		PvpRules.set(f, false, 0) -- even with the switch off ...
		check(PvpRules.flagged(Config, f, 12), "... the Crater keeps PvP on")
		check(
			PvpRules.craterStep(Config, f, false, 12, 301) == "out" and not PvpRules.flagged(Config, f, 12),
			"leaving ends it"
		)
		local low = PvpRules.newFlag()
		PvpRules.craterStep(Config, low, true, 9, 0)
		PvpRules.craterStep(Config, low, true, 9, 30)
		check(low.crater == "warn" and not PvpRules.flagged(Config, low, 9), "level 9 is never forced in")
		local centre = { x = 1000, z = -1000 }
		check(
			PvpRules.inCrater(centre, 400, 1190, -810) and not PvpRules.inCrater(centre, 400, 1210, -1000),
			"400 x 400"
		)
	end
)

test("M8: hits read both flags at the moment of the hit; safe areas, protection and allies block", function()
	local PvpRules = require("../src/shared/PvpRules")
	local function side(id: number, on: boolean): any
		local f = PvpRules.newFlag()
		f.on = on
		return { id = id, flag = f, level = 20, alive = true, safe = false }
	end
	local a, b, c = side(1, true), side(2, true), side(3, false)
	check(PvpRules.canHit(Config, a, b, false, 10), "two flagged players fight")
	check(not PvpRules.canHit(Config, a, c, false, 10), "never an unflagged player")
	check(not PvpRules.canHit(Config, c, a, false, 10), "an unflagged player cannot hit a flagged one")
	check(not PvpRules.canHit(Config, a, b, true, 10), "allies skip each other")
	b.safe = true
	check(
		not PvpRules.canHit(Config, a, b, false, 10) and not PvpRules.canHit(Config, b, a, false, 10),
		"safe both ways"
	)
	b.safe = false
	PvpRules.protect(Config, b.flag, 10)
	check(not PvpRules.canHit(Config, a, b, false, 12), "5 s spawn protection")
	check(PvpRules.canHit(Config, a, b, false, 15.1), "over after 5 s")
	PvpRules.endProtect(b.flag)
	PvpRules.protect(Config, b.flag, 16)
	check(not PvpRules.protected(b.flag, 17), "protection cannot be reused in one life")
	PvpRules.newLife(b.flag)
	PvpRules.protect(Config, b.flag, 30)
	check(PvpRules.protected(b.flag, 31), "a new life protects again")
	-- the flag is read at hit time: switching off mid-air stops the hit
	a.flag.on = false
	check(not PvpRules.canHit(Config, a, side(4, true), false, 40), "a flag that went off stops hits")
	-- support: an unflagged healer cannot help a flagged player in PvP combat
	local healer, fighter = side(5, false), side(6, true)
	check(PvpRules.canSupport(Config, healer, fighter, false, 50), "out of PvP combat: fine")
	PvpRules.notePvp(fighter.flag, 49)
	check(not PvpRules.canSupport(Config, healer, fighter, false, 50), "no invincible healers")
	check(
		not PvpRules.canSupport(Config, side(7, true), fighter, false, 50),
		"a flagged stranger cannot either"
	)
	check(PvpRules.canSupport(Config, side(8, true), fighter, true, 50), "a flagged ally can")
	check(PvpRules.canSupport(Config, healer, fighter, false, 65), "15 s later it is fine again")
end)

test("M8: stat compression: best gear is about 10% stronger; supers 60%; perks off or half", function()
	local PvpRules = require("../src/shared/PvpRules")
	local base = Config.Stats.power.base + Config.Stats.power.perLevel * 30
	near(PvpRules.power(Config, 30, 0), base, 0.01, "no gear: the baseline")
	near(PvpRules.power(Config, 30, base * 5), base * 1.1, 0.01, "huge gear: +10% at most")
	near(PvpRules.power(Config, 30, base * 0.5), base * 1.05, 0.01, "half the baseline in gear: +5%")
	near(PvpRules.power(Config, 55, 0), PvpRules.power(Config, 40, 0), 0.01, "level capped at 40")
	local hp0 = PvpRules.health(Config, 30, 0, "Powerhouse")
	near(PvpRules.health(Config, 30, 4000, "Powerhouse"), hp0 * 1.1, 0.01, "health compresses too")
	-- a geared target dies in as many hits as its compressed health takes
	local maxHealth = Formulas.health(Config, 30, 400, "Elemental")
	local pvpHealth = PvpRules.health(Config, 30, 400, "Elemental")
	local d = PvpRules.damage(
		Config,
		100,
		{ power = 300, pvpPower = 300, maxHealth = maxHealth, pvpHealth = pvpHealth }
	)
	near(maxHealth / d, pvpHealth / 100, 0.01, "hits to defeat match the compressed pool")
	local s = PvpRules.damage(
		Config,
		100,
		{ power = 300, pvpPower = 300, maxHealth = 1, pvpHealth = 1, super = true }
	)
	near(s, 60, 0.01, "supers deal 60%")
	check(
		PvpRules.perk(Config, "LuckyStrike") == 0 and PvpRules.perk(Config, "SecondWind") == 0.5,
		"perk table"
	)
	near(PvpRules.minor(Config, 400), 100, 0.01, "Focus, Precision, Resolve at a quarter")
	-- stuns and roots: halved on repeats within 8 s, then 3 s immune (Status, pvp = true)
	local Status = require("../src/shared/Status")
	local book = Status.new()
	local d1 = Status.apply(book, "stun", 2, 0, { pvp = true })
	check(d1 == 2, "first stun in full")
	check(Status.apply(book, "stun", 2, 3, { pvp = true }) == 0, "immune for 3 s after it ends")
	local d2 = Status.apply(book, "stun", 2, 5.5, { pvp = true })
	near(d2, 1, 0.01, "a repeat within 8 s is halved")
	check(Status.apply(book, "slow", 2, 6, { pvp = true }) > 0, "slows have no diminishing returns")
end)

test(
	"M8: PvP defeat: 5% of on-hand Credits above 500 (max 300); rewards 40 + 2 x level and 15 Fame",
	function()
		local PvpRules = require("../src/shared/PvpRules")
		check(PvpRules.loss(Config, 400) == 0, "the first 500 are safe")
		check(PvpRules.loss(Config, 2500) == 100, "5% above 500")
		check(PvpRules.loss(Config, 100000) == 300, "at most 300")
		local credits, fame = PvpRules.reward(Config, 20, 1)
		check(credits == 80 and fame == 15, "40 + 2 x 20 Credits, 15 Fame")
		local hc, hf = PvpRules.reward(Config, 20, 0.5)
		check(hc == 40 and hf == 7, "half")
	end
)

test(
	"M8: anti-farming: 2 paid wins per target in 30 min, level gap, same side, boss, 3-and-3 trades",
	function()
		local PvpRules = require("../src/shared/PvpRules")
		local L = PvpRules.newLedger()
		local even = { winnerLevel = 20, loserLevel = 20, sameSide = false, inBoss = false }
		check(PvpRules.win(Config, L, 1, 2, 0, even) == 1, "first win pays")
		check(PvpRules.win(Config, L, 1, 2, 60, even) == 1, "second win pays")
		local f3, why = PvpRules.win(Config, L, 1, 2, 120, even)
		check(f3 == 0 and why == "repeat", "third win in 30 min pays nothing")
		check(PvpRules.win(Config, L, 1, 2, 120 + 1801, even) == 1, "pays again after 30 min")
		check(
			PvpRules.win(
				Config,
				L,
				1,
				3,
				10,
				{ winnerLevel = 30, loserLevel = 20, sameSide = false, inBoss = false }
			) == 0,
			"10 levels down pays nothing"
		)
		check(
			PvpRules.win(
				Config,
				L,
				1,
				4,
				10,
				{ winnerLevel = 30, loserLevel = 21, sameSide = false, inBoss = false }
			) == 1,
			"9 levels down pays"
		)
		check(
			PvpRules.win(
				Config,
				L,
				1,
				5,
				10,
				{ winnerLevel = 20, loserLevel = 20, sameSide = true, inBoss = false }
			) == 0.5,
			"same side half"
		)
		check(
			PvpRules.win(
				Config,
				L,
				1,
				6,
				10,
				{ winnerLevel = 20, loserLevel = 20, sameSide = false, inBoss = true }
			) == 0.5,
			"boss fight half"
		)
		-- alt farming: A and B trade 3 wins each inside an hour
		local T = PvpRules.newLedger()
		local t = 0
		local paid = 0
		for _ = 1, 3 do
			t += 300
			paid += PvpRules.win(Config, T, 10, 11, t, even)
			t += 300
			paid += PvpRules.win(Config, T, 11, 10, t, even)
		end
		check(#T.review == 1, "the pair is logged for review once")
		check(PvpRules.win(Config, T, 10, 11, t + 2000, even) == 0, "zero both ways ...")
		check(PvpRules.win(Config, T, 11, 10, t + 2001, even) == 0, "... for the hour")
		check(#T.review == 1, "still one review row")
	end
)

test("M8: Downed, revive and Fame: ranks at 0 to 13,000, sources and the Warden revive", function()
	local PvpRules = require("../src/shared/PvpRules")
	check(
		PvpRules.reviveTime(Config, "Mystic") == 1.5 and PvpRules.reviveTime(Config, "Powerhouse") == 3,
		"revive times"
	)
	check(PvpRules.fameRank(Config, 0) == 1 and PvpRules.fameRank(Config, 99) == 1, "rank 1")
	check(PvpRules.fameRank(Config, 100) == 2 and PvpRules.fameRank(Config, 12999) == 9, "ranks")
	check(PvpRules.fameRank(Config, 13000) == 10 and PvpRules.nextRank(Config, 13000) == nil, "top rank")
	check(PvpRules.nextRank(Config, 150) == 300, "next at 300")
	check(
		PvpRules.fameFor(Config, "rescue", "hero") == 2 and PvpRules.fameFor(Config, "rescue", "villain") == 3,
		"rescues"
	)
	check(
		PvpRules.fameFor(Config, "bossMvp", "hero") == 50 and PvpRules.fameFor(Config, "pvp", "villain") == 15,
		"boss and PvP"
	)
	check(PvpRules.fameFor(Config, "nothing", "hero") == 0, "unknown pays nothing")
	local GearMath = require("../src/shared/GearMath")
	for i, row in Config.Pvp.fame.ranks do
		local r = row.reward
		if r.style then
			check(GearMath.questStyle(Config, r.style) ~= nil, "rank " .. i .. " style exists")
		end
		for _, kind in { "emote", "frame", "title", "trim" } do
			local name = r[kind]
			if name then
				local words = if kind == "trim" then "titles" else kind .. "s"
				check(Config.Story.unlocks[words][name] ~= nil, "rank " .. i .. " " .. kind .. " has a bit")
			end
		end
	end
end)

test("M8: strikes kick at 3 in 10 min (never ban); reports flag at 3 accounts in 10 min", function()
	local GuardRules = require("../src/shared/GuardRules")
	local s = GuardRules.newStrikes()
	check(not GuardRules.strike(Config, s, "speed", 0), "1 strike")
	check(not GuardRules.strike(Config, s, "speed", 100), "2 strikes")
	check(GuardRules.strike(Config, s, "speed", 200), "3 in 10 minutes kick")
	local s2 = GuardRules.newStrikes()
	GuardRules.strike(Config, s2, "speed", 0)
	GuardRules.strike(Config, s2, "speed", 300)
	check(not GuardRules.strike(Config, s2, "speed", 700), "spread over more than 10 minutes: no kick")
	-- dropped remotes: honest lag never strikes; a flood does
	local s3 = GuardRules.newStrikes()
	local struck = false
	for i = 1, 9 do
		struck = struck or GuardRules.netDrop(Config, s3, i * 70)
	end
	check(not struck and #s3.times == 0, "a drop a minute never strikes")
	for i = 1, 30 do
		GuardRules.netDrop(Config, s3, 1000 + i * 0.1)
	end
	check(#s3.times == 3, "a flood counts strikes")
	check(
		not GuardRules.needsReview(Config, 1) and GuardRules.needsReview(Config, 2),
		"repeated kicks go to review"
	)
	local R = GuardRules.newReports()
	check(not GuardRules.report(Config, R, 1, 1, 0), "never yourself")
	local ok1, f1 = GuardRules.report(Config, R, 1, 9, 0)
	check(ok1 and not f1, "one report")
	check(not GuardRules.report(Config, R, 1, 9, 60), "one per reporter per target per 10 min")
	GuardRules.report(Config, R, 2, 9, 100)
	local ok3, f3 = GuardRules.report(Config, R, 3, 9, 200)
	check(ok3 and f3, "3 accounts in 10 minutes flag for review")
	local R2 = GuardRules.newReports()
	GuardRules.report(Config, R2, 1, 9, 0)
	GuardRules.report(Config, R2, 2, 9, 400)
	local _, late = GuardRules.report(Config, R2, 3, 9, 700)
	check(not late, "spread past 10 minutes: not flagged")
end)

---------------------------------------------------------------------------
-- M9: creator, HQ, shop, passes, Legacy
---------------------------------------------------------------------------

local function isAnime(tab: string, kit: string): boolean
	return tab == "hair"
		or tab == "eyes"
		or string.sub(kit, 1, 5) == "coat:"
		or string.sub(kit, 1, 6) == "scarf:"
		or string.sub(kit, 1, 5) == "wraps"
end

test(
	"M9: the creator has the 116 spec pieces (30 free, 52 loot, 34 Robux), 28 anime pieces, real sources",
	function()
		local CreatorRules = require("../src/shared/CreatorRules")
		local C = Config.Creator
		local want = {
			suit = { 5, 5, 4 },
			back = { 3, 5, 4 },
			head = { 5, 6, 5 },
			hands = { 3, 3, 2 },
			feet = { 3, 3, 2 },
			emblem = { 8, 20, 12 },
			aura = { 0, 4, 2 },
			trail = { 2, 4, 2 },
			voice = { 1, 2, 1 },
		}
		local spec, anime = { 0, 0, 0 }, { 0, 0, 0 }
		local names = {}
		local idx = CreatorRules.index(Config)
		for _, tab in C.tabs do
			local got = { 0, 0, 0 }
			for _, p in idx.byTab[tab.id] do
				check(not names[p.name], "piece names are unique: " .. p.name)
				names[p.name] = true
				local k = p.source.kind
				local col = if k == "free" then 1 elseif k == "pack" then 3 elseif k == "starter" then 0 else 2
				if col > 0 and p.id <= 146 then -- the M9 spec counts (the creator plan's pieces come after)
					local into = if isAnime(tab.id, p.kit) then anime else spec
					into[col] += 1
					if not isAnime(tab.id, p.kit) then
						got[col] += 1
					end
				end
				-- every source names something real
				if k == "rep" then
					check(
						table.find(Config.Story.rep.order, p.source.a) ~= nil and (p.source.n or 0) <= 5,
						p.name
					)
				elseif k == "boss" then
					check(table.find(Config.Boss.order, p.source.a) ~= nil and (p.source.n or 0) <= 3, p.name)
				elseif k == "mission" then
					check(Config.Story.missions[p.source.n or 0] ~= nil, p.name .. " mission")
				elseif k == "quest" then
					check(Config.Story.quests[p.source.n or 0] ~= nil, p.name .. " quest")
				elseif k == "fame" then
					check((p.source.n or 0) <= #Config.Pvp.fame.ranks, p.name .. " fame")
				elseif k == "lvl" then
					check((p.source.n or 0) <= 40, p.name)
				elseif k == "legacy" then
					check((p.source.n or 0) <= Config.Hq.legacy.maxRanks, p.name)
				elseif k == "pack" then
					check(Config.Shop.packs[p.source.n or 0] ~= nil, p.name .. " pack")
				else
					check(k == "free" or k == "drop" or k == "starter", p.name .. " source " .. k)
				end
				if tab.id == "emblem" then
					check(C.shapes[string.split(p.kit, ":")[1]] ~= nil, p.name .. " shape")
				end
			end
			local w = want[tab.id]
			if w then
				check(
					got[1] == w[1] and got[2] == w[2] and got[3] == w[3],
					tab.id .. " free/loot/Robux per the spec"
				)
			end
		end
		check(
			spec[1] == 30 and spec[2] == 52 and spec[3] == 34,
			"116 spec pieces: 30 free, 52 loot, 34 Robux"
		)
		check(anime[1] == 7 and anime[2] == 13 and anime[3] == 8, "28 anime pieces: 7 free, 13 loot, 8 Robux")
		local legacy, maxId, ids = 0, 0, {}
		for _, p in idx.list do
			check(not ids[p.id], "piece ids are unique: " .. p.name)
			ids[p.id] = true
			maxId = math.max(maxId, p.id)
			if p.id <= 146 then
				legacy += 1
			end
		end
		check(legacy == 146, "the 146 M9 pieces keep ids 1 to 146")
		check(maxId < 32 * ProfileSchema.PIECE_WORDS, "every id fits the unlock set")
		check(#CreatorRules.packPieces(Config, nil) == 2, "the starter pack: a suit finish and a cape")
		local packTotal = 0
		for i = 1, 5 do
			local n = #CreatorRules.packPieces(Config, i)
			check(n >= 6 and n <= 7, "pack " .. i .. " has about 7 pieces")
			packTotal += n
		end
		check(
			packTotal == 34 and #CreatorRules.packPieces(Config, 6) == 8,
			"34 pieces in 5 packs; the anime pack has 8"
		)
		check(#C.palette == 48 and #C.skins == 30, "48 colours and 30 skins (24 natural, 6 fantasy)")
		check(#C.titles == 12 and #C.nouns == 16, "12 titles and 16 nouns")
		for _, name in C.blockedNames do
			local parts = string.split(name, " ")
			check(
				table.find(C.titles, parts[1]) ~= nil and table.find(C.nouns, parts[2]) ~= nil,
				"blocked names are wheel pairs: " .. name
			)
		end
	end
)

test(
	"M9: a look is a 128-byte record (v2), 32 words in the save; v1 records still read; empty is no look",
	function()
		local LookCodec = require("../src/shared/LookCodec")
		local look = {
			pieces = {
				suit = 3,
				back = 14,
				head = 0,
				emblem = 40,
				hair = 9,
				eyes = 6,
				hat = 12,
				backpack = 7,
				legs = 3,
			},
			colors = { 1, 12, 48 },
			hair = 13,
			skin = 30,
			anime = true,
			gender = 2,
			build = 4,
			height = 5,
			eyeColor = 46,
			tints = { hat = { 4, 0, 46 }, legs = { 0, 22, 0 } },
			mats = { hat = 3, legs = 2, backpack = 5 },
		}
		local b = LookCodec.encode(look :: any)
		check(buffer.len(b) == 128, "128 bytes")
		local words = LookCodec.toWords(b)
		check(#words == 32, "32 words")
		local back = LookCodec.read(words) :: any
		check(
			back ~= nil and back.anime == true and back.pieces.back == 14 and back.pieces.emblem == 40,
			"round trip"
		)
		check(
			back.colors[3] == 48 and back.hair == 13 and back.skin == 30 and back.pieces.head == 0,
			"colours and skin"
		)
		check(
			back.gender == 2 and back.build == 4 and back.height == 5 and back.eyeColor == 46,
			"body and eyes"
		)
		check(back.pieces.hat == 12 and back.pieces.backpack == 7 and back.pieces.legs == 3, "the new slots")
		check(
			back.tints.hat[1] == 4 and back.tints.hat[3] == 46 and back.tints.legs[2] == 22,
			"per-slot colours"
		)
		check(
			back.tints.suit == nil and back.mats.hat == 3 and back.mats.legs == 2 and back.mats.backpack == 5,
			"materials"
		)
		check(
			#LookCodec.SLOTS == 23 and LookCodec.SLOTS[11] == "eyes",
			"23 slots; the first 11 keep v1's order"
		)
		-- a version 1 record (8 words) still reads: Male, Medium, standard height, no per-slot colours
		local v1 = buffer.create(32)
		buffer.writeu8(v1, 0, 1)
		buffer.writeu8(v1, 1, 1)
		buffer.writeu8(v1, 2, 5) -- suit
		buffer.writeu8(v1, 3, 2) -- back
		buffer.writeu8(v1, 12, 4) -- eyes
		buffer.writeu8(v1, 13, 10)
		buffer.writeu8(v1, 16, 22)
		buffer.writeu8(v1, 17, 3)
		local old = LookCodec.read(LookCodec.toWords(v1)) :: any
		check(old ~= nil and #LookCodec.toWords(v1) == 8, "8-word v1 record")
		check(
			old.pieces.suit == 5 and old.pieces.back == 2 and old.pieces.eyes == 4 and old.anime,
			"v1 pieces"
		)
		check(old.colors[1] == 10 and old.hair == 22 and old.skin == 3, "v1 colours")
		check(
			old.gender == 1 and old.build == 2 and old.height == 3 and next(old.tints) == nil,
			"v1 body defaults"
		)
		check((old.pieces.hat or 0) == 0, "v1 has none of the new slots")
		local padded = table.clone(LookCodec.toWords(v1))
		for i = 9, 32 do
			padded[i] = 0
		end
		check((LookCodec.read(padded) :: any).pieces.suit == 5, "a v1 look padded to 32 words still reads")
		check(LookCodec.read(table.create(32, 0)) == nil, "all zero = no look yet")
		check(LookCodec.read({ "x", -1, 1e20 } :: any) == nil, "junk words read as no look")
		check(LookCodec.decode(buffer.create(31)) == nil, "wrong size")
		local bad = LookCodec.read(LookCodec.write({
			pieces = {},
			colors = { 0, 99, 2.5 },
			hair = 0,
			skin = 9,
			anime = false,
			gender = 7,
			build = 0,
			height = 9,
		} :: any)) :: any
		check(
			bad ~= nil and bad.colors[1] == 1 and bad.colors[3] == 1 and bad.skin == 9,
			"out of range bytes fall back (the palette check is CreatorRules.validate's)"
		)
		check(bad.gender == 1 and bad.build == 2 and bad.height == 3, "bad body bytes fall back")
	end
)

test(
	"M9: creator rules: owned pieces only, palette colours, the name filter, Randomize is always valid",
	function()
		local CreatorRules = require("../src/shared/CreatorRules")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		local profile = ProfileSchema.default()
		local look = CreatorRules.defaultLook(Config)
		check((CreatorRules.validate(Config, profile, look)), "the default look is all free pieces")
		local locked = CreatorRules.index(Config).byName["Night Patrol Suit"]
		look.pieces.suit = locked.index
		local ok, why = CreatorRules.validate(Config, profile, look)
		check(not ok and why == "locked", "a Robux piece needs its pack")
		CreatorRules.grant(profile, locked)
		check((CreatorRules.validate(Config, profile, look)), "after the pack it is open")
		look.pieces.suit = 99
		check(select(2, CreatorRules.validate(Config, profile, look)) == "piece", "no piece 99")
		look.pieces.suit = 1
		look.colors = { 1, 2, 49 }
		check(
			select(2, CreatorRules.validate(Config, profile, look)) == "color",
			"colour 49 is off the palette"
		)
		check(CreatorRules.nameOk(Config, 3, 1), "Storm Falcon is fine")
		check(CreatorRules.heroName(Config, 3, 1) == "Storm Falcon", "the name reads Title Noun")
		check(not CreatorRules.nameOk(Config, 1, 1), "Captain Falcon is blocked")
		check(
			not CreatorRules.nameOk(Config, 0, 1) and not CreatorRules.nameOk(Config, 1, 17),
			"both wheels needed"
		)
		local rng = Rng.new(9)
		for _ = 1, 300 do
			local l, t, n = CreatorRules.randomize(Config, profile, rng)
			local valid = CreatorRules.validate(Config, profile, l)
			check(valid and CreatorRules.nameOk(Config, t, n), "Randomize gives a valid look and name")
		end
		check(CreatorRules.pickOk(Config, "Rogue", "Blade", "villain"), "Blade can be a starting set")
		check(not CreatorRules.pickOk(Config, "Rogue", "Titan", "hero"), "Titan still opens by level")
		check(not CreatorRules.pickOk(Config, "Wizard", "Volt", "hero"), "classes from the list only")
		check(CreatorRules.maxSlots(profile) == 2, "2 free slots")
		profile.purchases.slots = bit32.lshift(1, 3)
		check(CreatorRules.maxSlots(profile) == 3, "slot 3 bought")
	end
)

test(
	"M9: play unlocks are account-wide and land once: levels, rep, Fame, bosses, missions, quests, Legacy",
	function()
		local CreatorRules = require("../src/shared/CreatorRules")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		local profile = ProfileSchema.default()
		check(#CreatorRules.earned(Config, profile) == 0, "a new account has earned nothing")
		local c = profile.characters[1]
		c.level = 15
		local got = {}
		for _, p in CreatorRules.earned(Config, profile) do
			got[p.name] = true
			CreatorRules.grant(profile, p)
		end
		check(got["Star Badge"] and got["Long Cape"] and got["Plated Suit"], "levels 5, 10 and 15")
		check(not got["Duster Coat"], "not level 20 yet")
		check(#CreatorRules.earned(Config, profile) == 0, "granted pieces are not earned again")
		-- a second character's progress counts for the account
		local villain = ProfileSchema.newCharacter("villain", "Powerhouse")
		villain.rep[2] = 1000 -- Syndicate rank 4
		villain.fame = 999999
		villain.story.missions = 0x3F
		villain.story.quests[4] = 4
		villain.legacy = 2
		table.insert(profile.characters, villain)
		profile.bosses[1] = 3
		local names = {}
		for _, p in CreatorRules.earned(Config, profile) do
			names[p.name] = true
		end
		check(
			names["Rib Frame"] and names["Horned Helm"] and not names["Peak Crest"],
			"Syndicate ranks 1 to 4, not 5"
		)
		check(names["Frame Helm"] and names["Orb Badge"] and names["Wind Scarf"], "mission and quest pieces")
		check(names["Spark Crest"] and names["Showboat"], "Fame ranks")
		check(
			names["Jet Boots"] and names["Reactor Core"] and names["Comet Trail"],
			"Rustjaw Prime tiers 1 to 3"
		)
		check(not names["Moon Crest"], "the Lumen Maw not yet")
		check(names["Star Crest"] and names["Royal Mantle"] and not names["Spirit Flame"], "Legacy 1 and 2")
		-- drops roll only locked drop pieces
		local rng = Rng.new(4)
		local seen = {}
		for _ = 1, 4000 do
			local p = CreatorRules.dropPick(Config, profile, rng)
			if p then
				check(p.source.kind == "drop", "drop pieces only")
				seen[p.id] = true
				CreatorRules.grant(profile, p)
			end
		end
		local left = 0
		for _, p in CreatorRules.index(Config).list do
			if p.source.kind == "drop" and not ProfileSchema.Bits.get(profile.pieces, p.id) then
				left += 1
			end
		end
		check(left == 0, "every drop piece turns up in time")
		check(CreatorRules.dropPick(Config, profile, rng) == nil, "nothing left to drop")
	end
)

test(
	"M9: purchases grant the right item once; a replayed receipt grants nothing; nothing changes a stat",
	function()
		local ShopRules = require("../src/shared/ShopRules")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		local serdeLocal = serde
		local profile = ProfileSchema.default()
		profile.currency.credits = 1234
		local function frozen(p: any): string
			return serdeLocal.encode("json", {
				p.currency,
				p.stash,
				p.styles,
				p.pity,
				p.characters[1].ranks,
				p.characters[1].level,
				p.characters[1].xp,
				p.characters[1].equipment,
			})
		end
		local before = frozen(profile)
		for key, row in Config.Shop.products do
			check(row.robux >= 25 and row.robux <= 399, key .. " priced 25 to 399")
			local ok, got = ShopRules.grant(Config, profile, key, "r-" .. key)
			check(ok and got ~= nil, key .. " grants")
			check(ShopRules.owned(Config, profile, key), key .. " is owned after")
			local again = ShopRules.grant(Config, profile, key, "r-" .. key)
			check(not again, key .. ": the same receipt grants nothing")
		end
		check(frozen(profile) == before, "no product touches Credits, gear, styles, pity, ranks or level")
		check(#profile.purchases.receipts <= 50, "receipts stay at 50")
		local p2 = ProfileSchema.default()
		check(select(2, ShopRules.available(Config, p2, "slot4")) == "slot3", "slot 4 needs slot 3")
		ShopRules.grant(Config, p2, "pack2", "a")
		check(
			select(2, ShopRules.available(Config, p2, "pack2")) == "owned",
			"an owned pack is not sold again"
		)
		check(ShopRules.grant(Config, p2, "pack3", "b"), "a new receipt for another pack grants")
		check(
			not ShopRules.grant(Config, p2, "pack4", "a"),
			"a reused receipt id never grants, even for another item"
		)
		check(
			ShopRules.grantPass(p2, "double") and not ShopRules.grantPass(p2, "double"),
			"a pass lands once"
		)
		check(ShopRules.byProductId(Config, 0) == nil, "id 0 (not made yet) never matches a receipt")
		for _, tab in Config.Shop.tabs do
			for _, key in tab.items do
				check(ShopRules.item(Config, key) ~= nil, tab.id .. " lists " .. key)
			end
		end
		-- the 2x pass is the only number: earned Credits and Renown, not Dust, gear, Fame or PvP
		check(Config.Economy.bonus.doublePass == 2, "x2 pass")
		local c1, r1 = Progress.earn(Config, "incident", 10, {})
		local c2, r2 = Progress.earn(Config, "incident", 10, { doublePass = true })
		check(c2 == 2 * c1 or math.abs(c2 - 2 * c1) <= 1, "x2 Credits")
		check(r2 == 2 * r1 or math.abs(r2 - 2 * r1) <= 1, "x2 Renown")
		check(
			ShopRules.starterDue(Config, ProfileSchema.default()) == false,
			"no starter offer before the first boss"
		)
		local p3 = ProfileSchema.default()
		p3.stats.bossesJoined = 1
		check(ShopRules.starterDue(Config, p3), "offered after the first world boss")
		p3.shop.starterSeen = 1
		check(not ShopRules.starterDue(Config, p3), "shown once")
	end
)

test("M9: the Robux shop opens only in HQ, safehouses and the menu, never mid-fight", function()
	local ShopRules = require("../src/shared/ShopRules")
	check((ShopRules.canOpen(Config, "hq", -100, 0)), "HQ")
	check((ShopRules.canOpen(Config, "safehouse", -100, 0)), "safehouse")
	check((ShopRules.canOpen(Config, "menu", -100, 0)), "menu")
	check(select(2, ShopRules.canOpen(Config, "city", -100, 0)) == "where", "not out in the city")
	check(select(2, ShopRules.canOpen(Config, "menu", 95, 100)) == "combat", "not within 10 s of a fight")
end)

test("M9: Gizmo's shop: 40 base styles for 500 to 3,000 Credits; loot never rolls the shop styles", function()
	local ShopRules = require("../src/shared/ShopRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local GearMath = require("../src/shared/GearMath")
	local list = ShopRules.gizmo(Config)
	check(#list == 40, "40 base styles")
	local shop = {}
	for _, e in list do
		check(e.price >= 500 and e.price <= 3000, "500 to 3,000")
		if e.row.tier == "Shop" then
			shop[e.id] = true
		end
	end
	local profile = ProfileSchema.default()
	profile.currency.credits = 700
	profile.currency.banked = 1000
	local id = list[1].id
	local ok, _, price = ShopRules.gizmoBuy(Config, profile, id)
	check(ok and price == list[1].price, "bought")
	check(ProfileSchema.Bits.get(profile.styles, id), "the style is unlocked")
	check(select(2, ShopRules.gizmoBuy(Config, profile, id)) == "owned", "not twice")
	check(profile.currency.credits + profile.currency.banked == 1700 - (price :: number), "Credits only")
	local rich = ShopRules.gizmo(Config)[40]
	check(select(2, ShopRules.gizmoBuy(Config, profile, rich.id)) == "credits", "needs the Credits")
	local rng = Rng.new(3)
	for _ = 1, 3000 do
		local piece = GearMath.roll(Config, rng, "Rare", 20, {})
		check(not shop[piece.style], "loot never rolls a shop style")
	end
end)

test("M9: HQ: solo cells, upgrade costs, what each level opens, offline drones cap at 8 hours", function()
	local HqRules = require("../src/shared/HqRules")
	local seen = {}
	for slot = 1, 500 do
		local x, y, z = HqRules.cell(Config, slot)
		local key = x .. "," .. z
		check(not seen[key], "one cell per hero slot")
		seen[key] = true
		check(HqRules.cellAt(Config, x + 20, y + 3, z - 20) == slot, "a point in the cell finds its slot")
		check(y > Config.Story.pockets.y + 1000, "far above the mission pockets")
	end
	check(HqRules.cellAt(Config, 0, 40, 0) == nil, "the city is not an HQ")
	local total = 0
	for lv = 1, 5 do
		total += HqRules.upgradeCost(Config, lv) :: number
	end
	check(
		total == 2000 + 5000 + 12000 + 25000 + 50000 and HqRules.upgradeCost(Config, 6) == nil,
		"levels 2 to 6"
	)
	check(HqRules.mannequins(Config, 1) == 1 and HqRules.mannequins(Config, 2) == 4, "1 look, 4 at level 2")
	check(HqRules.dummies(Config, 2) == 1 and HqRules.dummies(Config, 3) == 4, "4 dummies at level 3")
	check(not HqRules.bossSim(Config, 2) and HqRules.bossSim(Config, 3), "boss sim at level 3")
	check(
		HqRules.trophySlots(Config, 3) == 3 and HqRules.trophySlots(Config, 4) == 12,
		"12 trophies at level 4"
	)
	check(HqRules.drones(Config, 4, 3600) == 0, "drones off below level 5")
	check(HqRules.drones(Config, 5, 3600) == 120, "2 a minute at level 5")
	check(HqRules.drones(Config, 6, 3600) == 600, "10 a minute at the last level")
	check(HqRules.drones(Config, 6, 86400) == 10 * 60 * 8, "8 hours at most")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local profile = ProfileSchema.default()
	check(not HqRules.trophies(Config, profile).firstBoss, "no trophies yet")
	profile.stats.bossesJoined = 1
	profile.characters[1].level = 20
	local picks = HqRules.pickTrophies(Config, profile, 1, { 1, 5, 1, 2, 6 })
	check(#picks == 2 and picks[1] == 1 and picks[2] == 5, "only earned trophies, no repeats")
	check(#HqRules.cityProps(Config, 3) == 3, "City rank 3 opens 3 HQ props")
end)

test(
	"M9: Legacy at level 40: a statue, back to level 1, keeps unlocks and reputation, +10% Renown a rank",
	function()
		local HqRules = require("../src/shared/HqRules")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		local profile = ProfileSchema.default()
		local c = profile.characters[1]
		c.level = 39
		check(select(2, HqRules.canRetire(Config, c)) == "level", "not before 40")
		c.level = 40
		c.rep = { 900, 0, 300 }
		c.titleId, c.nounId = 3, 1
		c.fame = 5000
		c.startSet = "Blade"
		c.story.opening = 1
		c.equipment[1] = 0
		ProfileSchema.Bits.set(profile.styles, 70)
		local statue = HqRules.retire(Config, profile, 1, 1000)
		check(statue ~= nil and statue.rank == 1 and statue.level == 40, "a statue in the Hall of Legends")
		local n = profile.characters[1]
		check(n.level == 1 and n.xp == 0 and n.legacy == 1, "the slot restarts at level 1, Legacy rank 1")
		check(
			n.rep[1] == 900 and n.fame == 5000 and n.titleId == 3 and n.story.opening == 1,
			"keeps rep, Fame, name, story"
		)
		check(n.loadouts[1].set == "Blade" and n.ranks.FlashStep == 1, "starts again on its own set")
		check(
			ProfileSchema.Bits.get(profile.styles, 70) and #profile.legends == 1,
			"unlocks are account-wide"
		)
		check(
			HqRules.legacyBonus(Config, 1) == 0.10 and HqRules.legacyBonus(Config, 9) == 0.50,
			"+10% each, max 50%"
		)
		check(Config.Gear.equipSlack == 5, "old gear is wearable again at item level minus 5")
		for _ = 1, 30 do
			profile.characters[1].level = 40
			HqRules.retire(Config, profile, 1, 2000)
		end
		check(#profile.legends == Config.Hq.legacy.statues, "the hall keeps the last 20 statues")
	end
)

test("M9: save version 4: creator, shop and HQ fields are added and repaired", function()
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local old = ProfileSchema.default()
	old.version = 3
	old.pieces = nil
	old.legends = nil
	old.purchases = { passes = { double = true, junk = 5 }, receipts = { "a", 7, "b" } }
	old.characters[1].hq = { level = 1 }
	old.characters[1].look = nil
	old.characters[1].looks = { { 1, 2, 3 }, "x", { 1, 2, 3, 4, 5, 6, 7, 8 }, {}, {}, {} }
	old.characters[1].startSet = "Nonsense"
	old.characters[1].titleId = 999
	local p = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
	check(p.version == ProfileSchema.VERSION and ProfileSchema.VERSION >= 4, "version 4 or later")
	check(#p.pieces == ProfileSchema.PIECE_WORDS and #p.legends == 0, "pieces and legends added")
	check(p.purchases.passes.double == true and p.purchases.passes.junk == nil, "passes kept, junk dropped")
	check(#p.purchases.receipts == 2, "receipts are strings")
	local c = p.characters[1]
	check(
		#c.look == ProfileSchema.LOOK_WORDS and c.hq.droneAt == 0 and #c.hq.trophies == 0,
		"look and HQ fields added"
	)
	check(
		#c.looks == 4 and #c.looks[1] == ProfileSchema.LOOK_WORDS,
		"at most 4 saved looks, padded to the look size"
	)
	check(c.startSet == "Volt" and c.titleId == 64, "bad picks repaired")
	check(c.created == 0, "an older hero meets the creator once")
	local view = ProfileSchema.clientView(p)
	check(view.roster and #view.roster == 1 and view.hq.level == 1, "the client sees its roster and HQ")
end)

test("M9: 1,000 heroes over 10 hours reach level 20 to 28 and spend within 15% of the Sinks table", function()
	local EconomySim = require("../src/shared/EconomySim")
	local r = EconomySim.run(Config, 1000, 10, 2026)
	check(r.p10 >= 20 and r.p90 <= 28, string.format("levels %d to %d (median %d)", r.p10, r.p90, r.median))
	local build = EconomySim.buildCost(Config)
	check(math.abs(build - 35000) <= 35000 * 0.15, "a fully ranked 5-skill build is about 35,000 Credits")
	check(
		r.buildHours >= 12 * 0.85 and r.buildHours <= 15 * 1.15,
		string.format("earned in about 12 to 15 hours (%.1f)", r.buildHours)
	)
	local A = Config.Abilities
	check(A.rankCredits[5] == 3200 and A.superRankCredits[3] == 2400, "rank prices from the Sinks table")
	check(r.spent.ranks > 0 and r.spent.hq > 0 and r.spent.styles > 0, "heroes spend on ranks, HQ and styles")
end)

---------------------------------------------------------------------------
-- M10: settings, accessibility and squads
---------------------------------------------------------------------------

test(
	"M10: settings: every key has a default in range; values snap and clamp; bad values are refused",
	function()
		local SettingsRules = require("../src/shared/SettingsRules")
		local S = Config.Settings
		local ids = {}
		for _, k in S.keys do
			check(not ids[k.id], "unique id " .. k.id)
			ids[k.id] = true
			check(SettingsRules.value(k, k.default) == k.default, "default is valid: " .. k.id)
		end
		for _, id in { "preset", "textSize", "leftHanded", "reduceFlashing" } do
			check(ids[id], "the save keeps " .. id .. " (spec: Settings save)")
		end
		local d = SettingsRules.defaults(Config)
		check(d.textSize == 100 and d.preset == 0, "text 100% and the Auto preset by default")
		local idx
		for i, k in S.keys do
			if k.id == "textSize" then
				idx = i
			end
		end
		local s = SettingsRules.defaults(Config)
		check(SettingsRules.set(Config, s, idx, 133) and s.textSize == 130, "text size snaps to 10% steps")
		check(SettingsRules.set(Config, s, idx, 500) and s.textSize == 160, "text size tops out at 160%")
		check(SettingsRules.set(Config, s, idx, 10) and s.textSize == 100, "text size never below 100%")
		check(not SettingsRules.set(Config, s, 99, 1), "an unknown key is refused")
		check(not SettingsRules.set(Config, s, idx, 0 / 0), "NaN is refused")
		local c = SettingsRules.clean(Config, { textSize = 1.4, leftHanded = true, preset = 9, junk = 4 })
		check(c.textSize == 140, "an old scale (1.4) reads as 140%")
		check(c.leftHanded == 1 and c.preset == 3 and c.junk == nil, "booleans to 0/1, clamped, junk dropped")
		check(SettingsRules.clean(Config, "x").textSize == 100, "a broken save gets the defaults")
	end
)

test("M10: mutes: added once, removed, capped with the oldest dropped", function()
	local SettingsRules = require("../src/shared/SettingsRules")
	local list = {}
	SettingsRules.mute(Config, list, 5, true)
	SettingsRules.mute(Config, list, 5, true)
	check(#list == 1, "muted once")
	SettingsRules.mute(Config, list, 5, false)
	check(#list == 0, "unmuted")
	SettingsRules.mute(Config, list, -3, true)
	SettingsRules.mute(Config, list, 2.5, true)
	check(#list == 0, "bad ids are ignored")
	for i = 1, Config.Settings.maxMutes + 5 do
		SettingsRules.mute(Config, list, i, true)
	end
	check(#list == Config.Settings.maxMutes and list[1] == 6, "capped; the oldest drop off")
end)

test("M10: squads: invite, accept, up to 4, allies, leave and kick", function()
	local SquadRules = require("../src/shared/SquadRules")
	local Q = Config.Squad
	check(Q.max == 4, "squads of up to 4 (spec)")
	local st = SquadRules.new()
	local ok, why = SquadRules.invite(Config, st, 1, 1, 0)
	check(not ok and why == "self", "no inviting yourself")
	check(SquadRules.invite(Config, st, 1, 2, 0), "1 invites 2")
	ok, why = SquadRules.invite(Config, st, 1, 2, 1)
	check(not ok and why == "pending", "one invite at a time")
	ok, why = SquadRules.invite(Config, st, 3, 2, 1)
	check(not ok and why == "busy", "someone else's invite is waiting")
	ok, why = SquadRules.accept(Config, st, 2, Q.inviteLife + 1)
	check(not ok and why == "expired", "invites expire")
	check(SquadRules.invite(Config, st, 1, 2, 100), "invite again")
	local okA, _, squadId = SquadRules.accept(Config, st, 2, 101)
	check(okA and squadId ~= nil, "accepted: the squad is made")
	check(SquadRules.leader(st, 2) == 1, "the inviter leads")
	check(SquadRules.allies(st, 1, 2) and not SquadRules.allies(st, 1, 3), "squadmates are allies")
	check(not SquadRules.allies(st, 1, 1), "you are not your own ally")
	for u = 3, 4 do
		check(SquadRules.invite(Config, st, 2, u, 102), "any member invites")
		check((SquadRules.accept(Config, st, u, 103)), "joins")
	end
	ok, why = SquadRules.invite(Config, st, 1, 5, 104)
	check(not ok and why == "full", "a squad of 4 is full")
	ok, why = SquadRules.invite(Config, st, 5, 4, 104)
	check(not ok and why == "taken", "someone in a squad can't be invited")
	check(not SquadRules.kick(st, 2, 3), "only the leader kicks")
	check(SquadRules.kick(st, 1, 4) and st.of[4] == nil, "the leader kicks")
	SquadRules.leave(st, 1)
	check(SquadRules.leader(st, 2) == 2, "the next member leads")
	SquadRules.leave(st, 3)
	check(st.of[2] == nil and next(st.squads) == nil, "a squad of one is gone")
	check(#SquadRules.members(st, 2) == 1, "solo again")
	SquadRules.invite(Config, st, 7, 8, 0)
	SquadRules.leave(st, 7)
	check(SquadRules.pending(Config, st, 8, 1) == nil, "leaving drops the invites you sent")
end)

test("M10: party missions scale by the median level", function()
	local SquadRules = require("../src/shared/SquadRules")
	check(SquadRules.median({}) == 1, "nobody: level 1")
	check(SquadRules.median({ 30 }) == 30, "solo")
	check(SquadRules.median({ 5, 40, 12 }) == 12, "odd count")
	check(SquadRules.median({ 10, 20, 31, 2 }) == 15, "even count rounds the middle pair")
end)

test("M10: save version 5 keeps settings and mutes, repaired", function()
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local old = ProfileSchema.default()
	old.version = 4
	old.settings = nil
	old.mutes = { 3, "x", -1, 9 }
	local p = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
	check(p.version == ProfileSchema.VERSION and ProfileSchema.VERSION >= 5, "version 5 or later")
	check(type(p.settings) == "table", "settings added")
	check(#p.mutes == 2 and p.mutes[1] == 3 and p.mutes[2] == 9, "only real user ids are kept")
	local view = ProfileSchema.clientView(p)
	check(view.settings ~= nil and view.mutes ~= nil, "the client sees settings and mutes")
end)

test("M10: colorblind markers: every marker kind has its own shape", function()
	local src = require("@lune/fs").readFile("src/client/Ui/Radar.luau")
	for _, shape in { '"circle"', '"diamond"', '"triangle"', '"square"', '"star"' } do
		check(string.find(src, shape, 1, true) ~= nil, "the radar uses " .. shape)
	end
end)

---------------------------------------------------------------------------
-- M11: juice, audio and wait fillers
---------------------------------------------------------------------------

local function clientSources(): { [string]: string }
	local fs = require("@lune/fs")
	local out = {}
	local function walk(dir: string)
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path)
			elseif string.sub(name, -5) == ".luau" then
				out[path] = fs.readFile(path)
			end
		end
	end
	walk("src/client")
	return out
end

test("M11: the juice table has all 31 actions, each with a sound and a visual, and each is fired", function()
	local Au = Config.Audio
	check(#Au.juice == 31, "31 juice actions (spec juice table)")
	local src = clientSources()
	local seen = {}
	for _, row in Au.juice do
		check(not seen[row.id], "unique juice id " .. row.id)
		seen[row.id] = true
		local snd = Au.sounds[row.id]
		check(snd ~= nil and (snd.asset > 0 or snd.fallback ~= nil), "a sound for " .. row.id)
		local fired = false
		for _, text in src do
			local direct = string.find(text, 'Juice%.fire%(%s*"' .. row.id .. '"')
				or string.find(text, 'Juice%.hold%(%s*"' .. row.id .. '"')
			-- casts pick their sound by slot: castSound returns "basic", "super" or "cast"
			local bySlot = string.find(text, "Juice.fire(castSound(", 1, true)
				and (
					string.find(text, 'then "' .. row.id .. '"', 1, true)
					or string.find(text, 'else "' .. row.id .. '"', 1, true)
				)
			if direct or bySlot then
				fired = true
				break
			end
		end
		check(fired, "the client fires " .. row.id)
		local found = false
		for path, _ in src do
			if string.find(path, "/" .. row.visual .. ".luau", 1, true) then
				found = true
			end
		end
		check(found, row.id .. " draws in " .. row.visual)
	end
	local jfx = src["src/client/Fx/JuiceFx.luau"]
	for _, row in Au.juice do
		if row.visual == "JuiceFx" then
			check(
				string.find(jfx, "function JuiceFx." .. row.id .. "(", 1, true) ~= nil,
				"JuiceFx." .. row.id
			)
		end
	end
	check(Au.sounds.ui ~= nil, "buttons click")
end)

test("M11: music: three loops, ducked 40% for the siren and voices; 6 voice lines per pack", function()
	local Mu = Config.Audio.music
	check(Mu.patrolDay and Mu.patrolNight and Mu.boss and Mu.victory, "patrol day and night, boss, victory")
	check(Mu.victory.sting == true, "victory is a sting")
	check(math.abs(Mu.duck - 0.6) < 1e-9, "ducks 40%")
	check(Config.Audio.sounds.bossWarning.duck == true, "the boss siren ducks the music")
	check(#Config.Audio.voice.lines == 6, "6 lines")
	for pack, ids in Config.Shop.voiceSounds do
		check(#ids == 6, "6 clips in " .. pack)
	end
	for _, tab in Config.Creator.tabs do
		if tab.id == "voice" then
			for _, piece in tab.pieces do
				check(Config.Shop.voiceSounds[piece[2]] ~= nil, "voice pack " .. piece[2] .. " has clip ids")
			end
		end
	end
end)

test("M11: collision freeze: two heroes' heavy hits together, once per pair per 5 s", function()
	local ClashRules = require("../src/shared/ClashRules")
	local cfg = Config.Combat.clash
	check(cfg.freeze == 0.3 and cfg.radius == 14 and cfg.window == 0.15, "spec numbers")
	check(math.abs(cfg.push - 0.08) < 1e-9 and cfg.pairCooldown == 5, "camera push 8%, 5 s per pair")
	local book = ClashRules.book()
	check(ClashRules.note(cfg, book, { hero = 1, x = 0, y = 0, z = 0, t = 0 }) == nil, "the first hit waits")
	check(
		ClashRules.note(cfg, book, { hero = 1, x = 1, y = 0, z = 0, t = 0.05 }) == nil,
		"the same hero never clashes"
	)
	local other = ClashRules.note(cfg, book, { hero = 2, x = 5, y = 0, z = 0, t = 0.1 })
	check(other ~= nil and other.hero == 1, "two heroes within 0.15 s clash")
	ClashRules.note(cfg, book, { hero = 1, x = 0, y = 0, z = 0, t = 1 })
	check(
		ClashRules.note(cfg, book, { hero = 2, x = 0, y = 0, z = 0, t = 1.05 }) == nil,
		"the same pair waits 5 s"
	)
	ClashRules.note(cfg, book, { hero = 1, x = 0, y = 0, z = 0, t = 6 })
	check(ClashRules.note(cfg, book, { hero = 2, x = 0, y = 0, z = 0, t = 6.1 }) ~= nil, "again after 5 s")
	ClashRules.note(cfg, book, { hero = 3, x = 0, y = 0, z = 0, t = 20 })
	check(ClashRules.note(cfg, book, { hero = 4, x = 0, y = 0, z = 0, t = 20.3 }) == nil, "too late (0.3 s)")
	ClashRules.note(cfg, book, { hero = 5, x = 0, y = 0, z = 0, t = 30 })
	check(ClashRules.note(cfg, book, { hero = 6, x = 80, y = 0, z = 0, t = 30.05 }) == nil, "too far apart")
end)

test("M11: wait fillers: friend boost, offline drones cap, respawn, incident refill", function()
	local b = Config.Economy.bonus
	check(
		math.abs(b.friendEach - 0.1) < 1e-9 and math.abs(b.friendMax - 0.3) < 1e-9,
		"+10% per friend, max +30%"
	)
	check(Config.Incidents.spawner.refill[2] <= 10, "a new incident within 10 s")
	check(Config.Incidents.spawner.radius == 300, "within 300 studs")
	check(Config.Pvp.spawnProtect == 5, "the 5 s shield ring after a respawn")
	local HqRules = require("../src/shared/HqRules")
	local eight = HqRules.drones(Config, 6, 8 * 3600)
	check(HqRules.drones(Config, 6, 20 * 3600) == eight, "drones stop at 8 hours")
	check(HqRules.drones(Config, 4, 3600) == 0, "drones start at HQ level 5")
end)

---------------------------------------------------------------------------
-- M12: analytics (events, funnels, the onboarding save)
---------------------------------------------------------------------------

local AnalyticsSchema = require("../src/shared/AnalyticsSchema")

local function serverSources(): { [string]: string }
	local fs = require("@lune/fs")
	local out = {}
	for _, name in fs.readDir("src/server/Services") do
		out[name] = fs.readFile("src/server/Services/" .. name)
	end
	return out
end

-- Is this funnel step stepped by the server? A literal step(…, "Funnel", "step") call, or a file that names
-- the funnel and has the step as a quoted name (a table or an if-expression picks it)
local function stepped(src: { [string]: string }, funnel: string, step: string): boolean
	for _, text in src do
		if string.find(text, '"' .. funnel .. '", "' .. step .. '"', 1, true) then
			return true
		end
		if
			string.find(text, "Analytics.step(", 1, true)
			and string.find(text, '"' .. funnel .. '"', 1, true)
			and string.find(text, '"' .. step .. '"', 1, true)
		then
			return true
		end
	end
	return false
end

test("M12: every spec event and funnel step is in the schema, and each one is logged somewhere", function()
	local spec = {
		"session_start",
		"first_leap",
		"first_catch",
		"first_blast",
		"choice_made",
		"choice_pick",
		"creator_done",
		"incident_done",
		"contract_done",
		"skill_cast",
		"skill_rank",
		"level_up",
		"gear_drop",
		"gear_upgrade",
		"boss_join",
		"boss_done",
		"flag_on",
		"flag_off",
		"pvp_hit",
		"pvp_win",
		"defeat",
		"downed",
		"fast_travel",
		"mission_start",
		"mission_done",
		"report_player",
		"anti_exploit_flag",
		"purchase",
		"perf_sample",
		"session_end", -- the studio-wide FunnelKit's session_end replaced the spec's "leave"
	}
	local E = AnalyticsSchema.EVENTS
	for _, name in spec do
		check(E[name] ~= nil, "schema has " .. name)
	end
	local src = serverSources()
	local all = table.concat(
		(function()
			local t = {}
			for _, s in src do
				table.insert(t, s)
			end
			return t
		end)(),
		"\n"
	)
	for name, fields in E do
		check(#fields <= 3, name .. " has at most 3 custom fields (Roblox's limit)")
		check(string.match(name, "^[a-z0-9_]+$") ~= nil, name .. " is lowercase")
		local logged = string.find(all, '"' .. name .. '"', 1, true) ~= nil
		check(logged, "the server logs " .. name)
	end
	local F = AnalyticsSchema.FUNNELS
	check(
		#F.Opening == 12 and F.Opening[1] == "session_start" and F.Opening[12] == "d1_return",
		"Opening: 12 steps"
	)
	for _, f in { "Combat", "PvP", "Story", "Purchase" } do
		check(F[f] ~= nil and #F[f] >= 4, f .. " funnel")
		for i, step in F[f] do
			check(AnalyticsSchema.stepOf(f, step) == i, f .. " step " .. step)
			-- every step is reached: a server call, or a device note (shop_open, shop_view_item)
			local reached = stepped(src, f, step)
			check(reached, f .. "." .. step .. " is stepped")
		end
	end
	for _, step in F.Opening do
		local reached = stepped(src, "Opening", step)
		check(reached, "Opening." .. step .. " is stepped")
	end
	check(AnalyticsSchema.stepOf("Opening", "nope") == nil, "unknown step is nil")
end)

test("M12: events are checked: unknown names refused, fields cut to short safe codes", function()
	local ok, f = AnalyticsSchema.check("level_up", { 12, 30 })
	check(ok and f[1] == "12" and f[2] == "30", "numbers become text")
	check(not (AnalyticsSchema.check("made_up", {})), "unknown event refused")
	check(not (AnalyticsSchema.check("level_up", { 1, 2, 3 })), "more fields than the event has refused")
	local _, g = AnalyticsSchema.check("choice_pick", { "a b<script>", string.rep("x", 50) })
	check(g[1] == "abscript", "spaces and symbols removed")
	check(#g[2] == 32, "cut to 32 characters")
	ok = AnalyticsSchema.check("first_leap", nil)
	check(ok, "no fields is fine")
	local A = Config.Analytics
	check(A.castSample > 0 and A.castSample <= 0.2, "skill casts are sampled at 20% or less (spec)")
	check(
		A.budget.base > 0 and A.budget.lowShare < 1,
		"a per-minute budget with busy events giving way first"
	)
	for name in A.lowPriority do
		check(AnalyticsSchema.EVENTS[name] ~= nil, "low-priority event exists: " .. name)
	end
	check(A.perfSample == 0.1 and A.perfEvery == 60, "perf: 10% of devices, every 60 s (spec)")
	local r = Remotes.Telemetry
	check(r ~= nil and r.dir == "C2S" and r.rate ~= nil, "Telemetry remote is rate limited")
end)

test("M12: save v6 keeps the onboarding step and first-seen day; repair clamps them", function()
	check(ProfileSchema.VERSION >= 6, "version 6 or later")
	local p = ProfileSchema.default()
	check(p.analytics.onboard == 0 and p.analytics.firstSeen == 0 and p.analytics.d1 == 0, "fresh analytics")
	local bad = ProfileSchema.default()
	bad.analytics = { onboard = 99, firstSeen = -5, d1 = 7 }
	local fixed = ProfileSchema.load(bad)
	check(
		fixed.analytics.onboard <= 32 and fixed.analytics.firstSeen >= 0 and fixed.analytics.d1 <= 1,
		"clamped"
	)
	local old = ProfileSchema.default()
	old.analytics = nil
	old.version = 5
	local m = ProfileSchema.load(old)
	check(m.version == ProfileSchema.VERSION and m.analytics.onboard == 0, "a v5 save gains analytics")
end)

---------------------------------------------------------------------------
-- Red Faction-style destruction (nate 2026-11-16): Structure pieces, supports and holes
---------------------------------------------------------------------------

local Structure = require("../src/shared/Structure")

test("RF: every building is pillars, wall panels and slabs inside its box, at most 256 pieces", function()
	for _, b in world.buildings do
		local g = Structure.build(DS, b)
		check(#g.pieces >= 13 and #g.pieces <= 256, "piece count for " .. b.id .. ": " .. #g.pieces)
		local kinds = {}
		for _, p in g.pieces do
			kinds[p.kind] = (kinds[p.kind] or 0) + 1
			check(
				math.abs(p.cx - b.x) <= b.sx / 2 - p.sx / 2 + 1e-6
					and math.abs(p.cz - b.z) <= b.sz / 2 - p.sz / 2 + 1e-6,
				"inside the footprint"
			)
			check(p.cy - p.sy / 2 >= b.base - 1e-6 and p.cy + p.sy / 2 <= b.top + 1e-6, "inside the height")
		end
		check(kinds.pillar == 4 * g.storeys, "4 pillars a storey")
		check((kinds.wall or 0) >= 4 * g.storeys and (kinds.slab or 0) >= g.storeys, "walls and slabs")
		for st = 1, g.storeys do
			check(Structure.stands(DS, g, {}, st), "an intact storey stands")
		end
		local again = Structure.build(DS, b)
		check(
			#again.pieces == #g.pieces and again.pieces[5].cx == g.pieces[5].cx,
			"every device builds the same"
		)
	end
end)

test("RF: a hit knocks out the nearest pieces for its damage; holes are real (nothing else moves)", function()
	local b = world.buildings[1]
	local g = Structure.build(DS, b)
	local gone = {}
	local hit = Structure.blast(DS, g, gone, b.x, b.base + 4, b.z - b.sz / 2 - 1, 12, DS.superStruct)
	check(#hit >= 2 and #hit <= DS.structure.maxPerHit, "a super knocks out a few pieces (" .. #hit .. ")")
	for _, i in hit do
		check(g.pieces[i].storey <= 2, "near where it landed")
	end
	local small = Structure.blast(DS, g, {}, b.x, b.base + 4, b.z - b.sz / 2 - 1, 12, 100)
	check(#small == 1, "a small hit still knocks out one piece")
	local none = Structure.blast(DS, g, {}, b.x + 500, b.base, b.z, 12, 99999)
	check(#none == 0, "a hit far away does nothing")
	local fell, failed = Structure.settle(DS, g, gone)
	check(failed == nil, "one hole does not bring the building down")
	check(#fell == 0 or #fell < #hit * 3, "a few loose bits at most")
end)

test(
	"RF: knock out a storey's supports and it and everything above fall; the ground storey is a collapse",
	function()
		-- a tall building
		local b
		for _, x in world.buildings do
			if not b or x.top - x.base > b.top - b.base then
				b = x
			end
		end
		local g = Structure.build(DS, b)
		check(g.storeys >= 3, "a tall building has several storeys")
		local mid = math.ceil(g.storeys / 2)
		local gone = {}
		for _, i in g.bearing[mid] do
			gone[i] = true
			if not Structure.stands(DS, g, gone, mid) then
				break
			end
		end
		local fell, failed = Structure.settle(DS, g, gone)
		check(failed == mid, "storey " .. mid .. " gave way")
		local below, above = 0, 0
		for i, p in g.pieces do
			if p.storey >= mid then
				check(gone[i] == true, "everything from that storey up is gone")
				above += 1
			elseif not gone[i] then
				below += 1
			end
		end
		check(#fell > 0 and below > 0, "the floors below still stand")
		check(Structure.standingTop(g, gone) <= b.base + (mid - 1) * g.storeyH + 1e-6, "the height drops")
		local gone2 = {}
		for _, i in g.bearing[1] do
			gone2[i] = true
		end
		local _, f2 = Structure.settle(DS, g, gone2)
		check(f2 == 1, "the ground storey failing is a full collapse")
		local gone3 = {}
		for _, i in g.bearing[1] do
			gone3[i] = true
		end
		local _, f3 = Structure.settle(DS, g, gone3, true)
		check(f3 ~= 1, "the collapse cap holds the ground storey up")
		-- a panel left hanging with nothing under or beside it drops
		local gone4 = {}
		local key = function(...)
			return table.concat({ ... }, ":")
		end
		local w = g.at[key("w", 1, 1, 2)]
		for _, k in { key("w", 1, 1, 1), key("p", 1, 2), key("w", 1, 2, 2) } do
			if g.at[k] then
				gone4[g.at[k]] = true
			end
		end
		if g.panels[1] == 1 then
			gone4[g.at[key("p", 2, 2)]] = true
		end
		local fell4 = Structure.settle(DS, g, gone4)
		check(table.find(fell4, w) ~= nil, "a hanging panel falls")
		local bits = Structure.pack(#g.pieces, gone)
		local back = Structure.unpack(bits, #g.pieces)
		local same = true
		for i = 1, #g.pieces do
			if (back[i] == true) ~= (gone[i] == true) then
				same = false
			end
		end
		check(same and buffer.len(bits) <= 32, "one bit a piece, 32 bytes at most")
	end
)

test(
	"RF: BuildingState: blasts set Damaged, list the pieces for devices, collapse at the ground; repair heals",
	function()
		local list = {}
		for i = 1, 4 do
			local b = table.clone(world.buildings[i])
			b.district = "A"
			table.insert(list, b)
		end
		local book = BuildingState.new(DS, list)
		local b = list[1]
		local r =
			BuildingState.blast(DS, book, b.id, b.x, b.base + 4, b.z - b.sz / 2 - 1, 12, DS.superStruct, 0)
		check(r.state == BuildingState.DAMAGED and r.changed and #r.hit > 0, "the first hit makes it Damaged")
		check(book.hp[b.id] < book.maxHp[b.id], "structure HP follows the weight lost")
		local removed = BuildingState.takeRemoved(book)
		check(#removed == (#r.hit + #r.fell) * 3, "every removed piece is listed for the devices")
		check(#BuildingState.takeRemoved(book) == 0, "listed once")
		local snap = BuildingState.packGone(DS, book)
		check(
			#snap == 1 and snap[1][1] == b.id and type(snap[1][2]) == "buffer",
			"the snapshot carries its holes"
		)
		-- blast around the ground floor until it gives
		local k = 0
		repeat
			k += 1
			local a = k * 2.4
			r = BuildingState.blast(
				DS,
				book,
				b.id,
				b.x + math.cos(a) * (b.sx / 2 + 1),
				b.base + 4,
				b.z + math.sin(a) * (b.sz / 2 + 1),
				14,
				DS.superStruct,
				k
			)
		until r.state == BuildingState.COLLAPSED or k > 40
		check(
			r.state == BuildingState.COLLAPSED and k <= 12,
			"supers around the base bring it down (" .. k .. ")"
		)
		check(#BuildingState.packGone(DS, book) == 0, "a collapsed building needs no holes in the snapshot")
		BuildingState.repair(book, b.id)
		check(book.state[b.id] == 0 and book.gone[b.id] == nil, "repair puts every piece back")
		local p = list[2]
		local pr = BuildingState.punch(DS, book, p.id, p.x, p.base + 3, p.z - p.sz / 2, 100)
		check(
			pr.state == BuildingState.DAMAGED and #pr.hit >= 1 and #pr.hit <= DS.structure.clashPanels,
			"a robot thrown through breaks a panel or two"
		)
	end
)

---------------------------------------------------------------------------
-- Place layout (only when a built place is passed)
---------------------------------------------------------------------------

local placePath = process.args[1]
if placePath then
	test("place: the Rojo build has every service in the right spot", function()
		local fs = require("@lune/fs")
		local roblox = require("@lune/roblox")
		local game = roblox.deserializePlace(fs.readFile(placePath))
		local rs = game:GetService("ReplicatedStorage")
		check(rs:FindFirstChild("Config") ~= nil, "ReplicatedStorage.Config")
		-- the Blender robot meshes (art/models/Robots.rbxm), uploaded and mapped in by Rojo
		local art = rs:FindFirstChild("Art")
		local robots = art and art:FindFirstChild("Robots")
		check(robots ~= nil, "ReplicatedStorage.Art.Robots")
		if robots then
			local Fit = Config.ArtFit
			for name in Fit.fit do
				local m = robots:FindFirstChild(name, true)
				check(m ~= nil and m:IsA("MeshPart"), "Art mesh " .. name)
				check(
					m ~= nil and string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil,
					"Art mesh " .. name .. " is uploaded"
				)
			end
		end
		local shared = rs:FindFirstChild("Shared")
		for _, name in
			{
				"Net",
				"NetSchema",
				"Remotes",
				"Rng",
				"Formulas",
				"MoveMath",
				"MoveCheck",
				"PosHistory",
				"HitQuery",
				"Cooldowns",
				"EnemySim",
				"EnemyBuffer",
				"CityLayout",
				"Status",
				"AbilityRules",
				"CastPlan",
				"Awakening",
				"GearMath",
				"LootTable",
				"Progress",
				"ProfileSchema",
				"Inventory",
				"BoxKit",
				"Districts",
				"WorldGen",
				"HeightMap",
				"WorldMap",
				"Travel",
				"Chunker",
				"BuildingState",
				"Vehicles",
				"VehiclePose",
				"CitizenSim",
				"CitizenBuffer",
				"ZoneLevel",
				"WorldClock",
				"IncidentPlan",
				"ContractPlan",
				"EventPlan",
				"BossMath",
				"BossSim",
				"IncidentSpots",
				"StoryPlan",
				"PocketLayout",
				"OpeningPlan",
				"PvpRules",
				"GuardRules",
				"LookCodec",
				"CreatorRules",
				"ShopRules",
				"HqRules",
				"EconomySim",
				"LookKit",
				"SettingsRules",
				"SquadRules",
				"ClashRules",
			}
		do
			check(shared ~= nil and shared:FindFirstChild(name) ~= nil, "Shared." .. name)
		end
		local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
		check(server ~= nil and server.ClassName == "Script", "Server script")
		for _, name in
			{
				"HeroService",
				"MoveGuard",
				"CombatService",
				"EnemyService",
				"CityBuilder",
				"LoadBots",
				"DevService",
				"PerfMonitor",
				"AbilityService",
				"DataService",
				"EconomyService",
				"GearService",
				"LookService",
				"PerkService",
				"SafehouseService",
				"BeaconService",
				"BuildingService",
				"VehicleService",
				"CitizenService",
				"SiteKit",
				"IncidentService",
				"ContractService",
				"EventService",
				"BossService",
				"ClockService",
				"StoryService",
				"OpeningService",
				"MissionService",
				"QuestService",
				"FlagService",
				"FameService",
				"GuardService",
				"DeathService",
				"CreatorService",
				"HqService",
				"ShopService",
				"PurchaseService",
				"SettingsService",
				"SquadService",
				"Analytics",
				"AnalyticsHooks",
			}
		do
			local folder = server and server:FindFirstChild("Services")
			check(folder ~= nil and folder:FindFirstChild(name) ~= nil, "Services." .. name)
		end
		local client =
			game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
		check(client ~= nil and client.ClassName == "LocalScript", "Client local script")
		for _, path in
			{
				{ "Controllers", "InputController" },
				{ "Controllers", "MoveController" },
				{ "Controllers", "CameraController" },
				{ "Controllers", "CombatClient" },
				{ "Controllers", "EnemyRenderer" },
				{ "Controllers", "QualityController" },
				{ "Fx", "CombatFx" },
				{ "Fx", "MoveFx" },
				{ "Fx", "AuraFx" },
				{ "Ui", "LoadoutScreen" },
				{ "Ui", "GearScreen" },
				{ "Ui", "Toasts" },
				{ "Controllers", "GadgetClient" },
				{ "Ui", "Kit" },
				{ "Ui", "Hud" },
				{ "Ui", "DevPanel" },
				{ "Ui", "MapScreen" },
				{ "Controllers", "TravelClient" },
				{ "Controllers", "CitizenRenderer" },
				{ "Fx", "BuildingFx" },
				{ "Fx", "VehicleFx" },
				{ "Fx", "DebrisBudget" },
				{ "Controllers", "WorldClient" },
				{ "Fx", "WorldFx" },
				{ "Ui", "WorldHud" },
				{ "Ui", "ContractBoard" },
				{ "Controllers", "StoryClient" },
				{ "Fx", "StoryFx" },
				{ "Ui", "StoryHud" },
				{ "Ui", "Journal" },
				{ "Controllers", "PvpClient" },
				{ "Fx", "PvpFx" },
				{ "Ui", "PvpHud" },
				{ "Ui", "Plates" },
				{ "Ui", "Preview" },
				{ "Ui", "CreatorScreen" },
				{ "Ui", "ShopHud" },
				{ "Ui", "HqHud" },
				{ "Controllers", "HqClient" },
				{ "Fx", "EmoteFx" },
				{ "Controllers", "SettingsClient" },
				{ "Controllers", "SquadClient" },
				{ "Ui", "SettingsMenu" },
				{ "Ui", "SquadHud" },
				{ "Ui", "Radar" },
				{ "Ui", "Shapes" },
				{ "Ui", "MainMenu" },
				{ "Controllers", "AudioController" },
				{ "Controllers", "IdleWatch" },
				{ "Fx", "Juice" },
				{ "Fx", "JuiceFx" },
				{ "Ui", "PhotoMode" },
				{ "Controllers", "Telemetry" },
				{ "Controllers", "GroundGuard" },
			}
		do
			local folder = client and client:FindFirstChild(path[1])
			check(folder ~= nil and folder:FindFirstChild(path[2]) ~= nil, path[1] .. "." .. path[2])
		end
		local first = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingScreen")
		check(first ~= nil and first.ClassName == "LocalScript", "ReplicatedFirst.LoadingScreen")
		check(
			game:GetService("Players").CharacterAutoLoads == false,
			"characters wait for the city (CharacterAutoLoads off until the hub is built)"
		)
		check(game:GetService("Workspace").StreamingEnabled == true, "StreamingEnabled on")
		check(
			game:GetService("Workspace").StreamOutBehavior == roblox.Enum.StreamOutBehavior.Opportunistic,
			"parts stream out when far away (Opportunistic)"
		)
	end)
end

test("Mobility: five picks; caps cover every move; sprint, super leap and swing maths", function()
	check(#M.mobilityOrder == 5, "five mobilities")
	for _, id in M.mobilityOrder do
		local m = M.mobility[id]
		check(
			m ~= nil and m.name ~= nil and m.text ~= nil and m.swim ~= nil and m.up ~= nil,
			id .. " is complete"
		)
		local cap = MoveMath.speedCap(M, { [id] = true }, true)
		check(cap >= m.swim, id .. ": the cap covers swimming")
	end
	local sp = M.mobility.speed
	check(MoveMath.speedCap(M, { speed = true }, false) >= sp.sprint, "Super-speed cap covers the sprint")
	local s, t = M.run.speed, 0
	while s < sp.sprint and t < 5 do
		s = MoveMath.sprintStep(M, s, true, 1 / 60)
		t += 1 / 60
	end
	check(s == sp.sprint and t > 0.8 and t < 1.6, string.format("full sprint in %.2f s", t))
	check(MoveMath.sprintStep(M, 100, false, 10) == M.run.speed, "letting go drops back to a run")
	check(sp.waterRun < sp.sprint and sp.wallRun <= sp.cap, "water and wall runs are inside the sprint")
	-- Leaping: the super leap clears a 6-storey building and the pound is inside the cap
	local lp = M.mobility.leap
	local vx, vy, vz = MoveMath.superLeapLaunch(M, 1, 0, 1)
	near(vy * vy / (2 * M.airGravity), lp.apex, 0.5, "super leap apex")
	check(vx > 0 and vz == 0, "forward along the aim")
	local leapCap = MoveMath.speedCap(M, { leap = true }, false)
	check(
		leapCap >= MoveMath.superLeapSpeed(M) and leapCap >= lp.pound.speed,
		"leap cap covers the leap and pound"
	)
	check(lp.pound.speed <= M.fall.terminal, "the pound is no faster than the legal fall")
	-- Acrobat: jumps, wall runs and the glide stay under the cap
	local ac = M.mobility.acrobat
	local acCap = MoveMath.speedCap(M, { acrobat = true }, false)
	check(
		math.sqrt(ac.jump ^ 2 + (ac.jumpForward + ac.glideForward * 0.5) ^ 2) <= acCap * M.tolerance,
		"a double jump at glide speed is legal"
	)
	check(
		ac.wallRun <= acCap and ac.glideForward <= acCap and ac.climb <= acCap,
		"wall run, glide and climb are legal"
	)
	-- Swing: the rope keeps its length, the speed caps, and zips are legal
	local sw = M.mobility.swing
	local px, py, pz, qx, qy, qz = 0, 0, 30, 0, 0, 0
	for _ = 1, 600 do
		px, py, pz, qx, qy, qz = MoveMath.swingStep(M, px, py, pz, qx, qy, qz, 0, 40, 0, 50, 0, 1, 1 / 60)
	end
	local d = math.sqrt(px * px + (py - 40) ^ 2 + pz * pz)
	check(d <= 50.01, string.format("the rope holds (%.2f of 50)", d))
	check(math.sqrt(qx * qx + qy * qy + qz * qz) <= sw.maxSpeed + 1e-6, "swing speed caps")
	local swCap = MoveMath.speedCap(M, { swing = true }, false)
	check(swCap >= sw.maxSpeed and swCap >= sw.zip, "swing cap covers swings and zips")
	-- Flight's level 10 boost stays inside the flight cap
	check(M.mobility.flight.up.boost <= M.caps.flight, "faster boost is still legal")
	-- every ride speed in the travel powers is a server-allowed ride buff (MoveGuard reads it)
	for _, id in AB.order do
		local a = AB.list[id]
		if a.shape == "ride" then
			check(
				a.speed ~= nil
					and a.duration ~= nil
					and (a.ride == "air" or a.ride == "surf" or a.ride == "rail"),
				id .. " ride kind and speed"
			)
			local fast = AbilityRules.effective(Config, id, 5, 2)
			check(fast.speed <= 140, id .. " ride stays under 140 even with Fast mods")
		end
	end
end)

test("Underwater: areas, floors, water checks and the world cut around them", function()
	local D = Config.Deep
	local wy = Config.World.coast.waterY
	local b = Config.City.docks.basin
	local L = D.sunkenLine
	local half = Config.City.mapSize / 2
	local function at(x, y, z)
		return DeepLayout.area(Config, x, z, y),
			DeepLayout.floorAt(Config, x, z, y),
			DeepLayout.underwater(Config, x, y, z)
	end
	local a, f, u = at((b.minX + b.maxX) / 2, -10, (b.minZ + b.maxZ) / 2)
	check(a == "basin" and f == D.basin.floor and u, "the harbour basin is water down to its floor")
	a, f, u = at(300, L.floor + 4, L.z)
	check(a == "line" and f == L.floor and u, "the Sunken Line tunnel")
	a, f = at((L.station.minX + L.station.maxX) / 2, L.floor + 8, L.z - L.station.width / 2 + 5)
	check(a == "line" and f == L.floor + L.station.platform, "the station platform")
	a, _, u = at(300, 5, L.z)
	check(a == nil and not u, "the street over the tunnel is land")
	a, f, u = at(0, -20, half + 300)
	check(a == "shelf" and f and f < -20 and u, "the Coral Shelf off the south beach")
	a, f, u = at(0, -100, 3300)
	check(a == "trench" and f == D.trench.floor and u, "the Trench")
	a, _, u = at(half + 100, -5, 0)
	check(a == "sea" and u, "the rest of the ring is open sea")
	check(not DeepLayout.underwater(Config, 0, -5, 0), "under the hub is not water")
	check(not DeepLayout.underwater(Config, 0, wy + 1, half + 300), "above the surface is not underwater")
	check(DeepLayout.floorAt(Config, half + 10, half + 0) ~= nil, "floor near the beach")
	local shore = DeepLayout.floorAt(Config, 0, half + 10) :: number
	local outer = DeepLayout.floorAt(Config, 0, half + D.ring.width - 10) :: number
	check(shore > outer and wy - shore >= D.ring.shore - 0.01, "the ring gets deeper away from the beach")

	local lay = DeepLayout.build(Config)
	local again = DeepLayout.build(Config)
	check(
		#lay.boxes == #again.boxes and lay.boxes[40].cx == again.boxes[40].cx,
		"the layout is the same every build"
	)
	check(#lay.caches == D.caches.count, "every cache placed")
	check(#lay.rescues == #L.cars + 1, "a commuter in every car and on the platform")
	for _, c in lay.caches do
		check(DeepLayout.underwater(Config, c.x, c.y, c.z), "cache " .. c.id .. " is underwater")
	end
	for _, r in lay.rescues do
		check(DeepLayout.underwater(Config, r.x, r.y, r.z), "commuter " .. r.id .. " is underwater")
	end
	local water = 0
	for _, t in lay.terrain do
		check(t.sx > 0 and t.sy > 0 and t.sz > 0, "terrain fills have size")
		if t.material == "water" then
			water += 1
		end
		for _, c in DeepLayout.chunks(t, D.fillChunk) do
			check(
				c.sx <= D.fillChunk + 0.01 and c.sy <= D.fillChunk + 0.01 and c.sz <= D.fillChunk + 0.01,
				"chunk size"
			)
		end
	end
	check(water >= 4 * D.ring.bands + 3, "water in the ring, the basin, the line and the trench")
	check(#lay.boxes < 1500, "the underwater parts stay in budget (" .. #lay.boxes .. ")")
	for _, bx in lay.boxes do
		check(Config.City.palette[bx.color] ~= nil, "palette has " .. bx.color)
	end
	-- the ground and the quay leave the basin open; no sea parts over the ring or the trench
	local world = WorldMap.build(Config, 202647)
	local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
	local function covers(bx, x, z)
		return math.abs(x - bx.cx) < bx.sx / 2 and math.abs(z - bx.cz) < bx.sz / 2
	end
	for _, bx in world.baseBoxes do
		check(
			not ((bx.kind == "ground" or bx.kind == "sea") and covers(bx, cx, cz)),
			"nothing over the basin"
		)
		check(not (bx.kind == "sea" and covers(bx, 0, half + 300)), "no sea part over the shelf")
		check(not (bx.kind == "sea" and covers(bx, 0, 3300)), "no sea part over the trench")
		check(bx.sx <= 2048 and bx.sz <= 2048, "base parts fit Roblox's size limit")
	end
	for _, bx in world.hubBoxes do
		check(
			not ((bx.kind == "plaza" or bx.kind == "water") and covers(bx, cx, cz)),
			"the quay is cut around the basin"
		)
	end
	check(
		#BoxKit.around(0, 0, 10, 10, { x0 = 3, z0 = 3, x1 = 6, z1 = 6 }) == 4,
		"a hole in the middle: 4 pieces"
	)
	check(#BoxKit.around(0, 0, 10, 10, { x0 = 20, z0 = 20, x1 = 30, z1 = 30 }) == 1, "no overlap: whole")
	check(DeepLayout.zoneLevel(Config, 0, -100, 3300, 1) == D.zoneFloor.trench, "the trench has a zone floor")
end)

test("Underwater: sea robots stay in the water, land robots stay out, torpedoes turn", function()
	local wy = Config.World.coast.waterY
	local half = Config.City.mapSize / 2
	local seed = 99
	local sim = EnemySim.new(Config, {
		heightAt = function(x, z, y)
			if y and y < wy - 0.5 then
				local f = DeepLayout.floorAt(Config, x, z, y)
				if f then
					return f
				end
			end
			return if DeepLayout.area(Config, x, z) then wy else 0
		end,
		water = function(x, y, z)
			return DeepLayout.underwater(Config, x, y, z)
		end,
		random = function()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end,
	})
	for _, kind in { "Diver", "Anchor", "TorpedoSentry" } do
		local cfg = Config.Enemies[kind]
		check(
			cfg.sea == true and cfg.body ~= nil and (Config.Enemies.mix[kind] or 0) == 0,
			kind .. " is a sea robot"
		)
		check((Config.Deep.mix[kind] or 0) > 0, kind .. " spawns underwater")
	end
	-- a swimming hero meets only sea robots
	local swimmer = { id = 1, x = 0, y = -20, z = half + 300, alive = true }
	for t = 1, 60 do
		EnemySim.populate(sim, { swimmer }, t)
		EnemySim.step(sim, t, { swimmer })
	end
	local n = 0
	for _, e in sim.enemies do
		n += 1
		check(e.cfg.sea == true, "only sea robots near a swimmer (" .. e.kind .. ")")
		check(DeepLayout.underwater(Config, e.x, e.y, e.z), e.kind .. " is in the water")
		check(e.y <= wy - 3 + 0.01, e.kind .. " stays under the surface")
	end
	check(n >= 3, "sea robots spawned (" .. n .. ")")
	for t = 61, 120, 0.1 do
		EnemySim.step(sim, t, { swimmer })
	end
	for _, e in sim.enemies do
		check(DeepLayout.underwater(Config, e.x, e.y, e.z), e.kind .. " still in the water after chasing")
	end
	-- a land brute at the beach never walks into the sea after a hero who swims off
	local land = EnemySim.new(Config, {
		heightAt = function(x, z, y)
			if y and y < wy - 0.5 then
				local f = DeepLayout.floorAt(Config, x, z, y)
				if f then
					return f
				end
			end
			return if DeepLayout.area(Config, x, z) then wy else 0
		end,
		water = function(x, y, z)
			return DeepLayout.underwater(Config, x, y, z)
		end,
	})
	local brute = EnemySim.spawn(land, "BruteBot", 0, 4, half - 10, 1) :: any
	local bait = { id = 2, x = 0, y = -12, z = half + 40, alive = true }
	for t = 0, 20, 0.1 do
		EnemySim.step(land, t, { bait })
	end
	check(not DeepLayout.underwater(Config, brute.x, wy - 2, brute.z), "the land brute stays on the beach")
	-- torpedoes turn after their hero at the set rate
	local shot = { x = 0, y = 0, z = 0, vx = 40, vy = 0, vz = 0, home = 5, turn = math.rad(60) }
	local target = { id = 5, x = 0, y = -1.5, z = 100, alive = true }
	EnemySim.steer(shot, { target }, 0.5)
	local ang = math.deg(math.atan2(shot.vz, shot.vx))
	check(math.abs(ang - 30) < 0.5, "turned 30 degrees in half a second (" .. ang .. ")")
	check(math.abs(math.sqrt(shot.vx ^ 2 + shot.vz ^ 2) - 40) < 1e-6, "same speed")
	-- the wire carries the new type ids
	local e = {
		id = 7,
		x = 1,
		y = -20,
		z = 3,
		yaw = 0,
		health = 1,
		maxHealth = 1,
		state = 2,
		typeId = 9,
		flags = 0,
		alive = true,
	}
	local _, _, rows = EnemyBuffer.decode(EnemyBuffer.encodeFor(1, 0, { e }, 0, 0, 0, 100, 10))
	check(rows[1].typeId == 9 and rows[1].state == 2, "type id 9 and the state survive the packet")
end)

test("Underwater: Leviathan Engine boss, its drop and the save slot", function()
	local B = Config.Boss
	check(table.find(B.order, "LeviathanEngine") ~= nil, "in the world boss rotation")
	check(#B.order == ProfileSchema.BOSSES, "the save has a slot per boss")
	local cfg = B.bosses.LeviathanEngine
	local nums = {}
	for id, b in B.bosses do
		check(not nums[b.num], id .. " has its own number")
		nums[b.num] = true
	end
	local weak = 0
	for _, t in cfg.targets do
		if t.weak then
			weak += 1
		end
	end
	check(weak >= 2 and #cfg.objectives.list == 2, "weak points and two torpedo bays")
	for _, a in cfg.attacks do
		check(table.find({ "ring", "cone", "circles", "lines", "pull" }, a.shape) ~= nil, a.id .. " shape")
	end
	check(GearMath.bossStyle(Config, "LeviathanEngine", false) ~= nil, "it drops a style")
	check(GearMath.bossStyle(Config, "LeviathanEngine", true) ~= nil, "and a shiny one")
	local sim =
		BossSim.new(Config, "LeviathanEngine", 0, Config.World.coast.waterY, 3260, 100000, 20, 0, Rng.new(4))
	check(sim ~= nil, "the fight builds")
	local old = ProfileSchema.default()
	old.bosses = { 2, 1 }
	local p = ProfileSchema.load(old)
	check(p.bosses[1] == 2 and p.bosses[2] == 1 and p.bosses[3] == 0, "an older save gets the new slot")
	check(
		Config.Loot.sources.deepCache ~= nil and table.find(Config.Loot.order, "deepCache") ~= nil,
		"cache loot"
	)
	check(
		Config.Economy.earn.deepCache ~= nil and Config.Economy.earn.deepRescue ~= nil,
		"cache and rescue pay"
	)
end)

test("Destruction: basic hits add up to break a piece; repair clears them", function()
	local D = Config.Destruction
	local world = WorldMap.build(Config, 202647)
	local book = BuildingState.new(D, world.buildings)
	local b = world.buildings[1]
	local x, y, z = b.x + b.sx / 2, b.base + 4, b.z
	local hits = math.ceil(D.structure.chunkCost / D.slotStruct.basic)
	for k = 1, hits - 1 do
		local r = BuildingState.blast(D, book, b.id, x, y, z, 5, D.slotStruct.basic, k)
		check(#r.hit == 0, "basic hit " .. k .. " only chips")
	end
	local r = BuildingState.blast(D, book, b.id, x, y, z, 5, D.slotStruct.basic, hits)
	check(#r.hit == 1 and book.state[b.id] == 1, "hit " .. hits .. " knocks a piece out")
	check(
		#BuildingState.blast(D, book, b.id, x, y + 12, z, 12, D.slotStruct.skill, 20).hit >= 1,
		"a skill breaks a piece at once"
	)
	BuildingState.blast(D, book, b.id, x, y, z, 5, D.slotStruct.basic, 21)
	BuildingState.repair(book, b.id)
	check(book.chip[b.id] == nil and book.state[b.id] == 0, "repair clears the chips")
	check(D.slotStruct.skill >= D.structure.chunkCost, "a skill is worth a piece")
end)

test("Art: the hero body is a standard R15 rig whose joints meet", function()
	local rig = Config.HeroRig
	local names = { "Head", "UpperTorso", "LowerTorso" }
	for _, side in { "Left", "Right" } do
		for _, part in { "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" } do
			table.insert(names, side .. part)
		end
	end
	local count = 0
	for _ in rig.parts do
		count += 1
	end
	check(count == 15, "exactly the 15 R15 parts, got " .. count)
	-- every rig joint: the two parts that share it put it at the same point in the world
	local joints: { [string]: { { number } } } = {}
	local function addJoints(def)
		for name, at in def.attachments do
			if string.sub(name, -13) == "RigAttachment" then
				joints[name] = joints[name] or {}
				table.insert(
					joints[name],
					{ def.centre[1] + at[1], def.centre[2] + at[2], def.centre[3] + at[3] }
				)
			end
		end
	end
	addJoints(rig.root)
	for _, name in names do
		local def = rig.parts[name]
		check(def ~= nil, "part " .. name)
		if def then
			check(def.size[1] > 0.05 and def.size[2] > 0.05 and def.size[3] > 0.05, name .. " has a size")
			addJoints(def)
		end
	end
	local expected = {
		"Root",
		"Waist",
		"Neck",
		"LeftShoulder",
		"RightShoulder",
		"LeftElbow",
		"RightElbow",
		"LeftWrist",
		"RightWrist",
		"LeftHip",
		"RightHip",
		"LeftKnee",
		"RightKnee",
		"LeftAnkle",
		"RightAnkle",
	}
	for _, j in expected do
		local pts = joints[j .. "RigAttachment"]
		check(pts ~= nil and #pts == 2, j .. " joins exactly two parts")
		if pts and #pts == 2 then
			local a, b = pts[1], pts[2]
			local d = math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3])
			check(d < 0.01, j .. " meets in the world (off by " .. d .. ")")
		end
	end
	-- standing on the ground: the feet reach y = 0 and the root part sits hipHeight above it
	local lowest = math.huge
	for _, def in rig.parts do
		lowest = math.min(lowest, def.centre[2] - def.size[2] / 2)
	end
	check(math.abs(lowest) < 0.02, "feet on the ground")
	check(
		math.abs(rig.root.centre[2] - rig.root.size[2] / 2 - rig.hipHeight) < 0.01,
		"hip height matches the root part"
	)
	-- left is -x like Roblox's own rig, and the face looks down -z
	check(rig.parts.LeftUpperArm.centre[1] < 0 and rig.parts.RightUpperArm.centre[1] > 0, "left on -x")
	check(rig.parts.Head.attachments.FaceFrontAttachment[3] < 0, "the face looks down -z")
	for _, side in { "Left", "Right" } do
		check(rig.parts[side .. "Hand"].attachments[side .. "GripAttachment"] ~= nil, side .. " grip")
		check(rig.parts[side .. "Foot"].attachments[side .. "FootAttachment"] ~= nil, side .. " foot point")
	end
	check(
		rig.triangles > 1000 and rig.triangles <= 12000,
		"hero within its triangle budget: " .. rig.triangles
	)
end)

-- The studio-wide funnels (shared test file, the same in every game) against Capeline's ladder and save
require("./funnelkit_test")(test, check, FunnelKit, FunnelDef, ProfileSchema.default())

test("Analytics: the funnels' save is in the profile, repaired on load and kept off the client", function()
	local p = ProfileSchema.default()
	for key, value in FunnelKit.blank() :: any do
		check(p.funnel[key] == value, "default funnel." .. key)
	end
	local bad = ProfileSchema.default()
	bad.funnel = { sessions = -3, stage = "x", played = 12 }
	local fixed = ProfileSchema.load(bad)
	check(fixed.funnel.sessions == 0 and fixed.funnel.stage == 0 and fixed.funnel.played == 12, "repaired")
	local old = ProfileSchema.default()
	old.funnel = nil
	old.version = 7
	check(ProfileSchema.load(old).funnel.sessions == 0, "a v7 save gains the funnel numbers")
	check(ProfileSchema.clientView(p).funnel == nil, "never sent to the client")
	for _, name in { "session_start", "stage_reached", "session_end", "first_session_end", "session_device" } do
		check(AnalyticsSchema.EVENTS[name] ~= nil, "schema has " .. name)
	end
	check(AnalyticsSchema.EVENTS.leave == nil, "leave is replaced by session_end")
end)

test("Perf: FrameProf times wrapped loops, passes values through, sorts busiest first", function()
	FrameProf.rows() -- clear
	local light = FrameProf.wrap("Light", function(a: number, b: number)
		return a + b, "ok"
	end)
	local heavy = FrameProf.wrap("Heavy", function()
		local x = 0
		for i = 1, 200000 do
			x += i
		end
		return x
	end)
	for _ = 1, 4 do
		FrameProf.tick()
		local sum, tag = light(2, 3)
		check(sum == 5 and tag == "ok", "wrap returns every value")
		check(heavy() > 0, "wrap returns the value")
	end
	local rows, frames = FrameProf.rows()
	check(frames == 4, "4 frames counted")
	check(#rows == 2 and rows[1].name == "Heavy", "busiest system first")
	check(rows[1].calls == 4 and rows[1].worst >= rows[1].avg, "calls and worst kept")
	local again = FrameProf.rows()
	check(#again == 0, "rows clears the window")
	check(string.find(FrameProf.report(), "[FrameProf]", 1, true) ~= nil, "report has a header")
end)

test("Art: robot mesh fits are sane and match the renderer's pieces", function()
	local fit = Config.ArtFit.fit
	-- the pieces EnemyRenderer builds that a Blender mesh can stand in for
	local pieces = {}
	for _, n in
		{
			"Spine",
			"Ribs",
			"Core",
			"Pelvis",
			"Skull",
			"Jaw",
			"Eyes",
			"Upper",
			"Lower",
			"Thigh",
			"Shin",
			"Elbow",
			"Knee",
			"ChestL",
			"ChestR",
			"Belly",
			"Belt",
			"Emblem",
			"FaceL",
			"FaceR",
			"Hair",
			"EyeL",
			"EyeR",
			"ShUpper",
			"ShLowerL",
			"ShLowerR",
			"ShThigh",
			"ShShin",
			"Cape",
			"Jet",
			"Cannon",
			"Muzzle",
			"Base",
			"Guard",
			"Tank",
			"Collar",
			"Mask",
			"Bag",
		}
	do
		pieces[n] = true
	end
	for name, f in fit do
		check(pieces[name] == true, "fit " .. name .. " is a renderer piece")
		check(#f == 3, "fit " .. name .. " has x, up and depth")
		for _, v in f do
			check(v > 0.3 and v < 8, "fit " .. name .. " is a sensible size")
		end
	end
	check(fit.ChestL[1] == 1 and fit.FaceL[1] == 1, "the halves meet in the middle")
	local h = Config.ArtFit.hair
	check(#h == 2 and h[1] > 0 and h[1] < 0.8 and math.abs(h[2]) < 0.2, "the hair sits on top of the head")
end)

test("Creator plan: 36 weapons in 7 families, Exotic ones sold for Robux, the rest on the Rack", function()
	local WeaponRules = require("../src/shared/WeaponRules")
	local W = Config.Weapons
	local list = WeaponRules.list(Config)
	check(#list == 36, "36 weapons")
	local perFamily, names = {}, {}
	for id, w in list do
		check(w.id == id, "ids match their place")
		check(not names[w.name], "unique name " .. w.name)
		names[w.name] = true
		perFamily[w.family] = (perFamily[w.family] or 0) + 1
		check(w.complexity >= 1 and w.complexity <= #W.complexity, w.name .. " complexity")
		check(W.styles[w.family] ~= nil and #W.styles[w.family] == 4, w.name .. " has 4 styles")
		if w.family == "exotic" then
			local row = w.robux and Config.Shop.products[w.robux]
			check(row ~= nil and row.kind == "weapon" and row.weapon == id, w.name .. " is a Robux product")
			check(w.price == nil, w.name .. " is not on the Rack")
		else
			check(w.price ~= nil and w.price >= 0 and w.robux == nil, w.name .. " is on the Rack")
		end
	end
	local want = { fists = 4, one = 6, two = 6, dual = 5, shield = 3, ranged = 7, exotic = 5 }
	for _, f in W.families do
		check(perFamily[f.id] == want[f.id], f.name .. " count")
	end
	check(#W.playable == 36, "all 36 weapons are playable")
	local seen = {}
	for _, id in W.playable do
		seen[list[id].family] = true
	end
	for _, f in W.families do
		check(seen[f.id], f.name .. " has a playable weapon")
	end
	check(list[W.defaultWeapon].price == 0, "the default weapon is always owned")
end)

test("Creator plan: weapon ownership, free pick, the Rack, mastery skills and the weapon look", function()
	local WeaponRules = require("../src/shared/WeaponRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local ShopRules = require("../src/shared/ShopRules")
	local p = ProfileSchema.default()
	check(WeaponRules.owned(Config, p, 1), "Bare Fists are always owned")
	check(not WeaponRules.owned(Config, p, 5), "the Sword is not owned yet")
	check(WeaponRules.freePickOk(Config, 5), "the creator may give the Sword free")
	check(not WeaponRules.freePickOk(Config, 36), "never a Robux weapon free")
	check(WeaponRules.freePickOk(Config, 6), "the Katana is a free pick now that every weapon is playable")
	local ok, why = WeaponRules.buyOk(Config, p, 5, 100)
	check(not ok and why == "credits", "too few Credits")
	ok = WeaponRules.buyOk(Config, p, 5, 5000)
	check(ok, "the Rack sells the Sword")
	check(
		select(2, WeaponRules.buyOk(Config, p, 32, 99999)) == "robux",
		"the Rack never sells Exotic weapons"
	)
	check(WeaponRules.grant(p, 5) and not WeaponRules.grant(p, 5), "grant once")
	check(select(2, WeaponRules.buyOk(Config, p, 5, 99999)) == "owned", "owned weapons are not sold twice")
	-- the Robux shop gives an Exotic weapon once per receipt
	check(not ShopRules.owned(Config, p, "weaponBoomerang"), "Boomerang not owned")
	local granted, got = ShopRules.grant(Config, p, "weaponBoomerang", "r1")
	check(granted and got and got.weapon == 36, "the Boomerang is granted")
	check(ShopRules.owned(Config, p, "weaponBoomerang") and WeaponRules.owned(Config, p, 36), "owned now")
	check(not (ShopRules.grant(Config, p, "weaponBoomerang", "r1")), "a receipt grants once")
	-- mastery: Z at once, X at 25, C at 75, V at 150, max 300
	local M = Config.Weapons.mastery
	check(WeaponRules.skillOpen(Config, 0, "Z") and not WeaponRules.skillOpen(Config, 0, "X"), "Z at once")
	local lvl, opened = WeaponRules.addMastery(Config, p, 5, 25 * M.perLevel)
	check(lvl == 25 and #opened == 1 and opened[1] == "X", "X opens at 25")
	lvl, opened = WeaponRules.addMastery(Config, p, 5, 10 ^ 9)
	check(lvl == M.max and #opened == 2, "C and V open together on a big jump; capped at max")
	check(WeaponRules.state(p, 5).mastery == M.max * M.perLevel, "points cap at max")
	-- the weapon look: 12 bytes, range checks, saved per weapon
	local look = {
		id = 5,
		style = 3,
		finish = 6,
		main = 48,
		trim = 0,
		glow = 46,
		glowLevel = 3,
		emblem = true,
		trail = 2,
	}
	local back = WeaponRules.decodeLook(WeaponRules.encodeLook(look)) :: any
	check(back and back.style == 3 and back.main == 48 and back.emblem and back.trail == 2, "look round trip")
	check(WeaponRules.lookOk(Config, back), "a valid look")
	local bad = table.clone(back)
	bad.style = 5
	check(select(2, WeaponRules.lookOk(Config, bad)) == "style", "4 styles only")
	bad = table.clone(back)
	bad.main = 49
	check(select(2, WeaponRules.lookOk(Config, bad)) == "color", "colours on the palette")
	WeaponRules.setLook(p, back)
	local saved = WeaponRules.lookOf(p, 5)
	check(
		saved.finish == 6 and saved.glow == 46 and WeaponRules.state(p, 5).mastery > 0,
		"look saved, mastery kept"
	)
	-- the carried weapon falls back to Bare Fists when not owned
	local c = p.characters[1]
	c.weapon = 6
	check(WeaponRules.carried(Config, p, c) == 1, "an unowned weapon falls back")
	c.weapon = 5
	check(WeaponRules.carried(Config, p, c) == 5, "an owned weapon is carried")
end)

test("Creator plan: save v9 pads looks and pieces, keeps weapons, repairs junk", function()
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local LookCodec = require("../src/shared/LookCodec")
	local old = ProfileSchema.default()
	old.version = 8
	old.pieces = { 1, 2, 3, 4, 5, 6, 7, 8 }
	old.weaponsOwned = nil
	old.weapons = { ["5"] = { 100, 2, 3 }, junk = { 1 }, ["99"] = { 1 } }
	local v1 = buffer.create(32)
	buffer.writeu8(v1, 0, 1)
	buffer.writeu8(v1, 2, 4)
	old.characters[1].look = LookCodec.toWords(v1)
	old.characters[1].weapon = "x"
	local p = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
	check(p.version == 9, "version 9")
	check(
		#p.pieces == 32 and p.pieces[8] == 8 and p.pieces[9] == 0,
		"the unlock set pads to 32 words, keeping bits"
	)
	check(#p.weaponsOwned == 2, "weapons owned added")
	check(
		p.weapons["5"] ~= nil and p.weapons["5"][1] == 100 and #p.weapons["5"] == 9,
		"a weapon's numbers kept"
	)
	check(p.weapons.junk == nil and p.weapons["99"] == nil, "junk weapons dropped")
	local c = p.characters[1]
	check(c.weapon == 0, "a bad carried weapon becomes none")
	check(
		#c.look == 32 and (LookCodec.read(c.look) :: any).pieces.suit == 4,
		"an old look pads and still reads"
	)
end)

test(
	"Creator plan: every new piece has a kit, body builds scale sensibly, Randomize uses the new slots",
	function()
		local fs = require("@lune/fs")
		local luau = require("@lune/luau")
		local roblox = require("@lune/roblox")
		local CreatorRules = require("../src/shared/CreatorRules")
		local BodyShape = require("../src/shared/BodyShape")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		local Rng = require("../src/shared/Rng")
		local kits = luau.load(fs.readFile("src/shared/PieceKits.luau"), {
			debugName = "PieceKits",
			environment = { Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Enum = roblox.Enum },
		})()
		local idx = CreatorRules.index(Config)
		local count = 0
		for _, p in idx.list do
			if p.id > 146 then
				count += 1
				if p.tab == "eyes" then
					-- eye shapes: "shape:colour" (LookKit's EYE_SHAPES and EYE_COLORS)
					local shape, tone = string.match(p.kit, "^(%a+):(%a+)$")
					local shapes = { bar = 1, sharp = 1, round = 1, big = 1, narrow = 1, slit = 1, visor = 1 }
					local tones = {
						accent = 1,
						prism = 1,
						gold = 1,
						ice = 1,
						ember = 1,
						spirit = 1,
						white = 1,
						violet = 1,
						toxic = 1,
					}
					check(
						shapes[shape] ~= nil and tones[tone] ~= nil,
						p.name .. " is a real eye shape and colour"
					)
				elseif p.tab == "emblem" then
					local glyph, backing = string.match(p.kit, "^(%a+):(%a+)$")
					local backings = { none = 1, badge = 1, crest = 1, gem = 1 }
					check(
						Config.Creator.shapes[glyph] ~= nil and backings[backing] ~= nil,
						p.name .. " is a real emblem"
					)
				else
					local set = kits[p.tab]
					check(
						set ~= nil and set[p.kit] ~= nil,
						p.name .. " has a kit (" .. p.tab .. "." .. p.kit .. ")"
					)
				end
				check(p.index <= 255, p.name .. " fits a look byte")
				check(p.id < 1024, p.name .. " fits the 1,024-bit pieces bitset")
			end
		end
		-- 121 in the first slice, then 2026-11-17's head area: 20 hair, 7 facial hair, 15 faces, 12 makeup,
		-- 4 ears, 14 eyes and 20 emblems; then 10 headwear and 14 masks; then 30 tops, 10 shoulders and 7 neck; then 7 arms, 8 gloves, 14 boots, 6 wrist, 7 belts, 18 legs, 10 back bling and 3 capes (73)
		check(count == 121 + 92 + 24 + 47 + 73, "357 pieces beyond the first 146 (503 in all)")
		-- every piece's unlock can actually be earned
		for _, p in idx.list do
			local src, n = p.source, p.source.n
			if src.kind == "lvl" then
				check(n >= 1 and n <= Config.Stats.levelCap, p.name .. " level unlock is reachable")
			elseif src.kind == "legacy" then
				check(n >= 1 and n <= Config.Hq.legacy.maxRanks, p.name .. " Legacy rank exists")
			elseif src.kind == "fame" then
				check(n >= 1 and n <= #Config.Pvp.fame.ranks, p.name .. " Fame rank exists")
			elseif src.kind == "mission" then
				check(n >= 1 and n <= #Config.Story.missions, p.name .. " mission exists")
			elseif src.kind == "quest" then
				check(n >= 1 and n <= #Config.Story.quests, p.name .. " side quest exists")
			elseif src.kind == "rep" then
				check(
					(src.a == "league" or src.a == "syndicate" or src.a == "city")
						and n >= 1
						and n <= #Config.Story.rep.ranks,
					p.name .. " reputation rank exists"
				)
			end
		end
		-- every piece beyond the first 146 looks different: no kit shared with another piece in its slot (the
		-- old Robux pack pieces reuse kits in their own colours on purpose)
		local seenKit = {}
		for _, p in idx.list do
			if p.id <= 146 then
				seenKit[p.tab .. "/" .. p.kit] = true
			end
		end
		for _, p in idx.list do
			if p.id > 146 then
				local key = p.tab .. "/" .. p.kit
				check(not seenKit[key], p.name .. " has its own kit (" .. key .. ")")
				seenKit[key] = true
			end
		end
		local roles = {
			head = true,
			torso = true,
			waist = true,
			luarm = true,
			ruarm = true,
			llarm = true,
			rlarm = true,
			lhand = true,
			rhand = true,
			lthigh = true,
			rthigh = true,
			lshin = true,
			rshin = true,
			lfoot = true,
			rfoot = true,
		}
		for slot, set in kits do
			if type(set) == "table" and not string.find(slot, "Hides") and slot ~= "suitPaint" then
				for kit, specs in set do
					local list = if slot == "legs" then specs.parts else specs
					for _, s in list do
						check(roles[s.at] == true, slot .. "." .. kit .. " sits on a body part")
						check(
							s.size.X > 0 and s.size.Y > 0 and s.size.Z > 0 and s.size.Magnitude < 4,
							slot .. "." .. kit .. " size"
						)
					end
				end
			end
		end
		-- the creator's slots are LookCodec's slots
		local LookCodec = require("../src/shared/LookCodec")
		for _, tab in Config.Creator.tabs do
			check(table.find(LookCodec.SLOTS, tab.id) ~= nil, tab.id .. " is a look slot")
		end
		-- body: Medium is the standard rig, Titan is wide and tall, the head never stretches, legs fit the waist
		local std = BodyShape.factors(Config, { build = 2, height = 3, gender = 1 })
		for name, f in std do
			check(f[1] == 1 and f[2] == 1 and f[3] == 1, name .. " is standard on a Medium body")
		end
		local titan, tall = BodyShape.factors(Config, { build = 4, height = 5, gender = 1 })
		check(
			titan.UpperTorso[1] == 1.6 and titan.LeftHand[1] == 1.4 and tall > 1.25,
			"Titan: wide torso, big fists, tall"
		)
		check(titan.Head[1] == titan.Head[2], "the head scales evenly")
		local small = BodyShape.factors(Config, { build = 1, height = 1, gender = 2 })
		check(small.LowerTorso[1] < small.UpperTorso[1], "Female: the waist is narrower")
		check(small.LeftUpperLeg[1] <= small.LowerTorso[1], "legs fit under the waist")
		-- Randomize gives a valid look with new slots and a body
		local profile = ProfileSchema.default()
		local rng = Rng.new(7)
		local used = {}
		for _ = 1, 60 do
			local look = CreatorRules.randomize(Config, profile, rng)
			check((CreatorRules.validate(Config, profile, look)), "Randomize is valid")
			for slot, i in look.pieces do
				if i ~= 0 then
					used[slot] = true
				end
			end
			used["build" .. look.build] = true
		end
		check(
			used.hat and used.legs and used.face and used.build4,
			"Randomize reaches the new slots and builds"
		)
	end
)

test("Creator plan: all 36 weapons have an M1 and Z X C V, held with key 2, opened by Mastery", function()
	local WeaponRules = require("../src/shared/WeaponRules")
	local A, W = Config.Abilities, Config.Weapons
	check(#A.order == 136, "weapon moves stay out of the power order and loadouts")
	local SHAPES =
		{ arc = true, bolt = true, chain = true, dash = true, cone = true, nova = true, line = true }
	SHAPES.buff, SHAPES.field = true, true
	local nums, rows = {}, 0
	for _, id in W.playable do
		for k, key in { "M1", "Z", "X", "C", "V" } do
			local aid = WeaponRules.skillId(Config, id, key)
			local row = aid and A.list[aid]
			check(row ~= nil, "weapon " .. id .. " has " .. key)
			if row then
				rows += 1
				check(A.byNum[row.num] == row, aid .. " is in byNum")
				check(
					row.num > 136 and row.num <= 1023 and not nums[row.num],
					aid .. " num unique, fits CombatUse"
				)
				nums[row.num] = true
				check(row.set == "Weapon" and row.weapon == id, aid .. " is a weapon move")
				check(row.slot == (if k == 1 then "basic" else "skill"), aid .. " slot")
				check(
					SHAPES[row.shape] == true and row.coeff ~= nil and row.cd ~= nil,
					aid .. " shape and numbers"
				)
				check(row.coeff <= 3.5, aid .. " is no stronger than a power skill")
				local eff = AbilityRules.effective(Config, aid, 1)
				check(eff.coeff == row.coeff, aid .. " never ranks up")
				if k == 1 and row.shape == "arc" then
					check(#row.hits == 4, aid .. " is a 4-hit combo")
				end
				if row.shape ~= "buff" and row.shape ~= "field" then
					local cands = { cand(1, 0, 2, -6), cand(2, 3, 2, -8) }
					local plan =
						CastPlan.build(eff, 0, 2, 0, 0, 0, -1, 1, cands, flatWorld, { comboStep = 2 })
					check(plan ~= nil, aid .. " builds a cast plan")
				end
			end
		end
	end
	check(rows == 36 * 5, "180 weapon moves")
	for wid in W.skills do
		check(WeaponRules.playable(Config, wid), "only playable weapons have moves")
	end
	-- the held kit
	local loadout = { set = "Volt", basic = "ZapBolt", skills = { "ChainLightning" }, super = "ThunderDrop" }
	local p = WeaponRules.kit(Config, loadout, "power", 5, 0)
	check(p.basic == "ZapBolt" and p.skills[1] == "ChainLightning" and not p.weapon, "key 1: the power")
	local k0 = WeaponRules.kit(Config, loadout, "weapon", 5, 0)
	check(
		k0.weapon and k0.basic == "W5M1" and k0.skills[1] == "W5Z" and k0.skills[4] == "W5V",
		"key 2: the sword"
	)
	check(k0.super == "ThunderDrop", "the super stays the power's")
	check(not k0.locked[1] and k0.locked[2] and k0.locked[3] and k0.locked[4], "only Z is open at Mastery 0")
	check(
		WeaponRules.slotIn(k0, "W5Z") == "skill" and WeaponRules.slotIn(k0, "W5X") == nil,
		"locked X can't cast"
	)
	check(WeaponRules.slotIn(k0, "ChainLightning") == nil, "power skills wait while the weapon is held")
	check(WeaponRules.slotIn(k0, "W5M1") == "basic", "M1 is the sword combo")
	local per = W.mastery.perLevel
	local k25 = WeaponRules.kit(Config, loadout, "weapon", 5, 25 * per)
	check(not k25.locked[2] and k25.locked[3], "Mastery 25 opens X")
	local k150 = WeaponRules.kit(Config, loadout, "weapon", 5, 150 * per)
	check(not k150.locked[3] and not k150.locked[4], "Mastery 150 opens C and V")
	local soon = WeaponRules.kit(Config, loadout, "weapon", 99, 0) -- a future weapon with no kit yet
	check(not soon.weapon and soon.basic == "ZapBolt", "a weapon with no moves falls back to the power")
	-- the slot in play
	for _, name in { "WeaponHold", "WeaponBuy", "WeaponCarry" } do
		check(
			Remotes[name] and Remotes[name].dir == "C2S" and Remotes[name].rate ~= nil,
			name .. " is rate-limited"
		)
	end
	check(Remotes.CombatUse.schema[1].max >= 300 + 64 * 5 + 4, "CombatUse takes every weapon num")
	for _, sh in world.safehouses do
		check(sh.terminals.weapons ~= nil, sh.name .. " has a Weapon Rack")
		local t = sh.terminals.weapons
		local pad = Config.World.safehouse.pad / 2
		check(math.abs(t.x - sh.x) <= pad and math.abs(t.z - sh.z) <= pad, sh.name .. " Rack sits on the pad")
	end
	check(Config.City.palette.weapons ~= nil, "the Rack has its colour")
end)

test(
	"Hero animations: every mode has its pose, every cast and weapon move has a clip, clips are clean",
	function()
		local HeroAnim = require("../src/shared/HeroAnim")
		local RigMath = require("../src/shared/RigMath")
		local fsx = require("@lune/fs")
		-- every mode MoveController sets is one HeroAnim knows (the MoveMode index other devices read)
		local src = fsx.readFile("src/client/Controllers/MoveController.luau")
		local seen = 0
		for m in string.gmatch(src, 'setMode%("(%a+)"%)') do
			seen += 1
			check(HeroAnim.modeIndex[m] ~= nil, "mode " .. m .. " is in HeroAnim.MODES")
		end
		for m in string.gmatch(src, 'enterWall%([^\n]-"(%a+)"') do
			check(HeroAnim.modeIndex[m] ~= nil, "wall mode " .. m .. " is in HeroAnim.MODES")
		end
		check(seen >= 10, "found MoveController's modes")
		check(Remotes.MoveMode.schema[1].max == #HeroAnim.MODES, "MoveMode takes every mode index")
		for _, m in HeroAnim.MODES do
			local clip = HeroAnim.modeClip(m, 30, false, nil)
			check(
				m == "ground" and clip == nil or clip ~= nil and HeroAnim.CLIPS[clip] ~= nil,
				m .. " has a pose"
			)
		end
		-- hover and fly switch with a margin
		check(HeroAnim.modeClip("fly", 5, false, nil) == "hover", "slow flight hovers")
		check(HeroAnim.modeClip("fly", 40, false, nil) == "fly", "fast flight flies")
		check(
			HeroAnim.modeClip("fly", HeroAnim.hoverSpeed + 2, false, "hover") == "hover",
			"hover holds past the line"
		)
		check(
			HeroAnim.modeClip("fly", HeroAnim.hoverSpeed - 2, false, "fly") == "fly",
			"fly holds past the line"
		)
		check(HeroAnim.modeClip("fly", 0, true, nil) == "downed", "Downed wins over flight")
		-- clips: real R15 joints, keys in order inside the clip, loops end where they start, sane angles
		local joints = { Root = true }
		for _, j in RigMath.JOINTS do
			joints[j[1]] = true
		end
		for name, clip in HeroAnim.CLIPS do
			check(clip.dur > 0 and clip.dur <= 3, name .. " length")
			for joint, keys in clip.joints do
				check(joints[joint] == true, name .. "." .. joint .. " is an R15 joint")
				check(#keys >= 1 and keys[1][1] == 0, name .. "." .. joint .. " starts at 0")
				for i, k in keys do
					check(#k == 5, name .. "." .. joint .. " key has 5 numbers")
					check(k[1] <= clip.dur + 1e-6, name .. "." .. joint .. " key inside the clip")
					if i > 1 then
						check(k[1] > keys[i - 1][1], name .. "." .. joint .. " keys in order")
					end
					for a = 2, 4 do
						check(math.abs(k[a]) <= 360, name .. "." .. joint .. " angle")
					end
					check(
						k[5] == 0 or joint == "Root",
						name .. "." .. joint .. " only Root moves up and down"
					)
				end
				if clip.loop and #keys > 1 then
					local a, b = keys[1], keys[#keys]
					check(
						b[1] == clip.dur and a[2] == b[2] and a[3] == b[3] and a[4] == b[4],
						name .. "." .. joint .. " loops without a pop"
					)
				end
			end
		end
		-- every power and weapon move picks a clip that exists; combos change hands or swings
		local fam = {}
		for _, w in Config.Weapons.list do
			fam[w[1]] = w[2]
		end
		local count = 0
		for _, row in Config.Abilities.list do
			count += 1
			local c = HeroAnim.castClip(row, row.weapon and fam[row.weapon], 1)
			check(HeroAnim.CLIPS[c] ~= nil, row.id .. " plays " .. tostring(c))
		end
		check(count >= 136 + 36 * 5, "checked every power and weapon move")
		for wid = 1, 36 do
			local m1 = Config.Abilities.list["W" .. wid .. "M1"]
			if m1 then
				local a = HeroAnim.castClip(m1, fam[wid], 1)
				local c = HeroAnim.castClip(m1, fam[wid], 3)
				check(
					HeroAnim.CLIPS[a] ~= nil and HeroAnim.CLIPS[c] ~= nil,
					"weapon " .. wid .. " combo clips"
				)
			end
		end
		check(
			HeroAnim.castClip(Config.Abilities.list.W1M1, "fists", 1)
				~= HeroAnim.castClip(Config.Abilities.list.W1M1, "fists", 2),
			"fists alternate hands"
		)
		-- sampling
		local keys = { { 0, 0, 0, 0, 0 }, { 1, 90, 0, -30, 0 } }
		local s0, s1, sh =
			HeroAnim.sampleKeys(keys, 0, 1, false),
			HeroAnim.sampleKeys(keys, 1, 1, false),
			HeroAnim.sampleKeys(keys, 0.5, 1, false)
		check(s0[1] == 0 and s1[1] == 90 and s1[3] == -30, "keys hit exactly")
		check(math.abs(sh[1] - 45) < 1e-6, "halfway is half (smoothstep is symmetric)")
		local w = HeroAnim.sampleKeys(keys, 1.5, 1, true)
		check(math.abs(w[1] - 45) < 1e-6, "loops wrap")
		-- mirror
		local m = HeroAnim.mirror(HeroAnim.CLIPS.punch)
		check(m.joints.LeftShoulder ~= nil and m.joints.RightShoulder ~= nil, "mirror swaps sides")
		check(
			m.joints.LeftShoulder[2][2] == HeroAnim.CLIPS.punch.joints.RightShoulder[2][2],
			"mirror keeps x"
		)
		check(m.joints.Waist[2][3] == -HeroAnim.CLIPS.punch.joints.Waist[2][3], "mirror flips y")
		-- action weights fade in and out
		check(
			HeroAnim.actionWeight(0, 0.5) == 0 and HeroAnim.actionWeight(0.25, 0.5) == 1,
			"fades in, then full"
		)
		check(HeroAnim.actionWeight(0.5, 0.5) == 0, "over at the end")
	end
)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
