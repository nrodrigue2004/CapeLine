-- Hq: the Hero HQ and the Hall of Legends (spec: Hero HQ (Beacon Tower or the Foundry); Legacy rebirth).
-- One HQ per side: the Vigil's Safehouse and the Dread Syndicate's Foundry, entered by their doors in the city.
-- nate's lore plan Q1/Q2 (2026-11-17): the Beacon Tower is Crane's Hero Hall now, and the Vigil are hunted, so
-- their HQ is the hideout under the Downtown plaza (the safehouse from mission 2). A visit is solo (friend
-- visits come in Update 2): each visitor gets their own sealed cell far above the map, the server builds its
-- floor and walls, and the device builds the rooms. PLACEHOLDER ART: greybox rooms.
return {
	names = { hero = "The Safehouse", villain = "The Foundry" }, -- the save key stays "hero"
	-- the way in: the Vigil's maintenance stairwell at the plaza's edge (Shared.HqRules.heroDoor) or the
	-- Foundry door (the Docks), your side's only; leaving puts you back outside it
	door = {
		-- the plaza edge it stands on (west: the Ceremony stage faces the rooftop row, east), `along` studs
		-- north along it from its middle (clear of the corner spawns, the contest corner and the quest NPCs),
		-- `inset` studs in from the plaza block's edge; the stairwell head is `size` (width, height, depth)
		edge = { -1, 0 },
		along = 24,
		inset = 10,
		size = { 10, 11, 8 },
		object = "Service Door", -- what everyone reads; a Vigil device swaps in the HQ's name
		locked = "Locked", -- the Syndicate's prompt: a locked service door
		enter = "Go down", -- the Vigil's prompt
		marker = "THE SAFEHOUSE", -- the small marker only the Vigil see
		markerRange = 70,
	},
	-- the Vigil's hideout look, shared by the HQ cell (HqClient) and mission 2's Safehouse pocket
	-- (PocketLayout): City palette keys, the wall height, a lamp every `lampEvery` studs along a wall
	hideout = {
		colors = {
			wall = "tunnel",
			pillar = "concrete",
			floor = "slate",
			pipe = "rust",
			pipeB = "steel",
			tray = "steel",
			lamp = "workLamp",
			screen = "beaconGlow",
			stripe = "containerC",
		},
		height = 30,
		lampEvery = 24,
	},
	-- the hideout art pass (2026-11-19, Shared.HideoutKit): the looks a quality preset leaves as plain parts (phones
	-- keep the ceiling tiles and beam bays plain: the least seen, the most parts) and each preset's ceiling for one
	-- room shell's modules (mesh parts and triangles; tests/hideout_test.luau checks both rooms against it)
	art = {
		skip = { low = { HideCeiling = true, HideBeam = true }, medium = {}, high = {} },
		budget = {
			low = { parts = 160, tris = 50000 },
			medium = { parts = 260, tris = 70000 },
			high = { parts = 260, tris = 70000 },
		},
	},
	doorRange = 14,
	-- the solo cells: one per hero slot (HeroService pvpSlot), on a grid at y 4,500 (safe: no PvP, no
	-- schedulers, out of every streaming range)
	cell = { x0 = 9000, z0 = 9000, y = 4500, gap = 260, perRow = 25, size = 120, wall = 40 },
	-- rooms: offsets from the cell centre (x, z) where each station stands
	stations = {
		command = { 0, -36 }, -- the command table: contracts, story replay, side quest log
		gizmo = { -36, -12 }, -- Gizmo's shop and the Lumen Dust upgrade bench
		mannequins = { 36, -12 }, -- saved looks
		training = { -30, 30 }, -- dummies with a DPS meter
		trophies = { 30, 30 }, -- the trophy wall
		legends = { 0, 44 }, -- the Hall of Legends (statues, Retire at the level cap)
		scanner = { -36, 12 }, -- the HQ Scanner: marks your nearest missing collection find (H7)
		exit = { 0, -54 },
	},
	stationRange = 12,

	-- Upgrades (Credits): levels 2 to 6 cost Config.Economy.hqLevels. What each level opens:
	levels = {
		mannequins = { 1, 4 }, -- level 1: 1 saved look; level 2: 4
		trainingDummies = { 1, 1, 4 }, -- level 3: 4 dummies and the boss sim
		bossSim = 3,
		trophies = { 3, 3, 3, 12 }, -- level 4: 12 trophies and MVP cards
		mvpCards = 4,
		drones = 5, -- offline drones from level 5
	},
	-- Offline drones (spec: 2 Credits a minute at level 5, rising to 10 at the last upgrade, 8 hours max;
	-- a tuning guess). Paid on the next join for the minutes away, banked.
	drones = { perMinute = { [5] = 2, [6] = 10 }, capHours = 8 },

	-- Training room: a dummy that soaks every hit and shows damage per second over the last 10 s
	dummy = { window = 10, hp = 1e9, radius = 3 },
	bossSim = { hp = 60000, time = 60, slamEvery = 6, slamRadius = 14 }, -- a 60 s DPS check with telegraphs

	-- Trophy wall: earned once per account, picked to show (3 slots, 12 at level 4)
	trophies = {
		{ id = "firstBoss", name = "First World Boss" },
		{ id = "bossMvp", name = "Boss MVP" },
		{ id = "act1", name = "Act 1 Finale" },
		{ id = "allQuests", name = "Every Side Quest" },
		{ id = "level20", name = "Level 20" },
		{ id = "level40", name = "Level 40" },
		{ id = "legacy1", name = "Hall of Legends" },
		{ id = "fame5", name = "Fame Rank 5" },
		{ id = "fame10", name = "Fame Rank 10" },
		{ id = "rescues100", name = "100 Rescues" },
		{ id = "contracts50", name = "50 Contracts" },
		{ id = "repMax", name = "Reputation Rank 5" },
		{ id = "pvp10", name = "10 PvP Wins" },
		{ id = "styles50", name = "50 Styles" },
		{ id = "mentorPride", name = "Mentor's Pride" }, -- H6: a mentor's quest line done
	},

	-- WP9 (gap G5, spec H5): the WANTED poster of your current nemesis and a head trophy per nemesis rank you
	-- have beaten, on the east wall between the pilasters at z 24 and 48, by the Trophy Wall (Shared.
	-- WantedRules). The same spot in the Safehouse and the Foundry: below the Foundry's light band (y 15) and
	-- above the floor props (3 studs tall, 6 studs out). `wall` is the wall's face (cell offsets) and the way
	-- it faces into the room; the poster and the heads' row are measured along it from the viewer's left to
	-- right (u), up from the floor (y) and out from the face (d). PLACEHOLDER ART: parts and a Kit-style
	-- SurfaceGui until the HQ art pass.
	wanted = {
		wall = { x = 59, z = 36, nx = -1, nz = 0 },
		poster = { u = 0, y = 6.3, w = 7, h = 8, board = 0.4 }, -- board: the wooden backing's margin
		pixels = 50, -- the poster's SurfaceGui pixels per stud (7 x 8 studs = 350 x 400)
		heads = { y = 12.6, step = 3.8, mount = { 3, 2.6 }, plate = { 3.4, 0.7 } },
		prompt = { object = "Wanted Poster", action = "Read" },
	},

	-- WP12 (gap G15, spec Update 2): visit a friend's HQ on the same server (Shared.VisitRules, VisitService).
	-- VISIT on the SQUAD panel asks the owner; their card says ACCEPT or NO for askLife seconds. A yes puts the
	-- visitor in a read-only copy of the owner's HQ built from their save (the rooms, trophy wall, statues,
	-- props, dressing, the WANTED poster and heads, as the owner sees them), in a visit pocket of its own: no
	-- teleport, same server. Visitors only look (and LEAVE back to where they were): no stations, no changes,
	-- no loot, no boss sim. The owner sees visitors in SQUAD and can KICK them. Mutes, blocks and reports stop
	-- asks. Fixed text only.
	visit = {
		-- one pocket per host on the HQ cells' grid (x0, z0, gap, perRow as Hq.cell) but 700 studs higher, so a
		-- copy never meets a real cell (y 4,500), a mission pocket (y 3,000) or the city; count covers a full
		-- server of hosts
		pocket = { x0 = 9000, z0 = 9000, y = 5200, gap = 260, perRow = 25, count = 60 },
		max = 4, -- visitors in one HQ at once (a squad's size)
		askLife = 30, -- seconds a visit card waits for an answer
		again = 60, -- after a NO, the same visitor waits this long before asking that owner again
		kicked = 300, -- after a KICK, this long
		logEvery = 60, -- hq_visit analytics: at most one a minute per visitor
		-- the lines (%s: the other player's hero name or display name)
		text = {
			asked = "%s wants to visit your HQ",
			sent = "Visit request sent to %s",
			declined = "%s can't have visitors right now",
			arrived = "%s is visiting your HQ",
			left = "%s left your HQ",
			welcome = "Visiting %s's HQ. Look around, LEAVE takes you back",
			kicked = "Your visit to %s's HQ is over",
			hostLeft = "%s left the server. Back you go",
			station = "Owner only",
			leave = "LEAVE HQ",
			visit = "VISIT",
			heading = "VISITING YOUR HQ",
			visitingRow = "Visiting %s's HQ",
			hint = "Friends can ask to visit your HQ with VISIT. You see who is in, and KICK shows them out.",
			card = "ACCEPT",
			no = "NO",
			titleSub = "%s's HQ",
		},
		reasons = {
			self = "That's your own HQ!",
			visiting = "Leave this HQ first",
			busy = "Finish what you are doing first",
			new = "They don't have an HQ yet",
			muted = "Unmute or unblock them first",
			pending = "Request already sent",
			asking = "You already asked someone. Wait for their answer",
			wait = "Give them a moment before asking again",
			full = "Their HQ is full (4 visitors)",
			theirBusy = "They have another request open",
			expired = "That request ran out",
			gone = "They left the server",
		},
	},

	-- City reputation ranks unlock HQ props (profile.props bits; CafeSign = 1 is a side quest reward)
	cityProps = {
		{ rank = 1, prop = 2, name = "Potted Fern" },
		{ rank = 2, prop = 3, name = "City Map Table" },
		{ rank = 3, prop = 4, name = "Thank-You Board" },
		{ rank = 4, prop = 5, name = "Rescue Bell" },
		{ rank = 5, prop = 6, name = "Key to the City" },
	},
	props = {
		[1] = "Cafe Sign",
		[2] = "Potted Fern",
		[3] = "City Map Table",
		[4] = "Thank-You Board",
		[5] = "Rescue Bell",
		[6] = "Key to the City",
		[7] = "Comic Rack", -- H7: the ComicCovers collection
		[8] = "Toy Shelf", -- H7: the LostToys collection
		[9] = "Ship's Bell", -- H7: the ShipBells collection
		[10] = "Relic Case", -- H7: the DeepRelics collection
		[11] = "Pigeon Coop", -- H7: the RoofPigeons collection
		[12] = "Star Lamp", -- H7: the Star Charms collection (id CometShards)
		[13] = "Parts Rack", -- H7: the RobotParts collection
		[14] = "Boss Plate Wall", -- H7: the BossPlates collection
		[15] = "Core Case", -- H7: the NemesisCores collection
		[16] = "Ribbon Board", -- H7: the ContestRibbons collection
		[17] = "Keepsake Box", -- H7: the MentorKeepsakes collection
		[18] = "Crest Banner", -- H7: the Task Force Crests collection (id TaskForcePatches)
		[19] = "Season One Poster", -- H8: Hero Pass season 1 (free track)
		[20] = "Golden Ticket Booth", -- H8: Hero Pass season 1 (paid track)
		[21] = "Spotlight Rig", -- H8
		[22] = "Season One Statue", -- H8
	},

	-- Legacy rebirth (spec: at the level cap, 50 since 2026-11-17, retire to the Hall of Legends: a statue;
	-- the slot restarts at level 1 and keeps every unlock and reputation; +10% Renown and a plate frame per
	-- rank, up to 5)
	legacy = { maxRanks = 5, statues = 20 }, -- retiring opens at the level cap (Config.Stats.levelCap)
	classChange = true, -- respec and class change are free at HQ
}
