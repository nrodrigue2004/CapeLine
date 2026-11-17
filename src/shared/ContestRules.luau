--!strict
-- ContestRules: costume contests (spec: Hero MMO features > Costume contests; H7). Pure, so ContestService,
-- ContestHud and the Lune tests agree: the schedule on the clock (every 30 minutes, the same on every
-- server), the phase at a time, the theme, who may vote and how much a vote weighs (2 minutes on the server;
-- squadmates count half; never for yourself), the tally and placings (a player wins at most once an hour:
-- the next best takes first), whether it runs at all (3 contestants and 5 voters) and the pay.

local ContestRules = {}

export type Phase = { name: string, cycle: number, startsAt: number, endsAt: number, showAt: number }

-- The contest of the half hour this time is in: its number, when its call starts, when the show starts and
-- when it ends (call, then show per contestant slot, vote, results). maxEntries slots are always kept.
function ContestRules.cycle(K: any, now: number): (number, number, number, number)
	local cycle = math.floor((now - K.offset) / K.every)
	local callAt = cycle * K.every + K.offset
	local showAt = callAt + K.call
	local endAt = showAt + K.show * K.maxEntries + K.vote + K.results
	return cycle, callAt, showAt, endAt
end

-- The phase for n contestants: "call" (entries open), "show" (spotlight i), "vote", "results" or "idle"
function ContestRules.phase(K: any, now: number, n: number): (string, number, number)
	local cycle, callAt, showAt = ContestRules.cycle(K, now)
	if now < callAt then
		return "idle", cycle, callAt
	end
	if now < showAt then
		return "call", cycle, showAt
	end
	local slots = math.max(1, n)
	local showEnd = showAt + K.show * slots
	if now < showEnd then
		local i = math.floor((now - showAt) / K.show) + 1
		return "show", i, showAt + K.show * i
	end
	if now < showEnd + K.vote then
		return "vote", cycle, showEnd + K.vote
	end
	if now < showEnd + K.vote + K.results then
		return "results", cycle, showEnd + K.vote + K.results
	end
	return "idle", cycle, callAt + K.every
end

-- The theme for a contest number (fixed list; the same on every server)
function ContestRules.theme(K: any, cycle: number): string
	local n = #K.themes
	-- a stride that is prime to the list length walks every theme before repeating
	return K.themes[(cycle * 7) % n + 1]
end

-- May this player step on? (entries open in the call, not full, not already in, near the stage)
function ContestRules.canEnter(K: any, entries: { number }, userId: number, dist: number): (boolean, string?)
	if table.find(entries, userId) then
		return false, "in"
	elseif #entries >= K.maxEntries then
		return false, "full"
	elseif dist > K.enterRange then
		return false, "far"
	end
	return true, nil
end

-- May this player vote? (on the server 2 minutes, not a contestant)
function ContestRules.canVote(K: any, joinedAt: number, now: number, isEntry: boolean): boolean
	return not isEntry and now - joinedAt >= K.voteAfter
end

-- A vote's weight: half for a squadmate's vote, nothing for your own or out of range stars
function ContestRules.weight(
	K: any,
	voter: number,
	target: number,
	stars: number,
	squadmates: boolean
): number
	if voter == target or stars < 1 or stars > 5 or stars % 1 ~= 0 then
		return 0
	end
	return stars * (if squadmates then K.squadWeight else 1)
end

-- Enough people for a contest?
function ContestRules.enough(K: any, entries: number, voters: number): boolean
	return entries >= K.minEntries and voters >= K.minVoters
end

-- Scores to placings: entries in order (user ids), score per user id, the last win time per user id.
-- Ties keep entry order. A player who won within winEvery cannot take first: the next best does, and they
-- keep their place behind. Returns user ids best first.
function ContestRules.placings(
	K: any,
	entries: { number },
	score: { [number]: number },
	lastWin: { [number]: number },
	now: number
): { number }
	local order = table.clone(entries)
	local at = {}
	for i, u in entries do
		at[u] = i
	end
	table.sort(order, function(a, b)
		local sa, sb = score[a] or 0, score[b] or 0
		if sa ~= sb then
			return sa > sb
		end
		return at[a] < at[b]
	end)
	for i, u in order do
		if now - (lastWin[u] or -math.huge) >= K.winEvery then
			if i > 1 then
				table.remove(order, i)
				table.insert(order, 1, u)
			end
			break
		end
	end
	return order
end

-- Can the first place go to this player? (the placings above already moved a recent winner down)
function ContestRules.canWin(K: any, lastWin: number?, now: number): boolean
	return now - (lastWin or -math.huge) >= K.winEvery
end

-- Credits for a place (1 to 3, else entry pay); a skipped contest pays showedUp
function ContestRules.pay(K: any, place: number?, skipped: boolean): number
	if skipped then
		return K.pay.showedUp
	end
	return (
		if place == 1
			then K.pay.first
			elseif place == 2 then K.pay.second
			elseif place == 3 then K.pay.third
			else 0
	) + K.pay.entry
end

-- The stage at a corner of the plaza around the Beacon Tower (bx, bz its centre)
function ContestRules.stage(K: any, bx: number, bz: number): (number, number)
	return bx + K.stage.corner, bz + K.stage.corner
end

-- A pad's offset from the stage centre (8 pads: two rows of four)
function ContestRules.pad(K: any, i: number): (number, number)
	local col = (i - 1) % 4
	local row = (i - 1) // 4
	return (col - 1.5) * K.stage.padGap, (row - 0.5) * K.stage.padGap
end

return ContestRules
