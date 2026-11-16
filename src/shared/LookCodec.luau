--!strict
-- LookCodec: a hero's look as a fixed-size record (spec: Hero creator "The creator saves a look as a
-- record and 4 looks can be saved"). Pure, so Lune tests it.
-- Version 2 (nate's hero creator plan, 2026-11-16) is 128 bytes:
--   byte 0       version (2; 0 = no look yet: the default look is used)
--   byte 1       flags: bit 0 the Anime effect style (else Comic)
--   byte 2       gender (1 Male, 2 Female)
--   byte 3       build (1 Small, 2 Medium, 3 Large, 4 Titan)
--   byte 4       height step (1 to 5, 3 = standard)
--   byte 5       skin (Config.Creator.skins, 1 to 30)
--   byte 6       hair colour, byte 7 eye colour (palette; eye colour 0 = the eyes piece's own)
--   bytes 8-10   the whole-hero primary, secondary and accent colour (palette 1 to 48)
--   bytes 11-19  reserved (0)
--   bytes 20-42  one piece per slot (LookCodec.SLOTS order), the piece's index in its tab, 0 = none
--   bytes 44-112 per slot main, trim and glow colour (palette; 0 = the whole-hero colour)
--   bytes 113-124 per slot material, a nibble each (0 = the piece's own; Config.Creator.materials)
--   bytes 125-127 reserved (0)
-- Version 1 records (32 bytes: flags, 11 pieces, 3 colours, hair, skin) still read: the first 11 slots
-- keep their order, so a saved v1 look reads with Male, Medium, standard height and no per-slot colours.
-- On the wire it is a buffer; in the save it is unsigned 32-bit words (DataStores store JSON).

local LookCodec = {}

LookCodec.VERSION = 2
LookCodec.SIZE = 128
LookCodec.WORDS = 32
LookCodec.V1_SIZE = 32
-- the first 11 are version 1's slots in version 1's order; never reorder, only append
LookCodec.SLOTS = {
	"suit", -- Top (a bodysuit also colours the legs while Legs is empty)
	"back", -- Cape
	"head", -- Mask
	"hands", -- Gloves
	"feet", -- Shoes
	"emblem", -- Symbol
	"aura",
	"trail",
	"voice",
	"hair",
	"eyes",
	"beard", -- Facial hair
	"face", -- mouth and brows
	"makeup", -- makeup and face paint
	"hat", -- Headwear
	"ears",
	"shoulders",
	"neck",
	"arms",
	"wrist", -- rings and bracelets
	"belt",
	"legs",
	"backpack", -- Back bling
}
local PIECES_AT, TINTS_AT, MATS_AT = 20, 44, 113

export type Tint = { number } -- main, trim, glow (0 = the whole-hero colour)

export type Look = {
	pieces: { [string]: number }, -- slot -> piece index in its tab (0 or missing = none)
	colors: { number }, -- primary, secondary, accent
	hair: number,
	skin: number,
	anime: boolean,
	gender: number,
	build: number,
	height: number,
	eyeColor: number,
	tints: { [string]: Tint }, -- slot -> its own colours (missing = all whole-hero)
	mats: { [string]: number }, -- slot -> material (missing or 0 = the piece's own)
}

local function byte(v: any, lo: number, hi: number, default: number): number
	if type(v) ~= "number" or v ~= v or v % 1 ~= 0 or v < lo or v > hi then
		return default
	end
	return v
end

function LookCodec.encode(look: Look): buffer
	local b = buffer.create(LookCodec.SIZE)
	buffer.writeu8(b, 0, LookCodec.VERSION)
	buffer.writeu8(b, 1, if look.anime then 1 else 0)
	buffer.writeu8(b, 2, byte(look.gender, 1, 2, 1))
	buffer.writeu8(b, 3, byte(look.build, 1, 4, 2))
	buffer.writeu8(b, 4, byte(look.height, 1, 5, 3))
	buffer.writeu8(b, 5, byte(look.skin, 1, 255, 1))
	buffer.writeu8(b, 6, byte(look.hair, 1, 255, 1))
	buffer.writeu8(b, 7, byte(look.eyeColor, 0, 255, 0))
	for i = 1, 3 do
		buffer.writeu8(b, 7 + i, byte(look.colors[i], 1, 255, 1))
	end
	local tints: { [string]: Tint } = look.tints or {}
	local mats: { [string]: number } = look.mats or {}
	for i, slot in LookCodec.SLOTS do
		buffer.writeu8(b, PIECES_AT + i - 1, byte(look.pieces[slot], 0, 255, 0))
		local t = tints[slot]
		for c = 1, 3 do
			buffer.writeu8(b, TINTS_AT + (i - 1) * 3 + c - 1, byte(t and t[c], 0, 255, 0))
		end
		local m = byte(mats[slot], 0, 15, 0)
		local at = MATS_AT + (i - 1) // 2
		local old = buffer.readu8(b, at)
		buffer.writeu8(
			b,
			at,
			if (i - 1) % 2 == 0 then bit32.bor(old, m) else bit32.bor(old, bit32.lshift(m, 4))
		)
	end
	return b
end

local function decodeV1(b: buffer): Look
	local pieces = {}
	for i = 1, 11 do
		pieces[LookCodec.SLOTS[i]] = buffer.readu8(b, 1 + i)
	end
	return {
		pieces = pieces,
		colors = { buffer.readu8(b, 13), buffer.readu8(b, 14), buffer.readu8(b, 15) },
		hair = buffer.readu8(b, 16),
		skin = buffer.readu8(b, 17),
		anime = bit32.btest(buffer.readu8(b, 1), 1),
		gender = 1,
		build = 2,
		height = 3,
		eyeColor = 0,
		tints = {},
		mats = {},
	}
end

-- nil when the record is not a look (wrong size, version 0 or an unknown version)
function LookCodec.decode(b: buffer): Look?
	local len = buffer.len(b)
	if len < LookCodec.V1_SIZE then
		return nil
	end
	local v = buffer.readu8(b, 0)
	if v == 1 then
		return decodeV1(b)
	elseif v ~= 2 or len ~= LookCodec.SIZE then
		return nil
	end
	local pieces, tints, mats = {}, {}, {}
	for i, slot in LookCodec.SLOTS do
		pieces[slot] = buffer.readu8(b, PIECES_AT + i - 1)
		local t = {}
		local any = false
		for c = 1, 3 do
			t[c] = buffer.readu8(b, TINTS_AT + (i - 1) * 3 + c - 1)
			any = any or t[c] ~= 0
		end
		if any then
			tints[slot] = t
		end
		local packed = buffer.readu8(b, MATS_AT + (i - 1) // 2)
		local m = if (i - 1) % 2 == 0 then bit32.band(packed, 15) else bit32.rshift(packed, 4)
		if m ~= 0 then
			mats[slot] = m
		end
	end
	return {
		pieces = pieces,
		colors = { buffer.readu8(b, 8), buffer.readu8(b, 9), buffer.readu8(b, 10) },
		hair = buffer.readu8(b, 6),
		skin = buffer.readu8(b, 5),
		anime = bit32.btest(buffer.readu8(b, 1), 1),
		gender = buffer.readu8(b, 2),
		build = buffer.readu8(b, 3),
		height = buffer.readu8(b, 4),
		eyeColor = buffer.readu8(b, 7),
		tints = tints,
		mats = mats,
	}
end

function LookCodec.toWords(b: buffer): { number }
	local n = buffer.len(b) // 4
	local out = table.create(n, 0)
	for i = 0, n - 1 do
		out[i + 1] = buffer.readu32(b, i * 4)
	end
	return out
end

-- Saved words to a buffer: 8 words (a version 1 record) or 32 (version 2); anything else is padded or cut
-- to 32 words, so a v1 record keeps its first 32 bytes and the rest is 0
function LookCodec.fromWords(words: { number }?): buffer
	local b = buffer.create(LookCodec.SIZE)
	if type(words) == "table" then
		for i = 0, LookCodec.WORDS - 1 do
			local w = words[i + 1]
			if type(w) == "number" and w == w and w >= 0 and w < 2 ^ 32 then
				buffer.writeu32(b, i * 4, w // 1)
			end
		end
	end
	return b
end

-- Words straight to a look (nil = no look saved)
function LookCodec.read(words: { number }?): Look?
	return LookCodec.decode(LookCodec.fromWords(words))
end

function LookCodec.write(look: Look): { number }
	return LookCodec.toWords(LookCodec.encode(look))
end

function LookCodec.copy(look: Look): Look
	local tints = {}
	local src: { [string]: Tint } = look.tints or {}
	for k, t in src do
		tints[k] = table.clone(t)
	end
	return {
		pieces = table.clone(look.pieces),
		colors = table.clone(look.colors),
		hair = look.hair,
		skin = look.skin,
		anime = look.anime,
		gender = look.gender or 1,
		build = look.build or 2,
		height = look.height or 3,
		eyeColor = look.eyeColor or 0,
		tints = tints,
		mats = table.clone(look.mats or {}),
	}
end

return LookCodec
