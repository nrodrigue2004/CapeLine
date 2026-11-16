--!strict
-- HqRules: the Hero HQ, offline drones, trophies and Legacy rebirth (spec: Hero HQ; Legacy rebirth;
-- Economy > Sinks "HQ levels"). Pure, so Lune tests it.
-- * cell(slot): where a hero's solo HQ cell is (one per hero slot, far above the map).
-- * upgradeCost(level), and what each level opens (mannequins, dummies, boss sim, trophies, drones).
-- * drones(level, awaySeconds): offline Credits, 8 hours at most.
-- * trophies(profile): the trophies this account has earned (shown on the wall, 3 or 12 picked).
-- * canRetire / retire: Legacy at level 40. The hero becomes a statue; the slot restarts at level 1 and keeps
--   every unlock (account-wide already), reputation, Fame, story, beacons and its HQ; gear goes back to the
--   stash (wearable again at item level minus 5, the existing equip slack).

local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")
local StoryPlan = if script then require(script.Parent.StoryPlan) else (require :: any)("./StoryPlan")
local PvpRules = if script then require(script.Parent.PvpRules) else (require :: any)("./PvpRules")
local AbilityRules = if script
	then require(script.Parent.AbilityRules)
	else (require :: any)("./AbilityRules")

local Bits = ProfileSchema.Bits

local HqRules = {}

function HqRules.cell(Config: any, slot: number): (number, number, number)
	local c = Config.Hq.cell
	local i = math.max(slot, 1) - 1
	return c.x0 + (i % c.perRow) * c.gap, c.y, c.z0 + (i // c.perRow) * c.gap
end

-- Which cell a point is in (any slot), or nil
function HqRules.cellAt(Config: any, x: number, y: number, z: number): number?
	local c = Config.Hq.cell
	if y < c.y - 60 or y > c.y + 200 then
		return nil
	end
	local col = math.floor((x - c.x0) / c.gap + 0.5)
	local row = math.floor((z - c.z0) / c.gap + 0.5)
	if col < 0 or col >= c.perRow or row < 0 then
		return nil
	end
	local cx, cz = c.x0 + col * c.gap, c.z0 + row * c.gap
	if math.abs(x - cx) > c.size / 2 + 10 or math.abs(z - cz) > c.size / 2 + 10 then
		return nil
	end
	return row * c.perRow + col + 1
end

HqRules.MAX_LEVEL = 6

-- Credits to go from `level` to level + 1 (nil at the top)
function HqRules.upgradeCost(Config: any, level: number): number?
	return Config.Economy.hqLevels[level]
end

local function at(list: { number }, level: number): number
	return list[math.min(level, #list)]
end

function HqRules.mannequins(Config: any, level: number): number
	return at(Config.Hq.levels.mannequins, level)
end

function HqRules.dummies(Config: any, level: number): number
	return at(Config.Hq.levels.trainingDummies, level)
end

function HqRules.bossSim(Config: any, level: number): boolean
	return level >= Config.Hq.levels.bossSim
end

function HqRules.trophySlots(Config: any, level: number): number
	return at(Config.Hq.levels.trophies, level)
end

function HqRules.mvpCards(Config: any, level: number): boolean
	return level >= Config.Hq.levels.mvpCards
end

function HqRules.dronesOn(Config: any, level: number): boolean
	return level >= Config.Hq.levels.drones
end

function HqRules.dronePerMinute(Config: any, level: number): number
	local best = 0
	for lv, rate in Config.Hq.drones.perMinute do
		if level >= lv and rate > best then
			best = rate
		end
	end
	return best
end

-- Offline drone Credits for time away (whole minutes, capped at 8 hours)
function HqRules.drones(Config: any, level: number, awaySeconds: number): number
	if not HqRules.dronesOn(Config, level) or awaySeconds <= 0 then
		return 0
	end
	local minutes = math.min(awaySeconds, Config.Hq.drones.capHours * 3600) // 60
	return minutes * HqRules.dronePerMinute(Config, level)
end

-- Trophies earned by this account (ids from Config.Hq.trophies)
function HqRules.trophies(Config: any, profile: any): { [string]: boolean }
	local s = profile.stats
	local out: { [string]: boolean } = {}
	local maxLevel, maxFame, maxRep, quests, act1 = 0, 0, 0, 0, false
	for _, c in profile.characters do
		maxLevel = math.max(maxLevel, c.level or 1)
		maxFame = math.max(maxFame, PvpRules.fameRank(Config, c.fame or 0))
		for i = 1, 3 do
			maxRep = math.max(maxRep, StoryPlan.repRank(Config, c.rep[i] or 0))
		end
		local done = 0
		for _, q in c.story.quests do
			if q == 4 then
				done += 1
			end
		end
		quests = math.max(quests, done)
		if StoryPlan.cleared(c.story, #Config.Story.missions) then
			act1 = true
		end
	end
	for _, l in profile.legends do
		maxLevel = math.max(maxLevel, l.level or 0)
	end
	out.firstBoss = (s.bossesJoined or 0) >= 1
	out.bossMvp = (s.mvps or 0) >= 1
	out.act1 = act1
	out.allQuests = quests >= #Config.Story.quests
	out.level20 = maxLevel >= 20
	out.level40 = maxLevel >= 40
	out.legacy1 = #profile.legends >= 1
	out.fame5 = maxFame >= 5
	out.fame10 = maxFame >= 10
	out.rescues100 = (s.rescues or 0) >= 100
	out.contracts50 = (s.contracts or 0) >= 50
	out.repMax = maxRep >= 5
	out.pvp10 = (s.wins or 0) >= 10
	out.styles50 = #Bits.list(profile.styles) >= 50
	return out
end

-- Pick trophies for the wall: earned ones only, no repeats, at most the level's slots
function HqRules.pickTrophies(Config: any, profile: any, level: number, picks: { number }): { number }
	local earned = HqRules.trophies(Config, profile)
	local out, seen = {}, {}
	for _, i in picks do
		local t = Config.Hq.trophies[i]
		if t and earned[t.id] and not seen[i] and #out < HqRules.trophySlots(Config, level) then
			seen[i] = true
			table.insert(out, i)
		end
	end
	return out
end

-- City reputation rank -> HQ prop bits to unlock
function HqRules.cityProps(Config: any, cityRank: number): { number }
	local out = {}
	for _, row in Config.Hq.cityProps do
		if cityRank >= row.rank then
			table.insert(out, row.prop)
		end
	end
	return out
end

-- Legacy
function HqRules.canRetire(Config: any, char: any): (boolean, string?)
	if (char.level or 1) < Config.Hq.legacy.level then
		return false, "level"
	end
	return true, nil
end

-- Retire the character: returns the statue record. The character restarts at level 1 in place.
function HqRules.retire(Config: any, profile: any, charIndex: number, now: number): any?
	local c = profile.characters[charIndex]
	if not c or not HqRules.canRetire(Config, c) then
		return nil
	end
	local statue = {
		look = table.clone(c.look),
		titleId = c.titleId,
		nounId = c.nounId,
		classId = c.classId,
		side = c.side,
		level = c.level,
		rank = (c.legacy or 0) + 1,
		at = now,
	}
	table.insert(profile.legends, statue)
	while #profile.legends > Config.Hq.legacy.statues do
		table.remove(profile.legends, 1)
	end
	local fresh = ProfileSchema.newCharacter(c.side, c.classId)
	-- kept: who the hero is, reputation, Fame, story, the map, HQ, looks, tint and landing pose
	for _, key in
		{
			"side",
			"classId",
			"look",
			"looks",
			"titleId",
			"nounId",
			"fxStyle",
			"startSet",
			"fame",
			"rep",
			"hq",
			"story",
			"bonusPoints",
			"beacons",
			"safehouses",
			"lastSafehouse",
			"tint",
			"landing",
			"created",
		}
	do
		fresh[key] = c[key]
	end
	-- a new run starts on its own starting set with fresh ranks
	local ranks, loadout = AbilityRules.starter(Config, c.startSet or "Volt")
	fresh.ranks = ranks
	fresh.loadouts = { loadout, table.clone(loadout) }
	fresh.loadouts[2].skills = table.clone(loadout.skills)
	fresh.legacy = math.min((c.legacy or 0) + 1, 255)
	profile.characters[charIndex] = fresh
	return statue
end

-- Legacy's Renown bonus (+10% a rank, max 5 ranks); the frame keeps growing past 5
function HqRules.legacyBonus(Config: any, ranks: number): number
	local b = Config.Economy.bonus
	return math.min(ranks * b.legacyEach, b.legacyMax)
end

return HqRules
