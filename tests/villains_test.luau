-- The villain name cards and catalog beards pass (gap-villains, 2026-11-19, nate): every side quest finale's name
-- card has its villain's rendered portrait (Config.VillainArt, Shared.VillainCards), and facial hair is Roblox
-- catalog beards only (Config.CatalogLooks.beards), pickable in the creator and worn by the cast who suit one.
-- Called from tests/run.luau:
--   require("./villains_test")({ test = test, check = check, Config = Config })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local VillainCards = require("../src/shared/VillainCards")
	local PeopleLooks = require("../src/shared/PeopleLooks")
	local CreatorRules = require("../src/shared/CreatorRules")
	local FakeRules = require("../src/shared/FakeRules")

	test("Villain cards: every side quest finale's name card has an uploaded portrait cell", function()
		local problems = VillainCards.problems(Config)
		check(#problems == 0, "villain cards: " .. table.concat(problems, "; "))
		local names = VillainCards.names(Config)
		check(#names >= 17, "every chain's villain and encore card is listed (" .. #names .. ")")
		check(table.find(names, "THE BRAMBLEBEAST") ~= nil, "the encore's first foe has its own card")
		check(table.find(names, "THE TEST VILLAIN") == nil, "the Dev sample chain keeps the text card")
		local used = {}
		for _, n in names do
			local cell = VillainCards.portrait(Config, n)
			check(cell ~= nil, n .. " resolves to a sheet and cell")
			if cell then
				local key = cell.image .. ":" .. cell.offset[1] .. ":" .. cell.offset[2]
				check(used[key] == nil, n .. " has its own cell")
				used[key] = true
				check(cell.size[1] == Config.VillainArt.cell, n .. "'s cell is the sheet's cell size")
			end
		end
		check(
			VillainCards.portrait(Config, "KIND TEST") == nil,
			"a name with no portrait answers nil (text card)"
		)
		check(VillainCards.portrait(Config, nil) == nil, "no name answers nil")
		for i = 1, #Config.VillainArt.sheets do
			local path = "art/export/villains/VillainCards_" .. i .. ".png"
			check(fs.isFile(path), path .. " is exported")
		end
	end)

	test("Villain cards: an unuploaded sheet falls back to the text card", function()
		local A = Config.VillainArt
		local name = VillainCards.names(Config)[1]
		local at = A.cards[name]
		local saved = A.sheets[at[1]]
		A.sheets[at[1]] = 0
		check(VillainCards.portrait(Config, name) == nil, "id 0 answers nil")
		A.sheets[at[1]] = saved
	end)

	test("Catalog beards: verified catalog facial hair, offered free in the creator", function()
		local B = Config.CatalogLooks.beards
		check(#B >= 8 and #B <= 12, "8 to 12 catalog beards (" .. #B .. ")")
		local ids, names = {}, {}
		for _, b in B do
			check(type(b[1]) == "string" and b[1] ~= "", "a beard has a name")
			check(type(b[2]) == "number" and b[2] > 0 and b[2] % 1 == 0, tostring(b[1]) .. " has an asset id")
			check(not ids[b[2]], tostring(b[1]) .. " is listed once")
			ids[b[2]] = b[1]
			names[b[1]] = b[2]
		end
		local tab = nil
		for _, t in Config.Creator.tabs do
			if t.id == "beard" then
				tab = t
			end
		end
		check(
			tab ~= nil and tab.hidden ~= true and tab.catalog == true,
			"the facial hair tab is a catalog tab"
		)
		check(CreatorRules.hidden(Config, "beard") == false, "the creator shows the facial hair tab")
		local offered = 0
		local seen = {}
		for _, p in CreatorRules.index(Config).byTab.beard do
			local id = tonumber(string.match(p.kit, "^cat:(%d+)$") or "")
			if id then
				check(ids[id] == p.name, p.name .. " is a Config.CatalogLooks beard under its own name")
				check(p.source.kind == "free", p.name .. " is free")
				check(CreatorRules.offered(Config, p), p.name .. " is offered")
				check(p.id > 315 and p.id < 340, p.name .. " uses the facial hair tab's own spare ids")
				offered += 1
				seen[id] = true
			else
				check(not CreatorRules.offered(Config, p), p.name .. " (drawn) is never offered")
			end
		end
		check(offered == #B, "every catalog beard is a creator piece")
		-- piece ids stay unique with the new pieces
		local all = {}
		for _, p in CreatorRules.index(Config).list do
			check(all[p.id] == nil, "piece id " .. p.id .. " is used once")
			all[p.id] = true
		end
		-- an older look with a drawn beard drops it (no default beard)
		local look = CreatorRules.defaultLook(Config)
		look.pieces.beard = 3
		look = CreatorRules.offeredLook(Config, look)
		check((look.pieces.beard or 0) == 0, "a drawn beard comes off")
	end)

	test("Catalog beards: the cast who suit one wear a catalog beard, never a drawn one", function()
		local problems = PeopleLooks.castProblems(Config)
		check(#problems == 0, "cast picks: " .. table.concat(problems, "; "))
		local bearded = 0
		for _, k in PeopleLooks.namedKeys(Config) do
			local _, _, _, beard = PeopleLooks.catalogPick(Config, k)
			local def = PeopleLooks.lookDef(Config, k)
			if def and def.pieces.beard then
				check(beard == def.pieces.beard, k .. "'s look's beard is its catalog pick")
				local look = FakeRules.lookFrom(Config, def, k)
				local p = CreatorRules.piece(Config, "beard", look.pieces.beard or 0)
				check(
					p ~= nil and string.sub(p.kit, 1, 4) == "cat:",
					k .. "'s built look wears a catalog beard"
				)
			end
			if beard then
				bearded += 1
			end
		end
		check(bearded >= 12, "the bearded cast have their beards (" .. bearded .. ")")
		for _, k in { "brine", "Gus", "toymaker", "OldBeacon", "hoshi", "lodestar" } do
			local _, _, _, beard = PeopleLooks.catalogPick(Config, k)
			check(beard ~= nil, k .. " wears a catalog beard")
		end
		local pick = PeopleLooks.castPick(Config, "toymaker")
		check(pick ~= nil and type(pick.beard) == "number", "a cast row's beard resolves to its asset id")
		local none = PeopleLooks.castPick(Config, "patch")
		check(none ~= nil and none.beard == nil, "a cast row with no beard wears none")
	end)
end
