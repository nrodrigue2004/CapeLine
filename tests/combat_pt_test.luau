-- nate's playtest 2026-11-19 (combat list): lock-on (soft and hard), omnidirectional movement (flight too),
-- knockback by move that sends robots through buildings, the block key, a drop onto a roof smashing it, and
-- grabbing a robot to swing it. The pure parts: Shared.LockRules, Shared.KnockRules, MoveMath's omni steps,
-- EnemySim.launch, ImpactRules' drop curve, ThrowMath's swing rules, and the key map read from the source.
-- Called from tests/run.luau; ONLY="PT combat" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local LockRules = require("../src/shared/LockRules")
	local KnockRules = require("../src/shared/KnockRules")
	local MoveMath = require("../src/shared/MoveMath")
	local EnemySim = require("../src/shared/EnemySim")
	local ImpactRules = require("../src/shared/ImpactRules")
	local ThrowMath = require("../src/shared/ThrowMath")
	local SettingsRules = require("../src/shared/SettingsRules")
	local TouchLayout = require("../src/shared/TouchLayout")
	local Status = require("../src/shared/Status")

	local KN = Config.Combat.knock
	local LK = Config.Combat.lock
	local M = Config.Move

	local function near(a: number, b: number, eps: number?): boolean
		return math.abs(a - b) <= (eps or 1e-6)
	end

	---------------------------------------------------------------------------
	-- Knockback by move
	---------------------------------------------------------------------------

	test("PT combat: every damaging ability and weapon move has a knockback kind and a throw", function()
		local n, weapons = 0, 0
		local byKind: { [string]: number } = {}
		for id, row in Config.Abilities.list do
			if KnockRules.damaging(row) then
				n += 1
				if row.weapon then
					weapons += 1
				end
				local kind = KnockRules.kind(KN, row)
				check(KN.kinds[kind] ~= nil, id .. ": a known kind (" .. kind .. ")")
				byKind[kind] = (byKind[kind] or 0) + 1
				local plan = KnockRules.plan(KN, kind)
				if kind == "field" then
					check(plan.dist == 0, id .. ": a field holds, never shoves")
				else
					check(plan.dist > 0, id .. ": throws its target")
				end
			end
		end
		check(
			n >= 250 and weapons >= 150,
			string.format("all moves covered (%d, %d weapon moves)", n, weapons)
		)
		for _, kind in { "field", "jab", "strike", "heavy", "super" } do
			check((byKind[kind] or 0) > 0, "some moves are " .. kind)
		end
		for k in KN.kinds do
			check(table.find(KN.order, k) ~= nil, k .. " is in the order list")
		end
	end)

	test("PT combat: light jabs shove, smashes knock hard, charged and super moves launch huge", function()
		local d: { [string]: number } = {}
		for _, k in { "jab", "strike", "heavy", "charged", "super" } do
			d[k] = KnockRules.plan(KN, k).dist
		end
		check(
			d.jab < d.strike and d.strike < d.heavy and d.heavy < d.charged and d.charged < d.super,
			"rising"
		)
		check(KnockRules.plan(KN, "jab").speed == 0, "a jab is an instant shove, no flight")
		check(
			KnockRules.plan(KN, "heavy").speed > 0 and KnockRules.plan(KN, "heavy").lift > 0,
			"a heavy flies"
		)
		-- kinds from the rows
		local A = Config.Abilities.list
		check(KnockRules.kind(KN, A.ZapBolt) == "jab", "a basic is a jab")
		check(KnockRules.kind(KN, A.StaticField) == "field", "a field ticks")
		check(KnockRules.kind(KN, { slot = "super", shape = "nova", coeff = 3 }) == "super", "a super")
		check(KnockRules.kind(KN, { slot = "skill", shape = "nova", coeff = 2.4 }) == "heavy", "a slam")
		check(KnockRules.kind(KN, { slot = "skill", shape = "bolt", coeff = 1.0 }) == "strike", "a skill")
		check(
			KnockRules.kind(KN, { slot = "skill", shape = "bolt", coeff = 1, knockKind = "swing" }) == "swing",
			"own"
		)
		-- charge: a full charge is "charged", half lies between
		local half = KnockRules.plan(KN, "strike", { charge = 0.5 })
		local full = KnockRules.plan(KN, "strike", { charge = 1 })
		check(half.dist > d.strike and half.dist < d.charged, "half a charge lies between")
		check(
			full.kind == "charged" and near(full.dist, d.charged),
			"a full charge throws like a charged move"
		)
		-- a combo's last hit, a crit, a knockback status's own distance
		check(KnockRules.plan(KN, "jab", { last = true }).dist > d.jab, "the combo finisher throws further")
		check(KnockRules.plan(KN, "strike", { crit = true }).dist > d.strike, "a crit throws further")
		check(KnockRules.plan(KN, "jab", { knock = 18 }).dist == 18, "a Haymaker keeps its 18 studs")
	end)

	test("PT combat: bosses resist knockback, PvP knockback is compressed and capped", function()
		check(KnockRules.plan(KN, "super", { boss = true }).dist == 0, "a world boss never moves")
		check(KnockRules.plan(KN, "super", { immune = true }).dist == 0, "an immune robot never moves")
		local mini = KnockRules.plan(KN, "super", { miniBoss = true })
		check(
			mini.dist > 0 and mini.dist <= KnockRules.plan(KN, "super").dist * 0.15,
			"a mini-boss barely moves"
		)
		local P = Config.Pvp
		check(
			KnockRules.pvp(KN, P, "jab", 10) == 0 and KnockRules.pvp(KN, P, "strike", 10) == 0,
			"no jab juggles"
		)
		check(near(KnockRules.pvp(KN, P, "heavy", 28), 28 * P.knock.scale), "a heavy is compressed")
		check(KnockRules.pvp(KN, P, "super", 500) == P.knock.maxDistance, "never past the PvP cap")
		check(near(KnockRules.arc(10, 0.5), 10) and KnockRules.arc(10, 0) == 0, "the arc peaks at the middle")
	end)

	-- a flat world with one building box (x 20..40, z -10..10, 40 high)
	local function world(wallHit: any): any
		return EnemySim.new(Config, {
			heightAt = function(x: number, z: number)
				if x >= 20 and x <= 40 and z >= -10 and z <= 10 then
					return 40
				end
				return 0
			end,
			wallHit = wallHit,
			random = function()
				return 0.5
			end,
		})
	end

	local function fly(sim: any, secs: number)
		local t = sim.now
		for _ = 1, math.floor(secs * 30) do
			t += 1 / 30
			EnemySim.step(sim, t, {})
		end
	end

	test("PT combat: a launched robot flies an arc and breaks through a building in its way", function()
		local hits = 0
		local sim = world(function()
			hits += 1
			return true
		end)
		local e = EnemySim.spawn(sim, "BruteBot", 0, 3, 0, 5) :: any
		check(e ~= nil, "a robot")
		local y0 = e.y
		local plan = KnockRules.plan(KN, "super")
		check(EnemySim.launch(sim, e.id, 1, 0, plan.dist, plan.lift, plan.speed, 7), "launched")
		check(EnemySim.launching(sim, e.id), "in flight")
		fly(sim, 0.25)
		check(e.y > y0 + 1, "it rises along the arc")
		check(bit32.band(e.flags, Status.BITS.lifted) ~= 0, "it tumbles on every screen while it flies")
		fly(sim, 3)
		check(hits >= 1, "the building's wall was asked to break")
		check(e.x > 40, string.format("out the far side of the building (x %.1f)", e.x))
		check(not EnemySim.launching(sim, e.id) and near(e.y, y0, 0.01), "landed on the ground again")
	end)

	test(
		"PT combat: a wall that holds stops the launch dazed; a held exit sends it back out the hole",
		function()
			local sim = world(function()
				return false
			end)
			local e = EnemySim.spawn(sim, "BruteBot", 0, 3, 0, 5) :: any
			EnemySim.launch(sim, e.id, 1, 0, 60, 4, 80, 7)
			fly(sim, 2)
			check(e.x < 20, string.format("stopped short of the wall (x %.1f)", e.x))
			check(
				Status.has(e.status, "stun", sim.now) or not EnemySim.launching(sim, e.id),
				"dazed, not flying"
			)
			-- the entry breaks, the far wall holds: it comes back out where it went in
			local calls = 0
			local sim2 = world(function(_, _, _, _, _, _, _, exit)
				calls += 1
				return not exit
			end)
			local e2 = EnemySim.spawn(sim2, "BruteBot", 0, 3, 0, 5) :: any
			EnemySim.launch(sim2, e2.id, 1, 0, 60, 4, 80, 7)
			fly(sim2, 3)
			check(calls >= 2, "asked for the way in and the way out")
			check(e2.x < 20, string.format("back outside the hole (x %.1f)", e2.x))
			-- immune robots and held robots never launch
			local t = EnemySim.spawn(sim2, "Turret", -30, 3, 0, 5) :: any
			if t then
				check(not EnemySim.launch(sim2, t.id, 1, 0, 40, 4, 60, 7), "a turret is immune")
			end
			local h = EnemySim.spawn(sim2, "BruteBot", -60, 3, 0, 5) :: any
			EnemySim.hold(sim2, h.id, 9)
			check(not EnemySim.launch(sim2, h.id, 1, 0, 40, 4, 60, 7), "a held robot is not launched")
			local x = h.x
			fly(sim2, 0.5)
			check(h.x == x, "a held robot does not think or walk")
		end
	)

	test("PT combat: the server source launches by kind, through walls, within the caps", function()
		local cs = fs.readFile("src/server/Services/CombatService.luau")
		check(
			string.find(cs, "KnockRules.plan(C.knock, KnockRules.kind(C.knock, eff)", 1, true) ~= nil,
			"by kind"
		)
		check(string.find(cs, "EnemyService.launch(", 1, true) ~= nil, "robots launch")
		check(string.find(cs, "KnockRules.pvp(", 1, true) ~= nil, "PvP compressed")
		local is = fs.readFile("src/server/Services/ImpactService.luau")
		check(string.find(is, "EnemyService.launchWall = launchWall", 1, true) ~= nil, "walls asked")
		local n = 0
		for _ in string.gmatch(is, "ImpactRules%.allow%(") do
			n += 1
		end
		check(n >= 5, "every break (ram, throw, robot, launch, swing, drop) is capped by the ledger")
	end)

	---------------------------------------------------------------------------
	-- Lock-on
	---------------------------------------------------------------------------

	local CAM = { x = 0, y = 5, z = 10, lx = 0, ly = 0, lz = -1 }
	local HERO = { x = 0, y = 5, z = 0 }

	test("PT combat: lock-on picks the best target in front within range", function()
		local cands = {
			{ id = 1, x = 0, y = 5, z = 20 }, -- behind the camera
			{ id = 2, x = 25, y = 5, z = -30 }, -- in front, off to the side (32 degrees)
			{ id = 3, x = 1, y = 5, z = -40 }, -- in front, near the centre
			{ id = 4, x = 0, y = 5, z = -400 }, -- too far
		}
		local i = LockRules.pick(cands, CAM, HERO, LK.hard.range, LK.hard.angle)
		check(i ~= nil and cands[i].id == 3, "the central one")
		check(LockRules.pick({ cands[1], cands[4] }, CAM, HERO, LK.hard.range, LK.hard.angle) == nil, "none")
		-- the soft lock's narrower cone leaves the side one out
		local s = LockRules.pick({ cands[2] }, CAM, HERO, LK.soft.range, LK.soft.angle)
		check(s == nil, "the soft lock only takes what is near the aim")
		-- a boss counts by its size from further
		local boss = { id = -1, x = 0, y = 30, z = -(LK.hard.range + 20), size = 60 }
		check(
			LockRules.pick({ boss }, CAM, HERO, LK.hard.range, LK.hard.angle) == 1,
			"a big boss reaches further"
		)
	end)

	test("PT combat: Tab and the stick flick cycle right and left and wrap round", function()
		local cands = {
			{ id = 10, x = -20, y = 5, z = -30 },
			{ id = 11, x = 0, y = 5, z = -30 },
			{ id = 12, x = 20, y = 5, z = -30 },
		}
		local function nextOf(cur: number, dir: number): number?
			local i = LockRules.cycle(cands, cur, CAM, dir, HERO, LK.hard.range, LK.hard.cycleAngle)
			return i and cands[i].id
		end
		check(nextOf(11, 1) == 12, "right of the middle")
		check(nextOf(11, -1) == 10, "left of the middle")
		check(nextOf(12, 1) == 10, "wraps round to the far left")
		check(nextOf(10, -1) == 12, "and back")
		check(LockRules.keep(LK, 50, 0) and not LockRules.keep(LK, LK.hard.keep + 1, 0), "drops past keep")
		check(not LockRules.keep(LK, 50, LK.hard.lost + 0.1), "drops when hidden too long")
	end)

	test(
		"PT combat: the locked camera frames the target, keeps the hero, pulls back for big targets",
		function()
			local f = LockRules.frame(LK, HERO, { x = 0, y = 5, z = -40 }, 6)
			check(near(f.yaw, 0, 1e-6) and near(f.pitch, 0, 1e-6), "looks straight at a target ahead")
			check(f.pull == 0 and f.shoulder > 0, "no pull for a robot; a shoulder offset")
			check(f.look.z > -40 and f.look.z < 0, "the look point sits between the target and the hero")
			local right = LockRules.frame(LK, HERO, { x = 40, y = 5, z = 0 }, 6)
			check(near(right.yaw, -math.pi / 2, 1e-6), "turns to a target on the right")
			local up = LockRules.frame(LK, HERO, { x = 0, y = 400, z = -5 }, 6)
			check(up.pitch <= math.rad(LK.hard.pitch[2]) + 1e-9, "never tilts past the pitch limit")
			local boss = LockRules.frame(LK, HERO, { x = 0, y = 30, z = -80 }, 60)
			check(boss.pull > 0 and boss.pull <= LK.hard.pullMax, "a boss pulls the camera back")
			-- the soft ease: nothing in the dead zone or while you turn the camera; Camera motion Off removes it
			check(LockRules.softTurn(LK, math.rad(30), 2, 1, 1 / 60) > 0, "eases toward a target to the side")
			check(LockRules.softTurn(LK, math.rad(2), 2, 1, 1 / 60) == 0, "dead zone")
			check(LockRules.softTurn(LK, math.rad(30), 0.1, 1, 1 / 60) == 0, "not while you turn the camera")
			check(LockRules.softTurn(LK, math.rad(30), 2, 0, 1 / 60) == 0, "Camera motion Off")
			check(LockRules.softTurn(LK, -math.rad(30), 2, 1, 1 / 60) < 0, "either way")
		end
	)

	test("PT combat: the comic marker: four corner brackets, a diamond only on the hard lock", function()
		local soft = LockRules.marker(LK.marker, 64, 0, false)
		local hard = LockRules.marker(LK.marker, 64, 0.3, true)
		check(#soft.bars == 8 and #hard.bars == 8, "two arms a corner")
		check(soft.diamond == nil and hard.diamond ~= nil, "the diamond marks the hard lock")
		for _, b in soft.bars do
			check(math.abs(b.x) <= 40 and math.abs(b.y) <= 40, "the brackets sit round the target")
		end
	end)

	test("PT combat: lock-on settings, both on by default, keys appended inside Settings.Set", function()
		local idx: { [string]: number } = {}
		for i, k in Config.Settings.keys do
			idx[k.id] = i
		end
		check(idx.softLock == 14 and idx.hardLock == 15, "appended after Camera motion")
		check(#Config.Settings.keys <= 64, "inside Settings.Set's range")
		local d = SettingsRules.defaults(Config)
		check(d.softLock == 1 and d.hardLock == 1, "both on (nate: both)")
		local sc = fs.readFile("src/client/Controllers/SettingsClient.luau")
		check(
			string.find(sc, "LockClient.softOn", 1, true) and string.find(sc, "LockClient.hardOn", 1, true),
			"applied"
		)
		-- the LOCK button's slot is a real cluster slot (the phone checks place it, size it, keep it apart)
		local slot = TouchLayout.SLOTS.Lock
		check(slot ~= nil and not slot.optional, "LOCK has its own slot")
		local l, t, r, b = TouchLayout.extent({ Block = true })
		local s2 = TouchLayout.SLOTS
		check(slot.x - slot.d / 2 >= l and slot.y - slot.d / 2 >= t and slot.x + slot.d / 2 <= r, "inside")
		check(slot.y + slot.d / 2 <= b and s2.Fly ~= nil, "inside the cluster's extent, nothing else moves")
	end)

	---------------------------------------------------------------------------
	-- Omnidirectional movement
	---------------------------------------------------------------------------

	test("PT combat: the stick moves relative to the camera in every direction", function()
		-- camera looking along -Z, right +X, pitched down 30 degrees
		local p = math.rad(-30)
		local lx, ly, lz = 0, math.sin(p), -math.cos(p)
		local fx, fz, ax, ay, az = MoveMath.omniWish(1, 0, lx, ly, lz, 1, 0)
		check(
			near(fx, 1) and near(fz, 0) and near(ax, 1) and near(ay, 0),
			"strafe right is the camera's right"
		)
		fx, fz, ax, ay, az = MoveMath.omniWish(0, 1, lx, ly, lz, 1, 0)
		check(near(fx, 0) and near(fz, 1), "backpedal: straight back on the ground")
		check(ay > 0 and az > 0, "and back up the camera's pitch in the air")
		fx, fz, ax, ay, az = MoveMath.omniWish(0, -1, lx, ly, lz, 1, 0)
		check(ay < 0 and near(math.sqrt(ax * ax + ay * ay + az * az), 1), "forward dives along the look")
		fx, fz = MoveMath.omniWish(1, -1, lx, ly, lz, 1, 0)
		check(near(math.sqrt(fx * fx + fz * fz), 1), "never longer than 1")
	end)

	test("PT combat: omni flight strafes and backpedals without turning round, inside the caps", function()
		-- flying forward at cruise, then the stick pulls straight back
		local vx, vy, vz = 0, 0, -M.flight.cruise
		local input =
			{ wishX = 0, wishY = 0, wishZ = 1, vertical = 0, boost = false, omni = true, forward = -1 }
		local sideMax = 0
		local top = 0
		for _ = 1, 120 do
			vx, vy, vz = MoveMath.flightStep(M, vx, vy, vz, 100, 100, input, 1 / 60)
			sideMax = math.max(sideMax, math.abs(vx))
			top = math.max(top, math.sqrt(vx * vx + vy * vy + vz * vz))
		end
		check(sideMax < 1e-6, "no swing round: straight back through a stop")
		check(vz > M.flight.cruise * 0.9, string.format("flying backwards at cruise after 2 s (%.1f)", vz))
		check(top <= M.flight.cruise + 1e-6, "never over cruise without boost")
		-- the old turn: the same pull without omni swings round sideways
		local ox, oz = 0, -M.flight.cruise
		local swing = 0
		for _ = 1, 30 do
			local x, _, z = MoveMath.flightStep(M, ox, 0, oz, 100, 100, {
				wishX = 0.01,
				wishY = 0,
				wishZ = 1,
				vertical = 0,
				boost = false,
			}, 1 / 60)
			ox, oz = x, z
			swing = math.max(swing, math.abs(ox))
		end
		check(swing > 5, "without omni it turns round (the old flight)")
		-- strafing in the air, and up and down
		local sx, sy, sz = 0, 0, 0
		for _ = 1, 90 do
			sx, sy, sz = MoveMath.flightStep(M, sx, sy, sz, 100, 100, {
				wishX = 1,
				wishY = 0,
				wishZ = 0,
				vertical = 1,
				boost = false,
				omni = true,
				forward = 0,
			}, 1 / 60)
		end
		check(sx > M.flight.cruise * 0.9 and near(sz, 0, 1e-6) and sy > 0, "strafes and climbs")
		-- boosting along the look keeps the swoop; the total never passes boost speed
		local bx, by, bz = 0, 0, -M.flight.cruise
		for _ = 1, 120 do
			bx, by, bz = MoveMath.flightStep(M, bx, by, bz, 100, 100, {
				wishX = 0,
				wishY = 0,
				wishZ = -1,
				vertical = 0,
				boost = true,
				omni = true,
				forward = 1,
			}, 1 / 60)
			check(math.sqrt(bx * bx + by * by + bz * bz) <= M.flight.boost + 1e-6, "inside the boost cap")
		end
		check(-bz > M.flight.cruise, "the boost builds speed")
		-- the server's cap holds every omni flight speed
		check(M.caps.flight >= M.flight.boost and M.caps.cruise >= M.flight.cruise, "MoveCheck caps cover it")
	end)

	test(
		"PT combat: omni glide drifts any way; swimming follows the camera's pitch inside the cap",
		function()
			local gx, gy, gz = 0, -12, -50
			for _ = 1, 180 do
				gx, gy, gz = MoveMath.glideStep(M, gx, gy, gz, 1, 0, 1 / 60, true)
			end
			check(gx > 40 and math.abs(gz) < 5, "the glide drifts sideways without turning")
			check(math.sqrt(gx * gx + gy * gy + gz * gz) <= M.glide.cap + 1e-6, "inside the glide cap")
			local speed = M.mobility.flight.swim
			local up = MoveMath.swimVertical(M, 1, 1, speed)
			check(up > 0 and up <= speed * M.omni.swimVertical + 1e-9, "swims up, capped")
			check(MoveMath.swimVertical(M, -0.5, 0, speed) < 0, "looking down swims down")
			local total = math.sqrt(speed * speed + up * up)
			check(
				total <= M.caps.cruise * M.tolerance,
				"a 3D swim stays inside the server's flight cruise cap"
			)
		end
	)

	test(
		"PT combat: the body faces the camera or the lock while strafing, its travel when flying fast",
		function()
			local fx, fz = MoveMath.omniFace(M, 0, -1, 40, 0)
			check(near(fx, 0) and near(fz, -1), "strafing: faces the camera's look")
			fx, fz = MoveMath.omniFace(M, 0, -1, 0, -M.flight.cruise)
			check(near(fz, -1), "fast forward: faces the travel")
			fx, fz = MoveMath.omniFace(M, 0, -1, 40, 0, 10, 0)
			check(near(fx, 1) and near(fz, 0), "locked: faces the target")
			local pitch, roll = MoveMath.omniLean(M, 0, -1, 0, -M.flight.cruise)
			check(pitch < 0 and near(roll, 0), "leans forward into a forward flight")
			pitch = MoveMath.omniLean(M, 0, -1, 0, M.flight.cruise)
			check(pitch > 0, "leans back flying backwards")
			local _, r2 = MoveMath.omniLean(M, 0, -1, M.flight.cruise, 0)
			check(r2 ~= 0, "rolls into a strafe")
			local mc = fs.readFile("src/client/Controllers/MoveController.luau")
			check(string.find(mc, "omni = true", 1, true) ~= nil, "MoveController flies omni")
			check(string.find(mc, "MoveMath.swimVertical", 1, true) ~= nil, "and swims in 3D")
			check(string.find(mc, "MoveController.lockAt", 1, true) ~= nil, "and faces the lock")
		end
	)

	---------------------------------------------------------------------------
	-- The block key
	---------------------------------------------------------------------------

	test("PT combat: Block is Q (Alt was unreliable), no key in the map twice", function()
		local src = fs.readFile("src/client/Controllers/InputController.luau")
		local keys = string.match(src, "local KEYS: [^\n]*\n(.-)\n}") or ""
		local seen: { [string]: string } = {}
		for code, action in string.gmatch(keys, '%[Enum%.KeyCode%.(%w+)%] = "(%w+)"') do
			check(seen[code] == nil, code .. " is mapped once")
			seen[code] = action
		end
		check(seen.Q == "Block", "Q blocks")
		check(seen.LeftAlt == nil and seen.RightAlt == nil, "no Alt")
		check(seen.Z == "Skill1" and seen.F == "Fly" and seen.ButtonL1 == "Block", "Z, F and LB unchanged")
		check(seen.Tab == "LockCycle", "Tab cycles the lock")
		check(seen.ButtonR3 == nil, "R3 is the lock tap and the gadget hold (handled on its own)")
		check(string.find(src, 'Block = "Q"', 1, true) ~= nil, "the key hint says Q")
		check(string.find(src, "MouseButton3", 1, true) ~= nil, "middle mouse toggles the lock")
		local tasks = fs.readFile("notes/Tasks.md")
		check(string.find(tasks, "Hold Alt", 1, true) == nil, "no help text still says Alt")
	end)

	---------------------------------------------------------------------------
	-- Drops and swinging robots (nate, 2026-11-19 13:18Z)
	---------------------------------------------------------------------------

	test(
		"PT combat: a drop from high up smashes the roof, scaled by the fall and checked by the server",
		function()
			local Dp = Config.Combat.drop
			local d0 = ImpactRules.dropDamage(Dp, Dp.minFall - 1)
			local d1, r1 = ImpactRules.dropDamage(Dp, Dp.minFall)
			local d2, r2 = ImpactRules.dropDamage(Dp, Dp.fullFall)
			check(d0 == 0 and d1 > 0 and d2 > d1 and r2 > r1, "nothing below the minimum, more from higher")
			check(ImpactRules.dropOk(Dp, 150, 150, 5) == 150, "a true fall counts")
			check(ImpactRules.dropOk(Dp, 150, 20, 5) == nil, "the server never saw that speed")
			check(ImpactRules.dropOk(Dp, 150, 150, 500) == nil, "too far from where the server has the hero")
			check(
				(ImpactRules.dropOk(Dp, 300, 150, 5) :: number) <= 150 * Dp.slack,
				"never more than the server saw"
			)
			-- falling far enough to reach minFall under the leap gravity is a real height
			check(Dp.minFall ^ 2 / (2 * M.airGravity) > 25, "only a real drop (25+ studs)")
		end
	)

	test("PT combat: grab a stunned robot or a wreck and swing it, then throw it", function()
		local TT = Config.Throw
		local E = Config.Enemies
		check(ThrowMath.canHoldRobot(TT, E.BruteBot, 1), "a stunned Brute can be held")
		check(not ThrowMath.canHoldRobot(TT, E.BruteBot, 0), "not one that is not stunned")
		check(not ThrowMath.canHoldRobot(TT, E.Turret, 1), "not one immune to knockback")
		check(not ThrowMath.canHoldRobot(TT, E.Swarmer, 1), "not the small pack robots")
		for name, row in E do
			if type(row) == "table" and row.miniBoss then
				check(not ThrowMath.canHoldRobot(TT, row, 5), name .. ": never a mini-boss")
			end
		end
		check(
			ThrowMath.swingable(TT, "wreck") and ThrowMath.swingable(TT, "robot"),
			"wrecks and robots swing"
		)
		check(not ThrowMath.swingable(TT, "bench"), "a bench is thrown, not swung")
		check(ThrowMath.swingReady(TT, 0, -10, 0), "the first swing")
		check(not ThrowMath.swingReady(TT, 1, 0, TT.swing.gap * 0.5), "a gap between swings")
		check(not ThrowMath.swingReady(TT, TT.swing.max, -10, 0), "then it must be thrown")
		check(
			KN.kinds.swing.dist > KN.kinds.strike.dist and KN.kinds.thrown.dist > KN.kinds.heavy.dist,
			"big"
		)
		local ts = fs.readFile("src/server/Services/ThrowService.luau")
		check(string.find(ts, "ImpactService.swingWall(", 1, true) ~= nil, "swings break walls (capped)")
		check(string.find(ts, "CombatService.swung(", 1, true) ~= nil, "and hit robots in the arc")
		local R = require("../src/shared/Remotes")
		check(R.WorldSwing and R.WorldGrabRobot and R.ImpactDrop and R.SwingFx, "the remotes")
	end)
end
