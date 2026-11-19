-- MoveFx: movement juice (spec juice rows: Leap dust ring, Land thud with a crack for 30 s, Glide faint
-- trail, Boost trail in your color, speed lines at boost). Anime style adds speed lines at cruise too.
-- PLACEHOLDER ART: the crack is a dark flat disc until a decal is generated in the art pass.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local State = require(script.Parent.Parent.State)
local Juice = require(script.Parent.Juice)

local MoveFx = {}

local F = Config.Fx
local player = Players.LocalPlayer
local folder: Folder
local cracks: { BasePart } = {}
local trail: Trail? = nil
local lines: { Frame } = {}

local function ring(pos: Vector3, color: Color3, size: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = 0.3
	p.Size = Vector3.new(0.3, 2, 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = folder
	TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.5)
end

local function groundBelow(pos: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, folder }
	local hit = Workspace:Raycast(pos, Vector3.new(0, -8, 0), params)
	return hit and hit.Position
end

local function crack(pos: Vector3, size: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Slate
	p.Color = Color3.fromRGB(40, 40, 44)
	p.Transparency = 0.35
	p.Size = Vector3.new(0.1, size, size)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = folder
	table.insert(cracks, p)
	while #cracks > QualityController.preset.craters do
		local old = table.remove(cracks, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(F.crack.life, function()
		local i = table.find(cracks, p)
		if i then
			table.remove(cracks, i)
		end
		p:Destroy()
	end)
end

local function heroColor(): Color3
	local c = Config.Ui.colors.volt
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function attachTrail(char: Model)
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = root
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(heroColor())
	t.Transparency = NumberSequence.new(0.2, 1)
	t.Lifetime = F.trail.boostLife
	t.LightEmission = 0.8
	t.FaceCamera = true
	t.Enabled = false
	t.Parent = root
	trail = t
end

local function makeLines()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpeedLines"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -2
	for i = 1, 14 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		local ang = (i / 14) * math.pi * 2
		f.Position = UDim2.fromScale(0.5 + math.cos(ang) * 0.46, 0.5 + math.sin(ang) * 0.46)
		f.Size = UDim2.fromOffset(2, 90)
		f.Rotation = math.deg(ang) + 90
		f.Parent = gui
		table.insert(lines, f)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

function MoveFx.init()
	folder = Instance.new("Folder")
	folder.Name = "MoveFx"
	folder.Parent = Workspace
	makeLines()
	if player.Character then
		task.spawn(attachTrail, player.Character)
	end
	player.CharacterAdded:Connect(attachTrail)

	MoveController.Leaped:Connect(function(pos)
		Juice.fire("leap", pos)
		local g = groundBelow(pos)
		if g then
			ring(g + Vector3.new(0, 0.2, 0), Color3.fromRGB(200, 196, 186), 12)
		end
	end)
	MoveController.Landed:Connect(function(pos, fallSpeed)
		local g = groundBelow(pos + Vector3.new(0, 1, 0))
		if fallSpeed >= 30 then
			Juice.fire("land", pos, { mine = true })
		end
		if not g then
			return
		end
		ring(g + Vector3.new(0, 0.2, 0), Color3.fromRGB(200, 196, 186), math.clamp(fallSpeed / 3, 8, 26))
		if fallSpeed >= F.crack.minFall then
			crack(g, math.clamp(fallSpeed / 6, 5, 14))
		end
	end)

	local phase = 0
	local lastMode, wasBoosting = "", false
	local nextCharge, chargeFull = 0, false
	RunService.RenderStepped:Connect(FrameProf.wrap("MoveFx", function(dt)
		local mode = MoveController.mode
		-- hold to charge: rings at the feet grow as the Leap's crouch fills, a bright one when it is full
		if mode == "charge" then
			local now = os.clock()
			local frac = MoveController.chargeFraction()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local g = root and groundBelow(root.Position)
			if g and frac >= 1 and not chargeFull then
				chargeFull = true
				ring(g + Vector3.new(0, 0.2, 0), heroColor(), F.charge.full)
			elseif g and frac < 1 and now >= nextCharge then
				nextCharge = now + F.charge.every
				local s = F.charge.size
				ring(g + Vector3.new(0, 0.2, 0), Color3.fromRGB(255, 236, 170), s[1] + (s[2] - s[1]) * frac)
			end
		else
			chargeFull = false
		end
		local speed = MoveController.velocity.Magnitude
		local anime = State.hero.fxStyle == "Anime"
		-- sounds: a soft air on glide, a burst on boost, wind that rises with flight speed
		if mode == "glide" and lastMode ~= "glide" then
			Juice.fire("glide")
		end
		if MoveController.boosting and not wasBoosting then
			Juice.fire("boost", nil, { mine = true })
		end
		lastMode, wasBoosting = mode, MoveController.boosting
		Juice.hold("flyCruise", mode == "fly" or mode == "glide", math.clamp(speed / 220, 0.05, 0.5))
		if trail then
			trail.Enabled = MoveController.boosting or mode == "glide" or mode == "dash"
			trail.Lifetime = if mode == "glide" then 0.2 else F.trail.boostLife
		end
		local show = MoveController.boosting or (anime and mode == "fly" and speed > 45) or mode == "dash"
		phase += dt * 30
		for i, f in lines do
			local target = if show then 0.55 + 0.35 * math.abs(math.sin(phase + i * 1.7)) else 1
			f.BackgroundTransparency += (target - f.BackgroundTransparency) * math.min(1, dt * 10)
		end
	end))
end

return MoveFx
