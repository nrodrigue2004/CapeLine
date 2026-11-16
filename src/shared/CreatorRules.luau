--!strict
-- CreatorRules: the hero creator's rules (spec: Hero creator; Character slots; Faction reputation "a style
-- unlock"). Pure, so Lune tests it.
-- * Pieces have one account-wide id each; profile.pieces is the bitset of unlocked ones. Free pieces are
--   always open. The M9 pieces are 1 to 146, tab by tab in Config.Creator order; tabs added later carry a
--   fixed base (piece i is base + i) and older tabs grow through tab.extra (its own base), so no id moves.
-- * validate(look): every piece exists and is unlocked, every colour is on the palette.
-- * nameOk(title, noun): both picked from the wheels, and the pair is not on the blocked list.
-- * earned(profile): the play-unlocked pieces this account has now earned (levels, reputation, Fame,
--   bosses, missions, side quests, Legacy) but not yet got; dropPick rolls a "drop" piece.
-- * randomize: a whole random look and name from what the account owns (the creator's Randomize button).

local LookCodec = if script then require(script.Parent.LookCodec) else (require :: any)("./LookCodec")
local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")
local StoryPlan = if script then require(script.Parent.StoryPlan) else (require :: any)("./StoryPlan")
local PvpRules = if script then require(script.Parent.PvpRules) else (require :: any)("./PvpRules")

local Bits = ProfileSchema.Bits

local CreatorRules = {}

-- the LookCodec record (repeated here: the pure-module require pattern drops cross-module types)
export type Look = {
	pieces: { [string]: number },
	colors: { number },
	hair: number,
	skin: number,
	anime: boolean,
	gender: number,
	build: number,
	height: number,
	eyeColor: number,
	tints: { [string]: { number } },
	mats: { [string]: number },
}

export type Source = { kind: string, a: string?, n: number? }
export type Piece = {
	id: number,
	tab: string,
	tabIndex: number,
	index: number,
	name: string,
	kit: string,
	source: Source,
}
export type Index = {
	list: { Piece },
	byTab: { [string]: { Piece } },
	byName: { [string]: Piece },
}

local cache: { [any]: Index } = {}

function CreatorRules.parse(s: string): Source
	local parts = string.split(s, ":")
	local kind = parts[1]
	if kind == "lvl" or kind == "fame" or kind == "mission" or kind == "quest" or kind == "legacy" then
		return { kind = kind, n = tonumber(parts[2]) }
	elseif kind == "pack" then
		return { kind = "pack", n = tonumber(parts[2]) }
	elseif kind == "rep" then
		return { kind = "rep", a = parts[2], n = tonumber(parts[3]) }
	elseif kind == "boss" then
		return { kind = "boss", a = parts[2], n = tonumber(parts[3]) }
	end
	return { kind = kind } -- free, drop, starter
end

function CreatorRules.index(Config: any): Index
	local hit = cache[Config]
	if hit then
		return hit
	end
	local idx: Index = { list = {}, byTab = {}, byName = {} }
	local nextLegacy = 1
	local function add(t: number, tab: any, row: any, id: number)
		local list = idx.byTab[tab.id]
		local p: Piece = {
			id = id,
			tab = tab.id,
			tabIndex = t,
			index = #list + 1,
			name = row[1],
			kit = row[2],
			source = CreatorRules.parse(row[3]),
		}
		table.insert(idx.list, p)
		table.insert(list, p)
		idx.byName[p.name] = p
	end
	for t, tab in Config.Creator.tabs do
		idx.byTab[tab.id] = {}
		for i, row in tab.pieces do
			if tab.base then
				add(t, tab, row, tab.base + i)
			else
				add(t, tab, row, nextLegacy)
				nextLegacy += 1
			end
		end
	end
	-- older tabs' extra pieces come after every tab's own pieces (ids from their own base)
	for t, tab in Config.Creator.tabs do
		if tab.extra then
			for i, row in tab.extra.pieces do
				add(t, tab, row, tab.extra.base + i)
			end
		end
	end
	cache[Config] = idx
	return idx
end

function CreatorRules.piece(Config: any, tab: string, index: number): Piece?
	local t = CreatorRules.index(Config).byTab[tab]
	return t and t[index]
end

function CreatorRules.owned(_Config: any, profile: any, p: Piece): boolean
	if p.source.kind == "free" then
		return true
	end
	return profile ~= nil and Bits.get(profile.pieces, p.id)
end

-- Unlock a piece for the account; true when it was new
function CreatorRules.grant(profile: any, p: Piece): boolean
	if Bits.get(profile.pieces, p.id) then
		return false
	end
	Bits.set(profile.pieces, p.id)
	return true
end

-- The pieces a Robux pack (or the starter pack, pack = nil) gives
function CreatorRules.packPieces(Config: any, pack: number?): { Piece }
	local out = {}
	for _, p in CreatorRules.index(Config).list do
		if
			(pack and p.source.kind == "pack" and p.source.n == pack)
			or (not pack and p.source.kind == "starter")
		then
			table.insert(out, p)
		end
	end
	return out
end

-- The default look (a new hero before the creator, or a save with no look)
function CreatorRules.defaultLook(Config: any): Look
	local d = Config.Creator.default
	return {
		pieces = table.clone(d.pieces),
		colors = table.clone(d.colors),
		hair = d.hair,
		skin = d.skin,
		anime = false,
		gender = d.gender,
		build = d.build,
		height = d.height,
		eyeColor = 0,
		tints = {},
		mats = {},
	}
end

-- A character's look (its saved words, or the default)
function CreatorRules.lookOf(Config: any, char: any): Look
	return LookCodec.read(char and char.look) or CreatorRules.defaultLook(Config)
end

function CreatorRules.validate(Config: any, profile: any, look: Look): (boolean, string?)
	local C = Config.Creator
	for _, slot in LookCodec.SLOTS do
		local i = look.pieces[slot] or 0
		if i ~= 0 then
			local p = CreatorRules.piece(Config, slot, i)
			if not p then
				return false, "piece"
			end
			if not CreatorRules.owned(Config, profile, p) then
				return false, "locked"
			end
		end
	end
	for i = 1, 3 do
		if not C.palette[look.colors[i]] then
			return false, "color"
		end
	end
	if not C.palette[look.hair] or not C.skins[look.skin] then
		return false, "color"
	end
	if look.eyeColor ~= 0 and not C.palette[look.eyeColor] then
		return false, "color"
	end
	for slot, t in look.tints or {} do
		if not table.find(LookCodec.SLOTS, slot) then
			return false, "slot"
		end
		for i = 1, 3 do
			local c = t[i] or 0
			if c ~= 0 and not C.palette[c] then
				return false, "color"
			end
		end
	end
	for slot, m in look.mats or {} do
		if not table.find(LookCodec.SLOTS, slot) or (m ~= 0 and not C.materials[m]) then
			return false, "material"
		end
	end
	local B = C.body
	if not B.genders[look.gender] or not B.builds[look.build] or not B.heights[look.height] then
		return false, "body"
	end
	return true, nil
end

function CreatorRules.heroName(Config: any, titleId: number, nounId: number): string?
	local t, n = Config.Creator.titles[titleId], Config.Creator.nouns[nounId]
	if not t or not n then
		return nil
	end
	return t .. " " .. n
end

function CreatorRules.nameOk(Config: any, titleId: number, nounId: number): boolean
	local name = CreatorRules.heroName(Config, titleId, nounId)
	return name ~= nil and table.find(Config.Creator.blockedNames, name) == nil
end

-- What the account has done, across every character (unlocks are account-wide)
local function best(Config: any, profile: any)
	local b = { level = 0, legacy = 0, fame = 0, rep = { 0, 0, 0 }, missions = 0, quests = {} }
	for _, c in profile.characters do
		b.level = math.max(b.level, c.level or 1)
		b.legacy = math.max(b.legacy, c.legacy or 0)
		b.fame = math.max(b.fame, PvpRules.fameRank(Config, c.fame or 0))
		for i = 1, 3 do
			b.rep[i] = math.max(b.rep[i], StoryPlan.repRank(Config, (c.rep and c.rep[i]) or 0))
		end
		local st = c.story
		if st then
			b.missions = bit32.bor(b.missions, st.missions or 0)
			for q, state in st.quests or {} do
				if state == 4 then
					b.quests[q] = true
				end
			end
		end
	end
	-- a retired hero's level counts too (the Hall of Legends)
	for _, s in profile.legends or {} do
		b.level = math.max(b.level, s.level or 0)
	end
	return b
end

local function earnedBy(Config: any, profile: any, b: any, s: Source): boolean
	local k, n = s.kind, s.n or 0
	if k == "lvl" then
		return b.level >= n
	elseif k == "legacy" then
		return b.legacy >= n
	elseif k == "fame" then
		return b.fame >= n
	elseif k == "rep" then
		return b.rep[StoryPlan.repIndex(Config, s.a :: string)] >= n
	elseif k == "mission" then
		return StoryPlan.cleared({ missions = b.missions }, n)
	elseif k == "quest" then
		return b.quests[n] == true
	elseif k == "boss" then
		local i = table.find(Config.Boss.order, s.a)
		return i ~= nil and (profile.bosses[i] or 0) >= n
	end
	return false
end

-- Play-unlocked pieces earned but not yet unlocked (grant them, then toast each)
function CreatorRules.earned(Config: any, profile: any): { Piece }
	local b = best(Config, profile)
	local out = {}
	for _, p in CreatorRules.index(Config).list do
		if not Bits.get(profile.pieces, p.id) and earnedBy(Config, profile, b, p.source) then
			table.insert(out, p)
		end
	end
	return out
end

-- An Epic or Legendary drop may also unlock a random locked "drop" piece
function CreatorRules.dropPick(Config: any, profile: any, rng: any): Piece?
	if not rng:chance(Config.Creator.dropChance) then
		return nil
	end
	local pool = {}
	for _, p in CreatorRules.index(Config).list do
		if p.source.kind == "drop" and not Bits.get(profile.pieces, p.id) then
			table.insert(pool, p)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:int(1, #pool)]
end

-- Owned pieces of one tab (for the creator's grid and Randomize)
function CreatorRules.ownedIn(Config: any, profile: any, tab: string): { Piece }
	local out = {}
	for _, p in CreatorRules.index(Config).byTab[tab] or {} do
		if CreatorRules.owned(Config, profile, p) then
			table.insert(out, p)
		end
	end
	return out
end

-- Randomize: a look from owned pieces (cape, hair, eyes, aura may be left off) and a valid name
function CreatorRules.randomize(Config: any, profile: any, rng: any): (Look, number, number)
	local C = Config.Creator
	local look = CreatorRules.defaultLook(Config)
	-- the chance a slot gets a piece at all (slots not listed always get one)
	local optional = {
		back = 0.8,
		aura = 0.4,
		hair = 0.7,
		eyes = 0.3,
		head = 0.85,
		hands = 0.85,
		feet = 0.9,
		beard = 0.25,
		makeup = 0.2,
		hat = 0.3,
		ears = 0.3,
		shoulders = 0.4,
		neck = 0.35,
		arms = 0.35,
		wrist = 0.3,
		belt = 0.6,
		legs = 0.5,
		backpack = 0.25,
	}
	for _, slot in LookCodec.SLOTS do
		local pool = CreatorRules.ownedIn(Config, profile, slot)
		local keep = optional[slot]
		if #pool == 0 or (keep and not rng:chance(keep)) then
			look.pieces[slot] = 0
		else
			look.pieces[slot] = pool[rng:int(1, #pool)].index
		end
	end
	local n = #C.palette
	look.colors = { rng:int(1, n), rng:int(1, n), rng:int(1, n) }
	look.hair = rng:int(1, n)
	look.skin = rng:int(1, #C.skins)
	look.anime = rng:chance(0.5)
	look.gender = rng:int(1, #C.body.genders)
	look.build = rng:int(1, #C.body.builds)
	look.height = rng:int(1, #C.body.heights)
	if look.pieces.eyes ~= 0 then
		look.eyeColor = rng:int(1, n)
	end
	local t, w = 1, 1
	for _ = 1, 40 do
		t, w = rng:int(1, #C.titles), rng:int(1, #C.nouns)
		if CreatorRules.nameOk(Config, t, w) then
			break
		end
	end
	return look, t, w
end

-- Hero.Create's other picks: the archetype, one of its paths (with its abilities built) and a mobility
function CreatorRules.pickOk(
	Config: any,
	classId: string?,
	setId: string?,
	side: string?,
	mobility: string?
): boolean
	local class = classId and Config.Classes[classId]
	if not class or not setId or not table.find(class.paths, setId) then
		return false
	end
	local ready = false
	for _, row in Config.Abilities.list do
		if row.set == setId and row.slot == "super" then
			ready = true
		end
	end
	return ready
		and (side == "hero" or side == "villain")
		and (mobility == nil or Config.Move.mobility[mobility] ~= nil)
end

-- May this hero change its archetype or path now? Once, before Abilities.pathChangeBefore (nate 2026-11-16)
function CreatorRules.pathChangeOk(Config: any, level: number, pathChanged: number): boolean
	return pathChanged == 0 and level < Config.Abilities.pathChangeBefore
end

-- Which gear styles show over a look: styles (one per gear slot, Inventory.shownStyles), shown (the
-- character's Show Style picks). A creator piece covers its gear slot unless a style was picked there.
function CreatorRules.visibleStyles(
	Config: any,
	look: Look,
	styles: { number },
	shown: { number }
): { number }
	local out = table.clone(styles)
	for slotIdx, slot in Config.Gear.slotOrder do
		local tab = Config.Creator.covers[slot]
		if tab and (look.pieces[tab] or 0) ~= 0 and (shown[slotIdx] or 0) == 0 then
			out[slotIdx] = 0
		end
	end
	return out
end

-- Character slots: 2 free; slots 3 and 4 are bought (profile.purchases.slots, a bit per slot)
function CreatorRules.maxSlots(profile: any): number
	local n = 2
	for slot = 3, 4 do
		if bit32.btest(profile.purchases.slots or 0, bit32.lshift(1, slot)) then
			n += 1
		end
	end
	return n
end

return CreatorRules
