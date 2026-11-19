--!strict
-- HideoutKit: the HQ room shells dressed in Blender modules (the hideout art pass, 2026-11-19; art/blender/hideout.py,
-- imported as ReplicatedStorage.Art.Hideout; each mesh's size, centre, colour and baked texture set is
-- Config.HideoutArt). Pure, so Lune checks it. Where each module goes over today's plain parts, which stay (hidden)
-- so every collision, prompt, light and glowing face is as before; a look shows only once all its meshes are
-- imported (Shared.SetPieceKit's rule), else the parts draw as today.
-- * cell(Config, pieces, preset): the Vigil's Safehouse (Shared.HqRules.hideout): wall bays, floor and ceiling
--   tiles, the shaft's panels, pillars, pilasters, beam bays, the wall kit's runs (pipes, cable tray, stripe) and
--   caged lamps, the service stair, the city map wall's frame and the monitors' housings. The glowing faces (lamps,
--   the map's screen and districts, the monitors' screens) stay parts.
-- * foundry(Config, preset): the Dread Syndicate's Foundry box room (HqClient buildRoom): iron wall bays, diamond
--   plate floor tiles round the rug and rug tiles in the side's colour; the light bands stay parts.
-- * stairHead(): the plaza stairwell head (HqService): one look over its parts (Head, Roof, Frame, Stripe, Plate
--   and the door, which keeps its prompt); the lamp stays a part.
-- * runs(list, run, at): the wall kit's run modules for any run (also mission 2's tunnels, PocketLayout).
-- A module is a placement with a `scale` (SetPieceKit.Place): repeated along a wall or floor of any length, each
-- stretched a little to fit (never more than a few percent on the HQ's own walls).

local SetPieceKit = if script then require(script.Parent.SetPieceKit) else (require :: any)("./SetPieceKit")

local HideoutKit = {}

export type Place = SetPieceKit.Place

HideoutKit.MODULE = 12 -- a wall, beam, run or panel module's length
HideoutKit.TILE = 24 -- a floor or ceiling tile's side (the Foundry's trim tiles are 22.4)

-- each module's own size as built (art/blender/hideout.py): x along, y up, z deep
HideoutKit.SIZE = {
	HideWall = { 12, 30, 2 },
	HidePanel = { 12, 12, 1 },
	HidePillar = { 4, 30, 4 },
	HidePilaster = { 4, 30, 3 },
	HideBeam = { 12, 2, 3 },
	HideFloor = { 24, 0.2, 24 },
	HideCeiling = { 24, 1, 24 },
	HideRun = { 12, 1, 1 }, -- (scaled along x only)
	FoundryWall = { 12, 30, 2 },
	FoundryFloor = { 22.4, 0.2, 22.4 },
	FoundryRug = { 24, 0.25, 24 },
} :: { [string]: { number } }

-- What each hideout piece is drawn as (pieces not named stay parts: the glowing lamp faces, map screen and
-- districts, monitor screens); `cover` pieces are hidden by their group's look (the wall kit's run, the stair)
HideoutKit.PIECES = {
	wall = "HideWall",
	floor = "HideFloor",
	ceiling = "HideCeiling",
	shaft = "HidePanel", -- (its lid: a ceiling tile)
	pillar = "HidePillar",
	pilaster = "HidePilaster",
	beam = "HideBeam",
	pipe = "HideRun",
	cableTray = "HideRun",
	stripe = "HideRun",
	lampHousing = "HideLamp",
	stairStep = "HideStair",
	stairNosing = "HideStair",
	stairRail = "HideStair",
	stairPost = "HideStair",
	mapBoard = "HideMapFrame",
	monitorBezel = "HideMonitor",
} :: { [string]: string }

-- The stairwell head's parts its look stands in for (HqService makeServiceDoor's names); the lamp stays
HideoutKit.HEAD = "HideStairHead"
HideoutKit.HEAD_PARTS = { "Head", "Roof", "Frame", "Stripe", "Plate", "HqDoor_hero" }

-- The turn about up (degrees) that faces a look's front (-z) toward the room's middle from (x, z), for a piece
-- thin along x (`alongZ`) or along z
local function faceIn(x: number, z: number, alongZ: boolean): number
	if alongZ then
		return if x < 0 then -90 else 90
	end
	return if z > 0 then 0 else 180
end

-- n modules of `look` along a box (x, y, z the middle; sx, sy, sz) thin along x or z: their feet on the face
-- toward the room's middle, at the box's foot, each stretched to the box's length, height and depth
local function along(
	out: { Place },
	look: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number
): number
	local m = HideoutKit.SIZE[look]
	local alongZ = sx < sz
	local len = if alongZ then sz else sx
	local thick = if alongZ then sx else sz
	local n = math.max(1, math.floor(len / m[1] + 0.5))
	local ry = faceIn(x, z, alongZ)
	local first = #out + 1
	local foot = y - sy / 2
	for i = 1, n do
		local t = -len / 2 + (i - 0.5) * len / n
		local px, pz
		if alongZ then
			px, pz = x - (if x < 0 then -1 else 1) * thick / 2, z + t
		else
			px, pz = x + t, z - (if z > 0 then 1 else -1) * thick / 2
		end
		table.insert(out, {
			look = look,
			x = px,
			y = foot,
			z = pz,
			ry = ry,
			scale = { len / n / m[1], sy / m[2], thick / m[3] },
		})
	end
	return first
end

-- Tiles of `look` over a flat box (its underside the tiles' feet): returns the first tile's index
local function tiles(
	out: { Place },
	look: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	tint: { [string]: { number } }?
): number
	local m = HideoutKit.SIZE[look]
	local nx = math.max(1, math.floor(sx / m[1] + 0.5))
	local nz = math.max(1, math.floor(sz / m[3] + 0.5))
	local first = #out + 1
	for i = 1, nx do
		for j = 1, nz do
			table.insert(out, {
				look = look,
				x = x - sx / 2 + (i - 0.5) * sx / nx,
				y = y - sy / 2,
				z = z - sz / 2 + (j - 0.5) * sz / nz,
				ry = 0,
				scale = { sx / nx / m[1], sy / m[2], sz / nz / m[3] },
				tint = tint,
			})
		end
	end
	return first
end

-- The wall kit's run modules (HideRun) along one run (HqRules.Run), offset by (ox, oy, oz) (a pocket's middle):
-- returns the first module's index and the count
function HideoutKit.runs(out: { Place }, run: any, ox: number?, oy: number?, oz: number?): (number, number)
	local n = math.max(1, math.floor(run.len / HideoutKit.MODULE + 0.5))
	local a = math.rad(run.ry)
	local ux, uz = math.cos(a), -math.sin(a) -- the look's own x after its turn
	local first = #out + 1
	for i = 1, n do
		local t = -run.len / 2 + (i - 0.5) * run.len / n
		table.insert(out, {
			look = "HideRun",
			x = (ox or 0) + run.x + ux * t,
			y = oy or 0,
			z = (oz or 0) + run.z + uz * t,
			ry = run.ry,
			scale = { run.len / n / HideoutKit.MODULE, 1, 1 },
		})
	end
	return first, n
end

-- Looks a preset leaves as parts (Config.Hq.art.skip): phones keep the ceiling and the beams plain
local function skipped(Config: any, preset: string?): { [string]: boolean }
	local A = Config.Hq.art
	return (A and A.skip and A.skip[preset or "medium"]) or {}
end

-- The Safehouse: placements (cell offsets) and, for each piece index, the placement it hides under
function HideoutKit.cell(Config: any, pieces: { any }, preset: string?): ({ Place }, { [number]: number })
	local out: { Place } = {}
	local hides: { [number]: number } = {}
	local skip = skipped(Config, preset)
	local runs: { [any]: number } = {}
	local stair: number? = nil
	for i, p in pieces do
		local look = HideoutKit.PIECES[p.name]
		if look and skip[look] then
			continue
		end
		if look == "HideRun" and p.run then
			local k = runs[p.run]
			if not k then
				k = HideoutKit.runs(out, p.run)
				runs[p.run] = k
			end
			hides[i] = k
		elseif look == "HideStair" then
			if not stair then
				-- its foot: the first step's foot middle (the steps climb along +x)
				local x0, zc, depth = math.huge, 0, 8
				for _, q in pieces do
					if q.name == "stairStep" and q.x - q.sx / 2 < x0 then
						x0, zc, depth = q.x - q.sx / 2, q.z, q.sz
					end
				end
				table.insert(out, { look = look, x = x0, y = 0, z = zc, ry = 0, scale = { 1, 1, depth / 8 } })
				stair = #out
			end
			hides[i] = stair :: number
		elseif look == "HideWall" then
			hides[i] = along(out, look, p.x, p.y, p.z, p.sx, p.sy, p.sz)
		elseif look == "HidePanel" then
			if p.sy < math.min(p.sx, p.sz) then -- the shaft's lid
				if not skip.HideCeiling then
					hides[i] = tiles(out, "HideCeiling", p.x, p.y, p.z, p.sx, p.sy, p.sz)
				end
			else
				hides[i] = along(out, look, p.x, p.y, p.z, p.sx, p.sy, p.sz)
			end
		elseif look == "HideFloor" or look == "HideCeiling" then
			hides[i] = tiles(out, look, p.x, p.y, p.z, p.sx, p.sy, p.sz)
		elseif look == "HidePillar" then
			table.insert(out, {
				look = look,
				x = p.x,
				y = p.y - p.sy / 2,
				z = p.z,
				ry = 0,
				scale = { p.sx / 4, p.sy / 30, p.sz / 4 },
			})
			hides[i] = #out
		elseif look == "HidePilaster" then
			local alongZ = p.sx < p.sz
			local w, d = if alongZ then p.sz else p.sx, if alongZ then p.sx else p.sz
			local ry = if alongZ then (if p.x > 0 then 90 else -90) else (if p.z > 0 then 0 else 180)
			table.insert(out, {
				look = look,
				x = p.x,
				y = p.y - p.sy / 2,
				z = p.z,
				ry = ry,
				scale = { w / 4, p.sy / 30, d / 3 },
			})
			hides[i] = #out
		elseif look == "HideBeam" then
			local m = HideoutKit.SIZE.HideBeam
			local n = math.max(1, math.floor(p.sx / m[1] + 0.5))
			hides[i] = #out + 1
			for k = 1, n do
				table.insert(out, {
					look = look,
					x = p.x - p.sx / 2 + (k - 0.5) * p.sx / n,
					y = p.y - p.sy / 2,
					z = p.z,
					ry = 0,
					scale = { p.sx / n / m[1], p.sy / m[2], p.sz / m[3] },
				})
			end
		elseif look == "HideLamp" then
			table.insert(out, { look = look, x = p.x, y = p.y, z = p.z, ry = if p.run then p.run.ry else 0 })
			hides[i] = #out
		elseif look == "HideMapFrame" or look == "HideMonitor" then
			table.insert(out, { look = look, x = p.x, y = p.y, z = p.z, ry = faceIn(p.x, p.z, p.sx < p.sz) })
			hides[i] = #out
		end
	end
	return out, hides
end

-- The Foundry's box room as HqClient draws it (cell offsets): the floor's trim and rug and the four walls, by
-- name; and their modules (the rug's tiles tinted `main`)
export type Box = { name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number }
function HideoutKit.foundryBoxes(Config: any): { Box }
	local s = Config.Hq.cell.size
	local half = s / 2
	return {
		{ name = "trim", x = 0, y = 0.15, z = 0, sx = s - 8, sy = 0.2, sz = s - 8 },
		{ name = "rug", x = 0, y = 0.2, z = 0, sx = s - 24, sy = 0.25, sz = s - 24 },
		{ name = "wall", x = 0, y = 15, z = -half, sx = s, sy = 30, sz = 2 },
		{ name = "wall", x = -half, y = 15, z = 0, sx = 2, sy = 30, sz = s },
		{ name = "wall", x = 0, y = 15, z = half, sx = s, sy = 30, sz = 2 },
		{ name = "wall", x = half, y = 15, z = 0, sx = 2, sy = 30, sz = s },
	}
end

function HideoutKit.foundry(Config: any, main: { number }, preset: string?): ({ Place }, { [number]: number })
	local out: { Place } = {}
	local hides: { [number]: number } = {}
	local skip = skipped(Config, preset)
	for i, b in HideoutKit.foundryBoxes(Config) do
		if b.name == "wall" and not skip.FoundryWall then
			hides[i] = along(out, "FoundryWall", b.x, b.y, b.z, b.sx, b.sy, b.sz)
		elseif b.name == "trim" and not skip.FoundryFloor then
			hides[i] = tiles(out, "FoundryFloor", b.x, b.y, b.z, b.sx, b.sy, b.sz)
		elseif b.name == "rug" and not skip.FoundryRug then
			hides[i] = tiles(out, "FoundryRug", b.x, b.y, b.z, b.sx, b.sy, b.sz, { FoundryRugBody = main })
		end
	end
	return out, hides
end

-- The plaza stairwell head: one placement at its foot (HqService's `cf`: the door side is the look's front)
function HideoutKit.stairHead(): Place
	return { look = HideoutKit.HEAD, x = 0, y = 0, z = 0, ry = 0 }
end

-- Every look this kit places (the fit table must hold each)
function HideoutKit.looks(): { [string]: boolean }
	local out = { [HideoutKit.HEAD] = true, FoundryWall = true, FoundryFloor = true, FoundryRug = true }
	for _, look in HideoutKit.PIECES do
		out[look] = true
	end
	out.HideCeiling = true
	return out
end

-- Mesh parts and triangles a set of placements draws (the budget test and HqClient's preset check)
function HideoutKit.cost(Config: any, places: { Place }): (number, number)
	local parts, tris = 0, 0
	for _, pl in places do
		local fit = SetPieceKit.fit(Config, pl.look)
		for _, f in fit or {} do
			parts += 1
			tris += f.tris or 0
		end
	end
	return parts, tris
end

return HideoutKit
