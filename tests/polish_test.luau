-- The side quest juice pass and the beacon roof fix (overnight queue item 7, 2026-11-18). Called from
-- tests/run.luau:
--   require("./polish_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="SQ juice" or ONLY="Beacon roofs" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local BuildingState = require("../src/shared/BuildingState")
	local SideQuestPlan = require("../src/shared/SideQuestPlan")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local QuestJuice = require("../src/shared/QuestJuice")
	local GearMath = require("../src/shared/GearMath")
	local DS = Config.Destruction
	local Au = Config.Audio

	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local rows = {}
	for _, row in Au.juice do
		rows[row.id] = row
	end

	---------------------------------------------------------------------------
	-- Task A: side quest juice
	---------------------------------------------------------------------------

	test(
		"SQ juice: every chain moment is a juice row with a sound and a visual, fired by StoryHud",
		function()
			local hud = src("src/client/Ui/StoryHud.luau")
			local jfx = src("src/client/Fx/JuiceFx.luau")
			for _, m in QuestJuice.MOMENTS do
				local id = QuestJuice.moment(Config, m)
				check(id ~= nil, "moment " .. m .. " maps to a juice row")
				local row = id and rows[id]
				check(row ~= nil, m .. ": " .. tostring(id) .. " is in Config.Audio.juice")
				local snd = id and Au.sounds[id]
				check(
					snd ~= nil and (snd.asset > 0 or snd.fallback ~= nil),
					m .. ": a sound (PLACEHOLDER until ids)"
				)
				check(
					id ~= nil and has(hud, 'Juice.fire("' .. id .. '"'),
					m .. ": StoryHud fires " .. tostring(id)
				)
				if row and row.visual == "JuiceFx" then
					check(has(jfx, "function JuiceFx." .. id .. "("), "JuiceFx." .. id .. " draws it")
				end
				check(
					row ~= nil
						and fs.isFile(
							"src/client/"
								.. (if row.visual == "JuiceFx" then "Fx/" else "Ui/")
								.. row.visual
								.. ".luau"
						),
					m .. ": its visual's module exists"
				)
			end
			-- the visuals the moments promise: a stamp or burst each, the result card, the name card's sting
			for _, fn in { "questAccept", "questStep", "questEncore", "questFinale", "questRetry" } do
				local at = string.find(jfx, "function JuiceFx." .. fn .. "(", 1, true)
				local body = at and string.sub(jfx, at, (string.find(jfx, "\nend\n", at, true) or #jfx))
				check(body ~= nil and (has(body, "stamp(") or has(body, "ring(")), fn .. " stamps or bursts")
			end
			check(
				has(jfx, "function JuiceFx.questDone()") and has(hud, "questResult(chain"),
				"chain done: confetti and the card"
			)
			check(
				has(hud, 'Juice.fire("questVillain"') and has(hud, "CinemaHud.nameCard"),
				"the name card plays its sting"
			)
			check(Au.sounds.questDone.sting == true, "the chain's end plays the victory sting")
			check(has(src("src/client/Fx/Juice.luau"), "AudioController.victory()"), "Juice plays the sting")
			check(
				has(src("src/client/Controllers/AudioController.luau"), "function AudioController.victory()"),
				"AudioController has the sting"
			)
		end
	)

	test("SQ juice: every step kind of all 16 chains and every finale maps to a juice action", function()
		local kinds = Au.sideQuest.kinds
		for kind in SideQuestPlan.KINDS do
			local r = kinds[kind]
			check(r ~= nil and rows[r.juice] ~= nil, kind .. " maps to a juice row")
			check(
				r ~= nil
					and type(r.word) == "string"
					and #r.word > 0
					and #r.word <= 12
					and string.upper(r.word) == r.word,
				kind .. " has a short stamp word"
			)
		end
		for kind in kinds do
			check(SideQuestPlan.KINDS[kind] ~= nil, kind .. " is a real step kind")
		end
		check(
			kinds.finale.juice == QuestJuice.moment(Config, "finale"),
			"a finale's win is the finale moment"
		)
		local layers, real, steps = {}, 0, 0
		for _, chain in Config.SideQuests.chains do
			if not chain.dev then
				real += 1
				layers[chain.layer] = (layers[chain.layer] or 0) + 1
			end
			for idx, st in chain.steps do
				for _, side in { "hero", "villain" } do
					local g = SideQuestPlan.goal(st, side)
					if g then
						steps += 1
						local r = QuestJuice.step(Config, g.kind)
						check(
							r ~= nil,
							string.format("%s step %d (%s) %s has juice", chain.id, idx, side, g.kind)
						)
						if idx == #chain.steps then
							check(
								r ~= nil and r.juice == "questFinale",
								chain.id .. ": its finale fires questFinale"
							)
						else
							check(
								r ~= nil and r.juice == "questStep",
								chain.id .. " step " .. idx .. ": questStep"
							)
						end
					end
				end
				local k = QuestJuice.kindOf(chain, idx, "hero")
				check(
					k ~= nil and QuestJuice.step(Config, k) ~= nil,
					chain.id .. " step " .. idx .. ": the hero's kind"
				)
				local kv = QuestJuice.kindOf(chain, idx, "villain")
				check(
					kv ~= nil and QuestJuice.step(Config, kv) ~= nil,
					chain.id .. " step " .. idx .. ": the villain's kind"
				)
			end
			-- the finale's name cards (and an encore's) for the villain sting and the ENCORE! stamp
			local card = SideQuestPlan.card(chain, #chain.steps, 2)
			check(card ~= nil and card.name ~= "", chain.id .. ": its finale has a name card")
		end
		check(real == 16, "16 chains (got " .. real .. ")")
		check(
			layers.district == 7 and layers.character == 4 and layers.origin == 5,
			"7 district, 4 character, 5 origin"
		)
		check(steps > 200, "every step's goals checked (" .. steps .. ")")
		for _, dk in Config.SideQuests.devKinds do
			check(QuestJuice.step(Config, dk.kind) ~= nil, "Dev kind test " .. dk.kind .. " has juice")
		end
	end)

	test(
		"SQ juice: each chain's result card shows its title, pay and every cosmetic reward by name",
		function()
			for _, chain in Config.SideQuests.chains do
				local r = QuestJuice.result(Config, chain, 1234.6, 56)
				check(r.title == string.upper(chain.name) .. " COMPLETE!", chain.id .. ": the card's title")
				check(r.credits == 1234 and r.renown == 56, chain.id .. ": the pay")
				local cos = SideQuestPlan.cosmetic(chain)
				local n = 0
				for _ in cos do
					n += 1
				end
				check(n >= 1 and #r.rewards == n, chain.id .. ": one line per cosmetic")
				if cos.title then
					check(
						table.find(r.rewards, "NEW TITLE: " .. string.upper(cos.title)) ~= nil,
						chain.id .. ": the title"
					)
				end
				if cos.style then
					local id = GearMath.questStyle(Config, cos.style)
					local row = id and GearMath.styleRow(Config, id)
					check(
						row ~= nil and table.find(r.rewards, "NEW STYLE: " .. string.upper(row.name)) ~= nil,
						chain.id .. ": the style by its Gear name"
					)
				end
				for _, line in r.rewards do
					check(#line <= 40, chain.id .. ": a reward line fits the card")
				end
			end
			local none = QuestJuice.result(Config, { name = "X", steps = {} }, nil, nil)
			check(none.credits == 0 and #none.rewards == 0, "no pay, no rewards: zero lines")
		end
	)

	test("SQ juice: the server sends each moment's facts; no side quest toast stays silent", function()
		local svc = src("src/server/Services/SideQuestService.luau")
		check(
			has(svc, 'id = "sqStep", bit = chain.bit, step = g.idx + 1, credits = credits'),
			"a step's pay rides its toast"
		)
		check(
			has(svc, 'id = "sqDone", bit = chain.bit, credits = reward.credits'),
			"the chain's pay rides its toast"
		)
		check(has(svc, "out.sq = g.chain.bit"), "a pocket run's card carries the chain")
		local hud = src("src/client/Ui/StoryHud.luau")
		for _, id in { "sqStart", "sqStep", "sqWait", "sqTest", "sqEncore", "sqDone" } do
			check(has(hud, 'id == "' .. id .. '"'), "StoryHud juices " .. id)
		end
		check(has(hud, 'Net.listen("Toast"'), "StoryHud hears the side quest toasts")
		check(
			has(hud, 'Juice.fire("questRetry"') and has(hud, "PvpClient.Changed"),
			"Downed in a finale: TRY AGAIN"
		)
		check(has(hud, "local sq = r.sq and SideQuestPlan.byBit"), "a pocket's card names the chain")
		check(
			Au.sideQuest.doneDelay > 0 and Au.sideQuest.doneDelay < 3,
			"the card follows the VICTORY! stamp"
		)
	end)

	---------------------------------------------------------------------------
	-- Task B: beacons, safehouses and side quest roofs never stand on a breakable building
	---------------------------------------------------------------------------

	local function under(b: any, x: number, z: number, margin: number): boolean
		return math.abs(x - b.x) <= b.sx / 2 + margin and math.abs(z - b.z) <= b.sz / 2 + margin
	end

	-- supers round the base until it comes down (or nothing more breaks); returns the last state
	local function wreck(book: any, b: any, now: number): number
		for k = 1, 40 do
			local a = k * 2.4
			BuildingState.blast(
				DS,
				book,
				b.id,
				b.x + math.cos(a) * (b.sx / 2 + 1),
				b.base + 4,
				b.z + math.sin(a) * (b.sz / 2 + 1),
				14,
				DS.superStruct,
				now + k * 10
			)
		end
		return book.state[b.id]
	end

	test("Beacon roofs: every beacon's host building is fixed and never breaks", function()
		local book = BuildingState.new(DS, world.buildings)
		local hosts = {}
		for id, bc in world.beacons do
			for _, b in world.buildings do
				if under(b, bc.x, bc.z, 0) and b.base < bc.y and bc.y <= (b.peak or b.top) + 2 then
					check(
						b.fixed == true,
						string.format("beacon %d (%s) stands on building %d: fixed", id, bc.name, b.id)
					)
					check(
						BuildingState.pinned(book, b.id),
						"beacon " .. id .. ": its host is pinned in BuildingState"
					)
					hosts[b.id] = id
				end
			end
		end
		-- beacon 2 (Downtown East) is on a roof: the bug the city audit found
		local host2 = nil
		for bid, bcn in hosts do
			if bcn == 2 then
				host2 = bid
			end
		end
		check(host2 ~= nil, "Downtown East has its host roof")
		if host2 then
			local b = world.buildings[host2]
			check(wreck(book, b, 0) == BuildingState.INTACT, "40 supers on beacon 2's host: still Intact")
			check(
				BuildingState.hit(DS, book, host2, 1e9, 1000) == BuildingState.INTACT,
				"an HP hit does nothing"
			)
			check(not BuildingState.force(DS, book, host2, 1000), "a knockback through it does nothing")
			check(next(book.gone[host2] or {}) == nil and #book.removed == 0, "no piece knocked out")
		end
		-- only beacon hosts are fixed: the rest of the city still breaks
		-- (2026-11-19: the added Old Town and outskirts buildings are also fixed next to a safehouse or under a
		-- beacon, WorldMap.keepClear; tests/impact_test checks those)
		local fixed = 0
		for _, b in world.buildings do
			if b.fixed and not b.more then
				fixed += 1
				check(hosts[b.id] ~= nil, "building " .. b.id .. " is fixed only for a beacon")
			end
		end
		check(fixed >= 1 and fixed <= #Config.World.beacons, "a handful fixed, no more (" .. fixed .. ")")
		local other = nil
		for _, b in world.buildings do
			if not b.fixed and b.district == "Downtown" and b.top - b.base < 60 and not b.crown then
				other = b
				break
			end
		end
		check(
			other ~= nil and wreck(book, other, 5000) ~= BuildingState.INTACT,
			"an ordinary building still breaks"
		)
	end)

	test("Beacon roofs: no safehouse stands on a breakable building", function()
		local pad = Config.World.safehouse.pad
		for id, s in world.safehouses do
			for _, b in world.buildings do
				local hit = under(b, s.x, s.z, pad / 2) and b.base < s.roofY
				check(
					not hit or b.fixed == true,
					string.format("safehouse %d is clear of building %d", id, b.id)
				)
			end
		end
	end)

	test("Beacon roofs: side quest roof sites are held whole while their goal stands", function()
		local book = BuildingState.new(DS, world.buildings)
		local courses = 0
		for id, c in Config.SideQuests.courses do
			if type(c) == "table" then
				local roofs = SideQuestSites.course(Config, world, id)
				check(roofs ~= nil and #roofs >= 3, id .. ": a rooftop course")
				courses += 1
				for _, r in roofs or {} do
					check(
						world.buildings[r.id] ~= nil and world.buildings[r.id].x == r.x,
						id .. ": real building records"
					)
					BuildingState.pin(book, r.id, true)
				end
				local first = roofs and roofs[1]
				if first then
					check(
						wreck(book, world.buildings[first.id], 0) == BuildingState.INTACT,
						id .. ": a held roof stands"
					)
				end
				for _, r in roofs or {} do
					BuildingState.pin(book, r.id, false)
				end
			end
		end
		check(courses == 3, "the 3 rooftop courses")
		-- holders count: two goals on one roof; the roof breaks again once both let go
		local b = nil
		for _, x in world.buildings do
			if not x.fixed and x.district == "Downtown" and x.top - x.base < 60 and not x.crown then
				b = x
				break
			end
		end
		if b then
			BuildingState.pin(book, b.id, true)
			BuildingState.pin(book, b.id, true)
			BuildingState.pin(book, b.id, false)
			check(BuildingState.pinned(book, b.id), "one holder left: still held")
			check(wreck(book, b, 100) == BuildingState.INTACT, "held: nothing breaks")
			BuildingState.pin(book, b.id, false)
			check(not BuildingState.pinned(book, b.id), "let go")
			BuildingState.pin(book, b.id, false)
			check(book.pins[b.id] == nil, "never below zero")
			check(wreck(book, b, 2000) ~= BuildingState.INTACT, "let go: it breaks again")
		end
		local svc = src("src/server/Services/SideQuestService.luau")
		check(has(svc, "BuildingService.state(b.id) == 0 -- a standing roof"), "a roof spot is never a wreck")
		local _, holds = string.gsub(svc, "holdRoof%(goal, b%.id%)", "")
		check(holds >= 3, "every roof spot and both course kinds hold their roofs (" .. holds .. ")")
		check(has(svc, "BuildingService.pin(id, false)"), "clearGoal lets them go")
		local bs = src("src/server/Services/BuildingService.luau")
		check(has(bs, "and not BuildingState.pinned(book, id)"), "a knockback never picks a held wall")
		check(has(bs, "function BuildingService.pin("), "BuildingService.pin")
	end)
end
