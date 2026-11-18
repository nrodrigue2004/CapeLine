-- pages.luau: writes the Rogues File's 45 pages (Shared.RoguesFile over Config.Rogues) as JSON for the portrait
-- pipeline: art/blender/rogues.py renders each page's figure from the game's own look and art/rogues/portraits.py
-- draws the case-file portraits. Each row: the page's bit, group, id, name, title, the Config.Enemies kind and
-- its body (colours and gear flags: the parts EnemyRenderer adds), the creator look it wears (a dress's or a
-- fake's: pieces and colours) and its Config.NpcLooks.people key, a finale's own model (Config.FinaleArt) and a
-- world boss's (Config.BossArt).
-- Run from the repo root: lune run art/rogues/pages.luau   (writes art/export/rogues/pages.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../../src/config")
local RoguesFile = require("../../src/shared/RoguesFile")

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

local P = Config.Creator.palette
local function pal(i: number?): any
	return if i and i > 0 then copy(P[i]) else nil
end
local function tints(look: any): any
	local o = {}
	for slot, t in look.tints or {} do
		o[slot] = { pal(t[1]), pal(t[2]), pal(t[3]) }
	end
	return o
end

local out = {}
for _, e in RoguesFile.list(Config) do
	local def = e.kind and Config.Enemies[e.kind]
	local dress = e.dress and Config.SideQuests.dress[e.dress]
	-- the creator look it wears: a dress's, else a costumed villain's or famous fake's own (fake.look)
	local look = (dress and dress.look) or (def and def.fake and def.fake.look)
	local finKey = e.dress or e.kind
	local fin = finKey and Config.FinaleArt[finKey]
	local person = nil
	for _, key in { e.dress, e.id, e.kind } do
		if key and Config.NpcLooks.people[key] then
			person = key
			break
		end
	end
	table.insert(out, {
		bit = e.bit,
		gold = e.gold,
		group = e.group,
		id = e.id,
		name = e.name,
		title = e.title,
		kind = e.kind,
		dress = e.dress,
		boss = e.boss,
		person = person,
		colors = copy(e.colors),
		body = def and copy(def.body),
		look = look and copy(look),
		-- the look's primary, secondary and accent colours, and each tinted slot's colours, as RGB
		rgb = look and { pal(look.colors[1]), pal(look.colors[2]), pal(look.colors[3]) },
		tints = look and tints(look),
		dressBody = dress and copy(dress.body),
		height = dress and dress.height,
		-- a finale with its own model (Config.FinaleArt, keyed by the dress, else the kind: as EnemyRenderer)
		finaleName = if fin then finKey else nil,
		finaleArt = fin and copy(fin),
		-- a world boss's model (Config.BossArt) and the weak points' gold
		bossArt = e.boss and copy(Config.BossArt[e.boss]),
		weakColor = e.boss and copy(Config.BossArt.weakColor[1]),
	})
end
fs.writeDir("art/export/rogues")
fs.writeFile("art/export/rogues/pages.json", serde.encode("json", out, true))
print(#out .. " pages -> art/export/rogues/pages.json")
