-- Gap polish (2026-11-19): the fast-travel flight, the gadgets, the landing crack, the ice pieces and the thrown
-- crate, and the loading splash (notes/Tasks.md "Placeholder art and animation"). Checked here:
--   * Shared.PolishPlan's numbers (flicker, drone orbit, smoke puffs and spots, crack pick and fade, wall
--     shards and crate planks inside their boxes, the flight's ease) and Travel.routeGap
--   * the server's travel rules are unchanged; MoveGuard frees only a body on the trip's arc
--   * the ice pieces and the crate keep their sizes and collisions; the dressing never collides
--   * every per-frame loop is under FrameProf, the budgets per preset rise from low to high
--   * the loading card needs no requires and is in the place, LoadingScreen keeps its waits
-- Called from tests/run.luau: require("./gap_polish_test")({ test = test, check = check, Config = Config,
-- placePath = process.args[1] }). ONLY="Gap polish" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local PolishPlan = require("../src/shared/PolishPlan")
	local Travel = require("../src/shared/Travel")
	local P = Config.Fx.polish

	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(path: string, needle: string): boolean
		return string.find(src(path), needle, 1, true) ~= nil
	end

	test("Gap polish: the decoy flickers more as it runs out, the drone circles at its radius", function()
		local early, late = 0, 0
		for i = 0, 299 do
			local t = i / 300 * 5
			local a = PolishPlan.flicker(t, 5, P.decoy.flickerFrom)
			check(a >= 0 and a <= 0.9, "flicker in range at " .. t)
			if a > 0.6 then
				if t < 3 then
					early += 1
				else
					late += 1
				end
			end
		end
		-- per second: the last 2 s drop out more often than the first 3
		check(late / 2 > early / 3 * 2, string.format("late drop-outs %d vs early %d", late, early))
		check(PolishPlan.flicker(1.2, 5, 0.7) == PolishPlan.flicker(1.2, 5, 0.7), "the same on every device")
		local D = P.drone
		for i = 0, 20 do
			local x, y, z = PolishPlan.droneAt(i * 0.13, D.radius, D.height, D.spin)
			check(math.abs(math.sqrt(x * x + z * z) - D.radius) < 1e-6, "on its circle")
			check(math.abs(y - D.height) <= 0.36, "bobs near its height")
		end
	end)

	test("Gap polish: the smoke cloud covers the blind's time and radius within the preset budget", function()
		local G = Config.Gear.gadgets.SmokeBomb
		local puffs = PolishPlan.smokePuffs(G.blind, P.smoke.puffEvery)
		check(#puffs >= 2 and puffs[1] == 0, "puffs from the throw on")
		check(
			puffs[#puffs] < G.blind and puffs[#puffs] + P.smoke.puffEvery >= G.blind - 0.2,
			"until the blind ends"
		)
		for _, name in Config.Presets.order do
			local row = P.presets[name]
			check(row ~= nil, "a budget row for " .. name)
			for _, s in PolishPlan.smokeSpots(row.smoke, G.radius * 0.85, 42) do
				check(math.sqrt(s[1] ^ 2 + s[2] ^ 2) <= G.radius, "a puff inside the radius")
			end
			-- particles a second at most: the cloud stays inside the device's particle budget
			local perSecond = row.smoke / P.smoke.puffEvery
			check(perSecond <= Config.Fx.lib.budget[name], name .. " smoke fits the particle budget")
		end
		local L = Config.Fx.lib.kinds.cloud
		check(
			L ~= nil and L.tex == "smoke" and L.life[2] > P.smoke.puffEvery,
			"the cloud kind outlives a top-up"
		)
	end)

	test("Gap polish: budgets per preset rise from low to high, and low draws less", function()
		local lo, md, hi = P.presets.low, P.presets.medium, P.presets.high
		for k, v in md do
			check(lo[k] ~= nil and hi[k] ~= nil, "every preset has " .. k)
			if type(v) == "number" then
				check(lo[k] <= v and v <= hi[k], k .. " rises low to high")
			end
		end
		check(
			lo.frost == 0 and lo.decoyGlow == false and lo.droneBits == false,
			"phones skip motes, glow and drone bits"
		)
	end)

	test("Gap polish: the landing crack decals are uploaded, picked by the spot, and fade out", function()
		local C = Config.Fx.crack
		check(#C.decals == 3, "three variants")
		for i, id in C.decals do
			check(type(id) == "number" and id >= 0, "decal " .. i .. " is an id or 0 (the disc fallback)")
			check(fs.isFile("art/export/fx/crack_" .. i .. ".png"), "crack_" .. i .. ".png drawn")
		end
		check(fs.isFile("art/preview/fx_cracks.png"), "the preview")
		local seen = {}
		for i = 1, 60 do
			local k, turn = PolishPlan.crackPick(3, i * 7.3, i * -3.1)
			check(k >= 1 and k <= 3 and turn >= 0 and turn < 360, "a valid pick")
			seen[k] = true
			local k2 = PolishPlan.crackPick(3, i * 7.3, i * -3.1)
			check(k == k2, "the same spot, the same crack")
		end
		check(seen[1] and seen[2] and seen[3], "all three show up")
		check(PolishPlan.crackAlpha(0, C.life, C.fade, 0) == 0, "solid when it lands")
		check(PolishPlan.crackAlpha(C.life - C.fade, C.life, C.fade, 0) == 0, "solid until the fade")
		check(PolishPlan.crackAlpha(C.life, C.life, C.fade, 0) == 1, "gone at the end")
		check(has("src/client/Fx/MoveFx.luau", "if id ~= 0 then"), "an id of 0 keeps the disc")
	end)

	test(
		"Gap polish: ice shards and crate planks stay inside their pieces; sizes and collisions unchanged",
		function()
			for n = 1, 4 do
				for _, sh in PolishPlan.wallShards(6.5, 8, 1.6, n, 5) do
					check(
						sh.x - sh.w / 2 >= -3.25 - 1e-6 and sh.x + sh.w / 2 <= 3.25 + 1e-6,
						"a shard within the slab's ends"
					)
					check(sh.y - sh.h / 2 <= 4, "a shard sits on the top edge")
				end
			end
			local boxes = PolishPlan.crateBoxes(4, 3, 4)
			check(#boxes == 16, "12 edges and 4 side planks")
			for _, b in boxes do
				check(
					math.abs(b[2]) + b[5] / 2 <= 2 + 1e-6
						and math.abs(b[3]) + b[6] / 2 <= 1.5 + 1e-6
						and math.abs(b[4]) + b[7] / 2 <= 2 + 1e-6,
					"a plank inside the 4 x 3 x 4 crate"
				)
			end
			local cs = "src/server/Services/CombatService.luau"
			check(has(cs, "Vector3.new(6.5, 8, 1.6)"), "the Snow Wall slab keeps its size")
			check(has(cs, "w.Size = Vector3.new(8, height, len)"), "the ramp keeps its size")
			check(has(cs, '"wall"\n\t\t)') and has(cs, 'iceLook(w, "ramp")'), "both are tagged for IceFx")
			local ice = src("src/client/Fx/IceFx.luau")
			check(string.find(ice, "p.CanCollide = false", 1, true) ~= nil, "the dressing never collides")
			check(string.find(ice, "CanCollide = true", 1, true) == nil, "nothing in IceFx collides")
			check(
				string.find(ice, "Heartbeat", 1, true) == nil
					and string.find(ice, "RenderStepped", 1, true) == nil,
				"no per-frame loop"
			)
			check(
				has("src/client/Fx/CombatFx.luau", "local CRATE = Vector3.new(4, 3, 4)"),
				"the crate keeps its size"
			)
		end
	)

	test("Gap polish: the flight eases from still to full speed, and MoveGuard frees only the arc", function()
		check(PolishPlan.travelEase(0) == 0 and PolishPlan.travelEase(1) == 1, "ends")
		local last = -1
		for i = 0, 20 do
			local e = PolishPlan.travelEase(i / 20)
			check(e >= last, "never goes back")
			last = e
		end
		local d0 = PolishPlan.travelEase(0.01) - PolishPlan.travelEase(0)
		local d1 = PolishPlan.travelEase(1) - PolishPlan.travelEase(0.99)
		check(d1 > d0 * 20, "it dives into the landing, not floats")
		-- on the arc (anywhere along it, so a lagged sample counts) the gap is small; off it, big
		local a, b = { X = 0, Y = 20, Z = 0 }, { X = 1600, Y = 80, Z = -900 }
		for i = 0, 50 do
			local x, y, z = Travel.flightPath(a.X, a.Y, a.Z, b.X, b.Y, b.Z, PolishPlan.travelEase(i / 50))
			check(Travel.routeGap(a.X, a.Y, a.Z, b.X, b.Y, b.Z, x, y, z) < 8, "on the arc at " .. i)
		end
		local mx, my, mz = Travel.flightPath(a.X, a.Y, a.Z, b.X, b.Y, b.Z, 0.5)
		local slack = Config.World.beacon.routeSlack
		check(
			Travel.routeGap(a.X, a.Y, a.Z, b.X, b.Y, b.Z, mx, my - 200, mz) > slack,
			"under the arc is off it"
		)
		check(Travel.routeGap(a.X, a.Y, a.Z, b.X, b.Y, b.Z, 3000, 50, 3000) > slack, "far away is off it")
		local mg = src("src/server/Services/MoveGuard.luau")
		check(
			string.find(mg, "Travel.routeGap(", 1, true) ~= nil
				and string.find(mg, "routeSlack", 1, true) ~= nil,
			"MoveGuard checks the arc"
		)
		local bs = "src/server/Services/BeaconService.luau"
		check(
			has(bs, 'player:SetAttribute("Traveling", true)')
				and has(bs, 'player:SetAttribute("Traveling", nil)'),
			"the attribute on and off"
		)
		check(has(bs, "hero.travelRoute = { from = pos, to = dest }"), "the route for MoveGuard")
		check(
			has(bs, "hero.alive and not hero.traveling and HeroService.position(hero)"),
			"no beacon found mid-flight"
		)
		-- the travel rules themselves are as before
		check(
			has(bs, "Travel.canTravel(W, {") and has(bs, "task.delay(B.travelTime, arrive, player, trip)"),
			"rules and timing unchanged"
		)
		check(
			Config.World.beacon.travelTime == 3 and Config.World.beacon.cooldown == 20,
			"3 s flight, 20 s cooldown"
		)
	end)

	test(
		"Gap polish: the hero flies the route in the flight pose; per-frame loops under FrameProf",
		function()
			local tc = src("src/client/Controllers/TravelClient.luau")
			check(
				string.find(tc, "MoveController.travel(at, data.time)", 1, true) ~= nil,
				"the body flies the arc"
			)
			check(
				string.find(tc, "MoveController.endTravel(T.dive)", 1, true) ~= nil,
				"and dives out to land"
			)
			check(
				string.find(tc, 'FrameProf.wrap("TravelClient"', 1, true) ~= nil,
				"the camera under FrameProf"
			)
			check(
				string.find(tc, 'GetAttributeChangedSignal("Traveling")', 1, true) ~= nil,
				"others see it leave and arrive"
			)
			local mc = src("src/client/Controllers/MoveController.luau")
			check(
				string.find(mc, 'FrameProf.wrap("MoveController", stepAll)', 1, true) ~= nil,
				"MoveController under FrameProf"
			)
			check(
				string.find(mc, 'setMode("fly")\nend', 1, true) ~= nil,
				"the flight pose comes from the fly mode"
			)
			check(P.travel.dive >= Config.Fx.landShake.minFall, "the dive lands hard enough for the thud")
			check(
				has("src/client/Fx/GadgetFx.luau", 'FrameProf.wrap("GadgetFx", update)'),
				"GadgetFx under FrameProf"
			)
			check(
				has("src/client/Fx/GadgetFx.luau", "pcall(Preview.clone, char, true)"),
				"the decoy is the owner's own body and look"
			)
		end
	)

	test("Gap polish: the loading card needs nothing and is in the place", function()
		local card = src("src/first/LoadingCard.luau")
		check(string.find(card, "require(", 1, true) == nil, "LoadingCard requires nothing")
		local ls = src("src/first/LoadingScreen.client.luau")
		local n = 0
		for _ in string.gmatch(ls, "require%(") do
			n += 1
		end
		check(
			n == 1 and string.find(ls, 'require(script.Parent:WaitForChild("LoadingCard"))', 1, true) ~= nil,
			"LoadingScreen requires only the card"
		)
		check(
			#string.split(card, "\n") > 50 and string.find(card, "TIPS = {", 1, true) ~= nil,
			"tips on the card"
		)
		if T.placePath then
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(T.placePath))
			local m = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingCard")
			check(m ~= nil and m.ClassName == "ModuleScript", "ReplicatedFirst.LoadingCard is a module")
		end
	end)
end
