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
	local function add(kind: string, district: string, x: number, z: number, ry: number, color: string?)
		local s = SIZE[kind]
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
		})
	end
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
					table.insert(slots, { x + lane * 8, z + off })
				end
			end
		end
	end
	local cars = V.count - V.trams - 12
	for _ = 1, cars do
		local k = rng:int(1, #slots)
		local s = table.remove(slots, k) :: { number }
		add("car", "Downtown", s[1], s[2], 0)
	end
	-- trams: two east-west lines, 4 trams each
	local lines = { d.minZ + pitch * 2, d.minZ + pitch * 4 }
	for li, z in lines do
		for k = 1, V.trams / #lines do
			local x = d.minX + pitch / 2 + (k - 1) * pitch * 1.25 + li * 20
			add("tram", "Downtown", x, z, 90, if li == 1 then "containerC" else "containerB")
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
		add("car", "OldTown", x + 3, z, 0)
	end
	-- the Docks: two trucks between the warehouses and the Foundry
	add("truck", "Docks", 200, 565, 90, "containerA")
	add("truck", "Docks", 300, 565, 90, "white")
	return list
end

-- The flip at fraction t (0..1) pushed along (dx, dz): lift, travel and roll. The vehicle lands upside down.
-- Returns the offset (ox, oy, oz) and the roll angle in radians about the axis (dz, 0, -dx).
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
	local travel = V.flipTravel * (if v.kind == "tram" then 0.5 else 1) * t
	local oy = 4 * lift * t * (1 - t) + v.sy * math.sin(t * math.pi) * 0.5
	return dx * travel, oy, dz * travel, math.pi * t
end

return Vehicles
