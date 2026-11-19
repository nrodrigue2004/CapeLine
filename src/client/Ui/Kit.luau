-- Kit: the one UI kit (spec: Screens and UI; shared with Mossbell Stand). Comic display font, one palette,
-- 56 px touch targets (48 minimum), safe-area aware screens. The bold comic look (nate's pick, 2026-11-18):
-- every drawn panel and button gets a thick ink outline and a hard ink drop shadow (Kit.ink), paper panels
-- faint halftone dots, light display text an ink outline, and the top row's tabs lean (Config.Ui.ink).

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
-- The top row of screen buttons from every module, laid out by TouchLayout.dock. The declutter pass (nate's
-- playtest 2026-11-19): the row holds only Config.Ui.dock.row (POWERS, GEAR, MAP, SHOP, LEAVE) and pinned
-- buttons (the DockPin attribute: PVP while flagged); everything else, and what does not fit on a phone,
-- goes in the MENU drawer, a grid under MENU. Each owner still shows and hides its own button; the row and
-- the grid close up around hidden ones. A drawer button whose label ends in "!" makes it "MENU !" in gold.
---------------------------------------------------------------------------
type DockEntry = { id: string, order: number, button: GuiButton, slot: Frame }
local dockGui: ScreenGui? = nil
local dockMenuGui: ScreenGui? = nil -- the drawer's own screen, over the HUD's action buttons
local dockEntries: { DockEntry } = {}
local dockDrawer: ScrollingFrame? = nil
local dockMore: TextButton? = nil
local dockOpen = false
local dockSpan = { lo = 274, hi = -1, fromLo = false }
local dockQueued = false
Kit.DockLaid = Signal.new() -- after the row is laid out (the plan, for whoever needs the row's height)

local layoutDock: () -> ()
local hintShown: (GuiButton, boolean) -> ()

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
	-- the drawer draws (and takes taps) over the HUD's buttons, under every panel (5 and up)
	local menuGui = Kit.screen("DockMenu", 4)
	dockMenuGui = menuGui
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
	Kit.ink(drawer, { shadow = false }) -- it clips, so it would cut its own shadow off
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = drawer
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, 6)
	end
	pad.Parent = drawer
	drawer.Parent = menuGui
	dockDrawer = drawer
	local more = Kit.button({
		Name = "More",
		Text = Config.Ui.dock.menu,
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

-- A docked button's key hint (the Hud's "Hint" label under it) shows in the row, not in the drawer (under a
-- grid cell it would sit on the next row): the InDrawer attribute tells the Hud
function hintShown(button: GuiButton, on: boolean)
	if button:GetAttribute("InDrawer") ~= not on then
		button:SetAttribute("InDrawer", not on)
	end
end

function layoutDock()
	local g = dockScreen()
	local a = Kit.area()
	local hi = if dockSpan.hi < 0 then a.X - Config.Ui.safe else dockSpan.hi
	local items = {}
	local byId: { [string]: DockEntry } = {}
	local rowIds = Config.Ui.dock.row
	for _, e in dockEntries do
		if e.button.Parent == e.slot and e.button.Visible then
			local menu = not rowIds[e.id] and e.button:GetAttribute("DockPin") ~= true
			table.insert(items, { id = e.id, text = e.button.Text, order = e.order, menu = menu })
			byId[e.id] = e
		else
			e.slot.Visible = false
		end
	end
	local plan = TouchLayout.dock(Config, items, dockSpan.lo, hi, a.X, a.Y, dockSpan.fromLo)
	local xs = {}
	for id, box in plan.row do
		local e = byId[id]
		e.slot.Parent = g
		e.slot.Position = UDim2.fromOffset(box.x, box.y)
		e.slot.Size = UDim2.fromOffset(box.w, box.h)
		e.slot.Visible = true
		table.insert(xs, { x = box.x, e = e })
	end
	-- the comic tabs lean alternately along the row (drawer rows sit straight)
	table.sort(xs, function(p, q)
		return p.x < q.x
	end)
	for i, p in xs do
		p.e.button.Rotation = if i % 2 == 0 then Config.Ui.ink.tilt else -Config.Ui.ink.tilt
		hintShown(p.e.button, true)
	end
	local drawer = dockDrawer :: ScrollingFrame
	local alert = false
	for i, id in plan.drawer do
		local e = byId[id]
		e.slot.Parent = drawer
		e.slot.LayoutOrder = i
		e.slot.Visible = true
		e.button.Rotation = 0
		hintShown(e.button, false) -- a key hint under a grid cell would sit on the next row
		if e.button:IsA("TextButton") and string.sub(e.button.Text, -1) == "!" then
			alert = true
		end
	end
	-- something to claim in the drawer (DAILY !): MENU says so the same way
	local menuText = Config.Ui.dock.menu .. (if alert then " !" else "")
	if dockMore and dockMore.Text ~= menuText then
		dockMore.Text = menuText
		dockMore.BackgroundColor3 = if alert then Kit.color.gold else Kit.color.paper
	end
	local more = dockMore :: TextButton
	more.Visible = plan.more ~= nil
	more.Rotation = Config.Ui.ink.tilt
	if plan.more then
		local m = plan.more
		more.Position = UDim2.fromOffset(m.x, m.y)
		more.Size = UDim2.fromOffset(m.w, m.h)
		-- a grid of up to Config.Ui.dock.columns columns, hung under MENU and kept on screen
		local cols = math.max(1, math.min(Config.Ui.dock.columns, #plan.drawer))
		local cw = Config.Ui.phone.drawerW
		local dw = cols * cw + (cols - 1) * 6 + 12
		local x = if dockSpan.fromLo then m.x else m.x + m.w - dw
		x = math.clamp(x, Config.Ui.safe, math.max(Config.Ui.safe, a.X - Config.Ui.safe - dw))
		-- below the row's key hints and the wallet line on a big screen
		local y = m.y + m.h + (if Kit.compact() then 6 else 26)
		local rows = math.ceil(#plan.drawer / cols)
		local want = rows * (plan.height + 6) + 6
		local grid = drawer:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
		grid.CellSize = UDim2.fromOffset(cw, plan.height)
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
	-- a comic tab: square-ish corners, ink outline and hard shadow, whatever made the button
	Kit.round(button)
	if button:IsA("TextButton") then
		Kit.ink(button, { force = true })
		-- one lettering size for every tab, whoever made the button (they sit side by side in the MENU grid)
		local limit = button:FindFirstChildOfClass("UITextSizeConstraint")
		if limit and limits[limit] then
			limits[limit] = Config.Ui.dock.text
			limit.MaxTextSize = math.max(1, math.floor(Config.Ui.dock.text * Kit.textScale))
		end
	end
	slot.Parent = dockGui
	table.insert(dockEntries, { id = id, order = order, button = button, slot = slot })
	button:GetPropertyChangedSignal("Visible"):Connect(queueDock)
	button:GetAttributeChangedSignal("DockPin"):Connect(queueDock)
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
	dockScreen().Enabled = on;
	(dockMenuGui :: ScreenGui).Enabled = on
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
	Kit.dockDrawer(false) -- a screen opening puts the MENU drawer away
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

---------------------------------------------------------------------------
-- The comic ink (nate's bold comic pick, 2026-11-18; Config.Ui.ink). Kit.ink gives a drawn panel or button
-- an ink outline (UIStroke "InkLine") and a hard drop shadow: two ink bars just past its bottom and right
-- edges (with Sibling ZIndex a child always draws over its parent, so a shadow cannot sit under it), with
-- paper and night panels' halftone dots, all in a Folder "Ink" so the object's UIListLayout or UIGridLayout
-- never lays them out. It follows the fill: hidden on an invisible container (more transparent than
-- showBelow), fading with it; no shadow on a bar's fill or a full-screen backdrop (sized to the parent's full
-- height), a part under minShadow tall (thin outline only) or a circle or pill (rounder than maxRound: the
-- owner draws that shadow, as the Hud does). Pass ink = false to Kit.frame, Kit.label or Kit.button to opt
-- out; a label gets ink only when it is made with a fill, a square-cornered frame only with ink = true.
---------------------------------------------------------------------------
local INK = Config.Ui.ink
local inkSync: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" }) :: any
local inkOpts: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local inkCustom: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- Kit.stroke set its look

local function luma(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end
Kit.luma = luma

local function inkBar(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Kit.color.ink
	f.BorderSizePixel = 0
	f.Active = false
	f.Selectable = false
	f.ZIndex = -100 -- under anything of the owner's that hangs past its edge
	f.Parent = parent
	return f
end

function Kit.ink(inst: GuiObject, opts: { [string]: any }?)
	if inkSync[inst] then
		for k, v in opts or {} do
			inkOpts[inst][k] = v -- a second call changes its options (Kit.dock forces a tab's ink on)
		end
		inkSync[inst]()
		return
	end
	local o = table.clone(opts or {})
	inkOpts[inst] = o
	local line = Instance.new("UIStroke")
	line.Name = "InkLine"
	line.Color = Kit.color.ink
	line.Thickness = INK.stroke
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.LineJoinMode = Enum.LineJoinMode.Miter
	line.Parent = inst
	local deco = Instance.new("Folder")
	deco.Name = "Ink"
	deco.Parent = inst
	local right = inkBar("ShadowR", deco)
	local bottom = inkBar("ShadowB", deco)
	local dots: ImageLabel? = nil
	local dotsCorner: UICorner? = nil
	if o.halftone and INK.halftone.image ~= "" then
		local d = Instance.new("ImageLabel")
		d.Name = "Halftone"
		d.BackgroundTransparency = 1
		d.Image = INK.halftone.image
		d.ScaleType = Enum.ScaleType.Tile
		d.TileSize = UDim2.fromOffset(INK.halftone.tile, INK.halftone.tile)
		d.Active = false
		d.Selectable = false
		d.ZIndex = -100 -- under the panel's own content
		d:SetAttribute("Halftone", true)
		local c = Instance.new("UICorner")
		c.Parent = d
		d.Parent = deco
		dots, dotsCorner = d, c
	end
	local function sync()
		local t = inst.BackgroundTransparency
		local size = inst.Size
		local auto = inst.AutomaticSize == Enum.AutomaticSize.Y or inst.AutomaticSize == Enum.AutomaticSize.XY
		local fill = size.Y.Scale >= 0.999 and not o.force -- a bar's fill, a backdrop
		local shown = t <= INK.showBelow and not fill
		local thin = not auto and size.Y.Scale == 0 and size.Y.Offset < INK.minShadow
		local corner = inst:FindFirstChildOfClass("UICorner")
		local r = if corner then corner.CornerRadius else UDim.new(0, 0)
		local round = r.Scale >= 0.25 or r.Offset > INK.maxRound
		if not inkCustom[inst] then
			line.Thickness = if thin then INK.thin else INK.stroke
		end
		line.Enabled = shown
		line.Transparency = t
		local w = line.Thickness
		local d = INK.shadow
		-- the outline draws outside the box, so the shadow is the outlined shape moved d down-right; a
		-- Folder's GuiObjects lay out in the owner's padded content box, so undo its UIPadding
		local pad = if INK.padsFolder then inst:FindFirstChildOfClass("UIPadding") else nil
		local pl, pt = if pad then pad.PaddingLeft.Offset else 0, if pad then pad.PaddingTop.Offset else 0
		local pr, pb = if pad then pad.PaddingRight.Offset else 0, if pad then pad.PaddingBottom.Offset else 0
		local cast = shown and not thin and not round and o.shadow ~= false
		right.Visible = cast
		bottom.Visible = cast
		right.BackgroundTransparency = t
		bottom.BackgroundTransparency = t
		right.Position = UDim2.new(1, w + pr, 0, d - w - pt)
		right.Size = UDim2.new(0, d, 1, 2 * w + pt + pb)
		bottom.Position = UDim2.new(0, d - w - pl, 1, w + pb)
		bottom.Size = UDim2.new(1, 2 * w - d + pl + pr, 0, d)
		if dots then
			local light = luma(inst.BackgroundColor3) > 0.6
			local dark = luma(inst.BackgroundColor3) < 0.3
			dots.Visible = shown and (light or dark) and not thin
			dots.ImageColor3 = if dark then Kit.color.white else Kit.color.ink
			local base = if dark then INK.halftone.darkTransparency else INK.halftone.transparency
			dots.ImageTransparency = base + (1 - base) * t
			dots.Position = UDim2.fromOffset(-pl, -pt)
			dots.Size = UDim2.new(1, pl + pr, 1, pt + pb);
			(dotsCorner :: UICorner).CornerRadius = r
		end
	end
	inkSync[inst] = sync
	for _, key in { "BackgroundTransparency", "BackgroundColor3", "Size", "AutomaticSize" } do
		inst:GetPropertyChangedSignal(key):Connect(sync)
	end
	sync()
end

-- A round button's hard ink drop shadow (the comic look, 2026-11-18): a disc one outline wider, moved
-- down-right, drawn as the button's sibling under it (a child would draw over it). burst also sits it on a red
-- starburst: three turned squares whose crossings hide under the button. Both follow the button's place,
-- anchor, size, fill and visibility, in the parent's Folder "Ink" (decoration: never laid out or tapped).
-- Call once the button has its parent; the button keeps a ZIndex above 1 less than its own.
function Kit.discInk(b: GuiObject, burst: boolean?)
	local parent = b.Parent :: Instance
	local folder = parent:FindFirstChild("Ink")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Ink"
		folder.Parent = parent
	end
	local function disc(name: string, color: Color3): Frame
		local d = Instance.new("Frame")
		d.Name = b.Name .. name
		d.BackgroundColor3 = color
		d.BorderSizePixel = 0
		d.Active = false
		d.Selectable = false
		d.ZIndex = b.ZIndex - 1
		d.Parent = folder
		return d
	end
	local shadow = disc("Shadow", Kit.color.ink)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = shadow
	local rays: { Frame } = {}
	if burst then
		for i = 0, 2 do
			local r = disc("Burst" .. i, Kit.color.red)
			r.AnchorPoint = Vector2.new(0.5, 0.5)
			r.Rotation = i * 30
			Kit.stroke(r, Kit.color.ink, INK.stroke)
			table.insert(rays, r)
		end
	end
	local function sync()
		local line = b:FindFirstChild("InkLine") :: UIStroke?
		local w = if line then line.Thickness else INK.stroke
		-- the button's UIScale (a phone's smaller radar, Kit.bounce) scales it about its anchor point
		local us = b:FindFirstChildOfClass("UIScale")
		local k = if us then us.Scale else 1
		local p, a, size = b.Position, b.AnchorPoint, b.Size.X.Offset
		local d = INK.shadow * k
		shadow.AnchorPoint = a
		shadow.Position = p + UDim2.fromOffset((2 * a.X - 1) * w * k + d, (2 * a.Y - 1) * w * k + d)
		shadow.Size = UDim2.fromOffset((size + 2 * w) * k, (size + 2 * w) * k)
		shadow.Visible = b.Visible and not burst -- the starburst stands in for Super's shadow
		shadow.BackgroundTransparency = b.BackgroundTransparency
		local side = math.floor(size * k * 0.93) -- the squares' crossings sit just inside the button's outline
		for _, r in rays do
			r.Position = p + UDim2.fromOffset((0.5 - a.X) * size * k, (0.5 - a.Y) * size * k)
			r.Size = UDim2.fromOffset(side, side)
			r.Visible = b.Visible
		end
	end
	for _, key in { "Position", "AnchorPoint", "Size", "Visible", "BackgroundTransparency" } do
		b:GetPropertyChangedSignal(key):Connect(sync)
	end
	local function watchScale(c: Instance)
		if c:IsA("UIScale") then
			c:GetPropertyChangedSignal("Scale"):Connect(sync)
			sync()
		end
	end
	for _, c in b:GetChildren() do
		watchScale(c)
	end
	b.ChildAdded:Connect(watchScale)
	sync()
end

-- Ink only once the object draws a fill (a container made invisible that lights up later still gets it)
local function inkWhenDrawn(inst: GuiObject, opts: { [string]: any }?)
	if inst.BackgroundTransparency <= INK.showBelow then
		Kit.ink(inst, opts)
		return
	end
	local conn: RBXScriptConnection? = nil
	conn = inst:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if inst.BackgroundTransparency <= INK.showBelow then
			(conn :: RBXScriptConnection):Disconnect()
			Kit.ink(inst, opts)
		end
	end)
end

-- Light display text gets an ink outline (a thick one on big text), so it reads on any fill like a comic's
-- lettering; dark text and body text stay plain. props that set the text stroke themselves keep theirs.
local function inkText(t: TextLabel | TextButton, props: { [string]: any }, big: boolean)
	if props.TextStrokeTransparency ~= nil or props.inkText == false then
		return
	end
	local thick: UIStroke? = nil
	if big and t.BackgroundTransparency >= 0.99 then
		local s = Instance.new("UIStroke")
		s.Name = "InkText"
		s.Color = Kit.color.ink
		s.Thickness = INK.thin
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = t
		thick = s
	end
	local set = 1
	local function sync()
		local light = t.Font == Kit.font and luma(t.TextColor3) > 0.55
		if thick then
			thick.Enabled = light
		elseif t.TextStrokeTransparency == set then
			set = if light then 0 else 1
			t.TextStrokeColor3 = Kit.color.ink
			t.TextStrokeTransparency = set
		end
	end
	sync()
	t:GetPropertyChangedSignal("TextColor3"):Connect(sync)
end

---------------------------------------------------------------------------
-- The comic icon set (gap-icons, 2026-11-19; art/icons/icons.py, Config.Icons): 128 px cells on 1024 px
-- sheets. Every call gives nil while the cell's sheet is not uploaded (id 0), so callers keep their text.
---------------------------------------------------------------------------
local IC = Config.Icons

-- The image, offset and size of one cell ("ability" ZapBolt, "weapon" 5, "slot" head ...), or nil
function Kit.iconCell(group: string, key: any): (string?, Vector2?, Vector2?)
	local list = IC and IC[group]
	local at = list and list[key]
	local sheet = at and IC.sheets[at[1]]
	if not sheet or (sheet.id or 0) == 0 then
		return nil
	end
	local c = at[2]
	return "rbxassetid://" .. sheet.id,
		Vector2.new((c % IC.perRow) * IC.cell, (c // IC.perRow) * IC.cell),
		Vector2.new(IC.cell, IC.cell)
end

-- An ImageLabel showing one cell (props set its size and place; default: fills the parent), or nil
function Kit.icon(group: string, key: any, props: { [string]: any }?): ImageLabel?
	local image, offset, size = Kit.iconCell(group, key)
	if not image then
		return nil
	end
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = image :: string
	i.ImageRectOffset = offset :: Vector2
	i.ImageRectSize = size :: Vector2
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = UDim2.fromScale(1, 1)
	i.Active = false
	i.Selectable = false
	for k, v in props or {} do
		(i :: any)[k] = v
	end
	return i
end

-- Points an icon made by Kit.icon at another cell (false when that cell has no uploaded sheet)
function Kit.setIcon(i: ImageLabel, group: string, key: any): boolean
	local image, offset, size = Kit.iconCell(group, key)
	if not image then
		return false
	end
	i.Image = image :: string
	i.ImageRectOffset = offset :: Vector2
	i.ImageRectSize = size :: Vector2
	return true
end

-- A power's or a weapon move's icon cells: a power is its own disc; a weapon move ("W<n><key>", see
-- Shared.WeaponRules.skillId) is the weapon's silhouette plus its move badge (the combo, or Z X C V)
function Kit.abilityCells(id: string): ({ any }?, { any }?)
	if IC and IC.ability[id] then
		return { "ability", id }, nil
	end
	local n, key = string.match(id, "^W(%d+)(%w+)$")
	if n and IC and IC.weapon[tonumber(n)] then
		return { "weapon", tonumber(n) }, if IC.move[key] then { "move", key } else nil
	end
	return nil, nil
end

-- Shows one cell on `holder` (the icon is made once, then re-pointed): it fills the holder's whole box,
-- under a button's cooldown sweep and numbers; `badge` ({ group, key }) sits at its lower right. Returns
-- false (and hides any icon) when there is nothing to show, so the caller keeps its text.
function Kit.showIcon(holder: GuiObject, group: string?, key: any, badge: { any }?): boolean
	local icon = holder:FindFirstChild("Icon") :: ImageLabel?
	if not group or not Kit.iconCell(group, key) then
		if icon then
			icon.Visible = false
		end
		return false
	end
	if not icon then
		-- a padded button lays its children out inside the padding: undo it
		local p = holder:FindFirstChildOfClass("UIPadding")
		local pl = if p then p.PaddingLeft.Offset else 0
		local pr = if p then p.PaddingRight.Offset else 0
		local pt = if p then p.PaddingTop.Offset else 0
		local pb = if p then p.PaddingBottom.Offset else 0
		local made = Kit.icon(group, key, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, (pr - pl) / 2, 0.5, (pb - pt) / 2),
			Size = UDim2.new(1, pl + pr, 1, pt + pb),
			ZIndex = holder.ZIndex,
		}) :: ImageLabel
		made.Parent = holder
		icon = made
	end
	local i = icon :: ImageLabel
	i.Visible = true
	Kit.setIcon(i, group, key)
	local mark = i:FindFirstChild("Badge") :: ImageLabel?
	if badge and Kit.iconCell(badge[1], badge[2]) then
		if not mark then
			mark = Kit.icon(badge[1], badge[2], {
				Name = "Badge",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1.06, 1.06),
				Size = UDim2.fromScale(0.42, 0.42),
				ZIndex = i.ZIndex,
			});
			(mark :: ImageLabel).Parent = i
		end
		local m = mark :: ImageLabel
		m.Visible = true
		Kit.setIcon(m, badge[1], badge[2])
	elseif mark then
		mark.Visible = false
	end
	return true
end

-- An ability's icon on `holder` (a power's disc, or a weapon's silhouette with its move badge)
function Kit.showAbility(holder: GuiObject, id: string?): boolean
	local main, badge = nil, nil
	if id then
		main, badge = Kit.abilityCells(id)
	end
	return Kit.showIcon(holder, main and main[1], main and main[2], badge)
end

-- A gear piece's icon: the tier frame with the slot symbol over it (pips along the frame's bottom stay
-- clear). nil while the sheet is not uploaded.
function Kit.gearIcon(slot: string, tier: string, props: { [string]: any }?): ImageLabel?
	local frame = Kit.icon("tier", tier, props)
	if not frame then
		return nil
	end
	frame.Name = "GearIcon"
	local s = Kit.icon("slot", slot, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = frame.ZIndex + 1,
	})
	if s then
		s.Parent = frame
	end
	return frame
end

-- gap-icons2 (2026-11-19): a world symbol (an incident, event, contract or marker) on its colorblind-safe shape
-- (Config.Icons.shape: white comic backings tinted with ImageColor3), filling `holder`'s box. The shape keeps
-- the marker's colour and outline (circle incident, star event, diamond boss, triangle danger, square squad,
-- hex contract); the symbol sits where Config.Icons.shapeInner puts it. Made once, then re-pointed. false (and
-- both hidden) while either cell is not uploaded, so the caller keeps today's look.
function Kit.showMark(holder: GuiObject, shape: string, color: Color3, group: string?, key: any): boolean
	local back = holder:FindFirstChild("MarkShape") :: ImageLabel?
	local sym = back and back:FindFirstChild("MarkSym") :: ImageLabel?
	if not group or not Kit.iconCell("shape", shape) or not Kit.iconCell(group, key) then
		if back then
			back.Visible = false
		end
		return false
	end
	if not back then
		local z = holder.ZIndex
		back = Kit.icon("shape", shape, {
			Name = "MarkShape",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = z,
		})
		sym = Kit.icon(group, key, { Name = "MarkSym", AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z });
		(sym :: ImageLabel).Parent = back;
		(back :: ImageLabel).Parent = holder
	end
	local b, s = back :: ImageLabel, sym :: ImageLabel
	b.Visible = true
	-- a rotated holder (the old diamond) must not turn the picture
	b.Rotation = -holder.Rotation
	Kit.setIcon(b, "shape", shape)
	b.ImageColor3 = color
	Kit.setIcon(s, group, key)
	local inner = IC.shapeInner and IC.shapeInner[shape] or { 0.5, 0.5, 0.66 }
	s.Position = UDim2.fromScale(inner[1], inner[2])
	s.Size = UDim2.fromScale(inner[3], inner[3])
	return true
end

-- gap-icons2: an icon at the left of a text line (a header, a tab, a row's title): the text moves right by the
-- icon's width. px: the icon's size (default the label's height). nil while the cell is not uploaded.
function Kit.lead(label: GuiObject, group: string, key: any, px: number?): ImageLabel?
	local old = label:FindFirstChild("Lead") :: ImageLabel?
	if old then
		old:Destroy()
	end
	local size = px or label.AbsoluteSize.Y
	if size <= 0 then
		size = label.Size.Y.Offset
	end
	local i = Kit.icon(group, key, {
		Name = "Lead",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -(size + 4), 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		ZIndex = label.ZIndex,
	})
	if not i then
		return nil
	end
	-- one UIPadding an object (a button already has one): widen its left by the icon, once
	local pad = label:FindFirstChildOfClass("UIPadding")
	if not pad then
		local made = Instance.new("UIPadding")
		made.Parent = label
		pad = made
	end
	local p = pad :: UIPadding
	local base = p:GetAttribute("LeadBase")
	if type(base) ~= "number" then
		base = p.PaddingLeft.Offset
		p:SetAttribute("LeadBase", base)
	end
	p.PaddingLeft = UDim.new(0, (base :: number) + size + 4)
	i.Parent = label
	return i
end

function Kit.round(inst: GuiObject, radius: number?)
	local c = inst:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Config.Ui.corner)
	c.Parent = inst
	local sync = inkSync[inst]
	if sync then
		sync() -- a circle or pill drops its bar shadow; the halftone follows the corner
	end
end

-- An outline. On an inked object it restyles the ink outline (one UIStroke per object); an ink-coloured one
-- is never thinner than the ink.
function Kit.stroke(inst: GuiObject, color: Color3?, thickness: number?)
	local line = if inkSync[inst] then inst:FindFirstChild("InkLine") :: UIStroke? else nil
	if line then
		inkCustom[inst] = true
		local c = color or Kit.color.ink
		line.Color = c
		line.Thickness = if c == Kit.color.ink then math.max(thickness or 2, INK.stroke) else thickness or 2
		inkSync[inst]()
		return
	end
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
		if k ~= "round" and k ~= "ink" and k ~= "halftone" then
			(f :: any)[k] = v
		end
	end
	if props.round ~= false then
		Kit.round(f)
	end
	-- a square-cornered frame (round = false) is a shape (a letterbox bar, a speed line, a drawing's part):
	-- inked only when asked (ink = true)
	if props.ink == true or (props.ink ~= false and props.round ~= false) then
		inkWhenDrawn(f, { halftone = props.halftone ~= false })
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
		if k ~= "maxText" and k ~= "ink" and k ~= "inkText" then
			(l :: any)[k] = v
		end
	end
	limitFor(l, props.maxText or 32)
	if props.ink ~= false and l.BackgroundTransparency < 0.99 then
		Kit.ink(l)
	end
	inkText(l, props, (props.maxText or 32) >= 24)
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
		if k ~= "maxText" and k ~= "pending" and k ~= "ink" and k ~= "inkText" then
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
	if props.ink ~= false then
		inkWhenDrawn(b)
	end
	inkText(b, props, false)
	if onClick then
		local waits = props.pending == true
		local function fire()
			if waits and b:GetAttribute("Pending") then
				return -- one request at a time
			end
			Kit.bounce(b)
			Kit.Clicked:Fire()
			if waits then
				Kit.pending(b)
			end
			onClick()
		end
		Kit.tapGuard(b, fire)
	end
	return b
end

-- Every tap counts once (nate's playtest 2026-11-19: "so many buttons are extremely unreliable, next button in
-- character creator still requires me to keep hitting it"). Activated is the tap, but a press can also end
-- with no Activated (the engine drops it when the screen under the cursor changes mid-press: a hover that
-- rebuilds the hero, a redraw). So a press that begins on the button and ends on it, without moving more than
-- Config.Ui.tap.slop pixels and with the button where it was (not a scroll), also counts, after
-- Config.Ui.tap.wait seconds if no Activated came for it. Each press fires once, whichever arrives first.
local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end
Kit.TAPS = { fallback = 0 } -- how many taps the fallback saved (the Dev panel, tests)

function Kit.tapGuard(b: GuiButton, fire: () -> ())
	local TAP = Config.Ui.tap
	local press: { input: InputObject, at: Vector3, from: Vector2, done: boolean }? = nil
	b.InputBegan:Connect(function(input)
		if isPress(input) then
			press = { input = input, at = input.Position, from = b.AbsolutePosition, done = false }
		end
	end)
	b.Activated:Connect(function()
		local p = press
		if p and p.done then
			press = nil -- the fallback already counted this press
			return
		end
		if p then
			p.done = true
		end
		fire()
	end)
	b.InputEnded:Connect(function(input)
		local p = press
		if
			not p
			or not isPress(input)
			or (input ~= p.input and input.UserInputType ~= p.input.UserInputType)
		then
			return
		end
		if p.done then
			press = nil -- Activated counted it
			return
		end
		local moved = (input.Position - p.at).Magnitude > TAP.slop
			or (b.AbsolutePosition - p.from).Magnitude > TAP.slop
		if moved then
			press = nil -- a drag or a scroll, not a tap
			return
		end
		task.delay(TAP.wait, function()
			if press ~= p then
				return -- a new press began
			end
			press = nil
			if p.done or not b.Parent or not shown(b) or not b.Active or not b.Interactable then
				return
			end
			p.done = true
			Kit.TAPS.fallback += 1
			fire()
		end)
	end)
end

-- Pending state (spec: "every remote call has a pending state under 150 ms"): the button shows "..." at
-- once and takes no more taps until the server answers (any profile sync, notice or toast settles it, and
-- most screens redraw). No answer in 5 s shows TRY AGAIN, the error state, and the button takes a tap again at
-- once (2026-11-19: it used to stay locked 1.6 s more under TRY AGAIN, so the tap it asked for did nothing;
-- one of the "keep hitting it" buttons); its own text comes back after 1.6 s.
-- Each wait is tagged with its own number, so an earlier tap's timer (settled, then tapped again) never
-- shows TRY AGAIN or unlocks the button before the new tap's answer.
local pendingButtons: { [TextButton]: { text: string, tag: number } } = setmetatable({}, { __mode = "k" }) :: any
local retryText: { [TextButton]: { text: string, tag: number } } = setmetatable({}, { __mode = "k" }) :: any
local pendingTag = 0
function Kit.pending(b: TextButton, timeout: number?)
	if pendingButtons[b] then
		return
	end
	pendingTag += 1
	local tag = pendingTag
	-- a tap on TRY AGAIN: the button's own text is the one from before
	local text = if retryText[b] then retryText[b].text else b.Text
	retryText[b] = nil
	pendingButtons[b] = { text = text, tag = tag }
	b:SetAttribute("Pending", true)
	b.Text = "..."
	task.delay(timeout or 5, function()
		local p = pendingButtons[b]
		if p and p.tag == tag and b.Parent ~= nil then
			pendingButtons[b] = nil
			b:SetAttribute("Pending", nil)
			b.Text = "TRY AGAIN"
			retryText[b] = { text = text, tag = tag }
			task.delay(1.6, function()
				local r = retryText[b]
				if r and r.tag == tag then
					retryText[b] = nil
					b.Text = text
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
