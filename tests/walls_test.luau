-- Walls (nate's playtest 2026-11-18: "Enemies just go through walls. The subway fight is impossible because he just
-- goes through walls"). Two causes, both fixed and both checked here:
--   1. the prologue's subway pocket never told the robots where its walls are (the city answered a flat floor
--      there), so Skylance kept its range by walking out of the fight chamber; EnemyService.usePocket now holds
--      every built pocket's layout (the subway and the mission runs), with its ceilings for fliers
--   2. a ground robot looked one point ahead per tick, so it could step over a thin wall (2 studs) at speed,
--      and fliers, knockbacks, pulls, dashes and shots had no wall check at all; now every move is checked a
--      stud apart out to the body's edge (EnemySim.groundClear, flyClear).
-- The subway fight is replayed in the real subway layout with the real Skylance and Crane Troopers.
-- Called from tests/run.luau: require("./walls_test")({ test = test, check = check, Config = Config })
-- ONLY="Walls" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local EnemySim = require("../src/shared/EnemySim")
	local PocketLayout = require("../src/shared/PocketLayout")
	local BoxKit = require("../src/shared/BoxKit")

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	-- A sim standing in one pocket layout (heights and ceilings from its boxes), as EnemyService gives it
	local function pocketSim(l: any): any
		PocketLayout.heights(l)
		local n = 0
		return EnemySim.new(Config, {
			heightAt = function(x, z)
				return PocketLayout.heightAt(l, x, z)
			end,
			ceilingAt = function(x, z, y)
				return PocketLayout.ceilingAt(l, x, z, y)
			end,
			random = function()
				n += 1
				return (math.sin(n * 12.9898) * 43758.5453) % 1
			end,
		})
	end

	-- A flat sim with these boxes standing on it
	local function boxSim(boxes: { any }): any
		return EnemySim.new(Config, {
			heightAt = function(x, z)
				local top = 0
				for _, b in boxes do
					if math.abs(x - b.cx) <= b.sx / 2 and math.abs(z - b.cz) <= b.sz / 2 then
						top = math.max(top, b.cy + b.sy / 2)
					end
				end
				return top
			end,
			random = function()
				return 0.5
			end,
		})
	end

	local subway = PocketLayout.build(Config, PocketLayout.subwayIndex(Config), "subway")
	local S = Config.Story.opening.subway
	local lane = PocketLayout.lane(Config, 1)
	-- inside lane 1's fight chamber (its inner faces: walls are 2 thick, centred c/2 + 1 out)
	local half = S.chamber / 2
	local czm = lane.z1 - half
	local function inChamber(x: number, z: number): boolean
		return math.abs(x - lane.x) <= half and z <= lane.z1 + 0.5 and z >= lane.z1 - S.chamber
	end
	-- inside the lane's tunnel or its chamber (the only open floor a robot down there may reach)
	local function inLane(x: number, z: number): boolean
		local inTunnel = math.abs(x - lane.x) <= S.width / 2 and z <= lane.z0 and z >= lane.z1
		return inTunnel or inChamber(x, z)
	end

	test("Walls: the subway's walls stand in its heights and its ceilings are known", function()
		PocketLayout.heights(subway)
		local floorY = lane.floorY
		check(PocketLayout.heightAt(subway, lane.x, czm) <= floorY + 1, "the chamber's floor is open")
		check(
			PocketLayout.heightAt(subway, lane.x + half + 1, czm) >= floorY + S.height - 0.5,
			"its side wall is a full-height wall"
		)
		check(
			PocketLayout.heightAt(subway, lane.x, lane.z1 - S.chamber - 1) >= floorY + S.height - 0.5,
			"its back wall too"
		)
		check(
			PocketLayout.heightAt(subway, lane.x + S.width / 2 + 1, (lane.z0 + lane.z1) / 2)
				>= floorY + S.height - 0.5,
			"the tunnel's walls too"
		)
		local c = PocketLayout.ceilingAt(subway, lane.x, czm, floorY + 3)
		check(c ~= nil and math.abs((c :: number) - (floorY + S.height)) < 0.01, "the chamber's ceiling")
		check(
			PocketLayout.ceilingAt(subway, lane.x, (lane.z0 + lane.z1) / 2, floorY + 3) ~= nil,
			"the tunnel's ceiling"
		)
		check(
			PocketLayout.ceilingAt(subway, lane.x, lane.z0 + 10, floorY + 3) == nil,
			"open sky past the steps"
		)
	end)

	-- The prologue's fight: Skylance spawned 14 studs in from the chamber's middle (OpeningService), the hero
	-- walking at it, circling and backing off; then the swarm of Crane Troopers rings the hero
	test(
		"Walls: the subway fight: Skylance never leaves the chamber and the hero can always reach it",
		function()
			local sim = pocketSim(subway)
			local F = Config.Story.opening.fight
			local fx, fy, fz = lane.fight[1], lane.fight[2], lane.fight[3]
			local e = EnemySim.spawn(sim, F.fake, fx, fy, fz - 14, 1) :: any
			check(e ~= nil, "Skylance spawns")
			if not e then
				return
			end
			e.y = lane.floorY + EnemySim.halfHeight(e.cfg)
			local hero =
				{ id = 1, x = fx, y = lane.floorY + 3, z = lane.z1 - 4, alive = true, lx = 0, lz = -1 }
			local left, attacks, spears, dashes = 0, 0, 0, 0
			local worstOut = 0
			local t = 0
			for step = 1, 60 * 100 do
				t = step / 60
				-- the hero: walks at Skylance, then circles it, then backs off (within the chamber)
				local phase = math.floor(t / 10) % 3
				local dx, dz = e.x - hero.x, e.z - hero.z
				local d = math.max(1, math.sqrt(dx * dx + dz * dz))
				local vx, vz = 0, 0
				if phase == 0 then
					vx, vz = dx / d * 16, dz / d * 16
				elseif phase == 1 then
					vx, vz = -dz / d * 16, dx / d * 16
				else
					vx, vz = -dx / d * 10, -dz / d * 10
				end
				local nx, nz = hero.x + vx / 60, hero.z + vz / 60
				if
					inChamber(nx, nz)
					and math.abs(nx - lane.x) <= half - 2
					and nz >= lane.z1 - S.chamber + 2
				then
					hero.x, hero.z = nx, nz
				end
				EnemySim.step(sim, t, { hero })
				for _, ev in EnemySim.drainEvents(sim) do
					if ev.k == "aim" then
						attacks += 1
					elseif ev.k == "shot" then
						spears += 1
					elseif ev.k == "dash" then
						dashes += 1
					end
				end
				if not inLane(e.x, e.z) then
					left += 1
					worstOut = math.max(worstOut, math.abs(e.x - lane.x) - half, (lane.z1 - S.chamber) - e.z)
				end
			end
			check(
				left == 0,
				string.format(
					"Skylance stayed in the chamber or its tunnel (%d ticks out, worst %.1f studs)",
					left,
					worstOut
				)
			)
			check(
				attacks >= 10,
				string.format("it still sights and throws in the small room (%d aims)", attacks)
			)
			check(spears >= 10, string.format("spears flew (%d)", spears))
			check(dashes >= 3, string.format("and it dashes aside where there is room (%d)", dashes))
			check(
				math.abs(e.y - (lane.floorY + EnemySim.halfHeight(e.cfg))) < 0.5,
				"it stands on the floor (never on a wall)"
			)
		end
	)

	test("Walls: the subway swarm: Crane Troopers fly under the ceiling and inside the walls", function()
		local sim = pocketSim(subway)
		local W = Config.Story.opening.swarm
		local hx, hz = lane.x + 6, czm + 4
		local hero = { id = 1, x = hx, y = lane.floorY + 3, z = hz, alive = true }
		local drones = {}
		for i = 1, W.count do
			local a = i / W.count * math.pi * 2
			-- OpeningService's ring, pulled inside the chamber as it does in the subway
			local x, z = PocketLayout.chamberPoint(
				Config,
				lane,
				hx + math.cos(a) * W.ring,
				hz + math.sin(a) * W.ring,
				W.margin
			)
			local d = EnemySim.spawn(sim, W.kind, x, hero.y, z, 1) :: any
			if d then
				table.insert(drones, d)
			end
		end
		check(#drones == W.count, "the swarm spawns")
		local wasIn: { [any]: boolean } = {}
		for _, d in drones do
			check(inChamber(d.x, d.z), "every trooper starts inside the chamber")
		end
		local escaped, overCeiling, shots = 0, 0, 0
		for step = 1, 60 * 30 do
			local t = step / 60
			hero.x = hx + math.sin(t * 0.7) * 10
			EnemySim.step(sim, t, { hero })
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "shot" then
					shots += 1
				end
			end
			for _, d in drones do
				if d.alive then
					local inside = inLane(d.x, d.z)
					if inside then
						wasIn[d] = true
					else
						escaped += 1
					end
					if inside and d.y > lane.floorY + S.height - 1 then
						overCeiling += 1
					end
				end
			end
		end
		local reached = 0
		for _ in wasIn do
			reached += 1
		end
		check(
			escaped == 0,
			string.format("no trooper left the chamber or its tunnel (%d ticks out)", escaped)
		)
		check(overCeiling == 0, string.format("none flew up through the ceiling (%d)", overCeiling))
		check(
			reached == W.count,
			string.format("all of the swarm is in the hero's room (%d of %d)", reached, W.count)
		)
		check(shots > 0, "and they fire")
	end)

	test("Walls: a fast ground robot never steps over a thin wall, at any tick length", function()
		local wall = { cx = 0, cy = 10, cz = 0, sx = 2, sy = 20, sz = 200 } -- a 2-stud wall along z
		for _, kind in { "BruteBot", "Skylance", "Swarmer", "SneakBot" } do
			if EnemySim.enabled(Config, kind) then
				for _, tick in { 1 / 60, 0.1, 0.3 } do
					local sim = boxSim({ wall })
					local e = EnemySim.spawn(sim, kind, -12, 3, 0, 5) :: any
					if e then
						e.y = EnemySim.halfHeight(e.cfg)
						-- the hero on the far side, close enough to be chased or lunged at
						local hero = { id = 1, x = 10, y = 3, z = 0, alive = true, lx = -1, lz = 0 }
						local crossed = false
						for step = 1, math.floor(20 / tick) do
							EnemySim.step(sim, step * tick, { hero })
							EnemySim.drainEvents(sim)
							if e.x > -1 then
								crossed = true
							end
						end
						check(
							not crossed,
							string.format("%s stays on its side of the wall (tick %.3f s)", kind, tick)
						)
					end
				end
			end
		end
	end)

	test("Walls: knockbacks, pulls and nudges stop at a thin wall; a knock reports the wall", function()
		local wall = { cx = 0, cy = 10, cz = 0, sx = 2, sy = 20, sz = 200 }
		local sim = boxSim({ wall })
		local e = EnemySim.spawn(sim, "BruteBot", -8, 3, 0, 5) :: any
		e.y = EnemySim.halfHeight(e.cfg)
		local hitWall = EnemySim.knock(sim, e.id, 1, 0, 40)
		check(hitWall, "the knock reports the wall (Wall Breaker's stun)")
		check(e.x < -1, string.format("and stops before it (x %.1f)", e.x))
		e.x = -6
		EnemySim.push(sim, e.id, 10, 0, 0)
		check(e.x < -1, "a nudge through the wall is refused")
		e.x = -6
		EnemySim.applyStatus(sim, e.id, "pull", 2, { x = 20, y = e.y, z = 0, speed = 60 })
		for step = 1, 30 do
			EnemySim.step(sim, step / 30, {})
		end
		check(
			e.x < -1,
			string.format("a pull from past the wall drags it to the wall, not through (x %.1f)", e.x)
		)
		-- a flier in a tunnel (a ceiling over the wall's height) is knocked into the wall, not through it
		local flier = EnemySim.spawn(sim, "SparkDrone", -8, 8, 0, 5) :: any
		EnemySim.knock(sim, flier.id, 1, 0, 40)
		check(flier.x < -1, "a flier below the wall's top is stopped by it")
	end)

	test("Walls: a robot's shot stops at a thin wall and never hits a hero behind it", function()
		local wall = { cx = 0, cy = 10, cz = 0, sx = 2, sy = 20, sz = 200 }
		local sim = boxSim({ wall })
		local e = EnemySim.spawn(sim, "Sniper", -40, 3, 0, 5) :: any
		check(e ~= nil, "a sniper")
		if not e then
			return
		end
		e.y = EnemySim.halfHeight(e.cfg)
		-- the hero right behind the wall, in its range and line
		local hero = { id = 1, x = 4, y = 3, z = 0, alive = true }
		local hits = 0
		for step = 1, 60 * 20 do
			EnemySim.step(sim, step / 60, { hero })
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "hit" and ev.hero == 1 then
					hits += 1
				end
			end
		end
		check(hits == 0, string.format("no hit through the wall (%d)", hits))
		-- and with no wall the same hero is hit (the shots are real)
		local open = boxSim({})
		local e2 = EnemySim.spawn(open, "Sniper", -40, 3, 0, 5) :: any
		e2.y = EnemySim.halfHeight(e2.cfg)
		local hits2 = 0
		for step = 1, 60 * 20 do
			EnemySim.step(open, step / 60, { hero })
			for _, ev in EnemySim.drainEvents(open) do
				if ev.k == "hit" and ev.hero == 1 then
					hits2 += 1
				end
			end
		end
		check(hits2 > 0, string.format("with no wall it hits (%d)", hits2))
	end)

	test("Walls: a flier climbs over a building instead of jumping onto its roof", function()
		local tower = { cx = 0, cy = 20, cz = 0, sx = 40, sy = 40, sz = 40 } -- a 40-stud block
		local sim = boxSim({ tower })
		local e = EnemySim.spawn(sim, "SparkDrone", -30, 20, 0, 5) :: any
		e.y = 20
		local hero = { id = 1, x = 40, y = 3, z = 0, alive = true } -- in its aggro range, the tower between
		local inside, bigJump = 0, 0
		local lastY = e.y
		for step = 1, 60 * 40 do
			EnemySim.step(sim, step / 60, { hero })
			EnemySim.drainEvents(sim)
			if math.abs(e.x) < 20 - 0.5 and math.abs(e.z) < 20 - 0.5 and e.y < 40 + 3 then
				inside += 1
			end
			if e.y - lastY > 8 then
				bigJump += 1
			end
			lastY = e.y
		end
		check(inside == 0, string.format("never inside the tower (%d ticks)", inside))
		check(bigJump == 0, "never pops up onto the roof in one move")
		check(e.x > 0, string.format("it got past it to the hero (x %.1f)", e.x))
	end)

	test("Walls: EnemyService knows every built pocket: the subway and the mission runs", function()
		local es = fs.readFile("src/server/Services/EnemyService.luau")
		local os_ = fs.readFile("src/server/Services/OpeningService.luau")
		local ms = fs.readFile("src/server/Services/MissionService.luau")
		check(has(es, "function EnemyService.usePocket("), "EnemyService.usePocket")
		check(has(es, "return PocketLayout.heightAt(pl, x, z)"), "heights come from the pocket's layout")
		check(has(es, "ceilingAt = function(x, z, y)"), "and its ceilings")
		check(
			has(os_, "EnemyService.usePocket(PocketLayout.subwayIndex(Config), l)"),
			"the subway registers its layout when it is built"
		)
		check(has(ms, "EnemyService.usePocket(pocket, run.layout)"), "a mission run registers its pocket")
		check(has(ms, "EnemyService.usePocket(run.pocket, nil)"), "and frees it")
		local _ = BoxKit
	end)
end
