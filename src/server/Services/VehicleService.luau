-- VehicleService: the 40 cars, trucks and trams in the hub (spec: Destruction "Cars and trams"; Clash
-- moments > Vehicle flip "Any heavy hit on a car or tram: scripted flip arc of 1 s, resets after 30 s; 6
-- vehicles per district").
-- The server builds the vehicles (anchored, a few parts each), and on a heavy hit sets the landed pose at
-- once and tells clients (VehicleFlip), who play the 1 s arc locally from the same VehiclePose.flip. After
-- 30 s it puts the vehicle back (VehicleReset). PLACEHOLDER ART: boxes and wheel cylinders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local VehiclePose = require(Shared:WaitForChild("VehiclePose"))

local VehicleService = {}

local V = Config.Destruction.vehicles
local list: { any } = {}
local models: { [number]: Model } = {}
local homes: { [number]: CFrame } = {}
local flipped: { [number]: number } = {} -- id -> reset time
VehicleService.list = list

local function color(key: string): Color3
	local c = Config.City.palette[key] or { 200, 200, 200 }
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(model: Model, size: Vector3, offset: CFrame, col: Color3, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch = false
	p.Size = size
	p.Color = col
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p:SetAttribute("Offset", offset)
	p.Parent = model
	return p
end

-- One vehicle model; parts keep their offset from the model's root so a pose moves them all
local function build(v: any): Model
	local m = Instance.new("Model")
	m.Name = string.format("Vehicle_%d_%s", v.id, v.kind)
	m:SetAttribute("VehicleId", v.id)
	local body = color(v.color)
	local dark = Color3.fromRGB(30, 32, 38)
	local glass = color("glass")
	local root = part(m, Vector3.new(v.sx, v.sy * 0.55, v.sz), CFrame.new(0, v.sy * 0.275 + 1, 0), body)
	root.Name = "Body"
	m.PrimaryPart = root
	if v.kind == "car" then
		part(m, Vector3.new(v.sx * 0.9, v.sy * 0.4, v.sz * 0.5), CFrame.new(0, v.sy * 0.75 + 1, -0.5), glass)
	elseif v.kind == "truck" then
		part(m, Vector3.new(v.sx, v.sy * 0.6, v.sz * 0.3), CFrame.new(0, v.sy * 0.6 + 1, -v.sz * 0.35), glass)
		part(
			m,
			Vector3.new(v.sx * 0.95, v.sy * 0.8, v.sz * 0.6),
			CFrame.new(0, v.sy * 0.6 + 1, v.sz * 0.18),
			body
		)
	else
		part(m, Vector3.new(v.sx * 0.98, v.sy * 0.35, v.sz * 0.96), CFrame.new(0, v.sy * 0.72 + 1, 0), glass)
		part(m, Vector3.new(v.sx * 0.6, 0.6, v.sz * 0.9), CFrame.new(0, v.sy + 1.3, 0), dark)
	end
	local wheel = math.min(2.6, v.sy * 0.45)
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		part(
			m,
			Vector3.new(1.2, wheel, wheel),
			CFrame.new(s[1] * (v.sx / 2 - 0.4), wheel / 2, s[2] * (v.sz / 2 - wheel)),
			dark,
			Enum.PartType.Cylinder
		)
	end
	return m
end

local home = VehiclePose.home

function VehicleService.pose(m: Model, root: CFrame)
	VehiclePose.apply(m, root)
end

function VehicleService.flipRoot(v: any, t: number, dx: number, dz: number): CFrame
	return VehiclePose.flip(Config.Destruction, v, t, dx, dz)
end

local function flippedIn(district: string): number
	local n = 0
	for id in flipped do
		if list[id].district == district then
			n += 1
		end
	end
	return n
end

-- A heavy hit at center: vehicles within radius flip away from it
function VehicleService.hit(center: Vector3, radius: number): number
	local now = os.clock()
	local n = 0
	for _, v in list do
		if not flipped[v.id] then
			local d = Vector3.new(v.x - center.X, 0, v.z - center.Z)
			if d.Magnitude <= radius + v.sz / 2 and math.abs(center.Y - v.y) < radius + 10 then
				if flippedIn(v.district) < V.perDistrict then
					local dir = if d.Magnitude > 0.1 then d.Unit else Vector3.new(1, 0, 0)
					flipped[v.id] = now + V.resetAfter
					VehicleService.pose(models[v.id], VehicleService.flipRoot(v, 1, dir.X, dir.Z))
					Net.fireAll("VehicleFlip", v.id, dir.X, dir.Z)
					n += 1
				end
			end
		end
	end
	return n
end

function VehicleService.resetAll()
	for id in flipped do
		flipped[id] = 0
	end
end

function VehicleService.init()
	for _, v in Vehicles.place(Config) do
		list[v.id] = v
	end
	local folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	for id, v in list do
		local m = build(v)
		homes[id] = home(v)
		VehicleService.pose(m, homes[id])
		models[id] = m
		m.Parent = folder
	end
	folder.Parent = Workspace:FindFirstChild("City") or Workspace
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for id, at in flipped do
				if now >= at then
					flipped[id] = nil
					VehicleService.pose(models[id], homes[id])
					Net.fireAll("VehicleReset", id)
				end
			end
		end
	end)
end

return VehicleService
