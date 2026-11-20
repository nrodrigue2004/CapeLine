--!strict
-- CitizenBuffer: the Citizen.Delta packet (4 Hz, unreliable; not in the spec's remote list, see
-- Decisions.md). Each player gets the visible citizens within Destruction.citizens.relevance.
-- Header 6 bytes: u32 sequence, u16 count. Then 9 bytes a citizen: id u8, packed u8 = state (2 bits) +
-- colour set (3 bits) + carries a shopping bag (1 bit, Everything Left 275), x/y/z signed 16-bit in 0.1 stud steps, yaw u8. Hidden citizens are not sent.

local CitizenBuffer = {}

local HEADER = 6
local PER = 9
CitizenBuffer.PER = PER

local function i16(value: number): number
	return math.clamp(math.floor(value * 10 + 0.5), -32768, 32767)
end

function CitizenBuffer.encodeFor(
	sequence: number,
	citizens: { any },
	px: number,
	pz: number,
	radius: number
): buffer
	local picked = {}
	local r2 = radius * radius
	for _, c in citizens do
		if c.state ~= 3 and (c.x - px) ^ 2 + (c.z - pz) ^ 2 <= r2 then
			table.insert(picked, c)
		end
	end
	local b = buffer.create(HEADER + PER * #picked)
	buffer.writeu32(b, 0, sequence % 4294967296)
	buffer.writeu16(b, 4, #picked)
	local o = HEADER
	for _, c in picked do
		buffer.writeu8(b, o, c.id % 256)
		buffer.writeu8(b, o + 1, (c.state % 4) + ((c.color - 1) % 8) * 4 + (if c.bag then 32 else 0))
		buffer.writei16(b, o + 2, i16(c.x))
		buffer.writei16(b, o + 4, i16(c.y))
		buffer.writei16(b, o + 6, i16(c.z))
		local yaw = math.atan2(-c.fx, -c.fz) -- Roblox yaw: CFrame.Angles(0, yaw, 0) faces (fx, fz)
		buffer.writeu8(b, o + 8, math.floor((yaw % (2 * math.pi)) / (2 * math.pi) * 256) % 256)
		o += PER
	end
	return b
end

export type Row = {
	id: number,
	state: number,
	color: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	bag: boolean?,
}

function CitizenBuffer.decode(b: buffer): (number, { Row })
	if buffer.len(b) < HEADER then
		return 0, {}
	end
	local seq = buffer.readu32(b, 0)
	local count = buffer.readu16(b, 4)
	local rows: { Row } = {}
	local o = HEADER
	for _ = 1, count do
		if o + PER > buffer.len(b) then
			break
		end
		local packed = buffer.readu8(b, o + 1)
		table.insert(rows, {
			id = buffer.readu8(b, o),
			state = packed % 4,
			color = math.floor(packed / 4) % 8 + 1,
			bag = math.floor(packed / 32) % 2 == 1,
			x = buffer.readi16(b, o + 2) / 10,
			y = buffer.readi16(b, o + 4) / 10,
			z = buffer.readi16(b, o + 6) / 10,
			yaw = buffer.readu8(b, o + 8) / 256 * 2 * math.pi,
		})
		o += PER
	end
	return seq, rows
end

return CitizenBuffer
