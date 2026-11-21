--!nocheck
-- The six new weathers (2026-11-21, Everything Left 735, nate 2026-11-20 22:05Z "all six"): snow with white roofs,
-- blizzard, heatwave, windy days, lightning that strikes roofs, aurora nights. Called from tests/run.luau:
-- ONLY="Weathers" runs these.

local fs = require("@lune/fs")

return function(T)
	local test, check, Config = T.test, T.check, T.Config
	local WeatherPlan = require("../src/shared/WeatherPlan")
	local W = Config.Weather
	local NEW = { "snow", "blizzard", "heatwave", "windy", "electric", "aurora" }

	test("Weathers: six new kinds in the roll, with their rules", function()
		for _, name in NEW do
			check(W.kinds[name] ~= nil and W.kinds[name].weight > 0, name .. " has a weight")
			check(table.find(W.order, name) ~= nil, name .. " is in the order")
			check(type(W.names[name]) == "string", name .. " has a radar name")
		end
		local N = 8000
		local counts, bad = {}, {}
		local function fail(why: string)
			bad[why] = (bad[why] or 0) + 1
		end
		for _, name in W.order do
			counts[name] = 0
		end
		for s = 1, N do
			local prev, cur = WeatherPlan.run(W, s)
			counts[cur] += 1
			if cur == prev and cur ~= "clear" then
				fail("twice in a row")
			end
			if cur == "blizzard" and prev ~= "snow" then
				fail("blizzard without snow first")
			end
			if cur == "electric" and not table.find({ "rain", "overcast", "storm" }, prev) then
				fail("lightning storm out of a clear sky")
			end
			if cur == "snow" and prev == "heatwave" then
				fail("snow after a heatwave")
			end
			if cur == "heatwave" and (prev == "snow" or prev == "blizzard") then
				fail("heatwave after snow")
			end
			if cur == "storm" and prev ~= "rain" then
				fail("storm without rain")
			end
		end
		local msg = {}
		for k, v in bad do
			table.insert(msg, k .. " " .. v)
		end
		check(#msg == 0, "every rule holds: " .. table.concat(msg, ", "))
		for _, name in NEW do
			check(counts[name] > N * 0.01, name .. " comes up: " .. counts[name])
			check(counts[name] < N * 0.12, name .. " stays rare: " .. counts[name])
		end
		check(counts.clear >= N * 0.3, "clear is still the most common: " .. counts.clear)
	end)

	test("Weathers: each look and the blend", function()
		local b = {
			air = {
				Density = 0.3,
				Offset = 0.15,
				Haze = 1.2,
				Glare = 0.2,
				Color = { 235, 199, 168 },
				Decay = { 140, 128, 179 },
			},
			clouds = { cover = 0.55, density = 0.6 },
		}
		local clear = WeatherPlan.mix(W, "clear", "clear", 1, b)
		check(clear.snow == 0 and clear.whiten == 0 and clear.gust == 0 and clear.debris == 0, "clear: none")
		check(
			clear.heat == 0 and clear.aurora == 0 and not clear.strikes,
			"clear: no heat, aurora or strikes"
		)
		check(clear.wind[1] == W.rain.wind[1], "clear: the calm wind")
		local snow = WeatherPlan.mix(W, "clear", "snow", 1, b)
		check(snow.snow == 1 and snow.whiten == 1 and snow.rain == 0, "snow: flakes that settle, no rain")
		local bl = WeatherPlan.mix(W, "snow", "blizzard", 1, b)
		check(bl.snow > 2 and bl.gust > 0.5 and bl.wind[1] > 40, "blizzard: heavy sideways snow and wind")
		check(bl.air.Density > snow.air.Density, "blizzard: a white-out")
		local heat = WeatherPlan.mix(W, "clear", "heatwave", 1, b)
		check(
			heat.heat == 1 and heat.air.Color[1] == 255 and heat.air.Color[3] < 170,
			"heatwave: an orange haze"
		)
		check(heat.grade.saturation > 0, "heatwave: richer colour")
		local windy = WeatherPlan.mix(W, "clear", "windy", 1, b)
		check(windy.gust == 1 and windy.debris == 1 and windy.wind[1] > 30, "windy: gusts and blowing debris")
		local el = WeatherPlan.mix(W, "rain", "electric", 1, b)
		check(
			el.strikes and el.lightning and el.rain > 0 and el.rain < 1,
			"lightning storm: strikes, light rain"
		)
		local au = WeatherPlan.mix(W, "clear", "aurora", 1, b)
		check(au.aurora == 1 and au.clouds.cover < 0.3, "aurora: a clear sky with the curtains")
		local half = WeatherPlan.mix(W, "clear", "windy", 0.5, b)
		check(math.abs(half.gust - 0.5) < 1e-6 and half.wind[1] > W.rain.wind[1], "half way, half the gust")
	end)

	test("Weathers: snow settles and melts; the aurora only at night", function()
		local c = 0
		for _ = 1, W.snow.settle * 10 + 5 do
			c = WeatherPlan.settle(W, c, 1, 0.1)
		end
		check(c == 1, "white after the settle time")
		check(WeatherPlan.settle(W, 0, 1, 1) < 0.05, "not white at once")
		local m = 1
		for _ = 1, W.snow.melt * 10 + 5 do
			m = WeatherPlan.settle(W, m, 0, 0.1)
		end
		check(m == 0, "melted after the melt time")
		check(WeatherPlan.settle(W, 1, 0, 30) > 0.5, "melts slowly")
		check(WeatherPlan.nightShare("day", 0.5) == 0, "no aurora by day")
		check(WeatherPlan.nightShare("night", 0.1) == 1, "full at night")
		check(
			WeatherPlan.nightShare("dusk", 0.3) == 0 and WeatherPlan.nightShare("dusk", 1) == 1,
			"fades in at dusk"
		)
		check(
			WeatherPlan.nightShare("dawn", 0) == 1 and WeatherPlan.nightShare("dawn", 0.5) == 0,
			"out at dawn"
		)
	end)

	test("Weathers: lightning strikes a roof near a hero, never on a hero", function()
		local K = W.strikes
		local roofs = {
			{ id = 3, x = 10, z = 0, sx = 20, sz = 20, top = 80 }, -- too close to the hero
			{ id = 1, x = 120, z = 0, sx = 30, sz = 24, top = 140 },
			{ id = 2, x = -150, z = 40, sx = 20, sz = 20, top = 60 },
		}
		local seen = {}
		for i = 1, 40 do
			local r, at = WeatherPlan.pickRoof(W, roofs, 0, 0, {}, (i - 0.5) / 40, (i * 7 % 40) / 40)
			check(r ~= nil and at ~= nil, "a roof is found")
			if r and at then
				seen[r.id] = true
				check(r.id ~= 3, "never closer than strikes.min")
				check(at[2] == r.top, "on the roof")
				check(
					math.abs(at[1] - r.x) <= r.sx / 2 and math.abs(at[3] - r.z) <= r.sz / 2,
					"inside its box"
				)
			end
		end
		check(seen[1] and seen[2], "both far roofs get struck")
		-- a hero standing on roof 1's corners: only roof 2 now
		local others = {}
		for _, q in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
			table.insert(others, { 120 + q[1] * 12, 140, q[2] * 9 })
		end
		for i = 1, 20 do
			local r = WeatherPlan.pickRoof(W, roofs, 0, 0, others, (i - 0.5) / 20, (i * 3 % 20) / 20)
			check(r and r.id == 2, "not the roof a hero stands on")
		end
		check(
			WeatherPlan.pickRoof(W, { roofs[1] }, 0, 0, {}, 0.5, 0.5) == nil,
			"nothing far enough: no strike"
		)
		local pts = WeatherPlan.strikeBolt(5, 80, 7, 600, 42)
		check(
			pts[#pts][1] == 5 and pts[#pts][2] == 80 and pts[#pts][3] == 7,
			"the bolt ends on the roof point"
		)
		check(pts[1][2] == 600, "from the cloud base")
		check(K.dmg >= Config.Destruction.structure.chunkCost, "a strike knocks at least one piece out")
	end)

	test("Weathers: art, wiring and the Studio hold", function()
		for _, f in { "snow", "paper", "shimmer", "aurora" } do
			check(fs.isFile("art/export/fx/" .. f .. ".png"), f .. ".png drawn")
		end
		check(
			W.snow.texture > 0 and W.debris.paper > 0 and W.heat.texture > 0 and W.aurora.texture > 0,
			"uploaded"
		)
		local function has(path: string, text: string)
			check(string.find(fs.readFile(path), text, 1, true) ~= nil, path .. ": " .. text)
		end
		has("src/shared/Remotes.luau", 'WeatherStrike = { dir = "S2C" }')
		has("src/server/init.server.luau", 'boot("WeatherService", WeatherService.init)')
		has("src/server/Services/WeatherService.luau", "BuildingService.smash(roof.id")
		has("src/client/Fx/WeatherFx.luau", "WeatherLook.step(look, cam, lead, groundY, dt, preset)")
		has("src/client/Fx/WeatherFx.luau", 'Net.listen("WeatherStrike"')
		has("src/client/Fx/CityLife.luau", 'GetAttribute("WeatherGust")')
		has("src/client/Controllers/AudioController.luau", 'GetAttribute("WeatherGust")')
		has("src/client/Ui/Radar.luau", 'me:GetAttribute("Weather")')
		has("src/client/Ui/DevPanel.luau", 'Net.send("DevCommand", "weather", weatherIdx)')
		has("src/server/Services/DevService.luau", "WeatherService.hold(n or 0)")
		-- particle budgets: the heaviest weather per preset stays at or under the rain's
		for _, p in { "low", "medium", "high" } do
			local blizzard = W.snow.flakes[p] * W.kinds.blizzard.snow
				+ W.debris.rate[p] * (W.kinds.blizzard.debris or 0)
			check(
				blizzard <= W.rain.drops[p] * 1.8 + 1,
				p .. ": a blizzard's flakes near a storm's rain: " .. blizzard
			)
		end
	end)

	test("Weathers: every kind runs on a device (sim)", function()
		if not T.placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		sim:run("WeatherFx", sim:require("Client.Fx.WeatherFx").init)
		local WS = sim.game:GetService("Workspace")
		local Run = sim.game:GetService("RunService")
		local function frames(n: number)
			for _ = 1, n do
				sim:advance(1 / 30)
				for _, h in table.clone(Run.Heartbeat.handlers) do
					sim:run("Heartbeat", function()
						h(1 / 30)
					end)
				end
			end
		end
		local cam = WS.CurrentCamera
		local function emitter(part: string, name: string)
			local p = cam:FindFirstChild(part)
			return p and p:FindFirstChild(name)
		end
		for _, kind in W.order do
			WS:SetAttribute("WeatherForce", kind)
			frames(12)
			check(#sim.errors == 0, kind .. ": no errors: " .. table.concat(sim.errors, "; "))
		end
		WS:SetAttribute("WeatherForce", "blizzard")
		frames(5)
		local snow = emitter("WeatherSnow", "Snow")
		check(snow and snow.Rate > 0, "a blizzard snows")
		WS:SetAttribute("WeatherForce", "windy")
		frames(5)
		local leaves = emitter("WeatherWind", "Leaves")
		check(leaves and leaves.Rate > 0, "a windy day blows leaves")
		check(snow and snow.Rate == 0, "and no snow")
		check(
			sim.game:GetService("Players").LocalPlayer:GetAttribute("Weather") == "Windy",
			"the radar's name"
		)
	end)
end
