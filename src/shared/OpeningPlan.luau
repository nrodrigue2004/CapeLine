--!strict
-- OpeningPlan: where the playable disaster happens for one new hero (spec: First 30 seconds and the
-- playable disaster). Pure, from the world data, so Lune checks every point is real for any weekly seed:
-- * start: a roof 30 to 90 studs up near the plaza, next to a tram line
-- * leap: the next roof, 30 to 75 studs away (one Leap reaches 80), toward the tram
-- * tram: the tram car hanging off the broken rail, on the street below (Glide down to it)
-- * drones: where the two Spark Drones come from
-- * shard: the glowing shard beside a trapped citizen, on open ground near the tram
-- * pad: Save Her: the rooftop pad 120 to 200 studs away
-- * escape: Grab It: the Docks marker 260 to 340 studs away, toward the Docks
-- * beacon: the first beacon for the guided flight (the nearest to the plaza)

local IncidentSpots = if script
	then require(script.Parent.IncidentSpots)
	else (require :: any)("./IncidentSpots")

local OpeningPlan = {}

export type Route = {
	start: { number },
	leap: { number },
	tram: { number },
	drones: { number },
	shard: { number },
	pad: { number },
	escape: { number },
	beacon: number,
	beaconAt: { number },
}

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

local function roofPoint(b: any): { number }
	return { b.x, b.top + 1.5, b.z }
end

-- The plaza: the Beacon Tower's square in Downtown
function OpeningPlan.plaza(world: any): (number, number)
	local bt = world.downtown and world.downtown.beacon
	return if bt then bt.x else -400, if bt then bt.z else 0
end

function OpeningPlan.route(Config: any, world: any, rng: any): Route?
	local O = Config.Story.opening
	local gy = Config.City.ground.y
	local px, pz = OpeningPlan.plaza(world)
	-- the tram car: on the tram line nearest the plaza
	local tram = IncidentSpots.find(Config, world, "tram", px, pz, 0, 600, rng, { run = 120 })
	if not tram then
		return nil
	end
	local tx, tz = tram.x, tram.z
	-- the start roof: 60 to 200 studs from the tram, 30 to 90 up, near the plaza; then a neighbour
	-- within one Leap that is closer to the tram
	local starts = {}
	for _, b in world.buildings do
		local h = b.top - gy
		if
			b.district == "Downtown"
			and h >= O.startRoof.minH
			and h <= O.startRoof.maxH
			and dist(b.x, b.z, px, pz) <= O.startRoof.near
		then
			local dt = dist(b.x, b.z, tx, tz)
			if dt >= 80 and dt <= 240 then
				table.insert(starts, b)
			end
		end
	end
	table.sort(starts, function(a, b)
		return a.id < b.id
	end)
	local start, leap = nil, nil
	local offset = if #starts > 0 then rng:int(1, #starts) else 1
	for k = 0, #starts - 1 do
		local s = starts[(offset + k - 1) % #starts + 1]
		local best, bestD = nil, math.huge
		for _, b in world.buildings do
			local gap = dist(b.x, b.z, s.x, s.z)
			local h = b.top - gy
			if
				b.id ~= s.id
				and gap >= O.leapRoof.minGap
				and gap <= O.leapRoof.maxGap
				and h >= 18
				and b.top <= s.top + 12
			then
				local dt = dist(b.x, b.z, tx, tz)
				if dt < dist(s.x, s.z, tx, tz) and dt < bestD then
					best, bestD = b, dt
				end
			end
		end
		if best then
			start, leap = s, best
			break
		end
	end
	if not start or not leap then
		return nil
	end
	-- the shard and the trapped citizen: open ground 40 to 90 studs from the tram
	local shard = IncidentSpots.find(Config, world, "street", tx, tz, 40, 90, rng)
	if not shard then
		return nil
	end
	-- Save: a roof 120 to 200 studs from the shard
	local pads = {}
	for _, b in world.buildings do
		local d = dist(b.x, b.z, shard.x, shard.z)
		if d >= O.rescueGap[1] and d <= O.rescueGap[2] and b.top - gy >= 20 and b.top - gy <= 80 then
			table.insert(pads, b)
		end
	end
	if #pads == 0 then
		return nil
	end
	table.sort(pads, function(a, b)
		return a.id < b.id
	end)
	local pad = pads[rng:int(1, #pads)]
	-- Grab: open ground 260 to 340 studs away, the one nearest the Docks
	local docks = Config.City.districts.Docks
	local dx, dz = (docks.minX + docks.maxX) / 2, (docks.minZ + docks.maxZ) / 2
	local escape, escapeD = nil, math.huge
	for _ = 1, 12 do
		local s = IncidentSpots.find(Config, world, "street", shard.x, shard.z, O.escape[1], O.escape[2], rng)
		if s then
			local d = dist(s.x, s.z, dx, dz)
			if d < escapeD then
				escape, escapeD = s, d
			end
		end
	end
	if not escape then
		return nil
	end
	-- the first beacon: the nearest to the plaza
	local beacon, beaconD, beaconAt = 0, math.huge, { px, gy, pz }
	for id, b in world.beacons do
		local d = dist(b.x, b.z, px, pz)
		if d < beaconD then
			beacon, beaconD, beaconAt = id, d, { b.x, b.y, b.z }
		end
	end
	return {
		start = roofPoint(start),
		leap = roofPoint(leap),
		tram = { tx, gy + 0.2, tz },
		drones = { tx + (shard.x - tx) * 0.5, gy + 16, tz + (shard.z - tz) * 0.5 },
		shard = { shard.x, shard.y, shard.z },
		pad = roofPoint(pad),
		escape = { escape.x, escape.y, escape.z },
		beacon = beacon,
		beaconAt = beaconAt,
	}
end

-- Is a hero at a target? (within reach on the ground plane, and not far below it)
function OpeningPlan.at(
	Config: any,
	target: { number },
	x: number,
	y: number,
	z: number,
	reach: number?
): boolean
	local r = reach or Config.Story.opening.reach
	return dist(x, z, target[1], target[3]) <= r and y >= target[2] - 4 and y <= target[2] + 40
end

-- The opening's beats in order (the server runs them; the client pulses one verb button per beat)
OpeningPlan.STEPS = { "leap", "glide", "catch", "blast", "choice", "save", "grab", "suitup", "flight" }
OpeningPlan.CODE = {}
for i, s in OpeningPlan.STEPS do
	OpeningPlan.CODE[s] = i
end

return OpeningPlan
