-- Incidents (spec: Schedulers > Incident spawner; Opening and story > Incidents). 30 s to 2 min jobs spawned
-- around each hero. Templates are data: a list of steps, each one of
--   defeat  robots to beat: { kind, min, max } rows, rolled when the incident starts
--   rescue  citizens (or a cat) stuck at the site to carry to its drop pad (no citizen is ever hurt)
--   hold    stand at the spot for `seconds` (more heroes go faster)
--   object  a thing to break or stop: HP is `hits` hits of a hero's Power at the zone level
--   runner  a Velvet Paw bot that runs a roof (or street) path; beat it before it gets away
-- where: the kind of spot it needs (street, tower, tram, sign, roof, crane, any). side: hero, villain or
-- both; in "both" templates villains see villainName and play the same mechanics. (tune)
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
	},
	templates = {
		RobotHeist = {
			num = 1,
			name = "Robot heist",
			side = "hero",
			where = "street",
			time = 90,
			text = "Stop the Burglar Bots",
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
			villainText = "Catch the League courier bot",
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
			name = "Shard crate",
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
			text = "Wreck the League relay before the timer",
			steps = {
				{ kind = "defeat", enemies = { { "SparkDrone", 2, 3 } } },
				{ kind = "object", hits = 10, label = "Relay" },
			},
		},
	},
}
