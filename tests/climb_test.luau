-- move-2 (nate's playtest 2026-11-19 20:42Z and his card pick 20:45Z): the smash rule for Leaping and Super-speed,
-- the Hulk wall climb, the Acrobat's wall crawl and dodge flips, swing anywhere (the wide fan and the sky line) and
-- everyone's sprint. Shared.ClimbMath and SwingMath in Lune, bots climbing, crawling, flipping, sprinting and sky
-- swinging through the server's speed check (MoveCheck at 10 Hz: no pull-backs), and source and place checks on
-- the runtime path (MoveController, MoveGuard, ImpactService, HeroService, HeroAnim, the built place).
-- Called from tests/run.luau; ONLY="Climb" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local ClimbMath = require("../src/shared/ClimbMath")
	local ClimbAnim = require("../src/shared/ClimbAnim")
	local MoveMath = require("../src/shared/MoveMath")
	local MoveCheck = require("../src/shared/MoveCheck")
	local MoveRanks = require("../src/shared/MoveRanks")
	local SwingMath = require("../src/shared/SwingMath")
	local HeroAnim = require("../src/shared/HeroAnim")
	local Remotes = require("../src/shared/Remotes")
	local M = Config.Move
	local S = Config.Safety
	local len3 = ClimbMath.len3

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	-- a path sampled at 10 Hz through MoveCheck for a hero with one pick: returns the pull-backs
	local function guard(cfg: any, pick: string, path: { { number } }, boosting: boolean?): number
		local cap = MoveMath.guardCap(cfg, { [pick] = true }, boosting == true, {})
		local st = MoveCheck.new(path[1][1], path[1][2], path[1][3], path[1][4])
		local fails = 0
		for i = 2, #path do
			local s = path[i]
			local ok, _, wait = MoveCheck.sample(st, s[1], s[2], s[3], s[4], cap, cfg, S)
			if not ok and not wait then
				fails += 1
			end
		end
		return fails
	end

	-- the Hulk climb up a `height` wall with its face at z = 0 (normal +z): grab, bound, grab... vault. Leap held
	-- all the way (a bound every grip). Returns the 10 Hz path, the time to the top and the grabs.
	local function climbSim(cfg: any, height: number): ({ { number } }, number, number)
		local C = cfg.mobility.leap.climb
		local x, y, z = 0, 3, 1.5
		local vy = 0
		local mode, gripAt, t, grabs = "climb", 0, 0, 1
		local path = { { x, y, z, 0 } }
		local dt, nextSample = 1 / 60, 0.1
		local topAt = math.huge
		while t < 20 do
			t += dt
			local vx, vz = 0, 0
			if mode == "climb" then
				vz = -C.press
				if t - gripAt >= C.grip then
					vy = ClimbMath.boundUp(cfg)
					mode = "bound"
				else
					vy = 0
				end
			elseif mode == "bound" then
				local top
				vx, vy, vz, top = ClimbMath.boundStep(cfg, vy, 0, 1, 0, dt)
				if y > height then
					vx, vy, vz = ClimbMath.vault(cfg, 0, 1)
					mode = "air"
					topAt = t
				elseif top then
					mode, gripAt, grabs = "climb", t, grabs + 1
					vy = 0
				end
			else
				vy = math.max(-M.fall.terminal, vy - cfg.airGravity * dt)
				if y <= height + 3 and z < -2 then
					break -- on the roof
				end
			end
			x, y, z = x + vx * dt, y + vy * dt, math.max(if mode == "air" then -40 else 0.5, z + vz * dt)
			if t >= nextSample then
				nextSample += 0.1
				table.insert(path, { x, y, z, t })
			end
		end
		return path, topAt, grabs
	end

	test(
		"Climb: the smash rule: a charged leap or Boost goes through, a tapped leap or no Boost climbs",
		function()
			local full = { MoveMath.superLeapLaunch(M, 1, 0, 1, M.caps.run, 0) }
			local tap = { MoveMath.superLeapLaunch(M, 1, 0, 0) }
			local still = { MoveMath.superLeapLaunch(M, 0, 0, 1) }
			-- a wall facing back at the leap (normal -x)
			check(
				ClimbMath.leapSmash(M, full[1], full[3], -1, 0),
				"a full charged running leap smashes through"
			)
			check(not ClimbMath.leapSmash(M, tap[1], tap[3], -1, 0), "a tapped leap grabs the wall")
			check(
				not ClimbMath.leapSmash(M, still[1], still[3], -1, 0),
				"a straight-up jump beside a wall grabs it"
			)
			check(
				not ClimbMath.leapSmash(M, full[1], full[3], 0, 1),
				"a wall along the leap is never smashed"
			)
			check(
				full[1] >= M.mobility.leap.smash.into and tap[1] < M.mobility.leap.smash.into,
				"into sits between"
			)
			check(
				full[1] >= Config.Combat.impact.ram.minSpeed,
				"the leap's smash is fast enough for the ram itself"
			)
			check(
				ClimbMath.speedSmash(M, true, M.mobility.speed.sprint),
				"Super-speed at top speed with Boost smashes"
			)
			check(not ClimbMath.speedSmash(M, false, M.mobility.speed.sprint), "without Boost it wall runs")
			check(
				not ClimbMath.speedSmash(M, true, M.run.speed),
				"Boost from a standstill: not fast enough yet"
			)
			check(
				M.mobility.speed.smash >= Config.Combat.impact.ram.minSpeed,
				"the speed smash meets the ram minimum"
			)
			-- the wall run needs no Boost now (the stick into the wall keeps it going)
			check(
				MoveMath.wallRunKeep(M, "speed", 1, 0, -1, 0, 1, false, 50),
				"stick along or into the wall: runs on"
			)
			check(not MoveMath.wallRunKeep(M, "speed", 1, 0, 1, 0, 1, false, 50), "stick pulled away: off")
		end
	)

	test(
		"Climb: the Hulk climb bounds up a 160-stud wall grab by grab and vaults, never pulled back",
		function()
			for _, rank in { 0, 5 } do
				local cfg = MoveRanks.config(M, "leap", rank)
				local path, topAt, grabs = climbSim(cfg, 160)
				check(topAt < math.huge, "rank " .. rank .. ": reached the top")
				local per = cfg.mobility.leap.climb.bound
				check(
					grabs >= math.floor(157 / per) - 1,
					string.format("rank %d: %d grabs on the way up", rank, grabs)
				)
				check(guard(cfg, "leap", path) == 0, "rank " .. rank .. ": MoveCheck never pulls it back")
				local rate = 157 / topAt
				check(rate > 25, string.format("rank %d: climbs %.1f studs/s", rank, rate))
				-- the Acrobat's crawl climbs faster at the same rank (the fastest climb)
				local acro = MoveRanks.config(M, "acrobat", rank)
				check(
					acro.mobility.acrobat.climb > rate,
					string.format(
						"rank %d: Acrobat crawl %d beats the Hulk's %.1f",
						rank,
						acro.mobility.acrobat.climb,
						rate
					)
				)
			end
			local vx, vy, vz = ClimbMath.vault(M, 0, 1)
			check(vz < 0 and vy > 0 and vx == 0, "the vault goes into the wall's top and up (onto the roof)")
			local kx, ky, kz = ClimbMath.kick(M, 0, 1, 1, 0.2)
			check(kz > 0 and ky > 0 and kx > 0, "the kick goes out from the wall, up and toward the stick")
			check(
				ClimbMath.pullsAway(0, 1, 0, 1) and not ClimbMath.pullsAway(1, 0, 0, 1),
				"pull away vs along"
			)
			local cap = MoveMath.speedCap(M, { leap = true }, false)
			check(
				len3(kx, ky, kz) <= cap and ClimbMath.boundUp(M) <= cap,
				"kick and bound inside the Leaping cap"
			)
		end
	)

	test("Climb: the Acrobat's crawl: up on a wall, the camera's way on a ceiling, inside its cap", function()
		-- a wall facing +z, the camera behind looking -z: forward is up, right is +x
		local fx, fy, fz, rx, ry, rz = ClimbMath.crawlBasis(0, 0, 1, 0, 0, -1, 1, 0, 0)
		check(
			math.abs(fy - 1) < 1e-6 and math.abs(rx - 1) < 1e-6,
			"on a wall: stick up is up the face, right is right"
		)
		check(math.abs(fx) + math.abs(fz) + math.abs(ry) + math.abs(rz) < 1e-6, "both lie on the face")
		-- a ceiling (normal down), the camera looking -z: forward is -z on it, right +x
		fx, fy, fz, rx, ry, rz = ClimbMath.crawlBasis(0, -1, 0, 0, -0.3, -1, 1, 0, 0)
		check(fz < -0.99 and rx > 0.99, "on a ceiling: forward is the camera's way, right its right")
		check(ClimbMath.crawlKind(-0.9) == "ceiling" and ClimbMath.crawlKind(0.9) == "floor", "face kinds")
		check(ClimbMath.crawlKind(0.1) == "wall", "a wall")
		-- crawl up a 120 wall at the scurry, 10 Hz through MoveCheck
		for _, rank in { 0, 5 } do
			local cfg = MoveRanks.config(M, "acrobat", rank)
			local a = cfg.mobility.acrobat
			local y, t = 3, 0
			local path = { { 0, y, 1.6, 0 } }
			local bf, by, bz, brx, bry, brz = ClimbMath.crawlBasis(0, 0, 1, 0, 0, -1, 1, 0, 0)
			while y < 120 do
				local vx, vy = ClimbMath.crawlVel(cfg, 0, 0, 1, bf, by, bz, brx, bry, brz, 0.3, -1, true, 1.6)
				t += 0.1
				y += vy * 0.1
				table.insert(path, { vx * t, y, 1.6, t })
			end
			check(guard(cfg, "acrobat", path) == 0, "rank " .. rank .. ": the scurry is never pulled back")
			local vx, vy, vz = ClimbMath.crawlVel(cfg, 0, 0, 1, bf, by, bz, brx, bry, brz, 0, -1, false, 1.6)
			check(math.abs(vy - a.climb) < 1e-6 and vx == 0 and vz == 0, "crawl speed is `climb` at the gap")
			local _, _, pz = ClimbMath.crawlVel(cfg, 0, 0, 1, bf, by, bz, brx, bry, brz, 0, 0, false, 2.6)
			check(pz < 0, "too far off the face: pulled back onto it")
			local jx, jy, jz = ClimbMath.crawlJump(cfg, 0, 0, 1, 0, 1)
			check(
				jz > 0 and jy > 0 and len3(jx, jy, jz) <= a.cap + 1e-6,
				"the jump off goes out and up, in the cap"
			)
		end
	end)

	test("Climb: flips dodge for their i-frames on the server's clock, inside the Acrobat's cap", function()
		local f = M.mobility.acrobat.flip
		local ok, untilT = ClimbMath.flipOk(M, -math.huge, 10)
		check(ok and math.abs(untilT - (10 + f.iframes)) < 1e-9, "a flip opens its dodge window")
		check(not ClimbMath.flipOk(M, 10, 10 + f.cooldown * 0.5), "not again inside the cooldown")
		check(ClimbMath.flipOk(M, 10, 10 + f.cooldown * 0.9, 0.85), "the server's slack lets a laggy one in")
		local vx, vy, vz = ClimbMath.flipVel(M, 0, 0, 0, 1)
		check(vz > 0 and vy > 0, "a still stick flips back")
		vx, vy, vz = ClimbMath.flipVel(M, 1, 0, 0, 1)
		check(vx > 0 and vz == 0, "else along the stick")
		-- a flip every cooldown for 6 s, 10 Hz through MoveCheck
		local path, x, t, y = { { 0, 3, 0, 0 } }, 0, 0, 3
		while t < 6 do
			t += 0.1
			local phase = (t % f.cooldown)
			x += (if phase < f.time then f.speed else M.mobility.acrobat.run) * 0.1
			table.insert(path, { x, y, 0, t })
		end
		check(guard(M, "acrobat", path) == 0, "back-to-back flips are never pulled back")
		check(
			f.iframes <= f.time + 0.1 and f.iframes < f.cooldown,
			"the window is short and can't be chained"
		)
		local r3 = MoveRanks.config(M, "acrobat", 3).mobility.acrobat.flip
		check(r3.iframes > f.iframes and r3.cooldown < f.cooldown, "Evasion (rank 3) flips longer and sooner")
		-- the server's side: HeroService.damage misses while dodgeUntil lasts, MoveGuard takes MoveFlip
		local hs = fs.readFile("src/server/Services/HeroService.luau")
		check(has(hs, "now < hero.dodgeUntil"), "HeroService.damage checks the dodge window")
		local mg = fs.readFile("src/server/Services/MoveGuard.luau")
		check(
			has(mg, 'Net.on("MoveFlip"')
				and has(mg, 'hero.mobility ~= "acrobat"')
				and has(mg, "ClimbMath.flipOk("),
			"MoveGuard checks the pick and the cooldown on its own clock"
		)
		check(has(mg, "HeroService.disabled(hero)"), "a stunned hero cannot flip")
	end)

	test("Climb: the Acrobat is the agility pick: best air control, crawl, flip, ranks match", function()
		local acro, leap = M.mobility.acrobat.air, M.mobility.leap.air
		check(acro.accel > leap.accel and acro.max > leap.max, "the best air control of any pick")
		check(#M.mobility.acrobat.text <= 44 and has(M.mobility.acrobat.text, "Crawl"), "its line says crawl")
		local names = {}
		for _, r in M.mobility.acrobat.ranks do
			table.insert(names, r.name)
		end
		check(
			table.concat(names, ",") == "Spider Grip,Spring Step,Evasion,Freerunner,Triple Jump",
			"the 5 ranks"
		)
		check(
			#MoveRanks.check(M) == 0,
			"every rank of every pick inside its own cap: " .. table.concat(MoveRanks.check(M), "; ")
		)
		for r = 0, 5 do
			local cfg = MoveRanks.config(M, "acrobat", r)
			local cap = MoveMath.speedCap(cfg, { acrobat = true }, false)
			for what, v in MoveRanks.speeds(cfg, "acrobat") do
				check(
					v <= cap * cfg.tolerance,
					string.format("acrobat rank %d %s %.1f in the cap %.1f", r, what, v, cap)
				)
			end
		end
	end)

	test("Climb: everyone sprints on Boost: 1.4x the run, never pulled back on any pick", function()
		local s = M.run.speed
		for _ = 1, 120 do
			s = ClimbMath.sprintStep(M, s, true, 1 / 60)
		end
		check(math.abs(s - M.sprint.speed) < 0.06, "eases up to the sprint in two seconds")
		for _ = 1, 120 do
			s = ClimbMath.sprintStep(M, s, false, 1 / 60)
		end
		check(math.abs(s - M.run.speed) < 0.06, "and back down")
		check(M.sprint.speed / M.run.speed >= 1.35, "clearly faster than the run")
		check(M.mobility.speed.sprint >= M.sprint.speed * 3, "Super-speed stays far faster")
		check(
			ClimbMath.sprinting(M, false, true, 1) and not ClimbMath.sprinting(M, false, true, 0.6),
			"touch edge"
		)
		check(not ClimbMath.sprinting(M, false, false, 1), "a full stick on a keyboard is no sprint")
		for _, pick in M.mobilityOrder do
			local speed = M.sprint.speed
			if pick == "acrobat" then
				speed = M.mobility.acrobat.run + M.sprint.speed - M.run.speed
			end
			local path = {}
			for i = 0, 100 do
				table.insert(path, { speed * i * 0.1, 3, 0, i * 0.1 })
			end
			check(guard(M, pick, path) == 0, pick .. ": a 10 s sprint is never pulled back")
		end
		local mc = fs.readFile("src/client/Controllers/MoveController.luau")
		check(has(mc, 'out.boost = "SPRINT"'), "SPRINT shows on the Boost button for everyone on the ground")
		check(has(mc, "ClimbMath.sprinting("), "the ground run reads the sprint rule")
		local ic = fs.readFile("src/client/Controllers/InputController.luau")
		check(has(ic, '[Enum.KeyCode.LeftShift] = "Boost"'), "Shift is Boost (no other action on it)")
		local proj = fs.readFile("default.project.json")
		check(has(proj, '"EnableMouseLockOption": false'), "Roblox's Shift Lock stays off, so Shift is free")
	end)

	test(
		"Climb: swing anywhere: trees and rocks by the wide fan, else a weaker sky line, the city best",
		function()
			local sw = M.mobility.swing
			-- one lone tree 40 ahead and off to the side, a low rock: the main fan misses, the wide one catches
			local boxes = { { x = 21, z = -36, sx = 6, sz = 6, base = 0, top = 22 } }
			local cast = SwingMath.boxCast(boxes, 0)
			check(
				SwingMath.findAnchor(M, 0, 8, 0, 0, 0, -1, 0, 0, sw.range, cast) == nil,
				"in the city the main fan alone (no low near catch)"
			)
			local a = SwingMath.findAnchor(M, 0, 8, 0, 0, 0, -1, 0, 0, sw.range, cast, true)
			check(a ~= nil and not (a :: any).sky, "a tree off to the side holds a line")
			-- nothing at all: no anchor, the sky line hangs ahead and above
			local none = SwingMath.boxCast({}, 0)
			check(
				SwingMath.findAnchor(M, 0, 8, 0, 0, 0, -1, 0, 0, sw.range, none, true) == nil,
				"open fields: no real anchor"
			)
			local d = Config.City.districts.Downtown
			check(
				SwingMath.inCity(Config.City.districts, (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2),
				"Downtown is city"
			)
			check(not SwingMath.inCity(Config.City.districts, 5000, 5000), "the outskirts are not")
			local sky = SwingMath.skyAnchor(M, 0, 8, 0, 0, -1, 0, 0, none)
			check(sky ~= nil and (sky :: any).sky == true, "the sky line fires")
			if sky then
				check(sky.y > 8 + 20 and sky.z < -20, "it hangs ahead and above")
			end
			-- under a roof (a tunnel, a pocket): no sky line through it
			local roof = SwingMath.boxCast({ { x = 0, z = 0, sx = 200, sz = 200, base = 20, top = 24 } }, 0)
			check(SwingMath.skyAnchor(M, 0, 8, 0, 0, -1, 0, 0, roof) == nil, "never through a ceiling")
			local weak = SwingMath.skyConfig(M)
			check(
				weak.mobility.swing.maxSpeed < sw.maxSpeed and weak.mobility.swing.pump < sw.pump,
				"the sky is weaker"
			)
			check(weak.mobility.swing.release.cap < sw.release.cap, "and lets go slower")
			check(
				SwingMath.skyConfig(M) == weak and M.mobility.swing.maxSpeed == sw.maxSpeed,
				"cached, base untouched"
			)
			-- a sky swing (line after line) on the sky numbers, 10 Hz through MoveCheck
			local px, py, pz, vx, vy, vz = 0, 60, 0, 0, 0, -40
			local t, path = 0, { { px, py, pz, 0 } }
			local nextS = 0.1
			for _ = 1, 6 do
				local an = SwingMath.skyAnchor(M, px, py, pz, 0, -1, vx, vz, none) :: any
				local len = SwingMath.rope(weak, px, py, pz, an.x, an.y, an.z, 0)
				for _ = 1, 60 do
					px, py, pz, vx, vy, vz, len = SwingMath.step(
						weak,
						px,
						py,
						pz,
						vx,
						vy,
						vz,
						an.x,
						an.y,
						an.z,
						len,
						len,
						0,
						-1,
						1 / 60
					)
					t += 1 / 60
					if t >= nextS then
						nextS += 0.1
						table.insert(path, { px, py, pz, t })
					end
				end
				vx, vy, vz = SwingMath.release(weak, vx, vy, vz, 0.5)
			end
			check(guard(M, "swing", path) == 0, "sky swinging is never pulled back")
			local mc = fs.readFile("src/client/Controllers/MoveController.luau")
			check(
				has(mc, "SwingMath.skyAnchor(") and has(mc, "SwingMath.skyConfig("),
				"the device falls back to the sky"
			)
		end
	)

	test("Climb: the runtime path: modes, clips, remotes, server hooks and the built place", function()
		for _, m in ClimbAnim.MODES do
			check(HeroAnim.modeIndex[m] ~= nil, m .. " is a HeroAnim mode (the Move attribute)")
		end
		check(Remotes.MoveMode.schema[1].max == #HeroAnim.MODES, "MoveMode takes every mode index")
		for _, name in
			{
				"climb",
				"bound",
				"crawl",
				"flip",
				"climbVault",
				"runFast",
				"leapGrab",
				"leapRegrab",
				"crawlLand",
			}
		do
			check(HeroAnim.CLIPS[name] ~= nil, name .. " is a clip")
		end
		for _, m in { "climb", "bound", "crawl", "flip", "climbVault" } do
			check(HeroAnim.modeClip(m, 10, false, nil) == m, m .. " plays its own clip")
		end
		check(HeroAnim.modeClip("ground", 28, false, nil) == "runFast", "the sprint stride at 28")
		check(HeroAnim.modeClip("ground", 20, false, nil) == nil, "the walk stays the Animator's")
		check(HeroAnim.modeClip("ground", 60, false, nil) == "sprint", "Super-speed keeps its sprint")
		check(HeroAnim.transition("air", "climb", 0, 0) == "leapGrab", "the grab one-shot")
		check(HeroAnim.transition("bound", "climb", 0, 0) == "leapRegrab", "the next grab")
		check(HeroAnim.transition("air", "crawl", 0, 0) == "crawlLand", "sticking to a face")
		check(HeroAnim.transition("crawl", "air", 0, 0) == "wallKick", "jumping off")
		local fl = HeroAnim.sample("flip", ClimbAnim.CLIPS.flip.dur * 0.5)
		check(fl.Root and math.abs(fl.Root[1] + 180) < 1, "the flip turns the Root half over at its middle")
		for _, r in { "MoveGrab", "MoveFlip", "MoveDodged" } do
			check(Remotes[r] ~= nil, r .. " is a remote")
		end
		local mc = fs.readFile("src/client/Controllers/MoveController.luau")
		for _, m in { 'setMode("climb")', 'setMode("bound")', 'setMode("crawl")', 'setMode("flip")' } do
			check(has(mc, m), "MoveController sets " .. m)
		end
		check(
			has(mc, 'Net.send("MoveGrab"') and has(mc, 'Net.send("MoveFlip")'),
			"the device tells the server"
		)
		check(
			has(mc, "ClimbMath.leapSmash(") and has(mc, "ClimbMath.speedSmash("),
			"the smash rule on the device"
		)
		check(has(mc, "groundRam("), "Super-speed on Boost rams on the ground too")
		local ha = fs.readFile("src/client/Controllers/HeroAnimator.luau")
		check(has(ha, 'return "climbVault"'), "HeroAnimator shows the vault")
		local is = fs.readFile("src/server/Services/ImpactService.luau")
		check(
			has(is, 'Net.on("MoveGrab", onGrab)') and has(is, "B.dmg * mult, B.radius"),
			"the grab chips the building"
		)
		local fx = fs.readFile("src/client/Fx/MoveFx.luau")
		check(
			has(fx, "MoveController.Grabbed:Connect") and has(fx, "wallCrack("),
			"the crack where the hands bite"
		)
		check(has(fx, 'Net.listen("MoveDodged"'), "DODGE! on a miss")
		-- the built place has the new modules where the runtime requires them
		local placePath = T.placePath
		if placePath and fs.isFile(placePath) then
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(placePath))
			local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
			check(
				shared and shared:FindFirstChild("ClimbMath") ~= nil,
				"ReplicatedStorage.Shared.ClimbMath built"
			)
			check(
				shared and shared:FindFirstChild("ClimbAnim") ~= nil,
				"ReplicatedStorage.Shared.ClimbAnim built"
			)
		end
	end)
end
