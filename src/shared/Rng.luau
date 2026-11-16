--!strict
-- Rng: a small seeded random generator (xorshift32) that gives the same numbers in Roblox and in Lune
-- tests, so a seed builds the same city on every server (spec: Procedural outskirts). Never use
-- math.random for anything a seed must repeat.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

-- Mix any number of integers into one 32-bit seed (order matters)
function Rng.hash(...: number): number
	local h = 0x811C9DC5
	for i = 1, select("#", ...) do
		local value = math.floor(select(i, ...)) % 4294967296
		for _ = 1, 4 do
			h = bit32.bxor(h, bit32.band(value, 0xFF))
			-- h * 16777619 mod 2^32 without overflowing doubles: split the multiply
			local lo = bit32.band(h, 0xFFFF) * 16777619
			local hi = bit32.rshift(h, 16) * 16777619
			h = (lo + (hi % 65536) * 65536) % 4294967296
			value = bit32.rshift(value, 8)
		end
	end
	if h == 0 then
		h = 0x9E3779B9
	end
	return h
end

function Rng.new(seed: number): Rng
	local state = Rng.hash(seed)
	local self = setmetatable({ state = state }, Rng)
	-- warm up so close seeds diverge
	for _ = 1, 4 do
		self:nextInt32()
	end
	return self
end

function Rng.nextInt32(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Float in [0, 1)
function Rng.next(self: Rng): number
	return self:nextInt32() / 4294967296
end

-- Integer in [lo, hi]
function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng.range(self: Rng, lo: number, hi: number): number
	return lo + self:next() * (hi - lo)
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

-- Pick a key from { key = weight } using a fixed key order (tables have no stable order)
function Rng.weighted(self: Rng, order: { string }, weights: { [string]: number }): string?
	local total = 0
	for _, key in order do
		total += math.max(0, weights[key] or 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = self:next() * total
	for _, key in order do
		local w = math.max(0, weights[key] or 0)
		if roll < w then
			return key
		end
		roll -= w
	end
	return order[#order]
end

-- Fisher-Yates shuffle in place
function Rng.shuffle<T>(self: Rng, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Rng
