-- The movement fixes from nate's playtest (2026-11-19): "Can't jump in tunnel so I'm stuck", "Rid of slide",
-- "Swing doesn't work properly", "Leap could be a bit better for leap mobility chosen" and "Should be able to
-- jump onto building and keep wall running". Pure maths in Lune plus source checks; every new speed passes
-- the server's speed check (MoveMath.guardCap, MoveCheck). Called from tests/run.luau; ONLY="Move fixes" runs
-- just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local MoveMath = require("../src/shared/MoveMath")
	local MoveCheck = require("../src/shared/MoveCheck")
	local OpeningPlan = require("../src/shared/OpeningPlan")
	local HeroAnim = require("../src/shared/HeroAnim")
	local M = Config.Move

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function len3(x: number, y: number, z: number): number
		return math.sqrt(x * x + y * y + z * z)
	end
	local mc = fs.readFile("src/client/Controllers/MoveController.luau")

	-- a path of (x, y, z) samples at 10 Hz through the server's check: the number of pull-backs
	local function pullBacks(path: { { number } }, cap: number): number
		local p0 = path[1]
		local st = MoveCheck.new(p0[1], p0[2], p0[3], 0)
		local fails = 0
		for i = 2, #path do
			local p = path[i]
			if not MoveCheck.sample(st, p[1], p[2], p[3], (i - 1) * 0.1, cap, M, Config.Safety) then
				fails += 1
			end
		end
		return fails
	end

	test("Move fixes: the sky's ceiling never flattens a Leap or a flight down in the pockets", function()
		local pocketY = Config.Story.pockets.y
		check(not MoveMath.ceilingOn(M, pocketY), "no ceiling at the pockets' height (the subway too)")
		check(MoveMath.ceilingOn(M, M.ceiling.hard), "the ceiling still acts at the top of the sky")
		check(M.ceiling.hard + M.ceiling.band < pocketY - 100, "the band ends well below the pockets")
		-- climbing in a pocket keeps rising; at the top of the sky the push down still wins
		local input = { wishX = 0, wishY = 1, wishZ = 0, vertical = 1, boost = false }
		local _, vy = MoveMath.flightStep(M, 0, 20, 0, pocketY + 5, 100, input, 1 / 60)
		check(vy > 20, string.format("a flight climbs in a pocket (vy %.1f)", vy))
		_, vy = MoveMath.flightStep(M, 0, 20, 0, M.ceiling.hard + 1, 100, input, 1 / 60)
		check(vy <= -5, "and is pushed back down at the top of the sky")
		check(
			has(mc, "pos.Y > M.ceiling.hard and vel.Y > 0 and MoveMath.ceilingOn(M, pos.Y)"),
			"the controller's air ceiling uses the same rule (it zeroed every Leap at y 3,000)"
		)
		-- a Leap in the subway tunnel now rises: the full leap's apex is far over the hero's head room
		local S = Config.Story.opening.subway
		local _, lvy = MoveMath.leapLaunch(M, 0, -1, 1)
		check(lvy * lvy / (2 * M.airGravity) > S.rubble + 2, "a Leap clears the tunnel's rubble")
	end)

	test("Move fixes: the tunnel's rubble only ever shuts the way back", function()
		local S = Config.Story.opening.subway
		for i = 1, S.lanes do
			local lane = OpeningPlan.lane(Config, i)
			for k, c in lane.collapses do
				local startZ = lane.start[3]
				check(
					not OpeningPlan.rubbleShuts(Config, lane, k, startZ),
					"no wall in front of a hero at the start"
				)
				check(
					not OpeningPlan.rubbleShuts(Config, lane, k, c.z),
					"a hero caught under the pile walks out of it"
				)
				check(
					OpeningPlan.rubbleShuts(Config, lane, k, lane.z1 - 2),
					"behind a hero in the chamber it is shut"
				)
				-- the moment a slab falls, the hero is already past its rubble (nothing lands on or in front of them)
				local fallZ = c.z - S.slab / 2 - S.behind
				check(OpeningPlan.slabFalls(Config, lane, k, fallZ), "the slab falls here")
				check(OpeningPlan.rubbleShuts(Config, lane, k, fallZ), "and only shuts behind the hero")
			end
		end
		-- the guided roof hops never apply down in the subway (a city target would fling the hero away)
		check(OpeningPlan.hopsAt(Config, "descend", 40), "the descend hop works in the city")
		check(
			not OpeningPlan.hopsAt(Config, "descend", Config.Story.pockets.y + 3),
			"but never in the subway"
		)
		check(not OpeningPlan.hopsAt(Config, "tunnel", 40), "the tunnel is no guided hop")
		local fx = fs.readFile("src/client/Fx/PrologueFx.luau")
		check(
			has(fx, "OpeningPlan.rubbleShuts(Config, lane, k, r.Position.Z)"),
			"PrologueFx follows the rule"
		)
		check(
			has(fx, "OpeningPlan.hopsAt(Config, step, r.Position.Y)"),
			"and the hop assist checks the height"
		)
		check(not has(fx, "slab.CanCollide = true"), "no pile is made solid regardless of where the hero is")
	end)

	test("Move fixes: Super-speed's slide is gone, the mode slots keep their numbers", function()
		check(M.mobility.speed.slide == nil, "no slide tuning")
		check(not has(mc, 'setMode("slide")') and not has(mc, '"SLIDE"'), "no slide mode or button")
		check(not has(mc, "slideUntil"), "no slide timer")
		check(HeroAnim.modeIndex.slide == nil and HeroAnim.CLIPS.slide == nil, "no slide pose")
		check(#HeroAnim.MODES == 13 and HeroAnim.modeIndex.swing == 10, "later modes keep their wire index")
		check(HeroAnim.modeClip("retired", 30, false, nil) == "air", "the retired slot poses as the air")
		-- the running jump (2026-11-18) is untouched
		check(has(mc, "MoveMath.speedHop(M, runFlat.X, runFlat.Z"), "the Super-speed hop is still there")
	end)

	test("Move fixes: the swing attaches reliably, never scrapes the street and flings on release", function()
		local sw = M.mobility.swing
		check(#sw.lifts >= 3 and sw.lifts[1] == 0.45, "the line tries several aims, the old one first")
		-- the rope's length keeps the low point clear of the ground and stays taut
		local len = MoveMath.swingRope(M, 0, 10, 60, 0, 80, 0, 0)
		check(len <= 80 - sw.clearance + 1e-6, string.format("low point clears the street (rope %.1f)", len))
		check(
			MoveMath.swingRope(M, 0, 40, 20, 0, 60, 0, 0) <= math.sqrt(20 * 20 + 20 * 20) * 0.95 + 1e-6,
			"never longer than the gap"
		)
		check(MoveMath.swingRope(M, 0, 79, 1, 0, 80, 0, 0) == sw.minLen, "never shorter than minLen")
		-- swing from a ledge-height start: the hero stays on or inside the rope's sphere, above the street
		local ax, ay, az = 0, 90, 0
		local px, py, pz, vx, vy, vz = 0, 30, 70, 0, 0, -30
		local rope = MoveMath.swingRope(M, px, py, pz, ax, ay, az, 0)
		local low, high, past = math.huge, -math.huge, false
		for _ = 1, 240 do
			px, py, pz, vx, vy, vz =
				MoveMath.swingStep(M, px, py, pz, vx, vy, vz, ax, ay, az, rope, 0, -1, 1 / 60)
			low = math.min(low, py)
			if pz < 0 then
				past = true
				high = math.max(high, py)
			end
		end
		check(low >= ay - rope - 1e-3 and low > 0, string.format("lowest point %.1f is over the street", low))
		check(past and high > 20, "the swing carries through and up the far side")
		-- letting go keeps the swing's speed (a fling), capped inside the server's swing cap
		local rx, ry, rz = MoveMath.swingRelease(M, 0, 0, -sw.maxSpeed)
		local out = len3(rx, ry, rz)
		check(out >= sw.maxSpeed and ry > 0, "letting go flings on and up")
		check(out <= sw.release.cap + 1e-6, "at most release.cap")
		local swCap = MoveMath.guardCap(M, { swing = true }, false, {})
		check(
			sw.release.cap <= swCap and sw.groundPop <= swCap,
			"release and ground pop are under the swing cap"
		)
		-- a swing at top speed, then the release's flight, sampled by the server
		local path = {}
		local x, y, z, fvy = 0, 60, 0, ry
		for i = 1, 30 do
			table.insert(path, { x, y, z })
			if i <= 10 then
				z -= sw.maxSpeed * 0.1
			else
				z += rz * 0.1
				y += fvy * 0.1
				fvy -= M.airGravity * 0.1
			end
		end
		check(pullBacks(path, swCap) == 0, "a swing and its release pass the speed check")
		check(
			has(mc, "swingAim()") and has(mc, "MoveMath.swingRope(M"),
			"the controller aims and sizes the rope"
		)
		check(has(mc, "MoveMath.swingRelease(M, vel.X, vel.Y, vel.Z)"), "and flings on release")
		check(has(mc, "part and not part.Parent"), "a broken anchor drops the line")
		check(has(mc, "swung into a wall: let go and push off it"), "swinging into a wall never sticks")
	end)

	test("Move fixes: Leaping is quicker to charge, keeps the run and steers in the air", function()
		local lp = M.mobility.leap
		check(lp.charge <= 0.3 and lp.charge < 0.4, "a shorter crouch than the old 0.4 s")
		check(lp.minCharge >= 0.5 and lp.cooldown <= 0.6, "a tapped leap is big, the cooldown short")
		local _, tapVy = MoveMath.superLeapLaunch(M, 1, 0, 0)
		check(tapVy * tapVy / (2 * M.airGravity) >= lp.apex * 0.5 - 0.5, "a tap still leaps half the apex")
		-- running into a leap keeps some of the run
		local still = MoveMath.superLeapLaunch(M, 1, 0, 1)
		local run = MoveMath.superLeapLaunch(M, 1, 0, 1, M.caps.run, 0)
		check(math.abs(run - still - M.caps.run * lp.carry) < 1e-6, "carry adds the run's share")
		local fast = MoveMath.superLeapLaunch(M, 1, 0, 1, 500, 0)
		check(math.abs(fast - run) < 1e-6, "but never more than a top run's worth")
		local cap = MoveMath.guardCap(M, { leap = true }, false, {})
		check(cap >= MoveMath.superLeapSpeed(M), "the server's cap covers the carried leap")
		-- the air steer turns a leap without slowing it and builds at most air.max from a standstill
		local sx, sz = MoveMath.airSteer(60, 0, 0, 1, lp.air.accel, lp.air.max, 1)
		check(math.abs(math.sqrt(sx * sx + sz * sz) - 60) < 1e-6 and sz > 0, "steering turns a fast leap")
		sx, sz = 0, 0
		for _ = 1, 300 do
			sx, sz = MoveMath.airSteer(sx, sz, 1, 0, lp.air.accel, lp.air.max, 1 / 60)
		end
		check(math.abs(sx - lp.air.max) < 1e-6, "and builds up to air.max at most")
		-- a bounce off a wall at the leap's speed stays legal
		local lvx = MoveMath.superLeapLaunch(M, 1, 0, 1, M.caps.run, 0)
		local b = lp.bounce
		check(
			math.sqrt(b.up ^ 2 + (b.out + lvx * b.keep) ^ 2) <= cap,
			"a bounce that keeps its speed along the wall is legal"
		)
		check(lp.pound.minFall <= 15, "the pound works from lower down")
		-- a chain of running full leaps, sampled by the server
		local vx, vy, vz = MoveMath.superLeapLaunch(M, 1, 0, 1, M.caps.run, 0)
		local path, x, y, yv = {}, 0, 10, vy
		for _ = 1, 80 do
			table.insert(path, { x, y, 0 })
			x += vx * 0.1
			y += yv * 0.1
			yv -= M.airGravity * 0.1
			if y <= 10 then
				y, yv = 10, vy
			end
		end
		check(vz == 0 and pullBacks(path, cap) == 0, "running leaps pass the speed check")
		check(
			has(mc, "MoveMath.superLeapLaunch(M, flat.X, flat.Z, frac, chargeRun.X, chargeRun.Z)"),
			"launch carries"
		)
		check(has(mc, "MoveMath.airSteer(vel.X, vel.Z, flat.X, flat.Z, A.accel, A.max, dt)"), "air steer")
		check(
			has(mc, "MoveController.chargeFraction()") or has(mc, "function MoveController.chargeFraction"),
			"charge"
		)
		local fx = fs.readFile("src/client/Fx/MoveFx.luau")
		check(has(fx, "MoveController.chargeFraction()"), "MoveFx shows the charge filling")
	end)

	test("Move fixes: jumping at a building grabs the wall, runs along it and chains", function()
		local a, sp = M.mobility.acrobat, M.mobility.speed
		local head, glance = 0.95, 0.3
		-- Acrobat: head-on with the stick in climbs; glancing runs along at the speed it came in
		local kind, speed = MoveMath.wallGrab(M, "acrobat", 40, head, true)
		check(kind == "wall" and speed == a.climb, "Acrobat jumps at a wall and climbs it")
		kind, speed = MoveMath.wallGrab(M, "acrobat", 50, glance, false)
		check(kind == "wallrun" and speed == 50, "a glancing jump runs along it at its speed")
		kind, speed = MoveMath.wallGrab(M, "acrobat", 200, glance, true)
		check(kind == "wallrun" and speed == a.cap, "never over the Acrobat cap")
		kind = MoveMath.wallGrab(M, "acrobat", a.wallRunMin - 1, glance, false)
		check(kind == nil, "too slow to run a wall")
		-- Super-speed: a hop into a wall runs up it, a glancing one runs along at the run's speed
		kind, speed = MoveMath.wallGrab(M, "speed", sp.waterRun, head, false)
		check(kind == "wall" and speed == sp.wallRun, "a Super-speed hop into a wall runs up it")
		kind, speed = MoveMath.wallGrab(M, "speed", 90, glance, false)
		check(kind == "wallrun" and speed == 90, "and along one at the run's speed")
		kind = MoveMath.wallGrab(M, "speed", sp.hop.from - 1, glance, false)
		check(kind == nil, "not at a walk")
		check(MoveMath.wallGrab(M, "leap", 90, head, true) == nil, "Leaping bounces instead")
		check(MoveMath.wallGrab(M, "flight", 90, glance, true) == nil, "Flight has no wall runs")
		-- the run keeps going while held (it used to end after a fixed 1.6 s)
		check(a.wallRunTime >= 3, "an Acrobat wall run lasts while the stick is held")
		check(MoveMath.wallRunKeep(M, "acrobat", 2.5, 1, 0, 0, 1, false, 0), "stick along the wall: on")
		check(not MoveMath.wallRunKeep(M, "acrobat", 2.5, 0, 0, 0, 1, false, 0), "stick let go: off")
		check(not MoveMath.wallRunKeep(M, "acrobat", 1, 0, 1, 0, 1, false, 0), "stick pulled away: off")
		check(
			not MoveMath.wallRunKeep(M, "acrobat", a.wallRunTime, 1, 0, 0, 1, false, 0),
			"up to wallRunTime"
		)
		check(
			MoveMath.wallRunKeep(M, "speed", 9, 0, 0, 0, 1, true, 5),
			"Super-speed: while held, with stamina"
		)
		check(not MoveMath.wallRunKeep(M, "speed", 1, 0, 0, 0, 1, true, 0), "out of stamina: off")
		-- the kick off keeps the speed along the wall and stays inside each cap
		for _, pick in { "acrobat", "speed" } do
			local cap = MoveMath.guardCap(M, { [pick] = true }, false, {})
			local m = M.mobility[pick]
			local kx, ky, kz = MoveMath.wallKick(M, pick, 1, 0, m.cap, 0, 1, 55, 35)
			check(len3(kx, ky, kz) <= m.cap + 1e-6 and m.cap <= cap, pick .. ": the kick is inside the cap")
			check(kx > 0 and ky > 0 and kz > 0, pick .. ": along, up and away")
		end
		-- an alley chain: run along wall A, kick across to wall B, run along it, kick back, sampled by the server
		local acCap = MoveMath.guardCap(M, { acrobat = true }, false, {})
		local path, x, y, z = {}, 0, 20, 0
		for leg = 1, 6 do
			for _ = 1, 10 do -- 1 s along a wall at the cap
				table.insert(path, { x, y, z })
				x += a.cap * 0.1
				y -= a.sink * 0.1
			end
			local kx, ky, kz = MoveMath.wallKick(
				M,
				"acrobat",
				1,
				0,
				a.cap,
				0,
				if leg % 2 == 1 then 1 else -1,
				a.jump,
				a.jumpForward
			)
			for _ = 1, 4 do -- 0.4 s across the alley
				table.insert(path, { x, y, z })
				x += kx * 0.1
				y += ky * 0.1
				z += kz * 0.1
			end
		end
		check(pullBacks(path, acCap) == 0, "a chain of wall runs passes the speed check")
		check(
			has(mc, "airWallGrab(flat, now)"),
			"the air checks for a wall to grab (Acrobat and Super-speed)"
		)
		check(has(mc, "MoveMath.wallRunKeep("), "the run lasts while held")
		check(has(mc, "kickAlong(M.mobility.acrobat.jump, M.mobility.acrobat.jumpForward)"), "Leap kicks on")
		check(not has(mc, "wallUntil"), "no fixed wall run timer")
	end)
end
