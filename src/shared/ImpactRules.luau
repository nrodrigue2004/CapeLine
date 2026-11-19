--!strict
-- ImpactRules: momentum and impact as pure maths (nate's playtest 2026-11-19: "get hit with something and it
-- sends me back into a building and it destroys the building. Or even just flying at super speed. Momentum and
-- impact should destroy things"). ImpactService on the server uses it; Lune checks it.
-- * index / near: buildings bucketed on a flat grid so a hit, a ram or a throw looks only at the buildings
--   round it (2,600+ wreckable buildings once the outskirts break too).
-- * enter / firstWall: where a straight path first goes into a building's box (a throw's wall).
-- * containing: the building a contact point is on (a ram the device saw).
-- * ramDamage, knockDistance, knockDamage, robotDamage, through: the tuning curves (Config.Combat.impact).
-- * ramOk: the server's check of a claimed ram (speed against its own history, distance to the hero).
-- * ledger / allow: the caps (breaks per hero per window, breaks per second on the server).

local ImpactRules = {}

export type Box = { id: number, x: number, z: number, sx: number, sz: number, base: number, top: number }
export type Index = { cell: number, cells: { [number]: { number } } }

local OFFSET = 32768

local function key(cx: number, cz: number): number
	return (cx + OFFSET) * 65536 + (cz + OFFSET)
end

-- Buckets every building by the grid cells its footprint covers
function ImpactRules.index(boxes: { [number]: Box }, cell: number): Index
	local index: Index = { cell = cell, cells = {} }
	for id, b in boxes do
		ImpactRules.add(index, id, b)
	end
	return index
end

function ImpactRules.add(index: Index, id: number, b: Box)
	local c = index.cell
	for cx = math.floor((b.x - b.sx / 2) / c), math.floor((b.x + b.sx / 2) / c) do
		for cz = math.floor((b.z - b.sz / 2) / c), math.floor((b.z + b.sz / 2) / c) do
			local k = key(cx, cz)
			local list = index.cells[k]
			if not list then
				list = {}
				index.cells[k] = list
			end
			table.insert(list, id)
		end
	end
end

-- Ids of the buildings in the cells within r of (x, z), each once, smallest id first
function ImpactRules.near(index: Index, x: number, z: number, r: number): { number }
	local c = index.cell
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for cx = math.floor((x - r) / c), math.floor((x + r) / c) do
		for cz = math.floor((z - r) / c), math.floor((z + r) / c) do
			local list = index.cells[key(cx, cz)]
			if list then
				for _, id in list do
					if not seen[id] then
						seen[id] = true
						table.insert(out, id)
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

-- Ids near a straight path from (ox, oz) moving (mx, mz), with a margin
function ImpactRules.nearPath(
	index: Index,
	ox: number,
	oz: number,
	mx: number,
	mz: number,
	margin: number
): { number }
	local len = math.sqrt(mx * mx + mz * mz)
	return ImpactRules.near(index, ox + mx / 2, oz + mz / 2, len / 2 + margin)
end

-- Where the path from o moving m (0..1 along it) first enters box b, or nil (it misses, or starts inside)
function ImpactRules.enter(
	b: Box,
	ox: number,
	oy: number,
	oz: number,
	mx: number,
	my: number,
	mz: number
): number?
	local t0, t1 = 0, 1
	local inside = true
	for axis = 1, 3 do
		local o, d, lo, hi
		if axis == 1 then
			o, d, lo, hi = ox, mx, b.x - b.sx / 2, b.x + b.sx / 2
		elseif axis == 2 then
			o, d, lo, hi = oy, my, b.base, b.top
		else
			o, d, lo, hi = oz, mz, b.z - b.sz / 2, b.z + b.sz / 2
		end
		if o < lo or o > hi then
			inside = false
		end
		if math.abs(d) < 1e-9 then
			if o < lo or o > hi then
				return nil
			end
		else
			local a, c = (lo - o) / d, (hi - o) / d
			if a > c then
				a, c = c, a
			end
			t0, t1 = math.max(t0, a), math.min(t1, c)
			if t0 > t1 then
				return nil
			end
		end
	end
	if inside then
		return nil
	end
	return t0
end

-- The first building along the path (of ids, skipping any skip(id) says no to): its id and how far (0..1)
function ImpactRules.firstWall(
	boxes: { [number]: Box },
	ids: { number },
	ox: number,
	oy: number,
	oz: number,
	mx: number,
	my: number,
	mz: number,
	skip: ((number) -> boolean)?
): (number?, number)
	local best, bestT = nil, math.huge
	for _, id in ids do
		local b = boxes[id]
		if b and not (skip and skip(id)) then
			local t = ImpactRules.enter(b, ox, oy, oz, mx, my, mz)
			if t and t < bestT then
				best, bestT = id, t
			end
		end
	end
	return best, if best then bestT else 1
end

-- The building whose box (grown by pad) holds the point, nearest centre first, or nil
function ImpactRules.containing(
	boxes: { [number]: Box },
	ids: { number },
	x: number,
	y: number,
	z: number,
	pad: number,
	skip: ((number) -> boolean)?
): number?
	local best, bestD = nil, math.huge
	for _, id in ids do
		local b = boxes[id]
		if
			b
			and not (skip and skip(id))
			and math.abs(x - b.x) <= b.sx / 2 + pad
			and math.abs(z - b.z) <= b.sz / 2 + pad
			and y >= b.base - pad
			and y <= b.top + pad
		then
			local d = (x - b.x) ^ 2 + (z - b.z) ^ 2
			if d < bestD then
				best, bestD = id, d
			end
		end
	end
	return best
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

-- Structure damage from a ram at `speed` (0 below the minimum)
function ImpactRules.ramDamage(ram: any, speed: number): number
	if speed < ram.minSpeed then
		return 0
	end
	return math.floor(lerp(ram.dmg[1], ram.dmg[2], (speed - ram.minSpeed) / (ram.fullSpeed - ram.minSpeed)))
end

-- How far a robot melee hit that took `taken` of `maxHealth` throws the hero (0: no throw)
function ImpactRules.knockDistance(knock: any, taken: number, maxHealth: number): number
	if maxHealth <= 0 then
		return 0
	end
	local share = taken / maxHealth
	if share < knock.minShare then
		return 0
	end
	return lerp(knock.dist[1], knock.dist[2], (share - knock.minShare) / (knock.fullShare - knock.minShare))
end

-- Structure damage from a hero thrown into a wall at `speed` studs/s (0 when too slow)
function ImpactRules.knockDamage(knock: any, speed: number): number
	if speed < knock.wallSpeed then
		return 0
	end
	return math.floor(
		lerp(knock.dmg[1], knock.dmg[2], (speed - knock.wallSpeed) / (knock.fullSpeed - knock.wallSpeed))
	)
end

-- Structure damage from a robot knocked `distance` studs into a wall (0 when too short)
function ImpactRules.robotDamage(robot: any, distance: number): number
	if distance < robot.minKnock then
		return 0
	end
	return math.floor(
		lerp(robot.dmg[1], robot.dmg[2], (distance - robot.minKnock) / (robot.fullKnock - robot.minKnock))
	)
end

-- A hero dropping onto a roof at `fall` studs/s (nate, 2026-11-19 13:18Z): structure damage and radius (0 when
-- too slow). drop: Config.Combat.drop
function ImpactRules.dropDamage(drop: any, fall: number): (number, number)
	if fall < drop.minFall then
		return 0, 0
	end
	local t = (fall - drop.minFall) / (drop.fullFall - drop.minFall)
	return math.floor(lerp(drop.dmg[1], drop.dmg[2], t)), lerp(drop.radius[1], drop.radius[2], t)
end

-- The server's check of a drop the device saw: the server's own recent top speed backs the claimed fall, and
-- the landing is near where the server has the hero. Returns the fall speed it counts at, or nil.
function ImpactRules.dropOk(drop: any, claimed: number, peak: number, distance: number): number?
	if claimed < drop.minFall or peak < drop.minFall / drop.slack then
		return nil
	end
	if distance > drop.near + claimed * drop.lag then
		return nil
	end
	return math.min(claimed, peak * drop.slack)
end

-- A throw of `total` studs whose wall is `t` (0..1) along it: the studs it travels in all. broke: the wall gave
-- way, so the hero goes on through with `through` of the rest; else it stops `stopShort` before the wall.
function ImpactRules.throwLength(knock: any, total: number, t: number, broke: boolean): number
	local before = total * math.clamp(t, 0, 1)
	if broke then
		return before + (total - before) * knock.through
	end
	return math.max(0, before - knock.stopShort)
end

-- The velocity after going through a wall
function ImpactRules.after(ram: any, speed: number): number
	return speed * (1 - ram.loss)
end

-- The server's check of a ram the device saw: fast enough by the server's own history, the claim no faster
-- than that allows, and the contact near where the server has the hero
function ImpactRules.ramOk(ram: any, claimed: number, peak: number, distance: number): boolean
	if claimed < ram.minSpeed or peak < ram.minSpeed / ram.slack then
		return false
	end
	if claimed > peak * ram.slack + 10 then
		return false
	end
	return distance <= ram.near + claimed * ram.lag
end

-- The speed a ram counts at: the claim, never more than the server saw
function ImpactRules.ramSpeed(ram: any, claimed: number, peak: number): number
	return math.min(claimed, peak * ram.slack)
end

export type Ledger = { heroes: { [number]: { number } }, server: { number } }

function ImpactRules.ledger(): Ledger
	return { heroes = {}, server = {} }
end

local function trim(list: { number }, now: number, window: number)
	for i = #list, 1, -1 do
		if now - list[i] >= window then
			table.remove(list, i)
		end
	end
end

-- May hero `who` break a wall now? Counts it when yes. cfg: Config.Combat.impact
function ImpactRules.allow(cfg: any, ledger: Ledger, who: number, now: number): boolean
	trim(ledger.server, now, 1)
	if #ledger.server >= cfg.serverPerSecond then
		return false
	end
	local list = ledger.heroes[who]
	if not list then
		list = {}
		ledger.heroes[who] = list
	end
	trim(list, now, cfg.ram.heroWindow)
	if #list >= cfg.ram.perHero then
		return false
	end
	table.insert(list, now)
	table.insert(ledger.server, now)
	return true
end

function ImpactRules.forget(ledger: Ledger, who: number)
	ledger.heroes[who] = nil
end

return ImpactRules
