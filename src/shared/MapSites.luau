--!strict
-- MapSites: story missions on the real map (missions lane, 2026-11-20; nate's call "Mix": story missions play
-- privately on the map, special places keep pockets; Config.MapSites). Pure, so Lune checks every site.
-- * layout(Config, world, name): the same Layout a pocket gives (Shared.PocketLayout: points, lists, boxes, floorY) but
--   in world studs at the layout's site, so Config.Story and MissionService's steps read the same names (spawn, boss,
--   stations, path, turrets, beacons...). Each pocket point is turned and scaled onto the site, then
--     - at a permanent site (the pocket's geometry is a real piece of the city: permanent() below) it keeps its height
--       over the piece; a point the pocket had on its floor settles onto open ground nearby;
--     - at a city site a point the pocket had on its floor settles onto open street or paving nearby (never inside a
--       building or over water), a point it had on a roof goes onto the nearest real roof (each pocket roof onto its own
--       real one), and a point on a kept set piece stays on that piece.
--   boxes: the run's own set pieces (the site's `keep` kinds), built by MissionService as a phased Sites model.
-- * permanent(Config): the boxes of the permanent pieces (Harbour Bridge, Crane Tower, Crane's plant) for WorldMap to
--   build into the city for everyone, and the clear circles their ground is kept free with. A box with `nomap` (Crane
--   Tower's ledges and deck) stays out of the city's height map: heights over it come from topAt.
-- * topAt(boxes, x, z, y): the highest solid top over (x, z) at or under y + 3 among some boxes (a site's own heights,
--   so a robot on Crane Tower's deck stands on it and one on the ground below stays there); nil when none covers.
-- * standing(world, l, x, y, z): what a map point stands on (for the tests): the surface's height or nil and why.

local PocketLayout = if script
	then require(script.Parent.PocketLayout)
	else (require :: any)("./PocketLayout")
local HeightMap = if script then require(script.Parent.HeightMap) else (require :: any)("./HeightMap")
local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")

local MapSites = {}

type Box = BoxKit.Box
type Layout = PocketLayout.Layout

local SHELL = 5 -- PocketLayout's shell: the floor and the 4 sealing walls, always its first boxes
local MIN = 4 -- the thinnest a moved box gets (a wall's thickness)

-- Is this pocket layout played on the map?
function MapSites.on(Config: any, name: string?): boolean
	local M = Config.MapSites
	return M ~= nil and name ~= nil and M.on[name] == true and M.sites[name] ~= nil
end

local function turn(site: any): (number, number)
	local a = math.rad(site.yaw or 0)
	return math.floor(math.cos(a) + 0.5), math.floor(math.sin(a) + 0.5)
end

-- A pocket offset (from the pocket's centre) to world x, z at the site
local function place(site: any, lx: number, lz: number): (number, number)
	local c, s = turn(site)
	lx *= site.sx or 1
	lz *= site.sz or 1
	return site.x + lx * c + lz * s, site.z - lx * s + lz * c
end

local function counts(b: Box): boolean
	return BoxKit.solid(b) and b.tag ~= "ceiling" and b.tag ~= "decor" and b.kind ~= "band"
end

local function covers(b: Box, x: number, z: number): boolean
	local hx, hz = BoxKit.footprint(b)
	if b.shape == "cylinder" then
		hx, hz = b.sx, b.sx
	end
	return math.abs(x - b.cx) <= hx / 2 and math.abs(z - b.cz) <= hz / 2
end

-- The box a pocket point stands on (its top at or under the point), or nil for the pocket's floor
local function under(pl: Layout, x: number, y: number, z: number): (number, Box?)
	local top, on = pl.floorY, nil
	for i, b in pl.boxes do
		if i > SHELL and counts(b) and covers(b, x, z) then
			local t = b.cy + b.sy / 2
			if t <= y + 0.5 and t > top then
				top, on = t, b
			end
		end
	end
	return top, on
end

-- A pocket box onto the site (turned by a multiple of 90 degrees and scaled; its height over the floor kept)
local function moved(site: any, pl: Layout, b: Box, base: number): Box
	local n: Box = table.clone(b)
	local x, z = place(site, b.cx - pl.cx, b.cz - pl.cz)
	local _, s = turn(site)
	-- sizes scale with the site, but never thinner than MIN studs (or the box itself, if thinner): a wall keeps a
	-- real wall's thickness (the city breaks it into Structure pieces)
	local function span(v: number, k: number): number
		return math.max(v * k, math.min(v, MIN))
	end
	local fx, fz = span(b.sx, site.sx or 1), span(b.sz, site.sz or 1)
	if b.shape == "cylinder" then
		-- a round piece keeps its size (the War-Frame's pillars are cover of Config.Story.warframe.pillarRadius)
		fx, fz = b.sx, b.sx
	elseif s ~= 0 then
		fx, fz = fz, fx
	end
	n.cx, n.cz = x, z
	n.cy = b.cy - pl.floorY + base
	n.sx, n.sz = math.max(fx, 1), math.max(fz, 1)
	if b.shape == "cylinder" then
		n.sx = math.max(fx, 2)
		n.sz = n.sx
	end
	n.art = nil
	return n
end

local pockets: { [string]: Layout } = {}
local function pocket(Config: any, name: string): Layout
	local pl = pockets[name]
	if not pl then
		pl = PocketLayout.build(Config, 1, name)
		pockets[name] = pl
	end
	return pl
end

local permanentCache: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

-- The permanent pieces' boxes (for WorldMap, built for everyone whether or not the missions are on the map) and the
-- circles kept clear for them
function MapSites.permanent(Config: any): { boxes: { Box }, clear: { BoxKit.Circle } }
	local hit = permanentCache[Config]
	if hit then
		return hit
	end
	local out = { boxes = {}, clear = {} }
	local M = Config.MapSites
	for name, site in (if M then M.sites else {}) :: { [string]: any } do
		if site.permanent and PocketLayout.known(name) then
			local pl = pocket(Config, name)
			for i, b in pl.boxes do
				if i > SHELL and not (b.kind == "plaza" and b.color == "water") then
					local n = moved(site, pl, b, site.base or 0)
					if site.nomap and site.nomap[b.kind] then
						(n :: any).nomap = true
					end
					(n :: any).site = name
					table.insert(out.boxes, n)
				end
			end
			for _, c in site.clear or {} do
				table.insert(out.clear, { x = c.x, z = c.z, r = c.r })
			end
		end
	end
	permanentCache[Config] = out
	return out
end

-- The highest solid top over (x, z) at or under y + 3 (any height when y is nil) among `boxes`; nil when none covers
function MapSites.topAt(boxes: { Box }, x: number, z: number, y: number?): number?
	local best: number? = nil
	local reach = if y then y + 3 else math.huge
	for _, b in boxes do
		if counts(b) and covers(b, x, z) then
			local t = b.cy + b.sy / 2
			if t <= reach and (not best or t > best) then
				best = t
			end
		end
	end
	return best
end

local function inBasin(Config: any, x: number, z: number): boolean
	local bs = Config.City.docks.basin
	return x >= bs.minX and x <= bs.maxX and z >= bs.minZ and z <= bs.maxZ
end

-- Open ground at (x, z): street, paving or lawn height, not in water, with room round it (no wall within 3 studs)
local function open(Config: any, world: any, x: number, z: number, avoid: { Box }): number?
	local h = HeightMap.at(world.heights, x, z)
	if h > 1.6 or h < -0.5 or inBasin(Config, x, z) then
		return nil
	end
	for _, d in { { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } } do
		local hx, hz = x + d[1], z + d[2]
		if HeightMap.at(world.heights, hx, hz) > 1.6 or inBasin(Config, hx, hz) then
			return nil
		end
	end
	for _, b in avoid do
		if counts(b) and covers(b, x, z) then
			return nil
		end
	end
	return h
end

-- The nearest open ground to (x, z), searching rings out to `reach` studs; nil when there is none
local function settle(
	Config: any,
	world: any,
	x: number,
	z: number,
	avoid: { Box }
): (number?, number?, number?)
	local S = Config.MapSites.settle
	local h = open(Config, world, x, z, avoid)
	if h then
		return x, h, z
	end
	for r = S.step, S.ground, S.step do
		local n = math.max(8, math.floor(2 * math.pi * r / S.step))
		for k = 0, n - 1 do
			local a = k / n * 2 * math.pi
			local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
			local g = open(Config, world, px, pz, avoid)
			if g then
				return px, g, pz
			end
		end
	end
	return nil
end

-- The nearest real roof to (x, z) not taken by another pocket roof: a building (no skyscraper crown, no higher than
-- settle.roofTop), the spot on it nearest (x, z) a few studs in from its edge
local function roofNear(Config: any, world: any, x: number, z: number, taken: { [any]: boolean }): any?
	local S = Config.MapSites.settle
	local best, bestD = nil, S.roof
	for _, b in world.buildings do
		if
			not b.crown
			and not taken[b]
			and b.top <= (S.roofTop or math.huge)
			and b.sx >= 12
			and b.sz >= 12
		then
			local dx = math.max(0, math.abs(x - b.x) - b.sx / 2)
			local dz = math.max(0, math.abs(z - b.z) - b.sz / 2)
			local d = math.sqrt(dx * dx + dz * dz)
			if d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

local function roofSpot(b: any, x: number, z: number): (number, number)
	local mx, mz = math.min(4, b.sx / 4), math.min(4, b.sz / 4)
	return math.clamp(x, b.x - b.sx / 2 + mx, b.x + b.sx / 2 - mx),
		math.clamp(z, b.z - b.sz / 2 + mz, b.z + b.sz / 2 - mz)
end

-- Does a box cut into one of the city's buildings (footprints and heights overlapping)? Not the city's copies of the
-- permanent pieces themselves
local function inBuilding(world: any, b: Box): any?
	local hx, hz = b.sx / 2, b.sz / 2
	local lo, hi = b.cy - b.sy / 2, b.cy + b.sy / 2
	for _, c in world.buildings do
		if not c.site then
			local ox = math.min(b.cx + hx, c.x + c.sx / 2) - math.max(b.cx - hx, c.x - c.sx / 2)
			local oz = math.min(b.cz + hz, c.z + c.sz / 2) - math.max(b.cz - hz, c.z - c.sz / 2)
			if ox > 0.5 and oz > 0.5 and lo < c.top - 0.5 and hi > c.base + 0.5 then
				return c
			end
		end
	end
	return nil
end
MapSites.inBuilding = inBuilding

-- The layout of a pocket played at its site on the map (nil when the layout has no site or no pocket)
function MapSites.layout(Config: any, world: any, name: string): Layout?
	local M = Config.MapSites
	local site = M and M.sites[name]
	if not site or not PocketLayout.known(name) then
		return nil
	end
	local pl = pocket(Config, name)
	local base = site.base or 0
	local lift = M.lift or 0.5
	local l: Layout = {
		index = 0,
		cx = site.x,
		cy = base,
		cz = site.z,
		boxes = {},
		points = {},
		lists = {},
		floorY = base,
		art = {},
	}
	local keep = site.keep or {}
	local kept: { [Box]: boolean } = {}
	if not site.permanent then
		for i, b in pl.boxes do
			if i > SHELL and keep[b.kind] then
				local n = moved(site, pl, b, 0)
				-- a set piece stands on the street or paving where it lands
				-- a set piece the turn and scale put into a building slides toward the site's middle (a street or
				-- the plaza) until it is clear
				for _ = 1, 40 do
					if not inBuilding(world, n) then
						break
					end
					local dx, dz = site.x - n.cx, site.z - n.cz
					local d = math.sqrt(dx * dx + dz * dz)
					if d < 2 then
						break
					end
					n.cx += dx / d * 2
					n.cz += dz / d * 2
				end
				local h = HeightMap.at(world.heights, n.cx, n.cz)
				n.cy += if h <= 1.6 then math.max(h, 0) else 0
				table.insert(l.boxes, n)
				kept[b] = true
			end
		end
	end
	local perm = MapSites.permanent(Config).boxes
	-- where a ground point may not settle: the run's set pieces and this site's permanent piece
	local avoid: { Box } = table.clone(l.boxes)
	for _, b in perm do
		if (b :: any).site == name then
			table.insert(avoid, b)
		end
	end
	local roofFor: { [Box]: any } = {}
	local taken: { [any]: boolean } = {}
	local function onto(p: { number }): { number }
		local px, py, pz = p[1], p[2], p[3]
		local top, on = under(pl, px, py, pz)
		local off = math.max(0, py - top)
		local s = top - pl.floorY
		local wx, wz = place(site, px - pl.cx, pz - pl.cz)
		if site.permanent and on then
			local y = base + s + off
			local inside = false
			for _, b in avoid do
				if
					counts(b)
					and covers(b, wx, wz)
					and b.cy - b.sy / 2 < y - 0.4
					and b.cy + b.sy / 2 > y + 0.6
				then
					inside = true
				end
			end
			if not inside then
				return { wx, y, wz }
			end
		end
		if on and kept[on] then
			local h = HeightMap.at(world.heights, wx, wz)
			return { wx, (if h <= 1.6 then math.max(h, 0) else 0) + s + off, wz }
		end
		if on and s > 0.5 and not site.permanent then
			local b = roofFor[on]
			if not b then
				b = roofNear(Config, world, wx, wz, taken)
				if b then
					roofFor[on] = b
					taken[b] = true
				end
			end
			if b then
				local rx, rz = roofSpot(b, wx, wz)
				return { rx, HeightMap.at(world.heights, rx, rz) + math.max(off, 1), rz }
			end
		end
		if (not on or s <= 0.5) and off > 4 and not site.permanent then
			-- a hop the pocket had in the air between its roofs: onto the nearest real roof (shared, any roof)
			local b = roofNear(Config, world, wx, wz, {})
			if b then
				local rx, rz = roofSpot(b, wx, wz)
				return { rx, HeightMap.at(world.heights, rx, rz) + 1, rz }
			end
		end
		local gx, gh, gz = settle(Config, world, wx, wz, avoid)
		if gx and gh and gz then
			return { gx, gh + lift + off, gz }
		end
		return { wx, base + lift + off, wz }
	end
	local at = site.at or {}
	for key, p0 in pl.points do
		-- `at`: a point the site puts somewhere else in the pocket's own studs (Most Wanted's tram on the street)
		local p = if at[key] then { at[key][1], p0[2], at[key][2] } else p0
		if key == "trainDir" then
			-- a direction (x, z) and a length, not a place: turned, the length scaled along it
			local c, s = turn(site)
			local dx, dz = p[1], p[2]
			local len = p[3] * (math.abs(dx) * (site.sx or 1) + math.abs(dz) * (site.sz or 1))
			l.points[key] = { dx * c + dz * s, -dx * s + dz * c, len }
		else
			l.points[key] = onto(p)
		end
	end
	for key, list in pl.lists do
		local out = {}
		for _, p in list do
			table.insert(out, onto(p))
		end
		l.lists[key] = out
	end
	-- the site's reach (for its own heights): its points and boxes, with a margin
	local x0, x1, z0, z1 = site.x, site.x, site.z, site.z
	local function grow(x: number, z: number, r: number)
		x0, x1, z0, z1 = math.min(x0, x - r), math.max(x1, x + r), math.min(z0, z - r), math.max(z1, z + r)
	end
	for _, b in l.boxes do
		grow(b.cx, b.cz, math.max(b.sx, b.sz) / 2 + 10)
	end
	for _, b in perm do
		if (b :: any).site == name then
			grow(b.cx, b.cz, math.max(b.sx, b.sz) / 2 + 10)
		end
	end
	for _, p in l.points do
		grow(p[1], p[3], 10)
	end
	local L: any = l
	L.onMap = true
	L.site = name
	L.bounds = { x0, x1, z0, z1 }
	return l
end

-- What a map point stands on, for the tests: the surface height under (x, z) at or below its feet, or nil and why
-- ("inside" a building or piece, "water"). Exact footprints: the city's buildings (body to roof), the permanent
-- pieces and the run's own set pieces; the city's 10-stud height map only where none of those covers the point (a
-- prop, a kerb, a rooftop tank).
function MapSites.standing(
	Config: any,
	world: any,
	l: Layout,
	x: number,
	y: number,
	z: number
): (number?, string?)
	local top: number? = nil
	local function seen(t: number)
		if t <= y + 0.6 and (not top or t > top) then
			top = t
		end
	end
	for _, b in world.buildings do
		if not b.site and math.abs(x - b.x) <= b.sx / 2 and math.abs(z - b.z) <= b.sz / 2 then
			if b.base < y - 0.4 and (b.peak or b.top) > y + 0.6 and b.top > y + 0.6 then
				return nil, "inside"
			end
			seen(b.top)
		end
	end
	for _, list in { l.boxes, MapSites.permanent(Config).boxes } do
		for _, b in list do
			if counts(b) and covers(b, x, z) then
				local lo, hi = b.cy - b.sy / 2, b.cy + b.sy / 2
				if lo < y - 0.4 and hi > y + 0.6 then
					return nil, "inside"
				end
				seen(hi)
			end
		end
	end
	local h = HeightMap.at(world.heights, x, z)
	if h <= y + 0.6 then
		seen(h)
	end
	if not top then
		seen(0)
	end
	local t = top :: number
	if t <= 1.6 and inBasin(Config, x, z) then
		return nil, "water"
	end
	if t < -0.5 then
		return nil, "water"
	end
	return t, nil
end

return MapSites
