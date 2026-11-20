--!strict
-- SaveAdminPlan (list-combat 2026-11-20, Everything Left 464, 465): the pure side of the save admin tools.
-- * erase: every place a player's data is kept, for Roblox's right-to-erasure requests: the profile key, their
--   rows on each weekly board from Config.Data.admin.firstWeek to this week, and the review queue rows (key
--   prefixes per kind: "<kind>_<userId>_"; GuardService.review). Nothing else stores a user id (BalanceService
--   keeps one live key for the whole game).
-- * rollback: which of a profile key's saved versions to put back after a bad build: the newest version written
--   before the given time (Roblox keeps every DataStore version for 30 days; DataStore:ListVersionsAsync).
-- No Roblox types here, so Lune tests it; Services.SaveAdmin does the calls.

local BoardKeys = if script then require(script.Parent.BoardKeys) else (require :: any)("./BoardKeys")

local SaveAdminPlan = {}

export type Target = { store: string, scope: string?, key: string, ordered: boolean? }

-- The keys to remove for one user: { targets (exact keys), prefixes (review store keys to list then remove) }
function SaveAdminPlan.erase(
	Config: any,
	userId: number,
	now: number
): ({ Target }, { { store: string, prefix: string } })
	local D = Config.Data
	local B = Config.Boards
	local id = math.floor(userId)
	local out: { Target } = { { store = D.storeName, key = D.keyPrefix .. tostring(id) } }
	local thisWeek = BoardKeys.week(now)
	for week = D.admin.firstWeek, thisWeek + 1 do
		for _, board in B.boards do
			table.insert(out, {
				store = BoardKeys.storeName(B, week),
				scope = board.id,
				key = BoardKeys.entryKey(id),
				ordered = true,
			})
		end
	end
	local prefixes = {}
	for _, kind in D.admin.reviewKinds do
		table.insert(prefixes, { store = D.reviewStore, prefix = string.format("%s_%d_", kind, id) })
	end
	return out, prefixes
end

-- The version to roll back to: the newest of `versions` ({ version, time (unix seconds), deleted }) written
-- strictly before `before`, skipping deleted ones; nil when there is none
function SaveAdminPlan.pick(
	versions: { { version: string, time: number, deleted: boolean? } },
	before: number
): string?
	local best, bestAt = nil, -math.huge
	for _, v in versions do
		if not v.deleted and v.time < before and v.time > bestAt then
			best, bestAt = v.version, v.time
		end
	end
	return best
end

return SaveAdminPlan
