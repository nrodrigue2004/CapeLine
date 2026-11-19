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
-- * Audit fixes (2026-11-18): a building the collapse cap held up comes down once the cap has room (stepHeld);
--   a repair is sent with the diffs (r) so a device clears the old holes even when the building is hit again in
--   the same batch (applyDiff, applySnapshot: the device's copy, pure so Lune checks it matches); ray finds the
--   standing pieces of Damaged buildings (their real body stops blocking on the server, so only the holes let
--   shots through); abilityStruct and castStruct say which casts break buildings (every damaging one).
-- * Pins (2026-11-18): a building that holds something up never breaks: a fast-travel beacon's host for good
--   (WorldMap marks it `fixed`), and the roof a side quest goal stands on while that goal is live (pin/unpin,
--   SideQuestService through BuildingService.pin). Hits on a pinned building knock nothing out.

-- * blast / punch (Red Faction-style, nate 2026-11-16): a hit knocks pieces out of the building's Structure
--   grid and whatever loses its support falls. Damaged = any piece gone; Collapsed = the ground storey gave
--   way. Structure HP follows the share of weight lost. The pieces gone are sent as diffs and in the
--   snapshot (one bit a piece), so every device shows the same holes. hit() and force() are the older
--   HP-only path, kept for callers without a position.

local Structure = if script then require(script.Parent.Structure) else (require :: any)("./Structure")
local ImpactRules = if script then require(script.Parent.ImpactRules) else (require :: any)("./ImpactRules")

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
	chip: { [number]: number }, -- id -> small hits' structure damage still under one piece's cost
	open: { [number]: boolean }, -- ids Damaged now (ray looks only at these)
	held: { [number]: boolean }, -- ids whose ground storey gave way while the collapse cap was full
	fixed: { number }, -- ids repaired since the last send (sent first, so devices drop the old holes)
	keep: { [number]: boolean }, -- ids that never break (a beacon's host: the building record's `fixed`)
	pins: { [number]: number }, -- ids held whole for now, with how many holders (side quest roofs)
	index: ImpactRules.Index, -- the buildings on a flat grid (cfg.cell): hits look only at the ones round them
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
		chip = {},
		open = {},
		held = {},
		fixed = {},
		keep = {},
		pins = {},
		index = { cell = cfg.cell or 64, cells = {} },
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
		if b.fixed == true then
			book.keep[b.id] = true
		end
		if b.sx then
			ImpactRules.add(book.index, b.id, b)
		end
		districts[b.district] = true
	end
	local names = {}
	for d in districts do
		table.insert(names, d)
	end
	table.sort(names)
	for _, d in names do
		local per = (cfg.repair.districtDrones and cfg.repair.districtDrones[d])
			or cfg.repair.dronesPerDistrict
		for _ = 1, per do
			table.insert(book.drones, { id = #book.drones + 1, district = d, target = nil, doneAt = 0 })
		end
	end
	return book
end

-- The building ids whose footprints are in the grid cells within r of (x, z) (smallest id first)
function BuildingState.near(book: Book, x: number, z: number, r: number): { number }
	return ImpactRules.near(book.index, x, z, r)
end

-- Hold building id whole for good (a side quest's outskirts house, 2026-11-19), like a beacon's host
function BuildingState.keepWhole(book: Book, id: number)
	if book.state[id] ~= nil then
		book.keep[id] = true
	end
end

-- Does building id never break right now (a beacon's host, or a roof a side quest goal stands on)?
function BuildingState.pinned(book: Book, id: number): boolean
	return book.keep[id] == true or (book.pins[id] or 0) > 0
end

-- Hold building id whole (on) or let it go (off); holders count, so two goals on one roof both hold it
function BuildingState.pin(book: Book, id: number, on: boolean)
	if book.state[id] == nil then
		return
	end
	local n = math.max(0, (book.pins[id] or 0) + (if on then 1 else -1))
	if n > 0 then
		book.pins[id] = n
	else
		book.pins[id] = nil
	end
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
	if state == 1 then
		book.open[id] = true
	else
		book.open[id] = nil
		book.held[id] = nil
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
	if state == nil or state == 2 or dmg <= 0 or BuildingState.pinned(book, id) then
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
	if book.state[id] ~= 0 or BuildingState.pinned(book, id) then
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
	book.chip[id] = nil
	book.held[id] = nil
	set(book, id, 0)
	table.insert(book.fixed, id)
	-- pieces of it still waiting to be sent are from before the repair (the Dev panel's repair all)
	local r = book.removed
	for i = #r - 2, 1, -3 do
		if r[i] == id then
			table.remove(r, i + 2)
			table.remove(r, i + 1)
			table.remove(r, i)
		end
	end
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

-- Does a blast at (x, y, z) with radius touch building b (BuildingService.hit)? A skyscraper's crown
-- (setbacks, spire, lantern, mast) stands above its shaft up to its peak, so it takes hits too.
function BuildingState.touches(b: any, x: number, y: number, z: number, radius: number): boolean
	local dx = math.max(math.abs(x - b.x) - b.sx / 2, 0)
	local dz = math.max(math.abs(z - b.z) - b.sz / 2, 0)
	local dy = math.max(y - ((b.peak or b.top) + 10), b.base - y, 0)
	return dx * dx + dz * dz + dy * dy <= radius * radius
end

-- The height a hit lands at on building b: a hit on the crown lands on the shaft's top storey (the Structure
-- grid ends at the roof), so its roof and top walls break and the crown goes with them (BuildingFx)
function BuildingState.blastY(b: any, y: number): number
	return math.min(y, b.top)
end

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
	if state == nil or state == 2 or dmg <= 0 or BuildingState.pinned(book, id) then
		return out
	end
	local grid = BuildingState.grid(cfg, book, id)
	if not grid then
		return out
	end
	book.lastHit[id] = now
	-- small hits (basic attacks) add up: a piece breaks once they reach one piece's cost
	if dmg < cfg.structure.chunkCost then
		local chip = (book.chip[id] or 0) + dmg
		if chip < cfg.structure.chunkCost then
			book.chip[id] = chip
			return out
		end
		book.chip[id] = nil
		dmg = chip
	end
	local gone = book.gone[id] or {}
	book.gone[id] = gone
	out.hit = Structure.blast(cfg, grid, gone, x, y, z, radius, dmg)
	if #out.hit == 0 then
		return out
	end
	local capped = recentCollapses(cfg, book, now) >= cfg.maxCollapses
	out.fell, out.failed = Structure.settle(cfg, grid, gone, capped)
	out.cut = capped and not Structure.stands(cfg, grid, gone, 1)
	if out.cut then
		book.held[id] = true -- it comes down once the cap has room (stepHeld)
	end
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

-- Buildings the collapse cap held up (their ground storey gave way while 3 others were coming down) come down
-- once the cap has room, longest-held first, so no building is left standing on nothing. Returns { id, blast }.
function BuildingState.stepHeld(cfg: any, book: Book, now: number): { { id: number, blast: Blast } }
	local out = {}
	local ids = {}
	for id in book.held do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return book.lastHit[a] < book.lastHit[b] or (book.lastHit[a] == book.lastHit[b] and a < b)
	end)
	for _, id in ids do
		local grid = BuildingState.grid(cfg, book, id)
		local gone = book.gone[id]
		if book.state[id] ~= 1 or not grid or not gone or Structure.stands(cfg, grid, gone, 1) then
			book.held[id] = nil
		elseif recentCollapses(cfg, book, now) < cfg.maxCollapses then
			book.held[id] = nil
			local fell = Structure.settle(cfg, grid, gone, false)
			local warn = not book.warned[id]
			book.warned[id] = true
			book.hp[id] = 0
			book.lastHit[id] = now -- the drones wait the full time after it fell
			table.insert(book.collapses, now)
			set(book, id, 2)
			table.insert(out, {
				id = id,
				blast = {
					state = 2,
					changed = true,
					cut = false,
					warn = warn,
					hit = {},
					fell = fell,
					failed = 1,
				},
			})
		end
	end
	return out
end

-- Where a ray (unit direction dx, dy, dz) first meets a standing piece of a Damaged building, or max. A
-- Damaged building's real body stops blocking shots on the server (setWrecked), so without this a bolt, a
-- dash or a leap passed through every wall it still has and could never finish it off. A piece the ray
-- starts inside is skipped (as a Roblox raycast does).
local function enter(
	cx: number,
	cy: number,
	cz: number,
	hx: number,
	hy: number,
	hz: number,
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	max: number
): number?
	local t0, t1 = -math.huge, math.huge
	for axis = 1, 3 do
		local o, d, lo, hi
		if axis == 1 then
			o, d, lo, hi = ox, dx, cx - hx, cx + hx
		elseif axis == 2 then
			o, d, lo, hi = oy, dy, cy - hy, cy + hy
		else
			o, d, lo, hi = oz, dz, cz - hz, cz + hz
		end
		if math.abs(d) < 1e-9 then
			if o < lo or o > hi then
				return nil
			end
		else
			local a, b = (lo - o) / d, (hi - o) / d
			if a > b then
				a, b = b, a
			end
			t0, t1 = math.max(t0, a), math.min(t1, b)
			if t0 > t1 then
				return nil
			end
		end
	end
	if t1 < 0 or t0 > max then
		return nil
	end
	return t0 -- negative: the ray starts inside
end

function BuildingState.ray(
	cfg: any,
	book: Book,
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	max: number
): number
	local best = max
	for id in book.open do
		local b = book.boxes[id]
		if
			b
			and b.sx
			and enter(
				b.x,
				(b.base + b.top) / 2,
				b.z,
				b.sx / 2,
				(b.top - b.base) / 2,
				b.sz / 2,
				ox,
				oy,
				oz,
				dx,
				dy,
				dz,
				best
			)
		then
			local grid = BuildingState.grid(cfg, book, id)
			local gone: { [number]: boolean } = book.gone[id] or {}
			if grid then
				for i, p in grid.pieces do
					if not gone[i] then
						local t = enter(
							p.cx,
							p.cy,
							p.cz,
							p.sx / 2,
							p.sy / 2,
							p.sz / 2,
							ox,
							oy,
							oz,
							dx,
							dy,
							dz,
							best
						)
						if t and t >= 0 and t < best then
							best = t
						end
					end
				end
			end
		end
	end
	return best
end

-- An ability's structure damage (CombatService): its own structDmg, else supers cfg.superStruct, else a
-- default by slot for anything that deals damage (nate 2026-11-16: every damaging ability breaks buildings)
function BuildingState.abilityStruct(cfg: any, eff: any): number
	if eff.structDmg then
		return eff.structDmg
	elseif eff.slot == "super" then
		return cfg.superStruct
	elseif (eff.coeff or 0) > 0 and not eff.allyHeal then
		return cfg.slotStruct[eff.slot] or 0
	end
	return 0
end

-- Shapes whose cast hits buildings where it lands (leaps and throws hit when they land, CombatService). The
-- area shapes (fields, rides, launches, placed things) hit at their centre, when the cast has one.
local CAST = { bolt = true, chain = true, dash = true, cone = true, arc = true, nova = true, line = true }
local AREA = { field = true, ride = true, launch = true, place = true }
BuildingState.LANDS = { leap = true, throw = true }
function BuildingState.castStruct(shape: string?, hasCentre: boolean): boolean
	return shape ~= nil and (CAST[shape] == true or (AREA[shape] == true and hasCentre))
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
	-- the wrecked buildings once (2,500+ buildings since 2026-11-19: no drone walks all of them)
	local wrecked: { number }? = nil
	for _, d in book.drones do
		if not d.target then
			if not wrecked then
				local list = {}
				for id = 1, book.n do
					if book.state[id] ~= 0 then
						table.insert(list, id)
					end
				end
				wrecked = list
			end
			local best, bestT = nil, math.huge
			for _, id in wrecked :: { number } do
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

-- Building boxes as 32-bit floats, 6 a building (x, z, sx, sz, base, top) in list order (the outskirts records in
-- the snapshot, 2026-11-19). WorldMap snaps them to a quarter stud so a float holds them exactly.
function BuildingState.packBoxes(list: { any }): buffer
	local b = buffer.create(#list * 24)
	for i, r in list do
		local o = (i - 1) * 24
		buffer.writef32(b, o, r.x)
		buffer.writef32(b, o + 4, r.z)
		buffer.writef32(b, o + 8, r.sx)
		buffer.writef32(b, o + 12, r.sz)
		buffer.writef32(b, o + 16, r.base)
		buffer.writef32(b, o + 20, r.top)
	end
	return b
end

-- The device's read of packBoxes: records by id from `from` on (at most `max` of them)
function BuildingState.unpackBoxes(b: buffer, from: number, max: number): { [number]: any }
	local out = {}
	local n = math.min(buffer.len(b) // 24, max)
	for i = 1, n do
		local o = (i - 1) * 24
		local id = from + i - 1
		out[id] = {
			id = id,
			x = buffer.readf32(b, o),
			z = buffer.readf32(b, o + 4),
			sx = buffer.readf32(b, o + 8),
			sz = buffer.readf32(b, o + 12),
			base = buffer.readf32(b, o + 16),
			top = buffer.readf32(b, o + 20),
		}
	end
	return out
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

-- The buildings repaired since the last call (sent as r, before the pieces and states)
function BuildingState.takeFixed(book: Book): { number }
	local list = book.fixed
	book.fixed = {}
	return list
end

-- The device's copy (BuildingFx): view = { state = { [id] = state }, gone = { [id] = { [piece] = true } } }.
-- A snapshot replaces all of it; count(id) is the building's piece count, or nil when it is unknown.
function BuildingState.applySnapshot(view: any, data: any, count: (number) -> number?)
	table.clear(view.gone)
	local list = BuildingState.unpack(data.s, math.clamp(tonumber(data.n) or 0, 0, 4096))
	for id, s in list do
		view.state[id] = s
	end
	for _, row in data.g or {} do
		local id, bits = row[1], row[2]
		local n = if type(id) == "number" then count(id) else nil
		if n and type(bits) == "buffer" then
			view.gone[id] = Structure.unpack(bits, n)
		end
	end
end

-- A diff batch onto the device's copy: repairs first (their old holes go), then the pieces, then the states.
-- known(id): the device knows that building. Returns the buildings touched, the pieces that just went per
-- building (piece -> 1 knocked out, 2 fell) and the buildings repaired in this batch (redraw them from scratch).
function BuildingState.applyDiff(
	view: any,
	data: any,
	known: (any) -> boolean
): ({ [number]: boolean }, { [number]: { [number]: number } }, {
	[number]: boolean,
})
	local touched: { [number]: boolean } = {}
	local fresh: { [number]: { [number]: number } } = {}
	local reset: { [number]: boolean } = {}
	for _, id in data.r or {} do
		if type(id) == "number" then
			view.gone[id] = nil
			view.state[id] = 0
			touched[id] = true
			reset[id] = true
		end
	end
	local c = data.c or {}
	for i = 1, #c - 2, 3 do
		local id, piece, cause = c[i], c[i + 1], c[i + 2]
		if known(id) and type(piece) == "number" then
			local g = view.gone[id] or {}
			view.gone[id] = g
			g[piece] = true
			fresh[id] = fresh[id] or {}
			fresh[id][piece] = cause
			touched[id] = true
		end
	end
	local d = data.d or {}
	for i = 1, #d - 1, 2 do
		local id, s = d[i], d[i + 1]
		if type(id) == "number" and type(s) == "number" and view.state[id] ~= s then
			view.state[id] = s
			touched[id] = true
		end
	end
	return touched, fresh, reset
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
