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
-- HqHud draws the station panels. PLACEHOLDER ART: every room piece is a box until the art pass (M10).

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
local State = require(script.Parent.Parent.State)

local CombatClient = require(script.Parent.CombatClient)
local Preview = require(script.Parent.Parent.Ui.Preview)

local HqClient = {}

HqClient.Changed = Signal.new() -- (state) on entering, leaving and every HqState
HqClient.Station = Signal.new() -- (name) a station prompt was used
HqClient.Dps = Signal.new() -- (packet) the training room meter, 2 Hz

local H = Config.Hq
local GOLD = Color3.fromRGB(255, 200, 60)
local function paletteColor(key: string): Color3
	local rgb = Config.City.palette[key] or { 255, 0, 255 }
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end
local SIDE_COLORS = {
	hero = { main = Color3.fromRGB(70, 140, 255), trim = Color3.fromRGB(240, 244, 255) },
	villain = { main = Color3.fromRGB(210, 60, 60), trim = Color3.fromRGB(40, 36, 44) },
}
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
	sign(title, string.upper(state.name or ""), "HQ level " .. (state.level or 1), 0)
end

local function buildRoom(f: Folder, colors: { main: Color3, trim: Color3 })
	local c = centre()
	local size = H.cell.size
	-- the floor's trim ring and rug (the server's floor holds you up)
	part(f, Vector3.new(size - 8, 0.2, size - 8), CFrame.new(c + Vector3.new(0, 0.15, 0)), colors.trim)
	part(f, Vector3.new(size - 24, 0.25, size - 24), CFrame.new(c + Vector3.new(0, 0.2, 0)), colors.main)
	-- the walls (drawn, the server's are invisible), with a glowing band in the side's colour
	for i = 0, 3 do
		local a = i * math.pi / 2
		local out = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -size / 2)
		local wall =
			part(f, Vector3.new(size, 30, 2), CFrame.new(c) * out * CFrame.new(0, 15, 0), colors.trim)
		wall.Material = Enum.Material.Concrete
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
	for _, p in HqRules.hideout(Config) do
		local cf = CFrame.new(c + Vector3.new(p.x, p.y, p.z))
		if p.rz then
			cf *= CFrame.Angles(0, 0, math.rad(p.rz))
		end
		local made = part(f, Vector3.new(p.sx, p.sy, p.sz), cf, paletteColor(p.color))
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
	local pos = stationAt(name, 0.4)
	local pad = part(f, Vector3.new(10, 0.4, 10), CFrame.new(pos), colors.main, Enum.Material.Neon)
	pad.Transparency = 0.4
	local post = part(f, Vector3.new(1.2, 3.2, 1.2), CFrame.new(pos + Vector3.new(0, 1.8, 0)), colors.trim)
	sign(post, string.upper(STATION_NAMES[name]), STATION_ACTIONS[name], 4)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = STATION_ACTIONS[name]
	prompt.ObjectText = STATION_NAMES[name]
	prompt.KeyboardKeyCode = Enum.KeyCode.B -- E is Skill 2
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = H.stationRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = post
	prompt.Triggered:Connect(function()
		if name == "exit" then
			Net.send("HqLeave")
		else
			HqClient.Station:Fire(name)
		end
	end)
end

-- PLACEHOLDER ART: a training dummy robot on a plate: a bare metal robot on the heroes' blocky R15 rig (nate,
-- 2026-11-16: "literally everyone should be r15. enemies too"), glowing eye visor and a red target on the chest;
-- the big one has the creator's Large build at 2.6 times the size
local function dummy(f: Folder, pos: Vector3, big: boolean?)
	local s = if big then 2.6 else 1
	local base = pos - Vector3.new(0, 3 * s, 0)
	local metal = Color3.fromRGB(150, 156, 170)
	part(
		f,
		Vector3.new(3 * s, 0.6, 3 * s),
		CFrame.new(base + Vector3.new(0, 0.3, 0)),
		Color3.fromRGB(60, 64, 76)
	)
	local factors = if big then BodyShape.factors(Config, { gender = 1, build = 3, height = 3 }) else nil
	local layout = RigMath.layout(Config.HeroRig, factors, s)
	local colors: { [string]: Color3 } = {}
	for _, name in BodyShape.PARTS do
		colors[name] = if big and string.find(name, "Arm") then Color3.fromRGB(90, 94, 110) else metal
	end
	local rig =
		NpcRig.build(layout, "Dummy", colors, Enum.Material.Metal, nil, if big then "MaleLarge" else nil)
	rig.model.Parent = f
	NpcRig.place(rig, CFrame.new(base + Vector3.new(0, 0.6, 0)))
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
end

local function statue(f: Folder, entry: { [string]: any }, at: CFrame)
	part(
		f,
		Vector3.new(5, 2, 5),
		at * CFrame.new(0, 1, 0),
		Color3.fromRGB(120, 120, 130),
		Enum.Material.Slate
	)
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
	local base = stationAt("trophies", 0) + Vector3.new(0, 0, 8)
	local shown = state.trophies or {}
	local slots = state.trophySlots or 3
	for i = 1, slots do
		local col, row = (i - 1) % 4, (i - 1) // 4
		local at = base + Vector3.new((col - 1.5) * 4.2, 4 + row * 3.6, 0)
		local idx = shown[i]
		local t = idx and H.trophies[idx]
		local plaque =
			part(f, Vector3.new(3.6, 3, 0.4), CFrame.new(at), if t then colors.main else colors.trim)
		plaque.Material = if t then Enum.Material.Foil else Enum.Material.SmoothPlastic
		if t then
			local cup = part(f, Vector3.new(1.2, 1.4, 1.2), CFrame.new(at + Vector3.new(0, 0, -0.6)), GOLD)
			cup.Shape = Enum.PartType.Cylinder
			cup.CFrame = CFrame.new(at + Vector3.new(0, 0.2, -0.6)) * CFrame.Angles(0, 0, math.pi / 2)
			sign(plaque, t.name, nil, 2)
		end
	end
end

-- PLACEHOLDER ART: the city's thank-you gifts and the Cafe sign
local PROP_SPOTS = {
	[1] = { 22, -30 },
	[2] = { -46, -40 },
	[3] = { -16, -26 },
	[4] = { 46, -40 },
	[5] = { 16, -26 },
	[6] = { 0, 20 },
	-- H7: the collection set props (Config.Collect rewards) along the side walls
	[7] = { -52, -28 },
	[8] = { -52, -16 },
	[9] = { -52, -4 },
	[10] = { -52, 22 },
	[11] = { -52, 34 },
	[12] = { -52, 46 },
	[13] = { 52, -28 },
	[14] = { 52, -16 },
	[15] = { 52, -4 },
	[16] = { 52, 22 },
	[17] = { 52, 34 },
	[18] = { 52, 46 },
}
local function props(f: Folder)
	for _, bit in state.props or {} do
		local spot = PROP_SPOTS[bit]
		local name = H.props[bit]
		if spot and name then
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
		end
	end
end

-- Lore step 12 (the city remembers): the hideout's dressing for your own side's reputation tier (Shared.RepTiers:
-- the Safehouse's thank-you notes, Patch's hacking rig and the relic case; the Foundry's loot vault, trophy
-- screen and captured Crane robot). Purely visual; the stations stay where they are. PLACEHOLDER ART.
local SHAPES: { [string]: Enum.PartType } = {
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Wedge,
}
local function dressing(f: Folder)
	local c = centre()
	for _, p in RepTiers.dressing(Config, state.side, state.repTier or 0) do
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
		table.insert(dummies, { id = d.id, pos = pos })
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

function HqClient.state(): { [string]: any }
	return state
end

function HqClient.inside(): boolean
	return state.on == true
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
	end)
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
