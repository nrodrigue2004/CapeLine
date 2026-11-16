-- Studio test switches. Everything here is off in a live server unless noted.
return {
	-- Off since M3 (levels save): Flight opens at level 3 as in the spec. DEV > Level +5 skips ahead.
	unlockAllStyles = false,
	-- Off since M3 (the wallet exists): ranks cost Credits. DEV > +1000 Credits in Studio.
	freeRankCredits = false,
	loadBots = { max = 30, flySpeed = 55, fireEvery = 0.6 }, -- the 30-player load test (spec M1 and M4)
	stats = { every = 1 }, -- server frame stats to the Dev panel, seconds
}
