--!strict
-- PocketLayout: the story mission pockets (spec: Map layout > Mission pockets "7 sealed 400 x 400 areas at
-- y = 3,000 studs, used by story missions for parties of up to 4; no PvP, no world scheduler inside").
-- Pure: a pocket index and a layout name give the boxes to build and the named points the mission script
-- uses (spawn, stations, crates, the tower top and mast, the contact and the chase path, the three rooms
-- and the gauntlet, the arena and its pillars). A pocket is a floor with walls and a sky dome feel; parts
-- are made by CityBuilder's part maker.
-- PLACEHOLDER ART: every pocket is greybox parts until the art pass.

local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local HqRules = if script then require(script.Parent.HqRules) else (require :: any)("./HqRules")

local PocketLayout = {}

-- One prologue's tunnel in the subway pocket: it runs from start (the steps down) along -z to the fight chamber
export type Lane = {
	index: number,
	x: number, -- the lane's centre line
	z0: number, -- the tunnel mouth (the start end)
	z1: number, -- the tunnel's far end, where the chamber begins
	floorY: number,
	start: { number },
	fight: { number }, -- the chamber's centre
	collapses: { { z: number, t: number } }, -- where each slab falls (its centre z) and when (s into the tunnel)
}

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

-- The subway pocket of the Ceremony prologue (lore step 3): the one after the missions' (they never take it)
function PocketLayout.subwayIndex(Config: any): number
	return Config.Story.pockets.count + 1
end

-- Which pocket a point is in, or nil (the subway pocket counts: no PvP, no world schedulers there either)
function PocketLayout.at(Config: any, x: number, y: number, z: number): number?
	local p = Config.Story.pockets
	if y < p.y - 100 then
		return nil
	end
	for i = 1, p.count + 1 do
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

-- A Downtown block with 3 power stations (or crates) and cover (no Act 1 mission uses it since lore step 5;
-- kept for later acts)
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
	l.points.trainDir = { 1, 0, 300 } -- a direction (x, z) and a length, not a place
	for i = 0, 6 do
		add(l, "path", -150 + i * 50, 51.5, if i % 2 == 0 then 110 else -110)
	end
end

-- The Signal (mission 5): Crane Tower, a spiral of ledges up to a top deck, its broadcast mast (the Vigil
-- guards Patch's uplink there) and a relay across the deck (the Syndicate plants its feed there)
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
	box(l, "prop", 30, h + 4, 0, 4, 6, 4, "steel")
	box(l, "glow", 30, h + 7.5, 0, 3, 1, 3, "foundryGlow")
	point(l, "relay", 26, h + 2.5, 0)
end

-- The Copy (mission 4): rooftops of Old Town with the contact on one, the copy waiting on the next, and a
-- lap of the rest
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
	local k = roofs[8] -- the roof beside it: where the copy stands
	point(l, "copy", k[1], k[2], k[3])
	-- the chase: a lap of the outer roofs
	for _, i in { 12, 7, 2, 3, 4, 9, 14, 19, 24, 23, 22 } do
		add(l, "path", roofs[i][1], roofs[i][2], roofs[i][3])
	end
	point(l, "spawn", 0, 3, 180)
end

-- Safehouse (mission 2): the old tunnels under the plaza, three rooms in a row, the old security line in the
-- middle and the Vigil's safehouse door at the end (the Syndicate smashes the scanner relays on the way). The
-- Safehouse is the Vigil's HQ (nate's lore plan Q2), so the tunnels wear its look: the hideout's wall colour and
-- its wall kit (pipes, cable trays, work lamps; Shared.HqRules.wallKit) along both long walls, as walk-through
-- decoration robots never stand on.
function BUILD.dungeon(l: Layout, Config: any)
	local K = Config.Hq.hideout
	local wallH = K.height
	local wallC = K.colors.wall
	box(l, "building", 0, wallH + 1, 0, 400, 2, 400, wallC, { tag = "ceiling" }) -- the ceiling (robots never stand on it)
	for k = -1, 1, 2 do
		box(l, "building", 0, wallH / 2, k * 60, 380, wallH, 4, wallC)
		local kit: { any } = {}
		HqRules.placeKit(kit, HqRules.wallKit(Config, 376), 0, k * 58, 1, 0, 0, -k)
		for _, p in kit do
			BoxKit.box(
				l.boxes,
				if p.glow then "glow" else "prop",
				l.cx + p.x,
				l.cy + p.y,
				l.cz + p.z,
				p.sx,
				p.sy,
				p.sz,
				p.color,
				{ tag = "decor", ghost = true }
			)
		end
	end
	-- dividing walls with doors between the 3 rooms
	for _, x in { -60, 60 } do
		box(l, "building", x, wallH / 2, -38, 4, wallH, 40, wallC)
		box(l, "building", x, wallH / 2, 38, 4, wallH, 40, wallC)
	end
	add(l, "rooms", -130, 0.5, 0)
	add(l, "rooms", 0, 0.5, 0)
	add(l, "rooms", 130, 0.5, 0)
	for i = 0, 3 do
		add(l, "turrets", -40 + i * 26, 0.5, if i % 2 == 0 then -45 else 45)
	end
	point(l, "gauntletEnd", 70, 3, 0)
	point(l, "boss", 150, 3, 0)
	box(l, "glow", 180, 8, 0, 4, 12, 12, "beaconGlow") -- the safehouse door
	point(l, "door", 160, 3, 0)
	for _, r in { { -150, -40 }, { -110, 40 }, { -20, -42 } } do
		add(l, "relays", r[1], 0.5, r[2])
	end
	point(l, "spawn", -170, 3, 0)
end

-- Live (mission 6): the fake's big public event, a stage under a giant screen, cameras and stage screens
-- around it, and 6 pillars to hide behind when Bulwark's battle form fires
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
	box(l, "building", 0, 1.5, -160, 120, 3, 40, "slate") -- the stage
	box(l, "glow", 0, 34, -188, 140, 46, 2, "beaconGlow") -- the giant screen
	for _, c in { { -130, 10 }, { 130, 10 }, { 0, 150 } } do
		add(l, "cams", c[1], 0.5, c[2])
		box(l, "prop", c[1], 3, c[2] - 6, 2, 6, 2, "steel")
		box(l, "prop", c[1], 6.5, c[2] - 6, 4, 3, 5, "steel")
	end
	for _, c in { { -150, -120 }, { 150, -120 }, { 70, 160 } } do
		add(l, "screens", c[1], 0.5, c[2])
	end
	point(l, "spawn", 0, 3, 170)
end

-- Framed (mission 3): a rail and road bridge over the water, two towers with cables, stranded people on the
-- deck (the Vigil's rings), armored trucks (the Syndicate's crates), the runaway train's line and a cash van
function BUILD.bridge(l: Layout)
	local deck = 20
	box(l, "plaza", 0, 0.1, 0, 396, 0.2, 396, "water")
	box(l, "road", 0, deck - 1, 0, 60, 2, 396, "road")
	for k = -1, 1, 2 do
		box(l, "ledge", k * 31, deck + 1.5, 0, 2, 3, 396, "steel") -- the railings
		for _, z in { -90, 90 } do
			box(l, "building", k * 34, 50, z, 6, 100, 6, "steel") -- the towers
		end
	end
	for _, z in { -90, 90 } do
		box(l, "ledge", 0, 98, z, 74, 4, 6, "steel")
	end
	local crates = { { 16, 70 }, { -16, -70 }, { 12, -150 } }
	for i, st in { { -14, 40 }, { 14, -30 }, { 0, -120 } } do
		add(l, "stations", st[1], deck + 0.5, st[2])
		add(l, "crates", crates[i][1], deck + 0.5, crates[i][2])
	end
	point(l, "trainStart", -20, deck + 0.2, 180)
	l.points.trainDir = { 0, -1, 330 } -- a direction (x, z) and a length, not a place
	point(l, "van", 18, deck + 0.5, 120)
	point(l, "boss", 0, deck + 0.5, -40)
	-- the chase: tower tops, crossbeams and the deck
	for _, c in
		{
			{ -34, 101, 90 },
			{ 34, 101, 90 },
			{ 20, deck + 1.5, 20 },
			{ -34, 101, -90 },
			{ 34, 101, -90 },
			{ 0, deck + 1.5, -170 },
			{ -20, deck + 1.5, 60 },
		}
	do
		add(l, "path", c[1], c[2], c[3])
	end
	point(l, "spawn", 0, deck + 3, 175)
end

-- Lane i (1 to Config.Story.opening.subway.lanes) of the subway pocket
function PocketLayout.lane(Config: any, i: number): Lane
	local S = Config.Story.opening.subway
	local cx, cy, cz = PocketLayout.centre(Config, PocketLayout.subwayIndex(Config))
	local x = cx + (i - (S.lanes + 1) / 2) * S.pitch
	local z0 = cz + Config.Story.pockets.size / 2 - 16
	local z1 = z0 - S.length
	local collapses = {}
	for _, c in S.collapses do
		table.insert(collapses, { z = z0 - c.at, t = c.t })
	end
	return {
		index = i,
		x = x,
		z0 = z0,
		z1 = z1,
		floorY = cy,
		start = { x, cy + 3, z0 - 8 },
		fight = { x, cy + 3, z1 - S.chamber / 2 },
		collapses = collapses,
	}
end

-- The prologue's subway (lore step 3): one tunnel a lane (walls, a ceiling, rails, lamps), each ending in a
-- square fight chamber. The falling slabs and rubble are drawn on the hero's device (PrologueFx).
-- PLACEHOLDER ART: greybox like every pocket.
function BUILD.subway(l: Layout, Config: any)
	local S = Config.Story.opening.subway
	for i = 1, S.lanes do
		local ln = PocketLayout.lane(Config, i)
		local x = ln.x - l.cx
		local z0, z1 = ln.z0 - l.cz, ln.z1 - l.cz
		local len = z0 - z1
		local zm = (z0 + z1) / 2
		local w, h = S.width, S.height
		for k = -1, 1, 2 do
			box(l, "building", x + k * (w / 2 + 1), h / 2, zm, 2, h, len, "foundry")
		end
		box(l, "building", x, h + 1, zm, w + 4, 2, len, "foundry", { tag = "ceiling" })
		box(l, "road", x, 0.1, zm, w, 0.2, len, "road")
		for k = -1, 1, 2 do
			box(l, "prop", x + k * 3, 0.35, zm, 0.6, 0.5, len, "steel") -- the rails
		end
		for z = z0 - 20, z1 + 10, -40 do
			box(l, "glow", x, h - 0.4, z, 3, 0.6, 3, "foundryGlow") -- a lamp every 40 studs
		end
		box(l, "building", x, h / 2, z0 + 1, w + 4, h, 2, "foundry") -- the end wall behind the steps
		-- the fight chamber: wider than the tunnel, with a ceiling and a doorway from the tunnel
		local c = S.chamber
		local czm = z1 - c / 2
		for k = -1, 1, 2 do
			box(l, "building", x + k * (c / 2 + 1), h / 2, czm, 2, h, c, "foundry")
			box(l, "building", x + k * (c + w) / 4, h / 2, z1 + 1, (c - w) / 2, h, 2, "foundry")
		end
		box(l, "building", x, h / 2, z1 - c - 1, c + 4, h, 2, "foundry")
		box(l, "building", x, h + 1, czm, c + 4, 2, c + 4, "foundry", { tag = "ceiling" })
		box(l, "glow", x, h - 0.4, czm, 6, 0.6, 6, "foundryGlow")
		add(l, "lanes", ln.start[1] - l.cx, 0.5, ln.start[3] - l.cz)
	end
end

-- Halo Academy (lore step 11, side quest chain The Hero Academy): the inside of an existing Downtown building.
-- The school stands on a deck DECK studs up: the entrance hall with Halo's statue (the spawn), two classrooms
-- with desks and blackboards (rooms 1 and 2) either side of the training hall (mats, dummies, hoops; `hall`),
-- and the back wall's hidden door (`hiddenDoor`) to a stairwell down. Under the school's floor (its ceiling
-- tagged so robots never stand on it) is Crane's copier workshop: four Spark scanner pods (`pods`), an
-- assembly line of copy robots and the foreman's spot (`boss`); `workshop` is the foot of the stairs.
-- PLACEHOLDER ART: greybox parts in the city palette, like every pocket.
local DECK = 24
function BUILD.academy(l: Layout, _Config: any)
	local D = DECK
	local deco = { tag = "decor", ghost = true }
	-- the school's floor: a deck over the south of the pocket, with a wood skin
	box(l, "building", 0, D / 2, 80, 396, D, 232, "sand")
	box(l, "plaza", 0, D + 0.1, 80, 396, 0.2, 232, "wood")
	point(l, "spawn", 0, D + 3, 172)
	-- the entrance hall: Halo's statue on a plinth, a gold halo over it, the school crest on the front wall
	box(l, "prop", 0, D + 2, 146, 12, 4, 12, "white")
	box(l, "prop", 0, D + 8, 146, 4, 8, 3, "white", deco)
	box(
		l,
		"glow",
		0,
		D + 14,
		146,
		7,
		0.6,
		7,
		"beaconGlow",
		{ shape = "cylinder", ghost = true, tag = "decor" }
	)
	box(l, "glow", 0, D + 16, 195, 80, 6, 1, "beaconGlow", deco)
	-- the classrooms: west (room 1) and east (room 2), each with a door onto the hall
	for k = -1, 1, 2 do
		local wx = k * 90 -- the inner wall, a door gap in its middle
		box(l, "building", wx, D + 11, 26, 4, 22, 32, "white")
		box(l, "building", wx, D + 11, 104, 4, 22, 32, "white")
		box(l, "building", k * 143, D + 11, 10, 106, 22, 4, "white")
		box(l, "building", k * 143, D + 11, 120, 106, 22, 4, "white")
		box(l, "prop", k * 195, D + 9, 65, 1, 10, 34, "slate", deco) -- the blackboard
		for r = 0, 2 do
			for c = 0, 3 do
				box(l, "prop", k * (110 + c * 20), D + 1.5, 40 + r * 24, 6, 3, 4, "wood", deco)
			end
		end
		add(l, "rooms", k * 143, D + 0.5, 65)
	end
	-- the training hall: mats, dummies and hoops
	box(l, "plaza", 0, D + 0.25, 50, 120, 0.3, 110, "roofBlue")
	for i, p in { { -50, 10 }, { 50, 10 }, { -50, 90 }, { 50, 90 } } do
		box(l, "prop", p[1], D + 3, p[2], 1.5, 6, 1.5, "steel", deco)
		box(l, "prop", p[1], D + 7, p[2], 3, 3, 3, if i % 2 == 0 then "roofRed" else "white", deco)
	end
	for _, x in { -70, 70 } do
		box(l, "prop", x, D + 9, -20, 1, 18, 1, "steel", deco)
		box(
			l,
			"glow",
			x,
			D + 18,
			-18,
			6,
			0.5,
			6,
			"beaconGlow",
			{ shape = "cylinder", ghost = true, tag = "decor" }
		)
	end
	point(l, "hall", 0, D + 0.5, 50)
	-- the back wall and its hidden door (a bookcase slid aside)
	box(l, "building", -107, D + 18, -34, 178, 36, 4, "white")
	box(l, "building", 107, D + 18, -34, 178, 36, 4, "white")
	box(l, "prop", 26, D + 7, -30, 14, 14, 3, "wood", deco)
	point(l, "hiddenDoor", 0, D + 0.5, -28)
	-- the stairwell down: 11 steps of 2 studs from the deck to the workshop floor, walled both sides
	for i = 1, 11 do
		local top = D - 2 * i
		box(l, "building", 0, top / 2, -39 - (i - 1) * 6, 32, top, 6, "concrete")
	end
	for k = -1, 1, 2 do
		box(l, "building", k * 18, 22, -70, 4, 44, 68, "tunnel")
	end
	point(l, "workshop", 0, 0.5, -112)
	-- Crane's copier workshop under the school: its ceiling is the school's floor (robots never stand on it)
	local ceil = { tag = "ceiling" }
	box(l, "building", -109, D + 2, -117, 178, 4, 162, "tunnel", ceil)
	box(l, "building", 109, D + 2, -117, 178, 4, 162, "tunnel", ceil)
	box(l, "building", 0, D + 2, -152, 40, 4, 92, "tunnel", ceil)
	for _, p in { { -120, -80 }, { -120, -150 }, { 120, -80 }, { 120, -150 } } do
		add(l, "pods", p[1], 0.5, p[2])
		box(l, "glow", p[1], 4, p[2] - 7, 5, 8, 0.6, "nullGlow", deco) -- the pod's scanner light
		box(l, "prop", p[1], 0.5, p[2], 9, 1, 9, "steel", deco)
	end
	-- the assembly line: a conveyor of half-built copy robots, work lamps under the ceiling
	box(l, "prop", 0, 1.5, -185, 300, 3, 10, "steel", deco)
	for i = -3, 3 do
		box(l, "prop", i * 40, 6, -185, 4, 7, 3, "nullMetal", deco)
		box(l, "glow", i * 40, 9.2, -183.4, 2, 0.6, 0.4, "nullGlow", deco)
	end
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D - 0.6, -117, 10, 0.6, 3, "workLamp", deco)
	end
	box(l, "glow", -197, 10, -117, 1, 4, 140, "foundryGlow", deco)
	box(l, "glow", 197, 10, -117, 1, 4, 140, "foundryGlow", deco)
	point(l, "boss", 0, 0.5, -160)
end

-- Tick-Tock Toys (lore step 11, the Suburbs chain Wind-Up Lane): the Toymaker's toy shop. The shop floor is a deck
-- over the south of the pocket: the toy aisles west (room 1) and east (room 2) with their shelves, the playroom in
-- the middle (`playroom`: a rug, a toy train ring and the giant music box), the counter at the back with the
-- trapdoor behind it (`trapdoor`) and a stairwell down. Under the shop floor (its ceiling tagged so robots never
-- stand on it) is the basement workshop: four clockwork winders (`winders`) piped to the Tantrum Tap, the brass
-- tank in the middle, half-built toy soldiers on the benches and the boss spot (`boss`); `workshop` is the foot
-- of the stairs.
-- PLACEHOLDER ART: greybox parts in the city palette, like every pocket.
local SHOP_DECK = 20
function BUILD.toyshop(l: Layout, _Config: any)
	local D = SHOP_DECK
	local deco = { tag = "decor", ghost = true }
	-- the shop floor: a deck over the south of the pocket, with a wood skin
	box(l, "building", 0, D / 2, 80, 396, D, 232, "sand")
	box(l, "plaza", 0, D + 0.1, 80, 396, 0.2, 232, "wood")
	point(l, "spawn", 0, D + 3, 172)
	-- the front: the big clock sign over the door, the shop window's glow
	box(l, "glow", 0, D + 22, 195, 16, 16, 1, "beaconGlow", deco)
	box(l, "prop", 0, D + 22, 194.2, 1, 6, 0.4, "steel", deco) -- the clock's hands
	box(l, "prop", 2, D + 22, 194.2, 4, 1, 0.4, "steel", deco)
	box(l, "glow", 0, D + 9, 196, 160, 10, 1, "window", deco)
	-- the aisles: tall toy shelves in rows, west (room 1) and east (room 2), toys on every shelf
	for k = -1, 1, 2 do
		for r = 0, 2 do
			local z = 40 + r * 36
			box(l, "prop", k * 130, D + 6, z, 70, 12, 4, "wood", deco)
			for c = 0, 4 do
				local col = if (r + c) % 3 == 0
					then "roofRed"
					elseif (r + c) % 3 == 1 then "roofBlue"
					else "white"
				box(l, "prop", k * (100 + c * 14), D + 13.5, z, 4, 3, 3, col, deco)
			end
		end
		add(l, "rooms", k * 130, D + 0.5, 58)
	end
	-- the playroom: a round rug, a toy train ring, giant blocks and the music box that plays the Toymaker's tune
	box(l, "plaza", 0, D + 0.25, 60, 64, 0.3, 64, "roofRed", { shape = "cylinder" })
	for i = 0, 7 do
		local a = i * math.pi / 4
		box(l, "prop", math.cos(a) * 26, D + 1, 60 + math.sin(a) * 26, 5, 2, 3, "steel", deco)
	end
	for i, p in { { -20, 30 }, { 22, 34 }, { -24, 92 } } do
		box(l, "prop", p[1], D + 2.5, p[2], 5, 5, 5, if i == 2 then "roofBlue" else "white", deco)
	end
	box(l, "prop", 18, D + 4, 88, 10, 8, 8, "wood", deco) -- the music box
	box(l, "glow", 18, D + 8.5, 88, 6, 0.6, 6, "beaconGlow", deco)
	point(l, "playroom", 0, D + 0.5, 60)
	-- the back wall, the counter and the trapdoor behind it
	box(l, "building", -107, D + 15, -34, 178, 30, 4, "white")
	box(l, "building", 107, D + 15, -34, 178, 30, 4, "white")
	box(l, "prop", 0, D + 2, -14, 50, 4, 6, "wood", deco) -- the counter
	box(l, "prop", -16, D + 5, -14, 4, 3, 3, "steel", deco) -- the till
	point(l, "trapdoor", 0, D + 0.5, -28)
	-- the stairwell down: 9 steps of 2 studs from the shop floor to the basement floor, walled both sides
	for i = 1, 9 do
		local top = D - 2 * i
		box(l, "building", 0, top / 2, -39 - (i - 1) * 6, 32, top, 6, "concrete")
	end
	for k = -1, 1, 2 do
		box(l, "building", k * 18, 18, -64, 4, 36, 56, "tunnel")
	end
	point(l, "workshop", 0, 0.5, -100)
	-- the basement workshop under the shop: its ceiling is the shop's floor level (robots never stand on it)
	local ceil = { tag = "ceiling" }
	box(l, "building", -109, D + 2, -117, 178, 4, 162, "tunnel", ceil)
	box(l, "building", 109, D + 2, -117, 178, 4, 162, "tunnel", ceil)
	box(l, "building", 0, D + 2, -152, 40, 4, 92, "tunnel", ceil)
	-- the four winders: big brass keys turning on plinths, piped to the Tap
	for _, p in { { -120, -80 }, { -120, -150 }, { 120, -80 }, { 120, -150 } } do
		add(l, "winders", p[1], 0.5, p[2])
		box(l, "prop", p[1], 0.5, p[2], 9, 1, 9, "steel", deco)
		box(l, "prop", p[1], 5, p[2], 2, 8, 2, "roof", deco)
		box(l, "prop", p[1], 9, p[2], 8, 3, 1, "roof", deco)
		box(l, "prop", p[1] / 2, 14, p[2], math.abs(p[1]), 1.5, 1.5, "steel", deco) -- its pipe to the middle
	end
	-- the Tantrum Tap: a brass tank fed by the main pipe, its gauge glowing, and the toy soldier benches either side
	box(l, "prop", 0, 14, -127.5, 1.5, 1.5, 95, "steel", deco)
	box(l, "prop", 0, 9, -178, 26, 18, 26, "roof", { shape = "cylinder", tag = "decor", ghost = true })
	box(l, "glow", 0, 12, -164.6, 8, 4, 0.4, "nullGlow", deco)
	for k = -1, 1, 2 do
		box(l, "prop", k * 60, 1.5, -190, 60, 3, 8, "wood", deco)
		for i = 0, 3 do
			box(l, "prop", k * (40 + i * 12), 5, -190, 3, 5, 3, "roofRed", deco)
		end
	end
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D - 0.6, -117, 10, 0.6, 3, "workLamp", deco)
	end
	point(l, "boss", 0, 0.5, -140)
end

-- Captain Brine's sea cave (lore step 11, the Coast chain The Salt Dogs). The cave's rock shelf is a deck over the
-- south of the pocket: the cave mouth with the sea's daylight behind it (the spawn), the tide pools west (room
-- 1) and east (room 2) with their rocks and coral, the wharf in the middle (`wharf`: a plank landing, mooring
-- posts, a rowboat and the cage the Salt Dogs keep Finn in), and the back wall with the rock steps down behind
-- it (`stairhead`). Under the shelf (its ceiling tagged so robots never stand on it) is the hidden grotto: the
-- Drowned Gull, Brine's little ship, moored in a sea pool with its hologram "ghost" sails, the four projector
-- rigs that throw the ghost ship (`projectors`), the treasure along the back and the boss spot (`boss`);
-- `grotto` is the foot of the steps.
-- PLACEHOLDER ART: greybox parts in the city palette, like every pocket.
local CAVE_SHELF = 20
function BUILD.seacave(l: Layout, _Config: any)
	local D = CAVE_SHELF
	local deco = { tag = "decor", ghost = true }
	-- the rock shelf: a deck over the south of the pocket, its wet sand skin
	box(l, "building", 0, D / 2, 80, 396, D, 232, "rock")
	box(l, "plaza", 0, D + 0.1, 80, 396, 0.2, 232, "seabed")
	point(l, "spawn", 0, D + 3, 172)
	-- the cave mouth: rock either side and over the top, the sea's daylight beyond
	for k = -1, 1, 2 do
		box(l, "prop", k * 150, D + 20, 190, 100, 40, 12, "rock", deco)
	end
	box(l, "prop", 0, D + 44, 190, 400, 10, 12, "rock", deco)
	box(l, "glow", 0, D + 16, 196, 200, 30, 1, "water", deco)
	-- the tide pools, west (room 1) and east (room 2): a pool, rocks round it and coral at its edge
	local corals = { "coralA", "coralB", "coralC", "coralD" }
	for k = -1, 1, 2 do
		box(l, "glow", k * 130, D + 0.25, 58, 60, 0.3, 50, "water", deco)
		for i = 0, 3 do
			box(l, "prop", k * (100 + i * 20), D + 2.5, 30 + (i % 2) * 56, 8, 5, 7, "rock", deco)
			box(l, "prop", k * (108 + i * 14), D + 1.5, 82, 3, 3, 3, corals[i + 1], deco)
		end
		add(l, "rooms", k * 130, D + 0.5, 58)
	end
	-- the wharf: a plank landing, four mooring posts, a rowboat and Finn's cage
	box(l, "plaza", 0, D + 0.25, 60, 60, 0.3, 50, "wood")
	for _, p in { { -28, 36 }, { 28, 36 }, { -28, 84 }, { 28, 84 } } do
		box(l, "prop", p[1], D + 2.5, p[2], 2, 5, 2, "wood", deco)
	end
	box(l, "prop", 20, D + 1, 42, 6, 2, 14, "wreck", deco)
	for _, p in { { -5, 83 }, { 5, 83 }, { -5, 93 }, { 5, 93 } } do
		box(l, "prop", p[1], D + 4, p[2], 0.6, 8, 0.6, "steel", deco)
	end
	box(l, "prop", 0, D + 8.2, 88, 11, 0.4, 11, "steel", deco)
	point(l, "wharf", 0, D + 0.5, 60)
	-- the back wall, its lanterns and the rock steps behind it
	box(l, "building", -107, D + 15, -34, 178, 30, 4, "rock")
	box(l, "building", 107, D + 15, -34, 178, 30, 4, "rock")
	for k = -1, 1, 2 do
		box(l, "glow", k * 60, D + 12, -31.5, 3, 4, 1, "workLamp", deco)
	end
	point(l, "stairhead", 0, D + 0.5, -28)
	-- the steps down: 9 steps of 2 studs from the shelf to the grotto floor, rock walls both sides
	for i = 1, 9 do
		local top = D - 2 * i
		box(l, "building", 0, top / 2, -39 - (i - 1) * 6, 32, top, 6, "rock")
	end
	for k = -1, 1, 2 do
		box(l, "building", k * 18, 18, -64, 4, 36, 56, "rock")
	end
	point(l, "grotto", 0, 0.5, -100)
	-- the grotto under the shelf: its ceiling is the shelf's level (robots never stand on it)
	local ceil = { tag = "ceiling" }
	box(l, "building", -109, D + 2, -117, 178, 4, 162, "rock", ceil)
	box(l, "building", 109, D + 2, -117, 178, 4, 162, "rock", ceil)
	box(l, "building", 0, D + 2, -152, 40, 4, 92, "rock", ceil)
	-- the Drowned Gull in its sea pool: hull, deck, mast, the hologram sails and the lens that throws them
	box(l, "glow", 80, 0.25, -150, 90, 0.3, 80, "sea", deco)
	box(l, "prop", 80, 2.5, -150, 22, 5, 60, "wreck", deco)
	box(l, "prop", 80, 5.2, -150, 20, 0.4, 56, "wood", deco)
	box(l, "prop", 80, 11, -150, 1.6, 12, 1.6, "wood", deco)
	for _, z in { -138, -162 } do
		box(l, "glow", 80, 12, z, 0.4, 8, 18, "water", deco)
	end
	box(l, "glow", 80, 17.5, -150, 2, 2, 2, "sparkGlow", { tag = "decor", ghost = true, shape = "ball" })
	-- the four projector rigs that throw the ghost ship: a plinth, a post and a glowing lens each
	for _, p in { { -140, -80 }, { -140, -160 }, { 140, -80 }, { 140, -180 } } do
		add(l, "projectors", p[1], 0.5, p[2])
		box(l, "prop", p[1], 0.5, p[2], 7, 1, 7, "steel", deco)
		box(l, "prop", p[1], 4, p[2], 1.5, 6, 1.5, "steel", deco)
		box(l, "glow", p[1], 7.5, p[2], 3, 3, 3, "sparkGlow", { tag = "decor", ghost = true, shape = "ball" })
	end
	-- the treasure along the back: chests with gold heaped on them
	for i = -2, 2 do
		box(l, "prop", i * 24, 1.5, -192, 8, 3, 5, "wood", deco)
		box(l, "prop", i * 24, 3.3, -192, 6, 0.6, 3, "cargo", deco)
	end
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D - 0.6, -117, 10, 0.6, 3, "workLamp", deco)
	end
	point(l, "boss", -40, 0.5, -140)
end

-- Is this a pocket layout name? (lore step 10: side quest pocket steps are checked against it)
function PocketLayout.known(layout: any): boolean
	return type(layout) == "string" and BUILD[layout] ~= nil
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
		if b.tag ~= "ceiling" and b.tag ~= "decor" and b.kind ~= "glow" and b.kind ~= "band" then
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
