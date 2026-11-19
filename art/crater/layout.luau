-- Writes art/export/crater/layout.json for art/blender/crater.py: the Crater's boxes (world studs, with the look that
-- hides each), every look placement (Shared.CraterArtKit.cover) with the boxes it covers in its own frame (x, up, z
-- from its middle, before its turn), and the high preset's debris bits, from the game's own data (WorldGen.landmark).
--   lune run art/crater/layout.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local WorldGen = require("../../src/shared/WorldGen")
local CraterArtKit = require("../../src/shared/CraterArtKit")

local W = Config.World
local pal = Config.City.palette
local lm
for i, l in W.landmarks do
	if l.id == "CometCrater" then
		lm = WorldGen.landmark(Config.City, W, i)
	end
end
local out = { boxes = {}, places = {}, bits = {}, floorY = lm.floorY, centre = { lm.centre.x, lm.centre.z } }
local function row(b, at, ry)
	return {
		kind = b.kind,
		at = at,
		size = { b.sx, b.sy, b.sz },
		shape = b.shape,
		ry = ry,
		color = pal[b.tint or b.color] or pal[b.color] or { 200, 200, 200 },
		kit = b.kit,
		ghost = b.ghost,
		art = b.art,
	}
end
for _, b in lm.boxes do
	table.insert(out.boxes, row(b, { b.cx, b.cy, b.cz }, b.ry or 0))
end
for _, p in lm.art do
	local a = math.rad(p.ry or 0)
	local c, s = math.cos(a), math.sin(a)
	local covered = {}
	for _, b in lm.boxes do
		if b.art == p.look and CraterArtKit.inside(p, b.cx, b.cy, b.cz, 0.05) then
			local dx, dz = b.cx - p.cx, b.cz - p.cz
			local r = row(b, { dx * c - dz * s, b.cy - p.cy, dx * s + dz * c }, (b.ry or 0) - (p.ry or 0))
			-- a box a quarter turn off its placement: its own sizes in the placement's axes, unturned
			local q = (r.ry % 180 + 180) % 180
			if b.shape ~= "cylinder" and b.shape ~= "ball" and math.abs(q - 90) < 1e-6 then
				r.size = { b.sz, b.sy, b.sx }
				r.ry = 0
			elseif math.abs(q) < 1e-6 then
				r.ry = 0
			end
			table.insert(covered, r)
		end
	end
	table.insert(out.places, {
		look = p.look,
		at = { p.cx, p.cy, p.cz },
		size = { p.sx, p.sy, p.sz },
		ry = p.ry or 0,
		boxes = covered,
	})
end
for _, b in CraterArtKit.bits(Config, lm.centre.x, lm.centre.z, lm.art, "high") do
	table.insert(out.bits, { look = b.look, at = { b.x, lm.floorY, b.z }, ry = b.ry })
end
out.lookBits = W.crater.art.bits
fs.writeDir("art/export/crater")
fs.writeFile("art/export/crater/layout.json", serde.encode("json", out))
print("crater layout:", #out.boxes, "boxes,", #out.places, "placements,", #out.bits, "bits")
