-- Random events (spec: Schedulers > Random events; Opening and story > Random events): one every 4 to 6
-- minutes, at most 2 at once, never the same type twice in a row, never inside a mission pocket. Every
-- hero who takes part gets the event's Credits and Renown and one gear roll from the "event" drop source;
-- villains play the same events under villainName. Zone level: the median level of the heroes in the
-- server, raised to the area floor. (tune)
return {
	scheduler = { every = { 240, 360 }, maxActive = 2, firstAfter = 90, pocketY = 2000 },
	reward = { credits = { 60, 4 }, renown = { 80, 6 } }, -- per participant (M6, see Decisions)
	helpRadius = 150, -- heroes this close when it ends who took part count
	order = { "MeteorShower", "RobotRampage", "TidalSurge", "VaultBreach", "TrainHijack", "Blackout" },
	events = {
		MeteorShower = {
			num = 1,
			name = "Meteor shower",
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
			length = 150,
			text = "A Brute Bot squad is running riot",
			waves = { { "BruteBot", 3 }, { "BurglarBot", 4 }, { "BruteBot", 3 }, { "SparkDrone", 4 } },
			waveGap = 25,
		},
		TidalSurge = {
			num = 3,
			name = "Tidal surge",
			villainName = "Tidal surge",
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
			length = 120,
			text = "The city vault is open: hold it against the robbers",
			villainText = "The city vault is open: crack it before the League",
			hold = 30, -- seconds of holding (shared by everyone)
			waves = { { "BurglarBot", 4 }, { "SneakBot", 3 }, { "BurglarBot", 4 } },
			waveGap = 30,
		},
		TrainHijack = {
			num = 5,
			name = "Train hijack",
			villainName = "Train robbery",
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
			length = 180,
			text = "A district went dark: restore 4 generators",
			generators = 4,
			hold = 5,
			radius = 12,
			guards = { "SparkDrone", 2 }, -- at each generator
		},
	},
}
