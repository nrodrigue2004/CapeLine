--!strict
-- KnockRules: knockback by move as pure rules (nate's playtest 2026-11-19: "A lot of moves should have strong
-- knock back. That is to send enemies flying through buildings. Determine knock back based on move"). Numbers in
-- Config.Combat.knock; CombatService and ThrowService use it, Lune checks it.
-- * damaging(row): does this ability or weapon move deal damage (so it needs a knockback)?
-- * kind(K, row): its knockback kind: the row's own `knockKind`, else field (fields and channels tick), super
--   (supers), jab (basics and combo M1s), heavy (slams over slamCoeff, anything over heavyCoeff, breakers and
--   charge-up powers' full hits), else strike.
-- * plan(K, kind, o): the throw for one hit: distance, arc height, speed (0 = an instant shove). o.charge (0..1)
--   lerps toward "charged", o.last (a combo's last hit) multiplies a jab, o.crit, o.miniBoss scale it, o.immune and
--   o.boss stop it.
-- * pvp(K, P, kind, dist): a player's throw: only pvpKinds, at Config.Pvp.knock.scale, at most maxDistance.
-- * arc(lift, u): the launch's height over its path (u 0..1).

local KnockRules = {}

export type Plan = { dist: number, lift: number, speed: number, kind: string }

local NO_DAMAGE = { buff = true, wall = true, ramp = true }

function KnockRules.damaging(row: any): boolean
	if not row or NO_DAMAGE[row.shape] then
		return false
	end
	return (row.coeff or 0) > 0
end

function KnockRules.kind(K: any, row: any): string
	if row.knockKind and K.kinds[row.knockKind] then
		return row.knockKind
	end
	if row.shape == "field" or row.channel then
		return "field"
	end
	if row.slot == "super" then
		return "super"
	end
	if row.slot == "basic" then
		return "jab"
	end
	local coeff = row.coeff or 0
	if coeff >= K.heavyCoeff or (K.slamShapes[row.shape] and coeff >= K.slamCoeff) then
		return "heavy"
	end
	if row.breaker or (row.status == "knockback" and (row.knock or 0) >= K.kinds.heavy.dist * 0.5) then
		return "heavy"
	end
	return "strike"
end

export type Opts = {
	charge: number?, -- 0..1: a charged hit lerps toward "charged"
	last: boolean?, -- a combo's last hit
	crit: boolean?,
	miniBoss: boolean?,
	boss: boolean?,
	immune: boolean?,
	knock: number?, -- the row's own knockback status distance (kept if bigger)
}

function KnockRules.plan(K: any, kind: string, o: Opts?): Plan
	local opts: Opts = o or {}
	local base = K.kinds[kind] or K.kinds.strike
	local dist, lift, speed = base.dist, base.lift, base.speed
	local charge = math.clamp(opts.charge or 0, 0, 1)
	if charge > 0 and kind ~= "field" then
		local c = K.kinds.charged
		dist = math.max(dist, dist + (c.dist - dist) * charge)
		lift = math.max(lift, lift + (c.lift - lift) * charge)
		speed = math.max(speed, speed + (c.speed - speed) * charge)
		if charge >= 1 then
			kind = if kind == "super" then "super" else "charged"
		end
	end
	if opts.last and kind == "jab" then
		dist *= K.lastHit
	end
	if opts.knock and opts.knock > dist then
		dist = opts.knock
		if speed <= 0 then
			speed = K.kinds.strike.speed
		end
	end
	if opts.crit then
		dist *= K.crit
	end
	if opts.boss or opts.immune then
		dist, lift, speed = 0, 0, 0
	elseif opts.miniBoss then
		dist *= K.miniBoss
		lift *= K.miniBoss
		if dist < 4 then
			speed = 0 -- a nudge, no flight
		end
	end
	return { dist = dist, lift = lift, speed = speed, kind = kind }
end

-- A flagged player's throw: only the big kinds, compressed, capped. 0 = none
function KnockRules.pvp(K: any, P: any, kind: string, dist: number): number
	if not K.pvpKinds[kind] or dist <= 0 then
		return 0
	end
	return math.min(dist * (P.knock.scale or 1), P.knock.maxDistance)
end

-- The launch's height over its path: a parabola `lift` high at the middle
function KnockRules.arc(lift: number, u: number): number
	u = math.clamp(u, 0, 1)
	return lift * 4 * u * (1 - u)
end

return KnockRules
