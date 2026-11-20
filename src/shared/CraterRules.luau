--!strict
-- CraterRules: craters in the ground (fix-destroy, 2026-11-19, nate: "I literally want everything destructible even
-- terrain"). Pure, so Lune checks it; CraterService on the server and GroundFx on every device use it.
-- * The ground under the city is parts (Shared.WorldGen.base: ground, sand, roads; the districts' sidewalks and
--   plazas; the fields), and Roblox Terrain only under water (Shared.DeepLayout: the sand seabed and the rock walls
--   round the ring, the harbour basin and the Trench). So a crater is one of two kinds:
--   "terrain": the voxels themselves are dug out (carve: a bowl `depth` x its radius deep; a voxel under the water's
--   surface becomes Water, one above becomes Air, so a water volume never opens and a Water voxel is never touched),
--   and the server writes the voxels it read back when the crater heals;
--   "part": a part can't be dug, so every device draws the crater over it: the comic ink crater decal, a dark pit
--   disc and a ring of broken rim chunks in the ground's own colour (GroundFx), sinking back as it heals.
-- * The server keeps the list (add, step) so every device shows the same craters; each lives `life` seconds, the
--   last `heal` of them healing (healing(c, now): 0 whole crater .. 1 gone). Caps: perSecond craters a second on
--   the server, perCell live craters in a `cell`-stud square, maxLive in all, and a terrain crater never overlaps
--   another live one (its voxels would be written back over the other's), so the world never turns to swiss cheese.

local CraterRules = {}

export type Crater = {
	id: number,
	x: number,
	y: number,
	z: number,
	r: number,
	ground: string, -- "terrain" or "part"
	born: number,
	deep: number?, -- destroy-all round 3: how many hits dug it (1 .. cfg.deepen.max; nil is 1)
}

export type Book = {
	list: { Crater },
	next: number,
	times: { number },
}

function CraterRules.new(): Book
	return { list = {}, next = 1, times = {} }
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

-- The crater a hit of `dmg` structure damage makes (0: too light to crater)
function CraterRules.radiusFor(cfg: any, dmg: number): number
	if dmg < cfg.minDmg then
		return 0
	end
	return lerp(cfg.radius[1], cfg.radius[2], (dmg - cfg.minDmg) / (cfg.fullDmg - cfg.minDmg))
end

local function cellOf(cfg: any, x: number, z: number): (number, number)
	return math.floor(x / cfg.cell), math.floor(z / cfg.cell)
end

-- May a crater go here now? Returns the reason it may not (nil: it may)
function CraterRules.refuse(
	cfg: any,
	book: Book,
	x: number,
	z: number,
	r: number,
	ground: string,
	now: number
): string?
	for i = #book.times, 1, -1 do
		if now - book.times[i] >= 1 then
			table.remove(book.times, i)
		end
	end
	if #book.times >= cfg.perSecond then
		return "rate"
	end
	if #book.list >= cfg.maxLive then
		return "full"
	end
	local cx, cz = cellOf(cfg, x, z)
	local inCell = 0
	for _, c in book.list do
		local ox, oz = cellOf(cfg, c.x, c.z)
		if ox == cx and oz == cz then
			inCell += 1
		end
		if ground == "terrain" and c.ground == "terrain" then
			local d = math.sqrt((c.x - x) ^ 2 + (c.z - z) ^ 2)
			if d < c.r + r + cfg.voxel * 2 then
				return "overlap"
			end
		end
	end
	if inCell >= cfg.perCell then
		return "cell"
	end
	return nil
end

-- A crater at (x, y, z) from a hit of dmg, or nil (too light, or a cap says no)
function CraterRules.add(
	cfg: any,
	book: Book,
	x: number,
	y: number,
	z: number,
	dmg: number,
	ground: string,
	now: number
): Crater?
	local r = CraterRules.radiusFor(cfg, dmg)
	if r <= 0 or CraterRules.refuse(cfg, book, x, z, r, ground, now) then
		return nil
	end
	local c: Crater = { id = book.next, x = x, y = y, z = z, r = r, ground = ground, born = now }
	book.next += 1
	table.insert(book.list, c)
	table.insert(book.times, now)
	return c
end

-- Repeated heavy hits dig deeper (destroy-all round 3, 2026-11-20): a hit landing within deepen.near x its radius of
-- a live crater's middle deepens that crater one level (to deepen.max) and starts its life again, instead of a new
-- crater beside it. It counts toward the craters-a-second cap. Returns the crater, or nil (none near, or the cap).
function CraterRules.deepen(cfg: any, book: Book, x: number, z: number, now: number): Crater?
	local dp = cfg.deepen
	if not dp then
		return nil
	end
	for i = #book.times, 1, -1 do
		if now - book.times[i] >= 1 then
			table.remove(book.times, i)
		end
	end
	if #book.times >= cfg.perSecond then
		return nil
	end
	for _, c in book.list do
		if (c.x - x) ^ 2 + (c.z - z) ^ 2 <= (c.r * dp.near) ^ 2 then
			c.deep = math.min((c.deep or 1) + 1, dp.max)
			c.born = now
			table.insert(book.times, now)
			return c
		end
	end
	return nil
end

-- A crater's bowl depth in radii: deeper by deepen.add for each level past the first; scale (0..1) fills it back
function CraterRules.depthOf(cfg: any, c: Crater, scale: number?): number
	local dp = cfg.deepen
	local level = if dp then math.clamp(c.deep or 1, 1, dp.max) else 1
	return cfg.depth * (1 + (level - 1) * (if dp then dp.add else 0)) * (scale or 1)
end

-- How much of its bowl a crater still has (1 whole .. 0 filled back), in steps of 1 / deepen.fills while it heals,
-- so the server writes the voxels a few times, not every frame
function CraterRules.fillScale(cfg: any, c: Crater, now: number): number
	local h = CraterRules.healing(cfg, c, now)
	local n = (cfg.deepen and cfg.deepen.fills) or 1
	return 1 - math.floor(h * n) / n
end

-- 0 while the crater is whole, rising to 1 over its last `heal` seconds
function CraterRules.healing(cfg: any, c: Crater, now: number): number
	local age = now - c.born
	return math.clamp((age - (cfg.life - cfg.heal)) / cfg.heal, 0, 1)
end

-- The craters whose life is over (taken out of the book)
function CraterRules.step(cfg: any, book: Book, now: number): { Crater }
	local out = {}
	for i = #book.list, 1, -1 do
		if now - book.list[i].born >= cfg.life then
			table.insert(out, table.remove(book.list, i) :: Crater)
		end
	end
	return out
end

-- The voxel region a terrain crater reads and writes: its min and max corners on the voxel grid
function CraterRules.region(cfg: any, c: Crater): ({ number }, { number })
	local v = cfg.voxel
	-- the deepest it can be dug (deepen.max), so the voxels read once cover every later dig and the heal
	local d = c.r * CraterRules.depthOf(cfg, { deep = if cfg.deepen then cfg.deepen.max else 1 } :: any)
	local lo = {
		math.floor((c.x - c.r - v) / v) * v,
		math.floor((c.y - d - v) / v) * v,
		math.floor((c.z - c.r - v) / v) * v,
	}
	local hi = {
		math.ceil((c.x + c.r + v) / v) * v,
		math.ceil((c.y + v) / v) * v,
		math.ceil((c.z + c.r + v) / v) * v,
	}
	return lo, hi
end

-- Dig a terrain crater into voxels read from `lo` (ReadVoxels' layout: mats[x][y][z] material names, occ[x][y][z]
-- occupancies, nx x ny x nz). The bowl is an ellipsoid: c.r across, c.r x depth deep, its rim at c.y; a soft edge
-- band thins the voxels round it. A Water voxel never changes; a dug voxel under waterY becomes Water. Edits in
-- place and returns how many voxels changed.
function CraterRules.carve(
	cfg: any,
	c: Crater,
	lo: { number },
	mats: { any },
	occ: { any },
	waterY: number,
	scale: number?
): number
	local v = cfg.voxel
	local depth = c.r * CraterRules.depthOf(cfg, c, scale)
	if depth < v * 0.5 then
		return 0 -- filled back
	end
	local changed = 0
	for i, plane in mats do
		for j, row in plane do
			for k, m in row do
				if m ~= "Air" and m ~= "Water" then
					local x = lo[1] + (i - 0.5) * v
					local y = lo[2] + (j - 0.5) * v
					local z = lo[3] + (k - 0.5) * v
					local dy = y - c.y
					local f =
						math.sqrt(((x - c.x) ^ 2 + (z - c.z) ^ 2) / (c.r * c.r) + (dy * dy) / (depth * depth))
					if dy <= v and f < 1 then
						if y < waterY then
							row[k] = "Water"
							occ[i][j][k] = 1
						else
							row[k] = "Air"
							occ[i][j][k] = 0
						end
						changed += 1
					elseif dy <= v and f < 1 + cfg.soft then
						local keep = (f - 1) / cfg.soft
						if occ[i][j][k] > keep then
							occ[i][j][k] = math.max(keep, 0.05)
							changed += 1
						end
					end
				end
			end
		end
	end
	return changed
end

-- The water line a terrain crater at (x, z) fills to (destroy-all, 2026-11-20): the sea's (seaY) everywhere but the
-- park, whose Terrain lawns sit above the sea line (ParkBuilder): there a dug voxel turns to Water only by one of
-- the park's own waters (within two voxels of its shore, at that water's level) and to Air anywhere else, so a
-- crater in the lawn is a dry bowl and one on the lake's bank lets the lake in. park: Shared.ParkLayout's build
-- (bounds, waters) or nil; inside: ParkLayout.inside (how far inside a water's shore a point is).
function CraterRules.waterLevel(
	cfg: any,
	park: any?,
	seaY: number,
	x: number,
	z: number,
	inside: ((any, number, number) -> number)?
): number
	local b = park and park.bounds
	if not b or not inside or x < b.minX or x > b.maxX or z < b.minZ or z > b.maxZ then
		return seaY
	end
	local best = -math.huge
	for _, w in park.waters or {} do
		if inside(w, x, z) > -cfg.voxel * 2 and w.level > best then
			best = w.level
		end
	end
	return best
end

-- Is (x, z) inside the park (its water splashes are the park's own: Fx.ParkLife)?
function CraterRules.inPark(park: any?, x: number, z: number): boolean
	local b = park and park.bounds
	return b ~= nil and x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ
end

-- A device's rim chunks for a part crater: n chunks round the rim, tilted outward, seeded by the crater's id so
-- every device draws the same ring. { x, y, z, sx, sy, sz, ry, tilt } (degrees)
function CraterRules.rim(c: Crater, n: number): { any }
	local out = {}
	local seed = c.id * 7919
	local function rnd(k: number): number
		local s = math.sin(seed + k * 12.9898) * 43758.5453
		return s - math.floor(s)
	end
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2 + rnd(i) * 0.4
		local size = c.r * (0.28 + rnd(i + 50) * 0.22)
		local rr = c.r * (0.92 + rnd(i + 100) * 0.18)
		table.insert(out, {
			x = c.x + math.cos(a) * rr,
			y = c.y + size * 0.18,
			z = c.z + math.sin(a) * rr,
			sx = size,
			sy = size * 0.45,
			sz = size * (0.6 + rnd(i + 150) * 0.4),
			ry = -math.deg(a),
			tilt = 18 + rnd(i + 200) * 22,
		})
	end
	return out
end

return CraterRules
