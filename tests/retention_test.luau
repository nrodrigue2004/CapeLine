-- Retention (list-combat 2026-11-20, nate: "a recurring player base"): the week's city news, boss alerts and the
-- weekly bounty, nemesis callbacks and scars, long goals, the friend boss invite. ONLY="Retention" runs these.
return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local BossMath = require("../src/shared/BossMath")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local LongGoals = require("../src/shared/LongGoals")
	local NemesisMath = require("../src/shared/NemesisMath")
	local LorePlan = require("../src/shared/LorePlan")

	test("Retention: a weekly bounty boss from the rotation, the same all week, and it moves", function()
		local seen = {}
		for week = 202601, 202652 do
			local id = BossMath.bounty(Config, week)
			check(Config.Boss.bosses[id] ~= nil, "a real boss for week " .. week)
			check(BossMath.bounty(Config, week) == id, "the same every call")
			seen[id] = true
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		check(n == #Config.Boss.order, "every boss takes a turn over a year")
		check(Config.Boss.bounty.mult >= 1.5 and Config.Boss.bounty.dust > 0, "the bounty pays")
		local p = ProfileSchema.default()
		check(p.stats.bountyWeek == 0 and p.stats.newsWeek == 0, "saved per account, 0 for new saves")
		local bs = fs.readFile("src/server/Services/BossService.luau")
		check(string.find(bs, "profile.stats.bountyWeek ~= week", 1, true) ~= nil, "paid once a week")
		check(string.find(bs, 'id = "bossSoon"', 1, true) ~= nil, "the rises-in alert")
		check(string.find(bs, 'id = "friendBoss"', 1, true) ~= nil, "the friend invite")
		for _, m in Config.Boss.schedule.alerts do
			check(m * 60 > Config.Boss.schedule.banner, "an alert before the banner")
		end
		local toasts = fs.readFile("src/client/Ui/Toasts.luau")
		for _, id in { "bossSoon", "friendBoss", "weekNews" } do
			check(string.find(toasts, '"' .. id .. '"', 1, true) ~= nil, "Toasts shows " .. id)
		end
		local ds = fs.readFile("src/server/Services/DailyService.luau")
		check(string.find(ds, 'id = "weekNews"', 1, true) ~= nil, "the week's news on a returning visit")
	end)

	test("Retention: the nemesis remembers you (callback lines and scars)", function()
		local N = Config.Nemesis
		check(#N.callbacks >= 4 and N.scars >= 1, "callback lines and scars")
		for i = 1, 20 do
			local line = NemesisMath.line(N, "callback", 1234, i, "Ace")
			check(string.find(line, "Ace", 1, true) ~= nil, "the hero's name in " .. line)
			check(string.find(line, "{", 1, true) == nil, "no template left in " .. line)
		end
		local ns = fs.readFile("src/server/Services/NemesisService.luau")
		check(string.find(ns, 'if st.met >= 2 then "callback"', 1, true) ~= nil, "from the second meeting")
		check(select(2, string.gsub(ns, "scars = math.clamp", "")) >= 2, "both spawns send the scars")
		local fx = fs.readFile("src/client/Fx/NemesisFx.luau")
		check(string.find(fx, "d.scars", 1, true) ~= nil, "NemesisFx draws them")
	end)

	test("Retention: long goals as bars from the client's own view", function()
		local p = ProfileSchema.default()
		local view = ProfileSchema.clientView(p)
		local lore = LorePlan.progress(Config.Lore, {})
		local rows = LongGoals.rows(Config, view, lore)
		local ids = {}
		for _, r in rows do
			ids[r.id] = true
			check(r.have >= 0 and r.have <= r.need and r.need > 0, r.id .. " in range")
			check(#r.note > 0 and #r.note <= 70, r.id .. " has a short note")
		end
		for _, id in { "level", "hq", "mobility", "mastery", "lore", "bosses" } do
			check(ids[id] == true, "a " .. id .. " goal")
		end
		view.level = Config.Stats.levelCap
		local capped = LongGoals.rows(Config, view, nil)
		check(capped[1].id == "legacy", "Legacy past the cap")
		local j = fs.readFile("src/client/Ui/Journal.luau")
		check(string.find(j, '{ "goals", "GOALS" }', 1, true) ~= nil, "a GOALS tab in the Journal")
	end)
end
