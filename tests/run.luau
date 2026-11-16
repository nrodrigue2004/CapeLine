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

test("config: every module loads; 40 abilities with unique network ids", function()
	check(#Config.Abilities.order == 40, "40 abilities")
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
		check(t >= 1 and t <= 7 and not ids[t], kind .. " typeId unique in 1..7")
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
		Formulas.health(Config, 1, 0, "Bruiser") == math.floor(425 * 1.35 + 0.5),
		"Bruiser health at level 1"
	)
	check(
		Formulas.health(Config, 1, 0, "Blaster") == math.floor(425 * 0.9 + 0.5),
		"Blaster health at level 1"
	)
	near(Formulas.damage(Config, 36, 0.6, "Blaster"), 36 * 0.6 * 1.15, 1e-6, "Zap Bolt damage")
	near(
		Formulas.damage(Config, 100, 1, "Speedster", true, 0.4),
		100 * 1.5 * 0.6,
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
		Formulas.damage(Config, Formulas.power(Config, 1), Config.Abilities.list.ZapBolt.coeff, "Blaster")
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
}

test("M2: 5 sets x 8 abilities; every skill and super has 2 mods and a capstone; shapes are known", function()
	check(#AB.sets == 5 and AB.sets[5] == "Blade", "five sets, Blade last")
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
		check(AB.setUnlockLevel[set] ~= nil and AB.setColor[set] ~= nil, set .. " unlock level and colour")
	end
	check(#AB.combos.pairs == 10, "10 team-up combos")
end)

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
		check(not ok4 and reason4 == "set locked", "Frost is locked at level 1")
		local ok5, reason5 = AbilityRules.canRank(Config, { level = 6, ranks = ranks }, "FreezeBeam", true)
		check(ok5 and reason5 == nil, "a starter of a newly unlocked set is free to learn")
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
	local _, r2 = v(40, "Volt", { "Shatter", "Haymaker", "Crush", "ThousandCuts" })
	check(r2 == "over budget", "four 14-point skills (56) are over 52")
	check((v(40, "Volt", { "Shatter", "Haymaker", "Crush", "GroundSpark" })), "14+14+14+8 = 50 fits")
	local _, r3 = v(40, "Volt", { "ChainLightning", "ChainLightning" })
	check(r3 == "duplicate", "no duplicates")
	local _, r4 = v(40, "Volt", { "ThunderDrop" })
	check(r4 == "not a skill", "a super is not a skill")
	local _, r5 = v(19, "Volt", { "ChainLightning" }, "ThunderDrop")
	check(r5 == "super locked", "supers open at 20")
	check((v(20, "Volt", { "ChainLightning" }, "ThunderDrop")), "super at 20")
	local _, r6 = v(10, "Volt", { "FreezeBeam" })
	check(r6 == nil, "Frost unlocked at 6 can be mixed in at 10")
	local _, r7 = v(10, "Volt", { "FlashStep" })
	check(r7 == "set locked", "Blade opens at 18")
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
	near(AbilityRules.cooldown(Config, Formulas, zap, { classId = "Blaster" }), 0.5, 1e-9, "basic 0.5 s")
	near(
		AbilityRules.cooldown(Config, Formulas, zap, { classId = "Blaster", attackSpeed = 0.25 }),
		0.4,
		1e-9,
		"Overcharge +25% attack speed"
	)
	local chain = AbilityRules.effective(Config, "ChainLightning", 1)
	local base = AbilityRules.cooldown(Config, Formulas, chain, { classId = "Blaster" })
	near(base, 6, 1e-9, "Chain 6 s")
	near(
		AbilityRules.cooldown(Config, Formulas, chain, { classId = "Blaster", awakened = true }),
		6 / 1.35,
		1e-9,
		"awakened skills 35% faster"
	)
	near(
		AbilityRules.cooldown(Config, Formulas, chain, { classId = "Speedster" }),
		6 * 0.95,
		1e-9,
		"Speedster -5%"
	)
	local td = AbilityRules.effective(Config, "ThunderDrop", 1)
	near(
		AbilityRules.cooldown(Config, Formulas, td, { classId = "Blaster", awakened = true }),
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
		check(dps("Blaster") > dps("Bruiser"), set .. ": a Bruiser never out-damages a Blaster")
		for _, cls in Config.Classes.order do
			local t = hp / dps(cls)
			-- Push Wave is a cone that hits a crowd, so it is the slowest on one target
			local most = if a.shape == "cone" then 3.8 else 3.2
			check(t >= 1.6 and t <= most, string.format("%s %s kills a L10 Burglar in %.1f s", set, cls, t))
		end
	end
	check(
		Formulas.health(Config, 10, 0, "Bruiser") > Formulas.health(Config, 10, 0, "Blaster"),
		"a Blaster never out-tanks a Bruiser"
	)
	local zapT = hp / (Formulas.damage(Config, power, AB.list.ZapBolt.coeff, "Blaster") / 0.5)
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
	local c, r = Progress.earn(Config, "incident", 10)
	check(c == 35 and r == 45, "incident at zone 10: 35 Credits, 45 Renown")
	local c2, r2 = Progress.earn(Config, "incident", 10, { friends = 5 })
	check(c2 == 46 and r2 == 59, "friend boost caps at +30%")
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
		table.insert(full.characters, ProfileSchema.newCharacter("villain", "Bruiser"))
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
	local cr, rn, m = ContractPlan.pay(Config, "DroneSweep", 10, 0)
	check(cr == (40 + 40) * 2 and rn == (60 + 50) * 2 and m == 2, "Drone sweep L10, first of the day: x2")
	cr, rn, m = ContractPlan.pay(Config, "DroneSweep", 10, 5)
	check(cr == 80 and rn == 110 and m == 1, "the 6th pays the base")
	local _, rn2 = ContractPlan.pay(Config, "Escort", 10, 9)
	check(rn2 == 60 + 5 * 10, "types without their own Renown use the contract row")
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
	check(ProfileSchema.VERSION == 3, "version 3")
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
	local hp0 = PvpRules.health(Config, 30, 0, "Bruiser")
	near(PvpRules.health(Config, 30, 4000, "Bruiser"), hp0 * 1.1, 0.01, "health compresses too")
	-- a geared target dies in as many hits as its compressed health takes
	local maxHealth = Formulas.health(Config, 30, 400, "Blaster")
	local pvpHealth = PvpRules.health(Config, 30, 400, "Blaster")
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
		PvpRules.reviveTime(Config, "Controller") == 1.5 and PvpRules.reviveTime(Config, "Bruiser") == 3,
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
			}
		do
			local folder = client and client:FindFirstChild(path[1])
			check(folder ~= nil and folder:FindFirstChild(path[2]) ~= nil, path[1] .. "." .. path[2])
		end
		local first = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingScreen")
		check(first ~= nil and first.ClassName == "LocalScript", "ReplicatedFirst.LoadingScreen")
		check(game:GetService("Workspace").StreamingEnabled == true, "StreamingEnabled on")
		check(
			game:GetService("Workspace").StreamOutBehavior == roblox.Enum.StreamOutBehavior.Opportunistic,
			"parts stream out when far away (Opportunistic)"
		)
	end)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
