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
	if process.env.TRACE then
		print("> " .. name)
	end
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

test("M1: the ceiling pushes back above the soft line and never lets a hero past the hard one", function()
	local _, _, _, _, y = flyFor(
		20,
		{ wishX = 0, wishY = 1, wishZ = 0, vertical = 1, boost = true },
		0,
		0,
		0,
		100,
		M.ceiling.soft - 60
	)
	check(y <= M.ceiling.hard + 1, string.format("ends below the hard ceiling (y = %.1f)", y))
	check(y > M.ceiling.soft - 20, string.format("climbs up to the soft ceiling (y = %.1f)", y))
end)

test("M1: stamina regenerates 15/s on the ground and 8/s in the air", function()
	near(MoveMath.staminaStep(M, 50, true, false, 1), 65, 1e-6, "ground regen")
	near(MoveMath.staminaStep(M, 50, false, false, 1), 58, 1e-6, "air regen")
	check(
		MoveMath.staminaStep(M, M.stamina.max - 1, true, false, 1) == M.stamina.max,
		"caps at the pool's max"
	)
	check(M.stamina.max == 200, "nate 2026-11-19: double the stamina (100 -> 200)")
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

test("M2: Enemy.Delta carries status flags, facing and the new types' extra flags (13 bytes each)", function()
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "NullSentinel", -60, 0, 0, 1) :: any
	e.yaw = 1.0
	EnemySim.applyStatus(sim, e.id, "slow", 2, { value = 0.5 })
	run(sim, {}, 0, 0.2)
	local b = EnemyBuffer.encodeFor(1, 0, sim.enemies, -60, 0, 0, 100, 60)
	check(buffer.len(b) == EnemyBuffer.HEADER + 13, "13 bytes")
	local _, _, rows = EnemyBuffer.decode(b)
	local r = rows[1]
	check(bit32.band(r.flags, Status.BITS.slow) ~= 0, "slow flag")
	check(bit32.band(r.flags, Status.BITS.shield) ~= 0, "guard up shows as shield")
	check(math.abs(r.yaw - (e.yaw % (2 * math.pi))) < 0.03, "facing survives")
	check(r.typeId == 6, "type")
end)

local NEW_KINDS = {
	"ShieldBearer",
	"Captain",
	"Sniper",
	"Bomber",
	"MedicUnit",
	"Swarmer",
	"Mimic",
	"Interceptor",
	"Grappler",
}

test(
	"New robot types: all 9 in the game, each with its own switch; a switched-off type never spawns",
	function()
		local EnemyVariety = require("../src/shared/EnemyVariety")
		for _, kind in NEW_KINDS do
			local cfg = Config.Enemies[kind]
			check(cfg ~= nil and cfg.on == true, kind .. " is on")
			check(table.find(Config.Enemies.order, kind) ~= nil, kind .. " is in the order")
			check(cfg.typeId >= 10 and cfg.typeId <= 31, kind .. " typeId fits the wire")
			check(cfg.body ~= nil and cfg.name ~= nil, kind .. " has a body and a name")
		end
		-- switch every new type off: nothing spawns, populate never picks one, squads never swap one in
		for _, kind in NEW_KINDS do
			Config.Enemies[kind].on = false
		end
		local ok, err = pcall(function()
			local sim = robotSim()
			for _, kind in NEW_KINDS do
				check(EnemySim.spawn(sim, kind, -50, 0, 0, 1) == nil, kind .. " off: never spawns")
				check(not EnemySim.enabled(Config, kind), kind .. " off: not enabled")
			end
			local heroes = {}
			for i = 1, 8 do
				table.insert(heroes, { id = i, x = -200 - i * 40, y = 3, z = 0, alive = true })
			end
			for t = 1, 120 do
				EnemySim.populate(sim, heroes, t)
			end
			for _, e in sim.enemies do
				check(table.find(NEW_KINDS, e.kind) == nil, "populate never brings a switched-off type")
			end
			local rng = Rng.new(5)
			for _ = 1, 200 do
				for _, row in
					EnemyVariety.squad(
						Config,
						{ { kind = "BurglarBot", n = 6 }, { kind = "SparkDrone", n = 4 } },
						40,
						function()
							return Rng.next(rng)
						end
					)
				do
					check(table.find(NEW_KINDS, row.kind) == nil, "squads never swap in a switched-off type")
				end
			end
		end)
		for _, kind in NEW_KINDS do
			Config.Enemies[kind].on = true
		end
		check(ok, "switches test ran: " .. tostring(err))
	end
)

test("New robot types: squads gain them by level, at most `max` each, story squads untouched", function()
	local EnemyVariety = require("../src/shared/EnemyVariety")
	local rng = Rng.new(11)
	local function rand()
		return Rng.next(rng)
	end
	local squad =
		{ { kind = "BurglarBot", n = 4 }, { kind = "SparkDrone", n = 3 }, { kind = "BruteBot", n = 1 } }
	-- level 1: the first fights stay the classic robots
	for _ = 1, 100 do
		for _, row in EnemyVariety.squad(Config, squad, 1, rand) do
			check(table.find(NEW_KINDS, row.kind) == nil, "level 1 squads keep the classic robots")
		end
	end
	check(#EnemyVariety.unlocked(Config, 1) == 0, "nothing new unlocked at level 1")
	check(#EnemyVariety.unlocked(Config, 40) == 9, "all 9 by the level cap")
	local seen: { [string]: number } = {}
	for _ = 1, 400 do
		local out = EnemyVariety.squad(Config, squad, 30, rand)
		local count, per = 0, {}
		for _, row in out do
			count += row.n
			per[row.kind] = (per[row.kind] or 0) + row.n
		end
		check(count == 8, "a swap keeps the squad size")
		for _, sw in Config.Enemies.variety.swaps do
			check((per[sw.kind] or 0) <= sw.max, sw.kind .. " at most " .. sw.max)
			if per[sw.kind] then
				seen[sw.kind] = (seen[sw.kind] or 0) + 1
			end
		end
	end
	for _, kind in NEW_KINDS do
		check((seen[kind] or 0) > 0, kind .. " shows up in level 30 squads")
	end
	-- a small squad never gets a Captain (min 4)
	for _ = 1, 200 do
		for _, row in EnemyVariety.squad(Config, { { kind = "BurglarBot", n = 2 } }, 40, rand) do
			check(row.kind ~= "Captain", "no Captain in a squad of 2")
		end
	end
end)

test("New robot types: Shield Bearer blocks the front, covers robots behind it, bashes and slows", function()
	local sim = robotSim()
	local b = EnemySim.spawn(sim, "ShieldBearer", -60, 0, 0, 1) :: any
	b.yaw = 0 -- facing -Z
	local _, _, front, f1 = EnemySim.damage(sim, b.id, 100, 1, -60, -30)
	check(f1 == EnemySim.BLOCKED and front == 0, "front hits do nothing")
	-- a Burglar Bot right behind the shield (on +Z), hit from the front (-Z)
	local behind = EnemySim.spawn(sim, "BurglarBot", -60, 0, 6, 1) :: any
	local _, _, cut, f2 = EnemySim.damage(sim, behind.id, 100, 1, -60, -30)
	check(f2 == EnemySim.BLOCKED, "covered by the shield")
	near(cut, 100 * (1 - Config.Enemies.ShieldBearer.cover.cut), 1e-6, "takes 60% less")
	local _, _, open = EnemySim.damage(sim, behind.id, 100, 1, -30, 6)
	near(open, 100, 1e-6, "a hit from the side is not covered")
	local _, _, side, f3 = EnemySim.damage(sim, b.id, 100, 1, -30, 0)
	check(f3 == EnemySim.BROKE and side == 100, "a flank hit knocks the shield aside")
	local _, _, cut2 = EnemySim.damage(sim, behind.id, 100, 1, -60, -30)
	near(cut2, 100, 1e-6, "no cover while the shield is down")
	-- the bash slows
	local s2 = robotSim()
	local b2 = EnemySim.spawn(s2, "ShieldBearer", -60, 0, 0, 1) :: any
	local hero = { id = 1, x = -60, y = 3.5, z = -5, alive = true }
	local bashed
	run(s2, { hero }, 0, 6, function(ev)
		if ev.k == "hit" and ev.cc then
			bashed = ev
		end
	end)
	check(bashed ~= nil and bashed.cc == "slow" and bashed.ccValue == 0.5, "the bash slows the hero")
	check(b2.alive, "still standing")
end)

test("New robot types: Captain rallies robots near it (harder, faster); its fall slows them", function()
	local sim = robotSim()
	local cap = EnemySim.spawn(sim, "Captain", -60, 0, 0, 1) :: any
	local grunt = EnemySim.spawn(sim, "BurglarBot", -60, 0, 10, 1) :: any
	local far = EnemySim.spawn(sim, "BurglarBot", -60, 0, 200, 1) :: any
	cap.nextSpecial = 0
	local hero = { id = 1, x = -60, y = 3, z = -30, alive = true }
	local rally
	run(sim, { hero }, 0, 2, function(ev)
		if ev.k == "rally" then
			rally = ev
		end
	end)
	check(rally ~= nil and rally.r == Config.Enemies.Captain.rally.radius, "a rally goes out")
	check(grunt.rallyUntil > sim.now and grunt.rallyBy == cap.id, "the robot near it is rallied")
	check(far.rallyUntil == 0, "a far one is not")
	check(bit32.band(grunt.extra, EnemySim.EXTRA.rally) ~= 0, "the rally shows on the wire")
	EnemySim.damage(sim, cap.id, math.huge, 1)
	check(grunt.rallyUntil == 0, "the rally ends with the Captain")
	check(Status.has(grunt.status, "slow", sim.now), "and its robots falter")
	-- an ambient Captain brings an escort; a site squad's does not
	local s2 = robotSim()
	local c2 = EnemySim.spawn(s2, "Captain", -60, 0, 0, 1) :: any
	check(#EnemySim.company(s2, c2) == Config.Enemies.Captain.escort.n, "the escort")
	check(#EnemySim.company(s2, c2, false) == 0, "no escort for a squad's Captain")
end)

test("New robot types: Sniper's laser locks before the shot; moving then dodges it", function()
	local function duel(dodge: boolean): (number, any)
		local sim = robotSim()
		local sn = EnemySim.spawn(sim, "Sniper", -60, 0, 0, 1) :: any
		sn.nextSpecial = 0
		local hero = { id = 1, x = -60, y = 3, z = -80, alive = true }
		local hits, aim = 0, nil
		local cfg = Config.Enemies.Sniper
		local t = 0
		while t < cfg.aim.time + 1.5 do
			t += 0.05
			if dodge and aim and t >= aim.at + cfg.aim.time - cfg.aim.lock + 0.05 then
				hero.x = -45 -- side-step once the aim locks
			end
			EnemySim.step(sim, t, { hero })
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "aim" then
					aim = { at = t, ev = ev }
				elseif ev.k == "hit" then
					hits += ev.damage
				end
			end
		end
		return hits, aim
	end
	local hit, aim = duel(false)
	check(
		aim ~= nil and aim.ev.hero == 1 and aim.ev.t == Config.Enemies.Sniper.aim.time,
		"the laser names its hero"
	)
	local cfg = Config.Enemies.Sniper
	near(
		hit,
		Formulas.enemyDamage(Config, "Sniper", 1) * cfg.fire.coeff,
		1e-6,
		"standing still: one heavy round"
	)
	local dodged = duel(true)
	check(dodged == 0, "moving after the lock dodges it")
	-- a stun cancels the aim
	local sim = robotSim()
	local sn = EnemySim.spawn(sim, "Sniper", -60, 0, 0, 1) :: any
	sn.nextSpecial = 0
	run(sim, { { id = 1, x = -60, y = 3, z = -80, alive = true } }, 0, 0.3)
	check(sn.aimUntil > 0, "aiming")
	EnemySim.applyStatus(sim, sn.id, "stun", 1)
	check(sn.aimUntil == 0, "a stun breaks the aim")
	-- it backs away from a hero too close
	local s3 = robotSim()
	local sn3 = EnemySim.spawn(s3, "Sniper", -60, 0, 0, 1) :: any
	run(s3, { { id = 1, x = -60, y = 3, z = -20, alive = true } }, 0, 1)
	check(sn3.z > 0.5, "backs off from a close hero")
end)

test("New robot types: Bomber's grenade lands on the ring, then the ground burns", function()
	local sim = robotSim()
	local bm = EnemySim.spawn(sim, "Bomber", -60, 0, 0, 1) :: any
	bm.nextSpecial = 0
	local cfg = Config.Enemies.Bomber
	local hero = { id = 1, x = -60, y = 3, z = -30, alive = true }
	local lob, boom, zone
	local hits = 0
	run(sim, { hero }, 0, 0.2, function(ev)
		if ev.k == "lob" then
			lob = ev
		end
	end)
	check(lob ~= nil, "a lob (the client draws the landing ring from it)")
	near(lob.t, cfg.grenade.flight, 1e-6, "the ring shows for the flight")
	check(
		math.sqrt((lob.tx - hero.x) ^ 2 + (lob.tz - hero.z) ^ 2) <= cfg.grenade.spread * 1.5,
		"aimed at the hero's spot"
	)
	run(sim, { hero }, 0.2, 2.5, function(ev)
		if ev.k == "boom" then
			boom = ev
		elseif ev.k == "zone" then
			zone = ev
		elseif ev.k == "hit" then
			hits += 1
		end
	end)
	check(boom ~= nil and zone ~= nil, "the blast and the burning patch")
	check(hits >= 2, "standing in it: the blast and the burn")
	-- a hero who walked away is not hit
	local s2 = robotSim()
	local b2 = EnemySim.spawn(s2, "Bomber", -60, 0, 0, 1) :: any
	b2.nextSpecial = 0
	local h2 = { id = 1, x = -60, y = 3, z = -30, alive = true }
	local got = 0
	run(s2, { h2 }, 0, 0.2)
	h2.z = -60
	run(s2, { h2 }, 0.2, 2, function(ev)
		if ev.k == "hit" then
			got += 1
		end
	end)
	check(got == 0, "out of the ring: no hit")
end)

test("New robot types: Medic Unit repairs the most damaged robot, never another Medic", function()
	local sim = robotSim()
	local med = EnemySim.spawn(sim, "MedicUnit", -60, 0, 0, 1) :: any
	local hurt = EnemySim.spawn(sim, "BruteBot", -60, 0, 12, 1) :: any
	local med2 = EnemySim.spawn(sim, "MedicUnit", -70, 0, 0, 1) :: any
	hurt.health = hurt.maxHealth * 0.4
	med2.health = med2.maxHealth * 0.2
	local mend
	local hero = { id = 1, x = -60, y = 3, z = 60, alive = true }
	run(sim, { hero }, 0, 3, function(ev)
		if ev.k == "mend" and ev.e == med.id then
			mend = ev
		end
	end)
	check(mend ~= nil and mend.patient == hurt.id, "repairs the Brute Bot")
	check(hurt.health > hurt.maxHealth * 0.5, "health comes back")
	check(med2.health <= med2.maxHealth * 0.2 + 1e-6, "never repairs another Medic")
	check(bit32.band(med.extra, EnemySim.EXTRA.mend) ~= 0, "the beam shows on the wire")
end)

test("New robot types: Swarmers come in packs, surround, lunge and nip (a third of a robot each)", function()
	local sim = robotSim()
	local lead = EnemySim.spawn(sim, "Swarmer", -60, 0, 0, 1) :: any
	local pack = EnemySim.company(sim, lead)
	check(#pack + 1 == Config.Enemies.Swarmer.pack, "a pack of 6")
	-- 6 Burglar Bots already on one hero: Swarmers still join (each counts a third)
	local hero = { id = 1, x = -60, y = 3, z = -25, alive = true }
	local s2 = robotSim()
	for i = 1, 4 do
		local o = EnemySim.spawn(s2, "BurglarBot", -40 - i * 3, 0, -25, 1) :: any
		o.target, o.state = 1, EnemySim.CHASE
	end
	local sw = EnemySim.spawn(s2, "Swarmer", -60, 0, 0, 1) :: any
	local mates = EnemySim.company(s2, sw)
	local lunged, bites = false, 0
	run(s2, { hero }, 0, 4, function(ev)
		if ev.k == "hit" and ev.melee then
			bites += 1
		end
	end)
	for _, m in mates do
		if m.lungeUntil > 0 then
			lunged = true
		end
	end
	check(lunged or sw.lungeUntil > 0, "they lunge")
	check(bites >= 3, string.format("the pack nips (%d bites)", bites))
	-- they spread round the hero
	local minX, maxX = math.huge, -math.huge
	for _, m in mates do
		minX, maxX = math.min(minX, m.x), math.max(maxX, m.x)
	end
	check(maxX - minX > 2, "the pack spreads out")
end)

test("New robot types: Mimic passes for a citizen until a hero is close, then ambushes", function()
	local sim = robotSim()
	local m = EnemySim.spawn(sim, "Mimic", -60, 0, 0, 1) :: any
	check(m.disguised, "dressed as a citizen")
	run(sim, {}, 0, 0.2)
	check(bit32.band(m.extra, EnemySim.EXTRA.disguise) ~= 0, "the disguise shows on the wire")
	local seen = false
	for _, c in EnemySim.candidates(sim) do
		if c.id == m.id then
			seen = true
		end
	end
	check(not seen, "not a hit target while disguised")
	local hero = { id = 1, x = -60, y = 3, z = -40, alive = true }
	local revealed
	local first
	run(sim, { hero }, 0.2, 20, function(ev)
		if ev.k == "reveal" then
			revealed = ev
		elseif ev.k == "hit" and not first then
			first = ev
		end
	end)
	check(revealed ~= nil, "it walks up and shows itself")
	check(not m.disguised, "no longer disguised")
	check(first ~= nil, "then strikes")
	near(
		first.damage,
		(Config.Enemies.scale.dmgBase + Config.Enemies.scale.dmgPerLevel) * Config.Enemies.Mimic.ambush.coeff,
		1e-6,
		"the ambush strike hits hard"
	)
	-- a hit (an area power) also gives it away
	local s2 = robotSim()
	local m2 = EnemySim.spawn(s2, "Mimic", -60, 0, 0, 1) :: any
	EnemySim.damage(s2, m2.id, 10, 1, -60, -20)
	check(not m2.disguised, "a hit reveals it")
end)

test("New robot types: Interceptor hunts only fliers, its net holds them", function()
	local sim = robotSim()
	local it = EnemySim.spawn(sim, "Interceptor", -60, 40, 0, 1) :: any
	local walker = { id = 1, x = -60, y = 3, z = -20, alive = true }
	run(sim, { walker }, 0, 1)
	check(it.target == nil, "ignores a hero on the ground")
	local flier = { id = 2, x = -60, y = 50, z = -40, alive = true }
	local net
	it.nextSpecial = 0
	run(sim, { walker, flier }, 1, 6, function(ev)
		if ev.k == "hit" and ev.cc then
			net = ev
		end
	end)
	check(it.target == 2, "goes after the flier")
	check(net ~= nil and net.cc == "root" and net.hero == 2, "the net holds the flier")
	-- it lets the hero go a while after it lands
	flier.y = 3
	run(sim, { walker, flier }, 6, 9.5)
	check(it.target == nil, "lets a landed hero go")
end)

test("New robot types: Grappler's hook pulls a hero down to it, then it punches", function()
	local sim = robotSim()
	local g = EnemySim.spawn(sim, "Grappler", -60, 0, 0, 1) :: any
	g.nextSpecial = 0
	local flier = { id = 1, x = -60, y = 30, z = -25, alive = true }
	local hook, shot
	run(sim, { flier }, 0, 2, function(ev)
		if ev.k == "shot" and ev.style == 3 then
			shot = ev
		elseif ev.k == "hit" and ev.pull then
			hook = ev
		end
	end)
	check(shot ~= nil, "fires the hook")
	check(
		hook ~= nil and hook.cc == "root" and hook.ccTime == Config.Enemies.Grappler.hook.hold,
		"hooked and held"
	)
	check(
		hook.pull.reel == Config.Enemies.Grappler.hook.reel and math.abs(hook.pull.x - g.x) < 1e-6,
		"pulled to the Grappler"
	)
	-- up close it punches
	local s2 = robotSim()
	EnemySim.spawn(s2, "Grappler", -60, 0, 0, 1)
	local punches = 0
	run(s2, { { id = 1, x = -60, y = 3.5, z = -4, alive = true } }, 0, 4, function(ev)
		if ev.k == "hit" and ev.melee then
			punches += 1
		end
	end)
	check(punches >= 2, "punches up close")
end)

test("New robot types: fast shots never pass through a hero between steps", function()
	local sim = robotSim()
	local sn = EnemySim.spawn(sim, "Sniper", -60, 0, 0, 1) :: any
	sn.nextSpecial = 0
	local hero = { id = 1, x = -60, y = 3, z = -90, alive = true }
	local hit = false
	local t = 0
	while t < 3 do
		t += 0.2 -- a slow server frame: the round moves 48 studs a step
		EnemySim.step(sim, t, { hero })
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "hit" then
				hit = true
			end
		end
	end
	check(hit, "the round still hits")
end)

test("New robot types (review): a pull breaks a Sniper's aim, so no round comes without a laser", function()
	local sim = robotSim()
	local sn = EnemySim.spawn(sim, "Sniper", -60, 0, 0, 1) :: any
	sn.nextSpecial = 0
	local hero = { id = 1, x = -60, y = 3, z = -80, alive = true }
	local t = run(sim, { hero }, 0, 0.3)
	check(sn.aimUntil > 0, "aiming")
	-- a Pull longer than the aim drags it 10 studs toward the hero
	EnemySim.applyStatus(sim, sn.id, "pull", 2, { x = -60, y = 3, z = -10, speed = 5 })
	local shots = 0
	run(sim, { hero }, t, t + 2.4, function(ev)
		if ev.k == "shot" then
			shots += 1
		end
	end)
	check(shots == 0, string.format("no round right after the pull (%d)", shots))
	check(bit32.band(sn.extra, EnemySim.EXTRA.aim) == 0 or sn.aimUntil > sim.now, "no stale aim bit")
end)

test("New robot types (review): a Grappler that falls or is stunned cuts its hook", function()
	local function fired(stun: boolean): (number, any, any)
		local sim = robotSim()
		local g = EnemySim.spawn(sim, "Grappler", -60, 0, 0, 1) :: any
		g.nextSpecial = 0
		local hero = { id = 1, x = -60, y = 3, z = -40, alive = true }
		local t, shot = 0, false
		while not shot and t < 2 do
			t += 0.05
			EnemySim.step(sim, t, { hero })
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "shot" and ev.style == 3 then
					shot = true
				end
			end
		end
		check(shot, "the hook is out")
		if stun then
			EnemySim.applyStatus(sim, g.id, "stun", 1)
		else
			EnemySim.damage(sim, g.id, math.huge, 1)
		end
		local pulls = 0
		run(sim, { hero }, t, t + 1.5, function(ev)
			if ev.k == "hit" and ev.pull then
				pulls += 1
			end
		end)
		return pulls, g, sim
	end
	local pulls = fired(false)
	check(pulls == 0, "a fallen Grappler's hook pulls nobody")
	local p2, g2, s2 = fired(true)
	check(p2 == 0, "a stun cuts the cable")
	check(
		g2.hookUntil <= s2.now and bit32.band(g2.extra, EnemySim.EXTRA.hooked) == 0,
		"the hooked bit clears"
	)
	for _, s in s2.shots do
		check(s.enemyId ~= g2.id or not s.pull, "no hook left in flight")
	end
end)

test("New robot types (review): a site's Mimic shows itself once the rest of its squad is gone", function()
	local sim = robotSim()
	local m = EnemySim.spawn(sim, "Mimic", -60, 0, 0, 5) :: any
	local mate = EnemySim.spawn(sim, "BurglarBot", -60, 0, 20, 5) :: any
	m.tag, mate.tag = 7, 7
	-- the hero hangs back out of its sight (or hovers over it): nothing would ever give it away
	local hero = { id = 1, x = -60, y = 3, z = -150, alive = true }
	local t = run(sim, { hero }, 0, 1)
	check(m.disguised, "disguised while its squad fights")
	EnemySim.damage(sim, mate.id, math.huge, 1)
	local revealed = false
	t = run(sim, { hero }, t, t + 1, function(ev)
		if ev.k == "reveal" and ev.e == m.id then
			revealed = true
		end
	end)
	check(revealed and not m.disguised, "the last of its squad: it shows itself")
	local seen = false
	for _, c in EnemySim.candidates(sim) do
		seen = seen or c.id == m.id
	end
	check(seen, "and can be hit, so the site can finish")
	-- an untagged one (the Dev panel, the stand-in spawner) keeps its disguise alone
	local s2 = robotSim()
	local m2 = EnemySim.spawn(s2, "Mimic", -60, 0, 0, 5) :: any
	run(s2, { hero }, 0, 1)
	check(m2.disguised, "an ambient Mimic stays disguised")
end)

test("New robot types (review): an Interceptor never nets a hero who has landed", function()
	local sim = robotSim()
	local it = EnemySim.spawn(sim, "Interceptor", -60, 40, 0, 1) :: any
	local flier = { id = 2, x = -60, y = 50, z = -30, alive = true }
	local t = run(sim, { flier }, 0, 1)
	check(it.target == 2, "after the flier")
	flier.y = 3 -- lands; the Interceptor keeps it 2 s
	it.nextSpecial = 0
	local nets = 0
	run(sim, { flier }, t, t + 1.8, function(ev)
		if ev.k == "shot" and ev.style == 2 then
			nets += 1
		end
	end)
	check(nets == 0, string.format("no net at a grounded hero (%d)", nets))
end)

test("New robot types (review): a pack or escort never spawns inside a building", function()
	local sim = robotSim()
	-- the street ends at x = 20, where a 30-stud building starts
	local lead = EnemySim.spawn(sim, "Swarmer", 17, 0, 0, 1) :: any
	local cap = EnemySim.spawn(sim, "Captain", 15, 0, 50, 1) :: any
	local all = EnemySim.company(sim, lead)
	for _, o in EnemySim.company(sim, cap) do
		table.insert(all, o)
	end
	check(#all == 7, "the pack and the escort")
	for _, o in all do
		if o.ai ~= "flyer" then
			check(cityHeight(o.x, o.z) <= 1, o.kind .. " on the street")
			near(o.y, EnemySim.halfHeight(o.cfg), 1e-6, o.kind .. " on the ground, not a roof")
		end
	end
end)

test(
	"New robot types (review): a hook's pull is granted its flat travel only (the drop is a free fall)",
	function()
		local pull = { x = 0, y = 3.5, z = 0, reel = 6, time = 0.5 }
		local hx, hy, hz = 0, 45, 30 -- a flier 30 studs out and 41.5 up
		local mx, mz, drop, grant = EnemySim.hookPull(pull, hx, hy, hz)
		near(math.sqrt(mx * mx + mz * mz), 24, 1e-6, "pulled to `reel` studs short")
		near(drop, 3.5 - 45, 1e-6, "and down to it")
		check(grant <= 24 + 12, string.format("grant %.1f has no drop in it", grant))
		-- the client's arc (MoveController.arcTo, height 3) passes the speed check with that grant
		local st = MoveCheck.new(hx, hy, hz, 0)
		MoveCheck.grant(st, grant)
		local tx, ty, tz = hx + mx, hy + drop, hz + mz
		local ok = true
		for i = 1, 5 do
			local u = i / 5
			local x = hx + (tx - hx) * u
			local y = hy + (ty - hy) * u + 3 * 4 * u * (1 - u)
			local z = hz + (tz - hz) * u
			local pass =
				MoveCheck.sample(st, x, y, z, i * 0.1, Config.Move.caps.run, Config.Move, Config.Safety)
			ok = ok and pass
		end
		check(ok, "the pull is never pulled back")
	end
)

test("New robot types (review): the Dev panel's robot button skips switched-off types", function()
	local order = Config.Enemies.order
	local sniper = table.find(order, "Sniper") :: number
	Config.Enemies.Sniper.on = false
	local nextIdx = EnemySim.nextEnabled(Config, sniper - 1)
	local wrap = EnemySim.nextEnabled(Config, #order)
	Config.Enemies.Sniper.on = true
	check(order[nextIdx] == "Bomber", "Sniper off: Captain then Bomber")
	check(wrap == 1, "wraps to the first")
	check(order[EnemySim.nextEnabled(Config, sniper - 1)] == "Sniper", "on again: back in the cycle")
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

test("M3: levels: xpToNext, cumulative 68,400 to 40, level ups and the cap (Stats.levelCap)", function()
	check(Progress.xpToNext(Config, 1) == 100 and Progress.xpToNext(Config, 2) == 112, "100, 112")
	local total = Progress.totalTo(Config, 40)
	near(total, 68400, 68400 * 0.01, string.format("level 40 takes %d Renown", total))
	local lv, xp, gained = Progress.addRenown(Config, 1, 0, 250)
	check(lv == 3 and xp == 38 and gained == 2, "250 Renown: level 3 with 38 over")
	local CAP = Config.Stats.levelCap
	local cap, capXp = Progress.addRenown(Config, CAP - 1, 0, 1e7)
	check(cap == CAP and capXp == 0, "stops at the cap")
	check(select(1, Progress.nextUnlock(Config, 1)) == 3, "next unlock after 1 is Flight at 3")
	local at, what = Progress.nextUnlock(Config, 40)
	check(at == CAP and what == Progress.CAP_UNLOCK, "after 40 the next unlock is the cap and Legacy")
	check(Progress.nextUnlock(Config, CAP) == nil, "nothing after the cap")
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
	check(r.characters[1].level == Config.Stats.levelCap and r.characters[1].ranks.ZapBolt == 5, "clamped")
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
	-- a district past the hub's tiles (Uptown, the second downtown, and the grown Downtown's west edge) stands on
	-- hub tiles of its own
	local function inDistrict(tx: number, tz: number): boolean
		local x0, z0 = WorldGen.tileOrigin(Config.City, tx, tz)
		local s = Config.City.tile
		for _, d in Config.City.districts do
			if x0 < d.maxX and x0 + s > d.minX and z0 < d.maxZ and z0 + s > d.minZ then
				return true
			end
		end
		return false
	end
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
			if ring > 0 and (t.zone == Z.hub) ~= inDistrict(tx, tz) then
				ringsOk = false
			end
			if
				ring >= 1
				and ring <= 6
				and t.zone ~= Z.suburbs
				and t.zone ~= Z.landmark
				and not inDistrict(tx, tz)
			then
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
	-- the first 220 are the first Downtown, the Docks and Old Town; the grown Downtown and Uptown come after
	local extra = #world.uptown.buildings
	for _, b in world.downtown.buildings do
		extra += if b.grown then 1 else 0
	end
	-- then (2026-11-19, more destruction everywhere) the rest of Old Town and the outskirts (tests/impact_test)
	for _, b in list do
		extra += if b.more then 1 else 0
	end
	check(#list == DS.hubBuildings + extra, "220 buildings and the new ones (got " .. #list .. ")")
	for i = 1, DS.hubBuildings do
		local d = list[i] and list[i].district
		check(d == "Downtown" or d == "Docks" or d == "OldTown", "ids 1 to 220 are the first hub")
	end
	local per: { [string]: number } = {}
	for i, b in list do
		check(b.id == i, "ids run 1 to " .. #list)
		local h = b.top - b.base
		local want = if h <= DS.smallMax then "small" elseif h <= DS.mediumMax then "medium" else "tower"
		check(b.size == want and b.hp == DS.hp[want], "building " .. i .. " has the HP of its size")
		check(b.sx > 0 and b.sz > 0 and h > 0, "building " .. i .. " has a body")
		per[b.district] = (per[b.district] or 0) + 1
	end
	check((per.Downtown or 0) > 0 and (per.Docks or 0) > 0 and (per.OldTown or 0) > 0, "all three districts")
	local again = WorldMap.build(Config, 202650)
	-- the outskirts (last, from the weekly tiles) change by seed; everything before them never does
	local function hubCount(l: { any }): number
		local n = 0
		for _, b in l do
			n += if b.district ~= "Outskirts" then 1 else 0
		end
		return n
	end
	check(
		hubCount(again.buildings) == hubCount(list) and again.buildings[200].x == list[200].x,
		"the hub list never changes by seed"
	)
	local tagged: { [number]: boolean } = {}
	for _, b in world.hubBoxes do
		if b.bid then
			tagged[b.bid] = true
		end
	end
	for _, plan in world.tilePlans do
		for _, b in plan.boxes do
			if b.bid then
				tagged[b.bid] = true
			end
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
	-- pushed along its street (a push toward the kerb stops at the road's edge: travel_test)
	local _, y1, z1, r1 = Vehicles.flipPose(DS, v, 1, 0, 1)
	near(z1, DS.vehicles.flipTravel, 1e-6, "it lands pushed away from the hit")
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

test("M6: zone level is the hero's level raised to the area floor, capped at the level cap", function()
	check(ZoneLevel.area(Config, 0, 0, world.tiles) == "hub", "the plaza is hub")
	check(ZoneLevel.at(Config, 0, 0, 3, world.tiles) == 3, "hub: the hero's own level")
	-- 4 tiles out (3 until 2026-11-19: Downtown now reaches into the third tile west of the hub)
	local sx = -Config.City.mapSize / 2 + (Config.World.hubFirst - 4) * Config.City.tile + 50
	check(ZoneLevel.area(Config, sx, 0, world.tiles) == "suburbs", "4 tiles out is suburbs")
	check(ZoneLevel.at(Config, sx, 0, 1, world.tiles) == 5, "the suburbs floor is 5")
	check(ZoneLevel.at(Config, sx, 0, 30, world.tiles) == 30, "a higher hero keeps their level")
	local cr = Config.World.landmarks[1]
	local cx = -Config.City.mapSize / 2 + (cr.tx + 2) * Config.City.tile
	local cz = -Config.City.mapSize / 2 + (cr.tz + 2) * Config.City.tile
	check(ZoneLevel.area(Config, cx, cz, world.tiles) == "CometCrater", "the crater is its own area")
	check(ZoneLevel.at(Config, cx, cz, 2, world.tiles) == 10, "crater floor 10")
	check(ZoneLevel.at(Config, 0, 0, 99) == Config.Stats.levelCap, "capped at the level cap")
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
local ALL_WHERE =
	{ street = true, tower = true, tram = true, sign = true, roof = true, crane = true, nest = true }

test("M6: 25 incident templates; each side gets its own and the shared ones", function()
	check(#IC.order == 25, "25 templates (10 at M6, 14 more on 2026-11-17, the Suspicious Hero in WP5)")
	local nums = {}
	for _, tid in IC.order do
		local t = IC.templates[tid]
		check(
			t ~= nil and not nums[t.num] and t.num >= 1 and t.num <= #IC.order,
			tid .. " has a unique number"
		)
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
		#hero == 19 and table.find(hero, "RobotHeist") and not table.find(hero, "VaultBreach"),
		"hero: 19 without a boss"
	)
	check(
		#villain == 22 and table.find(villain, "ShardCrate") and not table.find(villain, "RobotHeist"),
		"villain: 22"
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

test("M6: contract boards offer 4 for your side, the same until they change; max 3 accepted", function()
	check(#CC.order == 12, "12 contract types (6 at M6, 6 more on 2026-11-17)")
	for w = 1, 60 do
		local h = ContractPlan.offers(CC, 7, "hero", w, 10)
		local v = ContractPlan.offers(CC, 7, "villain", w, 10)
		check(#h == CC.board.offers and #v == CC.board.offers and CC.board.offers == 4, "4 offers")
		local seen = {}
		for _, o in h do
			check(o.type ~= "VaultJob" and not seen[o.type], "heroes never see the Vault job; no repeats")
			seen[o.type] = true
		end
		for _, o in v do
			check(o.type ~= "Stakeout" and o.type ~= "Defusal", "villains never see the hero-only jobs")
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
		{ { type = "Escort", got = 9999, level = 99 }, { type = "Escort" }, { type = "Nope" }, 5 },
		Config.Stats.levelCap
	)
	check(
		#fixed == 1 and fixed[1].got == 600 and fixed[1].level == Config.Stats.levelCap,
		"repair clamps and drops junk"
	)
	check(#ContractPlan.repair(CC, "bad", Config.Stats.levelCap) == 0, "repair of junk is empty")
end)

test(
	"M6: random events every 4 to 6 minutes, max 2, never the same twice in a row, all 12 turn up",
	function()
		local EV = Config.Events
		check(#EV.order == 12, "12 events (6 at M6, 6 more on 2026-11-17)")
		local st = EventPlan.new(EV, 0)
		local rng = Rng.new(21)
		local last, starts, seen, lastStart = nil, 0, {}, nil
		for t = 0, 14400, 1 do
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
		check(
			starts >= 38 and kinds == 12,
			string.format("about one every 5 minutes (%d), all 12 kinds", starts)
		)
		check(
			EventPlan.inPocket(EV, 3000) and not EventPlan.inPocket(EV, 100),
			"no events in mission pockets"
		)
	end
)

---------------------------------------------------------------------------
-- More activities (2026-11-17): 24 incidents, 12 events, 12 contracts, the Heroic tier
---------------------------------------------------------------------------

local HeroicRules = require("../src/shared/HeroicRules")
local EnemyVariety = require("../src/shared/EnemyVariety")

-- A copy of Config with some robot types switched off (the real Config is never changed)
local function configWithOff(off: { string }): any
	local c = table.clone(Config)
	c.Enemies = table.clone(Config.Enemies)
	for _, kind in off do
		c.Enemies[kind] = table.clone(Config.Enemies[kind])
		c.Enemies[kind].on = false
	end
	return c
end

local NEW_TYPES = {
	"ShieldBearer",
	"MedicUnit",
	"Sniper",
	"Swarmer",
	"Mimic",
	"Interceptor",
	"Bomber",
	"Captain",
	"Grappler",
}

test("Activities: every incident template is valid (robots exist, step kinds handled, fixed text)", function()
	local kinds = {}
	for _, k in IncidentPlan.KINDS do
		kinds[k] = true
		check(IC.kinds[k] ~= nil and IC.kinds[k].text ~= "", k .. " has a tracker line")
	end
	for k in IC.kinds do
		check(kinds[k] == true, k .. " is a kind the server builds")
	end
	local where = {
		street = true,
		tower = true,
		tram = true,
		sign = true,
		roof = true,
		crane = true,
		nest = true,
		any = true,
	}
	local featured = {}
	local function enemy(kind: any, tid: string)
		check(
			type(kind) == "string" and Config.Enemies[kind] ~= nil,
			tid .. ": robot " .. tostring(kind) .. " exists"
		)
		featured[kind] = true
	end
	for _, tid in IC.order do
		local t = IC.templates[tid]
		check(where[t.where] == true, tid .. " has a known spot kind")
		for _, kind in t.requires or {} do
			enemy(kind, tid)
			check(
				IncidentPlan.levelFor(IC, Config, tid) >= IncidentPlan.unlockLevel(Config, kind),
				tid .. " waits for " .. kind
			)
		end
		for i, row in t.steps do
			check(kinds[row.kind] == true, tid .. " step " .. i .. " kind " .. row.kind .. " is handled")
			-- (a row with `side` runs only for that side: its line is that side's step, WP5)
			local side = row.side or "hero"
			local at = table.find(IncidentPlan.rows(t, side), row) :: number
			check(IncidentPlan.stepText(IC, tid, at, side) ~= "", tid .. " step " .. i .. " has a line")
			for _, e in row.enemies or {} do
				enemy(e[1], tid)
				check(e[2] >= 0 and e[3] >= e[2], tid .. " row counts")
				if e[4] then
					enemy(e[4], tid)
					check(
						IncidentPlan.unlockLevel(Config, e[4]) <= IncidentPlan.unlockLevel(Config, e[1]),
						tid .. " fallback unlocks no later"
					)
				end
			end
			if row.leader then
				enemy(row.leader, tid)
			end
			if row.enemy then
				enemy(row.enemy, tid)
			end
			if row.prop then
				check(table.find(IC.props, row.prop) ~= nil, tid .. " prop is built")
			end
			if row.kind == "object" then
				check(
					row.label == nil or table.find(IC.objects, row.label) ~= nil,
					tid .. " object model is built"
				)
			end
			if row.kind == "barrage" then
				check(row.blocks >= 1 and row.misses >= 0 and row.every > row.warn, tid .. " barrage timing")
			end
		end
	end
	for _, kind in NEW_TYPES do
		check(featured[kind] == true, kind .. " has an incident of its own")
	end
	for key, b in IC.beats do
		check(Config.Audio.sounds[b.juice] ~= nil and b.text ~= "", key .. " beat has a sound and a line")
	end
	check(#IncidentPlan.KINDS == 12, "6 new step kinds on top of the first 5, and WP5's unmask")
end)

test("Activities: switched-off or locked robot types skip a template or fall back", function()
	local lvl50 = IncidentPlan.choices(IC, "hero", ALL_WHERE, false, Config, 50)
	check(#lvl50 == 19, "every hero template at level 50 with every type on (" .. #lvl50 .. ")")
	local lvl1 = IncidentPlan.choices(IC, "hero", ALL_WHERE, false, Config, 1)
	check(
		not table.find(lvl1, "SniperNest") and not table.find(lvl1, "MimicCrowd"),
		"new types wait for their level"
	)
	check(
		table.find(lvl1, "DroneSwarm") ~= nil and table.find(lvl1, "ShieldWall") ~= nil,
		"fallback templates run early"
	)
	check(
		not IncidentPlan.available(IC, Config, "MimicCrowd", 8)
			and IncidentPlan.available(IC, Config, "MimicCrowd", 9),
		"the Mimic unlocks at 9"
	)
	local off = configWithOff({ "Sniper", "Captain" })
	local list = IncidentPlan.choices(IC, "villain", ALL_WHERE, false, off, 50)
	check(
		not table.find(list, "SniperNest") and not table.find(list, "CaptainWarband"),
		"a switched-off type's template is skipped"
	)
	check(table.find(list, "SignalJam") ~= nil, "a template that only features it stays")
	local rng = Rng.new(5)
	local jam = IncidentPlan.new(IC, rng, "SignalJam", 50, 0, { config = off })
	for _, r in jam.steps[1].spawn :: any do
		check(r.kind ~= "Sniper", "the Sniper falls back")
	end
	check((jam.steps[1].spawn :: any)[1].kind == "Turret", "to a Turret")
	local swarm = IncidentPlan.new(IC, rng, "DroneSwarm", 1, 0, { config = Config })
	for _, r in swarm.steps[1].spawn :: any do
		check(r.kind == "SparkDrone", "level 1: the swarm is Spark Drones")
	end
	local all = configWithOff(NEW_TYPES)
	for _ = 1, 300 do
		local tid = IncidentPlan.pick(IC, rng, "hero", ALL_WHERE, nil, false, false, nil, all, 50)
		check(tid ~= nil, "something to do with every new type off")
		for _, row in IC.templates[tid :: string].steps do
			check(
				row.kind ~= "leader"
					and row.kind ~= "find"
					and row.kind ~= "convoy"
					and row.kind ~= "barrage"
					and row.kind ~= "tug",
				"no template that needs a cut type"
			)
		end
		local inc = IncidentPlan.new(IC, rng, tid :: string, 50, 0, { config = all })
		for _, st in inc.steps do
			for _, r in st.spawn or {} do
				check(EnemyVariety.enabled(all, r.kind), "never a switched-off robot")
			end
		end
	end
end)

test("Activities: the scheduler picks the new templates", function()
	local rng = Rng.new(17)
	local seen = {}
	for _ = 1, 6000 do
		local tid = IncidentPlan.pick(IC, rng, "hero", ALL_WHERE, nil, false, false, nil, Config, 50)
		seen[tid :: string] = true
	end
	for _, tid in IncidentPlan.choices(IC, "hero", ALL_WHERE, false, Config, 50) do
		check(seen[tid] == true, tid .. " turns up")
	end
	check(seen.SniperNest and seen.BomberBarrage and seen.GrapplerTow, "new ones among them")
end)

test("Activities: the new step kinds count right (leader, find, convoy, barrage, tug, nest)", function()
	local rng = Rng.new(23)
	local war = IncidentPlan.new(IC, rng, "CaptainWarband", 30, 0, { config = Config })
	local s = war.steps[1]
	check(
		s.kind == "leader" and s.need == 1 and s.leader == "Captain" and #(s.spawn :: any) >= 1,
		"one Captain to down, an escort"
	)
	check(IncidentPlan.advance(war, "leader", 1) == "done", "the Captain falls: done")
	local mimic = IncidentPlan.new(IC, rng, "MimicCrowd", 30, 0, { config = Config })
	check(mimic.steps[1].need == 1 and (mimic.steps[1].spawn :: any)[1].kind == "Mimic", "one Mimic to find")
	local convoy = IncidentPlan.new(IC, rng, "MedicConvoy", 30, 0, { config = Config })
	check(
		convoy.steps[1].need == 2 and (convoy.steps[1].spawn :: any)[1].kind == "MedicUnit",
		"2 Medic Units, then the squad"
	)
	check(
		IncidentPlan.advance(convoy, "convoy", 2) == "step" and convoy.steps[2].kind == "defeat",
		"convoy stopped: the squad"
	)
	local b = IncidentPlan.new(IC, rng, "BomberBarrage", 30, 0, { config = Config })
	local row = IC.templates.BomberBarrage.steps[1]
	check(b.steps[1].need == row.blocks, "blocks to make")
	check(IncidentPlan.shell(b, true) == nil and b.steps[1].have == 1, "a block counts")
	for _ = 1, row.misses do
		check(IncidentPlan.shell(b, false) == nil, "misses up to the limit are allowed")
	end
	check(IncidentPlan.shell(b, false) == "failed" and b.failed, "one more fails it")
	local b2 = IncidentPlan.new(IC, rng, "BomberBarrage", 30, 0, { config = Config })
	check(IncidentPlan.endBarrage(b2) == "done" and b2.done, "every Bomber down ends the barrage")
	local tow = IncidentPlan.new(IC, rng, "GrapplerTow", 30, 0, { config = Config })
	check(
		tow.steps[1].need == 1 and #tow.steps == 2 and tow.steps[2].kind == "rescue",
		"down the Grappler, then the driver"
	)
	local nest = IncidentPlan.new(IC, rng, "SniperNest", 30, 0, { config = Config })
	check(nest.steps[1].need >= 3, "2 Snipers and drones on the roof")
	check(
		IncidentPlan.stepText(IC, "WaterMain", 2, "hero") == "Carry the soaked citizens out",
		"step lines come from config"
	)
end)

test("Activities: Heroic rules (level 40+, tougher robots, one more each squad, x1.5 pay)", function()
	local H = Config.Heroic
	check(
		H.minLevel == 40 and not HeroicRules.eligible(Config, 39) and HeroicRules.eligible(Config, 40),
		"from level 40"
	)
	local rng = Rng.new(31)
	local n = 0
	for _ = 1, 4000 do
		if HeroicRules.roll(Config, "incident", 45, rng) then
			n += 1
		end
		check(not HeroicRules.roll(Config, "incident", 39, rng), "never under 40")
	end
	near(n / 4000, H.chance.incident, 0.03, "rolls at its chance")
	check(
		HeroicRules.robotLevel(Config, 45, true) == 50 and HeroicRules.robotLevel(Config, 45, false) == 45,
		"robots 5 levels up"
	)
	local rows = { { kind = "BurglarBot", n = 2 }, { kind = "SparkDrone", n = 1 } }
	local more = HeroicRules.squad(Config, rows, true)
	check(more[1].n == 3 and more[2].n == 1 and rows[1].n == 2, "one more robot, template untouched")
	local c, r = HeroicRules.pay(Config, 100, 41, true)
	check(c == 150 and r == 62, "x1.5 pay, rounded")
	check(HeroicRules.gearLevel(Config, 50, true) == Config.Stats.levelCap, "gear capped at the level cap")
	check(HeroicRules.time(Config, 100, true) == 115, "15% more time")
	local inc = IncidentPlan.new(IC, rng, "RobotHeist", 45, 0, { config = Config, heroic = true })
	local plain = IncidentPlan.new(IC, Rng.new(1), "RobotHeist", 45, 0, { config = Config })
	check(
		inc.heroic and inc.steps[1].need >= 5 and plain.steps[1].need >= 4,
		"a Heroic squad has the extra robot"
	)
	check(inc.deadline == HeroicRules.time(Config, 90, true) and inc.deadline >= 103, "and 15% more time")
	check(
		not IncidentPlan.canHeroic(IC, "TowerFire") and IncidentPlan.canHeroic(IC, "WaterMain"),
		"only robots or objects get tougher"
	)
	-- the economy check (Decisions 2026-11-17): the bump over the play model stays small
	local bc, br = HeroicRules.incomeBump(Config, 45)
	print(
		string.format("  [Heroic] level 45 income bump: Credits +%.1f%%, Renown +%.1f%%", bc * 100, br * 100)
	)
	check(bc > 0.02 and bc < 0.12 and br > 0.02 and br < 0.12, "Heroic adds a few percent, never a new pace")
	local zc, zr = HeroicRules.incomeBump(Config, 39)
	check(zc == 0 and zr == 0, "nothing under 40")
end)

test("Activities: 12 events, each a known goal, placed by district name (a second downtown joins)", function()
	local EV = Config.Events
	local goals = {}
	for _, g in EventPlan.GOALS do
		goals[g] = true
	end
	local nums, used = {}, {}
	for _, id in EV.order do
		local d = EV.events[id]
		check(goals[d.goal] == true, id .. " has a goal the server builds")
		check(not nums[d.num], id .. " has its own number")
		nums[d.num] = true
		if d.where ~= "hub" and d.where ~= "anchor" then
			local areas = EventPlan.areas(Config, d.where)
			check(#areas >= 1, id .. " finds its district")
			for _, a in areas do
				used[a.name] = true
			end
		end
		for _, w in d.waves or {} do
			check(Config.Enemies[w[1]] ~= nil and w[2] >= 1, id .. " wave robot " .. w[1])
			check(w[3] == nil or Config.Enemies[w[3]] ~= nil, id .. " wave fallback")
		end
		for _, g in EventPlan.guardRows(d) do
			check(Config.Enemies[g[1]] ~= nil, id .. " guard robot " .. g[1])
		end
	end
	check(
		used.Downtown and used.Docks and used.OldTown,
		"events spread over Downtown, the Docks and Old Town"
	)
	local rng = Rng.new(3)
	local x, z, name = EventPlan.place(Config, EV.events.HarbourFog, rng)
	local docks = Config.City.districts.Docks
	check(
		name == "Docks" and x >= docks.minX and x <= docks.maxX and z >= docks.minZ and z <= docks.maxZ,
		"inside the Docks"
	)
	check(
		EventPlan.place(Config, EV.events.RobotRampage, rng) == nil,
		"anchor events are placed by the server"
	)
	-- a bigger city: Uptown (and any "Downtown" district) joins the downtown events
	local big = table.clone(Config)
	big.City = table.clone(Config.City)
	big.City.districts = table.clone(Config.City.districts)
	big.City.districts.Uptown = { minX = -1600, maxX = -900, minZ = -350, maxZ = 350 }
	big.City.districts.DowntownEast = { minX = 900, maxX = 1200, minZ = 0, maxZ = 300 }
	local names = {}
	for _, a in EventPlan.areas(big, "downtown") do
		names[a.name] = true
	end
	check(
		names.Downtown and names.Uptown and names.DowntownEast and not names.Docks,
		"every downtown, by name"
	)
	local lm = EventPlan.areas(Config, { "CometCrater" })
	check(#lm == 1 and lm[1].hx == 200, "landmarks by id")
	local off = configWithOff({ "Mimic" })
	local function ready(kind: string, level: number): boolean
		return IncidentPlan.kindReady(off, kind, level)
	end
	local row = EventPlan.row(off, { "Mimic", 2, "SneakBot" }, 50, false, ready)
	check(row ~= nil and row.kind == "SneakBot" and row.n == 2, "a cut type uses the fallback")
	local hrow = EventPlan.row(Config, { "BurglarBot", 4 }, 45, true, ready)
	check(hrow ~= nil and hrow.n == 5, "Heroic adds one")
	check(EventPlan.row(off, { "Mimic", 2 }, 50, false, ready) == nil, "no fallback: dropped")
end)

test("Activities: 12 contracts: bounty names, Heroic offers and pay, timers, repair", function()
	local B = CC.types.Bounty
	check(#B.names == 12, "12 fixed bounty names")
	for _, kind in B.targets do
		check(Config.Enemies[kind] ~= nil, "bounty target " .. kind .. " exists")
	end
	for _, id in CC.order do
		local t = CC.types[id]
		for _, key in { "squad", "guards", "ambush", "escort" } do
			local g = t[key]
			if g then
				for _, r in (if type(g[1]) == "string" then { g } else g) do
					check(Config.Enemies[r[1]] ~= nil, id .. " robot " .. r[1])
				end
			end
		end
		for _, w in t.waves or {} do
			check(Config.Enemies[w[1]] ~= nil, id .. " wave robot " .. w[1])
		end
	end
	local ready = ContractPlan.readyFor(Config)
	local who, kind = ContractPlan.bounty(CC, 1, 50, ready)
	check(who == "Rust Baron" and kind == "Captain", "pick 1: the first name, the first ready type")
	local _, early = ContractPlan.bounty(CC, 1, 4, ready)
	check(early == "ShieldBearer", "at level 4 only unlocked types are hunted")
	local offReady =
		ContractPlan.readyFor(configWithOff({ "Captain", "Grappler", "ShieldBearer", "Bomber", "Sniper" }))
	local _, last = ContractPlan.bounty(CC, 3, 50, offReady)
	check(last == "BruteBot", "everything cut: a Brute Bot")
	local enemyName = function(k: string): string
		return Config.Enemies[k].name
	end
	local title, text = ContractPlan.title(
		CC,
		{ type = "Bounty", seed = 1, level = 50, got = 0, pick = 2 },
		"hero",
		enemyName,
		ready
	)
	check(
		title == "Bounty: Iron Widow" and string.find(text, "Iron Widow", 1, true) ~= nil,
		"the bounty's name on the board"
	)
	local gt = ContractPlan.title(
		CC,
		{ type = "GeneratorHold", seed = 1, level = 5, got = 0 },
		"villain",
		enemyName,
		ready
	)
	check(gt == "Power tap", "villains see their name")
	local heroic, plain = 0, 0
	for w = 1, 400 do
		for _, o in ContractPlan.offers(CC, 9, "hero", w, 45, false, nil, Config) do
			if o.heroic then
				heroic += 1
			else
				plain += 1
			end
			if o.type == "Bounty" then
				check(o.pick ~= nil and o.pick >= 1 and o.pick <= 12, "a bounty offer has a name")
			end
		end
		for _, o in ContractPlan.offers(CC, 9, "hero", w, 30, false, nil, Config) do
			check(not o.heroic, "no Heroic offers under 40")
		end
	end
	near(heroic / (heroic + plain), Config.Heroic.chance.contract, 0.04, "Heroic offers at their chance")
	local c1, r1 = ContractPlan.pay(Config, "Demolition", 45, 9)
	local c2, r2 = ContractPlan.pay(Config, "Demolition", 45, 9, true)
	check(c2 == math.floor(c1 * 1.5 + 0.5) and r2 == math.floor(r1 * 1.5 + 0.5), "Heroic pays x1.5")
	local fixed = ContractPlan.repair(
		CC,
		{ { type = "Bounty", pick = 99, heroic = true, got = 3 }, { type = "Escort", pick = 4 } },
		50
	)
	check(
		fixed[1].pick == 12 and fixed[1].heroic == true and fixed[1].got == 1,
		"repair keeps Heroic and clamps the pick"
	)
	check(fixed[2].pick == nil and fixed[2].heroic == nil, "no pick on other types")
	near(ContractPlan.holdTick(CC, 10, true, 1), 11, 1e-9, "holding fills")
	near(ContractPlan.holdTick(CC, 10, false, 2), 9, 1e-9, "an empty ring drains")
	check(
		ContractPlan.holdTick(CC, 0.2, false, 2) == 0 and ContractPlan.holdTick(CC, 44.9, true, 1) == 45,
		"clamped"
	)
	check(
		ContractPlan.courierLeft(CC, nil, 5) == nil and ContractPlan.courierLeft(CC, 0, 30) == 45,
		"the courier's clock"
	)
	check(ContractPlan.courierLeft(CC, 0, 99) == 0, "late")
	check(ContractPlan.fuseLeft(CC, 10, 70) == 0 and ContractPlan.fuseLeft(CC, 10, 20) == 40, "the fuse")
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
	-- Framed (mission 3): stage 6 is choice 1's branch
	local before = StoryPlan.steps(Config, 3, "hero", story.choices)
	check(#before == StoryPlan.stages(Config, 3) - 1, "the branch waits for its choice")
	check(StoryPlan.pendingBranch(Config, 3, "hero", 6) == 1, "stage 6 is choice 1's branch")
	local ok, fx = StoryPlan.pick(Config, story, 1, 1, "hero")
	check(ok and fx.skillPoints == 2 and fx.rep[1] == "city" and fx.flag == "bridgeSaved", "Save the Bridge")
	check(not StoryPlan.pick(Config, story, 1, 2, "hero"), "a choice is picked only once")
	local after = StoryPlan.stage(Config, 3, 6, "hero", story.choices)
	check(after ~= nil and after.train, "the train branch goes in")
	local villain = ProfileSchema.newCharacter("villain").story
	local _, vfx = StoryPlan.pick(Config, villain, 1, 2, "villain")
	check(
		vfx.rep[1] == "syndicate" and vfx.flag == "cashGrabbed",
		"a villain's own-side rep is the Syndicate"
	)
	check(StoryPlan.labels(Config, 1, "villain")[2] == "Grab the Cash", "villain button labels")
	check(StoryPlan.stage(Config, 3, 6, "villain", villain.choices).at == "van", "the cash van branch")
	-- The Signal: Test Her puts in an ambush; Trust Her goes straight on
	local trust = ProfileSchema.newCharacter().story
	StoryPlan.pick(Config, trust, 2, 1, "hero")
	check(StoryPlan.stage(Config, 5, 4, "hero", trust.choices) == nil, "trust: no ambush")
	local test2 = ProfileSchema.newCharacter().story
	StoryPlan.pick(Config, test2, 2, 2, "hero")
	check(StoryPlan.stage(Config, 5, 4, "hero", test2.choices).kind == "defeat", "test: an ambush")
	-- The Copy: a villain who reprograms the twin's core gets the Echo Drone (cosmetic)
	local minion = ProfileSchema.newCharacter("villain").story
	StoryPlan.pick(Config, minion, 3, 1, "villain")
	check(StoryPlan.bit(minion.perks, 1), "Reprogram It unlocks the Echo Drone")
end)

test("M7: the journal pins the next mission; quest styles; reputation ranks", function()
	local StoryPlan = require("../src/shared/StoryPlan")
	local story = ProfileSchema.newCharacter().story
	check(StoryPlan.pinnedText(Config, story, "villain") == "Mission 1: The Ceremony", "the next mission")
	check(
		GearMath.questStyle(Config, "GoldSash") ~= nil and GearMath.questStyle(Config, "DockCoat") ~= nil,
		"quest styles (side quest chain rewards, lore step 10)"
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
	check(
		st.missions == 999 and st.quests == nil,
		"kept in the save's mission room (WP11); the old arc list is gone (lore step 10)"
	)
	check(bad.characters[1].sq.retired == 1, "a finished old arc is retired, not lost")
	check(
		st.choices[1] == 2 and st.choices[3] == 0 and st.pinned == 0,
		"choices clamped; the old pin dropped"
	)
	check(
		#bad.frames == ProfileSchema.SMALL_WORDS and #bad.props == ProfileSchema.SMALL_WORDS,
		"new unlock words"
	)
end)

test("M7: story robots: a harmless one never fires and falls in 2 hits; a weak one takes 4", function()
	local sim = EnemySim.new(Config, {
		random = function()
			return 0.5
		end,
	})
	local a = EnemySim.spawn(sim, "SparkDrone", 0, 20, 0, 1) :: any
	local b = EnemySim.spawn(sim, "SparkDrone", 10, 20, 0, 1) :: any
	a.dmgMult, a.hitLife = 0, 2
	b.dmgMult, b.hitLife = 0.35, 4
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
		bridge = {
			points = { "spawn", "trainStart", "trainDir", "van", "boss" },
			lists = { stations = 3, crates = 3, path = 3 },
		},
		tower = { points = { "spawn", "top", "mast", "relay", "boss" }, lists = {} },
		rooftops = { points = { "spawn", "contact", "copy" }, lists = { path = 8 } },
		dungeon = {
			points = { "spawn", "gauntletEnd", "door", "boss" },
			lists = { rooms = 3, turrets = 4, relays = 3 },
		},
		arena = { points = { "spawn", "boss" }, lists = { pillars = 6, cams = 3, screens = 3 } },
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
	check(seen.bridge and seen.tower and seen.rooftops and seen.dungeon and seen.arena, "5 layouts")
	-- robots stand on the pocket's own boxes: the tower top, a roof, the floor, never the dungeon ceiling
	local tower = PocketLayout.build(Config, 3, "tower")
	local top = tower.points.top
	near(PocketLayout.heightAt(tower, top[1], top[3]), top[2] - 1, 1.5, "the tower deck")
	near(PocketLayout.heightAt(tower, tower.cx + 150, tower.cz + 150), tower.floorY, 0.01, "the pocket floor")
	local dungeon = PocketLayout.build(Config, 2, "dungeon")
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
	local CAP = Config.Stats.levelCap
	near(PvpRules.power(Config, CAP + 15, 0), PvpRules.power(Config, CAP, 0), 0.01, "level capped at the cap")
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
	check(s3.kicking and #s3.times == 0, "a flood counts strikes up to one kick")
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
				elseif k == "chains" then
					check((p.source.n or 0) >= 1 and (p.source.n or 0) <= 8, p.name .. " side quest chains")
				elseif k == "fame" then
					check((p.source.n or 0) <= #Config.Pvp.fame.ranks, p.name .. " fame")
				elseif k == "lvl" then
					check((p.source.n or 0) <= 40, p.name)
				elseif k == "legacy" then
					check((p.source.n or 0) <= Config.Hq.legacy.maxRanks, p.name)
				elseif k == "pack" then
					check(Config.Shop.packs[p.source.n or 0] ~= nil, p.name .. " pack")
				elseif k == "pass" then -- H8: a Hero Pass season's costume set
					check(Config.Pass.seasons[p.source.n or 0] ~= nil, p.name .. " pass season")
				else
					check(
						k == "free"
							or k == "drop"
							or k == "starter"
							or (k == "origin" and Config.Creator.origins[p.source.n or 0] ~= nil),
						p.name .. " source " .. k
					)
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
		-- 2026-11-18 (nate: more naming options): 40 titles and 56 nouns, at most 64 each (the save's range)
		check(#C.titles == 40 and #C.nouns == 56, "40 titles and 56 nouns")
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
			not CreatorRules.nameOk(Config, 0, 1)
				and not CreatorRules.nameOk(Config, 1, #Config.Creator.nouns + 1),
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
		check(CreatorRules.maxSlots(profile) == 3, "3 free slots (nate, 2026-11-19)")
		profile.purchases.slots = bit32.lshift(1, 4)
		check(CreatorRules.maxSlots(profile) == 4, "slot 4 bought")
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
		villain.sq.retired = 15 -- 4 old arcs finished before lore step 10: they count as chains
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
			names["Jet Boots"] and names["Reactor Core"] and names["Meteor Trail"],
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
			-- the Hero Pass is nate's call 4: 499 Robux (H8)
			local hi = if row.kind == "heroPass" then 499 else 399
			check(row.robux >= 25 and row.robux <= hi, key .. " priced 25 to " .. hi)
			local ok, got = ShopRules.grant(Config, profile, key, "r-" .. key)
			check(ok and got ~= nil, key .. " grants")
			check(ShopRules.owned(Config, profile, key), key .. " is owned after")
			local again = ShopRules.grant(Config, profile, key, "r-" .. key)
			check(not again, key .. ": the same receipt grants nothing")
		end
		check(frozen(profile) == before, "no product touches Credits, gear, styles, pity, ranks or level")
		check(#profile.purchases.receipts <= 50, "receipts stay at 50")
		local p2 = ProfileSchema.default()
		check(
			ShopRules.available(Config, p2, "slot4"),
			"slot 4 is sold on its own (slot 3 is free since 2026-11-19)"
		)
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
	"M9: Legacy at the level cap: a statue, back to level 1, keeps unlocks and reputation, +10% Renown a rank",
	function()
		local HqRules = require("../src/shared/HqRules")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		local profile = ProfileSchema.default()
		local c = profile.characters[1]
		local CAP = Config.Stats.levelCap
		c.level = CAP - 1
		check(select(2, HqRules.canRetire(Config, c)) == "level", "not before the cap")
		c.level = 40
		check(select(2, HqRules.canRetire(Config, c)) == "level", "not at the old cap of 40 either")
		c.level = CAP
		c.rep = { 900, 0, 300 }
		c.titleId, c.nounId = 3, 1
		c.fame = 5000
		c.startSet = "Blade"
		c.story.opening = 1
		c.equipment[1] = 0
		ProfileSchema.Bits.set(profile.styles, 70)
		local statue = HqRules.retire(Config, profile, 1, 1000)
		check(statue ~= nil and statue.rank == 1 and statue.level == CAP, "a statue in the Hall of Legends")
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
			profile.characters[1].level = CAP
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

test("Level cap 50: Renown, stats, zones, gear, bosses, PvP, Legacy and saves all work to the cap", function()
	local PvpRules = require("../src/shared/PvpRules")
	local HqRules = require("../src/shared/HqRules")
	local CAP = Config.Stats.levelCap
	check(CAP == 50, "the level cap is 50 (nate, 2026-11-17)")
	check(ProfileSchema.LEVEL_CAP == CAP, "the save repairs levels to the same cap")
	-- Renown: every step to the cap is positive and bigger than the one before; 1 to 40 is unchanged
	local prev = 0
	for L = 1, CAP - 1 do
		local need = Progress.xpToNext(Config, L)
		check(
			need > 0 and need > prev,
			string.format("level %d to %d takes more than the step before", L, L + 1)
		)
		prev = need
	end
	near(Progress.totalTo(Config, 40), 68400, 684, "levels 1 to 40 keep the old curve")
	local band = Progress.totalTo(Config, CAP) - Progress.totalTo(Config, 40)
	check(band > 0, string.format("40 to the cap takes %d more Renown", band))
	local lv, xp, gained = Progress.addRenown(Config, 1, 0, Progress.totalTo(Config, CAP) + 5000)
	check(lv == CAP and xp == 0 and gained == CAP - 1, "enough Renown reaches the cap and no further")
	local lv2, xp2, gained2 = Progress.addRenown(Config, CAP, 0, 1e7)
	check(lv2 == CAP and xp2 == 0 and gained2 == 0, "the cap holds")
	local lv3 = Progress.addRenown(Config, 40, 0, Progress.xpToNext(Config, 40))
	check(lv3 == 41, "a level 40 hero now goes on to 41")
	check(
		select(2, Progress.nextUnlock(Config, CAP - 1)) == Progress.CAP_UNLOCK
			and Progress.unlockAt(Config, CAP) == Progress.CAP_UNLOCK,
		"the cap's unlock line is at the cap"
	)
	-- stats keep growing to the cap
	for L = 41, CAP do
		check(Formulas.power(Config, L) > Formulas.power(Config, L - 1), "Power grows at level " .. L)
		check(
			Formulas.health(Config, L, 0, "Elemental") > Formulas.health(Config, L - 1, 0, "Elemental"),
			"Health grows at level " .. L
		)
	end
	-- zones: a hero from 41 to the cap meets their own level everywhere, the hardest water has a floor too
	for L = 41, CAP do
		check(ZoneLevel.at(Config, 0, 0, L, world.tiles) == L, "the hub runs at level " .. L)
		check(DeepLayout.zoneLevel(Config, 0, -100, 3300, L) == L, "the Trench runs at level " .. L)
	end
	check(ZoneLevel.at(Config, 0, 0, CAP + 9, world.tiles) == CAP, "zone levels stop at the cap")
	local D = Config.Deep
	check(
		DeepLayout.zoneLevel(Config, 0, D.trench.floor + 4, 3300, 1) == D.zoneFloor.trenchDeep
			and DeepLayout.zoneLevel(Config, 0, D.trench.deepBelow + 10, 3300, 1) == D.zoneFloor.trench,
		"the Trench's depths are the hardest floor"
	)
	check(D.zoneFloor.trenchDeep > D.zoneFloor.trench and D.zoneFloor.trenchDeep < CAP, "and below the cap")
	-- gear: item levels for the 41 to 50 band, wearable, stronger, every tier open
	local rng = Rng.new(50)
	local lo, hi = 99, 0
	for _ = 1, 500 do
		local il = GearMath.itemLevel(Config, rng, CAP)
		lo, hi = math.min(lo, il), math.max(hi, il)
	end
	local spread = Config.Gear.ilvlSpread
	check(GearMath.ilvlMax(Config) == CAP + spread, "item levels top out at the cap + the spread")
	check(
		lo == CAP - spread and hi == CAP + spread,
		string.format("a level cap zone drops ilvl %d to %d", lo, hi)
	)
	for L = 41, CAP do
		local piece = GearMath.roll(Config, rng, "Legendary", L, { slot = "hands" })
		check(
			piece.ilvl == L and GearMath.canWear(Config, L, piece),
			"a Legendary at ilvl " .. L .. " is wearable"
		)
		check(
			GearMath.baseBudget(Config, "hands", "Legendary", L)
				> GearMath.baseBudget(Config, "hands", "Legendary", L - 1),
			"gear budget grows at ilvl " .. L
		)
		check(LootTable.gate(Config, "Legendary", L) == "Legendary", "Legendary drops at level " .. L)
	end
	check(
		GearMath.canWear(Config, CAP, GearMath.roll(Config, rng, "Epic", CAP + spread, { slot = "head" })),
		"the cap wears the top item level"
	)
	-- robots and world bosses scale on past 40
	check(
		Formulas.enemyHealth(Config, "BurglarBot", CAP) > Formulas.enemyHealth(Config, "BurglarBot", 40),
		"robots at the cap are tougher than at 40"
	)
	check(BossMath.maxHp(Config, 10, CAP, 0) > BossMath.maxHp(Config, 10, 40, 0), "so are world bosses")
	-- PvP compression uses the cap; Legacy opens at the cap
	check(
		PvpRules.level(Config, 45) == 45 and PvpRules.level(Config, CAP + 5) == CAP,
		"PvP levels to the cap"
	)
	local profile = ProfileSchema.default()
	profile.characters[1].level = 40
	check(not HqRules.canRetire(Config, profile.characters[1]), "no Legacy at 40")
	profile.characters[1].level = CAP
	check(HqRules.canRetire(Config, profile.characters[1]), "Legacy at the cap")
	-- saves: a level 45 hero survives a save and load, a level 40 hero from the old cap loads as it was,
	-- nonsense repairs to the cap
	local old = ProfileSchema.default()
	old.characters[1].level = 40
	old.characters[2] = ProfileSchema.newCharacter()
	old.characters[2].level = 45
	old.characters[2].xp = 1234
	old.characters[3] = ProfileSchema.newCharacter()
	old.characters[3].level = 99
	old.legends = { { look = {}, level = 40, rank = 1 } }
	local p = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
	check(p.characters[1].level == 40, "an old level 40 hero keeps level 40")
	check(p.characters[2].level == 45 and p.characters[2].xp == 1234, "level 45 and its Renown are kept")
	check(p.characters[3].level == CAP, "a broken level repairs to the cap")
	check(p.legends[1].level == 40, "an old level 40 statue keeps its level")
	local fixed = ContractPlan.repair(Config.Contracts, { { type = "Escort", level = 47 } }, CAP)
	check(fixed[1].level == 47, "a saved level 47 contract keeps its level")
	-- analytics: the Progress funnel has a stage at the cap, after level 40 and before the first Legacy
	local at40, atCap, atLegacy
	for i, st in FunnelDef.stages do
		if st.name == "Level 40" then
			at40 = i
		elseif st.name == "Level " .. CAP then
			atCap = i
		elseif st.name == "First legacy" then
			atLegacy = i
		end
	end
	check(at40 and atCap and atLegacy and at40 < atCap and atCap < atLegacy, "the funnel has the cap stage")
end)

test("Level cap 50: pacing sim: 1 to 40 keeps its hours, 41 to 50 adds about 35 to 55 hours", function()
	local EconomySim = require("../src/shared/EconomySim")
	local CAP = Config.Stats.levelCap
	local r = EconomySim.run(Config, 1000, 130, 2026)
	local to40, toCap = r.hoursTo[40], r.hoursTo[CAP]
	check(
		to40 >= 40 and to40 <= 55,
		string.format("median hours to 40: %.1f (about 46 before the cap moved)", to40)
	)
	check(toCap < math.huge, "most heroes reach the cap in 130 hours")
	check(
		toCap - to40 >= 35 and toCap - to40 <= 55,
		string.format("41 to %d adds %.1f hours (%.1f to the cap)", CAP, toCap - to40, toCap)
	)
	for L = 41, CAP do
		check(r.hoursTo[L] > r.hoursTo[L - 1], string.format("level %d comes after level %d", L, L - 1))
	end
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

-- Overhaul step 8, the phone pass: touch layout, presets, Button size, and every screen run headless
require("./phone_test")(test, check, Config, process.args[1])

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
	check(Au.juiceSpec == 31 and #Au.juice >= 31, "31 juice actions (spec juice table), then the MMO rows")
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
		"spark_detected",
		"first_spark",
		"fake_cracked",
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
	ok = AnalyticsSchema.check("spark_detected", nil)
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
		-- an outskirts house (2026-11-19) can be one storey of one panel a face: 4 pillars, 4 walls and its roof
		-- (fix-destroy: a round body or an added hub box can be that small too)
		local least = if b.district == "Outskirts" or b.district == "Hub" or b.round then 9 else 13
		check(#g.pieces >= least and #g.pieces <= 256, "piece count for " .. b.id .. ": " .. #g.pieces)
		local kinds = {}
		for _, p in g.pieces do
			kinds[p.kind] = (kinds[p.kind] or 0) + 1
			if b.round then
				-- a silo or tank (fix-destroy): its pieces sit on the circle
				local dx, dz = p.cx - b.x, p.cz - b.z
				check(math.sqrt(dx * dx + dz * dz) <= b.sx / 2 + 1e-6, "inside the round footprint")
			else
				check(
					math.abs(p.cx - b.x) <= b.sx / 2 - p.sx / 2 + 1e-6
						and math.abs(p.cz - b.z) <= b.sz / 2 - p.sz / 2 + 1e-6,
					"inside the footprint"
				)
			end
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
		-- every Blender set uploaded from the cloud (2026-11-18, art/upload/pull_models.py) is in the place, each
		-- MeshPart carries its uploaded mesh, and every mesh name the game looks up is there
		local RigMath = require("../src/shared/RigMath")
		local function meshIn(set: any, name: string, label: string)
			local m = set and set:FindFirstChild(name, true)
			check(m ~= nil and m:IsA("MeshPart"), label .. " has " .. name)
		end
		local function meshFields(t: any, out: { string })
			for k, v in t do
				if k == "mesh" and type(v) == "string" then
					table.insert(out, v)
				elseif type(v) == "table" then
					meshFields(v, out)
				end
			end
			return out
		end
		local sets = {
			Gear = "GearArt",
			Weapons = "WeaponArt",
			Capes = "CapeArt",
			Heads = "HeadArt",
			Gloves = "GloveArt",
			Boots = "BootArt",
			Coats = "CoatArt",
			Belts = "BeltArt",
			Shoulders = "ShoulderArt",
			Backs = "BackArt",
			Hats = "HatArt",
			Hair = "HairArt",
			Eyes = "EyeArt",
			Ears = "EarArt",
			Necks = "NeckArt",
			Wrists = "WristArt",
			Arms = "ArmArt",
			Street = "StreetArt",
			SetPieces = "SetPieceArt",
			Vehicles = "VehicleArt",
			Hq = "HqArt",
			Bosses = "BossArt",
			Trooper = "TrooperArt",
			Bramblebeast = "FinaleArt",
			Voidhound = "FinaleArt",
			WindupGiant = "FinaleArt",
			Bodies = false,
		}
		for name, cfgName in sets do
			local set = art and art:FindFirstChild(name)
			check(set ~= nil, "ReplicatedStorage.Art." .. name)
			if set == nil then
				continue
			end
			local parts, bare = 0, 0
			for _, d in set:GetDescendants() do
				if d:IsA("MeshPart") then
					parts += 1
					if string.match(d.MeshId, "^rbxassetid://%d+$") == nil then
						bare += 1
					end
				end
			end
			check(parts > 0 and bare == 0, name .. ": " .. parts .. " meshes, all uploaded")
			local cfg = cfgName and (Config :: any)[cfgName]
			if cfgName == "FinaleArt" or cfgName == "TrooperArt" then
				local row = if cfgName == "FinaleArt" then cfg[name] else cfg
				for _, j in RigMath.JOINTS do
					meshIn(set, j[3], name)
				end
				for extra in row.extras or {} do
					meshIn(set, extra, name)
				end
			elseif cfgName == "BossArt" then
				for id, row in cfg do
					if type(row) == "table" and row.pieces then
						for _, group in { row.pieces, row.objective or {} } do
							for piece in group do
								meshIn(set, id .. "_" .. piece, name)
							end
						end
					end
				end
			elseif
				cfgName == "StreetArt"
				or cfgName == "SetPieceArt"
				or cfgName == "VehicleArt"
				or cfgName == "HqArt"
			then
				for _, kit in cfg do
					for mesh, row in kit do
						if type(row) == "table" and row.size then
							meshIn(set, mesh, name)
						end
					end
				end
			elseif cfg then
				local list = meshFields(cfg, {})
				check(#list > 0, name .. " names its meshes")
				for _, mesh in list do
					meshIn(set, mesh, name)
				end
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
				"SideQuestService",
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
	local SwingMath = require("../src/shared/SwingMath")
	local px, py, pz, qx, qy, qz, ql = 0, 0, 30, 0, 0, 0, 50
	for _ = 1, 600 do
		px, py, pz, qx, qy, qz, ql = SwingMath.step(M, px, py, pz, qx, qy, qz, 0, 40, 0, ql, 50, 0, 1, 1 / 60)
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
		check(
			table.find({ "ring", "cone", "circles", "lines", "pull", "homing", "column", "tether" }, a.shape)
				~= nil,
			a.id .. " shape"
		)
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

-- WP2: the weekly boards (keys, ranking, the write budget, the reward claimed once, no free text)
require("./boards_test")(test, check, Config)

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
	check(p.version == ProfileSchema.VERSION and p.version >= 9, "version 9 or later")
	check(
		#p.pieces == ProfileSchema.PIECE_WORDS and p.pieces[8] == 8 and p.pieces[9] == 0,
		"the unlock set pads to its full size, keeping bits"
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
				elseif p.tab == "shirt" or p.tab == "pants" then
					local CC = Config.Creator.clothes
					local ids = if p.tab == "shirt" then CC.shirts else CC.pants
					check(type(ids[p.kit]) == "number", p.name .. " has a clothes image slot")
				elseif string.sub(p.kit, 1, 4) == "cat:" then
					-- a Roblox catalog face or hair (2026-11-18): a real face with its image, or a hair to load
					local id = tonumber(string.sub(p.kit, 5))
					local found = false
					for _, row in
						(if p.tab == "visage"
							then Config.CatalogLooks.faces
							elseif p.tab == "beard" then Config.CatalogLooks.beards
							else Config.CatalogLooks.hair)
					do
						found = found or (row[2] == id and (p.tab ~= "visage" or (row[3] or 0) > 0))
					end
					check(found, p.name .. " is a Config.CatalogLooks item")
				elseif p.tab == "visage" then
					check(Config.NpcLooks.faces[p.kit] ~= nil, p.name .. " is one of our faces")
				else
					local set = kits[p.tab]
					check(
						set ~= nil and set[p.kit] ~= nil,
						p.name .. " has a kit (" .. p.tab .. "." .. p.kit .. ")"
					)
				end
				check(p.index <= 255, p.name .. " fits a look byte")
				check(p.id < 32 * ProfileSchema.PIECE_WORDS, p.name .. " fits the pieces bitset")
			end
		end
		-- 121 in the first slice, then 2026-11-17's head area: 20 hair, 7 facial hair, 15 faces, 12 makeup,
		-- 4 ears, 14 eyes and 20 emblems; then 10 headwear and 14 masks; then 30 tops, 10 shoulders and 7 neck; then 7 arms, 8 gloves, 14 boots, 6 wrist, 7 belts, 18 legs, 10 back bling and 3 capes (73)
		-- and the classic clothes and faces (2026-11-17): 18 shirts, 12 pants, 6 faces; and the 5 origin crests
		-- (lore step 2)
		-- and Hero Pass season 1's Opening Night set (H8: suit, cape, mask, boots)
		-- + 5 origin crests and 49 catalog hairs + 44 catalog faces (2026-11-18) + 8 catalog beards (gap-villains)
		check(
			count == 121 + 92 + 24 + 47 + 73 + 36 + 5 + 4 + 5 + 49 + 44 + 8,
			"508 pieces beyond the first 146 (654 in all)"
		)
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
			elseif src.kind == "chains" then
				check(n >= 1 and n <= Config.SideQuests.retired.arcs, p.name .. " side quest chain count")
			elseif src.kind == "rep" then
				check(
					(src.a == "vigil" or src.a == "syndicate" or src.a == "city")
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
			check(table.find(LookCodec.ALL, tab.id) ~= nil, tab.id .. " is a look slot")
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
			used.hat and used.legs and used.build4 and not used.face, -- face details retired 2026-11-18
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
					-- (a 6th of 1 marks a linear key: pt-anims' two-handed copies, sampled every 1/30 s)
					check(#k == 5 or (#k == 6 and k[6] == 1), name .. "." .. joint .. " key has 5 numbers")
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

test("Effects library: every set has an element, every kind a texture, budgets and plans hold", function()
	local FxPlan = require("../src/shared/FxPlan")
	local fsx = require("@lune/fs")
	local L = Config.Fx.lib
	for set in Config.Abilities.setColor do
		check(L.setElement[set] ~= nil and L.elements[L.setElement[set]] ~= nil, set .. " has an element")
	end
	check(L.setElement.Weapon ~= nil, "weapon moves have an element")
	for name, k in L.kinds do
		check(L.textures[k.tex] ~= nil, name .. " has a texture")
		check(
			k.size[1] >= 0 and k.size[2] >= 0 and k.life[1] > 0 and k.life[2] >= k.life[1],
			name .. " sizes and life"
		)
		check(
			k.speed[2] >= k.speed[1] and k.light >= 0 and k.light <= 1 and k.alpha >= 0 and k.alpha < 1,
			name .. " ranges"
		)
	end
	for name, t in L.textures do
		check(
			string.find(t.builtin, "rbxasset://textures/particles/", 1, true) == 1,
			name .. " has a built-in fallback"
		)
		check(fsx.isFile("art/export/fx/" .. t.file), name .. " sheet " .. t.file .. " is generated")
		check(t.id == 0 or t.id > 0, name .. " id is a number")
	end
	for el, e in L.elements do
		for _, moment in { "impact", "trail", "burst" } do
			check(e[moment] ~= nil, el .. " has a " .. moment)
			for kind, n in e[moment] or {} do
				check(L.kinds[kind] ~= nil and n >= 1, el .. "." .. moment .. "." .. kind .. " is a kind")
			end
		end
	end
	-- the presets' shares and budgets exist for every device preset
	for _, name in Config.Presets.order do
		check(L.budget[name] ~= nil and L.scale[name] ~= nil, name .. " has an effects budget")
	end
	check(L.budget.low < L.budget.medium and L.budget.medium < L.budget.high, "budgets grow with the preset")
	-- plans: one-offs always show, the rest scale and never vanish
	local hi = FxPlan.plan(L, "electric", "impact", 1, 1)
	local lo = FxPlan.plan(L, "electric", "impact", 0.4, 1)
	local function count(plan, kind)
		for _, e in plan do
			if e.kind == kind then
				return e.count
			end
		end
		return 0
	end
	check(count(hi, "spark") == L.elements.electric.impact.spark, "high preset draws the full count")
	check(count(lo, "spark") < count(hi, "spark") and count(lo, "spark") >= 1, "low preset draws fewer")
	check(count(lo, "glow") == 1, "a single glow always shows")
	check(FxPlan.plan(L, "nope", "impact", 1, 1)[1] ~= nil, "an unknown element falls back")
	-- the budget refills over a second and trims a burst over it
	local b = FxPlan.newBudget(100, 0)
	check(FxPlan.take(b, 80, 0) == 80 and FxPlan.take(b, 80, 0) == 20, "the budget trims")
	check(FxPlan.take(b, 10, 0) == 0, "an empty budget draws nothing")
	check(FxPlan.take(b, 60, 0.5) == 50, "half a second refills half")
	check(FxPlan.take(b, 500, 10) == 100, "it never stores more than a second")
	-- rings, trails, textures
	check(FxPlan.shockRadius(L, 13) == 12 and FxPlan.shockRadius(L, 400) == 50, "rings snap to a size")
	local pts = FxPlan.trailPoints(L, 1000)
	check(#pts == L.trailMax and pts[1] > 0 and pts[#pts] < 1, "long trails cap their points")
	check(#FxPlan.trailPoints(L, 2) == 1, "short trails emit once")
	local savedSpark = L.textures.spark.id
	L.textures.spark.id = 0
	local tex = FxPlan.textureOf(L, "spark")
	check(tex == L.textures.spark.builtin, "no upload yet: the built-in image")
	L.textures.spark.id = savedSpark
	local saved = L.textures.smoke.id
	L.textures.smoke.id = 12345
	local t2, flip = FxPlan.textureOf(L, "smoke")
	check(t2 == "rbxassetid://12345" and flip == 4, "an uploaded sheet is used with its grid")
	L.textures.smoke.id = saved
end)

test(
	"All power paths: every path has its own look in both styles, every element every moment, and the budget holds",
	function()
		local FxPlan = require("../src/shared/FxPlan")
		local F = Config.Fx
		local L = F.lib
		local A = Config.Abilities
		local function has(list, name)
			return table.find(list, name) ~= nil
		end
		local function rgbOk(t)
			return type(t) == "table" and #t == 3 and t[1] >= 0 and t[1] <= 255 and t[2] >= 0 and t[3] <= 255
		end
		-- which shapes each path has (heads are needed where something flies)
		local shapes: { [string]: { [string]: boolean } } = {}
		local superOf: { [string]: any } = {}
		for _, row in A.list do
			if row.set ~= "Weapon" then
				shapes[row.set] = shapes[row.set] or {}
				shapes[row.set][row.shape] = true
				if row.slot == "super" then
					superOf[row.set] = row
				end
			end
		end
		-- every super look draws from what its shape gives it (a line's end, a cone's fan, an area's centre)
		local LOOK_SHAPE = {
			icecrown = "field",
			sunfall = "field",
			overgrowth = "field",
			tsunami = "line",
			splitter = "line",
			highnoon = "cone",
			mechdrop = "field",
			eclipse = "nova",
			meteor = "leap",
			heavenfall = "line",
			siege = "field",
			titanrise = "field",
			singularity = "field",
			psistorm = "field",
			ascend = "field",
			dawn = "nova",
		}
		local paths, elements, tuples, looks = 0, {}, {}, {}
		for set in A.setColor do
			paths += 1
			local p = F.paths[set]
			check(p ~= nil, set .. " has a look row")
			if p then
				check(rgbOk(p.accent) and rgbOk(p.super.tint), set .. " accent and tint are colours")
				check(has(FxPlan.HEADS, p.head), set .. " head " .. tostring(p.head))
				check(has(FxPlan.MARKS, p.mark), set .. " mark " .. tostring(p.mark))
				check(has(FxPlan.CASTS, p.cast), set .. " cast " .. tostring(p.cast))
				check(has(FxPlan.DASHES, p.dash), set .. " dash " .. tostring(p.dash))
				check(has(FxPlan.PIECES, p.piece), set .. " piece " .. tostring(p.piece))
				check(
					has(FxPlan.PIECES, p.field.piece) and has(FxPlan.MOTIONS, p.field.motion),
					set .. " field"
				)
				check(
					has(FxPlan.PIECES, p.charge.piece) and p.charge.piece ~= "none" and p.charge.n >= 1,
					set .. " charge motes"
				)
				check(
					p.charge.n <= 8 and p.charge.radius > 0 and p.charge.spin > 0,
					set .. " charge motes stay small"
				)
				check(has(FxPlan.SUPERS, p.super.look), set .. " super " .. tostring(p.super.look))
				check(F.words[set] ~= nil and #F.words[set] == 3, set .. " has its Comic sound words")
				local sounds = Config.Audio.paths[set]
				check(sounds ~= nil, set .. " has its sound layer")
				for _, moment in { "cast", "super", "hit", "charge" } do
					local s = sounds and sounds[moment]
					check(s ~= nil and (s.asset > 0 or s.fallback ~= nil), set .. " " .. moment .. " sound")
				end
				local el = L.setElement[set]
				check(el ~= nil and not elements[el], set .. " has its own element (" .. tostring(el) .. ")")
				elements[el] = true
				if set == "Volt" then
					-- the slice nate OKed keeps its look: nothing of the path section draws over it
					check(
						p.head == "none"
							and p.mark == "none"
							and p.cast == "none"
							and p.dash == "none"
							and p.piece == "none"
							and p.field.piece == "none"
							and p.super.look == "none",
						"Volt keeps the slice's look"
					)
					check(L.setElement.Volt == "electric", "Volt stays electric")
				else
					check(
						p.mark ~= "none" and p.cast ~= "none" and p.piece ~= "none",
						set .. " has a mark, flourish, piece"
					)
					check(
						p.super.look ~= "none" and not looks[p.super.look],
						set .. " has its own super moment"
					)
					looks[p.super.look] = true
					local key = p.mark .. "/" .. p.cast .. "/" .. p.head
					check(not tuples[key], set .. " does not share its look with another path")
					tuples[key] = true
					local sh = shapes[set] or {}
					if sh.bolt or sh.chain then
						check(p.head ~= "none", set .. " has a head for what it throws")
					end
					if sh.dash then
						check(p.dash ~= "none", set .. " has a dash trail")
					end
					local sup = superOf[set]
					check(sup ~= nil, set .. " has a super")
					if sup then
						check(
							LOOK_SHAPE[p.super.look] == sup.shape,
							set .. " super look " .. p.super.look .. " suits its " .. sup.shape
						)
					end
				end
			end
		end
		check(paths == 17, "17 paths")
		-- CombatFx draws every name the rows may use
		local src = clientSources()["src/client/Fx/CombatFx.luau"]
		local function drawn(prefix, list)
			for _, name in list do
				if not (prefix == "PIECE" and name == "none") then
					check(
						string.find(src, prefix .. "." .. name .. " = function", 1, true) ~= nil,
						"CombatFx draws " .. prefix .. "." .. name
					)
				end
			end
		end
		drawn("HEAD", FxPlan.HEADS)
		drawn("MARK", FxPlan.MARKS)
		drawn("CAST", FxPlan.CASTS)
		drawn("DASH", FxPlan.DASHES)
		drawn("MOTION", FxPlan.MOTIONS)
		drawn("PIECE", FxPlan.PIECES)
		drawn("SUPER", FxPlan.SUPERS)
		-- every element has all five moments, each a real kind
		for el, e in L.elements do
			for _, moment in { "impact", "trail", "burst", "charge", "super" } do
				check(e[moment] ~= nil, el .. " has a " .. moment)
				for kind, n in e[moment] or {} do
					check(L.kinds[kind] ~= nil and n >= 1, el .. "." .. moment .. "." .. kind .. " is a kind")
					check(kind ~= "shock", el .. "." .. moment .. " leaves shock rings to FxLib.shock")
				end
			end
		end
		-- the budget: a whole super (burst, its own particles, crits on six robots) fits every preset, phones fewer
		for el in L.elements do
			local prev = -1
			for _, name in Config.Presets.order do
				local cost = FxPlan.superCost(L, el, L.scale[name])
				check(
					cost <= L.budget[name] * L.superShare,
					string.format("%s super on %s: %d of %d", el, name, cost, L.budget[name])
				)
				check(cost > prev, el .. " draws more on bigger presets")
				prev = cost
			end
		end
		check(
			L.partBudget.low < L.partBudget.medium and L.partBudget.medium < L.partBudget.high,
			"path pieces: phones fewer"
		)
		check(
			FxPlan.pieces(L, "low", 10) < FxPlan.pieces(L, "high", 10) and FxPlan.pieces(L, "low", 1) == 1,
			"piece counts scale by preset and never vanish"
		)
		-- charge motes close in and grow as the charge fills
		local ch = F.paths.Frost.charge
		local x0, y0, z0, s0 = FxPlan.orbit(ch, 0, 0.3, 1)
		local x1, y1, z1, s1 = FxPlan.orbit(ch, 1, 0.3, 1)
		check(
			math.sqrt(x1 * x1 + y1 * y1 + z1 * z1) < math.sqrt(x0 * x0 + y0 * y0 + z0 * z0),
			"motes close in at full charge"
		)
		check(s1 > s0, "motes grow at full charge")
		local ax, _, az = FxPlan.orbit(ch, 0.5, 0, 1)
		local bx, _, bz = FxPlan.orbit(ch, 0.5, 0, 2)
		check(math.abs(ax - bx) + math.abs(az - bz) > 0.5, "motes spread around the hand")
		check(
			FxPlan.pathOf(F, "Weapon") == nil and FxPlan.pathOf(F, nil) == nil,
			"weapon moves keep their shapes"
		)
		-- the client plays the path's sound layer for casts, supers, hits and charges
		local cc = clientSources()["src/client/Controllers/CombatClient.luau"]
		check(
			string.find(cc, 'Juice.path(eff.set, if slot == "super" then "super" else "cast"', 1, true) ~= nil,
			"cast sound"
		)
		check(
			string.find(cc, '"hit",', 1, true) ~= nil and string.find(cc, '"charge", origin', 1, true) ~= nil,
			"hit and charge sounds"
		)
		check(string.find(cc, "CombatFx.castFlourish(", 1, true) ~= nil, "your own flourish")
		check(string.find(cc, "CombatFx.superMoment(", 1, true) ~= nil, "your predicted super's moment")
	end
)

test("Hold to aim and charge: what charges, how much, and the server's cap", function()
	local ChargeRules = require("../src/shared/ChargeRules")
	local CC = Config.Combat
	local ch = CC.charge
	check(ch.start > 0 and ch.full > ch.start and ch.maxHold > ch.full, "charge timings in order")
	check(
		ch.damage > 0 and ch.damage <= 0.25 and ch.size > 0 and ch.size <= 0.2,
		"a full charge is a modest boost"
	)
	-- what charges
	local charged, aimOnly = 0, 0
	for _, row in Config.Abilities.list do
		if ChargeRules.chargeable(row) then
			charged += 1
			check(
				row.slot == "skill" and not row.channel and (row.coeff or 0) > 0,
				row.id .. " is a damaging skill"
			)
		end
		if row.slot == "super" then
			check(not ChargeRules.chargeable(row), row.id .. " (super) aims but never charges")
			check(ChargeRules.aimable(row), row.id .. " aims")
		end
		if row.slot == "basic" then
			check(not ChargeRules.aimable(row), row.id .. " (basic) fires at once")
		end
		if ChargeRules.aimable(row) and not ChargeRules.chargeable(row) then
			aimOnly += 1
		end
	end
	check(charged >= 40 and aimOnly >= 40, "many skills charge and many only aim")
	-- levels
	check(ChargeRules.level(CC, 0.1) == 0, "a tap does not charge")
	check(ChargeRules.level(CC, ch.full) == 1 and ChargeRules.level(CC, 10) == 1, "full at full")
	near(ChargeRules.level(CC, (ch.start + ch.full) / 2), 0.5, 1e-6, "halfway is half")
	-- the server's cap: no press recorded, no charge; claims cannot beat the timed hold
	check(ChargeRules.allowed(CC, 100, nil, 10, 0.1) == 0, "no press, no charge")
	check(ChargeRules.allowed(CC, 100, 10, 10.05, 0) == 0, "a claim right after the press is cut to 0")
	check(ChargeRules.allowed(CC, 100, 10, 10 + ch.full, 0) == 1, "a real full hold counts")
	near(ChargeRules.allowed(CC, 40, 10, 15, 0), 0.4, 1e-6, "a lower claim is kept")
	check(ChargeRules.allowed(CC, 0, 10, 15, 0) == 0, "a tap claim is a tap")
	-- applying
	local eff = { coeff = 2, radius = 10, range = 40, width = 4, cone = 160 }
	ChargeRules.apply(CC, eff, 1)
	near(eff.coeff, 2 * (1 + ch.damage), 1e-6, "damage grows")
	near(eff.radius, 10 * (1 + ch.size), 1e-6, "size grows")
	check(eff.cone <= 170, "a cone never wraps round")
	local same = { coeff = 2, radius = 10 }
	ChargeRules.apply(CC, same, 0)
	check(same.coeff == 2 and same.radius == 10 and same.charged == nil, "no charge changes nothing")
	-- the remotes
	check(
		Remotes.CombatCharge.dir == "C2S" and Remotes.CombatCharge.rate ~= nil,
		"CombatCharge is rate-limited"
	)
	local last = Remotes.CombatUse.schema[5]
	check(last ~= nil and last.optional == true and last.max == 100, "CombatUse takes an optional charge")
end)

test("Remade robot (Spark Trooper): its superhero shell set and hair", function()
	local T = Config.TrooperArt
	local RigMath = require("../src/shared/RigMath")
	check(T.triangles > 0 and T.triangles <= 8000, "the whole robot is under the 8,000 triangle budget")
	local parts = {}
	for _, j in RigMath.JOINTS do
		parts[j[3]] = true
	end
	local n = 0
	for name, x in T.extras do
		n += 1
		check(parts[x.parent] == true, name .. " sits on an R15 part")
		for k = 1, 3 do
			check(x.size[k] > 0.1 and x.size[k] < 3, name .. " is a sensible size against its part")
			check(math.abs(x.offset[k]) < 1.5, name .. " stays near its part")
		end
	end
	-- the superhero look (nate, 2026-11-17): a face under swept hair, no helmet, pads or pack
	check(n == 1 and T.extras.Hair ~= nil, "the only extra is the hair")
	check(T.extras.Hair.parent == "Head", "the hair sits on the head")
	check(T.extras.Hair.offset[2] > 0, "the hair is on top of the head")
	check(T.extras.Hair.size[1] >= 1 and T.extras.Hair.size[1] < 1.3, "the hair is just wider than the head")
	check(Config.Enemies.SparkDrone.body.art == "Trooper", "the Spark Trooper uses the remade set")
end)

test("Remade bosses: every boss has its meshes, weak points inside their hit spheres", function()
	local A = Config.BossArt
	local ROLES = { hull = true, shed2 = true, shed3 = true, glow = true, weak = true }
	check(A.texture > 0 and A.texture <= 1024, "one phone-friendly texture set a boss (1024 px at most)")
	check(#A.weakColor == 2 and A.pulse > 0, "the weak points pulse between two golds")
	check(#A.objectiveColor == 3, "the objective lamps have a colour")
	local n = 0
	for id, def in Config.Boss.bosses do
		local art = A[id]
		check(art ~= nil, id .. " has remade art")
		if not art then
			continue
		end
		n += 1
		check(art.triangles > 0 and art.triangles <= 16000, id .. " is under the 16,000 triangle boss budget")
		check(#art.glow == 3, id .. " has an accent colour for each phase")
		local roles = {}
		for name, row in art.pieces do
			check(ROLES[row.role] == true, id .. "_" .. name .. " has a body role")
			roles[row.role] = true
			for k = 1, 3 do
				check(
					row.size[k] > 0 and row.size[k] <= def.arenaRadius,
					id .. "_" .. name .. " fits its arena"
				)
				-- a limb split off the hull for the boss pass (the Leviathan's tail wheel) keeps the hull's old reach
				local reach = if row.seg and row.seg ~= "Body" then 0.6 else 0.5
				check(
					math.abs(row.offset[k]) <= def.arenaRadius * reach,
					id .. "_" .. name .. " sits on the boss"
				)
			end
			check(
				row.offset[2] - row.size[2] / 2 > -def.height,
				id .. "_" .. name .. " is not far underground"
			)
		end
		check(roles.hull and roles.weak and roles.glow, id .. " has a hull, accents and weak points")
		check(roles.shed2 and roles.shed3, id .. " sheds plates at phases 2 and 3")
		-- every weak point has a lamp inside its hit sphere (hit boxes stay Config.Boss's), and no lamp is a fake
		for _, t in def.targets do
			if t.weak then
				local at = art.weak[t.id]
				check(at ~= nil, id .. " " .. t.id .. " has a lamp")
				if at then
					local d = math.sqrt((at[1] - t.at[1]) ^ 2 + (at[2] - t.at[2]) ^ 2 + (at[3] - t.at[3]) ^ 2)
					check(d <= t.r, id .. " " .. t.id .. "'s lamp is inside its hit sphere")
				end
			end
		end
		for tid in art.weak do
			local real = false
			for _, t in def.targets do
				real = real or (t.id == tid and t.weak == true)
			end
			check(real, id .. " " .. tid .. " is a real weak point")
		end
		-- one objective body and one lamp, set at each objective; the lamp inside the objective's 5-stud hit sphere
		-- (on the body at the objective's point; a generator's is 8 studs over its foot, BossSim)
		local bodies, lamps = 0, 0
		local up = if def.objectives.list[1].ring then 8 else 0
		for name, row in art.objective do
			if row.role == "objective" then
				bodies += 1
			elseif row.role == "objectiveGlow" then
				lamps += 1
				local o = row.offset
				local d = math.sqrt(o[1] ^ 2 + (o[2] - up) ^ 2 + o[3] ^ 2)
				check(d <= 5, id .. " " .. name .. " sits inside its objective's hit sphere")
			end
			check(row.size[1] > 0 and row.size[2] > 0 and row.size[3] > 0, id .. " " .. name .. " has a size")
		end
		check(bodies == 1 and lamps == 1, id .. " has one objective body and one lamp")
	end
	check(
		n == 4,
		"all four bosses (Rustjaw Prime, the Lumen Maw, the Leviathan Engine, the War-Frame) are remade"
	)
	-- only the look changes: the bosses' hit spheres and numbers are the ones the fight was tuned with
	check(Config.Boss.bosses.RustjawPrime.targets[5].id == "core", "Rustjaw's core target is unchanged")
	check(Config.Boss.bosses.RustjawPrime.targets[5].r == 6, "Rustjaw's core radius is unchanged")
	check(Config.Boss.weakMult == 2, "weak points still take double damage")
end)

test(
	"Heroes in our own clothes: avatar off, the classic clothes and faces, and the avatar rules kept",
	function()
		local AvatarRules = require("../src/shared/AvatarRules")
		local LookCodec = require("../src/shared/LookCodec")
		local CreatorRules = require("../src/shared/CreatorRules")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		-- nate, 2026-11-17: nothing from the player's avatar; our clothes, faces, hair and gear only
		check(Config.Creator.avatar.on == false, "the player's avatar is not used")
		-- nate, 2026-11-19 16:45Z: gender, build and height are back (the creator's Body step)
		check(Config.Creator.bodyStep == true, "the Body step: gender, build and height")
		check(Config.Creator.clothes.on == true, "heroes wear our classic Shirt and Pants")
		-- nothing picked: every avatar item shows
		local none = AvatarRules.hides({})
		check(
			not none.shirt and not none.pants and not none.face and next(none.types) == nil,
			"an empty look hides nothing"
		)
		-- a suit is a bodysuit: shirt, pants, layered tops and bottoms and chest items go
		local suit = AvatarRules.hides({ suit = 1 })
		check(suit.shirt and suit.pants, "a suit hides the shirt and pants")
		for _, t in { "TShirt", "Shirt", "Sweater", "Jacket", "Pants", "Shorts", "DressSkirt", "Front" } do
			check(suit.types[t] == true, "a suit hides layered " .. t)
		end
		check(
			not suit.types.Hair and not suit.types.Hat and not suit.face,
			"a suit keeps hair, hats and the face"
		)
		local legs = AvatarRules.hides({ legs = 3 })
		check(
			not legs.shirt and legs.pants and legs.types.Shorts and not legs.types.Jacket,
			"legs hide only the bottoms"
		)
		check(
			AvatarRules.hides({ feet = 1 }).types.LeftShoe and AvatarRules.hides({ feet = 1 }).types.RightShoe,
			"shoes"
		)
		local hair = AvatarRules.hides({ hair = 2 })
		check(hair.types.Hair and not hair.types.Hat, "creator hair replaces the avatar's hair, hats stay")
		check(AvatarRules.hides({ hat = 1 }).types.Hat, "creator headwear replaces the avatar's hat")
		local helm = AvatarRules.hides({ head = 4 }, true, false)
		check(
			helm.types.Hair and helm.types.Hat and helm.types.Face and not helm.face,
			"a full helm hides hair and hats"
		)
		check(AvatarRules.hides({}, false, true).face, "a closed helm hides the face")
		check(AvatarRules.hides({ face = 1 }).face, "a Face piece replaces the avatar's face")
		check(
			AvatarRules.hides({ back = 2 }).types.Back and AvatarRules.hides({ backpack = 1 }).types.Back,
			"a cape hides wings"
		)
		check(AvatarRules.hides({ back = 0, hair = 0 }).types.Back == nil, "0 means the avatar's own")
		-- old items with no type go by their attachment
		check(AvatarRules.kind("Unknown", "HairAttachment") == "Hair", "an untyped hair")
		check(AvatarRules.kind("Unknown", "BodyBackAttachment") == "Back", "an untyped back item")
		check(AvatarRules.kind("Hat", "HairAttachment") == "Hat", "a typed item keeps its type")
		check(AvatarRules.kind("Unknown", nil) == "Unknown", "no attachment")
		-- every hero is the same size: body parts and scales reset
		for _, f in { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
			check(table.find(AvatarRules.CLEAR, f) ~= nil, f .. " body part reset to the blocky one")
		end
		check(
			AvatarRules.SCALES.HeightScale == 1 and AvatarRules.SCALES.BodyTypeScale == 0,
			"standard scales"
		)
		-- the default look: our hoodie and jeans, a face and hair, with a starter mask, cape and symbol, all free
		local look = CreatorRules.defaultLook(Config)
		check((look.pieces.suit or 0) == 0, "no suit: the classic clothes show")
		check(
			look.pieces.shirt > 0 and look.pieces.pants > 0 and look.pieces.visage > 0,
			"a shirt, pants and a face"
		)
		check(look.pieces.hair > 0 and Config.Creator.skins[look.skin] ~= nil, "our hair and a skin tone")
		check(
			look.pieces.head > 0 and look.pieces.back > 0 and look.pieces.emblem > 0,
			"a starter mask, cape and symbol"
		)
		check((CreatorRules.validate(Config, ProfileSchema.default(), look)), "the default look is valid")
		local bad = LookCodec.copy(look)
		bad.skin = 0
		check(
			not (CreatorRules.validate(Config, ProfileSchema.default(), bad)),
			"skin 0 (the avatar's) is not allowed"
		)
		-- the clothes and face round-trip through the save (kept in the look record's spare bytes)
		look.pieces.shirt, look.pieces.pants, look.pieces.visage = 10, 6, 4
		look.tints.shirt, look.tints.pants = { 7, 0, 0 }, { 12, 0, 0 }
		local back = LookCodec.read(LookCodec.write(look)) :: any
		check(
			back.pieces.shirt == 10 and back.pieces.pants == 6 and back.pieces.visage == 4,
			"clothes and face saved"
		)
		check(back.tints.shirt[1] == 7 and back.tints.pants[1] == 12, "the clothes' tints saved")
		check(
			back.pieces.head == look.pieces.head and back.pieces.emblem == look.pieces.emblem,
			"the other slots kept"
		)
		for _, tab in { "shirt", "pants", "visage" } do
			check(#(CreatorRules.index(Config).byTab[tab] or {}) >= 6, tab .. " has its pieces")
			for _, p in CreatorRules.index(Config).byTab[tab] do
				check(p.source.kind == "free", p.name .. " is free (the everyday look is never sold)")
			end
		end
	end
)

test("Roblox look: classic clothes map onto the R15 body, robots' recipes and Roblox hair", function()
	local ClothesMap = require("../src/shared/ClothesMap")
	local W, H = ClothesMap.W, ClothesMap.H
	local parts = { "UpperTorso", "LowerTorso" }
	for _, side in { "Left", "Right" } do
		for _, p in { "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" } do
			table.insert(parts, side .. p)
		end
	end
	for _, part in parts do
		local shown = 0
		for _, face in ClothesMap.FACES do
			local r = ClothesMap.rect(part, face)
			if r then
				shown += 1
				check(
					r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= W and r[2] + r[4] <= H,
					part .. " " .. face .. " inside"
				)
				check(r[3] > 0 and r[4] > 0, part .. " " .. face .. " has area")
				-- the Texture settings put exactly that rectangle on the face
				local fw, fh = 1.6, 2.2
				local su, sv, ou, ov = ClothesMap.texture(r, fw, fh)
				check(
					math.abs(su * r[3] / W - fw) < 1e-6 and math.abs(sv * r[4] / H - fh) < 1e-6,
					"rect fills the face"
				)
				check(
					math.abs(-ou / su * W - r[1]) < 1e-6 and math.abs(-ov / sv * H - r[2]) < 1e-6,
					"rect starts at the corner"
				)
			end
		end
		check(shown >= 4, part .. " shows its four sides")
	end
	check(ClothesMap.rect("Head", "Front") == nil, "the head is skin and the face decal")
	-- the torso's two parts split the torso strip with no gap or overlap; the limbs split theirs
	local ut, lt = ClothesMap.rect("UpperTorso", "Front"), ClothesMap.rect("LowerTorso", "Front")
	check(ut and lt and ut[2] + ut[4] == lt[2] and lt[2] + lt[4] == 74 + 128, "torso split")
	check(
		ut and lt and ut[1] == 231 and lt[1] == 231 + ClothesMap.PANTS_X,
		"upper torso from the shirt, lower from the pants"
	)
	local ul, ua2 = ClothesMap.rect("LeftUpperLeg", "Front"), ClothesMap.rect("LeftUpperArm", "Front")
	check(
		ul and ua2 and ul[1] == ua2[1] + ClothesMap.PANTS_X and ul[2] == ua2[2],
		"legs read the pants' copy of the limb slots"
	)
	local ua, la, ha =
		ClothesMap.rect("RightUpperArm", "Front"),
		ClothesMap.rect("RightLowerArm", "Front"),
		ClothesMap.rect("RightHand", "Front")
	check(
		ua and la and ha and ua[2] + ua[4] == la[2] and la[2] + la[4] == ha[2] and ha[2] + ha[4] == 355 + 128,
		"arm split"
	)
	-- the right limb's outer face sits next to its front on the template (the strip wraps round the limb)
	local rr, rf = ClothesMap.rect("RightUpperArm", "Right"), ClothesMap.rect("RightUpperArm", "Front")
	check(rr and rf and rr[1] + rr[3] + 2 == rf[1], "right arm: R next to F")
	check(
		ClothesMap.rect("RightUpperArm", "Top") ~= nil and ClothesMap.rect("RightLowerArm", "Top") == nil,
		"only the shoulder shows the top"
	)
	check(
		ClothesMap.rect("RightHand", "Bottom") ~= nil and ClothesMap.rect("RightUpperArm", "Bottom") == nil,
		"only the hand shows the bottom"
	)
	-- a lone Shirt or Pants image (citizens, NpcRig.dressPair): no half offset, the 585 px width
	local single = ClothesMap.rect("LeftLowerLeg", "Front", true) :: { number }
	check(single[1] == 308 and ClothesMap.TEMPLATE_W == 585, "a lone Pants image reads its own legs")
	local su1 = ClothesMap.texture(single, 1, 1, 1, ClothesMap.TEMPLATE_W)
	check(math.abs(su1 - 585 / 64) < 1e-9, "a lone image tiles at its own width")
	local tint = Config.Destruction.citizens.clothesTints
	check(#tint.shirts >= 8 and #tint.pants >= 6, "citizens' clothes colours")
	-- every robot recipe names a real robot and only Roblox hairs from the list
	local NL = Config.NpcLooks
	check(
		NL.style == "auto" or NL.style == "roblox" or NL.style == "shell" or NL.style == "plain",
		"a known style"
	)
	check(NL.offsetSign == 1 or NL.offsetSign == -1, "offset sign")
	check(#NL.faceOrder >= 6, "at least six faces, so robots do not repeat")
	for _, fname in NL.faceOrder do
		local f = NL.faces[fname]
		check(f ~= nil and type(f.human) == "number" and type(f.turned) == "number", fname .. " face ids")
	end
	-- every robot kind has its three uniform versions, so no kind is left in the plain look
	check(#NL.versions == 3, "three uniform versions")
	for _, kind in Config.Enemies.order do
		-- (the famous fakes and the twin wear a hero look instead: lore step 4)
		if not Config.Enemies[kind].fake then
			check(NL.robots[kind] ~= nil, kind .. " has a Roblox-look uniform")
		end
	end
	for kind, r in NL.robots do
		check(Config.Enemies[kind] ~= nil and Config.Enemies[kind].typeId ~= nil, kind .. " is a robot")
		for _, v in NL.versions do
			check(type(r.clothes[v]) == "number", kind .. " " .. v .. " clothes id")
			check((NL.versionOdds[v] or 0) >= 1, v .. " has odds")
		end
		check(#r.hair >= 1, kind .. " has hair")
		for _, h in r.hair do
			check(type(NL.hairs[h]) == "number" and NL.hairs[h] > 0, kind .. " hair " .. h .. " is listed")
		end
	end
end)

test("City kit block: textured fronts, street dressing, and the rest of Downtown unchanged", function()
	local K = Config.City.kit
	local layout = CityLayout.downtown(Config.City, Config.World)
	-- the same Downtown without the kit: every building where it was
	local bare = table.clone(Config.City)
	bare.kit = nil
	local plain = CityLayout.downtown(bare, Config.World)
	check(#plain.buildings == #layout.buildings, "same buildings with the kit")
	for i, b in plain.buildings do
		local k = layout.buildings[i]
		check(k.x == b.x and k.z == b.z and k.h == b.h, "building " .. i .. " unchanged")
	end
	check(#plain.props == 0, "no props without the kit")
	local kits, bands, marks, kerbs, blocks = {}, 0, 0, 0, 0
	for _, b in layout.boxes do
		-- a skyscraper's setback tiers wear its body's front too; count each building's body once
		if b.kit and not b.crown then
			check(K.baseMaterial[b.kit] ~= nil and K.studsPerTile[b.kit] ~= nil, b.kit .. " is a kit texture")
			kits[b.kit] = (kits[b.kit] or 0) + 1
		end
		if b.plain then
			check(
				b.kind == "band" and K.baseMaterial[b.plain] ~= nil,
				"only window bands give way to a kit front"
			)
			bands += 1
		end
		if b.kind == "mark" then
			marks += 1
		end
		if b.color == "kerb" and b.kind == "sidewalk" then
			kerbs += 1
		end
		if b.kind == "sidewalk" and b.color == "sidewalk" then
			blocks += 1
		end
	end
	-- 53 blocks of lots (24 in the first Downtown, 9 grown on 2026-11-17, 20 on 2026-11-19) and 2 open squares
	local dressed = blocks + #layout.open
	check(
		kits.Paving == dressed and blocks == 53 and #layout.open == 2 and kits.Asphalt == 1,
		string.format("every block paved, the road textured (%d blocks, %d squares)", blocks, #layout.open)
	)
	local fronts = 0
	for _, name in { "Brick", "Office", "Curtain", "Stone", "Deco", "Panel" } do
		fronts += kits[name] or 0
		check((kits[name] or 0) > 0, name .. " fronts in Downtown")
	end
	check(
		fronts == #layout.buildings,
		string.format("%d textured fronts (every building; the Beacon in panels since pt-ui)", fronts)
	)
	check(
		bands > 0 and marks > 0 and kerbs == 4 * dressed,
		"bands to replace, lane dashes and four kerbs a block"
	)
	-- every street between two blocks gets its dashes once: no two dashes in one place
	local seen, dup = {}, 0
	for _, b in layout.boxes do
		if b.kind == "mark" then
			local key = string.format("%.1f,%.1f", b.cx, b.cz)
			if seen[key] then
				dup += 1
			end
			seen[key] = true
		end
	end
	check(dup == 0, "no doubled lane dashes")
	-- props: each a known prop with its pieces in StreetArt, on a block's sidewalk
	local counts = {}
	for _, pr in layout.props do
		counts[pr.name] = (counts[pr.name] or 0) + 1
		local def = K.props[pr.name]
		check(def ~= nil, pr.name .. " is a kit prop")
		for piece in def.pieces do
			check(Config.StreetArt[pr.name][piece] ~= nil, piece .. " has a mesh size")
		end
		check(math.abs(pr.y - (Config.City.ground.y + 0.9)) < 1e-6, "props stand on the sidewalk")
	end
	check(
		(counts.StreetLamp or 0) >= 8 * dressed and (counts.Planter or 0) >= 4 * dressed,
		"lamps and trees line every block"
	)
	check(
		counts.TrafficLight == 2 * dressed and (counts.Hydrant or 0) == 4 * dressed,
		"lights on two corners, a hydrant a side"
	)
	check(
		(counts.BusStop or 0) > 0 and (counts.BikeRack or 0) > 0 and (counts.Bench or 0) > blocks,
		"the sides vary: bus stops, bike racks, benches"
	)
	check(layout.parts <= Config.City.partBudget.downtown, "still within the Downtown part budget")
end); -- Hero MMO features (H1 to H8) live in their own file so this one merges easily
(require :: any)("./mmo")({ test = test, check = check, near = near, Config = Config }); -- WP1: the daily login streak and daily quests
(require :: any)("./daily")({ test = test, check = check, Config = Config }); -- WP6: robot combat depth
(require :: any)("./robots")({ test = test, check = check, near = near, Config = Config });
-- WP4 and WP5 (the gap check's funnel, favorite, rematch and Suspicious Hero) live in their own file too
(require :: any)("./hooks")({ test = test, check = check, near = near, Config = Config });
-- Overnight item 6: the analytics and funnels audit (own file, merges easily)
(require :: any)("./analytics_audit")({ test = test, check = check, Config = Config }); -- the Rogues File and the Journal's Badge Book, Mentor and Showdown tabs (own file, merges easily)
(require :: any)("./rogues_test")({ test = test, check = check, Config = Config, placePath = process.args[1] });
(require :: any)("./comic_art_test")({ test = test, check = check, Config = Config });
(require :: any)("./hairfit_test")({ test = test, check = check, Config = Config }); -- the hair fit pass: explicit catalog picks
(require :: any)("./fit_test")({ test = test, check = check, Config = Config }); -- pt-fit: pieces and weapons on Roblox's own body
(require :: any)("./flow_test")({ test = test, check = check, Config = Config, place = process.args[1] }); -- fix-flow
-- WP10: the group-join piece and creator codes (own file, merges easily)
(require :: any)("./promo_test")({ test = test, check = check, Config = Config, placePath = process.args[1] }); -- WP11: story acts (Act 1 today, Acts 2 and 3 coming soon), own file
(require :: any)("./acts_test")({ test = test, check = check, Config = Config, placePath = process.args[1] }); -- WP8: live tuning from Balance_v<N> (own file, merges easily)
(require :: any)("./balance_test")({ test = test, check = check, Config = Config });
-- WP9: the HQ's WANTED poster and nemesis heads (own file, merges easily)
(require :: any)("./wanted_test")({ test = test, check = check, Config = Config });
-- Overnight queue item 5: the underwater, vehicles, citizens and travel audit (own file, merges easily)
(require :: any)("./travel_test")({ test = test, check = check, Config = Config, world = world });
(require :: any)("./pockets_test")({ test = test, check = check, Config = Config }); -- the pocket kit pass (2026-11-19)
(require :: any)("./gap_review_test")({ test = test, check = check, Config = Config }); -- the gap review (2026-11-19)
-- WP12: visit a friend's HQ on the same server (own file, merges easily)
(require :: any)("./visit_test")({ test = test, check = check, Config = Config, placePath = process.args[1] })

test(
	"City kit: every district dressed, deterministic, within budget, nothing in buildings or roads",
	function()
		local fs = require("@lune/fs")
		local Districts = require("../src/shared/Districts")
		local CityKit = require("../src/shared/CityKit")
		local K = Config.City.kit
		local C = Config.City
		local gy = C.ground.y
		local seed = 202647
		local a = WorldMap.build(Config, seed)
		local b = WorldMap.build(Config, seed, { props = true })
		-- deterministic: the same props in the same order (a device builds the same list as the tests)
		local same = #a.props == #b.props
		for i, p in a.props do
			local q = b.props[i]
			if
				not (
					q
					and q.name == p.name
					and q.x == p.x
					and q.y == p.y
					and q.z == p.z
					and q.ry == p.ry
					and q.d == p.d
				)
			then
				same = false
			end
		end
		check(same and #a.props > 5000, string.format("same seed, same %d props", #a.props))

		-- the kit changes no random draw: without it the world is the same, box for box
		local bareCfg = table.clone(Config)
		bareCfg.City = table.clone(Config.City)
		bareCfg.City.kit = nil
		local p0 = WorldMap.build(bareCfg, seed)
		check(p0.hash == a.hash and #p0.props == 0, "same tile hash, no props without the kit")
		local bOk = #p0.buildings == #a.buildings
		for i, x in p0.buildings do
			local y = a.buildings[i]
			bOk = bOk and y.x == x.x and y.z == x.z and y.sx == x.sx and y.base == x.base and y.top == x.top
		end
		check(bOk, "the same wreckable buildings, ids and sizes")
		local FIELDS =
			{ "kind", "cx", "cy", "cz", "sx", "sy", "sz", "color", "shape", "ry", "grp", "bid", "tag", "ref" }
		local function sameBoxes(x: { any }, y: { any }, what: string)
			local ys = {}
			for _, bx in y do
				if not bx.dress then
					table.insert(ys, bx)
				end
			end
			local ok = #x == #ys
			for i, bx in x do
				local by = ys[i]
				if not by then
					ok = false
					break
				end
				for _, f in FIELDS do
					if bx[f] ~= by[f] then
						ok = false
					end
				end
			end
			check(ok, what .. ": every box as before (the kit only adds kerbs, lines and cornices)")
		end
		sameBoxes(p0.hubBoxes, a.hubBoxes, "hub")
		sameBoxes(p0.baseBoxes, a.baseBoxes, "base")
		local plansOk = #p0.tilePlans == #a.tilePlans
		for i, plan in p0.tilePlans do
			local other = a.tilePlans[i]
			if not other or #other.boxes ~= #plan.boxes then
				plansOk = false
			else
				for k, bx in plan.boxes do
					for _, f in FIELDS do
						if other.boxes[k][f] ~= bx[f] then
							plansOk = false
						end
					end
				end
			end
		end
		check(plansOk, "outskirts tiles: every box as before")

		-- every kit texture has its files, a base material and a tile size; every tint is a palette colour
		local used = {}
		local function scanKit(list: { any })
			for _, bx in list do
				if bx.kit then
					used[bx.kit] = true
				end
				if bx.tint then
					check(C.palette[bx.tint] ~= nil, bx.tint .. " is a palette colour")
					check(K.tinted[bx.kit] ~= nil, bx.kit .. " is a tinted texture")
				end
				if bx.plain then
					check(bx.kind == "band", "only window bands are plain")
				end
			end
		end
		scanKit(a.hubBoxes)
		scanKit(a.baseBoxes)
		for _, plan in a.tilePlans do
			scanKit(plan.boxes)
		end
		for name in K.baseMaterial do
			-- (the pockets' own textures dress the pockets, not the city: tests/pockets_test.luau)
			check(
				used[name] == true
					or table.find(Config.PocketKit.textures, name) ~= nil
					or (K.landmark and K.landmark[name]) == true,
				name .. " is used somewhere in the city"
			)
			check(K.studsPerTile[name] ~= nil, name .. " has a tile size")
			for _, map in { "Color", "Normal", "Roughness" } do
				check(
					fs.isFile("art/export/city/" .. name .. "_" .. map .. ".png"),
					name .. "_" .. map .. ".png exists"
				)
			end
		end
		for name in used do
			check(K.baseMaterial[name] ~= nil, name .. " has a base material")
		end
		for _, list in K.tinted do
			if type(list) == "table" then
				for _, key in list do
					check(C.palette[key] ~= nil, key .. " tint is in the palette")
				end
			end
		end

		-- budgets per district: props, their mesh parts, and the server-built dressing boxes
		local per = {}
		for _, p in a.props do
			local def = K.props[p.name]
			check(
				def ~= nil and def.tier >= 1 and def.tier <= 3 and #def.foot == 3,
				p.name .. " is a kit prop"
			)
			for piece in def.pieces do
				check(
					Config.StreetArt[p.name] ~= nil and Config.StreetArt[p.name][piece] ~= nil,
					piece .. " has a mesh"
				)
			end
			local d = per[p.d] or { props = 0, parts = 0, boxes = 0, tier1 = 0 }
			per[p.d] = d
			d.props += 1
			d.parts += CityKit.parts(K, p.name)
			if def.tier == 1 then
				d.tier1 += CityKit.parts(K, p.name)
			end
		end
		local function districtOf(x: number, z: number): string
			for name, r in C.districts do
				if x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ then
					return name
				end
			end
			return "Hub"
		end
		for _, bx in a.hubBoxes do
			if bx.dress then
				local d = per[districtOf(bx.cx, bx.cz)]
				d.boxes += 1
			end
		end
		local lines = {}
		for _, name in { "Downtown", "Uptown", "Docks", "OldTown", "Hub", "Outskirts" } do
			local d = per[name]
			local cap = K.budget[name]
			check(d ~= nil and d.props > 0, name .. " has props")
			if d then
				check(
					d.props <= cap.props and d.parts <= cap.parts and d.boxes <= cap.boxes,
					string.format(
						"%s within budget: %d props, %d parts, %d boxes",
						name,
						d.props,
						d.parts,
						d.boxes
					)
				)
				check(d.tier1 < d.parts, name .. ": a phone (tier 1) builds fewer")
				table.insert(lines, string.format("%s %d/%d/%d", name, d.props, d.parts, d.boxes))
			end
		end
		print("  city kit (props/parts/boxes): " .. table.concat(lines, ", "))
		-- device presets: phones get the fewest, nearest first
		local P = Config.Presets
		for i, name in P.order do
			local pr = P[name].props
			check(pr ~= nil and pr.tier == i, name .. " builds props up to tier " .. i)
			if i > 1 then
				local lo = P[P.order[i - 1]].props
				check(
					pr.radius > lo.radius and pr.parts > lo.parts,
					name .. " builds more than " .. P.order[i - 1]
				)
			end
		end
		check(C.partBudget.downtown >= a.downtown.parts, "Downtown within its part budget")
		local docks = Districts.docks(C, {})
		local old = Districts.oldTown(C, {})
		check(
			docks.parts <= C.partBudget.docks and old.parts <= C.partBudget.oldTown,
			"Docks and Old Town part budgets"
		)

		-- placement: no ground prop inside anything solid (buildings, walls, props, trees, terminals, water),
		-- a parked vehicle, the harbour or another prop; independent of the layout's own check
		local cell = 20
		local grid = {}
		local function addRect(r: any, what: string)
			for ix = math.floor(r.x0 / cell), math.floor(r.x1 / cell) do
				for iz = math.floor(r.z0 / cell), math.floor(r.z1 / cell) do
					local k = ix * 100000 + iz
					grid[k] = grid[k] or {}
					table.insert(grid[k], { r = r, what = what })
				end
			end
		end
		local function hit(r: any): string?
			for ix = math.floor(r.x0 / cell), math.floor(r.x1 / cell) do
				for iz = math.floor(r.z0 / cell), math.floor(r.z1 / cell) do
					for _, o in grid[ix * 100000 + iz] or {} do
						local q = o.r
						if
							r.x0 < q.x1 - 1e-6
							and q.x0 < r.x1 - 1e-6
							and r.z0 < q.z1 - 1e-6
							and q.z0 < r.z1 - 1e-6
						then
							return o.what
						end
					end
				end
			end
			return nil
		end
		local SOLIDS = {
			building = true,
			prop = true,
			roof = true,
			ledge = true,
			beacon = true,
			terminal = true,
			water = true,
		}
		local function addSolids(list: { any })
			for _, bx in list do
				local bottom, top = bx.cy - bx.sy / 2, bx.cy + bx.sy / 2
				if SOLIDS[bx.kind] and bottom < gy + 7 and top > gy + 0.5 and bx.sx < 400 and bx.sz < 400 then
					local fx, fz = BoxKit.footprint(bx)
					addRect(
						{ x0 = bx.cx - fx / 2, z0 = bx.cz - fz / 2, x1 = bx.cx + fx / 2, z1 = bx.cz + fz / 2 },
						bx.kind
					)
				end
			end
		end
		addSolids(a.hubBoxes)
		for _, plan in a.tilePlans do
			addSolids(plan.boxes)
		end
		for _, v in Vehicles.place(Config) do
			local fx, fz = v.sx, v.sz
			if v.ry % 180 == 90 then
				fx, fz = fz, fx
			end
			addRect({ x0 = v.x - fx / 2, z0 = v.z - fz / 2, x1 = v.x + fx / 2, z1 = v.z + fz / 2 }, "vehicle")
		end
		local bs = C.docks.basin
		addRect({ x0 = bs.minX, z0 = bs.minZ, x1 = bs.maxX, z1 = bs.maxZ }, "harbour")
		local lane = C.docks.lane
		addRect({ x0 = lane.minX, z0 = lane.minZ, x1 = lane.maxX, z1 = lane.maxZ }, "truck lane")
		-- the roads where cars drive: Downtown's and Old Town's streets (everything off a block), the outskirts
		-- road strips and the filler tiles' street ring
		local function blockRects(r: any, block: number, street: number): { any }
			local out = {}
			local pitch = block + street
			for bx = 1, math.floor((r.maxX - r.minX) / pitch) do
				for bz = 1, math.floor((r.maxZ - r.minZ) / pitch) do
					local x0 = r.minX + street / 2 + (bx - 1) * pitch
					local z0 = r.minZ + street / 2 + (bz - 1) * pitch
					table.insert(out, { x0 = x0, z0 = z0, x1 = x0 + block, z1 = z0 + block })
				end
			end
			return out
		end
		local onBlock = {
			Downtown = blockRects(C.districts.Downtown, C.downtown.block, C.downtown.street),
			Uptown = blockRects(C.districts.Uptown, C.uptown.block, C.uptown.street),
			OldTown = blockRects(C.districts.OldTown, C.oldTown.block, C.oldTown.street),
		}
		do -- Clock Square spans its 2 x 2 blocks and the streets between them (no cars there)
			local o, ot = C.districts.OldTown, C.oldTown
			local x0 = o.minX + ot.street / 2 + (ot.square[1] - 1) * (ot.block + ot.street)
			local z0 = o.minZ + ot.street / 2 + (ot.square[1] - 1) * (ot.block + ot.street)
			local size = 2 * ot.block + ot.street
			table.insert(onBlock.OldTown, { x0 = x0, z0 = z0, x1 = x0 + size, z1 = z0 + size })
		end
		local function within(r: any, list: { any }): boolean
			for _, q in list do
				if
					r.x0 >= q.x0 - 1e-6
					and r.x1 <= q.x1 + 1e-6
					and r.z0 >= q.z0 - 1e-6
					and r.z1 <= q.z1 + 1e-6
				then
					return true
				end
			end
			return false
		end
		local roads = {}
		for _, bx in a.baseBoxes do
			if bx.kind == "road" then
				table.insert(roads, {
					x0 = bx.cx - bx.sx / 2,
					z0 = bx.cz - bx.sz / 2,
					x1 = bx.cx + bx.sx / 2,
					z1 = bx.cz + bx.sz / 2,
				})
			end
		end
		local bad: { [string]: number } = {}
		local function fail(why: string)
			bad[why] = (bad[why] or 0) + 1
		end
		local stacked = 0
		local hubFill = C.hubFill.street
		for _, p in a.props do
			local r = CityKit.footprint(K, p)
			local ground = p.y <= gy + 1
			if not ground then
				-- only crates stack, square on a crate below
				local under = false
				for _, q in a.props do
					if
						q ~= p
						and q.name == "Crate"
						and q.x == p.x
						and q.z == p.z
						and math.abs(q.y + 3 - p.y) < 1e-6
					then
						under = true
					end
				end
				if not (p.name == "Crate" and under) then
					fail("a raised prop not on a crate")
				end
				stacked += 1
				continue
			end
			local what = hit(r)
			if what then
				fail(p.d .. " " .. p.name .. " in a " .. what)
			end
			if p.d == "Downtown" or p.d == "OldTown" or p.d == "Uptown" then
				if not within(r, onBlock[p.d]) then
					fail(p.d .. " " .. p.name .. " in the street")
				end
			elseif p.d == "Hub" or p.d == "Outskirts" then
				for _, q in roads do
					if r.x0 < q.x1 and q.x0 < r.x1 and r.z0 < q.z1 and q.z0 < r.z1 then
						fail(p.d .. " " .. p.name .. " on a road")
						break
					end
				end
				if p.d == "Hub" then
					local tx, tz = WorldGen.tileOf(C, p.x, p.z)
					local x0, z0 = WorldGen.tileOrigin(C, tx, tz)
					local inner = {
						{
							x0 = x0 + hubFill,
							z0 = z0 + hubFill,
							x1 = x0 + C.tile - hubFill,
							z1 = z0 + C.tile - hubFill,
						},
					}
					if not within(r, inner) then
						fail("Hub " .. p.name .. " in the filler street")
					end
				end
			end
			addRect(r, "prop " .. p.name)
		end
		local msgs = {}
		for why, n in bad do
			table.insert(msgs, why .. " x" .. n)
		end
		table.sort(msgs)
		check(
			#msgs == 0,
			"every prop clear of buildings, roads, water, vehicles and other props: "
				.. table.concat(msgs, "; ")
		)
		check(stacked > 0, "some crates are stacked")

		-- variety: fronts and tints differ along a street
		local frontKinds: { [string]: { [string]: boolean } } = {}
		for _, bx in a.hubBoxes do
			if bx.kind == "building" and bx.kit then
				local d = districtOf(bx.cx, bx.cz)
				frontKinds[d] = frontKinds[d] or {}
				frontKinds[d][bx.kit .. ":" .. (bx.tint or "")] = true
			end
		end
		local function count(t: { [string]: boolean }?): number
			local n = 0
			for _ in t or {} do
				n += 1
			end
			return n
		end
		check(count(frontKinds.Downtown) >= 6, "Downtown has at least 6 fronts")
		check(count(frontKinds.OldTown) >= 8, "Old Town has at least 8 front and colour mixes")
		check(count(frontKinds.Docks) >= 3, "the Docks have at least 3 fronts")
		check(count(frontKinds.Uptown) >= 8, "Uptown has at least 8 front and colour mixes")
		local own, all = 0, 0
		for _, bx in a.hubBoxes do
			if bx.kind == "building" and bx.kit and districtOf(bx.cx, bx.cz) == "Uptown" then
				all += 1
				if bx.kit == "Ribbon" or bx.kit == "Prism" then
					own += 1
				end
			end
		end
		check(
			all > 0 and own >= all * 0.7,
			"Uptown wears mostly its own fronts (Ribbon, Prism), not Downtown's"
		)
		local houses = {}
		for _, plan in a.tilePlans do
			for _, bx in plan.boxes do
				if bx.kind == "building" and bx.kit then
					houses[bx.kit .. ":" .. (bx.tint or "")] = true
				end
			end
		end
		check(count(houses) >= 8, "the outskirts have at least 8 front and colour mixes")
		for _, name in { "Downtown", "Uptown", "Docks", "OldTown", "Hub", "Outskirts" } do
			local kinds = {}
			for _, p in a.props do
				if p.d == name then
					kinds[p.name] = true
				end
			end
			check(count(kinds) >= 3, name .. " has at least 3 kinds of prop")
		end
	end
)

test(
	"Bigger Downtown and Uptown: the first Downtown unchanged, nothing overlaps, everything reachable",
	function()
		local IncidentSpots = require("../src/shared/IncidentSpots")
		local C = Config.City
		local gy = C.ground.y
		local seed = 202647
		local wd = world -- WorldMap.build(Config, 202647) above
		local t = C.downtown
		local core = t.core
		local pitch = t.block + t.street

		-- the size is config: the district is the core grown by whole blocks, and the core is the first 700 x 700
		local d = C.districts.Downtown
		check(
			d.minX == core.minX - t.grow.west * pitch
				and d.maxX == core.maxX + t.grow.east * pitch
				and d.minZ == core.minZ - t.grow.north * pitch
				and d.maxZ == core.maxZ + t.grow.south * pitch,
			"Downtown is its core grown by whole blocks"
		)
		check(
			core.maxX - core.minX == 700 and core.maxZ - core.minZ == 700,
			"the core is the first 700 x 700"
		)
		check((d.maxX - d.minX) * (d.maxZ - d.minZ) >= 1.3 * 700 * 700, "Downtown is at least 1.3x as big")

		-- the core is built exactly as before growing: same buildings, safehouse lots and Beacon Tower
		local small = table.clone(C)
		small.districts = table.clone(C.districts)
		small.districts.Downtown = table.clone(core)
		small.downtown = table.clone(t)
		small.downtown.grow = { north = 0, south = 0, west = 0, east = 0 }
		small.downtown.open = {}
		local before = CityLayout.downtown(small, W)
		local after = CityLayout.downtown(C, W)
		local same = true
		for i, b in before.buildings do
			local k = after.buildings[i]
			if not (k and k.x == b.x and k.z == b.z and k.h == b.h and k.sx == b.sx and k.grp == b.grp) then
				same = false
			end
			if k and k.grown then
				same = false
			end
		end
		check(same, string.format("the first %d Downtown buildings are where they were", #before.buildings))
		check(
			after.beacon.x == before.beacon.x and after.beacon.z == before.beacon.z,
			"the Beacon Tower and the plaza did not move"
		)
		for id, s in before.safehouseSpots do
			local s2 = after.safehouseSpots[id]
			check(s2 ~= nil and s2.x == s.x and s2.z == s.z, "safehouse " .. id .. " keeps its lot")
		end
		local grown = 0
		for _, b in after.buildings do
			if b.grown then
				grown += 1
			end
		end
		local newBlocks = ((d.maxX - d.minX) / pitch) * ((d.maxZ - d.minZ) / pitch) - 25
		check(
			grown == 4 * (newBlocks - #t.open),
			string.format("%d buildings in %d new blocks (%d kept open)", grown, newBlocks, #t.open)
		)
		-- the same twice (deterministic)
		local again = CityLayout.downtown(C, W)
		local up1, up2 = CityLayout.uptown(C), CityLayout.uptown(C)
		local twice = #again.boxes == #after.boxes and #up1.boxes == #up2.boxes
		for i, b in up1.boxes do
			local q = up2.boxes[i]
			twice = twice
				and q.cx == b.cx
				and q.cy == b.cy
				and q.cz == b.cz
				and q.sy == b.sy
				and q.color == b.color
		end
		check(twice, "Downtown and Uptown build the same twice")

		-- wreckable ids: the first 220 as before, then the grown Downtown blocks and Uptown
		local Districts = require("../src/shared/Districts")
		local clear = {}
		for _, s in wd.safehouses do
			table.insert(clear, { x = s.x, z = s.z, r = W.safehouse.pad * 0.75 })
		end
		local first = WorldMap.pickBuildings(
			Config,
			CityLayout.downtown(small, W),
			Districts.docks(C, clear),
			Districts.oldTown(C, clear)
		)
		local idsOk = #first == Config.Destruction.hubBuildings
		for i, b in first do
			local k = wd.buildings[i]
			idsOk = idsOk
				and k ~= nil
				and k.x == b.x
				and k.z == b.z
				and k.top == b.top
				and k.district == b.district
		end
		check(idsOk, "the first 220 wreckable buildings keep their ids")
		local up = wd.uptown
		-- then the 2026-11-19 additions (the rest of Old Town, the outskirts: b.more; tests/impact_test)
		local more = 0
		for _, b in wd.buildings do
			more += if b.more then 1 else 0
		end
		check(
			#wd.buildings == Config.Destruction.hubBuildings + grown + #up.buildings + more,
			string.format(
				"%d wreckable: 220 + %d grown Downtown + %d Uptown + %d more",
				#wd.buildings,
				grown,
				#up.buildings,
				more
			)
		)
		for i = Config.Destruction.hubBuildings + 1, #wd.buildings do
			local b = wd.buildings[i]
			check(
				b.id == i
					and (
						b.district == "Downtown"
						or b.district == "Uptown"
						or (
							b.more == true
							and (b.district == "OldTown" or b.district == "Outskirts" or b.district == "Hub")
						)
					),
				"new wreckable " .. i
			)
		end

		-- districts never overlap each other, the outskirts safehouses, landmarks or the beacons outside them
		local names = {}
		for name in C.districts do
			table.insert(names, name)
		end
		for i, an in names do
			for j = i + 1, #names do
				local ra, rb = C.districts[an], C.districts[names[j]]
				check(
					ra.maxX <= rb.minX or rb.maxX <= ra.minX or ra.maxZ <= rb.minZ or rb.maxZ <= ra.minZ,
					an .. " and " .. names[j] .. " do not overlap"
				)
			end
		end
		local u = C.districts.Uptown
		local half = C.mapSize / 2
		check(u.maxX - u.minX >= 600 and u.maxZ - u.minZ >= 600, "Uptown is at least 600 x 600")
		check(
			u.minX > -half + 2 * C.tile and u.maxZ < half - 2 * C.tile,
			"Uptown is on the map, clear of the coast"
		)
		check(
			u.maxZ <= C.hub.min or u.minZ >= C.hub.max or u.maxX <= C.hub.min or u.minX >= C.hub.max,
			"Uptown is out of the hub"
		)
		local function inside(r: any, x: number, z: number, pad: number): boolean
			return x > r.minX - pad and x < r.maxX + pad and z > r.minZ - pad and z < r.maxZ + pad
		end
		for _, s in wd.safehouses do
			for name, r in C.districts do
				if s.district ~= name and s.district ~= "Downtown" then
					check(not inside(r, s.x, s.z, W.safehouse.pad / 2), s.name .. " is not in " .. name)
				end
			end
		end
		for _, lm in wd.landmarks do
			for name, r in C.districts do
				local s = lm.size / 2
				check(not inside(r, lm.centre.x, lm.centre.z, s), lm.id .. " is clear of " .. name)
			end
		end
		-- Uptown's tiles are fixed (no roads, nothing seeded built in it); the rest of the outskirts as before
		local noUp = table.clone(Config)
		noUp.City = table.clone(C)
		noUp.City.districts = table.clone(C.districts)
		noUp.City.districts.Uptown = nil
		local tilesA = WorldGen.tiles(C, W, seed)
		local tilesB = WorldGen.tiles(noUp.City, W, seed)
		local tilesOk, upTiles = true, 0
		for tz = 0, W.tiles - 1 do
			for tx = 0, W.tiles - 1 do
				local x0, z0 = WorldGen.tileOrigin(C, tx, tz)
				local touch = x0 < u.maxX and x0 + C.tile > u.minX and z0 < u.maxZ and z0 + C.tile > u.minZ
				local ta, tb = WorldGen.get(W, tilesA, tx, tz), WorldGen.get(W, tilesB, tx, tz)
				if touch then
					upTiles += 1
					tilesOk = tilesOk and ta.zone == W.zones.hub and not ta.roadNS and not ta.roadEW
				else
					tilesOk = tilesOk
						and ta.zone == tb.zone
						and ta.variant == tb.variant
						and ta.rot == tb.rot
						and ta.roadNS == tb.roadNS
						and ta.roadEW == tb.roadEW
				end
			end
		end
		-- 750 x 750 from x -850 (half a tile in) to the tile edge at -100: 8 x 8 tiles (6 x 6 until 2026-11-19)
		check(
			tilesOk and upTiles == 64,
			string.format("Uptown's %d tiles are fixed, every other tile as before", upTiles)
		)
		local intruders = 0
		for _, plan in wd.tilePlans do
			for _, b in plan.boxes do
				for _, r in C.districts do
					if inside(r, b.cx, b.cz, -0.5) and b.kind ~= "road" then
						intruders += 1
					end
				end
			end
		end
		for _, b in wd.baseBoxes do
			if b.kind == "road" then
				local x0, x1 = b.cx - b.sx / 2, b.cx + b.sx / 2
				local z0, z1 = b.cz - b.sz / 2, b.cz + b.sz / 2
				if x0 < u.maxX and x1 > u.minX and z0 < u.maxZ and z1 > u.minZ then
					intruders += 1
				end
			end
		end
		check(intruders == 0, string.format("no tile, house or road built inside a district (%d)", intruders))

		-- every Downtown and Uptown building stands in its district, no two overlap
		local function overlaps(list: { any }): number
			local n = 0
			for i, a in list do
				for j = i + 1, #list do
					local b = list[j]
					if
						math.abs(a.x - b.x) < (a.sx + b.sx) / 2
						and math.abs(a.z - b.z) < (a.sz + b.sz) / 2
					then
						n += 1
					end
				end
			end
			return n
		end
		for _, b in after.buildings do
			check(inside(d, b.x, b.z, -b.sx / 2), "a Downtown building is in Downtown")
		end
		for _, b in up.buildings do
			check(inside(u, b.x, b.z, -b.sx / 2), "an Uptown building is in Uptown")
		end
		check(overlaps(after.buildings) == 0 and overlaps(up.buildings) == 0, "no two buildings overlap")
		check(
			up.parts <= C.partBudget.uptown and after.parts <= C.partBudget.downtown,
			string.format("part budgets: Downtown %d, Uptown %d", after.parts, up.parts)
		)

		-- the open squares and Uptown's green: open ground, nothing built on them, streets all round
		check(#wd.open == #t.open and #wd.open >= 2, "the open squares are in the world")
		local function clearSquare(x: number, z: number, size: number, what: string)
			local blocked = 0
			for _, b in wd.hubBoxes do
				if
					(b.kind == "building" or b.kind == "roof")
					and math.abs(b.cx - x) < size / 2
					and math.abs(b.cz - z) < size / 2
				then
					blocked += 1
				end
			end
			check(blocked == 0, what .. ": nothing built on it")
			for _, o in { { 0, 0 }, { -0.3, -0.3 }, { 0.3, 0.3 }, { -0.3, 0.3 } } do
				local h = WorldMap.heightAt(wd, x + o[1] * size, z + o[2] * size)
				check(h <= gy + 1.5, string.format("%s: open ground (%.1f)", what, h))
			end
			for _, s in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local h = WorldMap.heightAt(wd, x + s[1] * (size / 2 + 8), z + s[2] * (size / 2 + 8))
				check(h <= gy + 1.5, what .. ": a street on each side")
			end
		end
		for _, o in wd.open do
			check(inside(d, o.x, o.z, -o.size / 2), o.id .. " is in Downtown")
			clearSquare(o.x, o.z, o.size - 30, o.id)
		end
		local f = C.uptown.fountain
		local pk = up.park
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			for _, r in { f.radius + 10, pk.size / 2 - 4 } do
				local h = WorldMap.heightAt(wd, pk.x + o[1] * r, pk.z + o[2] * r)
				check(h <= gy + 1.5, string.format("Uptown's green: its paths are open ground (%.1f)", h))
			end
		end
		check(
			WorldMap.heightAt(wd, pk.x, pk.z) <= gy + 1 + f.height + 0.5,
			"the fountain is low enough to stand on its rim"
		)

		-- reachable: each Uptown and grown Downtown building has a street beside it, and incidents find spots
		local streets = 0
		for _, b in up.buildings do
			local ok = false
			for _, s in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local px = b.x + s[1] * (b.sx / 2 + 14)
				local pz = b.z + s[2] * (b.sz / 2 + 14)
				if WorldMap.heightAt(wd, px, pz) <= gy + 1.5 then
					ok = true
				end
			end
			if ok then
				streets += 1
			end
		end
		check(streets == #up.buildings, "every Uptown building has open ground beside it")
		local rng = Rng.new(5)
		local kinds = IncidentSpots.kinds(Config, wd, pk.x, pk.z, 250)
		check(
			kinds.street and kinds.tower and kinds.sign and kinds.roof,
			"Uptown has street, tower, sign and roof spots"
		)
		local spot = IncidentSpots.find(Config, wd, "tower", pk.x, pk.z, 0, 250, rng)
		check(spot ~= nil and wd.buildings[spot.building].district == "Uptown", "a tower spot in Uptown")
		local st = IncidentSpots.find(Config, wd, "street", pk.x, pk.z, 20, 200, rng)
		check(st ~= nil and inside(u, st.x, st.z, 0), "a street spot in Uptown")
		local o1 = wd.open[1]
		check(
			IncidentSpots.find(Config, wd, "street", o1.x, o1.z, 0, 60, rng) ~= nil,
			"a street spot at a square"
		)
		-- zone levels: Uptown at the suburbs' floor, the grown Downtown in the hub's
		check(ZoneLevel.area(Config, pk.x, pk.z, wd.tiles) == "Uptown", "Uptown is its own area")
		check(ZoneLevel.at(Config, pk.x, pk.z, 1, wd.tiles) == W.zoneFloor.Uptown, "Uptown's floor")
		check(ZoneLevel.area(Config, o1.x, o1.z, wd.tiles) == "hub", "the grown Downtown is the hub")
		-- the beacons and the Beacon Tower roof are unchanged in number and stay under the ceiling
		local tallest = 0
		for _, b in up.boxes do
			tallest = math.max(tallest, b.cy + b.sy / 2)
		end
		check(tallest < Config.Move.ceiling.soft, "Uptown is under the flight ceiling")
		print(
			string.format(
				"  bigger city: Downtown %d buildings (%d new), %d parts; Uptown %d buildings, %d parts; hub boxes %d",
				#after.buildings,
				grown,
				after.parts,
				#up.buildings,
				up.parts,
				#wd.hubBoxes
			)
		)
	end
)

test(
	"Skyscrapers: towers of 400 to 600, an 820 landmark, under the ceiling, destructible, within budget",
	function()
		local Structure = require("../src/shared/Structure")
		local C = Config.City
		local D = Config.Destruction
		local M = Config.Move
		local gy = C.ground.y
		local wd = world
		local t, u = C.downtown, C.uptown
		-- heights: towers 400 to 600 (Uptown 380 to 560) to the top of their crowns, varied silhouettes
		local towers = { Downtown = 0, Uptown = 0 }
		local styles = {}
		local corePeak = 0
		local core = t.core
		for _, b in wd.buildings do
			local peak = b.peak or b.top
			local h = peak - b.base
			if b.district == "Downtown" or b.district == "Uptown" then
				local cfg = if b.district == "Downtown" then t.height else u.height
				if h >= cfg.towerMin - 1 and b.crown ~= "landmark" then
					towers[b.district] += 1
					check(
						h <= cfg.towerMax + 1,
						string.format("a %s tower at most %d (%.0f)", b.district, cfg.towerMax, h)
					)
				end
				if b.crown then
					styles[b.crown] = true
				end
				if
					b.district == "Downtown"
					and b.x > core.minX
					and b.x < core.maxX
					and b.z > core.minZ
					and b.z < core.maxZ
				then
					corePeak = math.max(corePeak, peak)
				end
			end
		end
		check(
			towers.Downtown >= 15 and towers.Uptown >= 8,
			string.format("a skyline: %d Downtown and %d Uptown towers", towers.Downtown, towers.Uptown)
		)
		local n = 0
		for _ in styles do
			n += 1
		end
		check(n >= 5, string.format("%d tower silhouettes (setback, spire, crown, mast, landmark)", n))
		local bt = wd.downtown.beacon
		check(
			gy + 1 + bt.h > corePeak,
			string.format("the Beacon Tower (%d) is the first Downtown's tallest (%.0f)", bt.h, corePeak)
		)
		local lm = wd.uptown.landmark
		local tallest = 0
		for _, b in wd.hubBoxes do
			tallest = math.max(tallest, b.cy + b.sy / 2)
		end
		check(
			math.abs(lm.peak - (gy + 0.9 + u.landmark.height)) < 1 and u.landmark.height >= 780,
			"the landmark is about 800 studs"
		)
		check(
			math.abs(tallest - lm.peak) < 1,
			string.format("the landmark is the tallest thing in the city (%.0f)", tallest)
		)
		-- ceiling clearance: every roof and spire under the soft ceiling with room to fly over, the clouds above
		check(
			tallest + 60 <= M.ceiling.soft,
			string.format(
				"60 studs of sky over the tallest spire (%.0f, ceiling %d)",
				tallest,
				M.ceiling.soft
			)
		)
		check(
			C.ceilingCloudY > tallest and C.ceilingCloudY < M.ceiling.soft and M.ceiling.soft < M.ceiling.hard,
			"clouds over the spires, under the ceiling"
		)
		for _, plan in wd.tilePlans do
			for _, b in plan.boxes do
				tallest = math.max(tallest, b.cy + b.sy / 2)
			end
		end
		check(tallest + 60 <= M.ceiling.soft, "the outskirts too")
		-- destructible: the shaft is the wreck box; every building's pieces fit the 256-bit pack, chunks and rubble
		-- stay in their caps, and the crown sits on its own shaft
		local maxPieces, maxStoreyH = 0, 0
		for _, b in wd.buildings do
			local g = Structure.build(D, b)
			maxPieces = math.max(maxPieces, #g.pieces)
			maxStoreyH = math.max(maxStoreyH, g.storeyH)
			check(
				#g.pieces <= 256 and g.storeys <= D.structure.maxStoreys,
				"building " .. b.id .. " fits the piece pack"
			)
			local chunks = Chunker.split(D, b)
			check(
				#chunks >= D.chunks.min and #chunks <= D.chunks.max,
				"building " .. b.id .. " chunks in 10 to 40"
			)
			local rubble = Chunker.rubble(D, b, b.id)
			check(#rubble >= D.rubble.min and #rubble <= D.rubble.max, "building " .. b.id .. " rubble heap")
		end
		local byGrp = {}
		for _, b in wd.buildings do
			byGrp[b.grp] = b
		end
		local crownParts, bad = 0, 0
		local perBuilding = {}
		for _, bx in wd.hubBoxes do
			-- (the street art pieces, pt-city 2026-11-19, have their own cap: tests/city_play_test)
			if bx.grp and not bx.art then
				perBuilding[bx.grp] = (perBuilding[bx.grp] or 0) + 1
			end
			if bx.crown then
				crownParts += 1
				local b = byGrp[bx.grp]
				if
					not b
					or not b.crown
					or bx.cy - bx.sy / 2 < b.top - 1.5
					or math.abs(bx.cx - b.x) > b.sx / 2 + 1
					or math.abs(bx.cz - b.z) > b.sz / 2 + 1
				then
					bad += 1
				end
			end
		end
		check(
			crownParts > 0 and bad == 0,
			string.format("%d crown parts, each on top of its own tower's shaft", crownParts)
		)
		for _, b in wd.buildings do
			if b.crown then
				check(b.peak ~= nil and b.peak > b.top, "a crowned tower's peak is over its shaft")
			end
		end
		-- part budget: no building over 32 parts (window bands thin out high up), the districts in their budgets
		local most = 0
		for _, k in perBuilding do
			most = math.max(most, k)
		end
		check(most <= 32, string.format("at most 32 parts a building (%d)", most))
		check(
			wd.downtown.parts <= C.partBudget.downtown and wd.uptown.parts <= C.partBudget.uptown,
			"district part budgets"
		)
		-- beacons never on a crown; heights see the crowns
		for _, b in wd.beacons do
			for _, w in wd.buildings do
				if w.crown and math.abs(b.x - w.x) < w.sx / 2 and math.abs(b.z - w.z) < w.sz / 2 then
					check(false, b.name .. " is not on a skyscraper's crown")
				end
			end
		end
		check(WorldMap.heightAt(wd, lm.x, lm.z) >= lm.peak - 12, "the heightmap sees the landmark's spire")
		print(
			string.format(
				"  skyline: %d Downtown and %d Uptown towers, Beacon %d, landmark %.0f, %d crown parts, max %d pieces, storeys up to %.0f studs",
				towers.Downtown,
				towers.Uptown,
				bt.h,
				lm.peak,
				crownParts,
				maxPieces,
				maxStoreyH
			)
		)
	end
)

---------------------------------------------------------------------------
-- Lore step 1 (nate's lore, 2026-11-17): the old lore (the Shardfall comet, Null, the League, the Comet
-- Crater) is gone from every player-visible text. The Story content that build plan steps 3 and 5 replace
-- wholesale is excluded below: delete each exclusion when its step lands.
local OLD_LORE = { "Shardfall", "Null", "League", "Comet" }
local LORE_SKIP_CONFIG: { [string]: boolean } = {} -- (step 10 retired the side quests: no exclusions left)
local LORE_SKIP_FILES: { [string]: boolean } = {}

-- The old-lore word in a piece of text, or nil. Whole words as players read them (Title or CAPS), so ids
-- like CometCrater or NullSentinel that never reach the screen pass.
local function oldLore(text: string): string?
	for _, w in OLD_LORE do
		if
			string.find(text, "%f[%w]" .. w .. "%f[%W]")
			or string.find(text, "%f[%w]" .. string.upper(w) .. "%f[%W]")
		then
			return w
		end
	end
	return nil
end

test(
	"Lore step 1: no Shardfall, Null, League or Comet in player-visible text (bar Story steps 3/5)",
	function()
		local hits = {}
		local function walk(v: any, path: string, seen: { [any]: boolean })
			if LORE_SKIP_CONFIG[path] then
				return
			end
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w .. ' in "' .. v .. '"')
				end
			elseif type(v) == "table" and not seen[v] then
				seen[v] = true
				for k, x in v do
					walk(x, path .. "." .. tostring(k), seen)
				end
			end
		end
		for name, mod in Config do
			walk(mod, name, {})
		end
		-- the string literals in every other source file (config is checked as data above; comments stripped)
		local fs = require("@lune/fs")
		local files = 0
		local function look(path: string, lit: string)
			local w = oldLore(lit)
			if w then
				table.insert(hits, path .. ": " .. w .. " in " .. lit)
			end
		end
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif
					string.sub(name, -5) == ".luau"
					and not LORE_SKIP_FILES[path]
					and not string.find(path, "^src/config/")
				then
					files += 1
					local src = string.gsub(fs.readFile(path), "%-%-%[(=*)%[.-%]%1%]", "")
					for line in string.gmatch(src .. "\n", "([^\n]*)\n") do
						line = string.gsub(line, '"[^"]*"', function(lit)
							look(path, lit)
							return '""'
						end)
						local cut = string.find(line, "--", 1, true)
						local code = if cut then string.sub(line, 1, cut - 1) else line
						for lit in string.gmatch(code, "`[^`]*`") do
							look(path, lit)
						end
					end
				end
			end
		end
		scan("src")
		check(files > 100, "the scan read the source files")
		for _, h in hits do
			check(false, "old lore: " .. h)
		end
		-- the scanner itself
		check(
			oldLore("Join the League") == "League" and oldLore("COMET CRATER") == "Comet",
			"the scan finds the words"
		)
		check(oldLore("CometCrater") == nil and oldLore("NullSentinel") == nil, "ids pass")
		-- the renames players read
		local W = Config.World
		check(
			W.landmarks[1].name == "The Crater" and W.safehouses[6].name == "Gantry Yard",
			"The Crater, Gantry Yard"
		)
		check(
			Config.Boss.bosses.NullWarFrame.name == "Bulwark's Battle Form",
			"Bulwark's battle form (lore step 5)"
		)
		check(Config.Story.perks.NullEcho.name == "Echo Drone", "the Echo Drone perk")
	end
)

test("Lore step 1: each robot's display name lives in one place (Config.Enemies.<Kind>.name)", function()
	local fs = require("@lune/fs")
	local E = Config.Enemies
	for _, kind in E.order do
		check(type(E[kind].name) == "string" and #E[kind].name > 0, kind .. " has a display name")
	end
	-- activity text names robots with a "{Kind}" token (Config init fills it in), never by hand
	for _, mod in { "Incidents", "Contracts", "Events", "Deep", "Boss", "World" } do
		local src = fs.readFile("src/config/" .. mod .. ".luau")
		for line in string.gmatch(src .. "\n", "([^\n]*)\n") do
			for lit in string.gmatch(line, '"([^"]*)"') do
				for _, kind in E.order do
					local name = E[kind].name
					local plain = string.gsub(lit, "{%w+}", "")
					if lit ~= kind and lit ~= name and string.find(plain, "%f[%w]" .. name .. "%f[%W]") then
						check(
							false,
							mod .. ': "' .. lit .. '" names ' .. kind .. " by hand: use {" .. kind .. "}"
						)
					end
				end
			end
		end
		local function walk(t: any, seen: { [any]: boolean })
			seen[t] = true
			for _, v in t do
				if type(v) == "string" then
					check(not string.find(v, "{%w+}"), mod .. ": every robot token is filled: " .. v)
				elseif type(v) == "table" and not seen[v] then
					walk(v, seen)
				end
			end
		end
		walk(Config[mod], {})
	end
	check(
		Config.Contracts.types.DroneSweep.text == "Defeat 3 " .. E.SparkDrone.name .. " squads",
		"filled in"
	)
	check(
		Config.Incidents.templates.MedicConvoy.steps[1].text == "Stop the " .. E.MedicUnit.name .. "s",
		"plural"
	)
	check(E.NullSentinel.name == "Warden", "the Null Sentinel is the Warden now")
end)

test("Lore step 1: League rep is Vigil Trust, Syndicate rep is Fear; old saves keep their points", function()
	local StoryPlan = require("../src/shared/StoryPlan")
	local R = Config.Story.rep
	check(
		R.order[1] == "vigil" and R.order[2] == "syndicate" and R.order[3] == "city",
		"vigil, syndicate, city"
	)
	check(R.labels.vigil == "Vigil Trust" and R.labels.syndicate == "Syndicate Fear", "Trust and Fear labels")
	check(StoryPlan.repIndex(Config, "vigil") == 1, "Vigil Trust is the save's first rep slot")
	-- a version 9 save from before the rename: rep is a list in track order, so nothing moves
	local old = ProfileSchema.default()
	old.version = 9
	old.characters[1].rep = { 900, 40, 300 }
	old.characters[2] = ProfileSchema.newCharacter("villain")
	old.characters[2].rep = { 0, 1000, 120 }
	local back = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
	local h, v = back.characters[1], back.characters[2]
	check(back.version == ProfileSchema.VERSION, "loads at the current version")
	check(
		h.rep[1] == 900 and h.rep[2] == 40 and h.rep[3] == 300,
		"a hero's old League points are its Vigil Trust"
	)
	check(StoryPlan.repRank(Config, h.rep[StoryPlan.repIndex(Config, "vigil")]) == 3, "rank 3 Trust")
	check(v.rep[2] == 1000 and StoryPlan.repRank(Config, v.rep[2]) == 4, "a villain's Fear rank 4 intact")
	-- the hero's own-side rep from a choice goes to the Vigil
	local story = ProfileSchema.newCharacter("hero").story
	local _, fx = StoryPlan.pick(Config, story, 1, 2, "hero")
	check(fx.rep[1] == "vigil", "a hero's own-side rep is Vigil Trust")
	-- every creator unlock names a real track
	local unlocks = 0
	local function walk(t: any)
		for _, v in t do
			if type(v) == "string" and string.sub(v, 1, 4) == "rep:" then
				unlocks += 1
				check(
					table.find(R.order, string.match(v, "^rep:(%a+):")) ~= nil,
					"unlock " .. v .. " names a track"
				)
			elseif type(v) == "table" then
				walk(v)
			end
		end
	end
	walk(Config.Creator)
	check(unlocks >= 30, "the rep unlocks were found")
end)

test(
	"Lore step 2: origins are a title and one crest, never a stat; saves v9 load with a default origin",
	function()
		local CreatorRules = require("../src/shared/CreatorRules")
		local C = Config.Creator
		check(#C.origins == 10, "ten origins (five more on 2026-11-18)")
		local want = {
			"Lab accident",
			"Alien blood",
			"Magic relic",
			"Tech suit",
			"Training",
			"Born with it",
			"Strange storm",
			"Strange serum",
			"Spirit bond",
			"Family legacy",
		}
		for i, o in C.origins do
			check(o.name == want[i], "origin " .. i .. " is " .. want[i])
			check(type(o.title) == "string" and o.title ~= "", o.name .. " has a title")
			check(
				type(o.line) == "string" and #o.line > 10 and #o.line <= 80,
				o.name .. " has one short fixed line"
			)
			-- looks only: an origin row holds words, never a number a fight could read
			for k, v in o do
				check(type(v) == "string", o.name .. "." .. k .. " is text, not a stat")
			end
			local crest = CreatorRules.originPiece(Config, i)
			check(crest ~= nil and crest.tab == "emblem", o.name .. " has its crest in the Emblems tab")
			if crest then
				check(C.shapes[string.split(crest.kit, ":")[1]] ~= nil, crest.name .. " has a shape")
			end
		end
		check(CreatorRules.originOk(Config, 1) and CreatorRules.originOk(Config, 10), "1 to 10 are origins")
		check(
			not CreatorRules.originOk(Config, 0) and not CreatorRules.originOk(Config, 11),
			"0 and 11 are not"
		)
		check(C.origins[C.originDefault] ~= nil, "the default origin exists")
		-- the crest: worn free by a hero of that origin, refused for another, unlocked once any hero has it
		local profile = ProfileSchema.default()
		local look = CreatorRules.defaultLook(Config)
		local lab = CreatorRules.originPiece(Config, 1) :: any
		look.pieces.emblem = lab.index
		check(not (CreatorRules.validate(Config, profile, look)), "the Lab crest is locked with no origin")
		check(CreatorRules.validate(Config, profile, look, 1), "a Lab-accident hero may wear it")
		check(not (CreatorRules.validate(Config, profile, look, 2)), "an Alien-blood hero may not")
		profile.characters[1].origin = 1
		local earned = CreatorRules.earned(Config, profile)
		local got = false
		for _, p in earned do
			got = got or p.id == lab.id
		end
		check(got, "a Lab-accident hero earns the Lab crest for the account")
		CreatorRules.grant(profile, lab)
		check(CreatorRules.validate(Config, profile, look, 3), "once unlocked, any hero may wear it")
		-- the save: v10, a new character has no origin yet, an old one gets the default, bad values are fixed
		check(ProfileSchema.VERSION >= 10, "save version 10 or later")
		check(ProfileSchema.newCharacter().origin == 0, "a new character has not picked an origin")
		local old = ProfileSchema.default()
		old.version = 9
		old.characters[1].origin = nil
		old.characters[1].created = 1
		old.characters[1].level = 12
		old.characters[2] = ProfileSchema.newCharacter("villain")
		old.characters[2].origin = nil
		local back = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
		check(back.version == ProfileSchema.VERSION, "a v9 save loads at the current version")
		check(back.characters[1].origin == C.originDefault, "an old hero gets the default origin")
		check(back.characters[2].origin == C.originDefault, "every old character does")
		check(back.characters[1].level == 12, "nothing else moved")
		local bad = ProfileSchema.default()
		bad.characters[1].origin = 99
		check(ProfileSchema.load(bad).characters[1].origin == 0, "an origin out of range is cleared")
		local made = ProfileSchema.default()
		made.characters[1].created = 1
		made.characters[1].origin = 0
		check(ProfileSchema.load(made).characters[1].origin == C.originDefault, "a made hero always has one")
		local view = ProfileSchema.clientView(back)
		check(
			view.origin == C.originDefault and view.roster[1].origin == C.originDefault,
			"the client sees it"
		)
		-- Hero.Create carries the origin (optional, last)
		local hc = Remotes.HeroCreate.schema
		local last = hc[#hc]
		check(
			last.optional == true and last.min == 1 and last.max >= #C.origins,
			"HeroCreate's last arg is the origin"
		)
	end
)

test("Lore step 2: the street outfit is plain classic clothes and the hero's own face and hair", function()
	local CreatorRules = require("../src/shared/CreatorRules")
	local LookCodec = require("../src/shared/LookCodec")
	local C = Config.Creator
	local S = C.street
	local profile = ProfileSchema.default()
	local rng = Rng.new(77)
	for n = 1, 40 do
		local look = CreatorRules.randomize(Config, profile, rng)
		look.pieces.suit = 1
		look.pieces.back = 2
		look.pieces.hair = 2
		look.tints.suit = { 3, 4, 5 }
		look.tints.hair = { 6, 0, 0 }
		look.mats.suit = 3
		local before = LookCodec.copy(look)
		local st = CreatorRules.streetLook(Config, look)
		for _, slot in LookCodec.ALL do
			local keep = table.find(S.keep, slot) ~= nil
			if slot == "shirt" then
				check(st.pieces.shirt == S.shirt, "street shirt " .. n)
			elseif slot == "pants" then
				check(st.pieces.pants == S.pants, "street pants " .. n)
			elseif keep then
				check(st.pieces[slot] == (look.pieces[slot] or 0), slot .. " is the hero's own " .. n)
			else
				check(st.pieces[slot] == 0, slot .. " is off in the street " .. n)
			end
		end
		check(st.pieces.suit == 0 and st.pieces.back == 0 and st.pieces.head == 0, "no suit, cape or mask")
		check(st.pieces.emblem == 0 and st.pieces.aura == 0, "no emblem or aura")
		check(st.tints.suit == nil and st.mats.suit == nil, "the suit's colours and material are gone")
		check(st.tints.hair ~= nil and st.tints.hair[1] == 6, "the hair keeps its colour")
		check(st.tints.shirt[1] == S.shirtColor and st.tints.pants[1] == S.pantsColor, "plain colours")
		check(
			st.skin == look.skin and st.hair == look.hair and st.anime == look.anime,
			"skin and hair colour"
		)
		check(
			buffer.tostring(LookCodec.encode(look)) == buffer.tostring(LookCodec.encode(before)),
			"the designed look is not changed"
		)
		check(CreatorRules.validate(Config, profile, st), "the street outfit is always wearable " .. n)
		check(LookCodec.decode(LookCodec.encode(st)) ~= nil, "it encodes " .. n)
	end
	local shirt = CreatorRules.piece(Config, "shirt", S.shirt)
	local pants = CreatorRules.piece(Config, "pants", S.pants)
	check(shirt ~= nil and shirt.source.kind == "free", "the street shirt is one of our free shirts")
	check(pants ~= nil and pants.source.kind == "free", "the street pants are free")
	check(C.palette[S.shirtColor] ~= nil and C.palette[S.pantsColor] ~= nil, "street colours on the palette")
	check(C.avatar.on == false, "nothing from the player's own avatar")
end)

test("Lore step 2: creator first: the Opening funnel starts with the creator", function()
	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local F = AnalyticsSchema.FUNNELS.Opening
	check(
		F[1] == "session_start" and F[2] == "creator_open" and F[3] == "creator_done",
		"creator steps first"
	)
	check(F[4] == "spark_detected" and F[7] == "opening_done", "then the prologue")
	check(AnalyticsSchema.EVENTS.origin_pick ~= nil, "origin picks are logged")
end)

---------------------------------------------------------------------------
-- Lore step 4: the famous fakes and the evil twin (Config.Enemies `fake`, Shared.FakeRules)
---------------------------------------------------------------------------

local FakeRules = require("../src/shared/FakeRules")
local function readFile(path: string): string
	return require("@lune/fs").readFile(path)
end
local FAKES = { "Radiant", "Bulwark", "Skylance", "HeadmasterHalo" } -- Halo: lore step 11's chain fake

test("Lore 4: each famous fake wears a full hero look that validates through CreatorRules", function()
	local CreatorRules = require("../src/shared/CreatorRules")
	local LookCodec = require("../src/shared/LookCodec")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	-- an account that has earned everything a player can earn (every piece but the Robux packs')
	local profile = ProfileSchema.default()
	for _, p in CreatorRules.index(Config).list do
		if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
			CreatorRules.grant(profile, p)
		end
	end
	local L = Config.Enemies.look
	local names = {}
	for _, kind in FAKES do
		local cfg = Config.Enemies[kind]
		check(cfg.fake ~= nil and cfg.fake.look ~= nil, kind .. " has a hero look")
		check(type(cfg.fake.title) == "string" and cfg.fake.title ~= "", kind .. " has a title")
		check(Config.Abilities.setName[cfg.fake.path] ~= nil, kind .. "'s attacks take a real path's look")
		local look = FakeRules.look(Config, kind)
		local ok, why = CreatorRules.validate(Config, profile, look)
		check(ok, kind .. " look validates (" .. tostring(why) .. ")")
		for slot, i in look.pieces do
			if i > 0 then
				local p = CreatorRules.piece(Config, slot, i)
				check(
					p ~= nil and p.source.kind ~= "pack",
					kind .. " " .. slot .. " is earnable, never a Robux piece"
				)
			end
		end
		-- a full hero: a suit, a face, hair, an emblem and its colours
		for _, slot in { "suit", "visage", "hair", "emblem" } do
			check((look.pieces[slot] or 0) > 0, kind .. " wears a " .. slot)
		end
		-- the record survives the codec byte for byte
		local again = LookCodec.decode(LookCodec.encode(look :: any)) :: any
		check(
			again ~= nil
				and buffer.tostring(LookCodec.encode(again))
					== buffer.tostring(LookCodec.encode(look :: any)),
			kind .. " look round-trips"
		)
		-- drawn on the build and gender its look has
		check(L.builds[cfg.body.build] == look.build, kind .. " robot build matches its hero build")
		check((cfg.body.gender or 1) == look.gender, kind .. " robot gender matches its look")
		check(not names[cfg.name], kind .. " has its own name")
		names[cfg.name] = true
		check(cfg.elite and cfg.miniBoss, kind .. " is mini-boss tier")
		check(cfg.hp >= 4 * Config.Enemies.NullSentinel.hp / 2, kind .. " HP is mini-boss tier")
		check(Config.Enemies.mix[kind] == nil, kind .. " never spawns in the ambient mix")
	end
	check(Config.Enemies.Bulwark.body.height > 1.5 * Config.Enemies.Radiant.body.height, "Bulwark is a giant")
	check(FakeRules.look(Config, "Bulwark").build == 4, "Bulwark has the Titan build")
	-- the twin with no hero yet wears the default look
	local d = FakeRules.look(Config, "EvilTwin")
	check(CreatorRules.validate(Config, profile, d), "the twin's stand-in look is the default look")
end)

test(
	"Lore 4: fakes and the twin respect their switches; nothing new in the ambient mix or the swaps",
	function()
		for _, kind in { "Radiant", "Bulwark", "Skylance", "EvilTwin" } do
			local cfg = Config.Enemies[kind]
			check(cfg.on == true, kind .. " has an on switch (on)")
			local off = table.clone(Config)
			off.Enemies = table.clone(Config.Enemies)
			off.Enemies[kind] = table.clone(cfg)
			off.Enemies[kind].on = false
			local sim = EnemySim.new(off, {})
			check(EnemySim.spawn(sim, kind, 0, 20, 0, 5) == nil, kind .. " off: never spawns")
			check(not EnemySim.enabled(off, kind), kind .. " off: not enabled")
			if kind == "EvilTwin" then
				check(EnemySim.spawnTwin(sim, "Fire", 0, 20, 0, 5) == nil, "twin off: no twin of anyone")
			end
			local on = EnemySim.new(Config, {})
			check(EnemySim.spawn(on, kind, 0, 20, 0, 5) ~= nil, kind .. " on: spawns")
			for _, sw in Config.Enemies.variety.swaps do
				check(sw.kind ~= kind and not table.find(sw.from, kind), kind .. " is not an open-world swap")
			end
		end
	end
)

test("Lore 4: the face cracks at the threshold, once, and the shell only breaks after it", function()
	local RobotDamage = require("../src/shared/RobotDamage")
	local crack = FakeRules.crackAt(Config)
	check(crack > 0 and crack < 1, "a crack threshold")
	check(not FakeRules.cracked(Config, crack + 0.01) and FakeRules.cracked(Config, crack), "cracked at it")
	for _, kind in FAKES do
		local sim = EnemySim.new(Config, {})
		local e = EnemySim.spawn(sim, kind, 0, 20, 0, 10) :: any
		EnemySim.drainEvents(sim)
		local max = e.maxHealth
		-- (mitigation cuts each hit, so hit by what lands)
		local cut = 1 - (e.cfg.mitigation or 0)
		EnemySim.damage(sim, e.id, (max * (1 - crack) - 5) / cut, 1)
		local unmasks = 0
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "unmask" then
				unmasks += 1
			end
		end
		EnemySim.step(sim, 1, {})
		check(unmasks == 0 and not e.unmasked, kind .. " still a hero just above the crack")
		check(bit32.band(e.extra, EnemySim.EXTRA.unmasked) == 0, kind .. " no unmasked bit yet")
		local h = e.health / max
		check(FakeRules.shellHealth(Config, h, false) == 1, kind .. " shell whole before the crack")
		check(
			RobotDamage.count(FakeRules.shellHealth(Config, h, false), 17, Config.Enemies.look.stripBy) == 0,
			"no piece off"
		)
		EnemySim.damage(sim, e.id, 10 / cut, 1)
		EnemySim.damage(sim, e.id, 10 / cut, 1)
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "unmask" then
				unmasks += 1
				check(ev.e == e.id, "the event names the fake")
			end
		end
		EnemySim.step(sim, 2, {})
		check(unmasks == 1 and e.unmasked, kind .. " unmasked once, at the crack")
		check(bit32.band(e.extra, EnemySim.EXTRA.unmasked) ~= 0, kind .. " unmasked bit on the wire")
		near(
			FakeRules.shellHealth(Config, crack * 0.5, true),
			0.5,
			1e-9,
			"half the shell health left at half the crack"
		)
		check(FakeRules.shellHealth(Config, 0, true) == 0, "all metal at the end")
	end
	-- a plain robot never unmasks
	local sim = EnemySim.new(Config, {})
	local w = EnemySim.spawn(sim, "BruteBot", 0, 0, 0, 1) :: any
	EnemySim.damage(sim, w.id, w.maxHealth * 0.8, 1)
	for _, ev in EnemySim.drainEvents(sim) do
		check(ev.k ~= "unmask", "robots without a hero look have no face to crack")
	end
end)

test("Lore 4: plates read the hero name and title, no robot tag, then FAKE in red", function()
	for _, kind in FAKES do
		local cfg = Config.Enemies[kind]
		local p = FakeRules.plate(Config, kind, false)
		check(
			p.name == string.upper(cfg.name) and p.sub == cfg.fake.title and not p.red,
			kind .. " hero plate"
		)
		local lower = string.lower(p.name .. " " .. p.sub)
		for _, word in { "robot", "bot", "fake", "crane", "android" } do
			check(not string.find(lower, word, 1, true), kind .. " plate has no robot tag: " .. word)
		end
		local u = FakeRules.plate(Config, kind, true)
		check(
			u.name == "FAKE" and u.red and u.sub == string.upper(cfg.name),
			kind .. " unmasked: FAKE in red"
		)
	end
	local ident = { name = "Iron Comet", title = "Lab-Born" }
	local t = FakeRules.plate(Config, "EvilTwin", false, ident)
	check(t.name == "IRON COMET" and t.sub == "Lab-Born" and not t.red, "the twin's plate reads its hero")
	local tu = FakeRules.plate(Config, "EvilTwin", true, ident)
	check(tu.name == "FAKE" and tu.red and tu.sub == "IRON COMET", "the twin unmasked")
	-- the client builds the plate and turns it on the unmasked bit
	local src = clientSources()["src/client/Controllers/EnemyRenderer.luau"]
	check(string.find(src, "FakeRules.plate(", 1, true) ~= nil, "EnemyRenderer draws plates from FakeRules")
	check(string.find(src, "EXTRA.unmasked", 1, true) ~= nil, "and reads the unmasked bit")
end)

test("Lore 4: the evil twin copies its hero's look bytes and fights with its path's style", function()
	local LookCodec = require("../src/shared/LookCodec")
	local CreatorRules = require("../src/shared/CreatorRules")
	-- the server sends the active character's words as they are; the client reads the same look back
	local rng = Rng.new(44)
	local look = CreatorRules.randomize(Config, nil, rng)
	look.tints.suit = { 3, 7, 0 }
	look.mats.back = 2
	local words = LookCodec.write(look)
	local sent = LookCodec.toWords(LookCodec.fromWords(words))
	check(#sent == #words, "same word count")
	local same = true
	for i, w in words do
		same = same and sent[i] == w
	end
	check(same, "the twin carries the exact look record")
	local back = LookCodec.read(sent) :: any
	check(
		buffer.tostring(LookCodec.encode(back)) == buffer.tostring(LookCodec.encode(look)),
		"and draws the exact look"
	)
	-- every one of the 17 paths maps to a style its brain knows, drawn in that path's look
	local brains = {
		blaster = "flyer",
		gunner = "sniper",
		lobber = "bomber",
		striker = "sneak",
		duelist = "sneak",
		smasher = "brute",
	}
	local n = 0
	for _, arch in Config.Classes.order do
		for _, path in Config.Classes[arch].paths do
			n += 1
			local style = FakeRules.styleOf(Config, path)
			local cfg = FakeRules.twinCfg(Config, path)
			check(brains[style] ~= nil and cfg.ai == brains[style], path .. " -> " .. tostring(style))
			check(cfg.fake.path == path, path .. " twin draws its attacks in its path's look")
			local sim = EnemySim.new(Config, {})
			local e = EnemySim.spawnTwin(sim, path, 0, 20, 0, 12) :: any
			check(
				e ~= nil and e.kind == "EvilTwin" and e.path == path and e.ai == cfg.ai,
				path .. " twin spawns"
			)
			check(e.maxHealth == Formulas.enemyHealth(Config, "EvilTwin", 12), path .. " twin HP")
		end
	end
	check(n == 17, "all 17 paths")
	check(
		FakeRules.styleOf(Config, "Titan") == "smasher" and FakeRules.styleOf(Config, "Shadow") == "striker",
		"melee paths"
	)
	check(FakeRules.twinCfg(Config, "Blade").cloak == false, "a sword twin walks straight in (no cloak)")
	check(
		FakeRules.twinCfg(Config, "nope").fake.path == Config.Enemies.EvilTwin.twin.default,
		"unknown path: default"
	)
	-- the server's API and its wire
	local svc = readFile("src/server/Services/EnemyService.luau")
	check(
		string.find(
			svc,
			"function EnemyService.spawnTwin(player: Player, pos: Vector3, level: number",
			1,
			true
		) ~= nil,
		"EnemyService.spawnTwin(player, pos, level)"
	)
	check(
		string.find(svc, '"EnemyIdentity"', 1, true) ~= nil and Remotes.EnemyIdentity ~= nil,
		"who a twin copies goes to every device"
	)
end)

test(
	"Lore 4: the fakes' moves: Radiant's dive, Bulwark's guard, charge and shockwave, Skylance's spear and dash",
	function()
		-- Radiant: a warning ring under the hero, then the dive lands on it
		local sim = EnemySim.new(Config, {})
		local r = EnemySim.spawn(sim, "Radiant", 0, 30, 0, 10) :: any
		local hero = { id = 1, x = 0, y = 3, z = -30, alive = true }
		local warned, dived, hit, pathShots = false, false, 0, 0
		run(sim, { hero }, 0, 14, function(ev)
			if ev.k == "warn" and ev.e == r.id then
				warned = true
			elseif ev.k == "dash" and ev.e == r.id then
				dived = true
			elseif ev.k == "hit" and ev.melee then
				hit += 1
			elseif ev.k == "shot" and ev.style == 4 then
				pathShots += 1
			end
		end)
		check(warned and dived and hit >= 1, "Radiant warns, dives and strikes")
		check(pathShots >= 3, "Radiant's bolts are path shots")
		-- Bulwark: the shield takes front hits; a charge down a lane at a hero farther off; every 3rd slam a shockwave
		sim = EnemySim.new(Config, {})
		local b = EnemySim.spawn(sim, "Bulwark", 0, 0, 0, 10) :: any
		b.yaw = 0
		local fx, fz = -math.sin(0), -math.cos(0)
		local _, _, _, flag = EnemySim.damage(sim, b.id, 100, 1, b.x + fx * 10, b.z + fz * 10)
		check(flag == EnemySim.BLOCKED, "a front hit meets the tower shield")
		local far = { id = 1, x = 0, y = 3, z = -35, alive = true }
		b.nextSpecial = 0 -- the charge is ready
		local charged, stunned, lane = false, false, false
		run(sim, { far }, 0, 6, function(ev)
			if ev.k == "warn" and ev.e == b.id and ev.arc and ev.arc < 90 then
				lane = true
			elseif ev.k == "dash" and ev.e == b.id then
				charged = true
			elseif ev.k == "hit" and ev.cc == "stun" then
				stunned = true
			end
		end)
		check(lane and charged and stunned, "Bulwark shows a lane, charges and stuns the hero in it")
		sim = EnemySim.new(Config, {})
		b = EnemySim.spawn(sim, "Bulwark", 0, 0, 0, 10) :: any
		b.nextSpecial = math.huge -- slams only
		local close = { id = 1, x = 0, y = 3, z = -6, alive = true }
		local radii = {}
		run(sim, { close }, 0, 14, function(ev)
			if ev.k == "slam" and ev.e == b.id then
				table.insert(radii, ev.r)
			end
		end)
		check(
			#radii >= 3 and radii[3] == Config.Enemies.Bulwark.shockwave.radius,
			"every 3rd slam is a shockwave"
		)
		check(radii[1] == Config.Enemies.Bulwark.slam.radius, "the others the shield slam")
		-- a hero in the air (a jump) clears the shockwave
		sim = EnemySim.new(Config, {})
		b = EnemySim.spawn(sim, "Bulwark", 0, 0, 0, 10) :: any
		b.nextSpecial = math.huge
		b.slams = 2
		local jumper = { id = 1, x = 0, y = 9, z = -6, alive = true }
		local hits = 0
		run(sim, { jumper }, 0, 2.5, function(ev)
			if ev.k == "hit" then
				hits += 1
			end
		end)
		check(hits == 0, "jumping clears the shockwave")
		-- Skylance: a sighting line, a path spear, a dash to one side
		sim = EnemySim.new(Config, {})
		local s = EnemySim.spawn(sim, "Skylance", 0, 0, 0, 10) :: any
		local target = { id = 1, x = 0, y = 3, z = -50, alive = true }
		local aimed, spear, dashed = false, false, false
		run(sim, { target }, 0, 8, function(ev)
			if ev.k == "aim" and ev.e == s.id then
				aimed = true
			elseif ev.k == "shot" and ev.e == s.id and ev.style == 4 then
				spear = true
			elseif ev.k == "dash" and ev.e == s.id then
				dashed = true
			end
		end)
		check(aimed and spear and dashed, "Skylance sights, throws a spear and dashes aside")
		-- the dive, charge and dash and the face crack reach every device
		local svc = readFile("src/server/Services/EnemyService.luau")
		check(
			string.find(svc, 'ev.k == "dash"', 1, true) ~= nil
				and string.find(svc, 'ev.k == "unmask"', 1, true) ~= nil,
			"DASH and UNMASK on the wire"
		)
		local cc = clientSources()["src/client/Controllers/CombatClient.luau"]
		check(string.find(cc, "CombatFx.pathShot(", 1, true) ~= nil, "path shots drawn in the path's look")
		check(
			string.find(cc, 'Juice.fire("unmask"', 1, true) ~= nil
				and string.find(cc, "hitPause(Config.Fx.fakes.unmaskPause)", 1, true) ~= nil,
			"the crack: sound, flash and hit-stop"
		)
		check(Config.Audio.sounds.unmask ~= nil, "the crack has a sound")
	end
)

-- damage a second on a hero standing 30 studs off (80 for a Sniper), from one robot over 60 s, per (20 + 4L)
local function robotDps(kind: string, level: number, path: string?): number
	local sim = EnemySim.new(Config, {})
	local e = if path
		then EnemySim.spawnTwin(sim, path, 0, 30, 0, level) :: any
		else EnemySim.spawn(sim, kind, 0, 30, 0, level) :: any
	if e.ai ~= "flyer" then
		e.y = EnemySim.halfHeight(e.cfg)
	end
	local dist = if e.ai == "sniper" and not e.cfg.dash then 80 else 30
	local hero = { id = 1, x = 0, y = 3, z = -dist, alive = true, lx = 0, lz = 1 }
	local total, t = 0, 0
	while t < 60 do
		t += 1 / 30
		EnemySim.step(sim, t, { hero })
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "hit" and ev.hero == 1 then
				total += ev.damage
			end
		end
	end
	return total / 60
end

local function bossDps(id: string, level: number): number
	local sim = BossSim.new(Config, id, 0, 0, 0, 1e9, level, 0, Rng.new(5))
	BossSim.step(sim, 6, {})
	local hero = { id = 1, x = 0, y = 3, z = -30, alive = true }
	local total, t = 0, 6
	while t < 66 do
		t += 0.1
		BossSim.step(sim, t, { hero })
		for _, ev in BossSim.drain(sim) do
			if ev.k == "strike" then
				for _, h in ev.hits do
					total += h[2]
				end
			end
		end
	end
	return total / 60
end

test(
	"Lore 4: a fake's damage a second sits between the elite robots and the hardest-hitting world boss",
	function()
		local twinPaths = {}
		local seen = {}
		for path, style in Config.Enemies.EvilTwin.twin.paths do
			if not seen[style] then
				seen[style] = true
				table.insert(twinPaths, path)
			end
		end
		table.sort(twinPaths)
		for _, lv in { 5, 20, 40, 50 } do
			local elite = 0
			for _, kind in Config.Enemies.order do
				local cfg = Config.Enemies[kind]
				if cfg.elite and not cfg.fake then
					elite = math.max(elite, robotDps(kind, lv))
				end
			end
			local boss = 0
			for id in Config.Boss.bosses do
				boss = math.max(boss, bossDps(id, lv))
			end
			check(elite > 0 and boss > elite, "L" .. lv .. " a band to fit in")
			for _, kind in FAKES do
				local d = robotDps(kind, lv)
				check(
					d > elite and d < boss,
					string.format("L%d %s %.1f between elite %.1f and boss %.1f", lv, kind, d, elite, boss)
				)
			end
			for _, path in twinPaths do
				local d = robotDps("EvilTwin", lv, path)
				check(
					d > elite and d < boss,
					string.format(
						"L%d twin of %s (%s) %.1f between %.1f and %.1f",
						lv,
						path,
						FakeRules.styleOf(Config, path),
						d,
						elite,
						boss
					)
				)
			end
		end
	end
)

test("Lore 4: the cracked faces and the Dev panel buttons", function()
	local NL = Config.NpcLooks
	for _, fname in NL.faceOrder do
		check(type(NL.faces[fname].cracked) == "number", fname .. " has a cracked face id (0 until uploaded)")
	end
	local dev = clientSources()["src/client/Ui/DevPanel.luau"]
	check(
		string.find(dev, '"fake", i', 1, true) ~= nil and string.find(dev, '"twin"', 1, true) ~= nil,
		"Dev: each fake and your twin"
	)
	local ds = readFile("src/server/Services/DevService.luau")
	check(
		string.find(ds, "fake = function", 1, true) ~= nil
			and string.find(ds, "EnemyService.spawnTwin(player", 1, true) ~= nil,
		"DevService spawns them"
	)
end)

---------------------------------------------------------------------------
-- Lore step 3: the Ceremony prologue (Config.Story.opening, Shared.OpeningPlan, OpeningService, PrologueFx)
---------------------------------------------------------------------------

local OpeningPlan = require("../src/shared/OpeningPlan")
local PocketLayout = require("../src/shared/PocketLayout")
local OP = Config.Story.opening
local SIDES = { "hero", "villain" }

local function flat(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end

test("Lore 3: the prologue's whole route is real for any weekly seed", function()
	local gy = Config.City.ground.y
	local R = OP.roofs
	local half = Config.City.downtown.beacon.width / 2
	local front = half + OP.plaza.stage.gap + OP.plaza.stage.depth
	for _, seed in { 202647, 11, 777, 31337, 2026, 99991 } do
		local w = if seed == 202647 then world else WorldMap.build(Config, seed)
		for k = 1, 6 do
			local r = OpeningPlan.route(Config, w, Rng.new(seed * 7 + k))
			check(r ~= nil, "a route for seed " .. seed .. " #" .. k)
			if r then
				local tag = " (seed " .. seed .. ")"
				local hx, hz = OpeningPlan.plaza(w)
				check(r.hall[1] == hx and r.hall[3] == hz, "the stage is at Crane's Hero Hall" .. tag)
				check(
					#r.crowd == OP.plaza.crowd.count and #r.fakes == 3,
					"a full crowd and the three fakes" .. tag
				)
				for _, c in r.crowd do
					check(
						HeightMap.at(w.heights, c[1], c[3]) <= gy + 1.5,
						"the crowd stands on open ground" .. tag
					)
				end
				check(
					HeightMap.at(w.heights, r.start[1], r.start[3]) <= gy + 1.5,
					"the hero starts on the ground"
				)
				check(flat(r.stage, r.hall) <= front, "the stage stands before the Hall" .. tag)
				local away = (r.spark[1] - hx) * r.face[1] + (r.spark[3] - hz) * r.face[3]
				check(away >= front, "the run goes away from the stage" .. tag)
				local run = flat(r.spark, r.start)
				check(
					run >= OP.run.minD - 1 and run <= OP.run.maxD + 1,
					"the run is " .. math.floor(run) .. tag
				)
				check(
					HeightMap.at(w.heights, r.spark[1], r.spark[3]) <= gy + 1.5,
					"the spark point is open ground"
				)
				check(#r.roofs == R.count, R.count .. " roofs for the chase" .. tag)
				for i = 2, #r.roofs do
					local a, b = r.roofs[i - 1], r.roofs[i]
					local gap = flat(a, b)
					check(
						gap >= R.gap[1] and gap <= Config.Move.leap.range,
						"roof " .. i .. " is one Leap away" .. tag
					)
					check(b[2] <= a[2] + R.climb, "no higher than a Leap climbs" .. tag)
					check(b[2] - gy >= R.minH, "a real roof" .. tag)
				end
				check(
					HeightMap.at(w.heights, r.entrance[1], r.entrance[3]) <= gy + 1.5,
					"the subway steps are on the street" .. tag
				)
				local eg = flat(r.entrance, r.roofs[#r.roofs])
				check(
					eg >= OP.entrance.minD and eg <= OP.entrance.maxD + 1,
					"the steps are below the last roof"
				)
				check(
					r.billboard[2] - gy >= 20 and (r.billboard[4] ~= 0 or r.billboard[5] ~= 0),
					"a billboard"
				)
				check(flat(r.landing, r.hall) <= 120, "the hero lands back in the plaza" .. tag)
				-- every beat has a place to start from, in the city or the subway, on both sides
				local lane = OpeningPlan.lane(Config, (k - 1) % OP.subway.lanes + 1)
				for _, step in OpeningPlan.STEPS do
					local p = OpeningPlan.startPoint(r, lane, step)
					local inPocket = PocketLayout.at(Config, p[1], p[2], p[3])
						== PocketLayout.subwayIndex(Config)
					check(
						inPocket == (OpeningPlan.CITY[step] ~= true),
						step .. " starts in the right place" .. tag
					)
					check(
						OpeningPlan.startPoint(r, nil, step) ~= nil,
						step .. " has a place with every lane busy"
					)
				end
			end
		end
	end
end)

test(
	"Lore 3: the rooftop row: in the layout, clear of the squares and the Hall, wreckable, the chase's roofs",
	function()
		local gy = Config.City.ground.y
		local T = Config.City.downtown
		local R = OP.roofs
		local L = world.downtown
		check(#L.row == #T.row.roofs and #L.row >= R.count, #L.row .. " roofs in the row")
		local function overlaps(ax, az, asx, asz, bx, bz, bsx, bsz): boolean
			return math.abs(ax - bx) < (asx + bsx) / 2 and math.abs(az - bz) < (asz + bsz) / 2
		end
		local hall = L.beacon
		local heights = {}
		for i, r in L.row do
			heights[r.top] = true
			for _, o in L.open do
				check(
					not overlaps(r.x, r.z, r.sx, r.sz, o.x, o.z, o.size, o.size),
					"roof " .. i .. " is off " .. o.id
				)
			end
			check(
				not overlaps(r.x, r.z, r.sx, r.sz, hall.x, hall.z, T.block, T.block),
				"roof " .. i .. " is off the Hall's plaza"
			)
			for id, s in L.safehouseSpots do
				check(
					not overlaps(r.x, r.z, r.sx, r.sz, s.x, s.z, 20, 20),
					"roof " .. i .. " is off safehouse " .. id
				)
			end
			-- a real building: alone on its lot, wreckable like any other
			local mine, others = 0, 0
			for _, b in L.buildings do
				if b.grp == r.grp then
					mine += 1
				elseif overlaps(r.x, r.z, r.sx, r.sz, b.x, b.z, b.sx, b.sz) then
					others += 1
				end
			end
			check(mine == 1 and others == 0, "roof " .. i .. " stands alone")
			local wreck = nil
			for _, b in world.buildings do
				if b.grp == r.grp then
					wreck = b
				end
			end
			check(
				wreck ~= nil and wreck.district == "Downtown" and math.abs(wreck.top - r.top) < 0.01,
				"roof " .. i .. " can be wrecked and repaired"
			)
			-- the middle stays clear to land on: anything solid near it is a low skylight
			for _, b in L.boxes do
				if b.grp == r.grp and b.kind == "prop" and not b.ghost then
					local near = math.abs(b.cx - r.x) < b.sx / 2 + 4 and math.abs(b.cz - r.z) < b.sz / 2 + 4
					check(
						not near or b.cy + b.sy / 2 <= r.top + 1.5,
						"roof " .. i .. "'s middle is clear to land"
					)
				end
			end
			if i > 1 then
				local p = L.row[i - 1]
				local gap = math.sqrt((r.x - p.x) ^ 2 + (r.z - p.z) ^ 2)
				check(
					gap >= 35 and gap <= 65 and gap <= Config.Move.leap.range,
					"hop " .. i .. " is a short Leap"
				)
				check(r.top <= p.top + R.climb, "hop " .. i .. " rises no more than a Leap climbs")
				check(r.top - gy >= R.minH, "roof " .. i .. " is a real roof")
			end
		end
		local n = 0
		for _ in heights do
			n += 1
		end
		check(n >= 4, "the roofs have varied heights")
		-- the chase runs the row (for any seed) and falls back to ordinary roofs without it
		for k = 1, 4 do
			local r = OpeningPlan.route(Config, world, Rng.new(k))
			check(r ~= nil and #r.roofs == R.count, "the chase has " .. R.count .. " roofs")
			if r then
				for i, p in r.roofs do
					check(p[1] == L.row[i].x and p[3] == L.row[i].z, "chase roof " .. i .. " is the row's")
				end
				check(flat(r.spark, r.roofs[1]) <= 80, "the spark point is at the foot of the row")
			end
		end
		local bare = table.clone(world)
		bare.downtown = table.clone(world.downtown)
		bare.downtown.row = {}
		local fb = OpeningPlan.route(Config, bare, Rng.new(5))
		check(fb ~= nil and #fb.roofs == R.fallback, "without the row, " .. R.fallback .. " ordinary roofs")
	end
)

test("Lore 3: the subway pocket: a lane per prologue, collapses behind the hero, a fight chamber", function()
	local S = OP.subway
	local idx = PocketLayout.subwayIndex(Config)
	check(idx == Config.Story.pockets.count + 1, "the subway is its own pocket (missions never take it)")
	local l = PocketLayout.build(Config, idx, "subway")
	check(#l.boxes > 10 and #(l.lists.lanes or {}) == S.lanes, "the tunnels are built, one a lane")
	local seen = {}
	for i = 1, S.lanes do
		local ln = OpeningPlan.lane(Config, i)
		check(
			PocketLayout.at(Config, ln.start[1], ln.start[2], ln.start[3]) == idx,
			"lane " .. i .. " start inside"
		)
		check(
			PocketLayout.at(Config, ln.fight[1], ln.fight[2], ln.fight[3]) == idx,
			"lane " .. i .. " chamber inside"
		)
		check(ln.start[3] > ln.z1 and ln.fight[3] < ln.z1, "the chamber is past the tunnel")
		local last = math.huge
		for k, c in ln.collapses do
			check(c.z < ln.start[3] and c.z > ln.z1, "each slab falls inside the tunnel")
			check(c.z < last, "the slabs fall in order down the tunnel")
			last = c.z
			-- kid-proof: never on the hero, only once it is past the slab's far edge
			check(
				not OpeningPlan.slabFalls(Config, ln, k, c.z + S.slab / 2),
				"no slab falls on a hero under it"
			)
			check(not OpeningPlan.slabFalls(Config, ln, k, c.z - S.slab / 2), "nor on one at its edge")
			check(OpeningPlan.slabFalls(Config, ln, k, c.z - S.slab / 2 - S.behind - 1), "it falls behind")
		end
		check(#ln.collapses >= 3, "the tunnel caves in behind the hero")
		local b = OpeningPlan.chamber(Config, ln)
		check(
			b[1] < ln.fight[1] and ln.fight[1] < b[2] and b[3] < ln.fight[3] and ln.fight[3] < b[4],
			"room holds the fight"
		)
		check(
			b[2] - b[1] < S.chamber and b[4] - b[3] < S.chamber and b[3] > ln.z1 - S.chamber,
			"room inside walls"
		)
		check(not seen[ln.x], "lanes do not overlap")
		seen[ln.x] = true
	end
	check(S.pitch >= S.chamber + 4, "chambers fit side by side")
	check(S.rubble < Config.Move.leap.range, "the rubble can be leapt")
end)

test("Kid-proof prologue: solo robots, guided hops, a hint on every played beat", function()
	-- the solo rule: a prologue hero sees only its own robots, and they only it
	local sim = EnemySim.new(Config, { seed = 7 })
	local e = EnemySim.spawn(sim, "SparkDrone", 0, 5, 0, 1)
	check(e ~= nil, "a robot")
	local city = { id = 1, x = 4, y = 5, z = 0, alive = true }
	local solo = { id = 2, x = 3, y = 5, z = 0, alive = true, solo = 2 }
	check(EnemySim.sees(e, city) and not EnemySim.sees(e, solo), "a city robot never sees a prologue hero");
	(e :: any).solo = 2
	check(EnemySim.sees(e, solo) and not EnemySim.sees(e, city), "a prologue robot sees only its hero")
	EnemySim.step(sim, 1, { city, solo })
	check((e :: any).target == nil or (e :: any).target == 2, "it never picks the city hero");
	(e :: any).bounds = { -2, 2, -2, 2, 6 };
	(e :: any).x, (e :: any).z, (e :: any).y = 50, -50, 30
	EnemySim.keepIn(e :: any)
	check((e :: any).x == 2 and (e :: any).z == -2 and (e :: any).y == 6, "a robot never leaves its room")
	-- guided hops: sane arcs for any roof gap and the long drop to the subway
	for _, d in { { 30, 0 }, { 75, 12 }, { 60, -200 } } do
		local t, h = OpeningPlan.hopArc(Config, { 0, 100, 0 }, { d[1], 100 + d[2], 0 })
		check(t >= OP.hop.time[1] and t <= OP.hop.time[2] and h >= OP.hop.height[1], "hop arc " .. d[1])
	end
	for _, step in OpeningPlan.STEPS do
		if not OpeningPlan.CUT[step] and not OpeningPlan.timed(Config, step) then
			for _, side in { "hero", "villain" } do
				local h = OpeningPlan.hint(Config, step, side, function(a)
					return "[" .. a .. "]"
				end)
				check(
					type(h) == "string" and #h <= 60 and not string.find(h, "{"),
					step .. " hint for " .. side
				)
			end
		end
	end
	for _, step in { "leap", "chase", "descend" } do
		check(OpeningPlan.HOPS[step] and Config.Ui.prologue.hints[step], step .. " is a guided hop")
	end
end)

test("Lore 3: every beat in order for both sides; the side's own Spark and lines", function()
	check(#OpeningPlan.STEPS == 13 and OpeningPlan.STEPS[1] == "ceremony", "13 beats, the ceremony first")
	check(OpeningPlan.STEPS[#OpeningPlan.STEPS] == "title", "the title card last")
	for i, step in OpeningPlan.STEPS do
		check(OpeningPlan.CODE[step] == i, step .. " has its code")
		check(OpeningPlan.limit(Config, step) > 0, step .. " moves on by itself")
	end
	check(OpeningPlan.sparkBeat("hero") == "shield", "the Vigil's Spark shields the kid")
	check(OpeningPlan.sparkBeat("villain") == "blast", "the Syndicate's Spark blasts the shover")
	local patchFrom = OpeningPlan.CODE.leap
	for _, side in SIDES do
		for _, step in OpeningPlan.STEPS do
			for _, l in OpeningPlan.lines(Config, step, side) do
				check(
					type(l.text) == "string" and #l.text > 0 and #l.text <= 90,
					step .. " line text (" .. side .. ")"
				)
				check(
					Config.Story.guides.speakers[l.who] ~= nil,
					step .. ": a known speaker " .. tostring(l.who)
				)
				check(
					l.at >= 0 and l.at < OpeningPlan.limit(Config, step),
					step .. " line comes inside its beat"
				)
				if l.who == "patch" then
					check(OpeningPlan.CODE[step] >= patchFrom, "Patch is on the radio from the chase on")
				end
			end
		end
		check(#OpeningPlan.lines(Config, "ceremony", side) >= 4, "Crane's stage speech")
		local rescue = OpeningPlan.lines(Config, "rescue", side)
		local lodestar = false
		for _, l in rescue do
			lodestar = lodestar or l.who == "lodestar"
		end
		check(lodestar, "Lodestar speaks at the rescue")
	end
	for _, step in { "spark", "chase", "rescue" } do
		local a, b = OpeningPlan.lines(Config, step, "hero"), OpeningPlan.lines(Config, step, "villain")
		check(#a == #b and a[1].text ~= b[1].text, step .. ": a side-flavoured line")
	end
	check(
		Config.Story.guides.speakers.patch.style == "radio"
			and Config.Story.guides.speakers.lodestar.style == "person",
		"Patch is a radio voice"
	)
	check(
		OP.chase.fake == "Skylance" and Config.Enemies.Skylance.fake ~= nil,
		"Skylance chases (a famous fake)"
	)
	check(OP.fight.fake == "Skylance", "the fight is with the chaser")
	local sum = 0
	for _, step in OpeningPlan.STEPS do
		if OpeningPlan.timed(Config, step) then
			sum += OpeningPlan.limit(Config, step)
		end
	end
	check(sum >= 50 and sum <= 90, "about a minute of camera beats in about 4 minutes")
end)

test("Lore 3: stuck beats move on, the prologue finishes itself, skips only on a replay", function()
	-- a hero who never does anything still reaches the end, every beat once, in order
	local step: string? = OpeningPlan.STEPS[1]
	local t, seen = 0, {}
	while step do
		table.insert(seen, step)
		t += OpeningPlan.limit(Config, step)
		step = OpeningPlan.next(step)
	end
	check(#seen == #OpeningPlan.STEPS, "every beat once")
	check(OP.timeout < t, "the whole-prologue timeout cuts a stuck run short (" .. math.floor(t) .. " s)")
	check(OP.timeout >= 240, "but never a played one (about 4 minutes)")
	for _, step in OpeningPlan.STEPS do
		check(not OpeningPlan.canSkip(step, false), step .. ": no skip the first time")
		check(
			OpeningPlan.canSkip(step, true) == (OpeningPlan.CUT[step] == true),
			step .. ": skip on a replay"
		)
	end
	check(
		OP.spark.auto < OpeningPlan.limit(Config, "spark"),
		"the Spark fires by itself before its beat ends"
	)
	-- the server: the safety, the hold for a returning account, Create First and skips
	local src = readFile("src/server/Services/OpeningService.luau")
	for _, needle in
		{
			"O.timeout",
			"OpeningPlan.limit(Config, s)",
			"OpeningPlan.canSkip(r.step, r.replay)",
			"act == 3 and r.hold",
			"act == 4 and r.hold",
			"hero.floor",
			"OpeningService.Finished",
		}
	do
		check(string.find(src, needle, 1, true) ~= nil, "OpeningService: " .. needle)
	end
end)

test(
	"Lore 3: returning players skip it; old saves never replay it; a save mid-opening restarts it",
	function()
		check(not OpeningPlan.due(ProfileSchema.newCharacter()), "a hero not made yet waits for its creator")
		local v10 = ProfileSchema.load({
			version = 10,
			characters = {
				{ created = 1, level = 1, story = { opening = 0 } },
				{ created = 1, story = { opening = 1 } },
			},
		})
		check(
			OpeningPlan.due(v10.characters[1]),
			"a v10 save that stopped mid-opening starts the new prologue"
		)
		check(not OpeningPlan.due(v10.characters[2]), "anyone past the old opening is never sent back")
		local old = ProfileSchema.load({ version = 2, characters = { { level = 7, xp = 10 } } })
		check(not OpeningPlan.due(old.characters[1]), "an old played hero skips it")
		check(
			Config.Story.missions[1].opening and Config.Story.missions[1].name == "The Ceremony",
			"mission 1"
		)
		check(Config.Story.missions[OP.next] ~= nil, "the hook: the next mission")
		local menu = clientSources()["src/client/Ui/MainMenu.luau"]
		check(
			string.find(menu, "StoryClient.createFirst()", 1, true) ~= nil
				and string.find(menu, "StoryClient.playPrologue()", 1, true) ~= nil,
			"the main menu's Create First and PLAY THE PROLOGUE"
		)
		check(Config.Story.cinematic == nil, "the old cinematic is gone")
	end
)

test("Lore 3: no old opening names in the prologue's player text", function()
	local OLD = { "shardfall", "tram", "comet", "save her", "grab it" }
	local hits = {}
	local function look(where: string, text: string)
		local low = string.lower(text)
		for _, w in OLD do
			if string.find(low, "%f[%w]" .. w .. "%f[%W]") then
				table.insert(hits, where .. ": " .. w .. " in " .. text)
			end
		end
	end
	local function walk(v: any, path: string)
		if type(v) == "string" then
			look(path, v)
		elseif type(v) == "table" then
			for k, x in v do
				walk(x, path .. "." .. tostring(k))
			end
		end
	end
	walk(OP, "Story.opening")
	walk(Config.Story.missions[1], "Story.missions[1]")
	for _, path in
		{
			"src/shared/OpeningPlan.luau",
			"src/server/Services/OpeningService.luau",
			"src/client/Fx/PrologueFx.luau",
			"src/client/Fx/StoryFx.luau",
			"src/client/Ui/StoryHud.luau",
			"src/client/Controllers/StoryClient.luau",
			"src/client/Ui/MainMenu.luau",
		}
	do
		local src = readFile(path)
		for line in string.gmatch(src .. "\n", "([^\n]*)\n") do
			local cut = string.find(line, "--", 1, true)
			local code = if cut then string.sub(line, 1, cut - 1) else line
			for lit in string.gmatch(code, '"[^"]*"') do
				if lit ~= '"Catch"' then -- the HUD's interact button id (Hud), not text
					look(path, lit)
				end
			end
		end
	end
	check(#hits == 0, "old opening names left: " .. table.concat(hits, "; "))
end)

test("Lore 3: Lodestar's look, the street outfit, the funnel and the Dev panel", function()
	local CreatorRules = require("../src/shared/CreatorRules")
	local profile = ProfileSchema.default()
	for _, p in CreatorRules.index(Config).list do
		if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
			CreatorRules.grant(profile, p)
		end
	end
	local look = FakeRules.lookFrom(Config, OP.lodestar.look, "Lodestar")
	local ok, why = CreatorRules.validate(Config, profile, look)
	check(ok, "Lodestar's hero look validates (" .. tostring(why) .. ")")
	check(look.pieces.suit > 0 and look.pieces.back > 0 and look.pieces.emblem > 0, "a full hero look")
	local src = readFile("src/server/Services/OpeningService.luau")
	check(
		string.find(src, "GearService.setStreet(r.player, true)", 1, true) ~= nil
			and string.find(src, "GearService.setStreet(r.player, false)", 1, true) ~= nil,
		"the street outfit on at the ceremony, off for the suit"
	)
	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local F = AnalyticsSchema.FUNNELS.Opening
	check(#F == 12, "the funnel keeps its shape")
	check(
		F[4] == "spark_detected"
			and F[5] == "first_spark"
			and F[6] == "fake_cracked"
			and F[7] == "opening_done",
		"the prologue's beats in the funnel"
	)
	for _, name in { "spark_detected", "first_spark", "fake_cracked" } do
		check(string.find(src, '"' .. name .. '"', 1, true) ~= nil, name .. " is logged by the prologue")
	end
	local dev = clientSources()["src/client/Ui/DevPanel.luau"]
	check(
		string.find(dev, '"prologue", 0', 1, true) ~= nil
			and string.find(dev, '"prologue", 1', 1, true) ~= nil
			and string.find(dev, '"opening", beat', 1, true) ~= nil,
		"Dev: the prologue as each side and a jump to each beat"
	)
	check(
		string.find(readFile("src/server/Services/DevService.luau"), "prologue = function", 1, true) ~= nil,
		"DevService"
	)
	local fx = clientSources()["src/client/Fx/PrologueFx.luau"]
	-- (lore step 7: SKIP is the cutscene player's; the prologue's beat scene asks canSkip)
	check(string.find(fx, "OpeningPlan.canSkip", 1, true) ~= nil, "the SKIP button follows canSkip")
	check(
		string.find(fx, "CombatFx.reduceFlashing", 1, true) ~= nil,
		"reduce flashing softens the slow motion"
	)
	check(string.find(fx, "PLACEHOLDER ART", 1, true) ~= nil, "placeholder art is labelled")
	check(string.find(fx, 'QualityController.name == "low"', 1, true) ~= nil, "a smaller crowd on phones")
end)

---------------------------------------------------------------------------
-- Lore step 5: Act 1 rewritten (nate's lore doc A3/A4): Safehouse, Framed, The Copy, The Signal, Live, co-op
-- with each side's own goals, the 3 choices per side, the ending broadcast, the old saves mapped by index
---------------------------------------------------------------------------

do
	local StoryPlan = require("../src/shared/StoryPlan")
	local PocketLayout = require("../src/shared/PocketLayout")
	local S = Config.Story
	local NAMES = { "The Ceremony", "Safehouse", "Framed", "The Copy", "The Signal", "Live" }
	local KINDS = {
		hold = true,
		["break"] = true,
		chase = true,
		reach = true,
		boss = true,
		defeat = true,
		fake = true,
		twin = true,
		scene = true,
		choice = true,
		warframe = true,
	}

	-- Every step a side can meet in a mission, with both picks of every choice (each branch at least once)
	local function allSteps(num: number, side: string): { any }
		local out = {}
		for pick = 0, 2 do
			local choices = { pick, pick, pick }
			for i = 1, StoryPlan.stages(Config, num) do
				local st = StoryPlan.stage(Config, num, i, side, choices)
				if st and not table.find(out, st) then
					table.insert(out, st)
				end
			end
		end
		return out
	end

	-- Can this step be played in the layout? (its points, lists, robots and lines all exist)
	local function playable(l: any, st: any, side: string, where: string)
		check(KINDS[st.kind] == true, where .. ": a known step kind (" .. tostring(st.kind) .. ")")
		check(StoryPlan.need(st) >= 1, where .. ": needs something")
		if st.kind ~= "scene" and st.kind ~= "choice" then
			local text = StoryPlan.text(st, side)
			check(#text > 4, where .. ": objective text")
		end
		for _, key in { "at", "focus", "lodestar" } do
			if type(st[key]) == "string" and st[key] ~= "fake" then
				check(l.points[st[key]] ~= nil, where .. ": the pocket has " .. st[key])
			end
		end
		if st.list then
			check(
				l.lists[st.list] and #l.lists[st.list] >= (st.points or 1),
				where .. ": the pocket has " .. st.list
			)
		end
		if st.kind == "hold" and not st.at and not st.list then
			check(#(l.lists.stations or {}) >= st.points, where .. ": stations")
		end
		if st.kind == "break" and not st.at and not st.list and not st.train then
			check(#(l.lists.crates or {}) >= st.points, where .. ": crates")
		end
		if st.train then
			check(l.points.trainStart and l.points.trainDir, where .. ": the train line")
		end
		if st.room then
			check(l.lists.rooms and l.lists.rooms[st.room], where .. ": room " .. st.room)
		end
		if st.kind == "chase" then
			check(#(l.lists.path or {}) >= 3, where .. ": a chase path")
		end
		if st.kind == "warframe" then
			check(#(l.lists.pillars or {}) >= 6 and l.points.boss, where .. ": the arena")
		end
		for _, kind in { st.enemy, st.guards and st.guards[1], st.adds and st.adds[1] } do
			if kind then
				check(Config.Enemies[kind] ~= nil, where .. ": robot " .. kind)
			end
		end
		for _, row in st.squads or {} do
			check(Config.Enemies[row[1]] ~= nil, where .. ": squad " .. row[1])
		end
		for _, row in st.waves or {} do
			check(Config.Enemies[row[1]] ~= nil, where .. ": wave " .. row[1])
		end
		if st.kind == "fake" then
			check(Config.Enemies[st.enemy].fake ~= nil, where .. ": " .. st.enemy .. " is a famous fake")
		end
		if st.kind == "scene" then
			local lines = StoryPlan.sceneLines(st, side)
			check(
				#lines >= 2 and st.seconds >= 5 and st.seconds <= 20,
				where .. ": a 5 to 20 s beat with lines"
			)
			for _, line in lines do
				check(S.guides.speakers[line.who] ~= nil, where .. ": speaker " .. line.who)
				check(line.at < st.seconds, where .. ": each line starts inside the beat")
			end
		end
		if st.kind == "choice" then
			check(
				S.choices[st.choice] ~= nil and S.choices[st.choice].mission == l.num,
				where .. ": its choice"
			)
		end
	end

	test(
		"Lore 5: Act 1 is the 6 missions of nate's lore doc, in order, at the old levels and rewards",
		function()
			check(#S.missions == 6, "6 missions")
			for n, name in NAMES do
				check(
					S.missions[n].name == name and S.missions[n].num == n,
					"mission " .. n .. " is " .. name
				)
			end
			check(S.missions[1].opening and S.opening.next == 2, "1 is the Ceremony prologue; it leads to 2")
			-- pacing and rewards by index, exactly the old Act 1's (so totals do not move)
			local OLD = {
				{ minLevel = 1, skillPoints = 1 },
				{ minLevel = 3, minutes = 8, loot = "story" },
				{ minLevel = 4, minutes = 8, loot = "story", renown = 600 },
				{ minLevel = 5, minutes = 7, rep = 120 },
				{ minLevel = 6, minutes = 10, loot = "story" },
				{ minLevel = 8, minutes = 12, loot = "storyFinale", skillPoints = 1 },
			}
			for n, old in OLD do
				local m = S.missions[n]
				for _, k in { "minLevel", "minutes", "loot", "renown", "rep", "skillPoints" } do
					check(m[k] == old[k], m.id .. " keeps the old " .. k)
				end
			end
			check(StoryPlan.actSkillPoints(Config) == 8, "Act 1 still grants 8 Skill Points")
			check(S.missions[6].finale and S.missions[6].ending == "act1", "Live ends the act")
		end
	)

	-- one test per mission and side: playable in its pocket, and in a mixed party both sides play at once
	for n = 2, 6 do
		for _, side in { "hero", "villain" } do
			local m = S.missions[n]
			local label = if side == "villain" then "the Syndicate" else "the Vigil"
			test(
				string.format("Lore 5: %s as %s: every stage plays in its pocket, co-op", m.name, label),
				function()
					local l = PocketLayout.build(Config, 1, m.layout)
					l.num = n
					check(
						#m.hero == #m.villain and #m.hero == StoryPlan.stages(Config, n),
						"both lists, one per stage"
					)
					local steps = allSteps(n, side)
					check(#steps >= 4, "at least 4 steps")
					for i, st in steps do
						playable(l, st, side, string.format("%s %s step %d", m.id, side, i))
					end
					-- a mixed party: each stage gives both sides something, or one shared step; split stages differ
					local split, kinds = 0, {}
					for i = 1, StoryPlan.stages(Config, n) do
						local plan =
							StoryPlan.tracks(Config, n, i, { hero = { 1, 1, 1 }, villain = { 2, 2, 2 } })
						if plan.both then
							check(
								plan.hero == nil and plan.villain == nil,
								"a shared stage is one step for all"
							)
							kinds[plan.both.kind] = true
						else
							check(
								plan.hero ~= nil and plan.villain ~= nil,
								"a split stage has a track per side"
							)
							local h, v = plan.hero, plan.villain
							if h and v and h.kind ~= "choice" then
								split += 1
								check(
									StoryPlan.text(h, "hero") ~= StoryPlan.text(v, "villain"),
									"each side's own goal"
								)
							end
						end
						-- a solo player of this side gets only their own track
						local solo = StoryPlan.tracks(Config, n, i, { [side] = { 1, 1, 1 } })
						local other = if side == "hero" then "villain" else "hero"
						check(solo[other] == nil, "no track for a side that is not there")
					end
					check(split >= 1, "at least one stage where the sides do different jobs at once")
					check(kinds.scene == true, "at least one camera beat")
					-- shared steps word the goal per side
					for i = 1, StoryPlan.stages(Config, n) do
						local st = m.hero[i]
						if StoryPlan.shared(Config, n, i) and st.kind ~= "scene" and st.villainText then
							check(
								st.villainText ~= st.text,
								m.id .. " stage " .. i .. ": the Syndicate reads its own goal"
							)
						end
					end
				end
			)
		end
	end

	test(
		"Lore 5: the beats follow the doc (Lodestar and Patch, the bridge, the twin, the tower, the unmask)",
		function()
			local function has(n: number, kind: string, field: string?, value: any?): boolean
				for _, side in { "hero", "villain" } do
					for _, st in allSteps(n, side) do
						if st.kind == kind and (not field or st[field] == value) then
							return true
						end
					end
				end
				return false
			end
			local function speaks(n: number, who: string): boolean
				for _, st in S.missions[n].hero do
					for _, l in st.lines or {} do
						if l.who == who then
							return true
						end
					end
				end
				return false
			end
			check(
				S.missions[2].layout == "dungeon" and speaks(2, "lodestar") and speaks(2, "patch"),
				"Safehouse"
			)
			check(has(2, "scene", "lodestar", "door"), "Lodestar stands in the safehouse")
			local offer = S.missions[2].hero[5]
			check(
				offer.kind == "scene" and offer.lines[2].hero ~= offer.lines[2].villain,
				"recruited, or a deal"
			)
			check(S.missions[3].layout == "bridge" and has(3, "fake", "enemy", "Radiant"), "Framed: Radiant")
			check(has(3, "hold") and has(3, "break"), "Vigil saves people while the Syndicate loots")
			check(has(4, "twin"), "The Copy: the evil twin")
			check(
				S.missions[5].layout == "tower" and speaks(5, "insider"),
				"The Signal: the tower and the insider"
			)
			check(
				has(5, "hold", "at", "mast") and has(5, "hold", "at", "relay"),
				"guard Patch / plant the feed"
			)
			check(
				has(6, "fake", "enemy", "Bulwark") and has(6, "warframe"),
				"Live: Bulwark, then its battle form"
			)
			check(
				has(6, "fake", "news", "unmask") and S.news.unmask ~= nil,
				"the unmask goes out on every screen"
			)
			check(Config.Boss.bosses.NullWarFrame.name == "Bulwark's Battle Form", "the battle form's name")
		end
	)

	test(
		"Lore 5: each side's 3 choices record their flag and pay only Skill Points, rep and cosmetics",
		function()
			local ALLOWED = { label = true, flag = true, rep = true, perk = true, arena = true }
			local flags = {}
			check(#S.choices == 3, "3 choices")
			local missions = {}
			for n, c in S.choices do
				missions[c.mission] = true
				for _, side in { "hero", "villain" } do
					local key = StoryPlan.sideKey(side)
					check(#c[key] == 2, string.format("choice %d: 2 options for the %s", n, side))
					for o, opt in c[key] do
						for k in opt do
							check(
								ALLOWED[k] == true,
								string.format("choice %d %s %d: %s changes no stats", n, side, o, k)
							)
						end
						check(not flags[opt.flag], "flag " .. opt.flag .. " is its own")
						flags[opt.flag] = true
						local story = ProfileSchema.newCharacter(side).story
						local ok, fx = StoryPlan.pick(Config, story, n, o, side)
						check(
							ok and fx.flag == opt.flag and fx.skillPoints == 2,
							opt.label .. ": picked, flag, 2 points"
						)
						check(story.choices[n] == o, opt.label .. ": saved in its slot")
						check(
							StoryPlan.flag(Config, story, side, opt.flag),
							opt.label .. ": the flag reads back"
						)
						local other = c[key][3 - o]
						check(
							not StoryPlan.flag(Config, story, side, other.flag),
							opt.label .. ": not the other flag"
						)
						local track = fx.rep and fx.rep[1]
						check(
							track == "city" or track == (if side == "villain" then "syndicate" else "vigil"),
							"rep track"
						)
						check(
							fx.credits == nil and fx.gadget == nil and fx.renown == nil,
							"no Credits, gear or Renown"
						)
						check(not StoryPlan.pick(Config, story, n, 3 - o, side), opt.label .. ": once only")
					end
					check(#StoryPlan.labels(Config, n, side) == 2, "2 buttons")
				end
			end
			check(
				missions[3] and missions[4] and missions[5],
				"one choice each in Framed, The Copy and The Signal"
			)
			-- the flags each mission's choice step asks for match the doc
			check(StoryPlan.labels(Config, 1, "hero")[1] == "Save the Bridge", "Framed: save the bridge")
			check(StoryPlan.labels(Config, 1, "villain")[1] == "Grab the Data Core", "Framed: the data core")
			check(StoryPlan.labels(Config, 3, "hero")[1] == "Spare the Core", "The Copy: spare the core")
			check(StoryPlan.labels(Config, 3, "villain")[1] == "Reprogram It", "The Copy: a minion")
			check(StoryPlan.labels(Config, 2, "hero")[2] == "Test Her", "The Signal: test the insider")
			check(StoryPlan.labels(Config, 2, "villain")[2] == "Hold It for Ransom", "The Signal: the ransom")
		end
	)

	test("Lore 5: the ending broadcast plays after Live (registration law, public enemy number 1)", function()
		for n = 1, 5 do
			check(StoryPlan.ending(Config, n) == nil, "no broadcast after mission " .. n)
		end
		check(StoryPlan.ending(Config, 6) == "act1", "the broadcast after Live")
		local e = S.ending.act1
		check(string.find(e.headline, "REGISTRATION", 1, true) ~= nil, "the registration law passes")
		check(string.find(e.enemy, "PUBLIC ENEMY", 1, true) ~= nil, "public enemy number 1")
		check(e.enemyAt < e.seconds and #e.lines >= 2, "Crane's lines, then the card")
		for _, l in e.lines do
			check(S.guides.speakers[l.who] ~= nil and l.at < e.enemyAt, "a known speaker before the card")
		end
		local svc = readFile("src/server/Services/MissionService.luau")
		check(string.find(svc, 'Net.fire("StoryBroadcast"', 1, true) ~= nil, "the server sends it")
		check(
			string.find(svc, "StoryPlan.ending(Config, run.num)", 1, true) ~= nil,
			"after the act's ending mission"
		)
		check(require("../src/shared/Remotes").StoryBroadcast ~= nil, "its remote")
		local hud = clientSources()["src/client/Ui/StoryHud.luau"]
		check(
			string.find(hud, "StoryClient.Broadcast:Connect(showBroadcast)", 1, true) ~= nil,
			"the HUD shows it"
		)
		check(string.find(hud, 'GetAttribute("HeroName")', 1, true) ~= nil, "under the hero's own name")
	end)

	test("Lore 5: no old Act 1 names in player text", function()
		local OLD = {
			"Shardfall",
			"War-Frame",
			"War Frame",
			"Hold the Line",
			"Signal Tower",
			"The Informant",
			"Under the Docks",
			"Smash and Grab",
		}
		local hits = {}
		local function look(where: string, text: string)
			for _, w in OLD do
				if string.find(string.lower(text), string.lower(w), 1, true) then
					table.insert(hits, where .. ": " .. w .. " in " .. text)
				end
			end
			if string.find(text, "%f[%w]Null%f[%W]") or string.find(text, "%f[%w]NULL%f[%W]") then
				table.insert(hits, where .. ": Null in " .. text)
			end
		end
		local function walk(v: any, path: string, seen: { [any]: boolean })
			if type(v) == "string" then
				look(path, v)
			elseif type(v) == "table" and not seen[v] then
				seen[v] = true
				for k, x in v do
					walk(x, path .. "." .. tostring(k), seen)
				end
			end
		end
		for name, mod in Config do
			walk(mod, name, {})
		end
		local fs = require("@lune/fs")
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(name, -5) == ".luau" and not string.find(path, "^src/config/") then
					for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
						line = string.gsub(line, '"[^"]*"', function(lit)
							look(path, lit)
							return '""'
						end)
					end
				end
			end
		end
		scan("src")
		for _, h in hits do
			check(false, "old Act 1 name: " .. h)
		end
		check(#hits == 0, "the new Act 1 only")
	end)

	test(
		"Lore 5: an old save mid-Act 1 lands on the new mission at the same index and keeps its rewards",
		function()
			local StoryPlan2 = StoryPlan
			-- a hero who cleared the old opening, Hold the Line and Signal Tower and picked twice (train, trust)
			local old = ProfileSchema.default()
			old.version = ProfileSchema.VERSION - 1
			local c = old.characters[1]
			c.created, c.level, c.bonusPoints = 1, 6, 5
			c.story.opening = 1
			c.story.missions = 7 -- 1, 2 and 3
			c.story.choices = { 1, 1, 0 }
			c.story.perks = 1 -- the old Echo Drone (spared the old core in a replay save)
			c.rep = { 250, 0, 120 }
			local back = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
			local st = back.characters[1].story
			check(
				st.missions == 7 and st.choices[1] == 1 and st.choices[2] == 1,
				"the bits and picks are kept"
			)
			check(StoryPlan2.nextMission(Config, st) == 4, "next up: mission 4, now The Copy")
			check(StoryPlan2.state(Config, st, 6, 4) == "open", "open at the same level")
			check(
				StoryPlan2.state(Config, st, 6, 3) == "done",
				"Framed counts as cleared (no second first-clear)"
			)
			check(not StoryPlan2.clear(st, 3), "a cleared index never pays its first clear again")
			check(back.characters[1].bonusPoints == 5, "Skill Points already earned stay")
			check(back.characters[1].rep[1] == 250 and back.characters[1].rep[3] == 120, "reputation stays")
			check(StoryPlan2.bit(st.perks, 1), "the Echo Drone stays")
			-- the old picks keep their meaning in the new slots: 1 the first mission choice, 2 the trust test
			check(
				StoryPlan2.flag(Config, st, "hero", "bridgeSaved"),
				"Save the Train reads as Save the Bridge"
			)
			check(StoryPlan2.flag(Config, st, "hero", "insiderTrusted"), "Trust Her stays Trust Her")
			-- the choice already made is not asked (or paid) again in its new mission
			check(not StoryPlan2.pick(Config, st, 1, 2, "hero"), "no second pick, no second Skill Points")
			check(
				st.choices[3] == 0 and StoryPlan2.pick(Config, st, 3, 1, "hero"),
				"the new Copy choice is open"
			)
			-- a hero who finished the old Act 1 has finished the new one
			local done = ProfileSchema.newCharacter().story
			done.missions = 63
			check(StoryPlan2.nextMission(Config, done) == nil, "all 6 cleared")
			check(StoryPlan2.canEnter(Config, done, 8, 6), "and Live can be replayed")
		end
	)

	test(
		"Lore 5: the Journal, markers, phone controls, safety, analytics and the Dev panel carry over",
		function()
			local svc = readFile("src/server/Services/MissionService.luau")
			check(
				string.find(svc, "run.m.minutes * 60 * 2 + 300", 1, true) ~= nil,
				"an abandoned run ends itself"
			)
			check(string.find(svc, '"mission_start"', 1, true) ~= nil, "mission_start is logged on entry")
			check(
				string.find(svc, '{ run.m.id, #run.members, run.sides[player] or "hero" }', 1, true) ~= nil,
				"mission events carry the new mission id and the side"
			)
			check(
				string.find(svc, 'Analytics.step(player, "Story", "act_done")', 1, true) ~= nil,
				"the funnel's end"
			)
			local AS = require("../src/shared/AnalyticsSchema")
			check(
				#AS.FUNNELS.Story == 4 and AS.FUNNELS.Story[4] == "act_done",
				"the Story funnel keeps its shape"
			)
			check(
				AS.EVENTS.mission_done[3] == "side" and AS.EVENTS.choice_pick[3] == "side",
				"events by side"
			)
			check(
				string.find(svc, "out.target = stepTarget(run, track, player)", 1, true) ~= nil,
				"each side's marker"
			)
			local hud = clientSources()["src/client/Ui/StoryHud.luau"]
			check(
				string.find(hud, "Hud.setFocus(if sceneFocus then {} else nil)", 1, true) ~= nil,
				"buttons step aside"
			)
			check(string.find(hud, "sceneText(scene", 1, true) ~= nil, "the beat's subtitles")
			local fx = clientSources()["src/client/Fx/StoryFx.luau"]
			check(string.find(fx, "Reduce flashing", 1, true) ~= nil, "no flashes in a camera beat")
			check(string.find(fx, "PLACEHOLDER ART", 1, true) ~= nil, "placeholder art is labelled")
			local journal = clientSources()["src/client/Ui/Journal.luau"]
			check(string.find(journal, "(PROLOGUE)", 1, true) ~= nil, "the Journal marks mission 1")
			local dev = clientSources()["src/client/Ui/DevPanel.luau"]
			check(
				string.find(dev, '"missionas"', 1, true) ~= nil
					and string.find(dev, '"missionstep"', 1, true) ~= nil,
				"Dev: each mission as each side, and each stage"
			)
			local ds = readFile("src/server/Services/DevService.luau")
			check(
				string.find(ds, "missionas = function", 1, true) ~= nil
					and string.find(ds, "MissionService.jumpStage", 1, true) ~= nil,
				"DevService"
			)
		end
	)
end

---------------------------------------------------------------------------
-- Lore step 6: the guides (nate's lore doc: a veteran Vigil hero in person, a hacker kid on the radio).
-- One line queue for every line (GuidePlan, GuideHud), Lodestar in the Vigil's HQ, Patch's open-world radio
---------------------------------------------------------------------------

do
	local GuidePlan = require("../src/shared/GuidePlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local SettingsRules = require("../src/shared/SettingsRules")
	local TouchLayout = require("../src/shared/TouchLayout")
	local S = Config.Story
	local Gd = S.guides

	test(
		"Lore 6: every guide line has a known speaker, both sides, the phone length cap, no free text",
		function()
			local bad = GuidePlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "every line is valid")
			local lines = GuidePlan.lines(Config)
			check(
				#lines >= 120,
				"the prologue, the missions, the radio and the talk (" .. #lines .. " lines)"
			)
			check(Gd.maxChars <= 120, "short enough for a phone's subtitle box")
			-- the three guides: their own portrait, name colour and blip (different blips)
			local blips = {}
			for _, who in { "lodestar", "patch", "crane" } do
				check(table.find(Gd.guides, who) ~= nil, who .. " is a guide")
				local sp = Gd.speakers[who]
				check(sp and sp.portrait and sp.portrait.bg and sp.portrait.skin, who .. ": a portrait")
				check(Config.Audio.sounds[sp.blip] ~= nil, who .. ": a blip sound")
				check(blips[sp.blip] == nil, who .. ": a blip of their own")
				blips[sp.blip] = true
			end
			check(Gd.speakers.patch.style == "radio", "Patch on the radio")
			check(Gd.speakers.lodestar.style == "person", "Lodestar in person")
			check(Gd.speakers.crane.style == "broadcast", "Crane's broadcast voice")
			check(Gd.tags.radio ~= nil and Gd.tags.broadcast ~= nil, "RADIO and ON AIR tags")
			for who, sp in Gd.speakers do
				check(Config.Audio.sounds[sp.blip] ~= nil, who .. ": its blip exists")
			end
			check(S.opening.speakers == nil, "one speaker table (guides.speakers)")
			-- no old names in any guide line
			local OLD = { "War-Frame", "War Frame", "Signal Tower", "The Informant", "Under the Docks" }
			for _, e in lines do
				for _, side in SIDES do
					local t = GuidePlan.lineText(e.line, side) or ""
					check(oldLore(t) == nil, e.where .. ": no old lore")
					for _, w in OLD do
						check(not string.find(t, w, 1, true), e.where .. ": no " .. w)
					end
				end
			end
			-- no free text: the guide code has no text box, and the radio and stage lines come from GuidePlan
			local src = clientSources()
			local hud = src["src/client/Ui/GuideHud.luau"]
			local cli = src["src/client/Controllers/GuideClient.luau"]
			check(
				not string.find(hud, "TextBox", 1, true) and not string.find(cli, "TextBox", 1, true),
				"no text box"
			)
			for call in string.gmatch(cli, "GuideHud%.say%(([^,]+,[^,]+),") do
				check(call == "l.who, l.text", "GuideClient says only fixed lines: " .. call)
			end
		end
	)

	test("Lore 6: the line queue never overlaps, skips cleanly and waits for camera beats", function()
		local Q = GuidePlan.queue()
		local t = 0
		check(GuidePlan.push(Q, { who = "patch", text = "One." }, t), "a story line")
		check(GuidePlan.push(Q, { who = "lodestar", text = "Two." }, t), "another story line waits")
		local a = GuidePlan.tick(Config, Q, t, false)
		check(a and a.text == "One." and Q.current == a, "the first starts")
		check(GuidePlan.tick(Config, Q, t + 0.5, false) == nil, "never two at once")
		local d = GuidePlan.duration(Config, "One.")
		check(d >= Gd.queue.min and d <= Gd.queue.max, "a sensible time on screen")
		check(GuidePlan.duration(Config, string.rep("x", 120)) == Gd.queue.max, "long lines cap out")
		-- skip: the next starts at once
		GuidePlan.skip(Q)
		local b = GuidePlan.tick(Config, Q, t + 1, false)
		check(b and b.text == "Two.", "a skip moves to the next line")
		check(
			GuidePlan.tick(Config, Q, t + 1 + d + 0.1, false) == nil and Q.current == nil,
			"then the box clears"
		)
		-- open-world lines wait while a camera beat runs, and only one waits
		check(GuidePlan.push(Q, { who = "patch", text = "World.", world = true }, 20), "a radio line")
		check(not GuidePlan.push(Q, { who = "patch", text = "Again.", world = true }, 20), "only one waits")
		check(GuidePlan.tick(Config, Q, 20, true) == nil, "paused for the camera beat")
		local w = GuidePlan.tick(Config, Q, 21, false)
		check(w and w.world, "it plays after the beat")
		-- a story line queued after the radio line goes before later radio lines; a beat cuts a radio line
		check(
			GuidePlan.tick(Config, Q, 21.5, true) == nil and Q.current == nil,
			"a camera beat cuts a radio line"
		)
		GuidePlan.push(Q, { who = "patch", text = "Late.", world = true }, 30)
		GuidePlan.push(Q, { who = "lodestar", text = "Story." }, 30)
		local s1 = GuidePlan.tick(Config, Q, 30, false)
		check(s1 and s1.text == "Story.", "story lines go before open-world ones")
		-- stale radio lines are dropped
		GuidePlan.skip(Q)
		check(GuidePlan.tick(Config, Q, 30 + Gd.queue.ttl + 1, false) == nil, "a stale radio line is dropped")
		-- a camera beat's timed line takes the box at once, and the beat's end drops it
		GuidePlan.push(Q, { who = "patch", text = "Long story line." }, 40)
		GuidePlan.tick(Config, Q, 40, false)
		GuidePlan.push(Q, { who = "crane", text = "Cut!", cut = true, hold = 3, tag = "beat1" }, 41)
		local c = GuidePlan.tick(Config, Q, 41, false)
		check(c and c.text == "Cut!" and Q.untilT == 44, "a timed line takes the box for its hold")
		GuidePlan.cancel(Q, "beat1")
		check(Q.current == nil, "the beat's end drops its line")
		-- due: the line for the moment, until the next (at most hold); a late join skips passed lines
		local list = { { at = 0.5, who = "patch", text = "a" }, { at = 4, who = "patch", text = "b" } }
		local i1, h1 = GuidePlan.due(Config, list, 0.6, 0)
		check(i1 == 1 and h1 and math.abs(h1 - 3.4) < 1e-6, "the first line until the second")
		check(GuidePlan.due(Config, list, 1, 1) == nil, "nothing new until the next")
		local i2, h2 = GuidePlan.due(Config, list, 4.2, 1)
		check(i2 == 2 and h2 and math.abs(h2 - (Gd.queue.hold - 0.2)) < 1e-6, "the last line holds")
		local i3, h3 = GuidePlan.due(Config, list, 30, 0)
		check(i3 == 2 and h3 == nil, "a late join shows nothing stale")
	end)

	test(
		"Lore 6: Patch's open-world radio: one line a 45 s at most, once-a-session lines, the setting",
		function()
			local R = GuidePlan.radio()
			local on = { on = true, busy = false }
			check(Gd.radio.gap >= 45, "never more than one line a ~45 s")
			check(GuidePlan.radioOk(Config, R, 100, "firstIncident", on), "the first incident")
			GuidePlan.radioMark(R, 100, "firstIncident")
			check(not GuidePlan.radioOk(Config, R, 120, "firstBoss", on), "too soon after the last line")
			check(GuidePlan.radioOk(Config, R, 100 + Gd.radio.gap, "firstBoss", on), "after the gap")
			check(
				not GuidePlan.radioOk(Config, R, 1000, "firstIncident", on),
				"the first incident once a session"
			)
			check(
				not GuidePlan.radioOk(Config, R, 1000, "firstBoss", { on = true, busy = true }),
				"never in a mission"
			)
			check(
				not GuidePlan.radioOk(Config, R, 1000, "firstBoss", { on = false, busy = false }),
				"the setting off"
			)
			GuidePlan.radioMark(R, 1000, "idle")
			check(
				not GuidePlan.radioOk(Config, R, 1000 + Gd.radio.gap, "idle", on),
				"the idle hint waits its repeat"
			)
			check(GuidePlan.radioOk(Config, R, 1000 + Gd.radio.idleRepeat, "idle", on), "then hints again")
			check(GuidePlan.radioOk(Config, R, 1000 + Gd.radio.gap, "unlock3", on), "a level-up line")
			GuidePlan.radioMark(R, 2000, "unlock3")
			check(not GuidePlan.radioOk(Config, R, 9000, "unlock3", on), "each unlock once")
			-- every trigger has a side-flavoured line
			for _, key in { "firstIncident", "firstBoss", "afterAct1" } do
				local h, v =
					GuidePlan.worldLine(Config, key, "hero"), GuidePlan.worldLine(Config, key, "villain")
				check(h and v and h.who == "patch" and h.text ~= v.text, key .. ": Patch, by side")
			end
			for num = 2, #S.missions do
				for _, key in { "unlock", "idle" } do
					local h, v =
						GuidePlan.worldLine(Config, key, "hero", num),
						GuidePlan.worldLine(Config, key, "villain", num)
					check(h and v and h.text ~= v.text, key .. " " .. num .. ": a line per side")
				end
			end
			-- level-ups at story levels: the level that opens the next mission, and only when it opens
			local story = { missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2), pinned = 0 }
			check(GuidePlan.unlockAt(Config, story, S.missions[3].minLevel) == 3, "Framed opens at its level")
			check(
				GuidePlan.unlockAt(Config, story, S.missions[4].minLevel) == nil,
				"The Copy waits for Framed"
			)
			check(GuidePlan.unlockAt(Config, story, 7) == nil, "no line at a level that opens nothing")
			check(GuidePlan.idleMission(Config, story, 1) == nil, "no idle hint below the mission's level")
			check(GuidePlan.idleMission(Config, story, 10) == 3, "an idle hint for the pinned mission")
			check(
				GuidePlan.idleMission(Config, { missions = story.missions, pinned = 2 }, 10) == nil,
				"not with a side quest pinned"
			)
			-- the Settings switch
			local key, idx = nil, 0
			for i, k in Config.Settings.keys do
				if k.id == "guideRadio" then
					key, idx = k, i
				end
			end
			check(
				key and key.name == "Guide radio" and key.kind == "toggle" and key.default == 1,
				"Guide radio, on by default"
			)
			-- (keys only ever append: lore step 7's Camera motion came after it, so its index stays 12)
			check(idx == 12 and #Config.Settings.keys <= 16, "its own key, inside Settings.Set's range")
			check(SettingsRules.defaults(Config).guideRadio == 1, "the save's default")
			local cli = clientSources()["src/client/Controllers/GuideClient.luau"]
			check(
				string.find(cli, 'SettingsClient.on("guideRadio")', 1, true) ~= nil,
				"the radio reads the switch"
			)
		end
	)

	test(
		"Lore 6: Lodestar's look validates; his talk follows the story and keeps away from the Syndicate",
		function()
			local CreatorRules = require("../src/shared/CreatorRules")
			local profile = ProfileSchema.default()
			for _, p in CreatorRules.index(Config).list do
				if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
					CreatorRules.grant(profile, p)
				end
			end
			local look = FakeRules.lookFrom(Config, S.opening.lodestar.look, "Lodestar")
			local ok, why = CreatorRules.validate(Config, profile, look)
			check(ok, "Lodestar's look validates through CreatorRules (" .. tostring(why) .. ")")
			local fresh = { missions = StoryPlan.setBit(0, 1), pinned = 0 }
			local a1 = GuidePlan.talk(Config, fresh, "hero", 1)
			local a2 = GuidePlan.talk(Config, fresh, "hero", 2)
			local a4 = GuidePlan.talk(Config, fresh, "hero", 1 + #Gd.lodestar.talk[1].lines)
			check(a1 and a2 and a1.who == "lodestar" and a1.text ~= a2.text, "a rotation of lines")
			check(a4 and a4.text == a1.text, "a short fixed rotation")
			local all = 0
			for n = 1, #S.missions do
				all = StoryPlan.setBit(all, n)
			end
			local done = GuidePlan.talk(Config, { missions = all, pinned = 0 }, "hero", 1)
			check(done and done.text ~= a1.text, "the lines change with the story (Act 1 done)")
			local tiers = {}
			for n = 1, #S.missions do
				local m = 0
				for k = 1, n do
					m = StoryPlan.setBit(m, k)
				end
				tiers[(GuidePlan.talk(Config, { missions = m, pinned = 0 }, "hero", 1) :: any).text] = true
			end
			local count = 0
			for _ in tiers do
				count += 1
			end
			check(count >= 3, "at least three stages of the story")
			check(GuidePlan.talk(Config, fresh, "villain", 1) == nil, "no HQ talk for the Dread Syndicate")
			local cli = clientSources()["src/client/Controllers/GuideClient.luau"]
			check(string.find(cli, 'state.side ~= "villain"', 1, true) ~= nil, "he keeps out of the Foundry")
			check(string.find(cli, "PrologueFx.lodestarRig", 1, true) ~= nil, "the one reusable figure")
			check(string.find(cli, "ProximityPrompt", 1, true) ~= nil, "a Talk prompt")
			-- where the doc puts him: the prologue's rescue and the safehouse (where the Syndicate's deal is offered)
			check(
				table.find(Gd.appears.lodestar, 1) and table.find(Gd.appears.lodestar, 2),
				"the prologue and Safehouse"
			)
			local offer = S.missions[2].villain[5]
			check(offer.kind == "scene" and offer.lodestar ~= nil, "he stands where the deal is offered")
		end
	)

	test(
		"Lore 6: every mission and the prologue has its guide lines per side (Patch, and Lodestar where the doc puts him)",
		function()
			for num, m in S.missions do
				for _, side in SIDES do
					local c = GuidePlan.coverage(Config, num, side)
					check((c.patch or 0) >= 1, m.id .. " " .. side .. ": Patch speaks")
					if table.find(Gd.appears.lodestar, num) then
						check((c.lodestar or 0) >= 1, m.id .. " " .. side .. ": Lodestar speaks")
					end
				end
			end
			for _, num in Gd.appears.patch do
				check(S.missions[num] ~= nil, "Patch's missions exist")
			end
			-- key beats: every playable stage (and branch) has a guide line for each side as it starts
			local PLAY = { scene = false, choice = false, branch = false, none = false }
			for _, m in S.missions do
				for _, side in SIDES do
					local key = StoryPlan.sideKey(side)
					local steps = table.clone(m[key] or {})
					for _, b in (m.branches and m.branches[key]) or {} do
						table.insert(steps, b)
					end
					for i, st in steps do
						if PLAY[st.kind] == nil then
							check(
								#GuidePlan.stageLines(st, side) >= 1,
								string.format("%s %s step %d (%s): a line", m.id, side, i, st.kind)
							)
						end
					end
				end
			end
			-- the client finds a stage from its MissionState, branches too
			local st = GuidePlan.stageFor(
				Config,
				{ num = 3, step = 6, side = "hero", kind = "chase", text = "Chase Radiant down" }
			)
			check(st ~= nil and st.radio ~= nil, "a branch stage")
			check(
				GuidePlan.stageFor(Config, { num = 2, step = 2, side = "villain", kind = "break" })
					== S.missions[2].villain[2],
				"a side's stage"
			)
			check(
				GuidePlan.stageFor(Config, { num = 2, step = 2, side = "villain", kind = "defeat" }) == nil,
				"a mismatch is nothing"
			)
			check(
				GuidePlan.stageFor(Config, { num = 150, step = 1, side = "hero", kind = "defeat" }) == nil,
				"custom runs have none"
			)
		end
	)

	test("Lore 6: the line box stays clear of the phone controls", function()
		local devices = {
			{ "iPhone SE", 667, 375, true },
			{ "big phone", 844, 390, true },
			{ "small phone", 568, 320, true },
			{ "tablet", 1024, 768, true },
			{ "PC", 1280, 720, false },
			{ "PC wide", 1920, 1080, false },
		}
		for _, d in devices do
			for _, left in { false, true } do
				local opts = { touch = d[4], leftHanded = left, user = 1, present = { Block = true } }
				local b = GuidePlan.box(Config, d[2], d[3], opts, false)
				local where = d[1] .. (if left then " left-handed" else "")
				for _, o in GuidePlan.obstacles(Config, d[2], d[3], opts) do
					check(
						not GuidePlan.overlaps(b, o),
						where .. ": clear of the buttons, status corner and top row"
					)
				end
				check(
					b.x >= 0 and b.y >= 0 and b.x + b.w <= d[2] and b.y + b.h <= d[3],
					where .. ": on screen"
				)
				check(b.w >= 200, where .. ": wide enough to read")
				if d[4] and b.tap then
					local mode = if left then "left" else "default"
					check(
						not GuidePlan.overlaps(b, TouchLayout.stickZone(d[2], d[3], mode)),
						where .. ": taps never steal the stick"
					)
				end
				-- a tracker to keep clear of
				local extra = { { x = d[2] / 2 - 150, y = 60, w = 300, h = 64 } }
				local b2 = GuidePlan.box(Config, d[2], d[3], opts, false, extra)
				if b2.w >= Gd.box.minW then
					check(not GuidePlan.overlaps(b2, extra[1]), where .. ": clear of the story tracker")
				end
			end
			local c = GuidePlan.box(Config, d[2], d[3], { touch = d[4] }, true)
			check(
				c.y >= d[3] * Gd.box.letterbox and c.w <= Gd.box.maxW,
				d[1] .. ": under the letterbox on a beat"
			)
		end
	end)

	test(
		"Lore 6: wiring: StoryHud feeds the queue, blips per speaker, reduce flashing, Dev panel, init",
		function()
			local src = clientSources()
			local hud = src["src/client/Ui/GuideHud.luau"]
			local story = src["src/client/Ui/StoryHud.luau"]
			check(
				string.find(story, "GuideHud.timeline(lineCache, lineCache.list, t)", 1, true) ~= nil,
				"the beats' lines go to the queue"
			)
			check(string.find(story, "GuideHud.setScene(", 1, true) ~= nil, "camera beats pause the radio")
			check(string.find(story, "GuideHud.keepClear(tracker)", 1, true) ~= nil, "clear of the tracker")
			check(not string.find(story, "Subtitle", 1, true), "the old subtitle box is gone")
			check(string.find(hud, "AudioController.play(sp.blip)", 1, true) ~= nil, "each speaker's blip")
			check(string.find(hud, 'SettingsClient.on("reduceFlashing")', 1, true) ~= nil, "reduce flashing")
			check(string.find(hud, "PLACEHOLDER ART", 1, true) ~= nil, "placeholder portraits are labelled")
			check(string.find(hud, "GuidePlan.box(", 1, true) ~= nil, "the box follows the phone layout")
			for _, path in { "src/client/Fx/PrologueFx.luau", "src/client/Fx/StoryFx.luau" } do
				check(
					not string.find(src[path], '"radio" else "ui"', 1, true),
					path .. ": no ad hoc blip left"
				)
			end
			local dev = src["src/client/Ui/DevPanel.luau"]
			check(string.find(dev, "GuideHud.sample(", 1, true) ~= nil, "Dev: a sample line per speaker")
			check(string.find(dev, "GuideClient.spawnLodestar()", 1, true) ~= nil, "Dev: Lodestar near you")
			local boot = src["src/client/init.client.luau"]
			check(
				string.find(boot, "GuideHud.init()", 1, true) ~= nil
					and string.find(boot, "GuideClient.init()", 1, true) ~= nil,
				"both start"
			)
			check(
				string.find(
					readFile("src/config/Audio.luau"),
					"PLACEHOLDER SOUND: built-in clips until real voice",
					1,
					true
				) ~= nil,
				"placeholder blips are labelled"
			)
		end
	)
end

test("Weighty hits: flash, sound, sparks, knockback, shake and freeze on every hit you land", function()
	local W = Config.Combat.weight
	check(Config.Fx.hitFlash >= 0.1, "the robot turns white for at least 0.1 s")
	check(
		Config.Combat.hitPause >= 0.05 and Config.Combat.critPause > Config.Combat.hitPause,
		"a real hit-stop, bigger on crits"
	)
	check(W.knock > 0 and W.knockHeavy > W.knock, "knockback, more on heavy hits")
	check(
		W.shake[2] > 0 and W.shakeHeavy[2] > W.shake[2] and W.shakeHeavy[1] >= W.shake[1],
		"shake, more on heavy hits"
	)
	check(
		W.flinchHeavy > W.flinchStuds and W.flinch > 0 and W.sparks > 0 and W.thudGap > 0,
		"recoil and sparks"
	)
	local I = Config.Audio.impact
	check(I and I.hit and I.heavy and I.clank and I.hit.fallback ~= nil, "the impact thud has sounds")
	-- the server shove moves a robot by the configured distance on open ground
	local sim = robotSim()
	local e = EnemySim.spawn(sim, "BurglarBot", -40, 0, 0, 1) :: any
	local x0 = e.x
	EnemySim.knock(sim, e.id, -1, 0, W.knock)
	check(math.abs((x0 - e.x) - W.knock) < 1e-6, "a normal hit shoves it")
	-- wiring
	local svc = readFile("src/server/Services/CombatService.luau")
	check(
		string.find(svc, "KnockRules.plan(C.knock", 1, true) ~= nil
			and string.find(svc, "r.k ~= K.TICK", 1, true) ~= nil,
		"the server shoves on hits, not ticks"
	)
	local cc = clientSources()["src/client/Controllers/CombatClient.luau"]
	check(string.find(cc, "EnemyRenderer.impact(", 1, true) ~= nil, "the robot freezes and recoils")
	check(string.find(cc, "CombatFx.hitSparks(", 1, true) ~= nil, "sparks spray out")
	check(string.find(cc, "IMPACT.heavy else IMPACT.hit", 1, true) ~= nil, "the thud plays")
	check(string.find(cc, "W.shakeHeavy else W.shake", 1, true) ~= nil, "the camera shakes")
	check(
		string.find(cc, "not CameraController.reduceMotion", 1, true) ~= nil,
		"reduce flashing turns off the freeze"
	)
end)

test(
	"Vigil HQ: The Safehouse under the plaza, its stairwell door, the hideout cell, no Beacon Tower text",
	function()
		local HqRules = require("../src/shared/HqRules")
		local ContestRules = require("../src/shared/ContestRules")
		local fs = require("@lune/fs")
		local H = Config.Hq
		-- names: the Vigil's HQ is The Safehouse (save key "hero"); the Foundry keeps its name
		check(
			H.names.hero == "The Safehouse" and H.names.villain == "The Foundry",
			"The Safehouse and The Foundry"
		)
		check(Config.World.beacons[1].name == "Crane's Hero Hall", "the plaza beacon is Crane's Hero Hall")
		-- no "Beacon Tower" in any string a player can read (string literals outside comments, every source)
		local function literals(line: string): { string }
			local out, i, q, start = {}, 1, nil :: string?, 0
			while i <= #line do
				local ch = string.sub(line, i, i)
				if q then
					if ch == "\\" then
						i += 1
					elseif ch == q then
						table.insert(out, string.sub(line, start, i - 1))
						q = nil
					end
				elseif ch == '"' or ch == "'" then
					q, start = ch, i + 1
				elseif string.sub(line, i, i + 1) == "--" then
					break
				end
				i += 1
			end
			return out
		end
		local hits = {}
		local function walk(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					walk(path)
				elseif string.sub(name, -5) == ".luau" then
					for n, line in string.split(fs.readFile(path), "\n") do
						for _, s in literals(line) do
							if string.find(s, "Beacon Tower", 1, true) then
								table.insert(hits, path .. ":" .. n)
							end
						end
					end
				end
			end
		end
		walk("src")
		check(#hits == 0, "no Beacon Tower in player text: " .. table.concat(hits, ", "))

		-- the door: at the plaza's edge, outside the Hall, the open squares, the ceremony and the chase row
		local L = world.downtown
		local bt = L.beacon
		local hd = HqRules.heroDoor(Config, world) :: any
		check(hd ~= nil, "the Vigil door exists")
		if hd then
			local half = Config.City.downtown.block / 2
			local edge = math.max(math.abs(hd.x - bt.x), math.abs(hd.z - bt.z))
			check(
				edge <= half and edge >= half - 15,
				string.format("at the plaza's edge (%.0f of %.0f)", edge, half)
			)
			local d = H.door.size[3]
			-- the stairwell head's footprint: from the door back toward the edge
			local fx, fz = hd.x - hd.fx * d / 2, hd.z - hd.fz * d / 2
			local w2 = math.max(H.door.size[1], d) / 2
			local hall = Config.City.downtown.beacon.width / 2
			check(
				math.abs(fx - bt.x) > hall + w2 + 10 or math.abs(fz - bt.z) > hall + w2 + 10,
				"outside Crane's Hero Hall"
			)
			check(
				math.abs(fx - bt.x) + w2 <= half and math.abs(fz - bt.z) + w2 <= half,
				"on the plaza, not the street"
			)
			for _, o in L.open do
				check(
					math.abs(hd.x - o.x) > o.size / 2 + 20 or math.abs(hd.z - o.z) > o.size / 2 + 20,
					"clear of " .. o.id
				)
			end
			for i, r in L.row do
				check(
					math.abs(hd.x - r.x) > r.sx / 2 + 40 or math.abs(hd.z - r.z) > r.sz / 2 + 40,
					"clear of chase roof " .. i
				)
			end
			for _, b in world.buildings do
				check(
					math.abs(fx - b.x) >= b.sx / 2 + w2 or math.abs(fz - b.z) >= b.sz / 2 + w2,
					"no building on the stairwell"
				)
			end
			local door = { hd.x, 0, hd.z }
			for k = 1, 6 do
				local r = OpeningPlan.route(Config, world, Rng.new(k))
				check(r ~= nil, "the prologue route")
				if r then
					check(flat(door, r.stage) > 45, "clear of the ceremony stage")
					local nearest = math.huge
					for _, p in r.crowd do
						nearest = math.min(nearest, flat(door, p))
					end
					check(nearest > 30, string.format("clear of the ceremony crowd (%.0f)", nearest))
					for _, p in { r.start, r.spark, r.kid, r.entrance, r.landing } do
						check(flat(door, p) > 25, "clear of the prologue's points")
					end
					for _, p in r.roofs do
						check(flat(door, p) > 60, "clear of the chase")
					end
				end
			end
			local cx, cz = ContestRules.stage(Config.Contest, bt.x, bt.z)
			check(flat(door, { cx, 0, cz }) > 40, "clear of the contest stage")
			local spawnClear = true
			for _, s in world.spawns or {} do
				if math.abs(s.x - hd.x) < 10 and math.abs(s.z - hd.z) < 10 then
					spawnClear = false
				end
			end
			check(spawnClear, "clear of the hero spawns")
		end
		check(H.doorRange == 14, "same door range")

		-- the cell: the same stations, rooms, levels and size; the hideout look underground, no windows
		local S = H.stations
		local want = {
			command = { 0, -36 },
			gizmo = { -36, -12 },
			mannequins = { 36, -12 },
			training = { -30, 30 },
			trophies = { 30, 30 },
			legends = { 0, 44 },
			scanner = { -36, 12 },
			exit = { 0, -54 },
		}
		for k, v in want do
			check(S[k] and S[k][1] == v[1] and S[k][2] == v[2], "station " .. k .. " unchanged")
		end
		check(H.cell.size == 120 and H.cell.wall == 40 and H.stationRange == 12, "same cell")
		check(H.levels.drones == 5 and H.levels.bossSim == 3 and H.legacy.statues == 20, "same levels")
		local pieces = HqRules.hideout(Config)
		local count = {}
		local half = H.cell.size / 2
		for _, p in pieces do
			count[p.name] = (count[p.name] or 0) + 1
			local n = string.lower(p.name)
			check(
				not string.find(n, "window") and not string.find(n, "sky") and not string.find(n, "glass"),
				"no window parts: " .. p.name
			)
			check(p.mat ~= "Glass" and p.color ~= "glass" and p.color ~= "window", "no glass: " .. p.name)
			check(Config.City.palette[p.color] ~= nil, "palette colour " .. p.color)
			check(
				p.mat == nil
					or p.mat == "Concrete"
					or p.mat == "Metal"
					or p.mat == "DiamondPlate"
					or p.mat == "Neon",
				"material " .. tostring(p.mat)
			)
			check(
				math.abs(p.x) <= half + 1.5
					and math.abs(p.z) <= half + 1.5
					and p.y + p.sy / 2 <= H.cell.wall + 1,
				"inside the cell: " .. p.name
			)
			-- nothing low stands on a station pad or where Lodestar waits
			if p.name ~= "floor" and p.y - p.sy / 2 < 6 then
				local spots = { Config.Story.guides.lodestar.at }
				for _, v in S do
					table.insert(spots, v)
				end
				for _, s in spots do
					check(
						math.abs(p.x - s[1]) >= p.sx / 2 + 4 or math.abs(p.z - s[2]) >= p.sz / 2 + 4,
						p.name .. " is clear of the pads"
					)
				end
			end
		end
		check((count.wall or 0) == 4 and (count.ceiling or 0) >= 1, "concrete walls and a ceiling")
		check(
			(count.pillar or 0) >= 2 and (count.pilaster or 0) >= 4 and (count.beam or 0) >= 1,
			"pillars and beams"
		)
		check((count.pipe or 0) >= 8 and (count.cableTray or 0) >= 8, "pipes and cable trays on every wall")
		check((count.workLamp or 0) >= 10 and (count.monitorScreen or 0) >= 6, "work lamps and monitors")
		check((count.mapScreen or 0) == 1 and (count.mapDistrict or 0) == 9, "the city map wall")
		local ceiling = 0
		for _, p in pieces do
			if p.name == "ceiling" then
				ceiling += p.sx * p.sz
			end
		end
		check(
			ceiling >= H.cell.size ^ 2 * 0.95 and ceiling < H.cell.size ^ 2,
			"a ceiling, open only over the stair"
		)
		-- the stair arrives from above at the entrance: its foot beside the Exit, its top at the ceiling
		local foot, top = math.huge, 0
		for _, p in pieces do
			if p.name == "stairStep" then
				foot = math.min(foot, math.sqrt((p.x - S.exit[1]) ^ 2 + (p.z - S.exit[2]) ^ 2))
				top = math.max(top, p.y + p.sy / 2)
			end
		end
		check(
			(count.stairStep or 0) == 12 and foot < 16,
			string.format("the stair's foot is at the Exit (%.0f)", foot)
		)
		check(
			math.abs(top - H.hideout.height) < 0.01 and (count.shaft or 0) == 5,
			"the stair climbs up a shaft"
		)

		-- mission 2's Safehouse pocket wears the same look: the hideout's walls and wall kit
		local dungeon = PocketLayout.build(Config, 2, "dungeon")
		local kit = HqRules.wallKit(Config, 376)
		local decor, wallC = 0, 0
		for _, b in dungeon.boxes do
			if b.tag == "decor" then
				decor += 1
				check(b.ghost == true, "decor is walk-through")
			elseif b.kind == "building" and b.color == H.hideout.colors.wall then
				wallC += 1
			end
		end
		-- (the hideout art pass) each run piece is cut into module-long boxes, one under each HideRun module
		local HideoutKit = require("../src/shared/HideoutKit")
		local placed: { any } = {}
		HqRules.placeKit(placed, kit, 0, 58, 1, 0, 0, -1)
		local cuts = math.max(1, math.floor(placed[1].run.len / HideoutKit.MODULE + 0.5))
		local expect = 0
		for _, p in kit do
			expect += if HideoutKit.PIECES[p.name] == "HideRun" then cuts else 1
		end
		check(
			decor == expect * 2,
			string.format("the wall kit on both tunnel walls (%d of %d)", decor, expect * 2)
		)
		check(wallC >= 7, "the tunnels have the hideout's walls")
		local room = dungeon.lists.rooms[3]
		near(
			PocketLayout.heightAt(dungeon, room[1], dungeon.cz + 56),
			dungeon.floorY,
			0.01,
			"robots never stand on pipes"
		)

		-- wiring: the cell draws the hideout for the Vigil and the Foundry as ever; the stairwell replaces the tower door
		local hc = readFile("src/client/Controllers/HqClient.luau")
		check(string.find(hc, "HqRules.hideout(Config)", 1, true) ~= nil, "HqClient draws the hideout")
		check(
			string.find(hc, 'if state.side == "villain" then\n\t\tbuildRoom(f, colors)', 1, true) ~= nil,
			"the Foundry as ever"
		)
		check(string.find(hc, "H.door.marker", 1, true) ~= nil, "the Vigil-only marker")
		local hs = readFile("src/server/Services/HqService.luau")
		check(
			string.find(hs, "HqRules.heroDoor(Config, world)", 1, true) ~= nil,
			"the service door at the plaza edge"
		)
		check(string.find(hs, 'makeDoor("villain"', 1, true) ~= nil, "the Foundry door unchanged")
		check(string.find(hs, "bt.z - 18", 1, true) == nil, "no door at the Hall's foot")
		check(world.spots.foundryDoor ~= nil, "the Foundry door spot")
		local cb = readFile("src/server/Services/CityBuilder.luau")
		check(
			string.find(cb, "HqRules.heroDoor(Config, world)", 1, true) ~= nil,
			"the map's Safehouse is the stairwell"
		)
	end
)

---------------------------------------------------------------------------
-- Lore step 7: the cinematic layer (Config.Cinema, Shared.CinemaPlan, Shared.NewsPlan; CinemaClient,
-- CinemaHud, NewsHud, FinisherFx; CinemaService, NewsService)
---------------------------------------------------------------------------

do
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local NewsPlan = require("../src/shared/NewsPlan")
	local CreatorRules = require("../src/shared/CreatorRules")
	local Ci = Config.Cinema
	local OPB = Config.Story.opening.beats

	test(
		"Lore 7: named scene bits are 0 to 15, the extra 120 to 127 and 128 to 255, never a mission's",
		function()
			local M, X, W = Ci.missionBits, Ci.extraBits, Ci.wideBits
			check(
				X ~= nil and X.from == M.base + M.missions * M.perMission and X.to == 127,
				"the extra bits sit above the missions'"
			)
			check(
				W ~= nil and W.from == X.to + 1 and W.to == 255,
				"the wide bits are the seen set's second half"
			)
			check(W.to < ProfileSchema.SEEN_WORDS * 32, "and fit the save's seen set")
			for _, b in { 0, 15, 120, 127, 128, 200, 255 } do
				check(CinemaPlan.namedBit(Config, b), b .. " is named")
			end
			for _, b in { -1, 16, 119, 256, 12.5, 130.5 } do
				check(not CinemaPlan.namedBit(Config, b), b .. " is not named")
			end
		end
	)

	test("Save v12: the seen set gets its own 8 words; a v11 save keeps every bit", function()
		local serde = require("@lune/serde")
		local Bits = ProfileSchema.Bits
		check(ProfileSchema.VERSION >= 12, "save version 12 or later")
		check(ProfileSchema.SEEN_WORDS == 8 and ProfileSchema.SMALL_WORDS == 4, "8 seen words; titles keep 4")
		local fresh = ProfileSchema.default()
		check(#fresh.seen == ProfileSchema.SEEN_WORDS, "a new save has 256 seen bits")
		check(
			#fresh.titles == ProfileSchema.SMALL_WORDS and #fresh.emotes == ProfileSchema.SMALL_WORDS,
			"titles and emotes unchanged"
		)
		-- a v11 save with 4 words and bits all over them (a named, a mission, the extra range's last)
		local old = ProfileSchema.default()
		old.version = 11
		old.seen = { 0, 0, 0, 0 }
		local bits = { 0, 5, 15, 16, 63, 64, 100, 119, 120, 124, 127 }
		for _, b in bits do
			Bits.set(old.seen, b, true)
		end
		old.titles = { 7, 0, 0, 0 }
		local p = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
		check(p.version == ProfileSchema.VERSION, "loads at the current version")
		check(#p.seen == ProfileSchema.SEEN_WORDS, "padded to 8 words")
		for _, b in bits do
			check(Bits.get(p.seen, b), "bit " .. b .. " is kept")
		end
		check(#Bits.list(p.seen) == #bits, "and no bit appears")
		for k = 5, 8 do
			check(p.seen[k] == 0, "word " .. k .. " starts empty")
		end
		check(p.titles[1] == 7 and #p.titles == ProfileSchema.SMALL_WORDS, "titles are untouched")
		-- a bit above 127 round-trips through the save and the client view
		Bits.set(p.seen, 128, true)
		Bits.set(p.seen, 200, true)
		Bits.set(p.seen, 255, true)
		local back = ProfileSchema.load(serde.decode("json", serde.encode("json", p)))
		for _, b in { 128, 200, 255, 127, 0 } do
			check(Bits.get(back.seen, b), "bit " .. b .. " round-trips")
		end
		local view = ProfileSchema.clientView(back)
		for _, b in { 128, 200, 255 } do
			check(CinemaPlan.seen(view.seen, b), "the client view carries bit " .. b)
		end
		-- repair: short, broken or missing seen lists
		local r = ProfileSchema.default()
		r.seen = { 3 }
		local rr = ProfileSchema.load(serde.decode("json", serde.encode("json", r)))
		check(#rr.seen == 8 and rr.seen[1] == 3 and rr.seen[8] == 0, "a short list pads with 0")
		local r2 = ProfileSchema.default()
		r2.seen = { -4, "x", 1.5, 2 ^ 40, 9, 0, 0, 0, 0, 0, 77 }
		local rr2 = ProfileSchema.load(r2)
		check(
			#rr2.seen == 8 and rr2.seen[1] == 0 and rr2.seen[3] == 1 and rr2.seen[5] == 9,
			"bad words clean in place"
		)
		check(rr2.seen[4] == 0, "a word past 32 bits is dropped")
		local r3 = ProfileSchema.default()
		r3.seen = nil
		check(#ProfileSchema.load(r3).seen == 8, "a missing list comes back empty")
		local r4 = ProfileSchema.default()
		r4.version = 11
		r4.seen = "bad"
		check(#ProfileSchema.load(r4).seen == 8, "a broken v11 set repairs")
		-- the device may send a scene's bit up to 255
		local R = require("../src/shared/Remotes")
		local sch = R.SceneSeen.schema[1]
		check(sch.max == 255, "SceneSeen takes bits to 255")
	end)

	test("Lore 7: every scene is well formed, 5 to 20 s, with a bit of its own in the save", function()
		local bits = {}
		for id, sc in Ci.scenes do
			check(type(sc.bit) == "number" and CinemaPlan.namedBit(Config, sc.bit), id .. ": a named bit")
			check(not bits[sc.bit], id .. ": its bit is its own")
			bits[sc.bit] = true
			local secs = if sc.beat then OPB[sc.beat] else CinemaPlan.length(sc)
			local ok, why = CinemaPlan.check(Config, sc, secs)
			check(ok, id .. ": " .. tostring(why))
			if sc.beat then
				check(OpeningPlan.CUT[sc.beat] == true, id .. ": a prologue camera beat")
			end
			if sc.long then
				check(id == "ceremony" and secs <= 30, "only the Ceremony keeps nate's longer beat")
			end
			if sc.comic then
				local pg = Ci.comic.pages[sc.comic]
				check(pg ~= nil and #pg.panels >= 3 and #pg.panels <= 5, id .. ": a page of 3 to 5 panels")
				for i, pn in pg.panels do
					check(
						pn.at < secs and type(pn.caption) == "string" and #pn.caption > 0,
						id .. " panel " .. i
					)
				end
			end
		end
		for step in OpeningPlan.CUT do
			check(
				Ci.scenes[step] ~= nil and Ci.scenes[step].beat == step,
				step .. ": every CUT beat is a scene"
			)
		end
		-- every mission camera beat: its own bit above the named ones, under 128, and 5 to 20 s
		local mb = {}
		local n = 0
		for num, m in Config.Story.missions do
			for _, list in { m.hero or {}, m.villain or {} } do
				for stage, st in list do
					if st.kind == "scene" then
						local bit = CinemaPlan.missionBit(Config, num, stage)
						check(
							bit ~= nil and bit >= Ci.missionBits.base and bit < 128,
							"mission " .. num .. " stage " .. stage
						)
						check(not bits[bit :: number], "a mission bit never reuses a named one")
						mb[bit :: number] = true
						n += 1
						local ok, why = CinemaPlan.check(Config, { seconds = st.seconds })
						check(ok, "mission " .. num .. " stage " .. stage .. ": " .. tostring(why))
					end
				end
			end
		end
		check(n >= 10, "the Act 1 camera beats are counted (" .. n .. ")")
		check(
			CinemaPlan.missionBit(Config, 1, 1) == 16 and CinemaPlan.missionBit(Config, 2, 1) == 24,
			"stable bits"
		)
		check(
			CinemaPlan.missionBit(Config, 14, 1) == nil and CinemaPlan.missionBit(Config, 2, 9) == nil,
			"range"
		)
		local maxBit =
			CinemaPlan.missionBit(Config, Ci.missionBits.missions, Ci.missionBits.perMission) :: number
		check(maxBit < ProfileSchema.SEEN_WORDS * 32, "every bit fits the save's seen set")
		-- a bad scene is caught
		check(not CinemaPlan.check(Config, { seconds = 3 }), "too short")
		check(not CinemaPlan.check(Config, { seconds = 25 }), "too long")
		check(not CinemaPlan.check(Config, {
			seconds = 8,
			shots = { { kind = "cut", t0 = 0, t1 = 4, from = { 0, 0, 0 }, at = { 1, 0, 0 } } },
		}), "shots must fill the scene")
		check(not CinemaPlan.check(Config, {
			seconds = 8,
			shots = { { kind = "spin", t0 = 0, t1 = 8, from = { 0, 0, 0 }, at = { 1, 0, 0 } } },
		}), "unknown shot kind")
	end)

	test("Lore 7: shots: cut, dolly, orbit and look sample into one buffer; at() picks the shot", function()
		local out = table.create(6, 0)
		local dolly = {
			kind = "dolly",
			t0 = 0,
			t1 = 4,
			from = { 0, 0, 0 },
			to = { 10, 0, 0 },
			at = { 0, 0, -5 },
			at2 = { 0, 10, -5 },
		}
		local r = CinemaPlan.sample(dolly :: any, 0.5, out)
		check(r == out, "the same buffer comes back (no new table)")
		near(out[1], 5, 1e-6, "dolly halfway")
		near(out[5], 5, 1e-6, "its look pans halfway")
		CinemaPlan.sample(
			{ kind = "cut", t0 = 0, t1 = 1, from = { 1, 2, 3 }, at = { 4, 5, 6 }, to = { 9, 9, 9 } } :: any,
			0.7,
			out
		)
		check(out[1] == 1 and out[4] == 4, "a cut stays put")
		CinemaPlan.sample(
			{ kind = "look", t0 = 0, t1 = 1, from = { 1, 2, 3 }, at = { 0, 0, 0 }, at2 = { 10, 0, 0 } } :: any,
			1,
			out
		)
		check(out[1] == 1 and out[4] == 10, "a look pans from one spot")
		CinemaPlan.sample(
			{
				kind = "orbit",
				t0 = 0,
				t1 = 1,
				center = { 0, 0, 0 },
				radius = 10,
				height = 4,
				yaw0 = 0,
				yaw1 = math.pi / 2,
				lift = 2,
			} :: any,
			1,
			out
		)
		near(out[1], 10, 1e-6, "orbit a quarter round")
		near(out[2], 4, 1e-6, "at its height")
		near(out[5], 2, 1e-6, "looking at the centre's lift")
		local shots = {
			{ kind = "cut", t0 = 0, t1 = 2, from = { 0, 0, 0 }, at = { 0, 0, 1 } },
			{ kind = "dolly", t0 = 2, t1 = 6, from = { 0, 0, 0 }, to = { 4, 0, 0 }, at = { 0, 0, 1 } },
		}
		local s, k = CinemaPlan.at(shots :: any, 4)
		check(s == shots[2] and math.abs(k - 0.5) < 1e-6, "the second shot halfway (eased)")
		local last, k2 = CinemaPlan.at(shots :: any, 99)
		check(last == shots[2] and k2 == 1, "after the end: the last frame holds")
		local moved = CinemaPlan.around(shots :: any, 100, 0, 0)
		check(moved[2].to[1] == 104 and shots[2].to[1] == 4, "around() offsets a copy")
		-- the prologue's beats and the missions' play through the one player (no camera code left in them)
		local src = clientSources()
		for _, path in { "src/client/Fx/PrologueFx.luau", "src/client/Fx/StoryFx.luau" } do
			check(
				string.find(src[path], "CinemaClient.play(", 1, true) ~= nil,
				path .. ": plays through CinemaClient"
			)
			check(not string.find(src[path], "CameraType", 1, true), path .. ": no camera of its own")
		end
		local cc = src["src/client/Controllers/CinemaClient.luau"]
		check(
			string.find(cc, "CinemaPlan.sample(shot, k, buf)", 1, true) ~= nil,
			"the player samples into its buffer"
		)
		local stepAt = string.find(cc, "local function step(dt: number)", 1, true) :: number
		local stepEnd = string.find(cc, "function CinemaClient.init()", 1, true) :: number
		local body = string.sub(cc, stepAt, stepEnd)
		check(not string.find(body, "{", 1, true), "no new tables in the camera step")
		check(
			not string.find(src["src/client/Ui/StoryHud.luau"], "LetterTop", 1, true),
			"one letterbox (CinemaHud's)"
		)
		check(
			string.find(src["src/client/Ui/CinemaHud.luau"], "LetterTop", 1, true) ~= nil,
			"CinemaHud draws it"
		)
	end)

	test("Lore 7: SKIP only once the save has seen the scene; device scenes only in safe moments", function()
		check(not CinemaPlan.canSkip(Config, {}, 0, 5), "never the first time")
		check(not CinemaPlan.canSkip(Config, { 0 }, 0, 0.1), "not in the scene's first moment")
		check(CinemaPlan.canSkip(Config, { 0 }, 0, Ci.skipDelay), "seen: skippable")
		check(CinemaPlan.canSkip(Config, { [3] = true }, 3, 2), "a lookup works too")
		check(CinemaPlan.clientBit(Config, Ci.scenes.cityWatch.bit), "a device scene's bit")
		check(
			not CinemaPlan.clientBit(Config, Ci.scenes.ceremony.bit),
			"a device never marks a prologue beat"
		)
		check(not CinemaPlan.clientBit(Config, 16), "nor a mission beat")
		-- the save: seen survives a load and reaches the device
		local p = ProfileSchema.default()
		ProfileSchema.Bits.set(p.seen, 2, true)
		ProfileSchema.Bits.set(p.seen, 30, true)
		local loaded = ProfileSchema.load(p)
		local view = ProfileSchema.clientView(loaded)
		check(
			table.find(view.seen, 2) ~= nil and table.find(view.seen, 30) ~= nil,
			"the client view lists seen bits"
		)
		check(CinemaPlan.seen(view.seen, 30) and not CinemaPlan.seen(view.seen, 31), "seen() reads it")
		-- safe moments
		check(
			CinemaPlan.safe(Config, { beat = true, hitAgo = 0, enemy = 1 }),
			"a server beat is safe by design"
		)
		check(CinemaPlan.safe(Config, { hitAgo = 60, enemy = 500 }), "a quiet street")
		check(not CinemaPlan.safe(Config, { hitAgo = 1, enemy = 500 }), "just hit")
		check(not CinemaPlan.safe(Config, { hitAgo = 60, enemy = 20 }), "a robot close by")
		check(not CinemaPlan.safe(Config, { hitAgo = 60, enemy = 500, downed = true }), "downed")
		check(not CinemaPlan.safe(Config, { hitAgo = 60, enemy = 500, pvp = true }), "flagged for PvP")
		check(not CinemaPlan.safe(Config, { hitAgo = 60, enemy = 500, boss = true }), "in a boss fight")
		local cc = clientSources()["src/client/Controllers/CinemaClient.luau"]
		check(string.find(cc, "function CinemaClient.hurt()", 1, true) ~= nil, "a hit ends a device scene")
		check(
			string.find(
				clientSources()["src/client/Controllers/CombatClient.luau"],
				"CinemaClient.hurt()",
				1,
				true
			) ~= nil,
			"CombatClient tells it"
		)
		-- the server marks and checks the seen set
		local os_ = readFile("src/server/Services/OpeningService.luau")
		check(
			string.find(os_, "CinemaService.markScene(r.player, r.step)", 1, true) ~= nil,
			"prologue beats marked"
		)
		check(
			string.find(os_, "OpeningPlan.canSkip(r.step, CinemaService.seenScene(player, r.step))", 1, true)
				~= nil,
			"skip once seen"
		)
		local ms = readFile("src/server/Services/MissionService.luau")
		check(string.find(ms, "CinemaService.mark(h.player, bit)", 1, true) ~= nil, "mission beats marked")
		check(
			string.find(ms, "sceneSeen(run, track)", 1, true) ~= nil,
			"a mission skip needs every hero to have seen it"
		)
		check(string.find(ms, 'Net.on("SceneSkip", MissionService.skipScene)', 1, true) ~= nil, "SceneSkip")
		local cs = readFile("src/server/Services/CinemaService.luau")
		check(
			string.find(cs, "CinemaPlan.clientBit(Config, bit)", 1, true) ~= nil,
			"SceneSeen takes device bits only"
		)
		local R = require("../src/shared/Remotes")
		check(R.SceneSeen and R.SceneSeen.dir == "C2S" and R.SceneSkip and R.NewsFact, "the remotes")
	end)

	test("Lore 7: Camera motion Full / Reduced / Off and Reduce flashing are respected", function()
		local keys = {}
		for i, k in Config.Settings.keys do
			keys[k.id] = i
		end
		local idx = keys.cameraMotion
		-- (keys only ever append: the lock-on keys came after it on 2026-11-19, so its index stays 13)
		check(idx == 13, "its own key, its index fixed (the Settings.Set number)")
		local k = Config.Settings.keys[idx]
		check(k.kind == "choice" and #k.options == 3 and k.default == 0, "Full by default")
		local SettingsRules = require("../src/shared/SettingsRules")
		check(SettingsRules.clean(Config, {}).cameraMotion == 0, "old saves get Full")
		local full = CinemaPlan.motion(Config, 0, false)
		local half = CinemaPlan.motion(Config, 1, false)
		local off = CinemaPlan.motion(Config, 2, false)
		check(full.lean == 1 and full.push == 1 and full.orbit == 1 and full.shake == 1, "Full")
		check(
			half.lean == 0.5 and half.push == 0.5 and half.orbit == 0.5 and half.shake == 0.5,
			"Reduced halves"
		)
		check(off.lean == 0 and off.push == 0 and off.orbit == 0 and off.shake == 0, "Off removes")
		local rf = CinemaPlan.motion(Config, 0, true)
		check(
			rf.shake == 0 and rf.flash == 0 and rf.lean == 1,
			"Reduce flashing removes shakes and flashes only"
		)
		local buf = CinemaPlan.motion(Config, 0, false)
		check(
			CinemaPlan.motion(Config, 2, false, buf) == buf and buf.push == 0,
			"refreshed in place (no new table)"
		)
		-- the finishers by style, role and settings
		for _, style in { "Comic", "Anime" } do
			for _, opt in { 0, 1, 2 } do
				for _, flashOff in { false, true } do
					local me = CinemaPlan.finisher(Config, style, "killer", opt, flashOff)
					local them = CinemaPlan.finisher(Config, style, "near", opt, flashOff)
					local tag = style .. " opt " .. opt .. (if flashOff then " RF" else "")
					check(me.slow < 1 and me.slow > 0, tag .. ": a time slow")
					check(them.seconds < me.seconds and them.slow > me.slow, tag .. ": nearby is shorter")
					check(
						me.push == Ci.camera.push.finisher * Ci.camera.scale[opt + 1],
						tag .. ": the push follows Camera motion"
					)
					if flashOff then
						check(
							me.hitStop == 0 and me.freeze == 0 and me.flash == 0,
							tag .. ": no hit stop, freeze or flash"
						)
					end
					if style == "Comic" then
						check(me.word and me.lines == 0 and me.freeze == 0, tag .. ": impact word, no lines")
						check(flashOff or me.hitStop > 0, tag .. ": a hit stop")
					else
						check(not me.word and me.lines > 0 and them.lines < me.lines, tag .. ": speed lines")
						check(flashOff or me.freeze > 0, tag .. ": a freeze frame")
					end
				end
			end
		end
		check(CinemaPlan.role(Config, true, 9999) == "killer", "the finisher sees it anywhere")
		check(CinemaPlan.role(Config, false, Ci.finisher.near - 1) == "near", "nearby")
		check(CinemaPlan.role(Config, false, Ci.finisher.near + 1) == nil, "far away: nothing")
		check(
			CinemaPlan.word(Config, "bossDead", 7) == CinemaPlan.word(Config, "bossDead", 7),
			"the same word on every screen"
		)
		-- wiring: the camera obeys both settings; the server is never slowed
		local src = clientSources()
		local cam = src["src/client/Controllers/CameraController.luau"]
		check(
			string.find(cam, "CameraController.motion.shake", 1, true) ~= nil,
			"shakes scale with Camera motion"
		)
		check(string.find(cam, "function CameraController.lean(", 1, true) ~= nil, "lean")
		check(string.find(cam, "function CameraController.push(", 1, true) ~= nil, "push")
		check(string.find(cam, "function CameraController.orbit(", 1, true) ~= nil, "orbit")
		local setc = src["src/client/Controllers/SettingsClient.luau"]
		check(string.find(setc, "CameraController.setMotion(v)", 1, true) ~= nil, "Camera motion applies")
		check(
			string.find(setc, "CameraController.setMotion(nil, on)", 1, true) ~= nil,
			"Reduce flashing applies"
		)
		local cb = src["src/client/Controllers/CombatClient.luau"]
		check(string.find(cb, "CameraController.lean(dir)", 1, true) ~= nil, "dashes lean")
		check(string.find(cb, "CameraController.push()", 1, true) ~= nil, "heavy hits push")
		check(string.find(cb, "CameraController.orbit(", 1, true) ~= nil, "supers orbit")
		check(
			string.find(cb, "not CameraController.reduceMotion", 1, true) ~= nil,
			"the hit freeze still obeys RF"
		)
		local fin = src["src/client/Fx/FinisherFx.luau"]
		check(string.find(fin, "HeroAnimator.timeScale = plan.slow", 1, true) ~= nil, "animation slows")
		check(string.find(fin, "FxLib.setTimeScale(plan.slow)", 1, true) ~= nil, "effects slow")
		check(
			string.find(fin, "CameraController.reduceMotion", 1, true) ~= nil,
			"reduce flashing reaches the plan"
		)
		for _, path in { "src/server/Services/BossService.luau", "src/server/Services/MissionService.luau" } do
			local sv = readFile(path)
			check(not string.find(sv, "timeScale", 1, true), path .. ": the server is never slowed")
			check(string.find(sv, "out.by = ", 1, true) ~= nil, path .. ": the finisher's hero goes out")
		end
	end)

	test("Lore 7: the news: fixed templates, safe names, feed, reel, streaks and the big screens", function()
		local t, n = 1, 1
		local name = CreatorRules.heroName(Config, t, n) :: string
		check(type(name) == "string", "a safe name")
		local samples = {
			boss = Config.Boss.bosses.RustjawPrime.num,
			bossDown = Config.Boss.bosses.LumenMaw.num,
			bossAway = Config.Boss.bosses.RustjawPrime.num,
			unmask = Config.Enemies.Bulwark.typeId,
			streak = 5,
			heist = 0,
			heistVillain = 0,
			act1 = 3,
		}
		for kind, a in samples do
			local line = NewsPlan.text(Config, { k = NewsPlan.CODE[kind], t = t, n = n, a = a }, name)
			check(line ~= nil and not string.find(line :: string, "%", 1, true), kind .. ": a full line")
			if NewsPlan.named(kind) then
				check(
					string.find(line :: string, string.upper(name), 1, true) ~= nil,
					kind .. ": names the hero"
				)
			end
		end
		check(
			NewsPlan.text(Config, { k = NewsPlan.CODE.bossDown, a = 99 }, name) == nil,
			"an unknown boss: nothing"
		)
		check(
			NewsPlan.text(Config, { k = NewsPlan.CODE.streak, a = 1.5 }, name) == nil,
			"a bad count: nothing"
		)
		check(NewsPlan.text(Config, { k = 99 }, name) == nil, "an unknown kind: nothing")
		check(
			string.find(
				NewsPlan.text(Config, { k = NewsPlan.CODE.heist, a = 0 }, nil) :: string,
				"A HERO",
				1,
				true
			) ~= nil,
			"no name: A HERO"
		)
		check(
			NewsPlan.flash(Config, { k = NewsPlan.CODE.boss })
				and not NewsPlan.flash(Config, { k = NewsPlan.CODE.heist }),
			"flashes"
		)
		-- the feed: newest first, capped, repeats dropped
		local feed = NewsPlan.feed()
		check(NewsPlan.push(Config, feed, { k = NewsPlan.CODE.heist, t = 1, n = 1, a = 0 }, 0), "first")
		check(
			not NewsPlan.push(Config, feed, { k = NewsPlan.CODE.heist, t = 1, n = 1, a = 0 }, 10),
			"a repeat"
		)
		check(
			NewsPlan.push(
				Config,
				feed,
				{ k = NewsPlan.CODE.heist, t = 1, n = 1, a = 0 },
				Ci.news.repeatGap + 1
			),
			"news again later"
		)
		for i = 1, 20 do
			NewsPlan.push(Config, feed, { k = NewsPlan.CODE.streak, t = i, n = 1, a = 3 }, 200 + i)
		end
		check(#feed == Ci.news.feed and feed[1].t == 20, "capped, newest first")
		-- the reel: a fresh flash breaks in, then Crane and the ticker take turns
		local f2 = NewsPlan.feed()
		NewsPlan.push(Config, f2, { k = NewsPlan.CODE.boss, a = 1 }, 1000)
		check(NewsPlan.reel(Config, f2, 1001) == "breaking", "BREAKING while fresh")
		local saw = {}
		for tt = 1000 + Ci.news.breaking + 1, 1100 do
			saw[NewsPlan.reel(Config, f2, tt)] = true
		end
		check(saw.crane and saw.ticker and not saw.breaking, "then Crane's segment and the ticker")
		local tick = NewsPlan.ticker(Config, f2, function()
			return nil
		end)
		check(string.find(tick, "RUSTJAW", 1, true) ~= nil, "the ticker reads the feed")
		check(NewsPlan.ticker(Config, {}, function()
			return nil
		end) == Ci.news.channel, "an empty feed shows the channel")
		-- streaks
		local st = {}
		local got = {}
		for i = 1, 6 do
			table.insert(got, NewsPlan.streak(Config, st, 7, i * 10) or 0)
		end
		check(got[3] == 3 and got[5] == 5 and got[4] == 0, "3 and 5 in a row are news")
		check(NewsPlan.streak(Config, st, 7, 10000) == nil and st[7].n == 1, "a long gap starts again")
		-- the big screens for a real world
		local screens = NewsPlan.screens(Config, world)
		local kinds = {}
		for _, s in screens do
			kinds[s.kind] = (kinds[s.kind] or 0) + 1
			check(s.w > 0 and s.h > 0 and math.abs(s.nx) + math.abs(s.nz) == 1, "a screen faces one way")
		end
		check(
			kinds.plaza == 1 and (kinds.downtown or 0) >= 1 and kinds.uptown == 1,
			"plaza, Downtown and Uptown screens"
		)
		-- no free text: the server sends ids only and the device builds every line
		local ns = readFile("src/server/Services/NewsService.luau")
		check(
			string.find(ns, "return { k = f.k, t = f.t, n = f.n, a = f.a, g =", 1, true) ~= nil,
			"facts are ids"
		)
		check(
			string.find(ns, "CreatorRules.nameOk(Config, t, n)", 1, true) ~= nil,
			"blocked names never go out"
		)
		check(
			not string.find(ns, "DisplayName", 1, true) and not string.find(ns, ".Name,", 1, true),
			"no account names"
		)
		local nh = clientSources()["src/client/Ui/NewsHud.luau"]
		check(
			string.find(nh, "CreatorRules.heroName(Config", 1, true) ~= nil,
			"the device rebuilds the safe name"
		)
		check(not string.find(nh, "TextBox", 1, true), "no text box")
		local bs = readFile("src/server/Services/BossService.luau")
		check(string.find(bs, "BossService.Arrived:Fire(bossId)", 1, true) ~= nil, "a boss landing is news")
		check(
			string.find(nh, 'Toasts.show({ id = "newsFlash"', 1, true) ~= nil,
			"the boss flash is a toast too"
		)
		check(string.find(nh, "CinemaHud.nameCard(id)", 1, true) ~= nil, "arriving heroes get the name card")
		for id in Config.Boss.bosses do
			local nm, title = CinemaPlan.nameCard(Config, id)
			check(#nm > 0 and #title > 0, id .. ": a name card")
		end
		check(CinemaPlan.nameCardDue(Config, 3, 100, 200, false), "due on arrival")
		check(not CinemaPlan.nameCardDue(Config, 3, 100, 200, true), "once a fight")
		check(not CinemaPlan.nameCardDue(Config, 0, 1, 200, false), "not when no fight")
		check(not CinemaPlan.nameCardDue(Config, 3, 200 + Ci.nameCard.reach + 1, 200, false), "not far away")
	end)

	test("Lore 7: each piece has a Dev panel button; pooled GUI; placeholder art labelled; boot", function()
		local src = clientSources()
		local dev = src["src/client/Ui/DevPanel.luau"]
		for _, needle in
			{
				'CinemaClient.playScene("cityWatch")',
				'CinemaClient.playScene("lastStand")',
				'"DevCommand", "news"',
				"NewsHud.crane()",
				"NewsHud.nameCard(",
				'"bossDead",\n\t\t\t\tr.Position',
				'FinisherFx.play("bossPhase"',
				'SettingsClient.set("cameraMotion"',
			}
		do
			check(string.find(dev, needle, 1, true) ~= nil, "Dev: " .. needle)
		end
		check(
			string.find(
				readFile("src/server/Services/DevService.luau"),
				"NewsService.dev(player, what)",
				1,
				true
			) ~= nil,
			"DevService"
		)
		local hud = src["src/client/Ui/CinemaHud.luau"]
		check(string.find(hud, "built[id]", 1, true) ~= nil, "comic panels are built once and kept")
		check(
			string.find(hud, "for i = 1, C.finisher.anime.lines do", 1, true) ~= nil,
			"speed lines pooled at boot"
		)
		for _, path in
			{
				"src/client/Ui/CinemaHud.luau",
				"src/client/Ui/NewsHud.luau",
				"src/server/Services/NewsService.luau",
			}
		do
			local text = src[path] or readFile(path)
			check(string.find(text, "PLACEHOLDER ART", 1, true) ~= nil, path .. ": placeholder art labelled")
		end
		check(
			string.find(readFile("src/config/Cinema.luau"), "PLACEHOLDER", 1, true) ~= nil,
			"placeholder titles labelled"
		)
		local boot = src["src/client/init.client.luau"]
		for _, m in { "CinemaClient.init()", "CinemaHud.init()", "NewsHud.init()", "FinisherFx.init()" } do
			check(string.find(boot, m, 1, true) ~= nil, "boot: " .. m)
		end
		local sboot = readFile("src/server/init.server.luau")
		check(
			string.find(sboot, 'boot("CinemaService"', 1, true) ~= nil
				and string.find(sboot, 'boot("NewsService"', 1, true) ~= nil,
			"server boot"
		)
		check(
			string.find(src["src/client/Ui/StoryHud.luau"], "CinemaClient.letterboxed()", 1, true) ~= nil,
			"the guide box goes under the letterbox"
		)
	end)
end

---------------------------------------------------------------------------
-- Lore step 8: the world bosses' looks (nate's lore, 2026-11-17)
---------------------------------------------------------------------------

test(
	"Lore 8: the world bosses' new looks: part-built looks in budget, titles, colours, no old looks",
	function()
		local A = Config.BossArt
		local B = Config.Boss
		local NewsPlan = require("../src/shared/NewsPlan")
		local CinemaPlan = require("../src/shared/CinemaPlan")
		-- nate's lore (2026-11-17): the three world bosses keep their names and fights and get new looks
		local LOOKS = {
			RustjawPrime = { name = "Rustjaw Prime", title = "THE JUNKYARD TITAN", fx = "sparks", parts = 23 },
			LumenMaw = { name = "Lumen Maw", title = "THE LIGHT EATER", fx = "light", parts = 19 },
			LeviathanEngine = {
				name = "Leviathan Engine",
				title = "THE DEEP MACHINE",
				fx = "tide",
				parts = 29,
			},
		}
		local ROLES = { body = true, glow = true, weak = true }
		for id, want in LOOKS do
			local def, art = B.bosses[id], A[id]
			check(def.name == want.name, id .. " keeps its name")
			check(table.find(B.order, id) ~= nil, id .. " is still a world boss")
			check(type(art.look) == "string" and #art.look > 0, id .. " has its lore look")
			check(#art.theme == 3 and #art.debris == 3, id .. " has its look's colours")
			check(
				art.fx and art.fx.kind == want.fx and art.fx.every > 0 and #art.fx.at > 0,
				id .. " has its look's effect"
			)
			for _, at in art.fx.at do
				check(
					math.abs(at[1]) <= def.arenaRadius and at[2] >= -def.height,
					id .. " effect point on the boss"
				)
			end
			-- the name card and the BREAKING flash: "RUSTJAW PRIME, THE JUNKYARD TITAN"
			local nm, title = CinemaPlan.nameCard(Config, id)
			check(
				nm == string.upper(want.name) and title == want.title,
				id .. ": the name card reads " .. want.title
			)
			check(#title <= 26, id .. ": the title fits the card")
			local line = NewsPlan.text(Config, { k = NewsPlan.CODE.boss, a = def.num }, nil) :: string
			check(
				string.find(line, string.upper(want.name) .. ", " .. want.title, 1, true) ~= nil,
				id .. ": the BREAKING flash names it with its title"
			)
			-- the part-built look (until the meshes are imported): the old part budget, real roles, inside the arena
			local per = #def.objectives.list
			local n = #art.parts + #art.objectiveParts * per
			check(A.partBudget[id] == want.parts, id .. ": the part budget is the old count")
			check(
				n <= A.partBudget[id],
				id .. ": the part-built look is within " .. A.partBudget[id] .. " parts"
			)
			local weak = {}
			for _, row in art.parts do
				check(ROLES[row.role] == true, id .. " part role " .. tostring(row.role))
				check(
					row.shape == "Block" or row.shape == "Ball" or row.shape == "Cylinder",
					id .. " part shape"
				)
				for k = 1, 3 do
					check(row.size[k] > 0 and row.size[k] <= def.arenaRadius, id .. " part size")
					check(math.abs(row.at[k]) <= def.arenaRadius, id .. " part inside the arena")
				end
				check(row.at[2] > -def.height, id .. " part not far underground")
				if row.role == "body" then
					check(#row.color == 3 and row.mat ~= nil, id .. " body part colour and material")
				elseif row.role == "weak" then
					table.insert(weak, row.at)
				end
			end
			-- each weak point has a gold part inside its hit sphere, and no gold part is a fake
			local real = 0
			for _, t in def.targets do
				if t.weak then
					real += 1
					local found = false
					for _, at in weak do
						local d =
							math.sqrt((at[1] - t.at[1]) ^ 2 + (at[2] - t.at[2]) ^ 2 + (at[3] - t.at[3]) ^ 2)
						found = found or d <= t.r
					end
					check(found, id .. " " .. t.id .. ": a gold part inside its hit sphere")
				end
			end
			check(#weak == real, id .. ": one gold part a weak point")
			local bodies, lamps = 0, 0
			local up = if def.objectives.list[1].ring then 8 else 0
			for _, row in art.objectiveParts do
				if row.role == "objective" then
					bodies += 1
				elseif row.role == "objectiveGlow" then
					lamps += 1
					local o = row.at
					check(
						math.sqrt(o[1] ^ 2 + (o[2] - up) ^ 2 + o[3] ^ 2) <= 5,
						id .. ": the objective lamp in its hit sphere"
					)
				end
			end
			check(bodies >= 1 and lamps == 1, id .. ": an objective body and one lamp")
			-- the phase hooks are the same: accents per phase, plates that break off at 66% and 33%
			check(#art.glow == 3, id .. " accent colours for 3 phases")
		end
		-- the battle form keeps its look and its plain parts (its own pass)
		check(
			A.NullWarFrame.parts == nil and A.NullWarFrame.look == nil,
			"the battle form's look is unchanged"
		)
		-- the fights are unchanged: the same hit spheres, objectives and attacks
		check(
			B.bosses.LumenMaw.targets[3].id == "crystalA" and B.bosses.LumenMaw.targets[3].r == 5,
			"the Maw's targets"
		)
		check(B.bosses.LeviathanEngine.targets[6].id == "reactor", "the Leviathan's reactor")
		check((function()
			local n = 0
			for _, a in B.bosses.RustjawPrime.attacks do
				n += if a.react then 0 else 1 -- the counters (2026-11-19) come on top
			end
			return n == 4
		end)() and B.bosses.RustjawPrime.attacks[3].id == "ScrapRain", "Rustjaw's attacks")
		-- no old look names or placeholder looks left
		local files = {
			"src/config/Cinema.luau",
			"src/config/Boss.luau",
			"src/config/BossArt.luau",
			"src/client/Fx/WorldFx.luau",
			"art/blender/bosses.py",
		}
		for _, path in files do
			local text = string.lower(readFile(path))
			for _, old in
				{
					"scrapyard titan",
					"terror of the deep",
					"scrap robot",
					"crystal-powered",
					"war submarine",
					"generic neutral machines",
					"placeholder look: boss lore pending",
					"titles are placeholder until the bosses' lore",
				}
			do
				check(string.find(text, old, 1, true) == nil, path .. ": no old look '" .. old .. "'")
			end
		end
		-- the game draws the part-built looks and the looks' effects
		local wf = readFile("src/client/Fx/WorldFx.luau")
		for _, needle in { "partBoss(m, id, s)", "lookFx(sh)", "MawDim", "fit.theme", "PLACEHOLDER ART" } do
			check(string.find(wf, needle, 1, true) ~= nil, "WorldFx: " .. needle)
		end
		check(
			string.find(
				readFile("src/client/Ui/CinemaHud.luau"),
				"cardSlash.BackgroundColor3 = if theme",
				1,
				true
			) ~= nil,
			"the name card's slash takes the look's colour"
		)
	end
)
-- Lore step 10: the side quest framework (Config.SideQuests, Shared.SideQuestPlan; SideQuestService, the
-- Journal's QUESTS page, the tracker, the map's givers, the Dev panel). The 8 old arcs are retired.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local ContractPlan = require("../src/shared/ContractPlan")
	local HqRules = require("../src/shared/HqRules")
	local serde = require("@lune/serde")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local Bits = ProfileSchema.Bits

	local function deep(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deep(x)
		end
		return out
	end

	-- A Config whose side quest data is a copy with a real (non-Dev) giver "TestGiver" and the chains given
	local function withChains(chains: { any }): any
		local sq = deep(SQ)
		sq.givers.TestGiver = deep(SQ.givers.SampleGiver)
		sq.givers.TestGiver.dev = nil
		sq.chains = chains
		return setmetatable({ SideQuests = sq }, { __index = Config })
	end

	-- A valid real chain built from the sample
	local function realChain(id: string, bit: number): any
		local c = deep(SQ.chains[1])
		c.id, c.bit, c.dev, c.giver = id, bit, nil, "TestGiver"
		for _, step in c.steps do
			for _, l in step.lines or {} do
				if l.who == "SampleGiver" then
					l.who = "TestGiver"
				end
			end
		end
		return c
	end

	local function problems(C: any, chain: any): { string }
		local ids = {}
		for _, ch in C.SideQuests.chains do
			ids[ch.id] = ch
		end
		ids[chain.id] = chain
		return SideQuestPlan.checkChain(C, chain, ids)
	end

	local function fails(C: any, chain: any, want: string, label: string)
		local found = false
		for _, b in problems(C, chain) do
			if string.find(b, want, 1, true) then
				found = true
			end
		end
		check(found, label .. " (wants: " .. want .. ")")
	end

	test("Lore 10: every chain validates like a mission; the Dev sample runs every brief kind", function()
		local bad = SideQuestPlan.validate(Config)
		for _, b in bad do
			check(false, b)
		end
		check(#bad == 0, "the side quest data is clean")
		local sample = SideQuestPlan.chain(Config, "Sample")
		check(sample ~= nil and sample.dev == true, "the framework sample is a Dev chain")
		check(sample and #sample.steps == 5, "5 steps")
		check(Config.Dev.sideQuestSample == false, "the Dev flag is off in the build")
		local kinds = {}
		for _, step in sample.steps do
			for _, side in SQ.sides do
				kinds[(SideQuestPlan.goal(step, side) :: any).kind] = true
			end
		end
		for _, k in { "talk", "fight", "incident", "chase", "deliver", "pocket", "finale" } do
			check(kinds[k] == true, "the sample runs " .. k)
		end
		local tried = {}
		for _, g in SQ.devKinds do
			tried[g.kind] = true
		end
		for k in SideQuestPlan.KINDS do
			check(tried[k] == true, "the Dev panel can try " .. k .. " alone")
		end
		check(SideQuestPlan.shared(sample.steps[5]) and not SideQuestPlan.shared(sample.steps[2]), "shared")
		check(
			SideQuestPlan.need(SideQuestPlan.goal(sample.steps[2], "hero")) == 3,
			"a fight needs its robots"
		)
		check(
			SideQuestPlan.text(SideQuestPlan.goal(sample.steps[2], "villain"), "villain")
				~= SideQuestPlan.text(SideQuestPlan.goal(sample.steps[2], "hero"), "hero"),
			"each side its own goal text"
		)
		-- a real chain made from the sample validates (with a real giver)
		local C = withChains({ realChain("Real", 2) })
		check(#problems(C, C.SideQuests.chains[1]) == 0, "a real chain from the sample is fine")
	end)

	test("Lore 10: a broken chain fails each check", function()
		local C = withChains({})
		local function try(edit: (any) -> (), want: string, label: string)
			local c = realChain("Broken", 9)
			edit(c)
			fails(C, c, want, label)
		end
		try(function(c)
			c.steps[2].hero.kind = "dance"
		end, "unknown kind", "an unknown step kind")
		try(function(c)
			c.steps[2].villain = nil
		end, "no villain goal", "a side with no goal")
		try(function(c)
			c.steps[3].hero.text = nil
		end, "hero text: no text", "a goal with no text")
		try(function(c)
			c.steps[2].hero.text = "Stop %s robots"
		end, "format hole", "free text holes")
		try(function(c)
			c.steps[2].hero.text = string.rep("x", SQ.maxText + 1)
		end, "characters (cap", "text over the phone cap")
		try(function(c)
			c.reward.share = SQ.pay.maxShare + 1
		end, "reward share out of range", "a reward over the contract range")
		try(function(c)
			c.reward.credits = 5000
		end, "reward credits", "fixed Credits outside the formula")
		try(function(c)
			c.reward.skillPoints = 1
		end, "reward skillPoints", "nothing that changes stats")
		try(function(c)
			c.reward.emote = "Wave"
		end, "must exist and never be sold", "a sold emote")
		try(function(c)
			c.reward.frame = "PhotoFrame"
		end, "one cosmetic or title", "two cosmetics")
		try(function(c)
			c.unlock.level = Config.Stats.levelCap + 1
		end, "out of reach", "an unreachable level")
		try(function(c)
			c.unlock.after = "Broken"
		end, "after Broken", "after itself")
		try(function(c)
			c.unlock.after = "Nowhere"
		end, "after Nowhere", "after a missing chain")
		try(function(c)
			c.unlock.story = #Config.Story.missions + 1
		end, "story mission", "a story mission that does not exist")
		try(function(c)
			c.layer = "origin"
		end, "an origin line needs its origin", "an origin line without an origin")
		try(function(c)
			table.remove(c.steps)
		end, "the last step is the finale", "no finale")
		try(function(c)
			c.steps[2].hero = deep(c.steps[5].hero)
		end, "a finale only as the last step", "a finale in the middle")
		try(function(c)
			c.steps[5].hero.enemy = "BurglarBot"
		end, "an elite or a famous fake", "a finale on a basic robot")
		try(function(c)
			c.steps[5].hero.hpMult = 40
		end, "finale health", "a finale out of the boss-lite range")
		try(function(c)
			table.remove(c.steps, 2)
		end, "4 steps", "too few steps")
		try(function(c)
			for _ = 1, 6 do
				table.insert(c.steps, 2, deep(c.steps[2]))
			end
		end, "11 steps", "too many steps")
		try(function(c)
			c.steps[5].scene = "ceremony"
		end, "a device scene", "a prologue beat as a step scene")
		try(function(c)
			c.steps[3].hero.template = "Nowhere"
		end, "unknown incident", "an incident that does not exist")
		try(function(c)
			c.steps[3].villain = { kind = "incident", count = 1, template = "RobotHeist", text = "Rob it" }
		end, "is not for villain", "a Vigil-only incident on the Syndicate side")
		try(function(c)
			c.steps[2].lines = { { who = "Stranger", text = "Hello there" } }
		end, "unknown speaker", "a line by nobody")
		try(function(c)
			c.steps[4].hero.layout = "moon"
		end, "unknown pocket layout", "a pocket that does not exist")
		try(function(c)
			c.giver = "SampleGiver"
		end, "a Dev giver on a real chain", "a real chain on the Dev giver")
		try(function(c)
			c.villain = { name = "Boss %s" }
		end, "villain name card", "a broken name card")
		-- side and origin reachability through `after`
		local first = realChain("First", 10)
		first.unlock.side = "hero"
		local second = realChain("Second", 11)
		second.unlock = { level = 1, after = "First", side = "villain" }
		local C2 = withChains({ first, second })
		fails(C2, second, "another side cannot finish", "after a chain only the other side can finish")
		local loopA, loopB = realChain("LoopA", 12), realChain("LoopB", 13)
		loopA.unlock.after, loopB.unlock.after = "LoopB", "LoopA"
		fails(withChains({ loopA, loopB }), loopA, "an after loop", "a loop of after links")
		-- the whole validate() sees duplicate ids and bits
		local d1, d2 = realChain("Twin", 20), realChain("Twin", 20)
		local bad = SideQuestPlan.validate(withChains({ d1, d2 }))
		local idTwice, bitTwice = false, false
		for _, b in bad do
			idTwice = idTwice or string.find(b, "chain id twice", 1, true) ~= nil
			bitTwice = bitTwice or string.find(b, "chain bit twice", 1, true) ~= nil
		end
		check(idTwice and bitTwice, "a chain id and bit are each used once")
	end)

	test("Lore 10: no old arc names anywhere in the side quest data or player text", function()
		-- the 8 arcs nate retired and their givers (Old Beacon and The Velvet Paw stay H6 mentors)
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local MENTOR = { "Old Beacon", "OldBeacon", "Velvet Paw", "VelvetPaw" }
		local hits = {}
		local function look(where: string, text: string, list: { string })
			for _, w in list do
				if string.find(text, "%f[%w]" .. w .. "%f[%W]") then
					table.insert(hits, where .. ": " .. w)
				end
			end
		end
		local function walk(v: any, path: string, list: { string }, seen: { [any]: boolean })
			if type(v) == "string" then
				look(path, v, list)
			elseif type(v) == "table" and not seen[v] then
				seen[v] = true
				for k, x in v do
					if type(k) == "string" then
						look(path, k, list)
					end
					walk(x, path .. "." .. tostring(k), list, seen)
				end
			end
		end
		local all = table.clone(ARC)
		for _, w in MENTOR do
			table.insert(all, w)
		end
		walk(Config.SideQuests, "SideQuests", all, {})
		walk(Config.Story, "Story", all, {})
		for name, mod in Config do
			if name ~= "Mentors" then
				walk(mod, name, ARC, {})
			end
		end
		local MENTOR_FILES = {
			["src/config/Mentors.luau"] = true,
			["src/client/Fx/MentorFx.luau"] = true,
			["src/config/Incidents.luau"] = true, -- the Velvet Paw's runner bot (an incident, H6's villain mentor)
			["src/config/ComicArt.luau"] = true, -- the H6 mentors' rendered portraits (generated by art/panels/post.py)
			["src/config/NpcLooks.luau"] = true, -- the H6 mentors' catalog face and hair (NpcLooks.cast, gap-hairfit)
		}
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(name, -5) == ".luau" then
					look(path, fs.readFile(path), if MENTOR_FILES[path] then ARC else all)
				end
			end
		end
		scan("src")
		for _, h in hits do
			check(false, "an old arc name: " .. h)
		end
		check(#hits == 0, "the old arcs are gone")
		check(not fs.isFile("src/server/Services/QuestService.luau"), "QuestService is gone")
		check(Config.Story.quests == nil and Config.Story.questRange == nil, "the old arcs' data is gone")
	end)

	test("Lore 10: unlocks, accept, abandon and resume, advance to the end", function()
		local a = realChain("A", 2)
		a.unlock = { level = 5 }
		local b = realChain("B", 3)
		b.unlock = { level = 1, after = "A" }
		local o = realChain("O", 4)
		o.layer, o.unlock = "origin", { level = 1, origin = 2 }
		local v = realChain("V", 5)
		v.unlock = { level = 1, side = "villain", story = 2 }
		local n = realChain("N", 6)
		n.layer, n.unlock = "character", { level = 1, npc = true }
		local C = withChains({ a, b, o, v, n })
		check(#SideQuestPlan.validate(C) == 0, "the test chains are valid")
		local c = ProfileSchema.newCharacter()
		c.origin = 1
		local st, why = SideQuestPlan.state(C, c, a, 3, "hero")
		check(st == "locked" and why == "level", "A waits for level 5")
		check(SideQuestPlan.state(C, c, a, 5, "hero") == "open", "then opens")
		check(select(2, SideQuestPlan.state(C, c, b, 50, "hero")) == "after", "B after A")
		check(select(2, SideQuestPlan.state(C, c, o, 50, "hero")) == "origin", "O for origin 2 only")
		check(select(2, SideQuestPlan.state(C, c, v, 50, "hero")) == "side", "V for the Syndicate")
		check(select(2, SideQuestPlan.state(C, c, v, 50, "villain")) == "story", "V after mission 2")
		local rows = SideQuestPlan.journal(C, c, 50, "hero", false)
		local seen = {}
		for _, r in rows do
			seen[r.bit] = r
		end
		check(
			seen[2] and seen[3] and seen[6] and not seen[4] and not seen[5],
			"other sides' and origins' lines hide"
		)
		check(seen[3].why == "after" and seen[3].after == "A", "the Journal says what B waits on")
		-- an NPC-only line is taken at its giver, never from the Journal
		local ok, nwhy = SideQuestPlan.accept(C, c, n, 50, "hero", true)
		check(not ok and nwhy == "npc", "a character line is accepted by talking to its giver")
		check(SideQuestPlan.accept(C, c, n, 50, "hero", false), "at the giver it starts")
		check(c.story.pinned == n.bit and SideQuestPlan.stepOf(c, n) == 1, "started at step 1 and tracked")
		-- abandon and resume
		check(SideQuestPlan.advance(c, n) == "next" and SideQuestPlan.stepOf(c, n) == 2, "step 2")
		check(SideQuestPlan.abandon(c, n) and c.story.pinned == 0, "on hold: no longer tracked")
		check(SideQuestPlan.stepOf(c, n) == 2, "its finished steps are kept")
		check(SideQuestPlan.pinned(C, c) == nil, "nothing is built while it waits")
		check(SideQuestPlan.state(C, c, n, 50, "hero") == "active", "still in progress")
		local pick, kind = SideQuestPlan.talkPick(C, c, "TestGiver", 50, "hero", false)
		check(kind == "resume" and pick == n, "its giver offers to resume it first")
		check(SideQuestPlan.resume(c, n) and c.story.pinned == n.bit, "resumed")
		local chain, step = SideQuestPlan.pinned(C, c)
		check(chain == n and step == 2, "the tracked step is where it was left")
		-- to the end
		for _ = 3, #n.steps do
			check(SideQuestPlan.advance(c, n) == "next", "next step")
		end
		check(SideQuestPlan.advance(c, n) == "done", "the finale ends the chain")
		check(SideQuestPlan.isDone(c, n) and c.story.pinned == 0 and c.sq.at.N == nil, "done, untracked")
		check(SideQuestPlan.advance(c, n) == nil, "a done chain stays done")
		local again, awhy = SideQuestPlan.accept(C, c, n, 50, "hero", false)
		check(not again and awhy == "done", "and is not taken twice")
		-- a Dev chain only with the Dev flag
		local devC = SideQuestPlan.chain(Config, "Sample")
		local function hasSample(rows: { any }): boolean
			for _, r in rows do
				if r.bit == (devC :: any).bit then
					return true
				end
			end
			return false
		end
		check(
			not hasSample(SideQuestPlan.journal(Config, c, 50, "hero", false)),
			"no Dev chain in a live Journal"
		)
		check(hasSample(SideQuestPlan.journal(Config, c, 50, "hero", true)), "the sample with the Dev flag")
		check(
			select(2, SideQuestPlan.talkPick(Config, c, "SampleGiver", 50, "hero", false)) == "none",
			"live"
		)
		check(devC ~= nil, "the sample exists")
	end)

	test("Lore 10: the save: old arcs retire with no loss, settle pays once, repair", function()
		local old = {
			version = 10,
			currency = { credits = 100, banked = 0, dust = 0 },
			characters = {
				{
					level = 12,
					created = 1,
					origin = 1,
					story = {
						opening = 1,
						missions = 3,
						quests = { 4, 2, 0, 4, 3, 0, 0, 4 },
						pinned = 3,
						menu = 2,
					},
				},
				{ level = 4, created = 1, origin = 1, story = { opening = 1, missions = 1 } },
			},
		}
		local p = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
		check(p.version == ProfileSchema.VERSION and ProfileSchema.VERSION >= 11, "save version 11 or later")
		local c = p.characters[1]
		check(
			c.story.quests == nil and c.story.menu == nil and c.story.pinned == 0,
			"the old list, menu and pin go"
		)
		check(c.sq.retired == 1 + 8 + 128, "finished arcs 1, 4 and 8 are retired")
		check(
			c.sq.owed == 3 * SQ.retired.stepCredits,
			"arcs in progress leave Credits for their 3 finished steps"
		)
		check(c.sq.settled == 0 and p.characters[2].sq.retired == 0, "to settle; a hero with none has none")
		check(c.level == 12 and c.story.missions == 3, "nothing else moved")
		local got = SideQuestPlan.settle(Config, p)
		check(got.credits == 600 and p.currency.credits == 700, "the Credits are paid")
		check(Bits.get(p.styles, GearMath.questStyle(Config, "GoldSash") :: number), "arc 1's style is owned")
		check(Bits.get(p.frames, Config.Story.unlocks.frames.PhotoFrame), "arc 8's frame is owned")
		check(#got.unlocks == 2, "two unlocks set (arc 4 gave none that is kept)")
		local twice = SideQuestPlan.settle(Config, p)
		check(twice.credits == 0 and #twice.unlocks == 0 and p.currency.credits == 700, "settled once only")
		-- an unlock already owned is not given twice
		local q = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
		Bits.set(q.styles, GearMath.questStyle(Config, "GoldSash") :: number)
		check(#SideQuestPlan.settle(Config, q).unlocks == 1, "an owned unlock stays as it is")
		-- the creator's chain pieces, the HQ trophy and the badge read the retired arcs
		check(SideQuestPlan.chainsDone(Config, p) == 3, "3 retired arcs count as 3 chains")
		check(not SideQuestPlan.allDone(Config, c), "not every side quest")
		c.sq.retired = 255
		check(
			SideQuestPlan.allDone(Config, c) and HqRules.trophies(Config, p).allQuests,
			"all 8 keep the trophy"
		)
		local fresh = ProfileSchema.default()
		check(not HqRules.trophies(Config, fresh).allQuests, "a new hero has not done them")
		check(fresh.characters[1].sq.settled == 1, "a new hero has nothing to settle")
		-- repair: known chains at real steps only, and the pin only on one of them
		local r = ProfileSchema.default()
		local rc = r.characters[1]
		rc.sq.at = { Sample = 2, Gone = 3 }
		rc.story.pinned = 1
		local back = ProfileSchema.load(serde.decode("json", serde.encode("json", r)))
		local bc = back.characters[1]
		check(
			bc.sq.at.Sample == 2 and bc.sq.at.Gone == nil and bc.story.pinned == 1,
			"a chain in progress survives"
		)
		rc.sq.at = { Sample = 99 }
		local back2 = ProfileSchema.load(serde.decode("json", serde.encode("json", r)))
		check(
			back2.characters[1].sq.at.Sample == nil and back2.characters[1].story.pinned == 0,
			"a bad step goes"
		)
		rc.sq.at = {}
		rc.story.pinned = 77
		check(ProfileSchema.load(r).characters[1].story.pinned == 0, "a pin on nothing goes")
	end)

	test("Lore 10: co-op: each side its own goal, and the group moves on when every side is done", function()
		local sample = SideQuestPlan.chain(Config, "Sample") :: any
		local split, shared = sample.steps[2], sample.steps[4]
		local g = SideQuestPlan.newGroup("Sample", 2)
		local k1, new1 = SideQuestPlan.join(g, split, "hero1", "hero")
		local k2, new2 = SideQuestPlan.join(g, split, "hero2", "hero")
		local k3, new3 = SideQuestPlan.join(g, split, "villain1", "villain")
		check(k1 == "hero" and new1 and k2 == "hero" and not new2, "two Vigil heroes share one goal")
		check(k3 == "villain" and new3, "the Syndicate member gets its own goal")
		check(g.sides.hero.need == 3 and g.sides.villain.need == 1, "each side's own need")
		check(not SideQuestPlan.add(g, "hero", 2), "progress counts for the side")
		check(SideQuestPlan.add(g, "hero", 1), "the Vigil goal is met")
		check(
			not SideQuestPlan.groupDone(g) and SideQuestPlan.waiting(g, "hero"),
			"the Vigil wait on the Syndicate"
		)
		check(SideQuestPlan.set(g, "villain", 1) and SideQuestPlan.groupDone(g), "then the group moves on")
		-- a side that leaves drops its goal, so nobody waits on it
		local h = SideQuestPlan.newGroup("Sample", 2)
		SideQuestPlan.join(h, split, "a", "hero")
		SideQuestPlan.join(h, split, "b", "villain")
		SideQuestPlan.add(h, "hero", 3)
		local dropped, empty = SideQuestPlan.leave(h, "b")
		check(
			dropped == "villain" and not empty and SideQuestPlan.groupDone(h),
			"the rest finish without them"
		)
		local _, gone = SideQuestPlan.leave(h, "a")
		check(gone, "the last one out empties the group")
		-- a shared step is one goal for both sides
		local s = SideQuestPlan.newGroup("Sample", 4)
		local ka = SideQuestPlan.join(s, shared, "a", "hero")
		local kb, nb = SideQuestPlan.join(s, shared, "b", "villain")
		check(ka == "both" and kb == "both" and not nb, "a shared step: one goal")
		check(SideQuestPlan.set(s, "both", 1) and SideQuestPlan.groupDone(s), "one finish moves everyone on")
		check(
			SideQuestPlan.canJoin(s, "Sample", 4) and not SideQuestPlan.canJoin(s, "Sample", 3),
			"same step only"
		)
		check(
			not SideQuestPlan.groupDone(SideQuestPlan.newGroup("Sample", 1)),
			"an empty group is never done"
		)
	end)

	test("Lore 10: pay is a contract's at the hero's level; rewards are a cosmetic, no stats", function()
		for _, level in { 1, 10, 25, 50 } do
			local c, r = ContractPlan.pay(Config, SQ.pay.contract, level, math.huge, false)
			local sc, sr = SideQuestPlan.stepPay(Config, level, false)
			local fc, fr = SideQuestPlan.stepPay(Config, level, true)
			check(
				sc == math.floor(c * SQ.pay.step + 0.5) and sr == math.floor(r * SQ.pay.step + 0.5),
				"a step"
			)
			check(fc > sc and fr > sr, "the finale pays more")
			local cc, cr = SideQuestPlan.chainPay(Config, SQ.chains[1], level)
			check(cc <= c * SQ.pay.maxShare + 1 and cr <= r * SQ.pay.maxShare + 1, "the chain's end in range")
		end
		local cos = SideQuestPlan.cosmetic(SQ.chains[1])
		local n = 0
		for k in cos do
			n += 1
			check(k ~= "credits" and k ~= "skillPoints", "a cosmetic key")
		end
		check(n == 1 and cos.emote == "Bow", "one cosmetic: the sample's emote")
		check(Config.Shop.emotes[Config.Story.unlocks.emotes.Bow].earned == true, "never sold")
	end)

	test("Lore 10: the runtime is wired: service, remotes, Journal, tracker, map, Dev panel", function()
		local sboot = fs.readFile("src/server/init.server.luau")
		check(string.find(sboot, 'boot("SideQuestService"', 1, true) ~= nil, "SideQuestService boots")

		local R = Remotes
		check(R.SideQuestAct ~= nil and R.SideQuestState ~= nil and R.SideQuestTalk ~= nil, "the remotes")
		check(R.QuestState == nil and R.QuestTalk == nil, "the old remotes are gone")
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		check(string.find(svc, "PLACEHOLDER ART", 1, true) ~= nil, "placeholder givers labelled")
		for _, k in { "talk", "fight", "incident", "chase", "deliver", "pocket", "finale" } do
			check(string.find(svc, 'k == "' .. k .. '"', 1, true) ~= nil, "the service builds " .. k)
		end
		check(string.find(svc, "MissionService.enterCustom", 1, true) ~= nil, "pocket steps are pocket runs")
		check(string.find(svc, "SideQuestPlan.settle", 1, true) ~= nil, "the retired arcs settle on load")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		for _, b in
			{ "SQ: give sample chain", "SQ: start step", "SQ: finish step", "SQ: finish chain", "SQ kind: " }
		do
			check(string.find(dev, b, 1, true) ~= nil, "Dev panel: " .. b)
		end
		check(
			string.find(fs.readFile("src/client/Ui/Journal.luau"), "SideQuestPlan", 1, true) ~= nil,
			"Journal"
		)
		check(
			string.find(fs.readFile("src/client/Ui/MapScreen.luau"), "SideQuestGivers", 1, true) ~= nil,
			"map"
		)
		check(
			string.find(fs.readFile("src/client/Ui/StoryHud.luau"), "CinemaHud.nameCard", 1, true) ~= nil,
			"card"
		)
		check(
			string.find(fs.readFile("src/config/SideQuests.luau"), "PLACEHOLDER TEXT", 1, true) ~= nil,
			"sample"
		)
	end)
end

---------------------------------------------------------------------------
-- 2026-11-18 side quest server fixes (SideQuestService): a finale kill in the Killed gap, escorts that could
-- not finish, pockets that pulled a hero straight back, a side left waiting, photo steps, full servers and
-- switched-off robot types, slot switches. The service's own wiring is on the Studio list.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local IncidentSpots = require("../src/shared/IncidentSpots")
	local SQ = Config.SideQuests

	test(
		"SQ fixes: a beaten boss is dying until the event drain, so the finale waits for its Killed",
		function()
			local sim = EnemySim.new(Config, {})
			local e = EnemySim.spawn(sim, "NullSentinel", 0, 0, 0, 10) :: any
			check(e ~= nil and not EnemySim.dying(sim, e.id), "a live boss is not dying")
			local killed = EnemySim.damage(sim, e.id, math.huge, 1)
			check(killed, "the boss falls")
			check(sim.byId[e.id] == nil, "EnemySim drops it at once (the gap the fix covers)")
			-- the finale's rule: respawn only when not alive and not dying
			local alive = sim.byId[e.id] ~= nil and sim.byId[e.id].alive
			check(not alive and EnemySim.dying(sim, e.id), "gone but dying: the finale waits")
			local sawDie = false
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "die" and ev.e == e.id then
					sawDie = true
				end
			end
			check(sawDie and not EnemySim.dying(sim, e.id), "after the drain (Killed fired) it is not dying")
			-- a robot taken away without a defeat is never dying: that one comes back
			local f = EnemySim.spawn(sim, "NullSentinel", 0, 0, 0, 10) :: any
			EnemySim.remove(sim, f.id)
			check(not EnemySim.dying(sim, f.id), "a removed robot is not dying")
		end
	)

	-- where SideQuestService builds a step (newGroup): the step's site, else its chain giver's spot
	local function stepHome(wd: any, chain: any, step: any, rng: any): (number?, number?)
		if step.at then
			local spot, door = SideQuestSites.place(Config, wd, step.at)
			if spot and door then
				if SQ.sites[step.at].square then
					return spot.x, spot.z
				end
				return door.x, door.z
			end
		end
		local gv = SQ.givers[chain.giver]
		if not gv then
			return nil, nil
		end
		local x, z
		if gv.anchor == "site" then
			local _, door = SideQuestSites.place(Config, wd, gv.site)
			if door then
				x, z = door.x, door.z
			else
				x, z = OpeningPlan.plaza(wd)
			end
		elseif gv.anchor == "plaza" then
			x, z = OpeningPlan.plaza(wd)
		elseif gv.anchor == "hq" then
			local s = wd.safehouses[Config.World.safehouse.homeSafehouse]
			x, z = s.x, s.z + 30
		else
			local d = Config.City.districts[gv.anchor]
			x, z = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
		end
		x, z = x + (gv.dx or 0), z + (gv.dz or 0)
		local px, _, pz =
			IncidentSpots.groundNear(Config, wd, x, z, if gv.anchor == "site" then 6 else 40, rng)
		return px, pz
	end

	test("SQ fixes: every escort (origin lines too) gets a drive as long as its goal, on any seed", function()
		local escorts = {}
		for _, chain in SQ.chains do
			for i, step in chain.steps do
				for _, side in SQ.sides do
					local st = SideQuestPlan.goal(step, side)
					if st and st.kind == "escort" and not table.find(escorts, st) then
						table.insert(
							escorts,
							{ chain = chain, step = step, st = st, name = chain.id .. " " .. i }
						)
					end
				end
			end
		end
		check(#escorts >= 5, "the chains have escorts (" .. #escorts .. ")")
		local runs, full, oldJams = 0, 0, 0
		for _, seed in { 202647, 202649, 202655 } do
			local wd = if seed == 202647 then world else WorldMap.build(Config, seed)
			for _, ex in escorts do
				local st = ex.st
				for r = 1, 40 do
					local rng = Rng.new(Rng.hash(seed, r))
					local x, z = stepHome(wd, ex.chain, ex.step, rng)
					if x and z then
						local road = if st.road
							then SideQuestSites.roadPath(Config, wd, x, z, st.goal * 1.15, 7)
							else nil
						-- the old way: the road, else one street path; need at least 30 studs
						local old = road
							or IncidentSpots.streetPath(
								Config,
								wd,
								x,
								z,
								8,
								st.goal / 7,
								Rng.new(Rng.hash(seed, r, 2))
							)
						if IncidentSpots.pathLength(old) < math.min(st.goal, 30) then
							oldJams += 1
						end
						local path, len =
							IncidentSpots.drivePath(Config, wd, x, z, 8, st.goal / 7, st.goal, rng, road)
						local need = math.max(1, math.min(st.goal, math.floor(len)))
						runs += 1
						check(
							#path >= 2 and len >= need,
							ex.name .. " seed " .. seed .. " #" .. r .. ": the truck can finish"
						)
						near(len, IncidentSpots.pathLength(path), 0.01, "the length returned is the path's")
						if len >= st.goal then
							full += 1
						end
						if road then
							check(
								path[1][1] == road[1][1] and path[1][3] == road[1][3],
								"a farm road escort keeps its road"
							)
						end
					end
				end
			end
		end
		check(runs > 0 and full == runs, string.format("every drive is the full goal (%d of %d)", full, runs))
		print(string.format("  (escorts: %d drives; the old way jammed %d)", runs, oldJams))
	end)

	test("SQ fixes: a lone point still gets a drive; a short path goes there and back", function()
		local y = Config.City.ground.y + 0.5
		local two = { { 0, y, 0 }, { 20, y, 0 } }
		local p, len = IncidentSpots.drivePath(Config, world, 0, 0, 8, 20, 100, Rng.new(3), two)
		check(len >= 100 and #p > 2, "a 20-stud road is driven back and forth to 100")
		for i = 2, #p do
			local d = math.abs(p[i][1] - p[i - 1][1])
			near(d, 20, 0.001, "each leg is a leg of the road")
		end
	end)

	test("SQ fixes: robot types nate switches off give way to one that is on", function()
		local enemies = setmetatable({}, { __index = Config.Enemies })
		for _, k in { "BurglarBot", "SneakBot", "Diver", "SparkDrone" } do
			local cfg = table.clone(Config.Enemies[k])
			cfg.on = false
			enemies[k] = cfg
		end
		local C = setmetatable({ Enemies = enemies }, { __index = Config })
		check(SideQuestPlan.robotFor(Config, "BurglarBot") == "BurglarBot", "a type that is on is itself")
		for _, k in { "BurglarBot", "SneakBot", "Diver", "SparkDrone" } do
			local got = SideQuestPlan.robotFor(C, k)
			local cfg = C.Enemies[got]
			check(got ~= k and cfg.on ~= false and not cfg.fake and not cfg.twin, k .. " -> " .. got)
			check((cfg.sea == true) == (Config.Enemies[k].sea == true), k .. ": the same medium")
		end
		check(
			(C.Enemies[SideQuestPlan.robotFor(C, "SparkDrone")].ai or "flyer")
				== (Config.Enemies.SparkDrone.ai or "flyer"),
			"the same AI first (a flyer for a flyer)"
		)
		-- every robot a chain step spawns resolves to a type that is on
		for _, chain in SQ.chains do
			for i, step in chain.steps do
				for _, side in SQ.sides do
					local st = SideQuestPlan.goal(step, side)
					local kinds = {}
					if st then
						for _, row in st.squads or {} do
							table.insert(kinds, row[1])
						end
						for _, row in st.adds or {} do
							table.insert(kinds, row[1])
						end
						if type(st.enemy) == "string" then
							table.insert(kinds, st.enemy)
						end
						if st.kind == "photo" then
							table.insert(kinds, "SneakBot")
						end
					end
					for _, k in kinds do
						local got = SideQuestPlan.robotFor(Config, k)
						check(
							EnemySim.enabled(Config, got),
							chain.id .. " step " .. i .. ": " .. k .. " spawns"
						)
					end
				end
			end
		end
	end)

	test("SQ fixes: fights never need more kills than robots; photos keep a spare", function()
		check(SideQuestPlan.shortfall(6, 0, 0) == 6, "a squad the full server could not build is owed")
		check(SideQuestPlan.shortfall(6, 2, 4) == 0, "nothing owed while the rest stand")
		check(SideQuestPlan.shortfall(6, 2, 3) == 1, "one gone without a defeat comes back")
		check(SideQuestPlan.shortfall(1, 1, 0) == 0, "a finished fight owes nothing")
		-- a 2-photo step: 3 Sneak Bots; beat two before any photo and two more slip in
		check(SideQuestPlan.photoSpawns(2, 0, 0) == 3, "count + 1 at the start")
		check(SideQuestPlan.photoSpawns(2, 0, 1) == 2, "two beaten: two more")
		check(SideQuestPlan.photoSpawns(2, 1, 2) == 0, "one photo, two standing: enough")
		check(SideQuestPlan.photoSpawns(2, 1, 0) == 2, "one photo, none standing: a target and a spare")
	end)

	test("SQ fixes: a pocket's ring starts a run only on a fresh step in", function()
		local inside = {}
		local first = SideQuestPlan.ringEntries(inside, { a = true, b = false })
		check(#first == 1 and first[1] == "a", "stepping in starts it")
		check(#SideQuestPlan.ringEntries(inside, { a = true }) == 0, "standing in it does not start again")
		check(#SideQuestPlan.ringEntries(inside, {}) == 0 and inside.a, "away in the pocket keeps the mark")
		check(
			#SideQuestPlan.ringEntries(inside, { a = true }) == 0,
			"put back in the ring after a run: no pull"
		)
		check(#SideQuestPlan.ringEntries(inside, { a = false }) == 0, "stepping out")
		local again = SideQuestPlan.ringEntries(inside, { a = true, b = true })
		check(#again == 2, "then stepping in again starts it (and b's first step in)")
	end)

	test("SQ fixes: a side left waiting finishes when the other side leaves", function()
		local split = {
			hero = { kind = "talk", text = "x" },
			villain = { kind = "fight", squads = { { "BruteBot", 2 } }, text = "y" },
		}
		local g = SideQuestPlan.newGroup("Sample", 2)
		SideQuestPlan.join(g, split, "a", "hero")
		SideQuestPlan.join(g, split, "b", "villain")
		SideQuestPlan.set(g, "hero", 1)
		check(SideQuestPlan.waiting(g, "hero"), "the Vigil wait on the Syndicate")
		local dropped, empty, done = SideQuestPlan.leave(g, "b")
		check(dropped == "villain" and not empty and done, "the Syndicate leave: the step is done")
		local h = SideQuestPlan.newGroup("Sample", 2)
		SideQuestPlan.join(h, split, "a", "hero")
		SideQuestPlan.join(h, split, "b", "villain")
		local _, _, notYet = SideQuestPlan.leave(h, "b")
		check(not notYet, "a side still working is not done")
		local _, gone, none = SideQuestPlan.leave(h, "a")
		check(gone and not none, "an empty group completes nobody")
	end)
end

---------------------------------------------------------------------------
-- Lore step 9: the Crater as a blasted Crane lab, and your double as a rare world event (nate's lore, 2026-11-17)
---------------------------------------------------------------------------

test("Lore 9: the Crater is a blasted Crane lab: bounds, spawn, sight lines and part budget kept", function()
	local C = W.crater
	local gy = Config.City.ground.y
	local lm = world.landmarks[1]
	check(lm.id == "CometCrater" and lm.id == Config.Pvp.crater.id, "the Crater is still the PvP landmark")
	-- the zone: the same 4 x 4 tiles, so PvpRules.inCrater's square is where it was
	local def = W.landmarks[1]
	local x0, z0 = WorldGen.tileOrigin(Config.City, def.tx, def.tz)
	check(
		lm.size == 400 and lm.centre.x == x0 + 200 and lm.centre.z == z0 + 200,
		"same bounds (400 x 400 on the same tiles)"
	)
	local r = lm.size / 2 - C.rimWidth
	check(
		lm.spot.x == lm.centre.x and lm.spot.z == lm.centre.z - r and lm.spot.y == gy + C.rimHeight + 0.5,
		"the beacon's spot on the south rim is unchanged"
	)
	-- the part budget (was 21: the floor, 16 rim rocks, the old glow core and 3 posts)
	check(#lm.boxes <= C.parts, string.format("%d parts within %d (%+d)", #lm.boxes, C.parts, #lm.boxes - 21))
	local by: { [string]: number } = {}
	local rim, tallest, inside, open = 0, 0, true, true
	for _, b in lm.boxes do
		by[b.color] = (by[b.color] or 0) + 1
		local top = b.cy + (if b.shape == "ball" then math.max(b.sx, b.sy, b.sz) else b.sy) / 2
		local reach = math.sqrt((b.cx - lm.centre.x) ^ 2 + (b.cz - lm.centre.z) ^ 2)
		local half = math.max(b.sx, b.sz) / 2
		if b.kind == "rock" then
			rim += 1
		elseif b.kind ~= "field" then
			tallest = math.max(tallest, top - gy)
			if reach + half > r - 5 then
				inside = false
			end
			if reach - half < C.openRadius and top > gy + C.openTop then
				open = false
			end
		end
		check(
			not string.find(string.lower(b.color), "comet", 1, true)
				and not string.find(string.lower(b.color), "meteor", 1, true),
			"no comet or meteor dressing: " .. b.color
		)
		if b.kit then
			check(Config.City.kit.baseMaterial[b.kit] ~= nil, "a real kit texture: " .. b.kit)
		end
	end
	check(rim == 16, "the blast ring's 16 rim rocks stay")
	check(
		tallest <= C.maxTop and tallest < C.rimHeight,
		string.format("nothing over %d studs (%.1f)", C.maxTop, tallest)
	)
	check(inside, "the ruins stay on the floor inside the rim")
	check(open, "an open fighting floor in the middle (sight lines across the bowl)")
	check(Config.City.palette.comet == nil, "the old comet glow colour is gone")
	-- what it is dressed as
	check((by.labWall or 0) >= 2 * #C.walls + #C.towers, "broken lab walls and toppled towers")
	check((by.craneNavy or 0) >= 2 and (by.white or 0) >= 6, "the Crane C on two walls")
	check(
		(by.sparkGlow or 0) == #C.tanks and (by.glass or 0) >= 2 * #C.tanks,
		"cracked tanks with a Spark glow"
	)
	check((by.husk or 0) == #C.husks and (by.rust or 0) == #C.husks, "robot husks from the battle")
	check(
		(by.relicRed or 0) == 2 and (by.relicBlue or 0) == 1 and (by.relicGold or 0) == 2,
		"the old heroes' relics: a torn cape, a cracked shield emblem, a dented helmet"
	)
	check((by.scorch or 0) >= C.scars.n + 1, "burn scars and a scorched foundation")
	-- the flag rules are the M8 tests' (unchanged); the beacon and rim height tests too
	check(Config.Pvp.crater.warn == 5 and Config.Pvp.minLevel == 10, "the Crater's PvP numbers unchanged")
	-- no comet, meteor or Shardfall in the Crater's player text
	local BAD = { "comet", "meteor", "shardfall" }
	local function clean(text: string): boolean
		local low = string.lower(text)
		for _, w in BAD do
			if string.find(low, w, 1, true) then
				return false
			end
		end
		return true
	end
	local card = Config.Cinema.nameCard.places.crater
	check(card.name == "THE CRATER" and card.title == "WHERE THE OLD HEROES FELL", "the Crater's card")
	check(clean(def.name) and clean(card.name) and clean(card.title), "config text")
	for _, path in
		{
			"src/client/Ui/Toasts.luau",
			"src/client/Ui/PvpHud.luau",
			"src/client/Ui/MapScreen.luau",
			"src/client/Ui/NewsHud.luau",
			"src/server/Services/FlagService.luau",
		}
	do
		for lit in string.gmatch(readFile(path), '"([^"\n]*)"') do
			if string.find(string.lower(lit), "crater", 1, true) and lit ~= Config.Pvp.crater.id then
				check(clean(lit), path .. ": " .. lit)
			end
		end
	end
	local nh = readFile("src/client/Ui/NewsHud.luau")
	check(
		string.find(nh, 'player:GetAttribute("InCrater") == true', 1, true) ~= nil
			and string.find(nh, "craterCard = true", 1, true) ~= nil,
		"the card shows the first time a session a hero walks in"
	)
	check(
		string.find(readFile("src/shared/WorldGen.luau"), "PLACEHOLDER ART: plain parts; the walls", 1, true)
			~= nil,
		"placeholder art labelled"
	)
end)

test("Lore 9: your double is a rare event: the scheduler's rare tier, its odds and cooldowns", function()
	local EV = Config.Events
	local R = EV.scheduler.rare
	local D = EV.events.YourDouble
	check(
		table.find(EV.rare, "YourDouble") ~= nil and table.find(EV.order, "YourDouble") == nil,
		"rare, not in the mix"
	)
	check(table.find(EventPlan.GOALS, D.goal) ~= nil and D.goal == "twin", "a goal the server builds")
	check(R.gap >= 3600 and R.chance <= 0.1 and R.firstAfter >= 600, "the rare tier is rare")
	-- 48 hours of a server where someone may always get it
	local st = EventPlan.new(EV, 0)
	local rng = Rng.new(91)
	local rares, all, lastRare, lastAny, most = {}, 0, nil, nil, 0
	for t = 0, 172800 do
		local id = EventPlan.due(EV, st, t, rng, nil, function()
			return true
		end)
		most = math.max(most, EventPlan.activeCount(st))
		if id then
			all += 1
			if lastAny then
				check(t - lastAny >= 240 - 1e-6, "slots stay 4 to 6 minutes apart")
			end
			lastAny = t
			if id == "YourDouble" then
				check(t >= R.firstAfter, "never in the server's first 20 minutes")
				if lastRare then
					check(t - lastRare >= R.gap, "at most one rare event an hour")
				end
				lastRare = t
				table.insert(rares, t)
			end
		end
	end
	check(most <= EV.scheduler.maxActive, "never more than 2 at once")
	check(#rares >= 8 and #rares <= 48, string.format("%d doubles in 48 h of a busy server", #rares))
	check(#rares / all <= 0.1, string.format("%.1f%% of events are rare", #rares / all * 100))
	-- no eligible hero, or no rare predicate (the old call): never
	local st2, st3 = EventPlan.new(EV, 0), EventPlan.new(EV, 0)
	local r2, r3 = Rng.new(5), Rng.new(5)
	local none = 0
	for t = 0, 36000 do
		if EventPlan.due(EV, st2, t, r2, nil, function()
			return false
		end) == "YourDouble" then
			none += 1
		end
		if EventPlan.due(EV, st3, t, r3) == "YourDouble" then
			none += 1
		end
	end
	check(none == 0, "nobody eligible: no double; the old call never rolls the rare tier")
	-- one hero: at most once per 3 hours of play
	local info = {
		level = 20,
		copyDone = true,
		prologue = false,
		mission = false,
		y = 10,
		crater = false,
		busy = false,
		still = 0,
		played = 0,
		lastAt = nil :: number?,
	}
	local st4 = EventPlan.new(EV, 0)
	local r4 = Rng.new(17)
	local mine, prev = 0, nil
	for t = 0, 108000 do -- 30 hours played in one long session
		info.played = t
		local id = EventPlan.due(EV, st4, t, r4, nil, function()
			return EventPlan.doubleOk(EV, info)
		end)
		if id == "YourDouble" then
			mine += 1
			if prev then
				check(t - prev >= D.playerGap, "3 hours of play between one hero's doubles")
			end
			prev = t
			info.lastAt = t
		end
	end
	check(
		D.playerGap >= 10800 and mine >= 2 and mine <= 10,
		string.format("%d doubles for one hero in 30 h", mine)
	)
	-- pays like a rare event
	local c, rn = EventPlan.rarePay(EV, 100, 51)
	check(c == 100 * R.pay and rn == math.floor(51 * R.pay + 0.5) and R.pay >= 2, "rare pay")
	-- the save keeps the last one's play time
	local p = ProfileSchema.default()
	check(p.stats.doubleAt == 0, "a new save has never had one")
	p.stats.doubleAt = "junk"
	check(ProfileSchema.load(p).stats.doubleAt == 0, "junk repairs to 0")
end)

test(
	"Lore 9: who may meet their double: level, The Copy, the open city, not AFK, never the prologue",
	function()
		local EV = Config.Events
		local D = EV.events.YourDouble
		local function base(): EventPlan.DoubleInfo
			return {
				level = 20,
				copyDone = true,
				prologue = false,
				mission = false,
				y = 10,
				crater = false,
				busy = false,
				still = 5,
				played = 50000,
				lastAt = nil,
			}
		end
		check(EventPlan.doubleOk(EV, base()), "an eligible hero")
		check(D.mission == 4 and Config.Story.missions[4].name == "The Copy", "past The Copy (mission 4)")
		check(D.minLevel >= Config.Story.missions[4].minLevel, "level at least The Copy's")
		local cases: { { any } } = {
			{
				"level",
				function(i)
					i.level = D.minLevel - 1
				end,
			},
			{
				"copy",
				function(i)
					i.copyDone = false
				end,
			},
			{
				"prologue",
				function(i)
					i.prologue = true
				end,
			},
			{
				"mission",
				function(i)
					i.mission = true
				end,
			},
			{
				"pocket",
				function(i)
					i.y = EV.scheduler.pocketY + 10
				end,
			},
			{
				"crater",
				function(i)
					i.crater = true
				end,
			},
			{
				"busy",
				function(i)
					i.busy = true
				end,
			},
			{
				"afk",
				function(i)
					i.still = D.afk
				end,
			},
			{
				"cooldown",
				function(i)
					i.lastAt = i.played - D.playerGap + 1
				end,
			},
		}
		for _, c in cases do
			local i = base()
			c[2](i)
			local ok, why = EventPlan.doubleOk(EV, i)
			check(not ok and why == c[1], "not when: " .. c[1] .. " (" .. tostring(why) .. ")")
		end
		local i = base()
		i.lastAt = i.played - D.playerGap
		check(EventPlan.doubleOk(EV, i), "again after 3 hours of play")
		-- the prologue wins over everything (a new hero is low level too)
		local pro = base()
		pro.prologue, pro.level, pro.copyDone = true, 1, false
		check(select(2, EventPlan.doubleOk(EV, pro)) == "prologue", "never during the prologue")
		-- the pick: only eligible heroes, the same one for the same seed
		local list = { [3] = base(), [7] = base(), [9] = base() }
		list[7].crater = true
		list[9].still = 999
		for s = 1, 20 do
			check(EventPlan.doublePick(EV, list, Rng.new(s)) == 3, "only the eligible hero")
		end
		list[3].mission = true
		check(EventPlan.doublePick(EV, list, Rng.new(1)) == nil, "nobody eligible")
		local two = { [4] = base(), [2] = base() }
		check(
			EventPlan.doublePick(EV, two, Rng.new(8)) == EventPlan.doublePick(EV, two, Rng.new(8)),
			"a seed picks the same hero"
		)
		-- the event's pieces: the twin, co-op credit, the news flash, the name card and Patch's line
		local es = readFile("src/server/Services/EventService.luau")
		for _, needle in
			{
				"EnemyService.spawnTwin(player, spot",
				"helpers = { [h.id] = true }",
				'NewsService.post("double", player)',
				'NewsService.post("doubleDown", ev.target)',
				"EventPlan.rarePay(EC, credits, renown)",
				"PassRules.eventWeights(Config, os.time()),\n\t\t\t\trareAllowed,", -- lore step 12 adds sideAllowed
				"player.Idled:Connect",
				"OpeningService.running(player)",
				"MissionService.runOf(player) ~= nil",
				'player:GetAttribute("InCrater") == true',
			}
		do
			check(string.find(es, needle, 1, true) ~= nil, "EventService: " .. needle)
		end
		local NewsPlan = require("../src/shared/NewsPlan")
		local CinemaPlan = require("../src/shared/CinemaPlan")
		local GuidePlan = require("../src/shared/GuidePlan")
		local fact = { k = NewsPlan.CODE.double }
		check(
			NewsPlan.text(Config, fact, "Captain Spark")
					== "BREAKING: A FAKE OF CAPTAIN SPARK IS LOOSE IN THE CITY"
				and NewsPlan.flash(Config, fact),
			"a news flash for everyone"
		)
		check(
			NewsPlan.text(Config, { k = NewsPlan.CODE.doubleDown }, nil) == "A HERO CRACKS THEIR OWN DOUBLE",
			"and when it is cracked"
		)
		local nm, title = CinemaPlan.card(Config, "events", "YourDouble")
		check(nm == "DOUBLE TROUBLE" and title == "A FAKE WEARING YOUR FACE", "the name card")
		local hero = GuidePlan.worldLine(Config, "double", "hero")
		local villain = GuidePlan.worldLine(Config, "double", "villain")
		check(
			hero ~= nil and villain ~= nil and hero.who == "patch" and hero.text ~= villain.text,
			"Patch's line, by side"
		)
		local radio = GuidePlan.radio()
		GuidePlan.radioMark(radio, 100, "firstIncident")
		check(
			GuidePlan.radioOk(Config, radio, 101, "double", { on = true, busy = false }),
			"it skips the radio gap"
		)
		check(
			not GuidePlan.radioOk(Config, radio, 101, "double", { on = false, busy = false }),
			"the Guide radio setting turns it off"
		)
		check(
			not GuidePlan.radioOk(Config, radio, 101, "double", { on = true, busy = true }),
			"never in a mission"
		)
		check(#GuidePlan.validate(Config) == 0, "every guide line still valid")
		-- Dev panel: teleport to the Crater, its card, force the double on yourself
		local dev = clientSources()["src/client/Ui/DevPanel.luau"]
		for _, needle in
			{ '"DevCommand", "crater"', '"DevCommand", "double"', 'NewsHud.card("places", "crater")' }
		do
			check(string.find(dev, needle, 1, true) ~= nil, "Dev: " .. needle)
		end
		check(
			string.find(
				readFile("src/server/Services/DevService.luau"),
				"EventService.forceDouble(player)",
				1,
				true
			) ~= nil,
			"DevService"
		)
	end
)
---------------------------------------------------------------------------
-- Lore step 11, chain 1: The Hero Academy (Downtown). Config.SideQuests (the chain, Janitor Gus, the Academy
-- site), Shared.SideQuestSites (the building), PocketLayout "academy" (its inside), Headmaster Halo (a famous
-- fake: Config.Enemies.HeadmasterHalo, also in FAKES above), the scenes, the reward, the Dev panel.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local HqRules = require("../src/shared/HqRules")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local A = SideQuestPlan.chain(Config, "HeroAcademy") :: any
	local SIDES = { "hero", "villain" }

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	-- a hero who has cleared Act 1's Ceremony and Safehouse
	local function afterSafehouse(): any
		local c = ProfileSchema.newCharacter()
		c.story.missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
		return c
	end

	test(
		"Lore 11: The Hero Academy validates: 8 Downtown quests, each side's flavour, Halo's finale",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			check(A ~= nil and not A.dev, "a real chain")
			check(#A.steps == 8 and A.layer == "district" and A.district == "Downtown", "8 Downtown quests")
			local gus = SQ.givers.Gus
			check(A.giver == "Gus" and not gus.dev and gus.anchor == "site", "Janitor Gus gives it at a site")
			check(A.site == "Academy" and gus.site == "Academy", "the Academy")
			local last = A.steps[#A.steps]
			local fin = SideQuestPlan.goal(last, "hero") :: any
			check(
				SideQuestPlan.shared(last) and fin.kind == "finale" and fin.enemy == "HeadmasterHalo",
				"Halo's finale, both sides together"
			)
			check(
				Config.Enemies.HeadmasterHalo.fake ~= nil
					and table.find(SQ.finale.enemies, "HeadmasterHalo") ~= nil,
				"Halo is a famous fake on the finale list (face crack: the Lore 4 tests run on FAKES)"
			)
			-- each side's flavour (nate: the Vigil rescue and expose fakes, the Syndicate heist and sabotage)
			local kinds = { hero = {}, villain = {} }
			local split = 0
			for i, step in A.steps do
				for _, side in SIDES do
					kinds[side][(SideQuestPlan.goal(step, side) :: any).kind] = true
				end
				if SideQuestPlan.shared(step) then
					local g = SideQuestPlan.goal(step, "hero") :: any
					check(
						type(g.villainText) == "string" and g.villainText ~= g.text,
						"step " .. i .. ": the Syndicate reads its own goal"
					)
				else
					split += 1
					check(
						SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
							~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
						"step " .. i .. ": each side's own job"
					)
				end
			end
			check(split >= 5, "most steps give each side its own job (" .. split .. ")")
			for _, k in { "photo", "escort", "find", "carry", "hold" } do
				check(kinds.hero[k] == true, "the Vigil: " .. k)
			end
			for _, k in { "fetch", "chase", "deliver", "race" } do
				check(kinds.villain[k] == true, "the Syndicate: " .. k)
			end
			check(kinds.hero.pocket and kinds.villain.pocket, "inside the academy, both sides")
			-- who speaks: the guides and the chain's own cast
			local who = {}
			for _, step in A.steps do
				for _, l in step.lines or {} do
					who[l.who] = true
				end
			end
			for _, w in { "Gus", "patch", "lodestar", "halo", "wren" } do
				check(who[w] == true, "speaks: " .. w)
			end
			for _, w in { "halo", "wren" } do
				local sp = Config.Story.guides.speakers[w]
				check(
					sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
					w .. ": a guide speaker with a portrait and a blip"
				)
			end
			-- 1 to 3 short device scenes, one before the finale
			local scenes = 0
			for _, step in A.steps do
				if step.scene then
					scenes += 1
					local sc = Config.Cinema.scenes[step.scene]
					check(sc ~= nil and sc.client == true, step.scene .. ": a device scene")
					check(sc and CinemaPlan.check(Config, sc), step.scene .. ": 5 to 20 s")
					for _, l in (sc and sc.lines) or {} do
						check(
							Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
							step.scene .. ": speaker " .. tostring(l.who)
						)
					end
				end
			end
			check(scenes >= 1 and scenes <= 3, "1 to 3 short scenes (" .. scenes .. ")")
			check(last.scene ~= nil, "a scene before Halo's finale")
			check(Config.Cinema.comic.pages.wrenStory ~= nil, "Wren's story is a comic page")
			local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
			for _, k in { "school", "scan" } do
				check(string.find(hud, 'kind == "' .. k .. '"', 1, true) ~= nil, "the comic draws " .. k)
			end
		end
	)

	test("Lore 11: the finale's name card: HEADMASTER HALO on the last step only", function()
		for i = 1, #A.steps - 1 do
			check(SideQuestPlan.card(A, i) == nil, "no card on step " .. i)
		end
		local card = SideQuestPlan.card(A, #A.steps) :: any
		check(card ~= nil and card.name == "HEADMASTER HALO", "the finale's card names Halo")
		check(card and card.title == A.villain.title and #card.title > 0, "and his title")
		check(
			SideQuestPlan.fixedText(card.name, 32) == nil and SideQuestPlan.fixedText(card.title, 32) == nil,
			"fixed text that fits the card"
		)
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		check(string.find(svc, "SideQuestPlan.card(g.chain, g.idx", 1, true) ~= nil, "the server sends it")
		local sh = fs.readFile("src/client/Ui/StoryHud.luau")
		check(string.find(sh, "CinemaHud.nameCard", 1, true) ~= nil, "the device shows it on arrival")
	end)

	test(
		"Lore 11: it opens after Act 1's Safehouse for both sides; Gus offers it; the Journal page",
		function()
			for _, side in SIDES do
				local c = ProfileSchema.newCharacter()
				c.story.missions = StoryPlan.setBit(0, 1)
				local st, why, n = SideQuestPlan.state(Config, c, A, 10, side)
				check(st == "locked" and why == "story" and n == 2, side .. ": waits for the Safehouse")
				local rows = SideQuestPlan.journal(Config, c, 10, side, false)
				local row = nil
				for _, r in rows do
					if r.bit == A.bit then
						row = r
					end
				end
				check(row ~= nil and row.why == "story", side .. ": the Journal says what it waits on")
				check(
					select(2, SideQuestPlan.talkPick(Config, c, "Gus", 10, side, false)) == "none",
					side .. ": Gus has nothing yet"
				)
				local d = afterSafehouse()
				check(
					SideQuestPlan.state(Config, d, A, 3, side) == "open",
					side .. ": open after the Safehouse"
				)
				local pick, kind = SideQuestPlan.talkPick(Config, d, "Gus", 3, side, false)
				check(pick == A and kind == "offer", side .. ": Gus offers it")
				check(SideQuestPlan.fixedText(A.blurb[side], 90) == nil, side .. ": the page's line")
				check(SideQuestPlan.fixedText(A.lines.offer[side], 120) == nil, side .. ": Gus's offer")
			end
			check(
				string.find(fs.readFile("src/client/Ui/Journal.luau"), "chain.blurb", 1, true) ~= nil,
				"the Journal shows the page line"
			)
			check(
				string.find(fs.readFile("src/client/Ui/MapScreen.luau"), "SideQuestSites", 1, true) ~= nil,
				"the map marks the site"
			)
			check(
				string.find(
					fs.readFile("src/server/Services/SideQuestService.luau"),
					'SetAttribute("SideQuestSites"',
					1,
					true
				) ~= nil,
				"the server publishes the site"
			)
		end
	)

	test(
		"Lore 11: Halo Academy is an existing Downtown building clear of the ceremony, row and stairwell",
		function()
			local L = world.downtown
			local st = SQ.sites.Academy
			local b, door = SideQuestSites.place(Config, world, "Academy")
			check(b ~= nil and door ~= nil, "a building fits")
			if not b or not door then
				return
			end
			check(table.find(L.buildings, b) ~= nil, "one of Downtown's own buildings")
			check(not b.crown and b.h >= st.height[1] and b.h <= st.height[2], "a school block, not a tower")
			check(b.sx >= 40 and b.sz >= 40, "a large footprint")
			local bt = L.beacon
			check(flat(b.x, b.z, bt.x, bt.z) >= st.away.plaza, "away from the plaza's ceremony")
			for i, r in L.row do
				check(flat(b.x, b.z, r.x, r.z) >= st.away.row, "clear of chase roof " .. i)
			end
			local hd = HqRules.heroDoor(Config, world) :: any
			check(flat(b.x, b.z, hd.x, hd.z) >= st.away.door, "clear of the Safehouse stairwell")
			for _, o in L.open do
				check(
					math.abs(b.x - o.x) > o.size / 2 + st.away.open
						or math.abs(b.z - o.z) > o.size / 2 + st.away.open,
					"not The Gala Heist's square " .. o.id
				)
			end
			-- the door: on the building's face, in no building, the plaza side
			for _, o in world.buildings do
				check(
					math.abs(door.x - o.x) >= o.sx / 2 or math.abs(door.z - o.z) >= o.sz / 2,
					"the door is outside every building"
				)
			end
			local half = if door.fx ~= 0 then b.sx / 2 else b.sz / 2
			near(flat(door.x, door.z, b.x, b.z), half + 6, 0.01, "at the face")
			check(
				flat(door.x, door.z, bt.x, bt.z) < flat(b.x, b.z, bt.x, bt.z),
				"the door faces toward the plaza side"
			)
			-- Downtown's layout is fixed: the same building every week
			local again = SideQuestSites.building(Config, world, "Academy")
			check(again == b, "picked the same way every time")
			check(
				SideQuestSites.building(Config, { downtown = nil }, "Academy") == nil,
				"no Downtown, no site"
			)
		end
	)

	test("Lore 11: Halo Academy's pocket: classrooms, the training hall and the workshop under it", function()
		check(PocketLayout.known("academy"), "a pocket layout")
		local l = PocketLayout.build(Config, 1, "academy")
		check(#l.boxes < 400, "under 400 parts (" .. #l.boxes .. ")")
		local sp = l.points.spawn
		check(PocketLayout.at(Config, sp[1], sp[2], sp[3]) == 1, "the spawn is inside its pocket")
		check(#(l.lists.rooms or {}) >= 2, "two classrooms")
		check(#(l.lists.pods or {}) >= 4, "four scanner pods")
		for _, p in { "hall", "hiddenDoor", "workshop", "boss" } do
			check(l.points[p] ~= nil, "has " .. p)
		end
		local deck = PocketLayout.heightAt(l, sp[1], sp[3])
		check(deck > l.floorY + 20, "the school stands on its floor above the workshop")
		for i, r in l.lists.rooms do
			near(
				PocketLayout.heightAt(l, r[1], r[3]),
				deck,
				0.5,
				"classroom " .. i .. " is on the school floor"
			)
		end
		local hall = l.points.hall
		near(PocketLayout.heightAt(l, hall[1], hall[3]), deck, 0.5, "the training hall")
		for _, name in { "workshop", "boss" } do
			local p = l.points[name]
			near(PocketLayout.heightAt(l, p[1], p[3]), l.floorY, 0.01, name .. " is on the workshop floor")
		end
		for i, p in l.lists.pods do
			near(
				PocketLayout.heightAt(l, p[1], p[3]),
				l.floorY,
				0.01,
				"pod " .. i .. " is not on the ceiling"
			)
		end
		-- under the school: a ceiling over the workshop (robots never stand on it)
		local b = l.points.boss
		local over = false
		for _, x in l.boxes do
			if
				x.tag == "ceiling"
				and math.abs(x.cx - b[1]) <= x.sx / 2
				and math.abs(x.cz - b[3]) <= x.sz / 2
				and x.cy > l.floorY + 20
			then
				over = true
			end
		end
		check(over, "the workshop is under the school's floor")
		-- the hidden stairs: from the door down to the workshop, no step over 2.5 studs
		local from, to = l.points.hiddenDoor, l.points.workshop
		local prev = PocketLayout.heightAt(l, from[1], from[3])
		local ok = true
		for z = from[3], to[3], -1 do
			local h = PocketLayout.heightAt(l, from[1], z)
			if h > prev + 1e-6 or prev - h > 2.5 then
				ok = false
			end
			prev = h
		end
		check(ok and math.abs(prev - l.floorY) < 0.01, "the stairs walk down to the workshop")
		-- every pocket step of the chain finds its places there (the framework's pocket check runs too)
		local pocket = SideQuestPlan.goal(A.steps[5], "hero") :: any
		check(pocket.kind == "pocket" and pocket.layout == "academy", "step 5 is inside the academy")
		local used = {}
		for _, s in pocket.steps do
			used[s.kind] = true
			if s.at then
				check(l.points[s.at] ~= nil, s.kind .. " at " .. s.at)
			end
			if s.room then
				check(l.lists.rooms[s.room] ~= nil, s.kind .. " in room " .. s.room)
			end
			if s.list then
				check(#(l.lists[s.list] or {}) >= (s.points or 1), s.kind .. " on " .. s.list)
			end
			check(SideQuestPlan.POCKET_KINDS[s.kind] == true, s.kind .. " runs in a pocket")
		end
		check(
			used.defeat and used.hold and used.reach and used["break"] and used.boss,
			"class, hall, stairs, pods, foreman"
		)
		check(
			string.find(fs.readFile("src/shared/PocketLayout.luau"), "PLACEHOLDER ART", 1, true) ~= nil,
			"placeholder art labelled"
		)
	end)

	test("Lore 11: Gus and Headmaster Halo wear hero looks that validate through CreatorRules", function()
		local profile = ProfileSchema.default()
		for _, p in CreatorRules.index(Config).list do
			if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
				CreatorRules.grant(profile, p)
			end
		end
		local n = 0
		for id, g in SQ.givers do
			if g.look then
				n += 1
				local look = FakeRules.lookFrom(Config, g.look, id)
				local ok, why = CreatorRules.validate(Config, profile, look)
				check(ok, id .. "'s look validates (" .. tostring(why) .. ")")
				for slot, i in look.pieces do
					if i > 0 then
						local p = CreatorRules.piece(Config, slot, i)
						check(
							p ~= nil and p.source.kind ~= "pack",
							id .. " " .. slot .. " is never a Robux piece"
						)
					end
				end
			end
		end
		check(n >= 1 and SQ.givers.Gus.look ~= nil, "Gus has a look")
		local halo = FakeRules.look(Config, "HeadmasterHalo")
		check(CreatorRules.validate(Config, profile, halo), "Halo's look validates")
		check(FakeRules.plate(Config, "HeadmasterHalo", false).name == "HEADMASTER HALO", "his hero plate")
		check(FakeRules.plate(Config, "HeadmasterHalo", true).name == "FAKE", "FAKE once his face cracks")
		check(Config.Enemies.mix.HeadmasterHalo == nil, "never in the ambient mix")
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		check(string.find(svc, "LookKit.build", 1, true) ~= nil, "the server dresses the giver")
		check(string.find(svc, "FakeRules.lookFrom", 1, true) ~= nil, "from its fixed look")
	end)

	-- one test per side (like the mission tests): that side takes the chain from Gus, a squadmate of the
	-- other side joins from the Journal, and they play all 8 steps together in one run
	for _, lead in SIDES do
		local mate = if lead == "hero" then "villain" else "hero"
		local label = if lead == "villain" then "the Syndicate" else "the Vigil"
		test(
			"Lore 11: The Hero Academy as " .. label .. ": all 8 steps co-op with the other side, to the end",
			function()
				local a, b = afterSafehouse(), afterSafehouse()
				check(SideQuestPlan.accept(Config, a, A, 6, lead, false), "the lead takes it from Gus")
				check(SideQuestPlan.accept(Config, b, A, 6, mate, true), "the squadmate from the Journal")
				local credits = { 0, 0 }
				for i, step in A.steps do
					check(
						SideQuestPlan.stepOf(a, A) == i and SideQuestPlan.stepOf(b, A) == i,
						"both on step " .. i
					)
					local g = SideQuestPlan.newGroup(A.id, i)
					local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
					local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
					if SideQuestPlan.shared(step) then
						check(
							ka == "both" and kb == "both" and newA and not newB,
							"step " .. i .. ": one shared goal"
						)
					else
						check(
							ka == lead and kb == mate and newA and newB,
							"step " .. i .. ": a goal per side"
						)
					end
					for _, k in { ka, kb } do
						local goal =
							SideQuestPlan.goal(step, if k == "villain" then "villain" else "hero") :: any
						check(
							g.sides[k].need == SideQuestPlan.need(goal),
							"step " .. i .. ": " .. k .. "'s need"
						)
					end
					check(
						SideQuestPlan.set(g, ka, g.sides[ka].need),
						"step " .. i .. ": the lead's side finishes"
					)
					if ka ~= kb then
						check(
							SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
							"step " .. i .. ": and waits for the other side"
						)
						check(
							SideQuestPlan.set(g, kb, g.sides[kb].need),
							"step " .. i .. ": the other side finishes"
						)
					end
					check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
					local last = i == #A.steps
					if last then
						check(SideQuestPlan.card(A, i) ~= nil, "Halo's name card at the finale")
					end
					for n, c in { a, b } do
						local cr = SideQuestPlan.stepPay(Config, 6, last)
						credits[n] += cr
						check(
							SideQuestPlan.advance(c, A) == (if last then "done" else "next"),
							"step " .. i .. " moves on"
						)
					end
				end
				for n, c in { a, b } do
					check(
						SideQuestPlan.isDone(c, A) and c.story.pinned == 0 and c.sq.at.HeroAcademy == nil,
						"done, untracked"
					)
					check(
						credits[n] > 0 and SideQuestPlan.chainPay(Config, A, 6) > 0,
						"steps and the end pay"
					)
					check(
						SideQuestPlan.chainsDone(Config, { characters = { c } }) == 1,
						"counts toward the creator's chain pieces"
					)
					check(
						not SideQuestPlan.accept(Config, c, A, 6, if n == 1 then lead else mate, false),
						"once only"
					)
				end
			end
		)
	end

	test("Lore 11: the reward is a chain title and one cosmetic, earned only; nothing sold", function()
		local cos = SideQuestPlan.cosmetic(A)
		local n = 0
		for _ in cos do
			n += 1
		end
		check(n == 2 and cos.title == "Class Dismissed" and cos.style == "CrackedHalo", "a title and a style")
		local bit = Config.Story.unlocks.titles["Class Dismissed"]
		check(type(bit) == "number" and bit < 100, "a story title")
		local seen = {}
		for name, b in Config.Story.unlocks.titles do
			check(not seen[b], "title bit " .. b .. " used once (" .. name .. ")")
			seen[b] = true
		end
		local id = GearMath.questStyle(Config, "CrackedHalo")
		check(id ~= nil, "the Cracked Halo is a gear style")
		local styles = 0
		for _, slot in Config.Gear.slotOrder do
			for _, row in Config.Gear.styles[slot] do
				if row.quest == "CrackedHalo" then
					styles += 1
					check(row.tier == "Story" and row.price == nil, "never rolled, never sold")
				end
			end
		end
		check(styles == 1, "one Cracked Halo")
		check(A.reward.share > 0 and A.reward.share <= SQ.pay.maxShare, "the end's pay share in range")
		for _, k in { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" } do
			check(A.reward[k] == nil, "no " .. k)
		end
	end)

	test(
		"Lore 11: the framework checks a pocket's places, sites and the title plus cosmetic reward",
		function()
			local function deep(v: any): any
				if type(v) ~= "table" then
					return v
				end
				local out = {}
				for k, x in v do
					out[k] = deep(x)
				end
				return out
			end
			local function problems(edit: (any, any) -> ()): string
				local sq = deep(SQ)
				local C = setmetatable({ SideQuests = sq }, { __index = Config })
				local chain = SideQuestPlan.chain(C, "HeroAcademy") :: any
				edit(chain, sq)
				return table.concat(SideQuestPlan.validate(C), " | ")
			end
			local function fails(edit: (any, any) -> (), want: string, label: string)
				local got = problems(edit)
				check(string.find(got, want, 1, true) ~= nil, label .. " (wants: " .. want .. ")")
			end
			check(problems(function() end) == "", "the copy is clean")
			fails(function(c)
				c.steps[5].hero.steps[2].at = "moon"
			end, "point moon is not in academy", "a pocket point that is not there")
			fails(function(c)
				c.steps[5].hero.steps[1].room = 9
			end, "room 9 is not in academy", "a classroom that is not there")
			fails(function(c)
				c.steps[5].hero.steps[4].points = 9
			end, "pods in academy are too few", "more pods than the workshop has")
			fails(function(c)
				c.steps[5].hero.steps[4].hits = nil
			end, "break needs hits", "a break with no hits")
			fails(function(c)
				c.reward.emote = "Bow"
			end, "one cosmetic or title", "two cosmetics with the title")
			fails(function(c)
				c.reward.title, c.reward.style = nil, nil
			end, "one cosmetic or title", "no reward at all")
			check(problems(function(c)
				c.reward.style = nil
			end) == "", "a title alone is fine")
			fails(function(c)
				c.site = "Moon"
			end, "site Moon", "an unknown site")
			fails(function(_, sq)
				sq.givers.Gus.site = "Moon"
			end, "giver Gus: anchor site", "a giver at an unknown site")
			fails(function(_, sq)
				sq.sites.Academy.away.row = nil
			end, "away.row", "a site without its row distance")
			fails(function(c)
				c.blurb.villain = "Steal %s"
			end, "villain blurb", "a page line with a format hole")
		end
	)

	test("Lore 11: no old names in the chain; the Dev panel starts it and jumps to each step", function()
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local hits = {}
		local function walk(v: any, path: string)
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w)
				end
				for _, a in ARC do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a)
					end
				end
			elseif type(v) == "table" then
				for k, x in v do
					walk(x, path .. "." .. tostring(k))
				end
			end
		end
		walk(A, "HeroAcademy")
		walk(SQ.givers.Gus, "Gus")
		walk(SQ.sites, "sites")
		walk(Config.Story.guides.speakers.halo, "halo")
		walk(Config.Story.guides.speakers.wren, "wren")
		for _, id in { "academyGates", "wrenStory", "haloBell" } do
			walk(Config.Cinema.scenes[id], id)
		end
		walk(Config.Cinema.comic.pages.wrenStory, "wrenStory page")
		walk(Config.Enemies.HeadmasterHalo, "HeadmasterHalo")
		for _, h in hits do
			check(false, "an old name: " .. h)
		end
		check(#hits == 0, "no old lore or retired arc names")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(string.find(dev, "SQ chain: ", 1, true) ~= nil, "Dev panel: start a chain")
		check(string.find(dev, "SQ: start step", 1, true) ~= nil, "Dev panel: jump to a step")
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		check(
			string.find(svc, "what > 300 and SQ.chains[what - 300]", 1, true) ~= nil,
			"the server starts it"
		)
		check(
			#A.steps <= SQ.maxSteps and 300 + #SQ.chains <= 1000,
			"every step and chain fits the Dev command"
		)
	end)
end

---------------------------------------------------------------------------
-- Lore step 11, chain 3: Wind-Up Lane (the Suburbs). Config.SideQuests (the chain, Scoops, the ToyShop site),
-- Shared.SideQuestSites.outskirts (a seeded Suburbs shop lot), PocketLayout "toyshop" (its inside), the
-- Toymaker's clockwork toys (Config.Enemies.WindupToy and WindupGiant), the scenes, the reward, the Dev panel.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local EnemyVariety = require("../src/shared/EnemyVariety")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local W = SideQuestPlan.chain(Config, "WindUpLane") :: any
	local SIDES = { "hero", "villain" }
	local TOYS = { "WindupToy", "WindupGiant" }

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	-- a hero who has cleared Act 1's Ceremony and Safehouse
	local function afterSafehouse(): any
		local c = ProfileSchema.newCharacter()
		c.story.missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
		return c
	end

	test(
		"Lore 11 Suburbs: Wind-Up Lane validates: 8 Suburbs quests, each side's flavour, the Toymaker",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			check(W ~= nil and not W.dev, "a real chain")
			check(#W.steps == 8 and W.layer == "district" and W.district == "Suburbs", "8 Suburbs quests")
			local sc = SQ.givers.Scoops
			check(W.giver == "Scoops" and not sc.dev and sc.anchor == "site", "Scoops gives it at a site")
			check(W.site == "ToyShop" and sc.site == "ToyShop", "Tick-Tock Toys")
			check(W.bit ~= SideQuestPlan.chain(Config, "HeroAcademy").bit, "its own save bit")
			local last = W.steps[#W.steps]
			local fin = SideQuestPlan.goal(last, "hero") :: any
			check(
				SideQuestPlan.shared(last) and fin.kind == "finale" and fin.enemy == "WindupGiant",
				"the Toymaker's giant, both sides together"
			)
			check(table.find(SQ.finale.enemies, "WindupGiant") ~= nil, "the giant is on the finale list")
			local kinds = { hero = {}, villain = {} }
			local split = 0
			for i, step in W.steps do
				for _, side in SIDES do
					kinds[side][(SideQuestPlan.goal(step, side) :: any).kind] = true
				end
				if SideQuestPlan.shared(step) then
					local g = SideQuestPlan.goal(step, "hero") :: any
					check(
						type(g.villainText) == "string" and g.villainText ~= g.text,
						"step " .. i .. ": the Syndicate reads its own goal"
					)
				else
					split += 1
					check(
						SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
							~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
						"step " .. i .. ": each side's own job"
					)
				end
			end
			check(split >= 5, "most steps give each side its own job (" .. split .. ")")
			-- the Vigil rescue and protect; the Dread Syndicate heist and sabotage
			for _, k in { "fight", "find", "escort", "carry", "hold" } do
				check(kinds.hero[k] == true, "the Vigil: " .. k)
			end
			for _, k in { "fetch", "chase", "deliver", "race" } do
				check(kinds.villain[k] == true, "the Syndicate: " .. k)
			end
			check(kinds.hero.pocket and kinds.villain.pocket, "inside the toy shop, both sides")
			-- the toys are the chain's robots: every fight, guard, chase and add is a clockwork toy
			local toyOnly = true
			for _, step in W.steps do
				for _, side in SIDES do
					local g = SideQuestPlan.goal(step, side) :: any
					for _, row in g.squads or {} do
						toyOnly = toyOnly and table.find(TOYS, row[1]) ~= nil
					end
					for _, row in g.adds or {} do
						toyOnly = toyOnly and table.find(TOYS, row[1]) ~= nil
					end
					if g.guards then
						toyOnly = toyOnly and table.find(TOYS, g.guards[1]) ~= nil
					end
					if g.kind == "chase" or g.kind == "finale" then
						toyOnly = toyOnly and table.find(TOYS, g.enemy) ~= nil
					end
					for _, s in g.steps or {} do
						for _, row in s.squads or {} do
							toyOnly = toyOnly and table.find(TOYS, row[1]) ~= nil
						end
						if s.enemy then
							toyOnly = toyOnly and table.find(TOYS, s.enemy) ~= nil
						end
					end
					check(g.kind ~= "photo", "no photo step (it spawns Sneak Bots, not toys)")
				end
			end
			check(
				toyOnly,
				"every robot in the chain is one of the Toymaker's toys (standalone: no Crane robots)"
			)
			local who = {}
			for _, step in W.steps do
				for _, l in step.lines or {} do
					who[l.who] = true
				end
			end
			for _, w in { "Scoops", "patch", "lodestar", "toymaker", "toby" } do
				check(who[w] == true, "speaks: " .. w)
			end
			for _, w in { "toymaker", "toby" } do
				local sp = Config.Story.guides.speakers[w]
				check(
					sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
					w .. ": a guide speaker with a portrait and a blip"
				)
			end
			local scenes = 0
			for _, step in W.steps do
				if step.scene then
					scenes += 1
					local s = Config.Cinema.scenes[step.scene]
					check(s ~= nil and s.client == true, step.scene .. ": a device scene")
					check(s and CinemaPlan.check(Config, s), step.scene .. ": 5 to 20 s")
					check(s and s.bit >= 0 and s.bit <= 15, step.scene .. ": a named scene bit")
					for _, l in (s and s.lines) or {} do
						check(
							Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
							step.scene .. ": speaker " .. tostring(l.who)
						)
					end
				end
			end
			check(scenes >= 1 and scenes <= 3, "1 to 3 short scenes (" .. scenes .. ")")
			check(last.scene ~= nil, "a scene before the Toymaker's finale")
			local seenBits = {}
			for id, s in Config.Cinema.scenes do
				check(not seenBits[s.bit], "scene bit " .. s.bit .. " used once (" .. id .. ")")
				seenBits[s.bit] = true
			end
			local page = Config.Cinema.comic.pages.tobyStory
			check(page ~= nil and #page.panels == 4, "Toby's story is a comic page")
			local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
			for _, p in page.panels do
				check(
					string.find(hud, 'kind == "' .. p.scene .. '"', 1, true) ~= nil,
					"the comic draws " .. p.scene
				)
			end
		end
	)

	test("Lore 11 Suburbs: the finale's name card: THE TOYMAKER on the last step only", function()
		for i = 1, #W.steps - 1 do
			check(SideQuestPlan.card(W, i) == nil, "no card on step " .. i)
		end
		local card = SideQuestPlan.card(W, #W.steps) :: any
		check(card ~= nil and card.name == "THE TOYMAKER", "the finale's card names the Toymaker")
		check(card and card.title == "THE OLD INVENTOR", "and his title")
		check(
			SideQuestPlan.fixedText(card.name, 32) == nil and SideQuestPlan.fixedText(card.title, 32) == nil,
			"fixed text that fits the card"
		)
	end)

	test(
		"Lore 11 Suburbs: it opens after the Safehouse at the Suburbs' level for both sides; Scoops offers it",
		function()
			for _, side in SIDES do
				local c = ProfileSchema.newCharacter()
				c.story.missions = StoryPlan.setBit(0, 1)
				local st, why, n = SideQuestPlan.state(Config, c, W, 10, side)
				check(st == "locked" and why == "story" and n == 2, side .. ": waits for the Safehouse")
				check(
					select(2, SideQuestPlan.talkPick(Config, c, "Scoops", 10, side, false)) == "none",
					side .. ": Scoops has nothing yet"
				)
				local d = afterSafehouse()
				local st2, why2, lv = SideQuestPlan.state(Config, d, W, 4, side)
				check(
					st2 == "locked" and why2 == "level" and lv == Config.World.zoneFloor.suburbs,
					side .. ": and the Suburbs' level floor"
				)
				check(SideQuestPlan.state(Config, d, W, 5, side) == "open", side .. ": open at level 5")
				local pick, kind = SideQuestPlan.talkPick(Config, d, "Scoops", 5, side, false)
				check(pick == W and kind == "offer", side .. ": Scoops offers it")
				check(SideQuestPlan.fixedText(W.blurb[side], 90) == nil, side .. ": the page's line")
				check(SideQuestPlan.fixedText(W.lines.offer[side], 120) == nil, side .. ": Scoops's offer")
				-- the Hero Academy's giver never offers it, and Scoops never offers the Academy
				local gp = SideQuestPlan.talkPick(Config, d, "Gus", 5, side, false)
				check(gp ~= W, side .. ": Gus never offers it")
			end
			local J = fs.readFile("src/client/Ui/Journal.luau")
			check(string.find(J, 'Suburbs = "the Suburbs"', 1, true) ~= nil, "the Journal names the Suburbs")
		end
	)

	test("Lore 11 Suburbs: Tick-Tock Toys is a seeded Suburbs shop lot, picked by rule every week", function()
		local st = SQ.sites.ToyShop
		check(
			SideQuestSites.isOutskirts(st) and not SideQuestSites.isOutskirts(SQ.sites.Academy),
			"an outskirts site"
		)
		check(SideQuestSites.building(Config, world, "ToyShop") == nil, "never a Downtown building")
		local gy = Config.City.ground.y
		local Z = Config.World.zones
		for _, seed in { 202647, 202648, 202701, 202720, 202752 } do
			local wd = if seed == 202647 then world else WorldMap.build(Config, seed)
			local b, door = SideQuestSites.place(Config, wd, "ToyShop")
			check(b ~= nil and door ~= nil, seed .. ": a shop fits")
			if b and door then
				local t = WorldGen.get(Config.World, wd.tiles, b.tx, b.tz)
				check(
					t.zone == Z.suburbs and t.variant ~= Config.World.special,
					seed .. ": on a Suburbs tile"
				)
				local ring = WorldGen.ring(Config.World, b.tx, b.tz)
				check(ring >= st.rings[1] and ring <= st.rings[2], seed .. ": ring " .. ring .. " in range")
				check(b.lot.kind == "shop", seed .. ": a shop lot")
				local tx, tz = WorldGen.tileOf(Config.City, b.x, b.z)
				check(tx == b.tx and tz == b.tz, seed .. ": the building stands on its tile")
				check(b.h >= st.height[1] and b.h <= st.height[2], seed .. ": a one-storey shop")
				local a = st.away
				for _, s in wd.safehouses do
					check(flat(b.x, b.z, s.x, s.z) >= a.pad, seed .. ": clear of safehouse " .. s.id)
				end
				for _, bc in wd.beacons do
					check(flat(b.x, b.z, bc.x, bc.z) >= a.beacon, seed .. ": clear of beacon " .. bc.id)
				end
				for name, dr in Config.City.districts do
					check(
						b.x < dr.minX - a.district
							or b.x > dr.maxX + a.district
							or b.z < dr.minZ - a.district
							or b.z > dr.maxZ + a.district
							or flat(
									b.x,
									b.z,
									math.clamp(b.x, dr.minX, dr.maxX),
									math.clamp(b.z, dr.minZ, dr.maxZ)
								)
								>= a.district,
						seed .. ": clear of " .. name
					)
				end
				local ac = SideQuestSites.building(Config, wd, "Academy")
				check(ac ~= nil and flat(b.x, b.z, ac.x, ac.z) >= a.site, seed .. ": far from Halo Academy")
				-- the door: the shop's front, open ground in front of it, not inside any outskirts box
				near(door.z, b.z + b.sz / 2 + 6, 1e-6, seed .. ": the door is at the front")
				check(WorldMap.heightAt(wd, door.x, door.z) <= gy + 1.5, seed .. ": open ground at the door")
				-- among the Suburbs' houses: mailboxes and power poles from the city kit around it
				local mail, poles = 0, 0
				for _, p in wd.props do
					local d = flat(p.x, p.z, b.x, b.z)
					if p.name == "Mailbox" and d <= 160 then
						mail += 1
					elseif p.name == "PowerPole" and d <= 160 then
						poles += 1
					end
				end
				check(mail >= 1 and poles >= 1, seed .. ": mailboxes and power poles nearby")
				local again = SideQuestSites.outskirts(Config, wd, "ToyShop")
				check(again and again.x == b.x and again.z == b.z, seed .. ": the same seed, the same shop")
			end
		end
		-- the framework checks an outskirts site's rules
		local function deep(v: any): any
			if type(v) ~= "table" then
				return v
			end
			local out = {}
			for k, x in v do
				out[k] = deep(x)
			end
			return out
		end
		local function problems(edit: (any) -> ()): string
			local sq = deep(SQ)
			edit(sq.sites.ToyShop)
			local C = setmetatable({ SideQuests = sq }, { __index = Config })
			return table.concat(SideQuestPlan.validate(C), " | ")
		end
		check(problems(function() end) == "", "the copy is clean")
		check(string.find(
			problems(function(s)
				s.lot = "moon"
			end),
			"lot moon is not a Suburbs lot",
			1,
			true
		) ~= nil, "an unknown lot kind")
		check(string.find(
			problems(function(s)
				s.rings = { 2, 9 }
			end),
			"rings inside the Suburbs",
			1,
			true
		) ~= nil, "rings past the Suburbs")
		check(string.find(
			problems(function(s)
				s.away.pad = nil
			end),
			"away.pad",
			1,
			true
		) ~= nil, "no safehouse distance")
		check(string.find(
			problems(function(s)
				s.district = "Downtown"
			end),
			"district Downtown",
			1,
			true
		) ~= nil, "an outskirts site is in the Suburbs")
		-- the server stands Scoops at the door and marks the map for any site (the framework's own hooks)
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		check(
			string.find(svc, "SideQuestSites.place(Config, world, id)", 1, true) ~= nil,
			"the server places it"
		)
	end)

	test(
		"Lore 11 Suburbs: Tick-Tock Toys' pocket: the aisles, the playroom and the workshop under it",
		function()
			check(PocketLayout.known("toyshop"), "a pocket layout")
			local l = PocketLayout.build(Config, 1, "toyshop")
			check(#l.boxes < 400, "under 400 parts (" .. #l.boxes .. ")")
			local sp = l.points.spawn
			check(PocketLayout.at(Config, sp[1], sp[2], sp[3]) == 1, "the spawn is inside its pocket")
			check(#(l.lists.rooms or {}) >= 2, "two toy aisles")
			check(#(l.lists.winders or {}) >= 4, "four winders")
			for _, p in { "playroom", "trapdoor", "workshop", "boss" } do
				check(l.points[p] ~= nil, "has " .. p)
			end
			local deck = PocketLayout.heightAt(l, sp[1], sp[3])
			check(deck > l.floorY + 15, "the shop stands on its floor above the workshop")
			for i, r in l.lists.rooms do
				near(
					PocketLayout.heightAt(l, r[1], r[3]),
					deck,
					0.5,
					"aisle " .. i .. " is on the shop floor"
				)
			end
			local pr = l.points.playroom
			near(PocketLayout.heightAt(l, pr[1], pr[3]), deck, 0.5, "the playroom")
			for _, name in { "workshop", "boss" } do
				local p = l.points[name]
				near(
					PocketLayout.heightAt(l, p[1], p[3]),
					l.floorY,
					0.01,
					name .. " is on the workshop floor"
				)
			end
			for i, p in l.lists.winders do
				near(
					PocketLayout.heightAt(l, p[1], p[3]),
					l.floorY,
					0.01,
					"winder " .. i .. " is on the floor"
				)
			end
			local b = l.points.boss
			local over = false
			for _, x in l.boxes do
				if
					x.tag == "ceiling"
					and math.abs(x.cx - b[1]) <= x.sx / 2
					and math.abs(x.cz - b[3]) <= x.sz / 2
					and x.cy > l.floorY + 15
				then
					over = true
				end
			end
			check(over, "the workshop is under the shop's floor")
			local from, to = l.points.trapdoor, l.points.workshop
			local prev = PocketLayout.heightAt(l, from[1], from[3])
			local ok = true
			for z = from[3], to[3], -1 do
				local h = PocketLayout.heightAt(l, from[1], z)
				if h > prev + 1e-6 or prev - h > 2.5 then
					ok = false
				end
				prev = h
			end
			check(ok and math.abs(prev - l.floorY) < 0.01, "the stairs walk down to the workshop")
			local pocket = SideQuestPlan.goal(W.steps[5], "hero") :: any
			check(pocket.kind == "pocket" and pocket.layout == "toyshop", "step 5 is inside the shop")
			local used = {}
			for _, s in pocket.steps do
				used[s.kind] = true
				if s.at then
					check(l.points[s.at] ~= nil, s.kind .. " at " .. s.at)
				end
				if s.room then
					check(l.lists.rooms[s.room] ~= nil, s.kind .. " in aisle " .. s.room)
				end
				if s.list then
					check(#(l.lists[s.list] or {}) >= (s.points or 1), s.kind .. " on " .. s.list)
				end
			end
			check(
				used.defeat and used.hold and used.reach and used["break"] and used.boss,
				"aisles, playroom, trapdoor, winders, captain"
			)
		end
	)

	test(
		"Lore 11 Suburbs: the Toymaker's toys: switches, uniforms, never ambient, a boss-lite giant",
		function()
			local profile = ProfileSchema.default()
			for _, p in CreatorRules.index(Config).list do
				if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
					CreatorRules.grant(profile, p)
				end
			end
			local look = FakeRules.lookFrom(Config, SQ.givers.Scoops.look, "Scoops")
			local ok, why = CreatorRules.validate(Config, profile, look)
			check(ok, "Scoops's look validates (" .. tostring(why) .. ")")
			for slot, i in look.pieces do
				if i > 0 then
					local p = CreatorRules.piece(Config, slot, i)
					check(
						p ~= nil and p.source.kind ~= "pack",
						"Scoops " .. slot .. " is never a Robux piece"
					)
				end
			end
			local NL = Config.NpcLooks
			for _, kind in TOYS do
				local cfg = Config.Enemies[kind]
				check(cfg.on == true and cfg.fake == nil, kind .. ": a machine with an on switch")
				check(table.find(Config.Enemies.order, kind) ~= nil, kind .. " is in the order")
				check(Config.Enemies.mix[kind] == nil, kind .. " never spawns in the ambient mix")
				for _, sw in Config.Enemies.variety.swaps do
					check(
						sw.kind ~= kind and table.find(sw.from, kind) == nil,
						kind .. " is never swapped in or out"
					)
				end
				check(cfg.body.windKey == true, kind .. " has its wind-up key")
				check(NL.robots[kind] ~= nil, kind .. " has its three toy uniforms")
				for _, v in NL.versions do
					check(
						fs.isFile("art/export/clothes/uniforms/" .. kind .. "_" .. v .. ".png"),
						kind .. " " .. v .. " uniform is drawn for upload"
					)
				end
				-- switched off: never spawns
				cfg.on = false
				local sim = EnemySim.new(Config, {})
				local gone = EnemySim.spawn(sim, kind, 0, 0, 0, 1) == nil
				cfg.on = true
				check(gone, kind .. " off: never spawns")
				check(
					EnemySim.spawn(EnemySim.new(Config, {}), kind, 0, 0, 0, 1) ~= nil,
					kind .. " on: spawns"
				)
			end
			local rng = Rng.new(9)
			local function rand(): number
				return rng:next()
			end
			for _ = 1, 50 do
				for _, row in EnemyVariety.squad(Config, { { kind = "WindupToy", n = 6 } }, 40, rand) do
					check(row.kind == "WindupToy", "a toy squad stays toys")
				end
			end
			local rend = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
			check(string.find(rend, "body.windKey", 1, true) ~= nil, "the renderer draws the key")
			local G = Config.Enemies.WindupGiant
			check(
				G.elite and G.miniBoss and G.body.height > 2 * Config.Enemies.WindupToy.body.height,
				"a giant elite"
			)
			check(Config.Enemies.WindupToy.body.small == true, "the toys are knee-high")
			for _, lv in { 5, 20, 50 } do
				local elite = 0
				for _, kind in Config.Enemies.order do
					local cfg = Config.Enemies[kind]
					if cfg.elite and not cfg.fake and kind ~= "WindupGiant" then
						elite = math.max(elite, robotDps(kind, lv))
					end
				end
				local d = robotDps("WindupGiant", lv)
				check(
					d > 0.5 * elite and d <= elite,
					string.format("L%d the giant %.1f is boss-lite: up to the elites' %.1f", lv, d, elite)
				)
			end
		end
	)

	for _, lead in SIDES do
		local mate = if lead == "hero" then "villain" else "hero"
		local label = if lead == "villain" then "the Syndicate" else "the Vigil"
		test(
			"Lore 11 Suburbs: Wind-Up Lane as " .. label .. ": all 8 steps co-op with the other side",
			function()
				local a, b = afterSafehouse(), afterSafehouse()
				check(SideQuestPlan.accept(Config, a, W, 6, lead, false), "the lead takes it from Scoops")
				check(SideQuestPlan.accept(Config, b, W, 6, mate, true), "the squadmate from the Journal")
				local credits = { 0, 0 }
				for i, step in W.steps do
					check(
						SideQuestPlan.stepOf(a, W) == i and SideQuestPlan.stepOf(b, W) == i,
						"both on step " .. i
					)
					local g = SideQuestPlan.newGroup(W.id, i)
					local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
					local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
					if SideQuestPlan.shared(step) then
						check(
							ka == "both" and kb == "both" and newA and not newB,
							"step " .. i .. ": one shared goal"
						)
					else
						check(
							ka == lead and kb == mate and newA and newB,
							"step " .. i .. ": a goal per side"
						)
					end
					check(
						SideQuestPlan.set(g, ka, g.sides[ka].need),
						"step " .. i .. ": the lead's side finishes"
					)
					if ka ~= kb then
						check(
							SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
							"step " .. i .. ": and waits for the other side"
						)
						check(
							SideQuestPlan.set(g, kb, g.sides[kb].need),
							"step " .. i .. ": the other side finishes"
						)
					end
					check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
					local last = i == #W.steps
					if last then
						check(SideQuestPlan.card(W, i) ~= nil, "the Toymaker's name card at the finale")
					end
					for n, c in { a, b } do
						credits[n] += SideQuestPlan.stepPay(Config, 6, last)
						check(
							SideQuestPlan.advance(c, W) == (if last then "done" else "next"),
							"step " .. i .. " moves on"
						)
					end
				end
				for n, c in { a, b } do
					check(
						SideQuestPlan.isDone(c, W) and c.story.pinned == 0 and c.sq.at.WindUpLane == nil,
						"done, untracked"
					)
					check(
						credits[n] > 0 and SideQuestPlan.chainPay(Config, W, 6) > 0,
						"steps and the end pay"
					)
					check(
						not SideQuestPlan.accept(Config, c, W, 6, if n == 1 then lead else mate, false),
						"once only"
					)
					check(
						not SideQuestPlan.isDone(c, SideQuestPlan.chain(Config, "HeroAcademy")),
						"the Hero Academy is untouched"
					)
				end
			end
		)
	end

	test("Lore 11 Suburbs: the reward is a chain title and one cosmetic; side rep pays every step", function()
		local cos = SideQuestPlan.cosmetic(W)
		local n = 0
		for _ in cos do
			n += 1
		end
		check(n == 2 and cos.title == "Unwound" and cos.style == "ClockworkPack", "a title and a style")
		local bit = Config.Story.unlocks.titles.Unwound
		check(type(bit) == "number" and bit < 100, "a story title")
		check(GearMath.questStyle(Config, "ClockworkPack") ~= nil, "the Clockwork Pack is a gear style")
		local styles = 0
		for _, slot in Config.Gear.slotOrder do
			local ns = {}
			for _, row in Config.Gear.styles[slot] do
				check(not ns[row.n], slot .. " style n " .. row.n .. " used once")
				ns[row.n] = true
				if row.quest == "ClockworkPack" then
					styles += 1
					check(row.tier == "Story" and row.price == nil, "never rolled, never sold")
				end
			end
		end
		check(styles == 1, "one Clockwork Pack")
		for _, k in { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" } do
			check(W.reward[k] == nil, "no " .. k)
		end
		-- lore step 12: every step a hero finishes fires StepPaid (any chain), and RepService pays side rep on it
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		local at =
			string.find(svc, 'SideQuestService.StepPaid:Fire(player, res == "done", chain.id)', 1, true)
		check(at ~= nil, "the step's pay fires StepPaid")
		local adv = string.find(svc, "local res = SideQuestPlan.advance(c, chain)", 1, true)
		check(adv ~= nil and at and adv < at, "after the save moves on, for whatever chain it is")
		check(string.find(svc, "WindUpLane", 1, true) == nil, "nothing chain-specific in the service")
		local rep = fs.readFile("src/server/Services/RepService.luau")
		check(string.find(rep, "SideQuestService.StepPaid:Connect", 1, true) ~= nil, "RepService listens")
		local E = Config.Remembers.earn
		check(E.sideStep > 0 and E.sideFinale > E.sideStep, "a step and the finale pay rep")
	end)

	test("Lore 11 Suburbs: no old names or Crane in the chain; the Dev panel covers it", function()
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local hits = {}
		local function walk(v: any, path: string)
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w)
				end
				for _, a in ARC do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a)
					end
				end
				for _, a in { "Crane", "Halcyon", "Adrian Vale", "Null" } do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a .. " (standalone chain)")
					end
				end
			elseif type(v) == "table" then
				for k, x in v do
					walk(x, path .. "." .. tostring(k))
				end
			end
		end
		walk(W, "WindUpLane")
		walk(SQ.givers.Scoops, "Scoops")
		walk(SQ.sites.ToyShop, "ToyShop")
		walk(Config.Story.guides.speakers.toymaker, "toymaker")
		walk(Config.Story.guides.speakers.toby, "toby")
		for _, id in { "tickTockLane", "tobyStory", "windupGiant" } do
			walk(Config.Cinema.scenes[id], id)
		end
		walk(Config.Cinema.comic.pages.tobyStory, "tobyStory page")
		for _, kind in TOYS do
			walk(Config.Enemies[kind], kind)
		end
		for _, h in hits do
			check(false, "an old name: " .. h)
		end
		check(#hits == 0, "no old lore, retired arc names or main-story names")
		local idx = table.find(SQ.chains, W) :: number
		check(idx ~= nil and 300 + idx <= 1000, "the Dev panel's SQ chain button reaches it")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(
			string.find(dev, "if not ch.dev then", 1, true) ~= nil,
			"every real chain is on the SQ chain button"
		)
		check(#W.steps <= SQ.maxSteps, "every step fits SQ: start step")
	end)
end

---------------------------------------------------------------------------
-- Lore step 11, the Coast chain: The Salt Dogs. Config.SideQuests (the chain, Skipper Nell, the GullPier
-- site), Shared.SideQuestSites.shore (a seeded coast pier, WorldGen.pier), PocketLayout "seacave" (Brine's sea
-- cave), Captain Brine's crew (Config.Enemies.SaltDog and CaptainBrine), the scenes, the reward, the Dev panel.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local EnemyVariety = require("../src/shared/EnemyVariety")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local S = SideQuestPlan.chain(Config, "SaltDogs") :: any
	local SIDES = { "hero", "villain" }
	local CREW = { "SaltDog", "CaptainBrine" }

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	-- a hero who has cleared Act 1's Ceremony and Safehouse
	local function afterSafehouse(): any
		local c = ProfileSchema.newCharacter()
		c.story.missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
		return c
	end

	test(
		"Lore 11 Coast: The Salt Dogs validates: 8 Coast quests, each side's flavour, Captain Brine",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			check(S ~= nil and not S.dev, "a real chain")
			check(#S.steps == 8 and S.layer == "district" and S.district == "Coast", "8 Coast quests")
			local nl = SQ.givers.Nell
			check(S.giver == "Nell" and not nl.dev and nl.anchor == "site", "Skipper Nell gives it at a site")
			check(S.site == "GullPier" and nl.site == "GullPier", "Gull Point Pier")
			for _, other in SQ.chains do
				check(other == S or other.bit ~= S.bit, "its own save bit (" .. tostring(other.id) .. ")")
			end
			local last = S.steps[#S.steps]
			local fin = SideQuestPlan.goal(last, "hero") :: any
			check(
				SideQuestPlan.shared(last) and fin.kind == "finale" and fin.enemy == "CaptainBrine",
				"Captain Brine, both sides together"
			)
			check(table.find(SQ.finale.enemies, "CaptainBrine") ~= nil, "Brine is on the finale list")
			local kinds = { hero = {}, villain = {} }
			local split = 0
			for i, step in S.steps do
				for _, side in SIDES do
					kinds[side][(SideQuestPlan.goal(step, side) :: any).kind] = true
				end
				if SideQuestPlan.shared(step) then
					local g = SideQuestPlan.goal(step, "hero") :: any
					check(
						type(g.villainText) == "string" and g.villainText ~= g.text,
						"step " .. i .. ": the Syndicate reads its own goal"
					)
				else
					split += 1
					check(
						SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
							~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
						"step " .. i .. ": each side's own job"
					)
				end
			end
			check(split >= 5, "most steps give each side its own job (" .. split .. ")")
			-- the Vigil rescue, protect and expose the fake ghost ship; the Dread Syndicate heist and sabotage
			for _, k in { "fight", "find", "escort", "carry", "hold" } do
				check(kinds.hero[k] == true, "the Vigil: " .. k)
			end
			for _, k in { "fetch", "chase", "deliver", "race" } do
				check(kinds.villain[k] == true, "the Syndicate: " .. k)
			end
			check(kinds.hero.pocket and kinds.villain.pocket, "inside the sea cave, both sides")
			-- every robot in the chain is Brine's crew: machines only, standalone (no Crane robots)
			local crewOnly = true
			for _, step in S.steps do
				for _, side in SIDES do
					local g = SideQuestPlan.goal(step, side) :: any
					for _, row in g.squads or {} do
						crewOnly = crewOnly and table.find(CREW, row[1]) ~= nil
					end
					for _, row in g.adds or {} do
						crewOnly = crewOnly and table.find(CREW, row[1]) ~= nil
					end
					if g.guards then
						crewOnly = crewOnly and table.find(CREW, g.guards[1]) ~= nil
					end
					if g.kind == "chase" or g.kind == "finale" then
						crewOnly = crewOnly and table.find(CREW, g.enemy) ~= nil
					end
					for _, s in g.steps or {} do
						for _, row in s.squads or {} do
							crewOnly = crewOnly and table.find(CREW, row[1]) ~= nil
						end
						for _, row in s.waves or {} do
							crewOnly = crewOnly and table.find(CREW, row[1]) ~= nil
						end
						if s.enemy then
							crewOnly = crewOnly and table.find(CREW, s.enemy) ~= nil
						end
					end
					check(g.kind ~= "photo", "no photo step (it spawns Sneak Bots, not Salt Dogs)")
				end
			end
			check(crewOnly, "every robot in the chain is one of Brine's Salt Dogs")
			local who = {}
			for _, step in S.steps do
				for _, l in step.lines or {} do
					who[l.who] = true
				end
			end
			for _, w in { "Nell", "patch", "lodestar", "brine", "finn" } do
				check(who[w] == true, "speaks: " .. w)
			end
			for _, w in { "brine", "finn" } do
				local sp = Config.Story.guides.speakers[w]
				check(
					sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
					w .. ": a guide speaker with a portrait and a blip"
				)
			end
			local sb = Config.Cinema.extraBits
			local scenes = 0
			for _, step in S.steps do
				if step.scene then
					scenes += 1
					local s = Config.Cinema.scenes[step.scene]
					check(s ~= nil and s.client == true, step.scene .. ": a device scene")
					check(s and CinemaPlan.check(Config, s), step.scene .. ": 5 to 20 s")
					check(
						s and s.bit >= sb.from and s.bit <= sb.to and CinemaPlan.clientBit(Config, s.bit),
						step.scene .. ": a side quest scene bit a device may send"
					)
					for _, l in (s and s.lines) or {} do
						check(
							Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
							step.scene .. ": speaker " .. tostring(l.who)
						)
					end
				end
			end
			check(scenes >= 1 and scenes <= 3, "1 to 3 short scenes (" .. scenes .. ")")
			check(last.scene ~= nil, "a scene before Brine's finale")
			check(
				sb.from > 16 + 8 * Config.Cinema.missionBits.missions - 1 and sb.to < 128,
				"past the missions' bits"
			)
			local seenBits = {}
			for id, s in Config.Cinema.scenes do
				check(not seenBits[s.bit], "scene bit " .. s.bit .. " used once (" .. id .. ")")
				seenBits[s.bit] = true
			end
			local page = Config.Cinema.comic.pages.brineLegend
			check(page ~= nil and #page.panels == 4, "the legend of Captain Brine is a comic page")
			local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
			for _, p in page.panels do
				check(
					string.find(hud, 'kind == "' .. p.scene .. '"', 1, true) ~= nil,
					"the comic draws " .. p.scene
				)
			end
		end
	)

	test("Lore 11 Coast: the finale's name card: CAPTAIN BRINE on the last step only", function()
		for i = 1, #S.steps - 1 do
			check(SideQuestPlan.card(S, i) == nil, "no card on step " .. i)
		end
		local card = SideQuestPlan.card(S, #S.steps) :: any
		check(card ~= nil and card.name == "CAPTAIN BRINE", "the finale's card names Captain Brine")
		check(card and card.title == "CAPTAIN OF THE SALT DOGS", "and his title")
		check(
			SideQuestPlan.fixedText(card.name, 32) == nil and SideQuestPlan.fixedText(card.title, 32) == nil,
			"fixed text that fits the card"
		)
	end)

	test(
		"Lore 11 Coast: it opens after the Safehouse at the coast's level for both sides; Nell offers it",
		function()
			for _, side in SIDES do
				local c = ProfileSchema.newCharacter()
				c.story.missions = StoryPlan.setBit(0, 1)
				local st, why, n = SideQuestPlan.state(Config, c, S, 30, side)
				check(st == "locked" and why == "story" and n == 2, side .. ": waits for the Safehouse")
				check(
					select(2, SideQuestPlan.talkPick(Config, c, "Nell", 30, side, false)) == "none",
					side .. ": Nell has nothing yet"
				)
				local d = afterSafehouse()
				local st2, why2, lv = SideQuestPlan.state(Config, d, S, 19, side)
				check(
					st2 == "locked" and why2 == "level" and lv == Config.World.zoneFloor.coast,
					side .. ": and the coast's level floor"
				)
				check(SideQuestPlan.state(Config, d, S, 20, side) == "open", side .. ": open at level 20")
				local pick, kind = SideQuestPlan.talkPick(Config, d, "Nell", 20, side, false)
				check(pick == S and kind == "offer", side .. ": Nell offers it")
				check(SideQuestPlan.fixedText(S.blurb[side], 90) == nil, side .. ": the page's line")
				check(SideQuestPlan.fixedText(S.lines.offer[side], 120) == nil, side .. ": Nell's offer")
				check(
					SideQuestPlan.talkPick(Config, d, "Scoops", 20, side, false) ~= S,
					side .. ": Scoops never offers it"
				)
			end
			local J = fs.readFile("src/client/Ui/Journal.luau")
			check(string.find(J, 'Coast = "the Coast"', 1, true) ~= nil, "the Journal names the Coast")
		end
	)

	test("Lore 11 Coast: Gull Point Pier is a seeded coast pier, picked by rule every week", function()
		local st = SQ.sites.GullPier
		check(
			SideQuestSites.isOutskirts(st)
				and SideQuestSites.isShore(st)
				and not SideQuestSites.isShore(SQ.sites.ToyShop),
			"an outskirts site on the shore"
		)
		check(SideQuestSites.building(Config, world, "GullPier") == nil, "never a Downtown building")
		local gy = Config.City.ground.y
		local W = Config.World
		local half = Config.City.mapSize / 2
		for _, seed in { 202647, 202648, 202701, 202720, 202752 } do
			local wd = if seed == 202647 then world else WorldMap.build(Config, seed)
			local b, door = SideQuestSites.place(Config, wd, "GullPier")
			check(b ~= nil and door ~= nil, seed .. ": a pier fits")
			if b and door then
				local t = WorldGen.get(W, wd.tiles, b.tx, b.tz)
				check(
					t.zone == W.zones.coast and WorldGen.COAST[t.variant + 1] == "pier",
					seed .. ": on a coast pier tile"
				)
				local ring = WorldGen.ring(W, b.tx, b.tz)
				check(ring >= st.rings[1] and ring <= st.rings[2], seed .. ": ring " .. ring .. " (the edge)")
				check(b.tx == 0, seed .. ": on the west shore, far from the Docks and the south sea")
				-- the pier is really built there: its harbour hut stands in that tile's plan at the deck's end
				local p = b.pier
				local hut = false
				for _, plan in wd.tilePlans do
					if plan.tx == b.tx and plan.tz == b.tz then
						for _, x in plan.boxes do
							if
								x.kind == "building"
								and math.abs(x.cx - p.hut[1]) < 1e-6
								and math.abs(x.cz - p.hut[2]) < 1e-6
							then
								hut = true
							end
						end
					end
				end
				check(hut, seed .. ": the pier's hut is built where WorldGen.pier says")
				check(math.abs(p.hut[1]) > half, seed .. ": the deck runs out over the sea past the map edge")
				local a = st.away
				for _, s in wd.safehouses do
					check(flat(b.x, b.z, s.x, s.z) >= a.pad, seed .. ": clear of safehouse " .. s.id)
				end
				for _, bc in wd.beacons do
					check(flat(b.x, b.z, bc.x, bc.z) >= a.beacon, seed .. ": clear of beacon " .. bc.id)
				end
				for _, lm in W.landmarks do
					local x0, z0 = WorldGen.tileOrigin(Config.City, lm.tx, lm.tz)
					local hs = lm.size * Config.City.tile / 2
					check(flat(b.x, b.z, x0 + hs, z0 + hs) >= a.landmark, seed .. ": clear of " .. lm.id)
				end
				for name, dr in Config.City.districts do
					local cx, cz = math.clamp(b.x, dr.minX, dr.maxX), math.clamp(b.z, dr.minZ, dr.maxZ)
					check(flat(b.x, b.z, cx, cz) >= a.district, seed .. ": clear of " .. name)
				end
				for _, other in { "Academy", "Bank", "ToyShop" } do
					local ob = SideQuestSites.place(Config, wd, other)
					check(ob ~= nil and flat(b.x, b.z, ob.x, ob.z) >= a.site, seed .. ": far from " .. other)
				end
				-- the way in: on the sand at the pier's foot, inside the map, facing inland
				check(WorldMap.heightAt(wd, door.x, door.z) <= gy + 1.5, seed .. ": open sand at the foot")
				check(math.abs(door.x) < half and math.abs(door.z) < half, seed .. ": inside the map")
				check(door.fx == -p.ox and door.fz == -p.oz, seed .. ": facing inland")
				local again = SideQuestSites.outskirts(Config, wd, "GullPier")
				check(again and again.x == b.x and again.z == b.z, seed .. ": the same seed, the same pier")
			end
		end
		-- piers only on the edge ring: an inner coast tile never has one
		local inner = 0
		for tz = 1, W.tiles - 2 do
			for tx = 1, W.tiles - 2 do
				if WorldGen.pier(Config.City, W, world.tiles, tx, tz) then
					inner += 1
				end
			end
		end
		check(inner == 0, "no pier off the edge ring")
		-- the framework checks a shore site's rules
		local function deep(v: any): any
			if type(v) ~= "table" then
				return v
			end
			local out = {}
			for k, x in v do
				out[k] = deep(x)
			end
			return out
		end
		local function problems(edit: (any) -> ()): string
			local sq = deep(SQ)
			edit(sq.sites.GullPier)
			local C = setmetatable({ SideQuests = sq }, { __index = Config })
			return table.concat(SideQuestPlan.validate(C), " | ")
		end
		check(problems(function() end) == "", "the copy is clean")
		check(string.find(
			problems(function(s)
				s.shore = "lighthouse"
			end),
			"shore lighthouse is not a coast pier",
			1,
			true
		) ~= nil, "only a pier has a placing rule")
		check(string.find(
			problems(function(s)
				s.rings = { 12, 16 }
			end),
			"rings on the coast",
			1,
			true
		) ~= nil, "rings off the coast")
		check(string.find(
			problems(function(s)
				s.away.site = nil
			end),
			"away.site",
			1,
			true
		) ~= nil, "no distance from other sites")
		check(string.find(
			problems(function(s)
				s.district = "Suburbs"
			end),
			"district Suburbs",
			1,
			true
		) ~= nil, "a shore site is on the Coast")
	end)

	test("Lore 11 Coast: Brine's sea cave: the tide pools, the wharf and the grotto under it", function()
		check(PocketLayout.known("seacave"), "a pocket layout")
		local l = PocketLayout.build(Config, 1, "seacave")
		check(#l.boxes < 400, "under 400 parts (" .. #l.boxes .. ")")
		local sp = l.points.spawn
		check(PocketLayout.at(Config, sp[1], sp[2], sp[3]) == 1, "the spawn is inside its pocket")
		check(#(l.lists.rooms or {}) >= 2, "two tide pools")
		check(#(l.lists.projectors or {}) >= 4, "four ghost projectors")
		for _, p in { "wharf", "stairhead", "grotto", "boss" } do
			check(l.points[p] ~= nil, "has " .. p)
		end
		local shelf = PocketLayout.heightAt(l, sp[1], sp[3])
		check(shelf > l.floorY + 15, "the cave's shelf stands above the grotto")
		for i, r in l.lists.rooms do
			near(PocketLayout.heightAt(l, r[1], r[3]), shelf, 0.5, "tide pool " .. i .. " is on the shelf")
		end
		local wh = l.points.wharf
		near(PocketLayout.heightAt(l, wh[1], wh[3]), shelf, 0.5, "the wharf")
		for _, name in { "grotto", "boss" } do
			local p = l.points[name]
			near(PocketLayout.heightAt(l, p[1], p[3]), l.floorY, 0.01, name .. " is on the grotto floor")
		end
		for i, p in l.lists.projectors do
			near(
				PocketLayout.heightAt(l, p[1], p[3]),
				l.floorY,
				0.01,
				"projector " .. i .. " is on the floor"
			)
		end
		local b = l.points.boss
		local over = false
		for _, x in l.boxes do
			if
				x.tag == "ceiling"
				and math.abs(x.cx - b[1]) <= x.sx / 2
				and math.abs(x.cz - b[3]) <= x.sz / 2
				and x.cy > l.floorY + 15
			then
				over = true
			end
		end
		check(over, "the grotto is under the shelf")
		local from, to = l.points.stairhead, l.points.grotto
		local prev = PocketLayout.heightAt(l, from[1], from[3])
		local ok = true
		for z = from[3], to[3], -1 do
			local h = PocketLayout.heightAt(l, from[1], z)
			if h > prev + 1e-6 or prev - h > 2.5 then
				ok = false
			end
			prev = h
		end
		check(ok and math.abs(prev - l.floorY) < 0.01, "the rock steps walk down to the grotto")
		local pocket = SideQuestPlan.goal(S.steps[5], "hero") :: any
		check(pocket.kind == "pocket" and pocket.layout == "seacave", "step 5 is inside the sea cave")
		local used = {}
		for _, s in pocket.steps do
			used[s.kind] = true
			if s.at then
				check(l.points[s.at] ~= nil, s.kind .. " at " .. s.at)
			end
			if s.room then
				check(l.lists.rooms[s.room] ~= nil, s.kind .. " in tide pool " .. s.room)
			end
			if s.list then
				check(#(l.lists[s.list] or {}) >= (s.points or 1), s.kind .. " on " .. s.list)
			end
		end
		check(
			used.defeat and used.hold and used.reach and used["break"] and used.boss,
			"tide pools, wharf, steps, projectors, bosun"
		)
	end)

	test(
		"Lore 11 Coast: the Salt Dogs and Captain Brine: switches, looks, never ambient, a boss-lite",
		function()
			local profile = ProfileSchema.default()
			for _, p in CreatorRules.index(Config).list do
				if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
					CreatorRules.grant(profile, p)
				end
			end
			local function lookOk(look: any, label: string)
				local ok, why = CreatorRules.validate(Config, profile, look)
				check(ok, label .. "'s look validates (" .. tostring(why) .. ")")
				for slot, i in look.pieces do
					if i > 0 then
						local p = CreatorRules.piece(Config, slot, i)
						check(
							p ~= nil and p.source.kind ~= "pack",
							label .. " " .. slot .. " is never a Robux piece"
						)
					end
				end
			end
			lookOk(FakeRules.lookFrom(Config, SQ.givers.Nell.look, "Nell"), "Nell")
			local NL = Config.NpcLooks
			for _, kind in CREW do
				local cfg = Config.Enemies[kind]
				check(cfg.on == true, kind .. ": an on switch")
				check(
					table.find(Config.Enemies.order, kind) ~= nil and cfg.typeId < 32,
					kind .. " is in the order"
				)
				check(Config.Enemies.mix[kind] == nil, kind .. " never spawns in the ambient mix")
				for _, sw in Config.Enemies.variety.swaps do
					check(
						sw.kind ~= kind and table.find(sw.from, kind) == nil,
						kind .. " is never swapped in or out"
					)
				end
				cfg.on = false
				local gone = EnemySim.spawn(EnemySim.new(Config, {}), kind, 0, 20, 0, 1) == nil
				cfg.on = true
				check(gone, kind .. " off: never spawns")
				check(
					EnemySim.spawn(EnemySim.new(Config, {}), kind, 0, 20, 0, 1) ~= nil,
					kind .. " on: spawns"
				)
			end
			-- the Salt Dogs: machines with a hook and a bandana and three crew uniforms drawn for upload
			local D = Config.Enemies.SaltDog
			check(D.fake == nil and D.body.hook == true, "a Salt Dog is a robot with a hook")
			check(NL.robots.SaltDog ~= nil, "the Salt Dogs have their three crew uniforms")
			for _, v in NL.versions do
				check(
					fs.isFile("art/export/clothes/uniforms/SaltDog_" .. v .. ".png"),
					"SaltDog " .. v .. " uniform is drawn for upload"
				)
			end
			local rng = Rng.new(11)
			local function rand(): number
				return rng:next()
			end
			for _ = 1, 50 do
				for _, row in EnemyVariety.squad(Config, { { kind = "SaltDog", n = 6 } }, 40, rand) do
					check(row.kind == "SaltDog", "a Salt Dog squad stays Salt Dogs")
				end
			end
			local rend = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
			check(string.find(rend, "body.hook", 1, true) ~= nil, "the renderer draws the hook")
			check(string.find(rend, "body.anchor", 1, true) ~= nil, "and Brine's anchor")
			-- Captain Brine: a costumed powered villain (a powered diving rig): no crack, no FAKE, a real look
			local B = Config.Enemies.CaptainBrine
			check(B.fake and B.fake.costumed == true and B.elite and B.miniBoss, "a costumed boss-lite")
			check(B.hp >= 2 * Config.Enemies.NullSentinel.hp, "boss-lite health")
			local look = FakeRules.look(Config, "CaptainBrine")
			lookOk(look, "Captain Brine")
			check(
				Config.Enemies.look.builds[B.body.build] == look.build,
				"Brine's robot build matches his look"
			)
			check((B.body.gender or 1) == look.gender, "and his gender")
			local sim = EnemySim.new(Config, {})
			local e = EnemySim.spawn(sim, "CaptainBrine", 0, 20, 0, 10) :: any
			EnemySim.drainEvents(sim)
			EnemySim.damage(sim, e.id, e.maxHealth * 0.8 / (1 - (B.mitigation or 0)), 1)
			local unmasks = 0
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "unmask" then
					unmasks += 1
				end
			end
			check(unmasks == 0 and not e.unmasked, "no unmask: Brine is no fake")
			check(FakeRules.plate(Config, "CaptainBrine", false).name == "CAPTAIN BRINE", "Brine's plate")
			-- damage a second in the fakes' band: above the elite robots, below the hardest world boss
			for _, lv in { 5, 20, 50 } do
				local elite = 0
				for _, kind in Config.Enemies.order do
					local cfg = Config.Enemies[kind]
					if cfg.elite and not cfg.fake then
						elite = math.max(elite, robotDps(kind, lv))
					end
				end
				local boss = 0
				for id in Config.Boss.bosses do
					boss = math.max(boss, bossDps(id, lv))
				end
				local d = robotDps("CaptainBrine", lv)
				check(
					d > elite and d < boss,
					string.format("L%d Brine %.1f between elite %.1f and boss %.1f", lv, d, elite, boss)
				)
				local grunt = robotDps("SaltDog", lv)
				check(grunt > 0 and grunt < elite, string.format("L%d a Salt Dog %.1f is a grunt", lv, grunt))
			end
		end
	)

	for _, lead in SIDES do
		local mate = if lead == "hero" then "villain" else "hero"
		local label = if lead == "villain" then "the Syndicate" else "the Vigil"
		test(
			"Lore 11 Coast: The Salt Dogs as " .. label .. ": all 8 steps co-op with the other side",
			function()
				local a, b = afterSafehouse(), afterSafehouse()
				check(SideQuestPlan.accept(Config, a, S, 22, lead, false), "the lead takes it from Nell")
				check(SideQuestPlan.accept(Config, b, S, 22, mate, true), "the squadmate from the Journal")
				local credits = { 0, 0 }
				for i, step in S.steps do
					check(
						SideQuestPlan.stepOf(a, S) == i and SideQuestPlan.stepOf(b, S) == i,
						"both on step " .. i
					)
					local g = SideQuestPlan.newGroup(S.id, i)
					local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
					local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
					if SideQuestPlan.shared(step) then
						check(
							ka == "both" and kb == "both" and newA and not newB,
							"step " .. i .. ": one shared goal"
						)
					else
						check(
							ka == lead and kb == mate and newA and newB,
							"step " .. i .. ": a goal per side"
						)
					end
					check(
						SideQuestPlan.set(g, ka, g.sides[ka].need),
						"step " .. i .. ": the lead's side finishes"
					)
					if ka ~= kb then
						check(
							SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
							"step " .. i .. ": and waits for the other side"
						)
						check(
							SideQuestPlan.set(g, kb, g.sides[kb].need),
							"step " .. i .. ": the other side finishes"
						)
					end
					check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
					local last = i == #S.steps
					if last then
						check(SideQuestPlan.card(S, i) ~= nil, "Captain Brine's name card at the finale")
					end
					for n, c in { a, b } do
						credits[n] += SideQuestPlan.stepPay(Config, 22, last)
						check(
							SideQuestPlan.advance(c, S) == (if last then "done" else "next"),
							"step " .. i .. " moves on"
						)
					end
				end
				for n, c in { a, b } do
					check(
						SideQuestPlan.isDone(c, S) and c.story.pinned == 0 and c.sq.at.SaltDogs == nil,
						"done, untracked"
					)
					check(
						credits[n] > 0 and SideQuestPlan.chainPay(Config, S, 22) > 0,
						"steps and the end pay"
					)
					check(
						not SideQuestPlan.accept(Config, c, S, 22, if n == 1 then lead else mate, false),
						"once only"
					)
					check(
						not SideQuestPlan.isDone(c, SideQuestPlan.chain(Config, "WindUpLane")),
						"Wind-Up Lane is untouched"
					)
				end
			end
		)
	end

	test("Lore 11 Coast: the reward is a chain title and one cosmetic; side rep pays every step", function()
		local cos = SideQuestPlan.cosmetic(S)
		local n = 0
		for _ in cos do
			n += 1
		end
		check(n == 2 and cos.title == "Brinebreaker" and cos.style == "TatteredSail", "a title and a style")
		local bit = Config.Story.unlocks.titles.Brinebreaker
		check(bit == 10, "a story title (bit 10)")
		local tb = {}
		for name, tbit in Config.Story.unlocks.titles do
			check(not tb[tbit], "title bit " .. tbit .. " used once (" .. name .. ")")
			tb[tbit] = true
		end
		check(GearMath.questStyle(Config, "TatteredSail") ~= nil, "the Tattered Sail is a gear style")
		local styles = 0
		for _, slot in Config.Gear.slotOrder do
			local ns = {}
			for _, row in Config.Gear.styles[slot] do
				check(not ns[row.n], slot .. " style n " .. row.n .. " used once")
				ns[row.n] = true
				if row.quest == "TatteredSail" then
					styles += 1
					check(row.tier == "Story" and row.price == nil, "never rolled, never sold")
				end
			end
		end
		check(styles == 1, "one Tattered Sail")
		for _, k in { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" } do
			check(S.reward[k] == nil, "no " .. k)
		end
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		check(string.find(svc, "SaltDogs", 1, true) == nil, "nothing chain-specific in the service")
		check(
			string.find(svc, 'SideQuestService.StepPaid:Fire(player, res == "done", chain.id)', 1, true)
				~= nil,
			"every step fires StepPaid (side rep)"
		)
	end)

	test("Lore 11 Coast: no old names or Crane in the chain; the Dev panel covers it", function()
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local hits = {}
		local function walk(v: any, path: string)
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w)
				end
				for _, a in ARC do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a)
					end
				end
				for _, a in { "Crane", "Halcyon", "Adrian Vale", "Null" } do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a .. " (standalone chain)")
					end
				end
			elseif type(v) == "table" then
				for k, x in v do
					walk(x, path .. "." .. tostring(k))
				end
			end
		end
		walk(S, "SaltDogs")
		walk(SQ.givers.Nell, "Nell")
		walk(SQ.sites.GullPier, "GullPier")
		walk(Config.Story.guides.speakers.brine, "brine")
		walk(Config.Story.guides.speakers.finn, "finn")
		for _, id in { "gullPoint", "brineLegend", "brineRig" } do
			walk(Config.Cinema.scenes[id], id)
		end
		walk(Config.Cinema.comic.pages.brineLegend, "brineLegend page")
		for _, kind in CREW do
			walk(Config.Enemies[kind], kind)
		end
		for _, h in hits do
			check(false, "an old name: " .. h)
		end
		check(#hits == 0, "no old lore, retired arc names or main-story names")
		local idx = table.find(SQ.chains, S) :: number
		check(idx ~= nil and 300 + idx <= 1000, "the Dev panel's SQ chain button reaches it")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(
			string.find(dev, "if not ch.dev then", 1, true) ~= nil,
			"every real chain is on the SQ chain button"
		)
		check(#S.steps <= SQ.maxSteps, "every step fits SQ: start step")
	end)
end

---------------------------------------------------------------------------
-- Lore step 12: the city remembers (Config.Remembers, Shared.RepTiers, the side tier in EventPlan; RepService,
-- EventService's side events, HqClient's dressing, CitizenRenderer's reactions, GuideClient's radio)
---------------------------------------------------------------------------
do
	local RepTiers = require("../src/shared/RepTiers")
	local BadgeRules = require("../src/shared/BadgeRules")
	local ShopRules = require("../src/shared/ShopRules")
	local NewsPlan = require("../src/shared/NewsPlan")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local PvpRules = require("../src/shared/PvpRules")
	local CreatorRules = require("../src/shared/CreatorRules")
	local R = Config.Remembers

	local function charWith(side: string, track: string?, points: number): any
		local c = ProfileSchema.newCharacter()
		c.side = side
		c.rep = { 0, 0, 0 }
		if track then
			c.rep[if track == "syndicate" then 2 else 1] = points
		end
		return c
	end

	test(
		"Lore 12: reputation tiers: 5 a side on the rank ladder, paced so rank 5 is a long-term goal",
		function()
			check(
				R.tracks.hero == "vigil" and R.tracks.villain == "syndicate",
				"Vigil Trust and Syndicate Fear"
			)
			check(
				Config.Story.rep.order[1] == "vigil" and Config.Story.rep.order[2] == "syndicate",
				"the save's positional keys"
			)
			local ranks = Config.Story.rep.ranks
			check(#ranks == RepTiers.MAX and RepTiers.MAX == 5, "5 tiers")
			for t = 1, 5 do
				check(RepTiers.tierOf(Config, ranks[t]) == t, "tier " .. t .. " at its threshold")
				check(RepTiers.tierOf(Config, ranks[t] - 1) == t - 1, "and not a point before")
				check(RepTiers.need(Config, t) == ranks[t], "need")
			end
			for k, v in R.earn do
				check(type(v) == "number" and v > 0, "earn " .. k)
			end
			check(R.earn.sideWin <= R.earn.sideEvent, "losing a side event still pays most of it")
			for _, side in { "hero", "villain" } do
				local lo, hi = RepTiers.act1(Config, side)
				check(
					lo >= ranks[1] and lo < ranks[3],
					side .. ": Act 1 alone reaches tier 1, not tier 3 (" .. lo .. ")"
				)
				check(hi >= lo and hi < ranks[5], side .. ": Act 1 never reaches tier 5 (" .. hi .. ")")
				local pace = RepTiers.pace(Config, side)
				for t = 2, 5 do
					check(pace[t] >= pace[t - 1], "each tier takes longer")
				end
				local g = R.paceGoal
				check(
					pace[3] >= g.tier3[1] - 1e-9 and pace[3] <= g.tier3[2],
					string.format("%s: rank 3 %.1f h past Act 1", side, pace[3])
				)
				check(
					pace[5] >= g.tier5[1] and pace[5] <= g.tier5[2],
					string.format("%s: rank 5 %.1f h past Act 1 (a long-term goal)", side, pace[5])
				)
				-- rank 5 takes longer than half the hours of the level cap's last ten levels... and less than the cap
				check(pace[5] < 91.5, "but sooner than the level cap (91.5 h)")
			end
			-- the hour model matches the earn table
			local P, E = R.pace, R.earn
			local hour = P.incidents * E.incident
				+ P.contracts * E.contract
				+ P.events * E.event
				+ P.sideEvents * (E.sideEvent + P.winShare * E.sideWin)
				+ P.sideSteps * E.sideStep
			check(math.abs(RepTiers.perHour(Config) - hour) < 1e-9, "per hour")
			check(
				P.incidents == Config.Economy.sim.per30.incident * 2,
				"incidents from the economy sim's play model"
			)
			check(P.contracts == Config.Economy.sim.per30.contract * 2, "contracts too")
			-- the server pays it: every hook is wired
			local rs = readFile("src/server/Services/RepService.luau")
			for _, needle in
				{
					"IncidentService.Cleared:Connect",
					'action == "contract"',
					"EventService.Paid:Connect",
					"SideQuestService.StepPaid:Connect",
					'StoryService.addRep(player, "side", amount)',
				}
			do
				check(string.find(rs, needle, 1, true) ~= nil, "RepService: " .. needle)
			end
			check(
				string.find(
					readFile("src/server/Services/SideQuestService.luau"),
					'SideQuestService.StepPaid:Fire(player, res == "done", chain.id)',
					1,
					true
				) ~= nil,
				"side quest steps pay"
			)
			check(
				string.find(
					readFile("src/server/init.server.luau"),
					'boot("RepService", RepService.init)',
					1,
					true
				) ~= nil,
				"RepService boots"
			)
		end
	)

	test(
		"Lore 12: nothing sold or unlocked changes stats (every side style, title and hideout prop)",
		function()
			local styles = RepTiers.styles(Config)
			check(#styles == 20, "20 side styles (2 a tier a side)")
			local COSMETIC =
				{ n = true, name = true, shape = true, tier = true, rep = true, price = true, color = true }
			local STAT_WORDS =
				{ "Might", "Vitality", "Focus", "Precision", "Resolve", "power", "health", "damage" }
			local ids = {}
			for _, s in styles do
				check(not ids[s.id], "unique id " .. s.id)
				ids[s.id] = true
				for k in s.row do
					check(COSMETIC[k] == true, s.row.name .. ": only looks fields (" .. tostring(k) .. ")")
				end
				check(
					s.row.tier == "Rep" and table.find(Config.Gear.tierOrder, "Rep") == nil,
					"never a loot tier"
				)
				check(s.price >= 500 and s.price <= 3000, s.row.name .. ": 500 to 3,000 Credits like Gizmo's")
				check(GearMath.styleRow(Config, s.id) == s.row, "a real style row")
				-- the shape is one its slot already builds
				local slot = Config.Gear.slotOrder[(GearMath.styleParts(s.id))]
				local known = false
				for _, row in Config.Gear.styles[slot] do
					if row.tier ~= "Rep" and row.shape == s.row.shape then
						known = true
					end
				end
				check(known, s.row.name .. ": a shape the " .. slot .. " slot draws")
				check(ShopRules.gizmoPrice(Config, s.id) == nil, "not in the 40 base styles")
			end
			check(#ShopRules.gizmo(Config) == 40, "Gizmo's 40 base styles unchanged")
			-- never sold for Robux: no product or pass names one
			for key, p in Config.Shop.products do
				for _, v in p do
					check(
						not (type(v) == "number" and ids[v] and p.kind == "style"),
						key .. ": no Robux style"
					)
				end
				check(p.kind ~= "rep", key)
			end
			-- loot never rolls one
			local rng = Rng.new(12)
			for _ = 1, 3000 do
				local piece = GearMath.roll(Config, rng, "Rare", 30, {})
				check(not ids[piece.style], "loot never rolls a side style")
			end
			-- wearing one changes no number
			local worn = {}
			for i = 1, 4 do
				table.insert(worn, GearMath.roll(Config, Rng.new(40 + i), "Rare", 30, {}))
			end
			local before = GearMath.totals(Config, worn)
			for i, piece in worn do
				for _, s in styles do
					if (GearMath.styleParts(s.id)) == piece.slot then
						worn[i] = table.clone(piece)
						worn[i].style = s.id
					end
				end
			end
			local after = GearMath.totals(Config, worn)
			check(after.gearScore == before.gearScore, "gear score unchanged")
			for k, v in before.stats do
				check(after.stats[k] == v, "stat " .. k .. " unchanged")
			end
			-- titles are words; the hideout dressing is props; the config holds no stat word
			for _, track in { "vigil", "syndicate" } do
				for t, name in R.titles[track] do
					check(type(name) == "string" and #name <= 24, track .. " title " .. t)
				end
			end
			for _, side in { "hero", "villain" } do
				for _, p in RepTiers.dressing(Config, side, 5) do
					for k in p do
						check(table.find({
							"name",
							"tier",
							"x",
							"y",
							"z",
							"sx",
							"sy",
							"sz",
							"rgb",
							"mat",
							"shape",
							"glow",
							"light",
							"clear",
							"ry",
							"rz",
						}, k) ~= nil, "a prop's field: " .. tostring(k))
					end
				end
			end
			local src = readFile("src/config/Remembers.luau")
				.. readFile("src/server/Services/RepService.luau")
			for _, w in STAT_WORDS do
				check(string.find(src, w .. " =", 1, true) == nil, "no stat in the city remembers: " .. w)
			end
			local rs = readFile("src/server/Services/RepService.luau")
			for _, call in
				{ "addCredits", "addRenown", "GearService", "bonusPoints", "setLevel", "addSkillPoints" }
			do
				check(string.find(rs, call, 1, true) == nil, "RepService never pays " .. call)
			end
			-- and the side events pay what any event pays: Credits, Renown and one gear roll, never by tier
			local es = readFile("src/server/Services/EventService.luau")
			check(string.find(es, "RepTiers", 1, true) == nil, "event pay never reads a tier")
		end
	)

	test(
		"Lore 12: unlocks gated by side and tier: Gizmo's side styles, titles and what each tier opens",
		function()
			local vig = RepTiers.styles(Config)[1]
			check(vig.track == "vigil" and vig.tier == 1, "vigil first, tier 1 first")
			for _, s in RepTiers.styles(Config) do
				local side = RepTiers.sideOf(Config, s.track) :: string
				local other = if side == "hero" then "villain" else "hero"
				local low = charWith(side, s.track, RepTiers.need(Config, s.tier) - 1)
				local ok, why = RepTiers.canBuy(Config, low, s.id)
				check(not ok and why == "tier", s.row.name .. ": not before its tier")
				local at = charWith(side, s.track, RepTiers.need(Config, s.tier))
				check((RepTiers.canBuy(Config, at, s.id)), s.row.name .. ": at its tier")
				local rival = charWith(other, s.track, 99999)
				local ok2, why2 = RepTiers.canBuy(Config, rival, s.id)
				check(not ok2 and why2 == "side", s.row.name .. ": never the other side's")
			end
			-- buying: Credits only, once, inside the same Gizmo path
			local profile = ProfileSchema.default()
			profile.currency.credits = 1500
			profile.currency.banked = 0
			local c = charWith("hero", "vigil", 100)
			local ok, _, price = ShopRules.gizmoBuy(Config, profile, vig.id, c)
			check(
				ok and price == vig.price and profile.currency.credits == 1500 - vig.price,
				"bought for Credits"
			)
			check(ProfileSchema.Bits.get(profile.styles, vig.id), "the style is unlocked")
			check(select(2, ShopRules.gizmoBuy(Config, profile, vig.id, c)) == "owned", "not twice")
			local t5 = RepTiers.styles(Config)[10]
			check(t5.tier == 5, "the Vigil's tier 5 style")
			check(
				select(2, ShopRules.gizmoBuy(Config, profile, t5.id, c)) == "tier",
				"rank 1 cannot buy rank 5"
			)
			check(
				select(2, ShopRules.gizmoBuy(Config, profile, t5.id)) == "item",
				"no character: not a base style"
			)
			local rich = charWith("hero", "vigil", 1500)
			check(
				select(2, ShopRules.gizmoBuy(Config, profile, t5.id, rich)) == "credits",
				"needs the Credits"
			)
			local ss = readFile("src/server/Services/ShopService.luau")
			check(
				string.find(ss, "ShopRules.repPrice(Config, ProfileSchema.active(profile), styleId)", 1, true)
						~= nil
					and string.find(ss, "CreatorService.inHq(hero)", 1, true) ~= nil,
				"the server gates the buy (at HQ, by tier)"
			)
			-- titles: one a tier, kept while the points are there, in the H7 title list
			for _, track in { "vigil", "syndicate" } do
				local side = RepTiers.sideOf(Config, track) :: string
				for t = 0, 5 do
					local ch = charWith(side, track, RepTiers.need(Config, t))
					local list = RepTiers.titles(Config, ch)
					check(#list == t, track .. " tier " .. t .. ": " .. t .. " titles")
					local p = ProfileSchema.default()
					for _, e in list do
						check(
							BadgeRules.titleText(Config, p, ch, e.id) == e.name,
							"in the title list: " .. e.name
						)
						check(
							e.id > Config.Pass.titleBase + 100 and e.id < R.titleBase + 100,
							"its own id range"
						)
					end
					if t > 0 then
						local u = RepTiers.unlocks(Config, track, t)
						check(
							#u.styles == 2 and u.title ~= nil and u.hideout ~= nil,
							track .. " tier " .. t .. " opens 3"
						)
					end
				end
			end
			-- every title name is new (not a badge's, a story or pass title)
			local names = {}
			for name in Config.Story.unlocks.titles do
				names[name] = true
			end
			for _, n in Config.Pass.titles do
				names[n] = true
			end
			for _, e in BadgeRules.list(Config.Badges) do
				names[e.name] = true
			end
			for _, track in { "vigil", "syndicate" } do
				for _, n in R.titles[track] do
					check(not names[n], "a new title: " .. n)
					names[n] = true
				end
			end
			-- the HQ panel lists only your own side's styles
			local hud = clientSources()["src/client/Ui/HqHud.luau"]
			check(string.find(hud, "if e.track == track then", 1, true) ~= nil, "HqHud: own side only")
		end
	)

	test(
		"Lore 12: the hideouts dress by tier: the right props, clear of the stations, in the cell",
		function()
			local function count(list: { any }, name: string): number
				local n = 0
				for _, p in list do
					if p.name == name then
						n += 1
					end
				end
				return n
			end
			local per = R.hideout.notesPerTier
			for _, side in { "hero", "villain" } do
				check(#RepTiers.dressing(Config, side, 0) == 0, side .. ": nothing at tier 0")
				local prev = 0
				for t = 1, 5 do
					local n = #RepTiers.dressing(Config, side, t)
					check(n > prev, side .. ": tier " .. t .. " adds props")
					prev = n
				end
				check(prev <= 140, side .. ": a part budget (" .. prev .. ")")
			end
			local v = function(t)
				return RepTiers.dressing(Config, "hero", t)
			end
			check(
				count(v(1), "noteBoard") == 1 and count(v(1), "note") == per,
				"Safehouse 1: the thank-you wall"
			)
			check(count(v(1), "rigScreen") == 0 and count(v(2), "rigScreen") == 3, "2: Patch's hacking rig")
			check(count(v(2), "relicCape") == 0, "no relics before 3")
			check(
				count(v(3), "relicCape") == 1 and count(v(3), "relicShield") == 1,
				"3: the hero relic display"
			)
			check(count(v(4), "relicHelmet") == 1 and count(v(4), "spotLamp") == 1, "4: the relic spotlight")
			check(count(v(5), "thanksBanner") == 1 and count(v(5), "note") == per * 5, "5: the city's thanks")
			for t = 1, 5 do
				check(count(v(t), "note") == per * t, "notes grow with the tier")
				check(count(v(t), "noteIcon") == count(v(t), "note"), "every note has a fixed icon (no text)")
			end
			local s = function(t)
				return RepTiers.dressing(Config, "villain", t)
			end
			check(count(s(1), "vaultDoor") == 1 and count(s(1), "goldBar") == 6, "Foundry 1: the loot vault")
			check(count(s(2), "trophyScreen") == 1, "2: the trophy screen")
			check(
				count(s(2), "robotHead") == 0 and count(s(3), "robotHead") == 1,
				"3: the captured Crane robot"
			)
			check(count(s(3), "craneC") == 3 and count(s(3), "hookChain") == 1, "on a hook, with the Crane C")
			check(count(s(4), "goldBar") == 15 and count(s(4), "cashCrate") == 2, "4: the vault expansion")
			check(
				count(s(5), "carpet") == 1 and count(s(5), "kingpinFrame") == 4,
				"5: the kingpin's spotlight"
			)
			-- inside the cell, never on a station's pad
			local half = Config.Hq.cell.size / 2
			for _, side in { "hero", "villain" } do
				for _, p in RepTiers.dressing(Config, side, 5) do
					-- a piece turned 90 degrees about y (the vault door, the shield) swaps its x and z sizes
					local sx, sz = p.sx, p.sz
					if p.ry and math.abs(p.ry) % 180 == 90 then
						sx, sz = sz, sx
					end
					check(
						math.abs(p.x) + sx / 2 <= half
							and math.abs(p.z) + sz / 2 <= half
							and p.y - p.sy / 2 >= 0,
						side .. ": " .. p.name .. " inside the cell"
					)
					if p.y - p.sy / 2 < 8 then -- at walking height
						for name, at in Config.Hq.stations do
							local dx = math.max(0, math.abs(p.x - at[1]) - sx / 2)
							local dz = math.max(0, math.abs(p.z - at[2]) - sz / 2)
							check(
								dx * dx + dz * dz >= Config.Hq.stationRange ^ 2 * 0.25,
								side .. ": " .. p.name .. " clear of the " .. name
							)
						end
					end
				end
			end
			-- the server sends the tier, the device draws it; the stations are the same
			check(
				string.find(
					readFile("src/server/Services/HqService.luau"),
					"repTier = if c then RepTiers.tier(Config, c)",
					1,
					true
				) ~= nil,
				"HqState carries the tier"
			)
			local hq = clientSources()["src/client/Controllers/HqClient.luau"]
			check(
				string.find(hq, "RepTiers.dressing(Config, state.side, state.repTier or 0)", 1, true) ~= nil,
				"HqClient draws it"
			)
			check(string.find(hq, "PLACEHOLDER ART", 1, true) ~= nil, "labelled placeholder art")
		end
	)

	test(
		"Lore 12: side-vs-side events: one side defends, one steals; scheduler odds and PvP unchanged",
		function()
			local EV = Config.Events
			local T = EV.scheduler.side
			check(#EV.side == 3, "3 side events")
			local defends = {}
			local nums = {}
			for _, e in EV.events do
				check(not nums[e.num], "unique num " .. e.num)
				nums[e.num] = true
			end
			for _, id in EV.side do
				local d = EV.events[id]
				check(d ~= nil and d.side == true, id .. ": a side event")
				check(
					table.find(EV.order, id) == nil and table.find(EV.rare, id) == nil,
					id .. ": not in the mix"
				)
				check(
					table.find(EventPlan.GOALS, d.goal) ~= nil,
					id .. ": an existing goal (" .. d.goal .. ")"
				)
				check(
					d.goal == "float" or d.goal == "hold" or d.goal == "shards",
					id .. ": a goal with side rules"
				)
				defends[d.defend] = true
				check(#EventPlan.areas(Config, d.where) > 0, id .. ": its district exists")
				for _, w in d.waves or {} do
					check(Config.Enemies[w[1]] ~= nil, id .. ": robot " .. w[1])
				end
				local nm, title = CinemaPlan.card(Config, "events", id)
				check(nm ~= nil and title ~= nil, id .. ": a name card")
				check(
					d.text ~= d.villainText and #d.text <= 120 and #d.villainText <= 120,
					id .. ": each side's line"
				)
				if d.goal == "shards" then
					check(d.shards % 2 == 1, id .. ": an odd count, so all grabbed has a winner")
				end
			end
			check(defends.hero and defends.villain, "each side defends one")
			check(EV.events.DataTruck.where[1] == "Downtown", "the data truck crosses Downtown")
			check(EV.events.UptownVault.where[1] == "Uptown", "the vault is in Uptown")
			check(EV.events.SparkShipment.where[1] == "Docks", "the shipment is at the Docks")
			-- odds unchanged: with nobody of the other side (or the old call), the scheduler draws exactly as before
			local function run(seed: number, side: ((string) -> boolean)?, rare: boolean): { string }
				local st = EventPlan.new(EV, 0)
				local r = Rng.new(seed)
				local out = {}
				for t = 0, 86400, 2 do
					local id = EventPlan.due(
						EV,
						st,
						t,
						r,
						nil,
						if rare
							then function()
								return true
							end
							else nil,
						side
					)
					if id then
						table.insert(out, id)
					end
				end
				return out
			end
			for _, rare in { false, true } do
				local a, b = run(31, nil, rare), run(31, function()
					return false
				end, rare)
				check(#a == #b, "same count")
				local same = true
				for i = 1, #a do
					same = same and a[i] == b[i]
				end
				check(
					same,
					"no side event possible: the very same draws (rare tier " .. tostring(rare) .. ")"
				)
			end
			-- with both sides always here: the side tier's rate and gaps; the rare tier keeps its own odds
			local st = EventPlan.new(EV, 0)
			local r = Rng.new(77)
			local sides, rares, all, lastSide, most = 0, 0, 0, nil, 0
			local mix: { [string]: number } = {}
			for t = 0, 172800 do
				local id = EventPlan.due(EV, st, t, r, nil, function()
					return true
				end, function()
					return true
				end)
				most = math.max(most, EventPlan.activeCount(st))
				if id then
					all += 1
					if EventPlan.isSide(EV, id) then
						sides += 1
						check(t >= T.firstAfter, "never in the first 10 minutes")
						if lastSide then
							check(t - lastSide >= T.gap, "at most one side event a 45 minutes")
						end
						lastSide = t
					elseif id == "YourDouble" then
						rares += 1
					else
						mix[id] = (mix[id] or 0) + 1
					end
				end
			end
			check(most <= EV.scheduler.maxActive, "never more than 2 at once")
			check(
				sides >= 20 and sides <= 64,
				string.format("%d side events in 48 h (about one an hour)", sides)
			)
			check(rares >= 8 and rares <= 48, string.format("%d rare events still", rares))
			local n, total = 0, 0
			for _, k in mix do
				n += 1
				total += k
			end
			check(n == #EV.order, "every normal event still runs")
			for id, k in mix do
				check(k >= total / n * 0.5 and k <= total / n * 1.5, id .. ": the normal mix stays even")
			end
			check(EventPlan.sideOk(EV, 1, 1) and not EventPlan.sideOk(EV, 5, 0), "both sides present")
			check(not EventPlan.sideOk(EV, 0, 5), "both, either way")
			-- the side rules
			local truck = EV.events.DataTruck
			check(
				EventPlan.canCrack(truck, "villain") and not EventPlan.canCrack(truck, "hero"),
				"only stealers crack"
			)
			check(
				EventPlan.canCrack(EV.events.SparkShipment, "hero"),
				"the Vigil steal the Syndicate's shipment"
			)
			for k = 0, 4 do
				check(EventPlan.crackRate(Config.Incidents, k, k) == 0, "an even ring never cracks")
				check(EventPlan.crackRate(Config.Incidents, k, k + 1) == 0, "the defenders hold it")
				check(
					EventPlan.crackRate(Config.Incidents, k + 2, 1)
						== IncidentPlan.holdRate(Config.Incidents, k + 1),
					"outnumbered: the hold rate of the difference"
				)
			end
			local function res(def, s)
				s.hero = s.hero or 0
				s.villain = s.villain or 0
				return EventPlan.sideResult(def, s)
			end
			check(res(truck, { goal = "float" }) == nil, "still on")
			check(res(truck, { goal = "float", broken = true }) == "villain", "cracked: the Syndicate")
			check(res(truck, { goal = "float", arrived = true }) == "hero", "delivered: the Vigil")
			check(res(truck, { goal = "float", timeUp = true }) == "draw", "time up: a draw")
			local vault = EV.events.UptownVault
			check(res(vault, { goal = "hold", cracked = true }) == "villain", "vault cracked")
			check(res(vault, { goal = "hold", timeUp = true }) == "hero", "vault held")
			local ship = EV.events.SparkShipment
			check(
				res(ship, { goal = "shards", hero = 5, villain = 4, need = 9 }) == "hero",
				"more crystals win"
			)
			check(res(ship, { goal = "shards", hero = 2, villain = 3, need = 9 }) == nil, "still on")
			check(
				res(ship, { goal = "shards", hero = 2, villain = 2, need = 9, timeUp = true }) == "draw",
				"level"
			)
			local E = R.earn
			check(EventPlan.sideRep(E, "hero", "hero") == E.sideEvent + E.sideWin, "the winners")
			check(EventPlan.sideRep(E, "hero", "villain") == E.sideEvent, "the losers still earn")
			check(EventPlan.sideRep(E, "draw", "villain") == E.sideEvent, "a draw")
			-- PvP unchanged: only flagged heroes may hit each other, in a side event or not
			local P = Config.Pvp
			local function side(id: number, flagged: boolean): any
				local f = PvpRules.newFlag()
				if flagged then
					PvpRules.set(f, true, -1000)
				end
				return { id = id, alive = true, level = math.max(P.minLevel, 20), flag = f, safe = false }
			end
			check(not PvpRules.canHit(P, side(1, false), side(2, false), false, 0), "unflagged: never")
			check(not PvpRules.canHit(P, side(1, true), side(2, false), false, 0), "one flagged: never")
			check((PvpRules.canHit(P, side(1, true), side(2, true), false, 0)), "both flagged: yes")
			local es = readFile("src/server/Services/EventService.luau")
			check(
				string.find(es, "FlagService", 1, true) == nil and string.find(es, "PvpRules", 1, true) == nil,
				"the side events add no PvP rule"
			)
			for _, needle in
				{
					"EventPlan.canCrack(d, h.side)",
					"EventPlan.crackRate(Config.Incidents, nS, nD)",
					"EventPlan.sideResult(d, s)",
					'NewsService.post("sideStart", nil, def.num)',
					"EventService.Paid:Fire(player, ev.id, ev.result, rep)",
					"rareAllowed,\n\t\t\t\tsideAllowed",
				}
			do
				check(string.find(es, needle, 1, true) ~= nil, "EventService: " .. needle)
			end
			check(
				string.find(
					readFile("src/server/Services/SiteKit.luau"),
					"if h.allow and not h.allow(heroId) then",
					1,
					true
				) ~= nil,
				"the objective takes only the stealers' hits"
			)
			-- the news: a flash as it starts, the winners named
			local nm = "Captain Spark"
			for _, kind in { "sideStart", "sideVigil", "sideSyndicate", "sideDraw" } do
				local line = NewsPlan.text(Config, { k = NewsPlan.CODE[kind], a = truck.num }, nm)
				check(
					line ~= nil and string.find(line :: string, "DATA TRUCK STANDOFF", 1, true) ~= nil,
					kind
				)
				check(
					NewsPlan.named(kind) == (kind == "sideVigil" or kind == "sideSyndicate"),
					kind .. " names"
				)
			end
			check(NewsPlan.flash(Config, { k = NewsPlan.CODE.sideStart }), "a news flash")
			check(
				NewsPlan.text(Config, { k = NewsPlan.CODE.sideStart, a = 99 }, nm) == nil,
				"an unknown event"
			)
			check(
				string.find(
					clientSources()["src/client/Ui/NewsHud.luau"],
					'data.id == "event" and data.side',
					1,
					true
				) ~= nil,
				"the name card for everyone"
			)
		end
	)

	test("Lore 12: the city reacts: cheers and flinches, Patch and the news name high-tier heroes", function()
		local C = R.citizens
		check(RepTiers.reaction(Config, "hero", C.minTier - 1, 1) == nil, "below the tier: nothing")
		check(RepTiers.reaction(Config, "hero", C.minTier, C.range) == "cheer", "the Vigil: cheers")
		check(RepTiers.reaction(Config, "villain", C.minTier, C.range) == "flinch", "the Syndicate: flinches")
		check(RepTiers.reaction(Config, "hero", C.minTier, C.range + 1) == nil, "too far")
		check(
			RepTiers.reaction(Config, "hero", C.highTier, C.highRange) == "cheer",
			"high tiers: from further"
		)
		check(RepTiers.reaction(Config, "hero", 5, 1, true) == nil, "a fleeing citizen never stops to cheer")
		local cr = clientSources()["src/client/Controllers/CitizenRenderer.luau"]
		check(
			string.find(cr, "RepTiers.reaction(Config, best.side, best.tier, bestD, fleeing)", 1, true) ~= nil
				and string.find(cr, 'p:GetAttribute("RepTier")', 1, true) ~= nil,
			"CitizenRenderer reacts"
		)
		-- the longest safe name fits every line on a phone
		local long = ""
		for t in Config.Creator.titles do
			for n in Config.Creator.nouns do
				local name = CreatorRules.heroName(Config, t, n) :: string
				if #name > #long then
					long = name
				end
			end
		end
		for _, side in { "hero", "villain" } do
			for t = 1, 5 do
				local line = RepTiers.radioSelf(Config, side, t, long) :: string
				check(
					line ~= nil and string.find(line, long, 1, true) ~= nil,
					side .. " tier " .. t .. ": names you"
				)
				check(#line <= 120, side .. " tier " .. t .. ": phone length (" .. #line .. ")")
				check(not string.find(line, "%", 1, true), "filled")
			end
			for _, track in { "vigil", "syndicate" } do
				local line = RepTiers.radioAbout(Config, side, track, long) :: string
				check(
					line ~= nil and #line <= 120 and string.find(line, long, 1, true) ~= nil,
					side .. " about " .. track
				)
			end
			check(
				RepTiers.radioAbout(Config, side, "vigil", "X")
					~= RepTiers.radioAbout(Config, side, "syndicate", "X"),
				"friend or rival"
			)
		end
		check(R.radio.self.hero[1] ~= R.radio.self.villain[1], "side-flavoured")
		check(
			not RepTiers.mention(Config, R.mention.tier - 1) and RepTiers.mention(Config, R.mention.tier),
			"who"
		)
		local line = NewsPlan.text(Config, { k = NewsPlan.CODE.repVigil, a = 5 }, "Captain Spark")
		check(
			line == 'THE CITY TRUSTS CAPTAIN SPARK: VIGIL TRUST RANK 5, "HEART OF THE CITY"',
			"the news: " .. tostring(line)
		)
		check(
			NewsPlan.text(Config, { k = NewsPlan.CODE.repSyndicate, a = 4 }, nil)
				== 'THE CITY FEARS A HERO: SYNDICATE FEAR RANK 4, "SYNDICATE KINGPIN"',
			"no name: A HERO"
		)
		check(NewsPlan.text(Config, { k = NewsPlan.CODE.repVigil, a = 6 }, "X") == nil, "a bad rank")
		local rs = readFile("src/server/Services/RepService.luau")
		check(
			string.find(rs, "NewsService.post(newsKind(track), player, tier)", 1, true) ~= nil,
			"the news names them"
		)
		check(string.find(rs, 'player:SetAttribute("RepTier", tier)', 1, true) ~= nil, "the attribute")
		local gc = clientSources()["src/client/Controllers/GuideClient.luau"]
		for _, needle in
			{
				"RepTiers.radioSelf(Config, side(), data.tier",
				"RepTiers.radioAbout(Config, side(), track, name)",
				'Net.listen("NewsFact", onRepFacts)',
				'SettingsClient.on("guideRadio")',
			}
		do
			check(string.find(gc, needle, 1, true) ~= nil, "GuideClient: " .. needle)
		end
		-- Dev panel: set your rep tier, start each side event
		local dev = clientSources()["src/client/Ui/DevPanel.luau"]
		for _, needle in { '"DevCommand", "reptier"', '"DevCommand", "sideevent", i' } do
			check(string.find(dev, needle, 1, true) ~= nil, "Dev: " .. needle)
		end
		local ds = readFile("src/server/Services/DevService.luau")
		check(
			string.find(ds, "RepService.devTier(player, n)", 1, true) ~= nil
				and string.find(ds, "EventService.forceSide(n)", 1, true) ~= nil,
			"DevService"
		)
	end)
end

---------------------------------------------------------------------------
-- Lore step 11, chain 2: The Gala Heist with Rooftop Racers (Downtown). Config.SideQuests (the chain, Valet
-- Benny, the Gala, MeetUp and Bank sites, the rooftop courses, the set pieces), Shared.SideQuestSites (the open
-- squares, the Uptown bank, the courses), Shared.SideQuestSets (the marquee and stage, the racers' meet),
-- Redline and Madame Masque-a-rade (costumed villains in powered suits), the encore finale, the scenes.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local SideQuestSets = require("../src/shared/SideQuestSets")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local HqRules = require("../src/shared/HqRules")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local G = SideQuestPlan.chain(Config, "GalaHeist") :: any
	local SIDES = { "hero", "villain" }
	local VILLAINS = { "Redline", "MasqueARade" }

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	-- a level 6 hero who has cleared Act 1's Ceremony and Safehouse
	local function ready(): any
		local c = ProfileSchema.newCharacter()
		c.story.missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
		return c
	end

	test(
		"Lore 11 chain 2: The Gala Heist validates: 8 quests over both squares, the roofs and the bank",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			check(G ~= nil and not G.dev and G.bit ~= 2, "a real chain with its own bit")
			check(#G.steps == 8 and G.layer == "district" and G.district == "Downtown", "8 Downtown quests")
			check(
				G.giver == "Benny" and SQ.givers.Benny.anchor == "site" and SQ.givers.Benny.site == "Gala",
				"Benny"
			)
			-- nate: both open squares and the rooftops, and the bank job in Uptown
			local used = {}
			for _, id in SideQuestPlan.sites(G) do
				used[id] = true
			end
			check(used.Gala and used.MeetUp and used.Bank, "the gala, the racers' meet and the bank")
			check(
				SQ.sites.Gala.square == "OpenNorth" and SQ.sites.MeetUp.square == "OpenWest",
				"both open squares"
			)
			check(SQ.sites.Bank.district == "Uptown", "the bank is in Uptown")
			local courses = {}
			for _, step in G.steps do
				for _, side in SIDES do
					local g = SideQuestPlan.goal(step, side) :: any
					if g.course then
						courses[g.course] = g.kind
					end
				end
			end
			check(
				courses.GalaRun == "race" and courses.OperaRun == "chase",
				"Downtown's roofs: a race and a chase"
			)
			check(courses.BankRun == "race", "Uptown's roofs: a race")
			check(
				SQ.courses.BankRun.from == "Bank" and SQ.courses.GalaRun.from == "Gala",
				"over both skylines"
			)
			-- the doc's beats in order: museum, a rooftop getaway, opera, a getaway, bank, a getaway, the finale
			local at = {}
			for i, step in G.steps do
				at[i] = step.at
			end
			check(
				at[2] == "Gala" and at[4] == "Gala" and at[6] == "Bank" and at[8] == "MeetUp",
				"heists then the meet"
			)
			for _, i in { 3, 5, 7 } do
				local g = SideQuestPlan.goal(G.steps[i], "hero") :: any
				check(g.course ~= nil, "step " .. i .. " escapes over the roofs")
			end
			-- each side's flavour: the Vigil stop, shield and rescue; the Syndicate snatch, find and empty the vault
			local kinds = { hero = {}, villain = {} }
			for i, step in G.steps do
				for _, side in SIDES do
					kinds[side][(SideQuestPlan.goal(step, side) :: any).kind] = true
				end
				if SideQuestPlan.shared(step) then
					local g = SideQuestPlan.goal(step, "hero") :: any
					check(
						type(g.villainText) == "string" and g.villainText ~= g.text,
						"step " .. i .. ": the Syndicate reads its own goal"
					)
				else
					check(
						SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
							~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
						"step " .. i .. ": each side's own job"
					)
				end
			end
			for _, k in { "fight", "hold", "carry" } do
				check(kinds.hero[k] == true, "the Vigil: " .. k)
			end
			for _, k in { "fetch", "find" } do
				check(kinds.villain[k] == true, "the Syndicate: " .. k)
			end
			-- who speaks: the guides and the chain's own cast
			local who = {}
			for _, step in G.steps do
				for _, l in step.lines or {} do
					who[l.who] = true
				end
			end
			for _, w in { "Benny", "patch", "lodestar", "masque", "redline" } do
				check(who[w] == true, "speaks: " .. w)
			end
			for _, w in { "masque", "redline" } do
				local sp = Config.Story.guides.speakers[w]
				check(
					sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
					w .. ": a guide speaker with a portrait and a blip"
				)
			end
			-- 1 to 3 short device scenes, one before the finale
			local scenes = 0
			for _, step in G.steps do
				if step.scene then
					scenes += 1
					local sc = Config.Cinema.scenes[step.scene]
					check(sc ~= nil and sc.client == true, step.scene .. ": a device scene")
					check(sc and CinemaPlan.check(Config, sc), step.scene .. ": 5 to 20 s")
					for _, l in (sc and sc.lines) or {} do
						check(
							Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
							step.scene .. ": speaker " .. tostring(l.who)
						)
					end
				end
			end
			check(scenes >= 1 and scenes <= 3, "1 to 3 short scenes (" .. scenes .. ")")
			check(G.steps[#G.steps].scene ~= nil, "a scene before the finale")
			local bits = {}
			for id, sc in Config.Cinema.scenes do
				check(not bits[sc.bit], "scene bit " .. sc.bit .. " used once (" .. id .. ")")
				bits[sc.bit] = true
				check(
					require("../src/shared/CinemaPlan").namedBit(Config, sc.bit),
					id .. ": a named scene bit"
				)
			end
		end
	)

	test(
		"Lore 11 chain 2: the finale's two name cards: REDLINE, then MADAME MASQUE-A-RADE's encore",
		function()
			for i = 1, #G.steps - 1 do
				check(SideQuestPlan.card(G, i) == nil, "no card on step " .. i)
			end
			local n = #G.steps
			local fin = SideQuestPlan.goal(G.steps[n], "hero") :: any
			check(SideQuestPlan.shared(G.steps[n]) and fin.kind == "finale", "both sides fight together")
			check(
				fin.enemy == "Redline" and fin.encore.enemy == "MasqueARade",
				"Redline, then Madame Masque-a-rade"
			)
			check(SideQuestPlan.need(fin) == 2, "two villains to beat")
			local a, b = SideQuestPlan.card(G, n, 1) :: any, SideQuestPlan.card(G, n, 2) :: any
			check(a and a.name == "REDLINE" and #a.title > 0, "phase 1: Redline's card")
			check(b and b.name == "MADAME MASQUE-A-RADE" and b.title == G.villain.title, "phase 2: hers")
			check(SideQuestPlan.card(G, n).name == "REDLINE", "the card starts on the first villain")
			check(SideQuestPlan.finaleFoe(fin, 1).enemy == "Redline", "phase 1's foe")
			check(SideQuestPlan.finaleFoe(fin, 2).enemy == "MasqueARade", "phase 2's foe")
			for _, c in { a, b } do
				check(
					SideQuestPlan.fixedText(c.name, 32) == nil and SideQuestPlan.fixedText(c.title, 32) == nil,
					"fixed text that fits the card"
				)
			end
			-- chain 1's finale has no encore: one card, one villain, as before
			local A = SideQuestPlan.chain(Config, "HeroAcademy") :: any
			check(SideQuestPlan.card(A, #A.steps, 2).name == "HEADMASTER HALO", "chain 1 unchanged")
			check(
				SideQuestPlan.need(SideQuestPlan.goal(A.steps[#A.steps], "hero")) == 1,
				"chain 1 one villain"
			)
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			check(
				string.find(svc, "SideQuestPlan.card(g.chain, g.idx, goal.phase)", 1, true) ~= nil,
				"server sends"
			)
			check(string.find(svc, "goal.phase = 2", 1, true) ~= nil, "the encore lands when the first falls")
			check(string.find(svc, 'id = "sqEncore"', 1, true) ~= nil, "with a toast")
			check(
				string.find(fs.readFile("src/client/Ui/Toasts.luau"), '"sqEncore"', 1, true) ~= nil,
				"the device has the encore toast"
			)
			local sh = fs.readFile("src/client/Ui/StoryHud.luau")
			check(
				string.find(sh, "tostring(q.phase or 1)", 1, true) ~= nil,
				"the card shows again for the encore"
			)
		end
	)

	test(
		"Lore 11 chain 2: it opens after the Safehouse at level 5 for both sides; Benny; the Journal",
		function()
			for _, side in SIDES do
				local c = ProfileSchema.newCharacter()
				c.story.missions = StoryPlan.setBit(0, 1)
				local st, why = SideQuestPlan.state(Config, c, G, 10, side)
				check(st == "locked" and why == "story", side .. ": waits for the Safehouse")
				local d = ready()
				local st2, why2, n2 = SideQuestPlan.state(Config, d, G, 4, side)
				check(st2 == "locked" and why2 == "level" and n2 == 5, side .. ": level 5 for Uptown")
				check(SideQuestPlan.state(Config, d, G, 5, side) == "open", side .. ": open at level 5")
				local pick, kind = SideQuestPlan.talkPick(Config, d, "Benny", 6, side, false)
				check(pick == G and kind == "offer", side .. ": Benny offers it")
				check(SideQuestPlan.fixedText(G.blurb[side], 90) == nil, side .. ": the page's line")
				check(SideQuestPlan.fixedText(G.lines.offer[side], 120) == nil, side .. ": Benny's offer")
			end
			-- the Academy's chain stays where it was: two chains, two givers
			local d = ready()
			local pick = SideQuestPlan.talkPick(Config, d, "Gus", 6, "hero", false)
			check(pick ~= G, "Gus still offers his own chain")
			check(
				string.find(
					fs.readFile("src/client/Ui/MapScreen.luau"),
					"SideQuestPlan.sites(chain)",
					1,
					true
				) ~= nil,
				"the map marks every site of the chain"
			)
		end
	)

	test(
		"Lore 11 chain 2: the sites: both open squares, kept for it, and an Uptown bank by Crane Tower",
		function()
			local L = world.downtown
			local open = {}
			for _, o in L.open do
				open[o.id] = o
			end
			for _, id in { "Gala", "MeetUp" } do
				local st = SQ.sites[id]
				local o, door = SideQuestSites.place(Config, world, id)
				check(o ~= nil and o == open[st.square], id .. ": in its open square")
				check(SideQuestSites.building(Config, world, id) == nil, id .. ": no building")
				if o and door then
					check(
						math.abs(door.x - o.x) <= o.size / 2 and math.abs(door.z - o.z) <= o.size / 2,
						id .. ": the giver's spot is on the square"
					)
					-- clear of the ceremony, the chase row and the stairwell
					check(flat(o.x, o.z, L.beacon.x, L.beacon.z) > 200, id .. ": away from the plaza")
					for i, r in L.row do
						check(flat(o.x, o.z, r.x, r.z) > 150, id .. ": clear of chase roof " .. i)
					end
					local hd = HqRules.heroDoor(Config, world) :: any
					check(flat(o.x, o.z, hd.x, hd.z) > 180, id .. ": clear of the Safehouse stairwell")
					local ab = SideQuestSites.building(Config, world, "Academy") :: any
					check(flat(o.x, o.z, ab.x, ab.z) > 150, id .. ": clear of the Hero Academy")
				end
			end
			check(SQ.sites.Gala.square ~= SQ.sites.MeetUp.square, "one set piece a square")
			-- the bank: an existing Uptown building near Uptown's landmark tower, not the tower itself
			local st = SQ.sites.Bank
			local b, door = SideQuestSites.place(Config, world, "Bank")
			check(b ~= nil and door ~= nil, "a building fits")
			if not b or not door then
				return
			end
			check(table.find(world.uptown.buildings, b) ~= nil, "one of Uptown's own buildings")
			check(
				not b.crown and b.h >= st.height[1] and b.h <= st.height[2],
				"a bank block, not a skyscraper"
			)
			local lm = world.uptown.landmark
			check(flat(b.x, b.z, lm.x, lm.z) >= st.away.landmark, "clear of the landmark tower")
			check(flat(b.x, b.z, lm.x, lm.z) < 300, "in the landmark's part of Uptown")
			for _, o in world.buildings do
				check(
					math.abs(door.x - o.x) >= o.sx / 2 or math.abs(door.z - o.z) >= o.sz / 2,
					"the bank's door is outside every building"
				)
			end
			check(SideQuestSites.building(Config, world, "Bank") == b, "picked the same way every time")
			check(SideQuestSites.building(Config, { uptown = nil }, "Bank") == nil, "no Uptown, no bank")
		end
	)

	test(
		"Lore 11 chain 2: the set pieces fit their squares, keep the benches clear and stay in budget",
		function()
			local S = SQ.sets
			for _, id in { "Gala", "MeetUp" } do
				local st = SQ.sites[id]
				check(SideQuestSets.known(st.set), id .. ": a set piece")
				local bad = SideQuestSets.check(Config, st.set, Config.City.downtown.block)
				for _, x in bad do
					check(false, x)
				end
				check(#bad == 0, id .. ": its set fits")
				local set = SideQuestSets.build(st.set)
				local pieces = 0
				for pid, pc in set.pieces do
					pieces += 1
					check(pc.r >= 3, pid .. " can be hit")
					local n = 0
					for _, b in set.boxes do
						if b.piece == pid then
							n += 1
						end
					end
					check(n >= 1, pid .. " has parts")
				end
				check(pieces >= 6, id .. ": at least six breakable pieces (" .. pieces .. ")")
				-- the phone's budget: every part plus an invisible root a piece
				local total = #set.boxes + pieces
				check(
					#set.boxes <= S.parts,
					id .. string.format(": %d parts (budget %d)", #set.boxes, S.parts)
				)
				check(total <= S.parts + 15, id .. ": " .. total .. " with the pieces' roots")
				local signs = 0
				for _, b in set.boxes do
					if b.sign then
						signs += 1
						check(SideQuestPlan.fixedText(b.sign, 24) == nil, "a fixed sign")
					end
				end
				check(signs == 1, id .. ": one sign")
				check(SideQuestSets.build(st.set) == set, "built once")
			end
			local gala = SideQuestSets.build("gala")
			check(
				gala.points.stage and gala.points.seats and #gala.lists.exhibits == 4,
				"the stage and four cases"
			)
			local meet = SideQuestSets.build("meet")
			check(meet.points.start and #meet.lists.cars == 3, "the start line and three racers")
			-- the opera hold ring (the square's middle) sits among the seats, under the marquee
			check(
				flat(gala.points.seats[1], gala.points.seats[3], 0, 0) <= 14,
				"the seats are in the hold ring"
			)
			check(not SideQuestSets.known("moon"), "unknown sets")
			local src = fs.readFile("src/shared/SideQuestSets.luau")
			check(string.find(src, "PLACEHOLDER ART", 1, true) ~= nil, "placeholder art labelled")
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			check(string.find(svc, "SiteKit.object(", 1, true) ~= nil, "pieces are combat targets")
			check(string.find(svc, "task.delay(S.rebuild", 1, true) ~= nil, "and stand again")
			check(S.rebuild >= 20 and S.hits >= 3, "a piece takes a few hits and comes back")
		end
	)

	test("Lore 11 chain 2: rooftop courses keep the 6-roof row's rules over both skylines", function()
		local R = Config.Story.opening.roofs
		local C = SQ.courses
		local gy = Config.City.ground.y
		-- the course jump is the row's own rule: 75 centre to centre on its narrowest roofs, inside one Leap
		local narrow = math.huge
		for _, r in Config.City.downtown.row.roofs do
			narrow = math.min(narrow, r.w)
		end
		check(C.jump <= math.min(R.gap[2], Config.Move.leap.range) - narrow, "the jump is inside one Leap")
		local row = world.downtown.row
		for i = 2, #row do
			check(
				SideQuestSites.edge(row[i - 1], row[i]) <= C.jump and row[i].top <= row[i - 1].top + R.climb,
				"the row's own hop " .. i .. " passes the course rule"
			)
		end
		local academy = SideQuestSites.building(Config, world, "Academy") :: any
		local seen = {}
		for _, id in { "GalaRun", "OperaRun", "BankRun" } do
			local cs = C[id]
			local path = SideQuestSites.course(Config, world, id)
			check(path ~= nil and #path == cs.count, id .. ": found, " .. cs.count .. " roofs")
			if not path then
				continue
			end
			local district = if SQ.sites[cs.from].square then "Downtown" else SQ.sites[cs.from].district
			local sx, sz = SideQuestSites.spot(Config, world, cs.from)
			check(
				flat(path[1].x, path[1].z, sx :: number, sz :: number) <= C.startNear,
				id .. ": starts by its site"
			)
			for i, b in path do
				check(b.district == district, id .. " roof " .. i .. " in " .. district)
				check(
					not b.crown and b.top - gy >= R.minH and b.top - gy <= R.maxH,
					id .. " roof " .. i .. " a roof"
				)
				for _, r in row do
					check(math.abs(r.x - b.x) > 1 or math.abs(r.z - b.z) > 1, id .. " never on the chase row")
				end
				check(
					math.abs(b.x - academy.x) > 1 or math.abs(b.z - academy.z) > 1,
					id .. " never on the Hero Academy"
				)
				if i > 1 then
					local a = path[i - 1]
					check(flat(a.x, a.z, b.x, b.z) >= R.gap[1], id .. " hop " .. i .. ": not a step in place")
					check(SideQuestSites.edge(a, b) <= C.jump, id .. " hop " .. i .. ": one Leap")
					check(b.top <= a.top + R.climb, id .. " hop " .. i .. ": no rise past a climb")
					check(SideQuestSites.hopOk(Config, a, b), id .. " hop " .. i .. " ok")
				end
				for other, list in seen do
					if other ~= "BankRun" and id ~= "BankRun" then
						check(table.find(list, b) == nil, id .. " shares no roof with " .. other)
					end
				end
			end
			seen[id] = path
			-- the same course on every server
			local again = SideQuestSites.course(Config, world, id) :: any
			local same = #again == #path
			for i, b in path do
				same = same and again[i] == b
			end
			check(same, id .. ": the same every time")
		end
		-- the bank crew go up through the bank: the Uptown run starts on its own roof
		local bank = SideQuestSites.building(Config, world, "Bank") :: any
		local bp = seen.BankRun
		check(
			bp and math.abs(bp[1].x - bank.x) < 1 and math.abs(bp[1].z - bank.z) < 1,
			"BankRun starts on the bank"
		)
		-- every race's clock gives time to run it on foot twice over
		for _, step in G.steps do
			local g = SideQuestPlan.goal(step, "hero") :: any
			if g.kind == "race" and g.course then
				local len = SideQuestSites.length(seen[g.course])
				check(
					g.time >= 2 * len / Config.Move.run.speed,
					string.format("%s: %d s for %.0f studs", g.course, g.time, len)
				)
				check(g.checkpoints == C[g.course].count, g.course .. ": a ring a roof")
			end
		end
		check(SideQuestSites.course(Config, { buildings = {} }, "GalaRun") == nil, "no city, no course")
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		check(string.find(svc, "courseRoofs(st.course)", 1, true) ~= nil, "races and chases run courses")
	end)

	test("Lore 11 chain 2: Redline and Madame Masque-a-rade: costumed looks, no FAKE, boss-lite", function()
		local profile = ProfileSchema.default()
		for _, p in CreatorRules.index(Config).list do
			if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
				CreatorRules.grant(profile, p)
			end
		end
		local L = Config.Enemies.look
		local names = {}
		for _, kind in VILLAINS do
			local cfg = Config.Enemies[kind]
			check(
				cfg ~= nil and cfg.on == true and cfg.fake and cfg.fake.costumed == true,
				kind .. ": costumed"
			)
			check(table.find(Config.Enemies.order, kind) ~= nil and cfg.typeId < 32, kind .. " in the order")
			check(table.find(SQ.finale.enemies, kind) ~= nil, kind .. " may be a finale villain")
			check(
				cfg.elite and cfg.miniBoss and cfg.hp >= 2 * Config.Enemies.NullSentinel.hp,
				kind .. " boss-lite"
			)
			check(Config.Enemies.mix[kind] == nil, kind .. " never in the ambient mix")
			for _, sw in Config.Enemies.variety.swaps do
				check(sw.kind ~= kind and not table.find(sw.from, kind), kind .. " is not an open-world swap")
			end
			local look = FakeRules.look(Config, kind)
			local ok, why = CreatorRules.validate(Config, profile, look)
			check(ok, kind .. "'s look validates (" .. tostring(why) .. ")")
			for slot, i in look.pieces do
				if i > 0 then
					local p = CreatorRules.piece(Config, slot, i)
					check(
						p ~= nil and p.source.kind ~= "pack",
						kind .. " " .. slot .. " is never a Robux piece"
					)
				end
			end
			check(L.builds[cfg.body.build] == look.build, kind .. " robot build matches its look")
			check((cfg.body.gender or 1) == look.gender, kind .. " gender matches")
			check(not names[cfg.name], kind .. " has its own name")
			names[cfg.name] = true
			-- never cracks or reads FAKE: no unmask at the threshold, the plate keeps the name
			local sim = EnemySim.new(Config, {})
			local e = EnemySim.spawn(sim, kind, 0, 20, 0, 10) :: any
			check(e ~= nil, kind .. " spawns")
			EnemySim.drainEvents(sim)
			local cut = 1 - (e.cfg.mitigation or 0)
			EnemySim.damage(sim, e.id, e.maxHealth * 0.8 / cut, 1)
			local unmasks = 0
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "unmask" then
					unmasks += 1
				end
			end
			check(unmasks == 0 and not e.unmasked, kind .. ": no unmask (not one of Crane's fakes)")
			check(FakeRules.plate(Config, kind, false).name == string.upper(cfg.name), kind .. "'s plate")
			-- switched off: never spawns
			local off = table.clone(Config)
			off.Enemies = table.clone(Config.Enemies)
			off.Enemies[kind] = table.clone(cfg)
			off.Enemies[kind].on = false
			check(
				EnemySim.spawn(EnemySim.new(off, {}), kind, 0, 20, 0, 5) == nil,
				kind .. " off: never spawns"
			)
		end
		-- damage a second in the fakes' band: above the elite robots, below the hardest world boss
		for _, lv in { 5, 20, 50 } do
			local elite = 0
			for _, kind in Config.Enemies.order do
				local cfg = Config.Enemies[kind]
				if cfg.elite and not cfg.fake then
					elite = math.max(elite, robotDps(kind, lv))
				end
			end
			local boss = 0
			for id in Config.Boss.bosses do
				boss = math.max(boss, bossDps(id, lv))
			end
			for _, kind in VILLAINS do
				local d = robotDps(kind, lv)
				check(
					d > elite and d < boss,
					string.format("L%d %s %.1f between elite %.1f and boss %.1f", lv, kind, d, elite, boss)
				)
			end
		end
		local rend = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
		check(string.find(rend, "body.costumed or", 1, true) ~= nil, "the costume tears off on the device")
	end)

	-- one test per side: that side takes the chain from Benny, a squadmate of the other side joins from the
	-- Journal, and they play all 8 steps together in one run (the finale's encore too)
	for _, lead in SIDES do
		local mate = if lead == "hero" then "villain" else "hero"
		local label = if lead == "villain" then "the Syndicate" else "the Vigil"
		test(
			"Lore 11 chain 2: The Gala Heist as " .. label .. ": all 8 steps co-op with the other side",
			function()
				local a, b = ready(), ready()
				check(SideQuestPlan.accept(Config, a, G, 6, lead, false), "the lead takes it from Benny")
				check(SideQuestPlan.accept(Config, b, G, 6, mate, true), "the squadmate from the Journal")
				for i, step in G.steps do
					check(
						SideQuestPlan.stepOf(a, G) == i and SideQuestPlan.stepOf(b, G) == i,
						"both on step " .. i
					)
					local g = SideQuestPlan.newGroup(G.id, i)
					local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
					local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
					if SideQuestPlan.shared(step) then
						check(
							ka == "both" and kb == "both" and newA and not newB,
							"step " .. i .. ": one shared goal"
						)
					else
						check(
							ka == lead and kb == mate and newA and newB,
							"step " .. i .. ": a goal per side"
						)
					end
					local last = i == #G.steps
					if last then
						-- Redline falls (half the step), then the encore
						check(g.sides[ka].need == 2, "the finale needs both villains")
						check(
							not SideQuestPlan.set(g, ka, 1) and not SideQuestPlan.groupDone(g),
							"Redline down"
						)
						check(SideQuestPlan.card(G, i, 2) ~= nil, "her card for the encore")
					end
					check(
						SideQuestPlan.set(g, ka, g.sides[ka].need),
						"step " .. i .. ": the lead's side finishes"
					)
					if ka ~= kb then
						check(
							SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
							"step " .. i .. ": waits"
						)
						check(
							SideQuestPlan.set(g, kb, g.sides[kb].need),
							"step " .. i .. ": the other side finishes"
						)
					end
					check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
					for _, c in { a, b } do
						check(
							SideQuestPlan.advance(c, G) == (if last then "done" else "next"),
							"step " .. i .. " on"
						)
					end
				end
				for n, c in { a, b } do
					check(
						SideQuestPlan.isDone(c, G) and c.story.pinned == 0 and c.sq.at.GalaHeist == nil,
						"done"
					)
					check(SideQuestPlan.chainPay(Config, G, 6) > 0, "the end pays")
					check(
						not SideQuestPlan.accept(Config, c, G, 6, if n == 1 then lead else mate, false),
						"once only"
					)
				end
				-- both chains finished count as two for the creator's chain pieces
				local A = SideQuestPlan.chain(Config, "HeroAcademy") :: any
				check(SideQuestPlan.accept(Config, a, A, 6, lead, false), "chain 1 too")
				for _ = 1, #A.steps do
					SideQuestPlan.advance(a, A)
				end
				check(SideQuestPlan.chainsDone(Config, { characters = { a } }) == 2, "two chains done")
			end
		)
	end

	test("Lore 11 chain 2: the reward is a chain title and the Masquerade Mask, earned only", function()
		local cos = SideQuestPlan.cosmetic(G)
		check(cos.title == "Curtain Call" and cos.style == "MasqueradeMask", "a title and a style")
		local bit = Config.Story.unlocks.titles["Curtain Call"]
		check(type(bit) == "number" and bit < 100, "a story title")
		local seen = {}
		for name, b in Config.Story.unlocks.titles do
			check(not seen[b], "title bit " .. b .. " used once (" .. name .. ")")
			seen[b] = true
		end
		check(GearMath.questStyle(Config, "MasqueradeMask") ~= nil, "the mask is a gear style")
		local n, used = 0, {}
		for _, row in Config.Gear.styles.head do
			check(not used[row.n], "head style " .. row.n .. " once")
			used[row.n] = true
			if row.quest == "MasqueradeMask" then
				n += 1
				check(row.tier == "Story" and row.price == nil, "never rolled, never sold")
			end
		end
		check(n == 1, "one Masquerade Mask")
		check(G.reward.share > 0 and G.reward.share <= SQ.pay.maxShare, "the end's pay share in range")
	end)

	test("Lore 11 chain 2: the framework checks courses, encores, step sites and square sites", function()
		local function deep(v: any): any
			if type(v) ~= "table" then
				return v
			end
			local out = {}
			for k, x in v do
				out[k] = deep(x)
			end
			return out
		end
		local function problems(edit: (any, any) -> ()): string
			local sq = deep(SQ)
			local C = setmetatable({ SideQuests = sq }, { __index = Config })
			local chain = SideQuestPlan.chain(C, "GalaHeist") :: any
			edit(chain, sq)
			return table.concat(SideQuestPlan.validate(C), " | ")
		end
		local function fails(edit: (any, any) -> (), want: string, label: string)
			local got = problems(edit)
			check(string.find(got, want, 1, true) ~= nil, label .. " (wants: " .. want .. ")")
		end
		check(problems(function() end) == "", "the copy is clean")
		fails(function(c)
			c.steps[3].hero.course = "Moon"
		end, "unknown course Moon", "an unknown course")
		fails(function(c)
			c.steps[3].hero.checkpoints = 4
		end, "course GalaRun has 7 roofs", "rings that do not match the course")
		fails(function(c)
			c.steps[5].hero.hops = 2
		end, "course OperaRun has 5 roofs", "a chase that does not match its course")
		fails(function(c)
			c.steps[2].hero.course = "GalaRun"
		end, "a course is for a race or a chase", "a course on a fight")
		fails(function(c)
			c.steps[8].hero.card = nil
		end, "names its first villain", "an encore with no card")
		fails(function(c)
			c.steps[8].hero.encore.enemy = "Redline"
		end, "the encore is someone else", "the same villain twice")
		fails(function(c)
			c.steps[8].hero.encore.enemy = "BurglarBot"
		end, "encore robot BurglarBot", "a grunt as the encore")
		fails(function(c)
			c.steps[8].hero.encore.hpMult = 99
		end, "encore health", "an encore too tough")
		fails(function(c)
			c.steps[8].hero.encore = nil
		end, "a finale card is for an encore finale", "a card with no encore")
		fails(function(c)
			c.steps[6].at = "Moon"
		end, "at an unknown site Moon", "a step at an unknown site")
		fails(function(_, sq)
			sq.sites.Gala.square = "OpenSouth"
		end, "site Gala: square OpenSouth", "a square that is not there")
		fails(function(_, sq)
			sq.sites.MeetUp.set = "moon"
		end, "site MeetUp: set moon", "an unknown set piece")
		fails(function(_, sq)
			sq.sites.Bank.away.landmark = nil
		end, "away.landmark", "the bank without its landmark distance")
		fails(function(_, sq)
			sq.courses.BankRun.from = "Moon"
		end, "course BankRun: from Moon", "a course from nowhere")
	end)

	test("Lore 11 chain 2: no old names; the Dev panel starts it and jumps to each step", function()
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local hits = {}
		local function walk(v: any, path: string)
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w)
				end
				for _, a in ARC do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a)
					end
				end
			elseif type(v) == "table" then
				for k, x in v do
					walk(x, path .. "." .. tostring(k))
				end
			end
		end
		walk(G, "GalaHeist")
		walk(SQ.givers.Benny, "Benny")
		walk(SQ.sites, "sites")
		walk(SQ.courses, "courses")
		for _, w in { "masque", "redline" } do
			walk(Config.Story.guides.speakers[w], w)
		end
		for _, id in { "galaNight", "bankJob", "curtainCall" } do
			walk(Config.Cinema.scenes[id], id)
		end
		for _, kind in VILLAINS do
			walk(Config.Enemies[kind], kind)
		end
		for _, h in hits do
			check(false, "an old name: " .. h)
		end
		check(#hits == 0, "no old lore or retired arc names")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(
			string.find(dev, "for i, ch in Config.SideQuests.chains do", 1, true) ~= nil,
			"Dev: every chain"
		)
		local idx = table.find(SQ.chains, G) :: number
		check(idx ~= nil and 300 + idx < 1000 and #G.steps <= SQ.maxSteps, "the Dev command reaches it")
	end)
end

---------------------------------------------------------------------------
-- Lore step 11, chain 4: The Harvest King (Farmland). Config.SideQuests (the chain, Farmer Dot, the Farmland
-- sites), Shared.SideQuestSites (farm lots on this week's outskirts tiles, the farm road and the escort's way
-- down it), the Bramblebeast (a cartoon creature) and the Harvest King (a costumed villain in a thresher suit),
-- the encore finale, the scenes and the comic page.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local H = SideQuestPlan.chain(Config, "HarvestKing") :: any
	local SIDES = { "hero", "villain" }
	local VILLAINS = { "Bramblebeast", "HarvestKing" }
	local FARM_SITES = { "Homestead", "Fields", "FarmRoad", "Silos", "KingsAcre" }

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	-- a level 12 hero who has cleared Act 1's Ceremony and Safehouse
	local function ready(): any
		local c = ProfileSchema.newCharacter()
		c.story.missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
		return c
	end

	test(
		"Lore 11 chain 4: The Harvest King validates: 8 Farmland quests, a barn, fields, silos, a road",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			check(H ~= nil and not H.dev, "a real chain")
			local bits = {}
			for _, ch in SQ.chains do
				check(not bits[ch.bit], "chain bit " .. ch.bit .. " once")
				bits[ch.bit] = true
			end
			check(#H.steps == 8 and H.layer == "district" and H.district == "Farmland", "8 Farmland quests")
			check(
				H.giver == "Dot" and SQ.givers.Dot.anchor == "site" and SQ.givers.Dot.site == "Homestead",
				"Dot"
			)
			local used = {}
			for _, id in SideQuestPlan.sites(H) do
				used[id] = true
			end
			for _, id in FARM_SITES do
				check(used[id] == true, "the chain uses " .. id)
				check(SQ.sites[id].district == "Farmland", id .. " is in Farmland")
			end
			check(H.steps[#H.steps].at == "KingsAcre", "the finale on the Harvest King's own farm")
			-- each side's flavour: the Vigil find, escort, fight, rescue, shield and expose; the Syndicate heist
			local kinds = { hero = {}, villain = {} }
			for i, step in H.steps do
				for _, side in SIDES do
					kinds[side][(SideQuestPlan.goal(step, side) :: any).kind] = true
				end
				if SideQuestPlan.shared(step) then
					local g = SideQuestPlan.goal(step, "hero") :: any
					check(
						type(g.villainText) == "string" and g.villainText ~= g.text,
						"step " .. i .. ": the Syndicate reads its own goal"
					)
				else
					check(
						SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
							~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
						"step " .. i .. ": each side's own job"
					)
				end
			end
			for _, k in { "find", "escort", "fight", "carry", "hold", "photo" } do
				check(kinds.hero[k] == true, "the Vigil: " .. k)
			end
			for _, k in { "fetch", "chase", "deliver", "race" } do
				check(kinds.villain[k] == true, "the Syndicate: " .. k)
			end
			local esc = SideQuestPlan.goal(H.steps[3], "hero") :: any
			check(
				esc.kind == "escort" and esc.road == true and H.steps[3].at == "FarmRoad",
				"down the farm road"
			)
			-- who speaks: the guides and the chain's own cast
			local who = {}
			for _, step in H.steps do
				for _, l in step.lines or {} do
					who[l.who] = true
				end
			end
			for _, w in { "Dot", "patch", "lodestar", "harvest" } do
				check(who[w] == true, "speaks: " .. w)
			end
			local sp = Config.Story.guides.speakers.harvest
			check(
				sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
				"the Harvest King: a guide speaker with a portrait and a blip"
			)
			local gh = fs.readFile("src/client/Ui/GuideHud.luau")
			for _, ex in { "crown", "strawhat" } do
				check(string.find(gh, 'extra == "' .. ex .. '"', 1, true) ~= nil, "the portrait draws " .. ex)
			end
			-- 1 to 3 short device scenes, one before the finale; the Harvest King's story is a comic page
			local scenes = 0
			for _, step in H.steps do
				if step.scene then
					scenes += 1
					local sc = Config.Cinema.scenes[step.scene]
					check(sc ~= nil and sc.client == true, step.scene .. ": a device scene")
					check(sc and CinemaPlan.check(Config, sc), step.scene .. ": 5 to 20 s")
					for _, l in (sc and sc.lines) or {} do
						check(
							Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
							step.scene .. ": speaker " .. tostring(l.who)
						)
						check(
							SideQuestPlan.fixedText(l.text, Config.Story.guides.maxChars) == nil,
							"a fixed line"
						)
					end
				end
			end
			check(scenes >= 1 and scenes <= 3, "1 to 3 short scenes (" .. scenes .. ")")
			check(H.steps[#H.steps].scene ~= nil, "a scene before the finale")
			local page = Config.Cinema.comic.pages.kingStory
			check(page ~= nil and #page.panels == 4, "the Harvest King's story is a 4-panel comic page")
			local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
			for _, p in (page and page.panels) or {} do
				check(SideQuestPlan.fixedText(p.caption, 90) == nil, "a fixed caption")
				check(
					string.find(hud, 'kind == "' .. p.scene .. '"', 1, true) ~= nil,
					"the comic draws " .. p.scene
				)
			end
			local seen = {}
			for id, sc in Config.Cinema.scenes do
				check(not seen[sc.bit], "scene bit " .. sc.bit .. " used once (" .. id .. ")")
				seen[sc.bit] = true
				check(
					require("../src/shared/CinemaPlan").namedBit(Config, sc.bit),
					id .. ": a named scene bit"
				)
			end
		end
	)

	test("Lore 11 chain 4: the finale's two name cards: THE BRAMBLEBEAST, then THE HARVEST KING", function()
		for i = 1, #H.steps - 1 do
			check(SideQuestPlan.card(H, i) == nil, "no card on step " .. i)
		end
		local n = #H.steps
		local fin = SideQuestPlan.goal(H.steps[n], "hero") :: any
		check(SideQuestPlan.shared(H.steps[n]) and fin.kind == "finale", "both sides fight together")
		check(fin.enemy == "Bramblebeast" and fin.encore.enemy == "HarvestKing", "the beast, then the King")
		check(SideQuestPlan.need(fin) == 2, "two to beat")
		local a, b = SideQuestPlan.card(H, n, 1) :: any, SideQuestPlan.card(H, n, 2) :: any
		check(a and a.name == "THE BRAMBLEBEAST" and #a.title > 0, "phase 1: the beast's card")
		check(b and b.name == "THE HARVEST KING" and b.title == H.villain.title, "phase 2: the King's")
		check(SideQuestPlan.finaleFoe(fin, 2).enemy == "HarvestKing", "phase 2's foe")
		for _, c in { a, b } do
			check(
				SideQuestPlan.fixedText(c.name, 32) == nil and SideQuestPlan.fixedText(c.title, 32) == nil,
				"fixed text that fits the card"
			)
		end
	end)

	test(
		"Lore 11 chain 4: it opens after the Safehouse at level 12 for both sides; Dot; the Journal",
		function()
			for _, side in SIDES do
				local c = ProfileSchema.newCharacter()
				c.story.missions = StoryPlan.setBit(0, 1)
				local st, why = SideQuestPlan.state(Config, c, H, 20, side)
				check(st == "locked" and why == "story", side .. ": waits for the Safehouse")
				local d = ready()
				local st2, why2, n2 = SideQuestPlan.state(Config, d, H, 11, side)
				check(
					st2 == "locked" and why2 == "level" and n2 == 12,
					side .. ": level 12, Farmland's floor"
				)
				check(n2 == ZoneLevel.floor(Config, "farmland"), side .. ": the unlock is the area's floor")
				check(SideQuestPlan.state(Config, d, H, 12, side) == "open", side .. ": open at level 12")
				local pick, kind = SideQuestPlan.talkPick(Config, d, "Dot", 12, side, false)
				check(pick == H and kind == "offer", side .. ": Dot offers it")
				check(SideQuestPlan.fixedText(H.blurb[side], 90) == nil, side .. ": the page's line")
				check(SideQuestPlan.fixedText(H.lines.offer[side], 120) == nil, side .. ": Dot's offer")
			end
			local d = ready()
			for _, other in { "Gus", "Benny" } do
				check(
					SideQuestPlan.talkPick(Config, d, other, 12, "hero", false) ~= H,
					other .. " keeps his own chain"
				)
			end
		end
	)

	test(
		"Lore 11 chain 4: Farmland sites on this week's tiles: a real barn, fields, silos and a road",
		function()
			local W = Config.World
			check(SQ.sites.KingsAcre.away.site >= 300, "the King's farm is not Dot's")
			for _, seed in { 202647, 202648, 202701, 202725, 202752 } do
				local wd = if seed == 202647 then world else WorldMap.build(Config, seed)
				local picks = {}
				for _, id in FARM_SITES do
					local st = SQ.sites[id]
					local s, door = SideQuestSites.place(Config, wd, id)
					check(s ~= nil and door ~= nil, seed .. " " .. id .. ": a site fits this week's tiles")
					if s and door then
						picks[id] = s
						local tile = WorldGen.get(W, wd.tiles, s.tx, s.tz)
						check(
							tile.zone == W.zones.farmland and tile.variant ~= W.special,
							seed .. " " .. id .. ": on a Farmland tile (not chain 3's Suburbs, not the hub)"
						)
						check(
							ZoneLevel.area(Config, s.x, s.z, wd.tiles) == "farmland",
							seed .. " " .. id .. ": in the farmland area"
						)
						check(
							s.kind == (st.farm or "road"),
							seed .. " " .. id .. ": a " .. tostring(st.farm or "road")
						)
						check(SideQuestSites.building(Config, wd, id) == nil, id .. ": no city building")
						for _, sh in wd.safehouses do
							check(
								flat(s.x, s.z, sh.x, sh.z) >= st.away.safehouse,
								id .. ": clear of safehouse " .. sh.id
							)
						end
						for _, b in wd.beacons do
							check(
								flat(s.x, s.z, b.x, b.z) >= st.away.beacon,
								id .. ": clear of beacon " .. b.id
							)
						end
						for _, lm in W.landmarks do
							local lx, lz = SideQuestSites.landmarkMid(Config, lm)
							-- the Crater's 400 x 400 PvP square reaches 283 studs from its middle at the corners
							check(flat(s.x, s.z, lx, lz) >= 300, id .. ": clear of " .. lm.id)
						end
						if st.from then
							local p = SideQuestSites.farm(Config, wd, st.from) :: any
							local d = flat(s.x, s.z, p.door.x, p.door.z)
							check(
								d >= st.range[1] and d <= st.range[2],
								seed .. " " .. id .. ": near " .. st.from
							)
						end
						check(
							SideQuestSites.farm(Config, wd, id) == s,
							id .. ": picked the same way every time"
						)
					end
				end
				local home, king = picks.Homestead, picks.KingsAcre
				if home and king then
					check(
						flat(home.x, home.z, king.x, king.z) >= SQ.sites.KingsAcre.away.site,
						seed .. ": two farms"
					)
				end
				-- the barns are the tile's own red clapboard barns (the boxes CityBuilder stands up), the door outside
				for _, id in { "Homestead", "KingsAcre" } do
					local s = picks[id]
					if s then
						local found = false
						for _, tp in wd.tilePlans do
							if tp.tx == s.tx and tp.tz == s.tz then
								for _, b in tp.boxes do
									if
										b.kind == "building"
										and b.color == "roofRed"
										and math.abs(b.cx - s.x) < 0.01
										and math.abs(b.cz - s.z) < 0.01
									then
										found = true
										check(b.tint == Config.City.kit.barnTint, id .. ": red clapboard")
									end
								end
							end
						end
						check(found, seed .. " " .. id .. ": a real barn on its tile")
						check(s.door.z >= s.z + s.sz / 2, id .. ": the door is in front of the barn")
					end
				end
				-- the road spot is on a farm road's middle line, and the escort drives down it toward town
				local road = picks.FarmRoad
				if road then
					local t = WorldGen.get(W, wd.tiles, road.tx, road.tz)
					local x0, z0 = WorldGen.tileOrigin(Config.City, road.tx, road.tz)
					local mid = Config.City.tile / 2
					check(
						(t.roadNS and math.abs(road.x - (x0 + mid)) < 0.01)
							or (t.roadEW and math.abs(road.z - (z0 + mid)) < 0.01),
						seed .. ": the road spot is on the road"
					)
					local g = SideQuestPlan.goal(H.steps[3], "hero") :: any
					local path = SideQuestSites.roadPath(Config, wd, road.x, road.z, g.goal * 1.15, 7)
					check(path ~= nil and #path >= 2, seed .. ": the truck has a road")
					local len = 0
					for i = 2, #(path or {}) do
						local p, q = (path :: any)[i - 1], (path :: any)[i]
						len += flat(p[1], p[3], q[1], q[3])
						check(p[1] == q[1] or p[3] == q[3], "a straight road")
						check(
							flat(q[1], q[3], 0, 0) < flat(p[1], p[3], 0, 0),
							seed .. ": leg " .. i .. " heads toward town"
						)
						local tx, tz = WorldGen.tileOf(Config.City, q[1], q[3])
						local qt = WorldGen.get(W, wd.tiles, tx, tz)
						check(
							if p[1] == q[1] then qt.roadNS else qt.roadEW,
							"leg " .. i .. " stays on the road"
						)
					end
					check(len >= g.goal * 0.5, seed .. string.format(": %.0f studs of road", len))
				end
			end
			-- the tile reader finds what the tile's plan stands up
			local n, ok = 0, 0
			for _, tp in world.tilePlans do
				for _, l in SideQuestSites.tileLots(Config, world, tp.tx, tp.tz) do
					if l.kind ~= "silo" then
						n += 1
						for _, b in tp.boxes do
							if math.abs(b.cx - l.x) < 0.01 and math.abs(b.cz - l.z) < 0.01 then
								ok += 1
								break
							end
						end
					end
				end
			end
			check(
				n > 100 and ok == n,
				string.format("every barn and field read is on its tile (%d of %d)", ok, n)
			)
			check(SideQuestSites.farm(Config, { tiles = nil }, "Homestead") == nil, "no world, no farm")
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			check(
				string.find(svc, "SideQuestSites.roadPath(", 1, true) ~= nil,
				"the escort drives the farm road"
			)
			check(string.find(svc, "st.sign ~= false", 1, true) ~= nil, "signs only where a site wants one")
		end
	)

	test("Lore 11 chain 4: the Bramblebeast (a creature) and the Harvest King (a suit): boss-lite", function()
		local profile = ProfileSchema.default()
		for _, p in CreatorRules.index(Config).list do
			if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
				CreatorRules.grant(profile, p)
			end
		end
		local L = Config.Enemies.look
		local ids = {}
		for _, kind in Config.Enemies.order do
			local t = Config.Enemies[kind].typeId
			check(not ids[t], kind .. ": its own typeId")
			ids[t] = true
		end
		for _, kind in VILLAINS do
			local cfg = Config.Enemies[kind]
			check(
				cfg ~= nil and cfg.on == true and cfg.fake and cfg.fake.costumed == true,
				kind .. ": costumed"
			)
			check(table.find(Config.Enemies.order, kind) ~= nil and cfg.typeId < 32, kind .. " in the order")
			check(table.find(SQ.finale.enemies, kind) ~= nil, kind .. " may be a finale villain")
			check(
				cfg.elite and cfg.miniBoss and cfg.hp >= 2 * Config.Enemies.NullSentinel.hp,
				kind .. " boss-lite"
			)
			check(Config.Enemies.mix[kind] == nil, kind .. " never in the ambient mix")
			for _, sw in Config.Enemies.variety.swaps do
				check(sw.kind ~= kind and not table.find(sw.from, kind), kind .. " is not an open-world swap")
			end
			local look = FakeRules.look(Config, kind)
			local ok, why = CreatorRules.validate(Config, profile, look)
			check(ok, kind .. "'s look validates (" .. tostring(why) .. ")")
			for slot, i in look.pieces do
				if i > 0 then
					local p = CreatorRules.piece(Config, slot, i)
					check(
						p ~= nil and p.source.kind ~= "pack",
						kind .. " " .. slot .. " is never a Robux piece"
					)
				end
			end
			check(L.builds[cfg.body.build] == look.build, kind .. " robot build matches its look")
			check((cfg.body.gender or 1) == look.gender, kind .. " gender matches")
			local sim = EnemySim.new(Config, {})
			local e = EnemySim.spawn(sim, kind, 0, 20, 0, 12) :: any
			check(e ~= nil, kind .. " spawns")
			EnemySim.drainEvents(sim)
			local cut = 1 - (e.cfg.mitigation or 0)
			EnemySim.damage(sim, e.id, e.maxHealth * 0.8 / cut, 1)
			local unmasks = 0
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "unmask" then
					unmasks += 1
				end
			end
			check(unmasks == 0 and not e.unmasked, kind .. ": no unmask (not one of Crane's fakes)")
			check(FakeRules.plate(Config, kind, false).name == string.upper(cfg.name), kind .. "'s plate")
			local off = table.clone(Config)
			off.Enemies = table.clone(Config.Enemies)
			off.Enemies[kind] = table.clone(cfg)
			off.Enemies[kind].on = false
			check(
				EnemySim.spawn(EnemySim.new(off, {}), kind, 0, 20, 0, 5) == nil,
				kind .. " off: never spawns"
			)
		end
		-- the beast is a cartoon creature: no metal, it bursts into light; the King's suit is a machine
		check(Config.Enemies.Bramblebeast.fake.creature == true, "the Bramblebeast is a creature")
		check(
			Config.Enemies.HarvestKing.fake.creature == nil,
			"the Harvest King's thresher suit is a machine"
		)
		check(Config.Enemies.Bramblebeast.guard == nil, "no tower shield on a creature")
		-- damage a second in the fakes' band: above the elite robots, below the hardest world boss
		for _, lv in { 12, 20, 50 } do
			local elite = 0
			for _, kind in Config.Enemies.order do
				local cfg = Config.Enemies[kind]
				if cfg.elite and not cfg.fake then
					elite = math.max(elite, robotDps(kind, lv))
				end
			end
			local boss = 0
			for id in Config.Boss.bosses do
				boss = math.max(boss, bossDps(id, lv))
			end
			for _, kind in VILLAINS do
				local d = robotDps(kind, lv)
				check(
					d > elite and d < boss,
					string.format("L%d %s %.1f between elite %.1f and boss %.1f", lv, kind, d, elite, boss)
				)
			end
		end
		local rend = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
		check(string.find(rend, "if body.creature then", 1, true) ~= nil, "a creature keeps its body whole")
		check(
			string.find(rend, "function EnemyRenderer.lightBurst(", 1, true) ~= nil,
			"and bursts into light"
		)
		local cc = fs.readFile("src/client/Controllers/CombatClient.luau")
		check(string.find(cc, "EnemyRenderer.lightBurst(", 1, true) ~= nil, "on defeat, not metal parts")
		local src = fs.readFile("src/config/Enemies.luau")
		check(
			string.find(src, "PLACEHOLDER ART: a creator look on the blocky rig", 1, true) ~= nil,
			"labelled"
		)
	end)

	-- one test per side: that side takes the chain from Dot, a squadmate of the other side joins from the
	-- Journal, and they play all 8 steps together in one run (the finale's encore too)
	for _, lead in SIDES do
		local mate = if lead == "hero" then "villain" else "hero"
		local label = if lead == "villain" then "the Syndicate" else "the Vigil"
		test(
			"Lore 11 chain 4: The Harvest King as " .. label .. ": all 8 steps co-op with the other side",
			function()
				local a, b = ready(), ready()
				check(SideQuestPlan.accept(Config, a, H, 12, lead, false), "the lead takes it from Dot")
				check(SideQuestPlan.accept(Config, b, H, 12, mate, true), "the squadmate from the Journal")
				for i, step in H.steps do
					check(
						SideQuestPlan.stepOf(a, H) == i and SideQuestPlan.stepOf(b, H) == i,
						"both on step " .. i
					)
					local g = SideQuestPlan.newGroup(H.id, i)
					local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
					local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
					if SideQuestPlan.shared(step) then
						check(
							ka == "both" and kb == "both" and newA and not newB,
							"step " .. i .. ": one shared goal"
						)
					else
						check(
							ka == lead and kb == mate and newA and newB,
							"step " .. i .. ": a goal per side"
						)
					end
					local last = i == #H.steps
					if last then
						check(g.sides[ka].need == 2, "the finale needs the beast and the King")
						check(
							not SideQuestPlan.set(g, ka, 1) and not SideQuestPlan.groupDone(g),
							"the beast is a seed"
						)
						check(SideQuestPlan.card(H, i, 2) ~= nil, "the King's card for the encore")
					end
					check(
						SideQuestPlan.set(g, ka, g.sides[ka].need),
						"step " .. i .. ": the lead's side finishes"
					)
					if ka ~= kb then
						check(
							SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
							"step " .. i .. ": waits"
						)
						check(
							SideQuestPlan.set(g, kb, g.sides[kb].need),
							"step " .. i .. ": the other side finishes"
						)
					end
					check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
					for _, c in { a, b } do
						check(
							SideQuestPlan.advance(c, H) == (if last then "done" else "next"),
							"step " .. i .. " on"
						)
					end
				end
				for n, c in { a, b } do
					check(
						SideQuestPlan.isDone(c, H) and c.story.pinned == 0 and c.sq.at.HarvestKing == nil,
						"done"
					)
					check(SideQuestPlan.chainPay(Config, H, 12) > 0, "the end pays")
					check(
						not SideQuestPlan.accept(Config, c, H, 12, if n == 1 then lead else mate, false),
						"once only"
					)
				end
			end
		)
	end

	test("Lore 11 chain 4: the reward is the title Uprooted and the Harvest Crown, earned only", function()
		local cos = SideQuestPlan.cosmetic(H)
		check(cos.title == "Uprooted" and cos.style == "HarvestCrown", "a title and a style")
		check(Config.Story.unlocks.titles.Uprooted == 9, "story title bit 9")
		local seen = {}
		for name, b in Config.Story.unlocks.titles do
			check(not seen[b], "title bit " .. b .. " used once (" .. name .. ")")
			seen[b] = true
		end
		check(GearMath.questStyle(Config, "HarvestCrown") ~= nil, "the crown is a gear style")
		local n, used = 0, {}
		for _, row in Config.Gear.styles.head do
			check(not used[row.n], "head style " .. row.n .. " once")
			used[row.n] = true
			if row.quest == "HarvestCrown" then
				n += 1
				check(row.tier == "Story" and row.price == nil, "never rolled, never sold")
			end
		end
		check(n == 1, "one Harvest Crown")
		check(H.reward.share > 0 and H.reward.share <= SQ.pay.maxShare, "the end's pay share in range")
	end)

	test("Lore 11 chain 4: the framework checks farm sites and the farm road", function()
		local function deep(v: any): any
			if type(v) ~= "table" then
				return v
			end
			local out = {}
			for k, x in v do
				out[k] = deep(x)
			end
			return out
		end
		local function problems(edit: (any, any) -> ()): string
			local sq = deep(SQ)
			local C = setmetatable({ SideQuests = sq }, { __index = Config })
			local chain = SideQuestPlan.chain(C, "HarvestKing") :: any
			edit(chain, sq)
			return table.concat(SideQuestPlan.validate(C), " | ")
		end
		local function fails(edit: (any, any) -> (), want: string, label: string)
			local got = problems(edit)
			check(string.find(got, want, 1, true) ~= nil, label .. " (wants: " .. want .. ")")
		end
		check(problems(function() end) == "", "the copy is clean")
		fails(function(_, sq)
			sq.sites.Silos.farm = "moon"
		end, "site Silos: farm moon", "an unknown farm lot")
		fails(function(_, sq)
			sq.sites.Fields.from = "Gala"
		end, "site Fields: from Gala", "from a site that is not a farm")
		fails(function(_, sq)
			sq.sites.Fields.range = nil
		end, "site Fields: range", "from with no range")
		fails(function(_, sq)
			sq.sites.Homestead.near = nil
		end, "site Homestead: near or from", "a farm with no place to be near")
		fails(function(_, sq)
			sq.sites.KingsAcre.away.landmark = nil
		end, "site KingsAcre: away.landmark", "a farm with no landmark distance")
		fails(function(_, sq)
			sq.sites.KingsAcre.apart = { "Moon" }
		end, "site KingsAcre: apart Moon", "apart from nowhere")
		fails(function(_, sq)
			sq.sites.Silos.district = "Downtown"
		end, "site Silos: a farm site is in Farmland", "a farm out of Farmland")
		fails(function(_, sq)
			sq.sites.FarmRoad.farm = "barn"
		end, "site FarmRoad: road is true", "a road that is a barn too")
		fails(function(c)
			c.steps[4].hero.road = true
		end, "a road is for an escort", "a road on a fight")
	end)

	test("Lore 11 chain 4: no old names; the Dev panel starts it and jumps to each step", function()
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local hits = {}
		local function walk(v: any, path: string)
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w)
				end
				for _, a in ARC do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a)
					end
				end
				for _, nm in { "Crane", "Halcyon", "Adrian Vale" } do
					if string.find(v, nm, 1, true) then
						table.insert(hits, path .. ": " .. nm .. " (standalone from the main story)")
					end
				end
			elseif type(v) == "table" then
				for k, x in v do
					walk(x, path .. "." .. tostring(k))
				end
			end
		end
		walk(H, "HarvestKing")
		walk(SQ.givers.Dot, "Dot")
		for _, id in FARM_SITES do
			walk(SQ.sites[id], id)
		end
		walk(Config.Story.guides.speakers.harvest, "harvest")
		for _, id in { "farmDusk", "kingsHarvest" } do
			walk(Config.Cinema.scenes[id], id)
		end
		walk(Config.Cinema.comic.pages.kingStory, "kingStory")
		for _, kind in VILLAINS do
			walk(Config.Enemies[kind], kind)
		end
		for _, h in hits do
			check(false, "an old name: " .. h)
		end
		check(#hits == 0, "no old lore, retired arc or main story names")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(
			string.find(dev, "for i, ch in Config.SideQuests.chains do", 1, true) ~= nil,
			"Dev: every chain"
		)
		local idx = table.find(SQ.chains, H) :: number
		check(idx ~= nil and 300 + idx < 1000 and #H.steps <= SQ.maxSteps, "the Dev command reaches it")
	end)
end

do
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local fs = require("@lune/fs")
	test("Side quests: outskirts sites stay put after CityBuilder drops the tile plans", function()
		local seed = 202733
		local wd = WorldMap.build(Config, seed)
		SideQuestSites.warm(Config, wd)
		local b = SideQuestSites.place(Config, wd, "ToyShop")
		check(b ~= nil, "a shop is picked while the plans are there")
		wd.tilePlans = {}
		local again = SideQuestSites.place(Config, wd, "ToyShop")
		check(again ~= nil and b ~= nil and again.x == b.x and again.z == b.z, "the same shop after they go")
		-- a world whose plans went before any pick finds nothing (why CityBuilder warms first)
		local cold = WorldMap.build(Config, seed)
		cold.tilePlans = {}
		check(SideQuestSites.place(Config, cold, "ToyShop") == nil, "no plans, no pick")
		local cb = fs.readFile("src/server/Services/CityBuilder.luau")
		local w = string.find(cb, "SideQuestSites.warm(Config, world)", 1, true)
		local c = string.find(cb, "world.tilePlans = {}", 1, true)
		check(w ~= nil and c ~= nil and w < c, "CityBuilder warms the picks before dropping the plans")
	end)
end

---------------------------------------------------------------------------
-- Lore step 11, the Underwater chain: The Sunken City. Config.SideQuests (the chain, Doc Pearl, the deep sites
-- ReefStation, DrownedGate and TideSpire, the Tidewright's dress), Shared.SideQuestSites.deep (sites on the sea
-- floor, picked by rule from Shared.DeepLayout), deepSpot and deepPath (goals in the open water), PocketLayout
-- "velmara" (the drowned city under its air dome), the scenes on the wide seen bits, the reward, the Dev panel.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local DeepLayout = require("../src/shared/DeepLayout")
	local LookCodec = require("../src/shared/LookCodec")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local S = SideQuestPlan.chain(Config, "SunkenCity") :: any
	local SIDES = { "hero", "villain" }
	local SEA = { "Diver", "Anchor", "TorpedoSentry" }
	local SITES = { "ReefStation", "DrownedGate", "TideSpire" }
	local GS = SQ.dress.Tidewright

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	local function afterSafehouse(): any
		local c = ProfileSchema.newCharacter()
		c.story.missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
		return c
	end

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	-- the validator's problems with an edited copy of Config.SideQuests
	local function problems(edit: (any) -> ()): string
		local sq = deepCopy(SQ)
		edit(sq)
		local C = setmetatable({ SideQuests = sq }, { __index = Config })
		return table.concat(SideQuestPlan.validate(C), " | ")
	end

	test(
		"Lore 11 Underwater: The Sunken City validates: 8 Underwater quests, each side's flavour, the Tidewright",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			check(S ~= nil and not S.dev, "a real chain")
			check(
				#S.steps == 8 and S.layer == "district" and S.district == "Underwater",
				"8 Underwater quests"
			)
			local pl = SQ.givers.Pearl
			check(S.giver == "Pearl" and not pl.dev and pl.anchor == "site", "Doc Pearl gives it at a site")
			check(S.site == "ReefStation" and pl.site == "ReefStation", "at the Reef Station")
			check(S.bit == 8, "chain save bit 8")
			for _, other in SQ.chains do
				check(other == S or other.bit ~= S.bit, "its own save bit (" .. tostring(other.id) .. ")")
			end
			local last = S.steps[#S.steps]
			local fin = SideQuestPlan.goal(last, "hero") :: any
			check(
				SideQuestPlan.shared(last)
					and fin.kind == "finale"
					and fin.enemy == "Anchor"
					and fin.dress == "Tidewright",
				"the Tidewright (a sea brute in his dress), both sides together"
			)
			check(table.find(SQ.finale.enemies, "Anchor") ~= nil, "the sea brute is on the finale list")
			check(
				GS.robot == true and Config.Enemies.Anchor.fake == nil,
				"the dress goes over the plain sea brute"
			)
			local kinds = { hero = {}, villain = {} }
			local split = 0
			for i, step in S.steps do
				check(
					SideQuestSites.isDeep(SQ.sites[step.at or S.site]),
					"step " .. i .. " is on the sea floor"
				)
				for _, side in SIDES do
					local g = SideQuestPlan.goal(step, side) :: any
					kinds[side][g.kind] = true
					check(
						table.find(SQ.deep.kinds, g.kind) ~= nil,
						"step " .. i .. ": " .. g.kind .. " works underwater"
					)
				end
				if SideQuestPlan.shared(step) then
					local g = SideQuestPlan.goal(step, "hero") :: any
					check(
						type(g.villainText) == "string" and g.villainText ~= g.text,
						"step " .. i .. ": the Syndicate reads its own goal"
					)
				else
					split += 1
					check(
						SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
							~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
						"step " .. i .. ": each side's own job"
					)
				end
			end
			check(split >= 5, "most steps give each side its own job (" .. split .. ")")
			-- the Vigil rescue and protect the shore; the Dread Syndicate loot the drowned city
			for _, k in { "fight", "find", "deliver", "carry", "hold" } do
				check(kinds.hero[k] == true, "the Vigil: " .. k)
			end
			for _, k in { "fetch", "chase", "hold", "race", "find" } do
				check(kinds.villain[k] == true, "the Syndicate: " .. k)
			end
			check(kinds.hero.pocket and kinds.villain.pocket, "inside Velmara, both sides")
			-- every robot is a sea robot, and no diver in the air dome (a sea flyer stays in the water)
			local seaOnly, dry = true, true
			local function row(kind: string, inPocket: boolean)
				seaOnly = seaOnly and table.find(SEA, kind) ~= nil
				if inPocket and kind == "Diver" then
					dry = false
				end
			end
			for _, step in S.steps do
				for _, side in SIDES do
					local g = SideQuestPlan.goal(step, side) :: any
					for _, r in g.squads or {} do
						row(r[1], false)
					end
					for _, r in g.adds or {} do
						row(r[1], false)
					end
					if g.guards then
						row(g.guards[1], false)
					end
					if g.kind == "chase" or g.kind == "finale" then
						row(g.enemy, false)
					end
					for _, s in g.steps or {} do
						for _, r in s.squads or {} do
							row(r[1], true)
						end
						for _, r in s.waves or {} do
							row(r[1], true)
						end
						if s.adds then
							row(s.adds[1], true)
						end
						if s.enemy then
							row(s.enemy, true)
						end
					end
					check(g.kind ~= "photo" and g.kind ~= "escort", "no street-only kind")
				end
			end
			check(seaOnly, "every robot in the chain is a sea robot (Diver, Anchor, Torpedo Sentry)")
			check(dry, "no Diver inside the air dome")
			for _, k in SEA do
				check(
					Config.Enemies[k].sea == true and Config.Enemies[k].typeId < 32,
					k .. ": an existing sea type"
				)
			end
			local who = {}
			for _, step in S.steps do
				for _, l in step.lines or {} do
					who[l.who] = true
				end
			end
			for _, w in { "Pearl", "patch", "lodestar", "tidewright", "dace" } do
				check(who[w] == true, "speaks: " .. w)
			end
			for _, w in { "tidewright", "dace" } do
				local sp = Config.Story.guides.speakers[w]
				check(
					sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
					w .. ": a guide speaker with a portrait and a blip"
				)
			end
		end
	)

	test("Lore 11 Underwater: three scenes on the wide seen bits 128 up; the comic page draws", function()
		local wb = Config.Cinema.wideBits
		check(wb.from == 128 and wb.to == 255, "the wide range is 128 to 255")
		check(wb.to < ProfileSchema.SEEN_WORDS * 32, "it fits the seen words")
		local want = { velmaraLights = 128, tidewrightTale = 129, tidewrightRises = 130 }
		local used = {}
		for _, step in S.steps do
			if step.scene then
				used[step.scene] = true
				local s = Config.Cinema.scenes[step.scene]
				check(s ~= nil and s.client == true, step.scene .. ": a device scene")
				check(s and CinemaPlan.check(Config, s), step.scene .. ": 5 to 20 s")
				check(s and s.bit == want[step.scene], step.scene .. ": its bit")
				check(
					s and CinemaPlan.namedBit(Config, s.bit) and CinemaPlan.clientBit(Config, s.bit),
					step.scene .. ": a named bit a device may send"
				)
				for _, l in (s and s.lines) or {} do
					check(
						Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
						step.scene .. ": speaker " .. tostring(l.who)
					)
				end
			end
		end
		for id in want do
			check(used[id] == true, id .. " plays in the chain")
		end
		check(S.steps[#S.steps].scene ~= nil, "a scene before the Tidewright's finale")
		local seenBits = {}
		for id, s in Config.Cinema.scenes do
			check(not seenBits[s.bit], "scene bit " .. s.bit .. " used once (" .. id .. ")")
			seenBits[s.bit] = true
		end
		local page = Config.Cinema.comic.pages.tidewrightTale
		check(page ~= nil and #page.panels == 4, "the last guardian's tale is a comic page")
		local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
		for _, p in page.panels do
			check(
				string.find(hud, 'kind == "' .. p.scene .. '"', 1, true) ~= nil,
				"the comic draws " .. p.scene
			)
		end
	end)

	test("Lore 11 Underwater: the finale's name card: THE TIDEWRIGHT on the last step only", function()
		for i = 1, #S.steps - 1 do
			check(SideQuestPlan.card(S, i) == nil, "no card on step " .. i)
		end
		local card = SideQuestPlan.card(S, #S.steps) :: any
		check(card ~= nil and card.name == "THE TIDEWRIGHT", "the finale's card names the Tidewright")
		check(card and card.title == "LAST GUARDIAN OF VELMARA", "and his title")
		check(
			SideQuestPlan.fixedText(card.name, 32) == nil and SideQuestPlan.fixedText(card.title, 32) == nil,
			"fixed text that fits the card"
		)
	end)

	test(
		"Lore 11 Underwater: it opens after the Safehouse at the Coral Shelf's level for both sides; Pearl offers it",
		function()
			local shelf = Config.Deep.zoneFloor.shelf
			check(
				S.unlock.level == shelf and S.unlock.story == 2,
				"the Safehouse and the shelf's level floor"
			)
			for _, side in SIDES do
				local c = ProfileSchema.newCharacter()
				c.story.missions = StoryPlan.setBit(0, 1)
				local st, why, n = SideQuestPlan.state(Config, c, S, 30, side)
				check(st == "locked" and why == "story" and n == 2, side .. ": waits for the Safehouse")
				local d = afterSafehouse()
				local st2, why2, lv = SideQuestPlan.state(Config, d, S, shelf - 1, side)
				check(
					st2 == "locked" and why2 == "level" and lv == shelf,
					side .. ": and the shelf's level floor"
				)
				check(
					SideQuestPlan.state(Config, d, S, shelf, side) == "open",
					side .. ": open at level " .. shelf
				)
				local pick, kind = SideQuestPlan.talkPick(Config, d, "Pearl", shelf, side, false)
				check(pick == S and kind == "offer", side .. ": Pearl offers it")
				check(SideQuestPlan.fixedText(S.blurb[side], 90) == nil, side .. ": the page's line")
				check(SideQuestPlan.fixedText(S.lines.offer[side], 120) == nil, side .. ": Pearl's offer")
				check(
					SideQuestPlan.talkPick(Config, d, "Nell", shelf + 10, side, false) ~= S,
					side .. ": Nell never offers it"
				)
			end
			local J = fs.readFile("src/client/Ui/Journal.luau")
			check(
				string.find(J, 'Underwater = "the Coral Shelf"', 1, true) ~= nil,
				"the Journal names the shelf"
			)
		end
	)

	test(
		"Lore 11 Underwater: the deep sites are on the Coral Shelf, picked by rule, clear of the sea's spots",
		function()
			local L = DeepLayout.build(Config)
			local wy = Config.World.coast.waterY
			local picks = {}
			for _, id in SITES do
				local st = SQ.sites[id]
				check(SideQuestSites.isDeep(st) and st.deep == "shelf", id .. ": a deep site on the shelf")
				check(not SideQuestSites.isDeep(SQ.sites.GullPier), "a pier is not a deep site")
				local b, door = SideQuestSites.place(Config, world, id)
				check(b ~= nil and door ~= nil, id .. ": a spot fits")
				if b and door then
					picks[id] = b
					check(
						b.area == "shelf" and DeepLayout.area(Config, b.x, b.z, nil) == "shelf",
						id .. ": on the shelf"
					)
					local floor = DeepLayout.floorAt(Config, b.x, b.z, nil) :: number
					near(b.y, floor, 1e-6, id .. ": on the seabed")
					check(DeepLayout.underwater(Config, b.x, b.y + 2, b.z), id .. ": under the sea")
					local depth = wy - floor
					check(depth >= st.depth[1] and depth <= st.depth[2], id .. ": " .. depth .. " studs deep")
					check(flat(b.x, b.z, st.near[1], st.near[2]) <= st.reach, id .. ": near its spot")
					local a = st.away
					for _, c in L.caches do
						check(flat(b.x, b.z, c.x, c.z) >= a.cache, id .. ": clear of a cache")
					end
					for _, r in L.rescues do
						check(flat(b.x, b.z, r.x, r.z) >= a.rescue, id .. ": clear of a rescue")
					end
					check(
						flat(b.x, b.z, L.arena.x, L.arena.z) - L.arena.radius >= a.arena,
						id .. ": clear of the Leviathan Engine's arena"
					)
					local clear = true
					for _, x in L.boxes do
						if flat(b.x, b.z, x.cx, x.cz) < math.max(x.sx, x.sz) / 2 + a.reef then
							clear = false
						end
					end
					check(clear, id .. ": clear of every reef, kelp stand and wreck")
					check(door.y == b.y and door.x == b.x and door.z == b.z, id .. ": the way in is the spot")
					check(math.abs(door.fx) + math.abs(door.fz) == 1, id .. ": facing along an axis")
					-- the same world for every seed (the underwater world is never seeded)
					local wd = WorldMap.build(Config, 202720)
					local again = SideQuestSites.place(Config, wd, id)
					check(
						again and again.x == b.x and again.z == b.z,
						id .. ": the same spot on every server"
					)
				end
			end
			for i, a in SITES do
				for j, b in SITES do
					if i < j and picks[a] and picks[b] then
						check(
							flat(picks[a].x, picks[a].z, picks[b].x, picks[b].z) >= SQ.sites[b].away.site
								or SQ.sites[b].away.site == 0,
							a .. " and " .. b .. " are apart"
						)
					end
				end
			end
			local gate, spire = picks.DrownedGate, picks.TideSpire
			check(
				gate and spire and flat(gate.x, gate.z, spire.x, spire.z) >= 300,
				"the gate and the spire are apart"
			)
			-- land sites never pick a deep site's spot as one to keep from, and keep their own picks
			check(SideQuestSites.building(Config, world, "ReefStation") == nil, "never a Downtown building")
		end
	)

	test("Lore 11 Underwater: goals under the sea are in the open water: deepSpot and deepPath", function()
		local rng = Rng.new(77)
		local function rnd(): number
			return rng:next()
		end
		local arena = SQ.deep.arena
		for _, id in SITES do
			local b = SideQuestSites.place(Config, world, id) :: any
			for _ = 1, 40 do
				local p = SideQuestSites.deepSpot(Config, b.x, b.z, 40, 120, rnd)
				check(p ~= nil, id .. ": a spot fits")
				if p then
					local d = flat(p[1], p[3], b.x, b.z)
					check(d >= 40 - 1e-6 and d <= 120 + 1e-6, id .. ": in range")
					local floor = DeepLayout.floorAt(Config, p[1], p[3], nil) :: number
					near(p[2], floor + 2, 1e-6, id .. ": just over the seabed")
					check(SideQuestSites.openSea(Config, p[1], p[2], p[3], arena), id .. ": open sea")
				end
			end
			for _ = 1, 10 do
				local path = SideQuestSites.deepPath(Config, b.x, b.z, 5, 60, SQ.deep.lift, rnd)
				check(path ~= nil and #path >= 4, id .. ": a swim of rings")
				local px, pz = b.x, b.z
				for _, q in path or {} do
					near(flat(q[1], q[3], px, pz), 60, 1e-6, id .. ": rings 60 apart")
					check(
						SideQuestSites.openSea(Config, q[1], q[2], q[3], arena),
						id .. ": a ring in open sea"
					)
					local floor = DeepLayout.floorAt(Config, q[1], q[3], nil) :: number
					check(q[2] > floor + 1 and q[2] <= Config.World.coast.waterY - 4, id .. ": at mid depth")
					px, pz = q[1], q[3]
				end
			end
		end
		check(not SideQuestSites.openSea(Config, 0, 5, 0, arena), "the city is not open sea")
		local ar = DeepLayout.build(Config).arena
		local fl = DeepLayout.floorAt(Config, ar.x, ar.z, nil) or -100
		check(
			not SideQuestSites.openSea(Config, ar.x, fl + 2, ar.z, arena),
			"nor the Leviathan Engine's arena"
		)
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		for _, s in { "SideQuestSites.deepSpot(", "SideQuestSites.deepPath(", "DeepLayout.underwater(" } do
			check(string.find(svc, s, 1, true) ~= nil, "the service builds deep goals with " .. s)
		end
		check(string.find(svc, "EnemyService.dress(", 1, true) ~= nil, "and dresses the finale villain")
	end)

	test(
		"Lore 11 Underwater: the validator checks deep sites, deep kinds and a dress over a plain robot",
		function()
			check(problems(function() end) == "", "the copy is clean")
			local function has(edit: (any) -> (), want: string, label: string)
				local p = problems(edit)
				check(string.find(p, want, 1, true) ~= nil, label .. " (" .. p .. ")")
			end
			has(function(sq)
				sq.sites.ReefStation.district = "Coast"
			end, "ReefStation: district Coast", "a deep site is Underwater")
			has(function(sq)
				sq.sites.ReefStation.away.cache = nil
			end, "away.cache", "a deep site keeps from the caches")
			has(function(sq)
				sq.sites.ReefStation.deep = "trench"
			end, "trench", "only an open area")
			has(function(sq)
				sq.sites.ReefStation.lot = "corner"
			end, "only on the sea floor", "no city lot under the sea")
			has(function(sq)
				for _, c in sq.chains do
					if c.id == "SunkenCity" then
						c.steps[2].hero.kind = "photo"
					end
				end
			end, "photo", "a kind that needs streets is refused under the sea")
			has(function(sq)
				for _, c in sq.chains do
					if c.id == "SunkenCity" then
						c.steps[8].hero.dress = "Nobody"
					end
				end
			end, "dress Nobody", "an unknown dress")
			has(function(sq)
				sq.dress.Tidewright.robot = nil
			end, "a dress goes on a costumed villain's suit (Anchor)", "a plain robot only with robot")
			has(function(sq)
				sq.dress.Tidewright.dmgMult = 3
			end, "dmgMult 1 to 2", "a dress's damage lift is capped")
			has(function(sq)
				sq.dress.Tidewright.path = "Nope"
			end, "path Nope", "a dress's path is a power path")
			has(function(sq)
				sq.dress.Tidewright.height = 20
			end, "height 4 to 12", "a dress's height is capped")
		end
	)

	test(
		"Lore 11 Underwater: Velmara: the terrace, the fountain, the stair and the engine hall under it",
		function()
			check(PocketLayout.known("velmara"), "a pocket layout")
			local l = PocketLayout.build(Config, 1, "velmara")
			check(#l.boxes < 400, "under 400 parts (" .. #l.boxes .. ")")
			local sp = l.points.spawn
			check(PocketLayout.at(Config, sp[1], sp[2], sp[3]) == 1, "the spawn is inside its pocket")
			check(#(l.lists.rooms or {}) >= 2, "two market streets")
			check(#(l.lists.pumps or {}) >= 4, "four tide engines")
			for _, p in { "fountain", "stairhead", "engines", "boss" } do
				check(l.points[p] ~= nil, "has " .. p)
			end
			local terrace = PocketLayout.heightAt(l, sp[1], sp[3])
			check(terrace > l.floorY + 15, "the terrace stands over the engine hall")
			for i, r in l.lists.rooms do
				near(
					PocketLayout.heightAt(l, r[1], r[3]),
					terrace,
					0.5,
					"street " .. i .. " is on the terrace"
				)
			end
			local f = l.points.fountain
			check(PocketLayout.heightAt(l, f[1], f[3]) >= terrace - 0.01, "the fountain is on the terrace")
			for _, name in { "engines", "boss" } do
				local p = l.points[name]
				near(PocketLayout.heightAt(l, p[1], p[3]), l.floorY, 0.01, name .. " is on the hall floor")
			end
			for i, p in l.lists.pumps do
				near(
					PocketLayout.heightAt(l, p[1], p[3]),
					l.floorY,
					0.01,
					"engine " .. i .. " is on the floor"
				)
			end
			local b = l.points.boss
			local over = false
			for _, x in l.boxes do
				if
					x.tag == "ceiling"
					and math.abs(x.cx - b[1]) <= x.sx / 2
					and math.abs(x.cz - b[3]) <= x.sz / 2
					and x.cy > l.floorY + 15
				then
					over = true
				end
			end
			check(over, "the engine hall is under the terrace")
			local from, to = l.points.stairhead, l.points.engines
			local prev = PocketLayout.heightAt(l, from[1], from[3])
			local ok = true
			for z = from[3], to[3], -1 do
				local h = PocketLayout.heightAt(l, from[1], z)
				if h > prev + 1e-6 or prev - h > 2.5 then
					ok = false
				end
				prev = h
			end
			check(ok and math.abs(prev - l.floorY) < 0.01, "the great stair walks down to the hall")
			local pocket = SideQuestPlan.goal(S.steps[5], "hero") :: any
			check(pocket.kind == "pocket" and pocket.layout == "velmara", "step 5 is inside Velmara")
			local used = {}
			for _, s in pocket.steps do
				used[s.kind] = true
				if s.at then
					check(l.points[s.at] ~= nil, s.kind .. " at " .. s.at)
				end
				if s.room then
					check(l.lists.rooms[s.room] ~= nil, s.kind .. " in street " .. s.room)
				end
				if s.list then
					check(#(l.lists[s.list] or {}) >= (s.points or 1), s.kind .. " on " .. s.list)
				end
			end
			check(
				used.defeat and used.hold and used.reach and used["break"] and used.boss,
				"streets, fountain, stair, engines, warden"
			)
		end
	)

	test(
		"Lore 11 Underwater: the Tidewright's dress: his look, his plate, a boss-lite, no new type",
		function()
			local profile = ProfileSchema.default()
			for _, p in CreatorRules.index(Config).list do
				if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
					CreatorRules.grant(profile, p)
				end
			end
			local function lookOk(look: any, label: string)
				local ok, why = CreatorRules.validate(Config, profile, look)
				check(ok, label .. "'s look validates (" .. tostring(why) .. ")")
				for slot, i in look.pieces do
					if i > 0 then
						local p = CreatorRules.piece(Config, slot, i)
						check(
							p ~= nil and p.source.kind ~= "pack",
							label .. " " .. slot .. " is never a Robux piece"
						)
					end
				end
			end
			lookOk(FakeRules.lookFrom(Config, SQ.givers.Pearl.look, "Pearl"), "Doc Pearl")
			local look = FakeRules.lookFrom(Config, GS.look, "Tidewright")
			lookOk(look, "The Tidewright")
			check(look.build == 3, "a heavy guardian")
			local d = FakeRules.dress(Config, "Tidewright") :: any
			check(
				d and d.robot and d.trident and d.height == 9 and d.path == GS.path and d.creature == false,
				"his dress rides EnemyIdentity: over a plain robot, 9 studs, a trident, a machine"
			)
			local words = LookCodec.write(look :: any)
			local back = LookCodec.read(words) :: any
			check(
				back ~= nil and back.build == look.build and back.hair == look.hair,
				"his look rides EnemyIdentity's words"
			)
			-- no new type: typeIds 1 to 31 are full, so the dress goes over the sea brute
			local ids = {}
			for _, kind in Config.Enemies.order do
				local t = Config.Enemies[kind].typeId
				check(not ids[t], "typeId " .. t .. " used once")
				ids[t] = true
				check(t >= 1 and t <= 31, kind .. " fits 5 bits")
			end
			for _, kind in Config.Enemies.order do
				check(Config.Enemies[kind].name ~= "The Tidewright", "no robot type named the Tidewright")
			end
			local plate = FakeRules.plate(Config, "Anchor", false, { name = GS.name, title = GS.title })
			check(plate.name == "THE TIDEWRIGHT" and plate.sub == GS.title and not plate.red, "his plate")
			check(
				table.find(ProfileSchema.PATHS, GS.path) ~= nil,
				"his attacks are drawn in a power path's look"
			)
			check(GS.trident == true and GS.height == 9, "a tall guardian with a trident")
			-- health and damage: the other chains' boss-lites (Brine: 2200 x 3)
			local fin = SideQuestPlan.goal(S.steps[8], "hero") :: any
			local hp = Config.Enemies.Anchor.hp * fin.hpMult
			check(
				hp >= Config.Enemies.CaptainBrine.hp * 2 and hp <= Config.Enemies.CaptainBrine.hp * 4,
				"boss-lite health (" .. hp .. ")"
			)
			for _, lv in { 12, 20, 50 } do
				local elite = 0
				for _, kind in Config.Enemies.order do
					local cfg = Config.Enemies[kind]
					if cfg.elite and not cfg.fake then
						elite = math.max(elite, robotDps(kind, lv))
					end
				end
				local boss = 0
				for id in Config.Boss.bosses do
					boss = math.max(boss, bossDps(id, lv))
				end
				local d = robotDps("Anchor", lv) * GS.dmgMult
				check(
					d > elite and d < boss,
					string.format(
						"L%d the Tidewright %.1f between elite %.1f and boss %.1f",
						lv,
						d,
						elite,
						boss
					)
				)
			end
			local rend = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
			check(
				string.find(rend, "ident.dress and ident.robot", 1, true) ~= nil,
				"devices draw a dress over a plain robot"
			)
			check(string.find(rend, "body.trident", 1, true) ~= nil, "and his trident")
			local es = fs.readFile("src/server/Services/EnemyService.luau")
			check(
				string.find(es, "function EnemyService.dress(", 1, true) ~= nil,
				"the server dresses the robot"
			)
		end
	)

	for _, lead in SIDES do
		local mate = if lead == "hero" then "villain" else "hero"
		local label = if lead == "villain" then "the Syndicate" else "the Vigil"
		test(
			"Lore 11 Underwater: The Sunken City as " .. label .. ": all 8 steps co-op with the other side",
			function()
				local a, b = afterSafehouse(), afterSafehouse()
				check(SideQuestPlan.accept(Config, a, S, 14, lead, false), "the lead takes it from Pearl")
				check(SideQuestPlan.accept(Config, b, S, 14, mate, true), "the squadmate from the Journal")
				for i, step in S.steps do
					check(
						SideQuestPlan.stepOf(a, S) == i and SideQuestPlan.stepOf(b, S) == i,
						"both on step " .. i
					)
					local g = SideQuestPlan.newGroup(S.id, i)
					local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
					local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
					if SideQuestPlan.shared(step) then
						check(
							ka == "both" and kb == "both" and newA and not newB,
							"step " .. i .. ": one shared goal"
						)
					else
						check(
							ka == lead and kb == mate and newA and newB,
							"step " .. i .. ": a goal per side"
						)
					end
					check(
						SideQuestPlan.set(g, ka, g.sides[ka].need),
						"step " .. i .. ": the lead's side finishes"
					)
					if ka ~= kb then
						check(
							SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
							"step " .. i .. ": and waits for the other side"
						)
						check(
							SideQuestPlan.set(g, kb, g.sides[kb].need),
							"step " .. i .. ": the other side finishes"
						)
					end
					check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
					local last = i == #S.steps
					for _, c in { a, b } do
						check(
							SideQuestPlan.advance(c, S) == (if last then "done" else "next"),
							"step " .. i .. " moves on"
						)
					end
				end
				for n, c in { a, b } do
					check(
						SideQuestPlan.isDone(c, S) and c.story.pinned == 0 and c.sq.at.SunkenCity == nil,
						"done, untracked"
					)
					check(SideQuestPlan.chainPay(Config, S, 14) > 0, "the end pay")
					check(
						not SideQuestPlan.accept(Config, c, S, 14, if n == 1 then lead else mate, false),
						"once only"
					)
					check(
						not SideQuestPlan.isDone(c, SideQuestPlan.chain(Config, "SaltDogs")),
						"the Salt Dogs are untouched"
					)
				end
			end
		)
	end

	test(
		"Lore 11 Underwater: the reward is Tide Turner and the Coral Crest; nothing chain-specific",
		function()
			local cos = SideQuestPlan.cosmetic(S)
			local n = 0
			for _ in cos do
				n += 1
			end
			check(n == 2 and cos.title == "Tide Turner" and cos.style == "CoralCrest", "a title and a style")
			check(Config.Story.unlocks.titles["Tide Turner"] == 12, "a story title (bit 12)")
			local tb = {}
			for name, tbit in Config.Story.unlocks.titles do
				check(not tb[tbit], "title bit " .. tbit .. " used once (" .. name .. ")")
				tb[tbit] = true
			end
			check(GearMath.questStyle(Config, "CoralCrest") ~= nil, "the Coral Crest is a gear style")
			local styles = 0
			for _, slot in Config.Gear.slotOrder do
				local ns = {}
				for _, row in Config.Gear.styles[slot] do
					check(not ns[row.n], slot .. " style n " .. row.n .. " used once")
					ns[row.n] = true
					if row.quest == "CoralCrest" then
						styles += 1
						check(row.tier == "Story" and row.price == nil, "never rolled, never sold")
					end
				end
			end
			check(styles == 1, "one Coral Crest")
			for _, k in { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" } do
				check(S.reward[k] == nil, "no " .. k)
			end
			for _, f in
				{
					"src/server/Services/SideQuestService.luau",
					"src/server/Services/EnemyService.luau",
					"src/client/Controllers/EnemyRenderer.luau",
					"src/shared/SideQuestSites.luau",
				}
			do
				local src = fs.readFile(f)
				for _, w in { "SunkenCity", "Tidewright", "ReefStation", "TideSpire", "DrownedGate" } do
					check(
						string.find(src, '"' .. w .. '"', 1, true) == nil,
						f .. ": nothing chain-specific (" .. w .. ")"
					)
				end
			end
		end
	)

	test("Lore 11 Underwater: no old names or main-story names; the Dev panel covers it", function()
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local hits = {}
		local function walk(v: any, path: string)
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w)
				end
				for _, a in ARC do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a)
					end
				end
				for _, a in { "Crane", "Halcyon", "Adrian Vale", "Null" } do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a .. " (standalone chain)")
					end
				end
			elseif type(v) == "table" then
				for k, x in v do
					walk(x, path .. "." .. tostring(k))
				end
			end
		end
		walk(S, "SunkenCity")
		walk(SQ.givers.Pearl, "Pearl")
		walk(GS, "Tidewright dress")
		for _, id in SITES do
			walk(SQ.sites[id], id)
		end
		walk(Config.Story.guides.speakers.tidewright, "tidewright")
		walk(Config.Story.guides.speakers.dace, "dace")
		for _, id in { "velmaraLights", "tidewrightTale", "tidewrightRises" } do
			walk(Config.Cinema.scenes[id], id)
		end
		walk(Config.Cinema.comic.pages.tidewrightTale, "tidewrightTale page")
		for _, h in hits do
			check(false, "an old name: " .. h)
		end
		check(#hits == 0, "no old lore, retired arc names or main-story names")
		local idx = table.find(SQ.chains, S) :: number
		check(idx ~= nil and 300 + idx <= 1000, "the Dev panel's SQ chain button reaches it")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(
			string.find(dev, "if not ch.dev then", 1, true) ~= nil,
			"every real chain is on the SQ chain button"
		)
		check(#S.steps <= SQ.maxSteps, "every step fits SQ: start step")
	end)
end

---------------------------------------------------------------------------
-- Lore step 11, the Old Quarry chain: The Pit. Config.SideQuests (the chain, Brick, the quarry sites, the
-- Pitboss's dress), Shared.SideQuestSites.quarry (sites read from the fixed landmark), PocketLayout "pit" (the
-- fight club under the quarry), FakeRules.dress (a finale villain's own look over an existing costumed suit, so
-- no new robot type), the scenes, the reward, the Dev panel.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local LookCodec = require("../src/shared/LookCodec")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local S = SideQuestPlan.chain(Config, "ThePit") :: any
	local SIDES = { "hero", "villain" }
	local SITES = { "QuarryGate", "MineLift", "QuarryRing" }
	-- the chain's robots: existing machine types only (Enemy.Delta's typeId has 5 bits, all used)
	local CREW = { "BurglarBot", "BruteBot", "SneakBot", "ShieldBearer", "Bramblebeast" }

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	local function afterSafehouse(): any
		local c = ProfileSchema.newCharacter()
		c.story.missions = StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
		return c
	end

	local function deep(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deep(x)
		end
		return out
	end

	-- the validator's problems for a copy of Config.SideQuests changed by edit
	local function problems(edit: (any) -> ()): string
		local sq = deep(SQ)
		edit(sq)
		local C = setmetatable({ SideQuests = sq }, { __index = Config })
		return table.concat(SideQuestPlan.validate(C), " | ")
	end

	local function pitOf(sq: any): any
		for _, ch in sq.chains do
			if ch.id == "ThePit" then
				return ch
			end
		end
		return nil
	end

	test(
		"Lore 11 Old Quarry: The Pit validates: 8 quarry quests, each side's flavour, the Pitboss",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			check(S ~= nil and not S.dev, "a real chain")
			check(
				#S.steps == 8 and S.layer == "district" and S.district == "OldQuarry",
				"8 Old Quarry quests"
			)
			local br = SQ.givers.Brick
			check(S.giver == "Brick" and not br.dev and br.anchor == "site", "Brick gives it at a site")
			check(S.site == "QuarryGate" and br.site == "QuarryGate", "at the quarry gate")
			for _, other in SQ.chains do
				check(other == S or other.bit ~= S.bit, "its own save bit (" .. tostring(other.id) .. ")")
			end
			check(S.bit == 7, "save bit 7")
			local used = SideQuestPlan.sites(S)
			for _, id in SITES do
				check(table.find(used, id) ~= nil, "uses " .. id)
			end
			local last = S.steps[#S.steps]
			local fin = SideQuestPlan.goal(last, "hero") :: any
			check(
				SideQuestPlan.shared(last) and fin.kind == "finale" and fin.dress == "Pitboss",
				"the Pitboss, both sides together"
			)
			check(table.find(SQ.finale.enemies, fin.enemy) ~= nil, "his suit is on the finale list")
			local kinds = { hero = {}, villain = {} }
			local split = 0
			for i, step in S.steps do
				for _, side in SIDES do
					kinds[side][(SideQuestPlan.goal(step, side) :: any).kind] = true
				end
				if SideQuestPlan.shared(step) then
					local g = SideQuestPlan.goal(step, "hero") :: any
					check(
						type(g.villainText) == "string" and g.villainText ~= g.text,
						"step " .. i .. ": the Syndicate reads its own goal"
					)
				else
					split += 1
					check(
						SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
							~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
						"step " .. i .. ": each side's own job"
					)
				end
			end
			check(split >= 5, "most steps give each side its own job (" .. split .. ")")
			-- the Vigil free the fighters and expose the fix; the Dread Syndicate rob the family
			for _, k in { "find", "photo", "fight", "carry", "hold" } do
				check(kinds.hero[k] == true, "the Vigil: " .. k)
			end
			for _, k in { "fetch", "chase", "deliver", "race" } do
				check(kinds.villain[k] == true, "the Syndicate: " .. k)
			end
			check(kinds.hero.pocket and kinds.villain.pocket, "down in the Pit, both sides")
			local crewOnly = true
			local function crew(kind: any)
				crewOnly = crewOnly and table.find(CREW, kind) ~= nil
			end
			for _, step in S.steps do
				for _, side in SIDES do
					local g = SideQuestPlan.goal(step, side) :: any
					for _, row in g.squads or {} do
						crew(row[1])
					end
					for _, row in g.adds or {} do
						crew(row[1])
					end
					if g.guards then
						crew(g.guards[1])
					end
					if g.kind == "chase" or g.kind == "finale" then
						crew(g.enemy)
					end
					for _, s in g.steps or {} do
						for _, row in s.squads or {} do
							crew(row[1])
						end
						for _, row in s.waves or {} do
							crew(row[1])
						end
						if s.enemy then
							crew(s.enemy)
						end
						if s.adds then
							crew(s.adds[1])
						end
					end
				end
			end
			check(crewOnly, "every robot in the chain is an existing type")
			local who = {}
			for _, step in S.steps do
				for _, l in step.lines or {} do
					who[l.who] = true
				end
			end
			for _, w in { "Brick", "patch", "lodestar", "pitboss", "flint" } do
				check(who[w] == true, "speaks: " .. w)
			end
			local guide = fs.readFile("src/client/Ui/GuideHud.luau")
			for _, w in { "pitboss", "flint" } do
				local sp = Config.Story.guides.speakers[w]
				check(
					sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
					w .. ": a guide speaker with a portrait and a blip"
				)
				for _, e in (sp and sp.portrait.extras) or {} do
					check(string.find(guide, '"' .. e .. '"', 1, true) ~= nil, w .. ": GuideHud draws " .. e)
				end
			end
			for _, e in SQ.givers.Brick.portrait.extras or {} do
				check(string.find(guide, '"' .. e .. '"', 1, true) ~= nil, "Brick: GuideHud draws " .. e)
			end
			local sb = Config.Cinema.extraBits
			local scenes = 0
			local mine = {}
			for _, step in S.steps do
				if step.scene then
					scenes += 1
					local s = Config.Cinema.scenes[step.scene]
					check(s ~= nil and s.client == true, step.scene .. ": a device scene")
					check(s and CinemaPlan.check(Config, s), step.scene .. ": 5 to 20 s")
					check(
						s and s.bit >= sb.from and s.bit <= sb.to and CinemaPlan.clientBit(Config, s.bit),
						step.scene .. ": a side quest scene bit a device may send"
					)
					if s then
						table.insert(mine, s.bit)
					end
					for _, l in (s and s.lines) or {} do
						check(
							Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
							step.scene .. ": speaker " .. tostring(l.who)
						)
					end
				end
			end
			table.sort(mine)
			check(scenes >= 1 and scenes <= 3, "1 to 3 short scenes (" .. scenes .. ")")
			check(#mine == 3 and mine[1] == 125 and mine[3] == 127, "scene bits 125 to 127")
			check(last.scene ~= nil, "a scene before the Pitboss's finale")
			local seenBits = {}
			for id, s in Config.Cinema.scenes do
				check(not seenBits[s.bit], "scene bit " .. s.bit .. " used once (" .. id .. ")")
				seenBits[s.bit] = true
			end
			local page = Config.Cinema.comic.pages.pitStory
			check(page ~= nil and #page.panels == 4, "the Pitboss's story is a comic page")
			local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
			for _, p in page.panels do
				check(SideQuestPlan.fixedText(p.caption, 90) == nil, "a short caption")
				check(
					string.find(hud, 'kind == "' .. p.scene .. '"', 1, true) ~= nil,
					"the comic draws " .. p.scene
				)
			end
		end
	)

	test("Lore 11 Old Quarry: the finale's name card: THE PITBOSS on the last step only", function()
		for i = 1, #S.steps - 1 do
			check(SideQuestPlan.card(S, i) == nil, "no card on step " .. i)
		end
		local card = SideQuestPlan.card(S, #S.steps) :: any
		check(card ~= nil and card.name == "THE PITBOSS", "the finale's card names the Pitboss")
		check(card and card.title == "HEAD OF THE GRAVEL FAMILY", "and his title")
		check(
			SideQuestPlan.fixedText(card.name, 32) == nil and SideQuestPlan.fixedText(card.title, 32) == nil,
			"fixed text that fits the card"
		)
	end)

	test(
		"Lore 11 Old Quarry: it opens after the Safehouse at the quarry's level for both sides; Brick offers it",
		function()
			for _, side in SIDES do
				local c = ProfileSchema.newCharacter()
				c.story.missions = StoryPlan.setBit(0, 1)
				local st, why, n = SideQuestPlan.state(Config, c, S, 30, side)
				check(st == "locked" and why == "story" and n == 2, side .. ": waits for the Safehouse")
				check(
					select(2, SideQuestPlan.talkPick(Config, c, "Brick", 30, side, false)) == "none",
					side .. ": Brick has nothing yet"
				)
				local d = afterSafehouse()
				local st2, why2, lv = SideQuestPlan.state(Config, d, S, 19, side)
				check(
					st2 == "locked" and why2 == "level" and lv == Config.World.zoneFloor.OldQuarry,
					side .. ": and the Old Quarry's level floor"
				)
				check(SideQuestPlan.state(Config, d, S, 20, side) == "open", side .. ": open at level 20")
				local pick, kind = SideQuestPlan.talkPick(Config, d, "Brick", 20, side, false)
				check(pick == S and kind == "offer", side .. ": Brick offers it")
				check(SideQuestPlan.fixedText(S.blurb[side], 90) == nil, side .. ": the page's line")
				check(SideQuestPlan.fixedText(S.lines.offer[side], 120) == nil, side .. ": Brick's offer")
				check(
					SideQuestPlan.talkPick(Config, d, "Nell", 20, side, false) ~= S,
					side .. ": Nell never offers it"
				)
			end
			local J = fs.readFile("src/client/Ui/Journal.luau")
			check(
				string.find(J, 'OldQuarry = "the Old Quarry"', 1, true) ~= nil,
				"the Journal names the Old Quarry"
			)
		end
	)

	test(
		"Lore 11 Old Quarry: the sites stand on the fixed quarry: the gate and two clear floor spots",
		function()
			local plan = SideQuestSites.quarryPlan(Config) :: any
			check(plan ~= nil, "the quarry's plan")
			local W = Config.World
			local lm = nil
			for _, x in W.landmarks do
				if x.id == "OldQuarry" then
					lm = x
				end
			end
			check(lm ~= nil, "the Old Quarry landmark")
			local x0, z0 = WorldGen.tileOrigin(Config.City, lm.tx, lm.tz)
			local hs = lm.size * Config.City.tile / 2
			local cx, cz = x0 + hs, z0 + hs
			near(plan.centre.x, cx, 0.01, "the plan's middle is the landmark's (x)")
			near(plan.centre.z, cz, 0.01, "and z")
			for _, id in SITES do
				local st = SQ.sites[id]
				check(
					st.district == "OldQuarry" and SideQuestSites.QUARRY_KINDS[st.quarry],
					id .. ": a quarry site"
				)
				check(SideQuestSites.building(Config, world, id) == nil, id .. ": never a Downtown building")
				local q = SideQuestSites.quarry(Config, world, id) :: any
				check(q ~= nil, id .. ": a spot fits")
				if q then
					check(
						math.abs(q.x - cx) < hs and math.abs(q.z - cz) < hs,
						id .. ": inside the quarry (" .. q.x .. ", " .. q.z .. ")"
					)
					check(q.door.fx == 0 and q.door.fz == -1, id .. ": facing north, toward town")
					if st.quarry == "floor" then
						check(
							SideQuestSites.quarryClearance(Config, q.x, q.z) >= st.clear,
							id .. ": " .. st.clear .. " studs clear of the walls, terraces and boulders"
						)
						check(
							WorldMap.heightAt(world, q.x, q.z) <= Config.City.ground.y + 1.5,
							id .. ": on the open floor"
						)
					else
						-- the gate: in the gap of the north wall, nothing standing in it
						check(q.z < cz - hs + 40, "the gate is on the north wall")
						check(
							SideQuestSites.quarryClearance(Config, q.x, q.z) >= q.sx / 2 - 0.01,
							"the gap is open"
						)
						check(q.sx >= 40, "a wide gate (" .. q.sx .. ")")
					end
					-- the landmark never moves with the seed: every week and every server agree, plans or none
					for _, seed in { 202648, 202720 } do
						local wd = WorldMap.build(Config, seed)
						wd.tilePlans = {}
						local again, door = SideQuestSites.place(Config, wd, id)
						check(
							again ~= nil and door ~= nil and again.x == q.x and again.z == q.z,
							id .. ": the same spot in week " .. seed .. " with no tile plans"
						)
					end
				end
			end
			local gate = SideQuestSites.quarry(Config, world, "QuarryGate") :: any
			local lift = SideQuestSites.quarry(Config, world, "MineLift") :: any
			local ring = SideQuestSites.quarry(Config, world, "QuarryRing") :: any
			check(flat(lift.x, lift.z, ring.x, ring.z) >= 120, "the lift and the ring are far apart")
			check(flat(gate.x, gate.z, ring.x, ring.z) >= 200, "the ring is deep in the quarry")
			-- far from every other chain's sites, every week
			for _, seed in { 202647, 202701, 202752 } do
				local wd = if seed == 202647 then world else WorldMap.build(Config, seed)
				SideQuestSites.warm(Config, wd)
				for oid, ost in SQ.sites do
					if not ost.quarry and not ost.dev then
						local ob = SideQuestSites.place(Config, wd, oid)
						if ob then
							for _, id in SITES do
								local q = SideQuestSites.quarry(Config, wd, id) :: any
								check(
									flat(q.x, q.z, ob.x, ob.z) >= 200,
									seed .. ": " .. id .. " is far from " .. oid
								)
							end
						end
					end
				end
			end
			-- the framework checks a quarry site's rules
			check(problems(function() end) == "", "the copy is clean")
			check(string.find(
				problems(function(sq)
					sq.sites.MineLift.quarry = "crater"
				end),
				"quarry crater",
				1,
				true
			) ~= nil, "only a gate or a floor spot")
			check(string.find(
				problems(function(sq)
					sq.sites.MineLift.spot = { 900, 0 }
				end),
				"spot on the quarry floor",
				1,
				true
			) ~= nil, "a floor spot off the quarry")
			check(string.find(
				problems(function(sq)
					sq.sites.QuarryRing.clear = 500
				end),
				"no spot on the quarry fits",
				1,
				true
			) ~= nil, "no floor that clear")
			check(string.find(
				problems(function(sq)
					sq.sites.QuarryGate.district = "Suburbs"
				end),
				"QuarryGate",
				1,
				true
			) ~= nil, "a quarry site is in the Old Quarry")
		end
	)

	test("Lore 11 Old Quarry: the Pit: the gallery, the betting hall, the odds machines, the ring", function()
		check(PocketLayout.known("pit"), "a pocket layout")
		local l = PocketLayout.build(Config, 1, "pit")
		check(#l.boxes < 400, "under 400 parts (" .. #l.boxes .. ")")
		local sp = l.points.spawn
		check(PocketLayout.at(Config, sp[1], sp[2], sp[3]) == 1, "the spawn is inside its pocket")
		check(#(l.lists.rooms or {}) >= 1, "the mine tunnel")
		check(#(l.lists.odds or {}) >= 4, "four odds machines")
		for _, p in { "bets", "stairhead", "pitfloor", "ring", "boss" } do
			check(l.points[p] ~= nil, "has " .. p)
		end
		local deck = PocketLayout.heightAt(l, sp[1], sp[3])
		check(deck > l.floorY + 15, "the gallery stands over the pit")
		for i, r in l.lists.rooms do
			near(PocketLayout.heightAt(l, r[1], r[3]), deck, 0.5, "room " .. i .. " is on the gallery")
		end
		for i, p in l.lists.odds do
			near(
				PocketLayout.heightAt(l, p[1], p[3]),
				deck,
				0.5,
				"odds machine " .. i .. " is on the gallery"
			)
		end
		local bets = l.points.bets
		near(PocketLayout.heightAt(l, bets[1], bets[3]), deck, 0.5, "the betting hall")
		local pf = l.points.pitfloor
		check(PocketLayout.heightAt(l, pf[1], pf[3]) < l.floorY + 1, "the pit floor is at the bottom")
		local ring, boss = l.points.ring, l.points.boss
		local stage = PocketLayout.heightAt(l, ring[1], ring[3])
		check(stage > l.floorY + 1 and stage < l.floorY + 4, "the ring stands on its stage")
		near(PocketLayout.heightAt(l, boss[1], boss[3]), stage, 0.01, "the champion waits in the ring")
		local from = l.points.stairhead
		local prev = PocketLayout.heightAt(l, from[1], from[3])
		local ok = true
		for z = from[3], pf[3], -1 do
			local h = PocketLayout.heightAt(l, from[1], z)
			if h > prev + 1e-6 or prev - h > 2.5 then
				ok = false
			end
			prev = h
		end
		check(ok and prev < l.floorY + 1, "the rock steps walk down from the gallery to the pit floor")
		local pocket = SideQuestPlan.goal(S.steps[5], "hero") :: any
		check(pocket.kind == "pocket" and pocket.layout == "pit", "step 5 is down in the Pit")
		local used = {}
		for _, s in pocket.steps do
			used[s.kind] = true
			if s.at then
				check(l.points[s.at] ~= nil, s.kind .. " at " .. s.at)
			end
			if s.room then
				check(l.lists.rooms[s.room] ~= nil, s.kind .. " in room " .. s.room)
			end
			if s.list then
				check(#(l.lists[s.list] or {}) >= (s.points or 1), s.kind .. " on " .. s.list)
			end
		end
		check(
			used.defeat and used.hold and used.reach and used["break"] and used.boss,
			"tunnel, betting hall, odds machines, ring, champion"
		)
		local src = fs.readFile("src/shared/PocketLayout.luau")
		check(string.find(src, "PLACEHOLDER ART", 1, true) ~= nil, "the crowd is marked placeholder art")
	end)

	test(
		"Lore 11 Old Quarry: the Pitboss is a dress over an existing costumed suit: no new robot type",
		function()
			local profile = ProfileSchema.default()
			for _, p in CreatorRules.index(Config).list do
				if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
					CreatorRules.grant(profile, p)
				end
			end
			local function lookOk(look: any, label: string)
				local ok, why = CreatorRules.validate(Config, profile, look)
				check(ok, label .. "'s look validates (" .. tostring(why) .. ")")
				for slot, i in look.pieces do
					if i > 0 then
						local p = CreatorRules.piece(Config, slot, i)
						check(
							p ~= nil and p.source.kind ~= "pack",
							label .. " " .. slot .. " is never a Robux piece"
						)
					end
				end
			end
			lookOk(FakeRules.lookFrom(Config, SQ.givers.Brick.look, "Brick"), "Brick")
			local fin = SideQuestPlan.goal(S.steps[#S.steps], "hero") :: any
			local suit = Config.Enemies[fin.enemy]
			check(
				suit and suit.on == true and suit.fake and suit.fake.costumed == true,
				"a costumed suit, switched on"
			)
			check(suit.elite and suit.miniBoss, "a boss-lite")
			-- every typeId is still one of the 31 Enemy.Delta can carry, each used once
			local ids = {}
			for _, kind in Config.Enemies.order do
				local cfg = Config.Enemies[kind]
				if cfg and cfg.typeId then
					check(cfg.typeId >= 1 and cfg.typeId < 32, kind .. ": typeId fits 5 bits")
					check(not ids[cfg.typeId], "typeId " .. cfg.typeId .. " used once (" .. kind .. ")")
					ids[cfg.typeId] = true
				end
			end
			check(Config.Enemies.Pitboss == nil, "no Pitboss robot type")
			-- the dress: his own creator look, name and title, a machine that sparks apart
			local d = FakeRules.dress(Config, "Pitboss") :: any
			check(d ~= nil and d.dress == true, "a dress")
			check(d.creature == false, "a machine: it sparks apart, never a light burst")
			local look = LookCodec.read(d.words)
			check(look ~= nil, "its look goes over the wire")
			if look then
				lookOk(look, "the Pitboss")
				check(
					Config.Enemies.look.builds[suit.body.build] == look.build,
					"his build matches the suit's"
				)
			end
			for _, k in FakeRules.DRESS_BODY do
				check(type(d.body[k]) == "table" and #d.body[k] == 3, "his suit colour: " .. k)
			end
			local plate = FakeRules.plate(Config, fin.enemy, false, d)
			check(plate.name == "THE PITBOSS" and plate.sub == SQ.dress.Pitboss.title, "his own name plate")
			check(FakeRules.dress(Config, "Nobody") == nil, "an unknown dress is nil")
			check(
				FakeRules.plate(Config, fin.enemy, false).name == string.upper(suit.name),
				"the Bramblebeast keeps its own plate"
			)
			-- the wire: EnemyService sends it as the robot's identity; every device draws it, never pooled
			local es = fs.readFile("src/server/Services/EnemyService.luau")
			check(string.find(es, "function EnemyService.dress(", 1, true) ~= nil, "EnemyService.dress")
			check(string.find(es, 'Net.fireAll("EnemyIdentity", d)', 1, true) ~= nil, "sent to every device")
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			check(
				string.find(svc, "EnemyService.dress(id, foe.dress)", 1, true) ~= nil,
				"the finale dresses it"
			)
			check(string.find(svc, "Pitboss", 1, true) == nil, "nothing chain-specific in the service")
			local rend = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
			check(
				string.find(rend, "FakeRules.DRESS_BODY", 1, true) ~= nil,
				"the renderer takes the suit colours"
			)
			check(string.find(rend, "ident.dress", 1, true) ~= nil, "and the dress's creature rule")
			check(
				string.find(rend, "(base and base.fake and idents[id])", 1, true) ~= nil,
				"a dressed suit is built for its dress"
			)
			-- the framework checks a dress
			check(string.find(
				problems(function(sq)
					local f = pitOf(sq).steps[8].hero
					f.dress = "Nobody"
				end),
				"dress Nobody",
				1,
				true
			) ~= nil, "an unknown dress")
			check(
				string.find(
					problems(function(sq)
						local f = pitOf(sq).steps[8].hero
						f.enemy = "BruteBot"
						table.insert(sq.finale.enemies, "BruteBot")
					end),
					"a dress goes on a costumed villain's suit",
					1,
					true
				) ~= nil,
				"a dress needs a costumed suit"
			)
			check(string.find(
				problems(function(sq)
					sq.dress.Pitboss.look.pieces.hat = "No Such Hat"
				end),
				"dress Pitboss",
				1,
				true
			) ~= nil, "a dress's pieces are the creator's own")
			check(string.find(
				problems(function(sq)
					sq.dress.Pitboss.body.metal = { 1, 2 }
				end),
				"dress Pitboss: body metal",
				1,
				true
			) ~= nil, "a dress's colours")
			check(string.find(
				problems(function(sq)
					sq.dress.Pitboss.title = "THE BIGGEST, BADDEST CHAMPION OF THE WHOLE PIT"
				end),
				"dress Pitboss: name and title",
				1,
				true
			) ~= nil, "a dress's title fits the plate")
		end
	)

	for _, lead in SIDES do
		local mate = if lead == "hero" then "villain" else "hero"
		local label = if lead == "villain" then "the Syndicate" else "the Vigil"
		test(
			"Lore 11 Old Quarry: The Pit as " .. label .. ": all 8 steps co-op with the other side",
			function()
				local a, b = afterSafehouse(), afterSafehouse()
				check(SideQuestPlan.accept(Config, a, S, 22, lead, false), "the lead takes it from Brick")
				check(SideQuestPlan.accept(Config, b, S, 22, mate, true), "the squadmate from the Journal")
				local credits = { 0, 0 }
				for i, step in S.steps do
					check(
						SideQuestPlan.stepOf(a, S) == i and SideQuestPlan.stepOf(b, S) == i,
						"both on step " .. i
					)
					local g = SideQuestPlan.newGroup(S.id, i)
					local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
					local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
					if SideQuestPlan.shared(step) then
						check(
							ka == "both" and kb == "both" and newA and not newB,
							"step " .. i .. ": one shared goal"
						)
					else
						check(
							ka == lead and kb == mate and newA and newB,
							"step " .. i .. ": a goal per side"
						)
					end
					check(
						SideQuestPlan.set(g, ka, g.sides[ka].need),
						"step " .. i .. ": the lead's side finishes"
					)
					if ka ~= kb then
						check(
							SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
							"step " .. i .. ": and waits for the other side"
						)
						check(
							SideQuestPlan.set(g, kb, g.sides[kb].need),
							"step " .. i .. ": the other side finishes"
						)
					end
					check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
					local last = i == #S.steps
					if last then
						check(SideQuestPlan.card(S, i) ~= nil, "the Pitboss's name card at the finale")
					end
					for n, c in { a, b } do
						credits[n] += SideQuestPlan.stepPay(Config, 22, last)
						check(
							SideQuestPlan.advance(c, S) == (if last then "done" else "next"),
							"step " .. i .. " moves on"
						)
					end
				end
				for n, c in { a, b } do
					check(
						SideQuestPlan.isDone(c, S) and c.story.pinned == 0 and c.sq.at.ThePit == nil,
						"done, untracked"
					)
					check(
						credits[n] > 0 and SideQuestPlan.chainPay(Config, S, 22) > 0,
						"steps and the end pay"
					)
					check(
						not SideQuestPlan.accept(Config, c, S, 22, if n == 1 then lead else mate, false),
						"once only"
					)
					check(
						not SideQuestPlan.isDone(c, SideQuestPlan.chain(Config, "SaltDogs")),
						"the Salt Dogs are untouched"
					)
				end
			end
		)
	end

	test(
		"Lore 11 Old Quarry: the reward is a chain title and one cosmetic; side rep pays every step",
		function()
			local cos = SideQuestPlan.cosmetic(S)
			local n = 0
			for _ in cos do
				n += 1
			end
			check(
				n == 2 and cos.title == "Undisputed" and cos.style == "UndisputedBelt",
				"a title and a style"
			)
			check(Config.Story.unlocks.titles.Undisputed == 11, "a story title (bit 11)")
			local tb = {}
			for name, tbit in Config.Story.unlocks.titles do
				check(not tb[tbit], "title bit " .. tbit .. " used once (" .. name .. ")")
				tb[tbit] = true
			end
			check(GearMath.questStyle(Config, "UndisputedBelt") ~= nil, "the Undisputed Belt is a gear style")
			local styles = 0
			for _, slot in Config.Gear.slotOrder do
				local ns = {}
				for _, row in Config.Gear.styles[slot] do
					check(not ns[row.n], slot .. " style n " .. row.n .. " used once")
					ns[row.n] = true
					if row.quest == "UndisputedBelt" then
						styles += 1
						check(row.tier == "Story" and row.price == nil, "never rolled, never sold")
					end
				end
			end
			check(styles == 1, "one Undisputed Belt")
			for _, k in { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" } do
				check(S.reward[k] == nil, "no " .. k)
			end
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			check(string.find(svc, "ThePit", 1, true) == nil, "nothing chain-specific in the service")
		end
	)

	test("Lore 11 Old Quarry: no old names or Crane in the chain; the Dev panel covers it", function()
		local ARC =
			{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
		local hits = {}
		local function walk(v: any, path: string)
			if type(v) == "string" then
				local w = oldLore(v)
				if w then
					table.insert(hits, path .. ": " .. w)
				end
				for _, a in ARC do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a)
					end
				end
				for _, a in { "Crane", "Halcyon", "Adrian Vale", "Null" } do
					if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
						table.insert(hits, path .. ": " .. a .. " (standalone chain)")
					end
				end
			elseif type(v) == "table" then
				for k, x in v do
					walk(x, path .. "." .. tostring(k))
				end
			end
		end
		walk(S, "ThePit")
		walk(SQ.givers.Brick, "Brick")
		walk(SQ.dress.Pitboss, "Pitboss dress")
		for _, id in SITES do
			walk(SQ.sites[id], id)
		end
		walk(Config.Story.guides.speakers.pitboss, "pitboss")
		walk(Config.Story.guides.speakers.flint, "flint")
		for _, id in { "quarryNight", "pitStory", "fightNight" } do
			walk(Config.Cinema.scenes[id], id)
		end
		walk(Config.Cinema.comic.pages.pitStory, "pitStory page")
		for _, h in hits do
			check(false, "an old name: " .. h)
		end
		check(#hits == 0, "no old lore, retired arc names or main-story names")
		local idx = table.find(SQ.chains, S) :: number
		check(idx ~= nil and 300 + idx <= 1000, "the Dev panel's SQ chain button reaches it")
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(
			string.find(dev, "if not ch.dev then", 1, true) ~= nil,
			"every real chain is on the SQ chain button"
		)
		check(#S.steps <= SQ.maxSteps, "every step fits SQ: start step")
	end)
end

---------------------------------------------------------------------------
-- Lore step 11, the character lines: The Last Partner (Lodestar), Finding Lark (Patch), Hostile Takeover (a
-- Syndicate boss, villains only) and The Scoop (a reporter). Config.SideQuests (the chains, their givers, the
-- city building sites, the four dresses), Shared.SideQuestSites (Docks and Old Town buildings, sites clear of
-- each other), PocketLayout "pound", FakeRules.dress `famous` (a dress over a famous fake), the one-side
-- chain rules, the relay giver, the scenes, the rewards, the Dev panel.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local LookCodec = require("../src/shared/LookCodec")
	local HqRules = require("../src/shared/HqRules")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local SIDES = { "hero", "villain" }
	-- each line: its chain id, save bit, giver, sites, story mission, level, the finale's dress and suit, the
	-- card, the title (and its bit), the style, its speakers, its scenes (bits), the comic page
	local LINES = {
		{
			id = "LastPartner",
			bit = 9,
			giver = "LodestarGiver",
			sites = { "NightOwl", "Penthouse" },
			story = 4,
			level = 8,
			dress = "Vesper",
			suit = "Radiant",
			card = { "VESPER", "THE EVENING STAR" },
			title = "True North",
			tbit = 13,
			style = "TwinStarCape",
			speakers = { "lodestar", "patch", "vesper" },
			scenes = { nightOwl = 160, vesperStory = 161, twoStars = 162 },
			page = "vesperStory",
		},
		{
			id = "FindingLark",
			bit = 10,
			giver = "PatchRelay",
			sites = { "LarkFlat", "Pound" },
			story = 3,
			level = 6,
			dress = "Catchpole",
			suit = "HarvestKing",
			card = { "CATCHPOLE", "THE SPARK CATCHER" },
			title = "Found Family",
			tbit = 14,
			style = "RelayVisor",
			speakers = { "patch", "lark", "catchpole" },
			scenes = { larkFlat = 163, larkStory = 164, netGun = 165 },
			page = "larkStory",
		},
		{
			id = "HostileTakeover",
			bit = 11,
			giver = "Vanta",
			sites = { "OpalRoom", "TorchGarage" },
			story = 2,
			level = 6,
			side = "villain",
			dress = "Scorch",
			suit = "Redline",
			card = { "SAL SCORCH", "BOSS OF THE TORCH CREW" },
			title = "Fireproof",
			tbit = 15,
			style = "ScorchproofGauntlets",
			speakers = { "Vanta", "patch", "scorch" },
			scenes = { opalRoom = 166, scorchStory = 167, torchOut = 168 },
			page = "scorchStory",
		},
		{
			id = "TheScoop",
			bit = 12,
			giver = "Nora",
			sites = { "Studio" },
			story = 6,
			level = 10,
			dress = "Censor",
			suit = "MasqueARade",
			card = { "THE CENSOR", "HE DECIDES WHAT YOU SEE" },
			title = "Front Page",
			tbit = 16,
			style = "PressVest",
			speakers = { "Nora", "patch", "censor" },
			scenes = { newsDesk = 169, cutStory = 170, onAir = 171 },
			page = "cutStory",
		},
	}
	local ALL_SITES = {}
	for _, L in LINES do
		L.chain = SideQuestPlan.chain(Config, L.id) :: any
		L.sides = if L.side then { L.side } else SIDES
		for _, id in L.sites do
			table.insert(ALL_SITES, id)
		end
	end
	-- the lines' robots: existing machine types only (Enemy.Delta's typeId has 5 bits, all used)
	local CREW = {
		"SparkDrone",
		"BurglarBot",
		"SneakBot",
		"ShieldBearer",
		"Bomber",
		"Grappler",
		"Radiant",
		"HarvestKing",
		"Redline",
		"MasqueARade",
	}

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	-- a hero who has cleared Act 1's missions 1 to n
	local function cleared(n: number): any
		local c = ProfileSchema.newCharacter()
		local m = 0
		for i = 1, n do
			m = StoryPlan.setBit(m, i)
		end
		c.story.missions = m
		return c
	end

	local function deep(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deep(x)
		end
		return out
	end

	local function problems(edit: (any) -> ()): string
		local sq = deep(SQ)
		edit(sq)
		local C = setmetatable({ SideQuests = sq }, { __index = Config })
		return table.concat(SideQuestPlan.validate(C), " | ")
	end

	local function chainOf(sq: any, id: string): any
		for _, ch in sq.chains do
			if ch.id == id then
				return ch
			end
		end
		return nil
	end

	local function has(text: string, part: string): boolean
		return string.find(text, part, 1, true) ~= nil
	end

	test(
		"Lore 11 character lines: four lines validate, each its own giver, sites, villain and scenes",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			local guide = fs.readFile("src/client/Ui/GuideHud.luau")
			local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
			local wb = Config.Cinema.wideBits
			local seenBits = {}
			for id, s in Config.Cinema.scenes do
				check(not seenBits[s.bit], "scene bit " .. s.bit .. " used once (" .. id .. ")")
				seenBits[s.bit] = true
			end
			for _, L in LINES do
				local S = L.chain
				check(S ~= nil and not S.dev, L.id .. ": a real chain")
				if not S then
					continue
				end
				check(S.layer == "character" and S.district == nil, L.id .. ": a character line")
				check(#S.steps >= 5 and #S.steps <= 8, L.id .. ": about 5 quests (" .. #S.steps .. ")")
				check(S.bit == L.bit, L.id .. ": save bit " .. L.bit)
				for _, other in SQ.chains do
					check(
						other == S or other.bit ~= S.bit,
						L.id .. ": its own save bit (" .. tostring(other.id) .. ")"
					)
				end
				check(S.unlock.npc == true, L.id .. ": only from its giver")
				check(S.unlock.side == L.side, L.id .. ": its sides")
				local gv = SQ.givers[S.giver]
				check(
					S.giver == L.giver and gv and not gv.dev and gv.anchor == "site",
					L.id .. ": its giver at a site"
				)
				check(
					gv and gv.site == S.site and S.site == L.sites[1],
					L.id .. ": the giver stands at its first site"
				)
				local used = SideQuestPlan.sites(S)
				for _, id in L.sites do
					check(table.find(used, id) ~= nil, L.id .. " uses " .. id)
				end
				for _, id in used do
					check(table.find(L.sites, id) ~= nil, L.id .. ": only its own sites (" .. id .. ")")
				end
				-- each side its flavour; most steps split by side
				local split = 0
				for i, step in S.steps do
					for _, side in L.sides do
						local g = SideQuestPlan.goal(step, side)
						check(g ~= nil, L.id .. " step " .. i .. ": a " .. side .. " goal")
					end
					if #L.sides == 2 then
						if SideQuestPlan.shared(step) then
							local g = SideQuestPlan.goal(step, "hero") :: any
							check(
								type(g.villainText) == "string" and g.villainText ~= g.text,
								L.id .. " step " .. i .. ": the Syndicate reads its own goal"
							)
						else
							split += 1
						end
					end
				end
				if #L.sides == 2 then
					check(split >= 4, L.id .. ": most steps give each side its own job (" .. split .. ")")
				end
				-- the finale: a dress over an existing suit on the finale list, both sides together
				local last = S.steps[#S.steps]
				for _, side in L.sides do
					local fin = SideQuestPlan.goal(last, side) :: any
					check(
						fin.kind == "finale" and fin.dress == L.dress,
						L.id .. ": " .. L.dress .. " at the end"
					)
					check(
						fin.enemy == L.suit and table.find(SQ.finale.enemies, fin.enemy) ~= nil,
						L.id .. ": the suit"
					)
				end
				-- existing robot types only
				local crewOnly = true
				local function crew(kind: any)
					if table.find(CREW, kind) == nil then
						crewOnly = false
						check(false, L.id .. ": not a known robot " .. tostring(kind))
					end
				end
				for _, step in S.steps do
					for _, side in L.sides do
						local g = SideQuestPlan.goal(step, side) :: any
						for _, row in g.squads or {} do
							crew(row[1])
						end
						for _, row in g.adds or {} do
							crew(row[1])
						end
						if g.guards then
							crew(g.guards[1])
						end
						if g.kind == "chase" or g.kind == "finale" then
							crew(g.enemy)
						end
						for _, s in g.steps or {} do
							for _, row in s.squads or {} do
								crew(row[1])
							end
							for _, row in s.waves or {} do
								crew(row[1])
							end
							if s.enemy then
								crew(s.enemy)
							end
							if s.adds then
								crew(s.adds[1])
							end
						end
					end
				end
				check(crewOnly, L.id .. ": every robot is an existing type")
				-- who speaks: guide speakers with portraits GuideHud draws
				local who = {}
				for _, step in S.steps do
					for _, l in step.lines or {} do
						who[l.who] = true
					end
				end
				for _, w in L.speakers do
					check(who[w] == true, L.id .. " speaks: " .. w)
					local sp = Config.Story.guides.speakers[w] or SQ.givers[w]
					check(
						sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
						w .. ": a speaker with a portrait and a blip"
					)
					for _, e in (sp and sp.portrait.extras) or {} do
						check(has(guide, '"' .. e .. '"'), w .. ": GuideHud draws " .. e)
					end
				end
				for _, e in gv.portrait.extras or {} do
					check(has(guide, '"' .. e .. '"'), L.giver .. ": GuideHud draws " .. e)
				end
				-- 1 to 3 short scenes in Cinema.wideBits 160 to 171, one before the finale
				local n = 0
				for _, step in S.steps do
					if step.scene then
						n += 1
						local s = Config.Cinema.scenes[step.scene]
						check(L.scenes[step.scene] ~= nil, L.id .. ": its own scene " .. step.scene)
						check(s ~= nil and s.client == true, step.scene .. ": a device scene")
						check(s and CinemaPlan.check(Config, s), step.scene .. ": 5 to 20 s")
						check(
							s
								and s.bit == L.scenes[step.scene]
								and s.bit >= wb.from
								and s.bit <= wb.to
								and CinemaPlan.clientBit(Config, s.bit),
							step.scene
								.. ": scene bit "
								.. tostring(L.scenes[step.scene])
								.. ", one a device may send"
						)
						for _, l in (s and s.lines) or {} do
							check(
								Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
								step.scene .. ": speaker " .. tostring(l.who)
							)
							check(
								SideQuestPlan.fixedText(l.text, 120) == nil,
								step.scene .. ": a short fixed line"
							)
						end
					end
				end
				check(n >= 1 and n <= 3, L.id .. ": 1 to 3 scenes (" .. n .. ")")
				check(last.scene ~= nil, L.id .. ": a scene before the finale")
				local page = Config.Cinema.comic.pages[L.page]
				check(page ~= nil and #page.panels == 4, L.id .. ": the villain's story is a comic page")
				for _, p in (page and page.panels) or {} do
					check(SideQuestPlan.fixedText(p.caption, 90) == nil, L.page .. ": a short caption")
					check(has(hud, 'kind == "' .. p.scene .. '"'), L.page .. ": the comic draws " .. p.scene)
				end
				for id, b in L.scenes do
					check(b >= 160 and b <= 171, id .. ": inside the character lines' scene bits")
				end
			end
		end
	)

	test("Lore 11 character lines: each finale's name card, on the last step only", function()
		for _, L in LINES do
			local S = L.chain
			for i = 1, #S.steps - 1 do
				check(SideQuestPlan.card(S, i) == nil, L.id .. ": no card on step " .. i)
			end
			local card = SideQuestPlan.card(S, #S.steps) :: any
			check(card ~= nil and card.name == L.card[1], L.id .. ": the card names " .. L.card[1])
			check(card and card.title == L.card[2], L.id .. ": and the title")
			check(
				card
					and SideQuestPlan.fixedText(card.name, 32) == nil
					and SideQuestPlan.fixedText(card.title, 32) == nil,
				L.id .. ": fixed text that fits the card"
			)
		end
	end)

	test(
		"Lore 11 character lines: unlocks: the story so far and a level; only the giver offers them",
		function()
			for _, L in LINES do
				local S = L.chain
				for _, side in SIDES do
					local mine = L.side == nil or L.side == side
					if mine then
						local early = cleared(L.story - 1)
						local st, why = SideQuestPlan.state(Config, early, S, L.level + 20, side)
						check(
							st == "locked" and why == "story",
							L.id .. " " .. side .. ": waits for mission " .. L.story
						)
						local c = cleared(L.story)
						local st2, why2, lv = SideQuestPlan.state(Config, c, S, L.level - 1, side)
						check(
							st2 == "locked" and why2 == "level" and lv == L.level,
							L.id .. " " .. side .. ": and level " .. L.level
						)
						check(
							SideQuestPlan.state(Config, c, S, L.level, side) == "open",
							L.id .. " " .. side .. ": open"
						)
						local pick, kind = SideQuestPlan.talkPick(Config, c, L.giver, L.level, side, false)
						check(pick == S and kind == "offer", L.id .. " " .. side .. ": its giver offers it")
						check(
							not SideQuestPlan.accept(Config, c, S, L.level, side, true),
							L.id .. " " .. side .. ": never from the Journal"
						)
						check(SideQuestPlan.accept(Config, c, S, L.level, side, false), "but from the giver")
						local p2, k2 = SideQuestPlan.talkPick(Config, c, L.giver, L.level, side, false)
						check(p2 == S and k2 == "resume", L.id .. " " .. side .. ": and the giver resumes it")
						for _, O in LINES do
							if O ~= L then
								check(
									SideQuestPlan.talkPick(
										Config,
										cleared(#Config.Story.missions),
										O.giver,
										50,
										side,
										false
									) ~= S,
									L.id .. ": " .. O.giver .. " never offers it"
								)
							end
						end
					else
						local c = cleared(#Config.Story.missions)
						local st3, why3 = SideQuestPlan.state(Config, c, S, 50, side)
						check(
							st3 == "locked" and why3 == "side",
							L.id .. " " .. side .. ": locked for this side"
						)
						check(
							select(2, SideQuestPlan.talkPick(Config, c, L.giver, 50, side, false)) == "none",
							L.id .. ": its giver has nothing for a " .. side
						)
						check(not SideQuestPlan.accept(Config, c, S, 50, side, false), "and can't take it")
					end
				end
			end
			-- the Duchess's own line for a Vigil hero (and a Syndicate villain who is not ready yet)
			local v = SQ.givers.Vanta.none
			check(type(v) == "table" and v.hero ~= v.villain, "Vanta has her own line for each side")
			for _, side in SIDES do
				check(SideQuestPlan.fixedText(v[side], 120) == nil, "a fixed line: " .. side)
			end
			local hud = fs.readFile("src/client/Ui/StoryHud.luau")
			check(has(hud, "GuidePlan.lineText(gv.none, side)"), "the giver says it")
			check(
				has(
					problems(function(sq)
						sq.givers.Vanta.none = { hero = "50% off", villain = "Fine" }
					end),
					"giver Vanta none line"
				),
				"a none line is fixed text"
			)
			local J = fs.readFile("src/client/Ui/Journal.luau")
			for _, d in { 'Docks = "', 'OldTown = "', 'Uptown = "', 'Downtown = "' } do
				check(has(J, d), "the Journal names the district " .. d)
			end
		end
	)

	test(
		"Lore 11 character lines: sites are existing city buildings by rule, clear of every other site",
		function()
			local hd = HqRules.heroDoor(Config, world)
			local fd = world.spots.foundryDoor
			for _, seed in { 202647, 202760 } do
				local wd = if seed == 202647 then world else WorldMap.build(Config, seed)
				SideQuestSites.warm(Config, wd)
				for _, id in ALL_SITES do
					local st = SQ.sites[id]
					check(SideQuestSites.isBuilding(st), id .. ": an existing city building")
					local b, door = SideQuestSites.place(Config, wd, id)
					check(b ~= nil and door ~= nil, seed .. " " .. id .. ": a building with a door")
					if not b or not door then
						continue
					end
					local h = b.h or (b.top - b.base)
					check(
						h >= st.height[1] and h <= st.height[2],
						id .. ": in its height range (" .. h .. ")"
					)
					check(b.district == nil or b.district == st.district, id .. ": in " .. st.district)
					if st.district == "Docks" or st.district == "OldTown" then
						local found = false
						for _, x in wd.buildings do
							if x == b then
								found = true
							end
						end
						check(
							found and b.district == st.district,
							id .. ": one of the district's own buildings"
						)
						for _, s in wd.safehouses do
							check(
								flat(b.x, b.z, s.x, s.z) >= st.away.pad,
								id .. ": clear of every safehouse pad"
							)
						end
						check(
							flat(b.x, b.z, hd.x, hd.z) >= st.away.door,
							id .. ": clear of the Safehouse door"
						)
						check(flat(b.x, b.z, fd.x, fd.z) >= st.away.door, id .. ": clear of the Foundry door")
						-- the door opens on open ground, beside the building
						local ok = WorldMap.heightAt(wd, door.x, door.z) <= Config.City.ground.y + 1.5
						check(ok, id .. ": the door is on the street")
					end
					-- clear of every other building and square site
					for oid, ost in SQ.sites do
						if oid ~= id and (SideQuestSites.isBuilding(ost) or ost.square) then
							local ob = SideQuestSites.place(Config, wd, oid)
							-- (of two sites that both keep away.site, the later id keeps its own from the earlier)
							local gap = if ost.away
									and ost.away.site
									and oid > id
								then ost.away.site
								else st.away.site
							if ob then
								check(
									flat(b.x, b.z, ob.x, ob.z) >= gap,
									seed .. ": " .. id .. " is " .. gap .. " from " .. oid
								)
							end
						end
					end
				end
			end
			-- the same building every time: the city never moves with the weekly seed
			local again = WorldMap.build(Config, 202647)
			for _, id in ALL_SITES do
				local a = SideQuestSites.place(Config, world, id)
				local b = SideQuestSites.place(Config, again, id)
				check(a and b and a.x == b.x and a.z == b.z, id .. ": the same building on every server")
			end
			-- the framework checks the new site rules
			check(problems(function() end) == "", "the copy is clean")
			check(
				has(
					problems(function(sq)
						sq.sites.Pound.away.pad = nil
					end),
					"away.pad"
				),
				"a Docks site keeps clear of the pads"
			)
			check(
				has(
					problems(function(sq)
						sq.sites.LarkFlat.away.door = -1
					end),
					"away.door"
				),
				"an Old Town site keeps clear of the HQ doors"
			)
			check(
				has(
					problems(function(sq)
						sq.sites.NightOwl.away.site = "far"
					end),
					"away.site"
				),
				"away.site is a distance"
			)
		end
	)

	test(
		"Lore 11 character lines: the Spark Pound: intake office, kennel hall, collar scanners, Lark's cell",
		function()
			check(PocketLayout.known("pound"), "a pocket layout")
			local l = PocketLayout.build(Config, 1, "pound")
			check(#l.boxes < 400, "under 400 parts (" .. #l.boxes .. ")")
			local sp = l.points.spawn
			check(PocketLayout.at(Config, sp[1], sp[2], sp[3]) == 1, "the spawn is inside its pocket")
			check(#(l.lists.rooms or {}) >= 1, "the intake office")
			check(#(l.lists.collars or {}) >= 4, "four collar scanners")
			for _, p in { "kennels", "cell", "boss" } do
				check(l.points[p] ~= nil, "has " .. p)
			end
			local floor = PocketLayout.heightAt(l, sp[1], sp[3])
			for _, p in { "kennels", "boss" } do
				local pt = l.points[p]
				near(PocketLayout.heightAt(l, pt[1], pt[3]), floor, 0.6, p .. " is on the warehouse floor")
			end
			local cell = l.points.cell
			check(PocketLayout.heightAt(l, cell[1], cell[3]) > floor, "the cell stands on its step")
			local S = SideQuestPlan.chain(Config, "FindingLark") :: any
			local pocket = SideQuestPlan.goal(S.steps[5], "hero") :: any
			check(pocket.kind == "pocket" and pocket.layout == "pound", "step 5 is inside the pound")
			local used = {}
			for _, s in pocket.steps do
				used[s.kind] = true
				if s.at then
					check(l.points[s.at] ~= nil, s.kind .. " at " .. s.at)
				end
				if s.room then
					check(l.lists.rooms[s.room] ~= nil, s.kind .. " in room " .. s.room)
				end
				if s.list then
					check(#(l.lists[s.list] or {}) >= (s.points or 1), s.kind .. " on " .. s.list)
				end
			end
			check(
				used.defeat and used.hold and used.reach and used["break"] and used.boss,
				"office, kennels, scanners, cell, warden"
			)
			local src = fs.readFile("src/shared/PocketLayout.luau")
			check(has(src, "function BUILD.pound("), "its builder")
		end
	)

	test(
		"Lore 11 character lines: four dresses over existing suits; Vesper cracks like a famous fake",
		function()
			local profile = ProfileSchema.default()
			for _, p in CreatorRules.index(Config).list do
				if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
					CreatorRules.grant(profile, p)
				end
			end
			local function lookOk(look: any, label: string)
				local ok, why = CreatorRules.validate(Config, profile, look)
				check(ok, label .. "'s look validates (" .. tostring(why) .. ")")
				for slot, i in look.pieces do
					if i > 0 then
						local p = CreatorRules.piece(Config, slot, i)
						check(
							p ~= nil and p.source.kind ~= "pack",
							label .. " " .. slot .. " is never a Robux piece"
						)
					end
				end
			end
			for _, id in { "LodestarGiver", "Vanta", "Nora" } do
				lookOk(FakeRules.lookFrom(Config, SQ.givers[id].look, id), id)
			end
			for _, L in LINES do
				local suit = Config.Enemies[L.suit]
				local d = FakeRules.dress(Config, L.dress) :: any
				check(d ~= nil and d.dress == true and d.creature == false, L.dress .. ": a machine's dress")
				local look = d and LookCodec.read(d.words)
				check(look ~= nil, L.dress .. ": its look goes over the wire")
				if look then
					lookOk(look, L.dress)
					check(
						Config.Enemies.look.builds[suit.body.build] == look.build,
						L.dress .. ": the suit's build"
					)
				end
				for _, k in FakeRules.DRESS_BODY do
					check(type(d.body[k]) == "table" and #d.body[k] == 3, L.dress .. " suit colour: " .. k)
				end
				local plate = FakeRules.plate(Config, L.suit, false, d)
				check(
					plate.name == L.card[1] and plate.sub == SQ.dress[L.dress].title,
					L.dress .. ": its own plate"
				)
				check(Config.Enemies[L.dress] == nil, L.dress .. ": no robot type of its own")
				check(
					suit.on == true and suit.elite and suit.miniBoss,
					L.suit .. ": a boss-lite suit, switched on"
				)
				if L.dress == "Vesper" then
					check(
						d.famous == true and suit.fake and not suit.fake.costumed,
						"Vesper is over a famous fake"
					)
					local cracked = FakeRules.plate(Config, L.suit, true, d)
					check(
						cracked.red and cracked.name == Config.Enemies.fakes.word and cracked.sub == "VESPER",
						"cracked, her plate reads FAKE over her own name"
					)
				else
					check(
						d.famous == false and suit.fake and suit.fake.costumed,
						L.dress .. ": over a costumed suit"
					)
				end
			end
			local ids = {}
			for _, kind in Config.Enemies.order do
				local cfg = Config.Enemies[kind]
				if cfg and cfg.typeId then
					check(
						not ids[cfg.typeId] and cfg.typeId < 32,
						"typeId " .. cfg.typeId .. " fits and is used once"
					)
					ids[cfg.typeId] = true
				end
			end
			-- the server: a famous dress only over a famous fake; a dressed fake's crack is no news headline
			local es = fs.readFile("src/server/Services/EnemyService.luau")
			check(
				has(es, "(d.famous and cfg.fake and not cfg.fake.costumed and not cfg.twin)"),
				"EnemyService's rule"
			)
			check(has(es, "if not (idents[ev.e] and idents[ev.e].dress) then"), "no news for a dressed fake")
			-- the framework checks a famous dress
			check(
				has(
					problems(function(sq)
						sq.dress.Vesper.famous = nil
					end),
					"a dress goes on a costumed villain's suit"
				),
				"a plain dress never goes over a famous fake"
			)
			check(
				has(
					problems(function(sq)
						sq.dress.Catchpole.famous = true
					end),
					"a dress goes on a costumed villain's suit"
				),
				"a famous dress never goes over a costumed suit"
			)
			check(
				has(
					problems(function(sq)
						chainOf(sq, "LastPartner").steps[6].hero.enemy = "EvilTwin"
						table.insert(sq.finale.enemies, "EvilTwin")
					end),
					"a dress goes on a costumed villain's suit"
				),
				"nor over the evil twin"
			)
			check(
				has(
					problems(function(sq)
						sq.dress.Vesper.famous = "yes"
					end),
					"dress Vesper"
				),
				"famous is true or nothing"
			)
		end
	)

	test(
		"Lore 11 character lines: Lodestar gives his line in his own look; Patch's is a relay box",
		function()
			local lg = SQ.givers.LodestarGiver
			local story = Config.Story.opening.lodestar.look
			local a = FakeRules.lookFrom(Config, lg.look, "LodestarGiver")
			local b = FakeRules.lookFrom(Config, story, "Lodestar")
			check(a ~= nil and b ~= nil, "both looks build")
			if a and b then
				check(
					table.concat(LookCodec.write(a), ",") == table.concat(LookCodec.write(b), ","),
					"the giver wears Lodestar's own look"
				)
			end
			local sp = Config.Story.guides.speakers.lodestar
			check(lg.name == sp.name and lg.blip == sp.blip, "his name and blip")
			for k, v in sp.portrait do
				if type(v) == "table" then
					check(table.concat(v, ",") == table.concat(lg.portrait[k], ","), "his portrait: " .. k)
				else
					check(lg.portrait[k] == v, "his portrait: " .. k)
				end
			end
			local pr = SQ.givers.PatchRelay
			local patch = Config.Story.guides.speakers.patch
			check(
				pr.relay == true and pr.style == "radio" and pr.look == nil,
				"Patch's relay is a radio voice"
			)
			check(
				pr.portrait.shape == patch.portrait.shape and pr.blip == patch.blip,
				"with Patch's portrait"
			)
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			check(has(svc, "local function relayModel("), "the service draws the relay box")
			check(has(svc, "if gv.relay"), "for a relay giver")
			check(has(svc, "PLACEHOLDER ART"), "marked placeholder art")
			check(
				has(
					problems(function(sq)
						sq.givers.PatchRelay.look = deep(sq.givers.Nora.look)
					end),
					"a relay is a radio voice with no look"
				),
				"a relay wears no look"
			)
			check(
				has(
					problems(function(sq)
						sq.givers.PatchRelay.style = "person"
					end),
					"a relay is a radio voice"
				),
				"a relay is a radio giver"
			)
		end
	)

	test(
		"Lore 11 character lines: Hostile Takeover is the Syndicate's alone: one side's goals and lines",
		function()
			local S = SideQuestPlan.chain(Config, "HostileTakeover") :: any
			for i, step in S.steps do
				check(
					step.hero == nil and type(step.villain) == "table",
					"step " .. i .. ": a villain goal only"
				)
				check(SideQuestPlan.goal(step, "hero") == nil, "step " .. i .. ": nothing for a hero")
				for _, l in step.lines or {} do
					check(type(l.text) == "string", "step " .. i .. ": its lines are the Syndicate's")
				end
			end
			check(S.blurb.villain ~= nil and S.blurb.hero == nil, "the Journal line is the Syndicate's")
			check(SideQuestPlan.card(S, #S.steps) ~= nil, "the card reads from the villain's finale")
			local sides = SideQuestPlan.sidesOf(Config, S)
			check(#sides == 1 and sides[1] == "villain", "a line for one side")
			check(
				#SideQuestPlan.sidesOf(Config, SideQuestPlan.chain(Config, "TheScoop")) == 2,
				"others: both"
			)
			check(
				has(
					problems(function(sq)
						chainOf(sq, "HostileTakeover").steps[3].villain = nil
					end),
					"no villain goal"
				),
				"every step has its villain goal"
			)
			check(
				has(
					problems(function(sq)
						chainOf(sq, "HostileTakeover").unlock.side = nil
					end),
					"no hero goal"
				),
				"without the side rule, it would need hero goals"
			)
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			check(
				has(svc, "if not SideQuestPlan.goal(chain.steps[idx], side) then"),
				"the service skips a hero"
			)
		end
	)

	for _, L in LINES do
		local pairs_ = if L.side
			then { { L.side, L.side } }
			else { { "hero", "villain" }, { "villain", "hero" } }
		for _, pr in pairs_ do
			local lead, mate = pr[1], pr[2]
			local label = if lead == "villain" then "the Syndicate" else "the Vigil"
			test(
				"Lore 11 character lines: "
					.. L.id
					.. " as "
					.. label
					.. ": every step co-op, start to finish",
				function()
					local S = L.chain
					local lv = L.level + 2
					local a, b = cleared(L.story), cleared(L.story)
					check(
						SideQuestPlan.accept(Config, a, S, lv, lead, false),
						"the lead takes it from the giver"
					)
					check(
						SideQuestPlan.accept(Config, b, S, lv, mate, false),
						"the squadmate from the giver too"
					)
					if L.side then
						local h = cleared(L.story)
						check(
							not SideQuestPlan.accept(Config, h, S, lv, "hero", false),
							"a Vigil hero never can"
						)
					end
					local credits = { 0, 0 }
					for i, step in S.steps do
						check(
							SideQuestPlan.stepOf(a, S) == i and SideQuestPlan.stepOf(b, S) == i,
							"both on step " .. i
						)
						local g = SideQuestPlan.newGroup(S.id, i)
						local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
						local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
						if lead == mate then
							check(ka == kb and newA and not newB, "step " .. i .. ": one goal for the pair")
						elseif SideQuestPlan.shared(step) then
							check(
								ka == "both" and kb == "both" and newA and not newB,
								"step " .. i .. ": shared"
							)
						else
							check(
								ka == lead and kb == mate and newA and newB,
								"step " .. i .. ": a goal per side"
							)
						end
						check(SideQuestPlan.set(g, ka, g.sides[ka].need), "step " .. i .. ": the lead's side")
						if ka ~= kb then
							check(
								SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
								"step " .. i .. ": waits for the other side"
							)
							check(
								SideQuestPlan.set(g, kb, g.sides[kb].need),
								"step " .. i .. ": the other side"
							)
						end
						check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
						local last = i == #S.steps
						if last then
							check(SideQuestPlan.card(S, i) ~= nil, "the name card at the finale")
						end
						for n, c in { a, b } do
							credits[n] += SideQuestPlan.stepPay(Config, lv, last)
							check(
								SideQuestPlan.advance(c, S) == (if last then "done" else "next"),
								"step " .. i .. " moves on"
							)
						end
					end
					for n, c in { a, b } do
						check(
							SideQuestPlan.isDone(c, S) and c.story.pinned == 0 and c.sq.at[S.id] == nil,
							"done, untracked"
						)
						check(
							credits[n] > 0 and SideQuestPlan.chainPay(Config, S, lv) > 0,
							"steps and the end pay"
						)
						check(
							not SideQuestPlan.accept(Config, c, S, lv, if n == 1 then lead else mate, false),
							"once only"
						)
						for _, O in LINES do
							if O ~= L then
								check(not SideQuestPlan.isDone(c, O.chain), O.id .. " is untouched")
							end
						end
					end
				end
			)
		end
	end

	test("Lore 11 character lines: each reward is a chain title and one cosmetic", function()
		local tb = {}
		for name, tbit in Config.Story.unlocks.titles do
			check(not tb[tbit], "title bit " .. tbit .. " used once (" .. name .. ")")
			tb[tbit] = true
		end
		for _, L in LINES do
			local S = L.chain
			local cos = SideQuestPlan.cosmetic(S)
			local n = 0
			for _ in cos do
				n += 1
			end
			check(n == 2 and cos.title == L.title and cos.style == L.style, L.id .. ": a title and a style")
			check(Config.Story.unlocks.titles[L.title] == L.tbit, L.title .. ": title bit " .. L.tbit)
			check(GearMath.questStyle(Config, L.style) ~= nil, L.style .. ": a gear style")
			local styles = 0
			for _, slot in Config.Gear.slotOrder do
				local ns = {}
				for _, row in Config.Gear.styles[slot] do
					check(not ns[row.n], slot .. " style n " .. row.n .. " used once")
					ns[row.n] = true
					if row.quest == L.style then
						styles += 1
						check(
							row.tier == "Story" and row.price == nil,
							L.style .. ": never rolled, never sold"
						)
						check(row.n < Config.Gear.setStyleBase, L.style .. ": below the set styles")
					end
				end
			end
			check(styles == 1, L.style .. ": one of it")
			for _, k in { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" } do
				check(S.reward[k] == nil, L.id .. ": no " .. k)
			end
			check(S.reward.share <= SQ.pay.maxShare, L.id .. ": the pay share")
		end
		local svc = fs.readFile("src/server/Services/SideQuestService.luau")
		for _, L in LINES do
			check(not has(svc, L.id), L.id .. ": nothing chain-specific in the service")
		end
	end)

	test(
		"Lore 11 character lines: no old names, Crane or the main story's names; the Dev panel covers them",
		function()
			local ARC =
				{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
			-- (and nate's other games' heroes: chain 7's diver was renamed for one)
			local OTHER = { "Marlo", "Mossbell" }
			local hits = {}
			local function walk(v: any, path: string)
				if type(v) == "string" then
					local w = oldLore(v)
					if w then
						table.insert(hits, path .. ": " .. w)
					end
					for _, list in { ARC, OTHER, { "Crane", "Halcyon", "Adrian Vale", "Null", "Velvet Paw" } } do
						for _, a in list do
							if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
								table.insert(hits, path .. ": " .. a)
							end
						end
					end
				elseif type(v) == "table" then
					for k, x in v do
						walk(x, path .. "." .. tostring(k))
					end
				end
			end
			for _, L in LINES do
				walk(L.chain, L.id)
				walk(SQ.givers[L.giver], L.giver)
				walk(SQ.dress[L.dress], L.dress .. " dress")
				for _, id in L.sites do
					walk(SQ.sites[id], id)
				end
				for _, w in L.speakers do
					walk(Config.Story.guides.speakers[w], w)
				end
				for id in L.scenes do
					walk(Config.Cinema.scenes[id], id)
				end
				walk(Config.Cinema.comic.pages[L.page], L.page .. " page")
			end
			for _, h in hits do
				check(false, "an old name: " .. h)
			end
			check(#hits == 0, "no old lore, retired arc names, main-story names or other games' names")
			local dev = fs.readFile("src/client/Ui/DevPanel.luau")
			check(has(dev, "if not ch.dev then"), "every real chain is on the SQ chain button")
			for _, L in LINES do
				local idx = table.find(SQ.chains, L.chain) :: number
				check(
					idx ~= nil and 300 + idx <= 1000,
					L.id .. ": the Dev panel's SQ chain button reaches it"
				)
				check(#L.chain.steps <= SQ.maxSteps, L.id .. ": every step fits SQ: start step")
			end
		end
	)
end

---------------------------------------------------------------------------
-- Lore step 11, the origin lines: one personal line per origin (Config.Creator.origins), offered only to heroes of
-- that origin. Config.SideQuests (the 5 chains, their givers, sites and dresses), Shared.SideQuestSites (an Old
-- Town building by Clock Square, Radio Hill's terrace, a Downtown building kept off the other chains', two
-- Suburbs lots), PocketLayout "ashlab" and "ironhall", the comic pages (each ends on the one Spark), the finale
-- scenes, the rewards, the Dev panel.
---------------------------------------------------------------------------

do
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CreatorRules = require("../src/shared/CreatorRules")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local StoryPlan = require("../src/shared/StoryPlan")
	local LookCodec = require("../src/shared/LookCodec")
	local fs = require("@lune/fs")
	local SQ = Config.SideQuests
	local SIDES = { "hero", "villain" }
	-- one row a line, in origin order
	local LINES = {
		{
			id = "AshgroveTest",
			origin = 1,
			bit = 13,
			giver = "Okafor",
			site = "Underlab",
			dress = "Holloway",
			card = { "DOCTOR HOLLOWAY", "DIRECTOR OF ASHGROVE LABS" },
			title = "Test Passed",
			titleBit = 17,
			style = "KindlingCore",
			comic = "kindlerTruth",
			finale = "hollowayRig",
			bits = { 192, 193 },
			speakers = { "Okafor", "patch", "lodestar", "holloway" },
			pocket = "ashlab",
			gap = "sealDoor",
		},
		{
			id = "StarbloodCalling",
			origin = 2,
			bit = 14,
			giver = "Ruth",
			site = "RadioMast",
			dress = "Voidhound",
			card = { "THE VOIDHOUND", "HUNTER FROM THE STARS" },
			title = "Starborn",
			titleBit = 18,
			style = "StarfallWings",
			comic = "podMessage",
			finale = "voidhoundLands",
			bits = { 194, 195 },
			speakers = { "Ruth", "patch", "voidhound" },
		},
		{
			id = "LastOwner",
			origin = 3,
			bit = 15,
			giver = "Moth",
			site = "VintageCurios",
			dress = "Morrow",
			card = { "MORROW THE MIRAGE", "THE JEALOUS ILLUSIONIST" },
			title = "Relic Keeper",
			titleBit = 19,
			style = "MoonstoneCirclet",
			comic = "relicTruth",
			finale = "morrowCurtain",
			bits = { 196, 197 },
			speakers = { "Moth", "patch", "lodestar", "ambrose", "morrow" },
		},
		{
			id = "SuitRecall",
			origin = 4,
			bit = 16,
			giver = "Tess",
			site = "Workshop",
			dress = "Clawback",
			card = { "CLAWBACK", "THE REPO KING" },
			title = "No Returns",
			titleBit = 20,
			style = "ClawbackGauntlet",
			comic = "coreTruth",
			finale = "clawbackClaim",
			bits = { 198, 199 },
			speakers = { "Tess", "patch", "clawback" },
		},
		{
			id = "TakenMaster",
			origin = 5,
			bit = 17,
			giver = "Kiko",
			site = "WillowDojo",
			dress = "Gale",
			card = { "GALE", "THE MASTER'S FALLEN STUDENT" },
			title = "Lesson Learned",
			titleBit = 21,
			style = "MastersBelt",
			comic = "masterLesson",
			finale = "galeChallenge",
			bits = { 200, 201 },
			speakers = { "Kiko", "lodestar", "hoshi", "gale" },
			pocket = "ironhall",
			gap = "ironDoor",
		},
	}
	local MINE =
		{ Underlab = true, RadioMast = true, VintageCurios = true, WillowDojo = true, Workshop = true }

	local function flat(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	local function hero(origin: number, safehouse: boolean): any
		local c = ProfileSchema.newCharacter()
		c.origin = origin
		c.story.missions = if safehouse
			then StoryPlan.setBit(StoryPlan.setBit(0, 1), 2)
			else StoryPlan.setBit(0, 1)
		return c
	end

	local function deep(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deep(x)
		end
		return out
	end

	-- the validator's problems for a copy of Config.SideQuests changed by edit
	local function problems(edit: (any) -> ()): string
		local sq = deep(SQ)
		edit(sq)
		local C = setmetatable({ SideQuests = sq }, { __index = Config })
		return table.concat(SideQuestPlan.validate(C), " | ")
	end

	-- every robot kind a chain names (squads, adds, guards, chasers, pocket steps, the finale)
	local function robots(S: any): { string }
		local out = {}
		local function add(kind: any)
			table.insert(out, tostring(kind))
		end
		for _, step in S.steps do
			for _, side in SIDES do
				local g = SideQuestPlan.goal(step, side) :: any
				for _, row in g.squads or {} do
					add(row[1])
				end
				for _, row in g.adds or {} do
					add(row[1])
				end
				if g.guards then
					add(g.guards[1])
				end
				if g.kind == "chase" or g.kind == "finale" then
					add(g.enemy)
				end
				for _, s in g.steps or {} do
					for _, row in s.squads or {} do
						add(row[1])
					end
					for _, row in s.waves or {} do
						add(row[1])
					end
					if s.enemy then
						add(s.enemy)
					end
					if s.adds then
						add(s.adds[1])
					end
				end
			end
		end
		return out
	end

	test(
		"Lore 11 Origins: five origin lines validate: one an origin, 5 to 8 quests, each side its flavour",
		function()
			local bad = SideQuestPlan.validate(Config)
			for _, b in bad do
				check(false, b)
			end
			check(#bad == 0, "the chain validator passes")
			local origins = {}
			local guide = fs.readFile("src/client/Ui/GuideHud.luau")
			for _, L in LINES do
				local S = SideQuestPlan.chain(Config, L.id) :: any
				check(S ~= nil and not S.dev, L.id .. ": a real chain")
				if S then
					check(S.layer == "origin" and S.unlock.origin == L.origin, L.id .. ": an origin line")
					check(Config.Creator.origins[L.origin] ~= nil, L.id .. ": a real origin")
					origins[S.unlock.origin] = (origins[S.unlock.origin] or 0) + 1
					check(#S.steps >= 5 and #S.steps <= 8, L.id .. ": 5 to 8 quests (" .. #S.steps .. ")")
					check(S.bit == L.bit, L.id .. ": save bit " .. L.bit)
					for _, other in SQ.chains do
						check(
							other == S or other.bit ~= S.bit,
							L.id .. ": its own save bit (" .. tostring(other.id) .. ")"
						)
					end
					local g = SQ.givers[L.giver]
					check(
						S.giver == L.giver and g and not g.dev and g.anchor == "site",
						L.id .. ": its giver at a site"
					)
					check(S.site == L.site and g and g.site == L.site, L.id .. ": at " .. L.site)
					check(table.find(SideQuestPlan.sites(S), L.site) ~= nil, L.id .. ": uses its site")
					local last = S.steps[#S.steps]
					local fin = SideQuestPlan.goal(last, "hero") :: any
					check(
						SideQuestPlan.shared(last) and fin.kind == "finale" and fin.dress == L.dress,
						L.id .. ": " .. L.dress .. ", both sides together"
					)
					check(
						table.find(SQ.finale.enemies, fin.enemy) ~= nil,
						L.id .. ": the finale robot is on the list"
					)
					local split = 0
					for i, step in S.steps do
						if SideQuestPlan.shared(step) then
							local sg = SideQuestPlan.goal(step, "hero") :: any
							check(
								type(sg.villainText) == "string" and sg.villainText ~= sg.text,
								L.id .. " step " .. i .. ": the Syndicate reads its own goal"
							)
						else
							split += 1
							check(
								SideQuestPlan.text(SideQuestPlan.goal(step, "hero"), "hero")
									~= SideQuestPlan.text(SideQuestPlan.goal(step, "villain"), "villain"),
								L.id .. " step " .. i .. ": each side's own job"
							)
						end
					end
					check(split >= 3, L.id .. ": most steps give each side its own job (" .. split .. ")")
					check(
						SideQuestPlan.goal(S.steps[1], "hero").kind == "talk",
						L.id .. ": the giver's story first"
					)
					-- existing robot types only (Enemy.Delta's typeId has 5 bits, all used)
					for _, kind in robots(S) do
						local cfg = Config.Enemies[kind]
						check(
							cfg ~= nil and cfg.typeId ~= nil,
							L.id .. ": " .. kind .. " is an existing robot type"
						)
					end
					-- who speaks: the giver, the guides and the line's own people, each drawn
					local who = {}
					for _, step in S.steps do
						for _, l in step.lines or {} do
							who[l.who] = true
							check(
								Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
								L.id .. ": speaker " .. tostring(l.who)
							)
						end
					end
					for _, w in L.speakers do
						check(who[w] == true, L.id .. " speaks: " .. w)
						local sp = Config.Story.guides.speakers[w] or SQ.givers[w]
						check(
							sp ~= nil and sp.portrait ~= nil and Config.Audio.sounds[sp.blip] ~= nil,
							w .. ": a portrait and a blip"
						)
						for _, e in (sp and sp.portrait.extras) or {} do
							check(
								string.find(guide, '"' .. e .. '"', 1, true) ~= nil,
								w .. ": GuideHud draws " .. e
							)
						end
					end
					-- the shared Spark lore: the line's truth step tells both sides their origin only woke the Spark
					local truth = S.steps[#S.steps - 1]
					for _, side in SIDES do
						local told = false
						for _, l in truth.lines or {} do
							local t = l.text or l[side]
							if
								type(t) == "string"
								and string.find(t, "Spark", 1, true)
								and string.find(t, "w[oa]ke")
							then
								told = true
							end
						end
						check(told, L.id .. " " .. side .. ": the origin only woke the Spark")
					end
				end
			end
			for i = 1, 5 do -- origins 6 to 10 (2026-11-18) have no quest line yet
				check(origins[i] == 1, "one line for origin " .. i)
			end
		end
	)

	test(
		"Lore 11 Origins: each line is offered only to its own origin, after the Safehouse; hidden from the rest",
		function()
			local J = fs.readFile("src/client/Ui/Journal.luau")
			check(string.find(J, "RadioHill = ", 1, true) ~= nil, "the Journal names Radio Hill's district")
			for _, L in LINES do
				local S = SideQuestPlan.chain(Config, L.id) :: any
				for _, side in SIDES do
					for o = 1, #Config.Creator.origins do
						local c = hero(o, true)
						local st, why, n = SideQuestPlan.state(Config, c, S, 30, side)
						local rows = SideQuestPlan.journal(Config, c, 30, side, false)
						local listed = false
						for _, r in rows do
							listed = listed or r.bit == S.bit
						end
						local pick, kind = SideQuestPlan.talkPick(Config, c, L.giver, 30, side, false)
						if o == L.origin then
							check(st == "open", L.id .. " " .. side .. ": open to its origin")
							check(listed, L.id .. " " .. side .. ": in its origin's Journal")
							check(
								pick == S and kind == "offer",
								L.id .. " " .. side .. ": " .. L.giver .. " offers it"
							)
							check(SideQuestPlan.accept(Config, c, S, 30, side, false), L.id .. ": taken")
						else
							check(
								st == "locked" and why == "origin" and n == L.origin,
								L.id .. " origin " .. o .. ": locked"
							)
							check(not listed, L.id .. " origin " .. o .. ": hidden from the Journal")
							check(
								kind == "none",
								L.id .. " origin " .. o .. ": " .. L.giver .. " has nothing"
							)
							check(
								not SideQuestPlan.accept(Config, c, S, 30, side, true),
								L.id .. " origin " .. o .. ": refused"
							)
						end
					end
					local early = hero(L.origin, false)
					local st, why = SideQuestPlan.state(Config, early, S, 30, side)
					check(
						st == "locked" and why == "story",
						L.id .. " " .. side .. ": waits for the Safehouse"
					)
					local st2, why2 =
						SideQuestPlan.state(Config, hero(L.origin, true), S, S.unlock.level - 1, side)
					check(st2 == "locked" and why2 == "level", L.id .. " " .. side .. ": and its level")
					check(
						SideQuestPlan.fixedText(S.blurb[side], 90) == nil,
						L.id .. " " .. side .. ": the page's line"
					)
					for _, k in { "offer", "resume", "done" } do
						check(
							SideQuestPlan.fixedText(S.lines[k][side], 120) == nil,
							L.id .. " " .. side .. ": " .. k
						)
					end
				end
			end
		end
	)

	test("Lore 11 Origins: every side quest done asks for the hero's own origin line only", function()
		local Bits = ProfileSchema.Bits
		for _, L in LINES do
			local c = hero(L.origin, true)
			c.side = "hero"
			local sq = SideQuestPlan.save(c)
			for _, chain in SQ.chains do
				local u = chain.unlock or {}
				if not chain.dev and (not u.side or u.side == c.side) and chain.layer ~= "origin" then
					Bits.set(sq.done, chain.bit, true)
				end
			end
			check(not SideQuestPlan.allDone(Config, c), L.id .. ": not done without its own line")
			Bits.set(sq.done, L.bit, true)
			check(SideQuestPlan.allDone(Config, c), L.id .. ": done with its own line, no other origin's")
		end
	end)

	test("Lore 11 Origins: each finale's name card on the last step only", function()
		for _, L in LINES do
			local S = SideQuestPlan.chain(Config, L.id) :: any
			for i = 1, #S.steps - 1 do
				check(SideQuestPlan.card(S, i) == nil, L.id .. ": no card on step " .. i)
			end
			local card = SideQuestPlan.card(S, #S.steps) :: any
			check(
				card ~= nil and card.name == L.card[1] and card.title == L.card[2],
				L.id .. ": " .. L.card[1]
			)
			check(
				card
					and SideQuestPlan.fixedText(card.name, 32) == nil
					and SideQuestPlan.fixedText(card.title, 32) == nil,
				L.id .. ": fixed text that fits the card"
			)
		end
	end)

	test(
		"Lore 11 Origins: the sites: a Downtown lab, an Old Town shop, Radio Hill's terrace, two Suburbs lots",
		function()
			local gy = Config.City.ground.y
			-- the Ashgrove lab: an existing Downtown building, clear of the other chains' buildings and courses
			local lab = SideQuestSites.building(Config, world, "Underlab") :: any
			local dd = Config.City.districts.Downtown
			check(
				lab ~= nil and lab.x > dd.minX and lab.x < dd.maxX and lab.z > dd.minZ and lab.z < dd.maxZ,
				"the lab is a Downtown building"
			)
			local h = lab.h
			check(h >= SQ.sites.Underlab.height[1] and h <= SQ.sites.Underlab.height[2], "a research block")
			for cid, crs in SQ.courses do
				if type(crs) == "table" then
					for _, r in SideQuestSites.course(Config, world, cid) or {} do
						check(r.id ~= lab.id, "the lab's roof is no " .. cid .. " checkpoint")
					end
				end
			end
			-- the curio shop: an Old Town building (the character lines' rule), its door on an open street
			local shop = SideQuestSites.building(Config, world, "VintageCurios") :: any
			check(shop ~= nil and shop.district == "OldTown", "the curio shop is an Old Town building")
			local sh = shop.top - shop.base
			check(
				sh >= SQ.sites.VintageCurios.height[1] and sh <= SQ.sites.VintageCurios.height[2],
				"a shop front"
			)
			local _, sdoor = SideQuestSites.place(Config, world, "VintageCurios")
			check(sdoor ~= nil, "an open door")
			if sdoor then
				check(
					WorldMap.heightAt(world, sdoor.x + sdoor.fx * 8, sdoor.z + sdoor.fz * 8) <= gy + 1.5,
					"on the street"
				)
			end
			-- Radio Hill's terrace: the hand-placed hill, on its first step and facing town, the same every week
			local hill = SideQuestSites.hill(Config, world, "RadioMast") :: any
			local steps, mid = SideQuestSites.hillSteps(Config)
			check(hill ~= nil and steps ~= nil and #steps >= 2, "Radio Hill's steps")
			if hill and steps and mid then
				local s1, s2 = steps[1], steps[2]
				check(
					math.abs(hill.x - s1.cx) < s1.sx / 2 and math.abs(hill.z - s1.cz) < s1.sz / 2,
					"on the hill"
				)
				check(math.abs(hill.x - s2.cx) > s2.sx / 2, "on the first terrace, off the second step")
				near(hill.top, s1.cy + s1.sy / 2, 0.01, "standing on the terrace")
				check(hill.top > gy + 5, "up off the ground")
				check(hill.door.fx == 1 and hill.door.fz == 0, "facing east, toward the city")
				near(hill.door.y, hill.top, 0.01, "the sign stands on the terrace")
				for _, seed in { 202648, 202720 } do
					local wd = WorldMap.build(Config, seed)
					local again = SideQuestSites.place(Config, wd, "RadioMast")
					check(
						again ~= nil and again.x == hill.x and again.z == hill.z,
						"the same spot in week " .. seed
					)
				end
				check(SideQuestSites.building(Config, world, "RadioMast") == nil, "never a city building")
			end
			-- every week: each origin site stands apart from every other chain's site, and nothing else moves
			local sites = {}
			for id, st in SQ.sites do
				if not MINE[id] then
					sites[id] = st
				end
			end
			local Old = setmetatable(
				{ SideQuests = setmetatable({ sites = sites }, { __index = SQ }) },
				{ __index = Config }
			)
			for _, seed in { 202647, 202701, 202752 } do
				local w1 = if seed == 202647 then world else WorldMap.build(Config, seed)
				local w2 = WorldMap.build(Config, seed)
				SideQuestSites.warm(Config, w1)
				SideQuestSites.warm(Old, w2)
				for id in sites do
					local a = SideQuestSites.place(Config, w1, id)
					local b = SideQuestSites.place(Old, w2, id)
					check(
						(a == nil) == (b == nil) and (a == nil or (a.x == b.x and a.z == b.z)),
						seed .. ": " .. id .. " stays where it was"
					)
				end
				for cid, crs in SQ.courses do
					if type(crs) == "table" then
						local a = SideQuestSites.course(Config, w1, cid) or {}
						local b = SideQuestSites.course(Old, w2, cid) or {}
						local same = #a == #b
						for i = 1, math.min(#a, #b) do
							same = same and a[i].id == b[i].id
						end
						check(same, seed .. ": the " .. cid .. " course is unchanged")
					end
				end
				for id in MINE do
					local a = SideQuestSites.place(Config, w1, id)
					check(a ~= nil, seed .. ": " .. id .. " is placed")
					if a then
						for oid, ost in SQ.sites do
							if oid ~= id and not ost.dev and not SideQuestSites.isDeep(ost) then
								local b = SideQuestSites.place(Config, w1, oid)
								if b then
									local gap =
										math.max(250, (SQ.sites[id].away and SQ.sites[id].away.site) or 0)
									if
										not SideQuestSites.isBuilding(SQ.sites[id])
										or not SideQuestSites.isBuilding(ost)
									then
										gap = 250
									end
									check(
										flat(a.x, a.z, b.x, b.z) >= gap,
										seed .. ": " .. id .. " is far from " .. oid
									)
								end
							end
						end
					end
				end
			end
			-- the framework checks the new site rules
			check(problems(function() end) == "", "the copy is clean")
			check(string.find(
				problems(function(q)
					q.sites.RadioMast.hill = "summit"
				end),
				"RadioMast",
				1,
				true
			) ~= nil, "only a known hill spot")
			check(string.find(
				problems(function(q)
					q.sites.RadioMast.district = "Suburbs"
				end),
				"RadioMast",
				1,
				true
			) ~= nil, "a hill site is on Radio Hill")
			check(string.find(
				problems(function(q)
					q.sites.VintageCurios.away.door = nil
				end),
				"VintageCurios: away.door",
				1,
				true
			) ~= nil, "an Old Town site keeps off the HQ doors")
			check(string.find(
				problems(function(q)
					q.sites.Underlab.away.site = "far"
				end),
				"Underlab",
				1,
				true
			) ~= nil, "away.site is a number")
		end
	)

	test(
		"Lore 11 Origins: the lab and the Iron Hall: rooms, a middle hold, stairs down, four targets, a boss",
		function()
			local src = fs.readFile("src/shared/PocketLayout.luau")
			check(string.find(src, "PLACEHOLDER ART", 1, true) ~= nil, "greybox marked placeholder art")
			for _, L in LINES do
				if L.pocket then
					local S = SideQuestPlan.chain(Config, L.id) :: any
					check(PocketLayout.known(L.pocket), L.pocket .. ": a pocket layout")
					local l = PocketLayout.build(Config, 1, L.pocket)
					check(#l.boxes < 400, L.pocket .. ": under 400 parts (" .. #l.boxes .. ")")
					local sp = l.points.spawn
					check(
						PocketLayout.at(Config, sp[1], sp[2], sp[3]) == 1,
						L.pocket .. ": the spawn is inside"
					)
					local deck = PocketLayout.heightAt(l, sp[1], sp[3])
					check(deck > l.floorY + 15, L.pocket .. ": the deck stands over the lower floor")
					check(#(l.lists.rooms or {}) >= 1, L.pocket .. ": a room")
					for i, r in l.lists.rooms do
						near(
							PocketLayout.heightAt(l, r[1], r[3]),
							deck,
							0.5,
							L.pocket .. ": room " .. i .. " on the deck"
						)
					end
					local pocket = nil
					for _, step in S.steps do
						local g = SideQuestPlan.goal(step, "hero") :: any
						if g.kind == "pocket" then
							pocket = g
						end
					end
					check(pocket ~= nil and pocket.layout == L.pocket, L.id .. ": goes inside " .. L.pocket)
					local used = {}
					local foot = nil
					for _, s in (pocket and pocket.steps) or {} do
						used[s.kind] = true
						if s.at then
							check(l.points[s.at] ~= nil, L.pocket .. ": " .. s.kind .. " at " .. s.at)
							if s.kind == "reach" then
								foot = l.points[s.at]
							elseif s.kind == "hold" then
								local p = l.points[s.at]
								near(
									PocketLayout.heightAt(l, p[1], p[3]),
									deck,
									0.5,
									L.pocket .. ": the hold is on the deck"
								)
							end
						end
						if s.room then
							check(
								l.lists.rooms[s.room] ~= nil,
								L.pocket .. ": " .. s.kind .. " in room " .. s.room
							)
						end
						if s.list then
							check(
								#(l.lists[s.list] or {}) >= (s.points or 1),
								L.pocket .. ": " .. s.kind .. " on " .. s.list
							)
							for i, p in l.lists[s.list] or {} do
								check(
									PocketLayout.heightAt(l, p[1], p[3]) < l.floorY + 2,
									L.pocket .. ": target " .. i .. " is on the lower floor"
								)
							end
						end
					end
					check(
						used.defeat and used.hold and used.reach and used["break"] and used.boss,
						L.pocket .. ": a room, a hold, the stairs, the targets, the boss"
					)
					local boss = l.points.boss
					check(
						boss ~= nil and PocketLayout.heightAt(l, boss[1], boss[3]) < l.floorY + 2,
						"the boss waits below"
					)
					-- the stairs walk down from the back wall's gap to the lower floor, never a drop over 2.5 studs
					check(foot ~= nil, L.pocket .. ": the stairs' foot")
					if foot then
						local gp = l.points[L.gap]
						local prev = PocketLayout.heightAt(l, gp[1], gp[3])
						near(prev, deck, 0.5, L.pocket .. ": the way down starts on the deck")
						local ok = true
						for z = gp[3], foot[3], -1 do
							local hz = PocketLayout.heightAt(l, gp[1], z)
							if hz > prev + 1e-6 or prev - hz > 2.5 then
								ok = false
							end
							prev = hz
						end
						check(
							ok and prev < l.floorY + 1,
							L.pocket .. ": the steps walk down to the lower floor"
						)
					end
				end
			end
		end
	)

	test(
		"Lore 11 Origins: each villain is a dress over an existing suit or robot: no new robot type",
		function()
			local profile = ProfileSchema.default()
			for _, p in CreatorRules.index(Config).list do
				if p.source.kind ~= "pack" and p.source.kind ~= "starter" then
					CreatorRules.grant(profile, p)
				end
			end
			local function lookOk(look: any, label: string)
				local ok, why = CreatorRules.validate(Config, profile, look)
				check(ok, label .. "'s look validates (" .. tostring(why) .. ")")
				for slot, i in look.pieces do
					if i > 0 then
						local p = CreatorRules.piece(Config, slot, i)
						check(
							p ~= nil and p.source.kind ~= "pack",
							label .. " " .. slot .. " is never a Robux piece"
						)
					end
				end
			end
			local elite, boss = {}, {}
			for _, lv in { 12, 20, 50 } do
				elite[lv], boss[lv] = 0, 0
				for _, kind in Config.Enemies.order do
					local cfg = Config.Enemies[kind]
					if cfg.elite and not cfg.fake then
						elite[lv] = math.max(elite[lv], robotDps(kind, lv))
					end
				end
				for id in Config.Boss.bosses do
					boss[lv] = math.max(boss[lv], bossDps(id, lv))
				end
			end
			for _, L in LINES do
				local S = SideQuestPlan.chain(Config, L.id) :: any
				lookOk(FakeRules.lookFrom(Config, SQ.givers[L.giver].look, L.giver), L.giver)
				local fin = SideQuestPlan.goal(S.steps[#S.steps], "hero") :: any
				local suit = Config.Enemies[fin.enemy]
				local D = SQ.dress[L.dress]
				check(suit ~= nil and suit.on ~= false, L.dress .. ": an existing robot, switched on")
				check(Config.Enemies[L.dress] == nil, L.dress .. ": no robot type of its own")
				if D.robot then
					check(suit.fake == nil, L.dress .. ": over a plain robot")
					check(
						table.find(ProfileSchema.PATHS, D.path) ~= nil,
						L.dress .. ": drawn in a power path's look"
					)
					for _, lv in { 12, 20, 50 } do
						local d = robotDps(fin.enemy, lv) * (D.dmgMult or 1)
						check(
							d > elite[lv] and d < boss[lv],
							string.format(
								"L%d %s %.1f between elite %.1f and boss %.1f",
								lv,
								L.dress,
								d,
								elite[lv],
								boss[lv]
							)
						)
					end
				else
					check(
						suit.fake and suit.fake.costumed == true,
						L.dress .. ": over a costumed villain's suit"
					)
				end
				local hp = suit.hp * fin.hpMult
				check(
					hp >= Config.Enemies.CaptainBrine.hp * 2 and hp <= Config.Enemies.CaptainBrine.hp * 4,
					L.dress .. ": boss-lite health (" .. hp .. ")"
				)
				local d = FakeRules.dress(Config, L.dress) :: any
				check(d ~= nil and d.dress == true and d.creature == false, L.dress .. ": a machine dress")
				local look = d and LookCodec.read(d.words)
				check(look ~= nil, L.dress .. ": its look goes over the wire")
				if look then
					lookOk(look, L.dress)
					check(
						Config.Enemies.look.builds[suit.body.build] == look.build,
						L.dress .. ": the frame's build"
					)
				end
				for _, k in FakeRules.DRESS_BODY do
					check(type(D.body[k]) == "table" and #D.body[k] == 3, L.dress .. ": body colour " .. k)
				end
				local plate = FakeRules.plate(Config, fin.enemy, false, d)
				check(plate.name == L.card[1] and plate.sub == D.title, L.dress .. ": his own name plate")
			end
			local ids = {}
			for _, kind in Config.Enemies.order do
				local cfg = Config.Enemies[kind]
				if cfg and cfg.typeId then
					check(cfg.typeId >= 1 and cfg.typeId < 32, kind .. ": typeId fits 5 bits")
					check(not ids[cfg.typeId], "typeId " .. cfg.typeId .. " used once (" .. kind .. ")")
					ids[cfg.typeId] = true
				end
			end
			local svc = fs.readFile("src/server/Services/SideQuestService.luau")
			for _, L in LINES do
				check(
					string.find(svc, L.id, 1, true) == nil,
					L.id .. ": nothing chain-specific in the service"
				)
				check(
					string.find(svc, L.dress, 1, true) == nil,
					L.dress .. ": nothing chain-specific in the service"
				)
			end
		end
	)

	test(
		"Lore 11 Origins: two short scenes a line: the truth as a comic page ending on the one Spark, the finale",
		function()
			local hud = fs.readFile("src/client/Ui/CinemaHud.luau")
			local wb = Config.Cinema.wideBits
			local seenBits = {}
			for id, s in Config.Cinema.scenes do
				check(not seenBits[s.bit], "scene bit " .. s.bit .. " used once (" .. id .. ")")
				seenBits[s.bit] = true
			end
			for _, L in LINES do
				local S = SideQuestPlan.chain(Config, L.id) :: any
				local mine = {}
				for _, step in S.steps do
					if step.scene then
						local s = Config.Cinema.scenes[step.scene]
						check(s ~= nil and s.client == true, step.scene .. ": a device scene")
						check(s and CinemaPlan.check(Config, s), step.scene .. ": 5 to 20 s")
						check(
							s and s.bit >= wb.from and s.bit <= wb.to and CinemaPlan.clientBit(Config, s.bit),
							step.scene .. ": a scene bit a device may send"
						)
						if s then
							table.insert(mine, s.bit)
						end
						for _, l in (s and s.lines) or {} do
							check(
								Config.Story.guides.speakers[l.who] ~= nil or SQ.givers[l.who] ~= nil,
								step.scene .. ": speaker " .. tostring(l.who)
							)
							check(SideQuestPlan.fixedText(l.text, 120) == nil, step.scene .. ": a short line")
						end
					end
				end
				table.sort(mine)
				check(
					#mine == 2 and mine[1] == L.bits[1] and mine[2] == L.bits[2],
					L.id .. ": its scene bits"
				)
				check(S.steps[#S.steps].scene == L.finale, L.id .. ": a scene before the finale")
				check(S.steps[#S.steps - 1].scene == L.comic, L.id .. ": the truth as a comic page")
				local page = Config.Cinema.comic.pages[L.comic]
				check(page ~= nil and #page.panels == 4, L.comic .. ": a 4-panel page")
				check(Config.Cinema.scenes[L.comic].comic == L.comic, L.comic .. ": the scene shows it")
				for _, p in (page and page.panels) or {} do
					check(SideQuestPlan.fixedText(p.caption, 90) == nil, L.comic .. ": a short caption")
					check(
						string.find(hud, 'kind == "' .. p.scene .. '"', 1, true) ~= nil,
						"the comic draws " .. p.scene
					)
				end
				local lastPanel = page and page.panels[4]
				check(
					lastPanel
						and lastPanel.scene == "spark"
						and string.find(lastPanel.caption, "Spark", 1, true) ~= nil,
					L.comic .. ": ends on the one Spark"
				)
			end
		end
	)

	for _, L in LINES do
		for _, lead in SIDES do
			local mate = if lead == "hero" then "villain" else "hero"
			local label = if lead == "villain" then "the Syndicate" else "the Vigil"
			test(
				"Lore 11 Origins: " .. L.id .. " as " .. label .. ": every step co-op with the other side",
				function()
					local S = SideQuestPlan.chain(Config, L.id) :: any
					local a, b = hero(L.origin, true), hero(L.origin, true)
					check(
						SideQuestPlan.accept(Config, a, S, 22, lead, false),
						"the lead takes it from " .. L.giver
					)
					check(
						SideQuestPlan.accept(Config, b, S, 22, mate, true),
						"the squadmate from the Journal"
					)
					for i, step in S.steps do
						check(
							SideQuestPlan.stepOf(a, S) == i and SideQuestPlan.stepOf(b, S) == i,
							"both on step " .. i
						)
						local g = SideQuestPlan.newGroup(S.id, i)
						local ka, newA = SideQuestPlan.join(g, step, "lead", lead)
						local kb, newB = SideQuestPlan.join(g, step, "mate", mate)
						if SideQuestPlan.shared(step) then
							check(
								ka == "both" and kb == "both" and newA and not newB,
								"step " .. i .. ": one shared goal"
							)
						else
							check(
								ka == lead and kb == mate and newA and newB,
								"step " .. i .. ": a goal per side"
							)
						end
						check(
							SideQuestPlan.set(g, ka, g.sides[ka].need),
							"step " .. i .. ": the lead's side finishes"
						)
						if ka ~= kb then
							check(
								SideQuestPlan.waiting(g, ka) and not SideQuestPlan.groupDone(g),
								"step " .. i .. ": and waits for the other side"
							)
							check(
								SideQuestPlan.set(g, kb, g.sides[kb].need),
								"step " .. i .. ": the other side finishes"
							)
						end
						check(SideQuestPlan.groupDone(g), "step " .. i .. ": done for the group")
						local last = i == #S.steps
						if last then
							check(SideQuestPlan.card(S, i) ~= nil, "the villain's name card at the finale")
						end
						for _, c in { a, b } do
							check(
								SideQuestPlan.advance(c, S) == (if last then "done" else "next"),
								"step " .. i .. " moves on"
							)
						end
					end
					for n, c in { a, b } do
						check(SideQuestPlan.isDone(c, S) and c.sq.at[S.id] == nil, "done, untracked")
						check(SideQuestPlan.chainPay(Config, S, 22) > 0, "the end pays")
						check(
							not SideQuestPlan.accept(Config, c, S, 22, if n == 1 then lead else mate, false),
							"once only"
						)
					end
				end
			)
		end
	end

	test(
		"Lore 11 Origins: the rewards: a chain title and one Story style each; nothing that changes stats",
		function()
			local tb = {}
			for name, tbit in Config.Story.unlocks.titles do
				check(not tb[tbit], "title bit " .. tbit .. " used once (" .. name .. ")")
				tb[tbit] = true
			end
			for _, slot in Config.Gear.slotOrder do
				local ns = {}
				for _, row in Config.Gear.styles[slot] do
					check(not ns[row.n], slot .. " style n " .. row.n .. " used once")
					ns[row.n] = true
					check(
						row.n <= Config.Gear.setStyleBase
							or row.n > Config.Gear.setStyleBase + #Config.Gear.setOrder,
						slot .. " style n " .. row.n .. " is not a set's"
					)
					check(
						row.n ~= Config.Gear.legendaryStyleN,
						slot .. " style n " .. row.n .. " is not the Legendary's"
					)
				end
			end
			for _, L in LINES do
				local S = SideQuestPlan.chain(Config, L.id) :: any
				local cos = SideQuestPlan.cosmetic(S)
				local n = 0
				for _ in cos do
					n += 1
				end
				check(
					n == 2 and cos.title == L.title and cos.style == L.style,
					L.id .. ": a title and a style"
				)
				check(
					Config.Story.unlocks.titles[L.title] == L.titleBit,
					L.id .. ": title bit " .. L.titleBit
				)
				check(SideQuestPlan.fixedText(L.title, 32) == nil, L.id .. ": a short title")
				check(GearMath.questStyle(Config, L.style) ~= nil, L.style .. ": a gear style")
				local styles = 0
				for _, slot in Config.Gear.slotOrder do
					for _, row in Config.Gear.styles[slot] do
						if row.quest == L.style then
							styles += 1
							check(
								row.tier == "Story" and row.price == nil,
								L.style .. ": never rolled, never sold"
							)
						end
					end
				end
				check(styles == 1, L.style .. ": one style")
				for _, k in { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" } do
					check(S.reward[k] == nil, L.id .. ": no " .. k)
				end
			end
		end
	)

	test(
		"Lore 11 Origins: no old names, main-story names or other games' names; the Dev panel covers them",
		function()
			local ARC =
				{ "Bellweather", "Mayor", "Pip", "Maribel", "Tamsin", "Quill", "Iron Dee", "IronDee", "Skye" }
			local OTHER =
				{ "Crane", "Halcyon", "Adrian Vale", "Null", "Marlo", "Sprocket", "Mossbell", "Ragdoll" }
			local hits = {}
			local function walk(v: any, path: string)
				if type(v) == "string" then
					local w = oldLore(v)
					if w then
						table.insert(hits, path .. ": " .. w)
					end
					for _, list in { ARC, OTHER } do
						for _, a in list do
							if string.find(v, "%f[%w]" .. a .. "%f[%W]") then
								table.insert(hits, path .. ": " .. a)
							end
						end
					end
				elseif type(v) == "table" then
					for k, x in v do
						walk(x, path .. "." .. tostring(k))
					end
				end
			end
			local dev = fs.readFile("src/client/Ui/DevPanel.luau")
			check(
				string.find(dev, "if not ch.dev then", 1, true) ~= nil,
				"every real chain is on the SQ chain button"
			)
			for _, L in LINES do
				local S = SideQuestPlan.chain(Config, L.id) :: any
				walk(S, L.id)
				walk(SQ.givers[L.giver], L.giver)
				walk(SQ.dress[L.dress], L.dress)
				walk(SQ.sites[L.site], L.site)
				for _, w in L.speakers do
					walk(Config.Story.guides.speakers[w], w)
				end
				walk(Config.Cinema.scenes[L.comic], L.comic)
				walk(Config.Cinema.scenes[L.finale], L.finale)
				walk(Config.Cinema.comic.pages[L.comic], L.comic .. " page")
				local idx = table.find(SQ.chains, S) :: number
				check(
					idx ~= nil and 300 + idx <= 1000,
					L.id .. ": the Dev panel's SQ chain button reaches it"
				)
				check(#S.steps <= SQ.maxSteps, L.id .. ": every step fits SQ: start step")
			end
			for _, h in hits do
				check(false, "an old name: " .. h)
			end
			check(#hits == 0, "no old lore, retired arc names, main-story names or other games' names")
		end
	)
end

---------------------------------------------------------------------------
-- Story fixes (2026-11-18): task force legs one at a time, full servers in missions, the last task force
-- member home, the prologue's seen ceremony and timeout, squadmates, party levels, newer saves.
-- The services' wiring is on the Studio list ("Story fixes").
---------------------------------------------------------------------------

do
	local MissionRules = require("../src/shared/MissionRules")
	local SidekickRules = require("../src/shared/SidekickRules")

	test("Story fixes: a run with no tracks, or a task force panel up, never moves on", function()
		check(not MissionRules.advance({}, nil), "no tracks (the fade in, between legs) is waiting")
		check(not MissionRules.advance({ both = { done = true } }, true), "never while the panel is up")
		check(MissionRules.advance({ both = { done = true } }, nil), "every track done: the next stage")
		check(
			not MissionRules.advance({ hero = { done = true }, villain = { done = false } }, nil),
			"a side still on its step holds the stage"
		)
		-- the old bug: a 3-leg task force at 10 Hz through its 4 s panels. Model the loop: a panel leaves no
		-- tracks; each advance past the last stage pays a leg.
		local legs, paid, leg, stage, stages = 3, 0, 1, 1, 2
		local tracks: { [string]: { done: boolean } } = { both = { done = true } }
		local panel, panelUntil = false, 0
		for tick = 1, 200 do -- 20 s
			local now = tick * 0.1
			if panel and now >= panelUntil then
				panel, stage, tracks = false, 1, { both = { done = true } }
			end
			if MissionRules.advance(tracks, panel) then
				stage += 1
				tracks = { both = { done = true } }
				if stage > stages then
					paid += 1
					tracks = {}
					if leg < legs then
						leg += 1
						panel, panelUntil = true, now + Config.TaskForce.panelTime
					end
				end
			end
		end
		check(paid == legs and leg == legs, "each leg paid once, in order (got " .. paid .. " pays)")
	end)

	test("Story fixes: a full server makes a boss, chase or defeat step wait, never skip", function()
		local sim = EnemySim.new(Config, {})
		for _ = 1, Config.Enemies.caps.perServer do
			EnemySim.spawn(sim, "NullSentinel", 0, 0, 0, 10)
		end
		local e = EnemySim.spawn(sim, "NullSentinel", 0, 0, 0, 10)
		check(e == nil, "the cap builds no more robots")
		local on = EnemySim.enabled(Config, "NullSentinel")
		check(on and MissionRules.afterSpawn(0, on) == "wait", "an enabled type at the cap waits and retries")
		check(MissionRules.afterSpawn(1, on) == "go", "a boss that came: fight it")
		check(MissionRules.afterSpawn(3, on) == "go", "a defeat step fights the 3 that came")
		local off = { Enemies = { Cut = { on = false } } }
		check(
			MissionRules.afterSpawn(0, EnemySim.enabled(off, "Cut")) == "skip",
			"a switched-off type lets the story move on"
		)
		local svc = readFile("src/server/Services/MissionService.luau")
		for _, needle in
			{
				"MissionRules.afterSpawn(got, enabled)",
				"track.need = got",
				"robots(run, track) -- a full server",
				"MissionRules.advance(run.tracks, run.panel)",
				"run.panel = true",
			}
		do
			check(string.find(svc, needle, 1, true) ~= nil, "MissionService: " .. needle)
		end
	end)

	test("Story fixes: the last task force member goes home before the pocket goes", function()
		local svc = readFile("src/server/Services/MissionService.luau")
		local a = string.find(svc, "function MissionService.leaveTaskForce", 1, true) :: number
		local b = string.find(svc, "function MissionService.leave(", a, true) :: number
		local body = string.sub(svc, a, b)
		local last = string.find(body, "#run.members <= 1", 1, true) :: number
		local fin = string.find(body, "finishRun(run, false)", last, true) :: number
		check(last ~= nil and fin ~= nil, "the last member ends the run")
		check(
			string.find(string.sub(body, last, fin), "releaseMember", 1, true) == nil,
			"still a member when finishRun sends everyone home"
		)
	end)

	test(
		"Story fixes: squadmates come only loaded, standing and free; pay counts members still in",
		function()
			local ok = { loaded = true, alive = true }
			check(MissionRules.canJoin(ok, false, false, false), "a free hero comes")
			check(not MissionRules.canJoin({ alive = true }, false, false, false), "not loaded")
			check(
				not MissionRules.canJoin({ loaded = true, alive = false, downed = true }, false, false, false),
				"Downed"
			)
			check(
				not MissionRules.canJoin(
					{ loaded = true, alive = true, scene = "opening" },
					false,
					false,
					false
				),
				"a scene"
			)
			check(
				not MissionRules.canJoin(
					{ loaded = true, alive = true, traveling = true },
					false,
					false,
					false
				),
				"a trip"
			)
			check(not MissionRules.canJoin(ok, true, false, false), "another run")
			check(not MissionRules.canJoin(ok, false, true, false), "in combat")
			check(not MissionRules.canJoin(ok, false, false, true), "a beacon trip")
			local a, b, gone = {}, {}, {}
			local levels = { [a] = 20, [b] = 18, [gone] = 40 }
			local list = MissionRules.partyLevels({ a, b }, levels)
			check(#list == 2 and table.find(list, 40) == nil, "a member who left is not counted")
			local multIn = SidekickRules.renown(Config.Sidekick, 20, list)
			local multOld = SidekickRules.renown(Config.Sidekick, 20, { 20, 18, 40 })
			check(
				multIn == 1 and multOld > 1,
				"so the top member is no longer paid as a sidekick of someone gone"
			)
		end
	)

	test("Story fixes: the ceremony is seen only once it ends; the timeout starts at PLAY", function()
		check(
			not MissionRules.markSeen("ceremony", "ceremony", true, false),
			"starting the ceremony is not seeing it"
		)
		check(MissionRules.markSeen("ceremony", "scan", true, false), "moving off it is")
		check(not MissionRules.markSeen("ceremony", "scan", true, true), "never while the main menu holds it")
		check(not MissionRules.markSeen("run", "spark", false, false), "only camera beats")
		local src = readFile("src/server/Services/OpeningService.luau")
		local a = string.find(src, "act == 4 and r.hold", 1, true) :: number
		local b = string.find(src, "local function maybeStart", a, true) :: number
		check(
			string.find(string.sub(src, a, b), "r.startedAt = r.stepAt", 1, true) ~= nil,
			"PLAY THE PROLOGUE restarts the 330 s clock"
		)
		check(
			string.find(src, 'hero.scene = "opening"\n\thero.floor = FLOOR', 1, true) ~= nil,
			"the prologue's floor from its first beat"
		)
	end)

	test("Story fixes: a save from a newer version keeps its version", function()
		local newer = ProfileSchema.load({ version = ProfileSchema.VERSION + 1 })
		check(newer.version == ProfileSchema.VERSION + 1, "a rollback never writes an older version on it")
		local old = ProfileSchema.load({ version = ProfileSchema.VERSION - 1 })
		check(old.version == ProfileSchema.VERSION, "an older save still migrates up")
		check(ProfileSchema.load({}).version == ProfileSchema.VERSION, "no version migrates from 0")
	end)
end

-- The side quests' people and finale models (2026-11-18 art pass): every giver, named helper and finale villain
-- has an outfit row, the drawn images are there to upload, and the finale models' config is sound
do
	local PeopleLooks = require("../src/shared/PeopleLooks")
	local fs = require("@lune/fs")
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local NL = Config.NpcLooks
	local SQ = Config.SideQuests

	test("Art pass: the people and helper tables are sound", function()
		local problems = PeopleLooks.problems(Config)
		check(#problems == 0, "PeopleLooks problems: " .. table.concat(problems, "; "))
		for id, g in SQ.givers do
			if not g.dev and not g.relay and id ~= "LodestarGiver" then
				check(NL.people[id] ~= nil, "giver " .. id .. " has an outfit row")
			end
		end
		local villains = 0
		for _, ch in SQ.chains do
			for _, step in ch.steps do
				for _, side in { "hero", "villain" } do
					local g = SideQuestPlan.goal(step, side)
					if g and g.kind == "finale" then
						for phase = 1, 2 do
							local foe = SideQuestPlan.finaleFoe(g, phase)
							local who = PeopleLooks.villain(foe.dress, foe.enemy) :: string
							villains += 1
							check(
								NL.people[who] ~= nil or (NL.robots and NL.robots[who] ~= nil),
								ch.id .. "'s finale villain " .. who .. " has an outfit row"
							)
						end
					end
				end
			end
		end
		check(villains >= 32, "every chain's finale was checked")
	end)

	test("Art pass: uploaded outfits show, and strip only the drawn slots", function()
		-- every outfit is uploaded (2026-11-18, Open Cloud): each person wears its drawn suit
		for id in NL.people do
			local fit = PeopleLooks.outfit(Config, id) :: any
			check(
				fit ~= nil and string.find(fit.clothes or "", "^rbxassetid://%d+$") ~= nil,
				id .. " wears its uploaded outfit"
			)
		end
		check(
			PeopleLooks.outfit(Config, "Nobody") == nil and PeopleLooks.outfit(Config, nil) == nil,
			"unknown ids"
		)
		local patched = { NpcLooks = { people = { Vesper = { clothes = 123, face = 0, cracked = 456 } } } }
		local fit = PeopleLooks.outfit(patched, "Vesper") :: any
		check(fit.clothes == "rbxassetid://123" and fit.face == nil, "an uploaded outfit's image")
		check(fit.cracked == "rbxassetid://456", "a famous fake's cracked face")
		local look = { pieces = { suit = 3, shirt = 1, pants = 2, legs = 4, hat = 5, hair = 6 } }
		local bare = PeopleLooks.strip(look)
		check(
			bare.pieces.suit == nil and bare.pieces.shirt == nil and bare.pieces.pants == nil,
			"drawn slots off"
		)
		check(
			bare.pieces.legs == nil and bare.pieces.hat == 5 and bare.pieces.hair == 6,
			"hats and hair stay"
		)
		check(look.pieces.suit == 3 and look.pieces.legs == 4, "the look itself is unchanged")
		check(PeopleLooks.villain("Pitboss", "Bramblebeast") == "Pitboss", "a dress names the villain")
		check(PeopleLooks.villain(nil, "WindupGiant") == "WindupGiant", "else the kind")
		local id, h = PeopleLooks.helperAt(Config, "HeroAcademy", 4, "hero")
		check(id == "Wren" and h and h.speaker == "wren", "Wren stands in at the academy's step 4")
		check(PeopleLooks.helperAt(Config, "HeroAcademy", 4, "villain") == nil, "only on her side")
		check(PeopleLooks.helperAt(Config, "HeroAcademy", 1, "both") == nil, "only at her step")
	end)

	-- Robot looks (2026-11-18, overnight item 11): no robot type is left without a Roblox look of its own
	test("Robot looks: every robot type has a drawn Roblox-look outfit", function()
		local kinds = 0
		for _, kind in Config.Enemies.order do
			local cfg = Config.Enemies[kind]
			kinds += 1
			if cfg.twin then
				-- the evil twin wears the exact look of the player it copies
				check(cfg.fake ~= nil, "the twin is a fake")
			elseif cfg.fake then
				-- a famous fake or a costumed villain: its own hero suit, face and cracked face (Shared.PeopleLooks)
				local p = NL.people[kind]
				check(p ~= nil and p.clothes ~= nil, kind .. " has a suit of its own")
				check(fs.isFile("art/export/clothes/people/" .. kind .. ".png"), kind .. "'s suit is drawn")
			else
				local r = NL.robots[kind]
				check(r ~= nil, kind .. " has uniforms")
				for _, v in NL.versions do
					local file = if kind == "SparkDrone" and v == "Grunt"
						then "art/export/clothes/Trooper_Clothes.png"
						else "art/export/clothes/uniforms/" .. kind .. "_" .. v .. ".png"
					check(fs.isFile(file), kind .. " " .. v .. " is drawn")
				end
			end
		end
		check(kinds == 31, "all 31 robot types checked")
		for _, fake in { "Radiant", "Bulwark", "Skylance" } do
			local p = NL.people[fake]
			check(p and p.face ~= nil and p.cracked ~= nil, fake .. " has a famous face and its cracked face")
			check(fs.isFile("art/export/clothes/people/Face_" .. fake .. ".png"), fake .. "'s face is drawn")
			check(PeopleLooks.villain(nil, fake) == fake, fake .. " wears its own row")
		end
		-- a Salt Dog's bandana is cloth: it breaks off with the head's shell
		local er = readFile("src/client/Controllers/EnemyRenderer.luau")
		check(string.find(er, 'Bandana = { "Head" }', 1, true) ~= nil, "the bandana goes with the head")
	end)

	test("Art pass: every outfit and face is drawn, and the finale models' config is sound", function()
		for id, p in NL.people do
			check(fs.isFile("art/export/clothes/people/" .. id .. ".png"), id .. "'s outfit is drawn")
			if p.cracked ~= nil then
				check(
					fs.isFile("art/export/clothes/people/Face_" .. id .. "_Cracked.png"),
					id .. "'s cracked face"
				)
			end
		end
		local R15 = {}
		for _, n in
			{
				"Head",
				"UpperTorso",
				"LowerTorso",
				"LeftUpperArm",
				"LeftLowerArm",
				"LeftHand",
				"RightUpperArm",
				"RightLowerArm",
				"RightHand",
				"LeftUpperLeg",
				"LeftLowerLeg",
				"LeftFoot",
				"RightUpperLeg",
				"RightLowerLeg",
				"RightFoot",
			}
		do
			R15[n] = true
		end
		local finales = {}
		for _, ch in SQ.chains do
			for _, step in ch.steps do
				local g = SideQuestPlan.goal(step, "hero")
				if g and g.kind == "finale" then
					for phase = 1, 2 do
						local foe = SideQuestPlan.finaleFoe(g, phase)
						finales[PeopleLooks.villain(foe.dress, foe.enemy) :: string] = true
					end
				end
			end
		end
		local n, names = 0, {}
		for name, fa in Config.FinaleArt do
			n += 1
			check(finales[name] == true, name .. " is a side quest finale villain")
			check(type(fa.tint) == "table" and #fa.tint == 3, name .. " has a tint")
			check(fa.triangles > 0 and fa.triangles <= 12000, name .. " is in the triangle budget")
			check(fs.isFile("art/export/finales/" .. name .. ".fbx"), name .. "'s model is exported")
			for xname, x in fa.extras do
				check(names[xname] == nil and R15[xname] == nil, xname .. " is a unique extra")
				names[xname] = true
				check(R15[x.parent] == true, xname .. " sits on an R15 part")
				check(#x.offset == 3 and #x.size == 3, xname .. " has an offset and size")
				for _, s in x.size do
					check(s > 0, xname .. " has a positive size")
				end
			end
		end
		check(n == 3 and Config.FinaleArt.Bramblebeast and Config.FinaleArt.Voidhound, "three finale models")
		check(Config.FinaleArt.WindupGiant ~= nil, "the Wind-Up Giant's model")
		local er = readFile("src/client/Controllers/EnemyRenderer.luau")
		check(string.find(er, "Config.FinaleArt[who]", 1, true) ~= nil, "the renderer reads a finale's model")
		check(string.find(er, "NpcRig.meshes(nil, who)", 1, true) ~= nil, "only once it is imported")
		check(string.find(er, "PeopleLooks.outfit(Config, who)", 1, true) ~= nil, "a villain's own outfit")
		local sq = readFile("src/server/Services/SideQuestService.luau")
		check(string.find(sq, "PeopleLooks.outfit(Config, id)", 1, true) ~= nil, "givers wear their outfit")
		check(string.find(sq, "PeopleLooks.helperAt(", 1, true) ~= nil, "named helpers stand in")
	end)
end

---------------------------------------------------------------------------
-- World fixes (2026-11-18): the boss's string tiers, leavers' tier slots, no Fame on a retreat, the drain
-- gap for bounties and Your double, a rampage cut short by the server cap, Reset while Downed or mid PvP.
-- The services' own wiring is on the Studio list.
---------------------------------------------------------------------------

do
	local PvpRules = require("../src/shared/PvpRules")
	local Signal = require("../src/shared/Util/Signal")

	test("World fixes: boss tiers are strings; tookPart reads them without throwing", function()
		for _, t in { "mvp", "contributor", "participant", "floor" } do
			check(BossMath.tookPart(t), t .. " took part")
		end
		for _, t: any in { "", 1, 3, false } do
			check(not BossMath.tookPart(t), "not a tier: " .. tostring(t))
		end
		check(not BossMath.tookPart(nil), "no tier")
		local tier: any = "mvp"
		check(not pcall(function()
			return tier >= 1
		end), "the old check (a string >= 1) throws, as the review found")
	end)

	test("World fixes: one throwing reward listener no longer stops the other heroes' pay", function()
		local rewarded = Signal.new()
		local onError = Signal.onError
		Signal.onError = function() end -- the listener's bug is expected here
		rewarded:Connect(function(_player: any, tier: any)
			if tier == "mvp" then
				error("a listener's bug")
			end
		end)
		local paid = {}
		rewarded:Connect(function(player: any)
			table.insert(paid, player)
		end)
		local scores = BossMath.scores(Config, {
			[1] = { damage = 900, support = 0, objectives = 0 },
			[2] = { damage = 500, support = 0, objectives = 0 },
			[3] = { damage = 300, support = 0, objectives = 0 },
			[4] = { damage = 100, support = 0, objectives = 0 },
		})
		local tiers, ranked = BossMath.tiers(Config, scores)
		local ended = false
		-- BossService.finish's loop: each hero's reward under its own pcall, then the result phase
		for _, heroId in ranked do
			pcall(function()
				rewarded:Fire(heroId, tiers[heroId])
			end)
		end
		ended = true
		Signal.onError = onError
		check(ended, "the fight reaches its result phase")
		-- data fixes: Signal now isolates each handler, so the MVPs get the rest of their reward too
		check(#paid == 4 and paid[4] == 4, "every hero, MVPs too, still got the rest of their reward")
	end)

	test("World fixes: heroes who left give up their MVP and Contributor slots", function()
		local ledger = {}
		for id = 1, 6 do
			ledger[id] = { damage = 1000 * (7 - id), support = 0, objectives = 0 } -- 1 is the top hitter
		end
		local gone = { [1] = true, [3] = true }
		local here = BossMath.present(ledger, function(id)
			return not gone[id]
		end)
		local tiers, ranked = BossMath.tiers(Config, BossMath.scores(Config, here))
		check(#ranked == 4 and tiers[1] == nil and tiers[3] == nil, "the two who left get no tier")
		check(tiers[2] == "mvp" and tiers[4] == "mvp" and tiers[5] == "mvp", "the next three are the MVPs")
		check(ranked[1] == 2, "the top hitter still here ranks first")
		check(next(BossMath.present(ledger, function()
			return false
		end)) == nil, "nobody here: an empty ledger")
	end)

	test("World fixes: a retreat pays its Credits consolation but no Fame; a win pays Fame", function()
		for _, t in { "mvp", "contributor", "participant", "floor" } do
			check(BossMath.reward(Config, t, true).fame, t .. ": a defeated boss pays the tier's Fame")
			local r = BossMath.reward(Config, t, false)
			check(not r.fame and #r.drops == 0 and not r.style, t .. ": a retreat pays no Fame")
		end
		check(BossMath.reward(Config, "mvp", false).share == Config.Boss.rewards.consolation, "the 25% stays")
	end)

	test(
		"World fixes: a robot beaten in the drain gap is not gone, so bounties and Your double wait",
		function()
			local sim = EnemySim.new(Config, {})
			local e = EnemySim.spawn(sim, "BruteBot", 0, 0, 0, 10) :: any
			check(e ~= nil and not EnemySim.gone(sim, e.id), "a live robot is not gone")
			check(EnemySim.damage(sim, e.id, math.huge, 1), "it falls")
			-- the bounty's 5 Hz tick and the event's tick run here, before the 10 Hz drain fires Killed
			check(
				not EnemySim.gone(sim, e.id),
				"killed, Killed not fired yet: not gone (no respawn, no fail)"
			)
			EnemySim.drainEvents(sim)
			check(EnemySim.gone(sim, e.id), "after the drain it is gone")
			local f = EnemySim.spawn(sim, "BruteBot", 0, 0, 0, 10) :: any
			EnemySim.remove(sim, f.id)
			check(
				EnemySim.gone(sim, f.id),
				"removed some other way: gone (the bounty respawns, the double ends)"
			)
		end
	)

	test("World fixes: a robot rampage cut short by the server cap can still be won", function()
		local d = Config.Events.events.RobotRampage
		local planned = 0
		for _, w in d.waves do
			planned += w[2]
		end
		local need = planned
		local got = { d.waves[1][2], 1, 0, d.waves[4][2] } -- wave 2 got 1, wave 3 none
		for i, w in d.waves do
			need = EventPlan.shortNeed(need, w[2], got[i])
		end
		local spawned = 0
		for _, n in got do
			spawned += n
		end
		check(need == spawned, "the goal is the robots that came: " .. need .. " of " .. planned)
		check(EventPlan.shortNeed(14, 3, 6) == 14, "a Swarmer's extra pack never raises the goal")
		check(EventPlan.shortNeed(3, 4, 0) == 1, "never below 1")
	end)

	test("World fixes: Reset while Downed is Give Up; a Reset mid PvP fight is that defeat", function()
		check(PvpRules.resetOutcome(true, false, nil) == "giveUp", "Downed: Give Up")
		check(
			PvpRules.resetOutcome(true, false, 77) == "giveUp",
			"Downed with a recent PvP hit: still Give Up"
		)
		check(
			PvpRules.resetOutcome(false, true, 77) == "pvp",
			"standing, hit in PvP inside 15 s: that defeat"
		)
		check(PvpRules.resetOutcome(false, true, nil) == "plain", "standing, no PvP: a plain defeat")
		check(PvpRules.resetOutcome(false, false, 77) == "plain", "already defeated: nothing more")
	end)
end

---------------------------------------------------------------------------
-- Data fixes (2026-11-18): receipts acknowledged only after a save that holds them, the Hero Pass on the
-- live season, one kick per kick event, a strike needs fresh evidence, Legacy keeps who the hero is,
-- Signal handlers isolated. The services' wiring is on the Studio list ("Data fixes").
---------------------------------------------------------------------------
do
	local ShopRules = require("../src/shared/ShopRules")
	local PassRules = require("../src/shared/PassRules")
	local GuardRules = require("../src/shared/GuardRules")
	local HqRules = require("../src/shared/HqRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local Signal = require("../src/shared/Util/Signal")

	test("Data fixes: a receipt is acknowledged only once a save that holds it worked", function()
		local profile = ProfileSchema.default()
		local saves, works = 0, false
		local function save()
			saves += 1
			return works
		end
		local answer, got = ShopRules.receipt(Config, profile, "pack2", "r1", 0, false, save)
		check(answer == "notYet" and got == nil and saves == 0, "a session that cannot save grants nothing")
		check(not ShopRules.hasReceipt(profile, "r1"), "and records nothing")
		answer, got = ShopRules.receipt(Config, profile, "pack2", "r1", 0, true, save)
		check(answer == "notYet" and got ~= nil and saves == 1, "granted, but the save failed: not yet")
		check(ShopRules.hasReceipt(profile, "r1"), "the grant stays in memory for the retry")
		-- Roblox asks again in the same session: the id is there, but it is still not on any save
		answer, got = ShopRules.receipt(Config, profile, "pack2", "r1", 0, true, save)
		check(
			answer == "notYet" and got == nil and saves == 2,
			"the retry saves again, never acknowledged unsaved"
		)
		works = true
		answer, got = ShopRules.receipt(Config, profile, "pack2", "r1", 0, true, save)
		check(
			answer == "granted" and got == nil and saves == 3,
			"acknowledged once a save holds it, no second grant"
		)
		answer, got = ShopRules.receipt(Config, profile, "pack3", "r2", 0, true, save)
		check(answer == "granted" and got ~= nil and got.key == "pack3", "a fresh receipt that saves at once")
	end)

	test("Data fixes: a Hero Pass bought at a season boundary lands on the live season", function()
		local P = Config.Pass
		local C2 = table.clone(Config)
		C2.Pass = table.clone(P)
		C2.Pass.seasons = { P.seasons[1], P.seasons[1] } -- a written season 2
		local inS2 = ((P.startWeek + P.weeks) * 7 - 3) * 86400 + 3600 -- an hour into season 2
		check(PassRules.season(P, inS2) == 2, "the time is in season 2")
		local profile = ProfileSchema.default()
		PassRules.roll(profile.pass, 1)
		profile.pass.xp = 500
		check(ShopRules.available(C2, profile, "heroPass", inS2), "on sale in the live season")
		check(profile.pass.season == 2 and profile.pass.xp == 0, "judged on the live season (rolled)")
		profile.pass.season = 1 -- the stale season again (no roll since the boundary)
		check(ShopRules.grant(C2, profile, "heroPass", "boundary", inS2), "the receipt grants")
		check(profile.pass.season == 2 and profile.pass.paid, "set on the live season")
		check(not PassRules.roll(profile.pass, 2) and profile.pass.paid, "the next roll keeps it")
		-- no season 2 written: not sold off a stale season 1
		local p2 = ProfileSchema.default()
		PassRules.roll(p2.pass, 1)
		check(not ShopRules.available(Config, p2, "heroPass", inS2), "an ended season is not sold")
		check(ShopRules.available(Config, p2, "heroPass", inS2 - P.weeks * 7 * 86400), "a live one is")
	end)

	test("Data fixes: one kick event is one kick; strikes start over after it", function()
		local s = GuardRules.newStrikes()
		local kicks = 0
		for i = 1, 30 do -- 10 Hz speed fails for 3 s
			if GuardRules.strike(Config, s, "speed", i * 0.1) then
				kicks += 1
			end
		end
		check(kicks == 1, string.format("one kick, not %d", kicks))
		check(
			s.kicking and #s.times == 0 and s.kinds.speed == 3,
			"the book is cleared, its kinds kept for the row"
		)
		check(
			not GuardRules.netDrop(Config, s, 10) and s.net == 0,
			"remote drops count nothing while kicking"
		)
		GuardRules.kickDone(s)
		check(not s.kicking and next(s.kinds) == nil, "Studio's no-kick opens the book again")
		check(not GuardRules.strike(Config, s, "speed", 20), "and counts from zero")
		check(not GuardRules.needsReview(Config, kicks), "a first offender is not queued for review")
	end)

	test("Data fixes: a lag spike's stale positions are one strike, not three", function()
		local S = Config.Safety
		local cap = MoveMath.speedCap(M, { flight = true }, true)
		local st = MoveCheck.new(0, 100, 0, 0)
		MoveCheck.sample(st, 10, 100, 0, 0.1, cap, M, S)
		-- the device was cut off and its positions land at once 400 studs on; until MoveCorrect reaches it,
		-- every 10 Hz sample sees the same far spot
		local strikes, fails = 0, 0
		for i = 1, 20 do
			local ok, strike = MoveCheck.sample(st, 410, 100, 0, 0.1 + i * 0.1, cap, M, S)
			fails += if ok then 0 else 1
			strikes += if strike then 1 else 0
		end
		check(fails == 20, "every sample still pulls back")
		check(strikes == 1, string.format("one strike in 2 s (%d)", strikes))
		check(S.strikeGrace >= 2 and S.strikeGrace < S.strikes.window / S.strikes.kickAt, "a short grace")
		-- still far after the grace: that is fresh evidence
		local _, again = MoveCheck.sample(st, 410, 100, 0, 0.1 + S.strikeGrace + 0.2, cap, M, S)
		check(again, "still teleported after the grace: a new strike")
		-- a teleport hack is still kicked inside the window, just not in one burst
		local hack = MoveCheck.new(0, 10, 0, 0)
		local book = GuardRules.newStrikes()
		local kickedAt = nil
		for i = 1, 200 do
			local t = i * 0.1
			local _, strike = MoveCheck.sample(hack, 1000 * i, 10, 0, t, cap, M, S)
			if strike and GuardRules.strike(Config, book, "speed", t) and not kickedAt then
				kickedAt = t
			end
		end
		check(kickedAt ~= nil and kickedAt > 2 * S.strikeGrace, "a hack is kicked after fresh strikes")
	end)

	test("Data fixes: Legacy keeps origin, mobility, weapon, title, travel styles and chains", function()
		local profile = ProfileSchema.default()
		local c = profile.characters[1]
		c.level = Config.Stats.levelCap
		c.created = 1
		c.origin = 3
		c.mobility = "swing"
		c.weapon = 7
		c.pathChanged = 1
		c.mmo.title = 12
		c.mmo.aura = 2
		c.mmo.trim = 101
		c.mmo.travel = { 1, 0, 2, 0, 3 }
		c.mmo.cores = 4
		c.mmo.nemesis.rank = 3
		ProfileSchema.Bits.set(c.sq.done, 1)
		c.contracts = { { id = 1 } }
		check(HqRules.retire(Config, profile, 1, 1000) ~= nil, "retired")
		local loaded = ProfileSchema.load(serde.decode("json", serde.encode("json", profile)))
		for _, n in { profile.characters[1], loaded.characters[1] } do
			check(n.level == 1 and n.legacy == 1, "a new run")
			check(
				n.origin == 3,
				"origin kept (was 0, then repaired to " .. Config.Creator.originDefault .. ")"
			)
			check(
				n.mobility == "swing" and n.weapon == 7 and n.pathChanged == 1,
				"mobility, weapon, path change"
			)
			check(n.mmo.title == 12 and n.mmo.aura == 2 and n.mmo.trim == 101, "worn title, aura and trim")
			check(n.mmo.travel[3] == 2 and n.mmo.travel[5] == 3, "travel picks")
			check(n.mmo.cores == 4 and n.mmo.nemesis.rank == 3, "the MMO record")
			check(ProfileSchema.Bits.get(n.sq.done, 1), "finished chains")
			check(#n.contracts == 0, "contracts start over (their pay is by level)")
		end
	end)

	test("Data fixes: a Signal handler's error never stops the handlers after it", function()
		local sig = Signal.new()
		local order = {}
		local errors = 0
		local was = Signal.onError
		Signal.onError = function()
			errors += 1
		end
		sig:Connect(function(v)
			table.insert(order, "a" .. v)
		end)
		sig:Connect(function()
			error("boom")
		end)
		sig:Connect(function(v)
			table.insert(order, "c" .. v)
		end)
		sig:Fire(1)
		Signal.onError = was
		check(errors == 1, "the error is reported")
		check(#order == 2 and order[1] == "a1" and order[2] == "c1", "the rest run, in connect order")
	end)
end

---------------------------------------------------------------------------
-- Combat fixes (review 5): speed caps, leaps, PvP rules, cooldowns, grants
---------------------------------------------------------------------------
do
	local fs = require("@lune/fs")
	local CastPlan = require("../src/shared/CastPlan")
	local Awakening = require("../src/shared/Awakening")
	local AbilityRules = require("../src/shared/AbilityRules")
	local ChargeRules = require("../src/shared/ChargeRules")
	local S = Config.Safety
	local AB = Config.Abilities
	local combatSrc = fs.readFile("src/server/Services/CombatService.luau")

	-- 10 Hz samples of a hero moving at `speed` studs/s along x for `secs`; a pull-back puts it back on the
	-- last good spot, as MoveCorrect does. Returns the pull-backs.
	local function pullBacks(speed: number, secs: number, cap: number): number
		local st = MoveCheck.new(0, 10, 0, 0)
		local x, fails = 0, 0
		for i = 1, math.floor(secs * 10 + 0.5) do
			x += speed * 0.1
			local ok, _, wait = MoveCheck.sample(st, x, 10, 0, i * 0.1, cap, M, S)
			if not ok and not wait then
				fails += 1
				x = st.x
			end
		end
		return fails
	end

	-- one move of `dist` studs over `time` s (a dash, a leap, a knock), sampled at 10 Hz from a standing
	-- start; `grantAt` is the sample index the server's grant arrives after (0: before the first position)
	local function movePulls(dist: number, time: number, grant: number, cap: number, grantAt: number): number
		local st = MoveCheck.new(0, 10, 0, 0)
		MoveCheck.sample(st, 0, 10, 0, 1, cap, M, S)
		if grantAt == 0 then
			MoveCheck.grant(st, grant, 1)
		end
		local fails = 0
		for i = 1, 30 do
			local t = i * 0.1
			local x = dist * math.min(1, t / time)
			local ok, strike, wait = MoveCheck.sample(st, x, 10, 0, 1 + t, cap, M, S)
			if strike or (not ok and not wait) then
				fails += 1
			end
			if i == grantAt then
				MoveCheck.grant(st, grant, 1 + t)
			end
		end
		return fails
	end

	test(
		"Combat fixes: speed buffs raise MoveGuard's cap (Super-speed with Weightless, Feather, a Mystic's)",
		function()
			local styles = { speed = true }
			local weightless = AB.list.Weightless
			local feather = weightless.value + weightless.mods[1].add.value
			local mystic = feather * (1 + Config.Classes.Mystic.supportBonus)
			local sprint = M.mobility.speed.sprint
			local oldCap = MoveMath.speedCap(M, styles, false)
			check(
				pullBacks(sprint * (1 + weightless.value), 6, oldCap) > 0,
				"the old cap pulled the buffed sprint back"
			)
			for _, b in { weightless.value, feather, mystic, AB.list.TideMirror.value } do
				local cap = MoveMath.guardCap(M, styles, false, { speedBuff = b })
				local n = pullBacks(sprint * (1 + b), 6, cap)
				check(
					n == 0,
					string.format(
						"sprint at %.0f under a +%.0f%% buff: %d pull-backs",
						sprint * (1 + b),
						b * 100,
						n
					)
				)
			end
			-- the buff scales every pick's run (Acrobat's, the walk) and leaves rides and Weightless flight intact
			local acro = MoveMath.guardCap(M, { acrobat = true }, false, { speedBuff = mystic })
			check(pullBacks(M.mobility.acrobat.run * (1 + mystic), 6, acro) == 0, "Acrobat's buffed run")
			local zero = MoveMath.guardCap(M, {}, false, { zeroG = true })
			check(zero == M.caps.flight, "Weightless lets anyone fly at the flight cap")
			check(pullBacks(M.flight.boost, 6, zero) == 0, "and boost there")
			check(
				MoveMath.guardCap(M, {}, false, {}) == MoveMath.speedCap(M, {}, false),
				"no buff: the old cap"
			)
			check(
				MoveMath.guardCap(M, {}, false, { speedBuff = -0.5 }) == MoveMath.speedCap(M, {}, false),
				"never less"
			)
			-- the buff ends on the device up to a ping later than on the server: the banked travel covers it
			local st = MoveCheck.new(0, 10, 0, 0)
			local x, fails = 0, 0
			local fast = sprint * (1 + mystic)
			for i = 1, 60 do
				local t = i * 0.1
				local serverBuff = if t <= 4 then mystic else 0
				local speed = if t <= 4.3 then fast else sprint
				x += speed * 0.1
				local cap = MoveMath.guardCap(M, styles, false, { speedBuff = serverBuff })
				local ok, _, wait = MoveCheck.sample(st, x, 10, 0, t, cap, M, S)
				if not ok and not wait then
					fails += 1
					x = st.x
				end
			end
			check(fails == 0, string.format("a 300 ms late end: %d pull-backs", fails))
		end
	)

	test("Combat fixes: every other client speed source fits the server's budget", function()
		-- every pick's top speed against its own cap, for 6 s
		local tops = {
			{ "speed", M.mobility.speed.sprint },
			{ "speed", M.mobility.speed.wallRun },
			{ "acrobat", M.mobility.acrobat.glideForward },
			{ "acrobat", M.mobility.acrobat.wallRun },
			{ "swing", M.mobility.swing.maxSpeed },
			{ "swing", M.mobility.swing.zip },
			{ "flight", M.mobility.flight.up.boost },
			{ "leap", MoveMath.superLeapSpeed(M) },
		}
		for _, row in tops do
			local cap = MoveMath.guardCap(M, { [row[1]] = true }, true, {})
			local n = pullBacks(row[2], 6, cap)
			check(n == 0, string.format("%s at %.0f: %d pull-backs", row[1], row[2], n))
		end
		-- travel styles ride at their own speed (the ride buff), with every mod
		local runner = MoveMath.speedCap(M, {}, false)
		local rides, dashes = 0, 0
		for id, row in AB.list do
			for mod = 0, #(row.mods or {}) do
				local eff = AbilityRules.effective(Config, id, 1, if mod > 0 then mod else nil)
				if eff.shape == "ride" then
					rides += 1
					local cap = MoveMath.guardCap(M, {}, false, { ride = eff.speed or 80 })
					local n = pullBacks(eff.speed or 80, eff.duration or 4, cap)
					check(n == 0, string.format("%s rides at %d: %d pull-backs", id, eff.speed or 80, n))
				elseif eff.shape == "dash" then
					-- dashes: the full range at the row's time, granted range + 10 as CombatService does,
					-- whether the grant reaches the server before the first position or one sample after it
					dashes += 1
					local d = eff.range or 0
					for _, at in { 0, 1 } do
						local n = movePulls(d, eff.time or 0.18, d + 10, runner, at)
						check(n == 0, string.format("%s (%d studs, grant after sample %d): %d", id, d, at, n))
					end
				end
			end
		end
		check(rides >= 7 and dashes >= 30, string.format("%d rides and %d dashes checked", rides, dashes))
		-- PvP knockback and thrown-car hits (capped at Pvp.knock.maxDistance in 0.35 s, granted + 10)
		local K8 = Config.Pvp.knock
		check(movePulls(K8.maxDistance, 0.35, K8.maxDistance + 10, runner, 1) == 0, "the biggest knockback")
		-- Meteor Leap (+40) and the Grappling Hook (+12)
		local meteor = AB.list.MeteorLeap
		check(movePulls(meteor.range, meteor.time, meteor.range + 40, runner, 1) == 0, "Meteor Leap")
		local hook = Config.Gear.gadgets.GrapplingHook
		check(movePulls(hook.range, hook.time, hook.range + 12, runner, 1) == 0, "the Grappling Hook")
	end)

	test("Combat fixes: a leap lands where the client flies it (flat aim, unit ray)", function()
		local world = {
			rayDist = function(_ox, oy, _oz, dx, dy, dz, max)
				local l = math.sqrt(dx * dx + dy * dy + dz * dz)
				if dy < 0 then
					local d = -oy / dy * l -- open ground at y = 0
					if d < max * l then
						return d
					end
				end
				return max * l
			end,
			groundY = function()
				return 0
			end,
		}
		for _, id in { "MeteorLeap", "PhoenixDive" } do
			local eff = AbilityRules.effective(Config, id, 1)
			for _, pitch in { 30, 10, 0, -10, -30, -60 } do
				local a = math.rad(pitch)
				local dx, dy = math.cos(a), math.sin(a)
				local plan = CastPlan.build(eff, 0, 60, 0, dx, dy, 0, 0, {}, world) :: any
				-- CombatClient.fire: a unit ray along (dx, max(dy, -0.2), dz) from 4 up, then along the flat aim
				local cy = math.max(dy, -0.2)
				local l = math.sqrt(dx * dx + cy * cy)
				local d = math.max(0, world.rayDist(0, 64, 0, dx / l, cy / l, 0, eff.range) - 3)
				near(plan.cx, d, 0.01, string.format("%s at %d degrees lands with the client", id, pitch))
				near(plan.cz, 0, 1e-6, "on the aim's line")
				near(plan.cy, 3, 1e-6, "on the floor")
			end
			local up = CastPlan.build(eff, 0, 60, 0, math.cos(math.rad(30)), 0.5, 0, 0, {}, world) :: any
			near(up.cx, eff.range - 3, 0.01, id .. " aimed up still goes its full range")
		end
	end)

	test("Combat fixes: a super's field ticks keep PvP's super rule and the set bonus", function()
		local eff = AbilityRules.effective(Config, "EmberRing", 1)
		local super = { slot = "super", set = "Fire", status = "pull", statusDur = 0.2, slow = 0.5 }
		local f = { coeff = 0.4, tick = 0.5 }
		local t = CastPlan.tickEff(super, f)
		check(
			t.slot == "super" and t.set == "Fire",
			"slot and set reach the tick (pvpHit's isSuper, the set bonus)"
		)
		near(t.statusDur, 0.6, 1e-9, "a pull lasts a tick")
		check(t.coeff == 0.4 and t.slow == 0.5, "the field's own numbers")
		local touch = CastPlan.tickEff(eff, { coeff = 0.2, tick = 0.5, status = false })
		check(touch.status == false and touch.slot == eff.slot, "an override still wins")
		local supers = 0
		for id, row in AB.list do
			if row.slot == "super" and row.shape == "field" then
				supers += 1
				check(
					CastPlan.tickEff(row, { coeff = row.coeff, tick = row.tick or 0.5 }).slot == "super",
					id
				)
			end
		end
		check(supers > 0, string.format("%d super fields", supers))
		check(
			string.find(combatSrc, "local fieldEff = CastPlan.tickEff(eff, f)", 1, true) ~= nil,
			"stepFields uses it"
		)
	end)

	test("Combat fixes: Awakening is +10% in PvP, +20% against robots", function()
		local m = Awakening.new()
		m.untilT = 100
		near(Awakening.damageMult(Config, m, 1, true), 1 + AB.awakening.pvpDamage, 1e-9, "PvP")
		near(Awakening.damageMult(Config, m, 1, false), 1 + AB.awakening.damage, 1e-9, "robots")
		check(
			string.find(combatSrc, "Awakening.damageMult(Config, hero.meter, os.clock(), pvp)", 1, true)
				~= nil,
			"rollDamage passes pvp"
		)
	end)

	test("Combat fixes: spamming a skill never beats its cooldown (skills and gadgets)", function()
		local leeway = Config.Combat.cooldownLeeway
		local function spam(startFn: any, secs: number): number
			local book = Cooldowns.new()
			local casts, t = 0, 0
			while t < secs do
				if Cooldowns.ready(book, "B", t, leeway) then
					startFn(book, "B", t, 0.5)
					casts += 1
				end
				t += 1 / 12
			end
			return casts
		end
		check(spam(Cooldowns.start, 10) > 21, "the old start from now let a spammer in early every cycle")
		local n10, n60 = spam(Cooldowns.startNext, 10), spam(Cooldowns.startNext, 60)
		check(n10 <= 21, string.format("10 s of a 0.5 s cooldown: %d casts (20, +1 for the leeway)", n10))
		check(n60 <= 121, string.format("60 s: %d casts", n60))
		-- an honest use after the cooldown ran out starts from now
		local book = Cooldowns.new()
		Cooldowns.startNext(book, "B", 0, 2)
		Cooldowns.startNext(book, "B", 5, 2)
		near(book.readyAt.B, 7, 1e-9, "from now when it was already ready")
		Cooldowns.startNext(book, "B", 6.95, 2)
		near(book.readyAt.B, 9, 1e-9, "from when it was due when let in early")
		local gear = fs.readFile("src/server/Services/GearService.luau")
		check(
			string.find(gear, "Cooldowns.startNext(book, kind, now, row.cd)", 1, true) ~= nil,
			"gadgets too"
		)
		check(string.find(combatSrc, "Cooldowns.startNext(", 1, true) ~= nil, "and CombatService.use")
	end)

	test("Combat fixes: granted travel does not last (5 old grants never bank a 200 stud jump)", function()
		local cap = MoveMath.speedCap(M, {}, false)
		local st = MoveCheck.new(0, 0, 0, 0)
		for _ = 1, 5 do
			MoveCheck.grant(st, 40, 0)
		end
		local now = 0
		for _ = 1, 300 do
			now += 0.1
			MoveCheck.sample(st, 0, 0, 0, now, cap, M, S)
		end
		now += 0.1
		local ok = MoveCheck.sample(st, 200, 0, 0, now, cap, M, S)
		check(not ok, "a 200 stud jump 30 s after five grants fails")
		check(st.extra == 0, "the old grants are gone")
		-- a grant still covers a move whose positions come late (inside grantKeep)
		local late = MoveCheck.new(0, 10, 0, 0)
		MoveCheck.sample(late, 0, 10, 0, 1, cap, M, S)
		MoveCheck.grant(late, 150, 1)
		local passed = MoveCheck.sample(late, 140, 10, 0, 1 + S.grantKeep - 0.1, cap, M, S)
		check(passed, "a granted move seen late (lag) still passes")
		-- an expired grant never strikes on its own: the biggest grant against the slowest cap
		local big = AB.list.MeteorLeap.range + 40
		local exp = MoveCheck.new(0, 10, 0, 0)
		MoveCheck.sample(exp, 0, 10, 0, 1, cap, M, S)
		MoveCheck.grant(exp, big, 1)
		local _, strike = MoveCheck.sample(exp, big, 10, 0, 1 + S.grantKeep + 0.2, cap, M, S)
		check(not strike, "a grant that ran out pulls back at most, never a strike")
		check(S.grantKeep >= 1.5, "grants last past the longest move (Meteor Leap's 1.1 s) and a ping")
	end)

	test("Combat fixes: a dash's positions before its grant wait one sample, not a pull-back", function()
		local cap = MoveMath.speedCap(M, {}, false)
		local st = MoveCheck.new(0, 10, 0, 0)
		MoveCheck.sample(st, 0, 10, 0, 1, cap, M, S)
		-- a 100 stud burst (more than the banked budget) seen before its grant
		local ok, strike, wait = MoveCheck.sample(st, 100, 10, 0, 1.1, cap, M, S)
		check(not ok and not strike and wait, "the first miss waits")
		MoveCheck.grant(st, 110, 1.15)
		check(
			(MoveCheck.sample(st, 100, 10, 0, 1.2, cap, M, S)),
			"the grant lands: passes from the last good spot"
		)
		-- no grant comes: the second miss pulls back; a teleport still strikes at once
		local hack = MoveCheck.new(0, 10, 0, 0)
		MoveCheck.sample(hack, 0, 10, 0, 1, cap, M, S)
		local _, _, w1 = MoveCheck.sample(hack, 100, 10, 0, 1.1, cap, M, S)
		local ok2, _, w2 = MoveCheck.sample(hack, 115, 10, 0, 1.2, cap, M, S)
		check(w1 and not ok2 and not w2, "a second miss in a row pulls back")
		local tp = MoveCheck.new(0, 10, 0, 0)
		MoveCheck.sample(tp, 0, 10, 0, 1, cap, M, S)
		local okT, strikeT, waitT = MoveCheck.sample(tp, 600, 10, 0, 1.1, cap, M, S)
		check(not okT and strikeT and not waitT, "a teleport is a strike on the first sample")
	end)

	test("Combat fixes: PvP opponents never form a team-up combo", function()
		local pair = AB.combos.pairs[1]
		local function use(hero: number, set: string, t: number): any
			return { hero = hero, set = set, x = 0, y = 0, z = 0, t = t }
		end
		local book = Awakening.comboBook()
		Awakening.noteSuper(Config, book, use(1, pair.sets[1], 0), function()
			return false
		end)
		local p = Awakening.noteSuper(Config, book, use(2, pair.sets[2], 0.5), function()
			return false
		end)
		check(p == nil, "canPair false: no combo")
		local book2 = Awakening.comboBook()
		Awakening.noteSuper(Config, book2, use(1, pair.sets[1], 0))
		check(Awakening.noteSuper(Config, book2, use(2, pair.sets[2], 0.5)) == pair, "friends still pair")
		check(string.find(combatSrc, "}, comboPair)", 1, true) ~= nil, "comboCheck passes canPair")
		check(
			string.find(combatSrc, "not (ha and hb and FlagService.canHit(ha, hb))", 1, true) ~= nil,
			"from canHit"
		)
	end)

	test("Combat fixes: the charge cap is the hold the server timed (no ping on top)", function()
		local CC = Config.Combat
		local ch = CC.charge
		local early = 10 + ch.full - ch.leeway - 0.15 -- 0.15 s short of a full hold
		check(ChargeRules.allowed(CC, 100, 10, early, 0.15) < 1, "a short hold at 150 ms ping is not full")
		check(
			ChargeRules.allowed(CC, 100, 10, 10 + ch.full, 0.3) == 1,
			"a real full hold is full at any ping"
		)
		check(ChargeRules.allowed(CC, 100, 10, 10 + ch.full - ch.leeway, 0) > 0.999, "jitter: the leeway")
	end)

	test(
		"Combat fixes: no casting in fast travel or the creator; fields, links and rafts are cleaned up",
		function()
			check(
				string.find(combatSrc, "or hero.traveling -- fast travel", 1, true) ~= nil,
				"use() checks traveling"
			)
			check(
				string.find(combatSrc, 'or hero.scene == "creator"', 1, true) ~= nil,
				"and the creator scene"
			)
			local removed =
				string.match(combatSrc, "HeroService%.Removed:Connect%(function%(hero%)(.-)\n\tend%)")
			check(removed ~= nil, "CombatService listens for heroes leaving")
			if removed then
				check(string.find(removed, "fields[i].hero == hero", 1, true) ~= nil, "their fields stop")
				check(string.find(removed, "links[id] = nil", 1, true) ~= nil, "their links go")
				check(
					string.find(removed, "raftUntil[hero.id] = nil", 1, true) ~= nil,
					"their raft timer goes"
				)
			end
			local sweep = string.match(combatSrc, "local function sweepStale%(now: number%)(.-)\nend")
			check(
				sweep ~= nil and string.find(sweep, "now > g.untilT", 1, true) ~= nil,
				"ended links are swept"
			)
			check(
				sweep ~= nil and string.find(sweep, "raftUntil[id] = nil", 1, true) ~= nil,
				"spent rafts too"
			)
			check(string.find(combatSrc, "sweepStale(t0)", 1, true) ~= nil, "every frame (every 5 s inside)")
		end
	)

	test("Combat fixes: at the field cap a caster's own oldest field goes first", function()
		local a, b = {}, {}
		local list = { { hero = b }, { hero = b }, { hero = a }, { hero = b }, { hero = a } }
		check(CastPlan.evictIndex(list, a) == 3, "the caster's oldest")
		check(CastPlan.evictIndex(list, {}) == 1, "a caster with none: the oldest of all")
		check(
			string.find(combatSrc, "table.remove(fields, CastPlan.evictIndex(fields, hero))", 1, true) ~= nil,
			"addField uses it"
		)
	end)
end

-- the perf pass's checks (fast paths against the slow ones they replace) live in their own file too
(require :: any)("./perf")({ test = test, check = check, near = near, Config = Config });
-- the city and destruction audit (2026-11-18, own file, merges easily); ONLY="City audit" runs just these
(require :: any)("./city_audit_test")({ test = test, check = check, Config = Config, world = world });
-- the side quests' set piece meshes (2026-11-18, own file); ONLY="Set piece art" runs just these
(require :: any)("./setpieces_test")({ test = test, check = check, Config = Config });
-- the 36 weapons' meshes and stances (2026-11-18, own file); ONLY="Weapon art" runs just these
(require :: any)("./weapon_art_test")({ test = test, check = check, Config = Config });
-- the weapons as the game builds them, on Roblox's body (fix-weapons, 2026-11-19); ONLY="Weapon sim"
(require :: any)("./weapon_sim_test")({ test = test, check = check, Config = Config, place = process.args[1] });
-- the gear styles' looks as meshes (2026-11-19, own file); ONLY="Gear art" runs just these
(require :: any)("./gear_art_test")({ test = test, check = check, Config = Config });
-- the escort and hub vehicle meshes (2026-11-18, own file); ONLY="Vehicle art" runs just these
(require :: any)("./vehicles_test")({ test = test, check = check, Config = Config });
(require :: any)("./drive_test")({ test = test, check = check, Config = Config });
-- the activity props' meshes and the crater and crack decals (2026-11-19, own file); ONLY="Activity art" runs these
(require :: any)("./activity_test")({ test = test, check = check, Config = Config });
-- the deep art pass (2026-11-19, own file); ONLY="Deep art" runs just these
(require :: any)("./deep_art_test")({ test = test, check = check, Config = Config });
-- the side quest juice pass and the beacon roof fix (2026-11-18); ONLY="SQ juice" or ONLY="Beacon roofs"
(require :: any)("./polish_test")({ test = test, check = check, Config = Config, world = world });
-- the text pass (2026-11-18, own file): old names, fixed typos and term casing; ONLY="Text pass" runs these
(require :: any)("./text_test")({ test = test, check = check, Config = Config });
-- the onboarding check (overnight item 8, 2026-11-18, own file); ONLY="Onboarding" runs just these
(require :: any)("./onboarding_test")({ test = test, check = check, Config = Config, world = world });
-- the hero creator's art (overnight item 12, 2026-11-18, own file); ONLY="Creator art" runs just these
(require :: any)("./creator_art_test")({ test = test, check = check, Config = Config });
-- the picture tiles (2026-11-19, own file); ONLY="Thumbs" runs just these
(require :: any)("./thumbs_test")({ test = test, check = check, Config = Config });
-- the seams review of tonight's packages (2026-11-18, own file); ONLY="Review" runs just these
(require :: any)("./review_test")({ test = test, check = check, Config = Config });
-- the HQ art pass (2026-11-18, own file); ONLY="HQ art" runs just these
(require :: any)("./hqart_test")({ test = test, check = check, Config = Config });
(require :: any)("./hideout_test")({ test = test, check = check, Config = Config });
-- walls (nate's playtest 2026-11-18: robots walked through walls; the subway fight); ONLY="Walls" runs these
(require :: any)("./walls_test")({ test = test, check = check, Config = Config });
-- Super-speed's running jump (nate's playtest 2026-11-18); ONLY="Speed hop" runs these
(require :: any)("./hop_test")({ test = test, check = check, Config = Config });
-- every power path's own hero moves (nate's playtest 2026-11-18); ONLY="Power anims" runs these
(require :: any)("./anim_test")({ test = test, check = check, Config = Config });
-- the enemy motion pass (2026-11-18, own file); ONLY="Enemy motion" runs just these
(require :: any)("./motion_test")({ test = test, check = check, Config = Config });
-- the movement fixes (nate's playtest 2026-11-19: tunnel, slide, swing, leap, wall runs); ONLY="Move fixes"
(require :: any)("./move_fixes_test")({ test = test, check = check, Config = Config });
-- more destruction and momentum impact (nate's playtest 2026-11-19); ONLY="Impact" runs these
(require :: any)("./impact_test")({ test = test, check = check, Config = Config, world = world });
-- fix-destroy (nate after gaps7: fly through buildings, everything destructible, terrain craters, billboards);
-- ONLY="Destroy" runs these
(require :: any)("./destroy_test")({
	test = test,
	check = check,
	Config = Config,
	world = world,
	placePath = placePath,
});
(require :: any)("./boss_counter_test")({ test = test, check = check, Config = Config, world = world });
-- lock-on, omnidirectional movement, knockback by move, the block key, drops and swinging robots (nate's
-- playtest 2026-11-19, own file); ONLY="PT combat" runs these
(require :: any)("./combat_pt_test")({ test = test, check = check, Config = Config });
-- Spider-Man swinging (nate's playtest 2026-11-19, own file); ONLY="Swing" runs these
(require :: any)("./swing_test")({ test = test, check = check, Config = Config, world = world });
-- the comic icon set (gap-icons, 2026-11-19, own file); ONLY="Icons" runs just these
(require :: any)("./icons_test")({ test = test, check = check, Config = Config });
-- every ability's own look (nate's playtest 2026-11-19: more unique effects); ONLY="FX unique" runs these
(require :: any)("./fx_unique_test")({ test = test, check = check, Config = Config });
-- the animation and weapons polish pass (2026-11-19, own file); ONLY="Anim pass" runs just these
(require :: any)("./anim_pass_test")({ test = test, check = check, Config = Config });
-- the boss pass (2026-11-19, own file): boss animation, telegraphs, the surge wave and the Blackout; ONLY="Boss anim"
(require :: any)("./boss_anim_test")({ test = test, check = check, Config = Config });
-- pt-anims (nate's playtest 2026-11-19, own file): the upper-body layer, two-handed holds, robot and people clips;
-- ONLY="PT anims" runs just these
(require :: any)("./anims_pt_test")({ test = test, check = check, Config = Config });
-- fix-anims (nate's playtest 2026-11-19, own file): the real client boot and key path on both joint kinds;
-- ONLY="Fix anims" runs just these
(require :: any)("./fix_anims_test")({
	test = test,
	check = check,
	Config = Config,
	placePath = process.args[1],
});
-- the gap polish (2026-11-19, own file): travel flight, gadgets, crack, ice, crate, loading card; ONLY="Gap polish"
(require :: any)("./gap_polish_test")({
	test = test,
	check = check,
	Config = Config,
	placePath = process.args[1],
});
-- the city life pass: citizens on Roblox's clips and the comic city map (2026-11-19); ONLY="City life"
(require :: any)("./life_test")({ test = test, check = check, Config = Config });
-- the Ceremony prologue's art pass (gap-prologue, 2026-11-19, own file); ONLY="Prologue art" runs just these
(require :: any)("./prologue_art_test")({ test = test, check = check, Config = Config, placePath = placePath });
-- the in-city news's art pass (gap-news, 2026-11-19, own file); ONLY="News art" runs just these
(require :: any)("./news_art_test")({ test = test, check = check, Config = Config, placePath = placePath });
-- the wrecks and Crater art pass (gap-wrecks, 2026-11-19, own file); ONLY="Wreck art" or ONLY="Crater art"
(require :: any)("./wrecks_art_test")({ test = test, check = check, Config = Config, placePath = placePath });
-- the Crater ground, burn scars and throw particles (gap-fx3, 2026-11-19, own file); ONLY="Crater ground" or ONLY="Throw fx"
(require :: any)("./crater_ground_test")({
	test = test,
	check = check,
	Config = Config,
	placePath = placePath,
});
-- the story art pass (gap-story, 2026-11-19, own file); ONLY="Story art" runs just these
(require :: any)("./story_art_test")({ test = test, check = check, Config = Config, placePath = placePath });
-- the pocket props and the plaza board's art pass (gap-props2, 2026-11-19, own file); ONLY="Pocket props" or ONLY="Board art"
(require :: any)("./pocket_props_test")({ test = test, check = check, Config = Config, placePath = placePath });
-- the villain name cards and catalog beards (gap-villains, 2026-11-19, own file); ONLY="Villain cards" or ONLY="Catalog beards"
(require :: any)("./villains_test")({ test = test, check = check, Config = Config });
-- nate's playtest 2026-11-19 (pt-ui, own file): the popup line, every card closes, the contest's skipped card,
-- building textures; ONLY="pt-ui"
(require :: any)("./pt_ui_test")({
	test = test,
	check = check,
	Config = Config,
	world = world,
	placePath = placePath,
});
-- nate's playtest of gaps7 2026-11-19 (fix-hud, own file): every popup dismissable (X, tap, Backspace, Settings
-- Popups), the boss bar only near the fight, double stamina; ONLY="fix-hud"
(require :: any)("./fix_hud_test")({ test = test, check = check, Config = Config, placePath = placePath });
-- nate's playtest 2026-11-19 (pt-city, own file): Downtown and Uptown 1.5x bigger, the street and roof pieces
-- heroes use or break; ONLY="City play"
(require :: any)("./city_play_test")({ test = test, check = check, Config = Config, world = world });

-- fix-carry (2026-11-19, own file): picked-up things held in the hands, telekinesis floats; ONLY="Carry"
(require :: any)("./carry_test")({ test = test, check = check, Config = Config, placePath = placePath })

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
