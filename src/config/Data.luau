-- Saving (spec: Data model and save rules). One DataStore key per player with a session lock, a version
-- and migrations, written only by the server (the Ragdoll Rides saving package, ported in DataService).
return {
	storeName = "CapelineProfile_v1",
	keyPrefix = "P_",
	autosave = 120, -- seconds; plus soon-saves on level up, gear change, quest turn-in, choice, purchase
	soonDelay = 8, -- a "save soon" waits this long so a burst of changes becomes one write (6 s per key limit)
	lockWaitTries = 5,
	lockWaitTime = 3,
	lockStealAfter = 600, -- a lock older than this belongs to a crashed server
	saveRetries = 3,
	-- Server close waits up to 25 s for every save (Roblox allows 30). The spec's 4 s deadline would only
	-- drop slow saves; Decisions.md.
	closeDeadline = 25,
	targetBytes = 60 * 1024,
	capBytes = 400 * 1024,
	freeCharacters = 2,
	maxCharacters = 4,
	receiptsKept = 50,
}
