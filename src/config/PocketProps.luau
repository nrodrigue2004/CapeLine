-- PocketProps: the mission and side quest pockets' most-seen props as Blender meshes (gap-props2, 2026-11-19;
-- art/blender/pocketprops.py, imported as ReplicatedStorage.Art.PocketProps, each look's frame and meshes in the
-- generated Config.PocketPropArt). Shared.PocketPropKit finds each prop's boxes in a built pocket by these rules
-- and lays a look over them; PocketDecor draws them on each device near the camera within its preset's budget
-- (Config.Presets <preset>.pockets.props: meshes a pocket) and hides the boxes they stand in for (never removed:
-- every collision, query and height stays exactly as before). Nothing imported: every box shows as today.
-- A rule (pocket-local studs, as PocketLayout builds them):
-- * look, layout: the look and the pocket it dresses; dress = true: the boxes are PocketDress dressing (each
--   device's own; a dressing look is drawn only where its boxes' tier is within the preset's)
-- * core: the prop's main box, "kind:color:sx:sy:sz" (color "*" any); every unclaimed box that matches is one prop
-- * with: its other boxes { signature, how many }, the nearest unclaimed within `reach` studs (flat) of the core
-- * face: a pocket-local { x, z } the look's front (its -z) turns toward (snapped to a quarter turn); else ry 0
-- * tint: the palette colour a look's tinted meshes take: 0 the core's, n the n-th `with` box's (a dummy's head)
-- * count: how many props the rule finds (tests "Pocket props")
-- Rules run in order and that order is the drawing priority when a preset's budget runs out.
return {
	slack = 0.6, -- studs a look's meshes may reach past their placement (bevels, bolts, a flame's lick)
	rules = {
		-- the Spark Pound's kennel hall: twelve cages and Lark's cell (corner bars, front bars and a lid each)
		{
			look = "PkKennel",
			layout = "pound",
			core = "prop:steel:29:0.4:29",
			with = { { "prop:steel:0.8:14:0.8", 4 }, { "prop:steel:0.4:14:0.4", 3 } },
			reach = 20,
			count = 12,
		},
		{
			look = "PkCell",
			layout = "pound",
			core = "prop:steel:42:0.4:28",
			with = { { "prop:steel:1:16:1", 4 }, { "prop:steel:0.5:16:0.5", 7 } },
			reach = 24,
			count = 1,
		},
		-- the Halo Academy's classrooms: 24 desks and their chairs (dressing, high preset), lockers by the hall
		{ look = "PkDesk", layout = "academy", core = "prop:wood:6:3:4", count = 24 },
		{
			look = "PkChairSchool",
			layout = "academy",
			dress = true,
			core = "prop:pkMatBlue:4:3:2",
			count = 24,
		},
		{
			look = "PkLockerSchool",
			layout = "academy",
			dress = true,
			core = "prop:*:4:8:7",
			face = { 0, 160 },
			tint = 0,
			count = 12,
		},
		-- Iron Hall's locker room
		{
			look = "PkLockerHall",
			layout = "ironhall",
			core = "prop:steel:10:12:4",
			face = { -143, 65 },
			count = 10,
		},
		-- Ashgrove Labs: the records office's filing cabinets, reception's chairs, the sublevel's holding tanks
		{ look = "PkCabinet", layout = "ashlab", core = "prop:steel:8:8:4", face = { 143, 65 }, count = 8 },
		{ look = "PkChairLab", layout = "ashlab", core = "prop:roofBlue:5:3:5", count = 8 },
		{
			look = "PkTank",
			layout = "ashlab",
			core = "prop:glass:10:14:6",
			with = { { "glow:nullGlow:8:1:4", 1 } },
			reach = 1,
			face = { 0, 0 },
			count = 7,
		},
		-- the training floors: the Academy's dummies (a tinted head) and Iron Hall's punching bags
		{
			look = "PkDummy",
			layout = "academy",
			core = "prop:steel:1.5:6:1.5",
			with = { { "prop:*:3:3:3", 1 } },
			reach = 1,
			face = { 0, 50 },
			tint = 1,
			count = 4,
		},
		{
			look = "PkPunchBag",
			layout = "ironhall",
			core = "prop:rust:3:6:3",
			with = { { "prop:steel:0.6:8:0.6", 1 } },
			reach = 1,
			count = 4,
		},
		-- the pads under the copier pods and the Kindlers
		{ look = "PkPad", layout = "academy", core = "prop:steel:9:1:9", count = 4 },
		{ look = "PkPad", layout = "ashlab", core = "prop:steel:9:1:9", count = 4 },
		-- posts: the Kindler's light ring, the Pound's collar scanners, Iron Hall's chain posts
		{ look = "PkPostKindler", layout = "ashlab", core = "prop:steel:2:10:2", count = 8 },
		{ look = "PkPostScan", layout = "pound", core = "prop:steel:2:8:2", count = 4 },
		{ look = "PkPostIron", layout = "ironhall", core = "prop:steel:3:8:3", count = 4 },
		-- Iron Hall's braziers (the fire box drawn as a flame)
		{
			look = "PkBrazier",
			layout = "ironhall",
			core = "prop:steel:4:4:4",
			with = { { "glow:foundryGlow:3:1.2:3", 1 } },
			reach = 1,
			count = 4,
		},
		-- desks with screens: the Pound's intake office, Holloway's work desk, Ashgrove's front desk
		{
			look = "PkDeskOffice",
			layout = "pound",
			core = "prop:wood:16:4:6",
			with = { { "glow:beaconGlow:6:4:0.4", 1 } },
			reach = 3,
			count = 2,
		},
		{
			look = "PkDeskLab",
			layout = "ashlab",
			core = "prop:steel:20:4:8",
			with = { { "glow:window:10:4:0.4", 1 } },
			reach = 4,
			count = 1,
		},
		{
			look = "PkDeskFront",
			layout = "ashlab",
			core = "prop:steel:30:4:6",
			with = { { "glow:beaconGlow:26:0.4:0.4", 1 } },
			reach = 3,
			count = 1,
		},
		-- the missions: Live's camera rigs (solid cover) and crowd barriers, The Copy's chimneys and water tanks
		{
			look = "PkCamera",
			layout = "arena",
			core = "prop:steel:2:6:2",
			with = { { "prop:steel:4:3:5", 1 } },
			reach = 1,
			count = 3,
		},
		{ look = "PkBarrier", layout = "arena", dress = true, core = "prop:steel:10:3:0.6", count = 11 },
		{ look = "PkChimney", layout = "rooftops", dress = true, core = "prop:brick:4:6:4", count = 13 },
		{ look = "PkWaterTank", layout = "rooftops", dress = true, core = "prop:wood:7:8:7", count = 12 },
	},
}
