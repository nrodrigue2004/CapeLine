-- Journal: the story screen (spec: Story perks live in the Journal; the mission replay board; Side quests;
-- Faction reputation). Four tabs:
-- * STORY: Act 1's 6 missions with their state, a START (or REPLAY) button, the choices picked so far, and
--   a PIN button for the story.
-- * QUESTS: the 8 side quest arcs: who gives them and where, the current step, PIN.
-- * REP: the League, Syndicate and City tracks with their rank (ranks at 100, 300, 600, 1,000, 1,500).
-- * PERKS: the story perks unlocked by choices (Null Echo).
-- Opened with the JOURNAL button or J. PLACEHOLDER look until the UI pass (M10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local StoryPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoryPlan"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local Journal = {}

local S = Config.Story
local U = Config.Ui
local gui: ScreenGui
local panel: Frame
local body: ScrollingFrame
local tab = "story"
local tabButtons: { [string]: TextButton } = {}

local WHERE = { plaza = "the plaza", OldTown = "Old Town", hq = "the home safehouse", Docks = "the Docks" }
local STATE_TEXT = { done = "CLEARED", open = "READY", level = "LEVEL %d", locked = "LOCKED" }

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function clearBody()
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function row(order: number, height: number?): Frame
	local f = Kit.frame({
		Size = UDim2.new(1, -8, 0, height or 64),
		LayoutOrder = order,
		BackgroundColor3 = Kit.color.paper,
	})
	f.Parent = body
	return f
end

local function text(
	parent: Instance,
	t: string,
	pos: UDim2,
	size: UDim2,
	color: Color3?,
	max: number?,
	font: Enum.Font?
)
	local l = Kit.label({
		Text = t,
		Position = pos,
		Size = size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Kit.color.ink,
		Font = font or Kit.font,
		maxText = max or 20,
	})
	l.Parent = parent
	return l
end

local function pinButton(parent: Instance, num: number, pinned: boolean)
	local b = Kit.button({
		Text = if pinned then "PINNED" else "PIN",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(84, U.touchTarget - 12),
		BackgroundColor3 = if pinned then Kit.color.gold else Kit.color.muted,
		maxText = 18,
	}, function()
		StoryClient.pin(num)
	end)
	b.Parent = parent
end

local function drawStory(j: any)
	local side = j.side
	for num, m in S.missions do
		local st = j.states[num] or "locked"
		local r = row(num)
		local name = if side == "villain" and m.villainName then m.villainName else m.name
		text(
			r,
			string.format("%d. %s", num, string.upper(name)),
			UDim2.fromOffset(10, 6),
			UDim2.new(0.6, 0, 0, 26),
			nil,
			22
		)
		local label = string.format(STATE_TEXT[st] or "", m.minLevel)
		local col = if st == "done"
			then rgb(U.colors.health)
			elseif st == "open" then Kit.color.gold
			else Kit.color.muted
		text(r, label, UDim2.fromOffset(10, 36), UDim2.new(0.5, 0, 0, 20), col, 16, Kit.bodyFont)
		if not m.opening and (st == "open" or st == "done") then
			local b = Kit.button({
				Text = if st == "done" then "REPLAY" else "START",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(100, U.touchTarget - 8),
				maxText = 20,
			}, function()
				StoryClient.enter(num)
				Journal.close()
			end)
			b.Parent = r
		end
	end
	-- the choices picked so far
	local r = row(20, 32 + #S.choices * 24)
	text(r, "YOUR CHOICES", UDim2.fromOffset(10, 4), UDim2.new(0.6, 0, 0, 24), nil, 20)
	for i, c in S.choices do
		local pick = j.choices[i] or 0
		local t = if pick > 0 then StoryPlan.labels(Config, i, side)[pick] else "not yet"
		text(
			r,
			string.format("Choice %d (mission %d): %s", i, c.mission, t),
			UDim2.fromOffset(10, 6 + i * 24),
			UDim2.new(1, -20, 0, 20),
			nil,
			15,
			Kit.bodyFont
		)
	end
	local p = row(21, 52)
	text(
		p,
		"Pin the story step to your tracker",
		UDim2.fromOffset(10, 0),
		UDim2.new(0.7, 0, 1, 0),
		nil,
		15,
		Kit.bodyFont
	)
	pinButton(p, 0, j.pinned == 0)
end

local function drawQuests(j: any)
	for num, q in S.quests do
		local s = j.quests[num] or 0
		local r = row(num, 70)
		local npc = StoryPlan.npcName(Config, num, j.side)
		text(r, string.upper(npc), UDim2.fromOffset(10, 4), UDim2.new(0.65, 0, 0, 24), rgb(q.color), 20)
		local line
		if s == 0 then
			line = string.format("Talk to %s in %s", npc, WHERE[q.at.anchor] or q.at.anchor)
		elseif s >= 4 then
			line = "DONE"
		else
			line = string.format("%d/3: %s", s, q.steps[s].text)
		end
		text(r, line, UDim2.fromOffset(10, 32), UDim2.new(0.7, 0, 0, 30), Kit.color.ink, 15, Kit.bodyFont)
		if s >= 1 and s <= 3 then
			pinButton(r, num, j.pinned == num)
		end
	end
end

local function drawRep(j: any)
	local names = { league = "THE LEAGUE", syndicate = "THE SYNDICATE", city = "THE CITY" }
	local colors =
		{ league = rgb(U.colors.league), syndicate = rgb(U.colors.syndicate), city = Kit.color.gold }
	for i, track in S.rep.order do
		local pts = j.rep[i] or 0
		local rank = StoryPlan.repRank(Config, pts)
		local nextAt = S.rep.ranks[rank + 1]
		local r = row(i, 70)
		text(
			r,
			string.format("%s   RANK %d", names[track], rank),
			UDim2.fromOffset(10, 4),
			UDim2.new(1, -20, 0, 26),
			colors[track],
			20
		)
		local bar = Kit.frame({
			Position = UDim2.fromOffset(10, 38),
			Size = UDim2.new(1, -20, 0, 12),
			BackgroundColor3 = Kit.color.muted,
		})
		bar.Parent = r
		local lo = S.rep.ranks[rank] or 0
		local frac = if nextAt then (pts - lo) / math.max(1, nextAt - lo) else 1
		local fill =
			Kit.frame({ Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1), BackgroundColor3 = colors[track] })
		fill.Parent = bar
		text(
			r,
			if nextAt then string.format("%d / %d", pts, nextAt) else string.format("%d (top rank)", pts),
			UDim2.fromOffset(10, 52),
			UDim2.new(1, -20, 0, 16),
			Kit.color.ink,
			13,
			Kit.bodyFont
		)
	end
end

local function drawPerks(j: any)
	local any = false
	for id, p in S.perks do
		if StoryPlan.bit(j.perks or 0, p.bit) then
			any = true
			local r = row(p.bit, 60)
			text(
				r,
				string.upper(p.name),
				UDim2.fromOffset(10, 4),
				UDim2.new(1, -20, 0, 24),
				Kit.color.gold,
				20
			)
			text(
				r,
				p.text,
				UDim2.fromOffset(10, 32),
				UDim2.new(1, -20, 0, 20),
				Kit.color.ink,
				15,
				Kit.bodyFont
			)
			r.Name = id
		end
	end
	if not any then
		local r = row(1, 52)
		text(
			r,
			"Story choices unlock perks here",
			UDim2.fromOffset(10, 0),
			UDim2.new(1, -20, 1, 0),
			Kit.color.ink,
			16,
			Kit.bodyFont
		)
	end
end

local function draw()
	local j = StoryClient.journal
	clearBody()
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == tab then Kit.color.gold else Kit.color.paper
	end
	if not j then
		-- the journal comes with the save; it is on its way (spec: every screen has a loading state)
		Kit.stateNote(body, "loading", "Loading your journal...")
		return
	end
	if tab == "story" then
		drawStory(j)
	elseif tab == "quests" then
		drawQuests(j)
	elseif tab == "rep" then
		drawRep(j)
	else
		drawPerks(j)
	end
end

function Journal.open()
	if StoryClient.inOpening() then
		return
	end
	panel.Visible = true
	draw()
end

function Journal.close()
	panel.Visible = false
end

function Journal.isOpen(): boolean
	return panel.Visible
end

function Journal.init()
	gui = Kit.screen("Journal", 6)
	panel = Kit.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.94, 0, 0.9, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 720)
	limit.Parent = panel
	panel.Parent = gui
	local title = Kit.label({
		Text = "JOURNAL",
		Size = UDim2.new(0.5, 0, 0, 30),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 28,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(U.touchTarget, U.touchTarget - 10),
		Position = UDim2.new(1, -U.touchTarget - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, Journal.close)
	close.Parent = panel
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(10, 52)
	tabs.Size = UDim2.new(1, -20, 0, U.touchTarget - 8)
	tabs.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = tabs
	for i, def in { { "story", "STORY" }, { "quests", "QUESTS" }, { "rep", "REP" }, { "perks", "PERKS" } } do
		local b = Kit.button({
			Text = def[2],
			Size = UDim2.new(0.25, -5, 1, 0),
			LayoutOrder = i,
			BackgroundColor3 = Kit.color.paper,
			maxText = 20,
		}, function()
			tab = def[1]
			draw()
		end)
		b.Parent = tabs
		tabButtons[def[1]] = b
	end
	body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(10, 52 + U.touchTarget)
	body.Size = UDim2.new(1, -20, 1, -(62 + U.touchTarget))
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = 6
	body.Parent = panel
	local blist = Instance.new("UIListLayout")
	blist.Padding = UDim.new(0, 6)
	blist.SortOrder = Enum.SortOrder.LayoutOrder
	blist.Parent = body
	InputController.Pressed:Connect(function(action)
		if action == "Journal" then
			if panel.Visible then
				Journal.close()
			else
				Journal.open()
			end
		end
	end)
	StoryClient.Changed:Connect(function(what)
		if what == "journal" and panel.Visible then
			draw()
		end
	end)
	State.Changed:Connect(function()
		if panel.Visible then
			draw()
		end
	end)
end

return Journal
