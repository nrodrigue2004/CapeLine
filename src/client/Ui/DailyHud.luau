-- DailyHud: the daily login streak and daily quests (spec: Update 1 > "daily quests and login streak"; gap
-- G1, WP1). Rules in Shared.DailyRules, numbers in Config.Daily; the server (DailyService) decides and pays.
-- * The DAILY button (top row or MORE) opens the daily card: the streak, the 7-day track (the day ready to
--   claim in gold, days got ticked), CLAIM (pending until the server answers; once a day), the weekly grace
--   note, today's 3 quests with counts and pay, the all-done bonus and the time to the 00:00 UTC reset.
-- * On join the server opens the card once the hero is free (made, the prologue done, no scene) when a
--   reward is waiting.
-- * The small tracker: a DAILY n/3 pill under the top row; it opens its 3 rows for a few seconds when a quest
--   moves on (tap to keep it open or shut). Hidden in the prologue, in cutscenes and while the card is open.
--   On a phone it folds into the DAILY button's "DAILY n/3" (no free spot clear of the action buttons).
-- * States: loading (until DailyState arrives), error (no answer in Config.Daily.ui.answerWait s, or the save
--   is offline: RETRY), empty (no quests open today, or the daily rewards switched off).
-- * Phone layout: the card is fitted to the safe area (Kit.fit); the pill's spot comes from the HUD plan
--   (Shared.TouchLayout through Kit.hudBoxes and the cluster box), clear of every HUD part.
-- * Juice: "dailyClaim" (the DAY N! stamp) and "dailyQuest" (the DAILY! stamp), through Juice.fire.
-- PLACEHOLDER ART: Kit frames and text until the UI pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local TouchLayout = require(Shared:WaitForChild("TouchLayout"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local Kit = require(script.Parent.Kit)
local PopupGate = require(script.Parent.PopupGate)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)

local DailyHud = {}

local D = Config.Daily
local U = Config.Ui
local T = U.touchTarget
local P = U.phone
local gui: ScreenGui
local panel: Frame
local body: ScrollingFrame
local openButton: TextButton
local tracker: Frame
local pill: TextButton
local rowsFrame: Frame
local rowLabels: { TextLabel } = {}
local state: { [string]: any }? = nil
local asked = 0 -- os.clock() of the last DailyOpen still unanswered (0 = none)
local resetAt = 0 -- os.clock() of the next 00:00 UTC
local order = 0
local pinned = false
local folded = false -- no free spot for the small tracker (a phone): the DAILY button shows the count
local openUntil = 0 -- the tracker's rows stay open until this os.clock()

local GOT = Color3.fromRGB(110, 220, 120)
local DIM = Color3.fromRGB(150, 150, 165)

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

local function comma(n: number): string
	return Kit.comma(n)
end

-- "300 Credits, 38 Renown and 20 Dust" (and the title)
local function rewardText(r: { [string]: any }): string
	local parts = {}
	if r.title then
		table.insert(parts, "the title " .. r.title)
	end
	if (r.credits or 0) > 0 then
		table.insert(parts, comma(r.credits) .. " Credits")
	end
	if (r.renown or 0) > 0 then
		table.insert(parts, comma(r.renown) .. " Renown")
	end
	if (r.dust or 0) > 0 then
		table.insert(parts, comma(r.dust) .. " Dust")
	end
	if #parts == 0 then
		return "nothing"
	elseif #parts == 1 then
		return parts[1]
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

-- A day's main reward on its tile: the amount and the kind
local function tileText(r: { [string]: any }, got: boolean): (string, string)
	if r.title and not got then
		return "NEW", "TITLE"
	elseif (r.renown or 0) > 0 then
		return comma(r.renown), "RENOWN"
	elseif (r.credits or 0) > 0 then
		return comma(r.credits), "CREDITS"
	end
	return comma(r.dust or 0), "DUST"
end

local function left(): string
	local s = math.max(0, math.floor(resetAt - os.clock()))
	return string.format("%d h %d min", s // 3600, (s % 3600) // 60)
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------

local function drawTrack(d: { [string]: any })
	order += 1
	local row = Instance.new("Frame")
	row.Name = "Track"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 76)
	row.LayoutOrder = order
	row.Parent = body
	local n = #d.days
	for i, day in d.days do
		local got, ready = day.state == "got", day.state == "ready"
		local cell = Kit.frame({
			Name = "Day" .. i,
			Size = UDim2.new(1 / n, -6, 1, -4),
			Position = UDim2.new((i - 1) / n, 3, 0, 2),
			BackgroundColor3 = if ready then Kit.color.gold elseif got then Kit.color.ink else Kit.color.night,
			BackgroundTransparency = if ready or got then 0 else 0.35,
		})
		Kit.stroke(cell, if ready then Kit.color.paper elseif got then GOT else DIM, if ready then 3 else 1)
		cell.Parent = row
		local ink = if ready then Kit.color.ink else Kit.color.paper
		local amount, kind = tileText(day, got)
		local top = Kit.label({
			Text = if got then "GOT" else "DAY " .. i,
			Size = UDim2.new(1, -6, 0, 18),
			Position = UDim2.fromOffset(3, 3),
			TextColor3 = if got then GOT else ink,
			maxText = 16,
		})
		top.Parent = cell
		local big = Kit.label({
			Text = amount,
			Size = UDim2.new(1, -6, 0, 26),
			Position = UDim2.fromOffset(3, 22),
			TextColor3 = ink,
			maxText = 24,
		})
		big.Parent = cell
		local small = Kit.label({
			Text = kind,
			Size = UDim2.new(1, -6, 0, 16),
			Position = UDim2.fromOffset(3, 50),
			TextColor3 = if ready then Kit.color.ink else DIM,
			Font = Kit.bodyFont,
			maxText = 12,
		})
		small.Parent = cell
		-- gap-icons2: the reward's comic icon in place of its kind word; a got day adds the tick on its corner
		local icon = Kit.icon("daily", string.lower(kind), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 46),
			Size = UDim2.fromOffset(26, 26),
			ImageTransparency = if got then 0.35 else 0,
		})
		if icon then
			icon.Parent = cell
			small.Visible = false
			local tick = got
				and Kit.icon("daily", "got", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.95, 0.8),
					Size = UDim2.fromScale(0.7, 0.7),
				})
			if tick then
				tick.Parent = icon
			end
		end
	end
end

local function drawQuests(d: { [string]: any })
	line("TODAY'S QUESTS", 26, 22, Kit.color.gold, Kit.font)
	if #d.quests == 0 then
		order += 1
		local note = Kit.stateNote(body, "empty", "No daily quests open today. New ones come at 00:00 UTC.")
		note.LayoutOrder = order
		return
	end
	for _, q in d.quests do
		order += 1
		local row = Kit.frame({
			Name = "Quest" .. q.slot,
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = Kit.color.ink,
			BackgroundTransparency = 0.2,
		})
		row.LayoutOrder = order
		row.Parent = body
		local text = Kit.label({
			Text = q.text,
			Size = UDim2.new(1, -96, 0, 22),
			Position = UDim2.fromOffset(8, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if q.done then GOT else Kit.color.paper,
			Font = Kit.bodyFont,
			maxText = 16,
		})
		text.Parent = row
		local count = Kit.label({
			Text = if q.done then "DONE" else string.format("%d / %d", q.have, q.n),
			Size = UDim2.fromOffset(80, 22),
			Position = UDim2.new(1, -86, 0, 4),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = if q.done then GOT else Kit.color.gold,
			maxText = 18,
		})
		count.Parent = row
		local bar = Kit.frame({
			Size = UDim2.new(1, -96, 0, 8),
			Position = UDim2.fromOffset(8, 34),
			BackgroundColor3 = Kit.color.night,
		})
		bar.Parent = row
		local fill = Kit.frame({
			Size = UDim2.fromScale(if q.n > 0 then math.clamp(q.have / q.n, 0, 1) else 0, 1),
			BackgroundColor3 = if q.done then GOT else Kit.color.gold,
		})
		fill.Parent = bar
		local pay = Kit.label({
			Text = string.format("+%s CR  +%s RN", comma(q.credits), comma(q.renown)),
			Size = UDim2.fromOffset(84, 16),
			Position = UDim2.new(1, -90, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = DIM,
			Font = Kit.bodyFont,
			maxText = 12,
		})
		pay.Parent = row
	end
	local b = d.bonus
	if b then
		line(
			if b.paid
				then "ALL 3 DONE: bonus paid. See you tomorrow!"
				else "ALL 3: " .. rewardText({ credits = b.credits, renown = b.renown, dust = b.dust }),
			22,
			16,
			if b.paid then GOT else Kit.color.paper
		)
	end
end

local function draw()
	if not panel.Visible then
		return
	end
	clear()
	local d = state
	if not d then
		if asked > 0 and os.clock() - asked > D.ui.answerWait then
			Kit.stateNote(body, "error", "The daily card did not load.", function()
				DailyHud.refresh()
			end)
		else
			Kit.stateNote(body, "loading", "Loading your daily streak...")
		end
		return
	end
	if d.offline then
		Kit.stateNote(
			body,
			"error",
			"Your save is offline right now, so today's streak waits for it. Rejoin in a moment to count it.",
			function()
				DailyHud.refresh()
			end
		)
		return
	end
	if d.on == false or type(d.days) ~= "table" then
		Kit.stateNote(body, "empty", "Daily rewards are taking a break. Check back soon!")
		return
	end
	line(
		string.format("STREAK %d  ·  BEST %d  ·  DAY %d OF %d", d.streak, d.best, d.day, #d.days),
		28,
		24,
		Kit.color.gold,
		Kit.font
	)
	drawTrack(d)
	local today = d.days[d.day]
	if d.owed and today then
		line("TODAY: " .. rewardText(today), 22, 16)
		order += 1
		local claim = Kit.button({
			Name = "Claim",
			Text = string.format("CLAIM DAY %d", d.day),
			Size = UDim2.new(1, 0, 0, T - 6),
			BackgroundColor3 = Kit.color.gold,
			pending = true,
		}, function()
			Net.send("DailyClaim")
		end)
		claim.LayoutOrder = order
		claim.Parent = body
		Kit.pulse(claim, 0.08)
	else
		local nextDay = d.day % #d.days + 1
		local tomorrow = d.days[nextDay]
		line(
			string.format(
				"Claimed! Tomorrow, day %d: %s",
				nextDay,
				if tomorrow and nextDay > d.day then rewardText(tomorrow) else "a new week"
			),
			22,
			16,
			GOT
		)
	end
	line(
		if d.grace
			then "Miss a day? Once a week a grace day keeps your streak going."
			else "This week's grace day is used: come back tomorrow to keep your streak.",
		20,
		14,
		DIM
	)
	drawQuests(d)
	line("A new day in " .. left() .. " (00:00 UTC)", 20, 14, DIM)
end

---------------------------------------------------------------------------
-- The small tracker
---------------------------------------------------------------------------

local function drawTracker()
	local d = state
	local quests = d and not d.offline and d.on ~= false and d.quests or nil
	local done = 0
	for _, q in quests or {} do
		if q.done then
			done += 1
		end
	end
	-- the DAILY button carries the count too (on a phone it is the whole small tracker)
	local count = if quests and #quests > 0 then string.format(" %d/%d", done, #quests) else ""
	openButton.Text = "DAILY" .. count .. (if d and d.owed then " !" else "")
	openButton.BackgroundColor3 = if d and d.owed then Kit.color.gold else Kit.color.paper
	local busy = StoryClient.inOpening() or CinemaClient.playing()
	tracker.Visible = quests ~= nil and #quests > 0 and not busy and not panel.Visible and not folded
	if not tracker.Visible or not quests then
		return
	end
	pill.Text = string.format("DAILY %d/%d%s", done, #quests, if d and d.owed then " !" else "")
	pill.BackgroundColor3 = if d and d.owed
		then Kit.color.gold
		elseif done == #quests then GOT
		else Kit.color.paper
	local open = pinned or os.clock() < openUntil
	rowsFrame.Visible = open
	for i, l in rowLabels do
		local q = quests[i]
		l.Visible = open and q ~= nil
		if q then
			l.Text = string.format(
				"%s  %s",
				q.text,
				if q.done then "DONE" else string.format("%d/%d", q.have, q.n)
			)
			l.TextColor3 = if q.done then GOT else Kit.color.paper
		end
	end
end

-- Where the pill goes (Shared.TouchLayout's HUD plan through Kit.hudBoxes): under the top row, from the
-- middle, stepped past every HUD part and the action buttons it would touch. A phone has no free spot (the
-- corner group, the move stick and the cluster fill it), so there the tracker folds into the DAILY button.
local function overlaps(a: { [string]: number }, b: { [string]: number }): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function placeTracker()
	local hb = Kit.hudBoxes()
	local a = Kit.area()
	local m = U.safe
	local w, h = 240, 44 + 3 * 28
	local y = m + P.row + P.gap
	local blockers = { hb.status, hb.buffs, hb.wallet, hb.radar, hb.radarText, hb.tracker, hb.squad }
	table.insert(blockers, TouchLayout.clusterBox(Config, a.X, a.Y, Kit.hudOptions() :: any))
	local x = math.floor((a.X - w) / 2)
	for _ = 1, #blockers do
		local moved = false
		for _, b in blockers do
			if overlaps({ x = x, y = y, w = w, h = h }, b) then
				x = math.ceil(b.x + b.w + P.gap)
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	local clash = false
	for _, b in blockers do
		clash = clash or overlaps({ x = x, y = y, w = w, h = h }, b)
	end
	folded = hb.compact or clash or x + w > a.X - m
	tracker.Position = UDim2.fromOffset(math.clamp(x, m, math.max(m, a.X - m - w)), y) -- on screen even folded
	tracker.Size = UDim2.fromOffset(w, h)
	drawTracker()
end

---------------------------------------------------------------------------

-- Ask the server again (the error state's RETRY)
function DailyHud.refresh()
	asked = os.clock()
	Net.send("DailyOpen")
	draw()
	task.delay(D.ui.answerWait + 0.1, function()
		if asked > 0 then
			draw()
		end
	end)
end

-- Open the card. d: a state to show at once (the headless UI check), else the last one and a refresh.
function DailyHud.open(d: { [string]: any }?)
	panel.Visible = true
	tracker.Visible = false
	if d then
		state = d
		draw()
		drawTracker()
		return
	end
	draw()
	DailyHud.refresh()
end

function DailyHud.close()
	panel.Visible = false
	drawTracker()
end

function DailyHud.isOpen(): boolean
	return panel.Visible
end

-- Keep the small tracker's rows open (a tap on the pill does the same; the headless UI check uses it)
function DailyHud.pin(on: boolean)
	pinned = on
	openUntil = 0
	drawTracker()
end

function DailyHud.init()
	gui = Kit.screen("Daily", 6)
	panel = Kit.frame({
		Name = "Card",
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	panel.Parent = gui
	Kit.fit(panel, 520, 300, 640, 560) -- phone pass: fits the safe area, scaled down a little at most
	PopupGate.card("daily", function()
		return panel.Visible
	end)
	local title = Kit.label({
		Text = "DAILY",
		Size = UDim2.new(1, -T - 30, 0, 34),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 30,
	})
	title.Parent = panel
	local close = Kit.button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(T, T - 10),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, DailyHud.close)
	close.Parent = panel
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, T)
	scroll.Size = UDim2.new(1, -28, 1, -T - 10)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = panel
	body = scroll
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = body

	openButton = Kit.button({
		Name = "DailyButton",
		Text = "DAILY",
		Size = UDim2.fromOffset(T * 2, T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if panel.Visible then
			DailyHud.close()
		else
			DailyHud.open()
		end
	end)
	Kit.dock(openButton, "Daily", 17) -- the top row (or its MORE drawer), after PASS

	-- the small tracker: the pill, then its 3 rows (display only, so the move stick works under them)
	tracker = Instance.new("Frame")
	tracker.Name = "Tracker"
	tracker.BackgroundTransparency = 1
	tracker.Visible = false
	tracker.Parent = Kit.screen("DailyTracker", 2) -- its own screen, under the panels
	pill = Kit.button({
		Name = "Pill",
		Text = "DAILY",
		Size = UDim2.new(0, 150, 0, 40),
		BackgroundColor3 = Kit.color.paper,
		maxText = 20,
	}, function()
		pinned = not pinned
		openUntil = 0
		drawTracker()
	end)
	pill.Parent = tracker
	rowsFrame = Instance.new("Frame")
	rowsFrame.Name = "Rows"
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Position = UDim2.fromOffset(0, 44)
	rowsFrame.Size = UDim2.new(1, 0, 0, 3 * 28)
	rowsFrame.Visible = false
	rowsFrame.Parent = tracker
	for i = 1, 3 do
		local r = Kit.label({
			Name = "Row" .. i,
			Text = "",
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, (i - 1) * 28),
			BackgroundTransparency = 0.25,
			BackgroundColor3 = Kit.color.night,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Kit.color.paper,
			Font = Kit.bodyFont,
			maxText = 14,
		})
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = r
		Kit.round(r, 6)
		r.Visible = false
		r.Parent = rowsFrame
		rowLabels[i] = r
	end
	placeTracker()
	Kit.LayoutChanged:Connect(placeTracker)
	StoryClient.Changed:Connect(drawTracker)
	CinemaClient.Changed:Connect(drawTracker)

	Net.listen("DailyState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		asked = 0
		state = d
		if typeof(d.resetIn) == "number" then
			resetAt = os.clock() + d.resetIn
		end
		Kit.settle()
		draw()
		drawTracker()
		if d.show and d.owed then
			-- the claim card on join (the server waited until the hero was free); on this device it also waits
			-- for the loading screen, the main menu and any other card (PopupGate: one card at a time)
			PopupGate.later("daily", function()
				if state and state.owed then
					panel.Visible = true
					tracker.Visible = false
					Kit.pulse(panel, 0.06)
					Kit.padFocus(panel, false)
					draw()
					drawTracker()
				end
			end)
		end
	end)
	Net.listen("DailyProgress", function(p: any)
		if type(p) ~= "table" then
			return
		end
		if p.kind == "claim" then
			Juice.fire("dailyClaim", nil, { day = p.day, streak = p.streak, title = p.title, mine = true })
		elseif p.kind == "quest" then
			Juice.fire("dailyQuest", nil, { text = p.text, mine = true })
			openUntil = os.clock() + D.ui.trackerShow
		elseif p.kind == "all" then
			Juice.fire("dailyQuest", nil, { all = true, text = rewardText(p), mine = true })
		elseif p.kind == "move" and state and type(state.quests) == "table" then
			for _, q in state.quests do
				if q.slot == p.slot then
					q.have = p.have
				end
			end
			openUntil = os.clock() + D.ui.trackerShow
			if panel.Visible then
				draw()
			end
		end
		drawTracker()
		task.delay(D.ui.trackerShow + 0.1, drawTracker)
	end)
	-- the reset countdown, and the next day's state once 00:00 UTC passes
	task.spawn(function()
		while gui.Parent do
			task.wait(30)
			if state and resetAt > 0 and os.clock() > resetAt + 5 then
				resetAt = 0
				DailyHud.refresh()
			elseif panel.Visible and state then
				draw()
			end
		end
	end)
end

return DailyHud
