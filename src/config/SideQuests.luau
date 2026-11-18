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
-- * (lore step 11, chain 6) Old Quarry sites on the landmark itself (sites with `quarry`: its gate, or an open
--   spot on its floor; Shared.SideQuestSites.quarry), and a finale villain's `dress` (dress: a fixed look, name
--   and title worn over an existing costumed villain's suit, so a chain needs no robot type of its own).
-- * (lore step 11, the Underwater chain) deep sites on the sea floor (sites with `deep`, picked from
--   Shared.DeepLayout): a chain at a deep site builds its goals in the open water round it (`deep` below lists
--   the kinds that work there), and a finale's dress may go over a plain sea robot (dress `robot`).
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
			"CaptainBrine", -- the Coast chain's pirate captain in his powered diving rig (The Salt Dogs)
			-- the Underwater chain (The Sunken City): the sea's heavy seabed brute, in the Tidewright's dress
			"Anchor",
		},
	},
	-- Goals at a deep site (lore step 11, the Underwater chain): built in the open water round it
	-- (Shared.SideQuestSites.deepSpot and deepPath), never on the streets. `kinds`: the step kinds that work
	-- under the sea (no trucks, roofs, beacons, incidents or Sneak Bot photos); `arena`: studs every goal keeps
	-- from the Leviathan Engine's arena; `lift`: a swim's rings and legs sit this share of the way up from the
	-- seabed to the surface.
	deep = {
		kinds = {
			"talk",
			"fight",
			"fetch",
			"hold",
			"carry",
			"race",
			"reach",
			"deliver",
			"find",
			"chase",
			"pocket",
			"finale",
		},
		areas = { "shelf" }, -- where a deep site may be (the Coral Shelf: its zone floor is the chain's)
		arena = 60,
		lift = 0.5,
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
		-- The Coast chain (The Salt Dogs): Gull Point Pier, the old ferry pier Captain Brine's crew raids, is an
		-- existing coast tile's pier (Shared.WorldGen.COAST: a "pier" tile on the map's edge ring runs its deck
		-- out over the sea, with the harbour hut at its end). The coast is seeded weekly too, so the pick is a rule
		-- (Shared.SideQuestSites.outskirts with `shore`): of the coast tiles with that feature in `rings`, the one
		-- nearest `near` (map studs) that keeps `away` studs from every safehouse pad, beacon, landmark, city
		-- district and other chain site. The giver stands on the sand at the pier's foot. The west shore: far from
		-- the Docks (the Syndicate's Foundry and the Spark crystal raid) and the south sea (the Coral Shelf, the
		-- Trench). Inside Brine's sea cave is the "seacave" pocket (Shared.PocketLayout).
		GullPier = {
			name = "GULL POINT PIER",
			district = "Coast",
			shore = "pier",
			near = { -2350, 450 }, -- the west shore, south of Radio Hill
			rings = { 16, 16 }, -- piers stand on the edge ring only (their deck runs out over the sea)
			away = { pad = 150, beacon = 150, landmark = 300, district = 200, site = 400 },
		},
		-- The Underwater chain (The Sunken City): three spots on the Coral Shelf's sea floor, picked by rule from
		-- Shared.DeepLayout (Shared.SideQuestSites.deep; the underwater world is fixed, so they never move): on a
		-- `grid` within `reach` of `near` (map studs), the seabed spot nearest it in the `deep` area with water
		-- `depth` studs deep, `away`.edge from the area's sides and clear of every sunken cache, Sunken Line
		-- rescue, the Leviathan Engine's arena (past its edge), every reef, kelp stand and wreck, and the other deep
		-- sites. West of the Trench, away from the Leviathan Engine; the shelf's zone floor (12) is the chain's.
		-- Doc Pearl's reef station in the shallows off the south beach, where the giver stands
		ReefStation = {
			name = "REEF STATION",
			district = "Underwater",
			deep = "shelf",
			near = { -760, 2470 },
			reach = 400,
			grid = 8,
			depth = { 8, 14 }, -- the shallows: the first band off the beach
			away = { cache = 90, rescue = 90, arena = 200, reef = 14, edge = 30, site = 0 },
		},
		-- the drowned gate where the shelf drops away, Velmara's way in (the "velmara" pocket)
		DrownedGate = {
			name = "THE DROWNED GATE",
			district = "Underwater",
			deep = "shelf",
			near = { -620, 2930 },
			reach = 400,
			grid = 8,
			depth = { 36, 46 }, -- the shelf's deepest band, over the city
			away = { cache = 90, rescue = 90, arena = 200, reef = 14, edge = 30, site = 300 },
		},
		-- the tide engine's spire east along the drop, where the Tidewright rises for the finale
		TideSpire = {
			name = "THE TIDE SPIRE",
			district = "Underwater",
			deep = "shelf",
			near = { -1080, 2850 },
			reach = 400,
			grid = 8,
			depth = { 28, 46 },
			away = { cache = 90, rescue = 90, arena = 200, reef = 14, edge = 30, site = 300 },
		},
		-- The Pit (chain 6, the Old Quarry; nate's lore, build plan step 11): spots on the Old Quarry landmark
		-- itself, read from its own boxes (Shared.SideQuestSites.quarry; the landmark is hand-placed, so the spots
		-- never move with the weekly seed). `quarry` "gate": the gap in its north wall, the way in from town;
		-- "floor": of the open floor points `clear` studs from every wall, terrace and boulder, the one nearest
		-- `spot` (studs from the quarry's middle, x east and z south). The fight club itself is underground: the
		-- "pit" pocket (Shared.PocketLayout), reached by the old mine lift.
		QuarryGate = {
			name = "THE OLD QUARRY",
			district = "OldQuarry",
			quarry = "gate",
		},
		MineLift = {
			name = "THE MINE LIFT",
			district = "OldQuarry",
			quarry = "floor",
			spot = { -60, -110 }, -- the floor's north-west corner, inside the gate, clear of the boulders
			clear = 10,
		},
		QuarryRing = {
			name = "THE QUARRY FLOOR",
			district = "OldQuarry",
			quarry = "floor",
			spot = { 0, 75 }, -- south of the boulders, in front of the terraces (the crowd's seats)
			clear = 14,
			sign = false,
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

	-- Finale dresses (lore step 11, chain 6): a chain villain who needs no robot type of their own (Enemy.Delta
	-- packs a type in 5 bits and all 32 are used): the finale's `enemy` is an existing costumed villain's
	-- powered suit (Config.Enemies, fake.costumed) for its fighting brain and numbers, and `dress` names a row
	-- here: the fixed creator look it wears (earnable pieces, Shared.FakeRules.lookFrom, validated by
	-- CreatorRules), the name and title on its plate, `creature` (false: a machine that sparks apart) and `body`
	-- (the robot colours under the costume: metal, eye, suit, trim). EnemyService.dress sends it as the robot's
	-- EnemyIdentity, the evil twin's wire, so every device draws it. Lore step 11, the Underwater chain: `robot`
	-- puts a dress over a plain finale robot instead (no costumed suit swims), drawn like a costumed villain
	-- (never cracks or reads FAKE) in its `path`'s look; `height` (studs) and `trident` change its drawing and
	-- `dmgMult` (1 to 2) lifts its damage into the boss-lite band.
	dress = {
		-- The Pit's finale (chain 6): the Pitboss in his powered prize-fighter rig, a big stone-skinned showman
		-- in a maroon tuxedo, top hat and iron boxing gloves, wearing his own title belt. The suit and brain are
		-- the Bramblebeast's (Bulwark's brute numbers without the shield: slams, a shockwave stomp, a charge),
		-- as a machine: no light burst, it sparks apart like the other costumed villains.
		Pitboss = {
			name = "The Pitboss",
			title = "Head of the Gravel Family",
			creature = false,
			body = {
				metal = { 120, 125, 135 },
				eye = { 255, 90, 60 },
				suit = { 110, 20, 25 },
				trim = { 240, 196, 64 },
			},
			look = {
				gender = 1,
				build = 4, -- Titan: the suit's build (the Bramblebeast's titan frame)
				height = 5,
				skin = 25, -- Stone: his Spark turned his skin to quarry stone
				hair = 22, -- black
				colors = { 38, 4, 22 }, -- maroon, gold, black
				pieces = {
					suit = "Tuxedo",
					hat = "Top Hat",
					hands = "Boxing Gloves",
					shoulders = "Riveted Pads",
					belt = "Champion Belt",
					beard = "Handlebar",
					hair = "Slicked Back",
					visage = "Scarred Face",
					neck = "Chain",
					feet = "Armored Boots",
				},
				tints = { hat = { 22, 38, 0 } }, -- a black top hat with a maroon band
				mats = { hands = "Metal", shoulders = "Metal" }, -- iron gloves and riveted pads: the rig
			},
		},
		-- The Sunken City's finale (the Underwater chain): the Tidewright, Velmara's last guardian, an ancient
		-- machine of bronze and coral. No costumed suit swims, so his dress goes over the sea's heavy seabed brute
		-- (`robot`: the Anchor's brain, health and slam, kept in the water), drawn like a costumed villain (never
		-- cracks or reads FAKE) in the Tide path's look, 9 studs tall with a trident (PLACEHOLDER ART), his
		-- damage lifted into the boss-lite band.
		Tidewright = {
			name = "The Tidewright",
			title = "Last Guardian of Velmara",
			creature = false,
			robot = true,
			path = "Tide",
			height = 9,
			trident = true,
			dmgMult = 1.6,
			body = {
				metal = { 170, 120, 70 },
				eye = { 120, 255, 230 },
				suit = { 30, 110, 120 },
				trim = { 190, 140, 60 },
			},
			look = {
				gender = 1,
				build = 3, -- Heavy: an ancient guardian machine
				height = 5,
				skin = 26, -- the Metal skin: no person inside, a machine all through
				hair = 31, -- sea foam
				colors = { 32, 27, 31 }, -- deep teal, bronze, sea foam
				pieces = {
					suit = "Plated Suit",
					back = "Long Cape",
					hat = "Iron Crown",
					hands = "Armored Gauntlets",
					feet = "Armored Boots",
					shoulders = "Shell Pads",
					arms = "Scale Guards",
					ears = "Fin Ears",
					eyes = "Ice Glow",
					emblem = "Orb Crest",
					hair = "Long Straight",
					beard = "Full Beard",
					visage = "Stern Face",
				},
				tints = { back = { 31, 27, 0 } }, -- a sea-foam cape with bronze trim
				mats = { suit = "Metal" },
			},
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
		-- The Salt Dogs' giver: Skipper Nell, who has run the Gull Point ferry for forty years. Captain Brine's crew
		-- raided her ferry and carried off her deckhand grandson Finn. She wants Finn home and the ghost ship
		-- stopped (the Vigil), or Brine's treasure split two ways with her ferry as the getaway boat (the Dread
		-- Syndicate).
		Nell = {
			name = "SKIPPER NELL",
			anchor = "site",
			site = "GullPier",
			color = { 90, 170, 220 },
			style = "person",
			blip = "guideInsider",
			portrait = {
				bg = { 30, 60, 90 },
				skin = { 198, 140, 100 },
				hair = { 225, 225, 230 },
				shape = "slick",
				extras = { "cap", "scar" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 2,
				skin = 4,
				hair = 40, -- bone white
				colors = { 11, 18, 1 }, -- navy, white, red
				pieces = {
					shirt = "Knit Sweater",
					pants = "Cargo Trousers",
					visage = "Stern Face",
					hair = "Braids",
					hat = "Beanie",
					neck = "Whistle",
					back = "Field Coat",
					feet = "Boots",
				},
				tints = {},
				mats = {},
			},
		},
		-- The Sunken City's giver: Doc Pearl, the marine biologist who runs the Reef Station on the Coral Shelf. She
		-- heard the reef hum, then saw Velmara's lights come on. She wants the coast safe and the guardian
		-- stopped (the Vigil), or she will trade her maps of the drowned city's vaults for a cut of its gold to
		-- fund her station (the Dread Syndicate). She stands on the sea floor in her dive gear.
		Pearl = {
			name = "DOC PEARL",
			anchor = "site",
			site = "ReefStation",
			color = { 60, 200, 220 },
			style = "person",
			blip = "guideInsider",
			portrait = {
				bg = { 20, 70, 100 },
				skin = { 120, 80, 55 },
				hair = { 30, 26, 24 },
				shape = "messy",
				extras = { "goggles" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 3,
				skin = 6,
				hair = 22, -- black
				colors = { 8, 26, 18 }, -- teal, peach, white
				pieces = {
					suit = "Wetsuit",
					hat = "Flight Goggles",
					backpack = "Air Tanks",
					feet = "Flippers",
					hands = "Gloves",
					hair = "Curly Top",
					visage = "Hero Face",
				},
				tints = {},
				mats = {},
			},
		},
		-- PLACEHOLDER (Dev only): the framework sample's giver
		-- The Pit's giver (chain 6, the Old Quarry): Brick, the Pit's old champion, who would not throw a fight
		-- and now walks the quarry at night as its watchman. He wants the young fighters out and the Pit shut (the
		-- Vigil), or every purse the Pitboss cheated him out of back from the family's vault (the Dread Syndicate).
		Brick = {
			name = "BRICK",
			anchor = "site",
			site = "QuarryGate",
			color = { 200, 70, 60 },
			style = "person",
			blip = "guideLodestar",
			portrait = {
				bg = { 60, 62, 70 },
				skin = { 120, 78, 52 },
				hair = { 175, 180, 190 },
				shape = "messy",
				extras = { "beard", "bandage" },
			},
			look = {
				gender = 1,
				build = 3,
				height = 4,
				skin = 6,
				hair = 19, -- silver
				colors = { 43, 1, 18 }, -- slate, red, white
				pieces = {
					shirt = "Tank",
					pants = "Track Bottoms",
					visage = "Stern Face",
					hair = "Buzz Cut",
					beard = "Boxed Beard",
					hat = "Beanie",
					hands = "Hand Wraps",
					neck = "Whistle",
					feet = "High Tops",
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

		-- Coast chain (nate's lore, build plan step 11): The Salt Dogs. nate's draft: "Powered pirates raid ships
		-- and hide treasure in sea caves. Captain Brine and the Salt Dogs crew." 8 quests (the draft's count).
		-- Captain Brine was a salvage diver whose Spark woke in the deep: he moves the tide. He fights in a powered
		-- brass diving rig and crews his ship with the Salt Dogs, old diving robots he patched up into pirates
		-- (machines only). His "ghost ship" is a hologram projected off his mast so sailors panic and jump ship;
		-- the plunder goes to his sea cave. The Vigil push the raiders off the pier, find the ferry's mate, get
		-- the crew to safety, free Nell's grandson Finn from the cave, expose the ghost ship and guard the beach
		-- while the ferries run; the Dread Syndicate grab the raided cargo, steal Brine's map, fence the haul, rob
		-- his vault, run off with the ghost lights' crystals and dig up his buried caches. Both sink Brine at the
		-- end. Standalone: no Crane in it.
		{
			id = "SaltDogs",
			bit = 6,
			name = "The Salt Dogs",
			layer = "district",
			district = "Coast",
			giver = "Nell",
			site = "GullPier",
			unlock = { story = 2, level = 20 }, -- after Act 1's Safehouse, at the coast's level floor
			villain = { name = "CAPTAIN BRINE", title = "CAPTAIN OF THE SALT DOGS" },
			reward = { share = 3, title = "Brinebreaker", style = "TatteredSail" },
			blurb = {
				hero = "Robot pirates raid the ferries and a ghost ship sails out of the fog. A deckhand is gone.",
				villain = "Captain Brine hides his plunder in a sea cave. A pirate's treasure, waiting for a thief.",
			},
			lines = {
				offer = {
					hero = "The Salt Dogs raided my ferry and took my grandson Finn. Every sailor's too scared to help. Will you?",
					villain = "Brine's sea cave is full of other folks' plunder. My ferry's fast. Split it with me?",
				},
				resume = {
					hero = "Back on the pier? Good. The tide won't wait, and neither will Finn.",
					villain = "Back for the treasure? Brine hasn't moved it yet. Let's go.",
				},
				done = {
					hero = "Finn's home, the ghost ship's a light show and Brine's rig is scrap. Free ferry rides, forever.",
					villain = "Pirate gold, ghost lights and a sunk captain. You'd make a fine pirate. Don't tell Finn.",
				},
			},
			steps = {
				-- 1. Fog on Gull Point: Nell's story at the pier
				{
					hero = { kind = "talk", text = "Hear Skipper Nell out at Gull Point Pier" },
					villain = { kind = "talk", text = "Get Skipper Nell's tip at Gull Point Pier" },
					scene = "gullPoint",
					lines = {
						{
							who = "Nell",
							hero = "A ghost ship rolls out of the fog, and the Salt Dogs strip my ferry bare. Last night they took Finn.",
							villain = "Captain Brine stashes every raided crate in his sea cave. I know which cave. You've got the muscle.",
						},
						{
							who = "patch",
							hero = "A ghost ship? Ghosts don't show up on radar, and this one does. Something very solid is out there.",
							villain = "Pirates with a robot crew and a cave full of loot? Honestly the best tip all week.",
						},
					},
				},
				-- 2. The raid on the pier / the raided cargo
				{
					hero = {
						kind = "fight",
						squads = { { "SaltDog", 6 } },
						range = { 60, 150 },
						text = "Fight off the Salt Dogs raiding the pier",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "SaltDog", 3 },
						text = "Grab the raided cargo before the Salt Dogs do",
					},
					lines = {
						{
							who = "patch",
							hero = "Salt Dogs: old diving robots patched up as pirates. Hooks, bandanas, zero manners. Push them back!",
							villain = "Those crates came off Nell's ferry. Grab them before the robot pirates haul them out to sea.",
						},
					},
				},
				-- 3. The mate who swam ashore / the robot with Brine's map
				{
					hero = {
						kind = "find",
						range = { 100, 250 },
						witness = true,
						text = "Find the ferry's mate who swam ashore",
					},
					villain = {
						kind = "chase",
						enemy = "SaltDog",
						hops = 5,
						speed = 20,
						text = "Catch the Salt Dog carrying Brine's map",
					},
					lines = {
						{
							who = "Nell",
							hero = "My mate Rook jumped overboard when they boarded. He swam for the dunes. Find him, please.",
							villain = "One of those tin sailors carries Brine's treasure map. Don't let it reach the water!",
						},
						{
							who = "lodestar",
							hero = "Cold water, long swim. Check the dunes and the driftwood first, kid.",
							villain = "A map to a pirate's treasure. Of course that's the part you heard.",
						},
					},
				},
				-- 4. Brine on his loudhailer; the ferry crew to safety / fence the haul
				{
					hero = {
						kind = "escort",
						goal = 160,
						speed = 9,
						near = 40,
						text = "Get the ferry crew's van to the coast road",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Fence the raided cargo at the drop",
					},
					lines = {
						{
							who = "brine",
							text = "Ahoy, landlubbers! Every crate on this coast belongs to Captain Brine. Hands off my plunder!",
						},
						{
							who = "patch",
							hero = "That voice is coming off a buoy speaker. Classic pirate move: yell from very far away.",
							villain = "The fence pays double for anything with Brine's mark on it. Pirates have a brand. Who knew?",
						},
					},
				},
				-- 5. Inside Brine's sea cave: the tide pools, the wharf and the hidden grotto under it
				{
					hero = {
						kind = "pocket",
						layout = "seacave",
						minutes = 12,
						text = "Sneak into Brine's sea cave",
						villainText = "Raid Brine's treasure cave",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "SaltDog", 6 } },
								text = "Clear the Salt Dogs from the tide pools",
								villainText = "Scrap the Salt Dog lookouts",
							},
							{
								kind = "hold",
								at = "wharf",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "SaltDog", 4 } },
								waveGap = 10,
								text = "Guard Finn on the wharf while Patch frees him",
								villainText = "Hold the wharf while the vault lock drills",
							},
							{
								kind = "reach",
								at = "grotto",
								text = "Climb down to Brine's hidden grotto",
								villainText = "Follow the rock steps down to the treasure",
							},
							{
								kind = "break",
								list = "projectors",
								points = 4,
								hits = 3,
								text = "Smash the ghost ship's hologram projectors",
								villainText = "Rip the crystals out of the ghost projectors",
							},
							{
								kind = "boss",
								enemy = "SaltDog",
								hpMult = 8,
								adds = { "SaltDog", 3 },
								text = "Beat the Salt Dogs' iron bosun",
								villainText = "Scrap the iron bosun for parts",
							},
						},
					},
					villain = "same",
					scene = "brineLegend",
					lines = {
						{
							who = "Nell",
							hero = "Finn's in that cave, I can hear him banging on a cage. Hold on, Finn. Help's coming.",
							villain = "Brine's vault is at the back of the cave. Finn's in there too. Grab him on the way out?",
						},
					},
				},
				-- 6. Out of the cave: Finn home / the ghost lights' crystals; Finn tells the ghost ship's secret
				{
					hero = {
						kind = "carry",
						range = { 80, 160 },
						text = "Fly Finn to the lifeboat station",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Race the stolen crystals past the tide",
					},
					lines = {
						{
							who = "finn",
							hero = "The ghost ship? It's just lights! Brine shines it off his mast so sailors panic and jump ship.",
							villain = "You smashed his ghost lights? Brine's going to be SO mad. Can I watch? From really far away?",
						},
						{
							who = "brine",
							text = "My ghost lights! My beautiful ghost lights! You'll be swimming with the crabs for that!",
						},
					},
				},
				-- 7. The ferries run for harbour / Brine's buried caches
				{
					hero = {
						kind = "hold",
						seconds = 20,
						radius = 10,
						text = "Hold the beach while the ferries get clear",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 160 },
						guards = { "SaltDog", 2 },
						text = "Dig up Brine's buried treasure caches",
					},
					lines = {
						{
							who = "Nell",
							hero = "Every ferry on this coast is running for harbour. Keep the Salt Dogs off the beach till they're clear!",
							villain = "Brine buries the best stuff in the sand. Three X marks. The man really commits to the bit.",
						},
						{
							who = "lodestar",
							hero = "The tide's turning. When Brine comes, he comes in with it. Be ready.",
							villain = "You're robbing a pirate. Just remember who taught you to watch your back.",
						},
					},
				},
				-- 8. The finale: Captain Brine rides the tide in, in his powered diving rig
				{
					hero = {
						kind = "finale",
						enemy = "CaptainBrine",
						hpMult = 3,
						adds = { { "SaltDog", 4 } },
						range = { 60, 140 },
						text = "Sink Captain Brine's powered diving rig",
						villainText = "Take down Captain Brine and claim his hoard",
					},
					villain = "same",
					scene = "brineRig",
					lines = {
						{
							who = "brine",
							hero = "You freed my prisoner AND broke my ghost? Then face the real thing: Captain Brine himself!",
							villain = "Thieves robbing a pirate? Bold! Now taste the tide, you barnacles!",
						},
					},
				},
			},
		},

		-- The Old Quarry's chain (nate's lore, build plan step 11, chain 6): The Pit. nate's draft: "An underground
		-- fight club for powered brawlers, run by a crime family. The Pitboss." 8 quests (the draft's count). When
		-- the Old Quarry closed, the Gravel family kept the mine tunnels under it and dug the Pit: a ring where
		-- powered fighters brawl for the crowd's bets. The family's eldest, the Pitboss, has a Spark that turned
		-- his skin to quarry stone; he never loses, the fights are rigged, and a fighter who loses owes the family
		-- and must fight again. The Vigil get the young fighters out, get the family's bouncer bots on camera and
		-- smash the rigged odds machines; the Dread Syndicate rob the collectors, steal the betting book, crack the
		-- odds machines and empty the family's vault. Both beat the Pitboss in his powered prize-fighter rig on the
		-- quarry floor (a machine: Config.SideQuests.dress over an existing costumed suit, so no new robot type).
		{
			id = "ThePit",
			bit = 7,
			name = "The Pit",
			layer = "district",
			district = "OldQuarry",
			giver = "Brick",
			site = "QuarryGate",
			unlock = { story = 2, level = 20 }, -- after Act 1's Safehouse, at the Old Quarry's level floor
			villain = { name = "THE PITBOSS", title = "HEAD OF THE GRAVEL FAMILY" },
			reward = { share = 3, title = "Undisputed", style = "UndisputedBelt" },
			blurb = {
				hero = "A crime family runs a fight club under the Old Quarry. Its young fighters can never leave.",
				villain = "A crime family runs a fight club under the Old Quarry. All those bets go to one vault.",
			},
			lines = {
				offer = {
					hero = "There's a fight club under this quarry, hero. Kids with Sparks fight for a crime family. They never get out.",
					villain = "The Pitboss cheated me out of every purse I ever won. His vault's under that quarry. Want half?",
				},
				resume = {
					hero = "Back at the gate? Good. The Pit's still open tonight. Let's shut it for good.",
					villain = "Back for the Pitboss's money? It's still down there. Let's go get it.",
				},
				done = {
					hero = "The Pit's shut and every fighter walked out free. Nobody owes the Gravels a thing now. Thank you.",
					villain = "The Pitboss is flat on the canvas and his vault is empty. Pleasure doing business, champ.",
				},
			},
			steps = {
				-- 1. Night at the Old Quarry: the Pit's crowd roars under the floor; Brick's story at the gate
				{
					hero = { kind = "talk", text = "Hear Brick out at the Old Quarry gate" },
					villain = { kind = "talk", text = "Get Brick's tip at the Old Quarry gate" },
					at = "QuarryGate",
					scene = "quarryNight",
					lines = {
						{
							who = "Brick",
							hero = "Every night they fight down there. Kids with Sparks, owing the family money they can never pay back.",
							villain = "The Gravel family runs the Pit, and the Pitboss runs the family. Every bet ends up in his vault.",
						},
						{
							who = "patch",
							hero = "An underground fight club for Sparks? Okay, that's illegal about nine different ways.",
							villain = "A fight club with a betting vault? Somebody's sitting on a LOT of cash down there.",
						},
					},
				},
				-- 2. The fighter who ran / the collectors' cash bags
				{
					hero = {
						kind = "find",
						range = { 40, 140 },
						witness = true,
						text = "Find the young fighter who ran from the Pit",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 40, 140 },
						guards = { "BurglarBot", 2 },
						text = "Grab the cash bags off the family's collector bots",
					},
					at = "QuarryGate",
					lines = {
						{
							who = "pitboss",
							text = "Flint! Back in the ring, kid. You still owe the house, and the house ALWAYS collects.",
						},
						{
							who = "Brick",
							hero = "That's Flint, the best young fighter they've got, and she just ran. Find her before the bouncers do!",
							villain = "The family's collector bots haul tonight's take up the lift. Three bags. Grab them!",
						},
					},
				},
				-- 3. The mine lift: the Vigil get the bouncer bots on camera; the Syndicate catch the bookie's runner
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 30, 120 },
						text = "Photograph the bouncer bots guarding the mine lift",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the bookie bot with the betting book",
					},
					at = "MineLift",
					lines = {
						{
							who = "flint",
							hero = "The lift goes down to the Pit. Get those bouncer bots on camera and the whole city sees it.",
							villain = "You're not here to save me, are you? Fine. The bookie bot's book shows every fight is rigged.",
						},
						{
							who = "patch",
							hero = "Bouncer bots dragging fighters to a secret lift. That's a headline. Snap it!",
							villain = "That runner bot carries the betting book. Every fix the family ever pulled is in there.",
						},
					},
				},
				-- 4. The family comes for Flint / sell the book to a rival
				{
					hero = {
						kind = "fight",
						home = true,
						squads = { { "BurglarBot", 3 }, { "BruteBot", 1 } },
						text = "Scrap the bouncer bots sent after Flint",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Sell the betting book to a rival bookie",
					},
					at = "QuarryGate",
					lines = {
						{
							who = "pitboss",
							text = "Nobody walks out on the Gravel family! Boys, bring her back. And whoever's helping her.",
						},
						{
							who = "lodestar",
							hero = "Bouncers coming for the girl. Stand your ground, kid. Nobody drags her back down there.",
							villain = "Selling a crook's secrets to other crooks. Just don't let that girl get caught in it.",
						},
					},
				},
				-- 5. Down the mine lift into the Pit: the tunnel, the betting hall, the odds machines, the ring.
				-- The Pitboss's comic page: the quarry, his stone Spark, the ring and the debts.
				{
					hero = {
						kind = "pocket",
						layout = "pit",
						minutes = 12,
						text = "Ride the mine lift down into the Pit",
						villainText = "Ride the mine lift down and rob the Pit",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "BruteBot", 2 }, { "BurglarBot", 3 } },
								text = "Clear the bouncer bots out of the mine tunnel",
								villainText = "Scrap the bouncer bots guarding the tunnel",
							},
							{
								kind = "hold",
								at = "bets",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "BurglarBot", 4 } },
								waveGap = 10,
								text = "Hold the betting hall while the fighters slip out",
								villainText = "Hold the betting hall while the cash box cracks",
							},
							{
								kind = "break",
								list = "odds",
								points = 4,
								hits = 3,
								text = "Smash the Pit's rigged odds machines",
								villainText = "Crack the odds machines' cash drawers",
							},
							{
								kind = "reach",
								at = "ring",
								text = "Take the steps down into the ring",
								villainText = "Drop into the ring where the big money is",
							},
							{
								kind = "boss",
								enemy = "BruteBot",
								hpMult = 8,
								adds = { "BurglarBot", 3 },
								text = "Beat the Pit's undefeated house champion bot",
								villainText = "Scrap the house champion and take its winnings",
							},
						},
					},
					villain = "same",
					at = "MineLift",
					scene = "pitStory",
					lines = {
						{
							who = "flint",
							hero = "There are more fighters down there, locked in cages till their next fight. Please, get them out.",
							villain = "The house cash is in the odds machines. Rob them blind. Just open the cages on your way past?",
						},
					},
				},
				-- 6. Up out of the Pit: the hurt fighters / the cash over the walls; the Pitboss on his speakers
				{
					hero = {
						kind = "carry",
						range = { 60, 160 },
						text = "Fly a hurt fighter up to the medics",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Run the Pit's cash out over the quarry walls",
					},
					at = "QuarryGate",
					lines = {
						{
							who = "pitboss",
							text = "My Pit! My machines! My CHAMPION! You'll pay for that, every last coin, with interest!",
						},
						{
							who = "Brick",
							hero = "Some of these kids have fought every night for a year. Get the hurt ones to the medics first.",
							villain = "The family's coming up the lift. Run the cash out over the walls, now!",
						},
					},
				},
				-- 7. The quarry floor: the freed fighters / the Pitboss's title belts; he comes up himself
				{
					hero = {
						kind = "hold",
						home = true,
						seconds = 25,
						radius = 14,
						text = "Guard the freed fighters on the quarry floor",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 30, 120 },
						guards = { "ShieldBearer", 1 },
						text = "Steal the Pitboss's gold title belts",
					},
					at = "QuarryRing",
					lines = {
						{
							who = "flint",
							hero = "We're all out! But he's coming up himself. Nobody's ever beaten him. Nobody.",
							villain = "He keeps his title belts in crates by the lift. Solid gold. He loves them more than people.",
						},
						{
							who = "lodestar",
							hero = "Stone skin in a powered rig. Big, slow and proud. Make him come to you, kid.",
							villain = "Taking a man's trophies right before he fights you. You've got nerve, I'll give you that.",
						},
					},
				},
				-- 8. The finale on the quarry floor: the Pitboss in his powered prize-fighter rig
				{
					hero = {
						kind = "finale",
						enemy = "Bramblebeast", -- the suit and brain; the Pitboss's own look, name and title: dress
						dress = "Pitboss",
						hpMult = 2,
						adds = { { "BruteBot", 2 } },
						range = { 10, 40 },
						text = "Beat the Pitboss on the quarry floor",
						villainText = "Knock out the Pitboss and empty the family vault",
					},
					villain = "same",
					at = "QuarryRing",
					scene = "fightNight",
					lines = {
						{
							who = "pitboss",
							hero = "A hero in MY quarry? The crowd's going to love this. Ding ding, little hero!",
							villain = "Thieves in MY quarry? The house always wins. Ding ding, thief!",
						},
						{
							who = "Brick",
							hero = "Watch his right hand. Took me three years to learn that. You've got about three seconds.",
							villain = "Watch his right hand. And when he's down, the vault key's on his belt.",
						},
					},
				},
			},
		},
		-- Underwater chain (nate's lore, build plan step 11): The Sunken City. nate's draft: "An ancient sunken city
		-- wakes up, and its guardian wants the surface gone. The Tidewright, the city's last guardian." 8 quests (the
		-- district drafts' count). Velmara, a city of bronze towers, drowned in a great storm long ago; its people
		-- swam for the shore and never came back, leaving the Tidewright, a guardian machine, to keep it safe. A
		-- salvage dredger's drill cracked the city's seal last week; the Tidewright woke, took the surface for the
		-- enemy and is turning Velmara's tide engines on to raise a wave that washes the shore away. Its sentries are
		-- the sea's own robots (Divers, Anchors, Torpedo Sentries: machines only). The Vigil drive the sentries off
		-- the reef, find the salvage diver Marlo, plant Doc Pearl's scanner at the drowned gate, jam the tide engines
		-- inside Velmara, swim a reef keeper clear of the first surge and hold the Tide Spire while Patch jams it; the
		-- Dread Syndicate grab the reef's relics, catch the sentry with the gate key, crack the gate, loot the city's
		-- vaults and the engines' cores, run the gold past the surge and find the guardian's treasury. Both stop the
		-- Tidewright at the end. Every step is on the Coral Shelf's sea floor (deep sites). Standalone: no Crane.
		{
			id = "SunkenCity",
			bit = 8,
			name = "The Sunken City",
			layer = "district",
			district = "Underwater",
			giver = "Pearl",
			site = "ReefStation",
			unlock = { story = 2, level = 12 }, -- after Act 1's Safehouse, at the Coral Shelf's level floor
			villain = { name = "THE TIDEWRIGHT", title = "LAST GUARDIAN OF VELMARA" },
			reward = { share = 3, title = "Tide Turner", style = "CoralCrest" },
			blurb = {
				hero = "A drowned city is waking under the reef, and its guardian wants to wash the shore away.",
				villain = "A lost city of bronze and gold, sealed for a thousand years. Its doors just opened.",
			},
			lines = {
				offer = {
					hero = "The reef's humming, the sea floor split, and something under it wants the shore gone. Help me?",
					villain = "I've mapped a drowned city's vaults. You crack them, I fund my station. Deal?",
				},
				resume = {
					hero = "Back in the water? Good. The tide's rising a little more every hour.",
					villain = "Back for the gold? Velmara's vaults aren't going anywhere. Its guardian might.",
				},
				done = {
					hero = "The tide's down, the shore is safe and Velmara can sleep. The reef thanks you. So do I.",
					villain = "A guardian beaten and a city's gold in your pockets. My station's funded for years. Pleasure.",
				},
			},
			steps = {
				-- 1. Lights under the reef: Doc Pearl's story at the Reef Station
				{
					hero = { kind = "talk", text = "Hear Doc Pearl out at the Reef Station" },
					villain = { kind = "talk", text = "Get Doc Pearl's tip at the Reef Station" },
					scene = "velmaraLights",
					lines = {
						{
							who = "Pearl",
							hero = "Three nights the reef hummed. Then the sea floor cracked open and a whole city lit up under it.",
							villain = "There's a city under this reef. Sealed a thousand years, vaults and all. I have the maps.",
						},
						{
							who = "patch",
							hero = "A city under the sea? On it. And hey, you swim, I'll stay dry. That's teamwork.",
							villain = "Sunken treasure AND a lost city? Okay, I'm listening. I'm listening very hard.",
						},
					},
				},
				-- 2. The sentries wake on the reef / the reef's relics
				{
					hero = {
						kind = "fight",
						squads = { { "Diver", 4 }, { "Anchor", 1 } },
						range = { 60, 150 },
						text = "Drive off the sentries swarming the reef",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "Diver", 2 },
						text = "Grab the glowing relics off the reef",
					},
					lines = {
						{
							who = "tidewright",
							text = "Surface-dwellers. You broke the seal of Velmara. My sentries will see you off the reef.",
						},
						{
							who = "patch",
							hero = "Those sea bots are old. Like, older-than-the-city-above-you old. And they're angry.",
							villain = "The relics are glowing on the reef. Glowing means valuable. Probably. Grab them!",
						},
					},
				},
				-- 3. Marlo, the salvage diver / the sentry with the gate key
				{
					hero = {
						kind = "find",
						range = { 100, 250 },
						witness = true,
						text = "Find the salvage diver lost in the kelp",
					},
					villain = {
						kind = "chase",
						enemy = "Diver",
						hops = 5,
						speed = 18,
						text = "Catch the sentry carrying the gate key",
					},
					lines = {
						{
							who = "Pearl",
							hero = "A salvage crew was drilling here when it all began. One of their divers never came up.",
							villain = "One sentry swims with a bronze key on its back. That key opens Velmara's gate. Catch it!",
						},
						{
							who = "lodestar",
							hero = "Kelp and silt hide a lot. Search low and slow, kid.",
							villain = "Chasing a robot for its key. Just don't lose the robot in the kelp, kid.",
						},
					},
				},
				-- 4. The drowned gate: Doc Pearl's scanner / cracking the gate
				{
					at = "DrownedGate",
					hero = {
						kind = "deliver",
						range = { 40, 100 },
						text = "Plant Doc Pearl's scanner by the drowned gate",
					},
					villain = {
						kind = "hold",
						home = true,
						seconds = 25,
						radius = 12,
						text = "Hold the drowned gate while the key turns",
					},
					lines = {
						{
							who = "marlo",
							hero = "We only drilled for scrap! Then the reef split open and the lights came on. Something woke up.",
							villain = "Our drill cracked that gate. Whatever's behind it is old, gold and very, very big.",
						},
						{
							who = "tidewright",
							text = "The gate of Velmara stays shut. Turn back, or the sea will turn you back.",
						},
					},
				},
				-- 5. Inside Velmara under its air dome: the market, the fountain, the great stair and the engine hall
				{
					at = "DrownedGate",
					hero = {
						kind = "pocket",
						layout = "velmara",
						minutes = 12,
						text = "Swim into the drowned city of Velmara",
						villainText = "Loot the drowned city of Velmara",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "Anchor", 2 }, { "TorpedoSentry", 2 } },
								text = "Beat the sentries in Velmara's market",
								villainText = "Scrap the sentries guarding the market",
							},
							{
								kind = "hold",
								at = "fountain",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "Anchor", 2 } },
								waveGap = 10,
								text = "Hold the old fountain while Patch maps the city",
								villainText = "Hold the fountain while the vault lock drills",
							},
							{
								kind = "reach",
								at = "engines",
								text = "Take the great stair down to the engine hall",
								villainText = "Follow the great stair down to the vaults",
							},
							{
								kind = "break",
								list = "pumps",
								points = 4,
								hits = 3,
								text = "Jam the four tide engines",
								villainText = "Rip the glowing cores out of the tide engines",
							},
							{
								kind = "boss",
								enemy = "Anchor",
								hpMult = 8,
								adds = { "TorpedoSentry", 2 },
								text = "Beat Velmara's iron gate warden",
								villainText = "Scrap the gate warden for its bronze",
							},
						},
					},
					villain = "same",
					scene = "tidewrightTale",
					lines = {
						{
							who = "Pearl",
							hero = "The city's air dome still holds. Breathe easy in there, and stop those tide engines.",
							villain = "Vaults on the top floor, engine cores at the bottom. Take your time. Not too much time.",
						},
					},
				},
				-- 6. The first surge: a reef keeper caught in it / the gold past the surge
				{
					hero = {
						kind = "carry",
						range = { 80, 160 },
						text = "Swim a stranded reef keeper back to the station",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Race Velmara's gold past the first surge",
					},
					lines = {
						{
							who = "tidewright",
							text = "You stopped four engines. Velmara has forty. The tide will rise, and the shore will be sea.",
						},
						{
							who = "Pearl",
							hero = "The first surge hit the reef! One of my keepers is stuck out there. Bring her home!",
							villain = "The surge is coming in fast. Get that gold past it before the current takes it!",
						},
					},
				},
				-- 7. The Tide Spire, the engine that drives the wave / the guardian's treasury
				{
					at = "TideSpire",
					hero = {
						kind = "hold",
						home = true,
						seconds = 25,
						radius = 12,
						text = "Hold the Tide Spire while Patch jams it",
					},
					villain = {
						kind = "find",
						range = { 60, 160 },
						text = "Find the Tidewright's sunken treasury",
					},
					lines = {
						{
							who = "patch",
							hero = "This spire drives the whole wave. Keep the sentries off me while I scramble it!",
							villain = "Every guardian guards something. Find what this one keeps under its spire.",
						},
						{
							who = "lodestar",
							hero = "It isn't evil, kid. It's lonely, and it's scared. Stop it anyway.",
							villain = "You're robbing a thousand-year-old guardian. Make sure it's asleep first.",
						},
					},
				},
				-- 8. The finale: the Tidewright rises from the spire
				{
					at = "TideSpire",
					hero = {
						kind = "finale",
						enemy = "Anchor",
						dress = "Tidewright",
						hpMult = 10,
						adds = { { "Diver", 4 } },
						range = { 40, 100 },
						text = "Stop the Tidewright before the wave rises",
						villainText = "Beat the Tidewright and claim Velmara's crown",
					},
					villain = "same",
					scene = "tidewrightRises",
					lines = {
						{
							who = "tidewright",
							hero = "You jammed my spire. Then I will raise the tide myself. Velmara will not drown twice!",
							villain = "Thieves in my treasury. The last guardian of Velmara will not let you leave.",
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
