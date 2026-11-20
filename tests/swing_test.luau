-- The Spider-Man swing (nate's playtest 2026-11-19: "Swinging should feel like Spider-Man"): Shared.SwingMath's
-- pendulum, anchors, release and zips in Lune, a bot swinging down a real Downtown street (tests/swing_sim.luau)
-- through the server's speed check (MoveCheck at 10 Hz, also with bursty delivery), and source checks on the
-- device side (MoveController, SwingFx, CameraController, MoveGuard). Called from tests/run.luau; ONLY="Swing"
-- runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local SwingMath = require("../src/shared/SwingMath")
	local MoveMath = require("../src/shared/MoveMath")
	local MoveCheck = require("../src/shared/MoveCheck")
	local sim = require("./swing_sim")
	local M = Config.Move
	local sw = M.mobility.swing
	local len3 = SwingMath.len3

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	-- the Downtown street the bot swings down (the 4th street of the grown core), and its buildings
	local C = Config.City
	local d = C.districts.Downtown
	local pitch = C.downtown.block + C.downtown.street
	local boxes = {}
	for _, b in world.buildings do
		if b.district == "Downtown" then
			table.insert(boxes, b)
		end
	end
	local streetX = d.minX + 4 * pitch
	local runs: { any } = {}
	local function street(k: number, seconds: number): any
		local key = k * 1000 + seconds
		if not runs[key] then
			runs[key] = sim(
				Config,
				boxes,
				C.ground.y,
				{ d.minX + k * pitch, 3, d.minZ + 40 },
				{ 0, 1 },
				seconds
			)
		end
		return runs[key]
	end

	test("Swing: the pendulum holds the rope, builds speed at the bottom and caps it", function()
		-- dropped from level with the anchor 50 out: the rope holds, the bottom is fastest, the far side rises
		local px, py, pz, vx, vy, vz, len = 0, 90, 50, 0, 0, 0, 50
		local bottomSpeed, sideSpeed, far = 0, math.huge, -math.huge
		local stretch = 0
		for _ = 1, 240 do
			px, py, pz, vx, vy, vz, len =
				SwingMath.step(M, px, py, pz, vx, vy, vz, 0, 90, 0, len, 50, 0, 0, 1 / 60)
			stretch = math.max(stretch, len3(px, py - 90, pz) - len)
			local sp = len3(vx, vy, vz)
			if math.abs(pz) < 4 then
				bottomSpeed = math.max(bottomSpeed, sp)
			end
			if pz < -30 then
				far = math.max(far, py)
				sideSpeed = math.min(sideSpeed, sp)
			end
		end
		check(stretch < 1e-6, string.format("the rope never stretches (%.4f)", stretch))
		local ideal = math.sqrt(2 * sw.gravity * 50)
		check(
			bottomSpeed > ideal * 0.85 and bottomSpeed <= sw.maxSpeed + 1e-6,
			string.format("speed builds to the bottom (%.1f of an ideal %.1f)", bottomSpeed, ideal)
		)
		check(far > 60 and sideSpeed < bottomSpeed, "and carries up the far side, slowing as it climbs")
		-- pumping forward adds speed; the cap holds
		local function swingWith(push: number): number
			local x, y, z, ax, ay, az, l = 0, 50, 30, 0, 0, -30, 50
			local top = 0
			for _ = 1, 600 do
				x, y, z, ax, ay, az, l =
					SwingMath.step(M, x, y, z, ax, ay, az, 0, 90, 0, l, 50, 0, -push, 1 / 60)
				top = math.max(top, len3(ax, ay, az))
			end
			return top
		end
		local free, pumped = swingWith(0), swingWith(1)
		check(pumped >= free, string.format("the stick forward pumps (%.1f vs %.1f)", pumped, free))
		check(pumped <= sw.maxSpeed + 1e-6, "never past maxSpeed")
		-- steering: the stick across the swing moves the hero sideways
		local x, y, z, ax, ay, az, l = 0, 50, 30, 0, 0, -30, 50
		for _ = 1, 60 do
			x, y, z, ax, ay, az, l = SwingMath.step(M, x, y, z, ax, ay, az, 0, 90, 0, l, 50, 1, 0, 1 / 60)
		end
		check(x > 3, string.format("air control steers the swing (%.1f studs across)", x))
	end)

	test("Swing: a slack line catches with the fall's speed, the rope reels in off the street", function()
		-- the hero falls 30 studs inside the rope's reach, then the line goes taut: most of the fall carries on
		local px, py, pz, vx, vy, vz, len = 0, 80, 45, 0, -30, -45, 60
		local caught, after = false, 0
		for _ = 1, 90 do
			local before = len3(vx, vy, vz)
			local slack = len3(px, py - 90, pz) < len - sw.catchSlack
			px, py, pz, vx, vy, vz, len =
				SwingMath.step(M, px, py, pz, vx, vy, vz, 0, 90, 0, len, 60, 0, 0, 1 / 60)
			if slack and len3(px, py - 90, pz) >= len - 1e-6 and not caught then
				caught = true
				after = len3(vx, vy, vz) / before
			end
		end
		check(caught and after > 0.75, string.format("the catch keeps the speed (%.2f of it)", after))
		-- reeling toward a shorter target, never past it
		local l = 80
		local _, _, _, _, _, _, l2 = SwingMath.step(M, 0, 10, 0, 0, 0, 0, 0, 90, 0, l, 60, 0, 0, 0.1)
		check(math.abs(l2 - (80 - sw.reel * 0.1)) < 1e-6, "the rope reels in at `reel`")
		local _, _, _, _, _, _, l3 = SwingMath.step(M, 0, 10, 0, 0, 0, 0, 0, 90, 0, 61, 60, 0, 0, 0.5)
		check(l3 == 60, "and stops at its target")
		-- the rope: taut at once, its low point clear of the street, never under minLen
		local rope = SwingMath.rope(M, 0, 10, 60, 0, 80, 0, 0)
		check(rope <= 80 - sw.clearance + 1e-6, "the low point clears the street")
		check(
			SwingMath.rope(M, 0, 40, 20, 0, 60, 0, nil) <= math.sqrt(800) * sw.taut + 1e-6,
			"never longer than the gap"
		)
		check(SwingMath.rope(M, 0, 79, 1, 0, 80, 0, 0) == sw.minLen, "never shorter than minLen")
	end)

	test("Swing: the arc phase, the release fling and the zip stay inside the cap", function()
		check(
			math.abs(SwingMath.phase(0, 40, 50, 0, 90, 0, -1) + 0.5) < 0.05,
			"45 degrees behind on the way down: -0.5"
		)
		check(math.abs(SwingMath.phase(0, 40, 0, 0, 90, 0, 0)) < 1e-6, "the bottom: 0")
		check(math.abs(SwingMath.phase(0, 90, -50, 0, 90, 0, 5) - 1) < 1e-6, "level ahead going up: +1")
		check(
			SwingMath.atTop(M, 89, 90, 5) and not SwingMath.atTop(M, 89, 90, -5),
			"the top lets go only rising"
		)
		-- a sweet release flings further up than an early one, both keep the swing's speed
		local _, sy, sz, sweet = SwingMath.release(M, 0, 30, -80, 0.6)
		local _, ey, ez, early = SwingMath.release(M, 0, -30, -80, -0.6)
		check(sweet and not early, "the rising half is the sweet release")
		check(sy > ey and sy > 30, string.format("the sweet one flings up (%.1f vs %.1f)", sy, ey))
		check(-sz >= 80 and -ez >= 80, "and forward, the speed kept")
		local swCap = MoveMath.guardCap(M, { swing = true }, false, {})
		local worst = 0
		for _, v in { { 0, sw.maxSpeed, 0 }, { 0, 0, -sw.maxSpeed }, { 60, 60, -60 }, { 0, -sw.maxSpeed, 0 } } do
			for _, ph in { -1, -0.3, 0, 0.3, 0.6, 1 } do
				local x, y, z = SwingMath.release(M, v[1], v[2], v[3], ph)
				worst = math.max(worst, len3(x, y, z))
			end
		end
		check(
			worst <= sw.release.cap + 1e-6 and sw.release.cap <= swCap,
			string.format("a release is at most %.0f (cap %.0f)", worst, swCap)
		)
		check(
			sw.maxSpeed <= swCap and sw.zip <= swCap and sw.groundPop <= swCap,
			"the swing and zip are under the cap"
		)
		-- a zip's fastest point (its start) is never over `zip`
		for _, tgt in { { 0, 60, -80 }, { 100, 5, 0 }, { 0, 150, -10 }, { 30, -40, 30 } } do
			local time, h = SwingMath.zipPlan(M, 0, 0, 0, tgt[1], tgt[2], tgt[3])
			local peak = len3(tgt[1], tgt[2] + 4 * h, tgt[3]) / time
			check(peak <= sw.zip + 1e-6, string.format("a zip peaks at %.1f (zip %d)", peak, sw.zip))
		end
		local px, py, pz = SwingMath.zipPop(M, 3, 4)
		check(len3(px, py, pz) <= swCap and py > 0, "the point launch pops up inside the cap")
	end)

	test("Swing: lines hang only from real buildings ahead and above, snapped to roof edges", function()
		local wall = { { x = 0, z = -80, sx = 60, sz = 20, base = 0, top = 70 } }
		local cast = SwingMath.boxCast(wall, 0)
		-- looking at the building: an anchor on its face, above the hero
		local a = SwingMath.findAnchor(M, 0, 3, 0, 0, 0.2, -1, 0, 0, sw.range, cast)
		check(a ~= nil, "a building ahead holds a line")
		if a then
			check(a.y >= 3 + sw.minAbove and a.z <= -69.9, "on the building's face, above the hero")
			check(a.y <= 70 + 1e-6, "never above the roof")
		end
		-- a hit just under the roof snaps up to the roof edge
		local low = { { x = 0, z = -60, sx = 60, sz = 20, base = 0, top = 40 } }
		local b = SwingMath.findAnchor(M, 0, 3, 0, 0, 0.1, -1, 0, 0, sw.range, SwingMath.boxCast(low, 0))
		check(
			b ~= nil
				and b.edge
				and math.abs(b.y - (40 - sw.edge.below)) < sw.edge.probe / 2 ^ sw.edge.steps + 0.01,
			string.format("snapped to the roof edge (y %.1f)", b and b.y or -1)
		)
		-- nothing but the street: no line (never the empty sky); a building behind the camera: no line either
		check(
			SwingMath.findAnchor(M, 0, 3, 0, 0, 0.2, -1, 0, 0, sw.range, SwingMath.boxCast({}, 0)) == nil,
			"no anchor in open sky"
		)
		check(
			SwingMath.findAnchor(M, 0, 3, 0, 0, 0.2, 1, 0, 0, sw.range, cast) == nil,
			"nothing hangs from behind the camera"
		)
		-- out of reach: no line
		local far = { { x = 0, z = -400, sx = 60, sz = 20, base = 0, top = 300 } }
		check(
			SwingMath.findAnchor(M, 0, 3, 0, 0, 0.2, -1, 0, 0, sw.range, SwingMath.boxCast(far, 0)) == nil,
			"beyond the line's reach"
		)
		-- a building only off to the side of a street: still found by the fan, and the swing runs along the street
		local side = { { x = 40, z = -60, sx = 30, sz = 80, base = 0, top = 120 } }
		local s = SwingMath.findAnchor(M, 0, 3, 0, 0, 0.2, -1, 0, -40, sw.range, SwingMath.boxCast(side, 0))
		check(s ~= nil and s.x >= 24.9, "a side building catches the line")
		if s then
			local qx, qy, qz = SwingMath.pivot(M, 0, 0, s.x, s.y, s.z, 0, -40)
			check(
				math.abs(qx) <= s.x * sw.plane + 1e-6 and qy == s.y and qz < 0,
				"the pivot sits over the street ahead"
			)
		end
		-- the fan's ray count stays small (the device casts them only when a line fires)
		local _, rays = SwingMath.findAnchor(M, 0, 3, 0, 0, 0.2, -1, 30, 30, sw.range, cast)
		check(
			rays <= 2 * #sw.aim.yaws * #sw.lifts + 1 + sw.edge.steps,
			string.format("%d rays at most", rays)
		)
	end)

	test(
		"Swing: a bot swinging down a Downtown street chains lines and passes the server's speed check",
		function()
			local r = street(4, 12)
			local path = r.path
			check(#r.lines >= 6, string.format("lines chain (%d)", #r.lines))
			check(#r.releases >= 5, string.format("released and caught again (%d)", #r.releases))
			local dist = path[#path].z - path[1].z
			local avg = dist / path[#path].t
			check(avg >= 45, string.format("covers the street at %.1f studs/s on average", avg))
			check(r.lowest >= C.ground.y + 3 - 1e-6, "never under the street")
			-- chaining keeps speed: the next line's speed in is most of the last release's speed out
			local kept, n = 0, 0
			for i = 2, #r.lines do
				local prev, cur = r.lines[i - 1], r.lines[i]
				if prev.speedOut > 40 then
					kept += cur.speedIn / prev.speedOut
					n += 1
				end
			end
			check(
				n > 0 and kept / n > 0.6,
				string.format("a chained line keeps the speed (%.2f)", if n > 0 then kept / n else 0)
			)
			-- the fastest moments are near the bottom of the arc
			local fastPhase, fast = 0, 0
			for _, s in path do
				if s.mode == "swing" and s.speed > fast then
					fast, fastPhase = s.speed, s.phase
				end
			end
			check(
				math.abs(fastPhase) < 0.7,
				string.format("top speed %.1f at phase %.2f (near the bottom)", fast, fastPhase)
			)
			-- every 10 Hz sample through MoveCheck at the Swing cap; also with samples arriving two at a time
			local cap = MoveMath.guardCap(M, { swing = true }, false, {})
			for _, bursty in { false, true } do
				local st = MoveCheck.new(path[1].x, path[1].y, path[1].z, 0)
				local fails, nextT = 0, 0.1
				for _, s in path do
					if s.t >= nextT then
						nextT += 0.1
						local at = s.t
						if bursty and math.floor(s.t * 10 + 0.5) % 2 == 1 then
							at += 0.08 -- late, then the next one right behind it
						end
						local ok, _, wait = MoveCheck.sample(st, s.x, s.y, s.z, at, cap, M, Config.Safety)
						if not ok and not wait then
							fails += 1
						end
					end
				end
				check(
					fails == 0,
					string.format("%s: %d pull-backs", if bursty then "bursty" else "steady", fails)
				)
			end
			-- other streets too
			for _, k in { 2, 3, 5 } do
				local o = street(k, 12)
				local p = o.path
				local cap2 = MoveMath.guardCap(M, { swing = true }, false, {})
				local st = MoveCheck.new(p[1].x, p[1].y, p[1].z, 0)
				local fails, nextT = 0, 0.1
				for _, s in p do
					if s.t >= nextT then
						nextT += 0.1
						local ok, _, wait = MoveCheck.sample(st, s.x, s.y, s.z, s.t, cap2, M, Config.Safety)
						if not ok and not wait then
							fails += 1
						end
					end
				end
				check(
					fails == 0 and #o.lines >= 4,
					string.format("street %d: %d lines, %d pull-backs", k, #o.lines, fails)
				)
			end
			check(streetX ~= nil, "the street is in Downtown")
		end
	)

	test("Swing: the device side shoots, swings, lets go, zips and feels it", function()
		local mc = fs.readFile("src/client/Controllers/MoveController.luau")
		check(
			has(mc, "SwingMath.findAnchor(") and has(mc, "look.X,\n\t\tlook.Y,"),
			"the line aims with SwingMath"
		)
		check(has(mc, "SwingMath.pivot(M,"), "and swings in the plane of travel")
		check(has(mc, "SwingMath.step("), "the pendulum is SwingMath's")
		check(has(mc, "SwingMath.release(swingCfg(), vel.X, vel.Y, vel.Z, phase)"), "letting go flings")
		check(
			has(mc, "SwingMath.zipPlan(M,") and has(mc, "zipLine() -- up the line"),
			"Leap while swinging zips up the line"
		)
		check(has(mc, "SwingMath.zipPop(M, zipDir.X, zipDir.Z)"), "and pops off the top")
		check(has(mc, "and startSwing(false)"), "holding Fly catches the next line")
		check(has(mc, "part and not part.Parent"), "a broken anchor drops the line")
		check(has(mc, "swung into a wall: let go and push off it"), "swinging into a wall never sticks")
		check(has(mc, "MoveController.SwingMissed:Fire"), "no anchor: the miss cue, no swing")
		check(has(mc, 'out.leap = "ZIP"'), "the touch and HUD labels show ZIP while swinging")
		check(
			has(mc, "MoveController.swingPose = {") and has(mc, 'pose.state = "zip"'),
			"the pose state for HeroAnimator"
		)
		check(has(mc, 'Net.send("MoveLine", anchor)'), "other devices learn where the line hangs")
		local fx = fs.readFile("src/client/Fx/SwingFx.luau")
		check(has(fx, 'GetAttribute("SwingAt")'), "SwingFx draws everyone's lines")
		-- (list-combat 2026-11-20, Everything Left 393) the line wears its drawn energy cord texture, tiled along it
		local F = Config.Move.mobility.swing.feel
		check(F.texture > 0 and F.texWidth > F.width and F.texLength > 0, "the line's texture and its width")
		check(fs.isFile("art/export/fx/SwingLine.png"), "drawn by art/fx/swing_line.py")
		check(
			has(fx, 'b.Texture = "rbxassetid://" .. FEEL.texture') and has(fx, "Enum.TextureMode.Wrap"),
			"the beam wears it, tiled"
		)
		check(has(fx, "FEEL.others[QualityController.name]"), "other heroes' lines are budgeted by preset")
		check(has(fx, 'FrameProf.wrap("SwingFx"'), "its frame loop is profiled")
		check(has(fx, '"swingRelease"') and Config.Audio.sounds.swingRelease ~= nil, "the release whoosh")
		local init = fs.readFile("src/client/init.client.luau")
		check(has(init, "SwingFx.init()"), "SwingFx runs")
		local cam = fs.readFile("src/client/Controllers/CameraController.luau")
		check(
			has(cam, "SWING.fov * swingK") and has(cam, "CameraController.motion.push"),
			"FOV with speed, by Camera motion"
		)
		check(has(cam, "SWING.pull * swingK"), "and the pull-back")
		local mfx = fs.readFile("src/client/Fx/MoveFx.luau")
		check(has(mfx, "or swingFast"), "wind lines at swing speed")
		local mg = fs.readFile("src/server/Services/MoveGuard.luau")
		check(
			has(mg, 'Net.on("MoveLine"') and has(mg, 'hero.mobility == "swing"'),
			"the server checks the line"
		)
		local R = require("../src/shared/Remotes")
		check(
			R.MoveLine and R.MoveLine.dir == "C2S" and (R.MoveLine.rate or 99) <= 10,
			"MoveLine is rate-limited"
		)
	end)
end
