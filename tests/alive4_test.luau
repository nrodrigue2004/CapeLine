-- The retention pass (alive-world round 4, 2026-11-20): the WELCOME BACK card (Shared.ReturnPlan, drawn by
-- Ui.ReturnHud, sent by DailyService after the daily claim card) on a returning hero's day 2 and day 7, and the
-- level 10 to 20 hero whose Act 1 is done (never an empty TO DO list). Called from tests/run.luau:
--   require("./alive4_test")({ test = test, check = check, Config = Config })
-- ONLY="Alive" runs these with the other alive tests.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local RP = require("../src/shared/ReturnPlan")
	local PS = require("../src/shared/ProfileSchema")
	local DR = require("../src/shared/DailyRules")
	local SP = require("../src/shared/StoryPlan")
	local NM = require("../src/shared/NemesisMath")

	local GO = {
		daily = true,
		pass = true,
		episode = true,
		map = true,
		contracts = true,
		wanted = true,
		story = true,
		quests = true,
		goals = true,
	}
	local NOW = 1_800_000_000 -- a fixed time (a Thursday in 2027), so the season and the episode are stable
	local TODAY = DR.day(Config, NOW)

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- A made hero past its prologue, its Act 1 cleared up to (and including) the missions open at `level`
	local function hero(level: number): any
		local p = PS.default()
		local c = PS.active(p)
		c.created = 1
		c.story.opening = 1
		for num, m in Config.Story.missions do
			if (m.minLevel or 1) <= level then -- every open act's missions (Act 2 since 2026-11-20)
				c.story.missions = SP.setBit(c.story.missions, num)
			end
		end
		p.daily.last = TODAY - 1
		return p
	end

	local function card(p: any, ctx: { [string]: any }): ({ [string]: any }, { [string]: any })
		local c: { [string]: any } = {
			now = NOW,
			level = 15,
			week = 4242,
			lastDay = TODAY - 1,
			visit = "next",
			boss = { phase = "waiting", left = 600, id = nil },
		}
		for k, v in ctx do
			c[k] = v
		end
		local f = RP.facts(Config, p, c :: any)
		return RP.card(Config, f), f
	end

	local function ids(cd: { [string]: any }): { [string]: number }
		local out = {}
		for i, r in cd.todo do
			out[r.id] = i
		end
		return out
	end

	local function wellFormed(cd: { [string]: any }, label: string)
		check(type(cd.title) == "string" and #cd.title > 0, label .. ": a title")
		check(#cd.todo >= 1, label .. ": never an empty TO DO list")
		check(
			#cd.todo <= Config.Daily.welcome.rows,
			label .. ": at most " .. Config.Daily.welcome.rows .. " rows"
		)
		for _, r in cd.todo do
			check(
				type(r.text) == "string" and #r.text > 0 and #r.text <= 60,
				label .. ": a short line: " .. r.text
			)
			check(type(r.note) == "string" and #r.note <= 70, label .. ": a short note: " .. tostring(r.note))
			check(r.go == nil or GO[r.go] == true, label .. ": " .. r.id .. " goes somewhere real")
			check(not string.find(r.text, "nil", 1, true), label .. ": no missing value in " .. r.text)
		end
		for _, n in cd.news do
			check(
				not string.find(n.text .. n.note, "nil", 1, true),
				label .. ": no missing value in " .. n.text
			)
		end
	end

	test(
		"Alive4: day 2: the streak, the reward to claim first, the daily quests and DOUBLE contracts",
		function()
			local p = hero(5)
			local d = p.daily
			DR.visit(Config, d, TODAY) -- day 2 of the streak: a reward owed
			DR.roll(Config, d, TODAY, 5)
			check(d.owed > 0, "the day's reward is owed")
			local cd, f = card(p, { level = 5, visit = "next" })
			wellFormed(cd, "day 2")
			check(cd.title == "WELCOME BACK!", "a short title after one night away")
			check(f.away == 0, "here yesterday: away 0 days")
			check(cd.news[1] and cd.news[1].id == "streak", "the streak is the first news")
			check(
				string.find(cd.news[1].text, "DAY " .. f.streak, 1, true) ~= nil,
				"it says the streak's day"
			)
			local at = ids(cd)
			check(at.claim == 1, "claiming the owed reward is the first thing to do")
			check(cd.todo[1].go == "daily", "and its GO opens DAILY")
			check(at.daily ~= nil, "the daily quests are on the list")
			check(at.contracts ~= nil, "DOUBLE contracts are on the list")
			check(
				string.find(
					cd.todo[at.contracts].text,
					tostring(Config.Economy.bonus.firstContracts),
					1,
					true
				) ~= nil,
				"with today's count (Config.Economy.bonus.firstContracts)"
			)
		end
	)

	test(
		"Alive4: day 7 after days away: the long title, the new week and its BOUNTY boss, a nemesis to face",
		function()
			local p = hero(15)
			p.daily.last = TODAY - 4
			local nem = NM.fresh(Config.Nemesis, 1, "hero")
			nem.met, nem.intel = 3, Config.Nemesis.intelForShowdown
			local cd, f = card(p, {
				level = 15,
				lastDay = TODAY - 4,
				visit = "grace",
				newWeek = true,
				nemesis = nem,
				friends = 2,
			})
			wellFormed(cd, "day 7")
			check(f.away == 3, "three days away")
			check(
				cd.title ~= "WELCOME BACK!",
				"the long title after " .. Config.Daily.welcome.longAway .. " days away"
			)
			local news = {}
			for _, n in cd.news do
				news[n.id] = n
			end
			check(
				news.streak ~= nil and string.find(news.streak.note, "grace", 1, true) ~= nil,
				"the grace kept it"
			)
			check(
				news.week ~= nil and string.find(news.week.note, f.bounty, 1, true) ~= nil,
				"the week's bounty boss"
			)
			check(f.showdown == true, "its Intel is full")
			check(news.nemesis ~= nil, "the nemesis waiting is news")
			check(ids(cd).showdown ~= nil, "and a Showdown row (GO: WANTED)")
			local unmet = NM.fresh(Config.Nemesis, 1, "hero")
			local _, f2 = card(p, { nemesis = unmet })
			check(f2.nemesis == nil, "a nemesis not met yet stays a surprise")
			check(
				cd.friends ~= nil and string.find(cd.friends, "20%", 1, true) ~= nil,
				"two friends: +20% Renown"
			)
		end
	)

	test("Alive4: level 10 to 20 with Act 1 done: never a dead end", function()
		for _, lvl in { 10, 14, 20 } do
			local p = hero(lvl)
			local cd, f = card(p, { level = lvl, visit = nil, boss = { phase = "result" } })
			wellFormed(cd, "level " .. lvl)
			check(not f.storyOpen, "level " .. lvl .. ": Act 1 is done")
			check(#cd.todo >= 3, "level " .. lvl .. ": at least 3 things to do (" .. #cd.todo .. ")")
			local at = ids(cd)
			check(at.contracts ~= nil or at.sideOpen ~= nil, "level " .. lvl .. ": contracts or side quests")
			check(at.bounty ~= nil, "level " .. lvl .. ": the week's bounty boss")
		end
		-- and when today's double contracts are used up, the goals and the pass still point somewhere
		local p = hero(15)
		p.daily.day = NOW // 86400
		p.daily.contractsDone = Config.Economy.bonus.firstContracts
		p.stats.bountyWeek = 4242
		local cd = card(p, { level = 15, visit = nil, boss = { phase = "result" } })
		wellFormed(cd, "all chores done")
		check(ids(cd).contracts == nil, "no DOUBLE row once the first 5 are done")
	end)

	test("Alive4: the boss row: a fight now comes before the daily chores; a bounty says so", function()
		local p = hero(15)
		local bounty = require("../src/shared/BossMath").bounty(Config, 4242)
		local cd = card(p, { boss = { phase = "fight", id = bounty } })
		local at = ids(cd)
		check(at.boss ~= nil and at.boss <= 2, "the live fight is near the top")
		check(string.find(cd.todo[at.boss].note, "BOUNTY", 1, true) ~= nil, "it is this week's bounty")
		check(cd.todo[at.boss].go == "map", "GO opens the MAP")
		local soon = card(p, { boss = { phase = "waiting", left = 130, id = bounty } })
		local s = ids(soon).bossSoon
		check(
			s ~= nil and string.find(soon.todo[s].text, "3 min", 1, true) ~= nil,
			"130 s rounds up to 3 min"
		)
	end)

	test(
		"Alive4: wiring: DailyService sends it, ReturnHud draws it with GO buttons and the TO DO dock",
		function()
			local svc = "src/server/Services/DailyService.luau"
			check(has(svc, 'Net.fire("ReturnCard", player, card)'), "the server sends the card")
			check(has(svc, 'Net.on("ReturnOpen"'), "and answers TO DO")
			check(has(svc, "returning[player] == true"), "it pops only for a returning hero")
			check(has(svc, "welcomed[player] = true"), "once a session")
			local hud = "src/client/Ui/ReturnHud.luau"
			check(has(hud, 'PopupGate.later("welcome"'), "it waits its turn behind the daily card")
			check(has(hud, 'Kit.dock(openButton, "ToDo"'), "TO DO in the MENU drawer")
			check(has(hud, 'if urgent(d) then " !"'), "TO DO ! while a reward waits")
			check(has(hud, 'Juice.fire("welcomeBack"'), "juice on open")
			check(has(hud, "PLACEHOLDER ART"), "labelled placeholder art")
			for key in GO do
				check(has(hud, '"' .. key .. '"'), "ReturnHud handles GO " .. key)
			end
			check(Config.Ui.popups.cards.welcome ~= nil, "the card is in the popup line")
			check(has("src/client/init.client.luau", "ReturnHud.init()"), "the client starts it")
			local R = require("../src/shared/Remotes")
			check(
				R.ReturnOpen and R.ReturnOpen.dir == "C2S" and R.ReturnCard and R.ReturnCard.dir == "S2C",
				"remotes"
			)
		end
	)
end
