-- ReturnHud (retention pass, alive-world 2026-11-20): the WELCOME BACK card. A returning hero's join (once the
-- daily claim card has had its turn, Ui.PopupGate) shows what changed since they left (the streak, a new week and
-- its BOUNTY boss, a nemesis waiting) and a short TO DO list, most rewarding first, each row with a GO button that
-- opens the screen that does it (DAILY, the Hero Pass, the MAP, the Journal, WANTED). The FRIEND BOOST line shows
-- when friends are here. The TO DO button in the MENU drawer asks for it again at any time (TO DO with a "!" while a
-- reward is waiting to be claimed). Every line is fixed text from Shared.ReturnPlan (no free text).
-- * Juice: "welcomeBack" (page flip and chime; the card slides in and its rows tick in one by one).
-- PLACEHOLDER ART: Kit frames and text until the UI pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Kit = require(script.Parent.Kit)
local PopupGate = require(script.Parent.PopupGate)
local Juice = require(script.Parent.Parent.Fx.Juice)

local ReturnHud = {}

local T = Config.Ui.touchTarget
local W = Config.Daily.welcome
local PW, PH = 520, 420
local gui: ScreenGui
local panel: Frame
local title: TextLabel
local body: ScrollingFrame
local openButton: TextButton
local state: { [string]: any }? = nil
local drawn = 0 -- each draw's number: a newer draw stops an older one's tick-in

-- The rows that mean a reward is waiting: the TO DO button gets its "!" (and MENU too)
local URGENT = { claim = true, passClaim = true, boss = true, showdown = true }

-- Where each row's GO goes (lazy requires: these screens require much of the HUD themselves)
local function go(key: string)
	local Ui = script.Parent
	ReturnHud.close()
	if key == "daily" then
		(require(Ui.DailyHud) :: any).open()
	elseif key == "pass" or key == "episode" then
		(require(Ui.PassHud) :: any).open(key)
	elseif key == "map" or key == "contracts" then
		(require(Ui.MapScreen) :: any).open()
	elseif key == "wanted" then
		(require(Ui.NemesisHud) :: any).open()
	elseif key == "story" or key == "quests" or key == "goals" then
		(require(Ui.Journal) :: any).open(key)
	end
end
ReturnHud.go = go

local function clear()
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function line(order: number, text: string, color: Color3, size: number, max: number): TextLabel
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, -8, 0, size),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		maxText = max,
		LayoutOrder = order,
	})
	l.Parent = body
	return l
end

-- One TO DO row: the line, its note under it, GO on the right
local function todoRow(order: number, r: { [string]: any }): Frame
	local row = Kit.frame({
		Name = "Todo_" .. tostring(r.id),
		Size = UDim2.new(1, -8, 0, 58),
		BackgroundColor3 = Kit.color.paper,
		BackgroundTransparency = 0.88,
		LayoutOrder = order,
	})
	local gw = if r.go then T * 2 else 0
	local head = Kit.label({
		Text = tostring(r.text),
		Size = UDim2.new(1, -gw - 18, 0, 30),
		Position = UDim2.fromOffset(8, 2),
		TextColor3 = if URGENT[r.id] then Kit.color.gold else Kit.color.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 20,
	})
	head.Parent = row
	local note = Kit.label({
		Text = tostring(r.note or ""),
		Size = UDim2.new(1, -gw - 18, 0, 22),
		Position = UDim2.fromOffset(8, 32),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 15,
	})
	note.Parent = row
	if r.go then
		local b = Kit.button({
			Name = "Go",
			Text = "GO",
			Size = UDim2.fromOffset(gw - 8, T - 10),
			Position = UDim2.new(1, -gw, 0.5, -(T - 10) / 2),
			BackgroundColor3 = if URGENT[r.id] then Kit.color.gold else Kit.color.paper,
		}, function()
			go(r.go)
		end)
		b.Parent = row
	end
	row.Parent = body
	return row
end

local function draw(tick: boolean)
	drawn += 1
	local me = drawn
	clear()
	local s = state
	if not s then
		title.Text = "TO DO"
		line(1, "Loading...", Kit.color.paper, 30, 18)
		return
	end
	title.Text = tostring(s.title or "WELCOME BACK!")
	local order = 0
	local shown: { GuiObject } = {}
	for _, n in (s.news or {}) :: { any } do
		order += 1
		table.insert(shown, line(order, tostring(n.text), Kit.color.gold, 30, 22))
		order += 1
		table.insert(shown, line(order, tostring(n.note or ""), Kit.color.paper, 24, 15))
	end
	if s.friends then
		order += 1
		table.insert(shown, line(order, tostring(s.friends), Kit.color.gold, 28, 18))
	end
	order += 1
	line(order, "TO DO", Kit.color.gold, 28, 20)
	local todo = (s.todo or {}) :: { any }
	for _, r in todo do
		order += 1
		table.insert(shown, todoRow(order, r))
	end
	if #todo == 0 then
		order += 1
		line(order, "All caught up! Fly the city: incidents pop up all the time", Kit.color.paper, 30, 16)
	end
	-- the tick-in: rows show one after another
	if tick then
		for i, g in shown do
			g.Visible = false
			task.delay(0.12 + i * 0.07, function()
				if drawn == me and g.Parent then
					g.Visible = true
				end
			end)
		end
	end
end

local function urgent(s: { [string]: any }?): boolean
	for _, r in (s and s.todo or {}) :: { any } do
		if URGENT[r.id] then
			return true
		end
	end
	return false
end

-- A card from the server (or a test): draw it; show = the join's own pop
function ReturnHud.apply(d: any)
	if type(d) ~= "table" then
		return
	end
	state = d
	openButton.Text = "TO DO" .. (if urgent(d) then " !" else "") -- (like DAILY !: MENU ! in gold)
	if d.show then
		PopupGate.later("welcome", function()
			ReturnHud.open(state, true)
		end)
	elseif panel.Visible then
		draw(false)
	end
end

-- Open the card. d: a card to show at once (the headless UI check), else the last one and a refresh.
function ReturnHud.open(d: { [string]: any }?, popped: boolean?)
	if d then
		state = d
	else
		Net.send("ReturnOpen")
	end
	if popped then
		Kit.padFocus(panel, false) -- a card that pops mid-play: the stick keeps moving the hero
	else
		Kit.opening("ReturnHud", panel, ReturnHud.close, true)
	end
	panel.Visible = true
	Kit.pulse(panel, 0.06)
	draw(true)
	Juice.fire("welcomeBack", nil, { mine = true })
	openButton.Text = "TO DO" -- seen: the "!" goes until the next card says a reward waits
end

function ReturnHud.close()
	panel.Visible = false
end

function ReturnHud.isOpen(): boolean
	return panel.Visible
end

function ReturnHud.init()
	gui = Kit.screen("Welcome", 6)
	panel = Kit.frame({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PW, PH),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	Kit.stroke(panel, Kit.color.gold, 3)
	Kit.fit(panel, PW, 300, 600, 520) -- phone pass: fits the safe area, scaled down a little at most
	panel.Parent = gui
	PopupGate.card("welcome", function()
		return panel.Visible
	end)
	PopupGate.closeWith("welcome", panel, ReturnHud.close)
	title = Kit.label({
		Text = "WELCOME BACK!",
		Size = UDim2.new(1, -T - 30, 0, 36),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 28,
	})
	title.Parent = panel
	local close = Kit.button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(T, T - 10),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, ReturnHud.close)
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
		Name = "ToDoButton",
		Text = "TO DO",
		Size = UDim2.fromOffset(T * 2, T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if panel.Visible then
			ReturnHud.close()
		else
			ReturnHud.open()
		end
	end)
	Kit.dock(openButton, "ToDo", 17.5) -- the MENU drawer, after DAILY
	openButton.Visible = W.on

	Net.listen("ReturnCard", ReturnHud.apply)
end

return ReturnHud
