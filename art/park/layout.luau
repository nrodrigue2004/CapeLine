-- layout.luau: the city park as the game lays it out (Shared.ParkLayout through WorldMap.build), written as JSON for
-- art/blender/park_preview.py: the Terrain (as slabs of each column run's top and material), the hub boxes (avenue,
-- paths, rounds, trees), every Art.Park piece, the street props with their Art.Street pieces, and the city's
-- buildings round the park (plain blocks) so the skyline views show both districts.
-- Run: lune run art/park/layout.luau   (writes art/park/layout.json; prints the park's counts)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")
local ParkLayout = require("../../src/shared/ParkLayout")

local world = WorldMap.build(Config, 202647)
local park = world.park
local P = Config.Park
local out = { bounds = P.bounds, green = park.green, terrain = {}, boxes = {}, meshes = {}, props = {}, city = {}, views = {} }

-- Terrain: 8-stud cells, merged along x while the top and material stay the same
local g = park.green
local cell = 8
for z = g.z0, g.z1 - cell, cell do
	local run: any = nil
	local function flush()
		if run then
			local top = run.top
			table.insert(out.terrain, {
				shape = "block",
				material = run.mat,
				cx = (run.x0 + run.x1) / 2,
				cy = (top - 6) / 2,
				cz = z + cell / 2,
				sx = run.x1 - run.x0,
				sy = top + 6,
				sz = cell,
			})
			if run.water then
				table.insert(out.terrain, {
					shape = "block",
					material = "water",
					cx = (run.x0 + run.x1) / 2,
					cy = (run.water + top) / 2,
					cz = z + cell / 2,
					sx = run.x1 - run.x0,
					sy = run.water - top,
					sz = cell,
				})
			end
		end
		run = nil
	end
	for x = g.x0, g.x1 - cell, cell do
		local top, mat, water = ParkLayout.column(park, x + cell / 2, z + cell / 2)
		if mat == "grass" and top <= 0.01 then
			mat = ParkLayout.floor(P, x + cell / 2, z + cell / 2)
		end
		top = math.floor(top * 2 + 0.5) / 2
		if run and run.top == top and run.mat == mat and run.water == water then
			run.x1 = x + cell
		else
			flush()
			run = { x0 = x, x1 = x + cell, top = top, mat = mat, water = water }
		end
	end
	flush()
end
for _, b in park.boxes do
	local leaf = nil
	if b.look == "Canopy" then
		leaf = Config.Life.leaves[(math.floor(b.cx * 7 + b.cz * 13) % #Config.Life.leaves) + 1]
	end
	table.insert(out.boxes, {
		kind = b.kind,
		cx = b.cx,
		cy = b.cy,
		cz = b.cz,
		sx = b.sx,
		sy = b.sy,
		sz = b.sz,
		ry = b.ry or 0,
		color = b.color,
		shape = b.shape,
		kit = b.kit,
		look = b.look,
		leaf = leaf,
	})
end
for _, m in park.meshes do
	table.insert(out.meshes, { name = m.name, x = m.x, y = m.y, z = m.z, ry = m.ry, size = m.size, color = m.color })
end
for _, p in park.props do
	local pieces = {}
	for piece, fit in Config.StreetArt[p.name] or {} do
		if Config.City.kit.props[p.name] and Config.City.kit.props[p.name].pieces[piece] then
			pieces[piece] = fit
		end
	end
	table.insert(out.props, { name = p.name, x = p.x, y = p.y, z = p.z, ry = p.ry, pieces = pieces })
end
-- the buildings within 420 studs of the park (their bodies; towers show the skyline)
local b = P.bounds
for _, bd in world.buildings do
	if bd.x > b.minX - 420 and bd.x < b.maxX + 300 and bd.z > b.minZ - 420 and bd.z < b.maxZ + 420 then
		local h = bd.top - bd.base
		local shade = if bd.district == "Uptown" then { 214, 150, 120 } else { 150, 158, 172 }
		table.insert(out.city, {
			cx = bd.x,
			cy = bd.base + h / 2,
			cz = bd.z,
			sx = bd.sx,
			sy = h,
			sz = bd.sz,
			rgb = shade,
		})
	end
end
-- street views: from the Mall's gate north, across the lake to Uptown, from the Bow Bridge, the reservoir looking
-- south to Downtown, and from a rock by the Great Lawn
out.views = {
	mall = { { -590, 7, -506 }, { -590, 10, -650 } },
	lake = { { -560, 8, -652 }, { -660, 30, -900 } },
	bow = { { -640, 12, -700 }, { -760, 10, -760 } },
	reservoir = { { -470, 8, -1070 }, { -470, 40, -700 } },
	lawn = { { -330, 14, -740 }, { -150, 20, -820 } },
	carousel = { { -790, 10, -560 }, { -820, 8, -600 } },
}
fs.writeFile("art/park/layout.json", serde.encode("json", out))
local counts = { trees = #park.trees, props = #park.props, meshes = #park.meshes, solid = #park.solid, boxes = #park.boxes }
local names = {}
for _, p in park.props do
	names[p.name] = (names[p.name] or 0) + 1
end
print(serde.encode("json", counts), serde.encode("json", names), #out.terrain, "terrain slabs")
print("spots:", #park.spots.picnics, "picnics", #park.spots.buskers, "buskers", #park.spots.boats, "boats", #park.spots.ducks, "ducks", #park.spots.carts, "carts")
