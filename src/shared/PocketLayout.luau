--!strict
-- PocketLayout: the story mission pockets (spec: Map layout > Mission pockets "7 sealed 400 x 400 areas at
-- y = 3,000 studs, used by story missions for parties of up to 4; no PvP, no world scheduler inside").
-- Pure: a pocket index and a layout name give the boxes to build and the named points the mission script
-- uses (spawn, stations, crates, the tower top and mast, the contact and the chase path, the three rooms
-- and the gauntlet, the arena and its pillars). A pocket is a floor with walls and a sky dome feel; parts
-- are made by CityBuilder's part maker.
-- PLACEHOLDER ART: every pocket is greybox parts until the art pass.
-- (lore step 11, the character lines: "pound", the Spark Pound, Catchpole's Docks warehouse.)
-- (overnight queue item 10: the side quests' pockets list their Blender looks, Layout.art: Shared.SetPieceKit
-- placements in world studs over the decor boxes that carry their index as `art`; MissionService draws the
-- meshes once nate imports ReplicatedStorage.Art.SetPieces and hides those boxes, else the boxes are drawn.)

local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local SetPieceKit = if script then require(script.Parent.SetPieceKit) else (require :: any)("./SetPieceKit")
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
	collapses: { { z: number } }, -- where each slab falls (its centre z), once the hero is past it
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
	art: { SetPieceKit.Place }, -- the Blender looks over its boxes (Shared.SetPieceKit)
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
	local b = BoxKit.box(l.boxes, kind, l.cx + x, l.cy + y, l.cz + z, sx, sy, sz, color, opts)
	if opts and opts.art then
		(b :: any).art = opts.art
	end
end

-- A Blender look (Shared.SetPieceKit) at x, y, z in the pocket's own studs, turned ry degrees; returns its index
local function look(l: Layout, name: string, x: number, y: number, z: number, ry: number?, tint: any?): number
	return SetPieceKit.place(l.art, name, l.cx + x, l.cy + y, l.cz + z, ry, nil, tint)
end

-- The options for a decor box a look stands over (no collision, as every pocket decor box)
local function art(i: number, shape: string?): any
	return { tag = "decor", ghost = true, art = i, shape = shape }
end

-- Bright toy and coral colours a look's copies take (SetPieceKit tints)
local TOY =
	{ red = { 228, 62, 56 }, blue = { 60, 124, 226 }, white = { 246, 242, 232 }, gold = { 250, 200, 60 } }
local CORAL = { { 255, 120, 120 }, { 255, 180, 90 }, { 190, 120, 230 }, { 90, 210, 190 } }

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
		table.insert(collapses, { z = z0 - c.at })
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

-- A point pulled inside a lane's fight chamber, `margin` studs clear of its walls (the prologue's swarm spawns
-- in a ring round the hero: a ring point past a wall would leave a robot outside the room)
function PocketLayout.chamberPoint(
	Config: any,
	lane: Lane,
	x: number,
	z: number,
	margin: number
): (number, number)
	local c = Config.Story.opening.subway.chamber
	local half = c / 2 - margin
	local cz = lane.z1 - c / 2
	return math.clamp(x, lane.x - half, lane.x + half), math.clamp(z, cz - half, cz + half)
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
	local clock = look(l, "ToyClock", 0, D + 22, 195)
	box(l, "glow", 0, D + 22, 195, 16, 16, 1, "beaconGlow", art(clock))
	box(l, "prop", 0, D + 22, 194.2, 1, 6, 0.4, "steel", art(clock)) -- the clock's hands
	box(l, "prop", 2, D + 22, 194.2, 4, 1, 0.4, "steel", art(clock))
	box(l, "glow", 0, D + 9, 196, 160, 10, 1, "window", deco)
	-- the aisles: tall toy shelves in rows, west (room 1) and east (room 2), toys on every shelf
	for k = -1, 1, 2 do
		for r = 0, 2 do
			local z = 40 + r * 36
			local tint = {}
			for c = 0, 4 do
				local m = (r + c) % 3
				tint["ShelfToy" .. (c + 1)] = if m == 0 then TOY.red elseif m == 1 then TOY.blue else TOY.white
			end
			-- (the far shelf turned round, so its toys run the same way along it)
			local shelf = look(l, "ToyShelf", k * 130, D, z, if k == 1 then 0 else 180, tint)
			box(l, "prop", k * 130, D + 6, z, 70, 12, 4, "wood", art(shelf))
			for c = 0, 4 do
				local col = if (r + c) % 3 == 0
					then "roofRed"
					elseif (r + c) % 3 == 1 then "roofBlue"
					else "white"
				box(l, "prop", k * (100 + c * 14), D + 13.5, z, 4, 3, 3, col, art(shelf))
			end
		end
		add(l, "rooms", k * 130, D + 0.5, 58)
	end
	-- the playroom: a round rug, a toy train ring, giant blocks and the music box that plays the Toymaker's tune
	box(l, "plaza", 0, D + 0.25, 60, 64, 0.3, 64, "roofRed", { shape = "cylinder" })
	local train = look(l, "ToyTrain", 0, D, 60)
	for i = 0, 7 do
		local a = i * math.pi / 4
		box(l, "prop", math.cos(a) * 26, D + 1, 60 + math.sin(a) * 26, 5, 2, 3, "steel", art(train))
	end
	for i, p in { { -20, 30 }, { 22, 34 }, { -24, 92 } } do
		local blk = look(l, "ToyBlock", p[1], D, p[2], (i - 1) * 25, {
			ToyBlockBody = if i == 2 then TOY.blue else TOY.white,
			ToyBlockMarks = if i == 2 then TOY.gold else TOY.red,
		})
		box(l, "prop", p[1], D + 2.5, p[2], 5, 5, 5, if i == 2 then "roofBlue" else "white", art(blk))
	end
	local music = look(l, "MusicBox", 18, D, 88)
	box(l, "prop", 18, D + 4, 88, 10, 8, 8, "wood", art(music)) -- the music box
	box(l, "glow", 18, D + 8.5, 88, 6, 0.6, 6, "beaconGlow", art(music))
	point(l, "playroom", 0, D + 0.5, 60)
	-- the back wall, the counter and the trapdoor behind it
	box(l, "building", -107, D + 15, -34, 178, 30, 4, "white")
	box(l, "building", 107, D + 15, -34, 178, 30, 4, "white")
	local counter = look(l, "ShopCounter", 0, D, -14)
	box(l, "prop", 0, D + 2, -14, 50, 4, 6, "wood", art(counter)) -- the counter
	box(l, "prop", -16, D + 5, -14, 4, 3, 3, "steel", art(counter)) -- the till
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
		-- (the key's pipe runs along its look's +x to the middle: the east keys are turned round)
		local key = look(l, "WindKey", p[1], 0, p[2], if p[1] < 0 then 0 else 180)
		box(l, "prop", p[1], 0.5, p[2], 9, 1, 9, "steel", art(key))
		box(l, "prop", p[1], 5, p[2], 2, 8, 2, "roof", art(key))
		box(l, "prop", p[1], 9, p[2], 8, 3, 1, "roof", art(key))
		box(l, "prop", p[1] / 2, 14, p[2], math.abs(p[1]), 1.5, 1.5, "steel", art(key)) -- its pipe to the middle
	end
	-- the Tantrum Tap: a brass tank fed by the main pipe, its gauge glowing, and the toy soldier benches either side
	local tap = look(l, "TantrumTap", 0, 0, -178)
	box(l, "prop", 0, 14, -127.5, 1.5, 1.5, 95, "steel", art(tap))
	box(l, "prop", 0, 9, -178, 26, 18, 26, "roof", art(tap, "cylinder"))
	box(l, "glow", 0, 12, -164.6, 8, 4, 0.4, "nullGlow", art(tap))
	for k = -1, 1, 2 do
		local bench = look(l, "SoldierBench", k * 60, 0, -190, if k == 1 then 0 else 180)
		box(l, "prop", k * 60, 1.5, -190, 60, 3, 8, "wood", art(bench))
		for i = 0, 3 do
			box(l, "prop", k * (40 + i * 12), 5, -190, 3, 5, 3, "roofRed", art(bench))
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
			local rx, rz = k * (100 + i * 20), 30 + (i % 2) * 56
			local rock = look(l, "CaveRock", rx, D, rz, (i + (k + 1) * 2) * 90)
			box(l, "prop", rx, D + 2.5, rz, 8, 5, 7, "rock", art(rock))
			local cx = k * (108 + i * 14)
			local coral = look(l, "Coral", cx, D, 82, i * 70 + k * 20, { CoralBranch = CORAL[i + 1] })
			box(l, "prop", cx, D + 1.5, 82, 3, 3, 3, corals[i + 1], art(coral))
		end
		add(l, "rooms", k * 130, D + 0.5, 58)
	end
	-- the wharf: a plank landing, four mooring posts, a rowboat and Finn's cage
	box(l, "plaza", 0, D + 0.25, 60, 60, 0.3, 50, "wood")
	for i, p in { { -28, 36 }, { 28, 36 }, { -28, 84 }, { 28, 84 } } do
		local post = look(l, "MooringPost", p[1], D, p[2], i * 90)
		box(l, "prop", p[1], D + 2.5, p[2], 2, 5, 2, "wood", art(post))
	end
	local boat = look(l, "Rowboat", 20, D, 42)
	box(l, "prop", 20, D + 1, 42, 6, 2, 14, "wreck", art(boat))
	local cage = look(l, "FinnCage", 0, D, 88)
	for _, p in { { -5, 83 }, { 5, 83 }, { -5, 93 }, { 5, 93 } } do
		box(l, "prop", p[1], D + 4, p[2], 0.6, 8, 0.6, "steel", art(cage))
	end
	box(l, "prop", 0, D + 8.2, 88, 11, 0.4, 11, "steel", art(cage))
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
	local ship = look(l, "DrownedGull", 80, 0, -150)
	box(l, "prop", 80, 2.5, -150, 22, 5, 60, "wreck", art(ship))
	box(l, "prop", 80, 5.2, -150, 20, 0.4, 56, "wood", art(ship))
	box(l, "prop", 80, 11, -150, 1.6, 12, 1.6, "wood", art(ship))
	for _, z in { -138, -162 } do
		box(l, "glow", 80, 12, z, 0.4, 8, 18, "water", art(ship))
	end
	box(l, "glow", 80, 17.5, -150, 2, 2, 2, "sparkGlow", art(ship, "ball"))
	-- the four projector rigs that throw the ghost ship: a plinth, a post and a glowing lens each
	for _, p in { { -140, -80 }, { -140, -160 }, { 140, -80 }, { 140, -180 } } do
		add(l, "projectors", p[1], 0.5, p[2])
		-- (each rig's lamp faces the ship's pool in the middle)
		local rig = look(l, "Projector", p[1], 0, p[2], if p[1] < 0 then 0 else 180)
		box(l, "prop", p[1], 0.5, p[2], 7, 1, 7, "steel", art(rig))
		box(l, "prop", p[1], 4, p[2], 1.5, 6, 1.5, "steel", art(rig))
		box(l, "glow", p[1], 7.5, p[2], 3, 3, 3, "sparkGlow", art(rig, "ball"))
	end
	-- the treasure along the back: chests with gold heaped on them
	for i = -2, 2 do
		local chest = look(l, "TreasureChest", i * 24, 0, -192)
		box(l, "prop", i * 24, 1.5, -192, 8, 3, 5, "wood", art(chest))
		box(l, "prop", i * 24, 3.3, -192, 6, 0.6, 3, "cargo", art(chest))
	end
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D - 0.6, -117, 10, 0.6, 3, "workLamp", deco)
	end
	point(l, "boss", -40, 0.5, -140)
end

-- Velmara, the drowned city (lore step 11, the Underwater chain The Sunken City), under its old air dome so
-- heroes walk its halls. The upper terrace is a deck over the south of the pocket: the drowned gate with the sea
-- held back behind it (the spawn), the market streets west (room 1) and east (room 2) with their stalls,
-- broken columns and coral, the old fountain in the middle (`fountain`: a basin round a bronze statue of the
-- Tidewright) and the back wall with the great stair down behind it (`stairhead`). Under the terrace (its
-- ceiling tagged so robots never stand on it) is the engine hall: the four tide engines that raise the wave
-- (`pumps`: a plinth, a drum and a glowing core each), the great sea valve along the back and the boss spot
-- (`boss`); `engines` is the foot of the stair.
-- PLACEHOLDER ART: greybox parts in the city palette, like every pocket.
local CITY_TERRACE = 20
function BUILD.velmara(l: Layout, _Config: any)
	local D = CITY_TERRACE
	local deco = { tag = "decor", ghost = true }
	-- the terrace: a stone deck over the south of the pocket, paved in sand-coloured flags
	box(l, "building", 0, D / 2, 80, 396, D, 232, "slate")
	box(l, "plaza", 0, D + 0.1, 80, 396, 0.2, 232, "sand")
	point(l, "spawn", 0, D + 3, 172)
	-- the drowned gate: two bronze pillars and a lintel with glowing runes, the sea held back beyond it
	local gate = look(l, "DrownedGate", 0, D, 186)
	for k = -1, 1, 2 do
		box(l, "prop", k * 26, D + 18, 186, 10, 36, 10, "rust", art(gate))
		box(l, "prop", k * 120, D + 20, 190, 180, 40, 12, "rock", deco)
	end
	box(l, "prop", 0, D + 39, 186, 64, 6, 10, "rust", art(gate))
	box(l, "glow", 0, D + 39, 180.8, 40, 1.5, 0.4, "sparkGlow", art(gate))
	box(l, "glow", 0, D + 18, 196, 200, 36, 1, "water", deco)
	-- the market streets, west (room 1) and east (room 2): stall counters, broken columns and coral
	local corals = { "coralA", "coralB", "coralC", "coralD" }
	for k = -1, 1, 2 do
		for i = 0, 2 do
			local stall = look(l, "MarketStall", k * 130, D, 28 + i * 30, if k == 1 then 0 else 180)
			box(l, "prop", k * 130, D + 2, 28 + i * 30, 18, 4, 6, "cargo", art(stall))
			local column = ({ "ColumnTall", "ColumnMid", "ColumnStub" })[i + 1]
			local col = look(l, column, k * (96 + i * 34), D, 98, (i + 1) * k * 40)
			box(l, "prop", k * (96 + i * 34), D + 7 - i * 2, 98, 4, 14 - i * 4, 4, "white", art(col))
		end
		for i = 0, 3 do
			local cx, cz = k * (100 + i * 22), 12 + (i % 2) * 90
			local coral = look(l, "Coral", cx, D, cz, i * 80 + k * 30, { CoralBranch = CORAL[i + 1] })
			box(l, "prop", cx, D + 1.5, cz, 3, 3, 3, corals[i + 1], art(coral))
		end
		box(l, "crop", k * 170, D + 6, 60, 0.8, 12, 0.8, "kelp", deco)
		add(l, "rooms", k * 130, D + 0.5, 58)
	end
	-- the old fountain: a basin round a bronze statue of the Tidewright, its eyes still glowing
	-- (the basin stays solid under its look: only its colour gives way to the stone rim)
	local fountain = look(l, "Fountain", 0, D, 60)
	box(l, "plaza", 0, D + 0.6, 60, 34, 1.2, 34, "white", { art = fountain })
	box(l, "glow", 0, D + 1.3, 60, 30, 0.3, 30, "sea", deco)
	box(l, "prop", 0, D + 6, 60, 5, 10, 5, "rust", art(fountain))
	box(l, "prop", 0, D + 13, 60, 4, 4, 4, "rust", art(fountain, "ball"))
	box(l, "glow", 0, D + 13.4, 58, 2.4, 0.5, 0.4, "sparkGlow", art(fountain))
	point(l, "fountain", 0, D + 1.5, 60)
	-- the back wall, its rune lamps and the great stair behind it
	box(l, "building", -107, D + 15, -34, 178, 30, 4, "slate")
	box(l, "building", 107, D + 15, -34, 178, 30, 4, "slate")
	for k = -1, 1, 2 do
		box(l, "glow", k * 60, D + 12, -31.5, 3, 4, 1, "sparkGlow", deco)
	end
	point(l, "stairhead", 0, D + 0.5, -28)
	-- the great stair: 9 steps of 2 studs from the terrace to the engine hall, stone walls both sides
	for i = 1, 9 do
		local top = D - 2 * i
		box(l, "building", 0, top / 2, -39 - (i - 1) * 6, 32, top, 6, "slate")
	end
	for k = -1, 1, 2 do
		box(l, "building", k * 18, 18, -64, 4, 36, 56, "slate")
	end
	point(l, "engines", 0, 0.5, -100)
	-- the engine hall under the terrace: its ceiling is the terrace's level (robots never stand on it)
	local ceil = { tag = "ceiling" }
	box(l, "building", -109, D + 2, -117, 178, 4, 162, "slate", ceil)
	box(l, "building", 109, D + 2, -117, 178, 4, 162, "slate", ceil)
	box(l, "building", 0, D + 2, -152, 40, 4, 92, "slate", ceil)
	-- the four tide engines: a plinth, a bronze drum and a glowing core each
	for _, p in { { -140, -80 }, { -140, -160 }, { 140, -80 }, { 140, -170 } } do
		add(l, "pumps", p[1], 0.5, p[2])
		local engine = look(l, "TideEngine", p[1], 0, p[2], if p[1] < 0 then 0 else 180)
		box(l, "prop", p[1], 0.5, p[2], 9, 1, 9, "slate", art(engine))
		box(l, "prop", p[1], 5, p[2], 6, 8, 6, "rust", art(engine, "cylinder"))
		box(l, "glow", p[1], 10, p[2], 3, 3, 3, "sparkGlow", art(engine, "ball"))
	end
	-- the great sea valve along the back: a wheel on a wall of bronze pipes, sea water glowing behind a grille
	local valve = look(l, "SeaValve", 0, 0, -194)
	for i = -3, 3 do
		box(l, "prop", i * 18, 8, -194, 4, 16, 4, "rust", art(valve, "cylinder"))
	end
	box(l, "glow", 0, 9, -197, 140, 14, 1, "water", deco)
	box(l, "prop", 0, 10, -190, 14, 14, 1.5, "rust", art(valve, "cylinder"))
	-- coral grown over the hall's floor and kelp up its pillars
	for i = 0, 5 do
		local cx, cz = -100 + i * 40, -120 + (i % 2) * 30
		local coral = look(l, "Coral", cx, 0, cz, i * 60, { CoralBranch = CORAL[i % 4 + 1] })
		box(l, "prop", cx, 1, cz, 3, 2, 3, corals[i % 4 + 1], art(coral))
	end
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D - 0.6, -117, 10, 0.6, 3, "sparkGlow", deco)
	end
	point(l, "boss", 40, 0.5, -140)
end

-- The Pit (lore step 11, chain 6 The Pit: the Old Quarry's underground fight club, run by the Gravel family).
-- The gallery is a rock deck over the south of the pocket: the old mine lift's cage you ride down in (the
-- spawn), the mine tunnel west (room 1) with its timber props, rails and a cart, the bookies' cash crates east
-- (room 2), the betting hall in the middle (`bets`: the bookies' counter under the glowing odds board), the
-- four rigged odds machines along it (`odds`) and the gallery's rail over the Pit with the steps down at its
-- middle (`stairhead`). Below the gallery, open to the cavern, is the Pit itself: the ring on its low stage
-- (`ring`, `boss`: canvas, corner posts and glowing ropes) under four floodlights, rock benches for the crowd
-- round three sides and the family's box seat at the back; `pitfloor` is the foot of the steps.
-- PLACEHOLDER ART: greybox parts in the city palette, like every pocket.
local PIT_DECK = 20
local RING = { z = -130, size = 40, stage = 2 }
function BUILD.pit(l: Layout, _Config: any)
	local D = PIT_DECK
	local deco = { tag = "decor", ghost = true }
	-- the gallery: a rock deck over the south of the pocket, its packed-sand skin
	box(l, "building", 0, D / 2, 80, 396, D, 232, "rock")
	box(l, "plaza", 0, D + 0.1, 80, 396, 0.2, 232, "sand")
	point(l, "spawn", 0, D + 3, 172)
	-- the mine lift: a steel cage on four rails, its winding frame and a work lamp
	local lift = look(l, "MineLift", 0, D, 189)
	for _, p in { { -10, 182 }, { 10, 182 }, { -10, 196 }, { 10, 196 } } do
		box(l, "prop", p[1], D + 9, p[2], 1, 18, 1, "steel", art(lift))
	end
	box(l, "prop", 0, D + 18.5, 189, 22, 1, 16, "steel", art(lift))
	box(l, "prop", 0, D + 26, 196, 2, 14, 2, "steel", art(lift))
	box(l, "prop", 0, D + 32, 196, 14, 2, 2, "steel", art(lift))
	box(l, "glow", 0, D + 17.4, 189, 6, 0.6, 6, "workLamp", deco)
	-- the mine tunnel, west (room 1): timber props in pairs under a beam, cart rails and an old mine cart
	for i = 0, 3 do
		local z = 20 + i * 36
		local timber = look(l, "MineTimber", -130, D, z, i * 180)
		for k = -1, 1, 2 do
			box(l, "prop", -130 + k * 32, D + 10, z, 3, 20, 3, "wood", art(timber))
		end
		box(l, "prop", -130, D + 20.5, z, 70, 2, 3, "wood", art(timber))
	end
	for k = -1, 1, 2 do
		box(l, "prop", -130 + k * 4, D + 0.4, 74, 1, 0.6, 140, "steel", deco)
	end
	local cart = look(l, "MineCart", -130, D, 44)
	box(l, "prop", -130, D + 2.5, 44, 8, 4, 12, "rust", art(cart))
	box(l, "glow", -130, D + 19.2, 74, 4, 0.6, 4, "workLamp", deco)
	add(l, "rooms", -130, D + 0.5, 74)
	-- the bookies' corner, east (room 2): stacked crates of cash bags under a lamp
	for i = 0, 5 do
		local x, z = 110 + (i % 3) * 20, 50 + (i // 3) * 40
		local crate = look(l, "CashCrate", x, D, z, i * 90)
		box(l, "prop", x, D + 3, z, 10, 6, 10, "wood", art(crate))
		box(l, "prop", x, D + 6.6, z, 6, 1.2, 6, "cargo", art(crate))
	end
	box(l, "glow", 130, D + 19.2, 74, 4, 0.6, 4, "workLamp", deco)
	add(l, "rooms", 130, D + 0.5, 74)
	-- the betting hall: the bookies' counter under the odds board (three dark rows of odds on a glowing board)
	box(l, "prop", 0, D + 2, 124, 60, 4, 6, "wood", art(look(l, "BookieCounter", 0, D, 124)))
	box(l, "glow", 0, D + 18, 134, 70, 14, 1, "window", deco)
	for r = 0, 2 do
		box(l, "prop", 0, D + 14 + r * 4, 133.3, 60, 0.6, 0.4, "scorch", deco)
	end
	point(l, "bets", 0, D + 0.5, 80)
	-- the four rigged odds machines along the hall: a red cabinet, its glowing gold dial and a lever
	for _, x in { -75, -25, 25, 75 } do
		add(l, "odds", x, D + 0.5, 30)
		local odds = look(l, "OddsMachine", x, D, 30)
		box(l, "prop", x, D + 4, 30, 6, 8, 4, "relicRed", art(odds))
		box(l, "glow", x, D + 6, 27.8, 4, 3, 0.4, "bank", art(odds))
		box(l, "prop", x + 3.6, D + 5, 30, 0.6, 4, 0.6, "steel", art(odds))
	end
	-- the gallery's rail over the Pit (waist high, a gap for the steps) and lamps along it
	box(l, "prop", -107, D + 1.5, -34, 178, 3, 1, "steel", deco)
	box(l, "prop", 107, D + 1.5, -34, 178, 3, 1, "steel", deco)
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D + 3.4, -34, 3, 0.6, 1.6, "workLamp", deco)
	end
	point(l, "stairhead", 0, D + 0.5, -28)
	-- the steps down: 9 steps of 2 studs from the gallery to the Pit's floor, rough rock either side
	for i = 1, 9 do
		local top = D - 2 * i
		box(l, "building", 0, top / 2, -39 - (i - 1) * 6, 32, top, 6, "rock")
	end
	point(l, "pitfloor", 0, 0.5, -100)
	-- the Pit's floor (packed sand) and the ring on its low stage: canvas, four corner posts, glowing ropes
	box(l, "plaza", 0, 0.1, -118, 396, 0.2, 160, "sand")
	local R, S = RING.size, RING.stage
	box(l, "building", 0, S / 2, RING.z, R, S, R, "roofBlue")
	box(l, "plaza", 0, S + 0.05, RING.z, R - 4, 0.1, R - 4, "white")
	local ropes = look(l, "RingRopes", 0, S, RING.z)
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		box(
			l,
			"prop",
			c[1] * (R / 2 - 1),
			S + 4,
			RING.z + c[2] * (R / 2 - 1),
			1.2,
			8,
			1.2,
			"steel",
			art(ropes)
		)
	end
	for _, y in { 3, 5.5, 8 } do
		for k = -1, 1, 2 do
			box(l, "glow", k * (R / 2 - 1), S + y, RING.z, 0.4, 0.4, R - 2, "relicRed", art(ropes))
			box(l, "glow", 0, S + y, RING.z + k * (R / 2 - 1), R - 2, 0.4, 0.4, "relicRed", art(ropes))
		end
	end
	point(l, "ring", 0, S + 0.5, RING.z + 8)
	point(l, "boss", 0, S + 0.5, RING.z - 6)
	-- four floodlights on tall poles at the ring's corners, their lamps over the canvas
	-- (each lamp hangs toward the ring: the look's lamp is at its -x, -z, turned to each corner)
	local FLOOD_TURN = { [-1] = { [-1] = 180, [1] = -90 }, [1] = { [-1] = 90, [1] = 0 } }
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local x, z = c[1] * (R / 2 + 10), RING.z + c[2] * (R / 2 + 10)
		local flood = look(l, "PitFlood", x, 0, z, FLOOD_TURN[c[1]][c[2]])
		box(l, "prop", x, 15, z, 1.5, 30, 1.5, "steel", art(flood))
		box(l, "glow", x - c[1] * 3, 30, z - c[2] * 3, 6, 2, 6, "beaconLight", art(flood))
	end
	-- the crowd's rock benches, three tiers round the west, east and north sides, and the family's box seat
	for t = 1, 3 do
		local hgt = t * 2
		local inset = 120 - (t - 1) * 12
		for k = -1, 1, 2 do
			box(l, "building", k * (inset + 6), hgt / 2, -122, 12, hgt, 140, "rock")
		end
		box(l, "building", 0, hgt / 2, -194 + (t - 1) * 12, 2 * inset, hgt, 12, "rock")
	end
	box(l, "building", 0, 4, -188, 30, 8, 10, "rock")
	local throne = look(l, "GoldThrone", 0, 8, -188)
	box(l, "prop", 0, 10, -188, 8, 4, 6, "bank", art(throne)) -- the Pitboss's gold chair
	box(l, "prop", 0, 13.5, -190.5, 8, 5, 1, "bank", art(throne))
	-- the crowd: cheering fans on the benches, facing the ring (PLACEHOLDER ART until Art.SetPieces is imported)
	local SHIRTS = { TOY.red, TOY.blue, TOY.gold, { 90, 200, 110 }, { 240, 120, 40 }, { 160, 90, 220 } }
	for i = 0, 11 do
		local k = if i % 2 == 0 then -1 else 1
		local t = (i // 2) % 3 + 1
		local z = -170 + (i // 6) * 60
		local x = k * (120 - (t - 1) * 12 + 6)
		local fan =
			look(l, "CrowdFan", x, t * 2, z, if k == 1 then 90 else -90, { FanShirt = SHIRTS[i % 6 + 1] })
		box(l, "prop", x, t * 2 + 2.5, z, 2, 3, 1.5, "scorch", art(fan))
	end
end

-- The deck, the back wall with its way down, the 9 steps and the sealed lower floor's ceiling that the origin
-- lines' two pockets share (the academy's shape): the deck over the south of the pocket at height D with its
-- floor skin, a back wall at z = -34 with a gap at its middle (`gapPoint`), 9 steps of 2 studs down to the
-- floor walled both sides, the lower floor's ceiling tagged so robots never stand on it, and `foot` at the
-- bottom of the steps
local function deckAndStairs(
	l: Layout,
	D: number,
	deckColor: string,
	skin: string,
	wall: string,
	stair: string,
	ceiling: string,
	gapPoint: string,
	foot: string
)
	box(l, "building", 0, D / 2, 80, 396, D, 232, deckColor)
	box(l, "plaza", 0, D + 0.1, 80, 396, 0.2, 232, skin)
	point(l, "spawn", 0, D + 3, 172)
	box(l, "building", -107, D + 18, -34, 178, 36, 4, wall)
	box(l, "building", 107, D + 18, -34, 178, 36, 4, wall)
	point(l, gapPoint, 0, D + 0.5, -28)
	for i = 1, 9 do
		local top = D - 2 * i
		box(l, "building", 0, top / 2, -39 - (i - 1) * 6, 32, top, 6, stair)
	end
	for k = -1, 1, 2 do
		box(l, "building", k * 18, D + 2, -70, 4, D + 4, 68, wall)
	end
	point(l, foot, 0, 0.5, -100)
	local ceil = { tag = "ceiling" }
	box(l, "building", -109, D + 2, -117, 178, 4, 162, ceiling, ceil)
	box(l, "building", 109, D + 2, -117, 178, 4, 162, ceiling, ceil)
	box(l, "building", 0, D + 2, -152, 40, 4, 92, ceiling, ceil)
end

-- Ashgrove Labs (lore step 11, the Lab origin line "The Ashgrove Test"): the lab that woke a Lab-Born hero's
-- Spark, open again in secret. The lab floor is a deck over the south of the pocket: reception west (room 1)
-- with its desk and waiting chairs, the records office east (room 2) with filing cabinets, and the test chamber
-- in the middle (`chamber`): the Kindler, a ring of eight light posts round a chair, under a glowing hood. The
-- back wall's sealed door (`sealDoor`) opens on the stairs down to the sublevel (`sublevel` is their foot), where
-- Doctor Holloway runs four new Kindlers (`kindlers`) beside holding tanks, his work desk and the boss spot
-- (`boss`).
-- PLACEHOLDER ART: greybox parts in the city palette, like every pocket.
local LAB_DECK = 20
function BUILD.ashlab(l: Layout, _Config: any)
	local D = LAB_DECK
	local deco = { tag = "decor", ghost = true }
	local glowPost = { shape = "cylinder", ghost = true, tag = "decor" }
	deckAndStairs(l, D, "concrete", "white", "white", "concrete", "slate", "sealDoor", "sublevel")
	-- the lab's sign over the entrance and a strip of blue lights along the front wall
	box(l, "glow", 0, D + 16, 195, 80, 6, 1, "beaconGlow", deco)
	for i = -4, 4 do
		box(l, "glow", i * 40, D + 0.4, 190, 6, 0.4, 2, "window", deco)
	end
	-- reception (room 1, west): the front desk and two rows of waiting chairs
	box(l, "building", -90, D + 11, 26, 4, 22, 32, "white")
	box(l, "building", -90, D + 11, 104, 4, 22, 32, "white")
	box(l, "building", -143, D + 11, 10, 106, 22, 4, "white")
	box(l, "building", -143, D + 11, 120, 106, 22, 4, "white")
	box(l, "prop", -150, D + 2, 65, 30, 4, 6, "steel", deco)
	box(l, "glow", -150, D + 4.2, 62.8, 26, 0.4, 0.4, "beaconGlow", deco)
	for r = 0, 1 do
		for c = 0, 3 do
			box(l, "prop", -120 - c * 12, D + 1.5, 90 + r * 12, 5, 3, 5, "roofBlue", deco)
		end
	end
	add(l, "rooms", -143, D + 0.5, 65)
	-- the records office (room 2, east): rows of filing cabinets and a shredder
	box(l, "building", 90, D + 11, 26, 4, 22, 32, "white")
	box(l, "building", 90, D + 11, 104, 4, 22, 32, "white")
	box(l, "building", 143, D + 11, 10, 106, 22, 4, "white")
	box(l, "building", 143, D + 11, 120, 106, 22, 4, "white")
	for c = 0, 3 do
		box(l, "prop", 120 + c * 18, D + 4, 30, 8, 8, 4, "steel", deco)
		box(l, "prop", 120 + c * 18, D + 4, 100, 8, 8, 4, "steel", deco)
	end
	box(l, "prop", 190, D + 2, 65, 4, 4, 8, "slate", deco)
	add(l, "rooms", 143, D + 0.5, 65)
	-- the test chamber: the Kindler, eight light posts in a ring round the test chair, a glowing hood over it
	box(l, "plaza", 0, D + 0.25, 50, 70, 0.3, 70, "slate")
	for i = 0, 7 do
		local a = i * math.pi / 4
		box(l, "prop", math.cos(a) * 22, D + 5, 50 + math.sin(a) * 22, 2, 10, 2, "steel", deco)
		box(l, "glow", math.cos(a) * 22, D + 10.5, 50 + math.sin(a) * 22, 3, 1, 3, "beaconGlow", glowPost)
	end
	box(l, "prop", 0, D + 1.5, 50, 4, 3, 4, "white", deco) -- the test chair
	box(l, "glow", 0, D + 18, 50, 16, 0.6, 16, "beaconGlow", glowPost) -- the hood
	point(l, "chamber", 0, D + 0.5, 50)
	-- the sealed door: a steel slab slid aside, a red warning light over it
	box(l, "prop", 26, D + 7, -30, 14, 14, 3, "steel", deco)
	box(l, "glow", 0, D + 15, -31.5, 6, 1.5, 0.5, "relicRed", deco)
	-- the sublevel: four new Kindlers (a ring of light round a steel plinth), holding tanks along the walls,
	-- Holloway's work desk and lamps under the ceiling
	for _, p in { { -120, -80 }, { -120, -150 }, { 120, -80 }, { 120, -150 } } do
		add(l, "kindlers", p[1], 0.5, p[2])
		box(l, "prop", p[1], 0.5, p[2], 9, 1, 9, "steel", deco)
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			box(l, "glow", p[1] + math.cos(a) * 6, 4, p[2] + math.sin(a) * 6, 1, 8, 1, "beaconGlow", deco)
		end
	end
	for i = -3, 3 do
		box(l, "prop", i * 40, 7, -194, 10, 14, 6, "glass", deco) -- a holding tank
		box(l, "glow", i * 40, 2, -194, 8, 1, 4, "nullGlow", deco)
	end
	box(l, "prop", 60, 2, -130, 20, 4, 8, "steel", deco) -- the work desk
	box(l, "glow", 60, 6, -133, 10, 4, 0.4, "window", deco)
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D - 0.6, -117, 10, 0.6, 3, "workLamp", deco)
	end
	point(l, "boss", 0, 0.5, -160)
end

-- Gale's Iron Hall (lore step 11, the Training origin line "The Taken Master"): the rival fight school where
-- Master Hoshi is held. The school's floor is a wooden deck over the south of the pocket: the locker room west
-- (room 1) with its benches, the trophy room east (room 2) with gold cups on shelves, and the training floor in
-- the middle (`hall`): red mats, punching bags and wooden dummies. The back wall's iron door (`ironDoor`) opens
-- on the stairs down to the inner dojo (`inner` is their foot): Master Hoshi's cage in the middle, held by four
-- chains to iron posts (`chains`), braziers along the walls and the boss spot (`boss`).
-- PLACEHOLDER ART: greybox parts in the city palette, like every pocket.
local HALL_DECK = 20
local CAGE = { x = 0, z = -140, half = 12 }
function BUILD.ironhall(l: Layout, _Config: any)
	local D = HALL_DECK
	local deco = { tag = "decor", ghost = true }
	deckAndStairs(l, D, "brick", "wood", "brick", "rock", "rock", "ironDoor", "inner")
	-- the school's banner over the entrance: a red cloth with a glowing fist mark
	box(l, "prop", 0, D + 16, 195, 60, 14, 1, "relicRed", deco)
	box(l, "glow", 0, D + 16, 194.4, 12, 8, 0.4, "foundryGlow", deco)
	-- the locker room (room 1, west): benches between two rows of lockers
	box(l, "building", -90, D + 11, 26, 4, 22, 32, "brick")
	box(l, "building", -90, D + 11, 104, 4, 22, 32, "brick")
	box(l, "building", -143, D + 11, 10, 106, 22, 4, "brick")
	box(l, "building", -143, D + 11, 120, 106, 22, 4, "brick")
	for c = 0, 4 do
		box(l, "prop", -110 - c * 16, D + 6, 18, 10, 12, 4, "steel", deco)
		box(l, "prop", -110 - c * 16, D + 6, 112, 10, 12, 4, "steel", deco)
	end
	box(l, "prop", -143, D + 1, 65, 60, 2, 4, "wood", deco)
	add(l, "rooms", -143, D + 0.5, 65)
	-- the trophy room (room 2, east): shelves of gold cups
	box(l, "building", 90, D + 11, 26, 4, 22, 32, "brick")
	box(l, "building", 90, D + 11, 104, 4, 22, 32, "brick")
	box(l, "building", 143, D + 11, 10, 106, 22, 4, "brick")
	box(l, "building", 143, D + 11, 120, 106, 22, 4, "brick")
	for r = 0, 2 do
		box(l, "prop", 194, D + 4 + r * 6, 65, 3, 0.6, 80, "wood", deco)
		for c = -3, 3 do
			box(l, "prop", 193, D + 5.6 + r * 6, 65 + c * 10, 2, 2.4, 2, "bank", deco)
		end
	end
	add(l, "rooms", 143, D + 0.5, 65)
	-- the training floor: red mats, four punching bags on chains and two wooden dummies
	box(l, "plaza", 0, D + 0.25, 50, 120, 0.3, 110, "roofRed")
	for _, p in { { -50, 10 }, { 50, 10 }, { -50, 90 }, { 50, 90 } } do
		box(l, "prop", p[1], D + 14, p[2], 0.6, 8, 0.6, "steel", deco)
		box(l, "prop", p[1], D + 7, p[2], 3, 6, 3, "rust", deco)
	end
	for _, x in { -20, 20 } do
		box(l, "prop", x, D + 3, 50, 1.5, 6, 1.5, "wood", deco)
		box(l, "prop", x, D + 5, 50, 5, 0.8, 0.8, "wood", deco)
	end
	box(l, "glow", -70, D + 18, -18, 6, 0.5, 6, "foundryGlow", deco)
	box(l, "glow", 70, D + 18, -18, 6, 0.5, 6, "foundryGlow", deco)
	point(l, "hall", 0, D + 0.5, 50)
	-- the iron door: a heavy slab slid aside
	box(l, "prop", 26, D + 7, -30, 14, 14, 3, "steel", deco)
	-- the inner dojo: Master Hoshi's cage on its plinth, four chains out to iron posts, braziers round the walls
	box(l, "building", CAGE.x, 1, CAGE.z, CAGE.half * 2, 2, CAGE.half * 2, "rock")
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		box(l, "prop", CAGE.x + c[1] * CAGE.half, 9, CAGE.z + c[2] * CAGE.half, 1, 14, 1, "steel", deco)
		local px, pz = CAGE.x + c[1] * (CAGE.half + 18), CAGE.z + c[2] * (CAGE.half + 18)
		add(l, "chains", px, 0.5, pz)
		box(l, "prop", px, 4, pz, 3, 8, 3, "steel", deco)
		local mx, mz = (px + CAGE.x + c[1] * CAGE.half) / 2, (pz + CAGE.z + c[2] * CAGE.half) / 2
		local chain = { tag = "decor", ghost = true, ry = 45 * c[1] * c[2] }
		box(l, "prop", mx, 7, mz, 0.6, 0.6, 26, "steel", chain)
	end
	box(l, "prop", CAGE.x, 16.5, CAGE.z, CAGE.half * 2, 1, CAGE.half * 2, "steel", deco) -- the cage's lid
	for _, p in { { -180, -80 }, { 180, -80 }, { -180, -180 }, { 180, -180 } } do
		box(l, "prop", p[1], 2, p[2], 4, 4, 4, "steel", deco)
		box(l, "glow", p[1], 4.6, p[2], 3, 1.2, 3, "foundryGlow", deco)
	end
	for _, x in { -150, -60, 60, 150 } do
		box(l, "glow", x, D - 0.6, -117, 10, 0.6, 3, "workLamp", deco)
	end
	point(l, "boss", 70, 0.5, -170)
end

-- Is this a pocket layout name? (lore step 10: side quest pocket steps are checked against it)
-- The Spark Pound (lore step 11, the character line Finding Lark): the Spark catcher Catchpole's pound in a Docks
-- warehouse, one floor under a steel roof. The loading dock and its roll door at the south (the spawn), the
-- intake office west (room 1: the desks and the scanner arch every caught Spark walks through), the kennel hall
-- in the middle (six cages either side of the aisle: the hold), four collar scanners on posts across the hall
-- (the break list), the warden's floor, and Lark's cell at the north end under a red lamp. PLACEHOLDER ART:
-- greybox parts, cages of thin bars.
function BUILD.pound(l: Layout, _Config: any)
	local deco = { tag = "decor", ghost = true }
	local H = 28
	-- the warehouse: a concrete floor skin, a steel roof (robots never stand on it) and the north wall
	box(l, "plaza", 0, 0.1, 0, 396, 0.2, 396, "concrete")
	box(l, "building", 0, H + 1, 0, 400, 2, 400, "steel", { tag = "ceiling" })
	box(l, "building", 0, H / 2, -186, 396, H, 4, "tunnel")
	-- the loading dock: the roll door (glowing slats), a dock edge and two stacked crates
	box(l, "glow", 0, 9, 196, 40, 18, 1, "window", deco)
	for r = 0, 4 do
		box(l, "prop", 0, 2 + r * 3.5, 195.2, 40, 0.5, 0.4, "steel", deco)
	end
	for _, x in { -40, 40 } do
		box(l, "prop", x, 3, 176, 10, 6, 10, "cargo", deco)
	end
	-- the intake office, west (room 1): two desks with screens and the scanner arch
	for i = 0, 1 do
		local z = 70 + i * 40
		box(l, "prop", -130, 2, z, 16, 4, 6, "wood", deco)
		box(l, "glow", -130, 6, z - 2, 6, 4, 0.4, "beaconGlow", deco)
	end
	for k = -1, 1, 2 do
		box(l, "prop", -90 + k * 6, 7, 90, 1.5, 14, 1.5, "steel", deco)
	end
	box(l, "glow", -90, 14.5, 90, 13.5, 1, 1.5, "relicRed", deco)
	add(l, "rooms", -130, 0.5, 90)
	-- the partition between the dock and the hall, with a wide gap in the middle
	for k = -1, 1, 2 do
		box(l, "building", k * 118, H / 2, 40, 160, H, 3, "tunnel")
	end
	-- the kennel hall: six cages either side of the aisle (four corner bars, a top and three front bars each)
	for side = -1, 1, 2 do
		for i = 0, 5 do
			local x, z = side * (40 + (i % 3) * 36), -20 - (i // 3) * 40
			for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
				box(l, "prop", x + c[1] * 14, 7, z + c[2] * 14, 0.8, 14, 0.8, "steel", deco)
			end
			box(l, "prop", x, 14.2, z, 29, 0.4, 29, "steel", deco)
			for b = -1, 1 do
				box(l, "prop", x + b * 7, 7, z + 14, 0.4, 14, 0.4, "steel", deco)
			end
		end
	end
	box(l, "glow", 0, H - 0.6, -40, 6, 0.6, 120, "workLamp", deco) -- the aisle's strip light
	point(l, "kennels", 0, 0.5, -30)
	-- the four collar scanners across the hall: a post, its glowing ring and a red lamp on top
	for _, x in { -150, -100, 100, 150 } do
		add(l, "collars", x, 0.5, 20)
		box(l, "prop", x, 4, 20, 2, 8, 2, "steel", deco)
		box(l, "glow", x, 8.6, 20, 5, 1.2, 5, "beaconGlow", deco)
		box(l, "glow", x, 9.6, 20, 1, 1, 1, "relicRed", deco)
	end
	-- the warden's floor before Lark's cell, and the cell itself: a big cage on a low step under a red lamp
	point(l, "boss", 0, 0.5, -112)
	box(l, "building", 0, 0.5, -160, 44, 1, 30, "slate")
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		box(l, "prop", c[1] * 20, 9, -160 + c[2] * 13, 1, 16, 1, "steel", deco)
	end
	for b = -3, 3 do
		box(l, "prop", b * 5, 9, -147, 0.5, 16, 0.5, "steel", deco)
	end
	box(l, "prop", 0, 17.2, -160, 42, 0.4, 28, "steel", deco)
	box(l, "glow", 0, H - 0.6, -160, 4, 0.6, 4, "relicRed", deco)
	point(l, "cell", 0, 1.5, -150)
end

function PocketLayout.known(layout: any): boolean
	return type(layout) == "string" and BUILD[layout] ~= nil
end

function PocketLayout.build(Config: any, index: number, layout: string): Layout
	local cx, cy, cz = PocketLayout.centre(Config, index)
	local l: Layout = {
		index = index,
		cx = cx,
		cy = cy,
		cz = cz,
		boxes = {},
		points = {},
		lists = {},
		floorY = cy,
		art = {},
	}

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

-- The underside of the lowest ceiling over (x, z) above height y in a pocket (a tunnel's or a room's roof, the
-- boxes tagged "ceiling"), or nil for open sky. Fliers stay under it (Shared.EnemySim's ceilingAt).
function PocketLayout.ceilingAt(l: Layout, x: number, z: number, y: number): number?
	local list = (l :: any).ceilings
	if not list then
		list = {}
		for _, b in l.boxes do
			if b.tag == "ceiling" then
				table.insert(list, b)
			end
		end
		(l :: any).ceilings = list
	end
	local best: number? = nil
	for _, b in list do
		local under = b.cy - b.sy / 2
		if under >= y and math.abs(x - b.cx) <= b.sx / 2 and math.abs(z - b.cz) <= b.sz / 2 then
			if not best or under < best then
				best = under
			end
		end
	end
	return best
end

return PocketLayout
