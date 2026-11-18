-- WP8: live tuning from Balance_v<N> (gap check G11). The pure merge (Shared.BalanceMerge), the whitelist
-- (Config.Balance), the boot order, the analytics event and the Dev panel print.
-- Called from tests/run.luau: require("./balance_test")({ test, check, Config }). ONLY=WP8 runs it alone.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local BalanceMerge = require("../src/shared/BalanceMerge")
	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local B = Config.Balance

	local function source(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function finite(v: any): boolean
		return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
	end
	local function deepCopy(t: any, seen: { [any]: any }?): any
		if type(t) ~= "table" then
			return t
		end
		local memo = seen or {}
		if memo[t] then
			return memo[t]
		end
		local out = {}
		memo[t] = out
		for k, v in t do
			out[k] = deepCopy(v, memo)
		end
		return out
	end
	-- every concrete path a pattern names in the bundled Config ("*" over the keys that exist)
	local function expand(pattern: string): { string }
		local segs = BalanceMerge.split(pattern)
		local out = {}
		local function walk(node: any, i: number, prefix: string)
			if i > #segs then
				if finite(node) then
					table.insert(out, prefix)
				end
				return
			end
			if type(node) ~= "table" then
				return
			end
			local function step(key: any)
				local nxt = node[key]
				local name = tostring(key)
				walk(nxt, i + 1, if prefix == "" then name else prefix .. "." .. name)
			end
			if segs[i] == "*" then
				for k in node do
					step(k)
				end
			else
				local key: any = segs[i]
				if node[key] == nil and tonumber(key) then
					key = tonumber(key)
				end
				step(key)
			end
		end
		walk(Config, 1, "")
		table.sort(out)
		return out
	end
	local function why(result: any, path: string): string?
		for _, r in result.rejected do
			if r.path == path then
				return r.why
			end
		end
		return nil
	end

	test("WP8 Balance: the whitelist: server numbers only, each in its own range, nothing locked", function()
		check(B.on == true, "on by default (it only reads; with no key nothing changes)")
		check(B.store == "Balance_v" and type(B.key) == "string" and #B.key > 0, "the spec's store name")
		check(
			math.floor(Config.Version.balance) == Config.Version.balance and Config.Version.balance >= 1,
			"version"
		)
		check(B.timeout > 0 and B.timeout <= 10, "boot waits at most a few seconds")
		check(B.tries >= 1 and B.maxEntries >= 20 and B.maxDepth >= 5, "limits")
		local total = 0
		for _, rule in B.keys do
			local paths = expand(rule.path)
			check(#paths >= 1, rule.path .. " names at least one number in the bundled Config")
			check(not BalanceMerge.locked(B, rule.path), rule.path .. " is not locked")
			check(rule.rel ~= nil or (rule.min ~= nil and rule.max ~= nil), rule.path .. " has a range")
			if rule.rel then
				check(
					rule.rel[1] > 0 and rule.rel[1] <= 1 and rule.rel[2] >= 1,
					rule.path .. ": rel brackets 1"
				)
			else
				check(rule.min <= rule.max, rule.path .. ": min <= max")
			end
			for _, p in paths do
				total += 1
				check(BalanceMerge.match(B, p) == rule, p .. " matches its own rule first")
				local v = BalanceMerge.get(Config, p)
				local lo, hi = BalanceMerge.range(rule, v)
				check(v >= lo and v <= hi, p .. ": the bundled number sits inside its range")
				if rule.int then
					check(math.floor(v) == v, p .. ": a whole number")
				end
			end
		end
		check(total >= 40, "a useful set of numbers (" .. total .. ")")
		-- never ids, prices, or anything sold or saved
		for _, rule in B.keys do
			local top = BalanceMerge.split(rule.path)[1]
			for _, banned in { "Shop", "Pass", "Data", "Version", "Loot", "Creator", "Weapons", "Hq" } do
				check(top ~= banned, rule.path .. " is not in " .. banned)
			end
			for _, seg in BalanceMerge.split(rule.path) do
				check(
					seg ~= "levels" and seg ~= "doublePass" and seg ~= "rewardMult",
					rule.path .. ": shown or sold"
				)
			end
		end
		for _, pair in B.pairs do
			check(
				BalanceMerge.match(B, pair[1]) ~= nil and BalanceMerge.match(B, pair[2]) ~= nil,
				"pair is listed"
			)
			check(
				BalanceMerge.get(Config, pair[1]) <= BalanceMerge.get(Config, pair[2]),
				"bundled pair in order"
			)
		end
		-- the bundled Config passes its own rules: a key that writes every bundled number back changes nothing
		local echo = {}
		for _, rule in B.keys do
			for _, p in expand(rule.path) do
				echo[p] = BalanceMerge.get(Config, p)
			end
		end
		local r = BalanceMerge.merge(Config, echo, B)
		check(#r.rejected == 0, "every bundled number is accepted (" .. #r.rejected .. " refused)")
		check(#r.applied == total, "and applied")
	end)

	test("WP8 Balance: no device reads a live number (devices keep the bundled Config)", function()
		local client = ""
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.match(name, "%.luau$") then
					client ..= source(path) .. "\n"
				end
			end
		end
		scan("src/client")
		for _, needle in
			{
				"Economy.scale",
				"Economy.earn",
				"Boss.hp",
				"Boss.schedule",
				"Enemies.scale",
				"hpPerLevel",
				"dmgBase",
				"dmgPerLevel",
				"Progress.earn(",
				"ContractPlan.pay(",
				"DailyRules.",
				"BossMath.",
				"Formulas.enemyHealth",
				"Formulas.enemyDamage",
				".credits[",
				".renown[",
			}
		do
			check(not has(client, needle), "the client never reads " .. needle)
		end
	end)

	test("WP8 Balance: merge lays whitelisted numbers over Config and never changes it", function()
		local before = Config.Economy.scale.credits
		local patch = {
			_rev = 3,
			_note = "a note, skipped",
			Economy = { scale = { credits = 1.6 }, earn = { incident = { credits = { 30, 2 } } } },
			["Boss.hp.base"] = 50000,
			Enemies = { BruteBot = { hp = 700 } },
			Contracts = { types = { DroneSweep = { renown = { 70 } } } },
		}
		local r = BalanceMerge.merge(Config, patch, B)
		check(#r.rejected == 0, "nothing refused (" .. #r.rejected .. ")")
		check(#r.applied == 6, "six numbers applied (" .. #r.applied .. ")")
		check(r.rev == 3, "the revision is kept")
		check(r.view.Economy.scale.credits == 1.6, "nested form")
		check(r.view.Boss.hp.base == 50000, "dotted form")
		check(
			r.view.Economy.earn.incident.credits[1] == 30 and r.view.Economy.earn.incident.credits[2] == 2,
			"arrays"
		)
		check(r.view.Enemies.BruteBot.hp == 700, "a robot's hp")
		check(r.view.Contracts.types.DroneSweep.renown[1] == 70, "a contract's pay")
		check(
			r.view.Contracts.types.DroneSweep.renown[2] == Config.Contracts.types.DroneSweep.renown[2],
			"the rest kept"
		)
		-- the bundled Config is untouched, and only the tables on the paths are copies
		check(Config.Economy.scale.credits == before, "Config unchanged")
		check(Config.Enemies.BruteBot.hp == 600 and Config.Boss.hp.base == 60000, "Config unchanged (2)")
		check(r.view ~= Config and r.view.Economy ~= Config.Economy, "the touched tables are copies")
		check(
			r.view.Move == Config.Move and r.view.Economy.levels == Config.Economy.levels,
			"the rest is shared"
		)
		check(r.view.Enemies.SparkDrone == Config.Enemies.SparkDrone, "other robots shared")
		check(r.view.Enemies.BruteBot.slam == Config.Enemies.BruteBot.slam, "deeper tables shared")
		-- the list is sorted, with old and new numbers for the log
		for i = 2, #r.applied do
			check(r.applied[i - 1].path < r.applied[i].path, "applied list sorted")
		end
		local brute
		for _, a in r.applied do
			if a.path == "Enemies.BruteBot.hp" then
				brute = a
			end
		end
		check(brute ~= nil and brute.old == 600 and brute.new == 700, "old and new kept")
		local lines = BalanceMerge.lines(r)
		check(#lines == 6 and has(lines[1], "->"), "one report line each")
		-- nothing: no change
		local none = BalanceMerge.merge(Config, nil, B)
		check(#none.applied == 0 and #none.rejected == 0 and none.view == Config, "no key, no change")
		local empty = BalanceMerge.merge(Config, {}, B)
		check(#empty.applied == 0 and #empty.rejected == 0, "an empty key, no change")
	end)

	test("WP8 Balance: refuses wrong types, NaN, inf, out of range, unknown, locked, duplicates", function()
		local cases = {
			{ "Economy.scale.credits", "1.5", "type" },
			{ "Economy.scale.renown", true, "type" },
			{ "Enemies.scale.dmgBase", 0 / 0, "nan" },
			{ "Enemies.scale.dmgPerLevel", math.huge, "inf" },
			{ "Enemies.scale.hpPerLevel", -math.huge, "inf" },
			{ "Boss.hp.perHero", 99999999, "range" },
			{ "Economy.earn.rescue.credits.1", -5, "range" },
			{ "Enemies.SparkDrone.hp", 1000, "range" }, -- 10x its own 100: rel caps at 2x
			{ "Enemies.SparkDrone.coeff", Config.Enemies.SparkDrone.coeff * 0.4, "range" },
			{ "Boss.hp.base", 55000.5, "int" },
			{ "Economy.levels.base", 120, "unknown" }, -- the level curve would move saved levels
			{ "Economy.bonus.doublePass", 3, "unknown" }, -- the 2x pass is sold
			{ "Heroic.rewardMult", 2, "unknown" }, -- shown on devices
			{ "Enemies.NotARobot.hp", 100, "unknown" }, -- "*" never makes a new key
			{ "Economy.earn.incident.credits.3", 1, "unknown" }, -- nor a new array slot
			{ "Economy.scale.brandNew", 1, "unknown" },
			{ "Enemies.SparkDrone.typeId", 2, "locked" }, -- an id
			{ "Loot.sources.incident.chance", 0.5, "locked" }, -- odds are shown in Loot Info
			{ "Shop.gizmo.price", 1, "locked" },
			{ "Version.balance", 9, "locked" },
			{ "Balance.timeout", 1, "locked" },
			{ "Data.autosave", 10, "locked" },
		}
		for _, c in cases do
			local r = BalanceMerge.merge(Config, { [c[1]] = c[2] }, B)
			check(#r.applied == 0, c[1] .. " is not applied")
			check(
				why(r, c[1]) == c[3],
				c[1] .. " refused as " .. c[3] .. " (got " .. tostring(why(r, c[1])) .. ")"
			)
		end
		-- a table where a number lives is a path that does not exist
		local r = BalanceMerge.merge(Config, { Economy = { scale = { credits = { 1 } } } }, B)
		check(#r.applied == 0 and why(r, "Economy.scale.credits.1") == "unknown", "a table for a number")
		-- one bad number never stops the good ones
		r = BalanceMerge.merge(Config, { ["Economy.scale.credits"] = 1.2, ["Economy.scale.renown"] = 50 }, B)
		check(#r.applied == 1 and r.applied[1].path == "Economy.scale.credits", "the good number lands")
		check(why(r, "Economy.scale.renown") == "range", "the bad one is refused")
		-- the same number twice (nested and dotted)
		r = BalanceMerge.merge(
			Config,
			{ ["Economy.scale.credits"] = 1.2, Economy = { scale = { credits = 1.3 } } },
			B
		)
		check(#r.applied == 1 and why(r, "Economy.scale.credits") == "duplicate", "twice: the first only")
		-- the boss wait stays shortest <= longest
		r = BalanceMerge.merge(Config, { Boss = { schedule = { every = { 2400 } } } }, B) -- over the bundled 1800
		check(#r.applied == 0 and why(r, "Boss.schedule.every.1") == "order", "shortest past the longest")
		r = BalanceMerge.merge(Config, { Boss = { schedule = { every = { 2400, 3000 } } } }, B)
		check(#r.applied == 2 and r.view.Boss.schedule.every[1] == 2400, "both moved together is fine")
		r = BalanceMerge.merge(Config, { Boss = { schedule = { every = { 1500, 1400 } } } }, B)
		check(#r.applied == 0 and #r.rejected == 2, "a crossed pair refuses both")
		-- whole-key limits and bad shapes
		local many = {}
		for i = 1, B.maxEntries + 1 do
			many["Economy.scale.x" .. i] = 1
		end
		r = BalanceMerge.merge(Config, many, B)
		check(#r.applied == 0 and why(r, "*") == "too_many", "too many numbers: all refused")
		local deep: any = { v = 1 }
		for _ = 1, B.maxDepth + 2 do
			deep = { a = deep }
		end
		r = BalanceMerge.merge(Config, deep, B)
		check(#r.applied == 0 and why(r, "*") == "too_deep", "too deep: all refused")
		r = BalanceMerge.merge(Config, "not a table", B)
		check(#r.applied == 0 and why(r, "*") == "type" and r.view == Config, "not a table: refused")
		r = BalanceMerge.merge(Config, { _rev = -1, _x = { a = 1 } }, B)
		check(#r.applied == 0 and #r.rejected == 0 and r.rev == nil, "notes and a bad revision are skipped")
	end)

	test("WP8 Balance: write sets the applied numbers in place; the documented example applies", function()
		local live = deepCopy(Config)
		-- the Launch Checklist's example key, as JSON the way the DataStore returns it
		local example = serde.decode(
			"json",
			'{"_rev": 1, "_note": "softer first weeks", "Economy": {"scale": {"credits": 1.5}},'
				.. ' "Boss": {"hp": {"base": 50000}}, "Enemies.BruteBot.hp": 500}'
		)
		local r = BalanceMerge.merge(live, example, B)
		check(#r.rejected == 0 and #r.applied == 3 and r.rev == 1, "the example applies cleanly")
		local n = BalanceMerge.write(live, r.applied)
		check(n == 3, "three numbers set")
		check(live.Economy.scale.credits == 1.5 and live.Boss.hp.base == 50000, "in place")
		check(live.Enemies.BruteBot.hp == 500, "in place (2)")
		check(live.Economy.scale.renown == Config.Economy.scale.renown, "the rest untouched")
		check(Config.Economy.scale.credits ~= 1.5, "the shared bundled Config is not the copy")
		-- write only ever replaces a number that is there
		local n2 = BalanceMerge.write(live, { { path = "Economy.scale.nope", old = 0, new = 1 } } :: any)
		check(n2 == 0 and live.Economy.scale.nope == nil, "never adds a key")
		-- the pay formula reads the live table: the scale moves pay
		local Progress = require("../src/shared/Progress")
		local c0 = Progress.earn(Config, "incident", 10)
		local c1 = Progress.earn(live, "incident", 10)
		check(c1 > c0, "a higher live scale pays more (" .. c0 .. " -> " .. c1 .. ")")
	end)

	test("WP8 Balance: boot order, fallback, analytics, Dev panel", function()
		local boot = source("src/server/init.server.luau")
		local load = string.find(boot, "BalanceService.load()", 1, true)
		local firstService = string.find(boot, "require(Services.", 1, true)
		check(
			load ~= nil and firstService ~= nil and load < firstService,
			"the balance loads before any service"
		)
		check(has(boot, 'boot("BalanceService", BalanceService.init)'), "its analytics hook boots")
		local a = string.find(boot, 'boot("Analytics", Analytics.init)', 1, true)
		local b = string.find(boot, 'boot("BalanceService", BalanceService.init)', 1, true)
		check(a ~= nil and b ~= nil and a < b, "after Analytics")
		local svc = source("src/server/Services/BalanceService.luau")
		check(
			not has(svc, "require(script.Parent.Analytics)") or has(svc, "function BalanceService.init()"),
			"lazy"
		)
		local top = string.sub(svc, 1, (string.find(svc, "local BalanceService = {}", 1, true)))
		check(not has(top, "script.Parent"), "requires no other service at load (only Config and Shared)")
		check(has(svc, "Config.Version.balance") and has(svc, "Config.Balance.store"), "Balance_v<N>")
		check(has(svc, "pcall") and has(svc, "GetAsync") and has(svc, "B.timeout"), "pcall and a timeout")
		check(has(svc, "game.PlaceId == 0") and has(svc, '"studio"'), "unpublished and Studio fall back")
		check(has(svc, "if not B.on then"), "the switch")
		check(has(svc, "BalanceMerge.write(Config"), "applies over the live Config")
		-- the analytics event: in the schema, short codes, never low priority, one per session
		local E = AnalyticsSchema.EVENTS.balance_live
		check(E ~= nil and #E <= 3, "balance_live in the schema")
		local ok, clean = AnalyticsSchema.check("balance_live", { "v1.3", "live", 0 })
		check(ok and clean[1] == "v1.3" and clean[2] == "live" and clean[3] == "0", "fields are short codes")
		check(Config.Analytics.lowPriority.balance_live == nil, "never dropped as busy")
		check(has(svc, "PlayerAdded"), "once per player session")
		-- a full server joining at once stays far inside the per-minute budget
		local budget = AnalyticsSchema.newBudget()
		local okAll = true
		for _ = 1, 30 do
			okAll = AnalyticsSchema.take(budget, Config.Analytics.budget, 0, 30, false) and okAll
		end
		check(okAll and budget.n == 30, "30 joins in a minute all fit")
		-- the Dev panel prints it
		check(has(source("src/client/Ui/DevPanel.luau"), '"Balance: print"'), "a Dev panel button")
		check(
			has(source("src/server/Services/DevService.luau"), "BalanceService.report()"),
			"the server prints"
		)
		local remotes = require("../src/shared/Remotes")
		check(
			remotes.DevCommand ~= nil and #"balance" <= remotes.DevCommand.schema[1].max,
			"the command fits"
		)
	end)
end
