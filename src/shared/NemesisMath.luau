--!strict
-- NemesisMath: your nemesis (spec: Hero MMO features > Nemesis; H5). Pure, so NemesisService, the client
-- (NemesisHud, NemesisFx) and the Lune tests agree:
--   who it is (built from your user id, rank and side: the same on every server), when it may show up,
--   how it grows (a trait per escape and per Down, up to 5), Intel and the Showdown, its health, its taunts
--   (fixed lines with your hero name, no free text) and the areas its signature attacks hit.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local NemesisMath = {}

export type Who = {
	seed: number,
	name: string,
	build: string,
	colors: number,
	head: string,
	cape: boolean,
	pitch: number,
	signature: string,
	order: { number }, -- the order its traits come in
}

export type Saved = { seed: number, rank: number, traits: number, met: number, intel: number, readyAt: number }

function NemesisMath.seed(userId: number, rank: number, side: string): number
	return Rng.hash(userId, rank, if side == "villain" then 2 else 1, 7331)
end

-- Its name from the two word lists (a villain's is a League hunter: "Hunter" in front)
function NemesisMath.name(N: any, seed: number, side: string): string
	local rng = Rng.new(Rng.hash(seed, 1))
	local a = N.first[rng:int(1, #N.first)]
	local b = N.second[rng:int(1, #N.second)]
	if a == b then
		b = N.second[(table.find(N.second, b) :: number) % #N.second + 1]
	end
	local base = a .. " " .. b
	return if side == "villain" then N.hunterWord .. " " .. base else base
end

function NemesisMath.make(N: any, userId: number, rank: number, side: string): Who
	local seed = NemesisMath.seed(userId, rank, side)
	local rng = Rng.new(seed)
	local order = { 1, 2, 3, 4, 5 }
	for i = #order, 2, -1 do
		local j = rng:int(1, i)
		order[i], order[j] = order[j], order[i]
	end
	return {
		seed = seed,
		name = NemesisMath.name(N, seed, side),
		build = N.builds[rng:int(1, #N.builds)],
		colors = rng:int(1, #N.colors),
		head = N.heads[rng:int(1, #N.heads)],
		cape = rng:next() < N.capeChance,
		pitch = N.pitch[1] + (N.pitch[2] - N.pitch[1]) * rng:next(),
		signature = N.signatureOrder[rng:int(1, #N.signatureOrder)],
		order = order,
	}
end

function NemesisMath.fresh(_N: any, userId: number, side: string, rank: number?, readyAt: number?): Saved
	local r = rank or 1
	return {
		seed = NemesisMath.seed(userId, r, side),
		rank = r,
		traits = 0,
		met = 0,
		intel = 0,
		readyAt = readyAt or 0,
	}
end

function NemesisMath.hasTrait(bits: number, index: number): boolean
	return bit32.btest(bits, bit32.lshift(1, index - 1))
end

function NemesisMath.traitCount(bits: number): number
	local n = 0
	for i = 1, 5 do
		if NemesisMath.hasTrait(bits, i) then
			n += 1
		end
	end
	return n
end

-- The next trait it gains (its own order), or nil at 5
function NemesisMath.nextTrait(who: Who, bits: number): number?
	for _, i in who.order do
		if not NemesisMath.hasTrait(bits, i) then
			return i
		end
	end
	return nil
end

-- Escape or Down: gain the next trait (never past maxTraits). Returns the trait gained.
function NemesisMath.grow(N: any, who: Who, st: Saved): number?
	if NemesisMath.traitCount(st.traits) >= N.maxTraits then
		return nil
	end
	local t = NemesisMath.nextTrait(who, st.traits)
	if t then
		st.traits = bit32.bor(st.traits, bit32.lshift(1, t - 1))
	end
	return t
end

-- Does this encounter (met counts it) end in an escape at 30%?
function NemesisMath.escapes(N: any, met: number): boolean
	return met <= N.escapesUntil
end

-- An escape: a trait and an Intel
function NemesisMath.escaped(N: any, who: Who, st: Saved): number?
	st.intel = math.min(N.intelForShowdown, st.intel + 1)
	return NemesisMath.grow(N, who, st)
end

function NemesisMath.showdownOpen(N: any, st: Saved): boolean
	return st.intel >= N.intelForShowdown
end

-- After a Showdown win: a new nemesis one rank tougher (up to 5), a day later
function NemesisMath.afterWin(N: any, st: Saved, userId: number, side: string, now: number): Saved
	local rank = math.min(N.maxRank, st.rank + 1)
	return NemesisMath.fresh(N, userId, side, rank, now + N.rankUpWait)
end

export type When = {
	level: number,
	session: number, -- seconds into this session
	since: number, -- seconds of play since the last encounter (math.huge if none)
	now: number, -- os.time()
	readyAt: number,
	intel: number,
	inPocket: boolean,
	inSafehouse: boolean,
	inCrater: boolean,
	bossFight: boolean,
}

-- May it show up now? (reason when not)
function NemesisMath.canAppear(N: any, w: When): (boolean, string?)
	if w.level < N.minLevel then
		return false, "level"
	elseif w.session < N.sessionMin then
		return false, "session"
	elseif w.since < N.gap then
		return false, "gap"
	elseif w.now < w.readyAt then
		return false, "waiting"
	elseif w.intel >= N.intelForShowdown then
		return false, "showdown" -- it waits for the Showdown now
	elseif w.inPocket or w.inSafehouse or w.inCrater or w.bossFight then
		return false, "place"
	end
	return true, nil
end

-- Its health multiplier on its Brute Bot body: 12x a Trooper solo, 18x in a squad, more per rank
function NemesisMath.hpMult(N: any, squad: boolean, rank: number): number
	return (if squad then N.hpMult.squad else N.hpMult.solo) * (1 + N.rankHp * (rank - 1))
end

-- Its signature attacks: its own, plus a second once it has the Second Signature trait
function NemesisMath.signatures(N: any, who: Who, bits: number): { string }
	local list = { who.signature }
	local second = 0
	for i, t in N.traits do
		if t.id == "second" then
			second = i
		end
	end
	if second > 0 and NemesisMath.hasTrait(bits, second) then
		local i = table.find(N.signatureOrder, who.signature) :: number
		table.insert(list, N.signatureOrder[i % #N.signatureOrder + 1])
	end
	return list
end

-- A taunt, gloat or escape line with the hero's name in it (fixed lines only)
function NemesisMath.line(N: any, kind: string, seed: number, n: number, hero: string): string
	local list = if kind == "gloat" then N.gloats elseif kind == "escape" then N.escapes else N.taunts
	local i = Rng.hash(seed, n, #kind) % #list + 1
	local text = string.gsub(list[i], "{hero}", hero)
	return text
end

export type Area = { shape: string, x: number, z: number, r: number, dx: number?, dz: number?, length: number? }

-- Where a signature lands: from the nemesis at (nx, nz) aimed at its target (tx, tz)
function NemesisMath.areas(
	N: any,
	sig: string,
	nx: number,
	nz: number,
	tx: number,
	tz: number,
	seed: number
): { Area }
	local S = N.signatures[sig]
	local dx, dz = tx - nx, tz - nz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1e-3 then
		dx, dz, d = 0, -1, 1
	end
	dx, dz = dx / d, dz / d
	if S.shape == "line" then
		return { { shape = "line", x = nx, z = nz, r = S.width / 2, dx = dx, dz = dz, length = S.length } }
	elseif S.shape == "nova" then
		return { { shape = "nova", x = nx, z = nz, r = S.radius } }
	elseif S.shape == "ring" then
		return { { shape = "nova", x = tx, z = tz, r = S.radius } }
	elseif S.shape == "cone" then
		return { { shape = "cone", x = nx, z = nz, r = S.radius, dx = dx, dz = dz, length = S.cone } }
	end
	-- mines: around the target
	local rng = Rng.new(seed)
	local out = {}
	for _ = 1, S.count do
		local a = rng:next() * math.pi * 2
		local r = rng:next() * S.spread
		table.insert(
			out,
			{ shape = "nova", x = tx + math.cos(a) * r, z = tz + math.sin(a) * r, r = S.radius }
		)
	end
	return out
end

function NemesisMath.inArea(a: Area, x: number, z: number): boolean
	local px, pz = x - a.x, z - a.z
	if a.shape == "nova" then
		return px * px + pz * pz <= a.r * a.r
	end
	local dx, dz = a.dx or 0, a.dz or -1
	local along = px * dx + pz * dz
	if a.shape == "line" then
		local across = math.abs(px * -dz + pz * dx)
		return along >= 0 and along <= (a.length or 0) and across <= a.r
	end
	-- cone: within r, within half the cone angle (degrees in `length`)
	local dist = math.sqrt(px * px + pz * pz)
	if dist > a.r then
		return false
	end
	if dist < 1e-3 then
		return true
	end
	return math.deg(math.acos(math.clamp(along / dist, -1, 1))) <= (a.length or 90) / 2
end

return NemesisMath
