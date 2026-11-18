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
-- slam on a windup (a Sneak Bot's low coil before its lunge, WP6), a tumble when knocked up, a wobble when stunned, and see-through while cloaked. Far
-- robots pose every few frames. Status flags from the server tint and mark the body: ice blue when slowed or
-- rooted, a spinning ring when stunned, a bubble or a guard plate when shielded.
-- The nine newer kinds (Config.Enemies typeIds 10 to 18) add their own gear from their `body` flags: a riot
-- shield (knocked away with chips while the guard is broken), an officer's cap, a long rifle and a glowing
-- visor, a grenade bandolier and satchel, a medic's backpack (a green plus and a light that pulses while it
-- repairs), a small fast build that crouches and lunges, a Mimic's street clothes, swept jet wings, and a
-- hook launcher arm whose claw is gone while it flies. The second flags byte (EnemyBuffer `extra`,
-- EnemySim.EXTRA) drives the rest: a rallied robot glows gold with a chevron over its head, and a disguised
-- Mimic is drawn as a plain citizen (no robot gear, no health bar, left out of auto-aim) until it shows itself.
-- Art: the R15 parts use the hero meshes (ReplicatedStorage.Art.Hero) once imported; the endoskeleton and the
-- extras use the Blender robot meshes in ReplicatedStorage.Art.Robots (art/blender/robots.py, uploaded by
-- nate, art/models/Robots.rbxm mapped by Rojo), each a clone sized by Config.ArtFit; a piece with no mesh
-- stays a plain part. The animations are still posed in code (PLACEHOLDER until real R15 animations).
-- The famous fakes and the evil twin (nate's lore, build plan step 4; Config.Enemies `fake`, Shared.FakeRules)
-- wear a full hero look on the same rig (LookKit: suit, cape, hair, face, emblem, colours; a twin the look of
-- the player it copies, from EnemyIdentity) with a hero name plate (name and title, no robot tag). Once its
-- health falls to the crack its face cracks to show metal and a glowing eye (Config.NpcLooks.faces' cracked
-- image once uploaded, else a part-built crack overlay on the head; PLACEHOLDER ART), the plate reads FAKE in
-- red, and the rest of the shell breaks off over the health that is left, hero pieces with their body part.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

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
local ClothesMap = require(Shared:WaitForChild("ClothesMap"))
local EnemySim = require(Shared:WaitForChild("EnemySim"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))
local LookKit = require(Shared:WaitForChild("LookKit"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local PeopleLooks = require(Shared:WaitForChild("PeopleLooks"))

local QualityController = require(script.Parent.QualityController)
local DebrisBudget = require(script.Parent.Parent.Fx.DebrisBudget)
local Kit = require(script.Parent.Parent.Ui.Kit)

local EnemyRenderer = {}

local DELAY = 0.1
local BITS = Status.BITS
local EXTRA = EnemySim.EXTRA
local GOLD = Color3.fromRGB(255, 205, 70) -- a Captain's rally
local CLASSIC_FACE = "rbxasset://textures/face.png" -- Roblox's built-in face, the one plain citizens wear
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
	-- weighty hits (Config.Combat.weight): held in place for the hit-stop, then a recoil away from the hit
	freezeUntil: number,
	freezePos: Vector3?,
	flinchAt: number,
	flinchDir: Vector3,
	flinchStuds: number,
	flinchTilt: number,
	look: string?,
	glow: Color3,
	turned: boolean,
	-- the Roblox look (Config.NpcLooks): "roblox", "shell" or "plain"; its clothes Textures by part, the face
	-- decal and its two images, and the hair handles it can show (one picked per robot)
	mode: string,
	clothes: { [string]: { Texture } }?,
	shown: number, -- how much of its clothes (and a Mimic's street clothes) is drawn: ClothesMap.level
	idleSince: number, -- when it went back to the pool (os.clock), for the pool trim
	faceDecal: Decal?,
	faces: { string }?,
	hairs: { string },
	-- the uniform images this kind can wear (each version repeated by its odds) and the one shown now
	outfits: { string },
	outfit: string?,
	-- the newer kinds: the second flags byte (EnemySim.EXTRA) and last frame's flags (for the edges, -1 = new)
	extra: number,
	prevFlags: number,
	riotUp: boolean,
	rally: BillboardGui,
	medLight: BasePart?,
	light: PointLight?,
	-- a Mimic's disguise: its street colours by part, the street clothes and their tints, and a citizen's face
	citizen: boolean,
	street: { [string]: Color3 },
	streetClothes: { [string]: { Texture } }?,
	streetTint: { Color3 },
	streetFace: Decal?,
	-- a famous fake or an evil twin (lore step 4): its hero look's pieces with the body part each is fixed to,
	-- its plate, its face decal's human and cracked images, its path (for the attacks' look) and whom it copies
	fake: boolean,
	costumed: boolean, -- lore step 11, chain 2: a costumed villain's powered suit (never cracks or reads FAKE)
	creature: boolean, -- lore step 11, chain 4: a cartoon creature (no shell to break, bursts into light)
	kind: string,
	ident: { [string]: any }?,
	lookParts: { { p: BasePart, owner: string, t: number } },
	plate: BillboardGui?,
	plateName: TextLabel?,
	plateSub: TextLabel?,
	heroFace: Decal?,
	humanFace: string,
	crackFace: string?,
	unmasked: boolean,
	path: string?,
	userId: number?,
}

-- The citizens' uploaded street clothes and faces (as CitizenRenderer picks them), so a disguised Mimic wears
-- what the citizens around it wear; empty until nate uploads them
local function uploadedIds(map: { [string]: number }): { string }
	local out = {}
	for _, id in map do
		if id ~= 0 then
			table.insert(out, "rbxassetid://" .. id)
		end
	end
	table.sort(out)
	return out
end
local STREET_SHIRTS = uploadedIds(Config.Creator.clothes.shirts)
local STREET_PANTS = uploadedIds(Config.Creator.clothes.pants)
local STREET = Config.Creator.clothes.on and #STREET_SHIRTS > 0 and #STREET_PANTS > 0
local STREET_TINTS = Config.Destruction.citizens.clothesTints

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
	-- a fake's crack overlay goes with its head
	CrackPlate = { "Head" },
	CrackEye = { "Head" },
	CrackLine1 = { "Head" },
	CrackLine2 = { "Head" },
	CrackLine3 = { "Head" },
	-- a Salt Dog's bandana is cloth on the head's shell: it goes with the head
	Bandana = { "Head" },
	BandanaKnot = { "Head" },
}
-- a side quest finale model's extras go with their R15 part (Config.FinaleArt, art/blender/finales.py)
for _, fa in Config.FinaleArt do
	for xname, x in fa.extras or {} do
		TIES[xname] = TIES[xname] or { x.parent }
	end
end
local CRACK = { CrackPlate = true, CrackEye = true, CrackLine1 = true, CrackLine2 = true, CrackLine3 = true }
local FAKE_RED = Color3.fromRGB(255, 70, 60)
-- who each evil twin copies (EnemyIdentity): { userId, words, path, name, title }; or a dressed side quest
-- finale villain's dress (lore step 11, chain 6: { words, name, title, dress, creature, body })
local idents: { [number]: { [string]: any } } = {}

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

-- A fake's rig: its hero look's gender and build proportions, scaled so the body is its kind's height
local function fakeLayout(look: any, height: number): RigMath.Layout
	local factors = BodyShape.factors(Config, { gender = look.gender, build = look.build, height = 3 })
	local base = RigMath.layout(Config.HeroRig, factors, 1)
	return RigMath.layout(Config.HeroRig, factors, height / base.height)
end

local SIDES = { { "Left", "L", -1 }, { "Right", "R", 1 } }

-- One robot: the R15 rig as the superhuman shell (uniform, skin, gloves, boots, hair, chest mark, cape on
-- elites) that breaks off with damage, and inside it the metal endoskeleton (spine, ribs, glowing core,
-- skull and eyes, bones, joints). ident: who an evil twin copies (EnemyIdentity), when known.
local function makeRobot(typeId: number, ident: { [string]: any }?): Body
	local cfg = byType[typeId] or Config.Enemies.SparkDrone
	local kind = kindByType[typeId] or "SparkDrone"
	if cfg.twin then
		cfg = FakeRules.twinCfg(Config, ident and ident.path) -- the path's fighting style (pose and moves)
	end
	-- a dress over a plain robot (lore step 11, the Underwater chain: Config.SideQuests.dress `robot`): drawn
	-- like a costumed villain (it never cracks or reads FAKE) in its dress's path look
	if ident and ident.dress and ident.robot and not cfg.fake then
		cfg = table.clone(cfg)
		cfg.fake = { costumed = true, path = ident.path }
	end
	local fake = cfg.fake ~= nil
	-- a fake's hero look: its fixed one, or the look of the player a twin copies
	local heroLook: any = nil
	if fake then
		heroLook = (ident and LookCodec.read(ident.words)) or FakeRules.look(Config, kind)
	end
	-- the 2026-11-18 art pass: a side quest finale's own model (Config.FinaleArt: ReplicatedStorage.Art.<Name>
	-- once nate imports art/export/finales/<Name>.fbx; until then today's look) and a finale villain's own
	-- outfit and face (Shared.PeopleLooks, once uploaded). Both PLACEHOLDER ART until nate approves them.
	local who = PeopleLooks.villain(ident and ident.dress, kind)
	local artCfg = who and Config.FinaleArt[who]
	if artCfg and not NpcRig.meshes(nil, who) then
		artCfg = nil
	end
	local fit = if fake and not artCfg then PeopleLooks.outfit(Config, who) else nil
	local body = cfg.body
	if fake and ident and ident.dress and type(ident.body) == "table" then
		-- lore step 11, chain 6: a dressed finale villain's own robot colours (Shared.FakeRules.dress)
		body = table.clone(body)
		for _, k in FakeRules.DRESS_BODY do
			local c = ident.body[k]
			if type(c) == "table" and #c == 3 then
				body[k] = c
			end
		end
		-- lore step 11, the Underwater chain: the dress's height and the Tidewright's trident
		if type(ident.height) == "number" then
			body.height = ident.height
		end
		if ident.trident then
			body.trident = true
		end
	end
	local h = body.height
	local metal = rgb(LOOK.endo):Lerp(rgb(body.metal), 0.35)
	local dark = rgb(body.metal):Lerp(Color3.new(0, 0, 0), 0.45)
	local eye = rgb(body.eye)
	local suit = rgb(body.suit or body.metal)
	local trim = rgb(body.trim or body.eye)
	local skin = rgb(LOOK.skins[1])
	local layout = if heroLook then fakeLayout(heroLook, body.height) else layoutFor(typeId, body)
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
	local set = if heroLook
		then BodyShape.setKey(Config, heroLook)
		else BodyShape.setKey(Config, { gender = 1, build = LOOK.builds[body.build] or 2 })
	-- the look (nate is trying both in game, 2026-11-17): "roblox" = a plain Roblox character in classic
	-- clothes with a Roblox face and catalog hair (Config.NpcLooks, once its images are uploaded); "shell" =
	-- the Blender superhero shell set (overhaul plan step 3: a face, a fitted suit with a chest emblem, gloves,
	-- boots and a belt baked in) once imported; else the plain look
	local recipe = NL.robots[kindByType[typeId] or ""]
	local outfits = outfitsOf(recipe)
	local hasRoblox = #outfits > 0 and #upFaces > 0
	local hasShell = body.art ~= nil and NpcRig.meshes(set, body.art) ~= nil
	local mode = if fake
		then "fake" -- a hero look, whatever the robots' style
		elseif artCfg and style ~= "plain" then "shell" -- a finale's own model wins over its clothes
		elseif style == "roblox" then (if hasRoblox then "roblox" else "plain")
		elseif style == "shell" then (if hasShell then "shell" else "plain")
		elseif style == "plain" then "plain"
		elseif hasRoblox then "roblox"
		elseif hasShell then "shell"
		else "plain"
	local look: string? = if artCfg then who elseif mode == "shell" then body.art else nil
	if artCfg then
		-- the model's colour map shows its own paint; its see-through parts take this one colour
		for pname in colors do
			colors[pname] = rgb(artCfg.tint)
		end
	elseif mode == "roblox" then
		-- skin everywhere: the clothes image covers the body, the skin shows on the head and where it is clear
		for pname in colors do
			colors[pname] = skin
		end
	end
	local rig = NpcRig.build(layout, cfg.name, colors, SKIN, nil, set, look)
	local model = rig.model
	-- a fake: the whole hero look, built before the endoskeleton so only the 15 body parts take its paint
	local lookParts: { { p: BasePart, owner: string, t: number } } = {}
	local heroFace: Decal? = nil
	local humanFace, crackFace = CLASSIC_FACE, nil
	local fakeClothes: { [string]: { Texture } }? = nil
	if heroLook and not artCfg then
		heroFace = NpcRig.face(rig, CLASSIC_FACE)
		-- a villain's own outfit draws the suit, shirt, pants and legs (PeopleLooks.strip)
		local built = if fit and fit.clothes then PeopleLooks.strip(heroLook) else heroLook
		local ok, err = pcall(LookKit.build, model, built)
		if not ok then
			warn("[EnemyRenderer] fake look", kind, err)
		end
		local hl = model:FindFirstChild("HeroLook")
		for _, d in if hl then hl:GetDescendants() else {} do
			if d:IsA("BasePart") then
				local w = d:FindFirstChildOfClass("WeldConstraint")
				local owner = if w and w.Part0 then w.Part0.Name else "UpperTorso"
				table.insert(lookParts, { p = d, owner = owner, t = d.Transparency })
			end
		end
		if fit then
			fakeClothes = NpcRig.wearOutfit(rig, fit, NL.offsetSign)
		end
		humanFace = (heroFace :: Decal).Texture
		-- the cracked face image for its visage (Config.NpcLooks.faces; 0 until nate uploads it), or the
		-- villain's own cracked face
		local vp = CreatorRules.piece(Config, "visage", heroLook.pieces.visage or 0)
		local fr = vp and NL.faces[vp.kit]
		if fit and fit.cracked then
			crackFace = fit.cracked
		elseif fr and (fr.cracked or 0) ~= 0 then
			crackFace = "rbxassetid://" .. fr.cracked
		end
	end
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
		for xname, x in if artCfg then artCfg.extras else Config.TrooperArt.extras do
			local p = lookMesh(look, xname)
			if p then
				local ps = size(x.parent)
				local o, sz = x.offset, x.size
				p.Name = xname
				p.Size = ps * Vector3.new(sz[1], sz[2], sz[3])
				p.Color = if artCfg then rgb(artCfg.tint) else rgb(LOOK.hair[1])
				p.Material = SKIN
				p.CastShadow = false
				NpcRig.fix(rig, x.parent, p, CFrame.new(ps * Vector3.new(o[1], o[2], o[3])))
				register(xname, p)
				hairMesh = hairMesh or xname == "Hair" or artCfg ~= nil
			end
		end
	end
	if not hairMesh and not fake then
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
	local clothes: { [string]: { Texture } }? = fakeClothes
	local faceDecal: Decal? = nil
	if mode == "roblox" and recipe then
		clothes = NpcRig.dress(rig, outfits[1], NL.offsetSign) -- assign picks this robot's uniform version
		faceDecal = NpcRig.face(rig, upFaces[1][1]) -- assign picks this robot's face
	end
	-- (a finale's own model has its face modelled and painted)
	local eyeSides: { any } = if mode == "roblox" or fake or artCfg then {} else SIDES
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
	-- a fake's face crack (PLACEHOLDER ART until the cracked face images are uploaded): one half of the face
	-- torn away to a metal plate with a glowing eye, and dark cracks across the rest; shown once unmasked
	if fake then
		local front = -HD.Z * 0.5 - 0.03
		add(
			"CrackPlate",
			"Head",
			CFrame.new(HD.X * 0.24, HD.Y * 0.02, front),
			Vector3.new(HD.X * 0.5, HD.Y * 0.86, 0.06),
			Color3.fromRGB(150, 156, 168),
			M,
			nil,
			1
		)
		add(
			"CrackEye",
			"Head",
			CFrame.new(HD.X * 0.2, HD.Y * 0.08, front - 0.04),
			Vector3.new(HD.X * 0.2, HD.X * 0.2, 0.08),
			Color3.fromRGB(255, 50, 40),
			N,
			Enum.PartType.Ball,
			1
		)
		local lines = {
			{ -0.02, 0.28, 34, 0.42 },
			{ -0.04, -0.12, -28, 0.36 },
			{ -0.18, 0.06, 70, 0.3 },
		}
		for k, l in lines do
			add(
				"CrackLine" .. k,
				"Head",
				CFrame.new(HD.X * l[1], HD.Y * l[2], front - 0.02) * CFrame.Angles(0, 0, math.rad(l[3])),
				Vector3.new(HD.X * l[4], HD.Y * 0.035, 0.04),
				Color3.fromRGB(25, 25, 30),
				SKIN,
				nil,
				1
			)
		end
	end
	if body.spear then
		-- Skylance's spear, held upright in the right hand (PLACEHOLDER ART)
		local hand = size("RightHand")
		local len = h * 1.15
		add(
			"Spear",
			"RightHand",
			CFrame.new(0, -hand.Y * 0.3, -hand.Z * 0.2),
			Vector3.new(0.18, len, 0.18),
			Color3.fromRGB(215, 220, 230),
			M
		)
		add(
			"SpearTip",
			"RightHand",
			CFrame.new(0, -hand.Y * 0.3 + len * 0.5 + 0.4, -hand.Z * 0.2) * CFrame.Angles(0, math.rad(45), 0),
			Vector3.new(0.35, 0.9, 0.35),
			trim,
			N
		)
	end
	if body.windKey and not artCfg then
		-- the Toymaker's toys (lore step 11, the Suburbs chain): a brass wind-up key in the back, its shaft out of
		-- the upper torso and two round bows across the top (PLACEHOLDER ART)
		local brass = Color3.fromRGB(215, 170, 70)
		local k = UT.X * 0.18
		add(
			"KeyShaft",
			"UpperTorso",
			CFrame.new(0, UT.Y * 0.1, UT.Z * 0.5 + k * 1.5),
			Vector3.new(k * 0.6, k * 0.6, k * 3),
			brass,
			M
		)
		for s = -1, 1, 2 do
			-- a disc facing back: a cylinder's axis is its X, turned to point along Z
			add(
				"KeyBow" .. (if s < 0 then "L" else "R"),
				"UpperTorso",
				CFrame.new(s * k * 1.1, UT.Y * 0.1, UT.Z * 0.5 + k * 3) * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(k * 0.4, k * 1.8, k * 1.8),
				brass,
				M,
				Enum.PartType.Cylinder
			)
		end
	end
	if body.hook then
		-- Captain Brine's Salt Dogs (lore step 11, the Coast chain): a steel hook for the left hand and a red
		-- bandana tied round the dome, its knot at the back (PLACEHOLDER ART)
		local hand = size("LeftHand")
		local steel = Color3.fromRGB(190, 195, 205)
		add(
			"HookShaft",
			"LeftHand",
			CFrame.new(0, -hand.Y * 0.9, 0),
			Vector3.new(0.22, hand.Y * 1.2, 0.22),
			steel,
			M
		)
		add(
			"HookCurve",
			"LeftHand",
			CFrame.new(0, -hand.Y * 1.5, -hand.Z * 0.35),
			Vector3.new(0.2, 0.2, hand.Z * 0.9),
			steel,
			M
		)
		add(
			"HookTip",
			"LeftHand",
			CFrame.new(0, -hand.Y * 1.3, -hand.Z * 0.8),
			Vector3.new(0.2, hand.Y * 0.5, 0.2),
			steel,
			M
		)
		local red = Color3.fromRGB(210, 45, 45)
		add("Bandana", "Head", CFrame.new(0, HD.Y * 0.3, 0), HD * Vector3.new(1.08, 0.2, 1.08), red, SKIN)
		add(
			"BandanaKnot",
			"Head",
			CFrame.new(0, HD.Y * 0.2, HD.Z * 0.6),
			HD * Vector3.new(0.2, 0.28, 0.14),
			red,
			SKIN
		)
	end
	if body.anchor then
		-- Captain Brine's anchor, swung in the right hand: the shank, the stock across its top and the two flukes
		-- at its foot (PLACEHOLDER ART)
		local hand = size("RightHand")
		local iron = Color3.fromRGB(70, 75, 85)
		local len = h * 0.55
		add("AnchorShank", "RightHand", CFrame.new(0, -len * 0.35, 0), Vector3.new(0.5, len, 0.5), iron, M)
		add(
			"AnchorStock",
			"RightHand",
			CFrame.new(0, len * 0.1, 0),
			Vector3.new(len * 0.45, 0.4, 0.4),
			iron,
			M
		)
		for s = -1, 1, 2 do
			add(
				"AnchorFluke" .. (if s < 0 then "L" else "R"),
				"RightHand",
				CFrame.new(s * len * 0.2, -len * 0.8, 0) * CFrame.Angles(0, 0, math.rad(s * 40)),
				Vector3.new(0.5, len * 0.35, 0.5),
				iron,
				M
			)
		end
		add(
			"AnchorRing",
			"RightHand",
			CFrame.new(0, len * 0.22, 0),
			Vector3.new(0.3, hand.X * 1.2, hand.X * 1.2),
			iron,
			M,
			Enum.PartType.Cylinder
		)
	end
	if body.trident then
		-- the Tidewright's trident, held upright in the right hand: a bronze shaft, a crossbar and three prongs
		-- (PLACEHOLDER ART)
		local bronze = rgb(body.trim or body.metal)
		local len = h * 0.7
		add(
			"TridentShaft",
			"RightHand",
			CFrame.new(0, len * 0.15, 0),
			Vector3.new(0.45, len, 0.45),
			bronze,
			M
		)
		add(
			"TridentBar",
			"RightHand",
			CFrame.new(0, len * 0.62, 0),
			Vector3.new(len * 0.32, 0.4, 0.4),
			bronze,
			M
		)
		for s = -1, 1 do
			add(
				"TridentProng" .. (s + 2),
				"RightHand",
				CFrame.new(s * len * 0.14, len * (if s == 0 then 0.8 else 0.74), 0),
				Vector3.new(0.35, len * (if s == 0 then 0.32 else 0.22), 0.35),
				bronze,
				M
			)
		end
		add("TridentGlow", "RightHand", CFrame.new(0, len * 0.62, -0.25), Vector3.new(0.5, 0.5, 0.1), eye, N)
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
	-- The newer kinds' gear (PLACEHOLDER ART: plain parts until Blender meshes are made for them)
	if body.riot then
		-- a riot shield on the left forearm: held out in front (the forearm points forward in the guard pose,
		-- so the plate stands across the body), with a window near the top and a trim stripe
		local la, hand = size("LeftLowerArm"), size("LeftHand")
		local sh = h * 0.5
		local plate = CFrame.new(UT.X * 0.3, -(la.Y * 0.5 + hand.Y + 0.25), sh * 0.3)
			* CFrame.Angles(math.rad(-90), 0, 0)
		add("Riot", "LeftLowerArm", plate, Vector3.new(UT.X * 1.25, sh, 0.25), suit:Lerp(dark, 0.4), M)
		add(
			"RiotWin",
			"LeftLowerArm",
			plate * CFrame.new(0, sh * 0.3, -0.14),
			Vector3.new(UT.X * 0.9, sh * 0.16, 0.06),
			Color3.fromRGB(170, 210, 235),
			Enum.Material.Glass,
			nil,
			0.3
		)
		add(
			"RiotBar",
			"LeftLowerArm",
			plate * CFrame.new(0, -sh * 0.15, -0.14),
			Vector3.new(UT.X * 1.1, sh * 0.08, 0.05),
			trim,
			SKIN
		)
	end
	if body.cap then
		-- a peaked officer's cap: the round crown over the hair, a dark peak and a gold badge
		add(
			"Cap",
			"Head",
			CFrame.new(0, HD.Y * 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(HD.Y * 0.32, HD.X * 1.15, HD.X * 1.15),
			suit:Lerp(dark, 0.3),
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
		add(
			"CapPeak",
			"Head",
			CFrame.new(0, HD.Y * 0.42, -HD.Z * 0.62) * CFrame.Angles(math.rad(-12), 0, 0),
			Vector3.new(HD.X * 0.85, 0.08, HD.Z * 0.45),
			Color3.fromRGB(25, 25, 30),
			SKIN
		)
		add(
			"CapBadge",
			"Head",
			CFrame.new(0, HD.Y * 0.56, -HD.X * 0.58),
			Vector3.new(HD.X * 0.22, HD.Y * 0.16, 0.06),
			trim,
			M
		)
	end
	if body.rifle then
		-- a long rifle in the right hand (the left hand holds the barrel in the aim and carry poses): stock
		-- behind the hand, a scope on top, a red tip the aim laser starts from
		local len, w = h * 0.55, HD.X * 0.14
		local grip = CFrame.new(0, -len * 0.25, 0) * CFrame.Angles(math.rad(90), 0, 0)
		add("Rifle", "RightHand", grip, Vector3.new(w, w * 1.3, len), dark, M)
		add(
			"Scope",
			"RightHand",
			grip * CFrame.new(0, -w * 1.1, -len * 0.05),
			Vector3.new(w * 0.8, w * 0.8, len * 0.3),
			metal,
			M
		)
		add(
			"RifleTip",
			"RightHand",
			grip * CFrame.new(0, 0, len * 0.5 + 0.05),
			Vector3.new(w * 0.7, w * 0.7, 0.12),
			eye,
			N
		)
	end
	if body.visor then
		add(
			"Visor",
			"Head",
			CFrame.new(0, HD.Y * 0.06, -HD.Z * 0.5 - 0.04),
			Vector3.new(HD.X * 0.92, HD.Y * 0.16, 0.08),
			eye,
			N
		)
	end
	if body.bandolier then
		-- a strap across the chest with three grenades on it, and a satchel on the right hip
		local strapLen = math.sqrt(UT.X * UT.X + UT.Y * UT.Y)
		local strap = CFrame.new(0, 0, -UT.Z * 0.5 - 0.05) * CFrame.Angles(0, 0, math.rad(40))
		add(
			"Strap",
			"UpperTorso",
			strap,
			Vector3.new(UT.X * 0.2, strapLen, 0.1),
			Color3.fromRGB(70, 55, 35),
			Enum.Material.Fabric
		)
		for k = 1, 3 do
			add(
				"Grenade" .. k,
				"UpperTorso",
				strap * CFrame.new(0, (k - 2) * strapLen * 0.28, -0.12),
				Vector3.one * UT.X * 0.17,
				Color3.fromRGB(70, 85, 45),
				M,
				Enum.PartType.Ball
			)
		end
		add(
			"Satchel",
			"LowerTorso",
			CFrame.new(LT.X * 0.55, -LT.Y * 0.1, LT.Z * 0.1),
			Vector3.new(LT.X * 0.25, LT.Y * 0.9, LT.Z * 0.7),
			Color3.fromRGB(110, 85, 50),
			Enum.Material.Fabric
		)
	end
	local medLight: BasePart? = nil
	local light: PointLight? = nil
	if body.medpack then
		-- a backpack with a green plus (never a red cross) and a green light on top that pulses while it mends
		local depth = UT.Z * 0.55
		local back = UT.Z * 0.5 + depth * 0.5
		local green = Color3.fromRGB(70, 230, 120)
		add(
			"Medpack",
			"UpperTorso",
			CFrame.new(0, 0, back),
			Vector3.new(UT.X * 0.75, UT.Y * 0.85, depth),
			suit,
			SKIN
		)
		local plus = CFrame.new(0, 0, back + depth * 0.5 + 0.02)
		add("PlusH", "UpperTorso", plus, Vector3.new(UT.X * 0.4, UT.X * 0.12, 0.05), green, N)
		add("PlusV", "UpperTorso", plus, Vector3.new(UT.X * 0.12, UT.X * 0.4, 0.05), green, N)
		medLight = add(
			"MedLight",
			"UpperTorso",
			CFrame.new(0, UT.Y * 0.425 + UT.X * 0.06, back),
			Vector3.new(UT.X * 0.14, UT.X * 0.12, UT.X * 0.14),
			green,
			N
		)
		local pl = Instance.new("PointLight")
		pl.Color = green
		pl.Range = 8
		pl.Brightness = 0
		pl.Enabled = false
		pl.Parent = medLight
		light = pl
	end
	if body.wings then
		-- swept jet wings on the back, tips glowing in the jet colour
		local span, chord = UT.X * 1.0, UT.Y * 0.5
		local tip = if body.jetColor then rgb(body.jetColor) else eye
		for _, side in SIDES do
			local sign = side[3]
			local sweep = math.rad(25)
			local wing = CFrame.new(
				sign * (UT.X * 0.4 + span * 0.45 * math.cos(sweep)),
				UT.Y * 0.2,
				UT.Z * 0.55 + span * 0.45 * math.sin(sweep)
			) * CFrame.Angles(0, -sign * sweep, sign * math.rad(8))
			add("Wing" .. side[2], "UpperTorso", wing, Vector3.new(span, 0.12, chord), metal, M)
			add(
				"WingTip" .. side[2],
				"UpperTorso",
				wing * CFrame.new(sign * span * 0.5, 0, 0),
				Vector3.new(0.15, 0.14, chord * 0.8),
				tip,
				N
			)
		end
	end
	if body.hookArm then
		-- the right forearm is a hook launcher with a claw (the claw is gone while it flies on its cable)
		local la = size("RightLowerArm")
		local down = CFrame.Angles(math.rad(-90), 0, 0)
		add(
			"Launcher",
			"RightLowerArm",
			CFrame.new(0, -la.Y * 0.3, 0) * down,
			Vector3.new(la.X * 1.9, la.X * 1.9, la.Y * 1.6),
			dark,
			M
		)
		add(
			"Claw",
			"RightLowerArm",
			CFrame.new(0, -la.Y * 1.15, 0),
			Vector3.new(la.X * 1.2, la.X * 0.6, la.X * 1.2),
			trim,
			M
		)
		for k, sign in { -1, 1 } do
			add(
				if k == 1 then "ClawA" else "ClawB",
				"RightLowerArm",
				CFrame.new(sign * la.X * 0.45, -la.Y * 1.35, 0) * CFrame.Angles(0, 0, sign * math.rad(20)),
				Vector3.new(la.X * 0.25, la.X * 0.9, la.X * 0.4),
				metal,
				M
			)
		end
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
	-- a fake's name plate: its hero name big and its title under it like a real hero's (no robot tag), then
	-- FAKE in red once unmasked (FakeRules.plate); the health bar stays under it
	local plate: BillboardGui? = nil
	local plateName: TextLabel? = nil
	local plateSub: TextLabel? = nil
	if fake then
		local pl = Instance.new("BillboardGui")
		pl.Name = "Plate"
		pl.Adornee = head
		pl.Size = UDim2.fromOffset(190, 44)
		pl.StudsOffset = Vector3.new(0, HD.Y + 1.6, 0)
		pl.MaxDistance = Config.Enemies.fakes.plateRange
		pl.AlwaysOnTop = true
		pl.LightInfluence = 0
		local text = FakeRules.plate(Config, kind, false, ident)
		local nm = Kit.label({
			Text = text.name,
			Size = UDim2.new(1, 0, 0, 26),
			TextColor3 = Kit.color.paper,
			TextStrokeTransparency = 0.2,
			maxText = 22,
		})
		nm.Parent = pl
		local sub = Kit.label({
			Text = text.sub,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 26),
			TextColor3 = Kit.color.paper,
			TextStrokeTransparency = 0.3,
			Font = Kit.bodyFont,
			maxText = 24,
		})
		sub.Parent = pl
		pl.Parent = head
		plate, plateName, plateSub = pl, nm, sub
	end
	-- the rally chevron over the head (a billboard, so it reads from every side)
	local rally = Instance.new("BillboardGui")
	rally.Name = "Rally"
	rally.Size = UDim2.fromScale(math.max(1, HD.X * 0.9), math.max(0.6, HD.X * 0.55))
	rally.StudsOffset = Vector3.new(0, HD.Y + 1.2, 0)
	rally.AlwaysOnTop = true
	rally.LightInfluence = 0
	rally.MaxDistance = 200
	rally.Enabled = false
	rally.Adornee = head
	for _, k in { -1, 1 } do
		local bar2 = Instance.new("Frame")
		bar2.AnchorPoint = Vector2.new(0.5, 0.5)
		bar2.Position = UDim2.fromScale(0.5 + k * 0.18, 0.5)
		bar2.Size = UDim2.fromScale(0.5, 0.22)
		bar2.Rotation = k * 35
		bar2.BackgroundColor3 = GOLD
		bar2.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(90, 60, 10)
		stroke.Thickness = 1.5
		stroke.Parent = bar2
		bar2.Parent = rally
	end
	rally.Parent = head
	-- a Mimic's disguise: the citizens' uploaded street clothes when there are any (assign picks them), and a
	-- citizen's face over the robot's eyes in the plain look
	local streetClothes: { [string]: { Texture } }? = nil
	local streetFace: Decal? = nil
	if body.citizen then
		if STREET then
			streetClothes = NpcRig.dressPair(rig, STREET_SHIRTS[1], STREET_PANTS[1], NL.offsetSign)
		end
		if not faceDecal then
			local d = NpcRig.face(rig, CLASSIC_FACE)
			d.Name = "street"
			d.Transparency = 1
			streetFace = d
		end
	end
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
		freezeUntil = 0,
		freezePos = nil,
		flinchAt = -1,
		flinchDir = Vector3.new(0, 0, -1),
		flinchStuds = 0,
		flinchTilt = 0,
		look = look,
		glow = glow,
		turned = false,
		mode = mode,
		clothes = clothes,
		shown = 2,
		idleSince = 0,
		faceDecal = faceDecal,
		faces = nil,
		hairs = hairs,
		outfits = outfits,
		outfit = if mode == "roblox" then outfits[1] else nil,
		extra = 0,
		prevFlags = -1,
		riotUp = false,
		rally = rally,
		medLight = medLight,
		light = light,
		citizen = body.citizen == true,
		street = {},
		streetClothes = streetClothes,
		streetTint = { Color3.new(1, 1, 1), Color3.new(1, 1, 1) },
		streetFace = streetFace,
		fake = fake,
		costumed = fake and cfg.fake.costumed == true,
		-- a dressed finale villain (lore step 11, chain 6) is a creature only if its dress says so
		creature = fake
			and (if ident and ident.dress then ident.creature == true else cfg.fake.creature == true),
		kind = kind,
		ident = ident,
		lookParts = lookParts,
		plate = plate,
		plateName = plateName,
		plateSub = plateSub,
		heroFace = heroFace,
		humanFace = humanFace,
		crackFace = crackFace,
		unmasked = false,
		path = if fake then cfg.fake.path else nil,
		userId = ident and ident.userId,
	}
end

-- A colour near `c`, picked by `h` (a Mimic's street clothes: its kind's suit and trim, varied per robot)
local function vary(c: Color3, h: number): Color3
	local hue, sat, val = c:ToHSV()
	hue = (hue + ((h % 21) - 10) / 100) % 1
	sat = math.clamp(sat * (0.75 + ((h // 21) % 11) / 20), 0, 1)
	val = math.clamp(val * (0.8 + ((h // 231) % 9) / 20), 0.08, 1)
	return Color3.fromHSV(hue, sat, val)
end

-- A Mimic's disguise for one robot id: a citizen's colours on the 15 body parts (a shirt on the torso and
-- upper arms, skin on the forearms, hands and head, trousers and darker shoes), or the citizens' own uploaded
-- shirt and pants tinted like theirs (CitizenRenderer.dress) with skin under them, and a citizen's face
local function disguiseFor(body: Body, id: number, skin: Color3)
	local h = Rng.hash(id, 6011)
	local shirt = vary(rgb(body.cfg.body.suit or body.cfg.body.metal), h)
	local pants = vary(rgb(body.cfg.body.trim or body.cfg.body.metal), h // 2401)
	local street: { [string]: Color3 } = { Head = skin, UpperTorso = shirt, LowerTorso = pants }
	for _, side in SIDES do
		local s = side[1]
		street[s .. "UpperArm"] = shirt
		street[s .. "LowerArm"] = skin
		street[s .. "Hand"] = skin
		street[s .. "UpperLeg"] = pants
		street[s .. "LowerLeg"] = pants
		street[s .. "Foot"] = pants:Lerp(Color3.new(0, 0, 0), 0.5)
	end
	local clothes = body.streetClothes
	if clothes then
		for pname in street do
			street[pname] = skin
		end
		local top = STREET_SHIRTS[h % #STREET_SHIRTS + 1]
		local bottom = STREET_PANTS[(h // 13) % #STREET_PANTS + 1]
		body.streetTint = {
			rgb(STREET_TINTS.shirts[(h // 211) % #STREET_TINTS.shirts + 1]),
			rgb(STREET_TINTS.pants[(h // 4099) % #STREET_TINTS.pants + 1]),
		}
		for pname, list in clothes do
			local upper = ClothesMap.half(pname) == 0
			for _, t in list do
				t.Texture = if upper then top else bottom
			end
		end
	end
	body.street = street
	if body.streetFace then
		body.streetFace.Texture = if STREET and #upFaces > 0
			then upFaces[(h // 77777) % #upFaces + 1][1]
			else CLASSIC_FACE
	end
end

-- Give a pooled body to one robot id: its break order, skin and hair (the same on every device)
local function assign(body: Body, id: number)
	body.order = RobotDamage.order(id, body.shell, LOOK.spread)
	body.broken = {}
	body.brokenN = -1 -- set without chips on the first frame (a robot can arrive already hurt)
	body.turned = false
	body.sparks.Enabled = false
	body.unmasked = false
	if body.fake then
		-- a fake keeps its hero look's own skin, hair and face (the same on every device)
		NpcRig.rest(body.rig)
		body.lastFlags = -1
		body.prevFlags = -1
		body.extra = 0
		body.riotUp = false
		if body.plateName and body.plateSub then
			local text = FakeRules.plate(Config, body.kind, false, body.ident)
			body.plateName.Text = text.name
			body.plateName.TextColor3 = Kit.color.paper
			body.plateSub.Text = text.sub
		end
		return
	end
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
	if body.citizen then
		disguiseFor(body, id, skin)
	end
	NpcRig.rest(body.rig)
	body.lastFlags = -1
	body.prevFlags = -1
	body.extra = 0
	body.riotUp = false
end

local function acquire(typeId: number, id: number): Body
	local base = byType[typeId]
	local body: Body
	if (base and base.twin) or (base and base.fake and idents[id]) or (idents[id] and idents[id].robot) then
		-- an evil twin wears its own hero's look, a dressed finale villain its dress (lore step 11, chain 6; the
		-- Underwater chain: a dress over a sea robot too): never pooled
		body = makeRobot(typeId, idents[id])
	else
		local list = pool[typeId]
		body = (list and table.remove(list)) or makeRobot(typeId)
	end
	body.lastFlags = -1
	body.model.Parent = folder
	return body
end

local function release(body: Body)
	if body.ident or (byType[body.typeId] and byType[body.typeId].twin) then
		body.model:Destroy()
		return
	end
	body.model.Parent = nil
	body.bar.Enabled = false
	body.rally.Enabled = false
	body.sparks.Enabled = false
	if body.light then
		body.light.Enabled = false
	end
	body.idleSince = os.clock()
	pool[body.typeId] = pool[body.typeId] or {}
	table.insert(pool[body.typeId], body)
end

-- Perf pass (2026-11-18): the pool kept every body it was ever given (a busy fight leaves dozens of rigs of a
-- kind, each about 90 parts and up to 66 clothes Textures, in memory for the whole session). Every few seconds
-- each kind keeps its newest few (Config.Presets <preset>.enemyPool.keep) and destroys the rest once they have
-- been idle that long (.idle seconds). The oldest are at the front: release appends.
local lastTrim = 0
local function trimPool(now: number)
	if now - lastTrim < 5 then
		return
	end
	lastTrim = now
	local P = QualityController.preset.enemyPool or Config.Presets.low.enemyPool
	for _, list in pool do
		while #list > P.keep and now - list[1].idleSince >= P.idle do
			table.remove(list, 1).model:Destroy()
		end
	end
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
	RifleTip = true,
	Visor = true,
	PlusH = true,
	PlusV = true,
	MedLight = true,
	WingTipL = true,
	WingTipR = true,
}

-- what a disguised Mimic shows: the person (body, hair, eyes); every robot piece is hidden
local PERSON: { [string]: boolean } = { Hair = true, Hair1 = true, Hair2 = true, Hair3 = true }
for _, pname in BodyShape.PARTS do
	PERSON[pname] = true
end
local RIOT = { Riot = true, RiotWin = true, RiotBar = true }
local CLAW = { Claw = true, ClawA = true, ClawB = true }

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

-- Colours and transparency change only when the flags, the extra byte or the broken shell change (cheap)
local function applyFlags(body: Body)
	local f = body.flags
	local x = body.extra
	local key = f + x * 256
	if body.flashUntil > 0 or key == body.lastFlags then
		return -- unchanged, or the white hit flash is showing
	end
	body.lastFlags = key
	local cold = bit32.band(f, BITS.slow + BITS.root) ~= 0
	local cloak = bit32.band(f, BITS.cloak) ~= 0
	local shield = bit32.band(f, BITS.shield) ~= 0
	local stun = bit32.band(f, BITS.stun) ~= 0
	local windup = bit32.band(f, BITS.windup) ~= 0
	local disguised = body.citizen and bit32.band(x, EXTRA.disguise) ~= 0
	local rally = bit32.band(x, EXTRA.rally) ~= 0
	local hooked = bit32.band(x, EXTRA.hooked) ~= 0
	local mending = bit32.band(x, EXTRA.mend) ~= 0
	body.riotUp = shield and bit32.band(f, BITS.guardBroken) == 0
	-- the robot turns (and stays turned) the first time it winds up an attack or its shell starts to break; a
	-- Mimic stays human-eyed while disguised and is turned from the moment it shows itself
	if not disguised then
		body.turned = body.turned or windup or body.brokenN > 0 or body.citizen
	end
	local turned = body.turned and not disguised
	local glow = if rally then GOLD else body.glow
	for i, p in body.parts do
		local name = body.names[i]
		local color = body.baseColors[i]
		local t = body.baseTransparency[i]
		if disguised then
			-- a plain citizen: street colours on the body and hair, a citizen's face decal (the robot's eyes are
			-- hidden under it), no robot gear
			if PERSON[name] then
				color = body.street[name] or color
			else
				t = 1
			end
			p.Color = color
			p.Transparency = t
		else
			if cold and not NEON_KEEP[name] then
				color = color:Lerp(ICE, 0.6)
			end
			if name == "IrisL" or name == "IrisR" then
				if turned then
					color = if windup then Color3.fromRGB(255, 40, 40) else glow
				end
				p.Material = if turned then Enum.Material.Neon else Enum.Material.SmoothPlastic
			elseif name == "EyeL" or name == "EyeR" then
				if turned then
					color = rgb(LOOK.turnedSclera)
				end
			elseif windup and (name == "Eyes" or name == "Visor") then
				color = Color3.fromRGB(255, 40, 40)
			elseif rally and (name == "Eyes" or name == "Core" or name == "Visor") then
				color = GOLD
			end
			if name == "Stun" then
				t = if stun then 0.2 else 1
			elseif name == "Bubble" then
				t = if shield then 0.55 else 1
			elseif name == "Guard" then
				t = if shield then 0.25 else 1
			elseif
				(RIOT[name] and not body.riotUp) -- knocked aside while the guard is broken
				or (CLAW[name] and hooked) -- the claw is out on its cable
				or gone(body, name)
			then
				t = 1
			elseif cloak then
				t = if name == "Eyes" or name == "IrisL" or name == "IrisR" then 0.6 else 0.92
			end
			p.Color = color
			p.Transparency = t
		end
		local tex = body.clothes and body.clothes[name]
		if tex then
			for _, c in tex do
				c.Transparency = if disguised then 1 else t
				c.Color3 = if cold then ICE else Color3.new(1, 1, 1)
			end
		end
		local street = body.streetClothes and body.streetClothes[name]
		if street then
			local tint = body.streetTint[if ClothesMap.half(name) == 0 then 1 else 2]
			for _, c in street do
				c.Transparency = if disguised then t else 1
				c.Color3 = tint
			end
		end
		if name == "Head" and body.faceDecal and body.faces then
			local d = body.faceDecal
			d.Texture = if turned then body.faces[2] else body.faces[1]
			d.Transparency = t
			d.Color3 = if windup then Color3.fromRGB(255, 110, 110) else Color3.new(1, 1, 1)
		end
	end
	if body.streetFace then
		body.streetFace.Transparency = if disguised then 0 else 1
	end
	if body.light then
		-- the light's glow on the ground is skipped on the Low preset (the neon light still pulses)
		body.light.Enabled = mending and not cloak and QualityController.name ~= "low"
	end
	body.rally.Enabled = rally and not disguised and not cloak
	body.bar.Enabled = body.health < 0.999 and not cloak and not disguised
	if body.fake then
		-- the hero look's pieces go with their body part (and fade with a cloak); the face cracks once unmasked
		local unmasked = bit32.band(x, EXTRA.unmasked) ~= 0
		for _, lp in body.lookParts do
			lp.p.Transparency = if gone(body, lp.owner) then 1 elseif cloak then 0.92 else lp.t
		end
		local headGone = gone(body, "Head")
		for name in CRACK do
			local i = body.index[name]
			if i then
				body.parts[i].Transparency = if unmasked
						and not headGone
						and not cloak
						and not body.crackFace
					then 0
					else 1
			end
		end
		if body.heroFace then
			body.heroFace.Texture = if unmasked and body.crackFace then body.crackFace else body.humanFace
			body.heroFace.Transparency = if headGone or cloak then 1 else 0
		end
		if body.plate then
			body.plate.Enabled = not cloak
		end
		if unmasked ~= body.unmasked and body.plateName and body.plateSub then
			body.unmasked = unmasked
			local text = FakeRules.plate(Config, body.kind, unmasked, body.ident)
			body.plateName.Text = text.name
			body.plateName.TextColor3 = if text.red then FAKE_RED else Kit.color.paper
			body.plateSub.Text = text.sub
		end
	end
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

-- What changes on one frame's flags: the riot shield knocked away with a burst of chips the moment the
-- guard breaks (only near the camera, like the shell chips)
local function edges(body: Body, near: boolean)
	local was = body.prevFlags
	local f = body.flags
	body.prevFlags = f
	if was < 0 then
		return -- new this frame
	end
	local broke = bit32.band(f, BITS.guardBroken) ~= 0 and bit32.band(was, BITS.guardBroken) == 0
	if broke and near and body.byName.Riot then
		chip(body, "Riot")
		chip(body, "RiotBar")
	end
end

-- A Medic Unit's backpack light pulses while it repairs
local GREEN_DIM = Color3.fromRGB(30, 110, 60)
local function pulse(body: Body, now: number)
	local p, pl = body.medLight, body.light
	if not p or body.flashUntil > 0 or bit32.band(body.flags, BITS.cloak) ~= 0 then
		return
	end
	local k = 0.5 + 0.5 * math.sin(now * 9)
	local i = body.index.MedLight
	p.Color = GREEN_DIM:Lerp(body.baseColors[i], k)
	if pl and pl.Enabled then
		pl.Brightness = 0.5 + k * 2
	end
end

-- Break or restore shell pieces to match the robot's health
local function updateShell(body: Body, near: boolean)
	local spark = body.health < LOOK.sparksBelow and bit32.band(body.flags, BITS.cloak) == 0
	if body.sparks.Enabled ~= spark then
		body.sparks.Enabled = spark
	end
	-- a fake's shell stays whole until its face cracks, then breaks off over the health that is left (a
	-- costumed villain's suit, lore step 11: never cracks, so its costume tears off from the crack's health on)
	local shellHealth = if body.fake
		then FakeRules.shellHealth(
			Config,
			body.health,
			body.costumed or bit32.band(body.extra, EXTRA.unmasked) ~= 0
		)
		else body.health
	if body.creature then
		-- a creature (lore step 11, chain 4) has no metal inside: its body stays whole and never sparks
		shellHealth = 1
		if body.sparks.Enabled then
			body.sparks.Enabled = false
		end
	elseif body.fake then
		local fakeSpark = shellHealth < LOOK.sparksBelow and bit32.band(body.flags, BITS.cloak) == 0
		if body.sparks.Enabled ~= fakeSpark then
			body.sparks.Enabled = fakeSpark
		end
	end
	local n = RobotDamage.count(shellHealth, #body.order, LOOK.stripBy)
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

local function disguised(body: Body): boolean
	return body.citizen and bit32.band(body.extra, EXTRA.disguise) ~= 0
end

function EnemyRenderer.flash(id: number)
	local body = live[id]
	if body and not disguised(body) then
		body.flashUntil = os.clock() + Config.Fx.hitFlash
		for i, p in body.parts do
			if body.baseTransparency[i] < 1 and not gone(body, body.names[i]) then
				p.Color = Color3.new(1, 1, 1)
				local tex = body.clothes and body.clothes[body.names[i]]
				if tex then
					for _, x in tex do
						x.Transparency = 0.85 -- the white flash shows through the clothes (weighty hits: nearly pure white)
					end
				end
			end
		end
	end
end

-- Weighty hits (Config.Combat.weight): robot `id` holds still for `freeze` seconds (your hit-stop; 0 for
-- other players' hits), then recoils along `dir` (from the hit into the robot), more when `heavy`
function EnemyRenderer.impact(id: number, dir: Vector3, heavy: boolean, freeze: number)
	local body = live[id]
	if not body or disguised(body) then
		return
	end
	local W = Config.Combat.weight
	local now = os.clock()
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if freeze > 0 then
		body.freezeUntil = now + freeze
		body.freezePos = body.pos
	end
	body.flinchAt = now + freeze
	body.flinchDir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	body.flinchStuds = if heavy then W.flinchHeavy else W.flinchStuds
	body.flinchTilt = if heavy then W.flinchTilt * 2 else W.flinchTilt
end

-- A melee swing pose (Sneak stab, Sentinel sweep) for 0.3 s
function EnemyRenderer.swing(id: number)
	local body = live[id]
	if body then
		body.swingUntil = os.clock() + 0.3
	end
end

-- Remove at once (death); returns the last drawn position, the body colour for the burst and whether it was
-- a cartoon creature (lore step 11, chain 4: it bursts into light, never into metal parts)
function EnemyRenderer.kill(id: number): (Vector3?, Color3?, boolean)
	local body = live[id]
	if not body then
		return nil, nil, false
	end
	live[id] = nil
	local pos = body.pos
	local color = body.metal
	local creature = body.creature
	release(body)
	for _, snap in snapshots do
		snap.rows[id] = nil
	end
	return pos, color, creature
end

-- A cartoon creature's defeat (nate's rule: creatures burst into light, never blood): a bright flash and a
-- swirl of glowing motes in its light colour that drift up and fade, inside the debris budget, and one seed
-- of light left on the ground for a moment (the Bramblebeast shrinks back into a seed)
function EnemyRenderer.lightBurst(pos: Vector3, color: Color3?)
	local c = color or Color3.fromRGB(255, 220, 120)
	local function mote(size: number, cf: CFrame, shape: Enum.PartType): Part
		local p = Instance.new("Part")
		p.Shape = shape
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = c
		p.Size = Vector3.one * size
		p.CFrame = cf
		p.Parent = folder
		return p
	end
	local flash = mote(4, CFrame.new(pos), Enum.PartType.Ball)
	flash.Transparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.45), { Size = Vector3.one * 16, Transparency = 1 }):Play()
	task.delay(0.5, function()
		flash:Destroy()
	end)
	local n = DebrisBudget.lease(14, 1.6)
	for k = 1, n do
		local a = (k / math.max(n, 1)) * math.pi * 2
		local r = 2 + math.random() * 3
		local p = mote(
			0.5 + math.random() * 0.6,
			CFrame.new(pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)),
			Enum.PartType.Ball
		)
		local rise = Vector3.new(
			math.cos(a) * (4 + math.random() * 4),
			8 + math.random() * 8,
			math.sin(a) * (4 + math.random() * 4)
		)
		TweenService:Create(
			p,
			TweenInfo.new(1.2 + math.random() * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = p.CFrame + rise, Transparency = 1, Size = Vector3.one * 0.1 }
		):Play()
		task.delay(1.6, function()
			p:Destroy()
		end)
	end
	local ground = Workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0))
	local seedAt = if ground then ground.Position + Vector3.new(0, 0.6, 0) else pos
	local seed = mote(1.2, CFrame.new(seedAt), Enum.PartType.Ball)
	TweenService
		:Create(
			seed,
			TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1 }
		)
		:Play()
	task.delay(2.6, function()
		seed:Destroy()
	end)
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

-- A famous fake's or an evil twin's power path (its attacks take that path's look), else nil; and, for a twin,
-- the player it copies (their effect tint)
function EnemyRenderer.pathOf(id: number): (string?, number?)
	local body = live[id]
	if body then
		return body.path, body.userId
	end
	local ident = idents[id]
	return if ident then ident.path else nil, if ident then ident.userId else nil
end

-- Where a drawn robot faces (flat), or nil
function EnemyRenderer.facing(id: number): Vector3?
	local body = live[id]
	return body and Vector3.new(-math.sin(body.yaw), 0, -math.cos(body.yaw))
end

-- Where one of a drawn robot's pieces is now (the rifle tip, the hook launcher's claw, a hand), or nil
function EnemyRenderer.point(id: number, piece: string): Vector3?
	local body = live[id]
	local p = body and body.byName[piece]
	return p and p.Position
end

-- Drawn enemies for aiming and the target hint; cloaked Sneak Bots and disguised Mimics are left out of
-- auto-aim
function EnemyRenderer.each(): { [number]: Vector3 }
	local out = {}
	for id, body in live do
		if bit32.band(body.flags, BITS.cloak) == 0 and not disguised(body) then
			out[id] = body.pos
		end
	end
	return out
end

function EnemyRenderer.flags(id: number): number
	local body = live[id]
	return if body then body.flags else 0
end

-- The second flags byte (EnemySim.EXTRA) of a drawn robot, 0 when it is not drawn
function EnemyRenderer.extra(id: number): number
	local body = live[id]
	return if body then body.extra else 0
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
	local look = cfg.body
	local extra = body.extra
	local small = look.small == true
	local sneak = cfg.ai == "sneak"
	-- a Swarmer's lunge, or a Sneak Bot's (WP6); a Sneak Bot's wind-up is a low coil, arms swept back
	local lunging = (small or sneak) and bit32.band(extra, EXTRA.lunge) ~= 0
	local coiled = sneak and windup and not lunging
	-- a Swarmer's short legs patter faster, and it runs crouched, leaning into it
	body.phase += dt * math.clamp(speed, 0, 30) * (if small then 0.75 else 0.45)
	local lean = if small then math.clamp(speed / 25, 0, 1) else 0
	-- e.y is the body centre for ground robots (the soles half its height below) and the hips for flyers
	local root = CFrame.new(body.pos) * CFrame.Angles(0, body.yaw, 0)
	if flyer then
		root *= CFrame.new(0, math.sin(now * 3 + id) * 0.35, 0) * CFrame.Angles(math.rad(-12), 0, 0)
	end
	if lunging then
		root *= CFrame.Angles(math.rad(if small then -55 else -38), 0, 0) -- a lunge: flat out, reaching
	elseif coiled then
		root *= CFrame.new(0, -L.height * 0.12, 0) -- sunk low on bent knees, ready to spring
	elseif lean > 0 then
		root *= CFrame.Angles(math.rad(-16 * lean), 0, 0)
	end
	-- a hit's recoil (EnemyRenderer.impact): a jolt away from the hit that springs back, rocking the top back
	local W = Config.Combat.weight
	local ft = (now - body.flinchAt) / W.flinch
	if ft >= 0 and ft < 1 then
		local k = math.sin(ft * math.pi) * (1 - ft * 0.5)
		local d = body.flinchDir
		local axis = Vector3.yAxis:Cross(d)
		root = CFrame.new(root.Position + d * body.flinchStuds * k)
			* CFrame.fromAxisAngle(
				if axis.Magnitude > 1e-3 then axis.Unit else Vector3.xAxis,
				math.rad(body.flinchTilt * k)
			)
			* root.Rotation
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
	local swingA = if flyer or lifted
		then 0
		else math.clamp(speed / 20, 0, 1) * math.rad(if small then 55 else 40)
	local s = math.sin(body.phase)
	local waist = CFrame.identity
	if coiled then
		waist = CFrame.Angles(math.rad(-38), 0, 0) -- coiled over its knees, head down toward its hero
	elseif sneak and not attacking then
		waist = CFrame.Angles(math.rad(-18), 0, 0) -- crouched creep
	elseif small and not lunging then
		waist = CFrame.Angles(math.rad(-10 - 14 * lean), 0, 0) -- a Swarmer's crouched scuttle
	elseif look.riot and body.riotUp then
		waist = CFrame.Angles(math.rad(-8), 0, 0) -- braced behind the shield
	end
	NpcRig.turn(rig, "Waist", waist)
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
	local aiming = look.rifle and (attacking or bit32.band(extra, EXTRA.aim) ~= 0)
	local mending = look.medpack and bit32.band(extra, EXTRA.mend) ~= 0
	local launching = look.hookArm and (attacking or bit32.band(extra, EXTRA.hooked) ~= 0)
	for _, side in SIDES do
		local name, sign = side[1], side[3]
		-- arms: aiming forward when attacking, raised overhead on a windup; elbows bend forward. yawA swings a
		-- forward arm in toward the middle (both hands on a rifle)
		local upperA, elbowA, yawA = -s * sign * swingA * 0.8, math.rad(15), 0
		if look.riot and body.riotUp and sign < 0 then
			upperA, elbowA = math.rad(75), math.rad(15) -- the shield arm held out in front
		elseif look.rifle and not lifted then
			-- the rifle in both hands: shouldered and level while it aims, held low across the body otherwise
			if aiming then
				upperA, elbowA = math.rad(if sign > 0 then 90 else 85), math.rad(if sign > 0 then 0 else 15)
			else
				upperA, elbowA = math.rad(if sign > 0 then 25 else 35), math.rad(if sign > 0 then 65 else 60)
			end
			yawA = if sign < 0 then math.rad(-30) else math.rad(8)
		elseif lunging then
			upperA, elbowA = math.rad(150), math.rad(10) -- reaching out ahead
		elseif coiled then
			upperA, elbowA = math.rad(-55), math.rad(35) -- blades swept back for the spring
		elseif windup then
			upperA, elbowA = math.rad(160), math.rad(20)
		elseif swinging then
			upperA, elbowA = math.rad(if sign > 0 then -95 else 30), 0
		elseif sign > 0 and (launching or mending) then
			upperA, elbowA = math.rad(if mending then 80 else 90), 0 -- the hook launcher aimed, or the repair hand out
		elseif attacking and (flyer or cfg.ai == "thief" or cfg.ai == "sentry") and sign > 0 then
			upperA, elbowA = math.rad(90), 0 -- gun arm up
		elseif flyer then
			upperA, elbowA = math.rad(-20), math.rad(25)
		elseif small then
			upperA, elbowA = math.rad(-35) - s * sign * swingA * 0.5, math.rad(40) -- arms swept back as it runs
		end
		NpcRig.turn(
			rig,
			name .. "Shoulder",
			if yawA ~= 0
				then CFrame.Angles(0, yawA, 0) * CFrame.Angles(upperA, 0, 0)
				else CFrame.Angles(upperA, 0, 0)
		)
		NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(elbowA, 0, 0))
		-- legs: knees bend back
		local thighA = s * sign * swingA
		local kneeA = math.max(0, -math.cos(body.phase) * sign) * swingA
		if flyer then
			thighA, kneeA = math.rad(-10), math.rad(35)
		elseif cfg.ai == "sentry" then
			thighA, kneeA = math.rad(-20 * sign), math.rad(20)
		elseif lunging then
			thighA, kneeA = math.rad(-35 + 10 * sign), math.rad(15) -- legs stretched out behind
		elseif coiled then
			thighA, kneeA = math.rad(50 + 12 * sign), math.rad(80) -- deep in the knees
		elseif small then
			thighA, kneeA = thighA + math.rad(20), kneeA + math.rad(25) -- crouched
		end
		NpcRig.turn(rig, name .. "Hip", CFrame.Angles(thighA, 0, 0))
		NpcRig.turn(rig, name .. "Knee", CFrame.Angles(-kneeA, 0, 0))
	end
end

-- Scratch kept across frames (perf pass 2026-11-18: render made about 130 tables a frame): the ids in
-- reach with their distances, the ones drawn, and the BulkMoveTo lists
local scratchIds: { number } = {}
local scratchDist: { [number]: number } = {}
local scratchKeep: { [number]: boolean } = {}
local scratchRoots: { BasePart } = {}
local scratchFrames: { CFrame } = {}
local function nearer(x: number, y: number): boolean
	return scratchDist[x] < scratchDist[y]
end

local lastRender = os.clock()
local function render()
	local now = os.clock()
	local dt = math.min(0.1, now - lastRender)
	lastRender = now
	frame += 1
	trimPool(now)
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
	local Q = QualityController.preset
	local limit = Q.enemiesDrawn
	-- robot poses and clothes by preset (phones pose fewer every frame; Config.Presets)
	local poseNear = Q.enemyPoseNear or LOOK.poseNear
	local poseEvery = Q.enemyPoseEvery or LOOK.poseEvery
	local clothesNear, clothesFar = Q.clothesNear or 25, Q.clothesFar or 80

	-- pick the nearest `limit` ids from the newest snapshot
	local ids, dists, keep = scratchIds, scratchDist, scratchKeep
	table.clear(ids)
	table.clear(dists)
	table.clear(keep)
	for id, r in newest do
		dists[id] = (Vector3.new(r.x, r.y, r.z) - cam).Magnitude
		table.insert(ids, id)
	end
	if #ids > limit then
		table.sort(ids, nearer)
	end
	for i = 1, math.min(#ids, limit) do
		keep[ids[i]] = true
	end
	for id, body in live do
		if not keep[id] then
			release(body)
			live[id] = nil
		end
	end

	local roots, cframes = scratchRoots, scratchFrames
	table.clear(roots)
	table.clear(cframes)
	for id in keep do
		local rb = b.rows[id] or newest[id]
		local ra = a.rows[id] or rb
		local pa = Vector3.new(ra.x, ra.y, ra.z)
		local pb = Vector3.new(rb.x, rb.y, rb.z)
		local pos = pa:Lerp(pb, alpha)
		local body = live[id]
		if not body then
			body = acquire(rb.typeId, id)
			assign(body, id)
			live[id] = body
			body.pos = pos
			body.yaw = rb.yaw
		end
		local bodyDt = dt
		if now < body.freezeUntil and body.freezePos then
			pos = body.freezePos -- the hit-stop: it holds still with you (limbs too), then catches up
			bodyDt = 0
		end
		local moved = Vector3.new(pos.X - body.pos.X, 0, pos.Z - body.pos.Z)
		body.speed = body.speed + (moved.Magnitude / math.max(dt, 1e-3) - body.speed) * math.min(1, dt * 8)
		body.pos = pos
		body.yaw =
			lerpAngle(body.yaw, lerpAngle(ra.yaw, rb.yaw, math.clamp(alpha, 0, 1)), math.min(1, dt * 12))
		if rb.health ~= body.health then
			body.fill.Size = UDim2.fromScale(rb.health, 1) -- the bar only when the health moves (every frame before)
		end
		body.health = rb.health
		body.state = rb.state
		body.flags = rb.flags
		body.extra = rb.extra or 0
		if body.flashUntil > 0 and now >= body.flashUntil then
			body.flashUntil = 0
			body.lastFlags = -1
		end
		local dist = (pos - cam).Magnitude
		if body.clothes or body.streetClothes then
			local level = ClothesMap.level(dist, clothesNear, clothesFar, body.shown)
			if level ~= body.shown then
				body.shown = level
				NpcRig.showClothes(body.rig, body.clothes, level)
				NpcRig.showClothes(body.rig, body.streetClothes, level)
			end
		end
		updateShell(body, dist < LOOK.chipRange)
		applyFlags(body)
		edges(body, dist < LOOK.chipRange)
		if body.medLight and bit32.band(body.extra, EXTRA.mend) ~= 0 and dist < poseNear then
			pulse(body, now)
		end
		pose(body, id, now, bodyDt, roots, cframes, dist < poseNear or (frame + id) % poseEvery == 0)
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
	-- who an evil twin copies; a twin already drawn is rebuilt in its hero's look on the next frame
	Net.listen("EnemyIdentity", function(msg: any)
		if type(msg) ~= "table" or type(msg.id) ~= "number" then
			return
		end
		idents[msg.id] = if msg.words then msg else nil
		local body = live[msg.id]
		if body and msg.words then
			live[msg.id] = nil
			release(body)
		end
	end)

	RunService.RenderStepped:Connect(FrameProf.wrap("EnemyRenderer", render))
end

return EnemyRenderer
