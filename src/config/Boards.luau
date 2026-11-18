-- Boards: the weekly leaderboards (spec: Global data and leaderboards, "Weekly_<week> ordered stores: Boss MVP
-- count, rescues, PvP wins (cosmetic leaderboards)"; PvP flag "A weekly PvP leaderboard gives cosmetics only";
-- gap check G2, WP2). Pure data, tuned in the playtest. Shared.BoardKeys has the rules.
-- * One OrderedDataStore per week, named storePrefix .. <week> (PassRules.week: Monday 00:00 UTC weeks, the
--   same weeks as the world seed, the episode and the Hero Pass); each board is a scope in it.
-- * A board's value is the player's total for the week (kept on the save, so a write is a SetAsync of the
--   total: safe to retry, never counted twice).
-- * Writes: at most one per stat per player per `writeEvery` seconds, never more than `budget.share` of the
--   server's sorted-write budget a minute, flushed on leave and on shutdown, retried with backoff.
-- * Reads: the top `readCount` once per `cacheSeconds` per board per server; the list shows `topCount`,
--   your own row is pinned under it, and FRIENDS is your Roblox friends found in what was read.
-- * Rewards: the top `reward.top` of a week's board earn that board's title, granted once, on the first join
--   (or the first minute online) after the week's standings settle. Titles are fixed text, earned only,
--   never sold and never a stat.
-- Names on the boards are Roblox display names (filtered by Roblox), never text a player typed.
return {
	storePrefix = "Weekly_", -- the spec's store name: Weekly_<week>
	-- the boards, in tab order. stat: what counts (Shared.BoardKeys.STATS); title: the weekly top-N title.
	-- Ids and order are saved (profile.mmo.counts keys and title bits): only ever add at the end.
	boards = {
		{ id = "BossMvp", name = "BOSS MVPS", unit = "MVP", units = "MVPS", title = "Boss Breaker" },
		{ id = "Rescues", name = "RESCUES", unit = "RESCUE", units = "RESCUES", title = "City Saver" },
		{ id = "PvpWins", name = "PVP WINS", unit = "WIN", units = "WINS", title = "Crater Champion" },
	},
	titleBase = 6000, -- a board title's id in the title list (Config.Remembers 4000s and Config.Daily 5000s sit below)

	writeEvery = 60, -- seconds: at most one write per stat per player in this window
	keyGap = 6, -- seconds: Roblox's own floor between writes to one key (a leave flush waits for it)
	tick = 5, -- seconds between write passes
	retry = { base = 4, max = 64, tries = 6 }, -- a failed write waits base x 2^n seconds (n = tries so far)
	-- the server's sorted-write budget a minute (Roblox: 30 + 5 per player for SetIncrementSortedAsync);
	-- the boards never take more than `share` of it, so other ordered writes always have room
	budget = { base = 30, perPlayer = 5, share = 0.6 },
	-- the sorted-read budget a minute (Roblox: 5 + 2 per player for GetSortedAsync)
	readBudget = { base = 5, perPlayer = 2 },

	cacheSeconds = 60, -- one read per board per minute per server
	readCount = 100, -- read the top 100 (FRIENDS and your own rank come from it at no extra cost)
	topCount = 50, -- rows shown
	friendsMax = 200, -- Roblox friends read once a session
	plazaCount = 10, -- rows on the plaza board

	reward = {
		top = 10, -- the top 10 of each board earn its title
		settle = 900, -- seconds after the week ends before its standings count (other servers' last flushes)
	},

	-- the plaza board: a free-standing board on the plaza's west edge, south of the Vigil's stairwell, facing
	-- east into the plaza (offsets from the Beacon Tower's centre; clear of the corner spawns at +-43, the
	-- stairwell at z -24, the contest stage's corner and the prologue's stage on the east face).
	-- PLACEHOLDER ART: a part-built frame and legs until the art pass.
	prop = {
		offset = { -44, 20 },
		face = { 1, 0 }, -- faces +x (into the plaza)
		size = { 22, 12 }, -- the screen, studs
		height = 4, -- the screen's bottom above the plaza
		pixelsPerStud = 24,
		maxDistance = 220,
		refresh = 60, -- seconds between checks for a new top 10 (pushed only when it changed)
	},
}
