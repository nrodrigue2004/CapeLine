-- The living world's round 3 (alive-world, 2026-11-20, nate: "too many simple shapes and untextured parts ... the
-- world must feel alive"): Art.Alive looks (Config.AliveArt, art/blender/alive.py) over the safehouses' terminals,
-- canopy and pad, the Docks' cranes, the Foundry's chimneys and Uptown's roof gardens (their boxes stay, some
-- hidden), and the devices' new life (Fx.CityLife): traffic scared off by fights, harbour gulls, chimney smoke.
-- Called from tests/run.luau:
--   require("./alive_test")({ test = test, check = check, Config = Config, world = world, placePath = p })
-- ONLY="Alive" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local LifeKit = require("../src/shared/LifeKit")
	local LifePlan = require("../src/shared/LifePlan")
	local AA = Config.AliveArt
	local A = Config.Life.alive

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	local function byLook(): { [string]: { any } }
		local out: { [string]: { any } } = {}
		for _, b in world.hubBoxes do
			if b.look and AA[b.look] then
				out[b.look] = out[b.look] or {}
				table.insert(out[b.look], b)
			end
		end
		return out
	end

	test("Alive: every look has meshes, an uploaded id each, a mapped and turned set", function()
		local ids = serde.decode("json", fs.readFile("art/models/alive_meshids.json"))
		local n, maps = 0, 0
		for look, def in AA do
			check(def.frame[1] > 0 and def.frame[2] > 0 and def.frame[3] > 0, look .. " has a frame")
			for name, m in def.meshes do
				n += 1
				check(m.size[1] > 0 and m.size[2] > 0 and m.size[3] > 0, name .. " has a size")
				check(ids[name] ~= nil, name .. " has an uploaded mesh id")
				check(
					Config.ShapeArt[name] == nil and Config.LifeArt.cover[name] == nil,
					name .. " is its own"
				)
				if m.maps then
					maps += 1
				end
			end
		end
		check(n == 42, "the set has its 42 meshes (" .. n .. ")")
		check(maps >= 18, "the big pieces carry baked texture sets (" .. maps .. ")")
		check(
			has("default.project.json", '"Alive": { "$path": "art/models/Alive.rbxm" }'),
			"Art.Alive is mapped"
		)
		check(has("src/shared/MeshFix.luau", '"Alive"'), "MeshFix knows the set's turn")
		local turns = serde.decode("json", fs.readFile("art/models/meshturns.json"))
		check(turns.Alive ~= nil and turns.Alive.verdict == "rotY180", "meshcheck measured the set turned")
		for look in A.hide do
			check(AA[look] ~= nil, "hidden look " .. look .. " is a look")
		end
		for _, look in A.terminals do
			check(AA[look] ~= nil, "terminal look " .. look .. " is a look")
		end
	end)

	test("Alive: the built place has every Art.Alive mesh and its texture sets", function()
		local path = T.placePath
		if not (path and fs.isFile(path)) then
			check(false, "no built place to read")
			return
		end
		local roblox = require("@lune/roblox")
		local game = roblox.deserializePlace(fs.readFile(path))
		local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
		local set = art and art:FindFirstChild("Alive")
		check(set ~= nil, "ReplicatedStorage.Art.Alive is in the place")
		local sa = 0
		for look, def in AA do
			for name, m in def.meshes do
				local p = set and set:FindFirstChild(name, true)
				check(p ~= nil and p.ClassName == "MeshPart", look .. "." .. name .. " is a MeshPart")
				if p and m.maps then
					local s = p:FindFirstChildOfClass("SurfaceAppearance")
					check(s ~= nil and s.ColorMap ~= "", name .. " has its baked SurfaceAppearance")
					if s then
						sa += 1
					end
				end
			end
		end
		check(sa >= 18, "texture sets in the place (" .. sa .. ")")
	end)

	test("Alive: the world dresses the safehouses, cranes, chimneys and roof gardens", function()
		local L = byLook()
		local nSafe = 0
		for _ in world.safehouses do
			nSafe += 1
		end
		for kind, look in A.terminals do
			local list = L[look] or {}
			check(#list == nSafe, look .. " on every safehouse (" .. #list .. " of " .. nSafe .. ")")
			for _, b in list do
				check(b.tag == kind and b.kind == "terminal", look .. " keeps its terminal tag (the prompt)")
			end
		end
		check(#(L.SafeCanopy or {}) == nSafe, "a canopy on every safehouse")
		check(#(L.SafePadRing or {}) == nSafe, "a painted pad on every safehouse")
		local c = Config.City.docks.cranes
		check(#(L.CraneLeg or {}) == c.count * 2, "two legs a crane")
		check(
			#(L.CraneBeam or {}) == c.count and #(L.CraneBoom or {}) == c.count,
			"a beam and a boom a crane"
		)
		check(#(L.FoundryChimney or {}) == Config.City.docks.foundry.chimneys, "every Foundry chimney")
		check(#(L.RoofGarden or {}) >= 15, "Uptown's roof gardens (" .. #(L.RoofGarden or {}) .. ")")
	end)

	test("Alive: the looks are visual only over boxes that stay, the right ones hidden", function()
		for look, list in byLook() do
			for _, b in list do
				check(LifeKit.keeps(Config, b), look .. " keeps its box")
				check(LifeKit.hides(Config, b) == (A.hide[look] == true), look .. " hidden as Config says")
				check(LifeKit.setOf(Config, look) == A.set, look .. " comes from Art.Alive")
				local pieces = LifeKit.cover(Config, b) or {}
				local nm = 0
				for _ in AA[look].meshes do
					nm += 1
				end
				check(#pieces == nm, look .. " gives a piece a mesh")
				for _, p in pieces do
					check(p.collide == false, look .. "." .. p.name .. " never collides (its box does)")
					check(p.set == A.set, p.name .. " is from the Alive set")
					-- every piece near its box (the canopy's posts reach the pad, the hook hangs under the boom)
					local reach = math.max(b.sx, b.sy, b.sz)
					check(
						math.abs(p.x - b.cx) <= reach
							and math.abs(p.z - b.cz) <= reach
							and math.abs(p.y - b.cy) <= reach,
						p.name .. " stands by its box"
					)
				end
				-- a terminal's screen glows in its kind's colour
				if look:sub(1, 4) == "Term" then
					local want = Config.City.palette[b.color]
					local glow = false
					for _, p in pieces do
						if p.mat == "Neon" then
							glow = p.color[1] == want[1] and p.color[2] == want[2] and p.color[3] == want[3]
						end
					end
					check(glow, look .. " glows in its kind's colour")
				end
			end
		end
		-- the canopy's posts stand on the pad (12.75 under the canopy's middle)
		local canopy = (byLook().SafeCanopy or {})[1]
		if canopy then
			for _, p in LifeKit.cover(Config, canopy) or {} do
				if p.name == "CanopyPosts" then
					check(
						math.abs((p.y - p.size[2] / 2) - (canopy.cy - 12.75)) < 0.3,
						"the posts' feet on the pad"
					)
				end
			end
		end
		check(
			has("src/server/Services/CityBuilder.luau", "LifeKit.hides(Config, b)"),
			"CityBuilder hides the box"
		)
		check(
			has("src/server/Services/CityBuilder.luau", "ALIVE_TAGS[b.look]"),
			"CityBuilder tags the life boxes"
		)
	end)

	test("Alive: traffic is scared off by fights and U-turns across the road", function()
		local F = Config.Life.traffic.fear
		check(LifePlan.feared(F, 0, 0, 1, 0, { { 40, 10 } }), "a robot by the car scares it")
		check(LifePlan.feared(F, 0, 0, 1, 0, { { 80, 0 } }), "a fight on the road ahead scares it")
		check(not LifePlan.feared(F, 0, 0, 1, 0, { { -120, 0 } }), "a fight far behind does not")
		check(not LifePlan.feared(F, 0, 0, 1, 0, {}), "no fight, no fear")
		-- the loop: from this lane (z = 3.6) to the other (z = -3.6), heading +x then -x
		local x0, z0, tx0 = LifePlan.uturn(0, 3.6, 0, -3.6, 1, 0, F.stretch, 0)
		local x1, z1, tx1 = LifePlan.uturn(0, 3.6, 0, -3.6, 1, 0, F.stretch, 1)
		local xm = LifePlan.uturn(0, 3.6, 0, -3.6, 1, 0, F.stretch, 0.5)
		check(math.abs(x0) < 1e-6 and math.abs(z0 - 3.6) < 1e-6 and tx0 > 0, "starts in its lane heading on")
		check(
			math.abs(x1) < 1e-6 and math.abs(z1 + 3.6) < 1e-6 and tx1 < 0,
			"ends in the other lane heading back"
		)
		check(xm > 3.6, "bulges ahead mid-turn (" .. xm .. ")")
		check(F.flee > 1 and F.fleeFor > 0 and F.wait > 0 and F.turn > 0, "it waits, turns, then races off")
		local src = fs.readFile("src/client/Fx/CityLife.luau")
		check(
			string.find(src, "EnemyRenderer.each()", 1, true) ~= nil,
			"the robots drawn on the device are the fights"
		)
		check(string.find(src, "fearStep(car, dt, now)", 1, true) ~= nil, "every car steps its fear")
	end)

	test("Alive: harbour gulls circle and wheel off; the chimneys smoke; budgets by preset", function()
		local G = Config.Life.gulls
		local x, y, z = LifePlan.gull(0, 0, 20, 5, 15, 0)
		check(
			math.abs(math.sqrt(x * x + z * z) - 20) < 1e-6 and math.abs(y - 5) <= 3.01,
			"a calm gull circles"
		)
		local fx, fy, fz = LifePlan.gull(0, 0, 20, 5, 15, 1)
		check(math.sqrt(fx * fx + fz * fz) > 60 and fy > 30, "a scared gull wheels out and up")
		check(G.scale > 1 and G.range > 0, "gulls are big pigeons near the camera")
		local prev: any = nil
		for _, name in { "low", "medium", "high" } do
			local B = Config.Life.budget[name]
			check(
				type(B.gullColonies) == "number" and type(B.gulls) == "number" and type(B.smoke) == "number",
				name .. " budgets gulls and smoke"
			)
			check(type(B.hazards) == "boolean", name .. " says if hazards blink")
			if prev then
				check(
					B.gulls >= prev.gulls and B.smokeRate >= prev.smokeRate,
					name .. " at least the preset below"
				)
			end
			prev = B
		end
		check(Config.Life.budget.low.hazards == false, "phones skip the hazard lights")
		check(
			A.tags.FoundryChimney == "LifeSmoke" and A.tags.CraneBeam == "LifeGulls",
			"the boxes the life finds"
		)
		local src = fs.readFile("src/client/Fx/CityLife.luau")
		for _, needle in { "stepGulls(dt, now, list)", "stepSmoke()", "puffSmoke(center, radius)" } do
			check(string.find(src, needle, 1, true) ~= nil, "CityLife runs " .. needle)
		end
	end)
end
