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
	-- the median hours of play to reach each level (math.huge when fewer than half the heroes got there),
	-- up to Config.Stats.levelCap: hoursTo[Config.Stats.levelCap] is the hours to the cap
	hoursTo: { [number]: number },
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
	local L = math.min(h.level, Config.Stats.levelCap)
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
	local cap = Config.Stats.levelCap
	local reached: { [number]: { number } } = {}
	for lv = 1, cap do
		reached[lv] = {}
	end
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
		for lv = 1, h.level do
			table.insert(reached[lv], 0)
		end
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
			local was = h.level
			h.level, h.xp = Progress.addRenown(Config, h.level, h.xp, r)
			for lv = was + 1, h.level do
				table.insert(reached[lv], b / 2)
			end
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
	local hoursTo: { [number]: number } = {}
	for lv = 1, cap do
		local list = reached[lv]
		table.sort(list)
		-- heroes who never got there count as slower than every one who did
		hoursTo[lv] = if #list >= math.ceil(heroes / 2) then list[math.ceil(heroes / 2)] else math.huge
	end
	return {
		hoursTo = hoursTo,
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

-- The first session, minute by minute (list-combat 2026-11-20, nate: the first 30 minutes matter most: level 5 and
-- a new power by about 15 minutes, the first mobility rank by about 20). The nominal new hero (skill 1, no friends,
-- no pass) leaves the prologue `start` seconds after joining at its reward level, then plays
-- the play model's mix at its expected rates (Config.Economy.sim.per30 / 30 a minute) and goes to each story
-- mission as it opens (its `minutes` long, else Config.Economy.sim.missionMinutes; paid at the end). It buys the first mobility rank
-- as soon as the level and the Credits allow (nothing else is bought first: the new power costs only a Skill
-- Point). Returns seconds from joining: levelAt[L], powerAt (the third skill slot), mobilityAt (rank 1).
function EconomySim.firstSession(Config: any, start: number, minutes: number?): { [string]: any }
	local S = Config.Economy.sim
	local O = Config.Story.opening
	local level, xp, credits = 1, 0, 0
	local levelAt: { [number]: number } = {}
	local t = start
	local function gain(c: number, r: number, exact: boolean?)
		credits += c
		local before = level
		level, xp =
			Progress.addRenown(Config, level, xp, if exact then r else r * Progress.rookie(Config, level))
		for L = before + 1, level do
			levelAt[L] = levelAt[L] or t
		end
	end
	-- the prologue: its reward level (OpeningService tops the hero up to it exactly)
	local reward = O.reward and O.reward.level or 1
	gain(0, Progress.totalTo(Config, reward), true)
	local missions = 1
	local acc = { incident = 0, rescue = 0, contract = 0, boss = 0 }
	local dayContracts = 0
	local powerAt, mobilityAt = nil :: number?, nil :: number?
	local M = Config.Move.ranks
	local stop = start + (minutes or 40) * 60
	while t < stop do
		local nextMission = Config.Story.missions[missions + 1]
		if nextMission and level >= nextMission.minLevel then
			-- the clear pay, then the first clear's own Renown (MissionService)
			t += (nextMission.minutes or S.missionMinutes) * 60
			gain(Progress.earn(Config, "mission", math.max(level, nextMission.minLevel), {}))
			gain(0, nextMission.renown or 0)
			missions += 1
		else
			t += 60
			local L = level
			for kind, rate in S.per30 do
				acc[kind] += rate / 30
				while acc[kind] >= 1 do
					acc[kind] -= 1
					if kind == "contract" then
						local c, r = ContractPlan.pay(Config, S.contractKinds[1], L, dayContracts)
						dayContracts += 1
						gain(c, r)
					elseif kind == "boss" then
						gain(Progress.earn(Config, "bossParticipant", L, {}))
					else
						gain(Progress.earn(Config, kind, L, {}))
					end
				end
			end
		end
		if not powerAt and AbilityRules.skillSlots(Config, level) >= 3 then
			powerAt = levelAt[Config.Abilities.slotLevels[3]] or t
		end
		if not mobilityAt and level >= M.levels[1] and credits >= M.costs[1] then
			mobilityAt = t
			credits -= M.costs[1]
		end
	end
	return { levelAt = levelAt, powerAt = powerAt, mobilityAt = mobilityAt, level = level, credits = credits }
end

return EconomySim
