-- Boss counters (nate's playtest 2026-11-19): "Boss is stuck between building. Idk if you need to make sure he gets
-- unstuck or just make sure he destroys all the buildings he runs into. Remember that bosses need to be able to fight
-- anyone with any power/mobility. Seems like a lot of bosses I can just fly stepping with ranged moves."
-- * Stuck: Rustjaw walks through the real city (WorldMap seed 202647, BuildingState) on chase paths in every
--   direction: it smashes what is in its way (the smashes are applied to the book, inside the collapse caps), slides
--   round pinned buildings, is never inside one, and never goes nowhere for longer than the unstick time.
-- * Counters: every boss reaches a hero in the air, hovering by it, and far away; melee heroes on the ground are not
--   their targets.
-- * Balance: a party of pure-flying ranged heroes and a party of pure-melee heroes both take meaningful damage and
--   both win, on every boss.
-- Called from tests/run.luau. ONLY="Boss counters" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local WorldMap = require("../src/shared/WorldMap")
	local BuildingState = require("../src/shared/BuildingState")
	local BossSim = require("../src/shared/BossSim")
	local BossMath = require("../src/shared/BossMath")
	local IncidentSpots = require("../src/shared/IncidentSpots")
	local Formulas = require("../src/shared/Formulas")
	local Rng = require("../src/shared/Rng")

	local B = Config.Boss
	local D = Config.Destruction
	local world = T.world or WorldMap.build(Config, 202647)

	local function hero(id: number, x: number, y: number, z: number): BossSim.Hero
		return { id = id, x = x, y = y, z = z, alive = true }
	end

	local function insideBox(x: number, z: number, b: any, pad: number): boolean
		return math.abs(x - b.x) < b.sx / 2 - pad and math.abs(z - b.z) < b.sz / 2 - pad
	end

	-- Rustjaw's arena as BossService.findArenas picks it
	local function rustArena(): (number, number, number)
		local bt = world.downtown.beacon
		local pitch = Config.City.downtown.block + Config.City.downtown.street
		return IncidentSpots.groundNear(Config, world, bt.x, bt.z + pitch * 0.6, 50, Rng.new(53))
	end

	-- One chase: heroes stand at `spot`; the boss walks there through the city for `secs`. Smashes go to the book.
	local function chase(book: any, spot: { number }, secs: number, flier: boolean?): { [string]: any }
		local ax, ay, az = rustArena()
		local sim = BossSim.new(Config, "RustjawPrime", ax, ay, az, 1e9, 20, 0, Rng.new(7))
		sim.blocks = function(x, z, r)
			return BuildingState.boxesNear(book, x, z, r)
		end
		BossSim.step(sim, 6, {})
		local h = hero(1, spot[1], ay + (if flier then 60 else 0), spot[2])
		local out = { smashes = 0, leaps = 0, worstStill = 0, insidePinned = 0, sim = sim }
		local still, lastX, lastZ = 0, sim.x, sim.z
		local t = 6
		while t < 6 + secs do
			t += 0.1
			BossSim.step(sim, t, { h })
			for _, ev in BossSim.drain(sim) do
				if ev.k == "smash" then
					out.smashes += 1
					BuildingState.blast(D, book, ev.id, ev.x, ev.y, ev.z, ev.r, ev.dmg, t)
				elseif ev.k == "strike" and ev.a == "Leap" then
					out.leaps += 1
				end
			end
			for _, b in BuildingState.boxesNear(book, sim.x, sim.z, 2) do
				if b.pinned and insideBox(sim.x, sim.z, b, 0.5) then
					out.insidePinned += 1
				end
			end
			-- seconds going nowhere while it still wants to close in (not at its leash, not attacking)
			local d = math.sqrt((h.x - sim.x) ^ 2 + (h.z - sim.z) ^ 2)
			local hx, hz = sim.x - sim.homeX, sim.z - sim.homeZ
			local atLeash = hx * hx + hz * hz >= (sim.cfg.arenaRadius - 1) ^ 2
			local lastD = math.sqrt((h.x - lastX) ^ 2 + (h.z - lastZ) ^ 2)
			if d > 45 and not atLeash and #sim.pending == 0 and lastD - d < 0.1 then
				still += 0.1 -- wants to close in and got no closer (sliding along a wall counts as stuck)
			elseif lastD - d >= 0.1 then
				still = 0
			end
			out.worstStill = math.max(out.worstStill, still)
			lastX, lastZ = sim.x, sim.z
		end
		local d = math.sqrt((h.x - sim.x) ^ 2 + (h.z - sim.z) ^ 2)
		local hx, hz = sim.x - sim.homeX, sim.z - sim.homeZ
		out.closed = d <= 75 or hx * hx + hz * hz >= (sim.cfg.arenaRadius - 2) ^ 2
		out.dist = d
		return out
	end

	test(
		"Boss counters: Rustjaw smashes through the city on every chase path and never gets stuck",
		function()
			local ax, _, az = rustArena()
			local book = BuildingState.new(D, world.buildings)
			local smashes, leaps = 0, 0
			local u = B.bosses.RustjawPrime.unstick
			for i = 0, 15 do
				local a = i / 16 * math.pi * 2
				for _, dist in { 140, 330 } do
					local spot = { ax + math.cos(a) * dist, az + math.sin(a) * dist }
					local r = chase(book, spot, 150, i % 2 == 1)
					smashes += r.smashes
					leaps += r.leaps
					local where = string.format("dir %d at %d", i, dist)
					check(r.insidePinned == 0, where .. ": never inside a pinned building")
					check(
						r.worstStill <= u.after + 2.5,
						string.format("%s: never stuck (still %.1f s)", where, r.worstStill)
					)
					check(r.closed, string.format("%s: it closes in (%.0f studs off)", where, r.dist))
				end
			end
			check(smashes > 0, string.format("it smashed its way through buildings (%d smashes)", smashes))
			print(string.format("  [Boss counters] chase paths: %d smashes, %d leaps", smashes, leaps))
		end
	)

	test("Boss counters: pinned buildings push it round; boxed in, it leaps to open ground", function()
		-- a synthetic street: a pinned block straight in its way, then the boss boxed in by pinned blocks
		local pinned = {
			{ id = 1, x = 0, z = -60, sx = 60, sz = 20, top = 200, pinned = true },
		}
		local sim = BossSim.new(Config, "RustjawPrime", 0, 0, 0, 1e9, 20, 0, Rng.new(3))
		sim.blocks = function()
			return pinned
		end
		BossSim.step(sim, 6, {})
		local h = hero(1, 0, 0, -150)
		local t, inside, leaps = 6, 0, 0
		for _ = 1, 600 do
			t += 0.1
			BossSim.step(sim, t, { h })
			for _, ev in BossSim.drain(sim) do
				if ev.k == "strike" and ev.a == "Leap" then
					leaps += 1
				end
				check(ev.k ~= "smash", "a pinned building is never smashed")
			end
			if insideBox(sim.x, sim.z, pinned[1], 0.5) then
				inside += 1
			end
		end
		check(inside == 0, "never inside the pinned block")
		check(sim.z < -70 or leaps > 0, string.format("it got past it (z %.0f, %d leaps)", sim.z, leaps))
		-- boxed in on all four sides
		local walls = {
			{ id = 1, x = 0, z = -30, sx = 80, sz = 10, top = 200, pinned = true },
			{ id = 2, x = 0, z = 30, sx = 80, sz = 10, top = 200, pinned = true },
			{ id = 3, x = -30, z = 0, sx = 10, sz = 80, top = 200, pinned = true },
			{ id = 4, x = 30, z = 0, sx = 10, sz = 80, top = 200, pinned = true },
		}
		local box = BossSim.new(Config, "RustjawPrime", 0, 0, 0, 1e9, 20, 0, Rng.new(4))
		box.blocks = function(x, z, r)
			local out = {}
			for _, w in walls do
				local dx = math.max(math.abs(x - w.x) - w.sx / 2, 0)
				local dz = math.max(math.abs(z - w.z) - w.sz / 2, 0)
				if dx * dx + dz * dz <= r * r then
					table.insert(out, w)
				end
			end
			return out
		end
		BossSim.step(box, 6, {})
		local far = hero(1, 0, 0, -160)
		local warned, landed = false, false
		t = 6
		for _ = 1, 150 do
			t += 0.1
			BossSim.step(box, t, { far })
			for _, ev in BossSim.drain(box) do
				if ev.k == "warn" and ev.a == "Leap" then
					warned = true
					check(ev.leap == true and ev.shape == "ring", "the leap is telegraphed where it lands")
				elseif ev.k == "strike" and ev.a == "Leap" then
					landed = true
				end
			end
		end
		check(warned and landed, "boxed in, it leaps out (telegraphed)")
		check(
			math.abs(box.x) > 35 or math.abs(box.z) > 35,
			string.format("it landed outside the box (%.0f, %.0f)", box.x, box.z)
		)
		check(BossSim.clearAt(box, box.x, box.z, box.cfg.bodyR), "on open ground")
	end)

	test("Boss counters: the stationary bosses' arenas are clear of buildings", function()
		local book = BuildingState.new(D, world.buildings)
		for _, lm in world.landmarks do
			if lm.id == B.bosses.LumenMaw.arena then
				local n = 0
				for _, b in BuildingState.boxesNear(book, lm.centre.x, lm.centre.z, 40) do
					local dx = math.max(math.abs(lm.centre.x - b.x) - b.sx / 2, 0)
					local dz = math.max(math.abs(lm.centre.z - b.z) - b.sz / 2, 0)
					if dx * dx + dz * dz < 30 * 30 then
						n += 1
					end
				end
				check(n == 0, "the Maw's pit has no building in it")
			end
		end
		for id, def in B.bosses do
			check(def.speed == 0 or def.unstick ~= nil, id .. ": a boss that walks can always get unstuck")
			check(def.speed == 0 or def.smash ~= nil, id .. ": a boss that walks smashes through buildings")
		end
	end)

	-- How often each counter reaches a hero of each kind (no dodging), over 90 s alone with the boss
	-- keep: the hero runs to stay this far from it (a speedster or teleporter kiting a walker)
	local function exposure(id: string, h: BossSim.Hero, keep: number?): { [string]: number }
		local sim = BossSim.new(Config, id, 0, 0, 0, 1e9, 20, 0, Rng.new(11))
		BossSim.step(sim, 6, {})
		local got: { [string]: number } = {}
		local t = 6
		for _ = 1, 900 do
			t += 0.1
			if keep then
				h.x, h.z = sim.x, sim.z - keep
			end
			BossSim.step(sim, t, { h })
			for _, ev in BossSim.drain(sim) do
				if ev.k == "strike" and #ev.hits > 0 then
					got[ev.a] = (got[ev.a] or 0) + 1
					got.total = (got.total or 0) + 1
				end
			end
		end
		return got
	end

	test(
		"Boss counters: every boss threatens every mobility and range; melee on the ground is never a target",
		function()
			for id, def in B.bosses do
				local react: { [string]: string } = {}
				for _, a in def.attacks do
					if a.react then
						react[a.react] = a.id
					end
				end
				check(
					react.air and react.hover and react.kite,
					id .. " has an anti-air, an anti-hover and a gap closer"
				)
				check(def.counters ~= nil, id .. " has its counter numbers")
				local c = def.counters
				-- a flier hovering high and far (flight, a swing's top, a leap's peak): the homing shots reach it
				local high = exposure(id, hero(1, 0, def.height + 40, -150))
				check((high[react.air] or 0) > 0, id .. ": homing shots reach a high, far flier")
				check(
					(high[react.kite] or 0) > 0 or react.kite == "Leap",
					id .. ": the gap closer reaches a kiter"
				)
				-- a hero hovering by its body (flight, a swing): the swat or snap
				local col = def.attacks[0]
				for _, a in def.attacks do
					if a.react == "hover" then
						col = a
					end
				end
				local hover = exposure(id, hero(1, 10, (col.lo + col.hi) / 2, -10))
				check((hover[react.hover] or 0) > 0, id .. ": the swat reaches a hero hovering by it")
				-- a speedster or teleporter kiting on the ground far away: the gap closer
				local kite = exposure(id, hero(1, 0, 0, -(c.kiteRange + 30)), c.kiteRange + 30)
				check((kite[react.kite] or 0) > 0, id .. ": the gap closer reaches a ground kiter")
				-- melee at its feet: none of the counters
				local melee = exposure(id, hero(1, 0, 0, -math.min(25, c.meleeR - 10)))
				for kind, aid in react do
					check(
						(melee[aid] or 0) == 0,
						id .. ": " .. kind .. " counter (" .. aid .. ") leaves ground melee alone"
					)
				end
				check((melee.total or 0) > 0, id .. ": ground melee still has attacks to dodge")
			end
		end
	)

	test("Boss counters: enraged when nobody comes close, calm when someone does", function()
		local sim = BossSim.new(Config, "LumenMaw", 0, 0, 0, 1e9, 20, 0, Rng.new(2))
		BossSim.step(sim, 6, {})
		local h = hero(1, 0, 60, -150)
		local on, off = false, false
		local t = 6
		for _ = 1, 400 do
			t += 0.1
			BossSim.step(sim, t, { h })
			for _, ev in BossSim.drain(sim) do
				if ev.k == "enrage" then
					on = on or ev.on
					off = off or (on and not ev.on)
				end
			end
		end
		check(on and sim.enraged, "kited for 25 s: it enrages")
		h.x, h.y, h.z = 0, 0, -20
		for _ = 1, 20 do
			t += 0.1
			BossSim.step(sim, t, { h })
			for _, ev in BossSim.drain(sim) do
				if ev.k == "enrage" and not ev.on then
					off = true
				end
			end
		end
		check(off and not sim.enraged, "a hero comes close: it calms down")
	end)

	-- The balance sim: a party of 4 at level 20, all fliers (high and far, shooting) or all melee (on the ground
	-- by its legs). They break the objectives first, then hit an ordinary body part. A typical player sees half
	-- the telegraphs in time and dodges 70 studs away. A hero at 0 HP is down for 20 s, then back at full.
	local LEVEL = 20
	-- bare: the fight without the 2026-11-19 counters (the old boss), to show what they changed
	local function bareCfg(def: any): any
		local c = table.clone(def)
		c.counters = nil
		c.attacks = {}
		for _, a in def.attacks do
			if not a.react then
				table.insert(c.attacks, a)
			end
		end
		return c
	end

	local function fight(id: string, style: string, bare: boolean?): { [string]: any }
		local def = B.bosses[id]
		local maxHp = if def.mission
			then BossMath.warframeHp(Config, LEVEL)
			else BossMath.maxHp(Config, 4, LEVEL, 0)
		local rng = Rng.new(Rng.hash(#id, #style))
		local sim = BossSim.new(Config, id, 0, 0, 0, maxHp, LEVEL, 0, Rng.new(19))
		if bare then
			sim.cfg = bareCfg(def)
		end
		BossSim.step(sim, 6, {})
		local stopAt = 6 + B.schedule.lifespan -- the War-Frame never retreats: judge it on the same 8 minutes
		local hpMax = Formulas.health(Config, LEVEL, 0, Config.Classes.default)
		local power = Config.Stats.power.base + Config.Stats.power.perLevel * LEVEL
		local dps = power * (if style == "melee" then 1.25 else 1.0)
		local heroes, state = {}, {}
		for i = 1, 4 do
			local a = (i - 1) / 4 * math.pi * 2 + 0.4
			local ax, ay, az
			if style == "melee" then
				ax, ay, az = math.cos(a) * 18, 0, math.sin(a) * 18
			else
				ax, ay, az = math.cos(a) * 150, def.height + 30, math.sin(a) * 150
			end
			heroes[i] = hero(i, ax, ay, az)
			state[i] =
				{ ax = ax, ay = ay, az = az, hp = hpMax, downUntil = 0, dodge = nil, taken = 0, downs = 0 }
		end
		local bodyKey
		for _, tg in def.targets do
			if not tg.weak and not bodyKey then
				bodyKey = tg.id
			end
		end
		local t, dt = 6, 0.1
		while t < math.min(sim.endsAt, stopAt) and sim.state == "fight" do
			t += dt
			for i, h in heroes do
				local st = state[i]
				h.alive = t >= st.downUntil
				if not h.alive then
					continue
				end
				if st.downUntil > 0 and st.hp <= 0 then
					st.hp = hpMax
				end
				-- fliers strafe slowly round it; melee keeps to its legs (the walker drags it along)
				local ax, az = st.ax, st.az
				if style == "melee" then
					ax, az = sim.x + st.ax, sim.z + st.az
				else
					local a = math.atan2(st.az, st.ax) + t * 0.05
					local r = math.sqrt(st.ax * st.ax + st.az * st.az)
					ax, az = math.cos(a) * r, math.sin(a) * r
				end
				local dx, dz = 0, 0
				if st.dodge and t < st.dodge.untilT then
					dx, dz = st.dodge.x, st.dodge.z
				end
				h.x, h.y, h.z = ax + dx, st.ay, az + dz
			end
			BossSim.step(sim, t, heroes)
			for _, ev in BossSim.drain(sim) do
				if ev.k == "warn" then
					for i, h in heroes do
						if h.alive and rng:chance(0.5) then
							-- away from the danger's centre (or sideways from a shot), clear before the hit
							local cx, cz = ev.x, ev.z
							local ux, uz = h.x - cx, h.z - cz
							if
								ev.shape == "homing"
								or ev.shape == "tether"
								or ev.shape == "circles"
								or ev.shape == "lines"
							then
								ux, uz = -(h.z - sim.z), h.x - sim.x
							end
							local l = math.sqrt(ux * ux + uz * uz)
							if l < 1e-3 then
								ux, uz, l = 1, 0, 1
							end
							state[i].dodge = { x = ux / l * 70, z = uz / l * 70, untilT = t + ev.t + 0.3 }
						end
					end
				elseif ev.k == "strike" then
					for _, hit in ev.hits do
						local st = state[hit[1]]
						st.hp -= hit[2]
						st.taken += hit[2]
						if st.hp <= 0 then
							st.downUntil = t + 20
							st.downs += 1
						end
					end
				end
			end
			-- their damage: objectives first, then the body
			for i, h in heroes do
				if h.alive then
					local key = bodyKey
					if sim.shield > 0 then
						key = sim.cfg.shield.key -- the War-Frame's phase 2 shield: hit its back
					end
					for _, ob in sim.objectives do
						if ob.alive then
							key = "obj" .. ob.idx
							break
						end
					end
					BossSim.damage(sim, key, dps * dt)
					local _ = i
				end
			end
		end
		local secs = t - 6
		local taken, downs = 0, 0
		for _, st in state do
			taken += st.taken
			downs += st.downs
		end
		return {
			won = sim.state == "dead",
			secs = secs,
			perMin = taken / 4 / hpMax / (secs / 60), -- share of a hero's HP taken each minute
			downs = downs,
		}
	end

	test("Boss counters: fliers and melee both take real damage and both can win, on every boss", function()
		for id in B.bosses do
			local fly = fight(id, "flier")
			local melee = fight(id, "melee")
			local oldFly = fight(id, "flier", true)
			local oldMelee = fight(id, "melee", true)
			local function row(r: any): string
				return string.format(
					"%s in %3.0f s, %.2f HP/min, %d downs",
					if r.won then "won" else "LOST",
					r.secs,
					r.perMin,
					r.downs
				)
			end
			print(string.format("  [Boss balance] %-16s flier: %s | melee: %s", id, row(fly), row(melee)))
			print(
				string.format(
					"  [Boss balance] %-16s before: flier %.2f HP/min, melee %.2f HP/min",
					"",
					oldFly.perMin,
					oldMelee.perMin
				)
			)
			check(fly.won, id .. ": a party of ranged fliers can win")
			check(melee.won, id .. ": a party of melee heroes can win")
			check(
				fly.perMin >= 0.25,
				string.format("%s: fliers take real damage (%.2f HP a minute)", id, fly.perMin)
			)
			check(
				melee.perMin >= 0.25,
				string.format("%s: melee takes real damage (%.2f HP a minute)", id, melee.perMin)
			)
			check(
				fly.perMin >= oldFly.perMin * 1.5 + 0.1,
				string.format(
					"%s: flying and shooting is no longer safe (%.2f, was %.2f)",
					id,
					fly.perMin,
					oldFly.perMin
				)
			)
			-- melee is not punished: the counters add little to what ground melee took before
			check(
				melee.perMin <= oldMelee.perMin * 1.15 + 0.05,
				string.format("%s: melee not punished (%.2f, was %.2f)", id, melee.perMin, oldMelee.perMin)
			)
		end
	end)
end
