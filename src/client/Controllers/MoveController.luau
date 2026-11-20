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
--   acrobat  Leap in the air to double jump, walk or jump into any wall (or rise into a ceiling) to `crawl` over
--            it (round corners, onto roofs; Boost scurries), jump at one glancingly to run along it (`wallrun`,
--            while the stick is held; Leap kicks off and chains), Down to `flip` (a dodge: the server's MoveFlip
--            makes attacks miss for its i-frames), the best air control, a faster glide (nate 2026-11-19 20:42Z)
--   leap/speed smash rule (nate on the card, 2026-11-19 20:45Z): Super-speed holding Boost and a fast leap
--            (ClimbMath.leapSmash) go straight through a wall (the flight ram); otherwise Super-speed runs up or
--            along it and Leaping grabs it: the Hulk `climb` (hang), Leap `bound`s up the face to the next grab,
--            a vault over the top onto the roof, Leap with the stick away kicks off (Shared.ClimbMath)
--   everyone sprints on Boost on the ground (Config.Move.sprint; nate 20:46Z), Super-speed far faster
--   swing    Spider-Man swinging (nate's playtest 2026-11-19; Shared.SwingMath): hold Fly in the air to shoot a line
--            at a real building face or roof corner ahead and above along the camera (never the sky: a miss shows
--            the cue), `swing` through the pendulum, let go to fling forward and up (hold Fly to catch the next
--            line as the hero falls), Leap while swinging zips up the line and pops over the top; Fly on the
--            ground zips to the spot aimed at. SwingFx draws the line, CameraController the speed feel
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
local CityPlay = require(Shared:WaitForChild("CityPlay"))
local SwingMath = require(Shared:WaitForChild("SwingMath"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MoveRanks = require(Shared:WaitForChild("MoveRanks"))
local ClimbMath = require(Shared:WaitForChild("ClimbMath"))

local InputController = require(script.Parent.InputController)
local State = require(script.Parent.Parent.State)

-- side-content (2026-11-19): M is this hero's own Config.Move, its pick's trained ranks applied (Shared.MoveRanks;
-- retune() swaps it when the hero state changes). The server's MoveGuard reads the very same copy for its caps.
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
MoveController.Dropped = Signal.new() -- (position, fall speed) a drop from high up smashed onto a roof (MoveFx)
MoveController.Bounced = Signal.new() -- (position, up speed) an awning sprang the hero up (pt-city)
MoveController.Rammed = Signal.new() -- (contact, wall normal, speed, building id) a fast hero hit a wall (ImpactFx)
-- the climbs (MoveFx): the Hulk grab (where the hands bite, the wall's normal), a bound up the face, the vault over
-- the top; the Acrobat's crawl taking a face (contact, normal) and its flip (position)
MoveController.Grabbed = Signal.new()
MoveController.Bounded = Signal.new()
MoveController.Vaulted = Signal.new()
MoveController.Crawled = Signal.new()
MoveController.Flipped = Signal.new()
-- the swing (SwingFx, CameraController, HeroAnimator): a line shot (anchor, edge), let go (velocity, sweet), a
-- line with nothing real to hang from (from, look), a zip begun (target)
MoveController.SwingShot = Signal.new()
MoveController.SwingReleased = Signal.new()
MoveController.SwingMissed = Signal.new()
MoveController.Zipped = Signal.new()
-- the swing's pose state, updated in place every frame (no new tables): state "none", "shoot" (the line flying
-- out), "swing", "release" (just let go) or "zip"; phase: SwingMath.phase (-1 high behind, 0 bottom, +1 level
-- ahead); speed: share of the swing's top speed; anchor: where the line hangs (nil: none); shotAt: os.clock() of
-- the shot. HeroAnimator can pick its swing clips from it (pt-anims adds them; today the swing, swingCatch and
-- swingRelease clips play from the mode).
MoveController.swingPose = {
	state = "none",
	phase = 0,
	speed = 0,
	anchor = nil :: Vector3?,
	shotAt = 0,
	sweet = false,
}

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
-- a fast-travel flight (TravelClient, gap polish 2026-11-19): the body follows at(f) for `time` seconds
local trip: { at: (number) -> Vector3, start: number, time: number, hold: boolean, upright: boolean? }? = nil

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
local swingPivot = Vector3.zero -- the point the hero swings under (SwingMath.pivot: in the plane of its travel)
local swingLen = 0
local swingTarget = 0 -- the length the rope reels toward (its low point clear of the street)
local swingPart: BasePart? = nil -- what the line hangs from (a broken building piece drops the line)
local swingNormal = Vector3.zero
local swingEdge = false -- the line hangs from a roof edge or corner
local releasedAt = -math.huge
local missedAt = -math.huge
local zipping = false -- the dash arc now is a zip (it pops at its end)
local zipDir = Vector3.zero
local swingDrive: Vector3? = nil -- this frame's body velocity on the rope (the swing's own plus the rope's pull)
local chargeRun = Vector3.zero -- the flat run speed when a Leaping charge began (carried into the leap)
local baseRun = M.run.speed -- everyone's run on the ground: eased up to Config.Move.sprint.speed on Boost
-- the Hulk climb (Leaping): the vertical speed of a bound, when the grab began, the last bite sent
local boundVy = 0
local gripAt = 0
local biteAt = -math.huge
-- the wall crawl (Acrobat): the face's normal and the body's heading along it
local crawlN = Vector3.zero
local crawlHead = Vector3.yAxis
local crawlAt = -math.huge -- when the last crawl ended (no re-stick at once)
-- the flip (Acrobat): when the last one began and when this one ends, and its burst
local flipAt = -math.huge
local flipUntil = 0
local swingSky = false -- the line hangs from the sky (SwingMath.skyAnchor): the weaker swing
local drainAt = -math.huge -- when stamina last went down (regen waits Config.Move.stamina.regenDelay after it)
local lastStamina = M.stamina.max
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

-- side-content: swap in the trained copy (and the two derived tables) when the pick or its rank changes
local tunedKey = ""
local function retune()
	local pick = mobility()
	local rank = MoveRanks.rankOf(Config.Move, State.hero.mobRanks, pick)
	local key = pick .. "#" .. rank
	if key == tunedKey then
		return
	end
	tunedKey = key
	M = MoveRanks.config(Config.Move, pick, rank)
	ACRO_CFG = table.clone(M)
	ACRO_CFG.glide = table.clone(M.glide)
	ACRO_CFG.glide.forward = M.mobility.acrobat.glideForward
	ACRO_CFG.glide.cap = M.mobility.acrobat.cap
	FLIGHT_UP = table.clone(M)
	FLIGHT_UP.flight = table.clone(M.flight)
	FLIGHT_UP.flight.boost = math.max(M.flight.boost, M.mobility.flight.up.boost)
end
MoveController.retune = retune
-- the hero's movement numbers as the device moves with them (the POWERS screen's MOBILITY tab, FX)
function MoveController.config(): any
	return M
end

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
	local base = baseRun -- everyone's run, up to the sprint on Boost (Config.Move.sprint)
	local pick = mobility()
	if pick == "speed" then
		base = sprint -- Super-speed: the sprint (20 walking, up to 100 holding Boost)
	elseif pick == "acrobat" then
		base = M.mobility.acrobat.run + (baseRun - M.run.speed)
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
	local look, right = cam.LookVector, cam.RightVector
	-- omnidirectional (Config.Move.omni): every direction relative to the camera, never relative to the body
	local ax, az, bx, by, bz = MoveMath.omniWish(mv.X, mv.Z, look.X, look.Y, look.Z, right.X, right.Z)
	return Vector3.new(ax, 0, az), Vector3.new(bx, by, bz)
end

-- Lock-on (LockClient sets it each frame): the locked target's position, or nil. The body turns to it on the
-- ground (strafe and backpedal circle it) and in the air (omniFace).
MoveController.lockAt = nil :: Vector3?
local groundLocked = false

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
	if not root or trip or dir.Magnitude < 0.1 then
		return
	end
	local mode = MoveController.mode
	zipping = false
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
	if not root or trip then
		return
	end
	local mode = MoveController.mode
	if mode == "ground" or mode == "charge" then
		enterAir(Vector3.zero)
	end
	dashReturn = "air"
	zipping = false
	arc = { from = root.Position, to = target, start = os.clock(), time = time, height = height }
	dashUntil = os.clock() + time
	setMode("dash")
end

-- Whether the dash now is an arc (a zip, a grapple, a launch power, a guided hop): HeroAnimator poses it as one
function MoveController.arcing(): boolean
	return arc ~= nil and MoveController.mode == "dash"
end

-- An awning under a falling hero (pt-city, 2026-11-19; Config.City.kit.play.bounce): the speed it springs the hero
-- up at, or nil (not on one, not falling fast enough, or bounced a moment ago). The server takes the bounce
-- (CityBounce) once it finds the hero by an awning.
local PLAY = Config.City.kit.play
local bouncedAt = -math.huge
local function awningUp(vy: number): number?
	if not root or not hum or not PLAY or os.clock() - bouncedAt < PLAY.bounce.cooldown then
		return nil
	end
	local reach = hum.HipHeight + root.Size.Y / 2 + 1.2
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	local p = hit and hit.Instance
	if not (p and p:GetAttribute("Bounce") == true and p.LocalTransparencyModifier < 1) then
		return nil
	end
	local up = CityPlay.bounce(PLAY, vy)
	if up then
		bouncedAt = os.clock()
	end
	return up
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

-- set below the ram (they need its building lookup): the smash rule's wall check and the crawl's start
local isSmashable: (RaycastResult) -> boolean
local enterCrawl: (Vector3, Vector3) -> ()

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
	if
		pick == "speed"
		and ClimbMath.speedSmash(M, InputController.isDown("Boost"), fv.Magnitude)
		and isSmashable(hit)
	then
		return false -- the smash rule: Boost held, the ram goes through it instead
	end
	local kind, speed = MoveMath.wallGrab(M, pick, fv.Magnitude, going:Dot(-n), stickIn)
	if not kind then
		return false
	end
	if pick == "acrobat" and kind == "wall" then
		enterCrawl(hit.Position, hit.Normal) -- head-on: stick to it and crawl
		return true
	end
	if pick == "speed" and MoveController.stamina <= M.mobility.speed.wallDrain * 0.5 then
		return false
	end
	local drain = if pick == "speed" then M.mobility.speed.wallDrain else 0
	enterWall(n, speed, drain, kind)
	return true
end

local function dropLine()
	local had = swingAnchor ~= nil
	swingAnchor = nil
	swingPart = nil
	MoveController.swingPose.anchor = nil
	if had then
		Net.send("MoveLine", Vector3.zero) -- other devices stop drawing your line
	end
end

-- Swing: the line's reach at this level
local function swingRange(): number
	return SwingMath.range(M, level())
end
local function aimHit(range: number, lift: number, look: Vector3?): RaycastResult?
	local cam = Workspace.CurrentCamera.CFrame
	local dir = ((look or cam.LookVector) + Vector3.new(0, lift, 0)).Unit
	local from = if root then root.Position else cam.Position
	return Workspace:Raycast(from, dir * range, rayParams)
end

-- SwingMath's raycast: only fixed, solid things hold a line (buildings, their pieces, the ground's terrain),
-- never a character, a robot, a vehicle or a ghost sign
local function worldCast(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number)
	local hit = Workspace:Raycast(Vector3.new(ox, oy, oz), Vector3.new(dx, dy, dz), rayParams)
	if not hit then
		return nil, 0, 0, 0, 0, 0
	end
	local inst = hit.Instance
	if inst:IsA("BasePart") and (not inst.Anchored or not inst.CanCollide) then
		return nil, 0, 0, 0, 0, 0
	end
	local p, n = hit.Position, hit.Normal
	return p.X, p.Y, p.Z, n.X, n.Y, n.Z
end

-- the line: the best real anchor ahead and above along the camera's aim (then the travel), snapped to a roof
-- edge or corner when one is close (SwingMath.findAnchor; up to 34 rays, only when a line fires)
-- the hero's velocity now (on the ground the Humanoid moves the body, not `vel`)
local function travelVel(): Vector3
	local mode = MoveController.mode
	if root and (mode == "ground" or mode == "charge") then
		return root.AssemblyLinearVelocity
	end
	return vel
end

-- swing anywhere (nate's playtest 2026-11-19 20:42Z): SwingMath's wide fan catches trees, poles, rocks and cliffs
-- outside the city; with nothing at all in reach the weaker sky line (SwingMath.skyAnchor) hangs from the air
local function swingAim(): (Vector3?, Vector3, boolean, boolean)
	if not root then
		return nil, Vector3.zero, false, false
	end
	local p = root.Position
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local v = travelVel()
	local a = SwingMath.findAnchor(
		M,
		p.X,
		p.Y,
		p.Z,
		look.X,
		look.Y,
		look.Z,
		v.X,
		v.Z,
		swingRange(),
		worldCast,
		not SwingMath.inCity(Config.City.districts, p.X, p.Z)
	)
	if not a then
		a = SwingMath.skyAnchor(M, p.X, p.Y, p.Z, look.X, look.Z, v.X, v.Z, worldCast)
	end
	if not a then
		return nil, Vector3.zero, false, false
	end
	return Vector3.new(a.x, a.y, a.z), Vector3.new(a.nx, a.ny, a.nz), a.edge, a.sky == true
end

-- the swing's numbers for the line out now (a sky line's are weaker: SwingMath.skyConfig)
local function swingCfg(): any
	return if swingSky then SwingMath.skyConfig(M) else M
end

-- cue: show the miss (a pressed Fly; a held one retrying while falling stays quiet)
local function startSwing(cue: boolean): boolean
	if not root then
		return false
	end
	local anchor, normal, edge, sky = swingAim()
	local p = root.Position
	if not anchor then
		missedAt = os.clock()
		if cue then
			MoveController.SwingMissed:Fire(p, Workspace.CurrentCamera.CFrame.LookVector)
		end
		return false
	end
	-- what it hangs from (a piece that breaks off drops the line), seen straight from the hero
	local to = anchor - p
	local seen = Workspace:Raycast(p, to.Unit * (to.Magnitude + 2), rayParams)
	swingAnchor = anchor
	swingSky = sky
	swingPart = if seen and not sky then seen.Instance else nil
	swingNormal = normal
	swingEdge = edge
	-- the swing runs along the travel (or the camera's look from a standstill), under the anchor's height
	local tv = travelVel()
	local fv = Vector3.new(tv.X, 0, tv.Z)
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local way = if fv.Magnitude > 10 then fv else Vector3.new(look.X, 0, look.Z)
	local qx, qy, qz = SwingMath.pivot(M, p.X, p.Z, anchor.X, anchor.Y, anchor.Z, way.X, way.Z)
	swingPivot = Vector3.new(qx, qy, qz)
	-- the rope keeps the swing's low point (under the pivot) off the street
	local below = Workspace:Raycast(swingPivot, Vector3.new(0, -(qy - p.Y + 200), 0), rayParams)
	swingLen = SwingMath.rope(M, p.X, p.Y, p.Z, qx, qy, qz, nil)
	swingTarget = SwingMath.rope(M, p.X, p.Y, p.Z, qx, qy, qz, if below then below.Position.Y else nil)
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		local run = root.AssemblyLinearVelocity
		enterAir(Vector3.new(run.X, M.mobility.swing.groundPop, run.Z))
	end
	local pose = MoveController.swingPose
	pose.anchor = anchor
	pose.shotAt = os.clock()
	setMode("swing")
	Net.send("MoveLine", anchor) -- other devices draw your line (MoveGuard checks the reach)
	MoveController.SwingShot:Fire(anchor, edge)
	return true
end

-- Let go of the line: fling on with the swing's speed (SwingMath.release; sweet on the rising half)
local function releaseSwing(now: number)
	local a = if swingAnchor then swingPivot else nil
	local phase = 0
	if a and root then
		local p = root.Position
		phase = SwingMath.phase(p.X, p.Y, p.Z, a.X, a.Y, a.Z, vel.Y)
	end
	dropLine()
	local vx, vy, vz, sweet = SwingMath.release(swingCfg(), vel.X, vel.Y, vel.Z, phase)
	vel = Vector3.new(vx, vy, vz)
	airSince = now
	releasedAt = now
	MoveController.swingPose.sweet = sweet
	setMode("air")
	MoveController.SwingReleased:Fire(vel, sweet)
end

-- A zip to a point on an arc never faster than the swing's zip speed; it pops on at the end (the point launch)
local function zipTo(target: Vector3)
	if not root then
		return
	end
	local p = root.Position
	local t, h = SwingMath.zipPlan(M, p.X, p.Y, p.Z, target.X, target.Y, target.Z)
	MoveController.arcTo(target, t, h)
	zipping = true
	zipDir = target - p
	MoveController.Zipped:Fire(target)
end

-- Leap while swinging: up the line to its anchor and over the top (a roof edge: onto the roof; a wall: up its
-- face, the pop sliding along it)
local function zipLine()
	local a = swingAnchor
	if not a or not root then
		return
	end
	local n = Vector3.new(swingNormal.X, 0, swingNormal.Z)
	n = if n.Magnitude > 1e-3 then n.Unit else Vector3.zero
	local target = if swingEdge then a + Vector3.new(0, 5, 0) - n * 4 else a + n * 3 + Vector3.new(0, 2, 0)
	local edge = swingEdge
	dropLine()
	zipTo(target)
	if not edge and n.Magnitude > 0 then
		local flat = Vector3.new(zipDir.X, 0, zipDir.Z)
		zipDir = flat - n * flat:Dot(n) -- the pop slides along the wall, never into it
	end
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
	zipTo(target)
	return true
end

-- the pose state HeroAnimator can read (MoveController.swingPose), in place
local function swingPoseStep(mode: string, now: number)
	local pose = MoveController.swingPose
	local sw = M.mobility.swing
	pose.speed = math.clamp(vel.Magnitude / sw.maxSpeed, 0, 1.2)
	if mode == "swing" then
		pose.state = if now - pose.shotAt < sw.feel.shoot then "shoot" else "swing"
	elseif mode == "dash" and zipping then
		pose.state = "zip"
	elseif mode == "air" and now - releasedAt < 0.35 then
		pose.state = "release"
	else
		pose.state = "none"
		pose.phase = 0
	end
end

-- Travel powers (CombatClient): ride for `duration` at up to `speed` (the server allows it with the ride buff)
function MoveController.ride(kind: string, speed: number, duration: number)
	if not root or trip then
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
	if not hum or trip or MoveController.mode == "fly" then
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
	if not air then
		out.boost = "SPRINT" -- everyone's sprint (Super-speed's below)
	end
	if mode == "climb" or mode == "bound" then
		out.leap, out.down, out.boost = "CLIMB", "LET GO", nil
		return out
	elseif mode == "crawl" then
		out.leap, out.down, out.boost = "JUMP", "LET GO", "SCURRY"
		return out
	end
	if pick == "speed" then
		out.boost = "SPRINT"
	elseif pick == "leap" then
		out.down = if air then "POUND" else nil
		if air and bounces < M.mobility.leap.bounce.max then
			out.leap = "BOUNCE"
		end
	elseif pick == "acrobat" then
		out.down = "FLIP"
		if
			air
			and airJumps
				< (if level() >= M.mobility.acrobat.up.jumpsLevel
					then M.mobility.acrobat.up.jumps or 2
					else M.mobility.acrobat.jumps)
		then
			out.leap = "JUMP"
		end
	elseif pick == "swing" then
		out.fly = if mode == "swing" then "LET GO" elseif air then "SWING" else "ZIP"
		if mode == "swing" then
			out.leap = "ZIP" -- up the line and over the top
		end
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
	-- omnidirectional flight and glide (Config.Move.omni): face the camera's look (or the lock target) while
	-- hovering, strafing or backpedalling, lean into the move; a fast forward flight or boost faces its travel
	local lock = MoveController.lockAt
	if (mode == "fly" and not MoveController.boosting) or mode == "glide" then
		local lx, lz
		if lock and root then
			lx, lz = lock.X - root.Position.X, lock.Z - root.Position.Z
		end
		local fx, fz = MoveMath.omniFace(M, camFlat.X, camFlat.Z, vel.X, vel.Z, lx, lz)
		local want = math.atan2(-fx, -fz)
		local k = 1 - math.exp(-M.omni.face * dt)
		local fyaw = lastYaw + ((want - lastYaw + math.pi) % (2 * math.pi) - math.pi) * k
		lastYaw = fyaw
		local pitch, lean = MoveMath.omniLean(M, -math.sin(fyaw), -math.cos(fyaw), vel.X, vel.Z)
		if mode == "glide" then
			pitch = math.min(pitch, -35) -- the glide's spread pose stays tipped forward
		end
		roll += (lean - roll) * math.min(1, dt * 6)
		return CFrame.fromOrientation(0, fyaw, 0)
			* CFrame.Angles(0, 0, math.rad(roll))
			* CFrame.Angles(math.rad(pitch), 0, 0)
	end
	local tilt = 0
	if mode == "fly" or mode == "dash" then
		local p = if speed > 1 then math.deg(math.asin(math.clamp(vel.Y / speed, -1, 1))) else 0
		tilt = math.clamp(-(90 - p), -170, 0) * (fl.pitchMax / 90) * frac
	elseif mode == "glide" then
		tilt = -35
	elseif (mode == "wall" or mode == "climb" or mode == "bound") and wallNormal.Magnitude > 0 then
		-- face the wall while running or climbing up it (and hanging on it, the Hulk climb)
		return CFrame.lookAt(Vector3.zero, -wallNormal)
	elseif mode == "crawl" and crawlN.Magnitude > 0 then
		-- flat on the face: the front into it, the head along the crawl (up a wall; the camera's way on a ceiling)
		local up = crawlHead - crawlN * crawlHead:Dot(crawlN)
		if up.Magnitude < 1e-3 then
			up = if math.abs(crawlN.Y) < 0.9 then Vector3.yAxis - crawlN * crawlN.Y else Vector3.zAxis
		end
		up = up.Unit
		return CFrame.fromMatrix(Vector3.zero, up:Cross(crawlN), up, crawlN)
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
-- fix-destroy (2026-11-19, nate: "I want to fly straight through buildings"): glides and swoops ram too, plain flight
-- is fast enough (Config.Combat.impact.ram.minSpeed), the hole opens on this device at once (BuildingFx.predict via
-- ImpactFx, the server's pieces follow) and a street thing in the way (a tree, a fence, a lamp, a pole) is knocked
-- loose as you go through it (onPropHit, BuildingFx.smashStreet)
local RAM_MODES = { fly = true, dash = true, pound = true, ride = true, glide = true }
-- set by BuildingFx: knock the street things at `at` loose on this device; true when something went
MoveController.onPropHit = nil :: ((part: BasePart, at: Vector3, speed: number) -> boolean)?
-- set by onPropHit (destroy-all, 2026-11-20): a short hit-stop for a ram through a vehicle or a park structure
MoveController.propStop = 0
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
	-- the smash rule in the air (nate on the card, 2026-11-19 20:45Z): Super-speed holding Boost, or a Leaping hero
	-- whose leap meets the wall fast (ClimbMath.leapSmash, checked once the wall is found); a slower one climbs
	local pick = mobility()
	local airSmash = mode == "air"
		and ((pick == "speed" and InputController.isDown("Boost")) or pick == "leap")
	if speed < RAM.minSpeed or now < ramNext or not (RAM_MODES[mode] or airSmash) then
		return v
	end
	local hit = Workspace:Raycast(pos, v.Unit * (speed * dt + RAM.reach), rayParams)
	if not hit or v.Unit:Dot(-hit.Normal) < RAM.facing then
		return v
	end
	if
		mode == "air"
		and pick == "leap"
		and not ClimbMath.leapSmash(M, v.X, v.Z, hit.Normal.X, hit.Normal.Z)
	then
		return v -- too slow into it: the Hulk grab takes it (leapGrab)
	end
	local id = buildingOf(hit.Instance)
	if not id then
		-- a street thing in the way goes flying and the hero keeps nearly all its speed
		local onProp = MoveController.onPropHit
		if onProp and hit.Instance:IsA("BasePart") and onProp(hit.Instance, hit.Position, speed) then
			ramNext = now + RAM.cooldown * 0.5
			local stop = MoveController.propStop
			MoveController.propStop = 0
			if stop > 0 then
				ramHold = now + stop
				ramCarry = v * (1 - RAM.loss * 0.5)
				return v * RAM.holdKeep
			end
			return v * (1 - RAM.loss * 0.5)
		end
		return v
	end
	if id == ramLast.id and now - ramLast.at < RAM.sameWall then
		return v -- the same one again at once (a wall that held: no hit-stop every frame)
	end
	ramLast.id, ramLast.at = id, now
	ramNext = now + RAM.cooldown
	ramHold = now + RAM.hitStop
	ramCarry = v * (1 - RAM.loss)
	MoveController.Rammed:Fire(hit.Position, hit.Normal, speed, id)
	return v * RAM.holdKeep
end

-- The smash rule on the ground (Super-speed holding Boost): a building's wall ahead is rammed like a flight ram
-- (ImpactFx tells the server and opens the hole here at once; the run holds a short hit-stop and goes on through).
-- True when it rammed, or when this is the building it is going through right now (so no wall run starts in the
-- hole); false for anything that never breaks (the hero runs up it instead).
local function groundRam(hit: RaycastResult, speed: number, now: number): boolean
	local id = buildingOf(hit.Instance)
	if not id then
		-- destroy-all (2026-11-20): a car or a park structure in the run's way goes flying instead of being run up
		local onProp = MoveController.onPropHit
		if
			onProp
			and speed >= RAM.minSpeed
			and now >= ramNext
			and hit.Instance:IsA("BasePart")
			and onProp(hit.Instance, hit.Position, speed)
		then
			ramNext = now + RAM.cooldown * 0.5
			local stop = MoveController.propStop
			MoveController.propStop = 0
			ramHold = now + stop
			return true
		end
		return false
	end
	if id == ramLast.id and now - ramLast.at < RAM.sameWall * 2 then
		return true
	end
	if now < ramNext or speed < RAM.minSpeed then
		return now < ramNext
	end
	ramLast.id, ramLast.at = id, now
	ramNext = now + RAM.cooldown
	ramHold = now + RAM.hitStop
	MoveController.Rammed:Fire(hit.Position, hit.Normal, speed, id)
	return true
end

-- Would a ram go through this wall (a wreckable building's)? The smash rule's air check
local function smashable(hit: RaycastResult): boolean
	return buildingOf(hit.Instance) ~= nil
end

isSmashable = smashable

---------------------------------------------------------------------------
-- Leaping: the Hulk wall climb (nate's playtest 2026-11-19 20:42Z; Config.Move.mobility.leap.climb, ClimbMath)
---------------------------------------------------------------------------

MoveController.vaultUntil = 0 -- HeroAnimator shows the vault clip until then (the air mode after a climb's top)

-- Grab the wall: the hands dig in where `at` is (a crack and dust, MoveFx; the server's MoveGrab chips the
-- building), the body hangs on it
local function enterClimb(at: Vector3, normal: Vector3, now: number)
	local n = Vector3.new(normal.X, 0, normal.Z)
	if n.Magnitude < 1e-3 then
		return
	end
	wallNormal = n.Unit
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		enterAir(Vector3.zero)
	end
	vel = -wallNormal * M.mobility.leap.climb.press
	gripAt = now
	boundVy = 0
	setMode("climb")
	local hands = at + Vector3.new(0, 1.2, 0)
	MoveController.Grabbed:Fire(hands, wallNormal)
	if now - biteAt >= M.mobility.leap.climb.bite.every then
		biteAt = now
		Net.send("MoveGrab", hands)
	end
end

-- Up the face: a big vertical bound to the next grab
local function bound()
	boundVy = ClimbMath.boundUp(M)
	setMode("bound")
	if root then
		MoveController.Bounded:Fire(root.Position)
	end
end

-- Off the wall with momentum (the stick pulled away from it)
local function climbKick(flat: Vector3, now: number)
	local vx, vy, vz = ClimbMath.kick(M, wallNormal.X, wallNormal.Z, flat.X, flat.Z)
	vel = Vector3.new(vx, vy, vz)
	airSince = now
	wallLeft = now
	setMode("air")
	if root then
		MoveController.Leaped:Fire(root.Position)
	end
end

-- Over the top: the vault onto the roof
local function vault(now: number)
	local vx, vy, vz = ClimbMath.vault(M, wallNormal.X, wallNormal.Z)
	vel = Vector3.new(vx, vy, vz)
	airSince = now
	wallLeft = now
	MoveController.vaultUntil = now + M.mobility.leap.climb.vault.time
	setMode("air")
	if root then
		MoveController.Vaulted:Fire(root.Position)
	end
end

-- In the air (Leaping): a wall the hero moves or pushes into is grabbed, unless the leap is fast enough to smash
-- through it (the smash rule; the ram takes that one). Returns whether it grabbed.
local function leapGrab(flat: Vector3, now: number): boolean
	if mobility() ~= "leap" or held() or not root then
		return false
	end
	if now - wallLeft < M.wall.regrab then
		return false
	end
	local fv = Vector3.new(vel.X, 0, vel.Z)
	local dir = if flat.Magnitude > 0.3 then flat.Unit elseif fv.Magnitude > 1 then fv.Unit else nil
	if not dir then
		return false
	end
	local hit = wallAlong(dir, M.mobility.leap.climb.reach)
	if not hit then
		return false
	end
	local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	if n.Magnitude < 1e-3 then
		return false
	end
	n = n.Unit
	local into = -fv:Dot(n)
	local pushes = flat.Magnitude > 0.3 and flat.Unit:Dot(-n) > 0.5
	if into < 2 and not pushes then
		return false -- going past it, not into it
	end
	if ClimbMath.leapSmash(M, fv.X, fv.Z, n.X, n.Z) and smashable(hit) then
		return false -- the smash rule: straight through (ramStep)
	end
	enterClimb(hit.Position, n, now)
	return true
end

-- On the ground (Leaping): Leap at a wall right in front grabs it and bounds straight up (the Hulk climb)
local function groundClimb(): boolean
	if not root then
		return false
	end
	local flat = wishDirs()
	local lk = root.CFrame.LookVector
	local look = Vector3.new(lk.X, 0, lk.Z)
	local dir = if flat.Magnitude > 0.3 then flat.Unit elseif look.Magnitude > 1e-3 then look.Unit else nil
	local wall = dir and wallAlong(dir, M.mobility.leap.climb.reach + 0.5)
	if not wall then
		return false
	end
	local now = os.clock()
	lastLeap = now
	enterClimb(wall.Position, wall.Normal, now)
	if MoveController.mode == "climb" then
		bound()
	end
	return true
end

---------------------------------------------------------------------------
-- Acrobat: the wall crawl and the flip (Config.Move.mobility.acrobat, ClimbMath)
---------------------------------------------------------------------------

local crawlMove = Vector3.zero -- the crawl's way over the face last frame (unit, or zero when still)

enterCrawl = function(at: Vector3, normal: Vector3)
	if not root or normal.Magnitude < 1e-3 then
		return
	end
	local n = normal.Unit
	if ClimbMath.crawlKind(n.Y) == "floor" then
		return
	end
	crawlN = n
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		enterAir(Vector3.zero)
	end
	vel = Vector3.zero
	crawlMove = Vector3.zero
	local up = Vector3.yAxis - n * n.Y
	crawlHead = if up.Magnitude > 0.2
		then up.Unit
		else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	airJumps = 0
	setMode("crawl")
	MoveController.Crawled:Fire(at, n)
end

local function leaveCrawl(v: Vector3, now: number)
	vel = v
	airSince = now
	crawlAt = now
	wallLeft = now
	setMode("air")
end

-- Rising under a ceiling (Acrobat in the air): stick to it
local function ceilingGrab(now: number): boolean
	if mobility() ~= "acrobat" or held() or not root or now - crawlAt < 0.35 or vel.Y < -4 then
		return false
	end
	local hit =
		Workspace:Raycast(root.Position, Vector3.new(0, M.mobility.acrobat.ceilingReach + 1.5, 0), rayParams)
	if hit and ClimbMath.crawlKind(hit.Normal.Y) == "ceiling" then
		enterCrawl(hit.Position, hit.Normal)
		return true
	end
	return false
end

-- One frame on the face: follow it round outside and inside corners, stand up on a floor, fall off an end
local function crawlStep(dt: number, now: number)
	local r = root :: BasePart
	local pos = r.Position
	local a = M.mobility.acrobat
	local cam = Workspace.CurrentCamera.CFrame
	local mv = InputController.moveVector()
	-- the face under the hands
	local hit = Workspace:Raycast(pos, -crawlN * a.crawlReach, rayParams)
	local dist: number? = nil
	if hit then
		local n = hit.Normal
		if ClimbMath.crawlKind(n.Y) == "floor" then
			toGround(0) -- crawled down onto the street (or a floor)
			return
		end
		crawlN = crawlN:Lerp(n, math.min(1, dt * 20)).Unit
		dist = (pos - hit.Position):Dot(crawlN)
	elseif crawlMove.Magnitude > 0.1 then
		-- past an outside corner: the face round it (a roof at a wall's top: up onto it)
		local round = Workspace:Raycast(pos - crawlN * (a.crawlGap + 1.4), -crawlMove * 3, rayParams)
		if round and ClimbMath.crawlKind(round.Normal.Y) == "floor" then
			leaveCrawl(-crawlN * 12 + Vector3.new(0, 22, 0), now) -- over the top onto the roof
			return
		elseif round then
			crawlN = round.Normal.Unit
		else
			leaveCrawl(crawlN * 6, now)
			return
		end
	else
		leaveCrawl(crawlN * 6, now) -- the face is gone (a piece broke off)
		return
	end
	if held() then
		leaveCrawl(crawlN * 6, now)
		return
	end
	local fx, fy, fz, rx, ry, rz = ClimbMath.crawlBasis(
		crawlN.X,
		crawlN.Y,
		crawlN.Z,
		cam.LookVector.X,
		cam.LookVector.Y,
		cam.LookVector.Z,
		cam.RightVector.X,
		cam.RightVector.Y,
		cam.RightVector.Z
	)
	-- Boost scurries on stamina
	local burst = InputController.isDown("Boost") and MoveController.stamina > 0 and mv.Magnitude > 0.2
	if burst then
		MoveController.stamina = math.max(0, MoveController.stamina - a.crawlDrain * dt)
	else
		MoveController.stamina =
			MoveMath.staminaStep(M, MoveController.stamina, false, false, dt, os.clock() - drainAt)
	end
	local vx, vy, vz =
		ClimbMath.crawlVel(M, crawlN.X, crawlN.Y, crawlN.Z, fx, fy, fz, rx, ry, rz, mv.X, mv.Z, burst, dist)
	local along = Vector3.new(vx, vy, vz) - crawlN * Vector3.new(vx, vy, vz):Dot(crawlN)
	crawlMove = if along.Magnitude > 1 then along.Unit else Vector3.zero
	-- the head turns toward the crawl's way (kept when still), so it creeps round rather than snapping
	if crawlMove.Magnitude > 0 then
		local h = crawlHead:Lerp(crawlMove, math.min(1, dt * 6))
		crawlHead = if h.Magnitude > 1e-3 then h.Unit else crawlMove
	elseif (crawlHead - crawlN * crawlHead:Dot(crawlN)).Magnitude < 0.2 then
		crawlHead = Vector3.new(fx, fy, fz)
	end
	-- an inside corner ahead: take the face it meets (a floor: stand up on it)
	if crawlMove.Magnitude > 0 then
		local ahead = Workspace:Raycast(pos, crawlMove * 2.2, rayParams)
		if ahead and ahead.Normal:Dot(crawlN) < 0.8 then
			if ClimbMath.crawlKind(ahead.Normal.Y) == "floor" then
				toGround(0)
				return
			end
			crawlN = ahead.Normal.Unit
		end
	end
	vel = Vector3.new(vx, vy, vz)
end

-- The flip (Down): a quick flip along the stick that dodges for its i-frames (the server's own clock)
local function startFlip(now: number): boolean
	if not root then
		return false
	end
	local ok = ClimbMath.flipOk(M, flipAt, now)
	if not ok then
		return false
	end
	local flat = wishDirs()
	local look = root.CFrame.LookVector
	local vx, vy, vz = ClimbMath.flipVel(M, flat.X, flat.Z, -look.X, -look.Z)
	if MoveController.mode == "ground" or MoveController.mode == "charge" then
		enterAir(Vector3.zero)
	end
	vel = Vector3.new(vx, vy, vz)
	flipAt = now
	flipUntil = now + M.mobility.acrobat.flip.time
	airSince = now
	setMode("flip")
	Net.send("MoveFlip")
	MoveController.Flipped:Fire(root.Position)
	return true
end

-- Fast travel (TravelClient; gap polish 2026-11-19: the hero used to stand still under a camera sweep): the body
-- flies at(f) (f = 0..1 of `time` seconds, the server's arc eased on this device) in the flight pose, through
-- everything (TravelClient's collision group), with no input, landing check or ram. The server sets the hero
-- down at the end; endTravel then drops it out of the flight diving at `dive`, so it lands with the landing's
-- juice and pose. hold(): stop following (a skip, or the server put the body somewhere else).
-- upright (prologue-cine, 2026-11-20: the prologue's directed runs, vaults and hops): the body stays upright facing
-- its travel instead of the flight's tilt (HeroAnimator.cineMode poses the limbs)
function MoveController.travel(at: (number) -> Vector3, time: number, upright: boolean?)
	if not root or not hum or hum.Health <= 0 then
		return
	end
	if MoveController.mode == "swing" then
		dropLine()
	end
	enterAir(Vector3.zero)
	arc, ride = nil, nil
	MoveController.autoTarget = nil
	setBoost(false)
	trip = { at = at, start = os.clock(), time = math.max(0.1, time), hold = false, upright = upright }
	setMode("fly")
end

function MoveController.traveling(): boolean
	return trip ~= nil
end

function MoveController.holdTravel()
	if trip then
		trip.hold = true
	end
end

function MoveController.endTravel(dive: number)
	if not trip then
		return
	end
	trip = nil
	vel = Vector3.new(0, -math.abs(dive), 0)
	airSince = os.clock() - 1 -- the landing may come at once
	if root and hum and hum.Health > 0 then
		setMode("air")
	end
end

-- one frame of the flight: steer onto the arc point a frame ahead (a feed-forward with the error folded in,
-- capped so a teleport never flings the body back across the map)
local function travelStep(
	t0: {
		at: (number) -> Vector3,
		start: number,
		time: number,
		hold: boolean,
		upright: boolean?,
	},
	dt: number
)
	local r, v, o, h = root :: BasePart, lv :: LinearVelocity, ao :: AlignOrientation, hum :: Humanoid
	local now = os.clock()
	local f = math.clamp((now - t0.start) / t0.time, 0, 1)
	local pos = r.Position
	local here = t0.at(f)
	local ahead = t0.at(math.min(1, f + dt / t0.time))
	local pace = (ahead - here).Magnitude / math.max(dt, 1e-3)
	-- a frame hitch at full speed leaves the body behind by up to half a second of flight: it catches up; only a
	-- skip, a pull-back or a server move (much farther) holds it still for the landing
	if t0.hold or (here - pos).Magnitude > Config.Fx.polish.travel.hold + pace * 0.5 then
		t0.hold = true
		vel = vel * math.max(0, 1 - dt * 6)
	else
		local want = (ahead - pos) / math.max(dt, 1e-3)
		local cap = math.max(80, pace * 1.6)
		vel = if want.Magnitude > cap then want.Unit * cap else want
	end
	h.PlatformStand = true
	v.Enabled = true
	o.Enabled = true
	v.VectorVelocity = vel
	if t0.upright then
		local flat = Vector3.new(ahead.X - here.X, 0, ahead.Z - here.Z)
		if flat.Magnitude > 1e-3 then
			lastYaw = math.atan2(-flat.X, -flat.Z)
		end
		o.CFrame = CFrame.fromOrientation(0, lastYaw, 0)
	else
		o.CFrame = orientation("fly", dt)
	end
	MoveController.velocity = vel
end

local step: (number) -> ()

-- every frame: the move, then a note of any stamina drain (boost, wall runs, the scurry) for the regen delay
local function stepAll(dt: number)
	step(dt)
	local st = MoveController.stamina
	if st < lastStamina - 1e-6 then
		drainAt = os.clock()
	end
	lastStamina = st
end

step = function(dt: number)
	if not root or not hum or not lv or not ao or hum.Health <= 0 then
		return
	end
	dt = math.min(dt, 1 / 20)
	if trip then
		travelStep(trip, dt)
		return
	end
	local mode = MoveController.mode
	local pos = root.Position
	local onGround, groundY = grounded()
	local now = os.clock()
	swingPoseStep(mode, now)

	if mode == "ground" then
		setBoost(false)
		MoveController.stamina =
			MoveMath.staminaStep(M, MoveController.stamina, true, false, dt, os.clock() - drainAt)
		local pick = mobility()
		local flatWish = wishDirs()
		local moving = flatWish.Magnitude > 0.3 and not held() and not downed()
		-- everyone's sprint (nate 2026-11-19 20:46Z): Boost held (or the touch stick at its edge) eases the run up to
		-- Config.Move.sprint.speed; Super-speed has its own far faster sprint below
		if pick ~= "speed" then
			local on = moving
				and scaleNow() >= 1
				and ClimbMath.sprinting(
					M,
					InputController.isDown("Boost"),
					InputController.device == "touch",
					InputController.moveVector().Magnitude
				)
			local was = baseRun
			baseRun = ClimbMath.sprintStep(M, baseRun, on, dt)
			if baseRun ~= was then
				hum.WalkSpeed = runSpeed()
			end
		end
		if now < ramHold then
			hum.WalkSpeed = runSpeed() * RAM.holdKeep -- the ram's hit-stop on the ground
		elseif ramHold > 0 then
			ramHold = 0
			hum.WalkSpeed = runSpeed()
		end
		if pick == "speed" then
			-- Super-speed: hold Boost to build up to the sprint; let go and it bleeds off
			local boostHeld = InputController.isDown("Boost")
			sprint = MoveMath.sprintStep(M, sprint, moving and boostHeld, dt)
			if now >= ramHold then
				hum.WalkSpeed = runSpeed()
			end
			local m = M.mobility.speed
			local wall = if moving then wallAlong(flatWish, 3 + sprint * dt) else nil
			if wall and ClimbMath.speedSmash(M, boostHeld, sprint) and groundRam(wall, sprint, now) then
				-- the smash rule: Boost held, a building ahead: straight through it (the flight ram)
				MoveController.velocity = root.AssemblyLinearVelocity
				return
			end
			if wall and flatWish.Unit:Dot(-wall.Normal) >= 0.7 then
				-- no Boost (or nothing that breaks): run up it at any speed, while stamina lasts
				if MoveController.stamina > m.wallDrain * 0.5 then
					enterWall(wall.Normal, m.wallRun, m.wallDrain, "wall")
					return
				end
			end
			if moving and sprint >= m.waterRun then
				local surface = waterBelow(hum.HipHeight + root.Size.Y / 2 + 4)
				if surface then
					enterAir(flatWish * sprint)
					setMode("water")
					return
				end
			end
		elseif pick == "acrobat" and moving and now - crawlAt > 0.35 then
			-- walk into any wall: stick to it and crawl
			local wall = wallAlong(flatWish, 2.5)
			if wall and flatWish.Unit:Dot(-wall.Normal) >= 0.6 then
				enterCrawl(wall.Position, wall.Normal)
				return
			end
		end
		-- lock-on: the body turns to the target, so the stick strafes and backpedals round it
		local lock = MoveController.lockAt
		if lock and not held() and not downed() then
			hum.AutoRotate = false
			groundLocked = true
			local to = Vector3.new(lock.X - pos.X, 0, lock.Z - pos.Z)
			if to.Magnitude > 0.5 then
				local want = CFrame.lookAt(pos, pos + to.Unit)
				local k = 1 - math.exp(-M.omni.groundTurn * dt)
				root.CFrame = root.CFrame:Lerp(want, k)
			end
		elseif groundLocked then
			groundLocked = false
			hum.AutoRotate = true
		end
		-- underwater: the camera's pitch swims up and down too, Leap rises, Down sinks (Config.Move.omni)
		if hum:GetState() == Enum.HumanoidStateType.Swimming and not held() and not downed() then
			local _, full = wishDirs()
			local vertical = (if InputController.isDown("Leap") then 1 else 0)
				- (if InputController.isDown("Down") then 1 else 0)
			if math.abs(full.Y) > 0.05 or vertical ~= 0 then
				local v = root.AssemblyLinearVelocity
				local vy = MoveMath.swimVertical(M, full.Y, vertical, runSpeed())
				root.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
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
		elseif mobility() == "swing" and not canFly() then
			-- Swing: steer the fling without losing it, and holding Fly catches the next line once falling
			local sw = M.mobility.swing
			local sx, sz = MoveMath.airSteer(vel.X, vel.Z, flat.X, flat.Z, sw.steer, M.caps.glide * 0.5, dt)
			vel = Vector3.new(sx, vel.Y, sz)
			if
				InputController.isDown("Fly")
				and vel.Y < 0
				and now - releasedAt >= sw.rearm
				and now - missedAt >= 0.3
				and not held()
				and startSwing(false)
			then
				mode = MoveController.mode
			elseif InputController.isDown("Leap") and vel.Y <= 0 then
				setMode("glide")
			end
		elseif mobility() == "acrobat" then
			-- Acrobat: the best air control of any pick (never slows a jump, only turns and builds it)
			local A = M.mobility.acrobat.air
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
		MoveController.stamina =
			MoveMath.staminaStep(M, MoveController.stamina, false, false, dt, os.clock() - drainAt)
		-- Acrobat and Super-speed: jump at a wall to climb or run up it, or glance off one to run along it;
		-- Leaping: grab it (the Hulk climb); Acrobat: rise into a ceiling and stick to it
		if leapGrab(flat, now) or ceilingGrab(now) or airWallGrab(flat, now) then
			mode = MoveController.mode
		end
	elseif mode == "glide" then
		local gcfg = if mobility() == "acrobat" then ACRO_CFG else M
		vel = Vector3.new(MoveMath.glideStep(gcfg, vel.X, vel.Y, vel.Z, flat.X, flat.Z, dt, true))
		if not InputController.isDown("Leap") then
			setMode("air")
		end
		MoveController.stamina =
			MoveMath.staminaStep(M, MoveController.stamina, false, false, dt, os.clock() - drainAt)
		if leapGrab(flat, now) then -- a glide into a wall grabs it (Leaping)
			mode = MoveController.mode
		end
	elseif mode == "climb" then
		-- hanging on the wall (Leaping): Leap bounds up (held: again after the grip), Leap with the stick away kicks off
		local C = M.mobility.leap.climb
		vel = -wallNormal * C.press
		if not wallAlong(-wallNormal, C.reach + 0.6) or held() then
			jumpOff(0, 6) -- the piece it held broke off
		elseif InputController.isDown("Leap") and now - gripAt >= C.grip then
			if ClimbMath.pullsAway(flat.X, flat.Z, wallNormal.X, wallNormal.Z) then
				climbKick(flat, now)
			else
				bound()
			end
		end
		mode = MoveController.mode
	elseif mode == "bound" then
		-- a bound up the face: over the top it vaults onto the roof; at its height it grabs again
		local C = M.mobility.leap.climb
		local right = Vector3.new(-wallNormal.Z, 0, wallNormal.X)
		local side = if flat.Magnitude > 0.3 then flat:Dot(right) else 0
		local vx, vy, vz, topped = ClimbMath.boundStep(M, boundVy, wallNormal.X, wallNormal.Z, side, dt)
		boundVy = vy
		vel = Vector3.new(vx, vy, vz)
		local face = wallAlong(-wallNormal, C.reach + 0.8)
		local roof = Workspace:Raycast(pos, Vector3.new(0, 3.2, 0), rayParams)
		if held() then
			jumpOff(0, 6)
		elseif not face then
			vault(now) -- up past the top: onto the roof
		elseif topped or roof then
			enterClimb(face.Position, face.Normal, now) -- the next grab
		end
		mode = MoveController.mode
	elseif mode == "crawl" then
		crawlStep(dt, now)
		if MoveController.mode == "ground" then
			return -- stood up on a floor (toGround ran)
		end
		mode = MoveController.mode
	elseif mode == "flip" then
		vel = Vector3.new(MoveMath.airStep(M, vel.X, vel.Y, vel.Z, dt))
		if now >= flipUntil then
			setMode("air")
			mode = "air"
		end
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
				omni = true,
				forward = if full.Magnitude > 1e-3
					then full.Unit:Dot(Workspace.CurrentCamera.CFrame.LookVector)
					else 0,
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
		MoveController.stamina = MoveMath.staminaStep(
			M,
			MoveController.stamina,
			false,
			boosting and not free,
			dt,
			os.clock() - drainAt
		)
	elseif mode == "wall" then
		-- running (Super-speed) or climbing (Acrobat) up a wall
		local stillWall = wallAlong(-wallNormal, 3.2)
		MoveController.stamina = math.max(0, MoveController.stamina - wallDrain * dt)
		-- Super-speed keeps running up while Boost or Leap is held or the stick pushes into the wall (the smash
		-- rule: a wall run needs no Boost now), while stamina lasts
		local keepGoing = if mobility() == "speed"
			then (
				InputController.isDown("Boost")
				or InputController.isDown("Leap")
				or (flat.Magnitude > 0.3 and flat.Unit:Dot(-wallNormal) > 0.3)
			) and MoveController.stamina > 0
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
		local anchor = if swingAnchor then swingPivot else nil
		local part = swingPart
		local ahead = Vector3.new(vel.X, 0, vel.Z)
		local bump = if ahead.Magnitude > 5 then wallAlong(ahead, 3) else nil
		if bump then
			-- swung into a wall: let go and push off it, never stuck pressed against the building; the speed along
			-- the wall carries on (so the next line chains)
			dropLine()
			local n = Vector3.new(bump.Normal.X, 0, bump.Normal.Z)
			wallNormal = if n.Magnitude > 1e-3 then n.Unit else -ahead.Unit
			local along = ahead - wallNormal * ahead:Dot(wallNormal)
			jumpOff(M.mobility.swing.release.up, 15)
			vel += along * 0.8
			releasedAt = now
		elseif not anchor or (part and not part.Parent) or not InputController.isDown("Fly") or held() then
			-- let go (or the piece it hung from broke off): fling on with the swing's speed
			releaseSwing(now)
		else
			local sw = M.mobility.swing
			local nx, ny, nz, vx, vy, vz, len = SwingMath.step(
				swingCfg(),
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
				swingTarget,
				flat.X,
				flat.Z,
				dt
			)
			swingLen = len
			vel = Vector3.new(vx, vy, vz)
			-- the body goes to the rope's point (the physics step drifts off it); the swing keeps its own velocity
			local drive = (Vector3.new(nx, ny, nz) - pos) / math.max(dt, 1e-3)
			swingDrive = if drive.Magnitude > sw.cap then drive.Unit * sw.cap else drive
			MoveController.swingPose.phase =
				SwingMath.phase(pos.X, pos.Y, pos.Z, anchor.X, anchor.Y, anchor.Z, vel.Y)
			if SwingMath.atTop(M, pos.Y, anchor.Y, vel.Y) then
				-- swung up level with the anchor: let go at the top, flinging on
				swingDrive = nil
				releaseSwing(now)
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
			if zipping then
				-- the zip's point launch: on and up off the top (SwingMath.zipPop, inside the swing cap)
				zipping = false
				vel = Vector3.new(SwingMath.zipPop(M, zipDir.X, zipDir.Z))
				airSince = now
			end
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
		or mode == "climb"
		or mode == "bound"
		or mode == "crawl"
		or (mode == "flip" and vel.Y > 0)
		or mode == "wallrun"
		or mode == "water"
		or mode == "pound"
		or mode == "ride"
		or (mode == "swing" and vel.Y > 0)
	if onGround and now - airSince > 0.15 and not selfManaged then
		if mode == "swing" then
			dropLine()
		end
		local landing = (mode == "air" or mode == "glide" or mode == "swing" or mode == "flip") and vel.Y <= 0
			or (mode == "fly" and (vel.Y < -2 or InputController.isDown("Down")) and pos.Y - groundY < 4.5)
		local spring = if landing and (mode == "air" or mode == "glide") then awningUp(vel.Y) else nil
		if spring then
			-- an awning: spring back up, most of the run kept (no landing, so no drop smash either)
			vel = Vector3.new(vel.X * 0.9, spring, vel.Z * 0.9)
			airSince = now
			if mode == "glide" then
				setMode("air")
			end
			Net.send("CityBounce")
			MoveController.Bounced:Fire(pos, spring)
		elseif landing then
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
	lv.VectorVelocity = if swingDrive and MoveController.mode == "swing" then swingDrive else vel
	swingDrive = nil
	ao.CFrame = orientation(MoveController.mode, dt)
	MoveController.velocity = vel
end

local function onPressed(action: string)
	if not hum or hum.Health <= 0 or held() or downed() or trip then
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
		elseif mode == "ground" and pick == "leap" and groundClimb() then
			return -- a jump at a wall right in front: grabbed it and bounding up
		elseif mode == "ground" and MoveController.leapReady() >= 1 then
			chargeStart = os.clock()
			chargeRun = runFlat -- Leaping keeps some of the run in the leap
			hum.WalkSpeed = 6 -- the crouch
			setMode("charge")
		elseif mode == "swing" then
			if swingSky then
				releaseSwing(os.clock()) -- a sky line has nothing to zip up to: let go
			else
				zipLine() -- up the line and over the top
			end
		elseif mode == "crawl" then
			-- jump off the face (an air jump back), along the stick
			local flat = wishDirs()
			local vx, vy, vz = ClimbMath.crawlJump(M, crawlN.X, crawlN.Y, crawlN.Z, flat.X, flat.Z)
			airJumps = 0
			leaveCrawl(Vector3.new(vx, vy, vz), os.clock())
			if root then
				MoveController.Leaped:Fire(root.Position)
			end
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
			local most = if level() >= a.up.jumpsLevel then a.up.jumps or 2 else a.jumps
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
				startSwing(true)
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
		if mode == "climb" or mode == "bound" then
			jumpOff(0, 6) -- let go of the wall
			return
		elseif mode == "crawl" then
			leaveCrawl(crawlN * 8, os.clock()) -- let go of the face
			return
		elseif
			pick == "acrobat"
			and (mode == "ground" or mode == "air" or mode == "glide" or mode == "wallrun" or mode == "wall")
		then
			startFlip(os.clock()) -- the dodge
			return
		end
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
	trip = nil
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
	retune()
	State.Changed:Connect(retune)
	-- a drop onto a building from high up (nate, 2026-11-19 13:18Z; Config.Combat.drop): a landing this fast on a
	-- wreckable roof asks the server to smash it (ImpactService checks the fall against its own history)
	MoveController.Landed:Connect(function(pos: Vector3, fallSpeed: number)
		if fallSpeed < Config.Combat.drop.minFall or not root then
			return
		end
		rayParams.FilterDescendantsInstances = { player.Character :: Instance }
		local reach = (if hum then hum.HipHeight else 2) + root.Size.Y / 2 + 3
		local hit = Workspace:Raycast(pos, Vector3.new(0, -reach, 0), rayParams)
		if hit and buildingOf(hit.Instance) then
			Net.send("ImpactDrop", hit.Position, fallSpeed)
			MoveController.Dropped:Fire(hit.Position, fallSpeed)
		end
	end)
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
		if trip then
			trip.hold = true -- pulled back off a flight: wait there for the landing
		end
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
	RunService.PreSimulation:Connect(FrameProf.wrap("MoveController", stepAll))
end

return MoveController
