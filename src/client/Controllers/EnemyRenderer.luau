-- EnemyRenderer: draws the server's enemies from Enemy.Delta (10 Hz). Positions are buffered and drawn
-- 100 ms in the past, interpolated between snapshots, so 10 Hz looks smooth. Bodies are pooled and moved
-- with one BulkMoveTo a frame; only the nearest `enemiesDrawn` (device preset) are shown.
-- PLACEHOLDER ART: the Spark Drone is a sphere, a glowing ring, an eye and two fins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local EnemyBuffer = require(Shared:WaitForChild("EnemyBuffer"))

local QualityController = require(script.Parent.QualityController)

local EnemyRenderer = {}

local DELAY = 0.1
local snapshots: { { t: number, rows: { [number]: any } } } = {}
local lastSeq = 0

type Body = {
	model: Model,
	parts: { BasePart },
	offsets: { CFrame },
	baseColors: { Color3 },
	core: BasePart,
	bar: BillboardGui,
	fill: Frame,
	typeId: number,
	pos: Vector3,
	look: Vector3,
	health: number,
	flashUntil: number,
}

local live: { [number]: Body } = {}
local pool: { [number]: { Body } } = {}
local folder: Folder

local function makeDrone(): Body
	local model = Instance.new("Model")
	model.Name = "SparkDrone"
	local specs = {
		-- name, shape, size, offset, color, material
		{
			"Core",
			Enum.PartType.Ball,
			Vector3.new(3, 3, 3),
			CFrame.new(),
			Color3.fromRGB(70, 76, 88),
			Enum.Material.Metal,
		},
		{
			"Ring",
			Enum.PartType.Cylinder,
			Vector3.new(0.4, 4.6, 4.6),
			CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(255, 140, 60),
			Enum.Material.Neon,
		},
		{
			"Eye",
			Enum.PartType.Ball,
			Vector3.new(1.1, 1.1, 1.1),
			CFrame.new(0, 0.2, -1.25),
			Color3.fromRGB(255, 60, 50),
			Enum.Material.Neon,
		},
		{
			"FinL",
			Enum.PartType.Block,
			Vector3.new(1.6, 0.25, 1),
			CFrame.new(-2.1, 0, 0.4),
			Color3.fromRGB(90, 96, 108),
			Enum.Material.Metal,
		},
		{
			"FinR",
			Enum.PartType.Block,
			Vector3.new(1.6, 0.25, 1),
			CFrame.new(2.1, 0, 0.4),
			Color3.fromRGB(90, 96, 108),
			Enum.Material.Metal,
		},
	}
	local parts, offsets, colors = {}, {}, {}
	for _, s in specs do
		local p = Instance.new("Part")
		p.Name = s[1]
		p.Shape = s[2]
		p.Size = s[3]
		p.Color = s[5]
		p.Material = s[6]
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		table.insert(parts, p)
		table.insert(offsets, s[4])
		table.insert(colors, s[5])
	end
	local bar = Instance.new("BillboardGui")
	bar.Size = UDim2.fromScale(3.2, 0.35)
	bar.StudsOffset = Vector3.new(0, 2.6, 0)
	bar.AlwaysOnTop = true
	bar.Enabled = false
	bar.Adornee = parts[1]
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	back.BorderSizePixel = 0
	back.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 120, 70)
	fill.BorderSizePixel = 0
	fill.Parent = back
	bar.Parent = parts[1]
	return {
		model = model,
		parts = parts,
		offsets = offsets,
		baseColors = colors,
		core = parts[1],
		bar = bar,
		fill = fill,
		typeId = 1,
		pos = Vector3.zero,
		look = Vector3.new(0, 0, -1),
		health = 1,
		flashUntil = 0,
	}
end

local function acquire(typeId: number): Body
	local list = pool[typeId]
	local body = list and table.remove(list)
	if not body then
		body = makeDrone() -- every type uses the drone body until M2 adds the other machines
		body.typeId = typeId
	end
	body.model.Parent = folder
	return body
end

local function release(body: Body)
	body.model.Parent = nil
	body.bar.Enabled = false
	pool[body.typeId] = pool[body.typeId] or {}
	table.insert(pool[body.typeId], body)
end

function EnemyRenderer.flash(id: number)
	local body = live[id]
	if body then
		body.flashUntil = os.clock() + Config.Fx.hitFlash
		for _, p in body.parts do
			p.Color = Color3.new(1, 1, 1)
		end
	end
end

-- Remove at once (death); returns the last drawn position for the burst
function EnemyRenderer.kill(id: number): Vector3?
	local body = live[id]
	if not body then
		return nil
	end
	live[id] = nil
	local pos = body.pos
	release(body)
	for _, snap in snapshots do
		snap.rows[id] = nil
	end
	return pos
end

function EnemyRenderer.position(id: number): Vector3?
	local body = live[id]
	return body and body.pos
end

-- Drawn enemies for aiming and the target hint
function EnemyRenderer.each(): { [number]: Vector3 }
	local out = {}
	for id, body in live do
		out[id] = body.pos
	end
	return out
end

local function onDelta(b: buffer)
	local seq, t, rows = EnemyBuffer.decode(b)
	if seq <= lastSeq and lastSeq - seq < 1000 then
		return -- old or duplicate packet
	end
	lastSeq = seq
	local map = {}
	for _, r in rows do
		map[r.id] = r
	end
	table.insert(snapshots, { t = t, rows = map })
	while #snapshots > 4 do
		table.remove(snapshots, 1)
	end
end

local function render()
	local n = #snapshots
	if n == 0 then
		return
	end
	local renderT = Workspace:GetServerTimeNow() - DELAY
	local a, b = snapshots[1], snapshots[n]
	for i = n - 1, 1, -1 do
		if snapshots[i].t <= renderT then
			a, b = snapshots[i], snapshots[i + 1]
			break
		end
	end
	local alpha = if b.t > a.t then math.clamp((renderT - a.t) / (b.t - a.t), 0, 1.2) else 1
	local newest = snapshots[n].rows
	local cam = Workspace.CurrentCamera.CFrame.Position
	local limit = QualityController.preset.enemiesDrawn

	-- pick the nearest `limit` ids from the newest snapshot
	local ids = {}
	for id, r in newest do
		local d = (Vector3.new(r.x, r.y, r.z) - cam).Magnitude
		table.insert(ids, { id = id, d = d })
	end
	if #ids > limit then
		table.sort(ids, function(x, y)
			return x.d < y.d
		end)
	end
	local keep = {}
	for i = 1, math.min(#ids, limit) do
		keep[ids[i].id] = true
	end
	for id, body in live do
		if not keep[id] then
			release(body)
			live[id] = nil
		end
	end

	local now = os.clock()
	local partList, cframes = {}, {}
	for id in keep do
		local rb = b.rows[id] or newest[id]
		local ra = a.rows[id] or rb
		local pa = Vector3.new(ra.x, ra.y, ra.z)
		local pb = Vector3.new(rb.x, rb.y, rb.z)
		local pos = pa:Lerp(pb, alpha)
		local body = live[id]
		if not body then
			body = acquire(rb.typeId)
			live[id] = body
			body.pos = pos
		end
		local moved = pos - body.pos
		if moved.Magnitude > 0.05 then
			body.look = body.look:Lerp(moved.Unit, 0.2)
		end
		body.pos = pos
		body.health = rb.health
		body.bar.Enabled = rb.health < 0.999
		body.fill.Size = UDim2.fromScale(rb.health, 1)
		if body.flashUntil > 0 and now >= body.flashUntil then
			body.flashUntil = 0
			for i, p in body.parts do
				p.Color = body.baseColors[i]
			end
		end
		local bob = math.sin(now * 3 + id) * 0.4
		local look = Vector3.new(body.look.X, 0, body.look.Z)
		if look.Magnitude < 0.05 then
			look = Vector3.new(0, 0, -1)
		end
		local base = CFrame.lookAt(pos + Vector3.new(0, bob, 0), pos + Vector3.new(0, bob, 0) + look.Unit)
		for i, p in body.parts do
			table.insert(partList, p)
			table.insert(cframes, base * body.offsets[i])
		end
	end
	if #partList > 0 then
		Workspace:BulkMoveTo(partList, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EnemyRenderer.init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	Net.listen("EnemyDelta", onDelta)
	RunService.RenderStepped:Connect(render)
end

return EnemyRenderer
