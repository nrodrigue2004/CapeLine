-- Park: the big city park between Downtown and Uptown (nate, 2026-11-19: "maybe add a large park between uptown and
-- downtown. like central park"). Its name is a PLACEHOLDER NAME for nate. Pure data; Shared.ParkLayout lays it out
-- (the same on every server and device), the server builds the ground, water and structures (ParkBuilder), the hub
-- builds its paths and trees like any hub box, each device builds its benches and lamps (CityProps) and its life
-- (Fx.ParkLife: joggers, dogs, picnics, buskers, ducks, rowboats, the carousel, the fountains' jets).
-- World x runs east, -z is north (Uptown). Every point below is a world position (studs).
--
-- Room (2026-11-20): Uptown moved 300 studs north (Config.City UPTOWN, its layout is drawn from its own corner, so
-- nothing inside it changed) and the park takes the 980 x 610 between Downtown's north edge and Uptown's south edge:
-- a 15-stud avenue lane inside the edge (Downtown's and Uptown's own 15-stud edges make 30-stud avenues north and
-- south), a sidewalk, then the park wall. The ground inside the wall is Terrain (grass, woods floor, beaches, rocks,
-- water), cut out of the city's ground plates.

return {
	name = "Brightwood Park", -- PLACEHOLDER NAME (nate picks the park's name)
	set = "Park", -- ReplicatedStorage.Art.Park (art/models/Park.rbxm; MeshFix.turn("Park"))
	seed = 20261120,
	bounds = { minX = -1030, maxX = -50, minZ = -1100, maxZ = -490 },
	avenue = 15, -- the road lane inside the bounds, all round
	sidewalk = 6,
	wall = { thick = 2, height = 3.4, cap = 0.5, segment = 24 }, -- the low stone wall (breaks in lengths)
	ground = { top = 0, depth = 8 }, -- the Terrain slab inside the wall (top flush with the city's ground)

	-- the gates in the wall: a gap `width` wide with a stone pillar each side. `side` is the wall it is in.
	gates = {
		{ id = "South", side = "S", at = -590, width = 16, sign = true }, -- the Mall's gate, signed
		{ id = "SouthEast", side = "S", at = -150, width = 12 },
		{ id = "SouthWest", side = "S", at = -880, width = 12 },
		{ id = "West", side = "W", at = -800, width = 12 },
		{ id = "East", side = "E", at = -800, width = 12 },
		{ id = "NorthWest", side = "N", at = -860, width = 12 },
		{ id = "North", side = "N", at = -470, width = 16, sign = true },
		{ id = "NorthEast", side = "N", at = -150, width = 12 },
	},

	-- water: each body is a union of circles (an organic shore on Terrain's 4-stud grid). `level` is the water's top,
	-- `bed` the floor under it; `shore` is the bank ring's material and width round every circle.
	lake = {
		level = -1.6,
		bed = -10,
		shore = { material = "sand", width = 5 },
		blobs = {
			{ -760, -745, 48 },
			{ -715, -760, 52 },
			{ -680, -725, 46 },
			{ -735, -705, 34 },
			{ -790, -770, 30 },
			{ -640, -735, 22 }, -- the neck under the Bow Bridge
			{ -595, -745, 44 },
			{ -550, -720, 50 },
			{ -505, -745, 40 },
			{ -540, -770, 34 },
			{ -470, -720, 26 },
		},
	},
	reservoir = { -- the walled reservoir in the north, the running loop round it
		level = -2.4,
		bed = -12,
		shore = { material = "slate", width = 4 },
		blobs = { { -610, -975, 52 }, { -540, -975, 68 }, { -470, -975, 72 }, { -400, -975, 68 }, { -330, -975, 52 } },
		rail = { every = 12, inset = 2 }, -- iron rail lengths round the stone rim
	},
	pond = { -- the little pond by the rink, the stone bridge over its waist
		level = -1.4,
		bed = -7,
		shore = { material = "sand", width = 4 },
		blobs = { { -275, -615, 24 }, { -240, -605, 28 }, { -210, -618, 20 } },
	},

	-- the open lawns (ellipses: x, z, radius along x, radius along z): bright grass, no trees, picnics
	meadows = {
		{ id = "GreatLawn", x = -245, z = -795, rx = 140, rz = 90 },
		{ id = "NorthMeadow", x = -870, z = -960, rx = 100, rz = 70 },
		{ id = "SheepMeadow", x = -890, z = -660, rx = 70, rz = 60 },
	},
	-- the woods: dense trees on a leafy floor (ellipses as above)
	woods = {
		{ id = "Ramble", x = -560, z = -852, rx = 200, rz = 40 },
		{ id = "NorthWoods", x = -760, z = -1040, rx = 110, rz = 30 },
		{ id = "EastWoods", x = -120, z = -910, rx = 40, rz = 110 },
		{ id = "WestWoods", x = -960, z = -840, rx = 40, rz = 90 },
		{ id = "Hallett", x = -470, z = -560, rx = 60, rz = 35 },
	},
	trees = {
		woods = 260, -- studs of ground a tree in the woods
		open = 2600, -- elsewhere
		size = { 12, 19 }, -- BoxKit.tree sizes (the Art.Life trunk and crown over its boxes)
		clear = { water = 7, path = 5, place = 6, meadow = 0.92 }, -- keep this far (meadow: inside this much of it)
		mall = { every = 16, out = 12, size = 16 }, -- the Mall's elm rows
		max = 420,
	},
	-- rock outcrops (Terrain rock in clusters of balls): x, z, radius, height. Climbable, every one.
	rocks = {
		{ id = "UmpireRock", x = -955, z = -560, r = 16, h = 15 },
		{ id = "RambleRock", x = -700, z = -862, r = 12, h = 11 },
		{ id = "CaveHill", x = -330, z = -932, r = 10, h = 9 },
		{ id = "NorthCrag", x = -110, z = -1050, r = 10, h = 9 },
		{ id = "WestBoulder", x = -850, z = -805, r = 8, h = 7 },
		{ id = "LawnRock", x = -330, z = -740, r = 8, h = 7 },
		{ id = "CherryKnoll", x = -840, z = -1040, r = 9, h = 8 },
	},

	-- the structures (Art.Park looks, each over hidden collision boxes): x, z, ry (degrees; a look faces -z at ry 0)
	places = {
		Bandshell = { x = -655, z = -565, ry = -90 }, -- facing east onto the Mall
		Carousel = { x = -820, z = -592, ry = 0 },
		Boathouse = { x = -440, z = -752, ry = -90 }, -- its deck out over the lake to the west
		Terrace = { x = -590, z = -640, ry = 0 }, -- the big fountain on its terrace by the lake
		BowBridge = { x = -640, z = -729, ry = 0, length = 72 }, -- over the lake's neck, along z
		StoneBridge = { x = -258, z = -608, ry = 0, length = 62 }, -- over the pond's waist
		Rink = { x = -150, z = -570, ry = 0 },
		FountainNE = { look = "SmallFountain", x = -150, z = -990, ry = 0 },
		FountainW = { look = "SmallFountain", x = -950, z = -760, ry = 0 },
	},
	plazas = { -- paved rounds (x, z, r) round the places
		{ x = -590, z = -640, r = 30 },
		{ x = -150, z = -990, r = 18 },
		{ x = -950, z = -760, r = 16 },
		{ x = -820, z = -592, r = 26 },
		{ x = -150, z = -570, r = 0, rect = { 84, 54 } }, -- the rink's apron
		{ x = -610, z = -565, r = 0, rect = { 50, 40 } }, -- the bandshell's lawn seats
	},

	-- the paths: polylines through the park, smoothed (Catmull-Rom) and laid as flat lengths `step` studs apart.
	-- kind: the Mall (flagstone), drive (asphalt), track (the reservoir's running loop, packed earth), walk.
	path = {
		step = 11,
		width = { mall = 16, drive = 10, walk = 7, track = 8 },
		kit = { mall = "Flagstone", drive = "Asphalt", walk = "Paving" },
		y = 0.15, -- the top above the grass (alternate lengths sit 0.03 higher: no z-fighting where they overlap)
		thick = 0.3,
	},
	paths = {
		{ kind = "mall", pts = { { -590, -513 }, { -590, -560 }, { -590, -612 } } },
		{
			kind = "drive",
			loop = true,
			pts = { -- round the lake
				{ -835, -740 },
				{ -815, -680 },
				{ -760, -652 },
				{ -690, -650 },
				{ -640, -684 },
				{ -600, -668 },
				{ -540, -654 },
				{ -480, -670 },
				{ -438, -700 },
				{ -405, -730 },
				{ -405, -785 },
				{ -450, -826 },
				{ -540, -828 },
				{ -640, -830 },
				{ -740, -832 },
				{ -805, -815 },
				{ -838, -780 },
			},
		},
		{ kind = "track", ellipse = { x = -470, z = -975, rx = 205, rz = 90 } },
		{ kind = "drive", ellipse = { x = -245, z = -795, rx = 160, rz = 110 } }, -- round the Great Lawn
		{ kind = "walk", pts = { { -73, -800 }, { -86, -797 } } }, -- the east gate onto it
		{ kind = "walk", pts = { { -1007, -800 }, { -945, -790 }, { -880, -762 }, { -838, -760 } } }, -- the west gate
		{ kind = "walk", pts = { { -470, -1077 }, { -470, -1065 } } }, -- the north gate to the track
		{
			kind = "walk",
			pts = { { -860, -1077 }, { -862, -1015 }, { -800, -985 }, { -730, -965 }, { -676, -975 } },
		}, -- the north-west gate, round the North Meadow to the track
		{
			kind = "walk",
			pts = { { -150, -1077 }, { -150, -1008 }, { -150, -972 }, { -200, -935 }, { -240, -914 } },
		}, -- the north-east gate by the fountain down to the lawn loop
		{ kind = "walk", pts = { { -150, -972 }, { -215, -985 }, { -266, -978 } } }, -- that fountain to the track
		{ kind = "walk", pts = { { -470, -885 }, { -500, -862 }, { -555, -845 }, { -600, -830 } } }, -- the Ramble
		{ kind = "walk", pts = { { -380, -888 }, { -352, -862 }, { -372, -838 }, { -410, -812 } } },
		{ kind = "walk", pts = { { -640, -830 }, { -640, -800 }, { -640, -770 } } }, -- to the Bow Bridge's north end
		{ kind = "walk", pts = { { -640, -688 }, { -640, -694 } } }, -- its south end onto the drive
		{ kind = "walk", pts = { { -150, -513 }, { -150, -536 }, { -150, -543 } } }, -- the south-east gate to the rink
		{ kind = "walk", pts = { { -192, -568 }, { -230, -566 }, { -258, -572 } } }, -- the rink to the stone bridge
		{ kind = "walk", pts = { { -258, -646 }, { -250, -668 }, { -240, -686 } } }, -- the bridge up to the lawn loop
		{
			kind = "walk",
			pts = { { -590, -585 }, { -530, -578 }, { -455, -590 }, { -420, -600 } },
		}, -- the Mall east to the North Park safehouse
		{ kind = "walk", pts = { { -380, -600 }, { -330, -590 }, { -285, -572 }, { -258, -572 } } },
		{
			kind = "walk",
			pts = { { -880, -513 }, { -868, -548 }, { -846, -580 } },
		}, -- the south-west gate to the carousel
		{ kind = "walk", pts = { { -796, -606 }, { -770, -630 }, { -760, -652 } } }, -- the carousel to the lake drive
		{ kind = "walk", pts = { { -945, -790 }, { -950, -776 } } }, -- the west fountain
		{ kind = "walk", pts = { { -405, -790 }, { -412, -800 } } }, -- the lake drive meets the lawn loop
	},
	safeClear = 30, -- studs kept clear round a safehouse inside the park (its pad is Config.World.safehouse.pad)

	-- what the park's things are made of: Art.Park piece -> colour, material, transparency (Shared.ParkLayout uses
	-- Config.ParkArt for each piece's size and offset)
	looks = {
		Bandshell = {
			BandStage = { { 196, 186, 168 }, "Limestone" },
			BandShell = { { 244, 236, 220 }, "SmoothPlastic" },
			BandRibs = { { 220, 206, 178 }, "Limestone" },
			BandSteps = { { 180, 172, 158 }, "Limestone" },
			BandLights = { { 255, 226, 160 }, "Neon" },
		},
		Carousel = {
			CarouselBase = { { 128, 34, 40 }, "WoodPlanks" },
			CarouselCore = { { 236, 200, 110 }, "SmoothPlastic" },
			CarouselRoof = { { 206, 52, 58 }, "Fabric" },
			CarouselStripes = { { 248, 240, 226 }, "Fabric" },
			CarouselPoles = { { 222, 182, 92 }, "Metal" },
			CarouselHorses = { { 246, 242, 236 }, "SmoothPlastic" },
			CarouselSaddles = { { 64, 110, 190 }, "SmoothPlastic" },
			CarouselLights = { { 255, 230, 170 }, "Neon" },
		},
		Boathouse = {
			BoatWalls = { { 150, 102, 70 }, "Wood" },
			BoatRoof = { { 92, 140, 120 }, "Slate" },
			BoatTrim = { { 238, 232, 216 }, "SmoothPlastic" },
			BoatGlass = { { 150, 196, 214 }, "Glass", 0.35 },
			BoatDeck = { { 140, 110, 78 }, "WoodPlanks" },
			BoatPilings = { { 96, 74, 56 }, "Wood" },
		},
		Terrace = {
			TerraceBasin = { { 206, 194, 172 }, "Limestone" },
			TerracePool = { { 96, 178, 200 }, "Glass", 0.3 },
			TerracePedestal = { { 196, 184, 160 }, "Limestone" },
			TerraceBowls = { { 210, 198, 176 }, "Limestone" },
			TerraceBowlWater = { { 120, 196, 214 }, "Glass", 0.25 },
			TerraceFinial = { { 226, 182, 84 }, "Metal" },
		},
		SmallFountain = {
			SmallBasin = { { 200, 190, 170 }, "Limestone" },
			SmallPool = { { 96, 178, 200 }, "Glass", 0.3 },
			SmallSpout = { { 190, 180, 160 }, "Limestone" },
		},
		BowBridge = {
			BowDeck = { { 150, 118, 86 }, "WoodPlanks" },
			BowRails = { { 236, 228, 206 }, "Metal" },
			BowGirders = { { 230, 220, 196 }, "Metal" },
			BowUrns = { { 210, 200, 180 }, "Limestone" },
		},
		StoneBridge = {
			StoneArch = { { 150, 136, 120 }, "Slate" },
			StoneParapet = { { 170, 158, 140 }, "Slate" },
			StoneDeck = { { 128, 120, 110 }, "Cobblestone" },
		},
		Rink = {
			RinkBoards = { { 236, 240, 244 }, "SmoothPlastic" },
			RinkTrim = { { 40, 92, 170 }, "SmoothPlastic" },
			RinkIce = { { 220, 236, 246 }, "Ice" },
		},
		GatePillar = {
			PillarStone = { { 172, 160, 142 }, "Slate" },
			PillarCap = { { 196, 186, 168 }, "Limestone" },
			PillarLamp = { { 255, 228, 170 }, "Neon" },
		},
		GateSign = {
			SignBoard = { { 46, 86, 62 }, "SmoothPlastic" },
			SignFrame = { { 40, 40, 44 }, "Metal" },
		},
		ParkWall = {
			WallStone = { { 150, 140, 124 }, "Slate" },
			WallCap = { { 186, 178, 162 }, "Limestone" },
		},
		ParkRail = { RailIron = { { 48, 54, 52 }, "Metal" } },
		Reeds = { Reeds = { { 108, 140, 70 }, "Grass" }, ReedHeads = { { 120, 84, 52 }, "Fabric" } },
		LilyPads = { LilyPads = { { 70, 140, 70 }, "Grass" }, LilyFlowers = { { 246, 206, 222 }, "SmoothPlastic" } },
		-- the device's living things (Fx.ParkLife; never on the server)
		Rowboat = {
			RowHull = { { 196, 78, 60 }, "Wood" },
			RowSeats = { { 170, 132, 92 }, "WoodPlanks" },
			RowOars = { { 150, 116, 80 }, "Wood" },
		},
		Duck = {
			DuckBody = { { 150, 120, 90 }, "SmoothPlastic" },
			DuckHead = { { 40, 110, 70 }, "SmoothPlastic" },
			DuckBill = { { 236, 170, 60 }, "SmoothPlastic" },
		},
		Dog = {
			DogBody = { { 176, 120, 70 }, "SmoothPlastic" },
			DogHead = { { 176, 120, 70 }, "SmoothPlastic" },
			DogLeg = { { 150, 100, 60 }, "SmoothPlastic" },
			DogTail = { { 176, 120, 70 }, "SmoothPlastic" },
		},
		Picnic = {
			Blanket = { { 200, 60, 60 }, "Fabric" },
			BlanketCheck = { { 246, 240, 230 }, "Fabric" },
			Basket = { { 170, 120, 70 }, "Fabric" },
		},
		Guitar = { GuitarBody = { { 176, 98, 46 }, "Wood" }, GuitarNeck = { { 70, 48, 34 }, "Wood" } },
		GuitarCase = { CaseShell = { { 40, 40, 46 }, "Fabric" }, CaseLining = { { 150, 40, 60 }, "Fabric" } },
	},
	-- dog coats and duck kinds (by hash)
	dogCoats = { { 176, 120, 70 }, { 60, 52, 48 }, { 236, 226, 206 }, { 200, 160, 100 }, { 120, 84, 60 } },
	duckKinds = { -- body, head (a mallard drake, a hen, a white duck)
		{ { 150, 130, 110 }, { 40, 110, 70 } },
		{ { 150, 120, 90 }, { 140, 110, 84 } },
		{ { 246, 244, 238 }, { 246, 244, 238 } },
	},

	-- the park's life on each device (Fx.ParkLife), by preset; radius: how far from the camera it lives
	life = {
		budget = {
			low = { radius = 220, joggers = 3, walkers = 2, dogs = 1, picnics = 3, buskers = 1, ducks = 6, boats = 3, jets = 2, spin = true },
			medium = { radius = 360, joggers = 6, walkers = 5, dogs = 3, picnics = 6, buskers = 2, ducks = 12, boats = 5, jets = 4, spin = true },
			high = { radius = 520, joggers = 10, walkers = 8, dogs = 5, picnics = 10, buskers = 3, ducks = 20, boats = 7, jets = 6, spin = true },
		},
		jog = { speed = 13, bob = 0.25 }, -- studs a second along the track and the drives
		walk = { speed = 5 },
		dog = { trot = 1.6, wag = 9, lead = 4 }, -- a dog trots at its walker's side `lead` studs ahead
		duck = { speed = 2.5, turn = 0.8, scare = 22, flee = 9, back = 18 }, -- a hero or a bang this close scatters them
		boat = { drift = 1.2, bob = 0.3, rock = 0.06, splashRock = 0.4 },
		carousel = { rpm = 3.2, horseBob = 1.1 },
		jet = { rate = 26, speed = 18, size = 1.1, terraceRate = 60 },
		burst = { radius = 26, time = 6, rate = 220, speed = 55 }, -- a big impact this close bursts a fountain
		splash = { rate = 160, speed = 45, ring = 18, time = 1.2 }, -- an impact on the water throws a splash
		busk = { volume = 0.35, range = 60 },
		people = 900000, -- the id space park people take their looks from (CitizenRenderer.borrow)
	},
	sounds = {
		busk = { asset = 0, fallback = "rbxasset://sounds/electronicpingshort.wav", volume = 0.2, pitch = 0.6 }, -- PLACEHOLDER SOUND
		splash = { asset = 0, fallback = "rbxasset://sounds/action_falling.mp3", volume = 0.5, pitch = 0.7 },
		burst = { asset = 0, fallback = "rbxasset://sounds/action_falling.mp3", volume = 0.6, pitch = 1.2 },
		quack = { asset = 0, fallback = "rbxasset://sounds/swoosh.wav", volume = 0.3, pitch = 2.2 }, -- PLACEHOLDER SOUND
	},
}
