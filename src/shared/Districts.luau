--!strict
-- Districts: the two hub districts after Downtown (spec: Map layout > Hub districts), as plain boxes with a
-- fixed seed each, so the hub never changes with the weekly seed.
-- * The Docks (800 x 500): warehouses, container stacks, gantry cranes over the harbour basin and the Foundry,
--   the Syndicate's HQ.
-- * Old Town (600 x 600): small blocks on 14-stud streets, pitched roofs and the Clock Tower on Clock Square.
-- clear: safehouse pads; nothing is built on them.
-- PLACEHOLDER ART: simple parts until the kit pass (M5). With Config.City.kit (overhaul step 5) both are dressed
-- after their seeded layout (no random draws change): the Docks get quay concrete, corrugated warehouses and
-- dock brick, ribbed containers, a safety line, mooring bollards, floodlight masts, two jib cranes and crate
-- piles; Old Town gets cobbles, flagstones and kerbs, old brick, plaster and timber fronts, tiled roofs,
-- lantern posts, flower tubs, cafe tables and benches.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")

local Districts = {}

type Box = BoxKit.Box

export type Building = { grp: string, x: number, z: number, sx: number, sz: number, h: number, base: number }

export type District = {
	boxes: { Box },
	buildings: { Building }, -- the wreckable ones (the Foundry and the Clock Tower are not)
	spots: { [string]: { x: number, y: number, z: number } }, -- named high points (crane, clock, foundry)
	parts: number,
	props: { CityKit.Prop }, -- the city kit's street props (built by each device: CityProps)
}

local box = BoxKit.box

-- Tag the boxes from `first` on as one building and list it
local function group(boxes: { Box }, buildings: { Building }, prefix: string, first: number, b: any)
	local grp = prefix .. (#buildings + 1)
	for k = first, #boxes do
		boxes[k].grp = grp
	end
	table.insert(buildings, { grp = grp, x = b.x, z = b.z, sx = b.sx, sz = b.sz, h = b.h, base = b.base })
end

local CONTAINER_COLORS = { "containerA", "containerB", "containerC", "containerD" }
local OLD_BODY = { "brick", "sand", "white", "concrete", "brick" }
local OLD_ROOF = { "roofRed", "roofBlue", "roof", "roofRed" }

-- Safehouse pads as keep-out squares for props
local function padRects(clear: { BoxKit.Circle }): { CityKit.Rect }
	local out = {}
	for _, c in clear do
		table.insert(out, { x0 = c.x - c.r, z0 = c.z - c.r, x1 = c.x + c.r, z1 = c.z + c.r })
	end
	return out
end

-- The Docks' dressing (after the seeded layout): a yellow safety line and mooring bollards along the basin,
-- floodlight masts, two jib cranes on the west quay, and crate piles by the warehouse doors and between the
-- container stacks. The truck lane between the warehouses and the Foundry stays clear.
local function dressDocks(cityCfg: any, boxes: { Box }, props: { CityKit.Prop }, clear: { BoxKit.Circle })
	local kit = cityCfg.kit
	local c = cityCfg.docks
	local b = c.basin
	local gy = cityCfg.ground.y
	local top = gy + 0.6
	-- the safety line 3 studs from the water on the north and west quays
	box(
		boxes,
		"mark",
		(b.minX - 3 + b.maxX) / 2,
		top + 0.02,
		b.minZ - 3,
		b.maxX - b.minX + 3.6,
		0.04,
		0.6,
		"line"
	)
	boxes[#boxes].dress = true
	box(boxes, "mark", b.minX - 3, top + 0.02, (b.minZ + b.maxZ) / 2, 0.6, 0.04, b.maxZ - b.minZ, "line")
	boxes[#boxes].dress = true
	local north = { x = (b.minX + b.maxX) / 2, z = b.minZ, ax = 1, az = 0, ox = 0, oz = 1, ry = 180 }
	local west = { x = b.minX, z = (b.minZ + b.maxZ) / 2, ax = 0, az = 1, ox = 1, oz = 0, ry = -90 }
	local function along(side: any, len: number, every: number, name: string, inset: number, skip: number?)
		local n = math.floor((len - 16) / every)
		for k = 0, n do
			if not skip or k % skip ~= 0 then
				CityKit.onSide(props, name, side, -len / 2 + 8 + k * every, inset, top)
			end
		end
	end
	local first = #props + 1
	-- jib cranes first (the biggest), then masts and bollards around them
	local jz = b.maxZ - b.minZ
	CityKit.onSide(props, "JibCrane", west, -jz / 2 + 70, 3.8, top)
	CityKit.onSide(props, "JibCrane", west, -jz / 2 + 160, 3.8, top)
	along(north, b.maxX - b.minX, 72, "DockLight", 6.5)
	along(west, jz, 72, "DockLight", 6.5)
	along(north, b.maxX - b.minX, 24, "MooringBollard", 1.6)
	along(west, jz, 24, "MooringBollard", 1.6)
	-- crate piles: a pallet, a crate, maybe barrels
	local function pile(x: number, z: number, ry: number)
		local r = CityKit.roll(kit, x, z, 31)
		local turn = math.rad(ry)
		local cs, sn = math.cos(turn), math.sin(turn)
		local function at(name: string, lx: number, lz: number)
			CityKit.put(props, name, x + lx * cs + lz * sn, top, z - lx * sn + lz * cs, ry)
		end
		at("Pallet", 0, 0)
		at("Crate", 3.7, 0)
		if r < 0.7 then
			at("Barrel", -3.3, 0.6)
		end
		if r < 0.35 then
			at("Barrel", -3.3, -1.6)
		end
		if r > 0.5 then
			at("Crate", 3.7, 3.4)
		end
	end
	local wh = c.warehouses
	local cw = (wh.maxX - wh.minX - wh.gap * (wh.cols - 1)) / wh.cols
	local cd = (wh.maxZ - wh.minZ - wh.gap * (wh.rows - 1)) / wh.rows
	for i = 1, wh.cols do
		for j = 1, wh.rows do
			local cx = wh.minX + (i - 1) * (cw + wh.gap) + cw / 2
			local cz = wh.minZ + (j - 1) * (cd + wh.gap) + cd / 2
			pile(cx + cw * 0.3, cz + cd / 2 + 3, 0)
		end
	end
	local ct = c.containers
	local pitchX = (ct.maxX - ct.minX) / ct.cols
	local pitchZ = (ct.maxZ - ct.minZ) / ct.rows
	for i = 1, ct.cols - 1 do
		for j = 1, ct.rows do
			local x = ct.minX + i * pitchX
			local z = ct.minZ + (j - 0.5) * pitchZ
			if CityKit.roll(kit, x, z, 33) < 0.45 then
				pile(x, z, 90)
			end
		end
	end
	-- keep clear of everything solid, the safehouse pads, the water and the truck lane
	local extra = padRects(clear)
	table.insert(extra, { x0 = b.minX, z0 = b.minZ, x1 = b.maxX, z1 = b.maxZ })
	local lane = c.lane
	table.insert(extra, { x0 = lane.minX, z0 = lane.minZ, x1 = lane.maxX, z1 = lane.maxZ })
	CityKit.keep(kit, props, first, CityKit.obstacles(boxes, top, extra))
	-- a second crate on some crates (stacked: it stands on the one below)
	for i = first, #props do
		local p = props[i]
		if p.name == "Crate" and p.y == top and CityKit.roll(kit, p.x, p.z, 35) < 0.4 then
			CityKit.put(props, "Crate", p.x, top + 3, p.z, p.ry + 90)
		end
	end
end

-- Old Town's dressing for one block: lantern posts on the corners, a flower tub on the east and west sides, and
-- by hash a bench on the north side or a cafe table on the south (the lot gap is a 4-stud strip)
local function dressOldBlock(
	kit: any,
	props: { CityKit.Prop },
	minX: number,
	minZ: number,
	size: number,
	top: number
)
	local sides = CityKit.sides(minX, minZ, size)
	local e = size / 2 - 1.3
	for _, si in { 1, 2 } do
		CityKit.onSide(props, "OldLamp", sides[si], -e, 1.3, top)
		CityKit.onSide(props, "OldLamp", sides[si], e, 1.3, top)
	end
	for _, si in { 3, 4 } do
		if CityKit.roll(kit, sides[si].x, sides[si].z, 41) < 0.75 then
			CityKit.onSide(props, "FlowerTub", sides[si], 0, 1.9, top)
		end
	end
	if CityKit.roll(kit, sides[1].x, sides[1].z, 42) < 0.4 then
		CityKit.onSide(props, "Bench", sides[1], 0, 1.6, top)
	end
	if CityKit.roll(kit, sides[2].x, sides[2].z, 43) < 0.35 then
		CityKit.onSide(props, "CafeSet", sides[2], 0, 2.0, top)
	end
end

-- Clock Square: lantern posts round the edge, benches facing the tower, flower tubs by the trees
local function dressSquare(
	kit: any,
	boxes: { Box },
	props: { CityKit.Prop },
	minX: number,
	minZ: number,
	size: number,
	top: number
)
	local first = #props + 1
	for _, side in CityKit.sides(minX, minZ, size) do
		for _, a in { -size / 4, size / 4 } do
			CityKit.onSide(props, "OldLamp", side, a, 2.0, top)
		end
		local bench = CityKit.onSide(props, "Bench", side, 0, 22, top)
		bench.ry += 180 -- facing the tower
		CityKit.onSide(props, "FlowerTub", side, -12, 22, top)
		CityKit.onSide(props, "FlowerTub", side, 12, 22, top)
	end
	CityKit.keep(kit, props, first, CityKit.obstacles(boxes, top))
end

function Districts.docks(cityCfg: any, clear: { BoxKit.Circle }): District
	local d = cityCfg.districts.Docks
	local c = cityCfg.docks
	local rng = Rng.new(c.seed)
	local boxes: { Box } = {}
	local buildings: { Building } = {}
	local spots = {}
	local gy = cityCfg.ground.y
	local kit = cityCfg.kit
	-- the quay: a concrete slab around the harbour basin (the basin is Terrain water dug down to its floor:
	-- Config.Deep, DeepLayout)
	local b = c.basin
	for _, r in
		BoxKit.around(d.minX, d.minZ, d.maxX, d.maxZ, { x0 = b.minX, z0 = b.minZ, x1 = b.maxX, z1 = b.maxZ })
	do
		box(
			boxes,
			"plaza",
			(r.x0 + r.x1) / 2,
			gy + 0.3,
			(r.z0 + r.z1) / 2,
			r.x1 - r.x0,
			0.6,
			r.z1 - r.z0,
			"concrete"
		)
		if kit then
			boxes[#boxes].kit = kit.ground.Docks.quay
		end
	end
	local top = gy + 0.6

	-- warehouses in a grid: body, flat roof and a big door (3 parts each)
	local wh = c.warehouses
	local cw = (wh.maxX - wh.minX - wh.gap * (wh.cols - 1)) / wh.cols
	local cd = (wh.maxZ - wh.minZ - wh.gap * (wh.rows - 1)) / wh.rows
	for i = 1, wh.cols do
		for j = 1, wh.rows do
			local cx = wh.minX + (i - 1) * (cw + wh.gap) + cw / 2
			local cz = wh.minZ + (j - 1) * (cd + wh.gap) + cd / 2
			local height = math.floor(rng:range(c.warehouseHeight.min, c.warehouseHeight.max) / 2) * 2
			local color = if rng:chance(0.5) then "steel" else "brick"
			if not BoxKit.hitsAny(clear, cx, cz, cw, cd) then
				local first = #boxes + 1
				box(boxes, "building", cx, top + height / 2, cz, cw, height, cd, color)
				if kit then
					CityKit.front(kit, boxes[#boxes], kit.fronts.Docks, color)
				end
				box(boxes, "ledge", cx, top + height + 1, cz, cw + 1, 2, cd + 1, "roof")
				box(
					boxes,
					"prop",
					cx,
					top + 9,
					cz + cd / 2 + 0.2,
					cw * 0.4,
					18,
					0.4,
					"slate",
					{ ghost = true }
				)
				if kit then
					boxes[#boxes].kit = "Container" -- a ribbed roller door in its own colour
				end
				group(
					boxes,
					buildings,
					"W",
					first,
					{ x = cx, z = cz, sx = cw, sz = cd, h = height, base = top }
				)
			end
		end
	end

	-- container stacks: 1 to 3 high, random colours
	local ct = c.containers
	local size = c.container
	local pitchX = (ct.maxX - ct.minX) / ct.cols
	local pitchZ = (ct.maxZ - ct.minZ) / ct.rows
	for i = 1, ct.cols do
		for j = 1, ct.rows do
			local cx = ct.minX + (i - 0.5) * pitchX
			local cz = ct.minZ + (j - 0.5) * pitchZ
			local stack = rng:int(0, ct.maxStack)
			local colors = {}
			for k = 1, stack do
				colors[k] = CONTAINER_COLORS[rng:int(1, #CONTAINER_COLORS)]
			end
			if stack > 0 and not BoxKit.hitsAny(clear, cx, cz, size.sx * 2, size.sz) then
				for k = 1, stack do
					box(
						boxes,
						"prop",
						cx,
						top + (k - 0.5) * size.sy,
						cz,
						size.sx * 2,
						size.sy,
						size.sz,
						colors[k]
					)
					if kit then
						boxes[#boxes].kit = "Container" -- ribbed, in its own colour
					end
				end
			end
		end
	end

	-- gantry cranes along the basin edge: 2 legs, a top beam and a boom over the water (4 parts)
	local cr = c.cranes
	for k = 1, cr.count do
		local cx = cr.minX + (k - 1) * (cr.maxX - cr.minX) / math.max(1, cr.count - 1)
		local height = cr.height + (k - 1) * 6
		box(boxes, "prop", cx - cr.span / 2, top + height / 2, cr.z, 4, height, 4, "containerC")
		box(boxes, "prop", cx + cr.span / 2, top + height / 2, cr.z, 4, height, 4, "containerC")
		box(boxes, "prop", cx, top + height + 2, cr.z, cr.span + 6, 6, 6, "containerC")
		box(boxes, "prop", cx, top + height - 4, cr.z + cr.boom / 2, 4, 4, cr.boom, "containerC")
		if k == 1 then
			spots.crane = { x = cx, y = top + height + 5, z = cr.z }
		end
	end

	-- the Foundry: the Syndicate HQ (body, roof, a red glow band, chimneys)
	local f = c.foundry
	local fx, fz = (f.minX + f.maxX) / 2, (f.minZ + f.maxZ) / 2
	local fw, fd = f.maxX - f.minX, f.maxZ - f.minZ
	box(boxes, "building", fx, top + f.height / 2, fz, fw, f.height, fd, "foundry")
	if kit then
		boxes[#boxes].kit = kit.fronts.Docks.foundry[1] -- dark corrugated metal, its own colour
	end
	box(boxes, "ledge", fx, top + f.height + 1.5, fz, fw + 2, 3, fd + 2, "roof")
	box(boxes, "band", fx, top + f.height * 0.6, fz, fw + 0.6, 4, fd + 0.6, "foundryGlow")
	box(boxes, "band", fx, top + 14, fz - fd / 2 - 0.2, fw * 0.3, 28, 0.4, "foundryGlow")
	for k = 1, f.chimneys do
		local x = f.minX + fw * (k / (f.chimneys + 1))
		box(
			boxes,
			"prop",
			x,
			top + f.chimneyHeight / 2,
			fz + fd * 0.2,
			16,
			f.chimneyHeight,
			16,
			"foundry",
			{ shape = "cylinder" }
		)
		box(
			boxes,
			"glow",
			x,
			top + f.chimneyHeight + 1,
			fz + fd * 0.2,
			12,
			2,
			12,
			"foundryGlow",
			{ shape = "cylinder" }
		)
	end
	spots.foundry = { x = fx, y = top + f.height + 3, z = fz }
	spots.foundryDoor = { x = fx, y = top + 3, z = f.minZ - 8 }

	local props: { CityKit.Prop } = {}
	if kit then
		dressDocks(cityCfg, boxes, props, clear)
	end
	return { boxes = boxes, buildings = buildings, spots = spots, parts = #boxes, props = props }
end

function Districts.oldTown(cityCfg: any, clear: { BoxKit.Circle }): District
	local d = cityCfg.districts.OldTown
	local t = cityCfg.oldTown
	local rng = Rng.new(t.seed)
	local boxes: { Box } = {}
	local buildings: { Building } = {}
	local spots = {}
	local gy = cityCfg.ground.y
	local kit = cityCfg.kit
	local props: { CityKit.Prop } = {}
	local w, h = d.maxX - d.minX, d.maxZ - d.minZ
	-- cobbled street base
	box(boxes, "road", (d.minX + d.maxX) / 2, gy + 0.1, (d.minZ + d.maxZ) / 2, w, 0.2, h, "slate")
	if kit then
		boxes[#boxes].kit = kit.ground.OldTown.road
	end
	local pitch = t.block + t.street
	local nx, nz = math.floor(w / pitch), math.floor(h / pitch)
	local sq0, sq1 = t.square[1], t.square[2]
	for bx = 1, nx do
		for bz = 1, nz do
			local minX = d.minX + t.street / 2 + (bx - 1) * pitch
			local minZ = d.minZ + t.street / 2 + (bz - 1) * pitch
			local inSquare = bx >= sq0 and bx <= sq1 and bz >= sq0 and bz <= sq1
			if inSquare then
				if bx == sq0 and bz == sq0 then
					-- Clock Square spans the 2 x 2 blocks and the streets between them
					local size = 2 * t.block + t.street
					local cx, cz = minX + size / 2, minZ + size / 2
					box(boxes, "plaza", cx, gy + 0.4, cz, size, 0.8, size, "sand")
					if kit then
						boxes[#boxes].kit = kit.ground.OldTown.square
					end
					local k = t.clock
					local top = gy + 0.8
					box(boxes, "building", cx, top + k.height / 2, cz, k.base, k.height, k.base, "brick")
					if kit then
						CityKit.front(kit, boxes[#boxes], kit.fronts.OldTown, "brick")
					end
					local faceY = top + k.height - 14
					for _, dir in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
						box(
							boxes,
							"band",
							cx + dir[1] * (k.base / 2 + 0.3),
							faceY,
							cz + dir[2] * (k.base / 2 + 0.3),
							if dir[1] == 0 then 16 else 0.6,
							16,
							if dir[1] == 0 then 0.6 else 16,
							"white"
						)
					end
					BoxKit.pitchedRoof(
						boxes,
						cx,
						top + k.height,
						cz,
						k.base + 2,
						k.base + 2,
						k.spire,
						"roofBlue"
					)
					spots.clock = { x = cx, y = top + k.height + k.spire + 2, z = cz }
					for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
						BoxKit.tree(boxes, cx + c[1] * (size / 2 - 14), top, cz + c[2] * (size / 2 - 14), 10)
					end
					if kit then
						dressSquare(kit, boxes, props, minX, minZ, size, top)
					end
				end
				continue
			end
			box(
				boxes,
				"sidewalk",
				minX + t.block / 2,
				gy + 0.4,
				minZ + t.block / 2,
				t.block,
				0.8,
				t.block,
				"sidewalk"
			)
			local blockFirst = #boxes
			local propsFrom = #props + 1
			if kit then
				boxes[#boxes].kit = kit.ground.OldTown.sidewalk
				CityKit.kerbs(boxes, minX, minZ, t.block, gy + 0.45, kit.kerb)
				dressOldBlock(kit, props, minX, minZ, t.block, gy + 0.8)
			end
			local lot = (t.block - t.lotGap * (t.lotsPerSide + 1)) / t.lotsPerSide
			for lx = 1, t.lotsPerSide do
				for lz = 1, t.lotsPerSide do
					local cx = minX + t.lotGap + (lx - 1) * (lot + t.lotGap) + lot / 2
					local cz = minZ + t.lotGap + (lz - 1) * (lot + t.lotGap) + lot / 2
					local height = math.floor(rng:range(t.height.min, t.height.max) / 2) * 2
					local body = OLD_BODY[rng:int(1, #OLD_BODY)]
					local roof = OLD_ROOF[rng:int(1, #OLD_ROOF)]
					local pitched = rng:chance(t.pitchedChance)
					local sx = lot - rng:range(0, 3)
					local sz = lot - rng:range(0, 3)
					if BoxKit.hitsAny(clear, cx, cz, sx, sz) then
						continue
					end
					local top = gy + 0.8
					local first = #boxes + 1
					box(boxes, "building", cx, top + height / 2, cz, sx, height, sz, body)
					-- one window band per floor above the shop front (PLACEHOLDER ART; with the kit, only until
					-- the building's front texture is in)
					local front = if kit
						then CityKit.front(kit, boxes[first], kit.fronts.OldTown, body)
						else nil
					local y = 12
					while y < height - 4 do
						box(boxes, "band", cx, top + y, cz, sx + 0.4, 2.5, sz + 0.4, "window")
						boxes[#boxes].plain = front
						y += 11
					end
					if pitched then
						local r0 = #boxes + 1
						BoxKit.pitchedRoof(boxes, cx, top + height, cz, sx, sz, sz * 0.4, roof, lx == lz)
						if kit then
							for k = r0, #boxes do
								CityKit.roof(kit, boxes[k])
							end
						end
					else
						box(boxes, "ledge", cx, top + height + 1, cz, sx + 1, 2, sz + 1, "roof")
					end
					group(
						boxes,
						buildings,
						"O",
						first,
						{ x = cx, z = cz, sx = sx, sz = sz, h = height, base = top }
					)
				end
			end
			if kit then
				-- the block's props stay clear of its houses, safehouse pads and each other
				local clearOf = {}
				table.move(boxes, blockFirst, #boxes, 1, clearOf)
				CityKit.keep(kit, props, propsFrom, CityKit.obstacles(clearOf, gy + 0.8, padRects(clear)))
			end
		end
	end
	return { boxes = boxes, buildings = buildings, spots = spots, parts = #boxes, props = props }
end

return Districts
