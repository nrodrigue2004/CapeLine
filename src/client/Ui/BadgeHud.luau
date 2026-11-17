-- BadgeHud: the Badge Book, Collections and titles (spec: Hero MMO features > Badges and titles,
-- Collections; H7). The BADGES button (top row or MORE) opens a book with three tabs:
-- * BADGES: every badge by group, earned ones in colour, the rest as a grey outline with their one-line hint
--   and progress (never hidden, so there is always a next goal), and each group's accolade;
-- * COLLECTIONS: the twelve sets, how many found, where they hide and the reward (shown before you start);
-- * TITLES: the title shown under your name (one at a time, all fixed text) and the accolade aura and plate
--   trim you wear.
-- A new badge: the stamp, chime and confetti (Juice "badgeEarned").
-- PLACEHOLDER ART: Kit frames until the UI pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BadgeRules = require(Shared:WaitForChild("BadgeRules"))
local Net = require(Shared:WaitForChild("Net"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local Kit = require(script.Parent.Kit)

local BadgeHud = {}

local B = Config.Badges
local C = Config.Collect
local T = Config.Ui.touchTarget
local gui: ScreenGui
local panel: Frame
local body: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local tab = "badges"
local last: { [string]: any }? = nil
local order = 0

local WHERE = {
	ComicCovers = "On the streets of Downtown",
	LostToys = "On the streets of Old Town",
	ShipBells = "On the streets of the Docks",
	DeepRelics = "On the seabed of the open sea and the Coral Shelf",
	RoofPigeons = "On the tall roofs of Downtown and Uptown",
	CometShards = "In the outskirts; they move every Monday",
	RobotParts = "A small chance when you defeat each robot kind",
	BossPlates = "A chance when a world boss is defeated",
	NemesisCores = "Win a Showdown at each nemesis rank",
	ContestRibbons = "Costume contests: enter, vote, place, win",
	MentorKeepsakes = "Your mentors' quest lines (parts 2 and 4)",
	TaskForcePatches = "Task forces: clear, speed clear, full squad",
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function clear()
	for _, c in body:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	order = 0
end

local function line(text: string, h: number, size: number, color: Color3?, font: Enum.Font?): TextLabel
	order += 1
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, h),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Kit.color.paper,
		Font = font or Kit.bodyFont,
		TextWrapped = true,
		maxText = size,
	})
	l.LayoutOrder = order
	l.Parent = body
	return l
end

local function button(text: string, color: Color3, onClick: () -> ()): TextButton
	order += 1
	local b = Kit.button({
		Text = text,
		Size = UDim2.new(1, 0, 0, T - 10),
		BackgroundColor3 = color,
	}, onClick)
	b.LayoutOrder = order
	b.Parent = body
	return b
end

local function has(bits: { number }, bit: number): boolean
	return table.find(bits, bit) ~= nil
end

local function drawBadges(d: { [string]: any })
	local earned = #d.bits
	line(string.format("%d OF %d BADGES", earned, #BadgeRules.list(B)), 30, 24, Kit.color.gold, Kit.font)
	for _, g in B.groups do
		line(string.upper(g.name), 28, 20, Kit.color.gold, Kit.font)
		if g.accolade then
			line("Finish the group: " .. g.accolade.name, 18, 13, Kit.color.muted)
		end
		for i, b in g.badges do
			local bit = g.at + i - 1
			local got = has(d.bits, bit)
			local p = d.progress[tostring(bit)] or { 0, b.n }
			order += 1
			local row = Kit.frame({
				Size = UDim2.new(1, 0, 0, 46),
				BackgroundColor3 = if got then Kit.color.night else Color3.fromRGB(40, 40, 46),
				BackgroundTransparency = if got then 0.1 else 0.5,
			})
			Kit.stroke(row, if got then Kit.color.gold else Color3.fromRGB(110, 110, 120), 2)
			row.LayoutOrder = order
			row.Parent = body
			local name = Kit.label({
				Text = string.upper(b.name),
				Size = UDim2.new(1, -90, 0, 24),
				Position = UDim2.fromOffset(8, 2),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if got then Kit.color.gold else Color3.fromRGB(150, 150, 160),
				maxText = 18,
			})
			name.Parent = row
			local hint = Kit.label({
				Text = b.hint,
				Size = UDim2.new(1, -90, 0, 18),
				Position = UDim2.fromOffset(8, 25),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Kit.color.paper,
				Font = Kit.bodyFont,
				maxText = 13,
			})
			hint.Parent = row
			local prog = Kit.label({
				Text = if got then "DONE" else string.format("%s / %s", Kit.comma(p[1]), Kit.comma(p[2])),
				AnchorPoint = Vector2.new(1, 0.5),
				Size = UDim2.fromOffset(84, 24),
				Position = UDim2.new(1, -6, 0.5, 0),
				TextColor3 = if got then Kit.color.gold else Kit.color.muted,
				maxText = 14,
			})
			prog.Parent = row
		end
	end
end

local function drawCollections(d: { [string]: any })
	line("COLLECTIONS", 30, 24, Kit.color.gold, Kit.font)
	if d.scanner == 1 then
		line("HQ Scanner on: a marker shows your nearest missing find near you.", 20, 13, Kit.color.muted)
	else
		line(
			string.format(
				"Buy the HQ Scanner at your HQ (%s Credits) to mark finds near you.",
				Kit.comma(C.scanner.cost)
			),
			20,
			13,
			Kit.color.muted
		)
	end
	for _, s in C.sets do
		local found = 0
		for i = 1, s.count do
			if has(d.collect, s.at + i - 1) then
				found += 1
			end
		end
		local done = found >= s.count
		line(
			string.format(
				"%s  %d / %d%s",
				string.upper(s.name),
				found,
				s.count,
				if done then "  DONE" else ""
			),
			26,
			18,
			if done then Kit.color.gold else Kit.color.paper,
			Kit.font
		)
		line(WHERE[s.id] or "", 18, 13, Kit.color.muted)
		line(
			string.format(
				"Reward: %s Renown and the %s for your HQ",
				Kit.comma(s.reward.renown),
				Config.Hq.props[s.reward.prop] or "prop"
			),
			18,
			13,
			Kit.color.paper
		)
	end
end

local function drawTitles(d: { [string]: any })
	line("YOUR TITLE", 30, 24, Kit.color.gold, Kit.font)
	line("One shows under your name. Earn more from badges, the story and Fame.", 20, 13, Kit.color.muted)
	for _, t in d.titles or {} do
		local on = t.id == d.title
		button(
			(if on then "✓ " else "") .. string.upper(t.name),
			if on then Kit.color.gold else Kit.color.paper,
			function()
				Net.send("TitleSet", t.id)
			end
		)
	end
	line("ACCOLADES", 30, 24, Kit.color.gold, Kit.font)
	if #(d.accolades or {}) == 0 then
		line("Finish every badge in a group for its aura, plate trim or emote.", 20, 13, Kit.color.muted)
	end
	for _, gi in d.accolades or {} do
		local g = B.groups[gi]
		local a = g and g.accolade
		if a and a.kind ~= "emote" then
			local slot = if a.kind == "aura" then 1 else 2
			local on = (if slot == 1 then d.aura else d.trim) == gi
			button(
				string.format("%s %s (%s)", if on then "TAKE OFF" else "WEAR", string.upper(a.name), a.kind),
				if on then Kit.color.paper else rgb(a.color),
				function()
					Net.send("AccoladeWear", slot, if on then 0 else gi)
				end
			)
		elseif a then
			line(a.name .. " emote: in your emote wheel", 20, 14, Kit.color.paper)
		end
	end
end

local function draw()
	clear()
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == tab then Kit.color.gold else Kit.color.paper
	end
	local d = last
	if not d then
		Kit.stateNote(body, "loading", "Opening the book")
		return
	end
	if tab == "badges" then
		drawBadges(d)
	elseif tab == "collect" then
		drawCollections(d)
	else
		drawTitles(d)
	end
end

function BadgeHud.open(which: string?)
	tab = which or tab
	panel.Visible = true
	draw()
	Net.send("BadgeOpen")
end

function BadgeHud.close()
	panel.Visible = false
end

function BadgeHud.isOpen(): boolean
	return panel.Visible
end

function BadgeHud.init()
	gui = Kit.screen("BadgeHud", 6)
	panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.84, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 620)
	limit.Parent = panel
	panel.Parent = gui
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, T - 10),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, BadgeHud.close)
	close.Parent = panel
	for i, row in { { "badges", "BADGES" }, { "collect", "COLLECTIONS" }, { "titles", "TITLES" } } do
		local b = Kit.button({
			Text = row[2],
			Size = UDim2.new(0.3, -10, 0, T - 12),
			Position = UDim2.new((i - 1) * 0.3, 10, 0, 8),
			BackgroundColor3 = Kit.color.paper,
		}, function()
			tab = row[1]
			draw()
		end)
		b.Parent = panel
		tabButtons[row[1]] = b
	end
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, T + 6)
	scroll.Size = UDim2.new(1, -28, 1, -T - 16)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.Parent = panel
	body = scroll
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = body
	-- the top row button
	local open = Kit.button({
		Name = "BadgesButton",
		Text = "BADGES",
		Size = UDim2.fromOffset(T * 2 + 20, T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if panel.Visible then
			BadgeHud.close()
		else
			BadgeHud.open()
		end
	end)
	Kit.dock(open, "Badges", 15) -- the top row (or its MORE drawer), after MENTOR
	Net.listen("BadgeBook", function(d: any)
		if type(d) == "table" then
			last = d
			if panel.Visible then
				draw()
			end
		end
	end)
	Net.listen("BadgeEarned", function(d: any)
		if type(d) ~= "table" then
			return
		end
		Juice.fire("badgeEarned", nil, { name = d.name, group = d.group, mine = true })
		if panel.Visible then
			Net.send("BadgeOpen")
		end
	end)
end

return BadgeHud
