-- Studio test switches. Everything here is off in a live server unless noted.
return {
	-- M1 slice: Flight is unlocked from the start so the move-and-fight test needs no levels (spec level 3).
	-- Turn off in M3 when levels and saves exist.
	unlockAllStyles = true,
	loadBots = { max = 30, flySpeed = 55, fireEvery = 0.6 }, -- the 30-player load test (spec M1 and M4)
	stats = { every = 1 }, -- server frame stats to the Dev panel, seconds
}
