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
	ceilingCloudY = 500,
	-- Muted building colours so saturated hero colours pop (spec: Style guide)
	palette = {
		concrete = { 158, 156, 150 },
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
	},
	partBudget = { downtown = 6000 }, -- greybox part count ceiling (hub budget 55,000 in the spec)
}
