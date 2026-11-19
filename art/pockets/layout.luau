-- Writes art/export/pockets/layout.json for art/blender/pocketprops.py and board.py (gap-props2, 2026-11-19): every
-- prop placement Shared.PocketPropKit finds in the pockets (Config.PocketProps rules), each with the boxes it covers in
-- its own frame (x, up, z from its middle, before its turn) and their colours, plus each pocket's other boxes near
-- the props for the previews, and the plaza weekly board's numbers (Config.Boards.prop). A look's "keep" boxes
-- (gap-props3) are in its rows with keep = true and stay in the pocket's boxes for the previews.
--   lune run art/pockets/layout.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local PocketLayout = require("../../src/shared/PocketLayout")
local PocketDress = require("../../src/shared/PocketDress")
local PocketPropKit = require("../../src/shared/PocketPropKit")

local pal = Config.City.palette
local function rgb(b)
	return pal[b.tint or b.color] or pal[b.color] or { 200, 200, 200 }
end
local function row(b, at, ry)
	return {
		kind = b.kind,
		color = b.color,
		at = at,
		size = { b.sx, b.sy, b.sz },
		shape = b.shape,
		ry = ry,
		rgb = rgb(b),
		ghost = b.ghost,
	}
end

local out = { looks = {}, pockets = {}, board = Config.Boards.prop }
local layouts = {}
for _, r in Config.PocketProps.rules do
	if not table.find(layouts, r.layout) then
		table.insert(layouts, r.layout)
	end
end
table.sort(layouts)
local total = 0
for _, name in layouts do
	local l = PocketLayout.build(Config, 1, name)
	local dress = PocketDress.apply(Config, l, name)
	local places = PocketPropKit.places(Config, l, dress, name)
	local pk = { name = name, centre = { l.cx, l.cy, l.cz }, places = {}, boxes = {} }
	local covered = { box = {}, dress = {} }
	for _, p in places do
		total += 1
		local a = math.rad(p.ry)
		local c, s = math.cos(a), math.sin(a)
		local list = if p.dress then dress.extras else l.boxes
		local rows = {}
		local every = {}
		for _, j in p.boxes do
			table.insert(every, { j, false })
		end
		for _, j in p.keep or {} do -- (gap-props3) framed by the look, left drawn
			table.insert(every, { j, true })
		end
		for _, e in every do
			local j = e[1]
			covered[if p.dress then "dress" else "box"][j] = not e[2]
			local b = list[j]
			local dx, dz = b.cx - p.cx, b.cz - p.cz
			local r = row(b, { dx * c - dz * s, b.cy - p.cy, dx * s + dz * c }, (b.ry or 0) - p.ry)
			local q = (r.ry % 180 + 180) % 180
			if b.shape ~= "ball" and math.abs(q - 90) < 1e-6 then
				r.size = { b.sz, b.sy, b.sx }
				r.ry = 0
			elseif math.abs(q) < 1e-6 then
				r.ry = 0
			end
			r.keep = e[2] or nil
			table.insert(rows, r)
		end
		if not out.looks[p.look] then
			out.looks[p.look] = {
				frame = { p.sx, p.sy, p.sz },
				boxes = rows,
				tint = p.tint and pal[p.tint],
				layout = name,
			}
		end
		table.insert(
			pk.places,
			{ look = p.look, at = { p.cx - l.cx, p.cy - l.cy, p.cz - l.cz }, ry = p.ry, tint = p.tint and pal[p.tint] }
		)
	end
	-- the other boxes (and the dressing the high preset builds) for the previews, pocket-local
	local function add(b, isDress)
		local big = math.max(b.sx, b.sz)
		if b.tag == "pocketWall" or b.tag == "ceiling" or b.kind == "mark" then
			return
		end
		local r = row(b, { b.cx - l.cx, b.cy - l.cy, b.cz - l.cz }, b.ry or 0)
		r.dress = isDress
		r.big = big
		table.insert(pk.boxes, r)
	end
	for j, b in l.boxes do
		if not covered.box[j] then
			add(b, false)
		end
	end
	for j, b in dress.extras do
		if not covered.dress[j] then
			add(b, true)
		end
	end
	table.insert(out.pockets, pk)
end
fs.writeDir("art/export/pockets")
fs.writeFile("art/export/pockets/layout.json", serde.encode("json", out))
local n = 0
for _ in out.looks do
	n += 1
end
print("pocket props:", total, "placements,", n, "looks in", #layouts, "pockets")
