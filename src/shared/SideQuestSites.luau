--!strict
-- SideQuestSites: where side quest chains happen inside the city's existing buildings (nate's lore, build plan
-- step 11). Pure, so Lune checks the pick for the seeded layout; SideQuestService stands the giver at the door,
-- puts up the sign and marks the map.
-- * building(Config, world, id): the Downtown building for Config.SideQuests.sites[id]: of the buildings that
--   fit (a height in range, no skyscraper crown, `away` studs from the Beacon Tower's plaza, every roof of the
--   prologue's chase row, the Vigil's stairwell and the open squares), the one nearest `near` (studs from the
--   Beacon Tower). nate (2026-11-17): the Hero Academy is an existing building, not an open square.
-- * door(world, b): the face of that building that opens on a street (a point 10 studs out is in no
--   building), nearest the plaza: { x, z, fx, fz } (fx, fz: the way out).
-- * outskirts(Config, world, id): a site out in the seeded Suburbs (a site with `lot`, the Suburbs chain's toy
--   shop): of the lots of that kind on Suburbs tiles `rings` out from the hub edge, built with their building
--   (a lot under a safehouse pad stays empty) and a height in range, the one nearest `near` (map studs) that
--   keeps `away` studs from every safehouse, beacon, landmark centre, city district and every other chain site
--   (Downtown ones, and outskirts ones earlier by id). The outskirts change weekly with the seed, so the shop
--   does too; the same seed always picks the same shop. Its door is the front (outskirts buildings face +z).

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
	local L = world.downtown
	local bt = L.beacon
	local a = st.away
	if b.crown or b.h < st.height[1] or b.h > st.height[2] then
		return false
	end
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

-- The building a site is in, or nil (no Downtown, or nothing fits)
function SideQuestSites.building(Config: any, world: any, id: string): any?
	local st = Config.SideQuests.sites[id]
	local L = world and world.downtown
	if not st or SideQuestSites.isOutskirts(st) or not L or not L.beacon then
		return nil
	end
	local tx, tz = L.beacon.x + st.near[1], L.beacon.z + st.near[2]
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

-- The way in: the street-side face nearest the plaza
function SideQuestSites.door(world: any, b: any): Door
	local bt = world.downtown.beacon
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
		local d = flat(x, z, bt.x, bt.z)
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

-- Is this site out in the outskirts (picked from a Suburbs lot) rather than in a Downtown building?
function SideQuestSites.isOutskirts(st: any): boolean
	return type(st) == "table" and st.lot ~= nil
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
				b = SideQuestSites.building(Config, world, other)
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
	if b.h < st.height[1] or b.h > st.height[2] then
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
	-- the way in is open ground (not a fence, a tree or the next lot's house)
	local door = SideQuestSites.frontDoor(b)
	if world.heights and WorldMap.heightAt(world, door.x, door.z) > gy + 1.5 then
		return false
	end
	return true
end

-- The outskirts building a site is in, or nil: { x, z, sx, sz, h, top, tx, tz, lot }
function SideQuestSites.outskirts(Config: any, world: any, id: string): any?
	local st = Config.SideQuests.sites[id]
	if not SideQuestSites.isOutskirts(st) or not world or not world.tiles or not world.tilePlans then
		return nil
	end
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

-- A site's building and door, or nil (a Downtown building, or an outskirts lot's)
function SideQuestSites.place(Config: any, world: any, id: string): (any?, Door?)
	local st = Config.SideQuests.sites[id]
	if SideQuestSites.isOutskirts(st) then
		local b = SideQuestSites.outskirts(Config, world, id)
		if not b then
			return nil, nil
		end
		return b, SideQuestSites.frontDoor(b)
	end
	local b = SideQuestSites.building(Config, world, id)
	if not b then
		return nil, nil
	end
	return b, SideQuestSites.door(world, b)
end

return SideQuestSites
