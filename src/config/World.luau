-- World: the seeded outskirts, landmarks, safehouses and fast-travel beacons (spec: Map layout; Procedural
-- outskirts; Movement kit > Fast travel; Defeat and death > Banking; Server lifecycle step 3). Tile (tx, tz)
-- covers x = -2,400 + tx * 100 to +100 (and the same for z); -z is north. The hub is tiles 16 to 31 on both
-- axes and never changes with the weekly seed. (tune)
return {
	tiles = 48, -- 48 x 48 tiles of Config.City.tile (100) studs
	hubFirst = 16,
	hubLast = 31,
	-- Zone rings, counted in tiles out from the hub edge (1 = the first tile outside the hub, 16 = the map
	-- edge). Suburbs 1 to 7, farmland 8 to 14, coast the last 2 (spec: "Coast: last 2 tiles").
	rings = { suburbsTo = 7, farmlandTo = 14 },
	zones = { hub = 0, suburbs = 1, farmland = 2, coast = 3, landmark = 4, hubFill = 5 },
	variants = { suburbs = 12, farmland = 10, coast = 4, hubFill = 6 },
	special = 31, -- variant 31 marks a hand-placed tile (an outskirts safehouse or the windmill beacon)
	roads = {
		highwayEvery = 6, -- a tile column or row whose index is a multiple of 6 carries a highway
		localEvery = 3, -- and a multiple of 3 a local road
		highwayWidth = 30,
		localWidth = 16,
		lineWidth = 1,
	},
	partsPerTile = 25, -- the average a tile may create (spec: about 51,000 parts for the outskirts)
	buildPerFrame = 40, -- tiles built per server frame (spec: Server lifecycle step 3)
	buildBudget = 20, -- seconds the whole outskirts may take
	-- Landmarks at fixed tiles (4 x 4 tiles each). The Crater is the forced PvP zone in M8.
	landmarks = {
		{ id = "CometCrater", name = "The Crater", tx = 36, tz = 6, size = 4 }, -- northeast
		{ id = "RadioHill", name = "Radio Hill", tx = 4, tz = 22, size = 4 }, -- west
		{ id = "OldQuarry", name = "Old Quarry", tx = 22, tz = 38, size = 4 }, -- south
	},
	-- The Crater (nate's lore, build plan step 9): where a Crane Industries research lab blew up in the battle where
	-- the old heroes fell. The blast ring (rim) and floor stay as they were (zone bounds, the beacon on the south
	-- rim, the PvP square); the floor is dressed as the lab's ruins and the battle's wreckage (WorldGen.landmark).
	-- Offsets are studs from the Crater's centre (x east, z north); heights from the floor. Everything stays
	-- under `maxTop` (the rim is 26) and nothing over `openTop` stands within `openRadius` of the centre, so
	-- fliers see across the whole bowl and the middle is an open fighting floor. `parts` caps the landmark.
	-- The lab's ruins wear art/blender/crater.py's meshes over these boxes once Art.Crater is imported (gap-wrecks,
	-- 2026-11-19; Shared.CraterArtKit, `art` below): the boxes stay as they are, hidden, for collision.
	crater = {
		rimHeight = 26,
		rimWidth = 30,
		floorDepth = 0,
		parts = 90, -- the landmark's part cap (was 21: floor, 16 rim rocks, the old glow core and 3 glow posts)
		maxTop = 22,
		openRadius = 30,
		openTop = 3,
		-- the lab's scorched foundation (a slab, top 1.8 above the floor); its walls stand on its edges
		foundation = { w = 120, d = 84, h = 1.2 },
		-- broken wall stretches: centre x, z, length, height, along ("x" or "z"); jag = a stub on top
		-- { dx, length, height } that leaves the top ragged. `logo` puts the Crane C on its outward face.
		walls = {
			{ x = -45, z = 42, len = 26, h = 14, along = "x", jag = { -6, 9, 4 } },
			{ x = -14, z = 42, len = 16, h = 7, along = "x", jag = { 3, 6, 3 } },
			{ x = 30, z = 42, len = 30, h = 12, along = "x", jag = { 9, 8, 5 }, logo = 1 },
			{ x = -38, z = -42, len = 24, h = 10, along = "x", jag = { 5, 8, 3 } },
			{ x = 26, z = -42, len = 22, h = 13, along = "x", jag = { -5, 7, 4 }, logo = -1 },
			{ x = -60, z = 10, len = 30, h = 12, along = "z", jag = { -7, 9, 4 } },
			{ x = 60, z = -14, len = 24, h = 9, along = "z", jag = { 6, 7, 3 } },
		},
		wallThick = 2,
		-- the Crane Industries C mark (original): a navy plate with a white C, `size` studs, its centre `at` up
		logo = { size = 8, at = 7, bar = 1.4 },
		-- cracked containment tanks on the foundation: a broken glass shell, the faint Spark glow left inside and a
		-- shard of the shell on the floor beside it
		tanks = {
			{ x = -34, z = 24, r = 4.5, h = 7, glow = 9, shard = { 5, -2, 40 } },
			{ x = -10, z = 34, r = 5, h = 5, glow = 8, shard = { -4, 2, -20 } },
			{ x = 18, z = 31, r = 4, h = 8, glow = 10, shard = { 4, 3, 70 } },
		},
		-- toppled lab towers, blown over outward (ry points the top away from the lab): a shaft (w x h x length) on
		-- the floor, its crown broken off past the top and its mast lying beside it
		towers = {
			{ x = -80, z = -50, ry = -122, w = 16, h = 12, len = 70 },
			{ x = 84, z = 56, ry = 56, w = 14, h = 11, len = 56 },
		},
		-- burn scars radiating from the blast: `n` dark strips from `from` to `to` studs out. Since gap-fx3 (2026-11-19)
		-- each wears a comic burn scar decal (art/fx/textures.py --scars, uploaded as Image assets) on its top face,
		-- taking turns through `decals` (the image's left end at the blast); the strip itself is hidden then (a mark:
		-- never collides or queries either way). id 0 keeps today's dark strip.
		scars = {
			n = 10,
			from = 48,
			to = 160,
			width = 5,
			decals = {
				{ id = 73344202395342, file = "scar_1.png" },
				{ id = 76818744119840, file = "scar_2.png" },
				{ id = 120924241999489, file = "scar_3.png" },
			},
		},
		-- the floor's and rim's ground (gap-fx3, 2026-11-19; art/city/crater_materials.py, MaterialVariants
		-- "Kit" .. name with an Organic pattern so the big floor never shows a grid): the blasted, cracked ash floor
		-- and the upthrown rock strata of the rim, drawn in their own colours. Until a variant is in MaterialService
		-- the box keeps its kit (CaveRock). Looks only: the boxes are exactly as before.
		ground = { floor = "CraterFloor", rim = "CraterRim" },
		-- robot husks from the battle (angle in degrees, distance out, ry): a torso lying down and its head
		husks = {
			{ a = 20, d = 92, ry = 30 },
			{ a = 115, d = 128, ry = -50 },
			{ a = 200, d = 104, ry = 80 },
			{ a = 255, d = 138, ry = 10 },
			{ a = 320, d = 84, ry = -15 },
		},
		-- the old heroes' relics where they made their stand, west of the lab (original designs): a torn red cape
		-- on a bent rebar, a cracked blue shield emblem with a gold chevron, a dented gold helmet half buried
		relics = {
			cape = { x = -76, z = 22, rebar = 12 },
			shield = { x = -70, z = 2, w = 8, d = 6, ry = 25 },
			helmet = { x = -84, z = -14, size = 5 },
		},
		-- the Blender looks (gap-wrecks, 2026-11-19; art/blender/crater.py, Shared.CraterArtKit, Config.CraterArt): every
		-- wall, fallen chunk, tank, tower, husk and relic is drawn over its boxes (hidden, kept for collision) once
		-- imported. `bits`: the loose debris looks each device scatters on the floor (weights), Config.Presets
		-- <preset>.ruins.bits of them (none on phones), seeded by `seed`, from ring[1] to ring[2] studs out, `pad`
		-- studs clear of every placement and `apart` studs from each other; ghosts, all under 2 studs tall
		art = {
			bits = { CraterBitRubble = 4, CraterBitPipes = 2, CraterBitConsole = 1, CraterBitPlates = 2 },
			tris = 90000, -- the lab's meshes may draw at most this many triangles (art/blender/crater.py; tests)
			seed = 9119,
			ring = { 36, 158 },
			pad = 2,
			apart = 7,
		},
	},
	radioHill = { steps = 6, stepHeight = 14, mastHeight = 120, rings = 6 },
	quarry = { wallHeight = 60, terraces = 3, terraceWidth = 24 },
	coast = { sandWidth = 200, oceanWidth = 2000, waterY = -1 },
	weekSeed = { epochNote = "ISO year x 100 + ISO week; changes Monday 00:00 UTC" },
	-- Safehouses: 12 in the hub and 4 in the outskirts. Each has a bank, a loadout and a respawn terminal and
	-- 3 respawn points; PvP is off within safeRadius (M8). Downtown ones sit on a reserved lot
	-- (block x, block z, lot x, lot z of the Downtown grid); the rest are at fixed points.
	safehouses = {
		{ id = 1, name = "Plaza West", district = "Downtown", lot = { 2, 3, 1, 1 } },
		{ id = 2, name = "Tower Row", district = "Downtown", lot = { 4, 2, 2, 1 } },
		{ id = 3, name = "Ledger Street", district = "Downtown", lot = { 2, 1, 2, 2 } },
		{ id = 4, name = "Glass Mile", district = "Downtown", lot = { 4, 5, 1, 2 } },
		{ id = 5, name = "Quay Gate", district = "Docks", x = 60, z = 360 },
		{ id = 6, name = "Gantry Yard", district = "Docks", x = 520, z = 380 },
		{ id = 7, name = "Foundry Lane", district = "Docks", x = 380, z = 740 },
		{ id = 8, name = "Clock Square", district = "OldTown", x = 300, z = -400 },
		{ id = 9, name = "Lantern Row", district = "OldTown", x = 600, z = -200 },
		{ id = 10, name = "Mill Bridge", district = "OldTown", x = 200, z = -640 },
		{ id = 11, name = "North Park", district = "Hub", x = -400, z = -600 },
		{ id = 12, name = "South Park", district = "Hub", x = -400, z = 720 }, -- z 620 until 2026-11-19 (Downtown grew south)
		{ id = 13, name = "Northgate", district = "Outskirts", tile = { 23, 11 } },
		{ id = 14, name = "Eastfield", district = "Outskirts", tile = { 35, 23 } },
		{ id = 15, name = "Southmoor", district = "Outskirts", tile = { 23, 35 } },
		{ id = 16, name = "Westbrook", district = "Outskirts", tile = { 11, 23 } },
	},
	safehouse = {
		pad = 36, -- the pad is 36 x 36 studs
		safeRadius = 40,
		terminalRange = 10, -- the prompt distance
		bankHold = 3, -- seconds held at the bank terminal (spec: "banked in 3 s at any safehouse terminal")
		bankBuffer = 500, -- Credits above this are "on hand" (spec: Banking)
		respawnPoints = 3,
		homeSafehouse = 1, -- a new hero's respawn point until they reach another
	},
	-- Fast-travel beacons (spec: 12 rooftop and landmark beacons, discovered by touching). "roof" puts the
	-- beacon on the tallest roof within 60 studs of (x, z); "safehouse" on that safehouse's roof; a landmark
	-- id on that landmark's high point.
	beacons = {
		{ id = 1, name = "Crane's Hero Hall", at = "plaza" }, -- the Beacon Tower (lore Q1: Crane's Hero Hall)
		{ id = 2, name = "Downtown East", at = "roof", x = -150, z = 150 },
		{ id = 3, name = "Harbour Gantry", at = "crane" },
		{ id = 4, name = "Clock Tower", at = "clock" },
		{ id = 5, name = "The Crater", at = "CometCrater" },
		{ id = 6, name = "Radio Hill", at = "RadioHill" },
		{ id = 7, name = "Old Quarry", at = "OldQuarry" },
		{ id = 8, name = "Northgate", at = "safehouse", safehouse = 13 },
		{ id = 9, name = "Eastfield", at = "safehouse", safehouse = 14 },
		{ id = 10, name = "Southmoor", at = "safehouse", safehouse = 15 },
		{ id = 11, name = "Westbrook", at = "safehouse", safehouse = 16 },
		{ id = 12, name = "Windmill", at = "tile", tile = { 40, 40 } },
	},
	beacon = {
		touchRadius = 14, -- discovered when a hero comes this close
		height = 10,
		travelTime = 3, -- the skippable flight (spec: 3 s)
		cooldown = 20,
		arriveAbove = 6,
		routeSlack = 60, -- a travelling hero may be this far off the flight arc (Travel.routeGap; MoveGuard)
	},
	heightCell = 10, -- the heightmap cell for the drone AI and bots (studs)
	-- World clock (spec: Day and night): one server clock, 24 minutes a cycle (16 day, 3 dusk, 4 night,
	-- 1 dawn), sent on join and every 60 s. Night: villain-side incidents and contracts 30% more often.
	clock = {
		cycle = 1440,
		day = 960,
		dusk = 180,
		night = 240,
		dawn = 60,
		sendEvery = 60,
		nightVillain = 1.3,
	},
	-- Zone level (M6, see Decisions): what an incident, contract or event pays and how strong its robots are.
	-- It is the level of the hero it spawned for, raised to the area's floor, so the outskirts and the
	-- landmarks are tougher and a level 50 helping a level 5 earns level 5 rewards. Capped at Stats.levelCap.
	zoneFloor = {
		hub = 1,
		hubFill = 1,
		suburbs = 5,
		farmland = 12,
		coast = 20,
		CometCrater = 10,
		RadioHill = 1,
		OldQuarry = 20,
		Uptown = 5, -- the second business district sits among the first suburbs, so it starts at their floor
	},
}
