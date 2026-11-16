-- Hud: the main HUD for M1 (spec: Screens and UI > Main HUD): health bar, stamina ring, the basic and two
-- skill buttons with cooldown sweeps, the movement buttons (Leap, Fly, Boost, Down), a crosshair that pops on
-- a confirmed hit, and the level, class and power set. Phone first: 56 px buttons, a 16 px safe area, and the
-- bottom 80 px on the right left clear for the flight pad. Buttons carry only verbs (spec: first 30 seconds).
-- On PC and gamepad the same buttons show their key; they are drawn smaller.
-- PLACEHOLDER look until the UI pass (M10): the Renown bar, radar, world clock and boss countdown arrive with
-- their systems (M3, M4, M6).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local CombatClient = require(script.Parent.Parent.Controllers.CombatClient)

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
		Size = UDim2.fromOffset(250, 66),
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
	card.Parent = gui
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
	local cluster = Instance.new("Frame")
	cluster.Name = "Cluster"
	cluster.BackgroundTransparency = 1
	cluster.AnchorPoint = Vector2.new(1, 1)
	cluster.Size = UDim2.fromOffset(300, 300)
	cluster.Position = UDim2.new(1, -U.safe, 1, -96) -- the bottom 80 px stay clear for the flight pad
	cluster.Parent = gui
	local big = U.touchTarget + 24
	local s = U.touchTarget
	local volt = rgb(U.colors.volt)
	local gold = Kit.color.gold
	actionButton(cluster, "Basic", "ZAP", big, UDim2.new(1, -big / 2 - 4, 1, -big / 2 - 4), volt)
	actionButton(cluster, "Skill1", "CHAIN", s, UDim2.new(1, -big - s / 2 - 20, 1, -s / 2 - 4), volt)
	actionButton(cluster, "Skill2", "DASH", s, UDim2.new(1, -big / 2 - 4, 1, -big - s / 2 - 22), volt)
	actionButton(cluster, "Leap", "LEAP", s, UDim2.new(1, -big - s * 1.5 - 40, 1, -s / 2 - 4), gold)
	actionButton(cluster, "Fly", "FLY", s, UDim2.new(1, -big - s * 1.5 - 40, 1, -s * 1.5 - 22), gold)
	local boost =
		actionButton(cluster, "Boost", "BOOST", s, UDim2.new(1, -big - s / 2 - 20, 1, -s * 1.5 - 22), gold)
	actionButton(cluster, "Down", "DOWN", s - 8, UDim2.new(1, -big - s * 2.5 - 52, 1, -s / 2 - 4), gold)
	buildStaminaRing(boost)
end

local function refreshInfo()
	local h = State.hero
	infoText.Text = string.format("LV %d  %s  %s", h.level, string.upper(h.classId), string.upper(h.setId))
	local skills = h.loadout.skills
	for i, action in { "Skill1", "Skill2" } do
		local id = skills[i]
		local entry = buttons[action]
		if entry then
			entry.button.Visible = id ~= nil
			if id and A[id] then
				entry.button.Text = string.upper(string.split(A[id].name, " ")[1])
			end
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

function Hud.init()
	gui = Kit.screen("Hud", 1)
	local stamFill = buildTopLeft()
	buildCrosshair()
	buildCluster()
	refreshInfo()
	applyDevice(InputController.device)
	State.Changed:Connect(refreshInfo)
	InputController.DeviceChanged:Connect(applyDevice)
	CombatClient.HitConfirm:Connect(function(crit)
		local scale = crosshair:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale = if crit then 1.8 else 1.4
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1 }):Play()
	end)
	local low = rgb(U.colors.healthLow)
	local ok = rgb(U.colors.health)
	RunService.RenderStepped:Connect(function()
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
		-- cooldown sweeps
		local h = State.hero
		for action, id in
			{ Basic = h.loadout.basic, Skill1 = h.loadout.skills[1], Skill2 = h.loadout.skills[2] }
		do
			local entry = buttons[action]
			if entry and entry.sweep and id then
				local f = CombatClient.cooldownFraction(id)
				entry.sweep.Size = UDim2.new(1, 12, f, if f > 0 then 20 * f else 0)
			end
		end
		local leap = buttons.Leap
		if leap and leap.sweep then
			local f = 1 - MoveController.leapReady()
			leap.sweep.Size = UDim2.new(1, 12, f, if f > 0 then 20 * f else 0)
		end
		local mode = MoveController.mode
		local flying = mode == "fly"
		buttons.Fly.button.Visible = h.styles ~= nil and h.styles.flight == true
		buttons.Fly.button.Text = if flying then "LAND" else "FLY"
		buttons.Boost.button.Visible = flying
		buttons.Down.button.Visible = flying
		buttons.Leap.button.Text = if flying
			then "UP"
			elseif mode == "air" or mode == "glide" then "GLIDE"
			else "LEAP"
	end)
end

return Hud
