--!strict
-- Structure: the Red Faction-style building model (nate 2026-11-16: "destruction like Red Faction
-- Guerrilla"). Pure and deterministic from the building's box, so the server and every device build the same
-- pieces and agree on what falls.
-- * build(cfg, b): a building is storeys of 4 corner pillars, wall panels on each face and a floor slab on
--   top (split 2 x 2 on wide buildings). Inside is open: a hole in a wall shows the floors behind it.
-- * blast(cfg, grid, gone, center, radius, dmg): which pieces a hit knocks out (nearest first, about one
--   piece per cfg.chunkCost of structure damage; pillars count double).
-- * settle(cfg, grid, gone, keepGround): what falls after that. A storey stands while its pillars and walls
--   still carry cfg.support of their full weight; when one gives way, it and every storey above come down
--   (a ground-floor failure is a full collapse). A wall panel with nothing under it and no neighbour on either
--   side drops, and so does a slab tile with nothing left holding it.
-- * pack/unpack: one bit a piece (at most 256 pieces, 32 bytes).

local Structure = {}

export type Piece = {
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	kind: string, -- "pillar", "wall" or "slab"
	storey: number, -- 1 at the bottom
	face: number, -- walls: 1 front (-z), 2 back (+z), 3 left (-x), 4 right (+x); pillars: corner 1 to 4
	col: number, -- walls: panel along the face; slabs: tile index
	weight: number, -- what it carries (pillars 2, walls 1, slabs 0)
}

export type Grid = {
	pieces: { Piece },
	storeys: number,
	storeyH: number,
	base: number,
	bearing: { { number } }, -- per storey: indexes of pillars and walls
	full: { number }, -- per storey: the full bearing weight
	at: { [string]: number }, -- "w:face:col:storey" / "p:corner:storey" -> index
	panels: { number }, -- panels per face (1..4)
	holds: { [number]: { number } }, -- slab index -> the bearing pieces under its tile
}

local function key(...: any): string
	return table.concat({ ... }, ":")
end

-- b: { x, z, sx, sz, base, top }
function Structure.build(cfg: any, b: any): Grid
	local S = cfg.structure
	local h = b.top - b.base
	local storeys = math.clamp(math.ceil(h / S.storey - 0.25), 1, S.maxStoreys)
	local sh = h / storeys
	local t, pt, slab = S.wall, math.min(S.pillar, b.sx / 3, b.sz / 3), S.slab
	local spanX, spanZ = b.sx - 2 * pt, b.sz - 2 * pt
	local nx = math.clamp(math.floor(spanX / S.panel + 0.5), 1, S.maxPanels)
	local nz = math.clamp(math.floor(spanZ / S.panel + 0.5), 1, S.maxPanels)
	local x0, z0 = b.x - b.sx / 2, b.z - b.sz / 2
	local grid: Grid = {
		pieces = {},
		storeys = storeys,
		storeyH = sh,
		base = b.base,
		bearing = {},
		full = {},
		at = {},
		panels = { nx, nx, nz, nz },
		holds = {},
	}
	local function add(p: Piece, k: string?): number
		table.insert(grid.pieces, p)
		local i = #grid.pieces
		if k then
			grid.at[k] = i
		end
		if p.weight > 0 then
			table.insert(grid.bearing[p.storey], i)
			grid.full[p.storey] += p.weight
		end
		return i
	end
	for s = 1, storeys do
		grid.bearing[s] = {}
		grid.full[s] = 0
		local y0 = b.base + (s - 1) * sh
		local wallH = sh - slab
		local wy = y0 + wallH / 2
		-- the 4 corner pillars
		local corners = {
			{ x0 + pt / 2, z0 + pt / 2 },
			{ x0 + b.sx - pt / 2, z0 + pt / 2 },
			{ x0 + pt / 2, z0 + b.sz - pt / 2 },
			{ x0 + b.sx - pt / 2, z0 + b.sz - pt / 2 },
		}
		for c, xz in corners do
			add({
				cx = xz[1],
				cy = wy,
				cz = xz[2],
				sx = pt,
				sy = wallH,
				sz = pt,
				kind = "pillar",
				storey = s,
				face = c,
				col = 0,
				weight = S.pillarCost,
			}, key("p", c, s))
		end
		-- wall panels: front and back run along x, left and right along z
		local pw, pd = spanX / nx, spanZ / nz
		for col = 1, nx do
			local cx = x0 + pt + (col - 0.5) * pw
			add({
				cx = cx,
				cy = wy,
				cz = z0 + t / 2,
				sx = pw,
				sy = wallH,
				sz = t,
				kind = "wall",
				storey = s,
				face = 1,
				col = col,
				weight = 1,
			}, key("w", 1, col, s))
			add({
				cx = cx,
				cy = wy,
				cz = z0 + b.sz - t / 2,
				sx = pw,
				sy = wallH,
				sz = t,
				kind = "wall",
				storey = s,
				face = 2,
				col = col,
				weight = 1,
			}, key("w", 2, col, s))
		end
		for col = 1, nz do
			local cz = z0 + pt + (col - 0.5) * pd
			add({
				cx = x0 + t / 2,
				cy = wy,
				cz = cz,
				sx = t,
				sy = wallH,
				sz = pd,
				kind = "wall",
				storey = s,
				face = 3,
				col = col,
				weight = 1,
			}, key("w", 3, col, s))
			add({
				cx = x0 + b.sx - t / 2,
				cy = wy,
				cz = cz,
				sx = t,
				sy = wallH,
				sz = pd,
				kind = "wall",
				storey = s,
				face = 4,
				col = col,
				weight = 1,
			}, key("w", 4, col, s))
		end
		-- the slab on top (the roof on the last storey); wide buildings get 2 x 2 tiles
		local split = if b.sx >= S.slabSplitAt and b.sz >= S.slabSplitAt then 2 else 1
		local tx, tz = b.sx / split, b.sz / split
		local tile = 0
		for i = 1, split do
			for j = 1, split do
				tile += 1
				local sIdx = add({
					cx = x0 + (i - 0.5) * tx,
					cy = y0 + sh - slab / 2,
					cz = z0 + (j - 0.5) * tz,
					sx = tx,
					sy = slab,
					sz = tz,
					kind = "slab",
					storey = s,
					face = 0,
					col = tile,
					weight = 0,
				})
				-- the bearing pieces of this storey under the tile's edge carry it
				local holds = {}
				local lx, hx = x0 + (i - 1) * tx - t, x0 + i * tx + t
				local lz, hz = z0 + (j - 1) * tz - t, z0 + j * tz + t
				for _, bi in grid.bearing[s] do
					local p = grid.pieces[bi]
					if
						p.cx + p.sx / 2 >= lx
						and p.cx - p.sx / 2 <= hx
						and p.cz + p.sz / 2 >= lz
						and p.cz - p.sz / 2 <= hz
					then
						table.insert(holds, bi)
					end
				end
				grid.holds[sIdx] = holds
			end
		end
	end
	return grid
end

-- Distance from a point to a piece's box
function Structure.distance(p: Piece, x: number, y: number, z: number): number
	local dx = math.max(math.abs(x - p.cx) - p.sx / 2, 0)
	local dy = math.max(math.abs(y - p.cy) - p.sy / 2, 0)
	local dz = math.max(math.abs(z - p.cz) - p.sz / 2, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The pieces a hit knocks out, nearest first. dmg buys pieces at cfg.chunkCost each (pillars cost double).
function Structure.blast(
	cfg: any,
	grid: Grid,
	gone: { [number]: boolean },
	x: number,
	y: number,
	z: number,
	radius: number,
	dmg: number
): { number }
	local S = cfg.structure
	local near = {}
	for i, p in grid.pieces do
		if not gone[i] then
			local d = Structure.distance(p, x, y, z)
			if d <= radius then
				table.insert(near, { i = i, d = d })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.d < b.d or (a.d == b.d and a.i < b.i)
	end)
	local budget = math.max(dmg / S.chunkCost, 1)
	local out = {}
	for _, n in near do
		if #out >= S.maxPerHit then
			break
		end
		local p = grid.pieces[n.i]
		local cost = if p.kind == "pillar" then S.pillarCost else 1
		if budget >= cost or #out == 0 then
			budget -= cost
			table.insert(out, n.i)
			gone[n.i] = true
		end
		if budget <= 0 then
			break
		end
	end
	return out
end

-- Does storey s still stand on its own pillars and walls?
function Structure.stands(cfg: any, grid: Grid, gone: { [number]: boolean }, s: number): boolean
	local left = 0
	for _, i in grid.bearing[s] do
		if not gone[i] then
			left += grid.pieces[i].weight
		end
	end
	return left >= grid.full[s] * cfg.structure.support
end

-- What falls after pieces were knocked out. Marks them gone and returns the pieces that fell and the lowest
-- storey that gave way (nil if none). keepGround: the ground floor may not fail (the collapse cap).
function Structure.settle(
	cfg: any,
	grid: Grid,
	gone: { [number]: boolean },
	keepGround: boolean?
): ({ number }, number?)
	local fell: { number } = {}
	local failed: number? = nil
	local function drop(i: number)
		if not gone[i] then
			gone[i] = true
			table.insert(fell, i)
		end
	end
	for s = 1, grid.storeys do
		if not (s == 1 and keepGround) and not Structure.stands(cfg, grid, gone, s) then
			failed = s
			break
		end
	end
	if failed then
		for i, p in grid.pieces do
			if p.storey >= failed then
				drop(i)
			end
		end
	end
	-- hanging pieces below the failure: keep looking until nothing more drops
	local top = if failed then failed - 1 else grid.storeys
	local changed = true
	while changed do
		changed = false
		for i, p in grid.pieces do
			if not gone[i] and p.storey <= top then
				local loose = false
				if p.kind == "wall" and p.storey > 1 then
					local below = grid.at[key("w", p.face, p.col, p.storey - 1)]
					local l = grid.at[key("w", p.face, p.col - 1, p.storey)]
					local r = grid.at[key("w", p.face, p.col + 1, p.storey)]
					-- the end panels lean on the corner pillars
					local n = grid.panels[p.face]
					local cl, cr
					if p.face == 1 then
						cl, cr = 1, 2
					elseif p.face == 2 then
						cl, cr = 3, 4
					elseif p.face == 3 then
						cl, cr = 1, 3
					else
						cl, cr = 2, 4
					end
					if p.col == 1 then
						l = grid.at[key("p", cl, p.storey)]
					end
					if p.col == n then
						r = grid.at[key("p", cr, p.storey)]
					end
					loose = (below == nil or gone[below] == true)
						and (l == nil or gone[l] == true)
						and (r == nil or gone[r] == true)
				elseif p.kind == "slab" then
					loose = true
					for _, bi in grid.holds[i] or {} do
						if not gone[bi] then
							loose = false
							break
						end
					end
				end
				if loose then
					drop(i)
					changed = true
				end
			end
		end
	end
	return fell, failed
end

-- The share of the building's bearing weight that is gone (0 to 1)
function Structure.lost(grid: Grid, gone: { [number]: boolean }): number
	local all, left = 0, 0
	for s = 1, grid.storeys do
		all += grid.full[s]
		for _, i in grid.bearing[s] do
			if not gone[i] then
				left += grid.pieces[i].weight
			end
		end
	end
	return if all > 0 then 1 - left / all else 0
end

-- The top of what still stands (for heights): the base of the lowest failed storey, or the roof
function Structure.standingTop(grid: Grid, gone: { [number]: boolean }): number
	for s = 1, grid.storeys do
		local any = false
		for _, i in grid.bearing[s] do
			if not gone[i] then
				any = true
				break
			end
		end
		if not any then
			return grid.base + (s - 1) * grid.storeyH
		end
	end
	return grid.base + grid.storeys * grid.storeyH
end

function Structure.pack(n: number, gone: { [number]: boolean }): buffer
	local b = buffer.create(math.ceil(n / 8))
	for i in gone do
		if i >= 1 and i <= n then
			local byte = (i - 1) // 8
			buffer.writeu8(b, byte, bit32.bor(buffer.readu8(b, byte), bit32.lshift(1, (i - 1) % 8)))
		end
	end
	return b
end

function Structure.unpack(b: buffer, n: number): { [number]: boolean }
	local out: { [number]: boolean } = {}
	for i = 1, math.min(n, buffer.len(b) * 8) do
		if bit32.band(buffer.readu8(b, (i - 1) // 8), bit32.lshift(1, (i - 1) % 8)) ~= 0 then
			out[i] = true
		end
	end
	return out
end

return Structure
