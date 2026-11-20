-- Cinema (nate's lore, build plan step 7: the cinematic layer; "bright world, serious story, anime fights").
-- Pure data; Shared.CinemaPlan and Shared.NewsPlan hold the rules, the client plays them.
-- * scenes: every cutscene the player plays (camera shots, letterbox, subtitles through the guide line box).
--   `bit` is the scene's place in the save's seen set (profile.seen, ProfileSchema.SEEN_WORDS words): a
--   scene may be skipped once that bit is set. Bits 0 to 15 are the named scenes (then extraBits, 120 to
--   127, once 0 to 15 were full, and wideBits, 128 to 255, since save v12); missions use
--   missionBits (base + (mission - 1) * perMission + (stage - 1)). Never reuse or move a bit.
--   `beat`: a prologue camera beat (OpeningPlan.CUT; its length is Config.Story.opening.beats). `client`: the
--   device starts it (it then sends SceneSeen). Scenes run 5 to 20 s (`length`); the Ceremony beat keeps
--   nate's 30 s (4 shots of 4.5 to 9 s) and says so with `long`.
-- * safe: a device-started scene only plays when no fight would leave the hero defenceless.
-- * camera: the dynamic camera in fights (Settings "Camera motion": Full, Reduced halves, Off removes).
-- * finisher: slow-mo finishers on bosses and elites (Comic: impact word + hit stop; Anime: freeze frame +
--   speed lines), the finisher's own and a shorter one for players nearby. The server is never slowed.
-- * nameCard: a world boss's (or a fake's battle form's) 3 s name card for players who arrive at the fight.
--   The world bosses' titles are nate's lore (2026-11-17, build plan step 8); the battle form's (THE IRON
--   OATH) is nate's pick of 2026-11-19. A world boss's BREAKING flash names it with its title too (NewsPlan).
-- * news: in-city news broadcasts (big screens, the HUD's corner TV, BREAKING NEWS and the ticker). Fixed
--   templates only; a hero's name comes from the safe name system (CreatorRules.heroName ids), never text.
-- * comic: comic-panel flashback pages (PLACEHOLDER ART: panels drawn from frames until the art pass).
return {
	length = { min = 5, max = 20 }, -- seconds a scene may run
	-- (first-30 polish 2026-11-20) the side HUD screens a letterboxed scene hides while its bars are up (each comes
	-- back as it was); never the subtitles (GuideHud, StoryHud), the prompts (Qte), the finisher or news screens
	hideScreens = {
		"Plates",
		"Toasts",
		"NemesisHud",
		"BadgeHud",
		"MentorHud",
		"TaskForceHud",
		"PvpHud",
		"Squad",
		"Daily",
		"DailyTracker",
		"BoardHud",
		"ContestHud",
		"HelpHud",
		"MoveTutor",
		"PassHud",
		"WeaponRack",
		"LoreCard",
	},
	skipDelay = 0.8, -- the SKIP button shows this long after a seen scene starts (no accidental taps)
	letterbox = { size = 0.1, tween = 0.35 }, -- bar height (share of the screen) and slide time

	scenes = {
		ceremony = { bit = 0, beat = "ceremony", long = true }, -- nate's prologue beat: 4 shots
		scan = { bit = 1, beat = "scan" },
		rescue = { bit = 2, beat = "rescue" },
		title = { bit = 3, beat = "title" },
		-- the exposition before the creator (fix-flow, 2026-11-19): played by the server's OpeningIntro, SKIP any time
		-- after Config.Story.opening.intro.skipAfter (bit 131: Cinema.wideBits)
		intro = { bit = 131, client = true, seconds = 18, comic = "intro" },
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
		-- The Harvest King (side quest chain 4, lore step 11, Farmland): dusk over Furrow Farm on step 1, the
		-- Harvest King's comic page on step 5, and the beast waking at the King's Acre before the finale. Bit 12
		-- (the last free named bit), then 120 and 121 (Cinema.extraBits: the named range was full)
		farmDusk = {
			bit = 12,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 6, 34 },
					to = { 0, 10, 16 },
					at = { 0, 6, 0 },
					at2 = { 0, 14, -40 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 24,
					height = 9,
					yaw0 = -0.4,
					yaw1 = 0.8,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "Dot",
					text = "Every night at dusk the ground shakes. Then the corn just... disappears.",
				},
				{
					at = 5.5,
					who = "harvest",
					text = "Eat up, my beauty. Every field from here to the sea is yours.",
				},
			},
		},
		kingStory = { bit = 120, client = true, seconds = 14, comic = "kingStory" },
		kingsHarvest = {
			bit = 121,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 16, 5, 16 }, at = { 0, 6, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 20,
					height = 6,
					yaw0 = 0.4,
					yaw1 = 1.8,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "harvest",
					text = "You hurt my crops, my bots, my fields. You will NOT hurt my creation!",
				},
				{
					at = 4,
					who = "patch",
					text = "The ground's moving! That's not a hill. That's the beast!",
				},
			},
		},
		-- The Salt Dogs (the Coast's side quest chain, lore step 11): fog over Gull Point Pier on step 1, the
		-- legend of Captain Brine as a comic page on step 5, and Brine riding the tide in before the finale.
		-- Bits 122 to 124 (Cinema.extraBits, after chain 4's)
		gullPoint = {
			bit = 122,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { -40, 22, 30 },
					to = { -6, 8, 18 },
					at = { 0, 4, 0 },
					at2 = { 0, 3, 0 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 20,
					height = 5,
					yaw0 = -0.5,
					yaw1 = 0.7,
					lift = 3,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "brine",
					text = "Yo ho! Mind the fog, little ferries. The ghost ship of Captain Brine sails tonight!",
				},
				{
					at = 5.5,
					who = "Nell",
					text = "Forty years on this pier, and I never believed in ghosts. Until the robots came with it.",
				},
			},
		},
		brineLegend = { bit = 123, client = true, seconds = 14, comic = "brineLegend" },
		brineRig = {
			bit = 124,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -18, 2, 18 }, at = { 0, 7, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 20,
					height = 5,
					yaw0 = 0.4,
					yaw1 = 1.8,
					lift = 5,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "brine",
					text = "The tide answers to Captain Brine! Batten down, barnacles, here comes the big wave!",
				},
				{
					at = 4,
					who = "patch",
					text = "A pirate in a powered diving suit, riding a wave. Sure. Why not. Sink him!",
				},
			},
		},
		-- The Pit (the Old Quarry's side quest chain 6, lore step 11): night over the quarry gate on step 1, the
		-- Pitboss's story as a comic page on step 5, and the Pitboss stepping up for the finale. Bits 125 to 127
		-- (Cinema.extraBits, after the Coast's)
		quarryNight = {
			bit = 125,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 40, -60 },
					to = { 0, 14, -16 },
					at = { 0, 6, 0 },
					at2 = { 0, 2, 60 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 22,
					height = 7,
					yaw0 = -0.6,
					yaw1 = 0.6,
					lift = 4,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "pitboss",
					text = "Welcome to the Pit, folks! Two Sparks go in, one walks out, and the house always wins!",
				},
				{
					at = 5.5,
					who = "Brick",
					text = "Hear that? It comes up through the quarry floor every night. I used to be the one in that ring.",
				},
			},
		},
		pitStory = { bit = 126, client = true, seconds = 14, comic = "pitStory" },
		fightNight = {
			bit = 127,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 14, 3, 18 }, at = { 0, 8, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.3,
					yaw1 = 1.7,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "pitboss",
					text = "You busted my Pit and robbed my house. Fine. Main event: you against the champ. That's ME.",
				},
				{
					at = 4,
					who = "patch",
					text = "His skin's solid stone and that rig punches like a truck. Hit the rig, not the rock!",
				},
			},
		},
		-- The Sunken City (the Underwater side quest chain, lore step 11): Velmara's lights waking under the reef
		-- on step 1, the Tidewright's tale as a comic page on step 5, and the Tidewright rising before the
		-- finale. Bits 128 to 130: the first of Cinema.wideBits (save v12's second half of the seen set)
		velmaraLights = {
			bit = 128,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 14, 40 },
					to = { 0, 4, 16 },
					at = { 0, -6, -30 },
					at2 = { 0, -10, -40 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 22,
					height = 4,
					yaw0 = -0.6,
					yaw1 = 0.6,
					lift = 2,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "Pearl",
					text = "There, under the reef. Lights that have been dark for a thousand years, all switching on.",
				},
				{
					at = 5.5,
					who = "tidewright",
					text = "Velmara wakes. Velmara remembers. Surface-dwellers, your time on the shore is over.",
				},
			},
		},
		tidewrightTale = { bit = 129, client = true, seconds = 14, comic = "tidewrightTale" },
		tidewrightRises = {
			bit = 130,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -16, -2, 20 }, at = { 0, 6, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 24,
					height = 3,
					yaw0 = 0.3,
					yaw1 = 1.9,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "tidewright",
					text = "I kept Velmara a thousand years. I will keep it from you. Let the tide rise!",
				},
				{
					at = 4,
					who = "patch",
					text = "That's not a robot someone built last week. That's the city's guardian. And it's HUGE.",
				},
			},
		},
		-- The character lines (lore step 11: one chain per character; Cinema.wideBits 160 to 171): an opening shot
		-- at the giver's site, the villain's story as a comic page, and the villain stepping up before the finale.
		-- The Last Partner (Lodestar's line): the Night Owl diner, Vesper's story, the two stars
		nightOwl = {
			bit = 160,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 30, 60 },
					to = { 0, 8, 18 },
					at = { 0, 4, 0 },
					at2 = { 0, 3, -20 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 22,
					height = 7,
					yaw0 = -0.6,
					yaw1 = 0.6,
					lift = 4,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "lodestar",
					text = "Same booth, every night after patrol. Two coffees. Hers has gone cold for a year now.",
				},
				{
					at = 5.5,
					who = "patch",
					text = "Old Star never talks about his partner. Like, ever. Whatever this is, it's big.",
				},
			},
		},
		vesperStory = { bit = 161, client = true, seconds = 14, comic = "vesperStory" },
		twoStars = {
			bit = 162,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 14, 3, 18 }, at = { 0, 8, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.3,
					yaw1 = 1.7,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "vesper",
					text = "Lodestar? You look old. I don't remember you. Should I? Smile for the cameras, darling.",
				},
				{
					at = 4,
					who = "lodestar",
					text = "That's her face and her voice, and none of her. Crack it. Show the city what's under it.",
				},
			},
		},
		-- Finding Lark (Patch's line): Lark's empty flat, her story, Catchpole's net gun
		larkFlat = {
			bit = 163,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 30, 60 },
					to = { 0, 8, 18 },
					at = { 0, 4, 0 },
					at2 = { 0, 3, -20 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 22,
					height = 7,
					yaw0 = -0.6,
					yaw1 = 0.6,
					lift = 4,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "patch",
					text = "This was our flat. Her jacket's still on the hook. She went out for milk a year ago.",
				},
				{
					at = 5.5,
					who = "patch",
					text = "Tonight her old radio came on. Just one word. Pound. I need your help. Please.",
				},
			},
		},
		larkStory = { bit = 164, client = true, seconds = 14, comic = "larkStory" },
		netGun = {
			bit = 165,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -14, 3, 18 }, at = { 0, 8, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.3,
					yaw1 = 1.7,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "catchpole",
					text = "You opened my pound? Every Spark in there was worth a bounty. You owe me a fortune.",
				},
				{
					at = 4,
					who = "lark",
					text = "Patch? Patch, is that you on the radio? I'm out! Now let's net the netter.",
				},
			},
		},
		-- Hostile Takeover (the Syndicate boss's line): the Opal Room, the Torch Crew's story, Sal Scorch's flames
		opalRoom = {
			bit = 166,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 30, 60 },
					to = { 0, 8, 18 },
					at = { 0, 4, 0 },
					at2 = { 0, 3, -20 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 22,
					height = 7,
					yaw0 = -0.6,
					yaw1 = 0.6,
					lift = 4,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "Vanta",
					text = "Twenty years I've run Old Town from this room, and nobody burned a single shop.",
				},
				{
					at = 5.5,
					who = "scorch",
					text = "Times change, Duchess. Old Town wants a new boss. Hot, bright and on fire. Me.",
				},
			},
		},
		scorchStory = { bit = 167, client = true, seconds = 14, comic = "scorchStory" },
		torchOut = {
			bit = 168,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 14, 3, -18 }, at = { 0, 8, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.3,
					yaw1 = 1.7,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "scorch",
					text = "My garages, my crew, my lieutenant? You're the Duchess's new help? Then you burn first!",
				},
				{
					at = 4,
					who = "Vanta",
					text = "His suit runs hot. Keep moving and let it cook him. Then tell him who sent you.",
				},
			},
		},
		-- The Scoop (the reporter's line): the BHN 24 news desk, the cut stories, the uplink on air
		newsDesk = {
			bit = 169,
			client = true,
			seconds = 10,
			shots = {
				{
					kind = "dolly",
					t0 = 0,
					t1 = 5,
					from = { 0, 40, 60 },
					to = { 0, 10, 18 },
					at = { 0, 6, 0 },
					at2 = { 0, 30, -20 },
				},
				{
					kind = "orbit",
					t0 = 5,
					t1 = 10,
					radius = 22,
					height = 7,
					yaw0 = -0.6,
					yaw1 = 0.6,
					lift = 4,
				},
			},
			lines = {
				{
					at = 0.4,
					who = "Nora",
					text = "Three of my stories cut mid-sentence this month. Somebody is choosing what this city sees.",
				},
				{
					at = 5.5,
					who = "censor",
					text = "Good evening, Brightharbor. Nothing happened today. Nothing ever happens. Sleep well.",
				},
			},
		},
		cutStory = { bit = 170, client = true, seconds = 14, comic = "cutStory" },
		onAir = {
			bit = 171,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -14, 3, -18 }, at = { 0, 8, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.3,
					yaw1 = 1.7,
					lift = 6,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "censor",
					text = "You put it ON AIR? The whole city is watching. Then they can watch you get cut.",
				},
				{
					at = 4,
					who = "Nora",
					text = "Keep fighting, the camera's rolling! That's the Censor, Brightharbor. Live!",
				},
			},
		},
		-- The origin lines (lore step 11): each line's story as a comic page on step 5 (the truth about your origin,
		-- ending on the same Spark panel in every line), and its villain stepping up for the finale. Bits 192 to
		-- 201 (Cinema.wideBits; 192 to 255 kept for the origin lines)
		kindlerTruth = { bit = 192, client = true, seconds = 14, comic = "kindlerTruth" },
		hollowayRig = {
			bit = 193,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 14, 3, 18 }, at = { 0, 7, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.3,
					yaw1 = 1.7,
					lift = 5,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "holloway",
					text = "Subject One. My Kindler woke you, so your Spark belongs to me. Step back into the light.",
				},
				{
					at = 4,
					who = "patch",
					text = "His rig runs on Kindling cells. Break that front shield, then hit him from the side!",
				},
			},
		},
		podMessage = { bit = 194, client = true, seconds = 14, comic = "podMessage" },
		voidhoundLands = {
			bit = 195,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -14, 4, 18 }, at = { 0, 7, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = -0.3,
					yaw1 = 1.3,
					lift = 5,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "voidhound",
					text = "STAR BLOOD CONFIRMED. ONE SPARK, UNCLAIMED. THE HUNT ENDS NOW.",
				},
				{
					at = 4,
					who = "Ruth",
					text = "It chased that ship across the stars for a thousand years. Send it home in pieces, kid!",
				},
			},
		},
		relicTruth = { bit = 196, client = true, seconds = 14, comic = "relicTruth" },
		morrowCurtain = {
			bit = 197,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 12, 3, 20 }, at = { 0, 7, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.4,
					yaw1 = 1.8,
					lift = 5,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "morrow",
					text = "Ladies and gentlemen, my greatest trick! The relic's new owner... disappears!",
				},
				{
					at = 4,
					who = "ambrose",
					text = "Mirrors and wires, old friend. Always mirrors and wires. Break his mirrors!",
				},
			},
		},
		coreTruth = { bit = 198, client = true, seconds = 14, comic = "coreTruth" },
		clawbackClaim = {
			bit = 199,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { -12, 3, 20 }, at = { 0, 7, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = -0.2,
					yaw1 = 1.4,
					lift = 5,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "clawback",
					text = "Final notice! Clawback Recovery takes back the suit, the core and YOU!",
				},
				{
					at = 4,
					who = "Tess",
					text = "That hook pulls you in. Keep moving, and hit him hard every time it misses!",
				},
			},
		},
		masterLesson = { bit = 200, client = true, seconds = 14, comic = "masterLesson" },
		galeChallenge = {
			bit = 201,
			client = true,
			seconds = 8,
			shots = {
				{ kind = "cut", t0 = 0, t1 = 3, from = { 14, 3, 16 }, at = { 0, 7, 0 } },
				{
					kind = "orbit",
					t0 = 3,
					t1 = 8,
					radius = 22,
					height = 6,
					yaw0 = 0.3,
					yaw1 = 1.7,
					lift = 5,
				},
			},
			lines = {
				{
					at = 0.3,
					who = "gale",
					text = "Hoshi's favourite. I trained harder than you ever did. My rig says I win.",
				},
				{
					at = 4,
					who = "hoshi",
					text = "Speed with no patience trips over itself. Let him rush past you, then strike.",
				},
			},
		},
	},
	missionBits = { base = 16, perMission = 8, missions = 13 }, -- bits 16 to 119
	-- More named scenes once bits 0 to 15 were full (lore step 11, chain 4): the seen set's last 8 bits,
	-- above the missions' (CinemaPlan.namedBit)
	extraBits = { from = 120, to = 127 },
	-- (2026-11-18) the seen set's second half once 0 to 127 were full: save v12 gives profile.seen its own 8
	-- words (ProfileSchema.SEEN_WORDS), so named scenes may use 128 to 255 too (the Underwater chain first,
	-- then the character and origin lines). CinemaPlan.namedBit accepts both ranges.
	wideBits = { from = 128, to = 255 },

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
		-- (first-30 polish 2026-11-20) a cutscene's field of view, held for the whole scene (the gameplay FOV's
		-- leap and boost widening no longer pumps the zoom mid-shot), and the seconds its end eases from the last
		-- shot to the follow camera instead of snapping behind the hero
		fov = 70,
		blendOut = 0.6,
		-- (round 2) every shot drifts a little: `push` of the way to its subject over the shot, a `sway` (studs)
		-- breathing at `rate` Hz; a jump cut (the next shot starting within `dist` studs and `angle` degrees of
		-- the last frame) eases across in `ease` s instead of cutting
		drift = { push = 0.05, sway = 0.08, rate = 0.22, jumpCut = { dist = 10, angle = 30, ease = 0.4 } },
		-- (round 2) a scene's shots get a soft depth of field: sharp within `radius` of the subject's distance, the
		-- far city blurred by `far`, eased over `ease` s; never on the low preset
		dof = { on = true, radius = 0.45, far = 0.35, ease = 0.4 },
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

	-- Impact frames (first-30, nate 2026-11-20: "Do we have hit stop/freeze frames/flash frames. Remember that the
	-- game being cinematic is also one of the most important things"): on the big blows the whole screen cuts
	-- for 2 to 4 frames to stark black and white with ink lines bursting from the hit (Shared.ImpactFrames,
	-- Fx.ImpactFrameFx). Comic: a blown-out white frame then an inked black one, thick tapered lines and the hit
	-- star; Anime: a negative-style black frame first, many thin speed lines. The game holds still under them
	-- (your own clip freezes). Reduce flashing: no frames, a gentle hit stop instead. Your own blows only, or a
	-- finisher near you (FinisherFx).
	impactFrames = {
		on = true,
		frame = 1 / 30, -- seconds a frame holds (two screen frames at 60 fps)
		frames = { crit = 2, super = 3, finisher = 4 }, -- how many frames each kind cuts to
		-- seconds since the last impact frames before this kind may cut again (a bigger kind never waits for a
		-- smaller one): a hail of crits cuts once, never strobes
		gap = { crit = 1.6, super = 0.5, finisher = 0 },
		order = { crit = 1, super = 2, finisher = 3 },
		-- the frames' looks by style, in order (each "white" or "black"), cycled when a kind has more frames
		looks = {
			Comic = { "white", "black", "white", "black" },
			Anime = { "black", "white", "black", "white" },
		},
		lines = { Comic = 16, Anime = 30 }, -- ink lines bursting from the hit's point on screen
		width = { Comic = { 6, 14 }, Anime = { 2, 5 } }, -- line thickness range (px)
		inner = 0.06, -- the lines start this share of the screen's height from the point (the hit shows)
		white = { saturation = -1, contrast = 1.6, brightness = 0.32 }, -- the white frame's ColorCorrection
		black = { saturation = -1, contrast = 2.2, brightness = -0.42, cover = 0.45 }, -- cover: the black wash
		gentle = 0.08, -- Reduce flashing: the hit stop held instead (seconds)
	},

	nameCard = {
		seconds = 3,
		reach = 150, -- studs past the arena's edge that count as arriving at the fight
		check = 0.5, -- seconds between checks
		-- names come from Config.Boss; the world bosses' titles are nate's lore (build plan step 8), the card reads
		-- e.g. RUSTJAW PRIME / THE JUNKYARD TITAN; the battle form's title is nate's pick (2026-11-19)
		titles = {
			RustjawPrime = "THE JUNKYARD TITAN",
			LumenMaw = "THE LIGHT EATER",
			LeviathanEngine = "THE DEEP MACHINE",
			StormColossus = "THE WEATHER MACHINE", -- bosses-3 (2026-11-20): DRAFT titles until nate OKs them
			SwarmQueen = "THE HIVE CORE",
			QuarryTitan = "THE MAGMA GOLEM",
			NullWarFrame = "THE IRON OATH",
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
			-- WP5: a Suspicious Hero's mask cracked in the street (no flash: it is everyday news; drafts)
			fakeVigil = "%s UNMASKS A FAKE HERO: IT WAS A ROBOT ALL ALONG",
			fakeSyndicate = "PANIC IN THE STREETS: %s CRACKS A HERO'S FACE AND FINDS METAL",
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
			-- The exposition a brand-new hero sees before the creator (fix-flow, 2026-11-19; Config.Story.opening.intro):
			-- who you are, Brightharbor, the Spark, the hunt and Crane's machines, in the lore's own facts (Crane's
			-- ceremony line, Lodestar's safehouse line). PLACEHOLDER ART: the drawn panels until the comic art pass
			-- renders them (art/blender/panels.py; Config.ComicArt "intro.<n>").
			intro = {
				title = "BRIGHTHARBOR",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 150, 210, 255 },
						ground = { 70, 80, 100 },
						scene = "city",
						caption = "Brightharbor: a bright city by the sea, cheering for its famous heroes.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 255, 196, 120 },
						ground = { 70, 60, 80 },
						scene = "blast",
						caption = "Ten years ago the Spark woke powers in people, and it nearly tore the city apart.",
						word = "KRAK!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 120, 60, 70 },
						ground = { 40, 34, 50 },
						scene = "scan",
						caption = "Now Crane Industries scans for the Spark, and Crane's machines hunt anyone who has it.",
						at = 7.5,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 240, 200 },
						ground = { 90, 80, 90 },
						scene = "spark",
						caption = "Today the Spark woke in you. Nobody knows yet. So... who are you?",
						word = "ZAP!",
						at = 11.5,
					},
				},
			},
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
			-- The Harvest King's story (The Harvest King, step 5): the drought, his Spark, the beast he grew
			kingStory = {
				title = "THE SUMMER THE RAIN STOPPED",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 255, 200, 110 },
						ground = { 170, 130, 80 },
						scene = "farm",
						caption = "Three summers without rain. Every farm out here was drying up.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 150, 210, 255 },
						ground = { 90, 140, 60 },
						scene = "sprout",
						caption = "Then my Spark woke up. Anything I touched would grow. Anything!",
						word = "SPROUT!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 120, 160, 210 },
						ground = { 60, 110, 50 },
						scene = "beast",
						caption = "So I grew a guardian to keep the crows off. It grew. And grew.",
						word = "RUMBLE!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 140, 90 },
						ground = { 70, 90, 50 },
						scene = "farm",
						caption = "Now it's always hungry. But it's MINE. Nobody hurts what I made.",
						at = 10.5,
					},
				},
			},
			-- The legend of Captain Brine (The Salt Dogs, step 5): Nell tells how the ghost ship works
			brineLegend = {
				title = "THE LEGEND OF CAPTAIN BRINE",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 150, 200, 235 },
						ground = { 60, 130, 180 },
						scene = "pier",
						caption = "Brine was a salvage diver off Gull Point. One day his Spark woke in the deep.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 60, 70, 100 },
						ground = { 30, 60, 90 },
						scene = "salvage",
						caption = "He pulled old diving robots off the sea floor and made them his crew.",
						word = "CLANK!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 40, 50, 70 },
						ground = { 25, 50, 70 },
						scene = "ghostship",
						caption = "Then the ghost ship came out of the fog. Sailors jumped ship. Brine took the rest.",
						word = "WOOOO!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 30, 30, 40 },
						ground = { 20, 30, 40 },
						scene = "seacave",
						caption = "Every crate goes to his sea cave. Nobody who went looking ever found it.",
						word = "SPLASH!",
						at = 10.5,
					},
				},
			},
			-- The Pitboss's story (The Pit, step 5): the old quarry, his stone Spark, the ring, the debts
			pitStory = {
				title = "THE BOSS OF THE PIT",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 255, 170, 100 },
						ground = { 150, 130, 110 },
						scene = "quarry",
						caption = "When the Old Quarry shut down, the Gravel family kept the mine tunnels under it.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 90, 80, 110 },
						ground = { 110, 100, 95 },
						scene = "stone",
						caption = "Then the eldest son's Spark woke up. His skin turned to quarry stone.",
						word = "CRACK!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 40, 34, 50 },
						ground = { 120, 100, 80 },
						scene = "ring",
						caption = "He never lost a fight. So he dug a ring, sold tickets and took the bets.",
						word = "DING DING!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 70, 20, 24 },
						ground = { 90, 70, 60 },
						scene = "ring",
						caption = "Lose in the Pit and you owe the family. So you fight again. Nobody walks out.",
						at = 10.5,
					},
				},
			},
			-- The Sunken City (the Underwater chain, step 5): the tale of Velmara and its guardian, from the
			-- mosaics in the drowned city's halls
			tidewrightTale = {
				title = "THE LAST GUARDIAN OF VELMARA",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 150, 210, 240 },
						ground = { 210, 190, 140 },
						scene = "velmara",
						caption = "Long ago Velmara stood in the sun, a city of bronze towers by the bay.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 50, 60, 90 },
						ground = { 30, 70, 110 },
						scene = "flood",
						caption = "Then a great storm drowned it. Its people swam for the shore and never came back.",
						word = "WHOOSH!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 20, 50, 80 },
						ground = { 20, 40, 60 },
						scene = "guardian",
						caption = "They left the Tidewright to keep the city safe. It waited, and waited, and slept.",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 25, 40, 60 },
						ground = { 20, 35, 50 },
						scene = "dredger",
						caption = "Last week a salvage drill cracked the seal. The guardian woke up angry.",
						word = "KRAK!",
						at = 10.5,
					},
				},
			},
			-- The Last Partner (Lodestar's line, step 5): the two stars, the diner, the fire, a stranger with her face
			vesperStory = {
				title = "THE EVENING STAR",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 40, 50, 100 },
						ground = { 30, 30, 50 },
						scene = "twostars",
						caption = "For twelve years Lodestar and Vesper kept Brightharbor's night sky safe.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 30, 30, 60 },
						ground = { 60, 50, 60 },
						scene = "diner",
						caption = "After every patrol: the Night Owl diner, two coffees, the booth by the window.",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 120, 40, 30 },
						ground = { 70, 40, 40 },
						scene = "blast",
						caption = "Then the harbour fire, last winter. Vesper flew in for the last family and never came out.",
						word = "FWOOM!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 200, 230 },
						ground = { 120, 90, 120 },
						scene = "tv",
						caption = "Last month she was back: rich, famous, on every screen. She walked right past him.",
						at = 10.5,
					},
				},
			},
			-- Finding Lark (Patch's line, step 5): two kids on a roof, the net vans, the pound, the radio
			larkStory = {
				title = "THE SPARK POUND",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 255, 180, 120 },
						ground = { 80, 70, 80 },
						scene = "sisters",
						caption = "Lark raised her kid brother alone. Patch could fix any radio. Lark could fly.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 60, 60, 80 },
						ground = { 50, 50, 60 },
						scene = "van",
						caption = "Then the net vans came. Catchpole hunts Sparks for the bounty on their heads.",
						word = "FWUMP!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 40, 44, 54 },
						ground = { 70, 72, 80 },
						scene = "cage",
						caption = "Twelve cages in a Docks warehouse. A collar on every Spark, so none can fight back.",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 20, 30, 60 },
						ground = { 40, 40, 60 },
						scene = "city",
						caption = "For a year Patch searched every radio wave in the city. Tonight one answered.",
						at = 10.5,
					},
				},
			},
			-- Hostile Takeover (the Syndicate boss's line, step 4): the Torch Crew, the fires, the Duchess, the job
			scorchStory = {
				title = "THE TORCH CREW",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 255, 160, 90 },
						ground = { 90, 70, 60 },
						scene = "garage",
						caption = "Sal Scorch started with one tow truck and a lighter. Now his Torch Crew owns the garages.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 120, 40, 30 },
						ground = { 70, 40, 40 },
						scene = "blast",
						caption = "Pay the Crew, or your shop catches fire. Nobody in Old Town says no twice.",
						word = "FWOOM!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 60, 20, 40 },
						ground = { 90, 50, 40 },
						scene = "club",
						caption = "For twenty years Duchess Vanta ran Old Town from the Opal Room. Scorch wants her chair.",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 40, 30, 60 },
						ground = { 50, 40, 60 },
						scene = "city",
						caption = "So the Duchess wants him gone, by someone nobody in Old Town knows. You.",
						at = 10.5,
					},
				},
			},
			-- The Scoop (the reporter's line, step 5): the news, the cuts, the last van, the uplink
			cutStory = {
				title = "THE STORIES THAT NEVER AIRED",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 120, 180, 240 },
						ground = { 70, 80, 100 },
						scene = "tv",
						caption = "Every night BHN 24 tells Brightharbor what happened today. Most of it, anyway.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 30, 30, 40 },
						ground = { 40, 40, 50 },
						scene = "blackout",
						caption = "Some stories never air. Tapes vanish. Screens go black in the middle of a sentence.",
						word = "CUT!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 255, 190, 120 },
						ground = { 80, 80, 90 },
						scene = "van",
						caption = "Nora Bright has one van, one camera and one uplink the Censor can't reach.",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 30, 40, 80 },
						ground = { 40, 40, 60 },
						scene = "city",
						caption = "If the uplink holds, every screen in the city shows the truth at once.",
						at = 10.5,
					},
				},
			},
			-- The Ashgrove Test (the Lab origin line, step 5): the test, the flash, the shut lab, the one Spark
			kindlerTruth = {
				title = "THE ASHGROVE TEST",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 150, 200, 230 },
						ground = { 90, 100, 120 },
						scene = "lab",
						caption = "Ashgrove Labs paid volunteers to sit in the Kindler, a ring of light. Most felt nothing.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 40, 50, 90 },
						ground = { 60, 70, 100 },
						scene = "kindler",
						caption = "Then it was your turn. The ring flashed, and something inside you lit up.",
						word = "FZZAP!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 60, 60, 90 },
						ground = { 50, 50, 70 },
						scene = "city",
						caption = "By morning the lab was shut and its files wiped. The director kept testing in secret.",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 236, 170 },
						ground = { 60, 50, 80 },
						scene = "spark",
						caption = "The Kindler never made a Spark. Every powered person has one. It only woke yours.",
						at = 10.5,
					},
				},
			},
			-- Starblood Calling (the Alien origin line, step 5): the falling ship, the pilot who stayed, the song
			podMessage = {
				title = "STARBLOOD",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 30, 26, 60 },
						ground = { 70, 80, 60 },
						scene = "starfall",
						caption = "Long ago a little ship fell from the stars and came down past Radio Hill.",
						word = "KA-THOOM!",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 255, 200, 150 },
						ground = { 110, 140, 80 },
						scene = "seedship",
						caption = "Its pilot stayed, and had a family. The star blood was passed down and down.",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 50, 40, 90 },
						ground = { 90, 110, 70 },
						scene = "radiomast",
						caption = "This week the old pod woke up, and began to sing to its family.",
						word = "LA-LA-LAA!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 236, 170 },
						ground = { 60, 50, 80 },
						scene = "spark",
						caption = "Its message: every Spark is one Spark. Star blood only woke the one in you.",
						at = 10.5,
					},
				},
			},
			-- The Last Owner (the Magic origin line, step 5): the great magician, his relic, his rival, the one Spark
			relicTruth = {
				title = "THE LAST OWNER",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 110, 30, 50 },
						ground = { 70, 40, 40 },
						scene = "stage",
						caption = "Forty years ago, Ambrose the Astonishing filled every theatre in Old Town.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 40, 30, 70 },
						ground = { 60, 40, 60 },
						scene = "relic",
						caption = "His secret was a little relic. Whenever he held it, his Spark woke up.",
						word = "TING!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 60, 20, 40 },
						ground = { 50, 30, 40 },
						scene = "stage",
						caption = "Jealous Morrow had no Spark. He tried to steal it, so Ambrose vanished for good.",
						word = "POOF!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 236, 170 },
						ground = { 60, 50, 80 },
						scene = "spark",
						caption = "The relic was never magic. It only woke the Spark in its owner. Now that is you.",
						at = 10.5,
					},
				},
			},
			-- Suit Recall (the Tech origin line, step 5): the garage, the dead core, the repo crew, the one Spark
			coreTruth = {
				title = "SUIT RECALL",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 255, 210, 150 },
						ground = { 120, 110, 100 },
						scene = "tinkergarage",
						caption = "You built the suit in Tinker Tess's garage, from scrapyard parts and a dead core.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 60, 60, 80 },
						ground = { 90, 85, 80 },
						scene = "suitup",
						caption = "The core stayed dead until you strapped in. Then it lit up.",
						word = "VRRRMM!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 230, 160, 90 },
						ground = { 100, 95, 90 },
						scene = "repo",
						caption = "Clawback's robots take back anything that glows. Now they want yours.",
						word = "CLANK!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 236, 170 },
						ground = { 60, 50, 80 },
						scene = "spark",
						caption = "The core never made your power. It runs on your Spark, and it always has.",
						at = 10.5,
					},
				},
			},
			-- The Taken Master (the Training origin line, step 5): the dojo, the dawn, the student who fell, the one Spark
			masterLesson = {
				title = "THE TAKEN MASTER",
				panels = {
					{
						rect = { 0.03, 0.12, 0.45, 0.4 },
						sky = { 255, 220, 170 },
						ground = { 160, 120, 80 },
						scene = "dojo",
						caption = "For years you trained at Master Hoshi's dojo on Willow Street.",
						at = 0,
					},
					{
						rect = { 0.52, 0.12, 0.45, 0.4 },
						sky = { 255, 170, 110 },
						ground = { 140, 100, 70 },
						scene = "dojo",
						caption = "Then, one dawn, after a thousand falls, your Spark woke up.",
						word = "WHOOSH!",
						at = 3.5,
					},
					{
						rect = { 0.03, 0.56, 0.45, 0.38 },
						sky = { 40, 60, 80 },
						ground = { 50, 50, 60 },
						scene = "suitup",
						caption = "Gale trained just as hard. His Spark never woke, so he built a racing rig.",
						word = "ZOOM!",
						at = 7,
					},
					{
						rect = { 0.52, 0.56, 0.45, 0.38 },
						sky = { 255, 236, 170 },
						ground = { 60, 50, 80 },
						scene = "spark",
						caption = "No one can give you a Spark. Training only wakes the one that was always there.",
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
