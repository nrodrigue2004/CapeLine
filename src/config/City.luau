-- World layout (spec: World, city generator and destruction budgets > Map layout). World origin is the map
-- centre, so the 4,800 stud map runs -2,400 to 2,400 and the Brightharbor hub -800 to 800 on both axes.
-- M1 builds only the Downtown greybox; M4 adds the other districts and the seeded outskirts. (tune)

-- Downtown's size (nate 2026-11-17: "make downtown bigger"; nate picked about 1.5x, ~860 x 860). The core is
-- the first 700 x 700 Downtown, built from the same draws as always; `grow` adds whole blocks (110 + a 30
-- street = 140 studs) on each side: 1 north and 1 west makes 840 x 840 (1.44x; the nearest square to 860).
-- West reaches 90 studs past the hub edge into the first suburb ring (those tiles become Downtown's); east
-- would run into the Docks. Other sizes are this one line (2 + 2 would need North Park moved).
local DOWNTOWN_BLOCK, DOWNTOWN_STREET = 110, 30
local PITCH = DOWNTOWN_BLOCK + DOWNTOWN_STREET
local CORE = { minX = -750, maxX = -50, minZ = -350, maxZ = 350 }
local GROW = { north = 1, south = 0, west = 1, east = 0 }
-- Uptown (PLACEHOLDER NAME; the lore thread decides what it is): the second Downtown-style district, out of
-- the hub just north of it, between North Park and Northgate. A square of `size` studs centred on (x, z).
local UPTOWN = { x = -400, z = -1100, size = 600 }

return {
	mapSize = 4800,
	tile = 100,
	hub = { min = -800, max = 800 },
	ground = { y = 0, thickness = 4 },
	districts = {
		Downtown = { -- the core grown by whole blocks: 840 x 840 with GROW above, towers and rooftops
			minX = CORE.minX - GROW.west * PITCH,
			maxX = CORE.maxX + GROW.east * PITCH,
			minZ = CORE.minZ - GROW.north * PITCH,
			maxZ = CORE.maxZ + GROW.south * PITCH,
		},
		Docks = { minX = 0, maxX = 800, minZ = 300, maxZ = 800 }, -- 800 x 500 (M4)
		OldTown = { minX = 100, maxX = 700, minZ = -700, maxZ = -100 }, -- 600 x 600 (M4)
		Uptown = { -- 600 x 600, the second business district (2026-11-17), out in the first suburb rings
			minX = UPTOWN.x - UPTOWN.size / 2,
			maxX = UPTOWN.x + UPTOWN.size / 2,
			minZ = UPTOWN.z - UPTOWN.size / 2,
			maxZ = UPTOWN.z + UPTOWN.size / 2,
		},
	},
	-- Downtown greybox grid: blocks of buildings split by streets
	downtown = {
		block = DOWNTOWN_BLOCK,
		street = DOWNTOWN_STREET, -- road width between blocks
		sidewalk = 5,
		lotsPerSide = 2, -- each block holds 2 x 2 lots
		lotGap = 6,
		-- towers are real skyscrapers (nate 2026-11-17: "We need taller buildings, skyscrapers"); each gets a
		-- silhouette from Config.City.skyline (setbacks, a spire, a lit crown, a mast or a flat roof)
		height = { min = 40, max = 190, towerChance = 0.18, towerMin = 400, towerMax = 600 },
		rooftop = { ledgeChance = 0.5, waterTowerChance = 0.25, antennaChance = 0.3 },
		plaza = { size = 140 }, -- the open square around the Beacon Tower, where new heroes land
		beacon = { height = 640, width = 46 }, -- Beacon Tower HQ (League side), the Downtown landmark, the tallest there
		seed = 20261116, -- fixed: the hub is handcrafted in the spec, so it never changes with the weekly seed
		core = CORE, -- the first 700 x 700: its blocks keep their draws, so its buildings never move
		grow = GROW,
		-- open squares in the new blocks, kept for the lore thread's side quest chains (a fake hero academy and
		-- one more): paved, lamps and benches round the edge, nothing built. Block (x, z) counts like the
		-- safehouse lots: the core is 1..5 on both axes, the north row and the west column 0.
		open = {
			{ id = "OpenNorth", block = { 2, 0 } },
			{ id = "OpenWest", block = { 0, 4 } },
		},
	},
	-- Uptown (PLACEHOLDER NAME): the second Downtown-style district, its own grid, heights and palette (sunset
	-- coral, teal, amber and violet fronts over warm terrazzo, flower tubs and bushes instead of trees), so it
	-- does not read as a copy of Downtown. Built like Downtown's grown blocks (CityLayout.uptown).
	uptown = {
		seed = 20261121,
		block = 120,
		street = 30,
		sidewalk = 5,
		lotsPerSide = 2,
		lotGap = 6,
		height = { min = 48, max = 170, towerChance = 0.24, towerMin = 380, towerMax = 560 },
		rooftop = { ledgeChance = 0.4, gardenChance = 0.35, antennaChance = 0.25 },
		colors = { "upCoral", "upTeal", "upAmber", "upViolet", "upCream", "upSky" },
		park = { 3, 2 }, -- one block is a green with a fountain (block x, z from the north-west corner, 1..4)
		-- the landmark skyscraper (PLACEHOLDER NAME), the city's tallest: a square shaft, two setbacks, a lit
		-- lantern and a spire to `height`, alone on its block with a plaza round it
		landmark = { block = { 2, 3 }, size = 64, height = 820 },
		fountain = { radius = 14, height = 2.4, jet = 10 },
	},
	-- The city kit (overhaul plan step 3: the first Downtown block; step 5: the whole city). Building fronts,
	-- paving, roads and roofs are tiling MaterialVariants in MaterialService named "Kit" .. name
	-- (art/city/materials.py, uploaded by nate); until one is in, the parts that use it keep their plain look
	-- (and their window bands). Street props are ReplicatedStorage.Art.Street meshes (art/blender/street.py),
	-- built by each device near its camera (CityProps, Config.Presets props budget); none until imported.
	-- Dressing never changes a layout's random draws: picks use Rng.hash(seed, position) and the props and
	-- kerbs are added after (tests "City kit").
	kit = {
		seed = 20261120, -- the hash seed for the dressing's picks (fronts, tints, which props a side gets)
		previewBlock = { 1, 0 }, -- art/city/block.luau's block (east of the plaza, in view where new heroes land)
		-- a building's palette colour -> its front choices (one picked per building by hash, so streets don't
		-- repeat); every front is a 12-stud storey a tile
		fronts = {
			Downtown = {
				brick = { "Brick", "Brick", "Deco" },
				concrete = { "Office", "Panel" },
				slate = { "Office", "Deco" },
				sand = { "Stone", "Deco" },
				steel = { "Curtain", "Panel" },
				glass = { "Curtain" },
				tower = { "Curtain", "Curtain", "Deco", "Panel" }, -- buildings over 200 studs
			},
			Docks = { steel = { "Warehouse" }, brick = { "DockBrick" }, foundry = { "Warehouse" } },
			-- Uptown: ribbon windows and prism glass tinted in the district's sunset colours, white panels
			Uptown = {
				upCoral = { "Ribbon", "Ribbon", "Panel" },
				upTeal = { "Prism", "Ribbon" },
				upAmber = { "Ribbon", "Prism" },
				upViolet = { "Prism", "Ribbon" },
				upCream = { "Panel", "Ribbon" },
				upSky = { "Prism", "Panel" },
				tower = { "Prism", "Prism", "Ribbon" },
			},
			OldTown = {
				brick = { "OldBrick" },
				sand = { "Stone", "Timber" },
				white = { "Plaster", "Timber", "Plaster" },
				concrete = { "Plaster" },
			},
			-- the outskirts and the hub filler, by lot kind and body colour
			house = {
				white = { "Siding" },
				sand = { "Siding" },
				brick = { "Brick" },
				concrete = { "Siding", "Plaster" },
			},
			shop = {
				white = { "Plaster" },
				sand = { "Plaster", "Stone" },
				brick = { "Brick" },
				concrete = { "Office" },
			},
			apt = {
				white = { "Plaster", "Panel" },
				sand = { "Stone" },
				brick = { "Brick" },
				concrete = { "Office" },
			},
			barn = { roofRed = { "Siding" } },
		},
		-- tinted fronts: the texture is drawn light and the part keeps a colour (palette keys, picked by hash);
		-- false keeps the part's own colour (containers, roofs, the Foundry)
		tinted = {
			Warehouse = { "whTeal", "whRust", "whBlue", "whGreen" },
			Plaster = { "plYellow", "plPeach", "plMint", "plSky", "plRose", "plCream" },
			Timber = { "plCream", "plYellow", "plRose" },
			Siding = { "sdBlue", "sdYellow", "sdMint", "sdCream", "sdRose", "sdWhite" },
			Ribbon = { "upCoral", "upTeal", "upAmber", "upViolet", "upMint" },
			Prism = { "upTeal", "upViolet", "upAmber", "upSky" },
			Container = false,
			RoofTile = false,
		},
		barnTint = "sdBarn", -- barns are red clapboard
		roofTints = { roofRed = "tileRed", roofBlue = "tileBlue", roof = "tileSlate" }, -- RoofTile on pitched roofs
		studsPerTile = {
			Brick = 12,
			Office = 12,
			Curtain = 12,
			Stone = 12,
			Paving = 8,
			Asphalt = 16,
			Deco = 12,
			Panel = 12,
			Warehouse = 12,
			DockBrick = 12,
			Quay = 12,
			Container = 8,
			OldBrick = 12,
			Plaster = 12,
			Timber = 12,
			Cobble = 8,
			Flagstone = 8,
			Siding = 12,
			RoofTile = 6,
			Ribbon = 12,
			Prism = 12,
			Terrazzo = 8,
		},
		baseMaterial = {
			Brick = "Brick",
			Office = "Concrete",
			Curtain = "Glass",
			Stone = "Sandstone",
			Paving = "Pavement",
			Asphalt = "Asphalt",
			Deco = "Limestone",
			Panel = "Marble",
			Warehouse = "CorrodedMetal",
			DockBrick = "Brick",
			Quay = "Concrete",
			Container = "DiamondPlate",
			OldBrick = "Brick",
			Plaster = "Plaster",
			Timber = "WoodPlanks",
			Cobble = "Cobblestone",
			Flagstone = "Slate",
			Siding = "Wood",
			RoofTile = "ClayRoofTiles",
			Ribbon = "SmoothPlastic",
			Prism = "Glass",
			Terrazzo = "Pavement",
		},
		-- the ground each district's kit puts down
		ground = {
			Downtown = { sidewalk = "Paving", road = "Asphalt" },
			OldTown = { sidewalk = "Flagstone", road = "Cobble", square = "Flagstone" },
			Docks = { quay = "Quay" },
			Uptown = { sidewalk = "Terrazzo", road = "Asphalt", park = "Terrazzo" },
			Hub = { sidewalk = "Paving" },
			Outskirts = { road = "Asphalt" },
		},
		kerb = 0.6, -- kerb width on the sidewalk's edge
		cornice = 1.2, -- the roof cornice: a cap this deep over the roof (0.05 above it, 0.5 proud all round), so the
		-- front texture never shows on top
		lampEvery = 26, -- street lamps along each side (studs apart), planted trees between them
		dash = { length = 6, gap = 6, width = 0.5 }, -- the lane dashes down the middle of Downtown's streets
		-- props: what each is made of (Art.Street mesh name -> colour, material, collides, transparency), its
		-- tier (1 every device, 2 medium and high, 3 high only: Config.Presets props) and its footprint on the
		-- ground (width across, depth, and how far the footprint's centre sits behind the foot point), which the
		-- layout keeps clear of buildings, roads and other props
		props = {
			StreetLamp = {
				tier = 1,
				foot = { 1, 1, 0 },
				pieces = {
					Pole = { { 48, 60, 56 }, "Metal", true },
					LampHead = { { 48, 60, 56 }, "Metal", false },
					Bulb = { { 255, 236, 190 }, "Neon", false },
				},
			},
			Bench = {
				tier = 2,
				foot = { 5.2, 1.9, 0.5 },
				pieces = {
					BenchSeat = { { 150, 102, 64 }, "WoodPlanks", true },
					BenchFrame = { { 40, 44, 48 }, "Metal", true },
				},
			},
			Hydrant = {
				tier = 2,
				foot = { 1.4, 1.4, 0 },
				pieces = { Hydrant = { { 214, 52, 44 }, "SmoothPlastic", true } },
			},
			Bin = { tier = 2, foot = { 2.2, 2.2, 0 }, pieces = { Bin = { { 60, 84, 72 }, "Metal", true } } },
			Planter = {
				tier = 2,
				foot = { 3.4, 3.4, 0 },
				pieces = {
					PlanterBox = { { 168, 164, 156 }, "Concrete", true },
					Trunk = { { 96, 70, 50 }, "Wood", true },
					Crown = { { 84, 150, 70 }, "Grass", false },
				},
			},
			TrafficLight = {
				tier = 1,
				foot = { 1, 1, 0 },
				pieces = {
					SignalPole = { { 54, 58, 64 }, "Metal", true },
					SignalBox = { { 40, 42, 46 }, "Metal", false },
					SignalLights = { { 120, 255, 140 }, "Neon", false },
				},
			},
			-- Downtown extras
			BusStop = {
				tier = 2,
				foot = { 7.4, 2.4, 0.05 },
				pieces = {
					ShelterFrame = { { 52, 60, 70 }, "Metal", true },
					ShelterRoof = { { 40, 160, 200 }, "SmoothPlastic", true },
					ShelterGlass = { { 190, 225, 240 }, "Glass", true, 0.6 },
					ShelterSeat = { { 230, 232, 236 }, "Metal", true },
				},
			},
			BikeRack = {
				tier = 3,
				foot = { 5.2, 2.4, 0 },
				pieces = { BikeRack = { { 70, 140, 210 }, "Metal", true } },
			},
			Bollard = {
				tier = 3,
				foot = { 0.8, 0.8, 0 },
				pieces = { Bollard = { { 58, 62, 70 }, "Metal", true } },
			},
			-- the Docks
			Crate = {
				tier = 2,
				foot = { 3.2, 3.2, 0 },
				pieces = { Crate = { { 186, 140, 88 }, "WoodPlanks", true } },
			},
			Barrel = {
				tier = 3,
				foot = { 2, 2, 0 },
				pieces = { Barrel = { { 40, 110, 190 }, "Metal", true } },
			},
			Pallet = {
				tier = 3,
				foot = { 4, 4, 0 },
				pieces = { Pallet = { { 176, 136, 92 }, "Wood", true } },
			},
			MooringBollard = {
				tier = 2,
				foot = { 2, 2, 0 },
				pieces = { MooringBollard = { { 44, 46, 52 }, "Metal", true } },
			},
			DockLight = {
				tier = 1,
				foot = { 1.8, 1.8, 0 },
				pieces = {
					DockMast = { { 236, 190, 50 }, "Metal", true },
					DockLamps = { { 255, 244, 214 }, "Neon", false },
				},
			},
			JibCrane = {
				tier = 1,
				foot = { 6.8, 6.8, 0 },
				pieces = {
					CranePedestal = { { 60, 110, 170 }, "Metal", true },
					CraneCab = { { 236, 236, 230 }, "SmoothPlastic", true },
					CraneJib = { { 244, 190, 40 }, "Metal", false },
					CraneHook = { { 40, 40, 44 }, "Metal", false },
				},
			},
			-- Old Town
			OldLamp = {
				tier = 1,
				foot = { 1.3, 1.3, 0 },
				pieces = {
					OldPost = { { 40, 70, 58 }, "Metal", true },
					OldLantern = { { 40, 70, 58 }, "Metal", false },
					OldGlow = { { 255, 214, 140 }, "Neon", false },
				},
			},
			FlowerTub = {
				tier = 2,
				foot = { 2.6, 2.6, 0 },
				pieces = {
					Tub = { { 196, 110, 72 }, "Concrete", true },
					TubLeaves = { { 80, 150, 64 }, "Grass", false },
					TubBlooms = { { 255, 110, 150 }, "SmoothPlastic", false },
				},
			},
			CafeSet = {
				tier = 3,
				foot = { 5.6, 2.6, 0 },
				pieces = {
					CafeTable = { { 50, 54, 60 }, "Metal", true },
					CafeChairs = { { 50, 54, 60 }, "Metal", true },
					Umbrella = { { 236, 84, 72 }, "Fabric", false },
				},
			},
			-- the outskirts
			Mailbox = {
				tier = 2,
				foot = { 1.1, 1.7, 0 },
				pieces = {
					MailPost = { { 132, 100, 70 }, "Wood", true },
					MailBox = { { 60, 110, 200 }, "SmoothPlastic", true },
				},
			},
			Bush = {
				tier = 3,
				foot = { 4.6, 4.4, 0 },
				pieces = { Bush = { { 72, 150, 66 }, "Grass", true } },
			},
			PowerPole = {
				tier = 2,
				foot = { 1.2, 1.2, 0 },
				pieces = { PowerPole = { { 120, 92, 66 }, "Wood", true } },
			},
		},
		-- the most each district may add, all tiers (props, their mesh parts, and the server-built kerbs, dashes
		-- and cornices, which also count in partBudget). A device builds only the props near its camera, under its
		-- preset's cap (Config.Presets props).
		budget = {
			Downtown = { props = 1900, parts = 4000, boxes = 1200 },
			Uptown = { props = 900, parts = 2400, boxes = 500 },
			Docks = { props = 260, parts = 420, boxes = 20 },
			OldTown = { props = 520, parts = 1200, boxes = 300 },
			Hub = { props = 1150, parts = 2400, boxes = 0 },
			Outskirts = { props = 9000, parts = 13000, boxes = 0 },
		},
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
		lane = { minX = 0, maxX = 440, minZ = 552, maxZ = 580 }, -- the truck lane (Vehicles): no street props
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
	ceilingCloudY = 880, -- the cloud layer, above the tallest spire (Config.Move ceiling)
	-- skyscraper silhouettes (2026-11-17): a tower's shape is picked by a hash of its spot (never a draw, so no
	-- building moves). The shaft is the wreckable box (Shared.Structure); the parts above it are its crown,
	-- shown while the shaft's top storey stands. Window bands every 12 studs low down, every 36 higher up
	-- (PLACEHOLDER ART, gone once the kit fronts are in), so a 600-stud tower stays cheap on a phone.
	skyline = {
		styles = { "flat", "setback", "spire", "crown", "mast", "setback", "spire", "crown" },
		bandsLow = 144, -- bands every 12 studs up to here
		bandStep = 36, -- then every 36
	},
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
		kerb = { 186, 184, 178 },
		cornice = { 132, 134, 138 }, -- the kit's roof caps (mid grey, so roofs read under the light fronts)
		mark = { 236, 234, 226 },
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
		weapons = { 200, 205, 215 }, -- the Weapon Rack (hero creator plan)
		beaconLight = { 255, 240, 170 },
		line = { 240, 210, 90 },
		-- city kit tints (Config.City.kit.tinted): bright, readable cartoon colours on the light tinted fronts
		whTeal = { 92, 176, 186 },
		whRust = { 206, 110, 80 },
		whBlue = { 96, 140, 206 },
		whGreen = { 120, 176, 110 },
		plYellow = { 255, 226, 150 },
		plPeach = { 255, 196, 160 },
		plMint = { 186, 236, 200 },
		plSky = { 180, 214, 250 },
		plRose = { 250, 188, 196 },
		plCream = { 255, 240, 214 },
		-- Uptown (2026-11-17): sunset fronts, plain bodies until the kit is in, and their kit tints
		upCoral = { 236, 128, 104 },
		upTeal = { 64, 170, 168 },
		upAmber = { 240, 178, 84 },
		upViolet = { 150, 118, 196 },
		upCream = { 244, 230, 206 },
		upSky = { 120, 182, 226 },
		upMint = { 136, 214, 176 },
		upRoof = { 196, 190, 180 },
		terrazzo = { 222, 206, 186 },
		sdBlue = { 160, 200, 236 },
		sdYellow = { 255, 228, 160 },
		sdMint = { 176, 226, 196 },
		sdCream = { 250, 238, 214 },
		sdRose = { 246, 190, 190 },
		sdWhite = { 246, 246, 242 },
		sdBarn = { 196, 70, 58 },
		tileRed = { 214, 96, 70 },
		tileBlue = { 88, 128, 190 },
		tileSlate = { 120, 126, 140 },
	},
	partBudget = { downtown = 6000, docks = 1500, oldTown = 2500, uptown = 2000, hub = 14000 }, -- greybox part count ceiling (hub budget 55,000 in the spec)
}
