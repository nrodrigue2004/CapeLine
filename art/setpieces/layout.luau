-- layout.luau: writes the side quests' set pieces as JSON for art/blender/setpieces.py's preview, straight from
-- the game's own data (Shared.SideQuestSets, Shared.PocketLayout, Shared.SetPieceKit), so the render shows each
-- look where the game puts it, over the boxes it hides, with the boxes it keeps.
-- Run: lune run art/setpieces/layout.luau   (writes art/export/setpieces/layout.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local SideQuestSets = require("../../src/shared/SideQuestSets")
local PocketLayout = require("../../src/shared/PocketLayout")
local SetPieceKit = require("../../src/shared/SetPieceKit")

local P = Config.City.palette
-- the pocket parts' materials (CityBuilder's MATERIAL by kind)
local KIND_MAT = { glow = "Neon", plaza = "Pavement", rock = "Slate", sand = "Sand" }

local out = { groups = {} }

-- one group: its boxes and looks in its own studs (from its origin)
local function group(name: string, boxes: { any }, places: { any }, ox: number, oy: number, oz: number, pocket: boolean)
	local g = { name = name, boxes = {}, art = {} }
	for _, b in boxes do
		local row: { [string]: any } = {}
		if pocket then
			row.at = { b.cx - ox, b.cy - oy, b.cz - oz }
			row.size = { b.sx, b.sy, b.sz }
			row.color = P[b.color] or { 200, 0, 200 }
			row.mat = KIND_MAT[b.kind] or "SmoothPlastic"
			-- BoxKit: a cylinder stands sy tall, sx across; a ball is its largest side
			row.shape = b.shape
			row.alpha = if b.kind == "water" or b.kind == "sea" then 0.1 elseif b.tag == "pocketWall" then 0.85 else 0
			row.tag = b.tag
		else
			row.at = { b.x, b.y, b.z }
			-- SideQuestSets: an upright cylinder stands sx tall
			row.size = if b.upright then { b.sy, b.sx, b.sz } else { b.sx, b.sy, b.sz }
			row.color = b.color
			row.mat = b.mat or "SmoothPlastic"
			row.shape = b.shape
			row.alpha = b.alpha or 0
			row.tilt = b.tilt
			row.sign = b.sign
		end
		row.art = b.art
		table.insert(g.boxes, row)
	end
	for _, pl in places do
		table.insert(g.art, {
			look = pl.look,
			at = { pl.x - ox, pl.y - oy, pl.z - oz },
			ry = pl.ry or 0,
			tint = pl.tint,
		})
	end
	table.insert(out.groups, g)
end

for _, id in { "gala", "meet" } do
	local s = SideQuestSets.build(id)
	group(id, s.boxes, s.art, 0, 0, 0, false)
end
for _, id in { "toyshop", "seacave", "velmara", "pit" } do
	local l = PocketLayout.build(Config, 1, id)
	group(id, l.boxes, l.art, l.cx, l.cy, l.cz, true)
end
-- the farm folk's truck (SideQuestService's motorcade box under its look)
group("farm", {
	{ x = 0, y = 2.5, z = 0, sx = 7, sy = 4, sz = 14, color = { 30, 30, 40 }, art = 1 },
	{ x = 0, y = 5.6, z = -2, sx = 6.6, sy = 2.4, sz = 6, color = { 90, 70, 160 }, art = 1 },
}, { { look = SetPieceKit.truck("HarvestKing"), x = 0, y = 0, z = 0 } }, 0, 0, 0, false)

fs.writeDir("art/export/setpieces")
fs.writeFile("art/export/setpieces/layout.json", serde.encode("json", out))
print("set pieces:", #out.groups, "groups")
