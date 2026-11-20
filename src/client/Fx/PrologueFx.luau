-- PrologueFx: the Ceremony prologue's world on this device only (nate's lore, build plan step 3). The server
-- (OpeningService) runs the beats and the real robots; this draws the rest for the local hero:
-- * the ceremony: the stage before Crane's Hero Hall with its banner, Silas Crane at the podium, the three
--   famous fakes standing as heroes (their hero looks, plates with hero names and titles, no robot tag), the
--   cheering crowd and the scanner drone; the scan's red sweep that stops on the hero; then the crowd flees
-- * the Spark beat: a Vigil hero's shield over the kid as the sign falls, or a Syndicate villain's blast that
--   sends the man who shoved them flying across the plaza (cartoon: he sits up dizzy and runs off)
-- * the rooftop leap in slow motion with the hero's own path look (CombatFx), Skylance's telegraphed spears
--   in the chase (they never hit), the suit snapping on piece by piece, the tunnel's falling slabs (the rubble
--   they leave is solid on this device: Leap over it), Lodestar's landing, and the billboard
-- * the camera beats: the CUT beats' shots (OpeningPlan.CUT) play through the one cutscene player
--   (CinemaClient, lore step 7: letterbox, SKIP once seen); the follow camera elsewhere
-- Reduce flashing: no flashes or shakes here either (CombatFx and CameraController already obey it).
-- The art pass (gap-prologue, 2026-11-19): the stage set (deck, trim, steps, podium, the Hall's banner frame,
-- spotlight towers, crowd barriers), the scanner drone, the falling sign, the subway slab and rubble and the
-- billboard's frame are art/blender/prologue.py's meshes (Fx.PrologueMeshes, Shared.PrologueArtKit) over the same
-- plain parts, which stay hidden and keep every collision, position and timing; until Art.Prologue is imported the
-- parts show as before. The banner and the billboard show the printed pictures (art/prologue/ads.py, Config ids)
-- and Silas Crane stands on the billboard as his own rig (his catalog face and hair; nothing drawn). The shield
-- bubble and the scanner's red sweep are effects with FxLib's pooled particles (its budget, Reduce flashing).
-- The crowd (Everything Left 406, 2026-11-20) are Roblox-avatar people like the city's citizens
-- (CitizenRenderer.dressRig: the uploaded shirts and pants, catalog faces and hair), and so are the kid and the shover
-- (their shirts tinted yellow and red so the beat still reads); Silas Crane wears his cast
-- pick (catalog face and hair) over his dark suit and red tie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local NpcAnim = require(Shared:WaitForChild("NpcAnim")) -- first-30: the crowd's cheers, the stage's wave, the gasp
local PeopleLooks = require(Shared:WaitForChild("PeopleLooks"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))
local LookKit = require(Shared:WaitForChild("LookKit"))
local CinemaPlan = require(Shared:WaitForChild("CinemaPlan"))

local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local CombatFx = require(script.Parent.CombatFx)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local CombatClient = require(script.Parent.Parent.Controllers.CombatClient)
local CitizenRenderer = require(script.Parent.Parent.Controllers.CitizenRenderer)
local FxLib = require(script.Parent.FxLib)
local PrologueMeshes = require(script.Parent.PrologueMeshes)
local PowerMeshes = require(script.Parent.PowerMeshes)
local PrologueArtKit = require(Shared:WaitForChild("PrologueArtKit"))

local PrologueFx = {}

local O = Config.Story.opening
local player = Players.LocalPlayer
local FAKES = { "Radiant", "Bulwark", "Skylance" }
local FACE = "rbxasset://textures/face.png"

type Npc = {
	rig: any,
	pos: Vector3,
	yaw: number,
	run: Vector3?,
	speed: number,
	phase: number,
	gone: number?,
	clip: string?, -- first-30: the NpcAnim clip it plays now, the one before (crossfading out) and since when
	prev: string?,
	clipAt: number?,
}

local folder: Folder? = nil
local crowd: { Npc } = {}
local stageNpcs: { [string]: Npc } = {}
local kid: Npc? = nil
local lodestar: Npc? = nil
local scanner: Part? = nil
local debris: Part? = nil
local board: Part? = nil
local slabs: { [number]: Part } = {}
local slabDown: { [number]: boolean } = {} -- slab k has landed as rubble
local slabArt: { [number]: { MeshPart } } = {} -- slab k's meshes (the falling slab, then the rubble)
local plainParts: { [string]: BasePart } = {} -- the ceremony's plain parts by PrologueArtKit frame name
local scan: { [string]: any }? = nil -- the scanner's sweep: its fan, line, ring and next mote
local lastStep: string? = nil
local leapDone = false
local sparkShown = false
local spearAt = 0
local suit: {
	hidden: { [BasePart]: boolean },
	queue: { BasePart },
	next: number,
	until_: number,
	shown: number?, -- pieces the HOLD prompt has put on (prologue-cine)
	gap: number?, -- seconds between the last pieces once the hold is done
}? =
	nil
local slowmo: ColorCorrectionEffect? = nil
-- act1-choices: the Ceremony's choice moment (the spark beat holds while its card is up): its grade and when the
-- crowd froze
local pickTint: ColorCorrectionEffect? = nil
local frozeAt: number? = nil
-- prologue-cine: the directed beats' props (a barrier, a debris pile, a beam) and the man who charges the hero
local props: { [string]: BasePart } = {}
local runner: Npc? = nil

local function v3(t: { number }?): Vector3?
	return if t then Vector3.new(t[1], t[2], t[3]) else nil
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function root(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function powerColor(): Color3
	return CombatFx.colorOf(State.hero.setId, player.UserId)
end

local function part(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function sign(p: BasePart, face: Enum.NormalId, lines: { { any } }, bg: Color3)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 20
	g.LightInfluence = 0
	g.Parent = p
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = bg
	back.BorderSizePixel = 0
	back.Parent = g
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = back
	for i, l in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.94, l[3])
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.Text = l[1]
		t.TextColor3 = l[2]
		t.Parent = back
	end
end

-- A printed picture (an uploaded Image id) over a part's face; false when there is none (the caller draws text)
local function picture(p: BasePart, face: Enum.NormalId, id: number?): boolean
	if type(id) ~= "number" or id <= 0 then
		return false
	end
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 16
	g.LightInfluence = 0
	g.Parent = p
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = "rbxassetid://" .. id
	img.ScaleType = Enum.ScaleType.Stretch
	img.Parent = g
	return true
end

-- A look's Blender meshes over its plain parts (Shared.PrologueArtKit): drawn only once every mesh is imported;
-- then the parts it stands for are hidden (they keep colliding exactly as before). Returns the meshes.
local function dress(look: string, cf: CFrame, weld: BasePart?, skip: { [string]: boolean }?): { MeshPart }
	if not folder then
		return {}
	end
	local made = PrologueMeshes.add(folder :: Folder, look, cf, weld, skip)
	if #made > 0 then
		for _, name in PrologueArtKit.LOOKS[look].hides do
			PrologueMeshes.hide(plainParts[name])
		end
	end
	return made
end

local function plate(model: Model, top: string, sub: string, color: Color3)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(160, 42)
	g.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	g.MaxDistance = 140
	g.LightInfluence = 0
	g.Adornee = head
	g.Parent = model
	local a = Instance.new("TextLabel")
	a.BackgroundTransparency = 1
	a.Size = UDim2.new(1, 0, 0.6, 0)
	a.Font = Enum.Font.GothamBlack
	a.TextScaled = true
	a.Text = top
	a.TextColor3 = color
	a.TextStrokeTransparency = 0.2
	a.Parent = g
	local b = a:Clone()
	b.Position = UDim2.fromScale(0, 0.6)
	b.Size = UDim2.new(1, 0, 0.4, 0)
	b.Font = Enum.Font.GothamBold
	b.Text = sub
	b.TextColor3 = Color3.fromRGB(240, 240, 240)
	b.Parent = g
end

-- A person on the rig (crowd, Crane, the kid): look gives gender, build and height; scale shrinks a kid
local function person(
	name: string,
	look: any,
	shirt: Color3,
	pants: Color3,
	skin: Color3,
	hair: Color3?,
	scale: number?
): any
	local factors = BodyShape.factors(Config, look)
	local layout = RigMath.layout(Config.HeroRig, factors, scale or 1)
	local rig = NpcRig.person(layout, name, shirt, pants, skin, hair, BodyShape.setKey(Config, look))
	rig.model.Parent = folder
	return rig
end

-- A hero look on the rig (the three fakes, Lodestar)
local function hero(name: string, look: any): any
	local factors =
		BodyShape.factors(Config, { gender = look.gender, build = look.build, height = look.height })
	local layout = RigMath.layout(Config.HeroRig, factors, 1)
	local skin = rgb(Config.Creator.skins[look.skin] or Config.Creator.skins[1])
	local colors = {}
	for _, n in { "Head", "UpperTorso", "LowerTorso" } do
		colors[n] = skin
	end
	for _, s in { "Left", "Right" } do
		for _, n in { "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" } do
			colors[s .. n] = skin
		end
	end
	local rig = NpcRig.build(layout, name, colors, nil, nil, BodyShape.setKey(Config, look))
	NpcRig.face(rig, FACE)
	local ok, err = pcall(LookKit.build, rig.model, look)
	if not ok then
		warn("[PrologueFx] look", name, err)
	end
	rig.model.Parent = folder
	return rig
end

-- The kid (Vigil) or the man who shoves (Syndicate): dressed like the crowd (uploaded shirt and pants, a catalog face
-- and hair, list-combat 2026-11-20; were plain flat colours), the shirt kept in the beat's colour so the camera's
-- push-in still finds them: the kid small in a yellow shirt, the shover big in a red one
local KID_SEED, SHOVER_SEED = 907, 911
local function kidRig(villain: boolean): any
	local shirt = if villain then Color3.fromRGB(190, 50, 50) else Color3.fromRGB(255, 200, 60)
	local pants = Color3.fromRGB(50, 60, 90)
	local skin = rgb(Config.Creator.skins[3])
	local rig = person(
		if villain then "Shover" else "Kid",
		{ gender = 1, build = if villain then 3 else 1, height = 3 },
		shirt,
		pants,
		skin,
		Color3.fromRGB(60, 40, 30),
		if villain then 1 else 0.68
	)
	CitizenRenderer.dressRig(
		rig,
		O.plaza.crowd.seed + (if villain then SHOVER_SEED else KID_SEED),
		skin,
		shirt,
		pants
	)
	return rig
end

local function npc(rig: any, pos: Vector3, yaw: number): Npc
	local n: Npc =
		{ rig = rig, pos = pos, yaw = yaw, run = nil, speed = 0, phase = math.random() * 6, gone = nil }
	NpcRig.place(rig, CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
	return n
end

local function yawTo(from: Vector3, to: Vector3): number
	local d = to - from
	return math.atan2(-d.X, -d.Z)
end

---------------------------------------------------------------------------
-- The ceremony's scene
---------------------------------------------------------------------------

local SHIRTS = {
	{ 235, 90, 80 },
	{ 80, 150, 235 },
	{ 250, 200, 70 },
	{ 120, 200, 120 },
	{ 200, 120, 220 },
	{ 245, 245, 245 },
	{ 255, 150, 60 },
	{ 70, 190, 190 },
}
local PANTS = { { 50, 60, 90 }, { 70, 70, 76 }, { 120, 90, 60 }, { 40, 40, 44 } }

local function clearScene()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(crowd)
	table.clear(stageNpcs)
	table.clear(slabs)
	table.clear(slabDown)
	table.clear(slabArt)
	table.clear(plainParts)
	scan = nil
	kid, lodestar, scanner, debris, board = nil, nil, nil, nil, nil
	sparkShown, leapDone, suit = false, false, nil
	table.clear(props)
	runner = nil
end

local function ensureFolder()
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Prologue"
		f.Parent = Workspace
		folder = f
	end
end

-- Silas Crane on the rig (the stage, and the billboard at `scale`): a sharp dark suit, a red tie, slicked silver
-- hair as the fallback cap; his own catalog face and hair (Config.NpcLooks.cast.crane, the same as his comic
-- portrait), the same on every device and at every size
local function craneRig(scale: number): any
	local crane = person(
		"Silas Crane",
		{ gender = 1, build = 2, height = 4 },
		Color3.fromRGB(34, 36, 44),
		Color3.fromRGB(34, 36, 44),
		rgb(Config.Creator.skins[2]),
		Color3.fromRGB(190, 195, 205),
		scale
	)
	NpcRig.fix(
		crane,
		"UpperTorso",
		part(Vector3.new(0.5, 1.4, 0.2) * scale, CFrame.identity, Color3.fromRGB(200, 30, 40)),
		CFrame.new(0, 0.1 * scale, -crane.parts.UpperTorso.Size.Z / 2 - 0.05 * scale)
	)
	NpcRig.wearCast(crane, PeopleLooks.castPick(Config, "crane"))
	return crane
end

local function buildCeremony(o: { [string]: any })
	ensureFolder()
	local stage, face, hall = v3(o.stage), v3(o.face), v3(o.hall)
	if not stage or not face or not hall then
		return
	end
	local P = O.plaza.stage
	local yawOut = yawTo(stage, stage + face)
	local base =
		CFrame.lookAt(stage - Vector3.new(0, P.height / 2, 0), stage - Vector3.new(0, P.height / 2, 0) + face)
	-- the stage: a deck, a gold trim, steps down to the crowd, a podium and the Hall's banner behind (the plain
	-- parts; the Blender looks draw over them once imported, the deck and steps still the colliding floor)
	plainParts.deck = part(
		Vector3.new(P.width, P.height, P.depth),
		base,
		Color3.fromRGB(70, 74, 92),
		Enum.Material.Concrete,
		true
	)
	plainParts.trim = part(
		Vector3.new(P.width + 0.6, 0.6, P.depth + 0.6),
		base * CFrame.new(0, P.height / 2, 0),
		Color3.fromRGB(255, 210, 60),
		Enum.Material.Metal
	)
	plainParts.steps = part(
		Vector3.new(10, P.height / 2, 4),
		base * CFrame.new(0, -P.height / 4, -P.depth / 2 - 2),
		Color3.fromRGB(70, 74, 92),
		Enum.Material.Concrete,
		true
	)
	plainParts.podium = part(
		Vector3.new(3, 4, 2),
		CFrame.new(v3(o.crane) :: Vector3 + face * 2.5 + Vector3.new(0, 2, 0)),
		Color3.fromRGB(30, 32, 40)
	)
	local banner = part(
		Vector3.new(P.width, 16, 1),
		CFrame.lookAt(
			hall + face * (Config.City.downtown.beacon.width / 2 + 0.8) + Vector3.new(0, 20, 0),
			hall + face * 100 + Vector3.new(0, 20, 0)
		),
		Color3.fromRGB(30, 34, 60)
	)
	plainParts.banner = banner
	if not picture(banner, Enum.NormalId.Front, O.art.banner) then
		sign(banner, Enum.NormalId.Front, {
			{ O.hall, Color3.fromRGB(255, 210, 60), 0.5 },
			{ O.brand, Color3.fromRGB(240, 240, 240), 0.3 },
		}, Color3.fromRGB(30, 34, 60))
	end
	local low = QualityController.name == "low"
	dress("Stage", base)
	dress("Podium", base)
	dress("Spotlights", base, nil, if low then { SpotlightsBeam = true } else nil) -- no light beams on phones
	dress("Barriers", base)
	dress("HallBanner", banner.CFrame)
	-- Silas Crane: a sharp dark suit, a red tie, his catalog face and hair
	local crane = craneRig(1)
	plate(crane.model, "SILAS CRANE", O.brand, Color3.fromRGB(255, 210, 60))
	stageNpcs.crane = npc(crane, v3(o.crane) :: Vector3, yawOut)
	-- the famous fakes as the city's heroes: their hero names and titles, no robot tag
	for i, kind in FAKES do
		local at = v3(o.fakes and o.fakes[i])
		if at and Config.Enemies[kind] then
			local rig = hero(kind, FakeRules.look(Config, kind))
			local pl = FakeRules.plate(Config, kind, false, nil)
			plate(rig.model, pl.name, pl.sub, Color3.fromRGB(255, 220, 120))
			stageNpcs[kind] = npc(rig, at, yawOut)
		end
	end
	-- the scanner drone over the stage
	local sc = v3(o.scanner)
	if sc then
		local d =
			part(Vector3.new(4, 4, 4), CFrame.new(sc), Color3.fromRGB(220, 222, 230), Enum.Material.Metal)
		d.Shape = Enum.PartType.Ball
		local ring = part(
			Vector3.new(0.4, 7, 7),
			CFrame.new(sc) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(255, 60, 60),
			Enum.Material.Neon
		)
		ring.Shape = Enum.PartType.Cylinder
		scanner = d
		plainParts.scanner, plainParts.scannerRing = d, ring
		-- the drone's meshes ride its bob (welded to the ball); the ring's part never moved, so it is just hidden
		dress("Scanner", d.CFrame, d)
	end
	-- the crowd, facing the stage (fewer on the phone preset)
	local start = v3(o.start) :: Vector3
	local count = if QualityController.name == "low" then O.plaza.crowd.low else O.plaza.crowd.count
	for i, c in o.crowd or {} do
		if #crowd >= count then
			break
		end
		local at = v3(c) :: Vector3
		if (at - start).Magnitude > 3.5 then
			local rig = person(
				"Citizen",
				{ gender = 1 + i % 2, build = 1 + i % 3, height = 2 + i % 3 },
				rgb(SHIRTS[i % #SHIRTS + 1]),
				rgb(PANTS[i % #PANTS + 1]),
				rgb(Config.Creator.skins[i % 8 + 1]),
				rgb(PANTS[(i + 1) % #PANTS + 1])
			)
			CitizenRenderer.dressRig(rig, O.plaza.crowd.seed + i, rgb(Config.Creator.skins[i % 8 + 1]))
			table.insert(crowd, npc(rig, at, yawTo(at, stage) + (math.random() - 0.5) * 0.3))
		end
	end
	-- the kid (Vigil) or the man who shoves (Syndicate), by the spark point
	local k = v3(o.kid)
	if k then
		kid = npc(kidRig(o.side == "villain"), k, yawTo(k, start))
	end
end

---------------------------------------------------------------------------
-- Poses and the crowd's panic
---------------------------------------------------------------------------

-- A clip's joint angles (degrees, an optional lift) as a joint turn
local function clipTurn(a: { number }): CFrame
	local cf = CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
	if (a[4] or 0) ~= 0 then
		cf = CFrame.new(0, a[4], 0) * cf
	end
	return cf
end

-- A running person (the crowd fleeing, the shover running off) takes the heroes' own sprint stride (HeroAnim
-- runFast: knees up, fists pumping, a bob; list-combat 2026-11-20, was a hip and shoulder swing), its pace matched
-- to the run's speed so the feet keep up with the ground
local RUN_CLIP = "runFast"
local function poseRun(n: Npc, speed: number, t: number)
	local angles = HeroAnim.sample(RUN_CLIP, t * speed / HeroAnim.runFastSpeed + n.phase)
	for joint in n.rig.motors do
		local a = angles[joint]
		NpcRig.turn(n.rig, joint, if a then clipTurn(a) else CFrame.identity)
	end
end

local function poseWalk(n: Npc, speed: number, t: number)
	if speed > 8 then
		poseRun(n, speed, t)
		return
	end
	local swing = math.sin(t * (6 + speed * 0.3) + n.phase) * math.clamp(speed / 14, 0, 1) * 0.8
	for _, s in { { "Left", 1 }, { "Right", -1 } } do
		NpcRig.turn(n.rig, s[1] .. "Hip", CFrame.Angles(swing * s[2], 0, 0))
		NpcRig.turn(n.rig, s[1] .. "Shoulder", CFrame.Angles(-swing * s[2] * 0.9, 0, 0))
	end
end

-- A whole-body clip from Shared.NpcAnim (first-30, 2026-11-20: was a shoulder sine), crossfading from the clip the
-- person played before over NpcAnim.crowd.blend; joints the clip leaves out rest
local clipNow: { [string]: { number } } = {}
local clipPrev: { [string]: { number } } = {}
local function poseClip(n: Npc, clip: string, t: number)
	if n.clip ~= clip then
		n.prev, n.clip, n.clipAt = n.clip, clip, t
	end
	local w = math.clamp((t - (n.clipAt or t)) / NpcAnim.crowd.blend, 0, 1)
	local a = NpcAnim.sample(clip, t + n.phase, clipNow)
	local b = if w < 1 and n.prev then NpcAnim.sample(n.prev, t + n.phase, clipPrev) else nil
	for joint in n.rig.motors do
		local k = a[joint]
		local cf = if k then clipTurn(k) else CFrame.identity
		if b then
			local kb = b[joint]
			cf = (if kb then clipTurn(kb) else CFrame.identity):Lerp(cf, w)
		end
		NpcRig.turn(n.rig, joint, cf)
	end
end

-- each person in the crowd keeps one cheer (a seeded pick from its phase, so the crowd mixes cheers and claps)
local function cheerOf(n: Npc): string
	return NpcAnim.pick(NpcAnim.crowd.cheer, (n.phase / 6) % 1)
end

local function moveNpc(n: Npc, dt: number, t: number)
	if n.run and n.speed > 0 then
		n.pos += n.run * n.speed * dt
		n.yaw = math.atan2(-n.run.X, -n.run.Z)
		NpcRig.place(n.rig, CFrame.new(n.pos) * CFrame.Angles(0, n.yaw, 0))
		poseWalk(n, n.speed, t)
	end
end

local function flee(from: Vector3)
	for _, n in crowd do
		if not n.run then
			local d = Vector3.new(n.pos.X - from.X, 0, n.pos.Z - from.Z)
			if d.Magnitude < 0.5 then
				d = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			end
			local a = (math.random() - 0.5) * 0.9
			n.run = (CFrame.Angles(0, a, 0) * d.Unit)
			n.speed = 14 + math.random() * 8
			n.gone = os.clock() + 4 + math.random() * 3
		end
	end
end

local function fade(n: Npc, time: number)
	for _, p in n.rig.model:GetDescendants() do
		if p:IsA("BasePart") or p:IsA("Decal") or p:IsA("Texture") then
			TweenService:Create(p, TweenInfo.new(time), { Transparency = 1 }):Play()
		end
	end
	local model = n.rig.model
	task.delay(time + 0.05, function()
		model:Destroy()
	end)
end

---------------------------------------------------------------------------
-- The camera beats
---------------------------------------------------------------------------

-- (lore step 7) each shot is a CinemaPlan dolly: the camera from a's spot to b's, its look from a's
-- point to b's (the same shots as before, now played by CinemaClient)
type Shot = { t0: number, t1: number, a: { Vector3 }, b: { Vector3 } }

local function look(from: Vector3, at: Vector3): { Vector3 }
	return { from, at }
end

local function P(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function toPlan(list: { Shot }): { CinemaPlan.Shot }
	local out = {}
	for _, s in list do
		table.insert(out, {
			kind = "dolly",
			t0 = s.t0,
			t1 = s.t1,
			from = P(s.a[1]),
			at = P(s.a[2]),
			to = P(s.b[1]),
			at2 = P(s.b[2]),
		})
	end
	return out
end

local function shots(step: string, o: { [string]: any }): { Shot }
	local list: { Shot } = {}
	local stage, face = v3(o.stage), v3(o.face)
	local start, crane = v3(o.start), v3(o.crane)
	local r = root()
	local up = Vector3.new(0, 1, 0)
	if (step == "ceremony" or step == "scan") and stage and face and start and crane then
		local side = Vector3.new(-face.Z, 0, face.X)
		local B = O.beats.ceremony
		if step == "ceremony" then
			table.insert(list, {
				t0 = 0,
				t1 = B * 0.25,
				a = look(start + face * 26 + up * 22, stage + up * 4),
				b = look(start + face * 14 + up * 12, stage + up * 5),
			})
			table.insert(list, {
				t0 = B * 0.25,
				t1 = B * 0.42,
				a = look(crane + face * 16 + up * 5 + side * 4, crane + up * 4.5),
				b = look(crane + face * 10 + up * 4.5 + side * 2, crane + up * 4.5),
			})
			local f1, f3 = v3(o.fakes[1]) :: Vector3, v3(o.fakes[3]) :: Vector3
			table.insert(list, {
				t0 = B * 0.42,
				t1 = B * 0.72,
				a = look(f1 + face * 14 + up * 5, f1 + up * 5),
				b = look(f3 + face * 14 + up * 5, f3 + up * 5),
			})
			table.insert(list, {
				t0 = B * 0.72,
				t1 = B,
				a = look(stage + face * 6 + up * 8, start + up * 3),
				b = look(crane + face * 4 + up * 6, start + up * 3),
			})
		else
			local S = O.beats.scan
			table.insert(list, {
				t0 = 0,
				t1 = S * 0.45,
				a = look(start + side * 30 + face * 6 + up * 10, start - side * 10),
				b = look(start + side * 22 + face * 4 + up * 8, start),
			})
			table.insert(list, {
				t0 = S * 0.45,
				t1 = S,
				a = look(start - face * 9 + up * 4, start + up * 3),
				b = look(start - face * 5 + up * 3.4, start + up * 3),
			})
		end
	elseif step == "rescue" and r then
		local p = r.Position
		local fwd = r.CFrame.LookVector
		local side = Vector3.new(-fwd.Z, 0, fwd.X)
		table.insert(list, {
			t0 = 0,
			t1 = O.beats.rescue,
			a = look(p + side * 16 + up * 1.5, p + up * 6),
			b = look(p + side * 11 + up * 2.5, p + up * 4),
		})
	elseif step == "title" then
		local bb = o.billboard
		local hall = v3(o.hall)
		if bb and hall and face then
			local at = Vector3.new(bb[1], bb[2], bb[3])
			local n = Vector3.new(bb[4], 0, bb[5])
			table.insert(list, {
				t0 = 0,
				t1 = O.beats.title,
				a = look(at + n * 120 + up * -20, at),
				b = look(at + n * 80 + up * -10, at),
			})
		end
	end
	return list
end

-- The CUT beat's scene for the cutscene player: the server times it (the beat's clock, held at 0 on the main
-- menu's hold), SKIP follows OpeningPlan.canSkip (a replay, or this save has seen the beat: lore step 7)
local function playBeat(step: string, o: { [string]: any })
	local list = toPlan(shots(step, o))
	if #list == 0 then
		CinemaClient.stop("prologue")
		return
	end
	CinemaClient.play({
		owner = "prologue",
		key = step,
		bit = CinemaPlan.bit(Config, step),
		shots = list,
		seconds = OpeningPlan.limit(Config, step),
		beat = true,
		clock = function(): number
			return if StoryClient.opening.hold then 0 else StoryClient.beatTime()
		end,
		bars = function(): boolean
			return not StoryClient.opening.hold
		end,
		canSkip = function(): boolean
			local op = StoryClient.opening
			return not op.hold and OpeningPlan.canSkip(step, op.replay == true or op.seen == true)
		end,
		skip = StoryClient.skipBeat,
	})
end

-- The Ceremony's choice (act1-choices, 2026-11-19): right after the Spark fires the moment freezes into a short
-- camera beat (letterbox, the hero held still, a slow push past the hero toward the kid or the shover, the world
-- greyed a little) while StoryHud's choice card is up. Never on the rooftop quick-time prompts: the server asks
-- only in the spark beat. The server times it (Config.Story.opening.pick.wait); no SKIP (the card is the way on).
local PICK_KEY = "ceremonyPick"
local function playPick(o: { [string]: any })
	local r = root()
	local k = v3(o.kid) or v3(o.spark)
	if not r or not k then
		return
	end
	local p = r.Position
	local flat = Vector3.new(k.X - p.X, 0, k.Z - p.Z)
	local fwd = if flat.Magnitude > 0.5 then flat.Unit else Vector3.new(0, 0, -1)
	local side = Vector3.new(-fwd.Z, 0, fwd.X)
	local up = Vector3.new(0, 1, 0)
	local mid = p:Lerp(k, 0.5) + up * 3
	local seconds = O.pick.wait
	local startedAt = os.clock()
	CinemaClient.play({
		owner = "prologue",
		key = PICK_KEY,
		shots = toPlan({
			{
				t0 = 0,
				t1 = seconds,
				a = look(p - fwd * 9 + side * 7 + up * 5, mid),
				b = look(p - fwd * 5 + side * 5 + up * 4, mid + fwd * 2),
			},
		}),
		seconds = seconds,
		beat = true,
		clock = function(): number
			return os.clock() - startedAt
		end,
		bars = function(): boolean
			return true
		end,
		canSkip = function(): boolean
			return false
		end,
		skip = function() end,
	})
	if not pickTint then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "CeremonyPick"
		cc.Saturation = -0.35
		cc.Contrast = 0.08
		cc.Parent = Lighting
		pickTint = cc
	end
	frozeAt = frozeAt or os.clock()
end

local function endPick()
	local cur = CinemaClient.current
	if cur and cur.owner == "prologue" and cur.key == PICK_KEY then
		CinemaClient.stop("prologue")
	end
	if pickTint then
		pickTint:Destroy()
		pickTint = nil
	end
	-- the frozen crowd and kid pick up where they stopped (their run-off timers move by the freeze)
	if frozeAt then
		local held = os.clock() - frozeAt
		frozeAt = nil
		for _, n in crowd do
			if n.gone then
				n.gone += held
			end
		end
		if kid and (kid :: Npc).gone then
			(kid :: Npc).gone = ((kid :: Npc).gone :: number) + held
		end
	end
end

---------------------------------------------------------------------------
-- The beats' moments
---------------------------------------------------------------------------

-- A flat triangle a, b, c from two wedges (the scanner's fan of light)
local function triangle(w1: WedgePart, w2: WedgePart, a: Vector3, b: Vector3, c: Vector3)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab)
	if right.Magnitude < 1e-4 or bc.Magnitude < 1e-4 then
		return
	end
	right = right.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	w1.Size = Vector3.new(0.05, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(0.05, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local SCAN_RED = Color3.fromRGB(255, 46, 46)

local function glowPart(size: Vector3, alpha: number): Part
	local p = part(size, CFrame.identity, SCAN_RED, Enum.Material.Neon)
	p.Transparency = alpha
	return p
end

local function wedge(alpha: number): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
	w.Material = Enum.Material.Neon
	w.Color = SCAN_RED
	w.Transparency = alpha
	w.Parent = folder
	return w
end

local function endScan()
	local s = scan
	if s then
		for _, p in s.parts do
			p:Destroy()
		end
		scan = nil
	end
end

-- The scan: a fan of red light from the drone's lens sweeps a line across the crowd, slows and locks onto the
-- hero (the same path and timing as before), then rings the hero with a target rune. Pooled FxLib motes ride the
-- line within the device's particle budget; with Reduce flashing on, nothing pulses.
local function sweep(o: { [string]: any }, t: number)
	local start, face = v3(o.start), v3(o.face)
	if not start or not face or not folder then
		return
	end
	local side = Vector3.new(-face.Z, 0, face.X)
	if not scan then
		local fan1, fan2, fan3, fan4 = wedge(0.78), wedge(0.78), wedge(0.78), wedge(0.78)
		local line = glowPart(Vector3.new(0.5, 0.18, 40), 0.15)
		local ring = glowPart(Vector3.new(0.18, 8, 8), 1)
		ring.Shape = Enum.PartType.Cylinder
		scan = {
			parts = { fan1, fan2, fan3, fan4, line, ring },
			fan = { fan1, fan2, fan3, fan4 },
			line = line,
			ring = ring,
			mote = 0,
			rune = 0,
			locked = false,
		}
		AudioController.play("bossWarning")
	end
	local s = scan :: { [string]: any }
	local lock = O.beats.scan * 0.42
	local x = if t < lock then math.sin(t / lock * math.pi * 1.5) * 26 * (1 - t / lock) else 0
	local g = start + side * x + Vector3.new(0, 0.12, 0)
	local half = if t < lock then 20 else 3.6
	local a, b = g - face * half, g + face * half
	local lens = if scanner
		then (scanner :: Part).Position - Vector3.new(0, 1.45, 0)
		else g + Vector3.new(0, 20, 0)
	-- the fan: two thin triangles a hair apart, so it reads from either side
	triangle(s.fan[1], s.fan[2], lens, a, b)
	triangle(s.fan[3], s.fan[4], lens + side * 0.06, a + side * 0.06, b + side * 0.06)
	s.line.Size = Vector3.new(0.5, 0.18, half * 2)
	s.line.CFrame = CFrame.lookAt(g, g + face)
	local now = os.clock()
	if t < lock then
		if now >= s.mote then
			s.mote = now + 0.12
			FxLib.emit("spark", SCAN_RED, a:Lerp(b, math.random()), 2, Vector3.new(0, 1, 0))
		end
	else
		if not s.locked then
			s.locked = true
			AudioController.play("aimLock", start) -- (first-30) the lock is heard, not only seen: the sniper's lock-on
			FxLib.shock(start + Vector3.new(0, 0.2, 0), 7, SCAN_RED)
			FxLib.emit("spark", SCAN_RED, start + Vector3.new(0, 1, 0), 10)
		end
		local pulse = if CombatFx.reduceFlashing then 0 else math.sin(now * 2 * math.pi * 1.5) * 0.12
		s.ring.Transparency = 0.25 + pulse
		s.ring.CFrame = CFrame.new(start + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		if now >= s.rune then
			s.rune = now + 0.55
			FxLib.emit("rune", SCAN_RED, start + Vector3.new(0, 0.25, 0), 1, Vector3.new(0, 1, 0))
		end
	end
end

local function fireSpark(o: { [string]: any })
	if sparkShown or not kid then
		return
	end
	sparkShown = true
	local k = kid :: Npc
	local r = root()
	local color = powerColor()
	local style = State.hero.fxStyle
	if OpeningPlan.sparkBeat(o.side) == "shield" then
		-- the sign comes down; the Spark throws a shield over the kid; it bounces off. The bubble pops open (a
		-- shimmering ForceField shell over a faint tinted core), hex plates and a ring flare out (FxLib), the hit
		-- ripples it, and it fades out in wisps.
		local center = k.pos + Vector3.new(0, 2, 0)
		local shield = part(Vector3.one, CFrame.new(center), color, Enum.Material.ForceField)
		shield.Shape = Enum.PartType.Ball
		shield.Transparency = 0.2
		local core = part(Vector3.one, CFrame.new(center), color, Enum.Material.Glass)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.82
		local pop = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(shield, pop, { Size = Vector3.new(9, 9, 9) }):Play()
		TweenService:Create(core, pop, { Size = Vector3.new(8.6, 8.6, 8.6) }):Play()
		FxLib.shock(k.pos + Vector3.new(0, 0.2, 0), 5, color)
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			local dir = Vector3.new(math.cos(a), 0.6, math.sin(a)).Unit
			FxLib.emit("hex", color, center + dir * 4.2, 2, dir)
		end
		FxLib.emit("star", color, center + Vector3.new(0, 4.4, 0), 3)
		if r then
			CombatFx.bolt(r.Position, center, style, color, State.hero.setId)
		end
		local d = debris
		if d then
			local hit = Vector3.new(d.Position.X, k.pos.Y + 7, d.Position.Z)
			TweenService:Create(
				d,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(hit) }
			):Play()
			task.delay(0.32, function()
				CombatFx.burst(hit, style, color)
				AudioController.play("clash", hit)
				CameraController.shake(0.25, 0.4)
				-- the shell takes the hit: sparks and plates off the top, a quick ripple (none with Reduce flashing)
				FxLib.emit("spark", color, hit - Vector3.new(0, 1.5, 0), 12, Vector3.new(0, 1, 0))
				FxLib.emit("hex", color, hit - Vector3.new(0, 1.5, 0), 6, Vector3.new(0, 1, 0))
				if shield.Parent and not CombatFx.reduceFlashing then
					local ripple =
						TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
					TweenService:Create(shield, ripple, { Size = Vector3.new(9.8, 8.4, 9.8) }):Play()
				end
				TweenService:Create(d, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {
					CFrame = CFrame.new(hit + Vector3.new(12, -5, 6)) * CFrame.Angles(0.6, 0.2, 1.2),
				}):Play()
			end)
		end
		task.delay(2.2, function()
			if shield.Parent then
				TweenService:Create(shield, TweenInfo.new(0.5), { Transparency = 1 }):Play()
				TweenService:Create(core, TweenInfo.new(0.5), { Transparency = 1 }):Play()
				FxLib.emit("wisp", color, center, 6)
			end
			local start = v3(o.start)
			if start and kid == k then
				k.run = Vector3.new(k.pos.X - start.X, 0, k.pos.Z - start.Z).Unit
				k.speed = 12
				k.gone = os.clock() + 3
			end
		end)
	else
		-- the shover flies across the plaza in a cartoon arc, sits up dizzy and runs off
		local from = if r then r.Position else k.pos
		local dir = Vector3.new(k.pos.X - from.X, 0, k.pos.Z - from.Z)
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
		local land = k.pos + dir * O.spark.blast
		if r then
			CombatFx.bolt(r.Position, k.pos + Vector3.new(0, 2, 0), style, color, State.hero.setId)
		end
		CombatFx.word(k.pos + Vector3.new(0, 4, 0), State.hero.setId, color, true)
		AudioController.play("clash", k.pos)
		CameraController.shake(0.25, 0.5)
		local t0 = os.clock()
		local p0 = k.pos
		k.run, k.speed = nil, 0
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			local u = math.clamp((os.clock() - t0) / 1.1, 0, 1)
			local pos = p0:Lerp(land, u) + Vector3.new(0, math.sin(u * math.pi) * 22, 0)
			k.pos = pos
			NpcRig.place(
				k.rig,
				CFrame.new(pos) * CFrame.Angles(0, k.yaw, 0) * CFrame.Angles(u * math.pi * 4, 0, 0)
			)
			if u >= 1 and conn then
				conn:Disconnect()
				NpcRig.place(k.rig, CFrame.new(land) * CFrame.Angles(0, k.yaw, 0))
				CombatFx.burst(land, style)
				task.delay(1.2, function()
					if kid == k then
						k.run = dir
						k.speed = 15
						k.gone = os.clock() + 3
					end
				end)
			end
		end)
	end
end

-- The rooftop leap's slow motion with the path's own power look (prologue-cine: Fx.PrologueQte moves the hero on
-- the authored arc, Shared.PrologueCine; this is its look: the grade, the punch and the super's flourish mid-air)
local function slowLeap(o: { [string]: any }, time: number)
	if leapDone then
		return
	end
	local goal = v3(o.roofs and o.roofs[2])
	local r = root()
	if not goal or not r then
		return
	end
	leapDone = true
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "PrologueSlowMo"
	cc.TintColor = Color3.new(1, 1, 1):Lerp(powerColor(), 0.25)
	cc.Saturation = 0.25
	cc.Contrast = if CombatFx.reduceFlashing then 0 else 0.15
	cc.Parent = Lighting
	slowmo = cc
	CameraController.punch(0.12)
	task.delay(time * 0.35, function()
		local rr = root()
		local id = AbilityRules.superOf(Config, State.hero.setId)
		local row = id and Config.Abilities.list[id]
		if rr and row then
			local d = (goal - rr.Position) * Vector3.new(1, 0, 1)
			CombatFx.castFlourish(
				row,
				State.hero.fxStyle,
				rr.Position,
				if d.Magnitude > 0.1 then d.Unit else rr.CFrame.LookVector
			)
			CombatFx.superMoment(row, State.hero.fxStyle, {
				o = rr.Position,
				d = if d.Magnitude > 0.1 then d.Unit else rr.CFrame.LookVector,
				c = rr.Position,
				a = player.UserId,
			})
		end
		AudioController.play("super", rr and rr.Position)
	end)
	task.delay(time, function()
		if slowmo == cc then
			TweenService
				:Create(
					cc,
					TweenInfo.new(0.5),
					{ Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }
				)
				:Play()
			task.delay(0.55, function()
				cc:Destroy()
			end)
			slowmo = nil
		end
	end)
end

local function spears(o: { [string]: any }, now: number)
	local id = o.fake
	local from = id and EnemyRenderer.position(id)
	local r = root()
	if not from or not r or now < spearAt then
		return
	end
	spearAt = now + O.chase.throwEvery
	-- telegraphed, and always a stride wide: the chase scares, it never hurts
	local a = math.random() * math.pi * 2
	local at = r.Position
		+ r.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * 0.3
		+ Vector3.new(math.cos(a) * 9, -2.5, math.sin(a) * 9)
	CombatFx.warn(at, 4, O.chase.warn)
	task.delay(O.chase.warn, function()
		CombatFx.bolt(from + Vector3.new(0, 3, 0), at, "Comic", Color3.fromRGB(110, 210, 255), "Blade")
		CombatFx.burst(at, "Comic")
		AudioController.play("clash", at)
	end)
end

-- The suit: the street outfit comes off on the server; here every piece of the look pops on in turn
local ORDER = {
	LeftFoot = 1,
	RightFoot = 1,
	LeftLowerLeg = 2,
	RightLowerLeg = 2,
	LeftUpperLeg = 3,
	RightUpperLeg = 3,
	LowerTorso = 4,
	LeftHand = 5,
	RightHand = 5,
	LeftLowerArm = 6,
	RightLowerArm = 6,
	LeftUpperArm = 7,
	RightUpperArm = 7,
	UpperTorso = 8,
	Head = 9,
}

local function suitStep(now: number)
	local s = suit
	local char = player.Character
	if not s or not char then
		return
	end
	if now < s.until_ then
		local hl = char:FindFirstChild("HeroLook")
		local fresh = {}
		for _, d in if hl then hl:GetDescendants() else {} do
			if d:IsA("BasePart") and not s.hidden[d] then
				s.hidden[d] = true
				d.LocalTransparencyModifier = 1
				table.insert(fresh, d)
			end
		end
		if #fresh > 0 then
			for _, p in fresh do
				table.insert(s.queue, p)
			end
			table.sort(s.queue, function(a, b)
				local wa = a:FindFirstChildOfClass("WeldConstraint")
				local wb = b:FindFirstChildOfClass("WeldConstraint")
				local oa = wa and wa.Part0 and ORDER[wa.Part0.Name] or 8
				local ob = wb and wb.Part0 and ORDER[wb.Part0.Name] or 8
				return oa < ob
			end)
		end
	end
	if now >= s.next and #s.queue > 0 then
		s.next = now + (s.gap or O.suit.pieceGap)
		local p = table.remove(s.queue, 1) :: BasePart
		if p.Parent then
			p.LocalTransparencyModifier = 0
			CombatFx.burst(p.Position, State.hero.fxStyle, powerColor())
			AudioController.play("skillRank", p.Position)
		end
		if #s.queue == 0 and now >= s.until_ then
			CombatFx.banner(
				if State.hero.fxStyle == "Anime" then "SUIT UP" else "SUIT UP!",
				powerColor(),
				State.hero.fxStyle
			)
			CameraController.punch(0.08)
			suit = nil
		end
	elseif now >= s.until_ + 2 and #s.queue == 0 then
		suit = nil
	end
end

---------------------------------------------------------------------------
-- The directed beats' moments (prologue-cine, 2026-11-20; Shared.PrologueCine, Fx.PrologueQte): what each prompt
-- shows as it comes up ("show"), when it is answered ("hit") and what a miss looks like ("miss": a near miss,
-- never damage). Everything here is on this device only and goes when the prologue ends.
-- The tunnel's falling roof chunks are Art.Rubble's broken blocks and the beam that pins the hero is the Blender
-- steel girder (Art.Powers Girder) since 2026-11-20, welded over their plain parts (which hide); before the meshes
-- are imported the parts show; the run's knocked-over barrier is Art.Rubble's sawhorse barricade (striped planks,
-- steel A-frame legs, a warning lamp), standing knocked askew across the street, over its hidden parts.
---------------------------------------------------------------------------

-- A mesh welded over a plain part so it follows the part's tweens; the part hides
local function weldOver(p: BasePart, m: BasePart)
	m.Anchored = false
	m.CanCollide = false
	m.CanQuery = false
	m.CanTouch = false
	m.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = p
	w.Part1 = m
	w.Parent = m
	m.Parent = p
end

-- A falling roof chunk as one of Art.Rubble's broken blocks (Chunk1-3), stretched to the part's box
local function coverChunk(c: BasePart, k: number)
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Rubble")
	local src = set and set:FindFirstChild("Chunk" .. k, true)
	if not (src and src:IsA("MeshPart")) then
		return
	end
	local m = MeshFix.clone(src)
	m:ClearAllChildren()
	m.Size = c.Size
	m.CFrame = c.CFrame * MeshFix.of(m)
	m.Color = c.Color
	m.Material = c.Material
	m.CastShadow = true
	weldOver(c, m)
	PrologueMeshes.hide(c)
end

-- The run's barrier as Art.Rubble's sawhorse barricade (Barrier: planks, stripes, legs, lamp), standing on its
-- feet at `at` facing along `flat`, knocked askew; the plain part and its stripe bars hide under it
local BARRIER = { scale = 0.85, yaw = 12, roll = 5 }
local function coverBarrier(b: BasePart, at: Vector3, flat: Vector3)
	local row = Config.RubbleArt and Config.RubbleArt.Barrier
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Rubble")
	if not (row and set) then
		return
	end
	local srcs = {}
	for name, m in row do
		if name ~= "box" then
			local src = set:FindFirstChild(name, true)
			if not (src and src:IsA("MeshPart")) then
				return -- all or none
			end
			srcs[name] = { src, m }
		end
	end
	local k = BARRIER.scale
	-- the feet (2.4 below the planks' centre as drawn) on the ground
	local frame = CFrame.lookAt(at + Vector3.new(0, 2.4 * k, 0), at + Vector3.new(0, 2.4 * k, 0) + flat)
		* CFrame.Angles(0, math.rad(BARRIER.yaw), math.rad(BARRIER.roll))
	for name, pair in srcs do
		local src, m = pair[1], pair[2]
		local p = MeshFix.clone(src)
		p:ClearAllChildren()
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = m.mat ~= "Neon"
		p.Size = Vector3.new(m.size[1], m.size[2], m.size[3]) * k
		p.CFrame = frame * CFrame.new(Vector3.new(m.offset[1], m.offset[2], m.offset[3]) * k) * MeshFix.of(p)
		p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[m.mat]
		end)
		p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
		p.Parent = b
	end
	PrologueMeshes.hide(b)
	for _, c in b:GetChildren() do
		if c:IsA("Part") then -- the old stripe bars
			PrologueMeshes.hide(c)
		end
	end
end

-- The pinning beam as the Blender girder (riveted, torn at one end), its length along the part's x
local function coverGirder(b: BasePart)
	if not PowerMeshes.ready("Girder") then
		return
	end
	local G = Config.PowerArt.Girder.GirderBeam
	local k = Vector3.new(b.Size.Y / G.size[1], b.Size.X / G.size[2], b.Size.Z / G.size[3])
	local anchor = b.CFrame
		* CFrame.Angles(0, 0, math.rad(90))
		* CFrame.new(-Vector3.new(G.offset[1], G.offset[2], G.offset[3]) * k)
	for _, pc in PowerMeshes.pieces("Girder", anchor, nil, k) do
		local m = PowerMeshes.make(pc, nil)
		if m then
			m.CastShadow = true
			weldOver(b, m)
		end
	end
	PrologueMeshes.hide(b)
end

local function feetOf(p: { number }?): Vector3?
	return if p then Vector3.new(p[1], p[2], p[3]) else nil
end

local function shoveHero(amount: number)
	CameraController.shake(0.3, amount)
	local r = root()
	if r then
		CombatFx.burst(r.Position - Vector3.new(0, 2, 0), "Comic")
	end
end

-- Skylance's spear from where he is to `at` (it never hurts)
local function throwSpear(o: { [string]: any }, at: Vector3)
	local from = o.fake and EnemyRenderer.position(o.fake)
	if from then
		CombatFx.bolt(from + Vector3.new(0, 3, 0), at, "Comic", Color3.fromRGB(110, 210, 255), "Blade")
	end
	CombatFx.burst(at, "Comic")
	AudioController.play("clash", at)
end

-- A chunk of the tunnel roof falling at `at` (a near miss, or where the hero just was)
local function chunk(at: Vector3)
	ensureFolder()
	local S = O.subway
	local c = part(
		Vector3.new(5, 3, 5),
		CFrame.new(at + Vector3.new(0, S.height - 4, 0)),
		Color3.fromRGB(110, 100, 92),
		Enum.Material.Slate
	)
	coverChunk(c, math.floor(math.abs(at.X + at.Z)) % 3 + 1)
	TweenService:Create(c, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(at + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0.3, 0.6, 0.2),
	}):Play()
	task.delay(0.3, function()
		CombatFx.burst(at + Vector3.new(0, 1, 0), "Comic")
		AudioController.play("collapse", at)
		CameraController.shake(0.3, 0.5)
	end)
	task.delay(4, function()
		c:Destroy()
	end)
end

function PrologueFx.moment(kind: string?, seg: { [string]: any }, phase: string)
	local o = StoryClient.opening
	local at = feetOf(seg.at)
	local r = root()
	if not kind or not at then
		return
	end
	ensureFolder()
	if kind == "runner" then
		if phase == "show" and not runner then
			-- a fleeing man barrels up the street at the hero
			local rig = person(
				"Citizen",
				{ gender = 1, build = 3, height = 3 },
				rgb(SHIRTS[3]),
				rgb(PANTS[1]),
				rgb(Config.Creator.skins[5]),
				rgb(PANTS[4])
			)
			local toward = if r
				then Vector3.new(r.Position.X - at.X, 0, r.Position.Z - at.Z)
				else Vector3.zero
			local n = npc(rig, at, 0)
			n.run = if toward.Magnitude > 0.1 then toward.Unit else Vector3.new(1, 0, 0)
			n.speed = 6 -- he slows as the prompt waits (the hero's moment), then charges past
			n.gone = os.clock() + 8
			table.insert(crowd, n)
			runner = n
		elseif phase == "hit" and runner then
			(runner :: Npc).speed = 22
		elseif phase == "miss" then
			shoveHero(0.45)
			if runner then
				(runner :: Npc).speed = 2 -- he stumbles back a step; the prompt comes again
			end
		end
	elseif kind == "barrier" then
		if phase == "show" and not props.barrier then
			-- a crowd barrier knocked flat across the street (yellow and black)
			local dir = feetOf(seg.to) and (feetOf(seg.to) :: Vector3) - (feetOf(seg.from) :: Vector3)
				or Vector3.new(0, 0, -1)
			local flat = Vector3.new(dir.X, 0, dir.Z)
			flat = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
			local cf = CFrame.lookAt(at + Vector3.new(0, 1.2, 0), at + Vector3.new(0, 1.2, 0) + flat)
			local b =
				part(Vector3.new(9, 2.4, 0.6), cf * CFrame.Angles(0.35, 0, 0), Color3.fromRGB(250, 200, 40))
			for i = -1, 1 do
				local stripe = part(
					Vector3.new(1.2, 2.5, 0.65),
					b.CFrame * CFrame.new(i * 3, 0, 0),
					Color3.fromRGB(30, 30, 34)
				)
				stripe.Parent = b
			end
			coverBarrier(b, at, flat)
			props.barrier = b
		elseif phase == "miss" then
			shoveHero(0.35)
		end
	elseif kind == "sign" or kind == "shove" then
		if phase == "miss" then
			if kind == "sign" and debris then
				-- the sign slips lower over the kid: hurry!
				local d = debris :: Part
				d.CFrame = d.CFrame - Vector3.new(0, 3, 0)
				CombatFx.burst(d.Position, "Comic")
				AudioController.play("clash", d.Position)
			end
			shoveHero(0.35)
		end
	elseif kind == "spear" then
		if phase == "show" and r then
			CombatFx.warn(r.Position - Vector3.new(0, 2.5, 0), 4, O.qte.window) -- the spear's mark under the hero
		elseif phase == "hit" then
			task.delay(0.15, throwSpear, o, at + Vector3.new(0, 0.5, 0)) -- it lands where the hero was
		elseif phase == "miss" and r then
			throwSpear(o, r.Position + Vector3.new(1.8, -2.5, 0)) -- a stride wide: it scares, never hurts
			shoveHero(0.45)
		end
	elseif kind == "ledge" then
		if phase == "miss" and r then
			-- the fingers slip: dust off the ledge, the hero catches lower
			FxLib.emit("spark", Color3.fromRGB(200, 190, 170), r.Position + Vector3.new(0, 2.5, 0), 6)
			shoveHero(0.4)
		end
	elseif kind == "slab" then
		if phase == "show" then
			CombatFx.warn(at, 3.5, O.qte.window)
		elseif phase == "hit" then
			chunk(at)
		elseif phase == "miss" and r then
			chunk(at + Vector3.new(0, 0, -5))
		end
	elseif kind == "pile" then
		if phase == "show" and not props.pile then
			local pile = part(
				Vector3.new(O.subway.width - 6, 3, 4),
				CFrame.new(at + Vector3.new(0, 1.5, 0)),
				Color3.fromRGB(110, 100, 92),
				Enum.Material.Slate
			)
			local art = PrologueMeshes.add(folder :: Folder, "Rubble", pile.CFrame, nil)
			if #art > 0 then
				PrologueMeshes.hide(pile)
			end
			props.pile = pile
		elseif phase == "miss" then
			shoveHero(0.35)
		end
	elseif kind == "beam" then
		if phase == "show" and not props.beam and r then
			-- a beam drops across the hero's shoulders: pinned
			local top = r.Position + Vector3.new(0, 2.2, 0)
			local b = part(
				Vector3.new(14, 1.6, 1.6),
				CFrame.new(top + Vector3.new(0, 14, 0)) * CFrame.Angles(0, 0, 0.2),
				Color3.fromRGB(120, 80, 50),
				Enum.Material.Wood
			)
			coverGirder(b)
			TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(top) * CFrame.Angles(0, 0, 0.2),
			}):Play()
			task.delay(0.26, function()
				CameraController.shake(0.35, 0.7)
				AudioController.play("collapse", top)
			end)
			props.beam = b
		elseif phase == "hit" and props.beam then
			-- thrown off: it tumbles away down the tunnel
			local b = props.beam
			props.beam = nil
			CombatFx.word(b.Position + Vector3.new(0, 2, 0), State.hero.setId, powerColor(), true)
			CombatFx.burst(b.Position, State.hero.fxStyle, powerColor())
			TweenService:Create(b, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
				CFrame = b.CFrame * CFrame.new(0, 9, 14) * CFrame.Angles(2.5, 0.4, 1.4),
				Transparency = 1,
			}):Play()
			for _, m in b:GetChildren() do
				if m:IsA("BasePart") then
					TweenService:Create(m, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Transparency = 1 })
						:Play()
				end
			end
			task.delay(0.65, function()
				b:Destroy()
			end)
		elseif phase == "miss" and props.beam then
			props.beam.CFrame = props.beam.CFrame - Vector3.new(0, 0.4, 0)
			shoveHero(0.5)
		end
	elseif kind == "suit" then
		if phase == "miss" then
			-- the Spark fizzles out for now: a puff, try again
			if r then
				FxLib.emit("wisp", powerColor(), r.Position, 4)
			end
		end
	end
end

-- The suit's HOLD prompt (prologue-cine): f (0 to 1) of the pieces are on; done: the rest snap on, then SUIT UP
function PrologueFx.suitHold(f: number, done: boolean)
	local s = suit
	if not s then
		return
	end
	local now = os.clock()
	if done then
		if #s.queue == 0 then
			-- every piece is on already (the hold built it all): the snap
			CombatFx.banner(
				if State.hero.fxStyle == "Anime" then "SUIT UP" else "SUIT UP!",
				powerColor(),
				State.hero.fxStyle
			)
			CameraController.punch(0.08)
			suit = nil
			return
		end
		s.next = math.min(s.next, now)
		s.until_ = math.min(s.until_, now + 0.2)
		s.gap = math.min(O.suit.pieceGap, 1.4 / math.max(1, #s.queue)) -- the rest in about the snap's time
		return
	end
	-- while held, pieces pop on in step with the fill
	local total = (s.shown or 0) + #s.queue
	local want = math.floor(f * total)
	while (s.shown or 0) < want and #s.queue > 0 do
		local p = table.remove(s.queue, 1) :: BasePart
		s.shown = (s.shown or 0) + 1
		if p.Parent then
			p.LocalTransparencyModifier = 0
			CombatFx.burst(p.Position, State.hero.fxStyle, powerColor())
			AudioController.play("skillRank", p.Position)
		end
	end
end

-- The big leap's slow motion (Fx.PrologueQte calls it as the JUMP lands its prompt)
function PrologueFx.slowLeap(time: number)
	slowLeap(StoryClient.opening, time)
end

local function tunnelStep(o: { [string]: any })
	local lane = o.lane
	local r = root()
	if not lane or not r then
		return
	end
	ensureFolder()
	local S = O.subway
	for k, slab in slabs do
		-- the way back is shut, but only behind the hero: never between the hero and the chamber
		local shut = slabDown[k] == true and OpeningPlan.rubbleShuts(Config, lane, k, r.Position.Z)
		if slab.CanCollide ~= shut then
			slab.CanCollide = shut
			slab.CanQuery = shut -- a ghost pile is no wall or floor to the movement rays either
		end
	end
	for k, c in lane.collapses do
		-- kid-proof: the tunnel caves in BEHIND the hero (OpeningPlan.slabFalls), every run the same
		if not slabs[k] and OpeningPlan.slabFalls(Config, lane, k, r.Position.Z) then
			local ceil = Vector3.new(lane.x, lane.floorY + S.height - S.slab / 4, c.z)
			local floor = Vector3.new(lane.x, lane.floorY, c.z)
			local slab = part(
				Vector3.new(S.width - 1, 3, S.slab),
				CFrame.new(ceil),
				Color3.fromRGB(110, 100, 92),
				Enum.Material.Slate
			)
			slabs[k] = slab
			-- the slab's look rides the falling part (welded); the part keeps its timing, size and collisions
			local art = PrologueMeshes.add(folder :: Folder, "Slab", slab.CFrame, slab)
			if #art > 0 then
				PrologueMeshes.hide(slab)
			end
			slabArt[k] = art
			TweenService:Create(slab, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(floor + Vector3.new(0, S.rubble / 2, 0)),
				Size = Vector3.new(S.width - 1, S.rubble, S.slab),
			}):Play()
			task.delay(0.24, function()
				if not slab.Parent then
					return
				end
				slabDown[k] = true -- CanCollide follows OpeningPlan.rubbleShuts each frame (above)
				-- the slab becomes the rubble pile's look where it landed (or the plain part again without one)
				local rubble = if folder
					then PrologueMeshes.add(folder :: Folder, "Rubble", slab.CFrame, nil)
					else {}
				for _, m in slabArt[k] or {} do
					m:Destroy()
				end
				slabArt[k] = rubble
				if #rubble > 0 then
					PrologueMeshes.hide(slab)
				else
					slab.Transparency = 0
				end
				CombatFx.burst(floor + Vector3.new(0, 2, 0), "Comic")
				AudioController.play("collapse", floor)
				CameraController.shake(0.35, 0.6)
			end)
		end
	end
end

local function rescueStep(t: number)
	local r = root()
	if not r then
		return
	end
	if not lodestar and t >= 0.6 then
		ensureFolder()
		local rig = hero("Lodestar", FakeRules.lookFrom(Config, O.lodestar.look, "Lodestar"))
		plate(rig.model, O.lodestar.name, O.lodestar.title, Color3.fromRGB(150, 190, 255))
		local fwd = r.CFrame.LookVector * Vector3.new(1, 0, 1)
		fwd = if fwd.Magnitude > 0.1 then fwd.Unit else Vector3.new(0, 0, -1)
		local land = r.Position + fwd * 9 - Vector3.new(0, 2.6, 0)
		local n = npc(rig, land + Vector3.new(0, 90, 0), yawTo(land, r.Position))
		lodestar = n
		local t0 = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			local u = math.clamp((os.clock() - t0) / 0.45, 0, 1)
			n.pos = (land + Vector3.new(0, 90, 0)):Lerp(land, u * u)
			NpcRig.place(n.rig, CFrame.new(n.pos) * CFrame.Angles(0, n.yaw, 0))
			if u >= 1 and conn then
				conn:Disconnect()
				-- the landing: a shockwave, a crater ring, a big word and a shake
				CombatFx.slam(land, 26)
				CombatFx.burst(land + Vector3.new(0, 2, 0), "Comic", Color3.fromRGB(150, 190, 255))
				CombatFx.word(land + Vector3.new(0, 6, 0), "Titan", Color3.fromRGB(150, 190, 255), true)
				AudioController.play("super", land)
				CameraController.shake(0.6, 1.4)
				NpcRig.turn(n.rig, "RightShoulder", CFrame.Angles(0.4, 0, 0))
				NpcRig.turn(n.rig, "LeftHip", CFrame.Angles(0.5, 0, 0))
			end
		end)
	end
	local n = lodestar
	if n and t >= O.beats.rescue - 2 then
		-- he grabs the hero: steps in, arm out
		local d = (r.Position - Vector3.new(0, 2.6, 0)) - n.pos
		if d.Magnitude > 3 then
			n.pos += d.Unit * math.min(d.Magnitude - 3, 0.5)
			NpcRig.place(n.rig, CFrame.new(n.pos) * CFrame.Angles(0, n.yaw, 0))
		end
		NpcRig.turn(n.rig, "RightShoulder", CFrame.Angles(1.6, 0, 0))
	end
end

local function buildBoard(o: { [string]: any })
	local bb = o.billboard
	if board or not bb then
		return
	end
	ensureFolder()
	local B = O.billboard
	local at = Vector3.new(bb[1], bb[2], bb[3])
	local n = Vector3.new(bb[4], 0, bb[5])
	local p =
		part(Vector3.new(B.size[1], B.size[2], 1), CFrame.lookAt(at, at + n), Color3.fromRGB(240, 240, 240))
	board = p
	plainParts.board = p
	-- the printed Crane Industries ad (art/prologue/ads.py); without its upload, the brand and slogan as text on
	-- the right two thirds, the same layout (the left third is Crane's)
	if not picture(p, Enum.NormalId.Front, O.art.billboard) then
		local g = Instance.new("SurfaceGui")
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 12
		g.LightInfluence = 0
		g.Parent = p
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(26, 30, 56)
		bg.BorderSizePixel = 0
		bg.Parent = g
		local function text(t: string, y: number, h: number, color: Color3)
			local l = Instance.new("TextLabel")
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.fromScale(0.7, y)
			l.Size = UDim2.fromScale(0.56, h)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBlack
			l.TextScaled = true
			l.TextWrapped = true
			l.Text = t
			l.TextColor3 = color
			l.Parent = bg
		end
		text(O.brand, 0.3, 0.22, Color3.fromRGB(255, 210, 60))
		text(O.slogan, 0.65, 0.34, Color3.fromRGB(245, 245, 245))
	end
	local cf = p.CFrame
	local frame = dress("Billboard", cf)
	-- Silas Crane himself on the catwalk in front of the ad's left third, turned three quarters toward its words
	-- and presenting them: his own rig at billboard size, his catalog face and catalog hair (nate's rule: faces and
	-- hair come from the Roblox catalog, never drawn), so the picture holds no person
	local C = PrologueArtKit.CRANE
	local feet = cf * CFrame.new(C.at[1], C.at[2], C.at[3])
	if #frame == 0 then
		-- no frame imported: a plain ledge to stand on (PLACEHOLDER ART until Art.Prologue)
		part(
			Vector3.new(16, 0.4, 5.6),
			feet * CFrame.new(0, -0.2, 0),
			Color3.fromRGB(78, 84, 98),
			Enum.Material.DiamondPlate
		)
	end
	local crane = craneRig(C.scale)
	NpcRig.place(crane, feet * CFrame.Angles(0, math.rad(C.yaw), 0))
	NpcRig.turn(crane, "RightShoulder", CFrame.Angles(1.75, 0, 0.35))
	NpcRig.turn(crane, "LeftShoulder", CFrame.Angles(0.15, 0, 0))
end

-- (lore step 6: each line's blip is the guide line queue's, Ui.GuideHud, with the speaker's own sound)

---------------------------------------------------------------------------
-- Each beat and each frame
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- The quiet world (kid-proof, nate's playtest 2026-11-18): while the prologue runs this device draws only the
-- story: no other heroes (bodies, plates, casts), no city robots or their shots, no city citizens. The server
-- keeps the same rule for hits (EnemySim's solo rule), so nothing unseen can touch the hero.
---------------------------------------------------------------------------

local quiet = false
local mine: { [number]: boolean } = {}
local veiled: { [Instance]: number } = {} -- parts and decals made invisible here, with their old modifier
local nextVeil = 0

local function veilOthers(on: boolean)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local plate = pg and pg:FindFirstChild("Plate_" .. p.UserId)
			if plate and plate:IsA("BillboardGui") then
				plate.Enabled = not on
			end
			local char = p.Character
			if on and char then
				for _, d in char:GetDescendants() do
					if (d:IsA("BasePart") or d:IsA("Decal")) and not veiled[d] then
						veiled[d] = d.LocalTransparencyModifier
						d.LocalTransparencyModifier = 1
					end
				end
			end
		end
	end
	if not on then
		for d, was in veiled do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = was
			end
		end
		table.clear(veiled)
	end
end

local function setQuiet(on: boolean)
	table.clear(mine)
	for _, id in (if on then StoryClient.opening.mine else nil) or {} do
		mine[id] = true
	end
	if on == quiet then
		return
	end
	quiet = on
	CitizenRenderer.hidden = on
	EnemyRenderer.only = if on
		then function(id: number): boolean
			return mine[id] == true
		end
		else nil
	CombatClient.hideEnemy = if on
		then function(id: number): boolean
			return not mine[id]
		end
		else nil
	CombatClient.hideCaster = if on
		then function(_: number): boolean
			return true
		end
		else nil
	veilOthers(on)
end

-- The Ceremony's held sounds on this device (alive-world 2026-11-20): the crowd's applause loop and the scanner's hum
local gasped = false
local function crowdSound(cheer: boolean, hum: boolean)
	AudioController.loop("crowdCheer", cheer)
	AudioController.loop("scanHum", hum)
end

local function onState()
	setQuiet(StoryClient.openingStep() ~= nil)
	local o = StoryClient.opening
	local step = StoryClient.openingStep()
	if not step then
		endPick()
		crowdSound(false, false)
		gasped = false
		CinemaClient.stop("prologue")
		if slowmo then
			slowmo:Destroy()
			slowmo = nil
		end
		clearScene()
		lastStep = nil
		return
	end
	if step ~= lastStep then
		if OpeningPlan.CODE[step] <= OpeningPlan.CODE.spark and #crowd == 0 and not stageNpcs.crane then
			buildCeremony(o)
		end
		if step == "spark" and kid and o.side ~= "villain" and not debris then
			-- the sign shaking loose over the kid
			local d = part(
				Vector3.new(8, 3, 1),
				CFrame.new((kid :: Npc).pos + Vector3.new(0, 24, 0)),
				Color3.fromRGB(230, 120, 60),
				Enum.Material.SmoothPlastic
			)
			debris = d
			plainParts.sign = d
			dress("FallingSign", d.CFrame, d) -- welded: the meshes shake, fall and bounce with it
		end
		if step == "leap" then
			-- the plaza is behind us now
			for _, n in crowd do
				n.rig.model:Destroy()
			end
			table.clear(crowd)
			for _, n in stageNpcs do
				n.rig.model:Destroy()
			end
			table.clear(stageNpcs)
			if kid then
				(kid :: Npc).rig.model:Destroy()
				kid = nil
			end
			spearAt = os.clock() + 2.5
		end
		if step == "run" then
			local start = v3(o.start)
			if start then
				flee(start)
			end
			for name, n in stageNpcs do
				if name ~= "crane" then
					CombatFx.burst(n.pos + Vector3.new(0, 3, 0), "Comic")
					fade(n, 0.4)
					stageNpcs[name] = nil
				end
			end
		end
		if step == "suit" then
			-- prologue-cine: the suit's pieces stay hidden until the HOLD prompt builds them (PrologueFx.suitHold)
			suit = { hidden = {}, queue = {}, next = math.huge, until_ = math.huge }
		end
		if step == "title" then
			buildBoard(o)
		end
		if OpeningPlan.CUT[step] then
			playBeat(step, o)
		else
			CinemaClient.stop("prologue")
		end
		lastStep = step
	end
	if step == "spark" and o.fired then
		fireSpark(o)
	end
	-- act1-choices: the Ceremony's choice card holds the moment
	if step == "spark" and o.choosing then
		playPick(o)
	else
		endPick()
	end
end

local function frame(dt: number)
	local step = StoryClient.openingStep()
	if not step then
		return
	end
	if quiet and os.clock() >= nextVeil then
		nextVeil = os.clock() + 0.5 -- heroes who join or respawn mid-prologue are veiled too
		veilOthers(true)
	end
	local o = StoryClient.opening
	local t = StoryClient.beatTime()
	local now = os.clock()
	-- (alive-world 2026-11-20) the crowd is heard: applause and whistles while it cheers, one gasp as the scan
	-- locks on the hero, the scanner drone's hum while it hovers over the stage (the Ambient atlas)
	local gasping = step == "scan" and t > O.beats.scan * 0.45
	crowdSound(
		(step == "ceremony" or step == "scan") and not gasping and #crowd > 0,
		scanner ~= nil and (step == "ceremony" or step == "scan")
	)
	if gasping and not gasped then
		gasped = true
		AudioController.play("crowdGasp")
	elseif step ~= "scan" then
		gasped = false
	end
	if step == "ceremony" then
		for _, n in crowd do
			poseClip(n, cheerOf(n), now)
		end
		for name, n in stageNpcs do
			poseClip(n, if name == "crane" then NpcAnim.crowd.crane else NpcAnim.crowd.stage, now)
		end
	elseif step == "scan" then
		sweep(o, t)
		-- (first-30) the crowd keeps cheering under the sweep, then gasps toward the hero it stops on
		local gasp = t > O.beats.scan * 0.45
		local start = if gasp then v3(o.start) else nil
		for _, n in crowd do
			if start and not n.run then
				n.yaw = yawTo(n.pos, start)
				NpcRig.place(n.rig, CFrame.new(n.pos) * CFrame.Angles(0, n.yaw, 0))
			end
			if not n.run then
				poseClip(n, if gasp then NpcAnim.crowd.scan else cheerOf(n), now)
			end
		end
	elseif scan then
		endScan()
	end
	-- the panic: the crowd runs off and fades away
	-- (act1-choices) the panic holds still while the Ceremony's choice card is up
	for i = #crowd, 1, -1 do
		if frozeAt then
			break
		end
		local n = crowd[i]
		moveNpc(n, dt, now)
		if n.gone and now >= n.gone then
			fade(n, 0.6)
			table.remove(crowd, i)
		end
	end
	local k = if frozeAt then nil else kid
	if k then
		moveNpc(k, dt, now)
		if k.gone and now >= k.gone then
			fade(k, 0.6)
			kid = nil
		end
	end
	if debris and step == "spark" and not sparkShown then
		local d = debris :: Part
		d.CFrame = CFrame.new(d.Position) * CFrame.Angles(0, 0, math.sin(now * 18) * 0.06)
	end
	if scanner then
		local s = scanner :: Part
		s.CFrame = CFrame.new(s.Position) * CFrame.new(0, math.sin(now * 2) * 0.03, 0)
	end
	if step == "chase" or step == "suit" or step == "descend" or step == "leap" then
		spears(o, now)
	end
	suitStep(now)
	if step == "tunnel" then
		tunnelStep(o)
	end
	if step == "rescue" then
		rescueStep(t)
	end
end

-- Lodestar's figure for a mission's camera beat (StoryFx, lore step 5): his fixed look and name plate, on
-- this device only. Returns the rig (NpcRig.place it, destroy rig.model when done).
function PrologueFx.lodestarRig(parent: Instance): any
	local rig = hero("Lodestar", FakeRules.lookFrom(Config, O.lodestar.look, "Lodestar"))
	plate(rig.model, O.lodestar.name, O.lodestar.title, Color3.fromRGB(150, 190, 255))
	rig.model.Parent = parent
	return rig
end

-- The cast on their own for another scene (the intro film, Fx.IntroFilm, list-combat 2026-11-20), parented to
-- `parent`: "crane" (Silas Crane and his plate), a fake's kind ("Radiant", "Bulwark", "Skylance": its hero look and
-- its hero plate), "citizen" (crowd clothes by i), or `look` (a creator look definition, FakeRules.lookFrom) as
-- `kind`. Returns the rig (NpcRig.place it, destroy rig.model when done).
function PrologueFx.cast(kind: string, parent: Instance, i: number?, look: any?): any
	local rig
	if kind == "crane" then
		rig = craneRig(1)
		plate(rig.model, "SILAS CRANE", O.brand, Color3.fromRGB(255, 210, 60))
	elseif kind == "kid" or kind == "shover" then
		rig = kidRig(kind == "shover")
	elseif kind == "citizen" then
		local k = i or 1
		rig = person(
			"Citizen",
			{ gender = 1 + k % 2, build = 1 + k % 3, height = 2 + k % 3 },
			rgb(SHIRTS[k % #SHIRTS + 1]),
			rgb(PANTS[k % #PANTS + 1]),
			rgb(Config.Creator.skins[k % 8 + 1]),
			rgb(PANTS[(k + 1) % #PANTS + 1])
		)
		CitizenRenderer.dressRig(rig, O.plaza.crowd.seed + k, rgb(Config.Creator.skins[k % 8 + 1]))
	elseif look then
		rig = hero(kind, FakeRules.lookFrom(Config, look, kind))
	else
		rig = hero(kind, FakeRules.look(Config, kind))
		local pl = FakeRules.plate(Config, kind, false, nil)
		plate(rig.model, pl.name, pl.sub, Color3.fromRGB(255, 220, 120))
	end
	rig.model.Parent = parent
	return rig
end

function PrologueFx.init()
	StoryClient.Changed:Connect(function(what)
		if what == "opening" then
			onState()
		end
	end)
	-- the guided hops (kid-proof): on the leap, the chase and the descend, a Leap from the ground is a set arc to
	-- the beat's target (the next roof, or the subway steps from the last roof); the server granted the travel
	MoveController.hopAssist = function(): (Vector3?, number, number)
		local step = StoryClient.openingStep()
		local o = StoryClient.opening
		local r = root()
		local to = o.target
		if not to or not r or not OpeningPlan.hopsAt(Config, step, r.Position.Y) then
			return nil, 0, 0
		end
		local p = r.Position
		local time, height = OpeningPlan.hopArc(Config, { p.X, p.Y, p.Z }, to)
		return Vector3.new(to[1], to[2] + 3, to[3]), time, height
	end
	RunService.RenderStepped:Connect(FrameProf.wrap("PrologueFx", frame))
end

return PrologueFx
