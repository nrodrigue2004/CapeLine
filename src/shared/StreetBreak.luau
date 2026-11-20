--!strict
-- StreetBreak: which street things a device knocks loose and how a long one breaks (fix-destroy, 2026-11-19, nate:
-- "I literally want everything destructible"). Pure, so Lune checks it; BuildingFx.smashStreet uses it.
-- * kind(sx, sy, sz): "whole" (it flies off whole: trees, lamps, crates, containers, hay, poles), "long" (a fence or
--   a low wall: broken only where it was hit, segments) or nil (too big: ground pads, rock bases, crane legs).
-- * segments(box, at, r, len): a long part as short lengths along its long side, each marked broken when it is
--   within r of the hit, or nil when it is not long.
-- * Dressed things (destroy-all, 2026-11-20, nate: "destroy EVERYTHING"): a look drawn over hidden collision boxes
--   (the park's structures, the Deep's coral and wreck props) breaks as one group: the boxes and the meshes carry
--   the same Dress key (parkDress, deepDress; set by ParkBuilder and CityBuilder), BuildingFx.smashStreet flings
--   the meshes and hides the boxes on the device, and all come back after the street's respawn. groupKind says
--   "whole" (any knock, like a tree) or "big" (only a heavy hit or a ram: a bandshell, a bridge, a carousel).

local StreetBreak = {}

StreetBreak.TALL = 32 -- a whole thing up to this tall
StreetBreak.WIDE = 20 -- and this wide either way
StreetBreak.THIN = 3 -- a long thing is at most this thick and this tall x 2
StreetBreak.LONG = 12 -- and at least this long

function StreetBreak.kind(sx: number, sy: number, sz: number): string?
	local long, thin = math.max(sx, sz), math.min(sx, sz)
	if long >= StreetBreak.LONG and thin <= StreetBreak.THIN and sy <= StreetBreak.THIN * 2 then
		return "long"
	end
	if sy <= StreetBreak.TALL and sx <= StreetBreak.WIDE and sz <= StreetBreak.WIDE then
		return "whole"
	end
	return nil
end

export type Seg = { x: number, y: number, z: number, sx: number, sy: number, sz: number, broken: boolean }

-- box: { x, y, z, sx, sy, sz } axis-aligned (a fence is BoxKit.fence: one axis-aligned part)
function StreetBreak.segments(box: any, at: any, r: number, len: number): { Seg }?
	if StreetBreak.kind(box.sx, box.sy, box.sz) ~= "long" then
		return nil
	end
	local alongX = box.sx >= box.sz
	local total = if alongX then box.sx else box.sz
	local n = math.max(2, math.ceil(total / len))
	local each = total / n
	local out: { Seg } = {}
	for i = 1, n do
		local off = -total / 2 + (i - 0.5) * each
		local x = if alongX then box.x + off else box.x
		local z = if alongX then box.z else box.z + off
		local dx = math.max(math.abs(at.x - x) - (if alongX then each / 2 else box.sx / 2), 0)
		local dz = math.max(math.abs(at.z - z) - (if alongX then box.sz / 2 else each / 2), 0)
		table.insert(out, {
			x = x,
			y = box.y,
			z = z,
			sx = if alongX then each else box.sx,
			sy = box.sy,
			sz = if alongX then box.sz else each,
			broken = dx * dx + dz * dz <= r * r,
		})
	end
	return out
end

function StreetBreak.groupKind(sx: number, sy: number, sz: number): string
	if sy <= StreetBreak.TALL and sx <= StreetBreak.WIDE and sz <= StreetBreak.WIDE then
		return "whole"
	end
	return "big"
end

export type Dress = {
	box: { [number]: string }, -- box index -> group key
	mesh: { [number]: string }, -- mesh (park) or placement (Deep) index -> group key
	big: { [string]: boolean }, -- a group only a heavy hit or a ram breaks
	count: number,
}

-- half extents in x and z of a box sx x sz turned ry degrees about y
local function halfXZ(sx: number, sz: number, ry: number?): (number, number)
	local a = math.rad(ry or 0)
	local c, s = math.abs(math.cos(a)), math.abs(math.sin(a))
	return (c * sx + s * sz) / 2, (s * sx + c * sz) / 2
end

local function grow(
	bounds: { [string]: { number } },
	key: string,
	x: number,
	y: number,
	z: number,
	hx: number,
	hy: number,
	hz: number
)
	local b = bounds[key]
	if not b then
		b = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge }
		bounds[key] = b
	end
	b[1], b[2], b[3] = math.min(b[1], x - hx), math.min(b[2], y - hy), math.min(b[3], z - hz)
	b[4], b[5], b[6] = math.max(b[4], x + hx), math.max(b[5], y + hy), math.max(b[6], z + hz)
end

-- The park's break groups (Shared.ParkLayout: a look's meshes and the solid boxes placed with it share `group`):
-- every look with at least one collision box; the wall and rail lengths stay plain street props (breaks)
function StreetBreak.parkDress(park: any): Dress
	local out: Dress = { box = {}, mesh = {}, big = {}, count = 0 }
	local bounds: { [string]: { number } } = {}
	for i, b in park.solid do
		local g = b.group
		if type(g) == "number" and g > 0 then
			local key = "P" .. g
			out.box[i] = key
			local hx, hz = halfXZ(b.sx, b.sz, b.ry)
			grow(bounds, key, b.cx, b.cy, b.cz, hx, b.sy / 2, hz)
		end
	end
	for i, m in park.meshes do
		local key = "P" .. tostring(m.group)
		if not m.breaks and bounds[key] then
			out.mesh[i] = key
			local hx, hz = halfXZ(m.size[1], m.size[3], m.ry)
			grow(bounds, key, m.x, m.y, m.z, hx, m.size[2] / 2, hz)
		end
	end
	for key, b in bounds do
		out.count += 1
		if StreetBreak.groupKind(b[4] - b[1], b[5] - b[2], b[6] - b[3]) == "big" then
			out.big[key] = true
		end
	end
	return out
end

-- The Deep's break groups: a hidden prop box (its look `art` is ready, no Tag: caches are pickups) and the
-- placement of that look round it (Shared.DeepLayout boxes and art). Only things a tree's size break (coral,
-- small wreck props); the train cars and the factory stay.
function StreetBreak.deepDress(boxes: { any }, places: { any }, ready: { [string]: boolean }): Dress
	local out: Dress = { box = {}, mesh = {}, big = {}, count = 0 }
	local byLook: { [string]: { number } } = {}
	for j, p in places do
		local list = byLook[p.look]
		if not list then
			list = {}
			byLook[p.look] = list
		end
		table.insert(list, j)
	end
	for i, b in boxes do
		local look = b.art
		if b.kind == "prop" and b.tag == nil and type(look) == "string" and ready[look] and byLook[look] then
			local fx, fz = halfXZ(b.sx, b.sz, b.ry)
			if StreetBreak.groupKind(fx * 2, b.sy, fz * 2) == "whole" then
				local best, bestD = nil, math.huge
				for _, j in byLook[look] do
					local p = places[j]
					local d = (p.cx - b.cx) ^ 2 + (p.cy - b.cy) ^ 2 + (p.cz - b.cz) ^ 2
					local reach = math.max(p.sx, p.sy, p.sz)
					if d < bestD and d <= reach * reach then
						best, bestD = j, d
					end
				end
				if best then
					local key = "D" .. best
					out.box[i] = key
					if not out.mesh[best] then
						out.mesh[best] = key
						out.count += 1
					end
				end
			end
		end
	end
	return out
end

return StreetBreak
