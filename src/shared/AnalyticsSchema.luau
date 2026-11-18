--!strict
-- AnalyticsSchema: every analytics event and funnel step the spec lists (spec: Analytics and KPIs), as
-- data, so the server can refuse anything else and Lune can test the list. Event names are lowercase with
-- underscores; fields are short codes and numbers only: never names, chat or free text.
-- * EVENTS[name] = the meaning of CustomField01 to 03 (at most 3, Roblox's limit).
-- * FUNNELS[name] = the steps in order. "Opening" is the onboarding funnel (once per account); since lore
--   step 2 (creator first) the creator's steps come right after session_start, and opening_done (the run's
--   end) replaced choice_made (the side is picked in the creator; choice_made stays an event). Lore step 3: the
--   prologue's three beats are spark_detected (the scan found you), first_spark (the side's Spark beat) and
--   fake_cracked (Skylance's face cracked), where first_leap, first_catch and first_blast were.
-- * Audit 2026-11-18: how each funnel counts (KINDS, gates that log in order, once), the sliding budget,
--   device pacing and the events a session with no loaded save may send (NOSAVE) are below.
-- * check(name, fields) cleans one event: false for an unknown name or too many fields; text fields are
--   cut to 32 characters with anything but letters, digits, "_", "-", "." and ":" removed.

local AnalyticsSchema = {}

AnalyticsSchema.EVENTS = {
	-- the studio-wide FunnelKit's 4 events (the same names and fields in every game; Analytics sends them)
	session_start = { "stage", "new_or_returning", "days_away" }, -- value: session number
	stage_reached = { "stage", "session" }, -- value: minutes played
	session_end = { "stage", "activity", "reason_length" }, -- value: session seconds
	first_session_end = { "stage", "activity", "reason_length" }, -- value: session seconds
	session_device = { "platform", "new_or_returning", "side" }, -- value: level (was session_start)
	spark_detected = {}, -- value: seconds since join (lore step 3: the Ceremony prologue's beats)
	first_spark = {},
	fake_cracked = {},
	choice_made = { "choice", "option" },
	choice_pick = { "choice", "option", "side" }, -- lore step 5: each side has its own options
	creator_done = { "class", "side", "set" }, -- value: seconds in the creator
	origin_pick = { "origin", "mode" }, -- value: level; lore step 2: a new hero's origin, or a free change
	path_change = { "class", "set", "kind" }, -- value: level; kind: free (the one change) or first
	incident_done = { "template", "medal", "participants" }, -- value: seconds
	contract_done = { "type", "daily_bonus" }, -- value: seconds
	skill_cast = { "ability", "slot" }, -- sampled (Config.Analytics.castSample); slot, as hits land later
	skill_rank = { "ability", "rank" },
	weapon_buy = { "weapon" }, -- value: Credits paid at a Weapon Rack
	weapon_skill_open = { "weapon", "key" }, -- Mastery opened X, C or V
	level_up = { "level", "session_len" }, -- value: seconds in session; session_len: FunnelKit.lengthBucket (Audit)
	gear_drop = { "tier", "source", "ilvl" },
	gear_upgrade = { "tier", "level", "dust" },
	boss_join = { "boss", "level", "participants" },
	boss_done = { "boss", "tier", "result" }, -- value: contribution
	flag_on = { "location", "level" },
	flag_off = { "location", "level" },
	pvp_hit = { "attacker_level", "target_level", "zone" },
	pvp_win = { "attacker_level", "target_level", "paid" },
	defeat = { "cause", "level" },
	downed = { "result" }, -- value: seconds
	fast_travel = { "beacon", "skipped" },
	mission_start = { "mission", "party", "side" }, -- lore step 5: the mission id (Safehouse, Framed, ...)
	mission_done = { "mission", "party", "side" }, -- value: seconds
	report_player = { "reason" },
	anti_exploit_flag = { "kind", "result" }, -- result: strike or kick
	purchase = { "item", "kind" }, -- value: Robux
	perf_sample = { "device", "preset", "fps_p5" }, -- value: median fps (sampled 10%)
	-- M10 and M11 extras the KPIs need (squads, photos, friend boost, settings)
	squad_join = { "size" },
	photo = { "backdrop" },
	setting_change = { "key", "value" },
	idle_wait = { "reason" }, -- value: seconds (the M11 gate)
	-- Hero MMO features (H4 task forces, H5 nemesis)
	taskforce_open = { "taskforce" },
	taskforce_start = { "taskforce", "party" },
	taskforce_done = { "taskforce", "party" }, -- value: seconds
	nemesis_met = { "rank", "traits" }, -- value: encounters with this nemesis
	nemesis_showdown_start = { "rank", "party" },
	nemesis_showdown = { "rank" }, -- a Showdown won
	mentor_pick = { "mentor", "kind" }, -- kind: first or change
	mentor_line_done = { "mentor" },
	badge_earned = { "badge" }, -- H7
	collect_found = { "set" }, -- value: finds in that set
	collect_set = { "set" },
	contest_enter = { "theme" },
	contest_done = { "theme", "voters" }, -- value: contestants
	pass_tier = { "season" }, -- H8: value: the tier reached
	pass_claim = { "track", "kind" }, -- value: the tier
	episode_step = { "episode" }, -- value: the step
	episode_done = { "episode" },
	travel_style = { "mobility" }, -- value: the style id worn (0 = plain)
	-- WP2: the weekly boards
	board_open = { "board", "filter" }, -- value: your rank (0 = not ranked)
	board_reward = { "board", "place" }, -- value: the final rank that earned the week's title
	-- WP1: the daily streak and quests (Shared.DailyRules builds each one)
	daily_login = { "track_day", "kind" }, -- value: the streak; kind: new, next, grace or reset
	daily_claim = { "track_day", "reward", "late" }, -- value: the streak; late 1: paid on the next day's login
	daily_quest = { "quest", "slot" }, -- value: quests done today
	daily_all_done = { "track_day" }, -- value: the streak
	-- WP10: a group piece or creator code paid (Shared.PromoRules.event): kind group or code, the code's tag
	-- (from the fixed list in Config.Promo; never typed text). Rare: once per account each
	promo_claim = { "kind", "code" },
	-- WP8: the live balance this server runs (BalanceService), once per player session
	balance_live = { "balance", "source", "refused" }, -- value: live numbers applied; balance "v<N>.<rev>"
	-- WP12: a visit to a friend's HQ started (Shared.VisitRules.event): the owner's side, same or cross side,
	-- visitors in that HQ now; value: the owner's HQ level. At most one a minute per visitor
	hq_visit = { "side", "cross", "visitors" },
}

AnalyticsSchema.FUNNELS = {
	Opening = {
		"session_start",
		"creator_open",
		"creator_done",
		"spark_detected",
		"first_spark",
		"fake_cracked",
		"opening_done",
		"first_incident",
		"level_3",
		"first_boss_join",
		"first_boss_done",
		"d1_return",
	},
	Combat = { "skill_cast", "skill_rank", "loadout_swap", "gear_equip", "gear_upgrade", "set_bonus_active" },
	-- Audit 2026-11-18: one flagged stretch, in order: flagged, landed a PvP hit, a PvP fight ended (won or
	-- lost), won one (was flag_on, first_pvp_hit, pvp_win, pvp_loss, flag_off: a win and a loss are two ends of
	-- one fight, so in order every loser skipped pvp_win and flag_off counted only after both)
	PvP = { "flag_on", "first_pvp_hit", "pvp_fight", "pvp_win" },
	Story = { "mission_start", "choice_pick", "mission_done", "act_done" },
	Purchase = { "shop_open", "shop_view_item", "shop_buy_prompt", "shop_buy_ok" },
	-- WP4 (spec: Hero MMO features, "each feature adds ... one funnel step": gap G6): the Hero MMO firsts. A
	-- lifetime funnel (FunnelDef.lifetime): each step once per account, in whatever order the player finds
	-- them (bit i of profile.analytics.mmo). Once live, only ADD steps at the end: the dashboard keys by number.
	MMO = { "first_block", "first_throw", "first_nemesis", "first_taskforce", "first_badge", "pass_bought" },
}

-- The step number of a funnel step (nil if unknown)
function AnalyticsSchema.stepOf(funnel: string, step: string): number?
	local list = AnalyticsSchema.FUNNELS[funnel]
	return list and table.find(list, step)
end

-- A once-per-account step of a lifetime funnel (WP4: the MMO firsts). mask: the steps already logged, one bit
-- each (step i is bit i - 1). Returns the step number and the mask with it set, or nil (unknown, or logged).
function AnalyticsSchema.first(mask: number, funnel: string, step: string): (number?, number)
	local found = AnalyticsSchema.stepOf(funnel, step)
	if not found or found > 16 then
		return nil, mask
	end
	local i = found :: number
	local bit = bit32.lshift(1, i - 1)
	if bit32.band(mask, bit) ~= 0 then
		return nil, mask
	end
	return i, bit32.bor(mask, bit)
end

-- The server's per-minute event budget (Config.Analytics.budget): base + perPlayer x players a minute, and
-- busy (low) events stop at lowShare of it first, so funnels and rare events always get through. Audit
-- 2026-11-18: a sliding 60 s window (the send times themselves), so no 60 s span ever holds more than the
-- cap whatever Roblox's own window is (a fixed minute let a burst at its end and another at the next
-- minute's start send twice the cap inside one 60 s span).
export type Budget = { times: { number }, head: number, tail: number, n: number, dropped: number }

local WINDOW = 60

function AnalyticsSchema.newBudget(): Budget
	return { times = {}, head = 1, tail = 0, n = 0, dropped = 0 }
end

-- Forget sends 60 s or more before `now`; b.n is then the sends inside the window
local function expire(b: Budget, now: number)
	local t = b.times
	local h = b.head
	while h <= b.tail and now - t[h] >= WINDOW do
		t[h] = nil
		h += 1
	end
	if h > b.tail then
		b.head, b.tail = 1, 0
	elseif h > 4096 then
		-- compact so the indices never grow for good on a server that is never quiet
		local keep = table.move(t, h, b.tail, 1, {})
		b.times, b.head, b.tail = keep, 1, #keep
	else
		b.head = h
	end
	b.n = b.tail - b.head + 1
end

local function push(b: Budget, now: number)
	b.tail += 1
	b.times[b.tail] = now
	b.n += 1
end

function AnalyticsSchema.cap(cfg: any, players: number): number
	return cfg.base + cfg.perPlayer * players
end

-- Take one slot at `now` (seconds) with `players` in the server: true when the event may go
function AnalyticsSchema.take(b: Budget, cfg: any, now: number, players: number, low: boolean): boolean
	expire(b, now)
	local cap = AnalyticsSchema.cap(cfg, players)
	if b.n >= cap or (low and b.n >= cap * cfg.lowShare) then
		b.dropped += 1
		return false
	end
	push(b, now)
	return true
end

-- A top-priority send (the studio-wide FunnelKit's events and steps: joins, quits, the Progress ladder) is
-- never dropped but still counts in the window, so the sends after it see the room it used. True while the
-- window is inside the cap (busy events stop at lowShare, which keeps room for these).
function AnalyticsSchema.force(b: Budget, cfg: any, now: number, players: number): boolean
	expire(b, now)
	push(b, now)
	return b.n <= AnalyticsSchema.cap(cfg, players)
end

-- Device facts (the Telemetry remote) are paced per player and kind (Config.Analytics.devicePace: the
-- fewest seconds between two), so one device can never spend the server's budget: the remote's own rate
-- (1 a second) would let 30 devices send 1,800 a minute. last: { [kind] = os.clock of the last one kept }
function AnalyticsSchema.pace(
	last: { [number]: number },
	gaps: { [number]: number },
	kind: number,
	now: number
): boolean
	local gap = gaps[kind]
	if gap == nil then
		return true
	end
	local at = last[kind]
	if at ~= nil and now - at < gap then
		return false
	end
	last[kind] = now
	return true
end

-- Low-cardinality fields (Roblox keeps a limited number of distinct field values per event; Audit
-- 2026-11-18): fps to a multiple of 5 from 0 to 240 (49 values; perf_sample's fps_p5 was the raw number a
-- device sends, up to 1,000)
function AnalyticsSchema.fps(n: number): number
	local v = math.clamp(math.floor(tonumber(n) or 0), 0, 240)
	return v - v % 5
end

-- How each funnel counts (Audit 2026-11-18). Every kind logs a step at most once, and the ordered kinds log
-- a step only after every step before it: a step reached early waits (the gate's reached bits) and goes out
-- the moment the gap fills, so no step is skipped and none is counted twice.
-- * onboarding: Roblox's onboarding funnel (Opening): once per account, in order, kept in the save.
-- * ladder: a lifetime funnel on FunnelKit.LIFE_SESSION: once per account, in order, kept in the save
--   (Combat: casts start a funnel session 2 times a second otherwise; Story: act_done and replays).
-- * session: a recurring funnel: step 1 opens a new funnel session (a new id), each later step once per
--   session, in order, and a step with no session open is not logged (PvP: one flagged stretch; Purchase:
--   one visit to the shop).
-- * any: a lifetime funnel whose steps count once per account in any order (MMO; AnalyticsSchema.first).
AnalyticsSchema.KINDS = {
	Opening = "onboarding",
	Combat = "ladder",
	Story = "ladder",
	PvP = "session",
	Purchase = "session",
	MMO = "any",
}

-- Where an onboarding or ladder funnel keeps its gate in profile.analytics: { steps sent, reached bits }
AnalyticsSchema.SAVE = {
	Opening = { "onboard", "onboardReach" },
	Combat = { "combat", "combatReach" },
	Story = { "story", "storyReach" },
}

-- A funnel's place in its steps: steps 1 to `sent` are logged, `reach` has bit i - 1 for each step reached
export type Gate = { sent: number, reach: number, id: string? }

function AnalyticsSchema.newGate(sent: number?, reach: number?): Gate
	local s = sent or 0
	-- the steps already sent were reached (a save from before the gate keeps only `sent`)
	return { sent = s, reach = bit32.bor(reach or 0, bit32.lshift(1, math.min(s, 31)) - 1) }
end

-- Mark a step reached: true when it is new (not sent and not reached before)
function AnalyticsSchema.reach(g: Gate, funnel: string, step: string): boolean
	local found = AnalyticsSchema.stepOf(funnel, step)
	if not found or found > 31 or found <= g.sent then
		return false
	end
	local bit = bit32.lshift(1, (found :: number) - 1)
	if bit32.band(g.reach, bit) ~= 0 then
		return false
	end
	g.reach = bit32.bor(g.reach, bit)
	return true
end

-- The next step to log in order (sent + 1 once it is reached), its number and name; nil while it waits
function AnalyticsSchema.due(g: Gate, funnel: string): (number?, string?)
	local list = AnalyticsSchema.FUNNELS[funnel]
	local i = g.sent + 1
	if not list or i > #list or i > 31 or bit32.band(g.reach, bit32.lshift(1, i - 1)) == 0 then
		return nil, nil
	end
	return i, list[i]
end

-- The due step went out
function AnalyticsSchema.sent(g: Gate)
	g.sent += 1
end

-- A recurring (session) funnel's step: step 1 opens a new funnel session in `open` (true as the second
-- result: the caller gives it a new id), a later step joins the one open; nil when none is open
function AnalyticsSchema.sessionGate(open: { [string]: Gate }, funnel: string, step: string): (Gate?, boolean)
	local i = AnalyticsSchema.stepOf(funnel, step)
	if not i then
		return nil, false
	end
	if i == 1 then
		local g = AnalyticsSchema.newGate()
		open[funnel] = g
		return g, true
	end
	return open[funnel], false
end

-- Events still logged for a session whose save did not load (DataService could not read it, so the
-- profile is a blank default): only facts about the device and the server. Everything else would count a
-- returning player as new (level ups from 1, badges, firsts, the creator, the onboarding funnel again).
AnalyticsSchema.NOSAVE = {
	session_device = true,
	balance_live = true,
	perf_sample = true,
	idle_wait = true,
	anti_exploit_flag = true,
	report_player = true,
}

function AnalyticsSchema.cleanText(v: any): string
	local s = tostring(v)
	s = string.gsub(s, "[^%w_%-%.:]", "")
	return string.sub(s, 1, 32)
end

-- Clean one event: ok, the fields as text (CustomField01 to 03 in order)
function AnalyticsSchema.check(name: string, fields: { any }?): (boolean, { string })
	local spec = AnalyticsSchema.EVENTS[name]
	local list = fields or {}
	if not spec or #list > 3 or #list > math.max(#spec, 0) then
		return false, {}
	end
	if not string.match(name, "^[a-z0-9_]+$") then
		return false, {}
	end
	local out = {}
	for i, v in list do
		out[i] = AnalyticsSchema.cleanText(v)
	end
	return true, out
end

return AnalyticsSchema
