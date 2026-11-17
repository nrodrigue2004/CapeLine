-- EnemyRenderer: draws the server's enemies from Enemy.Delta (10 Hz). Positions are buffered and drawn
-- 100 ms in the past, interpolated between snapshots, so 10 Hz looks smooth. Bodies are pooled and their
-- roots moved with one BulkMoveTo a frame; only the nearest `enemiesDrawn` (device preset) are shown.
-- Every enemy is a superhuman android (nate, 2026-11-16: "more humanoid, Terminator style") on the same
-- blocky R15 rig as the heroes (nate, 2026-11-16: "literally everyone should be r15. enemies too"; NpcRig):
-- the 15 R15 parts are its synthetic shell (uniform, cartoon skin, gloves and boots), with hair, a chest mark,
-- glowing eyes and a cape on elites, and inside them a metal endoskeleton fixed to the same parts (spine,
-- ribs, a glowing core, skull, jaw and eyes, bones, elbows and knees). The shell breaks off part by part with
-- chips and sparks as health drops (Shared.RobotDamage: limbs, hands and feet, then the torso, the head
-- last), the same on every device. Each robot's build (slim, normal, heavy) takes the creator's Small, Medium
-- or Large proportions (BodyShape), scaled to its height.
-- The rig is posed in code on its R15 joints: walk cycles from speed, aiming arms while attacking, a raised
-- slam on a windup, a tumble when knocked up, a wobble when stunned, and see-through while cloaked. Far
-- robots pose every few frames. Status flags from the server tint and mark the body: ice blue when slowed or
-- rooted, a spinning ring when stunned, a bubble or a guard plate when shielded.
-- Art: the R15 parts use the hero meshes (ReplicatedStorage.Art.Hero) once imported; the endoskeleton and the
-- extras use the Blender robot meshes in ReplicatedStorage.Art.Robots (art/blender/robots.py, uploaded by
-- nate, art/models/Robots.rbxm mapped by Rojo), each a clone sized by Config.ArtFit; a piece with no mesh
-- stays a plain part. The animations are still posed in code (PLACEHOLDER until real R15 animations).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local EnemyBuffer = require(Shared:WaitForChild("EnemyBuffer"))
local Status = require(Shared:WaitForChild("Status"))
local Rng = require(Shared:WaitForChild("Rng"))
local RobotDamage = require(Shared:WaitForChild("RobotDamage"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))

local QualityController = require(script.Parent.QualityController)
local DebrisBudget = require(script.Parent.Parent.Fx.DebrisBudget)

local EnemyRenderer = {}

local DELAY = 0.1
local BITS = Status.BITS
local ATTACK = 3
local snapshots: { { t: number, rows: { [number]: any } } } = {}
local lastSeq = 0
local frame = 0

local byType: { [number]: any } = {}
local kindByType: { [number]: string } = {}
for _, kind in Config.Enemies.order do
	local cfg = Config.Enemies[kind]
	byType[cfg.typeId] = cfg
	kindByType[cfg.typeId] = kind
end

-- Which look robots wear (Config.NpcLooks.style; the Dev panel "Robots:" button cycles it to compare)
local NL = Config.NpcLooks
local style: string = NL.style
local HAIR_SLOTS = 3 -- a Roblox-look robot carries up to this many of its kind's hairs and shows one
-- the shared faces that are uploaded: { human image, turned image } (a missing turned id keeps the human face)
local upFaces: { { string } } = {}
for _, fname in NL.faceOrder do
	local f = NL.faces[fname]
	if f and f.human ~= 0 then
		local human = "rbxassetid://" .. f.human
		table.insert(upFaces, { human, if f.turned ~= 0 then "rbxassetid://" .. f.turned else human })
	end
end

type Body = {
	model: Model,
	rig: NpcRig.Rig,
	layout: RigMath.Layout,
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
	look: string?,
	glow: Color3,
	turned: boolean,
	-- the Roblox look (Config.NpcLooks): "roblox", "shell" or "plain"; its clothes Textures by part, the face
	-- decal and its two images, and the hair handles it can show (one picked per robot)
	mode: string,
	clothes: { [string]: { Texture } }?,
	faceDecal: Decal?,
	faces: { string }?,
	hairs: { string },
	-- the uniform images this kind can wear (each version repeated by its odds) and the one shown now
	outfits: { string },
	outfit: string?,
}

-- A kind's uploaded uniform images, each version repeated by its odds (Config.NpcLooks.versionOdds), so a
-- robot's id picks Grunts most often and Elites rarely; empty until any version is uploaded
local function outfitsOf(recipe: any): { string }
	local list: { string } = {}
	if not recipe then
		return list
	end
	for _, v in NL.versions do
		local id = recipe.clothes[v]
		if id and id ~= 0 then
			for _ = 1, NL.versionOdds[v] or 1 do
				table.insert(list, "rbxassetid://" .. id)
			end
		end
	end
	return list
end

local live: { [number]: Body } = {}
local pool: { [number]: { Body } } = {}
local folder: Folder

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local LOOK = Config.Enemies.look
-- shell pieces that go with another piece (the eyes, mask and hair with the head, the chest mark with the
-- upper torso, the belt with the lower torso)
local TIES: { [string]: { string } } = {
	EyeL = { "Head" },
	EyeR = { "Head" },
	Hair1 = { "Head" },
	Hair2 = { "Head" },
	Hair3 = { "Head" },
	IrisL = { "Head" },
	IrisR = { "Head" },
	Mask = { "Head" },
	Hair = { "Head" },
	Emblem = { "UpperTorso" },
	Belt = { "LowerTorso" },
}

-- The Blender robot meshes, found once. A piece takes the mesh named after it, else its unsided name (UpperL
-- uses Upper); Tank2 is a second Tank.
local ArtFit = Config.ArtFit
local artFolder = ReplicatedStorage:FindFirstChild("Art")
local robotArt = artFolder and artFolder:FindFirstChild("Robots")
local ALIAS: { [string]: string } = { Tank2 = "Tank" }
local meshCache: { [string]: MeshPart | false } = {}

local function meshFor(name: string): MeshPart?
	if not robotArt then
		return nil
	end
	local cached = meshCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local key = ALIAS[name] or name
	local found = robotArt:FindFirstChild(key, true)
	local base = string.match(key, "^(.-)[LR]$")
	if not (found and found:IsA("MeshPart")) and base then
		found = robotArt:FindFirstChild(base, true)
	end
	local mesh = if found and found:IsA("MeshPart") then found else nil
	meshCache[name] = mesh or false
	return mesh
end

-- Where meshed pieces sit differently from the plain parts: the hair stands on the head, the cape hangs clear
-- of the back
local HAIR = if meshFor("Hair") then ArtFit.hair else { 0.5, 0.03 }
local CAPE_BACK = if meshFor("Cape") then 0.2 else 0.08

-- the big pieces cast shadows (the shadow setting per preset turns them off on low); small parts never do
local SHADOWS = {
	UpperTorso = true,
	LowerTorso = true,
	Head = true,
	LeftUpperLeg = true,
	RightUpperLeg = true,
	LeftLowerLeg = true,
	RightLowerLeg = true,
	Cape = true,
}

local function newPart(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): BasePart
	local mesh = meshFor(name)
	local p: BasePart
	if mesh then
		local fit = ArtFit.fit[mesh.Name]
		p = mesh:Clone()
		p.Size = if fit then size * Vector3.new(fit[1], fit[2], fit[3]) else size
	else
		local part = Instance.new("Part")
		part.Size = size
		if shape then
			part.Shape = shape
		end
		p = part
	end
	p.Name = name
	p.Color = color
	p.Material = material
	p.CastShadow = SHADOWS[name] == true
	return p
end

-- A remade robot's extra pieces (the hair) from its shell set, Art[look], with textures
local function lookMesh(look: string, name: string): BasePart?
	local f = artFolder and artFolder:FindFirstChild(look)
	local found = f and f:FindFirstChild(name, true)
	if not (found and found:IsA("MeshPart")) then
		return nil
	end
	local p = found:Clone()
	NpcRig.keepLook(p)
	return p
end

-- Each robot kind's rig: the creator build for its body build, scaled so the body is its height
local layouts: { [number]: RigMath.Layout } = {}
local function layoutFor(typeId: number, body: any): RigMath.Layout
	local cached = layouts[typeId]
	if cached then
		return cached
	end
	local factors =
		BodyShape.factors(Config, { gender = 1, build = LOOK.builds[body.build] or 2, height = 3 })
	local base = RigMath.layout(Config.HeroRig, factors, 1)
	local layout = RigMath.layout(Config.HeroRig, factors, body.height / base.height)
	layouts[typeId] = layout
	return layout
end

local SIDES = { { "Left", "L", -1 }, { "Right", "R", 1 } }

-- One robot: the R15 rig as the superhuman shell (uniform, skin, gloves, boots, hair, chest mark, cape on
-- elites) that breaks off with damage, and inside it the metal endoskeleton (spine, ribs, glowing core,
-- skull and eyes, bones, joints).
local function makeRobot(typeId: number): Body
	local cfg = byType[typeId] or Config.Enemies.SparkDrone
	local body = cfg.body
	local h = body.height
	local metal = rgb(LOOK.endo):Lerp(rgb(body.metal), 0.35)
	local dark = rgb(body.metal):Lerp(Color3.new(0, 0, 0), 0.45)
	local eye = rgb(body.eye)
	local suit = rgb(body.suit or body.metal)
	local trim = rgb(body.trim or body.eye)
	local skin = rgb(LOOK.skins[1])
	local layout = layoutFor(typeId, body)
	local M, N = Enum.Material.Metal, Enum.Material.Neon
	local SKIN = Enum.Material.SmoothPlastic
	-- the shell: suit on the torso, upper arms and thighs, trim for gloves and boots (skin and hair colours
	-- are picked per robot in assign)
	local colors: { [string]: Color3 } = { Head = skin, UpperTorso = suit, LowerTorso = suit }
	for _, side in SIDES do
		local s = side[1]
		colors[s .. "UpperArm"] = suit
		colors[s .. "LowerArm"] = trim
		colors[s .. "Hand"] = trim
		colors[s .. "UpperLeg"] = suit
		colors[s .. "LowerLeg"] = trim
		colors[s .. "Foot"] = trim
	end
	local set = BodyShape.setKey(Config, { gender = 1, build = LOOK.builds[body.build] or 2 })
	-- the look (nate is trying both in game, 2026-11-17): "roblox" = a plain Roblox character in classic
	-- clothes with a Roblox face and catalog hair (Config.NpcLooks, once its images are uploaded); "shell" =
	-- the Blender superhero shell set (overhaul plan step 3: a face, a fitted suit with a chest emblem, gloves,
	-- boots and a belt baked in) once imported; else the plain look
	local recipe = NL.robots[kindByType[typeId] or ""]
	local outfits = outfitsOf(recipe)
	local hasRoblox = #outfits > 0 and #upFaces > 0
	local hasShell = body.art ~= nil and NpcRig.meshes(set, body.art) ~= nil
	local mode = if style == "roblox"
		then (if hasRoblox then "roblox" else "plain")
		elseif style == "shell" then (if hasShell then "shell" else "plain")
		elseif style == "plain" then "plain"
		elseif hasRoblox then "roblox"
		elseif hasShell then "shell"
		else "plain"
	local look: string? = if mode == "shell" then body.art else nil
	if mode == "roblox" then
		-- skin everywhere: the clothes image covers the body, the skin shows on the head and where it is clear
		for pname in colors do
			colors[pname] = skin
		end
	end
	local rig = NpcRig.build(layout, cfg.name, colors, SKIN, nil, set, look)
	local model = rig.model
	local parts, names, cols, trans, byName, index = {}, {}, {}, {}, {}, {}
	local function register(name: string, p: BasePart)
		table.insert(parts, p)
		table.insert(names, name)
		table.insert(cols, p.Color)
		table.insert(trans, p.Transparency)
		byName[name] = p
		index[name] = #parts
	end
	for _, pname in BodyShape.PARTS do
		local p = rig.parts[pname]
		p.CastShadow = SHADOWS[pname] == true
		register(pname, p)
	end
	local function add(
		name: string,
		parent: string,
		c0: CFrame,
		size: Vector3,
		color: Color3,
		material: Enum.Material,
		shape: Enum.PartType?,
		transparency: number?,
		joint: string?,
		c1: CFrame?
	): BasePart
		local p = newPart(name, size, color, material, shape)
		p.Transparency = transparency or 0
		NpcRig.fix(rig, parent, p, c0, joint, c1)
		register(name, p)
		return p
	end
	local function size(part: string): Vector3
		return rig.parts[part].Size
	end
	local UT, LT, HD = size("UpperTorso"), size("LowerTorso"), size("Head")
	local I = CFrame.identity
	-- the endoskeleton (always there; seen as the shell breaks)
	add(
		"Ribs",
		"UpperTorso",
		CFrame.new(0, UT.Y * 0.05, 0),
		UT * Vector3.new(0.72, 0.78, 0.6),
		dark,
		Enum.Material.DiamondPlate
	)
	add(
		"Spine",
		"UpperTorso",
		CFrame.new(0, -UT.Y * 0.05, UT.Z * 0.32),
		Vector3.new(UT.Z * 0.22, UT.Y * 0.95, UT.Z * 0.22),
		metal,
		M
	)
	add(
		"Core",
		"UpperTorso",
		CFrame.new(0, UT.Y * 0.1, -UT.Z * 0.3 - 0.04),
		Vector3.new(UT.X * 0.26, UT.X * 0.26, 0.12),
		eye,
		N
	)
	add("Pelvis", "LowerTorso", I, LT * Vector3.new(0.8, 0.85, 0.8), dark, M)
	add("Skull", "Head", I, HD * 0.78, metal, M)
	add(
		"Jaw",
		"Head",
		CFrame.new(0, -HD.Y * 0.3, -HD.Z * 0.1),
		HD * Vector3.new(0.5, 0.16, 0.5),
		dark,
		M,
		nil,
		nil,
		"Jaw"
	)
	add(
		"Eyes",
		"Head",
		CFrame.new(0, HD.Y * 0.06, -HD.Z * 0.39 - 0.02),
		Vector3.new(HD.X * 0.55, HD.Y * 0.1, 0.06),
		eye,
		N
	)
	for _, side in SIDES do
		local s, sl = side[1], side[2]
		local ua, la, hand = size(s .. "UpperArm"), size(s .. "LowerArm"), size(s .. "Hand")
		local ul, ll, foot = size(s .. "UpperLeg"), size(s .. "LowerLeg"), size(s .. "Foot")
		add("Upper" .. sl, s .. "UpperArm", I, ua * Vector3.new(0.45, 0.94, 0.45), metal, M)
		add("Lower" .. sl, s .. "LowerArm", I, la * Vector3.new(0.42, 0.94, 0.42), metal, M)
		add(
			"Elbow" .. sl,
			s .. "LowerArm",
			CFrame.new(0, la.Y * 0.5, 0),
			Vector3.one * la.X * 0.6,
			dark,
			M,
			Enum.PartType.Ball
		)
		add("Hand" .. sl, s .. "Hand", I, hand * 0.7, metal, M)
		add("Thigh" .. sl, s .. "UpperLeg", I, ul * Vector3.new(0.5, 0.94, 0.5), metal, M)
		add("Shin" .. sl, s .. "LowerLeg", I, ll * Vector3.new(0.45, 0.94, 0.45), metal, M)
		add(
			"Knee" .. sl,
			s .. "LowerLeg",
			CFrame.new(0, ll.Y * 0.5, 0),
			Vector3.one * ll.X * 0.65,
			dark,
			M,
			Enum.PartType.Ball
		)
		add("Foot" .. sl, s .. "Foot", I, foot * 0.7, metal, M)
	end
	-- the shell's extras (the remade suit and the Roblox clothes have their own belt and chest emblem)
	if mode == "plain" then
		add(
			"Belt",
			"LowerTorso",
			CFrame.new(0, LT.Y * 0.3, 0),
			LT * Vector3.new(1.03, 0.45, 1.03),
			trim,
			SKIN
		)
		add(
			"Emblem",
			"UpperTorso",
			CFrame.new(0, UT.Y * 0.18, -UT.Z * 0.5 - 0.03) * CFrame.Angles(0, 0, math.rad(45)),
			Vector3.new(UT.X * 0.24, UT.X * 0.24, 0.06),
			trim,
			SKIN
		)
	end
	local glow = eye:Lerp(Color3.new(1, 1, 1), 0.35)
	-- the hair: a Roblox-look robot carries its kind's Roblox hairs (NpcLookService loads them; one shows per
	-- robot); a remade robot its swept hair mesh (Config.TrooperArt); else a plain cap
	local hairMesh = false
	local hairs: { string } = {}
	local hairFolder = ReplicatedStorage:FindFirstChild("NpcLooks")
	hairFolder = hairFolder and hairFolder:FindFirstChild("Hair")
	if mode == "roblox" and recipe and hairFolder then
		for _, hname in recipe.hair do
			local acc = hairFolder:FindFirstChild(hname)
			if acc and acc:IsA("Accessory") and #hairs < HAIR_SLOTS then
				local slot = "Hair" .. (#hairs + 1)
				local handle = NpcRig.wear(rig, acc, slot)
				if handle then
					register(slot, handle)
					table.insert(hairs, slot)
				end
			end
		end
		hairMesh = #hairs > 0
	end
	if look then
		for xname, x in Config.TrooperArt.extras do
			local p = lookMesh(look, xname)
			if p then
				local ps = size(x.parent)
				local o, sz = x.offset, x.size
				p.Name = xname
				p.Size = ps * Vector3.new(sz[1], sz[2], sz[3])
				p.Color = rgb(LOOK.hair[1])
				p.Material = SKIN
				p.CastShadow = false
				NpcRig.fix(rig, x.parent, p, CFrame.new(ps * Vector3.new(o[1], o[2], o[3])))
				register(xname, p)
				hairMesh = hairMesh or xname == "Hair"
			end
		end
	end
	if not hairMesh then
		add(
			"Hair",
			"Head",
			CFrame.new(0, HD.Y * HAIR[1], HD.Z * HAIR[2]),
			HD * Vector3.new(1.06, 0.3, 1.06),
			rgb(LOOK.hair[1]),
			SKIN
		)
	end
	-- the face: a Roblox-look robot wears a face decal (swapped to the turned face in applyFlags); the others
	-- get human eyes (the remade face's brows sit just above them): the white and an iris that glows once the
	-- robot turns
	local clothes: { [string]: { Texture } }? = nil
	local faceDecal: Decal? = nil
	if mode == "roblox" and recipe then
		clothes = NpcRig.dress(rig, outfits[1], NL.offsetSign) -- assign picks this robot's uniform version
		faceDecal = NpcRig.face(rig, upFaces[1][1]) -- assign picks this robot's face
	end
	local eyeSides: { any } = if mode == "roblox" then {} else SIDES
	for _, side in eyeSides do
		local at = CFrame.new(side[3] * HD.X * 0.2, HD.Y * 0.06, -HD.Z * 0.5 - 0.02)
		add("Eye" .. side[2], "Head", at, Vector3.new(HD.X * 0.22, HD.Y * 0.09, 0.05), rgb(LOOK.sclera), SKIN)
		add(
			"Iris" .. side[2],
			"Head",
			at * CFrame.new(-side[3] * HD.X * 0.015, 0, -0.02),
			Vector3.new(HD.X * 0.09, HD.Y * 0.09, 0.05),
			rgb(LOOK.irises[1]),
			SKIN
		)
	end
	if body.cape then
		local capeH = (UT.Y + LT.Y) * 1.25
		add(
			"Cape",
			"UpperTorso",
			CFrame.new(0, UT.Y * 0.5, UT.Z * 0.5 + CAPE_BACK),
			Vector3.new(UT.X * 0.95, capeH, 0.12),
			rgb(body.cape),
			Enum.Material.Fabric,
			nil,
			nil,
			"Cape",
			CFrame.new(0, capeH * 0.5, 0)
		)
	end
	if body.jets then
		local jet = if body.jetColor then rgb(body.jetColor) else Color3.fromRGB(255, 170, 70)
		for _, side in SIDES do
			local foot = size(side[1] .. "Foot")
			local jh = size(side[1] .. "LowerLeg").X * 0.9
			add(
				"Jet" .. side[2],
				side[1] .. "Foot",
				CFrame.new(0, -foot.Y * 0.5 - jh * 0.5, 0),
				Vector3.new(foot.X * 0.6, jh, foot.Z * 0.6),
				jet,
				N
			)
		end
	end
	-- sea robots: a glass diving helmet and an air tank (PLACEHOLDER ART)
	if body.helmet then
		add(
			"Helmet",
			"Head",
			I,
			Vector3.one * HD.Y * 1.45,
			Color3.fromRGB(190, 230, 255),
			Enum.Material.Glass,
			Enum.PartType.Ball,
			0.55
		)
		add("Collar", "Head", CFrame.new(0, -HD.Y * 0.55, 0), HD * Vector3.new(1.25, 0.18, 1.25), trim, M)
	end
	if body.tank then
		local tw = UT.X * 0.16
		for k, name in { "Tank", "Tank2" } do
			add(
				name,
				"UpperTorso",
				CFrame.new((if k == 1 then -1 else 1) * UT.X * 0.2, 0, UT.Z * 0.5 + tw * 0.5),
				Vector3.new(tw, UT.Y * 0.85, tw),
				trim:Lerp(dark, 0.3),
				M
			)
		end
	end
	if body.mask then
		add(
			"Mask",
			"Head",
			CFrame.new(0, HD.Y * 0.08, 0),
			HD * Vector3.new(1.05, 0.32, 1.05),
			Color3.fromRGB(25, 25, 30),
			SKIN
		)
		add(
			"Bag",
			"UpperTorso",
			CFrame.new(0, 0, UT.Z * 0.85),
			UT * Vector3.new(0.6, 0.75, 0.7),
			Color3.fromRGB(120, 90, 50),
			Enum.Material.Fabric
		)
	end
	if body.planted then
		local la = size("RightLowerArm")
		local down = CFrame.Angles(math.rad(-90), 0, 0)
		add(
			"Cannon",
			"RightLowerArm",
			CFrame.new(0, -la.Y * 0.4, 0) * down,
			Vector3.new(la.X * 1.5, la.X * 1.5, la.Y * 1.8),
			dark,
			M
		)
		add(
			"Muzzle",
			"RightLowerArm",
			CFrame.new(0, -la.Y * 1.3, 0) * down,
			Vector3.new(la.X * 0.9, la.X * 0.9, 0.3),
			eye,
			N
		)
		add(
			"Base",
			"HumanoidRootPart",
			CFrame.new(0, -layout.ground + 0.3, 0),
			Vector3.new(UT.X * 1.6, 0.6, UT.X * 1.6),
			dark,
			Enum.Material.DiamondPlate
		)
		add(
			"Bubble",
			"UpperTorso",
			I,
			Vector3.one * h * 1.2,
			Color3.fromRGB(120, 220, 255),
			Enum.Material.ForceField,
			Enum.PartType.Ball,
			1
		)
	end
	if body.shield then
		local la = size("LeftLowerArm")
		add(
			"Guard",
			"LeftLowerArm",
			CFrame.new(0, -la.Y * 0.2, -la.Z) * CFrame.Angles(math.rad(90), 0, 0),
			Vector3.new(UT.X * 1.1, UT.Y * 1.4, 0.35),
			Color3.fromRGB(200, 210, 230),
			N,
			nil,
			0.25
		)
	end
	add(
		"Stun",
		"Head",
		CFrame.new(0, HD.Y * 0.9, 0),
		Vector3.new(0.15, HD.Y * 1.6, HD.Y * 1.6),
		Color3.fromRGB(255, 230, 90),
		N,
		Enum.PartType.Cylinder,
		1,
		"Stun",
		CFrame.Angles(0, 0, math.rad(-90))
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

	local head = rig.parts.Head
	local bar = Instance.new("BillboardGui")
	bar.Size = UDim2.fromScale(math.max(3, UT.X * 1.6), 0.35)
	bar.StudsOffset = Vector3.new(0, HD.Y + 0.6, 0)
	bar.AlwaysOnTop = true
	bar.Enabled = false
	bar.Adornee = head
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
	bar.Parent = head
	return {
		model = model,
		rig = rig,
		layout = layout,
		parts = parts,
		names = names,
		baseColors = cols,
		baseTransparency = trans,
		byName = byName,
		index = index,
		bar = bar,
		fill = fill,
		typeId = typeId,
		cfg = cfg,
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
		look = look,
		glow = glow,
		turned = false,
		mode = mode,
		clothes = clothes,
		faceDecal = faceDecal,
		faces = nil,
		hairs = hairs,
		outfits = outfits,
		outfit = if mode == "roblox" then outfits[1] else nil,
	}
end

-- Give a pooled body to one robot id: its break order, skin and hair (the same on every device)
local function assign(body: Body, id: number)
	body.order = RobotDamage.order(id, body.shell, LOOK.spread)
	body.broken = {}
	body.brokenN = -1 -- set without chips on the first frame (a robot can arrive already hurt)
	body.turned = false
	body.sparks.Enabled = false
	local h = Rng.hash(id, 3301)
	local skin = rgb(LOOK.skins[h % #LOOK.skins + 1])
	local hair = rgb(LOOK.hair[(h // 7) % #LOOK.hair + 1])
	local iris = rgb(LOOK.irises[(h // 49) % #LOOK.irises + 1])
	local paint: { [string]: Color3 } = { Head = skin, Hair = hair, IrisL = iris, IrisR = iris }
	if body.mode == "roblox" then
		for _, pname in BodyShape.PARTS do
			paint[pname] = skin
		end
		-- one of the shared faces and one of its Roblox hairs, picked by the id like the skin
		if #upFaces > 0 then
			body.faces = upFaces[(h // 2401) % #upFaces + 1]
		end
		-- the uniform's version (Grunt, Veteran or Elite at Config.NpcLooks.versionOdds)
		local outfit = if #body.outfits > 0 then body.outfits[(h // 16807) % #body.outfits + 1] else nil
		if outfit and outfit ~= body.outfit and body.clothes then
			body.outfit = outfit
			for _, list in body.clothes do
				for _, tex in list do
					tex.Texture = outfit
				end
			end
		end
		local pick = if #body.hairs > 0 then body.hairs[(h // 343) % #body.hairs + 1] else nil
		for _, slot in body.hairs do
			local i = body.index[slot]
			body.baseTransparency[i] = if slot == pick then 0 else 1
		end
	end
	for name, color in paint do
		local i = body.index[name]
		if i then
			body.baseColors[i] = color
			body.parts[i].Color = color
		end
	end
	NpcRig.rest(body.rig)
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
	IrisL = true,
	IrisR = true,
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
	-- the robot turns (and stays turned) the first time it winds up an attack or its shell starts to break
	body.turned = body.turned or windup or body.brokenN > 0
	local turned = body.turned
	for i, p in body.parts do
		local name = body.names[i]
		local color = body.baseColors[i]
		local t = body.baseTransparency[i]
		if cold and not NEON_KEEP[name] then
			color = color:Lerp(ICE, 0.6)
		end
		if name == "IrisL" or name == "IrisR" then
			if turned then
				color = if windup then Color3.fromRGB(255, 40, 40) else body.glow
			end
			p.Material = if turned then Enum.Material.Neon else Enum.Material.SmoothPlastic
		elseif name == "EyeL" or name == "EyeR" then
			if turned then
				color = rgb(LOOK.turnedSclera)
			end
		elseif windup and name == "Eyes" then
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
			t = if name == "Eyes" or name == "IrisL" or name == "IrisR" then 0.6 else 0.92
		end
		p.Color = color
		p.Transparency = t
		local tex = body.clothes and body.clothes[name]
		if tex then
			for _, x in tex do
				x.Transparency = t
				x.Color3 = if cold then ICE else Color3.new(1, 1, 1)
			end
		end
		if name == "Head" and body.faceDecal and body.faces then
			local d = body.faceDecal
			d.Texture = if turned then body.faces[2] else body.faces[1]
			d.Transparency = t
			d.Color3 = if windup then Color3.fromRGB(255, 110, 110) else Color3.new(1, 1, 1)
		end
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
				local tex = body.clothes and body.clothes[body.names[i]]
				if tex then
					for _, x in tex do
						x.Transparency = 0.6 -- the white flash shows through the clothes
					end
				end
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

-- Switch the look every robot wears ("auto", "roblox", "shell", "plain"; the Dev panel compares them):
-- every drawn and pooled body is rebuilt in the new look on the next frame. Returns the style.
function EnemyRenderer.setStyle(s: string): string
	style = s
	for id, body in live do
		body.model:Destroy()
		live[id] = nil
	end
	for _, list in pool do
		for _, body in list do
			body.model:Destroy()
		end
	end
	table.clear(pool)
	return style
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

-- Pose one robot: its root goes on the BulkMoveTo lists; its R15 joints turn when `joints` is true (near
-- robots every frame, far ones every few frames)
local function pose(
	body: Body,
	id: number,
	now: number,
	dt: number,
	roots: { BasePart },
	cframes: { CFrame },
	joints: boolean
)
	local L = body.layout
	local rig = body.rig
	local cfg = body.cfg
	local flags = body.flags
	local flyer = cfg.ai == "flyer"
	local lifted = bit32.band(flags, BITS.lifted) ~= 0
	local stunned = bit32.band(flags, BITS.stun) ~= 0
	local windup = bit32.band(flags, BITS.windup) ~= 0
	local attacking = body.state == ATTACK
	local swinging = now < body.swingUntil
	local speed = body.speed
	body.phase += dt * math.clamp(speed, 0, 30) * 0.45
	-- e.y is the body centre for ground robots (the soles half its height below) and the hips for flyers
	local root = CFrame.new(body.pos) * CFrame.Angles(0, body.yaw, 0)
	if flyer then
		root *= CFrame.new(0, math.sin(now * 3 + id) * 0.35, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	end
	if lifted then
		root *= CFrame.Angles(math.rad((now * 540) % 360), 0, math.rad(25)) -- tumble
	elseif stunned then
		root *= CFrame.Angles(0, 0, math.rad(math.sin(now * 14) * 10))
	end
	local up = if flyer then L.hip else L.ground - L.height * 0.5
	table.insert(roots, rig.root)
	table.insert(cframes, root * CFrame.new(0, up, 0))
	if not joints then
		return
	end
	local swingA = if flyer or lifted then 0 else math.clamp(speed / 20, 0, 1) * math.rad(40)
	local s = math.sin(body.phase)
	NpcRig.turn(
		rig,
		"Waist",
		if cfg.ai == "sneak" and not attacking then CFrame.Angles(math.rad(-18), 0, 0) else CFrame.identity -- crouched creep
	)
	NpcRig.turn(rig, "Jaw", CFrame.new(0, if attacking or windup then -L.parts.Head.size[2] * 0.06 else 0, 0))
	-- the cape sways with speed
	NpcRig.turn(
		rig,
		"Cape",
		CFrame.Angles(math.rad(8 + math.clamp(speed, 0, 20) * 1.6 + math.sin(now * 2.2 + id) * 3), 0, 0)
	)
	if stunned then
		NpcRig.turn(rig, "Stun", CFrame.Angles(0, now * 6, 0))
	end
	for _, side in SIDES do
		local name, sign = side[1], side[3]
		-- arms: aiming forward when attacking, raised overhead on a windup; elbows bend forward
		local upperA, elbowA = -s * sign * swingA * 0.8, math.rad(15)
		if windup then
			upperA, elbowA = math.rad(160), math.rad(20)
		elseif swinging then
			upperA, elbowA = math.rad(if sign > 0 then -95 else 30), 0
		elseif attacking and (flyer or cfg.ai == "thief" or cfg.ai == "sentry") and sign > 0 then
			upperA, elbowA = math.rad(90), 0 -- gun arm up
		elseif flyer then
			upperA, elbowA = math.rad(-20), math.rad(25)
		end
		NpcRig.turn(rig, name .. "Shoulder", CFrame.Angles(upperA, 0, 0))
		NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(elbowA, 0, 0))
		-- legs: knees bend back
		local thighA = s * sign * swingA
		local kneeA = math.max(0, -math.cos(body.phase) * sign) * swingA
		if flyer then
			thighA, kneeA = math.rad(-10), math.rad(35)
		elseif cfg.ai == "sentry" then
			thighA, kneeA = math.rad(-20 * sign), math.rad(20)
		end
		NpcRig.turn(rig, name .. "Hip", CFrame.Angles(thighA, 0, 0))
		NpcRig.turn(rig, name .. "Knee", CFrame.Angles(-kneeA, 0, 0))
	end
end

local lastRender = os.clock()
local function render()
	local now = os.clock()
	local dt = math.min(0.1, now - lastRender)
	lastRender = now
	frame += 1
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

	local roots, cframes = {}, {}
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
		local dist = (pos - cam).Magnitude
		updateShell(body, dist < LOOK.chipRange)
		applyFlags(body)
		pose(body, id, now, dt, roots, cframes, dist < LOOK.poseNear or (frame + id) % LOOK.poseEvery == 0)
	end
	if #roots > 0 then
		Workspace:BulkMoveTo(roots, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EnemyRenderer.init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = Workspace
	Net.listen("EnemyDelta", onDelta)
	RunService.RenderStepped:Connect(FrameProf.wrap("EnemyRenderer", render))
end

return EnemyRenderer
