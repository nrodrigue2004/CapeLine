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
-- Events (drained by BossService): warn, strike, pull, phase, objective, dead, retreat.

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
	}
end

local function startAttack(sim: Sim, now: number, heroes: { Hero })
	local list, hazard = {}, nil
	for _, a in sim.cfg.attacks do
		if table.find(a.phases, sim.phase) then
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
	sim.nextAttack = now + atk.warn + sim.cfg.gap[sim.phase]
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
	if p.shape == "ring" or p.shape == "circles" then
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

local function resolve(sim: Sim, p: Pending, heroes: { Hero })
	local hits = {}
	local dmg = heroDamage(sim, p.coeff)
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
	if p.shape == "circles" then
		ev.points = p.points
		ev.r = p.r
	elseif p.shape == "pull" then
		ev.r = p.nova
	else
		ev.r = p.r
	end
	table.insert(sim.events, ev)
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
	-- move toward the crowd and face it
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
		if sim.cfg.speed > 0 and #sim.pending == 0 then
			local dx, dz = cx - sim.x, cz - sim.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 40 then
				local stepLen = math.min(d - 40, sim.cfg.speed * dt)
				local nx, nz = sim.x + dx / d * stepLen, sim.z + dz / d * stepLen
				local hx, hz = nx - sim.homeX, nz - sim.homeZ
				local hd = math.sqrt(hx * hx + hz * hz)
				if hd > sim.cfg.arenaRadius then
					nx = sim.homeX + hx / hd * sim.cfg.arenaRadius
					nz = sim.homeZ + hz / hd * sim.cfg.arenaRadius
				end
				sim.x, sim.z = nx, nz
			end
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
