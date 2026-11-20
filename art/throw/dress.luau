-- Writes art/export/throw_dress.json from Config.Throw (the throwables' part builds) for art/blender/throwables.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local T = require("../../src/config/Throw")
local out = {}
for kind, d in T.dress do
	if d.parts then
		out[kind] = { box = T.kinds[kind].size, color = T.kinds[kind].color, parts = d.parts }
	end
end
fs.writeFile("art/export/throw_dress.json", serde.encode("json", out, true))
