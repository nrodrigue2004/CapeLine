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
}
