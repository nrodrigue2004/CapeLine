--!strict
-- LockRules: lock-on as pure rules (nate's playtest 2026-11-19: "a player/enemy lock-on ... camera should have
-- dynamic movement"; nate decided both the soft lock and the hard LOCK toggle). Numbers in Config.Combat.lock;
-- LockClient and CameraController use it, Lune checks it. Vectors are plain numbers so Lune runs it.
-- * pick(cands, cam, hero, range, angle): the best target in front: within range of the hero and angle of the
--   camera's look, scored by how central it is first and how near second. Returns its index or nil.
-- * cycle(cands, current, cam, dir, range, maxAngle): the next target to the right (dir 1) or left (-1) of the
--   current one on screen, wrapping round.
-- * keep(K, dist, hiddenFor): does a hard lock hold?
-- * frame(K, hero, target, size, motion): where the locked camera looks (yaw, pitch in radians, clamped), how far
--   back it pulls for a big target, the shoulder offset.
-- * ease(rate, dt): the share of the way to move this frame (frame-rate independent).
-- * marker(M, px, t, hard): the comic target marker as bars and a diamond (LockClient draws them, and
--   art/lock/marker.py renders the same layout for the preview).

local LockRules = {}

export type Cand = { id: number, x: number, y: number, z: number, size: number? }
export type Cam = { x: number, y: number, z: number, lx: number, ly: number, lz: number }
export type P3 = { x: number, y: number, z: number }

local function angleOff(cam: Cam, c: Cand): (number, number)
	local dx, dy, dz = c.x - cam.x, c.y - cam.y, c.z - cam.z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-3 then
		return 0, 0
	end
	local dot = (dx * cam.lx + dy * cam.ly + dz * cam.lz) / d
	return math.deg(math.acos(math.clamp(dot, -1, 1))), d
end

function LockRules.pick(cands: { Cand }, cam: Cam, hero: P3, range: number, angle: number): number?
	local best, bestScore = nil, math.huge
	for i, c in cands do
		local hx, hy, hz = c.x - hero.x, c.y - hero.y, c.z - hero.z
		local hd = math.sqrt(hx * hx + hy * hy + hz * hz)
		local reach = range + (c.size or 0) * 0.5
		if hd <= reach then
			local a = angleOff(cam, c)
			if a <= angle then
				local score = a / angle + 0.5 * hd / reach
				if score < bestScore then
					best, bestScore = i, score
				end
			end
		end
	end
	return best
end

-- The flat screen angle of a candidate round the camera's look (degrees, right positive)
local function yawOf(cam: Cam, c: Cand): number
	local fx, fz = cam.lx, cam.lz
	local fl = math.sqrt(fx * fx + fz * fz)
	if fl < 1e-4 then
		fx, fz, fl = 0, -1, 1
	end
	fx, fz = fx / fl, fz / fl
	local dx, dz = c.x - cam.x, c.z - cam.z
	-- right of the look is (-fz, fx) in Roblox's axes (look -Z, right +X)
	local right = dx * -fz + dz * fx
	local fwd = dx * fx + dz * fz
	return math.deg(math.atan2(right, fwd))
end

function LockRules.cycle(
	cands: { Cand },
	current: number?,
	cam: Cam,
	dir: number,
	hero: P3,
	range: number,
	maxAngle: number
): number?
	local cur: Cand? = nil
	for _, c in cands do
		if c.id == current then
			cur = c
		end
	end
	local base = if cur then yawOf(cam, cur) else 0
	local bestUp, bestUpD = nil, math.huge -- the nearest the way asked
	local wrap, wrapD = nil, -math.huge -- the furthest the other way (the wrap round)
	for i, c in cands do
		if c.id ~= current then
			local hx, hy, hz = c.x - hero.x, c.y - hero.y, c.z - hero.z
			if math.sqrt(hx * hx + hy * hy + hz * hz) <= range + (c.size or 0) * 0.5 then
				local y = yawOf(cam, c)
				if math.abs(y) <= maxAngle then
					local d = (y - base) * dir
					if d > 0 and d < bestUpD then
						bestUp, bestUpD = i, d
					elseif d <= 0 and -d > wrapD then
						wrap, wrapD = i, -d
					end
				end
			end
		end
	end
	return bestUp or wrap
end

function LockRules.keep(K: any, dist: number, hiddenFor: number): boolean
	return dist <= K.hard.keep and hiddenFor <= K.hard.lost
end

export type Frame = { yaw: number, pitch: number, pull: number, shoulder: number, look: P3 }

-- The locked camera's aim: the look point sits between the target and the hero (heroAim), so both stay on
-- screen; a tall target pulls the camera back. Yaw follows Roblox's CFrame.fromOrientation (0 looks along -Z).
function LockRules.frame(K: any, hero: P3, target: P3, size: number?): Frame
	local H = K.hard
	local k = H.heroAim
	local lx = target.x + (hero.x - target.x) * k
	local ly = target.y + (hero.y - target.y) * k
	local lz = target.z + (hero.z - target.z) * k
	local dx, dy, dz = lx - hero.x, ly - hero.y, lz - hero.z
	local flat = math.sqrt(dx * dx + dz * dz)
	local yaw = math.atan2(-dx, -dz)
	local pitch = if flat > 1e-3 or math.abs(dy) > 1e-3 then math.atan2(dy, math.max(flat, 1e-3)) else 0
	pitch = math.clamp(pitch, math.rad(H.pitch[1]), math.rad(H.pitch[2]))
	local over = math.max(0, (size or 0) - H.big)
	return {
		yaw = yaw,
		pitch = pitch,
		pull = math.min(H.pullMax, over * H.pull),
		shoulder = H.shoulder,
		look = { x = lx, y = ly, z = lz },
	}
end

function LockRules.ease(rate: number, dt: number): number
	return 1 - math.exp(-math.max(0, rate) * math.max(0, dt))
end

-- The soft lock's camera ease: how far (radians) to turn the yaw toward a target `off` radians to the side this
-- frame, nothing inside the dead zone or while the player turns the camera themselves
function LockRules.softTurn(K: any, off: number, idle: number, motion: number, dt: number): number
	local S = K.soft
	if idle < S.camIdle or math.abs(off) < math.rad(S.camDead) or motion <= 0 then
		return 0
	end
	local sign = if off > 0 then 1 else -1
	local room = math.abs(off) - math.rad(S.camDead)
	return sign * room * LockRules.ease(S.camTurn * motion, dt)
end

export type Bar = { x: number, y: number, w: number, h: number, rot: number }

-- The comic marker at `px` pixels across, `t` seconds in: four corner brackets (two bars each, an ink copy under
-- each for the outline) turning slowly on a hard lock, breathing in and out, and a diamond over the target on a
-- hard lock. Positions are from the marker's centre in pixels; rot in degrees.
function LockRules.marker(M: any, px: number, t: number, hard: boolean): { bars: { Bar }, diamond: number? }
	local breathe = 1 + M.pulse * math.sin(t * 6)
	local half = px * 0.5 * (if hard then breathe else 1)
	local spin = if hard then (t * M.spin) % 360 else 0
	local len = px * 0.28
	local thick = math.max(3, px * (if hard then 0.07 else 0.045))
	local bars: { Bar } = {}
	local r = math.rad(spin)
	local cr, sr = math.cos(r), math.sin(r)
	local function put(x: number, y: number, w: number, h: number)
		table.insert(bars, { x = x * cr - y * sr, y = x * sr + y * cr, w = w, h = h, rot = spin })
	end
	for _, c in { { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } } do
		local sx, sy = c[1], c[2]
		put(sx * (half - len / 2), sy * half, len + thick, thick) -- along the top or bottom edge
		put(sx * half, sy * (half - len / 2), thick, len + thick) -- down the side
	end
	return { bars = bars, diamond = if hard then px * 0.22 else nil }
end

return LockRules
