-- Anti-exploit checks (spec: Server architecture > Anti-exploit checks). Leans toward not punishing
-- players (nate, 2026-11-15): a failed speed check only pulls the hero back. Only teleport-sized jumps count
-- as strikes, and 3 strikes in 10 minutes kick with a generic message. No automatic bans.
return {
	sampleRate = 10, -- MoveGuard position samples per second
	burstSeconds = 0.5, -- the speed budget can bank this much travel, so network jitter never trips it
	slack = 8, -- studs always allowed on top
	strikeFactor = 3, -- a jump this many times over the budget is a strike (teleport-sized)
	strikes = { kickAt = 3, window = 600 },
	-- after a strike, fails in the next this many seconds only pull back (MoveCorrect has to reach the
	-- device; a lag spike's stale positions are the same evidence, not new strikes)
	strikeGrace = 3,
	grantKeep = 1.0, -- seconds a granted dash allowance lasts
}
