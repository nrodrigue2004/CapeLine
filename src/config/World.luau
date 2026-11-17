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
	crater = { rimHeight = 26, rimWidth = 30, floorDepth = 0, glowHeight = 24 },
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
		{ id = 12, name = "South Park", district = "Hub", x = -400, z = 620 },
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
		{ id = 1, name = "Beacon Tower", at = "plaza" },
		{ id = 2, name = "Downtown East", at = "roof", x = -150, z = 150 },
		{ id = 3, name = "Harbor Gantry", at = "crane" },
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
