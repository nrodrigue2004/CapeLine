-- Radiant contracts (spec: Opening and story > Radiant contracts; Contract.Accept, Contract.Abandon,
-- Contract.Update). From the Contract Board at any safehouse, from level 4. Each takes 2 to 6 minutes; the
-- first 5 each day pay double (Economy.bonus.firstContracts). Rewards use the zone level L of the board's
-- area for the hero. Credits and Renown: base + perLevel x L (renown falls back to Economy.earn.contract).
-- Sites are placed within `radius` of the board; robots there spawn at L. (tune)
return {
	board = {
		offers = 3, -- contracts shown on a board
		maxAccepted = 3, -- spec: max 3
		minLevel = 4, -- spec: Contract Board unlocks at level 4
		radius = { 150, 450 }, -- sites this far from the board
		refresh = 300, -- a hero's offers change every 5 minutes (and after accepting)
		updateRate = 2,
	},
	order = { "DroneSweep", "RescueRun", "ShardRecovery", "Escort", "VaultJob", "Stakeout" },
	types = {
		DroneSweep = {
			num = 1,
			name = "Drone sweep",
			side = "both",
			text = "Defeat 3 Spark Trooper squads",
			goal = 3,
			squad = { "SparkDrone", 3 },
			credits = { 40, 4 },
			renown = { 60, 5 },
		},
		RescueRun = {
			num = 2,
			name = "Rescue run",
			side = "both",
			text = "Carry 5 stranded citizens to a safehouse",
			goal = 5,
			credits = { 36, 3 },
			renown = { 50, 5 },
		},
		ShardRecovery = {
			num = 3,
			name = "Shard recovery",
			side = "both",
			text = "Find 3 shards with the radar",
			goal = 3,
			credits = { 50, 4 },
			pickup = 8, -- touch range
		},
		Escort = {
			num = 4,
			name = "Escort",
			side = "both",
			text = "Walk the truck 600 studs",
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
			text = "Photograph 3 Sneak Bots",
			goal = 3,
			photoRange = 40,
			photoTime = 2, -- seconds in view to get the photo
			credits = { 40, 4 },
			fame = 40,
		},
	},
}
