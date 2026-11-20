--!strict
-- StoryPlan: the story's rules on the saved story table (spec: Act 1; Act 1 choices; Faction reputation; nate's
-- lore, build plan step 5). Pure, so Lune checks the gates, the stages, the choices, the flags, the Skill
-- Point total and the step counts. MissionService and StoryService do the world side (side quests:
-- Shared.SideQuestPlan, lore step 10).
-- * Acts (WP11, gap G14; Config.Story.acts): every mission and choice names its act (Act 1 is everything
--   built). An act marked soon is a locked "Act N: coming soon" row: none of its missions can be entered,
--   pinned or counted, so a future act is data only (its missions, choices and ending, then drop soon).
-- * Missions open in play order (a mission needs the one before it cleared, across acts too) at their minimum
--   level; cleared ones can be replayed, and only the first clear pays.
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

---------------------------------------------------------------------------
-- Acts (WP11)
---------------------------------------------------------------------------

-- The act a mission belongs to (a mission without one is Act 1's)
function StoryPlan.actOf(Config: any, num: number): number
	local m = Config.Story.missions[num]
	return m and m.act or 1
end

-- Is the act a locked "coming soon" row (marked soon, or not in the list)?
function StoryPlan.soon(Config: any, act: number): boolean
	local a = Config.Story.acts[act]
	return a == nil or a.soon == true
end

-- The act's missions in play order (mission numbers)
function StoryPlan.actMissions(Config: any, act: number): { number }
	local out = {}
	for num, m in Config.Story.missions do
		if (m.act or 1) == act then
			table.insert(out, num)
		end
	end
	return out
end

-- The act's choices (save slots), in their missions' order
function StoryPlan.actChoices(Config: any, act: number): { number }
	local out = {}
	for n, c in Config.Story.choices do
		if (c.act or 1) == act then
			table.insert(out, n)
		end
	end
	table.sort(out, function(a, b)
		local ma, mb = Config.Story.choices[a].mission, Config.Story.choices[b].mission
		return if ma == mb then a < b else ma < mb
	end)
	return out
end

-- A mission's place in its own act (1 for its act's first): the number players read
function StoryPlan.missionIndex(Config: any, num: number): number
	return table.find(StoryPlan.actMissions(Config, StoryPlan.actOf(Config, num)), num) or num
end

-- The mission played just before this one (the last of the act before, for an act's first), or nil
function StoryPlan.prevMission(Config: any, num: number): number?
	local act = StoryPlan.actOf(Config, num)
	local list = StoryPlan.actMissions(Config, act)
	local i = table.find(list, num)
	if i and i > 1 then
		return list[i - 1]
	end
	for a = act - 1, 1, -1 do
		local before = StoryPlan.actMissions(Config, a)
		if #before > 0 then
			return before[#before]
		end
	end
	return nil
end

-- Has every mission of the act a first clear? (a coming-soon or empty act is never done)
function StoryPlan.actDone(Config: any, story: any, act: number): boolean
	if StoryPlan.soon(Config, act) then
		return false
	end
	local list = StoryPlan.actMissions(Config, act)
	for _, num in list do
		if not StoryPlan.cleared(story, num) then
			return false
		end
	end
	return #list > 0
end

-- Is this the last mission of its act (the one whose first clear finishes the act)?
function StoryPlan.actLast(Config: any, num: number): boolean
	local list = StoryPlan.actMissions(Config, StoryPlan.actOf(Config, num))
	return list[#list] == num
end

-- "soon" (a locked coming-soon row), "locked" (an act before it is not done), "open" or "done"
function StoryPlan.actState(Config: any, story: any, act: number): string
	if StoryPlan.soon(Config, act) or #StoryPlan.actMissions(Config, act) == 0 then
		return "soon"
	end
	if StoryPlan.actDone(Config, story, act) then
		return "done"
	end
	for a = 1, act - 1 do
		if not StoryPlan.actDone(Config, story, a) then
			return "locked"
		end
	end
	return "open"
end

-- The act the hero is on (saved as story.act): the first act not done yet, else the last one out. While
-- Act 2 is coming soon this is always 1.
function StoryPlan.currentAct(Config: any, story: any): number
	local cur = 1
	for a in Config.Story.acts do
		local st = StoryPlan.actState(Config, story, a)
		if st == "open" or st == "locked" then
			return a
		elseif st == "done" then
			cur = a
		else
			break -- a coming-soon act: nothing after it is out
		end
	end
	return cur
end

-- Problems with the act data (an empty list is good): every mission and choice in a listed act, missions
-- grouped in act order, nothing in a coming-soon act and no act out after one, a choice in its mission's
-- act, and the save's room
function StoryPlan.validate(Config: any): { string }
	local S = Config.Story
	local out = {}
	local function no(msg: string)
		table.insert(out, msg)
	end
	local soonSeen = false
	for a, def in S.acts do
		if def.num ~= a then
			no("act " .. a .. " has num " .. tostring(def.num))
		end
		if def.soon then
			soonSeen = true
		elseif soonSeen then
			no("act " .. a .. " is out after a coming-soon act")
		end
	end
	local last = 1
	for num, m in S.missions do
		local a = m.act
		if type(a) ~= "number" or not S.acts[a] then
			no("mission " .. num .. " names no listed act")
		else
			if a < last then
				no("mission " .. num .. " (act " .. a .. ") comes after act " .. last .. "'s missions")
			end
			last = math.max(last, a)
			if S.acts[a].soon then
				no("mission " .. num .. " is in coming-soon act " .. a)
			end
		end
		if m.num ~= num then
			no("mission " .. num .. " has num " .. tostring(m.num))
		end
	end
	for n, c in S.choices do
		if type(c.act) ~= "number" or not S.acts[c.act] then
			no("choice " .. n .. " names no listed act")
		elseif S.acts[c.act].soon then
			no("choice " .. n .. " is in coming-soon act " .. c.act)
		elseif StoryPlan.actOf(Config, c.mission) ~= c.act then
			no("choice " .. n .. " is in act " .. c.act .. " but its mission is not")
		end
	end
	-- act1-choices: an option's reward is a title (a Config.Story.unlocks title) or Credits only, its scene lines
	-- with `when` name a real choice and option on their own side
	for n, c in S.choices do
		for _, key in { "hero", "villain" } do
			for o, opt in c[key] or {} do
				for k, v in opt.reward or {} do
					if k == "title" then
						if not (S.unlocks.titles[v] and S.unlocks.titles[v] < 100) then
							no(
								string.format(
									"choice %d %s %d: title %s is not a story title",
									n,
									key,
									o,
									tostring(v)
								)
							)
						end
					elseif k ~= "credits" or type(v) ~= "number" or v <= 0 then
						no(
							string.format(
								"choice %d %s %d: reward %s (a title or Credits only)",
								n,
								key,
								o,
								k
							)
						)
					end
				end
			end
		end
	end
	for num, m in S.missions do
		for _, key in { "hero", "villain" } do
			for i, st in m[key] or {} do
				for j, l in st.lines or {} do
					local w = l.when
					if w ~= nil then
						local c = S.choices[w[1]]
						local side = l.side
						if
							not c
							or (side ~= "hero" and side ~= "villain")
							or not (c[side] and c[side][w[2]])
						then
							no(
								string.format(
									"mission %d %s[%d] line %d: `when` needs its side's real option",
									num,
									key,
									i,
									j
								)
							)
						end
					end
				end
			end
		end
	end
	for a in S.acts do
		if not StoryPlan.soon(Config, a) and #StoryPlan.actMissions(Config, a) == 0 then
			no("act " .. a .. " is out with no missions")
		end
	end
	if #S.missions > S.saveRoom.missions then
		no("more missions than the save's " .. S.saveRoom.missions .. " bits")
	end
	if #S.choices > S.saveRoom.choices then
		no("more choices than the save's " .. S.saveRoom.choices .. " slots")
	end
	return out
end

-- "done", "open", "level" (open but the hero is too low) or "locked" (the one before is not cleared)
function StoryPlan.state(Config: any, story: any, level: number, num: number): string
	local m = Config.Story.missions[num]
	if not m then
		return "locked"
	end
	if StoryPlan.soon(Config, m.act or 1) then
		return "locked" -- a coming-soon act's (WP11): never entered
	end
	if StoryPlan.cleared(story, num) then
		return "done"
	end
	local prev = StoryPlan.prevMission(Config, num)
	if prev and not StoryPlan.cleared(story, prev) then
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

-- The next mission to play (the pinned story step), or nil when every act that is out is done (a
-- coming-soon act's missions are never next)
function StoryPlan.nextMission(Config: any, story: any): number?
	for num, m in Config.Story.missions do
		if not StoryPlan.soon(Config, m.act or 1) and not StoryPlan.cleared(story, num) then
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

-- Does a scene line read for this side and these picks? (act1-choices) A line with `side` is that side's only;
-- one with `when = { choice, option }` only for a hero whose own pick in that slot is that option.
function StoryPlan.lineFor(line: any, side: string, choices: { number }?): boolean
	if line.side ~= nil and line.side ~= sideKey(side) then
		return false
	end
	local w = line.when
	if w ~= nil then
		return choices ~= nil and (choices[w[1]] or 0) == w[2]
	end
	return true
end

-- A camera beat's subtitled lines for a side (and the hero's picks, for the `when` lines), by time:
-- { at, who, text }
function StoryPlan.sceneLines(
	step: any,
	side: string,
	choices: { number }?
): { { at: number, who: string, text: string } }
	local out = {}
	local key = sideKey(side)
	for _, l in step.lines or {} do
		local text = l.text or l[key]
		if type(text) == "string" and StoryPlan.lineFor(l, side, choices) then
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
	elseif k == "find" or k == "carry" then
		return step.points or 1 -- missions lane: spots to search, people to carry
	elseif k == "beacon" or k == "scene" then
		return step.seconds
	end
	return 1 -- reach, choice, chase, boss, fake, twin (one per hero, set when they spawn), warframe, talk, deliver
end

-- A choice's option as a side sees it (its label, flag, reputation and cosmetic), or nil
function StoryPlan.option(Config: any, choiceNum: number, side: string, option: number): any?
	local c = Config.Story.choices[choiceNum]
	local list = c and c[sideKey(side)]
	return list and list[option]
end

-- A choice: returns ok and the effects to pay ({ skillPoints, rep = { track, amount }, flag, perk, arena, reward })
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
	if (story.choices[choiceNum] or 0) ~= 0 then
		return false, nil -- already picked (a slot a later act added reads as not yet)
	end
	if StoryPlan.soon(Config, c.act or 1) then
		return false, nil
	end
	story.choices[choiceNum] = option
	local fx: { [string]: any } = {
		skillPoints = c.skillPoints,
		flag = o.flag,
		perk = o.perk,
		arena = o.arena,
		reward = o.reward, -- act1-choices: a title or Credits (StoryService.pay), nothing that changes stats
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
-- Skill Points an act grants in all (Act 1 when act is left out): its choices plus its missions that give
-- one (spec: 8 for Act 1)
function StoryPlan.actSkillPoints(Config: any, act: number?): number
	local a = act or 1
	local n = 0
	for _, c in Config.Story.choices do
		if (c.act or 1) == a then
			n += c.skillPoints
		end
	end
	for _, m in Config.Story.missions do
		if (m.act or 1) == a then
			n += m.skillPoints or 0
		end
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

-- What the journal pins when no side quest chain is tracked: the next story mission (nil once every act that
-- is out is done: a coming-soon act is never pinned). Act 1 reads "Mission 3: Framed"; a later act names
-- itself and counts its missions from 1.
function StoryPlan.pinnedText(Config: any, story: any, _side: string): string?
	local next = StoryPlan.nextMission(Config, story)
	if not next then
		return nil
	end
	local num = next :: number
	local name = Config.Story.missions[num].name
	local act = StoryPlan.actOf(Config, num)
	if act == 1 then
		return string.format("Mission %d: %s", num, name)
	end
	return string.format("Act %d, Mission %d: %s", act, StoryPlan.missionIndex(Config, num), name)
end

return StoryPlan
