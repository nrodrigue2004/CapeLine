-- ShopHud: the Robux shop (spec: Screens > Robux Shop "Packs, Effects, Emotes, Passes, Slots, a preview on
-- the hero, owned items marked"; Revenue levers; Pay-to-win check). Opens with SHOP (P) at HQ, a safehouse
-- or from the menu, never within 10 s of a fight (the server checks again).
-- * PACKS: costume packs, previewed on your hero. EFFECTS: colour tints over your power effects. EMOTES:
--   emotes and landing poses. PASSES: Quick Swap and 2x Credits and Renown. SLOTS: hero slots 3 and 4.
-- * Owned items say OWNED, and owned tints and landing poses can be equipped here.
-- * The starter pack offer shows once after your first world boss, with a big NO THANKS.
-- Nothing here changes a stat; only the 2x pass touches a number (earned Credits and Renown).
-- PLACEHOLDER look until the UI pass (M10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ShopRules = require(Shared:WaitForChild("ShopRules"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local TravelStyleRules = require(Shared:WaitForChild("TravelStyleRules"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))

local Kit = require(script.Parent.Kit)
local Preview = require(script.Parent.Preview)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local Telemetry = require(script.Parent.Parent.Controllers.Telemetry)

local ShopHud = {}

local S = Config.Shop
local T = Config.Ui.touchTarget
local KEYS = ShopRules.keys(Config)
local PASS_TEXT = {
	quickSwap = { "QUICK SWAP", "Change your loadout anywhere out of a fight" },
	double = { "2X CREDITS AND RENOWN", "Doubles earned Credits and Renown (never XP, loot or Dust)" },
}
local REASONS = {
	where = "Open the shop at your HQ, a safehouse or the menu",
	combat = "The shop opens 10 s after a fight",
	owned = "You already own that",
	slot3 = "Buy slot 3 first",
	soon = "Coming soon",
	item = "That is not for sale",
	save = "Saving is down on this server. Rejoin to shop",
}

local gui: ScreenGui
local panel: Frame
local tabRow: Frame
local grid: ScrollingFrame
local status: TextLabel
local preview: Preview.Handle
local offer: Frame
local tab = "packs"

-- The client's profile as ShopRules reads it (bitsets from the client view's id lists)
local function bitset(ids: { number }?, words: number): { number }
	local w = table.create(words, 0)
	for _, id in ids or {} do
		local k = id // 32 + 1
		if w[k] then
			w[k] = bit32.bor(w[k], bit32.lshift(1, id % 32))
		end
	end
	return w
end

local function profileView(): any
	local p = State.profile
	return {
		pieces = bitset(p.pieces, 8),
		emotes = bitset(p.emotes, 2),
		purchases = { passes = p.passes or {}, slots = p.slots or 0, tints = p.tints or 0, receipts = {} },
		-- H8: travel styles bought and the Hero Pass's paid track
		mmo = { travel = bitset(p.travelOwned, 1) },
		pass = { season = p.passSeason or 0, paid = p.passPaid == true },
	}
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function itemText(key: string, row: any, kind: string?): (string, string, Color3)
	if kind == "pack" then
		local pk = S.packs[row.pack]
		local names = {}
		for _, p in CreatorRules.packPieces(Config, row.pack) do
			table.insert(names, p.name)
		end
		return string.upper(pk.name), table.concat(names, ", "), rgb(pk.color)
	elseif kind == "tint" then
		local t = S.tints[row.tint]
		return string.upper(t.name) .. " EFFECTS", "A colour over every power effect", rgb(t.color)
	elseif kind == "emote" then
		local e = S.emotes[row.emote]
		return string.upper(e.name), if e.landing then "Landing pose" else "Emote", Kit.color.paper
	elseif kind == "pass" then
		local p = PASS_TEXT[key] or { key, "" }
		return p[1], p[2], Kit.color.gold
	elseif kind == "slot" then
		return string.format("HERO SLOT %d", row.slot),
			"Another hero with their own level, gear and story",
			Kit.color.paper
	elseif kind == "starter" then
		return "STARTER PACK", "Starter Cape, Chrome Finish and the Rookie Cheer emote", Kit.color.gold
	elseif kind == "travel" then
		local s = TravelStyleRules.byId(Config, row.style)
		local m = s and Config.Move.mobility[s.mobility]
		return string.upper(s and s.name or key),
			string.format("A %s travel style: trail, take-off and landing. Looks only", m and m.name or ""),
			if s then rgb(s.c1) else Kit.color.paper
	elseif kind == "heroPass" then
		local d = Config.Pass.seasons[State.profile.passSeason or 0]
		return "HERO PASS: PAID TRACK",
			string.format(
				"%s: 30 more looks on the pass (see PASS for every reward). No skips, nothing random",
				d and d.name or "This season"
			),
			Kit.color.gold
	end
	return key, "", Kit.color.paper
end

local function lookWith(pieces: { CreatorRules.Piece }): LookCodec.Look
	local look = LookCodec.read(State.profile.look) or CreatorRules.defaultLook(Config)
	for _, p in pieces do
		look.pieces[p.tab] = p.index
	end
	return look
end

local function showPreview(key: string)
	Telemetry.note("item")
	local row, kind = ShopRules.item(Config, key)
	if kind == "pack" then
		preview.set(lookWith(CreatorRules.packPieces(Config, row.pack)))
	elseif kind == "starter" then
		preview.set(lookWith(CreatorRules.packPieces(Config, nil)))
	else
		preview.set(LookCodec.read(State.profile.look) or CreatorRules.defaultLook(Config))
	end
end

local refresh: () -> ()

local function card(order: number, key: string)
	local row, kind = ShopRules.item(Config, key)
	if not row then
		return
	end
	local fake = profileView()
	local owned = ShopRules.owned(Config, fake, key)
	local can = ShopRules.available(Config, fake, key)
	local name, desc, color = itemText(key, row, kind)
	local f = Kit.frame({
		LayoutOrder = order,
		BackgroundColor3 = Kit.color.paper,
	})
	Kit.stroke(f, color, 3)
	local n = Kit.label({
		Text = name,
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.fromOffset(6, 4),
		maxText = 22,
	})
	n.Parent = f
	local d = Kit.label({
		Text = desc,
		Size = UDim2.new(1, -12, 0, 60),
		Position = UDim2.fromOffset(6, 30),
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 13,
	})
	d.Parent = f
	local equipped = (kind == "tint" and State.profile.tint == row.tint)
		or (kind == "emote" and S.emotes[row.emote].landing and State.profile.landing == row.emote)
	local text, click, bg
	if owned and kind == "tint" then
		text = if equipped then "EQUIPPED" else "EQUIP"
		click = function()
			Net.send("TintSet", if equipped then 0 else row.tint)
		end
		bg = if equipped then Kit.color.gold else Kit.color.paper
	elseif owned and kind == "emote" and S.emotes[row.emote].landing then
		text = if equipped then "EQUIPPED" else "EQUIP"
		click = function()
			Net.send("LandingSet", if equipped then 0 else row.emote)
		end
		bg = if equipped then Kit.color.gold else Kit.color.paper
	elseif owned then
		text, bg = "OWNED", Kit.color.muted
	elseif not can then
		text, bg = "LOCKED", Kit.color.muted
	else
		text = string.format("R$ %d", row.robux)
		click = function()
			status.Text = "..."
			Net.send("ShopBuy", table.find(KEYS, key))
		end
		bg = Kit.color.gold
	end
	local b = Kit.button({
		Text = text,
		pending = click ~= nil,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(1, -16, 0, T - 8),
		Position = UDim2.new(0.5, 0, 1, -6),
		BackgroundColor3 = bg,
	}, function()
		showPreview(key)
		if click then
			click()
		end
	end)
	b.Parent = f
	local look = Kit.button({
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -T),
		ZIndex = 0,
	}, function()
		showPreview(key)
	end)
	look.Parent = f
	f.Parent = grid
end

refresh = function()
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for _, b in tabRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == tab then Kit.color.gold else Kit.color.paper
		end
	end
	for _, t in S.tabs do
		if t.id == tab then
			for i, key in t.items do
				card(i, key)
			end
		end
	end
end

local function build()
	gui = Kit.screen("Shop", 18)
	gui.Enabled = false
	panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.88, 0),
		BackgroundColor3 = Kit.color.night,
	})
	Kit.stroke(panel, Kit.color.gold, 3)
	panel.Parent = gui
	Kit.fit(panel, 600, 286, 1100, 760) -- phone pass: scales down to fit a phone's safe area
	local title = Kit.label({
		Text = "SHOP",
		Size = UDim2.new(0.5, 0, 0, 38),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 34,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(120, T - 8),
		Position = UDim2.new(1, -10, 0, 8),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		ShopHud.close()
	end)
	close.Parent = panel
	preview = Preview.new(panel, UDim2.new(0.3, 0, 1, -110), UDim2.fromOffset(10, 56))
	status = Kit.label({
		Text = "Looks only: nothing here changes your stats",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(0.3, 0, 0, 36),
		Position = UDim2.new(0, 10, 1, -10),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 14,
	})
	status.Parent = panel
	tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.new(0.32, 0, 0, 58) -- phone pass: clear of CLOSE
	tabRow.Size = UDim2.new(0.68, -12, 0, T - 6)
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = tabRow
	for i, t in S.tabs do
		local b = Kit.button({
			Name = t.id,
			Text = string.upper(t.name),
			Size = UDim2.new(1 / #S.tabs, -6, 1, 0),
			LayoutOrder = i,
			BackgroundColor3 = Kit.color.paper,
		}, function()
			tab = t.id
			refresh()
		end)
		b.Parent = tabRow
	end
	grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.new(0.32, 0, 0, 58 + T)
	grid.Size = UDim2.new(0.68, -12, 1, -(66 + T))
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollBarThickness = 6
	grid.Parent = panel
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(200, 150)
	g.CellPadding = UDim2.fromOffset(10, 10)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grid

	-- the starter pack offer (once, after your first world boss)
	offer = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(360, 230),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	Kit.stroke(offer, Kit.color.gold, 3)
	offer.Parent = Kit.screen("ShopOffer", 17)
	local h = Kit.label({
		Text = "FIRST BOSS DOWN!",
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 8),
		TextColor3 = Kit.color.gold,
		maxText = 30,
	})
	h.Parent = offer
	local o = Kit.label({
		Text = string.format(
			"Starter Pack: Starter Cape, Chrome Finish and the Rookie Cheer emote. R$ %d, once.",
			S.products.starter.robux
		),
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 46),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 16,
	})
	o.Parent = offer
	local get = Kit.button({
		Text = "GET IT",
		Size = UDim2.new(0.5, -15, 0, T),
		Position = UDim2.new(0, 10, 1, -T - 10),
	}, function()
		offer.Visible = false
		Net.send("ShopBuy", table.find(KEYS, "starter"))
	end)
	get.Parent = offer
	local no = Kit.button({
		Text = "NO THANKS",
		Size = UDim2.new(0.5, -15, 0, T),
		Position = UDim2.new(0.5, 5, 1, -T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		offer.Visible = false
		Net.send("ShopDismiss")
	end)
	no.Parent = offer
end

function ShopHud.open(which: string?)
	tab = which or tab
	if not gui.Enabled then
		Telemetry.note("shop")
	end
	Kit.opening("ShopHud", gui, ShopHud.close)
	gui.Enabled = true
	status.Text = "Looks only: nothing here changes your stats"
	preview.set(LookCodec.read(State.profile.look) or CreatorRules.defaultLook(Config))
	refresh()
end

function ShopHud.close()
	gui.Enabled = false
end

function ShopHud.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function ShopHud.init()
	build()
	InputController.Pressed:Connect(function(action)
		if action == "Shop" then
			if gui.Enabled then
				ShopHud.close()
			else
				ShopHud.open()
			end
		end
	end)
	Net.listen("ShopResult", function(data)
		if data.ok then
			local name = data.key or ""
			local row, kind = ShopRules.item(Config, name)
			if row then
				name = (itemText(name, row, kind))
			end
			status.Text = "Thanks! " .. name .. " is yours"
			State.Toast:Fire({ id = "bought", name = name })
		else
			status.Text = REASONS[data.reason or ""] or "Try again later"
			if not gui.Enabled then
				State.Toast:Fire({ id = "shopRefused", reason = data.reason })
			end
		end
		if gui.Enabled then
			refresh()
		end
	end)
	Net.listen("ShopOffer", function()
		-- a card the server pops by itself (after the first world boss): it waits its turn with the other such
		-- cards (review 2026-11-18). Ui.PopupGate is required here, not at the top: it reads the main menu,
		-- which reads this shop
		local PopupGate = require(script.Parent.PopupGate) :: any
		PopupGate.card("starter", function()
			return offer.Visible
		end)
		PopupGate.later("starter", function()
			offer.Visible = true
		end)
	end)
	State.ProfileChanged:Connect(function()
		if gui.Enabled then
			refresh()
		end
	end)
end

return ShopHud
