--!strict
-- Vehicles: the 40 cars, trucks and trams parked in the hub and the scripted flip (spec: Destruction "Cars
-- and trams: 40 vehicles in the hub; flips are scripted arcs; reset 30 s later"; Clash moments > Vehicle
-- flip "Any heavy hit on a car or tram: scripted flip arc of 1 s"). Pure, so the server and every client
-- agree on where each one stands and how it flips.
-- Cars line Downtown's north-south streets, trams sit on two east-west lines, Old Town has small cars, the
-- Docks two trucks. Nothing parks in an intersection.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local Vehicles = {}

export type Vehicle = {
	id: number,
	kind: string, -- car, tram, truck
	district: string,
	x: number,
	y: number, -- the bottom of the body
	z: number,
	ry: number, -- degrees: 0 = long axis along z
	color: string,
	sx: number,
	sy: number,
	sz: number,
	-- where its middle may land after a flip so it stays on its own road (never in a building or on a block)
	room: { x0: number, x1: number, z0: number, z1: number },
}

local SIZE = {
	car = { 6, 4.5, 11 },
	tram = { 9, 10, 34 },
	truck = { 8, 9, 20 },
}
Vehicles.SIZE = SIZE

local CAR_COLORS = { "containerA", "containerB", "containerC", "white", "containerD", "roofBlue" }

function Vehicles.place(Config: any): { Vehicle }
	local city = Config.City
	local V = Config.Destruction.vehicles
	local rng = Rng.new(Rng.hash(city.downtown.seed, 40))
	local list: { Vehicle } = {}
	local gy = city.ground.y
	-- room: the road's edges (x0, x1, z0, z1) its footprint must stay inside when it lands
	local function add(
		kind: string,
		district: string,
		x: number,
		z: number,
		ry: number,
		color: string?,
		road: { x0: number, x1: number, z0: number, z1: number }
	)
		local s = SIZE[kind]
		local hx = (if ry % 180 == 90 then s[3] else s[1]) / 2 + 0.5
		local hz = (if ry % 180 == 90 then s[1] else s[3]) / 2 + 0.5
		table.insert(list, {
			id = #list + 1,
			kind = kind,
			district = district,
			x = x,
			y = gy + 0.2,
			z = z,
			ry = ry,
			color = color or CAR_COLORS[rng:int(1, #CAR_COLORS)],
			sx = s[1],
			sy = s[2],
			sz = s[3],
			room = {
				x0 = math.min(x, road.x0 + hx),
				x1 = math.max(x, road.x1 - hx),
				z0 = math.min(z, road.z0 + hz),
				z1 = math.max(z, road.z1 - hz),
			},
		})
	end
	local far = 1e6 -- along a street: no edge (the flip's own travel is far shorter than a block)
	-- Downtown: streets every 140 studs between 110-stud blocks
	local d = city.districts.Downtown
	local t = city.downtown
	local pitch = t.block + t.street
	local nStreets = math.floor((d.maxX - d.minX) / pitch) + 1
	local slots = {}
	for k = 1, nStreets - 2 do -- the inner streets (the outer ones are half on the grass)
		local x = d.minX + k * pitch
		for m = 0, math.floor((d.maxZ - d.minZ) / pitch) - 1 do
			local z = d.minZ + pitch / 2 + m * pitch
			for _, lane in { -1, 1 } do
				for _, off in { -22, 22 } do
					table.insert(slots, { x + lane * 8, z + off, x })
				end
			end
		end
	end
	local cars = V.count - V.trams - 12
	for _ = 1, cars do
		local k = rng:int(1, #slots)
		local s = table.remove(slots, k) :: { number }
		-- s[3]: the middle of its street (Downtown's streets are t.street wide)
		add("car", "Downtown", s[1], s[2], 0, nil, {
			x0 = s[3] - t.street / 2,
			x1 = s[3] + t.street / 2,
			z0 = -far,
			z1 = far,
		})
	end
	-- trams: two east-west lines through the first 700 x 700 (downtown.core), 4 trams each
	local core = t.core or d
	local lines = { core.minZ + pitch * 2, core.minZ + pitch * 4 }
	for li, z in lines do
		for k = 1, V.trams / #lines do
			local x = core.minX + pitch / 2 + (k - 1) * pitch * 1.25 + li * 20
			add(
				"tram",
				"Downtown",
				x,
				z,
				90,
				if li == 1 then "containerC" else "containerB",
				{ x0 = -far, x1 = far, z0 = z - t.street / 2, z1 = z + t.street / 2 }
			)
		end
	end
	-- Old Town: small cars on the narrow streets, one lane
	local o = city.districts.OldTown
	local ot = city.oldTown
	local op = ot.block + ot.street
	for k = 1, 10 do
		local col = (k - 1) % 7 + 1
		local row = ((k - 1) * 3 + ((k - 1) // 7) * 2) % 7
		local x = o.minX + col * op
		local z = o.minZ + op / 2 + row * op
		add("car", "OldTown", x + 3, z, 0, nil, {
			x0 = x - ot.street / 2,
			x1 = x + ot.street / 2,
			z0 = -far,
			z1 = far,
		})
	end
	-- the Docks: two trucks between the warehouses and the Foundry
	local lane = city.docks.lane
	local laneRoad = { x0 = lane.minX, x1 = lane.maxX, z0 = lane.minZ, z1 = lane.maxZ }
	add("truck", "Docks", 200, 565, 90, "containerA", laneRoad)
	add("truck", "Docks", 300, 565, 90, "white", laneRoad)
	return list
end

-- The flip at fraction t (0..1) pushed along (dx, dz): lift, travel and roll. The vehicle lands upside down.
-- Returns the offset (ox, oy, oz) and the roll angle in radians about the axis (dz, 0, -dx).
-- The travel is cut where the vehicle's road ends (v.room), so a car pushed toward the kerb rolls over on
-- the spot instead of landing in the building behind the sidewalk (travel audit, 2026-11-18).
function Vehicles.flipPose(
	cfg: any,
	v: Vehicle,
	t: number,
	dx: number,
	dz: number
): (number, number, number, number)
	local V = cfg.vehicles
	t = math.clamp(t, 0, 1)
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		dx, dz, len = 1, 0, 1
	end
	dx, dz = dx / len, dz / len
	local lift = V.flipHeight * (if v.kind == "tram" then 0.5 else 1)
	local travel = V.flipTravel * (if v.kind == "tram" then 0.5 else 1)
	local lx, lz = dx * travel, dz * travel
	local room = v.room
	if room then
		lx = math.clamp(v.x + lx, room.x0, room.x1) - v.x
		lz = math.clamp(v.z + lz, room.z0, room.z1) - v.z
	end
	local oy = 4 * lift * t * (1 - t) + v.sy * math.sin(t * math.pi) * 0.5
	return lx * t, oy, lz * t, math.pi * t
end

-- Is (x, z) in a vehicle's home spot (its footprint plus a hero's width)? The reset waits for it to clear,
-- so a car never comes back on top of someone standing where it was parked.
function Vehicles.occupied(v: Vehicle, x: number, z: number, pad: number?): boolean
	local p = pad or 2
	local a = math.rad(v.ry)
	local ddx, ddz = x - v.x, z - v.z
	local lx = ddx * math.cos(a) - ddz * math.sin(a)
	local lz = ddx * math.sin(a) + ddz * math.cos(a)
	return math.abs(lx) <= v.sx / 2 + p and math.abs(lz) <= v.sz / 2 + p
end

return Vehicles
