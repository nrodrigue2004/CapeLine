-- World layout (spec: World, city generator and destruction budgets > Map layout). World origin is the map
-- centre, so the 4,800 stud map runs -2,400 to 2,400 and the Brightharbor hub -800 to 800 on both axes.
-- M1 builds only the Downtown greybox; M4 adds the other districts and the seeded outskirts. (tune)

-- Downtown's size (nate 2026-11-17: "make downtown bigger"; nate picked about 1.5x, ~860 x 860). The core is
-- the first 700 x 700 Downtown, built from the same draws as always; `grow` adds whole blocks (110 + a 30
-- street = 140 studs) on each side. 2026-11-17: 1 north and 1 west made 840 x 840 (GROW1, kept as the first
-- ring: its blocks keep their draws and their order). 2026-11-19 (nate's playtest: "Downtown and Uptown should
-- be larger", skyscraper fights are the fun): about 1.5x again, 2 more blocks: 1 more column west and 2 rows
-- south, so 980 x 1,120 (1.56x of 840 x 840; 2.24x the first 700 x 700). East runs into the Docks, north into
-- North Park and Uptown, and a third column west would cut the column 12 highway, so south it is (South Park's
-- safehouse moved 100 studs south, out of the way). The new blocks are tower country (`towers` below).
local DOWNTOWN_BLOCK, DOWNTOWN_STREET = 110, 30
local PITCH = DOWNTOWN_BLOCK + DOWNTOWN_STREET
local CORE = { minX = -750, maxX = -50, minZ = -350, maxZ = 350 }
local GROW1 = { north = 1, south = 0, west = 1, east = 0 } -- the 2026-11-17 ring (840 x 840)
local GROW = { north = 1, south = 2, west = 2, east = 0 }
-- Uptown (PLACEHOLDER NAME; the lore thread decides what it is): the second Downtown-style district, out of
-- the hub just north of it, between North Park and Northgate. 2026-11-17: a square of 600 studs centred on
-- (-400, -1,100); 2026-11-19: grown by a block column west and a block row north (the east edge stays clear of
-- the Northgate safehouse and the south edge on the hub's), so 750 x 750 (1.56x). `grow` counts those blocks.
local UPTOWN = { minX = -850, maxX = -100, minZ = -1550, maxZ = -800, grow = { west = 1, north = 1 } }

return {
	mapSize = 4800,
	tile = 100,
	hub = { min = -800, max = 800 },
	ground = { y = 0, thickness = 4 },
	districts = {
		Downtown = { -- the core grown by whole blocks: 980 x 1,120 with GROW above, towers and rooftops
			minX = CORE.minX - GROW.west * PITCH,
			maxX = CORE.maxX + GROW.east * PITCH,
			minZ = CORE.minZ - GROW.north * PITCH,
			maxZ = CORE.maxZ + GROW.south * PITCH,
		},
		Docks = { minX = 0, maxX = 800, minZ = 300, maxZ = 800 }, -- 800 x 500 (M4)
		OldTown = { minX = 100, maxX = 700, minZ = -700, maxZ = -100 }, -- 600 x 600 (M4)
		Uptown = { -- 750 x 750 (600 x 600 until 2026-11-19), the second business district, in the first suburb rings
			minX = UPTOWN.minX,
			maxX = UPTOWN.maxX,
			minZ = UPTOWN.minZ,
			maxZ = UPTOWN.maxZ,
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
		beacon = { height = 640, width = 46 }, -- the Beacon Tower: Crane's Hero Hall (lore Q1), the Downtown landmark, the tallest there
		seed = 20261116, -- fixed: the hub is handcrafted in the spec, so it never changes with the weekly seed
		core = CORE, -- the first 700 x 700: its blocks keep their draws, so its buildings never move
		grow = GROW,
		grow1 = GROW1, -- the first ring's blocks are built (and numbered) before the 2026-11-19 ones
		-- the 2026-11-19 blocks (outside grow1) are where the skyline is: more of their lots draw a tower (the same
		-- draw, a higher chance, so nothing in the older blocks changes)
		towers = { chance = 0.4 },
		-- open squares in the new blocks, kept for the lore thread's side quest chains (a fake hero academy and
		-- one more): paved, lamps and benches round the edge, nothing built. Block (x, z) counts like the
		-- safehouse lots: the core is 1..5 on both axes, the north row and the west column 0.
		open = {
			{ id = "OpenNorth", block = { 2, 0 } },
			{ id = "OpenWest", block = { 0, 4 } },
		},
		-- the rooftop row (nate 2026-11-17: a longer prologue chase): purpose-built roofs one short Leap apart
		-- on the first lot strip (lots lz = strip) of the two core blocks east of the plaza, for the Ceremony
		-- prologue's chase (Shared.OpeningPlan) and anyone running roofs. The strip's lots still take their
		-- draws, so nothing else moves; the other strip keeps its seeded buildings. `at`: each block's roofs
		-- along x from its middle (38 apart in a block, 64 across the street); `roofs` in running order: body
		-- height, width along the row, depth, colour and the rooftop dressing (solid where you land, walk-through
		-- where it is decoration). Rises stay inside a Leap's climb (Config.Story.opening.roofs.climb).
		row = {
			blocks = { { 4, 3 }, { 5, 3 } },
			strip = 1,
			at = { -38, 0, 38 },
			roofs = {
				{ h = 24, w = 20, d = 36, color = "brick", dress = { "ac", "hatch" } },
				{ h = 32, w = 22, d = 38, color = "sand", dress = { "tank" } },
				{ h = 40, w = 20, d = 40, color = "slate", dress = { "billboard" } },
				{ h = 36, w = 22, d = 36, color = "concrete", dress = { "skylights", "ac" } },
				{ h = 44, w = 18, d = 38, color = "brick", dress = { "laundry" } },
				{ h = 40, w = 24, d = 40, color = "steel", dress = { "tank", "hatch" } },
			},
		},
	},
	-- Uptown (PLACEHOLDER NAME): the second Downtown-style district, its own grid, heights and palette (muted
	-- terracotta, slate teal, champagne stone and steel fronts since shapes-2, over warm terrazzo, flower tubs and bushes instead of trees), so it
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
		-- blocks count from the 2026-11-17 square's north-west block (1, 1) to (4, 4); the 2026-11-19 column west
		-- and row north are 0 (each block keeps its own seeded stream, so no older building moves)
		grow = UPTOWN.grow,
		towers = { chance = 0.42 }, -- the new blocks' tower chance (tower country, like Downtown's new blocks)
		park = { 3, 2 }, -- one block is a green with a fountain (block x, z as above)
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
			-- shapes-2 (2026-11-19, nate: "uptown buildings look weird with crazy colors and textures"): an upscale
			-- business district, not a candy box: mostly neutral glass curtain walls and stone, ribbon windows in
			-- muted tints; the diamond Prism glass read as a chain-link fence over a whole tower, so Uptown no longer uses it
			Uptown = {
				upCoral = { "Ribbon", "Deco", "Panel" },
				upTeal = { "Curtain", "Ribbon" },
				upAmber = { "Deco", "Ribbon" },
				upViolet = { "Curtain", "Ribbon" },
				upCream = { "Panel", "Deco" },
				upSky = { "Curtain", "Panel" },
				tower = { "Curtain", "Curtain", "Ribbon" },
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
			Ribbon = { "upCoral", "upTeal", "upAmber", "upViolet", "upMint" }, -- (muted since shapes-2)
			Prism = { "upTeal", "upSky" },
			Container = false,
			RoofTile = false,
			-- the pockets' kit (2026-11-19, art/city/pocket_materials.py; Config.PocketKit): drawn light, the part's colour shows
			Planks = false,
			Tile = false,
			CaveRock = false,
			Concrete = false,
			SteelPlate = false,
			Block = false,
			Sand = false,
			Ashlar = false,
			Brickwork = false,
		},
		-- pt-ui (2026-11-19): the kit texture for a building body or tower tier the layouts leave plain
		-- (Shared.CityKit.fill): by palette colour, round shapes (cylinders, balls) in plain concrete
		fill = {
			kinds = { building = true, tier = true },
			byColor = {
				slate = "Office", -- the safehouse shelters
				steel = "SteelPlate", -- tower masts and spires
				white = "Siding", -- pier huts (tinted clapboard)
				containerA = "Container",
				containerB = "Container",
				containerC = "Container", -- coast shacks
				containerD = "Container",
				brick = "Brick",
				concrete = "Office",
				sand = "Stone",
				glass = "Curtain",
			},
			round = "Concrete", -- lighthouses, the windmill
			default = "Concrete",
		},
		wreck = "Concrete", -- a broken kit building's pillars, slabs and rubble (Fx.BuildingFx)
		beaconFront = "Panel", -- the plaza's Beacon Tower (the Vigil's HQ)
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
			Planks = 8,
			Tile = 8,
			CaveRock = 16,
			Concrete = 12,
			SteelPlate = 8,
			Block = 8,
			Sand = 16,
			Ashlar = 12,
			Brickwork = 8,
			CraterFloor = 32,
			CraterRim = 24,
			Tilled = 8, -- the farm fields (Config.Life.tilled, 2026-11-19)
		},
		baseMaterial = {
			Brick = "Brick",
			Office = "Concrete",
			Curtain = "Concrete", -- pt-ui 2026-11-19: was Glass, which never shows a MaterialVariant
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
			Prism = "Concrete", -- (was Glass, like Curtain)
			Terrazzo = "Pavement",
			Planks = "WoodPlanks",
			Tile = "CeramicTiles",
			CaveRock = "Rock",
			Concrete = "Concrete",
			SteelPlate = "Metal",
			Block = "Concrete",
			Sand = "Sand",
			Ashlar = "Sandstone",
			Brickwork = "Brick",
			CraterFloor = "Ground",
			CraterRim = "Rock",
			Tilled = "Ground",
		},
		-- textures that dress one landmark in their own colours (the part shows white), set by a box's `ground`
		-- over its kit (gap-fx3, 2026-11-19: the Crater's floor and rim, Config.World.crater.ground)
		landmark = { CraterFloor = true, CraterRim = true },
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
		-- shapes-2 (2026-11-19): zebra crossings (this deep, this far in from the block's corner) and storm drains
		-- (x, z) on every dashed street (Config.Life.shapes.decals)
		crossing = { depth = 5, inset = 4, drain = { 3, 1.4 } },
		-- pt-city (2026-11-19): the street-level and rooftop pieces heroes use or break in Downtown and Uptown
		-- (CityLayout; Shared.CityPlay). Picks are hashes of each spot (salts below), never a layout draw, so no
		-- building moves. Chances are per building face or roof; heights in studs over the sidewalk.
		play = {
			awning = { chance = 0.55, y = 11, maxHeight = 1000, minFace = 16, salt = 31 }, -- over a shop front
			tints = { "awRed", "awGreen", "awBlue", "awYellow", "awTeal", "awPink", "awOrange" },
			ac = { chance = 0.6, salt = 32 }, -- on a flat roof's free quarter
			vent = { chance = 0.45, salt = 33 },
			billboard = { chance = 0.32, minHeight = 36, maxHeight = 200, minWidth = 26, salt = 34 },
			-- perches on a tower's faces (h 200 and up): every `every` studs from `from`, one face a level in turn
			perch = { minHeight = 200, from = 90, every = 110, top = 40, salt = 35 },
			newsBox = { chance = 0.35, salt = 36 }, -- by a corner hydrant's other end
			foodCart = { salt = 37 }, -- one in each open square and on Uptown's green and landmark plaza
			-- shop fronts (Shared.CityPlay: one under every awning, and a bare one now and then): sign words by hash
			shop = {
				bareChance = 0.3, -- a wide enough street face with no awning still gets a shop front this often
				salt = 41,
				frame = { { 40, 46, 58 }, { 92, 42, 40 }, { 30, 72, 62 }, { 54, 44, 80 }, { 230, 226, 214 } },
				signs = {
					"DELI",
					"BAKERY",
					"BOOKS",
					"COMICS",
					"PIZZA",
					"NOODLES",
					"FLOWERS",
					"TOYS",
					"GAMES",
					"TAILOR",
					"SHOES",
					"MUSIC",
					"CAFE",
					"GYM",
					"HARDWARE",
					"LAUNDRY",
					"ARCADE",
					"BIKES",
					"DONUTS",
					"TACOS",
					"BARBER",
					"BAGELS",
					"KARATE",
					"PET SHOP",
					"DINER",
					"FIX-IT",
					"HOBBY",
					"CAPES & CO",
					"GADGETS",
					"ICE CREAM",
				},
				ink = { 255, 248, 226 },
			},
			-- a vending machine toward a side's middle, in a tint by hash (Downtown and Uptown sidewalks)
			vending = { chance = 0.4, salt = 42, tints = { "awRed", "awBlue", "awYellow", "awTeal" } },
			-- an awning springs a hero who lands on it falling faster than minFall up at `up` studs/s (keep of a
			-- harder fall's speed, at most `max`); the server takes it (MoveGuard grant) once the hero is within
			-- `reach` studs of an awning's top, at most once a `cooldown`
			bounce = { up = 70, keep = 0.6, max = 105, minFall = 14, reach = 6, cooldown = 0.6 },
		},
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
			-- pt-city (2026-11-19, nate's playtest: "a more interactive map, more detailed ... fewer simple shapes").
			-- Street props like the rest (each device builds them near its camera; they knock loose):
			NewsBox = {
				tier = 2,
				foot = { 3.6, 1.6, 0 },
				pieces = {
					NewsBoxBody = { { 214, 60, 56 }, "SmoothPlastic", true, 0, true }, -- 5th: tinted per placement
					NewsBoxGlass = { { 200, 226, 236 }, "Glass", true, 0.4 },
				},
			},
			FoodCart = {
				tier = 2,
				foot = { 5.8, 3.2, 0 },
				pieces = {
					CartBody = { { 236, 84, 72 }, "SmoothPlastic", true, 0, true },
					CartTrim = { { 64, 68, 76 }, "Metal", true },
					CartUmbrella = { { 250, 244, 228 }, "Fabric", false },
				},
			},
			-- the roof and wall pieces: `server` ones are built by the server inside the building they stand on (in
			-- place of their box, CityLayout's `art`), so they break and come back with it; `falls` pieces are flung
			-- off as debris when it breaks (Fx.BuildingFx), `burst` adds a splash, `bounce` springs a hero up
			Awning = {
				tier = 1,
				server = true,
				bounce = true,
				foot = { 12, 4.5, 2.25 },
				pieces = {
					AwningCanvas = { { 214, 60, 56 }, "Fabric", true, 0, true },
					AwningStripe = { { 250, 244, 228 }, "Fabric", true },
					AwningFrame = { { 52, 56, 62 }, "Metal", false },
				},
			},
			-- the living world (2026-11-19, Art.Life from art/blender/life.py; Config.Life.shop): a shop front under each
			-- awning (and some bare ones), built by the server in the building's model like the awning, its sign
			-- lettered by CityBuilder. Piece row: colour, material, collides, transparency, tinted, frame paint
			ShopFront = {
				tier = 1,
				server = true,
				foot = { 12.7, 1.2, 0.6 },
				pieces = {
					ShopFrame = { { 40, 46, 58 }, "SmoothPlastic", true, 0, nil, true },
					ShopGlass = { { 170, 205, 225 }, "Glass", false, 0.45 },
					ShopBack = { { 150, 118, 84 }, "SmoothPlastic", false },
					ShopSign = { { 214, 60, 56 }, "SmoothPlastic", false, 0, true },
				},
			},
			-- a vending machine on Downtown's and Uptown's sidewalks (it spills its cans when knocked loose: Fx.CityLife)
			VendingMachine = {
				tier = 2,
				foot = { 3.8, 2.7, 0 },
				pieces = {
					VendBody = { { 210, 50, 50 }, "SmoothPlastic", true, 0, true },
					VendTrim = { { 40, 42, 48 }, "Metal", true },
					VendGlass = { { 200, 230, 245 }, "Glass", false, 0.5 },
					VendCans = { { 230, 230, 235 }, "Metal", false },
					VendLight = { { 255, 250, 220 }, "Neon", false },
				},
			},
			WaterTower = {
				tier = 1,
				server = true,
				falls = true,
				burst = true,
				foot = { 10, 10, 0 },
				pieces = {
					TowerLegs = { { 96, 74, 58 }, "Wood", true },
					TowerTank = { { 150, 108, 72 }, "WoodPlanks", true },
					TowerHoops = { { 48, 50, 56 }, "Metal", false },
					TowerRoof = { { 84, 92, 100 }, "Metal", true },
				},
			},
			RoofAntenna = {
				tier = 1,
				server = true,
				falls = true,
				foot = { 3.6, 3.6, 0 },
				pieces = {
					AntennaMast = { { 140, 146, 152 }, "Metal", true },
					AntennaDish = { { 236, 236, 230 }, "SmoothPlastic", false },
					AntennaLight = { { 255, 60, 60 }, "Neon", false },
				},
			},
			RoofAC = {
				tier = 1,
				server = true,
				falls = true,
				foot = { 5.2, 2.8, 0 },
				pieces = {
					ACBox = { { 206, 208, 204 }, "Metal", true },
					ACFan = { { 70, 74, 80 }, "Metal", false },
				},
			},
			RoofVent = {
				tier = 1,
				server = true,
				falls = true,
				foot = { 2.6, 3.4, 0 },
				pieces = { RoofVent = { { 150, 156, 160 }, "Metal", true } },
			},
			RoofBillboard = {
				tier = 1,
				server = true,
				falls = true,
				foot = { 23, 5, 1.6 },
				pieces = {
					BoardFrame = { { 56, 60, 68 }, "Metal", true },
					BoardFace = { { 255, 196, 60 }, "SmoothPlastic", true, 0, true },
					BoardArt = { { 255, 248, 230 }, "SmoothPlastic", false },
					BoardLamps = { { 255, 236, 190 }, "Neon", false },
				},
			},
			Perch = {
				tier = 1,
				server = true,
				foot = { 10, 4, 2 },
				pieces = { Perch = { { 128, 136, 146 }, "Metal", true } },
			},
		},
		-- the most each district may add, all tiers (props, their mesh parts, and the server-built kerbs, dashes
		-- and cornices, which also count in partBudget). A device builds only the props near its camera, under its
		-- preset's cap (Config.Presets props).
		budget = {
			-- 2026-11-19: Downtown 1.56x and Uptown 1.56x bigger, with the roof and wall pieces (pt-city)
			-- shapes-2 (2026-11-19): + the zebra crossings and drains (a part and a Decal each)
			Downtown = { props = 3400, parts = 8600, boxes = 2800 },
			Uptown = { props = 1800, parts = 4600, boxes = 1260 },
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
		workLamp = { 255, 206, 130 }, -- the Vigil hideout's work lamps (Config.Hq.hideout)
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
		zebra = { 236, 234, 226 }, -- a crossing's strip (shapes-2: hidden under its zebra picture)
		drain = { 54, 56, 60 }, -- a storm drain's strip (hidden under its grate picture)
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
		-- the Crater, a blasted Crane lab (lore step 9): scorch, the lab's white walls, Crane navy, the faint Spark
		-- glow in the cracked tanks, robot husks and the old heroes' relics
		scorch = { 38, 34, 36 },
		labWall = { 214, 212, 206 },
		craneNavy = { 30, 44, 92 },
		sparkGlow = { 110, 200, 225 },
		husk = { 78, 82, 92 },
		relicRed = { 196, 52, 60 },
		relicBlue = { 52, 92, 176 },
		relicGold = { 222, 178, 70 },
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
		-- Uptown's palette, muted to warm stone, slate and steel (shapes-2, 2026-11-19; was candy coral, teal,
		-- amber, violet, sky and mint): the same keys, so no layout draw changes
		upCoral = { 190, 140, 120 },
		upTeal = { 96, 132, 138 },
		upAmber = { 206, 182, 142 },
		upViolet = { 118, 118, 138 },
		upCream = { 236, 228, 212 },
		upSky = { 150, 172, 192 },
		upMint = { 150, 176, 160 },
		upRoof = { 196, 190, 180 },
		-- awnings, billboard faces, news boxes and food carts (pt-city, 2026-11-19): bright cartoon colours
		awRed = { 222, 70, 62 },
		awGreen = { 70, 160, 96 },
		awBlue = { 62, 116, 200 },
		awYellow = { 250, 196, 58 },
		awTeal = { 40, 168, 170 },
		awPink = { 236, 110, 160 },
		awOrange = { 246, 136, 52 },
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
		-- the pockets' kit (2026-11-19, Config.PocketKit): each pocket's own palette on the light pocket textures
		pkRoofGrey = { 150, 150, 154 },
		pkSteel = { 150, 160, 176 },
		pkSteelDark = { 92, 100, 116 },
		pkDeck = { 120, 126, 140 },
		pkRoofWarm = { 176, 128, 108 },
		pkRoofCool = { 120, 140, 170 },
		pkTunnelFloor = { 120, 118, 114 },
		pkTunnelWall = { 168, 164, 156 },
		pkPillar = { 236, 226, 206 },
		pkStage = { 70, 60, 86 },
		pkStageTrim = { 255, 92, 160 },
		pkBridgeRed = { 214, 76, 58 },
		pkSubwayTile = { 246, 236, 208 },
		pkSubwayBand = { 40, 140, 120 },
		pkSubwayCeil = { 150, 150, 146 },
		pkTrackBed = { 92, 88, 84 },
		pkAcademyStone = { 214, 204, 184 },
		pkOak = { 214, 158, 100 },
		pkAcademyWall = { 255, 240, 200 },
		pkAcademyTrim = { 60, 92, 170 },
		pkChalk = { 52, 96, 76 },
		pkMatBlue = { 70, 120, 210 },
		pkWorkshopWall = { 110, 112, 122 },
		pkWorkshopCeil = { 96, 100, 112 },
		pkToyBrick = { 206, 108, 90 },
		pkToyFloor = { 236, 184, 120 },
		pkToyWall = { 186, 232, 214 },
		pkToyTrim = { 238, 70, 92 },
		pkJoist = { 170, 120, 80 },
		pkRug = { 220, 64, 70 },
		pkBrass = { 214, 170, 80 },
		pkCaveRock = { 136, 124, 112 },
		pkWetSand = { 206, 186, 146 },
		pkDriftwood = { 178, 140, 104 },
		pkVelStone = { 136, 188, 184 },
		pkVelDark = { 88, 128, 132 },
		pkMarble = { 236, 238, 230 },
		pkBronze = { 176, 120, 64 },
		pkSeaSand = { 214, 202, 168 },
		pkQuarry = { 170, 144, 120 },
		pkPitSand = { 222, 190, 136 },
		pkRingBlue = { 52, 84, 168 },
		pkCanvas = { 240, 236, 226 },
		pkLabFloor = { 230, 240, 246 },
		pkLabWall = { 214, 240, 232 },
		pkLabCeil = { 176, 190, 204 },
		pkLabTrim = { 60, 170, 210 },
		pkIronBrick = { 168, 76, 62 },
		pkDojoWood = { 196, 140, 88 },
		pkDojoDark = { 112, 78, 56 },
		pkIronStone = { 150, 140, 132 },
		pkMatRed = { 200, 50, 50 },
		pkPoundFloor = { 156, 156, 150 },
		pkPoundRoof = { 110, 120, 130 },
		pkHazard = { 250, 200, 40 },
		pkSignNavy = { 34, 46, 96 },
		pkSignInk = { 24, 22, 30 },
		pkSignCream = { 255, 246, 220 },
		pkSignRed = { 222, 56, 60 },
		pkSignTeal = { 30, 150, 150 },
		pkSignGold = { 255, 200, 50 },
		pkBulb = { 255, 236, 170 },
	},
	-- 2026-11-19 (pt-city): downtown 6,000 -> 9,000 and uptown 2,000 -> 4,000 for the 1.56x districts and their new
	-- roof and wall pieces
	partBudget = { downtown = 9000, docks = 1500, oldTown = 2500, uptown = 4000, hub = 14000 }, -- greybox part count ceiling (hub budget 55,000 in the spec)
}
