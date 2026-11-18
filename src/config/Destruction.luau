-- Destruction (spec: World > Destruction; Clash moments: Knockback arc, Grab and slam, Vehicle flip, Stomp
-- wave). The server keeps a state per hub building (Intact, Damaged, Collapsed) and the client draws every
-- chunk, crack and dust cloud. (tune)
return {
	hubBuildings = 220, -- destructible buildings in the hub: all of the first Downtown, the Docks warehouses, the rest from Old Town;
	-- every building of the grown Downtown blocks and Uptown comes after these (ids 221 on; WorldMap.pickBuildings)
	hp = { small = 6000, medium = 10000, tower = 14000 }, -- structure HP by size
	smallMax = 30, -- a building up to this tall (2 or so floors) is small
	mediumMax = 150, -- up to this tall is medium, taller is a tower
	damagedAt = 0.4, -- 40% of structure HP lost: Damaged
	warnAt = 0.75, -- 75% lost: citizens nearby run for shelter (they are gone before any collapse)
	superStruct = 3000, -- supers with no structDmg of their own
	-- every other damaging ability breaks buildings too (nate 2026-11-16: "nothing is destructible"): a basic
	-- hit adds up (3 knock a piece out), a skill knocks out at least one piece. Basics only reach 5 studs.
	slotStruct = { basic = 200, skill = 700 },
	basicStructRadius = 5,
	bossStruct = 2000, -- boss attacks (M6)
	maxCollapses = 3, -- collapses at once per server; a fourth is cut to Damaged
	collapseTime = 6, -- the collapse animation on the client; "at once" means started within this window
	repair = {
		dronesPerDistrict = 3,
		damagedAfter = 180, -- quiet seconds before a Damaged building is repaired
		collapsedAfter = 240,
		each = 20, -- seconds a drone spends on one building
		-- the Ceremony prologue's 6-roof chase row: a row building already wrecked is put back whole when a
		-- prologue starts and again as its hold begins (the leap), so a new hero never hops onto rubble
		-- (Shared.PrologueRow.mend). Interim pick 2026-11-18, nate to OK; false: drones only, as before
		prologueRow = true,
	},
	diffRate = 2, -- Building.Diff batches per second
	impactRate = 6, -- impact notices per second per server (cracks and craters on clients)
	impactRadius = 300, -- players this close hear about an impact
	-- the Chunker: each building splits into 10 to 40 chunks (rows of floors, 1 or 2 across each way)
	chunks = { min = 10, max = 40, floor = 12, fallMin = 4, fallMax = 8, wideAt = 30 },
	rubble = { min = 6, max = 10, height = 12 },
	-- Red Faction-style structure (nate 2026-11-16, Shared.Structure): storeys of corner pillars, wall panels
	-- and floor slabs. Hits knock pieces out; a storey whose pillars and walls carry under `support` of
	-- their weight gives way and everything above comes down; a ground-floor failure is a full collapse.
	structure = {
		storey = 12, -- studs a storey (towers get fewer, taller storeys past maxStoreys)
		maxStoreys = 10,
		panel = 12, -- wall panel width; 1 to maxPanels a face
		maxPanels = 4,
		wall = 2, -- wall thickness
		pillar = 3, -- corner pillar width
		slab = 1.2, -- floor slab thickness
		slabSplitAt = 36, -- slabs split 2 x 2 on buildings this wide both ways
		support = 0.35, -- a storey stands while its pillars and walls keep 35% of their weight
		chunkCost = 600, -- structure damage per piece knocked out (a super's 3,000 takes about 5)
		pillarCost = 2, -- pillars weigh and cost double
		maxPerHit = 10, -- pieces one hit can knock out
		clashPanels = 2, -- a robot thrown through a wall breaks this many panels
		warnLost = 0.3, -- citizens nearby run once 30% of the weight is gone or a storey falls
		debrisLife = 5, -- seconds a loose piece tumbles on the device before it fades
	},
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
		-- Roblox look (2026-11-17): once the heroes' classic Shirt and Pants are uploaded (Config.Creator.clothes),
		-- every citizen wears one shirt and one pants picked from its id, tinted from these colours, with one of
		-- the shared faces (Config.NpcLooks.faces), so the city's people look like Roblox players, each different
		clothesTints = {
			shirts = {
				{ 236, 84, 72 },
				{ 70, 150, 230 },
				{ 250, 200, 60 },
				{ 96, 190, 120 },
				{ 186, 110, 220 },
				{ 245, 245, 240 },
				{ 40, 44, 52 },
				{ 240, 140, 60 },
				{ 90, 200, 210 },
				{ 230, 120, 170 },
				{ 120, 130, 140 },
				{ 150, 60, 60 },
			},
			pants = {
				{ 52, 62, 92 },
				{ 70, 64, 60 },
				{ 40, 44, 52 },
				{ 110, 86, 64 },
				{ 60, 70, 80 },
				{ 30, 90, 140 },
				{ 200, 190, 160 },
				{ 90, 100, 70 },
			},
		},
		-- hair colours, picked per citizen from its id (every citizen is on the blocky R15 rig, like heroes)
		hair = { { 30, 26, 24 }, { 70, 46, 30 }, { 160, 120, 60 }, { 225, 225, 230 }, { 120, 40, 40 } },
		-- body sets (gender, build), picked per citizen from its id: men and women, slim to big, no Titans
		bodies = { { 1, 1 }, { 1, 2 }, { 1, 2 }, { 1, 3 }, { 2, 1 }, { 2, 2 }, { 2, 2 }, { 2, 3 } },
		poseNear = 100, -- citizens this close to the camera pose every frame; farther ones every poseEvery frames
		poseEvery = 3,
		drawDelay = 0.3, -- clients draw citizens this far in the past (packets come 4 times a second)
	},
}
