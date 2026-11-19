-- Lore pages (nate, 2026-11-19: "maybe something like lore books wouldn't be bad. We have all these landmarks with
-- lore behind them but the game never really tells you. For example the crater."). Pure data; Shared.LorePlan holds
-- the rules, LoreService picks pages up and pays the sets, LoreClient draws the glowing books and the caption card,
-- and the Journal's LORE tab lists them by district.
-- * A page lies at a landmark with lore: a side quest site's door (Config.SideQuests.sites), a fast-travel beacon
--   (Config.World.beacons, on its roof), a landmark's middle (Config.World.landmarks) or Uptown's tallest tower.
--   LorePlan.spots puts it on flat open ground (or roof, or seabed) near that anchor, the same on every server and
--   every week's seed for the hub (outskirts sites move with the farm and shore lots the side quests use).
-- * Walk, fly or swim within `reach` to pick it up; the book glows within `glow` studs on your device only (a page
--   already read stays read: saved on the account, profile.lore bits).
-- * The caption card reads like a comic caption box: the page's title, its `lines` and who `by` says it.
-- * Sets: every page of a district pays that district's title (titleBase + set index; nothing that changes a
--   number in a fight); every page pays the Lore Shelf (Config.Hq.props 23) and the full set's title.
-- Text: every line here is taken from existing lore (nate's lore doc and the comic pages in Config.Cinema), word for
-- word where a page says `from`; pages marked `draft = true` carry new wording for nate to OK (Tasks.md).
-- Bits: a page's `bit` is its place in profile.lore (1 to 64); never reuse or move one.
return {
	bits = 64,
	reach = 7, -- studs: this close picks a page up (the server's check)
	glow = 140, -- studs: the book is drawn on your device this close (and only while you have not read it)
	chime = 45, -- studs: the soft chime as you come near a page you have not read
	checkEvery = 0.4, -- seconds between the server's pickup checks
	titleBase = 7000, -- a district set's title id (Config.Boards 6000s and Config.Daily 5000s sit below)
	allTitle = 7099, -- the full set's title id
	allName = "Keeper of Brightharbor",
	shelfProp = 23, -- Config.Hq.props: the Lore Shelf in your HQ, for every page
	renown = { page = 150, set = 600, all = 2500 }, -- Renown a page, a district's set, the whole lot
	-- where a page may stand round its anchor: rings of `ring` studs apart out to `far`, `spokes` points a ring;
	-- a spot is flat within `flat` studs over `probe` either way, and within `band` of the anchor's own height
	place = {
		first = 7,
		ring = 4,
		far = 44,
		spokes = 16,
		flat = 1.2,
		probe = 3,
		band = 3,
		float = 2.6,
		seabed = 3,
	},
	-- the districts in the Journal's order: id, the name shown, the set's title
	districts = {
		{ id = "Downtown", name = "Downtown", title = "Downtown Historian" },
		{ id = "Uptown", name = "Uptown", title = "Uptown Insider" },
		{ id = "OldTown", name = "Old Town", title = "Old Town Regular" },
		{ id = "Docks", name = "The Docks", title = "Dockside Snoop" },
		{ id = "Suburbs", name = "The Suburbs", title = "Lane Watcher" },
		{ id = "Farmland", name = "Farmland", title = "Field Reporter" },
		{ id = "Coast", name = "The Coast", title = "Salt Reader" },
		{ id = "Crater", name = "The Crater", title = "Crater Witness" },
		{ id = "RadioHill", name = "Radio Hill", title = "Star Listener" },
		{ id = "OldQuarry", name = "The Old Quarry", title = "Pit Historian" },
		{ id = "Underwater", name = "Velmara", title = "Deep Archivist" },
	},
	-- at: { site = id } a side quest site's door, { beacon = id }, { landmark = id, dx, dz } studs from its middle,
	-- { uptown = true } Uptown's landmark tower's foot. by: who speaks the caption (fixed text).
	pages = {
		{
			bit = 1,
			id = "HeroHall",
			district = "Downtown",
			at = { landmark = "plaza", dx = -44, dz = 0 },
			title = "CRANE'S HERO HALL",
			lines = {
				"Crane's Hero Hall is the tallest thing Downtown, the beacon on its roof.",
				"The heroes on my stage are the best this city has. Trust them.",
			},
			by = "SILAS CRANE, ON BHN 24",
			from = "Config.World.beacons (Crane's Hero Hall) and Config.Cinema.news.crane",
		},
		{
			bit = 2,
			id = "Plaza",
			district = "Downtown",
			at = { landmark = "plaza", dx = 0, dz = 52 },
			title = "THE CEREMONY",
			lines = {
				"Brightharbor: a bright city by the sea, cheering for its famous heroes.",
				"Crane gives out his medals here, on a stage, with a crowd and cameras.",
			},
			by = "THE CITY GUIDE",
			draft = true,
			from = "Config.Cinema.comic.pages.intro and the lore doc's ceremony",
		},
		{
			bit = 3,
			id = "Academy",
			district = "Downtown",
			at = { site = "Academy" },
			title = "HALO ACADEMY",
			lines = {
				"Halo Academy said I was special. Free lessons for kids with Sparks.",
				"Headmaster Halo picked me for the honours class. Everyone clapped.",
			},
			by = "WREN, A STUDENT",
			from = "Config.Cinema.comic.pages (Wren's first week)",
		},
		{
			bit = 4,
			id = "Gala",
			district = "Downtown",
			at = { site = "Gala" },
			title = "THE MUSEUM GALA",
			lines = {
				"A costumed crew hits the museum, then the opera, then the bank.",
				"Every time, they get away by racing across the rooftops.",
			},
			by = "BHN 24",
			draft = true,
			from = "the lore doc's Gala Heist + Rooftop Racers pick",
		},
		{
			bit = 5,
			id = "NightOwl",
			district = "Downtown",
			at = { site = "NightOwl" },
			title = "THE NIGHT OWL DINER",
			lines = {
				"For twelve years Lodestar and Vesper kept Brightharbor's night sky safe.",
				"After every patrol: the Night Owl diner, two coffees, the booth by the window.",
			},
			by = "THE EVENING STAR",
			from = "Config.Cinema.comic.pages (The Evening Star)",
		},
		{
			bit = 6,
			id = "Billboard",
			district = "Uptown",
			at = { uptown = true },
			title = "HEROES YOU CAN TRUST",
			lines = {
				"Crane's biggest billboard hangs on Uptown's tallest tower: HEROES YOU CAN TRUST.",
				"A registered hero is a safe hero. Register your powers today.",
			},
			by = "SILAS CRANE, ON BHN 24",
			from = "the lore doc's billboard and Config.Cinema.news.crane",
		},
		{
			bit = 7,
			id = "Bank",
			district = "Uptown",
			at = { site = "Bank" },
			title = "BRIGHTHARBOR BANK",
			lines = {
				"The Dread Syndicate wants the city for itself.",
				"Heists fund the takeover, and Uptown keeps the fattest vaults.",
			},
			by = "A VIGIL FILE",
			draft = true,
			from = "the lore doc (Sides and quests: heists fund the takeover)",
		},
		{
			bit = 8,
			id = "OpalRoom",
			district = "OldTown",
			at = { site = "OpalRoom" },
			title = "THE OPAL ROOM",
			lines = {
				"For twenty years Duchess Vanta ran Old Town from the Opal Room.",
				"Pay the Crew, or your shop catches fire. Nobody in Old Town says no twice.",
			},
			by = "THE TORCH CREW",
			from = "Config.Cinema.comic.pages (The Torch Crew)",
		},
		{
			bit = 9,
			id = "TorchGarage",
			district = "OldTown",
			at = { site = "TorchGarage" },
			title = "THE TORCH CREW GARAGE",
			lines = {
				"Sal Scorch started with one tow truck and a lighter.",
				"Now his Torch Crew owns the garages.",
			},
			by = "OLD TOWN TALK",
			from = "Config.Cinema.comic.pages (The Torch Crew)",
		},
		{
			bit = 10,
			id = "Curios",
			district = "OldTown",
			at = { site = "VintageCurios" },
			title = "AMBROSE THE ASTONISHING",
			lines = {
				"Forty years ago, Ambrose the Astonishing filled every theatre in Old Town.",
				"His secret was a little relic. Whenever he held it, his Spark woke up.",
			},
			by = "MOTH & MOON CURIOS",
			from = "Config.Cinema.comic.pages (The Last Owner)",
		},
		{
			bit = 11,
			id = "Gantry",
			district = "Docks",
			at = { beacon = 3 },
			title = "CRANE CRATES",
			lines = {
				"Crane Industries makes robots: security drones and police bots.",
				"Everyone knows those machines. Nobody asks what else comes off the boats.",
			},
			by = "A DOCKHAND",
			draft = true,
			from = "the lore doc (the public knows Crane makes robots)",
		},
		{
			bit = 12,
			id = "Pound",
			district = "Docks",
			at = { site = "Pound" },
			title = "THE SPARK POUND",
			lines = {
				"Catchpole hunts Sparks for the bounty on their heads.",
				"Twelve cages in a Docks warehouse. A collar on every Spark, so none can fight back.",
			},
			by = "PATCH, ON THE RADIO",
			from = "Config.Cinema.comic.pages (The Spark Pound)",
		},
		{
			bit = 13,
			id = "ToyShop",
			district = "Suburbs",
			at = { site = "ToyShop" },
			title = "TICK-TOCK TOYS",
			lines = {
				"Tick-Tock Toys was my favourite shop. The Toymaker said I was special.",
				"He gave me a wind-up bear. When I cried, every toy on the street woke up!",
			},
			by = "TOBY, AGE 8",
			from = "Config.Cinema.comic.pages (Toby and the Wind-Up Bear)",
		},
		{
			bit = 14,
			id = "Farm",
			district = "Farmland",
			at = { site = "Homestead" },
			title = "FURROW FARM",
			lines = {
				"Three summers without rain. Every farm out here was drying up.",
				"Then my Spark woke up. Anything I touched would grow. Anything!",
			},
			by = "THE HARVEST KING",
			from = "Config.Cinema.comic.pages (The Summer the Rain Stopped)",
		},
		{
			bit = 15,
			id = "Pier",
			district = "Coast",
			at = { site = "GullPier" },
			title = "GULL POINT PIER",
			lines = {
				"Brine was a salvage diver off Gull Point. One day his Spark woke in the deep.",
				"He pulled old diving robots off the sea floor and made them his crew.",
			},
			by = "THE LEGEND OF CAPTAIN BRINE",
			from = "Config.Cinema.comic.pages (The Legend of Captain Brine)",
		},
		{
			bit = 16,
			id = "CraterRim",
			district = "Crater",
			at = { beacon = 5 },
			title = "WHERE THE OLD HEROES FELL",
			lines = {
				"Years ago, the Crater was a busy city block.",
				"The old heroes made their last stand there against the machines.",
			},
			by = "THE OLD HEROES' LAST STAND",
			from = "Config.Cinema.comic.pages.lastStand",
		},
		{
			bit = 17,
			id = "CraterLab",
			district = "Crater",
			at = { landmark = "CometCrater", dx = -20, dz = 22 },
			title = "THE CRANE LAB",
			lines = {
				"Mid-battle, a Crane Industries lab went up in a flash.",
				"When the dust settled, the old heroes were gone. Only the Crater was left.",
			},
			by = "THE OLD HEROES' LAST STAND",
			from = "Config.Cinema.comic.pages.lastStand",
		},
		{
			bit = 18,
			id = "RadioHill",
			district = "RadioHill",
			at = { site = "RadioMast" },
			title = "STARBLOOD",
			lines = {
				"Long ago a little ship fell from the stars and came down past Radio Hill.",
				"Its pilot stayed, and had a family. The star blood was passed down and down.",
			},
			by = "RADIO HILL",
			from = "Config.Cinema.comic.pages (Starblood)",
		},
		{
			bit = 19,
			id = "Quarry",
			district = "OldQuarry",
			at = { site = "QuarryGate" },
			title = "THE BOSS OF THE PIT",
			lines = {
				"When the Old Quarry shut down, the Gravel family kept the mine tunnels under it.",
				"Lose in the Pit and you owe the family. So you fight again. Nobody walks out.",
			},
			by = "THE OLD QUARRY",
			from = "Config.Cinema.comic.pages (The Boss of the Pit)",
		},
		{
			bit = 20,
			id = "Velmara",
			district = "Underwater",
			at = { site = "DrownedGate" },
			title = "VELMARA",
			lines = {
				"Long ago Velmara stood in the sun, a city of bronze towers by the bay.",
				"Then a great storm drowned it. Its people swam for the shore and never came back.",
			},
			by = "THE LAST GUARDIAN OF VELMARA",
			from = "Config.Cinema.comic.pages (The Last Guardian of Velmara)",
		},
		{
			bit = 21,
			id = "Tidewright",
			district = "Underwater",
			at = { site = "TideSpire" },
			title = "THE TIDEWRIGHT",
			lines = {
				"They left the Tidewright to keep the city safe.",
				"It waited, and waited, and slept.",
			},
			by = "THE LAST GUARDIAN OF VELMARA",
			from = "Config.Cinema.comic.pages (The Last Guardian of Velmara)",
		},
	},
	-- the book's look on the device (Shared.LoreBookKit builds it from parts; PLACEHOLDER ART until the Blender
	-- book is uploaded: art/blender/lorebook.py): colours per district, the spin and bob, the collect burst
	look = {
		spin = 40, -- degrees a second about up
		bob = { height = 0.5, period = 2.4 },
		light = { range = 14, brightness = 2.2 },
		cover = {
			Downtown = { 40, 70, 150 },
			Uptown = { 200, 110, 60 },
			OldTown = { 120, 60, 130 },
			Docks = { 40, 110, 120 },
			Suburbs = { 210, 80, 90 },
			Farmland = { 120, 140, 50 },
			Coast = { 30, 100, 160 },
			Crater = { 30, 50, 80 },
			RadioHill = { 90, 70, 170 },
			OldQuarry = { 110, 80, 60 },
			Underwater = { 30, 130, 140 },
		},
		gold = { 255, 205, 90 },
		glow = { 255, 236, 160 },
		page = { 250, 244, 225 },
	},
}
