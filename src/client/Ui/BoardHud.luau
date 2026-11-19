-- BoardHud: the weekly leaderboards on this device (spec: Global data and leaderboards, Weekly_<week> boards
-- for boss MVPs, rescues and PvP wins; gap check G2, WP2; Config.Boards, Shared.BoardKeys).
-- * The BOARDS button (top row or MORE) opens the screen: a tab per board, ALL or FRIENDS, the top 50 with
--   ranks (equal totals share one), your own row pinned under the list, the week's countdown and the reward
--   (the top 10 earn the board's title). Loading, empty and error states (RETRY) come from Kit.
-- * The plaza board: one SurfaceGui (ResetOnSpawn off) on Workspace.WeeklyBoard's screen with each board's
--   top 10, redrawn only when BoardPlaza brings rows that changed; the countdown ticks once a minute.
-- * A weekly title earned (BoardReward): the boardReward juice (sound, vibration) and the TOP 10 card here.
-- Names are Roblox display names the server sends; nothing on this screen is typed by a player.
-- gap-icons2 (2026-11-19): each board's tab and the TOP 10! card lead with the board's comic icon (Config.Icons
-- board: a crown for Boss MVPs, the lifebuoy for rescues, a trophy for PvP wins).
-- PLACEHOLDER ART: Kit frames and plain text until the UI pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local Kit = require(script.Parent.Kit)
local PopupGate = require(script.Parent.PopupGate)
local BadgeHud = require(script.Parent.BadgeHud)

local BoardHud = {}

local B = Config.Boards
local T = Config.Ui.touchTarget
local ROW = 34
local BTN = T - 6 -- buttons stay a full tap target when a phone draws the panel at 80%

local gui: ScreenGui
local panel: Frame
local body: ScrollingFrame
local info: TextLabel
local youRank: TextLabel
local youName: TextLabel
local youValue: TextLabel
local filterButton: TextButton
local tabButtons: { TextButton } = {}
local tab = 1
local filter = 0 -- 0 all, 1 friends
local answers: { [string]: { data: any, at: number } } = {}
local asked: { [string]: number } = {}
local endsAt = 0 -- os.clock() when the week ends (from the last answer)

local function keyOf(t: number, f: number): string
	return t .. ":" .. f
end

local function clear()
	for _, c in body:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

-- "3D 04H", "2H 05M", "4M"
local function left(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if d > 0 then
		return string.format("%dD %02dH", d, h)
	elseif h > 0 then
		return string.format("%dH %02dM", h, m)
	end
	return string.format("%dM", math.max(1, m))
end

local function units(b: any, n: number): string
	return Kit.comma(n) .. " " .. (if n == 1 then b.unit else b.units)
end

local function rowFrame(order: number, r: any, b: any): Frame
	local f = Kit.frame({
		Size = UDim2.new(1, -8, 0, ROW),
		BackgroundColor3 = if r.me then Color3.fromRGB(70, 58, 20) else Kit.color.night,
		BackgroundTransparency = if r.me then 0.05 else 0.35,
	})
	f.LayoutOrder = order
	if r.me then
		Kit.stroke(f, Kit.color.gold, 2)
	end
	local top3 = r.rank and r.rank <= 3
	local rank = Kit.label({
		Text = if r.rank then "#" .. r.rank else "-",
		Size = UDim2.new(0, 52, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if top3 then Kit.color.gold else Kit.color.paper,
		maxText = 18,
	})
	rank.Parent = f
	local name = Kit.label({
		Text = (if r.friend then "★ " else "") .. string.upper(r.name),
		Size = UDim2.new(1, -170, 1, -8),
		Position = UDim2.fromOffset(60, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if r.me then Kit.color.gold else Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 16,
	})
	name.Parent = f
	local value = Kit.label({
		Text = units(b, r.value),
		Size = UDim2.new(0, 104, 1, -8),
		Position = UDim2.new(1, -110, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	value.Parent = f
	f.Parent = body
	return f
end

local function drawInfo(d: any?)
	local b = B.boards[tab]
	local reward = string.format("TOP %d EARN THE TITLE %s", B.reward.top, string.upper(b.title))
	if d and d.owned then
		reward ..= " (YOU HAVE IT)"
	end
	local ends = if endsAt > 0 then "  ·  RESETS IN " .. left(endsAt - os.clock()) else ""
	info.Text = reward .. ends
end

local function drawYou(d: any?)
	local b = B.boards[tab]
	local mine = d and d.mine
	if not d or d.error then
		youRank.Text, youName.Text, youValue.Text = "-", "YOU", ""
		return
	end
	if mine then
		youRank.Text = if mine.rank then "#" .. mine.rank elseif d.cut then "100+" else "-"
		youValue.Text = units(b, mine.value)
	else
		youRank.Text = "-"
		youValue.Text = units(b, 0)
	end
	youName.Text = if mine then "YOU" else "YOU: NOT ON THIS BOARD YET"
end

local function draw()
	clear()
	for i, btn in tabButtons do
		btn.BackgroundColor3 = if i == tab then Kit.color.gold else Kit.color.paper
	end
	filterButton.Text = if filter == 1 then "FRIENDS" else "ALL"
	filterButton.BackgroundColor3 = if filter == 1 then Kit.color.volt else Kit.color.paper
	local a = answers[keyOf(tab, filter)]
	local d = a and a.data
	drawInfo(d)
	drawYou(d)
	if not d then
		Kit.stateNote(body, "loading", "Reading the board...")
		return
	end
	if d.error then
		Kit.stateNote(body, "error", "The board could not be read just now.", function()
			asked[keyOf(tab, filter)] = nil
			BoardHud.refresh()
		end)
		return
	end
	if #d.rows == 0 then
		Kit.stateNote(
			body,
			"empty",
			if filter == 1
				then "None of your friends are on this board this week yet."
				else "Nobody is on this board this week yet. Be the first!"
		)
		return
	end
	local b = B.boards[tab]
	for i, r in d.rows do
		rowFrame(i, r, b)
	end
end

-- Ask for the open tab (a fresh answer within 2 s is reused; the server caches for a minute anyway)
function BoardHud.refresh()
	local k = keyOf(tab, filter)
	local now = os.clock()
	if asked[k] and now - asked[k] < 2 then
		return
	end
	asked[k] = now
	local was = answers[k]
	Net.send("BoardOpen", tab, filter)
	task.delay(6, function()
		-- no answer: the error state with RETRY
		if answers[k] == was and asked[k] == now then
			answers[k] = { data = { error = true }, at = os.clock() }
			if panel.Visible and keyOf(tab, filter) == k then
				draw()
			end
		end
	end)
end

function BoardHud.open(which: number?)
	if which and B.boards[which] then
		tab = which
	end
	Kit.opening("BoardHud", panel, BoardHud.close, true) -- a main panel: the others close
	panel.Visible = true
	draw()
	BoardHud.refresh()
end

function BoardHud.close()
	panel.Visible = false
end

function BoardHud.isOpen(): boolean
	return panel.Visible
end

---------------------------------------------------------------------------
-- The plaza board
---------------------------------------------------------------------------

local plazaRows: { { TextLabel } } = {}
local plazaEnds: TextLabel? = nil
local plazaEndsAt = 0

local function buildPlaza(screen: BasePart)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "WeeklyBoard"
	sg.ResetOnSpawn = false
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 1.4
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = B.prop.pixelsPerStud
	sg.MaxDistance = B.prop.maxDistance
	sg.Adornee = screen
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(16, 22, 44)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local head = Kit.label({
		Text = "THIS WEEK'S TOP " .. B.plazaCount,
		Size = UDim2.fromScale(0.6, 0.12),
		Position = UDim2.fromScale(0.02, 0.01),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 60,
	})
	head.Parent = bg
	local ends = Kit.label({
		Text = "",
		Size = UDim2.fromScale(0.36, 0.1),
		Position = UDim2.fromScale(0.62, 0.02),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 30,
	})
	ends.Parent = bg
	plazaEnds = ends
	local n = #B.boards
	for i, b in B.boards do
		local x = (i - 1) / n
		local col = Kit.frame({
			Size = UDim2.new(1 / n, -8, 0.84, 0),
			Position = UDim2.new(x, 4, 0.14, 0),
			BackgroundColor3 = Kit.color.night,
			BackgroundTransparency = 0.2,
		})
		col.Parent = bg
		local title = Kit.label({
			Text = b.name,
			Size = UDim2.new(1, -8, 0.1, 0),
			Position = UDim2.new(0, 4, 0, 2),
			TextColor3 = Kit.color.gold,
			maxText = 34,
		})
		title.Parent = col
		local rows = {}
		for r = 1, B.plazaCount do
			local l = Kit.label({
				Text = "",
				Size = UDim2.new(1, -12, 0.082, 0),
				Position = UDim2.new(0, 6, 0.11 + (r - 1) * 0.088, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if r <= 3 then Kit.color.gold else Kit.color.paper,
				Font = Kit.bodyFont,
				maxText = 24,
			})
			l.Parent = col
			table.insert(rows, l)
		end
		plazaRows[i] = rows
	end
	sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function drawPlaza(p: any)
	for i, labels in plazaRows do
		local rows = p.boards and p.boards[i] or {}
		local b = B.boards[i]
		for r, l in labels do
			local row = rows[r]
			if row then
				l.Text = string.format(
					"#%d  %s  ·  %s",
					row.rank or r,
					string.upper(row.name),
					units(b, row.value)
				)
			else
				l.Text = if r == 1 and #rows == 0 then "Be the first this week!" else ""
			end
		end
	end
end

local function tickPlaza()
	if plazaEnds and plazaEndsAt > 0 then
		(plazaEnds :: TextLabel).Text = "RESETS IN " .. left(plazaEndsAt - os.clock())
	end
end

---------------------------------------------------------------------------
-- The reward card
---------------------------------------------------------------------------

local cardGui: ScreenGui
local card: Frame
local cardText: TextLabel
local cardLines: { string } = {}

local function showReward(d: any)
	local b = B.boards[1]
	for _, x in B.boards do
		if x.id == d.board then
			b = x
		end
	end
	table.insert(
		cardLines,
		string.format("#%d ON %s LAST WEEK: TITLE %s", d.rank, b.name, string.upper(tostring(d.title)))
	)
	cardText.Text = table.concat(cardLines, "\n")
	Kit.lead(card:FindFirstChild("Head") :: TextLabel, "board", b.id, 30)
	card.Visible = true
	Kit.pulse(card, 0.15)
	Juice.fire("boardReward", nil, { mine = true, title = d.title, rank = d.rank })
end

local function buildCard()
	cardGui = Kit.screen("BoardReward", 8)
	card = Kit.frame({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(420, 168),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	Kit.stroke(card, Kit.color.gold, 3)
	card.Parent = cardGui
	local head = Kit.label({
		Name = "Head",
		Text = "TOP " .. B.reward.top .. "!",
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.fromOffset(8, 6),
		TextColor3 = Kit.color.gold,
		maxText = 32,
	})
	head.Parent = card
	cardText = Kit.label({
		Text = "",
		Size = UDim2.new(1, -16, 0, 56),
		Position = UDim2.fromOffset(8, 42),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 15,
	})
	cardText.Parent = card
	local wear = Kit.button({
		Text = "WEAR IT",
		Size = UDim2.new(0.5, -12, 0, BTN),
		Position = UDim2.new(0, 8, 1, -BTN - 8),
	}, function()
		card.Visible = false
		table.clear(cardLines)
		BadgeHud.open("titles")
	end)
	wear.Parent = card
	local ok = Kit.button({
		Text = "NICE!",
		Size = UDim2.new(0.5, -12, 0, BTN),
		Position = UDim2.new(0.5, 4, 1, -BTN - 8),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		card.Visible = false
		table.clear(cardLines)
	end)
	ok.Parent = card
	Kit.fit(card, 340, 168, 420, 168) -- centred, and scaled down on a short phone
	PopupGate.card("board", function()
		return card.Visible
	end)
end

-- A BoardData answer (also the phone test's way in)
function BoardHud.receive(d: any)
	if type(d) ~= "table" or type(d.board) ~= "number" then
		return
	end
	if type(d.rows) ~= "table" and not d.error then
		return
	end
	d.rows = d.rows or {}
	answers[keyOf(d.board, d.filter or 0)] = { data = d, at = os.clock() }
	if type(d.endsIn) == "number" then
		endsAt = os.clock() + d.endsIn
	end
	if panel.Visible and d.board == tab and (d.filter or 0) == filter then
		draw()
	end
end

-- A BoardReward: a weekly title earned. It comes on join, so the card waits for the loading screen, the main
-- menu, the creator, the prologue, a cutscene and the other join cards (PopupGate); the title is saved already.
local queued: { any } = {}
function BoardHud.reward(d: any)
	if type(d) == "table" and type(d.rank) == "number" then
		table.insert(queued, d)
		PopupGate.later("board", function()
			for _, q in queued do
				showReward(q)
			end
			table.clear(queued)
		end)
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function BoardHud.init()
	gui = Kit.screen("BoardHud", 6)
	panel = Kit.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 600),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	Kit.fit(panel, 440, 300, 560, 680) -- phone pass: fits the screen (a scale under 440 x 300)
	panel.Parent = gui
	local title = Kit.label({
		Text = "WEEKLY BOARDS",
		Size = UDim2.new(1, -T - 30, 0, 40),
		Position = UDim2.fromOffset(14, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 30,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, BTN),
		Position = UDim2.new(1, -T - 8, 0, 4),
		BackgroundColor3 = Kit.color.paper,
	}, BoardHud.close)
	close.Parent = panel
	-- the tabs and the ALL / FRIENDS switch, one row
	local n = #B.boards + 1
	for i, b in B.boards do
		local btn = Kit.button({
			Text = b.name,
			Size = UDim2.new(1 / n, -8, 0, BTN),
			Position = UDim2.new((i - 1) / n, 6, 0, 56),
			BackgroundColor3 = Kit.color.paper,
			maxText = 18,
		}, function()
			tab = i
			draw()
			BoardHud.refresh()
		end)
		btn.Parent = panel
		Kit.lead(btn, "board", b.id, BTN - 14)
		tabButtons[i] = btn
	end
	filterButton = Kit.button({
		Text = "ALL",
		Size = UDim2.new(1 / n, -8, 0, BTN),
		Position = UDim2.new((n - 1) / n, 2, 0, 56),
		BackgroundColor3 = Kit.color.paper,
		maxText = 18,
	}, function()
		filter = 1 - filter
		draw()
		BoardHud.refresh()
	end)
	filterButton.Parent = panel
	info = Kit.label({
		Text = "",
		Size = UDim2.new(1, -28, 0, 18),
		Position = UDim2.fromOffset(14, 56 + BTN + 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.muted,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	info.Parent = panel
	local top = 56 + BTN + 26
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, top)
	scroll.Size = UDim2.new(1, -28, 1, -top - ROW - 20)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = panel
	body = scroll
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = body
	-- your own row, pinned under the list
	local you = Kit.frame({
		Name = "You",
		Size = UDim2.new(1, -28, 0, ROW + 4),
		Position = UDim2.new(0, 14, 1, -ROW - 12),
		BackgroundColor3 = Color3.fromRGB(70, 58, 20),
	})
	Kit.stroke(you, Kit.color.gold, 2)
	you.Parent = panel
	youRank = Kit.label({
		Text = "-",
		Size = UDim2.new(0, 60, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 18,
	})
	youRank.Parent = you
	youName = Kit.label({
		Text = "YOU",
		Size = UDim2.new(1, -190, 1, -8),
		Position = UDim2.fromOffset(70, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	youName.Parent = you
	youValue = Kit.label({
		Text = "",
		Size = UDim2.new(0, 110, 1, -8),
		Position = UDim2.new(1, -116, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	youValue.Parent = you
	-- the top row button
	local open = Kit.button({
		Name = "BoardsButton",
		Text = "BOARDS",
		Size = UDim2.fromOffset(T * 2 + 20, T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if panel.Visible then
			BoardHud.close()
		else
			BoardHud.open()
		end
	end)
	Kit.dock(open, "Boards", 18) -- the top row (or its MORE drawer), after PASS and DAILY
	buildCard()
	Net.listen("BoardData", BoardHud.receive)
	Net.listen("BoardReward", BoardHud.reward)
	local lastPlaza: any = nil
	Net.listen("BoardPlaza", function(p: any)
		if type(p) ~= "table" or type(p.boards) ~= "table" then
			return
		end
		lastPlaza = p
		if type(p.endsIn) == "number" then
			plazaEndsAt = os.clock() + p.endsIn
		end
		if #plazaRows > 0 then
			drawPlaza(p)
			tickPlaza()
		end
	end)
	task.spawn(function()
		local model = Workspace:WaitForChild("WeeklyBoard", 120)
		local screen = model and model:WaitForChild("Screen", 30)
		if not screen or not screen:IsA("BasePart") then
			return
		end
		buildPlaza(screen)
		if lastPlaza then
			drawPlaza(lastPlaza)
		end
		while true do
			tickPlaza() -- the countdown, once a minute (the rows redraw only on a change)
			if panel.Visible then
				drawInfo(answers[keyOf(tab, filter)] and answers[keyOf(tab, filter)].data)
			end
			task.wait(60)
		end
	end)
end

return BoardHud
