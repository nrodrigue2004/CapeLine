-- path.luau: a swing down a real Downtown street for the preview (art/swing/path.py draws
-- art/preview/swing_path.png). The bot is tests/swing_sim.luau, the same Shared.SwingMath the game runs, over
-- the game's own buildings (WorldMap.build). Writes art/export/swing/path.json.
-- Run: lune run art/swing/path.luau [street index (4)] [seconds (9)]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")
local sim = require("../../tests/swing_sim")

local k = tonumber(process.args[1]) or 4
local seconds = tonumber(process.args[2]) or 9
local world = WorldMap.build(Config, 202647)
local C = Config.City
local d = C.districts.Downtown
local pitch = C.downtown.block + C.downtown.street
local boxes = {}
for _, b in world.buildings do
	if b.district == "Downtown" then
		table.insert(boxes, b)
	end
end
local x0 = d.minX + k * pitch
local r = sim(Config, boxes, C.ground.y, { x0, 3, d.minZ + 40 }, { 0, 1 }, seconds)

local minZ, maxZ = math.huge, -math.huge
for _, s in r.path do
	minZ, maxZ = math.min(minZ, s.z), math.max(maxZ, s.z)
end
local near = {}
for _, b in boxes do
	if math.abs(b.x - x0) < 200 and b.z > minZ - 80 and b.z < maxZ + 80 then
		table.insert(near, { x = b.x, z = b.z, sx = b.sx, sz = b.sz, base = b.base, top = b.top })
	end
end
local path = {}
for i, s in r.path do
	if i % 3 == 1 then
		table.insert(path, { s.t, s.x, s.y, s.z, s.speed, s.mode })
	end
end
local lines = {}
for _, l in r.lines do
	local at
	for _, s in r.path do
		if s.t >= l.t0 then
			at = s
			break
		end
	end
	table.insert(lines, { l.t0, l.t1, at.x, at.y, at.z, l.ax, l.ay, l.az, l.qx, l.qz, l.edge, l.speedIn, l.speedOut })
end
local rel = {}
for _, e in r.releases do
	table.insert(rel, { e.t, e.x, e.y, e.z, e.speed, e.sweet })
end
local avg = (r.path[#r.path].z - r.path[1].z) / r.path[#r.path].t
local top = 0
for _, s in r.path do
	if s.mode == "swing" then
		top = math.max(top, s.speed)
	end
end
fs.writeDir("art/export/swing")
fs.writeFile(
	"art/export/swing/path.json",
	serde.encode("json", {
		street = x0,
		buildings = near,
		path = path,
		lines = lines,
		releases = rel,
		stats = {
			seconds = seconds,
			avg = avg,
			top = top,
			lines = #r.lines,
			bumps = r.bumps,
			cap = Config.Move.mobility.swing.cap,
			maxSpeed = Config.Move.mobility.swing.maxSpeed,
		},
	})
)
print(string.format("%d lines, %d releases, avg %.1f studs/s, top swing speed %.1f, %d bumps", #r.lines, #r.releases, avg, top, r.bumps))
