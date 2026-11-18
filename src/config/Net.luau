-- Remote safety (spec: Remote events, Anti-exploit). A failing call is dropped and counted.
return {
	failureWindow = 60,
	kickAfterFailures = 40, -- far above honest play; only a script floods like this
	kickInStudio = false,
	enemyRelevance = 450, -- Enemy.Delta carries enemies this close to the player (streaming radius + margin)
	-- Enemy.Delta carries the robots the player's device can draw (Shared.QualityRules.enemiesFor) plus this
	-- many, so the camera's nearest are there too (perf pass 2026-11-18)
	enemySpare = 4,
}
