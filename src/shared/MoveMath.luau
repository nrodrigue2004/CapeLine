--!strict
-- MoveMath: the movement kit as pure maths (spec: Movement kit). The client runs it every frame to move its
-- own hero (network ownership), and the server uses the same numbers for its speed caps, so feel and
-- checks never drift apart. Vectors are plain numbers (x, y, z) so Lune can test it.

local MoveMath = {}

local function len3(x: number, y: number, z: number): number
	return math.sqrt(x * x + y * y + z * z)
end
local function len2(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

-- Move `current` toward `target` by at most `step` (scalar)
local function approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end
MoveMath.approach = approach

-- Rotate the 2D vector (ax, az) toward (bx, bz) by at most maxRad. Keeps a's length.
function MoveMath.turnToward(ax: number, az: number, bx: number, bz: number, maxRad: number): (number, number)
	local la, lb = len2(ax, az), len2(bx, bz)
	if la < 1e-6 or lb < 1e-6 then
		return ax, az
	end
	local angA = math.atan2(az, ax)
	local angB = math.atan2(bz, bx)
	local diff = (angB - angA + math.pi) % (2 * math.pi) - math.pi
	local turn = math.clamp(diff, -maxRad, maxRad)
	local ang = angA + turn
	return math.cos(ang) * la, math.sin(ang) * la
end

---------------------------------------------------------------------------
-- Leap: a 0.25 s charge, then a ballistic arc under airGravity
---------------------------------------------------------------------------

-- charge01: 0 to 1 of the charge time held. dirX/dirZ: wanted direction (0, 0 = straight up).
function MoveMath.leapLaunch(cfg: any, dirX: number, dirZ: number, charge01: number): (number, number, number)
	local leap = cfg.leap
	local g = cfg.airGravity
	local scale = math.clamp(charge01, leap.minCharge, 1)
	local h = leap.apex * scale
	local vy = math.sqrt(2 * g * h)
	local airTime = 2 * vy / g
	local horizontal = leap.range * scale / airTime
	local l = len2(dirX, dirZ)
	if l < 1e-3 then
		return 0, vy, 0
	end
	return dirX / l * horizontal, vy, dirZ / l * horizontal
end

-- Peak launch speed of a full leap (the server cap for leaping heroes)
function MoveMath.leapSpeed(cfg: any): number
	local vx, vy, vz = MoveMath.leapLaunch(cfg, 1, 0, 1)
	return len3(vx, vy, vz)
end

function MoveMath.airStep(cfg: any, vx: number, vy: number, vz: number, dt: number): (number, number, number)
	return vx, math.max(-cfg.fall.terminal, vy - cfg.airGravity * dt), vz
end

---------------------------------------------------------------------------
-- Glide: hold after the apex; fall 12 studs/s and drift forward at 50
---------------------------------------------------------------------------

function MoveMath.glideStep(
	cfg: any,
	vx: number,
	vy: number,
	vz: number,
	wishX: number,
	wishZ: number,
	dt: number
): (number, number, number)
	local gl = cfg.glide
	local blend = 1 - math.exp(-gl.blend * dt)
	-- heading: current horizontal direction turned toward the stick
	local hx, hz = vx, vz
	if len2(hx, hz) < 1 then
		hx, hz = wishX, wishZ
	end
	if len2(wishX, wishZ) > 0.1 and len2(hx, hz) > 1e-3 then
		hx, hz = MoveMath.turnToward(hx, hz, wishX, wishZ, math.rad(gl.turnRate) * dt)
	end
	local hl = len2(hx, hz)
	local speed = len2(vx, vz)
	speed = speed + (gl.forward - speed) * blend
	if hl > 1e-3 then
		vx, vz = hx / hl * speed, hz / hl * speed
	end
	vy = vy + (-gl.fall - vy) * blend
	local total = len3(vx, vy, vz)
	if total > gl.cap then
		local k = gl.cap / total
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	return vx, vy, vz
end

---------------------------------------------------------------------------
-- Flight: cruise 60, boost 110 (stamina), up 40, down 55, turn 120 degrees/s, auto-level
---------------------------------------------------------------------------

export type FlightInput = {
	wishX: number, -- world direction from the stick and camera, length 0 to 1, may point up or down
	wishY: number,
	wishZ: number,
	vertical: number, -- explicit up (+1) or down (-1) buttons
	boost: boolean,
}

-- Returns the new velocity and whether boost is actually on (stamina allowing).
function MoveMath.flightStep(
	cfg: any,
	vx: number,
	vy: number,
	vz: number,
	y: number,
	stamina: number,
	input: FlightInput,
	dt: number
): (number, number, number, boolean)
	local fl = cfg.flight
	local wishLen = len3(input.wishX, input.wishY, input.wishZ)
	local boosting = input.boost and stamina > 0 and wishLen > 0.1
	local topSpeed = if boosting then fl.boost else fl.cruise
	local accel = if boosting then fl.boostAccel else fl.accel

	-- target velocity
	local tx, ty, tz = 0, 0, 0
	if wishLen > 1e-3 then
		local k = math.min(1, wishLen) / wishLen * topSpeed
		tx, ty, tz = input.wishX * k, input.wishY * k, input.wishZ * k
	end
	ty += input.vertical * (if input.vertical > 0 then fl.up else fl.down)
	ty = math.clamp(ty, -fl.down, if boosting then fl.up * 1.5 else fl.up)

	-- horizontal: turn rate limited at speed, then speed up or slow down along the new heading
	local hSpeed = len2(vx, vz)
	local tSpeed = len2(tx, tz)
	if hSpeed > fl.freeTurnBelow and tSpeed > 1e-3 then
		vx, vz = MoveMath.turnToward(vx, vz, tx, tz, math.rad(fl.turnRate) * dt)
		local rate = if tSpeed > hSpeed then accel else fl.decel
		local newSpeed = approach(hSpeed, tSpeed, rate * dt)
		local l = len2(vx, vz)
		vx, vz = vx / l * newSpeed, vz / l * newSpeed
	else
		local rate = if tSpeed > 1e-3 then accel else fl.decel
		local dx, dz = tx - vx, tz - vz
		local d = len2(dx, dz)
		local step = rate * dt
		if d <= step then
			vx, vz = tx, tz
		else
			vx, vz = vx + dx / d * step, vz + dz / d * step
		end
	end

	-- vertical: settle toward the target; with no up or down wanted the hero auto-levels into a hover
	if math.abs(ty) < 1e-3 then
		vy = vy * math.exp(-fl.autoLevel * dt)
		if math.abs(vy) < 0.5 then
			vy = 0
		end
	else
		vy = approach(vy, ty, accel * dt)
	end

	-- ceiling: a soft push back down above the cloud layer, hard stop at 600
	local c = cfg.ceiling
	if y > c.soft then
		local over = math.clamp((y - c.soft) / (c.hard - c.soft), 0, 1)
		vy = math.min(vy, -c.push * over + (1 - over) * vy)
		if y >= c.hard then
			vy = math.min(vy, -5)
		end
	end

	-- never above boost speed in total
	local total = len3(vx, vy, vz)
	if total > fl.boost then
		local k = fl.boost / total
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	return vx, vy, vz, boosting
end

---------------------------------------------------------------------------
-- Stamina: 100. Boost drains 14/s; regen 15/s on the ground and 8/s gliding or cruising
---------------------------------------------------------------------------

function MoveMath.staminaStep(
	cfg: any,
	stamina: number,
	grounded: boolean,
	boosting: boolean,
	dt: number
): number
	local s = cfg.stamina
	if boosting then
		return math.max(0, stamina - s.boostDrain * dt)
	end
	local regen = if grounded then s.regenGround else s.regenAir
	return math.min(s.max, stamina + regen * dt)
end

---------------------------------------------------------------------------
-- Server cap: the fastest legal speed for a hero with these styles unlocked
---------------------------------------------------------------------------

function MoveMath.speedCap(cfg: any, styles: { [string]: boolean }, boosting: boolean): number
	local cap = math.max(cfg.caps.run, cfg.caps.glide, MoveMath.leapSpeed(cfg))
	if styles.flight then
		cap = math.max(cap, if boosting then cfg.caps.flight else cfg.caps.cruise)
	end
	for style, on in styles do
		local m = cfg.mobility[style]
		if on and m then
			if m.cap then
				cap = math.max(cap, m.cap)
			end
			if style == "leap" then
				cap = math.max(cap, MoveMath.superLeapSpeed(cfg))
			end
			cap = math.max(cap, m.swim or 0)
		end
	end
	return cap
end

-- The Leaping mobility's full leap (bigger than everyone's)
function MoveMath.superLeapLaunch(
	cfg: any,
	dirX: number,
	dirZ: number,
	charge01: number
): (number, number, number)
	local m = cfg.mobility.leap
	return MoveMath.leapLaunch({
		leap = { apex = m.apex, range = m.range, minCharge = cfg.leap.minCharge },
		airGravity = cfg.airGravity,
	}, dirX, dirZ, charge01)
end

function MoveMath.superLeapSpeed(cfg: any): number
	local vx, vy, vz = MoveMath.superLeapLaunch(cfg, 1, 0, 1)
	return len3(vx, vy, vz)
end

-- Super-speed: the sprint speed after dt of holding Boost (accelerates to the top speed)
function MoveMath.sprintStep(cfg: any, speed: number, holding: boolean, dt: number): number
	local m = cfg.mobility.speed
	if holding then
		return math.min(m.sprint, math.max(speed, cfg.run.speed) + m.accel * dt)
	end
	return math.max(cfg.run.speed, speed - m.accel * 1.5 * dt)
end

-- Swing: one step of a pendulum on a rope from (ax, ay, az) of length len. Gravity pulls, the rope keeps the
-- hero on the sphere (the outward part of the velocity is removed), `push` adds speed along the swing, the
-- speed is capped. Returns the new position and velocity.
function MoveMath.swingStep(
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
	pushX: number,
	pushZ: number,
	dt: number
): (number, number, number, number, number, number)
	local m = cfg.mobility.swing
	vy -= cfg.airGravity * dt
	vx += pushX * m.pump * dt
	vz += pushZ * m.pump * dt
	-- next position, then pulled back onto the rope's sphere
	local nx, ny, nz = px + vx * dt, py + vy * dt, pz + vz * dt
	local dx, dy, dz = nx - ax, ny - ay, nz - az
	local d = len3(dx, dy, dz)
	if d > len and d > 1e-4 then
		local k = len / d
		nx, ny, nz = ax + dx * k, ay + dy * k, az + dz * k
		-- remove the outward speed
		local ux, uy, uz = dx / d, dy / d, dz / d
		local out = vx * ux + vy * uy + vz * uz
		if out > 0 then
			vx, vy, vz = vx - ux * out, vy - uy * out, vz - uz * out
		end
	end
	local sp = len3(vx, vy, vz)
	if sp > m.maxSpeed then
		local k = m.maxSpeed / sp
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	return nx, ny, nz, vx, vy, vz
end

MoveMath.len3 = len3
MoveMath.len2 = len2

return MoveMath
