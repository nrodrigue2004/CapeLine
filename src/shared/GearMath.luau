--!strict
-- GearMath: every gear number as pure maths (spec: Tiers, slots and piece budget; Style collection,
-- salvage and upgrade; Epic sets; Legendary perks). Lune tests run it; the server rolls with it and the
-- client shows the same numbers. A piece is a plain table (the spec's Piece record):
--   id, slot (1-8), tier (1-6), ilvl, up (0-10), main (base value of the slot's main stat),
--   bonus = { { stat index, base value } }, set (0 or set index), perk (0 or perk index),
--   gadget (0 or gadget index), style (style id), retunes, seed
-- Upgrades scale every stat by 1 + 4% x up when stats are read; the saved values never change.

local GearMath = {}

export type Piece = {
	id: number,
	slot: number,
	tier: number,
	ilvl: number,
	up: number,
	main: number,
	bonus: { { number } },
	set: number,
	perk: number,
	gadget: number,
	style: number,
	retunes: number,
	seed: number,
}

export type Totals = {
	stats: { [string]: number },
	gearScore: number,
	sets: { [string]: number }, -- set name -> pieces worn
	perks: { [string]: boolean },
	gadget: string?,
	setDamage: { [string]: number }, -- power set -> damage bonus (2-piece)
	abilityMods: { [string]: { any } }, -- ability id -> mods (4-piece), applied after ranks
}

type RngLike = { next: (any) -> number, int: (any, number, number) -> number }

local function G(config: any): any
	return config.Gear
end

function GearMath.slotName(config: any, piece: Piece): string
	return G(config).slotOrder[piece.slot]
end

function GearMath.tierName(config: any, piece: Piece): string
	return G(config).tierOrder[piece.tier]
end

function GearMath.tierIndex(config: any, name: string): number
	return table.find(G(config).tierOrder, name) or 1
end

function GearMath.slotIndex(config: any, name: string): number
	return table.find(G(config).slotOrder, name) or 1
end

function GearMath.mainStat(config: any, piece: Piece): string?
	return G(config).slots[GearMath.slotName(config, piece)].main
end

-- Budget at roll time: round(ilvl x 1.5 x tier mult). Gadgets have none.
function GearMath.baseBudget(config: any, slot: string, tier: string, ilvl: number): number
	local g = G(config)
	if not g.slots[slot].main then
		return 0
	end
	return math.floor(ilvl * g.budget.perIlvl * g.tiers[tier].mult + 0.5)
end

function GearMath.upgradeMult(config: any, up: number): number
	return 1 + G(config).upgrade.perStep * up
end

-- The budget including upgrades (what gear score adds up)
function GearMath.budget(config: any, piece: Piece): number
	local base = GearMath.baseBudget(
		config,
		GearMath.slotName(config, piece),
		GearMath.tierName(config, piece),
		piece.ilvl
	)
	return math.floor(base * GearMath.upgradeMult(config, piece.up) + 0.5)
end

-- The piece's stats with upgrades: { Might = 12, Focus = 4 }
function GearMath.stats(config: any, piece: Piece): { [string]: number }
	local g = G(config)
	local out = {}
	local mult = GearMath.upgradeMult(config, piece.up)
	local main = GearMath.mainStat(config, piece)
	if main then
		out[main] = math.floor(piece.main * mult + 0.5)
	end
	for _, b in piece.bonus do
		local name = g.stats[b[1]]
		if name then
			out[name] = (out[name] or 0) + math.floor(b[2] * mult + 0.5)
		end
	end
	return out
end

-- Item level for a drop: zone level +- spread, at least 1
function GearMath.itemLevel(config: any, rng: RngLike, zoneLevel: number): number
	local g = G(config)
	return math.clamp(zoneLevel + rng:int(-g.ilvlSpread, g.ilvlSpread), 1, g.ilvlMax)
end

-- The style a new piece shows: a set's look, a Legendary look, or one from the slot's pool for its tier
function GearMath.styleId(slotIdx: number, n: number): number
	return slotIdx * 64 + n
end

function GearMath.styleParts(id: number): (number, number)
	return id // 64, id % 64
end

function GearMath.styleRow(config: any, id: number): any?
	local g = G(config)
	local slotIdx, n = GearMath.styleParts(id)
	local slot = g.slotOrder[slotIdx]
	if not slot then
		return nil
	end
	if n > g.setStyleBase and n <= g.setStyleBase + #g.setOrder then
		local setName = g.setOrder[n - g.setStyleBase]
		return {
			n = n,
			name = setName .. " " .. g.slots[slot].name,
			shape = "set",
			set = setName,
			slot = slot,
		}
	elseif n == g.legendaryStyleN then
		return { n = n, name = "Gilded " .. g.slots[slot].name, shape = "gilded", slot = slot }
	end
	for _, row in g.styles[slot] do
		if row.n == n then
			return row
		end
	end
	return nil
end

-- Every style id that can exist (the collection screen lists these)
function GearMath.allStyles(config: any): { number }
	local g = G(config)
	local out = {}
	for slotIdx, slot in g.slotOrder do
		for _, row in g.styles[slot] do
			table.insert(out, GearMath.styleId(slotIdx, row.n))
		end
		if g.slots[slot].main then
			if table.find(g.setSlots, slot) then
				for i in g.setOrder do
					table.insert(out, GearMath.styleId(slotIdx, g.setStyleBase + i))
				end
			end
			table.insert(out, GearMath.styleId(slotIdx, g.legendaryStyleN))
		end
	end
	return out
end

local function pickStyle(
	config: any,
	rng: RngLike,
	slot: string,
	tier: string,
	set: number,
	perk: number
): number
	local g = G(config)
	local slotIdx = table.find(g.slotOrder, slot) :: number
	if set > 0 then
		return GearMath.styleId(slotIdx, g.setStyleBase + set)
	end
	if perk > 0 then
		return GearMath.styleId(slotIdx, g.legendaryStyleN)
	end
	local tierIdx = table.find(g.tierOrder, tier) :: number
	local pool = {}
	for _, row in g.styles[slot] do
		local rowTier = table.find(g.tierOrder, row.tier) -- nil for boss drops: never rolled
		if rowTier and rowTier <= tierIdx then
			table.insert(pool, row.n)
		end
	end
	if #pool == 0 then
		return 0
	end
	return GearMath.styleId(slotIdx, pool[rng:int(1, #pool)])
end

-- The style id a world boss drops (shiny or not), or nil
function GearMath.bossStyle(config: any, bossId: string, shiny: boolean): number?
	local g = G(config)
	for slotIdx, slot in g.slotOrder do
		for _, row in g.styles[slot] do
			if row.boss == bossId and (row.shiny == true) == shiny then
				return GearMath.styleId(slotIdx, row.n)
			end
		end
	end
	return nil
end

-- The style a side quest gives (Gear styles with quest = name), or nil
function GearMath.questStyle(config: any, name: string): number?
	local g = G(config)
	for slotIdx, slot in g.slotOrder do
		for _, row in g.styles[slot] do
			if row.quest == name then
				return GearMath.styleId(slotIdx, row.n)
			end
		end
	end
	return nil
end

-- Roll one piece. opts: { id, gadget = true (force the gadget slot), slot = name }
function GearMath.roll(config: any, rng: RngLike, tier: string, ilvl: number, opts: { [string]: any }?): Piece
	local g = G(config)
	local o = opts or {}
	local slot: string = o.slot
	if not slot then
		if o.gadget then
			slot = "gadget"
		else
			slot = g.slotOrder[rng:int(1, 7)] -- the 7 stat slots
		end
	end
	local tierRow = g.tiers[tier]
	local set, perk, gadget = 0, 0, 0
	if tierRow.set and table.find(g.setSlots, slot) then
		set = rng:int(1, #g.setOrder)
	end
	if tierRow.perk and slot ~= "gadget" then
		perk = rng:int(1, #g.perkOrder)
	end
	if slot == "gadget" then
		gadget = rng:int(1, #g.gadgetOrder)
	end
	local budget = GearMath.baseBudget(config, slot, tier, ilvl)
	local main = 0
	local bonus = {}
	local mainName = g.slots[slot].main
	if mainName then
		local n = tierRow.bonus
		if n == 0 then
			main = budget
		else
			main = math.floor(budget * g.budget.mainShare + 0.5)
			local rest = budget - main
			local each = rest // n
			local pool = {}
			for i, name in g.stats do
				if name ~= mainName then
					table.insert(pool, i)
				end
			end
			for k = 1, n do
				local pickAt = rng:int(1, #pool)
				local stat = table.remove(pool, pickAt) :: number
				local value = if k == n then rest - each * (n - 1) else each
				table.insert(bonus, { stat, value })
			end
		end
	end
	return {
		id = o.id or 0,
		slot = table.find(g.slotOrder, slot) :: number,
		tier = table.find(g.tierOrder, tier) :: number,
		ilvl = ilvl,
		up = 0,
		main = main,
		bonus = bonus,
		set = set,
		perk = perk,
		gadget = gadget,
		style = pickStyle(config, rng, slot, tier, set, perk),
		retunes = 0,
		seed = rng:int(0, 65535),
	}
end

-- Upgrade: the Lumen Dust for the next step (nil at +10)
function GearMath.upgradeCost(config: any, piece: Piece): number?
	local u = G(config).upgrade
	local n = piece.up + 1
	if n > u.max then
		return nil
	end
	return math.floor(u.base * n ^ u.power * G(config).tiers[GearMath.tierName(config, piece)].mult + 0.5)
end

function GearMath.salvageValue(config: any, piece: Piece): number
	local g = G(config)
	return math.floor(
		g.tiers[GearMath.tierName(config, piece)].dust * (1 + piece.ilvl / g.salvage.perIlvl) + 0.5
	)
end

function GearMath.retuneCost(config: any, piece: Piece): number
	local g = G(config)
	return math.floor(g.retune.credits * g.tiers[GearMath.tierName(config, piece)].mult + 0.5)
end

-- Reroll bonus stat `index` to a stat the piece does not have yet (the value stays: the budget is fixed)
function GearMath.retune(config: any, rng: RngLike, piece: Piece, index: number): boolean
	local g = G(config)
	local b = piece.bonus[index]
	if not b or piece.retunes >= g.retune.max then
		return false
	end
	local main = GearMath.mainStat(config, piece)
	local pool = {}
	for i, name in g.stats do
		local taken = name == main
		for _, other in piece.bonus do
			if other[1] == i then
				taken = true
			end
		end
		if not taken then
			table.insert(pool, i)
		end
	end
	if #pool == 0 then
		return false
	end
	b[1] = pool[rng:int(1, #pool)]
	piece.retunes += 1
	return true
end

function GearMath.canWear(config: any, heroLevel: number, piece: Piece): boolean
	return piece.ilvl <= heroLevel + G(config).equipSlack
end

-- Add up what a hero wears: stats, gear score (7 stat slots with upgrades), sets, perks, gadget
function GearMath.totals(config: any, worn: { Piece }): Totals
	local g = G(config)
	local stats = {}
	for _, name in g.stats do
		stats[name] = 0
	end
	local score = 0
	local sets: { [string]: number } = {}
	local perks: { [string]: boolean } = {}
	local gadget = nil
	for _, piece in worn do
		for name, v in GearMath.stats(config, piece) do
			stats[name] += v
		end
		score += GearMath.budget(config, piece)
		if piece.set > 0 then
			local setName = g.setOrder[piece.set]
			sets[setName] = (sets[setName] or 0) + 1
		end
		if piece.perk > 0 then
			perks[g.perkOrder[piece.perk]] = true
		end
		if piece.gadget > 0 then
			gadget = g.gadgetOrder[piece.gadget]
		end
	end
	local setDamage: { [string]: number } = {}
	local abilityMods: { [string]: { any } } = {}
	for setName, count in sets do
		local row = g.sets[setName]
		if count >= 2 then
			setDamage[row.power] = (setDamage[row.power] or 0) + row.two.damage
		end
		if count >= 4 then
			local four = row.four
			abilityMods[four.ability] = abilityMods[four.ability] or {}
			table.insert(abilityMods[four.ability], { add = four.add, mul = four.mul, set = four.set })
		end
	end
	return {
		stats = stats,
		gearScore = score,
		sets = sets,
		perks = perks,
		gadget = gadget,
		setDamage = setDamage,
		abilityMods = abilityMods,
	}
end

-- A short description for the piece card
function GearMath.describe(config: any, piece: Piece): { string }
	local g = G(config)
	local lines = {}
	local stats = GearMath.stats(config, piece)
	local main = GearMath.mainStat(config, piece)
	if main then
		table.insert(lines, string.format("+%d %s", stats[main] or 0, main))
	end
	for _, b in piece.bonus do
		local name = g.stats[b[1]]
		table.insert(
			lines,
			string.format("+%d %s", math.floor(b[2] * GearMath.upgradeMult(config, piece.up) + 0.5), name)
		)
	end
	if piece.set > 0 then
		local setName = g.setOrder[piece.set]
		local row = g.sets[setName]
		table.insert(
			lines,
			string.format("%s set (2): %s damage +%d%%", setName, row.power, row.two.damage * 100)
		)
		table.insert(lines, string.format("%s set (4): %s", setName, row.four.text))
	end
	if piece.perk > 0 then
		local row = g.perks[g.perkOrder[piece.perk]]
		table.insert(lines, row.name .. ": " .. row.text)
	end
	if piece.gadget > 0 then
		local row = g.gadgets[g.gadgetOrder[piece.gadget]]
		table.insert(lines, string.format("%s (every %d s)", row.name, row.cd))
	end
	return lines
end

return GearMath
