--!strict
-- Progress: levels, Renown and earnings (spec: Levels; Earn formulas; Currencies). Pure.
--   xpToNext(L) = round(100 x 1.12^(L - 1)), so level 40 takes about 68,400 Renown in all; from 40 to the
--   cap (Config.Stats.levelCap, 50) each step grows by Economy.levels.lateGrowth (3%), about 156,000 in all.
--   earn(config, action, zoneLevel, bonus) -> credits, renown (bonuses multiply, capped at x4)
--   spend(currency, cost) takes Credits on hand first, then banked; false when short.

local Progress = {}

function Progress.xpToNext(config: any, level: number): number
	local lv = config.Economy.levels
	if lv.lateFrom and level >= lv.lateFrom then
		-- the endgame band (40 to the cap): each step is lateGrowth x the step before (levels 39 to 40)
		return math.floor(
			lv.base * lv.growth ^ (lv.lateFrom - 2) * lv.lateGrowth ^ (level - lv.lateFrom + 1) + 0.5
		)
	end
	return math.floor(lv.base * lv.growth ^ (level - 1) + 0.5)
end

function Progress.totalTo(config: any, level: number): number
	local sum = 0
	for l = 1, level - 1 do
		sum += Progress.xpToNext(config, l)
	end
	return sum
end

-- The rookie boost (list-combat 2026-11-20, nate: the first 30 minutes matter most: level 5 and a new power by
-- about 15 minutes, the first mobility rank by about 20): Renown counts this many times over while the hero is
-- below the levels in Config.Economy.rookie.renown (1 from there on). Earned only, the same for everyone.
function Progress.rookie(config: any, level: number): number
	local R = config.Economy.rookie
	return (R and R.renown[level]) or 1
end

-- Add Renown. Returns the new level, the Renown into that level, and how many levels were gained.
-- At the level cap Renown stops adding up (Legacy, M9, is the next step).
function Progress.addRenown(config: any, level: number, xp: number, amount: number): (number, number, number)
	local cap = config.Stats.levelCap
	local gained = 0
	xp += math.max(0, math.floor(amount))
	while level < cap do
		local need = Progress.xpToNext(config, level)
		if xp < need then
			break
		end
		xp -= need
		level += 1
		gained += 1
	end
	if level >= cap then
		xp = 0
	end
	return level, xp, gained
end

export type Bonus = {
	friends: number?, -- friends in the server
	legacy: number?, -- Legacy rank 0 to 5
	faction: number?, -- faction rank
	firstContract: boolean?, -- one of the first 5 contracts today
	doublePass: boolean?, -- the 2x pass (earned Credits and Renown only)
	renownMult: number?, -- Renown only, after the cap: the Crater's +50% (M8)
}

function Progress.multiplier(config: any, bonus: Bonus?): number
	local b = config.Economy.bonus
	local o = bonus or {}
	local m = 1 + math.min(b.friendMax, (o.friends or 0) * b.friendEach)
	m *= 1 + math.min(b.legacyMax, (o.legacy or 0) * b.legacyEach)
	m *= 1 + math.min(b.factionMax, (o.faction or 0) * b.factionEach)
	if o.firstContract then
		m *= b.firstContractMult
	end
	if o.doublePass then
		m *= b.doublePass
	end
	return math.min(b.cap, m)
end

-- Credits and Renown for an action at a zone level. Rewards follow the zone, not the hero, so a level 50
-- in a level 5 area earns level 5 rewards.
function Progress.earn(config: any, action: string, zoneLevel: number, bonus: Bonus?): (number, number)
	local row = config.Economy.earn[action]
	assert(row, "unknown earn action " .. tostring(action))
	local m = Progress.multiplier(config, bonus)
	local scale = config.Economy.scale
	local credits = (row.credits[1] + row.credits[2] * zoneLevel) * m * scale.credits
	local renown = (row.renown[1] + row.renown[2] * zoneLevel)
		* m
		* scale.renown
		* ((bonus and bonus.renownMult) or 1)
	return math.floor(credits + 0.5), math.floor(renown + 0.5)
end

export type Currency = { credits: number, banked: number, dust: number }

function Progress.canSpend(currency: Currency, cost: number): boolean
	return currency.credits + currency.banked >= cost
end

function Progress.spend(currency: Currency, cost: number): boolean
	if cost <= 0 then
		return true
	end
	if not Progress.canSpend(currency, cost) then
		return false
	end
	local fromHand = math.min(currency.credits, cost)
	currency.credits -= fromHand
	currency.banked -= cost - fromHand
	return true
end

-- What unlocks at each level, for the "next unlock" on the Renown bar and the level-up banner. first-30
-- (2026-11-20): read from the config the game really runs on. The spec's Levels table text had gone stale with
-- nate's later calls (every mobility pick from level 1, 2026-11-16; one main path, borrowing at borrowLevel), so
-- a new hero's first level-up said "Unlocked: Flight" whatever they picked, and the HUD said "NEXT LV 6: Frost
-- powers". Kept by hand: only what has no config row.
Progress.UNLOCKS = {
	[1] = "Leap, Glide, 2 skill slots",
	[40] = "Level 40 trophy",
}
Progress.CAP_UNLOCK = "Level cap, Legacy" -- at Config.Stats.levelCap (50 since 2026-11-17)

-- What a level unlocks (from the config: skill and super slots, move training ranks, the Contract Board,
-- borrowing, the second loadout, the PvP flag, gear tiers, story missions; the cap's line), or nil
function Progress.unlockAt(config: any, level: number): string?
	if level == config.Stats.levelCap then
		return Progress.CAP_UNLOCK
	end
	local out = {}
	if Progress.UNLOCKS[level] then
		table.insert(out, Progress.UNLOCKS[level])
	end
	local A = config.Abilities or {}
	for i, L in A.slotLevels or {} do
		if L == level and i > 1 and (A.slotLevels[i - 1] or 0) < level then
			table.insert(out, "Skill slot " .. i)
		end
	end
	if A.superLevel == level then
		table.insert(out, "Super slot")
	end
	local ranks = config.Move and config.Move.ranks
	local r = ranks and table.find(ranks.levels, level)
	if r then
		table.insert(out, if r == 1 then "Move training" else "Move training " .. r)
	end
	if config.Contracts and config.Contracts.board and config.Contracts.board.minLevel == level then
		table.insert(out, "Contract Board")
	end
	if A.borrowLevel == level then
		table.insert(out, "Borrow powers")
	end
	if A.secondLoadoutLevel == level then
		table.insert(out, "Second loadout")
	end
	if config.Pvp and config.Pvp.minLevel == level then
		table.insert(out, "PvP flag")
	end
	for _, tier in { "Epic", "Legendary" } do
		if config.Gear and config.Gear.tierLevel and config.Gear.tierLevel[tier] == level then
			table.insert(out, tier .. " gear")
		end
	end
	for _, m in (config.Story and config.Story.missions) or {} do
		if not m.opening and m.minLevel == level and (m.act or 1) == 1 then
			table.insert(out, "Mission: " .. m.name)
		end
	end
	return if #out > 0 then table.concat(out, ", ") else nil
end

function Progress.nextUnlock(config: any, level: number): (number?, string?)
	for l = level + 1, config.Stats.levelCap do
		local text = Progress.unlockAt(config, l)
		if text then
			return l, text
		end
	end
	return nil, nil
end

return Progress
