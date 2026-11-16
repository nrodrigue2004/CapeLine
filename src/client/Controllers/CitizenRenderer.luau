-- CitizenRenderer: draws the server's citizens from Citizen.Delta (4 Hz, unreliable; CitizenBuffer). Packets
-- are buffered by arrival time and drawn 0.3 s in the past, interpolated, so 4 Hz walks smoothly. Every
-- citizen is on the same blocky R15 rig as the heroes (nate, 2026-11-16: "literally everyone should be r15";
-- NpcRig): pooled by its 6 colour sets (shirt on the torso and sleeves, skin on the forearms, hands and head
-- with the classic face, pants and darker shoes), with blocky hair picked from its id, posed on its R15
-- joints in code: a walk swing, a standing idle, and a run with arms up when fleeing. Far citizens pose every
-- few frames. Citizens are never hurt or shown hurt (spec: Destruction); a hidden citizen (safe in a shelter)
-- is simply not sent.
-- PLACEHOLDER ART: plain blocks until the hero meshes are imported (then the hero meshes), and posed in code
-- until real R15 animations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CitizenBuffer = require(Shared:WaitForChild("CitizenBuffer"))
local Rng = require(Shared:WaitForChild("Rng"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))

local CitizenRenderer = {}

local C = Config.Destruction.citizens
local FLEE, PAUSE = 2, 1
local SIDES = { { "Left", -1 }, { "Right", 1 } }
local layout = RigMath.layout(Config.HeroRig, nil, 1)

type Body = {
	model: Model,
	rig: NpcRig.Rig,
	hair: BasePart,
	color: number,
	pos: Vector3,
	yaw: number,
	phase: number,
	speed: number,
	state: number,
}

local snapshots: { { t: number, rows: { [number]: CitizenBuffer.Row } } } = {}
local lastSeq = 0
local live: { [number]: Body } = {}
local pool: { [number]: { Body } } = {}
local folder: Folder
local frame = 0

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function newBody(color: number): Body
	local set = C.colors[color] or C.colors[1]
	local rig = NpcRig.person(layout, "Citizen", rgb(set[1]), rgb(set[2]), rgb(set[3]), rgb(C.hair[1]))
	rig.model.Parent = folder
	return {
		model = rig.model,
		rig = rig,
		hair = rig.model:FindFirstChild("Hair") :: BasePart,
		color = color,
		pos = Vector3.zero,
		yaw = 0,
		phase = 0,
		speed = 0,
		state = 0,
	}
end

local function acquire(color: number): Body
	local list = pool[color]
	local body = list and table.remove(list)
	if body then
		body.model.Parent = folder
		return body
	end
	return newBody(color)
end

local function release(body: Body)
	body.model.Parent = nil
	pool[body.color] = pool[body.color] or {}
	table.insert(pool[body.color], body)
end

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- Pose one citizen (pos is the feet): the root goes on the BulkMoveTo lists, the R15 joints turn when
-- `joints` is true
local function pose(body: Body, dt: number, roots: { BasePart }, cframes: { CFrame }, joints: boolean)
	local moving = body.speed > 0.8
	local fleeing = body.state == FLEE
	body.phase += dt * (if fleeing then 14 else 8) * (if moving then 1 else 0)
	local bob = if moving then math.abs(math.sin(body.phase)) * 0.15 else 0
	table.insert(roots, body.rig.root)
	table.insert(
		cframes,
		CFrame.new(body.pos + Vector3.new(0, layout.ground + bob, 0)) * CFrame.Angles(0, body.yaw, 0)
	)
	if not joints then
		return
	end
	local rig = body.rig
	local swing = if moving then math.sin(body.phase) * (if fleeing then 0.9 else 0.55) else 0
	NpcRig.turn(rig, "Waist", if fleeing then CFrame.Angles(math.rad(-12), 0, 0) else CFrame.identity)
	local armUp = if fleeing then math.rad(-150) else 0
	local idle = if body.state == PAUSE then math.sin(os.clock() * 1.5) * 0.05 else 0
	for _, side in SIDES do
		local name, sign = side[1], side[2]
		NpcRig.turn(rig, name .. "Hip", CFrame.Angles(swing * sign, 0, 0))
		NpcRig.turn(rig, name .. "Knee", CFrame.Angles(-math.max(0, swing * sign) * 0.6, 0, 0))
		NpcRig.turn(rig, name .. "Shoulder", CFrame.Angles(armUp - swing * sign * 0.8 - idle * sign, 0, 0))
		NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(if moving then math.rad(20) else math.rad(5), 0, 0))
	end
end

local lastRender = os.clock()
local function render()
	local now = os.clock()
	local dt = math.min(0.1, now - lastRender)
	lastRender = now
	local n = #snapshots
	if n == 0 then
		return
	end
	local renderT = now - C.drawDelay
	local a, b = snapshots[1], snapshots[n]
	for i = n - 1, 1, -1 do
		if snapshots[i].t <= renderT then
			a, b = snapshots[i], snapshots[i + 1]
			break
		end
	end
	local alpha = if b.t > a.t then math.clamp((renderT - a.t) / (b.t - a.t), 0, 1) else 1
	local newest = snapshots[n].rows
	for id, body in live do
		local row = newest[id]
		if not row or row.color ~= body.color then
			release(body)
			live[id] = nil
		end
	end
	local roots, cframes = {}, {}
	local cam = Workspace.CurrentCamera.CFrame.Position
	frame += 1
	for id, rb in newest do
		local ra = a.rows[id] or b.rows[id] or rb
		local rbb = b.rows[id] or rb
		local pos = Vector3.new(ra.x, ra.y, ra.z):Lerp(Vector3.new(rbb.x, rbb.y, rbb.z), alpha)
		local body = live[id]
		if not body then
			body = acquire(rb.color)
			body.hair.Color = rgb(C.hair[Rng.hash(id, 4409) % #C.hair + 1])
			NpcRig.rest(body.rig)
			live[id] = body
			body.pos = pos
			body.yaw = rb.yaw
		end
		local moved = Vector3.new(pos.X - body.pos.X, 0, pos.Z - body.pos.Z)
		body.speed += (moved.Magnitude / math.max(dt, 1e-3) - body.speed) * math.min(1, dt * 8)
		body.pos = pos
		body.yaw = lerpAngle(body.yaw, rbb.yaw, math.min(1, dt * 10))
		body.state = rb.state
		local near = (pos - cam).Magnitude < C.poseNear
		pose(body, dt, roots, cframes, near or (frame + id) % C.poseEvery == 0)
	end
	if #roots > 0 then
		Workspace:BulkMoveTo(roots, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function CitizenRenderer.count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

function CitizenRenderer.init()
	folder = Instance.new("Folder")
	folder.Name = "Citizens"
	folder.Parent = Workspace
	Net.listen("CitizenDelta", function(b: buffer)
		if type(b) ~= "buffer" then
			return
		end
		local seq, rows = CitizenBuffer.decode(b)
		if seq <= lastSeq then
			return -- unreliable: late packets are dropped
		end
		lastSeq = seq
		local byId = {}
		for _, r in rows do
			byId[r.id] = r
		end
		table.insert(snapshots, { t = os.clock(), rows = byId })
		while #snapshots > 6 do
			table.remove(snapshots, 1)
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("CitizenRenderer", render))
end

return CitizenRenderer
