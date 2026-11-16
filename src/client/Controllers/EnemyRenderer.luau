-- EnemyRenderer: draws the server's enemies from Enemy.Delta (10 Hz). Positions are buffered and drawn
-- 100 ms in the past, interpolated between snapshots, so 10 Hz looks smooth. Bodies are pooled and moved
-- with one BulkMoveTo a frame; only the nearest `enemiesDrawn` (device preset) are shown.
-- Every enemy is a humanoid robot (nate, 2026-11-16): a part-built android rig (torso, head with glowing
-- eyes, two-part arms and legs) animated in code: walk cycles from speed, aiming arms while attacking, a
-- raised slam on a windup, a tumble when knocked up, a wobble when stunned, and see-through while cloaked.
-- Status flags from the server tint and mark the body: ice blue when slowed or rooted, a spinning ring when
-- stunned, a bubble or a guard plate when shielded.
-- PLACEHOLDER ART: the robots are built from plain parts; meshes and real animations come with the art pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local EnemyBuffer = require(Shared:WaitForChild("EnemyBuffer"))
local Status = require(Shared:WaitForChild("Status"))

local QualityController = require(script.Parent.QualityController)

local EnemyRenderer = {}

local DELAY = 0.1
local BITS = Status.BITS
local ATTACK = 3
local snapshots: { { t: number, rows: { [number]: any } } } = {}
local lastSeq = 0

local byType: { [number]: any } = {}
for _, kind in Config.Enemies.order do
	local cfg = Config.Enemies[kind]
	byType[cfg.typeId] = cfg
end

type Body = {
	model: Model,
	parts: { BasePart },
	names: { string },
	baseColors: { Color3 },
	baseTransparency: { number },
	byName: { [string]: BasePart },
	bar: BillboardGui,
	fill: Frame,
	typeId: number,
	cfg: any,
	dims: any,
	pos: Vector3,
	yaw: number,
	speed: number,
	phase: number,
	health: number,
	flags: number,
	state: number,
	flashUntil: number,
	lastFlags: number,
	swingUntil: number,
}

local live: { [number]: Body } = {}
local pool: { [number]: { Body } } = {}
local folder: Folder

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Body proportions by build, scaled to the robot's height
local BUILDS = {
	slim = { torsoW = 0.32, torsoD = 0.2, limb = 0.11, head = 0.2 },
	normal = { torsoW = 0.38, torsoD = 0.24, limb = 0.13, head = 0.2 },
	heavy = { torsoW = 0.5, torsoD = 0.32, limb = 0.18, head = 0.17 },
}

local function newPart(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

local function makeRobot(typeId: number): Body
	local cfg = byType[typeId] or Config.Enemies.SparkDrone
	local body = cfg.body
	local b = BUILDS[body.build] or BUILDS.normal
	local h = body.height
	local metal = rgb(body.metal)
	local dark = metal:Lerp(Color3.new(0, 0, 0), 0.45)
	local eye = rgb(body.eye)
	local model = Instance.new("Model")
	model.Name = cfg.name
	local dims = {
		h = h,
		torsoH = h * 0.32,
		torsoW = h * b.torsoW,
		torsoD = h * b.torsoD,
		head = h * b.head,
		limb = h * b.limb,
		arm = h * 0.19, -- each of the upper and lower arm
		leg = h * 0.23, -- each of the thigh and shin
	}
	local parts, names, colors, trans, byName = {}, {}, {}, {}, {}
	local function add(
		name: string,
		size: Vector3,
		color: Color3,
		material: Enum.Material,
		shape: Enum.PartType?,
		transparency: number?
	)
		local p = newPart(model, name, size, color, material, shape)
		p.Transparency = transparency or 0
		table.insert(parts, p)
		table.insert(names, name)
		table.insert(colors, color)
		table.insert(trans, p.Transparency)
		byName[name] = p
		return p
	end
	local d = dims
	add("Torso", Vector3.new(d.torsoW, d.torsoH, d.torsoD), metal, Enum.Material.Metal)
	add("Core", Vector3.new(d.torsoW * 0.35, d.torsoW * 0.35, 0.2), eye, Enum.Material.Neon)
	add("Pelvis", Vector3.new(d.torsoW * 0.8, d.torsoH * 0.28, d.torsoD * 0.9), dark, Enum.Material.Metal)
	add("Head", Vector3.new(d.head, d.head * 1.1, d.head), metal, Enum.Material.Metal)
	add("Eyes", Vector3.new(d.head * 0.75, d.head * 0.18, 0.15), eye, Enum.Material.Neon)
	for _, side in { "L", "R" } do
		add("Upper" .. side, Vector3.new(d.limb, d.arm, d.limb), dark, Enum.Material.Metal)
		add("Lower" .. side, Vector3.new(d.limb * 0.9, d.arm, d.limb * 0.9), metal, Enum.Material.Metal)
		add("Thigh" .. side, Vector3.new(d.limb * 1.1, d.leg, d.limb * 1.1), dark, Enum.Material.Metal)
		add("Shin" .. side, Vector3.new(d.limb, d.leg, d.limb * 1.2), metal, Enum.Material.Metal)
	end
	if body.jets then
		add(
			"JetL",
			Vector3.new(d.limb * 0.8, d.limb * 1.6, d.limb * 0.8),
			Color3.fromRGB(255, 170, 70),
			Enum.Material.Neon
		)
		add(
			"JetR",
			Vector3.new(d.limb * 0.8, d.limb * 1.6, d.limb * 0.8),
			Color3.fromRGB(255, 170, 70),
			Enum.Material.Neon
		)
	end
	if body.mask then
		add(
			"Mask",
			Vector3.new(d.head * 1.05, d.head * 0.35, d.head * 1.05),
			Color3.fromRGB(25, 25, 30),
			Enum.Material.SmoothPlastic
		)
		add(
			"Bag",
			Vector3.new(d.torsoW * 0.7, d.torsoH * 0.7, d.torsoD * 0.8),
			Color3.fromRGB(120, 90, 50),
			Enum.Material.Fabric
		)
	end
	if body.planted then
		add("Cannon", Vector3.new(d.limb * 1.6, d.limb * 1.6, d.arm * 1.8), dark, Enum.Material.Metal)
		add("Muzzle", Vector3.new(d.limb * 1.0, d.limb * 1.0, 0.3), eye, Enum.Material.Neon)
		add("Base", Vector3.new(d.torsoW * 1.6, 0.6, d.torsoW * 1.6), dark, Enum.Material.DiamondPlate)
		add(
			"Bubble",
			Vector3.one * h * 1.2,
			Color3.fromRGB(120, 220, 255),
			Enum.Material.ForceField,
			Enum.PartType.Ball,
			1
		)
	end
	if body.shield then
		add(
			"Guard",
			Vector3.new(d.torsoW * 1.1, d.torsoH * 1.5, 0.35),
			Color3.fromRGB(200, 210, 230),
			Enum.Material.Neon,
			nil,
			0.25
		)
	end
	add(
		"Stun",
		Vector3.new(0.15, d.head * 1.6, d.head * 1.6),
		Color3.fromRGB(255, 230, 90),
		Enum.Material.Neon,
		Enum.PartType.Cylinder,
		1
	)

	local bar = Instance.new("BillboardGui")
	bar.Size = UDim2.fromScale(math.max(3, d.torsoW * 2), 0.35)
	bar.StudsOffset = Vector3.new(0, d.head + 0.8, 0)
	bar.AlwaysOnTop = true
	bar.Enabled = false
	bar.Adornee = byName.Head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	back.BorderSizePixel = 0
	back.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if cfg.elite then Color3.fromRGB(255, 210, 60) else Color3.fromRGB(255, 120, 70)
	fill.BorderSizePixel = 0
	fill.Parent = back
	bar.Parent = byName.Head
	return {
		model = model,
		parts = parts,
		names = names,
		baseColors = colors,
		baseTransparency = trans,
		byName = byName,
		bar = bar,
		fill = fill,
		typeId = typeId,
		cfg = cfg,
		dims = dims,
		pos = Vector3.zero,
		yaw = 0,
		speed = 0,
		phase = 0,
		health = 1,
		flags = 0,
		state = 1,
		flashUntil = 0,
		lastFlags = -1,
		swingUntil = 0,
	}
end

local function acquire(typeId: number): Body
	local list = pool[typeId]
	local body = list and table.remove(list)
	if not body then
		body = makeRobot(typeId)
	end
	body.lastFlags = -1
	body.model.Parent = folder
	return body
end

local function release(body: Body)
	body.model.Parent = nil
	body.bar.Enabled = false
	pool[body.typeId] = pool[body.typeId] or {}
	table.insert(pool[body.typeId], body)
end

local ICE = Color3.fromRGB(170, 225, 255)
local NEON_KEEP = {
	Eyes = true,
	Core = true,
	JetL = true,
	JetR = true,
	Muzzle = true,
	Guard = true,
	Stun = true,
	Bubble = true,
}

-- Colours and transparency change only when the flags change (cheap)
local function applyFlags(body: Body)
	local f = body.flags
	if body.flashUntil > 0 or f == body.lastFlags then
		return -- unchanged, or the white hit flash is showing
	end
	body.lastFlags = f
	local cold = bit32.band(f, BITS.slow + BITS.root) ~= 0
	local cloak = bit32.band(f, BITS.cloak) ~= 0
	local shield = bit32.band(f, BITS.shield) ~= 0
	local stun = bit32.band(f, BITS.stun) ~= 0
	local windup = bit32.band(f, BITS.windup) ~= 0
	for i, p in body.parts do
		local name = body.names[i]
		local color = body.baseColors[i]
		local t = body.baseTransparency[i]
		if cold and not NEON_KEEP[name] then
			color = color:Lerp(ICE, 0.6)
		end
		if name == "Eyes" and windup then
			color = Color3.fromRGB(255, 40, 40)
		end
		if name == "Stun" then
			t = if stun then 0.2 else 1
		elseif name == "Bubble" then
			t = if shield then 0.55 else 1
		elseif name == "Guard" then
			t = if shield then 0.25 else 1
		elseif cloak then
			t = if name == "Eyes" then 0.6 else 0.92
		end
		p.Color = color
		p.Transparency = t
	end
	body.bar.Enabled = body.health < 0.999 and not cloak
end

function EnemyRenderer.flash(id: number)
	local body = live[id]
	if body then
		body.flashUntil = os.clock() + Config.Fx.hitFlash
		for i, p in body.parts do
			if body.baseTransparency[i] < 1 then
				p.Color = Color3.new(1, 1, 1)
			end
		end
	end
end

-- A melee swing pose (Sneak stab, Sentinel sweep) for 0.3 s
function EnemyRenderer.swing(id: number)
	local body = live[id]
	if body then
		body.swingUntil = os.clock() + 0.3
	end
end

-- Remove at once (death); returns the last drawn position and the body colour for the burst
function EnemyRenderer.kill(id: number): (Vector3?, Color3?)
	local body = live[id]
	if not body then
		return nil, nil
	end
	live[id] = nil
	local pos = body.pos
	local color = body.baseColors[1]
	release(body)
	for _, snap in snapshots do
		snap.rows[id] = nil
	end
	return pos, color
end

function EnemyRenderer.position(id: number): Vector3?
	local body = live[id]
	return body and body.pos
end

-- Drawn enemies for aiming and the target hint; cloaked Sneak Bots are left out of auto-aim
function EnemyRenderer.each(): { [number]: Vector3 }
	local out = {}
	for id, body in live do
		if bit32.band(body.flags, BITS.cloak) == 0 then
			out[id] = body.pos
		end
	end
	return out
end

function EnemyRenderer.flags(id: number): number
	local body = live[id]
	return if body then body.flags else 0
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

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- Pose every part of one robot; appends to the BulkMoveTo lists
local function pose(
	body: Body,
	id: number,
	now: number,
	dt: number,
	partList: { BasePart },
	cframes: { CFrame }
)
	local d = body.dims
	local cfg = body.cfg
	local flags = body.flags
	local flyer = cfg.ai == "flyer"
	local lifted = bit32.band(flags, BITS.lifted) ~= 0
	local stunned = bit32.band(flags, BITS.stun) ~= 0
	local windup = bit32.band(flags, BITS.windup) ~= 0
	local attacking = body.state == ATTACK
	local swinging = now < body.swingUntil
	-- e.y is the body centre for ground robots and the hover point for flyers
	local hipY = if flyer then 0 else -d.h * 0.5 + d.leg * 2
	local root = CFrame.new(body.pos) * CFrame.Angles(0, body.yaw, 0)
	if flyer then
		root *= CFrame.new(0, math.sin(now * 3 + id) * 0.35, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	end
	if lifted then
		root *= CFrame.Angles(math.rad((now * 540) % 360), 0, math.rad(25)) -- tumble
	elseif stunned then
		root *= CFrame.Angles(0, 0, math.rad(math.sin(now * 14) * 10))
	end
	local speed = body.speed
	body.phase += dt * math.clamp(speed, 0, 30) * 0.45
	local swingA = if flyer or lifted then 0 else math.clamp(speed / 20, 0, 1) * math.rad(40)
	local s = math.sin(body.phase)
	local hips = root * CFrame.new(0, hipY, 0)
	local torsoC = hips * CFrame.new(0, d.torsoH * 0.5 + d.torsoH * 0.14, 0)
	if cfg.ai == "sneak" and not attacking then
		torsoC *= CFrame.Angles(math.rad(-18), 0, 0) -- crouched creep
	end
	local function put(name: string, cf: CFrame)
		local p = body.byName[name]
		if p then
			table.insert(partList, p)
			table.insert(cframes, cf)
		end
	end
	put("Pelvis", hips)
	put("Torso", torsoC)
	put("Core", torsoC * CFrame.new(0, d.torsoH * 0.1, -d.torsoD * 0.5 - 0.05))
	local neck = torsoC * CFrame.new(0, d.torsoH * 0.5 + d.head * 0.55, 0)
	put("Head", neck)
	put("Eyes", neck * CFrame.new(0, d.head * 0.08, -d.head * 0.5 - 0.05))
	put("Mask", neck * CFrame.new(0, d.head * 0.08, 0))
	put("Bag", torsoC * CFrame.new(0, 0, d.torsoD * 0.5 + d.torsoD * 0.35))
	put("Stun", neck * CFrame.new(0, d.head * 0.9, 0) * CFrame.Angles(0, now * 6, math.rad(90)))
	-- arms: shoulder pivots; aiming forward when attacking, raised overhead on a windup
	for k, side in { "L", "R" } do
		local sign = if k == 1 then -1 else 1
		local shoulder = torsoC * CFrame.new(sign * (d.torsoW * 0.5 + d.limb * 0.55), d.torsoH * 0.38, 0)
		local upperA, elbowA = -s * sign * swingA * 0.8, math.rad(-15)
		if windup then
			upperA, elbowA = math.rad(160), math.rad(-20)
		elseif swinging then
			upperA, elbowA = math.rad(if k == 2 then -95 else 30), 0
		elseif attacking and (flyer or cfg.ai == "thief" or cfg.ai == "sentry") and k == 2 then
			upperA, elbowA = math.rad(90), 0 -- gun arm up
		elseif flyer then
			upperA, elbowA = math.rad(-20), math.rad(-25)
		end
		local upper = shoulder * CFrame.Angles(upperA, 0, 0) * CFrame.new(0, -d.arm * 0.5, 0)
		local elbow = upper * CFrame.new(0, -d.arm * 0.5, 0) * CFrame.Angles(elbowA, 0, 0)
		local lower = elbow * CFrame.new(0, -d.arm * 0.5, 0)
		put("Upper" .. side, upper)
		put("Lower" .. side, lower)
		if side == "R" then
			put("Cannon", lower * CFrame.new(0, -d.arm * 0.4, 0) * CFrame.Angles(math.rad(-90), 0, 0))
			put("Muzzle", lower * CFrame.new(0, -d.arm * 1.3, 0) * CFrame.Angles(math.rad(-90), 0, 0))
		else
			put("Guard", lower * CFrame.new(0, -d.arm * 0.2, -d.limb) * CFrame.Angles(math.rad(90), 0, 0))
		end
		-- legs: hip pivots
		local hip = hips * CFrame.new(sign * d.torsoW * 0.25, -d.torsoH * 0.1, 0)
		local thighA = s * sign * swingA
		local kneeA = math.max(0, -math.cos(body.phase) * sign) * swingA
		if flyer then
			thighA, kneeA = math.rad(-10), math.rad(35)
		elseif cfg.ai == "sentry" then
			thighA, kneeA = math.rad(-20 * sign), math.rad(20)
		end
		local thigh = hip * CFrame.Angles(thighA, 0, 0) * CFrame.new(0, -d.leg * 0.5, 0)
		local knee = thigh * CFrame.new(0, -d.leg * 0.5, 0) * CFrame.Angles(kneeA, 0, 0)
		local shin = knee * CFrame.new(0, -d.leg * 0.5, 0)
		put("Thigh" .. side, thigh)
		put("Shin" .. side, shin)
		put(
			"Jet" .. side,
			shin * CFrame.new(0, -d.leg * 0.5 - d.limb * 0.6 + math.sin(now * 30 + k) * 0.05, 0)
		)
	end
	put("Base", root * CFrame.new(0, -d.h * 0.5 + 0.3, 0))
	put("Bubble", torsoC)
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
			body.yaw = rb.yaw
		end
		local moved = Vector3.new(pos.X - body.pos.X, 0, pos.Z - body.pos.Z)
		body.speed = body.speed + (moved.Magnitude / math.max(dt, 1e-3) - body.speed) * math.min(1, dt * 8)
		body.pos = pos
		body.yaw =
			lerpAngle(body.yaw, lerpAngle(ra.yaw, rb.yaw, math.clamp(alpha, 0, 1)), math.min(1, dt * 12))
		body.health = rb.health
		body.state = rb.state
		body.flags = rb.flags
		body.fill.Size = UDim2.fromScale(rb.health, 1)
		if body.flashUntil > 0 and now >= body.flashUntil then
			body.flashUntil = 0
			body.lastFlags = -1
		end
		applyFlags(body)
		pose(body, id, now, dt, partList, cframes)
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
