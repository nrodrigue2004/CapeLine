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

LifeKit.TURN = 180 -- Open Cloud's FBX import turns every Art.Life mesh 180 degrees about y (meshcheck, MeshFix)

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
	end
	return look
end

function LifeKit.ready(Config: any, look: string, has: (string) -> boolean): boolean
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
}

function LifeKit.cover(Config: any, b: any): { Piece }?
	local look = LifeKit.lookOf(Config, b)
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
			ry = ry + LifeKit.TURN,
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
