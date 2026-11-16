-- Remote safety (spec: Remote events, Anti-exploit). A failing call is dropped and counted.
return {
	failureWindow = 60,
	kickAfterFailures = 40, -- far above honest play; only a script floods like this
	kickInStudio = false,
	enemyRelevance = 450, -- Enemy.Delta carries enemies this close to the player (streaming radius + margin)
}
