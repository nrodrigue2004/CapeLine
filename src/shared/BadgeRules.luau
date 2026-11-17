--!strict
-- BadgeRules: badges, counters, accolades and titles (spec: Hero MMO features > Badges and titles; H7).
-- Pure, so BadgeService, BadgeHud and the Lune tests agree:
-- * the badge list from Config.Badges (each with its save bit: its group's `at` + its place);
-- * counters (profile.mmo.counts): bump adds, a max key keeps the highest value;
-- * which badges a set of numbers earns (counters and facts read from the save, plus "group:<id>" = how many
--   of that group you have), each once;
-- * accolades: a group with every badge earned;
-- * titles: one shown at a time, from one id space: 0 = your origin's title, 1 to 255 = the story and Fame
--   titles (profile.titles bits), titleBase + bit = a badge's name, baneBase + i = "Bane of <nemesis>",
--   Config.Remembers.titleBase + track x 10 + tier = a reputation tier's title (lore step 12, Shared.RepTiers).
--   All fixed text from the lists; nothing typed.

local Bits = if script
	then require(script.Parent.ProfileSchema).Bits
	else (require :: any)("./ProfileSchema").Bits
local NemesisMath = if script then require(script.Parent.NemesisMath) else (require :: any)("./NemesisMath")
local RepTiers = if script then require(script.Parent.RepTiers) else (require :: any)("./RepTiers")

local BadgeRules = {}

export type Entry = {
	bit: number,
	id: string,
	name: string,
	key: string,
	n: number,
	hint: string,
	group: string,
	groupName: string,
}

local cache: { [any]: { Entry } } = {}

-- Every badge in book order, with its save bit
function BadgeRules.list(B: any): { Entry }
	local c = cache[B]
	if c then
		return c
	end
	local out = {}
	for _, g in B.groups do
		for i, b in g.badges do
			table.insert(out, {
				bit = g.at + i - 1,
				id = b.id,
				name = b.name,
				key = b.key,
				n = b.n,
				hint = b.hint,
				group = g.id,
				groupName = g.name,
			})
		end
	end
	cache[B] = out
	return out
end

function BadgeRules.byId(B: any, id: string): Entry?
	for _, e in BadgeRules.list(B) do
		if e.id == id then
			return e
		end
	end
	return nil
end

function BadgeRules.byBit(B: any, bit: number): Entry?
	for _, e in BadgeRules.list(B) do
		if e.bit == bit then
			return e
		end
	end
	return nil
end

function BadgeRules.has(words: { number }, e: Entry): boolean
	return Bits.get(words, e.bit)
end

-- How many badges you have (of a group, or all)
function BadgeRules.count(B: any, words: { number }, group: string?): number
	local n = 0
	for _, e in BadgeRules.list(B) do
		if (group == nil or e.group == group) and Bits.get(words, e.bit) then
			n += 1
		end
	end
	return n
end

-- Add to a counter (a max key keeps the highest value instead). Counters cap at 2^31.
function BadgeRules.bump(B: any, counts: { [string]: number }, key: string, n: number?)
	local v = n or 1
	if B.maxKeys[key] then
		counts[key] = math.max(counts[key] or 0, math.floor(v))
	else
		counts[key] = math.min(2 ^ 31, (counts[key] or 0) + v)
	end
end

-- The numbers a badge reads: counters, then facts on top (facts win: they come from the save itself)
function BadgeRules.have(counts: { [string]: number }, facts: { [string]: number }?): { [string]: number }
	local out = table.clone(counts)
	for k, v in facts or {} do
		out[k] = v
	end
	return out
end

-- The badges these numbers earn that the save does not have yet; marks their bits. A "group:<id>" key reads
-- how many of that group are earned, so it is checked after the rest.
function BadgeRules.earn(B: any, words: { number }, have: { [string]: number }): { Entry }
	local out = {}
	for pass = 1, 2 do
		for _, e in BadgeRules.list(B) do
			local meta = string.sub(e.key, 1, 6) == "group:"
			if (pass == 1) ~= meta and not Bits.get(words, e.bit) then
				local v = if meta
					then BadgeRules.count(B, words, string.sub(e.key, 7))
					else (have[e.key] or 0)
				if v >= e.n then
					Bits.set(words, e.bit)
					table.insert(out, e)
				end
			end
		end
	end
	return out
end

-- A badge's progress for the book: (have, need)
function BadgeRules.progress(
	B: any,
	words: { number },
	have: { [string]: number },
	e: Entry
): (number, number)
	if string.sub(e.key, 1, 6) == "group:" then
		return math.min(e.n, BadgeRules.count(B, words, string.sub(e.key, 7))), e.n
	end
	return math.min(e.n, have[e.key] or 0), e.n
end

-- The groups whose every badge is earned (each with an accolade, if it has one)
function BadgeRules.accolades(B: any, words: { number }): { any }
	local out = {}
	for _, g in B.groups do
		if g.accolade and BadgeRules.count(B, words, g.id) >= #g.badges then
			table.insert(out, g.accolade)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Titles
---------------------------------------------------------------------------

-- The story and Fame titles' names by bit (Config.Story.unlocks.titles; plate trims from 100 are not titles)
local function storyTitles(Config: any): { [number]: string }
	local out = {}
	for name, bit in Config.Story.unlocks.titles do
		if bit < 100 then
			out[bit] = name
		end
	end
	return out
end

-- The titles a character may show: { id, name } (id 0 is the origin's title, shown when nothing is picked)
function BadgeRules.titles(Config: any, profile: any, char: any): { { id: number, name: string } }
	local B = Config.Badges
	local out = {}
	local origin = Config.Creator.origins[char.origin or 0]
	table.insert(out, { id = 0, name = if origin then origin.title else "None" })
	local story = storyTitles(Config)
	for _, bit in Bits.list(profile.titles) do
		if story[bit] then
			table.insert(out, { id = bit, name = story[bit] })
		end
	end
	local mmo = char.mmo
	local words = profile.mmo and profile.mmo.badges -- badges are the account's
	if words then
		for _, e in BadgeRules.list(B) do
			if Bits.get(words, e.bit) then
				table.insert(out, { id = B.titleBase + e.bit, name = e.name })
			end
		end
	end
	-- H8: Hero Pass titles (kept forever once claimed)
	local P = Config.Pass
	if P and profile.pass and profile.pass.titles then
		for _, n in Bits.list(profile.pass.titles) do
			if P.titles[n] then
				table.insert(out, { id = P.titleBase + n, name = P.titles[n] })
			end
		end
	end
	-- lore step 12: the reputation tier titles (Vigil Trust and Syndicate Fear), held while the points are there
	if Config.Remembers then
		for _, t in RepTiers.titles(Config, char) do
			table.insert(out, t)
		end
	end
	if mmo and mmo.banes then
		for i, seed in mmo.banes do
			if seed ~= 0 then
				local name = NemesisMath.name(Config.Nemesis, seed, char.side or "hero")
				table.insert(out, { id = B.baneBase + i, name = "Bane of " .. name })
			end
		end
	end
	return out
end

-- The text of a title this character owns (nil when they do not own it)
function BadgeRules.titleText(Config: any, profile: any, char: any, id: number): string?
	for _, t in BadgeRules.titles(Config, profile, char) do
		if t.id == id then
			return t.name
		end
	end
	return nil
end

return BadgeRules
