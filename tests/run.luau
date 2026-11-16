-- Unit and sim tests for the pure modules, run outside Studio with Lune:  lune run tests/run.luau
-- Optional: pass a built place file to also check the Rojo layout:
--   lune run tests/run.luau build/Capeline.rbxl
-- ONLY=M1 lune run tests/run.luau  runs just the tests whose name contains "M1"

local process = require("@lune/process")

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
				{ "Ui", "Kit" },
				{ "Ui", "Hud" },
				{ "Ui", "DevPanel" },
			}
		do
			local folder = client and client:FindFirstChild(path[1])
			check(folder ~= nil and folder:FindFirstChild(path[2]) ~= nil, path[1] .. "." .. path[2])
		end
		local first = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingScreen")
		check(first ~= nil and first.ClassName == "LocalScript", "ReplicatedFirst.LoadingScreen")
		check(game:GetService("Workspace").StreamingEnabled == true, "StreamingEnabled on")
	end)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
