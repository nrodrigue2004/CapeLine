--!strict
-- CityLayout: the Downtown greybox as plain boxes (spec: Map layout; M1 "greybox Downtown"; WorldMap adds the
-- rest of the map in M4 and has the whole-map heightAt). Pure and
-- seeded, so the server builds the same city every time, the Lune tests can check part counts and heights,
-- and the drone AI can ask how tall the city is anywhere (heightAt) without raycasts.
-- PLACEHOLDER ART: grey boxes, window bands and rooftop props until the kit pass (M5). With Config.City.kit
-- (overhaul step 5) every block is dressed: textured fronts, paving, kerbs, lane dashes, cornices and props.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")
local CityPlay = if script then require(script.Parent.CityPlay) else (require :: any)("./CityPlay")

local CityLayout = {}

export type Box = {
	kind: string, -- ground, road, sidewalk, plaza, building, band, ledge, prop, beacon, glow, water, spawn
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string, -- a Config.City.palette key
	shape: string?, -- "cylinder" (axis along y), "wedge" (see BoxKit), "ball"
	ry: number?, -- turn around y in degrees (multiples of 90 keep the box axis-aligned)
	tag: string?, -- what a server service looks for (a terminal kind, a beacon, a landmark zone)
	ref: number?, -- the id that tag belongs to (a safehouse or beacon id)
	ghost: boolean?, -- no collision (light beams, signs above heads)
	grp: string?, -- the building this part belongs to (its body, bands, roof and rooftop props)
	bid: number?, -- the destructible building id (WorldMap), when that building can be wrecked
	kit: string?, -- city kit texture (MaterialVariant "Kit" .. kit, Config.City.kit)
	tint: string?, -- the palette colour a tinted kit texture shows in (Config.City.kit.tinted)
	plain: string?, -- drawn only while this kit texture is missing (a kit building's window bands)
	dress: boolean?, -- added by the kit (kerbs, dashes, cornices): not part of the seeded layout
	crown: boolean?, -- a skyscraper's top above its wreckable shaft (setbacks, spire, lantern, mast)
	art: any?, -- the Art.Street prop the server builds in its place (Shared.CityPlay.Art, pt-city 2026-11-19)
}

-- A street prop (Config.City.kit.props; Art.Street meshes, built by each device: CityProps)
export type Prop = CityKit.Prop

export type Layout = {
	boxes: { Box },
	buildings: {
		{
			x: number,
			z: number,
			sx: number,
			sz: number,
			h: number,
			grp: string?,
			base: number?,
			grown: boolean?,
			crown: string?, -- a tower's silhouette (Config.City.skyline), above its shaft
			peak: number?, -- the top of its crown
		}
	},
	spawns: { { x: number, y: number, z: number } },
	droneSpots: { { x: number, y: number, z: number } },
	beacon: { x: number, z: number, h: number },
	safehouseSpots: { [number]: { x: number, z: number } }, -- reserved lots (Config.World.safehouses)
	grid: { cell: number, minX: number, minZ: number, n: number, tops: { number } },
	parts: number,
	props: { Prop },
	open: { { id: string, x: number, z: number, size: number } }, -- open squares kept for the lore thread
	-- the rooftop row (Config.City.downtown.row) in running order: each roof's centre, top and footprint
	row: { { x: number, z: number, top: number, sx: number, sz: number, grp: string } },
}

local function box(
	list: { Box },
	kind: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	shape: string?
)
	table.insert(
		list,
		{ kind = kind, cx = cx, cy = cy, cz = cz, sx = sx, sy = sy, sz = sz, color = color, shape = shape }
	)
end

local BODY_COLORS = { "concrete", "brick", "slate", "sand", "steel", "glass" }

-- The city kit's street dressing for one Downtown or Uptown block (style.planter: trees in planters or
-- flower tubs; no random draws, so the layout is unchanged; picks are
-- hashes of the block's position): kerbs, and props along each side: lamps at the kerb with trees between, a
-- feature near the middle (a bench and a bin, a bus stop, a bike rack with bollards, or two benches), a hydrant
-- near a corner, and traffic lights on the north-west and south-east corners (two at every crossing).
local function dressBlock(
	boxes: { Box },
	props: { Prop },
	t: any,
	kit: any,
	minX: number,
	minZ: number,
	gy: number,
	style: any
)
	local b = t.block
	local kw = kit.kerb
	local top = gy + 0.9
	CityKit.kerbs(boxes, minX, minZ, b, gy + 0.55, kw)
	local sides = CityKit.sides(minX, minZ, b)
	local span = b - 16
	local lamps = math.max(2, math.floor(span / kit.lampEvery) + 1)
	local step = span / (lamps - 1)
	local function put(name: string, side: any, along: number, inset: number)
		CityKit.onSide(props, name, side, along, inset, top)
	end
	for si, side in sides do
		for k = 0, lamps - 1 do
			local along = -span / 2 + k * step
			put("StreetLamp", side, along, kw + 0.7)
			if k < lamps - 1 then
				put(style.planter, side, along + step / 2, kw + 2.1)
			end
		end
		-- the side's feature between the middle lamps, picked by hash; a hydrant near a corner
		local mid = -span / 2 + math.floor((lamps - 1) / 2) * step + step * 0.25
		local feature = CityKit.pick(kit, { "bench", "bus", "bikes", "benches" }, side.x, side.z, 11)
		if feature == "bus" then
			put("BusStop", side, mid - 0.5, 3.0)
			put("Bin", side, mid + 4.4, 3.2)
		elseif feature == "bikes" then
			put("BikeRack", side, mid, 3.2)
			put("Bollard", side, mid + 4.0, kw + 0.9)
			put("Bollard", side, mid - 4.0, kw + 0.9)
		elseif feature == "benches" then
			put("Bench", side, mid - 3.0, 3.2)
			put("Bin", side, mid + 1.3, 3.2)
			put("Bench", side, mid + step / 2, 3.2)
		else
			put("Bench", side, mid, 3.2)
			put("Bin", side, mid + 4.2, 3.2)
		end
		put("Hydrant", side, (if si % 2 == 0 then -1 else 1) * (b / 2 - 5), kw + 0.9)
		-- pt-city (2026-11-19): a pair of news boxes toward the side's other end, in a tint by hash
		local play = kit.play
		if play and CityKit.roll(kit, side.x, side.z, play.newsBox.salt) < play.newsBox.chance then
			put("NewsBox", side, (if si % 2 == 0 then 1 else -1) * (b / 2 - 11), 3.0)
			props[#props].tint = CityKit.pick(kit, play.tints, side.x, side.z, play.newsBox.salt)
		end
	end
	-- traffic lights on two opposite corners, arms out over the street
	put("TrafficLight", sides[1], -b / 2 + 2.2, kw + 1.2)
	put("TrafficLight", sides[2], -b / 2 + 2.2, kw + 1.2)
end

-- Lane dashes down the middle of the streets east (+x) and south (+z) of a block, when a block lies beyond
-- (every street between two blocks gets its dashes once; the outer streets are half on the grass)
local function dashes(
	boxes: { Box },
	t: any,
	kit: any,
	minX: number,
	minZ: number,
	gy: number,
	east: boolean,
	south: boolean
)
	local b = t.block
	local cx, cz = minX + b / 2, minZ + b / 2
	local d = kit.dash
	local n = math.floor((b + d.gap) / (d.length + d.gap))
	local run = n * d.length + (n - 1) * d.gap
	for k = 0, n - 1 do
		local along = -run / 2 + d.length / 2 + k * (d.length + d.gap)
		if south then
			box(
				boxes,
				"mark",
				cx + along,
				gy + 0.22,
				minZ + b + t.street / 2,
				d.length,
				0.04,
				d.width,
				"mark"
			)
			boxes[#boxes].dress = true
		end
		if east then
			box(
				boxes,
				"mark",
				minX + b + t.street / 2,
				gy + 0.22,
				cz + along,
				d.width,
				0.04,
				d.length,
				"mark"
			)
			boxes[#boxes].dress = true
		end
	end
end

-- What one district grid builds into: shared by Downtown (its core and grown blocks) and Uptown
type Ctx = {
	boxes: { Box },
	buildings: { any },
	props: { Prop },
	droneSpots: { { x: number, y: number, z: number } },
	safehouseSpots: { [number]: { x: number, z: number } },
	reserved: { [string]: number },
	t: any, -- the district's grid config (Config.City.downtown or .uptown)
	kit: any?,
	gy: number,
	group: string, -- kit.fronts group and kit.ground key
	colors: { string }, -- body colours (palette keys)
	prefix: string, -- building group names: "D1", "D2", ... or "U1", ...
	style: any, -- dressBlock's props
	grown: boolean, -- buildings outside the first Downtown (WorldMap ids them after the first 220)
	skyline: any?, -- Config.City.skyline: tower silhouettes and band spacing
	row: { [string]: number }?, -- the rooftop row's blocks ("bx,bz" -> its place in downtown.row.blocks)
	rowOut: { any }?, -- the row's roofs as they are built (Layout.row)
	towerChance: number?, -- this block's tower chance when not the district's (the 2026-11-19 blocks: more towers)
}

local DOWNTOWN_STYLE = { planter = "Planter" }
local UPTOWN_STYLE = { planter = "FlowerTub" }

-- Skyscrapers (nate 2026-11-17: "We need taller buildings, skyscrapers"). A tower's shaft is its wreckable box
-- (Shared.Structure); its silhouette above the shaft is the crown (Config.City.skyline): setbacks, a spire on a
-- crown block, a lit lantern between corner fins, or a mast. Crown parts belong to the building (its grp) and
-- are marked crown, so a device shows them while the shaft's top storey stands. Part of the height each style
-- gives the shaft:
local SHAFT = { setback = 0.64, spire = 0.8, crown = 0.9, mast = 0.9 }

local function crownBox(
	c: Ctx,
	kind: string,
	x: number,
	y0: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	shape: string?
)
	box(c.boxes, kind, x, y0 + sy / 2, z, sx, sy, sz, color, shape)
	c.boxes[#c.boxes].crown = true
end

-- The parts above a shaft topped at `top`, `rise` studs up to the tower's peak. body: the shaft's box (a tier
-- wears the same kit front, capped by a cornice).
local function towerCrown(c: Ctx, style: string, body: Box, top: number, rise: number)
	local x, z, sx, sz = body.cx, body.cz, body.sx, body.sz
	local kit = c.kit
	local function tier(f: number, h: number, y0: number): number
		crownBox(c, "tier", x, y0, z, sx * f, h, sz * f, body.color)
		local b = c.boxes[#c.boxes]
		b.kit, b.tint = body.kit, body.tint
		if kit and body.kit then
			crownBox(
				c,
				"ledge",
				x,
				y0 + h - kit.cornice + 0.05,
				z,
				sx * f + 1,
				kit.cornice,
				sz * f + 1,
				"cornice"
			)
			c.boxes[#c.boxes].dress = true
		end
		return y0 + h
	end
	if style == "setback" then
		local y = tier(0.74, math.floor(rise * 0.56), top)
		y = tier(0.5, math.floor(rise * 0.33), y)
		tier(0.28, top + rise - y, y)
	elseif style == "spire" then
		local y = tier(0.78, math.floor(rise * 0.12), top)
		local d = math.max(2, math.min(sx, sz) * 0.1)
		crownBox(c, "tier", x, y, z, d, top + rise - y, d, "steel", "cylinder")
	elseif style == "crown" then
		-- a lit lantern between four corner fins
		crownBox(c, "glow", x, top, z, sx * 0.84, rise * 0.6, sz * 0.84, "beaconGlow")
		for _, k in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			crownBox(
				c,
				"tier",
				x + k[1] * (sx / 2 - 1.5),
				top,
				z + k[2] * (sz / 2 - 1.5),
				3,
				rise,
				3,
				body.color
			)
			-- the fins wear the shaft's front (pt-ui 2026-11-19: they were the only plain part of the tower)
			local fin = c.boxes[#c.boxes]
			fin.kit, fin.tint = body.kit, body.tint
		end
	elseif style == "mast" then
		local y = top + math.floor(rise * 0.2)
		crownBox(c, "tier", x, top, z, sx * 0.4, y - top, sz * 0.4, "steel")
		crownBox(c, "tier", x, y, z, 1.6, top + rise - y, 1.6, "steel", "cylinder")
	end
end

-- Window bands, one wrap-around part a storey low down and every few storeys higher up (PLACEHOLDER ART); on a
-- kit building they show only until its front texture is in, whose windows they stand for
local function bands(c: Ctx, x: number, z: number, sx: number, sz: number, height: number)
	local sky = c.skyline
	local y = 10
	while y < height - 6 do
		box(c.boxes, "band", x, c.gy + 0.9 + y, z, sx + 0.4, 3, sz + 0.4, "window")
		y += if sky and y >= sky.bandsLow then sky.bandStep else 12
	end
end

-- The rooftop row's dressing on one roof, in its own frame: u along the row, v across it (v < 0 is the street
-- side of the strip). The middle of every roof stays clear for landing; what stands is solid and low (AC
-- units, tanks, skylights, a hatch, the posts) and what is only decoration is walk-through (the billboard's
-- face, the washing line). PLACEHOLDER ART: plain boxes in the city palette until the kit gets rooftop meshes.
local ROW_DRESS: { [string]: { { any } } } = {
	-- { kind, u, u studs, v, du, dy, dv, y (its foot above the roof), color, shape?, ghost? }: u and v are -1
	-- to 1 across the roof's free half width and half depth (u plus a stud offset); sizes in studs, and a
	-- negative du is the roof's width less that much
	ac = {
		{ "prop", -1, 0, 1, 4, 3, 5, 0, "steel" },
		{ "prop", -1, 5, 1, 4, 3, 5, 0, "steel" },
	},
	hatch = { { "prop", 1, 0, -1, 4, 2.5, 4, 0, "roof" } },
	tank = {
		{ "prop", -1, 0, 1, 8, 2, 8, 0, "steel" },
		{ "prop", -1, -0.5, 1, 7, 10, 7, 2, "wood", "cylinder" },
	},
	billboard = {
		{ "prop", -1, 3, -1, 1, 15, 1, 0, "steel" },
		{ "prop", 1, -3, -1, 1, 15, 1, 0, "steel" },
		{ "prop", 0, 0, -1, -2, 9, 0.6, 5.5, "white", nil, true },
	},
	skylights = {
		{ "prop", -0.5, 0, 0.5, 6, 1.2, 8, 0, "glass" },
		{ "prop", 0.5, 0, 0.5, 6, 1.2, 8, 0, "glass" },
	},
	laundry = {
		{ "prop", -1, 2, 0.82, 0.6, 7, 0.6, 0, "steel" },
		{ "prop", 1, -2, 0.82, 0.6, 7, 0.6, 0, "steel" },
		{ "prop", 0, 0, 0.82, -6.6, 0.2, 0.2, 6.6, "white", nil, true },
		{ "prop", -0.45, 0, 0.82, 2.4, 3, 0.2, 3.6, "white", nil, true },
		{ "prop", 0, 0, 0.82, 2.4, 3, 0.2, 3.6, "roofRed", nil, true },
		{ "prop", 0.45, 0, 0.82, 2.4, 3, 0.2, 3.6, "roofBlue", nil, true },
	},
}

-- The rooftop row (Config.City.downtown.row) in one of its blocks: `k` is the block's place in row.blocks, so
-- its roofs are row.roofs[(k - 1) * #row.at + 1 ...]. Designed numbers, no draws: the same city every time.
-- Each roof is a real building (a group, a kit front, a cornice, a drone spot), so it wrecks and repairs.
local function rooftopRow(c: Ctx, k: number, minX: number, minZ: number)
	local boxes, t, kit, gy = c.boxes, c.t, c.kit, c.gy
	local R = t.row
	local inner = t.block - 2 * t.sidewalk
	local lot = (inner - t.lotGap * (t.lotsPerSide - 1)) / t.lotsPerSide
	local z = minZ + t.sidewalk + (R.strip - 1) * (lot + t.lotGap) + lot / 2
	for j, along in R.at do
		local i = (k - 1) * #R.at + j
		local r = R.roofs[i]
		if not r then
			continue
		end
		local x = minX + t.block / 2 + along
		local top = gy + 0.9 + r.h
		local first = #boxes + 1
		box(boxes, "building", x, gy + 0.9 + r.h / 2, z, r.w, r.h, r.d, r.color)
		bands(c, x, z, r.w, r.d, r.h)
		if kit then
			local front = CityKit.front(kit, boxes[first], kit.fronts[c.group], r.color) or "Office"
			for n = first + 1, #boxes do
				boxes[n].plain = front
			end
			box(boxes, "ledge", x, top - kit.cornice / 2 + 0.05, z, r.w + 1, kit.cornice, r.d + 1, "cornice")
			boxes[#boxes].dress = true
		end
		for _, name in r.dress or {} do
			local list: { { any } } = ROW_DRESS[name] or {}
			for _, d in list do
				local du = if d[5] < 0 then r.w + d[5] else d[5]
				local dv = d[7]
				local u = d[2] * (r.w / 2 - du / 2 - 1) + d[3]
				local v = d[4] * (r.d / 2 - dv / 2 - 1)
				box(boxes, d[1], x + u, top + d[8] + d[6] / 2, z + v, du, d[6], dv, d[9], d[10])
				boxes[#boxes].ghost = if d[11] then true else nil
			end
		end
		local grp = c.prefix .. (#c.buildings + 1)
		for n = first, #boxes do
			boxes[n].grp = grp
		end
		table.insert(
			c.buildings,
			{ x = x, z = z, sx = r.w, sz = r.d, h = r.h + 0.9, grp = grp, base = gy + 0.9 }
		)
		table.insert(c.droneSpots, { x = x, y = top + 18, z = z })
		if c.rowOut then
			c.rowOut[i] = { x = x, z = z, top = top, sx = r.w, sz = r.d, grp = grp }
		end
	end
end

-- One block of 2 x 2 lots (or a reserved safehouse lot), its sidewalk and, with the kit, its dressing. The
-- draws per lot are always the same eight in the same order, so a reserved lot never moves the others.
local function lotBlock(c: Ctx, rng: any, bx: number, bz: number, minX: number, minZ: number)
	local boxes, t, kit, gy = c.boxes, c.t, c.kit, c.gy
	local bcx, bcz = minX + t.block / 2, minZ + t.block / 2
	local blockFirst = #boxes + 1
	local propsFrom = #c.props + 1
	box(boxes, "sidewalk", bcx, gy + 0.5, bcz, t.block, 0.8, t.block, "sidewalk")
	if kit then
		boxes[#boxes].kit = kit.ground[c.group].sidewalk
		dressBlock(boxes, c.props, t, kit, minX, minZ, gy, c.style)
	end
	local inner = t.block - 2 * t.sidewalk
	local lot = (inner - t.lotGap * (t.lotsPerSide - 1)) / t.lotsPerSide
	local roofProp = t.rooftop.waterTowerChance or t.rooftop.gardenChance
	local rowAt = c.row and c.row[bx .. "," .. bz]
	for lx = 1, t.lotsPerSide do
		for lz = 1, t.lotsPerSide do
			local lcx = minX + t.sidewalk + (lx - 1) * (lot + t.lotGap) + lot / 2
			local lcz = minZ + t.sidewalk + (lz - 1) * (lot + t.lotGap) + lot / 2
			local tall = rng:chance(c.towerChance or t.height.towerChance)
			local height = if tall
				then rng:range(t.height.towerMin, t.height.towerMax)
				else rng:range(t.height.min, t.height.max)
			height = math.floor(height / 4) * 4
			local sx = lot - rng:range(0, 6)
			local sz = lot - rng:range(0, 6)
			local color = c.colors[rng:int(1, #c.colors)]
			local reservedId = c.reserved[string.format("%d,%d,%d,%d", bx, bz, lx, lz)]
			local hasLedge = rng:chance(t.rooftop.ledgeChance)
			local hasTank = rng:chance(roofProp)
			local hasAntenna = rng:chance(t.rooftop.antennaChance)
			if reservedId then
				c.safehouseSpots[reservedId] = { x = lcx, z = lcz }
				continue
			end
			if rowAt and lz == t.row.strip then
				continue -- the rooftop row stands here (its draws were taken, so nothing else moves)
			end
			local first = #boxes + 1
			-- a tower's silhouette, by a hash of its spot (never a draw): its shaft is the wreckable box
			local sky = c.skyline
			local style = "flat"
			if tall and sky then
				style = sky.styles[Rng.hash(t.seed, math.floor(lcx), math.floor(lcz), 9) % #sky.styles + 1]
			end
			local peak = height
			if style ~= "flat" then
				height = math.floor(height * SHAFT[style] / 4) * 4
			end
			local top = gy + 0.9 + height
			box(boxes, "building", lcx, gy + 0.9 + height / 2, lcz, sx, height, sz, color)
			bands(c, lcx, lcz, sx, sz, height)
			if kit then
				-- a kit building: its front has the windows in it (one storey a tile; picked by hash from its
				-- colour's fronts), its bands show only until that texture is in, and a roof cornice caps it
				local front = CityKit.front(
					kit,
					boxes[first],
					kit.fronts[c.group],
					if tall then "tower" else color
				) or "Office"
				for k = first + 1, #boxes do
					boxes[k].plain = front
				end
				box(
					boxes,
					"ledge",
					lcx,
					top - kit.cornice / 2 + 0.05, -- caps the roof (a front's texture has no roof)
					lcz,
					sx + 1,
					kit.cornice,
					sz + 1,
					"cornice"
				)
				boxes[#boxes].dress = true
			end
			if style ~= "flat" then
				towerCrown(c, style, boxes[first], top, peak - height)
				hasLedge, hasTank, hasAntenna = false, false, false -- the crown is the roof
			end
			-- rooftop: a ledge you can land on and a few props
			if hasLedge then
				box(boxes, "ledge", lcx, top + 1, lcz - sz / 2 + 0.75, sx, 2, 1.5, "roof")
				box(boxes, "ledge", lcx, top + 1, lcz + sz / 2 - 0.75, sx, 2, 1.5, "roof")
			end
			if hasTank and t.rooftop.gardenChance then
				-- Uptown: a roof garden, a planted bed you can land in
				box(boxes, "prop", lcx, top + 0.6, lcz, sx * 0.6, 1.2, sz * 0.6, "leaf")
			elseif hasTank then
				box(boxes, "prop", lcx + sx / 4, top + 6, lcz + sz / 4, 10, 12, 10, "brick", "cylinder")
				if kit and kit.play then
					-- a water tower mesh in its place (pt-city): it bursts off the roof when the building breaks
					boxes[#boxes].art =
						{ name = "WaterTower", x = lcx + sx / 4, y = top, z = lcz + sz / 4, ry = 0 }
				end
			end
			if hasAntenna then
				box(boxes, "prop", lcx - sx / 4, top + 10, lcz - sz / 4, 1, 20, 1, "steel")
				if kit and kit.play then
					boxes[#boxes].art =
						{ name = "RoofAntenna", x = lcx - sx / 4, y = top, z = lcz - sz / 4, ry = 0 }
				end
			end
			if kit and kit.play then
				-- pt-city (2026-11-19): awnings over its shop fronts, roof units and a billboard, perches up a tower
				CityPlay.dress(boxes, kit, {
					x = lcx,
					z = lcz,
					sx = sx,
					sz = sz,
					base = gy + 0.9,
					top = top,
					flat = style == "flat",
					faces = CityPlay.faces(lx, lz, t.lotsPerSide, minX, minZ, t.block, lcx, lcz, sx, sz),
					garden = hasTank and t.rooftop.gardenChance ~= nil,
					tank = hasTank and t.rooftop.gardenChance == nil,
					antenna = hasAntenna,
				})
			end
			local grp = c.prefix .. (#c.buildings + 1)
			for k = first, #boxes do
				boxes[k].grp = grp
			end
			table.insert(c.buildings, {
				x = lcx,
				z = lcz,
				sx = sx,
				sz = sz,
				h = height + 0.9,
				grp = grp,
				base = gy + 0.9,
				grown = if c.grown then true else nil,
				crown = if style ~= "flat" then style else nil,
				peak = gy + 0.9 + peak,
			})
			table.insert(c.droneSpots, { x = lcx, y = top + 18, z = lcz })
		end
	end
	if rowAt then
		rooftopRow(c, rowAt, minX, minZ)
	end
	if kit then
		-- the block's props stay clear of its buildings and of each other
		local clearOf = {}
		table.move(boxes, blockFirst, #boxes, 1, clearOf)
		CityKit.keep(kit, c.props, propsFrom, CityKit.obstacles(clearOf, gy + 0.9))
	end
end

-- An open square (kept for the lore thread): paved and kerbed, the street side's lamps and planters round its
-- edge, benches facing in and planters on the inner corners; nothing built on it
local function openBlock(c: Ctx, minX: number, minZ: number)
	local boxes, t, kit, gy = c.boxes, c.t, c.kit, c.gy
	local bcx, bcz = minX + t.block / 2, minZ + t.block / 2
	box(boxes, "plaza", bcx, gy + 0.5, bcz, t.block, 0.8, t.block, "sidewalk")
	if not kit then
		return
	end
	boxes[#boxes].kit = kit.ground[c.group].sidewalk
	local propsFrom = #c.props + 1
	dressBlock(boxes, c.props, t, kit, minX, minZ, gy, c.style)
	local top = gy + 0.9
	local r = t.block / 2 - 16
	for _, s in { { 0, -1, 180 }, { 0, 1, 0 }, { -1, 0, 90 }, { 1, 0, -90 } } do
		for _, along in { -10, 10 } do
			local x = bcx + s[1] * r + (if s[1] == 0 then along else 0)
			local z = bcz + s[2] * r + (if s[2] == 0 then along else 0)
			CityKit.put(c.props, "Bench", x, top, z, s[3])
		end
	end
	for _, s in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		CityKit.put(c.props, c.style.planter, bcx + s[1] * r, top, bcz + s[2] * r, 0)
	end
	if kit.play then
		-- a food cart (pt-city, 2026-11-19), in a tint by hash
		local cart = CityKit.put(c.props, "FoodCart", bcx + 14, top, bcz - 14, 0)
		cart.tint = CityKit.pick(kit, kit.play.tints, cart.x, cart.z, kit.play.foodCart.salt)
	end
	CityKit.keep(kit, c.props, propsFrom, CityKit.obstacles({}, top))
end

-- worldCfg (optional): Config.World, whose Downtown safehouses take a reserved lot each. The random draws
-- for a reserved lot still happen, so the rest of Downtown stays the same with or without them.
-- The first 700 x 700 (downtown.core) is built first from the one seeded stream, exactly as it always was;
-- the grown blocks (downtown.grow) follow, each from its own seeded stream, so growing Downtown or keeping
-- an open square never moves a core building, a safehouse lot or the Beacon Tower.
function CityLayout.downtown(cityCfg: any, worldCfg: any?): Layout
	local d = cityCfg.districts.Downtown
	local reserved: { [string]: number } = {}
	local safehouseSpots = {}
	if worldCfg then
		for _, s in worldCfg.safehouses do
			if s.lot then
				reserved[table.concat(s.lot, ",")] = s.id
			end
		end
	end
	local t = cityCfg.downtown
	local core = t.core or d
	local rng = Rng.new(t.seed)
	local boxes: { Box } = {}
	local buildings = {}
	local spawns = {}
	local droneSpots = {}
	local props: { Prop } = {}
	local gy = cityCfg.ground.y
	local kit = cityCfg.kit
	local c: Ctx = {
		boxes = boxes,
		buildings = buildings,
		props = props,
		droneSpots = droneSpots,
		safehouseSpots = safehouseSpots,
		reserved = reserved,
		t = t,
		kit = kit,
		gy = gy,
		group = "Downtown",
		colors = BODY_COLORS,
		prefix = "D",
		style = DOWNTOWN_STYLE,
		grown = false,
		skyline = cityCfg.skyline,
		row = nil,
		rowOut = {},
	}
	if t.row then
		local rowBlocks = {}
		for k, b in t.row.blocks do
			rowBlocks[b[1] .. "," .. b[2]] = k
		end
		c.row = rowBlocks
	end

	-- Downtown asphalt base (the kit's road texture covers it all: it is one part)
	local w, h = d.maxX - d.minX, d.maxZ - d.minZ
	local cx, cz = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
	box(boxes, "road", cx, gy + 0.1, cz, w, 0.2, h, "road")
	if kit then
		boxes[#boxes].kit = kit.ground.Downtown.road
	end

	-- block (bx, bz) counts from the core's north-west block (1, 1); grown blocks go below 1 and past n
	local pitch = t.block + t.street
	local nx = math.floor((core.maxX - core.minX) / pitch)
	local nz = math.floor((core.maxZ - core.minZ) / pitch)
	local firstX = 1 - math.floor((core.minX - d.minX) / pitch + 0.5)
	local firstZ = 1 - math.floor((core.minZ - d.minZ) / pitch + 0.5)
	local lastX = math.floor((d.maxX - core.minX) / pitch + 0.5)
	local lastZ = math.floor((d.maxZ - core.minZ) / pitch + 0.5)
	local midX, midZ = math.ceil(nx / 2), math.ceil(nz / 2)
	local beacon = { x = 0, z = 0, h = t.beacon.height }
	local open: { [string]: string } = {}
	for _, o in t.open or {} do
		open[o.block[1] .. "," .. o.block[2]] = o.id
	end
	local openSquares = {}
	local function corner(bx: number, bz: number): (number, number)
		return core.minX + t.street / 2 + (bx - 1) * pitch, core.minZ + t.street / 2 + (bz - 1) * pitch
	end

	-- the core, in its first order and from its first stream
	for bx = 1, nx do
		for bz = 1, nz do
			local minX, minZ = corner(bx, bz)
			local bcx, bcz = minX + t.block / 2, minZ + t.block / 2
			if kit then
				dashes(boxes, t, kit, minX, minZ, gy, bx < lastX, bz < lastZ)
			end
			if bx == midX and bz == midZ then
				-- the plaza and Beacon Tower (the Vigil's HQ): where new heroes land
				box(boxes, "plaza", bcx, gy + 0.6, bcz, t.block, 1, t.block, "sidewalk")
				local bw = t.beacon.width
				box(
					boxes,
					"beacon",
					bcx,
					gy + 1 + t.beacon.height / 2,
					bcz,
					bw,
					t.beacon.height,
					bw,
					"beacon"
				)
				if kit then
					-- the Beacon Tower in white panels with windows (pt-ui 2026-11-19: it was the tallest plain part)
					boxes[#boxes].kit = kit.beaconFront
				end
				box(
					boxes,
					"glow",
					bcx,
					gy + 1 + t.beacon.height + 3,
					bcz,
					bw * 0.6,
					6,
					bw * 0.6,
					"beaconGlow"
				)
				for k = 1, 8 do
					box(
						boxes,
						"band",
						bcx,
						gy + 1 + k * (t.beacon.height / 9),
						bcz,
						bw + 0.6,
						2,
						bw + 0.6,
						"beaconGlow"
					)
				end
				table.insert(buildings, { x = bcx, z = bcz, sx = bw, sz = bw, h = t.beacon.height + 7 })
				beacon = { x = bcx, z = bcz, h = t.beacon.height }
				local off = t.block / 2 - 12
				for _, s in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
					table.insert(spawns, { x = bcx + s[1] * off, y = gy + 4, z = bcz + s[2] * off })
				end
			else
				lotBlock(c, rng, bx, bz, minX, minZ)
			end
		end
	end

	-- the grown blocks, each from its own stream (a hash of the block), and the open squares among them. The
	-- first ring (downtown.grow1, 2026-11-17) is built first in its old order, so its buildings keep their
	-- groups and wreck ids; the 2026-11-19 blocks follow with their own tower chance (downtown.towers)
	c.grown = true
	local g1 = t.grow1 or t.grow
	local function firstRing(bx: number, bz: number): boolean
		return bx >= 1 - g1.west and bx <= nx + g1.east and bz >= 1 - g1.north and bz <= nz + g1.south
	end
	for pass = 1, 2 do
		for bx = firstX, lastX do
			for bz = firstZ, lastZ do
				if bx >= 1 and bx <= nx and bz >= 1 and bz <= nz then
					continue
				end
				if firstRing(bx, bz) ~= (pass == 1) then
					continue
				end
				c.towerChance = if pass == 2 and t.towers then t.towers.chance else nil
				local minX, minZ = corner(bx, bz)
				if kit then
					dashes(boxes, t, kit, minX, minZ, gy, bx < lastX, bz < lastZ)
				end
				local id = open[bx .. "," .. bz]
				if id then
					openBlock(c, minX, minZ)
					table.insert(
						openSquares,
						{ id = id, x = minX + t.block / 2, z = minZ + t.block / 2, size = t.block }
					)
				else
					lotBlock(c, Rng.new(Rng.hash(t.seed, bx + 64, bz + 64, 5)), bx, bz, minX, minZ)
				end
			end
		end
	end
	c.towerChance = nil

	-- height grid for the drone AI and shot checks (max top per 10-stud cell over the hub)
	local hub = cityCfg.hub
	local hubSize = hub.max - hub.min
	local cell = 10
	local n = math.ceil(hubSize / cell)
	local tops = table.create(n * n, gy)
	for _, b in buildings do
		local x0 = math.floor((b.x - b.sx / 2 - hub.min) / cell)
		local x1 = math.floor((b.x + b.sx / 2 - hub.min) / cell)
		local z0 = math.floor((b.z - b.sz / 2 - hub.min) / cell)
		local z1 = math.floor((b.z + b.sz / 2 - hub.min) / cell)
		for ix = math.max(0, x0), math.min(n - 1, x1) do
			for iz = math.max(0, z0), math.min(n - 1, z1) do
				local i = iz * n + ix + 1
				tops[i] = math.max(tops[i], gy + b.h)
			end
		end
	end

	local parts = 0
	for _, b in boxes do
		if b.kind ~= "spawn" then
			parts += 1
		end
	end

	return {
		boxes = boxes,
		buildings = buildings,
		spawns = spawns,
		droneSpots = droneSpots,
		beacon = beacon,
		safehouseSpots = safehouseSpots,
		grid = { cell = cell, minX = hub.min, minZ = hub.min, n = n, tops = tops },
		parts = parts,
		props = props,
		open = openSquares,
		row = c.rowOut or {},
	}
end

-- Uptown's green (Config.City.uptown.park): a lawn with a fountain in the middle, terrazzo paths across it,
-- trees in the four quarters and, with the kit, benches along the paths, flower tubs and bushes
local function parkBlock(c: Ctx, minX: number, minZ: number)
	local boxes, t, kit, gy = c.boxes, c.t, c.kit, c.gy
	local b = t.block
	local bcx, bcz = minX + b / 2, minZ + b / 2
	local f = t.fountain
	local parkFirst = #boxes + 1
	box(boxes, "plaza", bcx, gy + 0.5, bcz, b, 0.8, b, "grass")
	local top = gy + 0.9
	for _, p in { { b, 8 }, { 8, b } } do
		box(boxes, "plaza", bcx, gy + 0.55, bcz, p[1], 0.8, p[2], "terrazzo")
		if kit then
			boxes[#boxes].kit = kit.ground.Uptown.park
		end
	end
	-- the fountain: a stone basin, its water and a jet (walk round it, land on its rim)
	box(
		boxes,
		"prop",
		bcx,
		top + f.height / 2,
		bcz,
		f.radius * 2,
		f.height,
		f.radius * 2,
		"upCream",
		"cylinder"
	)
	box(
		boxes,
		"water",
		bcx,
		top + f.height - 0.2,
		bcz,
		f.radius * 2 - 2,
		0.4,
		f.radius * 2 - 2,
		"water",
		"cylinder"
	)
	box(boxes, "prop", bcx, top + f.height + f.jet / 2, bcz, 2, f.jet, 2, "water", "cylinder")
	boxes[#boxes].ghost = true
	-- trees in the quarters
	for _, q in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		for k = 0, 1 do
			local x = bcx + q[1] * (b / 4 + (k - 0.5) * 14)
			local z = bcz + q[2] * (b / 4 - (k - 0.5) * 14)
			local size = 11 + k * 2
			box(boxes, "prop", x, top + size * 0.4, z, size * 0.18, size * 0.8, size * 0.18, "wood")
			box(boxes, "prop", x, top + size, z, size * 0.9, size * 0.9, size * 0.9, "leaf", "ball")
		end
	end
	if not kit then
		return
	end
	CityKit.kerbs(boxes, minX, minZ, b, gy + 0.55, kit.kerb)
	local propsFrom = #c.props + 1
	local r = f.radius + 6
	for _, s in { { 0, -1, 180 }, { 0, 1, 0 }, { -1, 0, 90 }, { 1, 0, -90 } } do
		-- benches either side of each path, facing the fountain, and a flower tub at the path's end
		for _, side in { -1, 1 } do
			local x = bcx + s[1] * r + (if s[1] == 0 then side * 7.5 else 0)
			local z = bcz + s[2] * r + (if s[2] == 0 then side * 7.5 else 0)
			CityKit.put(c.props, "Bench", x, top, z, s[3])
			local ex = bcx + s[1] * (b / 2 - 6) + (if s[1] == 0 then side * 7 else 0)
			local ez = bcz + s[2] * (b / 2 - 6) + (if s[2] == 0 then side * 7 else 0)
			CityKit.put(c.props, "FlowerTub", ex, top, ez, 0)
		end
	end
	for _, q in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		CityKit.put(c.props, "Bush", bcx + q[1] * (b / 2 - 9), top, bcz + q[2] * 9, 0)
		CityKit.put(c.props, "Bush", bcx + q[1] * 9, top, bcz + q[2] * (b / 2 - 9), 0)
		CityKit.put(c.props, "StreetLamp", bcx + q[1] * (b / 2 - 3), top, bcz + q[2] * (b / 2 - 3), 0)
	end
	if kit.play then
		-- a food cart (pt-city, 2026-11-19), in a tint by hash
		local cart = CityKit.put(c.props, "FoodCart", bcx + f.radius + 14, top, bcz - f.radius - 14, 90)
		cart.tint = CityKit.pick(kit, kit.play.tints, cart.x, cart.z, kit.play.foodCart.salt)
	end
	local clearOf = {}
	table.move(boxes, parkFirst, #boxes, 1, clearOf)
	CityKit.keep(kit, c.props, propsFrom, CityKit.obstacles(clearOf, top))
end

-- Uptown's landmark skyscraper (Config.City.uptown.landmark, PLACEHOLDER NAME): the city's tallest, alone on
-- its block with a plaza round it: a square shaft (the wreckable box), two setbacks, a lit lantern and a spire
local function landmarkBlock(c: Ctx, minX: number, minZ: number)
	local boxes, t, kit, gy = c.boxes, c.t, c.kit, c.gy
	local L = t.landmark
	local bcx, bcz = minX + t.block / 2, minZ + t.block / 2
	local blockFirst = #boxes + 1
	local propsFrom = #c.props + 1
	box(boxes, "sidewalk", bcx, gy + 0.5, bcz, t.block, 0.8, t.block, "sidewalk")
	if kit then
		boxes[#boxes].kit = kit.ground[c.group].sidewalk
		dressBlock(boxes, c.props, t, kit, minX, minZ, gy, c.style)
	end
	local size = L.size
	local shaft = math.floor(L.height * 0.62 / 4) * 4
	local top = gy + 0.9 + shaft
	local first = #boxes + 1
	box(boxes, "building", bcx, gy + 0.9 + shaft / 2, bcz, size, shaft, size, "upSky")
	bands(c, bcx, bcz, size, size, shaft)
	local body = boxes[first]
	if kit then
		local front = CityKit.front(kit, body, kit.fronts[c.group], "tower") or "Prism"
		for k = first + 1, #boxes do
			boxes[k].plain = front
		end
		box(
			boxes,
			"ledge",
			bcx,
			top - kit.cornice / 2 + 0.05,
			bcz,
			size + 1,
			kit.cornice,
			size + 1,
			"cornice"
		)
		boxes[#boxes].dress = true
	end
	local rise = gy + 0.9 + L.height - top
	local function tier(f: number, h: number, y0: number): number
		crownBox(c, "tier", bcx, y0, bcz, size * f, h, size * f, body.color)
		local b = boxes[#boxes]
		b.kit, b.tint = body.kit, body.tint
		if kit and body.kit then
			crownBox(
				c,
				"ledge",
				bcx,
				y0 + h - kit.cornice + 0.05,
				bcz,
				size * f + 1,
				kit.cornice,
				size * f + 1,
				"cornice"
			)
			boxes[#boxes].dress = true
		end
		return y0 + h
	end
	local y = tier(0.78, math.floor(rise * 0.34), top)
	y = tier(0.56, math.floor(rise * 0.21), y)
	local lantern = math.floor(rise * 0.08)
	crownBox(c, "glow", bcx, y, bcz, size * 0.36, lantern, size * 0.36, "beaconGlow")
	y += lantern
	crownBox(c, "tier", bcx, y, bcz, 3, gy + 0.9 + L.height - y, 3, "steel", "cylinder")
	if kit and kit.play then
		-- perches up its shaft (pt-city): no street faces (its plaza is round it), no roof units (the crown)
		CityPlay.dress(boxes, kit, {
			x = bcx,
			z = bcz,
			sx = size,
			sz = size,
			base = gy + 0.9,
			top = top,
			flat = false,
			faces = {},
		})
	end
	local grp = c.prefix .. (#c.buildings + 1)
	for k = first, #boxes do
		boxes[k].grp = grp
	end
	table.insert(c.buildings, {
		x = bcx,
		z = bcz,
		sx = size,
		sz = size,
		h = shaft + 0.9,
		grp = grp,
		base = gy + 0.9,
		grown = true,
		crown = "landmark",
		peak = gy + 0.9 + L.height,
	})
	table.insert(c.droneSpots, { x = bcx, y = top + 18, z = bcz })
	if kit then
		-- benches and flower tubs round the tower's plaza
		local top0 = gy + 0.9
		local r = size / 2 + 10
		for _, sd in { { 0, -1, 180 }, { 0, 1, 0 }, { -1, 0, 90 }, { 1, 0, -90 } } do
			for _, along in { -12, 12 } do
				local x = bcx + sd[1] * r + (if sd[1] == 0 then along else 0)
				local z = bcz + sd[2] * r + (if sd[2] == 0 then along else 0)
				CityKit.put(c.props, "Bench", x, top0, z, sd[3] + 180)
			end
		end
		for _, q in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			CityKit.put(c.props, "FlowerTub", bcx + q[1] * r, top0, bcz + q[2] * r, 0)
		end
		if kit.play then
			-- a food cart (pt-city, 2026-11-19), in a tint by hash
			local cart = CityKit.put(c.props, "FoodCart", bcx - r + 8, top0, bcz + r + 4, 180)
			cart.tint = CityKit.pick(kit, kit.play.tints, cart.x, cart.z, kit.play.foodCart.salt)
		end
		local clearOf = {}
		table.move(boxes, blockFirst, #boxes, 1, clearOf)
		CityKit.keep(kit, c.props, propsFrom, CityKit.obstacles(clearOf, top0))
	end
	return { x = bcx, z = bcz, size = size, peak = gy + 0.9 + L.height }
end

export type District = {
	boxes: { Box },
	buildings: { any }, -- like Layout.buildings
	droneSpots: { { x: number, y: number, z: number } },
	props: { Prop },
	park: { x: number, z: number, size: number },
	landmark: { x: number, z: number, size: number, peak: number }, -- the landmark skyscraper
	parts: number,
}

-- Uptown (PLACEHOLDER NAME, 2026-11-17): the second Downtown-style district (Config.City.uptown), a grid like
-- Downtown's grown blocks with its own block size, heights, sunset colours, roof gardens and flower tubs, and
-- a green with a fountain. Each block is its own seeded stream, so it is the same every week and every size.
function CityLayout.uptown(cityCfg: any): District
	local d = cityCfg.districts.Uptown
	local t = cityCfg.uptown
	local gy = cityCfg.ground.y
	local kit = cityCfg.kit
	local boxes: { Box } = {}
	local c: Ctx = {
		boxes = boxes,
		buildings = {},
		props = {},
		droneSpots = {},
		safehouseSpots = {},
		reserved = {},
		t = t,
		kit = kit,
		gy = gy,
		group = "Uptown",
		colors = t.colors,
		prefix = "U",
		style = UPTOWN_STYLE,
		grown = true,
		skyline = cityCfg.skyline,
	}
	local w, h = d.maxX - d.minX, d.maxZ - d.minZ
	box(boxes, "road", (d.minX + d.maxX) / 2, gy + 0.1, (d.minZ + d.maxZ) / 2, w, 0.2, h, "road")
	if kit then
		boxes[#boxes].kit = kit.ground.Uptown.road
	end
	local pitch = t.block + t.street
	local nx, nz = math.floor(w / pitch), math.floor(h / pitch)
	local x0 = d.minX + (w - nx * pitch) / 2 + t.street / 2
	local z0 = d.minZ + (h - nz * pitch) / 2 + t.street / 2
	local park = { x = 0, z = 0, size = t.block }
	local landmark = { x = 0, z = 0, size = 0, peak = gy }
	-- block (bx, bz) counts from the 2026-11-17 square's north-west block (1, 1); the 2026-11-19 column west and
	-- row north (uptown.grow) are below 1. The old 4 x 4 is built first in its old order (same groups, same ids),
	-- then the new blocks with their own tower chance (uptown.towers)
	local gw = if t.grow then t.grow.west else 0
	local gn = if t.grow then t.grow.north else 0
	local firstX, firstZ = 1 - gw, 1 - gn
	local lastX, lastZ = nx - gw, nz - gn
	for pass = 1, 2 do
		for bx = firstX, lastX do
			for bz = firstZ, lastZ do
				if (bx >= 1 and bz >= 1) ~= (pass == 1) then
					continue
				end
				c.towerChance = if pass == 2 and t.towers then t.towers.chance else nil
				local minX, minZ = x0 + (bx - firstX) * pitch, z0 + (bz - firstZ) * pitch
				if kit then
					dashes(boxes, t, kit, minX, minZ, gy, bx < lastX, bz < lastZ)
				end
				if bx == t.park[1] and bz == t.park[2] then
					parkBlock(c, minX, minZ)
					park = { x = minX + t.block / 2, z = minZ + t.block / 2, size = t.block }
				elseif t.landmark and bx == t.landmark.block[1] and bz == t.landmark.block[2] then
					landmark = landmarkBlock(c, minX, minZ)
				else
					lotBlock(c, Rng.new(Rng.hash(t.seed, bx, bz, 5)), bx, bz, minX, minZ)
				end
			end
		end
	end
	c.towerChance = nil
	local parts = 0
	for _, b in boxes do
		if b.kind ~= "spawn" then
			parts += 1
		end
	end
	return {
		boxes = boxes,
		buildings = c.buildings,
		droneSpots = c.droneSpots,
		props = c.props,
		park = park,
		landmark = landmark,
		parts = parts,
	}
end

-- Roof or ground height at (x, z); 0 outside the hub
function CityLayout.heightAt(layout: Layout, x: number, z: number): number
	local g = layout.grid
	local ix = math.floor((x - g.minX) / g.cell)
	local iz = math.floor((z - g.minZ) / g.cell)
	if ix < 0 or iz < 0 or ix >= g.n or iz >= g.n then
		return 0
	end
	return g.tops[iz * g.n + ix + 1]
end

return CityLayout
