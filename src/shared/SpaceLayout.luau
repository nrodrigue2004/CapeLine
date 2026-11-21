--!strict
-- SpaceLayout (2026-11-21, Everything Left 736; spec "Fly-in planet travel"): the orbit zone and the worlds as
-- data. Where the Orbit Gate, the station and every approach ring are, which zone a point is in, whether a move
-- passed through a ring, where a trip lands, and the scenery of the orbit, the moon Calder and the alien planet
-- as plain rows ({ shape, p, s, r, c, m, ... }) that SpaceService turns into parts. Pure: Lune tests run it.
-- Config.Space holds every number.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local SpaceLayout = {}

export type Ring = { x: number, y: number, z: number, r: number, nx: number, ny: number, nz: number }
export type Row = {
	shape: string, -- Block, Ball, Cylinder, Wedge
	p: { number },
	s: { number },
	r: { number }?, -- degrees x, y, z
	c: { number },
	m: string, -- Enum.Material name
	t: number?, -- transparency
	glow: boolean?, -- Neon
	collide: boolean?,
	far: boolean?, -- seen from far off (the server keeps it streamed: Persistent)
	tag: string?, -- what it is (labels, tests)
}

local function u01(...: number): number
	return Rng.hash(...) / 4294967296
end

local function unit(x: number, y: number, z: number): (number, number, number)
	local m = math.sqrt(x * x + y * y + z * z)
	if m < 1e-6 then
		return 0, 0, 1
	end
	return x / m, y / m, z / m
end

-- The station deck's centre
function SpaceLayout.orbit(cfg: any): (number, number, number)
	local o = cfg.orbit.at
	return o[1], o[2], o[3]
end

-- The Orbit Gate over the Hero Hall roof's launch pad ({ x, y, z }): facing up, so you fly up into it
function SpaceLayout.gate(cfg: any, pad: { x: number, y: number, z: number }): Ring
	local G = cfg.gate
	return {
		x = pad.x,
		y = math.min(pad.y + G.above, G.maxY),
		z = pad.z,
		r = G.radius,
		nx = 0,
		ny = 1,
		nz = 0,
	}
end

-- World i's approach ring in orbit, facing the station
function SpaceLayout.ring(cfg: any, i: number): Ring
	local w = cfg.worlds[i]
	local ox, oy, oz = SpaceLayout.orbit(cfg)
	local o = w.ring.offset
	local nx, ny, nz = unit(-o[1], -o[2], -o[3])
	return { x = ox + o[1], y = oy + o[2], z = oz + o[3], r = w.ring.radius, nx = nx, ny = ny, nz = nz }
end

-- World i's ground centre (worlds with a zone)
function SpaceLayout.ground(cfg: any, i: number): (number, number, number)
	local a = cfg.worlds[i].zone.at
	return a[1], a[2], a[3]
end

-- World i's return ring: hovering over its landing pad, standing upright, facing +z
function SpaceLayout.back(cfg: any, i: number): Ring
	local x, y, z = SpaceLayout.ground(cfg, i)
	return { x = x, y = y + 70, z = z + 40, r = 30, nx = 0, ny = 0, nz = 1 }
end

-- Which zone (x, y, z) is in: "orbit", a world's index, or nil (the city and everywhere else)
function SpaceLayout.zoneAt(cfg: any, x: number, y: number, z: number): (string | number)?
	local ox, _, oz = SpaceLayout.orbit(cfg)
	if y > cfg.orbit.floor and (x - ox) ^ 2 + (z - oz) ^ 2 <= (cfg.orbit.edge + 600) ^ 2 then
		return "orbit"
	end
	for i, w in cfg.worlds do
		if w.zone then
			local a = w.zone.at
			local h = w.zone.half + 300
			if math.abs(x - a[1]) <= h and math.abs(z - a[3]) <= h and y < a[2] + 3000 and y > a[2] - 600 then
				return i
			end
		end
	end
	return nil
end

-- Did a move from a to b pass through the ring (its disc), or end inside its hoop?
function SpaceLayout.crossed(ring: Ring, a: { number }, b: { number }): boolean
	local function side(p: { number }): number
		return (p[1] - ring.x) * ring.nx + (p[2] - ring.y) * ring.ny + (p[3] - ring.z) * ring.nz
	end
	local da, db = side(a), side(b)
	local hit: { number }
	if da * db < 0 then
		local f = da / (da - db)
		hit = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
	elseif math.abs(db) < 3 then
		hit = b
	else
		return false
	end
	local dx, dy, dz = hit[1] - ring.x, hit[2] - ring.y, hit[3] - ring.z
	return dx * dx + dy * dy + dz * dz <= ring.r * ring.r
end

-- The server's check: is p close enough to the ring for a trip (lag slack)?
function SpaceLayout.near(ring: Ring, p: { number }, slack: number): boolean
	local dx, dy, dz = p[1] - ring.x, p[2] - ring.y, p[3] - ring.z
	return dx * dx + dy * dy + dz * dz <= (ring.r + slack) ^ 2
end

-- Can a hero of `level` go to destination `dest` (0 the orbit, else a world)? Returns ok, or false and why
function SpaceLayout.canGo(cfg: any, dest: number, level: number): (boolean, string?)
	if dest == 0 then
		if level < cfg.gate.level then
			return false, "level"
		end
		return true, nil
	end
	local w = cfg.worlds[dest]
	if not w then
		return false, "none"
	end
	if w.locked then
		return false, "locked"
	end
	if level < (w.level or 1) then
		return false, "level"
	end
	return true, nil
end

-- Where a trip to `dest` lands (still flying): the orbit's deck edge, a world's drop point, or home over the gate.
-- n: the traveller's place in the party (0 the leader), so friends arrive side by side
function SpaceLayout.arrival(cfg: any, dest: number, gate: Ring?, n: number): (number, number, number)
	local side = (n % 2 == 0 and 1 or -1) * math.ceil(n / 2) * 8
	if dest == 0 then
		local ox, oy, oz = SpaceLayout.orbit(cfg)
		return ox + side, oy + 6, oz + cfg.orbit.deck / 2 - 8
	end
	local w = cfg.worlds[dest]
	if w.home then
		local g = gate :: Ring
		return g.x + side, g.y - 60, g.z - 60
	end
	local x, y, z = SpaceLayout.ground(cfg, dest)
	return x + side, y + w.zone.drop, z - 120
end

----------------------------------------------------------------------------------------------- the scenery rows

local function row(list: { Row }, r: Row)
	table.insert(list, r)
end

-- A ring of `n` glowing segments ({ ring }), for the approach rings and the gate
function SpaceLayout.hoop(ring: Ring, color: { number }, n: number, tag: string): { Row }
	local out = {}
	-- two axes across the ring's plane: a = n x up (or x when the ring faces up), b = n x a
	local ax, ay, az = -ring.nz, 0, ring.nx
	if math.abs(ring.ny) > 0.9 then
		ax, ay, az = 1, 0, 0
	end
	ax, ay, az = unit(ax, ay, az)
	local bx, by, bz = ring.ny * az - ring.nz * ay, ring.nz * ax - ring.nx * az, ring.nx * ay - ring.ny * ax
	local seg = 2 * math.pi * ring.r / n * 1.08
	for k = 1, n do
		local a = (k - 0.5) / n * math.pi * 2
		local ca, sa = math.cos(a), math.sin(a)
		local px = ring.x + (ax * ca + bx * sa) * ring.r
		local py = ring.y + (ay * ca + by * sa) * ring.r
		local pz = ring.z + (az * ca + bz * sa) * ring.r
		-- each segment runs along the tangent; the server builds its CFrame from p and `look`
		local tx, ty, tz = -ax * sa + bx * ca, -ay * sa + by * ca, -az * sa + bz * ca
		table.insert(
			out,
			{
				shape = "Block",
				p = { px, py, pz },
				s = { 2.2, 2.2, seg },
				look = { tx, ty, tz },
				up = { ring.nx, ring.ny, ring.nz },
				c = color,
				m = "Neon",
				glow = true,
				far = true,
				tag = tag,
			} :: any
		)
	end
	return out
end

-- A planet in the orbit sky: the ball, land patches poking out of it, a cloud band, for ring worlds a ring
local function planet(list: { Row }, cfg: any, i: number)
	local w = cfg.worlds[i]
	local ox, oy, oz = SpaceLayout.orbit(cfg)
	local S = w.sphere
	local cx, cy, cz = ox + S.offset[1], oy + S.offset[2], oz + S.offset[3]
	local d = math.min(S.radius * 2, 2040)
	row(list, {
		shape = "Ball",
		p = { cx, cy, cz },
		s = { d, d, d },
		c = S.color,
		m = "SmoothPlastic",
		far = true,
		tag = "planet",
	})
	local seed = cfg.scenery.seed + i * 17
	for k = 1, 9 do
		local th, ph = u01(seed, k, 1) * math.pi * 2, math.acos(u01(seed, k, 2) * 2 - 1)
		local nx, ny, nz = math.sin(ph) * math.cos(th), math.cos(ph), math.sin(ph) * math.sin(th)
		local pd = d * (0.32 + 0.2 * u01(seed, k, 3))
		local out = d / 2 - pd / 2 + pd * 0.06
		row(list, {
			shape = "Ball",
			p = { cx + nx * out, cy + ny * out, cz + nz * out },
			s = { pd, pd, pd },
			c = S.land,
			m = "SmoothPlastic",
			far = true,
			tag = "land",
		})
	end
	if not w.locked and w.id ~= "Calder" then
		local cd = math.min(d * 1.03, 2046)
		row(list, {
			shape = "Ball",
			p = { cx, cy, cz },
			s = { cd, cd, cd },
			c = { 255, 255, 255 },
			m = "SmoothPlastic",
			t = 0.78,
			far = true,
			tag = "air",
		})
	end
	if w.id == "Thalyx" then
		-- a thin ring round the alien planet, tilted
		row(list, {
			shape = "Cylinder",
			p = { cx, cy, cz },
			s = { 2, math.min(d * 1.9, 2040), math.min(d * 1.9, 2040) },
			r = { 0, 0, 90 - 18 },
			c = { 200, 170, 255 },
			m = "Glass",
			t = 0.55,
			far = true,
			tag = "planetRing",
		})
	end
end

-- The orbit: the station deck, its rails, mast and ship counters, every planet, every approach ring
function SpaceLayout.orbitRows(cfg: any): { Row }
	local list: { Row } = {}
	local ox, oy, oz = SpaceLayout.orbit(cfg)
	local D = cfg.orbit.deck
	row(list, {
		shape = "Cylinder",
		p = { ox, oy - 1.5, oz },
		s = { 3, D, D },
		r = { 0, 0, 90 },
		c = { 70, 76, 92 },
		m = "DiamondPlate",
		collide = true,
		far = true,
		tag = "deck",
	})
	row(list, {
		shape = "Cylinder",
		p = { ox, oy - 0.05, oz },
		s = { 0.2, D * 0.55, D * 0.55 },
		r = { 0, 0, 90 },
		c = { 90, 200, 255 },
		m = "Neon",
		glow = true,
		t = 0.3,
		far = true,
		tag = "deckLight",
	})
	row(list, {
		shape = "Cylinder",
		p = { ox, oy - 8, oz },
		s = { 12, D * 0.7, D * 0.7 },
		r = { 0, 0, 90 },
		c = { 52, 56, 70 },
		m = "Metal",
		far = true,
		tag = "hull",
	})
	local n = 28
	for k = 1, n do
		local a = k / n * math.pi * 2
		local rx, rz = math.cos(a) * (D / 2 - 1), math.sin(a) * (D / 2 - 1)
		row(list, {
			shape = "Block",
			p = { ox + rx, oy + 1.6, oz + rz },
			s = { 0.6, 3.2, 0.6 },
			c = { 180, 186, 200 },
			m = "Metal",
			collide = true,
			tag = "rail",
		})
		local a2 = (k + 0.5) / n * math.pi * 2
		local seg = 2 * math.pi * (D / 2 - 1) / n + 0.4
		row(list, {
			shape = "Block",
			p = { ox + math.cos(a2) * (D / 2 - 1), oy + 3.2, oz + math.sin(a2) * (D / 2 - 1) },
			s = { 0.5, 0.5, seg },
			r = { 0, -math.deg(a2), 0 },
			c = { 255, 196, 80 },
			m = "Neon",
			glow = true,
			collide = true,
			tag = "rail",
		})
	end
	row(list, {
		shape = "Cylinder",
		p = { ox, oy + 14, oz },
		s = { 28, 3, 3 },
		r = { 0, 0, 90 },
		c = { 160, 166, 180 },
		m = "Metal",
		collide = true,
		tag = "mast",
	})
	row(list, {
		shape = "Ball",
		p = { ox, oy + 29, oz },
		s = { 4, 4, 4 },
		c = { 255, 80, 80 },
		m = "Neon",
		glow = true,
		tag = "mastLight",
	})
	-- a ship counter for each open world, round the deck's far half
	local open = {}
	for i, w in cfg.worlds do
		if not w.locked then
			table.insert(open, i)
		end
	end
	for k, i in open do
		-- round the far (-z) half of the deck, facing in; heroes arrive on the near (+z) edge
		local a = math.rad(225 + 90 * (k - 1) / math.max(#open - 1, 1))
		local px, pz = ox + math.cos(a) * (D / 2 - 7), oz + math.sin(a) * (D / 2 - 7)
		row(list, {
			shape = "Block",
			p = { px, oy + 1.8, pz },
			s = { 5, 3.6, 2.4 },
			c = { 60, 64, 80 },
			m = "Metal",
			collide = true,
			tag = "ship" .. i,
		})
	end
	for i in cfg.worlds do
		planet(list, cfg, i)
		local color = if cfg.worlds[i].locked then { 255, 70, 70 } else { 120, 220, 255 }
		for _, r in SpaceLayout.hoop(SpaceLayout.ring(cfg, i), color, 24, "ring" .. i) do
			row(list, r)
		end
	end
	return list
end

local function ground(list: { Row }, cfg: any, i: number, material: string)
	local w = cfg.worlds[i]
	local x, y, z = SpaceLayout.ground(cfg, i)
	local h = w.zone.half
	row(list, {
		shape = "Block",
		p = { x, y - 4, z },
		s = { h * 2, 8, h * 2 },
		c = w.ground,
		m = material,
		collide = true,
		tag = "ground",
	})
	-- invisible walls at the edge (fly out and you meet them), up high
	for _, e in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		row(list, {
			shape = "Block",
			p = { x + e[1] * (h + 2), y + 900, z + e[2] * (h + 2) },
			s = { if e[1] ~= 0 then 4 else h * 2 + 8, 1800, if e[2] ~= 0 then 4 else h * 2 + 8 },
			c = { 0, 0, 0 },
			m = "SmoothPlastic",
			t = 1,
			collide = true,
			tag = "wall",
		})
	end
	-- the landing pad and the return ship's counter under the return ring
	local b = SpaceLayout.back(cfg, i)
	row(list, {
		shape = "Cylinder",
		p = { b.x, y + 0.6, b.z },
		s = { 1.2, 34, 34 },
		r = { 0, 0, 90 },
		c = { 70, 76, 92 },
		m = "DiamondPlate",
		collide = true,
		tag = "pad",
	})
	row(list, {
		shape = "Cylinder",
		p = { b.x, y + 1.25, b.z },
		s = { 0.2, 20, 20 },
		r = { 0, 0, 90 },
		c = { 90, 200, 255 },
		m = "Neon",
		glow = true,
		t = 0.3,
		tag = "padLight",
	})
	row(list, {
		shape = "Block",
		p = { b.x + 14, y + 2.4, b.z },
		s = { 5, 3.6, 2.4 },
		c = { 60, 64, 80 },
		m = "Metal",
		collide = true,
		tag = "ship0",
	})
	for _, r in SpaceLayout.hoop(b, { 120, 220, 255 }, 20, "back" .. i) do
		row(list, r)
	end
	-- home hanging in the sky, far off
	local S = cfg.worlds[1].sphere
	row(list, {
		shape = "Ball",
		p = { x - 1700, y + 1300, z - 1900 },
		s = { 900, 900, 900 },
		c = S.color,
		m = "SmoothPlastic",
		far = true,
		tag = "skyHome",
	})
	row(list, {
		shape = "Ball",
		p = { x - 1700 + 260, y + 1300 + 200, z - 1900 + 300 },
		s = { 420, 420, 420 },
		c = S.land,
		m = "SmoothPlastic",
		far = true,
		tag = "skyHome",
	})
end

-- The moon Calder: grey regolith, craters with raised rims, boulders, a crashed probe (a landmark to find)
function SpaceLayout.calderRows(cfg: any, i: number): { Row }
	local list: { Row } = {}
	local x0, y0, z0 = SpaceLayout.ground(cfg, i)
	local h = cfg.worlds[i].zone.half
	local K = cfg.scenery.Calder
	local seed = cfg.scenery.seed + 101
	ground(list, cfg, i, "Slate")
	local function spot(k: number, salt: number, margin: number): (number, number)
		return x0 + (u01(seed, k, salt) * 2 - 1) * (h - margin),
			z0 + (u01(seed, k, salt + 1) * 2 - 1) * (h - margin)
	end
	for k = 1, K.craters do
		local cx, cz = spot(k, 10, 60)
		if (cx - x0) ^ 2 + (cz - (z0 + 40)) ^ 2 > 90 ^ 2 then
			local r = 18 + u01(seed, k, 12) * 46
			row(list, {
				shape = "Cylinder",
				p = { cx, y0 + 1.2, cz },
				s = { 2.4, r * 2 + 10, r * 2 + 10 },
				r = { 0, 0, 90 },
				c = { 176, 176, 184 },
				m = "Slate",
				collide = true,
				tag = "rim",
			})
			row(list, {
				shape = "Cylinder",
				p = { cx, y0 + 1.5, cz },
				s = { 2.4, r * 2, r * 2 },
				r = { 0, 0, 90 },
				c = { 96, 96, 106 },
				m = "Basalt",
				collide = true,
				tag = "crater",
			})
		end
	end
	for k = 1, K.rocks do
		local rx, rz = spot(k, 20, 20)
		local sz = 3 + u01(seed, k, 22) ^ 2 * 16
		row(list, {
			shape = if k % 3 == 0 then "Ball" else "Block",
			p = { rx, y0 + sz * 0.3, rz },
			s = { sz * 1.3, sz, sz * 1.1 },
			r = { u01(seed, k, 23) * 40, u01(seed, k, 24) * 360, u01(seed, k, 25) * 40 },
			c = { 128, 128, 138 },
			m = "Basalt",
			collide = true,
			tag = "rock",
		})
	end
	if K.probe then
		local px, pz = x0 + h * 0.45, z0 - h * 0.35
		row(list, {
			shape = "Block",
			p = { px, y0 + 4, pz },
			s = { 10, 8, 14 },
			r = { 12, 30, -8 },
			c = { 220, 200, 120 },
			m = "Foil",
			collide = true,
			tag = "probe",
		})
		row(list, {
			shape = "Cylinder",
			p = { px + 4, y0 + 11, pz + 3 },
			s = { 1, 14, 14 },
			r = { 0, 30, 60 },
			c = { 230, 232, 240 },
			m = "Metal",
			collide = true,
			tag = "probe",
		})
		for s = -1, 1, 2 do
			row(list, {
				shape = "Block",
				p = { px + s * 13, y0 + 3, pz - 2 },
				s = { 14, 0.4, 7 },
				r = { 0, 30, s * 14 },
				c = { 40, 70, 160 },
				m = "Glass",
				collide = true,
				tag = "probe",
			})
		end
		row(list, {
			shape = "Ball",
			p = { px, y0 + 10, pz },
			s = { 2.4, 2.4, 2.4 },
			c = { 255, 90, 60 },
			m = "Neon",
			glow = true,
			tag = "probeLight",
		})
	end
	return list
end

-- The alien planet: purple moss, crystal spires, giant glowing bulb plants, floating crystal rocks, glowing pools,
-- two suns
function SpaceLayout.thalyxRows(cfg: any, i: number): { Row }
	local list: { Row } = {}
	local x0, y0, z0 = SpaceLayout.ground(cfg, i)
	local h = cfg.worlds[i].zone.half
	local K = cfg.scenery.Thalyx
	local seed = cfg.scenery.seed + 202
	ground(list, cfg, i, "Grass")
	local crystal = { { 110, 240, 255 }, { 255, 110, 220 }, { 170, 130, 255 } }
	local function spot(k: number, salt: number, margin: number): (number, number)
		return x0 + (u01(seed, k, salt) * 2 - 1) * (h - margin),
			z0 + (u01(seed, k, salt + 1) * 2 - 1) * (h - margin)
	end
	local function clear(px: number, pz: number): boolean
		return (px - x0) ^ 2 + (pz - (z0 + 40)) ^ 2 > 80 ^ 2
			and (px - x0) ^ 2 + (pz - (z0 - 120)) ^ 2 > 60 ^ 2
	end
	for k = 1, K.spires do
		local sx, sz = spot(k, 10, 40)
		if clear(sx, sz) then
			local c = crystal[k % 3 + 1]
			local tall = 30 + u01(seed, k, 12) ^ 1.5 * 110
			for j = 0, 2 do
				local th = tall * (1 - j * 0.3)
				local w = th * 0.16
				local lean = (u01(seed, k, 13 + j) * 2 - 1) * 18
				local ox, oz = (u01(seed, k, 16 + j) * 2 - 1) * w, (u01(seed, k, 19 + j) * 2 - 1) * w
				row(list, {
					shape = "Block",
					p = { sx + ox, y0 + th / 2 - 2, sz + oz },
					s = { w, th, w },
					r = { lean, u01(seed, k, 22 + j) * 90, -lean * 0.6 },
					c = c,
					m = "Glass",
					t = 0.15,
					collide = true,
					tag = "spire",
				})
			end
			row(list, {
				shape = "Block",
				p = { sx, y0 + tall * 0.35, sz },
				s = { tall * 0.05, tall * 0.7, tall * 0.05 },
				c = c,
				m = "Neon",
				glow = true,
				tag = "spireCore",
			})
		end
	end
	for k = 1, K.plants do
		local px, pz = spot(k, 30, 30)
		if clear(px, pz) then
			local tall = 14 + u01(seed, k, 32) * 46
			local bulb = 8 + u01(seed, k, 33) * 16
			row(list, {
				shape = "Cylinder",
				p = { px, y0 + tall / 2, pz },
				s = { tall, 2.2 + tall * 0.05, 2.2 + tall * 0.05 },
				r = { 0, 0, 90 },
				c = { 40, 150, 130 },
				m = "LeafyGrass",
				collide = true,
				tag = "stem",
			})
			row(list, {
				shape = "Ball",
				p = { px, y0 + tall + bulb * 0.35, pz },
				s = { bulb, bulb * 0.75, bulb },
				c = if k % 2 == 0 then { 255, 120, 220 } else { 120, 255, 210 },
				m = "Neon",
				glow = true,
				t = 0.25,
				collide = true,
				tag = "bulb",
			})
			for f = 1, 3 do
				local a = (f / 3 + u01(seed, k, 34)) * math.pi * 2
				row(list, {
					shape = "Wedge",
					p = { px + math.cos(a) * 3, y0 + 1.5, pz + math.sin(a) * 3 },
					s = { 1, 3, 7 },
					r = { 0, -math.deg(a) + 90, 0 },
					c = { 60, 190, 150 },
					m = "LeafyGrass",
					tag = "leaf",
				})
			end
		end
	end
	for k = 1, K.floaters do
		local fx, fz = spot(k, 40, 80)
		local fy = y0 + 70 + u01(seed, k, 42) * 160
		local sz = 14 + u01(seed, k, 43) * 26
		row(list, {
			shape = "Ball",
			p = { fx, fy, fz },
			s = { sz * 1.4, sz, sz * 1.2 },
			c = { 72, 44, 96 },
			m = "Rock",
			collide = true,
			tag = "floater",
		})
		row(list, {
			shape = "Block",
			p = { fx, fy + sz * 0.6, fz },
			s = { sz * 0.18, sz * 0.9, sz * 0.18 },
			r = { 8, k * 37, -6 },
			c = crystal[k % 3 + 1],
			m = "Glass",
			t = 0.15,
			collide = true,
			tag = "floaterCrystal",
		})
	end
	for k = 1, K.pools do
		local qx, qz = spot(k, 50, 60)
		if clear(qx, qz) then
			local r = 12 + u01(seed, k, 52) * 22
			row(list, {
				shape = "Cylinder",
				p = { qx, y0 + 0.2, qz },
				s = { 0.6, r * 2, r * 2 },
				r = { 0, 0, 90 },
				c = { 90, 255, 230 },
				m = "Neon",
				glow = true,
				t = 0.35,
				tag = "pool",
			})
		end
	end
	-- two suns, far off in the sky
	row(list, {
		shape = "Ball",
		p = { x0 + 1500, y0 + 1500, z0 - 2000 },
		s = { 340, 340, 340 },
		c = { 255, 220, 160 },
		m = "Neon",
		glow = true,
		far = true,
		tag = "sun",
	})
	row(list, {
		shape = "Ball",
		p = { x0 + 2200, y0 + 900, z0 - 1500 },
		s = { 160, 160, 160 },
		c = { 255, 140, 200 },
		m = "Neon",
		glow = true,
		far = true,
		tag = "sun",
	})
	return list
end

-- Every world's scenery rows by world index
function SpaceLayout.worldRows(cfg: any, i: number): { Row }
	local id = cfg.worlds[i].id
	if id == "Calder" then
		return SpaceLayout.calderRows(cfg, i)
	elseif id == "Thalyx" then
		return SpaceLayout.thalyxRows(cfg, i)
	end
	return {}
end

return SpaceLayout
