--!strict
-- ReturnPlan: the WELCOME BACK card a returning hero gets on joining (retention pass, alive-world 2026-11-20, nate:
-- "keeping a recurring player base"): what changed since you left and what to do now, each line with a GO that opens
-- the screen it is about. Pure, so Lune checks it; DailyService gathers the facts from the save and the services
-- (ReturnPlan.facts), Ui.ReturnHud draws the card, and the MENU drawer's TO DO opens it again any time.
-- * facts(Config, profile, ctx): the save and the live world (ctx: now, level, week seed, the boss, friends here,
--   the nemesis, the last login day before today) -> plain facts, no Instances.
-- * card(Config, facts): { title, away, news = { Row }, todo = { Row } }. Rows are fixed templates filled with
--   numbers and names from config and the safe name systems: no free text. A to-do list is never empty: when the
--   day's chores are done it points at the story, the side quests and the long goals (no dead end at 10 to 20).
-- Nothing here pays or changes a stat; it only says where the rewards that exist already are.

local DailyRules = if script then require(script.Parent.DailyRules) else (require :: any)("./DailyRules")
local PassRules = if script then require(script.Parent.PassRules) else (require :: any)("./PassRules")
local NemesisMath = if script then require(script.Parent.NemesisMath) else (require :: any)("./NemesisMath")
local StoryPlan = if script then require(script.Parent.StoryPlan) else (require :: any)("./StoryPlan")
local SideQuestPlan = if script
	then require(script.Parent.SideQuestPlan)
	else (require :: any)("./SideQuestPlan")
local BossMath = if script then require(script.Parent.BossMath) else (require :: any)("./BossMath")
local LongGoals = if script then require(script.Parent.LongGoals) else (require :: any)("./LongGoals")
local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")

local ReturnPlan = {}

-- go: what the row's GO button opens on the device (Ui.ReturnHud): daily, pass, episode, map, wanted, story,
-- quests, goals, contracts (the map with the safehouses: a board is at each)
export type Row = { id: string, text: string, note: string, go: string? }

export type Ctx = {
	now: number, -- os.time()
	level: number,
	week: number, -- the weekly seed (CityBuilder.seed)
	lastDay: number?, -- the last UTC day counted before this join (nil: unknown)
	visit: string?, -- this join's streak visit: "new", "next", "grace", "reset" (nil: counted earlier today)
	newWeek: boolean?, -- the first visit of a new week on a returning account
	boss: { phase: string, left: number?, id: string? }?, -- BossService: waiting (left = seconds), fight, result
	friends: number?, -- Roblox friends on this server (the friend boost)
	nemesis: any?, -- NemesisMath.Saved or nil
	userId: number?,
	devOn: boolean?,
}

local function bossName(Config: any, id: string?): string
	local b = id and Config.Boss.bosses[id]
	return if b then b.name else "A world boss"
end

-- The facts the card is drawn from (the server's side: the save and the live world)
function ReturnPlan.facts(Config: any, profile: any, ctx: Ctx): { [string]: any }
	local c = ProfileSchema.active(profile)
	local d = profile.daily
	local today = DailyRules.day(Config, ctx.now)
	local f: { [string]: any } = { level = ctx.level, side = c.side or "hero" }
	-- away: whole days missed before today (0: you were here yesterday)
	if ctx.lastDay and ctx.lastDay > 0 and ctx.lastDay < today then
		f.away = today - ctx.lastDay - 1
	end
	f.visit = ctx.visit
	f.streak = d.streak
	f.owed = d.owed > 0
	f.trackDay = DailyRules.trackDay(Config, math.max(1, d.owed > 0 and d.owed or d.streak))
	local done, total = DailyRules.count(Config, d)
	f.dailyDone, f.dailyTotal = done, total
	-- contracts: the first `firstContracts` each UTC day pay double
	local firsts = Config.Economy.bonus.firstContracts
	local doneToday = if d.day == ctx.now // 86400 then d.contractsDone else 0 -- (ProfileSchema.rollDay's day)
	f.doubleLeft = math.max(0, firsts - doneToday)
	f.firsts = firsts
	-- the week: the bounty boss and whether it is paid this week
	f.newWeek = ctx.newWeek == true
	local bounty = BossMath.bounty(Config, ctx.week)
	f.bounty = bossName(Config, bounty)
	f.bountyPaid = profile.stats.bountyWeek == ctx.week
	-- the world boss now
	local b = ctx.boss
	if b then
		f.bossPhase = b.phase
		f.bossName = bossName(Config, b.id)
		f.bossMinutes = if b.left then math.max(1, math.ceil(b.left / 60)) else nil
		f.bossIsBounty = b.id == bounty and not f.bountyPaid
	end
	-- the nemesis
	local st = ctx.nemesis
	-- (only once you have met it: an unmet nemesis stays the surprise its first ambush is)
	if type(st) == "table" and (st.seed or 0) ~= 0 and (st.met or 0) > 0 then
		local N = Config.Nemesis
		f.nemesis = NemesisMath.name(N, st.seed, f.side)
		f.nemesisRank = st.rank
		f.intel, f.intelNeed = math.min(st.intel or 0, N.intelForShowdown), N.intelForShowdown
		f.showdown = NemesisMath.showdownOpen(N, st)
	end
	-- the Hero Pass (this season's) and this week's episode
	local P = Config.Pass
	local season = PassRules.season(P, ctx.now)
	local pass = profile.pass
	local xp = if pass.season == season then pass.xp else 0
	f.passTier = PassRules.tier(P, xp)
	f.passMax = P.tiers
	f.passToNext = if f.passTier < P.tiers then (f.passTier + 1) * P.xpPerTier - xp else 0
	local claim = 0
	if pass.season == season then
		for t = 1, f.passTier do
			if PassRules.canClaim(P, pass, t, false) then
				claim += 1
			end
			if pass.paid and PassRules.canClaim(P, pass, t, true) then
				claim += 1
			end
		end
	end
	f.passClaim = claim
	local ep, _, week = PassRules.episode(Config, ctx.now)
	if ep then
		local pe = profile.episode
		local steps = 0
		if pe.week == week then
			for i in ep.steps do
				if PassRules.stepDone(pe, i) then
					steps += 1
				end
			end
		end
		f.episode, f.episodeSteps, f.episodeTotal =
			ep.name or ep.theme or "This week's episode", steps, #ep.steps
	end
	-- the story: the next mission and whether it is open at this level
	local nextNum = StoryPlan.nextMission(Config, c.story)
	if nextNum then
		local m = Config.Story.missions[nextNum]
		local st2 = StoryPlan.state(Config, c.story, ctx.level, nextNum)
		f.story = m and m.name or ("Mission " .. nextNum)
		f.storyOpen = st2 == "open"
		f.storyLevel = m and m.minLevel or nil
	end
	-- side quests: chains in progress and chains open to start now (the first of each, and its giver)
	local active, open = 0, 0
	for _, row in SideQuestPlan.journal(Config, c, ctx.level, f.side, ctx.devOn == true) do
		local chain = SideQuestPlan.byBit(Config, row.bit)
		if chain and not chain.dev then
			if row.state == "active" then
				active += 1
				f.sideActive = f.sideActive or chain.name
			elseif row.state == "open" then
				open += 1
				if not f.sideOpen then
					f.sideOpen = chain.name
					local g = Config.SideQuests.givers[chain.giver]
					f.sideGiver = g and g.name or nil
				end
			end
		end
	end
	f.sideActiveN, f.sideOpenN = active, open
	-- friends: the friend boost on this server
	local fr = ctx.friends or 0
	if fr > 0 then
		local B = Config.Economy.bonus
		f.friends = fr
		f.friendPct = math.floor(math.min(B.friendMax, B.friendEach * fr) * 100 + 0.5)
	end
	-- the long goal nearest done (the Journal's GOALS)
	local best, bestShare = nil, -1
	for _, r in LongGoals.rows(Config, ProfileSchema.clientView(profile)) do
		local share = r.have / math.max(1, r.need)
		if share < 1 and share > bestShare then
			best, bestShare = r, share
		end
	end
	if best then
		f.goal, f.goalHave, f.goalNeed = best.name, best.have, best.need
	end
	return f
end

-- The card: news since you left, then the to-do list by priority (at most W.rows rows)
function ReturnPlan.card(Config: any, f: { [string]: any }): { [string]: any }
	local W = Config.Daily.welcome
	local news: { Row } = {}
	local todo: { Row } = {}
	local function n(id: string, text: string, note: string)
		table.insert(news, { id = id, text = text, note = note })
	end
	local function t(id: string, text: string, note: string, go: string?)
		table.insert(todo, { id = id, text = text, note = note, go = go })
	end
	-- news: the streak, the new week, the nemesis waiting
	if f.visit == "next" or f.visit == "grace" then
		n(
			"streak",
			string.format("DAY %d STREAK!", f.streak),
			if f.visit == "grace"
				then "You missed a day: your weekly grace kept the streak"
				else "Keep it going tomorrow"
		)
	elseif f.visit == "reset" then
		n("streak", "A NEW STREAK STARTS TODAY", "Everything you earned is still yours. Day 7 gives a title")
	end
	if f.newWeek then
		n(
			"week",
			"NEW WEEK IN BRIGHTHARBOR!",
			string.format("New outskirts to explore. This week's BOUNTY boss: %s", f.bounty)
		)
	end
	if f.showdown and f.nemesis then
		n(
			"nemesis",
			string.format("%s IS WAITING", string.upper(f.nemesis)),
			"Your Intel is complete: the Showdown is open"
		)
	end
	-- to do, most rewarding and most urgent first
	if f.owed then
		t(
			"claim",
			string.format("Claim your DAY %d reward", f.trackDay),
			"Your login streak's reward is waiting",
			"daily"
		)
	end
	if f.bossPhase == "fight" then
		t(
			"boss",
			string.format("%s is fighting now!", f.bossName),
			if f.bossIsBounty
				then "BOUNTY boss: double reward and Dust once this week"
				else "Join in: every hit counts",
			"map"
		)
	end
	if f.passClaim and f.passClaim > 0 then
		t(
			"passClaim",
			string.format(
				"Hero Pass: %d reward%s to claim",
				f.passClaim,
				if f.passClaim == 1 then "" else "s"
			),
			string.format("Tier %d of %d", f.passTier, f.passMax),
			"pass"
		)
	end
	if f.showdown then
		t(
			"showdown",
			string.format("Face %s in a Showdown", f.nemesis),
			"Beat it for its Core and a trophy head",
			"wanted"
		)
	end
	if f.dailyTotal and f.dailyTotal > 0 and f.dailyDone < f.dailyTotal then
		t(
			"daily",
			string.format("Daily quests: %d of %d done", f.dailyDone, f.dailyTotal),
			"Each pays Credits and Renown; all 3 add a bonus with Dust",
			"daily"
		)
	end
	if f.storyOpen then
		t(
			"story",
			string.format("Next story mission: %s", f.story),
			"Story missions pay the most and move the city on",
			"story"
		)
	end
	if f.doubleLeft and f.doubleLeft > 0 then
		t(
			"contracts",
			string.format("Contracts pay DOUBLE: %d left today", f.doubleLeft),
			string.format("The first %d each day; take them at any safehouse board", f.firsts),
			"contracts"
		)
	end
	if f.sideActive then
		t(
			"sideActive",
			string.format("Carry on: %s", f.sideActive),
			"Your side quest is where you left it",
			"quests"
		)
	elseif f.sideOpenN and f.sideOpenN > 0 then
		t(
			"sideOpen",
			string.format(
				"%d side quest%s to start: %s",
				f.sideOpenN,
				if f.sideOpenN == 1 then "" else "s",
				f.sideOpen
			),
			if f.sideGiver then string.format("Talk to %s", f.sideGiver) else "Start it from the Journal",
			"quests"
		)
	end
	if f.bossPhase == "waiting" and f.bossMinutes then
		t(
			"bossSoon",
			string.format("%s rises in %d min", f.bossName, f.bossMinutes),
			if f.bossIsBounty
				then "This week's BOUNTY boss: double reward once"
				else "Be there for a share of the reward",
			"map"
		)
	elseif not f.bountyPaid and f.bossPhase ~= "fight" then
		t(
			"bounty",
			string.format("Bounty: beat %s this week", f.bounty),
			"Double reward and Dust, once a week",
			"map"
		)
	end
	if f.episode and f.episodeSteps < f.episodeTotal then
		t(
			"episode",
			string.format("This week's episode: %d of %d steps", f.episodeSteps, f.episodeTotal),
			"Hero Pass XP and the week's comic",
			"episode"
		)
	end
	if not f.storyOpen and f.story and f.storyLevel and f.level < f.storyLevel then
		t(
			"storyLevel",
			string.format("%s opens at level %d", f.story, f.storyLevel),
			"Incidents, contracts and side quests all give Renown",
			"story"
		)
	end
	if f.nemesis and not f.showdown then
		t(
			"intel",
			string.format("Intel on %s: %d of %d", f.nemesis, f.intel, f.intelNeed),
			"It drops Intel each time it escapes you",
			"wanted"
		)
	end
	if f.goal then
		t(
			"goal",
			string.format("Closest goal: %s (%d of %d)", f.goal, f.goalHave, f.goalNeed),
			"Your long goals",
			"goals"
		)
	end
	if f.passTier and f.passTier < f.passMax and (f.passClaim or 0) == 0 then
		t(
			"pass",
			string.format("Hero Pass tier %d: %d XP to the next", f.passTier, f.passToNext),
			"Everything you do gives Pass XP",
			"pass"
		)
	end
	while #todo > W.rows do
		table.remove(todo)
	end
	local title = "WELCOME BACK!"
	if f.away and f.away >= W.longAway then
		title = "WELCOME BACK, HERO! THE CITY MISSED YOU"
	end
	local friendLine = if f.friends
		then string.format(
			"FRIEND BOOST +%d%% Renown: %d friend%s here",
			f.friendPct,
			f.friends,
			if f.friends == 1 then "" else "s"
		)
		else nil
	return { title = title, away = f.away, news = news, todo = todo, friends = friendLine }
end

return ReturnPlan
