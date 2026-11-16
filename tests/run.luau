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

test("config: every module loads; 32 abilities with unique network ids", function()
	check(#Config.Abilities.order == 32, "32 abilities")
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
