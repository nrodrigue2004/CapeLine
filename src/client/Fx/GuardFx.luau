-- GuardFx: the look of block, breaker and interrupt (spec: Hero MMO features > Block, breaker and interrupt;
-- H1). A blue shield disc in front of every hero holding Block (the Blocking attribute), a blue shine round
-- robots holding a timed block (GuardEvent rup / rdown), and the comic words BLOCKED, PERFECT!, SHATTER! and
-- CUT OFF! where they happen, each with its juice row (sound, flash, shake). PLACEHOLDER ART: plain neon
-- parts until the effects pass.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Juice = require(script.Parent.Juice)

local GuardFx = {}

local G = Config.Guard
local player = Players.LocalPlayer
local folder: Folder
local heroShields: { [Player]: BasePart } = {}
local robotShields: { [number]: { part: BasePart, untilT: number } } = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function newPart(shape: Enum.PartType, size: Vector3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.ForceField
	p.Color = rgb(G.shield.color)
	p.Transparency = G.shield.transparency
	p.Parent = folder
	return p
end

-- A comic word floating up from a spot (fixed words from Config.Guard.words)
local function pop(kind: string, pos: Vector3)
	local text = G.words[kind]
	if not text then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	local big = kind == "perfect" or kind == "shatter"
	gui.Size = UDim2.fromOffset(if big then 190 else 140, if big then 70 else 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 200
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.Bangers
	label.TextColor3 = rgb(G.colors[kind] or G.colors.block)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Rotation = (math.random() - 0.5) * 16
	label.Parent = gui
	gui.Parent = anchor
	TweenService:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)),
	}):Play()
	TweenService:Create(
		label,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	Debris:AddItem(anchor, 0.95)
end

-- A quick ring burst (the shatter's shards, the perfect block's flash)
local function burst(pos: Vector3, color: Color3, size: number)
	local p = newPart(Enum.PartType.Ball, Vector3.one * 1)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.2
	p.CFrame = CFrame.new(pos)
	TweenService:Create(p, TweenInfo.new(0.25), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(p, 0.3)
end

local function onEvent(ev: any)
	local pos = Vector3.new(ev.x, ev.y + 3, ev.z)
	local mine = ev.a == player.UserId
	if ev.k == "block" then
		pop("block", pos)
		Juice.fire("block", pos, { mine = mine })
	elseif ev.k == "perfect" then
		pop("perfect", pos)
		burst(pos, rgb(G.colors.perfect), 9)
		Juice.fire("perfectBlock", pos, { mine = mine })
		if mine then
			CameraController.punch(Config.Combat.punchHeavy)
		end
	elseif ev.k == "shatter" then
		pop("shatter", pos)
		burst(pos, rgb(G.colors.shatter), 11)
		Juice.fire("shatter", pos, { mine = mine })
		CameraController.shake(0.12, 0.35)
	elseif ev.k == "cut" then
		pop("cut", pos)
		burst(pos, rgb(G.colors.cut), 6)
		Juice.fire("interrupt", pos, { mine = mine })
	elseif ev.k == "rup" then
		local s = robotShields[ev.a]
		if not s then
			s = { part = newPart(Enum.PartType.Ball, Vector3.one * 9), untilT = 0 }
			robotShields[ev.a] = s
		end
		s.untilT = os.clock() + (ev.t or 2)
	elseif ev.k == "rdown" then
		local s = robotShields[ev.a]
		if s then
			s.part:Destroy()
			robotShields[ev.a] = nil
		end
	end
end

local function step()
	local now = os.clock()
	for id, s in robotShields do
		local pos = EnemyRenderer.position(id)
		if not pos or now > s.untilT then
			s.part:Destroy()
			robotShields[id] = nil
		else
			s.part.CFrame = CFrame.new(pos)
		end
	end
	for _, p in Players:GetPlayers() do
		local on = p:GetAttribute("Blocking") == true
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local shield = heroShields[p]
		if on and root then
			if not shield then
				local d = G.shield.size
				shield = newPart(Enum.PartType.Cylinder, Vector3.new(0.4, d, d))
				heroShields[p] = shield
			end
			-- a round shield held out in front of the chest
			local cf = root.CFrame * CFrame.new(0, 0.5, -2.2) * CFrame.Angles(0, math.rad(90), 0);
			(shield :: BasePart).CFrame = cf
		elseif shield then
			shield:Destroy()
			heroShields[p] = nil
		end
	end
end

function GuardFx.init()
	folder = Instance.new("Folder")
	folder.Name = "GuardFx"
	folder.Parent = Workspace
	Net.listen("GuardEvent", function(list)
		for _, ev in list do
			onEvent(ev)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local s = heroShields[p]
		if s then
			s:Destroy()
			heroShields[p] = nil
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("GuardFx", step))
end

return GuardFx
