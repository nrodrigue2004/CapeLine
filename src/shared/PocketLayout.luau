--!strict
-- PocketLayout: the story mission pockets (spec: Map layout > Mission pockets "7 sealed 400 x 400 areas at
-- y = 3,000 studs, used by story missions for parties of up to 4; no PvP, no world scheduler inside").
-- Pure: a pocket index and a layout name give the boxes to build and the named points the mission script
-- uses (spawn, stations, crates, the tower top and mast, the contact and the chase path, the three rooms
-- and the gauntlet, the arena and its pillars). A pocket is a floor with walls and a sky dome feel; parts
-- are made by CityBuilder's part maker.
-- PLACEHOLDER ART: every pocket is greybox parts until the art pass.

local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")

local PocketLayout = {}

export type Layout = {
	index: number,
	cx: number,
	cy: number,
	cz: number,
	boxes: { BoxKit.Box },
	points: { [string]: { number } }, -- name -> { x, y, z }
	lists: { [string]: { { number } } }, -- stations, crates, path, turrets, pillars, rooms
	floorY: number,
	cells: { [number]: { BoxKit.Box } }?, -- heights(): boxes by 25-stud cell
}

-- The centre of pocket i (1 to count)
function PocketLayout.centre(Config: any, i: number): (number, number, number)
	local p = Config.Story.pockets
	return p.firstX + (i - 1) * p.gap, p.y, p.z
end

-- Which pocket a point is in, or nil
function PocketLayout.at(Config: any, x: number, y: number, z: number): number?
	local p = Config.Story.pockets
	if y < p.y - 100 then
		return nil
	end
	for i = 1, p.count do
		local cx, _, cz = PocketLayout.centre(Config, i)
		if math.abs(x - cx) <= p.size / 2 + 20 and math.abs(z - cz) <= p.size / 2 + 20 then
			return i
		end
	end
	return nil
end

local function box(
	l: Layout,
	kind: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	opts: any?
)
	BoxKit.box(l.boxes, kind, l.cx + x, l.cy + y, l.cz + z, sx, sy, sz, color, opts)
end

local function point(l: Layout, name: string, x: number, y: number, z: number)
	l.points[name] = { l.cx + x, l.cy + y, l.cz + z }
end

local function add(l: Layout, list: string, x: number, y: number, z: number)
	l.lists[list] = l.lists[list] or {}
	table.insert(l.lists[list], { l.cx + x, l.cy + y, l.cz + z })
end

-- Floor and the 4 sealing walls (see-through glass so the sky shows)
local function shell(l: Layout, Config: any)
	local p = Config.Story.pockets
	local s = p.size
	box(l, "plaza", 0, -2, 0, s, 4, s, "sidewalk")
	for k = -1, 1, 2 do
		box(l, "ledge", k * s / 2, p.wall / 2, 0, 4, p.wall, s, "glass", { tag = "pocketWall" })
		box(l, "ledge", 0, p.wall / 2, k * s / 2, s, p.wall, 4, "glass", { tag = "pocketWall" })
	end
	point(l, "spawn", 0, 3, s / 2 - 30)
end

local BUILD: { [string]: (Layout, any) -> () } = {}

-- Mission 2: a Downtown block with 3 power stations (or shard crates) and cover
function BUILD.station(l: Layout)
	box(l, "road", 0, 0.1, 0, 30, 0.2, 380, "road")
	box(l, "road", 0, 0.1, 0, 380, 0.2, 30, "road")
	for _, q in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		box(l, "building", q[1] * 110, 25, q[2] * 110, 90, 50, 90, "concrete")
		box(l, "roof", q[1] * 110, 50.5, q[2] * 110, 92, 1, 92, "roof")
	end
	for i, s in { { -60, 0, -40 }, { 60, 0, -40 }, { 0, 0, -150 } } do
		add(l, "stations", s[1], 0.5, s[3])
		box(l, "prop", s[1], 4, s[3] - 8, 8, 8, 4, "steel")
		box(l, "glow", s[1], 6, s[3] - 10.2, 6, 3, 0.4, "beaconGlow")
		add(l, "crates", s[1] + (if i == 3 then 0 else 0), 0.5, s[3])
	end
	-- the branch after choice 1: a tram line (train) and roof hops (thief) along the east side
	point(l, "trainStart", -170, 0.2, 150)
	point(l, "trainDir", 1, 0, 300)
	for i = 0, 6 do
		add(l, "path", -150 + i * 50, 51.5, if i % 2 == 0 then 110 else -110)
	end
end

-- Mission 3: a signal tower with a spiral of ledges up to a top deck and its mast
function BUILD.tower(l: Layout)
	local h = 180
	box(l, "building", 0, h / 2, 0, 40, h, 40, "slate")
	for i = 0, 11 do
		local a = i * math.pi / 3
		local y = 15 + i * 14
		local r = 34
		box(l, "ledge", math.cos(a) * r, y, math.sin(a) * r, 18, 2, 18, "steel")
	end
	box(l, "roof", 0, h + 1, 0, 90, 2, 90, "roof")
	box(l, "prop", 0, h + 16, -30, 3, 30, 3, "steel")
	box(l, "glow", 0, h + 32, -30, 4, 4, 4, "beaconGlow")
	point(l, "top", 0, h + 3, 0)
	point(l, "mast", 0, h + 2.5, -24)
	point(l, "boss", 0, h + 3, 20)
end

-- Mission 4: rooftops of Old Town with the contact on one and a chase across the rest
function BUILD.rooftops(l: Layout)
	local roofs = {}
	for gx = -2, 2 do
		for gz = -2, 2 do
			local h = 30 + ((gx * 7 + gz * 13) % 5 + 5) % 5 * 10
			local x, z = gx * 70, gz * 70
			box(l, "building", x, h / 2, z, 50, h, 50, if (gx + gz) % 2 == 0 then "brick" else "concrete")
			box(l, "roof", x, h + 0.5, z, 52, 1, 52, if (gx + gz) % 2 == 0 then "roofRed" else "roofBlue")
			table.insert(roofs, { x, h + 1.5, z })
		end
	end
	local c = roofs[13] -- the middle roof
	point(l, "contact", c[1], c[2], c[3])
	-- the chase: a lap of the outer roofs
	for _, i in { 12, 7, 2, 3, 4, 9, 14, 19, 24, 23, 22 } do
		add(l, "path", roofs[i][1], roofs[i][2], roofs[i][3])
	end
	point(l, "spawn", 0, 3, 180)
end

-- Mission 5: three rooms under the Docks in a row, a gauntlet in the middle, the vault at the end
function BUILD.dungeon(l: Layout)
	local wallH = 30
	box(l, "building", 0, wallH + 1, 0, 400, 2, 400, "foundry", { tag = "ceiling" }) -- the ceiling (robots never stand on it)
	for k = -1, 1, 2 do
		box(l, "building", 0, wallH / 2, k * 60, 380, wallH, 4, "foundry")
	end
	-- dividing walls with doors between the 3 rooms
	for _, x in { -60, 60 } do
		box(l, "building", x, wallH / 2, -38, 4, wallH, 40, "foundry")
		box(l, "building", x, wallH / 2, 38, 4, wallH, 40, "foundry")
	end
	add(l, "rooms", -130, 0.5, 0)
	add(l, "rooms", 0, 0.5, 0)
	add(l, "rooms", 130, 0.5, 0)
	for i = 0, 3 do
		add(l, "turrets", -40 + i * 26, 0.5, if i % 2 == 0 then -45 else 45)
	end
	point(l, "gauntletEnd", 70, 3, 0)
	point(l, "boss", 150, 3, 0)
	box(l, "glow", 180, 8, 0, 4, 12, 12, "foundryGlow") -- the shard vault
	point(l, "spawn", -170, 3, 0)
end

-- Mission 6: the War-Frame arena with 6 pillars to hide behind
function BUILD.arena(l: Layout, Config: any)
	local w = Config.Story.warframe
	for _, p in w.pillars do
		box(
			l,
			"building",
			p[1],
			20,
			p[2],
			w.pillarRadius * 2,
			40,
			w.pillarRadius * 2,
			"slate",
			{ shape = "cylinder" }
		)
		add(l, "pillars", p[1], 0, p[2])
	end
	point(l, "boss", 0, 0.5, -20)
	point(l, "spawn", 0, 3, 170)
end

function PocketLayout.build(Config: any, index: number, layout: string): Layout
	local cx, cy, cz = PocketLayout.centre(Config, index)
	local l: Layout =
		{ index = index, cx = cx, cy = cy, cz = cz, boxes = {}, points = {}, lists = {}, floorY = cy }
	shell(l, Config)
	local fn = BUILD[layout]
	assert(fn, "unknown pocket layout " .. layout)
	fn(l, Config)
	return l
end

-- Ground robots inside a pocket stand on the tallest box over them (like the city height map); the
-- dungeon ceiling and glow strips do not count. heights() files the boxes into cells once.
local CELL = 25
local function cellKey(ix: number, iz: number): number
	return (ix + 1000) * 4096 + (iz + 1000)
end

function PocketLayout.heights(l: Layout)
	local cells = {}
	for _, b in l.boxes do
		if b.tag ~= "ceiling" and b.kind ~= "glow" and b.kind ~= "band" then
			local hx, hz = b.sx / 2, b.sz / 2
			if b.shape == "cylinder" then
				hx, hz = b.sx / 2, b.sx / 2
			end
			for ix = math.floor((b.cx - hx) / CELL), math.floor((b.cx + hx) / CELL) do
				for iz = math.floor((b.cz - hz) / CELL), math.floor((b.cz + hz) / CELL) do
					local k = cellKey(ix, iz)
					cells[k] = cells[k] or {}
					table.insert(cells[k], b)
				end
			end
		end
	end
	l.cells = cells
end

function PocketLayout.heightAt(l: Layout, x: number, z: number): number
	local cells = l.cells
	if not cells then
		PocketLayout.heights(l)
		cells = l.cells
	end
	local top = l.floorY
	for _, b in (cells :: any)[cellKey(math.floor(x / CELL), math.floor(z / CELL))] or {} do
		local hx, hz = b.sx / 2, b.sz / 2
		if b.shape == "cylinder" then
			hx, hz = b.sx / 2, b.sx / 2
		end
		if math.abs(x - b.cx) <= hx and math.abs(z - b.cz) <= hz then
			top = math.max(top, b.cy + b.sy / 2)
		end
	end
	return top
end

return PocketLayout
