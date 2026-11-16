-- Destruction (spec: World > Destruction; Clash moments: Knockback arc, Grab and slam, Vehicle flip, Stomp
-- wave). The server keeps a state per hub building (Intact, Damaged, Collapsed) and the client draws every
-- chunk, crack and dust cloud. (tune)
return {
	hubBuildings = 220, -- destructible buildings in the hub: all of Downtown, the Docks warehouses, the rest from Old Town
	hp = { small = 6000, medium = 10000, tower = 14000 }, -- structure HP by size
	smallMax = 30, -- a building up to this tall (2 or so floors) is small
	mediumMax = 150, -- up to this tall is medium, taller is a tower
	damagedAt = 0.4, -- 40% of structure HP lost: Damaged
	warnAt = 0.75, -- 75% lost: citizens nearby run for shelter (they are gone before any collapse)
	superStruct = 3000, -- supers with no structDmg of their own
	bossStruct = 2000, -- boss attacks (M6)
	maxCollapses = 3, -- collapses at once per server; a fourth is cut to Damaged
	collapseTime = 6, -- the collapse animation on the client; "at once" means started within this window
	repair = {
		dronesPerDistrict = 3,
		damagedAfter = 180, -- quiet seconds before a Damaged building is repaired
		collapsedAfter = 240,
		each = 20, -- seconds a drone spends on one building
	},
	diffRate = 2, -- Building.Diff batches per second
	impactRate = 6, -- impact notices per second per server (cracks and craters on clients)
	impactRadius = 300, -- players this close hear about an impact
	-- the Chunker: each building splits into 10 to 40 chunks (rows of floors, 1 or 2 across each way)
	chunks = { min = 10, max = 40, floor = 12, fallMin = 4, fallMax = 8, wideAt = 30 },
	rubble = { min = 6, max = 10, height = 12 },
	-- clash moments
	clash = { wallRange = 20, perPlayer = 3, window = 10, knock = 26 },
	crater = { radius = 6, life = 30 },
	-- cars and trams
	vehicles = {
		count = 40, -- in the hub
		trams = 8,
		flipTime = 1, -- the scripted flip arc
		resetAfter = 30,
		perDistrict = 6, -- flipped at once in one district
		flipHeight = 12,
		flipTravel = 14,
		hitRadius = 10, -- a heavy single hit flips vehicles this close to the target
	},
	-- citizens (never hurt, never shown hurt; they run to shelter)
	citizens = {
		max = 60,
		walk = 6,
		run = 18,
		fleeRadius = 55,
		hideFor = { 20, 40 }, -- seconds a citizen stays inside a shelter
		pauseChance = 0.25,
		pause = { 1, 4 },
		step = 0.1, -- sim step (10 Hz)
		sendRate = 4,
		relevance = 250, -- players see citizens this close
		colorSets = 6,
		-- shirt, trousers, skin for each colour set (cartoon tones, PLACEHOLDER ART until the art pass)
		colors = {
			{ { 236, 84, 72 }, { 52, 62, 92 }, { 255, 214, 170 } },
			{ { 70, 150, 230 }, { 70, 64, 60 }, { 198, 140, 96 } },
			{ { 250, 200, 60 }, { 40, 44, 52 }, { 141, 95, 64 } },
			{ { 96, 190, 120 }, { 110, 86, 64 }, { 240, 190, 150 } },
			{ { 186, 110, 220 }, { 60, 70, 80 }, { 92, 62, 44 } },
			{ { 245, 245, 240 }, { 30, 90, 140 }, { 224, 172, 130 } },
		},
		drawDelay = 0.3, -- clients draw citizens this far in the past (packets come 4 times a second)
	},
}
