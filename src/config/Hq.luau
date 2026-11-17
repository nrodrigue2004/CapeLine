-- Hq: the Hero HQ and the Hall of Legends (spec: Hero HQ (Beacon Tower or the Foundry); Legacy rebirth).
-- One HQ per side: the Vigil's Beacon Tower and the Dread Syndicate's Foundry, entered by their doors in the city. A visit is
-- solo (friend visits come in Update 2): each visitor gets their own sealed cell far above the map, the
-- server builds its floor and walls, and the device builds the rooms. PLACEHOLDER ART: greybox rooms.
return {
	names = { hero = "Beacon Tower", villain = "The Foundry" },
	-- the way in: the door at the foot of the Beacon Tower (Downtown) or the Foundry door (the Docks), your
	-- side's only; leaving puts you back outside it
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
	},

	-- Legacy rebirth (spec: at the level cap, 50 since 2026-11-17, retire to the Hall of Legends: a statue;
	-- the slot restarts at level 1 and keeps every unlock and reputation; +10% Renown and a plate frame per
	-- rank, up to 5)
	legacy = { maxRanks = 5, statues = 20 }, -- retiring opens at the level cap (Config.Stats.levelCap)
	classChange = true, -- respec and class change are free at HQ
}
