-- Rogues (spec: Collections and records > Rogues File, in the Journal: "Every enemy and villain with an
-- outline for unbeaten ones; a gold page for beating a boss at high difficulty"). Pure data; Shared.RoguesFile
-- holds the rules, RoguesService fills the pages and Ui.RoguesPage draws them as the Journal's ROGUES tab.
-- * Every page has a fixed bit in the account's 128-bit profile.rogues (ProfileSchema.SMALL_WORDS words), so
--   NEVER move or reuse a bit: add new rows in the free bits of their group's range. The world bosses keep
--   their Config.Boss `rogues` bits (1 to 3, set by BossService since M6; a test checks they match).
--   Ranges: 0 unused; 1-7 world bosses; 9-15 their gold pages; 16-47 robots; 48-63 famous fakes and the
--   evil twin; 64-119 side quest finale villains; 120-127 the collection milestones already paid.
-- * Names come from the game's own data: a robot's Config.Enemies name, a fake's name and fake.title, a
--   villain's finale name card (its dress or the chain's villain card), a boss's Config.Boss name and its
--   Config.Cinema.nameCard title. `blurb` is the page's one fixed line and `where` the outline's hint (a
--   robot that swaps into street fights adds "from level N" from Config.Enemies.variety). DRAFT TEXT: the
--   blurbs and hints are Claude's, for nate's OK (Tasks).
-- * Pages fill server side from the defeat hooks: a robot or fake from EnemyService.Killed (the hero who
--   beat it; a dressed finale robot fills its villain's page instead), a villain when its side quest finale
--   is won (every member of the group), a boss from BossService.Rewarded (beaten, any tier). A gold page:
--   a beaten boss whose fight was at `gold.level` or higher, as a Contributor or the MVP.
-- * Milestones: at `n` pages (or all of them) the account gets one existing earnable creator piece (a
--   "drop" piece, so it is also found in Epic and Legendary drops). Looks only; nothing is sold.
-- * Portraits (art pass 2026-11-18): `portraits` holds each page's uploaded image id (a case-file card drawn from
--   the game's own look: art/blender/rogues.py then art/rogues/portraits.py, art/export/rogues/Rogue_<Id>.png
--   and Rogue_<Boss>_Gold.png). 0 until nate uploads it; until then the page draws the Kit shapes in the robot's
--   own colours. An unbeaten page always keeps the black silhouette. PLACEHOLDER ART until nate approves the
--   cards (Tasks "Placeholder art").
return {
	-- a page's beaten count stops here (the page shows "999+" past 999)
	countMax = 65535,
	-- the rogues_page analytics event (Shared.AnalyticsSchema): once per page per account, the moment it is
	-- first filled (the page kind and gold 0/1; value: pages filled). Interim pick 2026-11-18, nate to OK;
	-- false: no event, as before
	analytics = true,
	groups = {
		{ id = "robots", name = "ROBOTS" },
		{ id = "fakes", name = "FAMOUS FAKES" },
		{ id = "villains", name = "VILLAINS" },
		{ id = "bosses", name = "WORLD BOSSES" },
	},
	-- Config.Enemies kinds, one page each (in Config.Enemies.order)
	robots = {
		{
			kind = "SparkDrone",
			bit = 16,
			where = "Patrols the whole city",
			blurb = "A jet-boot trooper that rains three-shot bursts from above. Close in fast!",
		},
		{
			kind = "BurglarBot",
			bit = 17,
			where = "Street crimes all over the city",
			blurb = "Grabs the loot and runs for it. Corner it and it fires back.",
		},
		{
			kind = "SneakBot",
			bit = 18,
			where = "Alleys and rooftops",
			blurb = "Cloaks, creeps up and strikes from behind. Watch for the shimmer.",
		},
		{
			kind = "BruteBot",
			bit = 19,
			where = "Street fights",
			blurb = "Slow, huge and loud. Step out of the red ring before it slams.",
		},
		{
			kind = "Turret",
			bit = 20,
			where = "Robot camps and guard posts",
			blurb = "Bolted down with an arm cannon. No knock, pull or float will budge it.",
		},
		{
			kind = "NullSentinel",
			bit = 21,
			where = "Robot camps and missions",
			blurb = "Guards the front with a big shield. Hit it from the side!",
		},
		{
			kind = "Diver",
			bit = 22,
			where = "Under the sea",
			blurb = "A frogman android with a jet pack and a glass helmet.",
		},
		{
			kind = "Anchor",
			bit = 23,
			where = "The seabed",
			blurb = "A heavy diving suit that stomps the seabed. Keep swimming.",
		},
		{
			kind = "TorpedoSentry",
			bit = 24,
			where = "The seabed",
			blurb = "Fires slow torpedoes that turn after you. Make them miss.",
		},
		{
			kind = "ShieldBearer",
			bit = 25,
			where = "Street fights",
			blurb = "A riot shield wall that covers the robots behind it. Go round!",
		},
		{
			kind = "Captain",
			bit = 26,
			where = "Big street fights",
			blurb = "Hangs back and rallies its squad. Take it out and they falter.",
		},
		{
			kind = "Sniper",
			bit = 27,
			where = "Street fights",
			blurb = "A red laser marks its target. Move once it locks!",
		},
		{
			kind = "Bomber",
			bit = 28,
			where = "Street fights",
			blurb = "Lobs grenades right where you stand. See a red ring? Run.",
		},
		{
			kind = "MedicUnit",
			bit = 29,
			where = "Street fights",
			blurb = "Patches up hurt robots with a green beam. Down it first.",
		},
		{
			kind = "Swarmer",
			bit = 30,
			where = "Street fights",
			blurb = "Small, fast and never alone: packs of six that lunge and nip.",
		},
		{
			kind = "Mimic",
			bit = 31,
			where = "Hiding in the crowd",
			blurb = "Strolls like a citizen until a hero gets close. Then it springs!",
		},
		{
			kind = "Interceptor",
			bit = 32,
			where = "The skies",
			blurb = "Hunts heroes in the air. Its net drops you out of the sky.",
		},
		{
			kind = "Grappler",
			bit = 33,
			where = "Street fights",
			blurb = "Hooks a hero, reels them in, then punches. Dodge the hook.",
		},
		{
			kind = "WindupToy",
			bit = 34,
			where = "Wind-Up Lane, in the Suburbs",
			blurb = "Knee-high clockwork that marches up, hops in and nips your ankles.",
		},
		{
			kind = "SaltDog",
			bit = 35,
			where = "The Salt Dogs, on the Coast",
			blurb = "A robot pirate of the Salt Dogs crew. All swagger, all bolts.",
		},
	},
	-- the famous fakes and the evil twin (Config.Enemies kinds with `fake`); a title from fake.title, or `title`
	fakes = {
		{
			kind = "Radiant",
			bit = 48,
			where = "The story",
			blurb = "The city's golden flyer: light bolts, then a dive. Not so golden inside.",
		},
		{
			kind = "Bulwark",
			bit = 49,
			where = "The story",
			blurb = "A giant behind a tower shield. Unbreakable, they said. They were wrong.",
		},
		{
			kind = "Skylance",
			bit = 50,
			where = "The story",
			blurb = "Sights a hero, throws a spear, dashes aside. Fast, but fake.",
		},
		{
			kind = "EvilTwin",
			bit = 51,
			-- the Your double event card's title (Config.Cinema.nameCard.events.YourDouble)
			title = "A FAKE WEARING YOUR FACE",
			where = "The story, and a rare city event",
			blurb = "Wears your look and fights with your powers. How rude!",
		},
	},
	-- each side quest chain's finale villain (the last step's foe; phase 2 = its encore), by Config.SideQuests id
	villains = {
		{
			id = "HeadmasterHalo",
			bit = 64,
			chain = "HeroAcademy",
			phase = 1,
			blurb = "Runs a free hero school with a very secret basement. Class dismissed!",
		},
		{
			id = "Redline",
			bit = 65,
			chain = "GalaHeist",
			phase = 1,
			blurb = "The masked crew's getaway racer. Nobody passes him on the last lap. Almost.",
		},
		{
			id = "MasqueARade",
			bit = 66,
			chain = "GalaHeist",
			phase = 2,
			blurb = "Plans the city's biggest heists and never misses a curtain call.",
		},
		{
			id = "Toymaker",
			bit = 67,
			chain = "WindUpLane",
			phase = 1,
			blurb = "An old inventor with a clockwork army and one very big toy.",
		},
		{
			id = "Bramblebeast",
			bit = 68,
			chain = "HarvestKing",
			phase = 1,
			blurb = "The King's crop beast: pumpkin head, bramble crown, terrible manners.",
		},
		{
			id = "HarvestKing",
			bit = 69,
			chain = "HarvestKing",
			phase = 2,
			blurb = "His Spark grows anything, monsters too. He rides a thresher suit.",
		},
		{
			id = "CaptainBrine",
			bit = 70,
			chain = "SaltDogs",
			phase = 1,
			blurb = "Captain of the robot pirates, in a powered diving rig. Yo ho, no!",
		},
		{
			id = "Pitboss",
			bit = 71,
			chain = "ThePit",
			phase = 1,
			blurb = "The quarry fight pit's stone-skinned showman. He wears his own belt.",
		},
		{
			id = "Tidewright",
			bit = 72,
			chain = "SunkenCity",
			phase = 1,
			blurb = "Velmara's last guardian: bronze, coral and a very long memory.",
		},
		{
			id = "Vesper",
			bit = 73,
			chain = "LastPartner",
			phase = 1,
			blurb = "Came back wearing a famous face. Under the starfield: metal.",
		},
		{
			id = "Catchpole",
			bit = 74,
			chain = "FindingLark",
			phase = 1,
			blurb = "Nets Spark kids for the Pound. Tonight the catcher got caught.",
		},
		{
			id = "Scorch",
			bit = 75,
			chain = "HostileTakeover",
			phase = 1,
			blurb = "Boss of the Torch Crew, in a suit of glowing magma. Hot temper.",
		},
		{
			id = "Censor",
			bit = 76,
			chain = "TheScoop",
			phase = 1,
			blurb = "A black tuxedo, a long black cape and a blackout for every story.",
		},
		{
			id = "Holloway",
			bit = 77,
			chain = "AshgroveTest",
			phase = 1,
			blurb = "Ashgrove Labs' director. No Spark of his own, so he tries to take one.",
		},
		{
			id = "Voidhound",
			bit = 78,
			chain = "StarbloodCalling",
			phase = 1,
			blurb = "An ancient hunting machine from the stars, following an old song.",
		},
		{
			id = "Morrow",
			bit = 79,
			chain = "LastOwner",
			phase = 1,
			blurb = "A jealous old illusionist. What you see is never what you get.",
		},
		{
			id = "Clawback",
			bit = 80,
			chain = "SuitRecall",
			phase = 1,
			blurb = "The repo king in a hooked exo frame. Everything you own, he wants back.",
		},
		{
			id = "Gale",
			bit = 81,
			chain = "TakenMaster",
			phase = 1,
			blurb = "The master's angriest old student. Fast hands, no honour.",
		},
	},
	-- the world bosses (Config.Boss.order): `bit` is Config.Boss's `rogues`, `gold` the gold page;
	-- colors = the portrait's suit, trim and eye (PLACEHOLDER ART)
	bosses = {
		{
			boss = "RustjawPrime",
			bit = 1,
			gold = 9,
			colors = { { 150, 90, 50 }, { 90, 90, 100 }, { 255, 140, 40 } },
			where = "World boss: Downtown",
			blurb = "A walking junkyard of wrecked cars. Hit the glowing weak points!",
		},
		{
			boss = "LumenMaw",
			bit = 2,
			gold = 10,
			colors = { { 40, 30, 70 }, { 120, 90, 200 }, { 255, 250, 200 } },
			where = "World boss: the Old Quarry",
			blurb = "A night creature that swallows light. Hit it until it shines.",
		},
		{
			boss = "LeviathanEngine",
			bit = 3,
			gold = 11,
			colors = { { 150, 110, 50 }, { 90, 120, 110 }, { 120, 255, 230 } },
			where = "World boss: over the Trench",
			blurb = "An ancient sea machine of brass and stone. It surfaces hungry.",
		},
	},
	-- a gold page: the boss beaten in a fight at this level or higher (BossService's fight level, the Heroic
	-- band's floor), as one of these tiers
	gold = {
		level = 40,
		tiers = { mvp = true, contributor = true },
		hint = "Gold page: beat it at level 40+ as a Contributor or MVP",
	},
	-- collection rewards, each once per account (its bit marks it paid): n pages, or every page (all)
	milestones = {
		{ n = 10, bit = 124, piece = "Antenna Helm" },
		{ n = 25, bit = 125, piece = "Circuit Suit" },
		{ all = true, bit = 126, piece = "Ember Aura" },
	},
	-- each page's portrait image id by group and page id (its Config.Enemies kind, villain id or boss id); gold:
	-- a world boss's gold page card. 0 = not uploaded yet (art/upload/make_package.py packs art/export/rogues,
	-- apply_ids.py fills these)
	portraits = {
		robots = {
			SparkDrone = 0,
			BurglarBot = 0,
			SneakBot = 0,
			BruteBot = 0,
			Turret = 0,
			NullSentinel = 0,
			Diver = 0,
			Anchor = 0,
			TorpedoSentry = 0,
			ShieldBearer = 0,
			Captain = 0,
			Sniper = 0,
			Bomber = 0,
			MedicUnit = 0,
			Swarmer = 0,
			Mimic = 0,
			Interceptor = 0,
			Grappler = 0,
			WindupToy = 0,
			SaltDog = 0,
		},
		fakes = {
			Radiant = 0,
			Bulwark = 0,
			Skylance = 0,
			EvilTwin = 0,
		},
		villains = {
			HeadmasterHalo = 0,
			Redline = 0,
			MasqueARade = 0,
			Toymaker = 0,
			Bramblebeast = 0,
			HarvestKing = 0,
			CaptainBrine = 0,
			Pitboss = 0,
			Tidewright = 0,
			Vesper = 0,
			Catchpole = 0,
			Scorch = 0,
			Censor = 0,
			Holloway = 0,
			Voidhound = 0,
			Morrow = 0,
			Clawback = 0,
			Gale = 0,
		},
		bosses = {
			RustjawPrime = 0,
			LumenMaw = 0,
			LeviathanEngine = 0,
		},
		gold = {
			RustjawPrime = 0,
			LumenMaw = 0,
			LeviathanEngine = 0,
		},
	},
	firstBit = { robots = 16, fakes = 48, villains = 64, bosses = 1, gold = 9, milestones = 120 },
	lastBit = { robots = 47, fakes = 63, villains = 119, bosses = 7, gold = 15, milestones = 127 },
}
