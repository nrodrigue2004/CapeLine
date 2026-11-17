--!strict
-- CityLayout: the Downtown greybox as plain boxes (spec: Map layout; M1 "greybox Downtown"; WorldMap adds the
-- rest of the map in M4 and has the whole-map heightAt). Pure and
-- seeded, so the server builds the same city every time, the Lune tests can check part counts and heights,
-- and the drone AI can ask how tall the city is anywhere (heightAt) without raycasts.
-- PLACEHOLDER ART: grey boxes, window bands and rooftop props until the kit pass (M5). With Config.City.kit
-- (overhaul step 5) every block is dressed: textured fronts, paving, kerbs, lane dashes, cornices and props.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")

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
}

-- A street prop (Config.City.kit.props; Art.Street meshes, built by each device: CityProps)
export type Prop = CityKit.Prop

export type Layout = {
	boxes: { Box },
	buildings: { { x: number, z: number, sx: number, sz: number, h: number, grp: string?, base: number? } },
	spawns: { { x: number, y: number, z: number } },
	droneSpots: { { x: number, y: number, z: number } },
	beacon: { x: number, z: number, h: number },
	safehouseSpots: { [number]: { x: number, z: number } }, -- reserved lots (Config.World.safehouses)
	grid: { cell: number, minX: number, minZ: number, n: number, tops: { number } },
	parts: number,
	props: { Prop },
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

-- The city kit's street dressing for one Downtown block (no random draws, so the layout is unchanged; picks are
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
	gy: number
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
				put("Planter", side, along + step / 2, kw + 2.1)
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

-- worldCfg (optional): Config.World, whose Downtown safehouses take a reserved lot each. The random draws
-- for a reserved lot still happen, so the rest of Downtown stays the same with or without them.
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
	local rng = Rng.new(t.seed)
	local boxes: { Box } = {}
	local buildings = {}
	local spawns = {}
	local droneSpots = {}
	local props: { Prop } = {}
	local gy = cityCfg.ground.y
	local kit = cityCfg.kit

	-- Downtown asphalt base (the kit's road texture covers it all: it is one part)
	local w, h = d.maxX - d.minX, d.maxZ - d.minZ
	local cx, cz = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
	box(boxes, "road", cx, gy + 0.1, cz, w, 0.2, h, "road")
	if kit then
		boxes[#boxes].kit = "Asphalt"
	end

	local pitch = t.block + t.street
	local nx = math.floor(w / pitch)
	local nz = math.floor(h / pitch)
	local midX, midZ = math.ceil(nx / 2), math.ceil(nz / 2)
	local beacon = { x = 0, z = 0, h = t.beacon.height }

	for bx = 1, nx do
		for bz = 1, nz do
			local minX = d.minX + t.street / 2 + (bx - 1) * pitch
			local minZ = d.minZ + t.street / 2 + (bz - 1) * pitch
			local bcx, bcz = minX + t.block / 2, minZ + t.block / 2
			if kit then
				dashes(boxes, t, kit, minX, minZ, gy, bx < nx, bz < nz)
			end
			if bx == midX and bz == midZ then
				-- the plaza and Beacon Tower (League HQ): where new heroes land
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
				for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
					table.insert(spawns, { x = bcx + c[1] * off, y = gy + 4, z = bcz + c[2] * off })
				end
			else
				local isKit = kit ~= nil
				local blockFirst = #boxes + 1
				local propsFrom = #props + 1
				box(boxes, "sidewalk", bcx, gy + 0.5, bcz, t.block, 0.8, t.block, "sidewalk")
				if isKit then
					boxes[#boxes].kit = kit.ground.Downtown.sidewalk
					dressBlock(boxes, props, t, kit, minX, minZ, gy)
				end
				local inner = t.block - 2 * t.sidewalk
				local lot = (inner - t.lotGap * (t.lotsPerSide - 1)) / t.lotsPerSide
				for lx = 1, t.lotsPerSide do
					for lz = 1, t.lotsPerSide do
						local lcx = minX + t.sidewalk + (lx - 1) * (lot + t.lotGap) + lot / 2
						local lcz = minZ + t.sidewalk + (lz - 1) * (lot + t.lotGap) + lot / 2
						local tall = rng:chance(t.height.towerChance)
						local height = if tall
							then rng:range(t.height.towerMin, t.height.towerMax)
							else rng:range(t.height.min, t.height.max)
						height = math.floor(height / 4) * 4
						local sx = lot - rng:range(0, 6)
						local sz = lot - rng:range(0, 6)
						local color = BODY_COLORS[rng:int(1, #BODY_COLORS)]
						local reservedId = reserved[string.format("%d,%d,%d,%d", bx, bz, lx, lz)]
						local hasLedge = rng:chance(t.rooftop.ledgeChance)
						local hasTank = rng:chance(t.rooftop.waterTowerChance)
						local hasAntenna = rng:chance(t.rooftop.antennaChance)
						if reservedId then
							safehouseSpots[reservedId] = { x = lcx, z = lcz }
							continue
						end
						local first = #boxes + 1
						local top = gy + 0.9 + height
						box(boxes, "building", lcx, gy + 0.9 + height / 2, lcz, sx, height, sz, color)
						-- window bands, one wrap-around part every 12 studs (PLACEHOLDER ART); on a kit block they
						-- show only until the kit textures are in, whose fronts have the windows
						local y = 10
						while y < height - 6 do
							box(boxes, "band", lcx, gy + 0.9 + y, lcz, sx + 0.4, 3, sz + 0.4, "window")
							y += 12
						end
						if isKit then
							-- a kit building: its front has the windows in it (one storey a tile; picked by hash
							-- from its colour's fronts), its bands show only until that texture is in, and a
							-- roof cornice caps it
							local front = CityKit.front(
								kit,
								boxes[first],
								kit.fronts.Downtown,
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
						-- rooftop: a ledge you can land on and a few props
						if hasLedge then
							box(boxes, "ledge", lcx, top + 1, lcz - sz / 2 + 0.75, sx, 2, 1.5, "roof")
							box(boxes, "ledge", lcx, top + 1, lcz + sz / 2 - 0.75, sx, 2, 1.5, "roof")
						end
						if hasTank then
							box(
								boxes,
								"prop",
								lcx + sx / 4,
								top + 6,
								lcz + sz / 4,
								10,
								12,
								10,
								"brick",
								"cylinder"
							)
						end
						if hasAntenna then
							box(boxes, "prop", lcx - sx / 4, top + 10, lcz - sz / 4, 1, 20, 1, "steel")
						end
						local grp = "D" .. (#buildings + 1)
						for k = first, #boxes do
							boxes[k].grp = grp
						end
						table.insert(buildings, {
							x = lcx,
							z = lcz,
							sx = sx,
							sz = sz,
							h = height + 0.9,
							grp = grp,
							base = gy + 0.9,
						})
						table.insert(droneSpots, { x = lcx, y = top + 18, z = lcz })
					end
				end
				if isKit then
					-- the block's props stay clear of its buildings and of each other
					local clearOf = {}
					table.move(boxes, blockFirst, #boxes, 1, clearOf)
					CityKit.keep(kit, props, propsFrom, CityKit.obstacles(clearOf, gy + 0.9))
				end
			end
		end
	end

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
