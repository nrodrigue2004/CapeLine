--!strict
-- HeroicRules: the Heroic tier for incidents, events and contracts (Config.Heroic), as plain rules so Lune
-- tests them. From level 40 an activity can roll Heroic: robots `levelBonus` levels higher through the usual
-- robot scaling, one more robot in each squad, `rewardMult` x the Credits and Renown, and a gear roll a
-- couple of item levels higher. Nothing here is sold, and the Heroic pay rides on the same earn maths.
-- * eligible(level), roll(kind, level, rng): may it roll, and did it
-- * robotLevel, squad, pay, gearLevel, time: what Heroic changes
-- * incomeBump(level): the expected Credits and Renown bump over Config.Economy.sim's play model (the
--   economy check in Decisions)

local Progress = if script then require(script.Parent.Progress) else (require :: any)("./Progress")

local HeroicRules = {}

export type Row = { kind: string, n: number }

function HeroicRules.eligible(Config: any, level: number): boolean
	local h = Config.Heroic
	return h ~= nil and h.on == true and level >= h.minLevel
end

-- rng: anything with :next() returning 0..1 (Rng). kind: "incident", "event" or "contract". The roll is
-- always taken, so a seeded rng gives the same rolls after it whatever the level.
function HeroicRules.roll(Config: any, kind: string, level: number, rng: any): boolean
	local r = rng:next()
	if not HeroicRules.eligible(Config, level) then
		return false
	end
	return r < (Config.Heroic.chance[kind] or 0)
end

-- The level its robots spawn at (objects' HP follows the same level)
function HeroicRules.robotLevel(Config: any, level: number, heroic: boolean?): number
	if heroic then
		return level + Config.Heroic.levelBonus
	end
	return level
end

-- One more robot in the squad: added to its first row (a copy; the template is never changed)
function HeroicRules.squad(Config: any, rows: { Row }, heroic: boolean?): { Row }
	local out: { Row } = {}
	for _, r in rows do
		table.insert(out, { kind = r.kind, n = r.n })
	end
	if heroic and out[1] then
		out[1].n += Config.Heroic.extraUnits
	end
	return out
end

-- Credits and Renown after Heroic (rounded); unchanged when not Heroic
function HeroicRules.pay(Config: any, credits: number, renown: number, heroic: boolean?): (number, number)
	if not heroic then
		return credits, renown
	end
	local m = Config.Heroic.rewardMult
	return math.floor(credits * m + 0.5), math.floor(renown * m + 0.5)
end

-- The zone level of the clear's gear roll
function HeroicRules.gearLevel(Config: any, level: number, heroic: boolean?): number
	if not heroic then
		return level
	end
	return math.min(Config.Stats.levelCap, level + Config.Heroic.gearLevels)
end

-- An incident's time limit
function HeroicRules.time(Config: any, seconds: number, heroic: boolean?): number
	if not heroic then
		return seconds
	end
	return math.floor(seconds * Config.Heroic.timeMult + 0.5)
end

-- The expected bump to a hero's Credits and Renown over 30 minutes of the play model (Economy.sim.per30)
-- at this level: incidents roll Heroic at their chance, contract offers at theirs and most are taken;
-- rescues and bosses are unchanged. Returns (credit share, renown share), e.g. 0.08 = +8%.
function HeroicRules.incomeBump(Config: any, level: number): (number, number)
	local sim = Config.Economy.sim.per30
	local h = Config.Heroic
	local function earn(action: string): (number, number)
		return Progress.earn(Config, action, level)
	end
	local ic, ir = earn("incident")
	local rc, rr = earn("rescue")
	local cc, cr = earn("contract")
	local bc, br = earn("bossParticipant")
	local baseC = sim.incident * ic + sim.rescue * rc + sim.contract * cc + sim.boss * bc
	local baseR = sim.incident * ir + sim.rescue * rr + sim.contract * cr + sim.boss * br
	if not HeroicRules.eligible(Config, level) then
		return 0, 0
	end
	local extra = h.rewardMult - 1
	local iShare = h.chance.incident
	local cShare = h.chance.contract * ((h.takeShare and h.takeShare.contract) or 1)
	local addC = sim.incident * ic * iShare * extra + sim.contract * cc * cShare * extra
	local addR = sim.incident * ir * iShare * extra + sim.contract * cr * cShare * extra
	return addC / math.max(baseC, 1), addR / math.max(baseR, 1)
end

return HeroicRules
