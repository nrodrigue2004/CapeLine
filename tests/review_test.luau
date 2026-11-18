-- The seams review (2026-11-18, own file): tonight's packages were built in parallel and merged one by one, so
-- these check where they meet. Each test failed before its fix (Decisions, "review"). Pure rules run here; the
-- services and devices are checked by their source, as the other audits do. Called from tests/run.luau:
--   require("./review_test")({ test = test, check = check, Config = Config })
-- ONLY="Review" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local Travel = require("../src/shared/Travel")
	local BoardKeys = require("../src/shared/BoardKeys")

	local function source(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	-- the text from a header to the first `close` after it: "\nend\n" for a top-level function, "\n\tend)\n" for a
	-- handler inside an init
	local function body(text: string, header: string, close: string?): string
		local at = string.find(text, header, 1, true)
		if not at then
			return ""
		end
		local stop = string.find(text, close or "\nend\n", at, true) or #text
		return string.sub(text, at, stop)
	end

	test("Review: no fast travel out of a scene (a friend's HQ, your HQ, a pocket, the prologue)", function()
		-- a visitor who flew out of a friend's HQ copy stood in the city still in the "hqVisit" scene: no robots,
		-- incidents, PvP, missions or side quests until the host left (the HQ and mission pockets the same)
		local W = Config.World
		local mask = Travel.add(0, 3)
		local base = { beacons = mask, inCombat = false, traveling = false, readyAt = 0, now = 100 }
		check((Travel.canTravel(W, base, 3)), "out in the city: fine")
		for _, scene in { "hqVisit", "hq", "mission", "opening", "creator" } do
			local s = table.clone(base) :: any
			s.scene = scene
			local ok, why = Travel.canTravel(W, s, 3)
			check(not ok and why == "scene", scene .. ": refused")
		end
		local beacon = source("src/server/Services/BeaconService.luau")
		check(has(beacon, "scene = hero.scene"), "BeaconService passes the hero's scene")
		local client = source("src/client/Controllers/TravelClient.luau")
		check(string.match(client, '\n\tscene = "[^"]+"') ~= nil, "the map says why")
	end)

	test("Review: a dressed villain leaves no robot wreck", function()
		-- WP6's wrecks listened to EnemyService.Killed for every kind; a side quest finale villain or WP5's
		-- Suspicious Hero costume (a person in its suit kind's rig) left that robot's heap. The Rogues File already
		-- skipped them (EnemyService.identity dress), so the wreck now does too.
		local throw = source("src/server/Services/ThrowService.luau")
		local hook = body(throw, "EnemyService.Killed:Connect(function(", "\n\tend)\n")
		check(hook ~= "", "ThrowService hooks Killed")
		check(has(hook, "enemyId"), "it reads the robot's id")
		check(has(hook, "EnemyService.identity(enemyId)"), "it looks up the identity")
		check(has(hook, "ident.dress"), "a dressed one leaves no wreck")
		local es = source("src/server/Services/EnemyService.luau")
		local fire = string.find(
			es,
			"EnemyService.Killed:Fire(ev.kind, ev.by, Vector3.new(ev.x, ev.y, ev.z), ev.e)",
			1,
			true
		)
		local forget = fire and string.find(es, "forgetIdent(ev.e)", fire, true)
		check(fire ~= nil and forget ~= nil, "the id goes with Killed and the identity outlives it")
		local dressed = 0
		local FakeRules = require("../src/shared/FakeRules")
		for _, set in { Config.SideQuests.dress or {}, (Config.Incidents :: any).dress or {} } do
			for id in set do
				local d = FakeRules.dress(Config, id)
				check(d ~= nil and d.dress == true, id .. ": reads dress = true")
				dressed += 1
			end
		end
		check(dressed > 0, "dresses were checked")
	end)

	test("Review: a daily PvP quest counts only a PvP win that paid", function()
		-- DailyService counted every PvP defeat, so two friends trading defeats (refused by the anti-farming
		-- ledger: no pay, no Fame, no board) could finish a paid daily quest. Off at launch (Config.Daily.pvp).
		local daily = source("src/server/Services/DailyService.luau")
		check(has(daily, "DeathService.PvpWon:Connect"), "reads PvpWon")
		check(not has(daily, "DeathService.PvpDefeat:Connect"), "not every defeat")
		local deaths = source("src/server/Services/DeathService.luau")
		local paid = string.find(deaths, "if fame > 0 then", 1, true)
		local won = paid and string.find(deaths, "DeathService.PvpWon:Fire", paid, true)
		check(won ~= nil, "PvpWon fires only for a win that paid")
	end)

	test("Review: every card the server pops waits its turn (PopupGate)", function()
		-- the episode's comic panels came 6 s after joining (PassService), over the creator on a first join;
		-- the starter offer and Roblox's favorite prompt both follow the first world boss win and stacked
		local pass = source("src/client/Ui/PassHud.luau")
		check(has(pass, 'PopupGate.later("episode"'), "the episode's panels wait")
		check(has(pass, 'PopupGate.card("episode"'), "and count as a card while up")
		local state = body(pass, 'Net.listen("PassState"', "\n\tend)\n")
		check(
			state ~= "" and not has(state, "\n\t\tPassHud.intro(false)\n"),
			"PassState never opens them at once"
		)
		local shop = source("src/client/Ui/ShopHud.luau")
		local offer = body(shop, 'Net.listen("ShopOffer"', "\n\tend)\n")
		check(has(offer, 'PopupGate.later("starter"'), "the starter offer waits")
		check(has(offer, 'PopupGate.card("starter"'), "and counts as a card")
		local fav = source("src/client/Controllers/FavoritePrompt.luau")
		local quiet = body(fav, "function FavoritePrompt.quiet")
		check(has(quiet, "PopupGate.free()"), "Roblox's favorite prompt waits for the cards")
		-- no require loop at load: the gate reads the main menu, which reads the shop
		local gate = source("src/client/Ui/PopupGate.luau")
		check(has(gate, "require(script.Parent.MainMenu)"), "(the gate reads the main menu)")
		check(
			not has(string.sub(shop, 1, (string.find(shop, "local ShopHud = {}", 1, true) or 1)), "PopupGate"),
			"the shop requires the gate only when the offer comes"
		)
	end)

	test("Review: board_open is paced, so one device never spends the event budget", function()
		-- BoardOpen allows one a second; each logged board_open (a high-priority event), so a device flipping
		-- tabs could send 60 a minute: 3x a player's whole share of the per-minute budget
		local B = Config.Boards
		check(type(B.logEvery) == "number" and B.logEvery >= 30, "a pace")
		local last = {}
		local logged, worst = 0, 0
		local perMinute: { [number]: number } = {}
		local combos = 2 * #B.boards
		for t = 0, 599 do -- 10 minutes at the remote's full rate, round every board and filter
			local k = t % combos
			if BoardKeys.logOpen(B, last, k // 2 + 1, k % 2, t) then
				logged += 1
				local m = t // 60
				perMinute[m] = (perMinute[m] or 0) + 1
				worst = math.max(worst, perMinute[m])
			end
		end
		check(worst <= combos, "at most one per board and filter a minute (" .. worst .. ")")
		check(
			worst <= Config.Analytics.budget.perPlayer * 0.5,
			"under half of a player's share of the budget (" .. worst .. ")"
		)
		check(BoardKeys.logOpen(B, {}, 1, 0, 0), "a first look always logs")
		local svc = source("src/server/Services/BoardService.luau")
		check(has(svc, "BoardKeys.logOpen(B, last, index, filterNum, os.clock())"), "BoardService paces it")
		check(has(svc, "opened[player] = nil"), "and forgets a leaver")
	end)

	test("Review: a friend's HQ copy redraws when the owner changes out in the city", function()
		-- HqService tells ownerChanged only from inside the owner's own HQ; a level (the poster opens at 8), new
		-- city props (StoryService.Changed) or a nemesis met or beaten (the poster, a new head) left visitors
		-- looking at the old copy
		local vs = source("src/server/Services/VisitService.luau")
		for _, hook in
			{
				"HeroService.Leveled:Connect",
				"StoryService.Changed:Connect(redraw)",
				"NemesisService.Met:Connect(redraw)",
				"NemesisService.Won:Connect(redraw)",
			}
		do
			check(has(vs, hook), "VisitService: " .. hook)
		end
		local redraw = body(vs, "local function redraw(owner: Player)")
		check(has(redraw, "not pockets[owner.UserId]"), "only an owner with visitors redraws")
		local hq = source("src/server/Services/HqService.luau")
		check(has(hq, "WantedRules.poster("), "the copy is HqService.view (the poster from the save)")
	end)

	test("Review: a slot switch or a Legacy retire is not a new analytics session", function()
		-- CreatorService (slot switch) and HqService (Legacy) fire DataService.Loaded again so every service takes
		-- the new character; AnalyticsHooks took it as a join: a second FunnelKit session (session_start, the
		-- sessions count), the play time so far dropped (FunnelKit.join resets placeAt) and session_device again
		for _, path in { "src/server/Services/CreatorService.luau", "src/server/Services/HqService.luau" } do
			check(has(source(path), "DataService.Loaded:Fire(player, profile)"), path .. " re-fires Loaded")
		end
		local hooks = source("src/server/Services/AnalyticsHooks.luau")
		local joined = body(hooks, "local function joined(player: Player, profile: any)")
		local guard = string.find(joined, "if sessionOn[player] then", 1, true)
		local session = string.find(joined, "Analytics.session(", 1, true)
		local join = string.find(joined, "funnels:join(", 1, true)
		check(
			guard ~= nil and session ~= nil and join ~= nil,
			"joined has the guard, the session and the join"
		)
		check(guard ~= nil and session ~= nil and guard < session, "the guard comes before the session start")
		check(has(hooks, "sessionOn[p] = nil"), "a leave forgets it, so the next join is a session")
		local FunnelKit = require("../src/shared/FunnelKit")
		local kit = source("src/shared/FunnelKit.luau")
		check(
			has(body(kit, "function FunnelKit.join("), "save.sessions += 1"),
			"(FunnelKit.join counts a session)"
		)
		check(FunnelKit.join ~= nil, "FunnelKit.join")
	end)

	test("Review: a rare event the budget refused waits for the next flush", function()
		-- with tonight's join events (8 a player) a filling server's minute ran out of room and dropped rare
		-- events for good, once-per-account ones too (the busy-minute sim in Audit analytics shows it: 937/1019)
		local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
		local q = {}
		for i = 1, AnalyticsSchema.HELD_MAX do
			check(AnalyticsSchema.hold(q, i), "held " .. i)
		end
		check(not AnalyticsSchema.hold(q, 0), "a full list says so (the caller gets full)")
		local room, out = 3, {}
		local n = AnalyticsSchema.release(q, function(): boolean
			room -= 1
			return room >= 0
		end, function(item)
			table.insert(out, item)
		end)
		check(
			n == 3 and out[1] == 1 and out[3] == 3 and #q == AnalyticsSchema.HELD_MAX - 3,
			"oldest first, while room"
		)
		local an = source("src/server/Services/Analytics.luau")
		local event = body(an, "function Analytics.event(")
		check(
			has(event, "AnalyticsSchema.hold(q, { name, value, clean })"),
			"Analytics.event holds a rare one"
		)
		check(has(event, "if not low then"), "never a busy (low) one: those are trimmed on purpose")
		local flush = body(an, "function Analytics.flush(")
		check(has(flush, "AnalyticsSchema.release(q"), "flush sends them")
		check(has(an, "held[p] = nil"), "a leaver's list is dropped")
		local hooks = source("src/server/Services/AnalyticsHooks.luau")
		check(has(hooks, "Analytics.flush(p)"), "AnalyticsHooks flushes every few seconds")
		-- the Rogues File's own queue lets a held page go (it waits in Analytics now, never twice)
		local rf = source("src/shared/RoguesFile.luau")
		check(has(rf, 'if send(q[1], q[2]) == "full" then'), "the Rogues queue keeps only a full refusal")
	end)
end
