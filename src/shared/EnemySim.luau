--!strict
-- EnemySim: machine enemies as plain data (spec: Enemies). The server runs it at World.Tick 10 Hz with at
-- most 40 AI updates per frame (the rest wait their turn) and replicates positions with EnemyBuffer; Lune
-- runs it headless in the tests. No Roblox instances in here.
-- States on the wire: 1 Patrol, 2 Chase, 3 Attack, 4 Flee, 5 Dead.
-- Enemies are machines only and never hurt citizens (spec: Choices baked in).

local Formulas = if script then require(script.Parent.Formulas) else (require :: any)("./Formulas")

local EnemySim = {}

EnemySim.PATROL, EnemySim.CHASE, EnemySim.ATTACK, EnemySim.FLEE, EnemySim.DEAD = 1, 2, 3, 4, 5

export type Hero = { id: number, x: number, y: number, z: number, alive: boolean }

export type Enemy = {
	id: number,
	kind: string,
	cfg: any,
	typeId: number,
	level: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	homeX: number,
	homeY: number,
	homeZ: number,
	wpX: number,
	wpY: number,
	wpZ: number,
	wpUntil: number,
	health: number,
	maxHealth: number,
	state: number,
	target: number?,
	nextTick: number,
	lastTick: number,
	burstLeft: number,
	nextShot: number,
	nextBurst: number,
	fleeUntil: number,
	fled: boolean,
	orbitDir: number,
	orbitFlip: number,
	alive: boolean,
	lastHeroNear: number,
}

export type Shot = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	life: number,
	damage: number,
	enemyId: number,
	radius: number,
}

export type Sim = {
	config: any,
	enemies: { Enemy },
	byId: { [number]: Enemy },
	shots: { Shot },
	events: { any },
	nextId: number,
	cursor: number,
	now: number,
	lastStep: number,
	heightAt: (x: number, z: number) -> number,
	heroMeta: { [number]: { nextSpawn: number } },
	rngNext: () -> number,
	ticksLastStep: number,
}

local function dist3(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- opts.heightAt(x, z): roof or ground height there (the city), opts.random(): 0..1 (seeded in tests)
function EnemySim.new(config: any, opts: { [string]: any }?): Sim
	local o = opts or {}
	local seed = 12345
	local function lcg(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	return {
		config = config,
		enemies = {},
		byId = {},
		shots = {},
		events = {},
		nextId = 1,
		cursor = 1,
		now = 0,
		lastStep = 0,
		heightAt = o.heightAt or function()
			return 0
		end,
		heroMeta = {},
		rngNext = o.random or lcg,
		ticksLastStep = 0,
	}
end

local function allocId(sim: Sim): number
	-- ids wrap inside u16 and skip ones still alive
	for _ = 1, 65535 do
		local id = sim.nextId
		sim.nextId = if id >= 65535 then 1 else id + 1
		if not sim.byId[id] then
			return id
		end
	end
	error("EnemySim: no free id")
end

function EnemySim.count(sim: Sim): number
	return #sim.enemies
end

function EnemySim.spawn(sim: Sim, kind: string, x: number, y: number, z: number, level: number?): Enemy?
	local cfg = sim.config.Enemies[kind]
	assert(cfg, "unknown enemy " .. kind)
	if #sim.enemies >= sim.config.Enemies.caps.perServer then
		return nil
	end
	local lvl = level or 1
	local hp = Formulas.enemyHealth(sim.config, kind, lvl)
	local e: Enemy = {
		id = allocId(sim),
		kind = kind,
		cfg = cfg,
		typeId = cfg.typeId,
		level = lvl,
		x = x,
		y = y,
		z = z,
		vx = 0,
		vy = 0,
		vz = 0,
		homeX = x,
		homeY = y,
		homeZ = z,
		wpX = x,
		wpY = y,
		wpZ = z,
		wpUntil = 0,
		health = hp,
		maxHealth = hp,
		state = EnemySim.PATROL,
		target = nil,
		nextTick = sim.now,
		lastTick = sim.now,
		burstLeft = 0,
		nextShot = 0,
		nextBurst = sim.now + 1 + sim.rngNext(),
		fleeUntil = 0,
		fled = false,
		orbitDir = if sim.rngNext() < 0.5 then 1 else -1,
		orbitFlip = sim.now + 3,
		alive = true,
		lastHeroNear = sim.now,
	}
	table.insert(sim.enemies, e)
	sim.byId[e.id] = e
	table.insert(sim.events, { k = "spawn", e = e.id })
	return e
end

local function removeAt(sim: Sim, index: number)
	local e = sim.enemies[index]
	sim.byId[e.id] = nil
	table.remove(sim.enemies, index)
	if sim.cursor > index then
		sim.cursor -= 1
	end
end

-- Damage from the Combat service. Returns killed, the enemy (nil if unknown or dead already).
function EnemySim.damage(sim: Sim, id: number, amount: number, attacker: number?): (boolean, Enemy?)
	local e = sim.byId[id]
	if not e or not e.alive then
		return false, nil
	end
	e.health -= amount
	if attacker and not e.target then
		e.target = attacker -- getting hit draws aggro
	end
	if e.health <= 0 then
		e.health = 0
		e.alive = false
		e.state = EnemySim.DEAD
		table.insert(
			sim.events,
			{ k = "die", e = e.id, x = e.x, y = e.y, z = e.z, by = attacker, kind = e.kind }
		)
		for i, other in sim.enemies do
			if other == e then
				removeAt(sim, i)
				break
			end
		end
		return true, e
	end
	return false, e
end

-- Shift an enemy (Dash Strike knock, later knockback arcs)
function EnemySim.push(sim: Sim, id: number, dx: number, dy: number, dz: number)
	local e = sim.byId[id]
	if e and e.alive then
		e.x += dx
		e.y = math.max(sim.heightAt(e.x, e.z) + 3, e.y + dy)
		e.z += dz
	end
end

local function findHero(heroes: { Hero }, id: number?): Hero?
	if not id then
		return nil
	end
	for _, h in heroes do
		if h.id == id then
			return h
		end
	end
	return nil
end

local function moveToward(sim: Sim, e: Enemy, tx: number, ty: number, tz: number, speed: number, dt: number)
	local dx, dy, dz = tx - e.x, ty - e.y, tz - e.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	local wantX, wantY, wantZ = 0, 0, 0
	if d > 0.5 then
		local s = math.min(speed, d / math.max(dt, 1e-3))
		wantX, wantY, wantZ = dx / d * s, dy / d * s, dz / d * s
	end
	-- smooth acceleration so motion reads as flying, not snapping
	local k = math.min(1, dt * 4)
	e.vx += (wantX - e.vx) * k
	e.vy += (wantY - e.vy) * k
	e.vz += (wantZ - e.vz) * k
	e.x += e.vx * dt
	e.y += e.vy * dt
	e.z += e.vz * dt
	local floor = sim.heightAt(e.x, e.z) + 4
	if e.y < floor then
		e.y = floor
		e.vy = math.max(0, e.vy)
	end
end

local function separate(sim: Sim, e: Enemy)
	for _, o in sim.enemies do
		if o ~= e and o.alive then
			local dx, dy, dz = e.x - o.x, e.y - o.y, e.z - o.z
			local d2 = dx * dx + dy * dy + dz * dz
			if d2 < 36 and d2 > 1e-4 then
				local d = math.sqrt(d2)
				local push = (6 - d) * 0.5
				e.x += dx / d * push
				e.y += dy / d * push
				e.z += dz / d * push
			end
		end
	end
end

local function fire(sim: Sim, e: Enemy, h: Hero)
	local cfg = e.cfg
	local dx, dy, dz = h.x - e.x, (h.y + 1.5) - e.y, h.z - e.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-3 then
		return
	end
	local s = cfg.shotSpeed
	local shot: Shot = {
		x = e.x,
		y = e.y,
		z = e.z,
		vx = dx / d * s,
		vy = dy / d * s,
		vz = dz / d * s,
		life = cfg.attackRange * 1.6 / s,
		damage = Formulas.enemyDamage(sim.config, e.kind, e.level),
		enemyId = e.id,
		radius = cfg.shotRadius,
	}
	table.insert(sim.shots, shot)
	table.insert(sim.events, {
		k = "shot",
		e = e.id,
		x = shot.x,
		y = shot.y,
		z = shot.z,
		vx = shot.vx,
		vy = shot.vy,
		vz = shot.vz,
	})
end

local function attackersOf(sim: Sim, heroId: number, except: Enemy): number
	local n = 0
	for _, o in sim.enemies do
		if
			o ~= except
			and o.alive
			and o.target == heroId
			and (o.state == EnemySim.ATTACK or o.state == EnemySim.CHASE)
		then
			n += 1
		end
	end
	return n
end

local function think(sim: Sim, e: Enemy, heroes: { Hero }, dt: number)
	local cfg = e.cfg
	local now = sim.now
	local caps = sim.config.Enemies.caps

	-- target upkeep
	local target = findHero(heroes, e.target)
	if
		target and (not target.alive or dist3(e.x, e.y, e.z, target.x, target.y, target.z) > cfg.aggro * 1.6)
	then
		target = nil
		e.target = nil
	end
	if not target then
		local best, bestD = nil, cfg.aggro
		for _, h in heroes do
			if h.alive then
				local d = dist3(e.x, e.y, e.z, h.x, h.y, h.z)
				if d < bestD and attackersOf(sim, h.id, e) < caps.attackingOneHero then
					best, bestD = h, d
				end
			end
		end
		target = best
		e.target = if best then best.id else nil
	end

	local nearestHero = math.huge
	for _, h in heroes do
		if h.alive then
			nearestHero = math.min(nearestHero, dist3(e.x, e.y, e.z, h.x, h.y, h.z))
		end
	end
	if nearestHero < 500 then
		e.lastHeroNear = now
	end

	-- flee once when badly hurt
	if not e.fled and e.health / e.maxHealth < cfg.fleeBelow and target then
		e.fled = true
		e.fleeUntil = now + cfg.fleeTime
	end

	if e.fleeUntil > now and target then
		e.state = EnemySim.FLEE
		local dx, dz = e.x - target.x, e.z - target.z
		local d = math.max(1, math.sqrt(dx * dx + dz * dz))
		moveToward(sim, e, e.x + dx / d * 30, target.y + 20, e.z + dz / d * 30, cfg.speed, dt)
		return
	end

	if not target then
		e.state = EnemySim.PATROL
		if now >= e.wpUntil then
			local ang = sim.rngNext() * math.pi * 2
			local r = 10 + sim.rngNext() * 30
			e.wpX = e.homeX + math.cos(ang) * r
			e.wpZ = e.homeZ + math.sin(ang) * r
			local hover = cfg.hover.min + sim.rngNext() * (cfg.hover.max - cfg.hover.min)
			e.wpY = sim.heightAt(e.wpX, e.wpZ) + hover
			e.wpUntil = now + 3 + sim.rngNext() * 2
		end
		moveToward(sim, e, e.wpX, e.wpY, e.wpZ, cfg.speed * 0.4, dt)
		return
	end

	local d = dist3(e.x, e.y, e.z, target.x, target.y, target.z)
	local floor = sim.heightAt(target.x, target.z)
	if d > cfg.attackRange then
		e.state = EnemySim.CHASE
		moveToward(sim, e, target.x, math.max(target.y + 8, floor + 8), target.z, cfg.speed, dt)
		return
	end

	-- attack: strafe around the hero at orbit distance and fire bursts
	e.state = EnemySim.ATTACK
	if now >= e.orbitFlip then
		e.orbitDir = -e.orbitDir
		e.orbitFlip = now + 2.5 + sim.rngNext() * 2
	end
	local ox, oz = e.x - target.x, e.z - target.z
	local ol = math.max(1, math.sqrt(ox * ox + oz * oz))
	local want = math.clamp(ol, cfg.orbit.min, cfg.orbit.max)
	local tangX, tangZ = -oz / ol * e.orbitDir, ox / ol * e.orbitDir
	local px = target.x + ox / ol * want + tangX * 12
	local pz = target.z + oz / ol * want + tangZ * 12
	moveToward(sim, e, px, math.max(target.y + 6, floor + 6), pz, cfg.speed, dt)

	if e.burstLeft <= 0 and now >= e.nextBurst then
		e.burstLeft = cfg.burst.shots
		e.nextShot = now
		e.nextBurst = now + cfg.burst.every
	end
	if e.burstLeft > 0 and now >= e.nextShot then
		fire(sim, e, target)
		e.burstLeft -= 1
		e.nextShot = now + cfg.burst.gap
	end
end

local function stepShots(sim: Sim, heroes: { Hero }, dt: number)
	local i = 1
	while i <= #sim.shots do
		local s = sim.shots[i]
		s.x += s.vx * dt
		s.y += s.vy * dt
		s.z += s.vz * dt
		s.life -= dt
		local done = s.life <= 0
		if not done then
			for _, h in heroes do
				if h.alive and dist3(s.x, s.y, s.z, h.x, h.y + 1.5, h.z) <= s.radius then
					table.insert(sim.events, { k = "hit", hero = h.id, damage = s.damage, e = s.enemyId })
					done = true
					break
				end
			end
		end
		if not done and s.y < sim.heightAt(s.x, s.z) then
			done = true -- hit a building or the street
		end
		if done then
			table.remove(sim.shots, i)
		else
			i += 1
		end
	end
end

-- Advance to `now`. Shots move every call; at most `maxTicks` enemies think this call, each at 10 Hz.
function EnemySim.step(sim: Sim, now: number, heroes: { Hero }, maxTicks: number?)
	local dt = math.clamp(now - sim.lastStep, 0, 0.25)
	sim.lastStep = now
	sim.now = now
	stepShots(sim, heroes, dt)
	local budget = maxTicks or sim.config.Enemies.caps.aiTicksPerFrame
	local interval = 1 / sim.config.Enemies.tickRate
	local n = #sim.enemies
	local ticks = 0
	local visited = 0
	while ticks < budget and visited < n do
		if sim.cursor > #sim.enemies then
			sim.cursor = 1
		end
		local e = sim.enemies[sim.cursor]
		sim.cursor += 1
		visited += 1
		if e and e.alive and now >= e.nextTick then
			local edt = math.clamp(now - e.lastTick, 0, 0.3)
			e.lastTick = now
			e.nextTick = now + interval
			think(sim, e, heroes, edt)
			separate(sim, e)
			ticks += 1
		end
	end
	sim.ticksLastStep = ticks
end

-- Alive enemies as hit-query candidates
function EnemySim.candidates(sim: Sim): { any }
	local out = table.create(#sim.enemies)
	for _, e in sim.enemies do
		if e.alive then
			table.insert(out, { id = e.id, x = e.x, y = e.y, z = e.z, r = e.cfg.radius or 2.5 })
		end
	end
	return out
end

-- M1 stand-in for the incident spawner (M6): keep `count` drones within `radius` of every hero, spawning
-- them out of sight at `minDistance` or more, and clear drones nobody has been near for 30 s.
function EnemySim.populate(sim: Sim, heroes: { Hero }, now: number, kind: string?)
	local cfg = sim.config.Enemies.nearHero
	local enemyKind = kind or "SparkDrone"
	local ecfg = sim.config.Enemies[enemyKind]
	for _, h in heroes do
		if h.alive then
			local meta = sim.heroMeta[h.id]
			if not meta then
				meta = { nextSpawn = now + 1 }
				sim.heroMeta[h.id] = meta
			end
			local near = 0
			for _, e in sim.enemies do
				if e.alive and dist3(e.x, e.y, e.z, h.x, h.y, h.z) <= cfg.radius then
					near += 1
				end
			end
			if near < cfg.count and now >= meta.nextSpawn then
				local ang = sim.rngNext() * math.pi * 2
				local r = cfg.minDistance + sim.rngNext() * (cfg.radius - cfg.minDistance)
				local x, z = h.x + math.cos(ang) * r, h.z + math.sin(ang) * r
				local y = sim.heightAt(x, z)
					+ ecfg.hover.min
					+ sim.rngNext() * (ecfg.hover.max - ecfg.hover.min)
				if EnemySim.spawn(sim, enemyKind, x, y, z, 1) then
					meta.nextSpawn = now + cfg.respawn / cfg.count
				end
			end
		end
	end
	for i = #sim.enemies, 1, -1 do
		local e = sim.enemies[i]
		if now - e.lastHeroNear > 30 then
			table.insert(sim.events, { k = "despawn", e = e.id })
			removeAt(sim, i)
		end
	end
end

function EnemySim.forgetHero(sim: Sim, heroId: number)
	sim.heroMeta[heroId] = nil
	for _, e in sim.enemies do
		if e.target == heroId then
			e.target = nil
		end
	end
end

function EnemySim.drainEvents(sim: Sim): { any }
	local ev = sim.events
	sim.events = {}
	return ev
end

return EnemySim
