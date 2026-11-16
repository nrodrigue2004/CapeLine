-- EnemyRenderer: draws the server's enemies from Enemy.Delta (10 Hz). Positions are buffered and drawn
-- 100 ms in the past, interpolated between snapshots, so 10 Hz looks smooth. Bodies are pooled and moved
-- with one BulkMoveTo a frame; only the nearest `enemiesDrawn` (device preset) are shown.
-- Every enemy is a superhuman android (nate, 2026-11-16: "more humanoid, Terminator style"): a synthetic shell
-- (uniform, cartoon skin and hair, chest mark, a cape on elites) over a metal endoskeleton (spine, ribs, a
-- glowing core, skull, glowing eyes, bones and joints). The shell breaks off in panels with chips and sparks
-- as health drops (Shared.RobotDamage: limbs, then chest and belly, the face last), the same on every device.
-- The rig is animated in code: walk cycles from speed, aiming arms while attacking, a
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
local Rng = require(Shared:WaitForChild("Rng"))
local RobotDamage = require(Shared:WaitForChild("RobotDamage"))

local QualityController = require(script.Parent.QualityController)
local DebrisBudget = require(script.Parent.Parent.Fx.DebrisBudget)

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
	index: { [string]: number },
	bar: BillboardGui,
	fill: Frame,
	typeId: number,
	cfg: any,
	dims: any,
	metal: Color3,
	shell: { RobotDamage.Piece },
	sparks: ParticleEmitter,
	order: { string },
	broken: { [string]: boolean },
	brokenN: number,
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

-- Body proportions by build, scaled to the robot's height: human proportions with a superhero's shoulders
local BUILDS = {
	slim = { torsoW = 0.28, torsoD = 0.17, limb = 0.1, head = 0.15 },
	normal = { torsoW = 0.32, torsoD = 0.2, limb = 0.115, head = 0.15 },
	heavy = { torsoW = 0.42, torsoD = 0.27, limb = 0.155, head = 0.13 },
}

local LOOK = Config.Enemies.look
-- shell pieces that hide with another piece (eyes with their half of the face, the chest mark with the chest)
local TIES: { [string]: { string } } = {
	EyeL = { "FaceL" },
	EyeR = { "FaceR" },
	Mask = { "FaceR" },
	Emblem = { "ChestL", "ChestR" },
	Belt = { "Belly" },
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

-- One robot: a metal endoskeleton (spine, ribs, glowing core, skull and eyes, bones, joints) and over it the
-- superhuman shell (uniform, skin, hair, chest mark, cape on elites) that breaks off with damage.
local function makeRobot(typeId: number): Body
	local cfg = byType[typeId] or Config.Enemies.SparkDrone
	local body = cfg.body
	local b = BUILDS[body.build] or BUILDS.normal
	local h = body.height
	local metal = rgb(LOOK.endo):Lerp(rgb(body.metal), 0.35)
	local dark = rgb(body.metal):Lerp(Color3.new(0, 0, 0), 0.45)
	local eye = rgb(body.eye)
	local suit = rgb(body.suit or body.metal)
	local trim = rgb(body.trim or body.eye)
	local model = Instance.new("Model")
	model.Name = cfg.name
	local dims = {
		h = h,
		torsoH = h * 0.3,
		torsoW = h * b.torsoW,
		torsoD = h * b.torsoD,
		head = h * b.head,
		limb = h * b.limb,
		arm = h * 0.19, -- each of the upper and lower arm
		leg = h * 0.235, -- each of the thigh and shin
	}
	local parts, names, colors, trans, byName, index = {}, {}, {}, {}, {}, {}
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
		index[name] = #parts
		return p
	end
	local d = dims
	local M, N = Enum.Material.Metal, Enum.Material.Neon
	local SKIN = Enum.Material.SmoothPlastic
	-- the endoskeleton (always there; seen as the shell breaks)
	add("Spine", Vector3.new(d.limb * 0.5, d.torsoH * 0.9, d.limb * 0.5), metal, M)
	add(
		"Ribs",
		Vector3.new(d.torsoW * 0.78, d.torsoH * 0.72, d.torsoD * 0.6),
		dark,
		Enum.Material.DiamondPlate
	)
	add("Core", Vector3.new(d.torsoW * 0.3, d.torsoW * 0.3, 0.12), eye, N)
	add("Pelvis", Vector3.new(d.torsoW * 0.8, d.torsoH * 0.28, d.torsoD * 0.9), suit:Lerp(dark, 0.3), SKIN)
	add("Skull", Vector3.one * d.head * 0.78, metal, M)
	add("Jaw", Vector3.new(d.head * 0.5, d.head * 0.18, d.head * 0.5), dark, M)
	add("Eyes", Vector3.new(d.head * 0.6, d.head * 0.12, 0.08), eye, N)
	for _, side in { "L", "R" } do
		add("Upper" .. side, Vector3.new(d.limb * 0.5, d.arm * 0.94, d.limb * 0.5), metal, M)
		add("Lower" .. side, Vector3.new(d.limb * 0.45, d.arm * 0.94, d.limb * 0.45), metal, M)
		add("Thigh" .. side, Vector3.new(d.limb * 0.55, d.leg * 0.94, d.limb * 0.55), metal, M)
		add("Shin" .. side, Vector3.new(d.limb * 0.5, d.leg * 0.94, d.limb * 0.5), metal, M)
		add("Elbow" .. side, Vector3.one * d.limb * 0.7, dark, M, Enum.PartType.Ball)
		add("Knee" .. side, Vector3.one * d.limb * 0.75, dark, M, Enum.PartType.Ball)
	end
	-- the shell: uniform, cartoon skin and hair (skin and hair colours are picked per robot in assign)
	local skin = rgb(LOOK.skins[1])
	add("ChestL", Vector3.new(d.torsoW * 0.5, d.torsoH * 0.6, d.torsoD), suit, SKIN)
	add("ChestR", Vector3.new(d.torsoW * 0.5, d.torsoH * 0.6, d.torsoD), suit, SKIN)
	add("Belly", Vector3.new(d.torsoW * 0.9, d.torsoH * 0.4, d.torsoD * 0.95), suit, SKIN)
	add("Belt", Vector3.new(d.torsoW * 0.94, d.torsoH * 0.1, d.torsoD * 1.02), trim, SKIN)
	add("Emblem", Vector3.new(d.torsoW * 0.26, d.torsoW * 0.26, 0.08), trim, SKIN)
	add("FaceL", Vector3.new(d.head * 0.5, d.head * 1.1, d.head), skin, SKIN)
	add("FaceR", Vector3.new(d.head * 0.5, d.head * 1.1, d.head), skin, SKIN)
	add("Hair", Vector3.new(d.head * 1.06, d.head * 0.3, d.head * 1.06), rgb(LOOK.hair[1]), SKIN)
	local glow = eye:Lerp(Color3.new(1, 1, 1), 0.35)
	add("EyeL", Vector3.new(d.head * 0.26, d.head * 0.1, 0.06), glow, N)
	add("EyeR", Vector3.new(d.head * 0.26, d.head * 0.1, 0.06), glow, N)
	for _, side in { "L", "R" } do
		add("ShUpper" .. side, Vector3.new(d.limb, d.arm, d.limb), suit, SKIN)
		add("ShLower" .. side, Vector3.new(d.limb * 0.92, d.arm, d.limb * 0.92), trim, SKIN) -- gloves
		add("ShThigh" .. side, Vector3.new(d.limb * 1.1, d.leg, d.limb * 1.1), suit, SKIN)
		add("ShShin" .. side, Vector3.new(d.limb, d.leg, d.limb * 1.15), trim, SKIN) -- boots
	end
	if body.cape then
		add("Cape", Vector3.new(d.torsoW * 0.95, d.torsoH * 1.7, 0.12), rgb(body.cape), Enum.Material.Fabric)
	end
	if body.jets then
		local jet = if body.jetColor then rgb(body.jetColor) else Color3.fromRGB(255, 170, 70)
		add("JetL", Vector3.new(d.limb * 0.8, d.limb * 1.6, d.limb * 0.8), jet, N)
		add("JetR", Vector3.new(d.limb * 0.8, d.limb * 1.6, d.limb * 0.8), jet, N)
	end
	-- sea robots: a glass diving helmet and an air tank (PLACEHOLDER ART)
	if body.helmet then
		add(
			"Helmet",
			Vector3.one * d.head * 1.45,
			Color3.fromRGB(190, 230, 255),
			Enum.Material.Glass,
			Enum.PartType.Ball,
			0.55
		)
		add("Collar", Vector3.new(d.head * 1.3, d.head * 0.2, d.head * 1.3), trim, M)
	end
	if body.tank then
		add("Tank", Vector3.new(d.torsoW * 0.32, d.torsoH * 0.85, d.torsoW * 0.32), trim:Lerp(dark, 0.3), M)
		add("Tank2", Vector3.new(d.torsoW * 0.32, d.torsoH * 0.85, d.torsoW * 0.32), trim:Lerp(dark, 0.3), M)
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
		add("Cannon", Vector3.new(d.limb * 1.6, d.limb * 1.6, d.arm * 1.8), dark, M)
		add("Muzzle", Vector3.new(d.limb * 1.0, d.limb * 1.0, 0.3), eye, N)
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
			N,
			nil,
			0.25
		)
	end
	add(
		"Stun",
		Vector3.new(0.15, d.head * 1.6, d.head * 1.6),
		Color3.fromRGB(255, 230, 90),
		N,
		Enum.PartType.Cylinder,
		1
	)
	-- the exposed core sparks when the robot is nearly beaten
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "CoreSparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 140, 50))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.12, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.45)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Rate = 10
	sparks.Enabled = false
	sparks.Parent = byName.Core

	-- the shell pieces this body has, by break tier
	local shell = {}
	for name, tier in LOOK.tiers do
		if byName[name] then
			table.insert(shell, { name = name, tier = tier })
		end
	end
	table.sort(shell, function(x, y)
		return x.name < y.name
	end)

	local bar = Instance.new("BillboardGui")
	bar.Size = UDim2.fromScale(math.max(3, d.torsoW * 2), 0.35)
	bar.StudsOffset = Vector3.new(0, d.head + 0.8, 0)
	bar.AlwaysOnTop = true
	bar.Enabled = false
	bar.Adornee = byName.Skull
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
	bar.Parent = byName.Skull
	return {
		model = model,
		parts = parts,
		names = names,
		baseColors = colors,
		baseTransparency = trans,
		byName = byName,
		index = index,
		bar = bar,
		fill = fill,
		typeId = typeId,
		cfg = cfg,
		dims = dims,
		metal = metal,
		shell = shell,
		sparks = sparks,
		order = {},
		broken = {},
		brokenN = 0,
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

-- Give a pooled body to one robot id: its break order, skin and hair (the same on every device)
local function assign(body: Body, id: number)
	body.order = RobotDamage.order(id, body.shell, LOOK.spread)
	body.broken = {}
	body.brokenN = -1 -- set without chips on the first frame (a robot can arrive already hurt)
	body.sparks.Enabled = false
	local h = Rng.hash(id, 3301)
	local skin = rgb(LOOK.skins[h % #LOOK.skins + 1])
	local hair = rgb(LOOK.hair[(h // 7) % #LOOK.hair + 1])
	for name, color in { FaceL = skin, FaceR = skin, Hair = hair } do
		local i = body.index[name]
		if i then
			body.baseColors[i] = color
			body.parts[i].Color = color
		end
	end
	body.lastFlags = -1
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
	body.sparks.Enabled = false
	pool[body.typeId] = pool[body.typeId] or {}
	table.insert(pool[body.typeId], body)
end

local ICE = Color3.fromRGB(170, 225, 255)
local NEON_KEEP = {
	Eyes = true,
	EyeL = true,
	EyeR = true,
	Core = true,
	JetL = true,
	JetR = true,
	Muzzle = true,
	Guard = true,
	Stun = true,
	Bubble = true,
}

local function gone(body: Body, name: string): boolean
	if body.broken[name] then
		return true
	end
	local ties = TIES[name]
	if ties then
		for _, t in ties do
			if body.broken[t] then
				return true
			end
		end
	end
	return false
end

-- Colours and transparency change only when the flags or the broken shell change (cheap)
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
		if windup and (name == "Eyes" or name == "EyeL" or name == "EyeR") then
			color = Color3.fromRGB(255, 40, 40)
		end
		if name == "Stun" then
			t = if stun then 0.2 else 1
		elseif name == "Bubble" then
			t = if shield then 0.55 else 1
		elseif name == "Guard" then
			t = if shield then 0.25 else 1
		elseif gone(body, name) then
			t = 1
		elseif cloak then
			t = if name == "Eyes" or name == "EyeL" or name == "EyeR" then 0.6 else 0.92
		end
		p.Color = color
		p.Transparency = t
	end
	body.bar.Enabled = body.health < 0.999 and not cloak
end

-- A shell piece breaks off: two or three chips of it fly and sparks pop (local, inside the debris budget)
local function chip(body: Body, name: string)
	local src = body.byName[name]
	if not src then
		return
	end
	local n = DebrisBudget.lease(4, 1.4)
	local cf = src.CFrame
	for k = 1, n do
		local p = Instance.new("Part")
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local out = (math.random() - 0.5) * 2
		if k == n then
			-- a spark
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(255, 200, 90)
			p.Size = Vector3.new(0.15, 0.15, 0.7)
		else
			p.Material = src.Material
			p.Color = body.baseColors[body.index[name]]
			p.Size = src.Size * Vector3.new(0.4 + math.random() * 0.2, 0.3 + math.random() * 0.2, 0.5)
		end
		p.CFrame = cf * CFrame.new(out * src.Size.X * 0.3, (math.random() - 0.5) * src.Size.Y * 0.5, 0)
		p.AssemblyLinearVelocity = (cf.RightVector * out + Vector3.new(0, 0.8 + math.random() * 0.5, 0))
			* (14 + math.random() * 10)
		p.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 8
		p.Parent = folder
		task.delay(1.4, function()
			p:Destroy()
		end)
	end
end

-- Break or restore shell pieces to match the robot's health
local function updateShell(body: Body, near: boolean)
	local spark = body.health < LOOK.sparksBelow and bit32.band(body.flags, BITS.cloak) == 0
	if body.sparks.Enabled ~= spark then
		body.sparks.Enabled = spark
	end
	local n = RobotDamage.count(body.health, #body.order, LOOK.stripBy)
	if n == body.brokenN then
		return
	end
	local first = body.brokenN < 0
	local was = math.max(body.brokenN, 0)
	for i, name in body.order do
		local now = i <= n
		if now and not body.broken[name] and not first and near and i > was then
			chip(body, name)
		end
		(body.broken :: any)[name] = if now then true else nil
	end
	body.brokenN = n
	body.lastFlags = -1
end

function EnemyRenderer.flash(id: number)
	local body = live[id]
	if body then
		body.flashUntil = os.clock() + Config.Fx.hitFlash
		for i, p in body.parts do
			if body.baseTransparency[i] < 1 and not gone(body, body.names[i]) then
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
	local color = body.metal
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
	-- the endoskeleton
	put("Spine", torsoC * CFrame.new(0, 0, d.torsoD * 0.12))
	put("Ribs", torsoC * CFrame.new(0, d.torsoH * 0.1, 0))
	put("Core", torsoC * CFrame.new(0, d.torsoH * 0.12, -d.torsoD * 0.3 - 0.06))
	local neck = torsoC * CFrame.new(0, d.torsoH * 0.5 + d.head * 0.58, 0)
	put("Skull", neck * CFrame.new(0, d.head * 0.05, 0))
	local jawDrop = if attacking or windup then d.head * 0.06 else 0
	put("Jaw", neck * CFrame.new(0, -d.head * 0.36 - jawDrop, -d.head * 0.1))
	put("Eyes", neck * CFrame.new(0, d.head * 0.08, -d.head * 0.39 - 0.02))
	-- the shell
	put("ChestL", torsoC * CFrame.new(-d.torsoW * 0.25, d.torsoH * 0.2, 0))
	put("ChestR", torsoC * CFrame.new(d.torsoW * 0.25, d.torsoH * 0.2, 0))
	put("Belly", torsoC * CFrame.new(0, -d.torsoH * 0.3, 0))
	put("Belt", torsoC * CFrame.new(0, -d.torsoH * 0.44, 0))
	put(
		"Emblem",
		torsoC * CFrame.new(0, d.torsoH * 0.24, -d.torsoD * 0.5 - 0.04) * CFrame.Angles(0, 0, math.rad(45))
	)
	put("FaceL", neck * CFrame.new(-d.head * 0.25, 0, 0))
	put("FaceR", neck * CFrame.new(d.head * 0.25, 0, 0))
	put("Hair", neck * CFrame.new(0, d.head * 0.5, d.head * 0.03))
	put("EyeL", neck * CFrame.new(-d.head * 0.2, d.head * 0.08, -d.head * 0.5 - 0.03))
	put("EyeR", neck * CFrame.new(d.head * 0.2, d.head * 0.08, -d.head * 0.5 - 0.03))
	put("Mask", neck * CFrame.new(0, d.head * 0.08, 0))
	put("Bag", torsoC * CFrame.new(0, 0, d.torsoD * 0.5 + d.torsoD * 0.35))
	put("Helmet", neck * CFrame.new(0, d.head * 0.05, 0))
	put("Collar", neck * CFrame.new(0, -d.head * 0.62, 0))
	put("Tank", torsoC * CFrame.new(-d.torsoW * 0.2, 0, d.torsoD * 0.5 + d.torsoW * 0.18))
	put("Tank2", torsoC * CFrame.new(d.torsoW * 0.2, 0, d.torsoD * 0.5 + d.torsoW * 0.18))
	-- the cape hangs from the shoulders and sways with speed
	local capeA = math.rad(8 + math.clamp(body.speed, 0, 20) * 1.6 + math.sin(now * 2.2 + id) * 3)
	put(
		"Cape",
		torsoC
			* CFrame.new(0, d.torsoH * 0.48, d.torsoD * 0.5 + 0.08)
			* CFrame.Angles(capeA, 0, 0)
			* CFrame.new(0, -d.torsoH * 0.85, 0)
	)
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
		put("ShUpper" .. side, upper)
		put("Elbow" .. side, elbow)
		put("Lower" .. side, lower)
		put("ShLower" .. side, lower)
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
		put("ShThigh" .. side, thigh)
		put("Knee" .. side, knee)
		put("Shin" .. side, shin)
		put("ShShin" .. side, shin)
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
			assign(body, id)
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
		updateShell(body, (pos - cam).Magnitude < LOOK.chipRange)
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
