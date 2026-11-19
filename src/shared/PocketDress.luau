--!strict
-- PocketDress: the mission and side quest pockets' kit look (2026-11-19, the pocket kit pass; Config.PocketKit).
-- A pocket (Shared.PocketLayout) keeps every box exactly where, how big and how solid it is: the robots-stop-at-
-- walls fix, heights, doors, spawns and step points all read those boxes. The kit only
-- * looks(): sets each box's look fields (kit texture, tint, plain material: BoxKit.Box kit / tint / mat), and
-- * dress(): adds dressing that never collides, is never queried and never touches (ghost boxes): wall caps and
--   skirting, the glass shell's neon rim, each pocket's own details, comic sign boards (fixed text), lamps with
--   PointLights and kit street props (Art.Street meshes, Config.City.kit.props).
-- Every piece has a tier: 1 every device (the server builds those boxes into the pocket's model, so they stream
-- with it), 2 medium and high, 3 high only (each device builds its own on top, PocketDecor, within its preset's
-- Config.Presets <preset>.pockets budget: dressing parts, tier 1 counted, and PointLights).
-- Pure: no Roblox instances, so Lune checks it (tests "Pocket kit").

local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local PocketDress = {}

-- a sign board's face: its fixed text (Config.PocketKit signs) and ink colour (palette key)
export type Sign = { text: string, ink: string }
-- a dressing box: a ghost BoxKit box with its tier, and a sign face or a lamp's light when it is one
export type Extra = BoxKit.Box & { tier: number, sign: Sign?, mat: string? }
export type Light = {
	x: number,
	y: number,
	z: number,
	color: string,
	range: number,
	brightness: number,
	tier: number,
}
export type Prop = { name: string, x: number, y: number, z: number, ry: number, tier: number }
export type Dress = { extras: { Extra }, lights: { Light }, props: { Prop }, layout: string }

-- the look fields a dressed box may change (everything else on a box stays as PocketLayout made it)
PocketDress.LOOK_FIELDS = { kit = true, tint = true, mat = true }

local function pickFrom<T>(v: T | { T }, x: number, z: number, salt: number): T
	if type(v) == "table" then
		local list = v :: { T }
		return list[Rng.hash(20261119, math.floor(x * 4), math.floor(z * 4), salt) % #list + 1]
	end
	return v :: T
end

local function lookFor(looks: any, b: BoxKit.Box): any
	local base = b.kind .. ":" .. b.color
	if b.shape then
		local v = looks[base .. ":" .. b.shape]
		if v then
			return v
		end
	end
	if b.tag == "ceiling" then
		local v = looks[base .. ":ceiling"]
		if v then
			return v
		end
	end
	return looks[base] or looks[b.color] or looks[b.kind]
end

-- Give every box of a built pocket its kit look; returns how many boxes took one
function PocketDress.looks(Config: any, l: any, layout: string): number
	local K = Config.PocketKit.pockets[layout]
	if not K then
		return 0
	end
	local n = 0
	for _, b in l.boxes :: { BoxKit.Box } do
		local v = lookFor(K.looks, b)
		if v then
			local bb = b :: any
			if v.kit then
				bb.kit = pickFrom(v.kit, b.cx, b.cz, 1)
			end
			if v.tint then
				bb.tint = pickFrom(v.tint, b.cx, b.cz, 2)
			end
			if v.mat then
				bb.mat = v.mat
			end
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- The dressing builder: pocket-local studs (x, y, z from the pocket's centre, y from its floor)
---------------------------------------------------------------------------

type D = {
	l: any,
	K: any,
	P: any, -- Config.PocketKit
	out: Dress,
}

-- Roblox's turn about +y: local (x, z) -> world offset
local function rot(lx: number, lz: number, ry: number): (number, number)
	local t = math.rad(ry)
	return lx * math.cos(t) + lz * math.sin(t), -lx * math.sin(t) + lz * math.cos(t)
end

local function put(
	d: D,
	tier: number,
	kind: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	opts: any?
): Extra
	local o = opts or {}
	local b = BoxKit.box(d.out.extras :: any, kind, d.l.cx + x, d.l.cy + y, d.l.cz + z, sx, sy, sz, color, {
		shape = o.shape,
		ry = o.ry,
		tag = "dress",
		ghost = true,
	}) :: any
	b.tier = tier
	b.mat = o.mat
	b.kit = o.kit
	b.tint = o.tint
	b.dress = true
	return b :: Extra
end

local function light(d: D, tier: number, x: number, y: number, z: number, color: string, key: boolean?)
	local L = if key then d.P.light.key else d.P.light
	table.insert(d.out.lights, {
		x = d.l.cx + x,
		y = d.l.cy + y,
		z = d.l.cz + z,
		color = color,
		range = L.range,
		brightness = L.brightness,
		tier = tier,
	})
end

local function prop(d: D, tier: number, name: string, x: number, y: number, z: number, ry: number)
	table.insert(
		d.out.props,
		{ name = name, x = d.l.cx + x, y = d.l.cy + y, z = d.l.cz + z, ry = ry, tier = tier }
	)
end

-- A comic sign board (Config.PocketKit signs[key]): an ink outline, the coloured face with the lettering (front
-- at local -z: ry 0 faces -z, 180 faces +z, 90 faces -x, -90 faces +x) and, at tier 2, a row of bulbs along its
-- top and bottom edges like a marquee
local function sign(d: D, key: string, x: number, y: number, z: number, w: number, h: number, ry: number)
	local s = d.K.signs and d.K.signs[key]
	if not s then
		return
	end
	local S = d.P.sign
	put(d, 1, "prop", x, y, z, w + S.outline * 2, h + S.outline * 2, S.depth, "pkSignInk", { ry = ry })
	local fx, fz = rot(0, -S.depth, ry)
	local face = put(d, 1, "prop", x + fx, y, z + fz, w, h, S.depth, s.board, { ry = ry })
	face.sign = { text = s.text, ink = s.ink }
	local n = math.max(2, math.floor(w / S.bulbEvery))
	for row = -1, 1, 2 do
		for i = 0, n - 1 do
			local lx = -w / 2 + (i + 0.5) * w / n
			local bx, bz = rot(lx, -S.depth * 1.5, ry)
			put(
				d,
				2,
				"glow",
				x + bx,
				y + row * (h / 2 + S.outline / 2),
				z + bz,
				S.bulb,
				S.bulb,
				S.bulb,
				"pkBulb",
				{ shape = "ball" }
			)
		end
	end
	local lx, lz = rot(0, -8, ry)
	light(d, 1, x + lx, y - h, z + lz, "pkBulb", false)
end

-- A neon strip
local function strip(
	d: D,
	tier: number,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	c: string?
)
	put(d, tier, "glow", x, y, z, sx, sy, sz, c or d.K.accent)
end

-- Caps on wall tops and skirting at their feet, the glass shell's neon rim and lights on the small lamps: what
-- every pocket gets from its own boxes
local function generic(d: D, Config: any)
	local W = d.P.wall
	local ceilings = {}
	for _, b in d.l.boxes :: { BoxKit.Box } do
		if b.tag == "ceiling" then
			table.insert(ceilings, b)
		end
	end
	local function underCeiling(b: BoxKit.Box, top: number): boolean
		for _, c in ceilings do
			if
				math.abs(top - (c.cy - c.sy / 2)) < 1.5
				and math.abs(b.cx - c.cx) < (b.sx + c.sx) / 2
				and math.abs(b.cz - c.cz) < (b.sz + c.sz) / 2
			then
				return true
			end
		end
		return false
	end
	local bd = d.K.backdrop
	if bd then
		local half = Config.Story.pockets.size / 2 - 2.6
		for _, k in { -1, 1 } do
			put(
				d,
				1,
				"prop",
				k * half,
				bd.h / 2,
				0,
				1,
				bd.h,
				half * 2,
				d.K.trim,
				{ kit = bd.kit, tint = bd.tint }
			)
			put(
				d,
				1,
				"prop",
				0,
				bd.h / 2,
				k * half,
				half * 2 - 2,
				bd.h,
				1,
				d.K.trim,
				{ kit = bd.kit, tint = bd.tint }
			)
		end
	end
	local lamps = 0
	for _, b in d.l.boxes :: { BoxKit.Box } do
		local x, y, z = b.cx - d.l.cx, b.cy - d.l.cy, b.cz - d.l.cz
		if
			b.kind == "building"
			and b.tag == nil
			and b.shape == nil
			and (b.ry or 0) == 0
			and b.sy >= W.minHeight
			and math.min(b.sx, b.sz) <= W.maxThick
		then
			local top = b.cy + b.sy / 2
			if not underCeiling(b, top) then
				put(
					d,
					1,
					"prop",
					x,
					y + b.sy / 2 + W.cap / 2,
					z,
					b.sx + W.capProud * 2,
					W.cap,
					b.sz + W.capProud * 2,
					d.K.trim
				)
			end
			put(
				d,
				2,
				"prop",
				x,
				y - b.sy / 2 + W.skirt / 2,
				z,
				b.sx + W.skirtProud * 2,
				W.skirt,
				b.sz + W.skirtProud * 2,
				d.K.trim
			)
		elseif b.tag == "pocketWall" then
			-- the sealed glass's neon rim along its top
			put(d, 1, "glow", x, y + b.sy / 2 + 0.3, z, b.sx + 0.6, 0.6, b.sz + 0.6, d.K.accent)
		elseif b.kind == "glow" and d.P.lamps[b.color] and b.sx * b.sy * b.sz <= 260 and lamps < 16 then
			lamps += 1
			light(d, 2, x, y - b.sy / 2 - 1, z, b.color)
		end
	end
	local _ = Config
end

-- Street lamps (Art.Street) every `every` studs along a line from (x0, z0) to (x1, z1), facing ry
local function lampRow(
	d: D,
	tier: number,
	name: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	y: number,
	every: number,
	ry: number
)
	local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local n = math.max(1, math.floor(len / every))
	for i = 0, n do
		local t = i / n
		prop(d, tier, name, x0 + (x1 - x0) * t, y, z0 + (z1 - z0) * t, ry)
	end
end

local DRESS: { [string]: (D, any) -> () } = {}

function DRESS.station(d: D)
	-- lane dashes down both roads, lamps and benches on the corners' sidewalks
	for i = -9, 9 do
		if math.abs(i) > 1 then
			put(d, 2, "mark", 0, 0.25, i * 20, 0.5, 0.05, 8, "line")
			put(d, 2, "mark", i * 20, 0.25, 0, 8, 0.05, 0.5, "line")
		end
	end
	for _, q in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local cx, cz = q[1] * 110, q[2] * 110
		lampRow(
			d,
			1,
			"StreetLamp",
			q[1] * 22,
			cz - 40,
			q[1] * 22,
			cz + 40,
			0,
			40,
			if q[1] < 0 then -90 else 90
		)
		prop(d, 2, "Bench", q[1] * 24, 0, cz, if q[1] < 0 then -90 else 90)
		prop(d, 2, "Bin", q[1] * 24, 0, cz + 10, 0)
		prop(d, 3, "Planter", cx, 0, q[2] * 22, if q[2] < 0 then 180 else 0)
		prop(d, 3, "Hydrant", cx + 30, 0, q[2] * 22, 0)
	end
end

function DRESS.tower(d: D)
	local h = 180
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		strip(d, 1, c[1] * 20.3, h / 2, c[2] * 20.3, 0.8, h, 0.8)
	end
	for _, k in { -1, 1 } do -- the roof's parapet
		put(d, 2, "prop", k * 45.4, h + 3, 0, 0.8, 2, 91, "pkSteelDark")
		put(d, 2, "prop", 0, h + 3, k * 45.4, 91, 2, 0.8, "pkSteelDark")
	end
	for i = 0, 11 do -- a neon lip under each ledge
		local a = i * math.pi / 3
		strip(d, 3, math.cos(a) * 34, 15 + i * 14 - 1.2, math.sin(a) * 34, 16, 0.4, 16)
	end
	sign(d, "top", 0, h + 10, 44, 54, 8, 180)
	light(d, 1, 0, h + 34, -30, "relicRed", true)
	light(d, 1, 30, h + 10, 0, "foundryGlow", true)
	for _, a in { 0, 90, 180, 270 } do
		local x, z = rot(0, 60, a)
		prop(d, 2, "Planter", x, 0, z, a)
		local lx, lz = rot(24, 60, a)
		prop(d, 1, "StreetLamp", lx, 0, lz, a)
	end
end

function DRESS.rooftops(d: D)
	for gx = -2, 2 do
		for gz = -2, 2 do
			local h = 30 + ((gx * 7 + gz * 13) % 5 + 5) % 5 * 10
			local x, z = gx * 70, gz * 70
			-- a low parapet round each roof, a chimney or a water tank
			for _, k in { -1, 1 } do
				put(d, 2, "prop", x + k * 25.6, h + 1.6, z, 0.8, 1.2, 52, "pkSignCream")
				put(d, 2, "prop", x, h + 1.6, z + k * 25.6, 52, 1.2, 0.8, "pkSignCream")
			end
			if (gx + gz) % 2 == 0 then
				put(
					d,
					3,
					"prop",
					x + 14,
					h + 4,
					z - 12,
					4,
					6,
					4,
					"brick",
					{ kit = "Brickwork", tint = "pkIronBrick" }
				)
			else
				put(
					d,
					3,
					"prop",
					x - 12,
					h + 5,
					z + 10,
					7,
					8,
					7,
					"wood",
					{ shape = "cylinder", kit = "Planks", tint = "pkDriftwood" }
				)
			end
		end
	end
	-- old lamps in the lanes between the houses, warm windows' light from the lanes
	light(d, 1, 0, 20, 35, "window", true)
	light(d, 1, 0, 20, -105, "window", true)
	for i = -2, 1 do
		for j = -2, 2 do
			prop(d, if j % 2 == 0 then 1 else 2, "OldLamp", i * 70 + 35, 0, j * 70 + 26, 90)
			if j % 2 == 0 and i % 2 == 0 then
				light(d, 2, i * 70 + 35, 12, j * 70 + 26, "window")
			end
		end
	end
end

function DRESS.dungeon(d: D)
	sign(d, "door", 177.5, 17, 0, 22, 4, 90)
	light(d, 1, 172, 10, 0, "beaconGlow", true)
	-- hazard stripes on the doorways' edges between the rooms
	for _, x in { -60, 60 } do
		for _, z in { -18, 18 } do
			for i = 0, 5 do
				put(
					d,
					2,
					"prop",
					x,
					2 + i * 4,
					z,
					4.4,
					2,
					0.6,
					if i % 2 == 0 then "pkHazard" else "pkSignInk"
				)
			end
		end
	end
end

function DRESS.arena(d: D, Config: any)
	local w = Config.Story.warframe
	for i, p in w.pillars do
		local r = w.pillarRadius
		put(d, 1, "glow", p[1], 40.4, p[2], r * 2 + 1, 0.8, r * 2 + 1, d.K.accent, { shape = "cylinder" })
		put(
			d,
			2,
			"glow",
			p[1],
			1,
			p[2],
			r * 2 + 1,
			1.2,
			r * 2 + 1,
			if i % 2 == 0 then "beaconGlow" else "pkStageTrim",
			{ shape = "cylinder" }
		)
	end
	-- the stage's neon lip, the truss round the screen, its spotlights and speaker stacks
	strip(d, 1, 0, 3.2, -140, 121, 0.6, 0.6)
	for _, k in { -1, 1 } do
		put(d, 1, "prop", k * 74, 30, -186, 3, 60, 3, "steel", { mat = "Metal" })
		put(d, 2, "prop", k * 66, 5, -150, 8, 10, 6, "pkSignInk", { mat = "SmoothPlastic" })
		put(d, 2, "prop", k * 66, 13, -150, 6, 6, 5, "pkSignInk", { mat = "SmoothPlastic" })
		for i = 0, 2 do
			put(
				d,
				2,
				"glow",
				k * 66,
				3 + i * 3.5 + (if i == 2 then 6.5 else 0),
				-153.1,
				3,
				3,
				0.4,
				"pkStageTrim"
			)
		end
	end
	put(d, 1, "prop", 0, 61, -186, 151, 3, 3, "steel", { mat = "Metal" })
	for i = -3, 3 do
		put(
			d,
			2,
			"glow",
			i * 20,
			58.5,
			-184.5,
			2.4,
			2,
			2.4,
			if i % 2 == 0 then "pkStageTrim" else "beaconGlow"
		)
	end
	light(d, 1, -40, 50, -170, "pkStageTrim", true)
	light(d, 1, 40, 50, -170, "beaconGlow", true)
	sign(d, "stage", 0, 72, -185, 64, 14, 180)
	-- crowd barriers in front of the stage
	for i = -5, 5 do
		put(d, 2, "prop", i * 11, 2, -128, 10, 3, 0.6, "steel", { mat = "Metal" })
	end
	-- a star painted on the floor where the show happens
	put(d, 2, "mark", 0, 0.03, -20, 30, 0.05, 30, "pkStageTrim", { shape = "cylinder" })
	put(d, 2, "mark", 0, 0.06, -20, 24, 0.05, 24, "pkSignCream", { shape = "cylinder" })
	for _, a in { 30, 150, 210, 330 } do
		local x, z = rot(0, 185, a)
		prop(d, 1, "StreetLamp", x, 0, z, a + 180)
	end
end

function DRESS.bridge(d: D)
	local deck = 20
	-- the suspension cables: hangers down to the deck and the cable over them (a sag between the towers, down to
	-- the deck past them)
	local function cableY(z: number): number
		local az = math.abs(z)
		if az <= 90 then
			return deck + 8 + (100 - deck - 8) * (z / 90) ^ 2
		end
		return 100 - (100 - deck - 2) * (az - 90) / 108
	end
	for _, k in { -1, 1 } do
		local x = k * 34
		for z = -186, 186, 12 do
			if math.abs(math.abs(z) - 90) > 4 then
				local top = cableY(z)
				local hh = top - (deck + 3)
				if hh > 1 then
					put(d, 2, "prop", x, deck + 3 + hh / 2, z, 0.4, hh, 0.4, "pkSteelDark", { mat = "Metal" })
				end
			end
		end
		-- the cable itself in 4-stud pieces (boxes only turn about y, so a sag is short steps), each as tall as
		-- its rise so the steps join up
		for z = -196, 192, 4 do
			local y0, y1 = cableY(z), cableY(z + 4)
			local h = math.abs(y1 - y0) + 1.2
			put(d, 2, "prop", x, (y0 + y1) / 2, z + 2, 1.2, h, 4.2, "pkBridgeRed", { mat = "Metal" })
		end
		lampRow(d, 1, "StreetLamp", k * 29, -180, k * 29, 180, deck, 60, if k < 0 then -90 else 90)
		light(d, 1, x, 101, if k < 0 then -90 else 90, "relicRed", true)
	end
	for i = -9, 9 do
		put(d, 2, "mark", 0, deck + 0.05, i * 20, 0.6, 0.05, 9, "line")
	end
	sign(d, "gate", 0, 106, 90, 54, 7, 180)
end

function DRESS.subway(d: D, Config: any)
	local S = Config.Story.opening.subway
	local p = Config.Story.pockets.size
	for i = 1, S.lanes do
		local x = (i - (S.lanes + 1) / 2) * S.pitch
		local z0 = p / 2 - 16
		local z1 = z0 - S.length
		local zm = (z0 + z1) / 2
		for _, k in { -1, 1 } do
			-- the line's green band and a tile dado along both walls
			put(d, 1, "prop", x + k * (S.width / 2 - 0.05), 5, zm, 0.3, 1.6, S.length - 2, "pkSubwayBand")
			put(d, 2, "prop", x + k * (S.width / 2 - 0.05), 9, zm, 0.3, 0.5, S.length - 2, "pkSubwayBand")
		end
		sign(d, "station", x - S.width / 2 + 0.6, 12, z0 - 24, 24, 3, -90)
		-- sleepers under the rails
		for z = z0 - 6, z1 + 6, -12 do
			put(d, 3, "prop", x, 0.25, z, 9, 0.3, 1.4, "wood", { kit = "Planks", tint = "pkDojoDark" })
		end
	end
end

-- The deck pockets share their back wall at z = -34 and the south front at z = 195
local function frontSign(d: D, D0: number, w: number)
	sign(d, "front", 0, D0 + 16, 194.2, w, 9, 0)
end

function DRESS.academy(d: D)
	local D0 = 24
	frontSign(d, D0, 82)
	-- the school's blue and gold banners on the back wall, lockers along the hall's sides
	for _, x in { -40, 40 } do
		put(d, 2, "prop", x, D0 + 22, -31.6, 12, 18, 0.4, "pkAcademyTrim", { mat = "Fabric" })
		put(d, 2, "prop", x, D0 + 24, -31.3, 5, 5, 0.4, "relicGold", { mat = "Fabric", ry = 45 })
	end
	for _, k in { -1, 1 } do
		for i = 0, 5 do
			put(
				d,
				2,
				"prop",
				k * 86,
				D0 + 4,
				140 + i * 8,
				4,
				8,
				7,
				if i % 2 == 0 then "pkAcademyTrim" else "pkMatBlue",
				{ kit = "SteelPlate" }
			)
		end
		-- the classroom clock over the blackboard
		put(d, 3, "prop", k * 194.4, D0 + 17, 65, 0.4, 3, 3, "pkSignCream")
		-- a chair behind every desk
		for r = 0, 2 do
			for c = 0, 3 do
				put(d, 3, "prop", k * (110 + c * 20), D0 + 1.5, 44 + r * 24, 4, 3, 2, "pkMatBlue")
			end
		end
	end
	prop(d, 1, "Bench", -24, D0, 160, 90)
	prop(d, 1, "Bench", 24, D0, 160, -90)
	prop(d, 2, "Planter", -14, D0, 132, 0)
	prop(d, 2, "Planter", 14, D0, 132, 0)
	light(d, 1, 0, D0 + 18, 146, "beaconGlow", true)
	-- the copier workshop: hazard stripes along the line, a caution ring round each pod
	for i = -7, 7 do
		put(d, 2, "mark", i * 20, 0.05, -178.5, 10, 0.05, 1.2, if i % 2 == 0 then "pkHazard" else "pkSignInk")
	end
	for _, p in { { -120, -80 }, { -120, -150 }, { 120, -80 }, { 120, -150 } } do
		put(d, 2, "mark", p[1], 0.04, p[2], 16, 0.05, 16, "pkHazard", { shape = "cylinder" })
		light(d, 1, p[1], 10, p[2], "nullGlow", false)
	end
end

function DRESS.toyshop(d: D)
	local D0 = 20
	frontSign(d, D0, 70)
	-- bunting across the shop: a line and little coloured pennants
	local cols = { "pkToyTrim", "pkMatBlue", "pkSignGold", "pkToyWall" }
	for _, z in { 30, 90, 150 } do
		put(d, 3, "prop", 0, D0 + 26, z, 380, 0.2, 0.2, "pkSignInk")
		for i = -9, 9 do
			put(
				d,
				3,
				"prop",
				i * 20,
				D0 + 25,
				z,
				3,
				2,
				0.2,
				cols[(i + 10) % 4 + 1],
				{ shape = "wedge", ry = 0 }
			)
		end
	end
	-- the shop window's display boxes and the till's sign
	for i = -2, 2 do
		put(d, 2, "prop", i * 30, D0 + 2, 188, 10, 4, 6, cols[(i + 3) % 4 + 1], { kit = "Planks" })
	end
	light(d, 1, 0, D0 + 14, 60, "pkSignGold", true)
	light(d, 1, -130, D0 + 14, 75, "pkBulb", false)
	light(d, 1, 130, D0 + 14, 75, "pkBulb", false)
	-- brass trims on the basement's pipes
	for _, x in { -90, -30, 30, 90 } do
		put(d, 2, "prop", x, 14, -80, 2.2, 2.2, 2.2, "pkBrass", { mat = "Metal", shape = "ball" })
	end
	prop(d, 2, "Crate", -170, 0, -110, 0)
	prop(d, 2, "Barrel", -176, 0, -100, 0)
	prop(d, 3, "Crate", 170, 0, -110, 90)
end

function DRESS.seacave(d: D)
	local D0 = 20
	-- lantern posts on the shelf: a driftwood post, a lantern on top and its warm light
	for _, p in { { -90, 60 }, { 90, 60 }, { -40, 130 }, { 40, 130 } } do
		put(d, 1, "prop", p[1], D0 + 5, p[2], 0.8, 10, 0.8, "wood", { kit = "Planks", tint = "pkDriftwood" })
		put(d, 1, "glow", p[1], D0 + 11, p[2], 1.6, 2.2, 1.6, "workLamp")
		light(d, 1, p[1], D0 + 12, p[2], "workLamp", true)
	end
	-- stalactites hanging from the cave mouth
	for i = -9, 9 do
		local len = 4 + (i * 7 % 5 + 5) % 5 * 1.6
		put(
			d,
			2,
			"prop",
			i * 21,
			D0 + 39 - len / 2,
			184.5,
			2.4,
			len,
			2.4,
			"rock",
			{ kit = "CaveRock", tint = "pkCaveRock", ry = 45 }
		)
	end
	sign(d, "wharf", 0, D0 + 5, 31, 16, 3, 180)
	put(d, 2, "prop", -5, D0 + 2.5, 31.4, 0.6, 5, 0.6, "wood", { kit = "Planks", tint = "pkDriftwood" })
	put(d, 2, "prop", 5, D0 + 2.5, 31.4, 0.6, 5, 0.6, "wood", { kit = "Planks", tint = "pkDriftwood" })
	for _, p in { { -40, 40 }, { 40, 90 }, { -170, 150 }, { 170, 140 } } do
		prop(d, 2, "Barrel", p[1], D0, p[2], 0)
	end
	prop(d, 2, "Crate", 36, D0, 82, 20)
	prop(d, 3, "MooringBollard", -24, D0, 60, 90)
	-- the grotto's glowing pool rim
	strip(d, 2, 80, 0.4, -150, 92, 0.3, 82, "sparkGlow")
	light(d, 1, 80, 10, -150, "sparkGlow", true)
end

function DRESS.velmara(d: D)
	local D0 = 20
	-- rune lines glowing along the back wall and the hall's walls, kelp banners on the terrace
	for _, k in { -1, 1 } do
		strip(d, 1, k * 107, D0 + 28, -31.7, 170, 0.6, 0.3, "sparkGlow")
		strip(d, 2, k * 107, D0 + 3, -31.7, 170, 0.4, 0.3, "sparkGlow")
		for i = 0, 3 do
			put(d, 2, "crop", k * (60 + i * 36), D0 + 7, 140 + (i % 2) * 20, 1, 14, 0.6, "kelp")
		end
		strip(d, 2, k * 196, 6, -117, 0.4, 0.6, 150, "sparkGlow")
	end
	light(d, 1, 0, D0 + 30, 186, "sparkGlow", true)
	light(d, 1, 0, D0 + 12, 60, "sparkGlow", true)
	-- bronze shell medallions on the gate's pillars
	for _, k in { -1, 1 } do
		put(d, 3, "prop", k * 26, D0 + 30, 180.6, 4, 4, 0.6, "pkBronze", { mat = "Metal", ry = 45 })
	end
end

function DRESS.pit(d: D)
	local D0 = 20
	sign(d, "pit", 0, D0 + 30, 133.5, 36, 7, 0)
	-- the ring's corner pads (red and blue) and a crowd fence round the stage
	for i, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		put(
			d,
			1,
			"prop",
			c[1] * 19,
			2 + 6,
			-130 + c[2] * 19,
			1.8,
			4,
			1.8,
			if i % 2 == 0 then "pkSignRed" else "pkRingBlue"
		)
	end
	for _, k in { -1, 1 } do
		put(d, 2, "prop", k * 30, 1.5, -130, 0.6, 3, 60, "steel", { mat = "Metal" })
		put(d, 2, "prop", 0, 1.5, -130 + k * 30, 60, 3, 0.6, "steel", { mat = "Metal" })
	end
	-- pennants strung from the floodlights over the ring
	local cols = { "pkSignRed", "pkSignGold", "pkRingBlue" }
	for _, k in { -1, 1 } do
		put(d, 3, "prop", 0, 28, -130 + k * 30, 60, 0.2, 0.2, "pkSignInk")
		for i = -5, 5 do
			put(
				d,
				3,
				"prop",
				i * 5,
				27,
				-130 + k * 30,
				2.5,
				1.8,
				0.2,
				cols[(i + 6) % 3 + 1],
				{ shape = "wedge" }
			)
		end
	end
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		light(d, 1, c[1] * 27, 28, -130 + c[2] * 27, "beaconLight", true)
	end
	for _, p in { { -150, 30 }, { -110, 120 }, { -160, 110 } } do
		prop(d, 2, "Barrel", p[1], D0, p[2], 0)
	end
	prop(d, 2, "Crate", -110, D0, 20, 0)
	prop(d, 3, "Pallet", -100, D0, 140, 0)
end

function DRESS.ashlab(d: D)
	local D0 = 20
	frontSign(d, D0, 82)
	-- a lab-blue stripe along the rooms' walls, light panels in the ceiling-less rooms' tops, a caution ring
	for _, k in { -1, 1 } do
		put(d, 2, "prop", k * 143, D0 + 3, 12.2, 104, 0.6, 0.3, "pkLabTrim")
		put(d, 2, "prop", k * 143, D0 + 3, 117.8, 104, 0.6, 0.3, "pkLabTrim")
		light(d, 1, k * 143, D0 + 16, 65, "pkSignCream", false)
	end
	put(d, 2, "mark", 0, D0 + 0.45, 50, 56, 0.05, 56, "pkHazard", { shape = "cylinder" })
	put(d, 2, "mark", 0, D0 + 0.5, 50, 52, 0.05, 52, "pkSteelDark", { shape = "cylinder" })
	light(d, 1, 0, D0 + 14, 50, "beaconGlow", true)
	-- the sublevel: hazard stripes before the tanks
	for i = -7, 7 do
		put(d, 2, "mark", i * 20, 0.05, -186, 10, 0.05, 1.2, if i % 2 == 0 then "pkHazard" else "pkSignInk")
	end
	light(d, 1, 0, 10, -186, "nullGlow", true)
end

function DRESS.ironhall(d: D)
	local D0 = 20
	sign(d, "front", 0, D0 + 27, 194.2, 40, 7, 0)
	-- paper lanterns over the training floor, a weapon rack by the mats
	-- (strung on two lines from wall to wall: the hall has no ceiling to hang them from)
	for _, z in { 30, 80 } do
		put(d, 2, "prop", 0, D0 + 30, z, 390, 0.25, 0.25, "pkSignInk")
		for _, x in { -60, 0, 60 } do
			put(d, 2, "prop", x, D0 + 28, z, 0.2, 4, 0.2, "pkSignInk")
			put(d, 2, "glow", x, D0 + 25, z, 3, 3.6, 3, "pkSignRed", { shape = "ball" })
		end
	end
	light(d, 1, 0, D0 + 20, 50, "foundryGlow", true)
	put(d, 2, "prop", 64, D0 + 4, 50, 1, 8, 16, "wood", { kit = "Planks", tint = "pkDojoDark" })
	for i = -2, 2 do
		put(d, 3, "prop", 63.2, D0 + 5, 50 + i * 3, 0.4, 7, 0.4, "pkDojoWood")
	end
	-- the inner dojo's braziers light the cage
	for _, p in { { -180, -80 }, { 180, -80 }, { -180, -180 }, { 180, -180 } } do
		light(d, 1, p[1], 8, p[2], "foundryGlow", true)
	end
end

function DRESS.pound(d: D)
	sign(d, "front", 0, 22, 194.6, 30, 5, 0)
	-- hazard stripes on the dock's edge and lane lines down the hall
	for i = -9, 9 do
		put(d, 1, "mark", i * 8, 0.25, 168, 4, 0.05, 1.5, if i % 2 == 0 then "pkHazard" else "pkSignInk")
	end
	for _, x in { -14, 14 } do
		put(d, 2, "mark", x, 0.25, -50, 0.6, 0.05, 170, "pkHazard")
	end
	-- warning beacons on the partition, pallets and crates by the dock
	for _, x in { -60, 60 } do
		put(d, 2, "glow", x, 24, 38.2, 1.6, 1.6, 1.6, "relicRed", { shape = "ball" })
	end
	light(d, 1, 0, 20, 150, "workLamp", true)
	light(d, 1, 0, 20, -160, "relicRed", true)
	prop(d, 2, "Pallet", -70, 0, 170, 0)
	prop(d, 2, "Crate", 70, 0, 172, 0)
	prop(d, 3, "Crate", 76, 0, 180, 30)
	prop(d, 2, "Barrel", -150, 0, 150, 0)
end

-- Every pocket's dressing (looks() first, so the boxes carry their kit)
function PocketDress.dress(Config: any, l: any, layout: string): Dress
	local out: Dress = { extras = {}, lights = {}, props = {}, layout = layout }
	local K = Config.PocketKit.pockets[layout]
	if not K then
		return out
	end
	local d: D = { l = l, K = K, P = Config.PocketKit, out = out }
	generic(d, Config)
	local fn = DRESS[layout]
	if fn then
		fn(d, Config)
	end
	return out
end

-- Both at once: the looks on the layout's boxes and the dressing
function PocketDress.apply(Config: any, l: any, layout: string): Dress
	PocketDress.looks(Config, l, layout)
	return PocketDress.dress(Config, l, layout)
end

-- How many parts a street prop is (its Art.Street pieces)
function PocketDress.propParts(Config: any, name: string): number
	local def = Config.City.kit.props[name]
	local n = 0
	if def then
		for _ in def.pieces do
			n += 1
		end
	end
	return n
end

-- What one device builds of a pocket's dressing for its preset budget (Config.Presets <preset>.pockets):
-- extras and props from `fromTier` up to the preset's tier, and its lights (tier order, then as listed). parts
-- counts the tier 1 boxes too (the server's), so the whole pocket's dressing stays under the budget; a piece
-- that would pass it is left out.
function PocketDress.pick(
	Config: any,
	dress: Dress,
	budget: any,
	fromTier: number
): ({ Extra }, { Prop }, { Light }, number)
	local used = 0
	for _, e in dress.extras do
		if e.tier < fromTier then
			used += 1
		end
	end
	local extras, props, lights = {}, {}, {}
	for tier = fromTier, budget.tier do
		for _, e in dress.extras do
			if e.tier == tier and used + 1 <= budget.parts then
				used += 1
				table.insert(extras, e)
			end
		end
		for _, p in dress.props do
			local n = PocketDress.propParts(Config, p.name)
			if p.tier == tier and used + n <= budget.parts then
				used += n
				table.insert(props, p)
			end
		end
	end
	for tier = 1, budget.tier do
		for _, li in dress.lights do
			if li.tier == tier and #lights < budget.lights then
				table.insert(lights, li)
			end
		end
	end
	return extras, props, lights, used
end

-- Parts of a pocket's dressing up to a tier (extras and props)
function PocketDress.parts(Config: any, dress: Dress, tier: number): number
	local n = 0
	for _, e in dress.extras do
		if e.tier <= tier then
			n += 1
		end
	end
	for _, p in dress.props do
		if p.tier <= tier then
			n += PocketDress.propParts(Config, p.name)
		end
	end
	return n
end

return PocketDress
