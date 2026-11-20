--!strict
-- CityKit: the city kit's dressing helpers (overhaul plan step 5; Config.City.kit), shared by every layout
-- (CityLayout's Downtown, Districts' Docks and Old Town, WorldGen's outskirts and hub filler tiles).
-- * Fronts and tints: which tiling MaterialVariant ("Kit" .. name) a box wears, picked by a hash of its
--   position, so streets don't repeat and no layout's random draws change.
-- * Props: street props (Art.Street meshes) as plain foot points with a footprint, kept clear of buildings,
--   water, safehouse pads and each other (CityKit.keep), so nothing stands inside a wall or another prop.
-- Pure: no Roblox instances, so Lune checks it (tests "City kit").

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local CityKit = {}

-- A street prop: its foot point and facing (degrees around y; a prop faces -z, toward the street). d: the
-- district it dresses (WorldMap fills it in: Downtown, Docks, OldTown, Hub, Outskirts).
-- tint: a palette key for its tinted pieces (Config.City.kit.props pieces' 5th field; pt-city 2026-11-19)
export type Prop = { name: string, x: number, y: number, z: number, ry: number, d: string?, tint: string? }

export type Rect = { x0: number, z0: number, x1: number, z1: number }

export type Grid = { cell: number, cells: { [number]: { Rect } } }

-- A deterministic pick from a list by position (never a random draw)
function CityKit.pick<T>(kit: any, list: { T }, x: number, z: number, salt: number): T
	local h = Rng.hash(kit.seed, math.floor(x * 4), math.floor(z * 4), salt)
	return list[h % #list + 1]
end

-- A 0..1 number from a position (for "one side in three gets a cafe")
function CityKit.roll(kit: any, x: number, z: number, salt: number): number
	return (Rng.hash(kit.seed, math.floor(x * 4), math.floor(z * 4), salt) % 10007) / 10007
end

-- The tint a tinted front takes at (x, z): a palette key, or nil to keep the part's own colour
function CityKit.tint(kit: any, name: string, x: number, z: number): string?
	local list = kit.tinted[name]
	if type(list) == "table" then
		return CityKit.pick(kit, list, x, z, 2)
	end
	return nil
end

-- Dress a building body from a front list (fronts[group][colorKey]); returns the front, or nil when the
-- group has no front for that colour (the body keeps its plain look)
function CityKit.front(kit: any, b: any, group: { [string]: { string } }?, colorKey: string): string?
	local list: { string }? = if group then group[colorKey] else nil
	if list == nil or b.shape ~= nil then
		return nil
	end
	local name = CityKit.pick(kit, list :: { string }, b.cx, b.cz, 1)
	b.kit = name
	-- a body already in one of the front's tints keeps it (Uptown's sunset colours); others get one by hash
	local tints = kit.tinted[name]
	b.tint = if type(tints) == "table" and table.find(tints, b.color)
		then b.color
		else CityKit.tint(kit, name, b.cx, b.cz)
	return name
end

-- pt-ui (2026-11-19, nate's playtest: "some buildings don't have textures"): every building body and tower
-- tier the layouts left plain (safehouse shelters, pier huts, coast shacks, lighthouses, the windmill, tower
-- masts and spires) takes a kit texture from Config.City.kit.fill by its colour and shape; a tinted texture
-- gets a tint by hash. Only kit fields change (no random draws), so the layout is the same box by box.
function CityKit.fill(kit: any, list: { any })
	local F = kit.fill
	if not F then
		return
	end
	for _, b in list do
		if F.kinds[b.kind] and b.kit == nil then
			local name = F.byColor[b.color]
			if b.shape ~= nil and b.shape ~= "wedge" and name ~= "SteelPlate" then
				name = F.round
			end
			name = name or F.default
			b.kit = name
			if b.tint == nil then
				b.tint = CityKit.tint(kit, name, b.cx, b.cz)
			end
		end
	end
end

-- A pitched roof wedge gets clay tiles in a brighter version of its colour
function CityKit.roof(kit: any, b: any)
	if b.shape == "wedge" and b.kind == "roof" then
		b.kit = "RoofTile"
		b.tint = kit.roofTints[b.color]
	end
end

function CityKit.put(props: { Prop }, name: string, x: number, y: number, z: number, ry: number): Prop
	local p: Prop = { name = name, x = x, y = y, z = z, ry = ry }
	table.insert(props, p)
	return p
end

-- A prop's ground footprint as a world rectangle (Config.City.kit.props[name].foot: width, depth, and how far
-- its centre sits behind the foot point; ry is a multiple of 90)
function CityKit.footprint(kit: any, p: Prop): Rect
	local f = kit.props[p.name].foot
	local w, dp, back = f[1], f[2], f[3]
	local a = math.rad(p.ry)
	local c, s = math.cos(a), math.sin(a)
	-- local (0, back) turned by ry around y: x' = z sin, z' = z cos
	local cx, cz = p.x + back * s, p.z + back * c
	local turned = math.abs(s) > 0.5
	local hx = (if turned then dp else w) / 2
	local hz = (if turned then w else dp) / 2
	return { x0 = cx - hx, z0 = cz - hz, x1 = cx + hx, z1 = cz + hz }
end

-- Ground-level things a prop must not stand in: anything solid from the ground up to head height (buildings,
-- walls, props, trees, terminals), and water. Flat ground (roads, sidewalks, plazas, fields, marks) and
-- window bands, glows and crops are fine to stand on or under.
local FLAT = {
	road = true,
	sidewalk = true,
	plaza = true,
	ground = true,
	field = true,
	crop = true,
	mark = true,
	band = true,
	glow = true,
	sand = true,
	sea = true,
}

local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
end

local function insert(g: Grid, r: Rect)
	local c = g.cell
	for ix = math.floor(r.x0 / c), math.floor(r.x1 / c) do
		for iz = math.floor(r.z0 / c), math.floor(r.z1 / c) do
			local k = ix * 65536 + iz
			local list = g.cells[k]
			if not list then
				list = {}
				g.cells[k] = list
			end
			table.insert(list, r)
		end
	end
end

local function hits(g: Grid, r: Rect): boolean
	local c = g.cell
	for ix = math.floor(r.x0 / c), math.floor(r.x1 / c) do
		for iz = math.floor(r.z0 / c), math.floor(r.z1 / c) do
			local list = g.cells[ix * 65536 + iz]
			if list then
				for _, o in list do
					if overlaps(r, o) then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Is this box something a prop standing at ground height gy must keep out of?
function CityKit.obstacle(b: any, gy: number): boolean
	if FLAT[b.kind] and b.kind ~= "water" then
		return false
	end
	local bottom, top = b.cy - b.sy / 2, b.cy + b.sy / 2
	return bottom < gy + 7 and top > gy + 0.05
end

-- The box's world footprint (a quarter turn swaps x and z)
function CityKit.boxRect(b: any): Rect
	local sx, sz = b.sx, b.sz
	if ((b.ry or 0) % 180) == 90 then
		sx, sz = sz, sx
	end
	return { x0 = b.cx - sx / 2, z0 = b.cz - sz / 2, x1 = b.cx + sx / 2, z1 = b.cz + sz / 2 }
end

-- An obstacle grid from boxes (gy: the ground the props stand on) plus extra keep-out rectangles (lanes
-- where vehicles drive, safehouse pads). cell: the grid's cell size (big for one small tile)
function CityKit.obstacles(boxes: { any }, gy: number, extra: { Rect }?, cell: number?): Grid
	local g: Grid = { cell = cell or 16, cells = {} }
	for _, b in boxes do
		if CityKit.obstacle(b, gy) and b.sx < 400 and b.sz < 400 then
			insert(g, CityKit.boxRect(b))
		end
	end
	if extra then
		for _, r in extra do
			insert(g, r)
		end
	end
	return g
end

-- Keep only the props from index `from` on whose footprint is clear of the grid and of the props kept before
-- them (each kept prop joins the grid). Order is kept, so the result is the same every time.
function CityKit.keep(kit: any, props: { Prop }, from: number, g: Grid)
	local kept: { Prop } = {}
	for i = from, #props do
		local p = props[i]
		local r = CityKit.footprint(kit, p)
		if not hits(g, r) then
			insert(g, r)
			table.insert(kept, p)
		end
	end
	for i = #props, from, -1 do
		props[i] = nil
	end
	table.move(kept, 1, #kept, from, props)
end

-- Kerbs on the four edges of a sidewalk block (4 parts), marked as dressing
function CityKit.kerbs(boxes: { any }, minX: number, minZ: number, size: number, y: number, w: number)
	local cx, cz = minX + size / 2, minZ + size / 2
	local function kerb(x: number, z: number, sx: number, sz: number)
		table.insert(boxes, {
			kind = "sidewalk",
			cx = x,
			cy = y,
			cz = z,
			sx = sx,
			sy = 0.9,
			sz = sz,
			color = "kerb",
			kit = "Concrete", -- shapes-2: a cast kerb, not a plain strip
			dress = true,
		})
	end
	kerb(cx, minZ + w / 2, size, w)
	kerb(cx, minZ + size - w / 2, size, w)
	kerb(minX + w / 2, cz, w, size - 2 * w)
	kerb(minX + size - w / 2, cz, w, size - 2 * w)
end

-- The four sides of a square block as (edge midpoint, along axis, outward normal, facing), for props that
-- face the street: a prop at `along` on a side, `inset` in from the edge
export type Side = { x: number, z: number, ax: number, az: number, ox: number, oz: number, ry: number }

function CityKit.sides(minX: number, minZ: number, size: number): { Side }
	local cx, cz = minX + size / 2, minZ + size / 2
	return {
		{ x = cx, z = minZ, ax = 1, az = 0, ox = 0, oz = -1, ry = 0 },
		{ x = cx, z = minZ + size, ax = -1, az = 0, ox = 0, oz = 1, ry = 180 },
		{ x = minX, z = cz, ax = 0, az = -1, ox = -1, oz = 0, ry = 90 },
		{ x = minX + size, z = cz, ax = 0, az = 1, ox = 1, oz = 0, ry = -90 },
	}
end

function CityKit.onSide(
	props: { Prop },
	name: string,
	side: Side,
	along: number,
	inset: number,
	y: number
): Prop
	return CityKit.put(
		props,
		name,
		side.x + side.ax * along - side.ox * inset,
		y,
		side.z + side.az * along - side.oz * inset,
		side.ry
	)
end

-- Mesh parts a prop builds (its pieces)
function CityKit.parts(kit: any, name: string): number
	local n = 0
	for _ in kit.props[name].pieces do
		n += 1
	end
	return n
end

return CityKit
