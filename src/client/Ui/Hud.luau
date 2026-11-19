-- Hud: the main HUD (spec: Screens and UI > Main HUD): health bar with the shield on top, stamina ring, the
-- basic, 4 skill buttons and the super with cooldown sweeps (coloured by power set), the Awakening meter and
-- its button, active buffs, the movement buttons (Leap, Fly, Boost, Down), the shield button with its Guard
-- ring (H1, hold to block), a crosshair that pops on a
-- confirmed hit, the level, class, power set and gear score, the Renown bar with the next unlock, the
-- wallet, a GADGET button when one is worn, and POWERS, GEAR, MAP, JOURNAL, SHOP and EMOTE buttons for those screens. Phone first: 56 px buttons, a 16 px safe area, and the
-- bottom 80 px on the right left clear for the flight pad. Buttons carry only verbs (spec: first 30 seconds).
-- On PC and gamepad the same buttons show their key; they are drawn smaller.
-- PLACEHOLDER look until the UI pass (M10): the radar, world clock and boss countdown arrive with their
-- systems (M4, M6).
-- Phone pass (overhaul step 8): every button's place and size comes from Shared.TouchLayout for the screen
-- (sized to fit under the top row, out of the move stick's zone, the Button size setting on top); the
-- screen buttons go in Kit's top row (MORE holds what does not fit on a phone); held skill buttons aim by
-- dragging and show their charge; cooldowns show the seconds left; controllers see their button names.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")

local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Progress = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progress"))
local TouchLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TouchLayout"))
local ChargeRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChargeRules"))
local WeaponRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponRules"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local CombatClient = require(script.Parent.Parent.Controllers.CombatClient)
local GadgetClient = require(script.Parent.Parent.Controllers.GadgetClient)
local BlockClient = require(script.Parent.Parent.Controllers.BlockClient)
local LockClient = require(script.Parent.Parent.Controllers.LockClient)

local Hud = {}

local player = Players.LocalPlayer
local U = Config.Ui
local A = Config.Abilities.list

local gui: ScreenGui
local healthFill: Frame
local healthText: TextLabel
local staminaDots: { Frame } = {}
local guardDots: { Frame } = {} -- H1: the Guard ring round the shield button
local infoText: TextLabel
local crosshair: Frame
type Entry = {
	button: TextButton,
	sweep: Frame?,
	hint: TextLabel,
	pad: UIPadding,
	corner: UICorner,
	cooldown: TextLabel,
	charge: UIStroke,
	caption: TextLabel, -- the short name under an icon (gap-icons: the icon replaces the button's text)
}
local buttons: { [string]: Entry } = {}
local statusCard: Frame
-- the buttons a held touch aims with (drag to turn the camera)
local AIMS = { Basic = true, Skill1 = true, Skill2 = true, Skill3 = true, Skill4 = true, Super = true }
local holdStart: { [string]: number } = {} -- when each held skill went down (the charge ring)
local shieldFill: Frame
local meterFill: Frame
local meterText: TextLabel
local meterBar: Frame -- the Awakening meter's track (shown once it holds any charge)
local renownBar: Frame
local keyLine: TextLabel -- mouse and keyboard: the movement keys as one line (Config.Ui.dock.keyLine)
local keyMode = false -- the device is mouse and keyboard
local buffRow: Frame
local renownFill: Frame
local renownText: TextLabel
local walletText: TextLabel
local cluster: Frame
local stickRing: Frame
local stickKnob: Frame
local mirrored = false
local SLOT_ACTIONS = { "Skill1", "Skill2", "Skill3", "Skill4" }
local fitCard: () -> ()
local layout: () -> ()
local applyDevice: (device: string) -> ()
local ShortName: { [string]: string } = {}
for id, row in A do
	-- the verb on the button: the ability's first word, or its second for "Ice", "Arc" and the like
	local words = string.split(row.name, " ")
	local w = words[1]
	if #words > 1 and #w <= 3 then
		w = words[2]
	end
	ShortName[id] = string.upper(w)
end

-- A hold button feeding an input action. Touch and mouse both press it.
local function actionButton(
	parent: Instance,
	action: string,
	text: string,
	size: number,
	pos: UDim2,
	color: Color3
): TextButton
	local b = Instance.new("TextButton")
	b.Name = action
	b.AutoButtonColor = false
	b.Text = text
	b.Font = Kit.font
	b.TextScaled = true
	b.TextColor3 = Kit.color.ink
	b.BackgroundColor3 = color
	b.Size = UDim2.fromOffset(size, size)
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	Kit.round(b, size // 2)
	-- the comic ink: a heavy outline; a cluster button also gets its round drop shadow (below)
	Kit.ink(b)
	Kit.stroke(b, Kit.color.ink, if parent == cluster then 4 else 3)
	local corner = b:FindFirstChildOfClass("UICorner") :: UICorner
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	-- the charge ring: thickens while a chargeable skill is held (Shared.ChargeRules)
	local charge = Instance.new("UIStroke")
	charge.Name = "Charge"
	charge.Color = Kit.color.gold
	charge.Thickness = 0
	charge.Enabled = false
	charge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	charge.Parent = b
	-- seconds left on the cooldown, big and outlined so it reads over the sweep
	local cooldown = Kit.label({
		Name = "Cooldown",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0,
		ZIndex = 4,
		maxText = 40,
	})
	cooldown.Parent = b
	local sweep = Instance.new("Frame")
	sweep.Name = "Sweep"
	sweep.BackgroundColor3 = Color3.new(0, 0, 0)
	sweep.BackgroundTransparency = 0.45
	sweep.BorderSizePixel = 0
	sweep.AnchorPoint = Vector2.new(0, 1)
	sweep.Position = UDim2.new(0, -6, 1, 10)
	sweep.Size = UDim2.new(1, 12, 0, 0)
	sweep.ZIndex = 2
	sweep.Parent = b
	Kit.round(sweep, size // 2)
	local hint = Kit.label({
		Name = "Hint",
		Text = InputController.hints[action] or "",
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, 12),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	hint.Parent = b
	-- the short name as a small caption across the icon's foot (shown only while an icon is shown)
	local caption = Kit.label({
		Name = "Caption",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(1, 16, 0, 13),
		Position = UDim2.new(0.5, 0, 1, 12),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0,
		Visible = false,
		ZIndex = 5,
		maxText = 12,
	})
	caption.Parent = b
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			InputController.set(action, true)
			if t == Enum.UserInputType.Touch then
				-- let go wherever the finger lifts; a held skill aims by dragging its button
				InputController.holdTouch(input, action, AIMS[action] == true)
			else
				InputController.holdMouse(action) -- let go wherever the mouse button comes up
			end
			Kit.bounce(b)
		end
	end)
	b.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			InputController.set(action, false)
		end
	end)
	b.Parent = parent
	if parent == cluster then
		Kit.discInk(b, action == "Super") -- its round shadow (Super: its starburst)
	end
	buttons[action] = {
		button = b,
		sweep = sweep,
		hint = hint,
		pad = pad,
		corner = corner,
		cooldown = cooldown,
		charge = charge,
		caption = caption,
	}
	return b
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function buildTopLeft()
	-- the comic status card (2026-11-18): cream paper with halftone, ink lettering, leaning a little
	local card = Kit.frame({
		Name = "Status",
		Size = UDim2.fromOffset(250, 104),
		Position = UDim2.fromOffset(U.safe, U.safe),
		BackgroundColor3 = Kit.color.paper,
		Rotation = -U.ink.tilt * 0.7,
	})
	infoText = Kit.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.ink,
		maxText = 20,
	})
	infoText.Parent = card
	local BAR = Color3.fromRGB(43, 43, 43) -- a bar's empty track
	local back = Kit.frame({
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 28),
		BackgroundColor3 = BAR,
	})
	back.Parent = card
	healthFill = Kit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(U.colors.health),
		ClipsDescendants = true,
	})
	healthFill.Parent = back
	-- chunky comic stripes along the health fill (cut off where the fill ends)
	for i = 0, 15 do
		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.BackgroundColor3 = Color3.new(0, 0, 0)
		stripe.BackgroundTransparency = 0.82 -- a darker band of whatever the fill's colour is (low health too)
		stripe.BorderSizePixel = 0
		stripe.Position = UDim2.fromOffset(i * 20 + 10, 0)
		stripe.Size = UDim2.new(0, 10, 1, 0)
		stripe.Parent = healthFill
	end
	shieldFill = Kit.frame({
		Name = "Shield",
		Size = UDim2.fromScale(0, 0.4),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.fromRGB(170, 225, 255),
		ZIndex = 2,
		ink = false,
	})
	shieldFill.Parent = back
	healthText = Kit.label({
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.4,
		Font = Kit.bodyFont,
		ZIndex = 3,
		maxText = 14,
	})
	healthText.Parent = back
	local stam = Kit.frame({
		Name = "StaminaBar",
		Size = UDim2.new(1, -16, 0, 8),
		Position = UDim2.fromOffset(8, 50),
		BackgroundColor3 = BAR,
	})
	stam.Parent = card
	local fill =
		Kit.frame({ Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(U.colors.stamina) })
	fill.Parent = stam
	-- the Awakening meter
	local meter = Kit.frame({
		Name = "Awakening",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.fromOffset(8, 64),
		BackgroundColor3 = BAR,
	})
	meter.Parent = card
	meterBar = meter
	meterFill = Kit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 220, 90) })
	meterFill.Parent = meter
	meterText = Kit.label({
		Text = "AWAKENING",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		ZIndex = 3,
		maxText = 11,
	})
	meterText.Parent = meter
	-- the Renown bar: progress to the next level and what it unlocks
	local renown = Kit.frame({
		Name = "Renown",
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 82),
		BackgroundColor3 = BAR,
	})
	renown.Parent = card
	renownBar = renown
	renownFill = Kit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(150, 120, 255) })
	renownFill.Parent = renown
	renownText = Kit.label({
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		ZIndex = 3,
		maxText = 11,
	})
	renownText.Parent = renown
	card.Parent = gui
	statusCard = card
	buffRow = Instance.new("Frame")
	buffRow.Name = "Buffs"
	buffRow.BackgroundTransparency = 1
	buffRow.Size = UDim2.fromOffset(250, 22)
	buffRow.Position = UDim2.fromOffset(U.safe, U.safe + 110)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)
	layout.Parent = buffRow
	buffRow.Parent = gui
	return fill
end

local function buildCrosshair()
	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.45)
	crosshair.Size = UDim2.fromOffset(14, 14)
	crosshair.BackgroundTransparency = 1
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.new(1, 1, 1)
	ring.Thickness = 2
	ring.Transparency = 0.2
	ring.Parent = crosshair
	Kit.round(crosshair, 7)
	local scale = Instance.new("UIScale")
	scale.Parent = crosshair
	crosshair.Parent = gui
end

-- Stamina ring: 24 dots around the Boost button
local function buildStaminaRing(around: GuiObject)
	local n = 24
	local r = around.Size.X.Offset / 2 + 8
	for i = 1, n do
		local ang = (i - 1) / n * math.pi * 2 - math.pi / 2
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(5, 5)
		d.Position = UDim2.new(0.5, math.cos(ang) * r, 0.5, math.sin(ang) * r)
		d.BackgroundColor3 = rgb(U.colors.stamina)
		d.BorderSizePixel = 0
		Kit.round(d, 3)
		d.Parent = around
		table.insert(staminaDots, d)
	end
end

-- H1: the Guard ring, 16 dots round the shield button (blue; orange while staggered)
local function buildGuardRing(around: GuiObject)
	local n = 16
	local r = around.Size.X.Offset / 2 + 7
	for i = 1, n do
		local ang = (i - 1) / n * math.pi * 2 - math.pi / 2
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(5, 5)
		d.Position = UDim2.new(0.5, math.cos(ang) * r, 0.5, math.sin(ang) * r)
		d.BackgroundColor3 = Color3.fromRGB(150, 205, 255)
		d.BorderSizePixel = 0
		Kit.round(d, 3)
		d.Parent = around
		table.insert(guardDots, d)
	end
end

-- The top row's order (lower stays in the row longest; Radar docks PING 5 and SQUAD 8, PvpHud PVP 6,
-- PhotoMode PHOTO 10)
local DOCK_ORDER = { Loadout = 1, Gear = 2, Map = 3, Shop = 4, Journal = 7, Emote = 9 }

local function buildCluster()
	cluster = Instance.new("Frame")
	cluster.Name = "Cluster"
	cluster.BackgroundTransparency = 1
	cluster.AnchorPoint = Vector2.new(1, 1)
	cluster.Size = UDim2.fromOffset(300, 300)
	cluster.Position = UDim2.new(1, -U.safe, 1, -96) -- the bottom 80 px stay clear for the flight pad
	cluster.Parent = gui
	local big = U.touchTarget + 24
	local s = U.touchTarget
	cluster.Size = UDim2.fromOffset(320, 320)
	local volt = rgb(U.colors.volt)
	local gold = Kit.color.gold
	-- powers around the big basic button; movement in a column to their left
	actionButton(cluster, "Basic", "ZAP", big, UDim2.new(1, -big / 2 - 4, 1, -big / 2 - 4), volt)
	actionButton(cluster, "Skill1", "", s, UDim2.new(1, -big - s / 2 - 20, 1, -s / 2 - 4), volt)
	actionButton(cluster, "Skill2", "", s, UDim2.new(1, -big / 2 - 4, 1, -big - s / 2 - 22), volt)
	actionButton(cluster, "Skill3", "", s, UDim2.new(1, -big - s / 2 - 14, 1, -big - s / 2 - 12), volt)
	actionButton(cluster, "Skill4", "", s, UDim2.new(1, -big / 2 - 4, 1, -big - s * 1.5 - 40), volt)
	actionButton(
		cluster,
		"Super",
		"SUPER",
		s + 8,
		UDim2.new(1, -big - s / 2 - 14, 1, -big - s * 1.5 - 34),
		gold
	)
	actionButton(
		cluster,
		"Awaken",
		"AWAKEN",
		s,
		UDim2.new(1, -big - s * 1.5 - 48, 1, -big - s * 2 - 70), -- raised for the shield button (H1)
		Color3.fromRGB(255, 220, 90)
	)
	-- power or weapon (hero creator plan: keys 1 and 2 on PC, the left stick click on gamepads)
	actionButton(
		cluster,
		"Swap",
		"WEAPON",
		s - 8,
		UDim2.new(1, -big - s * 2.5 - 64, 1, -big - s * 1.5 - 34),
		Kit.color.paper
	)
	actionButton(cluster, "Leap", "LEAP", s, UDim2.new(1, -big - s * 1.5 - 48, 1, -s / 2 - 4), gold)
	actionButton(cluster, "Fly", "FLY", s, UDim2.new(1, -big - s * 1.5 - 48, 1, -s * 1.5 - 22), gold)
	local boost =
		actionButton(cluster, "Boost", "BOOST", s, UDim2.new(1, -big - s * 2.5 - 64, 1, -s * 1.5 - 22), gold)
	actionButton(cluster, "Down", "DOWN", s - 8, UDim2.new(1, -big - s * 2.5 - 64, 1, -s / 2 - 4), gold)
	buildStaminaRing(boost)
	-- H1 (spec: "a new shield button above the jump button"): hold to block, above LEAP and FLY
	local block = actionButton(
		cluster,
		"Block",
		"BLOCK",
		s - 6,
		UDim2.new(1, -big - s * 1.5 - 48, 1, -s * 2.5 - 44),
		Color3.fromRGB(110, 180, 255)
	)
	buildGuardRing(block)
	-- lock-on (nate's playtest 2026-11-19): tap LOCK to lock the target in front or let go, hold it for the next
	-- (LockClient); placed by TouchLayout between FLY and the skills
	actionButton(
		cluster,
		"Lock",
		"LOCK",
		s - 10,
		UDim2.new(1, -big - s * 1.5 - 48, 1, -s - 12),
		Color3.fromRGB(255, 120, 100)
	)
	-- gap-icons: the shield and Awakening buttons wear their comic icons (their text stays without one)
	for action, key in { Block = "Block", Awaken = "Awaken" } do
		local entry = buttons[action]
		if Kit.showIcon(entry.button, "action", key, nil) then
			entry.button.Text = ""
		end
	end
	-- the loadout screen
	local powers = actionButton(
		gui,
		"Loadout",
		"POWERS",
		s,
		UDim2.new(1, -U.safe - s / 2 - 70, 0, U.safe + s / 2),
		Kit.color.paper
	)
	powers.Size = UDim2.fromOffset(s + 30, s - 10)
	local gear = actionButton(
		gui,
		"Gear",
		"GEAR",
		s,
		UDim2.new(1, -U.safe - s * 1.5 - 116, 0, U.safe + s / 2),
		Kit.color.paper
	)
	gear.Size = UDim2.fromOffset(s + 20, s - 10)
	local map = actionButton(
		gui,
		"Map",
		"MAP",
		s,
		UDim2.new(1, -U.safe - s * 2.5 - 152, 0, U.safe + s / 2),
		Kit.color.paper
	)
	map.Size = UDim2.fromOffset(s + 10, s - 10)
	-- the Journal (story, side quests, reputation, story perks)
	local journal = actionButton(
		gui,
		"Journal",
		"JOURNAL",
		s,
		UDim2.new(1, -U.safe - s * 3.5 - 186, 0, U.safe + s / 2),
		Kit.color.paper
	)
	journal.Size = UDim2.fromOffset(s + 40, s - 10)
	-- M10: Settings (also on the main menu)
	local settings = Kit.button({
		Name = "SettingsButton",
		Text = "SETTINGS", -- in the MENU drawer (the declutter pass): a word reads better than a glyph there
		Size = UDim2.fromOffset(s - 10, s - 10),
		Position = UDim2.fromOffset(U.safe + 258, U.safe),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		Hud.OpenSettings:Fire()
	end)
	settings.Parent = gui
	-- M9: the Robux shop (looks only) and the emote picker
	local shop = actionButton(
		gui,
		"Shop",
		"SHOP",
		s,
		UDim2.new(1, -U.safe - s * 4.5 - 232, 0, U.safe + s / 2),
		Kit.color.gold
	)
	shop.Size = UDim2.fromOffset(s + 10, s - 10)
	local emote = actionButton(
		gui,
		"Emote",
		"EMOTE",
		s,
		UDim2.new(1, -U.safe - s * 5.5 - 262, 0, U.safe + s / 2),
		Kit.color.paper
	)
	emote.Size = UDim2.fromOffset(s + 20, s - 10)
	-- the opening's Catch verb (only shown while a story step asks for it)
	local catch = actionButton(
		cluster,
		"Catch",
		"CATCH",
		big,
		UDim2.new(1, -big * 1.5 - 30, 1, -big * 2 - 40),
		Kit.color.gold
	)
	catch.Visible = false
	walletText = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(260, 18),
		Position = UDim2.new(1, -U.safe - 70, 0, U.safe + s + 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.3,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	walletText.Parent = gui
	-- the gadget slot's active (shown when one is worn)
	actionButton(
		cluster,
		"Gadget",
		"GADGET",
		s - 8,
		UDim2.new(1, -big - s * 2.5 - 64, 1, -big - s * 1.5 - 34),
		Color3.fromRGB(170, 200, 255)
	)
	-- phone pass: the screen buttons join Kit's top row (other modules add PING, SQUAD, PVP and PHOTO)
	for action, order in DOCK_ORDER do
		local entry = buttons[action]
		if entry then
			-- in the MENU drawer its key hint hides (Kit sets InDrawer)
			entry.button:GetAttributeChangedSignal("InDrawer"):Connect(function()
				applyDevice(InputController.device)
			end)
			Kit.dock(entry.button, action, order)
		end
	end
	Kit.dock(settings, "Settings", 11)
end

-- gap-icons (2026-11-19): a button shows its comic icon (Config.Icons) instead of its text; with no uploaded
-- icon it keeps the text. caption: the short name under the icon (nil hides it).
local function showIcon(entry: Entry?, group: string?, key: any, text: string, caption: string?)
	if not entry then
		return
	end
	local on = Kit.showIcon(entry.button, group, key, nil)
	entry.button.Text = if on then "" else text
	entry.caption.Text = caption or ""
	entry.caption.Visible = on and caption ~= nil
end

-- gap-icons2 (2026-11-19): the movement buttons wear their comic icons (FLY the hero's mobility pick; LEAP,
-- BOOST and DOWN their own) with the changing word (LEAP, GLIDE, BOUNCE, LAND, SPRINT, POUND...) as the small
-- caption; text only while the sheets are not uploaded. Set only when something changed (it runs every frame).
local moveShown: { [string]: string } = {}
local function moveButton(action: string, group: string, key: any, text: string)
	local sig = group .. ":" .. tostring(key) .. ":" .. text
	if moveShown[action] == sig then
		return
	end
	moveShown[action] = sig
	showIcon(buttons[action], group, key, text, text)
end

local function refreshInfo()
	local h = State.hero
	infoText.Text = string.format(
		"LV %d  %s  %s  GS %d",
		h.level,
		string.upper(h.classId),
		string.upper(h.setId),
		h.gearScore or 0
	)
	-- Renown to the next level and what it unlocks
	if h.level >= Config.Stats.levelCap then
		renownFill.Size = UDim2.fromScale(1, 1)
		renownText.Text = "MAX LEVEL"
	else
		local need = Progress.xpToNext(Config, h.level)
		renownFill.Size = UDim2.fromScale(math.clamp((h.xp or 0) / need, 0, 1), 1)
		local at, what = Progress.nextUnlock(Config, h.level)
		renownText.Text = string.format("RENOWN %d / %d", h.xp or 0, need)
			.. (if at and what then string.format("  NEXT LV %d: %s", at, what) else "")
	end
	local gadget = buttons.Gadget
	if gadget then
		gadget.button.Visible = h.gadget ~= nil
		if h.gadget then
			showIcon(
				gadget,
				"gadget",
				h.gadget,
				string.upper(string.split(Config.Gear.gadgets[h.gadget].name, " ")[1])
			)
		end
	end
	-- what is held (key 1 the power, key 2 the weapon) decides what M1 and the four skills cast
	local kit = State.kit()
	local weaponColor = rgb(Config.Fx.weaponColor)
	local function paint(action: string, id: string?, locked: boolean?)
		local entry = buttons[action]
		if not entry then
			return
		end
		-- the declutter pass (2026-11-19): a slot that is empty or still locked draws nothing (the status card
		-- says what the next level unlocks)
		entry.button.Visible = id ~= nil and not locked
		local shown = id ~= nil and A[id] ~= nil and not locked and Kit.showAbility(entry.button, id)
		if not shown then
			Kit.showAbility(entry.button, nil)
		end
		entry.caption.Visible = shown
		entry.caption.Text = if shown and id then ShortName[id] else ""
		if id and A[id] then
			entry.button.Text = if locked then "LOCKED" elseif shown then "" else ShortName[id]
			local c = Config.Abilities.setColor[A[id].set]
			if action ~= "Super" then
				local col = if c then rgb(c) else weaponColor
				entry.button.BackgroundColor3 = if locked then Kit.color.muted else col
			end
		end
	end
	paint("Basic", kit.basic)
	for i, action in SLOT_ACTIONS do
		paint(action, kit.skills[i], kit.locked[i])
	end
	paint("Super", kit.super)
	local swap = buttons.Swap
	if swap then
		local w = WeaponRules.get(Config, h.weapon or 0)
		local swapText = if kit.weapon
			then "POWER"
			else string.upper(string.split(if w then w.name else "WEAPON", " ")[1])
		-- the swap shows what a tap takes up: the power's fist, or the carried weapon's silhouette
		if kit.weapon then
			showIcon(swap, "action", "Power", swapText)
		else
			showIcon(swap, "weapon", h.weapon or 0, swapText)
		end
		swap.button.Visible = WeaponRules.skillId(Config, h.weapon or 0, "M1") ~= nil
	end
end

local BUFF_NAMES = {
	shield = "SHIELD",
	mitigation = "BRACE",
	attackSpeed = "FAST",
	power = "MIGHT",
	speed = "SPEED",
	parry = "PARRY",
	resist = "RESIST",
}
local function refreshBuffs()
	for _, c in buffRow:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for kind, label in BUFF_NAMES do
		if State.buff(kind) > 0 then
			local t = Kit.label({
				Text = label,
				Size = UDim2.fromOffset(56, 20),
				BackgroundTransparency = 0.2,
				BackgroundColor3 = Kit.color.night,
				TextColor3 = Kit.color.gold,
				Font = Kit.bodyFont,
				maxText = 12,
			})
			Kit.round(t, 6)
			t.Parent = buffRow
		end
	end
end

applyDevice = function(device: string)
	local touch = device == "touch"
	local pad = device == "gamepad"
	for action, entry in buttons do
		-- key names for keyboards, button names for controllers (none for touch)
		local hint = if pad then InputController.padHints[action] else InputController.hints[action]
		entry.hint.Text = hint or ""
		entry.hint.Visible = not touch and hint ~= nil and entry.button:GetAttribute("InDrawer") ~= true
		entry.button.BackgroundTransparency = if touch then 0 else 0.15 -- comic: solid ink-lined buttons
	end
	-- the mouse aims, so the crosshair only shows for touch and gamepad aiming
	crosshair.Visible = device ~= "mouse"
	if keyMode ~= (device == "mouse") then
		keyMode = device == "mouse"
		layout()
	end
	Kit.setHudOpts({ touch = touch })
	Kit.padUi = pad -- an opened panel selects its first button for the D-pad (Kit.opening)
end

-- Story focus (the opening's first 3 minutes): only these verb buttons show and pulse, nothing else on the
-- HUD (spec: "The only words on screen are verb buttons"). nil shows the full HUD again.
local focus: { [string]: boolean }? = nil
local focusPulse = 0
function Hud.setFocus(actions: { string }?)
	if actions then
		local f = {}
		for _, a in actions do
			f[a] = true
		end
		focus = f
	else
		focus = nil
		for action, entry in buttons do
			entry.button.Visible = action ~= "Catch" -- Catch shows only when a story step asks for it
		end
	end
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Cluster" and not buttons[child.Name] then
			child.Visible = focus == nil
		end
	end
	Kit.dockShown(focus == nil) -- the top row too
	if not focus then
		refreshInfo()
		applyDevice(InputController.device)
	end
end

function Hud.focused(): boolean
	return focus ~= nil
end

local function applyFocus()
	local f = focus
	if not f then
		return
	end
	local now = os.clock()
	local beat = now - focusPulse > 0.9
	if beat then
		focusPulse = now
	end
	for action, entry in buttons do
		local on = f[action] == true
		entry.button.Visible = on
		if on and beat then
			Kit.pulse(entry.button, 0.25)
		end
	end
end

Hud.OpenSettings = Signal.new() -- the gear button (SettingsMenu listens)

-- A button's cooldown sweep at f (0 to 1): a dark fill rising over the whole button, padding included
local function setSweep(entry: Entry, f: number)
	local sweep = entry.sweep
	if not sweep then
		return
	end
	local p = entry.pad
	local px = p.PaddingLeft.Offset + p.PaddingRight.Offset
	local py = p.PaddingTop.Offset + p.PaddingBottom.Offset
	sweep.Position = UDim2.new(0, -p.PaddingLeft.Offset, 1, p.PaddingBottom.Offset)
	sweep.Size = UDim2.new(1, px, f, if f > 0 then py * f else 0)
end

-- The status card's height: the Awakening meter's row only while it holds a charge
local cardFull = Vector2.new(250, 104)
local meterShown = false
local METER_ROW = 18
fitCard = function()
	meterBar.Visible = meterShown
	renownBar.Position = UDim2.fromOffset(8, if meterShown then 82 else 82 - METER_ROW)
	statusCard.Size = UDim2.fromOffset(cardFull.X, cardFull.Y - (if meterShown then 0 else METER_ROW))
end

-- Place every action button and the display parts for this screen (Shared.TouchLayout): on rotation, a
-- resize, the device changing, left-handed and the Button size setting
layout = function()
	if not cluster then
		return
	end
	local a = Kit.area()
	local opts = Kit.hudOptions()
	opts.present = { Block = buttons.Block ~= nil }
	local placed = TouchLayout.cluster(Config, a.X, a.Y, opts :: any)
	if keyMode and placed.Block and placed.Leap then
		-- mouse and keyboard: no movement column (the key line), so the shield closes up beside the skills
		placed.Block = { x = placed.Leap.x, y = placed.Leap.y, size = placed.Block.size }
	end
	cluster.AnchorPoint = Vector2.zero
	cluster.Position = UDim2.new()
	cluster.Size = UDim2.fromScale(1, 1)
	for action, p in placed do
		local entry = buttons[action]
		if entry and entry.button.Parent == cluster then
			local size = math.floor(p.size + 0.5)
			local b = entry.button
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.fromOffset(math.floor(p.x + 0.5), math.floor(p.y + 0.5))
			b.Size = UDim2.fromOffset(size, size)
			entry.corner.CornerRadius = UDim.new(0, size // 2)
			local py, px = math.floor(size * 0.18), math.floor(size * 0.1)
			entry.pad.PaddingTop = UDim.new(0, py)
			entry.pad.PaddingBottom = UDim.new(0, py)
			entry.pad.PaddingLeft = UDim.new(0, px)
			entry.pad.PaddingRight = UDim.new(0, px)
			local sweepCorner = entry.sweep and entry.sweep:FindFirstChildOfClass("UICorner")
			if sweepCorner then
				sweepCorner.CornerRadius = UDim.new(0, size // 2)
			end
			setSweep(entry, 0)
			-- the key or pad hint sits in the top padding (below the button it would land on the next one)
			entry.hint.Position = UDim2.fromOffset(0, -py + 1)
			entry.hint.Size = UDim2.new(1, 0, 0, py + 3)
			entry.hint.ZIndex = b.ZIndex + 1
		end
	end
	-- the stamina dots ring the Boost button
	local boost = buttons.Boost
	if boost then
		local r = boost.button.Size.X.Offset / 2 + TouchLayout.RING * 0.8
		local n = #staminaDots
		for i, d in staminaDots do
			local ang = (i - 1) / n * math.pi * 2 - math.pi / 2
			d.Position = UDim2.new(0.5, math.cos(ang) * r, 0.5, math.sin(ang) * r)
		end
	end
	-- the display parts and the top row's span
	local hb = Kit.hudBoxes()
	statusCard.Position = UDim2.fromOffset(hb.status.x, hb.status.y)
	cardFull = Vector2.new(hb.status.w, hb.status.h)
	fitCard()
	buffRow.Position = UDim2.fromOffset(hb.buffs.x, hb.buffs.y)
	buffRow.Size = UDim2.fromOffset(hb.buffs.w, hb.buffs.h)
	walletText.AnchorPoint = Vector2.zero
	walletText.Position = UDim2.fromOffset(hb.wallet.x, hb.wallet.y)
	walletText.Size = UDim2.fromOffset(hb.wallet.w, hb.wallet.h)
	walletText.TextXAlignment = if hb.compact then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	Kit.dockSpan(hb.dockLo, hb.dockHi, hb.dockFromLo)
end
Hud.layout = layout

-- Left-handed layout (spec: "left-handed mirror"): the action cluster moves to the bottom left, every
-- button mirrored, so the right thumb gets the move stick (InputController.setStick); on a phone the
-- status corner moves right (TouchLayout.hud)
function Hud.setLeftHanded(on: boolean)
	if on == mirrored then
		return
	end
	mirrored = on
	Kit.setHudOpts({ leftHanded = on })
end

-- The right-side move stick's ring (left-handed and one-hand modes)
local function drawStick()
	local origin, vec = InputController.stickState()
	stickRing.Visible = origin ~= nil
	if origin then
		stickRing.Position = UDim2.fromOffset(origin.X, origin.Y)
		stickKnob.Position = UDim2.new(0.5 + vec.X * 0.5, 0, 0.5 + vec.Y * 0.5, 0)
	end
end

function Hud.init()
	gui = Kit.screen("Hud", 1)
	local stamFill = buildTopLeft()
	buildCrosshair()
	buildCluster()
	keyLine = Kit.label({
		Name = "KeyLine",
		Text = "",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(460, 18),
		Position = UDim2.new(1, -U.safe, 1, -6),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.2,
		Font = Kit.bodyFont,
		Visible = false,
		maxText = 13,
	})
	keyLine.Parent = gui
	stickRing = Kit.frame({
		Name = "StickRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(140, 140),
		BackgroundColor3 = Kit.color.paper,
		BackgroundTransparency = 0.75,
		Visible = false,
	})
	Kit.round(stickRing, 70)
	stickRing.Parent = gui
	stickKnob = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Kit.color.gold,
		BackgroundTransparency = 0.2,
	})
	Kit.round(stickKnob, 28)
	stickKnob.Parent = stickRing
	RunService.RenderStepped:Connect(FrameProf.wrap("Hud", drawStick))
	refreshInfo()
	applyDevice(InputController.device)
	layout()
	Kit.LayoutChanged:Connect(layout)
	InputController.Pressed:Connect(function(action)
		if AIMS[action] then
			holdStart[action] = os.clock()
		elseif action == "Menu" then
			-- gamepad Select: into the top row (and its drawer) for the D-pad, or back out
			local modal = Kit.modalButton() -- the main menu or the creator is up: Select goes into it
			if GuiService.SelectedObject and not modal then
				GuiService.SelectedObject = nil
				Kit.dockDrawer(false)
			elseif modal then
				if not GuiService.SelectedObject then
					GuiService.SelectedObject = modal
				end
			elseif not focus then
				GuiService.SelectedObject = Kit.dockSelect()
			end
		end
	end)
	InputController.Released:Connect(function(action)
		holdStart[action] = nil
	end)
	State.Changed:Connect(refreshInfo)
	State.StatusChanged:Connect(refreshBuffs)
	local function refreshWallet()
		local c = State.profile.currency or { credits = 0, banked = 0, dust = 0 }
		walletText.Text =
			string.format("CREDITS %s   DUST %s", Kit.comma(c.credits + c.banked), Kit.comma(c.dust))
	end
	State.ProfileChanged:Connect(refreshWallet)
	refreshWallet()
	local lastFull = false
	InputController.DeviceChanged:Connect(applyDevice)
	CombatClient.HitConfirm:Connect(function(crit)
		local scale = crosshair:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale = if crit then 1.8 else 1.4
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1 }):Play()
	end)
	local low = rgb(U.colors.healthLow)
	local ok = rgb(U.colors.health)
	RunService.RenderStepped:Connect(FrameProf.wrap("Hud", function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			local frac = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
			healthFill.Size = UDim2.fromScale(frac, 1)
			healthFill.BackgroundColor3 = if frac < 0.3 then low else ok
			healthText.Text = string.format("%d / %d", math.ceil(hum.Health), hum.MaxHealth)
		end
		local stam = MoveController.stamina / Config.Move.stamina.max
		stamFill.Size = UDim2.fromScale(stam, 1)
		local lit = math.floor(stam * #staminaDots + 0.5)
		for i, d in staminaDots do
			d.BackgroundTransparency = if i <= lit then 0 else 0.8
		end
		-- shield on the health bar
		local shield = State.buff("shield")
		local maxH = math.max(1, State.hero.maxHealth or 1)
		shieldFill.Size = UDim2.fromScale(math.clamp(shield / maxH, 0, 1), 0.4)
		-- Awakening meter and button
		local st = State.status
		local awake = State.awakened()
		local maxM = Config.Abilities.awakening.max
		if awake then
			local left = st.awakeUntil - os.clock()
			meterFill.Size = UDim2.fromScale(math.clamp(left / Config.Abilities.awakening.duration, 0, 1), 1)
			meterText.Text = string.format("AWAKENED %d", math.ceil(left))
		else
			meterFill.Size = UDim2.fromScale(math.clamp(st.meter / maxM, 0, 1), 1)
			meterText.Text = if st.meter >= maxM then "AWAKENING READY" else "AWAKENING"
		end
		-- the meter shows once it holds any charge; empty, the card closes up over it
		local meterOn = awake or st.meter > 0
		if meterOn ~= meterShown then
			meterShown = meterOn
			fitCard()
		end
		local full = st.meter >= maxM and not awake
		buttons.Awaken.button.Visible = full
		if full and not lastFull then
			Kit.pulse(buttons.Awaken.button, 0.3)
		end
		lastFull = full
		-- cooldown sweeps
		local kit = State.kit()
		local skills = kit.skills
		for action, id in
			{
				Basic = kit.basic,
				Skill1 = skills[1],
				Skill2 = skills[2],
				Skill3 = skills[3],
				Skill4 = skills[4],
				Super = kit.super,
			}
		do
			local entry = buttons[action]
			if entry and entry.sweep and id then
				local f = CombatClient.cooldownFraction(id)
				setSweep(entry, f)
				-- whole seconds left, shown from 1 s up (a basic's short cooldown stays a sweep)
				local left = if f > 0 then CombatClient.cooldownLeft(id) else 0
				entry.cooldown.Text = if left >= 1 then tostring(math.ceil(left)) else ""
				-- the charge ring while held (chargeable damaging skills only)
				local held = holdStart[action]
				local row = A[id]
				local level = if held
						and row
						and ChargeRules.chargeable(row)
					then ChargeRules.level(Config.Combat, os.clock() - held)
					else 0
				entry.charge.Enabled = level > 0
				entry.charge.Thickness = 2 + 4 * level
				entry.charge.Color = if level >= 1 then Color3.new(1, 1, 1) else Kit.color.gold
			elseif entry then
				entry.cooldown.Text = ""
				entry.charge.Enabled = false
			end
		end
		local gadget = buttons.Gadget
		if gadget and gadget.sweep then
			setSweep(gadget, GadgetClient.fraction())
		end
		local leap = buttons.Leap
		if leap and leap.sweep then
			setSweep(leap, 1 - MoveController.leapReady())
		end
		-- the movement buttons follow the hero's mobility and what they are doing (MoveController.labels)
		local labels = MoveController.labels()
		-- mouse and keyboard: the movement keys are one key line, not round buttons (the declutter pass)
		local keys = keyMode and focus == nil
		buttons.Fly.button.Visible = labels.fly ~= nil and not keys
		moveButton("Fly", "mobility", State.hero.mobility or "flight", labels.fly or "FLY")
		buttons.Boost.button.Visible = labels.boost ~= nil and not keys
		moveButton("Boost", "moveKey", "Boost", labels.boost or "BOOST")
		buttons.Down.button.Visible = labels.down ~= nil and not keys
		moveButton("Down", "moveKey", "Down", labels.down or "DOWN")
		moveButton("Leap", "moveKey", "Leap", labels.leap)
		buttons.Leap.button.Visible = not keys
		keyLine.Visible = keys
		if keys then
			local parts = {}
			for _, action in U.dock.keyLine do
				local label = (labels :: any)[string.lower(action)]
				local key = InputController.hints[action]
				if label and key then
					table.insert(parts, string.upper(key) .. " " .. label)
				end
			end
			local text = table.concat(parts, "   ")
			if keyLine.Text ~= text then
				keyLine.Text = text
			end
		end
		-- H1: the Guard ring, and the shield button lit while blocking
		local g = BlockClient.guard()
		local litG = math.floor(g * #guardDots + 0.5)
		local broken = BlockClient.broken()
		for i, d in guardDots do
			d.BackgroundTransparency = if i <= litG then 0 else 0.8
			d.BackgroundColor3 = if broken
				then Color3.fromRGB(255, 140, 60)
				else Color3.fromRGB(150, 205, 255)
		end
		-- H2: the charge ring fills on the held skill's button (charge-up powers fill gold, others blue)
		local heldId, level, charges = CombatClient.holdState()
		for _, action in SLOT_ACTIONS do
			local entry = buttons[action]
			if entry then
				local fill = entry.button:FindFirstChild("ChargeFill") :: Frame?
				local on = heldId ~= nil
					and charges
					and skills[table.find(SLOT_ACTIONS, action) or 0] == heldId
				if on and not fill then
					local f = Instance.new("Frame")
					f.Name = "ChargeFill"
					f.BorderSizePixel = 0
					f.AnchorPoint = Vector2.new(0, 1)
					f.Position = UDim2.new(0, -6, 1, 10)
					f.BackgroundTransparency = 0.35
					f.ZIndex = 3
					f.Parent = entry.button
					Kit.round(f, entry.button.Size.X.Offset // 2)
					fill = f
				end
				if fill then
					fill.Visible = on == true and level > 0
					if on then
						local row = heldId and A[heldId]
						local power = row ~= nil and row.charge ~= nil
						fill.Size = UDim2.new(1, 12, level, if level > 0 then 20 * level else 0)
						fill.BackgroundColor3 = if level >= 1
							then Color3.fromRGB(255, 255, 255)
							elseif power then Color3.fromRGB(255, 210, 80)
							else Color3.fromRGB(140, 200, 255)
					end
				end
			end
		end
		-- lock-on: the LOCK button while the setting is on (PC uses middle mouse and Tab), lit while locked
		local lockBtn = buttons.Lock
		if lockBtn then
			lockBtn.button.Visible = LockClient.hardOn and not keys
			lockBtn.button.BackgroundColor3 = if LockClient.locked()
				then Color3.fromRGB(255, 70, 60)
				else Color3.fromRGB(255, 160, 140)
		end
		local blockBtn = buttons.Block
		if blockBtn then
			local blocking = BlockClient.blocking()
			blockBtn.button.BackgroundColor3 = if blocking
				then Color3.fromRGB(200, 235, 255)
				else Color3.fromRGB(110, 180, 255)
			local icon = blockBtn.button:FindFirstChild("Icon") :: ImageLabel?
			if icon then
				icon.ImageTransparency = if blocking then 0.4 else 0 -- lit: the pale fill shows through
			end
		end
		applyFocus()
	end))
end

return Hud
