--!strict
-- ProfileSchema: the saved profile (spec: Data model and save rules > Profile, Character, Piece record).
-- Pure, so Lune tests defaults, migrations, repair of bad data and the size budget (60 KB target).
--   default() -> a new profile with one character
--   load(raw) -> migrate an old save to VERSION and repair it (never errors on bad data)
--   clientView(profile) -> what the owner's client sees (Profile.Sync)
-- Every save change bumps VERSION and adds a function to MIGRATIONS[newVersion].
-- Arrays never hold nil (DataStores store JSON): empty equipment and style slots are 0.

local Config = if script
	then require(script.Parent.Parent:WaitForChild("Config"))
	else (require :: any)("../config")

local ProfileSchema = {}

-- The level cap a saved level is repaired to (Config.Stats.levelCap, 50 since 2026-11-17). A save from the
-- 40 cap is already in range, so raising the cap needs no migration.
ProfileSchema.LEVEL_CAP = Config.Stats.levelCap

ProfileSchema.VERSION = 11
ProfileSchema.BOSSES = 3 -- #Config.Boss.order (a test checks they match)
ProfileSchema.SLOTS = 8
ProfileSchema.STYLE_WORDS = 16 -- 512 bits
ProfileSchema.SMALL_WORDS = 4 -- 128 bits for emotes, titles, Rogues File pages, seen flags
ProfileSchema.PIECE_WORDS = 40 -- 1,280 bits: creator pieces unlocked (M9; 32 since the 2026-11-16 creator plan, 40 since the
-- 2026-11-17 classic clothes and faces; repair pads an older save with 0)
ProfileSchema.LOOK_WORDS = 32 -- a 128-byte look record (LookCodec v2; an 8-word v1 record pads with 0 and still reads)
ProfileSchema.WEAPON_WORDS = 2 -- 64 bits: weapons owned (Config.Weapons ids)
-- a weapon's saved state: mastery points, style, finish, main, trim and glow colour, glow strength, emblem, trail
ProfileSchema.WEAPON_FIELDS =
	{ "mastery", "style", "finish", "main", "trim", "glow", "glowLevel", "emblem", "trail" }

-- The archetypes, the 17 paths (Config.Classes, Config.Abilities.sets) and the mobilities (Config.Move.mobility)
ProfileSchema.ARCHETYPES = { "Elemental", "Rogue", "Powerhouse", "Mystic" }
ProfileSchema.PATHS = {
	"Volt",
	"Frost",
	"Fire",
	"Earth",
	"Tide",
	"Blade",
	"Gunslinger",
	"Gadgeteer",
	"Shadow",
	"Titan",
	"Martial",
	"Juggernaut",
	"Colossus",
	"Pulse",
	"Mind",
	"Spirit",
	"Light",
}
-- each path's archetype, in PATHS order (5, 4, 4, 4)
local PATH_ARCH = {}
for i, path in ProfileSchema.PATHS do
	PATH_ARCH[path] = if i <= 5
		then "Elemental"
		elseif i <= 9 then "Rogue"
		elseif i <= 13 then "Powerhouse"
		else "Mystic"
end
ProfileSchema.PATH_ARCH = PATH_ARCH
ProfileSchema.MOBILITIES = { "flight", "speed", "leap", "acrobat", "swing" }
local RENAMED = { Bruiser = "Powerhouse", Blaster = "Elemental", Speedster = "Rogue", Controller = "Mystic" }

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
		classId = classId or "Elemental",
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
		-- the creator (M9): look is a 32-byte LookCodec record (all 0 = the default look); looks are the saved
		-- looks on the HQ mannequins (up to 4); titleId and nounId name the hero ("Storm Falcon"); created is 1
		-- once the creator's Done was pressed; startSet is the creator's starting set (Volt or Blade)
		look = words(ProfileSchema.LOOK_WORDS),
		looks = {},
		titleId = 0,
		nounId = 0,
		created = 0,
		startSet = "Volt", -- the main path (nate 2026-11-16: archetype, path, mobility)
		mobility = "flight", -- swapped free at any safehouse
		weapon = 0, -- the carried weapon (Config.Weapons id), 0 = Bare Fists
		pathChanged = 0, -- 1 once the free archetype or path change (before level 10) is used
		-- lore step 2: how the Spark woke (Config.Creator.origins index, 0 = not picked yet; picked in the
		-- creator, changed there free); a title and one look piece, never a stat
		origin = 0,
		tint = 0, -- an owned effect colour (Config.Shop.tints), 0 = the set's own
		landing = 0, -- an owned landing pose (emote bit 20 to 31), 0 = none
		fame = 0,
		rep = { 0, 0, 0 },
		hq = { level = 1, trophies = {}, droneAt = 0 }, -- droneAt: os.time() of the last leave (offline drones)
		legacy = 0,
		-- story (M7): opening 1 once the playable disaster is done; missions: first clears (bit n - 1);
		-- choices: option picked per Act 1 choice (0 = not yet); pinned: 0 the story, else the side quest chain
		-- tracked (its Config.SideQuests bit); perks: story perks (bit 1 the Echo Drone; key NullEcho)
		story = {
			act = 1,
			flags = words(ProfileSchema.SMALL_WORDS),
			choices = { 0, 0, 0 },
			opening = 0,
			missions = 0,
			pinned = 0,
			perks = 0,
		},
		-- side quests (lore step 10, Shared.SideQuestPlan): at[chain id] = the current step of a chain in
		-- progress; done = chains finished (bit = the chain's Config.SideQuests bit); retired = the 8 arcs before
		-- step 10 this hero finished (bit n - 1); owed = Credits for finished steps of arcs left in progress,
		-- paid once with the retired arcs' unlocks (settled = 1 after)
		sq = { at = {}, done = words(ProfileSchema.SMALL_WORDS), retired = 0, owed = 0, settled = 1 },
		contracts = {},
		lastSafehouse = 0, -- 0 = none yet: the home safehouse (Config.World.safehouse.homeSafehouse)
		beacons = 0, -- fast-travel beacons discovered, a 12-bit mask (bit id - 1)
		safehouses = 0, -- safehouses visited, a 16-bit mask (respawn choices)
		respecAt = 0, -- os.time() when respec is free again
		secondWindAt = 0,
		-- Hero MMO features (H4 on): tfWeek = the week number (TaskForcePlan.week) of each task force's last
		-- clear, for the weekly double Renown
		mmo = {
			tfWeek = { 0, 0, 0, 0 },
			-- H5: the current nemesis (seed 0 = not made yet), banes = seeds of the ones you beat (titles,
			-- the newest 8), cores = Nemesis Cores (a collection item), heads = trophies for the HQ wall
			nemesis = { seed = 0, rank = 1, traits = 0, met = 0, intel = 0, readyAt = 0 },
			banes = {},
			cores = 0,
			heads = 0,
			-- H6: mentor = index in Config.Mentors.list (0 = not picked), mentorSeen = panel moment bits,
			-- mentorParts = quest parts finished per mentor, mentorCount = the open part's goal counts,
			-- mentorLook = the mentor whose look you wear (0 = none)
			mentor = 0,
			mentorSeen = 0,
			mentorParts = { 0, 0, 0, 0 },
			mentorCount = { 0, 0 },
			mentorLook = 0,
			-- H7: the title shown under your name (0 = your origin's; Shared.BadgeRules ids)
			title = 0,
			aura = 0, -- the accolade aura and plate trim worn (Config.Badges.groups index; 0 = none)
			trim = 0, -- (H8: 100 + n a Hero Pass trim, Config.Pass.trims)
			-- H8: the travel style worn per mobility (Config.Move.mobilityOrder; slot 1 to 6, 0 = plain)
			travel = { 0, 0, 0, 0, 0 },
		},
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
		purchases = { passes = {}, receipts = {}, slots = 0, tints = 0 }, -- slots, tints: a bit per slot or tint
		pieces = words(ProfileSchema.PIECE_WORDS), -- creator pieces unlocked (CreatorRules ids)
		-- weapons (2026-11-16 creator plan): owned for the account (Rack, creator pick or Robux for the Exotic
		-- ones); weapons[id as text] = the WEAPON_FIELDS numbers (mastery and the weapon's look)
		weaponsOwned = words(ProfileSchema.WEAPON_WORDS),
		weapons = {},
		legends = {}, -- the Hall of Legends: retired heroes' statues (HqRules.retire)
		bosses = { 0, 0, 0 }, -- best world boss reward tier per boss (Config.Boss.order): 1 joined, 2, 3 MVP
		shop = { starterSeen = 0 }, -- the starter pack offer was shown (once)
		settings = {}, -- M10: { [key id] = number } (SettingsRules.clean fills and fixes it on load)
		mutes = {}, -- M10: muted user ids (the mute list), at most Config.Settings.maxMutes
		-- M12 analytics: the furthest Opening funnel step logged (the onboarding funnel counts once per
		-- account), the first join (os.time) and whether the day-1 return was logged
		analytics = { onboard = 0, firstSeen = 0, d1 = 0 },
		-- the studio-wide FunnelKit's numbers (FunnelKit.blank(): sessions, furthest stage, times, play time);
		-- server only, never in the client view
		funnel = { sessions = 0, stage = 0, firstAt = 0, lastAt = 0, sessionAt = 0, hopAt = 0, played = 0 },
		daily = { day = 0, contractsDone = 0 },
		seen = words(ProfileSchema.SMALL_WORDS),
		stats = {
			playSeconds = 0,
			bossesJoined = 0,
			rescues = 0,
			wins = 0,
			kills = 0,
			drops = 0,
			contracts = 0,
			mvps = 0,
		},
		guard = { kicks = 0, reviewed = 0 }, -- M8: safety kicks on this account (review queue after 2); never a ban
		-- Hero MMO features on the account (H7): badges = 256 badge bits, counts = the counters badges read
		-- (kills by kind, blocks, throws, ...), collect = 128 collection item bits, scanner = the HQ Scanner
		-- bought (1), contest = contest wins and the last win (os.time; a win at most once an hour)
		mmo = {
			badges = words(8),
			counts = {},
			collect = words(4),
			scanner = 0,
			contest = { wins = 0, lastWin = 0 },
			travel = words(1), -- H8: travel styles owned from the shop and the pass (Config.TravelStyles ids)
		},
		-- H8: the Hero Pass (Shared.PassRules): season, xp, paid = the season's paid track (from a receipt),
		-- claimed = tier bits per track, day = the last daily first-win bonus (UTC day), titles and trims =
		-- pass looks kept forever (Config.Pass.titles / trims)
		pass = {
			season = 0,
			xp = 0,
			paid = false,
			claimed = { free = words(2), paid = words(2) },
			day = 0,
			titles = words(1),
			trims = words(1),
		},
		-- H8: this week's episode: week (PassRules.week), steps = done bits, counts per step, intro = the week
		-- whose panels were shown
		episode = { week = 0, steps = 0, counts = { 0, 0, 0, 0 }, intro = 0 },
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
	[4] = function(_p)
		-- M9: the creator, HQ, shop and Legacy fields start empty (repair() adds them); a hero made before the
		-- creator keeps created = 0, so the creator opens once on its next join to pick a name and look
	end,
	[5] = function(_p)
		-- M10: settings become numbers per key and the mute list is saved; SettingsRules.clean turns an old
		-- settings table (textSize as a 1 to 1.6 scale, booleans) into the new one on load
	end,
	[6] = function(_p)
		-- M12: analytics (onboarding step, first join, day-1 return); repair() fills it
	end,
	[7] = function(p)
		-- archetypes (nate 2026-11-16): the 4 classes become archetypes; a Speedster keeps its speed as the
		-- Super-speed mobility, everyone else starts with Flight (repair() fills mobility and pathChanged)
		local function rename(t: any)
			if type(t) == "table" and type(t.classId) == "string" and RENAMED[t.classId] then
				if t.classId == "Speedster" and t.mobility == nil then
					t.mobility = "speed"
				end
				t.classId = RENAMED[t.classId]
			end
		end
		for _, list in { p.characters, p.legends } do
			if type(list) == "table" then
				for _, c in list do
					rename(c)
				end
			end
		end
	end,
	[8] = function(_p)
		-- the studio-wide funnels (FunnelKit): repair() fills the funnel numbers
	end,
	[9] = function(_p)
		-- the hero creator plan (2026-11-16): looks grow to 32 words (old 8-word looks still read), the piece
		-- bitset to 32 words, weapons owned and each weapon's mastery and look; repair() pads and fills them
	end,
	[10] = function(p)
		-- nate's lore, build plan step 2: every character has an origin; a hero saved before origins gets the
		-- default (Config.Creator.originDefault) and may pick another in the creator for free
		if type(p.characters) == "table" then
			for _, c in p.characters do
				if type(c) == "table" and (tonumber(c.origin) or 0) == 0 then
					c.origin = Config.Creator.originDefault
				end
			end
		end
	end,
	[11] = function(p)
		-- nate's lore, build plan step 10: the 8 side quest arcs are retired for the side quest chains. A
		-- finished arc becomes a retired bit (its unlocks are kept and set once by SideQuestPlan.settle); an
		-- arc in progress leaves Credits for its finished steps; the old quest list, pin and menu pick go.
		local R = Config.SideQuests.retired
		if type(p.characters) == "table" then
			for _, c in p.characters do
				if type(c) == "table" then
					local st = if type(c.story) == "table" then c.story else {}
					local retired, owed = 0, 0
					if type(st.quests) == "table" then
						for arc = 1, R.arcs do
							local s = tonumber(st.quests[arc]) or 0
							if s >= 4 then
								retired += 2 ^ (arc - 1)
							elseif s >= 2 then
								owed += (math.floor(s) - 1) * R.stepCredits
							end
						end
					end
					st.quests = nil
					st.menu = nil
					st.pinned = 0
					c.sq = { at = {}, retired = retired, owed = owed, settled = 0 }
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

-- A list of whole numbers in [lo, hi], at most n long (pad: exactly n, missing ones 0)
local function cleanNumbers(list: any, n: number, lo: number, hi: number, pad: boolean?): { number }
	local out = {}
	if type(list) == "table" then
		for i = 1, n do
			local v = list[i]
			if type(v) == "number" and v == v and v >= lo and v <= hi then
				table.insert(out, math.floor(v))
			elseif pad then
				table.insert(out, 0)
			end
		end
	end
	if pad then
		for i = #out + 1, n do
			out[i] = 0
		end
	end
	return out
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
				c.level = num(c.level, 1, ProfileSchema.LEVEL_CAP, 1)
				c.xp = num(c.xp, 0, 2 ^ 31, 0)
				c.loadoutIndex = num(c.loadoutIndex, 1, 2, 1)
				c.lastSafehouse = num(c.lastSafehouse, 0, 16, 0)
				c.beacons = num(c.beacons, 0, 4095, 0)
				c.safehouses = num(c.safehouses, 0, 65535, 0)
				local st = c.story
				st.act = num(st.act, 1, 3, 1)
				st.opening = num(st.opening, 0, 1, 0)
				st.missions = num(st.missions, 0, 63, 0)
				st.perks = num(st.perks, 0, 255, 0)
				for i = 1, 3 do
					st.choices[i] = num(st.choices[i], 0, 2, 0)
				end
				st.quests, st.menu = nil, nil -- the retired arcs (lore step 10)
				-- side quests: only known chains in progress at a real step; the pin only on one of them
				local sq = c.sq
				sq.retired = num(sq.retired, 0, 2 ^ Config.SideQuests.retired.arcs - 1, 0)
				sq.owed = num(sq.owed, 0, 1e7, 0)
				sq.settled = num(sq.settled, 0, 1, 1)
				local at = {}
				for _, chain in Config.SideQuests.chains do
					local s = sq.at[chain.id]
					if
						type(s) == "number"
						and s >= 1
						and s <= #chain.steps
						and not Bits.get(sq.done, chain.bit)
					then
						at[chain.id] = math.floor(s)
					end
				end
				sq.at = at
				st.pinned = num(st.pinned, 0, ProfileSchema.SMALL_WORDS * 32 - 1, 0)
				if st.pinned > 0 then
					local tracked = false
					for _, chain in Config.SideQuests.chains do
						if chain.bit == st.pinned and at[chain.id] then
							tracked = true
						end
					end
					if not tracked then
						st.pinned = 0
					end
				end
				if c.fxStyle ~= "Comic" and c.fxStyle ~= "Anime" then
					c.fxStyle = "Comic"
				end
				c.titleId = num(c.titleId, 0, 64, 0)
				c.nounId = num(c.nounId, 0, 64, 0)
				c.created = num(c.created, 0, 1, 0)
				c.legacy = num(c.legacy, 0, 255, 0)
				c.tint = num(c.tint, 0, 31, 0)
				c.landing = num(c.landing, 0, 31, 0)
				c.fame = num(c.fame, 0, 2 ^ 31, 0)
				if not table.find(ProfileSchema.PATHS, c.startSet) then
					c.startSet = "Volt"
				end
				-- the path decides the archetype (a pre-archetype Bruiser who started on Volt is an Elemental now)
				c.classId = PATH_ARCH[c.startSet]
				if not table.find(ProfileSchema.MOBILITIES, c.mobility) then
					c.mobility = "flight"
				end
				c.pathChanged = num(c.pathChanged, 0, 1, 0)
				c.origin = num(c.origin, 0, 1e6, 0)
				if not Config.Creator.origins[c.origin] then
					c.origin = 0 -- not an origin: not picked yet
				end
				if c.origin == 0 and c.created == 1 then
					c.origin = Config.Creator.originDefault -- a made hero always has one
				end
				c.weapon = num(c.weapon, 0, 64, 0)
				c.hq.level = num(c.hq.level, 1, 6, 1)
				c.hq.droneAt = num(c.hq.droneAt, 0, 2 ^ 40, 0)
				c.hq.trophies = cleanNumbers(c.hq.trophies, 12, 1, 64)
				c.mmo.tfWeek = cleanNumbers(c.mmo.tfWeek, 4, 0, 2 ^ 20, true)
				local nm = c.mmo.nemesis
				nm.seed = num(nm.seed, 0, 2 ^ 32, 0)
				nm.rank = num(nm.rank, 1, 5, 1)
				nm.traits = num(nm.traits, 0, 31, 0)
				nm.met = num(nm.met, 0, 255, 0)
				nm.intel = num(nm.intel, 0, 3, 0)
				nm.readyAt = num(nm.readyAt, 0, 2 ^ 40, 0)
				c.mmo.banes = cleanNumbers(c.mmo.banes, 8, 0, 2 ^ 32)
				c.mmo.cores = num(c.mmo.cores, 0, 65535, 0)
				c.mmo.heads = num(c.mmo.heads, 0, 65535, 0)
				c.mmo.mentor = num(c.mmo.mentor, 0, 4, 0)
				c.mmo.mentorSeen = num(c.mmo.mentorSeen, 0, 2 ^ 16, 0)
				c.mmo.mentorParts = cleanNumbers(c.mmo.mentorParts, 4, 0, 4, true)
				c.mmo.mentorCount = cleanNumbers(c.mmo.mentorCount, 2, 0, 1000, true)
				c.mmo.mentorLook = num(c.mmo.mentorLook, 0, 4, 0)
				c.mmo.title = num(c.mmo.title, 0, 65535, 0)
				c.mmo.aura = num(c.mmo.aura, 0, 16, 0)
				c.mmo.trim = num(c.mmo.trim, 0, 131, 0)
				c.mmo.travel = cleanNumbers(c.mmo.travel, 5, 0, 6, true)
				local looks = {}
				for _, l in c.looks do
					if type(l) == "table" and #looks < 4 then
						table.insert(looks, cleanNumbers(l, ProfileSchema.LOOK_WORDS, 0, 2 ^ 32 - 1, true))
					end
				end
				c.looks = looks
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
	p.purchases.slots = num(p.purchases.slots, 0, 31, 0)
	p.purchases.tints = num(p.purchases.tints, 0, 2 ^ 31, 0)
	for i = 1, ProfileSchema.BOSSES do -- an older save gets 0 for a boss added since (the Leviathan Engine)
		p.bosses[i] = num(p.bosses[i], 0, 3, 0)
	end
	p.shop.starterSeen = num(p.shop.starterSeen, 0, 1, 0)
	-- H7: badges, counters, collections
	p.mmo.badges = cleanNumbers(p.mmo.badges, 8, 0, 2 ^ 32 - 1, true)
	p.mmo.collect = cleanNumbers(p.mmo.collect, 4, 0, 2 ^ 32 - 1, true)
	local counts, nCounts = {}, 0
	for k, v in p.mmo.counts do
		if type(k) == "string" and #k <= 40 and type(v) == "number" and v == v and nCounts < 200 then
			counts[k] = math.clamp(math.floor(v), 0, 2 ^ 31)
			nCounts += 1
		end
	end
	p.mmo.counts = counts
	p.mmo.scanner = num(p.mmo.scanner, 0, 1, 0)
	p.mmo.contest.wins = num(p.mmo.contest.wins, 0, 2 ^ 31, 0)
	p.mmo.contest.lastWin = num(p.mmo.contest.lastWin, 0, 2 ^ 40, 0)
	-- H8: travel styles, the Hero Pass, the episode
	p.mmo.travel = cleanNumbers(p.mmo.travel, 1, 0, 2 ^ 32 - 1, true)
	local pass = p.pass
	pass.season = num(pass.season, 0, 65535, 0)
	pass.xp = num(pass.xp, 0, 2 ^ 31, 0)
	pass.paid = pass.paid == true
	pass.claimed.free = cleanNumbers(pass.claimed.free, 2, 0, 2 ^ 32 - 1, true)
	pass.claimed.paid = cleanNumbers(pass.claimed.paid, 2, 0, 2 ^ 32 - 1, true)
	pass.day = num(pass.day, 0, 2 ^ 31, 0)
	pass.titles = cleanNumbers(pass.titles, 1, 0, 2 ^ 32 - 1, true)
	pass.trims = cleanNumbers(pass.trims, 1, 0, 2 ^ 32 - 1, true)
	local ep = p.episode
	ep.week = num(ep.week, 0, 2 ^ 31, 0)
	ep.steps = num(ep.steps, 0, 15, 0)
	ep.counts = cleanNumbers(ep.counts, 4, 0, 100000, true)
	ep.intro = num(ep.intro, 0, 2 ^ 31, 0)
	p.stats.contracts = num(p.stats.contracts, 0, 2 ^ 31, 0)
	p.stats.mvps = num(p.stats.mvps, 0, 2 ^ 31, 0)
	local receipts = {}
	for _, r in p.purchases.receipts do
		if type(r) == "string" and #r <= 64 then
			table.insert(receipts, r)
		end
	end
	p.purchases.receipts = receipts
	for k, v in p.purchases.passes do
		if type(k) ~= "string" or v ~= true then
			p.purchases.passes[k] = nil
		end
	end
	-- weapons: keys are weapon ids as text ("1" to "64"), each the WEAPON_FIELDS numbers
	local weapons = {}
	for k, v in p.weapons do
		local id = tonumber(k)
		if id and id % 1 == 0 and id >= 1 and id <= 64 and type(v) == "table" then
			local nums = cleanNumbers(v, #ProfileSchema.WEAPON_FIELDS, 0, 2 ^ 24, true)
			weapons[tostring(id)] = nums
		end
	end
	p.weapons = weapons
	local legends = {}
	for _, l in p.legends do
		if type(l) == "table" and #legends < 20 then
			table.insert(legends, {
				look = cleanNumbers(l.look, ProfileSchema.LOOK_WORDS, 0, 2 ^ 32 - 1, true),
				titleId = num(l.titleId, 0, 64, 0),
				nounId = num(l.nounId, 0, 64, 0),
				classId = if type(l.classId) == "string" then string.sub(l.classId, 1, 24) else "Elemental",
				side = if l.side == "villain" then "villain" else "hero",
				level = num(l.level, 1, ProfileSchema.LEVEL_CAP, ProfileSchema.LEVEL_CAP),
				rank = num(l.rank, 1, 255, 1),
				at = num(l.at, 0, 2 ^ 40, 0),
			})
		end
	end
	p.legends = legends
	if #p.purchases.receipts > 50 then
		local keep = {}
		for i = #p.purchases.receipts - 49, #p.purchases.receipts do
			table.insert(keep, p.purchases.receipts[i])
		end
		p.purchases.receipts = keep
	end
	p.mutes = cleanNumbers(p.mutes, 50, 1, 2 ^ 53)
	local an = if type(p.analytics) == "table" then p.analytics else {}
	p.analytics = {
		onboard = num(an.onboard, 0, 32, 0),
		firstSeen = num(an.firstSeen, 0, 2 ^ 40, 0),
		d1 = num(an.d1, 0, 1, 0),
	}
	local fu = if type(p.funnel) == "table" then p.funnel else {}
	p.funnel = {
		sessions = num(fu.sessions, 0, 2 ^ 31, 0),
		stage = num(fu.stage, 0, 255, 0),
		firstAt = num(fu.firstAt, 0, 2 ^ 40, 0),
		lastAt = num(fu.lastAt, 0, 2 ^ 40, 0),
		sessionAt = num(fu.sessionAt, 0, 2 ^ 40, 0),
		hopAt = num(fu.hopAt, 0, 2 ^ 40, 0),
		played = num(fu.played, 0, 2 ^ 40, 0),
	}
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

-- Every character in short (the slot picker): side, class, level, name ids, Legacy rank
function ProfileSchema.roster(profile: any): { any }
	local out = {}
	for i, c in profile.characters do
		out[i] = {
			side = c.side,
			classId = c.classId,
			level = c.level,
			titleId = c.titleId,
			nounId = c.nounId,
			legacy = c.legacy,
			created = c.created,
			look = c.look,
			origin = c.origin,
		}
	end
	return out
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
		-- M9: the creator, HQ and shops
		pieces = Bits.list(profile.pieces),
		weaponsOwned = Bits.list(profile.weaponsOwned),
		weapons = profile.weapons,
		weapon = c.weapon,
		emotes = Bits.list(profile.emotes),
		titles = Bits.list(profile.titles),
		props = Bits.list(profile.props),
		tints = profile.purchases.tints,
		slots = profile.purchases.slots,
		passes = profile.purchases.passes,
		look = c.look,
		looks = c.looks,
		titleId = c.titleId,
		nounId = c.nounId,
		created = c.created,
		startSet = c.startSet,
		mobility = c.mobility,
		pathChanged = c.pathChanged,
		origin = c.origin,
		tint = c.tint,
		landing = c.landing,
		legacy = c.legacy,
		hq = { level = c.hq.level, trophies = c.hq.trophies },
		legends = profile.legends,
		roster = ProfileSchema.roster(profile),
		stats = profile.stats,
		settings = profile.settings, -- M10
		mutes = profile.mutes,
		-- H8: travel styles, the Hero Pass, the episode (PassHud, TravelStyleFx, the shop)
		travelOwned = Bits.list(profile.mmo.travel),
		travel = c.mmo.travel,
		passSeason = profile.pass.season,
		passPaid = profile.pass.paid,
		-- lore step 7: the scenes seen on this save (CinemaPlan bits: a seen scene may be skipped)
		seen = Bits.list(profile.seen),
	}
end

return ProfileSchema
