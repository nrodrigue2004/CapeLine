--!strict
-- LitPlan: where the lit-window picture goes on a building face (shapes-2, 2026-11-19; Fx.LitWindows draws it).
-- Pure, so Lune checks it. A kit front tiles from the part's centre (object space: art/blender/block.py renders the
-- fronts that way, and art/city/litwindows.py draws each front's lit picture from the same window rectangles), so
-- the picture's tiles must start at the face's centre too: one tile's bottom-left corner on the face's middle.
-- * layout(w, h, block, pps): a face w x h studs, the picture covering `block` studs a tile, `pps` pixels a stud
--   -> { cw, ch (the canvas in px), x, y (the tiled label's top-left in px, at or left/above 0), sw, sh (its size),
--   tile (px) }: tile edges fall on the canvas's centre lines, and the label covers the whole canvas.
-- * faces(sx, sy, sz, min): the side faces of a box at least `min` studs wide: { face, w, h }.
-- * night(clock, from, to): is it after dusk and before dawn?

local LitPlan = {}

export type Layout = { cw: number, ch: number, x: number, y: number, sw: number, sh: number, tile: number }

function LitPlan.layout(w: number, h: number, block: number, pps: number): Layout
	local cw, ch = w * pps, h * pps
	local t = block * pps
	-- the first tile edge at or left of the canvas's left edge that is a whole number of tiles from the centre
	local x = cw / 2 - math.ceil((cw / 2) / t) * t
	local y = ch / 2 - math.ceil((ch / 2) / t) * t
	return { cw = cw, ch = ch, x = x, y = y, sw = cw - x, sh = ch - y, tile = t }
end

function LitPlan.faces(
	sx: number,
	sy: number,
	sz: number,
	min: number
): { { face: string, w: number, h: number } }
	local out = {}
	if sx >= min then
		table.insert(out, { face = "Front", w = sx, h = sy })
		table.insert(out, { face = "Back", w = sx, h = sy })
	end
	if sz >= min then
		table.insert(out, { face = "Left", w = sz, h = sy })
		table.insert(out, { face = "Right", w = sz, h = sy })
	end
	return out
end

function LitPlan.night(clock: number, from: number, to: number): boolean
	return clock >= from or clock < to
end

return LitPlan
