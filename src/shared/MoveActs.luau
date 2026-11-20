--!strict
-- MoveActs: the 20 mobility moves (nate's mobility upgrade rework, 2026-11-20; Config.Move.moves, each pick's ranks 3
-- and 5) as pure maths. The device (MoveController, Controllers.MoveActClient) decides when a move goes off from
-- these, the server (Services.MoveActService) checks the same numbers on its own clock and history before it hits,
-- breaks or grants anything, and the tests run both. Vectors are plain numbers; nothing here touches an Instance.
-- * the wire: ids (the 20 in pick, rank, option order) and num / idOf for the MoveAct remote's first argument
-- * cooldowns: ready / start on a { [id] = until } book (the device's and the server's)
-- * Flight: dive (Sonic Boom Dive), inWake / wakeCruise (Slipstream), phaseOn (Phase), blazeDamage (Blazing Ram)
-- * Super-speed: circled (Tornado Run), stopped (Afterimage), wakeSpeed (Sonic Wake), blinkReach (Blink)
-- * Leaping: impact (Impact Landing), apex / meteorAim (Meteor Strike), moonLeap (Moon Jump)
-- * Acrobat: chainStep / kickMult (Kick Chain), dropPick (Ceiling Drop), slingPlan (Slingshot)
-- * Swing: secondLine / dashPlan (Double Zip), aimPick (Yank), wallKick / bowl (Wrecking Kick)
-- Every speed a move adds stays inside its pick's MoveGuard cap (tests check each one through MoveCheck); the three
-- that cannot (Blink, Slingshot, Ceiling Drop's dash) are server-granted distances like Dash Strike.

local MoveActs = {}

local function len3(x: number, y: number, z: number): number
	return math.sqrt(x * x + y * y + z * z)
end
local function len2(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

---------------------------------------------------------------------------
-- The wire and cooldowns
---------------------------------------------------------------------------

-- The 20 move ids in a fixed order: each pick (mobilityOrder), its choice ranks, then the two options
function MoveActs.ids(base: any): { string }
	local out = {}
	for _, pick in base.mobilityOrder do
		local rows = base.mobility[pick].ranks or {}
		for _, r in base.choices or {} do
			local row = rows[r]
			for _, id in (row and row.choice) or {} do
				table.insert(out, id)
			end
		end
	end
	return out
end

local cache: { [any]: { list: { string }, num: { [string]: number } } } = {}
local function wire(base: any)
	local w = cache[base]
	if not w then
		local list = MoveActs.ids(base)
		local num = {}
		for i, id in list do
			num[id] = i
		end
		w = { list = list, num = num }
		cache[base] = w
	end
	return w
end

function MoveActs.num(base: any, id: string): number?
	return wire(base).num[id]
end

function MoveActs.idOf(base: any, num: number): string?
	return wire(base).list[num]
end

-- The pick a move belongs to
function MoveActs.pickOf(base: any, id: string): string?
	for _, pick in base.mobilityOrder do
		for _, row in base.mobility[pick].ranks or {} do
			if row.choice and table.find(row.choice, id) then
				return pick
			end
		end
	end
	return nil
end

-- Is the move off its cooldown? (slack: the server's share of it, for lag; 1 on the device)
function MoveActs.ready(book: { [string]: number }, id: string, now: number): boolean
	return now >= (book[id] or -math.huge)
end

-- Start the cooldown: `cd` seconds (times slack, the server's leeway) from now
function MoveActs.start(book: { [string]: number }, id: string, now: number, cd: number, slack: number?)
	book[id] = now + cd * (slack or 1)
end

---------------------------------------------------------------------------
-- Flight
---------------------------------------------------------------------------

-- Sonic Boom Dive: a landing that fell `fall` studs and hit at `speed` studs/s or more
function MoveActs.dive(m: any, fall: number, speed: number): boolean
	return fall >= m.drop and speed >= m.speed
end

-- Slipstream: is point p in the wake of a leader at l heading along (hx, hy, hz) (a unit vector)? Behind it, at most
-- `length` back, within `width` of the line
function MoveActs.inWake(
	m: any,
	lx: number,
	ly: number,
	lz: number,
	hx: number,
	hy: number,
	hz: number,
	px: number,
	py: number,
	pz: number
): boolean
	local dx, dy, dz = px - lx, py - ly, pz - lz
	local back = -(dx * hx + dy * hy + dz * hz) -- how far behind
	if back <= 0 or back > m.length then
		return false
	end
	local sx, sy, sz = dx + hx * back, dy + hy * back, dz + hz * back -- off the line
	return len3(sx, sy, sz) <= m.width
end

-- Slipstream: an ally's cruise in the wake (never past their own boost)
function MoveActs.wakeCruise(m: any, cruise: number, boost: number): number
	return math.min(cruise * m.ally, boost)
end

-- Phase: may a flicker start now (cooldown since the last one ended, and stamina for its drain)?
function MoveActs.phaseOn(m: any, endedAt: number, now: number, stamina: number): boolean
	return now - endedAt >= m.cooldown and stamina >= m.drain * 0.25
end

-- Phase: does the flicker go on? Up to `time` s; while still inside a building, up to twice that
function MoveActs.phaseHolds(m: any, startedAt: number, now: number, inside: boolean): boolean
	local t = now - startedAt
	return t < m.time or (inside and t < m.time * 2)
end

-- Blazing Ram: a ram's structure damage and how hard its pieces fly
function MoveActs.blazeDamage(m: any, dmg: number): number
	return dmg * m.ram
end

---------------------------------------------------------------------------
-- Super-speed
---------------------------------------------------------------------------

export type Sample = { x: number, z: number, t: number, s: number }

-- Tornado Run: the run's last samples (oldest first: position, time, speed). True with the middle when, inside the
-- last `window` s, every sample was at `speed` or more, within `radius` of their middle, and the run turned round
-- it `turns` times or more
function MoveActs.circled(m: any, samples: { Sample }, now: number): (boolean, number, number)
	local first = 1
	while first <= #samples and now - samples[first].t > m.window do
		first += 1
	end
	local n = #samples - first + 1
	if n < 8 then
		return false, 0, 0
	end
	local cx, cz = 0, 0
	for i = first, #samples do
		local s = samples[i]
		if s.s < m.speed then
			return false, 0, 0
		end
		cx += s.x
		cz += s.z
	end
	cx, cz = cx / n, cz / n
	local turned = 0
	local last: number? = nil
	for i = first, #samples do
		local s = samples[i]
		if len2(s.x - cx, s.z - cz) > m.radius then
			return false, 0, 0
		end
		local a = math.atan2(s.z - cz, s.x - cx)
		if last then
			turned += (a - last + math.pi) % (2 * math.pi) - math.pi
		end
		last = a
	end
	return math.abs(turned) / (2 * math.pi) >= m.turns, cx, cz
end

-- Afterimage: a hard stop: from `from` studs/s or more (peak, `ago` s back) to under `to` now, within `within` s
function MoveActs.stopped(m: any, peak: number, ago: number, speed: number): boolean
	return peak >= m.from and speed <= m.to and ago <= m.within
end

-- Sonic Wake: fast enough to flip cars and crack windows
function MoveActs.wakeSpeed(m: any, speed: number): boolean
	return speed >= m.speed
end

-- Blink: how far it goes along the stick with a wall `wall` studs away (nil: none in range), stopping 2 short
function MoveActs.blinkReach(m: any, wall: number?): number
	return math.max(0, math.min(m.range, if wall then wall - 2 else m.range))
end

---------------------------------------------------------------------------
-- Leaping
---------------------------------------------------------------------------

-- Impact Landing: after `fall` studs of fall, the stun's radius (nil: too small a drop) and whether it craters
function MoveActs.impact(m: any, fall: number): (number?, boolean)
	if fall < m.minFall then
		return nil, false
	end
	local k = math.clamp((fall - m.minFall) / (m.fullFall - m.minFall), 0, 1)
	return m.radius[1] + (m.radius[2] - m.radius[1]) * k, fall >= m.crater
end

-- Meteor Strike: near the top of a leap (rising or falling slower than `apex`)
function MoveActs.apex(m: any, vy: number): boolean
	return math.abs(vy) <= m.apex
end

-- Meteor Strike: where the pound lands (the aim, pulled in to `range`) and how long it takes at `speed`
function MoveActs.meteorAim(
	m: any,
	ox: number,
	oy: number,
	oz: number,
	tx: number,
	ty: number,
	tz: number
): (number, number, number, number)
	local dx, dy, dz = tx - ox, ty - oy, tz - oz
	local d = len3(dx, dy, dz)
	if d > m.range then
		local k = m.range / d
		dx, dy, dz, d = dx * k, dy * k, dz * k, m.range
	end
	return ox + dx, oy + dy, oz + dz, math.max(0.1, d / m.speed)
end

-- Moon Jump: the extra mid-air leap, `share` of a full Leaping leap along the stick (cfg: the hero's Config.Move)
function MoveActs.moonLeap(
	cfg: any,
	launch: (any, number, number, number) -> (number, number, number),
	fx: number,
	fz: number
): (number, number, number)
	local vx, vy, vz = launch(cfg, fx, fz, 1)
	local k = cfg.moves.moonJump.share
	return vx * k, vy * k, vz * k
end

---------------------------------------------------------------------------
-- Acrobat
---------------------------------------------------------------------------

-- Kick Chain: the chain after a kick-off `since` s after the last one (a kick soon enough adds one, up to `most`)
function MoveActs.chainStep(m: any, chain: number, since: number): number
	if since > m.within then
		return 1
	end
	return math.min(m.most, chain + 1)
end

-- Kick Chain: the kick's speed multiplier for this place in the chain (the first is a plain kick)
function MoveActs.kickMult(m: any, chain: number): number
	return 1 + m.step * math.clamp(chain - 1, 0, m.most - 1)
end

export type Cand = { id: number, x: number, y: number, z: number }

-- Ceiling Drop: the robot under a hero letting go at o: below it, within `reach`, inside `cone` degrees of straight
-- down; the nearest
function MoveActs.dropPick(m: any, ox: number, oy: number, oz: number, cands: { Cand }): Cand?
	local best: Cand?, bestD = nil, math.huge
	local cosCone = math.cos(math.rad(m.cone))
	for _, c in cands do
		local dx, dy, dz = c.x - ox, c.y - oy, c.z - oz
		local d = len3(dx, dy, dz)
		if d <= m.reach and d > 1e-3 and dy < -2 and -dy / d >= cosCone and d < bestD then
			best, bestD = c, d
		end
	end
	return best
end

-- Slingshot: the launch off a wall with normal (nx, nz) along the camera's flat look: the way it goes (never back
-- into the wall), the landing offset and the arc's time and height
function MoveActs.slingPlan(
	m: any,
	nx: number,
	nz: number,
	lx: number,
	lz: number
): (number, number, number, number)
	local fx, fz = lx, lz
	local l = len2(fx, fz)
	if l < 1e-3 then
		fx, fz = nx, nz
	else
		fx, fz = fx / l, fz / l
	end
	local into = fx * nx + fz * nz
	if into < 0.3 then
		-- turned toward the wall: take the look's part along the wall and push off it
		fx, fz = fx - nx * into + nx * 0.6, fz - nz * into + nz * 0.6
		local k = len2(fx, fz)
		fx, fz = fx / k, fz / k
	end
	return fx * m.range, fz * m.range, m.time, m.up
end

-- An arc's fastest moment (MoveController.arcTo: lerp plus a 4h u(1-u) lift): the start, (d + 4h up) / time
function MoveActs.arcPeak(dx: number, dy: number, dz: number, time: number, height: number): number
	return len3(dx, dy + 4 * height, dz) / time
end

---------------------------------------------------------------------------
-- Swing
---------------------------------------------------------------------------

-- Double Zip: the second line's way, the flat look turned `spread` degrees (side: 1 or -1)
function MoveActs.secondLine(m: any, lx: number, lz: number, side: number): (number, number)
	local a = math.rad(m.spread) * side
	local c, s = math.cos(a), math.sin(a)
	return lx * c - lz * s, lx * s + lz * c
end

-- Double Zip: how long the shot forward takes: never faster than `speed` or the swing's own zip
function MoveActs.dashTime(m: any, zipCap: number, dist: number): number
	return math.max(0.15, dist / math.min(m.speed, zipCap))
end

-- Yank: the target nearest the aim from o along the unit look l: within `range` and `cone` degrees
function MoveActs.aimPick(
	m: any,
	ox: number,
	oy: number,
	oz: number,
	lx: number,
	ly: number,
	lz: number,
	cands: { Cand }
): Cand?
	local best: Cand?, bestDot = nil, math.cos(math.rad(m.cone))
	for _, c in cands do
		local dx, dy, dz = c.x - ox, c.y - oy, c.z - oz
		local d = len3(dx, dy, dz)
		if d <= m.range and d > 3 then
			local dot = (dx * lx + dy * ly + dz * lz) / d
			if dot >= bestDot then
				best, bestDot = c, dot
			end
		end
	end
	return best
end

-- Wrecking Kick: a swing into a wall this fast kicks it out (a ram)
function MoveActs.wallKick(m: any, speed: number): boolean
	return speed >= m.speed
end

-- Wrecking Kick: a release this fast bowls the robots along its path
function MoveActs.bowl(m: any, speed: number): boolean
	return speed >= m.bowl
end

return MoveActs
