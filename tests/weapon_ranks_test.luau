-- Weapon ranks (nate 2026-11-21, card "Mix": "Mastery from use opens each skill, then you rank it up in the
-- POWERS screen like a power"). Run by tests/run.luau (ONLY=WeaponRanks runs this file):
--   require("./weapon_ranks_test")({ test = test, check = check, Config = Config })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local AbilityRules = require("../src/shared/AbilityRules")
	local A, W = Config.Abilities, Config.Weapons
	local M = W.mastery

	-- the first weapon with all four skills
	local wid
	for id, rows in W.skills do
		if A.list["W" .. id .. "V"] and (wid == nil or id < wid) then
			wid = id
		end
	end

	test("WeaponRanks: Mastery opens, points and Credits rank, rank 1 free", function()
		check(wid ~= nil, "a weapon with Z X C V")
		local idX = "W" .. wid .. "X"
		local hero = {
			level = 30,
			startSet = A.defaultLoadout.set,
			ranks = {},
			bonusPoints = 0,
			credits = 10 ^ 9,
			weapon = wid,
			weaponMastery = 0,
		}
		local ok, why = AbilityRules.canRank(Config, hero, idX)
		check(not ok and why == "mastery", "X shut before Mastery " .. M.skills.X .. ": " .. tostring(why))
		hero.weaponMastery = M.skills.X * M.perLevel
		local ok2, why2, pts, cr = AbilityRules.canRank(Config, hero, idX)
		check(ok2, "X ranks once open: " .. tostring(why2))
		local p2, c2 = AbilityRules.rankCost(Config, idX, 2)
		check(pts == p2 and cr == c2, "first bought rank is rank 2's cost")
		-- another weapon's skill can't be ranked
		hero.weapon = wid + 1
		local ok3, why3 = AbilityRules.canRank(Config, hero, idX)
		check(not ok3 and why3 == "weapon", "only the carried weapon ranks: " .. tostring(why3))
		hero.weapon = wid
		-- rank 1 is free: spent counts only bought ranks, and weapon skills never count as borrowed
		hero.ranks[idX] = 1
		check(AbilityRules.pointsSpent(Config, hero.ranks, hero.startSet) == 0, "rank 1 costs nothing")
		check(AbilityRules.creditsSpent(Config, hero.ranks, hero.startSet) == 0, "rank 1 costs no Credits")
		hero.ranks[idX] = 3
		check(
			AbilityRules.pointsSpent(Config, hero.ranks, hero.startSet)
				== (AbilityRules.rankCost(Config, idX, 2)) + (AbilityRules.rankCost(Config, idX, 3)),
			"ranks 2 and 3 are paid"
		)
		check(AbilityRules.borrowed(Config, hero.ranks, hero.startSet) == 0, "weapon skills are not borrowed")
		hero.ranks[idX] = AbilityRules.maxRank(A.list[idX])
		local ok4, why4 = AbilityRules.canRank(Config, hero, idX)
		check(not ok4 and why4 == "max rank", "stops at max rank")
		-- M1 has no ranks
		check(not AbilityRules.canRank(Config, hero, "W" .. wid .. "M1"), "M1 has no ranks")
	end)

	test("WeaponRanks: a rank hits harder like a power's", function()
		local idZ = "W" .. wid .. "Z"
		local e1 = AbilityRules.effective(Config, idZ, 1)
		local e3 = AbilityRules.effective(Config, idZ, 3)
		local d1, d3 = e1.coeff, e3.coeff
		check(
			d1 ~= nil and d3 ~= nil and d3 > d1,
			string.format("rank 3 coeff %s > rank 1 %s", tostring(d3), tostring(d1))
		)
	end)

	test("WeaponRanks: the POWERS screen has the WEAPON tab and the server ranks from rank 1", function()
		local ui = fs.readFile("src/client/Ui/LoadoutScreen.luau")
		check(string.find(ui, '"WeaponTab"', 1, true) ~= nil, "WEAPON tab")
		check(string.find(ui, "MASTERY %d OPENS IT", 1, true) ~= nil, "Mastery lock text")
		local sv = fs.readFile("src/server/Services/AbilityService.luau")
		check(
			string.find(sv, "AbilityRules.weaponRank(hero.ranks, id)", 1, true) ~= nil,
			"server starts weapon ranks at 1"
		)
	end)
end
