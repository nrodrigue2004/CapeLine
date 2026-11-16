-- Hud: the main HUD (spec: Screens and UI > Main HUD): health bar with the shield on top, stamina ring, the
-- basic, 4 skill buttons and the super with cooldown sweeps (coloured by power set), the Awakening meter and
-- its button, active buffs, the movement buttons (Leap, Fly, Boost, Down), a crosshair that pops on a
-- confirmed hit, the level, class, power set and gear score, the Renown bar with the next unlock, the
-- wallet, a GADGET button when one is worn, and POWERS, GEAR, MAP, JOURNAL, SHOP and EMOTE buttons for those screens. Phone first: 56 px buttons, a 16 px safe area, and the
-- bottom 80 px on the right left clear for the flight pad. Buttons carry only verbs (spec: first 30 seconds).
-- On PC and gamepad the same buttons show their key; they are drawn smaller.
-- PLACEHOLDER look until the UI pass (M10): the radar, world clock and boss countdown arrive with their
-- systems (M4, M6).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Progress = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progress"))
local WeaponRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponRules"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local CombatClient = require(script.Parent.Parent.Controllers.CombatClient)
local GadgetClient = require(script.Parent.Parent.Controllers.GadgetClient)

local Hud = {}

local player = Players.LocalPlayer
local U = Config.Ui
local A = Config.Abilities.list

local gui: ScreenGui
local healthFill: Frame
local healthText: TextLabel
local staminaDots: { Frame } = {}
local infoText: TextLabel
local crosshair: Frame
local buttons: { [string]: { button: TextButton, sweep: Frame?, hint: TextLabel } } = {}
local shieldFill: Frame
local meterFill: Frame
local meterText: TextLabel
local buffRow: Frame
local renownFill: Frame
local renownText: TextLabel
local walletText: TextLabel
local cluster: Frame
local stickRing: Frame
local stickKnob: Frame
local mirrored = false
local original: { [GuiObject]: UDim2 } = {}
local SLOT_ACTIONS = { "Skill1", "Skill2", "Skill3", "Skill4" }
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
	Kit.stroke(b, Kit.color.ink, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
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
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			InputController.set(action, true)
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
	buttons[action] = { button = b, sweep = sweep, hint = hint }
	return b
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function buildTopLeft()
	local card = Kit.frame({
		Name = "Status",
		Size = UDim2.fromOffset(250, 104),
		Position = UDim2.fromOffset(U.safe, U.safe),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.25,
	})
	infoText = Kit.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		maxText = 20,
	})
	infoText.Parent = card
	local back = Kit.frame({
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.fromOffset(8, 28),
		BackgroundColor3 = Color3.fromRGB(40, 40, 50),
	})
	back.Parent = card
	healthFill = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(U.colors.health) })
	healthFill.Parent = back
	shieldFill = Kit.frame({
		Name = "Shield",
		Size = UDim2.fromScale(0, 0.4),
		Position = UDim2.fromScale(0, 0),
		BackgroundColor3 = Color3.fromRGB(170, 225, 255),
		ZIndex = 2,
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
		BackgroundColor3 = Color3.fromRGB(40, 40, 50),
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
		BackgroundColor3 = Color3.fromRGB(40, 36, 30),
	})
	meter.Parent = card
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
		BackgroundColor3 = Color3.fromRGB(30, 34, 50),
	})
	renown.Parent = card
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
		UDim2.new(1, -big - s * 1.5 - 48, 1, -big - s * 1.5 - 34),
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
	-- M10: Settings (a gear glyph; also on the main menu)
	local settings = Kit.button({
		Name = "SettingsButton",
		Text = "⚙",
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
		local at, what = Progress.nextUnlock(h.level)
		renownText.Text = string.format("RENOWN %d / %d", h.xp or 0, need)
			.. (if at and what then string.format("  NEXT LV %d: %s", at, what) else "")
	end
	local gadget = buttons.Gadget
	if gadget then
		gadget.button.Visible = h.gadget ~= nil
		if h.gadget then
			gadget.button.Text = string.upper(string.split(Config.Gear.gadgets[h.gadget].name, " ")[1])
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
		entry.button.Visible = id ~= nil
		if id and A[id] then
			entry.button.Text = if locked then "LOCKED" else ShortName[id]
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
		swap.button.Text = if kit.weapon
			then "POWER"
			else string.upper(string.split(if w then w.name else "WEAPON", " ")[1])
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

local function applyDevice(device: string)
	local touch = device == "touch"
	for _, entry in buttons do
		entry.hint.Visible = not touch
		entry.button.BackgroundTransparency = if touch then 0.1 else 0.35
	end
	-- the mouse aims, so the crosshair only shows for touch and gamepad aiming
	crosshair.Visible = device ~= "mouse"
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

-- Left-handed layout (spec: "left-handed mirror"): the action cluster moves to the bottom left, every
-- button mirrored inside it, so the right thumb gets the move stick (InputController.setStick)
function Hud.setLeftHanded(on: boolean)
	if on == mirrored or not cluster then
		return
	end
	mirrored = on
	cluster.AnchorPoint = if on then Vector2.new(0, 1) else Vector2.new(1, 1)
	cluster.Position = if on then UDim2.new(0, U.safe, 1, -96) else UDim2.new(1, -U.safe, 1, -96)
	for _, c in cluster:GetChildren() do
		if c:IsA("GuiObject") then
			if not original[c] then
				original[c] = c.Position
			end
			local p = original[c]
			c.Position = if on then UDim2.new(1 - p.X.Scale, -p.X.Offset, p.Y.Scale, p.Y.Offset) else p
		end
	end
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
	stickRing = Kit.frame({
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
				entry.sweep.Size = UDim2.new(1, 12, f, if f > 0 then 20 * f else 0)
			end
		end
		local gadget = buttons.Gadget
		if gadget and gadget.sweep then
			local f = GadgetClient.fraction()
			gadget.sweep.Size = UDim2.new(1, 12, f, if f > 0 then 20 * f else 0)
		end
		local leap = buttons.Leap
		if leap and leap.sweep then
			local f = 1 - MoveController.leapReady()
			leap.sweep.Size = UDim2.new(1, 12, f, if f > 0 then 20 * f else 0)
		end
		-- the movement buttons follow the hero's mobility and what they are doing (MoveController.labels)
		local labels = MoveController.labels()
		buttons.Fly.button.Visible = labels.fly ~= nil
		buttons.Fly.button.Text = labels.fly or "FLY"
		buttons.Boost.button.Visible = labels.boost ~= nil
		buttons.Boost.button.Text = labels.boost or "BOOST"
		buttons.Down.button.Visible = labels.down ~= nil
		buttons.Down.button.Text = labels.down or "DOWN"
		buttons.Leap.button.Text = labels.leap
		applyFocus()
	end))
end

return Hud
