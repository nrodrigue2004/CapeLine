--!strict
-- WorldMap: the whole city as plain data for one seed (spec: Map layout; Server lifecycle steps 2 and 3).
-- build(Config, seed) gives the hub (Downtown, the Docks, Old Town and filler tiles), the outskirts tile
-- plans, the landmarks, the 16 safehouses with their terminals and respawn points, the 12 fast-travel
-- beacons, the base (ground, sand, ocean, roads) and a heightmap of everything. The server builds parts
-- from it (the hub at once, the outskirts 40 tiles a frame); the tests check it in Lune.

local CityLayout = if script then require(script.Parent.CityLayout) else (require :: any)("./CityLayout")
local Districts = if script then require(script.Parent.Districts) else (require :: any)("./Districts")
local WorldGen = if script then require(script.Parent.WorldGen) else (require :: any)("./WorldGen")
local HeightMap = if script then require(script.Parent.HeightMap) else (require :: any)("./HeightMap")
local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local WorldMap = {}

type Box = BoxKit.Box
type Point = { x: number, y: number, z: number }

export type Safehouse = {
	id: number,
	name: string,
	district: string,
	x: number,
	y: number, -- the pad top
	z: number,
	roofY: number,
	respawn: { Point },
	terminals: { [string]: Point },
}

export type Beacon = { id: number, name: string, x: number, y: number, z: number }

-- A wreckable hub building (spec: Destruction, 220 in the hub)
export type Building = {
	id: number,
	grp: string,
	district: string,
	x: number,
	z: number,
	sx: number,
	sz: number,
	base: number, -- the bottom of its body
	top: number, -- the top of its body (roofs and props stand above)
	size: string, -- small, medium or tower
	hp: number,
}

export type World = {
	seed: number,
	tiles: buffer,
	hash: string,
	downtown: any,
	hubBoxes: { Box }, -- Downtown, the Docks, Old Town, safehouses and beacons: built at boot
	baseBoxes: { Box }, -- ground, sand, ocean and road strips: built at boot
	tilePlans: { { tx: number, tz: number, boxes: { Box } } }, -- hub filler and outskirts, built in batches
	landmarks: { WorldGen.Landmark },
	safehouses: { [number]: Safehouse },
	beacons: { [number]: Beacon },
	buildings: { Building }, -- by id
	spawns: { Point },
	spots: { [string]: Point },
	heights: HeightMap.HeightMap,
	parts: { hub: number, base: number, outskirts: number, landmarks: number, total: number },
}

local function append(into: { Box }, from: { Box })
	table.move(from, 1, #from, #into + 1, into)
end

-- A safehouse: a pad, a shelter with a roof and a sign, and the bank, loadout, respawn and contract board
-- terminals (the board from M6)
local function buildSafehouse(list: { Box }, w: any, s: any, x: number, z: number, gy: number): Safehouse
	local c = w.safehouse
	local pad = c.pad
	local top = gy + 1.2
	BoxKit.box(list, "plaza", x, gy + 0.6, z, pad, 1.2, pad, "safe", { tag = "safehouse", ref = s.id })
	local shelterZ = z - pad / 2 + 7
	BoxKit.box(list, "building", x, top + 6, shelterZ, 22, 12, 10, "slate")
	BoxKit.box(list, "ledge", x, top + 12.75, shelterZ + 3, 28, 1.5, 18, "safe")
	BoxKit.box(list, "glow", x, top + 10, shelterZ + 5.2, 14, 2, 0.4, "beaconGlow", { ghost = true })
	local terminals = {}
	for i, kind in { "bank", "loadout", "respawn", "contracts" } do
		local tx = x + (i - 2) * 8
		local tz = shelterZ + 8
		BoxKit.box(list, "terminal", tx, top + 2.5, tz, 3, 5, 2, kind, { tag = kind, ref = s.id })
		terminals[kind] = { x = tx, y = top + 2.5, z = tz }
	end
	local respawn = {}
	for k = 1, c.respawnPoints do
		local a = (k - 2) * 0.9
		table.insert(
			respawn,
			{ x = x + math.sin(a) * pad * 0.35, y = top + 3, z = z + math.cos(a) * pad * 0.3 }
		)
	end
	return {
		id = s.id,
		name = s.name,
		district = s.district,
		x = x,
		y = top,
		z = z,
		roofY = top + 13.5,
		respawn = respawn,
		terminals = terminals,
	}
end

-- A fast-travel beacon: a disc, a post and a tall light beam you can see from far away
local function buildBeacon(list: { Box }, w: any, b: any, p: Point): Beacon
	local c = w.beacon
	BoxKit.box(
		list,
		"beacon",
		p.x,
		p.y + 0.4,
		p.z,
		10,
		0.8,
		10,
		"beacon",
		{ shape = "cylinder", tag = "beacon", ref = b.id }
	)
	BoxKit.box(
		list,
		"prop",
		p.x,
		p.y + 0.8 + c.height / 2,
		p.z,
		1.5,
		c.height,
		1.5,
		"steel",
		{ tag = "beaconPost", ref = b.id }
	)
	BoxKit.box(
		list,
		"glow",
		p.x,
		p.y + 0.8 + c.height + 30,
		p.z,
		3,
		60,
		3,
		"beaconLight",
		{ shape = "cylinder", ghost = true, tag = "beam", ref = b.id }
	)
	return { id = b.id, name = b.name, x = p.x, y = p.y + 1, z = p.z }
end

local function tallestNear(buildings: { any }, x: number, z: number, r: number, gy: number): Point
	local best: Point = { x = x, y = gy, z = z }
	for _, b in buildings do
		if (b.x - x) ^ 2 + (b.z - z) ^ 2 <= r * r and gy + b.h > best.y then
			best = { x = b.x, y = gy + b.h, z = b.z }
		end
	end
	return best
end

function WorldMap.build(Config: any, seed: number): World
	local city = Config.City
	local w = Config.World
	local gy = city.ground.y

	-- the hub: Downtown first (its reserved lots decide where its safehouses stand)
	local downtown = CityLayout.downtown(city, w)
	local safeSpots: { [number]: { x: number, z: number, gy: number } } = {}
	for _, s in w.safehouses do
		if s.lot then
			local spot = downtown.safehouseSpots[s.id]
			safeSpots[s.id] = { x = spot.x, z = spot.z, gy = gy }
		elseif s.tile then
			local x0, z0 = WorldGen.tileOrigin(city, s.tile[1], s.tile[2])
			safeSpots[s.id] = { x = x0 + city.tile / 2, z = z0 + city.tile / 2, gy = gy }
		else
			safeSpots[s.id] = { x = s.x, z = s.z, gy = gy }
		end
	end
	local clear: { BoxKit.Circle } = {}
	for _, spot in safeSpots do
		table.insert(clear, { x = spot.x, z = spot.z, r = w.safehouse.pad * 0.75 })
	end
	local docks = Districts.docks(city, clear)
	local oldTown = Districts.oldTown(city, clear)

	local buildings = WorldMap.pickBuildings(Config, downtown, docks, oldTown)
	local byGrp: { [string]: number } = {}
	for _, b in buildings do
		byGrp[b.grp] = b.id
	end
	for _, list in { downtown.boxes, docks.boxes, oldTown.boxes } do
		for _, b in list do
			if b.grp then
				b.bid = byGrp[b.grp]
			end
		end
	end

	local hubBoxes: { Box } = {}
	append(hubBoxes, downtown.boxes)
	append(hubBoxes, docks.boxes)
	append(hubBoxes, oldTown.boxes)

	-- the outskirts
	local tiles = WorldGen.tiles(city, w, seed)
	local tilePlans = {}
	local outskirtsParts = 0
	local n = w.tiles
	for tz = 0, n - 1 do
		for tx = 0, n - 1 do
			local plan = WorldGen.tilePlan(city, w, tiles, seed, tx, tz, clear)
			if #plan > 0 then
				table.insert(tilePlans, { tx = tx, tz = tz, boxes = plan })
				outskirtsParts += #plan
			end
		end
	end
	local landmarks = {}
	local landmarkParts = 0
	for i in w.landmarks do
		local lm = WorldGen.landmark(city, w, i)
		landmarks[i] = lm
		landmarkParts += #lm.boxes
	end
	local baseBoxes = WorldGen.base(city, w, tiles)

	-- safehouses and beacons
	local safehouses: { [number]: Safehouse } = {}
	for _, s in w.safehouses do
		local spot = safeSpots[s.id]
		safehouses[s.id] = buildSafehouse(hubBoxes, w, s, spot.x, spot.z, spot.gy)
	end
	local spots: { [string]: Point } = table.clone(docks.spots)
	for k, v in oldTown.spots do
		spots[k] = v
	end
	local beacons: { [number]: Beacon } = {}
	for _, b in w.beacons do
		local p: Point
		if b.at == "plaza" then
			local bt = downtown.beacon
			-- on the roof, in a corner clear of the glowing crown
			p = { x = bt.x + 17, y = gy + 1 + bt.h, z = bt.z + 17 }
		elseif b.at == "roof" then
			p = tallestNear(downtown.buildings, b.x, b.z, 60, gy)
		elseif b.at == "crane" or b.at == "clock" then
			p = spots[b.at]
		elseif b.at == "safehouse" then
			local s = safehouses[b.safehouse]
			p = { x = s.x, y = s.roofY, z = s.z - w.safehouse.pad / 2 + 10 }
		elseif b.at == "tile" then
			local x0, z0 = WorldGen.tileOrigin(city, b.tile[1], b.tile[2])
			p = { x = x0 + city.tile / 2, y = gy + WorldGen.windmill.height + 11, z = z0 + city.tile / 2 }
		else
			p = { x = 0, y = gy, z = 0 }
			for _, lm in landmarks do
				if lm.id == b.at then
					p = lm.spot
				end
			end
		end
		beacons[b.id] = buildBeacon(hubBoxes, w, b, p)
	end

	-- heights of everything
	local heights = HeightMap.new(city.mapSize, w.heightCell, w.coast.waterY)
	for _, b in hubBoxes do
		HeightMap.stamp(heights, b)
	end
	for _, plan in tilePlans do
		for _, b in plan.boxes do
			HeightMap.stamp(heights, b)
		end
	end
	for _, lm in landmarks do
		for _, b in lm.boxes do
			HeightMap.stamp(heights, b)
		end
	end

	local hubParts = #hubBoxes
	return {
		seed = seed,
		tiles = tiles,
		hash = WorldGen.hash(tiles),
		downtown = downtown,
		hubBoxes = hubBoxes,
		baseBoxes = baseBoxes,
		tilePlans = tilePlans,
		landmarks = landmarks,
		safehouses = safehouses,
		beacons = beacons,
		buildings = buildings,
		spawns = downtown.spawns,
		spots = spots,
		heights = heights,
		parts = {
			hub = hubParts,
			base = #baseBoxes,
			outskirts = outskirtsParts,
			landmarks = landmarkParts,
			total = hubParts + #baseBoxes + outskirtsParts + landmarkParts,
		},
	}
end

-- The wreckable buildings: all of Downtown, the Docks warehouses, then Old Town houses picked by a fixed
-- hash until Config.Destruction.hubBuildings is reached. Ids are 1..n in that order, the same every week.
function WorldMap.pickBuildings(Config: any, downtown: any, docks: any, oldTown: any): { Building }
	local D = Config.Destruction
	local list: { Building } = {}
	local function add(b: any, district: string, base: number, top: number)
		local h = top - base
		local size = if h <= D.smallMax then "small" elseif h <= D.mediumMax then "medium" else "tower"
		table.insert(list, {
			id = #list + 1,
			grp = b.grp,
			district = district,
			x = b.x,
			z = b.z,
			sx = b.sx,
			sz = b.sz,
			base = base,
			top = top,
			size = size,
			hp = D.hp[size],
		})
	end
	local gy = Config.City.ground.y
	for _, b in downtown.buildings do
		if b.grp then
			add(b, "Downtown", b.base or gy, gy + b.h)
		end
	end
	for _, b in docks.buildings do
		add(b, "Docks", b.base, b.base + b.h)
	end
	local old = table.clone(oldTown.buildings)
	local seed = Config.City.oldTown.seed
	table.sort(old, function(a, b)
		return Rng.hash(seed, math.floor(a.x), math.floor(a.z))
			< Rng.hash(seed, math.floor(b.x), math.floor(b.z))
	end)
	for _, b in old do
		if #list >= D.hubBuildings then
			break
		end
		add(b, "OldTown", b.base, b.base + b.h)
	end
	return list
end

function WorldMap.heightAt(world: World, x: number, z: number): number
	return HeightMap.at(world.heights, x, z)
end

-- The nearest safehouse to a point, from a set of allowed ids (nil = all)
function WorldMap.nearestSafehouse(
	world: World,
	x: number,
	z: number,
	allowed: { [number]: boolean }?
): Safehouse?
	local best, bestD = nil, math.huge
	for id, s in world.safehouses do
		if allowed == nil or allowed[id] then
			local d = (s.x - x) ^ 2 + (s.z - z) ^ 2
			if d < bestD then
				best, bestD = s, d
			end
		end
	end
	return best
end

return WorldMap
