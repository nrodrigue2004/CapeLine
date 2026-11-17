-- Story (spec: Opening, Act 1 story, quests; Act 1 choices; Side quests; nate's lore doc, build plan steps 3
-- and 5). Pure data: the Ceremony prologue's beats and lines, the 6 Act 1 missions (mission 1 is the prologue
-- itself), the 3 choices with each side's own options, the 7 mission pockets and the 8 side quest arcs. Every
-- number is a starting value to tune. All names and characters are original.
--
-- Act 1 missions (nate's lore, build plan step 5): every mission is co-op. `hero` and `villain` list the same
-- number of stages; a stage whose entry is the very same table in both lists is shared (one boss, one camera
-- beat, one goal for the whole party, with each side's own objective text: `text` and `villainText`), and a
-- stage with two different entries runs both at once in the same pocket, each side on its own job. The party
-- moves on when every side present has finished the stage. Camera beats (kind "scene") are short in-engine
-- moments with fixed subtitled lines: `who` names a speaker in opening.speakers; a line with `hero` and
-- `villain` texts reads by the side (nothing free-typed).

-- Shared stages (the same table in both lists)
local SAFEHOUSE_TUNNELS = {
	kind = "scene",
	seconds = 10,
	focus = "door",
	lodestar = "door", -- Lodestar stands here (in person)
	lines = {
		{
			at = 0.5,
			who = "lodestar",
			text = "Stay close. These tunnels ran under the city long before Crane did.",
		},
		{
			at = 5,
			who = "patch",
			text = "Hi again! Patch, your friendly voice in the walls. Old Star, did you warn them about the drones?",
		},
	},
}
local SAFEHOUSE_GAUNTLET = {
	kind = "reach",
	at = "gauntletEnd",
	turrets = 4,
	room = 2,
	text = "Get past the old security line",
}
local SAFEHOUSE_DOOR = { kind = "reach", at = "door", text = "Reach the safehouse door" }
local SAFEHOUSE_OFFER = {
	kind = "scene",
	seconds = 17,
	focus = "door",
	lodestar = "door",
	lines = {
		{
			at = 0.5,
			who = "lodestar",
			text = "Everyone with the Spark is being hunted. Crane's machines scan for it, so nobody can hide.",
		},
		{
			at = 6,
			who = "lodestar",
			hero = "The Vigil protects this city, even while it hunts us. Stand with us.",
			villain = "I know what you are. Crane wants your Spark as much as mine. Share the hideout, and keep your hands off my people.",
		},
		{
			at = 12,
			who = "patch",
			hero = "Welcome to the Vigil! I made you a badge. It's mostly tape.",
			villain = "A Syndicate crook in our safehouse? Fine. I'm hiding the snacks, Old Star.",
		},
	},
}

local FRAMED_BRIDGE = {
	kind = "scene",
	seconds = 11,
	focus = "boss",
	lines = {
		{ at = 0.5, who = "patch", text = "Radiant's over the bridge, and the cables are snapping!" },
		{ at = 4, who = "radiant", text = "Stay back, citizens! A rogue Spark hero did this!" },
		{ at = 7.5, who = "patch", text = "A rogue Spark? Those are Radiant's own light bolts!" },
	},
}
local FRAMED_FAKE = {
	kind = "fake",
	enemy = "Radiant",
	at = "boss",
	hpMult = 0.8,
	dmg = 0.6,
	text = "Crack Radiant's face on camera",
	villainText = "Knock Radiant down for its data core",
}
local FRAMED_PROOF = {
	kind = "scene",
	seconds = 8,
	focus = "fake",
	lines = {
		{
			at = 0.3,
			who = "patch",
			hero = "Its face! It's metal! And you got it ALL on camera!",
			villain = "Metal under the gold. And there's a data core glowing in its chest.",
		},
		{ at = 4.5, who = "radiant", text = "Identity compromised. Retreat." },
	},
}
local FRAMED_NEWS = {
	kind = "scene",
	seconds = 10,
	focus = "spawn",
	lines = {
		{
			at = 0.5,
			who = "crane",
			text = "Radiant reports a rogue Spark wrecked the bridge. Crane Industries is helping every victim.",
		},
		{
			at = 5.5,
			who = "patch",
			hero = "Lies. But we've got the footage, and Old Star is going to love it.",
			villain = "Lies. Not that you care, as long as you got paid.",
		},
	},
}

local COPY_SCAN = {
	kind = "scene",
	seconds = 11,
	focus = "copy",
	lines = {
		{ at = 0.5, who = "patch", text = "Hold still. Something on that roof is scanning you." },
		{
			at = 4,
			who = "patch",
			text = "It copied your Spark. Your face, your powers. That's YOU over there!",
		},
		{ at = 8, who = "copy", text = "Copy complete. I'll take your life from here." },
	},
}
local COPY_TWIN = {
	kind = "twin",
	at = "copy",
	text = "Beat your evil twin across the rooftops",
	villainText = "Beat the copy wearing your face",
}
local COPY_AFTER = {
	kind = "scene",
	seconds = 9,
	focus = "copy",
	lines = {
		{
			at = 0.5,
			who = "patch",
			hero = "If Crane can copy you, he can copy anyone. The city needs proof it can see.",
			villain = "Crane copies anyone he likes. Someone should show the whole city, for a price.",
		},
		{ at = 5, who = "patch", text = "Crane Tower has the biggest broadcast mast in town. Just saying." },
	},
}

local SIGNAL_CLIMB = { kind = "reach", at = "top", text = "Climb Crane Tower" }
local SIGNAL_INSIDER = {
	kind = "scene",
	seconds = 13,
	focus = "mast",
	lines = {
		{
			at = 0.5,
			who = "insider",
			text = "You don't know me. I work for Crane, and I've seen what's in his vaults.",
		},
		{ at = 5, who = "insider", text = "The broadcast mast is open for the next ten minutes. Use it." },
		{
			at = 9,
			who = "patch",
			hero = "A Crane insider? Could be a trap. Your call.",
			villain = "A Crane insider handing us every screen in the city? Your call, boss.",
		},
	},
}
local SIGNAL_WARDEN = {
	kind = "boss",
	enemy = "NullSentinel", -- the Warden
	hpMult = 8,
	adds = { "SparkDrone", 3 },
	text = "Beat the tower's Warden",
}
local SIGNAL_ON_AIR = {
	kind = "scene",
	seconds = 11,
	focus = "mast",
	lines = {
		{
			at = 0.5,
			who = "patch",
			hero = "We're on every screen! Now we need a fake to unmask, live, where nobody can deny it.",
			villain = "Your feed is on every screen. Crane pays, or the city sees what you saw.",
		},
		{
			at = 6,
			who = "crane",
			text = "Brightharbor, criminals hijacked our towers tonight. Tomorrow, Bulwark speaks at the Hero Hall.",
		},
	},
}

local LIVE_EVENT = {
	kind = "scene",
	seconds = 12,
	focus = "boss",
	lines = {
		{ at = 0.5, who = "crane", text = "Brightharbor! The hero who never falls: Bulwark!" },
		{
			at = 4.5,
			who = "bulwark",
			text = "Citizens. I am your shield. Every rogue Spark will be brought in.",
		},
		{ at = 8.5, who = "patch", text = "Cameras rolling. The whole city is watching. Crack that face!" },
	},
}
local LIVE_FAKE = {
	kind = "fake",
	enemy = "Bulwark",
	at = "boss",
	hpMult = 1,
	dmg = 0.7,
	news = "unmask", -- the crack goes out on every screen in the server (a news flash for everyone)
	text = "Crack Bulwark's face live on every screen",
	villainText = "Crack Bulwark's face for the whole city",
}
local LIVE_UNMASKED = {
	kind = "scene",
	seconds = 8,
	focus = "fake",
	lines = {
		{ at = 0.3, who = "patch", text = "Every screen in the city just saw that! Bulwark is a ROBOT!" },
		{ at = 4.5, who = "bulwark", text = "Exposure detected. Battle form." },
	},
}
local LIVE_BATTLE = {
	kind = "warframe",
	text = "Bring down Bulwark's battle form",
	villainText = "Wreck Bulwark's battle form",
}

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
			-- Act 1's missions (lore step 5): the insider is a voice on the radio; the fakes speak in person
			insider = { name = "CRANE INSIDER", color = { 230, 160, 255 }, radio = true },
			radiant = { name = "RADIANT", color = { 255, 220, 120 } },
			bulwark = { name = "BULWARK", color = { 200, 205, 215 } },
			copy = { name = "THE COPY", color = { 255, 110, 110 } },
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

	-- Act 1 (nate's lore, build plan step 5): minLevel and the order gate entry; first clears pay once. Levels,
	-- minutes and rewards are the old Act 1's at the same index, so pacing and totals do not move.
	missions = {
		{
			num = 1,
			id = "Ceremony",
			name = "The Ceremony",
			minLevel = 1,
			opening = true, -- the prologue (lore step 3), in the city and the subway pocket, not the board
			skillPoints = 1,
			blurb = "Crane's medal ceremony goes wrong. Your Spark wakes up.",
		},
		{
			num = 2,
			id = "Safehouse",
			name = "Safehouse",
			minLevel = 3,
			layout = "dungeon",
			minutes = 8,
			loot = "story",
			blurb = "Lodestar takes you underground. Patch is on the radio.",
			hero = {
				SAFEHOUSE_TUNNELS,
				{
					kind = "defeat",
					squads = { { "SparkDrone", 3 }, { "BurglarBot", 2 } },
					room = 1,
					text = "Clear the scanner drones from the tunnel",
				},
				SAFEHOUSE_GAUNTLET,
				SAFEHOUSE_DOOR,
				SAFEHOUSE_OFFER,
			},
			villain = {
				SAFEHOUSE_TUNNELS,
				{
					kind = "break",
					points = 3,
					hits = 12,
					list = "relays",
					text = "Smash Crane's scanner relays",
				},
				SAFEHOUSE_GAUNTLET,
				SAFEHOUSE_DOOR,
				SAFEHOUSE_OFFER,
			},
		},
		{
			num = 3,
			id = "Framed",
			name = "Framed",
			minLevel = 4,
			layout = "bridge",
			minutes = 8,
			loot = "story",
			renown = 600,
			blurb = "Radiant wrecks a bridge and blames a real hero.",
			hero = {
				FRAMED_BRIDGE,
				{
					kind = "hold",
					points = 3,
					seconds = 10,
					radius = 12,
					waves = { { "SparkDrone", 4 }, { "SparkDrone", 5 }, { "BurglarBot", 3 } },
					waveGap = 14,
					text = "Get the people off the bridge",
				},
				FRAMED_FAKE,
				FRAMED_PROOF,
				{ kind = "choice", choice = 1, text = "The bridge or the fake?" },
				{ kind = "branch", choice = 1 },
				FRAMED_NEWS,
			},
			villain = {
				FRAMED_BRIDGE,
				{
					kind = "break",
					points = 3,
					hits = 14,
					guards = { "Turret", 2 },
					text = "Loot the armored trucks in the chaos",
				},
				FRAMED_FAKE,
				FRAMED_PROOF,
				{ kind = "choice", choice = 1, text = "The data core or the cash?" },
				{ kind = "branch", choice = 1 },
				FRAMED_NEWS,
			},
			-- what each side's pick puts in at the branch (option 1, option 2)
			branches = {
				hero = {
					{
						kind = "break",
						points = 1,
						hits = 30,
						train = true,
						text = "Stop the runaway train before the gap",
					},
					{
						kind = "chase",
						enemy = "Radiant",
						fake = true,
						hops = 7,
						speed = 24,
						text = "Chase Radiant down",
					},
				},
				villain = {
					{
						kind = "chase",
						enemy = "Radiant",
						fake = true,
						hops = 7,
						speed = 24,
						text = "Run Radiant down and rip out its data core",
					},
					{
						kind = "break",
						points = 1,
						hits = 30,
						at = "van",
						text = "Crack the armored cash van",
					},
				},
			},
		},
		{
			num = 4,
			id = "TheCopy",
			name = "The Copy",
			minLevel = 5,
			layout = "rooftops",
			minutes = 7,
			rep = 120, -- own-side reputation on the first clear
			blurb = "A fake copies your look and powers. Fight your evil twin.",
			hero = {
				{ kind = "reach", at = "contact", text = "Answer the rooftop alarm" },
				COPY_SCAN,
				COPY_TWIN,
				{ kind = "choice", choice = 3, text = "Your twin's core" },
				COPY_AFTER,
			},
			villain = {
				{ kind = "reach", at = "contact", text = "Meet the fence on the rooftop" },
				COPY_SCAN,
				COPY_TWIN,
				{ kind = "choice", choice = 3, text = "Your twin's core" },
				COPY_AFTER,
			},
		},
		{
			num = 5,
			id = "TheSignal",
			name = "The Signal",
			minLevel = 6,
			layout = "tower",
			minutes = 10,
			loot = "story",
			blurb = "Take Crane's broadcast tower so the city sees the truth.",
			hero = {
				SIGNAL_CLIMB,
				SIGNAL_INSIDER,
				{ kind = "choice", choice = 2, text = "Trust the insider?" },
				{ kind = "branch", choice = 2 },
				{
					kind = "hold",
					points = 1,
					seconds = 20,
					radius = 10,
					at = "mast",
					waves = { { "SparkDrone", 3 }, { "BurglarBot", 3 } },
					waveGap = 12,
					text = "Guard Patch's uplink at the mast",
				},
				SIGNAL_WARDEN,
				SIGNAL_ON_AIR,
			},
			villain = {
				SIGNAL_CLIMB,
				SIGNAL_INSIDER,
				{ kind = "choice", choice = 2, text = "The truth feed" },
				{ kind = "branch", choice = 2 },
				{
					kind = "hold",
					points = 1,
					seconds = 20,
					radius = 10,
					at = "relay",
					waves = { { "BurglarBot", 3 }, { "SparkDrone", 3 } },
					waveGap = 12,
					text = "Plant the Syndicate feed on the relay",
				},
				SIGNAL_WARDEN,
				SIGNAL_ON_AIR,
			},
			branches = {
				hero = {
					{ kind = "none" }, -- trust: straight on
					{
						kind = "defeat",
						squads = { { "BurglarBot", 4 }, { "SparkDrone", 2 } },
						at = "top", -- on the tower's deck, where the party stands
						text = "Testing her tipped off the guards: beat them",
					},
				},
				villain = { { kind = "none" }, { kind = "none" } },
			},
		},
		{
			num = 6,
			id = "Live",
			name = "Live",
			minLevel = 8,
			layout = "arena",
			minutes = 12,
			loot = "storyFinale",
			skillPoints = 1,
			finale = true,
			ending = "act1", -- the ending broadcast plays after it (Config.Story.ending)
			blurb = "Unmask a famous fake live on every screen in the city.",
			hero = {
				{
					kind = "hold",
					points = 3,
					seconds = 6,
					radius = 10,
					list = "cams",
					waves = { { "SparkDrone", 3 }, { "BurglarBot", 2 } },
					waveGap = 16,
					text = "Set up the cameras around the stage",
				},
				LIVE_EVENT,
				LIVE_FAKE,
				LIVE_UNMASKED,
				LIVE_BATTLE,
			},
			villain = {
				{
					kind = "break",
					points = 3,
					hits = 14,
					list = "screens",
					guards = { "Turret", 1 },
					text = "Hijack the stage screens",
				},
				LIVE_EVENT,
				LIVE_FAKE,
				LIVE_UNMASKED,
				LIVE_BATTLE,
			},
		},
	},

	-- Choices (nate's lore: one per side in Framed, The Signal and The Copy). Each side has its own two
	-- options; each grants 2 Skill Points once. An option records its story flag and pays reputation, and a
	-- few add a cosmetic (the Echo Drone, the crackling arena): nothing that changes stats. The choice number
	-- is the save slot, kept from the old Act 1 so older picks keep their meaning (1 the first mission choice,
	-- 2 the trust test, 3 the robot core).
	choices = {
		{
			num = 1,
			mission = 3,
			skillPoints = 2,
			hero = {
				{ label = "Save the Bridge", flag = "bridgeSaved", rep = { "city", 100 } },
				{ label = "Chase the Fake", flag = "fakeChased", rep = { "side", 100 } },
			},
			villain = {
				{ label = "Grab the Data Core", flag = "coreStolen", rep = { "side", 100 } },
				{ label = "Grab the Cash", flag = "cashGrabbed", rep = { "side", 100 } },
			},
		},
		{
			num = 2,
			mission = 5,
			skillPoints = 2,
			hero = {
				{ label = "Trust Her", flag = "insiderTrusted", rep = { "side", 100 } },
				{ label = "Test Her", flag = "insiderTested", rep = { "city", 100 } },
			},
			villain = {
				{ label = "Share the Feed", flag = "feedShared", rep = { "city", 100 } },
				{ label = "Hold It for Ransom", flag = "feedRansomed", rep = { "side", 100 } },
			},
		},
		{
			num = 3,
			mission = 4,
			skillPoints = 2,
			hero = {
				{ label = "Spare the Core", flag = "twinStudied", rep = { "side", 100 } },
				{ label = "Destroy It", flag = "twinDestroyed", rep = { "city", 100 }, arena = true }, -- Live's
				-- arena pillars crackle (a cosmetic arena effect)
			},
			villain = {
				{ label = "Reprogram It", flag = "twinMinion", rep = { "side", 100 }, perk = "NullEcho" }, -- the
				-- twin's core as a little drone minion (cosmetic)
				{ label = "Sell It", flag = "twinSold", rep = { "side", 100 } },
			},
		},
	},
	perks = {
		NullEcho = {
			bit = 1,
			name = "Echo Drone",
			text = "A little drone made from a robot core follows you",
		},
	},

	-- The end of Act 1 (nate's lore: Crane answers on TV; the registration law passes and the hero is public
	-- enemy number 1): a news-style screen on the HUD after Live, back in the city. Fixed lines; the hero's
	-- own name goes under PUBLIC ENEMY #1.
	ending = {
		act1 = {
			seconds = 20,
			channel = "CRANE NEWS NETWORK",
			breaking = "BREAKING NEWS",
			headline = "HERO REGISTRATION ACT PASSES",
			ticker = "Every Spark must register and be scanned by Crane Industries  *  Unregistered Sparks will be hunted",
			lines = {
				{
					at = 1,
					who = "crane",
					text = "Tonight a criminal used a cheap trick to attack Bulwark on live TV.",
				},
				{
					at = 6,
					who = "crane",
					text = "So tonight the Hero Registration Act is law. Every Spark registers.",
				},
				{
					at = 11,
					who = "crane",
					text = "And the one behind this attack is now public enemy number one.",
				},
			},
			enemyAt = 13, -- seconds: the PUBLIC ENEMY #1 card slams in
			enemy = "PUBLIC ENEMY #1",
			sign = "TO BE CONTINUED",
		},
	},
	-- Every-screen news flashes (a toast for everyone in the server); %s is the fake's name
	news = { unmask = "BREAKING: %s IS A ROBOT FAKE" },
	-- What a side that finished its job reads while the other side is still on theirs
	wait = {
		hero = "Cover the Syndicate while they finish their job",
		villain = "Let the Vigil finish their job",
	},

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

	-- Bulwark's battle form (Live, mission 6; the old mission 6 fight reused): 36,000 HP at level 20, scaled by
	-- the party's median level. A BossSim boss with a back shield in phase 2 and pillars that block its laser in
	-- phase 3. (The key stays "warframe" so saves and data stay put.)
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
