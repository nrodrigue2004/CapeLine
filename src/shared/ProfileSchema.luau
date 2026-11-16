--!strict
-- ProfileSchema: the saved profile (spec: Data model and save rules > Profile, Character, Piece record).
-- Pure, so Lune tests defaults, migrations, repair of bad data and the size budget (60 KB target).
--   default() -> a new profile with one character
--   load(raw) -> migrate an old save to VERSION and repair it (never errors on bad data)
--   clientView(profile) -> what the owner's client sees (Profile.Sync)
-- Every save change bumps VERSION and adds a function to MIGRATIONS[newVersion].
-- Arrays never hold nil (DataStores store JSON): empty equipment and style slots are 0.

local ProfileSchema = {}

ProfileSchema.VERSION = 3
ProfileSchema.SLOTS = 8
ProfileSchema.STYLE_WORDS = 16 -- 512 bits
ProfileSchema.SMALL_WORDS = 4 -- 128 bits for emotes, titles, Rogues File pages, seen flags

local function words(n: number): { number }
	local t = table.create(n, 0)
	return t
end

-- Bitsets as arrays of 32-bit numbers
local Bits = {}
ProfileSchema.Bits = Bits

function Bits.get(w: { number }, i: number): boolean
	local word = w[i // 32 + 1]
	return word ~= nil and bit32.btest(word, bit32.lshift(1, i % 32))
end

function Bits.set(w: { number }, i: number, on: boolean?)
	local k = i // 32 + 1
	if w[k] == nil then
		return
	end
	local mask = bit32.lshift(1, i % 32)
	w[k] = if on == false then bit32.band(w[k], bit32.bnot(mask)) else bit32.bor(w[k], mask)
end

function Bits.list(w: { number }): { number }
	local out = {}
	for k, word in w do
		if word ~= 0 then
			for b = 0, 31 do
				if bit32.btest(word, bit32.lshift(1, b)) then
					table.insert(out, (k - 1) * 32 + b)
				end
			end
		end
	end
	return out
end

function ProfileSchema.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = ProfileSchema.deepCopy(v)
	end
	return out :: any
end

function ProfileSchema.newLoadout(): { [string]: any }
	return { set = "Volt", basic = "ZapBolt", skills = { "ChainLightning", "DashStrike" }, super = nil }
end

function ProfileSchema.newCharacter(side: string?, classId: string?): { [string]: any }
	return {
		side = side or "hero",
		classId = classId or "Blaster",
		level = 1,
		xp = 0,
		bonusPoints = 0, -- story Skill Points from Act 1 choices (M7)
		ranks = { ZapBolt = 1, ChainLightning = 1, DashStrike = 1 },
		mods = {},
		loadouts = { ProfileSchema.newLoadout(), ProfileSchema.newLoadout() },
		loadoutIndex = 1,
		fxStyle = "Comic",
		equipment = words(ProfileSchema.SLOTS), -- piece ids, 0 = empty
		shown = words(ProfileSchema.SLOTS), -- style shown over the slot, 0 = the worn piece's own
		looks = {}, -- creator looks (M9)
		titleId = 0,
		nounId = 0,
		fame = 0,
		rep = { 0, 0, 0 },
		hq = { level = 1 },
		legacy = 0,
		-- story (M7): opening 1 once the playable disaster is done; missions: first clears (bit n - 1);
		-- choices: option picked per Act 1 choice (0 = not yet); quests: per side quest arc, 0 not started,
		-- 1 to 3 the current step, 4 done; pinned: 0 the story, 1 to 8 a side quest; menu: Maribel's pick;
		-- perks: story perks (bit 1 Null Echo)
		story = {
			act = 1,
			flags = words(ProfileSchema.SMALL_WORDS),
			choices = { 0, 0, 0 },
			opening = 0,
			missions = 0,
			quests = { 0, 0, 0, 0, 0, 0, 0, 0 },
			pinned = 0,
			menu = 0,
			perks = 0,
		},
		contracts = {},
		lastSafehouse = 0, -- 0 = none yet: the home safehouse (Config.World.safehouse.homeSafehouse)
		beacons = 0, -- fast-travel beacons discovered, a 12-bit mask (bit id - 1)
		safehouses = 0, -- safehouses visited, a 16-bit mask (respawn choices)
		respecAt = 0, -- os.time() when respec is free again
		secondWindAt = 0,
	}
end

function ProfileSchema.default(): { [string]: any }
	return {
		version = ProfileSchema.VERSION,
		stash = {},
		nextPieceId = 1,
		styles = words(ProfileSchema.STYLE_WORDS),
		emotes = words(ProfileSchema.SMALL_WORDS),
		titles = words(ProfileSchema.SMALL_WORDS),
		rogues = words(ProfileSchema.SMALL_WORDS),
		frames = words(ProfileSchema.SMALL_WORDS), -- Photo Mode frames (M7 quest rewards, M11)
		props = words(ProfileSchema.SMALL_WORDS), -- HQ props (M7 quest rewards, M9)
		currency = { credits = 0, banked = 0, dust = 0 },
		pity = { epic = 0, legendary = 0 },
		characters = { ProfileSchema.newCharacter() },
		active = 1,
		purchases = { passes = {}, receipts = {} },
		settings = { preset = 0, textSize = 1, leftHanded = false, reduceFlashing = false },
		daily = { day = 0, contractsDone = 0 },
		seen = words(ProfileSchema.SMALL_WORDS),
		stats = { playSeconds = 0, bossesJoined = 0, rescues = 0, wins = 0, kills = 0, drops = 0 },
		guard = { kicks = 0, reviewed = 0 }, -- M8: safety kicks on this account (review queue after 2); never a ban
	}
end

-- MIGRATIONS[v] turns a version v - 1 save into version v. Version 0 is any save without a version.
local MIGRATIONS: { [number]: (any) -> () } = {
	[1] = function(_p)
		-- the first saved version: nothing to convert; repair() fills every field
	end,
	[2] = function(p)
		-- M4: beacons and safehouses discovered start empty (repair() adds the fields); a hero who already
		-- had a last safehouse keeps it as visited
		if type(p.characters) == "table" then
			for _, c in p.characters do
				if type(c) == "table" then
					c.beacons = 0
					local last = tonumber(c.lastSafehouse) or 0
					c.safehouses = if last >= 1 and last <= 16 then 2 ^ (last - 1) else 0
				end
			end
		end
	end,
	[3] = function(p)
		-- M7: a hero who already played (level 2+ or any Renown) has done the opening and mission 1, so a
		-- returning player never replays the disaster (repair() adds the new story fields)
		if type(p.characters) == "table" then
			for _, c in p.characters do
				if type(c) == "table" and ((tonumber(c.level) or 1) >= 2 or (tonumber(c.xp) or 0) > 0) then
					if type(c.story) ~= "table" then
						c.story = {}
					end
					c.story.opening = 1
					c.story.missions = 1
				end
			end
		end
	end,
}
ProfileSchema.MIGRATIONS = MIGRATIONS

local function num(v: any, lo: number, hi: number, default: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- Fill missing keys from a template, and replace wrong types with the template's value
local function fill(target: any, template: any)
	for k, v in template do
		local cur = target[k]
		if type(v) == "table" then
			if type(cur) ~= "table" then
				target[k] = ProfileSchema.deepCopy(v)
			elseif #v > 0 or next(v) ~= nil then
				-- arrays of numbers keep their length; maps fill recursively
				if #v > 0 and type(v[1]) == "number" then
					for i = 1, #v do
						if type(cur[i]) ~= "number" then
							cur[i] = v[i]
						end
					end
					for i = #cur, #v + 1, -1 do
						cur[i] = nil
					end
				elseif #v == 0 then
					fill(cur, v)
				end
			end
		elseif type(cur) ~= type(v) then
			target[k] = v
		end
	end
end

local function cleanPiece(p: any, maxId: number): any?
	if type(p) ~= "table" then
		return nil
	end
	local id = num(p.id, 0, 2 ^ 31, 0)
	if id <= 0 then
		return nil
	end
	local bonus = {}
	if type(p.bonus) == "table" then
		for _, b in p.bonus do
			if type(b) == "table" and #bonus < 3 then
				table.insert(bonus, { num(b[1], 1, 5, 1), num(b[2], 0, 65535, 0) })
			end
		end
	end
	return {
		id = id,
		slot = num(p.slot, 1, 8, 1),
		tier = num(p.tier, 1, 6, 1),
		ilvl = num(p.ilvl, 1, 255, 1),
		up = num(p.up, 0, 10, 0),
		main = num(p.main, 0, 65535, 0),
		bonus = bonus,
		set = num(p.set, 0, 255, 0),
		perk = num(p.perk, 0, 255, 0),
		gadget = num(p.gadget, 0, 255, 0),
		style = num(p.style, 0, 511, 0),
		retunes = num(p.retunes, 0, 255, 0),
		seed = num(p.seed, 0, 65535, 0),
	},
		math.max(maxId, id)
end

local function repair(p: any): any
	local d = ProfileSchema.default()
	-- characters are repaired one by one against a fresh character
	local chars = if type(p.characters) == "table" then p.characters else nil
	p.characters = nil
	fill(p, d)
	local cleanChars = {}
	if chars then
		for _, c in chars do
			if type(c) == "table" and #cleanChars < 4 then
				fill(c, ProfileSchema.newCharacter())
				c.level = num(c.level, 1, 40, 1)
				c.xp = num(c.xp, 0, 2 ^ 31, 0)
				c.loadoutIndex = num(c.loadoutIndex, 1, 2, 1)
				c.lastSafehouse = num(c.lastSafehouse, 0, 16, 0)
				c.beacons = num(c.beacons, 0, 4095, 0)
				c.safehouses = num(c.safehouses, 0, 65535, 0)
				local st = c.story
				st.act = num(st.act, 1, 3, 1)
				st.opening = num(st.opening, 0, 1, 0)
				st.missions = num(st.missions, 0, 63, 0)
				st.pinned = num(st.pinned, 0, 8, 0)
				st.menu = num(st.menu, 0, 3, 0)
				st.perks = num(st.perks, 0, 255, 0)
				for i = 1, 3 do
					st.choices[i] = num(st.choices[i], 0, 2, 0)
				end
				for i = 1, 8 do
					st.quests[i] = num(st.quests[i], 0, 4, 0)
				end
				if c.fxStyle ~= "Comic" and c.fxStyle ~= "Anime" then
					c.fxStyle = "Comic"
				end
				for id, r in c.ranks do
					if type(id) ~= "string" or type(r) ~= "number" then
						c.ranks[id] = nil
					else
						c.ranks[id] = num(r, 0, 5, 0)
					end
				end
				table.insert(cleanChars, c)
			end
		end
	end
	if #cleanChars == 0 then
		cleanChars = { ProfileSchema.newCharacter() }
	end
	p.characters = cleanChars
	p.active = num(p.active, 1, #cleanChars, 1)
	-- stash: drop malformed pieces and duplicates, cap the size
	local stash, seenIds, maxId = {}, {}, 0
	for _, raw in p.stash do
		local piece, newMax = cleanPiece(raw, maxId)
		if piece and not seenIds[piece.id] and #stash < 150 then
			seenIds[piece.id] = true
			maxId = newMax :: number
			table.insert(stash, piece)
		end
	end
	p.stash = stash
	p.nextPieceId = math.max(num(p.nextPieceId, 1, 2 ^ 31, 1), maxId + 1)
	-- equipment must point at pieces that exist, in the right slot, worn by one character only
	local worn = {}
	for _, c in p.characters do
		for slot = 1, 8 do
			local id = c.equipment[slot]
			local ok = false
			if id ~= 0 and not worn[id] then
				for _, piece in stash do
					if piece.id == id and piece.slot == slot then
						ok = true
					end
				end
			end
			if ok then
				worn[id] = true
			else
				c.equipment[slot] = 0
			end
		end
	end
	p.currency.credits = num(p.currency.credits, 0, 2 ^ 40, 0)
	p.currency.banked = num(p.currency.banked, 0, 2 ^ 40, 0)
	p.currency.dust = num(p.currency.dust, 0, 2 ^ 40, 0)
	p.pity.epic = num(p.pity.epic, 0, 1000, 0)
	p.pity.legendary = num(p.pity.legendary, 0, 1000, 0)
	if #p.purchases.receipts > 50 then
		local keep = {}
		for i = #p.purchases.receipts - 49, #p.purchases.receipts do
			table.insert(keep, p.purchases.receipts[i])
		end
		p.purchases.receipts = keep
	end
	p.version = ProfileSchema.VERSION
	return p
end

-- Migrate and repair. A save from a newer version (a rollback) is kept as it is, minus repairs.
function ProfileSchema.load(raw: any): { [string]: any }
	if type(raw) ~= "table" then
		return ProfileSchema.default()
	end
	local v = num(raw.version, 0, 1e6, 0)
	for step = v + 1, ProfileSchema.VERSION do
		local fn = MIGRATIONS[step]
		if fn then
			fn(raw)
		end
	end
	return repair(raw)
end

function ProfileSchema.active(profile: any): any
	return profile.characters[profile.active] or profile.characters[1]
end

-- Daily reset at 00:00 UTC
function ProfileSchema.rollDay(profile: any, now: number)
	local day = now // 86400
	if profile.daily.day ~= day then
		profile.daily.day = day
		profile.daily.contractsDone = 0
	end
end

-- The owner's client view (Profile.Sync): stash, styles, wallet, pity and the active character's gear.
-- walletOnly: just the wallet and level (most syncs: rewards and spending), merged into the last full view.
function ProfileSchema.clientView(profile: any, walletOnly: boolean?): { [string]: any }
	local c = ProfileSchema.active(profile)
	if walletOnly then
		return { currency = profile.currency, level = c.level, xp = c.xp }
	end
	return {
		stash = profile.stash,
		styles = Bits.list(profile.styles),
		currency = profile.currency,
		pity = profile.pity,
		equipment = c.equipment,
		shown = c.shown,
		level = c.level,
		xp = c.xp,
		beacons = c.beacons,
		safehouses = c.safehouses,
		lastSafehouse = c.lastSafehouse,
		active = profile.active,
		characters = #profile.characters,
	}
end

return ProfileSchema
