local Config = require("../src/config")
local WorldMap = require("../src/shared/WorldMap")
local w = WorldMap.build(Config, 202647)
local c = {}
for _, b in w.buildings do
	c[b.district .. b.size] = (c[b.district .. b.size] or 0) + 1
end
for k, v in c do
	print(k, v)
end
print(#w.buildings)
