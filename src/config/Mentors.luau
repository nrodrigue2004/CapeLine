-- Mentors (spec: Hero MMO features > Original mentors; H6). Pure data, tuned in the playtest.
-- After the opening each hero picks a mentor of their side (2 a side); it can be changed at any safehouse for
-- free. A mentor is a guide and a look, never stats: short comic panels the first time for each big thing
-- (first block, first nemesis, first task force) and at every 5 levels, a 4-part quest line (one part at
-- levels 10, 20, 30 and 40, from things the game already counts) whose last part gives their look reward and
-- the trophy Mentor's Pride, and they fight beside you in their task force's final fight.
-- Rules: Shared.MentorRules; MentorService; MentorHud (the MENTOR button, picker and panels); MentorFx (the
-- looks and the ally's assist beam).
-- Mentors are standalone guides (no story beats), fitted to nate's lore (2026-11-17): the Vigil and the Dread
-- Syndicate are the sides; Lodestar stays the Vigil's veteran and Patch its hacker kid, so no mentor claims
-- either role. Names and looks are the spec's (nate approved); blurbs and lines are drafts.
-- PLACEHOLDER CONTENT: lore thread to fill (each mentor's voice in the panel lines and quest part names)
-- PLACEHOLDER ART: each mentor is the blocky R15 body in their two colours until the Blender pass.
return {
	list = {
		{
			id = "CaptainMeridian",
			name = "Captain Meridian",
			initial = "M",
			side = "hero",
			group = "The Vigil",
			-- spec: "leads the League"; the League is gone and Lodestar is the Vigil's veteran (lore)
			blurb = "A Vigil flier who still runs every drill by the book.",
			colors = { { 40, 70, 160 }, { 240, 200, 70 } }, -- suit, trim
			look = {
				kind = "trail",
				id = "meridianGold",
				name = "Gold Flight Trail",
				color = { 255, 210, 80 },
			},
			emote = 12, -- Config.Shop.emotes (Salute style)
		},
		{
			id = "OldBeacon",
			name = "Old Beacon",
			initial = "B",
			side = "hero",
			group = "City",
			blurb = "The HQ drill coach, an old street hero who trusts people more than rules.",
			colors = { { 90, 110, 80 }, { 255, 190, 90 } },
			look = { kind = "aura", id = "lantern", name = "Lantern Glow", color = { 255, 190, 90 } },
			emote = 13,
		},
		{
			id = "TheMargrave",
			name = "The Margrave",
			initial = "M",
			side = "villain",
			group = "The Dread Syndicate",
			-- spec: "the Syndicate's boss"; kept off the Dread Syndicate's top seat so the lore can fill it
			blurb = "A Dread Syndicate money man: cold, rich, and carrying too many gadgets.",
			colors = { { 50, 30, 70 }, { 170, 110, 230 } },
			look = {
				kind = "trail",
				id = "violetSmoke",
				name = "Violet Smoke Trail",
				color = { 170, 110, 230 },
			},
			emote = 14,
		},
		{
			id = "TheVelvetPaw",
			name = "The Velvet Paw",
			initial = "V",
			side = "villain",
			group = "Independent",
			blurb = "A cat burglar who answers to no one, Old Beacon's villain twin from the drills.",
			colors = { { 120, 30, 60 }, { 120, 230, 255 } },
			look = { kind = "aura", id = "sparkCrackle", name = "Spark Crackle", color = { 120, 230, 255 } },
			emote = 15,
		},
	},

	-- moments that open a comic panel once per character (bits in mmo.mentorSeen); levels every 5 too
	moments = { "firstBlock", "firstNemesis", "firstTaskForce", "pick", "questDone" },
	levelEvery = 5,
	panelTime = 4, -- seconds a panel shows (it never blocks play)
	afterOpening = 8, -- seconds after the prologue's title before the picker pops (Lodestar's last line first)

	-- The quest line: 4 parts, each opening at its level; goals count things the game already tracks
	-- (incident clears, robots defeated, contracts, mission clears, world boss rewards). Each part pays a
	-- mission reward at your level; the last also the mentor's look, their emote and Mentor's Pride.
	-- Switching mentor keeps each mentor's finished parts; the part in progress starts over.
	quest = {
		{ level = 10, goals = { { kind = "incident", n = 3 } } },
		{ level = 20, goals = { { kind = "robot", n = 60 } } },
		{ level = 30, goals = { { kind = "contract", n = 3 }, { kind = "mission", n = 1 } } },
		{ level = 40, goals = { { kind = "boss", n = 1 }, { kind = "mission", n = 2 } } },
	},
	goalNames = {
		incident = "Clear incidents",
		robot = "Defeat robots",
		contract = "Finish contracts",
		mission = "Clear missions",
		boss = "Earn a world boss reward",
	},
	trophy = "mentorPride", -- Config.Hq.trophies id

	-- the ally in their task force's final fight (the task force's own mentor, Config.TaskForce.list[].mentor)
	ally = {
		every = 4, -- seconds between assists
		reach = 60, -- studs: the nearest robot this close to the ally
		bossShare = 0.01, -- an assist takes 1% of a boss robot's health
		share = 0.12, -- and 12% of any other robot's
		offset = { 6, 0, 4 }, -- where it stands from the pocket's boss point
	},

	-- PLACEHOLDER CONTENT: lore thread to fill. Fixed lines ({hero} = your hero name, {level} = the level).
	-- No backstory: tips and cheers only. One set per mentor, in list order.
	lines = {
		CaptainMeridian = {
			pick = "{hero}. Fly straight, keep your guard up, and we will do fine.",
			firstBlock = "Good block. Watch the glow: a heavy wind-up means block, a big flash means move.",
			firstNemesis = "That robot knows your name now. Every time it runs, it leaves a clue.",
			firstTaskForce = "A task force cleared. Rest, then we go again.",
			level = "Level {level}, {hero}. Try a new rank on your best skill.",
			ally = "Stay sharp, {hero}. I have your back.",
			questDone = "You did it, {hero}. Wear the gold with pride.",
		},
		OldBeacon = {
			pick = "Hey, {hero}. Help people first. The robots can wait a second.",
			firstBlock = "Nice block, kid. Hold it, then hit back when they are open.",
			firstNemesis = "A robot that hunts just you. Do not worry, it gets weaker every time it runs.",
			firstTaskForce = "A whole task force! Take your squad for snacks.",
			level = "Level {level}! Look at you, {hero}.",
			ally = "Room for one more? Let's go, {hero}!",
			questDone = "That glow is yours now, {hero}. Keep it lit.",
		},
		TheMargrave = {
			pick = "{hero}. Work for me and you will never work for anyone else.",
			firstBlock = "A block. Good. Never take a hit you did not price in.",
			firstNemesis = "A hunter robot with your name on it. Let it run. Learn from it.",
			firstTaskForce = "A clean job. The Dread Syndicate notices.",
			level = "Level {level}. Your value goes up, {hero}.",
			ally = "I came to protect my investment, {hero}.",
			questDone = "Smoke suits you, {hero}. Leave a little everywhere you go.",
		},
		TheVelvetPaw = {
			pick = "Oh, {hero}. Stay quick and stay curious.",
			firstBlock = "Ooh, a block. Now dodge the next one, it looks cooler.",
			firstNemesis = "Someone has a fan. Lead it on a chase, {hero}.",
			firstTaskForce = "A whole job, done. I am almost impressed.",
			level = "Level {level}. Faster every day, {hero}.",
			ally = "Did someone say big robot? Count me in.",
			questDone = "Sparks, for my favourite. Do not get caught.",
		},
	},
	partNames = { "Part 1", "Part 2", "Part 3", "Part 4" }, -- PLACEHOLDER CONTENT: lore thread to fill
}
