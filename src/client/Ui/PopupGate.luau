-- PopupGate: when a card the server pops by itself may show (onboarding check 2026-11-18). The join and
-- after-prologue cards (the daily claim card, the mentor picker, the weekly board's TOP 10 card) wait until
-- the player is free: no loading screen, main menu, hero creator, prologue or cutscene up, and none of the
-- other gated cards still open, so they come one at a time and never under a menu or over the story.
-- * PopupGate.card(name, isOpen): a gated card says how to tell it is up
-- * PopupGate.free(except): may a card show now? (except: the asking card's own name)
-- * PopupGate.later(name, show): run show once free (checked a few times a second; at most Config.Ui.popups.giveUp s, then
--   it shows anyway so nothing is lost)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local MainMenu = require(script.Parent.MainMenu)
local CreatorScreen = require(script.Parent.CreatorScreen)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)

local PopupGate = {}

local player = Players.LocalPlayer
local cards: { [string]: () -> boolean } = {}
local waiting: { [string]: boolean } = {}
local P = Config.Ui.popups

function PopupGate.card(name: string, isOpen: () -> boolean)
	cards[name] = isOpen
end

local function busy(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	return (pg ~= nil and pg:FindFirstChild("Loading") ~= nil)
		or MainMenu.isOpen()
		or CreatorScreen.isOpen()
		or StoryClient.inOpening()
		or CinemaClient.playing()
end

function PopupGate.free(except: string?): boolean
	if busy() then
		return false
	end
	for name, isOpen in cards do
		if name ~= except and isOpen() then
			return false
		end
	end
	return true
end

function PopupGate.later(name: string, show: () -> ())
	if waiting[name] then
		return
	end
	waiting[name] = true
	task.spawn(function()
		local t0 = os.clock()
		local calm: number? = nil
		local first = true
		while os.clock() - t0 < P.giveUp do
			if PopupGate.free(name) then
				if first then
					break -- free the moment it came: at once
				end
				calm = calm or os.clock()
				if os.clock() - (calm :: number) >= P.settle then
					break
				end
			else
				calm = nil
			end
			first = false
			task.wait(0.25)
		end
		waiting[name] = nil
		show()
	end)
end

return PopupGate
