-- block.luau: writes a piece of the dressed city (Config.City.kit) as JSON for art/blender/block.py's preview,
-- straight from the game's own layout (WorldMap.build), so the render is what players see once nate has
-- uploaded the textures and imported Art.Street.
-- Run: lune run art/city/block.luau [area]   (area: Downtown (default, the kit's preview block), Docks, OldTown,
-- Suburbs; writes art/export/city/<area>.json, Downtown as block.json)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")

local area = process.args[1] or "Downtown"
local world = WorldMap.build(Config, 202647, { props = true })
local C = Config.City
local gy = C.ground.y

-- each area: the window (x0, z0, x1, z1) and the cameras (from, to, lens) in Roblox (x, y, z)
local t = C.downtown
local d = C.districts.Downtown
local pitch = t.block + t.street
local nx = math.floor((d.maxX - d.minX) / pitch)
local nz = math.floor((d.maxZ - d.minZ) / pitch)
local o = C.kit.previewBlock
local bx, bz = math.ceil(nx / 2) + o[1], math.ceil(nz / 2) + o[2]
local minX = d.minX + t.street / 2 + (bx - 1) * pitch
local minZ = d.minZ + t.street / 2 + (bz - 1) * pitch
local b = C.docks.basin
local AREAS = {
	Downtown = {
		window = { minX - 180, minZ - 180, minX + t.block + 180, minZ + t.block + 180 },
		cams = {
			street = {
				{ minX - t.street * 0.35, gy + 6.5, minZ - t.street * 0.55 },
				{ minX + t.block * 0.55, gy + 22, minZ + 6 },
				24,
			},
			air = {
				{ minX + t.block * 0.5 - 260, gy + 400, minZ - 280 },
				{ minX + t.block * 0.5, gy + 10, minZ + t.block * 0.5 },
				30,
			},
		},
		file = "block",
	},
	Docks = {
		window = { 250, 380, 640, 800 },
		cams = {
			street = { { 437, gy + 6, 592 }, { 330, gy + 14, 546 }, 22 },
			air = { { 520, gy + 80, 660 }, { 380, gy + 12, 545 }, 26 },
		},
	},
	OldTown = {
		window = { 100, -600, 450, -250 },
		cams = {
			street = { { 196, gy + 6, -553 }, { 300, gy + 15, -528 }, 22 },
			air = { { 160, gy + 170, -620 }, { 290, gy + 10, -440 }, 30 },
		},
	},
	Suburbs = {
		window = { -1400, -300, -900, 200 },
		cams = {
			street = { { -1142, gy + 6, -150 }, { -1185, gy + 9, -60 }, 22 },
			air = { { -1250, gy + 170, -260 }, { -1150, gy, -40 }, 30 },
		},
	},
}
local a = AREAS[area]
assert(a, "unknown area " .. area)
local w = a.window
local function inside(x: number, z: number, pad: number): boolean
	return x > w[1] - pad and x < w[3] + pad and z > w[2] - pad and z < w[4] + pad
end

local out = { area = area, window = w, cams = a.cams, boxes = {}, props = {}, ground = gy }
local function add(list: { any })
	for _, bx2 in list do
		if inside(bx2.cx, bx2.cz, math.max(bx2.sx, bx2.sz) / 2) and not (bx2.plain and bx2.kit == nil) then
			table.insert(out.boxes, bx2)
		end
	end
end
add(world.hubBoxes)
for _, plan in world.tilePlans do
	add(plan.boxes)
end
for _, bb in world.baseBoxes do
	if bb.kind == "road" and inside(bb.cx, bb.cz, math.max(bb.sx, bb.sz) / 2) then
		table.insert(out.boxes, bb)
	end
end
for _, p in world.props do
	if inside(p.x, p.z, 0) then
		table.insert(out.props, p)
	end
end
if area == "Docks" then
	out.water = { b.minX, b.minZ, b.maxX, b.maxZ }
end
-- what the render needs from Config: palette, prop looks, tinted fronts and tile sizes
out.palette = C.palette
out.looks = {}
for name, def in C.kit.props do
	out.looks[name] = def.pieces
end
out.tinted = {}
for name, v in C.kit.tinted do
	out.tinted[name] = v ~= nil
end
out.studsPerTile = C.kit.studsPerTile
fs.writeFile("art/export/city/" .. (a.file or area) .. ".json", serde.encode("json", out))
print(area, #out.boxes, "boxes", #out.props, "props")
