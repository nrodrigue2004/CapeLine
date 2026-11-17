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
	},
}
