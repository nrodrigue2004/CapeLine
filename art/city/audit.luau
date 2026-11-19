-- audit.luau: what the player sees in the open city, counted by kind and district (the living-world pass,
-- 2026-11-19, nate: "you still use way too many simple shapes and textures"). The city is not in the built place
-- (CityBuilder builds it on the server at boot, CityProps the street props on each device), so this counts the
-- same data CityBuilder builds from (WorldMap.build, seed 202647) the way CityBuilder draws each box:
--   mesh: built as Blender meshes (Art.Street via `art`, Art.Life via `look`, street props, vehicles)
--   texture: a box in a city kit MaterialVariant (a textured box)
--   plain: a plain coloured box, ball, cylinder or wedge
-- "before" is the city without the living world's looks (look boxes counted as the boxes they were); "after" with
-- them. Writes art/preview/city_audit.txt.  Run: lune run art/city/audit.luau
local fs = require("@lune/fs")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")
local LifePlan = require("../../src/shared/LifePlan")
local LifeKit = require("../../src/shared/LifeKit")
local Vehicles = require("../../src/shared/Vehicles")

local world = WorldMap.build(Config, 202647, { props = true })
local K = Config.City.kit

local function category(b: any): string
	local look = b.look and LifeKit.lookOf(Config, b)
	if b.art and type(b.art) == "table" then
		local n = b.art.name
		if n == "Awning" or n == "ShopFront" then
			return "storefronts (awnings, shops)"
		elseif n == "Perch" then
			return "tower perches"
		end
		return "roof clutter (tanks, AC, vents, antennas, billboards)"
	end
	if look == "TreeTrunk" or look == "CanopyRound" or look == "CanopyTall" or look == "CanopyPine" then
		return "trees"
	elseif look == "Picket" then
		return "fences"
	elseif look == "CropRow" or look == "CornRow" then
		return "crops"
	elseif look == "HayBale" or look == "SiloBody" or look == "SiloDome" then
		return "farm props (hay, silos)"
	elseif look == "HouseDoor" then
		return "house doors"
	end
	local k = b.kind
	if k == "building" or k == "tier" or k == "beacon" then
		return "building bodies"
	elseif k == "band" then
		return "window bands"
	elseif k == "roof" or (k == "ledge" and (b.color == "roof" or b.color == "cornice")) then
		return "roofs and cornices"
	elseif k == "road" or k == "sidewalk" or k == "plaza" or k == "mark" or k == "field" or k == "ground" then
		return "ground (roads, walks, fields)"
	elseif k == "crop" then
		return "crops"
	elseif b.color == "leaf" then
		return "trees"
	elseif b.color == "white" and math.min(b.sx, b.sz) <= 1 and b.sy <= 3.5 then
		return "fences"
	end
	return "other props (containers, rocks, posts, glows)"
end

local function status(b: any, after: boolean): string
	if b.art and type(b.art) == "table" then
		return "mesh"
	end
	if after and b.look and b.look ~= "Picket" then
		return "mesh"
	end
	if after and b.look == "Picket" then
		return "texture"
	end
	if b.kit and (after or b.kit ~= "Tilled") then
		return "texture" -- (the fields' tilled soil is the living world's too)
	end
	return "plain"
end

local rows: { [string]: { [string]: { [string]: number } } } = {}
local function add(cat: string, district: string, st: string, n: number)
	local key = cat .. "|" .. district
	rows[key] = rows[key] or { before = {}, after = {} }
	return rows[key]
end
local function count(b: any)
	if b.plain and b.kit == nil and K.studsPerTile[b.plain] then
		return -- a window band its building's kit front replaces (skipPlain)
	end
	local d = LifePlan.districtAt(Config, b.cx, b.cz)
	local r = add(category(b), d, "", 0)
	local s0, s1 = status(b, false), status(b, true)
	if not (b.art and type(b.art) == "table" and b.art.name == "ShopFront") then -- the shops are new
		r.before[s0] = (r.before[s0] or 0) + 1
	end
	r.after[s1] = (r.after[s1] or 0) + 1
end
for _, b in world.hubBoxes do
	count(b)
end
for _, p in world.tilePlans do
	for _, b in p.boxes do
		count(b)
	end
end
for _, lm in world.landmarks do
	for _, b in lm.boxes do
		local r = add("landmarks", "Outskirts", "", 0)
		local s = status(b, false)
		r.before[s] = (r.before[s] or 0) + 1
		r.after[s] = (r.after[s] or 0) + 1
	end
end
for _, p in world.props do
	local r = add("street furniture (device props)", LifePlan.districtAt(Config, p.x, p.z), "", 0)
	r.before.mesh = (r.before.mesh or 0) + (if p.name == "VendingMachine" then 0 else 1)
	r.after.mesh = (r.after.mesh or 0) + 1
end
for _, v in Vehicles.place(Config) do
	local r = add("parked vehicles", v.district, "", 0)
	r.before.mesh = (r.before.mesh or 0) + 1
	r.after.mesh = (r.after.mesh or 0) + 1
end

local keys = {}
for k in rows do
	table.insert(keys, k)
end
table.sort(keys, function(a, b)
	local pa = (rows[a].before.plain or 0)
	local pb = (rows[b].before.plain or 0)
	if pa ~= pb then
		return pa > pb
	end
	return a < b
end)
local lines = {
	"City audit (art/city/audit.luau, seed 202647, " .. os.date("!%Y-%m-%d") .. "): what the player sees, by kind and district.",
	"mesh = Blender meshes; texture = a box in a kit MaterialVariant; plain = a plain coloured shape.",
	"before = without the living world's looks, after = with them (Art.Life). Biggest plain groups first.",
	"",
	string.format("%-52s %-10s %22s   %22s", "kind", "district", "before plain/tex/mesh", "after plain/tex/mesh"),
}
local tot = { before = { plain = 0, texture = 0, mesh = 0 }, after = { plain = 0, texture = 0, mesh = 0 } }
for _, k in keys do
	local r = rows[k]
	local cat, d = string.match(k, "^(.-)|(.*)$")
	for _, w in { "before", "after" } do
		for _, s in { "plain", "texture", "mesh" } do
			tot[w][s] += r[w][s] or 0
		end
	end
	table.insert(
		lines,
		string.format(
			"%-52s %-10s %6d %6d %6d     %6d %6d %6d",
			cat,
			d,
			r.before.plain or 0,
			r.before.texture or 0,
			r.before.mesh or 0,
			r.after.plain or 0,
			r.after.texture or 0,
			r.after.mesh or 0
		)
	)
end
table.insert(lines, "")
table.insert(
	lines,
	string.format(
		"%-63s %6d %6d %6d     %6d %6d %6d",
		"total",
		tot.before.plain,
		tot.before.texture,
		tot.before.mesh,
		tot.after.plain,
		tot.after.texture,
		tot.after.mesh
	)
)
fs.writeFile("art/preview/city_audit.txt", table.concat(lines, "\n") .. "\n")
print(table.concat(lines, "\n"))
