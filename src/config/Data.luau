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
	reviewStore = "CapelineReview_v1", -- M8: the manual review queue (kicks, reports, PvP trades); never bans
	-- the save admin tools (list-combat 2026-11-20, Everything Left 464, 465; Services.SaveAdmin, notes/Launch
	-- Checklist.md "Player data requests"): erasing a player's data for a right-to-erasure request looks at the
	-- weekly boards from firstWeek (a week before the first playtest) and these review row kinds; a rollback puts a
	-- profile back to its last version before a time (Roblox keeps 30 days of versions)
	admin = {
		firstWeek = 2965,
		reviewKinds = { "kicks", "reports", "trade" },
		listPage = 50, -- keys a ListKeysAsync page asks for
	},
}
