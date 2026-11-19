-- Writes art/export/deep/layout.json for art/blender/deep.py's previews: the Deep's boxes (with the look that
-- hides each), the art placements and the Terrain fills, from the game's own data (Shared.DeepLayout).
--   lune run art/deep/layout.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local DeepLayout = require("../../src/shared/DeepLayout")

local lay = DeepLayout.build(Config)
local pal = Config.City.palette
local out = { boxes = {}, art = {}, terrain = {}, waterY = Config.World.coast.waterY }
for _, b in lay.boxes do
	table.insert(out.boxes, {
		kind = b.kind,
		at = { b.cx, b.cy, b.cz },
		size = { b.sx, b.sy, b.sz },
		shape = b.shape,
		ry = b.ry or 0,
		color = pal[b.color] or { 200, 200, 200 },
		art = (b :: any).art,
	})
end
for _, p in lay.art do
	table.insert(out.art, {
		look = p.look,
		at = { p.cx, p.cy, p.cz },
		size = { p.sx, p.sy, p.sz },
		ry = p.ry or 0,
		tint = if p.tint then pal[p.tint] else nil,
	})
end
for _, f in lay.terrain do
	table.insert(out.terrain, { material = f.material, at = { f.cx, f.cy, f.cz }, size = { f.sx, f.sy, f.sz } })
end
fs.writeDir("art/export/deep")
fs.writeFile("art/export/deep/layout.json", serde.encode("json", out))
print("deep layout:", #out.boxes, "boxes,", #out.art, "placements,", #out.terrain, "fills")
