--!strict
-- OpeningPlan: the Ceremony prologue as plain rules (nate's lore, build plan step 3; mission 1). Pure, from the
-- world data, so Lune checks every point is real for any weekly seed and both sides' beats.
-- * route: where it all happens for one new hero: Crane's Hero Hall (the Beacon Tower) and the stage before it
--   (Silas Crane, the three famous fakes, the scanner), the crowd on the street, the hero's start among them,
--   the spark point down the street (the kid or the shover), the rooftop row's roofs one Leap apart for the
--   chase (Config.City.downtown.row; a chain of ordinary roofs if the row is missing), the subway steps below
--   the last roof, the billboard for the last shot and where the hero lands after.
-- * lane: one prologue's tunnel in the subway pocket (PocketLayout.lane): start, collapses, fight chamber.
-- * STEPS: the beats in order. CUT beats are camera beats (letterbox, no control); TIMED beats move on by
--   the clock; every other beat moves on by itself after Config.Story.opening.stuck seconds.
-- * lines: the subtitled lines of a beat for a side (fixed text in Config.Story.opening.lines).

local IncidentSpots = if script
	then require(script.Parent.IncidentSpots)
	else (require :: any)("./IncidentSpots")
local HeightMap = if script then require(script.Parent.HeightMap) else (require :: any)("./HeightMap")
local PocketLayout = if script
	then require(script.Parent.PocketLayout)
	else (require :: any)("./PocketLayout")

local OpeningPlan = {}

export type Point = { number }

export type Route = {
	hall: Point, -- the Hall's foot (its centre at street level)
	face: Point, -- { fx, 0, fz }: from the Hall toward the crowd
	stage: Point, -- the stage's top, at its centre
	crane: Point,
	fakes: { Point }, -- Radiant, Bulwark, Skylance on the stage
	scanner: Point, -- the scanner drone over the stage
	crowd: { Point },
	start: Point,
	spark: Point,
	kid: Point, -- the kid under the falling sign (Vigil) or the man who shoves (Syndicate)
	roofs: { Point }, -- the climb roof, then one Leap at a time
	entrance: Point, -- the subway steps
	billboard: { number }, -- { x, y, z, nx, nz }: the board's centre and the way it faces
	landing: Point, -- where the hero is after the title
}

-- (PocketLayout.Lane, repeated: the pure-module require pattern drops cross-module types)
export type Lane = {
	index: number,
	x: number,
	z0: number,
	z1: number,
	floorY: number,
	start: { number },
	fight: { number },
	collapses: { { z: number } },
}

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

local function roofPoint(b: any): Point
	return { b.x, b.top + 1.5, b.z }
end

-- The beats in order
OpeningPlan.STEPS = {
	"ceremony",
	"scan",
	"run",
	"spark",
	"leap",
	"chase",
	"suit",
	"descend",
	"tunnel",
	"fight",
	"swarm",
	"rescue",
	"title",
}
OpeningPlan.CODE = {} :: { [string]: number }
for i, s in OpeningPlan.STEPS do
	OpeningPlan.CODE[s] = i
end
-- camera beats: letterbox, the scripted camera, no control
OpeningPlan.CUT = { ceremony = true, scan = true, rescue = true, title = true }
-- the beats the hero spends in the city (the rest are in the subway pocket)
OpeningPlan.CITY = {
	ceremony = true,
	scan = true,
	run = true,
	spark = true,
	leap = true,
	chase = true,
	suit = true,
	descend = true,
	title = true,
}

-- The plaza: Crane's Hero Hall (the Beacon Tower's square) in Downtown
function OpeningPlan.plaza(world: any): (number, number)
	local bt = world.downtown and world.downtown.beacon
	return if bt then bt.x else -400, if bt then bt.z else 0
end

function OpeningPlan.next(step: string): string?
	local i = OpeningPlan.CODE[step]
	return if i then OpeningPlan.STEPS[i + 1] else nil
end

-- How long a beat may run before it moves on by itself (a timed beat's own length)
function OpeningPlan.limit(Config: any, step: string): number
	local O = Config.Story.opening
	return O.beats[step] or O.stuck[step] or 30
end

-- Is this beat over by the clock alone (no goal to reach)?
function OpeningPlan.timed(Config: any, step: string): boolean
	return Config.Story.opening.beats[step] ~= nil
end

-- May the skip button show? Only on the camera beats, and only on a replay or for a returning account (a
-- first-time player sees the story once in full).
function OpeningPlan.canSkip(step: string, replay: boolean): boolean
	return replay and OpeningPlan.CUT[step] == true
end

-- The side's own spark beat: a Vigil hero's Spark makes a shield over the kid; a Syndicate villain's blasts
-- the man who shoved them across the plaza (cartoon, nobody hurt-looking)
function OpeningPlan.sparkBeat(side: string): string
	return if side == "villain" then "blast" else "shield"
end

-- The subtitled lines of a beat for a side: { at, who, text }, in time order
function OpeningPlan.lines(
	Config: any,
	step: string,
	side: string
): { { at: number, who: string, text: string } }
	local out = {}
	local key = if side == "villain" then "villain" else "hero"
	for _, l in Config.Story.opening.lines[step] or {} do
		local text = l.text or l[key]
		if type(text) == "string" then
			table.insert(out, { at = l.at, who = l.who, text = text })
		end
	end
	table.sort(out, function(a, b)
		return a.at < b.at
	end)
	return out
end

-- Does this character play the prologue now? Made in the creator (created 1) and not through it yet. A save
-- from before lore step 3 that stopped mid-opening (created 1, opening 0) starts the new prologue from its first
-- beat; anyone past the old opening (opening 1) never sees it again.
function OpeningPlan.due(c: any): boolean
	return type(c) == "table" and c.created == 1 and type(c.story) == "table" and c.story.opening == 0
end

-- The prologue's subway lane i (1 to lanes) in the subway pocket
function OpeningPlan.lane(Config: any, i: number): Lane
	return PocketLayout.lane(Config, i)
end

-- Kid-proof (nate's playtest 2026-11-18): the tunnel caves in behind the hero. Does slab k fall now, with the
-- hero at z? (the lane runs toward lower z: the slab falls once the hero is Config's `behind` studs past it)
function OpeningPlan.slabFalls(Config: any, lane: Lane, k: number, z: number): boolean
	local c = lane.collapses[k]
	local S = Config.Story.opening.subway
	return c ~= nil and z <= c.z - S.slab / 2 - S.behind
end

-- The fight chamber's floor as a room its robots never leave: { x0, x1, z0, z1, yMax } (`pad` studs in from the
-- walls; yMax keeps a flyer under the ceiling, in reach)
function OpeningPlan.chamber(Config: any, lane: Lane, pad: number?): { number }
	local S = Config.Story.opening.subway
	local p = pad or 3
	local half = S.chamber / 2 - p
	return {
		lane.x - half,
		lane.x + half,
		lane.z1 - S.chamber + p,
		lane.z1 - p,
		lane.floorY + math.min(S.height - 6, 10),
	}
end

-- The beats whose hops are guided (kid-proof): one Leap press on a roof sends the hero on a set arc straight to
-- the next roof (or, from the last roof, down to the subway steps), so no hop can be missed
OpeningPlan.HOPS = { leap = true, chase = true, descend = true }

-- The guided hop from `from` to the beat's target: its time and its arc's height over the higher end
function OpeningPlan.hopArc(Config: any, from: { number }, to: { number }): (number, number)
	local H = Config.Story.opening.hop
	local flat = dist(from[1], from[3], to[1], to[3])
	local drop = math.max(0, from[2] - to[2])
	local time = math.clamp(flat / H.speed + drop / H.fall, H.time[1], H.time[2])
	local height = math.clamp(flat * H.lift, H.height[1], H.height[2])
	return time, height
end

-- The one plain instruction a beat shows (Config.Ui.prologue.hints; a beat's text, or its `hero` and `villain`
-- texts), with each {Action} named the way this device shows it (keyOf: "SPACE", "the LEAP button", "A")
function OpeningPlan.hint(Config: any, step: string, side: string, keyOf: (string) -> string): string?
	local h = Config.Ui.prologue.hints[step]
	if type(h) == "table" then
		h = h[if side == "villain" then "villain" else "hero"]
	end
	if type(h) ~= "string" then
		return nil
	end
	return (string.gsub(h, "{(%w+)}", keyOf))
end

-- Where the hero is put when a beat starts away from its place (a stuck beat moving on, a dev jump, a respawn)
function OpeningPlan.startPoint(route: Route, lane: Lane?, step: string): Point
	if step == "ceremony" or step == "scan" or step == "run" then
		return route.start
	elseif step == "spark" then
		return route.spark
	elseif step == "leap" then
		return route.roofs[1]
	elseif step == "chase" then
		return route.roofs[2]
	elseif step == "suit" or step == "descend" then
		return route.roofs[#route.roofs]
	elseif step == "title" then
		return route.landing
	elseif lane then
		return if step == "tunnel" then lane.start else lane.fight
	end
	return route.landing
end

-- Is a hero at a target? (within reach on the ground plane, and not far below it)
function OpeningPlan.at(
	Config: any,
	target: { number },
	x: number,
	y: number,
	z: number,
	reach: number?
): boolean
	local r = reach or Config.Story.opening.reach
	return dist(x, z, target[1], target[3]) <= r and y >= target[2] - 4 and y <= target[2] + 40
end

local function onGround(Config: any, world: any, x: number, z: number): boolean
	if not world.heights then
		return true
	end
	return HeightMap.at(world.heights, x, z) <= Config.City.ground.y + 1.5
end

local function groundY(Config: any, world: any, x: number, z: number): number
	local gy = Config.City.ground.y
	if not world.heights then
		return gy + 0.2
	end
	return math.max(gy + 0.2, HeightMap.at(world.heights, x, z))
end

-- The rooftop row's first `count` roofs (CityLayout's Layout.row), when every hop is one Leap and no higher
-- than a Leap climbs; nil if the row is missing or short (the route then picks a chain of ordinary roofs)
local function rowRoofs(Config: any, world: any, count: number): { any }?
	local row = world.downtown and world.downtown.row
	if not row or #row < count then
		return nil
	end
	local R = Config.Story.opening.roofs
	local reach = math.min(R.gap[2], Config.Move.leap.range)
	local list = {}
	for i = 1, count do
		local b = row[i]
		if not b then
			return nil
		end
		local cur = list[#list]
		if cur then
			local gap = dist(b.x, b.z, cur.x, cur.z)
			if gap < R.gap[1] or gap > reach or b.top > cur.top + R.climb then
				return nil
			end
		end
		table.insert(list, b)
	end
	return list
end

-- A chain of `count` roofs from `first`, each one Leap from the last and no higher than a Leap climbs (in a
-- Downtown block of 2 x 2 lots, the three tallest in falling order always make one)
local function roofChain(Config: any, world: any, first: any, count: number, rng: any): { any }?
	local R = Config.Story.opening.roofs
	local gy = Config.City.ground.y
	local chain = { first }
	local used = { [first.id] = true }
	local function grow(): boolean
		if #chain >= count then
			return true
		end
		local cur = chain[#chain]
		local options = {}
		for _, b in world.buildings do
			local gap = dist(b.x, b.z, cur.x, cur.z)
			local h = b.top - gy
			if
				not used[b.id]
				and gap >= R.gap[1]
				and gap <= R.gap[2]
				and h >= R.minH
				and b.top <= cur.top + R.climb
			then
				table.insert(options, b)
			end
		end
		table.sort(options, function(a, b)
			return a.id < b.id
		end)
		local n = #options
		local offset = if n > 0 then rng:int(1, n) else 1
		for k = 0, n - 1 do
			local b = options[(offset + k - 1) % n + 1]
			table.insert(chain, b)
			used[b.id] = true
			if grow() then
				return true
			end
			table.remove(chain)
			used[b.id] = nil
		end
		return false
	end
	return if grow() then chain else nil
end

function OpeningPlan.route(Config: any, world: any, rng: any): Route?
	local O = Config.Story.opening
	local P = O.plaza
	local gy = Config.City.ground.y
	local hx, hz = OpeningPlan.plaza(world)
	local half = Config.City.downtown.beacon.width / 2
	local plazaTop = gy + 1.1
	-- the stage's side of the Hall: one of the four, picked by the seed, whose crowd stands on open ground
	local dirs = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
	local first = rng:int(1, 4)
	-- with the rooftop row, the stage faces it (so the chase starts across the street from the crowd)
	local lineRoofs = rowRoofs(Config, world, O.roofs.count)
	if lineRoofs then
		local rx, rz = lineRoofs[1].x - hx, lineRoofs[1].z - hz
		local along = math.abs(rx) >= math.abs(rz)
		local wx = if along then math.sign(rx) else 0
		local wz = if along then 0 else math.sign(rz)
		for k, d in dirs do
			if d[1] == wx and d[2] == wz then
				first = k
			end
		end
	end
	local face, crowd = nil, nil
	for k = 0, 3 do
		local d = dirs[(first + k - 1) % 4 + 1]
		local fx, fz = d[1], d[2]
		local sx, sz = -fz, fx
		local front = half + P.stage.gap + P.stage.depth
		local list = {}
		local ok = true
		local perRow = math.ceil(P.crowd.count / P.crowd.rows)
		for row = 1, P.crowd.rows do
			local along = front
				+ P.crowd.near
				+ (row - 1) * (P.crowd.far - P.crowd.near) / math.max(1, P.crowd.rows - 1)
			for i = 1, perRow do
				if #list >= P.crowd.count then
					break
				end
				local across = (i - (perRow + 1) / 2) * (P.stage.width / perRow) * 1.25 + (row % 2) * 2.5
				local x, z = hx + fx * along + sx * across, hz + fz * along + sz * across
				if not onGround(Config, world, x, z) then
					ok = false
					break
				end
				table.insert(list, { x, groundY(Config, world, x, z), z })
			end
		end
		if ok then
			face, crowd = d, list
			break
		end
	end
	if not face or not crowd then
		return nil
	end
	local fx, fz = face[1], face[2]
	local sx, sz = -fz, fx
	local mid = half + P.stage.gap + P.stage.depth / 2
	local stage = { hx + fx * mid, plazaTop + P.stage.height, hz + fz * mid }
	local function onStage(back: number, across: number): Point
		return { stage[1] + fx * back + sx * across, stage[2], stage[3] + fz * back + sz * across }
	end
	local front = half + P.stage.gap + P.stage.depth
	local sx0, sz0 = hx + fx * (front + P.start), hz + fz * (front + P.start)
	local start = { sx0, groundY(Config, world, sx0, sz0), sz0 }
	-- the spark point: open ground down the street, never back toward the stage (with the rooftop row, the
	-- spot of a few nearest its first roof, so the chase starts close by)
	local spark = nil
	local best = math.huge
	for _ = 1, 24 do
		local s = IncidentSpots.find(Config, world, "street", start[1], start[3], O.run.minD, O.run.maxD, rng)
		if s then
			local away = (s.x - hx) * fx + (s.z - hz) * fz
			if away >= front and dist(s.x, s.z, hx, hz) >= front + 20 then
				local d = if lineRoofs then dist(s.x, s.z, lineRoofs[1].x, lineRoofs[1].z) else 0
				if d < best then
					spark, best = s, d
				end
				if not lineRoofs then
					break
				end
			end
		end
	end
	if not spark then
		return nil
	end
	-- the kid (or the shover) a few studs further on, between the hero and the spark point's far side
	local kx, kz = spark.x + fx * P.kid, spark.z + fz * P.kid
	local kid = { kx, groundY(Config, world, kx, kz), kz }
	-- the rooftop chase: the rooftop row; without it, a low roof near the spark point, then one Leap at a time
	local R = O.roofs
	local chain = lineRoofs
	local climbs = {}
	for _, b in world.buildings do
		local h = b.top - gy
		local d = dist(b.x, b.z, spark.x, spark.z)
		if
			not chain
			and b.district == "Downtown"
			and h >= R.minH
			and h <= R.maxH
			and d >= R.near[1]
			and d <= R.near[2]
		then
			table.insert(climbs, b)
		end
	end
	table.sort(climbs, function(a, b)
		return a.id < b.id
	end)
	local nc = if chain then 0 else #climbs
	local offset = if nc > 0 then rng:int(1, nc) else 1
	for k = 0, nc - 1 do
		chain = roofChain(Config, world, climbs[(offset + k - 1) % nc + 1], R.fallback, rng)
		if chain then
			break
		end
	end
	if not chain then
		return nil
	end
	local found = chain :: { any }
	local roofs = {}
	for _, b in found do
		table.insert(roofs, roofPoint(b))
	end
	local last = found[#found]
	local ent =
		IncidentSpots.find(Config, world, "street", last.x, last.z, O.entrance.minD, O.entrance.maxD, rng)
	if not ent then
		return nil
	end
	-- the billboard: a tall building's face toward the plaza
	local B = O.billboard
	local boards = {}
	for _, b in world.buildings do
		local d = dist(b.x, b.z, hx, hz)
		if b.top - gy >= B.minH and d >= B.near[1] and d <= B.near[2] and b.sx >= B.size[1] * 0.6 then
			table.insert(boards, b)
		end
	end
	if #boards == 0 then
		return nil
	end
	table.sort(boards, function(a, b)
		return a.id < b.id
	end)
	local bb = boards[rng:int(1, #boards)]
	local nx, nz = 0, 0
	if math.abs(hx - bb.x) / bb.sx > math.abs(hz - bb.z) / bb.sz then
		nx = if hx > bb.x then 1 else -1
	else
		nz = if hz > bb.z then 1 else -1
	end
	local by = math.min(bb.top - B.size[2] / 2 - 6, gy + 40 + B.size[2] / 2)
	local billboard = {
		bb.x + nx * ((bb.sx / 2) + 1.5),
		by,
		bb.z + nz * ((bb.sz / 2) + 1.5),
		nx,
		nz,
	}
	return {
		hall = { hx, gy, hz },
		face = { fx, 0, fz },
		stage = stage,
		crane = onStage(-2, 0),
		fakes = { onStage(-5, -15), onStage(-5, 5), onStage(-5, 16) },
		scanner = { stage[1], stage[2] + 18, stage[3] },
		crowd = crowd,
		start = start,
		spark = { spark.x, spark.y, spark.z },
		kid = kid,
		roofs = roofs,
		entrance = { ent.x, ent.y, ent.z },
		billboard = billboard,
		landing = start,
	}
end

return OpeningPlan
