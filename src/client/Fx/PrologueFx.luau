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
-- PLACEHOLDER ART: the stage, the crowd, Crane, the billboard and the slabs are parts until the art pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
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

local PrologueFx = {}

local O = Config.Story.opening
local player = Players.LocalPlayer
local FAKES = { "Radiant", "Bulwark", "Skylance" }
local FACE = "rbxasset://textures/face.png"

type Npc = { rig: any, pos: Vector3, yaw: number, run: Vector3?, speed: number, phase: number, gone: number? }

local folder: Folder? = nil
local crowd: { Npc } = {}
local stageNpcs: { [string]: Npc } = {}
local kid: Npc? = nil
local lodestar: Npc? = nil
local scanBeam: Part? = nil
local scanner: Part? = nil
local debris: Part? = nil
local board: Part? = nil
local slabs: { [number]: Part } = {}
local lastStep: string? = nil
local leapDone = false
local sparkShown = false
local spearAt = 0
local suit: { hidden: { [BasePart]: boolean }, queue: { BasePart }, next: number, until_: number }? = nil
local slowmo: ColorCorrectionEffect? = nil

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
	kid, lodestar, scanBeam, scanner, debris, board = nil, nil, nil, nil, nil, nil
	sparkShown, leapDone, suit = false, false, nil
end

local function ensureFolder()
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Prologue"
		f.Parent = Workspace
		folder = f
	end
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
	-- the stage: a deck, a gold trim, steps down to the crowd, a podium and the Hall's banner behind
	part(
		Vector3.new(P.width, P.height, P.depth),
		base,
		Color3.fromRGB(70, 74, 92),
		Enum.Material.Concrete,
		true
	)
	part(
		Vector3.new(P.width + 0.6, 0.6, P.depth + 0.6),
		base * CFrame.new(0, P.height / 2, 0),
		Color3.fromRGB(255, 210, 60),
		Enum.Material.Metal
	)
	part(
		Vector3.new(10, P.height / 2, 4),
		base * CFrame.new(0, -P.height / 4, -P.depth / 2 - 2),
		Color3.fromRGB(70, 74, 92),
		Enum.Material.Concrete,
		true
	)
	part(
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
	sign(banner, Enum.NormalId.Front, {
		{ O.hall, Color3.fromRGB(255, 210, 60), 0.5 },
		{ O.brand, Color3.fromRGB(240, 240, 240), 0.3 },
	}, Color3.fromRGB(30, 34, 60))
	-- Silas Crane: a sharp dark suit, a red tie, slicked silver hair
	local crane = person(
		"Silas Crane",
		{ gender = 1, build = 2, height = 4 },
		Color3.fromRGB(34, 36, 44),
		Color3.fromRGB(34, 36, 44),
		rgb(Config.Creator.skins[2]),
		Color3.fromRGB(190, 195, 205)
	)
	NpcRig.fix(
		crane,
		"UpperTorso",
		part(Vector3.new(0.5, 1.4, 0.2), CFrame.identity, Color3.fromRGB(200, 30, 40)),
		CFrame.new(0, 0.1, -crane.parts.UpperTorso.Size.Z / 2 - 0.05)
	)
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
		part(
			Vector3.new(0.4, 7, 7),
			CFrame.new(sc) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(255, 60, 60),
			Enum.Material.Neon
		).Shape =
			Enum.PartType.Cylinder
		scanner = d
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
			table.insert(crowd, npc(rig, at, yawTo(at, stage) + (math.random() - 0.5) * 0.3))
		end
	end
	-- the kid (Vigil) or the man who shoves (Syndicate), by the spark point
	local k = v3(o.kid)
	if k then
		local villain = o.side == "villain"
		local rig = person(
			if villain then "Shover" else "Kid",
			{ gender = 1, build = if villain then 3 else 1, height = 3 },
			if villain then Color3.fromRGB(150, 60, 60) else Color3.fromRGB(255, 200, 60),
			Color3.fromRGB(50, 60, 90),
			rgb(Config.Creator.skins[3]),
			Color3.fromRGB(60, 40, 30),
			if villain then 1 else 0.68
		)
		kid = npc(rig, k, yawTo(k, start))
	end
end

---------------------------------------------------------------------------
-- Poses and the crowd's panic
---------------------------------------------------------------------------

local function poseWalk(n: Npc, speed: number, t: number)
	local swing = math.sin(t * (6 + speed * 0.3) + n.phase) * math.clamp(speed / 14, 0, 1) * 0.8
	for _, s in { { "Left", 1 }, { "Right", -1 } } do
		NpcRig.turn(n.rig, s[1] .. "Hip", CFrame.Angles(swing * s[2], 0, 0))
		NpcRig.turn(
			n.rig,
			s[1] .. "Shoulder",
			CFrame.Angles(-swing * s[2] * 0.9 + (if speed > 8 then 0.6 else 0), 0, 0)
		)
	end
end

local function poseCheer(n: Npc, t: number)
	local up = 2.6 + math.sin(t * 5 + n.phase) * 0.35
	NpcRig.turn(n.rig, "LeftShoulder", CFrame.Angles(up, 0, 0))
	NpcRig.turn(n.rig, "RightShoulder", CFrame.Angles(up * 0.9, 0, 0))
end

local function poseWave(n: Npc, t: number)
	NpcRig.turn(n.rig, "RightShoulder", CFrame.Angles(2.8, 0, math.sin(t * 3 + n.phase) * 0.3))
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

---------------------------------------------------------------------------
-- The beats' moments
---------------------------------------------------------------------------

local function sweep(o: { [string]: any }, t: number)
	local start, face = v3(o.start), v3(o.face)
	if not start or not face then
		return
	end
	local side = Vector3.new(-face.Z, 0, face.X)
	if not scanBeam then
		local b =
			part(Vector3.new(0.6, 12, 40), CFrame.new(start), Color3.fromRGB(255, 50, 50), Enum.Material.Neon)
		b.Transparency = 0.45
		scanBeam = b
		AudioController.play("bossWarning")
	end
	local b = scanBeam :: Part
	local lock = O.beats.scan * 0.42
	local x = if t < lock then math.sin(t / lock * math.pi * 1.5) * 26 * (1 - t / lock) + 0 else 0
	b.CFrame =
		CFrame.lookAt(start + side * x + Vector3.new(0, 4, 0), start + side * x + Vector3.new(0, 4, 0) + face)
	if t >= lock then
		b.Size = Vector3.new(0.6, 9, 9)
		b.Color = Color3.fromRGB(255, 20, 20)
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
		-- the sign comes down; the Spark throws a shield over the kid; it bounces off
		local shield = part(
			Vector3.new(9, 9, 9),
			CFrame.new(k.pos + Vector3.new(0, 2, 0)),
			color,
			Enum.Material.ForceField
		)
		shield.Shape = Enum.PartType.Ball
		shield.Transparency = 0.2
		if r then
			CombatFx.bolt(r.Position, k.pos + Vector3.new(0, 2, 0), style, color, State.hero.setId)
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
				TweenService:Create(d, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {
					CFrame = CFrame.new(hit + Vector3.new(12, -5, 6)) * CFrame.Angles(0.6, 0.2, 1.2),
				}):Play()
			end)
		end
		task.delay(2.2, function()
			if shield.Parent then
				TweenService:Create(shield, TweenInfo.new(0.5), { Transparency = 1 }):Play()
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

-- The rooftop leap: one Leap becomes a slow, high arc to the next roof with the path's own power look
local function slowLeap(o: { [string]: any })
	if leapDone then
		return
	end
	local goal = v3(o.roofs and o.roofs[2])
	local r = root()
	if not goal or not r then
		return
	end
	leapDone = true
	local time = 1.9
	MoveController.arcTo(goal + Vector3.new(0, 3, 0), time, 26)
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
		s.next = now + O.suit.pieceGap
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

local function tunnelStep(o: { [string]: any }, t: number)
	local lane = o.lane
	if not lane then
		return
	end
	ensureFolder()
	local S = O.subway
	for k, c in lane.collapses do
		local ceil = Vector3.new(lane.x, lane.floorY + S.height - S.slab / 4, c.z)
		local floor = Vector3.new(lane.x, lane.floorY, c.z)
		if not slabs[k] and t >= c.t - S.warn then
			local slab = part(
				Vector3.new(S.width - 1, 3, S.slab),
				CFrame.new(ceil),
				Color3.fromRGB(110, 100, 92),
				Enum.Material.Slate
			)
			slabs[k] = slab
			CombatFx.warn(floor, S.width / 2, math.max(0.1, c.t - t))
			-- the ceiling cracks: a little dust, then it drops
			task.delay(math.max(0, c.t - t), function()
				if not slab.Parent then
					return
				end
				TweenService
					:Create(slab, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						CFrame = CFrame.new(floor + Vector3.new(0, S.rubble / 2, 0)),
						Size = Vector3.new(S.width - 1, S.rubble, S.slab),
					})
					:Play()
				task.delay(0.24, function()
					slab.CanCollide = true -- solid on this device: Leap over the pile
					slab.CanQuery = true
					CombatFx.burst(floor + Vector3.new(0, 2, 0), "Comic")
					AudioController.play("collapse", floor)
					CameraController.shake(0.35, 0.6)
				end)
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
	-- Silas Crane's smiling face (PLACEHOLDER ART: drawn with shapes)
	local function blob(
		parent: Instance,
		color: Color3,
		x: number,
		y: number,
		w: number,
		h: number,
		round: number?
	): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Parent = parent
		if round then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(round, 0)
			c.Parent = f
		end
		return f
	end
	local face = blob(bg, rgb(Config.Creator.skins[2]), 0.25, 0.55, 0.32, 0.8, 0.5)
	blob(bg, Color3.fromRGB(190, 195, 205), 0.25, 0.2, 0.34, 0.2, 0.5) -- slicked silver hair
	blob(face, Color3.fromRGB(30, 30, 40), 0.32, 0.38, 0.12, 0.08, 0.5)
	blob(face, Color3.fromRGB(30, 30, 40), 0.68, 0.38, 0.12, 0.08, 0.5)
	local smile = blob(face, Color3.fromRGB(250, 250, 250), 0.5, 0.68, 0.5, 0.14, 0.5)
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(120, 40, 50)
	st.Thickness = 3
	st.Parent = smile
	blob(bg, Color3.fromRGB(200, 30, 40), 0.25, 0.97, 0.06, 0.1) -- the red tie
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

-- (lore step 6: each line's blip is the guide line queue's, Ui.GuideHud, with the speaker's own sound)

---------------------------------------------------------------------------
-- Each beat and each frame
---------------------------------------------------------------------------

local function onState()
	local o = StoryClient.opening
	local step = StoryClient.openingStep()
	if not step then
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
			debris = part(
				Vector3.new(8, 3, 1),
				CFrame.new((kid :: Npc).pos + Vector3.new(0, 24, 0)),
				Color3.fromRGB(230, 120, 60),
				Enum.Material.SmoothPlastic
			)
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
			suit = { hidden = {}, queue = {}, next = os.clock() + 0.3, until_ = os.clock() + 1.6 }
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
end

local function frame(dt: number)
	local step = StoryClient.openingStep()
	if not step then
		return
	end
	local o = StoryClient.opening
	local t = StoryClient.beatTime()
	local now = os.clock()
	if step == "ceremony" then
		for _, n in crowd do
			poseCheer(n, now)
		end
		for name, n in stageNpcs do
			if name == "crane" then
				NpcRig.turn(n.rig, "RightShoulder", CFrame.Angles(0.9 + math.sin(now * 2) * 0.4, 0, 0))
			else
				poseWave(n, now)
			end
		end
	elseif step == "scan" then
		sweep(o, t)
		if t > O.beats.scan * 0.45 then
			local start = v3(o.start)
			for _, n in crowd do
				if start then
					n.yaw = yawTo(n.pos, start)
					NpcRig.place(n.rig, CFrame.new(n.pos) * CFrame.Angles(0, n.yaw, 0))
				end
				NpcRig.turn(n.rig, "LeftShoulder", CFrame.Angles(0.3, 0, 0))
				NpcRig.turn(n.rig, "RightShoulder", CFrame.Angles(0.3, 0, 0))
			end
		end
	elseif scanBeam then
		scanBeam:Destroy()
		scanBeam = nil
	end
	-- the panic: the crowd runs off and fades away
	for i = #crowd, 1, -1 do
		local n = crowd[i]
		moveNpc(n, dt, now)
		if n.gone and now >= n.gone then
			fade(n, 0.6)
			table.remove(crowd, i)
		end
	end
	local k = kid
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
		tunnelStep(o, t)
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

function PrologueFx.init()
	StoryClient.Changed:Connect(function(what)
		if what == "opening" then
			onState()
		end
	end)
	MoveController.Leaped:Connect(function()
		if StoryClient.openingStep() == "leap" then
			slowLeap(StoryClient.opening)
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("PrologueFx", frame))
end

return PrologueFx
