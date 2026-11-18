-- The escort and hub vehicle meshes (2026-11-18): art/blender/vehicles.py's looks for the side quests' escort
-- trucks (Shared.SetPieceKit.TRUCKS) and the hub's 40 cars, trams and trucks (Shared.VehicleKit). Called from
-- tests/run.luau:
--   require("./vehicles_test")({ test = test, check = check, Config = Config })
-- ONLY="Vehicle art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local SetPieceKit = require("../src/shared/SetPieceKit")
	local VehicleKit = require("../src/shared/VehicleKit")
	local Vehicles = require("../src/shared/Vehicles")
	local FIT = Config.VehicleArt

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- does this chain (any step, either side) have an escort goal?
	local function escorts(t: any, seen: { [any]: boolean }?): boolean
		local s = seen or {}
		if type(t) ~= "table" or s[t] then
			return false
		end
		s[t] = true
		if t.kind == "escort" then
			return true
		end
		for _, v in t do
			if escorts(v, s) then
				return true
			end
		end
		return false
	end

	local HUB =
		{ CarHatch = 1000, CarSedan = 1000, CarTaxi = 1000, CarBubble = 1000, Tram = 1500, DockTruck = 1500 }

	test("Vehicle art: the fit table, one look each, all in the phone budget", function()
		check(type(FIT) == "table", "Config.VehicleArt is indexed")
		local used: { [string]: boolean } = {}
		for _, look in SetPieceKit.TRUCKS do
			used[look] = true
		end
		for _, v in Vehicles.place(Config) do
			used[VehicleKit.look(v)] = true
		end
		local names: { [string]: boolean } = {}
		for _, fit in Config.SetPieceArt do
			for name in fit do
				names[name] = true
			end
		end
		local looks, meshes, total = 0, 0, 0
		for look, fit in FIT do
			looks += 1
			check(used[look] == true, look .. " is used by an escort or a hub vehicle")
			check(Config.SetPieceArt[look] == nil, look .. " is in one fit table only")
			local tris = 0
			for name, f in fit do
				meshes += 1
				check(names[name] == nil, name .. " is one mesh name across the set pieces and the vehicles")
				names[name] = true
				check(
					#f.size == 3 and #f.offset == 3 and #f.color == 3,
					name .. " has a size, offset and colour"
				)
				for _, s in f.size do
					check(s > 0, name .. " has a positive size")
				end
				check(type(f.mat) == "string" and #f.mat > 0, name .. " has a material")
				check(f.alpha == nil or (f.alpha > 0 and f.alpha < 1), name .. " is see-through or solid")
				check(type(f.tris) == "number" and f.tris > 0, name .. " counts its triangles")
				tris += f.tris or 0
			end
			local cap = HUB[look] or 2500
			check(tris <= cap, look .. " is in its phone budget (" .. tris .. " of " .. cap .. " tris)")
			total += tris
		end
		check(looks == 12 and meshes == 87, "12 looks in 87 meshes (" .. looks .. ", " .. meshes .. ")")
		check(total <= 18000, "the whole set is in budget (" .. total .. " tris)")
		-- the hub's worst case: every one of the 40 vehicles in its look at once
		local hub = 0
		for _, v in Vehicles.place(Config) do
			for _, f in FIT[VehicleKit.look(v)] or {} do
				hub += f.tris
			end
		end
		check(hub <= 40000, "all 40 hub vehicles together stay light (" .. hub .. " tris)")
		check(fs.isFile("art/export/Vehicles.fbx"), "the meshes are exported for nate's import")
		check(fs.isFile("art/preview/vehicles.png"), "and previewed")
		check(has("src/config/init.luau", '"VehicleArt"'), "the config index lists it")
		check(has("art/blender/vehicles.py", "Vehicles.fbx"), "the script writes the FBX")
	end)

	test("Vehicle art: every side quest escort has its own truck look over the motorcade box", function()
		local n = 0
		for _, ch in Config.SideQuests.chains do
			if escorts(ch) and not ch.dev then
				n += 1
				local look = SetPieceKit.truck(ch.id)
				check(look ~= nil, ch.id .. "'s escort has a truck look")
				if look then
					local bad = VehicleKit.checkEscort(Config, look)
					check(#bad == 0, ch.id .. ": " .. table.concat(bad, "; "))
				end
			end
		end
		check(n == 7, "the 7 chains with an escort are all dressed (" .. n .. ")")
		for chain in SetPieceKit.TRUCKS do
			local found = false
			for _, ch in Config.SideQuests.chains do
				found = found or (ch.id == chain and escorts(ch))
			end
			check(found, chain .. " is a side quest chain with an escort")
		end
		-- the looks stand over the boxes SideQuestService really builds (nose to -z, the cab forward)
		local sq = "src/server/Services/SideQuestService.luau"
		check(
			has(sq, "Vector3.new(7, 4, 14), CFrame.new(0, 2.5, 0)"),
			"the motorcade body is VehicleKit.ESCORT[1]"
		)
		check(has(sq, "Vector3.new(6.6, 2.4, 6), CFrame.new(0, 5.6, -2)"), "and its cab VehicleKit.ESCORT[2]")
		check(has(sq, "SetPieceMeshes.ready(look)"), "a truck is dressed only once its look is imported")
		-- the check catches a look that is not truck sized
		check(#VehicleKit.checkEscort(Config, "CarHatch") > 0, "a car over the motorcade box is caught")
		check(#VehicleKit.checkEscort(Config, "NoSuchLook") > 0, "an unknown look is caught")
	end)

	test("Vehicle art: each hub vehicle's look sits over its parts in its own paint", function()
		local P = Config.City.palette
		local count: { [string]: number } = {}
		for _, v in Vehicles.place(Config) do
			local look = VehicleKit.look(v)
			count[look] = (count[look] or 0) + 1
			local bad = VehicleKit.check(Config, v)
			check(#bad == 0, "vehicle " .. v.id .. ": " .. table.concat(bad, "; "))
			if v.kind == "tram" then
				check(look == "Tram", "a tram is a Tram")
			elseif v.kind == "truck" then
				check(look == "DockTruck", "a Docks truck is a DockTruck")
			elseif v.district == "OldTown" then
				check(look == "CarBubble", "Old Town's cars are the little round car")
			else
				check(table.find(VehicleKit.DOWNTOWN, look) ~= nil, "a Downtown car is a Downtown look")
			end
			local pl = VehicleKit.place(Config, v)
			check(
				pl.x == 0 and pl.y == 0 and pl.z == 0 and pl.ry == 0,
				"the look stands at the vehicle's root"
			)
			local body = VehicleKit.BODY[look]
			if body then
				local paint = pl.tint and pl.tint[body]
				check(paint ~= nil, "vehicle " .. v.id .. "'s body takes its paint")
				check(FIT[look][body] ~= nil, look .. " paints its own body mesh " .. tostring(body))
				local want = VehicleKit.PAINT[v.color] or P[v.color]
				check(paint == want, "vehicle " .. v.id .. " is painted its own colour " .. v.color)
			else
				check(look == "CarTaxi" and pl.tint == nil, "only the taxi keeps its own colour")
			end
			for key in VehicleKit.PAINT do
				check(P[key] ~= nil, key .. " is a palette colour")
			end
			-- the parts are the same boxes as before the meshes: the body first, four wheels
			local parts = VehicleKit.parts(v)
			check(
				parts[1].tone == "body" and parts[1].size[3] == v.sz,
				"the body part comes first (the root)"
			)
			local wheels = 0
			for _, p in parts do
				wheels += if p.wheel then 1 else 0
			end
			check(wheels == 4, "four wheels")
		end
		check(
			(count.CarTaxi or 0) >= 2 and (count.CarHatch or 0) >= 4 and (count.CarSedan or 0) >= 4,
			"a mix of cars"
		)
		check(
			count.CarBubble == 10 and count.Tram == 8 and count.DockTruck == 2,
			"the bubble cars, trams and trucks"
		)
		-- the check catches a look over the wrong size of vehicle
		local big = table.clone(Vehicles.place(Config)[1])
		big.sx, big.sz = 12, 30
		check(#VehicleKit.check(Config, big) > 0, "a car look over a much bigger box is caught")
	end)

	test("Vehicle art: before the import every vehicle is its parts; after, whole looks only", function()
		local none = function(_: string)
			return false
		end
		local all = function(_: string)
			return true
		end
		local looks: { string } = {}
		for look in FIT do
			table.insert(looks, look)
		end
		for _, look in looks do
			check(not SetPieceKit.ready(Config, look, none), look .. " waits for the import")
			check(SetPieceKit.ready(Config, look, all), look .. " is drawn after it")
			local miss = next(FIT[look])
			check(not SetPieceKit.ready(Config, look, function(n: string)
				return n ~= miss
			end), look .. " short of one mesh keeps its parts")
		end
		-- a paint replaces only its body's colour; the meshes come sorted with their fit
		local m = SetPieceKit.meshes(
			Config,
			{ look = "CarHatch", x = 0, y = 0, z = 0, tint = { CarHatchBody = { 1, 2, 3 } } }
		)
		for _, mesh in m do
			if mesh.name == "CarHatchBody" then
				check(mesh.color[1] == 1 and mesh.color[3] == 3, "the body takes the paint")
			else
				check(mesh.color == FIT.CarHatch[mesh.name].color, mesh.name .. " keeps its colour")
			end
		end
	end)

	test("Vehicle art: the services draw the meshes over hidden parts that keep their collision", function()
		local vs = "src/server/Services/VehicleService.luau"
		check(has(vs, "for i, b in VehicleKit.parts(v) do"), "the parts come from VehicleKit")
		check(has(vs, "local dressed = SetPieceMeshes.ready(place.look)"), "a look needs all its meshes")
		check(has(vs, "SetPieceMeshes.hide(p)"), "its parts hide (and keep colliding)")
		check(has(vs, 'mesh:SetAttribute("Offset", mesh.CFrame)'), "the meshes move with every pose")
		local kit = "src/server/Services/SetPieceMeshes.luau"
		check(has(kit, 'local ROOTS = { "SetPieces", "Vehicles" }'), "the meshes come from Art.Vehicles too")
		check(has(kit, "p.CanCollide = false") and has(kit, "p.CanQuery = false"), "a mesh never collides")
		local ts = "src/server/Services/ThrowService.luau"
		check(
			has(ts, "p.CanQuery = if it.query then it.query[p] ~= false else true"),
			"a thrown car's meshes take no queries after landing"
		)
	end)
end
