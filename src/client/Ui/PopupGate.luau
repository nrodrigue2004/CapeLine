-- PopupGate: when a card the server pops by itself may show (onboarding check 2026-11-18). The join and
-- after-prologue cards (the daily claim card, the mentor picker, the weekly board's TOP 10 card) wait until
-- the player is free: no loading screen, main menu, hero creator, prologue or cutscene up, and none of the
-- other gated cards still open, so they come one at a time and never under a menu or over the story.
-- * PopupGate.card(name, isOpen, obj?, close?): a gated card says how to tell it is up, and (fix-hud 2026-11-19)
--   its panel (or a function giving it) and how it closes, so its life, the X, a tap and Backspace take it down
-- * PopupGate.free(except): may a card show now? (except: the asking card's own name)
-- * PopupGate.later(name, show): run show when its turn comes in Ui.Popups' line (pt-ui 2026-11-19: one card at a
--   time with every other popup, by priority, never in a fight for the starter offer)

local Players = game:GetService("Players")

local MainMenu = require(script.Parent.MainMenu)
local CreatorScreen = require(script.Parent.CreatorScreen)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local Popups = require(script.Parent.Popups)

local PopupGate = {}

local player = Players.LocalPlayer
local cards: { [string]: () -> boolean } = {}
local closers: { [string]: () -> () } = {}
local waiting: { [string]: boolean } = {}

function PopupGate.card(name: string, isOpen: () -> boolean, obj: any?, close: (() -> ())?)
	cards[name] = isOpen
	if obj ~= nil then
		Popups.panel(name, obj)
	end
	if close then
		closers[name] = close
	end
end

local function busy(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	return (pg ~= nil and pg:FindFirstChild("Loading") ~= nil)
		or MainMenu.isOpen()
		or CreatorScreen.isOpen()
		or StoryClient.inOpening()
		or CinemaClient.playing()
end

-- (pt-ui 2026-11-19) the gate is Ui.Popups' busy rule: no new card over the loading screen, menu, creator,
-- prologue or a cutscene
Popups.busy = busy

function PopupGate.free(except: string?): boolean
	if busy() then
		return false
	end
	for name, isOpen in cards do
		if name ~= except and isOpen() then
			return false
		end
	end
	-- nor while another popup card (a result card, an invite, a name card) is up (Ui.Popups)
	return not Popups.cardUp() or (except ~= nil and Popups.cardUp(except))
end

-- The card waits in Ui.Popups' line (Config.Ui.popups.cards[name]: its priority; the starter offer never comes
-- in a fight), after the screen has been free for `settle` s; it holds the card slot while it is open
function PopupGate.later(name: string, show: () -> ())
	if waiting[name] then
		return
	end
	waiting[name] = true
	local spec = Popups.spec(name)
	local item: any = Popups.card(name, spec, function()
		waiting[name] = nil
		show()
	end, function()
		local isOpen = cards[name]
		return isOpen ~= nil and isOpen()
	end, function()
		waiting[name] = nil
		local close = closers[name]
		if close then
			close()
		end
	end)
	if item.dropped then
		waiting[name] = nil -- (Settings "Popups" left it out: a later one may ask again)
	end
end

return PopupGate
