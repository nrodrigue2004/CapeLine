--!strict
-- CityPlay: the street-level and rooftop pieces heroes use or break in Downtown and Uptown (pt-city, 2026-11-19,
-- nate's playtest: "a more interactive map, more detailed, higher quality ... fewer simple shapes";
-- Config.City.kit.play). Pure, so Lune checks it.
-- * dress(...): a building's awnings over its shop fronts (they bounce a hero who lands on them), its roof's water
--   tower and antenna as meshes, an air conditioner, vents and a billboard on a flat roof, and steel perches up a
--   tower's faces (mid-air landing spots for skyscraper fights). Each is a box (its collision, the heightmap and
--   today's look) carrying `art`: the Art.Street prop the server builds in its place (CityBuilder), inside the
--   building's model, so it breaks with the building: billboards, tanks and roof units fall off as debris and the
--   water tower bursts (Fx.BuildingFx). Picks are hashes of each spot (CityKit.roll), never a layout draw.
-- * bounce(play, vy): how fast an awning springs a falling hero up.
-- * awnings(boxes) and nearAwning(list, x, y, z): the server's check that a hero who says it bounced is on one.

local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")

local CityPlay = {}

-- What the server builds in place of a box: an Art.Street prop at a foot point, turned ry degrees (it faces -z
-- at 0), in a palette tint when its pieces take one
export type Art = { name: string, x: number, y: number, z: number, ry: number, tint: string? }

local function add(
	boxes: { any },
	kind: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	art: Art
): any
	-- dress: added by the kit, not part of the seeded layout (like kerbs and cornices)
	local b = {
		kind = kind,
		cx = cx,
		cy = cy,
		cz = cz,
		sx = sx,
		sy = sy,
		sz = sz,
		color = color,
		art = art,
		dress = true,
	}
	table.insert(boxes, b)
	return b
end

-- the facing (ry) of a piece on a building face pointing along (fx, fz): a prop faces -z at ry 0
local function facing(fx: number, fz: number): number
	if fz < 0 then
		return 0
	elseif fz > 0 then
		return 180
	elseif fx < 0 then
		return 90
	end
	return -90
end

export type Lot = {
	x: number, -- the body's centre and size
	z: number,
	sx: number,
	sz: number,
	base: number, -- the sidewalk top it stands on
	top: number, -- its roof (the shaft's top on a tower)
	flat: boolean, -- a flat roof (no crown)
	faces: { { number } }, -- its street faces: { fx, fz, gap } (gap: studs from the wall to the block's edge)
	garden: boolean?, -- Uptown's roof garden (no roof units then)
	tank: boolean?, -- a water tower stands on the roof (its quarter is taken)
	antenna: boolean?,
}

-- The awnings over a lot's street faces, its roof pieces and its perches (boxes appended; the caller groups them
-- with the building). Returns how many boxes it added.
function CityPlay.dress(boxes: { any }, kit: any, lot: Lot): number
	local P = kit.play
	if not P then
		return 0
	end
	local first = #boxes
	local x, z, sx, sz = lot.x, lot.z, lot.sx, lot.sz
	local h = lot.top - lot.base
	-- awnings: one over each street face that is wide enough, with room on the sidewalk under it
	local A = P.awning
	local spec = kit.props.Awning
	local out, wide = spec.foot[2], spec.foot[1]
	for _, f in lot.faces do
		local fx, fz, gap = f[1], f[2], f[3]
		local along = if fx ~= 0 then sz else sx
		local wx = x + fx * sx / 2
		local wz = z + fz * sz / 2
		if
			along >= A.minFace
			and gap >= out + 1.6
			and h <= A.maxHeight
			and h > A.y + 4
			and CityKit.roll(kit, wx, wz, A.salt) < A.chance
		then
			-- a long face gets a row of two (a shop front each side), else one slid along it by hash
			local two = along >= 2 * wide + 6
			local slide = if two
				then 0
				else (CityKit.roll(kit, wz, wx, A.salt + 100) - 0.5) * math.max(0, along - wide - 4)
			local y = lot.base + A.y
			local ry = facing(fx, fz)
			local offs: { number } = if two then { -(wide / 2 + 1), wide / 2 + 1 } else { 0 }
			for _, off in offs do
				local ax = wx + (if fx == 0 then slide + off else 0)
				local az = wz + (if fz == 0 then slide + off else 0)
				local tint = CityKit.pick(kit, P.tints, ax, az, A.salt + 200)
				-- the collider: the canvas's slope as one flat slab a little under its top
				local bsx = if fx ~= 0 then out else wide
				local bsz = if fx ~= 0 then wide else out
				local b = add(
					boxes,
					"awning",
					ax + fx * out / 2,
					y - 0.9,
					az + fz * out / 2,
					bsx,
					0.6,
					bsz,
					tint,
					{ name = "Awning", x = ax, y = y, z = az, ry = ry, tint = tint }
				)
				b.tag = "Awning"
			end
		end
	end
	-- the roof: a flat roof's free quarters (the water tower takes +x +z, the antenna -x -z)
	if lot.flat and not lot.garden then
		local top = lot.top
		local B = P.billboard
		local billboard = false
		local street = lot.faces[1]
		local hasStreetZ = false
		for _, f in lot.faces do
			if f[2] ~= 0 then
				street, hasStreetZ = f, true
			end
		end
		if
			not lot.tank
			and hasStreetZ
			and h >= B.minHeight
			and h <= B.maxHeight
			and sx >= B.minWidth
			and sz >= 30
			and CityKit.roll(kit, x, z, B.salt) < B.chance
		then
			-- along the street edge of the roof, facing the street; its face is the collider
			local fz = street[2]
			local bz = z + fz * (sz / 2 - 3.5)
			local tint = CityKit.pick(kit, P.tints, x, bz, B.salt + 200)
			add(
				boxes,
				"prop",
				x,
				top + 11.5,
				bz,
				22,
				9,
				0.6,
				tint,
				{ name = "RoofBillboard", x = x, y = top, z = bz, ry = facing(0, fz), tint = tint }
			)
			billboard = true
		end
		if not billboard and sx >= 20 and sz >= 20 then
			local ax, az = x - sx / 4, z + sz / 4
			if CityKit.roll(kit, ax, az, P.ac.salt) < P.ac.chance then
				local ry = if CityKit.roll(kit, az, ax, P.ac.salt) < 0.5 then 0 else 90
				local w, d = if ry == 0 then 4.6 else 2.8, if ry == 0 then 2.8 else 4.6
				add(boxes, "prop", ax, top + 1.8, az, w, 3.6, d, "steel", {
					name = "RoofAC",
					x = ax,
					y = top,
					z = az,
					ry = ry,
				})
			end
			local vx, vz = x + sx / 4, z - sz / 4
			if CityKit.roll(kit, vx, vz, P.vent.salt) < P.vent.chance then
				add(boxes, "prop", vx, top + 1.5, vz, 2.6, 3, 3.4, "steel", {
					name = "RoofVent",
					x = vx,
					y = top,
					z = vz,
					ry = 0,
				})
			end
		end
	end
	-- perches up a tower's faces: one a level, the face turning by hash, never in the top `top` studs
	local Q = P.perch
	if h >= Q.minHeight then
		local level = 0
		local y = lot.base + Q.from
		while y < lot.top - Q.top do
			local k = (math.floor(CityKit.roll(kit, x, z, Q.salt) * 4) + level) % 4
			local f = ({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } })[k + 1]
			local fx, fz = f[1], f[2]
			local wx, wz = x + fx * sx / 2, z + fz * sz / 2
			local along = if fx ~= 0 then sz else sx
			if along >= 14 then
				local bsx = if fx ~= 0 then 4 else 10
				local bsz = if fx ~= 0 then 10 else 4
				add(boxes, "ledge", wx + fx * 2, y - 0.2, wz + fz * 2, bsx, 0.4, bsz, "steel", {
					name = "Perch",
					x = wx,
					y = y,
					z = wz,
					ry = facing(fx, fz),
				})
				boxes[#boxes].tag = "Perch"
			end
			level += 1
			y += Q.every
		end
	end
	return #boxes - first
end

-- The street faces of lot (lx, lz) in a block of n x n lots: the sides that look onto a street, with the gap
-- from the wall to the block's edge
function CityPlay.faces(
	lx: number,
	lz: number,
	n: number,
	minX: number,
	minZ: number,
	block: number,
	x: number,
	z: number,
	sx: number,
	sz: number
): { { number } }
	local out = {}
	if lx == 1 then
		table.insert(out, { -1, 0, (x - sx / 2) - minX })
	elseif lx == n then
		table.insert(out, { 1, 0, minX + block - (x + sx / 2) })
	end
	if lz == 1 then
		table.insert(out, { 0, -1, (z - sz / 2) - minZ })
	elseif lz == n then
		table.insert(out, { 0, 1, minZ + block - (z + sz / 2) })
	end
	return out
end

-- How fast an awning springs a hero up who lands on it falling at vy (negative): at least `up`, more from a
-- higher fall (keep of the fall's speed), at most `max`. Nil when the hero is not falling fast enough.
function CityPlay.bounce(play: any, vy: number): number?
	local B = play.bounce
	if vy > -B.minFall then
		return nil
	end
	return math.min(B.max, math.max(B.up, -vy * B.keep))
end

-- The awnings in a list of boxes (the world's hubBoxes), bucketed for nearAwning
export type AwningIndex = { cell: number, cells: { [number]: { any } }, count: number }

function CityPlay.awnings(boxes: { any }): AwningIndex
	local idx: AwningIndex = { cell = 32, cells = {}, count = 0 }
	for _, b in boxes do
		if b.tag == "Awning" then
			local k = math.floor(b.cx / idx.cell) * 65536 + math.floor(b.cz / idx.cell)
			local list = idx.cells[k]
			if not list then
				list = {}
				idx.cells[k] = list
			end
			table.insert(list, b)
			idx.count += 1
		end
	end
	return idx
end

-- The awning a hero at (x, y, z) stands on or just left (within `reach` studs of its top), or nil
function CityPlay.nearAwning(idx: AwningIndex, x: number, y: number, z: number, reach: number): any?
	local c = idx.cell
	for ix = math.floor(x / c) - 1, math.floor(x / c) + 1 do
		for iz = math.floor(z / c) - 1, math.floor(z / c) + 1 do
			local list: { any } = idx.cells[ix * 65536 + iz] or {}
			for _, b in list do
				local top = b.cy + b.sy / 2
				if
					math.abs(x - b.cx) <= b.sx / 2 + reach
					and math.abs(z - b.cz) <= b.sz / 2 + reach
					and y >= top - 2
					and y <= top + reach + 6
				then
					return b
				end
			end
		end
	end
	return nil
end

return CityPlay
