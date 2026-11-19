-- cast.luau: the comic art pass's cast and pages as JSON for art/blender/panels.py (2026-11-19). Every guide
-- portrait (Config.Story.guides.speakers and the side quest givers, Config.SideQuests.givers) and every mentor
-- (Config.Mentors.list) as a person to stage on Roblox's blocky R15 body: their game outfit (the uploaded classic
-- clothes, Config.NpcLooks.people, else the creator look's colours, else a picked shirt and pants), their creator
-- pieces that show (hats, masks, capes), a Roblox catalog face and catalog hair (nate's hard rule: faces, hair,
-- facial hair and eyes only from the catalog). A person with a creator look wears the catalog face and hair the
-- game itself gives that look (Shared.LookKit catalogFaceFor / catalogHairFor: picked by the old piece's name);
-- a person with no look wears the pick in FACE and HAIR below (recorded in notes/Decisions.md 2026-11-19).
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

-- the same pick as Shared.LookKit (nameHash, catalogFaceFor, catalogHairFor)
local function nameHash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end
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
local function hairByName(n: string): any
	for _, h in hairs do
		if h[1] == n then
			return { name = h[1], asset = h[2] }
		end
	end
	error("no catalog hair " .. n)
end
local function faceFor(kit: string): any
	local id = tonumber(string.match(kit, "^cat:(%d+)$"))
	for _, f in faces do
		if f[2] == id then
			return faceByName(f[1])
		end
	end
	local f = faces[nameHash(kit) % #faces + 1]
	return faceByName(f[1])
end
local function hairFor(kit: string): any
	local id = tonumber(string.match(kit, "^cat:(%d+)$"))
	for _, h in hairs do
		if h[2] == id then
			return hairByName(h[1])
		end
	end
	local h = hairs[nameHash(kit) % #hairs + 1]
	return hairByName(h[1])
end

-- the catalog face for each person with no creator look (picked for the character; Decisions 2026-11-19)
local FACE = {
	patch = "Check It", -- the Vigil's hacker kid: quick and cocky
	crane = "Know-It-All Grin", -- the smiling CEO on every screen
	insider = "Stare", -- a voice in a hood
	copy = "Sinister", -- your robot copy
	toymaker = "Glee", -- the toy shop's old inventor
	lark = "Bandage", -- the flyer from the Spark Pound
	wren = "Smiling Girl",
	toby = "Happy D",
	flint = "Beast Mode",
	finn = "Joyful Smile",
	dace = "Chill",
	ambrose = "Tired Face",
	hoshi = "Alright",
	CaptainMeridian = "Man Face",
	OldBeacon = "Friendly Grin",
	TheMargrave = "Take Over the World",
	TheVelvetPaw = "Slickfang",
}
-- catalog hair for each person with no creator look (nil: a hood, helmet or hat covers the head)
local HAIR = {
	patch = "Pal Hair",
	crane = "Brown Charmer Hair",
	copy = "Black Short Wolf Cut",
	toymaker = "Lavender Updo",
	lark = "Blonde Action Ponytail",
	wren = "Black Ponytail",
	toby = "Cinnamon Hair",
	flint = "Crimson Shaggy 2.0",
	finn = "Blonde Spiked Hair",
	dace = "Short Blue Hair",
	ambrose = "Long Pastel Hair",
	hoshi = "Black Royal Braid",
	CaptainMeridian = "Clean Shiny Spikes",
	OldBeacon = "Hair Base In Brown",
	TheMargrave = "Purple and Blue Male Hair Slick",
	TheVelvetPaw = "Black Trendy Messy Buns",
}
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
-- speakers whose clothes, look or face come from another config row
local PEOPLE = {
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
	LodestarGiver = nil,
}
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
	local pieces = look and look.pieces or {}
	row.face = if FACE[key] then faceByName(FACE[key]) elseif pieces.visage then faceFor(pieces.visage) else nil
	row.hair = if HAIR[key] then hairByName(HAIR[key]) elseif pieces.hair then hairFor(pieces.hair) else nil
	if not row.face then
		-- a look with no visage piece (a masked or machine look): the catalog face its name picks
		row.face = faceFor(key)
		row.facePicked = true
	end
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

fs.writeDir("art/export/panels")
fs.writeFile(
	"art/export/panels/cast.json",
	serde.encode("json", { portraits = portraits, aliases = aliases, panels = panels }, true)
)
print(#portraits .. " portraits, " .. #panels .. " panels -> art/export/panels/cast.json")
