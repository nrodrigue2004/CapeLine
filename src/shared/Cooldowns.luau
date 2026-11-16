--!strict
-- Cooldowns: the server owns every cooldown, with 100 ms of leeway for lag (spec: Anti-exploit > Cooldowns).
-- The client keeps its own copy only to draw the sweeps.

local Cooldowns = {}

export type Book = { readyAt: { [string]: number }, length: { [string]: number } }

function Cooldowns.new(): Book
	return { readyAt = {}, length = {} }
end

function Cooldowns.ready(book: Book, id: string, now: number, leeway: number): boolean
	local at = book.readyAt[id]
	return at == nil or now + leeway >= at
end

function Cooldowns.start(book: Book, id: string, now: number, seconds: number)
	book.readyAt[id] = now + seconds
	book.length[id] = seconds
end

-- Seconds left (0 when ready)
function Cooldowns.left(book: Book, id: string, now: number): number
	local at = book.readyAt[id]
	return if at then math.max(0, at - now) else 0
end

-- Take seconds off a running cooldown (refunds)
function Cooldowns.reduce(book: Book, id: string, seconds: number)
	local at = book.readyAt[id]
	if at then
		book.readyAt[id] = at - seconds
	end
end

-- 0 when ready, 1 right after use (for the sweep). `seconds` defaults to the length it was started with.
function Cooldowns.fraction(book: Book, id: string, now: number, seconds: number?): number
	local at = book.readyAt[id]
	local len = seconds or book.length[id]
	if not at or not len or len <= 0 then
		return 0
	end
	return math.clamp((at - now) / len, 0, 1)
end

function Cooldowns.clear(book: Book)
	table.clear(book.readyAt)
	table.clear(book.length)
end

return Cooldowns
