-- cast.luau: the comic art pass's cast and pages as JSON for art/blender/panels.py (2026-11-19). Every guide
-- portrait (Config.Story.guides.speakers and the side quest givers, Config.SideQuests.givers) and every mentor
-- (Config.Mentors.list) as a person to stage on Roblox's blocky R15 body: their game outfit (the uploaded classic
-- clothes, Config.NpcLooks.people, else the creator look's colours, else a picked shirt and pants), their creator
-- pieces that show (hats, masks, capes), a Roblox catalog face and catalog hair (nate's hard rule: faces, hair,
-- facial hair and eyes only from the catalog). Every named person has an explicit catalog pick, the same one the
-- game wears (2026-11-19, the hair fit pass; Shared.PeopleLooks.catalogPick): a creator look names its catalog
-- face and hair pieces, everyone else has a row in Config.NpcLooks.cast.
-- Also every comic page panel (Config.Cinema.comic.pages) with its scene, colours, caption and shape.
-- Run from the repo root: lune run art/panels/cast.luau   (writes art/export/panels/cast.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../../src/config")

local function copy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in t do
		o[k] = copy(v)
	end
	return o
end

local PeopleLooks = require("../../src/shared/PeopleLooks")

local faces = Config.CatalogLooks.faces
local hairs = Config.CatalogLooks.hair
local function faceByName(n: string): any
	for _, f in faces do
		if f[1] == n then
			return { name = f[1], asset = f[2], image = f[3] }
		end
	end
	error("no catalog face " .. n)
end
local function beardByName(n: string): any
	for _, b in Config.CatalogLooks.beards do
		if b[1] == n then
			return { name = b[1], asset = b[2] }
		end
	end
	error("no catalog beard " .. n)
end
local function hairByName(n: string): any
	for _, h in hairs do
		if h[1] == n then
			return { name = h[1], asset = h[2] }
		end
	end
	error("no catalog hair " .. n)
end

-- people with no clothes upload and no look: a hero shirt and pants (art/export/clothes/heroes, white
-- templates tinted as the game tints them) in their colours
local OUTFIT = {
	patch = { shirt = "Hoodie", shirtTint = { 40, 150, 170 }, pants = "Cargo", pantsTint = { 70, 70, 80 } },
	crane = { shirt = "Blazer", shirtTint = { 245, 245, 240 }, pants = "Slacks", pantsTint = { 40, 40, 46 } },
	insider = { shirt = "Hoodie", shirtTint = { 60, 40, 80 }, pants = "Joggers", pantsTint = { 30, 30, 36 } },
	toymaker = { shirt = "Sweater", shirtTint = { 150, 60, 50 }, pants = "Chinos", pantsTint = { 90, 70, 50 } },
	lark = { shirt = "Bomber", shirtTint = { 230, 120, 40 }, pants = "Jeans", pantsTint = { 60, 80, 130 } },
	CaptainMeridian = { suit = { { 40, 70, 160 }, { 40, 70, 160 }, { 240, 200, 70 } } },
	OldBeacon = { shirt = "LeatherJacket", shirtTint = { 90, 110, 80 }, pants = "Cargo", pantsTint = { 70, 60, 50 } },
	TheMargrave = { shirt = "Blazer", shirtTint = { 50, 30, 70 }, pants = "Slacks", pantsTint = { 30, 24, 40 } },
	TheVelvetPaw = { suit = { { 120, 30, 60 }, { 40, 30, 40 }, { 40, 30, 40 } } },
	copy = { suit = { { 150, 152, 162 }, { 120, 122, 132 }, { 90, 92, 100 } } },
}
-- speakers whose clothes, look or face come from another config row (Shared.PeopleLooks.SPEAKERS)
local PEOPLE = PeopleLooks.SPEAKERS
-- the same portrait as another key (one render)
local ALIAS = { PatchRelay = "patch", LodestarGiver = "lodestar" }

local P = Config.Creator.palette
local function pal(i: number?): any
	return if i and i > 0 then copy(P[i]) else nil
end

local function lookOf(key: string, sp: any): any
	if sp and sp.look then
		return sp.look
	end
	if key == "lodestar" then
		return Config.Story.opening.lodestar.look
	end
	local pk = PEOPLE[key]
	if pk then
		local d = Config.SideQuests.dress[pk]
		if d and d.look then
			return d.look
		end
		local e = Config.Enemies[pk]
		if e and e.fake and e.fake.look then
			return e.fake.look
		end
	end
	return nil
end

local function person(key: string, sp: any, extra: any?): any
	local look = lookOf(key, sp)
	local pk = PEOPLE[key] or key
	local people = Config.NpcLooks.people[pk]
	local p = (sp and sp.portrait) or {}
	local row: any = {
		key = key,
		name = (sp and sp.name) or (extra and extra.name),
		color = copy((sp and sp.color) or (extra and extra.color)),
		bg = copy(p.bg or (extra and extra.bg)),
		shape = p.shape,
		extras = copy(p.extras or {}),
		style = sp and sp.style,
		people = if people and people.clothes ~= 0 then pk else nil,
		outfit = copy(OUTFIT[key]),
	}
	if look then
		row.look = copy(look)
		row.rgb = { pal(look.colors[1]), pal(look.colors[2]), pal(look.colors[3]) }
		local t = {}
		for slot, v in look.tints or {} do
			t[slot] = { pal(v[1]), pal(v[2]), pal(v[3]) }
		end
		row.tints = t
		row.skin = copy(Config.Creator.skins[look.skin] or p.skin)
	else
		row.skin = copy(p.skin or { 224, 172, 130 })
	end
	-- the explicit catalog pick (the look's catalog face and hair pieces, else Config.NpcLooks.cast)
	local faceName, hairName, err, beardName = PeopleLooks.catalogPick(Config, key)
	assert(faceName, err)
	row.face = faceByName(faceName)
	row.hair = if hairName then hairByName(hairName) else nil
	-- the catalog beard (gap-villains, 2026-11-19: Config.CatalogLooks.beards, a look's piece or the cast row's)
	row.beard = if beardName then beardByName(beardName) else nil
	return row
end

local portraits = {}
local keys = {}
for k in Config.Story.guides.speakers do
	table.insert(keys, k)
end
table.sort(keys)
for _, k in keys do
	table.insert(portraits, person(k, Config.Story.guides.speakers[k]))
end
keys = {}
for k in Config.SideQuests.givers do
	table.insert(keys, k)
end
table.sort(keys)
local aliases = {}
for _, k in keys do
	if ALIAS[k] then
		aliases[k] = ALIAS[k]
	elseif k ~= "SampleGiver" then -- the Dev panel's test giver keeps the drawn portrait
		table.insert(portraits, person(k, Config.SideQuests.givers[k]))
	end
end
for _, m in Config.Mentors.list do
	local c1, c2 = m.colors[1], m.colors[2]
	table.insert(
		portraits,
		person(m.id, nil, {
			name = string.upper(m.name),
			color = c2,
			bg = { math.floor(c1[1] * 0.6), math.floor(c1[2] * 0.6), math.floor(c1[3] * 0.6) },
		})
	)
end

local panels = {}
local ids = {}
for id in Config.Cinema.comic.pages do
	table.insert(ids, id)
end
table.sort(ids)
for _, id in ids do
	for i, p in Config.Cinema.comic.pages[id].panels do
		table.insert(panels, {
			page = id,
			index = i,
			key = id .. "." .. i,
			scene = p.scene,
			sky = copy(p.sky),
			ground = copy(p.ground),
			caption = p.caption,
			word = p.word,
			-- the panel's shape on a 16:9 screen (width / height)
			aspect = (p.rect[3] * 16) / (p.rect[4] * 9),
		})
	end
end

-- The side quest villains' name cards (gap-villains, 2026-11-19, nate): every name a finale's card shows
-- (SideQuestPlan.card: the chain's villain, or an encore finale's first foe) with the person who wears it, a
-- portrait key above, or a finale that is not a person (its own model, Config.FinaleArt). The Dev sample chain
-- keeps the text card.
local VILLAINS: { [string]: string } = {
	["HEADMASTER HALO"] = "halo",
	["REDLINE"] = "redline",
	["MADAME MASQUE-A-RADE"] = "masque",
	["THE TOYMAKER"] = "toymaker",
	["THE BRAMBLEBEAST"] = "finale:Bramblebeast",
	["THE HARVEST KING"] = "harvest",
	["CAPTAIN BRINE"] = "brine",
	["THE PITBOSS"] = "pitboss",
	["THE TIDEWRIGHT"] = "tidewright",
	["VESPER"] = "vesper",
	["CATCHPOLE"] = "catchpole",
	["SAL SCORCH"] = "scorch",
	["THE CENSOR"] = "censor",
	["DOCTOR HOLLOWAY"] = "holloway",
	["THE VOIDHOUND"] = "finale:Voidhound",
	["MORROW THE MIRAGE"] = "morrow",
	["CLAWBACK"] = "clawback",
	["GALE"] = "gale",
}
-- a finale's card colour (its look's own glow: the Bramblebeast's leaves, the Voidhound's violet)
local FINALE_COLOR = { Bramblebeast = { 90, 170, 70 }, Voidhound = { 150, 80, 230 } }
local byKey = {}
for _, r in portraits do
	byKey[r.key] = r
end
local villains, seen = {}, {}
local chainIds = {}
for id in Config.SideQuests.chains do
	table.insert(chainIds, id)
end
table.sort(chainIds, function(a, b)
	return tostring(a) < tostring(b)
end)
local function addVillain(name: string, title: string)
	if seen[name] then
		return
	end
	seen[name] = true
	local who = VILLAINS[name]
	assert(who, "no portrait for the villain card " .. name .. " (art/panels/cast.luau VILLAINS)")
	local fin = string.match(who, "^finale:(.+)$")
	if fin then
		local art = Config.FinaleArt[fin]
		assert(art, "no Config.FinaleArt " .. fin)
		table.insert(villains, { name = name, title = title, finale = fin, art = copy(art), color = copy(FINALE_COLOR[fin] or art.tint) })
	else
		local row = byKey[who]
		assert(row, "no portrait row " .. who)
		table.insert(villains, { name = name, title = title, key = who, color = copy(row.color) })
	end
end
for _, id in chainIds do
	local chain = Config.SideQuests.chains[id]
	if type(chain.villain) == "table" and not chain.dev then
		for _, step in chain.steps or {} do
			for _, side in { "hero", "villain" } do
				local g = step[side]
				if type(g) == "table" and g.kind == "finale" and g.encore and type(g.card) == "table" then
					addVillain(g.card.name, g.card.title)
				end
			end
		end
		addVillain(chain.villain.name, chain.villain.title)
	end
end
table.sort(villains, function(a, b)
	return a.name < b.name
end)

fs.writeDir("art/export/panels")
fs.writeFile(
	"art/export/panels/cast.json",
	serde.encode("json", { portraits = portraits, aliases = aliases, panels = panels, villains = villains }, true)
)
print(#portraits .. " portraits, " .. #panels .. " panels, " .. #villains .. " villain cards -> art/export/panels/cast.json")
