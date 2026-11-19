--!strict
-- LorePlan: the lore pages (side-content, 2026-11-19; Config.Lore). Pure, so LoreService, LoreClient, the Journal
-- and the Lune tests agree:
-- * the pages and their save bits (profile.lore: 2 words, bit = the page's `bit` - 1);
-- * where each page lies for a world (spots): near its anchor (a side quest site's door, a beacon, a landmark's
--   middle, Uptown's tower), on the first flat spot of the anchor's own height in rings out from it, checked on
--   the world's height map so a page never sits inside a building, in the air or under the street; a deep site's
--   page lies on the seabed in front of it;
-- * progress per district, finished sets, the rewards a new page pays and the titles a profile holds.

local Bits = if script
	then require(script.Parent.ProfileSchema).Bits
	else (require :: any)("./ProfileSchema").Bits
local WorldMap = if script then require(script.Parent.WorldMap) else (require :: any)("./WorldMap")
local DeepLayout = if script then require(script.Parent.DeepLayout) else (require :: any)("./DeepLayout")
local SideQuestSites = if script
	then require(script.Parent.SideQuestSites)
	else (require :: any)("./SideQuestSites")

local LorePlan = {}

export type Spot = { bit: number, id: string, x: number, y: number, z: number }

function LorePlan.page(L: any, bit: number): any?
	for _, p in L.pages do
		if p.bit == bit then
			return p
		end
	end
	return nil
end

function LorePlan.byId(L: any, id: string): any?
	for _, p in L.pages do
		if p.id == id then
			return p
		end
	end
	return nil
end

function LorePlan.has(words: { number }, bit: number): boolean
	return Bits.get(words, bit - 1)
end

function LorePlan.mark(words: { number }, bit: number)
	Bits.set(words, bit - 1, true)
end

-- The pages of a district (in Config order)
function LorePlan.inDistrict(L: any, district: string): { any }
	local out = {}
	for _, p in L.pages do
		if p.district == district then
			table.insert(out, p)
		end
	end
	return out
end

-- { district id, name, title, have, total, done } for every district, in the Journal's order
function LorePlan.progress(L: any, words: { number }): { any }
	local out = {}
	for _, d in L.districts do
		local have, total = 0, 0
		for _, p in LorePlan.inDistrict(L, d.id) do
			total += 1
			if LorePlan.has(words, p.bit) then
				have += 1
			end
		end
		table.insert(out, {
			id = d.id,
			name = d.name,
			title = d.title,
			have = have,
			total = total,
			done = total > 0 and have >= total,
		})
	end
	return out
end

function LorePlan.count(L: any, words: { number }): (number, number)
	local have = 0
	for _, p in L.pages do
		if LorePlan.has(words, p.bit) then
			have += 1
		end
	end
	return have, #L.pages
end

-- A district's index in L.districts (its title id is titleBase + index)
function LorePlan.districtIndex(L: any, district: string): number?
	for i, d in L.districts do
		if d.id == district then
			return i
		end
	end
	return nil
end

-- What reading page `bit` pays on a save that has `words` (before it is marked): { renown, district (set done),
-- all (every page done), titles = { ids } }; nil when the page is unknown or already read
function LorePlan.reward(L: any, words: { number }, bit: number): any?
	local page = LorePlan.page(L, bit)
	if not page or LorePlan.has(words, bit) then
		return nil
	end
	local after = table.clone(words)
	LorePlan.mark(after, bit)
	local r = { renown = L.renown.page, titles = {}, district = nil :: string?, all = false }
	local left = 0
	for _, p in LorePlan.inDistrict(L, page.district) do
		if not LorePlan.has(after, p.bit) then
			left += 1
		end
	end
	if left == 0 then
		r.district = page.district
		r.renown += L.renown.set
		table.insert(r.titles, L.titleBase + (LorePlan.districtIndex(L, page.district) or 0))
	end
	local have, total = LorePlan.count(L, after)
	if have >= total then
		r.all = true
		r.renown += L.renown.all
		table.insert(r.titles, L.allTitle)
	end
	return r
end

-- The lore titles a save holds: { id, name } (a district's set done, every page done)
function LorePlan.titles(L: any, words: { number }): { { id: number, name: string } }
	local out = {}
	for i, row in LorePlan.progress(L, words) do
		if row.done then
			table.insert(out, { id = L.titleBase + i, name = row.title })
		end
	end
	local have, total = LorePlan.count(L, words)
	if total > 0 and have >= total then
		table.insert(out, { id = L.allTitle, name = L.allName })
	end
	return out
end

---------------------------------------------------------------------------
-- Where the pages lie
---------------------------------------------------------------------------

-- The anchor of a page: x, z, the height a spot must match (nil: the ground at the anchor) and, for a deep
-- site, the seabed spot itself (deep = true)
local function anchor(Config: any, world: any, at: any): (number?, number?, number?, boolean)
	if at.site then
		local _, door = SideQuestSites.place(Config, world, at.site)
		if not door then
			return nil, nil, nil, false
		end
		local st = Config.SideQuests.sites[at.site]
		if st and SideQuestSites.isDeep(st) then
			return door.x + door.fx * 8, door.z + door.fz * 8, door.y, true
		end
		-- a little out from the door and to its side, so the page never sits on the giver or the sign
		return door.x + door.fx * 6 - door.fz * 8, door.z + door.fz * 6 + door.fx * 8, nil, false
	elseif at.beacon then
		local b = world.beacons[at.beacon]
		if not b then
			return nil, nil, nil, false
		end
		return b.x, b.z, b.y, false
	elseif at.uptown then
		local lm = world.uptown and world.uptown.landmark
		if not lm or (lm.size or 0) <= 0 then
			return nil, nil, nil, false
		end
		return lm.x, lm.z + lm.size / 2 + 20, nil, false
	elseif at.landmark == "plaza" then
		local bt = world.downtown and world.downtown.beacon
		if not bt then
			return nil, nil, nil, false
		end
		return bt.x + (at.dx or 0), bt.z + (at.dz or 0), nil, false
	elseif at.landmark then
		for _, lm in world.landmarks or {} do
			if lm.id == at.landmark then
				return lm.centre.x + (at.dx or 0), lm.centre.z + (at.dz or 0), nil, false
			end
		end
	end
	return nil, nil, nil, false
end
LorePlan.anchor = anchor

-- Is (x, z) flat open ground (or roof) at height `ref` (within band): the point and four round it read the same
local function flatAt(world: any, P: any, x: number, z: number, ref: number): number?
	local h = WorldMap.heightAt(world, x, z)
	if math.abs(h - ref) > P.band then
		return nil
	end
	for _, d in { { P.probe, 0 }, { -P.probe, 0 }, { 0, P.probe }, { 0, -P.probe } } do
		if math.abs(WorldMap.heightAt(world, x + d[1], z + d[2]) - h) > P.flat then
			return nil
		end
	end
	return h
end
LorePlan.flatAt = flatAt

-- Every page's spot in this world (pages whose anchor is missing are left out; the tests check none is)
function LorePlan.spots(Config: any, world: any): { Spot }
	local L = Config.Lore
	local P = L.place
	local out: { Spot } = {}
	for _, page in L.pages do
		local ax, az, ay, deep = anchor(Config, world, page.at)
		if ax and az then
			local x, z = ax :: number, az :: number
			if deep then
				local floor = DeepLayout.floorAt(Config, x, z, nil) or (ay :: number)
				table.insert(out, { bit = page.bit, id = page.id, x = x, y = floor + P.seabed, z = z })
			else
				local ref = ay or WorldMap.heightAt(world, x, z)
				local found: Spot? = nil
				local h = flatAt(world, P, x, z, ref)
				if h then
					found = { bit = page.bit, id = page.id, x = x, y = h + P.float, z = z }
				end
				local r = P.first
				while not found and r <= P.far do
					for k = 0, P.spokes - 1 do
						local a = k / P.spokes * math.pi * 2
						local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
						local ph = flatAt(world, P, px, pz, ref)
						if ph then
							found = { bit = page.bit, id = page.id, x = px, y = ph + P.float, z = pz }
							break
						end
					end
					r += P.ring
				end
				if found then
					table.insert(out, found)
				end
			end
		end
	end
	return out
end

-- The nearest page this save has not read, within `range` of (x, z), or nil
function LorePlan.nearestMissing(
	spots: { Spot },
	words: { number },
	x: number,
	z: number,
	range: number
): Spot?
	local best, bestD = nil, range * range
	for _, s in spots do
		local d = (s.x - x) ^ 2 + (s.z - z) ^ 2
		if d <= bestD and not LorePlan.has(words, s.bit) then
			best, bestD = s, d
		end
	end
	return best
end

-- Bad data in Config.Lore (the tests and the boot check read it): duplicate or out-of-range bits and ids,
-- unknown districts or sites, empty text, lines too long for the caption card
function LorePlan.validate(Config: any): { string }
	local L = Config.Lore
	local bad = {}
	local bits, ids, districts = {}, {}, {}
	for _, d in L.districts do
		districts[d.id] = true
	end
	for _, p in L.pages do
		local w = tostring(p.id)
		if type(p.bit) ~= "number" or p.bit < 1 or p.bit > L.bits or bits[p.bit] then
			table.insert(bad, w .. ": bit")
		end
		bits[p.bit] = true
		if ids[p.id] then
			table.insert(bad, w .. ": id repeats")
		end
		ids[p.id] = true
		if not districts[p.district] then
			table.insert(bad, w .. ": district " .. tostring(p.district))
		end
		if p.at.site and not Config.SideQuests.sites[p.at.site] then
			table.insert(bad, w .. ": site " .. tostring(p.at.site))
		end
		if p.at.beacon then
			local ok = false
			for _, b in Config.World.beacons do
				ok = ok or b.id == p.at.beacon
			end
			if not ok then
				table.insert(bad, w .. ": beacon")
			end
		end
		if type(p.title) ~= "string" or #p.title == 0 or #p.title > 32 then
			table.insert(bad, w .. ": title")
		end
		if type(p.lines) ~= "table" or #p.lines < 1 or #p.lines > 3 then
			table.insert(bad, w .. ": lines")
		end
		for _, line in p.lines or {} do
			if type(line) ~= "string" or #line < 8 or #line > 96 or string.find(line, "%%") then
				table.insert(bad, w .. ": line " .. tostring(line))
			end
		end
		if type(p.by) ~= "string" or #p.by == 0 or #p.by > 32 then
			table.insert(bad, w .. ": by")
		end
	end
	for _, d in L.districts do
		if #LorePlan.inDistrict(L, d.id) == 0 then
			table.insert(bad, d.id .. ": no pages")
		end
	end
	return bad
end

return LorePlan
