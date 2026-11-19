-- MoveController: the hero's movement feel (spec: Movement kit; M1 is built and tested first because
-- movement is the core fun). The hero owns its own character (network ownership) and moves it with MoveMath,
-- the same maths the server checks against. Modes:
--   ground  the normal Humanoid run (20 studs/s)
--   charge  a 0.25 s crouch before a Leap
--   air     a Leap arc (or falling) under the floaty airGravity
--   glide   hold Leap after the apex: fall 12 studs/s, drift forward at 50
--   fly     Flight style: cruise 60, Boost 110 on stamina, auto-level hover
--   dash    a short server-approved burst (Dash Strike, Flash Step, Shoulder Charge, the Thunder Drop dive)
--           or an arc to a landing spot (Meteor Leap)
-- Mobility (nate 2026-11-16): every hero has one pick (State.hero.mobility, Config.Move.mobility), which adds:
--   flight   the fly mode above (Fly toggles; level 10: faster boost)
--   speed    hold Boost to sprint up to 100; sprint (or hop) into a wall to run up it (`wall`, drains stamina),
--            hop at a wall glancingly to run along it (`wallrun`), across water (`water`); Leap while running
--            is the running jump (`hopping`). (Its slide is gone: nate's playtest 2026-11-19, "rid of slide".)
--   leap     bigger charged leaps that keep the run's speed, a firmer air steer, Leap near a wall in the air to
--            bounce off it, Down in the air to `pound` (the server's MovePound burst hits around the landing)
--   acrobat  Leap in the air to double jump, walk or jump into a wall to `wall` climb, jump at one glancingly to
--            run along it (`wallrun`, while the stick is held; Leap kicks off and chains), a faster glide
--   swing    Fly in the air fires a line at a building and `swing`s on it (release to let go and fling); Fly on
--            the ground zips to the spot aimed at
-- Travel powers (CombatClient): `ride` for `duration` at a server-allowed speed (air, surf or rail), and
-- `launch` arcs. A Weightless (zeroG) buff lets any hero fly while it lasts. Underwater the Humanoid swims at
-- the mobility's swim speed.
-- In the air modes the Humanoid is set to PlatformStand and a LinearVelocity plus AlignOrientation drive
-- the body; on landing the Humanoid takes over again.
-- M8: PvP crowd control on you (State.status.cc): stuns and roots stop movement and the leap and flight
-- buttons, slows cut speed, and a Downed hero (the Downed attribute) can only crawl. HeroKnock (a PvP
-- knockback, pull or knockup) plays as a short arc the server already allowed.
-- The flying pose is the body tilted along the travel direction; HeroAnimator poses the limbs for every mode
-- (Shared.HeroAnim clips, PLACEHOLDER ANIMATION until real animations).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local MoveMath = require(Shared:WaitForChild("MoveMath"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local InputController = require(script.Parent.InputController)
local State = require(script.Parent.Parent.State)

local M = Config.Move
local player = Players.LocalPlayer

local MoveController = {}
MoveController.mode = "ground"
MoveController.stamina = M.stamina.max
MoveController.boosting = false
MoveController.lineColor = nil :: Color3? -- H8: the worn travel style colours the swing line (TravelStyleFx)
MoveController.velocity = Vector3.zero
MoveController.Leaped = Signal.new() -- (position)
MoveController.Landed = Signal.new() -- (position, fallSpeed)
MoveController.ModeChanged = Signal.new() -- (mode, old)
MoveController.BoostChanged = Signal.new() -- (on)
MoveController.Pounded = Signal.new() -- (position) a Leaping ground pound landed
MoveController.Rammed = Signal.new() -- (contact, wall normal, speed, building id) a fast hero hit a wall (ImpactFx)

local root: BasePart? = nil
local hum: Humanoid? = nil
local lv: LinearVelocity? = nil
local ao: AlignOrientation? = nil

local vel = Vector3.zero
local chargeStart = 0
local lastLeap = -math.huge
local airSince = 0
local dashUntil = 0
local dashReturn = "air"
local lastYaw = 0
local roll = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local arc: { from: Vector3, to: Vector3, start: number, time: number, height: number }? = nil

-- mobility state
local sprint = M.run.speed -- Super-speed's current run speed
local airJumps = 0 -- Acrobat jumps used since leaving the ground
local bounces = 0 -- Leaping wall bounces since leaving the ground
local wallNormal = Vector3.zero -- the wall a wall mode clings to
local wallSpeed = 0
local wallDrain = 0
local wallStart = 0 -- when the hero took the wall it is on
local wallLeft = -math.huge -- when the hero last left a wall (wall.regrab)
local spentWall: Vector3? = nil -- a wall run that ran out: that wall is not grabbed again before a landing or a kick
local hopping = false -- in a Super-speed running jump (keeps the run's speed; holding Leap hops again)
local swingAnchor: Vector3? = nil
local swingLen = 0
local swingLine: Part? = nil
local swingPart: BasePart? = nil -- what the line hangs from (a broken building piece drops the line)
local chargeRun = Vector3.zero -- the flat run speed when a Leaping charge began (carried into the leap)
local ride: { kind: string, speed: number, untilT: number, dir: Vector3 }? = nil
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
waterParams.IgnoreWater = false

local function mobility(): string
	return State.hero.mobility or "flight"
end
local function mob(): any
	return M.mobility[mobility()] or M.mobility.flight
end
local function level(): number
	return State.hero.level or 1
end
-- flight is the Flight pick, or any hero during a Weightless (zeroG) buff
local function canFly(): boolean
	return (State.hero.styles ~= nil and State.hero.styles.flight == true) or State.buff("zeroG") > 0
end
MoveController.canFly = canFly

-- Tuning tables with the mobility's numbers swapped in (Acrobat's glide, Flight's boost)
local ACRO_CFG = table.clone(M)
ACRO_CFG.glide = table.clone(M.glide)
ACRO_CFG.glide.forward = M.mobility.acrobat.glideForward
ACRO_CFG.glide.cap = M.mobility.acrobat.cap
local FLIGHT_UP = table.clone(M)
FLIGHT_UP.flight = table.clone(M.flight)
FLIGHT_UP.flight.boost = M.mobility.flight.up.boost

local function ccLeft(kind: string): boolean
	local c = State.status.cc[kind]
	return c ~= nil and os.clock() < c.untilT
end

-- Downed, stunned or rooted: no moving under your own power (crawling aside), no leap, no flight
local function held(): boolean
	return ccLeft("stun") or ccLeft("root")
end
local function downed(): boolean
	return player:GetAttribute("Downed") == true
end
MoveController.held = held

-- Hero MMO features: named speed scales (block 0.5, charge 0.6, carry 0.8); the slowest one counts
MoveController.scales = {} :: { [string]: number }
local function scaleNow(): number
	local m = 1
	for _, v in MoveController.scales do
		m = math.min(m, v)
	end
	return m
end
MoveController.scaleNow = scaleNow

-- Run speed with Speedster's +10%, the Weightless buff, and PvP slows, stuns and roots
local function runSpeed(): number
	if downed() then
		return Config.Pvp.downed.crawlSpeed
	end
	if held() then
		return 0
	end
	local class = Config.Classes[State.hero.classId]
	local bonus = if class and class.moveSpeed then class.moveSpeed else 0
	local slow = State.status.cc.slow
	local slowMult = if slow and os.clock() < slow.untilT then slow.value else 1
	local base = M.run.speed
	local pick = mobility()
	if pick == "speed" then
		base = sprint -- Super-speed: the sprint (20 walking, up to 100 holding Boost)
	elseif pick == "acrobat" then
		base = M.mobility.acrobat.run
	end
	local speed = base * (1 + bonus) * (1 + State.buff("speed")) * slowMult * scaleNow()
	if hum and hum:GetState() == Enum.HumanoidStateType.Swimming then
		-- underwater: everyone swims, each mobility at its own speed
		speed = math.max(M.swim.base, mob().swim or M.swim.base) * slowMult * scaleNow()
	end
	return speed
end
MoveController.runSpeed = runSpeed

local function setMode(mode: string)
	local old = MoveController.mode
	if mode ~= "air" then
		hopping = false -- a running jump ends in any other move (glide, flight, a dash, a wall, the ground)
	end
	if old ~= mode then
		MoveController.mode = mode
		MoveController.ModeChanged:Fire(mode, old)
	end
end

local function setBoost(on: boolean)
	if MoveController.boosting ~= on then
		MoveController.boosting = on
		Net.send("MoveBoost", on)
		MoveController.BoostChanged:Fire(on)
	end
end

local function grounded(): (boolean, number)
	if not root or not hum then
		return false, 0
	end
	local reach = hum.HipHeight + root.Size.Y / 2 + 0.7
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	if hit then
		return true, hit.Position.Y
	end
	return false, 0
end

local function enterAir(v: Vector3)
	if not hum or not lv or not ao then
		return
	end
	vel = v
	hum.PlatformStand = true
	hum.AutoRotate = false
	lv.VectorVelocity = v
	lv.Enabled = true
	ao.Enabled = true
	airSince = os.clock()
end

local function toGround(fallSpeed: number, keepRun: boolean?)
	if not hum or not lv or not ao or not root then
		return
	end
	lv.Enabled = false
	ao.Enabled = false
	hum.PlatformStand = false
	hum.AutoRotate = true
	hum.WalkSpeed = runSpeed()
	-- stand up straight, keeping the heading
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	-- a running jump lands at full run (the sprint carries on); any other landing sheds most of the speed
	local keep = if keepRun then 1 else 0.3
	root.AssemblyLinearVelocity = Vector3.new(vel.X * keep, 0, vel.Z * keep)
	if keepRun then
		sprint = math.max(sprint, math.min(M.mobility.speed.sprint, Vector3.new(vel.X, 0, vel.Z).Magnitude))
		hum.WalkSpeed = runSpeed()
	end
	hopping = false
	hum:ChangeState(Enum.HumanoidStateType.Landed)
	vel = Vector3.zero
	airJumps, bounces = 0, 0
	spentWall = nil
	ride = nil
	setBoost(false)
	setMode("ground")
	MoveController.Landed:Fire(root.Position, fallSpeed)
end

-- World directions from the stick: flat for running, leaping and gliding, full 3D (camera pitch) for flight
local function wishDirs(): (Vector3, Vector3)
	local cam = Workspace.CurrentCamera.CFrame
	local mv = InputController.moveVector()
	local look = cam.LookVector
	local f = Vector3.new(look.X, 0, look.Z)
	f = if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
	local r = Vector3.new(cam.RightVector.X, 0, cam.RightVector.Z)
	r = if r.Magnitude > 1e-3 then r.Unit else Vector3.new(1, 0, 0)
	local flat = r * mv.X + f * -mv.Z
	local full = r * mv.X + look * -mv.Z
	if flat.Magnitude > 1 then
		flat = flat.Unit
	end
	if full.Magnitude > 1 then
		full = full.Unit
	end
	return flat, full
end

-- How far a Leap's crouch has charged (0 to 1; 0 outside the charge): MoveFx's charge rings
local function chargeTime(): number
	return if mobility() == "leap" then M.mobility.leap.charge else M.leap.charge
end
function MoveController.chargeFraction(): number
	if MoveController.mode ~= "charge" then
		return 0
	end
	return math.clamp((os.clock() - chargeStart) / chargeTime(), 0, 1)
end

function MoveController.leapReady(): number
	local cd = if mobility() == "leap" then M.mobility.leap.cooldown else M.leap.cooldown
	return math.clamp((os.clock() - lastLeap) / cd, 0, 1)
end

-- A guided Leap (the prologue's roof hops, kid-proof: nate's playtest 2026-11-18): when set and it returns a
-- spot, a Leap from the ground is a set arc there (target, time, height) instead of a free jump
MoveController.hopAssist = nil :: (() -> (Vector3?, number, number))?

local function launch(frac: number)
	local assist = MoveController.hopAssist
	if assist and root then
		local to, time, height = assist()
		if to then
			lastLeap = os.clock()
			MoveController.arcTo(to, time, height)
			MoveController.Leaped:Fire(root.Position)
			return
		end
	end
	local flat = wishDirs()
	local vx, vy, vz
	if mobility() == "leap" then
		vx, vy, vz = MoveMath.superLeapLaunch(M, flat.X, flat.Z, frac, chargeRun.X, chargeRun.Z)
	else
		vx, vy, vz = MoveMath.leapLaunch(M, flat.X, flat.Z, frac)
	end
	lastLeap = os.clock()
	enterAir(Vector3.new(vx, vy, vz))
	setMode("air")
	if root then
		MoveController.Leaped:Fire(root.Position)
	end
end

-- Dash Strike: a short burst along `dir`, approved by the server's MoveGuard grant
function MoveController.dash(dir: Vector3, distance: number, time: number)
	if not root or dir.Magnitude < 0.1 then
		return
	end
	local mode = MoveController.mode
	dashReturn = if mode == "fly" then "fly" else "air"
	if mode == "ground" or mode == "charge" then
		enterAir(Vector3.zero)
	end
	vel = dir.Unit * (distance / time)
	dashUntil = os.clock() + time
	arc = nil
	setMode("dash")
end

-- Meteor Leap: a high arc to a landing spot in `time` seconds (the server granted the travel)
function MoveController.arcTo(target: Vector3, time: number, height: number)
	if not root then
		return
	end
	local mode = MoveController.mode
	if mode == "ground" or mode == "charge" then
		enterAir(Vector3.zero)
	end
	dashReturn = "air"
	arc = { from = root.Position, to = target, start = os.clock(), time = time, height = height }
	dashUntil = os.clock() + time
	setMode("dash")
end

-- A wall within `reach` of the hero along `dir` (a near-vertical face), or nil
local function wallAlong(dir: Vector3, reach: number): RaycastResult?
	if not root or dir.Magnitude < 1e-3 then
		return nil
	end
	local hit = Workspace:Raycast(root.Position, dir.Unit * reach, rayParams)
	if hit and math.abs(hit.Normal.Y) < 0.35 then
		return hit
	end
	return nil
end

-- Terrain water under the hero (within `reach`), or nil: the surface height
local function waterBelow(reach: number): number?
	if not root then
		return nil
	end
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), waterParams)
	if hit and hit.Material == Enum.Material.Water then
		return hit.Position.Y
	end
	return nil
end

local function enterWall(normal: Vector3, speed: number, drain: number, mode: string)
	wallNormal = Vector3.new(normal.X, 0, normal.Z)
	if wallNormal.Magnitude < 1e-3 then
		return
	end
	wallNormal = wallNormal.Unit
	wallSpeed, wallDrain = speed, drain
	wallStart = os.clock()
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		enterAir(Vector3.zero)
	end
	setMode(mode)
end

-- off a wall with a kick away from it
local function jumpOff(up: number, out: number)
	vel = wallNormal * out + Vector3.new(0, up, 0)
	airSince = os.clock()
	wallLeft = airSince
	setMode("air")
end

-- off a wall run: keep the speed along the wall, kick away and up (inside the mobility's cap)
local function kickAlong(up: number, out: number)
	local fv = Vector3.new(vel.X, 0, vel.Z)
	local along = Vector3.yAxis:Cross(wallNormal)
	if along:Dot(fv) < 0 then
		along = -along
	end
	local vx, vy, vz =
		MoveMath.wallKick(M, mobility(), along.X, along.Z, wallSpeed, wallNormal.X, wallNormal.Z, up, out)
	vel = Vector3.new(vx, vy, vz)
	airSince = os.clock()
	wallLeft = airSince
	setMode("air")
end

-- In the air beside or at a wall (Acrobat and Super-speed): grab it to climb or run up it (head-on) or run
-- along it (glancing) at the speed the hero came in with. Returns whether it grabbed.
local function airWallGrab(flat: Vector3, now: number): boolean
	local pick = mobility()
	if (pick ~= "acrobat" and pick ~= "speed") or held() then
		return false
	end
	if now - wallLeft < M.wall.regrab or now - airSince < M.wall.regrab then
		return false
	end
	local fv = Vector3.new(vel.X, 0, vel.Z)
	local dir = if flat.Magnitude > 0.3 then flat.Unit elseif fv.Magnitude > 1 then fv.Unit else nil
	if not dir then
		return false
	end
	local hit = wallAlong(dir, 3)
	if not hit and fv.Magnitude > 1 then
		local side = fv.Unit:Cross(Vector3.yAxis)
		hit = wallAlong(side, 3.5) or wallAlong(-side, 3.5)
	end
	if not hit then
		return false
	end
	local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	if n.Magnitude < 1e-3 then
		return false
	end
	n = n.Unit
	if spentWall and spentWall:Dot(n) > 0.95 then
		return false -- the wall run that just ran out
	end
	-- the way the hero goes (slow, falling beside a wall: the way the stick points)
	local going = if fv.Magnitude >= M.mobility.acrobat.wallRunMin then fv.Unit else dir
	local stickIn = flat.Magnitude > 0.3 and flat.Unit:Dot(-n) > 0.5
	local kind, speed = MoveMath.wallGrab(M, pick, fv.Magnitude, going:Dot(-n), stickIn)
	if not kind then
		return false
	end
	if pick == "speed" and MoveController.stamina <= M.mobility.speed.wallDrain * 0.5 then
		return false
	end
	local drain = if pick == "speed" then M.mobility.speed.wallDrain else 0
	enterWall(n, speed, drain, kind)
	return true
end

local function dropLine()
	swingAnchor = nil
	swingPart = nil
	if swingLine then
		swingLine:Destroy()
		swingLine = nil
	end
end

-- Swing: fire a line at the building the camera looks at (a bit upward), within the line's range
local function swingRange(): number
	local m = M.mobility.swing
	return if level() >= m.up.rangeLevel then m.up.range else m.range
end
local function aimHit(range: number, lift: number, look: Vector3?): RaycastResult?
	local cam = Workspace.CurrentCamera.CFrame
	local dir = ((look or cam.LookVector) + Vector3.new(0, lift, 0)).Unit
	local from = if root then root.Position else cam.Position
	return Workspace:Raycast(from, dir * range, rayParams)
end

-- the first thing the line can hang from: the camera's aim at each of the swing's lifts, then the same along
-- the way the hero travels (nate's playtest 2026-11-19: one fixed aim missed most buildings)
local function swingAim(): RaycastResult?
	if not root then
		return nil
	end
	local m = M.mobility.swing
	local range = swingRange()
	local cam = Workspace.CurrentCamera.CFrame
	local looks = { cam.LookVector }
	local fv = Vector3.new(vel.X, 0, vel.Z)
	if fv.Magnitude > 5 then
		table.insert(looks, fv.Unit)
	end
	for _, look in looks do
		for _, lift in m.lifts do
			local hit = aimHit(range, lift, look)
			if hit and hit.Position.Y >= root.Position.Y + m.minAbove then
				return hit
			end
		end
	end
	return nil
end

local function startSwing(): boolean
	local hit = swingAim()
	if not hit or not root then
		return false
	end
	local m = M.mobility.swing
	-- the rope keeps the swing's low point off the street under the anchor
	local below = Workspace:Raycast(
		hit.Position + hit.Normal * 2,
		Vector3.new(0, -(hit.Position.Y - root.Position.Y + 200), 0),
		rayParams
	)
	local p, a = root.Position, hit.Position
	swingAnchor = a
	swingPart = hit.Instance
	swingLen = MoveMath.swingRope(M, p.X, p.Y, p.Z, a.X, a.Y, a.Z, if below then below.Position.Y else nil)
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		local run = root.AssemblyLinearVelocity
		enterAir(Vector3.new(run.X, m.groundPop, run.Z))
	end
	local line = Instance.new("Part")
	line.Name = "SwingLine" -- PLACEHOLDER ART: a plain line until the VFX pass
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	line.Material = Enum.Material.Neon
	line.Color = MoveController.lineColor or Color3.fromRGB(235, 235, 245)
	line.Size = Vector3.new(0.15, 0.15, 1)
	line.Parent = Workspace
	swingLine = line
	setMode("swing")
	return true
end

-- Swing on the ground: zip to the spot aimed at (a ledge or rooftop), inside the server's swing cap
local function zip(): boolean
	local hit = aimHit(swingRange(), 0.2)
	if not hit or not root then
		return false
	end
	local target = hit.Position + hit.Normal * 3 + Vector3.new(0, 4, 0)
	local d = (target - root.Position).Magnitude
	if d < 12 then
		return false
	end
	MoveController.arcTo(target, d / (M.mobility.swing.zip * 0.9), math.min(12, d * 0.08))
	return true
end

-- Travel powers (CombatClient): ride for `duration` at up to `speed` (the server allows it with the ride buff)
function MoveController.ride(kind: string, speed: number, duration: number)
	if not root then
		return
	end
	local cam = Workspace.CurrentCamera.CFrame
	local look = cam.LookVector
	if kind ~= "air" then
		local flat = Vector3.new(look.X, 0, look.Z)
		look = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	end
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		enterAir(Vector3.new(0, 8, 0))
	end
	dropLine()
	ride = { kind = kind, speed = speed, untilT = os.clock() + duration, dir = look }
	airSince = os.clock()
	setMode("ride")
end

-- Launch travel powers (Sky Step, Recoil Jump, Stone Pillar, Giant Stride): an arc to a spot the server allowed
function MoveController.launchTo(target: Vector3, time: number, height: number)
	dropLine()
	MoveController.arcTo(target, time, height)
end

-- Weightless: take off (any hero may fly while zeroG lasts)
MoveController.wantTakeOff = 0
function MoveController.takeOff()
	if not hum or MoveController.mode == "fly" then
		return
	end
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		enterAir(Vector3.new(0, 30, 0))
	end
	setMode("fly")
end

-- The touch and HUD labels for this hero's buttons (nil = hidden)
-- Set (or clear with nil) one named speed scale and apply it to the walk at once
function MoveController.setScale(name: string, value: number?)
	if MoveController.scales[name] == value then
		return
	end
	MoveController.scales[name] = value
	if hum and not hum.PlatformStand then
		hum.WalkSpeed = runSpeed()
	end
end

function MoveController.labels(): { leap: string, fly: string?, boost: string?, down: string? }
	local mode = MoveController.mode
	local pick = mobility()
	local flying = mode == "fly"
	local air = mode ~= "ground" and mode ~= "charge"
	local out: { leap: string, fly: string?, boost: string?, down: string? } = { leap = "LEAP" }
	if flying then
		out.leap, out.fly, out.boost, out.down = "UP", "LAND", "BOOST", "DOWN"
		return out
	end
	if canFly() then
		out.fly = "FLY"
	end
	if mode == "air" or mode == "glide" then
		out.leap = "GLIDE"
	end
	if pick == "speed" then
		out.boost = "SPRINT"
	elseif pick == "leap" then
		out.down = if air then "POUND" else nil
		if air and bounces < M.mobility.leap.bounce.max then
			out.leap = "BOUNCE"
		end
	elseif pick == "acrobat" then
		if
			air
			and airJumps
				< (if level() >= M.mobility.acrobat.up.jumpsLevel then 2 else M.mobility.acrobat.jumps)
		then
			out.leap = "JUMP"
		end
	elseif pick == "swing" then
		out.fly = if mode == "swing" then "LET GO" elseif air then "SWING" else "ZIP"
	end
	return out
end

local function orientation(mode: string, dt: number): CFrame
	local cam = Workspace.CurrentCamera.CFrame
	local camFlat = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local dir = if flatVel.Magnitude > 2
		then flatVel.Unit
		elseif camFlat.Magnitude > 1e-3 then camFlat.Unit
		else Vector3.new(0, 0, -1)
	local yaw = math.atan2(-dir.X, -dir.Z)
	-- bank into turns
	local yawRate = ((yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3)
	lastYaw = yaw
	local speed = vel.Magnitude
	local fl = M.flight
	local frac = math.clamp((speed - 10) / 50, 0, 1)
	local targetRoll = math.clamp(-math.deg(yawRate) * 0.25, -fl.bankMax, fl.bankMax) * frac
	roll += (targetRoll - roll) * math.min(1, dt * 6)
	local tilt = 0
	if mode == "fly" or mode == "dash" then
		local p = if speed > 1 then math.deg(math.asin(math.clamp(vel.Y / speed, -1, 1))) else 0
		tilt = math.clamp(-(90 - p), -170, 0) * (fl.pitchMax / 90) * frac
	elseif mode == "glide" then
		tilt = -35
	elseif mode == "wall" and wallNormal.Magnitude > 0 then
		-- face the wall while running or climbing up it
		return CFrame.lookAt(Vector3.zero, -wallNormal)
	end
	return CFrame.fromOrientation(0, yaw, 0)
		* CFrame.Angles(0, 0, math.rad(roll))
		* CFrame.Angles(math.rad(tilt), 0, 0)
end

-- Momentum and impact (nate's playtest 2026-11-19: "flying at super speed. Momentum and impact should destroy
-- things"): moving fast enough (flight boost, a Super-speed running jump, a dash, a Leaping pound, a travel ride)
-- into a building's wall is a ram. The hero holds a short hit-stop, loses some speed and keeps pushing; ImpactFx
-- tells the server (ImpactService checks it and knocks the pieces out, so the hole opens and the hero goes on
-- through). A ground sprint into a wall still runs up it (Super-speed's wall run).
local RAM = Config.Combat.impact.ram
local RAM_MODES = { fly = true, dash = true, pound = true, ride = true }
local ramHold = 0
local ramNext = 0
local ramCarry: Vector3? = nil
local ramLast: { id: number, at: number } = { id = 0, at = -math.huge }

-- The wreckable building a part belongs to (its model in the city, or the stand-in pieces BuildingFx draws)
local function buildingOf(part: Instance): number?
	local m = part.Parent
	while m and m ~= Workspace do
		local id = m:GetAttribute("BuildingId") or m:GetAttribute("WreckOf")
		if type(id) == "number" then
			return id
		end
		m = m.Parent
	end
	return nil
end

local function ramStep(mode: string, v: Vector3, pos: Vector3, now: number, dt: number): Vector3
	if now < ramHold then
		return v * RAM.holdKeep -- the hit-stop
	end
	local carry = ramCarry
	if carry then
		ramCarry = nil
		return carry -- on through, a little slower
	end
	local speed = v.Magnitude
	if speed < RAM.minSpeed or now < ramNext or not (RAM_MODES[mode] or (mode == "air" and hopping)) then
		return v
	end
	local hit = Workspace:Raycast(pos, v.Unit * (speed * dt + RAM.reach), rayParams)
	if not hit or v.Unit:Dot(-hit.Normal) < RAM.facing then
		return v
	end
	local id = buildingOf(hit.Instance)
	if not id or (id == ramLast.id and now - ramLast.at < RAM.sameWall) then
		return v -- not a building, or the same one again at once (a wall that held: no hit-stop every frame)
	end
	ramLast.id, ramLast.at = id, now
	ramNext = now + RAM.cooldown
	ramHold = now + RAM.hitStop
	ramCarry = v * (1 - RAM.loss)
	MoveController.Rammed:Fire(hit.Position, hit.Normal, speed, id)
	return v * RAM.holdKeep
end

local function step(dt: number)
	if not root or not hum or not lv or not ao or hum.Health <= 0 then
		return
	end
	dt = math.min(dt, 1 / 20)
	local mode = MoveController.mode
	local pos = root.Position
	local onGround, groundY = grounded()
	local now = os.clock()

	if mode == "ground" then
		setBoost(false)
		MoveController.stamina = MoveMath.staminaStep(M, MoveController.stamina, true, false, dt)
		local pick = mobility()
		local flatWish = wishDirs()
		local moving = flatWish.Magnitude > 0.3 and not held() and not downed()
		if pick == "speed" then
			-- Super-speed: hold Boost to build up to the sprint; let go and it bleeds off
			sprint = MoveMath.sprintStep(M, sprint, moving and InputController.isDown("Boost"), dt)
			hum.WalkSpeed = runSpeed()
			local m = M.mobility.speed
			if moving and sprint >= m.waterRun then
				local wall = wallAlong(flatWish, 3)
				if wall and MoveController.stamina > m.wallDrain * 0.5 then
					enterWall(wall.Normal, m.wallRun, m.wallDrain, "wall")
					return
				end
				local surface = waterBelow(hum.HipHeight + root.Size.Y / 2 + 4)
				if surface then
					enterAir(flatWish * sprint)
					setMode("water")
					return
				end
			end
		elseif pick == "acrobat" and moving then
			local wall = wallAlong(flatWish, 2.5)
			if wall then
				enterWall(wall.Normal, M.mobility.acrobat.climb, 0, "wall")
				return
			end
		end
		if
			not onGround
			and hum:GetState() == Enum.HumanoidStateType.Freefall
			and root.AssemblyLinearVelocity.Y < -30
		then
			-- walked off a roof: take over so the fall uses the same floaty gravity and can glide
			enterAir(root.AssemblyLinearVelocity)
			setMode("air")
		end
		MoveController.velocity = root.AssemblyLinearVelocity
		return
	end

	if mode == "charge" then
		MoveController.velocity = root.AssemblyLinearVelocity
		if now - chargeStart >= chargeTime() then
			launch(1)
		end
		return
	end

	local flat, full = wishDirs()
	-- M10 tap-to-fly: steer toward a map marker until the stick moves or you arrive
	local target = MoveController.autoTarget
	if target then
		local toward = Vector3.new(target.X, math.max(target.Y + 40, pos.Y), target.Z) - pos
		local flatDist = Vector3.new(toward.X, 0, toward.Z).Magnitude
		if mode ~= "fly" or InputController.moveVector().Magnitude > 0.2 or flatDist < 40 then
			MoveController.autoTarget = nil
			if flatDist < 40 then
				MoveController.Arrived:Fire(target)
			end
		elseif toward.Magnitude > 1 then
			full = toward.Unit
			flat = Vector3.new(toward.X, 0, toward.Z).Unit
		end
	end
	local scale = scaleNow()
	if scale < 1 then
		full *= scale -- blocking, charging or carrying: slower in the air too
	end
	local fallSpeed = -vel.Y
	if held() or downed() then
		-- no control: a flight or glide drops into a fall
		flat, full = Vector3.zero, Vector3.zero
		if mode == "fly" or mode == "glide" then
			setBoost(false)
			setMode("air")
			mode = "air"
		end
	end
	if mode == "air" then
		vel = Vector3.new(MoveMath.airStep(M, vel.X, vel.Y, vel.Z, dt))
		if hopping then
			-- Super-speed's running jump: steer without losing the run; holding Leap means "hop again", so it
			-- only glides once it is really falling (off a roof)
			local hx, hz = MoveMath.hopSteer(M, vel.X, vel.Z, flat.X, flat.Z, dt)
			vel = Vector3.new(hx, vel.Y, hz)
			if InputController.isDown("Leap") and vel.Y <= M.mobility.speed.hop.glideBelow then
				hopping = false
				setMode("glide")
			end
		elseif mobility() == "leap" then
			-- Leaping: a firm air steer that never slows the leap, only turns it
			local A = M.mobility.leap.air
			local sx, sz = MoveMath.airSteer(vel.X, vel.Z, flat.X, flat.Z, A.accel, A.max, dt)
			vel = Vector3.new(sx, vel.Y, sz)
			if InputController.isDown("Leap") and vel.Y <= 0 then
				setMode("glide")
			end
		else
			-- light air control so a leap can be nudged
			vel += flat * 30 * dt
			if InputController.isDown("Leap") and vel.Y <= 0 then
				setMode("glide")
			end
		end
		MoveController.stamina = MoveMath.staminaStep(M, MoveController.stamina, false, false, dt)
		-- Acrobat and Super-speed: jump at a wall to climb or run up it, or glance off one to run along it
		if airWallGrab(flat, now) then
			mode = MoveController.mode
		end
	elseif mode == "glide" then
		local gcfg = if mobility() == "acrobat" then ACRO_CFG else M
		vel = Vector3.new(MoveMath.glideStep(gcfg, vel.X, vel.Y, vel.Z, flat.X, flat.Z, dt))
		if not InputController.isDown("Leap") then
			setMode("air")
		end
		MoveController.stamina = MoveMath.staminaStep(M, MoveController.stamina, false, false, dt)
	elseif mode == "fly" then
		local vertical = (if InputController.isDown("Leap") then 1 else 0)
			- (if InputController.isDown("Down") then 1 else 0)
		local wantBoost = InputController.isDown("Boost") and scale >= 1 -- no boost while blocking or carrying
		if wantBoost and not MoveController.boosting and MoveController.stamina < M.stamina.boostMin then
			wantBoost = false
		end
		local vx, vy, vz, boosting = MoveMath.flightStep(
			if mobility() == "flight" and level() >= M.mobility.flight.up.boostLevel then FLIGHT_UP else M,
			vel.X,
			vel.Y,
			vel.Z,
			pos.Y,
			MoveController.stamina,
			{
				wishX = full.X,
				wishY = full.Y,
				wishZ = full.Z,
				vertical = vertical,
				boost = wantBoost,
			},
			dt
		)
		vel = Vector3.new(vx, vy, vz)
		setBoost(boosting)
		local free = State.buff("zeroG") > 0 -- Weightless capstone: boosting is free
		if not canFly() then
			setBoost(false)
			setMode("air") -- Weightless ran out: gravity takes the hero back
		end
		MoveController.stamina =
			MoveMath.staminaStep(M, MoveController.stamina, false, boosting and not free, dt)
	elseif mode == "wall" then
		-- running (Super-speed) or climbing (Acrobat) up a wall
		local stillWall = wallAlong(-wallNormal, 3.2)
		MoveController.stamina = math.max(0, MoveController.stamina - wallDrain * dt)
		local keepGoing = if mobility() == "speed"
			then (InputController.isDown("Boost") or InputController.isDown("Leap")) and MoveController.stamina > 0
			else flat.Magnitude > 0.3
		if not stillWall then
			-- over the top: a hop onto the roof
			vel = -wallNormal * 18 + Vector3.new(0, 28, 0)
			airSince = now
			wallLeft = now
			setMode("air")
		elseif not keepGoing or held() then
			jumpOff(4, 10)
		else
			vel = Vector3.new(0, wallSpeed, 0) - wallNormal * 4
		end
		mode = MoveController.mode
	elseif mode == "wallrun" then
		-- along a wall (Acrobat while the stick is held, Super-speed while Boost or Leap is), sinking slowly
		local pick = mobility()
		local along = Vector3.yAxis:Cross(wallNormal)
		local fv = Vector3.new(vel.X, 0, vel.Z)
		if fv.Magnitude > 1e-3 and along:Dot(fv) < 0 then
			along = -along
		end
		if pick == "speed" then
			MoveController.stamina = math.max(0, MoveController.stamina - wallDrain * dt)
		end
		local keep = MoveMath.wallRunKeep(
			M,
			pick,
			now - wallStart,
			flat.X,
			flat.Z,
			wallNormal.X,
			wallNormal.Z,
			InputController.isDown("Boost") or InputController.isDown("Leap"),
			MoveController.stamina
		)
		if onGround and now - wallStart > 0.2 then
			toGround(0, pick == "speed") -- ran down onto the street: carry on running
			return
		elseif not wallAlong(-wallNormal, 4) or held() then
			kickAlong(10, 8) -- the wall ended (a corner): on along the way
		elseif not keep then
			spentWall = wallNormal
			kickAlong(10, 8)
		else
			local sink = if pick == "acrobat" then M.mobility.acrobat.sink else 0
			vel = along * wallSpeed + Vector3.new(0, -sink, 0) - wallNormal * 3
		end
		mode = MoveController.mode
	elseif mode == "water" then
		-- Super-speed across water: hold the sprint or sink in
		local m = M.mobility.speed
		sprint = MoveMath.sprintStep(M, sprint, InputController.isDown("Boost"), dt)
		local surface = waterBelow(10)
		local fv = Vector3.new(vel.X, 0, vel.Z)
		local dir = if flat.Magnitude > 0.3
			then flat.Unit
			elseif fv.Magnitude > 1e-3 then fv.Unit
			else root.CFrame.LookVector
		if not surface or sprint < m.waterRun or held() then
			toGround(0) -- off the water onto land, or into the water to swim
			return
		end
		local targetY = surface + hum.HipHeight + root.Size.Y / 2
		vel = dir * sprint + Vector3.new(0, (targetY - pos.Y) * 10, 0)
	elseif mode == "pound" then
		vel = Vector3.new(0, -M.mobility.leap.pound.speed, 0)
		if onGround then
			Net.send("MovePound")
			MoveController.Pounded:Fire(pos)
			toGround(M.mobility.leap.pound.speed)
			return
		end
	elseif mode == "swing" then
		local anchor = swingAnchor
		local part = swingPart
		local ahead = Vector3.new(vel.X, 0, vel.Z)
		local bump = if ahead.Magnitude > 5 then wallAlong(ahead, 3) else nil
		if bump then
			-- swung into a wall: let go and push off it, never stuck pressed against the building
			dropLine()
			local n = Vector3.new(bump.Normal.X, 0, bump.Normal.Z)
			wallNormal = if n.Magnitude > 1e-3 then n.Unit else -ahead.Unit
			jumpOff(M.mobility.swing.release.up, 15)
		elseif not anchor or (part and not part.Parent) or not InputController.isDown("Fly") or held() then
			-- let go (or the piece it hung from broke off): fling on with the swing's speed
			dropLine()
			vel = Vector3.new(MoveMath.swingRelease(M, vel.X, vel.Y, vel.Z))
			airSince = now
			setMode("air")
		else
			local nx, ny, nz = MoveMath.swingStep(
				M,
				pos.X,
				pos.Y,
				pos.Z,
				vel.X,
				vel.Y,
				vel.Z,
				anchor.X,
				anchor.Y,
				anchor.Z,
				swingLen,
				flat.X,
				flat.Z,
				dt
			)
			local next = Vector3.new(nx, ny, nz)
			vel = (next - pos) / math.max(dt, 1e-3)
			if vel.Magnitude > M.mobility.swing.maxSpeed then
				vel = vel.Unit * M.mobility.swing.maxSpeed
			end
			if swingLine then
				local mid = (pos + anchor) / 2
				swingLine.Size = Vector3.new(0.15, 0.15, (anchor - pos).Magnitude)
				swingLine.CFrame = CFrame.lookAt(mid, anchor)
			end
			if pos.Y > anchor.Y - 2 then
				-- swung up past the anchor: let go at the top, flinging on
				dropLine()
				vel = Vector3.new(MoveMath.swingRelease(M, vel.X, vel.Y, vel.Z))
				airSince = now
				setMode("air")
			end
		end
		mode = MoveController.mode
	elseif mode == "ride" then
		local r = ride
		if not r or now >= r.untilT or held() then
			ride = nil
			vel *= 0.5
			setMode("air")
			mode = "air"
		else
			if r.kind == "air" then
				-- steer freely like flight; Leap climbs, Down dives
				local vertical = (if InputController.isDown("Leap") then 1 else 0)
					- (if InputController.isDown("Down") then 1 else 0)
				local want = if full.Magnitude > 0.3 then full.Unit else r.dir
				want = (want + Vector3.new(0, vertical * 0.6, 0)).Unit
				r.dir = r.dir:Lerp(want, math.min(1, dt * 4)).Unit
				vel = r.dir * r.speed
			elseif r.kind == "surf" then
				-- along the street (and over water), up any wall in the way
				local want = if flat.Magnitude > 0.3 then flat.Unit else r.dir
				r.dir = r.dir:Lerp(want, math.min(1, dt * 5)).Unit
				local wall = wallAlong(r.dir, 4)
				local below = Workspace:Raycast(pos, Vector3.new(0, -30, 0), waterParams)
				local up = 0
				if wall then
					up = r.speed * 0.8
				elseif below then
					up = (below.Position.Y + 3.5 - pos.Y) * 8
				else
					up = -30
				end
				vel = r.dir * r.speed + Vector3.new(0, up, 0)
			else -- rail: straight along the aim it started on, steering gently
				local want = if flat.Magnitude > 0.3 then flat.Unit else r.dir
				r.dir = r.dir:Lerp(want, math.min(1, dt * 1.2)).Unit
				vel = r.dir * r.speed + Vector3.new(0, if wallAlong(r.dir, 5) then r.speed * 0.7 else 0, 0)
			end
		end
	elseif mode == "dash" then
		local a = arc
		if a then
			local t = math.clamp((now - a.start) / a.time, 0, 1)
			local t2 = math.clamp(t + dt / a.time, 0, 1)
			local function at(u: number): Vector3
				return a.from:Lerp(a.to, u) + Vector3.new(0, a.height * 4 * u * (1 - u), 0)
			end
			vel = (at(t2) - at(t)) / math.max(dt, 1e-3)
		end
		if now >= dashUntil then
			arc = nil
			vel *= 0.25
			setMode(dashReturn)
			mode = dashReturn
		end
	end

	-- ceiling for every air mode
	if pos.Y > M.ceiling.hard and vel.Y > 0 and MoveMath.ceilingOn(M, pos.Y) then
		vel = Vector3.new(vel.X, 0, vel.Z)
	end

	-- landing
	local selfManaged = mode == "dash"
		or mode == "wall"
		or mode == "wallrun"
		or mode == "water"
		or mode == "pound"
		or mode == "ride"
		or (mode == "swing" and vel.Y > 0)
	if onGround and now - airSince > 0.15 and not selfManaged then
		if mode == "swing" then
			dropLine()
		end
		local landing = (mode == "air" or mode == "glide" or mode == "swing") and vel.Y <= 0
			or (mode == "fly" and (vel.Y < -2 or InputController.isDown("Down")) and pos.Y - groundY < 4.5)
		if landing then
			if
				hopping
				and mode == "air"
				and InputController.isDown("Leap")
				and not held()
				and not downed()
			then
				-- holding Leap: straight into the next hop, same speed (no landing stop, no crouch)
				local hx, hy, hz = MoveMath.speedHop(M, vel.X, vel.Z, flat.X, flat.Z, sprint)
				vel = Vector3.new(hx, hy, hz)
				airSince = now
				MoveController.Leaped:Fire(pos)
			else
				toGround(fallSpeed, hopping and mode == "air")
				return
			end
		end
	end

	vel = ramStep(MoveController.mode, vel, pos, now, dt)
	lv.VectorVelocity = vel
	ao.CFrame = orientation(MoveController.mode, dt)
	MoveController.velocity = vel
end

local function onPressed(action: string)
	if not hum or hum.Health <= 0 or held() or downed() then
		return
	end
	local mode = MoveController.mode
	local pick = mobility()
	local air = mode ~= "ground" and mode ~= "charge"
	if action == "Leap" then
		local runFlat = if root
			then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
			else Vector3.zero
		if
			mode == "ground"
			and pick == "speed"
			and math.max(sprint, runFlat.Magnitude) >= M.mobility.speed.hop.from
			and runFlat.Magnitude >= M.mobility.speed.hop.from * 0.5
		then
			-- Super-speed's running jump: no crouch, the run's speed carries into the air
			local flat = wishDirs()
			local hx, hy, hz = MoveMath.speedHop(M, runFlat.X, runFlat.Z, flat.X, flat.Z, sprint)
			lastLeap = os.clock()
			enterAir(Vector3.new(hx, hy, hz))
			hopping = true
			setMode("air")
			if root then
				MoveController.Leaped:Fire(root.Position)
			end
		elseif mode == "ground" and MoveController.leapReady() >= 1 then
			chargeStart = os.clock()
			chargeRun = runFlat -- Leaping keeps some of the run in the leap
			hum.WalkSpeed = 6 -- the crouch
			setMode("charge")
		elseif mode == "wall" or mode == "wallrun" then
			-- kick off the wall (Acrobat gets an air jump back)
			-- a kick off a wall run keeps the speed along the wall, so the next wall can be grabbed (chains)
			spentWall = nil
			local along = mode == "wallrun"
			if pick == "acrobat" then
				airJumps = math.max(0, airJumps - 1)
				if along then
					kickAlong(M.mobility.acrobat.jump, M.mobility.acrobat.jumpForward)
				else
					jumpOff(M.mobility.acrobat.jump, M.mobility.acrobat.jumpForward)
				end
			elseif along then
				kickAlong(40, 30)
			else
				jumpOff(40, 30)
			end
		elseif (mode == "air" or mode == "glide") and pick == "leap" then
			-- Leaping: bounce off a wall within reach
			local b = M.mobility.leap.bounce
			if bounces < b.max and root then
				for _, d in
					{
						root.CFrame.LookVector,
						-root.CFrame.LookVector,
						root.CFrame.RightVector,
						-root.CFrame.RightVector,
					}
				do
					local wall = wallAlong(Vector3.new(d.X, 0, d.Z), b.reach)
					if wall then
						bounces += 1
						wallNormal = Vector3.new(wall.Normal.X, 0, wall.Normal.Z).Unit
						-- keep `keep` of the speed along the wall, so bounces carry the leap on
						local fv = Vector3.new(vel.X, 0, vel.Z)
						local along = fv - wallNormal * fv:Dot(wallNormal)
						jumpOff(b.up, b.out)
						vel += along * b.keep
						MoveController.Leaped:Fire(root.Position)
						break
					end
				end
			end
		elseif (mode == "air" or mode == "glide") and pick == "acrobat" then
			-- Acrobat: jump again in the air
			local a = M.mobility.acrobat
			local most = if level() >= a.up.jumpsLevel then 2 else a.jumps
			if airJumps < most and root then
				airJumps += 1
				local flat = wishDirs()
				local keep = Vector3.new(vel.X, 0, vel.Z) * 0.5
				vel = keep + flat * a.jumpForward + Vector3.new(0, a.jump, 0)
				setMode("air")
				MoveController.Leaped:Fire(root.Position)
			end
		end
	elseif action == "Fly" then
		if pick == "swing" and not canFly() then
			if mode == "swing" then
				return -- releasing the button lets go
			end
			-- on the ground a zip to the spot aimed at; in the air (or with nothing to zip to) a swing line
			if air or not zip() then
				startSwing()
			end
			return
		end
		if mode == "fly" then
			setBoost(false)
			setMode("air")
		elseif canFly() and mode ~= "dash" then
			if mode == "ground" or mode == "charge" then
				hum.WalkSpeed = runSpeed()
				enterAir(Vector3.new(0, 30, 0)) -- take-off hop
			else
				dropLine()
				airSince = os.clock()
			end
			setMode("fly")
		end
	elseif action == "Down" then
		if pick == "leap" and (mode == "air" or mode == "glide") and root then
			local hit = Workspace:Raycast(root.Position, Vector3.new(0, -400, 0), rayParams)
			local height = if hit then root.Position.Y - hit.Position.Y else 400
			if height >= M.mobility.leap.pound.minFall then
				setMode("pound")
			end
		end
	end
end

-- Tap-to-fly (spec: Map "Tap a marker to auto-fly"): take off and fly toward a spot; any stick push or
-- landing ends it. Needs flight; false otherwise.
MoveController.autoTarget = nil :: Vector3?
MoveController.Arrived = Signal.new() -- (target)
function MoveController.flyTo(target: Vector3): boolean
	if not canFly() or not hum or hum.Health <= 0 then
		return false
	end
	MoveController.autoTarget = target
	if MoveController.mode ~= "fly" then
		onPressed("Fly")
	end
	return MoveController.mode == "fly"
end

local function onReleased(action: string)
	if action == "Leap" and MoveController.mode == "charge" then
		launch(math.clamp((os.clock() - chargeStart) / chargeTime(), 0, 1))
	end
end

local function bind(character: Model)
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	hum = character:WaitForChild("Humanoid") :: Humanoid
	rayParams.FilterDescendantsInstances = { character }
	local att = Instance.new("Attachment")
	att.Name = "MoveAttachment"
	att.Parent = root
	local v = Instance.new("LinearVelocity")
	v.Attachment0 = att
	v.RelativeTo = Enum.ActuatorRelativeTo.World
	v.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	v.MaxForce = 1e7
	v.Enabled = false
	v.Parent = root
	local o = Instance.new("AlignOrientation")
	o.Mode = Enum.OrientationAlignmentMode.OneAttachment
	o.Attachment0 = att
	o.Responsiveness = 35
	o.MaxTorque = 1e7
	o.Enabled = false
	o.Parent = root
	lv, ao = v, o
	vel = Vector3.zero
	MoveController.stamina = M.stamina.max
	MoveController.boosting = false
	sprint = M.run.speed
	airJumps, bounces = 0, 0
	ride = nil
	dropLine()
	setMode("ground");
	(hum :: Humanoid).Died:Connect(function()
		v.Enabled = false
		o.Enabled = false
		setBoost(false)
		dropLine()
		ride = nil
	end)
end

function MoveController.init()
	if player.Character then
		task.spawn(bind, player.Character)
	end
	player.CharacterAdded:Connect(bind)
	InputController.Pressed:Connect(onPressed)
	InputController.Released:Connect(onReleased)
	State.StatusChanged:Connect(function()
		if hum and MoveController.mode == "ground" then
			hum.WalkSpeed = runSpeed()
		end
		if os.clock() < MoveController.wantTakeOff and State.buff("zeroG") > 0 then
			MoveController.wantTakeOff = 0
			MoveController.takeOff()
		end
	end)
	Net.listen("MoveCorrect", function(pos: Vector3)
		if root then
			root.CFrame = CFrame.new(pos) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
			vel = Vector3.zero
			if MoveController.mode == "dash" then
				setMode(dashReturn)
			end
			sprint = M.run.speed
			if MoveController.mode ~= "ground" and MoveController.mode ~= "fly" then
				dropLine()
				ride = nil
				setMode("air")
			end
		end
	end)
	Net.listen("HeroKnock", function(k)
		local r = root
		if not r or downed() then
			return
		end
		local move = Vector3.new(k.x, k.y, k.z)
		local flat = Vector3.new(move.X, 0, move.Z)
		-- drop (optional, usually negative): a Grappler's hook pulls a flying hero down toward it
		MoveController.arcTo(
			r.Position + flat + Vector3.new(0, k.drop or 0, 0),
			k.time or 0.35,
			math.max(2, move.Y)
		)
	end)
	player:GetAttributeChangedSignal("Downed"):Connect(function()
		if hum and MoveController.mode == "ground" then
			hum.WalkSpeed = runSpeed()
		end
	end)
	RunService.PreSimulation:Connect(step)
end

return MoveController
