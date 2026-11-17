-- CollectClient: collection finds on this device (spec: Hero MMO features > Collections; H7). The server sends
-- every find spot (CollectState) and picks them up; here, the ones you are missing sparkle with a soft chime
-- once you are within Config.Collect.sparkle studs, and with the HQ Scanner a marker over the nearest find
-- you are missing near you shows where to look. A pickup (CollectFound) pops the find's juice.
-- PLACEHOLDER ART: a glowing gem part with engine sparkles until the Blender pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollectPlan = require(Shared:WaitForChild("CollectPlan"))
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
	return p
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
end

return CollectClient
