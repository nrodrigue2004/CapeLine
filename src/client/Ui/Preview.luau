-- Preview: a slowly turning copy of your own hero in a ViewportFrame, wearing any look (the creator, the
-- Robux shop's "a preview on the hero", the HQ mannequins). Built with LookKit, the same builder the server
-- uses, so what you see is what others see. Particles do not draw in a viewport, so auras show as a glow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
	-- turn the hero by this many radians (the creator's turn buttons); dragging the hero turns it too
	turn: (radians: number) -> (),
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
	-- nate's playtest (2026-11-18): "allow me to rotate character". Drag the hero (mouse or finger) to turn it,
	-- the wheel zooms; once turned by hand it stays where it was left (no auto spin) until the camera moves to
	-- another focus. Turn buttons call handle.turn.
	local manual = false
	local zoom = 1
	local dragging: InputObject? = nil
	local lastX = 0
	local conns: { RBXScriptConnection } = {}
	local DRAG = 0.012 -- radians per pixel
	table.insert(
		conns,
		RunService.RenderStepped:Connect(FrameProf.wrap("Preview", function(dt)
			if model and vp.Visible and model.PrimaryPart then
				-- turned by hand: it stays where the player left it
				if not manual and spin then
					yaw += dt * 0.6
				elseif not manual then
					-- ease back to facing the camera
					yaw = yaw - math.sin(yaw) * math.min(1, dt * 6)
				end
				model:PivotTo(CFrame.Angles(0, yaw, 0))
			end
		end))
	)
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end
	table.insert(
		conns,
		vp.InputBegan:Connect(function(input)
			if isPress(input) and not dragging then
				dragging = input
				lastX = input.Position.X
			end
		end)
	)
	table.insert(
		conns,
		UserInputService.InputChanged:Connect(function(input)
			local d = dragging
			if not d then
				return
			end
			local moved = (d.UserInputType == Enum.UserInputType.Touch and input == d)
				or (
					d.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseMovement
				)
			if moved then
				local dx = input.Position.X - lastX
				lastX = input.Position.X
				if math.abs(dx) > 0 then
					manual = true
					yaw += dx * DRAG
				end
			end
		end)
	)
	table.insert(
		conns,
		UserInputService.InputEnded:Connect(function(input)
			if dragging and (input == dragging or input.UserInputType == dragging.UserInputType) then
				dragging = nil
			end
		end)
	)
	local function aim(kind: string)
		local f = FOCUS[kind] or FOCUS.full
		local to = f[2]
		local from = to + (f[1] - to) * zoom
		cam.CFrame = CFrame.lookAt(from, to)
		spin = f[3]
	end
	local focusKind = "full"
	table.insert(
		conns,
		vp.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				zoom = math.clamp(zoom - input.Position.Z * 0.1, 0.55, 1.4)
				aim(focusKind)
			end
		end)
	)
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
					focusKind = "full"
					aim("full")
				end
			end
			if model then
				LookKit.strip(model)
				LookKit.build(model, look, weapon)
			end
		end,
		focus = function(kind: string)
			if kind ~= focusKind then
				-- a new camera spot: back to its own turn (auto spin on the full view)
				manual = false
				zoom = 1
				if kind ~= "full" then
					yaw = yaw % (2 * math.pi)
					if yaw > math.pi then
						yaw -= 2 * math.pi
					end
				end
			end
			focusKind = kind
			aim(kind)
		end,
		turn = function(radians: number)
			manual = true
			yaw += radians
		end,
		destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			vp:Destroy()
		end,
	}
	return handle
end

return Preview
