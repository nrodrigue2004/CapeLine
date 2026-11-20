--!strict
-- EnemyBuffer: the Enemy.Delta packet (10 Hz, unreliable). The spec's remote list has no enemy replication
-- line; this is it (Decisions.md, 2026-11-16). Each player gets only the enemies within Net.enemyRelevance.
-- Header 10 bytes: u32 sequence, f32 server time, u16 count. Then 13 bytes per enemy: id u16, x/y/z as
-- signed 16-bit in 0.1 stud steps (covers -3,276 to 3,276, so the whole map and the mission pockets at
-- y = 3,000), health fraction u8, packed u8 = state (3 bits) + typeId (5 bits), flags u8 (Status.BITS:
-- stun, root, slow, lifted, cloak, windup, shield, guard broken), yaw u8 (256 steps, for the robot bodies),
-- extra u8 (EnemySim.EXTRA: aim, rally, disguise, mend, lunge, hooked; 13 bytes each since the 9 new types).
-- The whole relevant list goes every packet, so a lost packet costs nothing.

local EnemyBuffer = {}

local HEADER = 10
local PER = 13
EnemyBuffer.HEADER = HEADER
EnemyBuffer.PER = PER

local function i16(value: number): number
	return math.clamp(math.floor(value * 10 + 0.5), -32768, 32767)
end

-- An UnreliableRemoteEvent drops any send over 900 bytes (perf pass 2026-11-18). A packet keeps 40 bytes for
-- the remote's own overhead, so it never holds more than MAX robots (65) whatever the caller asks for.
EnemyBuffer.LIMIT = 900
EnemyBuffer.MARGIN = 40
EnemyBuffer.MAX = (EnemyBuffer.LIMIT - EnemyBuffer.MARGIN - HEADER) // PER

-- Scratch kept across calls (perf pass 2026-11-18: 30 players at 10 Hz made a table per robot per player and
-- a sort closure each): the robots in reach, their squared distances, and their order (indices into both).
-- The output is byte for byte the old encoder's (tests/perf.luau).
local inReach: { any } = {}
local dist2: { number } = {}
local order: { number } = {}
local function closer(a: number, b: number): boolean
	return dist2[a] < dist2[b]
end
-- the fast sort: the distances alone (a plain number sort, no comparator) and which robot has each one. With
-- no two robots in reach at exactly the same distance the order is the only one there is, the old sort's
-- too; on a tie the old comparator sort runs, so even then the bytes match.
local keys: { number } = {}
local owner: { [number]: number } = {}
local function nearestFirst(n: number)
	table.clear(keys)
	table.clear(owner)
	for i = 1, n do
		local d = dist2[i]
		if d ~= d or owner[d] then
			table.sort(order, closer)
			return
		end
		owner[d] = i
		keys[i] = d
	end
	table.sort(keys)
	for i = 1, n do
		order[i] = owner[keys[i]]
	end
end

-- enemies: EnemySim list. Only those within `radius` of (px, py, pz), nearest first, at most maxCount (and
-- never more than MAX). key: the player's hero's solo key (EnemySim.sees; a private mission run's phase,
-- Shared.PhaseRules): only robots with the same key are sent (nil, the open world, gets only open-world robots).
function EnemyBuffer.encodeFor(
	sequence: number,
	time: number,
	enemies: { any },
	px: number,
	py: number,
	pz: number,
	radius: number,
	maxCount: number,
	key: number?
): buffer
	local r2 = radius * radius
	local n = 0
	table.clear(order)
	for _, e in enemies do
		if e.alive and e.solo == key then
			local dx, dy, dz = e.x - px, e.y - py, e.z - pz
			local d2 = dx * dx + dy * dy + dz * dz
			if d2 <= r2 then
				n += 1
				inReach[n] = e
				dist2[n] = d2
				order[n] = n
			end
		end
	end
	local cap = math.min(maxCount, EnemyBuffer.MAX)
	if n > cap then
		nearestFirst(n)
	end
	local count = math.min(n, cap)
	local b = buffer.create(HEADER + PER * count)
	buffer.writeu32(b, 0, sequence % 4294967296)
	buffer.writef32(b, 4, time)
	buffer.writeu16(b, 8, count)
	local offset = HEADER
	for i = 1, count do
		local e = inReach[order[i]]
		buffer.writeu16(b, offset, e.id)
		buffer.writei16(b, offset + 2, i16(e.x))
		buffer.writei16(b, offset + 4, i16(e.y))
		buffer.writei16(b, offset + 6, i16(e.z))
		buffer.writeu8(
			b,
			offset + 8,
			math.floor(math.clamp(e.health / math.max(1, e.maxHealth), 0, 1) * 255 + 0.5)
		)
		buffer.writeu8(b, offset + 9, (e.state % 8) + (e.typeId % 32) * 8)
		buffer.writeu8(b, offset + 10, (e.flags or 0) % 256)
		buffer.writeu8(b, offset + 11, math.floor(((e.yaw or 0) % (2 * math.pi)) / (2 * math.pi) * 256) % 256)
		buffer.writeu8(b, offset + 12, (e.extra or 0) % 256)
		offset += PER
	end
	-- drop the references so a removed robot is not held until the next call
	for i = 1, n do
		inReach[i] = nil
	end
	return b
end

export type Row = {
	id: number,
	x: number,
	y: number,
	z: number,
	health: number,
	state: number,
	typeId: number,
	flags: number,
	yaw: number,
	extra: number,
}

function EnemyBuffer.decode(b: buffer): (number, number, { Row })
	local len = buffer.len(b)
	if len < HEADER then
		return 0, 0, {}
	end
	local seq = buffer.readu32(b, 0)
	local time = buffer.readf32(b, 4)
	local count = buffer.readu16(b, 8)
	count = math.min(count, (len - HEADER) // PER)
	local rows = table.create(count)
	local offset = HEADER
	for _ = 1, count do
		local packed = buffer.readu8(b, offset + 9)
		table.insert(rows, {
			id = buffer.readu16(b, offset),
			x = buffer.readi16(b, offset + 2) / 10,
			y = buffer.readi16(b, offset + 4) / 10,
			z = buffer.readi16(b, offset + 6) / 10,
			health = buffer.readu8(b, offset + 8) / 255,
			state = packed % 8,
			typeId = (packed // 8) % 32,
			flags = buffer.readu8(b, offset + 10),
			yaw = buffer.readu8(b, offset + 11) / 256 * 2 * math.pi,
			extra = buffer.readu8(b, offset + 12),
		})
		offset += PER
	end
	return seq, time, rows
end

return EnemyBuffer
