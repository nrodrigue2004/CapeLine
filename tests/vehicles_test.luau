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

	-- the 2026-11-19 remake's budgets: about 6k a car, under about 10k a tram, truck or escort
	local HUB = { CarHatch = 7000, CarSedan = 7000, CarTaxi = 7000, CarBubble = 7000 }

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
			local cap = HUB[look] or 10500
			check(tris <= cap, look .. " is in its phone budget (" .. tris .. " of " .. cap .. " tris)")
			total += tris
		end
		-- 2026-11-19 (gap-vehicles): 46 road wheels split out of the Detail meshes, the same triangles
		check(looks == 12 and meshes == 110, "12 looks in 110 meshes (" .. looks .. ", " .. meshes .. ")")
		check(total <= 95000, "the whole set is in budget (" .. total .. " tris)")
		-- the hub's worst case: every one of the 40 vehicles in its look at once
		local hub = 0
		for _, v in Vehicles.place(Config) do
			for _, f in FIT[VehicleKit.look(v)] or {} do
				hub += f.tris
			end
		end
		check(hub <= 270000, "all 40 hub vehicles together stay in budget (" .. hub .. " tris)")
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
		check(
			has(kit, 'local ROOTS = { "SetPieces", "Vehicles", "Hideout" }'),
			"the meshes come from Art.Vehicles too"
		)
		check(has(kit, "p.CanCollide = false") and has(kit, "p.CanQuery = false"), "a mesh never collides")
		local ts = "src/server/Services/ThrowService.luau"
		check(
			has(ts, "p.CanQuery = if it.query then it.query[p] ~= false else true"),
			"a thrown car's meshes take no queries after landing"
		)
	end)

	-- nate's 2026-11-18 playtest: "plain/grey". The old meshes carried no texture, UVs or material, so every look
	-- read as flat plastic. Each look's body and detail now carry a baked texture set (SurfaceAppearance), the pulled
	-- model has its four maps, and the clone keeps them.
	test("Vehicle art: every look is textured, its maps are imported and kept on the clone", function()
		local ids = fs.readFile("art/models/vehicles_meshids.json")
		for look, fit in FIT do
			local textured = 0
			for name, f in fit do
				check(
					not (f.color[1] == 163 and f.color[2] == 162 and f.color[3] == 165),
					name .. " is not the importer's default grey"
				)
				if f.maps then
					textured += 1
					check(f.mat == "SmoothPlastic", name .. " lets its maps give the material")
					local maps = string.match(ids, '"' .. name .. '%.SurfaceAppearance#maps"%s*:%s*(%b[])')
					check(maps ~= nil, name .. " has its SurfaceAppearance in the pulled model")
					local n = 0
					for id in string.gmatch(maps or "", "%d+") do
						if tonumber(id) and (tonumber(id) :: number) > 0 then
							n += 1
						end
					end
					check(n == 4, name .. " has its colour, normal, roughness and metal maps (" .. n .. ")")
				end
			end
			local wheels = 0
			for _, f in fit do
				wheels += if f.wheel then 1 else 0
			end
			check(
				textured == 2 + wheels,
				look .. " has a textured body, detail and wheels (" .. textured .. ")"
			)
			for name, f in fit do
				if string.sub(name, -4) == "Body" or string.sub(name, -6) == "Detail" then
					check(f.maps == true, name .. " is textured")
				end
			end
		end
		local kit = "src/server/Services/SetPieceMeshes.luau"
		check(
			has(kit, 'if m.maps and c:IsA("SurfaceAppearance") then'),
			"a clone keeps its SurfaceAppearance"
		)
		check(has(kit, "c.AlphaMode = Enum.AlphaMode.Overlay"), "and lets the tint show through its paint")
		local m = SetPieceKit.meshes(Config, { look = "CarSedan", x = 0, y = 0, z = 0 })
		local any = false
		for _, mesh in m do
			any = any or mesh.maps
		end
		check(any, "SetPieceKit hands the maps flag on")
		check(
			has("src/server/Services/IncidentService.luau", 'SetPieceMeshes.ready("CarSedan")'),
			"the towed car wears the sedan look too"
		)
	end)

	-- gap-vehicles (2026-11-19): nate's "trash" list: the wheels did not turn, the escorts glided like the box and
	-- the Dev panel's sample escort kept the motorcade box
	test("Vehicle art: every road wheel is its own textured mesh on its axle", function()
		for look, fit in FIT do
			local n, steer, front = 0, 0, 0
			local axles: { [number]: number } = {}
			for name, f in fit do
				local w = f.wheel
				if w then
					n += 1
					check(f.maps == true, name .. " keeps the look's texture set")
					check(w.r > 0.5 and w.r < 2, name .. " has a wheel's radius (" .. w.r .. ")")
					-- the mesh is centred on its axle and as tall and long as the wheel
					check(math.abs(f.offset[2] - w.r) < 0.05, name .. " stands on the ground at its radius")
					check(math.abs(f.size[2] - 2 * w.r) < 0.1, name .. " is a wheel tall")
					check(math.abs(f.size[3] - 2 * w.r) < 0.1, name .. " is a wheel long")
					check(f.size[1] < 1.6, name .. " is one tyre wide")
					check(string.find(name, "Wheel", 1, true) ~= nil, name .. " is named a wheel")
					local side = string.sub(name, -1)
					check((side == "L") == (f.offset[1] < 0), name .. ": L is -x, R is +x")
					axles[w.axle] = (axles[w.axle] or 0) + 1
					if w.steer then
						steer += 1
						check(w.axle == 0, name .. ": only the front axle steers")
					end
					if w.axle == 0 then
						front += 1
					end
				end
			end
			if look == "Tram" then
				check(n == 0, "the tram's bogies stay in its detail (it never drives)")
			else
				check(n >= 4 and n % 2 == 0, look .. " has its road wheels in pairs (" .. n .. ")")
				check(steer == 2 and front == 2, look .. " steers its two front wheels")
				for axle, count in axles do
					check(count == 2, look .. " axle " .. axle .. " has a wheel each side")
				end
			end
		end
		-- the wheels ride every pose the meshes do, and the devices read them
		local kit = "src/server/Services/SetPieceMeshes.luau"
		check(has(kit, 'p:SetAttribute("WheelR", w.r)'), "a wheel mesh carries its radius")
		check(
			has(kit, 'CollectionService:AddTag(model, "DriveRig")'),
			"a driven vehicle is tagged for the devices"
		)
		local m = SetPieceKit.meshes(Config, { look = "CarSedan", x = 0, y = 0, z = 0 })
		local w = 0
		for _, mesh in m do
			w += if mesh.wheel then 1 else 0
		end
		check(w == 4, "SetPieceKit hands the wheel rows on")
		check(has("art/blender/vkit.py", "def split_wheels(lk):"), "the Blender script splits the wheels")
	end)

	test(
		"Vehicle art: escorts drive, the sample escort is a real vehicle, flipped wheels stay still",
		function()
			check(SetPieceKit.truck("KindTest") ~= nil, "the Dev panel's sample escort has a vehicle look")
			check(
				has("src/server/Services/SideQuestService.luau", 'id = "KindTest"'),
				"KindTest is the Dev panel's kind test chain"
			)
			local bad = VehicleKit.checkEscort(Config, SetPieceKit.truck("KindTest") :: string)
			check(#bad == 0, "and it fits the motorcade box: " .. table.concat(bad, "; "))
			for _, f in { "SideQuestService", "ContractService", "IncidentService" } do
				local path = "src/server/Services/" .. f .. ".luau"
				check(has(path, "DriveMath.step("), f .. " drives its vehicle with DriveMath")
				check(has(path, "DriveMath.pose("), f .. " turns it through rounded corners")
				check(has(path, "SetPieceMeshes.rig("), f .. " rigs its vehicle's meshes for the devices")
			end
			local vs = "src/server/Services/VehicleService.luau"
			check(has(vs, 'models[v.id]:SetAttribute("Wrecked", true)'), "a flipped hub vehicle is wrecked")
			check(has(vs, 'models[id]:SetAttribute("Wrecked", nil)'), "and whole again back home")
			local rig = "src/client/Fx/VehicleRig.luau"
			check(has(rig, 'FrameProf.wrap("VehicleRig"'), "the device rig is under FrameProf")
			check(has(rig, "QualityController.preset.vehicleRig"), "and only near the camera, by preset")
			check(has(rig, 'GetAttribute("Wrecked") == true'), "a wrecked vehicle's wheels stay still")
			check(has(rig, "Workspace:BulkMoveTo("), "all its moves go in one call")
			for _, name in Config.Presets.order do
				local r = Config.Presets[name].vehicleRig
				check(type(r) == "number" and r > 50, name .. " draws vehicles alive near the camera")
			end
			check(
				Config.Presets.low.vehicleRig < Config.Presets.high.vehicleRig,
				"a phone draws fewer alive than a PC"
			)
		end
	)
end
