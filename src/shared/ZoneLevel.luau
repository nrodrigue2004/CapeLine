--!strict
-- ZoneLevel: the level an incident, contract or event runs at (spec: "L = zone level"; Decisions M6). The
-- area under a point gives a floor (hub 1, suburbs 5, farmland 12, coast 20, the landmarks their own); the
-- zone level is the hero's level raised to that floor, capped at the level cap (Config.Stats.levelCap, 50),
-- so heroes from 41 to 50 meet their own level everywhere. Rewards follow the zone level, not the hero who
-- joins in, so a level 50 helping at a level 5 incident earns level 5 rewards.

local WorldGen = if script then require(script.Parent.WorldGen) else (require :: any)("./WorldGen")

local ZoneLevel = {}

-- The area name at (x, z): a landmark id, "hub", "suburbs", "farmland" or "coast". tiles (optional) is
-- the world's tile array; without it the ring rules decide.
function ZoneLevel.area(Config: any, x: number, z: number, tiles: buffer?): string
	local w = Config.World
	local tx, tz = WorldGen.tileOf(Config.City, x, z)
	tx = math.clamp(tx, 0, w.tiles - 1)
	tz = math.clamp(tz, 0, w.tiles - 1)
	local lm = WorldGen.landmarkAt(w, tx, tz)
	if lm then
		return w.landmarks[lm].id
	end
	if tiles then
		local zone = WorldGen.get(w, tiles, tx, tz).zone
		for name, num in w.zones do
			if num == zone and name ~= "landmark" then
				return if name == "hubFill" then "hub" else name
			end
		end
	end
	local ring = WorldGen.ring(w, tx, tz)
	if ring == 0 then
		return "hub"
	elseif ring <= w.rings.suburbsTo then
		return "suburbs"
	elseif ring <= w.rings.farmlandTo then
		return "farmland"
	end
	return "coast"
end

function ZoneLevel.floor(Config: any, area: string): number
	return Config.World.zoneFloor[area] or 1
end

-- The zone level for a hero of heroLevel at (x, z)
function ZoneLevel.at(Config: any, x: number, z: number, heroLevel: number, tiles: buffer?): number
	local floor = ZoneLevel.floor(Config, ZoneLevel.area(Config, x, z, tiles))
	return math.clamp(math.max(math.floor(heroLevel), floor), 1, Config.Stats.levelCap)
end

-- The median of a list of levels (events and the boss use the server's median), 1 when empty
function ZoneLevel.median(levels: { number }): number
	if #levels == 0 then
		return 1
	end
	local list = table.clone(levels)
	table.sort(list)
	local mid = (#list + 1) / 2
	return math.floor((list[math.floor(mid)] + list[math.ceil(mid)]) / 2 + 0.5)
end

return ZoneLevel
