--!strict
-- DeepLayout: the underwater world as plain data (nate 2026-11-16: underwater at launch). Config.Deep gives the
-- areas; this turns them into:
--   * boxes    parts (CityLayout boxes): basin walls, the Sunken Line's tunnel, station and train cars, the
--              reef, shipwrecks, kelp, cargo caches and the sunken factory
--   * terrain  Terrain fills { material, centre, size }: water, the sand seabed and rock walls that keep the
--              water closed in (under the land and the far sea surface there is nothing)
--   * caches, rescues and the boss arena, as points
-- plus the questions the server and client ask: which area a spot is in, the floor under it, and whether it
-- is underwater. Pure: no Roblox instances, so Lune tests it. PLACEHOLDER ART: simple parts until the art pass.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")

local DeepLayout = {}

type Box = BoxKit.Box
export type Fill = { material: string, cx: number, cy: number, cz: number, sx: number, sy: number, sz: number }
export type Spot = { id: number, x: number, y: number, z: number, area: string }
export type Layout = {
	boxes: { Box },
	terrain: { Fill },
	caches: { Spot },
	rescues: { Spot },
	arena: { x: number, y: number, z: number, radius: number },
	factory: { x: number, y: number, z: number },
}

local box = BoxKit.box

local function waterY(Config: any): number
	return Config.World.coast.waterY
end

local function fill(
	list: { Fill },
	material: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number
)
	if x1 <= x0 or y1 <= y0 or z1 <= z0 then
		return
	end
	table.insert(list, {
		material = material,
		cx = (x0 + x1) / 2,
		cy = (y0 + y1) / 2,
		cz = (z0 + z1) / 2,
		sx = x1 - x0,
		sy = y1 - y0,
		sz = z1 - z0,
	})
end

-- The ring's floor at `d` studs out from the map edge (bands of equal width, deeper further out)
local function ringFloor(Config: any, d: number): number
	local r = Config.Deep.ring
	local k = math.clamp(math.floor(d / (r.width / r.bands)), 0, r.bands - 1)
	local depth = r.shore + (r.outer - r.shore) * k / math.max(1, r.bands - 1)
	return waterY(Config) - depth
end

local function inRect(x: number, z: number, minX: number, maxX: number, minZ: number, maxZ: number): boolean
	return x >= minX and x <= maxX and z >= minZ and z <= maxZ
end

-- Which underwater area a spot is in (by x, z; the Sunken Line also needs y below the street):
-- "basin", "line", "shelf", "trench", "sea" (the rest of the ring), or nil on land or the far sea
function DeepLayout.area(Config: any, x: number, z: number, y: number?): string?
	local D = Config.Deep
	local half = Config.City.mapSize / 2
	local b = Config.City.docks.basin
	if inRect(x, z, b.minX, b.maxX, b.minZ, b.maxZ) then
		return "basin"
	end
	local L = D.sunkenLine
	if y and y < L.floor + L.height then
		local st = L.station
		if inRect(x, z, L.toX, L.fromX, L.z - L.width / 2, L.z + L.width / 2) then
			return "line"
		end
		if inRect(x, z, st.minX, st.maxX, L.z - st.width / 2, L.z + st.width / 2) then
			return "line"
		end
	end
	local t = D.trench
	if inRect(x, z, t.minX, t.maxX, t.minZ, t.maxZ) then
		return "trench"
	end
	local d = math.max(math.abs(x), math.abs(z)) - half
	if d >= 0 and d <= D.ring.width then
		if z > half and x >= D.shelf.minX and x <= D.shelf.maxX then
			return "shelf"
		end
		return "sea"
	end
	return nil
end

-- The floor under a spot in the water, or nil when it is not over underwater play space
function DeepLayout.floorAt(Config: any, x: number, z: number, y: number?): number?
	local area = DeepLayout.area(Config, x, z, y)
	if not area then
		return nil
	end
	local D = Config.Deep
	if area == "basin" then
		return D.basin.floor
	elseif area == "line" then
		local L = D.sunkenLine
		local st = L.station
		-- the station platform along its south side
		local sz0 = L.z - st.width / 2
		if x >= st.minX and x <= st.maxX and z >= sz0 and z <= sz0 + 18 then
			return L.floor + st.platform
		end
		return L.floor
	elseif area == "trench" then
		return D.trench.floor
	end
	local half = Config.City.mapSize / 2
	return ringFloor(Config, math.max(math.abs(x), math.abs(z)) - half)
end

-- Is this spot underwater play space (in an area, below the surface, above its floor)?
function DeepLayout.underwater(Config: any, x: number, y: number, z: number): boolean
	if y >= waterY(Config) - 0.5 then
		return false
	end
	local f = DeepLayout.floorAt(Config, x, z, y)
	return f ~= nil and y >= f - 2
end

-- The zone level underwater: the hero's level raised to the area's floor (rewards follow the area)
function DeepLayout.zoneLevel(Config: any, x: number, y: number, z: number, heroLevel: number): number
	local area = DeepLayout.area(Config, x, z, y) or "sea"
	local floor = Config.Deep.zoneFloor[area] or 1
	if area == "trench" and y < Config.Deep.trench.deepBelow then
		floor = Config.Deep.zoneFloor.trenchDeep -- the Trench's depths, the hardest water in the game
	end
	return math.clamp(math.max(math.floor(heroLevel), floor), 1, Config.Stats.levelCap)
end

DeepLayout.NAMES = {
	basin = "Harbour Basin",
	line = "The Sunken Line",
	shelf = "Coral Shelf",
	trench = "The Trench",
	sea = "Open Sea",
}

---------------------------------------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------------------------------------

local function ring(Config: any, terrain: { Fill })
	local D = Config.Deep
	local r = D.ring
	local half = Config.City.mapSize / 2
	local wy = waterY(Config)
	local t = D.trench
	local bw = r.width / r.bands
	for k = 0, r.bands - 1 do
		local d0, d1 = half + k * bw, half + (k + 1) * bw
		local floor = ringFloor(Config, k * bw + 1)
		for _, mat in { "water", "sand" } do
			local y0, y1 = if mat == "water" then floor else floor - 6, if mat == "water" then wy else floor
			-- south and north strips (full width, corners included), east and west strips between them
			fill(terrain, mat, -d1, y0, d0, d1, y1, d1)
			fill(terrain, mat, -d1, y0, -d1, d1, y1, -d0)
			fill(terrain, mat, d0, y0, -d0, d1, y1, d0)
			fill(terrain, mat, -d1, y0, -d0, -d0, y1, d0)
		end
	end
	-- the shore wall: rock under the land's edge, so a diver never swims under the map
	local deepest = ringFloor(Config, r.width) - 6
	local shoreBottom = ringFloor(Config, 0) - 6
	local w = r.wall
	fill(terrain, "rock", -half, shoreBottom, half - w, half, -4, half)
	fill(terrain, "rock", -half, shoreBottom, -half, half, -4, -half + w)
	fill(terrain, "rock", half - w, shoreBottom, -half, half, -4, half)
	fill(terrain, "rock", -half, shoreBottom, -half, -half + w, -4, half)
	-- the outer wall under the far sea surface (with the trench's mouth left open in the south)
	local o = half + r.width
	fill(terrain, "rock", -o - w, deepest, o, t.minX, -3, o + w)
	fill(terrain, "rock", t.maxX, deepest, o, o + w, -3, o + w)
	fill(terrain, "rock", -o - w, deepest, -o - w, o + w, -3, -o)
	fill(terrain, "rock", o, deepest, -o, o + w, -3, o)
	fill(terrain, "rock", -o - w, deepest, -o, -o, -3, o)
end

local function trench(
	Config: any,
	terrain: { Fill },
	boxes: { Box },
	rng: any
): { x: number, y: number, z: number }
	local t = Config.Deep.trench
	local wy = waterY(Config)
	local w = t.wall
	fill(terrain, "water", t.minX, t.floor, t.minZ, t.maxX, wy, t.maxZ)
	fill(terrain, "rock", t.minX - w, t.floor - 8, t.minZ, t.maxX + w, t.floor, t.maxZ + w)
	fill(terrain, "rock", t.minX - w, t.floor, t.minZ, t.minX, -3, t.maxZ + w)
	fill(terrain, "rock", t.maxX, t.floor, t.minZ, t.maxX + w, -3, t.maxZ + w)
	fill(terrain, "rock", t.minX, t.floor, t.maxZ, t.maxX, -3, t.maxZ + w)
	-- the cliff under the ring's floor where the shelf drops into the trench
	local ringBottom = ringFloor(Config, Config.Deep.ring.width) - 6
	fill(terrain, "rock", t.minX - w, t.floor, t.minZ - w, t.maxX + w, ringBottom, t.minZ)
	-- the sunken factory: a long hall, a sloped roof, chimneys, pipes and glowing vents
	local f = t.factory
	local fy = t.floor
	box(boxes, "building", f.x, fy + f.sy / 2, f.z, f.sx, f.sy, f.sz, "nullMetal")
	box(boxes, "roof", f.x, fy + f.sy + 3, f.z, f.sx + 6, 6, f.sz + 6, "nullMetal")
	for i = 1, f.chimneys do
		local cx = f.x - f.sx / 2 + f.sx * (i - 0.5) / f.chimneys
		box(boxes, "prop", cx, fy + f.sy + 26, f.z + f.sz * 0.25, 12, 40, 12, "rust", { shape = "cylinder" })
		box(boxes, "glow", cx, fy + f.sy + 47, f.z + f.sz * 0.25, 8, 2, 8, "nullGlow")
	end
	-- the gate facing the arena, and vents along the front
	box(boxes, "glow", f.x, fy + 16, f.z - f.sz / 2 - 0.6, 40, 30, 1, "nullGlow", { tag = "factoryGate" })
	for i = -2, 2 do
		box(boxes, "glow", f.x + i * 30, fy + 2, f.z - f.sz / 2 - 14, 10, 1, 10, "nullGlow")
	end
	for _ = 1, 6 do
		local px = t.minX + 40 + rng:range(0, t.maxX - t.minX - 80)
		local pz = t.minZ + 40 + rng:range(0, 160)
		box(boxes, "prop", px, fy + 3, pz, 6, 60, 6, "rust", { shape = "cylinder", ry = rng:range(0, 180) })
	end
	return { x = f.x, y = fy, z = f.z }
end

local function basin(Config: any, terrain: { Fill }, boxes: { Box })
	local D = Config.Deep
	local b = Config.City.docks.basin
	local wy = waterY(Config)
	local floor = D.basin.floor
	local w = D.basin.wall
	local top = Config.City.ground.y + 0.6
	fill(terrain, "water", b.minX, floor, b.minZ, b.maxX, wy, b.maxZ)
	fill(terrain, "sand", b.minX - w, floor - 6, b.minZ - w, b.maxX + w, floor, b.maxZ + w)
	local h = top - floor
	local cy = (top + floor) / 2
	-- north, south and east quay walls
	box(boxes, "ledge", (b.minX + b.maxX) / 2, cy, b.minZ - w / 2, b.maxX - b.minX + w * 2, h, w, "concrete")
	box(boxes, "ledge", (b.minX + b.maxX) / 2, cy, b.maxZ + w / 2, b.maxX - b.minX + w * 2, h, w, "concrete")
	box(boxes, "ledge", b.maxX + w / 2, cy, (b.minZ + b.maxZ) / 2, w, h, b.maxZ - b.minZ, "concrete")
	-- the west wall, with the Sunken Line's tunnel mouth in it
	local L = D.sunkenLine
	local gz0, gz1 = L.z - L.width / 2, L.z + L.width / 2
	local gTop = L.floor + L.height
	local wx = b.minX - w / 2
	box(boxes, "ledge", wx, cy, (b.minZ + gz0) / 2, w, h, gz0 - b.minZ, "concrete")
	box(boxes, "ledge", wx, cy, (gz1 + b.maxZ) / 2, w, h, b.maxZ - gz1, "concrete")
	box(boxes, "ledge", wx, (top + gTop) / 2, L.z, w, top - gTop, L.width, "concrete")
	-- a warning sign over the mouth
	box(boxes, "glow", wx + w / 2 + 0.3, gTop + 3, L.z, 0.4, 3, 14, "line")
end

local function sunkenLine(Config: any, terrain: { Fill }, boxes: { Box }, rescues: { Spot })
	local L = Config.Deep.sunkenLine
	local st = L.station
	local floor, ceil = L.floor, L.floor + L.height
	local w = L.wall
	local z0, z1 = L.z - L.width / 2, L.z + L.width / 2
	-- the tunnel from the station to the basin
	fill(terrain, "water", st.maxX, floor, z0, L.fromX, ceil, z1)
	local len = L.fromX - st.maxX
	local mx = (L.fromX + st.maxX) / 2
	box(boxes, "sidewalk", mx, floor - w / 2, L.z, len, w, L.width + w * 2, "tunnel")
	box(boxes, "sidewalk", mx, ceil + w / 2, L.z, len, w, L.width + w * 2, "tunnel")
	box(boxes, "sidewalk", mx, (floor + ceil) / 2, z0 - w / 2, len, L.height, w, "tunnel")
	box(boxes, "sidewalk", mx, (floor + ceil) / 2, z1 + w / 2, len, L.height, w, "tunnel")
	-- the rails and a line of lamps (dark now)
	for _, dz in { -3, 3 } do
		box(boxes, "prop", mx, floor + 0.3, L.z + dz, len, 0.6, 0.6, "steel")
	end
	-- the station: wider, with a platform along its south side and a row of pillars
	local sz0, sz1 = L.z - st.width / 2, L.z + st.width / 2
	local slen = st.maxX - st.minX
	local smx = (st.minX + st.maxX) / 2
	fill(terrain, "water", st.minX, floor, sz0, st.maxX, ceil, sz1)
	box(boxes, "sidewalk", smx, floor - w / 2, L.z, slen + w, w, st.width + w * 2, "tunnel")
	box(boxes, "sidewalk", smx, ceil + w / 2, L.z, slen + w, w, st.width + w * 2, "tunnel")
	box(boxes, "sidewalk", smx, (floor + ceil) / 2, sz0 - w / 2, slen + w, L.height, w, "tunnel")
	box(boxes, "sidewalk", smx, (floor + ceil) / 2, sz1 + w / 2, slen + w, L.height, w, "tunnel")
	box(boxes, "sidewalk", st.minX - w / 2, (floor + ceil) / 2, L.z, w, L.height, st.width + w * 2, "tunnel")
	-- the station's side walls step in to the tunnel's at its east end
	box(
		boxes,
		"sidewalk",
		st.maxX + w / 2,
		(floor + ceil) / 2,
		(sz0 + z0) / 2,
		w,
		L.height,
		z0 - sz0,
		"tunnel"
	)
	box(
		boxes,
		"sidewalk",
		st.maxX + w / 2,
		(floor + ceil) / 2,
		(z1 + sz1) / 2,
		w,
		L.height,
		sz1 - z1,
		"tunnel"
	)
	box(boxes, "plaza", smx, floor + st.platform / 2, sz0 + 9, slen, st.platform, 18, "concrete")
	for i = 0, 4 do
		local px = st.minX + 8 + i * (slen - 16) / 4
		box(
			boxes,
			"ledge",
			px,
			(floor + st.platform + ceil) / 2,
			sz0 + 18,
			2.5,
			L.height - st.platform,
			2.5,
			"white"
		)
	end
	box(boxes, "glow", smx, ceil - 1.5, sz0 + 0.4, 30, 2.5, 0.4, "line") -- the station's name board
	-- flooded train cars, each with a commuter in an air pocket
	local c = L.car
	for i, cx in L.cars do
		local cy = floor + 0.8 + c.height / 2
		box(boxes, "prop", cx, cy, L.z, c.length, c.height, c.width, "trainCar")
		box(boxes, "band", cx, cy + 1.5, L.z - c.width / 2 - 0.05, c.length - 4, 3, 0.3, "glass")
		box(boxes, "band", cx, cy + 1.5, L.z + c.width / 2 + 0.05, c.length - 4, 3, 0.3, "glass")
		box(boxes, "prop", cx, cy - 2.5, L.z, c.length + 0.2, 1, c.width + 0.2, "trainStripe")
		table.insert(rescues, { id = i, x = cx, y = cy + c.height / 2 + 2.5, z = L.z, area = "line" })
	end
	table.insert(rescues, {
		id = #L.cars + 1,
		x = st.minX + 20,
		y = floor + st.platform + 3,
		z = sz0 + 9,
		area = "line",
	})
end

local REEF_COLORS = { "coralA", "coralB", "coralC", "coralD" }

local function shelf(Config: any, boxes: { Box }, rng: any)
	local D = Config.Deep
	local s = D.shelf
	local half = Config.City.mapSize / 2
	local W = D.ring.width
	local t = D.trench
	-- reef clusters: coral heads, tubes and fans on the seabed
	for _ = 1, s.reefs do
		local x = rng:range(s.minX + 30, s.maxX - 30)
		local z = rng:range(half + 30, half + W - 30)
		local f = ringFloor(Config, z - half)
		for _ = 1, rng:int(3, 5) do
			local ox, oz = rng:range(-10, 10), rng:range(-10, 10)
			local col = REEF_COLORS[rng:int(1, #REEF_COLORS)]
			local kind = rng:int(1, 3)
			if kind == 1 then
				local r = rng:range(3, 7)
				box(boxes, "prop", x + ox, f + r * 0.4, z + oz, r, r, r, col, { shape = "ball" })
			elseif kind == 2 then
				local h = rng:range(4, 10)
				box(boxes, "prop", x + ox, f + h / 2, z + oz, 1.6, h, 1.6, col, { shape = "cylinder" })
			else
				local h = rng:range(4, 8)
				box(boxes, "prop", x + ox, f + h / 2, z + oz, h, h, 0.4, col, { ry = rng:range(0, 180) })
			end
		end
		-- kelp stands taller
		for _ = 1, rng:int(1, 3) do
			local h = rng:range(8, math.max(9, -f - 4))
			box(boxes, "crop", x + rng:range(-14, 14), f + h / 2, z + rng:range(-14, 14), 0.8, h, 0.8, "kelp")
		end
	end
	-- shipwrecks: a hull on its side, a bow, a cabin and a broken mast
	for _ = 1, s.wrecks do
		local x, z
		repeat
			x = rng:range(s.minX + 120, s.maxX - 120)
			z = rng:range(half + 200, half + W - 80)
		until x < t.minX - 80 or x > t.maxX + 80
		local f = ringFloor(Config, z - half)
		local ry = rng:range(0, 180)
		local a = math.rad(ry)
		local fx, fz = math.sin(a), math.cos(a)
		box(boxes, "rock", x, f + 6, z, 14, 12, 60, "wreck", { ry = ry })
		box(boxes, "rock", x + fx * 38, f + 6, z + fz * 38, 14, 12, 16, "wreck", { shape = "wedge", ry = ry })
		box(boxes, "prop", x - fx * 14, f + 15, z - fz * 14, 10, 7, 12, "rust", { ry = ry })
		box(boxes, "prop", x + fx * 4 + 14, f + 3, z + fz * 4, 2, 2, 36, "wood", { ry = ry + 70 })
	end
end

local function caches(Config: any, rng: any, out: { Spot }, factory: { x: number, y: number, z: number })
	local D = Config.Deep
	local c = D.caches
	local half = Config.City.mapSize / 2
	local s = D.shelf
	local nTrench = 3
	for i = 1, c.count - nTrench do
		local x = rng:range(s.minX + 40, s.maxX - 40)
		local z = rng:range(half + 60, half + D.ring.width - 40)
		table.insert(out, { id = i, x = x, y = ringFloor(Config, z - half) + 2, z = z, area = "shelf" })
	end
	-- the factory hall is solid: a cache the ring puts inside it moves out past its nearest wall (one of the
	-- three sat inside the hall, out of reach, until the travel audit of 2026-11-18)
	local f = D.trench.factory
	local margin = c.reach
	for k = 1, nTrench do
		local a = (k - 1) / nTrench * math.pi * 2
		local x = factory.x + math.cos(a) * 140
		local z = factory.z - 30 + math.sin(a) * 60
		local ox, oz = x - factory.x, z - factory.z
		local hx, hz = f.sx / 2 + margin, f.sz / 2 + margin
		if math.abs(ox) < hx and math.abs(oz) < hz then
			if hx - math.abs(ox) <= hz - math.abs(oz) then
				x = factory.x + (if ox < 0 then -hx else hx)
			else
				z = factory.z + (if oz < 0 then -hz else hz)
			end
		end
		table.insert(out, {
			id = c.count - nTrench + k,
			x = x,
			y = D.trench.floor + 2,
			z = z,
			area = "trench",
		})
	end
end

-- A Terrain fill split into pieces no longer than `max` studs on any side (big FillBlock calls stall a frame)
function DeepLayout.chunks(f: Fill, max: number): { Fill }
	local out: { Fill } = {}
	local nx, ny, nz = math.ceil(f.sx / max), math.ceil(f.sy / max), math.ceil(f.sz / max)
	local x0, y0, z0 = f.cx - f.sx / 2, f.cy - f.sy / 2, f.cz - f.sz / 2
	local dx, dy, dz = f.sx / nx, f.sy / ny, f.sz / nz
	for i = 0, nx - 1 do
		for j = 0, ny - 1 do
			for k = 0, nz - 1 do
				table.insert(out, {
					material = f.material,
					cx = x0 + dx * (i + 0.5),
					cy = y0 + dy * (j + 0.5),
					cz = z0 + dz * (k + 0.5),
					sx = dx,
					sy = dy,
					sz = dz,
				})
			end
		end
	end
	return out
end

function DeepLayout.build(Config: any): Layout
	local D = Config.Deep
	local rng = Rng.new(D.shelf.seed)
	local boxes: { Box } = {}
	local terrain: { Fill } = {}
	local rescues: { Spot } = {}
	local cacheSpots: { Spot } = {}
	ring(Config, terrain)
	local factory = trench(Config, terrain, boxes, rng)
	basin(Config, terrain, boxes)
	sunkenLine(Config, terrain, boxes, rescues)
	shelf(Config, boxes, rng)
	caches(Config, Rng.new(D.caches.seed), cacheSpots, factory)
	for _, c in cacheSpots do
		box(boxes, "prop", c.x, c.y, c.z, 6, 4, 6, "cargo", { tag = "cache", ref = c.id })
	end
	local a = D.trench.arena
	return {
		boxes = boxes,
		terrain = terrain,
		caches = cacheSpots,
		rescues = rescues,
		arena = { x = a.x, y = waterY(Config), z = a.z, radius = a.radius },
		factory = factory,
	}
end

return DeepLayout
