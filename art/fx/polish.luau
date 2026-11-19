-- The gap polish pieces' geometry for art/fx/polish.py's preview (2026-11-19): the Snow Wall slab with its
-- shards per preset, the crate's planks, the smoke cloud's puff spots and the shield drone's orbit, all from
-- Shared.PolishPlan and Config, so the preview draws exactly what the game builds.
--   lune run art/fx/polish.luau && python3 art/fx/polish.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local PolishPlan = require("../../src/shared/PolishPlan")

local P = Config.Fx.polish
local out = { shards = {}, crate = PolishPlan.crateBoxes(4, 3, 4), smoke = {}, drone = {}, ice = P.ice }
for _, name in Config.Presets.order do
	out.shards[name] = PolishPlan.wallShards(6.5, 8, 1.6, P.presets[name].shards, 5)
	out.smoke[name] = PolishPlan.smokeSpots(P.presets[name].smoke, Config.Gear.gadgets.SmokeBomb.radius * 0.85, 42)
end
for i = 0, 40 do
	local x, y, z = PolishPlan.droneAt(i / 40 / P.drone.spin, P.drone.radius, P.drone.height, P.drone.spin)
	table.insert(out.drone, { x, y, z })
end
out.radius = Config.Gear.gadgets.SmokeBomb.radius
out.bubble = P.drone.bubble
fs.writeFile("art/export/fx/polish.json", serde.encode("json", out))
print("wrote art/export/fx/polish.json")
