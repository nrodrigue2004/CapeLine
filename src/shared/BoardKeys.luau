-- BoardKeys: the weekly leaderboards' rules (spec: Global data and leaderboards, Weekly_<week> ordered stores;
-- gap check G2, WP2; Config.Boards). Pure, so BoardService, BoardHud and the Lune tests agree. Ported from
-- Ragdoll Rides' Shared/Boards (rows, friends, the pinned own row) and grown for Capeline:
-- * Weeks: PassRules.week (Monday 00:00 UTC, the world seed's weeks). One OrderedDataStore a week,
--   "Weekly_<week>", one scope per board, key = the user id, value = the player's total that week.
-- * The save keeps this week's totals in profile.mmo.counts ("board.week" and "board.<id>"), so a write is a
--   SetAsync of a total (a retry never counts twice) and a new week starts at 0. The week a player last
--   counted in waits there ("board.pending", "board.pmask") until its standings settle; then claim() reads
--   the player's final ranks once and grants the titles ("board.titles" bits). Claimed once: the pending
--   week is cleared in the same step.
-- * Ranking: the highest total first; equal totals share a rank (1, 2, 2, 4) and show by user id, so two
--   reads in a row always show the same order. A shared rank inside the top N earns the reward.
-- * Rows: the top `count` (or only friends and you, ranked among themselves) and your own row, pinned,
--   with your rank when you are in what was read. Names are filled in by the server from Roblox display
--   names; no row ever carries text a player typed.
-- * Writes (the batch): at most one write per stat per player per Config.Boards.writeEvery seconds, never
--   more than budget.share of the server's sorted-write budget in any minute; a leave or shutdown flushes at
--   once (only Roblox's own 6 s per-key floor applies); a failed write retries with backoff.

local PassRules = if script then require(script.Parent.PassRules) else (require :: any)("./PassRules")

local BoardKeys = {}

---------------------------------------------------------------------------
-- Weeks and keys
---------------------------------------------------------------------------

function BoardKeys.week(t: number): number
	return PassRules.week(t)
end

-- When a week starts and ends (os.time)
function BoardKeys.weekStart(week: number): number
	return (week * 7 - 3) * 86400
end

function BoardKeys.weekEnd(week: number): number
	return BoardKeys.weekStart(week + 1)
end

-- The store for a week ("Weekly_2970")
function BoardKeys.storeName(B: any, week: number): string
	return B.storePrefix .. tostring(math.floor(week))
end

function BoardKeys.entryKey(userId: number): string
	return tostring(math.floor(userId))
end

function BoardKeys.index(B: any, id: string): number?
	for i, b in B.boards do
		if b.id == id then
			return i
		end
	end
	return nil
end

function BoardKeys.board(B: any, id: string): any?
	local i = BoardKeys.index(B, id)
	return if i then B.boards[i] else nil
end

---------------------------------------------------------------------------
-- The save's counters (profile.mmo.counts)
---------------------------------------------------------------------------

BoardKeys.WEEK = "board.week"
BoardKeys.PENDING = "board.pending"
BoardKeys.PMASK = "board.pmask"
BoardKeys.TITLES = "board.titles"

function BoardKeys.countKey(id: string): string
	return "board." .. id
end

-- Every key the boards keep on the save (the save keeps at most 200 counters: the tests count them)
function BoardKeys.saveKeys(B: any): { string }
	local out = { BoardKeys.WEEK, BoardKeys.PENDING, BoardKeys.PMASK, BoardKeys.TITLES }
	for _, b in B.boards do
		table.insert(out, BoardKeys.countKey(b.id))
	end
	return out
end

local function bit(i: number): number
	return 2 ^ (i - 1)
end

local function has(mask: number, i: number): boolean
	return (mask // bit(i)) % 2 == 1
end

-- This week's total on a board (0 when the save's week is another)
function BoardKeys.total(counts: { [string]: number }, id: string, week: number): number
	if (counts[BoardKeys.WEEK] or 0) ~= week then
		return 0
	end
	return counts[BoardKeys.countKey(id)] or 0
end

-- A new week on the save: the old week (if it counted anything) waits for its standings, the totals start
-- at 0. Returns true when it rolled. A pending week still unclaimed is replaced by the newer one.
function BoardKeys.rollover(B: any, counts: { [string]: number }, week: number): boolean
	local was = counts[BoardKeys.WEEK] or 0
	if was == week then
		return false
	end
	local mask = 0
	for i, b in B.boards do
		local k = BoardKeys.countKey(b.id)
		if was > 0 and (counts[k] or 0) > 0 then
			mask += bit(i)
		end
		counts[k] = 0
	end
	if mask > 0 and was < week then
		counts[BoardKeys.PENDING] = was
		counts[BoardKeys.PMASK] = mask
	end
	counts[BoardKeys.WEEK] = week
	return true
end

-- Count n on a board this week. Returns the new total (rolling the week over first when it changed).
function BoardKeys.add(B: any, counts: { [string]: number }, id: string, n: number, week: number): number
	BoardKeys.rollover(B, counts, week)
	local k = BoardKeys.countKey(id)
	counts[k] = math.clamp(math.floor((counts[k] or 0) + math.max(0, n)), 0, 2 ^ 31)
	return counts[k]
end

-- The pending week whose standings have settled (nil: none yet), and the boards to read for it.
-- settle: seconds after the week's end (default Config.Boards.reward.settle; a Studio roll passes 0).
function BoardKeys.claimable(
	B: any,
	counts: { [string]: number },
	now: number,
	settle: number?
): (number?, { string })
	local week = counts[BoardKeys.PENDING] or 0
	if week <= 0 or now < BoardKeys.weekEnd(week) + (settle or B.reward.settle) then
		return nil, {}
	end
	local ids = {}
	local mask = counts[BoardKeys.PMASK] or 0
	for i, b in B.boards do
		if has(mask, i) then
			table.insert(ids, b.id)
		end
	end
	return week, ids
end

export type Grant = { board: string, rank: number, title: string, titleId: number, new: boolean }

-- Claim the pending week once: ranks[board id] = the player's final rank on it (nil: not read or not
-- ranked). Grants each board's title for a rank inside the top N, sets its bit and clears the pending week.
-- A second call finds nothing pending and grants nothing.
function BoardKeys.claim(
	B: any,
	counts: { [string]: number },
	week: number,
	ranks: { [string]: number? }
): { Grant }
	if (counts[BoardKeys.PENDING] or 0) ~= week or week <= 0 then
		return {}
	end
	local grants = {}
	local titles = counts[BoardKeys.TITLES] or 0
	local mask = counts[BoardKeys.PMASK] or 0
	for i, b in B.boards do
		local r = ranks[b.id]
		if has(mask, i) and r and r >= 1 and r <= B.reward.top then
			local new = not has(titles, i)
			if new then
				titles += bit(i)
			end
			table.insert(
				grants,
				{ board = b.id, rank = r, title = b.title, titleId = B.titleBase + i, new = new }
			)
		end
	end
	counts[BoardKeys.TITLES] = titles
	counts[BoardKeys.PENDING] = 0
	counts[BoardKeys.PMASK] = 0
	return grants
end

-- Does this account own a board's title?
function BoardKeys.owns(B: any, counts: { [string]: number }?, id: string): boolean
	local i = BoardKeys.index(B, id)
	return i ~= nil and counts ~= nil and has(counts[BoardKeys.TITLES] or 0, i)
end

-- The board titles this account owns: { id, name } (title ids titleBase + the board's place)
function BoardKeys.titles(B: any, counts: { [string]: number }?): { { id: number, name: string } }
	local out = {}
	local titles = if counts then counts[BoardKeys.TITLES] or 0 else 0
	for i, b in B.boards do
		if has(titles, i) then
			table.insert(out, { id = B.titleBase + i, name = b.title })
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Ranking and rows
---------------------------------------------------------------------------

export type Entry = { userId: number, value: number }
export type Row = { rank: number?, userId: number, value: number, me: boolean, friend: boolean }

-- Sort entries best first: higher totals, ties by user id (stable across reads)
function BoardKeys.sort(entries: { Entry }): { Entry }
	table.sort(entries, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	return entries
end

-- Competition ranks for sorted entries: equal totals share a rank (1, 2, 2, 4)
function BoardKeys.ranks(entries: { Entry }): { number }
	local out = {}
	for i, e in entries do
		if i > 1 and e.value == entries[i - 1].value then
			out[i] = out[i - 1]
		else
			out[i] = i
		end
	end
	return out
end

-- A player's rank in sorted entries (nil when not there or at 0)
function BoardKeys.rankOf(entries: { Entry }, userId: number): number?
	local ranks = BoardKeys.ranks(entries)
	for i, e in entries do
		if e.userId == userId then
			return if e.value > 0 then ranks[i] else nil
		end
	end
	return nil
end

-- The rows for a tab from what was read (sorted). filter: "all" or "friends" (a set of user ids).
-- Returns the list (at most `count`) and your pinned row (nil when you have nothing on this board).
function BoardKeys.rows(
	entries: { Entry },
	me: number,
	myValue: number,
	friends: { [number]: boolean },
	filter: string,
	count: number
): ({ Row }, Row?)
	local list: { Row } = {}
	local mine: Row? = nil
	local ranks = BoardKeys.ranks(entries)
	local pool: { Entry } = {}
	local poolRanks: { number } = {}
	for i, e in entries do
		if e.value > 0 then
			local isMe = e.userId == me
			if isMe then
				mine = {
					rank = ranks[i],
					userId = me,
					value = math.max(e.value, myValue),
					me = true,
					friend = false,
				}
			end
			if filter ~= "friends" or isMe or friends[e.userId] then
				table.insert(pool, e)
				table.insert(poolRanks, ranks[i])
			end
		end
	end
	-- friends rank among themselves and you
	local shown = if filter == "friends" then BoardKeys.ranks(pool) else poolRanks
	for i, e in pool do
		if #list >= count then
			break
		end
		table.insert(list, {
			rank = shown[i],
			userId = e.userId,
			value = e.value,
			me = e.userId == me,
			friend = friends[e.userId] == true,
		})
	end
	if mine and filter == "friends" then
		for i, e in pool do
			if e.userId == me then
				(mine :: Row).rank = shown[i]
			end
		end
	end
	if mine == nil and myValue > 0 then
		mine = { rank = nil, userId = me, value = myValue, me = true, friend = false }
	end
	return list, mine
end

-- One line that changes whenever a plaza board's rows change (the plaza redraws only then)
function BoardKeys.digest(boards: { { { rank: number?, name: string, value: number } } }): string
	local parts = {}
	for _, rows in boards do
		for _, r in rows do
			table.insert(parts, string.format("%s|%s|%d", tostring(r.rank), r.name, r.value))
		end
		table.insert(parts, "/")
	end
	return table.concat(parts, ";")
end

-- Where the plaza board stands: its centre on the ground and the way it faces (from the tower's centre)
function BoardKeys.propSpot(B: any, bx: number, bz: number): (number, number, number, number)
	local P = B.prop
	return bx + P.offset[1], bz + P.offset[2], P.face[1], P.face[2]
end

---------------------------------------------------------------------------
-- The write batch
---------------------------------------------------------------------------

export type Job = {
	week: number,
	board: string,
	userId: number,
	value: number, -- the newest total
	written: number, -- the last total written (-1: never)
	lastWrite: number, -- when the last write started (-math.huge: never)
	urgent: boolean, -- leave: write as soon as the key allows
	inflight: boolean,
	tries: number,
	nextTry: number,
}

export type Batch = { jobs: { [string]: Job }, sent: { number } }

function BoardKeys.newBatch(): Batch
	return { jobs = {}, sent = {} }
end

function BoardKeys.jobKey(week: number, board: string, userId: number): string
	return string.format("%d:%s:%d", week, board, userId)
end

-- The writes this server may start in a minute
function BoardKeys.budget(B: any, players: number, all: boolean?): number
	local full = B.budget.base + B.budget.perPlayer * math.max(0, players)
	return math.floor(if all then full else full * B.budget.share)
end

-- A total changed: keep the newest (only the newest total is ever written)
function BoardKeys.queue(batch: Batch, week: number, board: string, userId: number, value: number)
	local k = BoardKeys.jobKey(week, board, userId)
	local j = batch.jobs[k]
	if not j then
		j = {
			week = week,
			board = board,
			userId = userId,
			value = value,
			written = -1,
			lastWrite = -math.huge,
			urgent = false,
			inflight = false,
			tries = 0,
			nextTry = -math.huge,
		}
		batch.jobs[k] = j
	end
	j.value = math.max(j.value, value)
end

-- A player leaves: their unwritten totals go first, as soon as each key allows
function BoardKeys.leave(batch: Batch, userId: number)
	for _, j in batch.jobs do
		if j.userId == userId and j.value ~= j.written then
			j.urgent = true
		end
	end
end

local function dirty(j: Job): boolean
	return j.value ~= j.written
end

-- The jobs to write now. all = shutdown: every unwritten total is urgent and the whole budget is open.
-- Marks them in flight and spends the budget; the caller writes each and calls done().
function BoardKeys.due(B: any, batch: Batch, now: number, players: number, all: boolean?): { Job }
	local sent = batch.sent
	while sent[1] and sent[1] <= now - 60 do
		table.remove(sent, 1)
	end
	local room = BoardKeys.budget(B, players, all) - #sent
	if room <= 0 then
		return {}
	end
	local ready = {}
	for _, j in batch.jobs do
		if j.inflight or not dirty(j) or now < j.nextTry then
			continue
		end
		local gap = if j.urgent or all then B.keyGap else B.writeEvery
		if now - j.lastWrite >= gap then
			table.insert(ready, j)
		end
	end
	table.sort(ready, function(a, b)
		local ua, ub = a.urgent or false, b.urgent or false
		if ua ~= ub then
			return ua
		end
		if a.lastWrite ~= b.lastWrite then
			return a.lastWrite < b.lastWrite
		end
		return BoardKeys.jobKey(a.week, a.board, a.userId) < BoardKeys.jobKey(b.week, b.board, b.userId)
	end)
	local out = {}
	for _, j in ready do
		if #out >= room then
			break
		end
		j.inflight = true
		j.lastWrite = now
		table.insert(sent, now)
		table.insert(out, j)
	end
	return out
end

-- A write finished (wrote: the total it sent). A failure retries after base x 2^n s; after the last try the
-- job is dropped (the save still has the total, and the next change writes it again).
function BoardKeys.done(B: any, batch: Batch, j: Job, ok: boolean, wrote: number, now: number)
	j.inflight = false
	local k = BoardKeys.jobKey(j.week, j.board, j.userId)
	if ok then
		j.written = wrote
		j.tries = 0
		j.nextTry = -math.huge
		if not dirty(j) then
			j.urgent = false
		end
		return
	end
	j.tries += 1
	if j.tries >= B.retry.tries then
		batch.jobs[k] = nil
		return
	end
	j.nextTry = now + math.min(B.retry.max, B.retry.base * 2 ^ (j.tries - 1))
end

-- Forget written jobs whose write window has passed (they hold nothing left to send)
function BoardKeys.sweep(B: any, batch: Batch, now: number)
	for k, j in batch.jobs do
		if not j.inflight and not dirty(j) and now - j.lastWrite >= B.writeEvery then
			batch.jobs[k] = nil
		end
	end
end

-- Unwritten totals left (shutdown waits for these)
function BoardKeys.pending(batch: Batch): number
	local n = 0
	for _, j in batch.jobs do
		if dirty(j) or j.inflight then
			n += 1
		end
	end
	return n
end

return BoardKeys
