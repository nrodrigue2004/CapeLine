-- CinemaHud: the cinematic layer on screen (nate's lore, build plan step 7; Config.Cinema).
-- * The cutscene player's screen (CinemaClient): the letterbox bars sliding in and out, SKIP (once the scene
--   was seen on this save), and a device-started scene's subtitles fed to the guide line box (Ui.GuideHud).
-- * Comic-panel flashback pages: a full-screen page of 3 to 5 panels with ink borders, captions and sound
--   words, sliding in one by one. Each panel's picture is the comic art pass's rendered panel (Config.ComicArt,
--   Shared.ComicArt: the scene staged on Roblox's blocky bodies in game outfits, catalog faces and hair, inked
--   and cropped to the panel); a panel whose image is not uploaded yet is drawn from frames (a sky, a ground,
--   skyline blocks and simple figures; PLACEHOLDER ART fallback). One sample page: "The old heroes' last
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
local ComicArt = require(Shared:WaitForChild("ComicArt"))

local Kit = require(script.Parent.Kit)
local GuideHud = require(script.Parent.GuideHud)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local InputController = require(script.Parent.Parent.Controllers.InputController)

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
-- Comic-panel pages (the frame-drawn pictures below are the fallback until a panel's image is uploaded)
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
	elseif kind == "quarry" then
		-- the Old Quarry's stepped walls, the old mine lift's frame and a CLOSED sign on the gate (The Pit)
		local rock = Color3.fromRGB(150, 135, 115)
		for i = 0, 2 do
			box(parent, i * 0.1, 0.3 + i * 0.16, 0.12, 0.7 - i * 0.16, rock:Lerp(ink, i * 0.15), 62)
			box(parent, 0.88 - i * 0.1, 0.3 + i * 0.16, 0.12, 0.7 - i * 0.16, rock:Lerp(ink, i * 0.15), 62)
		end
		local frame = box(parent, 0.44, 0.34, 0.12, 0.44, Color3.fromRGB(110, 115, 125), 63)
		Kit.stroke(frame, ink, 2)
		box(parent, 0.47, 0.4, 0.06, 0.3, ink, 64)
		local sign = box(parent, 0.62, 0.56, 0.16, 0.08, Color3.fromRGB(200, 50, 45), 64)
		sign.Rotation = -8
		Kit.stroke(sign, ink, 2)
	elseif kind == "stone" then
		-- a fist turning to grey stone, cracks running up the arm
		figure(parent, 0.26, Color3.fromRGB(150, 60, 50), false)
		local fist = box(parent, 0.58, 0.36, 0.24, 0.24, Color3.fromRGB(150, 140, 130), 63)
		Kit.round(fist, 20)
		Kit.stroke(fist, ink, 3)
		box(parent, 0.42, 0.44, 0.18, 0.08, Color3.fromRGB(150, 140, 130), 62)
		for i = 0, 2 do
			local c = box(parent, 0.62 + i * 0.05, 0.4 + (i % 2) * 0.06, 0.02, 0.1, ink, 64)
			c.Rotation = if i % 2 == 0 then 25 else -25
		end
	elseif kind == "ring" then
		-- the fighting ring under a floodlight: canvas, red ropes, two fighters and the crowd's heads
		local canvas = box(parent, 0.14, 0.66, 0.72, 0.12, Color3.fromRGB(70, 90, 160), 62)
		Kit.stroke(canvas, ink, 2)
		for i = 0, 2 do
			box(parent, 0.14, 0.42 + i * 0.08, 0.72, 0.02, Color3.fromRGB(210, 50, 50), 64)
		end
		box(parent, 0.14, 0.38, 0.03, 0.3, Color3.fromRGB(200, 200, 210), 64)
		box(parent, 0.83, 0.38, 0.03, 0.3, Color3.fromRGB(200, 200, 210), 64)
		figure(parent, 0.36, Color3.fromRGB(150, 140, 130), false)
		figure(parent, 0.6, Color3.fromRGB(255, 150, 60), false)
		local lamp = box(parent, 0.44, 0.04, 0.12, 0.06, Color3.fromRGB(255, 240, 170), 63)
		Kit.round(lamp, 40)
		for i = 0, 6 do
			local h = box(parent, 0.04 + i * 0.14, 0.84, 0.07, 0.07, ink, 63)
			Kit.round(h, 200)
		end
	elseif kind == "velmara" then
		-- Velmara in the sun (The Sunken City): bronze towers with domed tops by a calm bay
		local bronze = Color3.fromRGB(205, 150, 80)
		box(parent, 0, 0.78, 1, 0.22, Color3.fromRGB(70, 150, 200), 62)
		for i = 0, 4 do
			local h = 0.22 + (i % 3) * 0.1
			local tower = box(parent, 0.08 + i * 0.18, 0.72 - h, 0.12, h, bronze, 63)
			Kit.stroke(tower, ink, 2)
			local dome = box(
				parent,
				0.08 + i * 0.18,
				0.72 - h - 0.06,
				0.12,
				0.1,
				bronze:Lerp(Color3.new(1, 1, 1), 0.3),
				63
			)
			Kit.round(dome, 200)
			Kit.stroke(dome, ink, 2)
		end
		local sun = box(parent, 0.82, 0.08, 0.12, 0.16, Color3.fromRGB(255, 230, 120), 62)
		Kit.round(sun, 200)
	elseif kind == "flood" then
		-- the great storm: a wave curling over the towers, rain streaks across the panel
		local bronze = Color3.fromRGB(150, 110, 60)
		for i = 0, 3 do
			local tower = box(parent, 0.12 + i * 0.22, 0.42, 0.1, 0.3, bronze, 62)
			Kit.stroke(tower, ink, 2)
		end
		local wave = box(parent, -0.1, 0.18, 0.9, 0.5, Color3.fromRGB(60, 140, 200), 63)
		Kit.round(wave, 200)
		Kit.stroke(wave, ink, 3)
		local foam = box(parent, 0.5, 0.18, 0.3, 0.12, Color3.fromRGB(230, 245, 255), 64)
		Kit.round(foam, 200)
		for i = 0, 5 do
			local rain = box(
				parent,
				0.1 + i * 0.15,
				0.04 + (i % 2) * 0.06,
				0.012,
				0.12,
				Color3.fromRGB(200, 220, 240),
				65
			)
			rain.Rotation = 20
		end
	elseif kind == "guardian" then
		-- the Tidewright on guard in the dark water: a tall bronze figure with glowing eyes and a trident
		local bronze = Color3.fromRGB(180, 130, 70)
		local glow = Color3.fromRGB(120, 255, 230)
		local body = box(parent, 0.42, 0.34, 0.16, 0.4, bronze, 63)
		Kit.stroke(body, ink, 2)
		local head = box(parent, 0.44, 0.18, 0.12, 0.14, bronze, 64)
		Kit.round(head, 60)
		Kit.stroke(head, ink, 2)
		for i = -1, 1, 2 do
			box(parent, 0.5 + i * 0.025 - 0.012, 0.23, 0.024, 0.03, glow, 65)
		end
		box(parent, 0.64, 0.12, 0.018, 0.62, Color3.fromRGB(90, 70, 50), 63)
		for i = -1, 1 do
			box(parent, 0.64 + i * 0.03 - 0.006, 0.08, 0.012, 0.08, glow, 64)
		end
		for i = 0, 6 do
			local bubble = box(
				parent,
				0.12 + i * 0.12,
				0.12 + (i % 3) * 0.12,
				0.025,
				0.04,
				Color3.fromRGB(200, 235, 255),
				65
			)
			Kit.round(bubble, 20)
		end
	elseif kind == "dredger" then
		-- a salvage dredger's drill punching into the reef, light spilling out of the crack it makes
		box(parent, 0, 0.78, 1, 0.22, Color3.fromRGB(170, 160, 130), 62)
		local hull = box(parent, 0.1, 0.04, 0.5, 0.12, Color3.fromRGB(230, 170, 40), 63)
		Kit.stroke(hull, ink, 2)
		box(parent, 0.33, 0.16, 0.03, 0.52, Color3.fromRGB(120, 120, 130), 63)
		local bit = box(parent, 0.315, 0.66, 0.06, 0.08, Color3.fromRGB(90, 90, 100), 64)
		bit.Rotation = 45
		local crack = box(parent, 0.3, 0.76, 0.4, 0.04, Color3.fromRGB(120, 255, 230), 64)
		Kit.round(crack, 40)
		for i = 0, 2 do
			local ray = box(parent, 0.36 + i * 0.1, 0.5, 0.02, 0.26, Color3.fromRGB(170, 255, 240), 63)
			ray.BackgroundTransparency = 0.4
			ray.Rotation = -20 + i * 20
		end
	elseif kind == "twostars" then
		-- two heroes flying side by side over the night skyline, a star over each (The Last Partner)
		for i = 0, 5 do
			local h = 0.18 + ((i * 29) % 4) * 0.05
			box(parent, i * 0.17, 0.72 - h, 0.14, h, ground:Lerp(ink, 0.4), 62)
		end
		figure(parent, 0.3, Color3.fromRGB(70, 110, 220), false)
		figure(parent, 0.56, Color3.fromRGB(200, 120, 230), false)
		for _, x in { 0.32, 0.58 } do
			local star = box(parent, x, 0.3, 0.05, 0.05, Color3.fromRGB(255, 235, 140), 64)
			star.Rotation = 45
			Kit.stroke(star, ink, 2)
		end
	elseif kind == "diner" then
		-- the Night Owl diner at night: a long front, a lit window, a booth and two coffee cups, a neon owl sign
		local front = box(parent, 0.08, 0.34, 0.84, 0.38, Color3.fromRGB(70, 60, 80), 62)
		Kit.stroke(front, ink, 2)
		local window = box(front, 0.06, 0.2, 0.62, 0.5, Color3.fromRGB(255, 220, 150), 63)
		Kit.stroke(window, ink, 2)
		box(window, 0.1, 0.62, 0.8, 0.12, Color3.fromRGB(190, 50, 60), 64)
		for i = 0, 1 do
			local cup = box(window, 0.36 + i * 0.18, 0.46, 0.08, 0.16, Color3.fromRGB(250, 250, 250), 65)
			Kit.stroke(cup, ink, 1)
		end
		box(front, 0.74, 0.3, 0.18, 0.7, Color3.fromRGB(120, 80, 60), 63)
		local sign = box(parent, 0.3, 0.2, 0.3, 0.1, Color3.fromRGB(120, 230, 255), 63)
		Kit.round(sign, 20)
		Kit.stroke(sign, ink, 2)
	elseif kind == "sisters" then
		-- a big sister and her kid brother on a rooftop under a radio aerial (Finding Lark)
		box(parent, 0, 0.66, 1, 0.06, ground:Lerp(ink, 0.3), 62)
		box(parent, 0.78, 0.2, 0.015, 0.46, Color3.fromRGB(160, 165, 175), 62)
		for i = 0, 2 do
			box(
				parent,
				0.74 + i * 0.02,
				0.24 + i * 0.07,
				0.09 - i * 0.02,
				0.012,
				Color3.fromRGB(160, 165, 175),
				62
			)
		end
		figure(parent, 0.34, Color3.fromRGB(240, 180, 60), false)
		local kid = box(parent, 0.5, 0.6, 0.05, 0.12, Color3.fromRGB(90, 200, 230), 64)
		Kit.stroke(kid, ink, 2)
		local head = box(parent, 0.505, 0.54, 0.04, 0.06, Color3.fromRGB(241, 194, 160), 64)
		Kit.round(head, 40)
		Kit.stroke(head, ink, 2)
	elseif kind == "van" then
		-- a boxy van with a dish or a net launcher on its roof (Finding Lark's net vans, The Scoop's news van)
		local body = box(parent, 0.16, 0.44, 0.62, 0.24, Color3.fromRGB(235, 235, 240), 63)
		Kit.stroke(body, ink, 2)
		local cab = box(parent, 0.78, 0.5, 0.12, 0.18, Color3.fromRGB(235, 235, 240), 63)
		Kit.stroke(cab, ink, 2)
		box(cab, 0.15, 0.1, 0.7, 0.4, Color3.fromRGB(150, 210, 255), 64)
		box(body, 0, 0.45, 1, 0.12, Color3.fromRGB(220, 60, 50), 64)
		for _, x in { 0.24, 0.66 } do
			local wheel = box(parent, x, 0.64, 0.1, 0.12, ink, 64)
			Kit.round(wheel, 200)
		end
		local dish = box(parent, 0.36, 0.34, 0.14, 0.1, Color3.fromRGB(200, 205, 215), 64)
		Kit.round(dish, 200)
		Kit.stroke(dish, ink, 2)
	elseif kind == "cage" then
		-- a row of cages in a warehouse, a collar glowing on the figure in each (Finding Lark's pound)
		for i = 0, 2 do
			local x = 0.08 + i * 0.3
			figure(parent, x + 0.08, Color3.fromRGB(200, 170, 150), false)
			box(parent, x + 0.07, 0.535, 0.08, 0.02, Color3.fromRGB(120, 230, 255), 65)
			for b = 0, 4 do
				box(parent, x + b * 0.06, 0.32, 0.012, 0.4, Color3.fromRGB(120, 125, 135), 66)
			end
			box(parent, x, 0.32, 0.25, 0.02, Color3.fromRGB(120, 125, 135), 66)
		end
	elseif kind == "garage" then
		-- an Old Town garage with its door half up, a tow truck and a flame painted on the sign (Hostile Takeover)
		local front = box(parent, 0.1, 0.3, 0.8, 0.42, Color3.fromRGB(150, 110, 90), 62)
		Kit.stroke(front, ink, 2)
		local door = box(front, 0.1, 0.4, 0.5, 0.6, Color3.fromRGB(110, 115, 125), 63)
		Kit.stroke(door, ink, 2)
		box(front, 0.1, 0.4, 0.5, 0.3, ink, 64)
		local sign = box(parent, 0.3, 0.18, 0.4, 0.1, Color3.fromRGB(40, 36, 40), 63)
		Kit.stroke(sign, ink, 2)
		local flame = box(sign, 0.4, 0.15, 0.2, 0.7, Color3.fromRGB(255, 120, 40), 64)
		Kit.round(flame, 40)
		local truck = box(parent, 0.66, 0.56, 0.2, 0.12, Color3.fromRGB(230, 70, 50), 64)
		Kit.stroke(truck, ink, 2)
	elseif kind == "club" then
		-- the Opal Room: red curtains, a small stage, a chandelier and the Duchess's booth (Hostile Takeover)
		for i = 0, 1 do
			box(parent, i * 0.82, 0, 0.18, 0.72, Color3.fromRGB(150, 30, 50), 62)
		end
		local stage = box(parent, 0.18, 0.58, 0.64, 0.14, Color3.fromRGB(110, 70, 40), 62)
		Kit.stroke(stage, ink, 2)
		local lamp = box(parent, 0.42, 0.06, 0.16, 0.1, Color3.fromRGB(255, 240, 190), 63)
		Kit.round(lamp, 40)
		Kit.stroke(lamp, ink, 2)
		figure(parent, 0.47, Color3.fromRGB(70, 50, 120), false)
		local pearl = box(parent, 0.475, 0.53, 0.04, 0.02, Color3.fromRGB(245, 240, 230), 65)
		Kit.round(pearl, 40)
	elseif kind == "tv" or kind == "blackout" then
		-- a TV set on a stand: a news anchor on it (tv), or a black screen cut mid-story (blackout: The Scoop)
		local set = box(parent, 0.22, 0.2, 0.56, 0.44, Color3.fromRGB(60, 56, 64), 62)
		Kit.round(set, 8)
		Kit.stroke(set, ink, 3)
		local screen = box(
			set,
			0.07,
			0.1,
			0.86,
			0.8,
			if kind == "tv" then Color3.fromRGB(120, 190, 255) else Color3.fromRGB(14, 14, 18),
			63
		)
		if kind == "tv" then
			box(screen, 0.4, 0.3, 0.2, 0.7, Color3.fromRGB(230, 70, 60), 64)
			local head = box(screen, 0.43, 0.08, 0.14, 0.24, Color3.fromRGB(224, 172, 130), 64)
			Kit.round(head, 40)
			box(screen, 0, 0.78, 1, 0.22, Color3.fromRGB(230, 60, 50), 65)
		else
			for i = 0, 2 do
				local bar =
					box(screen, 0.1 + i * 0.3, 0.2 + i * 0.2, 0.22, 0.04, Color3.fromRGB(90, 90, 100), 64)
				bar.BackgroundTransparency = 0.3
			end
		end
		box(parent, 0.47, 0.64, 0.06, 0.08, Color3.fromRGB(60, 56, 64), 62)
	elseif kind == "crater" then
		-- the empty crater under a still sky, broken stubs at its rim
		local pit = box(parent, 0.5, 0.78, 0.8, 0.22, ink, 63)
		pit.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(pit, 200)
		for i = 0, 3 do
			box(parent, 0.05 + i * 0.27, 0.6, 0.05, 0.12, ground:Lerp(ink, 0.5), 62)
		end
	-- The origin lines (lore step 11): one picture kind a panel, the same cartoon boxes as the rest
	elseif kind == "lab" then
		-- Ashgrove Labs: a white research block, rows of lit windows, a flask sign over the door
		local front = box(parent, 0.14, 0.26, 0.72, 0.46, Color3.fromRGB(235, 240, 245), 62)
		Kit.stroke(front, ink, 2)
		for r = 0, 2 do
			for i = 0, 4 do
				box(front, 0.06 + i * 0.19, 0.08 + r * 0.24, 0.12, 0.14, Color3.fromRGB(150, 230, 240), 63)
			end
		end
		box(front, 0.42, 0.78, 0.16, 0.22, Color3.fromRGB(60, 80, 110), 63)
		local flask = box(parent, 0.5, 0.2, 0.1, 0.1, Color3.fromRGB(80, 255, 255), 63)
		flask.AnchorPoint = Vector2.new(0.5, 0.5)
		flask.Rotation = 45
		Kit.stroke(flask, ink, 2)
	elseif kind == "kindler" then
		-- the Kindler: a figure in a ring of light, rays bursting out of it
		local ring = box(parent, 0.5, 0.5, 0.46, 0.66, Color3.fromRGB(80, 255, 255), 62)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.BackgroundTransparency = 0.6
		Kit.round(ring, 200)
		Kit.stroke(ring, Color3.fromRGB(200, 255, 255), 4)
		for i = 0, 5 do
			local ray = box(parent, 0.5, 0.5, 0.8, 0.025, Color3.fromRGB(230, 255, 255), 62)
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Rotation = i * 30
		end
		figure(parent, 0.47, Color3.fromRGB(255, 240, 160), false)
	elseif kind == "spark" then
		-- the one Spark: a row of different people, each with the same small light in the chest
		local cols = {
			Color3.fromRGB(70, 150, 255),
			Color3.fromRGB(150, 220, 120),
			Color3.fromRGB(235, 90, 90),
			Color3.fromRGB(190, 110, 240),
			Color3.fromRGB(255, 170, 60),
		}
		for i, c in cols do
			local x = 0.08 + (i - 1) * 0.18
			figure(parent, x, c, false)
			local glow = box(parent, x + 0.015, 0.6, 0.03, 0.05, Color3.fromRGB(255, 240, 140), 65)
			Kit.round(glow, 200)
			Kit.stroke(glow, Color3.fromRGB(255, 255, 230), 2)
		end
	elseif kind == "starfall" then
		-- a small ship falling out of a starry sky, a long bright tail behind it
		for i = 0, 9 do
			local star =
				box(parent, (i * 0.37) % 1, 0.04 + ((i * 0.23) % 0.5), 0.015, 0.025, Color3.new(1, 1, 1), 62)
			star.Rotation = 45
		end
		local tail = box(parent, 0.2, 0.18, 0.5, 0.05, Color3.fromRGB(255, 220, 150), 63)
		tail.Rotation = 35
		tail.BackgroundTransparency = 0.3
		local ship = box(parent, 0.6, 0.46, 0.14, 0.12, Color3.fromRGB(190, 200, 220), 64)
		ship.Rotation = 35
		Kit.round(ship, 40)
		Kit.stroke(ship, ink, 2)
	elseif kind == "seedship" then
		-- the pilot who stayed: a figure by the open pod in a field, a little house behind
		local pod = box(parent, 0.58, 0.5, 0.22, 0.22, Color3.fromRGB(190, 200, 220), 62)
		Kit.round(pod, 200)
		Kit.stroke(pod, ink, 2)
		box(pod, 0.3, 0.3, 0.4, 0.3, Color3.fromRGB(190, 90, 255), 63)
		figure(parent, 0.3, Color3.fromRGB(150, 110, 230), false)
		figure(parent, 0.4, Color3.fromRGB(255, 190, 120), false)
		local house = box(parent, 0.04, 0.5, 0.16, 0.22, Color3.fromRGB(230, 200, 160), 62)
		Kit.stroke(house, ink, 2)
	elseif kind == "radiomast" then
		-- Radio Hill's mast on its stepped hill at night, song rings rising off its tip
		for i = 0, 2 do
			box(
				parent,
				0.1 + i * 0.12,
				0.6 - i * 0.08,
				0.8 - i * 0.24,
				0.12 + i * 0.08,
				ground:Lerp(ink, 0.15 * i),
				62
			)
		end
		box(parent, 0.49, 0.12, 0.02, 0.36, Color3.fromRGB(200, 60, 60), 63)
		for i = 0, 2 do
			local ring = box(parent, 0.5, 0.12, 0.12 + i * 0.1, 0.06 + i * 0.05, Color3.new(1, 1, 1), 63)
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.BackgroundTransparency = 1
			Kit.round(ring, 200)
			Kit.stroke(ring, Color3.fromRGB(190, 90, 255), 2)
		end
	elseif kind == "stage" then
		-- a theatre stage: red curtains, a spotlight, a magician in a top hat
		for i = 0, 1 do
			local curtain = box(parent, i * 0.8, 0, 0.2, 0.72, Color3.fromRGB(170, 30, 45), 63)
			Kit.stroke(curtain, ink, 2)
		end
		box(parent, 0, 0, 1, 0.08, Color3.fromRGB(140, 25, 40), 63)
		local spot = box(parent, 0.5, 0.56, 0.36, 0.4, Color3.fromRGB(255, 245, 190), 62)
		spot.AnchorPoint = Vector2.new(0.5, 0.5)
		spot.BackgroundTransparency = 0.5
		Kit.round(spot, 200)
		figure(parent, 0.47, Color3.fromRGB(40, 40, 50), false)
		box(parent, 0.465, 0.38, 0.06, 0.08, Color3.fromRGB(24, 24, 28), 65)
	elseif kind == "relic" then
		-- the relic in an old hand: a glowing moonstone on a little stand, sparkles round it
		local stand = box(parent, 0.42, 0.56, 0.16, 0.16, Color3.fromRGB(180, 130, 70), 62)
		Kit.stroke(stand, ink, 2)
		local stone = box(parent, 0.5, 0.44, 0.16, 0.2, Color3.fromRGB(190, 200, 255), 63)
		stone.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(stone, 200)
		Kit.stroke(stone, Color3.fromRGB(255, 255, 255), 3)
		for i = 0, 5 do
			local a = i * math.pi / 3
			local s = box(
				parent,
				0.5 + math.cos(a) * 0.2,
				0.44 + math.sin(a) * 0.26,
				0.03,
				0.04,
				Color3.fromRGB(255, 240, 160),
				64
			)
			s.Rotation = 45
		end
	elseif kind == "tinkergarage" then
		-- Tinker Tess's garage: an open roll-up door, a workbench, a half-built suit on a stand
		local front = box(parent, 0.1, 0.22, 0.8, 0.5, Color3.fromRGB(200, 170, 130), 62)
		Kit.stroke(front, ink, 2)
		local door = box(front, 0.08, 0.2, 0.84, 0.8, Color3.fromRGB(60, 56, 54), 63)
		for i = 0, 2 do
			box(door, 0, 0.08 + i * 0.1, 1, 0.03, Color3.fromRGB(150, 145, 140), 64)
		end
		figure(parent, 0.6, Color3.fromRGB(150, 155, 165), true)
		box(parent, 0.2, 0.6, 0.24, 0.05, Color3.fromRGB(150, 100, 55), 65)
	elseif kind == "suitup" then
		-- the suit lighting up: a hero in a grey suit, a core glowing in its chest, rays out of it
		for i = 0, 5 do
			local ray = box(parent, 0.5, 0.6, 0.7, 0.02, Color3.fromRGB(120, 230, 255), 62)
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Rotation = i * 30
		end
		figure(parent, 0.47, Color3.fromRGB(150, 155, 165), false)
		local core = box(parent, 0.5, 0.62, 0.06, 0.08, Color3.fromRGB(120, 230, 255), 65)
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		Kit.round(core, 200)
		Kit.stroke(core, Color3.new(1, 1, 1), 2)
	elseif kind == "repo" then
		-- Clawback's tow truck: a yellow cab, its crane arm and a hook swinging down for a car
		local cab = box(parent, 0.06, 0.5, 0.24, 0.22, Color3.fromRGB(230, 190, 60), 63)
		Kit.stroke(cab, ink, 2)
		box(cab, 0.15, 0.12, 0.5, 0.35, Color3.fromRGB(150, 210, 255), 64)
		local bed = box(parent, 0.3, 0.6, 0.3, 0.12, Color3.fromRGB(80, 84, 92), 63)
		Kit.stroke(bed, ink, 2)
		local arm = box(parent, 0.42, 0.28, 0.36, 0.035, Color3.fromRGB(110, 115, 125), 63)
		arm.Rotation = -20
		box(parent, 0.74, 0.24, 0.008, 0.26, ink, 63)
		local hook = box(parent, 0.72, 0.48, 0.05, 0.06, Color3.fromRGB(150, 150, 160), 64)
		Kit.stroke(hook, ink, 2)
		for i = 0, 1 do
			local wheel = box(parent, 0.1 + i * 0.36, 0.68, 0.08, 0.1, ink, 64)
			Kit.round(wheel, 200)
		end
	elseif kind == "dojo" then
		-- the Willow Street Dojo: a low hall with a curved roof, a willow, a student in a white gi
		local hall = box(parent, 0.18, 0.4, 0.64, 0.32, Color3.fromRGB(240, 225, 200), 62)
		Kit.stroke(hall, ink, 2)
		local roof = box(parent, 0.12, 0.3, 0.76, 0.12, Color3.fromRGB(150, 40, 40), 63)
		Kit.round(roof, 40)
		Kit.stroke(roof, ink, 2)
		box(hall, 0.4, 0.4, 0.2, 0.6, Color3.fromRGB(120, 80, 50), 63)
		local willow = box(parent, 0.84, 0.2, 0.16, 0.5, Color3.fromRGB(110, 170, 80), 63)
		Kit.round(willow, 60)
		figure(parent, 0.3, Color3.fromRGB(245, 245, 245), false)
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
		local art = ComicArt.panel(Config, id, i)
		if art then
			-- the rendered panel, cropped to the panel's shape (the action sits in the middle of every render)
			local img = Instance.new("ImageLabel")
			img.Name = "Art"
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.ScaleType = Enum.ScaleType.Crop
			img.Image = art
			img.ZIndex = 62
			img.Parent = f
		else
			picture(f, p)
		end
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
	-- a controller cannot reach the button: B skips, and the button says so (onboarding check)
	skip.Text = if InputController.device == "gamepad" then "SKIP (B)" else "SKIP"
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
	-- gamepad B (the Down action, idle in a cutscene) presses SKIP while it shows
	InputController.Pressed:Connect(function(action)
		if action == "Down" and InputController.device == "gamepad" and skip.Visible then
			CinemaClient.skip()
		end
	end)
end

return CinemaHud
