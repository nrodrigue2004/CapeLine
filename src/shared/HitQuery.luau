--!strict
-- HitQuery: target finding for abilities as pure geometry (spec: Hit resolution). The server passes the
-- candidates (enemies, and flagged players from M8) and a line-of-sight callback that raycasts the city.
-- A candidate is { id, x, y, z, r }.

local HitQuery = {}

export type Candidate = { id: number, x: number, y: number, z: number, r: number }
export type LosFn = (ox: number, oy: number, oz: number, tx: number, ty: number, tz: number) -> boolean

local function norm(x: number, y: number, z: number): (number, number, number, number)
	local l = math.sqrt(x * x + y * y + z * z)
	if l < 1e-6 then
		return 0, 0, 0, 0
	end
	return x / l, y / l, z / l, l
end
HitQuery.norm = norm

-- Angle in degrees between the aim and the direction to a point
local function angleTo(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	c: Candidate
): (number, number)
	local tx, ty, tz, dist = norm(c.x - ox, c.y - oy, c.z - oz)
	if dist < 1e-6 then
		return 0, 0
	end
	local dot = math.clamp(dx * tx + dy * ty + dz * tz, -1, 1)
	return math.deg(math.acos(dot)), dist
end
HitQuery.angleTo = angleTo

local function byId(candidates: { Candidate }, id: number): Candidate?
	for _, c in candidates do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- Single target along the aim: the hint if it is in range and near the aim line, else the first candidate
-- whose body the fat ray touches.
function HitQuery.bolt(
	ox: number,
	oy: number,
	oz: number,
	aimX: number,
	aimY: number,
	aimZ: number,
	range: number,
	radius: number,
	hintId: number?,
	slackDeg: number,
	candidates: { Candidate },
	los: LosFn?
): Candidate?
	local dx, dy, dz = norm(aimX, aimY, aimZ)
	if hintId and hintId > 0 then
		local c = byId(candidates, hintId)
		if c then
			local ang, dist = angleTo(ox, oy, oz, dx, dy, dz, c)
			local bodySlack = if dist > 0 then math.deg(math.atan((c.r + radius) / dist)) else 90
			if dist <= range + c.r and ang <= slackDeg + bodySlack then
				if not los or los(ox, oy, oz, c.x, c.y, c.z) then
					return c
				end
			end
		end
	end
	local best: Candidate? = nil
	local bestT = math.huge
	for _, c in candidates do
		local rx, ry, rz = c.x - ox, c.y - oy, c.z - oz
		local t = rx * dx + ry * dy + rz * dz
		if t > 0 and t <= range + c.r and t < bestT then
			local px, py, pz = rx - dx * t, ry - dy * t, rz - dz * t
			local perp = math.sqrt(px * px + py * py + pz * pz)
			if perp <= radius + c.r and (not los or los(ox, oy, oz, c.x, c.y, c.z)) then
				best, bestT = c, t
			end
		end
	end
	return best
end

-- Nearest candidate inside a cone (degrees, full width) and range
function HitQuery.cone(
	ox: number,
	oy: number,
	oz: number,
	aimX: number,
	aimY: number,
	aimZ: number,
	range: number,
	coneDeg: number,
	candidates: { Candidate },
	los: LosFn?,
	exclude: { [number]: boolean }?
): Candidate?
	local dx, dy, dz = norm(aimX, aimY, aimZ)
	local best: Candidate? = nil
	local bestDist = math.huge
	for _, c in candidates do
		if not (exclude and exclude[c.id]) then
			local ang, dist = angleTo(ox, oy, oz, dx, dy, dz, c)
			if dist <= range + c.r and ang <= coneDeg / 2 and dist < bestDist then
				if not los or los(ox, oy, oz, c.x, c.y, c.z) then
					best, bestDist = c, dist
				end
			end
		end
	end
	return best
end

-- Chain: start at `first`, then jump to the nearest unhit candidate within `jump` studs, `count` targets total
function HitQuery.chain(
	first: Candidate,
	candidates: { Candidate },
	count: number,
	jump: number,
	los: LosFn?
): { Candidate }
	local hits = { first }
	local used = { [first.id] = true }
	local cur = first
	while #hits < count do
		local best: Candidate? = nil
		local bestDist = math.huge
		for _, c in candidates do
			if not used[c.id] then
				local _, _, _, dist = norm(c.x - cur.x, c.y - cur.y, c.z - cur.z)
				if
					dist <= jump + c.r
					and dist < bestDist
					and (not los or los(cur.x, cur.y, cur.z, c.x, c.y, c.z))
				then
					best, bestDist = c, dist
				end
			end
		end
		if not best then
			break
		end
		table.insert(hits, best)
		used[best.id] = true
		cur = best
	end
	return hits
end

-- Everything within `width` of the segment from (ax, ay, az) to (bx, by, bz): the Dash Strike path
function HitQuery.capsule(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	width: number,
	candidates: { Candidate }
): { Candidate }
	local sx, sy, sz = bx - ax, by - ay, bz - az
	local len2 = sx * sx + sy * sy + sz * sz
	local out = {}
	for _, c in candidates do
		local t = 0
		if len2 > 1e-6 then
			t = math.clamp(((c.x - ax) * sx + (c.y - ay) * sy + (c.z - az) * sz) / len2, 0, 1)
		end
		local px, py, pz = ax + sx * t - c.x, ay + sy * t - c.y, az + sz * t - c.z
		if math.sqrt(px * px + py * py + pz * pz) <= width + c.r then
			table.insert(out, c)
		end
	end
	return out
end

return HitQuery
