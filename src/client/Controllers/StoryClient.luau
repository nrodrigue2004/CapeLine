-- StoryClient: the client's view of the story (spec: Opening; Act 1; Side quests; Story.State, Mission.State
-- 2 Hz, Choice.Pick). Screens and effects read these tables and listen to Changed; nothing is trusted.
-- * journal: the latest StoryState (missions, choices, quests, pin, perks, reputation, mission states)
-- * opening: the playable disaster's step and its points; while it runs the HUD shows only the step's verb
--   button and the sky holds at dusk
-- * choice: the open choice prompt (its id and verb labels)
-- * mission: the latest MissionState; result: the last MissionResult
-- * quest: the pinned side quest's step (QuestState) and the last NPC line (QuestTalk)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))

local WorldClient = require(script.Parent.WorldClient)

local StoryClient = {}

StoryClient.Changed = Signal.new() -- (what) "journal", "opening", "choice", "mission", "quest"
StoryClient.Result = Signal.new() -- (result) a mission's result card
StoryClient.Talk = Signal.new() -- (num, line, side) an NPC speaks
StoryClient.Fade = Signal.new() -- () a mission trip: fade out and back in

StoryClient.journal = nil :: { [string]: any }?
StoryClient.opening = { step = 0 } :: { [string]: any }
StoryClient.choice = nil :: { id: number, labels: { string } }?
StoryClient.mission = { num = 0 } :: { [string]: any }
StoryClient.quest = nil :: { [string]: any }?

-- The verb button(s) each opening step pulses (Hud.setFocus)
StoryClient.VERBS = {
	leap = { "Leap" },
	glide = { "Leap" }, -- the Leap button reads GLIDE in the air
	catch = { "Catch" },
	blast = { "Basic" },
	choice = { "Leap", "Basic" },
	save = { "Leap" },
	grab = { "Leap" },
	suitup = {},
	flight = nil, -- the full HUD is back for the guided flight
}

function StoryClient.openingStep(): string?
	return OpeningPlan.STEPS[StoryClient.opening.step or 0]
end

function StoryClient.inOpening(): boolean
	local s = StoryClient.openingStep()
	return s ~= nil and s ~= "flight"
end

function StoryClient.inMission(): boolean
	return (StoryClient.mission.num or 0) > 0
end

function StoryClient.pick(option: number)
	local c = StoryClient.choice
	if c then
		Net.send("ChoicePick", c.id, option)
		StoryClient.choice = nil
		StoryClient.Changed:Fire("choice")
	end
end

function StoryClient.catch()
	Net.send("OpeningAct", 1)
end

function StoryClient.skipFlight()
	Net.send("OpeningAct", 2)
end

function StoryClient.suitUp(classIdx: number, sideIdx: number)
	Net.send("SuitUp", classIdx, sideIdx)
end

function StoryClient.enter(num: number)
	Net.send("MissionEnter", num)
end

function StoryClient.leave()
	Net.send("MissionLeave")
end

function StoryClient.pin(num: number)
	Net.send("StoryPin", num)
end

function StoryClient.init()
	Net.listen("StoryState", function(s)
		StoryClient.journal = s
		StoryClient.Changed:Fire("journal")
	end)
	Net.listen("OpeningState", function(s)
		StoryClient.opening = s
		WorldClient.clockOverride = if StoryClient.inOpening() then Config.Story.opening.clockTime else nil
		StoryClient.Changed:Fire("opening")
	end)
	Net.listen("ChoicePrompt", function(c)
		StoryClient.choice = if c.id >= 0 then c else nil
		StoryClient.Changed:Fire("choice")
	end)
	Net.listen("MissionState", function(m)
		if m.fade then
			StoryClient.Fade:Fire()
			return
		end
		StoryClient.mission = m
		StoryClient.Changed:Fire("mission")
	end)
	Net.listen("MissionResult", function(r)
		StoryClient.Result:Fire(r)
	end)
	Net.listen("QuestState", function(q)
		q.received = os.clock()
		StoryClient.quest = if (q.num or 0) > 0 then q else nil
		StoryClient.Changed:Fire("quest")
	end)
	Net.listen("QuestTalk", function(t)
		StoryClient.Talk:Fire(t.num, t.line, t.side)
	end)
end

return StoryClient
