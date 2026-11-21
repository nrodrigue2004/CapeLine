-- MoveTutor: teaching the mobility moves (first-30, 2026-11-20: "the first use of a new mobility move at rank 3:
-- does the player learn it exists and how to do it?"). The 20 moves (Config.Move.moves, picked at ranks 3 and 5 in
-- POWERS > MOBILITY) went off from movement alone, with nothing on screen saying how.
-- * A move picked this session: a NEW MOVE card in the popup line (Ui.Popups "moveNew": its life, an X, a tap and
--   Backspace close it) with the move's name, what it does (its Config.Move text) and how to do it on this device
--   (Config.Move.moves[id].how through MoveActs.howTo, list-combat's words on the MOBILITY cards).
-- * Using a move: its name stamped big (JuiceFx.stamp) the first `named` times a session, so a move that fires
--   by itself (a dive, a hard stop, a landing) is never a mystery.
-- * Once a session, `remind` s after joining, a move this hero has but has not used yet gets the card again.
-- Reads MoveController.Acted (the device's own moves); changes nothing in how they work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MoveRanks = require(Shared:WaitForChild("MoveRanks"))
local MoveActs = require(Shared:WaitForChild("MoveActs"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))

local Kit = require(script.Parent.Kit)
local Popups = require(script.Parent.Popups)
local State = require(script.Parent.Parent.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local JuiceFx = require(script.Parent.Parent.Fx.JuiceFx)

local MoveTutor = {}

local T = Config.Ui.moveTutor
local MOVES = Config.Move.moves
local GOLD = Color3.fromRGB(255, 205, 70)

local card: Frame? = nil
local cardTag: TextLabel? = nil
local cardTitle: TextLabel? = nil
local cardBody: TextLabel? = nil
local cardHow: TextLabel? = nil

local known: { [string]: boolean }? = nil -- the moves this hero had when this device first saw it
local used: { [string]: number } = {} -- this session's uses by move
local startedAt = os.clock()
local reminded = false

-- How to do a move on this device, or nil: the move's own words (Config.Move.moves[id].how through
-- MoveActs.howTo, the same as its MOBILITY card), the buttons named for this device
function MoveTutor.how(id: string): string?
	local m = MOVES[id]
	if not m or not m.how then
		return nil
	end
	local dev = InputController.device
	return MoveActs.howTo(Config.Move, id, if dev == "touch" or dev == "gamepad" then dev else "mouse")
end

-- The moves this hero has now
function MoveTutor.active(): { [string]: boolean }
	local h = State.hero
	return MoveRanks.active(Config.Move, h.mobRanks, h.mobMoves, h.mobility or "flight")
end

local function buildCard()
	local gui = Kit.screen("MoveTutor", 7)
	local f = Kit.frame({
		Name = "MoveCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 0),
		Size = UDim2.new(0.9, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(360, 240) -- smaller (nate 2026-11-21)
	limit.Parent = f
	Kit.stroke(f, GOLD, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 44) -- clear of the X
	pad.Parent = f
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	local function line(name: string, h: number, size: number, font: Enum.Font, color: Color3, order: number)
		local l = Kit.label({
			Name = name,
			Text = "",
			Size = UDim2.new(1, 0, 0, h),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			Font = font,
			TextWrapped = true,
			TextScaled = false,
			TextSize = size,
			maxText = size,
		})
		l.LayoutOrder = order
		l.Parent = f
		return l
	end
	cardTag = line("Tag", 16, 14, Kit.bodyFont, GOLD, 1)
	cardTitle = line("Title", 24, 22, Kit.font, Kit.color.paper, 2) -- smaller (nate 2026-11-21)
	cardBody = line("Body", 20, 16, Kit.bodyFont, Kit.color.paper, 3)
	cardHow = line("How", 18, 16, Kit.font, GOLD, 4)
	f.Parent = gui
	card = f
	Popups.panel("moveNew", function()
		return card
	end)
end

-- Show move `id`'s card (it waits its turn in the popup line); tag: T.tagNew or T.tagTry
function MoveTutor.show(id: string, tag: string?)
	local m = MOVES[id]
	if not m then
		return
	end
	if not card then
		buildCard()
	end
	Popups.show("moveNew", function()
		if not (card and cardTag and cardTitle and cardBody and cardHow) then
			return
		end
		cardTag.Text = tag or T.tagNew
		cardTitle.Text = string.upper(m.name)
		cardBody.Text = m.text or ""
		local how = MoveTutor.how(id)
		cardHow.Text = if how then T.howPrefix .. how else ""
		cardHow.Visible = how ~= nil
		card.Visible = true
	end, function()
		return card ~= nil and card.Visible
	end, function()
		if card then
			card.Visible = false
		end
	end, m.name)
end

-- A move just went off on this device: its name, the first few times a session
function MoveTutor.acted(id: string)
	local m = MOVES[id]
	if not m then
		return
	end
	used[id] = (used[id] or 0) + 1
	if used[id] <= T.named then
		JuiceFx.stamp(string.upper(m.name) .. "!", GOLD)
	end
end

-- The hero's moves changed (a sync): a move that is new since this device first saw the hero gets its card
function MoveTutor.sync()
	local now = MoveTutor.active()
	if not known then
		if State.hero.mobMoves == nil then
			return -- no hero yet
		end
		known = now
		return
	end
	local k = known :: { [string]: boolean }
	for id in now do
		if not k[id] then
			k[id] = true
			MoveTutor.show(id, T.tagNew)
		end
	end
end

local function tick()
	if reminded or os.clock() - startedAt < T.remind then
		return
	end
	reminded = true
	local ids = {}
	for id in MoveTutor.active() do
		if (used[id] or 0) == 0 then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	if ids[1] then
		MoveTutor.show(ids[1], T.tagTry)
	end
end

function MoveTutor.init()
	startedAt = os.clock()
	State.Changed:Connect(MoveTutor.sync)
	MoveTutor.sync()
	MoveController.Acted:Connect(function(id)
		MoveTutor.acted(id)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("MoveTutor", function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			tick()
		end
	end))
end

return MoveTutor
