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
-- * ry = "box": the placement turns with its core box (a chain on a diagonal); a `with` entry { sig, n, "keep" }:
--   boxes the look frames but leaves drawn (never hidden; gap-props3)
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
		-- the second set (gap-props3, 2026-11-19; Config.PocketPropArt2, Art.PocketProps2)
		-- the Halo Academy: Halo's statue on its plinth under the gold halo, the blackboards, the training hall's
		-- hoops, the bookcase by the hidden door, the copier workshop's conveyor and its half-built copy robots
		{
			look = "PkStatue",
			layout = "academy",
			core = "prop:white:4:8:3",
			with = { { "prop:white:12:4:12", 1 }, { "glow:beaconGlow:7:0.6:7", 1 } },
			reach = 1,
			face = { 0, 195 },
			count = 1,
		},
		{
			look = "PkBlackboard",
			layout = "academy",
			core = "prop:slate:1:10:34",
			face = { 0, 65 },
			count = 2,
		},
		{
			look = "PkHoop",
			layout = "academy",
			core = "prop:steel:1:18:1",
			with = { { "glow:beaconGlow:6:0.5:6", 1 } },
			reach = 2.1,
			count = 2,
		},
		{ look = "PkBookcase", layout = "academy", core = "prop:wood:14:14:3", face = { 0, 50 }, count = 1 },
		{ look = "PkConveyor", layout = "academy", core = "prop:steel:300:3:10", count = 1 },
		{
			look = "PkHalfBot",
			layout = "academy",
			core = "prop:nullMetal:4:7:3",
			with = { { "glow:nullGlow:2:0.6:0.4", 1 } },
			reach = 1.7,
			face = { 0, 0 },
			count = 7,
		},
		-- Iron Hall: the trophy shelves (three shelves and their 21 cups), the locker room bench, the wooden
		-- dummies, the iron door, Hoshi's cage and its four chains
		{
			look = "PkTrophyShelf",
			layout = "ironhall",
			core = "prop:wood:3:0.6:80",
			with = { { "prop:wood:3:0.6:80", 2 }, { "prop:bank:2:2.4:2", 21 } },
			reach = 31,
			face = { 143, 65 },
			count = 1,
		},
		{ look = "PkBench", layout = "ironhall", core = "prop:wood:60:2:4", count = 1 },
		{
			look = "PkWoodDummy",
			layout = "ironhall",
			core = "prop:wood:1.5:6:1.5",
			with = { { "prop:wood:5:0.8:0.8", 1 } },
			reach = 0.1,
			count = 2,
		},
		{
			look = "PkIronDoor",
			layout = "ironhall",
			core = "prop:steel:14:14:3",
			face = { 0, 50 },
			count = 1,
		},
		{
			look = "PkHoshiCage",
			layout = "ironhall",
			core = "prop:steel:24:1:24",
			with = { { "prop:steel:1:14:1", 4 } },
			reach = 17.1,
			count = 1,
		},
		{ look = "PkChain", layout = "ironhall", core = "prop:steel:0.6:0.6:26", ry = "box", count = 4 },
		-- Ashgrove Labs: the sealed door slid aside
		{ look = "PkSealDoor", layout = "ashlab", core = "prop:steel:14:14:3", face = { 0, 50 }, count = 1 },
		-- the Spark Pound: the roll door and its slats, the intake's scanner arch, the dock crates
		{
			look = "PkRollDoor",
			layout = "pound",
			core = "glow:window:40:18:1",
			with = { { "prop:steel:40:0.5:0.4", 5 } },
			reach = 0.9,
			count = 1,
		},
		{
			look = "PkScanArch",
			layout = "pound",
			core = "prop:steel:1.5:14:1.5",
			with = { { "prop:steel:1.5:14:1.5", 1 }, { "glow:relicRed:13.5:1:1.5", 1 } },
			reach = 12.1,
			count = 1,
		},
		{ look = "PkDockCrate", layout = "pound", core = "prop:cargo:10:6:10", count = 2 },
		-- the missions: the power stations, Crane Tower's broadcast mast, Live's stage (its giant screen kept)
		{
			look = "PkStation",
			layout = "station",
			core = "prop:steel:8:8:4",
			with = { { "glow:beaconGlow:6:3:0.4", 1 } },
			reach = 2.3,
			count = 3,
		},
		{
			look = "PkMast",
			layout = "tower",
			core = "prop:steel:3:30:3",
			with = { { "glow:beaconGlow:4:4:4", 1 } },
			reach = 0.1,
			count = 1,
		},
		{
			look = "PkStage",
			layout = "arena",
			core = "building:slate:120:3:40",
			with = { { "glow:beaconGlow:140:46:2", 1, "keep" } },
			reach = 30,
			count = 1,
		},
	},
}
