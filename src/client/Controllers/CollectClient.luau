-- CollectClient: collection finds on this device (spec: Hero MMO features > Collections; H7). The server sends
-- every find spot (CollectState) and picks them up; here, the ones you are missing sparkle with a soft chime
-- once you are within Config.Collect.sparkle studs, and with the HQ Scanner a marker over the nearest find
-- you are missing near you shows where to look. A pickup (CollectFound) pops the find's juice.
-- A find is its set's Blender figure (art/blender/finds.py, ReplicatedStorage.Art.Finds, Config.FindArt: a comic book,
-- a tin rocket, a ship's bell, a diving helmet, a pigeon, the Star Charm) bobbing and turning over a soft glow, with
-- the set's sparkles and light (Everything Left 335). PLACEHOLDER ART: a set whose meshes are not imported keeps the
-- glowing ball.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollectPlan = require(Shared:WaitForChild("CollectPlan"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local Net = require(Shared:WaitForChild("Net"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local AudioController = require(script.Parent.AudioController)

local CollectClient = {}

local C = Config.Collect
local SCAN_RANGE = 600 -- studs: the scanner marks the nearest missing find this close
local player = Players.LocalPlayer
local spots: { { bit: number, x: number, y: number, z: number } } = {}
local found: { [number]: boolean } = {}
local scanner = false
local shown: { [number]: BasePart } = {}
-- the figures in the world: their glow part (the anchor that carries the sparkles) and their meshes, posed from it
local figures: { [BasePart]: { home: CFrame, phase: number, meshes: { { part: BasePart, at: CFrame } } } } =
	{}
local ART = Config.FindArt
local BOB, SPIN = 0.35, 1.2 -- studs up and down, turns a second (radians)
local folder: Folder? = nil
local marker: BasePart? = nil

local COLORS = {
	ComicCovers = Color3.fromRGB(255, 90, 90),
	LostToys = Color3.fromRGB(255, 190, 80),
	ShipBells = Color3.fromRGB(230, 200, 90),
	DeepRelics = Color3.fromRGB(90, 230, 210),
	RoofPigeons = Color3.fromRGB(200, 200, 230),
	CometShards = Color3.fromRGB(150, 140, 255),
}

local function root(): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function holder(): Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "CollectFinds"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

local function gem(s: { bit: number, x: number, y: number, z: number }): BasePart
	local set = CollectPlan.setOfBit(C, s.bit)
	local color = set and COLORS[set.id] or Color3.fromRGB(255, 230, 120)
	local p = Instance.new("Part")
	p.Name = "Find" .. s.bit
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(1.6, 1.6, 1.6)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.CFrame = CFrame.new(s.x, s.y, s.z)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 6
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.35, 0)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Parent = p
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = p
	p.Parent = holder()
	-- the set's own figure: the glow shrinks to a soft halo under it
	local fit = set and ART[set.id]
	local lib = ReplicatedStorage:FindFirstChild("Art")
	lib = lib and lib:FindFirstChild("Finds")
	if fit and lib then
		local meshes: { { src: MeshPart, row: any } } = {}
		local ready = true
		for name, row in fit do
			local src = lib:FindFirstChild(name, true)
			if not (src and src:IsA("MeshPart")) then
				ready = false
				break
			end
			table.insert(meshes, { src = src :: MeshPart, row = row })
		end
		if ready then
			local fig = { home = p.CFrame, phase = s.bit * 0.7, meshes = {} }
			for _, m in meshes do
				local row = m.row
				local mp = MeshFix.clone(m.src)
				for _, c in mp:GetChildren() do
					c:Destroy()
				end
				mp.Name = m.src.Name
				mp.Anchored = true
				mp.CanCollide = false
				mp.CanQuery = false
				mp.CanTouch = false
				mp.CastShadow = false
				mp.Size = Vector3.new(row.size[1], row.size[2], row.size[3])
				mp.Color = Color3.fromRGB(row.color[1], row.color[2], row.color[3])
				local ok, mat = pcall(function()
					return (Enum.Material :: any)[row.mat]
				end)
				mp.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
				local at = CFrame.new(row.offset[1], row.offset[2], row.offset[3]) * MeshFix.turn("Finds")
				mp.CFrame = p.CFrame * at
				mp.Parent = p
				table.insert(fig.meshes, { part = mp, at = at })
			end
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.15, 2.6, 2.6)
			p.CFrame = CFrame.new(s.x, s.y - 1.1, s.z) * CFrame.Angles(0, 0, math.rad(90))
			p.Transparency = 0.55
			figures[p] = fig
		end
	end
	return p
end

-- the figures bob and turn (only the few near you exist)
local function animate()
	if next(figures) == nil then
		return
	end
	local t = os.clock()
	for glow, fig in figures do
		if not glow.Parent then
			figures[glow] = nil
			continue
		end
		local pose = fig.home
			* CFrame.new(0, math.sin(t * 2 + fig.phase) * BOB, 0)
			* CFrame.Angles(0, t * SPIN + fig.phase, 0)
		for _, m in fig.meshes do
			m.part.CFrame = pose * m.at
		end
	end
end

local function makeMarker(): BasePart
	local anchor = Instance.new("Part")
	anchor.Name = "ScannerMarker"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = holder()
	local bb = Instance.new("BillboardGui")
	bb.Name = "ScannerMarker"
	bb.Size = UDim2.fromOffset(120, 40)
	bb.AlwaysOnTop = true
	bb.MaxDistance = SCAN_RANGE + 50
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Bangers
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 230, 120)
	l.TextStrokeTransparency = 0.3
	l.Text = "▼ FIND"
	l.Parent = bb
	bb.Parent = anchor
	return anchor
end

local function step()
	local r = root()
	if not r then
		return
	end
	local pos = r.Position
	local s2 = C.sparkle * C.sparkle
	local best, bestD = nil, SCAN_RANGE * SCAN_RANGE
	for _, s in spots do
		local d = (s.x - pos.X) ^ 2 + (s.z - pos.Z) ^ 2
		local missing = not found[s.bit]
		if missing and d <= s2 then
			if not shown[s.bit] then
				shown[s.bit] = gem(s)
				AudioController.play("collectNear", Vector3.new(s.x, s.y, s.z))
			end
		elseif shown[s.bit] then
			shown[s.bit]:Destroy()
			shown[s.bit] = nil
		end
		if missing and d < bestD then
			best, bestD = s, d
		end
	end
	if scanner and best then
		local m = marker or makeMarker()
		marker = m
		m.CFrame = CFrame.new(best.x, best.y + 6, best.z)
		local bb = m:FindFirstChildOfClass("BillboardGui")
		if bb then
			bb.Enabled = true
		end
	elseif marker then
		local bb = marker:FindFirstChildOfClass("BillboardGui")
		if bb then
			bb.Enabled = false
		end
	end
end

-- one look round for finds near you (the init loop runs it 4 times a second; tests call it directly)
CollectClient.step = step

function CollectClient.hasScanner(): boolean
	return scanner
end

function CollectClient.init()
	Net.listen("CollectState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		spots = {}
		for _, row in d.spots or {} do
			table.insert(spots, { bit = row[1], x = row[2], y = row[3], z = row[4] })
		end
		found = {}
		for _, b in d.found or {} do
			found[b] = true
		end
		scanner = d.scanner == true
	end)
	Net.listen("CollectFound", function(d: any)
		if type(d) ~= "table" then
			return
		end
		found[d.bit] = true
		local p = shown[d.bit]
		local at = p and p.Position
		if p then
			p:Destroy()
			shown[d.bit] = nil
		end
		Juice.fire("collectFind", at, { name = d.set, found = d.found, count = d.count, mine = true })
	end)
	task.defer(function()
		Net.send("CollectOpen")
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			step()
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("CollectFinds", animate))
end

return CollectClient
