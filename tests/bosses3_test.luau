-- bosses-3 (nate 2026-11-19/20, "more bosses", picked Mix): the Storm Colossus, the Swarm Queen and the Quarry Titan.
-- DRAFT names and looks until nate OKs them. What this proves headless (BossSim is the whole fight's rules; the server
-- only feeds it heroes and applies its events):
-- * Schedule: six bosses take turns, still one every 20 to 30 minutes; each new one has its arena in WorldMap.
-- * Each boss's own mechanics: the Colossus hovers, comes down on a timer and at each phase, its rods and roof pads
--   ride heroes up, its gust pushes at any height, its bolts fall on fliers, its clouds linger; the Queen's
--   formations guard it, all three broken expose and drop its core, then re-form; the Titan's slams dig craters and
--   its lava floor burns the ground and not the air.
-- * Fair to every mobility: a party of four of one pick (flight, speed, leap, acrobat, swing), melee only (the
--   worst case: no ranged powers), with a reach model per pick, beats each boss inside its 8 minutes, takes real
--   damage and spends a real share of the fight hitting it. A mixed bot squad wins too.
-- * Budgets: the swarm's drones per preset, and 30 heroes on each boss keep its events and timers small.
-- Called from tests/run.luau. ONLY="bosses-3" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local BossSim = require("../src/shared/BossSim")
	local BossMath = require("../src/shared/BossMath")
	local SwarmShapes = require("../src/shared/SwarmShapes")
	local WorldMap = require("../src/shared/WorldMap")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local GearMath = require("../src/shared/GearMath")
	local Formulas = require("../src/shared/Formulas")
	local Rng = require("../src/shared/Rng")

	local B = Config.Boss
	local NEW = { "StormColossus", "SwarmQueen", "QuarryTitan" }
	local world = T.world or WorldMap.build(Config, 202647)

	local function hero(id: number, x: number, y: number, z: number): BossSim.Hero
		return { id = id, x = x, y = y, z = z, alive = true }
	end

	-- step a sim from `from` for `secs` with these heroes, calling on(ev, t) for every event
	local function run(
		sim: any,
		from: number,
		secs: number,
		heroes: { any },
		on: ((any, number) -> ())?
	): number
		local t = from
		while t < from + secs do
			t += 0.1
			BossSim.step(sim, t, heroes)
			for _, ev in BossSim.drain(sim) do
				if on then
					on(ev, t)
				end
			end
		end
		return t
	end

	test(
		"bosses-3: six bosses take turns, one every 20 to 30 minutes; each new one is a DRAFT with an arena",
		function()
			check(#B.order == 6, "six world bosses in the rotation")
			check(ProfileSchema.BOSSES == #B.order, "the save keeps a kill count for each")
			local seen = {}
			for turn = 0, 11 do
				local id = BossMath.nextInOrder(Config, turn)
				check(B.bosses[id] ~= nil and not B.bosses[id].mission, id .. " is a world boss")
				check(
					turn < 6 or id == BossMath.nextInOrder(Config, turn - 6),
					"the order repeats every six turns"
				)
				seen[id] = true
			end
			for _, id in NEW do
				check(seen[id], id .. " comes up in the rotation")
			end
			check(
				B.schedule.every[1] == 1200 and B.schedule.every[2] == 1800,
				"a boss every 20 to 30 minutes"
			)
			local pages = {}
			for _, id in B.order do
				local def = B.bosses[id]
				check(def.rogues ~= nil and not pages[def.rogues], id .. ": its own Rogues File page")
				pages[def.rogues] = true
			end
			for _, id in NEW do
				local def = B.bosses[id]
				check(def.draft == true, id .. ": marked DRAFT until nate OKs it")
				check(
					Config.BossArt[id] and Config.BossArt[id].set == "Bosses2",
					id .. ": its art is in Art.Bosses2"
				)
				local x, y, z = WorldMap.bossArena(Config, world, id)
				check(x ~= nil and y ~= nil and z ~= nil, id .. ": an arena in the world")
				if x then
					-- the park agent's new Uptown: keep out of it
					check(
						not (x > -1030 and x < -50 and z > -1850 and z < -490),
						id .. ": clear of the new Uptown"
					)
				end
				-- rewards: a boss look and its shiny (never sold, never stats), a badge, a name card title
				check(GearMath.bossStyle(Config, id, false) ~= nil, id .. ": a boss look drops")
				check(
					GearMath.bossStyle(Config, id, true) ~= GearMath.bossStyle(Config, id, false),
					id .. ": and a shiny"
				)
				local badge = false
				for _, g in Config.Badges.groups do
					for _, row in g.badges do
						if row.key == "boss:" .. id then
							badge = true
						end
					end
				end
				check(badge, id .. ": a defeat badge")
			end
			local bx, _, bz = WorldMap.bossArena(Config, world, "StormColossus")
			local bt = world.downtown.beacon
			check(
				bx and math.sqrt((bx - bt.x) ^ 2 + (bz - bt.z) ^ 2) < 400,
				"the Storm Colossus hovers by the Beacon Tower"
			)
		end
	)

	test(
		"bosses-3: the Storm Colossus hovers, comes down on its timer and each phase, and its lifts ride heroes up",
		function()
			local def = B.bosses.StormColossus
			local hv = def.hover
			local sim = BossSim.new(Config, "StormColossus", 0, 0, 0, 1e6, 20, 0, Rng.new(5))
			check(sim.alt == hv.high, "it starts high")
			check(#sim.lifts == def.lifts.rods, "lightning rods round it")
			local lows, ups, lifted = 0, 0, {}
			local h = hero(1, sim.lifts[1].x, 0, sim.lifts[1].z) -- standing on a rod
			local minAlt = math.huge
			run(sim, 0, B.schedule.landing + hv.every + hv.lowFor + 6, { h }, function(ev, t)
				if ev.k == "lower" then
					if ev.on then
						lows += 1
					else
						ups += 1
					end
				elseif ev.k == "lift" then
					table.insert(lifted, { t = t, to = ev.to })
					h.y = 0 -- it fell back down onto the rod
				end
				minAlt = math.min(minAlt, sim.alt)
			end)
			check(lows >= 1 and ups >= 1, string.format("it came down and went back up (%d, %d)", lows, ups))
			check(minAlt <= hv.low + 0.01, string.format("it reached its low height (%.0f)", minAlt))
			local body = def.targets[1]
			check(hv.low + body.at[2] - body.r <= 14, "low, its body's bottom is in a jump's reach")
			check(#lifted >= 2, "the rod rode the hero up, again and again")
			for i = 2, #lifted do
				check(
					lifted[i].t - lifted[i - 1].t >= def.lifts.every - 0.01,
					"a lift once every few seconds"
				)
			end
			check(lifted[1].to > def.lifts.above + 20, "up to its body")
			-- a phase brings it down too
			local s2 = BossSim.new(Config, "StormColossus", 0, 0, 0, 1000, 20, 0, Rng.new(6))
			BossSim.step(s2, B.schedule.landing + 1, {})
			BossSim.drain(s2)
			BossSim.damage(s2, "body", 400)
			local low = false
			for _, ev in BossSim.drain(s2) do
				low = low or (ev.k == "lower" and ev.on)
			end
			check(low and s2.isLow, "phase 2 brings it down")
			-- roof pads: the nearest roofs in reach of its height, never more than `roofs`, kept apart
			local boxes = {}
			for i = 1, 12 do
				local a = i / 12 * math.pi * 2
				table.insert(boxes, { x = math.cos(a) * 90, z = math.sin(a) * 90, top = 30 + i * 6 })
			end
			table.insert(boxes, { x = 10, z = 10, top = 60 }) -- too close to its body
			table.insert(boxes, { x = 120, z = 0, top = 400 }) -- too tall
			table.insert(boxes, { x = 60, z = 60, top = 8 }) -- a shed
			local s3 = BossSim.new(Config, "StormColossus", 0, 0, 0, 1e6, 20, 0, Rng.new(7))
			BossSim.addRoofPads(s3, boxes)
			local pads = 0
			for _, l in s3.lifts do
				if l.kind == "pad" then
					pads += 1
					check(l.y >= 20 and l.y <= hv.high + 20, "a pad on a real roof")
					check(math.sqrt(l.x * l.x + l.z * l.z) >= 40, "never on its body")
				end
			end
			check(pads == def.lifts.roofs, string.format("%d roof pads", pads))
		end
	)

	test(
		"bosses-3: the Colossus's gust pushes at any height, its bolts reach fliers, its clouds linger",
		function()
			local function strikeOf(id: string, heroes: { any }): any
				local sim = BossSim.new(Config, "StormColossus", 0, 0, 0, 1e6, 20, 0, Rng.new(9))
				BossSim.step(sim, B.schedule.landing + 1, {})
				local a
				for _, row in sim.cfg.attacks do
					if row.id == id then
						a = row
					end
				end
				sim.cfg = table.clone(sim.cfg)
				sim.cfg.attacks = { a }
				sim.cfg.counters = nil
				sim.cfg.objectives = { kind = "cannon", hits = 1, list = {} }
				local got
				local ticks = 0
				run(sim, B.schedule.landing + 1, 12, heroes, function(ev)
					if ev.k == "strike" and ev.a == id and not got then
						got = ev
					elseif ev.k == "tick" then
						ticks += #ev.hits
					end
				end)
				return got, ticks
			end
			local front, behind, flier = hero(1, 0, 200, -100), hero(2, 0, 0, 100), hero(3, 0, 120, -60)
			local g = strikeOf("Gust", { front, behind, flier })
			check(g ~= nil and g.push == 60, "the gust pushes")
			local hit = {}
			for _, row in g and g.hits or {} do
				hit[row[1]] = true
			end
			check(hit[1] and hit[3], "it reaches heroes high up in front")
			check(not hit[2], "not the one behind it")
			local high = hero(1, 30, 150, -30)
			local l = strikeOf("Lightning", { high })
			check(
				l ~= nil and l.tall == true and #l.hits > 0,
				"a bolt from the clouds hits a flier above the spot"
			)
			local sim = BossSim.new(Config, "StormColossus", 0, 0, 0, 1e6, 20, 0, Rng.new(10))
			BossSim.step(sim, B.schedule.landing + 1, {})
			BossSim.damage(sim, "body", 1e6 * 0.4) -- phase 2: storm clouds
			BossSim.drain(sim)
			local crowd = {}
			for i = 1, 6 do
				crowd[i] = hero(i, math.cos(i) * 50, 70, math.sin(i) * 50)
			end
			local zones, tickHits, maxZones = 0, 0, 0
			run(sim, B.schedule.landing + 1, 90, crowd, function(ev)
				if ev.k == "strike" and ev.shape == "zone" then
					zones += 1
				elseif ev.k == "tick" then
					tickHits += #ev.hits
				end
				maxZones = math.max(maxZones, #sim.zones)
			end)
			check(
				zones > 0 and tickHits > 0,
				string.format("clouds linger and hurt (%d, %d ticks)", zones, tickHits)
			)
			check(maxZones <= 6, "never more than a few at once")
		end
	)

	test(
		"bosses-3: the Swarm Queen's formations guard it; all broken expose its core, then they re-form",
		function()
			local def = B.bosses.SwarmQueen
			local g = def.guard
			local sim = BossSim.new(Config, "SwarmQueen", 0, 0, 0, 1e6, 20, 0, Rng.new(12))
			BossSim.step(sim, B.schedule.landing + 1, {})
			local dealt = BossSim.damage(sim, "core", 100)
			check(math.abs(dealt - 100 * g.guarded) < 1e-6, "guarded: the core takes a share")
			for _, ob in sim.objectives do
				local _, y = BossSim.objectivePos(sim, ob)
				check(y - sim.y <= 14, "a formation node within reach of the ground")
				BossSim.damage(sim, "obj" .. ob.idx, 1e9)
			end
			local t = B.schedule.landing + 1
			local exposedAt, closedAt
			local minAlt = math.huge
			t = run(sim, t, g.reform + 4, {}, function(ev, tt)
				if ev.k == "exposed" then
					if ev.on then
						exposedAt = tt
					else
						closedAt = tt
					end
				end
				if sim.exposed then
					minAlt = math.min(minAlt, sim.alt)
					local d = BossSim.damage(sim, "core", 0.001)
					check(math.abs(d - 0.001 * g.exposed) < 1e-9, "exposed: the core takes x" .. g.exposed)
				end
			end)
			check(exposedAt ~= nil, "all three broken: the core is exposed")
			check(minAlt <= def.hover.low + 0.01, "and it crashes down")
			check(
				closedAt ~= nil and math.abs(closedAt - exposedAt - g.reform) < 0.25,
				"the swarm re-forms after it"
			)
			for _, ob in sim.objectives do
				check(ob.alive and ob.hp == ob.maxHp, "every formation back at full strength")
			end
			local up = BossSim.damage(sim, "core", 100)
			check(math.abs(up - 100 * g.guarded) < 1e-6, "guarded again")
		end
	)

	test(
		"bosses-3: the swarm's drones fit every phone budget, read as thousands, and keep their shapes",
		function()
			local def = B.bosses.SwarmQueen
			local lowN = SwarmShapes.budget(def, "low")
			local medN = SwarmShapes.budget(def, "medium")
			local highN = SwarmShapes.budget(def, "high")
			check(lowN <= 100 and medN <= 200 and highN <= 320, "drone parts within the preset budgets")
			check(lowN < medN and medN < highN, "more on better devices")
			check(SwarmShapes.looksLike(def, "high") >= 2000, "high reads as thousands")
			check(SwarmShapes.looksLike(def, "medium") >= 1000, "medium reads as a thousand and more")
			check(def.swarm.rate.low * lowN <= 2000, "low moves under 2,000 drones a second")
			local groundY = -(30 + def.hover.high)
			local all = { true, true, true }
			for _, form in def.forms do
				for i = 1, highN do
					local x, y, z = SwarmShapes.target(i, highN, form, 3, groundY, all, false, nil)
					check(x == x and y == y and z == z, form .. ": a real spot")
					check(y >= groundY - 0.5, form .. ": never under the ground")
					check(math.abs(x) <= 80 and math.abs(z) <= 80, form .. ": round the core")
				end
			end
			-- the fists are balls round their nodes
			for i = 1, 60 do
				local gi = SwarmShapes.group(i)
				if gi < 3 then
					local x, y, z = SwarmShapes.target(i, 60, "fists", 1, groundY, all, false, nil)
					local node = def.objectives.list[gi].at
					local nx, ny, nz = node[1], node[2] - 30 + 8, node[3] -- the node from the core (30 up), a fist's centre
					check(
						math.sqrt((x - nx) ^ 2 + (y - ny) ^ 2 + (z - nz) ^ 2) <= 16,
						"a fist's drone by its node"
					)
				end
			end
			-- a broken formation's drones drop; exposed, every drone does
			for i = 1, 30 do
				local _, y =
					SwarmShapes.target(i, 30, "wall", 2, groundY, { false, false, false }, false, nil)
				check(y <= groundY + 4, "a broken formation's drones lie on the ground")
				local _, y2 = SwarmShapes.target(i, 30, "giant", 2, groundY, all, true, nil)
				check(y2 <= groundY + 4, "exposed: every drone is down")
			end
			-- an attack pulls its formation to where it lands
			local pt = { { 60, groundY + 2, -80 } }
			local x, y, z =
				SwarmShapes.target(1, 30, "fists", 0, groundY, all, false, { group = 1, f = 1, points = pt })
			check(
				math.abs(y - pt[1][2]) < 0.01 and math.abs(x - 60) < 6 and math.abs(z + 80) < 6,
				"a fist lands on its spot"
			)
			check(
				SwarmShapes.strikeGroup("Stingers") == 0 and SwarmShapes.strikeGroup("Unknown") == nil,
				"strike groups"
			)
			-- the giant stands on the ground
			local low = math.huge
			for i = 1, highN do
				local _, yy = SwarmShapes.target(i, highN, "giant", 0, groundY, all, false, nil)
				low = math.min(low, yy)
			end
			check(low <= groundY + 4, "the giant's legs reach the ground")
		end
	)

	test(
		"bosses-3: the Quarry Titan's slams dig craters; its lava floor burns the ground, not the air",
		function()
			local sim = BossSim.new(Config, "QuarryTitan", 0, 0, 0, 1e6, 20, 0, Rng.new(14))
			BossSim.step(sim, B.schedule.landing + 1, {})
			BossSim.damage(sim, "body", 1e6 * 0.4) -- phase 2: the lava floor
			BossSim.drain(sim)
			local ground, air = {}, {}
			for i = 1, 4 do
				local a = i * 1.5
				ground[i] = hero(i, math.cos(a) * 40, 0, math.sin(a) * 40)
				air[i] = hero(10 + i, math.cos(a) * 40, 30, math.sin(a) * 40)
			end
			local heroes = table.clone(ground)
			for _, h in air do
				table.insert(heroes, h)
			end
			local craters, burnGround, burnAir = 0, 0, 0
			run(sim, B.schedule.landing + 1, 120, heroes, function(ev)
				if ev.k == "strike" and ev.crater then
					craters += 1
					check(ev.crater > 0 and ev.crater <= 30, "a crater a fair size")
				elseif ev.k == "tick" and ev.a == "LavaFloor" then
					for _, hit in ev.hits do
						if hit[1] >= 10 then
							burnAir += 1
						else
							burnGround += 1
						end
					end
				end
			end)
			check(craters > 0, string.format("its hits dig craters (%d)", craters))
			check(burnGround > 0, string.format("lava burns heroes on the floor (%d)", burnGround))
			check(burnAir == 0, "and never the ones above it")
		end
	)

	-- The mobility model (Config.Move.mobility at rank 0, rounded down): how fast a pick runs, how high above the ground
	-- its melee hit lands without help (a jump; acrobat air jumps; a leap's arc, half the time; a swing from the
	-- buildings round it) and how long it stays by a boss's body after a lift's updraft (acrobat's air jumps and glide
	-- the longest). Flight goes anywhere. Melee lands within 12 studs of a target's surface.
	local MOB = {
		flight = { run = 45, up = math.huge, air = math.huge },
		speed = { run = 60, up = 10, air = 1.0 },
		leap = { run = 40, up = 55, air = 1.6, duty = 0.5 },
		acrobat = { run = 30, up = 30, air = 3.0 },
		swing = { run = 45, up = 60, air = 2.2, duty = 0.7 },
	}
	local REACH, LEVEL = 12, 20

	-- One fight: these heroes ({ mob, ranged? }) against a boss at the origin, as players would: each goes for what it
	-- can reach (formations and vents first, the core when exposed, else the body), rides lifts when nothing is in reach,
	-- dodges half the telegraphs aimed at it, takes the boss's pushes, yanks and drops, and is down 20 s at 0 HP.
	local function fight(
		id: string,
		party: { { mob: string, ranged: boolean? } },
		seed: number
	): { [string]: any }
		local maxHp = BossMath.maxHp(Config, #party, LEVEL, 0)
		local sim = BossSim.new(Config, id, 0, 0, 0, maxHp, LEVEL, 0, Rng.new(seed))
		local rng = Rng.new(seed + 1)
		local hpMax = Formulas.health(Config, LEVEL, 0, Config.Classes.default)
		local power = Config.Stats.power.base + Config.Stats.power.perLevel * LEVEL
		local heroes, st = {}, {}
		for i, p in party do
			local a = (i - 1) / #party * math.pi * 2 + 0.3
			heroes[i] = hero(i, math.cos(a) * 120, 0, math.sin(a) * 120)
			st[i] = {
				m = MOB[p.mob],
				mob = p.mob,
				ranged = p.ranged == true,
				hp = hpMax,
				downUntil = 0,
				airUntil = 0,
				arcUntil = 0,
				dodgeUntil = 0,
				hitting = 0,
				alive = 0,
				taken = 0,
				downs = 0,
				lifts = 0,
			}
		end
		local t, dt = 0, 0.1
		BossSim.step(sim, 0, heroes)
		local stopAt = B.schedule.landing + B.schedule.lifespan
		local lowered = 0
		local function moveToward(h: any, x: number, z: number, speed: number)
			local dx, dz = x - h.x, z - h.z
			local d = math.sqrt(dx * dx + dz * dz)
			local s = speed * dt
			if d <= s then
				h.x, h.z = x, z
			else
				h.x += dx / d * s
				h.z += dz / d * s
			end
		end
		-- the best target this hero can hit from (x, y, z), or (for planning) from the ground beside it
		local function pick(i: number, fromGround: boolean): any?
			local h, s = heroes[i], st[i]
			local best, bestScore = nil, -1
			for _, tg in BossSim.targets(sim) do
				local ok
				local dx, dy, dz = tg.x - h.x, tg.y - h.y, tg.z - h.z
				if s.ranged then
					ok = math.sqrt(dx * dx + dy * dy + dz * dz) <= 150 + tg.r
				elseif s.mob == "flight" then
					ok = true -- it flies to whatever it wants
				elseif fromGround then
					local gap = tg.y - tg.r - sim.y
					ok = gap <= s.m.up + REACH
					if ok and gap > 10 + REACH and s.m.duty then
						ok = rng:chance(s.m.duty) -- a leap's or a swing's arc is only up there part of the time
					end
				else
					-- in the air after a lift: air control carries it a few studs to what it wants
					ok = math.sqrt(dx * dx + dy * dy + dz * dz) <= tg.r + REACH + 8
				end
				if ok then
					local score = if tg.objective
						then 3
						elseif tg.weak and (sim.exposed or not sim.cfg.guard) then 2
						elseif tg.weak then 0.5
						else 1
					if score > bestScore then
						best, bestScore = tg, score
					end
				end
			end
			return best
		end
		-- is this hero where the warned hit lands (a player only dodges what is coming at them)
		local function danger(ev: any, h: any): boolean
			for _, p in ev.shots or {} do
				if p[4] == h.id then
					return true
				end
			end
			if ev.shape == "circles" or ev.shape == "zone" then
				for _, p in ev.points or {} do
					if (h.x - p[1]) ^ 2 + (h.z - p[2]) ^ 2 <= (ev.r + 10) ^ 2 then
						return true
					end
				end
				return false
			elseif ev.shape == "homing" or ev.shape == "tether" then
				return false
			end
			local r = (ev.r or ev.length or 60) + 10
			return (h.x - ev.x) ^ 2 + (h.z - ev.z) ^ 2 <= r * r
		end
		while t < stopAt and sim.state ~= "dead" and sim.state ~= "retreat" do
			t += dt
			if sim.isLow then
				lowered += dt
			end
			for i, h in heroes do
				local s = st[i]
				h.alive = t >= s.downUntil
				if not h.alive then
					continue
				end
				if s.downUntil > 0 and s.hp <= 0 then
					s.hp = hpMax
					h.x, h.y, h.z = math.cos(i) * 150, 0, math.sin(i) * 150 -- back from the respawn
				end
				s.alive += dt
				if t < s.arcUntil then
					continue -- riding the updraft
				end
				if t < s.dodgeUntil then
					continue
				end
				local inAir = t < s.airUntil
				if not inAir and h.y > 0 and s.mob ~= "flight" then
					h.y = 0 -- fell back down
				end
				if sim.state ~= "fight" then
					continue
				end
				local tg = pick(i, not inAir and s.mob ~= "flight" and not s.ranged)
				if tg then
					if s.ranged then
						BossSim.damage(sim, tg.key, power * dt)
						s.hitting += dt
					else
						-- go to it (beside it, out of its middle), then hit
						local dx, dz = h.x - tg.x, h.z - tg.z
						local d = math.sqrt(dx * dx + dz * dz)
						if d < 1e-3 then
							dx, dz, d = 1, 0, 1
						end
						local gx, gz = tg.x + dx / d * (tg.r + 6), tg.z + dz / d * (tg.r + 6)
						if s.mob == "flight" then
							h.y += math.clamp(tg.y - h.y, -s.m.run * dt, s.m.run * dt)
						end
						moveToward(h, gx, gz, s.m.run)
						local ex, ey, ez = tg.x - h.x, tg.y - h.y, tg.z - h.z
						local flatOk = math.sqrt(ex * ex + ez * ez) <= tg.r + REACH
						local upOk = if s.mob == "flight" or inAir
							then math.abs(ey) <= tg.r + REACH
							else tg.y - tg.r - h.y <= s.m.up + REACH
						if flatOk and upOk then
							BossSim.damage(sim, tg.key, power * 1.25 * dt)
							s.hitting += dt
						end
					end
				elseif #sim.lifts > 0 and not inAir then
					-- nothing in reach: run to the nearest lift and stand on it
					local best, bd = nil, math.huge
					for _, l in sim.lifts do
						local d = (l.x - h.x) ^ 2 + (l.z - h.z) ^ 2
						if d < bd then
							best, bd = l, d
						end
					end
					if best then
						if best.kind == "pad" then
							-- a roof: climbing (acrobat 40/s), a wall run, a leap or a swing gets there
							h.y = best.y
						end
						moveToward(h, best.x, best.z, s.m.run)
					end
				end
			end
			BossSim.step(sim, t, heroes)
			for _, ev in BossSim.drain(sim) do
				if ev.k == "warn" then
					for i, h in heroes do
						if h.alive and danger(ev, h) and rng:chance(0.5) and t >= st[i].arcUntil then
							st[i].dodgeUntil = t + math.min(ev.t, 1)
							local ux, uz = h.x - ev.x, h.z - ev.z
							local l = math.sqrt(ux * ux + uz * uz)
							if l < 1e-3 then
								ux, uz, l = 1, 0, 1
							end
							h.x += ux / l * 40
							h.z += uz / l * 40
						end
					end
				elseif ev.k == "lift" then
					local h, s = heroes[ev.id], st[ev.id]
					-- BossService: HeroKnock up to ev.to, in to 30 studs from its middle, over 1.1 s
					local dx, dz = ev.bx - h.x, ev.bz - h.z
					local d = math.sqrt(dx * dx + dz * dz)
					if d > 34 then
						h.x += dx / d * (d - 30)
						h.z += dz / d * (d - 30)
					end
					h.y = ev.to
					s.arcUntil = t + 1.1
					s.airUntil = t + 1.1 + s.m.air
					s.lifts += 1
				elseif ev.k == "strike" or ev.k == "tick" then
					for _, hit in ev.hits do
						local h, s = heroes[hit[1]], st[hit[1]]
						s.hp -= hit[2]
						s.taken += hit[2]
						if ev.push then
							local ux, uz = h.x - sim.x, h.z - sim.z
							local l = math.max(1e-3, math.sqrt(ux * ux + uz * uz))
							h.x += ux / l * ev.push
							h.z += uz / l * ev.push
						end
						if ev.yank then
							local ux, uz = h.x - sim.x, h.z - sim.z
							local l = math.max(1e-3, math.sqrt(ux * ux + uz * uz))
							h.x, h.z = sim.x + ux / l * ev.yank, sim.z + uz / l * ev.yank
						end
						if ev.drop and s.mob ~= "flight" then
							s.airUntil = 0
						end
						if s.hp <= 0 then
							s.downUntil = t + 20
							s.downs += 1
							s.airUntil, s.arcUntil = 0, 0
						end
					end
				end
			end
		end
		local secs = t - B.schedule.landing
		local taken, alive, hitting, downs, lifts = 0, 0, 0, 0, 0
		for _, s in st do
			taken += s.taken
			alive += s.alive
			hitting += s.hitting
			downs += s.downs
			lifts += s.lifts
		end
		return {
			won = sim.state == "dead",
			secs = secs,
			perMin = taken / #party / hpMax / (secs / 60),
			uptime = hitting / math.max(alive, 1),
			downs = downs,
			lifts = lifts,
			lowered = lowered,
			hp = sim.hp / sim.maxHp,
		}
	end

	test(
		"bosses-3: a melee party of every mobility beats every new boss in time, takes real hits, really hits",
		function()
			for _, id in NEW do
				for k, mob in Config.Move.mobilityOrder do
					local party = {}
					for i = 1, 4 do
						party[i] = { mob = mob }
					end
					local r = fight(id, party, 100 + k)
					print(
						string.format(
							"  [bosses-3] %-13s %-8s %s in %3.0f s (%2.0f%% left), %.2f HP/min, %2d downs, hitting %2.0f%%, %d lifts",
							id,
							mob,
							if r.won then "won " else "LOST",
							r.secs,
							r.hp * 100,
							r.perMin,
							r.downs,
							r.uptime * 100,
							r.lifts
						)
					)
					local where = id .. " vs " .. mob
					check(r.won, where .. ": a melee party wins inside the boss's 8 minutes")
					check(
						r.perMin >= 0.15,
						string.format("%s: takes real damage (%.2f HP a minute)", where, r.perMin)
					)
					check(
						r.uptime >= 0.25,
						string.format("%s: spends real time hitting it (%.0f%%)", where, r.uptime * 100)
					)
					if id == "StormColossus" and mob ~= "flight" then
						check(r.lifts > 0, where .. ": rides the lifts up")
					end
				end
			end
		end
	)

	test("bosses-3: a mixed bot squad (one of each pick, some ranged) beats every new boss", function()
		local squad = {
			{ mob = "flight", ranged = true },
			{ mob = "speed" },
			{ mob = "leap", ranged = true },
			{ mob = "acrobat" },
			{ mob = "swing" },
		}
		for k, id in NEW do
			local r = fight(id, squad, 300 + k)
			print(
				string.format(
					"  [bosses-3] %-13s squad    %s in %3.0f s, %.2f HP/min, %d downs, hitting %.0f%%",
					id,
					if r.won then "won " else "LOST",
					r.secs,
					r.perMin,
					r.downs,
					r.uptime * 100
				)
			)
			check(r.won, id .. ": the squad wins")
			check(r.secs >= 90, string.format("%s: not a pushover (%.0f s)", id, r.secs))
		end
	end)

	test("bosses-3: 30 heroes on each new boss keep its timers, zones and events small", function()
		for k, id in NEW do
			local sim = BossSim.new(Config, id, 0, 0, 0, 1e9, 30, 0, Rng.new(400 + k))
			local heroes = {}
			for i = 1, 30 do
				local a = i / 30 * math.pi * 2
				heroes[i] = hero(i, math.cos(a) * (30 + i * 4), (i % 3) * 40, math.sin(a) * (30 + i * 4))
			end
			BossSim.addRoofPads(sim, {})
			local events, maxPending, maxZones = 0, 0, 0
			local t0 = os.clock()
			run(sim, 0, 120, heroes, function()
				events += 1
				maxPending = math.max(maxPending, #sim.pending)
				maxZones = math.max(maxZones, #sim.zones)
			end)
			local ms = (os.clock() - t0) / 1200 * 1000
			print(
				string.format(
					"  [bosses-3] %-13s 30 heroes: %.1f events/s, %d pending, %d zones, %.3f ms a step",
					id,
					events / 120,
					maxPending,
					maxZones,
					ms
				)
			)
			check(events / 120 <= 12, id .. ": a few events a second")
			check(maxPending <= 10, id .. ": a handful of attacks in flight")
			check(maxZones <= 6, id .. ": a handful of zones")
			check(#sim.lifts <= 8, id .. ": a handful of lifts")
			check(ms < 2, string.format("%s: a step is cheap (%.3f ms)", id, ms))
		end
	end)
end
