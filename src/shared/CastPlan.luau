--!strict
-- CastPlan: what one ability use does, as pure geometry (spec: Hit resolution, the ability table). The
-- server builds a plan from the hero's rewound position and the aim, then applies it (damage, statuses,
-- dashes, fields, buffs). Lune runs it with fake candidates, so every shape is unit tested.
-- World access is injected: los(o, t) line of sight, rayDist(o, dir, max) studs to the first building,
-- groundY(x, y, z) the floor below a point.

local HitQuery = if script then require(script.Parent.HitQuery) else (require :: any)("./HitQuery")

local CastPlan = {}

export type Candidate = HitQuery.Candidate & { flags: number? }

export type World = {
	los: HitQuery.LosFn?,
	rayDist: (ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, max: number) -> number,
	groundY: (x: number, y: number, z: number) -> number,
}

export type Hit = { c: Candidate, coeff: number, primary: boolean }

export type Plan = {
	shape: string,
	hits: { Hit },
	ox: number,
	oy: number,
	oz: number,
	ex: number?, -- where the effect ends: bolt target, dash end, line end, leap landing
	ey: number?,
	ez: number?,
	cx: number?, -- the area centre (nova, field, throw landing)
	cy: number?,
	cz: number?,
	radius: number?,
	delay: number?, -- seconds before the hits land (leap and throw travel)
	moveHero: boolean?, -- the hero travels to (ex, ey, ez)
	thrown: number?, -- id of the lifted target (Lift and Throw)
	channel: { ids: { number }, ticks: number, tick: number }?,
	field: { x: number, y: number, z: number, follow: boolean }?,
	buff: boolean?,
	ride: boolean?,
	pieces: { { number } }?, -- wall pieces or the ramp: { x, y, z, yawDegrees }
	twin: { number }?, -- a second line's end for Twin Spark and Cross Wave
}

local SLOW_BIT = 4

local function flat(dx: number, dz: number): (number, number)
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-4 then
		return 0, 1
	end
	return dx / l, dz / l
end

local function coeffFor(eff: any, c: Candidate, base: number): number
	local k = base
	if eff.bonusVs == "slow" and c.flags and bit32.band(c.flags, SLOW_BIT) ~= 0 then
		k *= 1 + (eff.bonus or 0)
	end
	return k
end

local function addHits(
	plan: Plan,
	eff: any,
	list: { Candidate },
	coeff: number,
	primary: boolean,
	seen: { [number]: boolean }
)
	for _, c in list do
		if not seen[c.id] then
			seen[c.id] = true
			table.insert(plan.hits, { c = c, coeff = coeffFor(eff, c, coeff), primary = primary })
		end
	end
end

local function splash(plan: Plan, eff: any, cands: { Candidate }, world: World, seen: { [number]: boolean })
	if eff.splash == nil or #plan.hits == 0 then
		return
	end
	local t = plan.hits[1].c
	local around = HitQuery.sphere(t.x, t.y, t.z, eff.radius or 8, cands, world.los)
	addHits(plan, eff, around, eff.coeff * eff.splash, false, seen)
end

-- comboStep: 1..#hits for combo basics. Returns the plan, or nil when the use does nothing.
function CastPlan.build(
	eff: any,
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	hint: number?,
	cands: { Candidate },
	world: World,
	opts: { comboStep: number?, rangeBonus: number?, aimSlack: number?, reach: number? }?
): Plan?
	local o = opts or {}
	local reach = o.reach or 0
	local slack = o.aimSlack or 15
	local shape = eff.shape
	local plan: Plan = { shape = shape, hits = {}, ox = ox, oy = oy, oz = oz }
	local seen: { [number]: boolean } = {}
	local range = (eff.range or 0) + (o.rangeBonus or 0)

	if shape == "bolt" then
		local first = HitQuery.bolt(
			ox,
			oy,
			oz,
			dx,
			dy,
			dz,
			range + reach,
			eff.radius or 3,
			hint,
			slack,
			cands,
			if eff.curve then nil else world.los -- Trick Shot curves around cover
		)
		if first then
			addHits(plan, eff, { first }, eff.coeff, true, seen)
			if eff.targets and eff.targets > 1 then
				-- Two Pulls: the next nearest in a 30 degree cone
				local exclude = { [first.id] = true }
				for _ = 2, eff.targets do
					local nextC =
						HitQuery.cone(ox, oy, oz, dx, dy, dz, range + reach, 30, cands, world.los, exclude)
					if not nextC then
						break
					end
					exclude[nextC.id] = true
					addHits(plan, eff, { nextC }, eff.coeff, true, seen)
				end
			end
			plan.ex, plan.ey, plan.ez = first.x, first.y, first.z
		else
			local d = world.rayDist(ox, oy, oz, dx, dy, dz, range)
			plan.ex, plan.ey, plan.ez = ox + dx * d, oy + dy * d, oz + dz * d
		end
		splash(plan, eff, cands, world, seen)
		if eff.channel then
			local ids = {}
			for _, h in plan.hits do
				table.insert(ids, h.c.id)
			end
			plan.channel = { ids = ids, ticks = eff.channel, tick = eff.tick or 0.25 }
			plan.hits = {} -- the ticks do the damage
		end
	elseif shape == "chain" then
		local first = HitQuery.bolt(ox, oy, oz, dx, dy, dz, range + reach, 4, hint, slack, cands, world.los)
			or HitQuery.cone(ox, oy, oz, dx, dy, dz, range + reach, eff.cone or 30, cands, world.los)
		if first then
			local list = HitQuery.chain(first, cands, eff.targets or 3, eff.jump or 18, world.los)
			addHits(plan, eff, { list[1] }, eff.coeff, true, seen)
			local rest = table.clone(list)
			table.remove(rest, 1)
			addHits(plan, eff, rest, eff.coeff, false, seen)
			local last = list[#list]
			plan.ex, plan.ey, plan.ez = last.x, last.y, last.z
		end
	elseif shape == "dash" then
		-- full range in the open; 3 studs short of a building (Unstoppable goes through: `through`)
		local hit = if eff.through then range else world.rayDist(ox, oy, oz, dx, dy, dz, range)
		local d = if hit < range then math.max(0, hit - 3) else range
		plan.ex, plan.ey, plan.ez = ox + dx * d, oy + dy * d, oz + dz * d
		plan.moveHero = true
		local list = HitQuery.capsule(
			ox,
			oy,
			oz,
			plan.ex :: number,
			plan.ey :: number,
			plan.ez :: number,
			eff.width or 6,
			cands
		)
		addHits(plan, eff, list, eff.coeff, true, seen)
	elseif shape == "cone" then
		local list = HitQuery.coneAll(
			ox,
			oy,
			oz,
			dx,
			dy,
			dz,
			range + reach,
			eff.cone or 40,
			cands,
			world.los,
			eff.maxTargets
		)
		addHits(plan, eff, list, eff.coeff, true, seen)
		plan.ex, plan.ey, plan.ez = ox + dx * range, oy + dy * range, oz + dz * range
	elseif shape == "arc" then
		local coeff = eff.coeff
		if eff.hits then
			local step = math.clamp(o.comboStep or 1, 1, #eff.hits)
			coeff = eff.hits[step] * (eff.coeff / eff.hits[1]) -- rank bonuses scale the whole string
		end
		local list = HitQuery.coneAll(
			ox,
			oy,
			oz,
			dx,
			dy,
			dz,
			range + reach,
			eff.cone or 90,
			cands,
			world.los,
			eff.maxTargets
		)
		addHits(plan, eff, list, coeff, true, seen)
		plan.ex, plan.ey, plan.ez = ox + dx * range, oy + dy * range, oz + dz * range
		if eff.channel then
			local ids = {}
			for _, h in plan.hits do
				table.insert(ids, h.c.id)
			end
			plan.channel = { ids = ids, ticks = eff.channel, tick = eff.tick or 0.15 }
			plan.hits = {}
		end
	elseif shape == "nova" then
		local cx, cy, cz = ox, oy, oz
		if eff.slam then
			cy = world.groundY(ox, oy, oz) + 1.5
			plan.moveHero = true
			plan.ex, plan.ey, plan.ez = ox, cy, oz
		end
		plan.cx, plan.cy, plan.cz, plan.radius = cx, cy, cz, eff.radius
		local list = HitQuery.sphere(cx, cy, cz, eff.radius, cands, world.los)
		addHits(plan, eff, list, eff.coeff, true, seen)
	elseif shape == "line" then
		local lx, ly, lz = dx, dy, dz
		if eff.ground then
			local fx, fz = flat(dx, dz)
			lx, ly, lz = fx, 0, fz
		end
		local d = world.rayDist(ox, oy, oz, lx, ly, lz, range)
		plan.ex, plan.ey, plan.ez = ox + lx * d, oy + ly * d, oz + lz * d
		local list = HitQuery.capsule(
			ox,
			oy,
			oz,
			plan.ex :: number,
			plan.ey :: number,
			plan.ez :: number,
			eff.width or 5,
			cands
		)
		addHits(plan, eff, list, eff.coeff, true, seen)
		if eff.twin then
			-- a second line 25 degrees to the side
			local a = math.rad(25)
			local tx, tz = lx * math.cos(a) - lz * math.sin(a), lx * math.sin(a) + lz * math.cos(a)
			local d2 = world.rayDist(ox, oy, oz, tx, ly, tz, range)
			local ex2, ey2, ez2 = ox + tx * d2, oy + ly * d2, oz + tz * d2
			plan.twin = { ex2, ey2, ez2 }
			addHits(
				plan,
				eff,
				HitQuery.capsule(ox, oy, oz, ex2, ey2, ez2, eff.width or 5, cands),
				eff.coeff,
				true,
				seen
			)
		end
	elseif shape == "leap" then
		-- as the client flies it (CombatClient.fire): a unit ray along the aim (never steeper than -0.2 down)
		-- finds how far, and the hero travels that far along the flat aim, landing on the floor below
		local ry = math.max(dy, -0.2)
		local rl = math.sqrt(dx * dx + ry * ry + dz * dz)
		local rx, rz = dx, dz
		if rl > 1e-4 then
			rx, ry, rz = dx / rl, ry / rl, dz / rl
		end
		local d = math.max(0, world.rayDist(ox, oy + 4, oz, rx, ry, rz, range) - 3)
		local fx, fz = flat(dx, dz)
		local tx, tz = ox + fx * d, oz + fz * d
		local ty = world.groundY(tx, oy + 20, tz) + 3
		plan.ex, plan.ey, plan.ez = tx, ty, tz
		plan.cx, plan.cy, plan.cz, plan.radius = tx, ty, tz, eff.radius
		plan.moveHero = true
		plan.delay = eff.time or 1
		-- hits are found at landing (the server calls CastPlan.area then)
	elseif shape == "throw" then
		local grab: Candidate? = nil
		local best = 12
		for _, c in cands do
			local ddx, ddy, ddz = c.x - ox, c.y - oy, c.z - oz
			local dist = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz) - c.r
			if dist < best then
				grab, best = c, dist
			end
		end
		local d = math.max(0, world.rayDist(ox, oy, oz, dx, dy, dz, range) - 2)
		local tx, tz = ox + dx * d, oz + dz * d
		local ty = world.groundY(tx, oy + dy * d + 5, tz) + 2
		plan.ex, plan.ey, plan.ez = tx, ty, tz
		plan.cx, plan.cy, plan.cz, plan.radius = tx, ty, tz, eff.radius
		plan.thrown = if grab then grab.id else nil
		plan.delay = 0.5
	elseif shape == "field" then
		local fx, fy, fz = ox, oy, oz
		if eff.at == "aim" then
			local d = world.rayDist(ox, oy, oz, dx, dy, dz, range)
			fx, fy, fz = ox + dx * d, oy + dy * d, oz + dz * d
		end
		if eff.at ~= "self" then
			fy = world.groundY(fx, fy + 2, fz) + 1
		end
		plan.field = { x = fx, y = fy, z = fz, follow = eff.at == "self" }
		plan.cx, plan.cy, plan.cz, plan.radius = fx, fy, fz, eff.radius
		-- a field that also buffs the hero (Mech Suit, Siege Mode, Ascended Guardian)
		plan.buff = eff.buff ~= nil
	elseif shape == "buff" then
		plan.buff = true
	elseif shape == "ride" then
		-- a travel power: the hero rides for `duration` (MoveController) at up to `speed`; a start burst
		-- hits around the hero when the row has a radius
		plan.ride = true
		if eff.radius and (eff.coeff or 0) > 0 then
			plan.cx, plan.cy, plan.cz, plan.radius = ox, oy, oz, eff.radius
			addHits(
				plan,
				eff,
				HitQuery.sphere(ox, oy, oz, eff.radius, cands, world.los),
				eff.coeff,
				true,
				seen
			)
		end
	elseif shape == "place" then
		-- a point on the ground along the aim (Holo Decoy): something is set down there
		local d = world.rayDist(ox, oy, oz, dx, dy, dz, range)
		local px, pz = ox + dx * d, oz + dz * d
		local py = world.groundY(px, oy + dy * d + 2, pz) + 1
		plan.cx, plan.cy, plan.cz, plan.radius = px, py, pz, eff.radius or 0
		if (eff.radius or 0) > 0 and (eff.coeff or 0) > 0 then
			addHits(
				plan,
				eff,
				HitQuery.sphere(px, py, pz, eff.radius, cands, world.los),
				eff.coeff,
				true,
				seen
			)
		end
	elseif shape == "launch" then
		-- the hero springs up `up` studs and `forward` along the flat aim (Sky Step, Recoil Jump, Stone
		-- Pillar); what stands where it left is hit (radius)
		local fx, fz = flat(dx, dz)
		local fwd = math.min(eff.forward or 0, world.rayDist(ox, oy, oz, fx, 0, fz, eff.forward or 0))
		plan.ex, plan.ey, plan.ez = ox + fx * fwd, oy + (eff.up or 30), oz + fz * fwd
		plan.moveHero = true
		if eff.radius then
			plan.cx, plan.cy, plan.cz, plan.radius = ox, oy, oz, eff.radius
			addHits(
				plan,
				eff,
				HitQuery.sphere(ox, oy, oz, eff.radius, cands, world.los),
				eff.coeff,
				true,
				seen
			)
		end
	elseif shape == "wall" then
		local fx, fz = flat(dx, dz)
		local px, pz = -fz, fx
		local n = eff.pieces or 3
		local gap = 7
		local cx, cz = ox + fx * 10, oz + fz * 10
		local gy = world.groundY(cx, oy + 2, cz)
		local yaw = math.deg(math.atan2(-fx, -fz))
		plan.pieces = {}
		for i = 1, n do
			local off = (i - (n + 1) / 2) * gap
			table.insert(plan.pieces :: { { number } }, { cx + px * off, gy + 4, cz + pz * off, yaw })
		end
	elseif shape == "ramp" then
		local fx, fz = flat(dx, dz)
		local gy = world.groundY(ox, oy, oz)
		local yaw = math.deg(math.atan2(-fx, -fz))
		plan.pieces = { { ox + fx * (range / 2 + 2), gy, oz + fz * (range / 2 + 2), yaw } }
		plan.ex, plan.ey, plan.ez = ox + fx * range, gy, oz + fz * range
	else
		return nil
	end
	return plan
end

-- What one field tick hits with: the field's own coeff and status (or the row's), plus the row's slot and
-- set, so a super's field keeps PvP's super rule (FlagService.damage) and the Epic set bonus on every tick.
-- f: the live field ({ coeff, tick, status?, statusDur?, slow? })
function CastPlan.tickEff(eff: any, f: any): any
	local out = {
		coeff = f.coeff,
		status = if f.status ~= nil then f.status else eff.status,
		statusDur = f.statusDur or math.max(eff.statusDur or 0, f.tick + 0.15),
		slow = f.slow or eff.slow,
		slot = eff.slot,
		set = eff.set,
	}
	if out.status == "pull" then
		out.statusDur = f.tick + 0.1
	end
	return out
end

-- Which field to drop when the server is at its field cap: the caster's own oldest, else the oldest of all
-- (so one hero's spam never wipes another player's fields). list: oldest first, each with `hero`.
function CastPlan.evictIndex(list: { any }, owner: any): number
	for i, f in list do
		if f.hero == owner then
			return i
		end
	end
	return 1
end

-- The hits of an area that lands later (leap, throw, echoes, field ticks)
function CastPlan.area(
	x: number,
	y: number,
	z: number,
	radius: number,
	cands: { Candidate },
	los: HitQuery.LosFn?
): { Candidate }
	return HitQuery.sphere(x, y, z, radius, cands, los)
end

return CastPlan
