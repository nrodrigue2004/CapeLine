--!strict
-- BossSim: one world boss fight as plain data (spec: World boss "3 phases (66% and 33%), with weak points,
-- one hazard per phase, shared bar"; Boss.State). BossService feeds it hero positions and hits; it moves
-- the boss, picks attacks, warns, then resolves them against where the heroes are when the warning ends.
-- * Body parts and weak points are hit targets at offsets in the boss's facing frame; weak points take x2.
-- * Objectives: Rustjaw's shoulder cannons shell heroes until broken; the Maw's generators heal it while
--   they stand. Breaking them is the "objectives" part of contribution.
-- * Phases 2 and 3 alternate the phase's hazard with the normal attacks.
-- * Hits on heroes: (20 + 4 x level) x coeff, like robots. Ground attacks (ring, circles) miss heroes flying
--   more than 12 studs up; the cone and lines reach as high as the boss.
-- Events (drained by BossService): warn, strike, pull, phase, objective, dead, retreat, smash, enrage.
-- * Buildings (nate's playtest 2026-11-19, "Boss is stuck between building"): a walking boss smashes through any
--   building in its footprint (smash events: BuildingService blasts them within the collapse caps) and slows while
--   it plows; a pinned building (beacon hosts, side quest roofs) pushes it around instead. Last resort: if it has
--   not got anywhere for `unstick.after` seconds it leaps (telegraphed) to open ground near its crowd.
--   sim.blocks(x, z, r) gives the standing building boxes near a point (BuildingState.boxesNear); nil = no city.
-- * Counters (same playtest, "a lot of bosses I can just fly stepping with ranged moves"): every boss threatens
--   every mobility and range, each telegraphed: homing shots at airborne heroes away from it (react "air"), a
--   swat or snap at heroes hovering near its body (react "hover", a column), a gap closer on a hero who has stayed
--   far away too long (react "kite": a leap for the walker, a tether yank for the others), and it enrages
--   (faster, harder hits) when nobody has been close for a while. Melee heroes on the ground are never their
--   targets; a reactive attack never takes two slots in a row, so the normal rotation still runs.

local BossMath = if script then require(script.Parent.BossMath) else (require :: any)("./BossMath")

local BossSim = {}

export type Hero = { id: number, x: number, y: number, z: number, alive: boolean }
export type Objective = {
	idx: number,
	alive: boolean,
	hp: number,
	maxHp: number,
	x: number,
	y: number,
	z: number,
	nextFire: number,
}
export type Pending = {
	a: string,
	shape: string,
	src: string, -- "boss" or "cannon"
	resolveAt: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	r: number,
	arc: number,
	width: number,
	length: number,
	points: { { number } }, -- circles: { x, z }; lines: { dirX, dirZ }
	coeff: number,
	struct: boolean,
	nova: number,
	cover: boolean,
	up: number, -- how high above its feet a ring reaches (12 by default)
	lo: number, -- a column's floor and ceiling above its feet
	hi: number,
	track: number, -- homing: the share of a target's move the shot follows, at most maxTrack studs
	maxTrack: number,
	shots: { { number } }, -- homing and tether: { x, y, z, heroId } locked when the warning starts
	yank: number, -- tether: a hit pulls the hero in to this far from the boss
	drop: number, -- column: a hit knocks the hero down this far
	leap: boolean, -- the boss lands at (x, z) when it resolves
}
export type Sim = {
	Config: any,
	cfg: any,
	id: string,
	level: number,
	x: number,
	y: number,
	z: number,
	homeX: number,
	homeZ: number,
	yaw: number,
	hp: number,
	maxHp: number,
	phase: number,
	state: string, -- landing, fight, dead, retreat
	fightAt: number,
	endsAt: number,
	nextAttack: number,
	cycle: number,
	pending: { Pending },
	objectives: { Objective },
	rng: any,
	events: { any },
	lastStep: number,
	shield: number, -- hits left on a phase shield (War-Frame), 0 = none
	cover: { { number } }, -- pillars that block covered lines: { x, z, r }
	blocks: ((number, number, number) -> { any })?, -- standing building boxes near a point (nil: open ground)
	smashAt: { [number]: number }, -- building id -> last smash
	stuckFor: number, -- seconds it wanted to walk and got nowhere
	stuck: boolean,
	far: { [number]: number }, -- hero id -> seconds spent far away (kiting)
	closeAt: number, -- last time any hero was close
	enraged: boolean,
	cool: { [string]: number }, -- reactive attack id -> ready again at
	lastReact: boolean, -- the last attack was a reactive one
}

local function objectHp(Config: any, hits: number, level: number): number
	local p = Config.Stats.power
	return math.floor(hits * (p.base + p.perLevel * level) + 0.5)
end

function BossSim.new(
	Config: any,
	bossId: string,
	x: number,
	groundY: number,
	z: number,
	maxHp: number,
	level: number,
	now: number,
	rng: any
): Sim
	local cfg = Config.Boss.bosses[bossId]
	assert(cfg, "unknown boss " .. bossId)
	local sched = Config.Boss.schedule
	local sim: Sim = {
		Config = Config,
		cfg = cfg,
		id = bossId,
		level = level,
		x = x,
		y = groundY,
		z = z,
		homeX = x,
		homeZ = z,
		yaw = 0,
		hp = maxHp,
		maxHp = maxHp,
		phase = 1,
		state = "landing",
		fightAt = now + sched.landing,
		endsAt = now + sched.landing + sched.lifespan,
		nextAttack = now + sched.landing + 2,
		cycle = 0,
		pending = {},
		objectives = {},
		rng = rng,
		events = {},
		lastStep = now,
		shield = 0,
		cover = {},
		blocks = nil,
		smashAt = {},
		stuckFor = 0,
		stuck = false,
		far = {},
		closeAt = now + sched.landing,
		enraged = false,
		cool = {},
		lastReact = false,
	}
	if cfg.lifespan then
		sim.endsAt = now + sched.landing + cfg.lifespan
	end
	local o = cfg.objectives
	for i, row in o.list do
		local ox, oy, oz
		if row.ring then
			local a = math.rad(row.ring)
			local r = cfg.arenaRadius * 0.75
			ox, oy, oz = x + math.cos(a) * r, groundY + 8, z + math.sin(a) * r
		else
			ox, oy, oz = 0, 0, 0 -- moves with the boss (BossSim.objectivePos)
		end
		local hp = objectHp(Config, o.hits, level)
		table.insert(sim.objectives, {
			idx = i,
			alive = true,
			hp = hp,
			maxHp = hp,
			x = ox,
			y = oy,
			z = oz,
			nextFire = now + sched.landing + 3 + i,
		})
	end
	return sim
end

-- Where an objective is now
function BossSim.objectivePos(sim: Sim, ob: Objective): (number, number, number)
	local row = sim.cfg.objectives.list[ob.idx]
	if row.at then
		local dx, dy, dz = BossMath.worldOffset(sim.yaw, row.at[1], row.at[2], row.at[3])
		return sim.x + dx, sim.y + dy, sim.z + dz
	end
	return ob.x, ob.y, ob.z
end

export type Target = {
	key: string,
	x: number,
	y: number,
	z: number,
	r: number,
	weak: boolean,
	objective: number?,
}

-- Every hittable spot right now (none while it lands, dies or leaves)
function BossSim.targets(sim: Sim): { Target }
	local out: { Target } = {}
	if sim.state ~= "fight" then
		return out
	end
	for _, t in sim.cfg.targets do
		local dx, dy, dz = BossMath.worldOffset(sim.yaw, t.at[1], t.at[2], t.at[3])
		table.insert(
			out,
			{ key = t.id, x = sim.x + dx, y = sim.y + dy, z = sim.z + dz, r = t.r, weak = t.weak == true }
		)
	end
	for _, ob in sim.objectives do
		if ob.alive then
			local x, y, z = BossSim.objectivePos(sim, ob)
			table.insert(
				out,
				{ key = "obj" .. ob.idx, x = x, y = y, z = z, r = 5, weak = false, objective = ob.idx }
			)
		end
	end
	return out
end

local function weakKey(sim: Sim, key: string): boolean
	for _, t in sim.cfg.targets do
		if t.id == key then
			return t.weak == true
		end
	end
	return false
end

-- Damage a target. Returns damage dealt to the boss, damage dealt to an objective, and the objective
-- index if this hit broke it.
function BossSim.damage(sim: Sim, key: string, amount: number): (number, number, number?)
	if sim.state ~= "fight" or amount <= 0 then
		return 0, 0, nil
	end
	local objIdx = tonumber(string.match(key, "^obj(%d+)$"))
	if objIdx then
		local ob = sim.objectives[objIdx]
		if not ob or not ob.alive then
			return 0, 0, nil
		end
		local dealt = math.min(ob.hp, amount)
		ob.hp -= dealt
		if ob.hp <= 0 then
			ob.alive = false
			table.insert(sim.events, { k = "objective", idx = objIdx })
			return 0, dealt, objIdx
		end
		return 0, dealt, nil
	end
	if sim.shield > 0 then
		-- the phase shield: nothing gets through; each hit on its key point knocks one hit off it
		if key == sim.cfg.shield.key then
			sim.shield -= 1
			table.insert(sim.events, { k = "shield", left = sim.shield })
		end
		return 0, 0, nil
	end
	local dmg = amount * (if weakKey(sim, key) then sim.Config.Boss.weakMult else 1)
	local dealt = math.min(sim.hp, dmg)
	sim.hp -= dealt
	local phase = BossMath.phase(sim.Config, sim.hp / sim.maxHp)
	if phase > sim.phase then -- phases only go forward, even if the generators heal it back
		sim.phase = phase
		table.insert(sim.events, { k = "phase", phase = phase })
		local sh, su = sim.cfg.shield, sim.cfg.summon
		if sh and sh.phase == phase and sim.hp > 0 then
			sim.shield = sh.hits
			table.insert(sim.events, { k = "shield", left = sim.shield })
		end
		if su and su.phase == phase then
			table.insert(sim.events, { k = "summon", kind = su.kind, n = su.n })
		end
	end
	if sim.hp <= 0 then
		sim.state = "dead"
		sim.pending = {}
		table.insert(sim.events, { k = "dead" })
	end
	return dealt, 0, nil
end

local function heroDamage(sim: Sim, coeff: number): number
	local s = sim.Config.Enemies.scale
	return (s.dmgBase + s.dmgPerLevel * sim.level) * coeff
end

local function near(sim: Sim, heroes: { Hero }, range: number): { Hero }
	local out = {}
	for _, h in heroes do
		if h.alive and (h.x - sim.x) ^ 2 + (h.z - sim.z) ^ 2 <= range * range then
			table.insert(out, h)
		end
	end
	return out
end

local function turnToward(sim: Sim, tx: number, tz: number, dt: number)
	local dx, dz = tx - sim.x, tz - sim.z
	if dx * dx + dz * dz < 1 then
		return
	end
	local want = math.atan2(-dx, -dz) -- Roblox yaw facing (dx, dz)
	local d = (want - sim.yaw + math.pi) % (2 * math.pi) - math.pi
	local step = math.rad(sim.cfg.turn) * dt
	sim.yaw += math.clamp(d, -step, step)
end

local function addPending(sim: Sim, p: Pending, warn: number)
	table.insert(sim.pending, p)
	table.insert(sim.events, {
		k = "warn",
		a = p.a,
		shape = p.shape,
		src = p.src,
		x = p.x,
		y = p.y,
		z = p.z,
		yaw = p.yaw,
		r = p.r,
		arc = p.arc,
		width = p.width,
		length = p.length,
		points = p.points,
		t = warn,
		nova = p.nova,
		up = if p.up ~= 12 then p.up else nil,
		lo = if p.shape == "column" then p.lo else nil,
		hi = if p.shape == "column" then p.hi else nil,
		shots = if #p.shots > 0 then p.shots else nil,
		leap = if p.leap then true else nil,
	})
	if p.shape == "pull" then
		table.insert(sim.events, { k = "pull", x = p.x, y = p.y, z = p.z, r = p.r, t = warn })
	end
end

local function pending(sim: Sim, atk: any, now: number, src: string): Pending
	return {
		a = atk.id,
		shape = atk.shape,
		src = src,
		resolveAt = now + atk.warn,
		x = sim.x,
		y = sim.y,
		z = sim.z,
		yaw = sim.yaw,
		r = atk.r or 0,
		arc = atk.arc or 360,
		width = atk.width or 0,
		length = atk.length or 0,
		points = {},
		coeff = atk.coeff,
		struct = atk.struct == true,
		nova = atk.nova or 0,
		cover = atk.cover == true,
		up = atk.up or 12,
		lo = atk.lo or 0,
		hi = atk.hi or 0,
		track = atk.track or 0,
		maxTrack = atk.maxTrack or 0,
		shots = {},
		yank = atk.yank or 0,
		drop = atk.drop or 0,
		leap = atk.leap == true,
	}
end

-- Counters (nate's playtest 2026-11-19): who is close (melee reach of the body, not above its top), who is in the
-- air away from it, who hovers by its body
local function flat(sim: Sim, h: Hero): number
	return math.sqrt((h.x - sim.x) ^ 2 + (h.z - sim.z) ^ 2)
end

function BossSim.isClose(sim: Sim, h: Hero): boolean
	local c = sim.cfg.counters
	return c ~= nil and flat(sim, h) <= c.meleeR and h.y - sim.y <= sim.cfg.height + 15
end

function BossSim.isAir(sim: Sim, h: Hero): boolean
	local c = sim.cfg.counters
	return c ~= nil and h.y - sim.y > c.air and not BossSim.isClose(sim, h)
end

local function inColumn(sim: Sim, a: any, h: Hero): boolean
	local up = h.y - sim.y
	return flat(sim, h) <= a.r and up >= a.lo and up <= a.hi
end

local function circleBox(x: number, z: number, r: number, b: any): boolean
	local dx = math.max(math.abs(x - b.x) - b.sx / 2, 0)
	local dz = math.max(math.abs(z - b.z) - b.sz / 2, 0)
	return dx * dx + dz * dz < r * r
end

local function bodyR(sim: Sim): number
	return sim.cfg.bodyR or 12
end

-- Is there room for its body at (x, z)? (no standing building in the way)
function BossSim.clearAt(sim: Sim, x: number, z: number, r: number): boolean
	local f = sim.blocks
	if not f then
		return true
	end
	for _, b in f(x, z, r) do
		if circleBox(x, z, r, b) then
			return false
		end
	end
	return true
end

local function leash(sim: Sim, x: number, z: number): (number, number)
	local hx, hz = x - sim.homeX, z - sim.homeZ
	local d = math.sqrt(hx * hx + hz * hz)
	local R = sim.cfg.arenaRadius
	if d > R then
		return sim.homeX + hx / d * R, sim.homeZ + hz / d * R
	end
	return x, z
end

-- Open ground for its feet near (x, z) inside its arena: the point itself, else rings of points round it, else where
-- it stands (never back home: a leap must not lose ground)
function BossSim.openNear(sim: Sim, x: number, z: number): (number, number)
	local r = bodyR(sim)
	local px, pz = leash(sim, x, z)
	if BossSim.clearAt(sim, px, pz, r) then
		return px, pz
	end
	for ring = 1, 10 do
		local rad = ring * 18
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2 + ring * 0.3
			local qx, qz = leash(sim, x + math.cos(a) * rad, z + math.sin(a) * rad)
			if BossSim.clearAt(sim, qx, qz, r) then
				return qx, qz
			end
		end
	end
	return sim.x, sim.z
end

-- The reactive attack for now (and its target hero for a gap closer), or nil for the normal rotation
local function reactive(sim: Sim, now: number, heroes: { Hero }): (any?, Hero?)
	local c = sim.cfg.counters
	if not c then
		return nil, nil
	end
	local by: { [string]: any } = {}
	for _, a in sim.cfg.attacks do
		if a.react and table.find(a.phases, sim.phase) then
			by[a.react] = a
		end
	end
	if sim.stuck and by.kite and by.kite.leap then
		return by.kite, nil -- the last-resort unstick
	end
	if sim.lastReact then
		return nil, nil
	end
	local function ready(a: any): boolean
		return a ~= nil and now >= (sim.cool[a.id] or 0)
	end
	if ready(by.kite) then
		local best, bt = nil, c.kiteAfter
		local reach = if by.kite.leap then by.kite.up or 12 else math.huge -- a leap's slam can't reach a high flier
		for _, h in heroes do
			local f = sim.far[h.id] or 0
			if h.alive and f >= bt and h.y - sim.y <= reach then
				best, bt = h, f
			end
		end
		if best then
			return by.kite, best
		end
	end
	if ready(by.hover) then
		for _, h in heroes do
			if h.alive and inColumn(sim, by.hover, h) then
				return by.hover, nil
			end
		end
	end
	if ready(by.air) then
		for _, h in heroes do
			if h.alive and BossSim.isAir(sim, h) and flat(sim, h) <= 300 then
				return by.air, nil
			end
		end
	end
	return nil, nil
end

local function gapOf(sim: Sim): number
	local c = sim.cfg.counters
	return sim.cfg.gap[sim.phase] * (if sim.enraged and c then c.enrage.gap else 1)
end

local function startReactive(sim: Sim, atk: any, target: Hero?, now: number, heroes: { Hero })
	sim.lastReact = true
	sim.cool[atk.id] = now + (atk.cooldown or 8)
	local p = pending(sim, atk, now, "boss")
	if atk.shape == "homing" then
		for _, h in heroes do
			if #p.shots >= atk.count then
				break
			end
			if h.alive and BossSim.isAir(sim, h) and flat(sim, h) <= 300 then
				table.insert(p.shots, { h.x, h.y, h.z, h.id })
			end
		end
	elseif atk.shape == "tether" and target then
		table.insert(p.shots, { target.x, target.y, target.z, target.id })
	elseif atk.leap then
		local tx, tz = sim.homeX, sim.homeZ
		if target then
			tx, tz = target.x, target.z
		else
			local crowd = near(sim, heroes, sim.cfg.arenaRadius + 250)
			if #crowd > 0 then
				tx, tz = 0, 0
				for _, h in crowd do
					tx += h.x
					tz += h.z
				end
				tx /= #crowd
				tz /= #crowd
			end
		end
		p.x, p.z = BossSim.openNear(sim, tx, tz)
		sim.stuck = false
		sim.stuckFor = 0
	end
	if target then
		sim.far[target.id] = 0
	end
	addPending(sim, p, atk.warn)
	sim.nextAttack = now + atk.warn + gapOf(sim)
end

local function startAttack(sim: Sim, now: number, heroes: { Hero })
	local ratk, target = reactive(sim, now, heroes)
	if ratk then
		startReactive(sim, ratk, target, now, heroes)
		return
	end
	sim.lastReact = false
	local list, hazard = {}, nil
	for _, a in sim.cfg.attacks do
		if table.find(a.phases, sim.phase) and not a.react then
			if a.hazard then
				hazard = a
			else
				table.insert(list, a)
			end
		end
	end
	sim.cycle += 1
	local atk = if hazard and sim.cycle % 2 == 0 then hazard else list[(sim.cycle // 2) % #list + 1]
	local p = pending(sim, atk, now, "boss")
	local targets = near(sim, heroes, 300)
	if atk.shape == "circles" then
		for i = 1, atk.count do
			local h = targets[((i - 1) % math.max(1, #targets)) + 1]
			local bx, bz = if h then h.x else sim.x, if h then h.z else sim.z
			local spread = if i <= #targets then 0 else 24
			table.insert(
				p.points,
				{ bx + sim.rng:range(-spread, spread), bz + sim.rng:range(-spread, spread) }
			)
		end
	elseif atk.shape == "lines" then
		for i = 1, atk.count do
			local h = targets[((i - 1) % math.max(1, #targets)) + 1]
			local dx, dz
			if h then
				dx, dz = h.x - sim.x, h.z - sim.z
			else
				local a = sim.yaw + (i - 1) * 0.6
				dx, dz = -math.sin(a), -math.cos(a)
			end
			local l = math.sqrt(dx * dx + dz * dz)
			if l < 1e-3 then
				dx, dz, l = 0, -1, 1
			end
			table.insert(p.points, { dx / l, dz / l })
		end
	end
	addPending(sim, p, atk.warn)
	sim.nextAttack = now + atk.warn + gapOf(sim)
end

-- Is a pillar between the boss and this hero? (a circle crossing the segment, before the hero)
local function covered(sim: Sim, p: Pending, h: Hero): boolean
	local ax, az = p.x, p.z
	local bx, bz = h.x - ax, h.z - az
	local len2 = bx * bx + bz * bz
	if len2 < 1 then
		return false
	end
	for _, c in sim.cover do
		local t = math.clamp(((c[1] - ax) * bx + (c[2] - az) * bz) / len2, 0, 1)
		if t < 1 then
			local px, pz = ax + bx * t, az + bz * t
			if (c[1] - px) ^ 2 + (c[2] - pz) ^ 2 <= c[3] * c[3] then
				return true
			end
		end
	end
	return false
end

local function hitTest(sim: Sim, p: Pending, h: Hero): boolean
	local dx, dz = h.x - p.x, h.z - p.z
	local up = h.y - p.y
	if p.shape == "column" then
		return dx * dx + dz * dz <= p.r * p.r and up >= p.lo and up <= p.hi
	elseif p.shape == "homing" or p.shape == "tether" then
		for _, pt in p.points do
			if (h.x - pt[1]) ^ 2 + (h.y - pt[2]) ^ 2 + (h.z - pt[3]) ^ 2 <= p.r * p.r then
				return true
			end
		end
		return false
	elseif p.shape == "ring" then
		if up > p.up then
			return false
		end
	elseif p.shape == "circles" then
		if up > 12 then
			return false
		end
	elseif up > sim.cfg.height then
		return false
	end
	if p.shape == "ring" then
		return dx * dx + dz * dz <= p.r * p.r
	elseif p.shape == "pull" then
		return dx * dx + dz * dz <= p.nova * p.nova
	elseif p.shape == "cone" then
		local d = math.sqrt(dx * dx + dz * dz)
		if d > p.r then
			return false
		end
		if d < 4 then
			return true
		end
		local fx, fz = -math.sin(p.yaw), -math.cos(p.yaw)
		return (fx * dx + fz * dz) / d >= math.cos(math.rad(p.arc / 2))
	elseif p.shape == "circles" then
		for _, pt in p.points do
			if (h.x - pt[1]) ^ 2 + (h.z - pt[2]) ^ 2 <= p.r * p.r then
				return true
			end
		end
		return false
	elseif p.shape == "lines" then
		for _, dir in p.points do
			local along = dx * dir[1] + dz * dir[2]
			local side = math.abs(dx * dir[2] - dz * dir[1])
			if
				along >= 0
				and along <= p.length
				and side <= p.width / 2
				and not (p.cover and covered(sim, p, h))
			then
				return true
			end
		end
		return false
	end
	return false
end

-- Where each homing shot or tether ends up: it follows its target's move by `track`, at most maxTrack studs, so a
-- hero who keeps moving gets clear and one who hovers still is hit
local function homeIn(p: Pending, heroes: { Hero })
	local out = {}
	for _, s in p.shots do
		local x, y, z = s[1], s[2], s[3]
		for _, h in heroes do
			if h.id == s[4] and h.alive then
				local dx, dy, dz = h.x - x, h.y - y, h.z - z
				local d = math.sqrt(dx * dx + dy * dy + dz * dz)
				if d > 1e-3 then
					local m = math.min(d * p.track, p.maxTrack)
					x, y, z = x + dx / d * m, y + dy / d * m, z + dz / d * m
				end
				break
			end
		end
		table.insert(out, { x, y, z })
	end
	p.points = out
end

local function resolve(sim: Sim, p: Pending, heroes: { Hero })
	local hits = {}
	local c = sim.cfg.counters
	local dmg = heroDamage(sim, p.coeff) * (if sim.enraged and c then c.enrage.dmg else 1)
	if p.shape == "homing" or p.shape == "tether" then
		homeIn(p, heroes)
	end
	if p.leap then
		sim.x, sim.z = p.x, p.z -- it lands
	end
	for _, h in heroes do
		if h.alive and hitTest(sim, p, h) then
			table.insert(hits, { h.id, dmg })
		end
	end
	local ev: { [string]: any } =
		{ k = "strike", a = p.a, shape = p.shape, src = p.src, x = p.x, y = p.y, z = p.z, hits = hits }
	if p.struct then
		ev.struct = p.r
	end
	if p.yank > 0 then
		ev.yank = p.yank
	end
	if p.drop > 0 then
		ev.drop = p.drop
	end
	if p.leap then
		ev.leap = true
	end
	if p.shape == "circles" or p.shape == "homing" or p.shape == "tether" then
		ev.points = p.points
		ev.r = p.r
	elseif p.shape == "pull" then
		ev.r = p.nova
	else
		ev.r = p.r
	end
	table.insert(sim.events, ev)
end

-- Take a walking step to (nx, nz) among the buildings: a building in its footprint slows it and is smashed (a smash
-- event every `smash.every` seconds a building, BuildingService blasts it within the collapse caps); a pinned one
-- (a beacon host, a side quest roof) never breaks, so it pushes the boss out and it slides along it instead.
function BossSim.walk(sim: Sim, now: number, nx: number, nz: number)
	local f = sim.blocks
	local sm = sim.cfg.smash
	if not f or not sm then
		sim.x, sim.z = nx, nz
		return
	end
	local r = bodyR(sim)
	local list = f(nx, nz, r + sm.reach)
	local plow = false
	for _, b in list do
		if not b.pinned and circleBox(nx, nz, r + sm.reach, b) then
			plow = true
		end
	end
	if plow then
		nx, nz = sim.x + (nx - sim.x) * sm.slow, sim.z + (nz - sim.z) * sm.slow
	end
	-- pinned buildings push it out (twice, for corners between two of them)
	for _ = 1, 2 do
		for _, b in list do
			if b.pinned and circleBox(nx, nz, r, b) then
				local hx, hz = b.sx / 2, b.sz / 2
				local qx, qz = math.clamp(nx, b.x - hx, b.x + hx), math.clamp(nz, b.z - hz, b.z + hz)
				local ddx, ddz = nx - qx, nz - qz
				local d = math.sqrt(ddx * ddx + ddz * ddz)
				if d > 1e-3 then
					nx, nz = qx + ddx / d * r, qz + ddz / d * r
				else
					-- inside it: out through the nearest face
					local ex, ez = hx - math.abs(nx - b.x), hz - math.abs(nz - b.z)
					if ex < ez then
						nx = b.x + (if nx >= b.x then 1 else -1) * (hx + r)
					else
						nz = b.z + (if nz >= b.z then 1 else -1) * (hz + r)
					end
				end
			end
		end
	end
	sim.x, sim.z = nx, nz
	for _, b in list do
		if
			not b.pinned
			and circleBox(nx, nz, r + sm.reach, b)
			and now - (sim.smashAt[b.id] or -math.huge) >= sm.every
		then
			sim.smashAt[b.id] = now
			local hx, hz = b.sx / 2, b.sz / 2
			table.insert(sim.events, {
				k = "smash",
				id = b.id,
				x = math.clamp(nx, b.x - hx, b.x + hx),
				y = sim.y + sm.at,
				z = math.clamp(nz, b.z - hz, b.z + hz),
				r = r,
				dmg = sm.dmg,
			})
		end
	end
end

function BossSim.step(sim: Sim, now: number, heroes: { Hero })
	local dt = math.clamp(now - sim.lastStep, 0, 0.5)
	sim.lastStep = now
	if sim.state == "landing" then
		if now >= sim.fightAt then
			sim.state = "fight"
			table.insert(sim.events, { k = "fight" })
		end
		return
	end
	if sim.state ~= "fight" then
		return
	end
	if now >= sim.endsAt then
		sim.state = "retreat"
		sim.pending = {}
		table.insert(sim.events, { k = "retreat" })
		return
	end
	-- move toward the crowd and face it (through buildings: walk() smashes them, pinned ones push it round)
	local crowd = near(sim, heroes, sim.cfg.arenaRadius + 250)
	if #crowd > 0 then
		local cx, cz = 0, 0
		for _, h in crowd do
			cx += h.x
			cz += h.z
		end
		cx /= #crowd
		cz /= #crowd
		turnToward(sim, cx, cz, dt)
		-- it walks unless it is winding up its own attack (the cannons' shells never hold it up); a crowd far away
		-- makes it charge (chase.mult x speed past chase.beyond studs)
		local winding = false
		for _, p in sim.pending do
			winding = winding or p.src == "boss"
		end
		if sim.cfg.speed > 0 and not winding then
			local dx, dz = cx - sim.x, cz - sim.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 40 then
				local ch = sim.cfg.chase
				local speed = sim.cfg.speed * (if ch and d > ch.beyond then ch.mult else 1)
				local stepLen = math.min(d - 40, speed * dt)
				local nx, nz = leash(sim, sim.x + dx / d * stepLen, sim.z + dz / d * stepLen)
				local want = math.sqrt((nx - sim.x) ^ 2 + (nz - sim.z) ^ 2)
				local ox, oz = sim.x, sim.z
				BossSim.walk(sim, now, nx, nz)
				local u = sim.cfg.unstick
				if u and want > 0.05 then
					-- progress toward the crowd, not just movement: sliding to and fro along a pinned wall is stuck too
					local before = math.sqrt((cx - ox) ^ 2 + (cz - oz) ^ 2)
					local after = math.sqrt((cx - sim.x) ^ 2 + (cz - sim.z) ^ 2)
					if before - after < want * 0.25 then
						sim.stuckFor += dt
					else
						sim.stuckFor = math.max(0, sim.stuckFor - dt * 2)
					end
					if sim.stuckFor >= u.after and not sim.stuck then
						sim.stuck = true
						sim.nextAttack = math.min(sim.nextAttack, now)
					end
				end
			end
		end
	end
	-- who is close, who keeps away (the gap closers' clock), and the enrage when nobody comes close
	local c = sim.cfg.counters
	if c then
		local anyClose = #crowd == 0
		for _, h in crowd do
			if BossSim.isClose(sim, h) then
				anyClose = true
				sim.far[h.id] = 0
			elseif flat(sim, h) > c.kiteRange or h.y - sim.y > sim.cfg.height + 15 then
				sim.far[h.id] = (sim.far[h.id] or 0) + dt
			end
		end
		if anyClose then
			sim.closeAt = now
		end
		local want = now - sim.closeAt >= c.enrage.after
		if want ~= sim.enraged then
			sim.enraged = want
			table.insert(sim.events, { k = "enrage", on = want })
		end
	end
	-- generators heal; cannons shell
	local o = sim.cfg.objectives
	for _, ob in sim.objectives do
		if ob.alive then
			if o.heal then
				sim.hp = math.min(sim.maxHp, sim.hp + sim.maxHp * o.heal * dt)
			end
			if o.fire and now >= ob.nextFire then
				ob.nextFire = now + o.fire.every
				local targets = near(sim, heroes, 300)
				if #targets > 0 then
					local h = targets[sim.rng:int(1, #targets)]
					local x, _, z = BossSim.objectivePos(sim, ob)
					local p = pending(sim, {
						id = "Cannon",
						shape = "circles",
						r = o.fire.r,
						warn = o.fire.warn,
						coeff = o.fire.coeff,
					}, now, "cannon")
					p.x, p.y, p.z = x, sim.y, z
					p.points = { { h.x, h.z } }
					addPending(sim, p, o.fire.warn)
				end
			end
		end
	end
	if now >= sim.nextAttack then
		startAttack(sim, now, heroes)
	end
	for i = #sim.pending, 1, -1 do
		local p = sim.pending[i]
		if now >= p.resolveAt then
			table.remove(sim.pending, i)
			resolve(sim, p, heroes)
		end
	end
end

function BossSim.drain(sim: Sim): { any }
	local ev = sim.events
	sim.events = {}
	return ev
end

return BossSim
