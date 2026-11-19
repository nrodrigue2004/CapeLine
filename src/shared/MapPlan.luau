--!strict
-- MapPlan: the city map screen's drawing plan as plain data (the map pass, 2026-11-19; Tasks.md "Placeholder art
-- and animation": the map was flat coloured squares with no tile detail). MapScreen draws it once when the map
-- first opens (static layers, never rebuilt per frame):
-- * the projection: world x/z to 0..1 on the map, which shows the whole map plus a strip of sea round it, and
--   the zoom and pan view (the canvas scaled by `zoom`, its centre kept so the map always fills the frame);
-- * the outskirts zones for this week's seed (suburbs, farmland, coast, landmark tiles) merged into as few
--   rectangles as possible (a few dozen frames, not 2,000 tiles), each drawn with its zone's tiled pattern;
-- * the outskirts roads and highways from the same seed (WorldGen.base's road strips, one frame a straight run);
-- * where the fixed city images go (the hub and Uptown never change with the seed, so they are pictures drawn by
--   art/map/draw.py from the game's own layout, Config.MapArt) and the names on the map.
-- Pure: no Roblox instances, so Lune tests it.

local WorldGen = if script then require(script.Parent.WorldGen) else (require :: any)("./WorldGen")

local MapPlan = {}

export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Zone = Rect & { zone: string }
export type Road = Rect & { highway: boolean }
export type Label = { text: string, x: number, z: number, kind: string }

-- The map's square in world studs: the whole map and `margin` studs of sea on each side
function MapPlan.bounds(cityCfg: any, margin: number): (number, number)
	local half = cityCfg.mapSize / 2 + margin
	return -half, 2 * half
end

-- World x/z to 0..1 on the map (u east, v south)
function MapPlan.project(cityCfg: any, margin: number, x: number, z: number): (number, number)
	local min, size = MapPlan.bounds(cityCfg, margin)
	return (x - min) / size, (z - min) / size
end

-- 0..1 on the map back to world x/z
function MapPlan.unproject(cityCfg: any, margin: number, u: number, v: number): (number, number)
	local min, size = MapPlan.bounds(cityCfg, margin)
	return min + u * size, min + v * size
end

-- A world rectangle as its map position and size (u, v, du, dv)
function MapPlan.rectUV(cityCfg: any, margin: number, r: Rect): (number, number, number, number)
	local u0, v0 = MapPlan.project(cityCfg, margin, r.x0, r.z0)
	local u1, v1 = MapPlan.project(cityCfg, margin, r.x1, r.z1)
	return u0, v0, u1 - u0, v1 - v0
end

-- The zoom and pan view in a frame of any shape (w x h pixels; the phone's is wide): the map is a square
-- canvas `zoom` times the frame's shorter side, so zoom 1 shows the whole map. (cu, cv) is the map point at the
-- frame's centre, kept so the canvas covers the frame wherever it can (and centred where it is smaller).
-- Returns the clamped zoom and centre, and the canvas's Position and Size in frame scale.
export type View = {
	zoom: number,
	u: number,
	v: number,
	x: number, -- canvas Position = UDim2.fromScale(x, y)
	y: number,
	sx: number, -- canvas Size = UDim2.fromScale(sx, sy)
	sy: number,
	side: number, -- the canvas's side in pixels
}
function MapPlan.view(zoom: number, cu: number, cv: number, maxZoom: number, w: number, h: number): View
	local z = math.clamp(zoom, 1, maxZoom)
	local m = math.max(1, math.min(w, h))
	local side = z * m
	local visU, visV = w / side, h / side -- how much of the map the frame shows across and down
	local function clampAxis(c: number, vis: number): number
		if vis >= 1 then
			return 0.5
		end
		return math.clamp(c, vis / 2, 1 - vis / 2)
	end
	local u, v = clampAxis(cu, visU), clampAxis(cv, visV)
	local sx, sy = side / math.max(1, w), side / math.max(1, h)
	return { zoom = z, u = u, v = v, x = 0.5 - u * sx, y = 0.5 - v * sy, sx = sx, sy = sy, side = side }
end

-- A point on the frame (0..1 across and down it) to the map point under it, for the view above
function MapPlan.frameToMap(view: View, w: number, h: number, fx: number, fy: number): (number, number)
	return view.u + (fx - 0.5) * w / view.side, view.v + (fy - 0.5) * h / view.side
end

-- What a tile is drawn as: its zone's name, or nil where the fixed city images (the hub, Uptown) cover it
local function zoneKey(w: any, t: WorldGen.Tile): string?
	local Z = w.zones
	if t.zone == Z.hub or t.zone == Z.hubFill then
		return nil
	elseif t.zone == Z.suburbs then
		return "suburbs"
	elseif t.zone == Z.farmland then
		return "farmland"
	elseif t.zone == Z.coast then
		return "coast"
	elseif t.zone == Z.landmark then
		return "landmark"
	end
	return nil
end

-- The outskirts zones as merged rectangles: each row's runs of one zone, then runs stacked straight down
-- with the same ends and zone joined into one. Covers every outskirts tile exactly once.
function MapPlan.zones(cityCfg: any, w: any, tiles: buffer): { Zone }
	local n = w.tiles
	local size = cityCfg.tile
	local half = cityCfg.mapSize / 2
	local out: { Zone } = {}
	local open: { [string]: Zone } = {} -- "x0:x1:zone" -> the rectangle still growing down
	for tz = 0, n - 1 do
		local runs: { { a: number, b: number, key: string } } = {}
		local tx = 0
		while tx < n do
			local key = zoneKey(w, WorldGen.get(w, tiles, tx, tz))
			if key then
				local b = tx
				while b + 1 < n and zoneKey(w, WorldGen.get(w, tiles, b + 1, tz)) == key do
					b += 1
				end
				table.insert(runs, { a = tx, b = b, key = key })
				tx = b + 1
			else
				tx += 1
			end
		end
		local nextOpen: { [string]: Zone } = {}
		for _, r in runs do
			local id = r.a .. ":" .. r.b .. ":" .. r.key
			local z0 = -half + tz * size
			local rect = open[id]
			if rect then
				rect.z1 = z0 + size
			else
				rect = {
					x0 = -half + r.a * size,
					x1 = -half + (r.b + 1) * size,
					z0 = z0,
					z1 = z0 + size,
					zone = r.key,
				}
				table.insert(out, rect)
			end
			nextOpen[id] = rect
		end
		open = nextOpen
	end
	return out
end

-- The outskirts roads: one rectangle per straight run of road tiles (WorldGen.base's road strips), highways
-- wider and marked
function MapPlan.roads(cityCfg: any, w: any, tiles: buffer): { Road }
	local out: { Road } = {}
	for _, b in WorldGen.base(cityCfg, w, tiles) do
		if b.kind == "road" then
			local narrow = math.min(b.sx, b.sz)
			table.insert(out, {
				x0 = b.cx - b.sx / 2,
				x1 = b.cx + b.sx / 2,
				z0 = b.cz - b.sz / 2,
				z1 = b.cz + b.sz / 2,
				highway = narrow >= w.roads.highwayWidth - 0.01,
			})
		end
	end
	return out
end

-- The coast's sand strips along the map's edge (WorldGen.base)
function MapPlan.sand(cityCfg: any, w: any, tiles: buffer): { Rect }
	local out: { Rect } = {}
	for _, b in WorldGen.base(cityCfg, w, tiles) do
		if b.kind == "sand" then
			table.insert(
				out,
				{ x0 = b.cx - b.sx / 2, x1 = b.cx + b.sx / 2, z0 = b.cz - b.sz / 2, z1 = b.cz + b.sz / 2 }
			)
		end
	end
	return out
end

-- Where the fixed city pictures go: the hub square with the districts that spill past it (Downtown's grown
-- west column), and Uptown. Each picture's box is the bounding box of its own areas (`own`, the parts it
-- draws; the rest of the picture is clear, so the outskirts underneath show). Neither changes with the seed.
export type CityImage = Rect & { own: { Rect } }
function MapPlan.cityImages(cityCfg: any): { [string]: CityImage }
	local hub: CityImage = {
		x0 = cityCfg.hub.min,
		z0 = cityCfg.hub.min,
		x1 = cityCfg.hub.max,
		z1 = cityCfg.hub.max,
		own = { { x0 = cityCfg.hub.min, z0 = cityCfg.hub.min, x1 = cityCfg.hub.max, z1 = cityCfg.hub.max } },
	}
	for _, id in { "Downtown", "Docks", "OldTown" } do
		local d = cityCfg.districts[id]
		if d then
			table.insert(hub.own, { x0 = d.minX, z0 = d.minZ, x1 = d.maxX, z1 = d.maxZ })
			hub.x0, hub.z0 = math.min(hub.x0, d.minX), math.min(hub.z0, d.minZ)
			hub.x1, hub.z1 = math.max(hub.x1, d.maxX), math.max(hub.z1, d.maxZ)
		end
	end
	local up = cityCfg.districts.Uptown
	local upRect = { x0 = up.minX, z0 = up.minZ, x1 = up.maxX, z1 = up.maxZ }
	return {
		Hub = hub,
		Uptown = { x0 = up.minX, z0 = up.minZ, x1 = up.maxX, z1 = up.maxZ, own = { upRect } },
	}
end

-- The names on the map: the four districts at their centres, the landmarks, and the outskirts rings once each
-- (west of the hub, in the middle of each ring)
function MapPlan.labels(cityCfg: any, w: any, names: { [string]: string }): { Label }
	local out: { Label } = {}
	for id, d in cityCfg.districts do
		table.insert(out, {
			text = names[id] or string.upper(id),
			-- along the district's top edge, so the beacons and safehouses in its middle stay clear
			x = (d.minX + d.maxX) / 2,
			z = d.minZ + 0.12 * (d.maxZ - d.minZ),
			kind = "district",
		})
	end
	table.sort(out, function(a, b)
		return a.text < b.text
	end)
	for _, lm in w.landmarks do
		local x0, z0 = WorldGen.tileOrigin(cityCfg, lm.tx, lm.tz)
		local s = lm.size * cityCfg.tile
		table.insert(out, { text = string.upper(lm.name), x = x0 + s / 2, z = z0 + s, kind = "landmark" })
	end
	-- the outskirts rings once each, where nothing else is named: suburbs east of the hub, farmland further out
	-- to the south-east, the coast on the east edge
	local t = cityCfg.tile
	table.insert(out, {
		text = "SUBURBS",
		x = cityCfg.hub.max + (w.rings.suburbsTo / 2) * t,
		z = cityCfg.hub.max * 0.4,
		kind = "zone",
	})
	table.insert(out, {
		text = "FARMLAND",
		x = cityCfg.hub.max + ((w.rings.suburbsTo + w.rings.farmlandTo) / 2) * t,
		z = cityCfg.hub.max + (w.rings.suburbsTo + 2) * t,
		kind = "zone",
	})
	table.insert(out, {
		text = "COAST",
		x = cityCfg.mapSize / 2 - t,
		z = -cityCfg.hub.max * 0.5,
		kind = "zone",
	})
	return out
end

-- What the city pictures draw (art/map/layout.luau): the boxes of the fixed city seen from above, those that
-- reach into a picture (ground, roads, pavements, buildings, roofs, trees and props; not window bands, marks,
-- glows or terminals, too small for the map). `world` is WorldMap.build's; layer says where each came from.
local SEEN = {
	ground = true,
	sand = true,
	road = true,
	sidewalk = true,
	plaza = true,
	park = true,
	grass = true,
	building = true,
	tier = true,
	roof = true,
	prop = true,
	beacon = true,
	water = true,
	pier = true,
	field = true,
	tree = true,
}
function MapPlan.cityBoxes(cityCfg: any, w: any, world: any): { any }
	local regions = MapPlan.cityImages(cityCfg)
	local function inAny(b: any): boolean
		for _, r in regions do
			if
				b.cx + b.sx / 2 > r.x0
				and b.cx - b.sx / 2 < r.x1
				and b.cz + b.sz / 2 > r.z0
				and b.cz - b.sz / 2 < r.z1
			then
				return true
			end
		end
		return false
	end
	local out = {}
	local function add(list: { any }, layer: string)
		for _, b in list do
			if SEEN[b.kind] and inAny(b) then
				table.insert(out, {
					layer = layer,
					kind = b.kind,
					color = b.color,
					shape = b.shape,
					cx = b.cx,
					cz = b.cz,
					sx = b.sx,
					sz = b.sz,
					ry = b.ry or 0,
					top = b.cy + b.sy / 2,
					bottom = b.cy - b.sy / 2,
				})
			end
		end
	end
	add(world.baseBoxes, "base")
	for _, plan in world.tilePlans do
		if WorldGen.ring(w, plan.tx, plan.tz) == 0 then
			add(plan.boxes, "fill")
		end
	end
	add(world.hubBoxes, "hub")
	for _, lm in world.landmarks do
		add(lm.boxes, "landmark")
	end
	return out
end

return MapPlan
