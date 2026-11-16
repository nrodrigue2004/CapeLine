-- Classes at launch (spec: Classes and power sets > Classes at launch). Passives are data the Combat
-- service reads; their effects land in M2.
return {
	order = { "Bruiser", "Blaster", "Speedster", "Controller" },
	Bruiser = {
		role = "Tank and melee",
		healthMult = 1.35,
		damageMult = 0.9,
		taunt = 25,
		passive = { id = "StandFirm", mitigation = 0.15 },
	},
	Blaster = {
		role = "Ranged damage",
		healthMult = 0.9,
		damageMult = 1.15,
		basicRange = 60,
		passive = { id = "Overcharge", everyNth = 5, bonus = 0.30 },
	},
	Speedster = {
		role = "Mobility and burst",
		healthMult = 1.0,
		damageMult = 1.0,
		moveSpeed = 0.10,
		cooldowns = -0.05,
		passive = { id = "Momentum", perTenSpeed = 0.01, max = 0.10 },
	},
	Controller = {
		role = "Support and crowd control",
		healthMult = 1.0,
		damageMult = 0.9,
		supportBonus = 0.25,
		ccBonus = 0.20,
		passive = { id = "Anchor", radius = 25, mitigation = 0.08 },
	},
	default = "Blaster", -- M1 slice hero until the creator (M9)
}
