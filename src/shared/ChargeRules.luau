--!strict
-- ChargeRules: hold to aim and charge (overhaul plan step 3), pure so Lune tests it.
-- * aimable: every skill and super shows its aim while its key is held and casts on release.
-- * chargeable: damaging skills that hit where you aim (bolts, lines, chains, cones, arcs, novas) also charge;
--   channels, buffs, fields, summons, dashes, leaps, rides and supers do not (their balance stays as it was).
-- * level: 0 for a tap, rising to 1 between Config.Combat.charge.start and full seconds held.
-- * apply: a charged cast hits harder and wider (+damage and +size at level 1).
-- * allowed: the server's cap on a claimed level, from the hold it timed itself (press to use).
-- * H2 charge-up powers (spec: Hero MMO features > Charge-up powers): about 24 rows in Config.Abilities carry
--   charge = { max, mult, grow }: they charge over `max` seconds from 1x to `mult` damage and up to `grow`
--   size, a full charge is a breaker (Shared.GuardMath), and charging slows the hero (Config.Combat.charge
--   .powerSlow). Any shape with a coefficient can carry one (Telekinesis throws); every other damaging aimed
--   skill keeps the modest charge above.

local ChargeRules = {}

local CHARGE_SHAPES = { bolt = true, line = true, chain = true, cone = true, arc = true, nova = true }

function ChargeRules.aimable(row: any): boolean
	return row ~= nil and (row.slot == "skill" or row.slot == "super")
end

function ChargeRules.chargeable(row: any): boolean
	return row ~= nil
		and row.slot == "skill"
		and (CHARGE_SHAPES[row.shape or ""] == true or row.charge ~= nil)
		and not row.channel
		and (row.coeff or 0) > 0
end

-- H2: one of the charge-up powers (the big charge, a breaker when full)
function ChargeRules.power(row: any): boolean
	return ChargeRules.chargeable(row) and row.charge ~= nil
end

-- row (optional): a charge-up power fills over its own `max` seconds
function ChargeRules.level(C: any, held: number, row: any?): number
	local ch = C.charge
	if held <= ch.start then
		return 0
	end
	local full = if row and row.charge and row.charge.max then row.charge.max else ch.full
	return math.clamp((held - ch.start) / math.max(0.05, full - ch.start), 0, 1)
end

-- the claim the client sends (0 to 100) to a level, capped by what the server timed
function ChargeRules.allowed(
	C: any,
	claim: number?,
	pressedAt: number?,
	now: number,
	latency: number,
	row: any?
): number
	if not claim or claim <= 0 or not pressedAt then
		return 0
	end
	local held = now - (pressedAt :: number) + math.max(0, latency) + C.charge.leeway
	return math.min(math.clamp((claim :: number) / 100, 0, 1), ChargeRules.level(C, held, row))
end

-- scale an effective ability row for a charge level (changes eff in place; returns it)
function ChargeRules.apply(C: any, eff: any, level: number): any
	if level <= 0 then
		return eff
	end
	local ch = C.charge
	local big = eff.charge
	local grow: number
	if big then
		-- H2: a charge-up power: 1x to `mult` damage, up to `grow` size; full is a breaker
		eff.coeff = (eff.coeff or 0) * (1 + ((big.mult or 1) - 1) * level)
		grow = 1 + ((big.grow or 1) - 1) * level
		eff.chargedBig = level
		if level >= 1 then
			eff.breaker = true
		end
	else
		eff.coeff = (eff.coeff or 0) * (1 + ch.damage * level)
		grow = 1 + ch.size * level
	end
	if eff.radius then
		eff.radius *= grow
	end
	if eff.range then
		eff.range *= grow
	end
	if eff.width then
		eff.width *= grow
	end
	if eff.cone then
		eff.cone = math.min(170, eff.cone * grow)
	end
	eff.charged = level
	return eff
end

return ChargeRules
