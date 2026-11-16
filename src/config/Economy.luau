-- Economy and levels (spec: Economy and monetization; Creator, HQ, levels and Legacy > Levels). One soft
-- currency (Credits), one progression track (Renown), one crafting material (Lumen Dust). No trading.
-- All numbers are tuning guesses (Balance.Economy in the spec).
return {
	-- xpToNext(L) = round(100 x 1.12^(L - 1)); cumulative to level 40 is about 68,400
	levels = { base = 100, growth = 1.12 },
	-- Earn formulas (L = zone level): value = base + perLevel x L
	earn = {
		incident = { credits = { 20, 1.5 }, renown = { 25, 2 } },
		rescue = { credits = { 10, 0.5 }, renown = { 15, 1 } },
		contract = { credits = { 80, 4 }, renown = { 60, 5 } }, -- contract Credits come from the contract table (M6)
		mission = { credits = { 100, 8 }, renown = { 200, 10 } },
		bossParticipant = { credits = { 150, 0 }, renown = { 400, 15 } },
		bossContributor = { credits = { 250, 0 }, renown = { 600, 20 } },
		bossMvp = { credits = { 400, 0 }, renown = { 900, 25 } },
		deepCache = { credits = { 60, 4 }, renown = { 20, 1 } }, -- a sunken cargo cache (Config.Deep)
		deepRescue = { credits = { 30, 1.5 }, renown = { 45, 3 } }, -- a commuter swum out of the Sunken Line
	},
	-- Bonuses multiply, then round; the whole stack is capped at x4
	bonus = {
		friendEach = 0.10,
		friendMax = 0.30,
		firstContracts = 5, -- the first 5 contracts per day pay x2
		firstContractMult = 2,
		legacyEach = 0.10,
		legacyMax = 0.50,
		factionEach = 0.02,
		factionMax = 0.10,
		doublePass = 2, -- the 2x pass: earned Credits and Renown only (M9)
		cap = 4,
	},
	-- Balance knobs over the earn formulas above (M9 economy sim): every Credit and Renown reward is
	-- multiplied by these, contracts and bosses included
	scale = { credits = 1.4, renown = 0.35 },
	-- The 1,000-hero sim's play model (EconomySim): what a typical hero does in 30 minutes (a model to
	-- check the numbers against, not a rule), a 2 hour session per day, skill factor, friends, 2x pass share
	sim = {
		per30 = { incident = 6, rescue = 4, contract = 1.5, boss = 0.6 },
		bossTiers = { 0.6, 0.3, 0.1 }, -- joined, contributor, MVP
		contractKinds = { "DroneSweep", "RescueRun", "ShardRecovery", "Escort" },
		skill = { 0.7, 1.3 },
		friends = { 0, 2 },
		passShare = 0.04,
		sessionHours = 2,
		reserve = 1.25, -- keeps this much of a price in hand before buying HQ levels or styles
		stylePrice = 1200, -- a mid Gizmo style
	},
	-- Sinks
	hqLevels = { 2000, 5000, 12000, 25000, 50000 }, -- HQ levels 2 to 6 (M9)
	start = { credits = 0, banked = 0, dust = 0 },
}
