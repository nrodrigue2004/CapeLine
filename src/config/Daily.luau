-- The daily login streak and daily quests (spec: Update 1 > "daily quests and login streak"; gap check G1,
-- work package WP1). Pure data; Shared.DailyRules has the rules, DailyService pays, DailyHud draws.
-- The spec gives no numbers, so every number here is a starting guess for nate to tune (Decisions.md,
-- 2026-11-18 "Daily"). The day is the UTC day (os.time // 86400), the same 00:00 UTC reset as the daily
-- contracts (Profile daily, spec "Resets at 00:00 UTC").
-- Rewards use the game's existing scales only: Credits and Lumen Dust at Hero Pass sizes, Renown and quest
-- Credits at the contract scale (Config.Economy.earn.contract x Config.Economy.scale, by hero level), and on
-- day 7 an earnable title. Nothing is sold here and nothing changes a stat.
return {
	on = true,
	dayLength = 86400, -- seconds in a UTC day

	-- The streak (CLAUDE.md rule 6, be kind): a day's login counts the moment you join, and its reward waits
	-- for CLAIM (a reward still unclaimed when the next day's login comes is paid then, never lost). One missed
	-- day is forgiven once every `grace.every` days; a longer gap starts the track over at day 1 (everything
	-- already earned is kept, and so is your best streak).
	grace = { missed = 1, every = 7 },

	-- The 7-day reward track (it loops: day 8 is day 1 again). Kinds: credits (n), dust (n), renown
	-- (n = contracts' worth of Renown at your level, the contract scale), title (day 7: the next daily title
	-- you do not own; once you own them all, `titleDust` Dust instead).
	track = {
		{ { kind = "credits", n = 300 } },
		{ { kind = "dust", n = 20 } },
		{ { kind = "renown", n = 1 }, { kind = "credits", n = 200 } },
		{ { kind = "credits", n = 500 } },
		{ { kind = "dust", n = 40 } },
		{ { kind = "renown", n = 2 }, { kind = "credits", n = 300 } },
		{ { kind = "title" }, { kind = "credits", n = 800 }, { kind = "dust", n = 60 } },
	},
	titleDust = 80, -- day 7 when every daily title is already yours

	-- Day 7 titles, in the order they are earned (one per finished week of the streak). Shown in the title
	-- list as titleBase + n (Shared.BadgeRules.titles). Only ever add at the end; never reorder or remove.
	-- Side-neutral words (heroes and villains both wear them). Draft names for nate.
	titleBase = 5000,
	titles = { "Seven Days Strong", "Two Weeks Strong", "Round the Clock", "Never Off Duty" },

	-- Daily quests: 3 picks a UTC day from the pool below, the same order for every player that day (a seed
	-- from the day), each player taking the first ones open at their level with no two on the same key. Each
	-- counts a thing players already do; PvP ones are only in the pool while `pvp` is on, and even then the
	-- quest also counts its `alt` (a non-PvP way), so nobody is pushed into PvP.
	picks = 3,
	seedSalt = 7151, -- mixed with the day into the seed (change it to reshuffle every future day)
	pvp = false, -- nate's call: PvP daily quests off at launch
	-- pay = how many contracts' worth of Credits and Renown at your level (the contract scale)
	quests = {
		{ id = "incident2", key = "incident", n = 2, pay = 1, text = "Clear 2 incidents" },
		{ id = "incident4", key = "incident", n = 4, pay = 1.6, minLevel = 12, text = "Clear 4 incidents" },
		{ id = "rescue5", key = "rescue", n = 5, pay = 1, text = "Bring 5 citizens to safety" },
		{
			id = "rescue10",
			key = "rescue",
			n = 10,
			pay = 1.5,
			minLevel = 15,
			text = "Bring 10 citizens to safety",
		},
		{ id = "robots20", key = "kill", n = 20, pay = 0.8, text = "Defeat 20 robots" },
		{ id = "robots50", key = "kill", n = 50, pay = 1.4, minLevel = 15, text = "Defeat 50 robots" },
		{ id = "contract1", key = "contract", n = 1, pay = 0.8, minLevel = 4, text = "Finish a contract" },
		{ id = "contract3", key = "contract", n = 3, pay = 1.5, minLevel = 12, text = "Finish 3 contracts" },
		{ id = "boss1", key = "boss", n = 1, pay = 1.2, minLevel = 3, text = "Hit a world boss" },
		{ id = "side1", key = "sideQuest", n = 1, pay = 1, minLevel = 6, text = "Finish a side quest step" },
		{ id = "event1", key = "event", n = 1, pay = 1, text = "Help out at a city event" },
		{ id = "throw3", key = "throw", n = 3, pay = 0.6, minLevel = 2, text = "Pick up and throw 3 things" },
		{
			id = "pvp2",
			key = "pvpWin",
			alt = "incident",
			n = 2,
			pay = 1.2,
			minLevel = 10,
			pvp = true,
			text = "Win 2 PvP fights (or clear 2 incidents)",
		},
	},
	-- all 3 done: a bonus on top (Credits at the contract scale, plus Dust)
	allDone = { pay = 1, dust = 30 },

	-- the screens
	ui = {
		showAfter = 4, -- seconds after the hero is free (made, the prologue done, no scene) to show the card
		freeWait = 600, -- how long the server waits for a busy hero to be free before giving up for this join
		trackerShow = 6, -- seconds the small tracker opens after a quest moves on
		answerWait = 6, -- seconds the panel waits for the server before showing the error state
	},
}
