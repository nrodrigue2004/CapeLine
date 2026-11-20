--!strict
-- ImpactFrames: the plan for a big blow's impact frames (first-30, nate 2026-11-20: hit stop, freeze and flash
-- frames; "the game being cinematic is also one of the most important things"; Config.Cinema.impactFrames).
-- Pure, so Lune checks it; Fx.ImpactFrameFx draws it. A crit, a super's hit or a finisher (a boss's phase or
-- fall, an elite down, a fake unmasked) cuts the screen to 2 to 4 stark black and white frames with ink lines
-- from the hit. Reduce flashing never cuts: it gets a gentle hit stop instead. A hail of hits cuts once (gap).

local ImpactFrames = {}

export type Frame = { look: string, from: number, to: number } -- seconds from the cut's start
export type Plan = {
	kind: string,
	frames: { Frame },
	seconds: number, -- how long the cut holds in all (the game holds still for it)
	lines: number,
	width: { number },
	gentle: number?, -- Reduce flashing: only this hit stop, no frames
}

-- The cut for `kind` ("crit", "super" or "finisher") in `style` ("Comic" or "Anime") now, given the last cut's
-- kind and time (`last`: { kind, at }); nil when none may cut now. Updates `last` when it plans one.
function ImpactFrames.plan(
	Config: any,
	kind: string,
	style: string?,
	reduceFlashing: boolean,
	now: number,
	last: { kind: string?, at: number }
): Plan?
	local I = Config.Cinema.impactFrames
	local n = I.frames[kind]
	if not I.on or not n then
		return nil
	end
	local rank = I.order[kind]
	local lastRank = if last.kind then I.order[last.kind] or 0 else 0
	if rank <= lastRank and now - last.at < I.gap[kind] then
		return nil -- a hail of hits cuts once
	end
	if rank < lastRank and now - last.at < I.gap[last.kind :: string] then
		return nil -- never a smaller cut right over a bigger one
	end
	last.kind, last.at = kind, now
	if reduceFlashing then
		return { kind = kind, frames = {}, seconds = I.gentle, lines = 0, width = { 0, 0 }, gentle = I.gentle }
	end
	local st = if style == "Anime" then "Anime" else "Comic"
	local looks = I.looks[st]
	local frames = table.create(n)
	for i = 1, n do
		table.insert(
			frames,
			{ look = looks[(i - 1) % #looks + 1], from = (i - 1) * I.frame, to = i * I.frame }
		)
	end
	return { kind = kind, frames = frames, seconds = n * I.frame, lines = I.lines[st], width = I.width[st] }
end

-- The frame showing `t` seconds into a cut (nil once it is over)
function ImpactFrames.at(plan: Plan, t: number): Frame?
	for _, f in plan.frames do
		if t >= f.from and t < f.to then
			return f
		end
	end
	return nil
end

-- Line `i` of `n`: its angle (radians) and thickness (px), the same for a given seed (no flicker between frames)
function ImpactFrames.line(plan: Plan, i: number, seed: number): (number, number)
	local n = math.max(1, plan.lines)
	local h = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453
	local j = h - math.floor(h) -- 0 to 1
	local angle = (i - 1 + (j - 0.5) * 0.7) / n * math.pi * 2
	local w = plan.width[1] + (plan.width[2] - plan.width[1]) * j
	return angle, w
end

return ImpactFrames
