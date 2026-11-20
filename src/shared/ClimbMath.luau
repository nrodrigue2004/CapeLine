--!strict
-- ClimbMath: the climbing and agility moves as pure maths (nate's playtest 2026-11-19 20:42Z). The device
-- (MoveController) runs it every frame for its own hero, the tests run the same code through the server's speed
-- check (MoveCheck), and MoveRanks lists its speeds against each pick's cap. Vectors are plain numbers.
-- * smash rule (nate on the card, 20:45Z: "boost (or a fast leap) smashes through buildings"): leapSmash and
--   speedSmash say when a Leaping or Super-speed hero goes straight through a wall (the flight ram) instead of
--   climbing or running up it.
-- * the Hulk climb (Config.Move.mobility.leap.climb): boundUp (a bound's launch), boundStep (one frame of it up
--   the face), vault (over the top onto the roof), kick (off the wall with momentum).
-- * the Acrobat's wall crawl (mobility.acrobat): crawlBasis (the face's own up and right from the camera),
--   crawlVel (one frame's velocity over the face, held on at crawlGap), crawlKind (wall, ceiling or floor).
-- * flips that dodge (mobility.acrobat.flip): flipVel (the flip's burst) and flipOk (the cooldown, on the device
--   and on the server's own clock).
-- * sprint (Config.Move.sprint): everyone's run on Boost.

local ClimbMath = {}

local function len3(x: number, y: number, z: number): number
	return math.sqrt(x * x + y * y + z * z)
end
local function len2(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end
ClimbMath.len3 = len3

---------------------------------------------------------------------------
-- The smash rule
---------------------------------------------------------------------------

-- Does a Leaping hero moving (vx, vz) flat go through a wall with flat normal (nx, nz)? Only when it moves into
-- the face at smash.into or more (a charged leap); slower, it grabs and climbs.
function ClimbMath.leapSmash(cfg: any, vx: number, vz: number, nx: number, nz: number): boolean
	local nl = len2(nx, nz)
	if nl < 1e-3 then
		return false
	end
	local into = -(vx * nx + vz * nz) / nl
	return into >= cfg.mobility.leap.smash.into
end

-- Does a Super-speed hero smash through? Holding Boost and running at mobility.speed.smash or more
function ClimbMath.speedSmash(cfg: any, boostHeld: boolean, speed: number): boolean
	return boostHeld and speed >= cfg.mobility.speed.smash
end

---------------------------------------------------------------------------
-- Leap: the Hulk climb
---------------------------------------------------------------------------

-- A bound's upward launch speed (it rises climb.bound studs under climb.gravity)
function ClimbMath.boundUp(cfg: any): number
	local c = cfg.mobility.leap.climb
	return math.sqrt(2 * c.gravity * c.bound)
end

-- One frame of a bound: (vy) rising under the climb's gravity, the hands pressed into the face (nx, nz: the
-- wall's flat normal, unit), the stick's sideways share (side: -1..1 along the face's right) drifting it along.
-- Returns the velocity and whether the bound has topped out (time to grab again).
function ClimbMath.boundStep(
	cfg: any,
	vy: number,
	nx: number,
	nz: number,
	side: number,
	dt: number
): (number, number, number, boolean)
	local c = cfg.mobility.leap.climb
	local ny = vy - c.gravity * dt
	local rx, rz = -nz, nx -- the face's right (normal turned a quarter)
	local s = math.clamp(side, -1, 1) * c.side
	return -nx * c.press + rx * s, ny, -nz * c.press + rz * s, ny <= 0
end

-- Over the top: onto the roof (into the wall's face, up)
function ClimbMath.vault(cfg: any, nx: number, nz: number): (number, number, number)
	local v = cfg.mobility.leap.climb.vault
	return -nx * v.forward, v.up, -nz * v.forward
end

-- Off the wall with momentum: out along the normal blended toward the stick's away share, and up
function ClimbMath.kick(
	cfg: any,
	nx: number,
	nz: number,
	stickX: number,
	stickZ: number
): (number, number, number)
	local k = cfg.mobility.leap.climb.kick
	local dx, dz = nx, nz
	local sl = len2(stickX, stickZ)
	if sl > 0.3 and (stickX * nx + stickZ * nz) / sl > 0 then
		dx, dz = nx + stickX / sl, nz + stickZ / sl
	end
	local dl = len2(dx, dz)
	if dl < 1e-3 then
		dx, dz, dl = nx, nz, math.max(1e-3, len2(nx, nz))
	end
	return dx / dl * k.out, k.up, dz / dl * k.out
end

-- Does the stick pull away from the wall (a kick, not a bound)?
function ClimbMath.pullsAway(stickX: number, stickZ: number, nx: number, nz: number): boolean
	local sl = len2(stickX, stickZ)
	return sl > 0.3 and (stickX * nx + stickZ * nz) / sl > 0.5
end

---------------------------------------------------------------------------
-- Acrobat: the wall crawl
---------------------------------------------------------------------------

-- What a surface with normal (nx, ny, nz) is to a crawler: "floor" (stand up on it), "ceiling" or "wall"
function ClimbMath.crawlKind(ny: number): string
	if ny > 0.7 then
		return "floor"
	elseif ny < -0.7 then
		return "ceiling"
	end
	return "wall"
end

local function project(ax: number, ay: number, az: number, nx: number, ny: number, nz: number)
	local d = ax * nx + ay * ny + az * nz
	return ax - nx * d, ay - ny * d, az - nz * d
end

-- The face's own forward (the stick's up) and right, unit, on the plane with normal n: on a wall forward is up
-- the face; on a ceiling (or anything flatter) it is the camera's look laid on the face. Right follows the
-- camera's right laid on the face, else forward x n.
function ClimbMath.crawlBasis(
	nx: number,
	ny: number,
	nz: number,
	lookX: number,
	lookY: number,
	lookZ: number,
	rightX: number,
	rightY: number,
	rightZ: number
): (number, number, number, number, number, number)
	local fx, fy, fz
	if math.abs(ny) < 0.7 then
		fx, fy, fz = project(0, 1, 0, nx, ny, nz)
	else
		fx, fy, fz = project(lookX, lookY, lookZ, nx, ny, nz)
		if len3(fx, fy, fz) < 0.2 then
			fx, fy, fz = project(0, 0, -1, nx, ny, nz)
		end
	end
	local fl = len3(fx, fy, fz)
	fx, fy, fz = fx / fl, fy / fl, fz / fl
	-- right: forward x normal (consistent on any face), turned to agree with the camera's right
	local rx, ry, rz = fy * nz - fz * ny, fz * nx - fx * nz, fx * ny - fy * nx
	local rl = len3(rx, ry, rz)
	if rl < 1e-3 then
		rx, ry, rz = project(rightX, rightY, rightZ, nx, ny, nz)
		rl = math.max(1e-3, len3(rx, ry, rz))
	end
	rx, ry, rz = rx / rl, ry / rl, rz / rl
	if rx * rightX + ry * rightY + rz * rightZ < 0 then
		rx, ry, rz = -rx, -ry, -rz
	end
	return fx, fy, fz, rx, ry, rz
end

-- One frame's crawl velocity: the stick (mvX right, mvZ back, Roblox's move vector) over the face at the crawl
-- speed (the scurry with burst), plus the hold that keeps the body crawlGap off the face (dist: the face's
-- distance now, nil when unknown). Returns the velocity.
function ClimbMath.crawlVel(
	cfg: any,
	nx: number,
	ny: number,
	nz: number,
	fx: number,
	fy: number,
	fz: number,
	rx: number,
	ry: number,
	rz: number,
	mvX: number,
	mvZ: number,
	burst: boolean,
	dist: number?
): (number, number, number)
	local a = cfg.mobility.acrobat
	local speed = if burst then a.crawlBurst else a.climb
	local f, r = -mvZ, mvX
	local m = math.sqrt(f * f + r * r)
	if m > 1 then
		f, r = f / m, r / m
	end
	local vx = (fx * f + rx * r) * speed
	local vy = (fy * f + ry * r) * speed
	local vz = (fz * f + rz * r) * speed
	-- hold on at the gap: pulled in when too far, pushed out when too near (never faster than 12)
	local hold = if dist then math.clamp((a.crawlGap - dist) * 10, -12, 12) else -2
	return vx + nx * hold, vy + ny * hold, vz + nz * hold
end

-- The jump off a crawl: out along the normal, the stick's way (flat, camera-relative) and up on a wall
function ClimbMath.crawlJump(
	cfg: any,
	nx: number,
	ny: number,
	nz: number,
	wishX: number,
	wishZ: number
): (number, number, number)
	local a = cfg.mobility.acrobat
	local up = if ny < -0.7 then 0 else a.jump * 0.6
	local vx = nx * a.jumpForward * 0.8 + wishX * a.jumpForward
	local vy = ny * a.jumpForward * 0.8 + up
	local vz = nz * a.jumpForward * 0.8 + wishZ * a.jumpForward
	local total = len3(vx, vy, vz)
	if total > a.cap then
		local k = a.cap / total
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	return vx, vy, vz
end

---------------------------------------------------------------------------
-- Acrobat: flips that dodge
---------------------------------------------------------------------------

-- The flip's burst along the flat stick (dirX, dirZ), or straight back along (backX, backZ) when the stick is
-- still; up: a hop (on the ground or in the air)
function ClimbMath.flipVel(
	cfg: any,
	dirX: number,
	dirZ: number,
	backX: number,
	backZ: number
): (number, number, number)
	local f = cfg.mobility.acrobat.flip
	local dx, dz = dirX, dirZ
	if len2(dx, dz) < 0.3 then
		dx, dz = backX, backZ
	end
	local l = len2(dx, dz)
	if l < 1e-3 then
		return 0, f.up, 0
	end
	return dx / l * f.speed, f.up, dz / l * f.speed
end

-- May a flip start now (last: when the last one did)? Returns ok and when its dodge window ends. slack: the
-- server's share of the cooldown (lag can bring two flips closer)
function ClimbMath.flipOk(cfg: any, last: number, now: number, slack: number?): (boolean, number)
	local f = cfg.mobility.acrobat.flip
	if now - last < f.cooldown * (slack or 1) then
		return false, 0
	end
	return true, now + f.iframes
end

---------------------------------------------------------------------------
-- Everyone's sprint
---------------------------------------------------------------------------

-- Does this hero sprint now? Boost held, or on touch the stick pushed to its edge (stick: its length)
function ClimbMath.sprinting(cfg: any, boostHeld: boolean, touch: boolean, stick: number): boolean
	return boostHeld or (touch and stick >= cfg.sprint.edge)
end

-- The run speed after dt: eased toward the sprint when sprinting, back to the run when not
function ClimbMath.sprintStep(cfg: any, speed: number, on: boolean, dt: number): number
	local target = if on then cfg.sprint.speed else cfg.run.speed
	local k = 1 - math.exp(-cfg.sprint.ease * dt)
	local s = speed + (target - speed) * k
	if math.abs(s - target) < 0.05 then
		s = target
	end
	return s
end

return ClimbMath
