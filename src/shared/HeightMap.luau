--!strict
-- HeightMap: the top of whatever stands in each 10-stud cell of the whole 4,800-stud map, so the robot AI,
-- the load bots and spawn checks know roof and ground heights anywhere without raycasts (spec: Map layout).
-- One u16 per cell in a buffer (480 x 480 cells, 460 KB), quarter-stud steps. Flat pieces under 1.5 studs
-- (ground, roads, sidewalks, fields) are skipped: the ground is height 0. Outside the map is the sea.

local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")

local HeightMap = {}

local OFFSET = 64 -- heights from -64 up are stored
local SCALE = 4

export type HeightMap = {
	cell: number,
	min: number,
	n: number,
	sea: number,
	buf: buffer,
}

function HeightMap.new(mapSize: number, cell: number, sea: number): HeightMap
	local n = math.ceil(mapSize / cell)
	local buf = buffer.create(n * n * 2)
	local hm = { cell = cell, min = -mapSize / 2, n = n, sea = sea, buf = buf }
	-- every cell starts at ground level (0)
	local zero = OFFSET * SCALE
	for i = 0, n * n - 1 do
		buffer.writeu16(buf, i * 2, zero)
	end
	return hm
end

-- Raise the cells under a box to its top
-- (a box marked nomap stays out: Crane Tower's ledges and deck, whose heights come from Shared.MapSites.topAt)
function HeightMap.stamp(hm: HeightMap, b: BoxKit.Box)
	if not BoxKit.solid(b) or (b :: any).nomap then
		return
	end
	local fx, fz = BoxKit.footprint(b)
	local sy = b.sy
	if b.shape == "ball" then
		-- a Roblox ball is round: its largest size is its diameter
		local s = math.max(b.sx, b.sy, b.sz)
		fx, fz, sy = s, s, s
	end
	local top = b.cy + sy / 2
	if top < 1.5 then
		return
	end
	local ry = (b.ry or 0) % 90
	if ry ~= 0 then
		-- turned off the grid: cover the bounding square
		local r = math.max(fx, fz)
		fx, fz = r, r
	end
	local n = hm.n
	local x0 = math.max(0, math.floor((b.cx - fx / 2 - hm.min) / hm.cell))
	local x1 = math.min(n - 1, math.floor((b.cx + fx / 2 - hm.min) / hm.cell))
	local z0 = math.max(0, math.floor((b.cz - fz / 2 - hm.min) / hm.cell))
	local z1 = math.min(n - 1, math.floor((b.cz + fz / 2 - hm.min) / hm.cell))
	local v = math.clamp(math.ceil((top + OFFSET) * SCALE), 0, 65535)
	local buf = hm.buf
	for iz = z0, z1 do
		local row = iz * n
		for ix = x0, x1 do
			local at = (row + ix) * 2
			if buffer.readu16(buf, at) < v then
				buffer.writeu16(buf, at, v)
			end
		end
	end
end

function HeightMap.at(hm: HeightMap, x: number, z: number): number
	local ix = math.floor((x - hm.min) / hm.cell)
	local iz = math.floor((z - hm.min) / hm.cell)
	if ix < 0 or iz < 0 or ix >= hm.n or iz >= hm.n then
		return hm.sea
	end
	return buffer.readu16(hm.buf, (iz * hm.n + ix) * 2) / SCALE - OFFSET
end

return HeightMap
