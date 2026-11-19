-- DriveMath (gap-vehicles, 2026-11-19): wheels that roll, steer and sway, and escorts that drive. Called from
-- tests/run.luau:
--   require("./drive_test")({ test = test, check = check, Config = Config })
-- ONLY="Drive" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local DriveMath = require("../src/shared/DriveMath")
	local D = Config.Destruction.vehicles.drive
	local R = Config.Destruction.vehicles.rig

	local function near(a: number, b: number, e: number?): boolean
		return math.abs(a - b) <= (e or 1e-6)
	end

	test("Drive: a wheel turns once for each of its circumferences", function()
		local r = 1.05
		local a = DriveMath.spin(0, math.pi * r, r)
		check(near(a, math.pi), "half a circumference is half a turn")
		check(near(DriveMath.spin(0, 2 * math.pi * r, r), 0, 1e-9), "a whole one is a whole turn")
		check(near(DriveMath.spin(0, -math.pi * r / 2, r), 1.5 * math.pi), "backwards turns it back")
		-- a bigger wheel turns slower for the same road
		check(DriveMath.spin(0, 1, 1.4) < DriveMath.spin(0, 1, 1.05), "a truck's big wheel turns slower")
		check(DriveMath.spin(0.3, 5, 0) == 0.3, "no radius: no turn")
	end)

	test("Drive: the front wheels steer into the turn, straight when standing", function()
		local wb = 7
		check(DriveMath.steer(0, 9, wb, R.maxSteer) == 0, "straight on: straight wheels")
		local left = DriveMath.steer(0.5, 9, wb, R.maxSteer)
		check(left > 0, "a left turn steers left")
		check(near(left, math.atan(wb * 0.5 / 9)), "the bicycle model's angle")
		check(DriveMath.steer(-0.5, 9, wb, R.maxSteer) == -left, "a right turn steers right")
		check(DriveMath.steer(5, 9, wb, R.maxSteer) == R.maxSteer, "held to the most the wheels turn")
		check(DriveMath.steer(0.5, 0.1, wb, R.maxSteer) == 0, "standing still the wheels stay straight")
		check(
			DriveMath.steer(0.5, 18, wb, R.maxSteer) < left,
			"the same turn at speed needs less lock (a wider curve)"
		)
		check(near(DriveMath.turn(3, -3), 2 * math.pi - 6), "the short way round past pi")
	end)

	test("Drive: the body pitches on pull and brake, leans out of a turn and settles", function()
		local s = DriveMath.sway()
		for _ = 1, 30 do
			DriveMath.swayStep(s, 5, 0, 1 / 60, R.sway)
		end
		check(s.pitch > 0, "pulling away lifts the nose")
		check(s.pitch <= R.sway.maxPitch * 1.3, "but not far")
		local b = DriveMath.sway()
		for _ = 1, 30 do
			DriveMath.swayStep(b, -20, 0, 1 / 60, R.sway)
		end
		check(b.pitch < 0, "braking dips the nose")
		local t = DriveMath.sway()
		for _ = 1, 30 do
			DriveMath.swayStep(t, 0, 9 * 0.6, 1 / 60, R.sway)
		end
		check(t.roll < 0, "a left turn leans the body out to the right")
		-- let go: it settles, even through a phone hitch
		DriveMath.swayStep(t, 0, 0, 0.5, R.sway)
		for _ = 1, 240 do
			DriveMath.swayStep(t, 0, 0, 1 / 60, R.sway)
		end
		check(DriveMath.still(t), "it settles back level")
		local k = DriveMath.sway()
		DriveMath.swayStep(k, 0, 0, 1 / 60, R.sway, -R.kick)
		check(k.heave < 0, "a kick drops it onto its springs")
		local big = 0
		for _ = 1, 120 do
			DriveMath.swayStep(k, 0, 0, 1 / 60, R.sway)
			big = math.max(big, math.abs(k.heave))
		end
		check(big < 0.5 and DriveMath.still(k), "a small bounce that settles in two seconds")
		local x, v = DriveMath.spring(0, 0, 1, 70, 11, 2)
		check(near(x, 1, 0.05) and math.abs(v) < 0.5, "one long step of the spring stays stable")
	end)

	-- an L-shaped road: 40 east, then 40 north
	local L = { { 0, 0, 0 }, { 40, 0, 0 }, { 40, 0, -40 } }

	test("Drive: the pose follows the path and turns through rounded corners", function()
		local x, _, z, yaw = DriveMath.pose(L, 10, D.round)
		check(near(x, 10) and near(z, 0), "on a straight it is on the road")
		check(near(yaw, DriveMath.yaw(1, 0)), "nose along the road")
		local _, _, _, y0 = DriveMath.pose(L, 40 - D.round, D.round)
		local cx, _, cz, y1 = DriveMath.pose(L, 40, D.round)
		local _, _, _, y2 = DriveMath.pose(L, 40 + D.round, D.round)
		check(near(y0, DriveMath.yaw(1, 0), 1e-3), "the curve starts on the first heading")
		check(near(y2, DriveMath.yaw(0, -1), 1e-3), "and ends on the second")
		local mid = DriveMath.turn(y0, y1)
		check(mid > 0.6 and mid < 1.0, "halfway round it is halfway turned (" .. mid .. ")")
		check(cx < 40 and cz < 0, "it cuts the corner instead of touching it")
		-- the heading never jumps along the whole path
		local last = nil
		for s = 0, 80, 0.5 do
			local _, _, _, y = DriveMath.pose(L, s, D.round)
			if last then
				check(math.abs(DriveMath.turn(last, y)) < 0.2, "no snap at " .. s)
			end
			last = y
		end
		local ex, _, ez = DriveMath.pose(L, 500, D.round)
		check(near(ex, 40) and near(ez, -40), "past the end it waits at the end")
		-- side quest paths are { x, y, z }, contracts' are Vector3-like
		local vx = DriveMath.pose({ { X = 0, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 10 } } :: any, 5, D.round)
		check(near(vx, 0), "a path of Vector3s works too")
	end)

	test("Drive: it pulls away, slows into a corner and brakes when nobody escorts it", function()
		local cruise = 9
		local at, v = 0, 0
		at, v = DriveMath.step(at, v, cruise, true, L, 80, 0.5, D)
		check(v > 0 and v < cruise, "it pulls away from a stop, not at full speed at once")
		local slowest, top = cruise, 0
		local t = 0
		while at < 80 and t < 60 do
			at, v = DriveMath.step(at, v, cruise, true, L, 80, 1 / 30, D)
			t += 1 / 30
			if at > 30 and at < 42 then
				slowest = math.min(slowest, v)
			end
			top = math.max(top, v)
		end
		check(near(top, cruise, 1e-6), "it reaches its cruise on the straight")
		check(slowest < cruise * 0.75, "it slows for the right-angle corner (" .. slowest .. ")")
		check(slowest >= cruise * D.corner - 0.01, "but never below the corner share")
		check(at == 80 and v == 0, "it stops at the end of its drive")
		check(t < 80 / cruise * 1.35, "the drive takes about as long as before (" .. t .. " s)")
		-- nobody near: it brakes to a stop in a short way
		local a2, v2 = 0, cruise
		local t2 = 0
		while v2 > 0 and t2 < 5 do
			a2, v2 = DriveMath.step(a2, v2, cruise, false, { { 0, 0, 0 }, { 0, 0, 200 } }, 200, 1 / 30, D)
			t2 += 1 / 30
		end
		check(v2 == 0 and a2 < 2.5, "with nobody near it stops within a couple of studs (" .. a2 .. ")")
		local f = DriveMath.corner({ { 0, 0, 0 }, { 0, 0, 100 }, { 1, 0, 200 } }, 50, D)
		check(f > 0.98, "a gentle bend barely slows it")
	end)
end
