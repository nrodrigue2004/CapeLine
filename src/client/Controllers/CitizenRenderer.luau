-- CitizenRenderer: draws the server's citizens from Citizen.Delta (4 Hz, unreliable; CitizenBuffer). Packets
-- are buffered by arrival time and drawn 0.3 s in the past, interpolated, so 4 Hz walks smoothly. Bodies are
-- pooled blocky cartoon people (legs, torso, arms, head) in 6 colour sets, posed in code: a walk swing, a
-- standing idle, and a run with arms up when fleeing. Citizens are never hurt or shown hurt (spec:
-- Destruction); a hidden citizen (safe in a shelter) is simply not sent.
-- PLACEHOLDER ART: plain parts until the art pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CitizenBuffer = require(Shared:WaitForChild("CitizenBuffer"))

local CitizenRenderer = {}

local C = Config.Destruction.citizens
local FLEE, PAUSE = 2, 1
local PARTS = { "LegL", "LegR", "Torso", "ArmL", "ArmR", "Head" }

type Body = {
	model: Model,
	parts: { BasePart },
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

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function newBody(color: number): Body
	local set = C.colors[color] or C.colors[1]
	local shirt, pants, skin = rgb(set[1]), rgb(set[2]), rgb(set[3])
	local m = Instance.new("Model")
	m.Name = "Citizen"
	local sizes = {
		LegL = Vector3.new(0.7, 1.9, 0.7),
		LegR = Vector3.new(0.7, 1.9, 0.7),
		Torso = Vector3.new(1.7, 1.9, 0.9),
		ArmL = Vector3.new(0.55, 1.7, 0.55),
		ArmR = Vector3.new(0.55, 1.7, 0.55),
		Head = Vector3.new(1.1, 1.1, 1.1),
	}
	local colors = { LegL = pants, LegR = pants, Torso = shirt, ArmL = shirt, ArmR = shirt, Head = skin }
	local parts = {}
	for _, name in PARTS do
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Size = sizes[name]
		p.Color = colors[name]
		p.Parent = m
		table.insert(parts, p)
	end
	m.Parent = folder
	return {
		model = m,
		parts = parts,
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

-- Pose one citizen; pos is the feet
local function pose(body: Body, dt: number, partList: { BasePart }, cframes: { CFrame })
	local moving = body.speed > 0.8
	local fleeing = body.state == FLEE
	body.phase += dt * (if fleeing then 14 else 8) * (if moving then 1 else 0)
	local swing = if moving then math.sin(body.phase) * (if fleeing then 0.9 else 0.55) else 0
	local bob = if moving then math.abs(math.sin(body.phase)) * 0.15 else 0
	local root = CFrame.new(body.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, body.yaw, 0)
	local lean = if fleeing then CFrame.Angles(math.rad(-12), 0, 0) else CFrame.identity
	local hip = root * CFrame.new(0, 1.9, 0)
	local torso = hip * lean * CFrame.new(0, 0.95, 0)
	local legL = hip * CFrame.new(-0.4, 0, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -0.95, 0)
	local legR = hip * CFrame.new(0.4, 0, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -0.95, 0)
	local armUp = if fleeing then math.rad(-150) else 0
	local idle = if body.state == PAUSE then math.sin(os.clock() * 1.5) * 0.05 else 0
	local armL = torso
		* CFrame.new(-1.15, 0.8, 0)
		* CFrame.Angles(armUp - swing * 0.8 + idle, 0, 0)
		* CFrame.new(0, -0.8, 0)
	local armR = torso
		* CFrame.new(1.15, 0.8, 0)
		* CFrame.Angles(armUp + swing * 0.8 - idle, 0, 0)
		* CFrame.new(0, -0.8, 0)
	local head = torso * CFrame.new(0, 1.55, 0)
	local cfs = { legL, legR, torso, armL, armR, head }
	for i, p in body.parts do
		table.insert(partList, p)
		table.insert(cframes, cfs[i])
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
	local partList, cframes = {}, {}
	for id, rb in newest do
		local ra = a.rows[id] or b.rows[id] or rb
		local rbb = b.rows[id] or rb
		local pos = Vector3.new(ra.x, ra.y, ra.z):Lerp(Vector3.new(rbb.x, rbb.y, rbb.z), alpha)
		local body = live[id]
		if not body then
			body = acquire(rb.color)
			live[id] = body
			body.pos = pos
			body.yaw = rb.yaw
		end
		local moved = Vector3.new(pos.X - body.pos.X, 0, pos.Z - body.pos.Z)
		body.speed += (moved.Magnitude / math.max(dt, 1e-3) - body.speed) * math.min(1, dt * 8)
		body.pos = pos
		body.yaw = lerpAngle(body.yaw, rbb.yaw, math.min(1, dt * 10))
		body.state = rb.state
		pose(body, dt, partList, cframes)
	end
	if #partList > 0 then
		Workspace:BulkMoveTo(partList, cframes, Enum.BulkMoveMode.FireCFrameChanged)
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
	RunService.RenderStepped:Connect(render)
end

return CitizenRenderer
