--!strict
-- WantedRules: the HQ's WANTED poster and nemesis head trophies (gap check G5, spec H5: "its head for your HQ
-- wall"). Pure, so HqService, HqClient and the Lune tests agree:
-- * poster(...): what the poster shows: your current nemesis's look and rank (NemesisMath, from your user id,
--   rank and side: the same nemesis the WANTED button shows), its traits and Intel, and its state (locked
--   below level 8, on its way after a Showdown win, the Showdown open).
-- * beaten(...) and heads(...): one head per nemesis rank you have beaten (1 to Config.Nemesis.maxRank), each
--   the look of that rank's nemesis. Read from the save as it is (mmo.nemesis.rank, mmo.heads, mmo.banes): no
--   new save field.
-- * bust(...) and head(...): the look as boxes, balls and cylinders (the colours, head piece, build, cape and
--   trait pieces NemesisFx puts on its Brute Bot body), in a frame whose front is -z.
-- * layout(Config): where the poster and the five mounts go on the HQ wall (Config.Hq.wanted).
-- PLACEHOLDER ART: plain parts until nate imports the HQ art pass (art/blender/hq.py; Shared.HqArtKit shapes them).

local NemesisMath = if script then require(script.Parent.NemesisMath) else (require :: any)("./NemesisMath")

local WantedRules = {}

local SIDES = { "hero", "villain" }

-- The look of one nemesis, sent to the device (no free text: the name is from the fixed word lists)
export type Look = {
	name: string,
	rank: number,
	side: string,
	build: string,
	colors: number,
	head: string,
	cape: boolean,
	traits: number,
}

function WantedRules.look(N: any, userId: number, rank: number, side: string, traits: number?): Look
	local who = NemesisMath.make(N, userId, rank, side)
	return {
		name = who.name,
		rank = rank,
		side = side,
		build = who.build,
		colors = who.colors,
		head = who.head,
		cape = who.cape,
		traits = traits or 0,
	}
end

export type Poster = {
	look: Look,
	intel: number,
	need: number,
	locked: boolean, -- below Config.Nemesis.minLevel: a silhouette, "???"
	waiting: boolean, -- a new one is on its way (a day after a Showdown win): a silhouette
	showdown: boolean, -- 3 Intel: the Showdown is open
	state: string, -- "locked", "waiting", "showdown" or "hunting"
}

-- The poster for a hero at `level` with this saved MMO record (c.mmo), at os.time() `now`
function WantedRules.poster(
	N: any,
	userId: number,
	side: string,
	level: number,
	mmo: any,
	now: number
): Poster
	local st = mmo and mmo.nemesis or {}
	local rank = math.clamp(math.floor(st.rank or 1), 1, N.maxRank)
	local intel = math.clamp(math.floor(st.intel or 0), 0, N.intelForShowdown)
	local locked = level < N.minLevel
	local waiting = not locked and (st.readyAt or 0) > now
	local showdown = not locked and not waiting and intel >= N.intelForShowdown
	return {
		look = WantedRules.look(N, userId, rank, side, if locked or waiting then 0 else st.traits or 0),
		intel = if locked or waiting then 0 else intel,
		need = N.intelForShowdown,
		locked = locked,
		waiting = waiting,
		showdown = showdown,
		state = if locked
			then "locked"
			elseif waiting then "waiting"
			elseif showdown then "showdown"
			else "hunting",
	}
end

-- Which nemesis rank (and side) a saved bane seed is, or nil (a seed is NemesisMath.seed(userId, rank, side))
function WantedRules.rankOf(N: any, userId: number, seed: number): (number?, string?)
	for rank = 1, N.maxRank do
		for _, side in SIDES do
			if NemesisMath.seed(userId, rank, side) == seed then
				return rank, side
			end
		end
	end
	return nil, nil
end

-- The ranks this hero has beaten: rank -> the side its look is drawn for. A win is the only way up a rank
-- (NemesisMath.afterWin), so the current rank r means 1 to r - 1 are beaten, and heads counts the wins (past
-- the top rank a win keeps rank 5, so 5 wins or more means rank 5 too); banes names the newest 8 beaten.
function WantedRules.beaten(N: any, userId: number, side: string, mmo: any): { [number]: string }
	local out: { [number]: string } = {}
	local st = mmo and mmo.nemesis or {}
	local top = math.min(N.maxRank, math.max((st.rank or 1) - 1, math.floor(mmo and mmo.heads or 0)))
	for r = 1, top do
		out[r] = side
	end
	for _, seed in (mmo and mmo.banes or {}) do
		local r, s = WantedRules.rankOf(N, userId, seed)
		if r and s then
			out[r] = s -- the side it was beaten on (a bane from before a side change keeps its own look)
		end
	end
	return out
end

export type Head = { rank: number, look: Look? }

-- The wall's mounts: one per rank, 1 to maxRank, with the head of each one beaten (nil look: an empty mount)
function WantedRules.heads(N: any, userId: number, side: string, mmo: any): { Head }
	local beaten = WantedRules.beaten(N, userId, side, mmo)
	local out: { Head } = {}
	for r = 1, N.maxRank do
		local s = beaten[r]
		table.insert(out, { rank = r, look = if s then WantedRules.look(N, userId, r, s) else nil })
	end
	return out
end

function WantedRules.count(heads: { Head }): number
	local n = 0
	for _, h in heads do
		if h.look then
			n += 1
		end
	end
	return n
end

-- One piece of the look: a box (or Ball, Cylinder) at (x, y, z) in the look's frame (front -z), an RGB colour,
-- a Material name, turns about y then z in radians (ry, rz) and a lit face (glow)
export type Piece = {
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	rgb: { number },
	mat: string,
	shape: string?,
	ry: number?,
	rz: number?,
	glow: boolean?,
}

local WARN = { 255, 60, 50 }
local VISOR = { 120, 230, 255 }
local EYE = { 255, 220, 90 }

local function add(out: { Piece }, name: string, x, y, z, sx, sy, sz, rgb: { number }, mat: string?): Piece
	local p: Piece = {
		name = name,
		x = x,
		y = y,
		z = z,
		sx = sx,
		sy = sy,
		sz = sz,
		rgb = rgb,
		mat = mat or "SmoothPlastic",
	}
	table.insert(out, p)
	return p
end

local function colorsOf(N: any, look: Look): ({ number }, { number })
	local set = N.colors[look.colors] or N.colors[1]
	return set[1], set[2]
end

-- How wide the shoulders are (NemesisFx's build tell)
function WantedRules.wide(look: Look): number
	return if look.build == "bulky" or look.build == "spiked" then 1.3 else 1
end

-- The nemesis's head, centred on (ox, oy, oz), front -z: a trim skull, a faceplate in its main colour, its head
-- piece (visor, dome, horns or the cyclops eye, as NemesisFx), and its build (spikes on a spiked one)
function WantedRules.head(N: any, look: Look, ox: number?, oy: number?, oz: number?): { Piece }
	local x0, y0, z0 = ox or 0, oy or 0, oz or 0
	local main, trim = colorsOf(N, look)
	local out: { Piece } = {}
	local w = if look.build == "bulky" then 2.5 elseif look.build == "squat" then 2.3 else 2.1
	local h = if look.build == "lanky" then 2.4 elseif look.build == "squat" then 1.7 else 2
	add(out, "skull", x0, y0, z0, w, h, 2, trim, "Metal")
	add(out, "faceplate", x0, y0 - h * 0.12, z0 - 1.05, w * 0.82, h * 0.55, 0.15, main, "Metal")
	add(out, "jaw", x0, y0 - h * 0.42, z0 - 0.9, w * 0.6, h * 0.16, 0.4, trim, "Metal")
	local function eyes(rgb: { number })
		for _, s in { -1, 1 } do
			local e =
				add(out, "eye", x0 + s * w * 0.22, y0 + h * 0.18, z0 - 1.12, 0.38, 0.26, 0.1, rgb, "Neon")
			e.glow = true
		end
	end
	if look.head == "horned" then
		for _, s in { -1, 1 } do
			local horn =
				add(out, "horn", x0 + s * w * 0.36, y0 + h / 2 + 0.5, z0, 0.4, 1.3, 0.4, trim, "Metal")
			horn.rz = -s * 0.4
		end
		eyes(WARN)
	elseif look.head == "dome" then
		local dome = add(out, "dome", x0, y0 + h / 2, z0, w * 1.05, w * 1.05, w * 1.05, main, "Glass")
		dome.shape = "Ball"
		eyes(EYE)
	elseif look.head == "cyclops" then
		local eye = add(out, "cyclopsEye", x0, y0 + h * 0.16, z0 - 1.05, 0.9, 0.9, 0.9, WARN, "Neon")
		eye.shape = "Ball"
		eye.glow = true
	else
		local visor = add(out, "visor", x0, y0 + h * 0.18, z0 - 1.12, w * 0.86, 0.36, 0.14, VISOR, "Neon")
		visor.glow = true
	end
	if look.build == "spiked" then
		for _, s in { -1, 0, 1 } do
			local spike =
				add(out, "spike", x0 + s * w * 0.3, y0 + h / 2 + 0.35, z0 + 0.3, 0.3, 0.7, 0.3, trim, "Metal")
			spike.rz = -s * 0.3
		end
	end
	return out
end

-- The poster's bust: shoulders, chest, neck and head, the cape behind it, and its traits' pieces (the plates
-- on its chest, the second cannon, the heal drone, the summoner's antenna), front -z, the chest's middle at 0
function WantedRules.bust(N: any, look: Look): { Piece }
	local main, trim = colorsOf(N, look)
	local wide = WantedRules.wide(look)
	local out: { Piece } = {}
	if look.cape then
		add(out, "cape", 0, -0.6, 1.2, 4.6 * wide, 4.4, 0.3, main, "Fabric")
	end
	add(out, "chest", 0, -0.9, 0, 3.6 * wide, 3, 2, main, "Metal")
	add(out, "shoulders", 0, 0.9, 0, 5 * wide, 1, 2.6, trim, "Metal")
	add(out, "neck", 0, 1.7, 0, 0.9, 0.8, 0.9, trim, "Metal")
	for _, p in WantedRules.head(N, look, 0, 3.1, 0) do
		table.insert(out, p)
	end
	for i, t in N.traits do
		if NemesisMath.hasTrait(look.traits, i) then
			if t.id == "plates" then
				add(out, "plates", 0, -0.7, -1.15, 3.2 * wide, 1.8, 0.3, trim, "DiamondPlate")
			elseif t.id == "second" then
				local gun = add(out, "cannon", 2.4 * wide, 1.5, -0.6, 2.6, 0.9, 0.9, trim, "Metal")
				gun.shape = "Cylinder" -- a cylinder's axis is its x: turned to point forward
				gun.ry = math.pi / 2
			elseif t.id == "healDrone" then
				local d = add(out, "healDrone", -2.6 * wide, 3.4, -0.4, 1, 1, 1, { 120, 255, 140 }, "Neon")
				d.shape = "Ball"
				d.glow = true
			elseif t.id == "summon" then
				add(out, "antenna", 0.7, 5.2, 0.5, 0.2, 2, 0.2, trim, "Metal")
			end
		end
	end
	return out
end

-- Where things hang on the wall, in the wall's frame: origin at the face's foot (Config.Hq.wanted.wall), -z out
-- into the room, +x the frame's right (the viewer's left, as they face the wall). `poster` is its middle and
-- size; `mounts[r]` the middle of rank r's mount (rank 1 on the viewer's left) and `plates[r]` its name plate.
export type Spot = { x: number, y: number, z: number, sx: number, sy: number, sz: number }
function WantedRules.layout(Config: any): { poster: Spot, board: Spot, mounts: { Spot }, plates: { Spot } }
	local W = Config.Hq.wanted
	local P, Hd = W.poster, W.heads
	local n = Config.Nemesis.maxRank
	local mounts, plates = {}, {}
	for r = 1, n do
		local u = (r - (n + 1) / 2) * Hd.step
		table.insert(mounts, { x = -u, y = Hd.y, z = -0.25, sx = Hd.mount[1], sy = Hd.mount[2], sz = 0.3 })
		table.insert(plates, {
			x = -u,
			y = Hd.y - Hd.mount[2] / 2 - Hd.plate[2] / 2 - 0.05,
			z = -0.3,
			sx = Hd.plate[1],
			sy = Hd.plate[2],
			sz = 0.2,
		})
	end
	return {
		poster = { x = -P.u, y = P.y, z = -0.4, sx = P.w, sy = P.h, sz = 0.1 },
		board = { x = -P.u, y = P.y, z = -0.2, sx = P.w + P.board, sy = P.h + P.board, sz = 0.3 },
		mounts = mounts,
		plates = plates,
	}
end

-- Where a head sits on its mount: its back on the plaque's face (a head is 2 studs deep)
function WantedRules.headAt(mount: Spot): (number, number, number)
	return mount.x, mount.y, mount.z - mount.sz / 2 - 1
end

-- A point in the wall's frame as a cell offset (x, y, z), for the tests and the server
function WantedRules.toCell(Config: any, x: number, y: number, z: number): (number, number, number)
	local w = Config.Hq.wanted.wall
	-- the frame looks along (nx, nz): its right is (-nz, nx) and its back (-nx, -nz)
	return w.x + -w.nz * x + -w.nx * z, y, w.z + w.nx * x + -w.nz * z
end

return WantedRules
