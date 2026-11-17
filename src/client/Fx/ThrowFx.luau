-- ThrowFx: the look of pick up and throw (spec: Hero MMO features > Pick up and throw; H3). Flies every
-- thrown thing on the server's arc (ThrowFly: the same parabola on every screen, Shared.ThrowMath.arcPoint,
-- tumbling as it goes), with a dust ring, chips and a crash where it lands (a shake for heavy ones near you),
-- a puff when someone lifts something (the Carrying attribute) and when a prop comes home (ThrowBack).
-- PLACEHOLDER ART: plain parts for the dust and chips until the effects pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Net = require(Shared:WaitForChild("Net"))
local ThrowMath = require(Shared:WaitForChild("ThrowMath"))

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Juice = require(script.Parent.Juice)

local ThrowFx = {}

local T = Config.Throw
local player = Players.LocalPlayer
local DUST = Color3.fromRGB(196, 186, 170)
local flights: { [number]: any } = {}
local carrying: { [Player]: string? } = {}
local fxFolder: Folder

-- The model for an item id: a prop in Workspace.Throwables, or a vehicle tagged with ThrowId
function ThrowFx.model(id: number): Model?
	for _, root in { Workspace:FindFirstChild("Throwables"), Workspace:FindFirstChild("City") } do
		if root then
			local holder = if root.Name == "City" then root:FindFirstChild("Vehicles") else root
			for _, m in (if holder then holder:GetChildren() else {}) do
				if m:GetAttribute("ThrowId") == id then
					return m :: Model
				end
			end
		end
	end
	return nil
end

local function chip(at: Vector3, color: Color3, size: number, life: number, grow: number?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = Vector3.one * size
	p.CFrame = CFrame.new(at)
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(life), {
		Transparency = 1,
		Size = Vector3.one * size * (grow or 1),
		CFrame = CFrame.new(at + Vector3.new((math.random() - 0.5) * 4, size, (math.random() - 0.5) * 4)),
	}):Play()
	task.delay(life, function()
		p:Destroy()
	end)
end

local function dust(at: Vector3, radius: number, n: number)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = DUST
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = fxFolder
	TweenService
		:Create(
			ring,
			TweenInfo.new(0.45),
			{ Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1 }
		)
		:Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
	for _ = 1, n do
		chip(
			at + Vector3.new((math.random() - 0.5) * radius, 0.5, (math.random() - 0.5) * radius),
			DUST,
			1.2,
			0.6,
			2
		)
	end
end

-- Juice rows (Config.Audio.juice): the visual for grab and throwLand
function ThrowFx.grab(at: Vector3)
	dust(at - Vector3.new(0, 2.5, 0), 4, 3)
end

function ThrowFx.throwLand(at: Vector3, weight: string, mine: boolean)
	local W = T.weights[weight] or T.weights.light
	dust(at, W.radius, if weight == "heavy" then 8 else 4)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if weight ~= "light" and root and (root.Position - at).Magnitude < 60 then
		CameraController.shake(
			if weight == "heavy" then 0.25 else 0.12,
			if weight == "heavy" then 0.6 else 0.3
		)
	end
	Juice.fire("throwLand", at, { mine = mine })
end

local function weightOf(m: Model): string
	local kind = m:GetAttribute("ThrowKind")
	return (type(kind) == "string" and ThrowMath.weight(T, kind)) or "light"
end

local function step()
	local now = os.clock()
	for id, f in flights do
		local t = math.clamp((now - f.t0) / f.time, 0, 1)
		local x, y, z = ThrowMath.arcPoint(f.from.X, f.from.Y, f.from.Z, f.to.X, f.to.Y, f.to.Z, f.peak, t)
		if f.model.Parent then
			-- tumble end over end along the flight
			f.model:PivotTo(CFrame.new(x, y, z) * f.turn * CFrame.Angles(t * f.spin, 0, t * f.spin * 0.4))
		end
		if t >= 1 then
			flights[id] = nil
			if f.hit then
				ThrowFx.throwLand(f.to, weightOf(f.model), f.mine)
			end
		end
	end
	-- someone lifted something: a puff at their feet
	for _, p in Players:GetPlayers() do
		local kind = p:GetAttribute("Carrying")
		if kind ~= carrying[p] then
			carrying[p] = kind
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if kind and root then
				ThrowFx.grab(root.Position)
				Juice.fire("grab", root.Position, { mine = p == player })
			end
		end
	end
end

function ThrowFx.init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ThrowFx"
	fxFolder.Parent = Workspace
	Net.listen(
		"ThrowFly",
		function(id: number, from: Vector3, to: Vector3, time: number, peak: number, by: number)
			local m = ThrowFx.model(id)
			if not m or typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or type(time) ~= "number" then
				return
			end
			local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
			flights[id] = {
				model = m,
				from = from,
				to = to,
				time = math.max(0.05, time),
				peak = peak or 0,
				t0 = os.clock(),
				turn = if flat.Magnitude > 0.1 then CFrame.lookAt(Vector3.zero, flat) else CFrame.identity,
				spin = if weightOf(m) == "heavy" then math.pi else math.pi * 3,
				mine = by == player.UserId,
				hit = by ~= 0, -- props knocked aside by a landing just tip over, no crash of their own
			}
		end
	)
	Net.listen("ThrowBack", function(id: number)
		local m = ThrowFx.model(id)
		if m then
			chip(m:GetPivot().Position, Color3.fromRGB(200, 240, 255), 3, 0.4, 2)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		carrying[p] = nil
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("ThrowFx", step))
end

return ThrowFx
