-- Analytics sampling and timing (spec: Analytics and KPIs). The event and funnel lists themselves live in
-- Shared.AnalyticsSchema (pure data the tests check against the spec).
return {
	castSample = 0.02, -- skill_cast: 1 cast in 50 is logged (every cast would swamp the event budget)
	perfSample = 0.1, -- perf_sample: 10% of devices report
	perfEvery = 60, -- seconds between a sampled device's perf reports
	helloWait = 20, -- session_start waits this long for the device's hello (platform), then logs "unknown"
}
