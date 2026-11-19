-- The destruction preview's data (fix-destroy, 2026-11-19): a silo's Structure pieces as the game builds them
-- (intact body, after a super, its fall mid-way, the rubble heap) and two ground craters (a part crater on a road:
-- CraterRules.rim; a terrain crater: CraterRules.carve on a sand seabed), written to art/export/destroy/frames.json
-- for art/blender/destroy_preview.py.   lune run art/destroy/frames.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")
local BuildingState = require("../../src/shared/BuildingState")
local Structure = require("../../src/shared/Structure")
local Chunker = require("../../src/shared/Chunker")
local CraterRules = require("../../src/shared/CraterRules")

local D = Config.Destruction
local world = WorldMap.build(Config, 202647)
local silo
for _, b in world.buildings do
	if b.round and b.district == "Outskirts" and b.top - b.base > 30 and b.top - b.base < 40 then
		silo = b
		break
	end
end
assert(silo, "a silo")
local function pieceRows(grid, gone, drop)
	local out = {}
	for i, p in grid.pieces do
		if not gone[i] then
			local dy = 0
			if drop then
				dy = drop(p)
			end
			table.insert(out, {
				kind = p.kind,
				x = p.cx - silo.x,
				y = p.cy - silo.base - dy,
				z = p.cz - silo.z,
				w = p.dw or p.sx,
				h = p.sy,
				d = p.dd or p.sz,
				ry = p.ry or 0,
				disc = p.disc == true,
				tilt = if drop then (i % 5 - 2) * 6 else 0,
			})
		end
	end
	return out
end
local book = BuildingState.new(D, world.buildings)
local grid = BuildingState.grid(D, book, silo.id)
local r1 = BuildingState.blast(D, book, silo.id, silo.x, silo.base + 14, silo.z - silo.sx / 2, 10, D.superStruct, 0)
local holed = pieceRows(grid, table.clone(book.gone[silo.id] or {}))
-- a second super at the foot: the ground storey gives way (the pancake fall mid-way)
local r2 = BuildingState.blast(D, book, silo.id, silo.x, silo.base + 3, silo.z - silo.sx / 2, 10, D.superStruct, 1)
local before = {}
for i in grid.pieces do
	before[i] = false
end
local falling = pieceRows(grid, {}, function(p)
	return (p.storey - 1) * grid.storeyH * 0.55 + 2
end)
local rubble = {}
for _, r in Chunker.rubble(D, silo, silo.id) do
	table.insert(rubble, {
		x = r.cx - silo.x,
		y = r.cy - silo.base,
		z = r.cz - silo.z,
		w = r.sx,
		h = r.sy,
		d = r.sz,
		rx = r.rx,
		ry = r.ry,
		rz = r.rz,
	})
end
-- the ground craters
local G = D.ground
local part: CraterRules.Crater = { id = 3, x = 0, y = 0, z = 0, r = CraterRules.radiusFor(G, D.superStruct), ground = "part", born = 0 }
local rim = CraterRules.rim(part, 14)
local terr: CraterRules.Crater = { id = 4, x = 0, y = 0, z = 0, r = CraterRules.radiusFor(G, 4000), ground = "terrain", born = 0 }
local lo, hi = CraterRules.region(G, terr)
-- widen the read so the picture shows the flat seabed round it
local v = G.voxel
lo = { lo[1] - 12, lo[2], lo[3] - 12 }
hi = { hi[1] + 12, hi[2], hi[3] + 12 }
local mats, occ = {}, {}
for i = 1, (hi[1] - lo[1]) / v do
	mats[i], occ[i] = {}, {}
	for j = 1, (hi[2] - lo[2]) / v do
		mats[i][j], occ[i][j] = {}, {}
		for k = 1, (hi[3] - lo[3]) / v do
			local y = lo[2] + (j - 0.5) * v
			mats[i][j][k] = if y < 0 then "Sand" else "Air"
			occ[i][j][k] = if y < 0 then 1 else 0
		end
	end
end
local dug = CraterRules.carve(G, terr, lo, mats, occ, -100)
local voxels = {}
for i, plane in mats do
	for j, row in plane do
		for k, m in row do
			if m == "Sand" and occ[i][j][k] > 0.05 then
				table.insert(voxels, {
					x = lo[1] + (i - 0.5) * v,
					y = lo[2] + (j - 0.5) * v,
					z = lo[3] + (k - 0.5) * v,
					o = occ[i][j][k],
				})
			end
		end
	end
end
fs.writeDir("art/export/destroy")
fs.writeFile(
	"art/export/destroy/frames.json",
	serde.encode("json", {
		silo = { r = silo.sx / 2, h = silo.top - silo.base, cap = silo.sx },
		intact = pieceRows(grid, {}),
		holed = holed,
		falling = falling,
		rubble = rubble,
		crater = { r = part.r, rim = rim },
		terrain = { r = terr.r, voxel = v, voxels = voxels, dug = dug },
		hits = { #r1.hit, #r2.hit, r2.state },
	})
)
print(string.format("silo %d pieces, super 1 knocked %d, super 2 %d (state %d); crater r %.1f; terrain r %.1f dug %d voxels", #grid.pieces, #r1.hit, #r2.hit, r2.state, part.r, terr.r, dug))
