--!strict
-- ThrowMath: pick up and throw (spec: Hero MMO features > Pick up and throw; H3). Pure, so the server
-- (ThrowService), the client (ThrowClient, ThrowFx) and the Lune tests share one set of rules:
--   who lifts what (light and medium for everyone, heavy for Powerhouse or anyone Awakened; Titan's Lift and
--   Throw lifts anything), the nearest liftable in reach, the throw's arc (a scripted parabola, no free
--   physics, the same on every screen), what the landing hits for, and when a thrown prop comes back.
-- Citizens and heroes are never in the liftable list, and `canLift` refuses them by kind as a second guard.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local ThrowMath = {}

export type Item = {
	id: number,
	kind: string,
	x: number,
	y: number,
	z: number,
	busy: boolean?, -- carried, flying or waiting to respawn
}

export type Spot = { id: number, kind: string, x: number, z: number, ry: number }

local NEVER = { citizen = true, hero = true, player = true, tram = true }

function ThrowMath.weight(T: any, kind: string): string?
	local k = T.kinds[kind]
	return k and k.weight
end

-- Can a hero of this archetype lift this kind? titan: Lift and Throw (any weight)
function ThrowMath.canLift(
	T: any,
	kind: string,
	classId: string?,
	awakened: boolean,
	titan: boolean?
): boolean
	if NEVER[kind] then
		return false
	end
	local w = ThrowMath.weight(T, kind)
	if not w then
		return false
	end
	if w ~= "heavy" or titan then
		return true
	end
	return awakened or (classId ~= nil and T.heavyFor[classId] == true)
end

-- The nearest free item within reach that `can(kind)` allows; returns its id (or nil) and the distance
function ThrowMath.nearest(
	items: { [any]: any }, -- Items (extra fields are fine)
	px: number,
	py: number,
	pz: number,
	reach: number,
	can: (string) -> boolean
): (number?, number)
	local best, bestD = nil, reach
	for _, it in items do
		if not it.busy and can(it.kind) then
			local dx, dy, dz = it.x - px, it.y - py, it.z - pz
			-- reach is measured flat; a thing more than a storey above or below is out of reach
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= bestD and math.abs(dy) <= reach then
				best, bestD = it.id, d
			end
		end
	end
	return best, bestD
end

-- Where the props stand: every inner north-south Downtown street, both sidewalks, each block row; a fixed
-- seed so every server and every test agrees. Props keep clear of the crossings (|along| <= spread).
function ThrowMath.place(T: any, Config: any): { Spot }
	local P = T.place
	local city = Config.City
	local d = city.districts.Downtown
	local t = city.downtown
	local pitch = t.block + t.street
	local rng = Rng.new(Rng.hash(t.seed, P.seed))
	local total = 0
	for _, m in P.mix do
		total += m[2]
	end
	local function draw(): string
		local r = rng:next() * total
		for _, m in P.mix do
			r -= m[2]
			if r <= 0 then
				return m[1]
			end
		end
		return P.mix[#P.mix][1]
	end
	local list: { Spot } = {}
	local nStreets = math.floor((d.maxX - d.minX) / pitch) + 1
	for k = 1, nStreets - 2 do
		local x = d.minX + k * pitch
		for m = 0, math.floor((d.maxZ - d.minZ) / pitch) - 1 do
			local zc = d.minZ + pitch / 2 + m * pitch
			for _, side in { -1, 1 } do
				for n = 1, P.perSide do
					-- spread the props evenly along the sidewalk, with a little jitter
					local along = -P.spread + (n - 0.5) * (2 * P.spread / P.perSide) + (rng:next() - 0.5) * 6
					table.insert(list, {
						id = #list + 1,
						kind = draw(),
						x = x + side * P.inset,
						z = zc + along,
						ry = if side < 0 then 90 else -90, -- facing the street
					})
				end
			end
		end
	end
	return list
end

-- The throw: from the hand toward the aim point, at most the weight's range. Returns the landing point,
-- the flight time and the arc's peak height above the straight line.
function ThrowMath.arc(
	T: any,
	weight: string,
	fx: number,
	fy: number,
	fz: number,
	ax: number,
	ay: number,
	az: number,
	rangeMult: number?
): (number, number, number, number, number)
	local W = T.weights[weight]
	local dx, dy, dz = ax - fx, ay - fy, az - fz
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	local range = W.range * (rangeMult or 1)
	if dist < 1e-3 then
		dx, dy, dz, dist = 0, 0, -1, 1
	end
	local use = math.min(dist, range)
	local s = use / dist
	local tx, ty, tz = fx + dx * s, fy + dy * s, fz + dz * s
	local time = math.max(T.minFlight, use / W.speed)
	return tx, ty, tz, time, use * W.arc
end

-- A point along the arc at fraction t (0 at the hand, 1 landed)
function ThrowMath.arcPoint(
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
	peak: number,
	t: number
): (number, number, number)
	t = math.clamp(t, 0, 1)
	return fx + (tx - fx) * t, fy + (ty - fy) * t + peak * 4 * t * (1 - t), fz + (tz - fz) * t
end

-- What the landing does: the hit coefficient, the knock, the radius, structure damage and whether it is a
-- breaker. titan: Lift and Throw's bigger nova.
function ThrowMath.hit(T: any, weight: string, titan: boolean?): any
	local W = T.weights[weight]
	return {
		coeff = W.coeff,
		knock = W.knock,
		radius = W.radius * (if titan then T.titan.radiusMult else 1),
		structDmg = if W.struct > 0 then W.struct else nil,
		structKind = W.structKind or 2,
		breaker = W.breaker == true,
		status = "knockback",
		statusDur = 0.4,
	}
end

-- Carrying ends by itself after carryMax seconds
function ThrowMath.carryOver(T: any, since: number, now: number): boolean
	return now - since >= T.carryMax
end

-- Can it be thrown yet (the 0.3 s lift)?
function ThrowMath.lifted(T: any, since: number, now: number): boolean
	return now - since >= T.liftTime
end

-- A thrown prop comes back after `respawn` seconds once no hero is within `viewRadius` of its landing
-- spot or its home (it never pops in or out in front of someone)
function ThrowMath.respawnReady(T: any, landedAt: number, now: number, nearestHero: number): boolean
	return now - landedAt >= T.respawn and nearestHero > T.viewRadius
end

return ThrowMath
