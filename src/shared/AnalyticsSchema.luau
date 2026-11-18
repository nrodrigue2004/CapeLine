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
	level_up = { "level", "playtime_min" }, -- value: seconds in session
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
	anti_exploit_flag = { "kind", "strikes" },
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
	PvP = { "flag_on", "first_pvp_hit", "pvp_win", "pvp_loss", "flag_off" },
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
-- busy (low) events stop at lowShare of it first, so funnels and rare events always get through.
export type Budget = { at: number, n: number, dropped: number }

function AnalyticsSchema.newBudget(): Budget
	return { at = -math.huge, n = 0, dropped = 0 }
end

-- Take one slot at `now` (seconds) with `players` in the server: true when the event may go
function AnalyticsSchema.take(b: Budget, cfg: any, now: number, players: number, low: boolean): boolean
	if now - b.at >= 60 then
		b.at, b.n = now, 0
	end
	local cap = cfg.base + cfg.perPlayer * players
	if b.n >= cap or (low and b.n >= cap * cfg.lowShare) then
		b.dropped += 1
		return false
	end
	b.n += 1
	return true
end

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
