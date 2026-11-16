-- World layout (spec: World, city generator and destruction budgets > Map layout). World origin is the map
-- centre, so the 4,800 stud map runs -2,400 to 2,400 and the Brightharbor hub -800 to 800 on both axes.
-- M1 builds only the Downtown greybox; M4 adds the other districts and the seeded outskirts. (tune)
return {
	mapSize = 4800,
	tile = 100,
	hub = { min = -800, max = 800 },
	ground = { y = 0, thickness = 4 },
	districts = {
		Downtown = { minX = -750, maxX = -50, minZ = -350, maxZ = 350 }, -- 700 x 700, towers and rooftops
		Docks = { minX = 0, maxX = 800, minZ = 300, maxZ = 800 }, -- 800 x 500 (M4)
		OldTown = { minX = 100, maxX = 700, minZ = -700, maxZ = -100 }, -- 600 x 600 (M4)
	},
	-- Downtown greybox grid: blocks of buildings split by streets
	downtown = {
		block = 110,
		street = 30, -- road width between blocks
		sidewalk = 5,
		lotsPerSide = 2, -- each block holds 2 x 2 lots
		lotGap = 6,
		height = { min = 40, max = 190, towerChance = 0.18, towerMin = 200, towerMax = 280 },
		rooftop = { ledgeChance = 0.5, waterTowerChance = 0.25, antennaChance = 0.3 },
		plaza = { size = 140 }, -- the open square around the Beacon Tower, where new heroes land
		beacon = { height = 320, width = 46 }, -- Beacon Tower HQ (League side), the Downtown landmark
		seed = 20261116, -- fixed: the hub is handcrafted in the spec, so it never changes with the weekly seed
	},
	-- The Docks (spec: cranes, warehouses, the Foundry villain HQ). Fixed seed like Downtown.
	docks = {
		seed = 20261117,
		basin = { minX = 440, maxX = 790, minZ = 560, maxZ = 792 }, -- the harbour water
		warehouses = { minX = 110, maxX = 430, minZ = 320, maxZ = 545, cols = 3, rows = 2, gap = 16 },
		warehouseHeight = { min = 26, max = 40 },
		containers = { minX = 450, maxX = 790, minZ = 410, maxZ = 545, cols = 7, rows = 4, maxStack = 3 },
		container = { sx = 8, sy = 8.5, sz = 20 },
		cranes = { count = 3, minX = 470, maxX = 760, z = 552, height = 96, span = 34, boom = 70 },
		foundry = {
			minX = 40,
			maxX = 330,
			minZ = 585,
			maxZ = 785,
			height = 110,
			chimneys = 3,
			chimneyHeight = 170,
		},
	},
	-- Old Town (spec: narrow streets, clock tower). Small blocks, pitched roofs, a square in the middle.
	oldTown = {
		seed = 20261118,
		block = 60,
		street = 14,
		lotsPerSide = 2,
		lotGap = 4,
		height = { min = 18, max = 46 },
		pitchedChance = 0.7,
		square = { 4, 5 }, -- blocks 4 and 5 on both axes are Clock Square
		clock = { base = 26, height = 140, spire = 30 },
	},
	-- Hub filler tiles between the districts (parks, low-rise blocks), fixed seed
	hubFill = { seed = 20261119, street = 8, height = { min = 14, max = 40 } },
	ceilingCloudY = 500,
	-- Muted building colours so saturated hero colours pop (spec: Style guide)
	palette = {
		concrete = { 158, 156, 150 },
		-- The Deep (underwater): reef, wrecks, the Sunken Line and the sunken factory
		coralA = { 255, 120, 120 },
		coralB = { 255, 180, 90 },
		coralC = { 190, 120, 230 },
		coralD = { 90, 210, 190 },
		kelp = { 60, 120, 70 },
		wreck = { 96, 70, 52 },
		rust = { 140, 80, 50 },
		seabed = { 170, 160, 130 },
		tunnel = { 88, 92, 98 },
		trainCar = { 170, 175, 185 },
		trainStripe = { 220, 70, 60 },
		cargo = { 230, 180, 60 },
		nullMetal = { 50, 52, 64 },
		nullGlow = { 120, 90, 255 },
		brick = { 140, 98, 82 },
		slate = { 92, 100, 112 },
		sand = { 196, 180, 150 },
		steel = { 120, 130, 140 },
		glass = { 70, 96, 120 },
		road = { 46, 48, 54 },
		sidewalk = { 120, 120, 118 },
		grass = { 92, 130, 78 },
		roof = { 74, 76, 82 },
		window = { 255, 214, 140 },
		beacon = { 236, 240, 245 },
		beaconGlow = { 120, 200, 255 },
		water = { 58, 110, 150 },
		sea = { 46, 92, 132 },
		wood = { 132, 100, 70 },
		roofRed = { 150, 72, 60 },
		roofBlue = { 70, 90, 120 },
		white = { 228, 226, 220 },
		crop = { 170, 160, 70 },
		cropGreen = { 110, 150, 70 },
		soil = { 110, 84, 60 },
		hay = { 214, 186, 104 },
		leaf = { 70, 120, 60 },
		rock = { 120, 112, 104 },
		crater = { 60, 54, 60 },
		comet = { 140, 220, 255 },
		foundry = { 62, 58, 60 },
		foundryGlow = { 255, 90, 60 },
		containerA = { 196, 82, 58 },
		containerB = { 58, 120, 170 },
		containerC = { 210, 170, 60 },
		containerD = { 90, 140, 90 },
		safe = { 236, 240, 245 },
		bank = { 255, 205, 70 },
		loadout = { 110, 190, 255 },
		respawn = { 120, 230, 150 },
		contracts = { 255, 140, 60 },
		beaconLight = { 255, 240, 170 },
		line = { 240, 210, 90 },
	},
	partBudget = { downtown = 6000, docks = 1500, oldTown = 2500, hub = 14000 }, -- greybox part count ceiling (hub budget 55,000 in the spec)
}
