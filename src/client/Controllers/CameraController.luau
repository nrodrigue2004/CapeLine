-- CameraController: keeps the default Roblox follow camera (players already know it, on every device) and
-- adds the juice: FOV widens 6% on a leap and stretches at boost, short shakes on landing, hits and supers
-- (spec: juice table). Shake and FOV punches are off in reduce-flashing mode.
-- The dynamic camera (nate's lore, build plan step 7, K3; Config.Cinema.camera): a slight lean into dashes, a
-- gentle push in on heavy hits and finishers, a small orbit round the hero on supers. On by default; Settings
-- "Camera motion" scales it (CinemaPlan.motion: Full, Reduced halves, Off removes, shakes and punches too);
-- Reduce flashing still removes flashes and shakes. No new tables per frame: the motion scales live in one
-- table refreshed only when a setting changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CinemaPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CinemaPlan"))

local MoveController = require(script.Parent.MoveController)
local InputController = require(script.Parent.InputController)

local CameraController = {}
-- (first-30 polish, 2026-11-20) a cutscene owns the field of view: CinemaClient sets this while its camera plays,
-- so the gameplay FOV (the leap and boost widening) never pumps the zoom mid-shot; kicks and pushes still land
CameraController.fovOverride = nil :: number?
CameraController.reduceMotion = false -- Settings: Reduce flashing (no shakes, punches or hit-pause)
CameraController.motionOption = 0 -- Settings: Camera motion (0 Full, 1 Reduced, 2 Off)
CameraController.motion = CinemaPlan.motion(Config, 0, false) -- the scales in use (CinemaPlan.Motion)

local F = Config.Fx.fov
local CC = Config.Cinema.camera
local shakeTime, shakeLeft, shakeAmount = 0, 0, 0
local fovKick = 0
local pushKick = 0
local lean, leanWant, leanUntil = 0, 0, 0
local orbitTotal, orbitLeft = 0, 0
-- the Swing's speed feel (2026-11-19, Config.Move.mobility.swing.feel): FOV wider and the camera pulled back with
-- the swing's speed, both scaled by Camera motion (Off: none)
local SWING = Config.Move.mobility.swing.feel
local swingPull = 0
-- the blend back from a cutscene's last shot to the follow camera (CameraController.blendFrom)
local blendCf: CFrame? = nil
local blendTime, blendLeft = 0, 0
local pullParams = RaycastParams.new()
pullParams.FilterType = Enum.RaycastFilterType.Exclude

-- Settings changed: Camera motion's option and Reduce flashing (the scales are kept in one table)
function CameraController.setMotion(option: number?, reduceFlashing: boolean?)
	if option ~= nil then
		CameraController.motionOption = option
	end
	if reduceFlashing ~= nil then
		CameraController.reduceMotion = reduceFlashing
	end
	CinemaPlan.motion(
		Config,
		CameraController.motionOption,
		CameraController.reduceMotion,
		CameraController.motion
	)
end

function CameraController.shake(time: number, amount: number)
	local scale = CameraController.motion.shake
	if CameraController.reduceMotion or scale <= 0 then
		return
	end
	amount *= scale
	if amount >= shakeAmount * (shakeLeft / math.max(shakeTime, 1e-3)) then
		shakeTime, shakeLeft, shakeAmount = time, time, amount
	end
end

-- A quick FOV push (camera push 8% on clash moments; small on supers)
function CameraController.punch(amount: number)
	if not CameraController.reduceMotion then
		fovKick = math.max(fovKick, amount * CameraController.motion.push)
	end
end

-- A gentle push in (the FOV narrows a little, then eases back): heavy hits and finishers. scaled: the amount
-- already carries the Camera motion scale (a finisher's plan)
function CameraController.push(amount: number?, scaled: boolean?)
	local a = (amount or CC.push.heavy) * (if scaled then 1 else CameraController.motion.push)
	if a > pushKick then
		pushKick = a
	end
end

-- A slight lean (roll) into a dash: dir is the dash's way in the world
function CameraController.lean(dir: Vector3)
	local cam = Workspace.CurrentCamera
	local m = CameraController.motion.lean
	if not cam or m <= 0 then
		return
	end
	leanWant = -dir:Dot(cam.CFrame.RightVector) * CC.lean.max * m
	leanUntil = os.clock() + 0.25
end

-- A small orbit round the hero on a super (the swing keeps going the way it started; the player still steers)
function CameraController.orbit(sign: number?)
	local m = CameraController.motion.orbit
	if m <= 0 or orbitLeft > 0 then
		return
	end
	orbitTotal = CC.orbit.super * m * (if (sign or 1) < 0 then -1 else 1)
	orbitLeft = CC.orbit.time
end

-- A cutscene ended (CinemaClient): ease the camera from its last shot to the follow camera over `seconds`
-- instead of snapping behind the hero (first-30 polish: nate found the cutscenes' ends jumpy)
function CameraController.blendFrom(cf: CFrame, seconds: number)
	if seconds <= 0 then
		return
	end
	blendCf, blendTime, blendLeft = cf, seconds, seconds
end

function CameraController.init()
	local player = Players.LocalPlayer
	player.CameraMaxZoomDistance = 60
	player.CameraMinZoomDistance = 6
	local leapGlow = 0
	MoveController.Leaped:Connect(function()
		leapGlow = 0.6
	end)
	MoveController.Landed:Connect(function(_, fallSpeed: number)
		local ls = Config.Fx.landShake
		if fallSpeed >= ls.minFall then
			CameraController.shake(ls.time, ls.amount * math.clamp(fallSpeed / 60, 0.5, 2))
		end
	end)
	-- one-hand flight's auto-turn: the stick's sideways push swings the camera (and so the flight path)
	-- around the hero before the default camera runs
	RunService:BindToRenderStep(
		"CapelineAutoTurn",
		Enum.RenderPriority.Camera.Value - 1,
		FrameProf.wrap("CameraController", function(dt)
			local rate = InputController.turnRate()
			local yaw = 0
			if math.abs(rate) >= 0.08 then
				yaw = -rate * 2.2 * dt -- about 125 degrees a second at full push
			end
			-- a super's small orbit: an eased swing of orbitTotal over CC.orbit.time
			if orbitLeft > 0 then
				local T = CC.orbit.time
				local k0 = 1 - orbitLeft / T
				orbitLeft = math.max(0, orbitLeft - dt)
				local k1 = 1 - orbitLeft / T
				yaw += orbitTotal * (CinemaPlan.ease(k1) - CinemaPlan.ease(k0))
			end
			if yaw == 0 then
				return
			end
			local cam = Workspace.CurrentCamera
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or cam.CameraType == Enum.CameraType.Scriptable then
				return
			end
			local pivot = root.Position
			cam.CFrame = CFrame.new(pivot) * CFrame.Angles(0, yaw, 0) * CFrame.new(-pivot) * cam.CFrame
		end)
	)
	RunService:BindToRenderStep(
		"CapelineCamera",
		Enum.RenderPriority.Camera.Value + 1,
		FrameProf.wrap("CameraController", function(dt)
			local cam = Workspace.CurrentCamera
			local target = F.base
			local mode = MoveController.mode
			if MoveController.boosting then
				target = F.base * F.boost
			elseif mode == "air" or mode == "glide" or leapGlow > 0 then
				target = F.base * F.leap
			elseif mode == "fly" then
				local s = MoveController.velocity.Magnitude
				target = F.base * (1 + (F.leap - 1) * math.clamp(s / Config.Move.flight.cruise, 0, 1))
			end
			local sp = MoveController.swingPose
			local swingK = if sp.state ~= "none"
				then math.clamp(sp.speed, 0, 1) * CameraController.motion.push
				else 0
			if swingK > 0 then
				target = math.max(target, F.base * (1 + SWING.fov * swingK))
			end
			leapGlow = math.max(0, leapGlow - dt)
			fovKick = math.max(0, fovKick - dt * 0.6)
			pushKick = math.max(0, pushKick - dt * (CC.push.heavy / CC.push.time))
			local scripted = cam.CameraType == Enum.CameraType.Scriptable
			local over = CameraController.fovOverride
			if over then
				-- a cutscene's own FOV (the kicks and pushes still land on it)
				local want = over * (1 + fovKick - pushKick)
				cam.FieldOfView += (want - cam.FieldOfView) * math.min(1, dt * F.blend * 2)
			elseif not scripted then
				-- (a Scriptable camera that is no cutscene, the HQ's or a preview's, keeps the FOV it set)
				local want = target * (1 + fovKick - pushKick)
				cam.FieldOfView += (want - cam.FieldOfView) * math.min(1, dt * F.blend)
			end
			-- the blend back from a cutscene's last shot: eased in from where the shot left the camera
			if blendLeft > 0 and blendCf then
				if scripted then
					blendLeft = 0
				else
					blendLeft = math.max(0, blendLeft - dt)
					local k = CinemaPlan.ease(1 - blendLeft / blendTime)
					cam.CFrame = (blendCf :: CFrame):Lerp(cam.CFrame, k)
				end
			end
			-- the dash lean: rolls in fast, settles back slower (not while a cutscene owns the camera)
			local wantLean = if os.clock() < leanUntil then leanWant else 0
			local rate = if math.abs(wantLean) > math.abs(lean) then CC.lean.rise else CC.lean.fall
			lean += (wantLean - lean) * math.min(1, dt * rate)
			if math.abs(lean) > 1e-4 and cam.CameraType ~= Enum.CameraType.Scriptable then
				cam.CFrame *= CFrame.Angles(0, 0, lean)
			end
			-- the swing's pull-back: eased, and never through a wall behind the camera
			swingPull += (SWING.pull * swingK - swingPull) * math.min(1, dt * 3)
			if swingPull > 0.05 and cam.CameraType ~= Enum.CameraType.Scriptable then
				local back = -cam.CFrame.LookVector * swingPull
				pullParams.FilterDescendantsInstances = { player.Character :: Instance }
				local hit = Workspace:Raycast(cam.CFrame.Position, back * 1.2, pullParams)
				local k = if hit then math.max(0, (hit.Distance / 1.2 - 0.5) / swingPull) else 1
				cam.CFrame += back * math.min(1, k)
			end
			if shakeLeft > 0 then
				shakeLeft -= dt
				local k = shakeAmount * math.max(0, shakeLeft / shakeTime)
				local rx, ry = (math.random() - 0.5) * k, (math.random() - 0.5) * k
				cam.CFrame *= CFrame.new(rx, ry, 0) * CFrame.Angles(ry * 0.02, rx * 0.02, 0)
			end
		end)
	)
end

return CameraController
