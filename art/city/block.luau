-- block.luau: writes the city kit block (Config.City.kit) as JSON for art/blender/block.py's preview, straight
-- from the game's own Downtown layout, so the render is the block players see.
-- Run: lune run art/city/block.luau   (writes art/export/city/block.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local CityLayout = require("../../src/shared/CityLayout")

local layout = CityLayout.downtown(Config.City, Config.World)
local t = Config.City.downtown
local d = Config.City.districts.Downtown
local pitch = t.block + t.street
local nx = math.floor((d.maxX - d.minX) / pitch)
local nz = math.floor((d.maxZ - d.minZ) / pitch)
local o = Config.City.kit.blocks[1]
local bx, bz = math.ceil(nx / 2) + o[1], math.ceil(nz / 2) + o[2]
local minX = d.minX + t.street / 2 + (bx - 1) * pitch
local minZ = d.minZ + t.street / 2 + (bz - 1) * pitch
local pad = t.street + 40
local out = { block = { minX = minX, minZ = minZ, size = t.block, street = t.street }, boxes = {}, props = {} }
for _, b in layout.boxes do
	local inside = b.cx > minX - pad and b.cx < minX + t.block + pad and b.cz > minZ - pad and b.cz < minZ + t.block + pad
	if inside and b.kind ~= "road" and not b.plain then
		table.insert(out.boxes, b)
	end
end
for _, p in layout.props do
	table.insert(out.props, p)
end
fs.writeFile("art/export/city/block.json", serde.encode("json", out))
print(#out.boxes, "boxes", #out.props, "props")
