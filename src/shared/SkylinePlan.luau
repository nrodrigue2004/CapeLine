--!strict
-- SkylinePlan: the far skyline (2026-11-21, nate's playtest: "i can see the boss and i can see the park from really
-- far but not the buildings or skyscrapers. Thats way more importnat", and "windows should appear from further
-- away"). The hub's buildings stream (Workspace StreamingEnabled, Atomic chunk models), so past the streaming radius
-- a device had no buildings at all. Each device now draws a cheap stand-in (Fx.FarSkyline) for every hub building
-- whose real model is not streamed in: its body boxes and its crown (setbacks, spire, lantern, mast) in the body's own
-- kit texture and colour, plus a few window bands (glass by day, lit by night) so the windows read from far.
-- Pure: the server packs the list from WorldMap.build's boxes (CityBuilder.publishInfo, ReplicatedStorage.SkylineInfo,
-- JSON), the device unpacks it and asks for each building's boxes under its preset's budget (Config.Presets far).
-- Lune checks the list, the part counts per preset and the clipping of a damaged building.

local SkylinePlan = {}

-- piece flags
SkylinePlan.ROUND = 1 -- a cylinder (the Foundry's stacks, spires, masts)
SkylinePlan.CROWN = 2 -- above the shaft: shown only while the shaft's top storey stands
SkylinePlan.GLOW = 4 -- a lit lantern (Neon)

export type Piece = {
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	ry: number,
	color: string,
	kit: string?,
	tint: string?,
	flags: number,
}

export type Rec = {
	id: number,
	base: number,
	top: number, -- the shaft's top (BuildingState's top)
	peak: number, -- the highest piece's top (the crown's)
	pieces: { Piece },
}

-- a box the device builds: a piece, or a window band (kind "band")
export type Out = {
	kind: string, -- "body", "crown", "glow" or "band"
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	ry: number,
	color: string?,
	kit: string?,
	tint: string?,
	round: boolean,
}

local function snap(v: number): number
	return math.floor(v * 4 + 0.5) / 4
end

local function has(flags: number, bit: number): boolean
	return flags // bit % 2 == 1
end
SkylinePlan.has = has

-- Is box b one of a building's far pieces? Bodies, crown tiers and lanterns; a round body's cylinder (the Foundry's
-- stacks are "prop" cylinders). Window bands, ledges, roofs, awnings and roof props are left out (too small far away).
local function isPiece(b: any, round: boolean): boolean
	if b.ghost then
		return false
	end
	if b.kind == "building" or b.kind == "tier" or b.kind == "glow" then
		return true
	end
	return round and b.kind == "prop" and b.shape == "cylinder"
end

-- Every hub building's far pieces from a world (WorldMap.build): the outskirts are left out (low houses and barns,
-- 2,000+ of them, each an Atomic tile model of its own). Ordered by id.
function SkylinePlan.collect(_Config: any, world: any): { Rec }
	local recs: { [number]: Rec } = {}
	local round: { [number]: boolean } = {}
	for _, b in world.buildings do
		if b.district ~= "Outskirts" then
			recs[b.id] = { id = b.id, base = b.base, top = b.top, peak = b.top, pieces = {} }
			round[b.id] = b.round == true
		end
	end
	for _, b in world.hubBoxes do
		local r = b.bid and recs[b.bid]
		if r and isPiece(b, round[b.bid]) then
			local flags = 0
			if b.shape == "cylinder" then
				flags += SkylinePlan.ROUND
			end
			if b.crown then
				flags += SkylinePlan.CROWN
			end
			if b.kind == "glow" then
				flags += SkylinePlan.GLOW
			end
			table.insert(r.pieces, {
				cx = snap(b.cx),
				cy = snap(b.cy),
				cz = snap(b.cz),
				sx = snap(b.sx),
				sy = snap(b.sy),
				sz = snap(b.sz),
				ry = b.ry or 0,
				color = b.color,
				kit = b.kit,
				tint = b.tint,
				flags = flags,
			})
			r.peak = math.max(r.peak, b.cy + b.sy / 2)
		end
	end
	local out = {}
	for _, r in recs do
		if #r.pieces > 0 then
			table.insert(out, r)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- The list as plain JSON-able arrays (names once each): { v, names, b = { { id, base, top, peak, piece... } } },
-- a piece 11 numbers: cx cy cz sx sy sz ry color kit tint flags (kit and tint 0: none)
function SkylinePlan.pack(list: { Rec }): any
	local names: { string } = {}
	local index: { [string]: number } = {}
	local function nameOf(s: string?): number
		if not s then
			return 0
		end
		local i = index[s]
		if not i then
			table.insert(names, s)
			i = #names
			index[s] = i
		end
		return i
	end
	local rows = {}
	for _, r in list do
		local row: { number } = { r.id, r.base, r.top, r.peak } -- (exact: BuildingFx's standing top is measured from them)
		for _, p in r.pieces do
			for _, v in
				{
					p.cx,
					p.cy,
					p.cz,
					p.sx,
					p.sy,
					p.sz,
					p.ry,
					nameOf(p.color),
					nameOf(p.kit),
					nameOf(p.tint),
					p.flags,
				}
			do
				table.insert(row, v)
			end
		end
		table.insert(rows, row)
	end
	return { v = 1, names = names, b = rows }
end

-- Back from pack (a device; anything malformed is skipped)
function SkylinePlan.unpack(data: any): { Rec }
	local out: { Rec } = {}
	if type(data) ~= "table" or type(data.names) ~= "table" or type(data.b) ~= "table" then
		return out
	end
	local names = data.names
	local function name(i: any): string?
		return if type(i) == "number" and i > 0 then names[i] else nil
	end
	for _, row in data.b do
		if type(row) ~= "table" or #row < 15 or (#row - 4) % 11 ~= 0 then
			continue
		end
		local ok = true
		for _, v in row do
			if type(v) ~= "number" then
				ok = false
				break
			end
		end
		if not ok then
			continue
		end
		local r: Rec = { id = row[1], base = row[2], top = row[3], peak = row[4], pieces = {} }
		for i = 5, #row, 11 do
			table.insert(r.pieces, {
				cx = row[i],
				cy = row[i + 1],
				cz = row[i + 2],
				sx = row[i + 3],
				sy = row[i + 4],
				sz = row[i + 5],
				ry = row[i + 6],
				color = name(row[i + 7]) or "concrete",
				kit = name(row[i + 8]),
				tint = name(row[i + 9]),
				flags = row[i + 10],
			})
		end
		table.insert(out, r)
	end
	return out
end

-- How many window bands each building gets under a preset's budget (far = Config.Presets <p>.far: parts, bands,
-- bandMin): every piece of every building first, then bands to the tallest buildings first until the part cap.
-- Returns id -> bands and the parts it comes to.
function SkylinePlan.budget(list: { Rec }, far: any): ({ [number]: number }, number)
	local parts = 0
	for _, r in list do
		parts += #r.pieces
	end
	local out: { [number]: number } = {}
	local tall = {}
	for _, r in list do
		out[r.id] = 0
		if r.top - r.base >= far.bandMin then
			table.insert(tall, r)
		end
	end
	table.sort(tall, function(a, b)
		local ha, hb = a.top - a.base, b.top - b.base
		if ha ~= hb then
			return ha > hb
		end
		return a.id < b.id
	end)
	for _, r in tall do
		local want = SkylinePlan.bandCount(r, far)
		local bodies = 0
		for _, p in r.pieces do
			if p.flags == 0 then
				bodies += 1
			end
		end
		local cost = want * bodies
		if cost <= 0 then
			continue
		end
		if parts + cost > far.parts then
			-- what is left of the cap, whole bands only
			local fit = if bodies > 0 then (far.parts - parts) // bodies else 0
			if fit > 0 then
				out[r.id] = fit
				parts += fit * bodies
			end
			continue
		end
		out[r.id] = want
		parts += cost
	end
	return out, parts
end

-- The bands a building wants: one every `step` studs of its shaft (Config.City.far), at most the preset's `bands`
function SkylinePlan.bandCount(r: Rec, far: any, step: number?): number
	local h = r.top - r.base
	if h < (far.bandMin or 0) then
		return 0
	end
	local n = math.floor((h - 8) / (step or far.step or 24))
	return math.clamp(n, 0, far.bands or 0)
end

-- The boxes to build for a building now. bands: its share (budget); top: the top of what still stands (a Damaged
-- building's, Structure.standingTop; its rec.top when whole); crown: whether the crown still stands. A piece above the
-- standing top goes and one through it is cut there; bands are spread over what stands. F: Config.City.far.
function SkylinePlan.boxes(r: Rec, bands: number, top: number, crown: boolean, F: any): { Out }
	local out: { Out } = {}
	local standing = math.min(top, r.top)
	for _, p in r.pieces do
		local isCrown = has(p.flags, SkylinePlan.CROWN)
		if isCrown and (not crown or standing < r.top - 0.01) then
			continue
		end
		local y0, y1 = p.cy - p.sy / 2, p.cy + p.sy / 2
		if not isCrown and y1 > standing then
			y1 = standing
		end
		if y1 - y0 < 0.5 then
			continue
		end
		table.insert(out, {
			kind = if has(p.flags, SkylinePlan.GLOW) then "glow" elseif isCrown then "crown" else "body",
			cx = p.cx,
			cy = (y0 + y1) / 2,
			cz = p.cz,
			sx = p.sx,
			sy = y1 - y0,
			sz = p.sz,
			ry = p.ry,
			color = p.color,
			kit = p.kit,
			tint = p.tint,
			round = has(p.flags, SkylinePlan.ROUND),
		})
	end
	if bands <= 0 then
		return out
	end
	local h = standing - r.base
	local n = math.min(bands, math.floor((h - 8) / (F.minStep or 10)))
	if n <= 0 then
		return out
	end
	-- evenly up the standing shaft, a band `thick` share of its spacing tall
	local gap = (h - 8) / (n + 0.5)
	local thick = math.clamp(gap * F.thick, F.minThick, F.maxThick)
	for _, p in r.pieces do
		if p.flags ~= 0 then
			continue -- (round bodies and crowns carry no bands)
		end
		local y0, y1 = p.cy - p.sy / 2, math.min(p.cy + p.sy / 2, standing)
		for k = 1, n do
			local y = r.base + 6 + gap * (k - 0.5) + thick / 2
			if y - thick / 2 >= y0 and y + thick / 2 <= y1 - 1 then
				table.insert(out, {
					kind = "band",
					cx = p.cx,
					cy = y,
					cz = p.cz,
					sx = p.sx + F.out * 2,
					sy = thick,
					sz = p.sz + F.out * 2,
					ry = p.ry,
					round = false,
				})
			end
		end
	end
	return out
end

-- Should a building's stand-in show? Not while its real model is streamed in, nor once it collapsed (its rubble
-- heap is drawn with the real model). state: BuildingState's (0 intact, 1 damaged, 2 collapsed).
function SkylinePlan.shows(present: boolean, state: number): boolean
	return not present and state ~= 2
end

return SkylinePlan
