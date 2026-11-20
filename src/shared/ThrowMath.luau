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
		knockKind = W.knockKind, -- (destroy-all round 4: a medium or heavy throw launches the robots it hits)
	}
end

-- Carrying ends by itself after carryMax seconds
function ThrowMath.carryOver(T: any, since: number, now: number): boolean
	return now - since >= T.carryMax
end

-- Grab a robot and swing it (nate, 2026-11-19 13:18Z; Config.Throw.swing). May a live robot of this row be
-- grabbed with `stunLeft` seconds of stun (or a launch) on it? Never mini-bosses, the rows canWreck turns down
-- (fakes, twins, sea robots, creatures, pack robots) or one immune to knockback.
function ThrowMath.canHoldRobot(T: any, cfg: any, stunLeft: number): boolean
	if not ThrowMath.canWreck(cfg) or cfg.miniBoss or cfg.boss then
		return false
	end
	if cfg.immune and table.find(cfg.immune, "knockback") then
		return false
	end
	return stunLeft >= T.swing.robot.stunAtLeast
end

-- May the holder swing again? (swings so far, the last swing's time)
function ThrowMath.swingReady(T: any, swings: number, last: number, now: number): boolean
	return swings < T.swing.max and now - last >= T.swing.gap
end

-- What a held thing swings as: a robot's wreck or a live robot (the props stay throw-only)
function ThrowMath.swingable(T: any, kind: string?): boolean
	local k = kind and T.kinds[kind]
	return k ~= nil and (k.wreck == true or k.robot == true)
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

---------------------------------------------------------------------------
-- Downed robots (WP6, gap G10): a beaten robot leaves a wreck, a medium throwable (Config.Throw.wreck)
---------------------------------------------------------------------------

-- Does a robot of this Config.Enemies row leave a wreck? Every machine does, except the famous fakes, the twins
-- and the costumed finale villains (mini-bosses with their own endings), cartoon creatures (they burst into
-- light), sea robots (no throwing under water) and the small pack robots (Swarmers, Wind-Up Toys: a pack would
-- fill the cap at once). A row can opt out with wreck = false.
function ThrowMath.canWreck(cfg: any): boolean
	if not cfg or cfg.wreck == false or cfg.fake or cfg.sea or cfg.twin then
		return false
	end
	local body = cfg.body
	return not (body and (body.small or body.creature))
end

-- The wreck's heap box (x, y, z studs) for a robot row: shares of its height by build
function ThrowMath.wreckSize(T: any, cfg: any): (number, number, number)
	local body = cfg.body or {}
	local h = body.height or 6
	local share = T.wreck.size[body.build or "normal"] or T.wreck.size.normal
	return math.max(1.5, h * share[1]), math.max(1, h * share[2]), math.max(1.2, h * share[3])
end

export type Wreck = { id: number, busy: boolean?, born: number }

-- Room for one more wreck under the cap: (true, nil) when there is room, (true, id) when the oldest wreck
-- nobody holds or throws must go first, (false, nil) when every wreck is in someone's hands or in the air
function ThrowMath.wreckRoom(list: { Wreck }, max: number): (boolean, number?)
	if #list < max then
		return true, nil
	end
	local oldest: Wreck? = nil
	for _, w in list do
		if
			not w.busy
			and (oldest == nil or w.born < oldest.born or (w.born == oldest.born and w.id < oldest.id))
		then
			oldest = w
		end
	end
	if oldest then
		return true, oldest.id
	end
	return false, nil
end

-- When a wreck falls apart: `life` after it fell, or `after` once it was thrown or set down; never while held
-- or flying (busy)
function ThrowMath.wreckEnds(T: any, at: number, handled: boolean): number
	return at + (if handled then T.wreck.after else T.wreck.life)
end

function ThrowMath.wreckGone(endsAt: number, now: number, busy: boolean?): boolean
	return not busy and now >= endsAt
end

return ThrowMath
