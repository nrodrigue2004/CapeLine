-- Incidents (spec: Schedulers > Incident spawner; Opening and story > Incidents). 30 s to 2 min jobs spawned
-- around each hero. Templates are data: a list of steps, each one of
--   defeat  robots to beat: { kind, min, max } rows, rolled when the incident starts
--   rescue  citizens (or a cat) stuck at the site to carry to its drop pad (no citizen is ever hurt)
--   hold    stand at the spot for `seconds` (more heroes go faster)
--   object  a thing to break or stop: HP is `hits` hits of a hero's Power at the zone level
--   runner  a Velvet Paw bot that runs a roof (or street) path; beat it before it gets away
-- and the kinds added 2026-11-17 (nate: "way more content to keep players playing"):
--   nest    robots up on a roof (a "nest" spot): climb up and beat them all
--   leader  a warband: beat its `leader` and the rest scatter (the escort rows are not needed)
--   find    a robot hiding in a crowd of `crowd` citizens (the Mimic): find it and beat it
--   convoy  `n` robots of `enemy` driving a street route at `speed`: beat them all before the end
--   barrage Bombers shell `huddles` groups of citizens every `every` s (a red ring for `warn` s): stand
--           within `cover` of the ring to block a shell; block `blocks` (or beat the Bombers) before more
--           than `misses` land
--   tug     a robot (the Grappler) hauls a car `dist` studs at `speed`: beat it before the car is gone
-- and (WP5, gap G13: the lore's "some heroes are secretly robots; players spot and unmask them")
--   unmask  a costumed "hero" posing in a crowd of `crowd` citizens is one of the robot fakes: crack its mask
--           (the fakes' 50% crack, Config.Enemies.fakes.crack). It wears one of the `dress` costumes (below)
--           over a fake's suit (its fighting style), never a famous fake's own look; it poses until hit.
-- A step row with `side` runs only for that side (a both-sides template's side-flavoured goal), and a defeat
-- row with `keep` fights the fake the step before brought instead of spawning robots.
-- A row { kind, min, max, fallbackKind, fallbackMin, fallbackMax } names a fallback used when its type is off
-- (Config.Enemies.<Kind>.on) or not unlocked at the zone level yet (Config.Enemies.variety.swaps levels); a
-- template's `requires` types must be on and unlocked or the template is skipped. `text` on a step is the
-- tracker's line (villainText for villains); without it the kind's line below is shown. Fixed text only.
-- where: the kind of spot it needs (street, tower, tram, sign, roof, crane, nest, any). side: hero, villain
-- or both; in "both" templates villains see villainName and play the same mechanics. (tune)
return {
	spawner = {
		perHero = 2, -- every hero keeps 2 incidents within `radius`
		radius = 300,
		minDistance = 60, -- spawned at least this far away, so it is a short flight
		refill = { 3, 10 }, -- seconds until a cleared one is replaced (spec: within 10 s)
		maxActive = 90, -- per server
		sendRadius = 450, -- players this close get Incident.Spawn and Incident.Update
		updateRate = 2, -- Incident.Update per second
		helpRadius = 90, -- heroes this close at the clear who took part share the reward
		abandonAfter = 45, -- an incident nobody has come near for this long is replaced
		ownerFar = 600, -- or its hero has flown this far away
	},
	medal = { gold = 0.5, silver = 0.8 }, -- cleared within this share of the time limit
	objectPowerLevel = true, -- object HP scales with the zone level through Power = 30 + 6 x L
	rescueRange = 12, -- spec: Rescue.Pick range 12
	dropRadius = 14, -- carry a citizen into the pad's circle
	holdRate = { first = 1, each = 0.5, max = 2 }, -- hold speed with 1, 2, 3+ heroes
	beatRadius = 150, -- heroes this close hear and see a step's beat (Toast "beat")
	-- props a hold step can stand under, and object models by label (PLACEHOLDER ART: plain parts)
	props = { "Scaffold", "Load", "Crates" },
	objects = { "Tram", "Relay", "Valve" },
	convoyGap = 9, -- studs between convoy robots on their route
	convoyLeg = 40, -- studs per leg of the convoy's street route
	convoyWait = 0.25, -- the convoy's speed while no hero is within 120 studs (they floor it once spotted)
	capRetry = 3, -- seconds between tries when the server cap left a fight step with no robots at all
	-- the tracker's line for each step kind (a step's own `text` wins); squad: robots are its goal
	kinds = {
		defeat = { text = "Beat the robots", squad = true },
		rescue = { text = "Carry them to the pad" },
		hold = { text = "Hold the ring" },
		object = { text = "Break it" },
		runner = { text = "Catch the runner" },
		nest = { text = "Clear the roof", squad = true },
		leader = { text = "Down the leader", squad = true },
		find = { text = "Find the robot", squad = true },
		convoy = { text = "Stop the convoy", squad = true },
		barrage = { text = "Shield the citizens", squad = true },
		tug = { text = "Stop the tow", squad = true },
		unmask = { text = "Unmask the fake hero" },
	},
	-- beats: a step's big moments, each a toast line and an existing juice action (its sound, plus its
	-- visual where Juice draws one); sent to the heroes within beatRadius
	beats = {
		heroic = { text = "HEROIC INCIDENT NEARBY", juice = "rally" },
		nestCleared = { text = "NEST CLEARED!", juice = "revive" },
		leaderDown = { text = "LEADER DOWN: THE WARBAND SCATTERS!", juice = "revive" },
		found = { text = "FOUND IT!", juice = "reveal" },
		convoyStopped = { text = "CONVOY STOPPED!", juice = "revive" },
		shellBlocked = { text = "SHIELDED!", juice = "revive" },
		shellMissed = { text = "A shell landed: the citizens scatter", juice = "grenadeBoom" },
		barrageOver = { text = "BARRAGE OVER!", juice = "revive" },
		towStopped = { text = "TOW CUT!", juice = "revive" },
		-- WP5: the Suspicious Hero's moments
		fakeCracked = { text = "THE MASK CRACKS: IT'S A ROBOT!", juice = "unmask" },
		fakeScrapped = { text = "FAKE SCRAPPED! THE CROWD CHEERS!", juice = "revive" },
		panicSpread = { text = "PANIC IN THE STREETS!", juice = "grenadeBoom" },
	},
	order = {
		"RobotHeist",
		"TowerFire",
		"RunawayTram",
		"FallingSign",
		"RooftopChase",
		"CatOnCrane",
		"RaidPrep",
		"VaultBreach",
		"ShardCrate",
		"CommSabotage",
		"SniperNest",
		"MedicConvoy",
		"CaptainWarband",
		"MimicCrowd",
		"BomberBarrage",
		"GrapplerTow",
		"ScaffoldCollapse",
		"CraneLoad",
		"WaterMain",
		"DroneSwarm",
		"ShieldWall",
		"SkyAmbush",
		"DepotRaid",
		"SignalJam",
		"SuspiciousHero", -- WP5
	},
	templates = {
		RobotHeist = {
			num = 1,
			name = "Robot heist",
			side = "hero",
			where = "street",
			time = 90,
			text = "Stop the {BurglarBot}s",
			steps = { { kind = "defeat", enemies = { { "BurglarBot", 4, 8 } } } },
		},
		TowerFire = {
			num = 2,
			name = "Tower fire",
			villainName = "Smoke cover",
			side = "both",
			where = "tower",
			time = 120,
			text = "Carry the 3 citizens off the balconies",
			villainText = "Get the 3 witnesses clear of the smoke",
			steps = { { kind = "rescue", count = 3, at = "balcony" } },
		},
		RunawayTram = {
			num = 3,
			name = "Runaway tram",
			villainName = "Tram grab",
			side = "both",
			where = "tram",
			time = 60,
			text = "Brake the tram before the gap",
			villainText = "Stop the tram and take its cargo",
			steps = { { kind = "object", hits = 14, label = "Tram", moving = 7 } }, -- moving: studs/s to the gap
		},
		FallingSign = {
			num = 4,
			name = "Falling sign",
			villainName = "Loose billboard",
			side = "both",
			where = "sign",
			time = 40,
			text = "Hold the billboard up",
			villainText = "Hold the billboard while the crowd clears",
			steps = { { kind = "hold", seconds = 5, radius = 12 } },
		},
		RooftopChase = {
			num = 5,
			name = "Rooftop chase",
			villainName = "Rival runner",
			side = "both",
			where = "roof",
			time = 60,
			text = "Catch the Velvet Paw bot",
			villainText = "Catch the Vigil courier bot",
			steps = { { kind = "runner", enemy = "SneakBot", hops = 6, speed = 26 } },
		},
		CatOnCrane = {
			num = 6,
			name = "Cat on a crane",
			villainName = "Cat on a crane",
			side = "both",
			where = "crane",
			time = 75,
			text = "Bring the cat down safely",
			villainText = "Bring the cat down (even villains like cats)",
			steps = { { kind = "rescue", count = 1, at = "crane", cat = true } },
		},
		RaidPrep = {
			num = 7,
			name = "Raid prep",
			villainName = "Raid prep",
			side = "both",
			where = "any",
			time = 90,
			prep = true, -- only while a world boss is counting down; each clear weakens the boss
			text = "Destroy the drones powering the boss",
			steps = { { kind = "defeat", enemies = { { "SparkDrone", 3, 4 } } } },
		},
		VaultBreach = {
			num = 8,
			name = "Vault breach",
			side = "villain",
			where = "street",
			time = 110,
			text = "Beat the vault guards, then crack it",
			steps = {
				{ kind = "defeat", enemies = { { "Turret", 1, 2 }, { "BurglarBot", 2, 3 } } },
				{ kind = "hold", seconds = 6, radius = 10 },
			},
		},
		ShardCrate = {
			num = 9,
			name = "Tech crate",
			side = "villain",
			where = "any",
			time = 90,
			text = "Beat the 3 turrets and open the crate",
			steps = {
				{ kind = "defeat", enemies = { { "Turret", 3, 3 } } },
				{ kind = "hold", seconds = 3, radius = 10 },
			},
		},
		CommSabotage = {
			num = 10,
			name = "Comm sabotage",
			side = "villain",
			where = "any",
			time = 75,
			text = "Wreck the Vigil relay before the timer",
			steps = {
				{ kind = "defeat", enemies = { { "SparkDrone", 2, 3 } } },
				{ kind = "object", hits = 10, label = "Relay" },
			},
		},
		-- 2026-11-17: more activities (each of the nine new robot types gets a job of its own)
		SniperNest = {
			num = 11,
			name = "{Sniper} nest",
			villainName = "Rooftop nest",
			side = "both",
			where = "nest",
			time = 100,
			requires = { "Sniper" },
			text = "Climb to the roof and clear the sniper nest",
			villainText = "Clear the nest off your rooftop",
			steps = {
				{
					kind = "nest",
					enemies = { { "Sniper", 2, 2 }, { "SparkDrone", 1, 2 } },
					text = "Clear the sniper nest",
				},
			},
		},
		MedicConvoy = {
			num = 12,
			name = "Medic convoy",
			villainName = "Repair run",
			side = "both",
			where = "street",
			time = 110,
			requires = { "MedicUnit" },
			text = "Stop the {MedicUnit}s before they reach the squad",
			villainText = "Stop the {MedicUnit}s fixing a rival squad",
			steps = {
				{
					kind = "convoy",
					enemy = "MedicUnit",
					n = 2,
					speed = 9,
					legs = 6,
					text = "Stop the {MedicUnit}s",
				},
				{
					kind = "defeat",
					enemies = { { "BruteBot", 1, 1 }, { "BurglarBot", 2, 3 } },
					text = "Beat the squad they were fixing",
				},
			},
		},
		CaptainWarband = {
			num = 13,
			name = "Warband",
			villainName = "Rival warband",
			side = "both",
			where = "street",
			time = 110,
			requires = { "Captain" },
			text = "Break the warband: down its {Captain}",
			steps = {
				{
					kind = "leader",
					leader = "Captain",
					enemies = { { "BurglarBot", 2, 3 }, { "SparkDrone", 1, 2 } },
					text = "Down the {Captain}",
				},
			},
		},
		MimicCrowd = {
			num = 14,
			name = "{Mimic} in the crowd",
			villainName = "Copycat",
			side = "both",
			where = "street",
			time = 90,
			requires = { "Mimic" },
			text = "A {Mimic} hides in the crowd: find it",
			villainText = "A {Mimic} is copying your crew: find it",
			steps = {
				{ kind = "find", enemies = { { "Mimic", 1, 1 } }, crowd = 6, text = "Find the {Mimic}" },
			},
		},
		BomberBarrage = {
			num = 15,
			name = "{Bomber} barrage",
			villainName = "Shell storm",
			side = "both",
			where = "street",
			time = 100,
			requires = { "Bomber" },
			text = "Shield the citizens from the {Bomber} barrage",
			villainText = "Shield your crew from the {Bomber} barrage",
			steps = {
				{
					kind = "barrage",
					enemies = { { "Bomber", 1, 2 } },
					huddles = 3,
					blocks = 5,
					misses = 3,
					every = 4,
					warn = 2.5,
					cover = 8,
					text = "Stand in the red rings",
				},
			},
		},
		GrapplerTow = {
			num = 16,
			name = "{Grappler} tow",
			villainName = "Tow job",
			side = "both",
			where = "street",
			time = 80,
			requires = { "Grappler" },
			text = "A {Grappler} is hauling a car away: stop it",
			villainText = "A {Grappler} is hauling off your getaway car",
			steps = {
				{
					kind = "tug",
					enemies = { { "Grappler", 1, 1 } },
					speed = 2.5,
					dist = 110,
					text = "Down the {Grappler}",
				},
				{ kind = "rescue", count = 1, text = "Get the driver out" },
			},
		},
		ScaffoldCollapse = {
			num = 17,
			name = "Scaffold collapse",
			villainName = "Scaffold slip",
			side = "both",
			where = "tower",
			time = 110,
			text = "Brace the scaffold and get the workers down",
			villainText = "Brace the scaffold before it drops on your crew",
			steps = {
				{
					kind = "hold",
					seconds = 6,
					radius = 12,
					at = "front",
					prop = "Scaffold",
					text = "Brace the scaffold",
				},
				{ kind = "rescue", count = 2, at = "balcony", text = "Carry the workers down" },
			},
		},
		CraneLoad = {
			num = 18,
			name = "Runaway crane load",
			villainName = "Swinging cargo",
			side = "both",
			where = "street",
			time = 90,
			text = "Robots cut a crane cable: catch the load",
			villainText = "Catch the swinging cargo before it is lost",
			steps = {
				{ kind = "defeat", enemies = { { "BurglarBot", 2, 3 } }, text = "Beat the cable cutters" },
				{ kind = "hold", seconds = 5, radius = 10, prop = "Load", text = "Catch the load" },
			},
		},
		WaterMain = {
			num = 19,
			name = "Water main burst",
			villainName = "Flooded street",
			side = "both",
			where = "street",
			time = 100,
			text = "Shut the burst water main, then get people out",
			villainText = "Shut the water main and clear the street",
			steps = {
				{ kind = "object", hits = 10, label = "Valve", text = "Shut the valve" },
				{ kind = "rescue", count = 3, text = "Carry the soaked citizens out" },
			},
		},
		DroneSwarm = {
			num = 20,
			name = "Rooftop drone swarm",
			villainName = "Drone swarm",
			side = "both",
			where = "nest",
			time = 90,
			text = "Clear the drone swarm off the roof",
			steps = {
				{
					kind = "nest",
					enemies = {
						{ "Swarmer", 1, 1, "SparkDrone", 2, 3 },
						{ "Interceptor", 1, 2, "SparkDrone", 1, 2 },
					},
					text = "Clear the swarm",
				},
			},
		},
		ShieldWall = {
			num = 21,
			name = "Shield wall",
			side = "hero",
			where = "street",
			time = 100,
			text = "Break the shield wall: hit the bearers from the side",
			steps = {
				{
					kind = "defeat",
					enemies = {
						{ "ShieldBearer", 2, 2, "BruteBot", 1, 2 },
						{ "BurglarBot", 2, 3 },
					},
					text = "Flank the shields",
				},
			},
		},
		SkyAmbush = {
			num = 22,
			name = "Sky ambush",
			villainName = "Sky ambush",
			side = "both",
			where = "any",
			time = 80,
			text = "{Interceptor}s are hunting flyers: beat them",
			steps = {
				{
					kind = "defeat",
					enemies = {
						{ "Interceptor", 2, 3, "SparkDrone", 2, 3 },
						{ "SparkDrone", 1, 1 },
					},
					text = "Beat the jets",
				},
			},
		},
		DepotRaid = {
			num = 23,
			name = "Depot raid",
			side = "villain",
			where = "street",
			time = 110,
			text = "Beat the depot guards, then load the crates",
			steps = {
				{
					kind = "defeat",
					enemies = {
						{ "ShieldBearer", 1, 1, "BruteBot", 1, 1 },
						{ "Turret", 1, 2 },
					},
					text = "Beat the guards",
				},
				{ kind = "hold", seconds = 5, radius = 10, prop = "Crates", text = "Load the crates" },
			},
		},
		SignalJam = {
			num = 24,
			name = "Signal jam",
			side = "villain",
			where = "nest",
			time = 100,
			text = "Take the Vigil rooftop relay",
			steps = {
				{
					kind = "nest",
					enemies = {
						{ "Sniper", 1, 1, "Turret", 1, 1 },
						{ "SparkDrone", 1, 2 },
					},
					text = "Clear the roof",
				},
				{ kind = "object", hits = 8, label = "Relay", text = "Wreck the relay" },
			},
		},
		-- WP5 (gap G13): a robot fake in a hero's costume works the crowd. The Vigil exposes it and scraps it;
		-- the Syndicate cracks its mask for the crowd and holds the square while the panic spreads. Generic
		-- costumed fakes only: the famous fakes stay in the story. (Draft text: nate to OK.)
		SuspiciousHero = {
			num = 25,
			name = "Suspicious hero",
			villainName = "Fake in the crowd",
			side = "both",
			where = "street",
			time = 110,
			minLevel = 6, -- after the opening's own fake, so players know what a crack means
			text = "A hero in that crowd is too perfect: unmask the fake",
			villainText = "A fake hero is working the crowd: crack its mask and let them panic",
			steps = {
				{
					kind = "unmask",
					crowd = 7,
					dress = { "Gleam", "Steelvow", "Quickstep" }, -- one whose suit is switched on (below)
					hpMult = 0.5, -- a fake of a street hero: half a famous fake's health
					dmgMult = 0.8,
					text = "Find the fake and crack its mask",
					villainText = "Crack its mask in front of the crowd",
				},
				{
					kind = "defeat",
					side = "hero",
					keep = true,
					enemies = {},
					text = "Scrap the fake before it slips away",
				},
				{
					kind = "hold",
					side = "villain",
					seconds = 8,
					radius = 14,
					panic = 2.5, -- the crowd scatters again every 2.5 s while you hold
					villainText = "Let the panic spread: hold the square",
				},
			},
		},
	},
	-- WP5: the Suspicious Hero's costumes, each over a fake's suit (`suit`: its fighting style). Shared.FakeRules
	-- reads these like a side quest's dress; `famous`, so the face cracks to metal and the plate turns FAKE
	-- over its own name. Built from the creator's own pieces. Names and titles are drafts (PLACEHOLDER CONTENT
	-- until nate OKs them). Ids must not repeat Config.SideQuests.dress ids (a test checks).
	dress = {
		Gleam = {
			suit = "Radiant", -- a Light flyer's dives and bursts
			name = "Gleamheart",
			title = "Hero of the Hour",
			creature = false,
			famous = true,
			body = {
				metal = { 160, 160, 175 },
				eye = { 255, 90, 60 },
				suit = { 200, 50, 50 },
				trim = { 245, 245, 245 },
			},
			look = {
				gender = 1,
				build = 2, -- the suit's frame (Radiant's)
				height = 4,
				skin = 3,
				hair = 16, -- brown
				colors = { 1, 18, 4 }, -- red, white, gold
				pieces = {
					suit = "Split Tone",
					back = "Classic Cape",
					hands = "Gloves",
					feet = "Boots",
					emblem = "Star Badge",
					head = "Domino Mask",
					visage = "Joyful Smile", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Brown Charmer Hair", -- Roblox catalog hair
				},
				tints = {},
				mats = {},
			},
		},
		Steelvow = {
			suit = "Bulwark", -- a tank's slams, charges and shockwaves
			name = "Steelvow",
			title = "The People's Shield",
			creature = false,
			famous = true,
			body = {
				metal = { 140, 140, 150 },
				eye = { 255, 90, 60 },
				suit = { 40, 150, 80 },
				trim = { 255, 210, 60 },
			},
			look = {
				gender = 2,
				build = 4, -- the suit's frame (Bulwark's Titan)
				height = 5,
				skin = 8,
				hair = 2, -- crimson
				colors = { 7, 19, 4 }, -- green, silver, gold
				pieces = {
					suit = "Bastion Suit",
					hands = "Knuckle Guards",
					feet = "Armored Boots",
					shoulders = "Riveted Pads",
					belt = "Big Buckle",
					emblem = "Heart Crest",
					head = "Half Mask",
					visage = "Alright", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Belle Of Belfast Long Red Hair", -- Roblox catalog hair
				},
				tints = {},
				mats = { shoulders = "Metal" },
			},
		},
		Quickstep = {
			suit = "Skylance", -- a fast thrower's throws and side dashes
			name = "Quickstep",
			title = "Fastest Cape in Town",
			creature = false,
			famous = true,
			body = {
				metal = { 170, 170, 185 },
				eye = { 255, 90, 60 },
				suit = { 255, 140, 40 },
				trim = { 24, 24, 28 },
			},
			look = {
				gender = 1,
				build = 1, -- the suit's frame (Skylance's Small)
				height = 4,
				skin = 12,
				hair = 47, -- electric yellow
				colors = { 3, 22, 47 }, -- orange, black, electric yellow
				pieces = {
					suit = "Racing Suit",
					back = "Hero Scarf",
					hands = "Fingerless Gloves",
					feet = "Hover Boots",
					emblem = "Spark",
					hat = "Flight Goggles",
					trail = "Ribbon Trail",
					visage = "Check It", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Clean Shiny Spikes", -- Roblox catalog hair
				},
				tints = {},
				mats = {},
			},
		},
	},
}
