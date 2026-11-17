-- SideQuests (nate's lore, build plan step 10: the side quest framework). Pure data; Shared.SideQuestPlan holds
-- the rules and SideQuestService runs them. nate's rules: side quests are real story quests, not chores, in three
-- layers: district story chains (6 to 10 quests with a mini villain finale), character quest lines and an origin
-- quest line per origin (Lab, Alien, Magic, Tech, Training); mostly standalone from the main story; each side
-- gets its own flavour (Vigil: rescues and exposing fakes; Syndicate: heists and sabotage).
--
-- A chain: id (never change), bit (its place in the save's done set, 1 to 127; never reuse or move), name,
-- layer, giver (a row in givers), unlock rules, villain (the finale's name card), reward, lines and 5 to 10
-- steps. The real chains come in step 11, one at a time; `dev` chains are offered only in Studio with
-- Config.Dev.sideQuestSample on (the Dev panel gives them anyway).
-- * unlock: level (the hero's), story (that Act 1 mission cleared), after (another chain finished), origin
--   (Config.Creator.origins index; origin lines need it), side ("hero" or "villain": a line for one side
--   only), npc (true: accepted only by talking to the giver, never from the Journal: character lines).
-- * a step: hero and villain goals (the very same table in both is one shared goal), optional `lines`
--   (guide lines as it starts: { who, text } or { who, hero, villain }) and `scene` (a Config.Cinema client
--   scene id played in the next quiet moment). A goal: kind, the kind's numbers, text (and villainText on a
--   shared goal). The last step is the finale (kind "finale"), and only the last.
-- * kinds (Shared.SideQuestPlan.KINDS): talk, fight, incident, chase, deliver, fetch, hold, escort, carry,
--   race, reach, find, photo, beacon, pocket (a mission-shaped run in a mission pocket) and finale (the mini
--   villain: a boss-lite fight on an elite robot or a famous fake, with a name card).
-- * pay: every step pays like a contract at the hero's level (pay.contract x pay.step), the finale more, and
--   the chain's end its reward: a share of contract pay (at most pay.maxShare) and one cosmetic or title.
--   Nothing sold, nothing that changes stats beyond normal Renown.
-- * lines: what the giver says on the Talk prompt (offer, resume, done), each side its own text.
-- No free text anywhere: every string is fixed, with no format holes.
return {
	range = 12, -- talk range to a giver (the Talk prompt)
	gap = 3, -- seconds after a step before the next one is built
	coop = 220, -- studs: a squadmate on the same chain and step this close to its site shares it
	minSteps = 5,
	maxSteps = 10,
	maxText = 60, -- tracker text cap (a phone's tracker row)
	layers = { "district", "character", "origin" },
	-- where a district chain may be set (the city's districts, the outskirts rings, the quarry, the deep)
	districts = {
		"Downtown",
		"Uptown",
		"Docks",
		"OldTown",
		"Suburbs",
		"Farmland",
		"Coast",
		"OldQuarry",
		"Underwater",
	},
	sides = { "hero", "villain" },
	pocketNum = 160, -- MissionState num for a side quest pocket run (after the Showdown's 150)
	none = "Nothing for you right now. Come back later.", -- a giver with nothing to offer this hero yet
	pocketMinutes = { 4, 15 },
	finale = {
		reach = 150, -- studs from the finale that show the name card
		hpMult = { 2, 14 }, -- the boss-lite's health multiplier (a mission boss is 8)
		enemies = {
			"NullSentinel",
			"Captain",
			"Grappler",
			"Interceptor",
			"Radiant",
			"Bulwark",
			"Skylance",
			"HeadmasterHalo",
		},
	},
	pay = {
		contract = "DroneSweep", -- the yard stick: this contract's pay at the hero's level
		step = 0.6, -- a step pays this share of it
		finale = 1.5, -- the finale
		maxShare = 4, -- a chain's end reward may be at most this share (reward.share)
	},
	-- The 8 side quest arcs before step 10 (retired by nate, 2026-11-17): only their count and what a finished
	-- one gave stay, by number, so old saves lose nothing (Shared.SideQuestPlan.settle): a finished arc keeps
	-- its unlocks and counts toward the chain pieces; an arc in progress pays stepCredits a finished step.
	retired = {
		arcs = 8,
		stepCredits = 200,
		rewards = {
			[1] = { style = "GoldSash" },
			[2] = { emote = "Salute" },
			[3] = { prop = "CafeSign" },
			[5] = { style = "DockCoat" },
			[8] = { frame = "PhotoFrame" },
		},
	},

	-- Where chains happen inside the city's existing buildings (lore step 11): Shared.SideQuestSites picks the
	-- building from the seeded layout (the Downtown building nearest `near`, metres from the Beacon Tower's
	-- plaza, that keeps every `away` distance and the height range) and its door (the face that opens on a
	-- street, nearest the plaza). A giver with anchor "site" stands at that door; the map marks it by `name`.
	sites = {
		-- nate's decision (2026-11-17): the Hero Academy is an existing Downtown building, not an open square
		-- (those are The Gala Heist's): west of the plaza, clear of the ceremony, the 6-roof chase row and the
		-- Safehouse stairwell. Inside it is the "academy" pocket (Shared.PocketLayout).
		Academy = {
			name = "HALO ACADEMY",
			district = "Downtown",
			near = { -254, -26 },
			height = { 80, 200 }, -- a big school block, not a tower (no skyscraper crown either)
			away = { plaza = 220, row = 150, door = 180, open = 80 },
		},
	},

	-- Who gives chains: a person on the R15 rig at an anchor ("plaza", "hq", a Config.City district, or "site"
	-- with `site`: a row in sites) plus an offset; also a guide speaker (GuideHud lines). `look` (optional): a
	-- fixed hero look from earnable creator pieces (Shared.FakeRules.lookFrom, validated by CreatorRules) drawn
	-- by LookKit; without one, plain colours (PLACEHOLDER ART until the art pass).
	givers = {
		-- The Hero Academy's giver: the academy's grumpy night janitor, who found the stairs nobody uses. He wants
		-- the kids safe (the Vigil) and his three years of back pay out of Halo's vault (the Dread Syndicate).
		Gus = {
			name = "JANITOR GUS",
			anchor = "site",
			site = "Academy",
			color = { 120, 170, 210 },
			style = "person",
			blip = "guideLodestar",
			portrait = {
				bg = { 40, 58, 80 },
				skin = { 200, 150, 110 },
				hair = { 190, 190, 196 },
				shape = "messy",
				extras = { "cap", "beard" },
			},
			look = {
				gender = 1,
				build = 3,
				height = 3,
				skin = 4,
				hair = 19, -- silver
				colors = { 10, 19, 47 }, -- blue, silver, yellow
				pieces = {
					shirt = "Flannel Shirt",
					pants = "Cargo Trousers",
					visage = "Stern Face",
					hair = "Short Crop",
					beard = "Mutton Chops",
					hat = "Ball Cap",
					belt = "Utility Belt",
					feet = "Boots",
				},
				tints = {},
				mats = {},
			},
		},
		-- PLACEHOLDER (Dev only): the framework sample's giver
		SampleGiver = {
			name = "TEST GIVER",
			dev = true,
			anchor = "plaza",
			dx = -60,
			dz = 70,
			color = { 120, 200, 140 },
			style = "person",
			blip = "radio",
			portrait = {
				bg = { 40, 70, 50 },
				skin = { 224, 180, 140 },
				hair = { 60, 40, 30 },
				shape = "messy",
				extras = {},
			},
		},
	},

	chains = {
		-- PLACEHOLDER TEXT (Dev only): "Framework sample", 5 steps that run every runtime path once (talk, a
		-- fight and a heist run, an incident and a chase, a pocket run, the finale with its name card and a
		-- scene). Real chains come in build plan step 11.
		{
			id = "Sample",
			bit = 1,
			name = "Framework sample",
			layer = "district",
			district = "Downtown",
			giver = "SampleGiver",
			dev = true,
			unlock = { level = 1 },
			villain = { name = "THE TEST VILLAIN", title = "FRAMEWORK SAMPLE" },
			reward = { share = 2, emote = "Bow" },
			lines = {
				offer = {
					hero = "Sample chain. Five steps to test the framework.",
					villain = "Sample chain. Five jobs to test the framework.",
				},
				resume = { text = "Back for the sample? Pick up where you left off." },
				done = { text = "Sample done. Every step kind ran." },
			},
			steps = {
				{
					hero = { kind = "talk", text = "Sample: talk to the test giver" },
					villain = { kind = "talk", text = "Sample: talk to the test giver" },
					lines = {
						{
							who = "SampleGiver",
							hero = "Step one: talk. Done.",
							villain = "Step one: talk. Done.",
						},
					},
				},
				{
					hero = {
						kind = "fight",
						squads = { { "BurglarBot", 3 } },
						range = { 60, 150 },
						text = "Sample: stop the robots",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Sample: run the loot to the drop",
					},
					lines = { { who = "patch", text = "Sample radio line: each side has its own job here." } },
				},
				{
					hero = { kind = "incident", count = 1, text = "Sample: clear an incident" },
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Sample: catch the runner bot",
					},
				},
				{
					hero = {
						kind = "pocket",
						layout = "arena",
						minutes = 8,
						text = "Sample: clear the pocket",
						villainText = "Sample: clear the pocket",
						steps = {
							{
								kind = "defeat",
								squads = { { "SparkDrone", 4 } },
								text = "Sample: beat the drones",
							},
							{
								kind = "boss",
								enemy = "Captain",
								hpMult = 3,
								text = "Sample: beat the captain",
							},
						},
					},
					villain = "same", -- the hero's goal, shared (see SideQuestPlan.goal)
				},
				{
					hero = {
						kind = "finale",
						enemy = "NullSentinel",
						hpMult = 4,
						adds = { { "SparkDrone", 3 } },
						range = { 80, 180 },
						text = "Sample: beat the test villain",
						villainText = "Sample: beat the test villain",
					},
					villain = "same",
					scene = "cityWatch",
				},
			},
		},

		-- Downtown chain 1 (nate's lore, build plan step 11): The Hero Academy. nate's draft: "A famous fake runs a
		-- 'hero academy' that secretly recruits kids with Sparks (ties to Crane). Headmaster Halo, a fake teacher
		-- hero." 8 quests (the draft's count). Halo Academy, a free hero school in an existing Downtown building,
		-- measures every new kid's Spark; the "honours class" goes down hidden stairs to a Crane copier workshop.
		-- The Vigil photograph the recruiters, get a field trip home, find the runaway student Wren, free the kids
		-- and put the proof on every screen; the Dread Syndicate steal the Spark files, rob the bursar bot, fence
		-- the list, rip out the copier cores and loot the tuition safes. Both crack Halo's face at the end.
		{
			id = "HeroAcademy",
			bit = 2,
			name = "The Hero Academy",
			layer = "district",
			district = "Downtown",
			giver = "Gus",
			site = "Academy",
			unlock = { story = 2 }, -- after Act 1's Safehouse
			villain = { name = "HEADMASTER HALO", title = "THE FAKE TEACHER" },
			reward = { share = 3, title = "Class Dismissed", style = "CrackedHalo" },
			-- the Journal page: one line of the story so far, by side
			blurb = {
				hero = "Halo Academy trains Spark kids for free. Some come back from class... different.",
				villain = "Halo Academy sits on Spark files, Crane tech and a vault. Help yourself.",
			},
			lines = {
				offer = {
					hero = "You look like the real thing. Halo Academy takes Spark kids, and some don't come back right.",
					villain = "You look like trouble. Good. Halo owes me three years of pay, and his vault is right here.",
				},
				resume = {
					hero = "Back again? Those kids are still in there. Let's go.",
					villain = "Back for the rest of the loot? It isn't going anywhere. Neither is Halo.",
				},
				done = {
					hero = "The kids are home and the halls are quiet. Not bad, hero. Not bad at all.",
					villain = "Vault's empty, Halo's scrap and I got my pay. Pleasure doing crimes with you.",
				},
			},
			steps = {
				-- 1. Enrolment day: the academy at the gates, Gus's story
				{
					hero = { kind = "talk", text = "Hear Janitor Gus out at Halo Academy" },
					villain = { kind = "talk", text = "Get Janitor Gus's tip at Halo Academy" },
					scene = "academyGates",
					lines = {
						{
							who = "Gus",
							hero = "Every Spark kid gets free lessons. The honours class goes downstairs. Nobody comes up the same.",
							villain = "Halo keeps a vault, a list of every Spark kid and a basement nobody's allowed in. Interested?",
						},
						{
							who = "patch",
							hero = "Headmaster Halo? He's on every cereal box. Free hero school for Spark kids? Too good to be true.",
							villain = "Free tuition for Spark kids? Nobody gives anything away for free. Find the angle.",
						},
					},
				},
				-- 2. The Vigil expose the recruiters; the Syndicate steal the Spark files
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 40, 140 },
						text = "Photograph Halo's recruiter bots",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "BurglarBot", 2 },
						text = "Swipe the academy's Spark files",
					},
					lines = {
						{
							who = "patch",
							hero = "Those 'recruiters' handing out flyers are robots. Get them on camera. Proof first!",
							villain = "Those files list every Spark kid in the city. That list is worth a fortune.",
						},
					},
				},
				-- 3. A field trip to nowhere / the bursar bot with the vault key
				{
					hero = {
						kind = "escort",
						goal = 160,
						speed = 9,
						near = 40,
						text = "Get the field trip bus home safe",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the bursar bot with the vault key",
					},
					lines = {
						{
							who = "lodestar",
							hero = "A field trip with no teachers on board? Stay on that bus, kid. I'll watch the roofs.",
							villain = "That bursar bot carries Halo's vault key. Whatever you want it for, don't hurt the kids.",
						},
						{
							who = "patch",
							hero = "The honours class is on a bus to the docks. The docks! Get it home!",
							villain = "The key's on the run. Catch that bot and the vault is ours.",
						},
					},
				},
				-- 4. The runaway student / fence the files
				{
					hero = {
						kind = "find",
						range = { 100, 250 },
						witness = true,
						text = "Find Wren, the student who ran away",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Fence the Spark files at the drop",
					},
					lines = {
						{
							who = "patch",
							hero = "One kid ran from the honours class. Wren. Her phone pinged somewhere around here.",
							villain = "Buyer's waiting at the drop. Bring the files and don't get followed.",
						},
					},
				},
				-- 5. Inside Halo Academy: classrooms, the training hall and the workshop under it
				{
					hero = {
						kind = "pocket",
						layout = "academy",
						minutes = 12,
						text = "Get inside Halo Academy",
						villainText = "Break into Halo Academy",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "ShieldBearer", 2 }, { "BurglarBot", 2 } },
								text = "Clear the hall monitor bots from class",
								villainText = "Scrap the hall monitor bots",
							},
							{
								kind = "hold",
								at = "hall",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "SparkDrone", 3 } },
								waveGap = 10,
								text = "Shield the students in the training hall",
								villainText = "Hold the gym while the vault drill runs",
							},
							{
								kind = "reach",
								at = "workshop",
								text = "Take the hidden stairs under the gym",
								villainText = "Follow the stairs to the real money",
							},
							{
								kind = "break",
								list = "pods",
								points = 4,
								hits = 3,
								text = "Smash the Spark scanners. Free the kids!",
								villainText = "Rip the copier cores out of the scanners",
							},
							{
								kind = "boss",
								enemy = "Grappler",
								hpMult = 3,
								adds = { "SparkDrone", 2 },
								text = "Beat the workshop's foreman bot",
								villainText = "Scrap the foreman bot for parts",
							},
						},
					},
					villain = "same",
					scene = "wrenStory",
					lines = {
						{
							who = "wren",
							hero = "He measured my Spark with a machine. Then a robot used MY powers! The workshop is under the gym.",
							villain = "You're not heroes, are you? Doesn't matter. The workshop's under the gym. Please hurry.",
						},
					},
				},
				-- 6. Out with the kids / out with the cores; Halo on the school speakers
				{
					hero = { kind = "carry", range = { 80, 160 }, text = "Fly a freed kid to safety" },
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Rush the copier cores to your fence",
					},
					lines = {
						{
							who = "halo",
							text = "Attention, students. We have intruders. Detention is now... permanent.",
						},
						{
							who = "lodestar",
							hero = "That workshop copies kids' Sparks. That's Crane's work. I'd bet my cape on it.",
							villain = "Crane's copier cores, in your hands. I don't like it. Just keep them away from kids.",
						},
					},
				},
				-- 7. The proof on every screen / the tuition safes
				{
					hero = {
						kind = "hold",
						seconds = 20,
						radius = 10,
						high = true,
						text = "Guard Patch's uplink on the roof",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 160 },
						guards = { "ShieldBearer", 1 },
						text = "Loot Halo's tuition safes",
					},
					lines = {
						{
							who = "patch",
							hero = "Uploading the workshop footage. Twenty seconds and every screen in the city sees it!",
							villain = "Halo's emptying his tuition safes before he runs. Beat him to them.",
						},
						{
							who = "wren",
							hero = "Everyone at school is watching the feed. They believe us now!",
							villain = "Everyone's watching the feed. Nobody's watching the safes. Clever.",
						},
					},
				},
				-- 8. The finale: Headmaster Halo on the academy steps
				{
					hero = {
						kind = "finale",
						enemy = "HeadmasterHalo",
						hpMult = 2,
						adds = { { "ShieldBearer", 2 }, { "SparkDrone", 2 } },
						range = { 60, 140 },
						text = "Crack Headmaster Halo's face. Class dismissed!",
						villainText = "Topple Headmaster Halo and take his school",
					},
					villain = "same",
					scene = "haloBell",
					lines = {
						{
							who = "halo",
							hero = "You think you can teach ME a lesson? Class is in session!",
							villain = "Thieves in my halls? You'll be graded on a curve. A FALLING curve!",
						},
					},
				},
			},
		},
	},

	-- Dev panel: one goal of every kind, built as a throwaway step (nothing saved) so each kind can be tried
	devKinds = {
		{ kind = "talk", text = "Kind test: talk" },
		{ kind = "fight", squads = { { "BurglarBot", 2 } }, range = { 40, 120 }, text = "Kind test: fight" },
		{ kind = "incident", count = 1, text = "Kind test: incident" },
		{ kind = "chase", enemy = "SneakBot", hops = 4, speed = 20, text = "Kind test: chase" },
		{ kind = "deliver", range = { 100, 200 }, text = "Kind test: deliver" },
		{ kind = "fetch", count = 2, range = { 80, 200 }, text = "Kind test: fetch" },
		{ kind = "hold", seconds = 6, radius = 10, text = "Kind test: hold" },
		{ kind = "escort", goal = 150, speed = 9, near = 40, text = "Kind test: escort" },
		{ kind = "carry", range = { 80, 160 }, text = "Kind test: carry" },
		{ kind = "race", checkpoints = 3, gap = 60, time = 40, text = "Kind test: race" },
		{ kind = "reach", high = 40, range = { 60, 200 }, text = "Kind test: reach" },
		{ kind = "find", range = { 100, 250 }, witness = true, text = "Kind test: find" },
		{ kind = "photo", count = 2, range = { 80, 200 }, text = "Kind test: photo" },
		{ kind = "beacon", seconds = 4, text = "Kind test: beacon" },
		{
			kind = "pocket",
			layout = "arena",
			minutes = 6,
			text = "Kind test: pocket",
			steps = {
				{ kind = "defeat", squads = { { "SparkDrone", 3 } }, text = "Kind test: beat the drones" },
			},
		},
		{ kind = "finale", enemy = "Captain", hpMult = 2, range = { 60, 150 }, text = "Kind test: finale" },
	},
}
