--!strict
-- EnemyVariety: mixes the nine new robot types into open-world squads (nate, 2026-11-17: "Dont want enemies
-- to get repetitive"). A squad is a list of { kind, n } rows (incidents, contracts, events, side quests;
-- SiteKit.squad). Each robot in it may be swapped for a new type from Config.Enemies.variety.swaps once the
-- fight's level reaches that type's `level`, at its `chance`, at most `max` of it per squad, only in squads
-- of `minSquad` robots or more. A swapped-in Swarmer brings its pack (Config.Enemies.Swarmer.pack). A type
-- whose switch is off (Config.Enemies.<Kind>.on = false) is never swapped in. Pure: Lune tests it.
-- Story missions and the opening keep their set robots (they do not come through here).

local EnemyVariety = {}

export type Row = { kind: string, n: number }

local function enabled(config: any, kind: string): boolean
	local cfg = config.Enemies[kind]
	return cfg ~= nil and cfg.on ~= false
end
EnemyVariety.enabled = enabled

-- The new types a fight at this level can bring (for the Dev panel and tests)
function EnemyVariety.unlocked(config: any, level: number): { string }
	local out = {}
	local v = config.Enemies.variety
	if not v or not v.on then
		return out
	end
	for _, sw in v.swaps do
		if level >= sw.level and enabled(config, sw.kind) then
			table.insert(out, sw.kind)
		end
	end
	return out
end

-- The squad with swaps made. rand() returns 0..1 (the server's Random; tests pass a seeded one).
function EnemyVariety.squad(config: any, list: { Row }, level: number, rand: () -> number): { Row }
	local v = config.Enemies.variety
	if not v or not v.on then
		return list
	end
	local total = 0
	for _, row in list do
		total += row.n
	end
	local counts: { [string]: number } = {}
	local out: { Row } = {}
	local function add(kind: string, n: number)
		local last = out[#out]
		if last and last.kind == kind then
			last.n += n
		else
			table.insert(out, { kind = kind, n = n })
		end
	end
	for _, row in list do
		for _ = 1, row.n do
			local kind = row.kind
			for _, sw in v.swaps do
				if
					level >= sw.level
					and total >= sw.minSquad
					and (counts[sw.kind] or 0) < sw.max
					and enabled(config, sw.kind)
					and table.find(sw.from, row.kind) ~= nil
					and rand() < sw.chance
				then
					kind = sw.kind
					counts[sw.kind] = (counts[sw.kind] or 0) + 1
					break
				end
			end
			-- a Swarmer slot is a whole pack; SiteKit spawns the pack through EnemySim.company
			add(kind, 1)
		end
	end
	return out
end

return EnemyVariety
