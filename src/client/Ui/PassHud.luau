-- PassHud: the Hero Pass, the weekly episode and travel styles (spec: Hero MMO features > The Hero Pass,
-- Weekly episodes, Travel power styles; H8). The PASS button (top row or MORE) opens a panel with three tabs:
-- * HERO PASS: the season, your tier and XP, then all 40 tiers with the free and paid rewards shown before
--   buying (CLAIM once reached; the paid track says what the 499 Robux product unlocks and opens the shop's
--   Hero Pass tab). No tier skips, nothing random.
-- * EPISODE: this week's episode: its theme, the mentors' 3 panels, the 4 steps with counts, the reset time.
-- * STYLES: the travel styles for each mobility (how each is earned, bought or found on the pass) with WEAR,
--   and the pass's tints, landing pose and plate trims with EQUIP.
-- Moments: the episode's 3 comic panels the first time you log in each week (Juice "episodeIntro"), the TIER
-- UP card (Juice "passTier"), a claim pop (Juice "passClaim"), and after a mission or a world boss a small
-- card with the Pass XP it paid (the results screen hook).
-- PLACEHOLDER ART: Kit frames until the UI pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local PassRules = require(Shared:WaitForChild("PassRules"))
local TravelStyleRules = require(Shared:WaitForChild("TravelStyleRules"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local Kit = require(script.Parent.Kit)
local ShopHud = require(script.Parent.ShopHud)
local State = require(script.Parent.Parent.State)

local PassHud = {}

local P = Config.Pass
local T = Config.Ui.touchTarget
local gui: ScreenGui
local panel: Frame
local body: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local tab = "pass"
local state: { [string]: any }? = nil
local order = 0
local clockOffset = 0
local introShown = false

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
	local b =
		Kit.button({ Text = text, Size = UDim2.new(1, 0, 0, T - 10), BackgroundColor3 = color }, onClick)
	b.LayoutOrder = order
	b.Parent = body
	return b
end

local function left(endsAt: number): string
	local s = math.max(0, endsAt - (os.time() + clockOffset))
	local d = s // 86400
	if d >= 1 then
		return string.format("%d d %d h", d, (s % 86400) // 3600)
	end
	return string.format("%d h %d min", s // 3600, (s % 3600) // 60)
end

---------------------------------------------------------------------------
-- HERO PASS
---------------------------------------------------------------------------

-- One reward cell on a tier row: the label and its button (CLAIM, a tick, or why it is shut)
local function cell(row: Frame, x: number, tier: number, paid: boolean, d: { [string]: any })
	local r = PassRules.reward(P, d.season, tier, paid)
	local got = table.find(if paid then d.claimedPaid else d.claimedFree, tier - 1) ~= nil
	local reached = d.tier >= tier
	local name = Kit.label({
		Text = if r then PassRules.label(Config, r) else "-",
		Size = UDim2.new(0.42, -6, 0, 22),
		Position = UDim2.new(x, 4, 0, 2),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if paid then Kit.color.gold else Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 12,
	})
	name.Parent = row
	if not r then
		return
	end
	local text, color, click
	if got then
		text, color = "✓", Kit.color.muted
	elseif not reached then
		text, color = "LOCKED", Color3.fromRGB(90, 90, 100)
	elseif paid and not d.paid then
		text, color = "PAID TRACK", Color3.fromRGB(90, 90, 100)
	else
		text, color = "CLAIM", Kit.color.gold
		click = function()
			Net.send("PassClaim", tier, if paid then 1 else 0)
		end
	end
	local b = Kit.button({
		Text = text,
		Size = UDim2.new(0.42, -6, 0, T - 16),
		Position = UDim2.new(x, 4, 0, 26),
		BackgroundColor3 = color,
		pending = click ~= nil,
	}, click)
	b.Parent = row
end

local function drawPass(d: { [string]: any })
	if not d.open then
		line("HERO PASS", 30, 24, Kit.color.gold, Kit.font)
		line("The next season is on its way. Your claimed rewards stay yours.", 20, 13, Kit.color.muted)
		return
	end
	line(string.upper(d.seasonName), 30, 22, Kit.color.gold, Kit.font)
	line(
		string.format("Week %d of %d  ·  ends in %s", d.week, P.weeks, left(d.endsAt)),
		18,
		13,
		Kit.color.muted
	)
	local into = d.xp - d.tier * P.xpPerTier
	line(
		if d.tier >= P.tiers
			then string.format("TIER %d  ·  the season is done!", d.tier)
			else string.format(
				"TIER %d  ·  %s / %s XP to tier %d",
				d.tier,
				Kit.comma(into),
				Kit.comma(P.xpPerTier),
				d.tier + 1
			),
		24,
		18,
		Kit.color.paper,
		Kit.font
	)
	line(
		if d.dailyReady
			then "Daily first win ready: your first incident, contract, mission or boss today pays extra Pass XP."
			else "Daily first win done today. Pass XP comes from everything you do; the 2x pass never doubles it.",
		30,
		12,
		Kit.color.muted
	)
	if not d.paid then
		button(
			string.format("PAID TRACK: 30 MORE LOOKS (R$ %d)", Config.Shop.products.heroPass.robux),
			Kit.color.gold,
			function()
				PassHud.close()
				ShopHud.open("passes")
			end
		)
		line(
			"Looks only: every reward is shown below before you buy. No tier skips, nothing random.",
			20,
			12,
			Kit.color.muted
		)
	end
	for tier = 1, P.tiers do
		order += 1
		local row = Kit.frame({
			Size = UDim2.new(1, 0, 0, T + 20),
			BackgroundColor3 = if d.tier >= tier then Kit.color.night else Color3.fromRGB(40, 40, 46),
			BackgroundTransparency = if d.tier >= tier then 0.1 else 0.4,
		})
		row.LayoutOrder = order
		row.Parent = body
		local n = Kit.label({
			Text = tostring(tier),
			Size = UDim2.new(0.12, 0, 1, 0),
			TextColor3 = if d.tier >= tier then Kit.color.gold else Kit.color.muted,
			maxText = 22,
		})
		n.Parent = row
		cell(row, 0.14, tier, false, d)
		cell(row, 0.57, tier, true, d)
	end
end

---------------------------------------------------------------------------
-- EPISODE
---------------------------------------------------------------------------

local function mentorName(i: number): string
	local m = Config.Mentors.list[i]
	return if m then m.name else "?"
end

local function panelLine(p: { [string]: any }): (string, string)
	local villain = State.hero.side == "villain"
	local who = if villain then p.who[2] else p.who[1]
	return mentorName(who), if villain then p.villain else p.hero
end

local function drawEpisode(d: { [string]: any })
	local ep = d.episode
	if not ep then
		line("No episode this week.", 20, 14, Kit.color.muted)
		return
	end
	line(string.format("EPISODE %d: %s", ep.num, string.upper(ep.name)), 30, 22, Kit.color.gold, Kit.font)
	line(ep.theme .. "  ·  new episode in " .. left(ep.endsAt), 20, 13, Kit.color.muted)
	for _, p in ep.panels do
		local who, text = panelLine(p)
		line(string.upper(who) .. ": " .. text, 34, 13, Kit.color.paper)
	end
	line("THIS WEEK", 26, 18, Kit.color.gold, Kit.font)
	for _, st in ep.steps do
		line(
			string.format(
				"%s %s  (%s / %s)",
				if st.done then "✓" else "•",
				st.text,
				Kit.comma(st.have),
				Kit.comma(st.n)
			),
			22,
			14,
			if st.done then Kit.color.gold else Kit.color.paper
		)
	end
	local E = Config.Episodes
	line(
		string.format(
			"Each step: %s Renown and %s Pass XP. All four: %s Renown, %s Pass XP and the week's badge.",
			Kit.comma(E.stepRenown),
			Kit.comma(E.stepXp),
			Kit.comma(E.doneRenown),
			Kit.comma(E.doneXp)
		),
		34,
		12,
		Kit.color.muted
	)
	if ep.done then
		line("EPISODE DONE! See you next week.", 24, 16, Kit.color.gold, Kit.font)
	end
	button("REPLAY THE INTRO", Kit.color.paper, function()
		PassHud.intro(true)
	end)
end

---------------------------------------------------------------------------
-- STYLES
---------------------------------------------------------------------------

local function source(s: any): string
	if s.source == "badge" then
		for _, g in Config.Badges.groups do
			if g.id == s.group then
				return "Earned: every " .. g.name .. " badge"
			end
		end
		return "Earned"
	elseif s.source == "mentor" then
		return "Earned: finish a mentor's quest line"
	elseif s.source == "shop" then
		local row = Config.Shop.products[s.product]
		return string.format("Shop: R$ %d", row and row.robux or 0)
	end
	return "Hero Pass season 1 (" .. (if s.track == "paid" then "paid" else "free") .. " track)"
end

local function drawStyles()
	local prof = State.profile or {}
	local owned = {}
	for _, id in prof.travelOwned or {} do
		owned[id] = true
	end
	local worn = prof.travel or { 0, 0, 0, 0, 0 }
	line("TRAVEL STYLES", 30, 24, Kit.color.gold, Kit.font)
	line("A style changes how your mobility looks and sounds, never how fast it is.", 20, 12, Kit.color.muted)
	for mi, m in Config.Move.mobilityOrder do
		local mine = State.hero.mobility == m
		line(
			string.upper(Config.Move.mobility[m].name) .. (if mine then "  (yours now)" else ""),
			26,
			18,
			Kit.color.gold,
			Kit.font
		)
		button((if (worn[mi] or 0) == 0 then "✓ " else "") .. "PLAIN", Kit.color.paper, function()
			Net.send("TravelStyleSet", mi, 0)
		end)
		for slot = 1, Config.TravelStyles.perMobility do
			local s = TravelStyleRules.at(Config, m, slot)
			if s then
				-- earned styles are checked on the server; the device only knows bought and pass ones
				local have = owned[s.id] or s.source == "badge" or s.source == "mentor"
				local on = worn[mi] == slot
				local b = button(
					string.format("%s%s  ·  %s", if on then "✓ " else "", string.upper(s.name), source(s)),
					if on then Kit.color.gold elseif owned[s.id] then rgb(s.c1) else Kit.color.paper,
					function()
						Net.send("TravelStyleSet", mi, slot)
					end
				)
				b.AutoButtonColor = have
			end
		end
	end
	-- the pass's tints, landing pose and plate trims (Hero Pass looks; titles live in the Badge Book)
	line("HERO PASS LOOKS", 30, 22, Kit.color.gold, Kit.font)
	local tints = prof.tints or 0
	local any = false
	for i, t in Config.Shop.tints do
		if t.pass and bit32.btest(tints, bit32.lshift(1, i)) then
			any = true
			local on = prof.tint == i
			button((if on then "✓ " else "") .. string.upper(t.name) .. " EFFECTS", rgb(t.color), function()
				Net.send("TintSet", if on then 0 else i)
			end)
		end
	end
	for _, id in prof.emotes or {} do
		local e = Config.Shop.emotes[id]
		if e and e.landing and id == 25 then
			any = true
			local on = prof.landing == id
			button((if on then "✓ " else "") .. string.upper(e.name), Kit.color.paper, function()
				Net.send("LandingSet", if on then 0 else id)
			end)
		end
	end
	for i, t in P.trims do
		if state and table.find(state.trims or {}, i) then
			any = true
			button("WEAR " .. string.upper(t.name), rgb(t.color), function()
				Net.send("AccoladeWear", 2, P.trimBase + i)
			end)
		end
	end
	if not any then
		line(
			"Claim tints, the landing pose and plate trims on the Hero Pass; they show here.",
			20,
			12,
			Kit.color.muted
		)
	end
end

---------------------------------------------------------------------------
-- Drawing, moments
---------------------------------------------------------------------------

local function draw()
	clear()
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == tab then Kit.color.gold else Kit.color.paper
	end
	if tab == "styles" then
		drawStyles()
		return
	end
	local d = state
	if not d then
		Kit.stateNote(body, "loading", "Opening the Hero Pass")
		return
	end
	if tab == "pass" then
		drawPass(d)
	else
		drawEpisode(d)
	end
end

-- A card that slides up from the bottom for a few seconds
local function card(title: string, sub: string, color: Color3, onView: (() -> ())?)
	local f = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 80),
		Size = UDim2.fromOffset(300, 64),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.1,
	})
	Kit.stroke(f, color, 3)
	f.Parent = gui
	local t = Kit.label({
		Text = title,
		Size = UDim2.new(1, -90, 0, 30),
		Position = UDim2.fromOffset(10, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		maxText = 20,
	})
	t.Parent = f
	local s = Kit.label({
		Text = sub,
		Size = UDim2.new(1, -90, 0, 22),
		Position = UDim2.fromOffset(10, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	s.Parent = f
	if onView then
		local v = Kit.button({
			Text = "VIEW",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(70, T - 12),
			BackgroundColor3 = color,
		}, function()
			f:Destroy()
			onView()
		end)
		v.Parent = f
	end
	TweenService
		:Create(f, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 1, -150) })
		:Play()
	task.delay(5, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 1, 80) }):Play()
			task.delay(0.35, function()
				f:Destroy()
			end)
		end
	end)
end

-- The episode's 3 comic panels, one at a time (force: replay from the Episode tab)
function PassHud.intro(force: boolean?)
	local d = state
	local ep = d and d.episode
	if not ep or (not force and (introShown or not ep.intro)) then
		return
	end
	introShown = true
	local shade = Kit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		round = false,
	})
	shade.Parent = gui
	local box = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.86, 0, 0, 190),
		BackgroundColor3 = Kit.color.paper,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(520, 190)
	lim.Parent = box
	Kit.stroke(box, Kit.color.ink, 4)
	box.Parent = shade
	local head = Kit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.ink,
		maxText = 20,
	})
	head.Parent = box
	local text = Kit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 80),
		Position = UDim2.fromOffset(10, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Kit.color.ink,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 18,
	})
	text.Parent = box
	local i = 0
	local nextButton: TextButton
	local function show()
		i += 1
		local p = ep.panels[i]
		if not p then
			shade:Destroy()
			Net.send("EpisodeSeen")
			return
		end
		local who, said = panelLine(p)
		head.Text = string.format("EPISODE %d: %s  ·  %d/3", ep.num, string.upper(ep.name), i)
		text.Text = string.upper(who) .. ": " .. said
		nextButton.Text = if i >= #ep.panels then "LET'S GO" else "NEXT"
		Juice.fire("episodeIntro", nil, { panel = i })
	end
	nextButton = Kit.button({
		Text = "NEXT",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(130, T - 6),
		BackgroundColor3 = Kit.color.gold,
	}, show)
	nextButton.Parent = box
	show()
end

function PassHud.open(which: string?)
	tab = which or tab
	panel.Visible = true
	draw()
	Net.send("PassOpen")
end

function PassHud.close()
	panel.Visible = false
end

function PassHud.isOpen(): boolean
	return panel.Visible
end

function PassHud.init()
	gui = Kit.screen("PassHud", 6)
	panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.84, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(540, 640)
	limit.Parent = panel
	panel.Parent = gui
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, T - 10),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, PassHud.close)
	close.Parent = panel
	for i, row in { { "pass", "HERO PASS" }, { "episode", "EPISODE" }, { "styles", "STYLES" } } do
		local b = Kit.button({
			Text = row[2],
			Size = UDim2.new(0.28, -8, 0, T - 12),
			Position = UDim2.new((i - 1) * 0.28, 10, 0, 8),
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
	local open = Kit.button({
		Name = "PassButton",
		Text = "PASS",
		Size = UDim2.fromOffset(T * 2, T - 10),
		BackgroundColor3 = Kit.color.gold,
	}, function()
		if panel.Visible then
			PassHud.close()
		else
			PassHud.open()
		end
	end)
	Kit.dock(open, "Pass", 16) -- the top row (or its MORE drawer), after BADGES

	Net.listen("PassState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if typeof(d.now) == "number" then
			clockOffset = d.now - os.time()
		end
		state = d
		if type(d.claimed) == "table" then
			local r = PassRules.reward(P, d.season, d.claimed[1], d.claimed[2] == 1)
			Juice.fire("passClaim", nil, { name = PassRules.label(Config, r), mine = true })
		end
		if panel.Visible then
			draw()
		end
		PassHud.intro(false)
	end)
	Net.listen("PassXp", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if state then
			state.xp, state.tier = d.xp, d.tier
		end
		if d.tier > d.before then
			Juice.fire("passTier", nil, { tier = d.tier, mine = true })
			card(
				string.format("HERO PASS TIER %d!", d.tier),
				"A reward is ready to claim",
				Kit.color.gold,
				function()
					PassHud.open("pass")
				end
			)
		elseif
			d.reason == "mission"
			or d.reason == "boss"
			or d.reason == "contest"
			or d.reason == "episode"
		then
			-- the results screen hook: what this paid on the pass
			card(
				string.format("HERO PASS +%s XP%s", Kit.comma(d.add), if d.daily then " (DAILY WIN)" else ""),
				string.format(
					"Tier %d  ·  %s / %s",
					d.tier,
					Kit.comma(d.xp - d.tier * P.xpPerTier),
					Kit.comma(P.xpPerTier)
				),
				Color3.fromRGB(150, 210, 255),
				function()
					PassHud.open("pass")
				end
			)
		end
		if panel.Visible and tab == "pass" then
			draw()
		end
	end)
	Net.listen("ShopResult", function(d: any)
		if type(d) == "table" and d.kind == "heroPass" then
			Net.send("PassOpen") -- the paid track just opened
		end
	end)
	Net.listen("BadgeBook", function(d: any)
		if type(d) == "table" and panel.Visible and tab == "styles" then
			draw()
		end
	end)
end

return PassHud
