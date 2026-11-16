--!strict
-- LootTable: server-rolled drops (spec: Drops). Pure, so Lune checks every source's odds over 10,000
-- rolls and the pity rules. LootService calls roll() and stores the pieces; the client only ever gets
-- the result.
--   roll(config, rng, source, ctx) -> { tier names }, pity changed
-- ctx = { level = hero level, pity = { epic, legendary } (changed in place), noPity = true for odds tests }
-- Level gates: a tier above the hero's level gate (Epic 20, Legendary 30) drops one tier lower. Fixed
-- story rewards skip the gate (the spec names them outright).

local LootTable = {}

type RngLike = { next: (any) -> number, int: (any, number, number) -> number }

local function pick(config: any, rng: RngLike, odds: { [string]: number }): string
	local order = config.Gear.tierOrder
	local total = 0
	for _, tier in order do
		total += odds[tier] or 0
	end
	local r = rng:next() * total
	for _, tier in order do
		local w = odds[tier] or 0
		if r < w then
			return tier
		end
		r -= w
	end
	return order[1]
end

-- The highest tier this hero's level allows, at or below `tier`
function LootTable.gate(config: any, tier: string, level: number): string
	local g = config.Gear
	local idx = table.find(g.tierOrder, tier) :: number
	while idx > 1 do
		local need = g.tierLevel[g.tierOrder[idx]]
		if not need or level >= need then
			break
		end
		idx -= 1
	end
	return g.tierOrder[idx]
end

function LootTable.roll(config: any, rng: RngLike, source: string, ctx: { [string]: any }): { string }
	local L = config.Loot
	local src = L.sources[source]
	assert(src, "unknown loot source " .. tostring(source))
	local level = ctx.level or 1
	local pity = ctx.pity or { epic = 0, legendary = 0 }
	local out: { string } = {}
	if src.chance and rng:next() >= src.chance then
		return out
	end
	if src.fixed then
		for _, tier in src.fixed do
			table.insert(out, tier)
		end
	else
		for _ = 1, src.pieces do
			table.insert(out, pick(config, rng, src.odds))
		end
	end
	if src.mvp then
		-- the MVP's piece is Legendary at 8%, and the 15th roll in a row without one is Legendary
		local hit = rng:next() < src.legendary
		if not hit and not ctx.noPity and pity.legendary + 1 >= L.pity.legendary then
			hit = true
		end
		if hit then
			out[1] = "Legendary"
			pity.legendary = 0
		else
			pity.legendary += 1
		end
	end
	if src.boss then
		local hasEpic = false
		for _, tier in out do
			if tier == "Epic" or tier == "Legendary" then
				hasEpic = true
			end
		end
		if not hasEpic and not ctx.noPity and pity.epic + 1 >= L.pity.epic then
			out[1] = "Epic"
			hasEpic = true
		end
		pity.epic = if hasEpic then 0 else pity.epic + 1
	end
	if not (source == "story" or source == "storyFinale") then
		for i, tier in out do
			out[i] = LootTable.gate(config, tier, level)
		end
	end
	return out
end

-- The odds as shown in the Loot Info screen: { { source name, "Common 70%, Uncommon 28%, ..." } }
function LootTable.infoRows(config: any): { { string } }
	local L = config.Loot
	local rows = {}
	for _, key in L.order do
		local src = L.sources[key]
		local parts = {}
		if src.fixed then
			table.insert(parts, table.concat(src.fixed, " + "))
		else
			for _, tier in config.Gear.tierOrder do
				local w = src.odds[tier]
				if w then
					table.insert(parts, string.format("%s %d%%", tier, w))
				end
			end
		end
		local text = table.concat(parts, ", ")
		if src.chance then
			text = string.format("%d%% chance of a piece: %s", math.floor(src.chance * 100 + 0.5), text)
		elseif src.pieces > 1 and not src.fixed then
			text = string.format("%d pieces, each %s", src.pieces, text)
		end
		if src.legendary then
			text ..= string.format("; Legendary %d%%", math.floor(src.legendary * 100 + 0.5))
		end
		table.insert(rows, { src.name, text })
	end
	table.insert(rows, {
		"Pity",
		string.format(
			"The %dth boss in a row with no Epic gives an Epic; the %dth MVP roll in a row with no Legendary gives a Legendary",
			L.pity.epic,
			L.pity.legendary
		),
	})
	table.insert(rows, { "Level gates", "Epic from level 20, Legendary from level 30" })
	return rows
end

return LootTable
