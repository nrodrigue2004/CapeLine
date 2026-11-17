--!strict
-- EnemySim: machine enemies as plain data (spec: Enemies). The server runs it at World.Tick 10 Hz with at
-- most 40 AI updates per frame (the rest wait their turn) and replicates positions with EnemyBuffer; Lune
-- runs it headless in the tests. No Roblox instances in here.
-- Every enemy is a humanoid robot (nate, 2026-11-16); `ai` in Config.Enemies picks its brain:
--   flyer  (Spark Trooper) hovers, chases and strafes while firing 3-shot bursts
--   thief  (Burglar Bot) runs from heroes between loot spots; cornered, it turns and fires a laser
--   sneak  (Sneak Bot) cloaks for 4 s, circles behind the hero and backstabs
--   brute  (Brute Bot) walks in, plants, shows a 0.8 s warning ring, then slams
--   sentry (Sentry) planted; turns 90 degrees/s, fires when lined up; its shield flickers every 6 s
--   guard  (Null Sentinel) blocks hits from the front; a flank hit breaks the guard and stuns it
-- Status effects from heroes (Status): stun, root, slow, knockup, float, pull, blind, taunt.
-- States on the wire: 1 Patrol, 2 Chase, 3 Attack, 4 Flee, 5 Dead.
-- Enemies are machines only and never hurt citizens (spec: Choices baked in).
-- Underwater (Config.Deep): `sea` robots (Diver, Anchor, Torpedo Sentry) spawn near a swimming hero from
-- Deep.mix and stay in the water; land robots never walk into it. opts.water(x, y, z) says what is water.

local Formulas = if script then require(script.Parent.Formulas) else (require :: any)("./Formulas")
local Status = if script then require(script.Parent.Status) else (require :: any)("./Status")

local EnemySim = {}

EnemySim.PATROL, EnemySim.CHASE, EnemySim.ATTACK, EnemySim.FLEE, EnemySim.DEAD = 1, 2, 3, 4, 5

-- The second flags byte on the wire (EnemyBuffer `extra`): what the new robot types are doing
--   aim      a Sniper's laser is on a hero (the AIM event names the hero)
--   rally    a Captain's rally is on this robot (hits harder, moves faster)
--   disguise a Mimic still dressed as a citizen (not a hit target, no health bar)
--   mend     a Medic Unit is repairing a robot (the MEND event names it)
--   lunge    a Swarmer is lunging
--   hooked   a Grappler's hook is out
EnemySim.EXTRA = { aim = 1, rally = 2, disguise = 4, mend = 8, lunge = 16, hooked = 32 }

-- Hit flags returned by damage (sent to clients so a blocked hit reads)
EnemySim.HIT, EnemySim.BLOCKED, EnemySim.BROKE = 0, 1, 2

-- lx, lz: the hero's facing (for backstabs). Optional for old callers.
export type Hero = { id: number, x: number, y: number, z: number, alive: boolean, lx: number?, lz: number? }

export type Enemy = {
	id: number,
	kind: string,
	cfg: any,
	ai: string,
	typeId: number,
	level: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	yaw: number,
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
	status: Status.Book,
	liftBase: number?,
	flags: number,
	-- robot timers
	windupUntil: number, -- brute slam or guard sweep coming
	nextMelee: number,
	cloakUntil: number,
	nextCloak: number,
	shieldUntil: number,
	nextShield: number,
	guardBrokenUntil: number,
	corneredUntil: number,
	lastX: number,
	lastZ: number,
	scripted: boolean?,
	dmgMult: number?, -- the opening's drones: 0 never attacks back, 0.35 a weak one
	hitLife: number?, -- the opening's drones: any hit takes this share of its health (2 hits, 4 hits)
	tag: number?, -- the incident, contract site or event that spawned it
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
	home: number?, -- a torpedo: the hero it turns after
	turn: number?, -- radians per second it can turn
}

export type Blocker = { x: number, y: number, z: number, r: number, untilT: number }

export type Sim = {
	config: any,
	enemies: { Enemy },
	byId: { [number]: Enemy },
	shots: { Shot },
	blockers: { Blocker },
	events: { any },
	nextId: number,
	cursor: number,
	now: number,
	lastStep: number,
	heightAt: (x: number, z: number, y: number?) -> number, -- y: the asker's height (mission pockets)
	water: (x: number, y: number, z: number) -> boolean, -- underwater play space (Shared.DeepLayout)
	waterTop: number, -- sea robots keep below this
	heroMeta: { [number]: { nextSpawn: number } },
	rngNext: () -> number,
	ticksLastStep: number,
}

local function dist3(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function dist2(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- yaw 0 faces -Z (Roblox's forward); yaw grows toward -X
local function yawTo(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function yawDir(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
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
		blockers = {},
		events = {},
		nextId = 1,
		cursor = 1,
		now = 0,
		lastStep = 0,
		heightAt = o.heightAt or function()
			return 0
		end,
		water = o.water or function()
			return false
		end,
		waterTop = (if config.World then config.World.coast.waterY else 0) - 3,
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

-- Half the body height: ground robots keep their centre this far above the floor
local function halfHeight(cfg: any): number
	return if cfg.body then cfg.body.height * 0.5 else 2.5
end
EnemySim.halfHeight = halfHeight

function EnemySim.spawn(sim: Sim, kind: string, x: number, y: number, z: number, level: number?): Enemy?
	local cfg = sim.config.Enemies[kind]
	assert(cfg, "unknown enemy " .. kind)
	if #sim.enemies >= sim.config.Enemies.caps.perServer then
		return nil
	end
	local lvl = level or 1
	local hp = Formulas.enemyHealth(sim.config, kind, lvl)
	local ai = cfg.ai or "flyer"
	local yy = y
	if ai ~= "flyer" then
		yy = sim.heightAt(x, z, y) + halfHeight(cfg)
	end
	local now = sim.now
	local e: Enemy = {
		id = allocId(sim),
		kind = kind,
		cfg = cfg,
		ai = ai,
		typeId = cfg.typeId,
		level = lvl,
		x = x,
		y = yy,
		z = z,
		vx = 0,
		vy = 0,
		vz = 0,
		yaw = sim.rngNext() * math.pi * 2,
		homeX = x,
		homeY = yy,
		homeZ = z,
		wpX = x,
		wpY = yy,
		wpZ = z,
		wpUntil = 0,
		health = hp,
		maxHealth = hp,
		state = EnemySim.PATROL,
		target = nil,
		nextTick = now,
		lastTick = now,
		burstLeft = 0,
		nextShot = 0,
		nextBurst = now + 1 + sim.rngNext(),
		fleeUntil = 0,
		fled = false,
		orbitDir = if sim.rngNext() < 0.5 then 1 else -1,
		orbitFlip = now + 3,
		alive = true,
		lastHeroNear = now,
		status = Status.new(),
		liftBase = nil,
		flags = 0,
		windupUntil = 0,
		nextMelee = now + 1,
		cloakUntil = 0,
		nextCloak = now,
		shieldUntil = 0,
		nextShield = now + (if cfg.shield then cfg.shield.every * sim.rngNext() else 0),
		guardBrokenUntil = 0,
		corneredUntil = 0,
		lastX = x,
		lastZ = z,
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

local function shieldUp(sim: Sim, e: Enemy): boolean
	return e.cfg.shield ~= nil and sim.now < e.shieldUntil
end

local function guardUp(sim: Sim, e: Enemy): boolean
	return e.cfg.guard ~= nil and sim.now >= e.guardBrokenUntil
end

-- Damage from the Combat service. fromX/fromZ: where the hit came from (the Sentinel's guard checks it).
-- Returns killed, the enemy (nil if unknown or dead already), the damage dealt, and a flag (HIT, BLOCKED,
-- BROKE).
function EnemySim.damage(
	sim: Sim,
	id: number,
	amount: number,
	attacker: number?,
	fromX: number?,
	fromZ: number?
): (boolean, Enemy?, number, number)
	local e = sim.byId[id]
	if not e or not e.alive then
		return false, nil, 0, EnemySim.HIT
	end
	local cfg = e.cfg
	local flag = EnemySim.HIT
	local dealt = amount * (1 - (cfg.mitigation or 0))
	if amount == math.huge then
		dealt = math.huge
	elseif shieldUp(sim, e) then
		dealt = 0
		flag = EnemySim.BLOCKED
	elseif guardUp(sim, e) and fromX and fromZ then
		local fx, fz = yawDir(e.yaw)
		local tx, tz = fromX - e.x, fromZ - e.z
		local l = math.sqrt(tx * tx + tz * tz)
		local front = l < 0.5 or (fx * tx + fz * tz) / l >= math.cos(math.rad(cfg.guard.front / 2))
		if front then
			dealt *= 1 - cfg.guard.block
			flag = EnemySim.BLOCKED
		else
			e.guardBrokenUntil = sim.now + cfg.guard.breakTime
			Status.apply(e.status, "stun", cfg.guard.breakStun, sim.now)
			e.windupUntil = 0
			flag = EnemySim.BROKE
		end
	end
	if e.ai == "sneak" and e.cloakUntil > sim.now then
		e.cloakUntil = sim.now -- a hit reveals it
	end
	if e.hitLife and dealt > 0 and dealt ~= math.huge then
		dealt = e.maxHealth / e.hitLife -- a story robot that takes a set number of hits
	end
	e.health -= dealt
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
		return true, e, dealt, flag
	end
	return false, e, dealt, flag
end

-- A status effect from a hero ability. Returns the duration applied (0 if immune or resisted).
function EnemySim.applyStatus(
	sim: Sim,
	id: number,
	kind: string,
	duration: number,
	opts: Status.ApplyOpts?
): number
	local e = sim.byId[id]
	if not e or not e.alive then
		return 0
	end
	local o: Status.ApplyOpts = if opts then table.clone(opts) else {}
	o.resist = e.cfg.ccResist
	o.immune = e.cfg.immune
	local wasLifted = Status.lifted(e.status, sim.now)
	local dur = Status.apply(e.status, kind, duration, sim.now, o)
	if dur > 0 then
		if (kind == "knockup" or kind == "float") and not wasLifted then
			e.liftBase = e.y
		end
		if kind == "stun" or kind == "knockup" or kind == "float" then
			e.windupUntil = 0 -- crowd control interrupts a slam or sweep
			e.burstLeft = 0
		end
	end
	return dur
end

-- Shift an enemy now (small nudges)
function EnemySim.push(sim: Sim, id: number, dx: number, dy: number, dz: number)
	local e = sim.byId[id]
	if e and e.alive then
		if e.cfg.immune and table.find(e.cfg.immune, "knockback") then
			return
		end
		e.x += dx
		e.z += dz
		if e.ai == "flyer" then
			e.y = math.max(sim.heightAt(e.x, e.z, e.y) + 3, e.y + dy)
		else
			e.y = sim.heightAt(e.x, e.z, e.y) + halfHeight(e.cfg)
		end
	end
end

-- Knockback along (dx, dz) for `distance` studs; stops at a building. Returns true when it hit a wall
-- (Shoulder Charge's Wall Breaker stuns then).
function EnemySim.knock(sim: Sim, id: number, dx: number, dz: number, distance: number): boolean
	local e = sim.byId[id]
	if not e or not e.alive or distance <= 0 then
		return false
	end
	if e.cfg.immune and table.find(e.cfg.immune, "knockback") then
		return false
	end
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-4 then
		return false
	end
	dx, dz = dx / l, dz / l
	local moved = 0
	local floorY = e.y - (if e.ai == "flyer" then 2 else halfHeight(e.cfg))
	while moved < distance do
		local step = math.min(2, distance - moved)
		local nx, nz = e.x + dx * step, e.z + dz * step
		if sim.heightAt(nx, nz, e.y) > floorY + 3 then
			return true
		end
		e.x, e.z = nx, nz
		moved += step
	end
	if e.ai ~= "flyer" then
		e.y = sim.heightAt(e.x, e.z, e.y) + halfHeight(e.cfg)
	end
	return false
end

-- Snow Wall pieces stop enemy shots
function EnemySim.addBlocker(sim: Sim, x: number, y: number, z: number, r: number, untilT: number)
	table.insert(sim.blockers, { x = x, y = y, z = z, r = r, untilT = untilT })
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
	local floor = sim.heightAt(e.x, e.z, e.y) + 4
	if e.y < floor then
		e.y = floor
		e.vy = math.max(0, e.vy)
	end
	if e.vx * e.vx + e.vz * e.vz > 4 then
		e.yaw = yawTo(e.vx, e.vz)
	end
end

-- Ground robots walk the streets: they step around buildings (try the wanted heading, then 45, 90 and 135
-- degrees either side) and never climb. Returns the distance actually moved.
local TURNS = { 0, 45, -45, 90, -90, 135, -135 }
local function walk(sim: Sim, e: Enemy, tx: number, tz: number, speed: number, dt: number): number
	local dx, dz = tx - e.x, tz - e.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 0.5 or speed <= 0 then
		e.vx, e.vz = 0, 0
		return 0
	end
	local step = math.min(speed * dt, d)
	local floorY = e.y - halfHeight(e.cfg)
	local base = math.atan2(dz, dx)
	for _, turn in TURNS do
		local a = base + math.rad(turn)
		local ux, uz = math.cos(a), math.sin(a)
		local probe = math.max(step, 3)
		local h = sim.heightAt(e.x + ux * probe, e.z + uz * probe, e.y)
		if h <= floorY + 2.5 then
			e.x += ux * step
			e.z += uz * step
			e.vx, e.vz = ux * speed, uz * speed
			e.y = sim.heightAt(e.x, e.z, e.y) + halfHeight(e.cfg)
			e.yaw = yawTo(ux, uz)
			return step
		end
	end
	e.vx, e.vz = 0, 0
	return 0
end

local function separate(sim: Sim, e: Enemy)
	local flyer = e.ai == "flyer"
	if e.ai == "sentry" then
		return
	end
	for _, o in sim.enemies do
		if o ~= e and o.alive then
			local dx, dy, dz = e.x - o.x, if flyer then e.y - o.y else 0, e.z - o.z
			local d2 = dx * dx + dy * dy + dz * dz
			local min = (e.cfg.radius or 2.5) + (o.cfg.radius or 2.5)
			if d2 < min * min and d2 > 1e-4 then
				local d = math.sqrt(d2)
				local push = (min - d) * 0.5
				local nx, nz = e.x + dx / d * push, e.z + dz / d * push
				if flyer then
					e.x, e.z = nx, nz
					e.y += dy / d * push
				elseif sim.heightAt(nx, nz, e.y) <= e.y - halfHeight(e.cfg) + 2.5 then
					e.x, e.z = nx, nz
				end
			end
		end
	end
end

-- Fire a shot from the enemy toward a point (or along a direction for the sentry)
local function shoot(
	sim: Sim,
	e: Enemy,
	tx: number,
	ty: number,
	tz: number,
	speed: number,
	radius: number,
	range: number,
	coeff: number?,
	home: number?,
	turn: number?
)
	if e.dmgMult == 0 then
		return -- a harmless robot (the opening's first drone) never fires
	end
	local dx, dy, dz = tx - e.x, ty - e.y, tz - e.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-3 then
		return
	end
	dx, dy, dz = dx / d, dy / d, dz / d
	if Status.has(e.status, "blind", sim.now) then
		-- blinded: shots go up to 25 degrees wide
		local a = (sim.rngNext() - 0.5) * math.rad(50)
		dx, dz = dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
		dy += (sim.rngNext() - 0.5) * 0.4
	end
	local damage = Formulas.enemyDamage(sim.config, e.kind, e.level) * (coeff or 1) * (e.dmgMult or 1)
	local muzzle = 1.2
	local shot: Shot = {
		x = e.x + dx * muzzle,
		y = e.y + 0.8,
		z = e.z + dz * muzzle,
		vx = dx * speed,
		vy = dy * speed,
		vz = dz * speed,
		life = range * 1.6 / speed,
		damage = damage,
		enemyId = e.id,
		radius = radius,
		home = home,
		turn = turn,
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
		home = home,
		turn = turn,
	})
end

local function melee(sim: Sim, e: Enemy, h: Hero, coeff: number)
	if e.dmgMult == 0 then
		return
	end
	local damage = (sim.config.Enemies.scale.dmgBase + sim.config.Enemies.scale.dmgPerLevel * e.level)
		* coeff
		* (e.dmgMult or 1)
	table.insert(sim.events, { k = "hit", hero = h.id, damage = damage, e = e.id, melee = true })
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

local function nearestHeroDist(e: Enemy, heroes: { Hero }): number
	local best = math.huge
	for _, h in heroes do
		if h.alive then
			best = math.min(best, dist3(e.x, e.y, e.z, h.x, h.y, h.z))
		end
	end
	return best
end

-- Keep, drop or pick a target. Taunts force one; blind stops new picks.
local function upkeepTarget(sim: Sim, e: Enemy, heroes: { Hero }): Hero?
	local cfg = e.cfg
	local now = sim.now
	local taunt = Status.get(e.status, "taunt", now)
	if taunt and taunt.src then
		local h = findHero(heroes, taunt.src)
		if h and h.alive then
			e.target = h.id
			return h
		end
	end
	local target = findHero(heroes, e.target)
	if
		target and (not target.alive or dist3(e.x, e.y, e.z, target.x, target.y, target.z) > cfg.aggro * 1.6)
	then
		target = nil
		e.target = nil
	end
	if not target and not Status.has(e.status, "blind", now) then
		local caps = sim.config.Enemies.caps
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
	return target
end

local function wander(sim: Sim, e: Enemy, speed: number, dt: number, radius: number)
	local now = sim.now
	if now >= e.wpUntil then
		local ang = sim.rngNext() * math.pi * 2
		local r = 10 + sim.rngNext() * radius
		e.wpX = e.homeX + math.cos(ang) * r
		e.wpZ = e.homeZ + math.sin(ang) * r
		if e.ai == "flyer" then
			local hover = e.cfg.hover.min + sim.rngNext() * (e.cfg.hover.max - e.cfg.hover.min)
			e.wpY = sim.heightAt(e.wpX, e.wpZ, e.y) + hover
		end
		e.wpUntil = now + 3 + sim.rngNext() * 2
	end
	if e.ai == "flyer" then
		moveToward(sim, e, e.wpX, e.wpY, e.wpZ, speed, dt)
	elseif walk(sim, e, e.wpX, e.wpZ, speed, dt) == 0 then
		e.wpUntil = now -- blocked: pick another spot
	end
end

local function turnToward(e: Enemy, tx: number, tz: number, rateDeg: number, dt: number): number
	local want = yawTo(tx - e.x, tz - e.z)
	local diff = wrapAngle(want - e.yaw)
	local maxStep = math.rad(rateDeg) * dt
	e.yaw = wrapAngle(e.yaw + math.clamp(diff, -maxStep, maxStep))
	return math.deg(math.abs(wrapAngle(want - e.yaw)))
end

---------------------------------------------------------------------------
-- Brains
---------------------------------------------------------------------------

local function thinkFlyer(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	if not e.fled and e.health / e.maxHealth < cfg.fleeBelow and target then
		e.fled = true
		e.fleeUntil = now + cfg.fleeTime
	end
	if e.fleeUntil > now and target then
		e.state = EnemySim.FLEE
		if canMove then
			local dx, dz = e.x - target.x, e.z - target.z
			local d = math.max(1, math.sqrt(dx * dx + dz * dz))
			moveToward(sim, e, e.x + dx / d * 30, target.y + 20, e.z + dz / d * 30, speed, dt)
		end
		return
	end
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.4, dt, 30)
		end
		return
	end
	local d = dist3(e.x, e.y, e.z, target.x, target.y, target.z)
	local floor = sim.heightAt(target.x, target.z, target.y)
	if d > cfg.attackRange then
		e.state = EnemySim.CHASE
		if canMove then
			moveToward(sim, e, target.x, math.max(target.y + 8, floor + 8), target.z, speed, dt)
		end
		return
	end
	-- attack: strafe around the hero at orbit distance and fire bursts
	e.state = EnemySim.ATTACK
	if now >= e.orbitFlip then
		e.orbitDir = -e.orbitDir
		e.orbitFlip = now + 2.5 + sim.rngNext() * 2
	end
	if canMove then
		local ox, oz = e.x - target.x, e.z - target.z
		local ol = math.max(1, math.sqrt(ox * ox + oz * oz))
		local want = math.clamp(ol, cfg.orbit.min, cfg.orbit.max)
		local tangX, tangZ = -oz / ol * e.orbitDir, ox / ol * e.orbitDir
		local px = target.x + ox / ol * want + tangX * 12
		local pz = target.z + oz / ol * want + tangZ * 12
		moveToward(sim, e, px, math.max(target.y + 6, floor + 6), pz, speed, dt)
	end
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if e.burstLeft <= 0 and now >= e.nextBurst then
		e.burstLeft = cfg.burst.shots
		e.nextShot = now
		e.nextBurst = now + cfg.burst.every
	end
	if e.burstLeft > 0 and now >= e.nextShot then
		shoot(sim, e, target.x, target.y + 1.5, target.z, cfg.shotSpeed, cfg.shotRadius, cfg.attackRange)
		e.burstLeft -= 1
		e.nextShot = now + cfg.burst.gap
	end
end

local function thinkThief(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.45, dt, cfg.loot) -- trots between loot spots
		end
		return
	end
	local d = dist2(e.x, e.z, target.x, target.z)
	local cornered = d <= cfg.cornered or now < e.corneredUntil
	if not cornered then
		e.state = EnemySim.FLEE
		if canMove then
			local dx, dz = e.x - target.x, e.z - target.z
			local l = math.max(1, math.sqrt(dx * dx + dz * dz))
			local moved = walk(sim, e, e.x + dx / l * 20, e.z + dz / l * 20, speed, dt)
			if moved < speed * dt * 0.3 then
				e.corneredUntil = now + 2.5 -- boxed in: turn and fight
			end
		end
		return
	end
	e.state = EnemySim.ATTACK
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if d <= cfg.attackRange + 4 and now >= e.nextShot then
		shoot(
			sim,
			e,
			target.x,
			target.y + 1.5,
			target.z,
			cfg.fire.shotSpeed,
			cfg.fire.shotRadius,
			cfg.attackRange
		)
		e.nextShot = now + cfg.fire.every
	elseif d > cfg.attackRange and canMove then
		walk(sim, e, target.x, target.z, speed * 0.6, dt)
	end
end

local function behind(h: Hero, e: Enemy, maxAngle: number): boolean
	if not h.lx or not h.lz then
		return false
	end
	local tx, tz = e.x - h.x, e.z - h.z
	local l = math.sqrt(tx * tx + tz * tz)
	if l < 0.1 then
		return true
	end
	local dot = ((h.lx :: number) * tx + (h.lz :: number) * tz) / l
	return dot <= -math.cos(math.rad(maxAngle))
end

local function thinkSneak(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.35, dt, 30)
		end
		return
	end
	if now >= e.nextCloak then
		e.cloakUntil = now + cfg.cloak.time
		e.nextCloak = now + cfg.cloak.every
	end
	local cloaked = now < e.cloakUntil
	-- circle to the hero's back while cloaked, then go straight in
	local gx, gz = target.x, target.z
	local d = dist2(e.x, e.z, target.x, target.z)
	if cloaked and target.lx and target.lz and not behind(target, e, cfg.stab.behindAngle) then
		local fx, fz = target.lx :: number, target.lz :: number
		local sx, sz = -fz, fx
		if (e.x - target.x) * sx + (e.z - target.z) * sz < 0 then
			sx, sz = -sx, -sz -- keep to the side it is already on
		end
		-- wide around the flank, then in at the hero's back quarter
		local side = if d < 14 then 7 else 12
		gx, gz = target.x + sx * side - fx * 3, target.z + sz * side - fz * 3
		e.state = EnemySim.CHASE
		if canMove then
			walk(sim, e, gx, gz, speed, dt)
		end
		return
	end
	if d > cfg.attackRange then
		e.state = EnemySim.CHASE
		if canMove then
			walk(sim, e, gx, gz, speed, dt)
		end
		return
	end
	e.state = EnemySim.ATTACK
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if now >= e.nextMelee and math.abs(target.y - e.y) < 8 then
		local back = behind(target, e, cfg.stab.behindAngle)
		melee(sim, e, target, if back then cfg.stab.backCoeff else cfg.stab.frontCoeff)
		table.insert(sim.events, { k = "swing", e = e.id, back = back })
		e.nextMelee = now + cfg.stab.cooldown
		e.cloakUntil = now -- striking reveals it
	end
end

local function thinkBrute(
	sim: Sim,
	e: Enemy,
	target: Hero?,
	speed: number,
	canMove: boolean,
	dt: number,
	heroes: { Hero }
)
	local cfg = e.cfg
	local now = sim.now
	-- a slam on the way finishes even if the target left
	if e.windupUntil > 0 then
		if now >= e.windupUntil then
			e.windupUntil = 0
			local reach = cfg.slam.radius + sim.config.Enemies.melee.reach
			for _, h in heroes do
				if h.alive and dist2(e.x, e.z, h.x, h.z) <= reach and math.abs(h.y - e.y) <= 7 then
					melee(sim, e, h, cfg.coeff)
				end
			end
			table.insert(
				sim.events,
				{ k = "slam", e = e.id, x = e.x, y = e.y - halfHeight(cfg), z = e.z, r = cfg.slam.radius }
			)
			e.nextMelee = now + cfg.slam.every
		end
		e.state = EnemySim.ATTACK
		return
	end
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.5, dt, 25)
		end
		return
	end
	local d = dist2(e.x, e.z, target.x, target.z)
	if d > cfg.attackRange or math.abs(target.y - e.y) > 10 then
		e.state = EnemySim.CHASE
		if canMove then
			walk(sim, e, target.x, target.z, speed, dt)
		end
		return
	end
	e.state = EnemySim.ATTACK
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if now >= e.nextMelee then
		e.windupUntil = now + cfg.slam.windup
		table.insert(sim.events, {
			k = "warn",
			e = e.id,
			x = e.x,
			y = e.y - halfHeight(cfg),
			z = e.z,
			r = cfg.slam.radius,
			t = cfg.slam.windup,
		})
	end
end

local function thinkSentry(sim: Sim, e: Enemy, target: Hero?, dt: number)
	local cfg = e.cfg
	local now = sim.now
	if now >= e.nextShield then
		e.shieldUntil = now + cfg.shield.time
		e.nextShield = now + cfg.shield.every
	end
	if not target then
		e.state = EnemySim.PATROL
		e.yaw = wrapAngle(e.yaw + math.rad(20) * dt) -- slow scan
		return
	end
	e.state = EnemySim.ATTACK
	local off = turnToward(e, target.x, target.z, cfg.turnRate, dt)
	local d = dist3(e.x, e.y, e.z, target.x, target.y, target.z)
	if off <= cfg.aimCone and d <= cfg.attackRange and now >= e.nextShot then
		-- fires along its facing (pitched at the target), so circling fast beats it
		local fx, fz = yawDir(e.yaw)
		local flatD = dist2(e.x, e.z, target.x, target.z)
		local home = cfg.fire.home -- a torpedo sentry's shots turn after the hero
		shoot(
			sim,
			e,
			e.x + fx * flatD,
			target.y + 1.5,
			e.z + fz * flatD,
			cfg.fire.shotSpeed,
			cfg.fire.shotRadius,
			cfg.attackRange,
			cfg.fire.coeff,
			if home then target.id else nil,
			if home then math.rad(home) else nil
		)
		e.nextShot = now + cfg.fire.every
	end
end

local function thinkGuard(
	sim: Sim,
	e: Enemy,
	target: Hero?,
	speed: number,
	canMove: boolean,
	dt: number,
	heroes: { Hero }
)
	local cfg = e.cfg
	local now = sim.now
	if e.windupUntil > 0 then
		if now >= e.windupUntil then
			e.windupUntil = 0
			local reach = cfg.sweep.radius + sim.config.Enemies.melee.reach
			local fx, fz = yawDir(e.yaw)
			local half = math.cos(math.rad(cfg.sweep.arc / 2))
			for _, h in heroes do
				local dx, dz = h.x - e.x, h.z - e.z
				local l = math.sqrt(dx * dx + dz * dz)
				if
					h.alive
					and l <= reach
					and math.abs(h.y - e.y) <= 7
					and (l < 1 or (fx * dx + fz * dz) / l >= half)
				then
					melee(sim, e, h, cfg.coeff)
				end
			end
			table.insert(sim.events, { k = "swing", e = e.id })
			e.nextMelee = now + cfg.sweep.every
		end
		e.state = EnemySim.ATTACK
		return
	end
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.4, dt, 20)
		end
		return
	end
	-- always turns to face the target: heroes must work around the guard
	turnToward(e, target.x, target.z, cfg.turnRate, dt)
	local keepYaw = e.yaw
	local d = dist2(e.x, e.z, target.x, target.z)
	if d > cfg.attackRange then
		e.state = EnemySim.CHASE
		if canMove then
			walk(sim, e, target.x, target.z, speed, dt)
			e.yaw = keepYaw
		end
		return
	end
	e.state = EnemySim.ATTACK
	if now >= e.nextMelee and math.abs(target.y - e.y) <= 8 then
		e.windupUntil = now + cfg.sweep.windup
		table.insert(sim.events, {
			k = "warn",
			e = e.id,
			x = e.x,
			y = e.y - halfHeight(cfg),
			z = e.z,
			r = cfg.sweep.radius,
			t = cfg.sweep.windup,
			arc = cfg.sweep.arc,
			yaw = e.yaw,
		})
	end
end

local function updateFlags(sim: Sim, e: Enemy)
	local now = sim.now
	local f = Status.flags(e.status, now)
	local B = Status.BITS
	if e.cloakUntil > now then
		f += B.cloak
	end
	if e.windupUntil > now then
		f += B.windup
	end
	if shieldUp(sim, e) or guardUp(sim, e) then
		f += B.shield
	end
	if e.cfg.guard and not guardUp(sim, e) then
		f += B.guardBroken
	end
	e.flags = f
end

-- Sea robots stay in the water (a Diver keeps under the surface); land robots that walk never step into it
local function keepMedium(sim: Sim, e: Enemy, px: number, py: number, pz: number, wasWet: boolean?)
	if e.cfg.sea then
		if e.ai == "flyer" then
			e.y = math.min(e.y, sim.waterTop)
		end
		if wasWet and not sim.water(e.x, e.y, e.z) then
			e.x, e.y, e.z = px, py, pz
		end
	elseif e.ai == "flyer" then
		if sim.water(e.x, e.y, e.z) then
			e.y = sim.waterTop + 8 -- a land flyer skims the surface over a swimming hero
		end
	elseif sim.water(e.x, sim.waterTop + 1, e.z) and not sim.water(px, sim.waterTop + 1, pz) then
		e.x, e.y, e.z = px, py, pz
	end
end

local function think(sim: Sim, e: Enemy, heroes: { Hero }, dt: number)
	local now = sim.now
	local st = e.status
	local kn = sim.config.Abilities.status
	Status.clean(st, now)

	if nearestHeroDist(e, heroes) < 500 then
		e.lastHeroNear = now
	end

	-- lifted: knockup arcs, float holds (no moving or acting)
	if Status.lifted(st, now) then
		e.y = (e.liftBase or e.y) + Status.liftHeight(st, now, kn.knockupHeight, kn.floatHeight)
		e.vx, e.vy, e.vz = 0, 0, 0
		return
	elseif e.liftBase then
		e.y = if e.ai == "flyer"
			then e.liftBase :: number
			else sim.heightAt(e.x, e.z, e.y) + halfHeight(e.cfg)
		e.liftBase = nil
	end

	-- pulled toward a point (Pull, Gravity Well, Singularity)
	local pull = Status.get(st, "pull", now)
	if pull and pull.x then
		local px, py, pz = pull.x :: number, pull.y :: number, pull.z :: number
		local d = dist3(e.x, e.y, e.z, px, py, pz)
		if d > 4 then
			local s = math.min((pull.speed or kn.pullSpeed) * dt, d - 4)
			local nx, nz = e.x + (px - e.x) / d * s, e.z + (pz - e.z) / d * s
			if e.ai == "flyer" then
				e.x, e.z = nx, nz
				e.y += (py - e.y) / d * s
			elseif sim.heightAt(nx, nz, e.y) <= e.y - halfHeight(e.cfg) + 2.5 then
				e.x, e.z = nx, nz
				e.y = sim.heightAt(nx, nz, e.y) + halfHeight(e.cfg)
			end
		end
		e.windupUntil = 0
		return
	end

	if Status.has(st, "stun", now) then
		e.vx, e.vy, e.vz = 0, 0, 0
		return
	end

	local canMove = Status.canMove(st, now)
	local speed = (e.cfg.speed or 0) * Status.speedMult(st, now)
	local target = upkeepTarget(sim, e, heroes)
	local ai = e.ai
	if ai == "flyer" then
		thinkFlyer(sim, e, target, speed, canMove, dt)
	elseif ai == "thief" then
		thinkThief(sim, e, target, speed, canMove, dt)
	elseif ai == "sneak" then
		thinkSneak(sim, e, target, speed, canMove, dt)
	elseif ai == "brute" then
		thinkBrute(sim, e, target, speed, canMove, dt, heroes)
	elseif ai == "sentry" then
		thinkSentry(sim, e, target, dt)
	elseif ai == "guard" then
		thinkGuard(sim, e, target, speed, canMove, dt, heroes)
	end
end

-- A torpedo turns its velocity toward its hero, at most `turn` radians a second (same speed). Shared with
-- the client's drawing so the two agree.
function EnemySim.steer(s: any, heroes: { any }, dt: number)
	local h: any = nil
	for _, x in heroes do
		if x.id == s.home then
			h = x
			break
		end
	end
	if not h or h.alive == false then
		return
	end
	local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz)
	if speed < 1e-3 then
		return
	end
	local dx, dy, dz = h.x - s.x, h.y + 1.5 - s.y, h.z - s.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-3 then
		return
	end
	local ux, uy, uz = s.vx / speed, s.vy / speed, s.vz / speed
	local tx, ty, tz = dx / d, dy / d, dz / d
	local dot = math.clamp(ux * tx + uy * ty + uz * tz, -1, 1)
	local angle = math.acos(dot)
	local maxTurn = s.turn * dt
	if angle <= maxTurn then
		s.vx, s.vy, s.vz = tx * speed, ty * speed, tz * speed
		return
	end
	-- turn by maxTurn in the plane of (u, t): u cos a + w sin a, w the unit part of t across u
	local wx, wy, wz = tx - ux * dot, ty - uy * dot, tz - uz * dot
	local wl = math.sqrt(wx * wx + wy * wy + wz * wz)
	if wl < 1e-6 then
		return -- straight behind: no plane to turn in this step
	end
	local c, sn = math.cos(maxTurn), math.sin(maxTurn) / wl
	local nx, ny, nz = ux * c + wx * sn, uy * c + wy * sn, uz * c + wz * sn
	local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
	s.vx, s.vy, s.vz = nx / nl * speed, ny / nl * speed, nz / nl * speed
end

local function stepShots(sim: Sim, heroes: { Hero }, dt: number)
	local now = sim.now
	for i = #sim.blockers, 1, -1 do
		if sim.blockers[i].untilT <= now then
			table.remove(sim.blockers, i)
		end
	end
	local i = 1
	while i <= #sim.shots do
		local s = sim.shots[i]
		if s.home and s.turn then
			EnemySim.steer(s, heroes, dt)
		end
		s.x += s.vx * dt
		s.y += s.vy * dt
		s.z += s.vz * dt
		s.life -= dt
		local done = s.life <= 0
		if not done then
			for _, b in sim.blockers do
				if dist3(s.x, s.y, s.z, b.x, b.y, b.z) <= b.r + s.radius * 0.5 then
					table.insert(sim.events, { k = "blocked", x = s.x, y = s.y, z = s.z })
					done = true
					break
				end
			end
		end
		if not done then
			for _, h in heroes do
				if h.alive and dist3(s.x, s.y, s.z, h.x, h.y + 1.5, h.z) <= s.radius then
					table.insert(sim.events, { k = "hit", hero = h.id, damage = s.damage, e = s.enemyId })
					done = true
					break
				end
			end
		end
		if not done and s.y < sim.heightAt(s.x, s.z, s.y) then
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
			if not e.scripted then -- a scripted robot (an incident runner) is moved by its incident
				local px, py, pz = e.x, e.y, e.z
				local wasWet = e.cfg.sea and sim.water(px, py, pz)
				think(sim, e, heroes, edt)
				separate(sim, e)
				keepMedium(sim, e, px, py, pz, wasWet)
			end
			updateFlags(sim, e)
			ticks += 1
		end
	end
	sim.ticksLastStep = ticks
end

-- Alive enemies as hit-query candidates (flags let Shatter see a slowed target)
function EnemySim.candidates(sim: Sim): { any }
	local out = table.create(#sim.enemies)
	for _, e in sim.enemies do
		if e.alive then
			table.insert(
				out,
				{ id = e.id, x = e.x, y = e.y, z = e.z, r = e.cfg.radius or 2.5, flags = e.flags }
			)
		end
	end
	return out
end

-- A spawn spot for a robot near (x, z): flyers anywhere, ground robots only on the street (never in the
-- water); sea robots only in the water, at the depth of the hero they come for (`y`)
local function spotFor(sim: Sim, cfg: any, x: number, z: number, y: number?): (number?, number?, number?)
	if cfg.sea then
		local ask = math.min(y or sim.waterTop, sim.waterTop)
		for _ = 1, 6 do
			local floor = sim.heightAt(x, z, ask)
			local yy = if cfg.ai == "flyer"
				then math.min(
					floor + cfg.hover.min + sim.rngNext() * (cfg.hover.max - cfg.hover.min),
					sim.waterTop
				)
				else floor + halfHeight(cfg)
			if sim.water(x, yy, z) then
				return x, yy, z
			end
			x += (sim.rngNext() - 0.5) * 60
			z += (sim.rngNext() - 0.5) * 60
		end
		return nil, nil, nil
	end
	if cfg.ai == "flyer" then
		local yy = sim.heightAt(x, z) + cfg.hover.min + sim.rngNext() * (cfg.hover.max - cfg.hover.min)
		return x, yy, z
	end
	for _ = 1, 6 do
		local h = sim.heightAt(x, z)
		if h <= 1 and not sim.water(x, sim.waterTop + 1, z) then
			return x, h + halfHeight(cfg), z
		end
		x += (sim.rngNext() - 0.5) * 40
		z += (sim.rngNext() - 0.5) * 40
	end
	return nil, nil, nil
end

local function pickKind(sim: Sim, mix: { [string]: number }): string
	local total = 0
	for _, kind in sim.config.Enemies.order do
		total += mix[kind] or 0
	end
	local r = sim.rngNext() * total
	for _, kind in sim.config.Enemies.order do
		r -= mix[kind] or 0
		if r <= 0 and (mix[kind] or 0) > 0 then
			return kind
		end
	end
	return "SparkDrone"
end

-- Stand-in for the incident spawner (M6): keep `count` robots within `radius` of every hero, spawning them
-- out of sight at `minDistance` or more from the mix, and clear robots nobody has been near for 30 s.
-- kind forces one type (Dev and tests).
function EnemySim.populate(sim: Sim, heroes: { Hero }, now: number, kind: string?)
	local cfg = sim.config.Enemies.nearHero
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
				-- a swimming hero meets sea robots (Config.Deep.mix)
				local wet = sim.config.Deep ~= nil and sim.water(h.x, h.y, h.z)
				local mix = if wet then sim.config.Deep.mix else sim.config.Enemies.mix
				local enemyKind = kind or pickKind(sim, mix)
				local ecfg = sim.config.Enemies[enemyKind]
				local ang = sim.rngNext() * math.pi * 2
				local r = cfg.minDistance + sim.rngNext() * (cfg.radius - cfg.minDistance)
				local x, y, z = spotFor(sim, ecfg, h.x + math.cos(ang) * r, h.z + math.sin(ang) * r, h.y)
				if x and y and z and EnemySim.spawn(sim, enemyKind, x, y, z, 1) then
					meta.nextSpawn = now + cfg.respawn / cfg.count
				else
					meta.nextSpawn = now + 0.5
				end
			end
		end
	end
	for i = #sim.enemies, 1, -1 do
		local e = sim.enemies[i]
		if e.tag == nil and now - e.lastHeroNear > 30 then -- tagged robots belong to an incident
			table.insert(sim.events, { k = "despawn", e = e.id })
			removeAt(sim, i)
		end
	end
end

-- Take an enemy away without a defeat (its incident ended)
function EnemySim.remove(sim: Sim, id: number): boolean
	for i, e in sim.enemies do
		if e.id == id then
			table.insert(sim.events, { k = "despawn", e = e.id })
			removeAt(sim, i)
			return true
		end
	end
	return false
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
