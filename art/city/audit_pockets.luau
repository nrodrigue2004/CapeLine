-- audit_pockets.luau: what a player sees inside the mission and side quest pockets, counted the way the server
-- and devices draw them (alive-world, 2026-11-20, round 2 of nate's "too many simple shapes and untextured parts").
-- Each layout is built (PocketLayout.build), dressed (PocketDress.apply: kit textures, tints, materials) and its
-- prop looks found (PocketPropKit.places, every look counted as imported). Each layout box is then:
--   mesh: a Blender look stands over it (a PocketPropKit place, or a set piece: the box's `art`)
--   texture: a kit MaterialVariant or a Roblox material (PocketDress)
--   glow: a glow strip, neon or a light on purpose
--   plain: a plain coloured shape
-- The HQ rooms (the Vigil's Safehouse: HqRules.hideout pieces under HideoutKit.cell; the Syndicate's Foundry:
-- HideoutKit.foundryBoxes under HideoutKit.foundry, high preset) count a piece a module hides as mesh.
-- The underwater areas (DeepLayout.build) are counted the same way after the pockets (a box with `art`: a Deep look).
-- The biggest plain groups (layout, kind, colour, size) come first. Writes art/preview/pocket_audit.txt.
-- Run: lune run art/city/audit_pockets.luau
local fs = require("@lune/fs")
local Config = require("../../src/config")
local PocketLayout = require("../../src/shared/PocketLayout")
local PocketDress = require("../../src/shared/PocketDress")
local PocketPropKit = require("../../src/shared/PocketPropKit")
local DeepLayout = require("../../src/shared/DeepLayout")
local HqRules = require("../../src/shared/HqRules")
local HideoutKit = require("../../src/shared/HideoutKit")

local LAYOUTS = {
	"station",
	"tower",
	"rooftops",
	"dungeon",
	"arena",
	"bridge",
	"subway",
	"academy",
	"toyshop",
	"seacave",
	"velmara",
	"pit",
	"ashlab",
	"ironhall",
	"pound",
}

local function status(b: any, covered: boolean): string
	if covered or b.art then
		return "mesh"
	end
	if b.kind == "glow" or b.mat == "Neon" or b.color == "neon" then
		return "glow"
	end
	if b.kit or b.mat then
		return "texture"
	end
	return "plain"
end

local lines = {
	"Pocket audit (art/city/audit_pockets.luau, " .. os.date("!%Y-%m-%d") .. "): each pocket's layout boxes by how they show.",
	"",
	string.format("%-10s %6s %6s %6s %6s", "pocket", "plain", "tex", "mesh", "glow"),
}
local groups: { [string]: number } = {}
local totals = { plain = 0, texture = 0, mesh = 0, glow = 0 }
for _, layout in LAYOUTS do
	local l = PocketLayout.build(Config, 1, layout)
	local dress = PocketDress.apply(Config, l, layout)
	local covered: { [number]: boolean } = {}
	for _, p in PocketPropKit.places(Config, l, dress, layout) do
		if not p.dress then
			for _, i in p.boxes do
				covered[i] = true
			end
		end
	end
	local c = { plain = 0, texture = 0, mesh = 0, glow = 0 }
	for i, b in l.boxes do
		local s = status(b, covered[i] == true)
		c[s] += 1
		totals[s] += 1
		if s == "plain" then
			local key = string.format(
				"%-9s %-9s %-14s %s %dx%dx%d",
				layout,
				tostring(b.kind),
				tostring(b.color),
				tostring(b.shape or "box"),
				math.floor(b.sx + 0.5),
				math.floor(b.sy + 0.5),
				math.floor(b.sz + 0.5)
			)
			groups[key] = (groups[key] or 0) + 1
		end
	end
	table.insert(lines, string.format("%-10s %6d %6d %6d %6d", layout, c.plain, c.texture, c.mesh, c.glow))
end
table.insert(
	lines,
	string.format("%-10s %6d %6d %6d %6d", "total", totals.plain, totals.texture, totals.mesh, totals.glow)
)
-- the underwater areas: every box a Deep look stands in for is mesh
do
	local deep = DeepLayout.build(Config)
	local c = { plain = 0, texture = 0, mesh = 0, glow = 0 }
	for _, b in deep.boxes do
		local s = status(b, false)
		c[s] += 1
		if s == "plain" then
			local key = string.format(
				"%-9s %-9s %-14s %s %dx%dx%d",
				"deep",
				tostring(b.kind),
				tostring(b.color),
				tostring(b.shape or "box"),
				math.floor(b.sx + 0.5),
				math.floor(b.sy + 0.5),
				math.floor(b.sz + 0.5)
			)
			groups[key] = (groups[key] or 0) + 1
		end
	end
	table.insert(lines, string.format("%-10s %6d %6d %6d %6d", "deep", c.plain, c.texture, c.mesh, c.glow))
end
-- the HQ rooms
do
	local pieces = HqRules.hideout(Config)
	local _, hides = HideoutKit.cell(Config, pieces, "high")
	local c = { plain = 0, texture = 0, mesh = 0, glow = 0 }
	for i, pc in pieces do
		local s = if hides[i] then "mesh" elseif pc.glow or pc.light then "glow" elseif pc.mat then "texture" else "plain"
		c[s] += 1
		if s == "plain" then
			local key = string.format("%-9s %-24s %dx%dx%d", "safehouse", pc.name, pc.sx, pc.sy, pc.sz)
			groups[key] = (groups[key] or 0) + 1
		end
	end
	table.insert(lines, string.format("%-10s %6d %6d %6d %6d", "hq vigil", c.plain, c.texture, c.mesh, c.glow))
	local boxes = HideoutKit.foundryBoxes(Config)
	local _, fh = HideoutKit.foundry(Config, { 120, 30, 30 }, "high")
	local f = 0
	for i in boxes do
		if fh[i] then
			f += 1
		end
	end
	table.insert(lines, string.format("%-10s %6d %6d %6d %6d", "hq foundry", #boxes - f, 0, f, 0))
end
table.insert(lines, "")
table.insert(lines, "Plain groups, biggest first (pocket, kind, colour, shape, size):")
local keys = {}
for k in groups do
	table.insert(keys, k)
end
table.sort(keys, function(a, b)
	if groups[a] ~= groups[b] then
		return groups[a] > groups[b]
	end
	return a < b
end)
for i, k in keys do
	if i > 60 then
		break
	end
	table.insert(lines, string.format("%4d  %s", groups[k], k))
end
fs.writeFile("art/preview/pocket_audit.txt", table.concat(lines, "\n") .. "\n")
print(table.concat(lines, "\n"))
