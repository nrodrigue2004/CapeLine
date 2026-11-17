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
--   guard  (Warden) blocks hits from the front; a flank hit breaks the guard and stuns it. The Shield
--          Bearer is a guard too: its riot shield blocks every front hit and covers the robots behind it
-- The nine new types (nate, 2026-11-17; each has `on` in Config.Enemies, a type with on = false never spawns):
--   captain  (Captain) hangs back, fires a sidearm and rallies robots near it (harder hits, faster); when it
--            falls, the robots it rallied are slowed
--   sniper   (Sniper) keeps far, shows a laser on its hero, locks the aim, then fires one heavy round
--   bomber   (Bomber) lobs grenades at the hero's spot (a ring shows where), the blast leaves a burning patch
--   medic    (Medic Unit) repairs the most damaged robot near it with a beam, standing behind it
--   swarm    (Swarmer) small fast robots in packs that surround a hero, lunge and nip
--   mimic    (Mimic) dressed as a citizen (no hit target) until a hero is close, then an ambush strike
--   grappler (Grappler) hooks a hero (a flier too) and pulls it down to itself, then punches
--   the Interceptor is a flyer that hunts only heroes in the air and fires a net that drops them
-- The famous fakes and the evil twin (nate's lore, build plan step 4; Config.Enemies `fake`, Shared.FakeRules):
-- robots in a famous hero's look, mini-boss tier, on the brains above with a few added moves:
--   Radiant  (flyer) light bolts in bursts, and a dive: a ring under its hero, then it drops there and strikes
--   Bulwark  (brute) a tower shield (guard), the shield slam, every 3rd slam a wide shockwave, and a charge
--            down a lane at a hero farther off
--   Skylance (sniper) a short sighting line, a thrown spear, then a dash to one side
--   the evil twin takes its hero's path's style (FakeRules.twinCfg): blaster (flyer), gunner (sniper with
--   dashes), lobber (bomber), striker (sneak), duelist (sneak with no cloak) or smasher (brute with the charge
--   and shockwave). A fake's face cracks (an "unmask" event, EXTRA.unmasked) once its health falls to
--   Config.Enemies.fakes.crack.
-- Status effects from heroes (Status): stun, root, slow, knockup, float, pull, blind, taunt.
-- States on the wire: 1 Patrol, 2 Chase, 3 Attack, 4 Flee, 5 Dead.
-- Enemies are machines only and never hurt citizens (spec: Choices baked in).
-- Underwater (Config.Deep): `sea` robots (Diver, Anchor, Torpedo Sentry) spawn near a swimming hero from
-- Deep.mix and stay in the water; land robots never walk into it. opts.water(x, y, z) says what is water.

local Formulas = if script then require(script.Parent.Formulas) else (require :: any)("./Formulas")
local Status = if script then require(script.Parent.Status) else (require :: any)("./Status")
local FakeRules = if script then require(script.Parent.FakeRules) else (require :: any)("./FakeRules")

local EnemySim = {}

EnemySim.PATROL, EnemySim.CHASE, EnemySim.ATTACK, EnemySim.FLEE, EnemySim.DEAD = 1, 2, 3, 4, 5

-- The second flags byte on the wire (EnemyBuffer `extra`): what the new robot types are doing
--   aim      a Sniper's laser is on a hero (the AIM event names the hero)
--   rally    a Captain's rally is on this robot (hits harder, moves faster)
--   disguise a Mimic still dressed as a citizen (not a hit target, no health bar)
--   mend     a Medic Unit is repairing a robot (the MEND event names it)
--   lunge    a Swarmer is lunging
--   hooked   a Grappler's hook is out
--   unmasked a famous fake's or an evil twin's face has cracked (lore step 4)
EnemySim.EXTRA = { aim = 1, rally = 2, disguise = 4, mend = 8, lunge = 16, hooked = 32, unmasked = 64 }

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
	-- the nine new types
	extra: number, -- EnemySim.EXTRA bits on the wire
	nextSpecial: number, -- the next rally, aim, grenade, hook, net or lunge
	rallyUntil: number, -- a Captain's rally is on this robot until then
	rallyBy: number?, -- which Captain
	aimUntil: number, -- a Sniper's laser is on aimHero until then (0: not aiming)
	aimHero: number?,
	lockX: number?, -- the locked aim point
	lockY: number?,
	lockZ: number?,
	disguised: boolean, -- a Mimic still dressed as a citizen
	stalkSince: number, -- when a disguised Mimic first saw a hero
	ambush: boolean, -- the Mimic's first strike is still to come
	lungeUntil: number, -- a Swarmer's lunge
	lungeX: number,
	lungeZ: number,
	mendUntil: number, -- a Medic's beam is on (the patient) until then
	patient: number?,
	nextMendEvent: number,
	hookUntil: number, -- a Grappler's hook is out
	airSeen: number, -- an Interceptor: the last moment its hero was in the air
	-- the famous fakes and the evil twin (lore step 4)
	move: string?, -- the move its windup ends in: "slam", "shock", "charge" or "dive"
	slams: number, -- slams so far (every Nth is a shockwave)
	unmasked: boolean, -- its face has cracked
	path: string?, -- an evil twin's power path
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
	style: number?, -- drawn as: 1 a sniper round, 2 a net, 3 a grappling hook, 4 a power path's shot (a fake's)
	cc: string?, -- a crowd control the hit puts on the hero (the Interceptor's net)
	ccTime: number?,
	ccValue: number?,
	pull: { x: number, y: number, z: number, reel: number, time: number }?, -- a Grappler's hook
}

export type Blocker = { x: number, y: number, z: number, r: number, untilT: number }

-- A Bomber's grenade in the air (lands at `at`) and the burning patch it leaves
export type Bomb = {
	x: number,
	y: number,
	z: number,
	at: number,
	r: number,
	damage: number,
	enemyId: number,
	zone: any?,
	zoneDamage: number,
}
export type Zone = {
	x: number,
	y: number,
	z: number,
	r: number,
	untilT: number,
	nextTick: number,
	tick: number,
	damage: number,
	enemyId: number,
}

export type Sim = {
	config: any,
	enemies: { Enemy },
	byId: { [number]: Enemy },
	shots: { Shot },
	blockers: { Blocker },
	bombs: { Bomb },
	zones: { Zone },
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
		bombs = {},
		zones = {},
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

-- A robot type that is in the game (its switch in Config.Enemies is not off)
function EnemySim.enabled(config: any, kind: string): boolean
	local cfg = config.Enemies[kind]
	return cfg ~= nil and cfg.on ~= false
end

local function spawnWith(
	sim: Sim,
	kind: string,
	cfg: any,
	x: number,
	y: number,
	z: number,
	level: number?
): Enemy?
	if cfg.on == false then
		return nil -- a type nate cut never shows up
	end
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
		extra = 0,
		nextSpecial = now + (if cfg.lunge then sim.rngNext() * 0.5 else 1.5 + sim.rngNext() * 2),
		rallyUntil = 0,
		rallyBy = nil,
		aimUntil = 0,
		disguised = cfg.disguise ~= nil,
		stalkSince = 0,
		ambush = cfg.ambush ~= nil,
		lungeUntil = 0,
		lungeX = 0,
		lungeZ = 0,
		mendUntil = 0,
		patient = nil,
		nextMendEvent = 0,
		hookUntil = 0,
		airSeen = 0,
		move = nil,
		slams = 0,
		unmasked = false,
		path = if cfg.fake then cfg.fake.path else nil,
	}
	table.insert(sim.enemies, e)
	sim.byId[e.id] = e
	table.insert(sim.events, { k = "spawn", e = e.id })
	return e
end

function EnemySim.spawn(sim: Sim, kind: string, x: number, y: number, z: number, level: number?): Enemy?
	local cfg = sim.config.Enemies[kind]
	assert(cfg, "unknown enemy " .. kind)
	if cfg.twin then
		cfg = FakeRules.twinCfg(sim.config, cfg.twin.default) -- a twin with no hero: the default path's style
	end
	return spawnWith(sim, kind, cfg, x, y, z, level)
end

-- An evil twin that fights with a power path's moves (FakeRules.twinCfg); nil when the twin is switched off
function EnemySim.spawnTwin(sim: Sim, path: string?, x: number, y: number, z: number, level: number?): Enemy?
	return spawnWith(sim, "EvilTwin", FakeRules.twinCfg(sim.config, path), x, y, z, level)
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

-- A Shield Bearer whose raised shield stands between robot `e` and a hit from (fromX, fromZ): the bearer is
-- within its cover radius of e, faces the attacker, and sits on the line from e toward the attacker
local function coverFor(sim: Sim, e: Enemy, fromX: number, fromZ: number): Enemy?
	local ax, az = fromX - e.x, fromZ - e.z
	local al = math.sqrt(ax * ax + az * az)
	if al < 1 then
		return nil
	end
	ax, az = ax / al, az / al
	for _, b in sim.enemies do
		local cover = b.cfg.cover
		if cover and b ~= e and b.alive and guardUp(sim, b) then
			local bx, bz = b.x - e.x, b.z - e.z
			local along = bx * ax + bz * az
			local across = math.abs(bx * az - bz * ax)
			if along > 0 and along < math.min(cover.radius, al) and across <= cover.width then
				local fx, fz = yawDir(b.yaw)
				if fx * ax + fz * az >= math.cos(math.rad(b.cfg.guard.front / 2)) then
					return b -- the bearer faces the attacker: the hit meets its shield
				end
			end
		end
	end
	return nil
end

-- The rally on a robot: (damage, speed) multipliers
local function rallied(sim: Sim, e: Enemy): (number, number)
	if e.rallyUntil > sim.now and e.rallyBy then
		local cap = sim.byId[e.rallyBy]
		local r = if cap then cap.cfg.rally else nil
		if r then
			return r.damage, r.speed
		end
	end
	return 1, 1
end

-- A Mimic drops its disguise
local function reveal(sim: Sim, e: Enemy)
	if e.disguised then
		e.disguised = false
		e.nextMelee = sim.now + e.cfg.ambush.delay
		table.insert(sim.events, { k = "reveal", e = e.id, x = e.x, y = e.y, z = e.z })
	end
end

-- A Grappler's hook comes back: the cable in flight is cut (it pulls nobody) and the hooked bit clears. A
-- stun or the Grappler's fall does this, so a hook never yanks a hero toward a robot that is down or gone.
local function cutHook(sim: Sim, e: Enemy)
	if e.cfg.hook == nil then
		return
	end
	e.hookUntil = 0
	for i = #sim.shots, 1, -1 do
		local s = sim.shots[i]
		if s.enemyId == e.id and s.pull then
			table.remove(sim.shots, i)
		end
	end
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
	if flag == EnemySim.HIT and fromX and fromZ and dealt > 0 and dealt ~= math.huge then
		local bearer = coverFor(sim, e, fromX, fromZ)
		if bearer then
			dealt *= 1 - bearer.cfg.cover.cut -- behind a Shield Bearer's raised shield
			flag = EnemySim.BLOCKED
		end
	end
	if e.ai == "sneak" and e.cloakUntil > sim.now then
		e.cloakUntil = sim.now -- a hit reveals it
	end
	reveal(sim, e)
	if e.hitLife and dealt > 0 and dealt ~= math.huge then
		dealt = e.maxHealth / e.hitLife -- a story robot that takes a set number of hits
	end
	e.health -= dealt
	if attacker and not e.target then
		e.target = attacker -- getting hit draws aggro
	end
	if
		cfg.fake
		and not e.unmasked
		and e.health > 0
		and FakeRules.cracked(sim.config, e.health / e.maxHealth)
	then
		e.unmasked = true -- the hero face cracks to show metal
		-- (by: who cracked it, for the news and the slow-mo finisher, lore step 7)
		table.insert(
			sim.events,
			{ k = "unmask", e = e.id, x = e.x, y = e.y, z = e.z, by = attacker, kind = e.kind }
		)
	end
	if e.health <= 0 then
		e.health = 0
		e.alive = false
		e.state = EnemySim.DEAD
		table.insert(
			sim.events,
			{ k = "die", e = e.id, x = e.x, y = e.y, z = e.z, by = attacker, kind = e.kind }
		)
		cutHook(sim, e)
		local fall = cfg.leaderless
		if fall then
			-- the Captain fell: the robots it rallied falter
			for _, o in sim.enemies do
				if o.alive and o.rallyBy == e.id and o.rallyUntil > sim.now then
					o.rallyUntil = 0
					o.rallyBy = nil
					Status.apply(o.status, "slow", fall.time, sim.now, { value = fall.slow })
				end
			end
		end
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
			e.aimUntil = 0 -- and a Sniper's aim
			e.mendUntil = 0 -- and a Medic's beam
			cutHook(sim, e) -- and a Grappler's hook
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

-- A robot's shot damage before its coefficient: Formulas.enemyDamage from its own config (an evil twin's
-- config is its path's style, not Config.Enemies.EvilTwin's)
local function shotDamage(sim: Sim, e: Enemy): number
	local s = sim.config.Enemies.scale
	return (s.dmgBase + s.dmgPerLevel * e.level) * e.cfg.coeff
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
	turn: number?,
	special: { [string]: any }? -- style, cc, ccTime, ccValue, pull (the new types' special shots)
): Shot?
	if e.dmgMult == 0 then
		return nil -- a harmless robot (the opening's first drone) never fires
	end
	local dx, dy, dz = tx - e.x, ty - e.y, tz - e.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-3 then
		return nil
	end
	dx, dy, dz = dx / d, dy / d, dz / d
	if Status.has(e.status, "blind", sim.now) then
		-- blinded: shots go up to 25 degrees wide
		local a = (sim.rngNext() - 0.5) * math.rad(50)
		dx, dz = dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
		dy += (sim.rngNext() - 0.5) * 0.4
	end
	local rallyDmg = rallied(sim, e)
	local damage = shotDamage(sim, e) * (coeff or 1) * (e.dmgMult or 1) * rallyDmg
	local muzzle = 1.2
	local sp: { [string]: any } = special or {}
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
		style = sp.style,
		cc = sp.cc,
		ccTime = sp.ccTime,
		ccValue = sp.ccValue,
		pull = sp.pull,
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
		style = sp.style,
	})
	return shot
end

-- cc: an optional crowd control the hit puts on the hero ({ cc, time, value }: the Shield Bearer's bash)
local function melee(sim: Sim, e: Enemy, h: Hero, coeff: number, cc: { [string]: any }?)
	if e.dmgMult == 0 then
		return
	end
	local damage = (sim.config.Enemies.scale.dmgBase + sim.config.Enemies.scale.dmgPerLevel * e.level)
		* coeff
		* (e.dmgMult or 1)
		* (rallied(sim, e))
	table.insert(sim.events, {
		k = "hit",
		hero = h.id,
		damage = damage,
		e = e.id,
		melee = true,
		cc = if cc then cc.cc else nil,
		ccTime = if cc then cc.time else nil,
		ccValue = if cc then cc.value else nil,
	})
end

local function attackersOf(sim: Sim, heroId: number, except: Enemy): number
	-- robots already after this hero (weighted: a small Swarmer counts a third)
	local n = 0
	for _, o in sim.enemies do
		if
			o ~= except
			and o.alive
			and o.target == heroId
			and (o.state == EnemySim.ATTACK or o.state == EnemySim.CHASE)
		then
			n += o.cfg.attackWeight or 1 -- three Swarmers count as one robot
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

-- A hero at least `over` studs above the ground or roof under it (an Interceptor's prey)
local function airborne(sim: Sim, h: Hero, over: number): boolean
	return h.y - sim.heightAt(h.x, h.z, h.y) >= over
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
	-- an Interceptor hunts only heroes in the air (it lets one go once it has been down a moment)
	local function inAir(h: Hero): boolean
		return airborne(sim, h, cfg.airborne)
	end
	if target and cfg.hunter then
		if inAir(target) then
			e.airSeen = now
		elseif now - e.airSeen > 2 then
			target = nil
			e.target = nil
		end
	end
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
			if h.alive and (not cfg.hunter or inAir(h)) then
				local d = dist3(e.x, e.y, e.z, h.x, h.y, h.z)
				if d < bestD and attackersOf(sim, h.id, e) < caps.attackingOneHero then
					best, bestD = h, d
				end
			end
		end
		target = best
		e.target = if best then best.id else nil
		if best then
			e.airSeen = now
		end
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

local function thinkFlyer(
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
	local dive = cfg.dive
	-- Radiant's dive: the ring showed for the windup; now it drops to the spot and strikes (even if its hero left)
	if dive and e.windupUntil > 0 then
		e.state = EnemySim.ATTACK
		if now >= e.windupUntil then
			e.windupUntil = 0
			local lx, ly, lz = e.lockX :: number, e.lockY :: number, e.lockZ :: number
			table.insert(
				sim.events,
				{ k = "dash", e = e.id, x = e.x, y = e.y, z = e.z, tx = lx, ty = ly, tz = lz }
			)
			e.x, e.y, e.z = lx, ly + 1, lz
			for _, h in heroes do
				if h.alive and dist3(lx, ly, lz, h.x, h.y, h.z) <= dive.radius then
					melee(sim, e, h, dive.coeff)
				end
			end
			local floor = sim.heightAt(lx, lz, ly)
			table.insert(sim.events, { k = "slam", e = e.id, x = lx, y = floor, z = lz, r = dive.radius })
			e.nextSpecial = now + dive.every
		end
		return
	end
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
	if dive and now >= e.nextSpecial and e.burstLeft <= 0 and e.dmgMult ~= 0 then
		-- the dive: a ring under the hero (on the ground, or around a flier) for the windup
		e.windupUntil = now + dive.windup
		e.lockX, e.lockY, e.lockZ = target.x, target.y, target.z
		table.insert(sim.events, {
			k = "warn",
			e = e.id,
			x = target.x,
			y = math.min(target.y, floor + 0.2),
			z = target.z,
			r = dive.radius,
			t = dive.windup,
		})
		return
	end
	if e.burstLeft <= 0 and now >= e.nextBurst then
		e.burstLeft = cfg.burst.shots
		e.nextShot = now
		e.nextBurst = now + cfg.burst.every
	end
	if e.burstLeft > 0 and now >= e.nextShot then
		shoot(
			sim,
			e,
			target.x,
			target.y + 1.5,
			target.z,
			cfg.shotSpeed,
			cfg.shotRadius,
			cfg.attackRange,
			nil,
			nil,
			nil,
			if cfg.shotStyle then { style = cfg.shotStyle } else nil
		)
		e.burstLeft -= 1
		e.nextShot = now + cfg.burst.gap
	end
	local net = cfg.net
	-- (only at a hero still in the air: in the moment it keeps a landed hero, it shoots but never nets)
	if net and now >= e.nextSpecial and (not cfg.hunter or airborne(sim, target, cfg.airborne)) then
		-- the Interceptor's net: holds a flier a moment, so it drops out of flight
		shoot(
			sim,
			e,
			target.x,
			target.y + 1.5,
			target.z,
			net.shotSpeed,
			net.shotRadius,
			cfg.attackRange,
			0.2,
			nil,
			nil,
			{ style = 2, cc = net.cc, ccTime = net.time }
		)
		e.nextSpecial = now + net.every
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
	if cfg.cloak and now >= e.nextCloak then
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

-- The flat distance from (px, pz) to the segment a..b
local function segDist2(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local vx, vz = bx - ax, bz - az
	local l2 = vx * vx + vz * vz
	local t = if l2 > 1e-9 then math.clamp(((px - ax) * vx + (pz - az) * vz) / l2, 0, 1) else 0
	return dist2(px, pz, ax + vx * t, az + vz * t)
end

-- A ground robot's flat step to (nx, nz) is clear: no wall (a roof more than a step up) and no water
local function clearStep(sim: Sim, e: Enemy, nx: number, nz: number): boolean
	return sim.heightAt(nx, nz, e.y) <= e.y - halfHeight(e.cfg) + 2.5
		and not sim.water(nx, sim.waterTop + 1, nz)
end

-- Bulwark's charge (lore step 4): straight down the lane it showed, up to `dist` studs or the first wall; a hero
-- in the lane is hit and stunned
local function charge(sim: Sim, e: Enemy, heroes: { Hero })
	local ch = e.cfg.charge
	local fx, fz = yawDir(e.yaw)
	local sx, sy, sz = e.x, e.y, e.z
	local go = 0
	while go + 2 <= ch.dist and clearStep(sim, e, sx + fx * (go + 2), sz + fz * (go + 2)) do
		go += 2
	end
	local ex, ez = sx + fx * go, sz + fz * go
	local reach = ch.width + sim.config.Enemies.melee.reach
	for _, h in heroes do
		if h.alive and math.abs(h.y - sy) <= 7 and segDist2(h.x, h.z, sx, sz, ex, ez) <= reach then
			melee(sim, e, h, ch.coeff, { cc = "stun", time = ch.stun })
		end
	end
	e.x, e.z = ex, ez
	e.y = sim.heightAt(ex, ez, sy) + halfHeight(e.cfg)
	table.insert(sim.events, { k = "dash", e = e.id, x = sx, y = sy, z = sz, tx = ex, ty = e.y, tz = ez })
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
	-- a slam (or a fake's shockwave or charge) on the way finishes even if the target left
	if e.windupUntil > 0 then
		if now >= e.windupUntil then
			e.windupUntil = 0
			local move = e.move or "slam"
			e.move = nil
			local floor = e.y - halfHeight(cfg)
			if move == "charge" then
				charge(sim, e, heroes)
			elseif move == "shock" then
				-- a wide ring along the ground: a hero standing in it is hit; one in the air (a jump) is not
				local w = cfg.shockwave
				local reach = w.radius + sim.config.Enemies.melee.reach
				for _, h in heroes do
					if
						h.alive
						and dist2(e.x, e.z, h.x, h.z) <= reach
						and math.abs(h.y - e.y) <= 10
						and not airborne(sim, h, w.height + 3)
					then
						melee(sim, e, h, w.coeff)
					end
				end
				table.insert(sim.events, { k = "slam", e = e.id, x = e.x, y = floor, z = e.z, r = w.radius })
				e.nextMelee = now + cfg.slam.every
			else
				local reach = cfg.slam.radius + sim.config.Enemies.melee.reach
				for _, h in heroes do
					if h.alive and dist2(e.x, e.z, h.x, h.z) <= reach and math.abs(h.y - e.y) <= 7 then
						melee(sim, e, h, cfg.coeff)
					end
				end
				table.insert(
					sim.events,
					{ k = "slam", e = e.id, x = e.x, y = floor, z = e.z, r = cfg.slam.radius }
				)
				e.nextMelee = now + cfg.slam.every
			end
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
	local ch = cfg.charge
	if
		ch
		and now >= e.nextSpecial
		and d >= ch.min
		and d <= ch.range
		and math.abs(target.y - e.y) <= 10
		and e.dmgMult ~= 0
	then
		-- a fake's charge: a lane shows in front of it for the windup, then it runs down it
		e.state = EnemySim.ATTACK
		e.yaw = yawTo(target.x - e.x, target.z - e.z)
		e.windupUntil = now + ch.windup
		e.move = "charge"
		e.nextSpecial = now + ch.every
		table.insert(sim.events, {
			k = "warn",
			e = e.id,
			x = e.x,
			y = e.y - halfHeight(cfg),
			z = e.z,
			r = ch.dist,
			t = ch.windup,
			arc = math.deg(2 * math.atan(ch.width / ch.dist)) * 2,
			yaw = e.yaw,
		})
		return
	end
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
		-- every Nth slam of a fake's is a shockwave: wider, with a longer warning
		local w = cfg.shockwave
		e.slams += 1
		local shock = w ~= nil and e.slams % w.nth == 0
		e.move = if shock then "shock" else "slam"
		local r = if shock then w.radius else cfg.slam.radius
		local t = if shock then w.windup else cfg.slam.windup
		e.windupUntil = now + t
		table.insert(sim.events, {
			k = "warn",
			e = e.id,
			x = e.x,
			y = e.y - halfHeight(cfg),
			z = e.z,
			r = r,
			t = t,
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
					melee(sim, e, h, cfg.coeff, cfg.bash) -- a Shield Bearer's bash also slows
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

-- Ground robots that keep a range from their hero: back off inside `min`, close in past `max`. Returns the
-- flat distance.
local function keepRange(
	sim: Sim,
	e: Enemy,
	target: Hero,
	min: number,
	max: number,
	speed: number,
	canMove: boolean,
	dt: number
): number
	local d = dist2(e.x, e.z, target.x, target.z)
	if canMove then
		if d < min then
			local dx, dz = e.x - target.x, e.z - target.z
			local l = math.max(1, math.sqrt(dx * dx + dz * dz))
			walk(sim, e, e.x + dx / l * 20, e.z + dz / l * 20, speed, dt)
		elseif d > max then
			walk(sim, e, target.x, target.z, speed, dt)
		end
	end
	return d
end

local function rangeState(d: number, min: number, max: number): number
	return if d < min then EnemySim.FLEE elseif d > max then EnemySim.CHASE else EnemySim.ATTACK
end

-- Captain: hangs back behind its squad, fires a sidearm, and every so often raises an arm and rallies the
-- robots near it
local function thinkCaptain(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	local r = cfg.rally
	if e.windupUntil > 0 then
		e.state = EnemySim.ATTACK
		if now >= e.windupUntil then
			e.windupUntil = 0
			for _, o in sim.enemies do
				if o.alive and dist3(e.x, e.y, e.z, o.x, o.y, o.z) <= r.radius then
					o.rallyUntil = now + r.time
					o.rallyBy = e.id
				end
			end
			table.insert(sim.events, { k = "rally", e = e.id, x = e.x, y = e.y, z = e.z, r = r.radius })
			e.nextSpecial = now + r.every
		end
		return
	end
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.4, dt, 25)
		end
		return
	end
	local d = keepRange(sim, e, target, cfg.keep.min, cfg.keep.max, speed, canMove, dt)
	e.state = rangeState(d, cfg.keep.min, cfg.keep.max)
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if now >= e.nextSpecial and e.dmgMult ~= 0 then
		e.windupUntil = now + r.windup -- the arm goes up: the rally comes at the end
		return
	end
	if d <= cfg.attackRange and now >= e.nextShot then
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
	end
end

-- Skylance's dash (lore step 4): after a throw, a quick dash to one side of its hero (the other side next
-- time); it stays put if both sides are a wall or the water
local function dashAside(sim: Sim, e: Enemy, target: Hero)
	local dist = e.cfg.dash.dist
	local dx, dz = target.x - e.x, target.z - e.z
	local l = math.max(1e-3, math.sqrt(dx * dx + dz * dz))
	local sx, sz = -dz / l, dx / l
	e.orbitDir = -e.orbitDir
	for _, sign in { e.orbitDir, -e.orbitDir } do
		local mx, mz = e.x + sx * sign * dist * 0.5, e.z + sz * sign * dist * 0.5
		local nx, nz = e.x + sx * sign * dist, e.z + sz * sign * dist
		if clearStep(sim, e, mx, mz) and clearStep(sim, e, nx, nz) then
			local fx, fy, fz = e.x, e.y, e.z
			e.x, e.z = nx, nz
			e.y = sim.heightAt(nx, nz, fy) + halfHeight(e.cfg)
			table.insert(
				sim.events,
				{ k = "dash", e = e.id, x = fx, y = fy, z = fz, tx = nx, ty = e.y, tz = nz }
			)
			return
		end
	end
end

-- Sniper: keeps far, puts a laser on its hero, locks the aim for the last moment, then one heavy round
local function thinkSniper(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	local aim = cfg.aim
	if e.aimUntil > 0 then
		if not target or target.id ~= e.aimHero then
			e.aimUntil = 0 -- lost its hero
		else
			e.state = EnemySim.ATTACK
			if now < e.aimUntil - aim.lock then
				e.lockX, e.lockY, e.lockZ = target.x, target.y + 1.5, target.z -- still following
			end
			e.yaw = yawTo((e.lockX :: number) - e.x, (e.lockZ :: number) - e.z)
			if now >= e.aimUntil then
				shoot(
					sim,
					e,
					e.lockX :: number,
					e.lockY :: number,
					e.lockZ :: number,
					cfg.fire.shotSpeed,
					cfg.fire.shotRadius,
					cfg.attackRange,
					cfg.fire.coeff,
					nil,
					nil,
					{ style = cfg.shotStyle or 1 }
				)
				e.aimUntil = 0
				e.nextSpecial = now + aim.every
				if cfg.dash then
					dashAside(sim, e, target)
				end
			end
			return
		end
	end
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.35, dt, 20)
		end
		return
	end
	local d = keepRange(sim, e, target, cfg.keep.min, cfg.keep.max, speed, canMove, dt)
	e.state = rangeState(d, cfg.keep.min, cfg.keep.max)
	if e.state ~= EnemySim.FLEE then
		turnToward(e, target.x, target.z, cfg.turnRate, dt)
	end
	local full = dist3(e.x, e.y, e.z, target.x, target.y, target.z)
	if e.state == EnemySim.ATTACK and full <= cfg.attackRange and now >= e.nextSpecial and e.dmgMult ~= 0 then
		e.aimUntil = now + aim.time
		e.aimHero = target.id
		e.lockX, e.lockY, e.lockZ = target.x, target.y + 1.5, target.z
		table.insert(sim.events, {
			k = "aim",
			e = e.id,
			hero = target.id,
			t = aim.time,
			lock = aim.lock,
			x = e.x,
			y = e.y,
			z = e.z,
		})
	end
end

-- Bomber: lobs a grenade at the hero's spot (a ring shows where it lands); the blast leaves a burning patch
local function thinkBomber(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.4, dt, 20)
		end
		return
	end
	local d = keepRange(sim, e, target, cfg.keep.min, cfg.keep.max, speed, canMove, dt)
	e.state = rangeState(d, cfg.keep.min, cfg.keep.max)
	turnToward(e, target.x, target.z, cfg.turnRate, dt)
	local g = cfg.grenade
	local floor = sim.heightAt(target.x, target.z, target.y)
	-- grenades are for heroes on the ground or a roof: a flier is left to the others
	if d <= cfg.attackRange and now >= e.nextSpecial and target.y - floor < 8 and e.dmgMult ~= 0 then
		local tx = target.x + (sim.rngNext() - 0.5) * 2 * g.spread
		local tz = target.z + (sim.rngNext() - 0.5) * 2 * g.spread
		local ty = sim.heightAt(tx, tz, target.y)
		local base = shotDamage(sim, e) * (e.dmgMult or 1) * (rallied(sim, e))
		table.insert(sim.bombs, {
			x = tx,
			y = ty,
			z = tz,
			at = now + g.flight,
			r = g.radius,
			damage = base * g.coeff,
			enemyId = e.id,
			zone = cfg.zone,
			zoneDamage = if cfg.zone then base * cfg.zone.coeff else 0,
		})
		table.insert(
			sim.events,
			{ k = "lob", e = e.id, x = e.x, y = e.y + 1, z = e.z, tx = tx, ty = ty, tz = tz, t = g.flight }
		)
		table.insert(sim.events, { k = "swing", e = e.id })
		e.nextSpecial = now + g.every
	end
end

-- The robot a Medic Unit should repair: the most damaged one in reach (never another Medic, a disguised
-- Mimic or a story robot that takes a set number of hits)
local function patientFor(sim: Sim, e: Enemy): Enemy?
	local m = e.cfg.mend
	local best, bestF = nil, m.below
	for _, o in sim.enemies do
		if o ~= e and o.alive and o.ai ~= "medic" and not o.disguised and not o.hitLife then
			local f = o.health / o.maxHealth
			if f < bestF and dist3(e.x, e.y, e.z, o.x, o.y, o.z) <= m.range * 1.5 then
				best, bestF = o, f
			end
		end
	end
	return best
end

-- Medic Unit: stands behind its patient (away from the hero) and repairs it with a beam; with nobody to
-- repair it keeps its distance and plinks with a sidearm
local function thinkMedic(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	local m = cfg.mend
	local p = patientFor(sim, e)
	if p then
		local gx, gz = p.x, p.z
		if target then
			local dx, dz = p.x - target.x, p.z - target.z
			local l = math.max(1, math.sqrt(dx * dx + dz * dz))
			gx, gz = p.x + dx / l * cfg.keep.behind, p.z + dz / l * cfg.keep.behind
		end
		if canMove and dist2(e.x, e.z, gx, gz) > 3 then
			walk(sim, e, gx, gz, speed, dt)
		end
		if dist3(e.x, e.y, e.z, p.x, p.y, p.z) <= m.range then
			e.state = EnemySim.ATTACK
			e.yaw = yawTo(p.x - e.x, p.z - e.z)
			p.health = math.min(p.maxHealth, p.health + p.maxHealth * m.perSecond * dt)
			if e.patient ~= p.id or now >= e.nextMendEvent then
				e.patient = p.id
				e.nextMendEvent = now + m.every
				table.insert(
					sim.events,
					{ k = "mend", e = e.id, x = e.x, y = e.y, z = e.z, patient = p.id, t = m.every + 0.15 }
				)
			end
			e.mendUntil = now + 0.3
		else
			e.state = EnemySim.CHASE
			e.mendUntil = 0
		end
		return
	end
	e.mendUntil = 0
	e.patient = nil
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.4, dt, 20)
		end
		return
	end
	local d = keepRange(sim, e, target, cfg.keep.min, cfg.attackRange, speed, canMove, dt)
	e.state = rangeState(d, cfg.keep.min, cfg.attackRange)
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if d <= cfg.attackRange and now >= e.nextShot then
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
	end
end

-- Swarmer: each one runs for its own spot around the hero (so a pack surrounds it), lunges in, and nips
local function thinkSwarm(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	local lunging = e.lungeUntil > now
	if lunging and canMove then
		walk(sim, e, e.lungeX, e.lungeZ, cfg.lunge.speed, dt)
	end
	if not target then
		e.state = EnemySim.PATROL
		if canMove and not lunging then
			wander(sim, e, speed * 0.4, dt, 20)
		end
		return
	end
	local d = dist2(e.x, e.z, target.x, target.z)
	local dy = math.abs(target.y - e.y)
	local a = e.id * 2.39996 -- the golden angle: a pack spreads round the hero
	if not lunging then
		if dy > 10 then
			-- a flier or a roof: mill around underneath
			e.state = EnemySim.CHASE
			if canMove then
				walk(sim, e, target.x + math.cos(a) * 6, target.z + math.sin(a) * 6, speed * 0.6, dt)
			end
			return
		end
		if d > cfg.attackRange then
			e.state = EnemySim.CHASE
			local ring = if d > 10 then 3 else 0
			if canMove then
				walk(sim, e, target.x + math.cos(a) * ring, target.z + math.sin(a) * ring, speed, dt)
			end
			if d <= cfg.lunge.range and d > cfg.attackRange + 2 and now >= e.nextSpecial then
				e.lungeUntil = now + cfg.lunge.time
				e.lungeX, e.lungeZ = target.x, target.z
				e.nextSpecial = now + cfg.lunge.every
			end
		else
			e.state = EnemySim.ATTACK
		end
	else
		e.state = EnemySim.ATTACK
	end
	if d <= cfg.attackRange + 1 and dy < 6 and now >= e.nextMelee then
		e.yaw = yawTo(target.x - e.x, target.z - e.z)
		melee(sim, e, target, cfg.coeff)
		table.insert(sim.events, { k = "swing", e = e.id })
		e.nextMelee = now + cfg.bite.every
	end
end

-- Mimic: dressed as a citizen it strolls (no hit target); near a fight a while, it walks up to a hero at a
-- citizen's pace; a hero this close (or a hit) and it shows itself, then strikes hard once and fights on
-- A site's robot (tagged) with another robot of its fight still standing near it (a disguised Mimic does not
-- count: it hides among them)
local function squadNear(sim: Sim, e: Enemy, radius: number): boolean
	local r2 = radius * radius
	for _, o in sim.enemies do
		if o ~= e and o.alive and o.tag == e.tag and not o.disguised then
			local dx, dy, dz = o.x - e.x, o.y - e.y, o.z - e.z
			if dx * dx + dy * dy + dz * dz <= r2 then
				return true
			end
		end
	end
	return false
end

local function thinkMimic(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	local dg = cfg.disguise
	if e.disguised and e.tag ~= nil and not squadNear(sim, e, dg.alone) then
		-- the last of its site's squad shows itself, so the site can always be finished (a hero hanging back
		-- or hovering over it would never give it away, and it is no hit target while disguised)
		reveal(sim, e)
	end
	if e.disguised then
		e.state = EnemySim.PATROL
		if not target then
			e.stalkSince = 0
			if canMove then
				wander(sim, e, dg.walk * 0.6, dt, 20)
			end
			return
		end
		if dist3(e.x, e.y, e.z, target.x, target.y, target.z) <= dg.reveal then
			reveal(sim, e)
		else
			if e.stalkSince == 0 then
				e.stalkSince = now
			end
			if canMove then
				if now - e.stalkSince >= dg.stalk then
					walk(sim, e, target.x, target.z, dg.walk, dt)
				else
					wander(sim, e, dg.walk * 0.6, dt, 12)
				end
			end
			return
		end
	end
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.4, dt, 25)
		end
		return
	end
	local d = dist2(e.x, e.z, target.x, target.z)
	if d > cfg.attackRange then
		e.state = EnemySim.CHASE
		if canMove then
			walk(sim, e, target.x, target.z, speed, dt)
		end
		return
	end
	e.state = EnemySim.ATTACK
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if now >= e.nextMelee and math.abs(target.y - e.y) < 8 then
		local coeff = if e.ambush then cfg.ambush.coeff else cfg.coeff
		e.ambush = false
		melee(sim, e, target, coeff)
		table.insert(sim.events, { k = "swing", e = e.id })
		e.nextMelee = now + cfg.stab.cooldown
	end
end

-- Grappler: fires its hook at a hero 10 to 50 studs away (a flier too); a hooked hero is pulled down to it
-- and held a moment; up close it punches
local function thinkGrappler(sim: Sim, e: Enemy, target: Hero?, speed: number, canMove: boolean, dt: number)
	local cfg = e.cfg
	local now = sim.now
	local hk = cfg.hook
	if not target then
		e.state = EnemySim.PATROL
		if canMove then
			wander(sim, e, speed * 0.4, dt, 20)
		end
		return
	end
	e.yaw = yawTo(target.x - e.x, target.z - e.z)
	if e.hookUntil > now then
		e.state = EnemySim.ATTACK -- stands still while the hook is out
		return
	end
	local d = dist3(e.x, e.y, e.z, target.x, target.y, target.z)
	if d >= hk.min and d <= hk.range and now >= e.nextSpecial then
		local shot = shoot(
			sim,
			e,
			target.x,
			target.y + 1.5,
			target.z,
			hk.shotSpeed,
			hk.shotRadius,
			hk.range / 1.6, -- the cable is `range` long
			hk.coeff,
			nil,
			nil,
			{
				style = 3,
				cc = "root",
				ccTime = hk.hold,
				pull = { x = e.x, y = e.y, z = e.z, reel = hk.reel, time = hk.time },
			}
		)
		if shot then
			e.hookUntil = now + shot.life
		end
		e.nextSpecial = now + hk.every
		e.state = EnemySim.ATTACK
		return
	end
	local flat = dist2(e.x, e.z, target.x, target.z)
	if flat > cfg.attackRange or math.abs(target.y - e.y) > 8 then
		e.state = EnemySim.CHASE
		if canMove then
			walk(sim, e, target.x, target.z, speed, dt)
		end
		return
	end
	e.state = EnemySim.ATTACK
	if now >= e.nextMelee then
		melee(sim, e, target, cfg.coeff)
		table.insert(sim.events, { k = "swing", e = e.id })
		e.nextMelee = now + cfg.punch.every
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
	local X = EnemySim.EXTRA
	local x = 0
	if e.aimUntil > now then
		x += X.aim
	end
	if e.rallyUntil > now then
		x += X.rally
	end
	if e.disguised then
		x += X.disguise
	end
	if e.mendUntil > now then
		x += X.mend
	end
	if e.lungeUntil > now then
		x += X.lunge
	end
	if e.hookUntil > now then
		x += X.hooked
	end
	if e.unmasked then
		x += X.unmasked
	end
	e.extra = x
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
		e.aimUntil = 0 -- a Sniper being dragged loses its aim (no round without a fresh laser)
		return
	end

	if Status.has(st, "stun", now) then
		e.vx, e.vy, e.vz = 0, 0, 0
		return
	end

	local canMove = Status.canMove(st, now)
	local _, rallySpeed = rallied(sim, e)
	local speed = (e.cfg.speed or 0) * Status.speedMult(st, now) * rallySpeed
	local target = upkeepTarget(sim, e, heroes)
	local ai = e.ai
	if ai == "flyer" then
		thinkFlyer(sim, e, target, speed, canMove, dt, heroes)
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
	elseif ai == "captain" then
		thinkCaptain(sim, e, target, speed, canMove, dt)
	elseif ai == "sniper" then
		thinkSniper(sim, e, target, speed, canMove, dt)
	elseif ai == "bomber" then
		thinkBomber(sim, e, target, speed, canMove, dt)
	elseif ai == "medic" then
		thinkMedic(sim, e, target, speed, canMove, dt)
	elseif ai == "swarm" then
		thinkSwarm(sim, e, target, speed, canMove, dt)
	elseif ai == "mimic" then
		thinkMimic(sim, e, target, speed, canMove, dt)
	elseif ai == "grappler" then
		thinkGrappler(sim, e, target, speed, canMove, dt)
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

-- The distance from a point to the segment a..b (a fast shot is tested along the whole step it moved)
local function segDist(
	px: number,
	py: number,
	pz: number,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): number
	local vx, vy, vz = bx - ax, by - ay, bz - az
	local l2 = vx * vx + vy * vy + vz * vz
	local t = if l2 > 1e-9
		then math.clamp(((px - ax) * vx + (py - ay) * vy + (pz - az) * vz) / l2, 0, 1)
		else 0
	return dist3(px, py, pz, ax + vx * t, ay + vy * t, az + vz * t)
end

-- Grenades that land this step, then the burning patches they leave
local function stepBombs(sim: Sim, heroes: { Hero })
	local now = sim.now
	local i = 1
	while i <= #sim.bombs do
		local b = sim.bombs[i]
		if now >= b.at then
			for _, h in heroes do
				if h.alive and dist2(b.x, b.z, h.x, h.z) <= b.r and math.abs(h.y - b.y) <= b.r then
					table.insert(sim.events, { k = "hit", hero = h.id, damage = b.damage, e = b.enemyId })
				end
			end
			table.insert(sim.events, { k = "boom", e = b.enemyId, x = b.x, y = b.y, z = b.z, r = b.r })
			local zc = b.zone
			if zc then
				table.insert(sim.zones, {
					x = b.x,
					y = b.y,
					z = b.z,
					r = zc.radius,
					untilT = now + zc.time,
					nextTick = now + zc.tick,
					tick = zc.tick,
					damage = b.zoneDamage,
					enemyId = b.enemyId,
				})
				table.insert(
					sim.events,
					{ k = "zone", e = b.enemyId, x = b.x, y = b.y, z = b.z, r = zc.radius, t = zc.time }
				)
			end
			table.remove(sim.bombs, i)
		else
			i += 1
		end
	end
	for j = #sim.zones, 1, -1 do
		local z = sim.zones[j]
		if now >= z.untilT then
			table.remove(sim.zones, j)
		elseif now >= z.nextTick then
			z.nextTick += z.tick
			for _, h in heroes do
				if h.alive and dist2(z.x, z.z, h.x, h.z) <= z.r and math.abs(h.y - z.y) <= 6 then
					table.insert(sim.events, { k = "hit", hero = h.id, damage = z.damage, e = z.enemyId })
				end
			end
		end
	end
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
		local ox, oy, oz = s.x, s.y, s.z
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
				if h.alive and segDist(h.x, h.y + 1.5, h.z, ox, oy, oz, s.x, s.y, s.z) <= s.radius then
					table.insert(sim.events, {
						k = "hit",
						hero = h.id,
						damage = s.damage,
						e = s.enemyId,
						cc = s.cc,
						ccTime = s.ccTime,
						ccValue = s.ccValue,
						pull = s.pull,
					})
					if s.pull then
						local g = sim.byId[s.enemyId]
						if g then
							g.hookUntil = sim.now + s.pull.time -- reeling in
						end
					end
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
	stepBombs(sim, heroes)
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
		if e.alive and not e.disguised then -- a disguised Mimic is a citizen until it shows itself
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
	local function weight(kind: string): number
		return if EnemySim.enabled(sim.config, kind) then mix[kind] or 0 else 0 -- a cut type is never picked
	end
	local total = 0
	for _, kind in sim.config.Enemies.order do
		total += weight(kind)
	end
	local r = sim.rngNext() * total
	for _, kind in sim.config.Enemies.order do
		r -= weight(kind)
		if r <= 0 and weight(kind) > 0 then
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
				local first = if x and y and z then EnemySim.spawn(sim, enemyKind, x, y, z, 1) else nil
				if first then
					EnemySim.company(sim, first)
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

-- The robots a spawn brings along: a Swarmer's pack (pack - 1 more) and a Captain's escort. Returns them
-- (each with the leader's level and tag set by the caller).
function EnemySim.company(sim: Sim, lead: Enemy, escort: boolean?): { Enemy }
	local cfg = lead.cfg
	local out = {}
	local function near(kind: string, k: number, n: number)
		local kc = sim.config.Enemies[kind]
		local a = k / n * math.pi * 2
		local r = if cfg.pack then 3 else 6
		local x, z = lead.x + math.cos(a) * r, lead.z + math.sin(a) * r
		local y = if kc.ai == "flyer" then lead.y + (kc.hover and kc.hover.min or 14) else lead.y
		if
			kc.ai ~= "flyer"
			and (
				sim.heightAt(x, z, lead.y) > lead.y - halfHeight(lead.cfg) + 2.5
				or (not kc.sea and sim.water(x, sim.waterTop + 1, z))
			)
		then
			-- that spot is a building (spawn would stand it on the roof) or the water: start on the leader's
			-- own spot (a hair apart, so separate() can spread them)
			x, z = lead.x + math.cos(a) * 0.1, lead.z + math.sin(a) * 0.1
		end
		local e = EnemySim.spawn(sim, kind, x, y, z, lead.level)
		if e then
			e.tag = lead.tag
			table.insert(out, e)
		end
	end
	if cfg.pack then
		for k = 1, cfg.pack - 1 do
			near(lead.kind, k, cfg.pack - 1)
		end
	end
	if cfg.escort and escort ~= false then
		for k = 1, cfg.escort.n do
			local kind = cfg.escort.kinds[(k - 1) % #cfg.escort.kinds + 1]
			if EnemySim.enabled(sim.config, kind) then
				near(kind, k, cfg.escort.n)
			end
		end
	end
	return out
end

-- A Grappler's hook on a hero at (px, py, pz): the flat move (to `reel` studs short of the Grappler), the drop
-- down to it, and the travel MoveGuard grants for it. The drop is not granted: falling is free in MoveCheck
-- up to terminal speed, so granting it would only bank budget an exploiter could spend elsewhere.
function EnemySim.hookPull(pull: any, px: number, py: number, pz: number): (number, number, number, number)
	local tx, ty, tz = pull.x - px, pull.y - py, pull.z - pz
	local flat = math.sqrt(tx * tx + tz * tz)
	local len = math.max(0, flat - pull.reel)
	local mx, mz = 0, 0
	if flat > 0.1 then
		mx, mz = tx / flat * len, tz / flat * len
	else
		len = 0
	end
	return mx, mz, math.min(0, ty), len + 10 -- + the arc's 3-stud lift and some slack
end

-- The next robot type after order index `index` whose switch is on (wraps; the Dev panel's robot button)
function EnemySim.nextEnabled(config: any, index: number): number
	local order = config.Enemies.order
	for k = 1, #order do
		local i = (index + k - 1) % #order + 1
		if EnemySim.enabled(config, order[i]) then
			return i
		end
	end
	return 1
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
