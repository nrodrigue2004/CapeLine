--!strict
-- LifePlan: where the living world's ambient life goes and how it moves (2026-11-19, nate's playtest: "World needs
-- to feel way more alive"; Config.Life). Pure, so Lune checks it; Fx.CityLife draws it on each device.
-- * lanes(boxes, skips): the city's driving lines from the lane dashes down the middle of Downtown's and Uptown's
--   streets (CityLayout: kind "mark", colour "mark"), merged across the crossings: { ax, c, a0, a1, y } (ax "x": the
--   line runs along x at z = c). The tram lines (skips) are left out. The server sends them in WorldInfo.
-- * crossings(lanes): each line's crossing points (where another line crosses it), sorted.
-- * green(cfg, t, x, z): which axis has the green at a crossing now (each crossing on its own beat).
-- * carSpeed(cfg, v, dt, stopIn, aheadIn): a car's next speed: up to cruise, braking to stop short of a red light, a
--   car ahead or a hero in the road.
-- * corners(cfg, lanes, crossings): the sidewalk corners pigeons may land on (a hash picks which have a flock).
-- * manholes(cfg, lanes, crossings): steam vents, one between some crossings.
-- * roofFlags(Config, buildings): flag poles on some flat Downtown, Uptown, Docks and Old Town roofs.
-- * districtAt(Config, x, z): the district a spot is in ("Outskirts" outside them all).
-- * wave(i, n, t, wind): a flag segment's turn (radians, chained from the pole) for a cloth of n segments.
-- * react(cfg, dist, speed, airborne, sinceBang, key): a citizen's reaction to the nearest hero: "point" (one
--   flying or racing by), "photo" (one standing near), "cheer" (just after a big hit), or nil.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local LifePlan = {}

export type Lane = { ax: string, c: number, a0: number, a1: number, y: number }

local function roll(seed: number, x: number, z: number, salt: number): number
	return (Rng.hash(seed, math.floor(x * 4), math.floor(z * 4), salt) % 10007) / 10007
end
LifePlan.roll = roll

function LifePlan.lanes(boxes: { any }, skips: { { ax: string, c: number } }?): { Lane }
	-- dashes grouped by their line: "x:<z>" for dashes along x, "z:<x>" along z
	local groups: { [string]: { ax: string, c: number, y: number, spans: { { number } } } } = {}
	for _, b in boxes do
		if b.kind == "mark" and b.color == "mark" then
			local alongX = b.sx >= b.sz
			local c = if alongX then b.cz else b.cx
			local a = if alongX then b.cx else b.cz
			local len = if alongX then b.sx else b.sz
			local key = (if alongX then "x:" else "z:") .. tostring(math.floor(c * 10 + 0.5))
			local g = groups[key]
			if not g then
				g = { ax = if alongX then "x" else "z", c = c, y = b.cy + (b.sy or 0) / 2, spans = {} }
				groups[key] = g
			end
			table.insert(g.spans, { a - len / 2, a + len / 2 })
		end
	end
	local out: { Lane } = {}
	for _, g in groups do
		local skip = false
		local list: { { ax: string, c: number } } = skips or {}
		for _, s in list do
			if s.ax == g.ax and math.abs(s.c - g.c) < 4 then
				skip = true
			end
		end
		if not skip then
			table.sort(g.spans, function(p, q)
				return p[1] < q[1]
			end)
			-- merge dashes into runs (a crossing is a gap of about a street's width)
			local a0, a1 = g.spans[1][1], g.spans[1][2]
			for k = 2, #g.spans + 1 do
				local s = g.spans[k]
				if s and s[1] - a1 <= 44 then
					a1 = math.max(a1, s[2])
				else
					if a1 - a0 >= 60 then
						table.insert(out, { ax = g.ax, c = g.c, a0 = a0, a1 = a1, y = g.y })
					end
					if s then
						a0, a1 = s[1], s[2]
					end
				end
			end
		end
	end
	table.sort(out, function(p, q)
		if p.ax ~= q.ax then
			return p.ax < q.ax
		end
		if p.c ~= q.c then
			return p.c < q.c
		end
		return p.a0 < q.a0
	end)
	return out
end

-- Each lane's crossing points along it (sorted): where a line the other way crosses within reach of both
function LifePlan.crossings(lanes: { Lane }): { { number } }
	local out = {}
	for i, l in lanes do
		local list = {}
		for _, m in lanes do
			if
				m.ax ~= l.ax
				and m.c >= l.a0 - 24
				and m.c <= l.a1 + 24
				and l.c >= m.a0 - 24
				and l.c <= m.a1 + 24
			then
				table.insert(list, m.c)
			end
		end
		table.sort(list)
		out[i] = list
	end
	return out
end

-- Which way the light at a crossing is green ("x" or "z"), each crossing on its own beat
function LifePlan.green(cfg: any, t: number, x: number, z: number): string
	local beat = roll(cfg.seed or 1, x, z, 7) * cfg.cycle
	local phase = ((t + beat) % cfg.cycle) / cfg.cycle
	return if phase < 0.5 then "x" else "z"
end

-- A car's next speed: cruise, or brake to stop `stopIn` studs ahead (a red light, a car, a hero; nil: clear)
function LifePlan.carSpeed(cfg: any, v: number, dt: number, stopIn: number?): number
	local want = cfg.cruise
	if stopIn then
		-- the speed that still stops in the room left, braking hard
		local room = math.max(0, stopIn)
		want = math.min(want, math.sqrt(2 * cfg.brake * room))
		if room < 0.5 then
			want = 0
		end
	end
	if v < want then
		return math.min(want, v + cfg.accel * dt)
	end
	return math.max(want, v - cfg.brake * dt)
end

-- The sidewalk corners round each crossing (pigeons): { x, z, y }
function LifePlan.corners(cfg: any, lanes: { Lane }, crossings: { { number } }, half: number): { { number } }
	local out = {}
	local seen: { [string]: boolean } = {}
	for i, l in lanes do
		if l.ax == "x" then
			for _, xc in crossings[i] do
				for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
					local x, z = xc + d[1] * half, l.c + d[2] * half
					local key = math.floor(x) .. "," .. math.floor(z)
					if not seen[key] and roll(cfg.seed or 1, x, z, cfg.salt) < cfg.chance then
						seen[key] = true
						table.insert(out, { x, z, l.y })
					end
				end
			end
		end
	end
	return out
end

-- Manholes between crossings: { x, z, y }
function LifePlan.manholes(cfg: any, lanes: { Lane }, crossings: { { number } }): { { number } }
	local out = {}
	for i, l in lanes do
		local list = crossings[i]
		for k = 1, #list - 1 do
			local a = (list[k] + list[k + 1]) / 2
			if list[k + 1] - list[k] > 60 and roll(cfg.seed or 1, a, l.c, cfg.salt) < cfg.chance then
				local off = (roll(cfg.seed or 1, l.c, a, cfg.salt + 1) - 0.5) * 30
				local s = a + off
				if l.ax == "x" then
					table.insert(out, { s, l.c, l.y })
				else
					table.insert(out, { l.c, s, l.y })
				end
			end
		end
	end
	return out
end

function LifePlan.districtAt(Config: any, x: number, z: number): string
	for name, d in Config.City.districts do
		if x >= d.minX and x <= d.maxX and z >= d.minZ and z <= d.maxZ then
			return name
		end
	end
	return "Outskirts"
end

-- WorldInfo's buildings ({ id, x, z, sx, sz, base, top, round }) -> roof flags { id, x, y, z, district }
function LifePlan.roofFlags(Config: any, buildings: { any }): { any }
	local F = Config.Life.flagRoofs
	local out = {}
	for _, b in buildings do
		local id, x, z, sx, sz, base, top, round = b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8]
		if
			round ~= 1
			and top - base <= F.maxHeight
			and top - base >= 20
			and sx >= 16
			and sz >= 16
			and roll(Config.Life.seed, x, z, F.salt) < F.chance
		then
			-- a front corner of the roof, a little in from its edge (clear of the cornice)
			local k = if roll(Config.Life.seed, z, x, F.salt) < 0.5 then -1 else 1
			table.insert(out, {
				id = id,
				x = x + k * (sx / 2 - 2.5),
				y = top,
				z = z - (sz / 2 - 2.5),
				district = LifePlan.districtAt(Config, x, z),
			})
		end
	end
	return out
end

-- A flag segment's turn about the one before it: a travelling wave that grows toward the fly end
function LifePlan.wave(i: number, n: number, t: number, wind: number): number
	local f = i / n
	return math.sin(t * 4.2 * wind - i * 1.1) * (0.12 + 0.3 * f) + math.sin(t * 7.3 - i * 1.9) * 0.05 * f
end

-- How a citizen reacts to the nearest hero (dist studs away, moving at speed, in the air or not), sinceBang
-- seconds after the last big hit near it (math.huge: none). `key` spreads who does what.
function LifePlan.react(
	cfg: any,
	dist: number,
	speed: number,
	airborne: boolean,
	sinceBang: number,
	key: number
): string?
	if sinceBang <= cfg.cheerFor and dist <= cfg.cheer then
		return "cheer"
	end
	local who = (key * 0.6180339) % 1
	if (airborne or speed > 40) and dist <= cfg.point then
		return if who < 0.6 then "point" else (if who < 0.85 then "photo" else nil)
	end
	if dist <= cfg.photo and speed < 8 then
		return if who < 0.45 then "photo" else (if who < 0.7 then "point" else nil)
	end
	return nil
end

return LifePlan
