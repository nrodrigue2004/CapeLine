-- layout.luau: writes both HQs as JSON for art/blender/hq.py's previews, straight from the game's own data
-- (Shared.HqArtKit's scene: every placed look and the parts it hides; Shared.HqRules.hideout, the Safehouse's
-- room; Shared.RepTiers' dressing; the WANTED wall from Shared.WantedRules with sample nemesis heads and a
-- bust; the dummies' spots as HqService places them), so each render shows every look where the game puts it,
-- beside today's parts.
-- Run: lune run art/hq/layout.luau   (writes art/export/hq/layout.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local HqArtKit = require("../../src/shared/HqArtKit")
local HqRules = require("../../src/shared/HqRules")
local WantedRules = require("../../src/shared/WantedRules")
local RepTiers = require("../../src/shared/RepTiers")

local P = Config.City.palette
local H = Config.Hq
local out: { [string]: any } = { sides = {}, size = H.cell.size, colors = HqArtKit.COLORS }

local function rgb(key: string): { number }
	return P[key] or { 255, 0, 255 }
end

local function piece(p: any): { [string]: any }
	return {
		name = p.name,
		at = { p.x, p.y, p.z },
		size = { p.sx, p.sy, p.sz },
		rgb = p.rgb,
		mat = p.mat or "SmoothPlastic",
		shape = p.shape,
		ry = if type(p.ry) == "number" then p.ry else 0,
		rz = if type(p.rz) == "number" then p.rz else 0,
		clear = p.clear or 0,
	}
end

-- the Safehouse's room pieces (HqRules.hideout) in palette colours
local hide = {}
for _, p in HqRules.hideout(Config) do
	local q = piece(p)
	q.rgb = rgb(p.color)
	table.insert(hide, q)
end
out.hideout = hide

for _, side in { "hero", "villain" } do
	local s = HqArtKit.scene(Config, side, 5)
	local places = {}
	for _, p in s.places do
		table.insert(places, { look = p.look, at = { p.x, p.y, p.z }, ry = p.ry or 0 })
	end
	local wall = {}
	for _, p in s.wall do
		table.insert(wall, { look = p.look, at = { p.x, p.y, p.z }, ry = p.ry or 0 })
	end
	local bx = {}
	for _, b in s.boxes do
		table.insert(bx, { name = b.name, at = { b.x, b.y, b.z }, size = { b.sx, b.sy, b.sz }, art = b.art })
	end
	local dress = {}
	for _, p in RepTiers.dressing(Config, side, RepTiers.MAX) do
		table.insert(dress, piece(p))
	end
	out.sides[side] = { places = places, wall = wall, boxes = bx, dressing = dress }
end

-- the WANTED wall in its own frame (WantedRules: origin at the wall's foot, -z into the room): the poster and
-- board, the pins, the mounts and plates, five sample nemeses' heads (one of each head piece and build) and a bust
local L = WantedRules.layout(Config)
local W = H.wanted
local function spot(s: any): { [string]: any }
	return { at = { s.x, s.y, s.z }, size = { s.sx, s.sy, s.sz } }
end
local mounts, plates, heads = {}, {}, {}
local BUILDS = { "bulky", "lanky", "spiked", "squat", "plain" }
for r = 1, #L.mounts do
	table.insert(mounts, spot(L.mounts[r]))
	table.insert(plates, spot(L.plates[r]))
	local look = WantedRules.look(Config.Nemesis, 1000 + r * 7, r, if r % 2 == 0 then "villain" else "hero")
	look.head = Config.Nemesis.heads[(r - 1) % #Config.Nemesis.heads + 1]
	look.build = BUILDS[r]
	look.colors = (r - 1) % #Config.Nemesis.colors + 1
	local hx, hy, hz = WantedRules.headAt(L.mounts[r])
	local pieces = {}
	for _, p in WantedRules.head(Config.Nemesis, look, hx, hy, hz) do
		table.insert(pieces, piece(p))
	end
	table.insert(heads, pieces)
end
local bustLook = WantedRules.look(Config.Nemesis, 4242, 3, "hero", 15)
bustLook.cape = true
bustLook.head = "horned"
bustLook.build = "spiked"
local bust = {}
for _, p in WantedRules.bust(Config.Nemesis, bustLook) do
	local q = piece(p)
	q.ry = math.deg(q.ry)
	table.insert(bust, q)
end
out.wanted = {
	wall = { W.wall.x, W.wall.z },
	yaw = HqArtKit.wallYaw(Config),
	poster = spot(L.poster),
	board = spot(L.board),
	pins = HqArtKit.pins(Config),
	mounts = mounts,
	plates = plates,
	heads = heads,
	bust = bust,
}

-- the stations (for labels), the dummies' spots (HqService: 4 at level 3, the boss sim 18 behind) and statues
local st = {}
for name, s in H.stations do
	st[name] = { s[1], s[2] }
end
out.stations = st
local tr = H.stations.training
local dummies = {}
for i = 1, 4 do
	table.insert(dummies, { tr[1] + (i - 1) * 7 - 3 * 3.5, 0, tr[2] + 6 })
end
out.dummies = dummies
out.sim = { tr[1], 0, tr[2] + 18 }
out.trophy = { HqArtKit.trophyBase(Config) }
out.statues = {}
for i = 1, 5 do
	local x, z, a = HqArtKit.statueAt(Config, i, 5)
	table.insert(out.statues, { x, z, math.deg(a) })
end

if not fs.isDir("art/export/hq") then
	fs.writeDir("art/export/hq")
end
fs.writeFile("art/export/hq/layout.json", serde.encode("json", out))
print("wrote art/export/hq/layout.json")
