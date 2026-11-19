-- layout.luau: writes the fixed city (the hub and Uptown, which never change with the weekly seed) as top-down
-- plan data for art/map/draw.py, straight from the game's own layout (WorldMap.build, Shared.MapPlan.cityBoxes),
-- so the map screen's pictures are the streets and buildings players fly over (the map pass, 2026-11-19).
-- Run: lune run art/map/layout.luau   (writes art/export/map/city.json), then python3 art/map/draw.py; put the
-- printed box count in Config.MapArt.boxes after re-uploading the pictures.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")
local MapPlan = require("../../src/shared/MapPlan")

local C = Config.City
-- the hub and Uptown are fixed, so any seed draws the same picture (tests check two seeds agree)
local world = WorldMap.build(Config, 202647)
local boxes = MapPlan.cityBoxes(C, Config.World, world)
local palette = {}
for k, v in C.palette do
	palette[k] = v
end
fs.writeDir("art/export/map")
fs.writeFile(
	"art/export/map/city.json",
	serde.encode("json", {
		regions = MapPlan.cityImages(C),
		ground = C.ground.y,
		palette = palette,
		boxes = boxes,
	})
)
print(string.format("city.json: %d boxes", #boxes))
