--!strict
-- SideQuestSites: where side quest chains happen in the city (nate's lore, build plan step 11). Pure, so Lune
-- checks the picks for the seeded layout; SideQuestService stands the giver at the door, puts up the sign or
-- the set piece and marks the map.
-- * building(Config, world, id): the building for Config.SideQuests.sites[id]. Downtown: of the buildings that
--   fit (a height in range, no skyscraper crown, `away` studs from the Beacon Tower's plaza, every roof of the
--   prologue's chase row, the Vigil's stairwell and the open squares), the one nearest `near` (studs from the
--   Beacon Tower). Uptown (chain 2's bank): the one nearest `near` from Uptown's landmark tower, `away`.landmark
--   from it. nate (2026-11-17): the Hero Academy is an existing building, not an open square.
-- * square(Config, world, id): a site in one of Downtown's open squares (`square`: a Config.City.downtown.open
--   id; nate kept both for The Gala Heist): the square's record { id, x, z, size }.
-- * door(world, b, ox?, oz?): the face of that building that opens on a street (a point 10 studs out is in no
--   building), nearest the plaza (or the point ox, oz): { x, z, fx, fz } (fx, fz: the way out).
-- * place / spot: a site's building or square and where its giver stands (a door, or the square's `spot`).
-- * course(Config, world, id): a rooftop race course (Config.SideQuests.courses, chain 2): `count` roofs of the
--   start site's district from the roof nearest it, heading toward `toward`, every hop inside the 6-roof chase
--   row's rules (hopOk: at least the row's shortest gap apart, an edge-to-edge jump within one Leap, no rise
--   past a Leap's climb), never on the row, a skyscraper or another chain's building.
-- * farm(Config, world, id) (lore step 11, chain 4: The Harvest King): a Farmland site on this week's outskirts
--   tiles (`farm`: a red clapboard barn, a pair of grain silos or a crop field, read from the tile's own plan;
--   `road`: a spot on a farm road), clear of every safehouse, beacon and landmark: { kind, x, z, sx, sz, top,
--   tx, tz, door }. tileLots lists one tile's lots; roadPath runs an escort down a farm road toward town.
-- * outskirts(Config, world, id): a site out in the seeded Suburbs (a site with `lot`, the Suburbs chain's toy
--   shop): of the lots of that kind on Suburbs tiles `rings` out from the hub edge, built with their building
--   (a lot under a safehouse pad stays empty) and a height in range, the one nearest `near` (map studs) that
--   keeps `away` studs from every safehouse, beacon, landmark centre, city district and every other chain site
--   (Downtown ones, and outskirts ones earlier by id). The outskirts change weekly with the seed, so the shop
--   does too; the same seed always picks the same shop. Its door is the front (outskirts buildings face +z).
-- * shore(Config, world, id): a site on the seeded coast (a site with `shore`, the Coast chain's Gull Point
--   Pier): of the coast tiles with that feature in `rings`, the pier whose foot is nearest `near` and keeps the
--   same `away` distances; its way in is the sand at the pier's foot, facing inland. Weekly like the shop.

local HqRules = if script then require(script.Parent.HqRules) else (require :: any)("./HqRules")
local WorldGen = if script then require(script.Parent.WorldGen) else (require :: any)("./WorldGen")
local WorldMap = if script then require(script.Parent.WorldMap) else (require :: any)("./WorldMap")

local SideQuestSites = {}

export type Door = { x: number, z: number, fx: number, fz: number }

local function flat(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- Does building b keep every distance site st asks for?
function SideQuestSites.fits(Config: any, world: any, st: any, b: any): boolean
	local a = st.away
	if b.crown or b.h < st.height[1] or b.h > st.height[2] then
		return false
	end
	if st.district == "Uptown" then
		-- chain 2's bank: clear of Uptown's landmark tower and the plaza round it
		local lm = world.uptown.landmark
		return flat(b.x, b.z, lm.x, lm.z) >= a.landmark
	end
	local L = world.downtown
	local bt = L.beacon
	if flat(b.x, b.z, bt.x, bt.z) < a.plaza then
		return false
	end
	for _, r in L.row or {} do
		if flat(b.x, b.z, r.x, r.z) < a.row then
			return false
		end
	end
	local hd = HqRules.heroDoor(Config, world)
	if hd and flat(b.x, b.z, hd.x, hd.z) < a.door then
		return false
	end
	for _, o in L.open or {} do
		if math.abs(b.x - o.x) <= o.size / 2 + a.open and math.abs(b.z - o.z) <= o.size / 2 + a.open then
			return false
		end
	end
	return true
end

-- The building a site is in, or nil (no such district, a square site, or nothing fits)
function SideQuestSites.building(Config: any, world: any, id: string): any?
	local st = Config.SideQuests.sites[id]
	if not st or st.square or SideQuestSites.isOutskirts(st) or st.farm or st.road then
		return nil
	end
	local L, ox, oz
	if st.district == "Uptown" then
		L = world and world.uptown
		if not L or not L.landmark then
			return nil
		end
		ox, oz = L.landmark.x, L.landmark.z
	else
		L = world and world.downtown
		if not L or not L.beacon then
			return nil
		end
		ox, oz = L.beacon.x, L.beacon.z
	end
	local tx, tz = ox + st.near[1], oz + st.near[2]
	local best, bestD = nil, math.huge
	for _, b in L.buildings do
		if SideQuestSites.fits(Config, world, st, b) then
			local d = flat(b.x, b.z, tx, tz)
			if d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

local FACES = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }

-- The way in: the street-side face nearest the plaza (or the point ox, oz)
function SideQuestSites.door(world: any, b: any, ox: number?, oz: number?): Door
	local tx = ox or world.downtown.beacon.x
	local tz = oz or world.downtown.beacon.z
	local best: Door? = nil
	local bestD = math.huge
	for _, f in FACES do
		local half = if f[1] ~= 0 then b.sx / 2 else b.sz / 2
		local x, z = b.x + f[1] * (half + 10), b.z + f[2] * (half + 10)
		local clear = true
		for _, o in world.buildings do
			for _, out in { 6, 10 } do
				local px, pz = b.x + f[1] * (half + out), b.z + f[2] * (half + out)
				if math.abs(px - o.x) < o.sx / 2 + 2 and math.abs(pz - o.z) < o.sz / 2 + 2 then
					clear = false
				end
			end
		end
		local d = flat(x, z, tx, tz)
		if clear and d < bestD then
			best, bestD =
				{ x = b.x + f[1] * (half + 6), z = b.z + f[2] * (half + 6), fx = f[1], fz = f[2] }, d
		end
	end
	return best or { x = b.x, z = b.z + b.sz / 2 + 6, fx = 0, fz = 1 }
end

-----------------------------------------------------------------------------------------------------------
-- Outskirts sites (the seeded Suburbs)
-----------------------------------------------------------------------------------------------------------

-- Is this site out in the outskirts (picked from a Suburbs lot, or a coast tile's feature with `shore`) rather
-- than in a Downtown building?
function SideQuestSites.isOutskirts(st: any): boolean
	return type(st) == "table" and (st.lot ~= nil or st.shore ~= nil)
end

-- Is this an outskirts site on the coast (a `shore` feature: The Salt Dogs' pier)?
function SideQuestSites.isShore(st: any): boolean
	return type(st) == "table" and st.shore ~= nil
end

-- A shore site's way in (lore step 11, the Coast chain): on the sand 14 studs in from the pier's foot (clear of
-- the deck's 10-stud height cell), facing inland, where the giver stands
function SideQuestSites.shoreDoor(b: any): Door
	local p = b.pier
	return { x = p.foot[1] - p.ox * 14, z = p.foot[2] - p.oz * 14, fx = -p.ox, fz = -p.oz }
end

-- A site's way in once its outskirts building (or pier) is known
local function outskirtsDoor(st: any, b: any): Door
	return if SideQuestSites.isShore(st) then SideQuestSites.shoreDoor(b) else SideQuestSites.frontDoor(b)
end

-- Distance from a point to a rectangle (0 inside it)
local function toRect(x: number, z: number, r: any): number
	local dx = math.max(r.minX - x, 0, x - r.maxX)
	local dz = math.max(r.minZ - z, 0, z - r.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- The front door of an outskirts building (its +z face, where the kit puts the shop window and mailbox)
function SideQuestSites.frontDoor(b: any): Door
	return { x = b.x, z = b.z + b.sz / 2 + 6, fx = 0, fz = 1 }
end

-- The centres of the other chain sites this one keeps away from (Downtown sites, and outskirts sites that come
-- earlier by id, so two outskirts sites never wait on each other)
local function otherSites(Config: any, world: any, id: string): { { number } }
	local out = {}
	for other, st in Config.SideQuests.sites do
		if other ~= id then
			local b = nil
			if not SideQuestSites.isOutskirts(st) then
				b = SideQuestSites.place(Config, world, other)
			elseif other < id then
				b = SideQuestSites.outskirts(Config, world, other)
			end
			if b then
				table.insert(out, { b.x, b.z })
			end
		end
	end
	return out
end

-- Does an outskirts building keep every distance its site asks for?
function SideQuestSites.outskirtsFits(
	Config: any,
	world: any,
	st: any,
	b: any,
	others: { { number } }?
): boolean
	local a = st.away
	local gy = Config.City.ground.y
	-- (a shore site's pier has no height rule: its deck is the beach's own)
	if st.height and (b.h < st.height[1] or b.h > st.height[2]) then
		return false
	end
	for _, s in world.safehouses do
		if flat(b.x, b.z, s.x, s.z) < a.pad then
			return false
		end
	end
	for _, bc in world.beacons do
		if flat(b.x, b.z, bc.x, bc.z) < a.beacon then
			return false
		end
	end
	for _, lm in Config.World.landmarks do
		local x0, z0 = WorldGen.tileOrigin(Config.City, lm.tx, lm.tz)
		local half = lm.size * Config.City.tile / 2
		if flat(b.x, b.z, x0 + half, z0 + half) < a.landmark then
			return false
		end
	end
	for _, d in Config.City.districts do
		if toRect(b.x, b.z, d) < a.district then
			return false
		end
	end
	for _, o in others or {} do
		if flat(b.x, b.z, o[1], o[2]) < a.site then
			return false
		end
	end
	-- the way in is open ground (not a fence, a tree or the next lot's house; for a pier, the sand at its foot)
	local door = outskirtsDoor(st, b)
	if world.heights and WorldMap.heightAt(world, door.x, door.z) > gy + 1.5 then
		return false
	end
	return true
end

-- picks per world, kept once found: CityBuilder drops world.tilePlans after building, so a site read later
-- (a giver met an hour in) uses the pick made while the plans were there (SideQuestSites.warm)
local outskirtsCache: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

-- The outskirts building a site is in, or nil: { x, z, sx, sz, h, top, tx, tz, lot }
function SideQuestSites.outskirts(Config: any, world: any, id: string): any?
	local st = Config.SideQuests.sites[id]
	if not SideQuestSites.isOutskirts(st) or not world or not world.tiles then
		return nil
	end
	if SideQuestSites.isShore(st) then
		return SideQuestSites.shore(Config, world, id) -- read from WorldGen, never the plans
	end
	local byWorld = outskirtsCache[world]
	if byWorld and byWorld[id] ~= nil then
		return byWorld[id] or nil
	end
	if not world.tilePlans or #world.tilePlans == 0 then
		return nil
	end
	local best = SideQuestSites.pickOutskirts(Config, world, id, st)
	if not byWorld then
		byWorld = {}
		outskirtsCache[world] = byWorld
	end
	byWorld[id] = best or false
	return best
end

-- Every outskirts site's pick, made now while world.tilePlans still holds the tiles' boxes
function SideQuestSites.warm(Config: any, world: any)
	for id, st in Config.SideQuests.sites do
		if SideQuestSites.isOutskirts(st) then
			SideQuestSites.outskirts(Config, world, id)
		end
	end
end

-- The search behind SideQuestSites.outskirts (no cache)
function SideQuestSites.pickOutskirts(Config: any, world: any, id: string, st: any): any?
	local w = Config.World
	local plans: { [number]: any } = {}
	for _, plan in world.tilePlans do
		plans[plan.tz * w.tiles + plan.tx] = plan
	end
	local others = otherSites(Config, world, id)
	local best, bestD = nil, math.huge
	for tz = 0, w.tiles - 1 do
		for tx = 0, w.tiles - 1 do
			local ring = WorldGen.ring(w, tx, tz)
			local plan = plans[tz * w.tiles + tx]
			if plan and ring >= st.rings[1] and ring <= st.rings[2] then
				for _, lot in WorldGen.suburbLots(Config.City, w, world.tiles, tx, tz) do
					if lot.kind == st.lot then
						-- the lot's building: the plain body box standing inside the lot
						local body = nil
						for _, x in plan.boxes do
							if
								x.kind == "building"
								and x.shape == nil
								and x.cx > lot.x0
								and x.cx < lot.x1
								and x.cz > lot.z0
								and x.cz < lot.z1
							then
								body = x
								break
							end
						end
						if body then
							local b = {
								x = body.cx,
								z = body.cz,
								sx = body.sx,
								sz = body.sz,
								h = body.sy,
								top = body.cy + body.sy / 2,
								tx = tx,
								tz = tz,
								lot = lot,
							}
							local d = flat(b.x, b.z, st.near[1], st.near[2])
							if d < bestD and SideQuestSites.outskirtsFits(Config, world, st, b, others) then
								best, bestD = b, d
							end
						end
					end
				end
			end
		end
	end
	return best
end

-- A shore site's pier (lore step 11, the Coast chain: The Salt Dogs' Gull Point Pier), or nil: of the coast
-- tiles in `rings` whose feature is `shore` (Shared.WorldGen.COAST; only "pier" has a placing rule), the one
-- whose foot is nearest `near` and keeps every `away` distance (the same rule as a Suburbs lot). The record is
-- { x, z (the pier's foot on the sand), sx, sz (its deck), h, top, tx, tz, pier }.
function SideQuestSites.shore(Config: any, world: any, id: string): any?
	local st = Config.SideQuests.sites[id]
	if not SideQuestSites.isShore(st) or st.shore ~= "pier" or not world or not world.tiles then
		return nil
	end
	local w = Config.World
	local gy = Config.City.ground.y
	local others = otherSites(Config, world, id)
	local best, bestD = nil, math.huge
	for tz = 0, w.tiles - 1 do
		for tx = 0, w.tiles - 1 do
			local ring = WorldGen.ring(w, tx, tz)
			if ring >= st.rings[1] and ring <= st.rings[2] then
				local p = WorldGen.pier(Config.City, w, world.tiles, tx, tz)
				if p then
					local b = {
						x = p.foot[1],
						z = p.foot[2],
						sx = p.sx,
						sz = p.sz,
						h = 0,
						top = gy + 2.5, -- the deck
						tx = tx,
						tz = tz,
						pier = p,
					}
					local d = flat(b.x, b.z, st.near[1], st.near[2])
					if d < bestD and SideQuestSites.outskirtsFits(Config, world, st, b, others) then
						best, bestD = b, d
					end
				end
			end
		end
	end
	return best
end

-- A square site's open square (chain 2: The Gala Heist), or nil
function SideQuestSites.square(Config: any, world: any, id: string): any?
	local st = Config.SideQuests.sites[id]
	local L = world and world.downtown
	if not st or not st.square or not L then
		return nil
	end
	for _, o in L.open or {} do
		if o.id == st.square then
			return o
		end
	end
	return nil
end

-- A site's building (or open square, or outskirts lot's building) and its way in, or nil. A square's way in is
-- its `spot` (studs from the square's middle), facing out of the square's nearer side; an outskirts building's
-- is its front.
function SideQuestSites.place(Config: any, world: any, id: string): (any?, Door?)
	local st = Config.SideQuests.sites[id]
	if not st then
		return nil, nil
	end
	if SideQuestSites.isOutskirts(st) then
		local b = SideQuestSites.outskirts(Config, world, id)
		if not b then
			return nil, nil
		end
		return b, outskirtsDoor(st, b)
	end
	if st.square then
		local o = SideQuestSites.square(Config, world, id)
		if not o then
			return nil, nil
		end
		local s = st.spot or { 0, 0 }
		return o, { x = o.x + s[1], z = o.z + s[2], fx = 0, fz = if s[2] < 0 then -1 else 1 }
	end
	if st.farm or st.road then
		-- lore step 11, chain 4: a Farmland site on the outskirts tiles
		local lot = SideQuestSites.farm(Config, world, id)
		if not lot then
			return nil, nil
		end
		return lot, lot.door
	end
	local b = SideQuestSites.building(Config, world, id)
	if not b then
		return nil, nil
	end
	if st.district == "Uptown" then
		local lm = world.uptown.landmark
		return b, SideQuestSites.door(world, b, lm.x, lm.z)
	end
	return b, SideQuestSites.door(world, b)
end

-- Where a site is on the ground (its door or its square's spot), or nil
function SideQuestSites.spot(Config: any, world: any, id: string): (number?, number?)
	local _, door = SideQuestSites.place(Config, world, id)
	if not door then
		return nil, nil
	end
	return door.x, door.z
end

---------------------------------------------------------------------------
-- Rooftop race courses (chain 2: The Gala Heist with Rooftop Racers)
---------------------------------------------------------------------------

-- The gap between two roofs' edges (0 when they touch or overlap)
function SideQuestSites.edge(a: any, b: any): number
	local dx = math.max(0, math.abs(a.x - b.x) - (a.sx + b.sx) / 2)
	local dz = math.max(0, math.abs(a.z - b.z) - (a.sz + b.sz) / 2)
	return math.sqrt(dx * dx + dz * dz)
end

-- Is the hop from roof a to roof b inside the 6-roof chase row's rules? (Config.Story.opening.roofs: at least
-- gap[1] apart centre to centre and no rise past a Leap's climb; the jump, edge to edge, within
-- Config.SideQuests.courses.jump, the widest the row's own rule allows on its narrowest roofs)
function SideQuestSites.hopOk(Config: any, a: any, b: any): boolean
	local R = Config.Story.opening.roofs
	return flat(a.x, a.z, b.x, b.z) >= R.gap[1]
		and SideQuestSites.edge(a, b) <= Config.SideQuests.courses.jump
		and b.top <= a.top + R.climb
end

-- The roofs a course may use in a district: real roofs (no crown, minH to maxH tall), never the chase row,
-- never another chain's building (keep: the course's own site building, which it may start on)
local function roofPool(Config: any, world: any, district: string, keep: any?): { any }
	local R = Config.Story.opening.roofs
	local gy = Config.City.ground.y
	local skip = {}
	for sid, st in Config.SideQuests.sites do
		if not st.square then
			local sb = SideQuestSites.building(Config, world, sid)
			if sb and sb ~= keep then
				skip[math.floor(sb.x) .. "," .. math.floor(sb.z)] = true
			end
		end
	end
	local row = world.downtown and world.downtown.row or {}
	local out = {}
	for _, b in world.buildings do
		local h = b.top - gy
		if b.district == district and not b.crown and h >= R.minH and h <= R.maxH then
			local onRow = false
			for _, r in row do
				if math.abs(r.x - b.x) < 1 and math.abs(r.z - b.z) < 1 then
					onRow = true
				end
			end
			if not onRow and not skip[math.floor(b.x) .. "," .. math.floor(b.z)] then
				table.insert(out, b)
			end
		end
	end
	table.sort(out, function(p, q)
		return p.id < q.id
	end)
	return out
end

-- A course's roofs in running order (world building records: x, z, sx, sz, top, id), or nil
function SideQuestSites.course(Config: any, world: any, id: string): { any }?
	local C = Config.SideQuests.courses
	local cs = C and C[id]
	local st = cs and Config.SideQuests.sites[cs.from]
	if not cs or not st or not world or not world.buildings then
		return nil
	end
	local sx, sz = SideQuestSites.spot(Config, world, cs.from)
	if not sx or not sz then
		return nil
	end
	local tx, tz
	if type(cs.toward) == "string" then
		tx, tz = SideQuestSites.spot(Config, world, cs.toward)
	elseif type(cs.toward) == "table" then
		tx, tz = sx + cs.toward[1], sz + cs.toward[2]
	end
	if not tx or not tz then
		return nil
	end
	local fx, fz, gx, gz = sx :: number, sz :: number, tx :: number, tz :: number
	local keep = if st.square then nil else SideQuestSites.building(Config, world, cs.from)
	local district = if st.square then "Downtown" else st.district
	local pool = roofPool(Config, world, district, keep)
	-- `avoid`: other courses whose roofs this one leaves alone (so two runs from one site differ)
	if type(cs.avoid) == "table" then
		local taken = {}
		for _, other in cs.avoid do
			for _, b in (other ~= id and SideQuestSites.course(Config, world, other)) or {} do
				taken[b] = true
			end
		end
		local kept = {}
		for _, b in pool do
			if not taken[b] then
				table.insert(kept, b)
			end
		end
		pool = kept
	end
	-- the start: the site's own roof (the crew goes up through the bank), else the roofs nearest the spot
	local starts = {}
	for _, b in pool do
		local own = keep ~= nil and math.abs(b.x - keep.x) < 1 and math.abs(b.z - keep.z) < 1
		local d = flat(b.x, b.z, fx, fz)
		if own or d <= C.startNear then
			table.insert(starts, { b = b, d = if own then -1 else d })
		end
	end
	table.sort(starts, function(p, q)
		if p.d ~= q.d then
			return p.d < q.d
		end
		return p.b.id < q.b.id
	end)
	local budget = 20000 -- hop tries: a course takes far fewer, so a dead end never stalls a server
	for _, s in starts do
		local path = { s.b }
		local used = { [s.b] = true }
		local function grow(): boolean
			if #path >= cs.count then
				return true
			end
			local cur = path[#path]
			local options = {}
			for _, b in pool do
				if not used[b] and SideQuestSites.hopOk(Config, cur, b) then
					table.insert(options, b)
				end
			end
			-- head for the finish: the nearest to it first (ties by id, so every server builds the same course)
			table.sort(options, function(p, q)
				local dp, dq = flat(p.x, p.z, gx, gz), flat(q.x, q.z, gx, gz)
				if dp ~= dq then
					return dp < dq
				end
				return p.id < q.id
			end)
			for _, b in options do
				budget -= 1
				if budget <= 0 then
					return false
				end
				table.insert(path, b)
				used[b] = true
				if grow() then
					return true
				end
				table.remove(path)
				used[b] = nil
			end
			return false
		end
		if grow() then
			return path
		end
	end
	return nil
end

-- A course's length in studs, roof centre to roof centre
function SideQuestSites.length(path: { any }): number
	local n = 0
	for i = 2, #path do
		n += flat(path[i].x, path[i].z, path[i - 1].x, path[i - 1].z)
	end
	return n
end

---------------------------------------------------------------------------
-- Farmland sites (lore step 11, chain 4: The Harvest King)
---------------------------------------------------------------------------

SideQuestSites.FARM_KINDS = { barn = true, silo = true, field = true }

local lotCache: { [any]: { [number]: { any } } } = setmetatable({}, { __mode = "k" }) :: any
local farmCache: { [any]: { [any]: any } } = setmetatable({}, { __mode = "k" }) :: any

-- Is tile (tx, tz) one of this week's Farmland tiles (not a hand-placed safehouse or windmill tile)?
local function farmTile(Config: any, world: any, tx: number, tz: number): any?
	local W = Config.World
	if not world or not world.tiles or tx < 0 or tz < 0 or tx >= W.tiles or tz >= W.tiles then
		return nil
	end
	local t = WorldGen.get(W, world.tiles, tx, tz)
	if t.zone ~= W.zones.farmland or t.variant == W.special then
		return nil
	end
	return t
end

-- The farm lots on one Farmland tile, read from the tile's own plan for this week's seed (the very boxes
-- CityBuilder stands up): barns (a red clapboard barn's body; its door is on the +z front, BoxKit.house), silo
-- pairs (one lot between the two silos) and crop fields, each { kind, x, z, sx, sz, top, tx, tz }.
function SideQuestSites.tileLots(Config: any, world: any, tx: number, tz: number): { any }
	local byWorld = lotCache[world]
	if not byWorld then
		byWorld = {}
		lotCache[world] = byWorld
	end
	local key = tz * Config.World.tiles + tx
	local hit = byWorld[key]
	if hit then
		return hit
	end
	local out = {}
	if farmTile(Config, world, tx, tz) then
		local W = Config.World
		local clear = {}
		for _, sh in world.safehouses or {} do
			table.insert(clear, { x = sh.x, z = sh.z, r = W.safehouse.pad * 0.75 })
		end
		local boxes = WorldGen.tilePlan(Config.City, W, world.tiles, world.seed, tx, tz, clear)
		local silos = {}
		for _, b in boxes do
			local top = b.cy + b.sy / 2
			if b.kind == "building" and b.color == "roofRed" and b.shape == nil then
				table.insert(
					out,
					{ kind = "barn", x = b.cx, z = b.cz, sx = b.sx, sz = b.sz, top = top, tx = tx, tz = tz }
				)
			elseif b.kind == "prop" and b.color == "steel" and b.shape == "cylinder" and b.sx >= 10 then
				table.insert(silos, b)
			elseif b.kind == "field" and b.color == "soil" then
				table.insert(
					out,
					{ kind = "field", x = b.cx, z = b.cz, sx = b.sx, sz = b.sz, top = top, tx = tx, tz = tz }
				)
			end
		end
		-- a silo lot stands two silos side by side on one line: one site between them
		local used = {}
		for i, a in silos do
			if not used[i] then
				for j = i + 1, #silos do
					local b = silos[j]
					if not used[j] and math.abs(a.cz - b.cz) < 1 and math.abs(a.cx - b.cx) <= 16 then
						used[i], used[j] = true, true
						table.insert(out, {
							kind = "silo",
							x = (a.cx + b.cx) / 2,
							z = a.cz,
							sx = math.abs(a.cx - b.cx) + a.sx,
							sz = a.sz,
							top = math.max(a.cy + a.sy / 2, b.cy + b.sy / 2),
							tx = tx,
							tz = tz,
						})
						break
					end
				end
			end
		end
	end
	byWorld[key] = out
	return out
end

-- The middle of a landmark (Config.World.landmarks: its corner tile and size in tiles)
function SideQuestSites.landmarkMid(Config: any, lm: any): (number, number)
	local x0, z0 = WorldGen.tileOrigin(Config.City, lm.tx, lm.tz)
	local half = lm.size * Config.City.tile / 2
	return x0 + half, z0 + half
end

-- Is a farm spot clear of the city's safehouses, beacons and landmarks (the site's `away`)?
local function clearOf(Config: any, world: any, st: any, x: number, z: number): boolean
	local a = st.away or {}
	for _, sh in world.safehouses or {} do
		if flat(x, z, sh.x, sh.z) < (a.safehouse or 0) then
			return false
		end
	end
	for _, b in world.beacons or {} do
		if flat(x, z, b.x, b.z) < (a.beacon or 0) then
			return false
		end
	end
	for _, lm in Config.World.landmarks do
		local lx, lz = SideQuestSites.landmarkMid(Config, lm)
		if flat(x, z, lx, lz) < (a.landmark or 0) then
			return false
		end
	end
	return true
end

-- A spot on a farm road: the middle line of a Farmland tile's road (a N-S road runs down the tile's middle in
-- x, an E-W road in z), the point on it nearest (x, z) between r0 and r1 studs: { x, z, axis }, or nil
local function roadNear(Config: any, world: any, st: any, x: number, z: number, r0: number, r1: number): any?
	local C = Config.City
	local cx, cz = WorldGen.tileOf(C, x, z)
	local span = math.ceil(r1 / C.tile) + 1
	local best, bestD = nil, math.huge
	for tz = cz - span, cz + span do
		for tx = cx - span, cx + span do
			local t = farmTile(Config, world, tx, tz)
			if t then
				local x0, z0 = WorldGen.tileOrigin(C, tx, tz)
				local cands = {}
				if t.roadNS then
					table.insert(
						cands,
						{ x = x0 + C.tile / 2, z = math.clamp(z, z0, z0 + C.tile), axis = "ns" }
					)
				end
				if t.roadEW then
					table.insert(
						cands,
						{ x = math.clamp(x, x0, x0 + C.tile), z = z0 + C.tile / 2, axis = "ew" }
					)
				end
				for _, c in cands do
					local d = flat(x, z, c.x, c.z)
					if d >= r0 and d <= r1 and d < bestD and clearOf(Config, world, st, c.x, c.z) then
						best, bestD = c, d
					end
				end
			end
		end
	end
	return best
end

-- A Farmland site (Config.SideQuests.sites with `farm` or `road`), or nil when none fits this week's tiles.
-- `near`: the lot nearest that point (studs from the map's middle) within `reach`; `from`: the lot nearest that
-- site's way in, inside `range`; never within away.site of a site in `apart`. The way in (door): a barn's
-- front door (+z), a silo pair's front, a field's middle or the road spot, facing +z.
function SideQuestSites.farm(Config: any, world: any, id: string, depth: number?): any?
	local st = Config.SideQuests.sites[id]
	if not st or not (st.farm or st.road) or not world or not world.tiles then
		return nil
	end
	local byWorld = farmCache[world]
	if not byWorld then
		byWorld = {}
		farmCache[world] = byWorld
	end
	local hit = byWorld[st]
	if hit ~= nil then
		return if hit then hit else nil
	end
	local level = depth or 0
	if level > 4 then
		return nil -- a loop of `from` links (the validator reports it)
	end
	local ox, oz, r0, r1
	if st.from then
		local parent = SideQuestSites.farm(Config, world, st.from, level + 1)
		if not parent or type(st.range) ~= "table" then
			byWorld[st] = false
			return nil
		end
		ox, oz = parent.door.x, parent.door.z
		r0, r1 = st.range[1], st.range[2]
	elseif type(st.near) == "table" then
		ox, oz = st.near[1], st.near[2]
		r0, r1 = 0, st.reach or 600
	else
		return nil
	end
	local others = {}
	for _, other in st.apart or {} do
		local o = other ~= id and SideQuestSites.farm(Config, world, other, level + 1)
		if o then
			table.insert(others, o)
		end
	end
	local gap = (st.away and st.away.site) or 0
	local function apartOk(x: number, z: number): boolean
		for _, o in others do
			if flat(x, z, o.x, o.z) < gap then
				return false
			end
		end
		return true
	end
	local found = nil
	if st.road then
		local r = roadNear(Config, world, st, ox, oz, r0, r1)
		if r and apartOk(r.x, r.z) then
			local w = Config.World.roads.localWidth
			local tx, tz = WorldGen.tileOf(Config.City, r.x, r.z)
			found = {
				kind = "road",
				x = r.x,
				z = r.z,
				sx = w,
				sz = w,
				top = Config.City.ground.y,
				tx = tx,
				tz = tz,
				axis = r.axis,
				door = { x = r.x, z = r.z, fx = 0, fz = 1 },
			}
		end
	else
		local C = Config.City
		local cx, cz = WorldGen.tileOf(C, ox, oz)
		local span = math.ceil(r1 / C.tile) + 1
		local bestD = math.huge
		local lot = nil
		for tz = cz - span, cz + span do
			for tx = cx - span, cx + span do
				for _, l in SideQuestSites.tileLots(Config, world, tx, tz) do
					if l.kind == st.farm then
						local d = flat(l.x, l.z, ox, oz)
						if
							d >= r0
							and d <= r1
							and d < bestD
							and clearOf(Config, world, st, l.x, l.z)
							and apartOk(l.x, l.z)
						then
							bestD, lot = d, l
						end
					end
				end
			end
		end
		if lot then
			local front = if lot.kind == "field" then 0 else lot.sz / 2 + 6
			found = table.clone(lot)
			found.door = { x = lot.x, z = lot.z + front, fx = 0, fz = 1 }
		end
	end
	byWorld[st] = found or false
	return found
end

-- An escort's way down a farm road toward town (lore step 11, chain 4): from the road spot nearest (x, z),
-- along that road toward the map's middle in `legs` even legs, `length` studs in all, stopping where the road
-- ends (a tile with no road that way, the hub, a landmark or a hand-placed tile): { { x, y, z } }, or nil when
-- no farm road is within 300 studs or fewer than two points fit.
function SideQuestSites.roadPath(
	Config: any,
	world: any,
	x: number,
	z: number,
	length: number,
	legs: number
): { { number } }?
	local C, W = Config.City, Config.World
	local spot = roadNear(Config, world, {}, x, z, 0, 300)
	if not spot then
		return nil
	end
	local ns = spot.axis == "ns"
	local dir = if ns then (if spot.z > 0 then -1 else 1) else (if spot.x > 0 then -1 else 1)
	local y = C.ground.y + 0.5
	local path = {}
	local step = length / math.max(1, legs)
	for i = 0, legs do
		local px = if ns then spot.x else spot.x + dir * step * i
		local pz = if ns then spot.z + dir * step * i else spot.z
		local tx, tz = WorldGen.tileOf(C, px, pz)
		if tx < 0 or tz < 0 or tx >= W.tiles or tz >= W.tiles then
			break
		end
		local t = WorldGen.get(W, world.tiles, tx, tz)
		local outskirts = (t.zone == W.zones.farmland or t.zone == W.zones.suburbs) and t.variant ~= W.special
		if not outskirts or not (if ns then t.roadNS else t.roadEW) then
			break
		end
		table.insert(path, { px, y, pz })
	end
	if #path < 2 then
		return nil
	end
	return path
end

return SideQuestSites
