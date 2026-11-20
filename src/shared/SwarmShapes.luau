--!strict
-- SwarmShapes: where each of the Swarm Queen's drones flies (bosses-3, nate 2026-11-20: "thousands of Crane drones
-- (visually; one networked body plus client-side swarm instancing within phone budgets) that form fists, walls and a
-- giant body"). The server runs one body (BossSim: the hive core and its three formation nodes); every device draws the
-- swarm from these shapes (Fx.SwarmFx), so nothing here is ever sent or trusted. DRAFT look until nate OKs it.
-- * Each drone belongs to one of the three formations (i % 3): fists (phase 1: the two nodes' drones ball into fists,
--   the third swirls round the hive's root behind it), walls (phase 2: a wall of drones in front of the core), the giant (phase 3: every drone
--   makes a giant body standing on the ground with the core in its chest). A broken formation's drones drop to the
--   ground and crawl (their node is gone); an exposed core drops every drone. They fly back when the formation re-forms.
-- * An attack pulls a formation's drones out to where it lands (a fist punch, the wall sweeping, the rain falling) over
--   its warning, then back.
-- * How many drones a device draws: Config.Boss.bosses.SwarmQueen.swarm by preset (parts), plus a particle haze of far
--   specks so it reads as thousands. Offsets are in the boss's frame from its core (x right, y up, -z its front).
-- Pure: no Roblox types, so Lune tests it.

local SwarmShapes = {}

local GOLD = 2.399963229728653 -- the golden angle

-- A repeatable 0..1 number for drone i and a salt
local function hash(i: number, salt: number): number
	local v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
	return v - math.floor(v)
end

-- The drones this device draws: the preset's parts and its haze particles a second
function SwarmShapes.budget(cfg: any, preset: string): (number, number)
	local s = cfg.swarm
	local n = s.drones[preset] or s.drones.low
	local h = s.haze[preset] or s.haze.low
	return n, h
end

-- How many drones the swarm looks like on this preset (parts plus the haze's live specks)
function SwarmShapes.looksLike(cfg: any, preset: string): number
	local n, h = SwarmShapes.budget(cfg, preset)
	return n + h * cfg.swarm.hazeLife
end

-- The form for a phase (Config.Boss forms)
function SwarmShapes.form(cfg: any, phase: number): string
	return cfg.forms[math.clamp(phase, 1, #cfg.forms)]
end

-- The formation a drone belongs to (1, 2 or 3: the Config.Boss objective it forms round)
function SwarmShapes.group(i: number): number
	return (i - 1) % 3 + 1
end

-- A point on a loose orbiting cloud round the core
local function cloud(i: number, n: number, t: number): (number, number, number)
	local u = hash(i, 1)
	local cosT = 1 - 2 * ((i - 0.5) / math.max(n, 1))
	local sinT = math.sqrt(math.max(0, 1 - cosT * cosT))
	local a = i * GOLD + t * 0.35 * (0.6 + u)
	local r = 30 + 16 * u
	return math.cos(a) * sinT * r, cosT * r * 0.75, math.sin(a) * sinT * r
end

-- A ball of drones (a fist) round a centre
local function ball(i: number, cx: number, cy: number, cz: number, r: number, t: number): (number, number, number)
	local u, v, w = hash(i, 2), hash(i, 3), hash(i, 4)
	local a = u * math.pi * 2 + t * 1.6
	local cosT = v * 2 - 1
	local sinT = math.sqrt(1 - cosT * cosT)
	local rr = r * (0.55 + 0.45 * w)
	return cx + math.cos(a) * sinT * rr, cy + cosT * rr, cz + math.sin(a) * sinT * rr
end

-- The giant: legs from the ground to the hips, a torso round the core, arms and a head (groundY: the ground from the
-- core, negative)
local GIANT = {
	-- { share, x0, y0, z0, x1, y1, z1, radius } segments the drones spread along (y from the core)
	{ 0.14, -14, 0, 0, -14, -1, 0, 6 }, -- left leg (y0 is the ground, filled in)
	{ 0.14, 14, 0, 0, 14, -1, 0, 6 }, -- right leg
	{ 0.3, 0, -14, 0, 0, 18, 0, 16 }, -- the torso round the core
	{ 0.12, -24, 14, 0, -40, -22, -8, 6 }, -- left arm
	{ 0.12, 24, 14, 0, 40, -22, -8, 6 }, -- right arm
	{ 0.08, -40, -22, -8, -40, -28, -10, 9 }, -- left fist
	{ 0.08, 40, -22, -8, 40, -28, -10, 9 }, -- right fist
	{ 0.02, 0, 30, 0, 0, 40, 0, 7 }, -- the head (the crown is its brow)
}
local function giant(i: number, groundY: number, t: number): (number, number, number)
	local u = hash(i, 5)
	local acc = 0
	local seg = GIANT[#GIANT]
	for _, s in GIANT do
		acc += s[1]
		if u <= acc then
			seg = s
			break
		end
	end
	local f = hash(i, 6)
	local y0 = if seg[3] == 0 and seg[6] == -1 then groundY + 2 else seg[3]
	local y1 = if seg[6] == -1 then -12 else seg[6]
	local a = hash(i, 7) * math.pi * 2 + t * 0.8
	local rr = seg[8] * math.sqrt(hash(i, 8))
	return seg[2] + (seg[5] - seg[2]) * f + math.cos(a) * rr,
		y0 + (y1 - y0) * f + math.sin(a) * rr * 0.4,
		seg[4] + (seg[7] - seg[4]) * f + math.sin(a) * rr
end

-- A drone whose formation is broken: dropped to the ground round the core, crawling a little
local function fallen(i: number, groundY: number, t: number): (number, number, number)
	local a = i * GOLD + math.sin(t * 0.7 + i) * 0.05
	local r = 22 + 40 * hash(i, 9)
	return math.cos(a) * r, groundY + 1 + hash(i, 10) * 2, math.sin(a) * r
end

export type Strike = {
	group: number, -- the formation that strikes (0: every drone)
	f: number, -- 0 at the warning's start .. 1 at the hit
	points: { { number } }, -- where it lands, in the core's frame { x, y, z }
}

-- Where drone i of n sits now (offsets from the core in its frame). opts: form, t (seconds), groundY (the ground from
-- the core), alive ({ boolean } per formation), exposed (every drone down), strike (an attack pulling a formation out)
function SwarmShapes.target(
	i: number,
	n: number,
	form: string,
	t: number,
	groundY: number,
	alive: { boolean },
	exposed: boolean,
	strike: Strike?
): (number, number, number)
	local g = SwarmShapes.group(i)
	if exposed or alive[g] == false then
		return fallen(i, groundY, t)
	end
	local x, y, z
	if form == "giant" then
		x, y, z = giant(i, groundY, t)
	elseif form == "wall" and g ~= 3 then
		-- a wall of drones in front of the core: 90 wide, 56 high, gently rippling
		local cols = math.max(1, math.floor(math.sqrt(n * 1.6)))
		local k = (i - 1) // 3
		local c, r = k % cols, k // cols
		local rows = math.max(1, math.ceil(n / 3 * 2 / cols))
		x = -45 + 90 * (c + 0.5) / cols
		y = -28 + 56 * (r + 0.5) / rows
		z = -30 + math.sin(t * 2 + c * 0.6) * 1.5
	elseif form == "fists" and g ~= 3 then
		local s = if g == 1 then -1 else 1
		-- a fist round its node, its knuckles on the ground (Config.Boss: the nodes are 26 below the core)
		x, y, z = ball(i, s * 34, -18, -12, 11, t)
	elseif g == 3 then
		-- the third formation swirls round the hive's root behind it, a twister up to the core
		local a = i * GOLD + t * 0.9
		local h = hash(i, 12)
		local r = 6 + 14 * h
		x, y, z = math.cos(a) * r, -26 + h * 40, 34 + math.sin(a) * r
	else
		x, y, z = cloud(i, n, t)
	end
	if strike and (strike.group == 0 or strike.group == g) and #strike.points > 0 then
		local p = strike.points[(i - 1) % #strike.points + 1]
		local f = strike.f * strike.f -- they gather, then rush in at the end
		local spread = 6 * (1 - f) + 3
		local jx, jz = (hash(i, 13) - 0.5) * spread, (hash(i, 14) - 0.5) * spread
		x = x + (p[1] + jx - x) * f
		y = y + (p[2] - y) * f
		z = z + (p[3] + jz - z) * f
	end
	return x, y, z
end

-- Which formation an attack sends (SwarmFx: a fist punch the fists' drones, the wall the wall's, the rain and the
-- giant's stomp every drone); nil: the attack moves no drones
function SwarmShapes.strikeGroup(attackId: string, i: number?): number?
	if attackId == "DroneFist" then
		return i or 1
	elseif attackId == "DroneWall" then
		return 1
	elseif attackId == "DroneRain" or attackId == "Stingers" or attackId == "HiveCrush" then
		return 0
	end
	return nil
end

return SwarmShapes
