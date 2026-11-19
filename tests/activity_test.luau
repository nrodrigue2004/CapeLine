-- The open-world activities' props in Blender meshes (2026-11-19, the props gap): art/blender/activity.py's looks
-- over the incident, event and contract props (Shared.ActivityKit, Fx.ActivityProps) and BuildingFx's crater and
-- crack decals. Called from tests/run.luau:
--   require("./activity_test")({ test = test, check = check, Config = Config })
-- ONLY="Activity art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local SetPieceKit = require("../src/shared/SetPieceKit")
	local ActivityKit = require("../src/shared/ActivityKit")
	local FIT = Config.ActivityArt
	local SERVICES = {
		"src/server/Services/SiteKit.luau",
		"src/server/Services/IncidentService.luau",
		"src/server/Services/EventService.luau",
		"src/server/Services/ContractService.luau",
	}
	local src = ""
	for _, p in SERVICES do
		src ..= fs.readFile(p) .. "\n"
	end
	local function has(needle: string): boolean
		return string.find(src, needle, 1, true) ~= nil
	end
	local function num(n: number): string
		return if n == math.floor(n) then string.format("%d", n) else string.format("%g", n)
	end

	-- every prop the tasks list names (Tasks.md "World activity (M6)" and "More activities (2026-11-17)")
	local LISTED = {
		"Tram",
		"Relay",
		"Vault",
		"ShardCrate",
		"Billboard",
		"Balcony",
		"Train",
		"Generator",
		"RescuePad",
		"HoldRing",
		"Valve",
		"Scaffold",
		"CraneLoad",
		"CrateStack",
		"EscortTruck",
		"Airship",
		"Float",
		"Clamp",
		"Gate",
		"Barricade",
		"Charge",
		"Pylon",
		"Parcel",
		"DropPad",
		"Outpost",
		"CityVault",
		"DataTruck",
		"Shard",
	}

	test("Activity art: every listed prop kind has a look, its meshes and fit data", function()
		check(type(FIT) == "table", "Config.ActivityArt is indexed")
		for _, name in LISTED do
			local kind = ActivityKit.kind(name)
			check(kind ~= nil, name .. " is a kind")
			local fit = kind and ActivityKit.fit(Config, kind.look)
			check(
				fit ~= nil and next(fit) ~= nil,
				name .. " has fit data (" .. tostring(kind and kind.look) .. ")"
			)
			for mesh, f in fit or {} do
				check(
					#f.size == 3 and #f.offset == 3 and #f.color == 3,
					mesh .. " has a size, offset and colour"
				)
				check(type(f.mat) == "string", mesh .. " has a material")
			end
		end
		check(FIT[ActivityKit.FOG] ~= nil, "the Harbour fog bank has its look")
		-- every look is used, each in one fit table, every mesh name unique across the sets
		local used = { [ActivityKit.FOG] = true }
		for _, kind in ActivityKit.KINDS do
			used[kind.look] = true
		end
		local names = {}
		for _, set in { Config.SetPieceArt, Config.VehicleArt, Config.HqArt } do
			for _, fit in set do
				for n in fit do
					names[n] = true
				end
			end
		end
		local total = 0
		for look, fit in FIT do
			check(used[look] == true, look .. " dresses a prop")
			check(
				Config.SetPieceArt[look] == nil and Config.VehicleArt[look] == nil,
				look .. " is in one table"
			)
			local tris = 0
			for n, f in fit do
				check(names[n] == nil, n .. " is one mesh name across every set")
				names[n] = true
				tris += f.tris or 0
			end
			-- phone budget: a prop is a few thousand triangles at most
			check(tris > 0 and tris <= 5000, look .. " is in its budget (" .. tris .. " tris)")
			total += tris
		end
		check(total < 60000, "the whole set is under 60k triangles (" .. total .. ")")
	end)

	test("Activity art: the meshes sit over today's parts and tints name real meshes", function()
		local bad = ActivityKit.check(Config, SetPieceKit)
		check(#bad == 0, "looks over their boxes: " .. table.concat(bad, "; "))
	end)

	test("Activity art: hit boxes and targets unchanged, every prop tagged on the server", function()
		for name, kind in ActivityKit.KINDS do
			-- the services still build each box this kit mirrors (sizes from Config are skipped: the drop circle, the ring)
			for _, b in kind.boxes do
				local v = string.format("Vector3.new(%s, %s, %s)", num(b.sx), num(b.sy), num(b.sz))
				-- (a cylinder turned to lie along z is built x-long: the airship's envelope)
				local turned = string.format("Vector3.new(%s, %s, %s)", num(b.sz), num(b.sy), num(b.sx))
				if not (b.shape and b.sy >= 20) then
					check(has(v) or has(turned), name .. ": a service still builds " .. v)
				end
			end
			check(has('"' .. name .. '"'), name .. " is tagged by a service")
		end
		-- the combat targets: lift and radius as the services pass them
		check(has('SiteKit.object("Pylon", at, 6, 4, hp'), "pylon target 6 / 4")
		check(has('SiteKit.object("Train", ev.pos, 6, 11, hp'), "train target 6 / 11")
		check(has("if isTram then 5 else 8") and has("if isTram then 9 else 5"), "tram and relay targets")
		check(has('target(ev, d.model or "Clamp", at, 6, 5, d.hits, true)'), "clamp target 6 / 5")
		check(has('target(ev, d.model or "Float", path[1], 5, 10, d.hits, false)'), "float target 5 / 10")
		check(
			has('target(ev, d.model or "Airship", ev.pos, d.lift or 40, 14, d.hits, false)'),
			"airship target"
		)
		-- the device never touches collision: the meshes are made non-colliding, the parts only hidden locally
		local client = fs.readFile("src/client/Fx/ActivityProps.luau")
		check(string.find(client, "p.CanCollide = false", 1, true) ~= nil, "meshes never collide")
		check(
			string.find(client, "LocalTransparencyModifier = 1", 1, true) ~= nil,
			"parts hidden on the device"
		)
		check(string.find(client, "CanCollide = true", 1, true) == nil, "nothing made solid")
	end)

	test("Activity art: the uploaded model holds every mesh, the textured ones with their maps", function()
		check(fs.isFile("art/models/Activity.rbxm"), "art/models/Activity.rbxm is pulled")
		local ids = fs.readFile("art/models/activity_meshids.json")
		for look, fit in FIT do
			for name, f in fit do
				check(
					string.find(ids, '"' .. name .. '":', 1, true) ~= nil,
					look .. ": " .. name .. " is in the model"
				)
				if f.maps then
					check(
						string.find(ids, '"' .. name .. '.SurfaceAppearance#maps"', 1, true) ~= nil,
						name .. " has its maps"
					)
				end
			end
		end
		check(
			string.find(fs.readFile("default.project.json"), "art/models/Activity.rbxm", 1, true) ~= nil,
			"mapped as Art.Activity"
		)
	end)

	test("Activity art: the device budget by preset", function()
		local lo, md, hi = Config.Presets.low.sites, Config.Presets.medium.sites, Config.Presets.high.sites
		check(lo and md and hi, "every preset has a sites budget")
		check(
			lo.looks < md.looks and md.looks < hi.looks and lo.parts < md.parts and lo.radius < md.radius,
			"low draws least"
		)
		local cands = {}
		for i = 1, 20 do
			table.insert(cands, { id = i, dist = i * 30, meshes = 3 })
		end
		local got = ActivityKit.pick(cands, lo)
		local n = 0
		for id in got do
			n += 1
			check(id * 30 <= lo.radius, "within the radius")
		end
		check(n <= lo.looks and n * 3 <= lo.parts and n > 0, "within the looks and parts caps (" .. n .. ")")
		check(got[1] == true, "nearest first")
		-- a ring scales across x and z only
		local ring = ActivityKit.KINDS.HoldRing
		local one = ActivityKit.meshes(Config, ring, 1)
		local two = ActivityKit.meshes(Config, ring, 2)
		check(
			math.abs(two[1].size[1] - one[1].size[1] * 2) < 1e-6 and two[1].size[2] == one[1].size[2],
			"ring scale"
		)
		check(
			ActivityKit.hides(ring, "Ring") == false and ActivityKit.hides(ring, "Root") == false,
			"keeps the disc"
		)
	end)

	test("Activity art: crater and crack decals with the old look as fallback", function()
		local d = Config.Destruction.decals
		check(d and d.crater and d.crack, "Config.Destruction.decals")
		for key, row in d do
			check(type(row.id) == "number" and row.id >= 0, key .. " id")
			check(fs.isFile("art/export/fx/" .. row.file), key .. " is drawn: " .. row.file)
		end
		local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
		check(string.find(fx, "ink.id ~= 0", 1, true) ~= nil, "BuildingFx falls back while an id is 0")
	end)
end
