-- HqClient: your base (spec: Hero HQ "a personal solo instance ... stations"; The Safehouse under the plaza for
-- heroes, nate's lore plan Q2, and The Foundry for villains). The server holds you in an invisible cell high above
-- the city and runs the dummies and the boss sim; this device draws the rooms from HqState:
-- * The Safehouse is drawn as the hideout (Shared.HqRules.hideout: concrete, pipes, lamps, monitors, the city
--   map wall, the stair down from the plaza); its service door in the city gets its name and a marker on Vigil
--   devices only.
-- * The floor trim, walls and lights in your side's colours, and one pad per station with a sign and a
--   B-key prompt (E is Skill 2): Command Table, Gizmo's Bench, Mannequins, Training Room, Trophy Wall,
--   Hall of Legends and the Exit.
-- * Training dummies (aim assist through CombatClient.addTargetSource), the boss sim's robot and its slam
--   rings (HqDps), statues of retired heroes in their own looks, the trophy plaques and the city's
--   thank-you props.
-- * Lore step 12: the dressing your own side's reputation tier has opened (Shared.RepTiers.dressing).
-- * WP9 (gap G5, spec H5): the WANTED poster of your current nemesis (its bust in a ViewportFrame, name, rank,
--   Intel and a stamp) and a mounted head per nemesis rank beaten, on the east wall by the Trophy Wall
--   (Shared.WantedRules); the poster's B prompt opens the WANTED panel (HqHud passes it to NemesisHud).
-- * WP12 (gap G15, spec Update 2): a friend's HQ as a visitor (HqState with `visit`): the same rooms, trophy
--   wall, statues, props, dressing, WANTED poster and heads from the owner's save, read-only: the pads and signs
--   draw but only the exit works (LEAVE HQ), the poster has no prompt, the dummies are decor. Also the visit
--   asks (HqVisitAsked: SquadHud's card), the owner's visitors (HqVisitors: SquadHud's rows) and this device's
--   Roblox block list for the server (GuardBlocks: a block stops visit asks).
-- HqHud draws the station panels.
-- The HQ art pass (2026-11-18): once nate imports art/blender/hq.py's meshes as ReplicatedStorage.Art.Hq, each
-- piece below is drawn in its meshes over today's part, which is hidden but kept (its prompt, sign and
-- SurfaceGuis work as before): the station consoles and pads, the Trophy Wall's frame, plaques and trophies, the
-- WANTED board, head mounts, name plates and the nemesis pieces, the training dummies (base, target, visor and
-- their own padded R15 body), the statues' plinths, every prop and the reputation dressing (Shared.HqArtKit,
-- Fx.HqMeshes). A look shows only once all of its meshes are there. PLACEHOLDER ART until that import, and
-- still for the room shells (the Foundry's box walls, the Safehouse's concrete), the title sign and the marble
-- copies of the hero on the statues.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))
local LookKit = require(Shared:WaitForChild("LookKit"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))
local HqRules = require(Shared:WaitForChild("HqRules"))
local RepTiers = require(Shared:WaitForChild("RepTiers")) -- lore step 12: the hideout's tiered dressing
local WantedRules = require(Shared:WaitForChild("WantedRules")) -- WP9: the WANTED poster and nemesis heads
local VisitRules = require(Shared:WaitForChild("VisitRules")) -- WP12: visits to a friend's HQ
local HqArtKit = require(Shared:WaitForChild("HqArtKit")) -- the HQ art pass: where the meshes go
local HideoutKit = require(Shared:WaitForChild("HideoutKit")) -- the hideout art pass: the room shells' modules
local LoreBookKit = require(Shared:WaitForChild("LoreBookKit")) -- side-content: the Lore Shelf (prop 23)
local State = require(script.Parent.Parent.State)

local CombatClient = require(script.Parent.CombatClient)
local Preview = require(script.Parent.Parent.Ui.Preview)
local HqMeshes = require(script.Parent.Parent.Fx.HqMeshes)
local LoreBooks = require(script.Parent.Parent.Fx.LoreBooks)
local QualityController = require(script.Parent.QualityController)

local HqClient = {}

HqClient.Changed = Signal.new() -- (state) on entering, leaving and every HqState
HqClient.Station = Signal.new() -- (name) a station prompt was used
HqClient.Dps = Signal.new() -- (packet) the training room meter, 2 Hz
HqClient.VisitAsked = Signal.new() -- (ask) WP12: { from, name, life }: someone asks to visit your HQ
HqClient.VisitorsChanged = Signal.new() -- () WP12: who is visiting your HQ, or your own visit, changed
HqClient.visitors = {} :: { { userId: number, name: string } } -- WP12: visitors in your HQ now

local H = Config.Hq
local VT = H.visit.text
local GOLD = Color3.fromRGB(255, 200, 60)
local function paletteColor(key: string): Color3
	local rgb = Config.City.palette[key] or { 255, 0, 255 }
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end
local function rgb3(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local SIDE_COLORS = {
	hero = { main = rgb3(HqArtKit.COLORS.hero.main), trim = rgb3(HqArtKit.COLORS.hero.trim) },
	villain = { main = rgb3(HqArtKit.COLORS.villain.main), trim = rgb3(HqArtKit.COLORS.villain.trim) },
}
-- (Color3 -> { r, g, b } for a mesh's tint)
local function tint(c: Color3): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local STATION_NAMES = {
	command = "Command Table",
	gizmo = "Gizmo's Bench",
	mannequins = "Mannequins",
	training = "Training Room",
	trophies = "Trophy Wall",
	legends = "Hall of Legends",
	scanner = "HQ Scanner",
	exit = "Exit",
}
local STATION_ACTIONS = {
	command = "Contracts and heroes",
	gizmo = "Styles and upgrades",
	mannequins = "Saved looks",
	training = "Test your damage",
	trophies = "Pick trophies",
	legends = "Legacy",
	scanner = "Find collections",
	exit = "Back to the city",
}

local state: { [string]: any } = { on = false }
local folder: Folder? = nil
local dummies: { { id: number, pos: Vector3 } } = {}

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function sign(parent: BasePart, text: string, sub: string?, height: number?)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, if sub then 60 else 40)
	bb.StudsOffset = Vector3.new(0, height or 5, 0)
	bb.MaxDistance = 90
	bb.AlwaysOnTop = false
	bb.Parent = parent
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 40)
	l.Font = Enum.Font.Bangers
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	l.Text = text
	l.Parent = bb
	if sub then
		local s = l:Clone()
		s.Size = UDim2.new(1, 0, 0, 20)
		s.Position = UDim2.fromOffset(0, 40)
		s.Font = Enum.Font.GothamBold
		s.Text = sub
		s.Parent = bb
	end
end

local function centre(): Vector3
	local c = state.cell or { 0, 0, 0 }
	return Vector3.new(c[1], c[2], c[3])
end

local function stationAt(name: string, up: number?): Vector3
	local s = H.stations[name]
	return centre() + Vector3.new(s[1], up or 0, s[2])
end

local function clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	dummies = {}
end

local function titleSign(f: Folder, colors: { main: Color3, trim: Color3 })
	local c = centre()
	local size = H.cell.size
	local title =
		part(f, Vector3.new(1, 1, 1), CFrame.new(c + Vector3.new(0, 24, -size / 2 + 5)), colors.main)
	title.Transparency = 1
	local sub = "HQ level " .. (state.level or 1)
	if state.visit then -- WP12: whose HQ this is
		sub = string.format(VT.titleSub, state.visit.name or "") .. ", level " .. (state.level or 1)
	end
	sign(title, string.upper(state.name or ""), sub, 0)
end

-- The hideout art pass (2026-11-19): a room shell's modules (Shared.HideoutKit placements and the part index each
-- hides) drawn once Art.Hideout holds their meshes; each part a drawn module stands in for is hidden, not removed
local function shellOver(
	f: Folder,
	places: { HideoutKit.Place },
	hides: { [number]: number },
	parts: { [number]: BasePart }
)
	local drawn: { [number]: boolean } = {}
	local c = centre()
	for k, pl in places do
		drawn[k] = HqMeshes.put(f, pl, c)
	end
	for i, k in hides do
		local p = parts[i]
		if p and drawn[k] then
			HqMeshes.hide(p)
		end
	end
end

local function buildRoom(f: Folder, colors: { main: Color3, trim: Color3 })
	local c = centre()
	local size = H.cell.size
	-- the floor's trim ring and rug (the server's floor holds you up); the boxes as Shared.HideoutKit.foundryBoxes
	-- lists them (trim, rug, then the walls), so its modules know which part each hides
	local parts: { [number]: BasePart } = {}
	parts[1] =
		part(f, Vector3.new(size - 8, 0.2, size - 8), CFrame.new(c + Vector3.new(0, 0.15, 0)), colors.trim)
	parts[2] =
		part(f, Vector3.new(size - 24, 0.25, size - 24), CFrame.new(c + Vector3.new(0, 0.2, 0)), colors.main)
	-- the walls (drawn, the server's are invisible), with a glowing band in the side's colour
	local walls: { BasePart } = {}
	for i = 0, 3 do
		local a = i * math.pi / 2
		local out = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -size / 2)
		local wall =
			part(f, Vector3.new(size, 30, 2), CFrame.new(c) * out * CFrame.new(0, 15, 0), colors.trim)
		wall.Material = Enum.Material.Concrete
		walls[i + 1] = wall
		local band =
			part(f, Vector3.new(size - 10, 6, 0.5), CFrame.new(c) * out * CFrame.new(0, 18, 1.2), colors.main)
		band.Material = Enum.Material.Neon
		band.Transparency = 0.3
	end
	local light = part(f, Vector3.new(4, 1, 4), CFrame.new(c + Vector3.new(0, 28, 0)), Color3.new(1, 1, 1))
	light.Transparency = 1
	local pl = Instance.new("PointLight")
	pl.Range = 60
	pl.Brightness = 1.6
	pl.Color = Color3.fromRGB(255, 244, 228)
	pl.Parent = light
	part(f, Vector3.new(24, 0.6, 6), CFrame.new(c + Vector3.new(0, 26, -size / 2 + 4)), colors.main).Material =
		Enum.Material.Neon
	-- the hideout art pass: iron wall bays, diamond plate floor tiles and rug tiles in the side's colour over the
	-- parts (the light bands stay); match each wall part to HideoutKit's box by where it stands
	for k, b in HideoutKit.foundryBoxes(Config) do
		if b.name == "wall" then
			for _, w in walls do
				local d = w.Position - (c + Vector3.new(b.x, b.y, b.z))
				if d.Magnitude < 1 then
					parts[k] = w
				end
			end
		end
	end
	local places, hides = HideoutKit.foundry(Config, tint(colors.main), QualityController.name)
	shellOver(f, places, hides, parts)
	titleSign(f, colors)
end

-- The Vigil's HQ: the hideout under the plaza (nate's lore plan Q2; Shared.HqRules.hideout): concrete, pipes,
-- cable trays, work lamps, monitors and the city map wall, the service stair down from the plaza, no sky. The
-- side's colours stay on the rug, the pads and the title.
local function buildHideout(f: Folder, colors: { main: Color3, trim: Color3 })
	local c = centre()
	local size = H.cell.size
	part(f, Vector3.new(size - 24, 0.25, size - 24), CFrame.new(c + Vector3.new(0, 0.3, 0)), colors.main).Transparency =
		0.35
	local pieces = HqRules.hideout(Config)
	local parts: { [number]: Part } = {}
	for i, p in pieces do
		local cf = CFrame.new(c + Vector3.new(p.x, p.y, p.z))
		if p.rz then
			cf *= CFrame.Angles(0, 0, math.rad(p.rz))
		end
		local made = part(f, Vector3.new(p.sx, p.sy, p.sz), cf, paletteColor(p.color))
		parts[i] = made
		local mat = p.mat and (Enum.Material :: any)[p.mat]
		if mat then
			made.Material = mat
		end
		if p.light then
			local l = Instance.new("PointLight")
			l.Range = p.light
			l.Brightness = 1.1
			l.Color = made.Color
			l.Parent = made
		end
	end
	-- the hideout art pass: the room shell's modules over the parts (Shared.HideoutKit), which stay hidden (their
	-- lights still shine); the glowing faces stay as they are
	local places, hides = HideoutKit.cell(Config, pieces, QualityController.name)
	shellOver(f, places, hides, parts)
	-- a soft fill so the room's middle is never dark
	local fill = part(f, Vector3.new(4, 1, 4), CFrame.new(c + Vector3.new(0, 26, 0)), Color3.new(1, 1, 1))
	fill.Transparency = 1
	local pl = Instance.new("PointLight")
	pl.Range = 60
	pl.Brightness = 1.1
	pl.Color = paletteColor(H.hideout.colors.lamp)
	pl.Parent = fill
	titleSign(f, colors)
end

local function stationPad(f: Folder, name: string, colors: { main: Color3, trim: Color3 })
	local pos = stationAt(name, HqArtKit.PAD.y)
	local pad = part(f, Vector3.new(10, 0.4, 10), CFrame.new(pos), colors.main, Enum.Material.Neon)
	pad.Transparency = 0.4
	local post =
		part(f, Vector3.new(1.2, 3.2, 1.2), CFrame.new(stationAt(name, HqArtKit.POST.y)), colors.trim)
	-- the art pass: the side's pad and this station's console over them (the post keeps its sign and prompt)
	local foot = CFrame.new(stationAt(name, 0))
	if HqMeshes.place(f, HqArtKit.pad(state.side), foot) then
		pad.Transparency = 1
	end
	local console = HqArtKit.station(state.side, name)
	if
		console
		and HqMeshes.place(f, console, foot * CFrame.Angles(0, math.rad(HqArtKit.FACING[name] or 0), 0))
	then
		HqMeshes.hide(post)
	end
	-- WP12: a visitor reads every station as the owner's; only the exit works (LEAVE HQ)
	local visiting = state.visit ~= nil
	if visiting and not VisitRules.allowed(name) then
		sign(post, string.upper(STATION_NAMES[name]), VT.station, 4)
		return
	end
	local action = if visiting then VT.leave else STATION_ACTIONS[name]
	sign(post, string.upper(STATION_NAMES[name]), action, 4)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = STATION_NAMES[name]
	prompt.KeyboardKeyCode = Enum.KeyCode.B -- E is Skill 2
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = H.stationRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = post
	prompt.Triggered:Connect(function()
		if name == "exit" then
			Net.send(if state.visit then "HqVisitLeave" else "HqLeave")
		else
			HqClient.Station:Fire(name)
		end
	end)
end

-- A training dummy robot on a plate: a metal robot on the heroes' blocky R15 rig (nate, 2026-11-16: "literally
-- everyone should be r15. enemies too"), glowing eye visor and a red target on the chest; the big one has the
-- creator's Large build at 2.6 times the size. Once Art.Hq is imported: a padded sparring bot (its own 15 R15
-- meshes, NpcRig's `look` "Hq") in the side's colours, a weighted base with bolts, a bullseye and a curved
-- visor (HqArtKit.SHAPES); until then the bare metal robot (PLACEHOLDER ART).
local DUMMY_COLORS = {
	hero = {
		body = Color3.fromRGB(232, 236, 246),
		limb = Color3.fromRGB(150, 176, 226),
		ends = SIDE_COLORS.hero.main,
	},
	villain = {
		body = Color3.fromRGB(78, 70, 88),
		limb = Color3.fromRGB(120, 112, 128),
		ends = SIDE_COLORS.villain.main,
	},
}
local function dummy(f: Folder, pos: Vector3, big: boolean?, look: Vector3?, sideName: string?)
	local s = if big then 2.6 else 1
	local base = pos - Vector3.new(0, 3 * s, 0)
	local metal = Color3.fromRGB(150, 156, 170)
	local plate = part(
		f,
		Vector3.new(3 * s, 0.6, 3 * s),
		CFrame.new(base + Vector3.new(0, 0.3, 0)),
		Color3.fromRGB(60, 64, 76)
	)
	HqMeshes.cover(plate, "dummyBase")
	local factors = if big then BodyShape.factors(Config, { gender = 1, build = 3, height = 3 }) else nil
	local layout = RigMath.layout(Config.HeroRig, factors, s)
	local padded = HqMeshes.ready(HqArtKit.BODY)
	local side = DUMMY_COLORS[sideName or state.side] or DUMMY_COLORS.hero
	local colors: { [string]: Color3 } = {}
	for _, name in BodyShape.PARTS do
		if padded then
			colors[name] = if string.find(name, "Torso") or name == "Head"
				then side.body
				elseif string.find(name, "Hand") or string.find(name, "Foot") then side.ends
				else side.limb
		else
			colors[name] = if big and string.find(name, "Arm") then Color3.fromRGB(90, 94, 110) else metal
		end
	end
	local rig = NpcRig.build(
		layout,
		"Dummy",
		colors,
		Enum.Material.Metal,
		nil,
		if big then "MaleLarge" else nil,
		if padded then HqArtKit.BODY_LOOK else nil
	)
	rig.model.Parent = f
	local feet = base + Vector3.new(0, 0.6, 0)
	local flat = if look then Vector3.new(look.X, 0, look.Z) else Vector3.zero
	NpcRig.place(rig, if flat.Magnitude > 0.01 then CFrame.lookAt(feet, feet + flat) else CFrame.new(feet))
	for _, name in { "Head", "UpperTorso", "LowerTorso" } do
		rig.parts[name].CanQuery = true
	end
	local head, chest = rig.parts.Head, rig.parts.UpperTorso
	local eye = Instance.new("Part")
	eye.Name = "Eye"
	eye.Size = Vector3.new(head.Size.X * 0.7, head.Size.Y * 0.18, 0.2)
	eye.Color = if big then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(120, 220, 255)
	eye.Material = Enum.Material.Neon
	eye.CastShadow = false
	NpcRig.fix(rig, "Head", eye, CFrame.new(0, head.Size.Y * 0.08, -head.Size.Z * 0.5))
	HqMeshes.cover(eye, "dummyVisor")
	local target = Instance.new("Part")
	target.Name = "Target"
	target.Shape = Enum.PartType.Cylinder
	target.Size = Vector3.new(0.2, chest.Size.Y * 0.8, chest.Size.Y * 0.8)
	target.Color = Color3.fromRGB(230, 70, 60)
	target.Material = Enum.Material.Neon
	target.CastShadow = false
	NpcRig.fix(
		rig,
		"UpperTorso",
		target,
		CFrame.new(0, 0, -chest.Size.Z * 0.5 - 0.05) * CFrame.Angles(0, math.pi / 2, 0)
	)
	HqMeshes.cover(target, "dummyTarget")
end

-- The Dev panel's Test Lab draws its training dummies with this (Studio only): the HQ's dummy at `pos` (its centre,
-- 3 studs up a small one) facing `look`, into `f`
function HqClient.drawDummy(f: Folder, pos: Vector3, big: boolean?, look: Vector3?)
	dummy(f, pos, big, look)
end

local function statue(f: Folder, entry: { [string]: any }, at: CFrame)
	local base = part(
		f,
		Vector3.new(5, 2, 5),
		at * CFrame.new(0, HqArtKit.PLINTH.y, 0),
		Color3.fromRGB(120, 120, 130),
		Enum.Material.Slate
	)
	if HqMeshes.place(f, HqArtKit.plinth(state.side), at) then
		HqMeshes.hide(base)
	end
	local look = entry.words and LookCodec.read(entry.words)
	local model = Preview.clone()
	if model then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		model:PivotTo(at * CFrame.new(0, 5, 0))
		if look then
			LookKit.strip(model)
			LookKit.build(model, look)
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.Color = Color3.fromRGB(196, 190, 178)
				d.Material = Enum.Material.Marble
			elseif d:IsA("Decal") or d:IsA("ParticleEmitter") or d:IsA("Trail") then
				d:Destroy()
			end
		end
		model.Parent = f
	end
	local plate =
		part(f, Vector3.new(4, 0.6, 0.2), at * CFrame.new(0, 1.2, -2.6), Color3.fromRGB(200, 170, 90))
	plate.Material = Enum.Material.Foil
	sign(
		plate,
		string.upper(entry.name or "Legend"),
		string.format("Level %d   Legacy %d", entry.level or Config.Stats.levelCap, entry.rank or 1),
		1.4
	)
end

local function trophyWall(f: Folder, colors: { main: Color3, trim: Color3 })
	local c = centre()
	local bx, by, bz = HqArtKit.trophyBase(Config)
	HqMeshes.place(f, HqArtKit.trophyWall(state.side), CFrame.new(c + Vector3.new(bx, by, bz))) -- its frame
	local shown = state.trophies or {}
	local slots = state.trophySlots or 3
	local plaqueLook = HqArtKit.plaque(state.side)
	for i = 1, slots do
		local x, y, z = HqArtKit.trophySpot(Config, i)
		local at = c + Vector3.new(x, y, z)
		local idx = shown[i]
		local t = idx and H.trophies[idx]
		local plaque =
			part(f, Vector3.new(3.6, 3, 0.4), CFrame.new(at), if t then colors.main else colors.trim)
		plaque.Material = if t then Enum.Material.Foil else Enum.Material.SmoothPlastic
		-- the plaque in the side's colour when it holds a trophy, its trim when empty
		local body = { [plaqueLook .. "Body"] = tint(if t then colors.main else colors.trim) }
		if HqMeshes.place(f, plaqueLook, CFrame.new(at), body) then
			HqMeshes.hide(plaque)
		end
		if t then
			local cup = part(f, Vector3.new(1.2, 1.4, 1.2), CFrame.new(at + Vector3.new(0, 0, -0.6)), GOLD)
			cup.Shape = Enum.PartType.Cylinder
			cup.CFrame = CFrame.new(at + Vector3.new(0, 0.2, -0.6)) * CFrame.Angles(0, 0, math.pi / 2)
			if HqMeshes.place(f, HqArtKit.trophy(idx), CFrame.new(at + Vector3.new(0, 0.2, -0.6))) then
				HqMeshes.hide(cup)
			end
			sign(plaque, t.name, nil, 2)
		end
	end
end

-- The city's thank-you gifts, the Cafe sign, the collection props and the Hero Pass props (HqArtKit.PROP_SPOTS;
-- 19 to 22 had no spot before, so they never showed). A 3-stud block each (PLACEHOLDER ART) until Art.Hq is
-- imported, then each its own mesh look, turned into the room.
local function props(f: Folder)
	for _, bit in state.props or {} do
		local spot = HqArtKit.PROP_SPOTS[bit]
		local name = H.props[bit]
		if spot and name and HqArtKit.PART_PROPS[bit] == "LoreShelf" then
			-- side-content: the Lore Shelf, one book a district, every one glowing (the prop comes with the full set)
			local at = centre() + Vector3.new(spot[1], 0, spot[2])
			local ry = math.rad(HqArtKit.facing(spot[1], spot[2]))
			local done: { [string]: boolean } = {}
			local ids: { string } = {}
			for _, d in Config.Lore.districts do
				done[d.id] = true
				table.insert(ids, d.id)
			end
			local colors = LoreBookKit.colors(Config.Lore.look, nil)
			colors.spine = { 120, 80, 50 }
			local parts = LoreBooks.build(
				f,
				LoreBookKit.shelf(ids, done),
				colors,
				CFrame.new(at) * CFrame.Angles(0, ry, 0),
				function(key)
					return Config.Lore.look.cover[string.sub(key, 6)]
				end
			)
			local back = parts.Back
			if back then
				sign(back, name, nil, 3)
			end
		elseif spot and name then
			local at = centre() + Vector3.new(spot[1], 0, spot[2])
			local p = part(
				f,
				Vector3.new(3, 3, 3),
				CFrame.new(at + Vector3.new(0, 1.5, 0)),
				Color3.fromRGB(120, 180, 110)
			)
			if bit == 6 then
				p.Size = Vector3.new(1, 4, 0.4)
				p.Color = GOLD
				p.Material = Enum.Material.Foil
				p.CFrame = CFrame.new(at + Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.rad(30))
			elseif bit == 1 then
				p.Size = Vector3.new(6, 2, 0.4)
				p.Color = Color3.fromRGB(240, 140, 90)
			end
			sign(p, name, nil, 3)
			local look = HqArtKit.PROPS[bit]
			local ry = math.rad(HqArtKit.facing(spot[1], spot[2]))
			if look and HqMeshes.place(f, look, CFrame.new(at) * CFrame.Angles(0, ry, 0)) then
				HqMeshes.hide(p)
			end
		end
	end
end

-- Lore step 12 (the city remembers): the hideout's dressing for your own side's reputation tier (Shared.RepTiers:
-- the Safehouse's thank-you notes, Patch's hacking rig and the relic case; the Foundry's loot vault, trophy
-- screen and captured Crane robot). Purely visual; the stations stay where they are. Parts (PLACEHOLDER ART)
-- until Art.Hq is imported; then the named pieces are drawn as meshes (HqArtKit.DRESS) and the glowing screens,
-- LEDs, frames, note icons and the robot's eyes and chest bars stay parts.
local SHAPES: { [string]: Enum.PartType } = {
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Wedge,
}
-- The captured robot as a figure on Roblox's own blocky body (NpcRig.robloxMeshes), `torso` its torso's middle:
-- the Spark Trooper uniform's real Shirt and Pants (Config.NpcLooks), a catalog face and catalog hair, hung limp
-- from the hook by a strap. Returns whether it was built (false: no Roblox body, clothes or faces yet).
local function captive(f: Folder, torso: Vector3): boolean
	local K = HqArtKit.CAPTIVE
	local NL = Config.NpcLooks
	local recipe = NL and NL.robots and NL.robots[K.kind]
	local id = recipe and recipe.clothes and recipe.clothes[K.version]
	local face = NpcRig.catalogFace(K.face)
	if not NpcRig.robloxMeshes() or not id or id == 0 or not face then
		return false
	end
	local skin = Config.Enemies.look.skins[1]
	local colors: { [string]: Color3 } = {}
	for _, name in BodyShape.PARTS do
		colors[name] = Color3.fromRGB(skin[1], skin[2], skin[3])
	end
	local rig =
		NpcRig.build(RigMath.layout(Config.HeroRig, nil, K.scale), "Captive", colors, nil, nil, nil, nil)
	NpcRig.redress(rig, nil, "rbxassetid://" .. id)
	NpcRig.face(rig, face)
	NpcRig.showHair(rig, K.hair, K.hair)
	rig.model.Parent = f
	NpcRig.place(rig, CFrame.new(torso + Vector3.new(0, K.feet, K.forward)))
	for joint, a in K.pose do
		NpcRig.bend(rig, joint, CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3])))
	end
	-- the strap from the hook down behind its neck
	local strap = part(
		f,
		Vector3.new(0.3, K.strap, 0.3),
		CFrame.new(torso + Vector3.new(0, K.feet + K.scale * 5 - K.strap / 2 + 0.6, K.forward + 0.55)),
		Color3.fromRGB(218, 186, 120),
		Enum.Material.Fabric
	)
	strap.Name = "Strap"
	return true
end

local function dressing(f: Folder)
	local c = centre()
	local pieces = RepTiers.dressing(Config, state.side, state.repTier or 0)
	local madeParts: { [number]: BasePart } = {}
	for i, p in pieces do
		local cf = CFrame.new(c + Vector3.new(p.x, p.y, p.z))
		if p.ry then
			cf *= CFrame.Angles(0, math.rad(p.ry), 0)
		end
		if p.rz then
			cf *= CFrame.Angles(0, 0, math.rad(p.rz))
		end
		local made = part(f, Vector3.new(p.sx, p.sy, p.sz), cf, Color3.fromRGB(p.rgb[1], p.rgb[2], p.rgb[3]))
		local mat = p.mat and (Enum.Material :: any)[p.mat]
		if mat then
			made.Material = mat
		end
		local shape = p.shape and SHAPES[p.shape]
		if shape == Enum.PartType.Wedge then
			-- a wedge is its own class: swap the box for one
			local w = Instance.new("WedgePart")
			w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
			w.Size, w.CFrame, w.Color, w.Material = made.Size, made.CFrame, made.Color, made.Material
			w.Parent = f
			made:Destroy()
			made = w :: any
		elseif shape then
			made.Shape = shape
		end
		if p.clear then
			made.Transparency = p.clear
		end
		if p.light then
			local l = Instance.new("PointLight")
			l.Range = p.light
			l.Brightness = 1.2
			l.Color = made.Color
			l.Parent = made
		end
		madeParts[i] = made
	end
	-- the captured Crane robot (Foundry rank 3): like every robot now, a figure on Roblox's own body in its
	-- uniform with a catalog face and hair (HqArtKit.CAPTIVE), limp on the hook; its boxes hide under it. Until
	-- Roblox's body is there, the robot mesh (HqCaptiveBot) or its boxes, as before.
	local figure = false
	for _, p in pieces do
		if p.name == HqArtKit.CAPTIVE.at then
			figure = captive(f, c + Vector3.new(p.x, p.y, p.z))
		end
	end
	local places, hides = HqArtKit.dressing(state.side, pieces)
	local drawn: { [number]: boolean } = {}
	for k, pl in places do
		local cf = CFrame.new(c + Vector3.new(pl.x, pl.y, pl.z)) * CFrame.Angles(0, math.rad(pl.ry or 0), 0)
		if figure and pl.look == HqArtKit.CAPTIVE.look then
			drawn[k] = true
		else
			drawn[k] = HqMeshes.place(f, pl.look, cf)
		end
	end
	if figure then
		for i, p in pieces do
			if HqArtKit.CAPTIVE.covers[p.name] and madeParts[i] then
				HqMeshes.hide(madeParts[i])
			end
		end
	end
	for i, k in hides do
		local p = madeParts[i]
		if p and drawn[k] then
			HqMeshes.hide(p)
		end
	end
end

-- WP9 (gap G5, spec H5): the WANTED poster and the nemesis heads on the east wall (Shared.WantedRules,
-- Config.Hq.wanted): a SurfaceGui on the paper part (the nemesis's bust in a ViewportFrame, built from the same
-- pieces NemesisFx puts on its body) over the printed bill (Config.Hq.wanted.paper, art/ui/wanted_paper.py: torn
-- edges, so the part itself goes clear), on the board; the board, mounts and plates are Art.Hq meshes and every
-- head and bust piece is shaped (HqArtKit.SHAPES: Art.Hq's skull, face, jaw, horns, spikes, visor, chest,
-- shoulders and cape, and Art.NemParts' eyes, dome, cyclops eye, neck, plates, cannon, heal drone and antenna;
-- list-combat 2026-11-20, Everything Left 397), each in its own colours. Parts stand in for anything not imported.
local W = H.wanted
local PAPER = Color3.fromRGB(236, 220, 180)
local INK = Color3.fromRGB(40, 30, 24)
local WANTED_RED = Color3.fromRGB(150, 30, 30)
local WOOD = Color3.fromRGB(120, 78, 44)
local STAMPS: { [string]: { any } } = {
	locked = { "LEVEL " .. Config.Nemesis.minLevel, Color3.fromRGB(70, 70, 80) },
	waiting = { "ON ITS WAY", Color3.fromRGB(70, 70, 80) },
	showdown = { "SHOWDOWN READY", Color3.fromRGB(200, 40, 40) },
}
-- the same notes as the WANTED panel (NemesisHud)
local function wantedNote(st: string): string
	if st == "locked" then
		return "Your nemesis finds you from level " .. Config.Nemesis.minLevel
	elseif st == "waiting" then
		return "A new one is on its way, one rank tougher"
	elseif st == "showdown" then
		return "Its weak point is known: its back. Take it down."
	end
	return "It hunts you in the city. Each escape leaves Intel."
end

-- the wall's frame: its face's foot, looking into the room (WantedRules.layout's frame)
local function wallFrame(): CFrame
	local at = centre() + Vector3.new(W.wall.x, 0, W.wall.z)
	return CFrame.lookAt(at, at + Vector3.new(W.wall.nx, 0, W.wall.nz))
end

local PART_SHAPES: { [string]: Enum.PartType } =
	{ Ball = Enum.PartType.Ball, Cylinder = Enum.PartType.Cylinder }
-- one WantedRules piece as a part in `frame`
local function lookPart(parent: Instance, p: WantedRules.Piece, frame: CFrame): Part
	local cf = frame
		* CFrame.new(p.x, p.y, p.z)
		* CFrame.Angles(0, p.ry or 0, 0)
		* CFrame.Angles(0, 0, p.rz or 0)
	local made = part(parent, Vector3.new(p.sx, p.sy, p.sz), cf, Color3.fromRGB(p.rgb[1], p.rgb[2], p.rgb[3]))
	local mat = (Enum.Material :: any)[p.mat]
	if mat then
		made.Material = mat
	end
	local shape = p.shape and PART_SHAPES[p.shape]
	if shape then
		made.Shape = shape
	end
	if p.mat == "Glass" then
		made.Transparency = 0.35
	end
	return made
end

local function words(
	parent: Instance,
	t: string,
	y: number,
	h: number,
	color: Color3,
	font: Enum.Font?
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0.04, 0, 0, y)
	l.Size = UDim2.new(0.92, 0, 0, h)
	l.Font = font or Enum.Font.Bangers
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.Text = t
	l.Parent = parent
	return l
end

local function surface(p: BasePart, pixels: number): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pixels
	g.LightInfluence = 0.4
	g.MaxDistance = 120
	g.Parent = p
	return g
end

local function wantedPoster(f: Folder)
	local d = state.wanted
	if not d or not d.look then
		return
	end
	local frame = wallFrame()
	local L = WantedRules.layout(Config)
	local b, s = L.board, L.poster
	local board =
		part(f, Vector3.new(b.sx, b.sy, b.sz), frame * CFrame.new(b.x, b.y, b.z), WOOD, Enum.Material.Wood)
	local paper = part(f, Vector3.new(s.sx, s.sy, s.sz), frame * CFrame.new(s.x, s.y, s.z), PAPER)
	paper.Material = Enum.Material.Fabric
	local pins = {}
	for _, at in HqArtKit.pins(Config) do -- two red pins at the top corners
		local pin = part(
			f,
			Vector3.new(0.35, 0.35, 0.35),
			frame * CFrame.new(at[1], at[2], at[3]),
			Color3.fromRGB(200, 40, 40)
		)
		pin.Shape = Enum.PartType.Ball
		table.insert(pins, pin)
	end
	-- the art pass: the side's board (a cork board in a wood frame, or a riveted steel plate) with its own pins;
	-- the paper and its SurfaceGui stay the part
	if HqMeshes.place(f, HqArtKit.board(state.side), frame * CFrame.new(b.x, b.y, b.z)) then
		HqMeshes.hide(board)
		for _, pin in pins do
			HqMeshes.hide(pin)
		end
	end
	local g = surface(paper, W.pixels)
	local h = s.sy * W.pixels
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = PAPER
	back.BorderSizePixel = 0
	back.Parent = g
	if W.paper then
		-- the printed bill: its torn edge shows the board, so the part and the plain card go clear
		back.BackgroundTransparency = 1
		paper.Transparency = 1
		local bill = Instance.new("ImageLabel")
		bill.Name = "Paper"
		bill.BackgroundTransparency = 1
		bill.Image = "rbxassetid://" .. W.paper
		bill.Size = UDim2.fromScale(1, 1)
		bill.ZIndex = 0
		bill.Parent = back
	else
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.Thickness = 6
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = back
	end
	words(back, "WANTED", 8, h * 0.15, WANTED_RED)
	-- its bust (a black silhouette while it is locked or on its way)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundColor3 = Color3.fromRGB(214, 196, 156)
	vp.BorderSizePixel = 0
	vp.Position = UDim2.new(0.1, 0, 0, h * 0.17)
	vp.Size = UDim2.new(0.8, 0, 0, h * 0.44)
	vp.Ambient = Color3.fromRGB(150, 150, 160)
	vp.LightColor = Color3.fromRGB(255, 245, 230)
	vp.LightDirection = Vector3.new(-0.4, -1, 0.6)
	if W.paper then
		vp.BackgroundTransparency = 0.45 -- the paper shows through behind the bust
	end
	vp.Parent = back
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.9, -17), Vector3.new(0, 1.6, 0)) -- the bust faces -z
	cam.Parent = vp
	vp.CurrentCamera = cam
	for _, p in WantedRules.bust(Config.Nemesis, d.look) do
		HqMeshes.cover(lookPart(vp, p, CFrame.new()), p.name) -- (the art pass: its shaped pieces)
	end
	local hidden = d.state == "locked" or d.state == "waiting"
	if hidden then
		vp.ImageColor3 = Color3.new(0, 0, 0)
	end
	local rank = d.look.rank or 1
	words(back, if d.state == "locked" then "???" else string.upper(d.look.name), h * 0.62, h * 0.1, INK)
	words(back, "RANK " .. rank .. "  " .. string.rep("★", rank), h * 0.725, h * 0.065, INK)
	local intel = if hidden
		then ""
		else string.format("INTEL %d / %d", d.intel or 0, d.need or Config.Nemesis.intelForShowdown)
	words(back, intel, h * 0.795, h * 0.06, INK, Enum.Font.GothamBold)
	words(back, wantedNote(d.state), h * 0.86, h * 0.11, INK, Enum.Font.GothamBold)
	local stamp = STAMPS[d.state]
	if stamp then
		local l = words(back, stamp[1], h * 0.36, h * 0.12, stamp[2])
		l.Rotation = -14
		l.Position = UDim2.new(0.08, 0, 0, h * 0.36)
		l.Size = UDim2.new(0.84, 0, 0, h * 0.12)
		l.BackgroundTransparency = 0.25
		l.BackgroundColor3 = PAPER
		local box = Instance.new("UIStroke")
		box.Color = stamp[2]
		box.Thickness = 4
		box.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		box.Parent = l
	end
	-- B (E is Skill 2) reads it: the WANTED panel, with SHOWDOWN once your Intel is full (WP12: the owner's
	-- only; a visitor just reads the poster)
	if state.visit then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = W.prompt.object
	prompt.ActionText = W.prompt.action
	prompt.KeyboardKeyCode = Enum.KeyCode.B
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = H.stationRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = paper
	prompt.Triggered:Connect(function()
		HqClient.Station:Fire("wanted")
	end)
end

-- the heads: a plaque per nemesis rank (rank 1 on the left), the head of each one beaten and a plate under it
-- with its name and stars; an empty plaque shows "?"
local function nemesisHeads(f: Folder)
	local frame = wallFrame()
	local L = WantedRules.layout(Config)
	for r, entry in state.heads or {} do
		local m, pl = L.mounts[r], L.plates[r]
		if not m or not pl then
			continue
		end
		local look = entry.look
		local plaque = part(
			f,
			Vector3.new(m.sx, m.sy, m.sz),
			frame * CFrame.new(m.x, m.y, m.z),
			if look then WOOD else Color3.fromRGB(70, 58, 48),
			Enum.Material.Wood
		)
		local plate = part(f, Vector3.new(pl.sx, pl.sy, pl.sz), frame * CFrame.new(pl.x, pl.y, pl.z), GOLD)
		plate.Material = if look then Enum.Material.Foil else Enum.Material.SmoothPlastic
		if not look then
			plate.Color = Color3.fromRGB(110, 100, 90)
		end
		-- the art pass: the side's mount and a gold name plate (grey while empty); the "?" and the name are the
		-- hidden parts' SurfaceGuis, drawn in front of the meshes
		if HqMeshes.place(f, HqArtKit.mount(state.side), frame * CFrame.new(m.x, m.y, m.z)) then
			HqMeshes.hide(plaque)
		end
		local plateTint = { [HqArtKit.NAMEPLATE .. "Body"] = tint(plate.Color) }
		if HqMeshes.place(f, HqArtKit.NAMEPLATE, frame * CFrame.new(pl.x, pl.y, pl.z), plateTint) then
			HqMeshes.hide(plate)
		end
		local label = words(surface(plate, 60), "", 0, 0, INK)
		label.Position = UDim2.fromScale(0.03, 0)
		label.Size = UDim2.fromScale(0.94, 1)
		label.Text = if look
			then string.upper(look.name) .. "  " .. string.rep("★", r)
			else "RANK " .. r .. "  ?"
		if look then
			local hx, hy, hz = WantedRules.headAt(m)
			for _, p in WantedRules.head(Config.Nemesis, look, hx, hy, hz) do
				HqMeshes.cover(lookPart(f, p, frame), p.name)
			end
		else
			local mark = words(surface(plaque, 40), "?", 0, 0, Color3.fromRGB(150, 130, 110))
			mark.Position = UDim2.fromScale(0, 0)
			mark.Size = UDim2.fromScale(1, 1)
		end
	end
end

local function draw()
	clear()
	if not state.on then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "HqDecor"
	f.Parent = Workspace
	folder = f
	local colors = SIDE_COLORS[state.side] or SIDE_COLORS.hero
	if state.side == "villain" then
		buildRoom(f, colors) -- The Foundry, as ever
	else
		buildHideout(f, colors) -- The Safehouse, under the plaza
	end
	for name in H.stations do
		stationPad(f, name, colors)
	end
	for _, d in state.dummies or {} do
		local pos = Vector3.new(d.x, d.y, d.z)
		dummy(f, pos)
		if not state.visit and (d.id or 0) > 0 then -- WP12: a visit copy's dummies are decor
			table.insert(dummies, { id = d.id, pos = pos })
		end
	end
	if state.sim then
		local pos = Vector3.new(state.sim.x, state.sim.y, state.sim.z)
		dummy(f, pos, true)
		table.insert(dummies, { id = state.sim.id, pos = pos })
	end
	-- the Hall of Legends: statues in a half ring
	local hall = stationAt("legends", 0)
	for i, entry in state.statues or {} do
		local a = math.rad(-80 + (i - 1) * (160 / math.max(1, math.min(#state.statues, 20) - 1)))
		local at = CFrame.new(hall + Vector3.new(math.sin(a) * 14, 0, math.cos(a) * 6 + 4))
			* CFrame.Angles(0, a + math.pi, 0)
		statue(f, entry, at)
	end
	trophyWall(f, colors)
	wantedPoster(f) -- WP9
	nemesisHeads(f)
	props(f)
	dressing(f)
end

-- a slam ring that fills over its warning time
local function slam(s: { number })
	local f = folder
	if not f then
		return
	end
	local pos, radius, warn = Vector3.new(s[1], s[2], s[3]), s[4], s[5]
	local ring = part(
		f,
		Vector3.new(0.3, radius * 2, radius * 2),
		CFrame.new(pos - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(255, 80, 60),
		Enum.Material.Neon
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.6
	local fill = ring:Clone()
	fill.Size = Vector3.new(0.35, 0.5, 0.5)
	fill.Transparency = 0.3
	fill.Parent = f
	TweenService:Create(
		fill,
		TweenInfo.new(warn, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(0.35, radius * 2, radius * 2) }
	):Play()
	task.delay(warn + 0.25, function()
		ring:Destroy()
		fill:Destroy()
	end)
end

-- hero-hall: the same training dummy for Crane's Hero Hall's training floor (HallClient), in a side's colours
HqClient.dummy = function(f: Folder, pos: Vector3, big: boolean?, side: string?)
	dummy(f, pos, big, nil, side)
end

function HqClient.state(): { [string]: any }
	return state
end

function HqClient.inside(): boolean
	return state.on == true
end

-- WP12: visiting a friend's HQ (a read-only copy): { owner, name }, or nil
function HqClient.visiting(): { owner: number, name: string }?
	return if state.on then state.visit else nil
end

function HqClient.visit(userId: number)
	Net.send("HqVisitAsk", userId)
end

function HqClient.answerVisit(userId: number, yes: boolean)
	Net.send("HqVisitAnswer", userId, if yes then 1 else 0)
end

function HqClient.leaveVisit()
	Net.send("HqVisitLeave")
end

function HqClient.kickVisitor(userId: number)
	Net.send("HqVisitKick", userId)
end

-- WP12: this device's Roblox block list goes to the server (GuardService.shuns), so a block stops visit asks;
-- sent at start and after every block or unblock ({ 0 } = none). StarterGui:GetCore can fail early: retried.
local StarterGui = game:GetService("StarterGui")
local blocksQueued = false
local function sendBlocks()
	if blocksQueued then
		return
	end
	blocksQueued = true
	task.delay(1, function()
		blocksQueued = false
		local ok, list = pcall(function()
			return StarterGui:GetCore("GetBlockedUserIds")
		end)
		local out = {}
		if ok and type(list) == "table" then
			for _, id in list do
				if type(id) == "number" and id > 0 and id % 1 == 0 and #out < 200 then
					table.insert(out, id)
				end
			end
		end
		if #out == 0 then
			out = { 0 }
		end
		Net.send("GuardBlocks", out)
	end)
end

local function watchBlocks()
	for _ = 1, 10 do
		local okB, blocked = pcall(function()
			return StarterGui:GetCore("PlayerBlockedEvent")
		end)
		local okU, unblocked = pcall(function()
			return StarterGui:GetCore("PlayerUnblockedEvent")
		end)
		if okB and okU and typeof(blocked) == "Instance" and typeof(unblocked) == "Instance" then
			(blocked :: any).Event:Connect(sendBlocks);
			(unblocked :: any).Event:Connect(sendBlocks)
			break
		end
		task.wait(3)
	end
	sendBlocks()
end

-- The Vigil's service door at the plaza's edge: the server builds a plain locked service door for everyone; on a
-- Vigil device its prompt reads the HQ's name and a small marker shows over it (the Syndicate never see either)
local doorPart: BasePart? = nil
local doorSide: string? = nil
local function serviceDoor()
	local side = if State.hero.side == "villain" then "villain" else "hero"
	local p = doorPart
	if not p or not p.Parent or (side == doorSide) then
		return
	end
	doorSide = side
	local prompt = p:FindFirstChildOfClass("ProximityPrompt")
	local vigil = side == "hero"
	if prompt then
		prompt.ObjectText = if vigil then H.names.hero else H.door.object
		prompt.ActionText = if vigil then H.door.enter else H.door.locked
	end
	local old = p:FindFirstChild("VigilMarker")
	if old then
		old:Destroy()
	end
	if vigil then
		local bb = Instance.new("BillboardGui")
		bb.Name = "VigilMarker"
		bb.Size = UDim2.fromOffset(150, 34)
		bb.StudsOffset = Vector3.new(0, 7.5, 0)
		bb.MaxDistance = H.door.markerRange
		bb.LightInfluence = 0
		bb.Parent = p
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.Bangers
		l.TextScaled = true
		l.TextColor3 = SIDE_COLORS.hero.main
		l.TextStrokeTransparency = 0.1
		l.Text = "V  " .. H.door.marker
		l.Parent = bb
	end
end

local function watchDoor(p: Instance)
	if p.Name == "HqDoor_hero" and p:IsA("BasePart") then
		doorPart = p
		doorSide = nil
		serviceDoor()
	end
end

function HqClient.init()
	task.spawn(function()
		local hq = Workspace:WaitForChild("Hq")
		hq.DescendantAdded:Connect(watchDoor)
		for _, d in hq:GetDescendants() do
			watchDoor(d)
		end
	end)
	State.Changed:Connect(serviceDoor)
	Net.listen("HqState", function(data)
		local was = state.on
		state = data
		draw()
		if was ~= data.on and not data.on then
			HqClient.Station:Fire(nil)
		end
		HqClient.Changed:Fire(state)
		HqClient.VisitorsChanged:Fire() -- WP12: SquadHud shows LEAVE HQ while you visit
	end)
	-- WP12: visits
	Net.listen("HqVisitAsked", function(ask)
		HqClient.VisitAsked:Fire(ask)
	end)
	Net.listen("HqVisitors", function(data)
		HqClient.visitors = data.list or {}
		HqClient.VisitorsChanged:Fire()
	end)
	task.spawn(watchBlocks)
	Net.listen("HqDps", function(packet)
		if packet.slam then
			slam(packet.slam)
		end
		HqClient.Dps:Fire(packet)
	end)
	CombatClient.addTargetSource(function()
		return dummies
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		-- a respawn inside never happens (the HQ has no fights), but a Legacy or slot switch rebuilds
		if state.on then
			task.defer(draw)
		end
	end)
end

return HqClient
