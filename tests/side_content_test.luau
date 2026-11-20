-- side-content (nate, 2026-11-19): lore pages, mobility training and each side's own radiant content. Run by
-- tests/run.luau (ONLY=SideContent runs this file):
--   require("./side_content_test")({ test = test, check = check, Config = Config, world = world })

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local LorePlan = require("../src/shared/LorePlan")
	local LoreBookKit = require("../src/shared/LoreBookKit")
	local MoveRanks = require("../src/shared/MoveRanks")
	local MoveMath = require("../src/shared/MoveMath")
	local MoveCheck = require("../src/shared/MoveCheck")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local BadgeRules = require("../src/shared/BadgeRules")
	local IncidentPlan = require("../src/shared/IncidentPlan")
	local ContractPlan = require("../src/shared/ContractPlan")
	local EventPlan = require("../src/shared/EventPlan")
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local HqArtKit = require("../src/shared/HqArtKit")
	local L = Config.Lore

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	---------------------------------------------------------------------------
	-- Lore pages
	---------------------------------------------------------------------------

	test("SideContent lore: the pages' data is clean and every district has pages", function()
		local bad = LorePlan.validate(Config)
		check(#bad == 0, "Config.Lore validates: " .. table.concat(bad, "; "))
		check(#L.pages >= 20, "at least 20 pages (" .. #L.pages .. ")")
		check(#L.districts == 11, "11 districts")
		for _, d in L.districts do
			check(L.look.cover[d.id] ~= nil, d.id .. " has a cover colour")
		end
		for _, p in L.pages do
			check(p.bit <= L.bits, p.id .. " fits the 2-word save")
		end
	end)

	test("SideContent lore: every page finds a flat spot near its landmark, apart from the others", function()
		local spots = LorePlan.spots(Config, world)
		check(#spots == #L.pages, string.format("%d of %d pages placed", #spots, #L.pages))
		for i, a in spots do
			check(a.y == a.y and math.abs(a.y) < 2000, a.id .. " has a sane height")
			for j = i + 1, #spots do
				local b = spots[j]
				check((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 > 100, a.id .. " and " .. b.id .. " are apart")
			end
		end
		-- a page near its anchor (within the search's reach plus the door offset)
		for _, s in spots do
			local page = LorePlan.byId(L, s.id)
			local ax, az = LorePlan.anchor(Config, world, page.at)
			if ax and not (page.at.site and Config.SideQuests.sites[page.at.site].deep) then
				local d = math.sqrt((s.x - ax) ^ 2 + (s.z - az) ^ 2)
				check(
					d <= L.place.far + 1,
					string.format("%s within %d of its anchor (%.0f)", s.id, L.place.far, d)
				)
			end
		end
		-- the same spots another week (the hub's pages never move; outskirts ones follow their sites)
		local other = LorePlan.spots(Config, require("../src/shared/WorldMap").build(Config, 202650))
		check(#other == #L.pages, "every page placed on another week's seed")
	end)

	test("SideContent lore: rewards, district titles, the full set and the Badge Book's titles", function()
		local words = { 0, 0 }
		local crater = LorePlan.inDistrict(L, "Crater")
		check(#crater >= 2, "the Crater has pages")
		local r = LorePlan.reward(L, words, crater[1].bit)
		check(r and r.renown == L.renown.page and r.district == nil, "a first page pays Renown only")
		LorePlan.mark(words, crater[1].bit)
		check(LorePlan.reward(L, words, crater[1].bit) == nil, "a page read is never paid twice")
		for i = 2, #crater do
			r = LorePlan.reward(L, words, crater[i].bit)
			LorePlan.mark(words, crater[i].bit)
		end
		check(
			r and r.district == "Crater" and r.renown == L.renown.page + L.renown.set,
			"the last Crater page pays the set"
		)
		local i = LorePlan.districtIndex(L, "Crater") :: number
		check(r and table.find(r.titles, L.titleBase + i) ~= nil, "and its title")
		for _, p in L.pages do
			if not LorePlan.has(words, p.bit) then
				r = LorePlan.reward(L, words, p.bit)
				LorePlan.mark(words, p.bit)
			end
		end
		check(r and r.all and table.find(r.titles, L.allTitle) ~= nil, "the very last page pays the full set")
		local held = LorePlan.titles(L, words)
		check(#held == #L.districts + 1, "every district's title and the full set's")
		-- the Badge Book lists them (titles change no number in a fight: they are names)
		local p = ProfileSchema.default()
		p.lore = words
		local names = {}
		for _, t in BadgeRules.titles(Config, p, p.characters[1]) do
			names[t.id] = t.name
		end
		check(names[L.allTitle] == L.allName, "the Badge Book has " .. L.allName)
		check(names[L.titleBase + i] == L.districts[i].title, "and the Crater's title")
		local ids = {}
		for _, t in BadgeRules.titles(Config, p, p.characters[1]) do
			check(not ids[t.id], "title ids never repeat (" .. t.id .. ")")
			ids[t.id] = true
		end
		check(Config.Hq.props[L.shelfProp] == "Lore Shelf", "the full set's HQ prop is the Lore Shelf")
		check(
			HqArtKit.PROP_SPOTS[L.shelfProp] ~= nil and HqArtKit.PART_PROPS[L.shelfProp] ~= nil,
			"it has a spot and a kit"
		)
	end)

	test(
		"SideContent lore: the book and the shelf (the pieces the device and the Blender preview draw)",
		function()
			local book = LoreBookKit.book()
			local lo, hi = LoreBookKit.bounds(book)
			check(hi[1] - lo[1] > 2.5 and hi[1] - lo[1] < 6, "the book is a few studs wide")
			check(hi[2] - lo[2] > 2 and hi[2] - lo[2] < 6, "and a few tall")
			local names = {}
			for _, p in book do
				names[p.name] = true
				check(#p.size == 3 and #p.pos == 3 and #p.rot == 3, p.name .. " is whole")
			end
			for _, n in { "CoverL", "CoverR", "PagesL", "PagesR", "Spine", "StarCore", "Halo", "Ribbon" } do
				check(names[n], "the book has its " .. n)
			end
			local colors = LoreBookKit.colors(L.look, "Crater")
			for _, p in book do
				check(colors[p.color] ~= nil, p.name .. "'s colour " .. p.color)
			end
			local ids = {}
			for _, d in L.districts do
				table.insert(ids, d.id)
			end
			local books = 0
			for _, p in LoreBookKit.shelf(ids, {}) do
				if string.sub(p.color, 1, 5) == "book:" then
					books += 1
				end
			end
			check(books == #ids, "the shelf holds a book a district")
			check(fs.isFile("art/preview/lorebook.png"), "the render check is on disk")
			check(fs.isFile("art/export/lore/book.json"), "and its piece list")
		end
	)

	test("SideContent lore: wired on the server, the device, the Journal and the juice", function()
		check(has("src/server/init.server.luau", "LoreService.init"), "LoreService boots")
		check(has("src/client/init.client.luau", "LoreClient.init()"), "LoreClient boots")
		check(has("src/client/Ui/Journal.luau", '{ "lore", "LORE" }'), "the Journal has a LORE tab")
		check(has("src/client/Ui/Journal.luau", "lore = LoreClient"), "fed by LoreClient")
		check(
			has("src/client/Controllers/LoreClient.luau", 'FrameProf.wrap("LoreClient"'),
			"the books' frame loop is profiled"
		)
		check(Config.Ui.popups.cards.lorePage ~= nil, "the caption card is in the popup line")
		local rows = {}
		for _, r in Config.Audio.juice do
			rows[r.id] = true
		end
		for _, id in { "lorePage", "moveTrain" } do
			check(rows[id] and Config.Audio.sounds[id] ~= nil, id .. " has its juice row and sound")
		end
		check(Config.Audio.sounds.loreNear ~= nil, "the near chime")
	end)

	---------------------------------------------------------------------------
	-- The save
	---------------------------------------------------------------------------

	test("SideContent save: version 14 adds the lore pages and the mobility ranks", function()
		check(ProfileSchema.VERSION >= 14, "save version 14 or later")
		local p = ProfileSchema.load({ version = 13, characters = { { level = 8 } } })
		check(p.version == ProfileSchema.VERSION, "a v13 save loads at the current version")
		check(type(p.lore) == "table" and #p.lore == 2 and p.lore[1] == 0, "with no pages read")
		local c = p.characters[1]
		check(type(c.mobRanks) == "table" and #c.mobRanks == 5, "and five untrained ranks")
		for i = 1, 5 do
			check(c.mobRanks[i] == 0, "rank " .. i .. " starts at 0")
		end
		local bad = ProfileSchema.load({
			version = 14,
			lore = { -3, "x" },
			characters = { { level = 8, mobRanks = { 99, -1, 2.6, "a" } } },
		})
		local bc = bad.characters[1]
		check(bad.lore[1] == 0 and bad.lore[2] == 0, "junk lore words repair to 0")
		check(
			bc.mobRanks[1] == 0 and bc.mobRanks[2] == 0 and bc.mobRanks[3] == 2,
			"out-of-range ranks reset to 0, whole ones stay"
		)
		check(#bc.mobRanks == 5 and bc.mobRanks[5] == 0, "a short list fills")
		local view = ProfileSchema.clientView(bad)
		check(view and view.mobRanks ~= nil, "the device sees its ranks")
	end)

	---------------------------------------------------------------------------
	-- Mobility training
	---------------------------------------------------------------------------

	test("SideContent mobility: every rank's speeds sit inside its own server caps", function()
		local bad = MoveRanks.check(Config.Move)
		check(#bad == 0, "MoveRanks.check: " .. table.concat(bad, "; "))
		for _, pick in Config.Move.mobilityOrder do
			check(MoveRanks.max(Config.Move, pick) == 5, pick .. " has 5 ranks")
			local base = MoveRanks.speeds(Config.Move, pick)
			local top = MoveRanks.speeds(MoveRanks.config(Config.Move, pick, 5), pick)
			local faster = false
			for what, v in top do
				faster = faster or v > (base[what] or 0) * 1.08
			end
			check(faster, pick .. "'s top rank is noticeably faster somewhere (8% or more)")
			for r = 1, 5 do
				local row = Config.Move.mobility[pick].ranks[r]
				check(type(row.name) == "string" and #row.text > 0, pick .. " rank " .. r .. " is named")
			end
		end
		check(MoveRanks.config(Config.Move, "flight", 0) == Config.Move, "rank 0 is the base itself")
		check(Config.Move.trained == nil, "training never writes into the base")
		check(
			MoveRanks.config(Config.Move, "flight", 3) == MoveRanks.config(Config.Move, "flight", 3),
			"one copy a pick and rank"
		)
		check(
			MoveRanks.config(Config.Move, "leap", 5).mobility.acrobat.up.jumps == 2,
			"a pick's ranks touch only its own numbers"
		)
		check(MoveRanks.config(Config.Move, "acrobat", 5).mobility.acrobat.up.jumps == 3, "Triple Jump")
	end)

	test(
		"SideContent mobility: the training rule (in order, at its level, for Credits; never sold)",
		function()
			local B = Config.Move
			local ranks = { 0, 0, 0, 0, 0 }
			local ok, why = MoveRanks.canTrain(B, ranks, "flight", 1, 10 ^ 6)
			check(not ok and why == "level", "rank 1 waits for its level")
			ok, why = MoveRanks.canTrain(B, ranks, "flight", B.ranks.levels[1], B.ranks.costs[1] - 1)
			check(not ok and why == "credits", "and its Credits")
			local n, cost
			ok, why, n, cost = MoveRanks.canTrain(B, ranks, "flight", B.ranks.levels[1], B.ranks.costs[1])
			check(ok and n == 1 and cost == B.ranks.costs[1], "then trains to rank 1")
			ranks = MoveRanks.withRank(B, ranks, "flight", n)
			check(
				MoveRanks.rankOf(B, ranks, "flight") == 1 and MoveRanks.rankOf(B, ranks, "speed") == 0,
				"one pick moves"
			)
			ok, why = MoveRanks.canTrain(B, { 5, 0, 0, 0, 0 }, "flight", 99, 10 ^ 9)
			check(not ok and why == "max", "five is the top")
			ok, why = MoveRanks.canTrain(B, ranks, "nothing", 99, 10 ^ 9)
			check(not ok and why == "pick", "no such pick")
			-- nothing sold trains a rank: no shop item or Robux product names a mobility rank
			check(not has("src/config/Shop.luau", "mobRanks"), "the shop never sells ranks")
			check(
				not has("src/server/Services/PurchaseService.luau", "trainMobility"),
				"nor does a Robux receipt"
			)
			check(
				has("src/server/Services/AbilityService.luau", "EconomyService.spend"),
				"training is paid in Credits"
			)
		end
	)

	test("SideContent mobility: the server's speed budget follows the trained caps", function()
		local B = Config.Move
		local top = MoveRanks.config(B, "flight", 5)
		local styles = { flight = true }
		local baseCap = MoveMath.guardCap(B, styles, true, {})
		local topCap = MoveMath.guardCap(top, styles, true, {})
		check(topCap > baseCap, string.format("the trained cap is higher (%.0f > %.0f)", topCap, baseCap))
		local speed = math.max(top.flight.boost, top.mobility.flight.up.boost)
		check(speed > baseCap * B.tolerance, "the top rank's boost would trip the untrained cap")
		local function fly(cap: number, cfg: any): boolean
			local st = MoveCheck.new(0, 100, 0, 0)
			for i = 1, 100 do
				local t = i * 0.1
				local ok, _, wait = MoveCheck.sample(st, speed * t, 100, 0, t, cap, cfg, Config.Safety)
				if not ok and not wait then
					return false
				end
			end
			return true
		end
		check(fly(topCap, top), "ten seconds at the trained boost pass the trained budget")
		check(not fly(baseCap, B), "and would be pulled back on the untrained one")
		check(
			has("src/server/Services/MoveGuard.luau", "HeroService.moveConfig(hero)"),
			"MoveGuard reads the hero's own caps"
		)
		check(
			has("src/client/Controllers/MoveController.luau", "MoveRanks.config("),
			"the device moves with the same copy"
		)
	end)

	---------------------------------------------------------------------------
	-- Each side's own radiant content
	---------------------------------------------------------------------------

	test(
		"SideContent sides: every shared incident, contract and event has the Syndicate's own words",
		function()
			local gaps = IncidentPlan.sideGaps(Config.Incidents)
			check(#gaps == 0, "incidents: " .. table.concat(gaps, "; "))
			gaps = ContractPlan.sideGaps(Config.Contracts)
			check(#gaps == 0, "contracts: " .. table.concat(gaps, "; "))
			gaps = EventPlan.sideGaps(Config.Events)
			check(#gaps == 0, "events: " .. table.concat(gaps, "; "))
			-- the shared side quest steps too ("same": one goal, each side's own line)
			for _, chain in Config.SideQuests.chains do
				for i, step in chain.steps do
					if step.villain == "same" and step.hero and step.hero.text then
						check(
							step.hero.villainText ~= nil,
							string.format("%s step %d has a villain line", chain.name, i)
						)
					end
				end
			end
			local name = IncidentPlan.title(Config.Incidents, "SkyAmbush", "villain")
			check(
				name ~= IncidentPlan.title(Config.Incidents, "SkyAmbush", "hero"),
				"a villain reads its own title"
			)
			check(
				IncidentPlan.stepText(Config.Incidents, "CaptainWarband", 1, "villain")
					~= IncidentPlan.stepText(Config.Incidents, "CaptainWarband", 1, "hero"),
				"and its own step line"
			)
		end
	)

	test("SideContent sides: each player sees and is offered only its own side's content", function()
		check(
			IncidentPlan.sees("hero", "hero") and IncidentPlan.sees("villain", "villain"),
			"own side sees it"
		)
		check(
			not IncidentPlan.sees("hero", "villain") and not IncidentPlan.sees("villain", "hero"),
			"the other does not"
		)
		check(IncidentPlan.sees(nil, nil), "an unset side is the Vigil's")
		-- the server's send and pay ask it
		check(
			has("src/server/Services/IncidentService.luau", "IncidentPlan.sees(inc.side, hero and hero.side)"),
			"sends ask"
		)
		check(
			has("src/server/Services/IncidentService.luau", "IncidentPlan.sees(inc.side, hero.side)"),
			"pay asks"
		)
		check(
			has("src/server/Services/IncidentService.luau", "IncidentPlan.sees(side, h.side)"),
			"beat toasts ask"
		)
		-- contracts: the board offers only a side's own types
		for _, side in { "hero", "villain" } do
			for _, id in ContractPlan.allowed(Config.Contracts, side) do
				local t = Config.Contracts.types[id]
				check(t.side == "both" or t.side == side, side .. " is offered " .. id)
			end
		end
		-- side quest chains: a chain for the other side is never in the Journal
		local c = ProfileSchema.default().characters[1]
		SideQuestPlan.save(c)
		for _, side in { "hero", "villain" } do
			for _, row in SideQuestPlan.journal(Config, c, 60, side, false) do
				local chain = SideQuestPlan.byBit(Config, row.bit)
				local only = chain and chain.unlock and chain.unlock.side
				check(
					only == nil or only == side,
					side .. "'s journal never lists " .. tostring(chain and chain.name)
				)
			end
		end
		-- a one-side giver is tagged and hidden on the other side's devices
		check(
			SideQuestPlan.giverSide(Config, "Vanta") == "villain",
			"Duchess Vanta serves the Syndicate only"
		)
		for id in Config.SideQuests.givers do
			local only = SideQuestPlan.giverSide(Config, id)
			check(only == nil or only == "hero" or only == "villain", id .. " has a side or both")
		end
		check(
			has("src/server/Services/SideQuestService.luau", 'CollectionService:AddTag(model, "SideOnly")'),
			"tagged"
		)
		check(has("src/client/init.client.luau", "SideOnly.init()"), "the device hides the other side's")
	end)
end
