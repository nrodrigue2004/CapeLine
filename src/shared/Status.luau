--!strict
-- Status: timed effects on one target, as plain data (spec: ability effects, Resolve, PvP diminishing
-- returns). Enemies carry one in EnemySim; heroes carry one in HeroService for buffs.
-- Crowd control: stun (no moving or acting), root (no moving), slow (value = speed multiplier), knockup
-- and float (lifted, no acting), pull (moved toward x/y/z at `speed`), blind (shots go wide, no new
-- targets), taunt (must target `src`).
-- Buffs: shield (value = points left), mitigation, attackSpeed, power, speed, parry, resist.
-- A stronger or longer apply replaces a weaker one; it never shortens what is already there.

local Status = {}

export type Entry = {
	untilT: number,
	startT: number,
	value: number,
	x: number?,
	y: number?,
	z: number?,
	speed: number?,
	src: number?,
}

export type Book = {
	list: { [string]: Entry },
	dr: { [string]: { count: number, last: number, immuneUntil: number } },
}

-- Bits for the Enemy.Delta flags byte (the client draws these)
Status.BITS = {
	stun = 1,
	root = 2,
	slow = 4,
	lifted = 8, -- knockup or float
	cloak = 16,
	windup = 32,
	shield = 64,
	guardBroken = 128,
}

local CC = { stun = true, root = true, slow = true, knockup = true, float = true, pull = true, blind = true }
Status.CC = CC
local HARD = { stun = true, root = true } -- the ones with PvP diminishing returns

function Status.new(): Book
	return { list = {}, dr = {} }
end

export type ApplyOpts = {
	value: number?,
	x: number?,
	y: number?,
	z: number?,
	speed: number?,
	src: number?,
	resist: number?, -- 0..1 shortens crowd control (enemy ccResist, hero Resolve)
	pvp: boolean?, -- PvP: stuns and roots halve on each repeat within 8 s, then 3 s immune
	immune: { string }?,
}

-- Returns the duration actually applied (0 when resisted or immune)
function Status.apply(book: Book, kind: string, duration: number, now: number, opts: ApplyOpts?): number
	local o: ApplyOpts = opts or {}
	if o.immune and table.find(o.immune, kind) then
		return 0
	end
	local dur = duration
	if CC[kind] and o.resist then
		dur *= 1 - math.clamp(o.resist, 0, 0.9)
	end
	if o.pvp and HARD[kind] then
		local d = book.dr[kind]
		if d and now < d.immuneUntil then
			return 0
		end
		if d and now - d.last <= 8 then
			d.count += 1
		else
			d = { count = 0, last = now, immuneUntil = 0 }
			book.dr[kind] = d
		end
		local dd = d :: any
		dur *= 0.5 ^ dd.count
		dd.last = now
		dd.immuneUntil = now + dur + 3
	end
	if dur <= 0 then
		return 0
	end
	local value = o.value or 1
	local cur = book.list[kind]
	if cur and cur.untilT > now then
		-- keep the stronger effect; extend if the new one runs longer
		local stronger = if kind == "slow" then value < cur.value else value > cur.value
		if stronger then
			cur.value = value
		end
		if now + dur > cur.untilT then
			cur.untilT = now + dur
		end
		if o.x then
			cur.x, cur.y, cur.z, cur.speed = o.x, o.y, o.z, o.speed
		end
		if o.src then
			cur.src = o.src
		end
		return dur
	end
	book.list[kind] = {
		untilT = now + dur,
		startT = now,
		value = value,
		x = o.x,
		y = o.y,
		z = o.z,
		speed = o.speed,
		src = o.src,
	}
	return dur
end

function Status.get(book: Book, kind: string, now: number): Entry?
	local e = book.list[kind]
	if e and e.untilT > now then
		return e
	end
	return nil
end

function Status.has(book: Book, kind: string, now: number): boolean
	return Status.get(book, kind, now) ~= nil
end

function Status.value(book: Book, kind: string, now: number, default: number): number
	local e = Status.get(book, kind, now)
	return if e then e.value else default
end

function Status.remove(book: Book, kind: string)
	book.list[kind] = nil
end

function Status.lifted(book: Book, now: number): boolean
	return Status.has(book, "knockup", now) or Status.has(book, "float", now)
end

function Status.canMove(book: Book, now: number): boolean
	return not (Status.has(book, "stun", now) or Status.has(book, "root", now) or Status.lifted(book, now))
end

function Status.canAct(book: Book, now: number): boolean
	return not (Status.has(book, "stun", now) or Status.lifted(book, now))
end

-- Speed multiplier from slows (the strongest one wins)
function Status.speedMult(book: Book, now: number): number
	return Status.value(book, "slow", now, 1)
end

-- Height above the resting point for knockup (an arc) and float (rise, hold, drop)
function Status.liftHeight(book: Book, now: number, knockupHeight: number, floatHeight: number): number
	local k = Status.get(book, "knockup", now)
	if k then
		local t = (now - k.startT) / math.max(0.05, k.untilT - k.startT)
		return knockupHeight * math.sin(math.pi * math.clamp(t, 0, 1))
	end
	local f = Status.get(book, "float", now)
	if f then
		local up = math.clamp((now - f.startT) / 0.4, 0, 1)
		local down = math.clamp((f.untilT - now) / 0.25, 0, 1)
		return floatHeight * math.min(up, down)
	end
	return 0
end

-- Absorb damage with the shield. Returns what gets through.
function Status.absorb(book: Book, amount: number, now: number): number
	local s = Status.get(book, "shield", now)
	if not s or s.value <= 0 then
		return amount
	end
	local taken = math.min(s.value, amount)
	s.value -= taken
	if s.value <= 0 then
		book.list.shield = nil
	end
	return amount - taken
end

-- Bits for the wire (see Status.BITS); cloak, windup, shield and guard come from the AI, not here
function Status.flags(book: Book, now: number): number
	local f = 0
	if Status.has(book, "stun", now) then
		f += Status.BITS.stun
	end
	if Status.has(book, "root", now) then
		f += Status.BITS.root
	end
	if Status.has(book, "slow", now) then
		f += Status.BITS.slow
	end
	if Status.lifted(book, now) then
		f += Status.BITS.lifted
	end
	return f
end

-- Drop expired entries; returns the kinds that ended (for end-of-effect hits such as Float's Drop)
function Status.clean(book: Book, now: number): { string }?
	local ended: { string }? = nil
	for kind, e in book.list do
		if e.untilT <= now then
			book.list[kind] = nil
			ended = ended or {}
			table.insert(ended :: { string }, kind)
		end
	end
	return ended
end

return Status
