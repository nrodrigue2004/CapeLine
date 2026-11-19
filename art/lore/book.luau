-- art/lore/book.luau: writes the lore book and the Lore Shelf (Shared.LoreBookKit) as JSON for the Blender
-- preview (art/blender/lorebook.py), so the preview shows exactly what the device builds.
--   lune run art/lore/book.luau   -> art/export/lore/book.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local LoreBookKit = require("../../src/shared/LoreBookKit")

local L = Config.Lore
local districts = {}
for _, d in L.districts do
	table.insert(districts, d.id)
end
local have = { Downtown = true, Crater = true, Docks = true }
local colors = {}
for _, d in districts do
	colors[d] = LoreBookKit.colors(L.look, d)
end
fs.writeDir("art/export/lore")
fs.writeFile(
	"art/export/lore/book.json",
	serde.encode("json", {
		book = LoreBookKit.book(),
		shelf = LoreBookKit.shelf(districts, have),
		colors = colors,
		show = { "Crater", "Downtown", "Farmland" },
	}, true)
)
print("wrote art/export/lore/book.json")
