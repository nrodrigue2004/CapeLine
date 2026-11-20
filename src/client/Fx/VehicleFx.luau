-- VehicleFx: the 1 s flip arc of a hub car, truck or tram (spec: Clash moments > Vehicle flip). The server
-- has already put the vehicle on its roof; this plays the arc from home to there on the device with the same
-- VehiclePose maths, adds a dust puff and sparks where it lands, and a pop of glass when it resets.
-- gap-vehicles (2026-11-19): the wheel meshes ride the same Offsets (they stay on their axles, still, while it is
-- flipped), and back home it bounces once on its springs (VehicleRig.kick).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local VehiclePose = require(Shared:WaitForChild("VehiclePose"))

local FxLib = require(script.Parent.FxLib)
local Juice = require(script.Parent.Juice)
local VehicleRig = require(script.Parent.VehicleRig)

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

-- item 296: the landing's dust and sparks and the reset's glass are effects-library particles (FxLib: the
-- uploaded textures, the preset's particle budget), no longer plain balls and neon sticks
local function landed(pos: Vector3)
	FxLib.dust(pos, 5, Color3.fromRGB(190, 180, 168))
	FxLib.emit("spark", Color3.fromRGB(255, 200, 90), pos + Vector3.new(0, 1, 0), 10, Vector3.yAxis)
	FxLib.emit("chip", Color3.fromRGB(70, 70, 78), pos + Vector3.new(0, 0.5, 0), 6, Vector3.yAxis)
end

local function popGlass(pos: Vector3)
	FxLib.emit("shard", Color3.fromRGB(200, 240, 255), pos, 8, Vector3.yAxis)
	FxLib.dust(pos - Vector3.new(0, 1.5, 0), 3)
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
			landed(VehiclePose.flip(Config.Destruction, v, 1, a.dx, a.dz).Position)
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
			local m = model(id)
			if m then
				VehicleRig.release(m) -- the arc draws it now
			end
			Juice.fire("vehicleFlip", VehiclePose.home(list[id]).Position, { mine = false })
		end
	end)
	Net.listen("VehicleReset", function(id: number)
		local v = list[id]
		if v then
			arcs[id] = nil
			popGlass(VehiclePose.home(v).Position + Vector3.new(0, 2, 0))
			local m = model(id)
			if m then
				VehicleRig.kick(m) -- gap-vehicles: it drops back onto its springs and settles
			end
		end
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("VehicleFx", step))
end

return VehicleFx
