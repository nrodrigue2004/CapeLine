--!strict
-- Awakening (nate, 2026-11-16): a meter fills from fighting; when full the hero can awaken for 15 s of
-- power (more damage, faster cooldowns, a stronger super, an aura). Same for every hero; nothing sold
-- touches it. Also the team-up combo check (spec: Social table, two supers within 3 s and 30 studs).

local Awakening = {}

export type Meter = { value: number, untilT: number }

function Awakening.new(): Meter
	return { value = 0, untilT = 0 }
end

function Awakening.active(m: Meter, now: number): boolean
	return now < m.untilT
end

-- kind: "basicHit", "skillHit", "superHit", "kill"; count = targets hit
function Awakening.gain(config: any, m: Meter, kind: string, count: number, now: number): number
	if Awakening.active(m, now) then
		return m.value -- the meter is spent while awake
	end
	local aw = config.Abilities.awakening
	local per = aw.gain[kind] or 0
	-- the first target counts in full, extra targets half (an AoE does not fill it in one cast)
	local amount = per * (1 + math.max(0, count - 1) * 0.5)
	m.value = math.min(aw.max, m.value + amount)
	return m.value
end

-- fraction of max health lost in one hit
function Awakening.hurt(config: any, m: Meter, fraction: number, now: number): number
	if Awakening.active(m, now) then
		return m.value
	end
	local aw = config.Abilities.awakening
	m.value = math.min(aw.max, m.value + fraction * 100 * aw.gain.hurtPerPct)
	return m.value
end

-- A flat amount (a perfect block's +10, H1); like gain, nothing while awake
function Awakening.add(config: any, m: Meter, amount: number, now: number): number
	if Awakening.active(m, now) then
		return m.value
	end
	m.value = math.min(config.Abilities.awakening.max, m.value + amount)
	return m.value
end

function Awakening.ready(config: any, m: Meter, now: number): boolean
	return m.value >= config.Abilities.awakening.max and not Awakening.active(m, now)
end

-- Spend a full meter. Returns true when it started.
function Awakening.start(config: any, m: Meter, now: number): boolean
	if not Awakening.ready(config, m, now) then
		return false
	end
	m.value = 0
	m.untilT = now + config.Abilities.awakening.duration
	return true
end

function Awakening.damageMult(config: any, m: Meter, now: number, pvp: boolean?): number
	if not Awakening.active(m, now) then
		return 1
	end
	local aw = config.Abilities.awakening
	return 1 + (if pvp then aw.pvpDamage else aw.damage)
end

---------------------------------------------------------------------------
-- Team-up combos
---------------------------------------------------------------------------

export type SuperUse = { hero: number, set: string, x: number, y: number, z: number, t: number }
export type ComboBook = { recent: { SuperUse } }

function Awakening.comboBook(): ComboBook
	return { recent = {} }
end

local function pairOf(config: any, a: string, b: string): any
	for _, p in config.Abilities.combos.pairs do
		local s1, s2 = p.sets[1], p.sets[2]
		if (s1 == a and s2 == b) or (s1 == b and s2 == a) then
			return p
		end
	end
	return nil
end

-- Note a super. Returns the combo row and the partner's use when it completes a pair.
-- canPair(a, b): false between flagged PvP opponents (M8).
function Awakening.noteSuper(
	config: any,
	book: ComboBook,
	use: SuperUse,
	canPair: ((number, number) -> boolean)?
): (any, SuperUse?)
	local cfg = config.Abilities.combos
	local i = 1
	while i <= #book.recent do
		if use.t - book.recent[i].t > cfg.window then
			table.remove(book.recent, i)
		else
			i += 1
		end
	end
	for k, other in book.recent do
		if other.hero ~= use.hero then
			local dx, dy, dz = other.x - use.x, other.y - use.y, other.z - use.z
			if dx * dx + dy * dy + dz * dz <= cfg.distance * cfg.distance then
				local p = pairOf(config, use.set, other.set)
				if p and (not canPair or canPair(use.hero, other.hero)) then
					table.remove(book.recent, k) -- each super pairs once
					return p, other
				end
			end
		end
	end
	table.insert(book.recent, use)
	return nil, nil
end

return Awakening
