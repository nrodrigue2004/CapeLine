--!strict
-- CollectPlan: collections (spec: Hero MMO features > Collections; H7). Pure, so CollectService, the client
-- and the Lune tests agree:
-- * the sets and their save bits (Config.Collect: each set's `at` + its place - 1, in 128 bits);
-- * where every find sits for a world (spots): the hidden sets from the city's own layout with a fixed seed
--   (on open street in their district, on a tall roof, or on the seabed), the weekly Star Charms from the
--   week's world seed in the outskirts; every spot is checked against the height map so it never sits inside
--   a building or under the water it should not be in;
-- * the item a drop or an earned moment gives (robot parts, boss plates, nemesis cores, ribbons, keepsakes,
--   task force patches), finished sets, and the HQ Scanner's nearest missing find.

local Bits = if script
	then require(script.Parent.ProfileSchema).Bits
	else (require :: any)("./ProfileSchema").Bits
local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local WorldMap = if script then require(script.Parent.WorldMap) else (require :: any)("./WorldMap")
local ZoneLevel = if script then require(script.Parent.ZoneLevel) else (require :: any)("./ZoneLevel")
local DeepLayout = if script then require(script.Parent.DeepLayout) else (require :: any)("./DeepLayout")

local CollectPlan = {}

export type Spot = { set: string, item: number, bit: number, x: number, y: number, z: number }

function CollectPlan.set(C: any, id: string): any?
	for _, s in C.sets do
		if s.id == id then
			return s
		end
	end
	return nil
end

function CollectPlan.setOfBit(C: any, bit: number): (any?, number)
	for _, s in C.sets do
		if bit >= s.at and bit < s.at + s.count then
			return s, bit - s.at + 1
		end
	end
	return nil, 0
end

function CollectPlan.bit(set: any, item: number): number
	return set.at + item - 1
end

function CollectPlan.found(words: { number }, set: any): number
	local n = 0
	for i = 1, set.count do
		if Bits.get(words, set.at + i - 1) then
			n += 1
		end
	end
	return n
end

function CollectPlan.done(words: { number }, set: any): boolean
	return CollectPlan.found(words, set) >= set.count
end

function CollectPlan.fullSets(C: any, words: { number }): number
	local n = 0
	for _, s in C.sets do
		if CollectPlan.done(words, s) then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Items from drops and earned moments (nil when there is none to give)
---------------------------------------------------------------------------

-- A robot kind's part
function CollectPlan.robotPart(C: any, kind: string): number?
	local s = CollectPlan.set(C, "RobotParts")
	local i = s and table.find(s.items, kind)
	return if s and i then CollectPlan.bit(s, i) else nil
end

-- A plate of this boss you are missing (each boss has two)
function CollectPlan.bossPlate(C: any, words: { number }, boss: string): number?
	local s = CollectPlan.set(C, "BossPlates")
	local i = s and table.find(s.bosses, boss)
	if not s or not i then
		return nil
	end
	for k = 1, 2 do
		local bit = CollectPlan.bit(s, (i - 1) * 2 + k)
		if not Bits.get(words, bit) then
			return bit
		end
	end
	return nil
end

function CollectPlan.nemesisCore(C: any, rank: number): number?
	local s = CollectPlan.set(C, "NemesisCores")
	return if s and rank >= 1 and rank <= s.count then CollectPlan.bit(s, rank) else nil
end

function CollectPlan.ribbon(C: any, name: string): number?
	local s = CollectPlan.set(C, "ContestRibbons")
	local i = C.ribbons[name]
	return if s and i then CollectPlan.bit(s, i) else nil
end

-- A mentor's keepsake: parts 2 and 4 of their quest line (mentor = index in Config.Mentors.list)
function CollectPlan.keepsake(C: any, mentor: number, part: number): number?
	local s = CollectPlan.set(C, "MentorKeepsakes")
	if not s or (part ~= 2 and part ~= 4) then
		return nil
	end
	local i = (mentor - 1) * 2 + (if part == 4 then 2 else 1)
	return if i >= 1 and i <= s.count then CollectPlan.bit(s, i) else nil
end

-- A task force patch: kind "clear", "speed" or "full"
function CollectPlan.patch(C: any, tf: number, kind: string): number?
	local s = CollectPlan.set(C, "TaskForcePatches")
	local k = if kind == "clear" then 1 elseif kind == "speed" then 2 elseif kind == "full" then 3 else nil
	if not s or not k then
		return nil
	end
	local i = (tf - 1) * 3 + k
	return if i >= 1 and i <= s.count then CollectPlan.bit(s, i) else nil
end

---------------------------------------------------------------------------
-- Where the finds sit
---------------------------------------------------------------------------

local function far(list: { Spot }, x: number, z: number, gap: number): boolean
	for _, s in list do
		if (s.x - x) ^ 2 + (s.z - z) ^ 2 < gap * gap then
			return false
		end
	end
	return true
end

-- Open street: this spot and four around it are at ground height, on dry land, out of the harbour water
function CollectPlan.isStreet(Config: any, world: any, x: number, z: number): boolean
	local gy = Config.City.ground.y
	for _, d in { { 0, 0 }, { 4, 0 }, { -4, 0 }, { 0, 4 }, { 0, -4 } } do
		local h = WorldMap.heightAt(world, x + d[1], z + d[2])
		if math.abs(h - gy) > 2 then
			return false
		end
	end
	return DeepLayout.area(Config, x, z) == nil
end

local function streetSpots(Config: any, world: any, set: any, rng: any): { Spot }
	local C = Config.Collect
	local r = Config.City.districts[set.area]
	local out: { Spot } = {}
	if not r then
		return out
	end
	for _ = 1, 4000 do
		if #out >= set.count then
			break
		end
		local x = rng:range(r.minX + 16, r.maxX - 16)
		local z = rng:range(r.minZ + 16, r.maxZ - 16)
		if CollectPlan.isStreet(Config, world, x, z) and far(out, x, z, C.minGap) then
			local i = #out + 1
			table.insert(out, {
				set = set.id,
				item = i,
				bit = CollectPlan.bit(set, i),
				x = x,
				y = WorldMap.heightAt(world, x, z) + 2.5,
				z = z,
			})
		end
	end
	return out
end

-- Tall flat roofs in the hub (Downtown and Uptown), never a skyscraper's crown
local function roofSpots(Config: any, world: any, set: any, rng: any): { Spot }
	local C = Config.Collect
	local gy = Config.City.ground.y
	local cands = {}
	for _, b in world.buildings do
		local d = b.district
		if (d == "Downtown" or d == "Uptown") and b.crown == nil and b.top - gy >= set.minHeight then
			-- the roof's centre must read the roof's own height (no prop or neighbour above it)
			local h = WorldMap.heightAt(world, b.x, b.z)
			if math.abs(h - b.top) <= 8 then
				table.insert(cands, { x = b.x, z = b.z, y = h })
			end
		end
	end
	table.sort(cands, function(a, c)
		return if a.x == c.x then a.z < c.z else a.x < c.x
	end)
	rng:shuffle(cands)
	local out: { Spot } = {}
	for _, c in cands do
		if #out >= set.count then
			break
		end
		if far(out, c.x, c.z, C.minGap) then
			local i = #out + 1
			table.insert(
				out,
				{ set = set.id, item = i, bit = CollectPlan.bit(set, i), x = c.x, y = c.y + 2.5, z = c.z }
			)
		end
	end
	return out
end

-- The seabed of the sea ring and the Coral Shelf (the Trench and the Line have their own caches)
local function seabedSpots(Config: any, set: any, rng: any): { Spot }
	local C = Config.Collect
	local half = Config.City.mapSize / 2
	local w = Config.Deep.ring.width
	local out: { Spot } = {}
	for _ = 1, 4000 do
		if #out >= set.count then
			break
		end
		local side = rng:int(1, 4)
		local along = rng:range(-half - w * 0.5, half + w * 0.5)
		local out0 = half + rng:range(w * 0.15, w * 0.85)
		local x, z
		if side == 1 then
			x, z = along, out0
		elseif side == 2 then
			x, z = along, -out0
		elseif side == 3 then
			x, z = out0, along
		else
			x, z = -out0, along
		end
		local area = DeepLayout.area(Config, x, z)
		local floor = (area == "sea" or area == "shelf") and DeepLayout.floorAt(Config, x, z)
		if floor and far(out, x, z, C.minGap * 4) then
			local i = #out + 1
			table.insert(
				out,
				{ set = set.id, item = i, bit = CollectPlan.bit(set, i), x = x, y = floor + 2.5, z = z }
			)
		end
	end
	return out
end

-- The outskirts (suburbs, farmland, coast) on dry ground, from the week's seed
local function outskirtsSpots(Config: any, world: any, set: any, rng: any): { Spot }
	local C = Config.Collect
	local half = Config.City.mapSize / 2 - 40
	local gy = Config.City.ground.y
	local ok = { suburbs = true, farmland = true, coast = true }
	local out: { Spot } = {}
	for _ = 1, 4000 do
		if #out >= set.count then
			break
		end
		local x, z = rng:range(-half, half), rng:range(-half, half)
		local area = ZoneLevel.area(Config, x, z, world.tiles)
		if ok[area] and CollectPlan.isStreet(Config, world, x, z) and far(out, x, z, C.minGap * 10) then
			local i = #out + 1
			table.insert(
				out,
				{ set = set.id, item = i, bit = CollectPlan.bit(set, i), x = x, y = gy + 2.5, z = z }
			)
		end
	end
	return out
end

-- Every find spot for this world (hidden sets with Config.Collect.seed, the weekly set with world.seed)
function CollectPlan.spots(Config: any, world: any): { Spot }
	local C = Config.Collect
	local out: { Spot } = {}
	for k, set in C.sets do
		local list: { Spot } = {}
		if set.kind == "hidden" then
			local rng = Rng.new(Rng.hash(C.seed, k))
			if set.place == "street" then
				list = streetSpots(Config, world, set, rng)
			elseif set.place == "roof" then
				list = roofSpots(Config, world, set, rng)
			elseif set.place == "seabed" then
				list = seabedSpots(Config, set, rng)
			end
		elseif set.kind == "weekly" then
			list = outskirtsSpots(Config, world, set, Rng.new(Rng.hash(world.seed, C.seed, k)))
		end
		for _, s in list do
			table.insert(out, s)
		end
	end
	return out
end

-- The HQ Scanner: the nearest find you are missing (within `range` studs, nil = anywhere)
function CollectPlan.nearest(spots: { Spot }, words: { number }, x: number, z: number, range: number?): Spot?
	local best, bestD = nil, (range or math.huge) ^ 2
	for _, s in spots do
		if not Bits.get(words, s.bit) then
			local d = (s.x - x) ^ 2 + (s.z - z) ^ 2
			if d < bestD then
				best, bestD = s, d
			end
		end
	end
	return best
end

return CollectPlan
