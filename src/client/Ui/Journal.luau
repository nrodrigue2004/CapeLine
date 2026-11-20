-- Journal: the story screen (spec: Story perks live in the Journal; the mission replay board; Side quests;
-- Faction reputation). Eight tabs:
-- * STORY: an act row on top (WP11: ACT 1, ACT 2, ACT 3 from Config.Story.acts; it opens on the act the hero
--   is on). An act that is out lists its missions (Act 1's 6, 1 the Ceremony prologue) with their state and
--   a line about each, a START (or REPLAY) button, the act's choices picked so far (each side's own options),
--   a PIN button for the story, and a locked row for each act still to come. A coming-soon act's page is only
--   its locked "Act 2: coming soon" row: no missions, names or story text.
-- * QUESTS: the side quest chains (lore step 10) by layer: who gives them and where, the step, ACCEPT, RESUME,
--   HOLD (abandon: the chain waits at its step) and the lock reason (level, a mission, another chain).
-- * REP: Vigil Trust, Syndicate Fear and City Reputation with their rank (ranks at 100, 300, 600, 1,000, 1,500).
-- * PERKS: the story perks unlocked by choices (the Echo Drone).
-- * LORE: the lore pages (side-content, LoreClient's drawInto): each district's pages read, tap one to read it again.
-- * ROGUES: the Rogues File (Ui.RoguesPage): every robot, famous fake, side quest villain and world boss,
--   silhouettes for the ones not beaten yet, gold pages for hard boss wins.
-- * BADGES: the Badge Book, Collections and titles (BadgeHud's views; spec H7: "a Badge Book in the
--   Journal", "the Collections page lives in the Journal next to the Badge Book").
-- * MENTOR: your mentor's card (MentorHud's; spec H6: "the mentor shown in the Journal").
-- * SHOWDOWN: your nemesis's WANTED poster and the Showdown start (NemesisHud's; spec H5: "started from the
--   Journal"). The other screens stay as they are; the Journal is one main panel (Kit.opening).
-- Opened with the JOURNAL button or J. PLACEHOLDER look until the UI pass (M10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local StoryPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoryPlan"))
local SideQuestPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SideQuestPlan"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local RoguesPage = require(script.Parent.RoguesPage)
local BadgeHud = require(script.Parent.BadgeHud)
local MentorHud = require(script.Parent.MentorHud)
local NemesisHud = require(script.Parent.NemesisHud)
local LoreClient = require(script.Parent.Parent.Controllers.LoreClient)

local Journal = {}

local S = Config.Story
local U = Config.Ui
local gui: ScreenGui
local panel: Frame
local body: ScrollingFrame
local tab = "story"
local badgeView = "badges" -- the BADGES tab's view: badges, collect or titles
local actView: number? = nil -- WP11: the STORY tab's act (nil: the act the hero is on)
local tabButtons: { [string]: TextButton } = {}
-- two rows (a phone fits four or five tabs a row; side-content added LORE to the first)
local TABS = {
	{
		{ "story", "STORY" },
		{ "quests", "QUESTS" },
		{ "lore", "LORE" },
		{ "rep", "REP" },
		{ "perks", "PERKS" },
	},
	{ { "rogues", "ROGUES" }, { "badges", "BADGES" }, { "mentor", "MENTOR" }, { "showdown", "SHOWDOWN" } },
}
-- the tabs drawn from another screen's data (each asks its server for it when it opens)
local FEEDS = {
	lore = LoreClient,
	rogues = RoguesPage,
	badges = BadgeHud,
	mentor = MentorHud,
	showdown = NemesisHud,
}

local WHERE = {
	plaza = "the plaza",
	hq = "the home safehouse",
	Downtown = "Downtown",
	Uptown = "Uptown",
	OldTown = "Old Town",
	Docks = "the Docks",
	Suburbs = "the Suburbs", -- lore step 11: Wind-Up Lane's toy shop
	Coast = "the Coast", -- lore step 11: The Salt Dogs' pier
	OldQuarry = "the Old Quarry", -- lore step 11, chain 6: The Pit
	Underwater = "the Coral Shelf", -- lore step 11: The Sunken City, on the sea floor
	RadioHill = "the west hills", -- lore step 11, the origin lines: Starblood Calling (RADIO HILL, the west hills)
}
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

-- WP11: a coming-soon act's locked row (its number and "coming soon" only: the act's story is not written)
local function soonRow(order: number, act: number)
	local r = row(order, 52)
	r.Name = "ActSoon" .. act
	text(r, string.format(S.actText.soon, act), UDim2.fromOffset(10, 0), UDim2.new(1, -124, 1, 0), nil, 18)
	local lock = text(
		r,
		S.actText.locked,
		UDim2.new(1, -110, 0, 0),
		UDim2.new(0, 100, 1, 0),
		Kit.color.muted,
		16,
		Kit.bodyFont
	)
	lock.TextXAlignment = Enum.TextXAlignment.Right
end

-- WP11: the act row on top of the STORY tab (one button an act: gold the shown one, paper an act that is out, grey a
-- coming-soon one, which opens its locked row)
local function actRow(shown: number)
	local pick = Instance.new("Frame")
	pick.Name = "ActTabs"
	pick.BackgroundTransparency = 1
	pick.Size = UDim2.new(1, -8, 0, U.touchTarget - 12)
	pick.LayoutOrder = -2
	pick.Parent = body
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = pick
	local n = #S.acts
	for a in S.acts do
		local soon = StoryPlan.soon(Config, a)
		local b = Kit.button({
			Name = "Act_" .. a,
			Text = string.format(S.actText.tab, a),
			Size = UDim2.new(1 / n, -6 * (n - 1) / n, 1, 0),
			LayoutOrder = a,
			BackgroundColor3 = if a == shown
				then Kit.color.gold
				elseif soon then Kit.color.muted
				else Kit.color.paper,
			maxText = 16,
		}, function()
			actView = a
			Journal.redraw()
		end)
		b.Parent = pick
	end
end

local function drawStory(j: any)
	local side = j.side
	local shown = actView or j.act or StoryPlan.currentAct(Config, { missions = j.missions or 0 })
	if not S.acts[shown] then
		shown = 1
	end
	actRow(shown)
	if StoryPlan.soon(Config, shown) then
		soonRow(1, shown)
		return
	end
	for _, num in StoryPlan.actMissions(Config, shown) do
		local m = S.missions[num]
		local st = j.states[num] or "locked"
		local r = row(num, 86)
		text(
			r,
			string.format("%d. %s", StoryPlan.missionIndex(Config, num), string.upper(m.name)),
			UDim2.fromOffset(10, 6),
			UDim2.new(0.6, 0, 0, 26),
			nil,
			22
		)
		-- lore step 5: mission 1 is the Ceremony prologue (its REPLAY plays the exposition, then the prologue)
		local label = string.format(STATE_TEXT[st] or "", m.minLevel)
			.. (if m.opening then "  (PROLOGUE)" else "")
		local col = if st == "done"
			then rgb(U.colors.health)
			elseif st == "open" then Kit.color.gold
			else Kit.color.muted
		text(r, label, UDim2.fromOffset(10, 34), UDim2.new(0.6, 0, 0, 20), col, 16, Kit.bodyFont)
		if m.blurb then
			text(
				r,
				m.blurb,
				UDim2.fromOffset(10, 58),
				UDim2.new(1, -124, 0, 20),
				Kit.color.ink,
				14,
				Kit.bodyFont
			)
		end
		if (st == "open" or st == "done") and (not m.opening or st == "done") then
			local b = Kit.button({
				Text = if st == "done" then "REPLAY" else "START",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(100, U.touchTarget - 8),
				maxText = 20,
			}, function()
				if m.opening then
					-- fix-flow (2026-11-19): the exposition again, then the prologue (out in the city only)
					StoryClient.replayPrologue()
				else
					StoryClient.enter(num)
				end
				Journal.close()
			end)
			b.Parent = r
		end
	end
	-- the act's choices picked so far, in mission order (the choice numbers are save slots); each side reads
	-- its own options
	local order = StoryPlan.actChoices(Config, shown)
	if #order > 0 then
		local r = row(S.saveRoom.missions + 1, 32 + #order * 24)
		text(r, "YOUR CHOICES", UDim2.fromOffset(10, 4), UDim2.new(0.6, 0, 0, 24), nil, 20)
		for k, i in order do
			local c = S.choices[i]
			local pick = j.choices[i] or 0
			local t = if pick > 0 then StoryPlan.labels(Config, i, side)[pick] else "not yet"
			text(
				r,
				string.format("%s: %s", S.missions[c.mission].name, t),
				UDim2.fromOffset(10, 6 + k * 24),
				UDim2.new(1, -20, 0, 20),
				nil,
				15,
				Kit.bodyFont
			)
		end
	end
	local p = row(S.saveRoom.missions + 2, 52)
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
	-- the acts still to come, each a locked row under the act that is out
	for a in S.acts do
		if a > shown and StoryPlan.soon(Config, a) then
			soonRow(S.saveRoom.missions + 2 + a, a)
		end
	end
end

-- A small action button on a quest row (ACCEPT, RESUME, HOLD), right-aligned at slot 1 or 2
local function actButton(parent: Instance, label: string, slot: number, color: Color3, fn: () -> ())
	local b = Kit.button({
		Text = label,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8 - (slot - 1) * 92, 0.5, 0),
		Size = UDim2.fromOffset(84, U.touchTarget - 12),
		BackgroundColor3 = color,
		maxText = 18,
		pending = true, -- fix-respawn: "..." at once until the server answers (a toast or the redrawn page)
	}, fn)
	b.Parent = parent
end

local LAYER_TITLE = { district = "DISTRICT CHAINS", character = "CHARACTER LINES", origin = "ORIGIN LINES" }

-- lore step 10: one page row per side quest chain (the server's rows: state, step, lock reason)
local function drawQuests(j: any)
	local rows = j.sq or {}
	if #rows == 0 then
		Kit.stateNote(body, "empty", "New side quest chains are on their way")
		return
	end
	for li, layer in Config.SideQuests.layers do
		local header = false
		for _, r in rows do
			local chain = SideQuestPlan.byBit(Config, r.bit)
			if chain and chain.layer == layer then
				if not header then
					header = true
					local h = row(li * 1000, 30)
					h.BackgroundTransparency = 1
					text(
						h,
						LAYER_TITLE[layer],
						UDim2.fromOffset(4, 2),
						UDim2.new(1, -8, 1, -4),
						Kit.color.gold,
						18
					)
				end
				local giver = Config.SideQuests.givers[chain.giver]
				local f = row(li * 1000 + r.bit, if chain.blurb then 100 else 78)
				text(
					f,
					string.upper(chain.name),
					UDim2.fromOffset(10, 4),
					UDim2.new(0.6, 0, 0, 24),
					if giver then rgb(giver.color) else Kit.color.ink,
					20
				)
				local where = giver and (WHERE[giver.anchor] or giver.anchor) or ""
				local site = giver and giver.anchor == "site" and Config.SideQuests.sites[giver.site]
				if site then
					-- lore step 11: a giver at a site's door (HALO ACADEMY, Downtown)
					where = site.name .. ", " .. (WHERE[site.district] or site.district)
				end
				local line
				if r.state == "done" then
					line = "DONE"
				elseif r.state == "active" then
					local step = chain.steps[r.step]
					local goal = step and SideQuestPlan.goal(step, j.side)
					line = string.format(
						"%d/%d: %s",
						r.step,
						r.steps,
						if goal then SideQuestPlan.text(goal, j.side) else ""
					)
					if j.pinned ~= r.bit then
						line ..= "  (on hold)"
					end
				elseif r.state == "open" then
					line = string.format("Talk to %s in %s", giver and giver.name or "?", where)
				elseif r.why == "level" then
					line = string.format("Opens at level %d", r.n or 1)
				elseif r.why == "story" then
					local m = S.missions[r.n or 0]
					line = "After the mission " .. (if m then m.name else "?")
				elseif r.why == "after" then
					local prev = SideQuestPlan.chain(Config, r.after or "")
					line = "After " .. (if prev then prev.name else "another chain")
				else
					line = "LOCKED"
				end
				text(
					f,
					line,
					UDim2.fromOffset(10, 32),
					UDim2.new(0.58, 0, 0, 40),
					Kit.color.ink,
					15,
					Kit.bodyFont
				)
				-- lore step 11: the chain's page line (fixed text, the reader's side)
				local blurb = chain.blurb and chain.blurb[if j.side == "villain" then "villain" else "hero"]
				if blurb then
					text(
						f,
						blurb,
						UDim2.fromOffset(10, 72),
						UDim2.new(0.58, 0, 0, 24),
						Kit.color.ink,
						13,
						Kit.bodyFont
					)
				end
				if r.state == "active" then
					if j.pinned == r.bit then
						pinButton(f, r.bit, true)
						actButton(f, "HOLD", 2, Kit.color.muted, function()
							StoryClient.sideQuest(2, r.bit)
						end)
					else
						actButton(f, "RESUME", 1, Kit.color.gold, function()
							StoryClient.sideQuest(1, r.bit)
						end)
					end
				elseif r.state == "open" and not (chain.unlock and chain.unlock.npc) then
					actButton(f, "ACCEPT", 1, Kit.color.gold, function()
						StoryClient.sideQuest(1, r.bit)
					end)
				end
			end
		end
	end
end

local function drawRep(j: any)
	local colors = { vigil = rgb(U.colors.vigil), syndicate = rgb(U.colors.syndicate), city = Kit.color.gold }
	for i, track in S.rep.order do
		local pts = j.rep[i] or 0
		local rank = StoryPlan.repRank(Config, pts)
		local nextAt = S.rep.ranks[rank + 1]
		local r = row(i, 70)
		text(
			r,
			string.format("%s   RANK %d", string.upper(S.rep.labels[track]), rank),
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

-- WP7: the BADGES tab: its three views (BadgeHud's), picked by a small row on top
local function drawBadges()
	local pick = Instance.new("Frame")
	pick.Name = "BadgeViews"
	pick.BackgroundTransparency = 1
	pick.Size = UDim2.new(1, -8, 0, U.touchTarget - 12)
	pick.LayoutOrder = -2
	pick.Parent = body
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = pick
	for i, def in { { "badges", "BADGE BOOK" }, { "collect", "COLLECTIONS" }, { "titles", "TITLES" } } do
		local b = Kit.button({
			Text = def[2],
			Size = UDim2.new(1 / 3, -4, 1, 0),
			LayoutOrder = i,
			BackgroundColor3 = if badgeView == def[1] then Kit.color.gold else Kit.color.muted,
			maxText = 16,
		}, function()
			badgeView = def[1]
			Journal.redraw()
		end)
		b.Parent = pick
	end
	BadgeHud.drawInto(body, badgeView)
end

local function draw()
	local j = StoryClient.journal
	clearBody()
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == tab then Kit.color.gold else Kit.color.paper
	end
	-- WP7: the tabs drawn from other screens' views (their own data, no journal needed)
	if tab == "rogues" then
		RoguesPage.drawInto(body)
		return
	elseif tab == "badges" then
		drawBadges()
		return
	elseif tab == "mentor" then
		MentorHud.drawInto(body)
		return
	elseif tab == "showdown" then
		NemesisHud.drawInto(body, Journal.close)
		return
	elseif tab == "lore" then
		LoreClient.drawInto(body) -- side-content: the lore pages by district
		return
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

function Journal.redraw()
	if panel.Visible then
		draw()
	end
end

-- Ask the server for a tab's data when it comes up (the drawn view shows loading until it lands)
local function feed(id: string)
	local f = FEEDS[id]
	if f then
		f.request()
	end
end

-- Open on the tab shown last, or on `which` (story, quests, rep, perks, rogues, badges, mentor, showdown)
function Journal.open(which: string?)
	if StoryClient.inOpening() then
		return
	end
	if which and tabButtons[which] then
		tab = which
	end
	Kit.opening("Journal", panel, Journal.close, true)
	panel.Visible = true
	draw()
	feed(tab)
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
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(U.touchTarget, U.touchTarget - 10),
		Position = UDim2.new(1, -U.touchTarget - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, Journal.close)
	close.Parent = panel
	-- WP7: eight tabs in two rows left of X (the JOURNAL title made way for the second row; the gold tab
	-- names the page)
	local tabH = U.touchTarget - 12
	for r, rowTabs in TABS do
		local tabs = Instance.new("Frame")
		tabs.Name = "Tabs" .. r
		tabs.BackgroundTransparency = 1
		tabs.Position = UDim2.fromOffset(10, 8 + (r - 1) * (tabH + 6))
		tabs.Size = UDim2.new(1, -(U.touchTarget + 8) - 18, 0, tabH)
		tabs.Parent = panel
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, 6)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = tabs
		for i, def in rowTabs do
			local b = Kit.button({
				Name = "Tab_" .. def[1],
				Text = def[2],
				Size = UDim2.new(1 / #rowTabs, -5, 1, 0),
				LayoutOrder = i,
				BackgroundColor3 = Kit.color.paper,
				maxText = 20,
			}, function()
				tab = def[1]
				draw()
				feed(def[1])
			end)
			b.Parent = tabs
			Kit.lead(b, "journal", def[1], tabH - 18) -- gap-icons2: the tab's comic icon before its name
			tabButtons[def[1]] = b
		end
	end
	local top = 8 + #TABS * (tabH + 6) + 4
	body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(10, top)
	body.Size = UDim2.new(1, -20, 1, -(top + 10))
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
	-- WP7: a tab drawn from another screen redraws when that screen's data lands
	RoguesPage.init()
	for id, f in FEEDS do
		f.Changed:Connect(function()
			if panel.Visible and tab == id then
				draw()
			end
		end)
	end
end

return Journal
