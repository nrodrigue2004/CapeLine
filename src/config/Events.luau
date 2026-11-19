-- Random events (spec: Schedulers > Random events; Opening and story > Random events): one every 4 to 6
-- minutes, at most 2 at once, never the same type twice in a row, never inside a mission pocket. Every
-- hero who takes part gets the event's Credits and Renown and one gear roll from the "event" drop source;
-- villains play the same events under villainName. Zone level: the median level of the heroes in the
-- server, raised to the area floor. (tune)
-- Each event has a goal (what its counter counts; EventService builds it):
--   shards      pickups fall across the area; the first hero to each gets a gear roll
--   robots      beat every robot of its waves
--   rescue      carry `citizens` to `pads` rescue boats
--   hold        hold the ring for `hold` seconds (everyone's time adds up)
--   train       stop the hijacked train on a Downtown tram line before the end of the line
--   generators  at each of `generators` sites beat the guards, then hold its ring for `hold` s
--   object      break a big target (`hits` hits of Power at the zone level) `lift` studs up
--   objects     break `objects` targets spread `spread` studs about, each with its guards
--   float       stop a target rolling a street route (`legs` x `leg` studs at `speed`) before its end
-- waves: { kind, n, fallback } rows, one every waveGap s (or as soon as the last is beaten). guards: rows at
-- each site. A row's robot type that is switched off or not unlocked at the level uses its fallback.
-- where: "hub" (the plaza), "anchor" (near a random hero), "downtown" (any downtown district, so a second
-- one joins by name), or a list of district names (Config.City.districts) and landmark ids
-- (Config.World.landmarks); Shared.EventPlan.place resolves it, never fixed coordinates.
return {
	scheduler = {
		every = { 240, 360 },
		maxActive = 2,
		firstAfter = 90,
		pocketY = 2000,
		-- the rare tier (lore step 9): when a slot comes up, a rare event (Events.rare) takes it on a `chance` roll,
		-- never in the first `firstAfter` s of the server nor within `gap` s of the last rare one; it pays `pay`
		-- times an event's Credits and Renown. Rare events never join the normal mix (order).
		rare = { chance = 0.1, gap = 3600, firstAfter = 1200, pay = 3 },
		-- the side tier (lore step 12): side-vs-side events (Events.side) take a due slot on their own roll after
		-- the rare tier's, only with at least `minEach` heroes of each side in the server, never in the first
		-- `firstAfter` s nor within `gap` s of the last one. They never join the normal mix (order), so its odds
		-- and the rare tier's stay as they were.
		side = { chance = 0.2, gap = 2700, firstAfter = 600, minEach = 1 },
	},
	reward = { credits = { 60, 4 }, renown = { 80, 6 } }, -- per participant (M6, see Decisions)
	helpRadius = 150, -- heroes this close when it ends who took part count
	-- the districts "downtown" events may use (any listed name that exists in Config.City.districts, plus any
	-- district with "Downtown" in its name or downtown = true): Uptown is the second downtown (PLACEHOLDER NAME)
	downtowns = { "Downtown", "Uptown" },
	order = {
		"MeteorShower",
		"RobotRampage",
		"TidalSurge",
		"VaultBreach",
		"TrainHijack",
		"Blackout",
		"AirshipDrop",
		"BridgeSiege",
		"StadiumLockdown",
		"PowerPlantOverload",
		"ParadeGoneWrong",
		"HarbourFog",
	},
	-- the rare tier (scheduler.rare): picked only on its own roll, and only when someone may get it
	rare = { "YourDouble" },
	-- the side tier (scheduler.side): one side defends, the other steals (lore step 12)
	side = { "DataTruck", "UptownVault", "SparkShipment" },
	events = {
		MeteorShower = {
			num = 1,
			name = "Meteor shower",
			villainName = "Shard grab", -- side-content: the Syndicate\'s own goal (draft for nate)
			goal = "shards",
			where = "hub",
			length = 90,
			text = "Shards are falling: first to each one gets a gear roll",
			villainText = "Shards are falling: grab each one before the Vigil does",
			shards = 6,
			spread = 500, -- across the hub
			grab = 10, -- touch range
			fallTime = 4, -- seconds a shard falls (a warning circle) before it can be grabbed
		},
		RobotRampage = {
			num = 2,
			name = "Robot rampage",
			villainName = "Turf war", -- side-content: the Syndicate's own goal (draft for nate)
			goal = "robots",
			where = "anchor",
			length = 150,
			text = "A {BruteBot} squad is running riot",
			villainText = "A {BruteBot} squad is wrecking your turf: show it who runs the street",
			waves = { { "BruteBot", 3 }, { "BurglarBot", 4 }, { "BruteBot", 3 }, { "SparkDrone", 4 } },
			waveGap = 25,
		},
		TidalSurge = {
			num = 3,
			name = "Tidal surge",
			villainName = "Flooded hideouts", -- side-content: the Syndicate's own goal (draft for nate)
			goal = "rescue",
			where = { "Docks" },
			length = 120,
			text = "The sea is rising: carry 12 citizens to the rescue boats",
			villainText = "The sea is rising: get 12 of your crew to the boats",
			citizens = 12,
			rise = 6, -- studs the water climbs on the client
			pads = 2,
		},
		VaultBreach = {
			num = 4,
			name = "Vault breach",
			villainName = "Vault rush",
			goal = "hold",
			where = "anchor",
			length = 120,
			text = "The city vault is open: hold it against the robbers",
			villainText = "The city vault is open: crack it before the Vigil",
			hold = 30, -- seconds of holding (shared by everyone)
			ring = 14,
			prop = "Vault",
			waves = { { "BurglarBot", 4 }, { "SneakBot", 3 }, { "BurglarBot", 4 } },
			waveGap = 30,
		},
		TrainHijack = {
			num = 5,
			name = "Train hijack",
			villainName = "Train robbery",
			goal = "train",
			where = { "Downtown" }, -- the tram lines run through Downtown
			length = 150,
			text = "Stop the hijacked train",
			villainText = "Stop the train and rob it",
			hits = 60, -- engine HP in hits of Power at the zone level
			speed = 22,
			guards = { "SparkDrone", 4 },
		},
		Blackout = {
			num = 6,
			name = "Blackout",
			villainName = "Dark streets", -- side-content: the Syndicate's own goal (draft for nate)
			goal = "generators",
			where = { "OldTown" },
			length = 180,
			text = "A district went dark: restore 4 generators",
			villainText = "A district went dark: tap 4 generators for the Syndicate",
			generators = 4,
			hold = 5,
			radius = 12,
			guards = { "SparkDrone", 2 }, -- at each generator
		},
		-- 2026-11-17: more activities
		AirshipDrop = {
			num = 7,
			name = "Robot airship",
			villainName = "Robot airship",
			goal = "object",
			where = "downtown",
			length = 180,
			text = "A robot airship is dropping squads: bring it down",
			villainText = "A Vigil-hunting airship is dropping squads: bring it down",
			hits = 70,
			lift = 70, -- it hovers this high over the street
			model = "Airship",
			waves = {
				{ "SparkDrone", 4 },
				{ "BurglarBot", 4 },
				{ "Interceptor", 3, "SparkDrone" },
				{ "ShieldBearer", 2, "BruteBot" },
				{ "Swarmer", 1, "SneakBot" },
			},
			waveGap = 28,
		},
		BridgeSiege = {
			num = 8,
			name = "Bridge siege",
			villainName = "Bridge siege",
			goal = "hold",
			where = { "OldTown" },
			length = 160,
			text = "Robots are storming the Old Town bridge: hold it",
			villainText = "Hold the Old Town bridge for the Dread Syndicate",
			hold = 35,
			ring = 16,
			prop = "Barricade",
			waves = {
				{ "ShieldBearer", 2, "BruteBot" },
				{ "BurglarBot", 4 },
				{ "Grappler", 2, "BruteBot" },
				{ "Bomber", 1, "BruteBot" },
				{ "BurglarBot", 4 },
			},
			waveGap = 25,
		},
		StadiumLockdown = {
			num = 9,
			name = "Stadium lockdown",
			villainName = "Stadium lockdown",
			goal = "generators",
			where = "downtown",
			length = 180,
			text = "Robots locked the arena gates: open all 3",
			villainText = "Open the 3 arena gates before the Vigil",
			generators = 3,
			hold = 6,
			radius = 12,
			model = "Gate",
			guards = { { "ShieldBearer", 1, "BruteBot" }, { "BurglarBot", 2 } },
		},
		PowerPlantOverload = {
			num = 10,
			name = "Power plant overload",
			villainName = "Power grab", -- side-content: the Syndicate's own goal (draft for nate)
			goal = "objects",
			where = { "Docks" },
			length = 180,
			text = "The harbour power plant is overloading: break the 4 robot clamps",
			villainText = "Crane clamps choke the harbour plant: break all 4 and take the power",
			objects = 4,
			hits = 16, -- each clamp
			spread = 220,
			model = "Clamp",
			guards = { { "MedicUnit", 1, "SparkDrone" }, { "SparkDrone", 2 } },
		},
		ParadeGoneWrong = {
			num = 11,
			name = "Parade gone wrong",
			villainName = "Parade heist",
			goal = "float",
			where = "downtown",
			length = 160,
			text = "Robots hijacked the parade float: stop it before the crowd",
			villainText = "Stop the hijacked float and take its prize",
			hits = 50,
			speed = 6,
			legs = 8,
			leg = 45,
			model = "Float",
			waves = {
				{ "BurglarBot", 4 },
				{ "Mimic", 2, "SneakBot" },
				{ "BruteBot", 2 },
				{ "Captain", 1, "BruteBot" },
			},
			waveGap = 30,
		},
		HarbourFog = {
			num = 12,
			name = "Harbour fog ambush",
			villainName = "Harbour fog ambush",
			goal = "rescue",
			where = { "Docks" },
			length = 150,
			text = "Fog rolls in and robots ambush the quay: carry 8 citizens to the boats",
			villainText = "Fog rolls in: get 8 of your crew to the boats",
			citizens = 8,
			pads = 2,
			fog = true, -- WorldClient fogs the Docks for heroes inside them
			waves = {
				{ "SneakBot", 3 },
				{ "Mimic", 2, "SneakBot" },
				{ "Sniper", 1, "SparkDrone" },
				{ "SneakBot", 3 },
			},
			waveGap = 25,
		},
		-- Your double (nate's lore A2, build plan step 9): the evil twin from The Copy returns as a rare world event.
		-- It picks one hero who may get it (EventPlan.doubleOk: level, The Copy cleared, in the open city, not
		-- in the Crater, the prologue, a mission, a scene or a trip, not AFK, and `playerGap` s of play since their
		-- last one) and spawns that hero's twin (EnemyService.spawnTwin: their look, their power path) `spawnAt`
		-- studs from them with a news flash and a name card; heroes near enough help and share the pay. The twin
		-- slips away at `length` s. Pay: an event's at the rare tier's `pay` (x3), one gear roll.
		YourDouble = {
			num = 13,
			name = "Double Trouble", -- fixed for everyone (helpers too); the hero's own card says it wears their face
			goal = "twin",
			where = "target",
			length = 180,
			minLevel = 6, -- The Copy opens at 5
			mission = 4, -- The Copy: cleared first
			playerGap = 10800, -- seconds of play (profile.stats.playSeconds) between one hero's doubles
			afk = 120, -- no `afkMove`-stud move (or a Roblox Idled) for this long is AFK
			afkMove = 8,
			spawnAt = { 35, 60 },
			hpMult = 3, -- a fake of a whole hero: tough enough for a few helpers
			text = "A fake wearing your face is loose. Crack it before it slips away!",
			helpText = "A fake is copying a hero nearby. Help crack it!",
			notify = 300, -- heroes this close when it starts hear about it (everyone sees the news flash)
		},
		-- Side-vs-side events (nate's lore, build plan step 12): one side defends, the other steals, on an existing
		-- goal. `defend` is the defending side ("hero" = the Vigil, "villain" = the Dread Syndicate); the other side
		-- steals. PvP stays as ever: only flagged heroes fight each other; unflagged heroes fight the robots and the
		-- objective. Everyone who took part gets the event's pay and own-side reputation (Config.Remembers.earn),
		-- the winning side a little more; a news flash and a name card open it, the news names the winners.
		-- * float: the armoured truck rolls its route at full speed while a defender is within `escort` studs
		--   (else it crawls at `crawl`); only the stealing side's hits crack it (`hits`). It reaching the end is
		--   the defenders' win, cracked the stealers'; time up is a draw.
		-- * hold: the stealers crack the vault by standing in its ring, only while they outnumber the defenders in
		--   it (Shared.EventPlan.crackRate); cracked (`hold` s) is the stealers' win, time up the defenders'.
		-- * shards: every crystal counts for the side that grabs it; more when all are grabbed (or time is up)
		--   wins, level is a draw (an odd count, so all grabbed always has a winner).
		DataTruck = {
			num = 14,
			name = "Data truck standoff",
			villainName = "Data truck heist",
			goal = "float",
			where = { "Downtown" },
			side = true,
			defend = "hero",
			length = 180,
			text = "An armored Crane data truck is crossing Downtown: escort it to the press office",
			villainText = "An armored Crane data truck is crossing Downtown: crack it before it gets there",
			hits = 70,
			speed = 6,
			crawl = 0.3,
			escort = 60,
			legs = 8,
			leg = 45,
			model = "Truck",
			waves = {
				{ "Interceptor", 3, "SparkDrone" },
				{ "BurglarBot", 4 },
				{ "ShieldBearer", 2, "BruteBot" },
				{ "SparkDrone", 4 },
			},
			waveGap = 30,
		},
		UptownVault = {
			num = 15,
			name = "Uptown vault standoff",
			villainName = "Uptown vault job",
			goal = "hold",
			where = { "Uptown" },
			side = true,
			defend = "hero",
			length = 160,
			text = "The Syndicate wants the Uptown vault: stand in its ring to stop the crack",
			villainText = "The Uptown vault is ripe: outnumber the Vigil in its ring to crack it",
			hold = 40,
			ring = 16,
			prop = "Vault",
			waves = {
				{ "BurglarBot", 4 },
				{ "SneakBot", 3 },
				{ "Captain", 1, "BruteBot" },
				{ "BurglarBot", 4 },
			},
			waveGap = 30,
		},
		SparkShipment = {
			num = 16,
			name = "Spark crystal raid",
			villainName = "Spark crystal shipment",
			goal = "shards",
			where = { "Docks" },
			side = true,
			defend = "villain",
			length = 150,
			text = "A Syndicate Spark crystal shipment spilled on the quay: seize the crystals",
			villainText = "Your Spark crystal shipment spilled on the quay: save the cargo before the Vigil",
			shards = 9,
			spread = 260,
			grab = 10,
			fallTime = 3,
			waves = { { "SneakBot", 3 }, { "BruteBot", 3 }, { "Mimic", 2, "SneakBot" } },
			waveGap = 30,
		},
	},
}
