-- PeopleLooks: the side quests' people in outfits of their own (2026-11-18 art pass; Config.NpcLooks.people and
-- helpers, drawn by art/clothes/people.py). Pure: no Roblox instances, so Lune tests it. The callers put the
-- outfit on a rig with NpcRig.wearOutfit:
-- * a giver (SideQuestService), a dressed finale villain or a costumed finale villain (EnemyRenderer) builds its
--   look with strip() (the outfit draws the suit, shirt, pants and legs; hats, coats, gloves, boots, hair and
--   capes stay), then wears the outfit's clothes image and face;
-- * a named helper (helperAt) stands in for a step's witness or the one carried, in their speaker card's skin
--   and hair, in their outfit once it is uploaded (else plain shirt and pants colours).
-- Every id is 0 until nate uploads the image; a person with nothing uploaded keeps today's look exactly.
-- * the named cast's catalog picks (2026-11-19, the hair fit pass; nate's rule: faces and hair only from the
--   Roblox catalog): a person with a creator look names a catalog face and hair piece in the look itself (or
--   `hairless = true`), everyone else has a row in Config.NpcLooks.cast (castPick). castProblems lists any named
--   character still left to a name hash. The drawn faces in Config.NpcLooks.people are no longer worn (the catalog
--   face shows); only a famous fake's `cracked` face stays, for the unmask.

local CreatorRules = if script
	then require(script.Parent.CreatorRules)
	else (require :: any)("./CreatorRules")

local PeopleLooks = {}

-- The speakers (Config.Story.guides.speakers) whose look is another config row's: a side quest dress, a fake's
-- look or a named helper (art/panels/cast.luau draws them the same way)
PeopleLooks.SPEAKERS = {
	halo = "HeadmasterHalo",
	redline = "Redline",
	masque = "MasqueARade",
	harvest = "HarvestKing",
	brine = "CaptainBrine",
	pitboss = "Pitboss",
	tidewright = "Tidewright",
	vesper = "Vesper",
	catchpole = "Catchpole",
	scorch = "Scorch",
	censor = "Censor",
	holloway = "Holloway",
	voidhound = "Voidhound",
	morrow = "Morrow",
	clawback = "Clawback",
	gale = "Gale",
	radiant = "Radiant",
	bulwark = "Bulwark",
	wren = "Wren",
	toby = "Toby",
	flint = "Flint",
	finn = "Finn",
	dace = "Dace",
	ambrose = "Ambrose",
	hoshi = "Hoshi",
}

-- the look slots an outfit draws (they come off the look when the outfit is worn)
PeopleLooks.DRAWN = { "suit", "shirt", "pants", "legs" }

export type Outfit = { clothes: string?, face: string?, cracked: string? }

local function image(n: any): string?
	if type(n) == "number" and n > 0 then
		return "rbxassetid://" .. string.format("%d", n)
	end
	return nil
end

-- The uploaded images of one person (a people key), or nil when none is uploaded
function PeopleLooks.outfit(Config: any, id: string?): Outfit?
	local p = id and Config.NpcLooks.people and Config.NpcLooks.people[id]
	if type(p) ~= "table" then
		return nil
	end
	-- the drawn face (p.face) is not worn: faces come only from the Roblox catalog (the look's catalog face, or
	-- the cast pick); a famous fake keeps its cracked face for the unmask
	local fit: Outfit = { clothes = image(p.clothes), face = nil, cracked = image(p.cracked) }
	if not fit.clothes and not fit.cracked then
		return nil
	end
	return fit
end

-- Who a finale villain is (its people key): the dress it wears, else its own robot kind
function PeopleLooks.villain(dress: string?, kind: string?): string?
	if type(dress) == "string" and dress ~= "" then
		return dress
	end
	return kind
end

-- A look without the slots the outfit draws (a copy; the look itself is not changed)
function PeopleLooks.strip(look: any): any
	local out = table.clone(look)
	local pieces = table.clone(look.pieces or {})
	for _, slot in PeopleLooks.DRAWN do
		pieces[slot] = nil
	end
	out.pieces = pieces
	return out
end

-- The named helper drawn for a chain's step on one goal key ("hero", "villain" or "both"), or nil
function PeopleLooks.helperAt(Config: any, chainId: string, step: number, key: string): (string?, any)
	for id, h in Config.NpcLooks.helpers or {} do
		if h.chain == chainId and h.step == step and (key == "both" or key == h.side) then
			return id, h
		end
	end
	return nil, nil
end

-- A catalog face row ({ name, face asset, image }) and hair row ({ name, asset }) by name, or nil
local function catFace(Config: any, name: any): any
	for _, f in Config.CatalogLooks.faces do
		if f[1] == name then
			return f
		end
	end
	return nil
end
local function catHair(Config: any, name: any): any
	for _, h in Config.CatalogLooks.hair do
		if h[1] == name then
			return h
		end
	end
	return nil
end
local function catBeard(Config: any, name: any): any
	for _, b in Config.CatalogLooks.beards or {} do
		if b[1] == name then
			return b
		end
	end
	return nil
end

-- The explicit catalog pick of a named person with no creator look (Config.NpcLooks.cast; a speaker key or a
-- mentor id): the face's image ("rbxassetid://...") and the hair accessory's asset id (nil: no hair). Nil when
-- the key has no pick (the rig keeps its own).
function PeopleLooks.castPick(
	Config: any,
	key: string?
): { face: string?, hair: number?, bald: boolean, beard: number? }?
	local row = key and Config.NpcLooks.cast and Config.NpcLooks.cast[key]
	if type(row) ~= "table" then
		return nil
	end
	local f = catFace(Config, row.face)
	local h = if row.hair then catHair(Config, row.hair) else nil
	local b = if row.beard then catBeard(Config, row.beard) else nil
	return {
		face = if f then "rbxassetid://" .. string.format("%d", f[3]) else nil,
		hair = if h then h[2] else nil,
		bald = row.hair == false,
		beard = if b then b[2] else nil, -- the catalog beard's asset id (gap-villains, 2026-11-19)
	}
end

-- The creator look def (piece names) of a named person: a speaker, giver, people, dress, fake or incident key
function PeopleLooks.lookDef(Config: any, key: string): any
	if key == "lodestar" then
		return Config.Story.opening.lodestar.look
	end
	local sp = Config.Story.guides.speakers[key]
	if sp and sp.look then
		return sp.look
	end
	local g = Config.SideQuests.givers[key]
	if g and g.look then
		return g.look
	end
	local pk = PeopleLooks.SPEAKERS[key] or key
	local d = Config.SideQuests.dress and Config.SideQuests.dress[pk]
	if d and d.look then
		return d.look
	end
	local e = Config.Enemies[pk]
	if type(e) == "table" and e.fake and e.fake.look then
		return e.fake.look
	end
	local i = Config.Incidents.dress and Config.Incidents.dress[pk]
	if i and i.look then
		return i.look
	end
	return nil
end

-- Every named character's key: the speakers, the side quest givers (not the Dev sample or Patch's relay box),
-- the mentors, the side quest dresses, the fakes with a look and the incident dresses
function PeopleLooks.namedKeys(Config: any): { string }
	local seen, out = {}, {}
	local function add(k: string)
		if not seen[k] then
			seen[k] = true
			table.insert(out, k)
		end
	end
	for k in Config.Story.guides.speakers do
		add(k)
	end
	for k, g in Config.SideQuests.givers do
		if k ~= "SampleGiver" and not g.relay then
			add(k)
		end
	end
	for _, m in Config.Mentors.list do
		add(m.id)
	end
	for k in Config.SideQuests.dress or {} do
		add(k)
	end
	for k, e in Config.Enemies do
		if type(e) == "table" and e.fake and e.fake.look then
			add(k)
		end
	end
	for k in Config.Incidents.dress or {} do
		add(k)
	end
	table.sort(out)
	return out
end

-- The catalog face and hair a named character wears, by name: (face name, hair name or false), and an error
-- text when the pick is not an explicit catalog item; then the catalog beard's name, or nil (gap-villains,
-- 2026-11-19: a look's beard piece or the cast row's beard must be a Config.CatalogLooks beard)
function PeopleLooks.catalogPick(Config: any, key: string): (string?, any, string?, string?)
	local def = PeopleLooks.lookDef(Config, key)
	if def then
		local byTab = CreatorRules.index(Config).byTab
		local function cat(tab: string, name: any): any
			for _, p in byTab[tab] or {} do
				if p.name == name then
					return if string.sub(p.kit, 1, 4) == "cat:" then p else nil
				end
			end
			return nil
		end
		local face = def.pieces.visage
		if not (cat("visage", face) and catFace(Config, face)) then
			return nil, nil, key .. ": the look's face " .. tostring(face) .. " is not a Roblox catalog face"
		end
		local beard = def.pieces.beard
		if beard ~= nil and not (cat("beard", beard) and catBeard(Config, beard)) then
			return nil,
				nil,
				key .. ": the look's beard " .. tostring(beard) .. " is not a Roblox catalog beard"
		end
		local hair = def.pieces.hair
		if hair == nil then
			if def.hairless ~= true then
				return nil, nil, key .. ": the look has no hair piece and no hairless = true"
			end
			return face, false, nil, beard
		end
		if def.hairless then
			return nil, nil, key .. ": hairless but the look names hair " .. tostring(hair)
		end
		if not (cat("hair", hair) and catHair(Config, hair)) then
			return nil, nil, key .. ": the look's hair " .. tostring(hair) .. " is not a Roblox catalog hair"
		end
		return face, hair, nil, beard
	end
	local row = Config.NpcLooks.cast and Config.NpcLooks.cast[key]
	if type(row) ~= "table" then
		return nil, nil, key .. ": no explicit catalog pick (Config.NpcLooks.cast or a look)"
	end
	if not catFace(Config, row.face) then
		return nil, nil, key .. ": cast face " .. tostring(row.face) .. " is not in Config.CatalogLooks"
	end
	if row.hair ~= false and not catHair(Config, row.hair) then
		return nil, nil, key .. ": cast hair " .. tostring(row.hair) .. " is not in Config.CatalogLooks"
	end
	if row.beard ~= nil and not catBeard(Config, row.beard) then
		return nil, nil, key .. ": cast beard " .. tostring(row.beard) .. " is not in Config.CatalogLooks"
	end
	return row.face, row.hair, nil, row.beard
end

-- Named characters left without an explicit catalog face and hair (tests)
function PeopleLooks.castProblems(Config: any): { string }
	local out = {}
	for _, k in PeopleLooks.namedKeys(Config) do
		local _, _, err = PeopleLooks.catalogPick(Config, k)
		if err then
			table.insert(out, err)
		end
	end
	for k in Config.NpcLooks.cast or {} do
		if PeopleLooks.lookDef(Config, k) then
			table.insert(out, k .. ": has a creator look, so its cast row is never used")
		end
	end
	return out
end

-- Problems with the tables (tests): every person is a giver, a dress, a finale villain or a helper; every id
-- is a whole number; every helper points at a witness or carry goal on its side and has a speaker card
function PeopleLooks.problems(Config: any): { string }
	local out = {}
	local SQ = Config.SideQuests
	local NL = Config.NpcLooks
	local finale = {}
	for _, k in SQ.finale.enemies do
		finale[k] = true
	end
	for id, p in NL.people or {} do
		local known = SQ.givers[id] ~= nil
			or (SQ.dress and SQ.dress[id] ~= nil)
			or (finale[id] and Config.Enemies[id] ~= nil)
			or (NL.helpers and NL.helpers[id] ~= nil)
		if not known then
			table.insert(out, id .. " is not a giver, dress, finale villain or helper")
		end
		for _, k in { "clothes", "face", "cracked" } do
			local v = p[k]
			if v ~= nil and (type(v) ~= "number" or v < 0 or v % 1 ~= 0) then
				table.insert(out, id .. "." .. k .. " is not an id")
			end
		end
		if p.clothes == nil then
			table.insert(out, id .. " has no clothes slot")
		end
	end
	local byId = {}
	for _, ch in SQ.chains do
		byId[ch.id] = ch
	end
	for id, h in NL.helpers or {} do
		local ch = byId[h.chain]
		local st = ch and ch.steps[h.step]
		local g = st and (st[h.side] or st.hero)
		if not (g and ((g.kind == "find" and g.witness) or g.kind == "carry")) then
			table.insert(out, id .. " does not point at a witness or carry step")
		end
		if not (NL.people and NL.people[id]) then
			table.insert(out, id .. " has no people row")
		end
		local sp = Config.Story.guides.speakers[h.speaker or ""]
		if not (sp and sp.portrait) then
			table.insert(out, id .. " has no speaker card")
		end
		for _, k in { "shirt", "pants" } do
			local c = h[k]
			if not (type(c) == "table" and #c == 3) then
				table.insert(out, id .. "." .. k .. " is not a colour")
			end
		end
	end
	return out
end

return PeopleLooks
