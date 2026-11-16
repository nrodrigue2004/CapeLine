--!strict
-- Cooldowns: the server owns every cooldown, with 100 ms of leeway for lag (spec: Anti-exploit > Cooldowns).
-- The client keeps its own copy only to draw the sweeps.

local Cooldowns = {}

export type Book = { readyAt: { [string]: number } }

function Cooldowns.new(): Book
	return { readyAt = {} }
end

function Cooldowns.ready(book: Book, id: string, now: number, leeway: number): boolean
	local at = book.readyAt[id]
	return at == nil or now + leeway >= at
end

function Cooldowns.start(book: Book, id: string, now: number, seconds: number)
	book.readyAt[id] = now + seconds
end

-- 0 when ready, 1 right after use (for the sweep)
function Cooldowns.fraction(book: Book, id: string, now: number, seconds: number): number
	local at = book.readyAt[id]
	if not at or seconds <= 0 then
		return 0
	end
	return math.clamp((at - now) / seconds, 0, 1)
end

function Cooldowns.clear(book: Book)
	table.clear(book.readyAt)
end

return Cooldowns
