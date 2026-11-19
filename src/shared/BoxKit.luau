--!strict
-- BoxKit: the small building blocks every city generator shares (Downtown, the Docks, Old Town, hub filler,
-- outskirts tiles, landmarks, safehouses). Everything is a plain CityLayout.Box, so the generators stay pure
-- and the Lune tests can count parts and check heights.
-- PLACEHOLDER ART: houses, trees, barns and props are a few simple parts each until the kit pass (M5).

local BoxKit = {}

-- Sizes are the part's own size before the ry turn. A wedge's high edge is at its +z side and it slopes down
-- toward -z (Roblox WedgePart); ry 90 moves the high edge to +x.
export type Box = {
	kind: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	shape: string?,
	ry: number?,
	tag: string?,
	ref: number?,
	ghost: boolean?,
	grp: string?, -- the building this part belongs to
	bid: number?, -- its destructible building id
	kit: string?, -- city kit texture (MaterialVariant "Kit" .. kit, Config.City.kit; CityKit)
	tint: string?, -- the palette colour a tinted kit texture shows in
	plain: string?, -- drawn only while this kit texture is missing (window bands on a textured front)
	dress: boolean?, -- added by the kit (kerbs, lines, cornices): not part of the seeded layout
	crown: boolean?, -- a skyscraper's top above its wreckable shaft (setbacks, spire, lantern, mast)
	art: string?, -- the Blender look drawn over it (hidden but kept once that look is imported; Deep and Crater)
	ground: string?, -- a landmark's own kit texture over `kit` once it is in (Config.City.kit.landmark; the Crater)
	scar: number?, -- the Crater's burn scar decal it wears on top (Config.World.crater.scars.decals)
}

export type Opts = { shape: string?, ry: number?, tag: string?, ref: number?, ghost: boolean? }

export type Circle = { x: number, z: number, r: number }

function BoxKit.box(
	list: { Box },
	kind: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	opts: Opts?
): Box
	local b: Box = { kind = kind, cx = cx, cy = cy, cz = cz, sx = sx, sy = sy, sz = sz, color = color }
	if opts then
		b.shape = opts.shape
		b.ry = opts.ry
		b.tag = opts.tag
		b.ref = opts.ref
		b.ghost = opts.ghost
	end
	table.insert(list, b)
	return b
end

export type Rect = { x0: number, z0: number, x1: number, z1: number }

-- A rectangle with a rectangular hole cut out of it, as up to 4 rectangles (south, north, west, east).
-- No overlap with the hole gives the rectangle back whole.
function BoxKit.around(x0: number, z0: number, x1: number, z1: number, hole: Rect): { Rect }
	local hx0, hz0 = math.max(x0, hole.x0), math.max(z0, hole.z0)
	local hx1, hz1 = math.min(x1, hole.x1), math.min(z1, hole.z1)
	if hx1 <= hx0 or hz1 <= hz0 then
		return { { x0 = x0, z0 = z0, x1 = x1, z1 = z1 } }
	end
	local out: { Rect } = {}
	local function add(a: number, b: number, c: number, d: number)
		if c > a and d > b then
			table.insert(out, { x0 = a, z0 = b, x1 = c, z1 = d })
		end
	end
	add(x0, z0, x1, hz0)
	add(x0, hz1, x1, z1)
	add(x0, hz0, hx0, hz1)
	add(hx1, hz0, x1, hz1)
	return out
end

-- Does an axis-aligned footprint (centre, size) touch any of the circles?
function BoxKit.hitsAny(circles: { Circle }, cx: number, cz: number, sx: number, sz: number): boolean
	for _, c in circles do
		local dx = math.max(math.abs(c.x - cx) - sx / 2, 0)
		local dz = math.max(math.abs(c.z - cz) - sz / 2, 0)
		if dx * dx + dz * dz < c.r * c.r then
			return true
		end
	end
	return false
end

-- A pitched roof of two wedges over a footprint, ridge along x (along z when alongZ). 2 parts.
function BoxKit.pitchedRoof(
	list: { Box },
	cx: number,
	top: number,
	cz: number,
	sx: number,
	sz: number,
	rise: number,
	color: string,
	alongZ: boolean?
)
	if alongZ then
		-- ridge runs along z: the two halves sit at -x and +x
		local half = sx / 2
		BoxKit.box(
			list,
			"roof",
			cx - half / 2,
			top + rise / 2,
			cz,
			sz,
			rise,
			half,
			color,
			{ shape = "wedge", ry = 90 }
		)
		BoxKit.box(
			list,
			"roof",
			cx + half / 2,
			top + rise / 2,
			cz,
			sz,
			rise,
			half,
			color,
			{ shape = "wedge", ry = -90 }
		)
	else
		local half = sz / 2
		BoxKit.box(
			list,
			"roof",
			cx,
			top + rise / 2,
			cz - half / 2,
			sx,
			rise,
			half,
			color,
			{ shape = "wedge", ry = 0 }
		)
		BoxKit.box(
			list,
			"roof",
			cx,
			top + rise / 2,
			cz + half / 2,
			sx,
			rise,
			half,
			color,
			{ shape = "wedge", ry = 180 }
		)
	end
end

-- A house: body, pitched roof and a door (4 parts). Returns the roof ridge height.
function BoxKit.house(
	list: { Box },
	cx: number,
	gy: number,
	cz: number,
	sx: number,
	sz: number,
	h: number,
	body: string,
	roof: string
): number
	BoxKit.box(list, "building", cx, gy + h / 2, cz, sx, h, sz, body)
	local rise = math.min(sx, sz) * 0.35
	BoxKit.pitchedRoof(list, cx, gy + h, cz, sx, sz, rise, roof, sx < sz)
	BoxKit.box(list, "prop", cx, gy + 3.5, cz + sz / 2 + 0.2, 4, 7, 0.4, "wood", { ghost = true })
	return gy + h + rise
end

-- A tree: trunk and a ball of leaves (2 parts). Returns its top.
function BoxKit.tree(list: { Box }, cx: number, gy: number, cz: number, size: number): number
	BoxKit.box(list, "prop", cx, gy + size * 0.4, cz, size * 0.18, size * 0.8, size * 0.18, "wood")
	BoxKit.box(
		list,
		"prop",
		cx,
		gy + size,
		cz,
		size * 0.9,
		size * 0.9,
		size * 0.9,
		"leaf",
		{ shape = "ball" }
	)
	return gy + size * 1.45
end

-- A low fence line from (x0, z0) to (x1, z1), axis-aligned (1 part)
function BoxKit.fence(list: { Box }, x0: number, z0: number, x1: number, z1: number, gy: number)
	local sx = math.max(math.abs(x1 - x0), 0.6)
	local sz = math.max(math.abs(z1 - z0), 0.6)
	BoxKit.box(list, "prop", (x0 + x1) / 2, gy + 1.5, (z0 + z1) / 2, sx, 3, sz, "white")
end

-- The world footprint of a box (a quarter turn swaps x and z)
function BoxKit.footprint(b: Box): (number, number)
	local ry = (b.ry or 0) % 180
	if ry == 90 then
		return b.sz, b.sx
	end
	return b.sx, b.sz
end

-- The solid parts count toward the heightmap and collisions; window bands, glows and ghosts do not
function BoxKit.solid(b: Box): boolean
	return not b.ghost and b.kind ~= "band" and b.kind ~= "glow"
end

return BoxKit
