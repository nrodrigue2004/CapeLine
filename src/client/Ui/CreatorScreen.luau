-- CreatorScreen: "Who are you?" (spec: Screens > Creator "9 tabs, live hero, 3 color slots, title and noun
-- wheels, Hero or Villain toggle, class and set pickers | Done needs a title and noun and a class;
-- Randomize; saves on Done via Hero.Create"). nate's anime additions add the Hair and Eyes tabs, coats,
-- scarves and wraps, the hair colour and the Comic or Anime pick; skin tone sits with the colours.
-- * A live hero turns in the middle (Preview: the same LookKit the server uses).
-- * Piece tabs show every piece: owned ones tap to wear, locked ones say how to get them (a level, a rank,
--   a boss, a mission, a pack in the shop). Optional tabs have a NONE tile.
-- * COLORS: primary, secondary, accent, hair and skin. NAME: a Title and a Noun from two wheels, never typed;
--   blocked pairs are refused here and on the server. HERO: Hero or Villain (new heroes only), class,
--   the starting set (Volt or Blade, new heroes only) and the Comic or Anime effect style.
-- * RANDOMIZE fills everything from what you own. DONE sends Hero.Create and waits for the answer.
-- Modes: "create" (Suit Up), "first" (a hero made before the creator), "edit" (HQ or a safehouse).
-- PLACEHOLDER look until the UI pass (M10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))

local Kit = require(script.Parent.Kit)
local Preview = require(script.Parent.Preview)
local State = require(script.Parent.Parent.State)

local CreatorScreen = {}

local C = Config.Creator
local T = Config.Ui.touchTarget
local OPTIONAL =
	{ back = true, head = true, hands = true, feet = true, aura = true, hair = true, eyes = true }
local EXTRA_TABS =
	{ { id = "colors", name = "Colors" }, { id = "name", name = "Name" }, { id = "hero", name = "Hero" } }
local REASONS = {
	locked = "That piece is not unlocked yet",
	piece = "That piece does not exist",
	color = "Pick colours from the palette",
	name = "Pick another name pair",
	pick = "Pick a class",
	look = "Something went wrong: try again",
	scene = "Finish what you are doing first",
	combat = "Not during a fight",
	safehouse = "Change your look at HQ or a safehouse",
}

local gui: ScreenGui
local panel: Frame
local tabRow: ScrollingFrame
local grid: ScrollingFrame
local nameLabel: TextLabel
local doneButton: TextButton
local cancelButton: TextButton
local status: TextLabel
local preview: Preview.Handle

local mode = "edit"
local look: LookCodec.Look = CreatorRules.defaultLook(Config)
local titleId, nounId, classIdx, sideIdx, setIdx = 0, 0, 0, 1, 1
local tab = "suit"
local colorSlot = 1 -- 1 primary, 2 secondary, 3 accent, 4 hair, 5 skin
local pending = false
local inHq = false -- opened at the HQ (class changes are allowed there)
local rng = Rng.new(os.time() % 100000 + 3)

local function profileView(): any
	-- the client's copy of the unlocks (the server checks again)
	local bits = {}
	for _, id in State.profile.pieces or {} do
		bits[id] = true
	end
	return bits
end

local function owned(p: CreatorRules.Piece, bits: { [number]: boolean }): boolean
	return p.source.kind == "free" or bits[p.id] == true
end

local function sourceText(p: CreatorRules.Piece): string
	local s = p.source
	local k = s.kind
	if k == "lvl" then
		return "Level " .. (s.n or 0)
	elseif k == "rep" then
		return (if s.a == "league" then "League" elseif s.a == "syndicate" then "Syndicate" else "City")
			.. " rank "
			.. (s.n or 0)
	elseif k == "fame" then
		return "Fame rank " .. (s.n or 0)
	elseif k == "boss" then
		local b = Config.Boss.bosses[s.a or ""]
		local tier = ({ "join", "contributor", "MVP" })[s.n or 1]
		return (if b then b.name else "World boss") .. ": " .. tier
	elseif k == "mission" then
		local m = Config.Story.missions[s.n or 0]
		return "Mission: " .. (if m then m.name else "?")
	elseif k == "quest" then
		local q = Config.Story.quests[s.n or 0]
		return "Side quest: " .. (if q then q.npc else "?")
	elseif k == "legacy" then
		return "Legacy rank " .. (s.n or 0)
	elseif k == "drop" then
		return "Epic drops"
	elseif k == "pack" then
		local pk = Config.Shop.packs[s.n or 0]
		return "Pack: " .. (if pk then pk.name else "?")
	elseif k == "starter" then
		return "Starter pack"
	end
	return ""
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function clearGrid()
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local refresh: () -> ()

local function tile(
	order: number,
	text: string,
	sub: string?,
	on: boolean,
	locked: boolean,
	onClick: () -> ()
)
	local b = Kit.button({
		Text = "",
		LayoutOrder = order,
		BackgroundColor3 = if on then Kit.color.gold elseif locked then Kit.color.muted else Kit.color.paper,
		AutoButtonColor = not locked,
	}, onClick)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0.6, 0),
		TextColor3 = if locked then Kit.color.paper else Kit.color.ink,
		Font = Kit.bodyFont,
		maxText = 16,
	})
	l.Parent = b
	if sub then
		local s = Kit.label({
			Text = sub,
			Size = UDim2.new(1, 0, 0.4, 0),
			Position = UDim2.fromScale(0, 0.6),
			TextColor3 = if locked then Kit.color.gold else Kit.color.ink,
			Font = Kit.bodyFont,
			maxText = 12,
		})
		s.Parent = b
	end
	b.Parent = grid
	return b
end

local function heroName(): string
	return CreatorRules.heroName(Config, titleId, nounId) or "PICK A NAME"
end

local function canFinish(): (boolean, string?)
	if titleId == 0 or nounId == 0 then
		return false, "Pick a Title and a Noun"
	end
	if not CreatorRules.nameOk(Config, titleId, nounId) then
		return false, REASONS.name
	end
	if classIdx == 0 then
		return false, "Pick a class"
	end
	return true, nil
end

local function drawPieces()
	local bits = profileView()
	local list = CreatorRules.index(Config).byTab[tab] or {}
	local cur = look.pieces[tab] or 0
	local order = 0
	if OPTIONAL[tab] or tab == "emblem" then
		order += 1
		tile(order, "NONE", nil, cur == 0, false, function()
			look.pieces[tab] = 0
			refresh()
		end)
	end
	for _, p in list do
		order += 1
		local have = owned(p, bits)
		tile(order, p.name, if have then nil else sourceText(p), cur == p.index, not have, function()
			if have then
				look.pieces[tab] = p.index
				refresh()
			else
				status.Text = p.name .. ": " .. sourceText(p)
			end
		end)
	end
end

local function swatch(order: number, color: Color3, on: boolean, onClick: () -> ())
	local b = Kit.button(
		{ Text = if on then "✓" else "", LayoutOrder = order, BackgroundColor3 = color },
		onClick
	)
	Kit.stroke(b, if on then Kit.color.gold else Kit.color.ink, if on then 4 else 2)
	b.Parent = grid
end

local function drawColors()
	local names = { "PRIMARY", "SECONDARY", "ACCENT", "HAIR", "SKIN" }
	for i, n in names do
		tile(i, n, nil, colorSlot == i, false, function()
			colorSlot = i
			refresh()
		end)
	end
	local current = if colorSlot <= 3
		then look.colors[colorSlot]
		elseif colorSlot == 4 then look.hair
		else look.skin
	local list = if colorSlot == 5 then C.skins else C.palette
	for i, c in list do
		swatch(10 + i, rgb(c), current == i, function()
			if colorSlot <= 3 then
				look.colors[colorSlot] = i
			elseif colorSlot == 4 then
				look.hair = i
			else
				look.skin = i
			end
			refresh()
		end)
	end
end

local function drawName()
	local order = 0
	order += 1
	tile(order, "TITLE", nil, false, true, function() end)
	for i, t in C.titles do
		order += 1
		tile(order, t, nil, titleId == i, false, function()
			titleId = i
			refresh()
		end)
	end
	order += 1
	tile(order, "NOUN", nil, false, true, function() end)
	for i, n in C.nouns do
		order += 1
		local blocked = titleId > 0 and not CreatorRules.nameOk(Config, titleId, i)
		tile(order, n, if blocked then "taken" else nil, nounId == i, blocked, function()
			if not blocked then
				nounId = i
				refresh()
			end
		end)
	end
end

local function drawHero()
	local order = 0
	local creating = mode == "create"
	for i, label in { "HERO", "VILLAIN" } do
		order += 1
		tile(
			order,
			label,
			if creating then nil else "set by your story",
			sideIdx == i,
			not creating,
			function()
				if creating then
					sideIdx = i
					refresh()
				end
			end
		)
	end
	local classOk = mode ~= "edit" or inHq
	for i, id in Config.Classes.order do
		order += 1
		tile(
			order,
			string.upper(id),
			Config.Classes[id].role,
			classIdx == i,
			not classOk and classIdx ~= i,
			function()
				if classOk then
					classIdx = i
					refresh()
				else
					status.Text = "Change class at your HQ"
				end
			end
		)
	end
	for i, set in C.startSets do
		order += 1
		tile(
			order,
			string.upper(set),
			if creating then "starting powers" else "your start",
			setIdx == i,
			not creating,
			function()
				if creating then
					setIdx = i
					refresh()
				end
			end
		)
	end
	for i, style in { "COMIC", "ANIME" } do
		order += 1
		tile(
			order,
			style,
			"effect style",
			(look.anime and i == 2) or (not look.anime and i == 1),
			false,
			function()
				look.anime = i == 2
				refresh()
			end
		)
	end
end

refresh = function()
	clearGrid()
	for _, b in tabRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == tab then Kit.color.gold else Kit.color.paper
		end
	end
	if tab == "colors" then
		drawColors()
	elseif tab == "name" then
		drawName()
	elseif tab == "hero" then
		drawHero()
	else
		drawPieces()
	end
	nameLabel.Text = string.upper(heroName())
	local ok, why = canFinish()
	doneButton.BackgroundColor3 = if ok and not pending then Kit.color.gold else Kit.color.muted
	if not pending then
		status.Text = if ok then Players.LocalPlayer.DisplayName else (why or "")
	end
	preview.set(look)
end

local function finish()
	local ok, why = canFinish()
	if not ok then
		status.Text = why or ""
		return
	end
	if pending then
		return
	end
	pending = true
	status.Text = "Saving..."
	Net.send("HeroCreate", LookCodec.encode(look), sideIdx, classIdx, setIdx, titleId, nounId)
	refresh()
end

local function randomize()
	-- CreatorRules reads profile.pieces as a bitset: rebuild one from the client's id list
	local words = table.create(8, 0)
	for id in profileView() do
		local k = id // 32 + 1
		if words[k] then
			words[k] = bit32.bor(words[k], bit32.lshift(1, id % 32))
		end
	end
	local l, t, n = CreatorRules.randomize(Config, { pieces = words }, rng)
	look = l
	titleId, nounId = t, n
	if mode ~= "edit" or inHq then
		classIdx = rng:int(1, #Config.Classes.order)
	end
	refresh()
end

local function build()
	gui = Kit.screen("Creator", 20)
	gui.Enabled = false
	panel = Kit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.color.night,
		round = false,
	})
	panel.Parent = gui
	local title = Kit.label({
		Text = "WHO ARE YOU?",
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 6),
		TextColor3 = Kit.color.gold,
		maxText = 36,
	})
	title.Parent = panel
	preview = Preview.new(panel, UDim2.new(0.38, 0, 1, -170), UDim2.fromOffset(10, 50))
	nameLabel = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(0.38, 0, 0, 34),
		Position = UDim2.new(0, 10, 1, -110),
		TextColor3 = Kit.color.paper,
		maxText = 30,
	})
	nameLabel.Parent = panel
	status = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(0.38, 0, 0, 20),
		Position = UDim2.new(0, 10, 1, -88),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 16,
	})
	status.Parent = panel
	tabRow = Instance.new("ScrollingFrame")
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.new(0.6, -10, 0, T + 8)
	tabRow.Position = UDim2.new(0.4, 0, 0, 50)
	tabRow.ScrollingDirection = Enum.ScrollingDirection.X
	tabRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabRow.CanvasSize = UDim2.new()
	tabRow.ScrollBarThickness = 4
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = tabRow
	local order = 0
	local function addTab(id: string, name: string)
		order += 1
		local b = Kit.button({
			Name = id,
			Text = string.upper(name),
			Size = UDim2.fromOffset(110, T),
			LayoutOrder = order,
			BackgroundColor3 = Kit.color.paper,
			maxText = 18,
		}, function()
			tab = id
			refresh()
		end)
		b.Parent = tabRow
	end
	for _, t in C.tabs do
		addTab(t.id, t.name)
	end
	for _, t in EXTRA_TABS do
		addTab(t.id, t.name)
	end
	grid = Instance.new("ScrollingFrame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(0.6, -10, 1, -(50 + T + 16 + T + 30))
	grid.Position = UDim2.new(0.4, 0, 0, 50 + T + 14)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollBarThickness = 6
	grid.Parent = panel
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(128, T + 14)
	g.CellPadding = UDim2.fromOffset(8, 8)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grid
	local rand = Kit.button({
		Text = "RANDOMIZE",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(170, T),
		Position = UDim2.new(0, 10, 1, -24),
		BackgroundColor3 = Kit.color.paper,
	}, randomize)
	rand.Parent = panel
	cancelButton = Kit.button({
		Text = "CANCEL",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(150, T),
		Position = UDim2.new(1, -200, 1, -24),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		CreatorScreen.close()
	end)
	cancelButton.Parent = panel
	doneButton = Kit.button({
		Text = "DONE",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(170, T),
		Position = UDim2.new(1, -16, 1, -24),
	}, finish)
	doneButton.Parent = panel
end

-- opts: { mode, side, classIdx }
function CreatorScreen.open(opts: { [string]: any })
	mode = opts.mode or "edit"
	pending = false
	local p = State.profile
	look = LookCodec.read(p.look) or CreatorRules.defaultLook(Config)
	look.anime = State.hero.fxStyle == "Anime"
	titleId, nounId = p.titleId or 0, p.nounId or 0
	sideIdx = if (opts.side or State.hero.side) == "villain" then 2 else 1
	classIdx = if mode == "create"
		then 0
		else (opts.classIdx or table.find(Config.Classes.order, State.hero.classId) or 1)
	setIdx = table.find(C.startSets, p.startSet or "Volt") or 1
	inHq = opts.hq == true
	tab = "suit"
	cancelButton.Visible = mode == "edit"
	gui.Enabled = true
	refresh()
end

function CreatorScreen.close()
	gui.Enabled = false
	pending = false
end

-- close only if it is open in this mode (the opening's Suit Up ending)
function CreatorScreen.closeMode(m: string)
	if gui.Enabled and mode == m then
		CreatorScreen.close()
	end
end

function CreatorScreen.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function CreatorScreen.init()
	build()
	Net.listen("CreatorOpen", function(data)
		CreatorScreen.open(data)
	end)
	Net.listen("CreatorResult", function(data)
		pending = false
		if data.ok then
			CreatorScreen.close()
		else
			status.Text = REASONS[data.reason] or "Try again"
			refresh()
			status.Text = REASONS[data.reason] or "Try again"
		end
	end)
	State.ProfileChanged:Connect(function()
		if gui.Enabled and not pending then
			refresh()
		end
	end)
end

return CreatorScreen
