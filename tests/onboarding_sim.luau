-- The onboarding timeline (overnight queue item 8, 2026-11-18): a brand-new player's first minutes as plain
-- data, from join to the first incident, built from the real numbers (Config.Story.opening, Config.Ui.prologue,
-- Config.Story.guides, Shared.OpeningPlan and Shared.GuidePlan). tests/onboarding_test.luau checks it; a
-- scratch script can print it for any Config (the report's before and after).
--
-- A row is one stretch of the first minutes: { name, t0, t1, kind, goal, gap, lines }:
--   kind "feedback" (the loading screen's spinner and status), "wait" (nothing on screen to do or watch),
--   "player" (the player's own pace: the creator), "watch" (a camera beat or a timed beat: lines and
--   overlays), "play" (the hero has control and a goal)
--   goal: what the screen asks for ("watch", a marker word, "fight", "create") or nil
--   gap: the longest stretch inside the row with nothing to do or watch (a watch row's time with no line or
--   overlay up; a wait row is all gap)
--
-- The nominal player (seconds): reacts 1 s into each play beat, runs at Config.Move.run.speed, presses the
-- Spark at once, makes the first hop on the scripted 1.9 s arc (PrologueFx.slowLeap) and every chase hop in
-- 3 s (charge, flight, landing and aim). Places past the chase are its stuck limits (the player's own time).

local OpeningPlan = require("../src/shared/OpeningPlan")
local GuidePlan = require("../src/shared/GuidePlan")

local Sim = {}

Sim.REACT = 1
Sim.ARC = 1.9 -- PrologueFx.slowLeap's scripted first hop
Sim.HOP = 3
Sim.PICK = 2 -- the Ceremony's choice card: the nominal player picks in this long (act1-choices)
Sim.LOAD = 6 -- a typical load on a phone (the screen gives up at 12 s)
Sim.CREATOR_DELAY = 1.5 -- CreatorService: task.delay(1.5, CreatorService.createFirst) after the profile loads
Sim.FADE = 0.45 -- the loading screen's fade out
Sim.CREATOR = 45 -- the player's own time in the creator (not counted as waiting)

-- The beats with a place to reach (OpeningService's target())
Sim.TARGETS = { run = true, spark = true, leap = true, chase = true, descend = true, tunnel = true }
-- The overlays a camera beat shows besides its lines: { from (share of the beat), to }
Sim.OVERLAYS = { scan = { 0.42, 1 }, title = { 0.55, 1 } } -- SPARK DETECTED, the CAPELINE title card

-- How long the nominal player takes in a play beat
function Sim.playTime(Config: any, step: string): number
	local O = Config.Story.opening
	if step == "run" then
		local d = (O.run.minD + O.run.maxD) / 2 - O.spark.reach
		return Sim.REACT + d / Config.Move.run.speed
	elseif step == "spark" then
		-- act1-choices: the Ceremony's choice comes `delay` s after the Spark; the player picks in Sim.PICK s
		return Sim.REACT + O.pick.delay + Sim.PICK + O.pick.after
	elseif step == "leap" then
		return Sim.REACT + Sim.ARC
	elseif step == "chase" then
		return (O.roofs.count - 2) * Sim.HOP
	end
	return OpeningPlan.limit(Config, step)
end

-- The largest stretch of [0, dur] that no span covers
local function largestGap(spans: { { number } }, dur: number): number
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	local reach, gap = 0, 0
	for _, s in spans do
		local a, b = math.clamp(s[1], 0, dur), math.min(dur, s[2])
		if a > reach then
			gap = math.max(gap, a - reach)
		end
		reach = math.max(reach, b)
	end
	return math.max(gap, dur - reach)
end

-- The lines a beat shows for this run, how long each stays up, and the stretch with none
-- carried: the beat before's unheard lines (taken by a play beat only). Returns rows { at, who, text, shown, read }
function Sim.beatLines(
	Config: any,
	step: string,
	side: string,
	dur: number,
	carried: { any }?
): ({ any }, { any })
	local own = OpeningPlan.lines(Config, step, side)
	local list = own
	if not OpeningPlan.CUT[step] and not OpeningPlan.timed(Config, step) then
		list = GuidePlan.withCarry(Config, carried or {}, own)
	end
	local rows = {}
	for i, l in list do
		local span = GuidePlan.span(Config, list, i)
		table.insert(rows, {
			at = l.at,
			who = l.who,
			text = l.text,
			shown = math.clamp(dur - l.at, 0, span),
			read = GuidePlan.duration(Config, l.text),
		})
	end
	return rows, list
end

-- The whole timeline for a side: the rows, plus when the hero first has control, when the Spark fires and
-- when the city's first incident can spawn (all seconds from join)
function Sim.timeline(Config: any, side: string, opts: { carry: boolean? }?): { [string]: any }
	local carryOn = not (opts and opts.carry == false)
	local P = Config.Ui.prologue
	local rows = {}
	local t = 0
	local function add(row: { [string]: any })
		row.t0 = t
		row.t1 = t + row.dur
		t = row.t1
		table.insert(rows, row)
	end
	add({ name = "loading", kind = "feedback", dur = Sim.LOAD, goal = "wait (spinner, status)", gap = 0 })
	-- the screen goes once the hero is loaded; the creator opens CREATOR_DELAY after the profile loads
	local wait = math.max(0, Sim.CREATOR_DELAY - Sim.FADE)
	add({ name = "to creator", kind = "wait", dur = wait, goal = nil, gap = wait })
	add({ name = "creator", kind = "player", dur = Sim.CREATOR, goal = "create", gap = 0 })
	local prologueAt = t
	local firstControl, sparkAt = nil, nil
	local carried: { any } = {}
	local heard: { [string]: number } = {} -- each line's longest time up (by text)
	for _, step in OpeningPlan.STEPS do
		local cut = OpeningPlan.CUT[step] == true
		local timed = OpeningPlan.timed(Config, step)
		local dur = if timed then OpeningPlan.limit(Config, step) else Sim.playTime(Config, step)
		local lines, list = Sim.beatLines(Config, step, side, dur, if carryOn then carried else nil)
		for _, l in lines do
			heard[l.text] = math.max(heard[l.text] or 0, l.shown)
		end
		local kind = if cut or timed then "watch" else "play"
		local goal: string? = nil
		local gap = 0
		if kind == "watch" then
			local spans = {}
			for _, l in lines do
				table.insert(spans, { l.at, l.at + l.shown })
			end
			local ov = Sim.OVERLAYS[step]
			if ov then
				table.insert(spans, { ov[1] * dur, ov[2] * dur })
			end
			gap = largestGap(spans, dur)
			goal = "watch"
		else
			if Sim.TARGETS[step] then
				goal = P.goals[step]
			elseif table.find(P.verbs[step] or {}, "Basic") then
				goal = "fight"
			end
			firstControl = firstControl or t
			if step == "spark" then
				sparkAt = t + Sim.REACT
			end
		end
		add({
			name = step,
			kind = kind,
			dur = dur,
			goal = goal,
			gap = gap,
			lines = lines,
			verbs = P.verbs[step],
		})
		-- what a quick player left unheard goes on to the next play beat
		if carryOn and not cut then
			carried = GuidePlan.unheard(Config, list, dur, P.heard, P.carry)
		else
			carried = {}
		end
	end
	return {
		rows = rows,
		prologueAt = prologueAt,
		firstControl = firstControl,
		sparkAt = sparkAt,
		incidentAt = t + 2, -- IncidentService: a hero out of a scene gets its first incident 2 s later
		heard = heard,
		total = t - prologueAt,
	}
end

-- One line per row, for a report
function Sim.format(tl: { [string]: any }): string
	local out = {}
	for _, r in tl.rows do
		table.insert(
			out,
			string.format(
				"%6.1f-%6.1f  %-10s %-8s goal=%-22s gap=%.1f",
				r.t0,
				r.t1,
				r.name,
				r.kind,
				tostring(r.goal),
				r.gap
			)
		)
	end
	table.insert(
		out,
		string.format(
			"prologue starts %.1f; first control %.1f (+%.1f); first_spark %.1f (+%.1f); prologue %.1f s; first incident %.1f",
			tl.prologueAt,
			tl.firstControl or -1,
			(tl.firstControl or 0) - tl.prologueAt,
			tl.sparkAt or -1,
			(tl.sparkAt or 0) - tl.prologueAt,
			tl.total,
			tl.incidentAt
		)
	)
	return table.concat(out, "\n")
end

return Sim
