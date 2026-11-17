-- Collections (spec: Hero MMO features > Collections; H7). Pure data, tuned in the playtest.
-- Twelve sets of 5 to 10 items (89 items); a full set pays Renown and an HQ prop (Config.Hq.props 7 to 18)
-- and counts toward the Show-off badges (fixed looks; the travel styles come with H8). Rewards show before you start a set (the Collections page).
-- * hidden: spots in the hub and districts, placed from the city's own layout with a fixed seed (Shared.
--   CollectPlan), so they sit on open ground or a roof on every world seed; they sparkle within `sparkle`
--   studs with a soft chime, and you pick one up by passing within `reach`.
-- * weekly: Star Charms (id CometShards), spots in the outskirts placed by the weekly world seed, so they move each week
--   (a shard found last week is still yours; this week's spots pay the same bits again only if missing).
-- * drops: a small chance from defeats, never paid. earned: from the Hero MMO features.
-- The save: profile.mmo.collect (4 words, 128 bits); an item's bit is its set's `at` + its place - 1.
-- Names are fixed text. PLACEHOLDER ART: the finds are simple glowing parts until the Blender pass.
return {
	bits = 128,
	sparkle = 40, -- studs: a find sparkles and chimes on your device this close
	reach = 8, -- studs: walking or flying this close picks it up
	checkEvery = 0.5, -- seconds between the server's pickup checks
	seed = 7171, -- the fixed seed for the hidden spots (the weekly set uses the world seed)
	minGap = 30, -- studs between two finds of a set
	scanner = { cost = 2500 }, -- the HQ Scanner station: one purchase (Credits), then a marker points at the
	-- nearest find you are missing in the area you are in
	dropChance = 0.02, -- a robot defeat drops its kind's part (once you are missing it)
	plateChance = 0.35, -- a world boss defeat drops one of its plates you are missing
	sets = {
		{
			id = "ComicCovers",
			name = "Comic Covers",
			kind = "hidden",
			at = 0,
			count = 8,
			area = "Downtown", -- on the street in Downtown
			place = "street",
			reward = { renown = 1500, prop = 7 }, -- Comic Rack (Config.Hq.props)
		},
		{
			id = "LostToys",
			name = "Lost Toys",
			kind = "hidden",
			at = 8,
			count = 8,
			area = "OldTown",
			place = "street",
			reward = { renown = 1500, prop = 8 }, -- Toy Shelf (Config.Hq.props)
		},
		{
			id = "ShipBells",
			name = "Ship Bells",
			kind = "hidden",
			at = 16,
			count = 8,
			area = "Docks",
			place = "street",
			reward = { renown = 1500, prop = 9 }, -- Ship's Bell (Config.Hq.props)
		},
		{
			id = "DeepRelics",
			name = "Deep Relics",
			kind = "hidden",
			at = 24,
			count = 8,
			area = "deep", -- on the seabed of the sea ring and the Coral Shelf
			place = "seabed",
			reward = { renown = 2500, prop = 10 }, -- Relic Case (Config.Hq.props)
		},
		{
			id = "RoofPigeons",
			name = "Roof Pigeons",
			kind = "hidden",
			at = 32,
			count = 8,
			area = "roofs", -- on the hub's tall roofs (Downtown and Uptown), 120 studs up or more
			place = "roof",
			minHeight = 120,
			reward = { renown = 2000, prop = 11 }, -- Pigeon Coop (Config.Hq.props)
		},
		{
			id = "CometShards",
			name = "Star Charms", -- not "Comet": the old lore word (id kept)
			kind = "weekly",
			at = 40,
			count = 8,
			area = "outskirts", -- the suburbs, farmland and coast, placed by the weekly seed
			place = "ground",
			reward = { renown = 3000, prop = 12 }, -- Star Lamp (Config.Hq.props)
		},
		{
			id = "RobotParts",
			name = "Robot Parts",
			kind = "drop",
			at = 48,
			count = 10,
			-- one part per robot kind, in this order
			items = {
				"SparkDrone",
				"BurglarBot",
				"SneakBot",
				"BruteBot",
				"Turret",
				"NullSentinel",
				"ShieldBearer",
				"Captain",
				"Sniper",
				"Bomber",
			},
			reward = { renown = 2000, prop = 13 }, -- Parts Rack (Config.Hq.props)
		},
		{
			id = "BossPlates",
			name = "Boss Plates",
			kind = "drop",
			at = 58,
			count = 6,
			-- two plates per world boss (Config.Boss.order), in this order
			bosses = { "RustjawPrime", "LumenMaw", "LeviathanEngine" },
			reward = { renown = 3000, prop = 14 }, -- Boss Plate Wall (Config.Hq.props)
		},
		{
			id = "NemesisCores",
			name = "Nemesis Cores",
			kind = "earned",
			at = 64,
			count = 5, -- one per Showdown rank won (H5)
			reward = { renown = 4000, prop = 15 }, -- Core Case (Config.Hq.props)
		},
		{
			id = "ContestRibbons",
			name = "Contest Ribbons",
			kind = "earned",
			at = 72,
			count = 6, -- enter, vote 10 times, 3rd, 2nd, 1st, 3 wins
			reward = { renown = 2500, prop = 16 }, -- Ribbon Board (Config.Hq.props)
		},
		{
			id = "MentorKeepsakes",
			name = "Mentor Keepsakes",
			kind = "earned",
			at = 80,
			count = 8, -- each mentor's quest part 2 and part 4 (H6), in Config.Mentors order
			reward = { renown = 3000, prop = 17 }, -- Keepsake Box (Config.Hq.props)
		},
		{
			id = "TaskForcePatches",
			name = "Task Force Crests", -- not "Patches": Patch is a lore character
			kind = "earned",
			at = 88,
			count = 6, -- each task force's clear, speed clear (under 20 min) and full-squad clear (H4)
			reward = { renown = 3000, prop = 18 }, -- Crest Banner (Config.Hq.props)
		},
	},
	-- the contest ribbons in order (ContestService)
	ribbons = { enter = 1, votes = 2, third = 3, second = 4, first = 5, wins3 = 6 },
	ribbonVotes = 10, -- votes cast for the ribbon
}
