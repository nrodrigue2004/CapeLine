-- Story (spec: Opening, Act 1 story, quests; Act 1: Shardfall; Act 1 choices; Boss: Null War-Frame; Side
-- quests). Pure data: the opening's beats and the playable disaster, the 6 Act 1 missions (mission 1 is the
-- disaster itself), the 3 choices, the 7 mission pockets and the 8 side quest arcs. Both routes share the
-- pockets and enemies; only the text, the NPC lines and the banners change. Every number is a starting
-- value to tune. All names and characters are original.
return {
	-- The cinematic over loading (Client): skippable after 2 s; 4 beats, 20 s
	cinematic = {
		skipAfter = 2,
		beats = {
			{ t = 0, len = 4, shot = "comet" }, -- night sky, the comet breaking, the title card
			{ t = 4, len = 5, shot = "rooftops" }, -- shards fall; two silhouettes watch from two rooftops
			{ t = 9, len = 5, shot = "shadow" }, -- the city flickers; a huge shadow crosses the moon
			{ t = 14, len = 6, shot = "street" }, -- down to the street; control is handed over
		},
	},

	-- The playable disaster (mission 1, Shardfall): only verb buttons carry words
	opening = {
		clockTime = 18.2, -- dusk on the client while it runs
		startRoof = { minH = 30, maxH = 90, near = 320 }, -- a roof near the plaza to start on
		leapRoof = { minGap = 30, maxGap = 75 }, -- the next roof, within one Leap
		reach = 14, -- studs from a target that count as there
		catchRange = 40, -- the Catch button works this close to the tram car
		catchRenown = 50,
		drones = { first = 2, second = 4 }, -- hits of the hero's basic attack each takes
		secondDamage = 0.35, -- the second drone hits this hard (x a normal Spark Drone)
		choice = { "Save Her", "Grab It" },
		rescueGap = { 120, 200 }, -- Save: carry her to a rooftop pad this far away
		escape = { 260, 340 }, -- Grab: reach the Docks marker this far away while drones chase
		escapeDrones = 3,
		reward = { level = 3, skillPoints = 1 }, -- level 3 and Flight; then the Suit Up screen
		guidedFlight = true, -- a marker leads the first flight to the nearest beacon
		timeout = 240, -- a stuck opening finishes itself after 4 minutes
	},

	-- Mission pockets: sealed 400 x 400 areas at y = 3,000 (no PvP, no world schedulers)
	pockets = { count = 7, size = 400, y = 3000, z = 1900, firstX = -1800, gap = 600, wall = 60 },

	-- Act 1: Shardfall. minLevel and the order gate entry; first clears pay once.
	missions = {
		{
			num = 1,
			id = "Shardfall",
			name = "Shardfall",
			minLevel = 1,
			opening = true, -- the playable disaster in the city, not a pocket
			skillPoints = 1,
		},
		{
			num = 2,
			id = "HoldTheLine",
			name = "Hold the Line",
			villainName = "Smash and Grab",
			minLevel = 3,
			layout = "station",
			minutes = 8,
			loot = "story",
			hero = {
				{ kind = "hold", points = 3, seconds = 10, radius = 12, text = "Defend the power stations" },
				{ kind = "choice", choice = 1, text = "The train or the thief?" },
				{ kind = "branch", choice = 1 }, -- option 1: stop the train; option 2: chase the thief
			},
			villain = {
				{
					kind = "break",
					points = 3,
					hits = 14,
					guards = { "Turret", 2 },
					text = "Steal the shard crates",
				},
				{ kind = "choice", choice = 1, text = "The train or the rival?" },
				{ kind = "branch", choice = 1 },
			},
			waves = { { "SparkDrone", 4 }, { "SparkDrone", 5 }, { "BurglarBot", 3 } },
			waveGap = 14,
			branches = {
				{ kind = "break", points = 1, hits = 30, train = true, text = "Stop the runaway train" },
				{ kind = "chase", enemy = "SneakBot", hops = 7, speed = 24, text = "Catch the thief" },
			},
		},
		{
			num = 3,
			id = "SignalTower",
			name = "Signal Tower",
			minLevel = 4,
			layout = "tower",
			minutes = 8,
			loot = "story",
			renown = 600,
			hero = {
				{ kind = "reach", at = "top", text = "Climb the tower" },
				{
					kind = "boss",
					enemy = "NullSentinel",
					hpMult = 8,
					adds = { "SparkDrone", 3 },
					text = "Beat the Null Sentinel",
				},
				{
					kind = "hold",
					points = 1,
					seconds = 6,
					radius = 10,
					at = "mast",
					text = "Restore the League signal",
				},
			},
			villain = {
				{ kind = "reach", at = "top", text = "Climb the tower" },
				{
					kind = "boss",
					enemy = "NullSentinel",
					hpMult = 8,
					adds = { "SparkDrone", 3 },
					text = "Beat the Null Sentinel",
				},
				{
					kind = "hold",
					points = 1,
					seconds = 6,
					radius = 10,
					at = "mast",
					text = "Cut the League signal",
				},
			},
		},
		{
			num = 4,
			id = "TheInformant",
			name = "The Informant",
			minLevel = 5,
			layout = "rooftops",
			minutes = 7,
			rep = 120, -- own-side reputation on the first clear
			hero = {
				{ kind = "reach", at = "contact", text = "Meet your contact" },
				{ kind = "choice", choice = 2, text = "Trust her?" },
				{ kind = "branch", choice = 2 },
				{ kind = "chase", enemy = "SneakBot", hops = 8, speed = 26, text = "Chase the Sneak Bot" },
			},
			villain = {
				{ kind = "reach", at = "contact", text = "Meet the fence" },
				{ kind = "choice", choice = 2, text = "Trust her?" },
				{ kind = "branch", choice = 2 },
				{ kind = "chase", enemy = "SneakBot", hops = 8, speed = 26, text = "Chase the Sneak Bot" },
			},
			branches = {
				{ kind = "none" }, -- trust: straight on
				{
					kind = "defeat",
					squads = { { "BurglarBot", 4 } },
					text = "It was a test: beat the ambush",
				},
			},
		},
		{
			num = 5,
			id = "UnderTheDocks",
			name = "Under the Docks",
			minLevel = 6,
			layout = "dungeon",
			minutes = 10,
			loot = "story",
			hero = {
				{
					kind = "defeat",
					squads = { { "BurglarBot", 4 }, { "SparkDrone", 2 } },
					room = 1,
					text = "Clear the first room",
				},
				{
					kind = "reach",
					at = "gauntletEnd",
					turrets = 4,
					trustTurrets = 2,
					room = 2,
					text = "Run the turret gauntlet",
				},
				{
					kind = "boss",
					enemy = "NullSentinel",
					hpMult = 6,
					adds = { "Turret", 2 },
					room = 3,
					text = "Beat the vault guard",
				},
				{ kind = "choice", choice = 3, text = "The Sentinel core" },
			},
			villain = {
				{
					kind = "defeat",
					squads = { { "BurglarBot", 4 }, { "SparkDrone", 2 } },
					room = 1,
					text = "Clear the first room",
				},
				{
					kind = "reach",
					at = "gauntletEnd",
					turrets = 4,
					trustTurrets = 2,
					room = 2,
					text = "Run the turret gauntlet",
				},
				{
					kind = "boss",
					enemy = "NullSentinel",
					hpMult = 6,
					adds = { "Turret", 2 },
					room = 3,
					text = "Beat the vault guard",
				},
				{ kind = "choice", choice = 3, text = "The Sentinel core" },
			},
		},
		{
			num = 6,
			id = "TheWarFrame",
			name = "The War-Frame",
			minLevel = 8,
			layout = "arena",
			minutes = 12,
			loot = "storyFinale",
			skillPoints = 1,
			finale = true,
			hero = { { kind = "warframe", text = "Bring down the War-Frame" } },
			villain = { { kind = "warframe", text = "Bring down the War-Frame" } },
		},
	},

	-- Choices: verb buttons, each grants 2 Skill Points (spec: Act 1 choices)
	choices = {
		{
			num = 1,
			mission = 2,
			skillPoints = 2,
			options = {
				{
					label = "Save the Train",
					villainLabel = "Stop the Train",
					rep = { "city", 100 },
					gadget = "Decoy",
				},
				{
					label = "Chase the Thief",
					villainLabel = "Chase the Rival",
					rep = { "side", 100 },
					credits = 600,
				},
			},
		},
		{
			num = 2,
			mission = 4,
			skillPoints = 2,
			options = {
				{ label = "Trust Her", shortcut = true }, -- mission 5: 2 turrets in the gauntlet, not 4
				{ label = "Test Her", epicChance = 0.1 }, -- an ambush now; a 10% Epic crate at the end
			},
		},
		{
			num = 3,
			mission = 5,
			skillPoints = 2,
			options = {
				{ label = "Spare the Core", perk = "NullEcho" }, -- a small drone buddy (cosmetic)
				{ label = "Overload It", credits = 800, renown = 600, arena = true }, -- mission 6: the arena's
				-- pillars crackle (a cosmetic arena effect)
			},
		},
	},
	perks = { NullEcho = { bit = 1, name = "Echo Drone", text = "A little drone buddy follows you" } },

	-- Reputation tracks (spec: Faction reputation): ranks at 100, 300, 600, 1,000 and 1,500. The save keeps
	-- the points as a list in this order (vigil was "league" before nate's lore, 2026-11-17: same slot).
	-- labels: what players read (Vigil rep is Trust, Syndicate rep is Fear); word: the short form.
	rep = {
		order = { "vigil", "syndicate", "city" },
		labels = { vigil = "Vigil Trust", syndicate = "Syndicate Fear", city = "City Reputation" },
		words = { vigil = "Trust", syndicate = "Fear", city = "Reputation" },
		ranks = { 100, 300, 600, 1000, 1500 },
		rescue = 5,
		mission = 50,
	},

	-- The War-Frame (mission 6): 36,000 HP at level 20, scaled by the party's median level. A BossSim
	-- boss with a back shield in phase 2 and pillars that block its laser in phase 3.
	warframe = {
		hp = 36000,
		atLevel = 20,
		summon = { "SparkDrone", 6 }, -- when phase 2 starts
		shieldHits = 3, -- hits on the back weak point that break the phase 2 shield
		pillars = { { -70, -40 }, { 70, -40 }, { -70, 50 }, { 70, 50 }, { 0, -100 }, { 0, 110 } }, -- x, z from the centre
		pillarRadius = 7,
	},

	-- Side quests: 8 arcs of 3 steps. NPCs stand in the hub; each step builds its own little site.
	-- at: where the NPC stands (an anchor and an offset); steps: kind and numbers; reward: what it gives.
	quests = {
		{
			num = 1,
			id = "Mayor",
			npc = "Mayor Bellweather",
			at = { anchor = "plaza", dx = 40, dz = 70 },
			color = { 90, 70, 160 },
			lines = {
				"My city records were stolen!",
				"Now, the speech. Stand with me.",
				"One last thing: the motorcade.",
			},
			steps = {
				{
					kind = "fetch",
					guards = { "BurglarBot", 3 },
					range = { 200, 400 },
					text = "Recover the city records",
				},
				{
					kind = "hold",
					seconds = 10,
					radius = 10,
					home = true,
					text = "Stand by the Mayor's speech",
				},
				{ kind = "escort", goal = 300, speed = 9, near = 40, text = "Escort the motorcade" },
			},
			reward = { style = "MayorsSash", credits = 500 },
		},
		{
			num = 2,
			id = "Pip",
			npc = "Pip",
			at = { anchor = "plaza", dx = -70, dz = 40 },
			color = { 255, 180, 60 },
			kid = true,
			lines = {
				"I need a helmet to be a hero!",
				"Show me 3 real incidents!",
				"Can you carry me over the gap?",
			},
			steps = {
				{ kind = "fetch", range = { 120, 250 }, text = "Find Pip a helmet" },
				{ kind = "spot", count = 3, range = 80, text = "Show Pip 3 incidents" },
				{ kind = "carry", range = { 120, 180 }, text = "Carry Pip over the gap" },
			},
			reward = { emote = "Salute", credits = 300 },
		},
		{
			num = 3,
			id = "Maribel",
			npc = "Maribel",
			at = { anchor = "OldTown", dx = 0, dz = 0 },
			color = { 230, 110, 90 },
			lines = {
				"My cafe got wrecked again.",
				"They are back! Keep them off!",
				"Help me pick a new menu?",
			},
			steps = {
				{ kind = "hold", seconds = 8, radius = 12, home = true, text = "Rebuild the cafe" },
				{
					kind = "defeat",
					squads = { { "BurglarBot", 3 }, { "SparkDrone", 3 } },
					home = true,
					text = "Defend the cafe",
				},
				{ kind = "choice", options = { "Soup", "Pie", "Noodles" }, text = "Pick a menu" },
			},
			reward = { credits = 1500, prop = "CafeSign" },
		},
		{
			num = 4,
			id = "OldBeacon",
			npc = "Old Beacon",
			villainNpc = "The Velvet Paw",
			at = { anchor = "hq", dx = 0, dz = 0 },
			color = { 70, 150, 255 },
			villainColor = { 160, 60, 140 },
			lines = {
				"Drill one: the rings. Go!",
				"Drill two: training drones.",
				"Drill three: get up high.",
			},
			steps = {
				{ kind = "race", checkpoints = 4, gap = 70, time = 45, text = "Fly the rings" },
				{
					kind = "defeat",
					squads = { { "SparkDrone", 5 } },
					home = true,
					text = "Beat the training drones",
				},
				{ kind = "reach", high = 60, range = { 80, 200 }, text = "Land on a high roof" },
			},
			reward = { skillPoints = 1 },
		},
		{
			num = 5,
			id = "Tamsin",
			npc = "Dock Boss Tamsin",
			at = { anchor = "Docks", dx = 0, dz = 0 },
			color = { 60, 140, 140 },
			lines = {
				"Run this crate across town. Quietly.",
				"One crate went missing. Find it.",
				"Someone is following us. Catch them.",
			},
			steps = {
				{ kind = "deliver", range = { 250, 400 }, text = "Run the smuggler crate" },
				{ kind = "find", range = { 150, 350 }, text = "Trace the missing crate" },
				{ kind = "chase", enemy = "SneakBot", hops = 6, speed = 24, text = "Catch the tail" },
			},
			reward = { style = "DockCoat", credits = 500 },
		},
		{
			num = 6,
			id = "Quill",
			npc = "Professor Quill",
			at = { anchor = "OldTown", dx = 80, dz = -60 },
			color = { 120, 200, 140 },
			lines = {
				"I need 3 shard readings.",
				"Now calibrate a beacon for me.",
				"A Sentinel took my sensor. Get it back!",
			},
			steps = {
				{ kind = "fetch", count = 3, range = { 150, 350 }, text = "Take 3 shard readings" },
				{ kind = "beacon", seconds = 5, text = "Calibrate a beacon" },
				{
					kind = "defeat",
					squads = { { "NullSentinel", 1 } },
					range = { 120, 250 },
					text = "Beat the Sentinel",
				},
			},
			reward = { loot = "story" },
		},
		{
			num = 7,
			id = "IronDee",
			npc = "Iron Dee",
			at = { anchor = "Docks", dx = 90, dz = 60 },
			color = { 200, 120, 40 },
			lines = {
				"Help me fix this hero car.",
				"Test my new gadget on some bots.",
				"Race my drone across the roofs!",
			},
			steps = {
				{ kind = "hold", seconds = 6, radius = 10, home = true, text = "Fix the hero car" },
				{
					kind = "defeat",
					squads = { { "BurglarBot", 3 } },
					range = { 60, 150 },
					text = "Test the gadget",
				},
				{ kind = "race", checkpoints = 5, gap = 90, time = 50, text = "Race the drone" },
			},
			reward = { gadget = "Decoy", credits = 300 },
		},
		{
			num = 8,
			id = "Skye",
			npc = "Skye",
			at = { anchor = "plaza", dx = 70, dz = -60 },
			color = { 240, 90, 160 },
			lines = {
				"I need 3 photos of Sneak Bots.",
				"Find my witness. Somewhere out there.",
				"Now get me on the air!",
			},
			steps = {
				{ kind = "photo", count = 3, range = { 120, 300 }, text = "Photograph 3 Sneak Bots" },
				{ kind = "find", range = { 200, 400 }, witness = true, text = "Find the witness" },
				{ kind = "hold", seconds = 8, radius = 10, high = true, text = "Broadcast from a roof" },
			},
			reward = { frame = "PhotoFrame", credits = 300 },
		},
	},
	-- Unlock bits for quest rewards that are not gear (profile.emotes, profile.frames, profile.props)
	-- Bit numbers for unlocks that rewards name (story here, Fame ranks in Config.Pvp). Titles and poses are
	-- M9's wheels; the bits are reserved now so saves never move.
	unlocks = {
		emotes = { Salute = 1, Bow = 2, SuperLanding = 20 }, -- landing poses share the emote bits from 20
		frames = { PhotoFrame = 1, FameFrame = 2 },
		props = { CafeSign = 1 },
		-- titles; plate trims share the title bits from 100
		titles = {
			Rookie = 1,
			["Local Name"] = 2,
			Headliner = 3,
			["Big Deal"] = 4,
			["Living Legend"] = 5,
			GoldTrim = 100,
		},
	},
	questRange = 12, -- talk range to an NPC (the Talk prompt)
	questGap = 3, -- seconds after a step before the next is built
}
