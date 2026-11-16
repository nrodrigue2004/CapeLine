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
	}
	local districts: { [string]: boolean } = {}
	for _, b in buildings do
		book.maxHp[b.id] = b.hp
		book.hp[b.id] = b.hp
		book.state[b.id] = 0
		book.lastHit[b.id] = -math.huge
		book.district[b.id] = b.district
		book.warned[b.id] = false
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
	set(book, id, 0)
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
