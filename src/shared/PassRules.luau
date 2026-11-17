-- PassRules: the Hero Pass and the weekly episode as pure rules (spec: Hero MMO features > The Hero Pass,
-- Weekly episodes; H8).
-- * Weeks start Monday 00:00 UTC, the same weeks as the world seed (WorldGen.isoWeek); week(t) counts them
--   from 1970. Season s runs Config.Pass.weeks weeks from Config.Pass.startWeek (before it: season 1 week 1).
-- * The save (profile.pass): season, xp, paid (the season's paid track, from a receipt), claimed (free and
--   paid tier bits), day (the last daily first-win bonus), titles and trims (pass looks kept forever).
--   roll() starts a new season: xp, paid and claims reset; the looks stay.
-- * Pass XP: addXp() caps at the last tier; the first win of a UTC day adds the daily bonus. Never doubled.
-- * claim(): a reached tier's reward once per track; the paid track needs paid; looks go into their own
--   stores (emotes, tints, travel styles, pieces, props, pass titles and trims); Credits and Dust come back
--   for the server to pay. Nothing on either track touches a stat.
-- * The episode (profile.episode): week, steps (done bits), counts (per step), intro (the week whose panels
--   were shown). episodeRoll() resets it on a new week; bump() counts a key towards the open steps.

local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")
local CreatorRules = if script
	then require(script.Parent.CreatorRules)
	else (require :: any)("./CreatorRules")
local TravelStyleRules = if script
	then require(script.Parent.TravelStyleRules)
	else (require :: any)("./TravelStyleRules")

local Bits = ProfileSchema.Bits

local PassRules = {}

---------------------------------------------------------------------------
-- Weeks and seasons
---------------------------------------------------------------------------

-- Monday weeks since 1970 (1970-01-01 was a Thursday)
function PassRules.week(t: number): number
	return (math.floor(t / 86400) + 3) // 7
end

function PassRules.day(t: number): number
	return math.floor(t / 86400)
end

-- The season and its week (1 to Config.Pass.weeks) at time t
function PassRules.season(P: any, t: number): (number, number)
	local w = PassRules.week(t) - P.startWeek
	if w < 0 then
		return 1, 1
	end
	return w // P.weeks + 1, w % P.weeks + 1
end

-- When the current week ends (os.time), for the countdowns
function PassRules.weekEnds(t: number): number
	return ((PassRules.week(t) + 1) * 7 - 3) * 86400
end

function PassRules.data(P: any, season: number): any?
	return P.seasons[season]
end

---------------------------------------------------------------------------
-- XP and tiers
---------------------------------------------------------------------------

function PassRules.tier(P: any, xp: number): number
	return math.min(P.tiers, xp // P.xpPerTier)
end

-- A new season: xp, the paid track and the claims start over (pass looks already claimed stay)
function PassRules.roll(pass: any, season: number): boolean
	if pass.season == season then
		return false
	end
	pass.season = season
	pass.xp = 0
	pass.paid = false
	pass.claimed = { free = { 0, 0 }, paid = { 0, 0 } }
	return true
end

-- Add Pass XP for an action (kind: a dailyKinds key gets the first-win bonus once a day).
-- Returns the xp added and the tier before and after.
function PassRules.addXp(P: any, pass: any, n: number, kind: string?, today: number): (number, number, number)
	local before = PassRules.tier(P, pass.xp)
	local add = math.max(0, math.floor(n))
	if kind and P.dailyKinds[kind] and pass.day ~= today then
		pass.day = today
		add += P.xp.dailyFirst
	end
	local cap = P.tiers * P.xpPerTier
	local was = pass.xp
	pass.xp = math.min(cap, pass.xp + add)
	return pass.xp - was, before, PassRules.tier(P, pass.xp)
end

---------------------------------------------------------------------------
-- Rewards and claims
---------------------------------------------------------------------------

-- A tier's reward on a track (false or nil: none)
function PassRules.reward(P: any, season: number, tier: number, paid: boolean): any?
	local d = PassRules.data(P, season)
	if not d then
		return nil
	end
	local row = (if paid then d.paid else d.free)[tier]
	return if row then row else nil
end

function PassRules.claimed(pass: any, tier: number, paid: boolean): boolean
	return Bits.get(if paid then pass.claimed.paid else pass.claimed.free, tier - 1)
end

function PassRules.canClaim(P: any, pass: any, tier: number, paid: boolean): (boolean, string?)
	if tier < 1 or tier > P.tiers or tier % 1 ~= 0 then
		return false, "tier"
	elseif not PassRules.reward(P, pass.season, tier, paid) then
		return false, "none"
	elseif PassRules.tier(P, pass.xp) < tier then
		return false, "locked"
	elseif paid and not pass.paid then
		return false, "paid"
	elseif PassRules.claimed(pass, tier, paid) then
		return false, "claimed"
	end
	return true, nil
end

-- Put a reward's look on the profile (Credits and Dust are the server's to pay). True when it was new.
function PassRules.give(Config: any, profile: any, row: any): boolean
	local k, v = row.kind, row.v
	if k == "title" then
		if Bits.get(profile.pass.titles, v) then
			return false
		end
		Bits.set(profile.pass.titles, v)
	elseif k == "trim" then
		if Bits.get(profile.pass.trims, v) then
			return false
		end
		Bits.set(profile.pass.trims, v)
	elseif k == "emote" then
		if Bits.get(profile.emotes, v) then
			return false
		end
		Bits.set(profile.emotes, v)
	elseif k == "tint" then
		local m = bit32.lshift(1, v)
		if bit32.btest(profile.purchases.tints, m) then
			return false
		end
		profile.purchases.tints = bit32.bor(profile.purchases.tints, m)
	elseif k == "travel" then
		return TravelStyleRules.give(profile, v)
	elseif k == "piece" then
		local p = CreatorRules.index(Config).byName[v]
		return p ~= nil and CreatorRules.grant(profile, p)
	elseif k == "prop" then
		if Bits.get(profile.props, v) then
			return false
		end
		Bits.set(profile.props, v)
	end
	return true
end

-- Claim a reached tier on a track: marks it and gives the look. Returns ok, the reward row.
function PassRules.claim(Config: any, profile: any, tier: number, paid: boolean): (boolean, any?)
	local P = Config.Pass
	local pass = profile.pass
	local ok = PassRules.canClaim(P, pass, tier, paid)
	if not ok then
		return false, nil
	end
	local row = PassRules.reward(P, pass.season, tier, paid)
	Bits.set(if paid then pass.claimed.paid else pass.claimed.free, tier - 1)
	PassRules.give(Config, profile, row)
	return true, row
end

-- A reward's short text for the cards
function PassRules.label(Config: any, row: any): string
	if not row then
		return ""
	end
	local k, v = row.kind, row.v
	if k == "credits" then
		return string.format("%d Credits", v)
	elseif k == "dust" then
		return string.format("%d Lumen Dust", v)
	elseif k == "title" then
		return "Title: " .. (Config.Pass.titles[v] or "?")
	elseif k == "trim" then
		local t = Config.Pass.trims[v]
		return if t then t.name else "Trim"
	elseif k == "emote" then
		local e = Config.Shop.emotes[v]
		return if e then (if e.landing then "Landing: " else "Emote: ") .. e.name else "Emote"
	elseif k == "tint" then
		local t = Config.Shop.tints[v]
		return if t then t.name .. " Effects" else "Tint"
	elseif k == "travel" then
		local s = TravelStyleRules.byId(Config, v)
		return if s then s.name .. " (" .. Config.Move.mobility[s.mobility].name .. ")" else "Travel style"
	elseif k == "piece" then
		return tostring(v)
	elseif k == "prop" then
		return "HQ: " .. (Config.Hq.props[v] or "prop")
	end
	return ""
end

---------------------------------------------------------------------------
-- The weekly episode
---------------------------------------------------------------------------

-- This week's episode: the episode row, its number in the season (1 to 8) and the week
function PassRules.episode(Config: any, t: number): (any?, number, number)
	local E = Config.Episodes
	local s, w = PassRules.season(Config.Pass, t)
	local list = E.seasons[s] or E.seasons[#E.seasons]
	local ep = list and list[((w - 1) % #list) + 1]
	return ep, w, PassRules.week(t)
end

-- A new week: the steps start over
function PassRules.episodeRoll(pe: any, week: number): boolean
	if pe.week == week then
		return false
	end
	pe.week = week
	pe.steps = 0
	pe.counts = { 0, 0, 0, 0 }
	pe.intro = 0
	return true
end

function PassRules.stepDone(pe: any, i: number): boolean
	return bit32.btest(pe.steps, bit32.lshift(1, i - 1))
end

function PassRules.episodeDone(ep: any, pe: any): boolean
	for i in ep.steps do
		if not PassRules.stepDone(pe, i) then
			return false
		end
	end
	return true
end

-- Count `n` of `key` towards this week's open steps. Returns the steps finished now and whether that
-- finished the whole episode.
function PassRules.bump(ep: any, pe: any, key: string, n: number?): ({ number }, boolean)
	local done = {}
	local was = PassRules.episodeDone(ep, pe)
	for i, st in ep.steps do
		if st.key == key and not PassRules.stepDone(pe, i) then
			pe.counts[i] = math.min(st.n, (pe.counts[i] or 0) + (n or 1))
			if pe.counts[i] >= st.n then
				pe.steps = bit32.bor(pe.steps, bit32.lshift(1, i - 1))
				table.insert(done, i)
			end
		end
	end
	return done, (not was) and PassRules.episodeDone(ep, pe)
end

-- The random events' weights this week (Config.Events ids; missing ones weigh 1)
function PassRules.eventWeights(Config: any, t: number): { [string]: number }
	local ep = PassRules.episode(Config, t)
	return if ep and ep.events then ep.events else {}
end

return PassRules
