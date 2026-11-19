--!strict
-- StreetBreak: which street things a device knocks loose and how a long one breaks (fix-destroy, 2026-11-19, nate:
-- "I literally want everything destructible"). Pure, so Lune checks it; BuildingFx.smashStreet uses it.
-- * kind(sx, sy, sz): "whole" (it flies off whole: trees, lamps, crates, containers, hay, poles), "long" (a fence or
--   a low wall: broken only where it was hit, segments) or nil (too big: ground pads, rock bases, crane legs).
-- * segments(box, at, r, len): a long part as short lengths along its long side, each marked broken when it is
--   within r of the hit, or nil when it is not long.

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

return StreetBreak
