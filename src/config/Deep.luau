-- Underwater (nate 2026-11-16: "no underwater comes now"): the bay and the sea become play space at launch.
-- The water is Roblox Terrain water (real swimming and buoyancy); everything else is built in code like the
-- rest of the city (Shared.DeepLayout). Heroes are supers: no air meter, no drowning. (tune)
-- Areas:
--   The Sunken Line  a flooded subway under the Docks, reached from the harbour basin's floor
--   Coral Shelf      the shallow sea off the south beach: reef, shipwrecks, sunken cargo caches
--   The Trench       the deep sea past the shelf: a sunken factory (the Act 2 mission pocket) and the
--                    Leviathan Engine's arena
-- Coordinates: the map runs -2,400 to 2,400 (City.mapSize); the water surface is World.coast.waterY.
return {
	-- the swimmable ring of sea all around the coast, sloping from `shore` deep at the beach to `outer`
	fillChunk = 512, -- the largest Terrain FillBlock side; bigger fills are split (DeepLayout.chunks)
	ring = { width = 600, bands = 4, shore = 10, outer = 42, wall = 8 },
	basin = { floor = -36, wall = 4 }, -- the harbour basin (City.docks.basin) dug down to this floor
	-- the Sunken Line: a tunnel west from the basin's west wall to a flooded station
	sunkenLine = {
		fromX = 440, -- the basin's west wall
		toX = 120,
		z = 676,
		width = 24,
		floor = -36,
		height = 18,
		wall = 3,
		cars = { 230, 300, 370 }, -- train car centres along x
		car = { width = 11, height = 11, length = 54 },
		station = { minX = 120, maxX = 205, width = 64, platform = 6 },
	},
	shelf = {
		minX = -1400,
		maxX = 1400, -- the south ring (z from the map edge to the ring's outer edge)
		seed = 20261118,
		reefs = 42,
		wrecks = 3,
	},
	trench = {
		minX = -450,
		maxX = 450,
		minZ = 3000,
		maxZ = 3600,
		floor = -240,
		deepBelow = -160, -- below this y the Trench's depths run at zoneFloor.trenchDeep
		wall = 12,
		factory = { x = 0, z = 3430, sx = 180, sy = 70, sz = 110, chimneys = 4 },
		arena = { x = 0, z = 3260, radius = 240 }, -- where the Leviathan Engine surfaces
	},
	-- sunken cargo caches on the shelf and in the trench: swim close to open one (once per hero per cooldown)
	caches = {
		count = 10,
		reach = 9,
		cooldown = 900,
		seed = 77, -- pay: Economy.earn.deepCache; gear: Loot.sources.deepCache
		markRange = 250, -- the client shows cache markers this close
	},
	-- commuters trapped in air pockets in the Sunken Line: swim one out to the quay
	rescues = {
		reach = 8,
		respawn = 240,
		quay = { x = 470, z = 545, reach = 18 }, -- swim the commuter here (pay: Economy.earn.deepRescue)
	},
	-- zone level floors underwater (ZoneLevel: rewards follow the area, not the hero)
	-- (trenchDeep: the Trench below trench.deepBelow, added with the level cap at 50 on 2026-11-17)
	zoneFloor = { basin = 3, line = 6, shelf = 12, sea = 10, trench = 25, trenchDeep = 35 },
	-- underwater robots spawn only around heroes who are underwater (EnemySim.populate); weights
	mix = { Diver = 5, Anchor = 2, TorpedoSentry = 1.5 },
	-- element reactions in water (a hero casting while underwater)
	reactions = {
		stormJump = 1.5, -- Storm chains jump 50% farther
		fireBlind = 1.5, -- Fire turns to steam bursts that blind (seconds) and push
		fireKnock = 8,
		frostPlatform = { size = 16, life = 8 }, -- Frost freezes a floating ice platform at the surface
		earthHide = 2, -- Earth stirs a silt cloud: robots lose the hero this long
		tideDamage = 1.25, -- Tide: every ability is stronger and faster
		tideCooldown = 0.8,
	},
	-- the underwater look (DeepClient): tint, fog and bubbles when the camera is below the surface
	look = {
		tint = { 70, 150, 200 },
		deepTint = { 20, 60, 110 }, -- at the trench floor
		haze = { 0.62, 0.85 }, -- Atmosphere density just under the surface and at the trench floor (the sky has one)
		fogStart = 10, -- Lighting fog, only for a place with no Atmosphere
		fogEnd = 160,
		bubbles = 0.08, -- seconds between bubbles from a moving hero
	},
}
