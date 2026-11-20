-- Early pacing (list-combat 2026-11-20, nate: "the first 30 minutes matter most": level 5 and a new power by about 15
-- minutes, the first mobility rank by about 20). EconomySim.firstSession from the onboarding timeline's end (the
-- loading screen, the intro film, the creator and the prologue). ONLY="Pacing" runs these.
return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local EconomySim = require("../src/shared/EconomySim")
	local Progress = require("../src/shared/Progress")
	local Sim = require("./onboarding_sim")

	test("Pacing: level 5 and a new power by about 15 minutes, a mobility rank by 20", function()
		for _, side in { "hero", "villain" } do
			local tl = Sim.timeline(Config, side)
			check(
				tl.ends > 240 and tl.ends < 900,
				string.format("%s: the prologue ends at %.0f s", side, tl.ends)
			)
			local r = EconomySim.firstSession(Config, tl.ends, 40)
			local l5 = r.levelAt[5] or math.huge
			check(l5 <= 16 * 60, string.format("%s: level 5 at %.1f min", side, l5 / 60))
			check(
				(r.powerAt or math.huge) <= 16 * 60,
				string.format("%s: the third skill slot at %.1f min", side, (r.powerAt or math.huge) / 60)
			)
			check(
				(r.mobilityAt or math.huge) <= 20 * 60,
				string.format("%s: mobility rank 1 at %.1f min", side, (r.mobilityAt or math.huge) / 60)
			)
			-- not a rush to the top: still short of level 12 after 40 minutes
			check(r.level < 12, side .. ": level " .. r.level .. " after 40 minutes")
		end
	end)

	test(
		"Pacing: the rookie boost is earned only, ends by level 7, and the prologue's level is exact",
		function()
			for L = 1, Config.Stats.levelCap do
				local m = Progress.rookie(Config, L)
				check(m >= 1 and m <= 4, "boost at level " .. L)
				if L >= 7 then
					check(m == 1, "no boost at level " .. L)
				end
			end
			local fs = require("@lune/fs")
			local os_ = fs.readFile("src/server/Services/OpeningService.luau")
			local es = fs.readFile("src/server/Services/EconomyService.luau")
			check(
				string.find(os_, "EconomyService.addRenown(player, need, true)", 1, true) ~= nil,
				"the prologue tops up exactly"
			)
			check(
				string.find(es, "Progress.rookie(Config, hero.level)", 1, true) ~= nil,
				"Renown goes through the boost"
			)
			check(
				Config.Move.ranks.levels[1] <= Config.Abilities.slotLevels[3],
				"rank 1 opens with the new power"
			)
		end
	)
end
