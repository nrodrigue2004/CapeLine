-- Super-speed's running jump (nate's playtest 2026-11-18: "Jumping with superspeed needs to be more fluid, like
-- holding the jump without losing speed"). Leap while running is an instant hop at the run's speed, the air
-- keeps it, holding Leap hops again on every landing, and the landing carries the sprint on. The server's speed
-- check passes a whole chain of top-speed hops. Called from tests/run.luau; ONLY="Speed hop" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local MoveMath = require("../src/shared/MoveMath")
	local MoveCheck = require("../src/shared/MoveCheck")
	local M = Config.Move
	local H = M.mobility.speed.hop

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	test("Speed hop: the jump keeps the run's speed and steers without losing it", function()
		local vx, vy, vz = MoveMath.speedHop(M, 100, 0, 1, 0, 100)
		check(math.abs(vx - 100) < 1e-6 and vz == 0, "a top-speed run hops at 100")
		check(vy == H.up, "with the hop's lift")
		vx, vy, vz = MoveMath.speedHop(M, 60, 0, 0, 1, 90)
		check(
			math.abs(math.sqrt(vx * vx + vz * vz) - 90) < 1e-6 and vz > 89,
			"along the stick, at the sprint so far"
		)
		vx, _, vz = MoveMath.speedHop(M, 150, 0, 0, 0, 20)
		check(math.abs(vx - M.mobility.speed.sprint) < 1e-6, "never over the top speed")
		vx, _, vz = MoveMath.speedHop(M, 0, -70, 0, 0, 20)
		check(math.abs(vz + 70) < 1e-6, "no stick: straight on at the run's speed")
		-- a second of steering hard right keeps all 100 studs/s and turns at most hop.turnRate
		local x, z = 100, 0
		for _ = 1, 60 do
			x, z = MoveMath.hopSteer(M, x, z, 0, 1, 1 / 60)
		end
		check(math.abs(math.sqrt(x * x + z * z) - 100) < 1e-6, "steering loses no speed")
		local turned = math.deg(math.atan2(z, x))
		check(
			turned > 0 and turned <= H.turnRate + 0.01,
			string.format("and turns %.0f degrees in a second", turned)
		)
	end)

	test("Speed hop: a chain of top-speed hops passes the server's speed check", function()
		local cap = MoveMath.speedCap(M, { speed = true }, false)
		check(cap >= math.sqrt(100 * 100 + H.up * H.up) - 1e-6, "the cap covers top speed plus the lift")
		local st = MoveCheck.new(0, 10, 0, 0)
		local x, y, vy, t, fails = 0, 10, 0, 0, 0
		for _ = 1, 10 * 20 do -- 20 s of hops sampled at 10 Hz
			t += 0.1
			if y <= 10 then
				vy = H.up -- held Leap: hop again on landing
			end
			x += 100 * 0.1
			y = math.max(10, y + vy * 0.1)
			vy -= M.airGravity * 0.1
			if not MoveCheck.sample(st, x, y, 0, t, cap, M, Config.Safety) then
				fails += 1
			end
		end
		check(fails == 0, string.format("no pull-backs (%d)", fails))
		local air = 2 * H.up / M.airGravity
		check(
			air > 0.5 and air < 1.2,
			string.format("a hop is %.2f s in the air (%.0f studs at top speed)", air, air * 100)
		)
	end)

	test(
		"Speed hop: the controller hops with no crouch, re-hops while Leap is held and lands at full run",
		function()
			local src = fs.readFile("src/client/Controllers/MoveController.luau")
			check(
				has(src, "MoveMath.speedHop(M, runFlat.X, runFlat.Z"),
				"Leap while running is the hop (no charge)"
			)
			check(has(src, "MoveMath.hopSteer(M, vel.X, vel.Z"), "the air keeps the run's speed")
			check(
				string.find(src, 'hopping%s+and mode == "air"%s+and InputController.isDown%("Leap"%)') ~= nil,
				"holding Leap hops again"
			)
			check(has(src, 'toGround(fallSpeed, hopping and mode == "air")'), "the landing keeps the run")
			check(has(src, "local keep = if keepRun then 1 else 0.3"), "full speed on landing")
		end
	)
end
