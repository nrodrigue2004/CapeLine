--!strict
-- AbilityRules: ranks, mods, capstones, skill points, cooldowns and the loadout budget (spec: Loadout rules;
-- Skill points, ranks and respec). Pure, so the server's checks, the loadout screen and the tests agree.
-- Skills have 5 ranks: 1 learn, 2 +10% coeff, 3 pick 1 of 2 mods, 4 -8% cooldown, 5 capstone.
-- Supers have 3 ranks (Decisions.md, 2026-11-16): 1 learn, 2 +10% coeff and the mod pick, 3 capstone and
-- -8% cooldown. Basics have no ranks.

local AbilityRules = {}

local SCALED = { "coeff", "endCoeff", "touchCoeff", "fieldCoeff" }

local function applyMod(eff: { [string]: any }, mod: any)
	if mod.add then
		for k, v in mod.add do
			eff[k] = (eff[k] or 0) + v
		end
	end
	if mod.mul then
		for k, v in mod.mul do
			if eff[k] then
				eff[k] *= v
			end
		end
	end
	if mod.set then
		for k, v in mod.set do
			eff[k] = v
		end
	end
end

function AbilityRules.maxRank(row: any): number
	if row.slot == "basic" then
		return 1
	elseif row.slot == "super" then
		return 3
	end
	return 5
end

-- The numbers an ability has at a rank with a mod pick (1 or 2). Returns a new table.
-- extra: mods from gear (Epic set 4-piece bonuses), applied after ranks, mods and the capstone
function AbilityRules.effective(
	config: any,
	id: string,
	rank: number?,
	modPick: number?,
	extra: { any }?
): { [string]: any }
	local A = config.Abilities
	local row = A.list[id]
	assert(row, "unknown ability " .. tostring(id))
	local eff = table.clone(row)
	local r = rank or 1
	eff.rank = r
	if row.slot == "basic" then
		return eff
	end
	local function finish()
		if extra then
			for _, mod in extra do
				applyMod(eff, mod)
			end
		end
		return eff
	end
	local isSuper = row.slot == "super"
	if r >= 2 then
		for _, k in SCALED do
			if eff[k] then
				eff[k] *= 1 + A.rankCoeff
			end
		end
	end
	local modRank = if isSuper then 2 else 3
	if r >= modRank and modPick and row.mods and row.mods[modPick] then
		applyMod(eff, row.mods[modPick])
		eff.modPick = modPick
	end
	local cdRank = if isSuper then 3 else 4
	if r >= cdRank then
		eff.cd *= 1 - A.rankCooldown
	end
	local capRank = if isSuper then 3 else 5
	if r >= capRank and row.cap then
		applyMod(eff, row.cap)
		eff.capstone = true
	end
	return finish()
end

-- Cost to go from toRank - 1 to toRank: skill points, Credits
function AbilityRules.rankCost(config: any, id: string, toRank: number): (number, number)
	local A = config.Abilities
	local row = A.list[id]
	if row.slot == "super" then
		return A.superRankPoints[toRank] or math.huge, A.superRankCredits[toRank] or math.huge
	end
	return A.rankPoints[toRank] or math.huge, A.rankCredits[toRank] or math.huge
end

function AbilityRules.pointsEarned(config: any, level: number, bonus: number?): number
	return level * config.Abilities.pointsPerLevel + (bonus or 0)
end

function AbilityRules.pointsSpent(config: any, ranks: { [string]: number }): number
	local total = 0
	for id, r in ranks do
		local row = config.Abilities.list[id]
		if row and row.slot ~= "basic" then
			for k = 1, r do
				if not AbilityRules.isStarter(config, id) or k > 1 then
					total += (AbilityRules.rankCost(config, id, k))
				end
			end
		end
	end
	return total
end

-- Credits paid for these ranks (refunded by a respec, so trying builds costs nothing)
function AbilityRules.creditsSpent(config: any, ranks: { [string]: number }): number
	local total = 0
	for id, r in ranks do
		local row = config.Abilities.list[id]
		if row and row.slot ~= "basic" then
			for k = 1, r do
				if not AbilityRules.isStarter(config, id) or k > 1 then
					total += select(2, AbilityRules.rankCost(config, id, k))
				end
			end
		end
	end
	return total
end

-- The two skills every set starts with are learned for free (spec: 2 skill slots at level 1)
function AbilityRules.isStarter(config: any, id: string): boolean
	local row = config.Abilities.list[id]
	local starter = row and config.Abilities.starter[row.set]
	return starter ~= nil and table.find(starter, id) ~= nil
end

-- The archetype a path belongs to (Classes.paths)
function AbilityRules.archetypeOf(config: any, set: string): string?
	for _, id in config.Classes.order do
		if table.find(config.Classes[id].paths, set) then
			return id
		end
	end
	return nil
end

-- A path is playable once it has its abilities (a basic and a super)
function AbilityRules.pathReady(config: any, set: string): boolean
	return AbilityRules.basicOf(config, set) ~= nil and AbilityRules.superOf(config, set) ~= nil
end

-- The paths a hero may pick in one archetype (creator)
function AbilityRules.paths(config: any, classId: string): { string }
	local out = {}
	local class = config.Classes[classId]
	for _, set in (if class then class.paths else {}) do
		if AbilityRules.pathReady(config, set) then
			table.insert(out, set)
		end
	end
	return out
end

-- Mostly one path (nate, 2026-11-16): the hero's main path is open from level 1; another path of the same
-- archetype opens for borrowing at Abilities.borrowLevel.
function AbilityRules.setUnlocked(config: any, level: number, set: string, startSet: string?): boolean
	local main = startSet or config.Abilities.defaultLoadout.set
	if set == main then
		return true
	end
	local arch = AbilityRules.archetypeOf(config, set)
	return arch ~= nil
		and arch == AbilityRules.archetypeOf(config, main)
		and level >= config.Abilities.borrowLevel
end

-- Skills learned from other paths (the borrow limit counts these)
function AbilityRules.borrowed(config: any, ranks: { [string]: number }, startSet: string?): number
	local main = startSet or config.Abilities.defaultLoadout.set
	local n = 0
	for id, rank in ranks do
		local row = config.Abilities.list[id]
		if row and rank > 0 and row.set ~= main then
			n += 1
		end
	end
	return n
end

function AbilityRules.skillSlots(config: any, level: number): number
	local n = 0
	for _, need in config.Abilities.slotLevels do
		if level >= need then
			n += 1
		end
	end
	return n
end

function AbilityRules.superUnlocked(config: any, level: number): boolean
	return level >= config.Abilities.superLevel
end

function AbilityRules.basicOf(config: any, set: string): string?
	for _, id in config.Abilities.order do
		local row = config.Abilities.list[id]
		if row.set == set and row.slot == "basic" then
			return id
		end
	end
	return nil
end

function AbilityRules.superOf(config: any, set: string): string?
	for _, id in config.Abilities.order do
		local row = config.Abilities.list[id]
		if row.set == set and row.slot == "super" then
			return id
		end
	end
	return nil
end

function AbilityRules.loadoutPoints(config: any, skills: { string }): number
	local total = 0
	for _, id in skills do
		local row = config.Abilities.list[id]
		total += if row then row.pts else 0
	end
	return total
end

export type HeroView = {
	level: number,
	startSet: string?,
	ranks: { [string]: number },
	bonusPoints: number?,
	credits: number?,
}

-- Can this hero buy the next rank? Returns ok, reason, points, credits
function AbilityRules.canRank(
	config: any,
	hero: HeroView,
	id: string,
	freeCredits: boolean?
): (boolean, string?, number, number)
	local row = config.Abilities.list[id]
	if not row or row.slot == "basic" then
		return false, "no ranks", 0, 0
	end
	if not AbilityRules.setUnlocked(config, hero.level, row.set, hero.startSet) then
		return false, "set locked", 0, 0
	end
	local main = hero.startSet or config.Abilities.defaultLoadout.set
	if row.set ~= main and row.slot ~= "skill" then
		return false, "main path only", 0, 0
	end
	if
		row.set ~= main
		and (hero.ranks[id] or 0) == 0
		and AbilityRules.borrowed(config, hero.ranks, hero.startSet) >= config.Abilities.borrowMax
	then
		return false, "borrow limit", 0, 0
	end
	if row.slot == "super" and not AbilityRules.superUnlocked(config, hero.level) then
		return false, "super locked", 0, 0
	end
	local cur = hero.ranks[id] or 0
	if cur >= AbilityRules.maxRank(row) then
		return false, "max rank", 0, 0
	end
	local pts, credits = AbilityRules.rankCost(config, id, cur + 1)
	if cur == 0 and AbilityRules.isStarter(config, id) then
		pts, credits = 0, 0 -- a set's two starter skills are free to learn
	end
	if freeCredits then
		credits = 0
	end
	local left = AbilityRules.pointsEarned(config, hero.level, hero.bonusPoints)
		- AbilityRules.pointsSpent(config, hero.ranks)
	if pts > left then
		return false, "points", pts, credits
	end
	if credits > (hero.credits or 0) then
		return false, "credits", pts, credits
	end
	return true, nil, pts, credits
end

export type Loadout = { set: string, basic: string?, skills: { string }, super: string? }

-- Server check for Hero.Loadout (spec: points cap 52, unlocked). Returns ok, reason.
function AbilityRules.validate(config: any, hero: HeroView, loadout: Loadout): (boolean, string?)
	local A = config.Abilities
	local main = hero.startSet or A.defaultLoadout.set
	if loadout.set ~= main then
		return false, "not the main path"
	end
	if loadout.basic and loadout.basic ~= AbilityRules.basicOf(config, loadout.set) then
		return false, "basic not of the set"
	end
	if #loadout.skills > AbilityRules.skillSlots(config, hero.level) then
		return false, "too many skills"
	end
	local seen = {}
	for _, id in loadout.skills do
		local row = A.list[id]
		if not row or row.slot ~= "skill" then
			return false, "not a skill"
		end
		if seen[id] then
			return false, "duplicate"
		end
		seen[id] = true
		if not AbilityRules.setUnlocked(config, hero.level, row.set, hero.startSet) then
			return false, "set locked"
		end
		if (hero.ranks[id] or 0) < 1 then
			return false, "not learned"
		end
	end
	if AbilityRules.loadoutPoints(config, loadout.skills) > A.loadoutCap then
		return false, "over budget"
	end
	if loadout.super then
		local row = A.list[loadout.super]
		if not row or row.slot ~= "super" then
			return false, "not a super"
		end
		if not AbilityRules.superUnlocked(config, hero.level) then
			return false, "super locked"
		end
		if row.set ~= main then
			return false, "main path only"
		end
		if (hero.ranks[loadout.super] or 0) < 1 then
			return false, "not learned"
		end
	end
	return true, nil
end

-- A new hero's ranks and loadout for a primary set
function AbilityRules.starter(config: any, set: string): ({ [string]: number }, Loadout)
	local ranks = {}
	local skills = {}
	for _, id in config.Abilities.starter[set] do
		ranks[id] = 1
		table.insert(skills, id)
	end
	local basic = AbilityRules.basicOf(config, set) :: string
	ranks[basic] = 1
	return ranks, { set = set, basic = basic, skills = skills, super = nil }
end

export type CdContext = {
	classId: string?,
	focus: number?,
	attackSpeed: number?, -- Overcharge buff: +0.25 means 25% faster basics
	awakened: boolean?,
}

-- Seconds of cooldown after a use (Focus, class, attack speed, Awakening)
function AbilityRules.cooldown(config: any, formulas: any, eff: any, ctx: CdContext): number
	local cd = formulas.cooldown(config, eff.cd, ctx.focus or 0, ctx.classId)
	if eff.slot == "basic" then
		return cd / (1 + (ctx.attackSpeed or 0))
	end
	if ctx.awakened then
		local aw = config.Abilities.awakening
		if eff.slot == "super" then
			cd *= aw.superCharge
		else
			cd /= aw.cooldownRate
		end
	end
	if ctx.attackSpeed and ctx.attackSpeed > 0 then
		cd /= 1 + ctx.attackSpeed * 0.5 -- skills get half of the attack speed buff
	end
	return cd
end

-- Recast capstones (Double Back, Double Toss, Twin Step): after the first use a 3 s window allows one free
-- recast; the full cooldown starts after the recast, or counts from the first use if no recast came.
-- state: per hero table. afterUse returns the cooldown to start now; blocked says a lapsed window still owes
-- its cooldown.
AbilityRules.RECAST_WINDOW = 3
export type RecastState = { [string]: { untilT: number, full: number } }

function AbilityRules.afterUse(state: RecastState, id: string, eff: any, now: number, fullCd: number): number
	if not eff.recast then
		return fullCd
	end
	local w = state[id]
	if w and now <= w.untilT then
		state[id] = nil -- the recast: now the full cooldown
		return fullCd
	end
	state[id] = { untilT = now + AbilityRules.RECAST_WINDOW, full = fullCd }
	return 0.35
end

function AbilityRules.blocked(state: RecastState, id: string, now: number): boolean
	local w = state[id]
	if not w or now <= w.untilT then
		return false
	end
	if now < w.untilT - AbilityRules.RECAST_WINDOW + w.full then
		return true
	end
	state[id] = nil
	return false
end

-- Combo strings (Punch Combo, Blade Slash): the step goes 1, 2, 3 while hits land within `gap` seconds
AbilityRules.COMBO_GAP = 1.0
function AbilityRules.comboStep(lastAt: number?, lastStep: number?, now: number, hits: number): number
	if lastAt and lastStep and now - lastAt <= AbilityRules.COMBO_GAP then
		return lastStep % hits + 1
	end
	return 1
end

return AbilityRules
