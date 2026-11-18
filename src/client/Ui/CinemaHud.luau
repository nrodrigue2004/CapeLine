-- CinemaHud: the cinematic layer on screen (nate's lore, build plan step 7; Config.Cinema).
-- * The cutscene player's screen (CinemaClient): the letterbox bars sliding in and out, SKIP (once the scene
--   was seen on this save), and a device-started scene's subtitles fed to the guide line box (Ui.GuideHud).
-- * Comic-panel flashback pages: a full-screen page of 3 to 5 panels with ink borders, captions and sound
--   words, sliding in one by one (PLACEHOLDER ART: each panel's picture is drawn from frames: a sky, a
--   ground, skyline blocks and simple figures, until the art pass). One sample page: "The old heroes' last
--   stand" (Dev panel only).
-- * A boss's name card: its name, its title and a stylised slam for 3 s when you arrive at the fight.
-- * The slow-mo finisher's screen (FinisherFx): Comic's big impact word, Anime's speed lines and freeze tint,
--   and a white frame that Reduce flashing removes. Everything is built once and reused (pooled), so a
--   finisher or a page makes no new objects on phones.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local CinemaPlan = require(Shared:WaitForChild("CinemaPlan"))

local Kit = require(script.Parent.Kit)
local GuideHud = require(script.Parent.GuideHud)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)

local CinemaHud = {}

local C = Config.Cinema
local U = Config.Ui

local gui: ScreenGui
local bars: { Frame } = {}
local skip: TextButton
local barsOn = false

local page: ScreenGui
local pageRoot: Frame
local pageTitle: TextLabel
local panels: { Frame } = {}
local built: { [string]: { Frame } } = {} -- each page's panels, built the first time it shows and kept
local pageOn: { id: string, def: any, shown: number }? = nil

local card: Frame
local cardName: TextLabel
local cardTitle: TextLabel
local cardSlash: Frame
local cardScale: UIScale
local cardUntil = 0

local over: ScreenGui
local word: TextLabel
local wordScale: UIScale
local white: Frame
local lines: { Frame } = {}
local linesUntil = 0
local tint: ColorCorrectionEffect? = nil

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

---------------------------------------------------------------------------
-- The letterbox and SKIP
---------------------------------------------------------------------------

local function setBars(on: boolean)
	if on == barsOn then
		return
	end
	barsOn = on
	local h = if on then C.letterbox.size else 0
	for _, b in bars do
		b.Visible = true
		TweenService:Create(b, TweenInfo.new(C.letterbox.tween), { Size = UDim2.fromScale(1, h) }):Play()
	end
end

local function buildBars()
	for i = 1, 2 do
		local bar = Kit.frame({
			Name = if i == 1 then "LetterTop" else "LetterBottom",
			AnchorPoint = Vector2.new(0, if i == 1 then 0 else 1),
			Position = UDim2.fromScale(0, if i == 1 then 0 else 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			round = false,
			Visible = false,
			ZIndex = 30,
		})
		bar.Parent = gui
		table.insert(bars, bar)
	end
	skip = Kit.button({
		Name = "Skip",
		Text = "SKIP",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -U.safe, 1, -U.safe),
		Size = UDim2.fromOffset(U.touchTarget * 2, U.touchTarget),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
		ZIndex = 70, -- above the comic page too
	}, CinemaClient.skip)
	skip.Parent = gui
end

---------------------------------------------------------------------------
-- Comic-panel pages (PLACEHOLDER ART)
---------------------------------------------------------------------------

local function box(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number
): Frame
	local f = Kit.frame({
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		round = false,
		ZIndex = z,
	})
	f.Parent = parent
	return f
end

-- A simple figure: a head and a body (heroes in bright colours, robots as blocky grey shapes)
local function figure(parent: Instance, x: number, color: Color3, robot: boolean)
	local ink = rgb(C.comic.ink)
	local body = box(
		parent,
		x,
		if robot then 0.5 else 0.54,
		if robot then 0.09 else 0.06,
		if robot then 0.22 else 0.18,
		color,
		64
	)
	Kit.stroke(body, ink, 2)
	local head = box(
		parent,
		x + (if robot then 0.015 else 0.008),
		if robot then 0.41 else 0.46,
		if robot then 0.06 else 0.045,
		0.08,
		color,
		64
	)
	Kit.stroke(head, ink, 2)
	if not robot then
		Kit.round(head, 40)
	end
end

local function picture(parent: Frame, p: any)
	local ink = rgb(C.comic.ink)
	local sky = box(parent, 0, 0, 1, 1, rgb(p.sky), 61)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(rgb(p.sky), rgb(p.sky):Lerp(Color3.new(1, 1, 1), 0.35))
	g.Parent = sky
	local ground = rgb(p.ground)
	box(parent, 0, 0.72, 1, 0.28, ground, 62)
	local kind = p.scene
	if kind == "city" or kind == "stand" then
		-- the skyline: blocks with a row of windows
		for i = 0, 6 do
			local h = 0.25 + ((i * 37) % 5) * 0.06
			local b = box(parent, i * 0.145, 0.72 - h, 0.12, h, ground:Lerp(ink, 0.3), 62)
			box(b, 0.2, 0.15, 0.6, 0.08, Color3.fromRGB(255, 230, 140), 63)
		end
	end
	if kind == "stand" then
		-- three old heroes facing the machines
		figure(parent, 0.12, Color3.fromRGB(70, 150, 255), false)
		figure(parent, 0.22, Color3.fromRGB(255, 200, 60), false)
		figure(parent, 0.32, Color3.fromRGB(235, 90, 90), false)
		figure(parent, 0.62, Color3.fromRGB(150, 150, 160), true)
		figure(parent, 0.78, Color3.fromRGB(130, 130, 140), true)
	elseif kind == "blast" then
		-- the lab going up: a round burst with rays
		for i = 0, 7 do
			local ray = box(parent, 0.5, 0.45, 0.9, 0.06, Color3.fromRGB(255, 220, 120), 62)
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Rotation = i * 22.5
		end
		local core = box(parent, 0.5, 0.45, 0.42, 0.62, Color3.fromRGB(255, 255, 230), 63)
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(core, 200)
		Kit.stroke(core, ink, 3)
	elseif kind == "school" then
		-- Halo Academy (The Hero Academy): a wide school front, its windows, a door and a gold halo over it
		local front = box(parent, 0.12, 0.34, 0.76, 0.38, Color3.fromRGB(235, 235, 240), 62)
		Kit.stroke(front, ink, 2)
		for i = 0, 4 do
			box(front, 0.06 + i * 0.19, 0.18, 0.11, 0.22, Color3.fromRGB(120, 190, 255), 63)
		end
		box(front, 0.42, 0.6, 0.16, 0.4, Color3.fromRGB(70, 110, 170), 63)
		local halo = box(parent, 0.5, 0.24, 0.3, 0.08, Color3.fromRGB(255, 220, 90), 63)
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(halo, 200)
		Kit.stroke(halo, ink, 2)
	elseif kind == "scan" then
		-- the copier workshop: a kid in a scanner pod, a green beam, the copy robot standing up
		local pod = box(parent, 0.16, 0.3, 0.22, 0.42, Color3.fromRGB(160, 230, 255), 62)
		pod.BackgroundTransparency = 0.4
		Kit.stroke(pod, ink, 3)
		figure(parent, 0.22, Color3.fromRGB(255, 170, 120), false)
		local beam = box(parent, 0.38, 0.5, 0.3, 0.04, Color3.fromRGB(120, 255, 160), 63)
		beam.AnchorPoint = Vector2.new(0, 0.5)
		figure(parent, 0.72, Color3.fromRGB(150, 150, 160), true)
	elseif kind == "toyshop" then
		-- Tick-Tock Toys (Wind-Up Lane): a shop front with a striped awning, a window of toys and a round clock sign
		local front = box(parent, 0.14, 0.36, 0.72, 0.36, Color3.fromRGB(245, 225, 190), 62)
		Kit.stroke(front, ink, 2)
		for i = 0, 5 do
			box(
				parent,
				0.12 + i * 0.127,
				0.3,
				0.127,
				0.08,
				if i % 2 == 0 then Color3.fromRGB(230, 70, 80) else Color3.fromRGB(250, 250, 250),
				63
			)
		end
		local window = box(front, 0.08, 0.3, 0.5, 0.45, Color3.fromRGB(150, 210, 255), 63)
		Kit.stroke(window, ink, 2)
		for i = 0, 2 do
			local toy = box(
				window,
				0.1 + i * 0.3,
				0.5,
				0.18,
				0.4,
				Color3.fromRGB(220, 60, 60):Lerp(Color3.fromRGB(90, 140, 230), i / 2),
				64
			)
			Kit.round(toy, 6)
		end
		box(front, 0.7, 0.4, 0.2, 0.6, Color3.fromRGB(120, 80, 50), 63)
		local clock = box(parent, 0.5, 0.2, 0.16, 0.16, Color3.fromRGB(255, 220, 90), 63)
		clock.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(clock, 200)
		Kit.stroke(clock, ink, 2)
	elseif kind == "gnome" then
		-- a lawn gnome waking: a red cone hat, a white beard, a wind-up key turning in its back; a small kid
		local hat = box(parent, 0.58, 0.32, 0.12, 0.18, Color3.fromRGB(220, 50, 50), 63)
		hat.Rotation = 8
		Kit.stroke(hat, ink, 2)
		box(parent, 0.57, 0.48, 0.14, 0.1, Color3.fromRGB(250, 250, 250), 63)
		local smock = box(parent, 0.56, 0.56, 0.16, 0.16, Color3.fromRGB(60, 110, 220), 63)
		Kit.stroke(smock, ink, 2)
		local key = box(parent, 0.74, 0.5, 0.1, 0.03, Color3.fromRGB(215, 170, 70), 64)
		key.Rotation = 35
		figure(parent, 0.22, Color3.fromRGB(120, 200, 255), false)
	elseif kind == "tantrum" then
		-- the Toymaker looming over a crying kid and a snapped toy (tears in blue drops)
		figure(parent, 0.3, Color3.fromRGB(120, 200, 255), false)
		for i = 0, 2 do
			local tear =
				box(parent, 0.27 + i * 0.03, 0.5 + i * 0.05, 0.02, 0.04, Color3.fromRGB(110, 180, 255), 64)
			Kit.round(tear, 20)
		end
		figure(parent, 0.66, Color3.fromRGB(150, 110, 80), false)
		local half = box(parent, 0.44, 0.66, 0.08, 0.05, Color3.fromRGB(220, 60, 60), 63)
		half.Rotation = -20
		local other = box(parent, 0.52, 0.67, 0.07, 0.05, Color3.fromRGB(220, 60, 60), 63)
		other.Rotation = 25
	elseif kind == "tap" then
		-- the Tantrum Tap: a brass tank with a funnel, pipes off to the sides and a gauge
		local tank = box(parent, 0.36, 0.3, 0.28, 0.42, Color3.fromRGB(205, 160, 70), 62)
		Kit.stroke(tank, ink, 3)
		box(parent, 0.42, 0.2, 0.16, 0.1, Color3.fromRGB(180, 140, 60), 62)
		for k = -1, 1, 2 do
			box(parent, 0.5 + k * 0.3 - 0.08, 0.5, 0.16, 0.04, Color3.fromRGB(160, 160, 170), 63)
		end
		local gauge = box(tank, 0.5, 0.35, 0.4, 0.25, Color3.fromRGB(250, 250, 240), 63)
		gauge.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(gauge, 200)
		Kit.stroke(gauge, ink, 2)
		local needle = box(gauge, 0.5, 0.5, 0.4, 0.06, Color3.fromRGB(220, 40, 40), 64)
		needle.AnchorPoint = Vector2.new(0, 0.5)
		needle.Rotation = -40
	elseif kind == "farm" then
		-- a red barn and a silo by the fields (The Harvest King)
		local barn = box(parent, 0.14, 0.4, 0.36, 0.32, Color3.fromRGB(190, 50, 40), 62)
		Kit.stroke(barn, ink, 2)
		local roof = box(parent, 0.32, 0.4, 0.3, 0.3, Color3.fromRGB(120, 40, 35), 62)
		roof.AnchorPoint = Vector2.new(0.5, 0.5)
		roof.Rotation = 45
		box(barn, 0.36, 0.45, 0.28, 0.55, Color3.fromRGB(245, 235, 220), 63)
		local silo = box(parent, 0.58, 0.2, 0.12, 0.52, Color3.fromRGB(190, 195, 205), 62)
		Kit.stroke(silo, ink, 2)
		local dome = box(parent, 0.58, 0.14, 0.12, 0.12, Color3.fromRGB(240, 240, 245), 63)
		Kit.round(dome, 200)
		for i = 0, 3 do
			box(parent, 0.74 + i * 0.065, 0.62, 0.035, 0.1, Color3.fromRGB(230, 200, 90), 63)
		end
	elseif kind == "sprout" then
		-- the farmer's hands glow and a sprout shoots up out of the dry ground
		figure(parent, 0.22, Color3.fromRGB(200, 160, 60), false)
		local glow = box(parent, 0.3, 0.6, 0.12, 0.12, Color3.fromRGB(180, 255, 120), 63)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(glow, 200)
		box(parent, 0.6, 0.3, 0.05, 0.42, Color3.fromRGB(70, 160, 60), 62)
		for i = 0, 2 do
			local leaf = box(
				parent,
				0.56 + (i % 2) * 0.08,
				0.32 + i * 0.12,
				0.12,
				0.06,
				Color3.fromRGB(110, 200, 80),
				63
			)
			leaf.Rotation = if i % 2 == 0 then -25 else 25
			Kit.round(leaf, 200)
		end
	elseif kind == "beast" then
		-- the Bramblebeast towers over the barn: a vine giant with a glowing pumpkin face
		local body = box(parent, 0.5, 0.42, 0.5, 0.6, Color3.fromRGB(50, 130, 60), 62)
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(body, 40)
		Kit.stroke(body, ink, 3)
		local head = box(parent, 0.5, 0.2, 0.26, 0.2, Color3.fromRGB(255, 150, 40), 63)
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(head, 200)
		Kit.stroke(head, ink, 2)
		for i = -1, 1, 2 do
			box(parent, 0.5 + i * 0.06 - 0.02, 0.17, 0.04, 0.05, Color3.fromRGB(255, 250, 200), 64)
		end
		box(parent, 0.08, 0.56, 0.16, 0.16, Color3.fromRGB(190, 50, 40), 63)
	elseif kind == "pier" then
		-- Gull Point Pier (The Salt Dogs): a plank pier on posts over the sea, the harbour hut at its end, a diver
		-- in a brass helmet climbing up the ladder
		local wood = Color3.fromRGB(150, 105, 65)
		local deck = box(parent, 0.08, 0.56, 0.84, 0.05, wood, 62)
		Kit.stroke(deck, ink, 2)
		for i = 0, 4 do
			box(parent, 0.12 + i * 0.18, 0.61, 0.025, 0.3, wood:Lerp(ink, 0.3), 61)
		end
		local hut = box(parent, 0.66, 0.36, 0.2, 0.2, Color3.fromRGB(245, 245, 250), 62)
		Kit.stroke(hut, ink, 2)
		box(parent, 0.64, 0.32, 0.24, 0.05, Color3.fromRGB(210, 60, 50), 63)
		local helm = box(parent, 0.3, 0.46, 0.1, 0.1, Color3.fromRGB(205, 160, 70), 64)
		Kit.round(helm, 200)
		Kit.stroke(helm, ink, 2)
		local port = box(helm, 0.5, 0.5, 0.5, 0.5, Color3.fromRGB(150, 210, 255), 65)
		port.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(port, 200)
	elseif kind == "salvage" then
		-- the sea floor: three rusty diving robots standing up out of the sand, eyes lighting one by one
		box(parent, 0, 0.82, 1, 0.18, Color3.fromRGB(170, 160, 130), 62)
		for i = 0, 2 do
			figure(parent, 0.22 + i * 0.28, Color3.fromRGB(140, 95, 65), true)
		end
		for i = 0, 5 do
			local bubble = box(
				parent,
				0.15 + i * 0.13,
				0.2 + (i % 3) * 0.08,
				0.025,
				0.04,
				Color3.fromRGB(200, 235, 255),
				65
			)
			Kit.round(bubble, 20)
		end
	elseif kind == "ghostship" then
		-- the ghost ship in the fog: a glowing green-blue hull and sails, and on its mast the little projector
		-- that makes it (the trick the Vigil expose)
		local glow = Color3.fromRGB(120, 255, 220)
		local hull = box(parent, 0.2, 0.52, 0.6, 0.14, glow, 62)
		hull.BackgroundTransparency = 0.35
		Kit.stroke(hull, glow, 2)
		box(parent, 0.49, 0.14, 0.02, 0.38, Color3.fromRGB(90, 70, 50), 62)
		for i = 0, 1 do
			local sail = box(parent, 0.3 + i * 0.22, 0.18 + i * 0.04, 0.16, 0.26, glow, 61)
			sail.BackgroundTransparency = 0.5
		end
		local lens = box(parent, 0.475, 0.1, 0.05, 0.05, Color3.fromRGB(255, 250, 200), 64)
		Kit.round(lens, 200)
		for i = 0, 3 do
			local fog = box(parent, i * 0.26, 0.64, 0.3, 0.08, Color3.fromRGB(220, 230, 240), 63)
			fog.BackgroundTransparency = 0.4
			Kit.round(fog, 40)
		end
	elseif kind == "seacave" then
		-- the sea cave's mouth over dark water, a treasure chest and gold on a rock shelf inside
		local rock = Color3.fromRGB(90, 85, 80)
		box(parent, 0, 0.1, 0.22, 0.9, rock, 62)
		box(parent, 0.78, 0.1, 0.22, 0.9, rock, 62)
		box(parent, 0, 0, 1, 0.16, rock, 62)
		box(parent, 0.2, 0.78, 0.6, 0.22, Color3.fromRGB(30, 70, 100), 62)
		local chest = box(parent, 0.4, 0.56, 0.2, 0.14, Color3.fromRGB(150, 100, 55), 63)
		Kit.stroke(chest, ink, 2)
		box(parent, 0.38, 0.5, 0.24, 0.07, Color3.fromRGB(130, 85, 45), 63)
		for i = 0, 4 do
			local coin = box(parent, 0.32 + i * 0.08, 0.7, 0.05, 0.04, Color3.fromRGB(255, 215, 80), 64)
			Kit.round(coin, 20)
		end
	elseif kind == "crater" then
		-- the empty crater under a still sky, broken stubs at its rim
		local pit = box(parent, 0.5, 0.78, 0.8, 0.22, ink, 63)
		pit.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(pit, 200)
		for i = 0, 3 do
			box(parent, 0.05 + i * 0.27, 0.6, 0.05, 0.12, ground:Lerp(ink, 0.5), 62)
		end
	end
end

local function buildPage()
	page = Kit.screen("ComicPage", 46)
	page.Enabled = false
	pageRoot = Kit.frame({
		Name = "Page",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(C.comic.ink),
		round = false,
		ZIndex = 60,
	})
	pageRoot.Parent = page
	pageTitle = Kit.label({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.015),
		Size = UDim2.fromScale(0.9, 0.08),
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0,
		maxText = 44,
		ZIndex = 66,
	})
	pageTitle.Parent = pageRoot
end

-- Show a page: its panels are built the first time and kept (pooled), hidden until each one's moment
local function openPage(id: string)
	local def = C.comic.pages[id]
	if not def then
		return
	end
	for _, f in panels do
		f.Visible = false
	end
	pageTitle.Text = def.title
	local have = built[id]
	if have then
		panels = have
		for _, f in panels do
			f.Visible = false
		end
		pageOn = { id = id, def = def, shown = 0 }
		page.Enabled = true
		return
	end
	panels = {}
	built[id] = panels
	local ink = rgb(C.comic.ink)
	for i, p in def.panels do
		local r = p.rect
		local f = Kit.frame({
			Name = "Panel" .. i,
			Position = UDim2.fromScale(r[1], r[2]),
			Size = UDim2.fromScale(r[3], r[4]),
			BackgroundColor3 = rgb(C.comic.paper),
			ClipsDescendants = true,
			round = false,
			Visible = false,
			ZIndex = 61,
		})
		Kit.stroke(f, ink, 5)
		picture(f, p)
		local cap = Kit.label({
			Name = "Caption",
			Text = p.caption,
			Position = UDim2.fromScale(0.03, 0.04),
			Size = UDim2.fromScale(0.7, 0.2),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(255, 236, 150),
			Font = Kit.bodyFont,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			maxText = 18,
			ZIndex = 67,
		})
		Kit.stroke(cap, ink, 2)
		cap.Parent = f
		if p.word then
			local w = Kit.label({
				Name = "Word",
				Text = p.word,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.72, 0.5),
				Size = UDim2.fromScale(0.45, 0.3),
				Rotation = -10,
				TextColor3 = Kit.color.gold,
				TextStrokeTransparency = 0,
				maxText = 60,
				ZIndex = 68,
			})
			w.Parent = f
		end
		f.Parent = pageRoot
		table.insert(panels, f)
	end
	pageOn = { id = id, def = def, shown = 0 }
	page.Enabled = true
end

local function closePage()
	if pageOn then
		pageOn = nil
		page.Enabled = false
	end
end

local function pageFrame(t: number)
	local on = pageOn
	if not on then
		return
	end
	for i, p in on.def.panels do
		local f = panels[i]
		if f and t >= p.at and not f.Visible then
			-- the panel slides in from below with a small bounce
			local r = p.rect
			f.Visible = true
			f.Position = UDim2.fromScale(r[1], r[2] + 0.06)
			TweenService:Create(
				f,
				TweenInfo.new(C.comic.panelIn, Enum.EasingStyle.Back),
				{ Position = UDim2.fromScale(r[1], r[2]) }
			):Play()
		end
	end
end

---------------------------------------------------------------------------
-- A boss's name card
---------------------------------------------------------------------------

local function buildCard()
	card = Kit.frame({
		Name = "NameCard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.32),
		Size = UDim2.fromScale(0.5, 0.16),
		BackgroundColor3 = Kit.color.night,
		round = false,
		Visible = false,
		ZIndex = 20,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(520, 150)
	lim.Parent = card
	Kit.stroke(card, Kit.color.gold, 3)
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	cardSlash = Kit.frame({
		Name = "Slash",
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.06),
		BackgroundColor3 = Color3.fromRGB(235, 70, 70),
		round = false,
		ZIndex = 21,
	})
	cardSlash.Parent = card
	cardName = Kit.label({
		Name = "Name",
		Position = UDim2.fromScale(0.04, 0.06),
		Size = UDim2.fromScale(0.92, 0.52),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 54,
		ZIndex = 22,
	})
	cardName.Parent = card
	cardTitle = Kit.label({
		Name = "Title",
		Position = UDim2.fromScale(0.04, 0.68),
		Size = UDim2.fromScale(0.92, 0.28),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 26,
		ZIndex = 22,
	})
	cardTitle.Parent = card
	card.Parent = gui
end

-- Show a boss's name card (3 s): the card slams in big and settles; the slash bar sweeps across in the boss's look
-- colour (Config.BossArt theme; red for the battle form and side quest villains). A side quest
-- finale (lore step 10) passes its mini villain's fixed name and title from Config.SideQuests instead.
function CinemaHud.nameCard(bossId: string, ownName: string?, ownTitle: string?)
	local name, title = CinemaPlan.nameCard(Config, bossId)
	if ownName then
		name, title = ownName, ownTitle or ""
	end
	local art = Config.BossArt[bossId]
	CinemaHud.card(name, title, if ownName then nil else art and art.theme)
end

-- Any card in the boss card's style (lore step 9: the Crater's and Your double's, Config.Cinema.nameCard places
-- and events): two fixed lines and the slash colour ({ r, g, b }, red when nil)
function CinemaHud.card(name: string, title: string, theme: { number }?)
	cardName.Text = name
	cardTitle.Text = title
	cardSlash.BackgroundColor3 = if theme
		then Color3.fromRGB(theme[1], theme[2], theme[3])
		else Color3.fromRGB(235, 70, 70)
	card.Visible = true
	cardScale.Scale = 1.5
	TweenService:Create(cardScale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	cardSlash.Size = UDim2.fromScale(0, 0.06)
	TweenService:Create(cardSlash, TweenInfo.new(0.35), { Size = UDim2.fromScale(1, 0.06) }):Play()
	cardUntil = os.clock() + C.nameCard.seconds
end

---------------------------------------------------------------------------
-- The finisher's screen (pooled)
---------------------------------------------------------------------------

local function buildOver()
	over = Kit.screen("Finisher", 9)
	white = Kit.frame({
		Name = "White",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		round = false,
		ZIndex = 1,
	})
	white.Parent = over
	for i = 1, C.finisher.anime.lines do
		local l = Kit.frame({
			Name = "Line" .. i,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.9, 0, 0, 3),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.15,
			round = false,
			Visible = false,
			ZIndex = 2,
		})
		l.Rotation = (i / C.finisher.anime.lines) * 360
		l.Parent = over
		table.insert(lines, l)
	end
	word = Kit.label({
		Name = "Word",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.7, 0.2),
		Rotation = -8,
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0,
		Visible = false,
		maxText = 120,
		ZIndex = 3,
	})
	wordScale = Instance.new("UIScale")
	wordScale.Parent = word
	word.Parent = over
end

-- The finisher on screen: plan is CinemaPlan.finisher's; text the impact word (Comic)
function CinemaHud.finisher(plan: CinemaPlan.Finisher, text: string)
	local now = os.clock()
	if plan.flash > 0 then
		white.BackgroundTransparency = 1 - plan.flash * Kit.flash()
		TweenService:Create(white, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end
	if plan.word then
		word.Text = text
		word.Visible = true
		word.TextTransparency = 0
		word.TextStrokeTransparency = 0
		wordScale.Scale = 2.2
		TweenService:Create(wordScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local hold = C.finisher.comic.wordSeconds
			* (if plan.hitStop > 0 or plan.seconds >= 0.8 then 1 else 0.6)
		task.delay(hold, function()
			TweenService
				:Create(word, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 })
				:Play()
		end)
	end
	if plan.lines > 0 then
		-- speed lines toward the centre (still, no flicker), the first `lines` of the pool
		for i, l in lines do
			l.Visible = i <= plan.lines
			l.Size = UDim2.new(0.9, 0, 0, if i % 3 == 0 then 5 else 2)
		end
		linesUntil = now
			+ C.finisher.anime.lineSeconds * (if plan.lines >= C.finisher.anime.lines then 1 else 0.6)
	end
	if plan.freeze > 0 then
		-- the freeze frame: the picture goes pale and inked for a moment
		local cc = tint
		if not cc then
			local made = Instance.new("ColorCorrectionEffect")
			made.Name = "FinisherFreeze"
			made.Parent = Lighting
			tint = made
			cc = made
		end
		local c = cc :: ColorCorrectionEffect
		c.Enabled = true
		c.Saturation = -0.6
		c.Contrast = 0.25
		task.delay(plan.freeze, function()
			c.Enabled = false
		end)
	end
end

-- The Dev panel: a comic page now (as a device-started scene: safe moments only)
function CinemaHud.showPage(id: string)
	openPage(id)
end

---------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------

local lastScene: any = nil
local function frame()
	local now = os.clock()
	local s = CinemaClient.current
	setBars(CinemaClient.letterboxed())
	skip.Visible = s ~= nil and CinemaClient.skippable()
	-- a device-started scene's lines go to the guide line box
	if s and s.lines then
		GuideHud.timeline(s, s.lines, CinemaClient.time())
	elseif lastScene and lastScene.lines then
		GuideHud.timeline(nil, nil, 0)
	end
	-- a comic page plays as a scene
	if s and s.comic then
		if not pageOn or pageOn.id ~= s.comic then
			openPage(s.comic)
		end
		pageFrame(CinemaClient.time())
	elseif pageOn then
		closePage()
	end
	lastScene = s
	if card.Visible and now >= cardUntil then
		card.Visible = false
	end
	if linesUntil > 0 and now >= linesUntil then
		linesUntil = 0
		for _, l in lines do
			l.Visible = false
		end
	end
	if barsOn == false then
		for _, b in bars do
			if b.Visible and b.Size.Y.Scale <= 0.001 then
				b.Visible = false
			end
		end
	end
end

function CinemaHud.init()
	gui = Kit.screen("CinemaHud", 6)
	buildBars()
	buildCard()
	buildPage()
	buildOver()
	-- the comic page's SKIP rides above the page
	CinemaClient.Changed:Connect(function(scene)
		skip.Parent = if scene and scene.comic then page else gui
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("CinemaHud", frame))
end

return CinemaHud
