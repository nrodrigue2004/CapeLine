--!strict
-- LookCodec: a hero's look as a 32-byte record (spec: Hero creator "The creator saves a look as a 32-byte
-- record and 4 looks can be saved"). Pure, so Lune tests it.
--   byte 0      version (1; 0 = no look yet: the default look is used)
--   byte 1      flags: bit 0 the Anime effect style (else Comic)
--   bytes 2-12  one piece per creator tab (LookCodec.SLOTS order), the piece's index in its tab, 0 = none
--   bytes 13-15 primary, secondary and accent colour (palette 1 to 24)
--   byte 16     hair colour (palette 1 to 24; nate's anime addition)
--   byte 17     skin tone (1 to 8)
--   bytes 18-31 reserved (0)
-- On the wire it is a buffer; in the save it is 8 unsigned 32-bit words (DataStores store JSON).

local LookCodec = {}

LookCodec.VERSION = 1
LookCodec.SIZE = 32
LookCodec.WORDS = 8
LookCodec.SLOTS =
	{ "suit", "back", "head", "hands", "feet", "emblem", "aura", "trail", "voice", "hair", "eyes" }

export type Look = {
	pieces: { [string]: number }, -- slot -> piece index in its tab (0 or missing = none)
	colors: { number }, -- primary, secondary, accent
	hair: number,
	skin: number,
	anime: boolean,
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
	for i, slot in LookCodec.SLOTS do
		buffer.writeu8(b, 1 + i, byte(look.pieces[slot], 0, 255, 0))
	end
	for i = 1, 3 do
		buffer.writeu8(b, 12 + i, byte(look.colors[i], 1, 24, 1))
	end
	buffer.writeu8(b, 16, byte(look.hair, 1, 24, 1))
	buffer.writeu8(b, 17, byte(look.skin, 1, 8, 1))
	return b
end

-- nil when the record is not a look (wrong size or version 0)
function LookCodec.decode(b: buffer): Look?
	if buffer.len(b) ~= LookCodec.SIZE or buffer.readu8(b, 0) == 0 then
		return nil
	end
	local pieces = {}
	for i, slot in LookCodec.SLOTS do
		pieces[slot] = buffer.readu8(b, 1 + i)
	end
	return {
		pieces = pieces,
		colors = { buffer.readu8(b, 13), buffer.readu8(b, 14), buffer.readu8(b, 15) },
		hair = buffer.readu8(b, 16),
		skin = buffer.readu8(b, 17),
		anime = bit32.btest(buffer.readu8(b, 1), 1),
	}
end

function LookCodec.toWords(b: buffer): { number }
	local out = table.create(LookCodec.WORDS, 0)
	for i = 0, LookCodec.WORDS - 1 do
		out[i + 1] = buffer.readu32(b, i * 4)
	end
	return out
end

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
	return {
		pieces = table.clone(look.pieces),
		colors = table.clone(look.colors),
		hair = look.hair,
		skin = look.skin,
		anime = look.anime,
	}
end

return LookCodec
