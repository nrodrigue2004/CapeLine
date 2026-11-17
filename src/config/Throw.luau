-- Pick up and throw (spec: Hero MMO features > Pick up and throw; H3). Pure data, tuned in the playtest.
-- Anyone can grab things in the world: light and medium things for everyone, heavy things (cars, trucks,
-- big rubble slabs) for Powerhouse heroes and for anyone Awakened. Citizens and heroes are never lifted.
-- Rules live in Shared.ThrowMath; the server (ThrowService) and the client (ThrowClient, ThrowFx) read this.
return {
	reach = 10, -- the Grab prompt shows on the nearest liftable thing this close
	liftTime = 0.3, -- seconds to raise it overhead (no throw before then)
	carrySpeed = 0.8, -- you move at 80% while carrying (no flight boost)
	carryMax = 8, -- after this long it is set down where you stand
	overhead = 4.5, -- studs above the hero's root where it rides
	grabRate = 4, -- WorldGrab and WorldThrow per second (Remotes)
	heavyFor = { Powerhouse = true }, -- archetypes that lift heavy things without Awakening
	minFlight = 0.35, -- seconds: the shortest flight
	-- the three weights: thrown hit coefficient, knock (studs), landing radius, structure damage (kind 2 is a
	-- blast, kind 1 a crater), range, flight speed (studs a second) and arc height (a share of the distance)
	weights = {
		light = { coeff = 0.8, knock = 6, radius = 6, struct = 0, range = 70, speed = 90, arc = 0.22 },
		medium = {
			coeff = 1.6,
			knock = 10,
			radius = 8,
			struct = 300,
			structKind = 2,
			range = 55,
			speed = 75,
			arc = 0.25,
		},
		heavy = {
			coeff = 3.0,
			knock = 14,
			radius = 12,
			struct = 1200,
			structKind = 1,
			range = 40,
			speed = 60,
			arc = 0.3,
			breaker = true,
		},
	},
	-- what each liftable kind is (props are built by ThrowService; vehicles come from VehicleService).
	-- size: the prop's box (x, y, z studs). PLACEHOLDER ART: plain parts until the street kit's meshes.
	kinds = {
		bench = {
			weight = "light",
			size = { 5, 2.6, 1.8 },
			color = { 150, 102, 64 },
			material = "WoodPlanks",
		},
		trashCan = { weight = "light", size = { 2, 3, 2 }, color = { 60, 84, 72 }, material = "Metal" },
		mailbox = { weight = "light", size = { 1.8, 3.6, 1.6 }, color = { 44, 82, 160 }, material = "Metal" },
		sign = { weight = "light", size = { 2.4, 5, 0.4 }, color = { 230, 190, 40 }, material = "Metal" },
		rubble = {
			weight = "light",
			size = { 2.4, 1.6, 2 },
			color = { 140, 136, 128 },
			material = "Concrete",
		},
		lampPost = { weight = "medium", size = { 0.8, 10, 0.8 }, color = { 48, 60, 56 }, material = "Metal" },
		dumpster = { weight = "medium", size = { 6, 4, 3.5 }, color = { 46, 110, 70 }, material = "Metal" },
		vending = {
			weight = "medium",
			size = { 3, 6, 2.4 },
			color = { 190, 50, 50 },
			material = "SmoothPlastic",
		},
		slab = { weight = "heavy", size = { 8, 2.4, 6 }, color = { 128, 124, 118 }, material = "Concrete" },
		car = { weight = "heavy", vehicle = true }, -- VehicleService's cars
		truck = { weight = "heavy", vehicle = true }, -- VehicleService's trucks (the spec's van)
		-- trams stay on their lines (34 studs long): they only flip
	},
	-- where props stand: each Downtown sidewalk along the north-south streets gets `perSide` props, drawn
	-- from `mix` (kind -> weight of the draw) with a fixed seed so every server matches
	place = {
		seed = 31,
		perSide = 2,
		inset = 17.5, -- from the street's middle to the sidewalk's (street 30 / 2 + sidewalk 5 / 2)
		spread = 36, -- studs along the sidewalk either side of the block's middle
		mix = {
			{ "bench", 3 },
			{ "trashCan", 3 },
			{ "mailbox", 2 },
			{ "sign", 2 },
			{ "rubble", 1 },
			{ "lampPost", 1 },
			{ "dumpster", 2 },
			{ "vending", 2 },
			{ "slab", 1 },
		},
	},
	respawn = 60, -- a thrown prop comes back this long after landing, once no hero is within `viewRadius`
	viewRadius = 120,
	-- Titan's Lift and Throw stays the strong version: it lifts any weight from further, with a bigger nova
	titan = { reach = 20, radiusMult = 1.4 },
}
