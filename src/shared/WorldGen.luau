--!strict
-- WorldGen: the weekly seed and the seeded outskirts (spec: Procedural outskirts; Server lifecycle step 3).
-- * weekSeed(t) = ISO year x 100 + ISO week, from the UTC date, so every server agrees all week.
-- * tiles(seed): the 48 x 48 tile array, 2 bytes a tile (4,608 bytes), packed as
--   zone (3 bits) | variant (5) | rotation (2) | local road N-S (1) | E-W (1) | highway N-S (1) | E-W (1).
--   Pass order as in the spec: terrain and coast (zone rings), highways every 6 tiles, local roads every 3,
--   zone fill (variant and rotation), then props (tilePlan). Hub tiles never depend on the seed.
-- * hash(tiles): FNV-1a over the 4,608 bytes; two servers with the same seed must log the same hash.
-- * tilePlan: the boxes one tile creates (25 or fewer on average). Suburb, farm and hub-filler tiles split
--   into 4 lots around their roads; the variant says what stands on each lot and the rotation turns that
--   pattern a quarter turn at a time. Coast tiles are beaches, piers, lighthouses and dunes.
-- * base: the ground, the coast sand, the ocean past the map edge and the long road strips.
-- * landmark: The Crater (id CometCrater; a blasted Crane lab, lore step 9), Radio Hill and the Old Quarry, hand-placed on fixed tiles.
-- PLACEHOLDER ART: simple parts until the kit pass (M5). With Config.City.kit (overhaul step 5) the outskirts
-- and hub filler are dressed after each lot is built (no random draws change): clapboard, plaster and brick
-- fronts, clay-tiled roofs, paved filler sidewalks and asphalt roads, mailboxes and bushes by the houses,
-- benches and bins by the shops, lamps on the filler blocks and power poles along the country roads.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")
local CraterArtKit = if script
	then require(script.Parent.CraterArtKit)
	else (require :: any)("./CraterArtKit")

local WorldGen = {}

type Box = BoxKit.Box
local box = BoxKit.box

-----------------------------------------------------------------------------------------------------------
-- Dates: the ISO week from a Unix time (UTC)
-----------------------------------------------------------------------------------------------------------

-- Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm, proleptic Gregorian)
function WorldGen.daysFromCivil(y: number, m: number, d: number): number
	y -= if m <= 2 then 1 else 0
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = if m > 2 then m - 3 else m + 9
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

function WorldGen.civilFromDays(days: number): (number, number, number)
	local z = days + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe =
		math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return y, m, d
end

-- ISO 8601 year and week for a Unix time. Weeks start on Monday 00:00 UTC.
function WorldGen.isoWeek(t: number): (number, number)
	local days = math.floor(t / 86400)
	local weekday = (days + 3) % 7 + 1 -- 1970-01-01 was a Thursday; Monday = 1
	local thursday = days - weekday + 4
	local y = WorldGen.civilFromDays(thursday)
	local jan1 = WorldGen.daysFromCivil(y, 1, 1)
	return y, math.floor((thursday - jan1) / 7) + 1
end

function WorldGen.weekSeed(t: number): number
	local y, w = WorldGen.isoWeek(t)
	return y * 100 + w
end

-----------------------------------------------------------------------------------------------------------
-- The tile array
-----------------------------------------------------------------------------------------------------------

local ROAD_NS, ROAD_EW, HWY_NS, HWY_EW = 1024, 2048, 4096, 8192

export type Tile = {
	zone: number,
	variant: number,
	rot: number,
	roadNS: boolean,
	roadEW: boolean,
	hwyNS: boolean,
	hwyEW: boolean,
}

function WorldGen.encode(zone: number, variant: number, rot: number, flags: number): number
	return zone + variant * 8 + rot * 256 + flags
end

function WorldGen.decode(v: number): Tile
	return {
		zone = v % 8,
		variant = math.floor(v / 8) % 32,
		rot = math.floor(v / 256) % 4,
		roadNS = bit32.btest(v, ROAD_NS),
		roadEW = bit32.btest(v, ROAD_EW),
		hwyNS = bit32.btest(v, HWY_NS),
		hwyEW = bit32.btest(v, HWY_EW),
	}
end

-- How many tiles out from the hub edge (0 inside the hub, 16 at the map edge)
function WorldGen.ring(w: any, tx: number, tz: number): number
	local dx = if tx < w.hubFirst then w.hubFirst - tx elseif tx > w.hubLast then tx - w.hubLast else 0
	local dz = if tz < w.hubFirst then w.hubFirst - tz elseif tz > w.hubLast then tz - w.hubLast else 0
	return math.max(dx, dz)
end

-- The min corner of a tile in studs
function WorldGen.tileOrigin(cityCfg: any, tx: number, tz: number): (number, number)
	local half = cityCfg.mapSize / 2
	return -half + tx * cityCfg.tile, -half + tz * cityCfg.tile
end

function WorldGen.tileOf(cityCfg: any, x: number, z: number): (number, number)
	local half = cityCfg.mapSize / 2
	return math.floor((x + half) / cityCfg.tile), math.floor((z + half) / cityCfg.tile)
end

function WorldGen.landmarkAt(w: any, tx: number, tz: number): (number?, boolean)
	for i, lm in w.landmarks do
		if tx >= lm.tx and tx < lm.tx + lm.size and tz >= lm.tz and tz < lm.tz + lm.size then
			return i, tx == lm.tx and tz == lm.tz
		end
	end
	return nil, false
end

local function specialAt(w: any, tx: number, tz: number): boolean
	for _, s in w.safehouses do
		if s.tile and s.tile[1] == tx and s.tile[2] == tz then
			return true
		end
	end
	for _, b in w.beacons do
		if b.tile and b.tile[1] == tx and b.tile[2] == tz then
			return true
		end
	end
	return false
end

local function touchesDistrict(cityCfg: any, tx: number, tz: number): boolean
	local x0, z0 = WorldGen.tileOrigin(cityCfg, tx, tz)
	local x1, z1 = x0 + cityCfg.tile, z0 + cityCfg.tile
	for _, d in cityCfg.districts do
		if x0 < d.maxX and x1 > d.minX and z0 < d.maxZ and z1 > d.minZ then
			return true
		end
	end
	-- the city park (2026-11-20; Shared.ParkLayout builds it): its tiles stay empty like a district's
	local p = cityCfg.park
	return p ~= nil and x0 < p.maxX and x1 > p.minX and z0 < p.maxZ and z1 > p.minZ
end

-- The whole map as a packed tile array for this seed
function WorldGen.tiles(cityCfg: any, w: any, seed: number): buffer
	local n = w.tiles
	local tiles = buffer.create(n * n * 2)
	local Z = w.zones
	local roads = w.roads
	for tz = 0, n - 1 do
		for tx = 0, n - 1 do
			local ring = WorldGen.ring(w, tx, tz)
			local zone, variant, rot, flags = 0, 0, 0, 0
			local lm = WorldGen.landmarkAt(w, tx, tz)
			if ring > 0 and touchesDistrict(cityCfg, tx, tz) then
				-- a district out of the hub (Uptown): fixed like the hub, built by its own layout, no roads
				zone = Z.hub
			elseif ring == 0 then
				-- the hub is fixed: districts, or a filler tile from the hub's own seed
				if not touchesDistrict(cityCfg, tx, tz) then
					local h = Rng.hash(cityCfg.hubFill.seed, tx, tz)
					zone = Z.hubFill
					variant = h % w.variants.hubFill
					rot = math.floor(h / 256) % 4
				end
			elseif lm then
				zone, variant = Z.landmark, lm
			else
				-- terrain: the suburb edge wobbles by a tile in 4 x 4 blocks so the rings are not square
				local wobble = Rng.hash(seed, math.floor(tx / 4), math.floor(tz / 4), 1) % 3 - 1
				if ring > w.rings.farmlandTo then
					zone = Z.coast
				elseif ring <= w.rings.suburbsTo + wobble then
					zone = Z.suburbs
				else
					zone = Z.farmland
				end
				local rng = Rng.new(Rng.hash(seed, tx, tz, 2))
				if specialAt(w, tx, tz) then
					variant = w.special
				elseif zone == Z.coast then
					variant = rng:int(0, w.variants.coast - 1)
				elseif zone == Z.suburbs then
					variant = rng:int(0, w.variants.suburbs - 1)
				else
					variant = rng:int(0, w.variants.farmland - 1)
				end
				rot = rng:int(0, 3)
				if zone ~= Z.coast and variant ~= w.special then
					if tx % roads.localEvery == 0 then
						flags += ROAD_NS
					end
					if tz % roads.localEvery == 0 then
						flags += ROAD_EW
					end
					if tx % roads.highwayEvery == 0 then
						flags += HWY_NS
					end
					if tz % roads.highwayEvery == 0 then
						flags += HWY_EW
					end
				end
			end
			buffer.writeu16(tiles, (tz * n + tx) * 2, WorldGen.encode(zone, variant, rot, flags))
		end
	end
	return tiles
end

function WorldGen.get(w: any, tiles: buffer, tx: number, tz: number): Tile
	return WorldGen.decode(buffer.readu16(tiles, (tz * w.tiles + tx) * 2))
end

-- FNV-1a (32-bit) of the tile bytes, as 8 hex digits
function WorldGen.hash(tiles: buffer): string
	local h = 0x811C9DC5
	for i = 0, buffer.len(tiles) - 1 do
		h = bit32.bxor(h, buffer.readu8(tiles, i))
		local lo = bit32.band(h, 0xFFFF) * 16777619
		local hi = bit32.rshift(h, 16) * 16777619
		h = (lo + (hi % 65536) * 65536) % 4294967296
	end
	return string.format("%08x", h)
end

-----------------------------------------------------------------------------------------------------------
-- Lots: what stands on one quarter of a tile
-----------------------------------------------------------------------------------------------------------

local HOUSE_BODY = { "white", "sand", "brick", "concrete", "white" }
local HOUSE_ROOF = { "roofRed", "roofBlue", "roof", "roofRed" }

type LotFn = (list: { Box }, rng: Rng.Rng, x0: number, z0: number, x1: number, z1: number, gy: number) -> ()

local LOTS: { [string]: LotFn } = {}

local function centre(x0: number, z0: number, x1: number, z1: number): (number, number, number, number)
	return (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
end

LOTS.house = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	local sx = math.min(w - 8, rng:range(18, 26))
	local sz = math.min(d - 8, rng:range(16, 22))
	local h = rng:range(10, 14)
	BoxKit.house(
		list,
		cx,
		gy,
		cz,
		sx,
		sz,
		h,
		HOUSE_BODY[rng:int(1, #HOUSE_BODY)],
		HOUSE_ROOF[rng:int(1, #HOUSE_ROOF)]
	)
	if rng:chance(0.5) then
		BoxKit.tree(list, x0 + 4, gy, z1 - 4, rng:range(8, 12))
	end
end

LOTS.bighouse = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	local sx = math.max(18, math.min(w - 6, rng:range(28, 36)))
	local sz = math.max(16, math.min(d - 8, rng:range(22, 28)))
	local h = rng:range(18, 22)
	BoxKit.house(
		list,
		cx,
		gy,
		cz,
		sx,
		sz,
		h,
		HOUSE_BODY[rng:int(1, #HOUSE_BODY)],
		HOUSE_ROOF[rng:int(1, #HOUSE_ROOF)]
	)
	BoxKit.fence(list, x0 + 1, z1 - 1, x1 - 1, z1 - 1, gy)
end

LOTS.shop = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	local sx, sz = math.min(w - 4, rng:range(26, 34)), math.min(d - 6, rng:range(20, 26))
	local h = rng:range(12, 16)
	local color = HOUSE_BODY[rng:int(1, #HOUSE_BODY)]
	box(list, "building", cx, gy + h / 2, cz, sx, h, sz, color)
	box(list, "prop", cx, gy + 9, cz + sz / 2 + 2, sx * 0.9, 0.6, 4, HOUSE_ROOF[rng:int(1, #HOUSE_ROOF)]).look =
		"ShopAwning"
	box(list, "band", cx, gy + 4, cz + sz / 2 + 0.2, sx * 0.8, 5, 0.4, "window")
end

LOTS.park = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	for _ = 1, rng:int(2, 3) do
		BoxKit.tree(list, rng:range(x0 + 6, x1 - 6), gy, rng:range(z0 + 6, z1 - 6), rng:range(9, 14))
	end
	box(list, "prop", cx, gy + 1, cz, math.min(w - 10, 8), 2, 2, "wood").look = "ParkBench"
	local _ = d
end

LOTS.pool = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	box(list, "water", cx, gy + 0.3, cz, w * 0.55, 0.6, d * 0.45, "water").look = "PoolEdge"
	-- (shapes-2, nate: "pools need to look better as well"): a ladder over the near edge, two loungers past the far one
	local pw, pd = w * 0.55, d * 0.45
	box(list, "prop", cx + pw * 0.25, gy, cz - pd / 2 + 0.4, 2, 4, 1, "white", { ghost = true }).look =
		"PoolLadder"
	for _, k in { -1, 1 } do
		box(list, "prop", cx + k * 3.2, gy + 0.7, cz + pd / 2 + 4.6, 2.4, 1.4, 6, "awBlue").look = "Lounger"
	end
	BoxKit.fence(list, x0 + 1, z0 + 1, x1 - 1, z0 + 1, gy)
	BoxKit.fence(list, x0 + 1, z0 + 1, x0 + 1, z1 - 1, gy)
	BoxKit.tree(list, x1 - 5, gy, z1 - 5, rng:range(8, 12))
end

LOTS.yard = function(list, rng, x0, z0, x1, z1, gy)
	BoxKit.fence(list, x0 + 1, z1 - 1, x1 - 1, z1 - 1, gy)
	BoxKit.fence(list, x1 - 1, z0 + 1, x1 - 1, z1 - 1, gy)
	BoxKit.tree(list, rng:range(x0 + 8, x1 - 8), gy, rng:range(z0 + 8, z1 - 8), rng:range(9, 13))
end

local function field(
	list: { Box },
	rng: Rng.Rng,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	gy: number,
	crop: string
)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	-- the living world (2026-11-19): tilled soil, lettuce rows on the brown fields and corn on the green ones
	box(list, "field", cx, gy + 0.2, cz, w, 0.4, d, "soil").kit = "Tilled"
	local row = if crop == "cropGreen" then "CornRow" else "CropRow"
	local alongX = rng:chance(0.5)
	for k = 1, 3 do
		local f = (k - 0.5) / 3
		if alongX then
			box(list, "crop", cx, gy + 1.2, z0 + d * f, w - 4, 2, d / 3 - 4, crop, { ghost = true }).look =
				row
		else
			box(list, "crop", x0 + w * f, gy + 1.2, cz, w / 3 - 4, 2, d - 4, crop, { ghost = true }).look =
				row
		end
	end
end

LOTS.field = function(list, rng, x0, z0, x1, z1, gy)
	field(list, rng, x0, z0, x1, z1, gy, "crop")
end

LOTS.fieldGreen = function(list, rng, x0, z0, x1, z1, gy)
	field(list, rng, x0, z0, x1, z1, gy, "cropGreen")
end

LOTS.barn = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	BoxKit.house(
		list,
		cx,
		gy,
		cz,
		math.min(w - 6, rng:range(24, 32)),
		math.min(d - 6, rng:range(18, 24)),
		rng:range(14, 18),
		"roofRed",
		"roof"
	)
end

LOTS.silo = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz = centre(x0, z0, x1, z1)
	for k = -1, 1, 2 do
		local h = rng:range(26, 36)
		local x = cx + k * 7
		box(list, "prop", x, gy + h / 2, cz, 11, h, 11, "steel", { shape = "cylinder" }).look = "SiloBody"
		box(list, "prop", x, gy + h, cz, 11, 8, 11, "white", { shape = "ball" }).look = "SiloDome"
	end
end

LOTS.orchard = function(list, rng, x0, z0, x1, z1, gy)
	local _, _, w, d = centre(x0, z0, x1, z1)
	for i = 1, 2 do
		for j = 1, 2 do
			BoxKit.tree(list, x0 + w * (i - 0.5) / 2, gy, z0 + d * (j - 0.5) / 2, rng:range(8, 11))
		end
	end
end

LOTS.pasture = function(list, rng, x0, z0, x1, z1, gy)
	BoxKit.fence(list, x0 + 1, z0 + 1, x1 - 1, z0 + 1, gy)
	BoxKit.fence(list, x0 + 1, z1 - 1, x1 - 1, z1 - 1, gy)
	BoxKit.fence(list, x0 + 1, z0 + 1, x0 + 1, z1 - 1, gy)
	BoxKit.fence(list, x1 - 1, z0 + 1, x1 - 1, z1 - 1, gy)
	for _ = 1, 2 do
		box(
			list,
			"prop",
			rng:range(x0 + 8, x1 - 8),
			gy + 2.5,
			rng:range(z0 + 8, z1 - 8),
			5,
			5,
			5,
			"hay",
			{ shape = "cylinder" }
		).look =
			"HayBale"
	end
end

LOTS.pond = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	local r = math.min(w, d) * 0.7
	box(list, "water", cx, gy + 0.3, cz, r, 0.6, r, "water", { shape = "cylinder" }).look = "PondRim"
	box(list, "prop", cx + r / 2, gy + 1.5, cz - r / 3, 5, 4, 5, "rock", { shape = "ball" }).look = "Rock"
	box(list, "prop", cx - r / 2, gy + 1.2, cz + r / 4, 4, 3, 4, "rock", { shape = "ball" }).look = "Rock"
	local _ = rng
end

LOTS.tractor = function(list, rng, x0, z0, x1, z1, gy)
	field(list, rng, x0, z0, x1, z1, gy, "crop")
	local cx, cz = centre(x0, z0, x1, z1)
	box(list, "prop", cx, gy + 3, cz, 6, 4, 9, "roofRed").look = "Tractor"
	box(list, "prop", cx, gy + 6.5, cz + 1.5, 5, 3, 4, "glass").look = "TractorCab"
end

LOTS.windmillSmall = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz = centre(x0, z0, x1, z1)
	local h = rng:range(24, 30)
	box(list, "prop", cx, gy + h / 2, cz, 3, h, 3, "steel", { shape = "cylinder" }).look = "WindTower"
	box(list, "prop", cx, gy + h, cz - 2, 1, 22, 1, "white", { ghost = true }).look = "WindBladeV"
	box(list, "prop", cx, gy + h, cz - 2, 22, 1, 1, "white", { ghost = true }).look = "WindBladeH"
end

-- hub filler lots (taller, on a sidewalk pad)
LOTS.apt = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	local sx, sz = w - rng:range(4, 8), d - rng:range(4, 8)
	local h = math.floor(rng:range(28, 40) / 2) * 2
	box(list, "building", cx, gy + h / 2, cz, sx, h, sz, HOUSE_BODY[rng:int(1, #HOUSE_BODY)])
	box(list, "band", cx, gy + h * 0.4, cz, sx + 0.4, 3, sz + 0.4, "window")
	box(list, "band", cx, gy + h * 0.75, cz, sx + 0.4, 3, sz + 0.4, "window")
	box(list, "ledge", cx, gy + h + 1, cz, sx + 1, 2, sz + 1, "roof")
end

LOTS.parking = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	box(list, "road", cx, gy + 0.15, cz, w - 2, 0.3, d - 2, "road").kit = "Asphalt"
	local colors = { "containerA", "containerB", "containerC", "white" }
	for k = 1, 3 do
		box(list, "prop", x0 + w * (k - 0.5) / 3, gy + 2.3, cz, 5, 4, 9, colors[rng:int(1, #colors)]).look =
			"LotCar"
	end
end

LOTS.court = function(list, rng, x0, z0, x1, z1, gy)
	local cx, cz, w, d = centre(x0, z0, x1, z1)
	box(
		list,
		"field",
		cx,
		gy + 0.2,
		cz,
		w - 4,
		0.4,
		d - 4,
		if rng:chance(0.5) then "roofBlue" else "containerD"
	)
	-- (the hoops face the court: a look faces -z, so the near end's turns round)
	box(list, "prop", cx, gy + 5, z0 + 4, 1, 10, 1, "white", { ry = 180 }).look = "HoopPost"
	box(list, "prop", cx, gy + 5, z1 - 4, 1, 10, 1, "white").look = "HoopPost"
end

-- Each variant names its 4 lots in clockwise order from the north-west; rotation shifts that order
local VARIANTS = {
	suburbs = {
		{ "house", "house", "house", "house" },
		{ "house", "bighouse", "house", "yard" },
		{ "shop", "shop", "house", "park" },
		{ "park", "park", "park", "park" },
		{ "bighouse", "pool", "house", "house" },
		{ "house", "yard", "house", "yard" },
		{ "shop", "house", "shop", "house" },
		{ "bighouse", "bighouse", "park", "house" },
		{ "house", "pool", "yard", "bighouse" },
		{ "shop", "shop", "shop", "park" },
		{ "house", "house", "park", "pool" },
		{ "bighouse", "house", "yard", "shop" },
	},
	farmland = {
		{ "field", "field", "field", "field" },
		{ "field", "fieldGreen", "field", "fieldGreen" },
		{ "barn", "field", "field", "silo" },
		{ "orchard", "orchard", "field", "fieldGreen" },
		{ "pasture", "pasture", "barn", "field" },
		{ "pond", "fieldGreen", "orchard", "field" },
		{ "field", "tractor", "field", "field" },
		{ "silo", "barn", "pasture", "fieldGreen" },
		{ "fieldGreen", "fieldGreen", "fieldGreen", "pond" },
		{ "windmillSmall", "field", "field", "field" },
	},
	hubFill = {
		{ "park", "park", "park", "park" },
		{ "shop", "shop", "shop", "shop" },
		{ "apt", "apt", "park", "apt" },
		{ "parking", "parking", "shop", "park" },
		{ "court", "court", "park", "shop" },
		{ "shop", "apt", "shop", "apt" },
	},
}
WorldGen.VARIANTS = VARIANTS
WorldGen.LOT_KINDS = LOTS

-- The 4 lot rectangles of a tile, clockwise from the north-west, kept clear of its roads
local function lotRects(
	w: any,
	x0: number,
	z0: number,
	size: number,
	t: Tile?,
	margin: number
): { { number } }
	local roads = w.roads
	local function spans(hasRoad: boolean, highway: boolean, base: number): { { number } }
		local mid = base + size / 2
		local gap = if hasRoad then (if highway then roads.highwayWidth else roads.localWidth) / 2 + 3 else 3
		return { { base + margin, mid - gap }, { mid + gap, base + size - margin } }
	end
	local xs = spans(t ~= nil and t.roadNS, t ~= nil and t.hwyNS, x0)
	local zs = spans(t ~= nil and t.roadEW, t ~= nil and t.hwyEW, z0)
	-- NW, NE, SE, SW
	return {
		{ xs[1][1], zs[1][1], xs[1][2], zs[1][2] },
		{ xs[2][1], zs[1][1], xs[2][2], zs[1][2] },
		{ xs[2][1], zs[2][1], xs[2][2], zs[2][2] },
		{ xs[1][1], zs[2][1], xs[1][2], zs[2][2] },
	}
end

-- A Suburbs tile's 4 lots as tilePlan lays them (lore step 11: side quest sites in the outskirts pick a lot by
-- kind): { kind, x0, z0, x1, z1 } clockwise from the north-west, or {} for any other tile. A lot under a
-- safehouse pad is listed too, but tilePlan leaves it empty.
function WorldGen.suburbLots(cityCfg: any, w: any, tiles: buffer, tx: number, tz: number): { any }
	local t = WorldGen.get(w, tiles, tx, tz)
	if t.zone ~= w.zones.suburbs or t.variant == w.special then
		return {}
	end
	local x0, z0 = WorldGen.tileOrigin(cityCfg, tx, tz)
	local rects = lotRects(w, x0, z0, cityCfg.tile, t, 3)
	local kinds = VARIANTS.suburbs[t.variant + 1]
	local out = {}
	for i = 1, 4 do
		local r = rects[i]
		table.insert(
			out,
			{ kind = kinds[(i - 1 + t.rot) % 4 + 1], x0 = r[1], z0 = r[2], x1 = r[3], z1 = r[4] }
		)
	end
	return out
end

-- The kit's dressing for one built lot (after its random draws): its building's front and tint, tiled roofs,
-- and a few props by what stands there (all placed from the building's own box, so they stay in its yard)
local FRONT_GROUP = { house = "house", bighouse = "house", shop = "shop", apt = "apt", barn = "barn" }

local function dressLot(
	kit: any,
	props: { CityKit.Prop },
	list: { Box },
	first: number,
	kind: string,
	r: { number },
	gy: number
)
	local body: Box? = nil
	for k = first, #list do
		local b = list[k]
		if b.kind == "building" and b.shape == nil and body == nil then
			body = b
		end
		CityKit.roof(kit, b)
	end
	local group = FRONT_GROUP[kind]
	if body and group then
		local front = CityKit.front(kit, body, kit.fronts[group], body.color)
		if kind == "barn" and front then
			body.tint = kit.barnTint
		end
		if kind == "apt" and front then
			for k = first, #list do
				if list[k].kind == "band" then
					list[k].plain = front
				end
			end
		end
	end
	local function put(name: string, x: number, z: number, ry: number)
		CityKit.put(props, name, x, gy, z, ry)
	end
	if body and (kind == "house" or kind == "bighouse") then
		-- a mailbox by the front path and a bush at each side (houses face +z)
		local front = body.cz + body.sz / 2
		put("Mailbox", body.cx + 3.6, front + 2.4, 180)
		put("Bush", body.cx - body.sx / 2 - 2.6, body.cz + body.sz / 4, 0)
		if CityKit.roll(kit, body.cx, body.cz, 51) < 0.6 then
			put("Bush", body.cx + body.sx / 2 + 2.6, body.cz - body.sz / 4, 0)
		end
	elseif body and kind == "shop" then
		local front = body.cz + body.sz / 2
		-- shapes-2 (2026-11-19): the window band is a real shop front (Art.Life, like Downtown's), its sign word and
		-- paint by hash
		local S = kit.play and kit.play.shop
		if S then
			for k = first, #list do
				local b = list[k]
				if b.kind == "band" and b.color == "window" then
					local tint = CityKit.pick(kit, kit.play.tints, body.cx, front, 31 + 200)
					b.art = {
						name = "ShopFront",
						x = body.cx,
						y = gy,
						z = front,
						ry = 180,
						tint = tint,
						sign = CityKit.pick(kit, S.signs, body.cx, front, S.salt),
						frame = CityKit.pick(kit, S.frame, front, body.cx, S.salt + 1),
					} :: any
				end
			end
		end
		put("Bench", body.cx - body.sx / 4, front + 1.8, 180)
		put("Bin", body.cx + body.sx / 2 - 1.6, front + 1.8, 180)
	elseif kind == "park" then
		put("Bush", r[1] + 3.2, r[2] + 3.2, 0)
		put("Bush", r[3] - 3.2, r[4] - 3.2, 0)
	end
end

local function lots(
	list: { Box },
	rng: Rng.Rng,
	rects: { { number } },
	kinds: { string },
	rot: number,
	gy: number,
	clear: { BoxKit.Circle },
	kit: any?,
	props: { CityKit.Prop }?
)
	for i = 1, 4 do
		local r = rects[i]
		local kind = kinds[(i - 1 + rot) % 4 + 1]
		local sub = Rng.new(rng:nextInt32())
		local cx, cz = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
		if not BoxKit.hitsAny(clear, cx, cz, r[3] - r[1], r[4] - r[2]) then
			local first = #list + 1
			LOTS[kind](list, sub, r[1], r[2], r[3], r[4], gy)
			if kit and props then
				dressLot(kit, props, list, first, kind, r, gy)
			end
		end
	end
end

-- Power poles beside a tile's country roads (one a tile on each road, off the tarmac, clear of the crossing)
local function poles(
	props: { CityKit.Prop },
	w: any,
	t: Tile,
	x0: number,
	z0: number,
	size: number,
	gy: number
)
	local roads = w.roads
	local mx, mz = x0 + size / 2, z0 + size / 2
	if t.roadNS then
		local half = (if t.hwyNS then roads.highwayWidth else roads.localWidth) / 2
		CityKit.put(props, "PowerPole", mx - half - 1.6, gy, z0 + size * 0.25, -90)
	end
	if t.roadEW then
		local half = (if t.hwyEW then roads.highwayWidth else roads.localWidth) / 2
		CityKit.put(props, "PowerPole", x0 + size * 0.75, gy, mz - half - 1.6, 180)
	end
end

-- The safehouse pads near a tile as keep-out squares for props
local function padRects(clear: { BoxKit.Circle }, x0: number, z0: number, size: number): { CityKit.Rect }
	local out = {}
	for _, c in clear do
		if c.x + c.r > x0 and c.x - c.r < x0 + size and c.z + c.r > z0 and c.z - c.r < z0 + size then
			table.insert(out, { x0 = c.x - c.r, z0 = c.z - c.r, x1 = c.x + c.r, z1 = c.z + c.r })
		end
	end
	return out
end

-----------------------------------------------------------------------------------------------------------
-- Coast tiles
-----------------------------------------------------------------------------------------------------------

local function outward(w: any, tx: number, tz: number): (number, number)
	local last = w.tiles - 1
	if tx <= 1 then
		return -1, 0
	elseif tx >= last - 1 then
		return 1, 0
	elseif tz <= 1 then
		return 0, -1
	end
	return 0, 1
end

-- The coast tiles' features by variant (0 to 3), so a side quest site can ask for one by name (lore step 11:
-- The Salt Dogs' pier)
WorldGen.COAST = { "beach", "pier", "lighthouse", "dunes" }

-- A pier: its deck's centre and size, its length out over the sea, the way out (ox, oz), its foot (where the
-- deck meets the sand) and the harbour hut at its far end
export type Pier = {
	x: number,
	z: number,
	sx: number,
	sz: number,
	len: number,
	ox: number,
	oz: number,
	foot: { number },
	hut: { number },
}

local PIER_LEN = 140

-- A pier tile's pier (only the map's edge tiles have one; nil elsewhere)
local function pierAt(w: any, tx: number, tz: number, x0: number, z0: number, size: number): Pier?
	if not (tx == 0 or tz == 0 or tx == w.tiles - 1 or tz == w.tiles - 1) then
		return nil
	end
	local cx, cz = x0 + size / 2, z0 + size / 2
	local ox, oz = outward(w, tx, tz)
	local len = PIER_LEN
	local px, pz = cx + ox * (size / 2 + len / 2 - 30), cz + oz * (size / 2 + len / 2 - 30)
	return {
		x = px,
		z = pz,
		sx = if ox ~= 0 then len else 12,
		sz = if oz ~= 0 then len else 12,
		len = len,
		ox = ox,
		oz = oz,
		foot = { px - ox * len / 2, pz - oz * len / 2 },
		hut = { px + ox * len * 0.4, pz + oz * len * 0.4 },
	}
end

-- The pier on tile (tx, tz) when that tile is a coast "pier" tile on the edge ring, else nil (lore step 11)
function WorldGen.pier(cityCfg: any, w: any, tiles: buffer, tx: number, tz: number): Pier?
	local t = WorldGen.get(w, tiles, tx, tz)
	if t.zone ~= w.zones.coast or WorldGen.COAST[t.variant + 1] ~= "pier" then
		return nil
	end
	local x0, z0 = WorldGen.tileOrigin(cityCfg, tx, tz)
	return pierAt(w, tx, tz, x0, z0, cityCfg.tile)
end

local function coastTile(
	list: { Box },
	w: any,
	rng: Rng.Rng,
	t: Tile,
	tx: number,
	tz: number,
	x0: number,
	z0: number,
	size: number,
	gy: number
)
	local cx, cz = x0 + size / 2, z0 + size / 2
	local ox, oz = outward(w, tx, tz)
	local edge = tx == 0 or tz == 0 or tx == w.tiles - 1 or tz == w.tiles - 1
	local sand = gy + 0.3
	if t.variant == 0 then
		-- beach: umbrellas and towels
		local cols = { "containerA", "containerB", "containerC", "white" }
		for _ = 1, 3 do
			local x, z = rng:range(x0 + 10, x0 + size - 10), rng:range(z0 + 10, z0 + size - 10)
			box(list, "prop", x, sand + 4, z, 0.6, 8, 0.6, "white", { ghost = true }).look = "UmbrellaPole"
			box(list, "prop", x, sand + 8, z, 9, 1, 9, cols[rng:int(1, #cols)], { shape = "cylinder" }).look =
				"UmbrellaTop"
		end
		for _ = 1, 2 do
			box(
				list,
				"prop",
				rng:range(x0 + 10, x0 + size - 10),
				sand + 0.1,
				rng:range(z0 + 10, z0 + size - 10),
				3,
				0.2,
				6,
				cols[rng:int(1, #cols)],
				{ ghost = true }
			).look =
				"BeachTowel"
		end
	elseif t.variant == 1 then
		-- a pier out over the water on the edge tiles, a boardwalk inland
		if edge then
			local p = pierAt(w, tx, tz, x0, z0, size) :: Pier
			local px, pz, len = p.x, p.z, p.len
			box(list, "prop", px, gy + 2, pz, p.sx, 1, p.sz, "wood").kit = "Planks"
			for k = -1, 1, 2 do
				box(list, "prop", px + ox * k * len * 0.3, gy - 2, pz + oz * k * len * 0.3, 2, 8, 2, "wood").look =
					"Piling"
			end
			box(list, "building", p.hut[1], gy + 6, p.hut[2], 10, 8, 10, "white")
		else
			box(
				list,
				"prop",
				cx,
				sand + 0.5,
				cz,
				if ox ~= 0 then 8 else size - 10,
				1,
				if oz ~= 0 then 8 else size - 10,
				"wood"
			).kit =
				"Planks"
			box(list, "building", cx + oz * 20, sand + 5, cz + ox * 20, 10, 10, 8, "containerC")
		end
	elseif t.variant == 2 then
		-- lighthouse with red bands and a lamp
		local h = 60
		local x, z = cx - ox * 15, cz - oz * 15
		box(list, "prop", x, sand + 3, z, 26, 6, 26, "rock", { shape = "cylinder" }).look = "RockBase"
		box(list, "building", x, sand + 6 + h / 2, z, 12, h, 12, "white", { shape = "cylinder" })
		box(list, "band", x, sand + 6 + h * 0.35, z, 12.6, 6, 12.6, "roofRed", { shape = "cylinder" }).look =
			"LightBand"
		box(list, "band", x, sand + 6 + h * 0.7, z, 12.6, 6, 12.6, "roofRed", { shape = "cylinder" }).look =
			"LightBand"
		box(list, "glow", x, sand + 6 + h + 3, z, 8, 6, 8, "beaconLight", { shape = "cylinder" }).look =
			"Lantern"
	else
		-- dunes and driftwood
		for _ = 1, 4 do
			local s = rng:range(10, 18)
			box(
				list,
				"prop",
				rng:range(x0 + 12, x0 + size - 12),
				sand,
				rng:range(z0 + 12, z0 + size - 12),
				s * 1.6,
				s * 0.6,
				s,
				"sand",
				{ shape = "ball" }
			).look =
				"Dune"
		end
		for _ = 1, 2 do
			box(
				list,
				"prop",
				rng:range(x0 + 10, x0 + size - 10),
				sand + 0.6,
				rng:range(z0 + 10, z0 + size - 10),
				10,
				1.2,
				1.2,
				"wood"
			).look =
				"Driftwood"
		end
	end
end

-----------------------------------------------------------------------------------------------------------
-- Tile plans
-----------------------------------------------------------------------------------------------------------

WorldGen.windmill = { height = 48, blade = 52 }

-- The boxes for one tile. Hub district tiles and the non-corner landmark tiles return nothing (the districts
-- and landmarks are built whole). clear: safehouse pads. props (optional): with Config.City.kit, the tile's
-- street props are added to it (kept clear of its buildings, pads and roads).
local function tilePlan(
	cityCfg: any,
	w: any,
	tiles: buffer,
	seed: number,
	tx: number,
	tz: number,
	clear: { BoxKit.Circle },
	props: { CityKit.Prop }?
): { Box }
	local list: { Box } = {}
	local kit = if props then cityCfg.kit else nil
	local propsFrom = if props then #props + 1 else 0
	local t = WorldGen.get(w, tiles, tx, tz)
	local Z = w.zones
	local size = cityCfg.tile
	local x0, z0 = WorldGen.tileOrigin(cityCfg, tx, tz)
	local gy = cityCfg.ground.y
	if t.zone == Z.hub or t.zone == Z.landmark then
		return list
	end
	if t.zone == Z.hubFill then
		local rng = Rng.new(Rng.hash(cityCfg.hubFill.seed, tx, tz, 3))
		local kinds = VARIANTS.hubFill[t.variant + 1]
		local street = cityCfg.hubFill.street
		local park = kinds[1] == "park" and kinds[2] == "park"
		box(list, "road", x0 + size / 2, gy + 0.1, z0 + size / 2, size, 0.2, size, "road").kit = kit
			and kit.ground.Outskirts.road
		box(
			list,
			"sidewalk",
			x0 + size / 2,
			gy + 0.45,
			z0 + size / 2,
			size - street * 2,
			0.7,
			size - street * 2,
			if park then "grass" else "sidewalk"
		)
		if kit and not park then
			list[#list].kit = kit.ground.Hub.sidewalk
		end
		lots(list, rng, lotRects(w, x0, z0, size, nil, street + 2), kinds, t.rot, gy + 0.8, clear, kit, props)
		if kit and props then
			-- lamps on the block's four corners, facing out
			for _, side in CityKit.sides(x0 + street, z0 + street, size - street * 2) do
				CityKit.onSide(props, "StreetLamp", side, -(size / 2 - street - 1), 1, gy + 0.8)
			end
			CityKit.keep(
				kit,
				props,
				propsFrom,
				CityKit.obstacles(list, gy + 0.8, padRects(clear, x0, z0, size), 50)
			)
		end
		return list
	end
	local rng = Rng.new(Rng.hash(seed, tx, tz, 3))
	if t.zone == Z.coast then
		coastTile(list, w, rng, t, tx, tz, x0, z0, size, gy)
		return list
	end
	if t.variant == w.special then
		-- a hand-placed tile: the windmill beacon on a farm, or trees around an outskirts safehouse
		local cx, cz = x0 + size / 2, z0 + size / 2
		if t.zone == Z.farmland then
			local m = WorldGen.windmill
			box(
				list,
				"building",
				cx,
				gy + m.height / 2,
				cz,
				16,
				m.height,
				16,
				"white",
				{ shape = "cylinder" }
			)
			box(list, "roof", cx, gy + m.height + 2, cz, 18, 10, 18, "roofRed", { shape = "ball" })
			box(list, "prop", cx, gy + m.height - 6, cz - 10, 2, m.blade, 1, "wood").look = "WindBladeV"
			box(list, "prop", cx, gy + m.height - 6, cz - 10, m.blade, 2, 1, "wood").look = "WindBladeH"
			local rects = lotRects(w, x0, z0, size, nil, 3)
			for i = 1, 4 do
				if i % 2 == 1 then
					local r = rects[i]
					field(list, rng, r[1], r[2], r[3], r[4], gy, "crop")
				end
			end
		else
			for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
				BoxKit.tree(list, cx + c[1] * 38, gy, cz + c[2] * 38, rng:range(9, 13))
			end
		end
		return list
	end
	local kinds = if t.zone == Z.suburbs
		then VARIANTS.suburbs[t.variant + 1]
		else VARIANTS.farmland[t.variant + 1]
	lots(list, rng, lotRects(w, x0, z0, size, t, 3), kinds, t.rot, gy, clear, kit, props)
	if kit and props then
		poles(props, w, t, x0, z0, size, gy)
		CityKit.keep(kit, props, propsFrom, CityKit.obstacles(list, gy, padRects(clear, x0, z0, size), 50))
	end
	return list
end

-----------------------------------------------------------------------------------------------------------
-- Base: ground, sand, ocean and the road strips
-----------------------------------------------------------------------------------------------------------

-- A long strip split into pieces of at most 2,048 studs (the Roblox part size limit)
local function strip(
	list: { Box },
	kind: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	y: number,
	sy: number,
	color: string,
	opts: BoxKit.Opts?
)
	local lx, lz = x1 - x0, z1 - z0
	local pieces = math.max(1, math.ceil(math.max(lx, lz) / 2000))
	for k = 1, pieces do
		if lx >= lz then
			local a = x0 + lx * (k - 1) / pieces
			local b = x0 + lx * k / pieces
			box(list, kind, (a + b) / 2, y, (z0 + z1) / 2, b - a, sy, lz, color, opts)
		else
			local a = z0 + lz * (k - 1) / pieces
			local b = z0 + lz * k / pieces
			box(list, kind, (x0 + x1) / 2, y, (a + b) / 2, lx, sy, b - a, color, opts)
		end
	end
end

-- `deep` (Config.Deep, optional): cut the harbour basin out of the ground and leave the swimmable ring and
-- the Trench (Terrain water, DeepLayout) free of sea parts. `holes` (optional): more rectangles the ground plates
-- leave open (the park's Terrain inside its wall, ParkLayout.holes)
function WorldGen.base(cityCfg: any, w: any, tiles: buffer, deep: any?, holes: { BoxKit.Rect }?): { Box }
	local list: { Box } = {}
	local half = cityCfg.mapSize / 2
	local gy = cityCfg.ground.y
	local th = cityCfg.ground.thickness
	local bs = cityCfg.docks.basin
	local basinHole: BoxKit.Rect? = if deep
		then { x0 = bs.minX, z0 = bs.minZ, x1 = bs.maxX, z1 = bs.maxZ }
		else nil
	-- ground: 3 x 3 squares of 1,600 studs (the middle one is the hub)
	local third = cityCfg.mapSize / 3
	for i = 0, 2 do
		for j = 0, 2 do
			local x0, z0 = -half + third * i, -half + third * j
			local rects = if basinHole
				then BoxKit.around(x0, z0, x0 + third, z0 + third, basinHole)
				else { { x0 = x0, z0 = z0, x1 = x0 + third, z1 = z0 + third } }
			for _, hole in holes or {} do
				local cut = {}
				for _, r in rects do
					for _, q in BoxKit.around(r.x0, r.z0, r.x1, r.z1, hole) do
						table.insert(cut, q)
					end
				end
				rects = cut
			end
			for _, r in rects do
				strip(list, "ground", r.x0, r.z0, r.x1, r.z1, gy - th / 2, th, "grass")
			end
		end
	end
	-- coast sand over the last 2 tile rings
	local c = w.coast
	local s = c.sandWidth
	strip(list, "sand", -half, -half, half, -half + s, gy + 0.15, 0.3, "sand")
	strip(list, "sand", -half, half - s, half, half, gy + 0.15, 0.3, "sand")
	strip(list, "sand", -half, -half + s, -half + s, half - s, gy + 0.15, 0.3, "sand")
	strip(list, "sand", half - s, -half + s, half, half - s, gy + 0.15, 0.3, "sand")
	-- the ocean past the edge (past the swimmable ring when there is one)
	local o = c.oceanWidth
	local wy = c.waterY - 1
	local e = half + (if deep then deep.ring.width else 0)
	local far = half + o
	local south: { BoxKit.Rect } = { { x0 = -far, z0 = e, x1 = far, z1 = far } }
	if deep then
		local t = deep.trench
		south = BoxKit.around(-far, e, far, far, { x0 = t.minX, z0 = t.minZ, x1 = t.maxX, z1 = t.maxZ })
	end
	for _, r in south do
		strip(list, "sea", r.x0, r.z0, r.x1, r.z1, wy, 2, "sea")
	end
	strip(list, "sea", -far, -far, far, -e, wy, 2, "sea")
	strip(list, "sea", -far, -e, -e, e, wy, 2, "sea")
	strip(list, "sea", e, -e, far, e, wy, 2, "sea")
	-- road strips: one per straight run of road tiles
	local n = w.tiles
	local size = cityCfg.tile
	local roads = w.roads
	local function runs(alongZ: boolean)
		for a = 0, n - 1 do
			local start: number? = nil
			local highway = false
			for b = 0, n do
				local has = false
				if b < n then
					local t = if alongZ then WorldGen.get(w, tiles, a, b) else WorldGen.get(w, tiles, b, a)
					has = if alongZ then t.roadNS else t.roadEW
					if has then
						highway = if alongZ then t.hwyNS else t.hwyEW
					end
				end
				if has and start == nil then
					start = b
				elseif not has and start ~= nil then
					local width = if highway then roads.highwayWidth else roads.localWidth
					local mid = -half + (a + 0.5) * size
					local from, to = -half + start * size, -half + b * size
					local y = gy + (if alongZ then 0.1 else 0.13)
					if alongZ then
						strip(list, "road", mid - width / 2, from, mid + width / 2, to, y, 0.2, "road")
						if highway then
							strip(
								list,
								"band",
								mid - roads.lineWidth / 2,
								from,
								mid + roads.lineWidth / 2,
								to,
								y + 0.12,
								0.05,
								"line",
								{ ghost = true }
							)
						end
					else
						strip(list, "road", from, mid - width / 2, to, mid + width / 2, y, 0.2, "road")
						if highway then
							strip(
								list,
								"band",
								from,
								mid - roads.lineWidth / 2,
								to,
								mid + roads.lineWidth / 2,
								y + 0.12,
								0.05,
								"line",
								{ ghost = true }
							)
						end
					end
					start = nil
				end
			end
		end
	end
	runs(true)
	runs(false)
	if cityCfg.kit then
		for _, b in list do
			if b.kind == "road" then
				b.kit = cityCfg.kit.ground.Outskirts.road
			end
		end
	end
	return list
end

-----------------------------------------------------------------------------------------------------------
-- Landmarks
-----------------------------------------------------------------------------------------------------------

export type Landmark = {
	id: string,
	boxes: { Box },
	spot: { x: number, y: number, z: number }, -- the beacon's place
	centre: { x: number, z: number },
	size: number,
	art: { CraterArtKit.Place }?, -- the Crater's Blender looks over its tagged boxes (gap-wrecks, CraterArtKit)
	floorY: number?, -- the Crater's floor top (its debris bits lie on it)
}

-- A local (lx, lz) offset turned by ry degrees (Roblox's turn about +y: local +x goes to (cos, -sin))
local function turned(lx: number, lz: number, ry: number): (number, number)
	local t = math.rad(ry)
	return lx * math.cos(t) + lz * math.sin(t), -lx * math.sin(t) + lz * math.cos(t)
end

-- The Crater's floor dressed as the blasted Crane Industries lab and the old battle's wreckage (nate's lore,
-- build plan step 9; Config.World.crater). fy is the floor's top. PLACEHOLDER ART: plain parts; the walls and
-- towers wear the kit's white Panel texture until Art.Crater is imported, and the burn scars and the foundation
-- (scorched) stay plain parts. Since gap-wrecks (2026-11-19) every wall, chunk, tank, tower, husk and
-- relic is also a Blender look (art/blender/crater.py, Shared.CraterArtKit): its boxes carry `art` and the looks'
-- placements come back (Landmark.art); the boxes themselves are exactly as before (same sizes, places, collisions).
local function craterRuins(list: { Box }, c: any, cx: number, fy: number, cz: number): { CraterArtKit.Place }
	local art: { CraterArtKit.Place } = {}
	local function cover(look: string, boxes: { Box }, x: number, z: number, ry: number)
		table.insert(art, CraterArtKit.cover(look, boxes, x, z, ry, 0))
	end
	-- burn scars radiating out from the blast (flat marks, under everything else)
	-- (gap-fx3, 2026-11-19) each strip names its burn scar decal (`scar`, 1.. #decals; CityBuilder draws it on top)
	local sc = c.scars
	for k = 0, sc.n - 1 do
		local a = (k + 0.5) / sc.n * 2 * math.pi + (if k % 2 == 0 then 0.06 else -0.09)
		local len = (sc.to - sc.from) * (if k % 3 == 0 then 1 else 0.8)
		local mid = sc.from + len / 2
		local strip = box(
			list,
			"mark",
			cx + math.cos(a) * mid,
			fy + 0.03,
			cz + math.sin(a) * mid,
			len,
			0.05,
			sc.width * (if k % 2 == 0 then 1 else 0.7),
			"scorch",
			{ ry = -math.deg(a) }
		)
		if sc.decals and #sc.decals > 0 then
			strip.scar = k % #sc.decals + 1
		end
	end
	-- the scorched foundation
	local f = c.foundation
	local fnd = box(list, "ledge", cx, fy + f.h / 2, cz, f.w, f.h, f.d, "scorch")
	fnd.kit, fnd.tint = "Concrete", "crater" -- the pocket kit's poured concrete, burnt dark (2026-11-19)
	local top = fy + f.h
	-- broken walls on its edges, ragged on top; the Crane C on two of them
	local th = c.wallThick
	for wi, wl in c.walls do
		local alongX = wl.along == "x"
		local wx, wz = cx + wl.x, cz + wl.z
		local sx = if alongX then wl.len else th
		local sz = if alongX then th else wl.len
		local wall = box(list, "building", wx, top + wl.h / 2, wz, sx, wl.h, sz, "labWall")
		wall.kit = "Panel"
		local mine: { Box } = { wall }
		local j = wl.jag
		local jx = if alongX then wx + j[1] else wx
		local jz = if alongX then wz else wz + j[1]
		local jsx = if alongX then j[2] else th
		local jsz = if alongX then th else j[2]
		local jag = box(list, "building", jx, top + wl.h + j[3] / 2, jz, jsx, j[3], jsz, "labWall")
		jag.kit = "Panel"
		table.insert(mine, jag)
		-- (the kit pass, 2026-11-19) a chunk of fallen wall at its foot: a ghost, so nothing stands on it and the
		-- wall's solid boxes are as before (one a wall keeps the Crater inside its part budget)
		local ox = if alongX then wl.len * 0.3 else th + 3
		local oz = if alongX then th + 3 else wl.len * 0.3
		local rb = box(list, "prop", wx + ox, top + 1, wz + oz, 4, 2, 3, "labWall", { ghost = true, ry = 25 })
		rb.kit, rb.tint = "Concrete", "labWall"
		cover("CraterChunk", { rb }, rb.cx, rb.cz, 25)
		if wl.logo then
			-- the Crane Industries C (original): a navy plate, a white C opening to the viewer's right. Seen from
			-- outside a north wall (logo 1) the viewer faces -z, so their right is +x; on a south wall it is -x.
			local L = c.logo
			local side = wl.logo
			local y = top + L.at
			local sz2, b = L.size, L.bar
			local plate = wz + side * (th / 2 + 0.15)
			table.insert(mine, box(list, "prop", wx, y, plate, sz2, sz2, 0.3, "craneNavy"))
			local fz = plate + side * 0.2
			local arm = sz2 / 2 - 1 - b / 2
			table.insert(mine, box(list, "prop", wx - side * arm, y, fz, b, sz2 - 2, 0.2, "white"))
			table.insert(mine, box(list, "prop", wx - side * 0.25, y + arm, fz, sz2 - 2.5, b, 0.2, "white"))
			table.insert(mine, box(list, "prop", wx - side * 0.25, y - arm, fz, sz2 - 2.5, b, 0.2, "white"))
		end
		-- the wall's look runs along its own x: a wall along z is turned 90 (its local x points to world -z)
		cover("CraterWall" .. wi, mine, wx, wz, if alongX then 0 else 90)
	end
	-- cracked containment tanks: the broken shell, the faint Spark glow left inside, a shard beside it
	for ti, t in c.tanks do
		local tx, tz = cx + t.x, cz + t.z
		local shell =
			box(list, "prop", tx, top + t.h / 2, tz, t.r * 2, t.h, t.r * 2, "glass", { shape = "cylinder" })
		local glow =
			box(list, "glow", tx, top + t.glow / 2, tz, t.r, t.glow, t.r, "sparkGlow", { shape = "cylinder" })
		local sh = t.shard
		local shard =
			box(list, "prop", tx + sh[1] + t.r, top + 1.5, tz + sh[2], 3, 3, 0.6, "glass", { ry = sh[3] })
		cover("CraterTank" .. ti, { shell, glow, shard }, tx, tz, 0)
	end
	-- toppled lab towers: the shaft lying on the floor, its crown broken off past the top, the mast beside it
	for twi, tw in c.towers do
		local ox, oz = cx + tw.x, cz + tw.z
		local shaft =
			box(list, "building", ox, fy + tw.h / 2, oz, tw.w, tw.h, tw.len, "labWall", { ry = tw.ry })
		shaft.kit = "Panel"
		local ex, ez = turned(0, tw.len / 2 + 9, tw.ry)
		local crown = box(
			list,
			"building",
			ox + ex,
			fy + 2.5,
			oz + ez,
			tw.w + 4,
			5,
			12,
			"craneNavy",
			{ ry = tw.ry + 12 }
		)
		crown.kit, crown.tint = "SteelPlate", "craneNavy"
		local mx, mz = turned(tw.w / 2 + 3, 6, tw.ry)
		local mast = box(list, "prop", ox + mx, fy + 0.6, oz + mz, 1.2, 1.2, 28, "steel", { ry = tw.ry - 6 })
		cover("CraterTower" .. twi, { shaft, crown, mast }, ox, oz, tw.ry)
	end
	-- robot husks from the battle: a torso on its back, its head rolled off
	for _, h in c.husks do
		local a = math.rad(h.a)
		local hx, hz = cx + math.cos(a) * h.d, cz + math.sin(a) * h.d
		local torso = box(list, "prop", hx, fy + 1.5, hz, 4.5, 3, 6.5, "husk", { ry = h.ry })
		torso.kit, torso.tint = "SteelPlate", "husk"
		local dx, dz = turned(3.5, 5.5, h.ry)
		local head = box(list, "prop", hx + dx, fy + 1.4, hz + dz, 2.8, 2.8, 2.8, "rust", { ry = h.ry + 35 })
		head.kit, head.tint = "SteelPlate", "rust"
		cover("CraterHusk", { torso, head }, hx, hz, h.ry)
	end
	-- the old heroes' relics where they made their stand (original designs)
	local rl = c.relics
	local cp = rl.cape
	local px, pz = cx + cp.x, cz + cp.z
	cover("CraterCape", {
		box(list, "prop", px, fy + cp.rebar / 2, pz, 0.8, cp.rebar, 0.8, "steel", { shape = "cylinder" }),
		box(list, "prop", px + 0.5, fy + cp.rebar - 3.6, pz, 0.3, 6.5, 4.5, "relicRed"),
		box(list, "prop", px + 0.5, fy + cp.rebar - 8, pz - 1.2, 0.3, 2.6, 1.6, "relicRed", { ry = 12 }),
	}, px, pz, 0)
	local sd = rl.shield
	local shx, shz = cx + sd.x, cz + sd.z
	cover("CraterShield", {
		box(list, "prop", shx, fy + 0.4, shz, sd.w, 0.8, sd.d, "relicBlue", { ry = sd.ry }),
		box(list, "prop", shx, fy + 0.85, shz, sd.w * 0.5, 0.2, sd.d * 0.4, "relicGold", { ry = sd.ry }),
		box(list, "mark", shx, fy + 0.97, shz, 0.4, 0.05, sd.d * 1.05, "scorch", { ry = sd.ry + 28 }),
	}, shx, shz, sd.ry)
	local hm = rl.helmet
	local hx, hz = cx + hm.x, cz + hm.z
	cover("CraterHelmet", {
		box(
			list,
			"prop",
			hx,
			fy + hm.size * 0.3,
			hz,
			hm.size,
			hm.size,
			hm.size,
			"relicGold",
			{ shape = "ball" }
		),
		box(list, "prop", hx, fy + hm.size * 0.45, hz - hm.size / 2 + 0.2, hm.size * 0.7, 1, 0.6, "scorch"),
	}, hx, hz, 0)
	return art
end

function WorldGen.landmark(cityCfg: any, w: any, index: number): Landmark
	local lm = w.landmarks[index]
	local x0, z0 = WorldGen.tileOrigin(cityCfg, lm.tx, lm.tz)
	local size = lm.size * cityCfg.tile
	local cx, cz = x0 + size / 2, z0 + size / 2
	local gy = cityCfg.ground.y
	local list: { Box } = {}
	local spot = { x = cx, y = gy, z = cz }
	local art: { CraterArtKit.Place }? = nil
	local floorY: number? = nil
	if lm.id == "CometCrater" then
		local c = w.crater
		local r = size / 2 - c.rimWidth
		-- the floor and the rim wear the Crater's own ground (`ground`, Config.World.crater.ground; gap-fx3) once its
		-- MaterialVariant is in, else their kit
		local floorBox =
			box(list, "field", cx, gy + 0.3, cz, r * 2, 0.6, r * 2, "crater", { shape = "cylinder" })
		floorBox.kit = "CaveRock"
		floorBox.ground = c.ground and c.ground.floor
		local segs = 16
		local seg = 2 * math.pi * r / segs + 4
		for k = 0, segs - 1 do
			local a = k / segs * 2 * math.pi
			local rim = box(
				list,
				"rock",
				cx + math.cos(a) * r,
				gy + c.rimHeight / 2,
				cz + math.sin(a) * r,
				c.rimWidth,
				c.rimHeight,
				seg,
				"rock",
				{ ry = -math.deg(a) }
			)
			rim.kit = "CaveRock"
			rim.ground = c.ground and c.ground.rim
		end
		art = craterRuins(list, c, cx, gy + 0.6, cz)
		floorY = gy + 0.6
		spot = { x = cx, y = gy + c.rimHeight + 0.5, z = cz - r }
	elseif lm.id == "RadioHill" then
		local h = w.radioHill
		local top = gy
		for k = 1, h.steps do
			local s = size - (k - 1) * (size / (h.steps + 1))
			box(
				list,
				"rock",
				cx,
				top + h.stepHeight / 2,
				cz,
				s,
				h.stepHeight,
				s,
				if k % 2 == 0 then "grass" else "rock"
			)
			-- shapes-2: the rock steps in the cave rock texture, the grass steps in Roblox grass
			if k % 2 == 0 then
				list[#list].mat = "Grass"
			else
				list[#list].kit = "CaveRock"
			end
			top += h.stepHeight
		end
		box(list, "prop", cx, top + h.mastHeight / 2, cz, 3, h.mastHeight, 3, "steel", { shape = "cylinder" }).look =
			"RadioMast"
		box(list, "glow", cx, top + h.mastHeight + 1, cz, 4, 2, 4, "foundryGlow")
		-- the glide course: square hoops floating down the west side (M6 times it)
		for k = 1, h.rings do
			local x = cx - 30 - k * 28
			local y = top + 40 - k * 14
			local hs = 12
			box(
				list,
				"glow",
				x,
				y + hs,
				cz,
				1,
				1,
				hs * 2,
				"beaconGlow",
				{ ghost = true, tag = "glideRing", ref = k }
			)
			box(list, "glow", x, y - hs, cz, 1, 1, hs * 2, "beaconGlow", { ghost = true })
			box(list, "glow", x, y, cz - hs, 1, hs * 2, 1, "beaconGlow", { ghost = true })
			box(list, "glow", x, y, cz + hs, 1, hs * 2, 1, "beaconGlow", { ghost = true })
		end
		spot = { x = cx + 14, y = top + 0.5, z = cz }
	else
		local q = w.quarry
		local t = 30
		box(list, "field", cx, gy + 0.3, cz, size - 2 * t, 0.6, size - 2 * t, "rock").kit = "CaveRock"
		-- walls on 3 sides and a north wall with a gate in the middle
		box(list, "rock", cx, gy + q.wallHeight / 2, z0 + size - t / 2, size, q.wallHeight, t, "rock")
		box(list, "rock", x0 + t / 2, gy + q.wallHeight / 2, cz, t, q.wallHeight, size - 2 * t, "rock")
		box(list, "rock", x0 + size - t / 2, gy + q.wallHeight / 2, cz, t, q.wallHeight, size - 2 * t, "rock")
		local gate = 80
		local side = (size - gate) / 2
		box(list, "rock", x0 + side / 2, gy + q.wallHeight / 2, z0 + t / 2, side, q.wallHeight, t, "rock")
		box(
			list,
			"rock",
			x0 + size - side / 2,
			gy + q.wallHeight / 2,
			z0 + t / 2,
			side,
			q.wallHeight,
			t,
			"rock"
		)
		-- terraces stepping down inside the south, west and east walls
		for k = 1, q.terraces do
			local hgt = q.wallHeight * (1 - k / (q.terraces + 1))
			local inset = t + (k - 0.5) * q.terraceWidth
			local len = size - 2 * inset
			box(list, "rock", cx, gy + hgt / 2, z0 + size - inset, len, hgt, q.terraceWidth, "sand")
			box(
				list,
				"rock",
				x0 + inset,
				gy + hgt / 2,
				cz + q.terraceWidth / 2,
				q.terraceWidth,
				hgt,
				len - q.terraceWidth,
				"sand"
			)
			box(
				list,
				"rock",
				x0 + size - inset,
				gy + hgt / 2,
				cz + q.terraceWidth / 2,
				q.terraceWidth,
				hgt,
				len - q.terraceWidth,
				"sand"
			)
		end
		for k = 1, 5 do
			local a = k * 1.3
			box(
				list,
				"rock",
				cx + math.cos(a) * 60,
				gy + 5,
				cz + math.sin(a) * 50,
				14,
				10,
				12,
				"rock",
				{ shape = "ball" }
			).look =
				"Rock"
		end
		-- shapes-2 (2026-11-19): the quarry's walls in cave rock, its cut terraces in sandstone blocks
		for _, b in list do
			if b.kind == "rock" and b.shape == nil then
				b.kit = if b.color == "sand" then "Ashlar" else "CaveRock"
			end
		end
		spot = { x = cx, y = gy + q.wallHeight + 0.5, z = z0 + size - t / 2 }
	end
	return {
		id = lm.id,
		boxes = list,
		spot = spot,
		centre = { x = cx, z = cz },
		size = size,
		art = art,
		floorY = floorY,
	}
end

-- One tile's boxes; with the kit, every building body the tile's layout left plain gets a kit texture
-- (pt-ui 2026-11-19, Shared.CityKit.fill: pier huts, coast shacks, lighthouses, the windmill)
function WorldGen.tilePlan(
	cityCfg: any,
	w: any,
	tiles: buffer,
	seed: number,
	tx: number,
	tz: number,
	clear: { BoxKit.Circle },
	props: { CityKit.Prop }?
): { Box }
	local list = tilePlan(cityCfg, w, tiles, seed, tx, tz, clear, props)
	if props and cityCfg.kit then
		CityKit.fill(cityCfg.kit, list)
	end
	return list
end

return WorldGen
