-- Cinema (nate's lore, build plan step 7: the cinematic layer; "bright world, serious story, anime fights").
-- Pure data; Shared.CinemaPlan and Shared.NewsPlan hold the rules, the client plays them.
-- * scenes: every cutscene the player plays (camera shots, letterbox, subtitles through the guide line box).
--   `bit` is the scene's place in the save's seen set (profile.seen, ProfileSchema.SMALL_WORDS bits): a
--   scene may be skipped once that bit is set. Bits 0 to 15 are the named scenes; missions use
--   missionBits (base + (mission - 1) * perMission + (stage - 1)). Never reuse or move a bit.
--   `beat`: a prologue camera beat (OpeningPlan.CUT; its length is Config.Story.opening.beats). `client`: the
--   device starts it (it then sends SceneSeen). Scenes run 5 to 20 s (`length`); the Ceremony beat keeps
--   nate's 30 s (4 shots of 4.5 to 9 s) and says so with `long`.
-- * safe: a device-started scene only plays when no fight would leave the hero defenceless.
-- * camera: the dynamic camera in fights (Settings "Camera motion": Full, Reduced halves, Off removes).
-- * finisher: slow-mo finishers on bosses and elites (Comic: impact word + hit stop; Anime: freeze frame +
--   speed lines), the finisher's own and a shorter one for players nearby. The server is never slowed.
-- * nameCard: a world boss's (or a fake's battle form's) 3 s name card for players who arrive at the fight.
--   The world bosses' titles are nate's lore (2026-11-17, build plan step 8); the battle form's is a
--   PLACEHOLDER until its own pass. A world boss's BREAKING flash names it with its title too (NewsPlan).
-- * news: in-city news broadcasts (big screens, the HUD's corner TV, BREAKING NEWS and the ticker). Fixed
--   templates only; a hero's name comes from the safe name system (CreatorRules.heroName ids), never text.
-- * comic: comic-panel flashback pages (PLACEHOLDER ART: panels drawn from frames until the art pass).
return {
	length = { min = 5, max = 20 }, -- seconds a scene may run
	skipDelay = 0.8, -- the SKIP button shows this long after a seen scene starts (no accidental taps)
	letterbox = { size = 0.1, tween = 0.35 }, -- bar height (share of the screen) and slide time

	scenes = {
		ceremony = { bit = 0, beat = "ceremony", long = true }, -- nate's prologue beat: 4 shots
		scan = { bit = 1, beat = "scan" },
		rescue = { bit = 2, beat = "rescue" },
		title = { bit = 3, beat = "title" },
		-- the Dev panel's sample in-engine scene: a slow orbit round the hero, a push up and a look out at
		-- the city, with two of Patch's lines (any safe moment)
		cityWatch = {
			bit = 4,
			client = true,
			seconds = 12,
			shots = {
				{ kind = "orbit", t0 = 0, t1 = 5, radius = 18, height = 6, yaw0 = 0.2, yaw1 = 1.6, lift = 3 },
				{
					kind = "dolly",
					t0 = 5,
					t1 = 9,
					from = { 0, 8, 22 },
					to = { 0, 40, 40 },
					at = { 0, 3, 0 },
					at2 = { 0, 20, -60 },
				},
				{ kind = "cut", t0 = 9, t1 = 12, from = { -30, 60, 30 }, at = { 60, 50, -160 } },
			},
			lines = {
				{
					at = 0.4,
					who = "patch",
					text = "Big city, bright lights. And every screen is watching you.",
				},
				{ at = 6.2, who = "patch", text = "Somewhere up there, Crane is smiling for the cameras." },
			},
		},
		-- the comic-panel flashback sample (Dev panel only): "The old heroes' last stand"
		lastStand = { bit = 5, client = true, seconds = 16, comic = "lastStand" },
		-- The Hero Academy (side quest chain, lore step 11): the gates on step 1, Wren's story as a comic page
		-- on step 5, and the bell before Headmaster Halo's finale
		academyGates = {
			bit = 6,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "orbit",
					t0 = 0,
					t1 = 4,
					radius = 20,
					height = 5,
					yaw0 = -0.4,
					yaw1 = 0.8,
					lift = 2,
				},
				{
					kind = "dolly",
					t0 = 4,
					t1 = 10,
					from = { 0, 6, 26 },
					to = { 0, 30, 44 },
					at = { 0, 4, 0 },
					at2 = { 0, 40, -40 },
				},
			},
			lines = {
				{
					at = 0.4,
					who = "halo",
					text = "Welcome to Halo Academy, where every Spark shines! Enrol today!",
				},
				{
					at = 5,
					who = "Gus",
					text = "Same speech every morning. Then the honours class goes downstairs.",
				},
			},
		},
		wrenStory = { bit = 7, client = true, seconds = 14, comic = "wrenStory" },
		haloBell = {
			bit = 8,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 14, 4, 14 }, at = { 0, 5, 0 } },
				{ kind = "orbit", t0 = 3, t1 = 8, radius = 16, height = 4, yaw0 = 0.6, yaw1 = 2.2, lift = 4 },
			},
			lines = {
				{
					at = 0.3,
					who = "halo",
					text = "Ding-dong! That's the bell, children. Time for your final exam!",
				},
				{
					at = 4,
					who = "patch",
					text = "That's Halo himself. Every screen is on him. Make it count!",
				},
			},
		},
		-- The Gala Heist (side quest chain 2, lore step 11): the gala's red carpet on step 1, the bank alarm in
		-- Uptown on step 6, and the curtain call before Redline and Madame Masque-a-rade's finale
		galaNight = {
			bit = 9,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 4, 30 },
					to = { 0, 8, 12 },
					at = { 0, 6, 0 },
					at2 = { 0, 10, -20 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 22,
					height = 8,
					yaw0 = 0.3,
					yaw1 = 1.4,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "masque",
					text = "Bonsoir, Brightharbor! Such lovely jewels. Such lovely, unguarded jewels.",
				},
				{
					at = 5.5,
					who = "Benny",
					text = "Masks at the gala, racers on the roofs. Something's going down tonight.",
				},
			},
		},
		bankJob = {
			bit = 10,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 16, 5, 16 }, at = { 0, 6, 0 } },
				{
					kind = "dolly",
					t0 = 3,
					t1 = 8,
					from = { 0, 8, 24 },
					to = { 0, 40, 40 },
					at = { 0, 6, 0 },
					at2 = { 0, 60, -30 },
				},
			},
			lines = {
				{
					at = 0.3,
					who = "redline",
					text = "Engines are warm, Madame. Roof to roof, all the way to the meet.",
				},
				{
					at = 4,
					who = "patch",
					text = "Alarms all over Uptown! The crew's inside the bank!",
				},
			},
		},
		curtainCall = {
			bit = 11,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -14, 4, 14 }, at = { 0, 5, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 18,
					height = 5,
					yaw0 = -0.6,
					yaw1 = 1.0,
					lift = 4,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "redline",
					text = "You followed us all the way here? Fine. Last lap. Winner takes all.",
				},
				{
					at = 4,
					who = "masque",
					text = "And for the grand finale, darlings: me!",
				},
			},
		},
		-- Wind-Up Lane (the Suburbs' side quest chain, lore step 11): the Lane outside Tick-Tock Toys on step 1,
		-- Toby's story as a comic page on step 5, and the Toymaker winding his giant before the finale. Bits 13
		-- to 15 (the top of the named range, clear of the Downtown chains')
		tickTockLane = {
			bit = 13,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { -30, 24, 40 },
					to = { 10, 10, 24 },
					at = { 0, 4, 0 },
					at2 = { 0, 3, 0 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 18,
					height = 4,
					yaw0 = 0.3,
					yaw1 = 1.4,
					lift = 2,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "toymaker",
					text = "Tick-Tock Toys! Toys that play all by themselves! Don't cry, little ones. Not yet.",
				},
				{
					at = 5.5,
					who = "Scoops",
					text = "That's the Toymaker. Sweet old man. Real sweet. Too sweet.",
				},
			},
		},
		tobyStory = { bit = 14, client = true, seconds = 14, comic = "tobyStory" },
		windupGiant = {
			bit = 15,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -16, 3, 16 }, at = { 0, 9, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = -0.4,
					yaw1 = 1.2,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "toymaker",
					text = "Behold my masterpiece! Wound up by hand, by me. Who needs a crying child?",
				},
				{
					at = 4,
					who = "patch",
					text = "That's a giant toy soldier. Of course it is. Knock it over!",
				},
			},
		},
	},
	missionBits = { base = 16, perMission = 8, missions = 13 }, -- bits 16 to 119

	safe = {
		quietSeconds = 6, -- no hit taken for this long
		enemyRange = 90, -- no robot drawn this close
		waitSeconds = 30, -- a scene that cannot play yet waits this long for a quiet moment, then drops
	},

	camera = {
		options = { "Full", "Reduced", "Off" }, -- Settings "Camera motion" (choice index 0, 1, 2)
		scale = { 1, 0.5, 0 }, -- by option: Reduced halves, Off removes
		lean = { max = 0.06, rise = 9, fall = 4 }, -- radians of roll into a dash; blend in and out per second
		push = { heavy = 0.05, finisher = 0.1, time = 0.28 }, -- FOV narrowed by this share (a gentle push in)
		orbit = { super = 0.32, time = 0.9 }, -- radians a super swings the camera round the hero
	},

	finisher = {
		near = 120, -- studs: players this close see the shorter version
		gap = 1.5, -- seconds between finishers on one screen
		killer = { slow = 0.25, seconds = 0.9 }, -- the finisher's own: time scale and how long it holds
		nearby = { slow = 0.5, seconds = 0.45 },
		comic = { hitStop = 0.14, wordSeconds = 1.1 },
		anime = { freeze = 0.2, lines = 24, lineSeconds = 0.75 },
		-- the impact words (original sound words, Comic style); picked by the event's seed
		words = { "KRA-KOOM!", "FINISHED!", "SHATTER!", "KA-BLAM!", "DOWN YOU GO!", "LIGHTS OUT!" },
		phaseWords = { "BREAK!", "CRACK!", "WHAM!" }, -- a phase's end (not the last blow)
	},

	nameCard = {
		seconds = 3,
		reach = 150, -- studs past the arena's edge that count as arriving at the fight
		check = 0.5, -- seconds between checks
		-- names come from Config.Boss; the world bosses' titles are nate's lore (build plan step 8), the card reads
		-- e.g. RUSTJAW PRIME / THE JUNKYARD TITAN; the battle form's title is a PLACEHOLDER until its own pass
		titles = {
			RustjawPrime = "THE JUNKYARD TITAN",
			LumenMaw = "THE LIGHT EATER",
			LeviathanEngine = "THE DEEP MACHINE",
			NullWarFrame = "THE SHIELD UNMASKED",
		},
		-- lore step 9: place and event cards in the same style (CinemaHud.card): the Crater the first time a
		-- session a hero walks in, and Your double on the copied hero's own device. { name, title, colour }
		places = {
			crater = { name = "THE CRATER", title = "WHERE THE OLD HEROES FELL", color = { 110, 200, 225 } },
		},
		events = {
			YourDouble = {
				name = "DOUBLE TROUBLE",
				title = "A FAKE WEARING YOUR FACE",
				color = { 235, 70, 70 },
			},
			-- lore step 12: the side-vs-side events' cards, for everyone as they start
			DataTruck = {
				name = "DATA TRUCK STANDOFF",
				title = "ESCORT IT OR CRACK IT",
				color = { 150, 110, 255 },
			},
			UptownVault = {
				name = "UPTOWN VAULT STANDOFF",
				title = "BLOCK THE RING OR CRACK THE VAULT",
				color = { 150, 110, 255 },
			},
			SparkShipment = {
				name = "SPARK CRYSTAL RAID",
				title = "SEIZE THE CRYSTALS OR SAVE THE CARGO",
				color = { 150, 110, 255 },
			},
		},
	},

	news = {
		feed = 8, -- facts kept for the ticker
		repeatGap = 90, -- the same kind for the same hero is news once in this many seconds
		breaking = 12, -- seconds a fresh flash stays on BREAKING NEWS
		reel = { crane = 9, ticker = 14 }, -- the screens' rotation: Crane's segment, then the ticker
		tickerSpeed = 0.06, -- share of the ticker's width a second
		streak = { gap = 300, at = { 3, 5, 10, 20 } }, -- incident clears in a row (each within gap seconds)
		channel = "BHN 24 / BRIGHTHARBOR NEWS",
		-- Crane on TV (fixed lines, his segment rotates through them)
		crane = {
			"Silas Crane: A registered hero is a safe hero. Register your powers today.",
			"Silas Crane: Crane Industries keeps Brightharbor bright. Every street, every night.",
			"Silas Crane: Rogue Sparks put your family at risk. Report them. We will do the rest.",
			"Silas Crane: The heroes on my stage are the best this city has. Trust them.",
		},
		-- the templates: %s is the hero name (CreatorRules.heroName) and %t the thing (a boss, a fake, a
		-- mission, a number); no other text ever goes in
		templates = {
			boss = "BREAKING: IT'S %t! HEROES AND VILLAINS ON THE WAY", -- %t: its name and title
			bossDown = "%s BRINGS DOWN %t",
			bossAway = "%t ESCAPES. CITY CLEANS UP",
			unmask = "%s CRACKS %t'S FACE. IT'S A ROBOT FAKE",
			streak = "%s CLEARS %t INCIDENTS IN A ROW",
			heist = "%s STOPS A ROBOT HEIST",
			heistVillain = "%s PULLS OFF A ROBOT HEIST",
			act1 = '%s FINISHES "%t"',
			double = "BREAKING: A FAKE OF %s IS LOOSE IN THE CITY", -- lore step 9: Your double starts
			doubleDown = "%s CRACKS THEIR OWN DOUBLE",
			-- lore step 12 (the city remembers): a hero reaching a high reputation rank (%t: the rank and its
			-- title), a side-vs-side event starting and its result (%t: the event's card name)
			repVigil = "THE CITY TRUSTS %s: VIGIL TRUST %t",
			repSyndicate = "THE CITY FEARS %s: SYNDICATE FEAR %t",
			sideStart = "BREAKING: VIGIL AND SYNDICATE CLASH IN THE %t",
			sideVigil = "%s AND THE VIGIL WIN THE %t",
			sideSyndicate = "%s AND THE SYNDICATE TAKE THE %t",
			sideDraw = "NO WINNER IN THE %t",
		},
		-- these also flash on every HUD (toast + corner TV)
		flash = { boss = true, unmask = true, double = true, sideStart = true },
		-- the corner TV: a flash plays this long; any other new fact shows on its ticker for `fact` s; with nothing
		-- new, Crane's segment airs every `craneEvery` s for `crane` s (never in the prologue, a mission or a scene)
		tv = { seconds = 7, fact = 5, crane = 8, craneEvery = 180, scroll = 10 },
		-- the big screens: where they hang (NewsPlan.screens picks the buildings from the world)
		screens = {
			downtown = 3, -- the Downtown towers nearest the plaza that get a screen
			minTop = 60, -- a screen building's roof is at least this high above the street
			size = { 36, 20 }, -- studs
			plaza = { size = { 28, 16 }, height = 22, back = 70 }, -- the plaza's own screen on its frame
			uptown = { size = { 70, 40 } }, -- the Crane billboard on Uptown's landmark
		},
	},

	comic = {
		pages = {
			-- "The old heroes' last stand" (the Crater lore: a Crane lab blew up in the battle where the old
			-- heroes fell). A neutral sample; Crane's own backstory pages wait for nate (Act 2).
			lastStand = {
				title = "THE OLD HEROES' LAST STAND",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 255, 196, 120 },
						ground = { 70, 60, 80 },
						scene = "city",
						caption = "Years ago, the Crater was a busy city block.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 120, 60, 70 },
						ground = { 40, 34, 50 },
						scene = "stand",
						caption = "The old heroes made their last stand there against the machines.",
						word = "KRAK!",
						at = 3,
					},
					{
						rect = { 0.03, 0.56, 0.3, 0.38 },
						sky = { 255, 240, 200 },
						ground = { 90, 80, 90 },
						scene = "blast",
						caption = "Mid-battle, a Crane Industries lab went up in a flash.",
						word = "BOOM!",
						at = 6.5,
					},
					{
						rect = { 0.36, 0.56, 0.61, 0.38 },
						sky = { 70, 80, 110 },
						ground = { 30, 30, 40 },
						scene = "crater",
						caption = "When the dust settled, the old heroes were gone. Only the Crater was left.",
						at = 10,
					},
				},
			},
			-- Wren's story (The Hero Academy, step 5): how the honours class works
			wrenStory = {
				title = "WREN'S FIRST WEEK AT HALO ACADEMY",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 150, 210, 255 },
						ground = { 90, 110, 80 },
						scene = "school",
						caption = "Halo Academy said I was special. Free lessons for kids with Sparks.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 255, 230, 160 },
						ground = { 70, 70, 90 },
						scene = "stand",
						caption = "Headmaster Halo picked me for the honours class. Everyone clapped.",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 40, 50, 70 },
						ground = { 30, 30, 40 },
						scene = "scan",
						caption = "Downstairs, a machine measured my Spark. A robot stood up... with MY powers.",
						word = "ZZZAP!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 140, 90 },
						ground = { 60, 50, 60 },
						scene = "city",
						caption = "So I ran. And I kept running until I found you.",
						at = 10.5,
					},
				},
			},
			-- Toby's story (Wind-Up Lane, step 5): how the Toymaker uses him
			tobyStory = {
				title = "TOBY AND THE WIND-UP BEAR",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 170, 220, 255 },
						ground = { 110, 170, 90 },
						scene = "toyshop",
						caption = "Tick-Tock Toys was my favourite shop. The Toymaker said I was special.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 255, 220, 170 },
						ground = { 110, 170, 90 },
						scene = "gnome",
						caption = "He gave me a wind-up bear. When I cried, every toy on the street woke up!",
						word = "TICK-TICK!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 90, 80, 120 },
						ground = { 70, 60, 70 },
						scene = "tantrum",
						caption = "Then he broke my toys on purpose. Every day. So I would keep crying.",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 40, 40, 60 },
						ground = { 30, 30, 40 },
						scene = "tap",
						caption = "His machine in the basement drinks it all up. He calls it the Tantrum Tap.",
						word = "GLUG!",
						at = 10.5,
					},
				},
			},
		},
		panelIn = 0.4, -- seconds a panel takes to slide in
		ink = { 20, 18, 26 }, -- the ink borders
		paper = { 250, 244, 228 },
	},
}
