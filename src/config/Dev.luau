-- Studio test switches. Everything here is off in a live server unless noted.
return {
	-- Off since M3 (levels save): Flight opens at level 3 as in the spec. DEV > Level +5 skips ahead.
	unlockAllStyles = false,
	-- Off since M3 (the wallet exists): ranks cost Credits. DEV > +1000 Credits in Studio.
	freeRankCredits = false,
	loadBots = { max = 30, flySpeed = 55, fireEvery = 0.6 }, -- the 30-player load test (spec M1 and M4)
	stats = { every = 1 },
	-- Studio only: build this world seed instead of the weekly one (0 = the weekly seed). Two Studio servers
	-- with the same number must log the same tile hash (the M4 gate).
	worldSeed = 0, -- server frame stats to the Dev panel, seconds
	-- lore step 10: offer the side quest framework's sample chain (Config.SideQuests dev chains) at its
	-- giver and in the Journal, in Studio only (the Dev panel gives it either way). Off for every build.
	sideQuestSample = false,
	-- The Test Lab (nate, 2026-11-21: "Need a way for me to test out all the weapons/powers/abolities/mobilies in an
	-- easier way"): the Dev panel's LAB page, Studio only (Shared.LabRules, DevService's lab commands).
	-- cooldown: seconds every non-basic use waits with "Cooldowns off" (the held M1 keeps its own rate);
	-- dummies: the most training dummies at once; ahead / gap: studs in front of the hero and apart; robotAhead:
	-- studs in front a spawned robot lands
	lab = { cooldown = 0.35, dummies = 6, ahead = 18, gap = 8, robotAhead = 30, flyUp = 14 },
}
