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

-- What unlocks at each level (spec: Levels table), for the "next unlock" on the Renown bar
Progress.UNLOCKS = {
	[1] = "Leap, Glide, 2 skill slots",
	[3] = "Flight",
	[4] = "Contract Board",
	[5] = "Skill slot 3",
	[6] = "Frost powers",
	[8] = "Super Speed",
	[10] = "Skill slot 4, Titan powers, PvP flag",
	[12] = "Super Leap",
	[14] = "Pulse powers",
	[15] = "Second loadout",
	[16] = "Grapple Acrobat",
	[18] = "Blade powers",
	[20] = "Super slot, Epic gear",
	[30] = "Legendary gear",
	[40] = "Level 40 trophy",
}
Progress.CAP_UNLOCK = "Level cap, Legacy" -- at Config.Stats.levelCap (50 since 2026-11-17)

-- What a level unlocks (the cap's line comes from the config), or nil
function Progress.unlockAt(config: any, level: number): string?
	if level == config.Stats.levelCap then
		return Progress.CAP_UNLOCK
	end
	return Progress.UNLOCKS[level]
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
