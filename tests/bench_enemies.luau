-- Robot AI bench (not in the default suite):  lune run tests/bench_enemies.luau [seconds]
-- EnemySim with 150 robots and 30 heroes for 60 simulated seconds, stepped at the server's Heartbeat (60 Hz;
-- each robot thinks at Enemies.tickRate). Heroes circle the streets (a third of them flying, a few swimming),
-- hit a random robot now and then (so Medics mend, robots fall and are replaced, stuns break aims) and the
-- server's Enemy.Delta is encoded for every hero at 10 Hz. Prints ms per step for the mixed scene of all 18
-- kinds, for the old 9 kinds only, and for each kind alone, plus Enemy.Delta bytes a second.

local process = require("@lune/process")

local Config = require("../src/config")
local EnemySim = require("../src/shared/EnemySim")
local EnemyBuffer = require("../src/shared/EnemyBuffer")
local Rng = require("../src/shared/Rng")

local SECONDS = tonumber(process.args[1] or "") or 60
local ROBOTS, HEROES, HZ = 150, 30, 60
local WATER_X = 260 -- the sea starts here (the sea robots and the swimmers)

-- a grid city: 40-stud blocks 30 tall with 20-stud streets
local function heightAt(x: number, z: number): number
	if x >= WATER_X then
		return -40 -- the seabed
	end
	local gx, gz = (x + 1000) % 60, (z + 1000) % 60
	if gx >= 20 and gz >= 20 then
		return 30
	end
	return 0
end
local waterTop = Config.World.coast.waterY
local function water(x: number, y: number, _z: number): boolean
	return x >= WATER_X and y < waterTop
end

local function street(rng: any): (number, number)
	local x = (Rng.int(rng, -4, 3)) * 60 + Rng.next(rng) * 18 + 1
	local z = (Rng.int(rng, -4, 3)) * 60 + Rng.next(rng) * 160
	return x, z
end

local OLD = {}
local NEW = {}
for _, kind in Config.Enemies.order do
	if (Config.Enemies[kind].typeId or 0) <= 9 then
		table.insert(OLD, kind)
	else
		table.insert(NEW, kind)
	end
end

local function scene(kinds: { string }, seconds: number): (number, number, number, number)
	local saved = Config.Enemies.caps.perServer
	Config.Enemies.caps.perServer = 400
	local rng = Rng.new(7)
	local sim = EnemySim.new(Config, {
		heightAt = heightAt,
		water = water,
		random = function()
			return Rng.next(rng)
		end,
	})
	local tag = 1
	local function spawnOne(kind: string)
		local cfg = Config.Enemies[kind]
		local x, z
		if cfg.sea then
			x, z = WATER_X + 20 + Rng.next(rng) * 150, (Rng.next(rng) - 0.5) * 300
		else
			x, z = street(rng)
		end
		local y = if cfg.ai == "flyer" then (if cfg.sea then -30 else 30) else (if cfg.sea then -40 else 0)
		local e = EnemySim.spawn(sim, kind, x, y, z, 20)
		if e then
			e.tag = tag
			tag = tag % 12 + 1 -- a dozen sites' worth of squads
		end
	end
	local k = 0
	while #sim.enemies < ROBOTS do
		k += 1
		spawnOne(kinds[(k - 1) % #kinds + 1])
	end
	local heroes = {}
	for i = 1, HEROES do
		local x, z = street(rng)
		local swim = i > HEROES - 3 and #kinds > 9
		table.insert(heroes, {
			id = i,
			x = if swim then WATER_X + 60 else x,
			y = if swim then -20 elseif i % 3 == 0 then 40 else 3,
			z = z,
			alive = true,
			lx = 0,
			lz = -1,
			cx = if swim then WATER_X + 60 else x,
			cz = z,
			fly = i % 3 == 0,
			swim = swim,
		})
	end
	local dt = 1 / HZ
	local t = 0
	local acc = 0
	local stepTime, stepN = 0, 0
	local bytes, events = 0, 0
	local seq = 0
	while t < seconds do
		t += dt
		for i, h in heroes do
			local a = t * 0.3 + i
			h.x, h.z = h.cx + math.cos(a) * 25, h.cz + math.sin(a) * 25
			h.lx, h.lz = -math.sin(a), math.cos(a)
		end
		local t0 = os.clock()
		EnemySim.step(sim, t, heroes)
		stepTime += os.clock() - t0
		stepN += 1
		acc += dt
		if acc >= 0.1 then
			acc -= 0.1
			-- the heroes' hits: 12 a tick on random robots, a stun now and then; the fallen are replaced
			for _ = 1, 12 do
				local e = sim.enemies[Rng.int(rng, 1, #sim.enemies)]
				if e then
					local h = heroes[Rng.int(rng, 1, #heroes)]
					EnemySim.damage(sim, e.id, e.maxHealth * 0.08, h.id, h.x, h.z)
				end
			end
			local s = sim.enemies[Rng.int(rng, 1, #sim.enemies)]
			if s and Rng.next(rng) < 0.3 then
				EnemySim.applyStatus(sim, s.id, "stun", 0.5)
			end
			for _, ev in EnemySim.drainEvents(sim) do
				events += 1
				if ev.k == "die" then
					spawnOne(ev.kind)
				end
			end
			seq += 1
			for _, h in heroes do
				local b = EnemyBuffer.encodeFor(
					seq,
					t,
					sim.enemies,
					h.x,
					h.y,
					h.z,
					Config.Net.enemyRelevance,
					Config.Presets.high.enemiesDrawn
				)
				bytes += buffer.len(b)
			end
		end
	end
	Config.Enemies.caps.perServer = saved
	return stepTime / stepN * 1000, bytes / seconds, events / seconds, #sim.enemies
end

print(string.format("Robot AI bench: %d robots, %d heroes, %d s at %d Hz", ROBOTS, HEROES, SECONDS, HZ))
local all = table.clone(OLD)
for _, k in NEW do
	table.insert(all, k)
end
local mixMs, mixBytes, mixEv = scene(all, SECONDS)
local oldMs, oldBytes, oldEv = scene(OLD, SECONDS)
print(
	string.format(
		"  all 18 kinds: %.3f ms a step (x%d = %.2f ms of AI a second), Enemy.Delta %.0f KB/s to 30 heroes (%.1f KB/s each), %d events/s",
		mixMs,
		HZ,
		mixMs * HZ,
		mixBytes / 1024,
		mixBytes / 1024 / HEROES,
		mixEv
	)
)
print(
	string.format(
		"  old 9 kinds:  %.3f ms a step (x%d = %.2f ms of AI a second), Enemy.Delta %.0f KB/s, %d events/s; new/old %.2fx",
		oldMs,
		HZ,
		oldMs * HZ,
		oldBytes / 1024,
		oldEv,
		mixMs / oldMs
	)
)
print("  each kind alone (150 of it):")
local per = math.max(5, SECONDS // 4)
for _, kind in all do
	local ms = scene({ kind }, per)
	print(string.format("    %-14s %.3f ms a step", kind, ms))
end
