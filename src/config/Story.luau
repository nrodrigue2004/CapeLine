-- Story (spec: Opening, Act 1 story, quests; Act 1: Shardfall; Act 1 choices; Boss: Null War-Frame; Side
-- quests). Pure data: the Ceremony prologue's beats and lines, the 6 Act 1 missions (mission 1 is the
-- prologue itself), the 3 choices, the 7 mission pockets and the 8 side quest arcs. Both routes share the
-- pockets and enemies; only the text, the NPC lines and the banners change. Every number is a starting
-- value to tune. All names and characters are original.
return {
	-- The Ceremony prologue (nate's lore, build plan step 3; mission 1): about 4 minutes, right after the creator.
	-- Silas Crane hands out medals at Crane's Hero Hall in the Downtown plaza; his scanner finds the new hero's
	-- Spark; a run through the panic, a rooftop chase by Skylance, a subway full of falling tunnel, a fight that
	-- cracks the fake's face to metal, a swarm of Crane robots, and Lodestar's rescue. Then the billboard and the
	-- CAPELINE title card. Every line is fixed text here (nothing free-typed); a line with `hero` and `villain`
	-- texts reads by the side picked in the creator. OpeningPlan.STEPS is the beat order.
	opening = {
		clockTime = 14.5, -- a bright afternoon on the client while it runs (bright world, serious story)
		timeout = 330, -- a stuck prologue finishes itself (straight to the title and the rewards) after this
		reach = 14, -- studs from a target that count as there (missions use it too)
		-- timed beats (seconds); the skip button shows on them only on a replay or for a returning account
		beats = { ceremony = 30, scan = 8, suit = 3.5, rescue = 9, title = 10 },
		-- a beat the hero has not finished in this long moves on by itself (the hero is placed at the next one)
		stuck = {
			run = 45,
			spark = 12,
			leap = 45,
			chase = 60,
			descend = 50,
			tunnel = 75,
			fight = 100,
			swarm = 11,
		},
		-- the plaza: the stage in front of Crane's Hero Hall, the crowd on the street before it
		plaza = {
			stage = { gap = 4, depth = 14, width = 44, height = 4 }, -- from the Hall's face, studs
			crowd = { count = 30, low = 14, rows = 4, near = 8, far = 34 }, -- low: the phone preset's crowd
			start = 18, -- the hero stands this far from the stage, among the crowd
			kid = 4, -- the kid (Vigil) or the shover (Syndicate) stands this far from the spark point
		},
		run = { minD = 60, maxD = 110 }, -- the spark point: open ground this far from the start, away from the stage
		spark = { reach = 18, auto = 6, after = 3, blast = 70 }, -- fires on Basic (or by itself); the shove flies 70
		roofs = { count = 3, minH = 18, maxH = 200, near = { 20, 160 }, gap = { 30, 75 }, climb = 12 },
		chase = { fake = "Skylance", behind = 26, throwEvery = 3.2, warn = 0.7 }, -- harmless telegraphed spears
		suit = { pieceGap = 0.16 }, -- the suit snaps on piece by piece this fast
		entrance = { minD = 20, maxD = 80 }, -- the subway steps: open ground below the last roof
		-- the subway pocket: Config.Story.pockets index count + 1 (missions never take it), one lane per prologue
		subway = {
			lanes = 6,
			pitch = 64, -- lane centres this far apart
			width = 26,
			height = 24,
			length = 300, -- start to the fight chamber
			chamber = 56, -- the chamber at the end, square
			-- tunnel collapses: a slab falls across the lane `at` studs in, `t` seconds after the tunnel starts,
			-- with a warning ring `warn` seconds before; a hero under it is knocked back `push` studs (no damage)
			collapses = {
				{ at = 60, t = 4 },
				{ at = 120, t = 9 },
				{ at = 180, t = 14 },
				{ at = 240, t = 19 },
			},
			warn = 1.2,
			slab = 10, -- studs deep
			rubble = 4, -- the pile left behind is this tall (Leap over it)
			push = 22,
		},
		fight = { fake = "Skylance", hpMult = 0.55, dmg = 0.35, lowHealth = 0.3 }, -- ends at the face crack
		swarm = { kind = "SparkDrone", count = 7, ring = 22, dmg = 0.12, lowHealth = 0.35 }, -- the Crane Troopers
		reward = { level = 3, skillPoints = 1 }, -- level 3 and Flight, as the old opening paid
		next = 2, -- the hook: mission 2 (Safehouse, lore step 5) is what the Journal pins next
		-- the billboard for the last shot: a tall building's face toward the plaza
		billboard = { minH = 80, near = { 140, 380 }, size = { 70, 40 } },
		-- Lodestar (veteran Vigil hero; Patch calls him "Old Star"): a fixed look from earnable creator pieces
		lodestar = {
			name = "LODESTAR",
			title = "THE VIGIL",
			look = {
				gender = 1,
				build = 3,
				height = 5,
				skin = 4,
				hair = 19, -- silver
				colors = { 11, 19, 4 }, -- navy, silver, gold
				pieces = {
					suit = "Split Tone",
					back = "Classic Cape",
					hands = "Gloves",
					feet = "Tall Boots",
					emblem = "Star",
					hair = "Slicked Back",
					beard = "Full Beard",
					shoulders = "Mantle",
					belt = "Utility Belt",
					visage = "Scarred Face",
				},
				tints = { back = { 11, 4, 0 } },
				mats = {},
			},
		},
		-- the voices: Crane on the stage (and the plaza speakers), Patch on the radio (subtitles and a radio
		-- blip; no voice acting), Lodestar in person
		speakers = {
			crane = { name = "SILAS CRANE", color = { 255, 210, 60 } },
			patch = { name = "PATCH", color = { 120, 230, 255 }, radio = true },
			lodestar = { name = "LODESTAR", color = { 150, 190, 255 } },
		},
		-- subtitled lines by beat: `at` seconds into the beat
		lines = {
			ceremony = {
				{ at = 1, who = "crane", text = "Brightharbor! Thank you all for coming out today." },
				{ at = 6.5, who = "crane", text = "Ten years ago, the Spark nearly tore this city apart." },
				{ at = 12, who = "crane", text = "Today we honour the heroes who keep you safe. Radiant!" },
				{ at = 16, who = "crane", text = "Bulwark! And Skylance! Built strong by Crane Industries." },
				{
					at = 22,
					who = "crane",
					text = "And with our new scanners, no rogue Spark will hurt you again.",
				},
			},
			scan = {
				{ at = 0.5, who = "crane", text = "Scanners on, everyone. Big smiles!" },
				{ at = 4.5, who = "crane", text = "Well, well. It seems we have a guest. Officers?" },
			},
			run = {
				{
					at = 1,
					who = "crane",
					text = "Please remain calm! Crane Industries has this under control!",
				},
			},
			spark = {
				{
					at = 0.5,
					who = "crane",
					hero = "Officers! Get that rogue away from the child!",
					villain = "You see? A rogue Spark, attacking citizens! This is why we scan!",
				},
			},
			leap = {
				{
					at = 1,
					who = "patch",
					text = "Hey! You, the one glowing like a firework! Can you hear me?",
				},
				{ at = 5.5, who = "patch", text = "I'm Patch. I hacked your phone. Jump to that roof, now!" },
			},
			chase = {
				{
					at = 0.5,
					who = "patch",
					hero = "You shielded that kid. Cool. Now Skylance is on your tail!",
					villain = "You sent that guy flying. Noted. Now Skylance is on your tail!",
				},
				{ at = 7, who = "patch", text = "Keep jumping! His spears never miss twice!" },
			},
			suit = {
				{ at = 0.4, who = "patch", text = "Whoa. Is your Spark making you a suit? That is SO cool." },
			},
			descend = {
				{
					at = 0.5,
					who = "patch",
					text = "Subway steps, down below! His scanners can't see underground!",
				},
			},
			tunnel = {
				{ at = 0.5, who = "patch", text = "That's the old tunnel. It's not exactly stable. RUN!" },
			},
			fight = {
				{ at = 0.5, who = "patch", text = "He's blocking the way out. You'll have to fight him!" },
			},
			swarm = {
				{
					at = 0.3,
					who = "patch",
					text = "His face... it's METAL! Skylance is a robot? He's a FAKE!",
				},
				{
					at = 5,
					who = "patch",
					text = "Crane robots, a whole squad! Hang on, I'm calling Old Star!",
				},
			},
			rescue = {
				{
					at = 1.2,
					who = "lodestar",
					hero = "Easy, rookie. You fought like the Vigil. Let an old star take it from here.",
					villain = "Mean little Spark you've got. Crane wants it. Tonight, he doesn't get it.",
				},
				{ at = 5.5, who = "patch", text = "Old Star! I knew you'd come!" },
				{ at = 7, who = "lodestar", text = "Hold on tight. We're going underground." },
			},
			title = {
				{ at = 0.8, who = "crane", text = "Crane Industries. Your heroes. Our promise." },
			},
		},
		-- the scan's banner and the billboard (fixed text)
		detected = "SPARK DETECTED",
		slogan = "A SAFER CITY, ONE SPARK AT A TIME",
		brand = "CRANE INDUSTRIES",
		hall = "CRANE'S HERO HALL",
	},

	-- Mission pockets: sealed 400 x 400 areas at y = 3,000 (no PvP, no world schedulers)
	pockets = { count = 7, size = 400, y = 3000, z = 1900, firstX = -1800, gap = 600, wall = 60 },

	-- Act 1: Shardfall. minLevel and the order gate entry; first clears pay once.
	missions = {
		{
			num = 1,
			id = "Ceremony",
			name = "The Ceremony",
			minLevel = 1,
			opening = true, -- the prologue (lore step 3), in the city and the subway pocket, not the board
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
