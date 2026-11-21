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
		check(has(cr, "CraterRules.waterLevel(cfg, world and world.park"), "park craters dig dry")
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

	-- destroy-all round 3 (2026-11-20): bosses wreck the city along each strike's own shape
	test("Destroy all: every boss strike wrecks the city along its shape, inside the caps", function()
		local ImpactRules = require("../src/shared/ImpactRules")
		local BossSim = require("../src/shared/BossSim")
		local Rng = require("../src/shared/Rng")
		local W = Config.Destruction.bossWreck
		check(W ~= nil and W.max >= 1 and W.dmg > 0, "bossWreck is tuned")
		local seen: { [string]: number } = {}
		local spots, over, wide, off = 0, 0, 0, 0
		for run = 1, #Config.Boss.order * 3 do
			local id = Config.Boss.order[(run - 1) // 3 + 1]
			local sim = BossSim.new(Config, id, 0, 0, 0, 1e9, 20, 0, Rng.new(11))
			sim.phase = (run - 1) % 3 + 1 -- every phase's attacks (lines are Rustjaw's phase 3 eye laser)
			BossSim.step(sim, 6, {})
			local heroes = {
				{ id = 1, x = 30, y = 0, z = 20, alive = true },
				{ id = 2, x = -25, y = 40, z = -30, alive = true },
			}
			local t = 6
			while t < 66 do
				t += 0.1
				BossSim.step(sim, t, heroes)
				for _, ev in BossSim.drain(sim) do
					if ev.k == "strike" then
						local w = ImpactRules.bossWreck(W, ev)
						if #w > 0 then
							seen[ev.shape] = (seen[ev.shape] or 0) + 1
						end
						if #w > W.max then
							over += 1
						end
						for _, s in w do
							spots += 1
							if s[4] < W.radius[1] or s[4] > W.radius[2] then
								wide += 1
							end
						end
						if ev.shape == "lines" then
							check(ev.points ~= nil and ev.length ~= nil, "a line strike carries its lines")
							-- every spot lies on one of its lines, within the line's reach
							for _, s in w do
								local dx, dz = s[1] - ev.x, s[3] - ev.z
								local best = math.huge
								for _, d in ev.points do
									local along = dx * d[1] + dz * d[2]
									local across = math.abs(dx * d[2] - dz * d[1])
									if along >= 0 and along <= ev.length + 1 then
										best = math.min(best, across)
									end
								end
								if best > 1 then
									off += 1
								end
							end
						end
					end
				end
			end
		end
		print(
			string.format(
				"  [destroy all] boss wreck: %d spots (lines %d, cone %d, ring %d, column %d, circles %d strikes)",
				spots,
				seen.lines or 0,
				seen.cone or 0,
				seen.ring or 0,
				seen.column or 0,
				seen.circles or 0
			)
		)
		check(over == 0, "never more than max spots a strike")
		check(wide == 0, "every spot's radius within bossWreck.radius")
		check(off == 0, "a charge's or beam's spots lie along its lines (" .. off .. " off)")
		for _, shape in { "lines", "cone", "ring", "column" } do
			check((seen[shape] or 0) > 0, "a " .. shape .. " strike wrecks the city")
		end
		check(
			#ImpactRules.bossWreck(W, { shape = "gust", x = 0, y = 0, z = 0, r = 30 }) == 0,
			"a gust wrecks nothing"
		)
		local fan = ImpactRules.bossWreck(W, {
			shape = "lines",
			x = 0,
			y = 0,
			z = 0,
			length = 200,
			width = 8,
			points = { { 1, 0 }, { 0, 1 }, { -1, 0 } },
		})
		local first = { false, false, false }
		for _, s in fan do
			if s[1] > 1 then
				first[1] = true
			elseif s[3] > 1 then
				first[2] = true
			elseif s[1] < -1 then
				first[3] = true
			end
		end
		check(
			#fan == W.max and first[1] and first[2] and first[3],
			"a long fan shares the cap among its lines"
		)

		local src = fs.readFile("src/server/Services/BossService.luau")
		check(
			string.find(src, "ImpactRules.bossWreck(W, ev)", 1, true) ~= nil
				and string.find(src, "BuildingService.hit(at, w[4], W.dmg, 2)", 1, true) ~= nil
				and string.find(src, "VehicleService.hit(at, w[4])", 1, true) ~= nil,
			"BossService hits each spot through BuildingService and flips the cars there"
		)
		check(
			string.find(src, "BuildingService.street(at, r, true)", 1, true) ~= nil
				and string.find(src, "stomp(f, now)", 1, true) ~= nil,
			"its footsteps knock the street as it walks"
		)
	end)

	-- destroy-all round 3: repeated heavy hits dig deeper, fill back in steps; big ones throw clods
	test("Destroy all: craters dig deeper under repeated hits and fill back over time", function()
		local G = Config.Destruction.ground
		local dp = G.deepen
		check(dp ~= nil and dp.max >= 2 and dp.fills >= 2, "deepen is tuned")
		local book = CraterRules.new()
		local c = CraterRules.add(G, book, 0, 0, 0, G.fullDmg, "terrain", 0)
		check(c ~= nil, "a first crater")
		if not c then
			return
		end
		local d1 = CraterRules.depthOf(G, c)
		check(CraterRules.deepen(G, book, 40, 40, 0.1) == nil, "a hit away from it is not the same crater")
		local again = CraterRules.deepen(G, book, c.r * 0.3, 0, 2)
		check(
			again == c and c.deep == 2 and c.born == 2,
			"a hit in it digs it a level deeper and starts its life again"
		)
		check(CraterRules.depthOf(G, c) > d1, "deeper")
		for k = 1, 6 do
			CraterRules.deepen(G, book, 0, 0, 2 + k * 2)
		end
		check(c.deep == dp.max, "up to the cap (" .. tostring(c.deep) .. ")")
		local cap = CraterRules.depthOf(G, c)
		check(math.abs(cap - G.depth * (1 + (dp.max - 1) * dp.add)) < 1e-6, "the cap's depth")
		local born = c.born
		check(CraterRules.fillScale(G, c, born + 1) == 1, "whole until it heals")
		local half = CraterRules.fillScale(G, c, born + G.life - G.heal / 2)
		check(half < 1 and half > 0, "half way through the heal it is part filled (" .. half .. ")")
		local steps: { [number]: boolean } = {}
		for t = born + G.life - G.heal, born + G.life, 1 do
			steps[CraterRules.fillScale(G, c, t)] = true
		end
		local n = 0
		for _ in steps do
			n += 1
		end
		check(n <= dp.fills + 1, "it fills in a few steps, not every frame (" .. n .. ")")
		-- the voxels read once cover the deepest bowl, and a filled bowl carves nothing
		local lo, hi = CraterRules.region(G, c)
		check(hi[2] - lo[2] >= c.r * cap, "the read region covers the deepest bowl")
		local function grid(): ({ any }, { any })
			local mats, occ = {}, {}
			local nx = (hi[1] - lo[1]) / G.voxel
			local ny = (hi[2] - lo[2]) / G.voxel
			local nz = (hi[3] - lo[3]) / G.voxel
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
			return mats, occ
		end
		local m1, o1 = grid()
		local deepN = CraterRules.carve(G, c, lo, m1, o1, -1e9)
		local shallow = table.clone(c)
		shallow.deep = 1
		local m2, o2 = grid()
		local oneN = CraterRules.carve(G, shallow, lo, m2, o2, -1e9)
		check(
			deepN > oneN and oneN > 0,
			"a deeper crater carves more voxels (" .. oneN .. " -> " .. deepN .. ")"
		)
		local m3, o3 = grid()
		check(CraterRules.carve(G, c, lo, m3, o3, -1e9, 0) == 0, "a filled-back bowl carves nothing")

		local srv = fs.readFile("src/server/Services/CraterService.luau")
		check(
			string.find(srv, "CraterRules.deepen(G, book", 1, true) ~= nil
				and string.find(srv, "CraterRules.fillScale(G, c, now)", 1, true) ~= nil
				and string.find(srv, "c.deep or 1", 1, true) ~= nil,
			"CraterService deepens, fills back and sends the depth"
		)
		local fx = fs.readFile("src/client/Fx/GroundFx.luau")
		check(
			string.find(fx, "clods(c)", 1, true) ~= nil
				and string.find(fx, "DebrisBudget.lease", 1, true) ~= nil
				and string.find(fx, "GetMaterialColor", 1, true) ~= nil,
			"GroundFx throws clods of the ground's own look within the debris budget"
		)
		local last = 0
		for _, name in Config.Presets.order do
			local pr = Config.Presets[name]
			local k = pr and pr.collapse and pr.collapse.clods
			check(k ~= nil and k >= last, name .. " has its clods (" .. tostring(k) .. ")")
			last = k or last
		end
	end)

	-- destroy-all round 3: "fly through buildings" reads well: flight at cruise goes through block buildings wall
	-- after wall without a stall, and the device's same-building gate lets the far wall ram
	test("Destroy all: a flight ram goes through whole buildings with no stall", function()
		local BuildingState = require("../src/shared/BuildingState")
		local ImpactRules = require("../src/shared/ImpactRules")
		local D = Config.Destruction
		local R = Config.Combat.impact.ram
		local book = BuildingState.new(D, world.buildings)
		local tried, through, stalls, farWalls, held, maxRams = 0, 0, 0, 0, 0, 0
		-- the 30 thinnest block buildings (where a far wall comes soonest) and 30 more across the city
		local pool = {}
		for _, b in world.buildings do
			if
				not b.round
				and b.district ~= "Outskirts"
				and not BuildingState.pinned(book, b.id)
				and b.top - b.base > 14
			then
				table.insert(pool, b)
			end
		end
		table.sort(pool, function(a, b)
			return a.sx < b.sx
		end)
		local picks = {}
		for k = 1, math.min(30, #pool) do
			table.insert(picks, pool[k])
		end
		for k = 31, #pool, math.max(1, (#pool - 30) // 30) do
			table.insert(picks, pool[k])
		end
		-- at cruise (60) and at Boost (110), each on a whole city
		for _, cruise in { 60, 110 } do
			book = BuildingState.new(D, world.buildings)
			for _, b in picks do
				tried += 1
				local y = b.base + 12.5
				local exitX = b.x + b.sx / 2 + 2
				local pos = b.x - b.sx / 2 - 3
				local rams, t, speed, good = 0, 0, cruise, true
				local lastT, lastX = -math.huge, -math.huge
				while pos < exitX do
					local d = math.huge
					for _, o in { { 0, 0 }, { 0, 1.5 }, { 0, -1.5 }, { 1.5, 0 }, { -1.5, 0 } } do
						d = math.min(d, BuildingState.ray(D, book, pos, y + o[1], b.z + o[2], 1, 0, 0, 200))
					end
					if rams == 0 then
						d = (b.x - b.sx / 2) - pos -- an intact building is not in the ray: its face
					end
					if pos + d >= exitX then
						break
					end
					local hitX = pos + d
					t += d / speed + R.hitStop
					-- MoveController's gate: the same building again inside sameWall is skipped; since round 3 only
					-- when it is within RAM.radius of the last hole (the far wall of a small block rams)
					if rams > 0 and t - lastT < R.sameWall then
						if hitX - lastX >= R.radius then
							farWalls += 1 -- a far wall: skipped before round 3, a ram now
						else
							held += 1 -- the same hole's edge again (a wall that held): still gated
						end
					end
					rams += 1
					local r = BuildingState.blast(
						D,
						book,
						b.id,
						hitX + 1.5,
						y,
						b.z,
						R.radius,
						ImpactRules.ramDamage(R, speed),
						t
					)
					if book.state[b.id] == 2 then
						break -- it came down round the hero
					end
					if #r.hit == 0 or rams > 12 then
						good = false
						break
					end
					lastT, lastX = t, hitX
					pos = hitX - 0.01
					speed *= 1 - R.loss
				end
				maxRams = math.max(maxRams, rams)
				if good then
					through += 1
				else
					stalls += 1
				end
			end
		end
		print(
			string.format(
				"  [destroy all] fly-through (cruise and Boost): %d of %d, %d stalls, up to %d rams; %d far-wall rams the old gate skipped, %d held-wall contacts gated",
				through,
				tried,
				stalls,
				maxRams,
				farWalls,
				held
			)
		)
		check(tried >= 80, "enough buildings tried")
		check(through >= tried * 0.95, "flight goes through nearly every building")
		check(
			has("src/client/Controllers/MoveController.luau", "(at - ramLast.pos).Magnitude < RAM.radius"),
			"MoveController gates the same building by distance from the last hole"
		)
	end)

	-- destroy-all round 4 (2026-11-20): the worst case all at once: 30 heroes wrecking Downtown (a super every 2 s,
	-- a skill every 0.5 s, rams flat out inside the impact caps), a boss's strikes wrecking down a street, and 3
	-- buildings coming down together. The server's pure building work per frame, the BuildingDiff bytes a second
	-- (the 2 Hz batch plus the rams' own flushes), the join snapshot at its biggest, and the Low device's dust.
	test("Destroy all: worst case load: 30 heroes, a boss and 3 collapses at once stay in budget", function()
		local BuildingState = require("../src/shared/BuildingState")
		local ImpactRules = require("../src/shared/ImpactRules")
		local D = Config.Destruction
		local I = Config.Combat.impact
		local R = I.ram
		local W = D.bossWreck
		local LB = D.load
		check(LB ~= nil, "Destruction.load holds the budgets")
		local book = BuildingState.new(D, world.buildings)
		local ledger = ImpactRules.ledger()
		local downtown = {}
		for _, b in world.buildings do
			if
				b.district == "Downtown"
				and not BuildingState.pinned(book, b.id)
				and b.x > -700
				and b.x < -100
				and b.z > -350
				and b.z < 350
			then
				table.insert(downtown, b)
			end
		end
		check(#downtown >= 60, "Downtown's blocks (" .. #downtown .. ")")
		-- Roblox remote sizes, on the heavy side: a number 9 bytes, a table 3 plus its keys, a buffer its length + 3
		local function bytes(v: any): number
			local t = type(v)
			if t == "number" then
				return 9
			elseif t == "buffer" then
				return buffer.len(v) + 3
			elseif t == "string" then
				return #v + 2
			elseif t == "table" then
				local n = 3
				for k, x in v do
					n += (if type(k) == "string" then #k + 2 else 0) + bytes(x)
				end
				return n
			end
			return 1
		end
		local roundTrip = true
		local function batch(): (number, number)
			local fixed = BuildingState.takeFixed(book)
			local diffs = BuildingState.takeDiffs(book)
			local removed = BuildingState.takeRemoved(book)
			if #diffs == 0 and #removed == 0 and #fixed == 0 then
				return 0, 0
			end
			local packed = BuildingState.packRemoved(removed)
			local back = BuildingState.removedList(packed)
			for i = 1, #removed do
				if back[i] ~= removed[i] then
					roundTrip = false
				end
			end
			return 1, bytes({ r = fixed, d = diffs, dr = {}, c = if #removed > 0 then packed else nil })
		end
		local seed = 11
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		-- 3 at once: three blocks knocked down at their feet
		local collapses = 0
		for k = 1, 3 do
			local b = downtown[k * 17]
			for _ = 1, 30 do
				local r = BuildingState.blast(
					D,
					book,
					b.id,
					b.x + (rnd() - 0.5) * b.sx,
					b.base + 2,
					b.z + (rnd() - 0.5) * b.sz,
					14,
					D.superStruct,
					0
				)
				if r.changed and r.state == BuildingState.COLLAPSED then
					collapses += 1
					break
				end
			end
		end
		local secs, dt = 30, 0.5
		local cpu, worstTick, sends, sent, worstSecond, worstLoop = 0, 0, 0, 0, 0, 0
		local second, secondBytes = 0, 0
		local rams, ramsOk, hits = 0, 0, 0
		local t = 0
		while t < secs do
			t += dt
			local t0 = os.clock()
			local tickBytes = 0
			for hero = 1, 30 do
				local b = downtown[1 + ((hero * 7 + math.floor(t / 8) * 3) % #downtown)]
				local x = b.x + (rnd() - 0.5) * b.sx
				local z = b.z + (if rnd() < 0.5 then -1 else 1) * b.sz / 2
				local y = b.base + 2 + rnd() * 20
				local dmg = if hero % 4 == math.floor(t / dt) % 4 then D.superStruct else D.slotStruct.skill
				for _, id in BuildingState.near(book, x, z, 12) do
					local bb = world.buildings[id]
					if bb and BuildingState.touches(bb, x, y, z, 12) then
						hits += 1
						BuildingState.blast(D, book, id, x, BuildingState.blastY(bb, y), z, 12, dmg, t)
					end
				end
				-- rams flat out (4 a second asked): each one the server allows knocks a hole and flushes at once
				for k = 0, 1 do
					rams += 1
					if ImpactRules.allow(I, ledger, hero, t + k * 0.25) then
						ramsOk += 1
						local r = BuildingState.blast(
							D,
							book,
							b.id,
							x,
							BuildingState.blastY(b, y),
							z,
							R.radius,
							ImpactRules.ramDamage(R, 110),
							t
						)
						if #r.hit > 0 then
							local n, by = batch()
							sends += n
							tickBytes += by
						end
					end
				end
			end
			-- the boss: a strike every 2 s down a street through the blocks (6 spots of bossWreck.dmg)
			if math.floor(t / dt) % 4 == 0 then
				local b = downtown[1 + (math.floor(t) % #downtown)]
				local ev = {
					shape = "lines",
					x = b.x - 60,
					y = b.base,
					z = b.z,
					length = 220,
					width = 10,
					points = { { 1, 0 }, { 0.7, 0.7 }, { 0.7, -0.7 } },
				}
				for _, w in ImpactRules.bossWreck(W, ev) do
					for _, id in BuildingState.near(book, w[1], w[3], w[4]) do
						local bb = world.buildings[id]
						if bb and BuildingState.touches(bb, w[1], w[2], w[3], w[4]) then
							BuildingState.blast(
								D,
								book,
								id,
								w[1],
								BuildingState.blastY(bb, w[2]),
								w[3],
								w[4],
								W.dmg,
								t
							)
						end
					end
				end
			end
			local s0 = os.clock()
			for _, h in BuildingState.stepHeld(D, book, t) do
				local _ = h
				collapses += 1
			end
			if math.floor(t) ~= math.floor(t - dt) then
				BuildingState.stepDrones(D, book, t)
			end
			local n, by = batch() -- the 2 Hz batch
			worstLoop = math.max(worstLoop, (os.clock() - s0) * 1000)
			sends += n
			tickBytes += by
			local spent = (os.clock() - t0) * 1000
			cpu += spent
			worstTick = math.max(worstTick, spent)
			sent += tickBytes
			if math.floor(t) ~= second then
				worstSecond = math.max(worstSecond, secondBytes)
				second, secondBytes = math.floor(t), 0
			end
			secondBytes += tickBytes
		end
		worstSecond = math.max(worstSecond, secondBytes)
		local perFrame = cpu / (secs * 60)
		local snap = bytes({
			s = BuildingState.pack(book),
			n = book.n,
			dr = {},
			g = BuildingState.packGone(D, book),
		})
		local damaged = 0
		for _ in book.open do
			damaged += 1
		end
		print(
			string.format(
				"  [destroy all] load: %d hits, %d/%d rams, %d collapses, %d Damaged; %.3f ms a frame (worst 0.5 s of hits %.1f ms, worst 2 Hz loop frame %.2f ms); %d sends, %.1f KB/s a player (worst second %.1f KB); snapshot %.1f KB",
				hits,
				ramsOk,
				rams,
				collapses,
				damaged,
				perFrame,
				worstTick,
				worstLoop,
				sends,
				sent / secs / 1024,
				worstSecond / 1024,
				snap / 1024
			)
		)
		check(collapses >= 3, "three buildings came down")
		check(roundTrip, "the packed pieces read back the same (id, piece, cause)")
		check(
			perFrame <= LB.serverMs,
			string.format("server building work %.3f ms a frame (budget %s)", perFrame, LB.serverMs)
		)
		check(
			worstSecond <= LB.diffBytes,
			string.format("BuildingDiff %d bytes in the worst second (budget %d)", worstSecond, LB.diffBytes)
		)
		check(
			snap <= LB.snapshotBytes,
			string.format("the join snapshot %d bytes (budget %d)", snap, LB.snapshotBytes)
		)
		check(
			sends / secs <= 2 + I.serverPerSecond,
			"diff sends a second: the 2 Hz batch plus the rams the server allows"
		)

		-- the Low device with three collapses in view: the dust clouds (emitters cap) and their rolling fronts
		local low = Config.Presets.low
		local C = D.collapseFx
		local clouds = math.min(3, low.emitters)
		local scale = low.collapse.dust or 1
		local perSec = clouds * (C.cloudRate + low.collapse.roll * C.rollRate) * scale
		local fxShare = Config.Fx.lib.budget.low
		print(
			string.format(
				"  [destroy all] Low device, 3 collapses: %d dust clouds, %.0f dust particles a second (effects budget %s a second)",
				clouds,
				perSec,
				tostring(fxShare)
			)
		)
		check(
			perSec <= LB.lowDust,
			string.format("Low collapse dust %.0f a second (budget %d)", perSec, LB.lowDust)
		)
		local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
		check(
			string.find(fx, ").cloudRate or 24)", 1, true) ~= nil
				and string.find(fx, "or {}).dust or 1)", 1, true) ~= nil,
			"BuildingFx's dust clouds and fronts scale by the preset"
		)
	end)

	-- destroy-all round 4: a body thrown into a wall reads: a hole and the body-through moment, else a dent; a robot
	-- knocked through flies on, tumbling; a thrown thing smashes the wall it meets and launches the robots it hits
	test("Destroy all: bodies and throws into walls read heavy (holes, dents, tumbles)", function()
		local ThrowMath = require("../src/shared/ThrowMath")
		local KnockRules = require("../src/shared/KnockRules")
		local imp = fs.readFile("src/server/Services/ImpactService.luau")
		local bs = fs.readFile("src/server/Services/BuildingService.luau")
		local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
		local throw = fs.readFile("src/server/Services/ThrowService.luau")
		local function count(src: string, needle: string): number
			local n, at = 0, 1
			while true do
				local i = string.find(src, needle, at, true)
				if not i then
					return n
				end
				n += 1
				at = i + #needle
			end
		end
		check(
			string.find(bs, "impact(Vector3.new(px, py, pz), radius, 6, false, dir.Unit)", 1, true) ~= nil
				and string.find(
						bs,
						'Net.fire("BuildingImpact", player, center, radius, kind, dir)',
						1,
						true
					)
					~= nil,
			"a smash with a direction sends the body-through moment (kind 6, its direction)"
		)
		check(
			string.find(fx, "if kind == 6 then", 1, true) ~= nil
				and string.find(fx, "bodyThrough(center, radius, dir.Unit)", 1, true) ~= nil
				and string.find(fx, 'FxLib.throwMoment("smash", at + dir * 2, color, dir, size)', 1, true) ~= nil
				and string.find(fx, "shakeAt(at, 0.22, 0.45, 160)", 1, true) ~= nil,
			"devices burst the wall out of the far side, crash and shake by distance"
		)
		check(
			count(imp, "I.ram.radius, flat) > 0") == 2 and count(imp, "BuildingService.dent(") >= 6,
			"robots knocked or launched into walls break them along their flight, or dent a wall that holds"
		)
		check(
			string.find(
				imp,
				"EnemyService.launch(enemyId, flat.Unit, T.carry, T.lift, T.speed, hero.id)",
				1,
				true
			) ~= nil,
			"a robot knocked through a wall flies on through the hole, tumbling"
		)
		local TR = Config.Combat.impact.robot.through
		check(TR ~= nil and TR.carry >= 8 and TR.speed > 0, "impact.robot.through is tuned")
		check(
			string.find(throw, "ImpactService.throwWall(hero, it.weight, wallAt, wallAt - from)", 1, true)
				~= nil,
			"a throw that meets a wall in flight smashes it there"
		)
		local T = Config.Throw
		local K = Config.Combat.knock
		local last = 0
		local order: { [string]: number } = {}
		for i, k in K.order do
			order[k] = i
		end
		for _, w in { "light", "medium", "heavy" } do
			local W = T.weights[w]
			check(
				W.wall and W.wall > last,
				w .. " throws hit walls harder than the lighter ones (" .. W.wall .. ")"
			)
			last = W.wall
			local hit = ThrowMath.hit(T, w)
			local kind = KnockRules.kind(K, { knockKind = hit.knockKind, coeff = hit.coeff, slot = "skill" })
			check(kind == W.knockKind, w .. " throws knock robots as " .. tostring(W.knockKind))
		end
		check(
			T.weights.light.wall >= Config.Destruction.structure.chunkCost,
			"even a light throw knocks a piece out"
		)
		check(
			order[T.weights.medium.knockKind] >= order.heavy
				and order[T.weights.heavy.knockKind] > order.heavy,
			"medium and heavy throws launch robots at least like a smash"
		)
	end)
end
