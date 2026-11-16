-- VehicleFx: the 1 s flip arc of a hub car, truck or tram (spec: Clash moments > Vehicle flip). The server
-- has already put the vehicle on its roof; this plays the arc from home to there on the device with the same
-- VehiclePose maths, adds a dust puff and sparks where it lands, and a pop of glass when it resets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local VehiclePose = require(Shared:WaitForChild("VehiclePose"))

local DebrisBudget = require(script.Parent.DebrisBudget)
local Juice = require(script.Parent.Juice)

local VehicleFx = {}

local V = Config.Destruction.vehicles
local list: { [number]: any } = {}
local arcs: { [number]: { t0: number, dx: number, dz: number } } = {}

local function model(id: number): Model?
	local city = Workspace:FindFirstChild("City")
	local folder = city and city:FindFirstChild("Vehicles")
	local m = folder and folder:FindFirstChild(string.format("Vehicle_%d_%s", id, list[id].kind))
	return if m and m:IsA("Model") then m else nil
end

local function puff(pos: Vector3, color: Color3, size: number, life: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = 0.35
	p.Size = Vector3.one * size
	p.CFrame = CFrame.new(pos)
	p.Parent = Workspace
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size * 3,
		Transparency = 1,
	}):Play()
	task.delay(life, function()
		p:Destroy()
	end)
end

local function sparks(pos: Vector3)
	local n = DebrisBudget.lease(5, 1.2)
	for _ = 1, n do
		local p = Instance.new("Part")
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 200, 90)
		p.Size = Vector3.new(0.2, 0.2, 0.8)
		p.CFrame = CFrame.new(pos)
		p.AssemblyLinearVelocity = Vector3.new(
			math.random() - 0.5,
			math.random() * 0.8 + 0.3,
			math.random() - 0.5
		) * 40
		p.Parent = Workspace
		task.delay(1.2, function()
			p:Destroy()
		end)
	end
end

local function step()
	local now = os.clock()
	for id, a in arcs do
		local v = list[id]
		local m = model(id)
		local t = math.clamp((now - a.t0) / V.flipTime, 0, 1)
		if m then
			VehiclePose.apply(m, VehiclePose.flip(Config.Destruction, v, t, a.dx, a.dz))
		end
		if t >= 1 then
			arcs[id] = nil
			local landed = VehiclePose.flip(Config.Destruction, v, 1, a.dx, a.dz).Position
			puff(landed, Color3.fromRGB(190, 180, 168), 5, 0.6)
			sparks(landed + Vector3.new(0, 1, 0))
		end
	end
end

function VehicleFx.init()
	for _, v in Vehicles.place(Config) do
		list[v.id] = v
	end
	Net.listen("VehicleFlip", function(id: number, dx: number, dz: number)
		if list[id] and type(dx) == "number" and type(dz) == "number" then
			arcs[id] = { t0 = os.clock(), dx = dx, dz = dz }
			Juice.fire("vehicleFlip", VehiclePose.home(list[id]).Position, { mine = false })
		end
	end)
	Net.listen("VehicleReset", function(id: number)
		local v = list[id]
		if v then
			arcs[id] = nil
			puff(VehiclePose.home(v).Position + Vector3.new(0, 2, 0), Color3.fromRGB(200, 240, 255), 4, 0.4)
		end
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("VehicleFx", step))
end

return VehicleFx
