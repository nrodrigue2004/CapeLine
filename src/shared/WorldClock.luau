--!strict
-- WorldClock: the shared day and night (spec: World clock "24 minutes per cycle (16 day, 3 dusk, 4 night,
-- 1 dawn)"). One server clock: every client gets the server's cycle start (World.Clock on join and every
-- 60 s) and works out the time itself. Night lets villain-side incidents and contracts spawn 30% more often;
-- no gameplay is locked to night.

local WorldClock = {}

-- Where in the cycle a time is: "day", "dusk", "night" or "dawn", and how far through that part (0 to 1)
function WorldClock.phase(cfg: any, t: number): (string, number)
	local c = t % cfg.cycle
	if c < cfg.day then
		return "day", c / cfg.day
	end
	c -= cfg.day
	if c < cfg.dusk then
		return "dusk", c / cfg.dusk
	end
	c -= cfg.dusk
	if c < cfg.night then
		return "night", c / cfg.night
	end
	c -= cfg.night
	return "dawn", math.min(1, c / cfg.dawn)
end

-- Lighting.ClockTime (hours) for a time: day runs 7:00 to 17:00, dusk to 19:30, night to 4:30, dawn to 7:00
local SPANS = {
	day = { 7, 17 },
	dusk = { 17, 19.5 },
	night = { 19.5, 28.5 },
	dawn = { 4.5, 7 },
}
function WorldClock.clockTime(cfg: any, t: number): number
	local name, f = WorldClock.phase(cfg, t)
	local s = SPANS[name]
	return (s[1] + (s[2] - s[1]) * f) % 24
end

function WorldClock.isNight(cfg: any, t: number): boolean
	return (WorldClock.phase(cfg, t)) == "night"
end

-- Lamps and neon glow from dusk to dawn
function WorldClock.lampsOn(cfg: any, t: number): boolean
	local name = WorldClock.phase(cfg, t)
	return name ~= "day"
end

return WorldClock
