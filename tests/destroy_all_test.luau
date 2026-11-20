-- destroy-all (2026-11-20, nate 2026-11-19: "destroy EVERYTHING, including silos and terrain, and fly through
-- buildings"). The audit's last whole things, made breakable through the existing paths:
-- * the park's structures (bandshell, carousel, boathouse, bridges, rink, fountains, gate pillars and signs) and the
--   Deep's coral and small wreck props: Blender looks over hidden collision boxes, now one Dress group a look
--   (Shared.StreetBreak.parkDress / deepDress; ParkBuilder and CityBuilder set the keys, BuildingFx breaks them);
-- * vehicles under rams, heavy landings and boss slams (ImpactService, BossService -> VehicleService.hit);
-- * the park's Terrain lawns dig dry bowls (CraterRules.waterLevel), the sea splashes (BuildingImpact kind 5).
-- Called from tests/run.luau; ONLY="Destroy all" runs just these. The park build runs the place's own ParkBuilder
-- headless (Lune Instances; Terrain writes are not modelled).

return function(T: any)
	local test, check, Config, world, placePath = T.test, T.check, T.Config, T.world, T.place
	local fs = require("@lune/fs")
	local StreetBreak = require("../src/shared/StreetBreak")
	local CraterRules = require("../src/shared/CraterRules")
	local ParkLayout = require("../src/shared/ParkLayout")
	local DeepLayout = require("../src/shared/DeepLayout")
	local DeepArtKit = require("../src/shared/DeepArtKit")

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	local STRUCTURES = {
		"Bandshell",
		"Carousel",
		"Boathouse",
		"BowBridge",
		"StoneBridge",
		"Rink",
		"Terrace",
		"SmallFountain",
		"GatePillar",
		"GateSign",
	}
	local BIG =
		{ Bandshell = true, Carousel = true, Boathouse = true, BowBridge = true, Rink = true, Terrace = true }

	test("Destroy all: every park structure breaks as one look with its collision boxes", function()
		local park = world.park
		check(park ~= nil and #park.solid > 0, "the park is in the world")
		local dress = StreetBreak.parkDress(park)
		local boxes, meshes = 0, 0
		for i in park.solid do
			if dress.box[i] then
				boxes += 1
			end
		end
		check(
			boxes == #park.solid,
			string.format("every collision box is in a group (%d of %d)", boxes, #park.solid)
		)
		local byLook: { [string]: { [string]: boolean } } = {}
		local bigOf: { [string]: boolean } = {}
		local smallOf: { [string]: boolean } = {}
		for i, m in park.meshes do
			local key = dress.mesh[i]
			if m.breaks then
				check(key == nil, "a wall or rail length stays a plain street prop (" .. m.look .. ")")
			elseif key then
				meshes += 1
				byLook[m.look] = byLook[m.look] or {}
				byLook[m.look][key] = true
				if dress.big[key] then
					bigOf[m.look] = true
				else
					smallOf[m.look] = true
				end
			end
		end
		for _, look in STRUCTURES do
			local n = 0
			for _ in byLook[look] or {} do
				n += 1
			end
			check(n >= 1, look .. " is a break group (" .. n .. " placed)")
			if BIG[look] then
				check(bigOf[look] == true, look .. " is big: only a heavy hit or a ram breaks it")
			end
		end
		check(
			smallOf.GatePillar == true,
			"a plain gate pillar goes with any knock, like a tree (a signed one with its arch: heavy)"
		)
		check(bigOf.SmallFountain ~= true, "a small fountain goes with any knock")
		check(dress.count >= #STRUCTURES, "groups " .. dress.count)
		-- the boxes of one group sit with its meshes (no box joins a look across the park)
		local centre: { [string]: { number } } = {}
		for i, m in park.meshes do
			local key = dress.mesh[i]
			if key and not centre[key] then
				centre[key] = { m.x, m.z }
			end
		end
		local far = 0
		for i, b in park.solid do
			local c = centre[dress.box[i]]
			if c and math.sqrt((b.cx - c[1]) ^ 2 + (b.cz - c[2]) ^ 2) > 80 then
				far += 1
			end
		end
		check(far == 0, "every box is next to its look's meshes (" .. far .. " far)")
		check(meshes > 0, "meshes in groups " .. meshes)
	end)

	test(
		"Destroy all: the Deep's coral and small wreck props break with their looks; caches never",
		function()
			local deep = DeepLayout.build(Config)
			local ready = {}
			for look in Config.DeepArt or {} do
				ready[look] = true
			end
			local dress = StreetBreak.deepDress(deep.boxes, deep.art, ready)
			local coral, grouped, caches, left = 0, 0, 0, {}
			for i, b in deep.boxes do
				if b.kind == "prop" then
					if b.tag == "cache" then
						caches += 1
						check(dress.box[i] == nil, "a cache is a pickup: never knocked loose")
					elseif dress.box[i] then
						grouped += 1
						if string.sub(b.color, 1, 5) == "coral" then
							coral += 1
						end
					elseif DeepArtKit.hides(b, ready) then
						local fx, fz = b.sx, b.sz
						if StreetBreak.groupKind(fx, b.sy, fz) == "whole" then
							table.insert(left, b.color .. " " .. math.floor(b.sx) .. "x" .. math.floor(b.sy))
						end
					end
				end
			end
			check(caches > 0, "caches found")
			check(coral >= 100, "the coral heads break (" .. coral .. ")")
			check(#left == 0, "no hidden small prop is left unbreakable (" .. (left[1] or "none") .. ")")
			for i, key in dress.box do
				local j = tonumber(string.sub(key, 2))
				local p = j and deep.art[j]
				check(
					p ~= nil and p.look == deep.boxes[i].art,
					"a box's group is a placement of its own look"
				)
				if p then
					local b = deep.boxes[i]
					local d = math.sqrt((p.cx - b.cx) ^ 2 + (p.cy - b.cy) ^ 2 + (p.cz - b.cz) ^ 2)
					check(d <= math.max(p.sx, p.sy, p.sz), "and round it")
				end
			end
			check(grouped > 0 and dress.count > 0, "groups " .. dress.count)
		end
	)

	test(
		"Destroy all: park lawns dig dry bowls, the lake's bank lets the lake in, the sea as before",
		function()
			local G = Config.Destruction.ground
			local park = world.park
			local sea = Config.World.coast.waterY
			local b = park.bounds
			-- a lawn point: inside the park, far from every water
			local lawn: { number }? = nil
			for x = b.minX + 60, b.maxX - 60, 20 do
				for z = b.minZ + 60, b.maxZ - 60, 20 do
					local dry = true
					for _, w in park.waters do
						if ParkLayout.inside(w, x, z) > -40 then
							dry = false
						end
					end
					if dry and not lawn then
						lawn = { x, z }
					end
				end
			end
			check(lawn ~= nil, "a lawn point")
			local lx, lz = (lawn :: any)[1], (lawn :: any)[2]
			check(
				CraterRules.waterLevel(G, park, sea, lx, lz, ParkLayout.inside) == -math.huge,
				"a lawn crater never fills with water"
			)
			local w = park.waters[1]
			local c0 = w.blobs[1]
			local shore = { c0[1] + c0[3] + 2, c0[2] } -- just past the first blob's edge
			local lv = CraterRules.waterLevel(G, park, sea, shore[1], shore[2], ParkLayout.inside)
			check(
				lv > -math.huge and lv <= 0,
				"a crater on the bank fills to a park water's level (" .. lv .. ")"
			)
			check(
				CraterRules.waterLevel(G, park, sea, 5000, 5000, ParkLayout.inside) == sea,
				"outside: the sea line"
			)
			check(CraterRules.waterLevel(G, nil, sea, lx, lz, nil) == sea, "no park: the sea line")
			-- the real carve on a small grass block at the lawn: everything dug is Air
			local crater = { id = 1, x = lx, y = 0, z = lz, r = 8, ground = "terrain", born = 0 }
			local lo = CraterRules.region(G, crater)
			local hi = select(2, CraterRules.region(G, crater))
			local nx, ny, nz = (hi[1] - lo[1]) / G.voxel, (hi[2] - lo[2]) / G.voxel, (hi[3] - lo[3]) / G.voxel
			local mats, occ = {}, {}
			for i = 1, nx do
				mats[i], occ[i] = {}, {}
				for j = 1, ny do
					mats[i][j], occ[i][j] = {}, {}
					for k = 1, nz do
						mats[i][j][k] = "Grass"
						occ[i][j][k] = 1
					end
				end
			end
			local waterY = CraterRules.waterLevel(G, park, sea, lx, lz, ParkLayout.inside)
			local dug = CraterRules.carve(G, crater, lo, mats, occ, waterY)
			local wet = 0
			for i = 1, nx do
				for j = 1, ny do
					for k = 1, nz do
						if mats[i][j][k] == "Water" then
							wet += 1
						end
					end
				end
			end
			check(dug > 0 and wet == 0, string.format("dug %d voxels, %d turned to water", dug, wet))
			-- the sea line as before would have flooded it (the bug the park's lawns had)
			local m2, o2 = {}, {}
			for i = 1, nx do
				m2[i], o2[i] = {}, {}
				for j = 1, ny do
					m2[i][j], o2[i][j] = {}, {}
					for k = 1, nz do
						m2[i][j][k] = "Grass"
						o2[i][j][k] = 1
					end
				end
			end
			CraterRules.carve(G, crater, lo, m2, o2, sea)
			local wet2 = 0
			for i = 1, nx do
				for j = 1, ny do
					for k = 1, nz do
						if m2[i][j][k] == "Water" then
							wet2 += 1
						end
					end
				end
			end
			check(wet2 > 0, "(with the sea line it would have filled " .. wet2 .. " voxels)")
			check(
				CraterRules.inPark(park, lx, lz) and not CraterRules.inPark(park, 5000, 5000),
				"in the park or not"
			)
		end
	)

	test("Destroy all: every path reaches the new breakables (source)", function()
		local fx = "src/client/Fx/BuildingFx.luau"
		check(has(fx, 'local dress = p:GetAttribute("Dress")'), "smashStreet breaks dressed looks")
		check(has(fx, "breakDress(p, dress, center, heavy)"), "as one group")
		check(
			has(fx, "local heavy = heavyIn == true or only ~= nil or radius >= (ST.bigRadius"),
			"big ones: heavy only"
		)
		check(has(fx, "smashStreet(center, radius, nil, true)"), "a ram relayed from another hero is heavy")
		check(has(fx, "return ramVehicle(car, part, at)"), "a ram into a vehicle goes through it")
		check(has(fx, "if kind == 5 then"), "the sea splash is drawn")
		check(has(fx, 'AudioController.play("splash", center'), "with the uploaded splash sound")
		check(has(fx, 'AudioController.play("wallSmash", mid'), "a big look crunches")
		check(
			has("src/client/Fx/ImpactFx.luau", "BuildingFx.onPropSmash = function"),
			"the ram smash's juice"
		)
		local mc = "src/client/Controllers/MoveController.luau"
		check(has(mc, "local stop = MoveController.propStop"), "a hit-stop through a car or a structure")
		check(
			has(mc, "-- destroy-all (2026-11-20): a car or a park structure in the run's way"),
			"the ground ram too"
		)
		local is = "src/server/Services/ImpactService.luau"
		check(
			has(is, "local fast = mayBreak(hero) and MoveGuard.peakSpeed(hero, R.window) >= R.minSpeed"),
			"the server checks the rammer's own speed"
		)
		check(has(is, "VehicleService.hit(at, Config.Destruction.street.vehicleRadius)"), "rams flip cars")
		check(has(is, "VehicleService.hit(at, radius) -- destroy-all"), "heavy landings flip cars")
		check(
			has(
				"src/server/Services/BossService.luau",
				"VehicleService.hit(Vector3.new(ev.x, ev.y, ev.z), ev.struct)"
			),
			"boss slams flip cars"
		)
		check(
			has("src/server/Services/CombatService.luau", "VehicleService.hit(center, radius)"),
			"powers and weapons flip cars (as before)"
		)
		local cr = "src/server/Services/CraterService.luau"
		check(has(cr, 'return "water", hit.Position'), "a hit on the water is seen")
		check(has(cr, 'Net.fire("BuildingImpact", player, at, radius, 5)'), "and splashes")
		check(has(cr, "CraterRules.waterLevel(G, world and world.park"), "park craters dig dry")
		check(
			has("src/server/Services/CityBuilder.luau", 'p:SetAttribute("Dress", dress.box[i])'),
			"the Deep's groups"
		)
		check(has("src/server/Services/ParkBuilder.luau", "dressUp(p, dress.mesh[i])"), "the park's groups")
		-- pins, safe areas and the server's say are untouched: dressed looks and street things break on devices only,
		-- vehicles through the same mayBreak as rams
		check(has(is, "local function mayBreak(hero: any): boolean"), "mayBreak stays")
		check(has(is, "return not FlagService.safe(hero)"), "safe areas never break")
	end)

	test(
		"Destroy all: heavier collapses, glass, bending lamps, the park's server say (source and budgets)",
		function()
			local fx = "src/client/Fx/BuildingFx.luau"
			check(has(fx, "rollDust(rec, p, seconds)"), "a collapse's dust rolls out along the ground")
			check(
				has(fx, "local hit = Workspace:Raycast(from, dir * reach, params)"),
				"and stops at the next wall"
			)
			check(
				has(fx, "shakeAt(Vector3.new(rec.x, rec.base, rec.z), D.collapseTime * 0.5, 0.6 * tall"),
				"shake by distance and height"
			)
			check(not has(fx, "if nearMe(rec.x, rec.z, 250) then"), "no flat 250-stud shake left")
			check(
				has(fx, "landed(f)") and has(fx, "part.CustomPhysicalProperties = DEBRIS_PHYS"),
				"pieces spill, bounce and settle"
			)
			check(
				has(fx, "glass(rec, knockAt, panes)") and has(fx, 'AudioController.play("shatter", at'),
				"windows shatter"
			)
			check(
				has(fx, 'd:GetAttributeChangedSignal("DressDown")'),
				"a look the server takes down breaks on every device"
			)
			check(
				has("src/client/Controllers/CityProps.luau", "bend(pr, m, center, c, respawn)"),
				"lamps bend at the edge"
			)
			check(
				has(
					"src/server/Services/BuildingService.luau",
					"ParkBuilder.breakAt(center, radius, heavy == true)"
				),
				"every knock reaches the park on the server"
			)
			check(
				has("src/server/Services/CityBuilder.luau", "local park = parkHeight(x, z)"),
				"robots walk where a look fell"
			)
			check(
				has("src/server/Services/ImpactService.luau", "BuildingService.street(at, 4, fast)"),
				"only a real ram is heavy"
			)
			-- phone budgets: the new counts grow with the preset and stay small on low
			local P = Config.Presets
			for _, name in { "low", "medium", "high" } do
				local c = P[name] and P[name].collapse
				check(c ~= nil, name .. " has collapse counts")
			end
			check(
				P.low.collapse.roll <= P.medium.collapse.roll
					and P.medium.collapse.roll <= P.high.collapse.roll,
				"dust fronts grow with the preset"
			)
			check(P.low.collapse.spill <= 4 and P.low.collapse.glass <= 4, "a phone spills and shards little")
			check(
				P.low.collapse.spill <= P.low.debris and P.high.collapse.spill <= P.high.debris,
				"spill inside the debris budget"
			)
			local B = Config.Destruction.street.bend
			check(B and B.from > 0 and B.from < 1 and B.angle[1] < B.angle[2], "the bend's numbers")
		end
	)

	test("Destroy all: the place's ParkBuilder dresses every structure (headless)", function()
		if not placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local luau = require("@lune/luau")
		local game = roblox.deserializePlace(fs.readFile(placePath))
		local cache: { [string]: any } = {}
		local GLOBALS =
			{ "Instance", "CFrame", "Vector3", "Color3", "Enum", "Region3", "UDim2", "UDim", "Vector2" }
		local function load(mod: any): any
			local key = mod:GetFullName()
			if cache[key] ~= nil then
				return cache[key]
			end
			local env: { [string]: any } = {}
			for _, g in GLOBALS do
				env[g] = (roblox :: any)[g]
			end
			env.game = game
			env.workspace = game:GetService("Workspace")
			env.script = mod
			env.task = {
				spawn = function() end,
				defer = function() end,
				delay = function() end,
				wait = function() end,
			}
			env.warn = function() end
			env.print = function() end
			env.typeof = roblox.typeof or typeof
			env.require = load
			env.__tag = function() end
			local src = string.gsub(mod.Source, ":WaitForChild%(", ":FindFirstChild(")
			src = string.gsub(src, "CollectionService:AddTag%(", "__tag(")
			src = string.gsub(src, "Players:GetPlayers%(%)", "{}") -- (no players in the sim)
			local out = luau.load(src, { debugName = key, environment = env })()
			cache[key] = out
			return out
		end
		local services =
			game:GetService("ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Services")
		local ParkBuilder = load(services:FindFirstChild("ParkBuilder"))
		local folder = roblox.Instance.new("Folder")
		folder.Name = "City"
		folder.Parent = game:GetService("Workspace")
		local function makePart(b: any): any
			local p = roblox.Instance.new("Part")
			p.Size = roblox.Vector3.new(b.sx, b.sy, b.sz)
			p.CFrame = roblox.CFrame.new(b.cx, b.cy, b.cz) * roblox.CFrame.Angles(0, math.rad(b.ry or 0), 0)
			return p
		end
		local ok = pcall(ParkBuilder.build, world, folder, makePart) -- (stops at the Terrain writes)
		local park = folder:FindFirstChild("Park")
		check(park ~= nil, "the park is built (" .. tostring(ok) .. ")")
		if not park then
			return
		end
		local solids, dressedSolids, big, meshKeys, solidKeys = 0, 0, 0, {}, {}
		local looks: { [string]: boolean } = {}
		local unkeyed = 0
		for _, p in park:GetDescendants() do
			if p:IsA("BasePart") then
				local key = p:GetAttribute("Dress")
				if p.Name == "parkSolid" then
					solids += 1
					if key then
						dressedSolids += 1
						solidKeys[key] = true
					end
				elseif p.Name ~= "prop" then
					if key then
						meshKeys[key] = true
						looks[tostring(p:GetAttribute("ParkPiece"))] = true
					else
						unkeyed += 1
					end
				end
				if p:GetAttribute("DressBig") == true then
					big += 1
				end
			end
		end
		check(
			solids > 100 and dressedSolids == solids,
			string.format("every box dressed (%d of %d)", dressedSolids, solids)
		)
		local orphan = 0
		for key in meshKeys do
			if not solidKeys[key] then
				orphan += 1
			end
		end
		check(orphan == 0, "every dressed mesh has its collision boxes in the same group")
		check(big > 0, "the big looks are marked (" .. big .. " parts)")
		local nLooks = 0
		for _ in looks do
			nLooks += 1
		end
		check(
			nLooks >= 20,
			"the meshes of every structure are in their groups (" .. nLooks .. " pieces kinds)"
		)
		print(
			string.format(
				"  [destroy all] park: %d boxes and %d mesh kinds dressed, %d big parts, %d decor pieces left whole (reeds, lily pads)",
				dressedSolids,
				nLooks,
				big,
				unkeyed
			)
		)

		-- the server's say on a broken look (ParkBuilder.breakAt from BuildingService.impact): robots stop meeting it
		local bandshell = world.park.places.Bandshell
		local ST = Config.Destruction.street
		local function groupOf(look: string): any
			for _, m in world.park.meshes do
				if m.look == look then
					local g = ParkBuilder.groups["P" .. m.group]
					if g and not g.big then
						return g
					end
				end
			end
			return nil
		end
		check(bandshell ~= nil, "the bandshell is placed")
		if not bandshell then
			return
		end
		local at = roblox.Vector3.new(bandshell.x, 4, bandshell.z)
		check(
			ParkBuilder.breakAt(at, 4, false) == 0,
			"a light knock leaves the bandshell standing on the server"
		)
		local before = ParkBuilder.heightAt(bandshell.x, bandshell.z)
		check(before == nil, "nothing is down yet")
		local n = ParkBuilder.breakAt(at, 12, false)
		check(n >= 1 and n <= ST.perHit, "a heavy hit takes it down (" .. n .. " looks)")
		local downBoxes, collide = 0, 0
		for _, g in ParkBuilder.down do
			for _, p in g.boxes do
				downBoxes += 1
				if p.CanCollide or p.CanQuery or p:GetAttribute("DressDown") ~= true then
					collide += 1
				end
			end
		end
		check(
			downBoxes > 0 and collide == 0,
			"its boxes stop colliding and taking queries, marked DressDown for devices"
		)
		local h = ParkBuilder.heightAt(bandshell.x, bandshell.z)
		check(h ~= nil and h < 3, "robots walk the ground where it stood (" .. tostring(h) .. ")")
		check(ParkBuilder.breakAt(at, 12, true) == 0, "a look already down is not taken twice")
		check(ParkBuilder.step(0) == 0, "it stays down until its time is up")
		local back = ParkBuilder.step(math.huge)
		check(back == n and next(ParkBuilder.down) == nil, "then stands again")
		local stood = 0
		for _, g in ParkBuilder.groups do
			for _, p in g.boxes do
				if p.CanCollide and p.CanQuery and p:GetAttribute("DressDown") == nil then
					stood += 1
				end
			end
		end
		check(stood == dressedSolids, "every box collides again (" .. stood .. ")")
		check(ParkBuilder.heightAt(bandshell.x, bandshell.z) == nil, "and the height is the look's again")
		local pillar = groupOf("GatePillar")
		check(pillar ~= nil, "a gate pillar group")
		if pillar then
			local b = pillar.bounds
			local c = roblox.Vector3.new((b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2)
			local m = ParkBuilder.breakAt(c, 4, false)
			check(m >= 1, "a light knock takes a small look down")
			ParkBuilder.step(math.huge)
		end
		check(
			ParkBuilder.breakAt(roblox.Vector3.new(5000, 0, 5000), 30, true) == 0,
			"nothing outside the park"
		)
	end)
end
