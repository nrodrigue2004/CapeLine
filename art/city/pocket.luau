-- pocket.luau: writes a mission or side quest pocket as JSON for art/blender/pocket.py's preview, straight from
-- the game's own layout (Shared.PocketLayout) and its kit dressing (Shared.PocketDress, Config.PocketKit), so the
-- render is what players see on a high preset (every tier, every light; the street props as Art.Street meshes).
-- Run: lune run art/city/pocket.luau [-- --plain] [name ...]   (no names: every pocket; --plain writes the greybox
-- as it was before the kit, for a before/after; writes art/export/city/pocket_<name>[_plain].json)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local PocketLayout = require("../../src/shared/PocketLayout")
local PocketDress = require("../../src/shared/PocketDress")

local ALL = {
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

-- cameras per pocket in pocket-local studs (x, y, z from its centre and floor): from, to, lens. air: a cutaway
-- from above (ceilings and the glass shell hidden); in: eye level from the spawn; down: the lower floor
local DECK = { 0, 34, 150 }
local CAMS: { [string]: any } = {
	station = { in_ = { { 12, 7, 170 }, { 0, 12, 40 }, 22 } },
	tower = {
		air = { { -170, 330, 240 }, { 0, 120, 0 }, 30 },
		in_ = { { -30, 190, 40 }, { 20, 186, -30 }, 20 },
	},
	rooftops = { in_ = { { 0, 58, 180 }, { 0, 50, 0 }, 22 } },
	dungeon = { in_ = { { -175, 7, 30 }, { -60, 8, -10 }, 20 } },
	arena = { in_ = { { 20, 7, 170 }, { 0, 25, -150 }, 22 } },
	bridge = { in_ = { { 14, 27, 185 }, { 0, 40, 40 }, 20 } },
	subway = {
		air = { { -260, 260, 260 }, { 0, 0, 30 }, 30 },
		in_ = { { 64 * 0.5 - 4, 7, 170 }, { 64 * 0.5, 7, 60 }, 18 },
		noSign = true, -- (the station boards are on the tunnel walls: the in view shows them)
	},
	academy = { in_ = { { 0, 32, 186 }, DECK, 20 }, down = { { -30, 8, -100 }, { 60, 4, -170 }, 18 } },
	toyshop = { in_ = { { 0, 28, 186 }, { 0, 26, 60 }, 20 }, down = { { -30, 8, -96 }, { 40, 6, -170 }, 18 } },
	seacave = { in_ = { { 0, 28, 180 }, { 0, 24, 60 }, 20 }, down = { { -30, 8, -96 }, { 80, 6, -150 }, 18 } },
	velmara = { in_ = { { 0, 28, 176 }, { 0, 28, 60 }, 20 }, down = { { -30, 8, -96 }, { 80, 6, -170 }, 18 } },
	pit = { in_ = { { 0, 30, -26 }, { 0, 4, -130 }, 20 }, down = { { 40, 8, -90 }, { 0, 6, -150 }, 20 } },
	ashlab = { in_ = { { 0, 28, 186 }, { 0, 26, 50 }, 20 }, down = { { -30, 8, -96 }, { 60, 6, -170 }, 18 } },
	ironhall = { in_ = { { 0, 28, 186 }, { 0, 26, 50 }, 20 }, down = { { -30, 8, -96 }, { 0, 6, -150 }, 18 } },
	pound = { in_ = { { 10, 8, 160 }, { 0, 10, -60 }, 18 } },
}

local plain = false
local names = {}
for _, a in process.args do
	if a == "--plain" then
		plain = true
	else
		table.insert(names, a)
	end
end
if #names == 0 then
	names = ALL
end

local function strip(b: any): any
	local o = {}
	for k, v in b do
		if type(v) ~= "table" or k == "sign" then
			o[k] = v
		end
	end
	return o
end

for _, name in names do
	local idx = if name == "subway" then PocketLayout.subwayIndex(Config) else 1
	local l = PocketLayout.build(Config, idx, name)
	local dress = if plain then { extras = {}, lights = {}, props = {} } else PocketDress.apply(Config, l, name)
	local out: any = {
		name = name,
		centre = { l.cx, l.cy, l.cz },
		boxes = {},
		lights = dress.lights,
		props = dress.props,
		cams = {},
	}
	for _, b in l.boxes do
		table.insert(out.boxes, strip(b))
	end
	for _, e in dress.extras do
		table.insert(out.boxes, strip(e))
	end
	local c = CAMS[name] or {}
	local function cam(v: any): any
		return {
			{ l.cx + v[1][1], l.cy + v[1][2], l.cz + v[1][3] },
			{ l.cx + v[2][1], l.cy + v[2][2], l.cz + v[2][3] },
			v[3],
		}
	end
	out.cams.air = cam(c.air or { { -230, 300, 330 }, { 0, 0, 10 }, 30 })
	out.cams["in"] = cam(c.in_)
	-- the first sign board, seen square on from in front of it
	for _, e in dress.extras do
		local sg = (e :: any).sign
		if sg and not c.noSign then
			local ry = math.rad(e.ry or 0)
			local w = math.max(e.sx, e.sz)
			local dist = w * 1.1 + 12
			local fx, fz = -math.sin(ry), -math.cos(ry)
			out.cams.sign = {
				{ e.cx + fx * dist, e.cy - 2, e.cz + fz * dist },
				{ e.cx, e.cy - 3, e.cz },
				24,
			}
			break
		end
	end
	if c.down then
		out.cams.down = cam(c.down)
	end
	out.palette = Config.City.palette
	out.looks = {}
	for pname, def in Config.City.kit.props do
		out.looks[pname] = def.pieces
	end
	out.tinted = {}
	for tname, v in Config.City.kit.tinted do
		out.tinted[tname] = v ~= nil
	end
	out.studsPerTile = Config.City.kit.studsPerTile
	local file = "art/export/city/pocket_" .. name .. (if plain then "_plain" else "") .. ".json"
	fs.writeFile(file, serde.encode("json", out))
	print(name, #out.boxes, "boxes", #out.props, "props", #out.lights, "lights")
end
