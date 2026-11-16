--!strict
-- EconomySim: many heroes playing for hours, earning and spending with the real formulas (spec: M9 test
-- "A simulation of 1,000 heroes over 10 hours reaches level 20 to 28 and spends within 15% of the Sinks
-- table"). Pure, so Lune runs it; nate can rerun it after any Balance change.
-- The play model (Config.Economy.sim) is what a typical hero does in 30 minutes: incidents, rescues,
-- contracts and world bosses at its zone level, story missions as they open, a play session per day. Each
-- hero gets a skill factor, 0 to 2 friends and a small share own the 2x pass. Earnings go through
-- Progress.earn, ContractPlan.pay and the boss tiers, so the sim always uses the live numbers.
-- Spending follows the Sinks table: skill ranks when a point and the Credits are there, then HQ levels,
-- then Gizmo's base styles.

local Progress = if script then require(script.Parent.Progress) else (require :: any)("./Progress")
local ContractPlan = if script
	then require(script.Parent.ContractPlan)
	else (require :: any)("./ContractPlan")
local AbilityRules = if script
	then require(script.Parent.AbilityRules)
	else (require :: any)("./AbilityRules")
local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local EconomySim = {}

export type Result = {
	levels: { number }, -- every hero's level at the end, sorted
	earned: { number }, -- Credits earned per hero, sorted
	spent: { ranks: number, hq: number, styles: number },
	median: number,
	p10: number,
	p90: number,
	creditsPer30At: { [number]: number }, -- the mean Credits a typical hero earns in 30 minutes at a level
	buildHours: number, -- mean hours of play to earn a fully ranked 5-skill build (the Sinks table)
}

-- Credits for a fully ranked build of 5 skills and a super (the Sinks table's "about 35,000")
function EconomySim.buildCost(Config: any): number
	local A = Config.Abilities
	local skill = 0
	for i = 2, #A.rankCredits do
		skill += A.rankCredits[i]
	end
	local super = 0
	for _, c in A.superRankCredits do
		super += c
	end
	return 5 * (skill + A.rankCredits[1]) + super
end

-- One 30 minute block at a level. Returns credits, renown.
local function block(Config: any, rng: any, h: any, dayContracts: number): (number, number, number)
	local S = Config.Economy.sim
	local L = math.min(h.level, 40)
	local bonus = { friends = h.friends, legacy = 0, doublePass = h.pass }
	local credits, renown = 0, 0
	local function add(c: number, r: number)
		credits += c
		renown += r
	end
	local function times(rate: number): number
		local x = rate * h.skill
		local n = math.floor(x)
		if rng:next() < x - n then
			n += 1
		end
		return n
	end
	for _ = 1, times(S.per30.incident) do
		add(Progress.earn(Config, "incident", L, bonus))
	end
	for _ = 1, times(S.per30.rescue) do
		add(Progress.earn(Config, "rescue", L, bonus))
	end
	local m = Progress.multiplier(Config, bonus)
	for _ = 1, times(S.per30.contract) do
		local kinds = S.contractKinds
		local c, r = ContractPlan.pay(Config, kinds[rng:int(1, #kinds)], L, dayContracts)
		dayContracts += 1
		add(math.floor(c * m + 0.5), math.floor(r * m + 0.5))
	end
	for _ = 1, times(S.per30.boss) do
		local roll = rng:next()
		local tier = if roll < S.bossTiers[1]
			then "bossParticipant"
			elseif roll < S.bossTiers[1] + S.bossTiers[2] then "bossContributor"
			else "bossMvp"
		add(Progress.earn(Config, tier, L, bonus))
	end
	-- story missions: the next first clear, one per block once its level is reached
	local nextMission = Config.Story.missions[h.missions + 1]
	if nextMission and h.level >= nextMission.minLevel then
		add(Progress.earn(Config, "mission", math.max(L, nextMission.minLevel), bonus))
		h.missions += 1
	end
	return credits, renown, dayContracts
end

-- Spend like a player: ranks first (the cheapest rank a point allows), then HQ, then styles
local function spend(Config: any, h: any, out: any)
	local A = Config.Abilities
	local loop = true
	while loop do
		loop = false
		local points = AbilityRules.pointsEarned(Config, h.level) - h.pointsSpent
		local slots = math.min(5, AbilityRules.skillSlots(Config, h.level) + 1)
		local bestI, bestCost = nil, math.huge
		for i = 1, slots do
			local r = h.ranks[i] or 1
			local to = r + 1
			local superSlot = i == 5
			local need = if superSlot then A.superRankPoints[r] else A.rankPoints[to]
			local cost = if superSlot then A.superRankCredits[r] else A.rankCredits[to]
			if superSlot and not AbilityRules.superUnlocked(Config, h.level) then
				need = nil
			end
			if need and cost and need <= points and cost < bestCost then
				bestI, bestCost = i, cost
			end
		end
		if bestI and h.credits >= bestCost then
			local r = h.ranks[bestI] or 1
			h.pointsSpent += if bestI == 5 then A.superRankPoints[r] else A.rankPoints[r + 1]
			h.ranks[bestI] = r + 1
			h.credits -= bestCost
			out.ranks += bestCost
			loop = true
		elseif not bestI then
			-- no rank to buy right now: HQ levels, then a base style, keeping a reserve for the next rank
			local hq = Config.Economy.hqLevels[h.hq]
			if hq and h.credits >= hq * Config.Economy.sim.reserve then
				h.credits -= hq
				h.hq += 1
				out.hq += hq
				loop = true
			elseif
				h.credits >= Config.Economy.sim.stylePrice * Config.Economy.sim.reserve and h.styles < 40
			then
				h.credits -= Config.Economy.sim.stylePrice
				h.styles += 1
				out.styles += Config.Economy.sim.stylePrice
				loop = true
			end
		end
	end
end

function EconomySim.run(Config: any, heroes: number, hours: number, seed: number): Result
	local S = Config.Economy.sim
	local rng = Rng.new(seed)
	local spent = { ranks = 0, hq = 0, styles = 0 }
	local levels, earned = {}, {}
	local per30: { [number]: { number } } = {}
	local buildCost = EconomySim.buildCost(Config)
	local buildSum, buildN = 0, 0
	for _ = 1, heroes do
		local h = {
			level = 1,
			xp = 0,
			credits = 0,
			skill = rng:range(S.skill[1], S.skill[2]),
			friends = rng:int(S.friends[1], S.friends[2]),
			pass = rng:next() < S.passShare,
			missions = 1, -- the opening clears mission 1 (level 3)
			ranks = {},
			pointsSpent = 0,
			hq = 1,
			styles = 0,
		}
		h.level, h.xp = Progress.addRenown(Config, 1, 0, Progress.totalTo(Config, 3))
		local total, dayContracts, buildAt = 0, 0, nil
		for b = 1, hours * 2 do
			if (b - 1) % (S.sessionHours * 2) == 0 then
				dayContracts = 0 -- a new day: the first 5 contracts pay double again
			end
			local at = h.level
			local c, r
			c, r, dayContracts = block(Config, rng, h, dayContracts)
			per30[at] = per30[at] or {}
			if not h.pass and h.friends == 0 then
				table.insert(per30[at], c / h.skill)
			end
			total += c
			h.credits += c
			h.level, h.xp = Progress.addRenown(Config, h.level, h.xp, r)
			spend(Config, h, spent)
			if not buildAt and total >= buildCost then
				buildAt = b / 2
			end
		end
		if not buildAt then
			-- extrapolate at this hero's last rate
			buildAt = hours * buildCost / math.max(total, 1)
		end
		buildSum += buildAt
		buildN += 1
		table.insert(levels, h.level)
		table.insert(earned, total)
	end
	table.sort(levels)
	table.sort(earned)
	local means = {}
	for lv, list in per30 do
		local sum = 0
		for _, v in list do
			sum += v
		end
		means[lv] = sum / #list
	end
	return {
		levels = levels,
		earned = earned,
		spent = spent,
		median = levels[math.ceil(#levels / 2)],
		p10 = levels[math.max(1, math.floor(#levels * 0.1))],
		p90 = levels[math.ceil(#levels * 0.9)],
		creditsPer30At = means,
		buildHours = buildSum / buildN,
	}
end

return EconomySim
