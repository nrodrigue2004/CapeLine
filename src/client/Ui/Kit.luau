-- Kit: the one UI kit (spec: Screens and UI; shared with Mossbell Stand). Comic display font, one palette,
-- rounded cards, 56 px touch targets (48 minimum), safe-area aware screens. PLACEHOLDER look until M10.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = {}

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
Kit.Clicked = Signal.new() -- every kit button tap (the UI click sound)

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

Kit.color = {}
for name, value in Config.Ui.colors do
	Kit.color[name] = rgb(value)
end
Kit.font = Enum.Font.Bangers -- comic-book display face
Kit.bodyFont = Enum.Font.GothamBold
Kit.textScale = 1 -- Settings: text size 100 to 160 percent (spec: Accessibility)

-- Every text size limit made by the kit, so a Settings change resizes all text at once
local limits: { [UITextSizeConstraint]: number } = setmetatable({}, { __mode = "k" }) :: any

local function limitFor(parent: Instance, base: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.max(1, math.floor(base * Kit.textScale))
	limit.Parent = parent
	limits[limit] = base
end

function Kit.setTextScale(scale: number)
	Kit.textScale = math.clamp(scale, Config.Ui.textScale.min, Config.Ui.textScale.max)
	for limit, base in limits do
		limit.MaxTextSize = math.max(1, math.floor(base * Kit.textScale))
	end
end

-- Settings: flash level for bursts and screen flashes. 1 = full, 0.35 = reduced (bursts become a glow),
-- 0 = flash-free (photosensitivity)
function Kit.flash(): number
	return Kit.flashLevel
end
Kit.flashLevel = 1

---------------------------------------------------------------------------
-- Screen size (overhaul plan step 8, the phone pass; Shared.TouchLayout has the rules)
---------------------------------------------------------------------------
local Workspace = game:GetService("Workspace")
local TouchLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TouchLayout"))

Kit.LayoutChanged = Signal.new() -- the screen's size or the Button size setting changed: lay out again
Kit.buttonScale = 1 -- Settings: Button size (touch action buttons), 0.8 to 1.3

local probe: ScreenGui? = nil
local lastArea = Vector2.zero
local function areaChanged()
	local a = Kit.area()
	if a ~= lastArea then
		lastArea = a
		Kit.LayoutChanged:Fire()
	end
end

-- The size of a Kit screen's safe area (inside the notch, the home bar and Roblox's top bar)
function Kit.area(): Vector2
	if not probe then
		local g = Instance.new("ScreenGui")
		g.Name = "KitArea"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = false
		g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		probe = g
		g:GetPropertyChangedSignal("AbsoluteSize"):Connect(areaChanged)
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(areaChanged)
		end
	end
	local a = (probe :: ScreenGui).AbsoluteSize
	if a.X < 1 or a.Y < 1 then
		local cam = Workspace.CurrentCamera
		return if cam then cam.ViewportSize else Vector2.new(1280, 720)
	end
	return a
end

-- A phone-sized screen: the compact HUD and fitted panels
function Kit.compact(): boolean
	local a = Kit.area()
	return TouchLayout.compact(Config, a.X, a.Y)
end

function Kit.setButtonScale(scale: number)
	if scale ~= Kit.buttonScale then
		Kit.buttonScale = scale
		Kit.LayoutChanged:Fire()
	end
end

-- The HUD's layout options (set by the Hud: device, left-handed, Button size) and the boxes they give, so
-- every HUD module (Radar, WorldHud, SquadHud) places its part from the same plan
Kit.hudOpts = { touch = true, leftHanded = false, user = 1, present = {} } :: { [string]: any }
function Kit.setHudOpts(o: { [string]: any })
	local changed = false
	for k, v in o do
		if Kit.hudOpts[k] ~= v then
			Kit.hudOpts[k] = v
			changed = true
		end
	end
	if changed then
		Kit.LayoutChanged:Fire()
	end
end
function Kit.hudOptions(): { [string]: any }
	local o = table.clone(Kit.hudOpts)
	o.user = Kit.buttonScale
	return o
end
function Kit.hudBoxes(): TouchLayout.HudBoxes
	local a = Kit.area()
	return TouchLayout.hud(Config, a.X, a.Y, Kit.hudOptions() :: any)
end

-- Size a centred panel to the screen: it fills the safe area (less a margin) up to maxW x maxH, and below
-- minW x minH it keeps that design size and draws smaller with a UIScale (never under
-- Config.Ui.phone.minPanelScale; a list inside it scrolls). Follows rotation and resizes.
function Kit.fit(panel: GuiObject, minW: number, minH: number, maxW: number, maxH: number)
	local P = Config.Ui.phone
	local scale = panel:FindFirstChild("Fit") :: UIScale?
	if not scale then
		local s = Instance.new("UIScale")
		s.Name = "Fit"
		s.Parent = panel
		scale = s
	end
	for _, c in panel:GetChildren() do
		if c:IsA("UISizeConstraint") then
			c:Destroy() -- the fit sets the size itself
		end
	end
	local function apply()
		local a = Kit.area()
		local w, h = a.X - 2 * P.panelMargin, a.Y - 2 * P.panelMargin
		local k = TouchLayout.panelScale(Config, a.X, a.Y, minW, minH)
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = UDim2.fromOffset(
			math.floor(math.clamp(w / k, minW, maxW)),
			math.floor(math.clamp(h / k, minH, maxH))
		);
		(scale :: UIScale).Scale = k
		panel:SetAttribute("FitScale", k)
	end
	apply()
	Kit.LayoutChanged:Connect(apply)
end

---------------------------------------------------------------------------
-- The top row of screen buttons (POWERS, GEAR, MAP, SHOP, PING ...) from every module, laid out by
-- TouchLayout.dock; what does not fit on a phone goes in the MORE drawer. Each owner still shows and hides
-- its own button; the row closes up around hidden ones.
---------------------------------------------------------------------------
type DockEntry = { id: string, order: number, button: GuiButton, slot: Frame }
local dockGui: ScreenGui? = nil
local dockEntries: { DockEntry } = {}
local dockDrawer: ScrollingFrame? = nil
local dockMore: TextButton? = nil
local dockOpen = false
local dockSpan = { lo = 274, hi = -1, fromLo = false }
local dockQueued = false
Kit.DockLaid = Signal.new() -- after the row is laid out (the plan, for whoever needs the row's height)

local layoutDock: () -> ()

local function queueDock()
	if dockQueued then
		return
	end
	dockQueued = true
	task.defer(function()
		dockQueued = false
		layoutDock()
	end)
end

local function dockScreen(): ScreenGui
	if dockGui then
		return dockGui
	end
	local g = Kit.screen("Dock", 1)
	dockGui = g
	local drawer = Instance.new("ScrollingFrame")
	drawer.Name = "Drawer"
	drawer.BackgroundColor3 = Kit.color.night
	drawer.BackgroundTransparency = 0.15
	drawer.BorderSizePixel = 0
	drawer.ScrollBarThickness = 4
	drawer.ScrollingDirection = Enum.ScrollingDirection.Y
	drawer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	drawer.CanvasSize = UDim2.new()
	drawer.Visible = false
	Kit.round(drawer)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = drawer
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, 6)
	end
	pad.Parent = drawer
	drawer.Parent = g
	dockDrawer = drawer
	local more = Kit.button({
		Name = "More",
		Text = "MORE",
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
		maxText = 20,
	}, function()
		Kit.dockDrawer(not dockOpen)
	end)
	more.Parent = g
	dockMore = more
	Kit.LayoutChanged:Connect(queueDock)
	return g
end

function layoutDock()
	local g = dockScreen()
	local a = Kit.area()
	local hi = if dockSpan.hi < 0 then a.X - Config.Ui.safe else dockSpan.hi
	local items = {}
	local byId: { [string]: DockEntry } = {}
	for _, e in dockEntries do
		if e.button.Parent == e.slot and e.button.Visible then
			table.insert(items, { id = e.id, text = e.button.Text, order = e.order })
			byId[e.id] = e
		else
			e.slot.Visible = false
		end
	end
	local plan = TouchLayout.dock(Config, items, dockSpan.lo, hi, a.X, a.Y, dockSpan.fromLo)
	for id, box in plan.row do
		local e = byId[id]
		e.slot.Parent = g
		e.slot.Position = UDim2.fromOffset(box.x, box.y)
		e.slot.Size = UDim2.fromOffset(box.w, box.h)
		e.slot.Visible = true
	end
	local drawer = dockDrawer :: ScrollingFrame
	for i, id in plan.drawer do
		local e = byId[id]
		e.slot.Parent = drawer
		e.slot.LayoutOrder = i
		e.slot.Size = UDim2.new(1, 0, 0, plan.height)
		e.slot.Visible = true
	end
	local more = dockMore :: TextButton
	more.Visible = plan.more ~= nil
	if plan.more then
		local m = plan.more
		more.Position = UDim2.fromOffset(m.x, m.y)
		more.Size = UDim2.fromOffset(m.w, m.h)
		local dw = Config.Ui.phone.drawerW
		local x = if dockSpan.fromLo then m.x else m.x + m.w - dw
		local y = m.y + m.h + 6
		local rows = #plan.drawer
		local want = rows * (plan.height + 6) + 6
		drawer.Position = UDim2.fromOffset(x, y)
		drawer.Size = UDim2.fromOffset(dw, math.min(want, a.Y - y - Config.Ui.safe))
	else
		dockOpen = false
	end
	drawer.Visible = dockOpen and plan.more ~= nil
	Kit.DockLaid:Fire(plan)
end

-- Put a screen button in the top row. order: lower is more important (nearer the right edge, last to
-- go in the drawer).
function Kit.dock(button: GuiButton, id: string, order: number)
	dockScreen()
	local slot = Instance.new("Frame")
	slot.Name = id
	slot.BackgroundTransparency = 1
	slot.Visible = false
	button.AnchorPoint = Vector2.zero
	button.Position = UDim2.new()
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = slot
	slot.Parent = dockGui
	table.insert(dockEntries, { id = id, order = order, button = button, slot = slot })
	button:GetPropertyChangedSignal("Visible"):Connect(queueDock)
	if button:IsA("TextButton") then
		button:GetPropertyChangedSignal("Text"):Connect(queueDock)
	end
	button.Activated:Connect(function()
		if dockOpen and slot.Parent == dockDrawer then
			Kit.dockDrawer(false) -- a pick from the drawer closes it
		end
	end)
	queueDock()
end

-- Where the row may go (the HUD sets it from TouchLayout.hud): x from lo to hi, filled from hi (or lo)
function Kit.dockSpan(lo: number, hi: number, fromLo: boolean)
	dockSpan.lo, dockSpan.hi, dockSpan.fromLo = lo, hi, fromLo
	queueDock()
end

function Kit.dockDrawer(open: boolean)
	dockOpen = open
	if dockDrawer then
		dockDrawer.Visible = open and dockMore ~= nil and dockMore.Visible
	end
end

-- The whole row (the opening shows only its verb buttons)
function Kit.dockShown(on: boolean)
	dockScreen().Enabled = on
	if not on then
		Kit.dockDrawer(false)
	end
end

-- Gamepad: open the drawer and select the row's first button (the D-pad then moves between them)
function Kit.dockSelect(): GuiButton?
	layoutDock()
	local first: GuiButton? = nil
	local best = math.huge
	for _, e in dockEntries do
		if e.slot.Visible and e.slot.Parent == dockGui and e.order < best then
			first, best = e.button, e.order
		end
	end
	if dockMore and dockMore.Visible then
		Kit.dockDrawer(true)
	end
	return first
end

-- Lay the row out now (tests, and after the HUD builds)
function Kit.layoutDock()
	layoutDock()
end

function Kit.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order or 0
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

---------------------------------------------------------------------------
-- Panels: one main panel at a time. Every panel calls Kit.opening as it opens. A main panel (POWERS, GEAR,
-- MAP, JOURNAL, the boards ...) closes any other open main panel, so two never draw on top of each other;
-- an overlay (the shop, settings) opens on top and closes nothing. Going Downed closes them all
-- (Kit.closePanels). On a gamepad an opened panel's first button is selected, so the D-pad reaches its
-- buttons.
---------------------------------------------------------------------------
type PanelEntry = { root: Instance, close: () -> (), main: boolean }
local panels: { [string]: PanelEntry } = {}
Kit.padUi = false -- a gamepad is the input (the Hud sets it from InputController's device)

local function panelOpen(p: PanelEntry): boolean
	local root = p.root
	if root:IsA("LayerCollector") then
		return (root :: any).Enabled == true
	end
	return (root :: any).Visible == true and (root :: any).Parent ~= nil
end

-- Is this object drawn (it and every GuiObject above it visible, its screen enabled)?
local function shown(inst: Instance): boolean
	local n: Instance? = inst
	while n do
		if n:IsA("GuiObject") and not (n :: GuiObject).Visible then
			return false
		elseif n:IsA("LayerCollector") then
			return (n :: any).Enabled == true
		end
		n = n.Parent
	end
	return false
end

-- The panel's first drawn button, top to bottom then left to right
function Kit.firstButton(root: Instance): GuiButton?
	local best: GuiButton? = nil
	local by, bx = math.huge, math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and shown(d) then
			local p = d.AbsolutePosition
			if p.Y < by - 0.5 or (math.abs(p.Y - by) <= 0.5 and p.X < bx) then
				best, by, bx = d, p.Y, p.X
			end
		end
	end
	return best
end

-- Call as a panel opens, before it shows. root is what shows it (a GuiObject's Visible, or a ScreenGui's
-- Enabled) and close the panel's own close. A main panel closes the other main panels.
function Kit.opening(id: string, root: Instance, close: () -> (), main: boolean?)
	local me: PanelEntry = { root = root, close = close, main = main == true }
	if not panels[id] or panels[id].root ~= root then
		-- closing it lets go of a gamepad selection inside it (the D-pad goes back to the game)
		root:GetPropertyChangedSignal(if root:IsA("LayerCollector") then "Enabled" else "Visible")
			:Connect(function()
				local sel = GuiService.SelectedObject
				if sel and not panelOpen(me) and sel:IsDescendantOf(root) then
					GuiService.SelectedObject = nil
				end
			end)
	end
	panels[id] = me
	if panelOpen(me) then
		return -- already open (an open that redraws it): nothing to close, the selection stays
	end
	if me.main then
		for other, p in panels do
			if other ~= id and p.main and panelOpen(p) then
				p.close()
			end
		end
	end
	if Kit.padUi then
		task.defer(function()
			if panelOpen(me) then
				local b = Kit.firstButton(me.root)
				if b then
					GuiService.SelectedObject = b
				end
			end
		end)
	end
end

-- A pick that is not a registered panel (the main menu, the hero creator: never closed by another panel or by
-- going Downed; the cards that pop by themselves): gamepad Select (Kit.modalButton) goes into it instead of
-- the top row while it shows, and unless select is false its first button is selected as it shows (a card
-- that pops mid-play passes false, so the stick keeps moving the hero) (onboarding check)
local modals: { Instance } = {}
function Kit.padFocus(root: Instance, select: boolean?)
	if not table.find(modals, root) then
		table.insert(modals, root)
	end
	if Kit.padUi and select ~= false then
		task.defer(function()
			local b = if shown(root) then Kit.firstButton(root) else nil
			if b then
				GuiService.SelectedObject = b
			end
		end)
	end
end

-- The first button of the topmost open modal pick, or nil
function Kit.modalButton(): GuiButton?
	for i = #modals, 1, -1 do
		local root = modals[i]
		if shown(root) then
			local b = Kit.firstButton(root)
			if b then
				return b
			end
		end
	end
	return nil
end

-- Close every open registered panel (going Downed: nothing may cover the Downed screen)
function Kit.closePanels()
	for _, p in panels do
		if panelOpen(p) then
			p.close()
		end
	end
end

function Kit.round(inst: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Config.Ui.corner)
	c.Parent = inst
end

function Kit.stroke(inst: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Kit.color.ink
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
end

function Kit.frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Kit.color.paper
	f.BorderSizePixel = 0
	for k, v in props do
		if k ~= "round" then
			(f :: any)[k] = v
		end
	end
	if props.round ~= false then
		Kit.round(f)
	end
	return f
end

function Kit.label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Kit.font
	l.TextColor3 = Kit.color.ink
	l.TextScaled = true
	l.Size = UDim2.fromOffset(100, 24)
	for k, v in props do
		if k ~= "maxText" then
			(l :: any)[k] = v
		end
	end
	limitFor(l, props.maxText or 32)
	return l
end

function Kit.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.Font = Kit.font
	b.TextColor3 = Kit.color.ink
	b.BackgroundColor3 = Kit.color.gold
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Size = UDim2.fromOffset(Config.Ui.touchTarget * 2, Config.Ui.touchTarget)
	for k, v in props do
		if k ~= "maxText" and k ~= "pending" then
			(b :: any)[k] = v
		end
	end
	Kit.round(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	limitFor(b, props.maxText or 28)
	if onClick then
		local waits = props.pending == true
		b.Activated:Connect(function()
			if waits and b:GetAttribute("Pending") then
				return -- one request at a time
			end
			Kit.bounce(b)
			Kit.Clicked:Fire()
			if waits then
				Kit.pending(b)
			end
			onClick()
		end)
	end
	return b
end

-- Pending state (spec: "every remote call has a pending state under 150 ms"): the button shows "..." at
-- once and takes no more taps until the server answers (any profile sync, notice or toast settles it, and
-- most screens redraw). No answer in 5 s shows TRY AGAIN, the error state.
-- Each wait is tagged with its own number, so an earlier tap's timer (settled, then tapped again) never
-- shows TRY AGAIN or unlocks the button before the new tap's answer.
local pendingButtons: { [TextButton]: { text: string, tag: number } } = setmetatable({}, { __mode = "k" }) :: any
local pendingTag = 0
function Kit.pending(b: TextButton, timeout: number?)
	if pendingButtons[b] then
		return
	end
	pendingTag += 1
	local tag = pendingTag
	local text = b.Text
	pendingButtons[b] = { text = text, tag = tag }
	b:SetAttribute("Pending", true)
	b.Text = "..."
	local function mine(): boolean
		local p = pendingButtons[b]
		return p ~= nil and p.tag == tag and b.Parent ~= nil
	end
	task.delay(timeout or 5, function()
		if mine() then
			b.Text = "TRY AGAIN"
			task.delay(1.6, function()
				if mine() then
					b.Text = text
					b:SetAttribute("Pending", nil)
					pendingButtons[b] = nil
				end
			end)
		end
	end)
end

-- The server answered: every pending button goes back to normal
function Kit.settle()
	for b, p in pendingButtons do
		if b.Parent then
			b.Text = p.text
			b:SetAttribute("Pending", nil)
		end
	end
	table.clear(pendingButtons)
end

-- Loading, empty and error states: one centred note in a list or panel, with an optional RETRY
function Kit.stateNote(parent: Instance, kind: string, text: string, retry: (() -> ())?): Frame
	local f = Instance.new("Frame")
	f.Name = "StateNote"
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, if retry then 96 else 56)
	f.LayoutOrder = -1
	local l = Kit.label({
		Text = (if kind == "loading" then "⏳ " elseif kind == "error" then "⚠ " else "") .. text,
		Size = UDim2.new(1, -16, 0, 48),
		Position = UDim2.fromOffset(8, 4),
		TextColor3 = if kind == "error" then Color3.fromRGB(255, 150, 120) else Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 16,
	})
	l.Parent = f
	if retry then
		local b = Kit.button({
			Text = "RETRY",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(140, Config.Ui.touchTarget - 12),
			Position = UDim2.new(0.5, 0, 0, 52),
		}, retry)
		b.Parent = f
	end
	f.Parent = parent
	return f
end

-- The object's UIScale and the size it rests at (a fitted panel rests at its fit, Kit.fit)
local function restScale(inst: GuiObject): (UIScale, number)
	local scale = inst:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = inst
	local fit = inst:GetAttribute("FitScale")
	return scale, if type(fit) == "number" then fit else 1
end

function Kit.bounce(inst: GuiObject)
	local scale, rest = restScale(inst)
	scale.Scale = 0.9 * rest
	TweenService
		:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = rest })
		:Play()
end

function Kit.pulse(inst: GuiObject, amount: number?)
	local scale, rest = restScale(inst)
	scale.Scale = (1 + (amount or 0.12)) * rest
	TweenService
		:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = rest })
		:Play()
end

-- 12345 -> "12,345"
-- Count a reward line up (spec: Wait table "Reward screens | Counts up in 5 s, skippable with one tap").
-- render(k) draws the line at k from 0 to 1 (eased). Returns finish(): jump to the end; true if it was
-- still counting (so a tap that finishes the count does not also close the card).
function Kit.countUp(label: TextLabel, seconds: number, render: (number) -> string): () -> boolean
	local t0 = os.clock()
	local done = false
	label.Text = render(0)
	task.spawn(function()
		while not done and label.Parent do
			local k = math.min(1, (os.clock() - t0) / seconds)
			label.Text = render(1 - (1 - k) * (1 - k))
			if k >= 1 then
				done = true
				break
			end
			task.wait()
		end
	end)
	return function(): boolean
		local was = not done
		done = true
		label.Text = render(1)
		return was
	end
end

-- "+1,234 CREDITS   +567 RENOWN" counted to k
function Kit.payLine(credits: number, renown: number, k: number): string
	return string.format(
		"+%s CREDITS   +%s RENOWN",
		Kit.comma(math.floor(credits * k + 0.5)),
		Kit.comma(math.floor(renown * k + 0.5))
	)
end

function Kit.comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	repeat
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return out
end

function Kit.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Kit
