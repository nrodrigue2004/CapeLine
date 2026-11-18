-- The Rogues File (WP3, spec: Collections and records > Rogues File) and the Journal's tabs (WP7: Badge Book,
-- Mentor, Showdown). Called from tests/run.luau:
--   require("./rogues_test")({ test = test, check = check, Config = Config, placePath = process.args[1] })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local RoguesFile = require("../src/shared/RoguesFile")
	local CreatorRules = require("../src/shared/CreatorRules")
	local Bits = ProfileSchema.Bits
	local R = Config.Rogues

	test(
		"Rogues File: the kind-to-bit map: unique bits, every kind covered, inside the save's words",
		function()
			local errs = RoguesFile.validate(Config)
			for _, e in errs do
				check(false, e)
			end
			check(#errs == 0, "the book validates")
			check(RoguesFile.WORDS == ProfileSchema.SMALL_WORDS, "the pages live in profile.rogues' words")
			check(#ProfileSchema.default().rogues == RoguesFile.WORDS, "the default save has them")
			local seen = {}
			local all = {}
			for _, e in RoguesFile.list(Config) do
				table.insert(all, e.bit)
				if e.gold then
					table.insert(all, e.gold)
				end
			end
			for _, m in R.milestones do
				table.insert(all, m.bit)
			end
			for _, b in all do
				check(not seen[b], "bit " .. b .. " used once")
				seen[b] = true
				check(b >= 1 and b < ProfileSchema.SMALL_WORDS * 32, "bit " .. b .. " inside 1..127")
			end
			-- every robot kind in the game has a page (its own, or its finale villain's)
			local kinds = {}
			for _, e in RoguesFile.list(Config) do
				if e.kind then
					kinds[e.kind] = true
				end
			end
			for _, kind in Config.Enemies.order do
				check(kinds[kind] == true, kind .. " is in the Rogues File")
				local e = RoguesFile.forKind(Config, kind)
				if e then
					check(e.group == "robots" or e.group == "fakes", kind .. " fills a robot or fake page")
				end
			end
			-- the counts: 20 robots, 4 fakes and the twin's, 18 finale villains (16 chains, 2 encores), 3 bosses
			local n = {}
			for _, e in RoguesFile.list(Config) do
				n[e.group] = (n[e.group] or 0) + 1
			end
			check(
				n.robots == 20 and n.fakes == 4 and n.villains == 18 and n.bosses == 3,
				"20 + 4 + 18 + 3 pages"
			)
			check(#RoguesFile.list(Config) == 45, "45 pages")
			-- the bosses keep the bits BossService has set since M6
			for _, id in Config.Boss.order do
				local e = RoguesFile.forBoss(Config, id)
				check(e ~= nil and e.bit == Config.Boss.bosses[id].rogues, id .. " on its Config.Boss bit")
				check(e ~= nil and e.gold ~= nil and e.gold ~= e.bit, id .. " has a gold page")
			end
			-- every live chain's finale villains, the encore too
			for _, chain in Config.SideQuests.chains do
				if not chain.dev then
					local pages = RoguesFile.forChain(Config, chain.id)
					check(#pages >= 1, chain.id .. " has its villain page")
				end
			end
			check(#RoguesFile.forChain(Config, "GalaHeist") == 2, "the Gala Heist: Redline and Masque-a-rade")
			check(
				#RoguesFile.forChain(Config, "HarvestKing") == 2,
				"the Harvest King: the beast and the King"
			)
			check(#RoguesFile.forChain(Config, "Sample") == 0, "no Dev chain in the book")
		end
	)

	test("Rogues File: names and titles come from the game's own data", function()
		local function page(id: string): any
			for _, e in RoguesFile.list(Config) do
				if e.id == id then
					return e
				end
			end
			return nil
		end
		check(page("SparkDrone").name == Config.Enemies.SparkDrone.name, "a robot's Config.Enemies name")
		check(page("Radiant").title == Config.Enemies.Radiant.fake.title, "a fake's title")
		check(page("Pitboss").name == Config.SideQuests.dress.Pitboss.name, "a dressed villain's dress name")
		check(page("Redline").name == "REDLINE", "an encore chain's first villain: its name card")
		check(page("MasqueARade").name == "MADAME MASQUE-A-RADE", "the encore: the chain's villain card")
		check(page("Toymaker").kind == "WindupGiant", "the Toymaker's page is his giant's fight")
		check(page("Tidewright").kind == "Anchor" and page("Tidewright").dress == "Tidewright", "a sea dress")
		check(page("RustjawPrime").title == Config.Cinema.nameCard.titles.RustjawPrime, "a boss's name card")
		check(
			RoguesFile.where(Config, page("Swarmer")) == "Street fights from level 3",
			"a swap robot's hint says its level"
		)
		check(RoguesFile.where(Config, page("SparkDrone")) == "Patrols the whole city", "a plain hint")
		-- nate's rules: fixed text, short lines, none of the main story's names, no gore (whole words, so the
		-- side quest "Starblood Calling" in a hint is fine)
		for _, e in RoguesFile.list(Config) do
			for _, word in { "Null", "Crane", "Halcyon", "Adrian", "Vale", "blood", "kill", "gore", "dead" } do
				local pat = "%f[%a]" .. string.lower(word) .. "%f[%A]"
				check(not string.find(string.lower(e.blurb), pat), e.id .. "'s blurb has no " .. word)
				check(not string.find(string.lower(e.where), pat), e.id .. "'s hint has no " .. word)
			end
			check(#e.blurb <= 80, e.id .. "'s blurb is short")
			check(not string.find(e.blurb, "%", 1, true), e.id .. ": no format holes")
		end
	end)

	test("Rogues File: a page beaten is marked once and counted, with the first day and level", function()
		local words = table.create(RoguesFile.WORDS, 0)
		local log = {}
		check(RoguesFile.beat(Config, words, log, 16, 20775, 3), "the first beat is a new page")
		check(Bits.get(words, 16), "its bit")
		check(not RoguesFile.beat(Config, words, log, 16, 20800, 9), "the second is not")
		check(
			log["16"][1] == 20775 and log["16"][2] == 2 and log["16"][3] == 3,
			"the first day and level stay"
		)
		check(not RoguesFile.beat(Config, words, log, 128, 1, 1), "outside the save: nothing")
		check(not RoguesFile.beat(Config, words, log, -1, 1, 1), "below it too")
		-- a boss: BossService sets its bit before Rewarded, so a page without a log row is still new
		Bits.set(words, 1)
		check(RoguesFile.beat(Config, words, log, 1, 20775, 40), "the boss page is new on its first win")
		check(not RoguesFile.beat(Config, words, log, 1, 20776, 40), "then counted")
		log["17"] = { 1, R.countMax, 1 }
		Bits.set(words, 17)
		RoguesFile.beat(Config, words, log, 17, 2, 2)
		check(log["17"][2] == R.countMax, "the count stops at countMax")
		check(RoguesFile.countText(1000) == "999+" and RoguesFile.countText(12) == "12", "the count shown")
		local n, total = RoguesFile.count(Config, words)
		check(n == 3 and total == 45, "3 of 45 (a gold page is extra)")
		check(RoguesFile.dateText(20775) == "18 Nov 2026", "a day as a date")
		check(RoguesFile.dateText(11016) == "29 Feb 2000", "a leap day")
		check(RoguesFile.dateText(20088) == "31 Dec 2024", "a year's end")
		check(RoguesFile.dateText(20878) == "1 Mar 2027", "after February")
		check(RoguesFile.dateText(0) == "1 Jan 1970", "day 0")
	end)

	test("Rogues File: gold pages are hard boss wins only", function()
		check(RoguesFile.isGold(Config, "mvp", true, 40), "MVP at level 40")
		check(RoguesFile.isGold(Config, "contributor", true, 50), "a Contributor at 50")
		check(not RoguesFile.isGold(Config, "participant", true, 50), "not a Participant")
		check(not RoguesFile.isGold(Config, "floor", true, 50), "not the floor")
		check(not RoguesFile.isGold(Config, "mvp", true, 39), "not below the gold level")
		check(not RoguesFile.isGold(Config, "mvp", false, 50), "not a retreat")
		check(not RoguesFile.isGold(Config, "mvp", true, nil), "not without the fight's level")
		check(R.gold.level == Config.Heroic.minLevel, "the gold level is the Heroic band's floor")
		local words = table.create(RoguesFile.WORDS, 0)
		Bits.set(words, 9)
		local g, gt = RoguesFile.goldCount(Config, words)
		check(g == 1 and gt == 3, "1 of 3 gold pages")
	end)

	test("Rogues File: milestone rewards at 10, 25 and every page, earnable looks only", function()
		local words = table.create(RoguesFile.WORDS, 0)
		local list = RoguesFile.list(Config)
		check(#RoguesFile.due(Config, words) == 0, "nothing at 0")
		check(RoguesFile.nextMilestone(Config, words).n == 10, "next: 10")
		for i = 1, 10 do
			Bits.set(words, list[i].bit)
		end
		local due = RoguesFile.due(Config, words)
		check(#due == 1 and due[1].n == 10, "10 pages: the first reward")
		Bits.set(words, due[1].bit)
		check(#RoguesFile.due(Config, words) == 0, "paid once")
		check(RoguesFile.nextMilestone(Config, words).n == 25, "next: 25")
		for _, e in list do
			Bits.set(words, e.bit)
		end
		due = RoguesFile.due(Config, words)
		check(#due == 2 and due[2].all == true, "every page: 25 and all at once")
		check(RoguesFile.need(Config, due[2]) == #list, "all = every page")
		check(RoguesFile.nextMilestone(Config, words) == nil, "nothing left")
		-- the milestone bits never count as pages
		for _, m in due do
			Bits.set(words, m.bit)
		end
		check((RoguesFile.count(Config, words)) == #list, "the count is pages only")
		local idx = CreatorRules.index(Config)
		for _, m in R.milestones do
			local p = idx.byName[m.piece]
			check(p ~= nil, m.piece .. " is a creator piece")
			check(
				p ~= nil and p.source.kind == "drop",
				m.piece .. " is earnable in play (a drop piece), never sold"
			)
		end
	end)

	test("Rogues File: the save keeps the log, cleaned on load, with no version bump", function()
		local p = ProfileSchema.default()
		check(type(p.roguesLog) == "table" and next(p.roguesLog) == nil, "an empty log by default")
		local raw = ProfileSchema.default()
		raw.roguesLog = {
			["16"] = { 20775, 4, 3 },
			["1"] = { 20775.7, -5, 999 },
			["200"] = { 1, 1, 1 },
			["x"] = { 1, 1, 1 },
			["17"] = "junk",
			["18"] = { "a", 5, 2 },
		}
		local back = ProfileSchema.load(serde.decode("json", serde.encode("json", raw)))
		local log = back.roguesLog
		check(log["16"][1] == 20775 and log["16"][2] == 4 and log["16"][3] == 3, "a good row stays")
		check(log["1"][1] == 20775 and log["1"][2] == 0 and log["1"][3] == ProfileSchema.LEVEL_CAP, "clamped")
		check(log["200"] == nil and log["x"] == nil and log["17"] == nil, "bad rows go")
		check(log["18"] ~= nil and log["18"][1] == 0 and log["18"][3] == 2, "a broken row is repaired")
		local old = ProfileSchema.default()
		old.roguesLog = nil
		check(type(ProfileSchema.load(old).roguesLog) == "table", "an older save gets the log")
		check(
			ProfileSchema.clientView(p).roguesLog == nil,
			"the log rides on RoguesFile, not the profile sync"
		)
	end)

	test("Rogues File: rogues_page fires once per page per account, never again after a rejoin", function()
		local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
		check(R.analytics == true, "on (Config.Rogues.analytics, interim pick)")
		local ok, clean = AnalyticsSchema.check("rogues_page", { "bosses", "1" })
		check(ok and #clean == 2, "in AnalyticsSchema with its two fields")
		check(AnalyticsSchema.NOSAVE.rogues_page == nil, "never sent for a save that did not load")
		check(Config.Analytics.lowPriority.rogues_page == nil, "not a busy event (it gets the full budget)")
		-- every page bit and gold bit, in book order (a gold page after its boss's)
		local bits, gold = {}, {}
		for _, e in RoguesFile.list(Config) do
			table.insert(bits, e.bit)
			if e.gold then
				table.insert(bits, e.gold)
				gold[e.gold] = true
			end
		end
		-- RoguesService.beat's rule: an event only when RoguesFile.beat says the page is new
		local function fill(profile: any, bit: number, sent: { { any } })
			if RoguesFile.beat(Config, profile.rogues, profile.roguesLog, bit, 20775, 10) then
				local value, fields = RoguesFile.event(Config, profile.rogues, bit)
				if value and fields then
					table.insert(sent, { bit, value, fields })
				end
			end
		end
		local profile = ProfileSchema.default()
		local sent = {}
		for _, bit in bits do
			fill(profile, bit, sent)
			fill(profile, bit, sent) -- beaten again at once: no second event
		end
		check(#sent == #bits, string.format("one event a page (%d of %d)", #sent, #bits))
		local seen, n = {}, 0
		for _, s in sent do
			local bit, value, fields = s[1], s[2], s[3]
			check(not seen[bit], "page " .. bit .. " once")
			seen[bit] = true
			local e = RoguesFile.byBit(Config, bit)
			for _, x in RoguesFile.list(Config) do
				if x.gold == bit then
					e = x
				end
			end
			check(e ~= nil and fields[1] == (e :: any).group, "page " .. bit .. ": its kind " .. fields[1])
			check(fields[2] == (if gold[bit] then "1" else "0"), "page " .. bit .. ": gold " .. fields[2])
			check(#fields == 2 and type(value) == "number", "two short fields and a number, no names")
			if not gold[bit] then
				n += 1
			end
			check(value == n, "value: pages filled so far (" .. value .. ")")
		end
		-- a rejoin (and a server hop: the same save) loads the pages back: nothing fires again
		local back = ProfileSchema.load(serde.decode("json", serde.encode("json", profile)))
		local again = {}
		for _, bit in bits do
			fill(back, bit, again)
		end
		check(#again == 0, "no event after a rejoin (" .. #again .. ")")
		-- half way: the rest still fire once each after the rejoin, never the first half again
		local half = ProfileSchema.default()
		local first = {}
		for i = 1, #bits // 2 do
			fill(half, bits[i], first)
		end
		local half2 = ProfileSchema.load(serde.decode("json", serde.encode("json", half)))
		local rest = {}
		for _, bit in bits do
			fill(half2, bit, rest)
		end
		check(#first + #rest == #bits and #rest == #bits - #bits // 2, "the rest once each after a rejoin")
		-- the switch off: no event at all
		local off = table.clone(Config)
		off.Rogues = table.clone(R)
		off.Rogues.analytics = false
		check(RoguesFile.event(off, profile.rogues, bits[1]) == nil, "off: no event")
		check(RoguesFile.event(Config, profile.rogues, 0) == nil, "not a page: no event")
	end)

	test(
		"Rogues File: rogues_page stays inside the per-minute budget (sliding window, every send counts)",
		function()
			local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
			local cfg = Config.Analytics.budget
			local players = 30
			local cap = AnalyticsSchema.cap(cfg, players)
			-- the biggest burst: a world boss beaten by 30 players at the gold level fills its page and its gold
			-- page for every one at once (2 each), on a window the busy events already filled to their share
			local b = AnalyticsSchema.newBudget()
			local t = 0
			while AnalyticsSchema.take(b, cfg, t, players, true) do
				t += 0.01
			end
			local burst, ok = players * 2, 0
			for _ = 1, burst do
				if AnalyticsSchema.take(b, cfg, t, players, false) then
					ok += 1
				end
			end
			check(ok == burst, string.format("all %d fit beside the busy events (cap %d)", burst, cap))
			-- a full window: the page waits (queued), takes no slot, and goes once the window has room
			local full = AnalyticsSchema.newBudget()
			for _ = 1, cap do
				AnalyticsSchema.force(full, cfg, 0, players)
			end
			local queue = { { 1, { "robots", "0" } }, { 2, { "bosses", "0" } } }
			local logged = 0
			local function send(now: number): (number, { string }) -> string
				return function(_v: number, _f: { string }): string
					if AnalyticsSchema.take(full, cfg, now, players, false) then
						logged += 1
						return "sent"
					end
					return "full"
				end
			end
			RoguesFile.drain(queue, send(30))
			check(#queue == 2 and logged == 0 and full.n == cap, "a full window: both wait and spend nothing")
			RoguesFile.drain(queue, send(61))
			check(#queue == 0 and logged == 2, "the window moved on: both go, once each")
			RoguesFile.drain(queue, send(62))
			check(logged == 2, "never twice")
			local gone = { { 1, { "robots", "0" } } }
			RoguesFile.drain(gone, function()
				return "refused"
			end)
			check(#gone == 0, "a refused one (left, or a save that did not load) is not retried")
			-- the service: an event only in beat()'s fresh branch, through Analytics.event (the budget)
			local svc = fs.readFile("src/server/Services/RoguesService.luau")
			local freshAt = string.find(svc, "fresh = true", 1, true) or 0
			local evAt = string.find(svc, "RoguesFile.event(Config, profile.rogues, bit)", 1, true) or 0
			check(
				freshAt > 0 and evAt > freshAt and evAt - freshAt < 200,
				"fired only for a page just filled"
			)
			check(
				string.find(svc, 'Analytics.event(player, "rogues_page", value, fields)', 1, true) ~= nil,
				"through Analytics.event (the per-minute budget)"
			)
			local an = fs.readFile("src/server/Services/Analytics.luau")
			check(
				string.find(an, 'return "full"', 1, true) ~= nil,
				"Analytics.event says when the budget was full"
			)
		end
	)

	test("Rogues File and Journal tabs: wired through signals and the Journal", function()
		local svc = fs.readFile("src/server/Services/RoguesService.luau")
		check(string.find(svc, "EnemyService.Killed:Connect", 1, true) ~= nil, "robot kills")
		check(string.find(svc, "SideQuestService.StepPaid:Connect", 1, true) ~= nil, "side quest finales")
		check(string.find(svc, "BossService.Rewarded:Connect", 1, true) ~= nil, "world bosses")
		check(
			string.find(svc, "ident.dress", 1, true) ~= nil,
			"a dressed finale villain is not its suit's robot"
		)
		-- a dressed fake (a finale villain, or WP5's Suspicious Hero costumes in Config.Incidents.dress) never
		-- counts as its suit's kind: every dress reads dress = true, and the identity is still there when Killed
		-- fires (it is forgotten just after)
		local FakeRules = require("../src/shared/FakeRules")
		local dressed = 0
		for _, set in { Config.SideQuests.dress or {}, (Config.Incidents :: any).dress or {} } do
			for id in set do
				local d = FakeRules.dress(Config, id)
				check(d ~= nil and d.dress == true, id .. ": a dress reads dress = true")
				dressed += 1
			end
		end
		check(dressed > 0, "dresses were checked")
		local es = fs.readFile("src/server/Services/EnemyService.luau")
		local fire = string.find(es, "EnemyService.Killed:Fire(ev.kind, ev.by", 1, true)
		local forget = fire and string.find(es, "forgetIdent(ev.e)", fire, true)
		check(fire ~= nil and forget ~= nil, "the identity outlives the Killed signal")
		check(string.find(svc, 'Net.on("RoguesOpen"', 1, true) ~= nil, "the tab asks for its pages")
		local sq = fs.readFile("src/server/Services/SideQuestService.luau")
		check(
			string.find(sq, 'StepPaid:Fire(player, res == "done", chain.id)', 1, true) ~= nil,
			"the chain id"
		)
		local boss = fs.readFile("src/server/Services/BossService.luau")
		check(
			string.find(boss, "Rewarded:Fire(player, f.id, tier, defeated, score, f.level)", 1, true) ~= nil,
			"level"
		)
		check(string.find(boss, "Bits.set(profile.rogues, f.sim.cfg.rogues)", 1, true) ~= nil, "the boss bit")
		local boot = fs.readFile("src/server/init.server.luau")
		check(string.find(boot, 'boot("RoguesService", RoguesService.init)', 1, true) ~= nil, "booted")
		local J = fs.readFile("src/client/Ui/Journal.luau")
		for _, id in { "rogues", "badges", "mentor", "showdown" } do
			check(string.find(J, '"' .. id .. '"', 1, true) ~= nil, "the Journal has a " .. id .. " tab")
		end
		check(string.find(J, "RoguesPage.drawInto(body)", 1, true) ~= nil, "the ROGUES tab")
		check(string.find(J, "BadgeHud.drawInto(body", 1, true) ~= nil, "the Badge Book's views")
		check(string.find(J, "MentorHud.drawInto(body)", 1, true) ~= nil, "the mentor card")
		check(string.find(J, "NemesisHud.drawInto(body, Journal.close)", 1, true) ~= nil, "the Showdown")
		check(
			string.find(J, 'Kit.opening("Journal", panel, Journal.close, true)', 1, true) ~= nil,
			"one main panel"
		)
		for _, hud in { "BadgeHud", "MentorHud", "NemesisHud" } do
			local src = fs.readFile("src/client/Ui/" .. hud .. ".luau")
			check(string.find(src, "function " .. hud .. ".drawInto(", 1, true) ~= nil, hud .. ".drawInto")
			check(string.find(src, "function " .. hud .. ".request(", 1, true) ~= nil, hud .. ".request")
			check(string.find(src, hud .. ".Changed:Fire()", 1, true) ~= nil, hud .. ".Changed")
		end
	end)

	local placePath = T.placePath
	if not placePath then
		return
	end

	test("Journal tabs at phone, tablet and PC sizes: on screen, readable, tappable", function()
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(placePath)))
		local P = Config.Ui.phone
		local DEVICES = {
			{ name = "iPhone SE", w = 667, h = 375, top = 58, left = 0, right = 0, bottom = 0, touch = true },
			{
				name = "Android 640",
				w = 640,
				h = 360,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = true,
			},
			{
				name = "iPhone 14",
				w = 844,
				h = 390,
				top = 58,
				left = 47,
				right = 47,
				bottom = 0,
				touch = true,
			},
			{
				name = "PC 1080p",
				w = 1920,
				h = 1080,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = false,
			},
		}
		for _, d in DEVICES do
			local sim = UiSim.new(trees, d)
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			local M = {}
			for _, m in { "BadgeHud", "MentorHud", "NemesisHud", "Journal" } do
				M[m] = sim:require("Client.Ui." .. m)
				sim:run(m, M[m].init)
			end
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			local function fire(name: string, data: any)
				sim:run(name, function()
					remotes:WaitForChild(name).OnClientEvent:Fire(data)
				end)
			end
			local function report(tag: string)
				for _, issue in
					sim:issues({
						minTap = P.minTap,
						minText = P.minText,
						safe = true,
						minList = 90,
						only = { Journal = true },
					})
				do
					check(false, d.name .. " " .. tag .. ": " .. issue)
				end
			end
			-- loading states first, then each tab with its data
			for _, id in { "rogues", "badges", "mentor", "showdown" } do
				check(
					sim:run("open " .. id, function()
						M.Journal.open(id)
					end),
					d.name .. ": the Journal opens on " .. id
				)
				report(id .. " loading")
			end
			fire("RoguesFile", {
				bits = { 16, 17, 25, 48, 64, 66, 1, 9, 2 },
				log = {
					["16"] = { 20775, 1234, 3 },
					["17"] = { 20775, 2, 4 },
					["25"] = { 20776, 1, 5 },
					["48"] = { 20777, 1, 6 },
					["64"] = { 20777, 1, 8 },
					["66"] = { 20778, 1, 9 },
					["1"] = { 20778, 3, 40 },
					["9"] = { 20779, 1, 41 },
					["2"] = { 20779, 1, 22 },
				},
			})
			fire("BadgeBook", {
				bits = { 0, 1 },
				progress = {},
				titles = { { id = 0, name = "Spark-Born" }, { id = 1, name = "Rookie" } },
				title = 0,
				accolades = {},
				aura = 0,
				trim = 0,
				collect = { 0, 1, 2 },
				scanner = 0,
			})
			fire("MentorState", {
				k = "card",
				mentor = 1,
				side = Config.Mentors.list[1].side,
				parts = { 1, 0, 0, 0 },
				count = { 3, 0 },
				open = 2,
				level = 12,
				look = 0,
				atSafe = true,
				canPick = true,
			})
			fire("NemesisState", {
				k = "poster",
				name = "Gearjaw the Relentless",
				rank = 2,
				traits = 3,
				intel = 3,
				met = 2,
				readyIn = 0,
				locked = false,
				showdown = true,
				banes = 1,
			})
			for _, id in { "rogues", "badges", "mentor", "showdown" } do
				sim:run("open " .. id, function()
					M.Journal.open(id)
				end)
				report(id)
			end
			-- the Badge Book's other two views
			local journal = sim.playerGui:FindFirstChild("Journal")
			sim:run("open badges", function()
				M.Journal.open("badges")
			end)
			for _, view in { "COLLECTIONS", "TITLES" } do
				local b = nil
				for _, c in journal:GetDescendants() do
					if c:IsA("TextButton") and c.Text == view then
						b = c
					end
				end
				check(b ~= nil, d.name .. ": the " .. view .. " view button")
				if b then
					sim:tap(b)
					report("badges " .. view)
				end
			end
			-- the ROGUES tab drew every page, beaten ones named and the rest as silhouettes
			sim:run("open rogues", function()
				M.Journal.open("rogues")
			end)
			local pages, unknown, gold = 0, 0, false
			for _, c in journal:GetDescendants() do
				if c:IsA("Frame") and string.match(c.Name, "^Page%d+$") then
					pages += 1
				end
				if c:IsA("TextLabel") then
					if c.Text == "???" then
						unknown += 1
					elseif string.find(c.Text, "GOLD PAGE", 1, true) then
						gold = true
					end
				end
			end
			check(pages == 45, d.name .. ": 45 pages drawn (" .. pages .. ")")
			-- 8 pages beaten (bit 9 is Rustjaw Prime's gold mark, not a page of its own)
			check(unknown == 45 - 8, d.name .. ": 37 silhouettes (" .. unknown .. ")")
			check(gold, d.name .. ": Rustjaw Prime's gold page")
			-- SHOWDOWN starts the fight and closes the Journal (one main panel)
			sim:run("open showdown", function()
				M.Journal.open("showdown")
			end)
			local start = nil
			for _, c in journal:GetDescendants() do
				if c:IsA("TextButton") and c.Text == "SHOWDOWN" and not string.match(c.Name, "^Tab_") then
					start = c
				end
			end
			check(start ~= nil, d.name .. ": the SHOWDOWN button")
			if start then
				sim:tap(start)
				check(not M.Journal.isOpen(), d.name .. ": SHOWDOWN closes the Journal")
			end
			for _, e in sim.errors do
				check(false, d.name .. ": " .. tostring(e))
			end
		end
	end)
end
