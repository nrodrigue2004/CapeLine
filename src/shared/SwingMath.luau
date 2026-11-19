--!strict
-- SwingMath: the Swing mobility as pure maths (nate's playtest 2026-11-19: "Swinging should feel like
-- Spider-Man"). The client (MoveController) runs it every frame for its own hero, the tests and the swing path
-- preview (art/swing/path.luau) run the very same code over the game's own buildings, and the server's speed
-- check (MoveCheck through MoveMath.guardCap) holds it to the Swing cap. Vectors are plain numbers.
--
-- * findAnchor: where a line can hang from: a fan of rays ahead and above the hero along the camera's look
--   (and its travel), scored for a good swing (ahead, above, not too near or far), then snapped up to the
--   building's roof edge or corner when that is close above the hit. Only real geometry is ever hit (the
--   cast callback is a raycast), so a line never hangs from the empty sky: nil means no swing (the device
--   shows the miss cue).
-- * pivot: the point the hero swings under (in the plane of its travel; the line is drawn to the anchor).
-- * rope: the line's length (taut at once, its low point clear of the street under it).
-- * step: one pendulum step: the swing's own gravity pulls the hero through the arc (speed builds at the
--   bottom), the rope only pulls (a slack line lets the hero fall until it catches, and a catch turns most of
--   the fall into speed along the swing), the stick pumps forward and steers sideways, the rope reels in
--   toward its target, the speed is capped.
-- * phase: where on the arc the hero is: -1 high behind, 0 the bottom, +1 level ahead (the pose's arc phase).
-- * release: letting go flings forward and up keeping the swing's speed; a release on the rising half
--   (release.sweet) gets the bigger boost, all inside release.cap (under the server's Swing cap).
-- * zipPlan: a zip to a point (the anchor, a ledge): the arc's time and height, never faster than `zip`.
-- * boxCast: a raycast over plain boxes (the game's buildings) for the tests and the preview.

local SwingMath = {}

local function len3(x: number, y: number, z: number): number
	return math.sqrt(x * x + y * y + z * z)
end
local function len2(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

-- cast(ox, oy, oz, dx, dy, dz): a ray from the origin along (dx, dy, dz) (its full length); returns the hit
-- point and the surface normal, or nil
export type Cast = (
	number,
	number,
	number,
	number,
	number,
	number
) -> (number?, number, number, number, number, number)

export type Anchor = {
	x: number,
	y: number,
	z: number,
	nx: number,
	ny: number,
	nz: number,
	edge: boolean, -- snapped up to a roof edge or corner
	score: number,
}

-- The line's reach at a hero level
function SwingMath.range(cfg: any, level: number): number
	local m = cfg.mobility.swing
	return if level >= m.up.rangeLevel then m.up.range else m.range
end

-- a candidate's score: ahead along the aim, a good height above the hero, a good distance
local function score(
	m: any,
	px: number,
	py: number,
	pz: number,
	hx: number,
	hy: number,
	hz: number,
	aimX: number,
	aimZ: number,
	tx: number,
	tz: number
): number?
	local up = hy - py
	if up < m.minAbove then
		return nil
	end
	local fx, fz = hx - px, hz - pz
	local fd = len2(fx, fz)
	local A = m.aim
	if len3(fx, up, fz) < A.near then
		return nil -- right in the hero's face: no swing in it (zip or climb instead)
	end
	local along = if fd > 1e-3 then (fx * aimX + fz * aimZ) / fd else 1
	if along < A.minAlong then
		return nil -- behind or far off to the side
	end
	local s = along * A.wAlong
	s -= math.abs(up - A.up) / A.up * A.wUp
	s -= math.abs(fd - A.ahead) / A.ahead * A.wAhead
	local tl = len2(tx, tz)
	if tl > 1e-3 and fd > 1e-3 then
		s += (fx * tx + fz * tz) / (fd * tl) * A.wTravel
	end
	return s
end

-- Where a line can hang from. (px, py, pz): the hero; (lx, ly, lz): the camera's look; (tx, tz): the flat
-- travel (zeros when still); range: the line's reach. Returns the anchor (nil: nothing real to hang from) and
-- the number of rays cast (the device's budget).
function SwingMath.findAnchor(
	cfg: any,
	px: number,
	py: number,
	pz: number,
	lx: number,
	ly: number,
	lz: number,
	tx: number,
	tz: number,
	range: number,
	cast: Cast
): (Anchor?, number)
	local m = cfg.mobility.swing
	local A = m.aim
	local rays = 0
	local aimL = len2(lx, lz)
	local aimX, aimZ = if aimL > 1e-3 then lx / aimL else 0, if aimL > 1e-3 then lz / aimL else -1
	local looks = { { aimX, ly, aimZ } }
	local tl = len2(tx, tz)
	if tl > A.travelAt then
		local ux, uz = tx / tl, tz / tl
		if ux * aimX + uz * aimZ < math.cos(math.rad(A.travelApart)) then
			table.insert(looks, { ux, 0, uz })
		end
	end
	local best: Anchor? = nil
	for li, look in looks do
		for _, yaw in A.yaws do
			local a = math.rad(yaw)
			local c, s = math.cos(a), math.sin(a)
			local fx, fz = look[1] * c - look[3] * s, look[1] * s + look[3] * c
			for _, lift in m.lifts do
				local dx, dy, dz = fx, math.max(look[2], 0) + lift, fz
				local dl = len3(dx, dy, dz)
				dx, dy, dz = dx / dl * range, dy / dl * range, dz / dl * range
				rays += 1
				local hx, hy, hz, nx, ny, nz = cast(px, py, pz, dx, dy, dz)
				if hx then
					-- the travel look scores against its own aim; the camera's stays the main one
					local sx, sz = if li == 1 then aimX else fx, if li == 1 then aimZ else fz
					local sc = score(m, px, py, pz, hx, hy, hz, sx, sz, tx, tz)
					if sc and li > 1 then
						sc -= A.travelCost
					end
					if sc and (not best or sc > best.score) then
						best = { x = hx, y = hy, z = hz, nx = nx, ny = ny, nz = nz, edge = false, score = sc }
					end
				end
			end
		end
	end
	if not best then
		return nil, rays
	end
	-- a wall face: snap up to its roof edge (or the corner) when that is close above the hit
	local b = best :: Anchor
	local E = m.edge
	local nl = len2(b.nx, b.nz)
	if math.abs(b.ny) < 0.35 and nl > 1e-3 then
		local ux, uz = b.nx / nl, b.nz / nl
		local function wallAt(h: number): boolean
			rays += 1
			local hx = cast(b.x + ux * E.out, b.y + h, b.z + uz * E.out, -ux * E.out * 2, 0, -uz * E.out * 2)
			return hx ~= nil
		end
		if not wallAt(E.probe) then
			local lo, hi = 0, E.probe
			for _ = 1, E.steps do
				local mid = (lo + hi) / 2
				if wallAt(mid) then
					lo = mid
				else
					hi = mid
				end
			end
			local ey = b.y + lo - E.below
			if ey > b.y and len3(b.x - px, ey - py, b.z - pz) <= range then
				b.y = ey
				b.edge = true
			end
		end
	end
	return b, rays
end

-- The swing's pivot for a line to (ax, ay, az): the hero swings in the plane of its travel (dx, dz), under a
-- point at the anchor's height and as far ahead as the anchor is, keeping only `plane` of the anchor's sideways
-- offset (a line to a building at the street's side swings the hero along the street, swaying a little toward
-- it, never across into the wall). The line is still drawn to the real anchor.
function SwingMath.pivot(
	cfg: any,
	px: number,
	pz: number,
	ax: number,
	ay: number,
	az: number,
	dx: number,
	dz: number
): (number, number, number)
	local l = len2(dx, dz)
	if l < 1e-3 then
		return ax, ay, az
	end
	local ux, uz = dx / l, dz / l
	local ox, oz = ax - px, az - pz
	local fwd = math.max(0, ox * ux + oz * uz)
	local sx, sz = ox - ux * (ox * ux + oz * uz), oz - uz * (ox * ux + oz * uz)
	local k = cfg.mobility.swing.plane
	return px + ux * fwd + sx * k, ay, pz + uz * fwd + sz * k
end

-- The rope's length for a line from the hero to the anchor: the gap (so it is taut at once), never so long
-- that the low point under the anchor scrapes the ground at groundY (nil: none found), never under minLen
function SwingMath.rope(
	cfg: any,
	px: number,
	py: number,
	pz: number,
	ax: number,
	ay: number,
	az: number,
	groundY: number?
): number
	local m = cfg.mobility.swing
	local len = len3(ax - px, ay - py, az - pz) * m.taut
	if groundY then
		len = math.min(len, ay - groundY - m.clearance)
	end
	return math.max(m.minLen, len)
end

-- One pendulum step. (px..pz, vx..vz): the hero; (ax..az): the anchor; len: the rope now; target: the
-- length it reels toward (only ever shorter); (sx, sz): the stick, flat in world space (length up to 1).
-- Returns the new position, velocity and rope length.
function SwingMath.step(
	cfg: any,
	px: number,
	py: number,
	pz: number,
	vx: number,
	vy: number,
	vz: number,
	ax: number,
	ay: number,
	az: number,
	len: number,
	target: number,
	sx: number,
	sz: number,
	dt: number
): (number, number, number, number, number, number, number)
	local m = cfg.mobility.swing
	-- was the line slack coming in (then a catch this step keeps the fall's speed along the swing)
	local d0 = len3(px - ax, py - ay, pz - az)
	local wasSlack = d0 < len - m.catchSlack
	if target < len then
		len = math.max(target, len - m.reel * dt)
	end
	vy -= m.gravity * dt
	-- the stick: its part along the flat travel pumps the swing, the rest steers sideways
	local fl = len2(vx, vz)
	if fl > 1 then
		local ux, uz = vx / fl, vz / fl
		local fwd = sx * ux + sz * uz
		local sideX, sideZ = sx - ux * fwd, sz - uz * fwd
		local pump = math.max(0, fwd) * m.pump
		vx += (ux * pump + sideX * m.steer) * dt
		vz += (uz * pump + sideZ * m.steer) * dt
	else
		vx += sx * m.pump * dt
		vz += sz * m.pump * dt
	end
	local nx, ny, nz = px + vx * dt, py + vy * dt, pz + vz * dt
	local dx, dy, dz = nx - ax, ny - ay, nz - az
	local d = len3(dx, dy, dz)
	if d > len and d > 1e-4 then
		-- the rope only pulls: back onto its sphere, the outward speed taken off
		local ux, uy, uz = dx / d, dy / d, dz / d
		nx, ny, nz = ax + ux * len, ay + uy * len, az + uz * len
		local out = vx * ux + vy * uy + vz * uz
		if out > 0 then
			vx, vy, vz = vx - ux * out, vy - uy * out, vz - uz * out
			if wasSlack then
				-- the catch: most of the fall goes on along the swing (momentum kept), never back up the rope
				local tl = len3(vx, vy, vz)
				if tl > 1e-3 then
					local k = out * m.catchKeep / tl
					vx, vy, vz = vx + vx * k, vy + vy * k, vz + vz * k
				end
			end
		end
	end
	local sp = len3(vx, vy, vz)
	if sp > m.maxSpeed then
		local k = m.maxSpeed / sp
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	return nx, ny, nz, vx, vy, vz, len
end

-- Where on the arc the hero is: -1 high behind the bottom (coming down), 0 at the bottom, +1 level with the
-- anchor ahead (going up). rising: vy > 0
function SwingMath.phase(
	px: number,
	py: number,
	pz: number,
	ax: number,
	ay: number,
	az: number,
	vy: number
): number
	local dx, dy, dz = px - ax, py - ay, pz - az
	local d = len3(dx, dy, dz)
	if d < 1e-4 then
		return 0
	end
	local theta = math.acos(math.clamp(-dy / d, -1, 1)) -- 0 straight down, pi/2 level with the anchor
	local p = math.clamp(theta / (math.pi / 2), 0, 1)
	return if vy > 0 then p else -p
end

-- Whether the swing ends on its own: swung up near the anchor's height
function SwingMath.atTop(cfg: any, py: number, ay: number, vy: number): boolean
	return vy > 0 and py > ay - cfg.mobility.swing.topGap
end

-- Letting go: the swing's speed kept, a push along the flat travel and a lift; on the rising half (phase in
-- release.sweet) the bigger boost and lift. Never more than release.cap in all. Returns the velocity and
-- whether it was a sweet release (the bigger whoosh).
function SwingMath.release(
	cfg: any,
	vx: number,
	vy: number,
	vz: number,
	phase: number
): (number, number, number, boolean)
	local r = cfg.mobility.swing.release
	local sweet = phase >= r.sweet[1] and phase <= r.sweet[2]
	local boost = if sweet then r.boost else r.early
	local up = if sweet then r.up else r.earlyUp
	vx, vy, vz = vx * boost, math.max(vy * boost, 0) + up + math.min(vy, 0) * 0.5, vz * boost
	local fl = len2(vx, vz)
	if fl > 1e-3 then
		vx += vx / fl * r.forward
		vz += vz / fl * r.forward
	end
	local total = len3(vx, vy, vz)
	if total > r.cap then
		local k = r.cap / total
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	return vx, vy, vz, sweet
end

-- A zip from (fx..fz) to (tx..tz): the arc's time and height (MoveController.arcTo), never faster than `zip`
-- at any point of the arc (its start is the fastest: the straight part plus the rise)
function SwingMath.zipPlan(
	cfg: any,
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number
): (number, number)
	local m = cfg.mobility.swing
	local dx, dy, dz = tx - fx, ty - fy, tz - fz
	local d = len3(dx, dy, dz)
	local h = math.min(m.zipArc.most, d * m.zipArc.share)
	-- the arc's start velocity is (d + up * 4h) / time: size the time so that stays at zip * zipArc.pace
	local peak = len3(dx, dy + 4 * h, dz)
	return math.max(m.zipArc.minTime, peak / (m.zip * m.zipArc.pace)), h
end

-- The pop at a zip's end: on along the zip's flat way and up (the point launch), inside the cap
function SwingMath.zipPop(cfg: any, dx: number, dz: number): (number, number, number)
	local p = cfg.mobility.swing.zipPop
	local l = len2(dx, dz)
	if l < 1e-3 then
		return 0, p.up, 0
	end
	return dx / l * p.forward, p.up, dz / l * p.forward
end

-- A Cast over axis-aligned boxes { x, z, sx, sz, base, top } (the game's buildings: WorldMap.buildings) and the
-- ground at groundY, for the tests and the preview (slab test). Returns the nearest hit.
function SwingMath.boxCast(boxes: { any }, groundY: number?): Cast
	return function(ox, oy, oz, dx, dy, dz)
		local bestT, bnx, bny, bnz = math.huge, 0, 0, 0
		if groundY and dy < 0 then
			local t = (groundY - oy) / dy
			if t >= 0 and t <= 1 then
				bestT, bnx, bny, bnz = t, 0, 1, 0
			end
		end
		for _, b in boxes do
			local lo = { b.x - b.sx / 2, b.base, b.z - b.sz / 2 }
			local hi = { b.x + b.sx / 2, b.top, b.z + b.sz / 2 }
			local o = { ox, oy, oz }
			local v = { dx, dy, dz }
			local t0, t1, axis, sign = 0, 1, 0, 0
			local ok = true
			for i = 1, 3 do
				if math.abs(v[i]) < 1e-9 then
					if o[i] < lo[i] or o[i] > hi[i] then
						ok = false
						break
					end
				else
					local ta, tb = (lo[i] - o[i]) / v[i], (hi[i] - o[i]) / v[i]
					local s = -1
					if ta > tb then
						ta, tb = tb, ta
						s = 1
					end
					if ta > t0 then
						t0, axis, sign = ta, i, s
					end
					t1 = math.min(t1, tb)
					if t0 > t1 then
						ok = false
						break
					end
				end
			end
			if ok and axis > 0 and t0 < bestT then
				bestT = t0
				bnx = if axis == 1 then sign else 0
				bny = if axis == 2 then sign else 0
				bnz = if axis == 3 then sign else 0
			end
		end
		if bestT == math.huge then
			return nil, 0, 0, 0, 0, 0
		end
		return ox + dx * bestT, oy + dy * bestT, oz + dz * bestT, bnx, bny, bnz
	end
end

SwingMath.len3 = len3

return SwingMath
