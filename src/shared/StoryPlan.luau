--!strict
-- StoryPlan: Act 1 and side quest rules on the saved story table (spec: Act 1: Shardfall; Act 1 choices;
-- Side quests; Faction reputation). Pure, so Lune checks the gates, the choices, the Skill Point total and
-- the step counts. MissionService, QuestService and StoryService do the world side.
-- * Missions open in order (mission n needs mission n - 1 cleared) at their minimum level; cleared ones
--   can be replayed, and only the first clear pays.
-- * A choice is picked once (later replays keep the first pick) and grants its Skill Points once.
-- * steps(): a mission's steps for a side, with the branch a choice picked put in place and the Trust Her
--   shortcut applied to the gauntlet.
-- * Objective progress: need() says how much each step takes; a run is { idx, have } over its steps.

local StoryPlan = {}

local function bit(mask: number, n: number): boolean
	return (mask // 2 ^ (n - 1)) % 2 == 1
end

local function setBit(mask: number, n: number): number
	if bit(mask, n) then
		return mask
	end
	return mask + 2 ^ (n - 1)
end
StoryPlan.bit = bit
StoryPlan.setBit = setBit

function StoryPlan.mission(Config: any, num: number): any?
	return Config.Story.missions[num]
end

function StoryPlan.cleared(story: any, num: number): boolean
	return bit(story.missions, num)
end

-- "done", "open", "level" (open but the hero is too low) or "locked" (the one before is not cleared)
function StoryPlan.state(Config: any, story: any, level: number, num: number): string
	local m = Config.Story.missions[num]
	if not m then
		return "locked"
	end
	if StoryPlan.cleared(story, num) then
		return "done"
	end
	if num > 1 and not StoryPlan.cleared(story, num - 1) then
		return "locked"
	end
	if level < m.minLevel then
		return "level"
	end
	return "open"
end

-- Can this hero enter mission num now? Missions 2 to 6 only (1 is the opening). Replays allowed.
function StoryPlan.canEnter(Config: any, story: any, level: number, num: number): (boolean, string?)
	local m = Config.Story.missions[num]
	if not m or m.opening then
		return false, "mission"
	end
	local st = StoryPlan.state(Config, story, level, num)
	if st == "done" or st == "open" then
		return true, nil
	end
	return false, st
end

-- The next mission to play (the pinned story step), or nil when Act 1 is done
function StoryPlan.nextMission(Config: any, story: any): number?
	for num in Config.Story.missions do
		if not StoryPlan.cleared(story, num) then
			return num
		end
	end
	return nil
end

-- A mission's steps for a side, with chosen branches in place. choices: the story's picks.
function StoryPlan.steps(Config: any, num: number, side: string, choices: { number }): { any }
	local m = Config.Story.missions[num]
	local list = if side == "villain" then m.villain else m.hero
	local out = {}
	for _, step in list or {} do
		if step.kind == "branch" then
			local pick = choices[step.choice]
			local b = m.branches and pick and pick > 0 and m.branches[pick]
			if b and b.kind ~= "none" then
				table.insert(out, b)
			end
		elseif step.kind == "reach" and step.turrets and choices[2] == 1 then
			-- Trust Her: the informant's shortcut leaves fewer turrets in the gauntlet
			local s = table.clone(step)
			s.turrets = step.trustTurrets or step.turrets
			table.insert(out, s)
		else
			table.insert(out, step)
		end
	end
	return out
end

-- Is the next step a branch still waiting on its choice? (the branch is resolved once the choice is in)
function StoryPlan.pendingBranch(Config: any, num: number, side: string, idx: number): number?
	local m = Config.Story.missions[num]
	local list = if side == "villain" then m.villain else m.hero
	local step = list and list[idx]
	return if step and step.kind == "branch" then step.choice else nil
end

-- How much progress a step takes
function StoryPlan.need(step: any): number
	local k = step.kind
	if k == "hold" then
		return (step.points or 1) * step.seconds
	elseif k == "break" then
		return step.points or 1
	elseif k == "defeat" then
		local n = 0
		for _, s in step.squads do
			n += s[2]
		end
		return n
	elseif k == "fetch" or k == "photo" or k == "spot" then
		return step.count or 1
	elseif k == "race" then
		return step.checkpoints
	elseif k == "escort" then
		return step.goal
	elseif k == "beacon" then
		return step.seconds
	end
	return 1 -- reach, choice, chase, boss, warframe, carry, deliver, find
end

-- A choice: returns ok and the effects to pay ({ skillPoints, rep = { track, amount }, credits, renown,
-- gadget, perk, shortcut, epicChance, arena }) the first time; a replay pick changes nothing.
function StoryPlan.pick(
	Config: any,
	story: any,
	choiceNum: number,
	option: number,
	side: string
): (boolean, any?)
	local c = Config.Story.choices[choiceNum]
	if not c or not c.options[option] then
		return false, nil
	end
	if story.choices[choiceNum] ~= 0 then
		return false, nil -- already picked
	end
	story.choices[choiceNum] = option
	local o = c.options[option]
	local fx: { [string]: any } = {
		skillPoints = c.skillPoints,
		credits = o.credits,
		renown = o.renown,
		gadget = o.gadget,
		perk = o.perk,
		shortcut = o.shortcut,
		epicChance = o.epicChance,
		arena = o.arena,
	}
	if o.rep then
		local track = o.rep[1]
		if track == "side" then
			track = if side == "villain" then "syndicate" else "league"
		end
		fx.rep = { track, o.rep[2] }
	end
	if o.perk then
		story.perks = setBit(story.perks, Config.Story.perks[o.perk].bit)
	end
	return true, fx
end

-- The button labels for a choice on a side
function StoryPlan.labels(Config: any, choiceNum: number, side: string): { string }
	local out = {}
	for _, o in Config.Story.choices[choiceNum].options do
		table.insert(out, if side == "villain" and o.villainLabel then o.villainLabel else o.label)
	end
	return out
end

-- Skill Points Act 1 grants in all: every choice plus the missions that give one (spec: 8)
function StoryPlan.actSkillPoints(Config: any): number
	local n = 0
	for _, c in Config.Story.choices do
		n += c.skillPoints
	end
	for _, m in Config.Story.missions do
		n += m.skillPoints or 0
	end
	return n
end

-- Mark a first clear; returns true if this was the first
function StoryPlan.clear(story: any, num: number): boolean
	if bit(story.missions, num) then
		return false
	end
	story.missions = setBit(story.missions, num)
	return true
end

-- Reputation: rank 0 to 5 from points
function StoryPlan.repRank(Config: any, points: number): number
	local r = 0
	for i, need in Config.Story.rep.ranks do
		if points >= need then
			r = i
		end
	end
	return r
end

function StoryPlan.repIndex(Config: any, track: string): number
	return table.find(Config.Story.rep.order, track) or 3
end

-- Side quests: state per arc (0 not started, 1 to 3 the current step, 4 done)
function StoryPlan.quest(Config: any, num: number): any?
	return Config.Story.quests[num]
end

function StoryPlan.startQuest(story: any, num: number): boolean
	if story.quests[num] ~= 0 then
		return false
	end
	story.quests[num] = 1
	return true
end

-- Finish the current step; returns "next" (another step), "done" (the arc is complete, pay it) or nil
function StoryPlan.advanceQuest(story: any, num: number): string?
	local s = story.quests[num]
	if s < 1 or s > 3 then
		return nil
	end
	story.quests[num] = s + 1
	return if s + 1 >= 4 then "done" else "next"
end

-- Is this quest offered to a side? (all 8 are; Old Beacon's drills come from the Velvet Paw for villains)
function StoryPlan.npcName(Config: any, num: number, side: string): string
	local q = Config.Story.quests[num]
	return if side == "villain" and q.villainNpc then q.villainNpc else q.npc
end

-- What the journal pins: the side quest the hero pinned, else the next story mission
function StoryPlan.pinnedText(Config: any, story: any, side: string): string?
	local p = story.pinned
	if p > 0 then
		local q = Config.Story.quests[p]
		local s = story.quests[p]
		if q and s >= 1 and s <= 3 then
			return q.steps[s].text
		end
	end
	local num = StoryPlan.nextMission(Config, story)
	if not num then
		return nil
	end
	local m = Config.Story.missions[num]
	local name = if side == "villain" and m.villainName then m.villainName else m.name
	return string.format("Mission %d: %s", num, name)
end

return StoryPlan
