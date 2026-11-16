-- GearScreen: the GEAR screen (spec: Stats, gear, loot and upgrades; Style collection; Drops "odds are shown
-- in the Loot Info screen"). Three tabs:
-- * STASH: the 8 slots with what is worn, the stash filtered by slot, and a card for the picked piece with
--   EQUIP or TAKE OFF, UPGRADE (Lumen Dust), RETUNE a bonus stat (Credits) and SALVAGE (one, or every
--   unworn Common at once).
-- * STYLES: every gear style by slot; unlocked ones can be shown over any gear in that slot.
-- * LOOT INFO: the drop odds per source, the pity rules and this player's pity counters.
-- Opens with the GEAR button, I on a keyboard, or Select on a gamepad. Every button only asks; the server
-- checks and answers with a notice. PLACEHOLDER look until the UI pass (M10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GearMath = require(Shared:WaitForChild("GearMath"))
local LootTable = require(Shared:WaitForChild("LootTable"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local GearScreen = {}

local G = Config.Gear
local gui: ScreenGui
local panel: Frame
local header: TextLabel
local wallet: TextLabel
local noticeLabel: TextLabel
local pages: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local slotButtons: { TextButton } = {}
local stashList: ScrollingFrame
local card: Frame
local cardTitle: TextLabel
local cardBody: TextLabel
local cardButtons: Frame
local stylesList: ScrollingFrame
local lootList: ScrollingFrame

local tab = "STASH"
local slotFilter = 0 -- 0 = every slot
local picked: number? = nil -- piece id
local styleSlot = 1

local REASONS = {
	["wrong slot"] = "That piece goes in another slot",
	level = "Your level is too low for that item level",
	["worn by another hero"] = "Another of your heroes wears it",
	worn = "Take it off before salvaging",
	dust = "Not enough Lumen Dust",
	credits = "Not enough Credits",
	locked = "Locked",
	max = "Already +10",
	gadget = "Gadgets cannot be upgraded",
	["not owned"] = "That piece is gone",
	count = "Pick 1 to 20 pieces",
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function notice(text: string, good: boolean?)
	noticeLabel.Text = text
	noticeLabel.TextColor3 = if good then Color3.fromRGB(120, 230, 140) else Color3.fromRGB(255, 150, 120)
	Kit.pulse(noticeLabel, 0.08)
end

-- "Rare Coil Gauntlets", "Epic Stormcaller Head", "Uncommon Smoke Bomb"
function GearScreen.pieceName(piece: any): string
	local tier = GearMath.tierName(Config, piece)
	if piece.gadget > 0 then
		return tier .. " " .. G.gadgets[G.gadgetOrder[piece.gadget]].name
	end
	local row = GearMath.styleRow(Config, piece.style)
	local slot = G.slots[GearMath.slotName(Config, piece)].name
	return tier .. " " .. (if row then row.name else slot)
end

local function tierColor(piece: any): Color3
	return rgb(G.tiers[GearMath.tierName(Config, piece)].color)
end

local function find(id: number?): any?
	if not id then
		return nil
	end
	for _, p in State.profile.stash do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function isWorn(id: number): boolean
	return table.find(State.profile.equipment, id) ~= nil
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function listFrame(parent: Instance, pos: UDim2, size: UDim2, cell: UDim2?): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Position = pos
	s.Size = size
	s.ScrollBarThickness = 6
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	if cell then
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = cell
		gl.CellPadding = UDim2.fromOffset(6, 6)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = s
	else
		local ll = Instance.new("UIListLayout")
		ll.Padding = UDim.new(0, 6)
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = s
	end
	s.Parent = parent
	return s
end

---------------------------------------------------------------------------
-- STASH
---------------------------------------------------------------------------

local function cardButton(text: string, color: Color3, fn: () -> ())
	local b = Kit.button(
		{ Text = text, Size = UDim2.new(0.5, -4, 0, 40), BackgroundColor3 = color, maxText = 15 },
		fn
	)
	b.Parent = cardButtons
end

local function refreshCard()
	clear(cardButtons)
	local piece = find(picked)
	if not piece then
		cardTitle.Text = "Pick a piece"
		cardTitle.TextColor3 = Kit.color.paper
		cardBody.Text =
			"Gear gives stats. Looks are separate: any style you have unlocked can show over any gear (STYLES)."
		return
	end
	cardTitle.Text = GearScreen.pieceName(piece) .. (if piece.up > 0 then " +" .. piece.up else "")
	cardTitle.TextColor3 = tierColor(piece)
	local lines = GearMath.describe(Config, piece)
	table.insert(
		lines,
		1,
		string.format("Item level %d  |  Budget %d", piece.ilvl, GearMath.budget(Config, piece))
	)
	if not GearMath.canWear(Config, State.hero.level, piece) then
		table.insert(lines, string.format("Needs level %d", piece.ilvl - G.equipSlack))
	end
	if piece.retunes > 0 then
		table.insert(lines, string.format("Retuned %d / %d", piece.retunes, G.retune.max))
	end
	cardBody.Text = table.concat(lines, "\n")
	local worn = isWorn(piece.id)
	if worn then
		cardButton("TAKE OFF", Kit.color.paper, function()
			Net.send("GearEquip", 0, piece.slot)
		end)
	else
		cardButton("EQUIP", Color3.fromRGB(120, 230, 140), function()
			Net.send("GearEquip", piece.id, piece.slot)
		end)
	end
	local cost = GearMath.upgradeCost(Config, piece)
	if cost and piece.gadget == 0 then
		cardButton(string.format("UPGRADE %d DUST", cost), Kit.color.gold, function()
			Net.send("GearUpgrade", piece.id)
		end)
	end
	if piece.retunes < G.retune.max then
		for i, b in piece.bonus do
			cardButton(
				string.format(
					"RETUNE %s %d CR",
					string.upper(G.stats[b[1]]),
					GearMath.retuneCost(Config, piece)
				),
				Color3.fromRGB(170, 200, 255),
				function()
					Net.send("GearRetune", piece.id, i)
				end
			)
		end
	end
	if not worn then
		cardButton(
			string.format("SALVAGE +%d DUST", GearMath.salvageValue(Config, piece)),
			Color3.fromRGB(255, 150, 120),
			function()
				Net.send("GearSalvage", { piece.id })
				picked = nil
			end
		)
	end
end

local function refreshStash()
	for i, b in slotButtons do
		local slot = G.slotOrder[i]
		local worn = find(State.profile.equipment[i])
		b.Text = string.upper(G.slots[slot].name)
			.. "\n"
			.. (if worn then GearScreen.pieceName(worn) else "empty")
		b.BackgroundColor3 = if worn then tierColor(worn) else Kit.color.paper
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if slotFilter == i then 3 else 0
		end
	end
	clear(stashList)
	local list = {}
	for _, p in State.profile.stash do
		if slotFilter == 0 or p.slot == slotFilter then
			table.insert(list, p)
		end
	end
	-- best first: tier, then budget
	table.sort(list, function(a, b)
		if a.tier ~= b.tier then
			return a.tier > b.tier
		end
		return GearMath.budget(Config, a) > GearMath.budget(Config, b)
	end)
	for i, p in list do
		local b = Kit.button({
			Text = string.format(
				"%s%s\nilvl %d%s",
				GearScreen.pieceName(p),
				if p.up > 0 then " +" .. p.up else "",
				p.ilvl,
				if isWorn(p.id) then "  WORN" else ""
			),
			BackgroundColor3 = tierColor(p),
			LayoutOrder = i,
			maxText = 14,
		}, function()
			picked = p.id
			refreshCard()
		end)
		b.Parent = stashList
	end
	if #list == 0 then
		local empty = Kit.label({
			Text = "Nothing here yet. Gear drops from incidents, contracts, events, missions and world bosses.",
			Size = UDim2.new(1, 0, 0, 60),
			TextColor3 = Kit.color.muted,
			Font = Kit.bodyFont,
			TextWrapped = true,
			maxText = 14,
		})
		empty.Parent = stashList
	end
	refreshCard()
end

---------------------------------------------------------------------------
-- STYLES and LOOT INFO
---------------------------------------------------------------------------

local styleTabs: { TextButton } = {}

local function refreshStyles()
	for i, b in styleTabs do
		b.BackgroundColor3 = if i == styleSlot then Kit.color.gold else Kit.color.paper
	end
	clear(stylesList)
	local owned = {}
	for _, id in State.profile.styles do
		owned[id] = true
	end
	local shown = State.profile.shown[styleSlot] or 0
	local own = Kit.button({
		Text = "SHOW MY GEAR'S OWN LOOK",
		BackgroundColor3 = if shown == 0 then Color3.fromRGB(120, 230, 140) else Kit.color.paper,
		LayoutOrder = 0,
		maxText = 14,
	}, function()
		Net.send("StyleApply", styleSlot, 0)
	end)
	own.Parent = stylesList
	local order = 1
	for _, id in GearMath.allStyles(Config) do
		local slotIdx = GearMath.styleParts(id)
		if slotIdx == styleSlot then
			local row = GearMath.styleRow(Config, id)
			local have = owned[id] == true
			local b = Kit.button({
				Text = (if row then row.name else "?") .. (if have then "" else "  (locked)"),
				BackgroundColor3 = if shown == id
					then Color3.fromRGB(120, 230, 140)
					elseif have then Kit.color.paper
					else Color3.fromRGB(90, 94, 108),
				AutoButtonColor = have,
				LayoutOrder = order,
				maxText = 14,
			}, function()
				if have then
					Net.send("StyleApply", styleSlot, id)
				else
					notice("Loot a piece with this style to unlock it")
				end
			end)
			order += 1
			b.Parent = stylesList
		end
	end
end

local function refreshLoot()
	clear(lootList)
	for i, row in LootTable.infoRows(Config) do
		local l = Kit.label({
			Text = row[1] .. ": " .. row[2],
			Size = UDim2.new(1, -8, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Kit.color.paper,
			Font = Kit.bodyFont,
			TextWrapped = true,
			LayoutOrder = i,
			maxText = 14,
		})
		l.Parent = lootList
	end
	local p = State.profile.pity or { epic = 0, legendary = 0 }
	local mine = Kit.label({
		Text = string.format(
			"Your pity: %d of %d bosses without an Epic, %d of %d MVP rolls without a Legendary",
			p.epic,
			Config.Loot.pity.epic,
			p.legendary,
			Config.Loot.pity.legendary
		),
		Size = UDim2.new(1, -8, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		Font = Kit.bodyFont,
		TextWrapped = true,
		LayoutOrder = 100,
		maxText = 14,
	})
	mine.Parent = lootList
end

local function refresh()
	if not panel.Visible then
		return
	end
	local c = State.profile.currency or { credits = 0, banked = 0, dust = 0 }
	wallet.Text = string.format(
		"GEAR SCORE %d   CREDITS %s (+%s BANKED)   DUST %s   STASH %d/%d",
		State.hero.gearScore or 0,
		Kit.comma(c.credits),
		Kit.comma(c.banked),
		Kit.comma(c.dust),
		#State.profile.stash,
		G.stashCap
	)
	for name, page in pages do
		page.Visible = name == tab
		tabButtons[name].BackgroundColor3 = if name == tab then Kit.color.gold else Kit.color.paper
	end
	if tab == "STASH" then
		refreshStash()
	elseif tab == "STYLES" then
		refreshStyles()
	else
		refreshLoot()
	end
end

function GearScreen.open()
	panel.Visible = true
	refresh()
end

function GearScreen.close()
	panel.Visible = false
end

function GearScreen.toggle()
	if panel.Visible then
		GearScreen.close()
	else
		GearScreen.open()
	end
end

function GearScreen.isOpen(): boolean
	return panel.Visible
end

function GearScreen.init()
	gui = Kit.screen("Gear", 5)
	panel = Kit.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.92, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(980, 720)
	limit.Parent = panel
	panel.Parent = gui
	header = Kit.label({
		Text = "GEAR",
		Size = UDim2.new(0.3, 0, 0, 34),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 30,
	})
	header.Parent = panel
	wallet = Kit.label({
		Text = "",
		Size = UDim2.new(1, -100, 0, 20),
		Position = UDim2.fromOffset(14, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 14,
	})
	wallet.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(Config.Ui.touchTarget, Config.Ui.touchTarget - 10),
		Position = UDim2.new(1, -Config.Ui.touchTarget - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, GearScreen.close)
	close.Parent = panel
	-- tabs
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(0.6, 0, 0, 36)
	tabs.Position = UDim2.new(0.3, 0, 0, 6)
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabs
	tabs.Parent = panel
	for _, name in { "STASH", "STYLES", "LOOT INFO" } do
		local b = Kit.button({ Text = name, Size = UDim2.new(0.31, 0, 1, 0), maxText = 16 }, function()
			tab = name
			refresh()
		end)
		b.Parent = tabs
		tabButtons[name] = b
		local page = Instance.new("Frame")
		page.Name = name
		page.BackgroundTransparency = 1
		page.Size = UDim2.new(1, -20, 1, -112)
		page.Position = UDim2.fromOffset(10, 70)
		page.Parent = panel
		pages[name] = page
	end
	-- STASH page: slots on the left, list in the middle, card on the right
	local stash = pages.STASH
	local slots = listFrame(stash, UDim2.fromScale(0, 0), UDim2.new(0.22, -6, 1, 0))
	local all = Kit.button(
		{ Text = "ALL SLOTS", Size = UDim2.new(1, -8, 0, 36), LayoutOrder = 0, maxText = 14 },
		function()
			slotFilter = 0
			refresh()
		end
	)
	all.Parent = slots
	for i, slot in G.slotOrder do
		local b = Kit.button({
			Text = G.slots[slot].name,
			Size = UDim2.new(1, -8, 0, 48),
			LayoutOrder = i,
			maxText = 13,
		}, function()
			slotFilter = i
			refresh()
		end)
		Kit.stroke(b, Kit.color.gold, 0)
		b.Parent = slots
		slotButtons[i] = b
	end
	stashList =
		listFrame(stash, UDim2.new(0.22, 0, 0, 0), UDim2.new(0.42, -6, 1, -48), UDim2.new(0.5, -6, 0, 56))
	local junk = Kit.button({
		Text = "SALVAGE UNWORN COMMONS",
		Size = UDim2.new(0.42, -6, 0, 40),
		Position = UDim2.new(0.22, 0, 1, -42),
		BackgroundColor3 = Color3.fromRGB(255, 150, 120),
		maxText = 14,
	}, function()
		local ids = {}
		for _, p in State.profile.stash do
			if p.tier == 1 and not isWorn(p.id) and #ids < G.salvage.maxPerRequest then
				table.insert(ids, p.id)
			end
		end
		if #ids == 0 then
			notice("No unworn Common pieces")
			return
		end
		Net.send("GearSalvage", ids)
	end)
	junk.Parent = stash
	card = Kit.frame({
		Size = UDim2.new(0.36, 0, 1, 0),
		Position = UDim2.fromScale(0.64, 0),
		BackgroundColor3 = Color3.fromRGB(30, 34, 50),
	})
	card.Parent = stash
	cardTitle = Kit.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.fromOffset(8, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 22,
	})
	cardTitle.Parent = card
	cardBody = Kit.label({
		Text = "",
		Size = UDim2.new(1, -16, 0.55, -40),
		Position = UDim2.fromOffset(8, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 15,
	})
	cardBody.Parent = card
	cardButtons = Instance.new("Frame")
	cardButtons.BackgroundTransparency = 1
	cardButtons.Size = UDim2.new(1, -16, 0.45, -8)
	cardButtons.Position = UDim2.new(0, 8, 0.55, 0)
	local cg = Instance.new("UIGridLayout")
	cg.CellSize = UDim2.new(0.5, -4, 0, 40)
	cg.CellPadding = UDim2.fromOffset(6, 6)
	cg.Parent = cardButtons
	cardButtons.Parent = card
	-- STYLES page
	local styles = pages.STYLES
	local stabs = Instance.new("Frame")
	stabs.BackgroundTransparency = 1
	stabs.Size = UDim2.new(1, 0, 0, 40)
	local stl = Instance.new("UIListLayout")
	stl.FillDirection = Enum.FillDirection.Horizontal
	stl.Padding = UDim.new(0, 4)
	stl.Parent = stabs
	stabs.Parent = styles
	for i, slot in G.slotOrder do
		if G.slots[slot].main then
			local b = Kit.button(
				{ Text = G.slots[slot].name, Size = UDim2.new(1 / 7, -4, 1, 0), maxText = 14 },
				function()
					styleSlot = i
					refresh()
				end
			)
			b.Parent = stabs
			styleTabs[i] = b
		end
	end
	stylesList =
		listFrame(styles, UDim2.fromOffset(0, 48), UDim2.new(1, 0, 1, -48), UDim2.new(0.33, -6, 0, 48))
	-- LOOT INFO page
	lootList = listFrame(pages["LOOT INFO"], UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	noticeLabel = Kit.label({
		Text = "",
		Size = UDim2.new(1, -28, 0, 26),
		Position = UDim2.new(0, 14, 1, -36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.muted,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	noticeLabel.Parent = panel

	InputController.Pressed:Connect(function(action)
		if action == "Gear" then
			GearScreen.toggle()
		end
	end)
	State.ProfileChanged:Connect(refresh)
	State.Changed:Connect(refresh)
	State.Toast:Connect(function(data)
		if data.id == "gear" then
			if data.ok then
				notice("Done", true)
			else
				notice(REASONS[data.reason or ""] or ("Not allowed: " .. tostring(data.reason)))
			end
		end
	end)
end

return GearScreen
