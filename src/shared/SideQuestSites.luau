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

local HqRules = if script then require(script.Parent.HqRules) else (require :: any)("./HqRules")

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
	if not st or not L or not L.beacon then
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

-- A site's door, or nil
function SideQuestSites.place(Config: any, world: any, id: string): (any?, Door?)
	local b = SideQuestSites.building(Config, world, id)
	if not b then
		return nil, nil
	end
	return b, SideQuestSites.door(world, b)
end

return SideQuestSites
