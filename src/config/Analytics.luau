-- Analytics sampling and timing (spec: Analytics and KPIs). The event and funnel lists themselves live in
-- Shared.AnalyticsSchema (pure data the tests check against the spec).
return {
	-- spec: 100% sampling at launch, "reduced to 20% for combat events if volume is high"; casts run at up
	-- to 12 a second per hero, so skill_cast starts at that 20% and the budget below guards the rest
	castSample = 0.2,
	-- the server's event budget a minute: base + perPlayer x players (Roblox's custom-event throttle,
	-- verify the live numbers before launch). Busy events (lowPriority) stop at half the budget first.
	budget = { base = 120, perPlayer = 20, lowShare = 0.5 },
	lowPriority = { skill_cast = true, perf_sample = true, gear_drop = true, pvp_hit = true },
	perfSample = 0.1, -- perf_sample: 10% of devices report
	perfEvery = 60, -- seconds between a sampled device's perf reports
	helloWait = 20, -- session_device waits this long for the device's hello (platform), then logs "unknown"
	-- the favorite prompt (WP4, gap G7): once per account after the first world boss win, a plain ask with no
	-- reward (Roblox's rules). The device waits `wait` s (the result card), then for `calm` s with no hit
	-- taken, no scene and not Downed; with no such moment in `giveUp` s it asks again at the next boss win
	favorite = { wait = 8, calm = 5, giveUp = 180 },
}
