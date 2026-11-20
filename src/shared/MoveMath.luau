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
	dt: number,
	omni: boolean?
): (number, number, number)
	local gl = cfg.glide
	local blend = 1 - math.exp(-gl.blend * dt)
	-- omnidirectional (cfg.omni and `omni`): the drift eases straight toward the stick's direction (strafe and
	-- drift back without turning round); the fall is the same
	local om = cfg.omni
	if omni and om and len2(wishX, wishZ) > 0.1 then
		local wl = len2(wishX, wishZ)
		local tx, tz = wishX / wl * gl.forward, wishZ / wl * gl.forward
		local dx, dz = tx - vx, tz - vz
		local d = len2(dx, dz)
		local step = om.glideAccel * dt
		if d <= step then
			vx, vz = tx, tz
		else
			vx, vz = vx + dx / d * step, vz + dz / d * step
		end
		vy = vy + (-gl.fall - vy) * blend
		local total = len3(vx, vy, vz)
		if total > gl.cap then
			local k = gl.cap / total
			vx, vy, vz = vx * k, vy * k, vz * k
		end
		return vx, vy, vz
	end
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
	omni: boolean?, -- omnidirectional flight (Config.Move.omni)
	forward: number?, -- the stick's direction dotted with the camera's look (1 = straight ahead)
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

	-- horizontal: turn rate limited at speed, then speed up or slow down along the new heading. Omnidirectional
	-- (cfg.omni with input.omni): the velocity eases straight to the stick's (strafe, backpedal) unless this is a
	-- boost along the camera's look, which keeps the swooping turn
	local hSpeed = len2(vx, vz)
	local tSpeed = len2(tx, tz)
	local om = cfg.omni
	local swoop = boosting and (input.forward or 0) >= (if om then om.swoop else 0)
	if input.omni and om and not swoop then
		local dx, dz = tx - vx, tz - vz
		local d = len2(dx, dz)
		local rate = if tSpeed > 1e-3 then om.flightAccel else math.max(fl.decel, om.flightAccel)
		local step = rate * dt
		if d <= step then
			vx, vz = tx, tz
		else
			vx, vz = vx + dx / d * step, vz + dz / d * step
		end
	elseif hSpeed > fl.freeTurnBelow and tSpeed > 1e-3 then
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

	-- ceiling: a soft push back down above the cloud layer, hard stop at the top (never in the pockets far above)
	local c = cfg.ceiling
	if y > c.soft and MoveMath.ceilingOn(cfg, y) then
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
-- Omnidirectional movement (nate's playtest 2026-11-19; Config.Move.omni)
---------------------------------------------------------------------------

-- The stick's world directions from the camera: flat (for running, leaping, gliding) and full 3D along the
-- camera's pitch (flight, swimming). mvX right, mvZ back (Roblox's move vector: forward is -Z); look is the
-- camera's look, right its right vector. Each at most length 1.
function MoveMath.omniWish(
	mvX: number,
	mvZ: number,
	lookX: number,
	lookY: number,
	lookZ: number,
	rightX: number,
	rightZ: number
): (number, number, number, number, number)
	local fx, fz = lookX, lookZ
	local fl = len2(fx, fz)
	if fl > 1e-3 then
		fx, fz = fx / fl, fz / fl
	else
		fx, fz = 0, -1
	end
	local rx, rz = rightX, rightZ
	local rl = len2(rx, rz)
	if rl > 1e-3 then
		rx, rz = rx / rl, rz / rl
	else
		rx, rz = 1, 0
	end
	local ax, az = rx * mvX + fx * -mvZ, rz * mvX + fz * -mvZ
	local a = len2(ax, az)
	if a > 1 then
		ax, az = ax / a, az / a
	end
	local bx, by, bz = rx * mvX + lookX * -mvZ, lookY * -mvZ, rz * mvX + lookZ * -mvZ
	local b = len3(bx, by, bz)
	if b > 1 then
		bx, by, bz = bx / b, by / b, bz / b
	end
	return ax, az, bx, by, bz
end

-- Where an omnidirectional flier faces (a flat direction): the lock target, else the camera's look while it
-- hovers, strafes or backpedals, and its travel once it flies forward fast (faceMoveAt of cruise)
function MoveMath.omniFace(
	cfg: any,
	camX: number,
	camZ: number,
	vx: number,
	vz: number,
	lockX: number?,
	lockZ: number?
): (number, number)
	if lockX and lockZ and len2(lockX, lockZ) > 1e-3 then
		local l = len2(lockX, lockZ)
		return lockX / l, lockZ / l
	end
	local cl = len2(camX, camZ)
	local cx, cz = if cl > 1e-3 then camX / cl else 0, if cl > 1e-3 then camZ / cl else -1
	local fwd = vx * cx + vz * cz
	local speed = len2(vx, vz)
	if speed > 1e-3 and fwd >= cfg.flight.cruise * cfg.omni.faceMoveAt and fwd / speed > 0.7 then
		return vx / speed, vz / speed
	end
	return cx, cz
end

-- The body's lean into its move, relative to where it faces (degrees): pitch forward (negative) when moving
-- ahead, back when backpedalling, roll into a strafe; full at cruise speed
function MoveMath.omniLean(cfg: any, faceX: number, faceZ: number, vx: number, vz: number): (number, number)
	local L = cfg.omni.lean
	local cruise = cfg.flight.cruise
	local fwd = (vx * faceX + vz * faceZ) / cruise
	local side = (vx * -faceZ + vz * faceX) / cruise
	fwd, side = math.clamp(fwd, -1, 1), math.clamp(side, -1, 1)
	local pitch = if fwd >= 0 then -L.forward * fwd else L.back * -fwd
	return pitch, -L.side * side
end

-- Swimming in 3D: the vertical speed for the stick along the camera's pitch plus Leap (up) and Down, at most
-- swimVertical of the swim speed so the whole move stays inside the server's cap
function MoveMath.swimVertical(cfg: any, wishY: number, vertical: number, speed: number): number
	local k = cfg.omni.swimVertical
	return math.clamp((wishY + vertical) * speed * k, -speed * k, speed * k)
end

-- Does the sky's ceiling act at height y? Only up to hard + band: the mission pockets and the prologue's subway
-- (y 3,000) are far above it, under their own roofs, and a Leap or a flight there must rise freely
function MoveMath.ceilingOn(cfg: any, y: number): boolean
	return y <= cfg.ceiling.hard + (cfg.ceiling.band or 0)
end

---------------------------------------------------------------------------
-- Stamina: Config.Move.stamina.max (200 since nate 2026-11-19, was 100). Boost drains 14/s; regen 40/s on the ground and 20/s gliding or cruising (nate 2026-11-20), after regenDelay s
---------------------------------------------------------------------------

function MoveMath.staminaStep(
	cfg: any,
	stamina: number,
	grounded: boolean,
	boosting: boolean,
	dt: number,
	idle: number?
): number
	local s = cfg.stamina
	if boosting then
		return math.max(0, stamina - s.boostDrain * dt)
	end
	-- idle: seconds since the last drain (boost, wall run, scurry); no regen until regenDelay has passed
	if idle and idle < (s.regenDelay or 0) then
		return stamina
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
			if m.hop then -- Super-speed's running jump: the top speed and the hop's lift together
				cap = math.max(cap, math.sqrt(m.cap * m.cap + m.hop.up * m.hop.up))
			end
			if style == "leap" then
				cap = math.max(cap, MoveMath.superLeapSpeed(cfg))
			end
			cap = math.max(cap, m.swim or 0)
		end
	end
	return cap
end

-- MoveGuard's cap for one sample: the style cap, a ride's own speed, flight during Weightless (zeroG), then
-- the run speed multipliers the client applies (MoveController.runSpeed): the class's moveSpeed and the
-- "speed" buff (Weightless, Feather, the Mystic's +25% on allies, Tide Mirror, Glide Step...). Slows are left
-- out on purpose: a slowed hero is never held to less (rule 6: speed fails only pull back, lean lenient).
function MoveMath.guardCap(
	cfg: any,
	styles: { [string]: boolean },
	boosting: boolean,
	o: { ride: number?, zeroG: boolean?, speedBuff: number?, classSpeed: number? }
): number
	local cap = MoveMath.speedCap(cfg, styles, boosting)
	cap = math.max(cap, o.ride or 0)
	if o.zeroG then
		cap = math.max(cap, cfg.caps.flight)
	end
	return cap * (1 + math.max(0, o.classSpeed or 0)) * (1 + math.max(0, o.speedBuff or 0))
end

-- The Leaping mobility's full leap (bigger than everyone's). runX/runZ (optional): the flat speed the hero
-- runs at; `carry` of it (at most caps.run's worth) is kept on top of the leap, so a running leap never stalls
function MoveMath.superLeapLaunch(
	cfg: any,
	dirX: number,
	dirZ: number,
	charge01: number,
	runX: number?,
	runZ: number?
): (number, number, number)
	local m = cfg.mobility.leap
	local vx, vy, vz = MoveMath.leapLaunch({
		leap = { apex = m.apex, range = m.range, minCharge = m.minCharge or cfg.leap.minCharge },
		airGravity = cfg.airGravity,
	}, dirX, dirZ, charge01)
	local rx, rz = runX or 0, runZ or 0
	local rl = len2(rx, rz)
	if rl > 1e-3 and m.carry then
		local k = math.min(rl, cfg.caps.run) / rl * m.carry
		vx, vz = vx + rx * k, vz + rz * k
	end
	return vx, vy, vz
end

-- The fastest Leaping launch: a full leap with a top-run carry along it (the server cap for Leaping heroes)
function MoveMath.superLeapSpeed(cfg: any): number
	local vx, vy, vz = MoveMath.superLeapLaunch(cfg, 1, 0, 1, cfg.caps.run, 0)
	return len3(vx, vy, vz)
end

-- Air steer: push the flat velocity along the stick at `accel`, never past `max` flat speed (or the speed it
-- already had, if faster: steering never slows a leap, it only turns it)
function MoveMath.airSteer(
	vx: number,
	vz: number,
	wishX: number,
	wishZ: number,
	accel: number,
	max: number,
	dt: number
): (number, number)
	local before = len2(vx, vz)
	local nx, nz = vx + wishX * accel * dt, vz + wishZ * accel * dt
	local after = len2(nx, nz)
	local limit = math.max(before, max)
	if after > limit and after > 1e-6 then
		nx, nz = nx / after * limit, nz / after * limit
	end
	return nx, nz
end

---------------------------------------------------------------------------
-- Wall grabs and wall runs (Acrobat and Super-speed)
---------------------------------------------------------------------------

-- What a hero in the air does on meeting a wall: "wall" (up it: an Acrobat's climb or Super-speed's run up),
-- "wallrun" (along it) or nil (nothing), with the speed. flatSpeed: the hero's flat speed; headOn: the cosine
-- between the way the hero goes and straight into the wall (1 = head-on); stickIn: the stick pushes into it.
function MoveMath.wallGrab(
	cfg: any,
	pick: string,
	flatSpeed: number,
	headOn: number,
	stickIn: boolean
): (string?, number)
	local front = headOn >= math.cos(math.rad(cfg.wall.grabAngle))
	if pick == "acrobat" then
		local a = cfg.mobility.acrobat
		if front and stickIn then
			return "wall", a.climb
		elseif not front and flatSpeed >= a.wallRunMin then
			return "wallrun", math.clamp(flatSpeed, a.wallRun, a.cap)
		end
	elseif pick == "speed" then
		local m = cfg.mobility.speed
		if front and flatSpeed >= m.waterRun then
			return "wall", m.wallRun
		elseif not front and flatSpeed >= m.hop.from then
			return "wallrun", math.min(flatSpeed, m.sprint)
		end
	end
	return nil, 0
end

-- Does a wall run go on? elapsed: seconds on this wall; stick: the flat stick (world); nx, nz: the wall's
-- normal; held: Super-speed's Boost or Leap is down. An Acrobat runs while the stick is pushed (not away from
-- the wall) up to wallRunTime; Super-speed while it holds Boost or Leap (or the stick, not away) and has stamina.
function MoveMath.wallRunKeep(
	cfg: any,
	pick: string,
	elapsed: number,
	stickX: number,
	stickZ: number,
	nx: number,
	nz: number,
	held: boolean,
	stamina: number
): boolean
	if pick == "speed" then
		-- Boost or Leap held, or (the smash rule, 2026-11-19: no Boost needed to wall run) the stick held and not
		-- pulling away from the wall; while stamina lasts
		local sl = len2(stickX, stickZ)
		local stick = sl >= 0.3 and (stickX * nx + stickZ * nz) / sl < 0.5
		return (held or stick) and stamina > 0
	end
	local a = cfg.mobility.acrobat
	if elapsed >= a.wallRunTime or len2(stickX, stickZ) < 0.3 then
		return false
	end
	return (stickX * nx + stickZ * nz) / len2(stickX, stickZ) < 0.5 -- not pulling away from the wall
end

-- Kicking off a wall run: `keep` of the speed along the wall, `out` away from it and `up`, never faster than
-- the mobility's cap in total (the server's cap). alongX/alongZ: the run's flat direction (unit).
function MoveMath.wallKick(
	cfg: any,
	pick: string,
	alongX: number,
	alongZ: number,
	speed: number,
	nx: number,
	nz: number,
	up: number,
	out: number
): (number, number, number)
	local vx, vy, vz = alongX * speed + nx * out, up, alongZ * speed + nz * out
	local cap = (cfg.mobility[pick] and cfg.mobility[pick].cap) or cfg.caps.run
	local total = len3(vx, vy, vz)
	if total > cap then
		local k = cap / total
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	return vx, vy, vz
end

-- Super-speed: the sprint speed after dt of holding Boost (accelerates to the top speed)
-- Super-speed's running jump: the run's own speed (never less than the sprint so far, never over the top
-- speed) along the stick (or straight on), and the hop's lift
function MoveMath.speedHop(
	cfg: any,
	vx: number,
	vz: number,
	wishX: number,
	wishZ: number,
	sprint: number
): (number, number, number)
	local m = cfg.mobility.speed
	local flat = len2(vx, vz)
	local speed = math.min(m.sprint, math.max(flat, sprint))
	local dx, dz = wishX, wishZ
	local wl = len2(dx, dz)
	if wl < 0.3 then
		dx, dz, wl = vx, vz, flat
	end
	if wl < 1e-3 then
		return 0, m.hop.up, 0
	end
	return dx / wl * speed, m.hop.up, dz / wl * speed
end

-- One air step of the running jump's steering: the flat velocity turns toward the stick at hop.turnRate and
-- keeps its speed (no air drag: the hop never loses the run)
function MoveMath.hopSteer(
	cfg: any,
	vx: number,
	vz: number,
	wishX: number,
	wishZ: number,
	dt: number
): (number, number)
	local speed = len2(vx, vz)
	if speed < 1e-3 or len2(wishX, wishZ) < 0.3 then
		return vx, vz
	end
	local cur = math.atan2(vz, vx)
	local want = math.atan2(wishZ, wishX)
	local diff = (want - cur + math.pi) % (2 * math.pi) - math.pi
	local maxTurn = math.rad(cfg.mobility.speed.hop.turnRate) * dt
	local a = cur + math.clamp(diff, -maxTurn, maxTurn)
	return math.cos(a) * speed, math.sin(a) * speed
end

function MoveMath.sprintStep(cfg: any, speed: number, holding: boolean, dt: number): number
	local m = cfg.mobility.speed
	if holding then
		return math.min(m.sprint, math.max(speed, cfg.run.speed) + m.accel * dt)
	end
	return math.max(cfg.run.speed, speed - m.accel * 1.5 * dt)
end

-- Swing: the pendulum, the rope, the anchor search and the release are in Shared.SwingMath (2026-11-19)

MoveMath.len3 = len3
MoveMath.len2 = len2

return MoveMath
