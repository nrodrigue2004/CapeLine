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
	scheduler = { every = { 240, 360 }, maxActive = 2, firstAfter = 90, pocketY = 2000 },
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
	events = {
		MeteorShower = {
			num = 1,
			name = "Meteor shower",
			goal = "shards",
			where = "hub",
			length = 90,
			text = "Shards are falling: first to each one gets a gear roll",
			shards = 6,
			spread = 500, -- across the hub
			grab = 10, -- touch range
			fallTime = 4, -- seconds a shard falls (a warning circle) before it can be grabbed
		},
		RobotRampage = {
			num = 2,
			name = "Robot rampage",
			villainName = "Robot rampage",
			goal = "robots",
			where = "anchor",
			length = 150,
			text = "A Brute Bot squad is running riot",
			waves = { { "BruteBot", 3 }, { "BurglarBot", 4 }, { "BruteBot", 3 }, { "SparkDrone", 4 } },
			waveGap = 25,
		},
		TidalSurge = {
			num = 3,
			name = "Tidal surge",
			villainName = "Tidal surge",
			goal = "rescue",
			where = { "Docks" },
			length = 120,
			text = "The sea is rising: carry 12 citizens to the rescue boats",
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
			villainText = "The city vault is open: crack it before the League",
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
			villainName = "Blackout",
			goal = "generators",
			where = { "OldTown" },
			length = 180,
			text = "A district went dark: restore 4 generators",
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
			villainText = "A League-hunting airship is dropping squads: bring it down",
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
			villainText = "Hold the Old Town bridge for the Syndicate",
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
			villainText = "Open the 3 arena gates before the League",
			generators = 3,
			hold = 6,
			radius = 12,
			model = "Gate",
			guards = { { "ShieldBearer", 1, "BruteBot" }, { "BurglarBot", 2 } },
		},
		PowerPlantOverload = {
			num = 10,
			name = "Power plant overload",
			villainName = "Power plant overload",
			goal = "objects",
			where = { "Docks" },
			length = 180,
			text = "The harbour power plant is overloading: break the 4 robot clamps",
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
	},
}
