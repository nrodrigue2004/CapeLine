-- CameraController: keeps the default Roblox follow camera (players already know it, on every device) and
-- adds the juice: FOV widens 6% on a leap and stretches at boost, short shakes on landing, hits and supers
-- (spec: juice table). Shake and FOV punches are off in reduce-flashing mode.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local MoveController = require(script.Parent.MoveController)
local InputController = require(script.Parent.InputController)

local CameraController = {}
CameraController.reduceMotion = false

local F = Config.Fx.fov
local shakeTime, shakeLeft, shakeAmount = 0, 0, 0
local fovKick = 0

function CameraController.shake(time: number, amount: number)
	if CameraController.reduceMotion then
		return
	end
	if amount >= shakeAmount * (shakeLeft / math.max(shakeTime, 1e-3)) then
		shakeTime, shakeLeft, shakeAmount = time, time, amount
	end
end

-- A quick FOV push (camera push 8% on clash moments; small on supers)
function CameraController.punch(amount: number)
	if not CameraController.reduceMotion then
		fovKick = math.max(fovKick, amount)
	end
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
			if math.abs(rate) < 0.08 then
				return
			end
			local cam = Workspace.CurrentCamera
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return
			end
			local pivot = root.Position
			local yaw = -rate * 2.2 * dt -- about 125 degrees a second at full push
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
			leapGlow = math.max(0, leapGlow - dt)
			fovKick = math.max(0, fovKick - dt * 0.6)
			local want = target * (1 + fovKick)
			cam.FieldOfView += (want - cam.FieldOfView) * math.min(1, dt * F.blend)
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
