-- Radiant contracts (spec: Opening and story > Radiant contracts; Contract.Accept, Contract.Abandon,
-- Contract.Update). From the Contract Board at any safehouse, from level 4. Each takes 2 to 6 minutes; the
-- first 5 each day pay double (Economy.bonus.firstContracts). Rewards use the zone level L of the board's
-- area for the hero. Credits and Renown: base + perLevel x L (renown falls back to Economy.earn.contract).
-- Sites are placed within `radius` of the board; robots there spawn at L. (tune)
return {
	board = {
		offers = 4, -- contracts shown on a board (3 until 2026-11-17: 12 types now, so one more shows)
		maxAccepted = 3, -- spec: max 3
		minLevel = 4, -- spec: Contract Board unlocks at level 4
		radius = { 150, 450 }, -- sites this far from the board
		refresh = 300, -- a hero's offers change every 5 minutes (and after accepting)
		updateRate = 2,
	},
	order = {
		"DroneSweep",
		"RescueRun",
		"ShardRecovery",
		"Escort",
		"VaultJob",
		"Stakeout",
		"Bounty",
		"Demolition",
		"RooftopCourier",
		"Defusal",
		"PhotoRecon",
		"GeneratorHold",
	},
	types = {
		DroneSweep = {
			num = 1,
			name = "Drone sweep",
			villainName = "Drone scrap raid", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Defeat 3 {SparkDrone} squads",
			villainText = "Scrap 3 {SparkDrone} squads for parts",
			goal = 3,
			squad = { "SparkDrone", 3 },
			credits = { 40, 4 },
			renown = { 60, 5 },
		},
		RescueRun = {
			num = 2,
			name = "Rescue run",
			villainName = "Jailbreak", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Carry 5 stranded citizens to a safehouse",
			villainText = "Break 5 crew members out to a safehouse",
			goal = 5,
			credits = { 36, 3 },
			renown = { 50, 5 },
		},
		ShardRecovery = {
			num = 3,
			name = "Core recovery",
			villainName = "Core heist", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Find 3 lost power cores with the radar",
			villainText = "Steal 3 lost power cores before the Vigil finds them",
			goal = 3,
			credits = { 50, 4 },
			pickup = 8, -- touch range
		},
		Escort = {
			num = 4,
			name = "Escort",
			villainName = "Getaway truck", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Walk the truck 600 studs",
			villainText = "Walk the stolen truck 600 studs",
			goal = 600,
			credits = { 44, 4 },
			speed = 9, -- truck studs/s while a hero is near it
			near = 40,
			ambushAt = { 0.3, 0.65 }, -- robots jump the truck at these shares of the route
			ambush = { "BurglarBot", 3 },
		},
		VaultJob = {
			num = 5,
			name = "Vault job",
			side = "villain",
			text = "Crack 2 vaults guarded by turrets",
			goal = 2,
			guards = { "Turret", 2 },
			crack = 6, -- seconds to hold at a vault once its turrets are down
			credits = { 54, 5 },
			infamy = 40,
		},
		Stakeout = {
			num = 6,
			name = "Stakeout",
			side = "hero",
			text = "Photograph 3 {SneakBot}s",
			goal = 3,
			photoRange = 40,
			photoTime = 2, -- seconds in view to get the photo
			credits = { 40, 4 },
			fame = 40,
		},
		-- 2026-11-17: more activities (nate: "way more content to keep players playing")
		Bounty = {
			num = 7,
			name = "Bounty",
			villainName = "Hit job", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Hunt down %s, an elite %s", -- the name and the robot type, from the fixed lists below
			villainText = "Take out %s, an elite %s, for the Syndicate",
			goal = 1,
			-- the elite's name: a fixed list (no free text); its type: the first of `targets` that is switched
			-- on and unlocked at the level, counted round from the contract's pick
			names = {
				"Rust Baron",
				"Iron Widow",
				"Bolt Jaw",
				"Gearhook",
				"Static Queen",
				"Rivet King",
				"Scrapmonger",
				"Cinder Knuckle",
				"Copper Saint",
				"Overclock",
				"Grim Sprocket",
				"Wirewolf",
			},
			targets = { "Captain", "Grappler", "ShieldBearer", "Bomber", "Sniper", "BruteBot" },
			elite = { hpMult = 3, levelBonus = 3 }, -- the bounty is tougher than its kind
			escort = { "BurglarBot", 2 },
			credits = { 60, 5 },
			renown = { 80, 6 },
		},
		Demolition = {
			num = 8,
			name = "Outpost demolition",
			villainName = "Outpost raid", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Knock down a robot outpost: break its 3 pylons",
			villainText = "Raid a robot outpost: break its 3 pylons",
			goal = 3,
			hits = 18, -- each pylon, in hits of Power at the zone level
			spread = 18, -- pylons stand this far round the outpost's mast
			guards = { { "Turret", 1 }, { "ShieldBearer", 1, "BruteBot" }, { "BurglarBot", 2 } },
			credits = { 56, 5 },
			renown = { 70, 6 },
		},
		RooftopCourier = {
			num = 9,
			name = "Rooftop courier",
			villainName = "Smuggle run", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Grab the parcel and touch 5 rooftop drops in %d s",
			villainText = "Grab the goods and touch 5 rooftop drops in %d s",
			goal = 5, -- drops after the parcel
			timeLimit = 75, -- from the parcel; out of time puts the parcel back on its roof
			touch = 10,
			credits = { 46, 4 },
			renown = { 55, 5 },
		},
		Defusal = {
			num = 10,
			name = "Sabotage defusal",
			side = "hero",
			text = "Defuse 3 robot charges before they pop",
			goal = 3,
			guards = { "BurglarBot", 2 },
			defuse = 4, -- seconds to hold at a charge once its guards are down
			radius = 8,
			fuse = 50, -- a charge's fuse starts when you come within `wake` studs; it fizzles and re-plants
			wake = 80,
			credits = { 50, 5 },
			renown = { 65, 6 },
		},
		PhotoRecon = {
			num = 11,
			name = "Photo recon",
			villainName = "Casing the job", -- side-content: the Syndicate's own job (draft for nate)
			side = "both",
			text = "Take a Photo Mode shot from 3 rooftop lookouts",
			villainText = "Case the city from 3 rooftop lookouts: Photo Mode shots",
			goal = 3,
			range = 14, -- stand this close to a lookout when you take the photo
			credits = { 42, 4 },
			renown = { 55, 5 },
		},
		GeneratorHold = {
			num = 12,
			name = "Protect the generator",
			villainName = "Power tap",
			side = "both",
			text = "Hold the generator's ring for %d s while robots attack",
			villainText = "Hold the power tap's ring for %d s while robots attack",
			goal = 45, -- seconds in the ring
			radius = 12,
			drain = 0.5, -- progress lost a second while nobody holds it
			waves = {
				{ "BurglarBot", 3 },
				{ "SparkDrone", 3 },
				{ "BruteBot", 2 },
				{ "Bomber", 1, "BurglarBot" },
			},
			waveEvery = 14,
			credits = { 48, 4 },
			renown = { 60, 5 },
		},
	},
}
