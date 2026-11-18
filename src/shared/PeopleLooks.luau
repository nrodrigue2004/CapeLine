-- PeopleLooks: the side quests' people in outfits of their own (2026-11-18 art pass; Config.NpcLooks.people and
-- helpers, drawn by art/clothes/people.py). Pure: no Roblox instances, so Lune tests it. The callers put the
-- outfit on a rig with NpcRig.wearOutfit:
-- * a giver (SideQuestService), a dressed finale villain or a costumed finale villain (EnemyRenderer) builds its
--   look with strip() (the outfit draws the suit, shirt, pants and legs; hats, coats, gloves, boots, hair and
--   capes stay), then wears the outfit's clothes image and face;
-- * a named helper (helperAt) stands in for a step's witness or the one carried, in their speaker card's skin
--   and hair, in their outfit once it is uploaded (else plain shirt and pants colours).
-- Every id is 0 until nate uploads the image; a person with nothing uploaded keeps today's look exactly.

local PeopleLooks = {}

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
	local fit: Outfit = { clothes = image(p.clothes), face = image(p.face), cracked = image(p.cracked) }
	if not fit.clothes and not fit.face then
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
