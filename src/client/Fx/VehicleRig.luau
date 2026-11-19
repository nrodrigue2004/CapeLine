-- VehicleRig (2026-11-19, gap-vehicles; nate called the vehicles "trash": the wheels did not turn and the escorts
-- glided like a box): makes a driven vehicle look alive on this device. For every vehicle tagged DriveRig (the side
-- quest escorts, the contract truck, the towed car; SetPieceMeshes.rig on the server) near the camera:
-- * the server's steps are eased into a glide (Config.Destruction.vehicles.rig.smooth; a big jump is taken at once),
-- * each road wheel (its own mesh, Config.VehicleArt `wheel`) rolls at the ground speed by its own radius, and the
--   front pair steers into the turn (Shared.DriveMath.steer from the heading change, the wheelbase from the meshes),
-- * the body pitches as it pulls away and brakes and leans out of turns, on springs (DriveMath.swayStep).
-- A hub car, truck or tram (VehicleService) settles on its springs when it drops back home after a flip (kick).
-- Wrecked vehicles (flipped or held, the Wrecked attribute) keep their wheels still.
-- Cheap: only vehicles within the preset's vehicleRig studs of the camera, nothing for a parked one once it has
-- settled, all moves in one BulkMoveTo, under FrameProf. The hidden boxes stay where the server puts them (they
-- carry the collision and queries); only the meshes are drawn here.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local DriveMath = require(Shared:WaitForChild("DriveMath"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local VehicleRig = {}

local R = Config.Destruction.vehicles.rig

type Piece = { part: BasePart, offset: CFrame, r: number, steer: boolean }
type Rig = {
	model: Model,
	root: BasePart,
	rootOff: CFrame, -- the root part's place on the vehicle's root pose
	body: { Piece },
	wheels: { Piece },
	wheelbase: number,
	temp: boolean, -- a hub vehicle settling after its reset: dropped once still
	sm: CFrame?, -- the eased pose drawn
	roll: number, -- studs rolled (each wheel's angle is roll / its radius)
	speed: number,
	accel: number,
	yaw: number,
	yawRate: number,
	steer: number,
	sway: DriveMath.Sway,
	kick: number?,
	live: boolean, -- drawn by this module now (else at rest where the server put it)
}

local rigs: { [Model]: Rig } = {}
local dirty: { [Model]: boolean } = {} -- tagged models whose rig is (re)built when next in range
local watched: { [Model]: { RBXScriptConnection } } = {}

-- The model's pieces: every visible mesh with an Offset on the root (wheels by their WheelR), never the root
local function build(m: Model, temp: boolean): Rig?
	local root = m.PrimaryPart
	if not root then
		return nil
	end
	local ro = root:GetAttribute("Offset")
	local rootOff = if typeof(ro) == "CFrame" then ro else CFrame.new()
	local body, wheels = {}, {}
	local front, back = math.huge, -math.huge
	for _, p in m:GetChildren() do
		if p:IsA("MeshPart") and p ~= root and p.Transparency < 1 then
			local off = p:GetAttribute("Offset")
			if typeof(off) == "CFrame" then
				local r = p:GetAttribute("WheelR")
				if type(r) == "number" and r > 0 then
					local steer = p:GetAttribute("Steer") == true
					table.insert(wheels, { part = p, offset = off, r = r, steer = steer })
					front = math.min(front, off.Position.Z)
					back = math.max(back, off.Position.Z)
				else
					table.insert(body, { part = p, offset = off, r = 0, steer = false })
				end
			end
		end
	end
	if #body == 0 and #wheels == 0 then
		return nil
	end
	return {
		model = m,
		root = root,
		rootOff = rootOff,
		body = body,
		wheels = wheels,
		wheelbase = if back > front then back - front else 8,
		temp = temp,
		sm = nil,
		roll = 0,
		speed = 0,
		accel = 0,
		yaw = 0,
		yawRate = 0,
		steer = 0,
		sway = DriveMath.sway(),
		kick = nil,
		live = false,
	}
end

local parts: { BasePart } = {}
local cfs: { CFrame } = {}

-- Queue a rig's pieces at a pose: the body swayed about its axles' height, the wheels steered and rolled
local function pose(rig: Rig, at: CFrame)
	local s = rig.sway
	local lean = at * CFrame.new(0, 1 + s.heave, 0) * CFrame.Angles(s.pitch, 0, s.roll) * CFrame.new(0, -1, 0)
	for _, b in rig.body do
		table.insert(parts, b.part)
		table.insert(cfs, lean * b.offset)
	end
	for _, w in rig.wheels do
		table.insert(parts, w.part)
		local turn = if w.steer then CFrame.Angles(0, rig.steer, 0) else CFrame.identity
		-- rolling forward (the nose is -z) turns the wheel's top toward -z: a negative turn about x
		table.insert(cfs, at * w.offset * turn * CFrame.Angles(-rig.roll / w.r, 0, 0))
	end
end

local function drop(m: Model)
	rigs[m] = nil
end

local function stepRig(rig: Rig, target: CFrame, dt: number)
	local sm = rig.sm
	if sm == nil or (target.Position - sm.Position).Magnitude > R.snap then
		sm = target
		rig.speed, rig.accel, rig.yawRate = 0, 0, 0
		local _, y = target:ToOrientation()
		rig.yaw = y
	else
		sm = sm:Lerp(target, 1 - math.exp(-R.smooth * dt))
	end
	local prev = rig.sm or sm
	rig.sm = sm
	local fwd = (sm.Position - prev.Position):Dot(prev.LookVector)
	local k = math.min(1, dt * 8)
	local speed = rig.speed + (fwd / dt - rig.speed) * k
	rig.accel += ((speed - rig.speed) / dt - rig.accel) * k
	rig.speed = speed
	local _, y = sm:ToOrientation()
	rig.yawRate += (DriveMath.turn(rig.yaw, y) / dt - rig.yawRate) * k
	rig.yaw = y
	local wrecked = rig.model:GetAttribute("Wrecked") == true
	if not wrecked then
		rig.roll = (rig.roll + fwd) % 1e4
		local want = DriveMath.steer(rig.yawRate, rig.speed, rig.wheelbase, R.maxSteer)
		rig.steer += (want - rig.steer) * math.min(1, dt * 10)
	end
	DriveMath.swayStep(
		rig.sway,
		if wrecked then 0 else rig.accel,
		if wrecked then 0 else rig.speed * rig.yawRate,
		dt,
		R.sway,
		rig.kick
	)
	rig.kick = nil
	pose(rig, sm)
	rig.live = true
end

local function step(dt: number)
	if dt <= 0 then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local eye = cam.CFrame.Position
	local near = QualityController.preset.vehicleRig or 150
	table.clear(parts)
	table.clear(cfs)
	for m in dirty do
		local root = m.PrimaryPart
		if root and (root.Position - eye).Magnitude <= near then
			dirty[m] = nil
			local old = rigs[m]
			local rig = build(m, false)
			if rig and old then
				rig.sm, rig.roll, rig.sway = old.sm, old.roll, old.sway
			end
			rigs[m] = rig
		end
	end
	for m, rig in rigs do
		local root = rig.root
		if root.Parent ~= m or m.Parent == nil then
			drop(m)
			continue
		end
		if rig.temp and m:GetAttribute("Wrecked") == true then
			drop(m) -- flipped or picked up again: the flip arc or the throw draws it now
			continue
		end
		local target = root.CFrame * rig.rootOff:Inverse()
		local sm = rig.sm
		-- far from the camera, or parked and settled: nothing to draw (it stays as last drawn, the wheels where they
		-- stopped, until the server moves it again)
		local far = (target.Position - eye).Magnitude > near
		local parked = sm ~= nil
			and rig.kick == nil
			and (target.Position - sm.Position).Magnitude < 0.01
			and math.abs(rig.speed) < 0.05
			and math.abs(rig.yawRate) < 0.01
			and DriveMath.still(rig.sway)
		if far or parked then
			rig.live = false
			if far then
				rig.sm = nil
			end
			if rig.temp then
				drop(m)
			end
			continue
		end
		stepRig(rig, target, dt)
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Stop drawing a vehicle (a hub car that flips again: VehicleFx's arc draws it)
function VehicleRig.release(m: Model)
	local rig = rigs[m]
	if rig and rig.temp then
		rigs[m] = nil
	end
end

-- A hub vehicle back home after a flip (VehicleFx): it drops onto its springs and settles
function VehicleRig.kick(m: Model)
	local rig = rigs[m] or build(m, true)
	if not rig then
		return
	end
	rigs[m] = rig
	rig.sm = nil
	rig.kick = -R.kick
end

local function track(m: Instance)
	if not m:IsA("Model") or watched[m] then
		return
	end
	dirty[m] = true
	-- streamed or added meshes: rebuild the rig next time it is in range
	watched[m] = {
		m.ChildAdded:Connect(function()
			dirty[m] = true
		end),
		m.ChildRemoved:Connect(function()
			dirty[m] = true
		end),
	}
end

local function untrack(m: Instance)
	local w = watched[m :: Model]
	if w then
		for _, c in w do
			c:Disconnect()
		end
		watched[m :: Model] = nil
	end
	dirty[m :: Model] = nil
	rigs[m :: Model] = nil
end

function VehicleRig.init()
	for _, m in CollectionService:GetTagged("DriveRig") do
		track(m)
	end
	CollectionService:GetInstanceAddedSignal("DriveRig"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("DriveRig"):Connect(untrack)
	RunService.RenderStepped:Connect(FrameProf.wrap("VehicleRig", step))
end

return VehicleRig
