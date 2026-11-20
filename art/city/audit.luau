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
	if b.look == "CorniceRun" or b.look == "RoofEdge" or b.look == "Parapet" then
		return "roofs and cornices"
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
	if b.look and Config.ShapeArt[LifeKit.lookOf(Config, b) or ""] then
		return "mesh" -- round 2's looks (shapes-2: Art.Shapes; a roof cap keeps its box under its moulding)
	end
	if after and b.look and b.look ~= "Picket" then
		return "mesh"
	end
	if after and b.look == "Picket" then
		return "texture"
	end
	if b.decal or b.scar then
		return "texture" -- a road picture (shapes-2: zebra crossings, drains) or the Crater's burn scars (gap-fx3)
	end
	if after and type(b.art) == "string" then
		return "mesh" -- a landmark box an art set's look stands in for (the Crater's lab and relics: Art.Crater)
	end
	if after and b.mat then
		return "texture" -- a Roblox material (shapes-2: Radio Hill's grass steps)
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
		-- (glows are lights on purpose: the beacons' beams, the Foundry's and the Crater's glow)
		local r = add(if b.kind == "glow" then "landmark lights (glows)" else "landmarks", "Outskirts", "", 0)
		local s, s1 = status(b, false), status(b, true)
		r.before[s] = (r.before[s] or 0) + 1
		r.after[s1] = (r.after[s1] or 0) + 1
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
-- round 2 (shapes-2, 2026-11-19): "before" is round 1's result (the living world's "after", kept in
-- art/preview/city_audit_round1.txt), "after" is today's city with round 2's looks (Art.Shapes, the roads' kits)
local round1: { [string]: { number } } = {}
for _, line in string.split(fs.readFile("art/preview/city_audit_round1.txt"), "\n") do
	local cat, d, rest = string.match(line, "^(.-)%s+(%u%a+)%s+%d+%s+%d+%s+%d+%s+(%d+%s+%d+%s+%d+)%s*$")
	if cat and d ~= nil then
		local a, b2, c = string.match(rest, "(%d+)%s+(%d+)%s+(%d+)")
		round1[cat .. "|" .. d] = { tonumber(a) :: number, tonumber(b2) :: number, tonumber(c) :: number }
	end
end
for k, r in rows do
	local old = round1[k]
	r.before = if old then { plain = old[1], texture = old[2], mesh = old[3] } else {}
	round1[k] = nil
end
for k, old in round1 do
	rows[k] = { before = { plain = old[1], texture = old[2], mesh = old[3] }, after = {} }
end
local lines = {
	"City audit (art/city/audit.luau, seed 202647, " .. os.date("!%Y-%m-%d") .. "): what the player sees, by kind and district.",
	"mesh = Blender meshes; texture = a box in a kit MaterialVariant; plain = a plain coloured shape.",
	"before = round 1 (the living world, art/preview/city_audit_round1.txt), after = today: round 2 (shapes-2: Art.Shapes,",
	"the roads' and roofs' kit textures) and round 3 (alive-world: Art.Alive over the safehouses, the Docks' cranes, the",
	"Foundry's chimneys and Uptown's roof gardens). Biggest plain groups first.",
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
