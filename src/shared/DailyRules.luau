--!strict
-- DailyRules: the daily login streak and daily quests (spec: Update 1 > "daily quests and login streak"; gap
-- G1, WP1). Pure, so DailyService, DailyHud and the Lune tests agree. Numbers in Config.Daily. Works on the
-- account's save block profile.daily (ProfileSchema v13); the day is the UTC day (os.time // dayLength).
-- * The streak: visit(d, today) counts a day's login once (a later day only, so a server whose clock is behind
--   never counts or pays twice): the next day goes on, one missed day goes on with the weekly grace, a longer
--   gap starts over at day 1 (kind: titles and the best streak are kept). The day's reward is owed until
--   claim(); a reward still owed when the next day's visit comes is handed back as `late` and paid then, never
--   lost (CLAUDE.md rule 6).
-- * The track: 7 days that loop; reward(d, streak, level) resolves a day (Renown and quest Credits at the
--   contract scale for the hero's level; day 7 the next daily title not yet owned, or Dust).
-- * Daily quests: order(day) shuffles the pool from the day's seed (the same for everyone that day); picks()
--   takes the first ones open at a level, no two on the same key, PvP ones only while Config.Daily.pvp is on
--   (and those also count a non-PvP `alt`). roll() sets a new day's picks once; bump() counts a key and returns
--   the slots it finished (each pays once) and whether all are now done (the bonus, once).
-- * Analytics: loginEvent / claimEvent / questEvent / allEvent give daily_login's, daily_claim's, daily_quest's
--   and daily_all_done's value and fields (the fields AnalyticsSchema lists for each).

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local DailyRules = {}

export type Reward = {
	credits: number,
	renown: number,
	dust: number,
	title: number, -- the daily title earned (its place in Config.Daily.titles), 0 = none
	titleName: string?,
	day: number, -- the track day (1 to 7)
	streak: number,
}

export type Visit = {
	kind: string, -- "new" (first ever), "next", "grace" (one missed day forgiven) or "reset" (started over)
	streak: number,
	old: number, -- the streak before (what a reset ended)
	late: number, -- the streak number of an earlier day's reward still owed (pay it now), 0 = none
}

-- The UTC day of time t
function DailyRules.day(Config: any, t: number): number
	return math.floor(t / Config.Daily.dayLength)
end

-- Seconds until the next reset (00:00 UTC)
function DailyRules.untilReset(Config: any, t: number): number
	local len = Config.Daily.dayLength
	return (math.floor(t / len) + 1) * len - t
end

-- The track day (1 to 7) of a streak count
function DailyRules.trackDay(Config: any, streak: number): number
	local n = #Config.Daily.track
	return (math.max(1, math.floor(streak)) - 1) % n + 1
end

-- Can the weekly grace forgive a missed day today?
function DailyRules.graceReady(Config: any, d: any, today: number): boolean
	return d.graceAt == 0 or today - d.graceAt >= Config.Daily.grace.every
end

---------------------------------------------------------------------------
-- The streak
---------------------------------------------------------------------------

-- Count today's login. nil when today is already counted (or the clock is behind the save's last day).
function DailyRules.visit(Config: any, d: any, today: number): Visit?
	if today <= d.last then
		return nil
	end
	local D = Config.Daily
	local late = d.owed
	local old = d.streak
	local kind
	if d.last == 0 or d.streak <= 0 then
		kind = "new"
		d.streak = 1
	else
		local missed = today - d.last - 1
		if missed == 0 then
			kind = "next"
			d.streak += 1
		elseif missed <= D.grace.missed and DailyRules.graceReady(Config, d, today) then
			kind = "grace"
			d.streak += 1
			d.graceAt = today
		else
			kind = "reset"
			d.streak = 1
		end
	end
	d.last = today
	d.best = math.max(d.best, d.streak)
	d.owed = d.streak
	return { kind = kind, streak = d.streak, old = old, late = late }
end

-- Credits and Renown for `mult` contracts at this level (Config.Economy.earn.contract x Config.Economy.scale)
function DailyRules.contractPay(Config: any, level: number, mult: number): (number, number)
	local e = Config.Economy.earn.contract
	local s = Config.Economy.scale
	local L = math.max(1, math.floor(level))
	local credits = (e.credits[1] + e.credits[2] * L) * mult * s.credits
	local renown = (e.renown[1] + e.renown[2] * L) * mult * s.renown
	return math.floor(credits + 0.5), math.floor(renown + 0.5)
end

local function hasTitle(d: any, n: number): boolean
	return bit32.btest(d.titles, bit32.lshift(1, n - 1))
end

-- The next daily title this account does not own (its place in Config.Daily.titles), 0 when all are owned
function DailyRules.nextTitle(Config: any, d: any): number
	for n = 1, #Config.Daily.titles do
		if not hasTitle(d, n) then
			return n
		end
	end
	return 0
end

-- What the reward for streak number `streak` is at this level (nothing is granted)
function DailyRules.reward(Config: any, d: any, streak: number, level: number): Reward
	local D = Config.Daily
	local day = DailyRules.trackDay(Config, streak)
	local out: Reward = { credits = 0, renown = 0, dust = 0, title = 0, day = day, streak = streak }
	for _, row in D.track[day] do
		if row.kind == "credits" then
			out.credits += row.n
		elseif row.kind == "dust" then
			out.dust += row.n
		elseif row.kind == "renown" then
			local _, r = DailyRules.contractPay(Config, level, row.n)
			out.renown += r
		elseif row.kind == "title" then
			local n = DailyRules.nextTitle(Config, d)
			if n > 0 then
				out.title = n
				out.titleName = D.titles[n]
			else
				out.dust += D.titleDust
			end
		end
	end
	return out
end

-- Pay streak number `streak`'s reward on the save: grants its title bit and returns what to pay. The caller
-- pays the Credits, Renown and Dust (the save holds the title).
function DailyRules.settle(Config: any, d: any, streak: number, level: number): Reward?
	if streak <= 0 then
		return nil
	end
	local r = DailyRules.reward(Config, d, streak, level)
	if r.title > 0 then
		d.titles = bit32.bor(d.titles, bit32.lshift(1, r.title - 1))
	end
	return r
end

-- CLAIM: today's (or the last visit's) owed reward, once. nil when nothing is owed.
function DailyRules.claim(Config: any, d: any, level: number): Reward?
	local owed = d.owed
	if owed <= 0 then
		return nil
	end
	d.owed = 0 -- marked before anything is paid: a second claim finds nothing
	return DailyRules.settle(Config, d, owed, level)
end

-- The daily titles this account owns, for the title list (Shared.BadgeRules.titles)
function DailyRules.titles(Config: any, d: any): { { id: number, name: string } }
	local D = Config.Daily
	local out = {}
	if type(d) ~= "table" or type(d.titles) ~= "number" then
		return out
	end
	for n, name in D.titles do
		if hasTitle(d, n) then
			table.insert(out, { id = D.titleBase + n, name = name })
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Daily quests
---------------------------------------------------------------------------

local byId: { [any]: { [string]: any } } = {}

-- A quest's definition by id (nil for an unknown id)
function DailyRules.quest(Config: any, id: string): any?
	local D = Config.Daily
	local map = byId[D]
	if not map then
		local made: { [string]: any } = {}
		for _, q in D.quests do
			made[q.id] = q
		end
		byId[D] = made
		map = made
	end
	return (map :: { [string]: any })[id]
end

-- The pool's order on a day (quest indices), from the day's seed
function DailyRules.order(Config: any, day: number): { number }
	local D = Config.Daily
	local list = {}
	for i = 1, #D.quests do
		list[i] = i
	end
	local rng = Rng.new(Rng.hash(day, D.seedSalt))
	return rng:shuffle(list)
end

-- May a quest be offered at this level? (PvP ones only while Config.Daily.pvp is on)
function DailyRules.open(Config: any, q: any, level: number): boolean
	if q.pvp and not Config.Daily.pvp then
		return false
	end
	return level >= (q.minLevel or 1)
end

-- The day's picks for a level: quest ids, at most Config.Daily.picks, no two on the same key
function DailyRules.picks(Config: any, day: number, level: number): { string }
	local D = Config.Daily
	local out, keys = {}, {}
	for _, i in DailyRules.order(Config, day) do
		local q = D.quests[i]
		if
			#out < D.picks
			and DailyRules.open(Config, q, level)
			and not keys[q.key]
			and not (q.alt and keys[q.alt])
		then
			table.insert(out, q.id)
			keys[q.key] = true
			if q.alt then
				keys[q.alt] = true
			end
		end
	end
	return out
end

-- A new day's quests, once a day (a later day only). Returns true when it rolled.
function DailyRules.roll(Config: any, d: any, today: number, level: number): boolean
	if today <= d.qday then
		return false
	end
	local picks = DailyRules.picks(Config, today, level)
	d.qday = today
	d.quests = { picks[1] or "", picks[2] or "", picks[3] or "" }
	d.have = { 0, 0, 0 }
	d.paid = 0
	d.bonus = 0
	return true
end

local function slotPaid(d: any, i: number): boolean
	return bit32.btest(d.paid, bit32.lshift(1, i - 1))
end
DailyRules.slotPaid = slotPaid

-- How many of today's quests are done, and how many there are
function DailyRules.count(Config: any, d: any): (number, number)
	local done, total = 0, 0
	for i, id in d.quests do
		if DailyRules.quest(Config, id) then
			total += 1
			if slotPaid(d, i) then
				done += 1
			end
		end
	end
	return done, total
end

-- Count `n` of a key towards today's quests. Returns the slots this finished (each marked paid here, so it
-- pays once), the slots that moved, and whether every quest is now done with the bonus not yet paid (marked
-- paid here too).
function DailyRules.bump(Config: any, d: any, key: string, n: number?): ({ number }, { number }, boolean)
	local add = math.max(0, math.floor(n or 1))
	local finished, moved = {}, {}
	if add <= 0 then
		return finished, moved, false
	end
	for i, id in d.quests do
		local q = DailyRules.quest(Config, id)
		if q and not slotPaid(d, i) and (q.key == key or q.alt == key) then
			d.have[i] = math.min(q.n, (d.have[i] or 0) + add)
			table.insert(moved, i)
			if d.have[i] >= q.n then
				d.paid = bit32.bor(d.paid, bit32.lshift(1, i - 1))
				table.insert(finished, i)
			end
		end
	end
	local all = false
	if #finished > 0 and d.bonus == 0 then
		local done, total = DailyRules.count(Config, d)
		if total > 0 and done == total then
			d.bonus = 1
			all = true
		end
	end
	return finished, moved, all
end

-- A quest's pay at a level (contracts' worth at the contract scale)
function DailyRules.questPay(Config: any, q: any, level: number): (number, number)
	return DailyRules.contractPay(Config, level, q.pay)
end

-- The all-done bonus at a level: Credits, Renown, Dust
function DailyRules.allPay(Config: any, level: number): (number, number, number)
	local a = Config.Daily.allDone
	local c, r = DailyRules.contractPay(Config, level, a.pay)
	return c, r, a.dust
end

---------------------------------------------------------------------------
-- The device's view, Studio, analytics
---------------------------------------------------------------------------

-- The DailyState packet's body (fixed text from the config only)
function DailyRules.view(Config: any, d: any, today: number, level: number, now: number): { [string]: any }
	local D = Config.Daily
	local streak = math.max(d.streak, 0)
	-- the track shown: the week the owed (or last claimed) day sits in
	local at = if d.owed > 0 then d.owed else math.max(streak, 1)
	local first = at - DailyRules.trackDay(Config, at) + 1
	local days = {}
	for i = 1, #D.track do
		local s = first + i - 1
		local r = DailyRules.reward(Config, d, s, level)
		days[i] = {
			credits = r.credits,
			renown = r.renown,
			dust = r.dust,
			title = r.titleName,
			state = if d.owed > 0 and s == d.owed
				then "ready"
				elseif s <= streak and d.last > 0 then "got"
				else "later",
		}
	end
	local quests = {}
	for i, id in d.quests do
		local q = DailyRules.quest(Config, id)
		if q then
			local c, r = DailyRules.questPay(Config, q, level)
			table.insert(quests, {
				slot = i,
				text = q.text,
				have = d.have[i] or 0,
				n = q.n,
				done = slotPaid(d, i),
				credits = c,
				renown = r,
			})
		end
	end
	local ac, ar, ad = DailyRules.allPay(Config, level)
	return {
		on = D.on,
		streak = streak,
		best = d.best,
		day = DailyRules.trackDay(Config, at),
		owed = d.owed > 0,
		grace = DailyRules.graceReady(Config, d, today + 1), -- would a missed day tomorrow be forgiven?
		days = days,
		quests = quests,
		bonus = { credits = ac, renown = ar, dust = ad, paid = d.bonus == 1 },
		resetIn = DailyRules.untilReset(Config, now),
	}
end

-- Studio: move the save `days` days into the past (as if that many days went by)
function DailyRules.shift(d: any, days: number)
	for _, k in { "last", "graceAt", "qday" } do
		if d[k] > 0 then
			d[k] = math.max(1, d[k] - days)
		end
	end
end

-- Analytics (the service names each event; AnalyticsSchema lists its fields). daily_login: value = the
-- streak; fields = track day, kind
function DailyRules.loginEvent(Config: any, v: Visit): (number, { any })
	return v.streak, { DailyRules.trackDay(Config, v.streak), v.kind }
end

-- daily_claim: value = the streak; fields = track day, what it gave (title, or the first kind), late (1/0)
function DailyRules.claimEvent(r: Reward, late: boolean): (number, { any })
	local what = if r.title > 0
		then "title"
		elseif r.renown > 0 then "renown"
		elseif r.dust > 0 and r.credits == 0 then "dust"
		else "credits"
	return r.streak, { r.day, what, if late then 1 else 0 }
end

-- daily_quest: value = quests done today; fields = the quest id, its slot
function DailyRules.questEvent(Config: any, d: any, slot: number): (number, { any })
	local done = DailyRules.count(Config, d)
	return done, { d.quests[slot], slot }
end

-- daily_all_done: value = the streak; fields = the track day
function DailyRules.allEvent(Config: any, d: any): (number, { any })
	return d.streak, { DailyRules.trackDay(Config, math.max(d.streak, 1)) }
end

return DailyRules
