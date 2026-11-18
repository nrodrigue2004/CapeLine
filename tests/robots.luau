-- WP6: robot combat depth (gap check G9 and G10). The Warden's and the War-Frame's timed blocks (the War-Frame's
-- telegraph), the Sneak Bot's lunge wind-up (timing, the lane, an interrupt cuts it, a step out of the lane
-- dodges it, a breaker against a block), downed robots' wrecks as medium throwables (who leaves one, the cap,
-- the window) and the wiring. EnemySim stays deterministic.
-- Called from tests/run.luau: require("./robots")({ test, check, near, Config })

return function(T: any)
	local test, check, near, Config = T.test, T.check, T.near, T.Config
	local fs = require("@lune/fs")
	local GuardMath = require("../src/shared/GuardMath")
	local EnemySim = require("../src/shared/EnemySim")
	local ThrowMath = require("../src/shared/ThrowMath")
	local Status = require("../src/shared/Status")
	local G = Config.Guard
	local TW = Config.Throw

	local function source(path: string): string
		return fs.readFile(path)
	end

	---------------------------------------------------------------------------
	-- Robot blocks (G9)
	---------------------------------------------------------------------------

	test("WP6: the Warden and the War-Frame block on a timer, and breakers shatter both", function()
		local wd = G.robotBlocks.NullSentinel
		local wf = G.robotBlocks.NullWarFrame
		check(
			wd ~= nil and Config.Enemies.NullSentinel.name == "Warden",
			"the Warden (kind NullSentinel) braces"
		)
		check(
			wf ~= nil and Config.Boss.bosses.NullWarFrame ~= nil,
			"the War-Frame (boss NullWarFrame) blocks"
		)
		check(
			wd.front > Config.Enemies.NullSentinel.guard.front,
			"the brace covers more than the front guard"
		)
		check(wd.warn == nil and (wf.warn or 0) > 0, "only the War-Frame telegraphs its block")
		check(wf.size ~= nil and wf.size > 20, "a big shine for a big machine")
		check(G.robotBlocks.BruteBot.warn == nil, "the Brute Bot is as it was")
		-- the Warden: like the Brute Bot (no telegraph)
		local rs = GuardMath.robotNew(wd, 0)
		check(GuardMath.robotStep(wd, rs, wd.first - 0.1, true, false) == nil, "waits `first`")
		check(GuardMath.robotStep(wd, rs, wd.first, true, false) == "start", "then braces")
		local out, mult = GuardMath.robotHit(G, wd, rs, { coeff = 1, front = true }, wd.first + 0.2)
		check(out == "blocked", "a normal hit is blocked")
		near(mult, 1 - wd.cut, 1e-9, "for the brace's cut")
		check(
			GuardMath.robotHit(G, wd, rs, { coeff = 1, front = false }, wd.first + 0.3) == "hit",
			"from behind"
		)
		-- its front guard shattered by a breaker ends the brace too, for brokenFor
		check(GuardMath.robotBreak(wd, rs, wd.first + 0.4), "a breaker on the guard ends a raised brace")
		check(not GuardMath.robotBlocking(rs, wd.first + 0.5), "no brace")
		check(
			GuardMath.robotStep(wd, rs, wd.first + 0.4 + wd.brokenFor - 0.1, true, false) == nil,
			"none while broken"
		)
		check(
			GuardMath.robotStep(wd, rs, wd.first + 0.4 + wd.brokenFor, true, false) == "start",
			"braces again later"
		)
		local idle = GuardMath.robotNew(wd, 0)
		check(not GuardMath.robotBreak(wd, idle, 1), "a break with no brace up reports nothing to take down")
		check(idle.nextAt == 1 + wd.brokenFor, "but the brace still waits brokenFor")
	end)

	test("WP6: the War-Frame's block windows: telegraph, block, shatter, called off when busy", function()
		local wf = G.robotBlocks.NullWarFrame
		local rs = GuardMath.robotNew(wf, 100)
		local t = 100 + wf.first
		check(
			GuardMath.robotStep(wf, rs, t - 0.05, true, false) == nil,
			"waits `first` after the fight starts"
		)
		check(GuardMath.robotStep(wf, rs, t, true, false) == "warn", "then the telegraph")
		check(
			GuardMath.robotWarning(rs, t + 0.1) and not GuardMath.robotBlocking(rs, t + 0.1),
			"warning, not up"
		)
		check(
			GuardMath.robotHit(G, wf, rs, { coeff = 1, front = true }, t + 0.1) == "hit",
			"the telegraph is the opening: hits land in full"
		)
		check(
			GuardMath.robotStep(wf, rs, t + wf.warn - 0.05, true, false) == nil,
			"the telegraph runs `warn`"
		)
		local up = t + wf.warn
		check(GuardMath.robotStep(wf, rs, up, true, false) == "start", "then the block goes up")
		check(GuardMath.robotBlocking(rs, up + wf.time - 0.05), "held `time`")
		local out, mult = GuardMath.robotHit(G, wf, rs, { coeff = 2, front = true }, up + 0.5)
		check(out == "blocked", "a big non-breaker hit is still blocked")
		near(mult, 1 - wf.cut, 1e-9, "for the block's cut")
		check(
			GuardMath.robotHit(G, wf, rs, { coeff = 1, front = false }, up + 0.6) == "hit",
			"the back is open"
		)
		check(
			GuardMath.robotHit(G, wf, rs, { charged = 1, front = true }, up + 0.7) == "shatter",
			"a full charge shatters it"
		)
		check(not GuardMath.robotBlocking(rs, up + 0.8), "the block is gone")
		check(
			GuardMath.robotStep(wf, rs, up + 0.7 + wf.brokenFor - 0.1, true, false) == nil,
			"none while broken"
		)
		check(GuardMath.robotStep(wf, rs, up + 0.7 + wf.brokenFor, true, false) == "warn", "telegraphs again")
		check(
			GuardMath.robotStep(wf, rs, up + 0.8 + wf.brokenFor, true, true) == "stop",
			"busy (its phase shield): off"
		)
		check(not GuardMath.robotWarning(rs, up + 0.9 + wf.brokenFor), "no telegraph left")
		-- a full cycle with no breaker: `every` counts from the block going up
		local rs2 = GuardMath.robotNew(wf, 0)
		GuardMath.robotStep(wf, rs2, wf.first, true, false)
		GuardMath.robotStep(wf, rs2, wf.first + wf.warn, true, false)
		check(
			GuardMath.robotStep(wf, rs2, wf.first + wf.warn + wf.time, true, false) == "stop",
			"it drops after `time`"
		)
		check(
			GuardMath.robotStep(wf, rs2, wf.first + wf.warn + wf.every - 0.05, true, false) == nil,
			"and waits `every` from going up"
		)
		check(
			GuardMath.robotStep(wf, rs2, wf.first + wf.warn + wf.every, true, false) == "warn",
			"then again"
		)
		check(
			GuardMath.robotStep(wf, rs2, wf.first + wf.warn + wf.every + 0.1, false, false) == "stop",
			"fight over"
		)
	end)

	test(
		"WP6: a braced Warden is hit without its guard's side check (no double cut, no flank break)",
		function()
			local sim = EnemySim.new(Config, {})
			local e = EnemySim.spawn(sim, "NullSentinel", 0, 0, 0, 10) :: any
			e.yaw = 0 -- facing -Z
			local hp = e.health
			-- from the side (+X): with its position the guard breaks; CombatService sends a braced hit with none
			local _, _, dealt, flag = EnemySim.damage(sim, e.id, 100, 1, nil, nil)
			check(flag == EnemySim.HIT and e.guardBrokenUntil == 0, "no position: no guard break")
			near(dealt, 100 * (1 - (Config.Enemies.NullSentinel.mitigation or 0)), 1e-6, "and no guard cut")
			check(e.health < hp, "it took the (already braced-down) hit")
			local _, _, _, flag2 = EnemySim.damage(sim, e.id, 100, 1, 10, 0)
			check(flag2 == EnemySim.BROKE, "an unbraced flank hit still breaks the guard")
			local combat = source("src/server/Services/CombatService.luau")
			check(
				string.find(
					combat,
					"EnemyService.damage(cand.id, dmg, hero.id, if gblocked then nil else from)",
					1,
					true
				) ~= nil,
				"CombatService drops the position for a hit a timed block took"
			)
			local block = source("src/server/Services/BlockService.luau")
			check(
				string.find(block, "GuardMath.robotBreak(rb, rs, now)", 1, true) ~= nil,
				"a guard break ends the brace"
			)
			check(
				string.find(block, "now < (e.guardBrokenUntil or 0)", 1, true) ~= nil,
				"a broken guard never braces"
			)
			check(
				string.find(block, "function BlockService.watchBoss", 1, true) ~= nil,
				"bosses can be watched"
			)
			check(
				string.find(block, "sim.nextAttack = math.max", 1, true) ~= nil,
				"a shattered War-Frame reels"
			)
			local mission = source("src/server/Services/MissionService.luau")
			check(
				string.find(mission, "BlockService.watchBoss(sim, track.wf.targets)", 1, true) ~= nil,
				"the War-Frame mission step registers its block"
			)
			local fx = source("src/client/Fx/GuardFx.luau")
			check(string.find(fx, '"rwarn"', 1, true) ~= nil, "the telegraph is drawn")
			check(
				string.find(fx, "s.fixed or EnemyRenderer.position(id)", 1, true) ~= nil,
				"a boss shine stays put"
			)
			check(Config.Audio.sounds.braceWarn ~= nil, "with its own hum")
		end
	)

	---------------------------------------------------------------------------
	-- The Sneak Bot's lunge (G9)
	---------------------------------------------------------------------------

	local L = Config.Enemies.SneakBot.lunge
	local DT = 0.05

	-- A Sneak Bot 14 studs in front of a hero that faces it, cloak and lunge timers set so the lunge comes now
	local function lungeSim(seed: number?): (any, any, any)
		local s = seed or 7
		local sim = EnemySim.new(Config, {
			random = function()
				s = (s * 16807) % 2147483647
				return s / 2147483647
			end,
		})
		local e = EnemySim.spawn(sim, "SneakBot", 0, 0, 0, 10) :: any
		e.nextCloak = math.huge
		e.nextSpecial = 0
		local hero = { id = 1, x = 0, y = 3, z = -14, alive = true, lx = 0, lz = 1 }
		return sim, e, hero
	end

	local function steps(sim: any, heroes: { any }, from: number, to: number, each: ((number, any) -> ())?)
		local t = from
		while t < to - 1e-9 do
			t += DT
			EnemySim.step(sim, t, heroes)
			for _, ev in EnemySim.drainEvents(sim) do
				if each then
					each(t, ev)
				end
			end
		end
		return t
	end

	test("WP6: the Sneak Bot's lunge: wind-up with a lane, then a dash and one breaker strike", function()
		check(L ~= nil and L.windup >= 0.5 and L.windup <= 0.8, "a readable wind-up (0.5 to 0.8 s)")
		check(L.min > Config.Enemies.SneakBot.attackRange and L.range > L.min, "from a little way off")
		local sim, e, hero = lungeSim()
		local lungeAt, lane, hitAt, hit = nil, nil, nil, nil
		local stillX, stillZ = nil, nil
		local movedInWindup, cloakedInWindup, flagged, lungeBit = false, false, false, false
		steps(sim, { hero }, 0, 3, function(t, ev)
			if ev.k == "lunge" and not lungeAt then
				lungeAt, lane = t, ev
				stillX, stillZ = e.x, e.z
			elseif ev.k == "hit" and ev.hero == 1 and not hitAt then
				hitAt, hit = t, ev
			end
		end)
		check(lungeAt ~= nil, "it winds up a lunge")
		check(lane.t == L.windup and lane.w == L.width, "the lane event carries the wind-up and the width")
		local dx, dz = lane.tx - lane.x, lane.tz - lane.z
		near(math.sqrt(dx * dx + dz * dz), 14 + L.over, 0.6, "the lane runs a little past the hero")
		check(lane.tz < hero.z, "toward and past the hero")
		-- replay to watch the wind-up itself
		sim, e, hero = lungeSim()
		local t = 0
		local started = nil
		while t < 3 do
			t += DT
			EnemySim.step(sim, t, { hero })
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "lunge" then
					started = t
					stillX, stillZ = e.x, e.z
				end
			end
			if started and t < started + L.windup - 0.06 then
				movedInWindup = movedInWindup
					or math.abs(e.x - stillX) > 1e-6
					or math.abs(e.z - stillZ) > 1e-6
				cloakedInWindup = cloakedInWindup or e.cloakUntil > t
				flagged = flagged or bit32.band(e.flags, Status.BITS.windup) ~= 0
			end
			lungeBit = lungeBit or bit32.band(e.extra, EnemySim.EXTRA.lunge) ~= 0
			if started and t > started + L.windup + L.time + 0.3 then
				break
			end
		end
		check(not movedInWindup, "it holds still in the wind-up")
		check(not cloakedInWindup, "and shows itself")
		check(flagged, "the windup flag is on (red eyes, the robot tell)")
		check(lungeBit, "then the lunge bit (the dash pose)")
		check(hitAt ~= nil and hit.breaker == true, "the strike is a breaker against a block")
		check(
			hitAt >= lungeAt + L.windup - 1e-6 and hitAt <= lungeAt + L.windup + L.time + 0.2,
			string.format("it lands after the wind-up (%.2f s)", hitAt - lungeAt)
		)
		local s = Config.Enemies.scale
		near(hit.damage, (s.dmgBase + s.dmgPerLevel * 10) * L.coeff, 1e-6, "at the lunge's coefficient")
		check(e.nextSpecial >= lungeAt + L.every - 1e-6, "once every `every` seconds")
	end)

	test("WP6: an interrupt in the wind-up cuts the lunge off; stepping out of the lane dodges it", function()
		local sim, e, hero = lungeSim()
		local t, cut = 0, false
		local breakerHit, lunged = false, false
		while t < 2.5 do
			t += DT
			EnemySim.step(sim, t, { hero })
			for _, ev in EnemySim.drainEvents(sim) do
				if ev.k == "lunge" and not cut then
					cut = true
					EnemySim.step(sim, t + 0.01, { hero }) -- (a tick inside the wind-up)
					-- BlockService's interrupt: a light hit on a robot winding up stuns it for robotStun
					check(e.windupUntil > t, "winding up")
					EnemySim.applyStatus(sim, e.id, "stun", G.interrupt.robotStun)
					check(e.windupUntil == 0, "the stun resets the wind-up")
				elseif ev.k == "hit" and ev.breaker then
					breakerHit = true
				end
			end
			lunged = lunged or bit32.band(e.extra, EnemySim.EXTRA.lunge) ~= 0
		end
		check(cut, "it started a wind-up")
		check(not lunged and not breakerHit, "no lunge after the interrupt")
		check(e.move == nil, "the lunge is dropped")
		-- the lane: the hero steps aside during the wind-up
		local sim2, e2, hero2 = lungeSim()
		local t2, seen, dodgedHit = 0, false, false
		while t2 < 2 do
			t2 += DT
			EnemySim.step(sim2, t2, { hero2 })
			for _, ev in EnemySim.drainEvents(sim2) do
				if ev.k == "lunge" then
					seen = true
					hero2.x = hero2.x + 9 -- out of the lane
				elseif ev.k == "hit" and ev.breaker then
					dodgedHit = true
				end
			end
			if seen and bit32.band(e2.extra, EnemySim.EXTRA.lunge) ~= 0 then
				hero2.x = 9 -- (stays out)
			end
		end
		check(seen and not dodgedHit, "a hero out of the lane is not struck")
		-- story robots that never fight back never lunge
		local sim3, e3, hero3 = lungeSim()
		e3.dmgMult = 0
		local any = false
		steps(sim3, { hero3 }, 0, 2, function(_, ev)
			any = any or ev.k == "lunge"
		end)
		check(not any, "a harmless story robot never lunges")
	end)

	test("WP6: EnemySim stays deterministic with the lunge (the same seed, the same fight)", function()
		local function fight(seed: number): string
			local sim, _, hero = lungeSim(seed)
			EnemySim.spawn(sim, "SneakBot", 30, 0, 10, 8)
			EnemySim.spawn(sim, "NullSentinel", -20, 0, 5, 8)
			EnemySim.spawn(sim, "BruteBot", 10, 0, -30, 8)
			local log = {}
			local t = 0
			while t < 12 do
				t += DT
				hero.x = math.sin(t) * 6
				hero.lx, hero.lz = math.sin(t * 0.7), math.cos(t * 0.7)
				EnemySim.step(sim, t, { hero })
				for _, ev in EnemySim.drainEvents(sim) do
					table.insert(
						log,
						string.format("%.2f %s %s %.3f", t, ev.k, tostring(ev.e), ev.damage or 0)
					)
				end
			end
			for _, e in sim.enemies do
				table.insert(log, string.format("%d %.4f %.4f %d %d", e.id, e.x, e.z, e.flags, e.extra))
			end
			return table.concat(log, "\n")
		end
		local a, b = fight(11), fight(11)
		check(#a > 100 and a == b, "the same seed gives the same events and positions")
		check(string.find(a, " lunge ", 1, true) ~= nil, "and the lunge is in it")
	end)

	test("WP6: the lunge's wiring: a CombatEvents id, the lane, the pose, the hero's block hook", function()
		local enemy = source("src/server/Services/EnemyService.luau")
		check(string.find(enemy, "EnemyService.LUNGE = 17", 1, true) ~= nil, "CombatEvents id 17")
		check(string.find(enemy, "breaker = ev.breaker", 1, true) ~= nil, "the breaker mark reaches the hero")
		local client = source("src/client/Controllers/CombatClient.luau")
		check(string.find(client, "local LUNGE = 17", 1, true) ~= nil, "the client knows id 17")
		check(string.find(client, "CombatFx.lane(", 1, true) ~= nil, "and draws the lane")
		check(string.find(client, 'Juice.fire("lungeWind"', 1, true) ~= nil, "with its whine")
		check(Config.Audio.sounds.lungeWind ~= nil, "a sound for it")
		local fx = source("src/client/Fx/CombatFx.luau")
		check(string.find(fx, "function CombatFx.lane(", 1, true) ~= nil, "CombatFx.lane")
		local rend = source("src/client/Controllers/EnemyRenderer.luau")
		check(string.find(rend, "local coiled = sneak and windup", 1, true) ~= nil, "the coiled wind-up pose")
		local block = source("src/server/Services/BlockService.luau")
		check(string.find(block, "source.breaker == true", 1, true) ~= nil, "a lunge breaks a hero's block")
		-- no new robot types: the 5-bit typeId stays full and unchanged
		local ids, n = {}, 0
		for _, row in Config.Enemies do
			if type(row) == "table" and row.typeId then
				check(not ids[row.typeId] and row.typeId >= 1 and row.typeId <= 31, "typeId " .. row.typeId)
				ids[row.typeId] = true
				n += 1
			end
		end
		check(n == 31, string.format("31 robot types, as before (%d)", n))
	end)

	---------------------------------------------------------------------------
	-- Downed robots (G10)
	---------------------------------------------------------------------------

	test("WP6: downed robots leave medium wrecks; fakes, creatures, sea and pack robots do not", function()
		local E = Config.Enemies
		check(ThrowMath.weight(TW, "wreck") == "medium", "a wreck is medium (the spec's row)")
		for _, cls in Config.Classes.order do
			check(
				ThrowMath.canLift(TW, "wreck", cls, false),
				cls .. " lifts a wreck (the existing carry rules)"
			)
		end
		local hit = ThrowMath.hit(TW, "medium")
		check(hit.coeff == 1.6 and not hit.breaker, "thrown: 1.6, knock and a small blast, not a breaker")
		for _, k in
			{ "SparkDrone", "BurglarBot", "SneakBot", "BruteBot", "Turret", "NullSentinel", "Captain" }
		do
			check(ThrowMath.canWreck(E[k]), k .. " leaves a wreck")
		end
		for _, k in { "Swarmer", "Radiant", "Bulwark", "EvilTwin", "Bramblebeast", "Diver", "WindupToy" } do
			if E[k] then
				check(not ThrowMath.canWreck(E[k]), k .. " leaves none")
			end
		end
		check(not ThrowMath.canWreck(nil), "an unknown kind leaves none")
		local bx, by, bz = ThrowMath.wreckSize(TW, E.BruteBot)
		local sx, sy, sz = ThrowMath.wreckSize(TW, E.SneakBot)
		check(bx > sx and by > sy and bz > sz, "a Brute's heap is bigger than a Sneak's")
		check(sy < E.SneakBot.body.height * 0.5, "a heap, not a standing robot")
	end)

	test("WP6: the wreck cap and window", function()
		local W = TW.wreck
		check(W.max >= 3 and W.max <= 10, "a few at once (perf)")
		check(W.life >= 5 and W.life <= 20 and W.after < W.life, "a short window, shorter once handled")
		check(W.blink < W.life, "it flickers before it goes")
		local ok, evict = ThrowMath.wreckRoom({ { id = 1, born = 0 } }, 3)
		check(ok and evict == nil, "under the cap: room")
		local list = {
			{ id = 5, born = 3 },
			{ id = 2, born = 1, busy = true },
			{ id = 9, born = 2 },
		}
		ok, evict = ThrowMath.wreckRoom(list, 3)
		check(ok and evict == 9, "at the cap: the oldest one nobody holds goes")
		ok, evict =
			ThrowMath.wreckRoom({ { id = 1, born = 0, busy = true }, { id = 2, born = 1, busy = true } }, 2)
		check(not ok and evict == nil, "all held or flying: no new wreck")
		ok, evict = ThrowMath.wreckRoom({ { id = 4, born = 1 }, { id = 3, born = 1 } }, 2)
		check(ok and evict == 3, "a tie goes to the lower id (the same on every run)")
		check(ThrowMath.wreckEnds(TW, 10, false) == 10 + W.life, "it lies `life` seconds")
		check(ThrowMath.wreckEnds(TW, 10, true) == 10 + W.after, "`after` once thrown or set down")
		check(not ThrowMath.wreckGone(20, 19.9) and ThrowMath.wreckGone(20, 20), "gone at its end")
		check(not ThrowMath.wreckGone(20, 30, true), "never while held or flying")
	end)

	test("WP6: wreck wiring: Killed hook, ids, cap, the pop and sparks in the debris budget", function()
		local throw = source("src/server/Services/ThrowService.luau")
		check(string.find(throw, "EnemyService.Killed:Connect", 1, true) ~= nil, "a defeat leaves the wreck")
		check(string.find(throw, "ThrowMath.wreckRoom(list, W.max)", 1, true) ~= nil, "under the cap")
		check(string.find(throw, "ThrowMath.canWreck(cfg)", 1, true) ~= nil, "only kinds that leave one")
		check(string.find(throw, 'SetAttribute("WreckGone", true)', 1, true) ~= nil, "every screen pops it")
		check(string.find(throw, "if it.wreck then", 1, true) ~= nil, "a wreck never goes home like a prop")
		check(string.find(throw, "PLACEHOLDER ART", 1, true) ~= nil, "placeholder art is labelled")
		local enemy = source("src/server/Services/EnemyService.luau")
		check(
			string.find(enemy, "ThrowService", 1, true) == nil,
			"EnemyService's Killed handler is untouched"
		)
		local fx = source("src/client/Fx/ThrowFx.luau")
		check(string.find(fx, "DebrisBudget.lease", 1, true) ~= nil, "sparks and chips in the debris budget")
		check(string.find(fx, '"WreckGone"', 1, true) ~= nil, "the pop")
		check(string.find(fx, "WreckEnds", 1, true) ~= nil, "the flicker near the end")
		for _, id in { "wreckSpark", "wreckPop" } do
			check(Config.Audio.sounds[id] ~= nil and string.find(fx, '"' .. id .. '"', 1, true) ~= nil, id)
		end
		-- ids: props 1.., vehicles 1000.., wrecks 3001..3999
		local spots = ThrowMath.place(TW, Config)
		check(#spots < 1000, "props stay under the vehicles' ids")
		check(string.find(throw, "WRECK_BASE = 3000", 1, true) ~= nil, "wrecks take their own ids")
	end)
end
