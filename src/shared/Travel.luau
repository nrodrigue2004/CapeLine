--!strict
-- Travel: the pure rules for safehouses and fast travel (spec: Movement kit > Fast travel; Defeat and death;
-- Banking; Remote events Move.FastTravel, Bank.Deposit, Respawn.Choose). Servers and Lune tests share them.
-- * Discovered beacons and visited safehouses are bit masks on the character (bit id - 1).
-- * canTravel: the beacon exists and is discovered, the hero is out of combat, not already travelling, not in a
--   scene (the HQ, a friend's HQ, a mission pocket, the prologue, the creator: each has its own way out, and a
--   flight out of one left the hero in the city still in that scene), and the 20 s cooldown is over.
-- * flightPath: the 3 s skippable flight's arc (the client animates it; the server moves the hero at the end).
-- * deposit: every on-hand Credit goes to the bank (only on-hand Credits can move in PvP, M8).
-- * respawnAt: a defeat respawns at the nearest visited safehouse; a join at the last chosen one.

local Travel = {}

function Travel.has(mask: number, id: number): boolean
	return id >= 1 and id <= 31 and bit32.btest(mask, bit32.lshift(1, id - 1))
end

function Travel.add(mask: number, id: number): number
	if id < 1 or id > 31 then
		return mask
	end
	return bit32.bor(mask, bit32.lshift(1, id - 1))
end

function Travel.count(mask: number): number
	local n = 0
	while mask ~= 0 do
		n += bit32.band(mask, 1)
		mask = bit32.rshift(mask, 1)
	end
	return n
end

export type TravelState = {
	beacons: number, -- discovered mask
	inCombat: boolean,
	traveling: boolean,
	readyAt: number, -- clock time the cooldown ends
	now: number,
	scene: string?, -- the hero's scene (hero.scene), nil out in the city
}

function Travel.canTravel(worldCfg: any, s: TravelState, beaconId: number): (boolean, string?)
	local exists = false
	for _, b in worldCfg.beacons do
		if b.id == beaconId then
			exists = true
		end
	end
	if not exists then
		return false, "no beacon"
	end
	if not Travel.has(s.beacons, beaconId) then
		return false, "undiscovered"
	end
	if s.traveling then
		return false, "traveling"
	end
	if s.scene ~= nil then
		return false, "scene"
	end
	if s.inCombat then
		return false, "combat"
	end
	if s.now < s.readyAt then
		return false, "cooldown"
	end
	return true, nil
end

-- Where a fast travel to beacon b sets the hero down (their root): beside the post, just above the disc, so the
-- body never starts inside the post or the roof (BeaconService and the travel audit's test share it)
function Travel.arrival(worldCfg: any, b: { x: number, y: number, z: number }): (number, number, number)
	return b.x + 4, b.y + worldCfg.beacon.arriveAbove, b.z + 4
end

-- May a trip that started at trip.started still land? Not when something else moved the hero after it began
-- (a mission pocket, the HQ, a contest pad: SafehouseService.place stamps hero.placedAt), so the landing
-- never pulls a hero back out of where the game just put them.
function Travel.landOk(trip: { started: number }, placedAt: number?): boolean
	return placedAt == nil or placedAt <= trip.started
end

-- A point on the fast-travel flight at fraction t (0..1): up to a cruise height, across, then down
function Travel.flightPath(
	fromX: number,
	fromY: number,
	fromZ: number,
	toX: number,
	toY: number,
	toZ: number,
	t: number
): (number, number, number)
	t = math.clamp(t, 0, 1)
	local dist = math.sqrt((toX - fromX) ^ 2 + (toZ - fromZ) ^ 2)
	local cruise = math.max(fromY, toY) + math.clamp(dist * 0.15, 40, 260)
	local x = fromX + (toX - fromX) * t
	local z = fromZ + (toZ - fromZ) * t
	-- a smooth hump: the base line plus a sine bump that reaches cruise height in the middle
	local base = fromY + (toY - fromY) * t
	local bump = math.sin(t * math.pi) * (cruise - (fromY + toY) / 2)
	return x, base + bump, z
end

-- Move every on-hand Credit into the bank; returns the amount moved
function Travel.deposit(currency: { [string]: any }): number
	local moved = math.max(0, math.floor(currency.credits or 0))
	currency.credits = 0
	currency.banked = (currency.banked or 0) + moved
	return moved
end

-- Where a hero respawns. safehouses: { [id] = { x, z } }. visited: mask. last: lastSafehouse (0 = none).
-- deathX/deathZ given: the nearest visited (or the home) safehouse to that spot. Otherwise the last one.
function Travel.respawnAt(
	safehouses: { [number]: any },
	visited: number,
	last: number,
	home: number,
	deathX: number?,
	deathZ: number?
): number
	if deathX == nil or deathZ == nil then
		if last ~= 0 and safehouses[last] then
			return last
		end
		return home
	end
	local best, bestD = home, math.huge
	for id, s in safehouses do
		if id == home or id == last or Travel.has(visited, id) then
			local d = (s.x - deathX) ^ 2 + (s.z - (deathZ :: number)) ^ 2
			if d < bestD then
				best, bestD = id, d
			end
		end
	end
	return best
end

return Travel
