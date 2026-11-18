-- Overnight queue item 6 (2026-11-18): the analytics and funnels audit. Run by tests/run.luau
-- (ONLY="Audit analytics" runs this package). Pure rules in Shared.AnalyticsSchema; the services are checked
-- by their source where only Studio can run them.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")

	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local FunnelKit = require("../src/shared/FunnelKit")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local DailyRules = require("../src/shared/DailyRules")
	local PromoRules = require("../src/shared/PromoRules")
	local Rng = require("../src/shared/Rng")

	local function source(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function body(text: string, header: string): string
		local at = string.find(text, header, 1, true)
		if not at then
			return ""
		end
		local stop = string.find(text, "\nend\n", at, true) or #text
		return string.sub(text, at, stop)
	end

	local B = Config.Analytics.budget
	local E = AnalyticsSchema.EVENTS
	local F = AnalyticsSchema.FUNNELS

	-- the most sends inside any 60 s span of a sorted list of send times
	local function busiest(times: { number }): number
		local most, lo = 0, 1
		for hi = 1, #times do
			while times[hi] - times[lo] >= 60 do
				lo += 1
			end
			most = math.max(most, hi - lo + 1)
		end
		return most
	end

	---------------------------------------------------------------------------
	-- The per-minute budget
	---------------------------------------------------------------------------

	test("Audit analytics: no 60 s span ever holds more than the budget's cap", function()
		local cap = B.base + B.perPlayer * 10
		local b = AnalyticsSchema.newBudget()
		local sent = {}
		local function try(now: number, n: number)
			for _ = 1, n do
				if AnalyticsSchema.take(b, B, now, 10, false) then
					table.insert(sent, now)
				end
			end
		end
		-- a quiet start, a burst late in that minute, another just after it (a fixed minute sent both)
		try(0, 1)
		try(59, cap)
		try(60.5, cap)
		try(119.5, cap)
		check(busiest(sent) <= cap, "at most " .. cap .. " in any 60 s (got " .. busiest(sent) .. ")")
		check(b.n <= cap, "the window's count is the sends inside it")
		-- and it frees up as sends age out
		check(AnalyticsSchema.take(b, B, 200, 10, false), "room again once the window has moved on")
	end)

	test("Audit analytics: FunnelKit's sends count in the window after a quiet spell", function()
		local cap = AnalyticsSchema.cap(B, 30)
		local b = AnalyticsSchema.newBudget()
		AnalyticsSchema.take(b, B, 0, 30, false)
		local sent = {}
		-- 30 joins at t = 500 (the window from t = 0 is long gone): each is a forced send
		for _ = 1, 30 do
			check(AnalyticsSchema.force(b, B, 500, 30), "a forced send inside the cap reports true")
			table.insert(sent, 500)
		end
		for _ = 1, cap * 2 do
			if AnalyticsSchema.take(b, B, 501, 30, false) then
				table.insert(sent, 501)
			end
		end
		check(
			busiest(sent) == cap,
			"the forced sends used their room (" .. busiest(sent) .. " of " .. cap .. ")"
		)
		local an = source("src/server/Services/Analytics.luau")
		check(not has(an, "budget.n +="), "no hand-made count that a stale window drops")
		check(has(an, "AnalyticsSchema.force(budget"), "FunnelKit's sends go through force")
		local sink = string.match(an, "Analytics%.funnelSink = {(.-)\n}") or ""
		local _, forced = string.gsub(sink, "forceBudget%(%)", "")
		check(forced == 2, "both of FunnelKit's sinks (steps and events) count in the window")
	end)

	test("Audit analytics: a busy minute with 30 players stays in budget and loses no funnel step", function()
		local players = 30
		local cap = AnalyticsSchema.cap(B, players)
		local b = AnalyticsSchema.newBudget()
		local paced: { [number]: { [number]: number } } = {}
		local sent: { number } = {}
		local lowSent: { number } = {}
		local highWanted, highSent, lowWanted = 0, 0, 0
		local function send(now: number, low: boolean)
			if low then
				lowWanted += 1
			else
				highWanted += 1
			end
			if AnalyticsSchema.take(b, B, now, players, low) then
				table.insert(sent, now)
				if low then
					table.insert(lowSent, now)
				else
					highSent += 1
				end
			end
		end
		local rng = Rng.new(6)
		local dt = 0.1
		for tick = 0, 1800 do -- 3 minutes
			local now = tick * dt
			for p = 1, players do
				-- the first 20 s: everyone joins (FunnelKit: session_start, Progress Joined, Returns) and the
				-- join events (session_device, balance_live, daily_login, the Opening step) go out
				if tick == p * 6 then
					for _ = 1, 3 do
						AnalyticsSchema.force(b, B, now, players)
						table.insert(sent, now)
					end
					for _ = 1, 4 do
						send(now, false)
					end
				end
				-- a hard fight: 3 casts a second a hero, skill_cast sampled (low priority)
				if Rng.next(rng) < 3 * dt * Config.Analytics.castSample then
					send(now, true)
				end
				-- a gear drop every 10 s a hero in the boss fight (low), PvP hits (low)
				if Rng.next(rng) < dt / 10 then
					send(now, true)
				end
				if Rng.next(rng) < dt / 5 then
					send(now, true)
				end
				-- rare events and funnel steps: level ups, incidents, boss join and done, missions, contracts,
				-- dailies, gear upgrades, ladder steps: 8 a minute a hero (a very busy minute)
				if Rng.next(rng) < dt * 8 / 60 then
					send(now, false)
				end
				-- perf samples: 10% of devices once a minute (low)
				if p <= 3 and tick % 600 == p then
					send(now, true)
				end
				-- one misbehaving device sends shop_open at the remote's full rate (1 a second): paced
				if p == 1 and tick % 10 == 0 then
					paced[p] = paced[p] or {}
					if AnalyticsSchema.pace(paced[p], Config.Analytics.devicePace, 2, now) then
						send(now, false)
					end
				end
			end
		end
		table.sort(sent)
		check(busiest(sent) <= cap, "every 60 s holds at most " .. cap .. " (got " .. busiest(sent) .. ")")
		check(
			highSent == highWanted,
			"no funnel step or rare event dropped (" .. highSent .. "/" .. highWanted .. ")"
		)
		check(busiest(lowSent) <= math.ceil(cap * B.lowShare), "busy events stay inside their share")
		check(#lowSent > 0 and #lowSent < lowWanted, "busy events are trimmed, not silenced")
	end)

	test("Audit analytics: device facts are paced per player and kind", function()
		local last = {}
		local kept = 0
		for t = 0, 59 do
			if AnalyticsSchema.pace(last, Config.Analytics.devicePace, 2, t) then
				kept += 1
			end
		end
		check(kept == 60 // Config.Analytics.devicePace[2], "shop_open at most once per gap (" .. kept .. ")")
		local perf = 0
		for t = 0, 599 do
			if AnalyticsSchema.pace(last, Config.Analytics.devicePace, 1, t) then
				perf += 1
			end
		end
		check(
			perf <= 600 / Config.Analytics.devicePace[1],
			"perf samples about once a minute (" .. perf .. ")"
		)
		check(Config.Analytics.devicePace[1] < Config.Analytics.perfEvery, "an honest device's minute fits")
		check(AnalyticsSchema.pace(last, Config.Analytics.devicePace, 5, 0), "the hello is not paced")
		local an = source("src/server/Services/Analytics.luau")
		local tele = body(an, "local function onTelemetry")
		check(
			has(tele, "AnalyticsSchema.pace(mine, Config.Analytics.devicePace, kind"),
			"the remote is paced"
		)
		check(not has(tele, "takeBudget("), "the shop steps take their slot once, in Analytics.step")
		check(has(tele, "Analytics.Photo:Fire(player)"), "the Photo recon contract still counts every shot")
	end)

	---------------------------------------------------------------------------
	-- Funnels: in order, never skipped, never twice
	---------------------------------------------------------------------------

	-- drive a gate like the server: reach, then send every due step in order
	local function walk(g: any, funnel: string, steps: { string }): { number }
		local out = {}
		for _, step in steps do
			AnalyticsSchema.reach(g, funnel, step)
			while true do
				local i = AnalyticsSchema.due(g, funnel)
				if not i then
					break
				end
				AnalyticsSchema.sent(g)
				table.insert(out, i)
			end
		end
		return out
	end
	local function inOrder(list: { number }, from: number, to: number): boolean
		if #list ~= to - from + 1 then
			return false
		end
		for k, v in list do
			if v ~= from + k - 1 then
				return false
			end
		end
		return true
	end

	test(
		"Audit analytics: the Opening funnel: level 3 from the prologue no longer skips first_incident",
		function()
			check(AnalyticsSchema.KINDS.Opening == "onboarding", "Opening is the onboarding funnel")
			local g = AnalyticsSchema.newGate()
			-- a real first session: the prologue's reward is level 3 (Config.Story.opening.reward), then a
			-- world boss starts before any incident
			check(Config.Story.opening.reward.level >= 3, "the prologue pays level 3")
			local sent = walk(g, "Opening", {
				"session_start",
				"creator_open",
				"creator_done",
				"spark_detected",
				"first_spark",
				"fake_cracked",
				"opening_done",
				"level_3",
				"first_boss_join",
				"first_boss_done",
			})
			check(inOrder(sent, 1, 7), "steps 1 to 7, then level_3 waits for first_incident")
			sent = walk(g, "Opening", { "first_incident" })
			check(inOrder(sent, 8, 11), "first_incident lets 8 to 11 out in order")
			sent = walk(g, "Opening", { "level_3", "session_start", "first_incident" })
			check(#sent == 0, "a step already logged never logs again")
			-- the save: kept across a rejoin and a server hop (the profile), repaired from an older save
			local p = ProfileSchema.default()
			p.analytics.onboard, p.analytics.onboardReach = g.sent, g.reach
			local back = ProfileSchema.load(ProfileSchema.deepCopy(p))
			local again = AnalyticsSchema.newGate(back.analytics.onboard, back.analytics.onboardReach)
			check(again.sent == 11 and again.reach == g.reach, "the gate survives a rejoin")
			check(
				#walk(again, "Opening", { "first_boss_done", "level_3" }) == 0,
				"nothing again after a rejoin"
			)
			check(inOrder(walk(again, "Opening", { "d1_return" }), 12, 12), "d1_return comes next")
			local old = ProfileSchema.default()
			old.analytics = { onboard = 9, firstSeen = 10, d1 = 0 }
			local repaired = ProfileSchema.load(old).analytics
			check(
				repaired.onboard == 9 and repaired.onboardReach == 2 ^ 9 - 1,
				"an older save: steps 1 to 9 reached"
			)
			local bad = ProfileSchema.default()
			bad.analytics.onboardReach = -4
			bad.analytics.combat = 99
			local fixed = ProfileSchema.load(bad).analytics
			check(fixed.onboardReach >= 0 and fixed.combat <= 31, "bad gates are clamped")
			check(
				ProfileSchema.clientView(ProfileSchema.default()).analytics == nil,
				"never in the client view"
			)
		end
	)

	test("Audit analytics: the Combat and Story funnels count once per account, in order", function()
		check(AnalyticsSchema.KINDS.Combat == "ladder" and AnalyticsSchema.KINDS.Story == "ladder", "ladders")
		for funnel, keys in AnalyticsSchema.SAVE do
			local d = ProfileSchema.default().analytics
			check(d[keys[1]] == 0 and d[keys[2]] == 0, funnel .. "'s gate in a new save")
			check(#F[funnel] <= 31, funnel .. " fits the 31 reached bits")
		end
		-- Combat: casts come several a second (each used to open a new funnel session)
		local g = AnalyticsSchema.newGate()
		local first = walk(g, "Combat", { "skill_cast", "skill_cast", "skill_cast" })
		check(inOrder(first, 1, 1), "one skill_cast however many casts")
		check(#walk(g, "Combat", { "gear_equip", "loadout_swap" }) == 0, "a step ahead waits")
		check(inOrder(walk(g, "Combat", { "skill_rank" }), 2, 4), "then 2, 3 and 4 in order")
		-- Story: a mission's clear comes before the first choice (mission 3); act_done once despite replays
		local st = AnalyticsSchema.newGate()
		check(inOrder(walk(st, "Story", { "mission_start", "mission_done", "mission_start" }), 1, 1), "start")
		check(inOrder(walk(st, "Story", { "choice_pick" }), 2, 3), "the choice lets the clear follow")
		check(inOrder(walk(st, "Story", { "act_done", "act_done", "mission_done" }), 4, 4), "act_done once")
		-- the server: the ladders read and write the save and send on the lifetime session id
		local an = source("src/server/Services/Analytics.luau")
		local ladder = body(an, "local function ladder(")
		check(
			has(ladder, "AnalyticsSchema.newGate(an[keys[1]], an[keys[2]])"),
			"the gate comes from the save"
		)
		check(has(ladder, "FunnelKit.LIFE_SESSION") and has(ladder, "DataService.saveSoon"), "sent and saved")
		local cs = source("src/server/Services/CombatService.luau")
		local at = string.find(cs, 'Analytics.step(hero.player, "Combat", "skill_cast")', 1, true) or 0
		local sample = string.find(cs, "math.random() < Config.Analytics.castSample", 1, true) or 0
		check(at > 0 and at < sample, "the first cast counts even when its event is not sampled")
	end)

	test(
		"Audit analytics: PvP and Purchase: one funnel session per flag or shop visit, each step once",
		function()
			check(
				AnalyticsSchema.KINDS.PvP == "session" and AnalyticsSchema.KINDS.Purchase == "session",
				"sessions"
			)
			local open = {}
			local g = AnalyticsSchema.sessionGate(open, "PvP", "pvp_win")
			check(g == nil, "a win with no flag_on opens nothing")
			local s1, opened = AnalyticsSchema.sessionGate(open, "PvP", "flag_on")
			check(s1 ~= nil and opened, "flag_on opens a session")
			check(inOrder(walk(s1, "PvP", { "flag_on" }), 1, 1), "flag_on is step 1")
			-- a loser who never hit: the fight waits for a hit in this session
			check(#walk(s1, "PvP", { "pvp_fight" }) == 0, "a fight with no hit waits")
			check(
				inOrder(walk(s1, "PvP", { "first_pvp_hit", "first_pvp_hit", "first_pvp_hit" }), 2, 3),
				"hit, fight"
			)
			check(inOrder(walk(s1, "PvP", { "pvp_fight", "pvp_win", "pvp_win" }), 4, 4), "one win counted")
			local s2 = AnalyticsSchema.sessionGate(open, "PvP", "flag_on")
			check(
				s2 ~= s1 and s2 ~= nil and inOrder(walk(s2, "PvP", { "flag_on" }), 1, 1),
				"a new flag, a new session"
			)
			check(AnalyticsSchema.sessionGate(open, "PvP", "first_pvp_hit") == s2, "later steps join it")
			-- the step list: an ordered ladder with no branch (a win and a loss used to be steps 3 and 4)
			check(#F.PvP == 4 and F.PvP[3] == "pvp_fight" and F.PvP[4] == "pvp_win", "flag, hit, fight, win")
			-- Purchase: a prompt outside a shop visit (the starter card) is not a shop funnel step
			local shop = {}
			check(
				AnalyticsSchema.sessionGate(shop, "Purchase", "shop_buy_prompt") == nil,
				"no visit, no step"
			)
			local v = AnalyticsSchema.sessionGate(shop, "Purchase", "shop_open")
			check(
				inOrder(walk(v, "Purchase", { "shop_open", "shop_view_item", "shop_view_item" }), 1, 2),
				"visit"
			)
			-- the server: flag off closes the session; every hit tries first_pvp_hit (the session keeps one)
			local hooks = source("src/server/Services/AnalyticsHooks.luau")
			check(has(hooks, 'Analytics.close(p, "PvP")'), "flag off ends the PvP session")
			local hit = body(hooks, "function AnalyticsHooks.pvpHit")
			local stepAt = string.find(hit, 'Analytics.step(p, "PvP", "first_pvp_hit")', 1, true) or 1e9
			local onceAt = string.find(hit, "if pvpHit[p] then", 1, true) or 0
			check(
				stepAt < onceAt,
				"first_pvp_hit per flagged stretch, the pvp_hit event once a server session"
			)
			local an = source("src/server/Services/Analytics.luau")
			local step = body(an, "function Analytics.step(")
			check(
				has(step, "AnalyticsSchema.sessionGate(mine, funnel, stepName)"),
				"the server uses the gate"
			)
			check(has(step, "if not g then"), "a step with no session open is dropped")
		end
	)

	test("Audit analytics: every funnel step takes a budget slot; a refused one is sent later", function()
		local an = source("src/server/Services/Analytics.luau")
		local drain = body(an, "local function drain(")
		check(has(drain, "takeBudget(false)"), "each step takes a slot")
		check(
			(string.find(drain, "takeBudget", 1, true) or 1e9)
				< (string.find(drain, "AnalyticsSchema.sent(g)", 1, true) or 0),
			"marked sent only once its slot was taken"
		)
		check(has(an, "function Analytics.flush("), "a flush for held steps")
		check(
			has(source("src/server/Services/AnalyticsHooks.luau"), "Analytics.flush(p)"),
			"run every few seconds"
		)
		local ev = body(an, "function Analytics.event(")
		local checkAt = string.find(ev, "AnalyticsSchema.check(name, fields)", 1, true) or 1e9
		local takeAt = string.find(ev, "takeBudget(", 1, true) or 0
		check(checkAt < takeAt, "a refused event takes no slot")
	end)

	---------------------------------------------------------------------------
	-- Once per account: a save that did not load
	---------------------------------------------------------------------------

	test("Audit analytics: a session whose save did not load never counts the account again", function()
		for name in AnalyticsSchema.NOSAVE do
			check(E[name] ~= nil, "NOSAVE lists a real event: " .. name)
		end
		for _, once in
			{ "creator_done", "level_up", "badge_earned", "collect_set", "promo_claim", "daily_login" }
		do
			check(not AnalyticsSchema.NOSAVE[once], once .. " is not sent from a blank profile")
		end
		local an = source("src/server/Services/Analytics.luau")
		local ev = body(an, "function Analytics.event(")
		check(has(ev, "not AnalyticsSchema.NOSAVE[name] and unsaved(player)"), "events check the save")
		check(has(body(an, "local function ladder("), "not DataService.isSaving(player)"), "ladders check it")
		check(
			has(body(an, "function Analytics.first("), "not DataService.isSaving(player)"),
			"MMO firsts check it"
		)
		local hooks = source("src/server/Services/AnalyticsHooks.luau")
		local joined = body(hooks, "local function joined(")
		local guard = string.find(joined, "if not DataService.isSaving(player) then", 1, true) or 1e9
		local join = string.find(joined, "funnels:join(", 1, true) or 0
		check(guard < join, "FunnelKit (sessions, Returns, Progress) skips a blank profile")
		check(
			has(joined, 'Analytics.session(player, "nosave", sideOf)'),
			"the device is still logged, tagged"
		)
	end)

	---------------------------------------------------------------------------
	-- Every event: in the schema, the right fields, no personal data, Roblox's limits
	---------------------------------------------------------------------------

	-- every Analytics.event( call in the server: its whole argument text
	local function calls(): { { file: string, args: string } }
		local out = {}
		for _, name in fs.readDir("src/server/Services") do
			local text = source("src/server/Services/" .. name)
			local from = 1
			while true do
				local at = string.find(text, "Analytics.event(", from, true)
				if not at then
					break
				end
				local i = at + #"Analytics.event("
				local depth = 1
				while depth > 0 and i <= #text do
					local c = string.sub(text, i, i)
					if c == "(" or c == "{" then
						depth += 1
					elseif c == ")" or c == "}" then
						depth -= 1
					elseif c == '"' then
						i = string.find(text, '"', i + 1, true) or #text
					end
					i += 1
				end
				local args = string.sub(text, at + #"Analytics.event(", i - 2)
				-- skip the definition itself
				if not string.find(args, "player: Player", 1, true) then
					table.insert(out, { file = name, args = args })
				end
				from = i
			end
		end
		return out
	end

	-- the top-level items of the last {...} argument (nil when the fields come from a function)
	local function fieldCount(args: string): number?
		local open = nil
		local depth = 0
		local i = 1
		while i <= #args do
			local c = string.sub(args, i, i)
			if c == '"' then
				i = string.find(args, '"', i + 1, true) or #args
			elseif c == "{" or c == "(" then
				if c == "{" and depth == 0 then
					open = i
				end
				depth += 1
			elseif c == "}" or c == ")" then
				depth -= 1
			end
			i += 1
		end
		if not open then
			return nil
		end
		local inner = string.match(string.sub(args, open :: number), "^{(.*)}%s*,?%s*$")
		if not inner then
			return nil
		end
		if string.match(inner, "^%s*$") then
			return 0
		end
		local n, d = 1, 0
		local j = 1
		while j <= #inner do
			local c = string.sub(inner, j, j)
			if c == '"' then
				j = string.find(inner, '"', j + 1, true) or #inner
			elseif c == "{" or c == "(" then
				d += 1
			elseif c == "}" or c == ")" then
				d -= 1
			elseif c == "," and d == 0 and string.match(string.sub(inner, j + 1), "%S") then
				n += 1
			end
			j += 1
		end
		return n
	end

	test(
		"Audit analytics: every event call is in the schema with its fields, and never personal data",
		function()
			local list = calls()
			check(#list >= 60, "found the call sites (" .. #list .. ")")
			local fired = {}
			for _, c in list do
				local where = c.file .. ": " .. string.sub(c.args, 1, 60)
				-- every literal name the call can send (a name, or an if-expression's two)
				local names = {}
				local afterPlayer = string.match(c.args, "^[^,]+,%s*(.*)$") or ""
				local head = string.match(afterPlayer, '^(if .- else%s*"[%w_]+")')
					or string.match(afterPlayer, '^("[%w_]+")')
				if head then
					for n in string.gmatch(head, '"([%w_]+)"') do
						table.insert(names, n)
					end
				end
				for _, n in names do
					fired[n] = true
					check(E[n] ~= nil, "in the schema: " .. n .. " (" .. where .. ")")
					local count = fieldCount(c.args)
					if E[n] and count then
						check(
							count <= #E[n],
							n .. " sends at most its " .. #E[n] .. " fields (" .. count .. ")"
						)
					end
				end
				-- never a name, user id or typed text in a field (a function's own arguments, like a count's
				-- squad lookup by user id, never reach a field: they are stripped first)
				local values = string.gsub(c.args, "%b()", "()")
				for _, bad in { "UserId", ".Name", "DisplayName", ".Text", "heroName", "loserName", ".label" } do
					check(not has(values, bad), "no " .. bad .. " in " .. where)
				end
			end
			-- the dynamic ones: the prologue's beats, and the fields WP1 and WP10 build in Shared
			local opening = source("src/server/Services/OpeningService.luau")
			for _, beat in { "spark_detected", "first_spark", "fake_cracked" } do
				check(
					has(opening, '"' .. beat .. '"') and E[beat] and #E[beat] == 0,
					beat .. ": a beat, no fields"
				)
				fired[beat] = true
			end
			-- every schema event has a call that sends it (FunnelKit sends its own four)
			for name in E do
				local kit =
					table.find({ "session_start", "stage_reached", "session_end", "first_session_end" }, name)
				check(kit ~= nil or fired[name] == true, "a call sends " .. name)
			end
			local v = { kind = "next", streak = 9, late = 0 }
			local _, login = DailyRules.loginEvent(Config, v :: any)
			check(#login == #E.daily_login, "daily_login's fields")
			local _, claim = DailyRules.claimEvent(
				{ credits = 1, renown = 0, dust = 0, title = 0, day = 2, streak = 2 },
				false
			)
			check(#claim == #E.daily_claim, "daily_claim's fields")
			local _, code = PromoRules.event("code", { code = "ABC", piece = 1 } :: any)
			check(
				#code == #E.promo_claim and code[2] == "ABC",
				"promo_claim: the fixed list's code, 2 fields"
			)
			-- the field names say what is sent
			check(
				E.anti_exploit_flag[2] == "result",
				"anti_exploit_flag's second field is the result (strike or kick)"
			)
			check(
				has(source("src/server/Services/GuardService.luau"), 'if kicked then "kick" else "strike"'),
				"as sent"
			)
			local hooks = source("src/server/Services/AnalyticsHooks.luau")
			check(not has(hooks, 'loser.level, "1" }'), "pvp_win's paid field is not always 1")
			check(
				has(hooks, "DeathService.PvpWon:Connect") and has(hooks, 'if paid then "1" else "0"'),
				"read from PvpWon"
			)
			local deaths = source("src/server/Services/DeathService.luau")
			check(
				(string.find(deaths, "DeathService.PvpWon:Fire", 1, true) or 1e9)
					< (string.find(deaths, "DeathService.PvpDefeat:Fire", 1, true) or 0),
				"PvpWon fires before PvpDefeat, so the flag is set in time"
			)
		end
	)

	test("Audit analytics: Roblox's limits: names, funnels, fields and few distinct field values", function()
		local names = 0
		for name, fields in E do
			names += 1
			check(#fields <= 3, name .. ": at most 3 custom fields")
			check(#name <= 50, name .. ": a short name")
		end
		-- Roblox's custom event names per experience (FunnelKit's header: 100)
		check(names <= 100, "custom event names: " .. names .. " of 100")
		local funnels = 0
		for funnel, steps in F do
			if AnalyticsSchema.KINDS[funnel] ~= "onboarding" then
				funnels += 1
			end
			check(AnalyticsSchema.KINDS[funnel] ~= nil, funnel .. " has a kind")
			local seen = {}
			for _, step in steps do
				check(not seen[step], funnel .. ": " .. step .. " once")
				seen[step] = true
			end
		end
		-- the onboarding funnel (Opening) plus the others, and FunnelKit's Progress and Returns
		check(funnels + 2 <= 10, "funnels: " .. funnels + 2 .. " of 10, plus the onboarding funnel")
		-- few distinct values per field: fps in 5s, session length in FunnelKit's buckets, no scene ids
		check(
			AnalyticsSchema.fps(1000) == 240
				and AnalyticsSchema.fps(57) == 55
				and AnalyticsSchema.fps(-3) == 0,
			"fps"
		)
		local fpsValues = {}
		for n = 0, 1000 do
			fpsValues[AnalyticsSchema.fps(n)] = true
		end
		local count = 0
		for _ in fpsValues do
			count += 1
		end
		check(
			4 * 4 * count <= 8000,
			"perf_sample: devices x presets x fps stay small (" .. 4 * 4 * count .. ")"
		)
		local an = source("src/server/Services/Analytics.luau")
		check(has(an, "AnalyticsSchema.fps(value // 1000)"), "perf_sample's fps_p5 is bucketed")
		local hooks = source("src/server/Services/AnalyticsHooks.luau")
		check(has(hooks, "FunnelKit.lengthBucket(Analytics.since(p))"), "level_up: session length in buckets")
		check(E.level_up[2] == "session_len", "level_up's field says so")
		check(not has(hooks, '"Scene " ..'), "session_end's activity has no scene id")
		check(#FunnelKit.lengthBucket(0) > 0, "FunnelKit buckets")
	end)
end
