--!strict
-- HallLayout: Crane's Hero Hall (Config.Hall) as plain boxes and named spots, from the Beacon Tower's centre.
-- CityLayout builds the tower through it (Config.Hall.on): the hollow lobby and training floor at the bottom,
-- the doors, the stair, the lift stops, the terminals, the launch deck on the roof, then the solid tower above.
-- HallService reads the spots for its prompts, dummies and pads; HallClient for its signs, statues, lights and
-- screens. Pure (no Roblox types), so Lune checks it.
--
-- Axes: x east, y up; -z is the Hall's front (the canopy door, the meeting spot, the launch deck), +z its back; every number in Config.Hall is studs from the tower's centre and
-- from the plaza's top. PLACEHOLDER ART: plain parts in the city palette.

local HallLayout = {}

export type Box = { [string]: any }
export type Spot = { x: number, y: number, z: number, [string]: any }

local function box(
	list: { Box },
	kind: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	extra: { [string]: any }?
): Box
	local b: Box = { kind = kind, cx = cx, cy = cy, cz = cz, sx = sx, sy = sy, sz = sz, color = color }
	if extra then
		for k, v in extra do
			b[k] = v
		end
	end
	table.insert(list, b)
	return b
end

-- A box from its corners (x0..x1, y0..y1, z0..z1); nothing when it has no size
local function span(
	list: { Box },
	kind: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: string,
	extra: { [string]: any }?
): Box?
	if x1 - x0 < 0.05 or y1 - y0 < 0.05 or z1 - z0 < 0.05 then
		return nil
	end
	return box(
		list,
		kind,
		(x0 + x1) / 2,
		(y0 + y1) / 2,
		(z0 + z1) / 2,
		x1 - x0,
		y1 - y0,
		z1 - z0,
		color,
		extra
	)
end

-- The floors' heights above the plaza's top: the lobby floor, the training floor, the tower's solid part
function HallLayout.levels(Config: any): (number, number, number)
	local H = Config.Hall
	local lobby = 0
	local train = H.lobbyHeight + H.slab
	local solid = train + H.trainHeight + H.slab
	return lobby, train, solid
end

-- Is a face a doorway? (fx, fz: the face's outward direction)
local function hasDoor(H: any, fx: number, fz: number): boolean
	for _, f in H.door.faces do
		if f[1] == fx and f[2] == fz then
			return true
		end
	end
	return false
end

-- One wall face of the hollow base: from y0 to y1 (above the plaza's top `top`), with a doorway in the lobby and
-- the window band on the training floor. Walls run along the face's length (a) at depth (d) from the centre.
local function face(
	list: { Box },
	Config: any,
	cx: number,
	cz: number,
	top: number,
	half: number,
	fx: number,
	fz: number,
	kit: string?
)
	local H = Config.Hall
	local w = H.wall
	local _, train, solid = HallLayout.levels(Config)
	-- a strip of wall: along the face from a0 to a1, from y0 to y1, glass when `glass`
	local function strip(a0: number, a1: number, y0: number, y1: number, glass: boolean?)
		local x0, x1, z0, z1
		if fz ~= 0 then
			x0, x1 = cx + a0, cx + a1
			local d = cz + fz * (half - w / 2)
			z0, z1 = d - w / 2, d + w / 2
		else
			z0, z1 = cz + a0, cz + a1
			local d = cx + fx * (half - w / 2)
			x0, x1 = d - w / 2, d + w / 2
		end
		if glass then
			span(list, "beacon", x0, x1, top + y0, top + y1, z0, z1, "hallGlass", {
				mat = "Glass",
				tint = "hallGlass",
				alpha = H.windows.alpha,
				hall = "glass",
			})
		else
			local b = span(list, "beacon", x0, x1, top + y0, top + y1, z0, z1, "beacon", { hall = "wall" })
			if b and kit then
				b.kit = kit
			end
		end
	end
	-- the corners belong to the north and south faces (full length); east and west fit between them
	local len = if fz ~= 0 then half else half - w
	local D = H.door
	-- the lobby storey
	if hasDoor(H, fx, fz) then
		strip(-len, -D.width / 2, 0, train)
		strip(D.width / 2, len, 0, train)
		strip(-D.width / 2, D.width / 2, D.height, train)
	else
		strip(-len, len, 0, train)
	end
	-- the training storey, its window band
	local W = H.windows
	strip(-len, len, train, train + W.from)
	strip(-len, len, train + W.from, train + W.to, true)
	strip(-len, len, train + W.to, solid)
end

-- The boxes of the Hall (the base, the inside and the deck; the tower above is the caller's) and its spots.
-- (cx, cz): the tower's centre; gy: the ground; width, height: the tower's (Config.City.downtown.beacon); kit:
-- the walls' city kit front (or nil without the kit).
function HallLayout.build(
	Config: any,
	cx: number,
	cz: number,
	gy: number,
	width: number,
	height: number,
	kit: string?
): ({ Box }, { [string]: any })
	local H = Config.Hall
	local list: { Box } = {}
	local top = gy + 1.1 -- the plaza's top
	local half = width / 2
	local w = H.wall
	local inner = half - w
	local lobby, train, solid = HallLayout.levels(Config)
	local spots: { [string]: any } = {}
	-- the walls
	for _, f in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		face(list, Config, cx, cz, top, half, f[1], f[2], kit)
	end
	-- the lobby's floor (terrazzo with a red runner from the south door to the dais) and its ceiling lights
	span(list, "plaza", cx - inner, cx + inner, top - 0.2, top + 0.15, cz - inner, cz + inner, "hallFloor")
	span(
		list,
		"plaza",
		cx - 3,
		cx + 3,
		top + 0.15,
		top + 0.25,
		cz - inner,
		cz - 8,
		"hallCarpet",
		{ ghost = true }
	)
	-- the slab between the floors, with the stair's hole along the east wall
	local S = H.stair
	local sx0, sx1 = cx + inner - S.width, cx + inner
	local steps = math.ceil(train / 1.0)
	local rise = train / steps
	local run = steps * S.step
	local sz0 = cz + inner - S.landing - run -- the stair's foot (south end)
	local sz1 = cz + inner - S.landing -- its head
	local y0, y1 = top + train - H.slab, top + train
	span(list, "beacon", cx - inner, sx0, y0, y1, cz - inner, cz + inner, "hallSlab", { hall = "slab" })
	span(list, "beacon", sx0, sx1, y0, y1, sz1, cz + inner, "hallSlab", { hall = "slab" })
	span(list, "beacon", sx0, sx1, y0, y1, cz - inner, sz0, "hallSlab", { hall = "slab" })
	-- the training floor's mats over the slab
	span(
		list,
		"plaza",
		cx - inner,
		sx0 - 0.6,
		y1,
		y1 + 0.15,
		cz - inner,
		cz + inner,
		"hallMat",
		{ ghost = true }
	)
	-- the steps: solid blocks up to each tread, north from the foot
	for i = 1, steps do
		local z0 = sz0 + (i - 1) * S.step
		span(list, "beacon", sx0, sx1, top, top + i * rise, z0, z0 + S.step, "hallStep", { hall = "step" })
	end
	-- the rail along the hole's west edge upstairs (gold), and on the stair's open side
	span(list, "beacon", sx0 - 0.6, sx0, y1, y1 + 3.2, sz0, sz1, "hallGold", { hall = "rail" })
	-- the roof slab of the base (the tower's solid part starts here)
	spots.levels = { lobby = top + lobby, train = top + train, solid = top + solid }
	-- ceiling light panels on both storeys (HallClient lights them)
	for ref, ceiling in { train - H.slab, solid } do -- each storey's ceiling (1 the lobby, 2 the training floor)
		for _, p in { { -10, -10 }, { 8, -10 }, { -10, 10 }, { 8, 10 } } do
			box(list, "glow", cx + p[1], top + ceiling - 0.15, cz + p[2], 8, 0.3, 8, "hallLight", {
				tag = "hallLight",
				ref = ref,
			})
		end
	end

	-- the lobby: the Hall of Fame dais and its statues' spots
	local L = H.lobby
	local dais = L.dais
	box(
		list,
		"prop",
		cx + dais.at[1],
		top + dais.height / 2,
		cz + dais.at[2],
		dais.radius * 2,
		dais.height,
		dais.radius * 2,
		"hallGold",
		{ shape = "cylinder" }
	)
	box(
		list,
		"prop",
		cx + dais.at[1],
		top + dais.height + 0.15,
		cz + dais.at[2],
		dais.radius * 2 - 1.4,
		0.3,
		dais.radius * 2 - 1.4,
		"hallNavy",
		{ shape = "cylinder" }
	)
	spots.statues = {}
	for i, s in L.statues do
		table.insert(spots.statues, {
			x = cx + dais.at[1] + s[1],
			y = top + dais.height + 0.3,
			z = cz + dais.at[2] + s[2],
			scale = s[3],
			rank = i,
		})
	end
	-- the shop counter (a gold-topped desk), its prompt on the top
	local sh = L.shop
	box(
		list,
		"prop",
		cx + sh.at[1],
		top + sh.size[2] / 2,
		cz + sh.at[2],
		sh.size[1],
		sh.size[2],
		sh.size[3],
		"hallNavy"
	)
	box(
		list,
		"terminal",
		cx + sh.at[1],
		top + sh.size[2] + 0.15,
		cz + sh.at[2],
		sh.size[1] + 0.4,
		0.3,
		sh.size[3] + 0.4,
		"hallGold",
		{ tag = "hallShop", ref = 0 }
	)
	spots.shop = { x = cx + sh.at[1], y = top + sh.size[2], z = cz + sh.at[2] }
	-- the wall screens: boards (north wall), contracts and squads (south wall), facing into the lobby
	local function screen(name: string, s: any, y: number, faceZ: number)
		local x, z = cx + s.at[1], cz + s.at[2]
		box(list, "terminal", x, y + s.y + s.size[2] / 2, z, s.size[1], s.size[2], 0.4, "hallScreen", {
			tag = name,
			ref = faceZ,
			ghost = false,
		})
		spots[name] =
			{ x = x, y = y + s.y + s.size[2] / 2, z = z, face = -faceZ, w = s.size[1], h = s.size[2] }
	end
	screen("hallBoards", L.boards, top, 1)
	screen("hallContracts", L.contracts, top, -1)
	screen("hallSquads", L.squads, top, -1)
	for _, p in L.planters do
		box(list, "prop", cx + p[1], top + 1.2, cz + p[2], 3.4, 2.4, 3.4, "hallNavy")
		box(list, "prop", cx + p[1], top + 3.4, cz + p[2], 3.6, 3.6, 3.6, "leaf", { shape = "ball" })
	end

	-- the lifts: one stop a floor and one on the roof, in the same order as H.lift.dests
	local LF = H.lift
	spots.lifts = {}
	local liftY = { top + lobby, top + train, top + height }
	for i = 1, #LF.dests do
		local lx, lz = cx + LF.at[1], cz + LF.at[2]
		if i == 3 then
			lx, lz = cx + H.roof.lift[1], cz + H.roof.lift[2]
		end
		local ly = liftY[i]
		box(list, "terminal", lx, ly + 0.2, lz, LF.radius * 2, 0.3, LF.radius * 2, "hallLift", {
			shape = "cylinder",
			tag = "hallLift",
			ref = i,
		})
		spots.lifts[i] = { x = lx, y = ly + 0.35, z = lz, name = LF.dests[i] }
	end

	-- the training floor: the dummies' spots, the Burst Test pad, the terminals
	local T = H.training
	local fy = top + train + 0.15
	spots.dummies = {}
	for _, d in T.dummies do
		box(list, "prop", cx + d[1], fy + 0.3, cz + d[2], 3.4, 0.6, 3.4, "hallNavy")
		table.insert(spots.dummies, { x = cx + d[1], y = fy + 3, z = cz + d[2], r = T.radius })
	end
	spots.big = { x = cx + T.big[1], y = fy + 3 * 2.6, z = cz + T.big[2], r = T.bigRadius }
	local B = T.burst
	box(
		list,
		"terminal",
		cx + B.at[1],
		fy + 0.15,
		cz + B.at[2],
		B.radius * 2,
		0.3,
		B.radius * 2,
		"hallBurst",
		{
			shape = "cylinder",
			tag = "hallBurst",
			ref = 0,
		}
	)
	spots.burst = { x = cx + B.at[1], y = fy + 0.3, z = cz + B.at[2], r = B.radius }
	local sb = T.scoreboard
	box(
		list,
		"terminal",
		cx + sb.at[1],
		fy + sb.y + sb.size[2] / 2,
		cz + sb.at[2],
		sb.size[1],
		sb.size[2],
		0.4,
		"hallScreen",
		{ tag = "hallScore", ref = -1 }
	)
	spots.hallScore = {
		x = cx + sb.at[1],
		y = fy + sb.y + sb.size[2] / 2,
		z = cz + sb.at[2],
		face = 1,
		w = sb.size[1],
		h = sb.size[2],
	}
	-- the Loadout terminal (a console) and the Weapon Rack (a rack on the south wall)
	box(list, "prop", cx + T.loadout.at[1], fy + 1.6, cz + T.loadout.at[2], 2.4, 3.2, 3, "hallNavy")
	box(
		list,
		"terminal",
		cx + T.loadout.at[1] + 1.25,
		fy + 2.6,
		cz + T.loadout.at[2],
		0.2,
		1.6,
		2.4,
		"hallScreen",
		{
			tag = "hallLoadout",
			ref = 0,
		}
	)
	spots.loadout = { x = cx + T.loadout.at[1], y = fy + 2.6, z = cz + T.loadout.at[2] }
	box(list, "prop", cx + T.weapons.at[1], fy + 2.5, cz + T.weapons.at[2], 7, 5, 1.2, "wood")
	box(
		list,
		"terminal",
		cx + T.weapons.at[1],
		fy + 2.5,
		cz + T.weapons.at[2] + 0.7,
		6,
		0.3,
		0.3,
		"hallGold",
		{
			tag = "hallWeapons",
			ref = 0,
		}
	)
	spots.weapons = { x = cx + T.weapons.at[1], y = fy + 2.5, z = cz + T.weapons.at[2] }

	-- the roof's launch deck: out over the south face from the tower's top, the pad at its end, side rails
	local R = H.roof
	local roofY = top + height - 0.1 -- the tower's top (its box ends at gy + 1 + height)
	local dk = R.deck
	local dz0, dz1 = cz - half - dk.length, cz - half + 2
	span(
		list,
		"beacon",
		cx - dk.width / 2,
		cx + dk.width / 2,
		roofY - dk.thick,
		roofY,
		dz0,
		dz1,
		"hallSlab",
		{
			hall = "deck",
		}
	)
	for _, sgn in { -1, 1 } do
		local rx = cx + sgn * (dk.width / 2 - 0.3)
		span(
			list,
			"beacon",
			rx - 0.3,
			rx + 0.3,
			roofY,
			roofY + R.rail,
			dz0 + R.pad.radius * 2 + 1,
			dz1,
			"hallGold",
			{
				hall = "rail",
			}
		)
	end
	local padZ = dz0 + R.pad.radius + 0.8
	box(list, "terminal", cx, roofY + 0.15, padZ, R.pad.radius * 2, 0.3, R.pad.radius * 2, "hallBurst", {
		shape = "cylinder",
		tag = "hallPad",
		ref = 0,
	})
	spots.pad = { x = cx, y = roofY + 0.3, z = padZ, r = R.pad.radius, dir = { 0, -1 } }

	-- outside: the canopy over the south door on two gold pillars, the signs over the doors and the big one on the
	-- east face (the Ceremony's backdrop), the meeting ring on the paving
	local C = H.plaza.canopy
	local doorTop = top + H.door.height
	span(
		list,
		"beacon",
		cx - C.width / 2,
		cx + C.width / 2,
		top + C.y,
		top + C.y + 1,
		cz - half - C.depth,
		cz - half,
		"hallNavy",
		{
			hall = "canopy",
		}
	)
	for _, sgn in { -1, 1 } do
		box(
			list,
			"prop",
			cx + sgn * (C.width / 2 - 1),
			top + C.y / 2,
			cz - half - C.depth + 1,
			1.4,
			C.y,
			1.4,
			"hallGold",
			{
				shape = "cylinder",
			}
		)
	end
	spots.signs = {}
	for _, f in H.door.faces do
		local fx, fz = f[1], f[2]
		local sx = cx + fx * (half + 0.15)
		local sz = cz + fz * (half + 0.15)
		local wide = fz ~= 0
		box(
			list,
			"terminal",
			sx,
			doorTop + 3,
			sz,
			if wide then 18 else 0.3,
			3.4,
			if wide then 0.3 else 18,
			"hallNavy",
			{
				tag = "hallSign",
				ref = 0,
				fx = fx,
				fz = fz,
			}
		)
		table.insert(spots.signs, { x = sx, y = doorTop + 3, z = sz, fx = fx, fz = fz, w = 18, h = 3.4 })
	end
	box(list, "terminal", cx + half + 0.15, top + 30, cz, 0.3, 8, 34, "hallNavy", {
		tag = "hallSign",
		ref = 1,
		fx = 1,
		fz = 0,
	})
	table.insert(
		spots.signs,
		{ x = cx + half + 0.15, y = top + 30, z = cz, fx = 1, fz = 0, w = 34, h = 8, big = true }
	)
	local M = H.plaza.meet
	box(list, "mark", cx + M.at[1], top + 0.05, cz + M.at[2], M.radius * 2, 0.1, M.radius * 2, "hallGold", {
		shape = "cylinder",
		tag = "hallMeet",
		ref = 0,
	})
	spots.meet = { x = cx + M.at[1], y = top, z = cz + M.at[2], r = M.radius }
	spots.top, spots.half, spots.centre = top, half, { cx, cz }
	return list, spots
end

-- The plaza's hub props (Config.Hall.plaza) as CityKit props: name, x, y, z, turn
function HallLayout.props(Config: any, cx: number, cz: number, gy: number): { { [string]: any } }
	local P = Config.Hall.plaza
	local y = gy + 1.1
	local out = {}
	local function put(name: string, x: number, z: number, ry: number)
		table.insert(out, { name = name, x = cx + x, y = y, z = cz + z, ry = ry })
	end
	for _, b in P.benches do
		put("Bench", b[1], b[2], b[3])
	end
	for _, c in P.carts do
		put("FoodCart", c[1], c[2], c[3])
	end
	for _, c in P.cafes do
		put("CafeSet", c[1], c[2], 0)
	end
	for _, t in P.tubs do
		put("FlowerTub", t[1], t[2], 0)
	end
	for _, l in P.lamps do
		put("StreetLamp", l[1], l[2], 0)
	end
	for _, b in P.bins do
		put("Bin", b[1], b[2], 0)
	end
	for _, v in P.vending do
		put("VendingMachine", v[1], v[2], v[3])
	end
	return out
end

-- Which floor a height is on (1 lobby, 2 training floor, 3 the roof; nil: not in the Hall's column)
function HallLayout.floorAt(spots: { [string]: any }, x: number, y: number, z: number): number?
	local c = spots.centre
	if math.abs(x - c[1]) > spots.half + 0.5 or math.abs(z - c[2]) > spots.half + 0.5 then
		return nil
	end
	local lv = spots.levels
	if y < lv.lobby - 2 then
		return nil
	elseif y < lv.train - 0.5 then
		return 1
	elseif y < lv.solid then
		return 2
	end
	return 3
end

return HallLayout
