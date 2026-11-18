-- Overnight queue item 5 (2026-11-18): the audit of underwater, vehicles, citizens and travel. Each test here
-- failed before its fix (notes/Decisions.md, "Travel audit"). Called from tests/run.luau:
--   require("./travel_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="Travel audit" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local BoxKit = require("../src/shared/BoxKit")
	local Travel = require("../src/shared/Travel")
	local MoveMath = require("../src/shared/MoveMath")
	local MoveCheck = require("../src/shared/MoveCheck")
	local Vehicles = require("../src/shared/Vehicles")
	local CitizenSim = require("../src/shared/CitizenSim")
	local DeepLayout = require("../src/shared/DeepLayout")
	local EnemySim = require("../src/shared/EnemySim")
	local gy = Config.City.ground.y

	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	-- every solid part of the world in a 32-stud grid (an independent copy of the checks the fixes use)
	local CELL = 32
	local function index(lists: { { any } }): any
		local cells: { [number]: { any } } = {}
		for _, list in lists do
			for _, b in list do
				if BoxKit.solid(b) and b.kind ~= "crop" then
					local r = math.sqrt(b.sx * b.sx + b.sz * b.sz) / 2
					for cx = math.floor((b.cx - r) / CELL), math.floor((b.cx + r) / CELL) do
						for cz = math.floor((b.cz - r) / CELL), math.floor((b.cz + r) / CELL) do
							local k = cx * 100000 + cz
							cells[k] = cells[k] or {}
							table.insert(cells[k], b)
						end
					end
				end
			end
		end
		return cells
	end
	-- the first solid box a standing body (radius r, from y0 to y1) at (x, z) would be inside
	local function inside(cells: any, x: number, y0: number, y1: number, z: number, r: number): any
		local list = cells[math.floor(x / CELL) * 100000 + math.floor(z / CELL)]
		for _, b in list or {} do
			if b.cy - b.sy / 2 < y1 and b.cy + b.sy / 2 > y0 then
				local a = math.rad(b.ry or 0)
				local dx, dz = x - b.cx, z - b.cz
				local lx = dx * math.cos(a) - dz * math.sin(a)
				local lz = dx * math.sin(a) + dz * math.cos(a)
				if math.abs(lx) < b.sx / 2 + r and math.abs(lz) < b.sz / 2 + r then
					return b
				end
			end
		end
		return nil
	end
	local lists = { world.hubBoxes }
	for _, plan in world.tilePlans do
		table.insert(lists, plan.boxes)
	end
	for _, lm in world.landmarks do
		table.insert(lists, lm.boxes)
	end
	local solids = index(lists)
	local function what(b: any): string
		return string.format("%s %s at %.0f, %.0f, %.0f", b.kind, b.color, b.cx, b.cy, b.cz)
	end

	test(
		"Travel audit: fast travel lands every hero clear of the beacon, its roof and its neighbours",
		function()
			local W = Config.World
			for id, b in world.beacons do
				local x, y, z = Travel.arrival(W, b)
				-- the body: feet 3 below the root, head 2.5 above it, 1.2 studs round
				local hit = inside(solids, x, y - 2.9, y + 2.5, z, 1.2)
				check(
					hit == nil,
					string.format(
						"beacon %d (%s) lands clear (inside %s)",
						id,
						b.name,
						if hit then what(hit) else ""
					)
				)
				local below = inside(solids, x, y - 40, y - 2.9, z, 0)
				check(
					below ~= nil or y - 3 <= gy + 40,
					string.format("beacon %d (%s) lands over a floor", id, b.name)
				)
			end
			local bs = src("src/server/Services/BeaconService.luau")
			check(has(bs, "Travel.arrival("), "BeaconService lands heroes where Travel.arrival says")
		end
	)

	test("Travel audit: every safehouse respawn point is clear of parts", function()
		for id, s in world.safehouses do
			for k, p in s.respawn do
				local hit = inside(solids, p.x, p.y - 2.9, p.y + 2.5, p.z, 1.2)
				check(
					hit == nil,
					string.format(
						"safehouse %d (%s) respawn %d clear (%s)",
						id,
						s.name,
						k,
						if hit then what(hit) else ""
					)
				)
			end
		end
	end)

	test(
		"Travel audit: a late teleport (lag past the grace second) is accepted, never pulled back",
		function()
			local M, S = Config.Move, Config.Safety
			local cap = MoveMath.speedCap(M, {}, false)
			local st = MoveCheck.new(0, 3, 0, 0)
			-- fast travel 1,200 studs away: the server moves the hero and expects them there
			MoveCheck.reset(st, 0, 3, 0, 0)
			MoveCheck.expect(st, 1200, 40, 0, 0 + S.teleportKeep)
			-- the device still sends the old spot for 1.5 s (a lag spike), then the new one
			for i = 1, 15 do
				local ok = MoveCheck.sample(st, 0, 3, 0, i * 0.1, cap, M, S)
				check(ok, "the old spot while the move is on its way")
			end
			local ok, strike, wait = MoveCheck.sample(st, 1200, 40, 0, 1.6, cap, M, S)
			check(
				ok and not strike and not wait,
				"the late arrival is the expected teleport: no strike, no pull back"
			)
			check(st.x == 1200 and st.z == 0, "and the check measures from there")
			-- once landed the expectation is spent: jumping back is a teleport again
			local ok2, strike2 = MoveCheck.sample(st, 0, 3, 0, 1.7, cap, M, S)
			check(not ok2 and strike2, "the same jump again is no longer expected")
			-- an expectation runs out
			local old = MoveCheck.new(0, 3, 0, 0)
			MoveCheck.expect(old, 900, 3, 0, S.teleportKeep)
			local okLate = MoveCheck.sample(old, 900, 3, 0, S.teleportKeep + 1, cap, M, S)
			check(not okLate, "a jump after the expectation ran out still fails")
			-- a move that lands on time spends the expectation: a later jump back to it is not free
			local onTime = MoveCheck.new(0, 3, 0, 0)
			MoveCheck.reset(onTime, 600, 3, 0, 0)
			MoveCheck.expect(onTime, 600, 3, 0, S.teleportKeep)
			check((MoveCheck.sample(onTime, 600, 3, 0, 0.1, cap, M, S)), "landed on time")
			check(onTime.expect == nil, "the expectation is spent")
			check(S.teleportKeep >= 4 and S.teleportKeep <= 10, "the expectation lasts a few seconds")
			local mg = src("src/server/Services/MoveGuard.luau")
			check(has(mg, "MoveCheck.expect("), "MoveGuard.reset expects the hero where it moved them")
			check(has(mg, "HeroService.byId(hero.id) ~= hero"), "a hero who already left gets no new track")
		end
	)

	test(
		"Travel audit: a fast travel landing never pulls a hero out of a place they were moved to meanwhile",
		function()
			local bs = src("src/server/Services/BeaconService.luau")
			local sh = src("src/server/Services/SafehouseService.luau")
			check(has(sh, "hero.placedAt = os.clock()"), "SafehouseService.place stamps the move")
			check(has(bs, "Travel.landOk("), "arrive asks Travel.landOk")
			check(Travel.landOk({ started = 10 }, nil), "no move since: land")
			check(Travel.landOk({ started = 10 }, 9), "a move before the trip: land")
			check(
				not Travel.landOk({ started = 10 }, 11),
				"moved during the flight (a pocket, the HQ): stay there"
			)
			local uw = src("src/server/Services/UnderwaterService.luau")
			check(has(uw, "hero.traveling"), "a fast travel lets go of a commuter (no skipping the swim)")
		end
	)

	test("Travel audit: citizens' sidewalk graph never walks through a building", function()
		-- the shelters CitizenService gives it
		local shelters = {}
		for _, sh in world.safehouses do
			if sh.district == "Downtown" or sh.district == "OldTown" then
				table.insert(shelters, { x = sh.x, z = sh.z })
			end
		end
		local bt = world.downtown.beacon
		table.insert(shelters, { x = bt.x, z = bt.z + 30 })
		local sim = CitizenSim.new(Config, shelters, 1, CitizenSim.blocker(world, Config))
		check(#sim.shelters == #shelters, "every shelter is on the graph")
		check(
			has(src("src/server/Services/CitizenService.luau"), "CitizenSim.blocker(world, Config)"),
			"the server prunes it"
		)
		for k, sh in sim.shelters do
			local n = sim.nodes[sh.node]
			local len = math.sqrt((sh.x - n.x) ^ 2 + (sh.z - n.z) ^ 2)
			for s = 1, math.ceil(len / 1.5) - 1 do
				local f = s / math.ceil(len / 1.5)
				local h =
					inside(solids, n.x + (sh.x - n.x) * f, n.y + 1.5, n.y + 5, n.z + (sh.z - n.z) * f, 0.6)
				if h then
					check(false, string.format("shelter %d: the last steps in pass through %s", k, what(h)))
					break
				end
			end
		end
		local bad = 0
		for i, n in sim.nodes do
			local hit = inside(solids, n.x, n.y + 1.5, n.y + 5, n.z, 0.6)
			if hit then
				bad += 1
				if bad <= 6 then
					check(false, string.format("node %d at %.0f, %.0f inside %s", i, n.x, n.z, what(hit)))
				end
			end
			for _, m in n.links do
				if m > i then
					local o = sim.nodes[m]
					local len = math.sqrt((o.x - n.x) ^ 2 + (o.z - n.z) ^ 2)
					local steps = math.max(1, math.ceil(len / 1.5))
					for s = 1, steps - 1 do
						local f = s / steps
						local x, z = n.x + (o.x - n.x) * f, n.z + (o.z - n.z) * f
						local h = inside(solids, x, n.y + 1.5, n.y + 5, z, 0.6)
						if h then
							bad += 1
							if bad <= 6 then
								check(false, string.format("link %d-%d through %s", i, m, what(h)))
							end
							break
						end
					end
				end
			end
		end
		check(bad == 0, "no node or link inside a part (" .. bad .. ")")
		-- every node can still reach every other one of its district (no island)
		local seen, queue, head = { [1] = true }, { 1 }, 1
		while head <= #queue do
			local n = queue[head]
			head += 1
			for _, m in sim.nodes[n].links do
				if not seen[m] then
					seen[m] = true
					table.insert(queue, m)
				end
			end
		end
		local downtown = 0
		for i in sim.nodes do
			if sim.nodes[i].x < Config.City.districts.OldTown.minX - 1 or sim.nodes[i].z > 0 then
				downtown += 1
			end
		end
		check(#queue >= downtown * 0.95, "Downtown's sidewalks stay one network")
	end)

	test(
		"Travel audit: a fleeing citizen with no way to a shelter ducks in, never cuts through buildings",
		function()
			-- two islands: a citizen on one, the only shelter on the other
			local sim = CitizenSim.new(Config, {}, 3)
			sim.nodes = {
				{ x = 0, y = 1, z = 0, links = { 2 } },
				{ x = 10, y = 1, z = 0, links = { 1 } },
				{ x = 200, y = 1, z = 0, links = { 4 } },
				{ x = 210, y = 1, z = 0, links = { 3 } },
			}
			sim.shelters = { { x = 205, y = 1, z = 5, node = 4 } }
			sim.citizens = {
				{
					id = 1,
					x = 0,
					y = 1,
					z = 0,
					fx = 0,
					fz = 1,
					state = CitizenSim.WALK,
					color = 1,
					node = 1,
					path = {},
					goal = nil,
					untilT = 0,
				},
			}
			CitizenSim.danger(sim, 0, 0, 30, 10)
			local c = sim.citizens[1]
			for t = 0.1, 3, 0.1 do
				CitizenSim.step(sim, 0.1, t)
				check(c.x <= 10.01, "it never walks off its sidewalks")
			end
			check(c.state == CitizenSim.HIDDEN, "it ducks into the nearest doorway instead")
		end
	)

	test(
		"Travel audit: a flipped vehicle never lands in a building, whichever way the hit pushes it",
		function()
			local DS = Config.Destruction
			local walls: { any } = {}
			for _, list in lists do
				for _, b in list do
					local top, bottom = b.cy + b.sy / 2, b.cy - b.sy / 2
					if BoxKit.solid(b) and b.kind ~= "crop" and top > gy + 2 and bottom < gy + 3 then
						table.insert(walls, b)
					end
				end
			end
			local cells = index({ walls })
			local bad = 0
			for _, v in Vehicles.place(Config) do
				local hx = (if v.ry % 180 == 90 then v.sz else v.sx) / 2
				local hz = (if v.ry % 180 == 90 then v.sx else v.sz) / 2
				for k = 0, 15 do
					local a = k / 16 * math.pi * 2
					local ox, _, oz = Vehicles.flipPose(DS, v, 1, math.cos(a), math.sin(a))
					local x, z = v.x + ox, v.z + oz
					local hit = nil
					for _, p in
						{
							{ -1, -1 },
							{ -1, 1 },
							{ 1, -1 },
							{ 1, 1 },
							{ 0, 0 },
							{ -1, 0 },
							{ 1, 0 },
							{ 0, -1 },
							{ 0, 1 },
						}
					do
						hit = hit or inside(cells, x + p[1] * hx, gy + 0.5, gy + 3, z + p[2] * hz, 0)
					end
					if hit then
						bad += 1
						if bad <= 6 then
							check(
								false,
								string.format(
									"vehicle %d (%s) pushed %d lands in %s",
									v.id,
									v.kind,
									k,
									what(hit)
								)
							)
						end
					end
				end
			end
			check(bad == 0, "every landing is on the road (" .. bad .. " in a building)")
			-- and the room it keeps is the same on every device (the client's arc ends where the server put it)
			local a, b = Vehicles.place(Config), Vehicles.place(Config)
			local x1, _, z1 = Vehicles.flipPose(DS, a[3], 1, 1, 0)
			local x2, _, z2 = Vehicles.flipPose(DS, b[3], 1, 1, 0)
			check(x1 == x2 and z1 == z2, "the same landing on every device")
		end
	)

	test("Travel audit: a vehicle never resets home onto a hero standing in its spot", function()
		local v = Vehicles.place(Config)[1]
		check(Vehicles.occupied(v, v.x, v.z), "a hero in the middle of its spot")
		check(Vehicles.occupied(v, v.x + v.sx / 2 + 1, v.z), "or right against its side")
		check(not Vehicles.occupied(v, v.x + 12, v.z), "a hero across the street is fine")
		local vs = src("src/server/Services/VehicleService.luau")
		check(has(vs, "Vehicles.occupied("), "VehicleService waits while someone stands there")
	end)

	test(
		"Travel audit: every sunken cache and trapped commuter can be reached (none inside a part)",
		function()
			local lay = DeepLayout.build(Config)
			local others = {}
			for _, b in lay.boxes do
				if b.tag ~= "cache" then
					table.insert(others, b)
				end
			end
			local cells = index({ others })
			for _, c in lay.caches do
				local hit = inside(cells, c.x, c.y - 2, c.y + 2, c.z, 1)
				check(
					hit == nil,
					string.format(
						"cache %d (%s) is clear (inside %s)",
						c.id,
						c.area,
						if hit then what(hit) else ""
					)
				)
				-- a swimming hero can float right next to it
				local free = false
				for k = 0, 7 do
					local a = k / 8 * math.pi * 2
					local r = Config.Deep.caches.reach - 2
					local x, z = c.x + math.cos(a) * r, c.z + math.sin(a) * r
					if inside(cells, x, c.y - 1, c.y + 4, z, 1) == nil then
						free = true
					end
				end
				check(free, "cache " .. c.id .. " has open water within reach")
			end
			for _, r in lay.rescues do
				local hit = inside(cells, r.x, r.y - 1, r.y + 1, r.z, 0.5)
				check(
					hit == nil,
					string.format("commuter %d is clear (inside %s)", r.id, if hit then what(hit) else "")
				)
			end
		end
	)

	test("Travel audit: the travel and world packets stay inside an unreliable remote's 900 bytes", function()
		local CitizenBuffer = require("../src/shared/CitizenBuffer")
		local C = Config.Destruction.citizens
		-- every citizen in reach at once (the whole crowd round one player)
		local crowd = {}
		for i = 1, C.max do
			table.insert(crowd, { id = i, state = 0, color = 1, x = i, y = 1, z = 0, fx = 0, fz = 1 })
		end
		local b = CitizenBuffer.encodeFor(1, crowd, 0, 0, C.relevance)
		check(
			buffer.len(b) + 40 <= 900,
			"Citizen.Delta with all " .. C.max .. " citizens: " .. buffer.len(b) .. " bytes"
		)
	end)

	local function seaSim(): any
		local wy = Config.World.coast.waterY
		local seed = 7
		return EnemySim.new(Config, {
			heightAt = function(x, z, y)
				if y and y < wy - 0.5 then
					local f = DeepLayout.floorAt(Config, x, z, y)
					if f then
						return f
					end
				end
				return if DeepLayout.area(Config, x, z) then wy else 0
			end,
			water = function(x, y, z)
				return DeepLayout.underwater(Config, x, y, z)
			end,
			random = function()
				seed = (seed * 1103515245 + 12345) % 2147483648
				return seed / 2147483648
			end,
		})
	end

	test("Travel audit: a sea robot thrown or pushed onto land goes back to the water", function()
		local half = Config.City.mapSize / 2
		for _, kind in { "Diver", "Anchor" } do
			local sim = seaSim()
			local e = EnemySim.spawn(sim, kind, 0, -6, half + 60, 10) :: any
			check(e ~= nil and DeepLayout.underwater(Config, e.x, e.y, e.z), kind .. " starts in the water")
			local hero = { id = 1, x = 0, y = 4, z = half - 80, alive = true }
			for t = 0, 1, 0.1 do
				EnemySim.step(sim, t, { hero })
			end
			-- Lift and Throw lands it on the street (EnemyService.place), or a push carries it ashore
			e.x, e.z = 0, half - 60
			e.y = if e.ai == "flyer" then 7 else 3
			for t = 1.1, 6, 0.1 do
				EnemySim.step(sim, t, { hero })
			end
			check(DeepLayout.underwater(Config, e.x, e.y, e.z), kind .. " is back in the water")
			EnemySim.push(sim, e.id, 0, 0, -200)
			for t = 6.1, 8, 0.1 do
				EnemySim.step(sim, t, { hero })
			end
			check(DeepLayout.underwater(Config, e.x, e.y, e.z), kind .. " pushed ashore swims back too")
		end
	end)

	test("Travel audit: a torpedo pops at the surface, never flies on through the air", function()
		local wy = Config.World.coast.waterY
		local half = Config.City.mapSize / 2
		local sim = seaSim()
		local s = EnemySim.spawn(sim, "TorpedoSentry", 0, -20, half + 300, 10) :: any
		check(s ~= nil, "a sentry on the seabed")
		-- the hero swims in front of it, then leaps out once a torpedo is on its way: it turns up after them
		local hero = { id = 1, x = 0, y = -12, z = half + 340, alive = true }
		local above, fired = false, false
		for t = 0, 14, 0.05 do
			if #sim.shots > 0 then
				fired = true
				hero.y, hero.z = wy + 12, half + 330 -- out of the water, right above
			end
			EnemySim.step(sim, t, { hero })
			for _, shot in sim.shots do
				if shot.y > wy + 0.5 then
					above = true
				end
			end
		end
		check(fired, "the sentry fired")
		check(not above, "no torpedo above the water")
		local fx = src("src/client/Fx/CombatFx.luau")
		check(has(fx, "EnemySim.torpedoDone("), "the device's torpedo pops at the same surface")
		check(
			EnemySim.torpedoDone(Config, wy + 1) and not EnemySim.torpedoDone(Config, wy - 3),
			"torpedoDone"
		)
	end)
end
