--!strict
-- DriveMath (2026-11-19, gap-vehicles: nate called the vehicles "trash"; the wheels did not turn and the escorts
-- glided like a box): the maths that makes a vehicle look driven. Pure, so Lune tests it; the server moves the
-- escorts with it (SideQuestService, ContractService, IncidentService's tug) and every device draws the wheels and
-- the body's sway with it (Fx.VehicleRig).
-- * spin: a wheel's roll angle from the distance it travelled (radius from the mesh, Config.VehicleArt `wheel`).
-- * steer: the front wheels' angle from the heading change (a bicycle model: atan(wheelbase * yaw rate / speed)).
-- * spring / sway: the body's pitch on accel and brake, its roll in turns and a little heave, as damped springs.
-- * pose: where a vehicle stands at a distance along its path, the corners rounded so it turns instead of
--   snapping its heading; at is the same distance along the straight path the escort rules have always counted.
-- * corner / speed: the drive's speed: it pulls away from a stop, slows into a corner and brakes when nobody
--   escorts it (Config.Destruction.vehicles.drive).
-- Angles are radians, in Roblox's sense: yaw about up (positive turns left, the nose at -z), pitch positive lifts
-- the nose, roll positive lifts the right (+x) side.

local DriveMath = {}

local TAU = 2 * math.pi

-- The roll angle of a wheel of radius r after rolling dist studs (forward is positive), kept within one turn
function DriveMath.spin(angle: number, dist: number, r: number): number
	if r <= 0 then
		return angle
	end
	return (angle + dist / r) % TAU
end

-- The front wheels' steer angle for a yaw rate (rad/s) at a speed (studs/s) and a wheelbase (studs), held to max.
-- Standing (or nearly) the wheels go straight.
function DriveMath.steer(yawRate: number, speed: number, wheelbase: number, max: number): number
	if math.abs(speed) < 0.5 or wheelbase <= 0 then
		return 0
	end
	local a = math.atan(wheelbase * yawRate / math.abs(speed))
	return math.clamp(a, -max, max)
end

-- The shortest turn from heading a to heading b (radians, -pi..pi)
function DriveMath.turn(a: number, b: number): number
	local d = (b - a) % TAU
	if d > math.pi then
		d -= TAU
	end
	return d
end

-- One damped spring step toward target: (value, velocity). k the stiffness, c the damping; substeps keep a long
-- frame (a phone hitch) from blowing it up.
function DriveMath.spring(
	x: number,
	v: number,
	target: number,
	k: number,
	c: number,
	dt: number
): (number, number)
	local n = math.max(1, math.ceil(dt / (1 / 60)))
	local h = dt / n
	for _ = 1, n do
		v += (k * (target - x) - c * v) * h
		x += v * h
	end
	return x, v
end

export type Sway = { pitch: number, pv: number, roll: number, rv: number, heave: number, hv: number }

function DriveMath.sway(): Sway
	return { pitch = 0, pv = 0, roll = 0, rv = 0, heave = 0, hv = 0 }
end

-- The body's sway for a forward acceleration (studs/s^2) and a sideways one (speed * yaw rate; positive in a left
-- turn): the nose lifts as it pulls away and dips when it brakes, the body leans out of a turn. cfg: pitch and
-- roll (radians per stud/s^2), maxPitch, maxRoll, k and c (the springs). kick adds a sudden bounce (heave studs/s).
function DriveMath.swayStep(
	s: Sway,
	accel: number,
	lateral: number,
	dt: number,
	cfg: any,
	kick: number?
): Sway
	local tp = math.clamp(accel * cfg.pitch, -cfg.maxPitch, cfg.maxPitch)
	local tr = math.clamp(-lateral * cfg.roll, -cfg.maxRoll, cfg.maxRoll)
	s.pitch, s.pv = DriveMath.spring(s.pitch, s.pv, tp, cfg.k, cfg.c, dt)
	s.roll, s.rv = DriveMath.spring(s.roll, s.rv, tr, cfg.k, cfg.c, dt)
	if kick then
		s.hv += kick
	end
	s.heave, s.hv = DriveMath.spring(s.heave, s.hv, 0, cfg.k, cfg.c * 0.8, dt)
	return s
end

-- Is the sway at rest (nothing left to draw)?
function DriveMath.still(s: Sway): boolean
	local e = 1e-3
	return math.abs(s.pitch) < e
		and math.abs(s.roll) < e
		and math.abs(s.heave) < e
		and math.abs(s.pv) < e
		and math.abs(s.rv) < e
		and math.abs(s.hv) < e
end

-- A path point's x, y, z: paths come as Vector3s (contracts, the tug) or { x, y, z } (side quests)
local function xyz(p: any): (number, number, number)
	if type(p) == "table" and p[1] ~= nil then
		return p[1], p[2], p[3]
	end
	return p.X, p.Y, p.Z
end

-- The yaw that points the nose (-z) along (dx, dz)
function DriveMath.yaw(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

-- Where a vehicle stands `at` studs along a path, with each corner rounded over up to `round` studs either side
-- (never more than half a leg): x, y, z and its yaw. Past either end it stays at the end.
function DriveMath.pose(path: { any }, at: number, round: number): (number, number, number, number)
	local n = #path
	if n == 0 then
		return 0, 0, 0, 0
	elseif n == 1 then
		local x, y, z = xyz(path[1])
		return x, y, z, 0
	end
	-- the legs: start, unit direction and length
	local legs = {}
	for i = 1, n - 1 do
		local ax, ay, az = xyz(path[i])
		local bx, by, bz = xyz(path[i + 1])
		local dx, dy, dz = bx - ax, by - ay, bz - az
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		table.insert(legs, { ax = ax, ay = ay, az = az, dx = dx, dy = dy, dz = dz, len = len })
	end
	at = math.max(0, at)
	local i, left = #legs, legs[#legs].len
	local acc = 0
	for k, l in legs do
		if at <= acc + l.len or k == #legs then
			i, left = k, math.min(at - acc, l.len)
			break
		end
		acc += l.len
	end
	local l = legs[i]
	local function point(leg: any, s: number): (number, number, number)
		local f = s / math.max(leg.len, 1e-6)
		return leg.ax + leg.dx * f, leg.ay + leg.dy * f, leg.az + leg.dz * f
	end
	local function flatYaw(leg: any): number
		return DriveMath.yaw(leg.dx, leg.dz)
	end
	-- the corner this point is rounding, if any: at the end of this leg or at its start
	local function rounded(a: any, b: any, s: number): (number, number, number, number)
		-- a quadratic curve from `r` before the corner (on leg a) to `r` after it (on leg b), the corner its control
		local r = math.min(round, a.len / 2, b.len / 2)
		local t = s / (2 * r) -- 0 at the curve's start, 1 at its end
		local p0x, p0y, p0z = point(a, a.len - r)
		local cx, cy, cz = point(b, 0)
		local p2x, p2y, p2z = point(b, r)
		local u = 1 - t
		local x = u * u * p0x + 2 * u * t * cx + t * t * p2x
		local y = u * u * p0y + 2 * u * t * cy + t * t * p2y
		local z = u * u * p0z + 2 * u * t * cz + t * t * p2z
		local tx = 2 * u * (cx - p0x) + 2 * t * (p2x - cx)
		local tz = 2 * u * (cz - p0z) + 2 * t * (p2z - cz)
		return x, y, z, DriveMath.yaw(tx, tz)
	end
	if i < #legs then
		local r = math.min(round, l.len / 2, legs[i + 1].len / 2)
		if r > 0.01 and left > l.len - r then
			return rounded(l, legs[i + 1], left - (l.len - r))
		end
	end
	if i > 1 then
		local r = math.min(round, l.len / 2, legs[i - 1].len / 2)
		if r > 0.01 and left < r then
			return rounded(legs[i - 1], l, r + left)
		end
	end
	local x, y, z = point(l, left)
	return x, y, z, flatYaw(l)
end

-- The share of cruise speed for the corners ahead: each corner within cfg.look studs slows the drive toward
-- cfg.corner (at a right angle or sharper; a gentle bend barely), more the closer it is
function DriveMath.corner(path: { any }, at: number, cfg: any): number
	local f = 1
	local acc = 0
	for i = 2, #path - 1 do
		local ax, _, az = xyz(path[i - 1])
		local bx, _, bz = xyz(path[i])
		local cx, _, cz = xyz(path[i + 1])
		acc += math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local ahead = acc - at
		if ahead > cfg.look then
			break
		end
		if ahead > -cfg.after then
			local turn =
				math.abs(DriveMath.turn(DriveMath.yaw(bx - ax, bz - az), DriveMath.yaw(cx - bx, cz - bz)))
			local sharp = math.clamp(turn / (math.pi / 2), 0, 1)
			local near = if ahead >= 0 then 1 - ahead / cfg.look else 1
			f = math.min(f, 1 - (1 - cfg.corner) * sharp * near)
		end
	end
	return f
end

-- The next speed: toward cruise * share while it may go (pulling away at cfg.accel), down to a stop at cfg.brake
-- when it may not (or when the share drops, a corner)
function DriveMath.speed(v: number, cruise: number, share: number, go: boolean, dt: number, cfg: any): number
	local target = if go then cruise * share else 0
	if v < target then
		return math.min(target, v + cfg.accel * dt)
	end
	return math.max(target, v - cfg.brake * dt)
end

-- One server step of a drive: the new distance along the path and speed (the distance is held to length)
function DriveMath.step(
	at: number,
	v: number,
	cruise: number,
	go: boolean,
	path: { any },
	length: number,
	dt: number,
	cfg: any
): (number, number)
	local share = DriveMath.corner(path, at, cfg)
	v = DriveMath.speed(v, cruise, share, go and at < length, dt, cfg)
	at = math.min(length, at + v * dt)
	if at >= length then
		v = 0
	end
	return at, v
end

return DriveMath
