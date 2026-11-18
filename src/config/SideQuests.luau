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
-- * (lore step 11, the character lines) chains with layer "character" and npc unlocks, at Docks and Old Town
--   buildings too (sites keep `away.site` from each other); a line for one side only (unlock.side) keeps its
--   goals on that side's key alone; a dress with `famous` goes over a famous fake (it cracks and reads FAKE);
--   a giver may be a relay box (`relay`) and have its own `none` line.
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
		"RadioHill", -- the hand-placed hill west of the city (the origin lines, Starblood Calling)
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
		-- The character lines (nate's lore, build plan step 11: one chain per character, "about 5 quests each"):
		-- existing city buildings picked by the same rules as the academy's and the bank's, each `away.site` studs
		-- from every other chain's building or square (Shared.SideQuestSites). A Docks or Old Town building: of
		-- that district's buildings in the height range, the one nearest `near` (studs from the district's middle,
		-- x east and z south) at least away.pad from every safehouse pad and away.door from both HQ doors (the
		-- Safehouse's and the Foundry's), with a street door (the face whose ground is open, nearest the middle).
		-- The Last Partner (Lodestar's line): the Night Owl, the all-night diner where Lodestar and his partner met
		-- after every patrol, a low Downtown block south-east of the plaza
		NightOwl = {
			name = "THE NIGHT OWL DINER",
			district = "Downtown",
			near = { 150, 260 },
			height = { 24, 80 }, -- a low block with the diner on its ground floor
			away = { plaza = 200, row = 150, door = 180, open = 80, site = 250 },
		},
		-- Vesper's penthouse: a tall Uptown tower, the famous stranger's home
		Penthouse = {
			name = "VESPER'S PENTHOUSE",
			district = "Uptown",
			near = { -140, -200 },
			height = { 100, 520 },
			away = { landmark = 120, site = 250 },
		},
		-- Finding Lark (Patch's line): the Old Town flat over a shop where Patch and his sister Lark grew up
		LarkFlat = {
			name = "LARK'S OLD FLAT",
			district = "OldTown",
			near = { -150, 150 },
			height = { 18, 44 },
			away = { pad = 60, door = 120, site = 200 },
		},
		-- the Spark Pound: Catchpole's Docks warehouse (inside it, the "pound" pocket: Shared.PocketLayout)
		Pound = {
			name = "THE SPARK POUND",
			district = "Docks",
			near = { 200, 100 },
			height = { 20, 40 },
			away = { pad = 60, door = 120, site = 200 },
		},
		-- Hostile Takeover (the Syndicate boss's line, villains only): Duchess Vanta's club in Old Town, and the
		-- Torch Crew's garage across the district
		OpalRoom = {
			name = "THE OPAL ROOM",
			district = "OldTown",
			near = { 150, -150 },
			height = { 24, 44 },
			away = { pad = 60, door = 120, site = 200 },
		},
		TorchGarage = {
			name = "THE TORCH CREW GARAGE",
			district = "OldTown",
			near = { -150, -200 },
			height = { 18, 44 },
			away = { pad = 60, door = 120, site = 200 },
		},
		-- The Scoop (the reporter's line): BHN 24's studio tower, Downtown, its uplink on the roof
		Studio = {
			name = "BHN 24 STUDIOS",
			district = "Downtown",
			near = { 270, -300 },
			height = { 90, 200 },
			away = { plaza = 200, row = 150, door = 180, open = 80, site = 250 },
		},
		-- The origin lines (nate's lore, build plan step 11): one home site a line, picked by the same rules. The
		-- city ones keep `away.site` studs from every other chain's city site; their ids sort after the
		-- character lines' (a site keeps clear of those earlier by id), so no earlier chain's pick moves.
		-- The Ashgrove Test (Lab): an existing Downtown building south-east of the plaza (`near` from it), off
		-- the museum and opera runners' roofs. Inside it is the "ashlab" pocket (Shared.PocketLayout).
		Underlab = {
			name = "ASHGROVE LABS",
			district = "Downtown",
			near = { 300, 260 },
			height = { 50, 160 }, -- a research block, not a tower
			away = { plaza = 220, row = 150, door = 180, open = 80, site = 250 },
		},
		-- Starblood Calling (Alien): the first terrace of Radio Hill on its town side, under the old radio mast on
		-- the hand-placed landmark west of the city (`hill` "terrace": Shared.SideQuestSites.hill reads it from
		-- the landmark's boxes, so it never moves with the weekly seed). The beacon on top is the step 2 climb.
		RadioMast = {
			name = "RADIO HILL",
			district = "RadioHill",
			hill = "terrace",
		},
		-- The Last Owner (Magic): Auntie Moth's curio shop, an existing Old Town building east of Clock Square
		-- (`near` from the district's middle), its door on an open street
		VintageCurios = {
			name = "MOTH & MOON CURIOS",
			district = "OldTown",
			near = { 220, 160 },
			height = { 18, 44 },
			away = { pad = 60, door = 120, site = 300 },
		},
		-- The Taken Master (Training): an outskirts shop lot west of the hub, the Willow Street Dojo (the same rule
		-- as Tick-Tock Toys; sorted after it, so the toy shop's pick never moves)
		WillowDojo = {
			name = "WILLOW STREET DOJO",
			district = "Suburbs",
			lot = "shop",
			near = { -1150, 600 },
			rings = { 2, 5 },
			height = { 10, 20 },
			away = { pad = 150, beacon = 150, landmark = 300, district = 200, site = 400 },
		},
		-- Suit Recall (Tech): Tinker Tess's garage, an outskirts house lot south of the hub
		Workshop = {
			name = "TINKER'S GARAGE",
			district = "Suburbs",
			lot = "house",
			near = { 700, 1250 },
			rings = { 2, 5 },
			height = { 6, 30 },
			away = { pad = 150, beacon = 150, landmark = 300, district = 200, site = 400 },
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
		-- The Last Partner's finale (Lodestar's line): the famous stranger who came back wearing Vesper's face, in
		-- a starfield suit and a star cape, white hair and a star at the brow. `famous`: the dress goes over a
		-- famous fake (Radiant's suit and brain: a Light flyer's dives and bursts), so her face cracks to metal
		-- and her plate turns FAKE over her own name like any famous fake's. Not news: the Unmasked headline names
		-- the suit's fake, so a dressed fake skips it (EnemyService).
		Vesper = {
			name = "Vesper",
			title = "The Evening Star",
			creature = false,
			famous = true,
			body = {
				metal = { 150, 150, 170 },
				eye = { 220, 150, 255 },
				suit = { 70, 20, 110 },
				trim = { 240, 240, 250 },
			},
			look = {
				gender = 2,
				build = 2, -- Normal: the suit's build (Radiant's frame)
				height = 4,
				skin = 10,
				hair = 18, -- white
				colors = { 35, 13, 18 }, -- deep purple, lilac, white
				pieces = {
					suit = "Starfield Suit",
					back = "Star Cape",
					hands = "Gloves",
					feet = "Tall Boots",
					emblem = "Star Crest",
					hair = "Long Straight",
					visage = "Hero Face",
					makeup = "Star Mark",
				},
				tints = {},
				mats = {},
			},
		},
		-- Finding Lark's finale (Patch's line): Catchpole the Spark catcher in his powered catcher's rig, a big
		-- man in a ranger harness, a duster coat and a tracker lens, nets slung from the rig. The suit and brain
		-- are the Harvest King's (a heavy lobber: his throws are Catchpole's nets), as a machine that sparks apart.
		Catchpole = {
			name = "Catchpole",
			title = "The Spark Catcher",
			creature = false,
			body = {
				metal = { 110, 105, 90 },
				eye = { 170, 255, 90 },
				suit = { 90, 110, 40 },
				trim = { 120, 75, 45 },
			},
			look = {
				gender = 1,
				build = 3, -- Heavy: the suit's build (the Harvest King's frame)
				height = 4,
				skin = 4,
				hair = 39, -- chocolate
				colors = { 29, 16, 4 }, -- olive, brown, yellow
				pieces = {
					suit = "Ranger Harness",
					back = "Duster Coat",
					hat = "Tracker Lens",
					hands = "Work Gloves",
					feet = "Combat Boots",
					belt = "Tool Belt",
					hair = "Shaggy",
					beard = "Stubble",
					visage = "Sharp Face",
				},
				tints = {},
				mats = { hands = "Leather" },
			},
		},
		-- Hostile Takeover's finale (the Syndicate boss's line): Sal Scorch, boss of the Torch Crew, in a suit of
		-- glowing magma veins with flame gloves and flame hair. The suit and brain are Redline's (a slim Fire
		-- racer: his dashes leave fire), as a machine that sparks apart.
		Scorch = {
			name = "Sal Scorch",
			title = "Boss of the Torch Crew",
			creature = false,
			body = {
				metal = { 90, 80, 80 },
				eye = { 255, 160, 40 },
				suit = { 200, 60, 20 },
				trim = { 30, 30, 34 },
			},
			look = {
				gender = 1,
				build = 1, -- Slim: the suit's build (Redline's frame)
				height = 3,
				skin = 3,
				hair = 24, -- orange-red
				colors = { 24, 22, 4 }, -- orange-red, black, yellow
				pieces = {
					suit = "Magma Veins",
					hands = "Flame Gloves",
					shoulders = "Flame Pads",
					feet = "Combat Boots",
					belt = "Chain Belt",
					neck = "Chain",
					hair = "Flame Hair",
					beard = "Goatee",
					visage = "Scarred Face",
				},
				tints = {},
				mats = {},
			},
		},
		-- The Scoop's finale (the reporter's line): the Censor, a man in a black tuxedo and a long black cape with
		-- a mono visor like a black bar over his eyes. The suit and brain are Masque-a-Rade's (a Shadow floater:
		-- his darkness is the Censor's blackouts), as a machine that sparks apart.
		Censor = {
			name = "The Censor",
			title = "He Decides What You See",
			creature = false,
			body = {
				metal = { 60, 60, 70 },
				eye = { 240, 240, 250 },
				suit = { 24, 24, 28 },
				trim = { 200, 200, 210 },
			},
			look = {
				gender = 1,
				build = 2, -- Normal: the suit's build (Masque-a-Rade's frame)
				height = 4,
				skin = 9,
				hair = 22, -- black
				colors = { 22, 18, 20 }, -- black, white, grey
				pieces = {
					suit = "Tuxedo",
					back = "Long Cape",
					head = "Mono Visor",
					hands = "Gloves",
					feet = "Loafers",
					neck = "High Collar",
					hair = "Side Part",
					visage = "Cold Face",
				},
				tints = { head = { 22, 22, 0 }, back = { 22, 20, 0 } }, -- an all-black visor (the bar), a black cape
				mats = {},
			},
		},
		-- The origin lines' finale villains (lore step 11): none needs a robot type of its own.
		-- The Ashgrove Test (Lab): Doctor Holloway in his shielded lab rig, a silver-haired director in a lab coat
		-- with steel plates, a gear rig on his back and a visor. No Spark of his own: the rig is the Warden's
		-- (`robot`: its guard brain, front shield and health), in the Light path's look, damage into the band.
		Holloway = {
			name = "Doctor Holloway",
			title = "Director of Ashgrove Labs",
			creature = false,
			robot = true,
			path = "Light",
			height = 7,
			dmgMult = 1.4,
			body = {
				metal = { 200, 205, 215 },
				eye = { 80, 255, 255 },
				suit = { 245, 245, 245 },
				trim = { 70, 60, 160 },
			},
			look = {
				gender = 1,
				build = 3, -- Heavy: the Warden's frame
				height = 4,
				skin = 2,
				hair = 19, -- silver
				colors = { 18, 34, 46 }, -- white, indigo, cyan glow
				pieces = {
					suit = "Lab Coat",
					shoulders = "Layered Plates",
					hands = "Tech Gloves",
					backpack = "Cog Rig",
					head = "Mono Visor",
					hair = "Slicked Back",
					visage = "Cold Face",
					feet = "Armored Boots",
				},
				tints = {},
				mats = { shoulders = "Metal", backpack = "Metal" },
			},
		},
		-- Starblood Calling (Alien): the Voidhound, an ancient hunting machine from the stars in a starfield shell,
		-- an antenna helm, a one-eyed visor and a meteor cape. Over the Captain (`robot`: it hangs back and
		-- rallies its drones), in the Pulse path's look, damage into the band.
		Voidhound = {
			name = "The Voidhound",
			title = "Hunter from the Stars",
			creature = false,
			robot = true,
			path = "Pulse",
			height = 8,
			dmgMult = 1.1,
			body = {
				metal = { 70, 60, 110 },
				eye = { 190, 90, 255 },
				suit = { 40, 44, 60 },
				trim = { 190, 90, 255 },
			},
			look = {
				gender = 1,
				build = 2, -- Normal: the Captain's frame
				height = 5,
				skin = 26, -- the Metal skin: a machine all through
				hair = 22,
				colors = { 35, 44, 48 }, -- deep purple, midnight, ultraviolet
				pieces = {
					suit = "Starfield Suit",
					head = "Antenna Helm",
					eyes = "Cyclops Visor",
					back = "Meteor Cape",
					shoulders = "Crystal Shards",
					hands = "Talon Gloves",
					feet = "Hover Boots",
				},
				tints = {},
				mats = { suit = "Metal" },
			},
		},
		-- The Last Owner (Magic): Morrow the Mirage, a jealous old stage illusionist in a tuxedo, a high-collared
		-- cape, a top hat and a masquerade mask, in Madame Masque-a-rade's powered suit of mirrors and wires.
		Morrow = {
			name = "Morrow the Mirage",
			title = "The Jealous Illusionist",
			creature = false,
			body = {
				metal = { 175, 180, 190 },
				eye = { 190, 110, 240 },
				suit = { 24, 24, 28 },
				trim = { 120, 80, 220 },
			},
			look = {
				gender = 1,
				build = 2, -- Normal: the suit's build
				height = 4,
				skin = 9,
				hair = 22, -- black
				colors = { 22, 12, 19 }, -- black, violet, silver
				pieces = {
					suit = "Tuxedo",
					back = "High Collar Cape",
					hat = "Top Hat",
					head = "Masquerade",
					hands = "Gloves",
					beard = "Pencil Mustache",
					hair = "Slicked Back",
					eyes = "Violet Glow",
				},
				tints = { back = { 22, 12, 0 } }, -- a black cape lined in violet
				mats = {},
			},
		},
		-- Suit Recall (Tech): Clawback, the repo king, a big man in a hooked exo frame with iron gauntlets, a
		-- ball cap and a rack of gears on his back. Over the Grappler (`robot`: its hook pulls a hero in), in the
		-- Gadgeteer path's look, damage into the band.
		Clawback = {
			name = "Clawback",
			title = "The Repo King",
			creature = false,
			robot = true,
			path = "Gadgeteer",
			height = 8,
			dmgMult = 1.1,
			body = {
				metal = { 110, 115, 125 },
				eye = { 255, 140, 40 },
				suit = { 230, 190, 60 },
				trim = { 55, 58, 66 },
			},
			look = {
				gender = 1,
				build = 3, -- Heavy: the Grappler's frame
				height = 5,
				skin = 4,
				hair = 39, -- chocolate
				colors = { 28, 21, 3 }, -- mustard, charcoal, orange
				pieces = {
					suit = "Exo Frame",
					hat = "Ball Cap",
					hands = "Armored Gauntlets",
					belt = "Tool Belt",
					shoulders = "Gear Pads",
					backpack = "Gear Rack",
					beard = "Horseshoe",
					visage = "Scarred Face",
					feet = "Armored Boots",
				},
				tints = {},
				mats = { hands = "Metal" },
			},
		},
		-- The Taken Master (Training): Gale, Master Hoshi's angriest old student, lean and fast in a fighter's
		-- sash, a headband, fighter's wraps and a long wind scarf. His Spark never woke, so he wears Redline's
		-- powered racing suit (its dashes and speed) as a speed rig.
		Gale = {
			name = "Gale",
			title = "The Master's Fallen Student",
			creature = false,
			body = {
				metal = { 85, 95, 110 },
				eye = { 80, 255, 255 },
				suit = { 24, 24, 28 },
				trim = { 40, 190, 170 },
			},
			look = {
				gender = 1,
				build = 1, -- Slim: the suit's build (Redline's lean racer)
				height = 3,
				skin = 3,
				hair = 21, -- charcoal
				colors = { 8, 18, 22 }, -- teal, white, black
				pieces = {
					suit = "Sash Fighter",
					hat = "Hachimaki",
					hands = "Fighter Wraps",
					legs = "Hakama",
					back = "Wind Scarf",
					hair = "Wild Mane",
					visage = "Sharp Face",
					eyes = "Ice Blades",
					feet = "Tabi Boots",
				},
				tints = {},
				mats = {},
			},
		},
	},

	-- Who gives chains: a person on the R15 rig at an anchor ("plaza", "hq", a Config.City district, or "site"
	-- with `site`: a row in sites) plus an offset; also a guide speaker (GuideHud lines). `look` (optional): a
	-- fixed hero look from earnable creator pieces (Shared.FakeRules.lookFrom, validated by CreatorRules) drawn
	-- by LookKit; without one, plain colours (PLACEHOLDER ART until the art pass). Lore step 11, the character
	-- lines: `relay` (true, a "radio" giver with no look) is a voice heard through a relay box SideQuestService
	-- draws instead of a person (Patch); `none` (optional, a fixed line or one per side) is what this giver says
	-- instead of the shared `none` line when it has nothing for the hero (Vanta to a Vigil hero).
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
		-- The Last Partner's giver (Lodestar's line): Lodestar himself, in his booth at the Night Owl diner, in his
		-- fixed look (Config.Story.opening.lodestar.look; tested to match) and his guide portrait. His partner of
		-- twelve years, Vesper, died in the harbour fire last winter; last month she came back, famous, and
		-- doesn't know his name. He wants the stranger unmasked (the Vigil), or will pay a Syndicate crook with
		-- everything in her penthouse to do it (the Dread Syndicate).
		LodestarGiver = {
			name = "LODESTAR",
			anchor = "site",
			site = "NightOwl",
			color = { 150, 190, 255 },
			style = "person",
			blip = "guideLodestar",
			portrait = {
				bg = { 30, 42, 86 },
				skin = { 214, 160, 120 },
				hair = { 205, 210, 220 },
				shape = "slick",
				extras = { "beard", "scar", "star" },
			},
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
		-- Finding Lark's giver (Patch's line): Patch is a voice on the radio, so his giver is a relay box he wired
		-- to a lamp post outside his sister's old flat (`relay`: SideQuestService draws the box, PLACEHOLDER ART).
		-- His big sister Lark, a flier, raised him alone until a Spark catcher's net van took her a year ago.
		PatchRelay = {
			name = "PATCH'S RELAY",
			anchor = "site",
			site = "LarkFlat",
			color = { 120, 230, 255 },
			style = "radio",
			relay = true,
			blip = "radio",
			portrait = {
				bg = { 18, 60, 72 },
				skin = { 241, 194, 160 },
				hair = { 120, 78, 40 },
				shape = "messy",
				extras = { "cap", "headset" },
			},
		},
		-- Hostile Takeover's giver (the Syndicate boss's line, villains only): Duchess Vanta, who has run Old Town's
		-- rackets from the Opal Room for twenty years without one fire. Sal Scorch's Torch Crew burns the shops
		-- that pay her. She wants him gone, by a face nobody in Old Town knows. A Vigil hero gets her `none` line.
		Vanta = {
			name = "DUCHESS VANTA",
			anchor = "site",
			site = "OpalRoom",
			color = { 190, 110, 240 },
			style = "person",
			blip = "guideInsider",
			none = {
				hero = "A hero in the Opal Room? You're lost, darling. The door is right behind you.",
				villain = "Not yet, darling. Make a name for yourself first. Then come and see me.",
			},
			portrait = {
				bg = { 50, 20, 60 },
				skin = { 160, 105, 70 },
				hair = { 175, 180, 190 },
				shape = "slick",
				extras = { "pearls" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 4,
				skin = 5,
				hair = 19, -- silver
				colors = { 35, 28, 22 }, -- deep purple, gold, black
				pieces = {
					suit = "Royal Coat",
					neck = "Bead Necklace",
					wrist = "Gem Ring",
					ears = "Gem Studs",
					hair = "Crown Braid",
					visage = "Cold Face",
					makeup = "Lipstick",
					feet = "Loafers",
				},
				tints = { neck = { 18, 18, 0 } }, -- white beads: her pearls
				mats = {},
			},
		},
		-- The Scoop's giver (the reporter's line): Nora Bright, BHN 24's night reporter, whose stories keep getting
		-- cut mid-sentence. She wants the truth on air (the Vigil), or will trade every secret she never got to
		-- air for help getting it out (the Dread Syndicate). Her hand mic is on her portrait.
		Nora = {
			name = "NORA BRIGHT",
			anchor = "site",
			site = "Studio",
			color = { 90, 170, 255 },
			style = "person",
			blip = "guideInsider",
			portrait = {
				bg = { 30, 50, 90 },
				skin = { 198, 140, 100 },
				hair = { 80, 50, 30 },
				shape = "messy",
				extras = { "mic" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 3,
				skin = 4,
				hair = 39, -- chocolate
				colors = { 10, 18, 1 }, -- blue, white, red
				pieces = {
					suit = "Trench Coat",
					hair = "Bob Cut",
					ears = "Comms Earpiece",
					neck = "Pendant",
					feet = "Sneakers",
					visage = "Hero Face",
					makeup = "Freckles",
				},
				tints = {},
				mats = {},
			},
		},
		-- The origin lines' givers (lore step 11), each at their line's home site.
		-- The Ashgrove Test (Lab): Dr. Okafor, the night-shift scientist who ran the Kindler on the night of your
		-- test. She was fired when she asked why the lab shut; she wants the volunteers out (the Vigil), or her
		-- back pay out of the research (the Dread Syndicate).
		Okafor = {
			name = "DR. OKAFOR",
			anchor = "site",
			site = "Underlab",
			color = { 240, 240, 245 },
			style = "person",
			blip = "guideInsider",
			portrait = {
				bg = { 30, 60, 80 },
				skin = { 86, 56, 38 },
				hair = { 24, 24, 28 },
				shape = "messy",
				extras = { "spectacles" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 3,
				skin = 7,
				hair = 22, -- black
				colors = { 18, 8, 43 }, -- white, teal, slate
				pieces = {
					suit = "Lab Coat",
					hair = "Locs",
					visage = "Hero Face",
					feet = "Sneakers",
				},
				tints = {},
				mats = {},
			},
		},
		-- Starblood Calling (Alien): Radio Ruth, a retired radio ham who lives by the old mast on Radio Hill and
		-- has been taping a song from the sky all week.
		Ruth = {
			name = "RADIO RUTH",
			anchor = "site",
			site = "RadioMast",
			color = { 230, 190, 60 },
			style = "person",
			blip = "radio",
			portrait = {
				bg = { 44, 40, 70 },
				skin = { 241, 194, 160 },
				hair = { 245, 245, 245 },
				shape = "slick",
				extras = { "headset" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 2,
				skin = 2,
				hair = 18, -- white
				colors = { 28, 16, 9 }, -- mustard, brown, sky
				pieces = {
					shirt = "Knit Sweater",
					pants = "Cargo Trousers",
					hair = "Top Bun",
					hat = "Headphones",
					backpack = "Radio Pack",
					visage = "Hero Face",
					feet = "Boots",
				},
				tints = {},
				mats = {},
			},
		},
		-- The Last Owner (Magic): Auntie Moth, who keeps the curio shop in Old Town where your relic sat on a
		-- shelf for forty years, until it picked you.
		Moth = {
			name = "AUNTIE MOTH",
			anchor = "site",
			site = "VintageCurios",
			color = { 150, 40, 110 },
			style = "person",
			blip = "guideLodestar",
			portrait = {
				bg = { 50, 30, 60 },
				skin = { 198, 140, 100 },
				hair = { 175, 180, 190 },
				shape = "hood",
				extras = {},
			},
			look = {
				gender = 2,
				build = 2,
				height = 2,
				skin = 4,
				hair = 19, -- silver
				colors = { 15, 13, 4 }, -- plum, lilac, gold
				pieces = {
					shirt = "Turtleneck",
					pants = "Long Skirt",
					back = "Hooded Cape",
					neck = "Pendant",
					wrist = "Bangles",
					hair = "Long Straight",
					visage = "Hero Face",
					feet = "Sandals",
				},
				tints = {},
				mats = {},
			},
		},
		-- Suit Recall (Tech): Tinker Tess, the mechanic whose garage you built your suit in, from scrapyard parts
		-- and a dead power core.
		Tess = {
			name = "TINKER TESS",
			anchor = "site",
			site = "Workshop",
			color = { 255, 140, 40 },
			style = "person",
			blip = "guideInsider",
			portrait = {
				bg = { 60, 50, 40 },
				skin = { 160, 105, 70 },
				hair = { 24, 24, 28 },
				shape = "messy",
				extras = { "goggles" },
			},
			look = {
				gender = 2,
				build = 2,
				height = 3,
				skin = 5,
				hair = 22, -- black
				colors = { 3, 10, 21 }, -- orange, blue, charcoal
				pieces = {
					suit = "Overalls",
					hat = "Flight Goggles",
					hands = "Work Gloves",
					belt = "Tool Belt",
					hair = "Afro",
					visage = "Rookie Face",
					feet = "Combat Boots",
				},
				tints = {},
				mats = {},
			},
		},
		-- The Taken Master (Training): Kiko, Master Hoshi's youngest student, who sweeps the Willow Street Dojo and
		-- saw the man in the fire rig take him.
		Kiko = {
			name = "KIKO",
			anchor = "site",
			site = "WillowDojo",
			color = { 235, 60, 60 },
			style = "person",
			blip = "guideLodestar",
			portrait = {
				bg = { 70, 40, 40 },
				skin = { 241, 194, 160 },
				hair = { 24, 24, 28 },
				shape = "slick",
				extras = { "headband" },
			},
			look = {
				gender = 2,
				build = 1,
				height = 1,
				skin = 10,
				hair = 22, -- black
				colors = { 18, 1, 22 }, -- white, red, black
				pieces = {
					suit = "Dojo Gi",
					hat = "Hachimaki",
					belt = "Obi",
					hair = "High Ponytail",
					visage = "Rookie Face",
					feet = "Sandals",
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
							villain = "Copier cores, in your hands. I don't like it. Just keep them away from kids.",
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
		-- the reef, find the salvage diver Dace, plant Doc Pearl's scanner at the drowned gate, jam the tide engines
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
				-- 3. Dace, the salvage diver / the sentry with the gate key
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
							who = "dace",
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
		-- Character line (nate's lore, build plan step 11): The Last Partner. nate's draft: "the veteran's last
		-- partner was replaced by a fake." Lodestar flew with Vesper, the Evening Star, for twelve years. Last
		-- winter she flew into the harbour fire for the last family and never came out; last month she came back,
		-- rich and famous, and walked right past him. The Vigil photograph her escort drones, find the fire crew
		-- captain who saw her fall, light the old two-star signal and scrap the drones she sends; the Dread
		-- Syndicate rob her trophy van, catch the courier with her key card, race it to her penthouse and run her
		-- memory chip to Lodestar. Both crack the fake's face at the end (a famous fake under her dress). Lines
		-- for both sides, from Lodestar's diner and her Uptown tower. Standalone: who built her is left open.
		{
			id = "LastPartner",
			bit = 9,
			name = "The Last Partner",
			layer = "character",
			giver = "LodestarGiver",
			site = "NightOwl",
			unlock = { story = 4, level = 8, npc = true }, -- after Act 1's fourth mission; only from Lodestar
			villain = { name = "VESPER", title = "THE EVENING STAR" },
			reward = { share = 3, title = "True North", style = "TwinStarCape" },
			blurb = {
				hero = "Lodestar's partner died last winter. Now she's back, famous, and doesn't know his name.",
				villain = "A famous hero wears a dead woman's face. Lodestar will pay to see her unmasked.",
			},
			lines = {
				offer = {
					hero = "Vesper was my partner for twelve years. She died in a fire. Now she's on every screen, and she doesn't know me.",
					villain = "I don't work with your kind. But she's no hero. Unmask her, and everything in her penthouse is yours.",
				},
				resume = {
					hero = "Back, kid? Good. Let's find out who is wearing my partner's face.",
					villain = "Still interested? Her penthouse is still full. Let's go.",
				},
				done = {
					hero = "That thing was never her. Vesper went down saving a family, and now the whole city knows it. Thank you, kid.",
					villain = "Her penthouse is empty and that fake is scrap. We're square. Don't let me catch you on a bad night.",
				},
			},
			steps = {
				-- 1. The Night Owl diner: Lodestar's booth, two coffees
				{
					hero = { kind = "talk", text = "Meet Lodestar at the Night Owl diner" },
					villain = { kind = "talk", text = "Hear Lodestar's offer at the Night Owl" },
					at = "NightOwl",
					scene = "nightOwl",
					lines = {
						{
							who = "lodestar",
							hero = "The harbour fire. She went in for the last family and the roof came down. I got the family out. Not her.",
							villain = "Twelve years we flew together. Last month she stepped out of a limo and smiled at me like a stranger.",
						},
						{
							who = "patch",
							hero = "Vesper's on every billboard in Uptown. And her escort drones follow her everywhere she goes.",
							villain = "Vesper's penthouse is full of awards. Gold ones. Just saying.",
						},
					},
				},
				-- 2. Uptown: her escort drones on camera / her trophy van
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 30, 120 },
						text = "Photograph Vesper's escort drones over Uptown",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 40, 140 },
						guards = { "ShieldBearer", 1 },
						text = "Grab the gold awards off Vesper's trophy van",
					},
					at = "Penthouse",
					lines = {
						{
							who = "vesper",
							text = "Smile for the drones, Uptown! Every photo of me is a memory you get to keep.",
						},
						{
							who = "patch",
							hero = "Those drones were built, not bought. Somebody made them. Get pictures and I'll trace the parts.",
							villain = "Her trophy van's parked out front. Solid gold awards. Who even gives a hero gold?",
						},
					},
				},
				-- 3. The fire crew captain who saw her fall / the courier with her key card
				{
					hero = {
						kind = "find",
						range = { 40, 140 },
						witness = true,
						text = "Find the fire captain who saw Vesper fall",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the courier bot with her key card",
					},
					at = "NightOwl",
					lines = {
						{
							who = "lodestar",
							hero = "The fire crew's captain was there that night. Nobody ever asked him what he saw.",
							villain = "Her courier bot carries the key card to the penthouse. It runs past here every night.",
						},
						{
							who = "patch",
							hero = "Found him in the old fire report. He retired near here. Go talk to him!",
							villain = "That courier bot is quick. Don't let it reach Uptown!",
						},
					},
				},
				-- 4. The two-star signal on the diner's roof / the key card over the roofs
				{
					hero = {
						kind = "hold",
						seconds = 20,
						radius = 10,
						high = true,
						text = "Light Lodestar's old two-star signal",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Race the key card over the roofs",
					},
					at = "NightOwl",
					lines = {
						{
							who = "lodestar",
							hero = "Our signal. Two stars on the clouds. The real Vesper always came. Let's see what does.",
							villain = "Get that card into her tower before she cancels it. Roofs are faster than roads.",
						},
					},
				},
				-- 5. Uptown: her drones come for the signal-lighters / the memory chip; her story as a comic page
				{
					hero = {
						kind = "fight",
						squads = { { "SparkDrone", 4 }, { "ShieldBearer", 1 } },
						range = { 60, 150 },
						text = "Scrap the drones guarding Vesper's tower",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Run Vesper's memory chip to Lodestar",
					},
					at = "Penthouse",
					scene = "vesperStory",
					lines = {
						{
							who = "vesper",
							text = "Somebody lit that dusty old signal. How rude. Drones? Make them go away.",
						},
						{
							who = "lodestar",
							hero = "She came, and she sent drones in first. Vesper never once sent anyone in ahead of her.",
							villain = "Her memory chip. If she's a machine, it's all in there. Bring it to me.",
						},
					},
				},
				-- 6. The finale outside her tower: the fake Vesper, cracked to metal
				{
					hero = {
						kind = "finale",
						enemy = "Radiant", -- a famous fake's suit and brain; Vesper's look, name and title: dress
						dress = "Vesper",
						hpMult = 3,
						adds = { { "SparkDrone", 3 } },
						range = { 20, 60 },
						text = "Crack the fake Vesper's face for the city",
						villainText = "Unmask the fake Vesper and rob her blind",
					},
					villain = "same",
					at = "Penthouse",
					scene = "twoStars",
					lines = {
						{
							who = "vesper",
							hero = "Lodestar sent you? How sweet. Tell him the old Vesper isn't coming back.",
							villain = "Robbing my penthouse? I'm a HERO, darling. Heroes always win on camera.",
						},
						{
							who = "lodestar",
							hero = "Same light, same moves. But she always led with her left. Watch for the cracks.",
							villain = "Hit it till it cracks. Whatever's in there isn't her.",
						},
					},
				},
			},
		},
		-- Character line (nate's lore, build plan step 11): Finding Lark. nate's draft: "the hacker kid is hunting
		-- for a missing sister." Patch's big sister Lark, a flier, raised him alone; a year ago she stopped a
		-- mugging on camera, and two days later Catchpole the Spark catcher's net van took her. Tonight her old
		-- radio said one word: pound. The Vigil find the neighbour who saw the van, photograph the vans at the
		-- Spark Pound (a Docks warehouse), clear its gate, break in and open every cage, fly the weakest to the
		-- medics; the Dread Syndicate, paid with everything Patch has, steal the bounty files, catch the catcher
		-- bot with the gate code, hold the gate while Patch jams the cameras, rob the pound's safe and run the
		-- bounty money out. Both open Lark's cell and stop Catchpole. Patch's giver is a relay box (he's radio only).
		{
			id = "FindingLark",
			bit = 10,
			name = "Finding Lark",
			layer = "character",
			giver = "PatchRelay",
			site = "LarkFlat",
			unlock = { story = 3, level = 6, npc = true }, -- after Act 1's third mission; only from Patch's relay
			villain = { name = "CATCHPOLE", title = "THE SPARK CATCHER" },
			reward = { share = 3, title = "Found Family", style = "RelayVisor" },
			blurb = {
				hero = "Patch's big sister Lark vanished a year ago. Tonight her old radio said one word: pound.",
				villain = "A Spark catcher keeps a pound full of bounties. Patch will pay anything to free Lark.",
			},
			lines = {
				offer = {
					hero = "I never ask for stuff. I'm asking. My sister Lark is alive, and I know where she is. Sort of.",
					villain = "I know you're not a good guy. I don't care. My sister's in a cage. I'll pay everything I have.",
				},
				resume = {
					hero = "You came back! Okay. Okay. Let's keep going. Lark's still in there.",
					villain = "You came back. I'm still paying. Let's get her out.",
				},
				done = {
					hero = "She's home. She's eating all my cereal. Best night of my whole life. I owe you forever.",
					villain = "Lark's home and Catchpole's broke. You kept your end. Here's mine. Thank you. Really.",
				},
			},
			steps = {
				-- 1. Lark's old flat in Old Town: her jacket on the hook, her radio waking up
				{
					hero = { kind = "talk", text = "Answer Patch's relay at Lark's old flat" },
					villain = { kind = "talk", text = "Hear Patch's offer at Lark's old flat" },
					at = "LarkFlat",
					scene = "larkFlat",
					lines = {
						{
							who = "patch",
							hero = "She stopped a mugging with her Spark, on camera. Two days later a van with a net on top took her.",
							villain = "A net van took her. A Spark catcher. He sells Sparks like they're stray dogs.",
						},
						{
							who = "lark",
							text = "Patch? If you can hear this... the pound. The Docks. Hurry.",
						},
					},
				},
				-- 2. Old Town: the neighbour who saw the van / the bounty files
				{
					hero = {
						kind = "find",
						range = { 40, 140 },
						witness = true,
						text = "Find the neighbour who saw the net van",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 40, 140 },
						guards = { "BurglarBot", 2 },
						text = "Steal the bounty files off the catcher's bots",
					},
					at = "LarkFlat",
					lines = {
						{
							who = "catchpole",
							text = "Another Spark seen in Old Town? Mark it. Net it. Bag it. The bounty's good this week.",
						},
						{
							who = "patch",
							hero = "The old lady downstairs sees everything. If anybody saw that van, it's her.",
							villain = "His bots collect tips all over Old Town. Their files say where the pound is.",
						},
					},
				},
				-- 3. The Spark Pound in the Docks: the net vans on camera / the catcher bot with the gate code
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 30, 120 },
						text = "Photograph the net vans at the Spark Pound",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the catcher bot with the gate code",
					},
					at = "Pound",
					lines = {
						{
							who = "patch",
							hero = "That's the pound. A real warehouse, right in the Docks. Get the vans on camera. Proof!",
							villain = "His catcher bot knows the gate code. Grab it and we're in.",
						},
						{
							who = "catchpole",
							text = "Who's snooping round my pound? Every Spark in there is paid for. Fair and square.",
						},
					},
				},
				-- 4. The pound's gate: its guard bots / the gate held while Patch jams the cameras
				{
					hero = {
						kind = "fight",
						home = true,
						squads = { { "BurglarBot", 3 }, { "Bomber", 1 } },
						text = "Scrap the guard bots at the pound's gate",
					},
					villain = {
						kind = "hold",
						seconds = 20,
						radius = 12,
						text = "Hold the gate while Patch jams the cameras",
					},
					at = "Pound",
					lines = {
						{
							who = "patch",
							hero = "They saw us. Guard bots at the gate. Clear them and the way in is open.",
							villain = "Hold there, I'm jamming the cameras. Twenty seconds. Don't let them near the gate box!",
						},
					},
				},
				-- 5. Inside the Spark Pound: the intake office, the kennel hall, the collar scanners, Lark's cell.
				-- Lark's story as a comic page.
				{
					hero = {
						kind = "pocket",
						layout = "pound",
						minutes = 12,
						text = "Break into the Spark Pound",
						villainText = "Break into the Spark Pound and rob it",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "BurglarBot", 3 }, { "ShieldBearer", 1 } },
								text = "Clear the guard bots out of the intake office",
								villainText = "Scrap the guard bots in the intake office",
							},
							{
								kind = "hold",
								at = "kennels",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "SparkDrone", 3 } },
								waveGap = 10,
								text = "Hold the kennel hall while the cages open",
								villainText = "Hold the kennel hall while the safe cracks",
							},
							{
								kind = "break",
								list = "collars",
								points = 4,
								hits = 3,
								text = "Smash the four collar scanners",
								villainText = "Smash the scanners and grab the bounty chips",
							},
							{
								kind = "reach",
								at = "cell",
								text = "Reach Lark's cell at the end of the hall",
								villainText = "Reach the last cell, and Lark",
							},
							{
								kind = "boss",
								enemy = "Grappler",
								hpMult = 4,
								adds = { "SparkDrone", 2 },
								text = "Beat the pound's warden bot",
								villainText = "Scrap the warden bot and take its keys",
							},
						},
					},
					villain = "same",
					at = "Pound",
					scene = "larkStory",
					lines = {
						{
							who = "patch",
							hero = "Every cage has a Spark in it. Twelve of them. Get them all out. Lark's at the end.",
							villain = "The bounty money's in the office safe. Take it. But Lark's in the last cell. Please.",
						},
					},
				},
				-- 6. Out of the pound: the weakest Spark to the medics / the bounty money over the roofs
				{
					hero = {
						kind = "carry",
						range = { 60, 160 },
						text = "Fly a freed Spark to the medics",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Run the bounty money out over the Docks",
					},
					at = "Pound",
					lines = {
						{
							who = "lark",
							text = "I'm out! Patch, I'm OUT! But Catchpole's van is coming back. Move!",
						},
						{
							who = "patch",
							hero = "Some of them can barely stand after a year in a collar. The medics are a block away.",
							villain = "Catchpole's back early! Get the money clear, I'll steer you.",
						},
					},
				},
				-- 7. The finale outside the pound: Catchpole in his catcher's rig
				{
					hero = {
						kind = "finale",
						enemy = "HarvestKing", -- the suit and brain (a heavy lobber); Catchpole's look, name and title: dress
						dress = "Catchpole",
						hpMult = 2,
						adds = { { "BurglarBot", 3 } },
						range = { 20, 60 },
						text = "Stop Catchpole before he nets Lark again",
						villainText = "Beat Catchpole and take his bounty book",
					},
					villain = "same",
					at = "Pound",
					scene = "netGun",
					lines = {
						{
							who = "catchpole",
							hero = "That girl's my best bounty all year. You don't get to keep her, hero.",
							villain = "A crook robbing a crook? Nothing's free, thief. There's a bounty on you now too.",
						},
						{
							who = "lark",
							text = "He fires nets, then reels you in. Keep moving. I'll call the shots from up here!",
						},
					},
				},
			},
		},
		-- Character line (nate's lore, build plan step 11): Hostile Takeover, for the Dread Syndicate only. nate's
		-- draft: "a Syndicate boss wants a rival removed (villain side only)." Duchess Vanta has run Old Town's
		-- rackets from the Opal Room for twenty years without one fire; Sal Scorch's Torch Crew now burns the shops
		-- that pay her. Villains steal back the protection money, catch the Crew's bookkeeper bot, plant its
		-- ledger on Scorch's own lieutenant so the Crew turns on itself, hit the garage and beat Scorch in front
		-- of his crew. Every goal and line sits on the villain key (unlock.side "villain"; a Vigil hero is locked
		-- out and gets Vanta's `none` line). "Removed": beaten and run out of town, cartoon style.
		{
			id = "HostileTakeover",
			bit = 11,
			name = "Hostile Takeover",
			layer = "character",
			giver = "Vanta",
			site = "OpalRoom",
			unlock = { story = 2, level = 6, side = "villain", npc = true }, -- after Act 1's Safehouse; villains
			villain = { name = "SAL SCORCH", title = "BOSS OF THE TORCH CREW" },
			reward = { share = 3, title = "Fireproof", style = "ScorchproofGauntlets" },
			blurb = {
				villain = "The Torch Crew burns Old Town shop by shop. Duchess Vanta wants their boss gone.",
			},
			lines = {
				offer = {
					text = "You're new, so nobody knows your face. Perfect. Sal Scorch wants my Old Town. I want him gone.",
				},
				resume = {
					text = "Back, darling? Sal is still in business. Let's change that.",
				},
				done = {
					text = "The Torch Crew is finished and Old Town is mine again. Your booth at the Opal Room is always waiting.",
				},
			},
			steps = {
				-- 1. The Opal Room: the Duchess's booth, the Torch Crew's threat
				{
					villain = { kind = "talk", text = "Meet Duchess Vanta at the Opal Room" },
					at = "OpalRoom",
					scene = "opalRoom",
					lines = {
						{
							who = "Vanta",
							text = "Old Town pays me to keep it quiet. Scorch burns the shops that pay me, and laughs.",
						},
						{
							who = "patch",
							text = "Duchess Vanta runs half of Old Town. If she wants Scorch gone, he's a big deal.",
						},
					},
				},
				-- 2. The Torch Crew's garage: the protection money
				{
					villain = {
						kind = "fetch",
						count = 3,
						range = { 40, 140 },
						guards = { "BurglarBot", 2 },
						text = "Take back the Torch Crew's protection money",
					},
					at = "TorchGarage",
					lines = {
						{
							who = "Vanta",
							text = "Every shop in Old Town paid Scorch this week. Take it back. It was mine anyway.",
						},
						{
							who = "scorch",
							text = "Somebody's knocking over my collectors? Find them. Toast them.",
						},
					},
				},
				-- 3. The bookkeeper bot with the Crew's ledger
				{
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the Torch Crew's bookkeeper bot",
					},
					at = "TorchGarage",
					lines = {
						{
							who = "Vanta",
							text = "His bookkeeper bot keeps the Crew's ledger. Every bribe, every fire. Get it.",
						},
						{
							who = "patch",
							text = "That bot's running for the Docks. Cut it off!",
						},
					},
				},
				-- 4. The ledger planted on Scorch's lieutenant; the Torch Crew's story as a comic page
				{
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Plant the ledger on Scorch's lieutenant",
					},
					at = "OpalRoom",
					scene = "scorchStory",
					lines = {
						{
							who = "Vanta",
							text = "Slip his ledger into his lieutenant's car. Sal will think his best man sold him out.",
						},
						{
							who = "scorch",
							text = "Who took my ledger?! Somebody in my own crew? Nobody trusts nobody till I find out!",
						},
					},
				},
				-- 5. The garage while the Crew fights itself
				{
					villain = {
						kind = "fight",
						home = true,
						squads = { { "BurglarBot", 3 }, { "Bomber", 2 } },
						text = "Scrap the Torch Crew's bots at the garage",
					},
					at = "TorchGarage",
					lines = {
						{
							who = "Vanta",
							text = "His crew is turning on itself. Hit the garage now, while nobody is watching his back.",
						},
						{
							who = "scorch",
							text = "My own garage? In MY town? Crew, light them up!",
						},
					},
				},
				-- 6. The finale in front of the garage: Sal Scorch in his magma suit
				{
					villain = {
						kind = "finale",
						enemy = "Redline", -- the suit and brain (a slim Fire racer); Scorch's look, name and title: dress
						dress = "Scorch",
						hpMult = 3,
						adds = { { "Bomber", 2 } },
						range = { 20, 60 },
						text = "Beat Sal Scorch in front of his own crew",
					},
					at = "TorchGarage",
					scene = "torchOut",
					lines = {
						{
							who = "scorch",
							text = "You work for the Duchess? Then tell her Old Town burns tonight. Starting with you!",
						},
						{
							who = "Vanta",
							text = "Beat him in front of his own crew. Nobody follows a boss who lost.",
						},
					},
				},
			},
		},
		-- Character line (nate's lore, build plan step 11): The Scoop. nate's draft: "a news reporter tries to get
		-- the truth out." Nora Bright, BHN 24's night reporter, keeps getting cut mid-sentence: a masked man in
		-- the control room, the Censor, decides what Brightharbor sees, and his blackout drones jam every screen
		-- that shows the rest. The Vigil find her vanished eyewitness, get her news van to the uplink and
		-- photograph the drones; the Dread Syndicate, promised every secret she never aired, grab the cut tapes,
		-- catch the bot with the control room key and sell a copy to a rival channel. Both hold the uplink on the
		-- studio roof while the story goes out, and fight the Censor live on air. Standalone: who the Censor
		-- works for is left open.
		{
			id = "TheScoop",
			bit = 12,
			name = "The Scoop",
			layer = "character",
			giver = "Nora",
			site = "Studio",
			unlock = { story = 6, level = 10, npc = true }, -- after Act 1's sixth mission; only from Nora
			villain = { name = "THE CENSOR", title = "HE DECIDES WHAT YOU SEE" },
			reward = { share = 3, title = "Front Page", style = "PressVest" },
			blurb = {
				hero = "Somebody cuts Brightharbor's news before it airs. Reporter Nora Bright wants it out.",
				villain = "A masked man decides what BHN 24 airs. A reporter will trade her secrets for help.",
			},
			lines = {
				offer = {
					hero = "Nora Bright, BHN 24. My stories keep getting cut, live, mid-sentence. I need someone the Censor can't scare.",
					villain = "You're not the kind I interview. But you get things done. Help me, and every secret I never aired is yours.",
				},
				resume = {
					hero = "Back for the story? Good. The Censor hasn't stopped, and neither have we.",
					villain = "Back? Good. The secrets are still yours once the story gets out.",
				},
				done = {
					hero = "The whole city saw it, live. No more cuts. That's the best story I ever ran. Thank you.",
					villain = "We're on air and the Censor's off it. A deal's a deal: every secret I never aired is yours.",
				},
			},
			steps = {
				-- 1. The BHN 24 news desk, the night a story goes black
				{
					hero = { kind = "talk", text = "Meet Nora Bright at BHN 24 Studios" },
					villain = { kind = "talk", text = "Hear Nora Bright out at BHN 24 Studios" },
					at = "Studio",
					scene = "newsDesk",
					lines = {
						{
							who = "Nora",
							hero = "Every time a story makes someone powerful look bad, the screen goes black. Every single time.",
							villain = "There's a man inside BHN 24 who decides what airs. He sits on a lot of secrets.",
						},
						{
							who = "patch",
							hero = "Wait, the news gets CUT? I thought my TV was just broken. Okay, I'm in.",
							villain = "A guy who controls the news? That's not a crook. That's the boss level.",
						},
					},
				},
				-- 2. The eyewitness from the cut story / the cut tapes
				{
					hero = {
						kind = "find",
						range = { 40, 140 },
						witness = true,
						text = "Find the eyewitness from the story that got cut",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 40, 140 },
						guards = { "ShieldBearer", 1 },
						text = "Grab the cut tapes off the courier bots",
					},
					at = "Studio",
					lines = {
						{
							who = "censor",
							text = "Some stories are too loud for Brightharbor. Turn them down.",
						},
						{
							who = "Nora",
							hero = "My eyewitness went quiet after the cut. Find her before someone else does.",
							villain = "The cut tapes go out on courier bots, to be shredded. Three of them. Grab them.",
						},
					},
				},
				-- 3. The news van to the uplink / the control room key
				{
					hero = {
						kind = "escort",
						goal = 160,
						speed = 9,
						near = 40,
						text = "Get Nora's news van to the uplink safely",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the bot with the control room key",
					},
					at = "Studio",
					lines = {
						{
							who = "censor",
							text = "A news van? How quaint. Drones, cut its signal. And its tyres.",
						},
						{
							who = "Nora",
							hero = "My van has the one uplink he can't cut. Keep it in one piece till we're set up.",
							villain = "The control room key rides on a runner bot. Catch it and we're inside.",
						},
					},
				},
				-- 4. The blackout drones on camera / a copy to a rival channel
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 30, 120 },
						text = "Photograph the blackout drones",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Sell a copy of the tapes to a rival channel",
					},
					at = "Studio",
					lines = {
						{
							who = "Nora",
							hero = "Those drones jam every screen on the block. Pictures, please. That's my proof.",
							villain = "The rival channel across town will pay for these. Then they'll air them. Everyone wins.",
						},
						{
							who = "patch",
							text = "Blackout drones! So that's why my cartoons cut out last Tuesday!",
						},
					},
				},
				-- 5. The uplink on the studio roof (both sides); the cut stories as a comic page
				{
					hero = {
						kind = "hold",
						seconds = 25,
						radius = 10,
						high = true,
						text = "Guard Nora's uplink on the studio roof",
						villainText = "Guard the uplink while the story goes live",
					},
					villain = "same",
					at = "Studio",
					scene = "cutStory",
					lines = {
						{
							who = "Nora",
							text = "Uplink's on the roof. Twenty-five seconds to reach every screen in the city. Hold it!",
						},
						{
							who = "censor",
							text = "Turn that off. TURN IT OFF. Nothing airs without me!",
						},
					},
				},
				-- 6. The finale live on air: the Censor in his shadow suit
				{
					hero = {
						kind = "finale",
						enemy = "MasqueARade", -- the suit and brain (a Shadow floater); the Censor's look, name and title: dress
						dress = "Censor",
						hpMult = 3,
						adds = { { "SparkDrone", 3 } },
						range = { 20, 60 },
						text = "Beat the Censor live on air",
						villainText = "Beat the Censor and take his secret files",
					},
					villain = "same",
					at = "Studio",
					scene = "onAir",
					lines = {
						{
							who = "censor",
							hero = "You think people want the truth? They want quiet. I give them quiet.",
							villain = "Secrets are worth more unseen. You of all people should know that.",
						},
						{
							who = "Nora",
							hero = "Camera's on you! Hit him hard, the whole city is watching!",
							villain = "Camera's rolling. Make it a good show and the files are yours.",
						},
					},
				},
			},
		},

		-- The origin lines (nate's lore, build plan step 11): one personal line per origin, offered only to heroes of
		-- that origin (unlock.origin, Config.Creator.origins). nate's drafts: lab "find the lab that woke you",
		-- alien "a signal from your bloodline", magic "the relic's last owner", tech "someone wants your suit
		-- back", training "your old master was taken". 6 quests each (the layer's 5 to 8), mostly standalone,
		-- each side its own flavour. All five end on the shared Spark lore: the origin never made the Spark, it
		-- only woke the one that was always there (each line's comic page ends on the same panel). Each finale
		-- villain wears a dress over an existing robot or costumed suit (no new enemy type).

		-- Lab origin: The Ashgrove Test. Ashgrove Labs paid volunteers to sit in the Kindler, a ring of light; on a
		-- Lab-Born hero's turn the machine lit up and woke their Spark, and the lab shut by morning. Now it runs
		-- again in secret: Doctor Holloway, its director, has no Spark and tests volunteers to learn to take one.
		-- The Vigil free the volunteers and smash the Kindlers; the Dread Syndicate steal the Kindling cells and
		-- sell the research. Both face Holloway in his shielded lab rig.
		{
			id = "AshgroveTest",
			bit = 13,
			name = "The Ashgrove Test",
			layer = "origin",
			giver = "Okafor",
			site = "Underlab",
			unlock = { origin = 1, story = 2, level = 5 }, -- Lab-Born heroes, after Act 1's Safehouse
			villain = { name = "DOCTOR HOLLOWAY", title = "DIRECTOR OF ASHGROVE LABS" },
			reward = { share = 3, title = "Test Passed", style = "KindlingCore" },
			blurb = {
				hero = "The lab that woke your Spark shut down overnight. Now its lights are back on.",
				villain = "The lab that woke your Spark is open again. Its research is worth a fortune.",
			},
			lines = {
				offer = {
					hero = "You're the one from the Ashgrove test. I was on shift that night. The lab is open again, and people go in.",
					villain = "You're the one from the Ashgrove test. The director owes us both, and his research sells.",
				},
				resume = {
					hero = "Back again? The volunteers are still in there. Let's finish this.",
					villain = "Back for the rest? Holloway's research won't steal itself.",
				},
				done = {
					hero = "The volunteers are home and the Kindlers are scrap. You passed the test. The real one.",
					villain = "The research is sold, the lab is dark and I got my back pay. Pleasure doing crimes.",
				},
			},
			steps = {
				-- 1. Dr. Okafor's story: the night of the test
				{
					hero = { kind = "talk", text = "Hear Dr. Okafor out at Ashgrove Labs" },
					villain = { kind = "talk", text = "Get Dr. Okafor's tip at Ashgrove Labs" },
					lines = {
						{
							who = "Okafor",
							hero = "The night of your test, the Kindler flashed and you lit up like a star. They shut the lab by morning.",
							villain = "The night of your test, the Kindler flashed and you lit up. Holloway hid it. I got fired.",
						},
						{
							who = "patch",
							hero = "Ashgrove's files were wiped the same week. Somebody really wanted that night forgotten.",
							villain = "Wiped files mean something worth hiding. Or worth selling.",
						},
					},
				},
				-- 2. A volunteer who ran / the courier with the director's keycard
				{
					hero = {
						kind = "find",
						range = { 100, 250 },
						witness = true,
						text = "Find a volunteer who ran from the lab",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the courier bot with the director's keycard",
					},
					lines = {
						{
							who = "patch",
							hero = "A volunteer got out last night, still glowing. Her phone pinged somewhere around here.",
							villain = "That courier bot carries Holloway's keycard. Catch it and every door in the lab opens.",
						},
					},
				},
				-- 3. Into the lab: Okafor's old badge / the Kindling cells on the loading dock
				{
					hero = {
						kind = "hold",
						seconds = 20,
						radius = 12,
						text = "Shield Dr. Okafor while she opens the lab",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "ShieldBearer", 1 },
						text = "Lift three Kindling cells from the loading dock",
					},
					lines = {
						{
							who = "Okafor",
							hero = "My old badge still works on the side door. Mostly. Keep the guard bots off me!",
							villain = "Kindling cells power the machine that woke you. Each one is worth a car.",
						},
						{
							who = "lodestar",
							hero = "A machine that wakes Sparks, back in business? I don't like it, kid. Watch your back in there.",
							villain = "Whatever you carry out of there, keep it away from people. That machine hurts folks.",
						},
					},
				},
				-- 4. Inside Ashgrove Labs: reception, the test chamber and the sublevel under it
				{
					hero = {
						kind = "pocket",
						layout = "ashlab",
						minutes = 12,
						text = "Get inside Ashgrove Labs",
						villainText = "Break into Ashgrove Labs",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "ShieldBearer", 2 }, { "BurglarBot", 2 } },
								text = "Clear the security bots from reception",
								villainText = "Scrap the security bots at the front desk",
							},
							{
								kind = "hold",
								at = "chamber",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "SparkDrone", 3 } },
								waveGap = 10,
								text = "Shield the volunteers in the test chamber",
								villainText = "Hold the chamber while the safe cracker runs",
							},
							{
								kind = "reach",
								at = "sublevel",
								text = "Take the sealed stairs to the sublevel",
								villainText = "Follow the stairs to the good stuff",
							},
							{
								kind = "break",
								list = "kindlers",
								points = 4,
								hits = 3,
								text = "Smash the Kindlers. Nobody else gets tested!",
								villainText = "Rip the Kindling cores out of the machines",
							},
							{
								kind = "boss",
								enemy = "Grappler",
								hpMult = 3,
								adds = { "SparkDrone", 2 },
								text = "Beat the lab's containment bot",
								villainText = "Scrap the containment bot for parts",
							},
						},
					},
					villain = "same",
					lines = {
						{
							who = "holloway",
							text = "Intruders in the test wing. Subject One, is that you? Come in. Let's finish your test.",
						},
					},
				},
				-- 5. Out with the volunteers / out with the cores; the truth about the Kindler
				{
					hero = { kind = "carry", range = { 80, 160 }, text = "Fly a volunteer home safe" },
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Rush the Kindling cores to your buyer",
					},
					scene = "kindlerTruth",
					lines = {
						{
							who = "Okafor",
							hero = "He tested hundreds. It only lit up people who already had a Spark. It never made one. Never.",
							villain = "It only ever woke a Spark someone already had. That's why he wants yours. Sell fast.",
						},
						{
							who = "holloway",
							text = "My Kindler woke them all. Not one Spark was mine. So I'll take the one I woke in you!",
						},
					},
				},
				-- 6. The finale: Doctor Holloway in his shielded lab rig at the lab's door
				{
					hero = {
						kind = "finale",
						enemy = "NullSentinel",
						dress = "Holloway",
						hpMult = 8,
						adds = { { "ShieldBearer", 2 }, { "SparkDrone", 2 } },
						range = { 60, 140 },
						text = "Stop Doctor Holloway. The test is over!",
						villainText = "Topple Holloway and take his lab",
					},
					villain = "same",
					scene = "hollowayRig",
					lines = {
						{
							who = "holloway",
							hero = "Every Spark I ever woke walked away from me. Not you, Subject One. You're coming back to the lab!",
							villain = "You took my cells, my files, my lab. Fine. I'll take the Spark my test woke in you!",
						},
					},
				},
			},
		},

		-- Alien origin: Starblood Calling. A song from the stars plays on Radio Hill's old mast, and only star blood
		-- hears it: an old pod, the ship a Star-Blooded hero's ancestor came down in long ago, has started to sing
		-- again. The Voidhound, an ancient star-hunting machine that followed that ship across the stars (not
		-- Crane's: standalone), hears it too. The Vigil boost the song, find the pod and guard its message; the
		-- Dread Syndicate grab the star-metal and steal the pod's core. Both face the Voidhound on the hill.
		{
			id = "StarbloodCalling",
			bit = 14,
			name = "Starblood Calling",
			layer = "origin",
			giver = "Ruth",
			site = "RadioMast",
			unlock = { origin = 2, story = 2, level = 5 }, -- Star-Blooded heroes, after Act 1's Safehouse
			villain = { name = "THE VOIDHOUND", title = "HUNTER FROM THE STARS" },
			reward = { share = 3, title = "Starborn", style = "StarfallWings" },
			blurb = {
				hero = "A song from the stars is playing on Radio Hill. Only star blood can hear it.",
				villain = "A song from the stars leads to star-metal nobody on Earth owns. Get there first.",
			},
			lines = {
				offer = {
					hero = "Radio Ruth. My old set has caught a song from the stars all week, and you're the only one who hums along.",
					villain = "Radio Ruth. Something up there is singing to you, and star-metal sells by the ounce.",
				},
				resume = {
					hero = "The song's still playing. Ready to follow it?",
					villain = "Still singing, still worth a fortune. Let's go.",
				},
				done = {
					hero = "The hunter is scrap and the song is quiet. Your people said hello, kid. Come back and visit.",
					villain = "Star-metal sold, hunter scrapped, and my radio's paid off. Nice doing business, starlight.",
				},
			},
			steps = {
				-- 1. Radio Ruth's story: the song on the old mast
				{
					hero = { kind = "talk", text = "Hear Radio Ruth out on Radio Hill" },
					villain = { kind = "talk", text = "Get Radio Ruth's tip on Radio Hill" },
					lines = {
						{
							who = "Ruth",
							hero = "Listen. That tune comes from the sky, and your Spark lights up every time it plays.",
							villain = "Hear that? A song from the stars. Wherever it leads, there's star-metal.",
						},
						{
							who = "patch",
							hero = "That signal isn't from any station on Earth. And it gets louder when YOU stand near the mast.",
							villain = "Whatever that signal comes from, nobody on Earth owns it yet. That makes it ours.",
						},
					},
				},
				-- 2. The hilltop beacon / the star-metal shards on the hillside
				{
					hero = { kind = "beacon", seconds = 20, text = "Boost the song at the hilltop beacon" },
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "BurglarBot", 1 },
						text = "Grab the star-metal shards on the hillside",
					},
					lines = {
						{
							who = "Ruth",
							hero = "Hold the beacon up top and my set can tune right in. Twenty seconds should do it.",
							villain = "Bits of star-metal fell all over this hill. Somebody else is picking them up too.",
						},
					},
				},
				-- 3. The hunter's drones arrive
				{
					hero = {
						kind = "fight",
						squads = { { "SparkDrone", 4 }, { "BurglarBot", 2 } },
						range = { 60, 150 },
						text = "Drive off the hunter drones on the hill",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the hunter drone with a star shard",
					},
					lines = {
						{
							who = "voidhound",
							text = "STAR BLOOD DETECTED. THE HUNT BEGINS. COLLECTION IS CERTAIN.",
						},
						{
							who = "patch",
							hero = "Those drones aren't from around here. They're tracking the song. They're tracking YOU.",
							villain = "Those drones are tracking the song, and the shards. Don't let them get away with yours.",
						},
					},
				},
				-- 4. The pod / the collector
				{
					hero = { kind = "find", range = { 100, 250 }, text = "Find the pod the song comes from" },
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Sell the star shards to a collector",
					},
					lines = {
						{
							who = "Ruth",
							hero = "The song is loudest past the hill. Something fell out there, a long, long time ago.",
							villain = "A collector's waiting at the drop. Star-metal, cash only, no questions.",
						},
					},
				},
				-- 5. The pod's message / the pod's core
				{
					hero = {
						kind = "hold",
						seconds = 25,
						radius = 12,
						text = "Guard the pod while it plays its message",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 70,
						time = 45,
						text = "Outrun the hunter with the pod's star core",
					},
					scene = "podMessage",
					lines = {
						{
							who = "Ruth",
							hero = "It's a message: 'Every Spark is one Spark. Our blood only woke yours.' Kid, your people knew.",
							villain = "The pod says every Spark is one Spark, and star blood woke yours. The hunter wants it. RUN.",
						},
					},
				},
				-- 6. The finale: the Voidhound lands on Radio Hill
				{
					hero = {
						kind = "finale",
						enemy = "Captain",
						dress = "Voidhound",
						hpMult = 14,
						adds = { { "SparkDrone", 3 } },
						range = { 60, 140 },
						text = "Stop the Voidhound. The hunt ends here!",
						villainText = "Scrap the Voidhound and sell its parts",
					},
					villain = "same",
					scene = "voidhoundLands",
					lines = {
						{
							who = "voidhound",
							hero = "ONE SPARK FROM THE STARS, STILL UNCLAIMED. HOLD STILL, STAR BLOOD.",
							villain = "THIEF WITH STAR BLOOD. DOUBLE BOUNTY. HOLD STILL.",
						},
					},
				},
			},
		},

		-- Magic origin: The Last Owner. A Relic-Bound hero's relic was Ambrose the Astonishing's, a stage magician
		-- who vanished on stage forty years ago. Auntie Moth, who sold it, says he is alive, hiding in Old Town, and
		-- his old rival Morrow the Mirage (a jealous illusionist with no Spark, in a powered rig of mirrors and
		-- wires) is hunting the relic. The Vigil find Ambrose, expose Morrow's robots and get him out; the Dread
		-- Syndicate rob Ambrose's hidden trunks and his vault. Both face Morrow's last trick.
		{
			id = "LastOwner",
			bit = 15,
			name = "The Last Owner",
			layer = "origin",
			giver = "Moth",
			site = "VintageCurios",
			unlock = { origin = 3, story = 2, level = 5 }, -- Relic-Bound heroes, after Act 1's Safehouse
			villain = { name = "MORROW THE MIRAGE", title = "THE JEALOUS ILLUSIONIST" },
			reward = { share = 3, title = "Relic Keeper", style = "MoonstoneCirclet" },
			blurb = {
				hero = "Your relic had an owner before you: Ambrose the Astonishing. Someone is hunting him.",
				villain = "Your relic's last owner hid forty years of stage gold. A rival wants it too.",
			},
			lines = {
				offer = {
					hero = "That relic picked you off my shelf, dear. Before you, it was Ambrose's. He's in trouble.",
					villain = "That relic was Ambrose the Astonishing's. He hid the rest of his fortune. All of it.",
				},
				resume = {
					hero = "Back again? Ambrose is counting on you. So am I.",
					villain = "Back for more gold? Ambrose hid plenty.",
				},
				done = {
					hero = "Ambrose is safe and Morrow's mirrors are in pieces. The relic chose well, dear.",
					villain = "Trunks emptied, vault cracked, Morrow scrapped. I'll take my cut in gold, dear.",
				},
			},
			steps = {
				-- 1. Auntie Moth's story: the relic's last owner
				{
					hero = { kind = "talk", text = "Hear Auntie Moth out at her curio shop" },
					villain = { kind = "talk", text = "Get Auntie Moth's tip at her curio shop" },
					lines = {
						{
							who = "Moth",
							hero = "Your relic belonged to Ambrose the Astonishing. He's alive, hiding in Old Town, and someone is hunting him.",
							villain = "Ambrose hid his trunks of stage gold all over Old Town. Forty years. Still locked.",
						},
						{
							who = "patch",
							hero = "Ambrose the Astonishing? Old posters say he vanished on stage forty years ago. Like, actually vanished.",
							villain = "Forty years of hidden stage gold? Somebody's about to get rich. Might as well be us.",
						},
					},
				},
				-- 2. Ambrose in hiding / his locked trunks
				{
					hero = {
						kind = "find",
						range = { 100, 250 },
						witness = true,
						text = "Find Ambrose, the relic's last owner",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "BurglarBot", 1 },
						text = "Pick the locks on Ambrose's hidden trunks",
					},
					lines = {
						{
							who = "Moth",
							hero = "Look for an old man feeding the pigeons, with playing cards up his sleeves.",
							villain = "Each trunk is locked with a trick. Each one is also full. Go on, dear.",
						},
					},
				},
				-- 3. Morrow's robots close in / the stagehand with the map
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 40, 140 },
						text = "Photograph the shadow bots stalking Ambrose",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the stagehand bot with Ambrose's map",
					},
					lines = {
						{
							who = "ambrose",
							hero = "So the relic found you. Good. My old rival Morrow hunts it, and his robots are everywhere.",
							villain = "After my trunks, are you? Ha! Morrow's robots want them too. And my relic.",
						},
						{
							who = "morrow",
							text = "Ambrose, old friend. Forty years in hiding. Give me the relic, and I'll make you vanish properly.",
						},
					},
				},
				-- 4. Out of Old Town / the stage gold
				{
					hero = {
						kind = "escort",
						goal = 160,
						speed = 9,
						near = 40,
						text = "Get Ambrose's old show van out of Old Town",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Fence Ambrose's stage gold at the drop",
					},
					lines = {
						{
							who = "lodestar",
							hero = "An old magician, a jealous rival and a relic. Get the old man somewhere safe. I'll watch the roofs.",
							villain = "Steal from the old man if you must. But if Morrow grabs him, you'll answer to me.",
						},
					},
				},
				-- 5. Morrow's troupe strikes / the race to the vault; the truth about the relic
				{
					hero = {
						kind = "fight",
						squads = { { "ShieldBearer", 1 }, { "BurglarBot", 3 } },
						range = { 60, 150 },
						text = "Stop Morrow's troupe grabbing Ambrose",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Beat Morrow's runners to the vault",
					},
					scene = "relicTruth",
					lines = {
						{
							who = "ambrose",
							hero = "The relic was never magic. It only woke the Spark I already had. Yours too. Morrow has none.",
							villain = "A secret, thief: the relic has no power. It only woke your Spark. Morrow can't stand it.",
						},
					},
				},
				-- 6. The finale: Morrow's last trick
				{
					hero = {
						kind = "finale",
						enemy = "MasqueARade",
						dress = "Morrow",
						hpMult = 3,
						adds = { { "BurglarBot", 2 }, { "SparkDrone", 2 } },
						range = { 60, 140 },
						text = "Break Morrow's last trick!",
						villainText = "Rob Morrow blind at his own show",
					},
					villain = "same",
					scene = "morrowCurtain",
					lines = {
						{
							who = "morrow",
							hero = "My greatest trick! The relic's new owner... VANISHES!",
							villain = "A thief at my show? Watch closely. Your pockets are about to vanish!",
						},
					},
				},
			},
		},

		-- Tech origin: Suit Recall. A Suit-Forged hero built the suit in Tinker Tess's garage from scrapyard junk and
		-- a dead power core that only lit up when they strapped in. Now Clawback, a repo king whose robots
		-- "recover" anything that glows, says the core is his. The Vigil chase off the repo bots, save Tess's parts
		-- and expose the fake repo orders; the Dread Syndicate rob Clawback's crew and his yard. Both face Clawback
		-- in his hooked repo rig.
		{
			id = "SuitRecall",
			bit = 16,
			name = "Suit Recall",
			layer = "origin",
			giver = "Tess",
			site = "Workshop",
			unlock = { origin = 4, story = 2, level = 5 }, -- Suit-Forged heroes, after Act 1's Safehouse
			villain = { name = "CLAWBACK", title = "THE REPO KING" },
			reward = { share = 3, title = "No Returns", style = "ClawbackGauntlet" },
			blurb = {
				hero = "The scrap core in your suit lit up when you put it on. Now a repo king wants it.",
				villain = "A repo king wants your suit back. His yard is full of other people's things.",
			},
			lines = {
				offer = {
					hero = "Remember the dead core we pulled from the scrap? A repo king says it's his. His robots took my garage door!",
					villain = "Clawback's repo crew wants your suit. His yard is stuffed with stolen gear. Shopping trip?",
				},
				resume = {
					hero = "Back? Good. The repo bots haven't given up, and neither have I.",
					villain = "Back for another load? The yard isn't empty yet.",
				},
				done = {
					hero = "Clawback's rig is scrap and the core stays with you. No returns, no refunds.",
					villain = "His yard's empty, his rig's scrap and my garage has a new door. Nice work.",
				},
			},
			steps = {
				-- 1. Tinker Tess's story: the suit from the scrapyard
				{
					hero = { kind = "talk", text = "Hear Tinker Tess out at her garage" },
					villain = { kind = "talk", text = "Get Tinker Tess's tip at her garage" },
					lines = {
						{
							who = "Tess",
							hero = "That core was dead scrap until you strapped in. Then it lit up. Now a repo crew wants it back.",
							villain = "Clawback repossesses anything that glows. Your suit glows. So does everything in his yard.",
						},
						{
							who = "patch",
							hero = "Clawback Recovery? They 'recover' stuff that was never theirs. Lots of it.",
							villain = "Clawback Recovery. A yard full of other people's stuff and not nearly enough guards.",
						},
					},
				},
				-- 2. The repo bots at the garage / the parts they took
				{
					hero = {
						kind = "fight",
						squads = { { "BurglarBot", 3 }, { "BruteBot", 1 } },
						range = { 40, 120 },
						text = "Chase the repo bots away from the garage",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "BruteBot", 1 },
						text = "Steal back the parts the repo bots took",
					},
					lines = {
						{
							who = "clawback",
							text = "This is Clawback Recovery. That suit is overdue. Hand it over, or we take the whole garage.",
						},
					},
				},
				-- 3. Tess's parts truck / the tow truck keys
				{
					hero = {
						kind = "escort",
						goal = 160,
						speed = 9,
						near = 40,
						text = "Drive Tess's parts truck somewhere safe",
					},
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Catch the repo bot with the tow truck keys",
					},
					lines = {
						{
							who = "Tess",
							hero = "Every spare part I own is in that truck. Keep the tow bots off it!",
							villain = "Their tow truck keys are on that runner bot. A tow truck of our very own.",
						},
					},
				},
				-- 4. The fake repo orders / the tow truck's parts
				{
					hero = {
						kind = "photo",
						count = 3,
						range = { 40, 140 },
						text = "Get the repo bots' fake orders on camera",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Sell the tow truck's parts at the drop",
					},
					lines = {
						{
							who = "patch",
							hero = "Their 'repo orders' are fakes. Snap the bots carrying them and I'll put the proof online.",
							villain = "Tow trucks sell by the piece. The buyer's waiting. Don't scratch it.",
						},
					},
				},
				-- 5. Locking the core / the yard's stolen gear; the truth about the core
				{
					hero = {
						kind = "hold",
						seconds = 20,
						radius = 12,
						text = "Guard Tess while she locks down your core",
					},
					villain = {
						kind = "race",
						checkpoints = 4,
						gap = 60,
						time = 45,
						text = "Rush the yard's stolen gear past the drones",
					},
					scene = "coreTruth",
					lines = {
						{
							who = "Tess",
							hero = "The core was dead when I found it. It never made your power. It only woke the Spark already in you.",
							villain = "Clawback thinks the core makes the power. Nope. It only woke your Spark. Without you it's a doorstop.",
						},
					},
				},
				-- 6. The finale: Clawback in his repo rig
				{
					hero = {
						kind = "finale",
						enemy = "Grappler",
						dress = "Clawback",
						hpMult = 14,
						adds = { { "BruteBot", 1 }, { "BurglarBot", 2 } },
						range = { 60, 140 },
						text = "Stop Clawback. This suit is not for sale!",
						villainText = "Repossess Clawback's rig for scrap",
					},
					villain = "same",
					scene = "clawbackClaim",
					lines = {
						{
							who = "clawback",
							hero = "Final notice! That suit, that core, that Spark. Clawback Recovery takes it ALL back!",
							villain = "You robbed my yard? Then you're overdue, thief. I'm repossessing YOU!",
						},
					},
				},
			},
		},

		-- Training origin: The Taken Master. A Self-Made hero trained for years at Master Hoshi's dojo on Willow
		-- Street until their Spark woke one dawn. Now Hoshi has been taken by Gale, his angriest old student,
		-- whose Spark never woke: he built a speed rig instead and runs a rich fight school, the Iron Hall, and he
		-- wants the "secret" he thinks Hoshi hid. The Vigil find the witness, free Hoshi and fly him home; the Dread
		-- Syndicate rob the school's purses and trophies and ransom Hoshi's scroll. Both face Gale.
		{
			id = "TakenMaster",
			bit = 17,
			name = "The Taken Master",
			layer = "origin",
			giver = "Kiko",
			site = "WillowDojo",
			unlock = { origin = 5, story = 2, level = 5 }, -- Self-Made heroes, after Act 1's Safehouse
			villain = { name = "GALE", title = "THE MASTER'S FALLEN STUDENT" },
			reward = { share = 3, title = "Lesson Learned", style = "MastersBelt" },
			blurb = {
				hero = "Master Hoshi trained you until your Spark woke. Now someone has taken him.",
				villain = "Your old master was taken. His kidnapper's fight school runs on prize money.",
			},
			lines = {
				offer = {
					hero = "You're one of Master Hoshi's old students! He's gone. A man in a racing rig took him in the night.",
					villain = "You trained with Master Hoshi too? He's been taken. The man who did it runs a rich fight school.",
				},
				resume = {
					hero = "Back to train? Master Hoshi would say: again, and better.",
					villain = "Back for more of Gale's prize money? There's plenty.",
				},
				done = {
					hero = "Master Hoshi is home, and Gale's rig is cold. He says you've learned the last lesson.",
					villain = "Gale's school is broke and the master is home. You're still a bad student, though.",
				},
			},
			steps = {
				-- 1. Kiko's story: the dojo, the master, the dawn your Spark woke
				{
					hero = { kind = "talk", text = "Hear Kiko out at the Willow Street Dojo" },
					villain = { kind = "talk", text = "Get Kiko's tip at the Willow Street Dojo" },
					lines = {
						{
							who = "Kiko",
							hero = "Master Hoshi says you trained longer than anyone, until your Spark woke one dawn. Please find him!",
							villain = "Master Hoshi always said you'd go your own way. The man who took him calls himself Gale.",
						},
						{
							who = "lodestar",
							hero = "Hoshi? He taught half the old heroes how to fall without breaking. Whoever took him wants something.",
							villain = "Hoshi taught me to fall without breaking, years back. Help the kid, whatever your reasons.",
						},
					},
				},
				-- 2. The witness / the prize purses
				{
					hero = {
						kind = "find",
						range = { 100, 250 },
						witness = true,
						text = "Find the student who saw the master taken",
					},
					villain = {
						kind = "fetch",
						count = 3,
						range = { 60, 180 },
						guards = { "BruteBot", 1 },
						text = "Swipe three prize purses from Gale's fighters",
					},
					lines = {
						{
							who = "Kiko",
							hero = "One of the big kids saw everything. He ran and hid. He'll trust you.",
							villain = "Gale pays his fighters in cash. The purses are all over the street.",
						},
					},
				},
				-- 3. The master's old rooftop course, both sides
				{
					hero = {
						kind = "race",
						checkpoints = 5,
						gap = 60,
						time = 50,
						text = "Run Master Hoshi's old training course",
						villainText = "Run the course faster than Gale's runners",
					},
					villain = "same",
					lines = {
						{
							who = "Kiko",
							hero = "This was his favourite course. Run it like he taught you. His trail starts at the end.",
							villain = "Gale's runners use the master's old course. Beat them to the end and follow them.",
						},
					},
				},
				-- 4. Inside the Iron Hall: the locker room, the training floor and the inner dojo under it
				{
					hero = {
						kind = "pocket",
						layout = "ironhall",
						minutes = 12,
						text = "Break into Gale's Iron Hall",
						villainText = "Rob Gale's Iron Hall",
						steps = {
							{
								kind = "defeat",
								room = 1,
								squads = { { "BruteBot", 2 }, { "BurglarBot", 2 } },
								text = "Beat the sparring bots in the locker room",
								villainText = "Scrap the sparring bots by the lockers",
							},
							{
								kind = "hold",
								at = "hall",
								points = 1,
								seconds = 20,
								radius = 16,
								waves = { { "BurglarBot", 3 } },
								waveGap = 10,
								text = "Hold the training floor for the captive students",
								villainText = "Hold the floor while the safe drill runs",
							},
							{
								kind = "reach",
								at = "inner",
								text = "Take the iron stairs down to the inner dojo",
								villainText = "Follow the stairs to the trophy vault",
							},
							{
								kind = "break",
								list = "chains",
								points = 4,
								hits = 3,
								text = "Break the chains holding Master Hoshi",
								villainText = "Break the chains off the prize cage",
							},
							{
								kind = "boss",
								enemy = "NullSentinel",
								hpMult = 3,
								adds = { "BurglarBot", 2 },
								text = "Beat the Iron Gatekeeper. Strike its side!",
								villainText = "Scrap the Iron Gatekeeper",
							},
						},
					},
					villain = "same",
					lines = {
						{
							who = "hoshi",
							hero = "You came. Good. Remember: a wall has two sides, and so does every guard. Go around it.",
							villain = "You came for gold, not for me. Still. Hit that iron guard from the side, student.",
						},
					},
				},
				-- 5. Master Hoshi home / his scroll at the drop; the master's last lesson
				{
					hero = { kind = "carry", range = { 80, 160 }, text = "Fly Master Hoshi home to the dojo" },
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Ransom Master Hoshi's scroll at the drop",
					},
					scene = "masterLesson",
					lines = {
						{
							who = "hoshi",
							hero = "Gale thinks I hid a secret that makes a Spark. There is none. Training only wakes what is there.",
							villain = "Ransom my scroll? It says only this: no one gives you a Spark. Training wakes what is there.",
						},
						{
							who = "gale",
							text = "You took the old man back? Then fight me, and I'll beat his secret out of you!",
						},
					},
				},
				-- 6. The finale: Gale in his racing rig
				{
					hero = {
						kind = "finale",
						enemy = "Redline",
						dress = "Gale",
						hpMult = 3,
						adds = { { "BruteBot", 2 } },
						range = { 60, 140 },
						text = "Beat Gale. Show him the last lesson!",
						villainText = "Beat Gale and take his school",
					},
					villain = "same",
					scene = "galeChallenge",
					lines = {
						{
							who = "gale",
							hero = "Hoshi's favourite! I trained harder than you, and my Spark never woke. So I built one. Fight me!",
							villain = "A thief from Hoshi's dojo? You're no better than me. Let's see whose fists are faster!",
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
