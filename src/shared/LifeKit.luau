--!strict
-- LifeKit: the living world's looks over the city's own boxes (2026-11-19, nate's playtest: "Too many simple
-- shapes"; Config.Life, Config.LifeArt from art/blender/life.py, imported as ReplicatedStorage.Art.Life). Pure, so
-- Lune checks it; CityBuilder builds what it says.
-- * A box with a `look` (BoxKit.tree's trunk and crown, the fields' crop and corn rows, hay bales, house doors,
--   silos) is built as that look's meshes in its place: every piece is scaled by the real box over the look's
--   nominal box, turned with the box (a row runs along its long side), and the box's record stays as it was
--   (heights, collisions, the breaking street things: the meshes are named and collide like the box did).
-- * cover(Config, b): the pieces { name, size, x, y, z, ry, color, mat, collide } or nil (no look / unknown).
--   ry is degrees about y, the set's import turn (MeshFix.turn) included.
-- * canopy(Config, b) and leaf(Config, b): which crown and colour a tree gets (hashes of its spot, so every
--   server and device agree and no tree changes from build to build).
-- * picket(Config, b): the faces a fence box wears the picket picture on ({ "Front", "Back" } along x, else
--   { "Left", "Right" }), or nil when it is not a picket fence.
-- * ready(Config, look, has): is every piece of a cover look imported (all or nothing, like the other sets)?

local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")

local LifeKit = {}

-- the looks whose long side follows the box's long side (a row along z turns a quarter)
local ROWS = { CropRow = true, CornRow = true }

local function kitOf(Config: any): any
	return { seed = Config.Life.seed }
end

local function weighted(list: { any }, r: number): string
	local total = 0
	for _, e in list do
		total += e[2]
	end
	local acc = 0
	for _, e in list do
		acc += e[2] / total
		if r <= acc then
			return e[1]
		end
	end
	return list[#list][1]
end

-- The crown look a tree's ball takes (`b.park`: a park or roof garden keeps broadleaves)
function LifeKit.canopy(Config: any, b: any): string
	local L = Config.Life
	local r = CityKit.roll(kitOf(Config), b.cx, b.cz, 1)
	return weighted(if b.park then L.parkCanopies else L.canopies, r)
end

-- The leaf colour a broadleaf crown takes
function LifeKit.leaf(Config: any, b: any): { number }
	return CityKit.pick(kitOf(Config), Config.Life.leaves, b.cx, b.cz, 2)
end

-- The look a box stands for: its own look, a crown's picked shape
function LifeKit.lookOf(Config: any, b: any): string?
	local look = b.look
	if look == "Canopy" then
		return LifeKit.canopy(Config, b)
	elseif look == "Rock" then
		return CityKit.pick(kitOf(Config), Config.Life.shapes.rocks, b.cx, b.cz, 5)
	end
	return look
end

function LifeKit.ready(Config: any, look: string, has: (string) -> boolean): boolean
	local sdef = Config.ShapeArt and Config.ShapeArt[look]
	if sdef then
		for name in sdef.meshes do
			if not has(name) then
				return false
			end
		end
		return true
	end
	local def = Config.LifeArt.cover[look]
	if not def then
		return false
	end
	for name in def.pieces do
		if not has(name) then
			return false
		end
	end
	return true
end

-- The box's size in the world before its turn: a ball is round (its largest side every way, like makePart)
local function dims(b: any): (number, number, number)
	if b.shape == "ball" then
		local m = math.max(b.sx, b.sy, b.sz)
		return m, m, m
	end
	return b.sx, b.sy, b.sz
end

export type Piece = {
	name: string,
	size: { number },
	x: number,
	y: number,
	z: number,
	ry: number,
	color: { number },
	mat: string,
	collide: boolean,
	set: string?, -- the art set (nil: Config.Life.set; round 2's: Config.Life.shapes.set)
	alpha: number?,
	maps: boolean?, -- keeps its baked SurfaceAppearance
}

-- Round 2 (shapes-2): an Art.Shapes look over its box (Config.ShapeArt: frame and meshes), or along its edges
local function shapeCover(Config: any, b: any, _look: string, sdef: any): { Piece }
	local SH = Config.Life.shapes
	local out: { Piece } = {}
	local fx, fy, fz = sdef.frame[1], sdef.frame[2], sdef.frame[3]
	local function color(m: any): { number }
		if m.tint then
			return Config.City.palette[b.color] or m.color
		end
		return m.color
	end
	local solid = not b.ghost and b.kind ~= "band" and b.kind ~= "glow" and b.kind ~= "crop" and not sdef.ring
	local function piece(
		name: string,
		m: any,
		kx: number,
		ky: number,
		kz: number,
		cx: number,
		cy: number,
		cz: number,
		ry: number
	)
		local a = math.rad(ry)
		local c, sn = math.cos(a), math.sin(a)
		local ox, oy, oz = m.offset[1] * kx, m.offset[2] * ky, m.offset[3] * kz
		table.insert(out, {
			name = name,
			size = { m.size[1] * kx, m.size[2] * ky, m.size[3] * kz },
			x = cx + ox * c + oz * sn,
			y = cy + oy,
			z = cz - ox * sn + oz * c,
			ry = ry,
			color = color(m),
			mat = m.mat,
			collide = solid and not SH.soft[name],
			set = SH.set,
			alpha = m.alpha,
			maps = m.maps,
		})
	end
	if sdef.ring then
		-- a run along each edge, its face out: (edge centre offset, its turn, its length); corners overlap
		local push = fz / 2 - SH.ring.out
		local ky = b.sy / fy
		local over = 2 * (fz - SH.ring.out)
		for _, e in
			{
				{ 0, -b.sz / 2 - push, 0, b.sx + over },
				{ 0, b.sz / 2 + push, 180, b.sx + over },
				{ -b.sx / 2 - push, 0, 90, b.sz + over },
				{ b.sx / 2 + push, 0, -90, b.sz + over },
			}
		do
			-- (a run's own -z face points out: turned 180 it faces +z, 90 -x, -90 +x, as CFrame.Angles turns it)
			for name, m in sdef.meshes do
				piece(name, m, e[4] / fx, ky, 1, b.cx + e[1], b.cy, b.cz + e[2], e[3])
			end
		end
	else
		local sx, sy, sz = b.sx, b.sy, b.sz
		local turn = 0
		if sz > sx and fx > fz * 3 then
			turn, sx, sz = 90, sz, sx -- a long look (a parapet, driftwood, a blade) follows the box's long side
		elseif SH.turns[b.look] then
			turn = math.floor(CityKit.roll(kitOf(Config), b.cx, b.cz, 6) * 8) * 45
		end
		for name, m in sdef.meshes do
			piece(name, m, sx / fx, sy / fy, sz / fz, b.cx, b.cy, b.cz, (b.ry or 0) + turn)
		end
	end
	table.sort(out, function(p, q)
		return p.name < q.name
	end)
	return out
end

-- Does the box itself stay under its look (a roof's cap under its moulding)?
function LifeKit.keeps(Config: any, b: any): boolean
	local look = b.look
	local sdef = look and Config.ShapeArt and Config.ShapeArt[look]
	return sdef ~= nil and (sdef.ring == true or Config.Life.shapes.keep[look] == true)
end

function LifeKit.cover(Config: any, b: any): { Piece }?
	local look = LifeKit.lookOf(Config, b)
	local sdef = look and Config.ShapeArt and Config.ShapeArt[look]
	if look and sdef then
		return shapeCover(Config, b, look, sdef)
	end
	local def = look and Config.LifeArt.cover[look]
	local spec = look and Config.Life.looks[look]
	if not (look and def and spec) then
		return nil
	end
	local sx, sy, sz = dims(b)
	local turn = 0
	if ROWS[look] and sz > sx then
		turn, sx, sz = 90, sz, sx
	elseif look == "TreeTrunk" or look == "CanopyRound" or look == "CanopyTall" or look == "CanopyPine" then
		turn = math.floor(CityKit.roll(kitOf(Config), b.cx, b.cz, 3) * 8) * 45 -- trees face every way
	end
	local ry = (b.ry or 0) + turn
	local a = math.rad(ry)
	local c, s = math.cos(a), math.sin(a)
	local n = def.nominal
	local kx, ky, kz = sx / n[1], sy / n[2], sz / n[3]
	local out: { Piece } = {}
	for name, f in def.pieces do
		local look1 = spec[name]
		if not look1 then
			continue
		end
		local ox, oy, oz = f.offset[1] * kx, f.offset[2] * ky, f.offset[3] * kz
		-- Roblox's CFrame.Angles(0, a, 0) turns (x, z) to (x cos a + z sin a, -x sin a + z cos a)
		local color = look1.color
		if look1.leaf then
			color = LifeKit.leaf(Config, b)
		elseif color and type(color[1]) == "table" then
			color = CityKit.pick(kitOf(Config), color, b.cx, b.cz, 4)
		end
		table.insert(out, {
			name = name,
			size = { f.size[1] * kx, f.size[2] * ky, f.size[3] * kz },
			x = b.cx + ox * c + oz * s,
			y = b.cy + oy,
			z = b.cz - ox * s + oz * c,
			ry = ry, -- (the import's turn is Shared.MeshFix's, put on by the builder)
			color = color :: { number },
			mat = look1.mat or "SmoothPlastic",
			collide = look1.collide ~= false and not b.ghost and b.kind ~= "crop",
		})
	end
	table.sort(out, function(p, q)
		return p.name < q.name
	end)
	return out
end

function LifeKit.picket(Config: any, b: any): { string }?
	if b.look ~= "Picket" or not Config.Life.picket then
		return nil
	end
	-- the faces are the part's own: a fence along its x shows on its z faces
	if b.sx >= b.sz then
		return { "Front", "Back" }
	end
	return { "Left", "Right" }
end

-- Round 2 (shapes-2): the roofs' plain ledges take a moulding look. A cornice cap (Config.City.kit.cornice) and a
-- low roof's cap keep their box (in the roof kit texture) with the moulding run round its edges; a parapet (a thin
-- ledge on a roof's edge) is drawn as the Parapet look. Boxes that are art, tagged or already looked stay as they
-- are. Returns how many it dressed.
function LifeKit.roofs(Config: any, boxes: { any }): number
	local SH = Config.Life.shapes
	if not (SH and Config.ShapeArt) then
		return 0
	end
	local n = 0
	for _, b in boxes do
		if b.kind == "ledge" and not b.art and not b.look and not b.tag and b.shape == nil then
			if b.color == "cornice" then
				b.look = "CorniceRun"
			elseif b.color == "roof" then
				b.look = if math.min(b.sx, b.sz) <= 2 then "Parapet" else "RoofEdge"
			end
			if b.look then
				n += 1
				if b.look ~= "Parapet" and b.kit == nil then
					b.kit = SH.roofKit
				end
			end
		end
	end
	return n
end

-- Every box with a look in a list, by look name (the audit and the tests)
function LifeKit.count(Config: any, boxes: { any }): { [string]: number }
	local out: { [string]: number } = {}
	for _, b in boxes do
		if b.look then
			local look = LifeKit.lookOf(Config, b) :: string
			out[look] = (out[look] or 0) + 1
		end
	end
	return out
end

return LifeKit
