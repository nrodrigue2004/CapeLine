--!strict
-- LocoMath: how a drawn rig's ground walk plays Roblox's own R15 idle, walk and run animations (quality pass,
-- 2026-11-18, nate: "the enemies dont move properly"). The same blend Roblox's default Animate script gives
-- every hero: under `still` studs/s the idle plays; above it the walk, crossfading into the run between
-- `walkAt` and `runAt`, each sped up or slowed so the feet keep pace with the ground (timewarp = speed over
-- the speed the clip was made for). A taller body takes longer strides, so its speeds scale with its leg
-- length over the standard R15 leg (heightScale, like Animate's HipHeight / 2).
-- Pure: no Roblox instances, so Lune tests it. EnemyRenderer uses it; cfg is Config.Enemies.look.loco.

local LocoMath = {}

export type Cfg = {
	still: number, -- studs/s: slower than this is standing (idle)
	walkAt: number, -- studs/s the walk clip was made for (timewarp 1) at heightScale 1
	runAt: number, -- the same for the run clip; between walkAt and runAt the two crossfade at timewarp 1
	refLeg: number, -- the standard R15 leg (soles to hips) in studs
	minWarp: number, -- the slowest a walk plays (a robot easing to a stop)
	maxWarp: number, -- the fastest a run plays (a fast small robot's patter)
}

export type Blend = {
	idle: number, -- weights, summing to 1
	walk: number,
	run: number,
	walkSpeed: number, -- playback speeds (timewarps)
	runSpeed: number,
}

-- How much bigger than the standard R15 body a rig's stride is: its leg (the root's height above the soles
-- less the root's height above the hips) over the standard leg
function LocoMath.heightScale(ground: number, hip: number, cfg: Cfg): number
	return math.max(0.25, (ground - hip) / cfg.refLeg)
end

-- The three clips' weights and speeds for a body moving at `speed` studs/s with this heightScale
function LocoMath.blend(speed: number, heightScale: number, cfg: Cfg): Blend
	local s = math.max(0, speed) / math.max(0.25, heightScale)
	if s < cfg.still then
		return { idle = 1, walk = 0, run = 0, walkSpeed = 1, runSpeed = 1 }
	end
	if s <= cfg.walkAt then
		local w = math.clamp(s / cfg.walkAt, cfg.minWarp, 1)
		return { idle = 0, walk = 1, run = 0, walkSpeed = w, runSpeed = 1 }
	end
	if s < cfg.runAt then
		local k = (s - cfg.walkAt) / (cfg.runAt - cfg.walkAt)
		return { idle = 0, walk = 1 - k, run = k, walkSpeed = 1, runSpeed = 1 }
	end
	return {
		idle = 0,
		walk = 0,
		run = 1,
		walkSpeed = 1,
		runSpeed = math.min(s / cfg.runAt, cfg.maxWarp),
	}
end

-- How far the feet travel in one second at this blend, for the tests: a clip covers its made-for speed at
-- timewarp 1, so the blend covers the weighted sum of each clip's speed times its timewarp, scaled by the body
function LocoMath.covered(b: Blend, heightScale: number, cfg: Cfg): number
	return (b.walk * cfg.walkAt * b.walkSpeed + b.run * cfg.runAt * b.runSpeed) * heightScale
end

-- The code-posed walk's stride for robots beyond the animated range (EnemyRenderer.pose): the phase advances
-- by 2 pi per two steps, each step about 2 * leg * sin(swing) long, so the feet keep pace with the ground
-- instead of skating. Radians per second, capped so a fast small robot's legs do not blur.
function LocoMath.phaseRate(speed: number, leg: number, swing: number): number
	local step = 2 * math.max(0.3, leg) * math.sin(math.max(swing, math.rad(15)))
	return math.min(2 * math.pi * math.max(0, speed) / (2 * step), 26)
end

-- Which drawn people play Roblox's own clips this frame (citizens, 2026-11-19): those within `near` studs of the
-- camera, nearest first, at most `max` (a phone animates only the few closest; the rest keep the cheap code
-- poses). One already animated counts as `keep` times nearer (and may stay out to near * keep), so a person at
-- the edge does not start and stop its clips every frame. rows: { id, dist }. Returns the chosen ids.
function LocoMath.pickAnimated(
	rows: { { id: number, dist: number } },
	current: { [number]: any },
	near: number,
	max: number,
	keep: number?
): { [number]: boolean }
	local k = keep or 1.15
	local cand: { { id: number, d: number } } = {}
	for _, r in rows do
		local d = if current[r.id] then r.dist / k else r.dist
		if d < near then
			table.insert(cand, { id = r.id, d = d })
		end
	end
	table.sort(cand, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.id < b.id
	end)
	local out: { [number]: boolean } = {}
	for i = 1, math.min(max, #cand) do
		out[cand[i].id] = true
	end
	return out
end

-- A person's own idle (citizens): which of the idle clips (weighted, like Animate's idle list), how fast it
-- plays and where in the loop it starts (0..1), all from its id's hash, so a crowd does not breathe in step
-- and everyone sees the same idle on a citizen. idles: { { id, weight } }; rate: { slowest, fastest }.
function LocoMath.idlePick(h: number, idles: { { any } }, rate: { number }): (number, number, number)
	local total = 0
	for _, e in idles do
		total += e[2]
	end
	local roll = h % math.max(1, total)
	local pick = 1
	for i, e in idles do
		if roll < e[2] then
			pick = i
			break
		end
		roll -= e[2]
	end
	local speed = rate[1] + (rate[2] - rate[1]) * ((h // 97) % 1000) / 999
	local offset = ((h // 7919) % 1000) / 1000
	return pick, speed, offset
end

return LocoMath
