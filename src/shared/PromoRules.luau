--!strict
-- PromoRules: the group-join cosmetic and creator codes as pure rules (gap check G12, WP10; numbers and the
-- code list in Config.Promo). No Roblox types, so Lune tests every rule.
-- * typed(text): what the code box keeps as you type (A to Z, 0 to 9, upper case, at most maxLength).
-- * normalize(raw): the code the server matches, or nil and why ("bad": not a code shape at all).
-- * find(code, studio): the row of the FIXED list with exactly this code (studio adds Config.Promo.studio).
--   Nothing else is ever matched: no prefix, no near miss, no player-made codes.
-- * window(row, day): "live", "notyet" or "expired" for a UTC day (os.time() // 86400).
-- * redeem(promo, raw, day, studio): one try on an account's promo block; marks the claim on success.
-- * canTry / fail: the wrong-code wait (Config.Promo.tries), per player, on the server only.
-- * group(promo, member): true once when a member's group piece should pay (marks it).
-- * validate(index): problems in Config.Promo (bad codes, repeats, dates, pieces that are not "drop").
-- * clean(raw): the saved block repaired (ProfileSchema.repair).
-- * view(promo, day, studio): what the Settings rows need (no code text, only counts).
-- * event(kind, row): promo_claim's value and fields (AnalyticsSchema).
-- profile.promo = { group = 0 or 1 (the group piece paid), codes = { [CODE] = the UTC day it was claimed } }.

local PromoRules = {}

export type Row = { code: string, piece: string, starts: string?, ends: string?, tag: string? }
export type Result = { ok: boolean, reason: string, row: Row? }

local MAX_SAVED = 200 -- claimed codes kept on one save (far above any real list)
local SAVED_KEY_MAX = 16

-- The code box: upper-case letters and digits only, cut to the longest code
function PromoRules.typed(Config: any, text: string): string
	local s = string.gsub(string.upper(text), "[^A-Z0-9]", "")
	return string.sub(s, 1, Config.Promo.maxLength)
end

-- The code the server matches: nil and "bad" for anything that is not a code's shape
function PromoRules.normalize(Config: any, raw: any): (string?, string?)
	local P = Config.Promo
	if type(raw) ~= "string" or #raw > P.rawMax then
		return nil, "bad"
	end
	local s = string.gsub(string.upper(raw), "[%s%-_]", "") -- spaces, dashes and underscores are forgiven
	if string.find(s, "[^A-Z0-9]") or #s < P.minLength or #s > P.maxLength then
		return nil, "bad"
	end
	return s, nil
end

-- A "YYYY-MM-DD" UTC date as a UTC day number (days since 1970-01-01), or nil when it is not a real date
function PromoRules.dayOf(date: any): number?
	if type(date) ~= "string" then
		return nil
	end
	local ys, ms, ds = string.match(date, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not ys then
		return nil
	end
	local y, m, d = tonumber(ys) :: number, tonumber(ms) :: number, tonumber(ds) :: number
	if m < 1 or m > 12 or d < 1 then
		return nil
	end
	local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
	local lengths = { 31, if leap then 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if d > lengths[m] then
		return nil
	end
	-- days from the civil date (Howard Hinnant's algorithm)
	local yy = if m <= 2 then y - 1 else y
	local era = yy // 400
	local yoe = yy - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

local function rows(Config: any, studio: boolean?): { Row }
	local out = {}
	for _, r in Config.Promo.codes do
		table.insert(out, r)
	end
	if studio then
		for _, r in Config.Promo.studio or {} do
			table.insert(out, r)
		end
	end
	return out
end

-- The fixed list's row for exactly this (normalized) code
function PromoRules.find(Config: any, code: string, studio: boolean?): Row?
	for _, r in rows(Config, studio) do
		if r.code == code then
			return r
		end
	end
	return nil
end

-- Is a row open on this UTC day?
function PromoRules.window(row: Row, day: number): string
	local s, e = PromoRules.dayOf(row.starts), PromoRules.dayOf(row.ends)
	if row.starts and (not s or day < s) then
		return "notyet"
	end
	if row.ends and (not e or day > e) then
		return "expired"
	end
	return "live"
end

-- One try. Reasons: "ok" (claimed now), "off", "bad", "unknown", "used", "expired", "notyet". Only "ok"
-- changes the block (promo.codes[code] = day). The caller pays row.piece.
function PromoRules.redeem(Config: any, promo: any, raw: any, day: number, studio: boolean?): Result
	if not Config.Promo.on then
		return { ok = false, reason = "off" }
	end
	local code, why = PromoRules.normalize(Config, raw)
	if not code then
		return { ok = false, reason = why or "bad" }
	end
	local row = PromoRules.find(Config, code :: string, studio)
	if not row then
		return { ok = false, reason = "unknown" }
	end
	if promo.codes[code] ~= nil then
		return { ok = false, reason = "used", row = row }
	end
	local w = PromoRules.window(row :: Row, day)
	if w ~= "live" then
		return { ok = false, reason = w, row = row }
	end
	promo.codes[code] = day
	return { ok = true, reason = "ok", row = row }
end

-- Does this answer count towards the wrong-code wait? (a code we never made, or not a code at all)
function PromoRules.wrong(reason: string): boolean
	return reason == "unknown" or reason == "bad"
end

-- The wrong-code wait: `t` is a player's list of wrong-try times (os.clock). False while `n` wrong tries
-- sit inside the window; the second value is the seconds left.
function PromoRules.canTry(Config: any, t: { number }, now: number): (boolean, number)
	local T = Config.Promo.tries
	local i = 1
	while i <= #t do
		if now - t[i] >= T.window then
			table.remove(t, i)
		else
			i += 1
		end
	end
	if #t >= T.n then
		return false, math.max(0, T.window - (now - t[1]))
	end
	return true, 0
end

function PromoRules.fail(t: { number }, now: number)
	table.insert(t, now)
end

-- The group piece: true once, for a member, while the group id is set (marks it paid)
function PromoRules.group(Config: any, promo: any, member: boolean): boolean
	local G = Config.Promo.group
	if not Config.Promo.on or G.id == 0 or not member or promo.group == 1 then
		return false
	end
	promo.group = 1
	return true
end

-- Problems in Config.Promo (empty = fine). `index` is CreatorRules.index(Config): every reward must be a
-- "drop" piece (earnable, never sold, looks only).
function PromoRules.validate(Config: any, index: any): { string }
	local P = Config.Promo
	local out = {}
	local function piece(name: any, what: string)
		local p = type(name) == "string" and index.byName[name]
		if not p then
			table.insert(out, what .. ": no creator piece " .. tostring(name))
		elseif p.source.kind ~= "drop" then
			table.insert(out, what .. ": " .. name .. " is a " .. p.source.kind .. " piece, not a drop piece")
		end
	end
	if type(P.group.id) ~= "number" or P.group.id < 0 or P.group.id % 1 ~= 0 then
		table.insert(out, "group id must be a whole number (0 = off)")
	end
	piece(P.group.piece, "group")
	local seen = {}
	for _, r in rows(Config, true) do
		local c = r.code
		if type(c) ~= "string" then
			table.insert(out, "a code row has no code")
			continue
		end
		local n = PromoRules.normalize(Config, c)
		if n ~= c then
			table.insert(
				out,
				c .. ": codes are " .. P.minLength .. " to " .. P.maxLength .. " of A-Z and 0-9"
			)
		end
		if seen[c] then
			table.insert(out, c .. ": listed twice")
		end
		seen[c] = true
		piece(r.piece, c)
		if r.starts ~= nil and not PromoRules.dayOf(r.starts) then
			table.insert(out, c .. ": starts is not a YYYY-MM-DD date")
		end
		if r.ends ~= nil and not PromoRules.dayOf(r.ends) then
			table.insert(out, c .. ": ends is not a YYYY-MM-DD date")
		end
		local s, e = PromoRules.dayOf(r.starts), PromoRules.dayOf(r.ends)
		if s and e and e < s then
			table.insert(out, c .. ": ends before it starts")
		end
		if
			r.tag ~= nil and (type(r.tag) ~= "string" or not string.match(r.tag, "^[%w_]+$") or #r.tag > 24)
		then
			table.insert(out, c .. ": tag is letters, digits and _ only, 24 at most")
		end
	end
	return out
end

-- The saved block repaired: group 0 or 1, codes only real code keys with a day number, at most MAX_SAVED
function PromoRules.clean(raw: any): { group: number, codes: { [string]: number } }
	local src = if type(raw) == "table" then raw else {}
	local codes = {}
	local n = 0
	if type(src.codes) == "table" then
		local keys = {}
		for k, v in src.codes do
			if
				type(k) == "string"
				and #k >= 1
				and #k <= SAVED_KEY_MAX
				and not string.find(k, "[^A-Z0-9]")
				and type(v) == "number"
				and v == v
			then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		for _, k in keys do
			if n < MAX_SAVED then
				codes[k] = math.clamp(math.floor(src.codes[k]), 0, 2 ^ 31)
				n += 1
			end
		end
	end
	return { group = if src.group == 1 then 1 else 0, codes = codes }
end

-- What the Settings rows show: the group row (on when an id is set), and how many codes are live today
-- (the code box shows only while one is). Never the codes themselves.
function PromoRules.view(Config: any, promo: any, day: number, studio: boolean?): { [string]: any }
	local P = Config.Promo
	if not P.on then
		return { on = false }
	end
	local live = 0
	for _, r in rows(Config, studio) do
		if PromoRules.window(r, day) == "live" then
			live += 1
		end
	end
	return {
		on = true,
		group = if P.group.id ~= 0
			then { piece = P.group.piece, name = P.group.name, claimed = promo.group == 1 }
			else nil,
		codes = live,
		maxLength = P.maxLength,
	}
end

-- promo_claim: value 1; fields = kind ("group" or "code"), the row's tag (or its code; the fixed list only)
function PromoRules.event(kind: string, row: Row?): (number, { any })
	if kind == "group" or not row then
		return 1, { "group", "group" }
	end
	local r = row :: Row
	return 1, { "code", r.tag or r.code }
end

return PromoRules
