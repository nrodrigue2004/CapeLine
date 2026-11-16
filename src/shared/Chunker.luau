--!strict
-- Chunker: splits a building into 10 to 40 chunks (spec: Destruction "Buildings are pre-split into 10 to 40
-- chunks"; Art list "each pre-split into 10 to 40 chunks by the Chunker tool"). Pure and seeded by the
-- building id, so every client splits a building the same way and the same chunks fall.
-- * split: rows of about one floor, 1 or 2 columns each way, filling the body exactly.
-- * fallen: the 4 to 8 chunks a Damaged building loses (upper and outer chunks first).
-- * rubble: the low heap a Collapsed building leaves (6 to 10 tilted pieces inside its footprint).

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local Chunker = {}

export type Chunk = {
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	row: number, -- 1 at the bottom
	outer: boolean, -- on a corner of the footprint
}

export type Piece = {
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	rx: number,
	ry: number,
	rz: number,
}

-- b: { x, z, sx, sz, base, top }
function Chunker.split(cfg: any, b: any): { Chunk }
	local c = cfg.chunks
	local h = b.top - b.base
	local nx = if b.sx >= c.wideAt then 2 else 1
	local nz = if b.sz >= c.wideAt then 2 else 1
	local per = nx * nz
	local rows = math.clamp(math.ceil(h / c.floor), math.ceil(c.min / per), math.floor(c.max / per))
	local list: { Chunk } = {}
	local cw, cd, ch = b.sx / nx, b.sz / nz, h / rows
	for row = 1, rows do
		for i = 1, nx do
			for j = 1, nz do
				table.insert(list, {
					cx = b.x - b.sx / 2 + (i - 0.5) * cw,
					cy = b.base + (row - 0.5) * ch,
					cz = b.z - b.sz / 2 + (j - 0.5) * cd,
					sx = cw,
					sy = ch,
					sz = cd,
					row = row,
					outer = (nx == 1 or i == 1 or i == nx) and (nz == 1 or j == 1 or j == nz),
				})
			end
		end
	end
	return list
end

-- Which chunks fall away when the building turns Damaged: 4 to 8, from the top half
function Chunker.fallen(cfg: any, chunks: { Chunk }, id: number): { [number]: boolean }
	local c = cfg.chunks
	local rng = Rng.new(Rng.hash(id, 77))
	local rows = 0
	for _, ch in chunks do
		rows = math.max(rows, ch.row)
	end
	local pool = {}
	for i, ch in chunks do
		if ch.row > rows / 2 and ch.row > 1 then
			table.insert(pool, i)
		end
	end
	local want = math.min(rng:int(c.fallMin, c.fallMax), #pool, #chunks - 1)
	local out: { [number]: boolean } = {}
	local n = 0
	while n < want do
		local k = rng:int(1, #pool)
		local idx = pool[k]
		table.remove(pool, k)
		out[idx] = true
		n += 1
	end
	return out
end

-- The rubble heap a Collapsed building leaves
function Chunker.rubble(cfg: any, b: any, id: number): { Piece }
	local r = cfg.rubble
	local rng = Rng.new(Rng.hash(id, 91))
	local n = rng:int(r.min, r.max)
	local h = math.min(r.height, (b.top - b.base) * 0.3)
	local list: { Piece } = {}
	for k = 1, n do
		local f = k / n
		local sx = b.sx * rng:range(0.25, 0.5)
		local sz = b.sz * rng:range(0.25, 0.5)
		local sy = math.max(2, h * rng:range(0.4, 1) * (1 - f * 0.5))
		table.insert(list, {
			cx = b.x + rng:range(-1, 1) * (b.sx - sx) / 2,
			cy = b.base + sy / 2 - 1,
			cz = b.z + rng:range(-1, 1) * (b.sz - sz) / 2,
			sx = sx,
			sy = sy,
			sz = sz,
			rx = rng:range(-18, 18),
			ry = rng:range(0, 180),
			rz = rng:range(-18, 18),
		})
	end
	return list
end

return Chunker
