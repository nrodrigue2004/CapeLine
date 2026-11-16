--!strict
-- CityLayout: the Downtown greybox as plain boxes (spec: Map layout; M1 "greybox Downtown"; WorldMap adds the
-- rest of the map in M4 and has the whole-map heightAt). Pure and
-- seeded, so the server builds the same city every time, the Lune tests can check part counts and heights,
-- and the drone AI can ask how tall the city is anywhere (heightAt) without raycasts.
-- PLACEHOLDER ART: grey boxes, window bands and rooftop props until the kit pass (M5).

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

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
}

export type Layout = {
	boxes: { Box },
	buildings: { { x: number, z: number, sx: number, sz: number, h: number } },
	spawns: { { x: number, y: number, z: number } },
	droneSpots: { { x: number, y: number, z: number } },
	beacon: { x: number, z: number, h: number },
	safehouseSpots: { [number]: { x: number, z: number } }, -- reserved lots (Config.World.safehouses)
	grid: { cell: number, minX: number, minZ: number, n: number, tops: { number } },
	parts: number,
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
	local gy = cityCfg.ground.y

	-- Downtown asphalt base
	local w, h = d.maxX - d.minX, d.maxZ - d.minZ
	local cx, cz = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
	box(boxes, "road", cx, gy + 0.1, cz, w, 0.2, h, "road")

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
				box(boxes, "sidewalk", bcx, gy + 0.5, bcz, t.block, 0.8, t.block, "sidewalk")
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
						box(boxes, "building", lcx, gy + 0.9 + height / 2, lcz, sx, height, sz, color)
						-- window bands, one wrap-around part every 12 studs (PLACEHOLDER ART)
						local y = 10
						while y < height - 6 do
							box(boxes, "band", lcx, gy + 0.9 + y, lcz, sx + 0.4, 3, sz + 0.4, "window")
							y += 12
						end
						local top = gy + 0.9 + height
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
						table.insert(buildings, { x = lcx, z = lcz, sx = sx, sz = sz, h = height + 0.9 })
						table.insert(droneSpots, { x = lcx, y = top + 18, z = lcz })
					end
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
