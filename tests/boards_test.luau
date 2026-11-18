-- WP2 weekly boards tests (gap check G2; Config.Boards, Shared.BoardKeys, BoardService, BoardHud): the weekly
-- keys, ranking and ties, the rows, the write batch's budget (30 players for 10 minutes), the reward claimed
-- once, the hooks, and no free text anywhere on the boards.
-- Called from tests/run.luau: require("./boards_test")(test, check, Config)

local fs = require("@lune/fs")

local BoardKeys = require("../src/shared/BoardKeys")
local PassRules = require("../src/shared/PassRules")
local BadgeRules = require("../src/shared/BadgeRules")
local ProfileSchema = require("../src/shared/ProfileSchema")
local Remotes = require("../src/shared/Remotes")
local AnalyticsSchema = require("../src/shared/AnalyticsSchema")

local function src(path: string): string
	return fs.readFile(path)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return function(test: (string, () -> ()) -> (), check: (boolean, string) -> (), Config: any)
	local B = Config.Boards

	test("Boards (WP2): weekly keys from the PassRules week", function()
		-- Monday 2026-11-30 00:00 UTC starts week 2970 (Config.Pass.startWeek's Monday)
		local monday = 1795996800
		check(
			BoardKeys.week(monday) == 2970,
			"2026-11-30 is week 2970 (got " .. BoardKeys.week(monday) .. ")"
		)
		check(BoardKeys.week(monday - 1) == 2969, "the Sunday before is the week before")
		check(BoardKeys.weekStart(2970) == monday, "the week starts Monday 00:00 UTC")
		check(BoardKeys.weekEnd(2970) == monday + 7 * 86400, "and ends a week later")
		for _, t in { monday, monday + 3600, monday + 5 * 86400 + 77, os.time() } do
			check(
				BoardKeys.week(t) == PassRules.week(t),
				"the same week as the Hero Pass and the seed at " .. t
			)
			check(BoardKeys.weekEnd(BoardKeys.week(t)) == PassRules.weekEnds(t), "the same week end at " .. t)
		end
		check(BoardKeys.storeName(B, 2970) == "Weekly_2970", "the spec's store name Weekly_<week>")
		check(BoardKeys.entryKey(123456789) == "123456789", "entries keyed by user id")
		check(
			BoardKeys.jobKey(2970, "Rescues", 7) == "2970:Rescues:7",
			"one write job per week, board and player"
		)
		-- the boards: the spec's three, unique ids and titles, title ids in their own range
		local ids, titles = {}, {}
		for i, b in B.boards do
			check(not ids[b.id] and not titles[b.title], "unique board " .. b.id)
			ids[b.id], titles[b.title] = true, true
			check(BoardKeys.index(B, b.id) == i and BoardKeys.board(B, b.id) == b, "find " .. b.id)
			check(b.name ~= "" and b.unit ~= "" and b.units ~= "", b.id .. " has its words")
		end
		check(
			ids.BossMvp and ids.Rescues and ids.PvpWins,
			"boss MVPs, rescues and PvP wins (the spec's boards)"
		)
		check(BoardKeys.board(B, "Nope") == nil, "an unknown board is nothing")
		local maxRep = Config.Remembers.titleBase + 10 * 2 + 9
		check(
			B.titleBase > maxRep and B.titleBase + #B.boards < 65535,
			"title ids above the rep titles, under TitleSet's cap"
		)
		-- the board titles never reuse another title's name
		local others = {}
		for name in Config.Story.unlocks.titles do
			others[name] = true
		end
		for _, t in Config.Pass.titles do
			others[t] = true
		end
		for _, e in BadgeRules.list(Config.Badges) do
			others[e.name] = true
		end
		for _, list in Config.Remembers.titles do
			for _, t in list do
				others[t] = true
			end
		end
		for _, b in B.boards do
			check(not others[b.title], "a title of its own: " .. b.title)
		end
		-- the save keeps at most 200 counters (ProfileSchema repair): the badges' keys and ours fit
		local keys = {}
		for _, e in BadgeRules.list(Config.Badges) do
			keys[e.key] = true
		end
		local n = 0
		for _ in keys do
			n += 1
		end
		for _, k in BoardKeys.saveKeys(B) do
			check(#k <= 40 and not keys[k], "a save key of its own, 40 characters at most: " .. k)
			n += 1
		end
		check(n <= 150, "badge and board counters leave room under the save's 200 (" .. n .. ")")
	end)

	test("Boards (WP2): ranking, ties and rows", function()
		local entries = BoardKeys.sort({
			{ userId = 30, value = 5 },
			{ userId = 10, value = 9 },
			{ userId = 20, value = 5 },
			{ userId = 40, value = 2 },
			{ userId = 50, value = 5 },
		})
		check(entries[1].userId == 10, "the highest total first")
		check(
			entries[2].userId == 20 and entries[3].userId == 30 and entries[4].userId == 50,
			"ties by user id"
		)
		local r = BoardKeys.ranks(entries)
		check(
			r[1] == 1 and r[2] == 2 and r[3] == 2 and r[4] == 2 and r[5] == 5,
			"ties share a rank (1, 2, 2, 2, 5)"
		)
		check(BoardKeys.rankOf(entries, 50) == 2 and BoardKeys.rankOf(entries, 40) == 5, "rankOf")
		check(BoardKeys.rankOf(entries, 99) == nil, "not on the board: no rank")
		check(BoardKeys.rankOf({ { userId = 1, value = 0 } }, 1) == nil, "a zero never ranks")
		-- all: top count, your own row pinned with your rank
		local list, mine = BoardKeys.rows(entries, 30, 5, {}, "all", 3)
		check(#list == 3, "at most count rows")
		check(
			list[3].userId == 30 and list[3].me and list[3].rank == 2,
			"you in the list, at your shared rank"
		)
		check(mine ~= nil and mine.rank == 2 and mine.value == 5, "your pinned row")
		local _, past = BoardKeys.rows(entries, 40, 2, {}, "all", 3)
		check(past ~= nil and past.rank == 5, "past the shown rows you still see your rank")
		local _, fresh = BoardKeys.rows(entries, 40, 4, {}, "all", 3)
		check(fresh ~= nil and fresh.value == 4, "your newer total from the save shows over a cached read")
		local _, unread = BoardKeys.rows(entries, 77, 3, {}, "all", 50)
		check(
			unread ~= nil and unread.rank == nil and unread.value == 3,
			"not in what was read: no rank, your total"
		)
		local _, none = BoardKeys.rows(entries, 77, 0, {}, "all", 50)
		check(none == nil, "nothing this week: no row")
		-- friends: only friends and you, ranked among yourselves
		local fl, fm = BoardKeys.rows(entries, 40, 2, { [30] = true, [50] = true }, "friends", 50)
		check(
			#fl == 3 and fl[1].userId == 30 and fl[2].userId == 50 and fl[3].userId == 40,
			"friends and you"
		)
		check(fl[1].rank == 1 and fl[2].rank == 1 and fl[3].rank == 3, "ranked among friends, ties shared")
		check(fl[1].friend and not fl[3].friend and fl[3].me, "friend and me marks")
		check(fm ~= nil and fm.rank == 3, "your pinned rank among friends")
		local el = BoardKeys.rows(entries, 77, 0, {}, "friends", 50)
		check(#el == 0, "no friends on the board: the empty state")
		-- zeros never show
		local zl = BoardKeys.rows({ { userId = 1, value = 0 } }, 2, 0, {}, "all", 50)
		check(#zl == 0, "a zero total is not a row")
		-- the plaza redraws only on a change
		local a = BoardKeys.digest({ { { rank = 1, name = "A", value = 3 } }, {} })
		local b = BoardKeys.digest({ { { rank = 1, name = "A", value = 3 } }, {} })
		local c = BoardKeys.digest({ { { rank = 1, name = "A", value = 4 } }, {} })
		check(a == b and a ~= c, "the plaza digest changes only with the rows")
	end)

	test("Boards (WP2): the batching budget: 30 players for 10 minutes", function()
		local batch = BoardKeys.newBatch()
		local present: { [number]: boolean } = {}
		for id = 1, 30 do
			present[id] = true
		end
		local totals: { [string]: number } = {}
		local lastAt: { [string]: number } = {}
		local log: { { t: number, players: number } } = {}
		local events, writes, fails = 0, 0, 0
		local spacingOk, budgetOk, hardOk = true, true, true
		local seed = 12345
		local function rand(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local week = 2970
		local function count(): number
			local n = 0
			for _ in present do
				n += 1
			end
			return n
		end
		local function run(now: number, all: boolean?)
			local players = count()
			for _, j in BoardKeys.due(B, batch, now, players, all) do
				local k = BoardKeys.jobKey(j.week, j.board, j.userId)
				local gap = if j.urgent or all then B.keyGap else B.writeEvery
				if lastAt[k] and now - lastAt[k] < gap - 1e-9 then
					spacingOk = false
				end
				lastAt[k] = now
				writes += 1
				table.insert(log, { t = now, players = players })
				local ok = all or rand() > 0.1 -- 10% of writes fail and retry
				if not ok then
					fails += 1
				end
				BoardKeys.done(B, batch, j, ok, j.value, now)
			end
			BoardKeys.sweep(B, batch, now)
		end
		for now = 1, 600 do
			-- players 1 to 5 leave at 300 s and come back at 360 s
			if now == 300 then
				for id = 1, 5 do
					BoardKeys.leave(batch, id)
					present[id] = nil
				end
				run(now)
			elseif now == 360 then
				for id = 1, 5 do
					present[id] = true
				end
			end
			for id in present do
				for _, b in B.boards do
					if rand() < 0.25 then -- far busier than real play: a stat every 4 s on every board
						local k = BoardKeys.jobKey(week, b.id, id)
						totals[k] = (totals[k] or 0) + 1
						events += 1
						BoardKeys.queue(batch, week, b.id, id, totals[k])
					end
				end
			end
			if now % B.tick == 0 then
				run(now)
			end
		end
		-- every minute window: within the share of the budget, and always under Roblox's whole budget
		for i, w in log do
			local inWindow, most, least = 0, 0, math.huge
			for j = i, #log do
				if log[j].t - w.t >= 60 then
					break
				end
				inWindow += 1
				most = math.max(most, log[j].players)
				least = math.min(least, log[j].players)
			end
			if inWindow > BoardKeys.budget(B, most) then
				budgetOk = false
			end
			if inWindow > B.budget.base + B.budget.perPlayer * least then
				hardOk = false
			end
		end
		check(spacingOk, "one write per stat per player per minute (a leave flush: Roblox's 6 s key floor)")
		check(budgetOk, "never more than the boards' share of the sorted-write budget in a minute")
		check(hardOk, "never over Roblox's whole budget, even as players leave")
		check(fails > 0, "the sim had failures to retry (" .. fails .. ")")
		check(writes < events / 5, string.format("batched: %d writes for %d stats", writes, events))
		-- shutdown flushes everything left, inside the close deadline
		local t = 600
		while BoardKeys.pending(batch) > 0 and t < 600 + Config.Data.closeDeadline do
			t += 0.25
			run(t, true)
		end
		check(BoardKeys.pending(batch) == 0, "shutdown wrote every unwritten total in " .. (t - 600) .. " s")
		local lost = 0
		for k, v in totals do
			local j = batch.jobs[k]
			if j and j.written ~= v then
				lost += 1
			end
		end
		check(lost == 0, "every final total reached the store")
		-- a lone player's server (budget 21 a minute) still writes everyone's totals, just spread out
		local small = BoardKeys.newBatch()
		for id = 1, 30 do
			BoardKeys.queue(small, week, "Rescues", id, 1)
		end
		local first = BoardKeys.due(B, small, 0, 1)
		check(#first == BoardKeys.budget(B, 1), "a small server writes its budget's worth first")
		for _, j in first do
			BoardKeys.done(B, small, j, true, j.value, 0)
		end
		check(#BoardKeys.due(B, small, 30, 1) == 0, "then waits for the minute")
		local rest = BoardKeys.due(B, small, 61, 1)
		check(#rest == 30 - #first, "and writes the rest next minute")
		-- retries back off and give up after the last try (the save keeps the total)
		local rb = BoardKeys.newBatch()
		BoardKeys.queue(rb, week, "PvpWins", 9, 3)
		local j = BoardKeys.due(B, rb, 0, 30)[1]
		BoardKeys.done(B, rb, j, false, 3, 0)
		check(j.nextTry == B.retry.base, "the first retry waits " .. B.retry.base .. " s")
		check(#BoardKeys.due(B, rb, 1, 30) == 0, "not before")
		for n = 2, B.retry.tries do
			BoardKeys.done(B, rb, j, false, 3, n)
		end
		check(rb.jobs[BoardKeys.jobKey(week, "PvpWins", 9)] == nil, "dropped after the last try")
	end)

	test("Boards (WP2): a week's reward is claimed once, after the standings settle", function()
		local counts: { [string]: number } = {}
		local w = 2970
		check(BoardKeys.add(B, counts, "BossMvp", 1, w) == 1, "a boss MVP counts")
		check(BoardKeys.add(B, counts, "BossMvp", 2, w) == 3, "and adds up")
		BoardKeys.add(B, counts, "Rescues", 4, w)
		check(BoardKeys.total(counts, "BossMvp", w) == 3, "this week's total")
		check(BoardKeys.total(counts, "BossMvp", w + 1) == 0, "another week reads 0")
		check(BoardKeys.total(counts, "PvpWins", w) == 0, "an untouched board reads 0")
		check(not BoardKeys.rollover(B, counts, w), "same week: no roll")
		-- the next week: totals start over, the old week waits for its standings
		check(BoardKeys.rollover(B, counts, w + 1), "a new week rolls")
		check(BoardKeys.total(counts, "BossMvp", w + 1) == 0, "totals start at 0")
		check(counts[BoardKeys.PENDING] == w, "the week played waits")
		local endT = BoardKeys.weekEnd(w)
		local none = BoardKeys.claimable(B, counts, endT + B.reward.settle - 1)
		check(none == nil, "not before the standings settle")
		local week, ids = BoardKeys.claimable(B, counts, endT + B.reward.settle)
		check(week == w, "claimable once settled")
		check(
			#ids == 2 and ids[1] == "BossMvp" and ids[2] == "Rescues",
			"only the boards you counted on are read"
		)
		-- 3rd on boss MVPs, 11th on rescues
		local grants = BoardKeys.claim(B, counts, w, { BossMvp = 3, Rescues = 11 })
		check(
			#grants == 1 and grants[1].board == "BossMvp" and grants[1].rank == 3,
			"a top 10 earns the title"
		)
		check(grants[1].title == "Boss Breaker" and grants[1].new, "the board's own title, new")
		check(grants[1].titleId == B.titleBase + 1, "title id titleBase + the board")
		check(BoardKeys.owns(B, counts, "BossMvp") and not BoardKeys.owns(B, counts, "Rescues"), "owned")
		-- claimed once
		check(#BoardKeys.claim(B, counts, w, { BossMvp = 3 }) == 0, "a second claim grants nothing")
		check(BoardKeys.claimable(B, counts, endT + 10 ^ 7) == nil, "and nothing is pending")
		-- a week with nothing counted leaves nothing pending
		local quiet: { [string]: number } = { [BoardKeys.WEEK] = w }
		BoardKeys.rollover(B, quiet, w + 1)
		check((quiet[BoardKeys.PENDING] or 0) == 0, "a quiet week has nothing to claim")
		-- a tie at 10th earns it; a second top 10 later is not new
		local again: { [string]: number } = table.clone(counts)
		BoardKeys.add(B, again, "BossMvp", 1, w + 1)
		BoardKeys.rollover(B, again, w + 2)
		local g2 = BoardKeys.claim(B, again, w + 1, { BossMvp = 10 })
		check(#g2 == 1 and not g2[1].new, "a shared 10th earns it; already owned is not new")
		-- the title shows in the title list (BadgeRules) the same as BoardKeys says
		local profile = ProfileSchema.default()
		profile.mmo.counts = { [BoardKeys.TITLES] = 5 } -- boss MVPs and PvP wins
		local char = profile.characters[1]
		local fromBadges = {}
		for _, t in BadgeRules.titles(Config, profile, char) do
			fromBadges[t.id] = t.name
		end
		for _, t in BoardKeys.titles(B, profile.mmo.counts) do
			check(fromBadges[t.id] == t.name, "the title list has " .. t.name)
		end
		check(#BoardKeys.titles(B, profile.mmo.counts) == 2, "two titles owned")
		check(BadgeRules.titleText(Config, profile, char, B.titleBase + 3) == "Crater Champion", "wearable")
		check(BadgeRules.titleText(Config, profile, char, B.titleBase + 2) == nil, "not one you lack")
		-- the save keeps the counters (repair keeps string keys of 40 characters or fewer)
		local loaded = ProfileSchema.load(ProfileSchema.deepCopy(profile))
		check(loaded.mmo.counts[BoardKeys.TITLES] == 5, "the title bits survive a load")
		-- the rewards are cosmetic: a title only, never a stat, never sold
		for _, b in B.boards do
			for _, item in Config.Shop.items or {} do
				check(item.title ~= b.title, "no shop item sells " .. b.title)
			end
		end
	end)

	test("Boards (WP2): hooks, flushes, plaza and screen are wired", function()
		local svc = src("src/server/Services/BoardService.luau")
		local store = src("src/server/Services/BoardStore.luau")
		local death = src("src/server/Services/DeathService.luau")
		local hud = src("src/client/Ui/BoardHud.luau")
		check(
			has(svc, "BossService.Rewarded:Connect") and has(svc, 'tier == "mvp"'),
			"boss MVPs from BossService"
		)
		check(
			has(svc, "IncidentService.Rescued:Connect"),
			"rescues from IncidentService (incidents, events, contracts)"
		)
		check(has(svc, '"deepRescue"'), "and the Sunken Line's commuters")
		check(has(svc, "DeathService.PvpWon:Connect"), "PvP wins from DeathService")
		local paid = string.match(death, "if fame > 0 then(.-)\n\t\tend\n")
		check(
			paid ~= nil and has(paid, "DeathService.PvpWon:Fire"),
			"only a PvP win that paid (past the ledger)"
		)
		check(has(svc, "DataService.Leaving:Connect") and has(svc, "BoardKeys.leave"), "a leave flushes")
		check(has(svc, "game:BindToClose") and has(svc, "pass(true)"), "shutdown flushes")
		check(has(svc, "DataService.Loaded:Connect") and has(svc, "tryClaim(player)"), "the claim on join")
		check(
			has(store, "SetAsync") and not has(store, "IncrementAsync"),
			"totals are set (a retry never double counts)"
		)
		check(has(store, "GetRequestBudgetForRequestType"), "writes and reads check Roblox's live budget")
		check(has(store, "cacheSeconds"), "reads are cached")
		check(has(svc, "ModelStreamingMode.Persistent"), "the plaza board streams to every device")
		check(has(hud, "ResetOnSpawn = false"), "the plaza SurfaceGui survives respawns")
		check(has(hud, "Kit.fit(panel"), "the screen fits phones")
		for _, kind in { '"loading"', '"empty"', '"error"' } do
			check(has(hud, "Kit.stateNote(") and has(hud, kind), "the " .. kind .. " state")
		end
		check(has(hud, 'Kit.dock(open, "Boards"'), "a BOARDS button in the top row")
		check(has(hud, 'Juice.fire("boardReward"'), "the reward juice")
		for _, e in { "board_open", "board_reward" } do
			local spec = AnalyticsSchema.EVENTS[e]
			check(spec ~= nil and #spec <= 3, "analytics schema has " .. e)
			check(has(svc, '"' .. e .. '"'), "BoardService logs " .. e)
		end
		local server = src("src/server/init.server.luau")
		local bi, di =
			string.find(server, 'boot("BoardService"', 1, true),
			string.find(server, 'boot("DataService"', 1, true)
		check(
			bi ~= nil and di ~= nil and bi < di,
			"BoardService starts before DataService (claims on the first loads)"
		)
		check(has(src("src/client/init.client.luau"), "BoardHud.init()"), "the client starts BoardHud")
		check(
			has(src("src/server/Services/DevService.luau"), 'BoardService.dev(player, "roll")'),
			"Dev: a week roll"
		)
		check(has(src("src/client/Ui/DevPanel.luau"), '"boardrows"'), "Dev panel: test rows")
	end)

	test("Boards (WP2): no free text: numbers go up, Roblox display names come back", function()
		local open = Remotes.BoardOpen
		check(open ~= nil and open.dir == "C2S" and open.rate ~= nil, "BoardOpen is rate limited")
		for i, a in open.schema do
			check(a.t == "integer" and a.max ~= nil, "BoardOpen argument " .. i .. " is a bounded number")
		end
		for _, name in { "BoardData", "BoardPlaza", "BoardReward" } do
			check(Remotes[name] ~= nil and Remotes[name].dir == "S2C", name .. " goes to the device only")
		end
		local store = src("src/server/Services/BoardStore.luau")
		local svc = src("src/server/Services/BoardService.luau")
		local hud = src("src/client/Ui/BoardHud.luau")
		-- names: Roblox display names (Roblox filters them; Plates show them under the hero name already)
		check(has(store, "player.DisplayName") and has(store, "info.DisplayName"), "display names only")
		check(not has(store, "info.Username") and not has(store, ".Name ="), "never user names or typed text")
		check(has(svc, 'names[r.userId] or "Hero"'), "a fixed word when a name cannot be read")
		check(
			not has(hud, "TextBox") and not has(src("src/shared/BoardKeys.luau"), "TextBox"),
			"no text entry"
		)
		-- the rows carry only numbers, flags and the server's name
		local rows = BoardKeys.rows({ { userId = 1, value = 3 } }, 1, 3, {}, "all", 50)
		for k, v in rows[1] do
			check(type(v) == "number" or type(v) == "boolean", "a row field is a number or flag: " .. k)
		end
	end)
end
