--!nocheck
-- Planet travel (2026-11-21, Everything Left 736; spec "Fly-in planet travel"): the Orbit Gate, the orbit zone,
-- the approach rings, the moon Calder and the alien planet. Called from tests/run.luau: ONLY="Space" runs these.

local fs = require("@lune/fs")

return function(T)
	local test, check, Config = T.test, T.check, T.Config
	local SpaceLayout = require("../src/shared/SpaceLayout")
	local S = Config.Space

	test("Space: the gate, the orbit and every ring", function()
		check(S ~= nil, "Config.Space is there (parked: on = false until nate picks it up)")
		local pad = { x = 0, y = 690, z = -30 }
		local gate = SpaceLayout.gate(S, pad)
		check(gate.y + gate.r <= Config.Move.ceiling.soft, "the Orbit Gate sits under the flight ceiling")
		check(gate.y > pad.y + 100, "well over the Hall roof")
		check(SpaceLayout.zoneAt(S, gate.x, gate.y, gate.z) == nil, "the gate is in the city")
		local ox, oy, oz = SpaceLayout.orbit(S)
		check(SpaceLayout.zoneAt(S, ox, oy, oz) == "orbit", "the station is in the orbit")
		check(oy > 6000, "the orbit is far above the pockets (3,000) and the HQ cells (4,500)")
		check(
			SpaceLayout.zoneAt(S, 0, 50, 0) == nil and SpaceLayout.zoneAt(S, 0, 3000, 1900) == nil,
			"city and pockets are not space"
		)
		for i, w in S.worlds do
			local r = SpaceLayout.ring(S, i)
			local d = math.sqrt((r.x - ox) ^ 2 + (r.y - oy) ^ 2 + (r.z - oz) ^ 2)
			check(
				d > S.orbit.deck and d < 900,
				w.id .. "'s ring is a short flight from the deck: " .. math.floor(d)
			)
			check(SpaceLayout.zoneAt(S, r.x, r.y, r.z) == "orbit", w.id .. "'s ring is in the orbit")
			-- a flight from the deck straight through the ring passes; one beside it does not
			local a = { ox, oy, oz }
			local b = { r.x + (r.x - ox) * 0.05, r.y + (r.y - oy) * 0.05, r.z + (r.z - oz) * 0.05 }
			check(SpaceLayout.crossed(r, a, b), w.id .. ": flying through the ring counts")
			local miss = { b[1] + r.r * 3, b[2], b[3] + r.r * 3 }
			check(
				not SpaceLayout.crossed(r, { a[1] + r.r * 3, a[2], a[3] + r.r * 3 }, miss),
				w.id .. ": past it does not"
			)
			check(
				SpaceLayout.near(r, { r.x + r.r, r.y, r.z }, S.ringSlack),
				"the server's check takes the ring's edge"
			)
			check(not SpaceLayout.near(r, { ox, oy, oz }, S.ringSlack), "but not the deck")
			-- the planet sits behind its ring, seen from the deck
			local so = w.sphere.offset
			check(
				so[1] * (r.x - ox) + so[2] * (r.y - oy) + so[3] * (r.z - oz) > 0,
				w.id .. ": its ring leads to it"
			)
			check(w.sphere.radius * 2 <= 2048, w.id .. ": the ball fits a Part")
			-- every ring and planet clear of the others
			for j = i + 1, #S.worlds do
				local q = SpaceLayout.ring(S, j)
				check(
					(q.x - r.x) ^ 2 + (q.y - r.y) ^ 2 + (q.z - r.z) ^ 2 > (r.r + q.r + 60) ^ 2,
					w.id .. " and " .. S.worlds[j].id .. " rings apart"
				)
			end
		end
		-- the gate faces up: flying up through it counts
		check(
			SpaceLayout.crossed(gate, { gate.x, gate.y - 5, gate.z }, { gate.x + 2, gate.y + 5, gate.z }),
			"fly up through the gate"
		)
	end)

	test("Space: who can go where, and where they land", function()
		check(not SpaceLayout.canGo(S, 0, S.gate.level - 1), "the orbit needs its level")
		check(SpaceLayout.canGo(S, 0, S.gate.level), "then opens")
		local ironmere, calder
		for i, w in S.worlds do
			if w.id == "Ironmere" then
				ironmere = i
			elseif w.id == "Calder" then
				calder = i
			end
		end
		local ok, why = SpaceLayout.canGo(S, ironmere, 50)
		check(not ok and why == "locked", "Ironmere waits for Act 2")
		ok, why = SpaceLayout.canGo(S, calder, S.worlds[calder].level - 1)
		check(not ok and why == "level", "Calder needs its level")
		check(SpaceLayout.canGo(S, calder, S.worlds[calder].level), "then opens")
		check(SpaceLayout.canGo(S, 1, 1), "home is always open")
		local gate = SpaceLayout.gate(S, { x = 10, y = 690, z = 20 })
		for i, w in S.worlds do
			if w.zone then
				local seen = {}
				for n = 0, 4 do
					local x, y, z = SpaceLayout.arrival(S, i, gate, n)
					check(SpaceLayout.zoneAt(S, x, y, z) == i, w.id .. ": you land in the world")
					local gx, gy, gz = SpaceLayout.ground(S, i)
					check(y >= gy + 150, w.id .. ": high over the ground, still flying")
					check(
						math.abs(x - gx) < w.zone.half and math.abs(z - gz) < w.zone.half,
						"inside its walls"
					)
					local key = math.floor(x) .. "," .. math.floor(z)
					check(not seen[key], "friends land side by side")
					seen[key] = true
				end
				local b = SpaceLayout.back(S, i)
				check(SpaceLayout.zoneAt(S, b.x, b.y, b.z) == i, w.id .. ": its return ring is on it")
				-- far from the city and each other
				local gx, _, gz = SpaceLayout.ground(S, i)
				check(
					math.abs(gx) - w.zone.half > Config.City.mapSize / 2 + 2000,
					w.id .. " is far off the city map"
				)
			end
		end
		local hx, hy, hz = SpaceLayout.arrival(S, 1, gate, 0)
		check(
			SpaceLayout.zoneAt(S, hx, hy, hz) == nil and hy < Config.Move.ceiling.soft,
			"home lands by the gate, in the city"
		)
		local ax, ay, az = SpaceLayout.arrival(S, 0, nil, 0)
		local ox, oy, oz = SpaceLayout.orbit(S)
		check(
			math.abs(ay - oy) < 10 and (ax - ox) ^ 2 + (az - oz) ^ 2 < (S.orbit.deck / 2) ^ 2,
			"the orbit lands on the deck"
		)
	end)

	test("Space: the scenery, in budget", function()
		local orbit = SpaceLayout.orbitRows(S)
		local tags = {}
		for _, r in orbit do
			tags[r.tag] = (tags[r.tag] or 0) + 1
			check(r.s[1] <= 2048 and r.s[2] <= 2048 and r.s[3] <= 2048, "every piece fits a Part: " .. r.tag)
		end
		check(tags.deck == 1 and tags.planet == #S.worlds, "the deck and every planet")
		for i, w in S.worlds do
			check((tags["ring" .. i] or 0) >= 16, w.id .. "'s ring is built")
			if not w.locked then
				check(tags["ship" .. i] == 1, w.id .. " has a ship counter")
			end
		end
		check(#orbit < 400, "the orbit's parts: " .. #orbit)
		for i, w in S.worlds do
			if w.zone then
				local rows = SpaceLayout.worldRows(S, i)
				check(#rows > 100 and #rows < 900, w.id .. "'s parts in budget: " .. #rows)
				local gx, gy, gz = SpaceLayout.ground(S, i)
				local b = SpaceLayout.back(S, i)
				local has = {}
				for _, r in rows do
					has[r.tag] = true
					for k = 1, 3 do
						check(r.s[k] <= 2048, w.id .. ": fits a Part")
					end
					-- nothing solid stands on the landing pad
					if
						r.collide
						and r.tag ~= "ground"
						and r.tag ~= "pad"
						and r.tag ~= "ship0"
						and r.tag ~= "wall"
					then
						local dx, dz = r.p[1] - b.x, r.p[3] - b.z
						check(
							dx * dx + dz * dz > 24 ^ 2 or r.p[2] > gy + 120,
							w.id .. ": the pad is clear (" .. r.tag .. ")"
						)
					end
				end
				check(
					has.ground and has.wall and has.pad and has.ship0,
					w.id .. ": ground, walls, pad, return ship"
				)
				if w.id == "Calder" then
					check(
						has.crater and has.rock and has.probe,
						"Calder: craters, boulders, the crashed probe"
					)
				else
					check(
						has.spire and has.bulb and has.floater and has.pool and has.sun,
						"Thalyx: crystals, plants, floating rocks, pools, two suns"
					)
				end
				check(gx ~= 0 and gz == gz, "placed")
			end
		end
	end)

	test("Space: wiring", function()
		local function has(path: string, text: string)
			check(string.find(fs.readFile(path), text, 1, true) ~= nil, path .. ": " .. text)
		end
		has("src/shared/Remotes.luau", 'SpaceGo = { dir = "C2S", schema = { n(0, 8) }')
		has("src/server/init.server.luau", 'boot("SpaceService", SpaceService.init)')
		has("src/client/init.client.luau", "SpaceClient.init()")
		has("src/server/Services/SpaceService.luau", "HeroService.inCombat(hero)")
		has("src/server/Services/SpaceService.luau", "SpaceLayout.near(ring, p, S.ringSlack)")
		has("src/server/Services/SpaceService.luau", 'hero.scene = "space"')
		has("src/server/Services/SpaceService.luau", "MoveGuard.reset(hero)")
		has("src/server/Services/SpaceService.luau", "Enum.ModelStreamingMode.Persistent")
		has("src/client/Fx/WeatherFx.luau", 'GetAttribute("SpaceZone")')
		has("src/config/init.luau", '"Space",')
	end)

	test("Space: the device's trip runs (sim)", function()
		if not T.placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local SpaceClient = sim:require("Client.Controllers.SpaceClient")
		sim:run("SpaceClient", SpaceClient.init)
		check(#sim.errors == 0, "init: " .. table.concat(sim.errors, "; "))
		local gui = sim.playerGui:FindFirstChild("SpaceTrip")
		check(gui ~= nil or not S.on, "the trip's screen is made (when on)")
	end)
end
