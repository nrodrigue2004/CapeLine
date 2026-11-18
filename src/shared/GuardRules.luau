--!strict
-- GuardRules: strikes and reports as plain data (spec: Anti-exploit checks; Anti-farming "Reports").
-- Moderation leans hard toward not punishing players (CLAUDE.md rule 6): a strike is only a counted flag,
-- 3 strikes in 10 minutes kick with a generic message, repeated kicks put the account in the review queue,
-- and nothing here ever bans. Reports never punish on their own: 3 from 3 different accounts in 10 minutes
-- flag the account for review.

local GuardRules = {}

-- kicking: a kick is under way (its save yields), so later strikes count nothing: one kick event is one
-- kick, never several (speed checks run at 10 Hz)
export type Strikes = {
	times: { number },
	kinds: { [string]: number },
	net: number,
	netAt: number,
	kicking: boolean,
}

function GuardRules.newStrikes(): Strikes
	return { times = {}, kinds = {}, net = 0, netAt = 0, kicking = false }
end

-- Count a strike of a kind ("speed", "remote", ...). Returns true when the rule says kick: true once, then
-- the book is cleared and stays quiet while the kick runs (GuardRules.kickDone opens it again).
function GuardRules.strike(config: any, s: Strikes, kind: string, now: number): boolean
	if s.kicking then
		return false
	end
	local c = config.Pvp.strikes
	table.insert(s.times, now)
	s.kinds[kind] = (s.kinds[kind] or 0) + 1
	local cutoff = now - c.window
	while #s.times > 0 and s.times[1] < cutoff do
		table.remove(s.times, 1)
	end
	if #s.times >= c.kickAt then
		s.kicking = true
		table.clear(s.times)
		return true
	end
	return false
end

-- The kick is done without the player leaving (Studio never kicks): strikes count from zero again
function GuardRules.kickDone(s: Strikes)
	s.kicking = false
	table.clear(s.times)
	table.clear(s.kinds)
	s.net = 0
end

-- A dropped remote call. Honest lag drops one now and then, so only every netWeight drops inside a minute
-- count one strike. Returns true when that strike says kick.
function GuardRules.netDrop(config: any, s: Strikes, now: number): boolean
	local c = config.Pvp.strikes
	if s.kicking then
		return false
	end
	if now - s.netAt > 60 then
		s.net = 0
	end
	s.netAt = now
	s.net += 1
	if s.net >= c.netWeight then
		s.net = 0
		return GuardRules.strike(config, s, "remote", now)
	end
	return false
end

-- After a kick: does this account now belong in the review queue? (kicks is the saved count)
function GuardRules.needsReview(config: any, kicks: number): boolean
	return kicks >= config.Pvp.strikes.reviewAfterKicks
end

export type Reports = {
	byPair: { [string]: number }, -- "reporter:target" -> time
	byTarget: { [number]: { { from: number, t: number } } },
	flagged: { [number]: number }, -- target -> time flagged
}

function GuardRules.newReports(): Reports
	return { byPair = {}, byTarget = {}, flagged = {} }
end

-- WP12: has `from` reported `target` on this server (any time)? A report stops the reported player's visit asks
-- to the reporter (Shared.VisitRules); it never punishes on its own.
function GuardRules.reported(book: Reports, from: number, target: number): boolean
	return book.byPair[from .. ":" .. target] ~= nil
end

-- A report from `from` on `target`. Returns accepted, flaggedNow. One per reporter per target every 10
-- minutes; never on yourself; 3 different reporters inside 10 minutes flag the target (once per window).
function GuardRules.report(
	config: any,
	book: Reports,
	from: number,
	target: number,
	now: number
): (boolean, boolean)
	local c = config.Pvp.report
	if from == target then
		return false, false
	end
	local key = from .. ":" .. target
	local last = book.byPair[key]
	if last and now - last < c.perTarget then
		return false, false
	end
	book.byPair[key] = now
	local list: { { from: number, t: number } } = book.byTarget[target] or {}
	book.byTarget[target] = list
	table.insert(list, { from = from, t = now })
	local seen: { [number]: boolean } = {}
	local distinct = 0
	local i = 1
	while i <= #list do
		local r = list[i]
		if now - r.t > c.window then
			table.remove(list, i)
		else
			if not seen[r.from] then
				seen[r.from] = true
				distinct += 1
			end
			i += 1
		end
	end
	local flaggedAt = book.flagged[target]
	if distinct >= c.flagAt and (not flaggedAt or now - flaggedAt > c.window) then
		book.flagged[target] = now
		return true, true
	end
	return true, false
end

return GuardRules
