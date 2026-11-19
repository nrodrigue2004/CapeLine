--!strict
-- LoreBookKit: the lore page's book as plain geometry (side-content, 2026-11-19; Config.Lore.look). Pure, so the
-- device (LoreClient, HqClient's Lore Shelf) and the Blender preview (art/blender/lorebook.py, which renders this
-- same list from `lune run art/lore/book.luau`) build the very same book.
-- The book stands open toward you, its two halves hinged at the spine and opened 140 degrees, a fat block of cream
-- pages in each half with ruled lines of text, gold corner caps and a gold clasp disc, a red ribbon hanging from the
-- spine, and a glowing Spark star turning over it. Studs; +y up, the book faces -z (toward the viewer at -z).
-- PLACEHOLDER ART: parts (wedges, cylinders and blocks) until a Blender book mesh is uploaded.

local LoreBookKit = {}

export type Piece = {
	name: string,
	shape: string, -- "block", "cylinder" (along x, as Roblox), "ball", "wedge"
	size: { number }, -- x, y, z
	pos: { number }, -- x, y, z from the book's middle
	rot: { number }, -- degrees about x, y, z (applied y, then x, then z: CFrame.fromEulerAnglesYXZ)
	color: string, -- "cover", "page", "gold", "glow", "ribbon", "ink", "spine"
	material: string, -- "plastic", "neon", "metal", "fabric"
	alpha: number?, -- transparency
	spin: boolean?, -- turns with the star (the glow pieces)
}

local OPEN = 20 -- degrees each half turns back from flat (140 between the covers)
local W, H = 1.45, 2.0 -- a half's width and height
local COVER_T, PAGE_T = 0.12, 0.26

-- A point on a half (side -1 left, +1 right): u studs out from the spine, v up, w in front of the cover
local function onHalf(side: number, u: number, v: number, w: number): ({ number }, { number })
	-- the half runs out from the spine along d = (side cos, 0, sin) (its outer edge swings back, away from the
	-- viewer at -z); its face looks along n = (side sin, 0, -cos), toward the viewer
	local c, s = math.cos(math.rad(OPEN)), math.sin(math.rad(OPEN))
	return { side * c * u + side * s * w, v, s * u - c * w }, { 0, -OPEN * side, 0 }
end

-- The book's pieces (one list, fresh each call)
function LoreBookKit.book(): { Piece }
	local out: { Piece } = {}
	local function add(p: Piece)
		table.insert(out, p)
	end
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		-- the cover board
		local pos, rot = onHalf(side, W / 2 + 0.05, 0, 0)
		add({
			name = "Cover" .. tag,
			shape = "block",
			size = { W + 0.1, H + 0.16, COVER_T }, -- a coloured rim shows round the pages
			pos = pos,
			rot = rot,
			color = "cover",
			material = "fabric",
		})
		-- the page block, a little smaller, in front of the board
		pos, rot = onHalf(side, W / 2 - 0.02, 0, COVER_T / 2 + PAGE_T / 2)
		add({
			name = "Pages" .. tag,
			shape = "block",
			size = { W - 0.14, H - 0.2, PAGE_T },
			pos = pos,
			rot = rot,
			color = "page",
			material = "plastic",
		})
		-- the ruled lines of text on the page
		for k = 1, 5 do
			local v = 0.62 - (k - 1) * 0.3
			local len = if k == 5 then 0.6 else 0.95
			pos, rot = onHalf(side, 0.2 + len / 2, v, COVER_T / 2 + PAGE_T + 0.006)
			add({
				name = string.format("Line%s%d", tag, k),
				shape = "block",
				size = { len, 0.05, 0.012 },
				pos = pos,
				rot = rot,
				color = "ink",
				material = "plastic",
			})
		end
		-- gold corner caps on the outer corners
		for _, v in { H / 2 - 0.1, -(H / 2 - 0.1) } do
			pos, rot = onHalf(side, W - 0.1, v, 0)
			add({
				name = "Corner" .. tag .. (if v > 0 then "T" else "B"),
				shape = "block",
				size = { 0.26, 0.26, COVER_T + 0.04 },
				pos = pos,
				rot = rot,
				color = "gold",
				material = "metal",
			})
		end
	end
	-- the rounded spine, and its gold bands
	add({
		name = "Spine",
		shape = "cylinder",
		size = { H + 0.04, 0.3, 0.3 },
		pos = { 0, 0, 0.06 },
		rot = { 0, 0, 90 },
		color = "spine",
		material = "fabric",
	})
	for _, v in { H / 2 - 0.18, -(H / 2 - 0.18) } do
		add({
			name = "Band" .. (if v > 0 then "T" else "B"),
			shape = "cylinder",
			size = { 0.08, 0.34, 0.34 },
			pos = { 0, v, 0.06 },
			rot = { 0, 0, 90 },
			color = "gold",
			material = "metal",
		})
	end
	-- the gold clasp disc on the right page's outer edge, and the ribbon hanging from the spine
	local cpos, crot = onHalf(1, W - 0.02, 0, COVER_T / 2 + PAGE_T / 2)
	add({
		name = "Clasp",
		shape = "cylinder",
		size = { 0.1, 0.42, 0.42 },
		pos = cpos,
		rot = { crot[1], crot[2] + 90, crot[3] },
		color = "gold",
		material = "metal",
	})
	add({
		name = "Ribbon",
		shape = "block",
		size = { 0.12, 0.9, 0.02 },
		pos = { 0.05, -H / 2 - 0.3, -0.02 },
		rot = { 0, 0, -8 },
		color = "ribbon",
		material = "fabric",
	})
	add({
		name = "RibbonTip",
		shape = "wedge",
		size = { 0.02, 0.18, 0.12 },
		pos = { 0.11, -H / 2 - 0.82, -0.02 },
		rot = { 0, 90, -8 },
		color = "ribbon",
		material = "fabric",
	})
	-- the Spark star turning over the book: a glowing core and two crossed rays, and a soft halo behind the book
	add({
		name = "StarCore",
		shape = "ball",
		size = { 0.42, 0.42, 0.42 },
		pos = { 0, H / 2 + 0.75, 0 },
		rot = { 0, 0, 0 },
		color = "glow",
		material = "neon",
		spin = true,
	})
	for k, r in { 0, 90 } do
		add({
			name = "StarRay" .. k,
			shape = "block",
			size = { 0.9, 0.12, 0.12 },
			pos = { 0, H / 2 + 0.75, 0 },
			rot = { 0, r, 45 },
			color = "glow",
			material = "neon",
			spin = true,
		})
	end
	add({
		name = "Halo",
		shape = "cylinder",
		size = { 0.05, 3.0, 3.0 },
		pos = { 0, 0.1, 0.7 },
		rot = { 0, 90, 0 },
		color = "glow",
		material = "neon",
		alpha = 0.88,
	})
	return out
end

-- The pieces' colours from Config.Lore.look for a district (each { r, g, b })
function LoreBookKit.colors(look: any, district: string?): { [string]: { number } }
	local cover = look.cover[district or ""] or look.cover.Downtown
	return {
		cover = cover,
		spine = { math.floor(cover[1] * 0.7), math.floor(cover[2] * 0.7), math.floor(cover[3] * 0.7) },
		page = look.page,
		gold = look.gold,
		glow = look.glow,
		ribbon = { 200, 40, 50 },
		ink = { 70, 60, 70 },
	}
end

-- The pieces' bounds (the Blender preview frames it; the tests check the book's size)
function LoreBookKit.bounds(pieces: { Piece }): ({ number }, { number })
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, p in pieces do
		local r = math.max(p.size[1], p.size[2], p.size[3]) / 2
		for i = 1, 3 do
			lo[i] = math.min(lo[i], p.pos[i] - r)
			hi[i] = math.max(hi[i], p.pos[i] + r)
		end
	end
	return lo, hi
end

-- The Lore Shelf (Config.Hq.props 23): a short bookcase and one closed book a district, spines out, on two shelves;
-- `have` lists the districts whose set is done (those books glow). Studs from the shelf's foot, facing -z.
function LoreBookKit.shelf(districts: { string }, have: { [string]: boolean }): { Piece }
	local out: { Piece } = {}
	local wood = "spine"
	local function add(p: Piece)
		table.insert(out, p)
	end
	local width, height, depth = 6.4, 5.2, 1.4
	add({
		name = "Back",
		shape = "block",
		size = { width, height, 0.2 },
		pos = { 0, height / 2, 0.6 },
		rot = { 0, 0, 0 },
		color = wood,
		material = "plastic",
	})
	for _, x in { -width / 2, width / 2 } do
		add({
			name = "Side",
			shape = "block",
			size = { 0.25, height, depth },
			pos = { x, height / 2, 0 },
			rot = { 0, 0, 0 },
			color = wood,
			material = "plastic",
		})
	end
	for k, y in { 0.15, 2.5, height - 0.1 } do
		add({
			name = "Shelf" .. k,
			shape = "block",
			size = { width, 0.22, depth },
			pos = { 0, y, 0 },
			rot = { 0, 0, 0 },
			color = wood,
			material = "plastic",
		})
	end
	local perRow = math.ceil(#districts / 2)
	for i, d in districts do
		local row = if i <= perRow then 0 else 1
		local col = if row == 0 then i - 1 else i - perRow - 1
		local tall = 1.6 + ((i * 7) % 4) * 0.12
		local x = -width / 2 + 0.55 + col * 0.95
		local y = (if row == 0 then 0.26 else 2.61) + tall / 2
		add({
			name = "Book" .. d,
			shape = "block",
			size = { 0.7, tall, 1.0 },
			pos = { x, y, -0.05 },
			rot = { 0, 0, if col % 3 == 2 then 6 else 0 },
			color = "book:" .. d,
			material = if have[d] then "neon" else "fabric",
		})
		add({
			name = "Band" .. d,
			shape = "block",
			size = { 0.72, 0.12, 1.02 },
			pos = { x, y + tall / 2 - 0.3, -0.05 },
			rot = { 0, 0, if col % 3 == 2 then 6 else 0 },
			color = "gold",
			material = "metal",
		})
	end
	return out
end

return LoreBookKit
