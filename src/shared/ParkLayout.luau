--!strict
-- ParkLayout: the city park between Downtown and Uptown as plain data (2026-11-20, nate: "maybe add a large park
-- between uptown and downtown. like central park"; Config.Park). Pure, so Lune checks it and every server and device
-- lays out the very same park. build(Config) gives:
-- * green: the Terrain rectangle inside the wall (cut out of the city's ground plates by WorldGen.base). column(p, x,
--   z) is the ground there: its top, its surface material and the water over it (the lake, the reservoir and the
--   pond with sloped sand banks, the reservoir's stone edge, woods floors, rock outcrops heroes climb); ParkBuilder
--   writes it as Terrain voxels (WriteVoxels), so the banks and rocks are smooth.
-- * boxes: what the hub builds like any hub box: the avenue round the park, the sidewalk, the paths (flat lengths
--   along smoothed lines, kit textures), the paved rounds, and the trees (BoxKit.tree's boxes with the Art.Life
--   trunk and broadleaf crown over them; they snap off and fly like any street tree).
-- * solid: the structures' hidden collision boxes (bandshell, carousel, boathouse, fountains, bridges, rink, gate
--   pillars), stamped into the height map. meshes: every Art.Park piece placed in the world (the structures over
--   those boxes, the wall and the reservoir rail as breakable lengths, reeds and lily pads), each with its colour,
--   material and whether it collides or breaks.
-- * props: the benches, lamps, bins, food carts, bushes and flower tubs along the paths (Art.Street props, CityProps
--   builds them on each device near its camera and knocks them loose on a big impact).
-- * routes (jog and walk loops), spots (picnics, buskers, boats, ducks), fountains, waters and the carousel: what each
--   device's Fx.ParkLife brings to life.
-- Placement maths: a look faces -z at ry 0; a piece at offset (ox, oy, oz) from a foot at (x, y, z) turned ry degrees
-- sits at (x + ox cos a + oz sin a, y + oy, z - ox sin a + oz cos a) (Roblox's CFrame.Angles(0, a, 0)).

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")

local ParkLayout = {}

type Box = BoxKit.Box
export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Mesh = {
	name: string,
	look: string,
	x: number,
	y: number,
	z: number,
	ry: number,
	size: { number },
	color: { number },
	mat: string,
	alpha: number,
	collide: boolean,
	breaks: boolean, -- named "prop": the street breaking knocks it loose (a wall or rail length)
	tag: string?, -- ParkSpin (the carousel's turning pieces), ParkJet (a fountain's water), ParkSign
	group: number, -- destroy-all (2026-11-20): one placed look; its collision boxes carry the same group (Shared.StreetBreak.parkDress)
}
export type Water = {
	id: string,
	level: number,
	bed: number,
	shore: any,
	blobs: { { number } },
	walled: boolean,
}
export type Route = { kind: string, pts: { { number } }, loop: boolean, length: number }
export type Park = {
	bounds: any,
	green: Rect,
	boxes: { Box },
	solid: { Box },
	meshes: { Mesh },
	props: { CityKit.Prop },
	waters: { Water },
	routes: { Route },
	spots: { [string]: { { number } } },
	fountains: { { x: number, y: number, z: number, r: number, top: number, terrace: boolean } },
	carousel: { x: number, z: number },
	places: { [string]: { x: number, z: number, ry: number, look: string } },
	paths: { { kind: string, pts: { { number } }, width: number } },
	rocks: { any },
	safe: { { x: number, z: number, r: number } },
	trees: { { number } }, -- x, z, size of every tree
	nearPlaced: any, -- (x, z, pad) -> boolean: by a place, a paved round or a safehouse
	wet: any, -- (x, z, pad) -> boolean: in a water body or its shore
}

local GRID = 4 -- Terrain's voxel

local function snap(v: number): number
	return math.floor(v / GRID + 0.5) * GRID
end

-- The rectangle inside the wall (Terrain), on Terrain's grid
function ParkLayout.green(P: any): Rect
	local b = P.bounds
	local inset = P.avenue + P.sidewalk + 1
	return {
		x0 = snap(b.minX + inset),
		z0 = snap(b.minZ + inset + 2),
		x1 = snap(b.maxX - inset),
		z1 = snap(b.maxZ - inset),
	}
end

-- (ox, oz) turned by ry degrees (Roblox's turn about y)
local function turn(ox: number, oz: number, ry: number): (number, number)
	local a = math.rad(ry)
	local c, s = math.cos(a), math.sin(a)
	return ox * c + oz * s, -ox * s + oz * c
end
ParkLayout.turn = turn

-- smooth value noise from the park's seed (rocks' lumps)
local function hnoise(seed: number, x: number, z: number): number
	local ix, iz = math.floor(x), math.floor(z)
	local fx, fz = x - ix, z - iz
	local function h(a: number, b: number): number
		return (Rng.hash(seed, a, b) % 10007) / 10007
	end
	local sx, sz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
	local a = h(ix, iz) + (h(ix + 1, iz) - h(ix, iz)) * sx
	local b = h(ix, iz + 1) + (h(ix + 1, iz + 1) - h(ix, iz + 1)) * sx
	return a + (b - a) * sz
end

-- How far inside a water body's shore line (positive in the water): the deepest circle wins
function ParkLayout.inside(w: Water, x: number, z: number): number
	local best = -math.huge
	for _, c in w.blobs do
		local dx, dz = x - c[1], z - c[2]
		local s = c[3] - math.sqrt(dx * dx + dz * dz)
		if s > best then
			best = s
		end
	end
	return best
end

local function inEllipse(e: any, x: number, z: number, k: number?): boolean
	local f = k or 1
	local dx, dz = (x - e.x) / (e.rx * f), (z - e.z) / (e.rz * f)
	return dx * dx + dz * dz <= 1
end
ParkLayout.inEllipse = inEllipse

-- The ground at (x, z) inside the green: its top, its surface material, and the water's top over it (or nil)
function ParkLayout.column(p: Park, x: number, z: number): (number, string, number?)
	local top, mat = 0, "grass"
	for _, w in p.waters do
		local s = ParkLayout.inside(w, x, z)
		local sw = w.shore.width
		if s > -sw then
			if w.walled then
				-- the reservoir: a stone coping, then a steep stone wall down to its bed
				if s <= 0 then
					return 0, w.shore.material, nil
				end
				local t = math.max(w.bed, -1 - s * 3)
				return t, if s < 4 then w.shore.material else "mud", if t < w.level then w.level else nil
			end
			if s <= 0 then
				return -0.7 * (s + sw) / sw, w.shore.material, nil -- the beach dips toward the water
			end
			local t = math.max(w.bed, -0.7 - s * 0.55)
			return t, if s < 5 then w.shore.material else "mud", if t < w.level then w.level else nil
		end
	end
	for _, r in p.rocks do
		local dx, dz = x - r.x, z - r.z
		local d = math.sqrt(dx * dx + dz * dz)
		local rr = r.r * (0.82 + 0.36 * hnoise(77, x / 9, z / 9))
		if d < rr then
			local k = 1 - (d / rr) ^ 2
			local h = r.h * math.sqrt(k) * (0.85 + 0.3 * hnoise(91, x / 5, z / 5))
			if h > top then
				top, mat = h, if h < 0.8 then "grass" else "rock"
			end
		end
	end
	if top > 0 then
		return top, mat, nil
	end
	return 0, mat, nil
end

-- The surface material where nothing special is: woods floors and lawns
function ParkLayout.floor(P: any, x: number, z: number): string
	for _, m in P.meadows do
		if inEllipse(m, x, z) then
			return "grass"
		end
	end
	for _, w in P.woods do
		if inEllipse(w, x, z) then
			return if hnoise(13, x / 14, z / 14) > 0.72 then "ground" else "leafy"
		end
	end
	return "grass"
end

-----------------------------------------------------------------------------------------------------------
-- Paths
-----------------------------------------------------------------------------------------------------------

local function catmull(pts: { { number } }, loop: boolean, step: number): { { number } }
	local n = #pts
	if n < 2 then
		return pts
	end
	local out: { { number } } = {}
	local last = if loop then n else n - 1
	local function at(i: number): { number }
		if loop then
			return pts[(i - 1) % n + 1]
		end
		return pts[math.clamp(i, 1, n)]
	end
	for i = 1, last do
		local p0, p1, p2, p3 = at(i - 1), at(i), at(i + 1), at(i + 2)
		local dx, dz = p2[1] - p1[1], p2[2] - p1[2]
		local k = math.max(1, math.ceil(math.sqrt(dx * dx + dz * dz) / step))
		for j = 0, k - 1 do
			local t = j / k
			local t2, t3 = t * t, t * t * t
			local function f(a: number, b: number, c: number, d: number): number
				return 0.5
					* (
						2 * b
						+ (-a + c) * t
						+ (2 * a - 5 * b + 4 * c - d) * t2
						+ (-a + 3 * b - 3 * c + d) * t3
					)
			end
			table.insert(out, { f(p0[1], p1[1], p2[1], p3[1]), f(p0[2], p1[2], p2[2], p3[2]) })
		end
	end
	if not loop then
		table.insert(out, pts[n])
	end
	return out
end

local function ellipsePts(e: any, step: number): { { number } }
	local per = 2 * math.pi * math.sqrt((e.rx * e.rx + e.rz * e.rz) / 2)
	local n = math.max(12, math.ceil(per / step))
	local out = {}
	for i = 0, n - 1 do
		local a = 2 * math.pi * i / n
		table.insert(out, { e.x + e.rx * math.cos(a), e.z + e.rz * math.sin(a) })
	end
	return out
end

-- Every path as a smoothed centre line (each point about `step` apart)
function ParkLayout.lines(P: any): { { kind: string, pts: { { number } }, loop: boolean, width: number } }
	local out = {}
	for _, d in P.paths do
		local pts, loop
		if d.ellipse then
			pts, loop = ellipsePts(d.ellipse, P.path.step), true
		else
			pts, loop = catmull(d.pts, d.loop == true, P.path.step), d.loop == true
		end
		table.insert(out, { kind = d.kind, pts = pts, loop = loop, width = P.path.width[d.kind] })
	end
	return out
end

-- The distance from (x, z) to the nearest path's edge (negative on a path)
local function segDist(px: number, pz: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / l2, 0, 1) else 0
	local qx, qz = a[1] + dx * t - px, a[2] + dz * t - pz
	return math.sqrt(qx * qx + qz * qz)
end
ParkLayout.segDist = segDist

function ParkLayout.pathDist(lines: { any }, x: number, z: number): number
	local best = math.huge
	for _, l in lines do
		local pts = l.pts
		local n = #pts
		for i = 1, (if l.loop then n else n - 1) do
			local d = segDist(x, z, pts[i], pts[i % n + 1]) - l.width / 2
			if d < best then
				best = d
			end
		end
	end
	return best
end

-----------------------------------------------------------------------------------------------------------
-- The build
-----------------------------------------------------------------------------------------------------------

local cache: { [any]: Park } = {}

function ParkLayout.build(Config: any): Park
	local hit = cache[Config]
	if hit then
		return hit
	end
	local P = Config.Park
	local ART = Config.ParkArt
	local gy = Config.City.ground.y
	local b = P.bounds
	local g = ParkLayout.green(P)
	local boxes: { Box } = {}
	local solid: { Box } = {}
	local meshes: { Mesh } = {}
	local group = 0 -- the look placed last: the solidAt boxes after a place() belong to it (they break together)
	local props: { CityKit.Prop } = {}
	local kit = Config.City.kit
	local rng = Rng.new(P.seed)

	local park: Park = {
		bounds = b,
		green = g,
		boxes = boxes,
		solid = solid,
		meshes = meshes,
		props = props,
		waters = {},
		routes = {},
		spots = { picnics = {}, buskers = {}, boats = {}, docked = {}, ducks = {}, carts = {} },
		fountains = {},
		carousel = { x = 0, z = 0 },
		places = {},
		paths = {},
		rocks = P.rocks,
		safe = {},
		trees = {},
		nearPlaced = nil,
		wet = nil,
	}
	for _, id in { "lake", "reservoir", "pond" } do
		local w = P[id]
		table.insert(park.waters, {
			id = id,
			level = w.level,
			bed = w.bed,
			shore = w.shore,
			blobs = w.blobs,
			walled = id == "reservoir",
		})
	end
	for _, s in Config.World.safehouses do
		if s.x and s.z and s.x > g.x0 and s.x < g.x1 and s.z > g.z0 and s.z < g.z1 then
			table.insert(park.safe, { x = s.x, z = s.z, r = P.safeClear })
		end
	end

	-- one look's pieces at a foot (x, y, z) turned ry; `scaleX` stretches a length piece (a wall) along its x
	local function place(look: string, x: number, y: number, z: number, ry: number, opts: any?): { Mesh }
		local fit = ART[look]
		local colors = P.looks[look]
		local out = {}
		if not (opts and opts.join) then
			group += 1 -- (join: the gate's sign goes with the pillar placed just before it)
		end
		if not (fit and colors) then
			return out
		end
		local o = opts or {}
		local kx = o.scaleX or 1
		local names = {}
		for name in fit do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local f = fit[name]
			local c = colors[name]
			if not c then
				continue
			end
			local ox, oz = turn(f.offset[1] * kx, f.offset[3], ry)
			local m: Mesh = {
				name = name,
				look = look,
				x = x + ox,
				y = y + f.offset[2],
				z = z + oz,
				ry = ry,
				size = { f.size[1] * kx, f.size[2], f.size[3] },
				color = c[1],
				mat = c[2],
				alpha = c[3] or 0,
				collide = o.collide == true,
				breaks = o.breaks == true,
				tag = if o.tags then o.tags[name] else o.tag,
				group = group,
			}
			table.insert(meshes, m)
			table.insert(out, m)
		end
		return out
	end

	-- a collision box in a place's own frame (lx, ly, lz are its centre; turned with the place)
	local function solidAt(
		x: number,
		z: number,
		ry: number,
		lx: number,
		ly: number,
		lz: number,
		sx: number,
		sy: number,
		sz: number,
		opts: any?
	): Box
		local ox, oz = turn(lx, lz, ry)
		local o = opts or {}
		local bx =
			BoxKit.box(solid, "parkSolid", x + ox, gy + ly, z + oz, sx, sy, sz, o.color or "sidewalk", {
				shape = o.shape,
				ry = (ry + (o.ry or 0)) % 360,
			})
		bx.tag = o.tag;
		(bx :: any).group = group
		return bx
	end

	-- the avenue round the park and the sidewalk inside it
	local av = P.avenue
	local W, D = b.maxX - b.minX, b.maxZ - b.minZ
	local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
	for _, r in
		{
			{ cx, b.minZ + av / 2, W, av },
			{ cx, b.maxZ - av / 2, W, av },
			{ b.minX + av / 2, cz, av, D - av * 2 },
			{ b.maxX - av / 2, cz, av, D - av * 2 },
		}
	do
		BoxKit.box(boxes, "road", r[1], gy + 0.1, r[2], r[3], 0.2, r[4], "road")
		if kit then
			boxes[#boxes].kit = kit.ground.Downtown.road
		end
	end
	-- the sidewalk: from the avenue to the green's edge (the wall stands on its inner side)
	local ix0, iz0, ix1, iz1 = b.minX + av, b.minZ + av, b.maxX - av, b.maxZ - av
	for _, r in
		{
			{ ix0, iz0, ix1, g.z0 },
			{ ix0, g.z1, ix1, iz1 },
			{ ix0, g.z0, g.x0, g.z1 },
			{ g.x1, g.z0, ix1, g.z1 },
		}
	do
		BoxKit.box(
			boxes,
			"sidewalk",
			(r[1] + r[3]) / 2,
			gy + 0.3,
			(r[2] + r[4]) / 2,
			r[3] - r[1],
			0.6,
			r[4] - r[2],
			"sidewalk"
		)
		if kit then
			boxes[#boxes].kit = kit.ground.Hub.sidewalk
		end
	end

	-- the wall and its gates: each side is broken by its gates (pillars either side), the runs between split into
	-- lengths of about P.wall.segment
	local wallY = gy
	local sides = {
		S = { z = g.z1 + P.wall.thick / 2, x0 = g.x0 - P.wall.thick, x1 = g.x1 + P.wall.thick, alongX = true },
		N = { z = g.z0 - P.wall.thick / 2, x0 = g.x0 - P.wall.thick, x1 = g.x1 + P.wall.thick, alongX = true },
		W = { x = g.x0 - P.wall.thick / 2, z0 = g.z0, z1 = g.z1, alongX = false },
		E = { x = g.x1 + P.wall.thick / 2, z0 = g.z0, z1 = g.z1, alongX = false },
	}
	local pillarHalf = 1.8
	park.spots.gates = {}
	for id, s in sides do
		local cuts = {}
		for _, gt in P.gates do
			if gt.side == id then
				table.insert(cuts, gt)
			end
		end
		table.sort(cuts, function(p: any, q: any)
			return p.at < q.at
		end)
		local a0 = if s.alongX then s.x0 else s.z0
		local a1 = if s.alongX then s.x1 else s.z1
		local runs = {}
		local from = a0
		for _, gt in cuts do
			local half = gt.width / 2 + pillarHalf * 2
			table.insert(runs, { from, gt.at - half })
			from = gt.at + half
			-- the pillars and, on the signed gates, the arch with the park's name
			local ry = if s.alongX then 0 else 90
			for _, side in { -1, 1 } do
				local off = side * (gt.width / 2 + pillarHalf)
				local px = if s.alongX then gt.at + off else s.x
				local pz = if s.alongX then s.z else gt.at + off
				place("GatePillar", px, wallY, pz, ry)
				solidAt(px, pz, ry, 0, 4.9, 0, 3.6, 9.8, 3.6)
			end
			local gx = if s.alongX then gt.at else s.x
			local gz = if s.alongX then s.z else gt.at
			if gt.sign then
				place("GateSign", gx, wallY, gz, ry, { tags = { SignBoard = "ParkSign" }, join = true })
			end
			table.insert(park.spots.gates, { gx, gz, ry })
		end
		table.insert(runs, { from, a1 })
		for _, r in runs do
			local len = r[2] - r[1]
			if len < 2 then
				continue
			end
			local n = math.max(1, math.ceil(len / P.wall.segment))
			local each = len / n
			for k = 1, n do
				local mid = r[1] + (k - 0.5) * each
				local x = if s.alongX then mid else s.x
				local z = if s.alongX then s.z else mid
				place("ParkWall", x, wallY, z, if s.alongX then 0 else 90, {
					scaleX = each / 24,
					collide = true,
					breaks = true,
				})
			end
		end
	end

	-- the places
	local placed: { { x: number, z: number, r: number } } = {}
	for id, pl in P.places do
		local look = pl.look or id
		park.places[id] = { x = pl.x, z = pl.z, ry = pl.ry, look = look }
		local x, z, ry = pl.x, pl.z, pl.ry
		if look == "Bandshell" then
			place(look, x, gy, z, ry)
			solidAt(x, z, ry, 0, 2, -1, 42, 4, 22)
			solidAt(x, z, ry, 0, 14.5, 13.5, 38, 21, 3)
			solidAt(x, z, ry, 0, 24.6, 7, 34, 1.2, 14)
			for k = 0, 2 do -- the steps
				solidAt(
					x,
					z,
					ry,
					0,
					0.67 + k * 1.33,
					-16 + k * 1.5 + (2 - k) * 0,
					14 - k * 1.5,
					1.33 * (k + 1),
					1.6
				)
			end
			table.insert(placed, { x = x, z = z, r = 26 })
		elseif look == "Carousel" then
			place(look, x, gy, z, ry, {
				tags = {
					CarouselCore = "ParkSpin",
					CarouselRoof = "ParkSpin",
					CarouselStripes = "ParkSpin",
					CarouselPoles = "ParkSpin",
					CarouselHorses = "ParkSpin",
					CarouselSaddles = "ParkSpin",
					CarouselLights = "ParkSpin",
				},
			})
			solidAt(x, z, ry, 0, 0.75, 0, 32.4, 1.5, 32.4, { shape = "cylinder" })
			solidAt(x, z, ry, 0, 8.4, 0, 7, 13.8, 7, { shape = "cylinder" })
			solidAt(x, z, ry, 0, 15.8, 0, 34, 1, 34, { shape = "cylinder" })
			solidAt(x, z, ry, 0, 17.6, 0, 22, 1.2, 22, { shape = "cylinder" })
			solidAt(x, z, ry, 0, 19.4, 0, 10, 1.2, 10, { shape = "cylinder" })
			park.carousel = { x = x, z = z }
			table.insert(placed, { x = x, z = z, r = 18 })
		elseif look == "Boathouse" then
			place(look, x, gy, z, ry)
			solidAt(x, z, ry, 0, 5, 10, 34, 10, 20)
			solidAt(x, z, ry, 0, 11.4, 10, 35, 2, 21)
			solidAt(x, z, ry, 0, 13.4, 10, 28, 2, 14)
			solidAt(x, z, ry, 0, 15.1, 10, 22, 1.4, 6)
			solidAt(x, z, ry, 0, 0.3, -9, 34.6, 0.6, 18)
			solidAt(x, z, ry, 0, 2.2, -17.7, 34, 3.2, 0.4)
			solidAt(x, z, ry, -16.7, 2.2, -9.4, 0.4, 3.2, 17.2)
			solidAt(x, z, ry, 16.7, 2.2, -9.4, 0.4, 3.2, 17.2)
			table.insert(placed, { x = x, z = z, r = 22 })
			-- three boats tied along the deck's edge
			for k = -1, 1 do
				local bx, bz = turn(k * 10, -21.5, ry)
				table.insert(park.spots.docked, { x + bx, z + bz, (ry + 90) % 360 })
			end
		elseif look == "Terrace" or look == "SmallFountain" then
			local terrace = look == "Terrace"
			place(look, x, gy + 0.35, z, ry, {
				tags = if terrace
					then { TerracePool = "ParkJet", TerraceBowlWater = "ParkJet" }
					else { SmallPool = "ParkJet" },
			})
			local R = if terrace then 17.6 else 7.6
			local n = if terrace then 16 else 8
			local h = if terrace then 3.1 else 2.4
			for k = 0, n - 1 do
				local a = 360 * k / n
				local lx, lz = turn(0, R, a)
				solidAt(
					x,
					z,
					0,
					lx,
					0.35 + h / 2,
					lz,
					2 * math.pi * R / n + 0.6,
					h,
					if terrace then 2.4 else 1.8,
					{ ry = a }
				)
			end
			solidAt(x, z, 0, 0, 0.5, 0, R * 2 - 1, 0.3, R * 2 - 1, { shape = "cylinder" })
			if terrace then
				solidAt(x, z, 0, 0, 6, 0, 4.4, 11.4, 4.4, { shape = "cylinder" })
				solidAt(x, z, 0, 0, 8.6, 0, 15.4, 1.0, 15.4, { shape = "cylinder" })
				solidAt(x, z, 0, 0, 12.4, 0, 7.4, 0.9, 7.4, { shape = "cylinder" })
			else
				solidAt(x, z, 0, 0, 4, 0, 2.2, 7.4, 2.2, { shape = "cylinder" })
			end
			table.insert(park.fountains, {
				x = x,
				y = gy + 0.35 + (if terrace then 2.5 else 1.85),
				z = z,
				r = if terrace then 16.2 else 7,
				top = gy + 0.35 + (if terrace then 12.7 else 7.4),
				terrace = terrace,
			})
			table.insert(placed, { x = x, z = z, r = R + 1.5 })
		elseif look == "BowBridge" or look == "StoneBridge" then
			local bow = look == "BowBridge"
			local L = pl.length
			local rise = if bow then 4.5 else 5.2
			local deckAdd = if bow then 0.7 else 0.12
			local halfW = if bow then 5.5 else 4.2
			place(look, x, gy, z, ry)
			local n = 12
			local function topAt(lz: number): number
				local t = 2 * lz / L
				return rise * (1 - t * t) + deckAdd
			end
			for k = 0, n - 1 do
				local z0, z1 = -L / 2 + L * k / n, -L / 2 + L * (k + 1) / n
				local t0, t1 = topAt(z0), topAt(z1)
				local lo = math.min(t0, t1)
				local mid = (z0 + z1) / 2
				solidAt(x, z, ry, 0, lo - 0.6, mid, halfW * 2, 1.2, z1 - z0 + 0.1)
				if math.abs(t1 - t0) > 0.05 then
					-- a ramp up toward the middle: a wedge is tallest at its +z end
					local up = t1 > t0
					solidAt(
						x,
						z,
						ry,
						0,
						lo + math.abs(t1 - t0) / 2,
						mid,
						halfW * 2,
						math.abs(t1 - t0),
						z1 - z0 + 0.1,
						{
							shape = "wedge",
							ry = if up then 0 else 180,
						}
					)
				end
				local railH = if bow then 3.8 else 2.6
				for _, side in { -1, 1 } do
					solidAt(x, z, ry, side * (halfW + 0.4), lo + railH / 2, mid, 0.5, railH, z1 - z0 + 0.1)
				end
			end
			if not bow then
				for _, side in { -1, 1 } do
					solidAt(x, z, ry, 0, -3.5, side * 23, 10, 7, 16)
				end
			end
			table.insert(park.spots.buskers, { turn(0, -L / 2 - 6, ry) })
			local bk = park.spots.buskers[#park.spots.buskers]
			bk[1] += x
			bk[2] += z
			bk[3] = ry
		elseif look == "Rink" then
			place(look, x, gy, z, ry)
			solidAt(x, z, ry, 0, 0.15, 0, 69, 0.3, 39, { tag = "ParkIce" })
			solidAt(x, z, ry, 35, 1.7, 0, 0.6, 3.4, 40)
			solidAt(x, z, ry, -35, 1.7, 0, 0.6, 3.4, 40)
			solidAt(x, z, ry, 0, 1.7, 20, 70, 3.4, 0.6)
			solidAt(x, z, ry, 0, 1.7, -20, 70, 3.4, 0.6)
			table.insert(placed, { x = x, z = z, r = 40 })
		end
	end

	-- paths and paved rounds
	local P2 = P.path
	local lines = ParkLayout.lines(P)
	park.paths = lines
	local alt = 0
	for _, l in lines do
		local pts = l.pts
		local n = #pts
		local w = l.width
		for i = 1, (if l.loop then n else n - 1) do
			local a, c = pts[i], pts[i % n + 1]
			local dx, dz = c[1] - a[1], c[2] - a[2]
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 0.5 then
				continue
			end
			alt += 1
			local y = gy + P2.y - P2.thick / 2 + (alt % 2) * 0.03
			local pb = BoxKit.box(
				boxes,
				"sidewalk",
				(a[1] + c[1]) / 2,
				y,
				(a[2] + c[2]) / 2,
				w,
				P2.thick,
				len + w * 0.5,
				if l.kind == "drive" then "road" elseif l.kind == "track" then "soil" else "sidewalk",
				{ ry = math.deg(math.atan2(dx, dz)) % 360 }
			)
			local k = P2.kit[l.kind]
			if kit and k then
				pb.kit = k
			end
			if l.kind == "track" then
				pb.mat = "Ground" -- the running loop's packed earth (no kit texture)
			end
		end
		table.insert(park.routes, { kind = l.kind, pts = pts, loop = l.loop, length = 0 })
	end
	for _, r in park.routes do
		local total = 0
		local n = #r.pts
		for i = 1, (if r.loop then n else n - 1) do
			local a, c = r.pts[i], r.pts[i % n + 1]
			total += math.sqrt((c[1] - a[1]) ^ 2 + (c[2] - a[2]) ^ 2)
		end
		r.length = total
	end
	for _, pz in P.plazas do
		if pz.rect then
			local pb =
				BoxKit.box(boxes, "sidewalk", pz.x, gy + 0.2, pz.z, pz.rect[1], 0.4, pz.rect[2], "sidewalk")
			pb.kit = if kit then "Flagstone" else nil
		else
			local pb =
				BoxKit.box(boxes, "sidewalk", pz.x, gy + 0.2, pz.z, pz.r * 2, 0.4, pz.r * 2, "sidewalk", {
					shape = "cylinder",
				})
			pb.kit = if kit then "Flagstone" else nil
		end
	end

	local function nearPlaced(x: number, z: number, pad: number): boolean
		for _, q in placed do
			local dx, dz = x - q.x, z - q.z
			if dx * dx + dz * dz < (q.r + pad) ^ 2 then
				return true
			end
		end
		for _, s in park.safe do
			local dx, dz = x - s.x, z - s.z
			if dx * dx + dz * dz < (s.r + pad) ^ 2 then
				return true
			end
		end
		for _, pz in P.plazas do
			if pz.rect then
				if
					math.abs(x - pz.x) < pz.rect[1] / 2 + pad
					and math.abs(z - pz.z) < pz.rect[2] / 2 + pad
				then
					return true
				end
			else
				local dx, dz = x - pz.x, z - pz.z
				if dx * dx + dz * dz < (pz.r + pad) ^ 2 then
					return true
				end
			end
		end
		return false
	end
	local function wet(x: number, z: number, pad: number): boolean
		for _, w in park.waters do
			if ParkLayout.inside(w, x, z) > -(w.shore.width + pad) then
				return true
			end
		end
		return false
	end
	local function rocky(x: number, z: number, pad: number): boolean
		for _, r in P.rocks do
			local dx, dz = x - r.x, z - r.z
			if dx * dx + dz * dz < (r.r * 1.2 + pad) ^ 2 then
				return true
			end
		end
		return false
	end
	local function inGreen(x: number, z: number, pad: number): boolean
		return x > g.x0 + pad and x < g.x1 - pad and z > g.z0 + pad and z < g.z1 - pad
	end
	park.nearPlaced = nearPlaced
	park.wet = wet

	-- street props along the paths: lamps every ~44 studs (alternating sides), a bench every ~30 facing the path with
	-- a bin by every other one; a food cart at each busy round; bushes and flower tubs by the gates and fountains
	local taken: { { number } } = {}
	local function free(x: number, z: number, r: number): boolean
		for _, t in taken do
			local dx, dz = x - t[1], z - t[2]
			if dx * dx + dz * dz < (r + t[3]) ^ 2 then
				return false
			end
		end
		return true
	end
	local function putProp(name: string, x: number, z: number, ry: number, r: number): CityKit.Prop?
		if not (inGreen(x, z, 3) and free(x, z, r) and not wet(x, z, 1) and not rocky(x, z, 1)) then
			return nil
		end
		if nearPlaced(x, z, 1) and name ~= "FoodCart" and name ~= "FlowerTub" then
			return nil
		end
		if ParkLayout.pathDist(lines, x, z) < 0.6 then
			return nil
		end
		table.insert(taken, { x, z, r })
		return CityKit.put(props, name, x, gy, z, ry % 360)
	end
	for li, l in lines do
		local pts = l.pts
		local n = #pts
		local run, nextLamp, nextBench, side = 0, 12, 20, if li % 2 == 0 then 1 else -1
		local benches = 0
		for i = 1, (if l.loop then n else n - 1) do
			local a, c = pts[i], pts[i % n + 1]
			local dx, dz = c[1] - a[1], c[2] - a[2]
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 0.5 then
				continue
			end
			local ux, uz = dx / len, dz / len
			local nx, nz = -uz, ux -- left of travel
			run += len
			if run >= nextLamp then
				local off = l.width / 2 + 1.4
				local x, z = c[1] + nx * off * side, c[2] + nz * off * side
				putProp("OldLamp", x, z, math.deg(math.atan2(-nx * side, -nz * side)), 1.2)
				nextLamp = run + (if l.kind == "mall" then 24 else 44)
				side = -side
			end
			if run >= nextBench and l.kind ~= "track" then
				local off = l.width / 2 + 2.6
				local s2 = -side
				local x, z = c[1] + nx * off * s2, c[2] + nz * off * s2
				-- the bench faces the path: its front (-z at ry 0) toward the path
				local ry = math.deg(math.atan2(nx * s2, nz * s2))
				if putProp("Bench", x, z, ry, 3) then
					benches += 1
					if benches % 2 == 0 then
						putProp("Bin", x + ux * 5, z + uz * 5, ry, 1.3)
					end
				end
				nextBench = run + (if l.kind == "mall" then 18 else 32)
			end
		end
	end
	-- the Mall's elm rows
	local mall = P.trees.mall
	local treeBoxes: { { number } } = {}
	local function tree(x: number, z: number, size: number): boolean
		if not (inGreen(x, z, 6) and not wet(x, z, P.trees.clear.water) and not rocky(x, z, 3)) then
			return false
		end
		if nearPlaced(x, z, P.trees.clear.place) then
			return false
		end
		if ParkLayout.pathDist(lines, x, z) < P.trees.clear.path then
			return false
		end
		if not free(x, z, size * 0.3) then
			return false
		end
		for _, t in treeBoxes do
			local dx, dz = x - t[1], z - t[2]
			if dx * dx + dz * dz < (t[3] * 0.45 + size * 0.45) ^ 2 then
				return false
			end
		end
		table.insert(treeBoxes, { x, z, size })
		BoxKit.box(boxes, "prop", x, gy + size * 0.4, z, size * 0.18, size * 0.8, size * 0.18, "wood").look =
			"TreeTrunk"
		boxes[#boxes].park = true
		BoxKit.box(
			boxes,
			"prop",
			x,
			gy + size,
			z,
			size * 0.9,
			size * 0.9,
			size * 0.9,
			"leaf",
			{ shape = "ball" }
		).look =
			"Canopy"
		boxes[#boxes].park = true
		return true
	end
	do
		local m = P.paths[1].pts -- the Mall
		local x = m[1][1]
		local zA, zB = m[1][2], m[#m][2]
		local z = zA - 8
		while z > zB + 4 do
			for _, sd in { -1, 1 } do
				tree(x + sd * mall.out, z, mall.size)
			end
			z -= mall.every
		end
	end
	-- the woods and the open ground: tries on a jittered grid, denser in the woods, never on a lawn's middle
	local area = (g.x1 - g.x0) * (g.z1 - g.z0)
	local tries = math.floor(area / P.trees.woods)
	local count = 0
	for _ = 1, tries do
		if count >= P.trees.max then
			break
		end
		local x = rng:range(g.x0 + 8, g.x1 - 8)
		local z = rng:range(g.z0 + 8, g.z1 - 8)
		local woods = false
		for _, w in P.woods do
			if inEllipse(w, x, z) then
				woods = true
			end
		end
		local keep = woods or rng:next() < P.trees.woods / P.trees.open
		local lawn = false
		for _, m in P.meadows do
			if inEllipse(m, x, z, P.trees.clear.meadow) then
				lawn = true
			end
		end
		if keep and not lawn then
			local s = rng:range(P.trees.size[1], P.trees.size[2])
			if tree(x, z, s) then
				count += 1
			end
		end
	end
	park.trees = treeBoxes

	-- food carts, bushes and flower tubs at the rounds and gates
	local cartAt = {
		{ -575, -530, -90 }, -- by the Mall's gate
		{ -615, -618, 0 }, -- the terrace
		{ -120, -540, 180 }, -- the rink's apron
		{ -130, -1004, 90 }, -- the north-east fountain
		{ -100, -790, 90 }, -- the east gate onto the lawn loop
		{ -470, -1050, 0 }, -- the north gate by the reservoir
	}
	for _, c in cartAt do
		local pr = putProp("FoodCart", c[1], c[2], c[3], 3.5)
		if pr and kit and kit.play then
			pr.tint = CityKit.pick(kit, kit.play.tints, pr.x, pr.z, kit.play.foodCart.salt)
			table.insert(park.spots.carts, { pr.x, pr.z, pr.ry })
		end
	end
	for _, gt in park.spots.gates do
		for _, sd in { -1, 1 } do
			local ox, oz = turn(sd * 13, 9, gt[3])
			-- inward is +z for the south wall's gates... keep both: the one inside the green stays
			for _, flip in { 1, -1 } do
				local x, z = gt[1] + ox, gt[2] + oz * flip
				if inGreen(x, z, 3) then
					putProp("Bush", x, z, 0, 2.6)
					break
				end
			end
		end
	end
	for _, f in park.fountains do
		local r = f.r + (if f.terrace then 6 else 5)
		for k = 0, 5 do
			local a = 2 * math.pi * (k + 0.5) / 6
			putProp("FlowerTub", f.x + r * math.cos(a), f.z + r * math.sin(a), 0, 1.6)
		end
	end

	-- reeds and lily pads round the lake and the pond (shore spots by hash), the reservoir's iron rail
	for _, w in park.waters do
		if w.walled then
			-- the rail round the stone edge: walk the shore line in steps of the rail's length
			local cx2, cz2 = 0, 0
			for _, c in w.blobs do
				cx2 += c[1] / #w.blobs
				cz2 += c[2] / #w.blobs
			end
			local ring = {}
			local n = 96
			for k = 0, n - 1 do
				local a = 2 * math.pi * k / n
				local dx, dz = math.cos(a), math.sin(a)
				local r = 0
				while
					ParkLayout.inside(w, cx2 + dx * r, cz2 + dz * r)
						> -(w.shore.width - P.reservoir.rail.inset)
					and r < 600
				do
					r += 0.5
				end
				table.insert(ring, { cx2 + dx * r, cz2 + dz * r })
			end
			local acc = 0
			local last = ring[1]
			for k = 2, n + 1 do
				local p2 = ring[(k - 1) % n + 1]
				local dx, dz = p2[1] - last[1], p2[2] - last[2]
				local d = math.sqrt(dx * dx + dz * dz)
				acc += d
				if acc >= P.reservoir.rail.every or k == n + 1 then
					local mx, mz = (p2[1] + last[1]) / 2, (p2[2] + last[2]) / 2
					local L = math.sqrt((p2[1] - last[1]) ^ 2 + (p2[2] - last[2]) ^ 2)
					if L > 2 then
						-- a rail length's x runs along the edge
						place("ParkRail", mx, gy, mz, math.deg(math.atan2(-dz, dx)), {
							scaleX = L / 12,
							collide = true,
							breaks = true,
						})
					end
					last = p2
					acc = 0
				end
			end
			continue
		end
		for i, c in w.blobs do
			local tries2 = math.max(2, math.floor(c[3] / 9))
			for k = 1, tries2 do
				local a = (Rng.hash(P.seed, i, k, 5) % 3600) / 10
				local ar = math.rad(a)
				local x, z = c[1] + math.cos(ar) * (c[3] - 1.5), c[2] + math.sin(ar) * (c[3] - 1.5)
				local s = ParkLayout.inside(w, x, z)
				if s > 0.5 and s < 4 and ParkLayout.pathDist(lines, x, z) > 6 and not nearPlaced(x, z, 4) then
					place(
						if k % 3 == 0 then "LilyPads" else "Reeds",
						x,
						w.level - (if k % 3 == 0 then 0 else 0.6),
						z,
						a
					)
				end
			end
		end
		-- ducks and boats: open water spots
		for k = 1, 60 do
			local c = w.blobs[(k - 1) % #w.blobs + 1]
			local a = math.rad((Rng.hash(P.seed, k, 9) % 3600) / 10)
			local r = (Rng.hash(P.seed, k, 10) % 1000) / 1000 * c[3] * 0.8
			local x, z = c[1] + math.cos(a) * r, c[2] + math.sin(a) * r
			local s = ParkLayout.inside(w, x, z)
			if s > 4 then
				table.insert(park.spots.ducks, { x, z, w.level })
			end
			if w.id == "lake" and s > 12 and k % 4 == 0 then
				table.insert(park.spots.boats, { x, z, math.deg(a) })
			end
		end
	end

	-- picnics on the lawns, buskers by the Mall and the terrace
	for _, m in P.meadows do
		for k = 1, 8 do
			local a = math.rad((Rng.hash(P.seed, k, 21, #m.id) % 3600) / 10)
			local r = ((Rng.hash(P.seed, k, 22, #m.id) % 1000) / 1000) ^ 0.5 * 0.8
			local x, z = m.x + math.cos(a) * m.rx * r, m.z + math.sin(a) * m.rz * r
			if not rocky(x, z, 3) and ParkLayout.pathDist(lines, x, z) > 5 and free(x, z, 4) then
				table.insert(taken, { x, z, 4 })
				table.insert(park.spots.picnics, { x, z, math.deg(a) })
			end
		end
	end
	for _, s in { { -604, -548, 90 }, { -576, -596, -90 }, { -566, -650, 0 }, { -160, -548, 180 } } do
		table.insert(park.spots.buskers, s)
	end
	cache[Config] = park
	return park
end

-- The street props alone (WorldMap.propsStep: a device's prop list, the same order as build)
function ParkLayout.props(Config: any): { CityKit.Prop }
	return ParkLayout.build(Config).props
end

-- The world rectangles the city's ground plates leave open (the Terrain inside the wall)
function ParkLayout.holes(Config: any): { Rect }
	if not Config.Park then
		return {}
	end
	return { ParkLayout.green(Config.Park) }
end

return ParkLayout
