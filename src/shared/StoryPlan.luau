--!strict
-- StoryPlan: Act 1 and side quest rules on the saved story table (spec: Act 1; Act 1 choices; Side quests;
-- Faction reputation; nate's lore, build plan step 5). Pure, so Lune checks the gates, the stages, the choices,
-- the flags, the Skill Point total and the step counts. MissionService, QuestService and StoryService do the
-- world side.
-- * Missions open in order (mission n needs mission n - 1 cleared) at their minimum level; cleared ones
--   can be replayed, and only the first clear pays.
-- * Every mission is co-op in stages: stage() is a side's step with its branch in place; shared() says the whole
--   party plays one step (a boss, a camera beat), else each side does its own job at the same time.
-- * A choice is picked once (later replays keep the first pick) and grants its Skill Points once; each side
--   has its own two options, and flags() reads the story flags the picks set.
-- * Objective progress: need() says how much each step takes; a run tracks { have } per side.

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

local function sideKey(side: string): string
	return if side == "villain" then "villain" else "hero"
end
StoryPlan.sideKey = sideKey

-- How many stages a mission has (both sides' lists are the same length)
function StoryPlan.stages(Config: any, num: number): number
	local m = Config.Story.missions[num]
	return if m and m.hero then #m.hero else 0
end

-- Is stage i one goal for the whole party (the same table in both lists: one boss, one camera beat)?
function StoryPlan.shared(Config: any, num: number, i: number): boolean
	local m = Config.Story.missions[num]
	return m ~= nil and m.hero ~= nil and m.hero[i] ~= nil and rawequal(m.hero[i], m.villain[i])
end

-- A side's step at stage i with its branch put in place: nil when the side has nothing to do there (a branch
-- whose pick is "none", or one still waiting on its choice). choices: the deciding player's story picks.
function StoryPlan.stage(Config: any, num: number, i: number, side: string, choices: { number }): any?
	local m = Config.Story.missions[num]
	local key = sideKey(side)
	local step = m and m[key] and m[key][i]
	if not step then
		return nil
	end
	if step.kind == "branch" then
		local pick = choices[step.choice]
		local list = m.branches and m.branches[key]
		local b = list and pick and pick > 0 and list[pick]
		if b and b.kind ~= "none" then
			return b
		end
		return nil
	end
	return step
end

-- What a party plays at stage i: { both = step } on a shared stage, else one entry per side present
-- ({ hero = step or false, villain = ... }: false when that side has nothing to do there). present maps each
-- side in the party to the picks of the member who decides for it.
function StoryPlan.tracks(
	Config: any,
	num: number,
	i: number,
	present: { [string]: { number } }
): { [string]: any }
	local out = {}
	if StoryPlan.shared(Config, num, i) then
		out.both = Config.Story.missions[num].hero[i]
		return out
	end
	for _, key in { "hero", "villain" } do
		local choices = present[key]
		if choices then
			out[key] = StoryPlan.stage(Config, num, i, key, choices) or false
		end
	end
	return out
end

-- A mission's steps for a side, stage by stage, with chosen branches in place (empty ones left out)
function StoryPlan.steps(Config: any, num: number, side: string, choices: { number }): { any }
	local out = {}
	for i = 1, StoryPlan.stages(Config, num) do
		local s = StoryPlan.stage(Config, num, i, side, choices)
		if s then
			table.insert(out, s)
		end
	end
	return out
end

-- Is stage idx a branch still waiting on its choice? (the branch is resolved once the choice is in)
function StoryPlan.pendingBranch(Config: any, num: number, side: string, idx: number): number?
	local m = Config.Story.missions[num]
	local list = m and m[sideKey(side)]
	local step = list and list[idx]
	return if step and step.kind == "branch" then step.choice else nil
end

-- The objective text a side reads for a step (a shared step can word it per side)
function StoryPlan.text(step: any, side: string): string
	if side == "villain" and step.villainText then
		return step.villainText
	end
	return step.text or ""
end

-- A camera beat's subtitled lines for a side, by time: { at, who, text }
function StoryPlan.sceneLines(step: any, side: string): { { at: number, who: string, text: string } }
	local out = {}
	local key = sideKey(side)
	for _, l in step.lines or {} do
		local text = l.text or l[key]
		if type(text) == "string" then
			table.insert(out, { at = l.at, who = l.who, text = text })
		end
	end
	table.sort(out, function(a, b)
		return a.at < b.at
	end)
	return out
end

-- The ending broadcast that plays after clearing mission num (nil for every mission but the act's last)
function StoryPlan.ending(Config: any, num: number): string?
	local m = Config.Story.missions[num]
	local id = m and m.ending
	return if id and Config.Story.ending[id] then id else nil
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
	elseif k == "beacon" or k == "scene" then
		return step.seconds
	end
	return 1 -- reach, choice, chase, boss, fake, twin (one per hero, set when they spawn), warframe, carry, deliver, find
end

-- A choice's option as a side sees it (its label, flag, reputation and cosmetic), or nil
function StoryPlan.option(Config: any, choiceNum: number, side: string, option: number): any?
	local c = Config.Story.choices[choiceNum]
	local list = c and c[sideKey(side)]
	return list and list[option]
end

-- A choice: returns ok and the effects to pay ({ skillPoints, rep = { track, amount }, flag, perk, arena })
-- the first time; a replay pick changes nothing. The pick is saved as 1 or 2 (the side's own options).
function StoryPlan.pick(
	Config: any,
	story: any,
	choiceNum: number,
	option: number,
	side: string
): (boolean, any?)
	local c = Config.Story.choices[choiceNum]
	local o = StoryPlan.option(Config, choiceNum, side, option)
	if not c or not o then
		return false, nil
	end
	if story.choices[choiceNum] ~= 0 then
		return false, nil -- already picked
	end
	story.choices[choiceNum] = option
	local fx: { [string]: any } = {
		skillPoints = c.skillPoints,
		flag = o.flag,
		perk = o.perk,
		arena = o.arena,
	}
	if o.rep then
		local track = o.rep[1]
		if track == "side" then
			track = if side == "villain" then "syndicate" else "vigil"
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
	for _, o in Config.Story.choices[choiceNum][sideKey(side)] do
		table.insert(out, o.label)
	end
	return out
end

-- The story flags a character's picks have set ({ [flag] = true }); the side reads the options
function StoryPlan.flags(Config: any, story: any, side: string): { [string]: boolean }
	local out = {}
	for n in Config.Story.choices do
		local o = StoryPlan.option(Config, n, side, story.choices[n] or 0)
		if o and o.flag then
			out[o.flag] = true
		end
	end
	return out
end

function StoryPlan.flag(Config: any, story: any, side: string, name: string): boolean
	return StoryPlan.flags(Config, story, side)[name] == true
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
function StoryPlan.pinnedText(Config: any, story: any, _side: string): string?
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
	return string.format("Mission %d: %s", num, Config.Story.missions[num].name)
end

return StoryPlan
