-- layout.luau: writes the hub's 40 vehicles as JSON for art/blender/vehicles.py's street preview, straight from the
-- game's own data (Shared.Vehicles places them, Shared.VehicleKit picks each one's look and paint), so the render
-- shows each look where the game parks it, in its own paint, beside today's parts.
-- Run: lune run art/vehicles/layout.luau   (writes art/export/vehicles/layout.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local Vehicles = require("../../src/shared/Vehicles")
local VehicleKit = require("../../src/shared/VehicleKit")

local P = Config.City.palette
local out = { vehicles = {} }
for _, v in Vehicles.place(Config) do
	local pl = VehicleKit.place(Config, v)
	table.insert(out.vehicles, {
		id = v.id,
		kind = v.kind,
		district = v.district,
		look = pl.look,
		at = { v.x, v.y, v.z },
		ry = v.ry,
		size = { v.sx, v.sy, v.sz },
		paint = P[v.color] or { 200, 200, 200 }, -- today's part colour
		tint = pl.tint,
	})
end
if not fs.isDir("art/export/vehicles") then
	fs.writeDir("art/export/vehicles")
end
fs.writeFile("art/export/vehicles/layout.json", serde.encode("json", out))
print("wrote art/export/vehicles/layout.json: " .. #out.vehicles .. " vehicles")
