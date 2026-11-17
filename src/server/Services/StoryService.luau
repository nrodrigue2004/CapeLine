-- StoryService: the saved story and what it pays (spec: Act 1 choices; Faction reputation; Side quests;
-- Story perks live in the Journal). OpeningService, MissionService and QuestService run the world side and
-- call in here for everything that touches the save:
-- * choices: ask() puts big verb buttons in front of a player (ChoicePrompt) and ChoicePick answers the one
--   that is open; only an open prompt can be answered, so a client cannot pick a choice it was not asked.
--   Act choices go through StoryPlan.pick (once only) and pay their effects here.
-- * rewards: Skill Points (the hero's bonus points), reputation (Vigil Trust, Syndicate Fear, City), quest styles,
--   emotes, Photo Mode frames, HQ props, the Decoy gadget, loot and Credits.
-- * the Journal: StoryState after every change; StoryPin pins a side quest step (or the story).
-- * a citizen carried to safety anywhere adds City reputation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local GearMath = require(Shared:WaitForChild("GearMath"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local IncidentService = require(script.Parent.IncidentService)

local Bits = ProfileSchema.Bits
local S = Config.Story

local StoryService = {}
StoryService.Changed = Signal.new() -- (player) the story save changed (QuestService rebuilds the pinned step)
StoryService.Picked = Signal.new() -- (player, id, option) a choice was answered

-- Choice ids on the wire: 1 to 3 the Act 1 choices, 4 a side quest pick (Maribel's menu), 0 the opening
StoryService.QUEST_CHOICE = 4
StoryService.OPENING_CHOICE = 0

local pending: { [Player]: { id: number, count: number, fn: (number) -> () } } = {}

function StoryService.char(player: Player): any?
	local profile = DataService.get(player)
	return profile and ProfileSchema.active(profile)
end

function StoryService.story(player: Player): any?
	local c = StoryService.char(player)
	return c and c.story
end

function StoryService.side(player: Player): string
	local hero = HeroService.get(player)
	return if hero and hero.side == "villain" then "villain" else "hero"
end

function StoryService.setSide(player: Player, side: string)
	local c = StoryService.char(player)
	local hero = HeroService.get(player)
	local s = if side == "villain" then "villain" else "hero"
	if c then
		c.side = s
	end
	if hero then
		hero.side = s
		HeroService.sendState(hero)
	end
	DataService.changed(player)
end

---------------------------------------------------------------------------
-- Choices
---------------------------------------------------------------------------

-- Put a choice in front of a player; fn(option) runs once when they answer. A new ask replaces an old one.
function StoryService.ask(player: Player, id: number, labels: { string }, fn: (number) -> ())
	pending[player] = { id = id, count = #labels, fn = fn }
	Net.fire("ChoicePrompt", player, { id = id, labels = labels })
end

function StoryService.cancelAsk(player: Player)
	if pending[player] then
		pending[player] = nil
		Net.fire("ChoicePrompt", player, { id = -1, labels = {} })
	end
end

local function onPick(player: Player, id: number, option: number)
	local p = pending[player]
	if not p or p.id ~= id or option > p.count then
		return
	end
	pending[player] = nil
	p.fn(option)
	StoryService.Picked:Fire(player, id, option)
end

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------

function StoryService.addSkillPoints(player: Player, n: number)
	local hero = HeroService.get(player)
	if not hero or n <= 0 then
		return
	end
	hero.bonusPoints += n
	local c = StoryService.char(player)
	if c then
		c.bonusPoints = hero.bonusPoints
	end
	HeroService.sendState(hero)
	Net.fire("Toast", player, { id = "skillPoint", n = n })
end

-- track: "vigil", "syndicate", "city", or "side" (the hero's own: Vigil or Syndicate)
function StoryService.addRep(player: Player, track: string, amount: number)
	local c = StoryService.char(player)
	if not c or amount <= 0 then
		return
	end
	if track == "side" then
		track = if StoryService.side(player) == "villain" then "syndicate" else "vigil"
	end
	local i = StoryPlan.repIndex(Config, track)
	local before = StoryPlan.repRank(Config, c.rep[i])
	c.rep[i] = math.min(c.rep[i] + math.floor(amount), 999999)
	local after = StoryPlan.repRank(Config, c.rep[i])
	if after > before then
		Net.fire("Toast", player, { id = "repRank", track = track, rank = after })
	end
	DataService.changed(player)
end

local function unlockBit(player: Player, words: string, name: string)
	local profile = DataService.get(player)
	local n = S.unlocks[words] and S.unlocks[words][name]
	if profile and n and profile[words] then
		Bits.set(profile[words], n)
		Net.fire("Toast", player, { id = "unlock", kind = words, name = name })
		DataService.changed(player)
	end
end

-- A quest or choice reward table: { style, emote, frame, prop, gadget, loot, credits, renown, skillPoints }
function StoryService.pay(player: Player, reward: any, level: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if reward.credits then
		EconomyService.addCredits(player, reward.credits)
	end
	if reward.renown then
		EconomyService.addRenown(player, reward.renown)
	end
	if reward.skillPoints then
		StoryService.addSkillPoints(player, reward.skillPoints)
	end
	if reward.style then
		local id = GearMath.questStyle(Config, reward.style)
		if id then
			Bits.set(profile.styles, id)
			GearService.refresh(player)
			Net.fire("Toast", player, { id = "unlock", kind = "styles", name = reward.style })
		end
	end
	if reward.emote then
		unlockBit(player, "emotes", reward.emote)
	end
	if reward.frame then
		unlockBit(player, "frames", reward.frame)
	end
	if reward.prop then
		unlockBit(player, "props", reward.prop)
	end
	if reward.gadget then
		GearService.grantPiece(player, "Rare", level, { gadget = reward.gadget })
	end
	if reward.loot then
		GearService.grant(player, reward.loot, level)
	end
	DataService.changed(player)
	DataService.saveSoon(player)
end

-- Answer an Act 1 choice: once only, then its effects. Returns true the first time.
function StoryService.choose(player: Player, choiceNum: number, option: number): boolean
	local story = StoryService.story(player)
	local hero = HeroService.get(player)
	if not story or not hero then
		return false
	end
	local ok, fx = StoryPlan.pick(Config, story, choiceNum, option, StoryService.side(player))
	if not ok or not fx then
		return false
	end
	StoryService.addSkillPoints(player, fx.skillPoints)
	if fx.rep then
		StoryService.addRep(player, fx.rep[1], fx.rep[2])
	end
	StoryService.pay(player, { credits = fx.credits, renown = fx.renown, gadget = fx.gadget }, hero.level)
	if fx.perk then
		Net.fire("Toast", player, { id = "unlock", kind = "perks", name = fx.perk })
	end
	StoryService.send(player)
	return true
end

---------------------------------------------------------------------------
-- The Journal
---------------------------------------------------------------------------

function StoryService.send(player: Player)
	local c = StoryService.char(player)
	local hero = HeroService.get(player)
	if not c or not hero then
		return
	end
	local story = c.story
	-- story perks others can see (the Echo Drone, a drone buddy)
	player:SetAttribute("NullEcho", StoryPlan.bit(story.perks, S.perks.NullEcho.bit) or nil)
	local states = {}
	for num in S.missions do
		states[num] = StoryPlan.state(Config, story, hero.level, num)
	end
	Net.fire("StoryState", player, {
		side = StoryService.side(player),
		opening = story.opening,
		missions = story.missions,
		choices = story.choices,
		quests = story.quests,
		pinned = story.pinned,
		perks = story.perks,
		menu = story.menu,
		rep = c.rep,
		states = states,
	})
end

function StoryService.changed(player: Player)
	DataService.changed(player)
	StoryService.send(player)
	StoryService.Changed:Fire(player)
end

function StoryService.init()
	Net.on("ChoicePick", onPick)
	Net.on("StoryPin", function(player, num)
		local story = StoryService.story(player)
		if not story then
			return
		end
		if num == 0 or (story.quests[num] >= 1 and story.quests[num] <= 3) then
			story.pinned = num
			StoryService.changed(player)
		end
	end)
	DataService.Loaded:Connect(function(player)
		task.defer(StoryService.send, player)
	end)
	HeroService.Leveled:Connect(function(hero)
		if hero.player then
			StoryService.send(hero.player) -- a mission may have opened
		end
	end)
	IncidentService.Rescued:Connect(function(hero)
		if hero.player then
			StoryService.addRep(hero.player, "city", S.rep.rescue)
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return StoryService
