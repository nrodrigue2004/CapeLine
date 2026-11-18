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
-- * (lore step 11, chain 2) a step's `at`: the site (sites) its goals are built round (else the giver); a race
--   or chase goal's `course`: a rooftop course (courses) instead of rings in the air or nearby roofs; a
--   finale's `card` (its first villain's name card) and `encore` (a second villain who lands when the first
--   falls; the chain's `villain` card is the last one standing).
-- * (lore step 11, chain 4) Farmland sites on this week's outskirts tiles (sites with `farm` or `road`), and an
--   escort's `road`: the truck drives down a real farm road toward town (Shared.SideQuestSites.roadPath).
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
			-- The Gala Heist's costumed villains in their powered suits (lore step 11, chain 2)
			"Redline",
			"MasqueARade",
			"WindupGiant", -- the Toymaker's giant clockwork soldier (Wind-Up Lane)
			-- The Harvest King's chain (lore step 11, chain 4): his crop beast, then the King in his thresher suit
			"Bramblebeast",
			"HarvestKing",
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
		-- The Gala Heist (chain 2, nate's decisions 2026-11-17): both of Downtown's open squares, kept empty for
		-- this chain, hold its set pieces (Shared.SideQuestSets, built by SideQuestService): the City Museum's
		-- gala marquee with the opera's open-air stage in the north row's square, and Redline's racers' meet in
		-- the west column's. `square`: a Config.City.downtown.open id; `spot`: where the giver stands and the
		-- steps start, studs from the square's middle.
		Gala = {
			name = "THE MUSEUM GALA",
			district = "Downtown",
			square = "OpenNorth",
			set = "gala",
			spot = { 0, 34 },
		},
		MeetUp = {
			name = "THE RACERS' MEET",
			district = "Downtown",
			square = "OpenWest",
			set = "meet",
			spot = { 0, 10 },
		},
		-- nate: the bank job happens in Uptown (Crane Tower's district): an existing Uptown building near its
		-- landmark tower (`near` from the tower, at least away.landmark from it), so the escape runs over
		-- Uptown's roofs. A sign by its door like the academy's.
		Bank = {
			name = "BRIGHTHARBOR BANK",
			district = "Uptown",
			near = { 150, 0 },
			height = { 60, 170 },
			away = { landmark = 90 },
		},
		-- The Suburbs chain (Wind-Up Lane): Tick-Tock Toys, the Toymaker's shop, is an existing outskirts shop lot
		-- (a Suburbs tile's "shop", with its clapboard front, mailboxes and power poles around it). The outskirts
		-- are seeded weekly, so the pick is a rule (Shared.SideQuestSites.outskirts): of the shop lots on Suburbs
		-- tiles in `rings` (tiles out from the hub edge), the one nearest `near` (map studs, x and z) that keeps
		-- `away` studs from every safehouse pad, beacon, landmark, city district and other chain site. Same seed,
		-- same shop. Inside it is the "toyshop" pocket (Shared.PocketLayout).
		ToyShop = {
			name = "TICK-TOCK TOYS",
			district = "Suburbs",
			lot = "shop",
			near = { 1150, 450 }, -- east of the hub, between Eastfield and the Southmoor road
			rings = { 2, 5 },
			height = { 10, 20 }, -- a one-storey shop front
			away = { pad = 150, beacon = 150, landmark = 300, district = 200, site = 400 },
		},
		-- The Harvest King (chain 4, Farmland; nate's lore, build plan step 11): sites on the Farmland outskirts
		-- tiles, picked by rule from this week's seeded tiles (Shared.SideQuestSites.farm). `farm` names the lot:
		-- "barn" (a red clapboard barn; the way in is its front door), "silo" (a pair of grain silos) or "field"
		-- (a crop field); `road` (true) a spot on a farm road. Every pick is on a Farmland tile, `away` studs
		-- from each safehouse, beacon and landmark (the Crater's PvP square with it) and from the sites in
		-- `apart`: the one nearest `near` (studs from the map's middle, the hub's centre) within `reach`, or,
		-- with `from`, the one nearest that site inside `range`. `sign` false: no sign (the map marks it anyway).
		Homestead = {
			name = "FURROW FARM",
			district = "Farmland",
			farm = "barn",
			near = { 1700, 300 }, -- east of the hub, in the middle of the Farmland rings
			reach = 700,
			away = { safehouse = 160, beacon = 160, landmark = 450, site = 0 },
		},
		Fields = {
			name = "THE CORN FIELDS",
			district = "Farmland",
			farm = "field",
			from = "Homestead",
			range = { 90, 360 },
			sign = false,
			away = { safehouse = 120, beacon = 120, landmark = 450, site = 0 },
		},
		FarmRoad = {
			name = "THE FARM ROAD",
			district = "Farmland",
			road = true,
			from = "Homestead",
			range = { 0, 320 },
			sign = false,
			away = { safehouse = 120, beacon = 120, landmark = 450, site = 0 },
		},
		Silos = {
			name = "FURROW SILOS",
			district = "Farmland",
			farm = "silo",
			from = "Homestead",
			range = { 60, 450 },
			away = { safehouse = 120, beacon = 120, landmark = 450, site = 0 },
		},
		-- the Harvest King's own farm, further out toward the coast (never the giver's farm)
		KingsAcre = {
			name = "THE KING'S ACRE",
			district = "Farmland",
			farm = "barn",
			near = { 2000, 800 },
			reach = 700,
			apart = { "Homestead" },
			away = { safehouse = 160, beacon = 160, landmark = 450, site = 400 },
		},
	},

	-- Rooftop race courses (chain 2: Rooftop Racers over both skylines, nate): Shared.SideQuestSites.course
	-- picks `count` real roofs from the one nearest the `from` site (or the site's own roof), heading toward
	-- `toward` (a site, or studs from the start), every hop inside the 6-roof chase row's rules
	-- (Config.Story.opening.roofs: gap[1] apart at least, no rise past `climb`) and an edge-to-edge jump of at
	-- most `jump` (the row's rule, 75 studs centre to centre, on its narrowest 20-stud roofs: one Leap). Getting
	-- up onto the first roof takes your mobility pick (all five reach a roof: the doc's "powered races"); from
	-- there the base Leap runs the course. Each checkpoint is a ring over a roof.
	courses = {
		jump = 55,
		startNear = 170, -- the first roof is at most this far from the start site
		ringUp = 6, -- a checkpoint ring floats this far over its roof
		GalaRun = { from = "Gala", toward = "MeetUp", count = 7 }, -- the museum crew's getaway (Downtown)
		-- the opera runner's roofs (Downtown), none of the museum run's
		OperaRun = { from = "Gala", toward = { 420, 120 }, count = 5, avoid = { "GalaRun" } },
		BankRun = { from = "Bank", toward = { -60, -320 }, count = 7 }, -- the bank crew over Uptown
	},

	-- The set pieces in the open squares (Shared.SideQuestSets): their breakable pieces are combat targets that
	-- take about `hits` blows from a hero of `level` and come back after `rebuild` seconds. `parts`: the most
	-- parts one set may have (they stand all the time, on every device, so they count against the phone's
	-- budget); `clear`: studs kept free inside the square's ring of benches and planters.
	sets = { parts = 60, hits = 6, level = 15, rebuild = 45, clear = 3 },

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
		-- The Gala Heist's giver: the gala's valet, who parks the racers' cars too, so he has seen the masks and
		-- the getaway roofs. He wants the crew stopped before someone gets hurt (the Vigil), or a cut of the
		-- take for his tips (the Dread Syndicate).
		Benny = {
			name = "VALET BENNY",
			anchor = "site",
			site = "Gala",
			color = { 200, 40, 60 },
			style = "person",
			blip = "guideLodestar",
			portrait = {
				bg = { 90, 24, 36 },
				skin = { 160, 105, 70 },
				hair = { 30, 26, 24 },
				shape = "slick",
				extras = { "tie" },
			},
			look = {
				gender = 1,
				build = 2,
				height = 3,
				skin = 5,
				hair = 22, -- black
				colors = { 2, 4, 18 }, -- crimson, gold, white
				pieces = {
					shirt = "Blazer and Tie",
					pants = "Slacks",
					visage = "Hero Face",
					hair = "Side Part",
					beard = "Soul Patch",
					feet = "Boots",
					hands = "Gloves",
				},
				tints = {},
				mats = {},
			},
		},
		-- Wind-Up Lane's giver: Scoops, who drives the Suburbs' ice cream truck and parks outside Tick-Tock Toys every
		-- afternoon. She knows every kid on the street and has seen the toys walk. She wants the kids safe (the
		-- Vigil), or a cut of the Toymaker's gold clockwork with her truck as the getaway (the Dread Syndicate).
		Scoops = {
			name = "SCOOPS",
			anchor = "site",
			site = "ToyShop",
			color = { 240, 110, 190 },
			style = "person",
			blip = "guideInsider",
			portrait = {
				bg = { 90, 40, 70 },
				skin = { 160, 105, 70 },
				hair = { 80, 50, 30 },
				shape = "messy",
				extras = { "cap" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 3,
				skin = 5,
				hair = 39, -- chocolate
				colors = { 14, 31, 18 }, -- pink, mint, white
				pieces = {
					shirt = "Polo",
					pants = "Chinos",
					visage = "Rookie Face",
					hair = "Space Buns",
					hat = "Ball Cap",
					neck = "Kerchief",
					feet = "Boots",
				},
				tints = {},
				mats = {},
			},
		},
		-- The Harvest King's giver (chain 4, Farmland): the Harvest King's neighbour, whose corn field and tractor
		-- the beast ate. She wants the farms safe (the Vigil), or the King ruined and his seed vault emptied, she
		-- doesn't much care by whom (the Dread Syndicate).
		Dot = {
			name = "FARMER DOT",
			anchor = "site",
			site = "Homestead",
			color = { 120, 170, 70 },
			style = "person",
			blip = "guideLodestar",
			portrait = {
				bg = { 50, 80, 40 },
				skin = { 224, 172, 130 },
				hair = { 80, 50, 30 },
				shape = "messy",
				extras = { "strawhat" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 3,
				skin = 3,
				hair = 39, -- chocolate
				colors = { 29, 16, 5 }, -- olive, brown, cream
				pieces = {
					shirt = "Flannel Shirt",
					pants = "Denim Jeans",
					visage = "Hero Face",
					hair = "Braids",
					hat = "Wide Brim",
					neck = "Kerchief",
					hands = "Work Gloves",
					feet = "Boots",
				},
				tints = {},
				mats = {},
			},
		},
		-- PLACEHOLDER (Dev only): the framework sample's giver
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

		-- Downtown chain 2 (nate's lore, build plan step 11): The Gala Heist with Rooftop Racers. nate's pick: "A
		-- costumed crew hits the museum, the opera and the bank, and escapes each time by racing across the
		-- rooftops, so you chase them over the skyline." Villains Madame Masque-a-rade and Redline. 8 quests (the
		-- draft's count). Madame Masque-a-rade plans the jobs and leads the masked crew (the heist half); Redline
		-- runs the getaways over the roofs (the racers' half). Both fight in powered suits, so the fights are
		-- machines that spark apart (nate's rule: machine enemies). Standalone: not Crane's. The Vigil stop the
		-- robberies and chase the crew down; the Dread Syndicate rob the robbers and race them for the loot. Both
		-- face Redline, then Madame Masque-a-rade herself, at the racers' meet.
		{
			id = "GalaHeist",
			bit = 3,
			name = "The Gala Heist",
			layer = "district",
			district = "Downtown",
			giver = "Benny",
			site = "Gala",
			unlock = { story = 2, level = 5 }, -- after Act 1's Safehouse; level 5 for Uptown's floor (the bank)
			villain = { name = "MADAME MASQUE-A-RADE", title = "THE MASKED THIEF" },
			reward = { share = 3, title = "Curtain Call", style = "MasqueradeMask" },
			blurb = {
				hero = "A masked crew robs the city's grandest nights, then races off over the roofs.",
				villain = "A masked crew is robbing the city's richest nights. Rob them first.",
			},
			lines = {
				offer = {
					hero = "You look quick. Masked thieves hit the gala tonight and fled over the roofs. Help me stop them?",
					villain = "You look crooked. Good. A masked crew's robbing the gala. Rob them first and cut me in.",
				},
				resume = {
					hero = "Back? The masks are still out there. So are the racers.",
					villain = "Back for your cut? The crew's still loaded. Go take it.",
				},
				done = {
					hero = "Masks off, engines cold. The city sleeps easy tonight. Thanks, hero.",
					villain = "The crew's loot is yours and my tips are fat. Encore any time.",
				},
			},
			steps = {
				-- 1. Gala night: the museum's treasures under the marquee; Benny saw the masks
				{
					hero = { kind = "talk", text = "Meet Valet Benny at the Museum Gala" },
					villain = { kind = "talk", text = "Get Valet Benny's tip at the Museum Gala" },
					at = "Gala",
					scene = "galaNight",
					lines = {
						{
							who = "Benny",
							hero = "Masked guests, no invitations, and a racer idling on every roof. Tonight they rob the gala.",
							villain = "Masked crew, museum jewels, rooftop getaway. You want in before they cash out?",
						},
						{
							who = "patch",
							hero = "The City Museum's gala, the opera, and Brightharbor Bank all this week. Big targets.",
							villain = "Gala, opera, then the bank? Somebody's planned a whole heist season.",
						},
					},
				},
				-- 2. The museum job: the Vigil stop the crew; the Syndicate snatch the jewels first
				{
					hero = {
						kind = "fight",
						home = true,
						squads = { { "BurglarBot", 3 }, { "SneakBot", 2 } },
						text = "Stop the masked crew robbing the gala",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 30, 90 },
						guards = { "BurglarBot", 2 },
						text = "Snatch the museum's jewels before the crew",
					},
					at = "Gala",
					lines = {
						{
							who = "masque",
							hero = "Bonsoir, darlings! Do enjoy the show. My crew will be taking the jewels.",
							villain = "A rival in a cheap mask? How sweet. The jewels are spoken for, darling.",
						},
					},
				},
				-- 3. The first getaway: over Downtown's roofs toward the racers' meet
				{
					hero = {
						kind = "race",
						course = "GalaRun",
						checkpoints = 7,
						time = 80,
						text = "Chase the crew's racer over the rooftops",
						villainText = "Race the crew's runner to the loot drop",
					},
					villain = "same",
					at = "Gala",
					lines = {
						{
							who = "redline",
							text = "Catch me? On MY roofs? Cute. Every jump's a Leap. Try to keep up.",
						},
						{
							who = "patch",
							hero = "That racer is Redline. He runs the getaways. Follow the rings!",
							villain = "That racer is Redline, the crew's driver. Beat him to the drop!",
						},
					},
				},
				-- 4. Opera night on the gala stage: the Vigil shield the audience; the Syndicate find the stash
				{
					hero = {
						kind = "hold",
						home = true,
						seconds = 25,
						radius = 14,
						text = "Shield the opera's audience from the smoke bombs",
					},
					villain = {
						kind = "find",
						range = { 60, 160 },
						text = "Find where the crew stashed the opera loot",
					},
					at = "Gala",
					lines = {
						{
							who = "masque",
							text = "Tonight's aria is called Hand Over the Diamonds. Masks on, my darlings!",
						},
						{
							who = "Benny",
							hero = "Smoke on the stage! Keep the crowd calm. I'll get the doors.",
							villain = "The crew swapped the diva's diamonds while everyone watched the smoke. Find the stash!",
						},
					},
				},
				-- 5. The second getaway: catch the runner over the roofs
				{
					hero = {
						kind = "chase",
						course = "OperaRun",
						enemy = "SneakBot",
						hops = 5,
						speed = 24,
						text = "Catch the runner with the opera's diamonds",
						villainText = "Catch the runner and keep the diamonds",
					},
					villain = "same",
					at = "Gala",
					lines = {
						{
							who = "redline",
							hero = "My runner's faster than your whole team, hero. Bye now!",
							villain = "Stealing from thieves? Respect. You still won't catch my runner.",
						},
						{
							who = "lodestar",
							hero = "Rooftop crews always run the same line. Cut the corners, kid.",
							villain = "Stealing from thieves is still stealing. Just keep the civilians out of it.",
						},
					},
				},
				-- 6. The bank job in Uptown: the Vigil fly a teller out; the Syndicate crack the vault first
				{
					hero = {
						kind = "carry",
						range = { 60, 160 },
						text = "Fly a trapped teller out of the bank",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 30, 100 },
						guards = { "ShieldBearer", 1 },
						text = "Empty the vault before the crew does",
					},
					at = "Bank",
					scene = "bankJob",
					lines = {
						{
							who = "masque",
							text = "The grand finale: Brightharbor Bank! No encores. Well... maybe one.",
						},
						{
							who = "patch",
							hero = "They're in the bank, right under Crane Tower. Tellers are trapped inside!",
							villain = "The bank's vault is open and the crew's busy. Go, go, go!",
						},
					},
				},
				-- 7. The last getaway: over Uptown's skyline
				{
					hero = {
						kind = "race",
						course = "BankRun",
						checkpoints = 7,
						time = 80,
						text = "Chase the bank crew over Uptown's rooftops",
						villainText = "Beat the bank crew across Uptown's roofs",
					},
					villain = "same",
					at = "Bank",
					lines = {
						{
							who = "redline",
							text = "New skyline, same result. Last one to the meet buys the fuel!",
						},
						{
							who = "Benny",
							hero = "They always end up at the racers' meet. That's where they split the take.",
							villain = "Win this and the whole take's waiting at the racers' meet. Cut me in!",
						},
					},
				},
				-- 8. The finale at the racers' meet: Redline, then Madame Masque-a-rade herself
				{
					hero = {
						kind = "finale",
						enemy = "Redline",
						hpMult = 3,
						card = { name = "REDLINE", title = "KING OF THE ROOFTOPS" },
						adds = { { "BurglarBot", 2 }, { "SneakBot", 2 } },
						encore = { enemy = "MasqueARade", hpMult = 3, adds = { { "SneakBot", 2 } } },
						range = { 10, 40 },
						text = "Stop Redline, then Madame Masque-a-rade",
						villainText = "Beat Redline and Madame Masque-a-rade for the take",
					},
					villain = "same",
					at = "MeetUp",
					scene = "curtainCall",
					lines = {
						{
							who = "redline",
							hero = "End of the line, hero. Nobody passes Redline on the last lap!",
							villain = "Want the take? Win it. Last race, winner keeps everything!",
						},
						{
							who = "masque",
							text = "Bravo! Bravo! Now for my favourite part of the show. The curtain call!",
						},
					},
				},
			},
		},

		-- Suburbs chain (nate's lore, build plan step 11): Wind-Up Lane. nate's draft: "A powered kid's tantrums are
		-- bringing toys and lawn gnomes to life across the neighborhood. The Toymaker, an old inventor using the
		-- kid." 8 quests (the draft's count). Toby's Spark makes clockwork run when he is upset; the Toymaker, who
		-- runs Tick-Tock Toys, gave him a wind-up bear, keeps him crying and drinks the winding through a machine in
		-- his basement (the Tantrum Tap) to power a clockwork army. The Vigil stop the toys, find Toby, get the
		-- kids home, shield him inside the shop, smash the Tap and help him calm down; the Dread Syndicate grab
		-- the gold mainsprings, steal the basement key, fence the springs, rip out the Tap's gold and lift the
		-- blueprints. Both topple the Toymaker's giant at the end. Standalone: no Crane in it.
		{
			id = "WindUpLane",
			bit = 4,
			name = "Wind-Up Lane",
			layer = "district",
			district = "Suburbs",
			giver = "Scoops",
			site = "ToyShop",
			unlock = { story = 2, level = 5 }, -- after Act 1's Safehouse, at the Suburbs' level floor
			villain = { name = "THE TOYMAKER", title = "THE OLD INVENTOR" },
			reward = { share = 3, title = "Unwound", style = "ClockworkPack" },
			blurb = {
				hero = "Toys and lawn gnomes are coming alive in the Suburbs. A crying kid is always nearby.",
				villain = "An old toymaker found a way to power clockwork with a kid's Spark. Steal it all.",
			},
			lines = {
				offer = {
					hero = "Toys are walking on this street, hero. And every time, little Toby is crying nearby. Help?",
					villain = "The old toymaker's basement is full of gold clockwork. My truck's fast. Want in?",
				},
				resume = {
					hero = "Back again? The toys are still winding up out there. Let's go.",
					villain = "Back for more gold? The Toymaker's still got plenty.",
				},
				done = {
					hero = "Toby's laughing again and the gnomes are just gnomes. Ice cream's on me, hero.",
					villain = "Gold, blueprints and a whole toy army. And free ice cream. Best job ever.",
				},
			},
			steps = {
				-- 1. Afternoon on the Lane: Scoops's story outside Tick-Tock Toys
				{
					hero = { kind = "talk", text = "Hear Scoops out at Tick-Tock Toys" },
					villain = { kind = "talk", text = "Get Scoops's tip at Tick-Tock Toys" },
					scene = "tickTockLane",
					lines = {
						{
							who = "Scoops",
							hero = "Gnomes walking. Toy soldiers marching. And little Toby is always crying nearby. It's not right.",
							villain = "Tick-Tock Toys has a basement full of gold clockwork, and the old man is up to something.",
						},
						{
							who = "patch",
							hero = "Toys coming alive in the Suburbs? Okay. That's either a Spark or I need more sleep.",
							villain = "Clockwork that walks on its own? Somebody's going to sell that tech. Make it us.",
						},
					},
				},
				-- 2. The toy stampede / the gold mainsprings
				{
					hero = {
						kind = "fight",
						squads = { { "WindupToy", 6 } },
						range = { 60, 150 },
						text = "Stop the wind-up toys stampeding the street",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "WindupToy", 3 },
						text = "Grab the gold mainsprings from the toy crates",
					},
					lines = {
						{
							who = "patch",
							hero = "Tin soldiers, lawn gnomes and a plush bear with a bad attitude. Stop them before they reach the kids!",
							villain = "Every one of those toys runs on a gold mainspring. Actual gold! Grab the crates.",
						},
					},
				},
				-- 3. The boy who ran off / the runaway toy with the basement key
				{
					hero = {
						kind = "find",
						range = { 100, 250 },
						witness = true,
						text = "Find Toby, the boy who ran off crying",
					},
					villain = {
						kind = "chase",
						enemy = "WindupToy",
						hops = 5,
						speed = 20,
						text = "Catch the wind-up toy with the basement key",
					},
					lines = {
						{
							who = "Scoops",
							hero = "The Toymaker gave Toby another present, and it broke. Again. He ran off crying.",
							villain = "One of those toys carries the key to the Toymaker's basement. Don't let it get home!",
						},
						{
							who = "patch",
							hero = "Every time Toby cries, the toys wind up harder. Find him and the street calms down.",
							villain = "It hops when it's scared. Ha. Same as you when Lodestar shows up.",
						},
					},
				},
				-- 4. Toby's story begins; the kids home / fence the springs
				{
					hero = {
						kind = "escort",
						goal = 160,
						speed = 9,
						near = 40,
						text = "Get Scoops's truck of kids home safe",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Fence the gold mainsprings at the drop",
					},
					lines = {
						{
							who = "toby",
							hero = "I didn't mean to! When I get sad, the toys just... wake up. All of them.",
							villain = "Are you bad guys? You don't look like bad guys. You look like cool guys.",
						},
						{
							who = "lodestar",
							hero = "Toys are swarming the bus stop. Stay with that truck, kid. I'll watch the street.",
							villain = "Selling toy parts, are we? Fine. Just keep those things away from the kids.",
						},
					},
				},
				-- 5. Inside Tick-Tock Toys: the aisles, the playroom and the basement workshop under it
				{
					hero = {
						kind = "pocket",
						layout = "toyshop",
						minutes = 12,
						text = "Get inside Tick-Tock Toys",
						villainText = "Break into Tick-Tock Toys",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "WindupToy", 6 } },
								text = "Clear the toy soldiers from the aisles",
								villainText = "Scrap the toy guards in the aisles",
							},
							{
								kind = "hold",
								at = "playroom",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "WindupToy", 4 } },
								waveGap = 10,
								text = "Shield Toby in the playroom",
								villainText = "Hold the playroom while the till cracks",
							},
							{
								kind = "reach",
								at = "workshop",
								text = "Take the trapdoor under the counter",
								villainText = "Follow the trapdoor to the gold",
							},
							{
								kind = "break",
								list = "winders",
								points = 4,
								hits = 3,
								text = "Smash the Tantrum Tap's winders",
								villainText = "Rip the gold out of the Tantrum Tap",
							},
							{
								kind = "boss",
								enemy = "WindupToy",
								hpMult = 8,
								adds = { "WindupToy", 3 },
								text = "Beat the Toymaker's nutcracker captain",
								villainText = "Scrap the nutcracker captain for parts",
							},
						},
					},
					villain = "same",
					scene = "tobyStory",
					lines = {
						{
							who = "toby",
							hero = "He gave me a bear that winds up when I cry. Then he MAKES me cry. The machine is downstairs!",
							villain = "You want the gold? It's downstairs, in the crying machine. Break it too? Please?",
						},
					},
				},
				-- 6. Out of the shop: a scared kid / the springs to the truck; the Toymaker on his music box
				{
					hero = {
						kind = "carry",
						range = { 80, 160 },
						text = "Fly a scared kid out of the toy stampede",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Rush the gold springs to Scoops's truck",
					},
					lines = {
						{
							who = "toymaker",
							text = "Who's been stomping in my shop? Naughty, naughty! My toys will tuck you in!",
						},
						{
							who = "lodestar",
							hero = "A grown man making a kid cry for power. That's low. Even for this city.",
							villain = "That old man's machine runs on a kid's tears. Take his gold. Then end it.",
						},
					},
				},
				-- 7. Toby calms down / the Toymaker's blueprints
				{
					hero = {
						kind = "hold",
						seconds = 20,
						radius = 10,
						text = "Stay with Toby while he calms down",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 160 },
						guards = { "WindupToy", 2 },
						text = "Swipe the Toymaker's toy army blueprints",
					},
					lines = {
						{
							who = "toby",
							hero = "Deep breaths, like Mom says. In... and out. Hey, look! The gnomes stopped moving!",
							villain = "You took his drawings? Good. Then nobody can make me cry for a machine again.",
						},
						{
							who = "patch",
							hero = "It's working! Toby's calm and the toys are winding down all over the street!",
							villain = "Those blueprints show a toy army on every street in the city. Don't tell Toby.",
						},
					},
				},
				-- 8. The finale: the Toymaker winds up his giant himself
				{
					hero = {
						kind = "finale",
						enemy = "WindupGiant",
						hpMult = 3,
						adds = { { "WindupToy", 4 } },
						range = { 60, 140 },
						text = "Topple the Wind-Up Giant. Game over, Toymaker!",
						villainText = "Topple the Toymaker and take his toy army",
					},
					villain = "same",
					scene = "windupGiant",
					lines = {
						{
							who = "toymaker",
							hero = "You took my little power source? Then I'll wind up the BIG one myself!",
							villain = "Thieves in MY toy box? Time for a play date with my biggest toy!",
						},
					},
				},
			},
		},

		-- Farmland's chain (nate's lore, build plan step 11, chain 4): The Harvest King. nate's draft: "A giant
		-- beast born from a crop-growing power is eating the farms. The Harvest King, a farmer who won't let anyone
		-- hurt his creation." 8 quests (the draft's count). After three dry summers a farmer's Spark woke: anything
		-- he touches grows. He grew a guardian for his fields, the Bramblebeast, a giant of vines and pumpkins,
		-- and it never stops eating. He calls himself the Harvest King, rigs his old farm machines into scarecrow
		-- bots and drives everyone else off the land. The Vigil save the farm folk and the town's grain; the Dread
		-- Syndicate steal his prize crops and his Spark seeds. Both face the beast at his farm (a cartoon creature:
		-- it bursts into light and shrinks back to a seed), then the King himself in his thresher suit (a machine).
		-- Standalone: not Crane's.
		{
			id = "HarvestKing",
			bit = 5,
			name = "The Harvest King",
			layer = "district",
			district = "Farmland",
			giver = "Dot",
			site = "Homestead",
			unlock = { story = 2, level = 12 }, -- after Act 1's Safehouse; level 12, Farmland's floor
			villain = { name = "THE HARVEST KING", title = "LORD OF THE FIELDS" },
			reward = { share = 3, title = "Uprooted", style = "HarvestCrown" },
			blurb = {
				hero = "A farmer's Spark grew a giant crop beast, and now it's eating every farm in sight.",
				villain = "A farmer's Spark grows anything, even monsters. His seeds are worth a fortune.",
			},
			lines = {
				offer = {
					hero = "A hero? Thank goodness. Something big as a barn ate my corn last night. And my tractor.",
					villain = "You look like you'd steal anything. Good. My neighbour grows gold out there. Take it all.",
				},
				resume = {
					hero = "Back? The ground's still shaking out there. Let's go.",
					villain = "Back for the rest of his harvest? It's ripe for the picking.",
				},
				done = {
					hero = "The beast's a seed again and my corn's growing back. Thank you, hero.",
					villain = "The King's off his throne and my fields are safe. I won't ask where his seeds went.",
				},
			},
			steps = {
				-- 1. Dusk at Furrow Farm: the beast's shadow over the fields, Dot's story
				{
					hero = { kind = "talk", text = "Hear Farmer Dot out at Furrow Farm" },
					villain = { kind = "talk", text = "Get Farmer Dot's tip at Furrow Farm" },
					at = "Homestead",
					scene = "farmDusk",
					lines = {
						{
							who = "Dot",
							hero = "It came at dusk. Big as a barn, made of vines, and it ATE my corn. My neighbour grew it.",
							villain = "My neighbour calls himself the Harvest King. His Spark grows anything. Even monsters.",
						},
						{
							who = "patch",
							hero = "A Spark that grows crops? That's a new one. Whatever he grew, it's hungry.",
							villain = "A Spark that grows anything? Giant pumpkins sell for a LOT. Just saying.",
						},
					},
				},
				-- 2. The beast's trail: the Vigil find the farmhand who saw it; the Syndicate grab the prize crops
				{
					hero = {
						kind = "find",
						range = { 30, 120 },
						witness = true,
						text = "Find the farmhand who saw the beast",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 30, 120 },
						guards = { "BurglarBot", 2 },
						text = "Grab the Harvest King's prize pumpkins",
					},
					at = "Fields",
					lines = {
						{
							who = "harvest",
							text = "Off my land! Every row out here belongs to the Harvest King!",
						},
						{
							who = "patch",
							hero = "A farmhand ran into the corn when it hit. Find him before it comes back!",
							villain = "Those prize pumpkins win every fair in the state. His scarecrow bots guard them.",
						},
					},
				},
				-- 3. Down the farm road: the Vigil get the farm folk to town; the Syndicate catch the seed runner
				{
					hero = {
						kind = "escort",
						road = true,
						goal = 160,
						speed = 9,
						near = 40,
						text = "Get the farm folk's truck down the road to town",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the King's seed runner bot",
					},
					at = "FarmRoad",
					lines = {
						{
							who = "lodestar",
							hero = "Farm folk are leaving with what's left. Keep that truck rolling. I'll watch the fields.",
							villain = "That runner carries the King's seeds. Take them if you must. Leave the farm folk be.",
						},
						{
							who = "patch",
							hero = "The beast's tracks cross the farm road. Stay with the truck!",
							villain = "His seed runner bot is making for the road. Grab its seed pouch!",
						},
					},
				},
				-- 4. The scarecrow bots raid Dot's farm / sell the haul
				{
					hero = {
						kind = "fight",
						home = true,
						squads = { { "BurglarBot", 3 }, { "BruteBot", 1 } },
						text = "Scrap the scarecrow bots raiding Furrow Farm",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Sell the pumpkins and seeds at the crossroads",
					},
					at = "Homestead",
					lines = {
						{
							who = "harvest",
							text = "My scarecrow bots will see you off. Nobody touches the King's crops!",
						},
						{
							who = "Dot",
							hero = "They're in my yard! He wants every last farmer gone!",
							villain = "Buyer's waiting at the crossroads. Sell fast, before the King finds out.",
						},
					},
				},
				-- 5. The silo yard: the Vigil free a farmer from the vines; the Syndicate crack the seed vault.
				-- The Harvest King's comic page: how the drought woke his Spark.
				{
					hero = {
						kind = "carry",
						range = { 60, 160 },
						text = "Fly a farmer out of the beast's vines",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 20, 90 },
						guards = { "ShieldBearer", 1 },
						text = "Crack the King's silo vault for his Spark seeds",
					},
					at = "Silos",
					scene = "kingStory",
					lines = {
						{
							who = "harvest",
							text = "You don't understand! It's only hungry. I grew it to SAVE these farms!",
						},
						{
							who = "patch",
							hero = "Vines all over the silo yard, and somebody's caught in them. Fly him out!",
							villain = "His seed vault's in the silos. Those seeds would grow anything we wanted.",
						},
					},
				},
				-- 6. The town's last silo: the Vigil hold off the beast; the Syndicate run the seeds to a fence
				{
					hero = {
						kind = "hold",
						home = true,
						seconds = 25,
						radius = 14,
						text = "Shield the town's last silo from the beast",
					},
					villain = {
						kind = "race",
						checkpoints = 5,
						gap = 60,
						time = 50,
						text = "Run the stolen seeds over the fields to your fence",
					},
					at = "Silos",
					lines = {
						{
							who = "Dot",
							hero = "That silo feeds half the city this winter. Don't let it get eaten!",
							villain = "The beast's busy with the silo. Run the seeds now, while nobody's looking!",
						},
						{
							who = "lodestar",
							hero = "That's a living creature, kid, not a robot. Hold it off. It doesn't know any better.",
							villain = "That thing's alive, not some robot. Get your seeds and stay out of its way.",
						},
					},
				},
				-- 7. The King's Acre: the Vigil get his bots on camera; the Syndicate wreck his harvester rigs
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 40, 140 },
						text = "Photograph the King's bots wrecking farms",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 40, 140 },
						guards = { "BruteBot", 1 },
						text = "Steal the fuel cells from his harvester rigs",
					},
					at = "KingsAcre",
					lines = {
						{
							who = "patch",
							hero = "The news says the farms just had a bad year. Get proof on camera!",
							villain = "No fuel, no harvester rigs. Pull the cells and his bots stop dead in the rows!",
						},
						{
							who = "harvest",
							text = "Thieves AND snoops on my acre? My beauty will deal with the lot of you!",
						},
					},
				},
				-- 8. The finale at the King's Acre: the Bramblebeast, then the Harvest King himself
				{
					hero = {
						kind = "finale",
						enemy = "Bramblebeast",
						hpMult = 2,
						card = { name = "THE BRAMBLEBEAST", title = "THE HUNGRY HARVEST" },
						adds = { { "BurglarBot", 2 } },
						encore = { enemy = "HarvestKing", hpMult = 3, adds = { { "BruteBot", 1 } } },
						range = { 20, 60 },
						text = "Calm the Bramblebeast, then topple the Harvest King",
						villainText = "Beat the Bramblebeast and rob the Harvest King",
					},
					villain = "same",
					at = "KingsAcre",
					scene = "kingsHarvest",
					lines = {
						{
							who = "harvest",
							hero = "Wake up, my beauty! Supper's here, and it brought a hero!",
							villain = "Wake up, my beauty! Supper's here, and it brought thieves!",
						},
						{
							who = "Dot",
							hero = "Careful! Hurt that beast and he'll come for you himself.",
							villain = "Beat his beast and he'll come out to fight. Then his vault's wide open.",
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
