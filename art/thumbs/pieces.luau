-- pieces.luau: the list of every picture tile the game shows (creator pieces, weapons, shop items) for the
-- thumbnail pipeline (2026-11-19). art/thumbs/thumbs.py reads it to know which cells to draw and pack, and
-- art/blender/clothed.py thumbs reads the Legs tab's part specs from it (the legs are body paint and parts, no
-- meshes). Shared.ThumbMap names each tile's key the same way (tests check both agree).
-- Run from the repo root: lune run art/thumbs/pieces.luau   (writes art/thumbs/pieces.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Config = require("../../src/config")
local CreatorRules = require("../../src/shared/CreatorRules")
local TravelStyleRules = require("../../src/shared/TravelStyleRules")
local ThumbMap = require("../../src/shared/ThumbMap")

local PieceKits = luau.load(fs.readFile("src/shared/PieceKits.luau"), {
	debugName = "PieceKits",
	environment = { Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Enum = roblox.Enum },
})()

local out = {
	creator = {},
	legs = {},
	weapons = {},
	travel = {},
	tints = {},
	emotes = {},
	packs = {},
	shop = {},
	auras = Config.Creator.auraFx.kits,
}

-- every offered creator piece: its tile key (nil for a catalog piece: those show the catalog's own image)
for _, p in CreatorRules.index(Config).list do
	if CreatorRules.offered(Config, p) then
		table.insert(out.creator, {
			tab = p.tab,
			kit = p.kit,
			name = p.name,
			key = ThumbMap.creatorKey(Config, p),
		})
	end
end

-- the Legs tab's specs: paint (upper and lower leg colour roles) and parts (body part role, size, CFrame
-- components in the part's frame, colour role, neon)
for kit, spec in PieceKits.legs do
	local parts = {}
	for _, s in spec.parts or {} do
		table.insert(parts, {
			at = s.at,
			size = { s.size.X, s.size.Y, s.size.Z },
			cf = { s.cf:GetComponents() },
			color = s.color,
			neon = s.neon == true,
			shape = s.shape,
		})
	end
	out.legs[kit] = { paint = spec.paint, parts = parts }
end

for _, w in Config.Weapons.list do
	table.insert(out.weapons, { id = w[1], name = w[3], key = ThumbMap.weaponKey(w[1]) })
end

for _, s in TravelStyleRules.list(Config) do
	table.insert(out.travel, {
		id = s.id,
		name = s.name,
		mobility = s.mobility,
		c1 = s.c1,
		c2 = s.c2,
		burst = s.burst,
		glow = s.glow,
	})
end

for i, t in Config.Shop.tints do
	table.insert(out.tints, { i = i, name = t.name, color = t.color, glow = t.glow, rainbow = t.rainbow == true })
end
for i, e in Config.Shop.emotes do
	out.emotes[tostring(i)] = { name = e.name, landing = e.landing == true }
end
for i, pk in Config.Shop.packs do
	local pieces = {}
	for _, p in CreatorRules.packPieces(Config, i) do
		table.insert(pieces, { tab = p.tab, kit = p.kit, key = ThumbMap.creatorKey(Config, p) })
	end
	table.insert(out.packs, { i = i, name = pk.name, color = pk.color, pieces = pieces })
end

-- every shop item in shop order: its key, kind and what it names (pack, tint, travel style, weapon, emote)
for _, tab in Config.Shop.tabs do
	for _, key in tab.items do
		local row = Config.Shop.products[key] or {}
		table.insert(out.shop, {
			key = key,
			tab = tab.id,
			kind = row.kind or (if Config.Shop.passes[key] then "pass" else nil),
			pack = row.pack,
			tint = row.tint,
			style = row.style,
			weapon = row.weapon,
			emote = row.emote,
		})
	end
end

fs.writeFile("art/thumbs/pieces.json", serde.encode("json", out, true))
print(string.format("wrote art/thumbs/pieces.json: %d creator pieces", #out.creator))
