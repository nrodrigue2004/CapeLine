-- Writes the effects config every path preview needs to art/export/fx/paths.json (overhaul plan step 6), for
-- art/fx/paths.py to draw art/preview/fx_paths.png. Run from the repo root:  lune run art/fx/paths.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../../src/config")
local F = Config.Fx
local L = F.lib

local out = { paths = {}, kinds = {}, elements = L.elements, order = {} }
for set in Config.Abilities.setColor do
	table.insert(out.order, set)
end
table.sort(out.order)
for _, set in out.order do
	local p = F.paths[set]
	local super
	for _, row in Config.Abilities.list do
		if row.set == set and row.slot == "super" then
			super = row.name
		end
	end
	out.paths[set] = {
		color = Config.Abilities.setColor[set],
		accent = p.accent,
		tint = p.super.tint,
		element = L.setElement[set],
		head = p.head,
		mark = p.mark,
		cast = p.cast,
		piece = p.piece,
		super = p.super.look,
		superName = super,
		words = F.words[set],
	}
end
for name, k in L.kinds do
	out.kinds[name] = { file = L.textures[k.tex].file, light = k.light, size = k.size, face = k.face }
end
fs.writeFile("art/export/fx/paths.json", serde.encode("json", out, true))
print("wrote art/export/fx/paths.json")
