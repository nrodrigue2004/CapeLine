--!strict
-- IntroFilm: a new account's first 45 seconds as one in-engine film (nate, 2026-11-20: "the first 30 seconds are almost
-- as important as the first 30 minutes"; a cold open "before anything else", then short in-engine cutscenes that
-- explain the world instead of the 4-panel intro comic; "make sure it looks very nice and isn't boring"). Pure, so
-- Lune checks it and art/intro/storyboard.luau renders its frames; Fx.IntroFilm plays it in the real city around
-- the spot the hero waits in.
-- * stage(Config, world, x, z): the city's real buildings near (x, z): the tower the hero smashes through, the
--   rooftop across the street, the street in front (the world's own boxes; the server sends it with OpeningIntro).
-- * film(Config, stage): shots (a cut every 2 to 4 s: dollies and follow shots in world space), the actors' tracks
--   (position, facing and pose by time), the events (smashes, shots, the title, the spark), the comic captions
--   and the sound words. Lore wording comes from the lore doc and the game's own lines; new wording is marked
--   draft = true for nate.
-- * camera(film, t): the camera's position and look point at t (the shot's eased move plus a decaying shake).
-- * at(track, t): an actor's position, facing (yaw) and pose clip at t.
-- Cold open 0 to 13 s (the chase, the smash through the tower, the landing, the CAPELINE title), then the world:
-- powered people are hunted, Silas Crane and his fake heroes, the Vigil and the Dread Syndicate, and your spark.

local IntroFilm = {}

export type V = { number } -- { x, y, z }
export type Shot = { t0: number, t1: number, from: V, to: V, at: V, at2: V, ease: string?, shake: number? }
export type Key = { t: number, p: V, yaw: number?, clip: string?, hide: boolean? }
export type Track = { id: string, kind: string, keys: { Key } }
export type Event = { t: number, kind: string, p: V?, q: V?, text: string?, actor: string? }
export type Caption = { t0: number, t1: number, text: string, draft: boolean?, from: string? }
export type Film = {
	seconds: number,
	coldOpen: number, -- the title lands here; the world's beats follow
	shots: { Shot },
	tracks: { Track },
	events: { Event },
	captions: { Caption },
	words: { Event },
}
export type Stage = {
	tower: { x: number, z: number, sx: number, sz: number, base: number, top: number, id: number },
	far: { x: number, z: number, sx: number, sz: number, base: number, top: number, id: number },
	street: V,
	r: V, -- the axis the hero flies along (through the tower)
	f: V, -- from the street toward the tower
	lift: { [number]: number }, -- shots raised this far so the camera clears every building on the way
	blocked: number?, -- actor samples inside a building (the stage pick keeps this at 0 where it can)
}

local function v(x: number, y: number, z: number): V
	return { x, y, z }
end
local function add(a: V, b: V): V
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end
local function mul(a: V, s: number): V
	return { a[1] * s, a[2] * s, a[3] * s }
end
local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

-- The stage near (x, z): the tallest solid tower within `reach` (not round, not a beacon's), the street on the side
-- toward (x, z), and the tallest other building 70 to 260 studs from it for the rooftop beat
local function stageFor(Config: any, world: any, tower: any, x: number, z: number, side: number): Stage
	local F = Config.Story.opening.film
	-- the street side: side 1 the face toward (x, z) along the nearer axis, 2 to 4 the other faces
	local dx, dz = x - tower.x, z - tower.z
	if side == 2 then
		dx, dz = -dx, -dz
	elseif side == 3 then
		dx, dz = dz * tower.sx / tower.sz, -dx * tower.sz / tower.sx
	elseif side == 4 then
		dx, dz = -dz * tower.sx / tower.sz, dx * tower.sz / tower.sx
	end
	local f: V, r: V, half: number
	if math.abs(dx) / tower.sx > math.abs(dz) / tower.sz then
		f = v(if dx > 0 then -1 else 1, 0, 0) -- toward the tower from the street
		r = v(0, 0, 1)
		half = tower.sx / 2
	else
		f = v(0, 0, if dz > 0 then -1 else 1)
		r = v(1, 0, 0)
		half = tower.sz / 2
	end
	local street = add(v(tower.x, tower.base, tower.z), mul(f, -(half + F.streetOut)))
	local far, farTop = nil, -math.huge
	for _, b in world.buildings do
		local d = math.sqrt((b.x - tower.x) ^ 2 + (b.z - tower.z) ^ 2)
		if
			b ~= tower
			and d >= 70
			and d <= 260
			and not b.round
			and b.top - b.base >= 30
			and b.top > farTop
		then
			-- across the street from the tower: on the street's side
			local side = (b.x - tower.x) * f[1] + (b.z - tower.z) * f[3]
			if side < 0 then
				far, farTop = b, b.top
			end
		end
	end
	far = far or tower
	local function box(b: any): any
		return { x = b.x, z = b.z, sx = b.sx, sz = b.sz, base = b.base, top = b.top, id = b.id }
	end
	local st: Stage = { tower = box(tower), far = box(far :: any), street = street, r = r, f = f, lift = {} }
	-- a shot whose camera would pass through another building rises over it (its look points stay, so it still
	-- frames the action); worked out here with the world's boxes so every device plays the same film
	local film = IntroFilm.film(Config, st)
	for i, sh in film.shots do
		local need = 0
		for k = 0, 20 do
			local e = k / 20
			local p = {
				lerp(sh.from[1], sh.to[1], e),
				lerp(sh.from[2], sh.to[2], e),
				lerp(sh.from[3], sh.to[3], e),
			}
			for _, b in world.buildings do
				if
					math.abs(p[1] - b.x) < b.sx / 2 + 2
					and math.abs(p[3] - b.z) < b.sz / 2 + 2
					and p[2] > b.base - 2
					and p[2] < (b.peak or b.top) + 3
				then
					need = math.max(need, (b.peak or b.top) + 4 - p[2])
				end
			end
		end
		if need > 0 then
			st.lift[i] = math.ceil(need)
		end
	end
	-- every actor while it shows stays in the open (the street, the air, the roofs): samples inside a building
	-- count against this stage
	local blocked = 0
	for _, tr in film.tracks do
		for t = tr.keys[1].t, tr.keys[#tr.keys].t, 0.25 do
			local p, _, _, show = IntroFilm.at(tr, t)
			if show then
				for _, b in world.buildings do
					if
						math.abs(p[1] - b.x) < b.sx / 2 - 0.5
						and math.abs(p[3] - b.z) < b.sz / 2 - 0.5
						and p[2] + 1 > b.base
						and p[2] + 1 < (b.peak or b.top)
					then
						blocked += 1
						break
					end
				end
			end
		end
	end
	st.blocked = blocked
	return st
end

-- The stage near (x, z): of the tallest solid towers within reach and each of their four street sides, the one whose
-- shots need the least lifting over other buildings (the clearest view), the side toward (x, z) first on a tie
function IntroFilm.stage(Config: any, world: any, x: number, z: number): Stage?
	local F = Config.Story.opening.film
	-- only the buildings the film can reach (the camera stays within reach + 260 of the spot): a pick is quick
	local near = {}
	for _, b in world.buildings do
		if math.sqrt((b.x - x) ^ 2 + (b.z - z) ^ 2) <= F.reach + 450 then
			table.insert(near, b)
		end
	end
	world = { buildings = near }
	local list = {}
	for _, b in world.buildings do
		local d = math.sqrt((b.x - x) ^ 2 + (b.z - z) ^ 2)
		if
			d <= F.reach
			and not b.round
			and b.sx >= F.minWidth
			and b.sz >= F.minWidth
			and b.top - b.base >= F.minHeight
			and b.top - b.base <= F.maxHeight
		then
			table.insert(list, b)
		end
	end
	table.sort(list, function(a, b)
		return a.top > b.top or (a.top == b.top and a.id < b.id)
	end)
	local best, bestScore = nil, math.huge
	for i = 1, math.min(#list, F.tries) do
		for side = 1, 4 do
			local st = stageFor(Config, world, list[i], x, z, side)
			local sum = 0
			for _, dy in st.lift do
				sum += dy
			end
			local score = sum + (st.blocked or 0) * 40 + (side - 1) * 2 + (i - 1) * 3
			if score < bestScore then
				best, bestScore = st, score
			end
		end
	end
	return best
end

-- The film for a stage
function IntroFilm.film(Config: any, st: Stage): Film
	local F = Config.Story.opening.film
	local T = st.tower
	local C = v(T.x, T.base, T.z)
	local r, f = st.r, st.f
	local up = v(0, 1, 0)
	local hr = if r[1] ~= 0 then T.sx / 2 else T.sz / 2 -- the tower's half width along r
	local hf = if f[1] ~= 0 then T.sx / 2 else T.sz / 2 -- and along f (toward its street face)
	local H = T.top - T.base
	local h = math.floor(H * 0.55) -- the smash height
	local function P(
		ra: number,
		fa: number,
		y: number
	): V -- a point in the tower's frame (y up from its base)
		return add(add(add(C, mul(r, ra)), mul(f, fa)), mul(up, y))
	end
	local function yawAlong(d: V): number
		return math.atan2(-d[1], -d[3])
	end
	local yR, yL, yS = yawAlong(r), yawAlong(mul(r, -1)), yawAlong(mul(f, -1)) -- facing +r, -r, the street
	-- the cold open's path: down the street (open air: the street runs along r in front of the tower's face),
	-- into the face, up through the tower and out of its roof, then down onto the street
	local S = st.street
	local function S_(ra: number, fa: number, y: number): V
		return add(add(add(S, mul(r, ra)), mul(f, fa)), mul(up, y))
	end
	local entry = P(0, -hf - 0.5, h) -- the street face
	local exit = P(0, 0, H + 0.5) -- the roof
	local land = S_(14, 2, 0)
	local apex = add(P(0, 0, H + 34), mul(f, -(hf * 0.6)))
	local FT = st.far
	local farRoof = v(FT.x, FT.top, FT.z)
	local towerRoof = add(v(T.x, T.top, T.z), mul(f, -(hf - 4)))
	local fakesAt = { S_(-7, 3, 0), S_(0, 1, 0), S_(7, 3, 0) }
	local yawOf = yawAlong

	local shots: { Shot } = {}
	local function shot(t0: number, t1: number, from: V, to: V, at: V, at2: V, shake: number?, ease: string?)
		table.insert(
			shots,
			{ t0 = t0, t1 = t1, from = from, to = to, at = at, at2 = at2, shake = shake, ease = ease }
		)
	end
	-- cold open --------------------------------------------------------------------------------------------
	-- 1 high over the street behind the hero: the city, the tower ahead, a gold streak and the drones below
	shot(0, 3, S_(-300, -4, h + 70), S_(-262, -2, h + 46), S_(-190, 0, h + 8), P(0, -hf, h))
	-- 2 riding with the hero down the street: just behind and above, the tower's face rushing up on the right
	shot(3, 5.2, S_(-152, 9, h + 14), S_(-60, 9, h + 9), S_(-112, 0, h + 9), entry, 0.15, "linear")
	-- 3 across the street, low and wide on the face: KRA-KOOM, the hero goes straight in
	shot(5.2, 7.5, S_(-30, -8, h - 22), S_(-24, -7, h - 15), entry, add(entry, v(0, 3, 0)), 0.9)
	-- 4 up by the roof: it bursts open, the hero rockets out, the drones chase up after it
	shot(
		7.5,
		9.5,
		P(-hr - 26, -(hf + 30), H + 10),
		P(-hr - 22, -(hf + 34), H + 18),
		exit,
		add(exit, v(0, 26, 0)),
		0.7
	)
	-- 5 low on the street: the hero drops out of the sky, THOOM, the dust rolls past; CAPELINE slams in
	shot(9.5, 13, S_(-4, -9, 2.5), S_(0, -7, 2), add(land, v(0, 8, 0)), add(land, v(0, 3.5, 0)), 0.5)
	-- the world --------------------------------------------------------------------------------------------
	-- 6 hunted: a man with a spark runs down the street at the camera, a scanner drone low behind him
	shot(13, 16.5, S_(-30, 2, 4), S_(-25, 2, 3.4), S_(-6, 6, 3), S_(-16, 6, 3))
	-- 7 the drone's view: high behind him, the red scan locks on
	shot(16.5, 19.5, S_(-4, 9, 8), S_(-18, 9, 6.5), S_(-18, 6, 2), S_(-33, 6, 2))
	-- 8 Silas Crane on the tower's roof edge, low against the sky
	shot(
		19.5,
		22.5,
		add(towerRoof, add(mul(f, -13), v(0, 2.5, 0))),
		add(towerRoof, add(mul(f, -9), v(0, 4, 0))),
		add(towerRoof, v(0, 5, 0)),
		add(towerRoof, v(0, 4.8, 0))
	)
	-- 9 his famous heroes land in a row on the street (a dolly along them)
	shot(22.5, 25.5, S_(-14, -13, 5), S_(10, -12, 4.5), S_(-3, 2, 4), S_(3, 2, 4))
	-- 10 close on Radiant: the face cracks to show metal
	shot(
		25.5,
		28.5,
		add(fakesAt[1], add(mul(f, -6), add(mul(r, 1.5), v(0, 5, 0)))),
		add(fakesAt[1], add(mul(f, -4), add(mul(r, 0.6), v(0, 4.8, 0)))),
		add(fakesAt[1], v(0, 4.6, 0)),
		add(fakesAt[1], v(0, 4.7, 0))
	)
	-- 11 the Vigil: Lodestar on the far roof
	local toFar = (function(): V
		local d = v(FT.x - T.x, 0, FT.z - T.z)
		local l = math.max(1, math.sqrt(d[1] ^ 2 + d[3] ^ 2))
		return v(d[1] / l, 0, d[3] / l)
	end)()
	local side = v(-toFar[3], 0, toFar[1])
	local lodestar = add(farRoof, mul(toFar, -(math.min(FT.sx, FT.sz) / 2 - 4)))
	local villain = add(v(T.x, T.top, T.z), mul(toFar, math.min(T.sx, T.sz) / 2 - 4))
	shot(
		28.5,
		31.5,
		add(lodestar, add(mul(toFar, -9), add(mul(side, 3), v(0, 4, 0)))),
		add(lodestar, add(mul(toFar, -6.5), add(mul(side, 1.5), v(0, 4.6, 0)))),
		add(lodestar, v(0, 4.8, 0)),
		add(lodestar, v(0, 5, 0))
	)
	-- 12 the Dread Syndicate across the way, on the tower
	shot(
		31.5,
		34.5,
		add(villain, add(mul(toFar, 9), add(mul(side, -3), v(0, 4, 0)))),
		add(villain, add(mul(toFar, 6.5), add(mul(side, -1.5), v(0, 4.6, 0)))),
		add(villain, v(0, 4.8, 0)),
		add(villain, v(0, 5, 0))
	)
	-- 13 over the crook's shoulder across the gap to Lodestar: Crane's drones rise up between them
	shot(
		34.5,
		37.5,
		add(villain, add(mul(toFar, -5), add(mul(side, 2.5), v(0, 6.5, 0)))),
		add(villain, add(mul(toFar, -6), add(mul(side, 3), v(0, 7.5, 0)))),
		add(villain, add(mul(toFar, 18), v(0, -6, 0))),
		add(lodestar, v(0, 5, 0))
	)
	-- 14 down from the sky to the street, to someone in the crowd: you
	local you = S_(4, 5, 0)
	shot(
		37.5,
		41,
		add(you, add(mul(f, -26), v(0, 46, 0))),
		add(you, add(mul(f, -11), v(0, 7, 0))),
		add(you, v(0, 2, 0)),
		add(you, v(0, 4.2, 0)),
		nil,
		"smooth"
	)
	-- 15 the spark wakes in your chest
	shot(
		41,
		45,
		add(you, add(mul(f, -7), v(0, 4.8, 0))),
		add(you, add(mul(f, -4.5), v(0, 4.6, 0))),
		add(you, v(0, 4.2, 0)),
		add(you, v(0, 4.4, 0)),
		0.3
	)
	for i, dy in st.lift or {} do
		local sh = shots[i]
		if sh then
			sh.from = add(sh.from, v(0, dy, 0))
			sh.to = add(sh.to, v(0, dy, 0))
		end
	end

	-- actors -----------------------------------------------------------------------------------------------
	local tracks: { Track } = {}
	local function track(id: string, kind: string, keys: { Key })
		table.insert(tracks, { id = id, kind = kind, keys = keys })
	end
	local start = S_(-230, 0, h + 16)
	local turn = S_(-40, 0, h + 4)
	local yLand = yawOf(mul(r, -1)) -- landed, facing back up the street (at the camera)
	track("hero", "lodestar", {
		{ t = 0, p = start, yaw = yR, clip = "fly", hide = true },
		{ t = 1.2, p = start, yaw = yR, clip = "fly" },
		{ t = 4.4, p = turn, yaw = yR, clip = "fly" },
		{ t = 5.6, p = entry, yaw = yawOf(f), clip = "fly" },
		{ t = 5.75, p = add(entry, mul(f, 3)), yaw = yawOf(f), clip = "fly", hide = true }, -- inside
		{ t = 8.0, p = exit, yaw = yawOf(f), clip = "fly" },
		{ t = 8.3, p = add(exit, v(0, 8, 0)), yaw = yawOf(f), clip = "fly" },
		{ t = 9.1, p = apex, yaw = yawOf(mul(f, -1)), clip = "fly" },
		{ t = 10.2, p = land, yaw = yLand, clip = "pound" },
		{ t = 13, p = land, yaw = yLand, clip = "hover", hide = true },
	})
	for i, off in { { 26, 5, 4 }, { 36, -6, -2 }, { 46, 2, 7 } } do
		local back, fa, y = off[1], off[2], off[3]
		track("drone" .. i, "drone", {
			{ t = 0, p = add(start, v(0, y, 0)), yaw = yR, hide = true },
			{ t = 1.2, p = add(S_(-230 - back, fa, h + 16), v(0, y, 0)), yaw = yR },
			{ t = 4.4, p = add(S_(-40 - back, fa, h + 4), v(0, y, 0)), yaw = yR },
			{
				t = 5.9,
				p = add(entry, add(mul(f, -(12 + i * 5)), add(mul(r, (i - 2) * 9), v(0, y * 0.5, 0)))),
				yaw = yawOf(f),
			},
			{
				t = 7.6,
				p = add(entry, add(mul(f, -(14 + i * 5)), add(mul(r, (i - 2) * 9), v(0, H - h - 6, 0)))),
				yaw = yawOf(f),
			},
			{
				t = 8.6 + i * 0.12,
				p = add(exit, add(mul(f, -(hf + 10 + i * 4)), add(mul(r, (i - 2) * 8), v(0, 14 + i * 3, 0)))),
				yaw = yawOf(f),
			},
			{ t = 10.4, p = add(land, add(mul(r, (i - 2) * 12), v(0, 26 + i * 4, 0))), yaw = yLand },
			{
				t = 13,
				p = add(land, add(mul(r, (i - 2) * 12), v(0, 30 + i * 4, 0))),
				yaw = yLand,
				hide = true,
			},
		})
	end
	track("runner", "citizen", {
		{ t = 12.9, p = S_(-2, 6, 0), yaw = yL, clip = "sprint", hide = true },
		{ t = 13, p = S_(-2, 6, 0), yaw = yL, clip = "sprint" },
		{ t = 19.5, p = S_(-34, 6, 0), yaw = yL, clip = "sprint", hide = true },
	})
	track("scanner", "drone", {
		{ t = 12.9, p = S_(10, 6, 9), yaw = yL, hide = true },
		{ t = 13, p = S_(10, 6, 9), yaw = yL },
		-- (its own view next: it is the camera, so it does not show)
		{ t = 16.5, p = S_(-4, 6, 8.5), yaw = yL, hide = true },
		{ t = 19.5, p = S_(-22, 6, 8), yaw = yL, hide = true },
	})
	track("crane", "crane", {
		{ t = 19.4, p = towerRoof, yaw = yS, clip = "hover", hide = true },
		{ t = 19.5, p = towerRoof, yaw = yS, clip = "hover" },
		{ t = 22.5, p = towerRoof, yaw = yS, clip = "hover", hide = true },
	})
	for i, kind in { "Radiant", "Bulwark", "Skylance" } do
		local at = fakesAt[i]
		track(kind, "fake", {
			{ t = 22.4, p = add(at, v(0, 40, 0)), yaw = yS, clip = "fly", hide = true },
			{ t = 22.5 + i * 0.25, p = add(at, v(0, 40, 0)), yaw = yS, clip = "fly" },
			{ t = 23.3 + i * 0.25, p = at, yaw = yS, clip = "pound" },
			{ t = 24 + i * 0.25, p = at, yaw = yS, clip = "hover" },
			{ t = 28.5, p = at, yaw = yS, clip = "hover", hide = true },
		})
	end
	local yFar, yBack = yawOf(mul(toFar, -1)), yawOf(toFar)
	track("vigil", "lodestar", {
		{ t = 28.4, p = lodestar, yaw = yFar, clip = "hover", hide = true },
		{ t = 28.5, p = lodestar, yaw = yFar, clip = "hover" },
		{ t = 37.5, p = lodestar, yaw = yFar, clip = "hover", hide = true },
	})
	track("syndicate", "villain", {
		{ t = 31.4, p = villain, yaw = yBack, clip = "hover", hide = true },
		{ t = 31.5, p = villain, yaw = yBack, clip = "hover" },
		{ t = 37.5, p = villain, yaw = yBack, clip = "hover", hide = true },
	})
	for i = 1, 4 do
		-- rising right in front of the crook, between the two roofs
		local s0 =
			add(add(villain, add(mul(toFar, 12 + i * 4), mul(side, (i - 2.5) * 5))), v(0, -14 - i * 3, 0))
		track("swarm" .. i, "drone", {
			{ t = 34.4, p = s0, yaw = yBack, hide = true },
			{ t = 34.5, p = s0, yaw = yBack },
			{ t = 37.5, p = add(s0, v(0, 36 + i * 2, 0)), yaw = yBack, hide = true },
		})
	end
	track("you", "you", {
		{ t = 37.4, p = you, yaw = yS, clip = "hover", hide = true },
		{ t = 37.5, p = you, yaw = yS, clip = "hover" },
		{ t = 45, p = you, yaw = yS, clip = "hover" },
	})
	-- the crowd round you (citizens walking by, behind and beside you, never between you and the camera)
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * math.pi
		local p0 = add(you, add(mul(r, math.cos(a) * 8), mul(f, math.sin(a) * 6 + 1)))
		local dir = if i % 2 == 0 then 1 else -1
		local p1 = add(p0, mul(r, dir * 9))
		local yw = if dir > 0 then yR else yL
		track("crowd" .. i, "citizen", {
			{ t = 37.4, p = p0, yaw = yw, clip = "walk", hide = true },
			{ t = 37.5, p = p0, yaw = yw, clip = "walk" },
			{ t = 45, p = p1, yaw = yw, clip = "walk" },
		})
	end

	-- events -----------------------------------------------------------------------------------------------
	local events: { Event } = {
		{ t = 0, kind = "music", text = "boss" },
		{ t = 1.3, kind = "whoosh", actor = "hero" },
		{ t = 3.5, kind = "shot", actor = "drone1", q = S_(-96, 3, h + 6) },
		{ t = 4.0, kind = "shot", actor = "drone2", q = S_(-70, -2, h + 2) },
		{ t = 4.5, kind = "shot", actor = "drone3", q = S_(-44, 4, h + 7) },
		{ t = 5.0, kind = "shot", actor = "drone1", q = add(entry, v(4, 3, 0)) },
		{ t = 5.6, kind = "smash", p = entry, q = f },
		{ t = 6.4, kind = "shot", actor = "drone2", q = add(entry, v(-3, -2, 0)) },
		{ t = 6.9, kind = "shot", actor = "drone3", q = add(entry, v(2, 4, 0)) },
		{ t = 8.0, kind = "smash", p = exit, q = up, text = "glass" },
		{ t = 8.85, kind = "boom", actor = "drone3" },
		{ t = 10.2, kind = "land", p = land },
		{ t = 11.0, kind = "title" },
		{ t = 13, kind = "music", text = "patrolNight" },
		{ t = 15.2, kind = "scan", actor = "scanner", q = S_(-12, 6, 0) },
		{ t = 26.3, kind = "crack", actor = "Radiant" },
		{ t = 34.8, kind = "rise" },
		{ t = 42.2, kind = "spark", actor = "you" },
		{ t = 44.4, kind = "flash" },
	}
	local words: { Event } = {
		{ t = 5.65, kind = "word", text = "KRA-KOOM!", p = entry },
		{ t = 8.05, kind = "word", text = "SKRASSH!", p = exit },
		{ t = 8.8, kind = "word", text = "BLAM!", actor = "drone3" },
		{ t = 10.25, kind = "word", text = "THOOM!", p = land },
		{ t = 17.2, kind = "word", text = "SPARK DETECTED", actor = "runner" },
		{ t = 26.4, kind = "word", text = "KRZZT!", actor = "Radiant" },
		{ t = 42.3, kind = "word", text = "ZAP!", actor = "you" },
	}
	-- the captions: the lore doc's words (from = "lore") and the game's own lines (from = "game"); the rest draft
	local captions: { Caption } = {
		{ t0 = 13.3, t1 = 16.3, text = "Powered people are being hunted.", from = "lore" },
		{
			t0 = 16.6,
			t1 = 19.4,
			text = "Crane's machines scan for sparks, so nobody can hide.",
			from = "lore",
		},
		{ t0 = 19.7, t1 = 22.4, text = "Silas Crane. In public, the city's savior.", from = "lore" },
		{ t0 = 22.8, t1 = 25.4, text = "His famous heroes keep Brightharbor safe...", draft = true },
		{ t0 = 25.7, t1 = 28.4, text = "...but some of them are robots.", draft = true },
		{
			t0 = 28.7,
			t1 = 31.4,
			text = "THE VIGIL: hunted, underground heroes who protect the city.",
			from = "lore",
		},
		{
			t0 = 31.7,
			t1 = 34.4,
			text = "THE DREAD SYNDICATE: they want the city for themselves.",
			from = "lore",
		},
		{ t0 = 34.7, t1 = 37.4, text = "Crane's robots hunt both sides.", from = "lore" },
		{ t0 = 37.7, t1 = 41, text = "Today the Spark woke in you.", from = "game" },
		{ t0 = 41.2, t1 = 44.6, text = "Nobody knows yet. So... who are you?", from = "game" },
	}
	return {
		seconds = F.seconds,
		coldOpen = 13,
		shots = shots,
		tracks = tracks,
		events = events,
		captions = captions,
		words = words,
	}
end

local function ease(x: number, how: string?): number
	if how == "linear" then
		return x
	end
	return x * x * (3 - 2 * x)
end

-- The shot at t
function IntroFilm.shotAt(film: Film, t: number): (Shot?, number)
	for _, s in film.shots do
		if t >= s.t0 and t < s.t1 then
			return s, (t - s.t0) / (s.t1 - s.t0)
		end
	end
	local last = film.shots[#film.shots]
	return last, 1
end

-- The camera at t: position and look point (x, y, z each); shake adds a decaying wobble from the shot's start
function IntroFilm.camera(film: Film, t: number): (V, V)
	local s, k = IntroFilm.shotAt(film, t)
	if not s then
		return v(0, 50, 0), v(0, 0, 0)
	end
	local e = ease(math.clamp(k, 0, 1), s.ease)
	local pos = v(lerp(s.from[1], s.to[1], e), lerp(s.from[2], s.to[2], e), lerp(s.from[3], s.to[3], e))
	local look = v(lerp(s.at[1], s.at2[1], e), lerp(s.at[2], s.at2[2], e), lerp(s.at[3], s.at2[3], e))
	if s.shake and s.shake > 0 then
		local into = (t - s.t0)
		local amp = s.shake * math.exp(-into * 2.2)
		pos[1] += math.sin(t * 41) * amp
		pos[2] += math.sin(t * 37 + 1.3) * amp
	end
	return pos, look
end

-- An actor at t: position, yaw, clip, and whether it shows
function IntroFilm.at(tr: Track, t: number): (V, number, string?, boolean)
	local keys = tr.keys
	if t <= keys[1].t then
		local k = keys[1]
		return k.p, k.yaw or 0, k.clip, not k.hide and t >= k.t
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t >= a.t and t < b.t then
			local k = (t - a.t) / math.max(1e-3, b.t - a.t)
			local p = v(lerp(a.p[1], b.p[1], k), lerp(a.p[2], b.p[2], k), lerp(a.p[3], b.p[3], k))
			return p, a.yaw or 0, a.clip, not a.hide
		end
	end
	local k = keys[#keys]
	return k.p, k.yaw or 0, k.clip, not k.hide
end

return IntroFilm
