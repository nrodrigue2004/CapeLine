--!strict
-- IncidentSpots: where incidents, contracts and events can happen, from the world data (WorldMap.build).
-- Pure so Lune checks every spot is real: streets are open ground, towers and signs are real hub buildings,
-- the tram runs on a tram line toward the end of the line, roof chases hop between nearby roofs, and the
-- cat sits on a Docks crane.
-- * kinds(world, x, z, radius): which spot kinds exist near a point
-- * find(world, kind, x, z, minD, maxD, rng): one spot of that kind, or nil

local WorldMap = if script then require(script.Parent.WorldMap) else (require :: any)("./WorldMap")

local IncidentSpots = {}

export type Spot = {
	kind: string,
	x: number,
	y: number,
	z: number,
	building: number?, -- the building it is on or at
	points: { { number } }?, -- balconies, roof hops or a path: { x, y, z }
	dir: { number }?, -- the tram's travel direction { dx, dz } and the distance to the gap in [3]
}

local GROUND = 1.5 -- open ground has no roof above this

local function ground(world: any, x: number, z: number): number
	return WorldMap.heightAt(world, x, z)
end

local function inMap(Config: any, x: number, z: number): boolean
	local half = Config.City.mapSize / 2 - 60
	return math.abs(x) < half and math.abs(z) < half
end

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- A street or open-ground point minD to maxD from (x, z)
local function street(
	Config: any,
	world: any,
	x: number,
	z: number,
	minD: number,
	maxD: number,
	rng: any
): Spot?
	for _ = 1, 40 do
		local a = rng:range(0, math.pi * 2)
		local r = rng:range(minD, maxD)
		local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
		if inMap(Config, px, pz) and ground(world, px, pz) <= GROUND then
			-- room around it for the robots and the ring
			local open = true
			for k = 0, 3 do
				local b = k * math.pi / 2
				if ground(world, px + math.cos(b) * 8, pz + math.sin(b) * 8) > GROUND then
					open = false
					break
				end
			end
			if open then
				return { kind = "street", x = px, y = Config.City.ground.y + 0.5, z = pz }
			end
		end
	end
	return nil
end

local function buildingsNear(
	world: any,
	x: number,
	z: number,
	minD: number,
	maxD: number,
	filter: (any) -> boolean
): { any }
	local out = {}
	for _, b in world.buildings do
		local d = dist(b.x, b.z, x, z)
		if d >= minD and d <= maxD and filter(b) then
			table.insert(out, b)
		end
	end
	return out
end

-- Three balcony points on the faces of a tall building, between half and 80% of its height
local function balconies(b: any, rng: any): { { number } }
	local out = {}
	local faces = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for i = 1, 3 do
		local f = faces[(i - 1) % 4 + 1]
		local h = b.base + (b.top - b.base) * rng:range(0.45, 0.8)
		local along = rng:range(-0.3, 0.3)
		local x = b.x + f[1] * (b.sx / 2 + 2.5) + (if f[1] == 0 then along * b.sx else 0)
		local z = b.z + f[2] * (b.sz / 2 + 2.5) + (if f[2] == 0 then along * b.sz else 0)
		table.insert(out, { x, h, z })
	end
	return out
end

-- Roof hops: from a start building to its nearest unvisited neighbours within 70 studs
local function roofPath(world: any, start: any, hops: number): { { number } }
	local path = { { start.x, start.top + 1, start.z } }
	local used = { [start.id] = true }
	local cur = start
	for _ = 2, hops do
		local best, bestD = nil, 70
		for _, b in world.buildings do
			if not used[b.id] and b.crown == nil then -- a skyscraper's crown is not a roof to land on
				local d = dist(b.x, b.z, cur.x, cur.z)
				if d < bestD then
					best, bestD = b, d
				end
			end
		end
		if not best then
			break
		end
		used[best.id] = true
		table.insert(path, { best.x, best.top + 1, best.z })
		cur = best
	end
	return path
end

local function tramLines(Config: any): ({ number }, any, number)
	local city = Config.City
	-- the tram lines run through the first 700 x 700 (downtown.core), where they always have
	local d = city.downtown.core or city.districts.Downtown
	local pitch = city.downtown.block + city.downtown.street
	return { d.minZ + pitch * 2, d.minZ + pitch * 4 }, d, pitch
end

function IncidentSpots.find(
	Config: any,
	world: any,
	kind: string,
	x: number,
	z: number,
	minD: number,
	maxD: number,
	rng: any,
	opts: any?
): Spot?
	if kind == "street" or kind == "any" then
		return street(Config, world, x, z, minD, maxD, rng)
	elseif kind == "tower" then
		local list = buildingsNear(world, x, z, minD, maxD, function(b)
			return b.top - b.base >= 60
		end)
		if #list == 0 then
			return nil
		end
		local b = list[rng:int(1, #list)]
		return { kind = kind, x = b.x, y = b.base, z = b.z, building = b.id, points = balconies(b, rng) }
	elseif kind == "sign" then
		local list = buildingsNear(world, x, z, minD, maxD, function(b)
			local h = b.top - b.base
			return h >= 18
				and h <= 90
				and (b.district == "Downtown" or b.district == "OldTown" or b.district == "Uptown")
		end)
		if #list == 0 then
			return nil
		end
		local b = list[rng:int(1, #list)]
		-- the billboard leans over the street side nearest the hero
		local fx, fz = 0, 0
		if math.abs(x - b.x) / b.sx > math.abs(z - b.z) / b.sz then
			fx = if x > b.x then 1 else -1
		else
			fz = if z > b.z then 1 else -1
		end
		local ex, ez = b.x + fx * (b.sx / 2 + 1), b.z + fz * (b.sz / 2 + 1)
		return {
			kind = kind,
			x = ex + fx * 6,
			y = Config.City.ground.y + 0.5,
			z = ez + fz * 6,
			building = b.id,
			points = { { ex, b.top + 6, ez } },
			dir = { fx, fz },
		}
	elseif kind == "roof" then
		local hops = (opts and opts.hops) or 6
		local list = buildingsNear(world, x, z, minD, maxD, function(b)
			return b.top - b.base <= 80
		end)
		if #list > 0 then
			local b = list[rng:int(1, #list)]
			local path = roofPath(world, b, hops)
			if #path >= 3 then
				return { kind = kind, x = b.x, y = b.top + 1, z = b.z, building = b.id, points = path }
			end
		end
		-- no roofs out here: a street chase instead
		local s = street(Config, world, x, z, minD, maxD, rng)
		if not s then
			return nil
		end
		local path = IncidentSpots.streetPath(Config, world, s.x, s.z, hops, 45, rng)
		if #path < 3 then
			return nil
		end
		s.kind = "roof"
		s.points = path
		return s
	elseif kind == "tram" then
		local lines, d, pitch = tramLines(Config)
		local options = {}
		for _, lz in lines do
			if math.abs(lz - z) <= maxD and x > d.minX - maxD and x < d.maxX + maxD then
				table.insert(options, lz)
			end
		end
		if #options == 0 then
			return nil
		end
		local lz = options[rng:int(1, #options)]
		local east = rng:chance(0.5)
		local run = (opts and opts.run) or 420
		local gapX = if east then d.maxX - pitch / 2 else d.minX + pitch / 2
		local sx = gapX + (if east then -run else run)
		return {
			kind = kind,
			x = sx,
			y = Config.City.ground.y + 0.2,
			z = lz,
			dir = { if east then 1 else -1, 0, run },
		}
	elseif kind == "crane" then
		local c = world.spots.crane
		if not c or dist(c.x, c.z, x, z) > maxD then
			return nil
		end
		return { kind = kind, x = c.x, y = c.y - 4, z = c.z, points = { { c.x, c.y - 4, c.z } } }
	end
	return nil
end

-- A path over open ground from (x, z): up to `steps` legs of `len` studs, turning away from buildings
-- (the street chase and the escort truck). Every leg's middle and end are open ground.
function IncidentSpots.streetPath(
	Config: any,
	world: any,
	x: number,
	z: number,
	steps: number,
	len: number,
	rng: any
): { { number } }
	local y = Config.City.ground.y + 0.5
	local path = { { x, y, z } }
	local a = rng:range(0, math.pi * 2)
	for _ = 2, steps do
		local p = path[#path]
		local placed = false
		for try = 0, 9 do
			local turn = (if try % 2 == 0 then 1 else -1) * math.ceil(try / 2) * 0.45
			local b = a + turn + rng:range(-0.2, 0.2)
			local nx, nz = p[1] + math.cos(b) * len, p[3] + math.sin(b) * len
			local mx, mz = (p[1] + nx) / 2, (p[3] + nz) / 2
			if
				inMap(Config, nx, nz)
				and ground(world, nx, nz) <= GROUND
				and ground(world, mx, mz) <= GROUND
			then
				-- never double back onto the last leg
				local back = #path >= 2 and dist(nx, nz, path[#path - 1][1], path[#path - 1][3]) < len * 0.6
				if not back then
					table.insert(path, { nx, y, nz })
					a = b
					placed = true
					break
				end
			end
		end
		if not placed then
			break
		end
	end
	return path
end

-- Which spot kinds exist within radius of (x, z) (quick checks, no rng)
function IncidentSpots.kinds(
	Config: any,
	world: any,
	x: number,
	z: number,
	radius: number
): { [string]: boolean }
	local out: { [string]: boolean } = { street = true, any = true }
	for _, b in world.buildings do
		local d = dist(b.x, b.z, x, z)
		if d <= radius and d >= 40 then
			local h = b.top - b.base
			if h >= 60 then
				out.tower = true
			end
			if
				h >= 18
				and h <= 90
				and (b.district == "Downtown" or b.district == "OldTown" or b.district == "Uptown")
			then
				out.sign = true
			end
			out.roof = true
		end
	end
	out.roof = true -- a street chase works anywhere
	local lines, d = tramLines(Config)
	for _, lz in lines do
		if math.abs(lz - z) <= radius and x > d.minX - radius and x < d.maxX + radius then
			out.tram = true
		end
	end
	local c = world.spots.crane
	if c and dist(c.x, c.z, x, z) <= radius then
		out.crane = true
	end
	return out
end

-- A ground point near (x, z) for a drop pad or a squad (open ground within r)
function IncidentSpots.groundNear(
	Config: any,
	world: any,
	x: number,
	z: number,
	r: number,
	rng: any
): (number, number, number)
	local s = street(Config, world, x, z, 0, r, rng)
	if s then
		return s.x, s.y, s.z
	end
	return x, ground(world, x, z) + 0.5, z
end

return IncidentSpots
