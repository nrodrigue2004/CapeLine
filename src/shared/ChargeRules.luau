--!strict
-- ChargeRules: hold to aim and charge (overhaul plan step 3), pure so Lune tests it.
-- * aimable: every skill and super shows its aim while its key is held and casts on release.
-- * chargeable: damaging skills that hit where you aim (bolts, lines, chains, cones, arcs, novas) also charge;
--   channels, buffs, fields, summons, dashes, leaps, rides and supers do not (their balance stays as it was).
-- * level: 0 for a tap, rising to 1 between Config.Combat.charge.start and full seconds held.
-- * apply: a charged cast hits harder and wider (+damage and +size at level 1).
-- * allowed: the server's cap on a claimed level, from the hold it timed itself (press to use).

local ChargeRules = {}

local CHARGE_SHAPES = { bolt = true, line = true, chain = true, cone = true, arc = true, nova = true }

function ChargeRules.aimable(row: any): boolean
	return row ~= nil and (row.slot == "skill" or row.slot == "super")
end

function ChargeRules.chargeable(row: any): boolean
	return row ~= nil
		and row.slot == "skill"
		and CHARGE_SHAPES[row.shape or ""] == true
		and not row.channel
		and (row.coeff or 0) > 0
end

function ChargeRules.level(C: any, held: number): number
	local ch = C.charge
	if held <= ch.start then
		return 0
	end
	return math.clamp((held - ch.start) / (ch.full - ch.start), 0, 1)
end

-- the claim the client sends (0 to 100) to a level, capped by what the server timed
function ChargeRules.allowed(C: any, claim: number?, pressedAt: number?, now: number, latency: number): number
	if not claim or claim <= 0 or not pressedAt then
		return 0
	end
	local held = now - (pressedAt :: number) + math.max(0, latency) + C.charge.leeway
	return math.min(math.clamp((claim :: number) / 100, 0, 1), ChargeRules.level(C, held))
end

-- scale an effective ability row for a charge level (changes eff in place; returns it)
function ChargeRules.apply(C: any, eff: any, level: number): any
	if level <= 0 then
		return eff
	end
	local ch = C.charge
	eff.coeff = (eff.coeff or 0) * (1 + ch.damage * level)
	local grow = 1 + ch.size * level
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
