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
-- In the air modes the Humanoid is set to PlatformStand and a LinearVelocity plus AlignOrientation drive
-- the body; on landing the Humanoid takes over again.
-- M8: PvP crowd control on you (State.status.cc): stuns and roots stop movement and the leap and flight
-- buttons, slows cut speed, and a Downed hero (the Downed attribute) can only crawl. HeroKnock (a PvP
-- knockback, pull or knockup) plays as a short arc the server already allowed.
-- PLACEHOLDER ANIMATION: the flying pose is the body tilted along the travel direction; real leap, glide and
-- fly animations come with the animation pass (Tasks.md).

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
MoveController.velocity = Vector3.zero
MoveController.Leaped = Signal.new() -- (position)
MoveController.Landed = Signal.new() -- (position, fallSpeed)
MoveController.ModeChanged = Signal.new() -- (mode, old)
MoveController.BoostChanged = Signal.new() -- (on)

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
	return M.run.speed * (1 + bonus) * (1 + State.buff("speed")) * slowMult
end
MoveController.runSpeed = runSpeed

local function setMode(mode: string)
	local old = MoveController.mode
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

local function toGround(fallSpeed: number)
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
	root.AssemblyLinearVelocity = Vector3.new(vel.X * 0.3, 0, vel.Z * 0.3)
	hum:ChangeState(Enum.HumanoidStateType.Landed)
	vel = Vector3.zero
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

function MoveController.leapReady(): number
	local cd = M.leap.cooldown
	return math.clamp((os.clock() - lastLeap) / cd, 0, 1)
end

local function launch(frac: number)
	local flat = wishDirs()
	local vx, vy, vz = MoveMath.leapLaunch(M, flat.X, flat.Z, frac)
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
	end
	return CFrame.fromOrientation(0, yaw, 0)
		* CFrame.Angles(0, 0, math.rad(roll))
		* CFrame.Angles(math.rad(tilt), 0, 0)
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
		if now - chargeStart >= M.leap.charge then
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
		-- light air control so a leap can be nudged
		vel += flat * 30 * dt
		if InputController.isDown("Leap") and vel.Y <= 0 then
			setMode("glide")
		end
		MoveController.stamina = MoveMath.staminaStep(M, MoveController.stamina, false, false, dt)
	elseif mode == "glide" then
		vel = Vector3.new(MoveMath.glideStep(M, vel.X, vel.Y, vel.Z, flat.X, flat.Z, dt))
		if not InputController.isDown("Leap") then
			setMode("air")
		end
		MoveController.stamina = MoveMath.staminaStep(M, MoveController.stamina, false, false, dt)
	elseif mode == "fly" then
		local vertical = (if InputController.isDown("Leap") then 1 else 0)
			- (if InputController.isDown("Down") then 1 else 0)
		local wantBoost = InputController.isDown("Boost")
		if wantBoost and not MoveController.boosting and MoveController.stamina < M.stamina.boostMin then
			wantBoost = false
		end
		local vx, vy, vz, boosting =
			MoveMath.flightStep(M, vel.X, vel.Y, vel.Z, pos.Y, MoveController.stamina, {
				wishX = full.X,
				wishY = full.Y,
				wishZ = full.Z,
				vertical = vertical,
				boost = wantBoost,
			}, dt)
		vel = Vector3.new(vx, vy, vz)
		setBoost(boosting)
		local free = State.buff("zeroG") > 0 -- Weightless capstone: boosting is free
		MoveController.stamina =
			MoveMath.staminaStep(M, MoveController.stamina, false, boosting and not free, dt)
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
	if pos.Y > M.ceiling.hard and vel.Y > 0 then
		vel = Vector3.new(vel.X, 0, vel.Z)
	end

	-- landing
	if onGround and now - airSince > 0.15 and mode ~= "dash" then
		local landing = (mode == "air" or mode == "glide") and vel.Y <= 0
			or (mode == "fly" and (vel.Y < -2 or InputController.isDown("Down")) and pos.Y - groundY < 4.5)
		if landing then
			toGround(fallSpeed)
			return
		end
	end

	lv.VectorVelocity = vel
	ao.CFrame = orientation(MoveController.mode, dt)
	MoveController.velocity = vel
end

local function onPressed(action: string)
	if not hum or hum.Health <= 0 or held() or downed() then
		return
	end
	local mode = MoveController.mode
	if action == "Leap" then
		if mode == "ground" and MoveController.leapReady() >= 1 then
			chargeStart = os.clock()
			hum.WalkSpeed = 6 -- the crouch
			setMode("charge")
		end
	elseif action == "Fly" then
		if mode == "fly" then
			setBoost(false)
			setMode("air")
		elseif State.hero.styles and State.hero.styles.flight and mode ~= "dash" then
			if mode == "ground" or mode == "charge" then
				hum.WalkSpeed = runSpeed()
				enterAir(Vector3.new(0, 30, 0)) -- take-off hop
			else
				airSince = os.clock()
			end
			setMode("fly")
		end
	end
end

-- Tap-to-fly (spec: Map "Tap a marker to auto-fly"): take off and fly toward a spot; any stick push or
-- landing ends it. Needs flight; false otherwise.
MoveController.autoTarget = nil :: Vector3?
MoveController.Arrived = Signal.new() -- (target)
function MoveController.flyTo(target: Vector3): boolean
	if not (State.hero.styles and State.hero.styles.flight) or not hum or hum.Health <= 0 then
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
		launch(math.clamp((os.clock() - chargeStart) / M.leap.charge, 0, 1))
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
	setMode("ground");
	(hum :: Humanoid).Died:Connect(function()
		v.Enabled = false
		o.Enabled = false
		setBoost(false)
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
	end)
	Net.listen("MoveCorrect", function(pos: Vector3)
		if root then
			root.CFrame = CFrame.new(pos) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
			vel = Vector3.zero
			if MoveController.mode == "dash" then
				setMode(dashReturn)
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
		MoveController.arcTo(r.Position + flat, k.time or 0.35, math.max(2, move.Y))
	end)
	player:GetAttributeChangedSignal("Downed"):Connect(function()
		if hum and MoveController.mode == "ground" then
			hum.WalkSpeed = runSpeed()
		end
	end)
	RunService.PreSimulation:Connect(step)
end

return MoveController
