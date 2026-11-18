--!strict
-- SideQuestSets: the set pieces side quest chains stand in Downtown's open squares (nate's lore, build plan
-- step 11, chain 2: The Gala Heist with Rooftop Racers). Pure, so Lune checks every set's size, its parts
-- budget and that it keeps clear of the square's own benches, planters and lamps; SideQuestService builds the
-- parts on the server (so every device sees the same thing) and makes each breakable piece a combat target
-- that breaks like the incidents' objects (it bursts into falling chunks) and is put back up a while later.
-- * build(id): { boxes, pieces, points }. A box: x, y, z (its centre, studs from the square's middle and up
--   from its paving), sx, sy, sz, color { r, g, b }, mat (a Roblox material name), shape ("cylinder" along x,
--   "ball"; upright: a cylinder standing on end, sx its height), alpha (transparency), ghost (no collision),
--   tilt (degrees about x), sign (fixed text the server writes on both faces), piece (the breakable piece it
--   belongs to). -z is the square's back.
-- * pieces: id -> { x, y, z, r } (the hit sphere round the piece's boxes); points: named spots (the stage,
--   the seats, the start line, the podium) and lists (exhibits, cars).
-- * check(Config, id, size): the boxes stay inside the square's paved middle (inner) so the square's
--   own dressing (CityLayout openBlock: benches and planters at block / 2 - 16, lamps at the kerb) is untouched.
-- * art: the Blender looks over the boxes (Shared.SetPieceKit placements; a box's `art` is its placement's
--   index): drawn as meshes once nate imports ReplicatedStorage.Art.SetPieces, the boxes then hidden but kept
--   (they still collide and make up the breakable pieces); until then the boxes are drawn as below.
-- PLACEHOLDER ART: plain parts in the city palette until nate imports Art.SetPieces (art/blender/setpieces.py).

local SetPieceKit = if script then require(script.Parent.SetPieceKit) else (require :: any)("./SetPieceKit")

local SideQuestSets = {}

export type Box = {
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: { number },
	mat: string?,
	shape: string?,
	alpha: number?,
	ghost: boolean?,
	tilt: number?,
	upright: boolean?,
	sign: string?,
	piece: string?,
	art: number?,
}

export type Set = {
	boxes: { Box },
	pieces: { [string]: { x: number, y: number, z: number, r: number } },
	points: { [string]: { number } },
	lists: { [string]: { { number } } },
	art: { SetPieceKit.Place },
}

-- the palette (the city's own colours)
local C = {
	crimson = { 160, 30, 45 },
	cream = { 245, 236, 214 },
	gold = { 230, 190, 60 },
	navy = { 30, 40, 90 },
	wood = { 110, 70, 45 },
	marble = { 235, 232, 226 },
	glass = { 200, 235, 255 },
	gem = { 120, 230, 255 },
	ruby = { 255, 70, 110 },
	white = { 245, 245, 245 },
	black = { 28, 28, 32 },
	charcoal = { 55, 58, 66 },
	red = { 220, 40, 40 },
	amber = { 255, 170, 40 },
	green = { 60, 220, 90 },
	blue = { 40, 110, 220 },
	yellow = { 250, 210, 40 },
	pink = { 255, 60, 140 },
	steel = { 120, 125, 135 },
	tyre = { 36, 36, 40 },
	fuel = { 200, 60, 40 },
}

local function add(s: Set, x, y, z, sx, sy, sz, color, opts: { [string]: any }?)
	local b: Box = { x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, color = color }
	for k, v in opts or {} do
		(b :: any)[k] = v
	end
	table.insert(s.boxes, b)
end

-- A Blender look standing over the boxes that take its index as `art` (Shared.SetPieceKit)
local function look(
	s: Set,
	name: string,
	x: number,
	y: number,
	z: number,
	ry: number?,
	piece: string?,
	tint: { [string]: { number } }?
): number
	return SetPieceKit.place(s.art, name, x, y, z, ry, piece, tint)
end

local BUILD: { [string]: (s: Set) -> () } = {}

-- The Museum Gala (OpenNorth): the City Museum's treasures under a striped marquee and, at the back, the
-- opera's open-air stage with its curtains and spotlights; a red carpet in from the street side.
function BUILD.gala(s: Set)
	-- the red carpet and the entrance sign
	add(s, 0, 0.1, 16, 6, 0.2, 30, C.crimson, { mat = "Fabric", ghost = true })
	local arch = look(s, "GalaArch", 0, 0, 31)
	add(s, -8, 6, 31, 1, 12, 1, C.gold, { art = arch })
	add(s, 8, 6, 31, 1, 12, 1, C.gold, { art = arch })
	add(s, 0, 11, 31, 16, 3.4, 0.6, C.cream, { sign = "THE MUSEUM GALA" })
	-- the opera stage: a deck, its gold trim and steps, the proscenium, the curtains and the backdrop
	local stage = look(s, "GalaStage", 0, 0, -26)
	add(s, 0, 2, -26, 40, 4, 12, C.wood, { mat = "Wood", art = stage })
	add(s, 0, 3.9, -19.9, 40, 0.4, 0.4, C.gold, { mat = "Neon", art = stage })
	add(s, 0, 1, -18.5, 10, 2, 3, C.wood, { mat = "Wood", art = stage })
	add(s, -20, 10, -31, 3, 16, 3, C.cream, { art = stage })
	add(s, 20, 10, -31, 3, 16, 3, C.cream, { art = stage })
	add(s, 0, 19.5, -31, 43, 3, 3, C.gold, { art = stage })
	local cl = look(s, "GalaCurtain", -13, 6, -30, 0, "curtainL")
	local cr = look(s, "GalaCurtain", 13, 6, -30, 180, "curtainR")
	add(s, -13, 12, -30, 10, 12, 1, C.crimson, { mat = "Fabric", piece = "curtainL", art = cl })
	add(s, 13, 12, -30, 10, 12, 1, C.crimson, { mat = "Fabric", piece = "curtainR", art = cr })
	add(s, 0, 12, -32.6, 37, 16, 0.6, C.navy, { mat = "Fabric", art = stage })
	-- the marquee: four poles, a striped canopy, a gold ridge and a valance over the way in
	for _, p in { { -24, -14 }, { 24, -14 }, { -24, 24 }, { 24, 24 } } do
		add(s, p[1], 8, p[2], 1, 16, 1, C.white, { art = look(s, "MarqueePole", p[1], 0, p[2]) })
	end
	local canopy = look(s, "GalaCanopy", 0, 15, 5, 0, "canopy")
	for i, x in { -18, -6, 6, 18 } do
		add(
			s,
			x,
			16.3,
			5,
			12,
			0.6,
			40,
			if i % 2 == 1 then C.crimson else C.cream,
			{ mat = "Fabric", piece = "canopy", art = canopy }
		)
	end
	add(s, 0, 16.8, 5, 49, 0.6, 1, C.gold, { piece = "canopy", art = canopy })
	add(s, 0, 15, 25, 48, 2, 0.4, C.gold, { mat = "Fabric", piece = "canopy", art = canopy })
	-- the chandelier under the canopy
	local ch = look(s, "GalaChandelier", 0, 10.8, 5, 0, "chandelier")
	add(s, 0, 15, 5, 0.3, 2, 0.3, C.gold, { piece = "chandelier", art = ch })
	add(
		s,
		0,
		13.6,
		5,
		0.6,
		8,
		8,
		C.gold,
		{ shape = "cylinder", upright = true, piece = "chandelier", art = ch }
	)
	add(s, 0, 12.6, 5, 2.4, 2.4, 2.4, C.gem, { shape = "ball", mat = "Neon", piece = "chandelier", art = ch })
	add(s, 0, 11.4, 5, 1.2, 1.2, 1.2, C.gem, { shape = "ball", mat = "Neon", piece = "chandelier", art = ch })
	-- the museum's treasures: four plinths with glass cases and a jewel in each
	s.lists.exhibits = {}
	for i, p in { { -16, -2 }, { 16, -2 }, { -16, 14 }, { 16, 14 } } do
		local id = "case" .. i
		local jewel = if i % 2 == 0 then C.ruby else C.gem
		local case = look(s, "ExhibitCase", p[1], 0, p[2], 0, id, { CaseJewel = jewel })
		add(s, p[1], 1.5, p[2], 4, 3, 4, C.marble, { mat = "Marble", piece = id, art = case })
		add(
			s,
			p[1],
			4.6,
			p[2],
			3.6,
			3.2,
			3.6,
			C.glass,
			{ mat = "Glass", alpha = 0.55, piece = id, art = case }
		)
		add(
			s,
			p[1],
			4.3,
			p[2],
			1.4,
			1.4,
			1.4,
			jewel,
			{ shape = "ball", mat = "Neon", piece = id, art = case }
		)
		table.insert(s.lists.exhibits, { p[1], 0, p[2] })
	end
	-- the opera's seats (velvet benches) facing the stage
	for _, z in { -12, -6, 0 } do
		add(s, 0, 1, z, 18, 2, 2, C.crimson, { mat = "Fabric", art = look(s, "VelvetBench", 0, 0, z) })
	end
	-- the spotlights at the stage's corners
	for k, x in { -24, 24 } do
		local id = if k == 1 then "spotL" else "spotR"
		local spot = look(s, "GalaSpot", x, 0, -21, if k == 1 then 0 else 180, id)
		add(s, x, 5, -21, 1, 10, 1, C.charcoal, { piece = id, art = spot })
		add(s, x, 10.5, -21, 2.5, 2, 3, C.cream, { mat = "Neon", piece = id, art = spot })
	end
	s.points.stage = { 0, 4, -26 }
	s.points.seats = { 0, 0, -6 }
	s.points.door = { 0, 0, 30 }
end

-- The Racers' Meet (OpenWest): Redline's crew's start line under a gantry with its start lights, three
-- parked racers, tyre stacks, fuel drums, a DJ booth, two floodlights and a kicker ramp.
function BUILD.meet(s: Set)
	-- the chequered start line
	for i = 0, 7 do
		add(s, -14 + i * 4, 0.1, 0, 4, 0.2, 4, if i % 2 == 0 then C.black else C.white, { ghost = true })
	end
	-- the gantry over it: two pylons, the beam, the banner and the start lights
	local gantry = look(s, "StartGantry", 0, 0, 0)
	add(s, -18, 9, 0, 3, 18, 3, C.charcoal, { art = gantry })
	add(s, 18, 9, 0, 3, 18, 3, C.charcoal, { art = gantry })
	add(s, 0, 19.5, 0, 39, 3, 3, C.red, { art = gantry })
	add(s, 0, 19.5, 1.8, 24, 2.6, 0.4, C.white, { sign = "THE RACERS' MEET" })
	local lights = look(s, "StartLights", 0, 17, 0, 0, "lights")
	for i, col in { C.red, C.amber, C.green } do
		add(
			s,
			-6 + (i - 1) * 6,
			17,
			0,
			2,
			2,
			2,
			col,
			{ shape = "ball", mat = "Neon", piece = "lights", art = lights }
		)
	end
	-- three parked racers: a body, a cockpit and a spoiler
	s.lists.cars = {}
	for i, p in { { -20, 18, C.red }, { 0, 21, C.blue }, { 20, 18, C.yellow } } do
		local id = "car" .. i
		local car = look(s, "Racer", p[1], 0, p[2], 0, id, { RacerBody = p[3] })
		add(s, p[1], 1.5, p[2], 6, 2, 11, p[3], { piece = id, art = car })
		add(
			s,
			p[1],
			3.2,
			p[2] - 0.5,
			4,
			1.6,
			4,
			C.black,
			{ mat = "Glass", alpha = 0.2, piece = id, art = car }
		)
		add(s, p[1], 4.3, p[2] + 5, 6, 0.4, 1.6, C.black, { piece = id, art = car })
		table.insert(s.lists.cars, { p[1], 0, p[2] })
	end
	-- tyre stacks
	for i, p in { { -28, -18 }, { 28, -18 }, { -28, 30 } } do
		local id = "tyres" .. i
		local stack = look(s, "TyreStack", p[1], 0, p[2], 0, id)
		for k = 0, 1 do
			add(
				s,
				p[1],
				0.8 + k * 1.6,
				p[2],
				1.6,
				4.5,
				4.5,
				C.tyre,
				{ shape = "cylinder", upright = true, piece = id, art = stack }
			)
		end
	end
	-- fuel drums
	for _, p in { { 24, -27 }, { 27.5, -25 }, { 24, -23 }, { 27.5, -29 } } do
		local drum = look(s, "FuelDrum", p[1], 0, p[2], 0, "drums")
		add(
			s,
			p[1],
			1.5,
			p[2],
			3,
			3.2,
			3.2,
			C.fuel,
			{ shape = "cylinder", upright = true, piece = "drums", art = drum }
		)
	end
	-- the DJ booth: a desk, two speakers and a neon strip
	local booth = look(s, "DJBooth", 0, 0, -24, 0, "booth")
	add(s, 0, 2, -24, 10, 4, 4, C.charcoal, { piece = "booth", art = booth })
	add(s, -8, 3, -24, 3, 6, 3, C.black, { piece = "booth", art = booth })
	add(s, 8, 3, -24, 3, 6, 3, C.black, { piece = "booth", art = booth })
	add(s, 0, 2.2, -21.9, 10, 0.4, 0.2, C.pink, { mat = "Neon", piece = "booth", art = booth })
	-- floodlights at the street corners of the square's middle
	for k, x in { -30, 30 } do
		local id = if k == 1 then "floodL" else "floodR"
		local flood = look(s, "Floodlight", x, 0, 30, 0, id)
		add(s, x, 10, 30, 1, 20, 1, C.steel, { piece = id, art = flood })
		add(s, x, 20.5, 29, 4, 2, 2, C.white, { mat = "Neon", piece = id, art = flood })
	end
	-- the kicker ramp the racers launch off (solid: it is for jumping, not breaking)
	local ramp = look(s, "KickerRamp", 22, 0, 0)
	add(s, 22, 1, 2, 10, 2, 6, C.steel, { mat = "DiamondPlate", art = ramp })
	add(s, 22, 2.6, -6, 10, 1, 12, C.yellow, { mat = "DiamondPlate", tilt = 18, art = ramp })
	s.points.start = { 0, 0, 0 }
	s.points.podium = { 0, 0, 10 }
	s.points.booth = { 0, 0, -24 }
end

-- Is this a set name?
function SideQuestSets.known(id: any): boolean
	return type(id) == "string" and BUILD[id] ~= nil
end

local cache: { [string]: Set } = {}

-- A set's boxes, breakable pieces and spots (the same every call; callers must not change it)
function SideQuestSets.build(id: string): Set
	local hit = cache[id]
	if hit then
		return hit
	end
	local s: Set = { boxes = {}, pieces = {}, points = {}, lists = {}, art = {} }

	BUILD[id](s)
	-- each piece's hit sphere: round the middle of its boxes, out to their far corners
	local sums: { [string]: { number } } = {}
	for _, b in s.boxes do
		if b.piece then
			local t = sums[b.piece]
				or { 0, 0, 0, 0, math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge }
			t[1] += b.x
			t[2] += b.y
			t[3] += b.z
			t[4] += 1
			local h = math.max(b.sx, b.sy, b.sz) / 2
			t[5], t[6] = math.min(t[5], b.x - h), math.max(t[6], b.x + h)
			t[7], t[8] = math.min(t[7], b.y - h), math.max(t[8], b.y + h)
			t[9], t[10] = math.min(t[9], b.z - h), math.max(t[10], b.z + h)
			sums[b.piece] = t
		end
	end
	for pid, t in sums do
		local cx, cy, cz = (t[5] + t[6]) / 2, (t[7] + t[8]) / 2, (t[9] + t[10]) / 2
		local r = math.max(t[6] - t[5], t[8] - t[7], t[10] - t[9]) / 2
		s.pieces[pid] = { x = cx, y = cy, z = cz, r = math.max(3, math.min(r, 14)) }
	end
	cache[id] = s
	return s
end

-- The footprint half-width a box covers (a tilted or round box by its largest side)
local function reach(b: Box): (number, number)
	if b.tilt or b.shape then
		local m = math.max(b.sx, b.sy, b.sz) / 2
		return m, m
	end
	return b.sx / 2, b.sz / 2
end

-- Problems with a set in an open square of `size` studs (empty when it is fine): every box inside the
-- square's middle, clear of its own benches and planters (CityLayout openBlock: at size / 2 - 16), under the
-- part budget, and each breakable piece with at least one box
function SideQuestSets.check(Config: any, id: string, size: number): { string }
	local bad = {}
	if not SideQuestSets.known(id) then
		return { "unknown set " .. tostring(id) }
	end
	local s = SideQuestSets.build(id)
	local S = Config.SideQuests.sets
	if #s.boxes > S.parts then
		table.insert(bad, string.format("%s: %d parts (budget %d)", id, #s.boxes, S.parts))
	end
	local inner = size / 2 - 16 - S.clear -- the bench and planter ring, less a walkway
	for i, b in s.boxes do
		local hx, hz = reach(b)
		if math.abs(b.x) + hx > inner or math.abs(b.z) + hz > inner then
			table.insert(bad, string.format("%s box %d reaches the square's benches", id, i))
		end
		local hy = if b.upright then b.sx / 2 else b.sy / 2
		if b.y - hy < -0.01 and not b.tilt then
			table.insert(bad, string.format("%s box %d is under the paving", id, i))
		end
		if b.sign and (#b.sign > 24 or string.find(b.sign, "%", 1, true)) then
			table.insert(bad, string.format("%s box %d sign", id, i))
		end
	end
	return bad
end

return SideQuestSets
