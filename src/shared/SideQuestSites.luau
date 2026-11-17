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

local HqRules = if script then require(script.Parent.HqRules) else (require :: any)("./HqRules")

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
	if not st or st.square then
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

-- A site's building (or open square) and its way in, or nil. A square's way in is its `spot` (studs from the
-- square's middle), facing out of the square's nearer side.
function SideQuestSites.place(Config: any, world: any, id: string): (any?, Door?)
	local st = Config.SideQuests.sites[id]
	if not st then
		return nil, nil
	end
	if st.square then
		local o = SideQuestSites.square(Config, world, id)
		if not o then
			return nil, nil
		end
		local s = st.spot or { 0, 0 }
		return o, { x = o.x + s[1], z = o.z + s[2], fx = 0, fz = if s[2] < 0 then -1 else 1 }
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

return SideQuestSites
