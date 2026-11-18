-- Badges and titles (spec: Hero MMO features > Badges and titles; H7). Pure data, tuned in the playtest.
-- About 120 badges, earned by doing things; every badge's name is also a title you can show under your name.
-- Each badge counts one key to n: a counter BadgeService bumps (profile.mmo.counts; "max" keys keep the
-- highest value seen) or a fact read from the save when it checks (story clears, styles owned, Fame rank).
-- The save's bits (profile.mmo.badges, 256): each group owns the bits from its `at` up to the next group's,
-- and a badge's bit is at + its place in the list. Only ever add a badge at the end of its group's list
-- (within its range), never reorder or delete one (Shared.BadgeRules; the tests check the ranges).
-- Six groups give an accolade when every badge in them is earned: an aura, a name plate trim or an emote,
-- never stats. Names are fixed text (no free text).
local function b(id: string, name: string, key: string, n: number, hint: string): { [string]: any }
	return { id = id, name = name, key = key, n = n, hint = hint }
end

return {
	bits = 256, -- profile.mmo.badges is 8 words (bits 0 to 255)
	titleBase = 1000, -- a badge's title id is titleBase + its bit (story and Fame titles keep 1 to 255)
	baneBase = 2000, -- "Bane of <nemesis>": baneBase + the index in mmo.banes (H5)
	stampTime = 2.2, -- seconds the badge stamp stays on screen
	squadToast = 120, -- squadmates this close (studs) see your badge toast too
	checkEvery = 1, -- seconds between position checks (explore badges)
	-- max keys: the counter keeps the highest value, not a sum (heights)
	maxKeys = { height = true },

	groups = {
		{
			id = "explore",
			at = 0,
			name = "Explore",
			accolade = { kind = "aura", id = "compassGlow", name = "Compass Glow", color = { 120, 220, 255 } },
			badges = {
				b("downtown", "Downtown Regular", "area:Downtown", 1, "Walk the streets of Downtown"),
				b("docks", "Dock Hand", "area:Docks", 1, "Visit the Docks"),
				b("oldtown", "Old Town Local", "area:OldTown", 1, "Visit Old Town"),
				b("uptown", "Uptown Climber", "area:Uptown", 1, "Visit Uptown"),
				b("crater", "Crater Gazer", "area:CometCrater", 1, "Stand in the Crater"),
				b("radiohill", "Hilltop Listener", "area:RadioHill", 1, "Climb Radio Hill"),
				b("quarry", "Quarry Diver", "area:OldQuarry", 1, "Go down into the Old Quarry"),
				b("suburbs", "Cul-de-sac Cruiser", "area:suburbs", 1, "Fly out to the suburbs"),
				b("farmland", "Field Flyer", "area:farmland", 1, "Reach the farmland"),
				b("coast", "Coast Runner", "area:coast", 1, "Reach the coast at the edge of the map"),
				b("basin", "Harbour Splash", "deep:basin", 1, "Dive into the harbour"),
				b("line", "Line Rider", "deep:line", 1, "Swim into the Sunken Line"),
				b("shelf", "Reef Reader", "deep:shelf", 1, "Swim over the Coral Shelf"),
				b("trench", "Trench Peeker", "deep:trench", 1, "Swim over the Trench"),
				b("sea", "Open Water", "deep:sea", 1, "Swim out into the open sea"),
				b("trenchfloor", "Bottom Toucher", "trenchFloor", 1, "Touch the Trench floor"),
				b("height60", "Off the Ground", "height", 60, "Get 60 studs up"),
				b("height150", "Rooftop Hopper", "height", 150, "Get 150 studs up"),
				b("height300", "Skyline Sitter", "height", 300, "Get 300 studs up"),
				b("height500", "Cloud Kisser", "height", 500, "Get 500 studs up"),
				b("height640", "Beacon Topper", "height", 640, "Get as high as the top of Crane's Hero Hall"),
				b("height800", "Top of the World", "height", 800, "Reach the top of the tallest tower"),
				b("safe4", "Safe Bet", "safehouses", 4, "Find 4 safehouses"),
				b("safe8", "Safe Keeper", "safehouses", 8, "Find 8 safehouses"),
				b("safeall", "Every Safe Place", "safehousesAll", 1, "Find every safehouse"),
				b("beacon4", "Beacon Spotter", "beacons", 4, "Light 4 beacons"),
				b("beacon8", "Beacon Runner", "beacons", 8, "Light 8 beacons"),
				b("beaconall", "Every Light On", "beaconsAll", 1, "Light every beacon"),
				b("underwater", "Held Breath", "underwater", 60, "Spend 60 seconds underwater"),
				b("atlas", "Brightharbor Atlas", "group:explore", 29, "Earn every other Explore badge"),
			},
		},
		{
			id = "defeat",
			at = 40,
			name = "Defeat",
			accolade = {
				kind = "trim",
				id = "scrapTrim",
				name = "Scrap Iron Trim",
				color = { 170, 176, 186 },
			},
			badges = {
				b("trooper100", "Trooper Toppler", "kill:SparkDrone", 100, "Defeat 100 Crane Troopers"),
				b("burglar100", "Burglar Buster", "kill:BurglarBot", 100, "Defeat 100 Burglar Bots"),
				b("sneak100", "Sneak Spotter", "kill:SneakBot", 100, "Defeat 100 Sneak Bots"),
				b("brute100", "Brute Breaker", "kill:BruteBot", 100, "Defeat 100 Brute Bots"),
				b("sentry100", "Sentry Silencer", "kill:Turret", 100, "Defeat 100 Sentries"),
				b("warden100", "Warden Walker", "kill:NullSentinel", 100, "Defeat 100 Wardens"),
				b("trooper1k", "Trooper Nightmare", "kill:SparkDrone", 1000, "Defeat 1,000 Crane Troopers"),
				b("burglar1k", "Vault Guardian", "kill:BurglarBot", 1000, "Defeat 1,000 Burglar Bots"),
				b("sneak1k", "Eyes Everywhere", "kill:SneakBot", 1000, "Defeat 1,000 Sneak Bots"),
				b("brute1k", "Bigger Than Brutes", "kill:BruteBot", 1000, "Defeat 1,000 Brute Bots"),
				b("sentry1k", "Sentry Scrapper", "kill:Turret", 1000, "Defeat 1,000 Sentries"),
				b("warden1k", "Shield Splitter", "kill:NullSentinel", 1000, "Defeat 1,000 Wardens"),
				b("robots1k", "Scrap Collector", "kills", 1000, "Defeat 1,000 robots"),
				b("robots10k", "Scrapyard King", "kills", 10000, "Defeat 10,000 robots"),
				b("elites10", "Elite Hunter", "elites", 10, "Defeat 10 elite robots"),
				b("rustjaw", "Jaw Breaker", "boss:RustjawPrime", 1, "Defeat Rustjaw Prime"),
				b("lumenmaw", "Light Snuffer", "boss:LumenMaw", 1, "Defeat the Lumen Maw"),
				b("leviathan", "Engine Stopper", "boss:LeviathanEngine", 1, "Defeat the Leviathan Engine"),
				-- WP5: the Suspicious Hero incident (draft name: nate to OK)
				b("fakes10", "Fake Spotter", "fakes", 10, "Unmask 10 fake heroes in the street"),
			},
		},
		{
			id = "rescue",
			at = 64,
			name = "Rescue",
			accolade = { kind = "emote", id = "thumbsUp", name = "Double Thumbs Up", emote = 16 },
			badges = {
				b("rescue10", "Helping Hand", "rescues", 10, "Carry 10 citizens to safety"),
				b("rescue100", "Street Guardian", "rescues", 100, "Carry 100 citizens to safety"),
				b("rescue1k", "City's Shield", "rescues", 1000, "Carry 1,000 citizens to safety"),
				b("cat1", "Cat Person", "cats", 1, "Get a cat down safely"),
				b("cat10", "Nine Lives Saver", "cats", 10, "Get 10 cats down safely"),
				b("rider1", "Last Stop Hero", "riders", 1, "Bring a Sunken Line rider up to the quay"),
				b("rider10", "Line Lifeguard", "riders", 10, "Bring 10 Sunken Line riders up"),
				b("rider50", "Deep Rescuer", "riders", 50, "Bring 50 Sunken Line riders up"),
				b("revive10", "Back on Your Feet", "revives", 10, "Revive 10 Downed heroes"),
				b("revive50", "Field Medic", "revives", 50, "Revive 50 Downed heroes"),
			},
		},
		{
			id = "story",
			at = 80,
			name = "Story",
			accolade = { kind = "trim", id = "inkTrim", name = "Comic Ink Trim", color = { 30, 30, 40 } },
			badges = {
				b("ceremony", "Ceremony Survivor", "mission:1", 1, "Get through the Ceremony"),
				b("safehouse", "Gone Underground", "mission:2", 1, "Clear Safehouse"),
				b("framed", "Framed", "mission:3", 1, "Clear Framed"),
				b("copy", "Seen Double", "mission:4", 1, "Clear The Copy"),
				b("signal", "Signal Boost", "mission:5", 1, "Clear The Signal"),
				b("live", "Live on Air", "mission:6", 1, "Clear Live"),
				b(
					"choice1",
					"Two Ways Framed",
					"bothChoices:1",
					1,
					"Make both picks in Framed (on any heroes)"
				),
				b("choice2", "Two Ways Signal", "bothChoices:2", 1, "Make both picks in The Signal"),
				b("choice3", "Two Ways Copy", "bothChoices:3", 1, "Make both picks in The Copy"),
				b("quests", "Odd Jobs Done", "quests", 1, "Finish every side quest"),
				b("vigil", "Sworn to the Vigil", "act1:hero", 1, "Finish Act 1 with the Vigil"),
				b(
					"syndicate",
					"Made in the Syndicate",
					"act1:villain",
					1,
					"Finish Act 1 with the Dread Syndicate"
				),
			},
		},
		{
			id = "combat",
			at = 104,
			name = "Combat",
			accolade = { kind = "aura", id = "guardSpark", name = "Guard Spark", color = { 150, 205, 255 } },
			badges = {
				b("block1", "Shields Up", "blocks", 1, "Block a hit"),
				b("block500", "Brick Wall", "blocks", 500, "Block 500 hits"),
				b("perfect10", "Good Timing", "perfects", 10, "Land 10 perfect blocks"),
				b("perfect100", "Perfect Hundred", "perfects", 100, "Land 100 perfect blocks"),
				b("cut50", "Cut Off", "interrupts", 50, "Interrupt 50 wind-ups"),
				b("break25", "Guard Crusher", "breaks", 25, "Break 25 blocks"),
				b("throw1", "Heave Ho", "throws", 1, "Throw something"),
				b("throw100", "Throw Pro", "throws", 100, "Throw 100 things"),
				b("heavy10", "Heavy Lifter", "heavyThrows", 10, "Throw 10 heavy things"),
				b(
					"carboss",
					"Car Trouble",
					"carAtBoss",
					1,
					"Hit a robot with a thrown car in a world boss fight"
				),
				b("awaken25", "Wide Awake", "awakens", 25, "Awaken 25 times"),
				b("awaken100", "Always Awake", "awakens", 100, "Awaken 100 times"),
			},
		},
		{
			id = "groups",
			at = 128,
			name = "Groups",
			accolade = { kind = "emote", id = "huddle", name = "Team Huddle", emote = 17 },
			badges = {
				b("tf1", "Long Night Done", "tf:1", 1, "Finish Meridian's Long Night"),
				b("tf2", "Heist Pulled", "tf:2", 1, "Finish The Margrave's Heist"),
				b("tf10", "Task Force Regular", "tfClears", 10, "Finish 10 task forces"),
				b("tfspeed", "Speed Run", "tfSpeed", 1, "Finish a task force in under 20 minutes"),
				b("tffull", "Full House", "tfFull", 1, "Finish a task force with a squad of 4"),
				b("sidekick1", "Sidekick", "sidekickClears", 1, "Clear a mission as a sidekick"),
				b("sidekick10", "Trusty Sidekick", "sidekickClears", 10, "Clear 10 missions as a sidekick"),
				b("mentor10", "Mentor", "mentorClears", 10, "Clear 10 missions as the mentor of a sidekick"),
				b("squad1", "Squad Up", "squadMissions", 1, "Clear a mission with a squad"),
				b("squad25", "Squad Goals", "squadMissions", 25, "Clear 25 missions with a squad"),
				b("squadinc25", "Team Players", "squadIncidents", 25, "Clear 25 incidents with squadmates"),
				b("mentorline", "Mentor's Pride", "mentorLines", 1, "Finish a mentor's quest line"),
			},
		},
		{
			id = "nemesis",
			at = 152,
			name = "Nemesis",
			badges = {
				b("nemmet", "Marked", "nemesisMet", 1, "Meet your nemesis"),
				b("bane1", "First Showdown", "bane:1", 1, "Win a Showdown"),
				b("bane2", "Rank Two Down", "bane:2", 1, "Beat a rank 2 nemesis"),
				b("bane3", "Rank Three Down", "bane:3", 1, "Beat a rank 3 nemesis"),
				b("bane4", "Rank Four Down", "bane:4", 1, "Beat a rank 4 nemesis"),
				b("bane5", "Nemesis Ender", "bane:5", 1, "Beat a rank 5 nemesis"),
			},
		},
		{
			id = "showoff",
			at = 168,
			name = "Show-off",
			badges = {
				b("contest1", "Stage Debut", "contestEntries", 1, "Step onto a costume contest stage"),
				b("contest10", "Stage Regular", "contestEntries", 10, "Enter 10 costume contests"),
				b("podium5", "Podium Regular", "contestPodiums", 5, "Place in the top 3 of 5 contests"),
				b("win1", "Best Dressed", "contestWins", 1, "Win a costume contest"),
				b("win5", "Style Icon", "contestWins", 5, "Win 5 costume contests"),
				b("set1", "Collector", "fullSets", 1, "Finish a collection"),
				b("set6", "Curator", "fullSets", 6, "Finish 6 collections"),
				b("set12", "Museum Piece", "fullSets", 12, "Finish every collection"),
				b("styles50", "Wardrobe", "styles", 50, "Own 50 styles"),
				b("emotes10", "Expressive", "emotes", 10, "Own 10 emotes"),
			},
		},
		{
			id = "pvp",
			at = 192,
			name = "PvP",
			badges = {
				b("fame2", "Getting Noticed", "fameRank", 2, "Reach Fame or Infamy rank 2"),
				b("fame4", "Name in Lights", "fameRank", 4, "Reach Fame or Infamy rank 4"),
				b("fame6", "Talk of the Town", "fameRank", 6, "Reach Fame or Infamy rank 6"),
				b("fame8", "Household Name", "fameRank", 8, "Reach Fame or Infamy rank 8"),
				b("fame10", "Legend of the Line", "fameRank", 10, "Reach the top Fame or Infamy rank"),
				b("pvp1", "First Win", "pvpWins", 1, "Win a PvP fight"),
				b("pvp10", "Contender", "pvpWins", 10, "Win 10 PvP fights"),
				b("pvp100", "Champion", "pvpWins", 100, "Win 100 PvP fights"),
				b("crater10", "Crater Brawler", "craterWins", 10, "Win 10 fights in the Crater"),
				b("crater50", "Crater King", "craterWins", 50, "Win 50 fights in the Crater"),
			},
		},
		{
			-- H8: the weekly episodes; badge e is the season's episode e (EpisodeRules), finished in any season
			id = "episodes",
			at = 216,
			name = "Episodes",
			badges = {
				b("ep1", "Opening Night Crew", "episode:1", 1, "Finish an episode in week 1 of a season"),
				b("ep2", "Lights Out Crew", "episode:2", 1, "Finish an episode in week 2 of a season"),
				b("ep3", "High Tide Crew", "episode:3", 1, "Finish an episode in week 3 of a season"),
				b("ep4", "Sky Freight Crew", "episode:4", 1, "Finish an episode in week 4 of a season"),
				b("ep5", "Vault Week Crew", "episode:5", 1, "Finish an episode in week 5 of a season"),
				b("ep6", "Bridge Out Crew", "episode:6", 1, "Finish an episode in week 6 of a season"),
				b("ep7", "Rooftop Crew", "episode:7", 1, "Finish an episode in week 7 of a season"),
				b("ep8", "Finale Crew", "episode:8", 1, "Finish an episode in week 8 of a season"),
			},
		},
	},
}
