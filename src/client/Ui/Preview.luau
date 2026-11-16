-- Preview: a slowly turning copy of your own hero in a ViewportFrame, wearing any look (the creator, the
-- Robux shop's "a preview on the hero", the HQ mannequins). Built with LookKit, the same builder the server
-- uses, so what you see is what others see. Particles do not draw in a viewport, so auras show as a glow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LookKit = require(Shared:WaitForChild("LookKit"))

local Preview = {}

export type Handle = {
	frame: ViewportFrame,
	set: (look: any, weapon: any?) -> (),
	-- the creator plan's camera per step: "full", "face" (eyes, makeup), "back" (capes, back bling), "weapon"
	focus: (kind: string) -> (),
	destroy: () -> (),
}

-- camera spots (from, to) per focus, the hero standing at the origin facing -z; spin: whether it turns
local FOCUS = {
	full = { Vector3.new(0, 1.2, -12), Vector3.new(0, 0.6, 0), true },
	face = { Vector3.new(0, 1.75, -4.6), Vector3.new(0, 1.65, 0), false },
	back = { Vector3.new(0, 1.4, 10), Vector3.new(0, 0.6, 0), false },
	weapon = { Vector3.new(-3.5, 1.0, -9), Vector3.new(0.5, 0.2, -1), false },
}

-- A still copy of your own hero (no scripts, sounds, gear look or name plate), root anchored
function Preview.clone(): Model?
	local char = Players.LocalPlayer.Character
	if not char then
		return nil
	end
	local was = char.Archivable
	char.Archivable = true
	local copy = char:Clone()
	char.Archivable = was
	if not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		if
			d:IsA("Script")
			or d:IsA("LocalScript")
			or d:IsA("ModuleScript")
			or d:IsA("Sound")
			or d:IsA("BillboardGui")
			or d:IsA("ProximityPrompt")
		then
			d:Destroy()
		end
	end
	local gear = copy:FindFirstChild("GearLook")
	if gear then
		gear:Destroy()
	end
	local hum = copy:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.PlatformStand = true
	end
	for _, p in copy:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = p.Name == "HumanoidRootPart"
		end
	end
	return copy
end

function Preview.new(parent: Instance, size: UDim2, position: UDim2): Handle
	local vp = Instance.new("ViewportFrame")
	vp.Name = "HeroPreview"
	vp.Size = size
	vp.Position = position
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 170, 185)
	vp.LightColor = Color3.fromRGB(255, 245, 230)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.6)
	vp.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 32
	cam.Parent = vp
	vp.CurrentCamera = cam
	local model: Model? = nil
	local yaw = 0
	local spin = true
	local conn = RunService.RenderStepped:Connect(FrameProf.wrap("Preview", function(dt)
		if model and vp.Visible and model.PrimaryPart then
			if spin then
				yaw += dt * 0.6
			else
				-- ease back to facing the camera
				yaw = yaw - math.sin(yaw) * math.min(1, dt * 6)
			end
			model:PivotTo(CFrame.Angles(0, yaw, 0))
		end
	end))
	local function aim(kind: string)
		local f = FOCUS[kind] or FOCUS.full
		cam.CFrame = CFrame.lookAt(f[1], f[2])
		spin = f[3]
	end
	local handle: Handle
	handle = {
		frame = vp,
		set = function(look: any, weapon: any?)
			if not model then
				model = Preview.clone()
				if model then
					model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
					model:PivotTo(CFrame.new())
					model.Parent = world
					aim("full")
				end
			end
			if model then
				LookKit.strip(model)
				LookKit.build(model, look, weapon)
			end
		end,
		focus = function(kind: string)
			aim(kind)
		end,
		destroy = function()
			conn:Disconnect()
			vp:Destroy()
		end,
	}
	return handle
end

return Preview
