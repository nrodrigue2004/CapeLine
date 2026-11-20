--!strict
-- PrologueCine: the Ceremony prologue as a directed cinematic, from the run off the plaza to the subway fight
-- (prologue-cine, nate 2026-11-20: "dont have the player run to the gold marker. whole prologue needs to be cutscene
-- with qtes until subway"; and 2026-11-19: "It should be a cutscene with QTE's. whole thing should be like that
-- until you have to fight them"). Pure, from the route the server sends (Shared.OpeningPlan.route) and the subway
-- lane, so Lune checks every beat: every move is authored, every prompt has a way through, nothing waits on a
-- marker, and each beat's worst case fits its stuck timer.
-- * beat(Config, o, step, hop): the segments of one beat (the chase: of one hop, roofs[hop - 1] to roofs[hop]), in
--   order. A segment is one authored move of the hero (a run along the street or the tunnel, an arc: a vault, a
--   roll, a hop, the big leap, a drop, a climb; or a stand: the Spark, the suit), the HeroAnim clip it plays, its
--   camera shot (cut or eased), and optionally the quick-time prompt that starts it (Shared.QtePlan) with the
--   moment the device draws for it (a fleeing man, a barrier, the falling sign, Skylance's spear, a ledge, a
--   slab, a debris pile, a beam) and what a miss looks like (a near miss: never damage).
-- * runAt / arcAt: the hero's feet at f (0 to 1) of a move; camera(Config, shot, ...): a shot's position and look
--   (the device pulls it in front of any building between it and the hero, like Roblox's own camera).
-- * worst(Config, segs): the longest a beat's segments can take (every prompt missed until the 3rd-miss help).
-- The server stays the judge of the beats (OpeningService): the hero's body really moves along these paths (the
-- device drives it, MoveController.travel, and the server grants the travel), so its position checks (at the spark
-- point, on each roof, at the subway steps, in the fight chamber) move the story on, and every beat keeps its stuck
-- timer. The suit (no move) is the one beat the device reports done (OpeningAct 7).

local QtePlan = if script then require(script.Parent.QtePlan) else (require :: any)("./QtePlan")
local OpeningPlan = if script then require(script.Parent.OpeningPlan) else (require :: any)("./OpeningPlan")

local PrologueCine = {}

export type Point = { number }
-- (Prompt, repeated: the pure-module require pattern drops cross-module types)
export type Prompt = { action: string, word: string, kind: string?, count: number?, hold: number? }
export type Seg = {
	id: string,
	prompt: Prompt?,
	move: string, -- "run" (along `path`), "arc" (from -> to over `height`) or "stand"
	path: { Point }?,
	from: Point,
	to: Point,
	time: number,
	height: number?,
	clip: string?, -- the hero's pose during the move (HeroAnimator's cine mode clip)
	start: string?, -- a one-shot clip as the move starts
	land: string?, -- a one-shot clip as it ends
	wait: string?, -- the pose while its prompt waits (in slow motion)
	shot: string, -- the camera: track, front, side, low, wide, top, ledge, over or orbit
	cut: boolean?, -- a hard cut into this shot (else the camera eases over)
	slow: boolean?, -- the big leap's slow motion
	fx: string?, -- the moment PrologueFx draws for the prompt
	at: Point?, -- where that moment is
	near: string?, -- what a miss looks like
	spark: boolean?, -- the prompt fires the Spark (OpeningAct 1)
	cue: boolean?, -- the device reports this beat done when the segment ends (OpeningAct 7)
}

-- The beats this module directs (Config.Story.opening.qte.beats)
function PrologueCine.directed(Config: any, step: string?): boolean
	return step ~= nil and Config.Story.opening.qte.beats[step] == true
end

-- The hero's controls rest from the ceremony until the subway fight (CUT beats included): no free movement, no
-- casts, no swings; the prompts are the only input
function PrologueCine.frozen(step: string?): boolean
	local c = step and OpeningPlan.CODE[step]
	return c ~= nil and c < OpeningPlan.CODE.fight
end

local function sub(a: Point, b: Point): Point
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function flatLen(a: Point, b: Point): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function len(a: Point, b: Point): number
	local d = sub(a, b)
	return math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
end

local function lerp(a: Point, b: Point, f: number): Point
	return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end

-- the flat unit direction a -> b (and its right-hand side)
local function dirOf(a: Point, b: Point): (number, number)
	local dx, dz = b[1] - a[1], b[3] - a[3]
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-3 then
		return 0, -1
	end
	return dx / l, dz / l
end

-- A polyline's length
function PrologueCine.length(path: { Point }): number
	local t = 0
	for i = 2, #path do
		t += len(path[i - 1], path[i])
	end
	return t
end

-- The point `d` studs along a polyline (clamped to its ends)
function PrologueCine.along(path: { Point }, d: number): Point
	if d <= 0 then
		return path[1]
	end
	local left = d
	for i = 2, #path do
		local l = len(path[i - 1], path[i])
		if left <= l and l > 0 then
			return lerp(path[i - 1], path[i], left / l)
		end
		left -= l
	end
	return path[#path]
end

-- The part of a polyline from d0 to d1 studs along it
function PrologueCine.slice(path: { Point }, d0: number, d1: number): { Point }
	local out = { PrologueCine.along(path, d0) }
	local acc = 0
	for i = 2, #path do
		acc += len(path[i - 1], path[i])
		if acc > d0 and acc < d1 then
			table.insert(out, path[i])
		end
	end
	table.insert(out, PrologueCine.along(path, d1))
	return out
end

-- The hero's feet at f of a run along `path`
function PrologueCine.runAt(path: { Point }, f: number): Point
	return PrologueCine.along(path, PrologueCine.length(path) * math.clamp(f, 0, 1))
end

-- The hero's feet at f of an arc: a straight line from `from` to `to` lifted by a parabola that peaks `height` over
-- the higher end
function PrologueCine.arcAt(from: Point, to: Point, height: number, f: number): Point
	f = math.clamp(f, 0, 1)
	local p = lerp(from, to, f)
	local peak = math.max(from[2], to[2]) + height
	p[2] += 4 * f * (1 - f) * (peak - (from[2] + to[2]) / 2)
	return p
end

-- A segment's feet point at f
function PrologueCine.at(seg: Seg, f: number): Point
	if seg.move == "run" and seg.path then
		return PrologueCine.runAt(seg.path, f)
	elseif seg.move == "arc" then
		return PrologueCine.arcAt(seg.from, seg.to, seg.height or 0, f)
	end
	return seg.from
end

-- The roof's feet point (route roofs are 1.5 over the roof)
local function roofFeet(p: Point): Point
	return { p[1], p[2] - 1.5, p[3] }
end

-- Where a hop toward roof `to` (its centre, half sizes hx, hz) meets the roof's near wall, coming from `from`:
-- the hang point just outside the wall, `drop` studs below the roof (the long hop's ledge grab)
function PrologueCine.ledge(from: Point, to: Point, half: { number }?, drop: number): Point
	local ux, uz = dirOf(to, from) -- from the roof's centre back toward the hero
	local hx, hz = if half then half[1] else 6, if half then half[2] else 6
	local tx = if math.abs(ux) > 1e-3 then hx / math.abs(ux) else math.huge
	local tz = if math.abs(uz) > 1e-3 then hz / math.abs(uz) else math.huge
	local t = math.min(tx, tz, flatLen(from, to) * 0.5) + 0.8
	return { to[1] + ux * t, to[2] - 1.5 - drop, to[3] + uz * t }
end

local function press(action: string, word: string): Prompt
	return { action = action, word = word, kind = "press" }
end

-- The run off the plaza: through the fleeing crowd to the spark point, a DODGE and a JUMP on the way
local function runBeat(Config: any, o: any): { Seg }
	local Q = Config.Story.opening.qte
	local W = Q.words
	local path: { Point } = o.runPath or { o.start, o.spark }
	local L = PrologueCine.length(path)
	local v = Q.speed.run
	local d1, d2 = L * 0.34, L * 0.66
	local out: { Seg } = {}
	local function run(id: string, a: number, b: number, shot: string, cut: boolean?): Seg
		local p = PrologueCine.slice(path, a, b)
		return {
			id = id,
			move = "run",
			path = p,
			from = p[1],
			to = p[#p],
			time = math.max(0.3, (b - a) / v),
			clip = "sprint",
			shot = shot,
			cut = cut,
		}
	end
	table.insert(out, run("bolt", 0, d1, "front", true))
	-- a fleeing man barrels straight at the hero: DODGE rolls aside
	local r0 = PrologueCine.along(path, d1)
	local r1 = PrologueCine.along(path, d1 + 6)
	local rx, rz = dirOf(r0, r1)
	local rollTo = { r1[1] - rz * 3, r1[2], r1[3] + rx * 3 }
	table.insert(out, {
		id = "dodge",
		prompt = press("Block", W.Block),
		move = "arc",
		from = r0,
		to = rollTo,
		time = 6 / Q.speed.roll + 0.1,
		height = Q.arc.roll,
		clip = "dash",
		land = "landRoll",
		wait = "brace",
		shot = "low",
		cut = true,
		fx = "runner",
		at = PrologueCine.along(path, d1 + 14),
		near = "bump",
	})
	table.insert(out, run("run2", d1 + 6, d2, "track", true))
	-- a crowd barrier knocked flat across the street: JUMP over it
	local v0 = PrologueCine.along(path, d2)
	local v1 = PrologueCine.along(path, d2 + 8)
	table.insert(out, {
		id = "vault",
		prompt = press("Leap", W.Leap),
		move = "arc",
		from = v0,
		to = v1,
		time = 0.7,
		height = Q.arc.vault,
		clip = "arc",
		start = "airFlip",
		land = "land",
		wait = "leapCrouch",
		shot = "side",
		cut = true,
		fx = "barrier",
		at = PrologueCine.along(path, d2 + 4),
		near = "trip",
	})
	table.insert(out, run("run3", d2 + 8, L, "track", true))
	return out
end

-- The Spark: the sign comes down on the kid (SHIELD), or the man who shoved the villain (SMASH)
local function sparkBeat(Config: any, o: any, side: string): { Seg }
	local W = Config.Story.opening.qte.words
	local here = o.spark
	local kid = o.kid or o.spark
	local shield = OpeningPlan.sparkBeat(side) == "shield"
	return {
		{
			id = "spark",
			prompt = press("Basic", if shield then W.shield else W.smash),
			move = "stand",
			from = here,
			to = here,
			time = 1.2,
			start = if shield then "blast" else "palmPush",
			wait = "powerCharge",
			shot = "over",
			cut = true,
			fx = if shield then "sign" else "shove",
			at = kid,
			near = if shield then "sign" else "shove",
			spark = true,
		},
	}
end

-- The big leap: up on the first roof (the cut), one JUMP and a slow-motion arc to the next
local function leapBeat(Config: any, o: any): { Seg }
	local Q = Config.Story.opening.qte
	local a, b = roofFeet(o.roofs[1]), roofFeet(o.roofs[2])
	return {
		{
			id = "ready",
			move = "stand",
			from = a,
			to = a,
			time = 0.8,
			clip = "leapCrouch",
			shot = "low",
			cut = true,
		},
		{
			id = "leap",
			prompt = press("Leap", Q.words.Leap),
			move = "arc",
			from = a,
			to = b,
			time = Q.arc.leapTime,
			height = Q.arc.leap,
			clip = "arc",
			start = "airFlip",
			land = "landHard",
			wait = "leapCrouch",
			shot = "wide",
			cut = true,
			slow = true,
			near = "teeter",
		},
	}
end

-- One hop of the rooftop chase: roofs[hop - 1] to roofs[hop] (a DODGE first on Config's dodge roofs; the long hop
-- falls short and is a GRAB at the ledge and a climb)
local function chaseHop(Config: any, o: any, hop: number): { Seg }
	local Q = Config.Story.opening.qte
	local W = Q.words
	local roofs = o.roofs
	local i = math.clamp(hop, 2, #roofs)
	local a, b = roofFeet(roofs[i - 1]), roofFeet(roofs[i])
	local out: { Seg } = {}
	local dx, dz = dirOf(a, b)
	local from = a
	if Q.dodge[i] then
		local side = if i % 2 == 0 then 1 else -1
		local to = { a[1] - dz * Q.side * side, a[2], a[3] + dx * Q.side * side }
		table.insert(out, {
			id = "dodge",
			prompt = press("Block", W.Block),
			move = "arc",
			from = a,
			to = to,
			time = 0.35,
			height = Q.arc.roll,
			clip = "dash",
			land = "landRoll",
			wait = "brace",
			shot = "front",
			cut = true,
			fx = "spear",
			at = a,
			near = "spear",
		})
		from = to
	end
	local last = i >= #roofs
	local shots = { "side", "track", "side", "front" }
	if Q.grab == i then
		local half = o.roofHalf and o.roofHalf[i]
		local hang = PrologueCine.ledge(from, b, half, 6.5)
		local t, h = OpeningPlan.hopArc(Config, { from[1], from[2] + 1.5, from[3] }, b)
		table.insert(out, {
			id = "jump",
			prompt = press("Leap", W.Leap),
			move = "arc",
			from = from,
			to = hang,
			time = t,
			height = h * 0.6,
			clip = "arc",
			land = "wallGrab",
			wait = "leapCrouch",
			shot = "side",
			cut = true,
			near = "teeter",
		})
		table.insert(out, {
			id = "grab",
			prompt = press("Catch", W.Catch),
			move = "arc",
			from = hang,
			to = b,
			time = 0.75,
			height = Q.arc.climb,
			clip = "wall",
			start = "wallKick",
			land = "land",
			wait = "wall",
			shot = "ledge",
			cut = true,
			fx = "ledge",
			at = hang,
			near = "slip",
		})
		return out
	end
	local t, h = OpeningPlan.hopArc(Config, { from[1], from[2] + 1.5, from[3] }, b)
	table.insert(out, {
		id = "jump",
		prompt = press("Leap", W.Leap),
		move = "arc",
		from = from,
		to = b,
		time = t,
		height = h,
		clip = "arc",
		land = if i % 2 == 0 then "landRoll" else "land",
		wait = "leapCrouch",
		shot = if last then "low" else shots[(i % #shots) + 1],
		cut = true,
		near = "teeter",
	})
	return out
end

-- The suit: HOLD to let the Spark build it (the pieces snap on), then SUIT UP
local function suitBeat(Config: any, o: any): { Seg }
	local Q = Config.Story.opening.qte
	local here = roofFeet(o.roofs[#o.roofs])
	return {
		{
			id = "suit",
			prompt = { action = "Block", word = Q.words.suit, kind = "hold" },
			move = "stand",
			from = here,
			to = here,
			time = 1.9,
			start = "raise",
			wait = "powerCharge",
			shot = "orbit",
			cut = true,
			fx = "suit",
			at = here,
			near = "fizzle",
			cue = true,
		},
	}
end

-- The drop off the last roof to the subway steps
local function descendBeat(Config: any, o: any): { Seg }
	local Q = Config.Story.opening.qte
	local a = roofFeet(o.roofs[#o.roofs])
	local b = o.entrance
	local t = OpeningPlan.hopArc(Config, { a[1], a[2] + 1.5, a[3] }, b)
	return {
		{
			id = "drop",
			prompt = press("Leap", Q.words.drop),
			move = "arc",
			from = a,
			to = b,
			time = t + 0.4,
			height = 8,
			clip = "arc",
			land = "landHard",
			wait = "leapCrouch",
			shot = "top",
			cut = true,
			near = "teeter",
		},
	}
end

-- The tunnel: a chase down the lane with the roof caving in behind (PrologueFx's slabs), a DODGE under a falling
-- chunk, a JUMP over a debris pile, a beam that pins the hero (mash to BREAK FREE), then into the fight chamber
local function tunnelBeat(Config: any, o: any): { Seg }
	local Q = Config.Story.opening.qte
	local S = Config.Story.opening.subway
	local W = Q.words
	local lane = o.lane
	local a = { lane.x, lane.floorY, lane.z0 - 8 }
	local b = { lane.x, lane.floorY, lane.z1 - 10 }
	local path = { a, b }
	local L = PrologueCine.length(path)
	local v = Q.speed.tunnel
	local out: { Seg } = {}
	local function run(id: string, d0: number, d1: number, shot: string): Seg
		local p = PrologueCine.slice(path, d0, d1)
		return {
			id = id,
			move = "run",
			path = p,
			from = p[1],
			to = p[#p],
			time = math.max(0.3, (d1 - d0) / v),
			clip = "sprint",
			shot = shot,
			cut = true,
		}
	end
	local function pt(d: number, side: number?): Point
		local p = PrologueCine.along(path, d)
		return { p[1] + (side or 0), p[2], p[3] }
	end
	local k = S.length / 300 -- the beats' spots scale with the tunnel (300 studs as tuned)
	table.insert(out, run("go", 0, 72 * k, "front"))
	table.insert(out, {
		id = "dodge",
		prompt = press("Block", W.Block),
		move = "arc",
		from = pt(72 * k),
		to = pt(80 * k, 3),
		time = 8 * k / Q.speed.roll + 0.1,
		height = Q.arc.roll,
		clip = "dash",
		land = "landRoll",
		wait = "brace",
		shot = "low",
		cut = true,
		fx = "slab",
		at = pt(78 * k),
		near = "slab",
	})
	table.insert(out, run("run2", 80 * k, 146 * k, "track"))
	table.insert(out, {
		id = "vault",
		prompt = press("Leap", W.Leap),
		move = "arc",
		from = pt(146 * k),
		to = pt(156 * k),
		time = 0.7,
		height = Q.arc.vault,
		clip = "arc",
		start = "airFlip",
		land = "land",
		wait = "leapCrouch",
		shot = "track",
		cut = true,
		fx = "pile",
		at = pt(151 * k),
		near = "trip",
	})
	table.insert(out, run("run3", 156 * k, 204 * k, "front"))
	table.insert(out, {
		id = "beam",
		prompt = { action = "Basic", word = W.mash, kind = "mash" },
		move = "stand",
		from = pt(204 * k),
		to = pt(204 * k),
		time = 0.8,
		start = "heave",
		wait = "brace",
		shot = "low",
		cut = true,
		fx = "beam",
		at = pt(204 * k),
		near = "beam",
	})
	table.insert(out, run("run4", 204 * k, L, "track"))
	return out
end

-- The segments of a beat (the chase: of one hop). o: the server's state (OpeningState: route points, roofHalf,
-- runPath, lane, side)
function PrologueCine.beat(Config: any, o: any, step: string, hop: number?): { Seg }
	if step == "run" and o.start and o.spark then
		return runBeat(Config, o)
	elseif step == "spark" and o.spark then
		return sparkBeat(Config, o, o.side or "hero")
	elseif step == "leap" and o.roofs and #o.roofs >= 2 then
		return leapBeat(Config, o)
	elseif step == "chase" and o.roofs and #o.roofs >= 2 then
		return chaseHop(Config, o, hop or 3)
	elseif step == "suit" and o.roofs then
		return suitBeat(Config, o)
	elseif step == "descend" and o.roofs and o.entrance then
		return descendBeat(Config, o)
	elseif step == "tunnel" and o.lane then
		return tunnelBeat(Config, o)
	end
	return {}
end

-- Every chase hop's segments, in order (the sims; the device plays one hop at a time as the server counts them)
function PrologueCine.chase(Config: any, o: any): { Seg }
	local out = {}
	for hop = 3, #o.roofs do
		for _, s in chaseHop(Config, o, hop) do
			table.insert(out, s)
		end
	end
	return out
end

-- The longest segments can take: every move, plus each prompt's worst case (QtePlan.worst)
function PrologueCine.worst(Config: any, segs: { Seg }): number
	local t = 0
	for _, s in segs do
		t += s.time
		if s.prompt then
			t += QtePlan.worst(Config, s.prompt.kind)
		end
	end
	return t
end

-- The quickest they can be played (every prompt hit the moment it shows; a prompt shows `lead` s before the move
-- in front of it ends, so it costs nothing after a move)
function PrologueCine.quickest(_Config: any, segs: { Seg }): number
	local t = 0
	for _, s in segs do
		t += s.time
	end
	return t
end

-- The camera for a shot: its position and look point. p: the hero's feet now; seg: the segment (its from, to and
-- moment); u: 0 to 1 through it. Returns two { x, y, z }.
function PrologueCine.camera(Config: any, shot: string, p: Point, seg: Seg, u: number): (Point, Point)
	local S = Config.Story.opening.qte.shot
	local dx, dz = dirOf(seg.from, seg.to)
	if seg.move == "stand" or flatLen(seg.from, seg.to) < 0.5 then
		local at = seg.at or { p[1], p[2], p[3] - 10 }
		dx, dz = dirOf(p, at)
	end
	local sx, sz = -dz, dx -- right-hand side
	local hy = p[2] + 2.5 -- the hero's chest
	if shot == "track" then
		local c = S.track
		return { p[1] - dx * c.back, p[2] + c.up, p[3] - dz * c.back }, {
			p[1] + dx * c.ahead,
			p[2] + 2,
			p[3] + dz * c.ahead,
		}
	elseif shot == "front" then
		local c = S.front
		return { p[1] + dx * c.ahead + sx * c.side, p[2] + c.up, p[3] + dz * c.ahead + sz * c.side }, {
			p[1],
			hy,
			p[3],
		}
	elseif shot == "side" then
		local cam, look = QtePlan.camera3(
			Config,
			{ p[1], p[2] + 3, p[3] },
			{ seg.to[1], seg.to[2] + 3, seg.to[3] }
		)
		return cam, look
	elseif shot == "low" then
		local c = S.low
		local t = seg.to
		return { t[1] + sx * c.side - dx * c.back, t[2] + c.up, t[3] + sz * c.side - dz * c.back }, {
			p[1],
			hy,
			p[3],
		}
	elseif shot == "wide" then
		local c = S.wide
		local gap = flatLen(seg.from, seg.to)
		local mid = lerp(seg.from, seg.to, 0.5)
		local top = math.max(seg.from[2], seg.to[2])
		return { mid[1] + sx * gap * c.side, top + c.up + gap * c.rise, mid[3] + sz * gap * c.side }, {
			p[1],
			hy,
			p[3],
		}
	elseif shot == "top" then
		local c = S.top
		return { p[1] - dx * c.back, p[2] + c.up, p[3] - dz * c.back }, {
			p[1] + dx * 4,
			p[2] - 2,
			p[3] + dz * 4,
		}
	elseif shot == "ledge" then
		-- out from the wall the hero hangs on (the hop came from that side), a little above: the hero and the ledge
		local c = S.ledge
		return { p[1] - dx * c.back + sx * c.side, p[2] + c.up, p[3] - dz * c.back + sz * c.side }, {
			p[1],
			p[2] + 2.5,
			p[3],
		}
	elseif shot == "over" then
		local c = S.over
		local at = seg.at or p
		-- over the shoulder: past the hero to the kid (or the shover), both in frame
		return { p[1] - dx * c.back + sx * c.side, p[2] + c.up, p[3] - dz * c.back + sz * c.side }, {
			(p[1] + at[1]) / 2,
			at[2] + 2,
			(p[3] + at[3]) / 2,
		}
	end
	-- orbit: round the hero, turning `turn` degrees over the segment
	local c = S.orbit
	local a = math.rad(c.turn) * math.clamp(u, 0, 1) + math.pi * 0.25
	local ox = dx * math.cos(a) - dz * math.sin(a)
	local oz = dx * math.sin(a) + dz * math.cos(a)
	return { p[1] + ox * c.radius, p[2] + c.up, p[3] + oz * c.radius }, { p[1], hy, p[3] }
end

return PrologueCine
