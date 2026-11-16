--!strict
-- BuildingState: the server's only record of destruction (spec: Destruction "The server stores only the
-- state"; State packing "2 bits per building, 55 bytes for the hub"; Repair; Collapses at once).
-- * hit(id, dmg, now): structure HP down; Damaged at 40% lost, Collapsed at 100%. A collapse while 3 others
--   started in the last 6 s is cut to Damaged (HP stays at 1 so a later hit can finish it).
-- * force(id, now): a knockback through a wall turns it Damaged at once.
-- * Repair: 3 drones per district each take the building that has been quiet longest (Damaged for 180 s,
--   Collapsed for 240 s) and spend 20 s on it.
-- * pack/unpack: 2 bits a building (0 Intact, 1 Damaged, 2 Collapsed); diffs batch the changes since the last
--   send.

-- * blast / punch (Red Faction-style, nate 2026-11-16): a hit knocks pieces out of the building's Structure
--   grid and whatever loses its support falls. Damaged = any piece gone; Collapsed = the ground storey gave
--   way. Structure HP follows the share of weight lost. The pieces gone are sent as diffs and in the
--   snapshot (one bit a piece), so every device shows the same holes. hit() and force() are the older
--   HP-only path, kept for callers without a position.

local Structure = if script then require(script.Parent.Structure) else (require :: any)("./Structure")

local BuildingState = {}

BuildingState.INTACT = 0
BuildingState.DAMAGED = 1
BuildingState.COLLAPSED = 2

export type Drone = { id: number, district: string, target: number?, doneAt: number }

export type Book = {
	n: number,
	maxHp: { number },
	hp: { number },
	state: { number },
	lastHit: { number },
	district: { string },
	warned: { boolean },
	collapses: { number }, -- start times of recent collapses
	dirty: { [number]: boolean },
	drones: { Drone },
	busy: { [number]: boolean }, -- building ids a drone is on
	boxes: { [number]: any }, -- id -> { x, z, sx, sz, base, top } (for the Structure grid)
	grids: { [number]: Structure.Grid }, -- built on the first blast
	gone: { [number]: { [number]: boolean } }, -- id -> piece indexes knocked out or fallen
	removed: { number }, -- flat { id, piece, cause } since the last send (cause 1 knocked out, 2 fell)
}

-- buildings: { id, hp, district } (WorldMap.buildings)
function BuildingState.new(cfg: any, buildings: { any }): Book
	local book: Book = {
		n = #buildings,
		maxHp = {},
		hp = {},
		state = {},
		lastHit = {},
		district = {},
		warned = {},
		collapses = {},
		dirty = {},
		drones = {},
		busy = {},
		boxes = {},
		grids = {},
		gone = {},
		removed = {},
	}
	local districts: { [string]: boolean } = {}
	for _, b in buildings do
		book.maxHp[b.id] = b.hp
		book.hp[b.id] = b.hp
		book.state[b.id] = 0
		book.lastHit[b.id] = -math.huge
		book.district[b.id] = b.district
		book.warned[b.id] = false
		book.boxes[b.id] = b
		districts[b.district] = true
	end
	local names = {}
	for d in districts do
		table.insert(names, d)
	end
	table.sort(names)
	for _, d in names do
		for _ = 1, cfg.repair.dronesPerDistrict do
			table.insert(book.drones, { id = #book.drones + 1, district = d, target = nil, doneAt = 0 })
		end
	end
	return book
end

local function recentCollapses(cfg: any, book: Book, now: number): number
	local n = 0
	for i = #book.collapses, 1, -1 do
		if now - book.collapses[i] < cfg.collapseTime then
			n += 1
		else
			table.remove(book.collapses, i)
		end
	end
	return n
end

local function set(book: Book, id: number, state: number)
	if book.state[id] ~= state then
		book.state[id] = state
		book.dirty[id] = true
	end
end

-- Returns the new state, whether it changed, whether a collapse was cut to Damaged, and whether the
-- building just crossed the warning line (citizens run).
function BuildingState.hit(
	cfg: any,
	book: Book,
	id: number,
	dmg: number,
	now: number
): (number, boolean, boolean, boolean)
	local state = book.state[id]
	if state == nil or state == 2 or dmg <= 0 then
		return state or 0, false, false, false
	end
	book.lastHit[id] = now
	local max = book.maxHp[id]
	book.hp[id] = math.max(0, book.hp[id] - dmg)
	local lost = 1 - book.hp[id] / max
	local warn = false
	if lost >= cfg.warnAt and not book.warned[id] then
		book.warned[id] = true
		warn = true
	end
	local cut = false
	local newState = state
	if lost >= 1 then
		if recentCollapses(cfg, book, now) < cfg.maxCollapses then
			newState = 2
			table.insert(book.collapses, now)
		else
			newState = 1
			book.hp[id] = 1
			cut = true
		end
	elseif lost >= cfg.damagedAt then
		newState = 1
	end
	local changed = newState ~= state
	set(book, id, newState)
	return newState, changed, cut, warn
end

-- A hero knocked through a wall: Damaged at once (HP drops to the Damaged line if it was above it)
function BuildingState.force(cfg: any, book: Book, id: number, now: number): boolean
	if book.state[id] ~= 0 then
		book.lastHit[id] = now
		return false
	end
	book.lastHit[id] = now
	book.hp[id] = math.min(book.hp[id], math.floor(book.maxHp[id] * (1 - cfg.damagedAt)))
	set(book, id, 1)
	return true
end

function BuildingState.repairable(cfg: any, book: Book, id: number, now: number): boolean
	local s = book.state[id]
	if s == 1 then
		return now - book.lastHit[id] >= cfg.repair.damagedAfter
	elseif s == 2 then
		return now - book.lastHit[id] >= cfg.repair.collapsedAfter
	end
	return false
end

function BuildingState.repair(book: Book, id: number)
	book.hp[id] = book.maxHp[id]
	book.warned[id] = false
	book.gone[id] = nil
	set(book, id, 0)
end

-- The building's Structure grid (built once)
function BuildingState.grid(cfg: any, book: Book, id: number): Structure.Grid?
	local g = book.grids[id]
	if not g and book.boxes[id] and book.boxes[id].sx then
		g = Structure.build(cfg, book.boxes[id])
		book.grids[id] = g
	end
	return g
end

export type Blast = {
	state: number,
	changed: boolean,
	cut: boolean, -- a full collapse was held back by the cap (the ground storey stays up for now)
	warn: boolean,
	hit: { number }, -- pieces knocked out
	fell: { number }, -- pieces that lost their support
	failed: number?, -- the lowest storey that gave way
}

-- A hit at (x, y, z): pieces knocked out, then whatever lost its support falls (see Structure)
function BuildingState.blast(
	cfg: any,
	book: Book,
	id: number,
	x: number,
	y: number,
	z: number,
	radius: number,
	dmg: number,
	now: number
): Blast
	local state = book.state[id]
	local out: Blast =
		{ state = state or 0, changed = false, cut = false, warn = false, hit = {}, fell = {}, failed = nil }
	local grid = BuildingState.grid(cfg, book, id)
	if state == nil or state == 2 or dmg <= 0 or not grid then
		return out
	end
	book.lastHit[id] = now
	local gone = book.gone[id] or {}
	book.gone[id] = gone
	out.hit = Structure.blast(cfg, grid, gone, x, y, z, radius, dmg)
	if #out.hit == 0 then
		return out
	end
	local capped = recentCollapses(cfg, book, now) >= cfg.maxCollapses
	out.fell, out.failed = Structure.settle(cfg, grid, gone, capped)
	out.cut = capped and not Structure.stands(cfg, grid, gone, 1)
	local lost = Structure.lost(grid, gone)
	book.hp[id] = math.max(1, math.floor(book.maxHp[id] * (1 - lost)))
	if (lost >= cfg.structure.warnLost or out.failed) and not book.warned[id] then
		book.warned[id] = true
		out.warn = true
	end
	local newState = 1
	if out.failed == 1 then
		newState = 2
		book.hp[id] = 0
		table.insert(book.collapses, now)
	else
		for _, i in out.hit do
			table.insert(book.removed, id)
			table.insert(book.removed, i)
			table.insert(book.removed, 1)
		end
		for _, i in out.fell do
			table.insert(book.removed, id)
			table.insert(book.removed, i)
			table.insert(book.removed, 2)
		end
	end
	out.changed = newState ~= state
	out.state = newState
	set(book, id, newState)
	return out
end

-- A robot thrown through a wall at (x, y, z): the nearest wall panels break
function BuildingState.punch(
	cfg: any,
	book: Book,
	id: number,
	x: number,
	y: number,
	z: number,
	now: number
): Blast
	local S = cfg.structure
	return BuildingState.blast(cfg, book, id, x, y, z, cfg.clash.wallRange, S.clashPanels * S.chunkCost, now)
end

-- The pieces gone from every Damaged building: { { id, bits }, ... } (the snapshot)
function BuildingState.packGone(cfg: any, book: Book): { { any } }
	local out = {}
	for id, gone in book.gone do
		if book.state[id] == 1 then
			local grid = BuildingState.grid(cfg, book, id)
			if grid then
				table.insert(out, { id, Structure.pack(#grid.pieces, gone) })
			end
		end
	end
	return out
end

-- The pieces removed since the last call: { id, piece, cause, ... }
function BuildingState.takeRemoved(book: Book): { number }
	local list = book.removed
	book.removed = {}
	return list
end

-- Run the drones: finish jobs that are done, then give idle drones the quietest eligible building in their
-- district. Returns the ids repaired this step and the drones that started a job.
function BuildingState.stepDrones(cfg: any, book: Book, now: number): ({ number }, { Drone })
	local repaired, started = {}, {}
	for _, d in book.drones do
		if d.target and now >= d.doneAt then
			local id = d.target :: number
			book.busy[id] = nil
			d.target = nil
			-- a building hit again during the job stays broken (the drone tries again later)
			if BuildingState.repairable(cfg, book, id, now - cfg.repair.each) or book.state[id] == 0 then
				if book.state[id] ~= 0 then
					BuildingState.repair(book, id)
					table.insert(repaired, id)
				end
			end
		end
	end
	for _, d in book.drones do
		if not d.target then
			local best, bestT = nil, math.huge
			for id = 1, book.n do
				if
					book.district[id] == d.district
					and not book.busy[id]
					and BuildingState.repairable(cfg, book, id, now)
					and book.lastHit[id] < bestT
				then
					best, bestT = id, book.lastHit[id]
				end
			end
			if best then
				d.target = best
				d.doneAt = now + cfg.repair.each
				book.busy[best] = true
				table.insert(started, d)
			end
		end
	end
	return repaired, started
end

-- 2 bits a building, 4 to a byte
function BuildingState.pack(book: Book): buffer
	local b = buffer.create(math.ceil(book.n / 4))
	for id = 1, book.n do
		local i = (id - 1) // 4
		local shift = ((id - 1) % 4) * 2
		buffer.writeu8(b, i, bit32.bor(buffer.readu8(b, i), bit32.lshift(book.state[id], shift)))
	end
	return b
end

function BuildingState.unpack(b: buffer, n: number): { number }
	local out = table.create(n, 0)
	for id = 1, n do
		local i = (id - 1) // 4
		if i < buffer.len(b) then
			out[id] = bit32.band(bit32.rshift(buffer.readu8(b, i), ((id - 1) % 4) * 2), 3)
		end
	end
	return out
end

-- The changes since the last call, as a flat list { id, state, id, state, ... }
function BuildingState.takeDiffs(book: Book): { number }
	local list = {}
	for id in book.dirty do
		table.insert(list, id)
		table.insert(list, book.state[id])
	end
	table.clear(book.dirty)
	return list
end

return BuildingState
