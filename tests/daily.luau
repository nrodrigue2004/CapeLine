-- WP1: the daily login streak and daily quests (gap check G1). The pure rules (Shared.DailyRules), the save
-- (ProfileSchema v13), the once-a-day payout, the seed picks, the analytics events and the wiring.
-- Called from tests/run.luau: require("./daily")({ test, check, Config })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local DailyRules = require("../src/shared/DailyRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local BadgeRules = require("../src/shared/BadgeRules")
	local D = Config.Daily
	local DAY = 20410 -- a UTC day (2025-11-18)

	local function fresh(): any
		return ProfileSchema.default().daily
	end

	-- a save round trip as the DataStore does it (JSON), then a load on "another server"
	local function hop(profile: any): any
		return ProfileSchema.load(serde.decode("json", serde.encode("json", profile)))
	end

	test(
		"WP1 Daily: the numbers: a 7-day track, day 7 an earnable title, the quest pool, no clashes",
		function()
			check(#D.track == 7, "a 7-day track")
			local titleOn7 = false
			for _, row in D.track[7] do
				titleOn7 = titleOn7 or row.kind == "title"
			end
			check(titleOn7, "day 7 gives a title (an earnable cosmetic)")
			for day, rows in D.track do
				for _, row in rows do
					check(
						row.kind == "credits"
							or row.kind == "dust"
							or row.kind == "renown"
							or row.kind == "title",
						"day " .. day .. ": a known kind (" .. tostring(row.kind) .. ")"
					)
					check(
						row.kind == "title" or (type(row.n) == "number" and row.n > 0),
						"day " .. day .. " pays"
					)
				end
			end
			check(#D.titles >= 1 and #D.titles <= 16, "1 to 16 daily titles (the save keeps 16 bits)")
			check(D.titleDust > 0, "Dust once every title is owned")
			-- the title ids sit in a range nobody else uses, and the names are new
			local bases = { Config.Badges.titleBase, Config.Badges.baneBase, Config.Pass.titleBase }
			table.insert(bases, Config.Remembers.titleBase)
			for _, b in bases do
				check(D.titleBase ~= b and math.abs(D.titleBase - b) >= 100, "title base apart from " .. b)
			end
			check(D.titleBase + #D.titles <= 65535, "fits the worn title (mmo.title)")
			local taken = {}
			for name in Config.Story.unlocks.titles do
				taken[name] = true
			end
			for _, name in Config.Pass.titles do
				taken[name] = true
			end
			for _, g in Config.Badges.groups do
				for _, b in g.badges do
					taken[b.name] = true
				end
			end
			local seen = {}
			for _, name in D.titles do
				check(not taken[name] and not seen[name], "a new title name: " .. name)
				seen[name] = true
			end
			local ids, keys = {}, {}
			for _, q in D.quests do
				check(not ids[q.id] and #q.id <= 24, "a unique short quest id: " .. q.id)
				ids[q.id] = true
				check(
					q.n >= 1 and q.pay > 0 and #q.text > 0 and #q.text <= 48,
					q.id .. ": a goal, pay and a line"
				)
				check(not q.pvp or q.alt ~= nil, q.id .. ": a PvP quest also counts a non-PvP way")
				keys[q.key] = true
				if q.alt then
					keys[q.alt] = true
				end
			end
			check(D.picks == 3, "3 quests a day")
			check(D.pvp == false, "PvP daily quests off at launch (nate's call)")
			-- every key a quest counts is counted by DailyService from an existing signal
			local svc = fs.readFile("src/server/Services/DailyService.luau")
			for key in keys do
				check(string.find(svc, '"' .. key .. '"', 1, true) ~= nil, "DailyService counts " .. key)
			end
		end
	)

	test(
		"WP1 Daily: the streak: next day, once a day, a clock behind, the weekly grace, a kind reset",
		function()
			local d = fresh()
			local v = DailyRules.visit(Config, d, DAY)
			check(v ~= nil and v.kind == "new" and v.streak == 1 and d.owed == 1, "the first login is day 1")
			check(DailyRules.visit(Config, d, DAY) == nil, "a second join the same day counts nothing")
			check(
				DailyRules.visit(Config, d, DAY - 1) == nil,
				"a server whose clock is behind counts nothing"
			)
			v = DailyRules.visit(Config, d, DAY + 1)
			check(v ~= nil and v.kind == "next" and d.streak == 2, "the next day goes on")
			check(v ~= nil and v.late == 1, "day 1 was never claimed: handed back to pay now")
			-- one missed day: forgiven by the grace
			v = DailyRules.visit(Config, d, DAY + 3)
			check(
				v ~= nil and v.kind == "grace" and d.streak == 3 and d.graceAt == DAY + 3,
				"one missed day: grace"
			)
			check(not DailyRules.graceReady(Config, d, DAY + 5), "the grace is used for the week")
			-- another missed day inside the week: the track starts over, the best is kept
			v = DailyRules.visit(Config, d, DAY + 5)
			check(
				v ~= nil and v.kind == "reset" and v.old == 3 and d.streak == 1,
				"a second miss that week: day 1"
			)
			check(d.best == 3, "the best streak is kept")
			-- a week after the grace, it is ready again
			for day = DAY + 6, DAY + 9 do
				DailyRules.visit(Config, d, day)
			end
			check(d.streak == 5, "five days running")
			check(
				DailyRules.graceReady(Config, d, DAY + 3 + D.grace.every),
				"the grace comes back a week later"
			)
			v = DailyRules.visit(Config, d, DAY + 11)
			check(v ~= nil and v.kind == "grace" and d.streak == 6, "a missed day forgiven again")
			-- two missed days in a row: never forgiven, but nothing earned is taken
			d.titles = 1
			v = DailyRules.visit(Config, d, DAY + 14)
			check(v ~= nil and v.kind == "reset" and d.streak == 1, "two missed days: day 1")
			check(d.titles == 1 and d.best == 6, "titles and the best streak are kept")
			check(DailyRules.trackDay(Config, 1) == 1 and DailyRules.trackDay(Config, 7) == 7, "track days")
			check(
				DailyRules.trackDay(Config, 8) == 1 and DailyRules.trackDay(Config, 15) == 1,
				"the track loops"
			)
			check(DailyRules.untilReset(Config, DAY * 86400 + 3600) == 82800, "23 h to 00:00 UTC")
			check(DailyRules.day(Config, DAY * 86400 + 86399) == DAY, "the UTC day")
		end
	)

	test("WP1 Daily: rewards: the contract scale, day 7 titles in order, then Dust", function()
		local d = fresh()
		local c1, r1 = DailyRules.contractPay(Config, 10, 1)
		local e, s = Config.Economy.earn.contract, Config.Economy.scale
		check(
			c1 == math.floor((e.credits[1] + e.credits[2] * 10) * s.credits + 0.5),
			"contract Credits at 10"
		)
		check(r1 == math.floor((e.renown[1] + e.renown[2] * 10) * s.renown + 0.5), "contract Renown at 10")
		local _, r30 = DailyRules.contractPay(Config, 30, 1)
		check(r30 > r1, "Renown grows with level")
		local day3 = DailyRules.reward(Config, d, 3, 10)
		check(
			day3.renown == r1 and day3.credits == 200 and day3.title == 0,
			"day 3: a contract's Renown and 200"
		)
		for i = 1, #D.titles do
			local r = DailyRules.settle(Config, d, 7 * i, 10)
			check(r ~= nil and r.title == i and r.titleName == D.titles[i], "week " .. i .. ": title " .. i)
			check(r ~= nil and r.day == 7, "on day 7")
		end
		local owned = DailyRules.titles(Config, d)
		check(#owned == #D.titles and owned[1].id == D.titleBase + 1, "every daily title owned")
		local last = DailyRules.reward(Config, d, 7 * (#D.titles + 1), 10)
		check(last.title == 0 and last.dust == D.titleDust + 60, "all owned: Dust instead of a title")
		-- the title list shows them (BadgeRules.titles)
		local p = ProfileSchema.default()
		p.daily.titles = 1
		local list = BadgeRules.titles(Config, p, p.characters[1])
		local found = false
		for _, t in list do
			found = found or (t.id == D.titleBase + 1 and t.name == D.titles[1])
		end
		check(found, "the title list has the daily title")
		check(BadgeRules.titleText(Config, p, p.characters[1], D.titleBase + 2) == nil, "not one you lack")
		-- nothing in the daily rewards is a stat or sold
		for _, rows in D.track do
			for _, row in rows do
				check(
					row.kind ~= "gear" and row.kind ~= "stat" and row.kind ~= "robux",
					"no stat or sold reward"
				)
			end
		end
	end)

	test("WP1 Daily: pays once a day per account, across a rejoin and a server hop", function()
		local p = ProfileSchema.default()
		local d = p.daily
		check(DailyRules.claim(Config, d, 5) == nil, "nothing to claim before the day is counted")
		DailyRules.visit(Config, d, DAY)
		local r = DailyRules.claim(Config, d, 5)
		check(r ~= nil and r.day == 1 and r.credits == 300, "day 1 pays 300 Credits")
		check(DailyRules.claim(Config, d, 5) == nil, "a second claim the same day pays nothing")
		-- rejoin the same server, or hop to another: the save says it is paid
		local q = hop(p)
		check(DailyRules.visit(Config, q.daily, DAY) == nil, "the other server does not count the day again")
		check(DailyRules.claim(Config, q.daily, 5) == nil, "and pays nothing")
		check(q.daily.streak == 1 and q.daily.last == DAY, "the streak travels with the save")
		-- the next day, on the other server: counted and paid once
		check(DailyRules.visit(Config, q.daily, DAY + 1) ~= nil, "the next day counts")
		local q2 = hop(q) -- a hop before claiming keeps the owed reward
		check(q2.daily.owed == 2, "the owed day travels too")
		check(DailyRules.claim(Config, q2.daily, 5) ~= nil, "claimed on the third server")
		check(DailyRules.claim(Config, hop(q2).daily, 5) == nil, "and never again")
		-- an unclaimed day is paid on the next login (never lost)
		local e = fresh()
		DailyRules.visit(Config, e, DAY)
		local v = DailyRules.visit(Config, e, DAY + 1)
		local late = v and DailyRules.settle(Config, e, v.late, 5)
		check(late ~= nil and late.day == 1, "yesterday's reward is paid late")
		local today = DailyRules.claim(Config, e, 5)
		check(today ~= nil and today.day == 2, "today's still waits for CLAIM")
		-- a day 7 title is granted once (the save holds the bit before anything is paid)
		local f = fresh()
		for day = DAY, DAY + 6 do
			DailyRules.visit(Config, f, day)
			DailyRules.claim(Config, f, 5)
		end
		check(f.titles == 1 and f.streak == 7 and f.owed == 0, "a week of claims: the first title")
		check(DailyRules.claim(Config, f, 5) == nil, "day 7 paid once")
	end)

	test("WP1 Daily: three quests a day from the day's seed", function()
		local a = DailyRules.order(Config, DAY)
		local b = DailyRules.order(Config, DAY)
		check(table.concat(a, ",") == table.concat(b, ","), "the same order on every server that day")
		local differ = 0
		for day = DAY + 1, DAY + 30 do
			if table.concat(DailyRules.order(Config, day), ",") ~= table.concat(a, ",") then
				differ += 1
			end
		end
		check(differ >= 29, "other days shuffle differently")
		local shown = {}
		for day = DAY, DAY + 120 do
			for _, level in { 1, 8, 20, 50 } do
				local picks = DailyRules.picks(Config, day, level)
				check(#picks == D.picks, string.format("3 picks on day %d at level %d", day, level))
				local keys = {}
				for _, id in picks do
					local q = DailyRules.quest(Config, id)
					check(q ~= nil, "a known quest " .. id)
					if q then
						check(level >= (q.minLevel or 1), id .. " is open at level " .. level)
						check(not q.pvp, "no PvP quest while it is off")
						check(not keys[q.key], "no two quests on one key")
						keys[q.key] = true
					end
					shown[id] = true
				end
			end
		end
		for _, q in D.quests do
			check(q.pvp == true or shown[q.id] == true, q.id .. " comes up within four months")
		end
		-- a level-1 hero gets nothing it cannot do yet
		for day = DAY, DAY + 60 do
			for _, id in DailyRules.picks(Config, day, 1) do
				local q = DailyRules.quest(Config, id)
				check(q ~= nil and (q.minLevel or 1) <= 1, "level 1: " .. id)
			end
		end
		-- PvP only when nate switches it on, and then never forced: the quest counts its non-PvP way too
		local was = D.pvp
		D.pvp = true
		local pvpSeen = false
		for day = DAY, DAY + 120 do
			for _, id in DailyRules.picks(Config, day, 20) do
				pvpSeen = pvpSeen or (DailyRules.quest(Config, id) :: any).pvp == true
			end
		end
		check(pvpSeen, "with the switch on, a PvP quest can come up")
		local d = fresh()
		d.quests, d.qday = { "pvp2", "", "" }, DAY
		local fin = DailyRules.bump(Config, d, "incident", 2)
		check(#fin == 1, "the PvP quest finishes without PvP (its non-PvP way)")
		D.pvp = was
	end)

	test("WP1 Daily: quests roll once a day, count, pay once, the bonus once", function()
		local d = fresh()
		check(DailyRules.roll(Config, d, DAY, 20), "a new day rolls")
		check(not DailyRules.roll(Config, d, DAY, 20), "once a day")
		check(not DailyRules.roll(Config, d, DAY - 1, 20), "never on a clock behind")
		check(#d.quests == 3 and d.quests[3] ~= "", "3 quests")
		local keys = {}
		for i, id in d.quests do
			keys[i] = (DailyRules.quest(Config, id) :: any).key
		end
		local q1 = DailyRules.quest(Config, d.quests[1]) :: any
		local fin, moved = DailyRules.bump(Config, d, keys[1], q1.n - 1)
		check(#fin == 0 and #moved == 1 and d.have[1] == q1.n - 1, "counting up")
		check(#(DailyRules.bump(Config, d, "nothingKey")) == 0, "an unknown key counts nothing")
		fin = DailyRules.bump(Config, d, keys[1], 99)
		check(#fin == 1 and fin[1] == 1 and d.have[1] == q1.n, "finished, capped at its goal")
		check(#(DailyRules.bump(Config, d, keys[1], 5)) == 0, "a finished quest pays once")
		local all
		fin, _, all = DailyRules.bump(Config, d, keys[2], 999)
		check(#fin == 1 and not all, "two done, no bonus yet")
		fin, _, all = DailyRules.bump(Config, d, keys[3], 999)
		check(#fin == 1 and all and d.bonus == 1, "all three: the bonus")
		local done, total = DailyRules.count(Config, d)
		check(done == 3 and total == 3, "3 of 3")
		check(not select(3, DailyRules.bump(Config, d, keys[3], 1)), "the bonus pays once")
		local c, r = DailyRules.questPay(Config, q1, 20)
		check(c > 0 and r > 0, "a quest pays Credits and Renown")
		local ac, ar, ad = DailyRules.allPay(Config, 20)
		check(ac > 0 and ar > 0 and ad == D.allDone.dust, "the bonus pays Credits, Renown and Dust")
		-- the next day: new quests, counts start over
		check(DailyRules.roll(Config, d, DAY + 1, 20), "the next day rolls")
		check(d.paid == 0 and d.bonus == 0 and d.have[1] == 0, "a fresh day")
		-- the device's view
		DailyRules.visit(Config, d, DAY + 1)
		local view = DailyRules.view(Config, d, DAY + 1, 20, (DAY + 1) * 86400 + 60)
		check(#view.days == 7 and view.days[1].state == "ready" and view.owed == true, "day 1 ready to claim")
		check(#view.quests == 3 and view.quests[1].n > 0, "the 3 quests with goals")
		check(view.resetIn == 86340, "the time to the reset")
		-- Studio: a day passes
		DailyRules.claim(Config, d, 20)
		DailyRules.shift(d, 1)
		check(DailyRules.visit(Config, d, DAY + 1) ~= nil and d.streak == 2, "the Dev panel's next day")
	end)

	test("WP1 Daily: save v13: a v12 save migrates, bad data is repaired", function()
		check(ProfileSchema.VERSION >= 13, "save version 13 or later")
		local fresh13 = ProfileSchema.default()
		local dl = fresh13.daily
		check(
			dl.streak == 0 and dl.owed == 0 and dl.titles == 0 and #dl.quests == 3,
			"a new save's daily block"
		)
		-- a v12 save: the daily block held only the contract count
		local old = ProfileSchema.default()
		old.version = 12
		old.daily = { day = DAY, contractsDone = 3 }
		local p = ProfileSchema.load(serde.decode("json", serde.encode("json", old)))
		check(p.version == ProfileSchema.VERSION, "loads at the current version")
		check(p.daily.day == DAY and p.daily.contractsDone == 3, "the day's contract count is kept")
		check(p.daily.streak == 0 and p.daily.last == 0 and p.daily.owed == 0, "the streak starts fresh")
		check(p.daily.quests[1] == "" and p.daily.have[3] == 0 and p.daily.bonus == 0, "no quests yet")
		check(DailyRules.visit(Config, p.daily, DAY) ~= nil and p.daily.streak == 1, "day 1 on this load")
		-- a v12 save with no daily block at all
		local bare = ProfileSchema.default()
		bare.version = 12
		bare.daily = nil
		local b = ProfileSchema.load(serde.decode("json", serde.encode("json", bare)))
		check(b.daily.streak == 0 and b.daily.contractsDone == 0, "a missing block is made")
		-- bad data
		local bad = ProfileSchema.default()
		bad.daily = {
			day = "x",
			contractsDone = -4,
			streak = 9,
			best = 2,
			last = -1,
			graceAt = 1e99,
			owed = 50,
			titles = 2 ^ 40,
			qday = DAY,
			quests = { "incident2", 7, "gone" },
			have = { 99, "x" },
			paid = 99,
			bonus = 4,
		}
		local r = ProfileSchema.load(serde.decode("json", serde.encode("json", bad)))
		local rd = r.daily
		check(rd.day == 0 and rd.contractsDone == 0, "bad contract counts")
		check(rd.streak == 9 and rd.best == 9 and rd.last == 0, "the best is never under the streak")
		check(rd.owed == 9, "owed is never past the streak")
		check(rd.titles == 2 ^ #D.titles - 1, "titles clamped to the list")
		check(
			rd.quests[1] == "incident2" and rd.quests[2] == "" and rd.quests[3] == "",
			"unknown quests dropped"
		)
		check(rd.qday == 0, "an unknown quest rolls the day again")
		check(rd.have[1] == 2 and rd.have[2] == 0, "counts clamped to the goal")
		check(rd.paid == 7 and rd.bonus == 1, "bits clamped")
		local again = ProfileSchema.load(serde.decode("json", serde.encode("json", r)))
		local same = true
		for k, v in rd do
			if type(v) == "table" then
				for i = 1, 3 do
					same = same and again.daily[k][i] == v[i]
				end
			else
				same = same and again.daily[k] == v
			end
		end
		check(same, "repair is stable")
		check(ProfileSchema.clientView(r).daily == nil, "the daily block stays on the server")
	end)

	test("WP1 Daily: analytics events: the schema's fields, logged by the server", function()
		local E = AnalyticsSchema.EVENTS
		local d = fresh()
		local v = DailyRules.visit(Config, d, DAY) :: any
		local value, fields = DailyRules.loginEvent(Config, v)
		local ok, clean = AnalyticsSchema.check("daily_login", fields)
		check(ok and #clean == #E.daily_login and value == 1, "daily_login: track day, kind")
		check(clean[1] == "1" and clean[2] == "new", "daily_login fields")
		local r = DailyRules.claim(Config, d, 5) :: any
		value, fields = DailyRules.claimEvent(r, false)
		ok, clean = AnalyticsSchema.check("daily_claim", fields)
		check(ok and #clean == #E.daily_claim and value == 1, "daily_claim: track day, reward, late")
		check(clean[2] == "credits" and clean[3] == "0", "daily_claim fields")
		DailyRules.roll(Config, d, DAY, 10)
		DailyRules.bump(Config, d, (DailyRules.quest(Config, d.quests[1]) :: any).key, 999)
		value, fields = DailyRules.questEvent(Config, d, 1)
		ok, clean = AnalyticsSchema.check("daily_quest", fields)
		check(ok and #clean == #E.daily_quest and value == 1 and clean[1] == d.quests[1], "daily_quest")
		value, fields = DailyRules.allEvent(Config, d)
		ok, clean = AnalyticsSchema.check("daily_all_done", fields)
		check(ok and #clean == #E.daily_all_done and value == 1, "daily_all_done")
		-- every kind cleans to a short code
		for _, kind in { "new", "next", "grace", "reset" } do
			local _, f = DailyRules.loginEvent(Config, { kind = kind, streak = 3, old = 0, late = 0 })
			check(AnalyticsSchema.check("daily_login", f), "daily_login " .. kind)
		end
		local svc = fs.readFile("src/server/Services/DailyService.luau")
		for _, name in { "daily_login", "daily_claim", "daily_quest", "daily_all_done" } do
			check(string.find(svc, '"' .. name .. '"', 1, true) ~= nil, "DailyService logs " .. name)
		end
	end)

	test("WP1 Daily: wiring: remotes, signals, juice, the card's states, phone fit, the Dev panel", function()
		local Remotes = require("../src/shared/Remotes")
		check(Remotes.DailyOpen.dir == "C2S" and #Remotes.DailyOpen.schema == 0, "DailyOpen")
		check(
			Remotes.DailyClaim.dir == "C2S" and (Remotes.DailyClaim.rate or 99) <= 1,
			"DailyClaim, rate-limited"
		)
		check(
			Remotes.DailyState.dir == "S2C" and Remotes.DailyProgress.dir == "S2C",
			"DailyState, DailyProgress"
		)
		local svc = fs.readFile("src/server/Services/DailyService.luau")
		for _, hook in
			{
				"IncidentService.Cleared",
				"EconomyService.Earned",
				"EnemyService.Killed",
				"BossService.Joined",
				"SideQuestService.StepPaid",
				"EventService.Paid",
				"ThrowService.Thrown",
				"DeathService.PvpWon", -- a paid win only (review 2026-11-18)
				"DataService.Loaded",
			}
		do
			check(string.find(svc, hook .. ":Connect", 1, true) ~= nil, "DailyService hooks " .. hook)
		end
		check(
			string.find(svc, "DataService.isSaving", 1, true) ~= nil,
			"never pays on a save that cannot save"
		)
		check(
			string.find(svc, "CombatService", 1, true) == nil
				and string.find(svc, "AbilityService", 1, true) == nil,
			"keeps away from combat and abilities"
		)
		local boot = fs.readFile("src/server/init.server.luau")
		local at = string.find(boot, 'boot("DailyService"', 1, true)
		local data = string.find(boot, 'boot("DataService"', 1, true)
		check(at ~= nil and data ~= nil and at < data, "DailyService starts before profiles load")
		local juice = {}
		for _, row in Config.Audio.juice do
			juice[row.id] = row.visual
		end
		check(juice.dailyClaim == "JuiceFx" and juice.dailyQuest == "JuiceFx", "juice rows drawn by JuiceFx")
		local hud = fs.readFile("src/client/Ui/DailyHud.luau")
		for _, s in
			{
				'Juice.fire("dailyClaim"',
				'Juice.fire("dailyQuest"',
				"Kit.fit(panel",
				"Kit.hudBoxes()",
				'"loading"',
				'"empty"',
				'"error"',
				"Kit.dock(",
				"pending = true",
			}
		do
			check(string.find(hud, s, 1, true) ~= nil, "DailyHud: " .. s)
		end
		local dev = fs.readFile("src/client/Ui/DevPanel.luau")
		check(string.find(dev, '"DevCommand", "daily", 1', 1, true) ~= nil, "the Dev panel's next-day button")
		local devSvc = fs.readFile("src/server/Services/DevService.luau")
		check(string.find(devSvc, "DailyService.dev", 1, true) ~= nil, "DevService runs it")
	end)
end
