-- ThumbMap: which picture a tile shows (2026-11-19, the creator, shop and HQ thumbnails). Pure: Lune runs it.
-- Our own art is packed into 1024 x 1024 sheets of 128 px cells (art/thumbs/thumbs.py renders and packs them,
-- Config.Thumbs holds each sheet's uploaded image id and each tile key's cell). Catalog items are never drawn by
-- us (nate's rule): a catalog face's tile shows the catalog face's own image (Config.CatalogLooks), catalog hair
-- keeps its text tile with a hair glyph. A cell whose sheet id is still 0 has no picture: the tile stays text.
-- Keys: "<creator tab>/<kit>" for a creator piece, "weapon/<id>", "shop/<shop key>", "emote/<bit>",
-- "travel/<style id>", "tint/<index>", "style/<gear slot>" (HQ Gizmo styles by slot), "trophy/<index>".

local ThumbMap = {}

export type Pic = {
	image: string, -- "rbxassetid://<id>"
	x: number, -- ImageRectOffset (0, 0 and 0 size for a whole image)
	y: number,
	w: number, -- ImageRectSize
	h: number,
	catalog: boolean?, -- a Roblox catalog item's own image (never our drawing)
}

-- the creator piece's tile key, or nil for a Roblox catalog piece (kit "cat:<id>")
function ThumbMap.creatorKey(_Config: any, p: { tab: string, kit: string }): string?
	if string.sub(p.kit, 1, 4) == "cat:" then
		return nil
	end
	return p.tab .. "/" .. p.kit
end

function ThumbMap.weaponKey(id: number): string
	return "weapon/" .. tostring(id)
end

-- the cell of a tile key: sheet number (1-based), column and row (0-based), or nil
function ThumbMap.cell(Config: any, key: string): (number?, number?, number?)
	local T = Config.Thumbs
	local n = T and T.cells[key]
	if not n then
		return nil, nil, nil
	end
	local perSheet = T.per * T.per
	local sheet = (n - 1) // perSheet + 1
	local i = (n - 1) % perSheet
	return sheet, i % T.per, i // T.per
end

-- the picture for a tile key, or nil while its sheet is not uploaded (or it has no cell)
function ThumbMap.pic(Config: any, key: string?): Pic?
	if not key then
		return nil
	end
	local T = Config.Thumbs
	if not T or T.on ~= true then
		return nil
	end
	local sheet, cx, cy = ThumbMap.cell(Config, key)
	local id = sheet and T.sheets[sheet] or 0
	if not sheet or id == 0 then
		return nil
	end
	return {
		image = "rbxassetid://" .. tostring(id),
		x = (cx :: number) * T.cell,
		y = (cy :: number) * T.cell,
		w = T.cell,
		h = T.cell,
	}
end

-- a catalog face's own image (Config.CatalogLooks.faces rows: name, face asset id, its image id)
function ThumbMap.catalogFace(Config: any, kit: string): Pic?
	local id = tonumber(string.match(kit, "^cat:(%d+)$") or "")
	if not id then
		return nil
	end
	for _, row in Config.CatalogLooks.faces do
		if row[2] == id and (row[3] or 0) ~= 0 then
			return { image = "rbxassetid://" .. tostring(row[3]), x = 0, y = 0, w = 0, h = 0, catalog = true }
		end
	end
	return nil
end

-- what a creator piece's tile shows: its cell, a catalog face's image, or nil (the text tile)
function ThumbMap.creator(Config: any, p: { tab: string, kit: string }): Pic?
	if p.tab == "visage" then
		return ThumbMap.catalogFace(Config, p.kit)
	end
	return ThumbMap.pic(Config, ThumbMap.creatorKey(Config, p))
end

-- a glyph for a text tile that has no picture (catalog hair, voices)
ThumbMap.GLYPHS = { hair = "✂", voice = "♪" }

return ThumbMap
