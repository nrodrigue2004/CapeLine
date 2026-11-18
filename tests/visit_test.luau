-- WP12 (gap check 2026-11-18, gap G15, spec Update 2): visit a friend's HQ on the same server (Shared.VisitRules,
-- Config.Hq.visit, VisitService, HqClient, SquadHud). Called from tests/run.luau:
--   require("./visit_test")({ test = test, check = check, Config = Config, placePath = process.args[1] })
-- ONLY="WP12" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local VisitRules = require("../src/shared/VisitRules")
	local HqRules = require("../src/shared/HqRules")
	local PocketLayout = require("../src/shared/PocketLayout")
	local EventPlan = require("../src/shared/EventPlan")
	local GuardRules = require("../src/shared/GuardRules")
	local WantedRules = require("../src/shared/WantedRules")
	local NemesisMath = require("../src/shared/NemesisMath")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local NetSchema = require("../src/shared/NetSchema")
	local Remotes = require("../src/shared/Remotes")
	local H = Config.Hq
	local V = H.visit
	local OWNER, VISITOR, OTHER = 1001, 2002, 3003

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- both players free and made, no mutes or blocks
	local function ok(): VisitRules.Context
		return { fromFree = true, toReady = true }
	end

	test(
		"WP12: visit pockets are sealed, out of the map and clear of every HQ cell and mission pocket",
		function()
			local P = V.pocket
			local half = H.cell.size / 2
			local seen = {}
			-- HeroService.MAX_SLOTS: every HQ cell a hero slot can take
			local maxSlots = tonumber(
				string.match(fs.readFile("src/server/Services/HeroService.luau"), "MAX_SLOTS = (%d+)")
			)
			check(maxSlots ~= nil and maxSlots >= 30, "HeroService.MAX_SLOTS read")
			check(P.count >= 30, "a pocket for every host a full server can have")
			for i = 1, P.count do
				local x, y, z = VisitRules.pocket(Config, i)
				local key = x .. "," .. z
				check(not seen[key], "pocket " .. i .. " has its own spot")
				seen[key] = true
				check(
					math.abs(x) > Config.City.mapSize / 2 + half
						and math.abs(z) > Config.City.mapSize / 2 + half,
					"pocket " .. i .. " is off the map"
				)
				check(
					VisitRules.pocketAt(Config, x + 20, y + 3, z - 20) == i,
					"a point in pocket " .. i .. " finds it"
				)
				-- never an HQ cell: the cells' floor to roof (cell.y to cell.y + wall) sits far under the pocket
				check(HqRules.cellAt(Config, x, y + 3, z) == nil, "pocket " .. i .. " is not an HQ cell")
				check(y - (H.cell.y + H.cell.wall + 2) >= 300, "pocket " .. i .. " is well over the HQ cells")
				-- never a mission pocket (or the prologue's subway pocket)
				check(
					PocketLayout.at(Config, x, y + 3, z) == nil,
					"pocket " .. i .. " is not a mission pocket"
				)
				check(y > Config.Story.pockets.y + 1000, "pocket " .. i .. " is far over the mission pockets")
				-- the world's schedulers and robots skip it (as they skip every pocket)
				check(EventPlan.inPocket(Config.Events, y), "events skip pocket " .. i)
				check(y >= Config.Story.pockets.y - 100, "robots and PvP skip pocket " .. i)
			end
			-- the pockets themselves never touch (each a cell wide, a gap apart)
			check(P.gap >= H.cell.size + 40, "pockets are a whole cell apart")
			-- the HQ cells never land in a visit pocket either
			for slot = 1, maxSlots :: number do
				local x, y, z = HqRules.cell(Config, slot)
				check(
					VisitRules.pocketAt(Config, x, y + 3, z) == nil,
					"HQ cell " .. slot .. " is not a visit pocket"
				)
			end
			for i = 1, Config.Story.pockets.count + 1 do
				local x, y, z = PocketLayout.centre(Config, i)
				check(
					VisitRules.pocketAt(Config, x, y + 3, z) == nil,
					"mission pocket " .. i .. " is not a visit pocket"
				)
			end
			check(VisitRules.pocketAt(Config, 0, 40, 0) == nil, "the city is not a visit pocket")
			-- the lowest free pocket; none when all are taken
			local st = VisitRules.new()
			check(VisitRules.freeIndex(Config, st) == 1, "the first host gets pocket 1")
			for i = 1, P.count do
				st.hosts[i] = { index = i, visitors = { 99 } }
			end
			check(VisitRules.freeIndex(Config, st) == nil, "no pocket when every one is held")
			st.hosts[7] = nil
			check(VisitRules.freeIndex(Config, st) == 7, "a freed pocket is used again")
		end
	)

	test("WP12: asking, the owner's card, ACCEPT and NO", function()
		local st = VisitRules.new()
		local A = function(from, to, now, ctx)
			return VisitRules.ask(Config, st, from, to, now, ctx or ok())
		end
		check(select(2, A(OWNER, OWNER, 0)) == "self", "not your own HQ")
		check(select(2, A(VISITOR, OWNER, 0, { fromFree = false, toReady = true })) == "busy", "busy visitor")
		check(select(2, A(VISITOR, OWNER, 0, { fromFree = true, toReady = false })) == "new", "no HQ yet")
		-- your own mute or block: undo it first (you know about it)
		for _, k in { "fromMuted", "fromBlocked" } do
			local ctx = ok()
			ctx[k] = true
			check(select(2, A(VISITOR, OWNER, 0, ctx)) == "muted", k .. ": refused, undo it first")
		end
		-- a real ask: the owner gets the card
		local sent, why, deliver = A(VISITOR, OWNER, 0)
		check(sent and why == nil and deliver, "the ask is sent and shown")
		check(select(2, A(VISITOR, OWNER, 1)) == "pending", "asked already")
		check(select(2, A(VISITOR, OTHER, 1)) == "asking", "one open ask at a time")
		check(select(2, A(OTHER, OWNER, 1)) == "theirBusy", "the owner has one card at a time")
		-- the ask runs out
		check(VisitRules.pending(Config, st, VISITOR, V.askLife + 1) == nil, "the ask runs out after askLife")
		check(
			select(2, VisitRules.answer(Config, st, OWNER, VISITOR, true, V.askLife + 1, ok())) == "expired",
			"a late ACCEPT does nothing"
		)
		check(VisitRules.hostOf(st, VISITOR) == nil, "not visiting")
		-- NO: a wait before asking that owner again
		A(VISITOR, OWNER, 100)
		check(
			select(2, VisitRules.answer(Config, st, OWNER, VISITOR, false, 101, ok())) == "declined",
			"NO declines"
		)
		check(select(2, A(VISITOR, OWNER, 102)) == "wait", "a wait after NO")
		check((A(VISITOR, OTHER, 102)), "another owner can be asked at once")
		VisitRules.answer(Config, st, OTHER, VISITOR, false, 103, ok())
		check((A(VISITOR, OWNER, 101 + V.again + 1)), "after the wait it can be asked again")
		-- ACCEPT: the visitor is in the owner's HQ, pocket 1
		local t = 101 + V.again + 2
		local yes, reason = VisitRules.answer(Config, st, OWNER, VISITOR, true, t, ok())
		check(yes and reason == nil, "ACCEPT")
		check(VisitRules.hostOf(st, VISITOR) == OWNER, "visiting the owner")
		check(st.hosts[OWNER].index == 1, "in pocket 1")
		check(select(2, A(VISITOR, OTHER, t)) == "visiting", "leave this HQ before asking another")
		-- someone muted or blocked since the ask: as if it ran out
		A(OTHER, OWNER, t)
		local muted = ok()
		muted.toMuted = true
		check(
			select(2, VisitRules.answer(Config, st, OWNER, OTHER, true, t, muted)) == "expired",
			"muted since the ask"
		)
		check(VisitRules.hostOf(st, OTHER) == nil, "not let in")
		-- a second host takes pocket 2
		A(OTHER, VISITOR + 1, t)
		VisitRules.answer(Config, st, VISITOR + 1, OTHER, true, t, ok())
		check(st.hosts[VISITOR + 1].index == 2, "a second host, pocket 2")
	end)

	test("WP12: mutes, blocks and reports stop asks without telling the asker", function()
		for _, k in { "toMuted", "toBlocked" } do
			local st = VisitRules.new()
			local ctx = ok()
			ctx[k] = true
			local sent, why, deliver = VisitRules.ask(Config, st, VISITOR, OWNER, 0, ctx)
			check(sent and why == nil and not deliver, k .. ": 'sent', but the owner never sees it")
			check(
				select(2, VisitRules.ask(Config, st, VISITOR, OWNER, 0.5, ctx)) == "pending",
				k .. ": asking again reads as sent already"
			)
			check(
				select(2, VisitRules.answer(Config, st, OWNER, VISITOR, true, 1, ok())) == "expired",
				k .. ": a hidden ask can never be accepted"
			)
			check(VisitRules.hostOf(st, VISITOR) == nil, k .. ": not let in")
			-- a hidden ask never blocks a real one to the same owner
			local st2 = VisitRules.new()
			VisitRules.ask(Config, st2, VISITOR, OWNER, 0, ctx)
			check(
				(VisitRules.ask(Config, st2, OTHER, OWNER, 1, ok())),
				k .. ": a hidden ask never blocks others"
			)
		end
		-- a report on this server counts as a shun (GuardService.shuns), and never on its own
		local book = GuardRules.newReports()
		check(not GuardRules.reported(book, OWNER, VISITOR), "no report yet")
		GuardRules.report(Config, book, OWNER, VISITOR, 10)
		check(GuardRules.reported(book, OWNER, VISITOR), "the owner reported the visitor")
		check(not GuardRules.reported(book, VISITOR, OWNER), "one way only")
		local gs = fs.readFile("src/server/Services/GuardService.luau")
		check(string.find(gs, "function GuardService.shuns(a: Player, b: number)", 1, true) ~= nil, "shuns")
		check(
			string.find(gs, "GuardRules.reported(reports, a.UserId, b)", 1, true) ~= nil,
			"shuns reads reports"
		)
		check(string.find(gs, 'Net.on("GuardBlocks"', 1, true) ~= nil, "the device's blocks arrive")
		-- the server reads the save's mute list (SettingsRules) and the shuns both ways
		local vs = fs.readFile("src/server/Services/VisitService.luau")
		for _, s in
			{
				"table.find(profile.mutes, b.UserId)",
				"fromBlocked = GuardService.shuns(from, to.UserId)",
				"toBlocked = GuardService.shuns(to, from.UserId)",
				"toMuted = muted(to, from)",
				"fromMuted = muted(from, to)",
			}
		do
			check(string.find(vs, s, 1, true) ~= nil, "VisitService: " .. s)
		end
		-- a mute or block during a visit ends it (the 1 Hz sweep, and at once on a new block list)
		check(
			string.find(vs, "GuardService.blocksChanged = function()", 1, true) ~= nil,
			"a block ends a visit"
		)
		check(string.find(vs, "muted(trip.owner, player)", 1, true) ~= nil, "a mute ends a visit")
		-- the device sends its Roblox block list
		local hc = fs.readFile("src/client/Controllers/HqClient.luau")
		check(string.find(hc, 'StarterGui:GetCore("GetBlockedUserIds")', 1, true) ~= nil, "the block list")
		check(string.find(hc, 'Net.send("GuardBlocks", out)', 1, true) ~= nil, "sent to the server")
	end)

	test("WP12: leaving, KICK, a full HQ and players leaving the server", function()
		local st = VisitRules.new()
		local guests = {}
		for i = 1, V.max + 1 do
			table.insert(guests, 5000 + i)
		end
		for i = 1, V.max - 1 do
			VisitRules.ask(Config, st, guests[i], OWNER, i, ok())
			check((VisitRules.answer(Config, st, OWNER, guests[i], true, i, ok())), "visitor " .. i .. " in")
		end
		-- two asks open (the second hidden behind nothing: the owner muted no one, so it waits its turn)
		VisitRules.ask(Config, st, guests[V.max], OWNER, 10, ok())
		check((VisitRules.answer(Config, st, OWNER, guests[V.max], true, 10, ok())), "the last place taken")
		-- an ask made while there was room, accepted once the HQ is full
		st.asks[guests[V.max + 1]] = { to = OWNER, at = 10, hidden = false }
		local yes, why = VisitRules.answer(Config, st, OWNER, guests[V.max + 1], true, 11, ok())
		check(not yes and why == "full", "the HQ is full at " .. V.max)
		check(#VisitRules.visitors(st, OWNER) == V.max, V.max .. " visitors")
		check(
			select(2, VisitRules.ask(Config, st, guests[V.max + 1], OWNER, 100, ok())) == "full",
			"asking a full HQ"
		)
		-- LEAVE: the owner keeps the pocket while anyone is in
		local owner, empty = VisitRules.leave(st, guests[1])
		check(owner == OWNER and not empty, "one left, the pocket stays")
		check(VisitRules.hostOf(st, guests[1]) == nil, "gone")
		-- KICK: only the owner's own visitors, then a long wait
		check(not VisitRules.kick(Config, st, OTHER, guests[2], 200), "only the owner kicks")
		check(VisitRules.kick(Config, st, OWNER, guests[2], 200), "KICK")
		check(VisitRules.hostOf(st, guests[2]) == nil, "shown out")
		check(
			select(2, VisitRules.ask(Config, st, guests[2], OWNER, 200 + V.kicked - 1, ok())) == "wait",
			"kicked: wait"
		)
		check(V.kicked > V.again, "a kick waits longer than a NO")
		-- the host leaves the server: everyone goes home, the pocket is free
		local home = VisitRules.drop(st, OWNER)
		check(#home == V.max - 2, "the rest go home")
		for _, id in home do
			check(VisitRules.hostOf(st, id) == nil, "visitor " .. id .. " is out")
		end
		check(st.hosts[OWNER] == nil and VisitRules.freeIndex(Config, st) == 1, "the pocket is free again")
		-- a visitor leaves the server: the host's list, and the last one takes the pocket down
		VisitRules.ask(Config, st, VISITOR, OTHER, 300, ok())
		VisitRules.answer(Config, st, OTHER, VISITOR, true, 300, ok())
		local _, was = VisitRules.drop(st, VISITOR)
		check(was == OTHER and st.hosts[OTHER] == nil, "the last visitor gone, the host's pocket is free")
		-- open asks to and from a player who left are gone
		VisitRules.ask(Config, st, OTHER, OWNER, 400, ok())
		VisitRules.drop(st, OWNER)
		check(st.asks[OTHER] == nil, "an ask to someone who left is gone")
	end)

	test("WP12: the visitor's copy is the owner's HQ as they see it, read-only", function()
		-- an owner's HqState packet as HqService.view builds it, with a WANTED poster and two heads
		local c = ProfileSchema.newCharacter("hero", "Powerhouse")
		local f = NemesisMath.fresh(Config.Nemesis, OWNER, "hero")
		for k, v in f do
			c.mmo.nemesis[k] = v
		end
		local poster = WantedRules.poster(Config.Nemesis, OWNER, "hero", 30, c.mmo, 1000)
		local heads = WantedRules.heads(Config.Nemesis, OWNER, "hero", c.mmo)
		local view = {
			on = true,
			cell = { 9000, 5200, 9000 },
			side = "hero",
			name = H.names.hero,
			level = 4,
			upgrade = 50000,
			mannequins = 4,
			trophySlots = 12,
			bossSim = true,
			mvpCards = true,
			drones = false,
			dronesPerMinute = 0,
			dummies = { { id = 50001, x = 1, y = 2, z = 3 }, { id = 50002, x = 4, y = 5, z = 6 } },
			canRetire = true,
			earned = { 1, 2, 5 },
			trophies = { 1, 5 },
			statues = { { name = "Old Hero", level = 50, rank = 1 } },
			props = { 2, 3 },
			sim = { x = 0, y = 0, z = 0, id = 50003 },
			repTier = 3,
			wanted = poster,
			heads = heads,
		}
		local copy = VisitRules.readOnly(view, { owner = OWNER, name = "Captain Spark" })
		check(
			copy.on and copy.visit and copy.visit.owner == OWNER and copy.visit.name == "Captain Spark",
			"visit"
		)
		-- the look, as the owner sees it
		for _, k in { "cell", "side", "name", "level", "trophySlots", "statues", "props", "repTier" } do
			check(copy[k] == view[k], "kept: " .. k)
		end
		check(copy.wanted == poster and copy.heads == heads, "the WANTED poster and heads as the owner's")
		check(#copy.trophies == 2 and copy.trophies[2] == 5, "the trophy wall as picked")
		check(copy.trophies ~= view.trophies, "a copy of the picks, never the save's own list")
		-- nothing that acts
		for _, k in
			{
				"upgrade",
				"mannequins",
				"bossSim",
				"mvpCards",
				"drones",
				"dronesPerMinute",
				"canRetire",
				"earned",
				"sim",
			}
		do
			check(copy[k] == nil, "dropped: " .. k)
		end
		check(#copy.dummies == 2, "the dummies stand as decor")
		for _, d in copy.dummies do
			check(d.id == 0, "a decor dummy has no target id")
		end
		-- only the exit works for a visitor
		for name in H.stations do
			check(
				VisitRules.allowed(name) == (name == "exit"),
				name .. (if name == "exit" then " works" else " is the owner's")
			)
		end
		check(not VisitRules.allowed("wanted"), "the poster's panel is the owner's")
		-- the server builds the copy from the owner's save through the same view as the owner's own HQ
		local hs = fs.readFile("src/server/Services/HqService.luau")
		check(
			string.find(hs, "function HqService.view(player: Player, hero: any, centre: Vector3)", 1, true)
				~= nil,
			"view"
		)
		check(
			string.find(hs, "local packet = HqService.view(player, v.hero, v.centre)", 1, true) ~= nil,
			"the owner's own HQ uses it"
		)
		local vs = fs.readFile("src/server/Services/VisitService.luau")
		check(
			string.find(vs, "HqService.view(trip.owner, hero, pocket.centre)", 1, true) ~= nil,
			"the copy uses it"
		)
		check(string.find(vs, "VisitRules.readOnly(view,", 1, true) ~= nil, "read-only")
		check(string.find(vs, 'local SCENE = "hqVisit"', 1, true) ~= nil, "visitors are in a scene")
		-- the stations only ever answer the owner in their own cell (HqService's visits table)
		for _, fn in { "upgrade", "lookSave", "lookWear", "trophies", "bossSim", "retire" } do
			local body = string.match(hs, "local function " .. fn .. "%(player: Player[^\n]*\n(.-)\nend\n")
			check(
				body ~= nil and string.find(body, "inside(player)", 1, true) ~= nil,
				fn .. " needs your own HQ"
			)
		end
		check(
			string.find(hs, "if visits[player] and c then", 1, true) ~= nil,
			"the command table's board too"
		)
		-- no shop or creator for visitors (both need your own HQ, a safehouse or no scene)
		check(
			has("src/server/Services/CreatorService.luau", 'if hero.scene and hero.scene ~= "hq" then'),
			"creator"
		)
		check(has("src/server/Services/PurchaseService.luau", "if hero.scene then"), "Robux shop")
		check(not string.find(vs, "EnemyService", 1, true), "no robots or loot in a visit")
		-- the device: no prompts but the exit, the poster has none, decor dummies are never aimed at
		local hc = fs.readFile("src/client/Controllers/HqClient.luau")
		check(string.find(hc, "if visiting and not VisitRules.allowed(name) then", 1, true) ~= nil, "pads")
		check(
			string.find(hc, 'Net.send(if state.visit then "HqVisitLeave" else "HqLeave")', 1, true) ~= nil,
			"exit"
		)
		check(string.find(hc, "if not state.visit and (d.id or 0) > 0 then", 1, true) ~= nil, "decor dummies")
		check(has("src/client/Controllers/GuideClient.luau", "and not state.visit"), "no Lodestar in a copy")
	end)

	test("WP12: hq_visit analytics stays inside the event budget", function()
		local E = AnalyticsSchema.EVENTS.hq_visit
		check(E ~= nil and #E == 3, "hq_visit: side, cross, visitors")
		check(Config.Analytics.lowPriority.hq_visit == nil, "never dropped as busy")
		local st = VisitRules.new()
		local value, fields = VisitRules.event(Config, st, VISITOR, 0, "hero", "villain", 2, 4)
		local good, clean = AnalyticsSchema.check("hq_visit", fields)
		check(
			value == 4 and good and clean[1] == "hero" and clean[2] == "cross" and clean[3] == "2",
			"fields"
		)
		check(
			select(2, VisitRules.event(Config, st, OTHER, 0, "hero", "hero", 1, 1))[2] == "same",
			"same side"
		)
		check(
			VisitRules.event(Config, st, VISITOR, V.logEvery - 1, "hero", "hero", 1, 1) == nil,
			"once a minute"
		)
		check(VisitRules.event(Config, st, VISITOR, V.logEvery, "hero", "hero", 1, 1) ~= nil, "then again")
		-- the worst case: every player visits once a minute, under each player's share of the budget
		local B = Config.Analytics.budget
		check(60 / V.logEvery <= B.perPlayer * 0.1, "at most 10% of a player's share of the budget")
		check(
			has(
				"src/server/Services/VisitService.luau",
				'Analytics.event(visitor, "hq_visit", value, fields)'
			),
			"logged"
		)
	end)

	test("WP12: rate-limited remotes with no text in them", function()
		for _, name in { "HqVisitAsk", "HqVisitAnswer", "HqVisitLeave", "HqVisitKick", "GuardBlocks" } do
			local R = Remotes[name]
			check(R ~= nil and R.dir == "C2S" and R.schema ~= nil, name .. " is client to server")
			check((R.rate :: number) <= 1 and (R.burst :: number) <= 3, name .. " is rate-limited")
			for _, spec in R.schema :: any do
				check(spec.t ~= "string" and spec.t ~= "any", name .. ": no text or free values")
			end
		end
		check((Remotes.HqVisitAsk.rate :: number) <= 0.5, "asks at most one every 2 s")
		for _, name in { "HqVisitAsked", "HqVisitors" } do
			check(Remotes[name] and Remotes[name].dir == "S2C", name .. " is server to client")
		end
		local ask = Remotes.HqVisitAsk.schema :: any
		check(NetSchema.validate(ask, { 12345 }, 1), "a user id")
		check(not NetSchema.validate(ask, { "12345" }, 1), "never a string")
		check(not NetSchema.validate(ask, { 0 }, 1), "never 0")
		local ans = Remotes.HqVisitAnswer.schema :: any
		check(
			NetSchema.validate(ans, { 12345, 1 }, 2) and not NetSchema.validate(ans, { 12345, 2 }, 2),
			"0 or 1"
		)
		local blocks = Remotes.GuardBlocks.schema :: any
		check(NetSchema.validate(blocks, { { 0 } }, 1), "{ 0 }: no blocks")
		local many = {}
		for i = 1, 201 do
			many[i] = i
		end
		check(not NetSchema.validate(blocks, { many }, 1), "at most 200 blocks")
		-- every remote has its handler or listener
		local vs = fs.readFile("src/server/Services/VisitService.luau")
		for _, name in { "HqVisitAsk", "HqVisitAnswer", "HqVisitLeave", "HqVisitKick" } do
			check(string.find(vs, 'Net.on("' .. name .. '"', 1, true) ~= nil, name .. " handled")
		end
		local hc = fs.readFile("src/client/Controllers/HqClient.luau")
		for _, name in { "HqVisitAsked", "HqVisitors" } do
			check(string.find(hc, 'Net.listen("' .. name .. '"', 1, true) ~= nil, name .. " listened to")
		end
		-- boots after the services it uses
		local init = fs.readFile("src/server/init.server.luau")
		local at = string.find(init, 'boot("VisitService", VisitService.init)', 1, true)
		check(at ~= nil, "VisitService boots")
		for _, before in { "HqService", "GuardService", "FlagService" } do
			local b = string.find(init, 'boot("' .. before .. '"', 1, true)
			check(b ~= nil and at ~= nil and b < at, "after " .. before)
		end
	end)

	test("WP12: fixed text only, and every reason has a line", function()
		local reasons = {
			"self",
			"visiting",
			"busy",
			"new",
			"muted",
			"pending",
			"asking",
			"wait",
			"full",
			"theirBusy",
			"expired",
			"gone",
		}
		for _, k in reasons do
			check(type(V.reasons[k]) == "string" and #V.reasons[k] > 0, "a line for " .. k)
		end
		-- every reason VisitRules returns has its line
		local src = fs.readFile("src/shared/VisitRules.luau")
		for k in string.gmatch(src, 'return false, "(%w+)"') do
			check(V.reasons[k] ~= nil or k == "declined", "VisitRules' reason " .. k .. " has a line")
		end
		for k, t in V.text do
			local _, n = string.gsub(t, "%%", "")
			check(n == 0 or (n == 1 and string.find(t, "%s", 1, true) ~= nil), k .. ": at most one name")
		end
		check(string.find(V.reasons.full, tostring(V.max), 1, true) ~= nil, "the full line says " .. V.max)
		check(
			VisitRules.line(Config, "asked", "Captain Spark") == "Captain Spark wants to visit your HQ",
			"asked"
		)
		check(VisitRules.line(Config, "wait") == V.reasons.wait, "a reason")
		check(VisitRules.line(Config, "nonsense") == V.reasons.busy, "an unknown key reads as busy")
		-- the device shows fixed lines; the server sends keys and names, never typed text
		check(
			has("src/client/Ui/Toasts.luau", "VisitRules.line(Config, key, data.name)"),
			"Toasts draws the line"
		)
		local vs = fs.readFile("src/server/Services/VisitService.luau")
		check(
			not string.find(vs, "TextBox", 1, true) and not string.find(vs, "fireAll", 1, true),
			"no text, no broadcast"
		)
		check(has("src/client/Ui/SquadHud.luau", "HqClient.visit(userId)"), "VISIT on the squad list")
		check(has("src/client/Ui/SquadHud.luau", "HqClient.kickVisitor(v.userId)"), "KICK on the visitors")
		check(
			has("src/client/Ui/SquadHud.luau", 'Kit.dock(leaveButton, "VisitLeave", 0)'),
			"LEAVE HQ in the top row"
		)
	end)

	local placePath = T.placePath
	if not placePath then
		return
	end

	test(
		"WP12: the visit card, the SQUAD panel's VISIT, KICK and LEAVE HQ fit phones, tablets and PCs",
		function()
			local roblox = require("@lune/roblox")
			local UiSim = require("./uisim")
			local trees = UiSim.load(roblox.deserializePlace(fs.readFile(placePath)))
			local P = Config.Ui.phone
			local LONG = "WWWWWWWWWWWWWWWWWWWW" -- a 20-character display name (the visitors, the card)
			local HERO = "Captain Thunderbolt" -- a long hero name (the squad, whose list under the radar is M10's)
			local devices = {
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
				{ name = "iPad", w = 1024, h = 768, top = 58, left = 0, right = 0, bottom = 0, touch = true },
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
			for _, d in devices do
				local sim = UiSim.new(trees, d)
				sim:run("InputController", sim:require("Client.Controllers.InputController").init)
				local M = {}
				for _, m in { "Hud", "Toasts", "Radar", "SquadHud", "HqHud" } do
					M[m] = sim:require("Client.Ui." .. m)
					sim:run(m, M[m].init)
				end
				local HqClient = sim:require("Client.Controllers.HqClient")
				local SquadClient = sim:require("Client.Controllers.SquadClient")
				local base = { minTap = P.minTap, minText = P.minText, safe = true, textOverlap = true }
				local function report(tag: string, opts: { [string]: any })
					local o = table.clone(base)
					for k, v in opts do
						o[k] = v
					end
					for _, issue in sim:issues(o) do
						check(false, d.name .. " WP12 " .. tag .. ": " .. issue)
					end
				end
				-- a full squad you lead, 4 visitors in your HQ, and you visiting someone else
				check(
					sim:run("visit state", function()
						SquadClient.state = {
							leader = 1,
							members = {
								{ userId = 1, name = HERO, level = 50, classId = "Powerhouse", slot = 1 },
								{ userId = 2, name = HERO, level = 50, classId = "Powerhouse", slot = 2 },
								{ userId = 3, name = HERO, level = 50, classId = "Powerhouse", slot = 3 },
								{ userId = 4, name = HERO, level = 50, classId = "Powerhouse", slot = 4 },
							},
						}
						HqClient.visitors = {}
						for i = 1, V.max do
							table.insert(HqClient.visitors, { userId = 10 + i, name = LONG })
						end
						local s = HqClient.state()
						s.on = true
						s.visit = { owner = 2, name = LONG }
						SquadClient.Changed:Fire()
						HqClient.VisitorsChanged:Fire()
					end),
					d.name .. ": the visit state draws"
				)
				local g = sim.playerGui:FindFirstChild("Squad")
				check(g ~= nil, d.name .. ": Squad screen")
				-- the HUD's squad list under the radar is M10's (phone_test checks it); these checks are WP12's parts
				local squadList = g and g:FindFirstChild("SquadList")
				if squadList then
					squadList.Visible = false
				end
				check(sim:run("SquadHud.open", M.SquadHud.open), d.name .. ": the SQUAD panel opens")
				report("SQUAD panel", { minList = 90, minOrder = g and g.DisplayOrder })
				sim:run("SquadHud.close", M.SquadHud.close)
				-- the owner's card
				check(
					sim:run("visit card", function()
						HqClient.VisitAsked:Fire({ from = 11, name = LONG, life = V.askLife })
					end),
					d.name .. ": the visit card shows"
				)
				local card = g and g:FindFirstChild("VisitCard")
				check(card ~= nil and card.Visible, d.name .. ": the visit card is up")
				report("visit card", { only = { Squad = true } })
				-- LEAVE HQ in the top row
				local leave = nil
				for _, c in sim.playerGui:GetDescendants() do
					if c.Name == "VisitLeave" then
						leave = c
					end
				end
				check(leave ~= nil and leave.Visible, d.name .. ": LEAVE HQ is in the top row while visiting")
				report("top row with LEAVE HQ", { only = { Dock = true } })
				-- NO closes the card
				local no = nil
				for _, c in (card :: any):GetChildren() do
					if c:IsA("TextButton") and c.Text == V.text.no then
						no = c
					end
				end
				check(no ~= nil, d.name .. ": the card has NO")
				if no then
					sim:tap(no)
					check(not (card :: any).Visible, d.name .. ": NO puts the card away")
				end
				for _, e in sim.errors do
					check(false, d.name .. ": " .. tostring(e))
				end
			end
		end
	)
end
