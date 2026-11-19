-- fix-carry (nate after gaps7, 2026-11-19: "when i pickup cars or items or whatever i should actually hold them.
-- Unless i have powers like telekinesis then i could make them float"): Shared.CarryPose's holds checked on the
-- game's own body (Config.HeroRig, the joints HeroBody builds) posed the way HeroAnimator poses it: the held
-- thing's world position against the hands across a walk, a flight and a swing, for holding and for the
-- telekinesis float, plus the runtime wiring read from the source and the built place.
-- Called from tests/run.luau; ONLY="Carry" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local CarryPose = require("../src/shared/CarryPose")
	local HeroAnim = require("../src/shared/HeroAnim")
	local TT = Config.Throw
	local body = CarryPose.bodyFromRig(Config.HeroRig)
	local CP = CarryPose

	-- quaternion slerp of two { p, r } frames (CFrame:Lerp, as HeroAnimator blends)
	local function quat(r: { { number } }): { number }
		local tr = r[1][1] + r[2][2] + r[3][3]
		local w, x, y, z
		if tr > 0 then
			local s = math.sqrt(tr + 1) * 2
			w, x, y, z = s / 4, (r[3][2] - r[2][3]) / s, (r[1][3] - r[3][1]) / s, (r[2][1] - r[1][2]) / s
		elseif r[1][1] > r[2][2] and r[1][1] > r[3][3] then
			local s = math.sqrt(1 + r[1][1] - r[2][2] - r[3][3]) * 2
			w, x, y, z = (r[3][2] - r[2][3]) / s, s / 4, (r[1][2] + r[2][1]) / s, (r[1][3] + r[3][1]) / s
		elseif r[2][2] > r[3][3] then
			local s = math.sqrt(1 + r[2][2] - r[1][1] - r[3][3]) * 2
			w, x, y, z = (r[1][3] - r[3][1]) / s, (r[1][2] + r[2][1]) / s, s / 4, (r[2][3] + r[3][2]) / s
		else
			local s = math.sqrt(1 + r[3][3] - r[1][1] - r[2][2]) * 2
			w, x, y, z = (r[2][1] - r[1][2]) / s, (r[1][3] + r[3][1]) / s, (r[2][3] + r[3][2]) / s, s / 4
		end
		return { w, x, y, z }
	end
	local function mat(q: { number }): { { number } }
		local w, x, y, z = q[1], q[2], q[3], q[4]
		return {
			{ 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w) },
			{ 2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w) },
			{ 2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y) },
		}
	end
	local function lerp(a: CarryPose.CF, b: CarryPose.CF, f: number): CarryPose.CF
		local qa, qb = quat(a.r), quat(b.r)
		local d = qa[1] * qb[1] + qa[2] * qb[2] + qa[3] * qb[3] + qa[4] * qb[4]
		if d < 0 then
			qb, d = { -qb[1], -qb[2], -qb[3], -qb[4] }, -d
		end
		local q
		if d > 0.9995 then
			q = {}
			for i = 1, 4 do
				q[i] = qa[i] + (qb[i] - qa[i]) * f
			end
		else
			local th = math.acos(d)
			local sa, sb = math.sin((1 - f) * th) / math.sin(th), math.sin(f * th) / math.sin(th)
			q = {}
			for i = 1, 4 do
				q[i] = qa[i] * sa + qb[i] * sb
			end
		end
		local n = math.sqrt(q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2)
		for i = 1, 4 do
			q[i] /= n
		end
		local p = {}
		for i = 1, 3 do
			p[i] = a.p[i] + (b.p[i] - a.p[i]) * f
		end
		return { p = p, r = mat(q) }
	end

	-- the parts posed as HeroAnimator layers them: the mode pose (or the Animator's walk), the held state pose at
	-- full weight, then an action over it at its weight (a flight's upper-body layer keeps the Root's pitch)
	local function walkBase(t: number): { [string]: { number } }
		local s = math.sin(t * 8)
		return {
			RightShoulder = { 40 * s, 0, 0, 0 },
			LeftShoulder = { -40 * s, 0, 0, 0 },
			RightHip = { -40 * s, 0, 0, 0 },
			LeftHip = { 40 * s, 0, 0, 0 },
			Root = { 0, 0, 0, math.abs(s) * 0.15 },
		}
	end
	local function posed(
		scene: string,
		state: string,
		t: number,
		action: string?,
		at: number?
	): { [string]: CarryPose.CF }
		local base = if scene == "fly" then HeroAnim.sample("fly", t) else walkBase(t)
		local st = HeroAnim.sample(state, t)
		local act = if action then HeroAnim.sample(action, at or 0) else nil
		local w = if action then HeroAnim.actionWeight(at or 0, HeroAnim.CLIPS[action].dur) else 0
		local frames: { [string]: CarryPose.CF } = {}
		local names = {}
		for n in base do
			names[n] = true
		end
		for n in st do
			names[n] = true
		end
		for n in act or {} do
			names[n] = true
		end
		for n in names do
			local out = CP.key(base[n])
			if st[n] then
				out = CP.key(st[n])
			end
			if act and act[n] and not (scene == "fly" and HeroAnim.LEGS[n]) then
				local a = act[n]
				if scene == "fly" and n == "Root" then
					a = HeroAnim.upperRoot(a)
				end
				out = lerp(out, CP.key(a), w)
			end
			frames[n] = out
		end
		-- parts from the blended joint frames
		local P: { [string]: CarryPose.CF } = { HumanoidRootPart = CP.cf(0, 0, 0) }
		for _, j in body.joints do
			local parent = P[j.part0]
			P[j.part1] = CP.mul(CP.mul(CP.mul(parent, j.c0), frames[j.name] or CP.cf(0, 0, 0)), CP.inv(j.c1))
		end
		return P
	end

	-- where the held box is now, as on a device: welded to its part (the hold), following the right hand at the
	-- action's weight through the lift and the swings (ThrowClient boxNow)
	local function boxAt(
		P: { [string]: CarryPose.CF },
		h: CarryPose.Hold,
		action: string?,
		at: number?
	): CarryPose.CF
		local part = P[h.part]
		local inPart = h.c0
		if action and CP.FOLLOW[action] then
			local w = HeroAnim.actionWeight(at or 0, HeroAnim.CLIPS[action].dur)
			inPart = lerp(h.c0, CP.mul(CP.mul(CP.inv(part), P.RightHand), h.hand), w)
		end
		return CP.mul(part, inPart)
	end

	local SCENES = { "walk", "fly" }
	local props = {
		{ "car", { 5, 4, 12 }, true },
		{ "truck", { 6, 6, 16 }, true },
		{ "dumpster", { 6, 4, 3.5 } },
		{ "vending", { 3, 6, 2.4 } },
		{ "slab", { 8, 2.4, 6 } },
		{ "bench", { 5, 2.6, 1.8 } },
		{ "trashCan", { 2, 3, 2 } },
		{ "mailbox", { 1.8, 3.6, 1.6 } },
		{ "sign", { 2.4, 5, 0.4 } },
		{ "lampPost", { 0.8, 10, 0.8 } },
	}

	test("Carry: the grips (held by default; Gravity and Mind heroes float)", function()
		check(CP.gripOf(TT, "car", "Titan") == "overhead", "a car overhead")
		check(CP.gripOf(TT, "robot", "Blade") == "overhead", "a robot overhead")
		check(CP.gripOf(TT, "dumpster", "Fire") == "overhead", "a crate overhead")
		check(CP.gripOf(TT, "bench", "Fire") == "hand", "a bench in one hand")
		check(CP.gripOf(TT, "lampPost", "Fire") == "pole", "a lamp post gripped")
		for _, set in { "Pulse", "Mind" } do
			check(CP.gripOf(TT, "car", set) == "mind", set .. " floats a car")
			check(CP.gripOf(TT, "robot", set) == "mind", set .. " floats a robot")
		end
		for _, set in { "Spirit", "Light", "Titan", "Volt", "Shadow" } do
			check(CP.gripOf(TT, "car", set) ~= "mind", set .. " holds it")
		end
		for g, clip in CP.CLIP do
			check(
				HeroAnim.CLIPS[clip] ~= nil and HeroAnim.CLIPS[clip].loop == true,
				g .. ": its hold pose loops"
			)
		end
		local src = fs.readFile("src/client/Controllers/HeroAnimator.luau")
		check(string.find(src, "CARRY_CLIP[grip", 1, true) ~= nil, "HeroAnimator picks the hold pose by grip")
	end)

	test("Carry: the old ride floated over the hands (the bug)", function()
		local P = CP.parts(body, HeroAnim.sample("carry", 0))
		local tip = CP.tip(body, P, "Right")
		check(
			TT.overhead - tip[2] > 1.5,
			string.format("old gap %.2f studs between fists and the thing", TT.overhead - tip[2])
		)
	end)

	test("Carry: held overhead, on the fists, across a walk, a flight and a swing", function()
		local worst, worstOut = 0, -math.huge
		local cases = {}
		for _, pr in props do
			if CP.gripOf(TT, pr[1], "Titan") == "overhead" then
				table.insert(cases, { pr[1], pr[2], false, pr[3] })
			end
		end
		table.insert(cases, { "robot", CP.robotSize(5.25), true })
		table.insert(cases, { "big robot", CP.robotSize(8), true })
		for _, c in cases do
			local h = CP.hold(TT, body, "overhead", HeroAnim.sample("carry", 0), c[2], c[3], c[4])
			check(h.part == "UpperTorso", c[1] .. ": welded to the upper torso")
			for _, scene in SCENES do
				for i = 0, 40 do
					local t = i * 0.05
					local P = posed(scene, "carry", t)
					local box = boxAt(P, h)
					for _, side in { "Right", "Left" } do
						local gap, out = CP.under(box, h, CP.tip(body, P, side))
						worst = math.max(worst, math.abs(gap))
						worstOut = math.max(worstOut, out)
						check(
							gap >= -0.2 and gap <= 0.3,
							string.format("%s %s %s fist under it (gap %.2f)", c[1], scene, side, gap)
						)
						check(
							out <= 0,
							string.format("%s %s %s fist inside its footprint (%.2f)", c[1], scene, side, out)
						)
					end
					-- never through the head
					local head = P.Head
					local hs = body.sizes.Head
					local gap = CP.under(box, h, CP.point(head, { 0, hs[2] / 2, 0 }))
					check(gap >= -0.05, string.format("%s %s clear of the head (%.2f)", c[1], scene, gap))
				end
			end
		end
		print(
			string.format(
				"    overhead: fists within %.2f studs of the underside, %.2f inside the edge",
				worst,
				-worstOut
			)
		)
		-- a swing: the thing follows the right hand through the clip; at full weight it keeps the hold's offset
		local h = CP.hold(TT, body, "overhead", HeroAnim.sample("carry", 0), CP.robotSize(5.25), true)
		for _, clip in { "robotSwing", "robotSwingBack", "robotSlam", "lift" } do
			local dur = HeroAnim.CLIPS[clip].dur
			local maxLeft = 0
			for i = 0, 30 do
				local at = dur * i / 30
				local P = posed("walk", "carry", 0, clip, at)
				local box = boxAt(P, h, clip, at)
				local w = HeroAnim.actionWeight(at, dur)
				if w >= 0.999 then
					local want = CP.mul(P.RightHand, h.hand)
					local d = 0
					for k = 1, 3 do
						d = math.max(d, math.abs(want.p[k] - box.p[k]))
					end
					check(d < 1e-6, clip .. ": in the right hand at full weight")
				end
				local l = CP.tip(body, P, "Left")
				local q = CP.point(CP.inv(box), l)
				local dx =
					math.max(0, math.abs(q[1]) - h.size[1] / 2 - 0.5, math.abs(q[3]) - h.size[3] / 2 - 0.5)
				maxLeft = math.max(maxLeft, dx)
			end
			print(
				string.format(
					"    %s: the left fist strays at most %.2f studs past the robot's sides",
					clip,
					maxLeft
				)
			)
		end
	end)

	test("Carry: small things up on the right fist, poles gripped", function()
		for _, pr in props do
			local grip = CP.gripOf(TT, pr[1], "Titan")
			if grip == "hand" or grip == "pole" then
				local h = CP.hold(TT, body, grip, HeroAnim.sample("carryHand", 0), pr[2])
				check(h.part == "RightHand", pr[1] .. ": welded to the right hand")
				for _, scene in SCENES do
					for i = 0, 40 do
						local P = posed(scene, "carryHand", i * 0.05)
						local box = boxAt(P, h)
						local rh = P.RightHand
						if grip == "hand" then
							local gap, out = CP.under(box, h, CP.tip(body, P, "Right"))
							check(
								math.abs(gap - -TT.hold.palm) < 1e-6 or math.abs(gap) < 0.1,
								pr[1] .. " " .. scene .. ": on the fist"
							)
							check(out <= 0, pr[1] .. " " .. scene .. ": over the fist")
						else
							local q = CP.point(CP.inv(box), rh.p)
							check(
								math.abs(q[1]) <= h.size[1] / 2 + 0.5
									and math.abs(q[3]) <= h.size[3] / 2 + 0.5,
								pr[1] .. " " .. scene .. ": the fist round the pole"
							)
						end
						-- the head stays out of it
						local hp = P.Head.p
						local q = CP.point(CP.inv(box), hp)
						local inside = math.abs(q[1]) < h.size[1] / 2 + 0.3
							and math.abs(q[2]) < h.size[2] / 2 + 0.3
							and math.abs(q[3]) < h.size[3] / 2 + 0.3
						check(not inside, pr[1] .. " " .. scene .. ": clear of the head")
					end
				end
			end
		end
	end)

	test(
		"Carry: telekinesis floats it over (or beside) the hero, hands raised, across a walk, a flight and a swing",
		function()
			local M = TT.mind
			local cases = {}
			for _, pr in props do
				table.insert(cases, { pr[1], pr[2], false })
			end
			table.insert(cases, { "robot", CP.robotSize(5.25), true })
			for _, c in cases do
				local h = CP.hold(TT, body, "mind", HeroAnim.sample("carryMind", 0), c[2], c[3])
				check(h.part == "HumanoidRootPart", c[1] .. ": floated from the root")
				for _, scene in SCENES do
					for i = 0, 40 do
						local t = i * 0.05
						local P = posed(scene, "carryMind", t)
						local bob = math.sin(t * M.bobRate) * M.bob
						local box = CP.mul(P.HumanoidRootPart, CP.mul(CP.cf(0, bob, 0), h.c0))
						-- nothing of the hero inside it: the body's parts' middles are all outside the box plus a margin
						for name, part in P do
							local q = CP.point(CP.inv(box), part.p)
							local s = body.sizes[name] or { 1, 1, 1 }
							local m = math.max(s[1], s[2], s[3]) / 2
							local inside = math.abs(q[1]) < h.size[1] / 2 + m
								and math.abs(q[2]) < h.size[2] / 2 + m
								and math.abs(q[3]) < h.size[3] / 2 + m
							check(
								not inside,
								string.format("%s %s: floats clear of the %s", c[1], scene, name)
							)
						end
						local sh = CP.point(P.UpperTorso, { 0, 0.56, 0 })
						for _, side in { "Right", "Left" } do
							check(
								CP.tip(body, P, side)[2] > sh[2] + 0.8,
								c[1] .. " " .. scene .. ": hands raised"
							)
						end
					end
				end
				-- the swing's whirl stays out of the hero
				for i = 0, 10 do
					local v = CP.whirl(TT, 0, i / 10)
					check(
						math.sqrt(v[1] ^ 2 + v[3] ^ 2) >= math.min(h.size[1], h.size[3]) / 2 + 1,
						c[1] .. ": whirls clear"
					)
				end
			end
		end
	)

	test("Carry: no lag: the hold is the hands' own frame, wherever the hero goes", function()
		-- a hero flying at 80 studs/s, turning: the box's world position is the root's world frame times the same
		-- posed chain, so its offset from the fists never changes with speed (the old held robot trailed by the
		-- renderer's interpolation delay times the speed)
		local h = CP.hold(TT, body, "overhead", HeroAnim.sample("carry", 0), { 5, 4, 12 }, false, true)
		local spread = 0
		local first: { number }? = nil
		for i = 0, 60 do
			local t = i / 60
			local root = CP.cf(80 * t, 40 + 10 * t, -30 * t, CP.angles(0, 90 * t, 0))
			local P = posed("fly", "carry", 0)
			local wb = CP.mul(root, boxAt(P, h))
			local tip = CP.point(root, CP.tip(body, P, "Right"))
			local rel = CP.point(CP.inv(wb), tip)
			if first then
				for k = 1, 3 do
					spread = math.max(spread, math.abs(rel[k] - first[k]))
				end
			else
				first = rel
			end
		end
		check(spread < 1e-6, string.format("the fist's spot under it is fixed in flight (%.6f)", spread))
		local er = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
		local delay = tonumber(string.match(er, "local DELAY = ([%d%.]+)")) or 0
		local lag = 80 * delay
		check(lag > 5, string.format("the old robot hold trailed about %.1f studs at 80 studs/s", lag))
	end)

	test("Carry: the runtime path (server welds, every device draws, robots in the hands)", function()
		local ts = fs.readFile("src/server/Services/ThrowService.luau")
		for _, s in
			{
				'weld.Name = "CarryWeld"',
				"RigJoints.of(char)",
				"CarryPose.hold(",
				'SetAttribute("CarryBase"',
				'SetAttribute("CarryHand"',
				'SetAttribute("CarryOffset"',
				'SetAttribute("CarryGrip"',
				'SetAttribute("CarryRobot"',
				"glow(it, hero)",
			}
		do
			check(string.find(ts, s, 1, true) ~= nil, "ThrowService: " .. s)
		end
		local tc = fs.readFile("src/client/Controllers/ThrowClient.luau")
		check(
			string.find(tc, "EnemyRenderer.heldAt = robotAt", 1, true) ~= nil,
			"ThrowClient draws held robots"
		)
		check(
			string.find(tc, 'FrameProf.wrap("ThrowHold", holdStep)', 1, true) ~= nil,
			"the prop follow is profiled"
		)
		local er = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
		check(
			string.find(er, 'RunService.PostSimulation:Connect(FrameProf.wrap("EnemyHeld"', 1, true) ~= nil,
			"held robots placed after physics"
		)
		-- the bridge to Roblox's own CFrame (Lune's roblox types): the same component order, the same angles and
		-- the same joint sum as the engine's (parent * C0 * Transform * C1:Inverse())
		do
			local roblox = require("@lune/roblox") :: any
			local RC = roblox.CFrame
			local a =
				CP.mul(CP.cf(1, 2, 3, CP.angles(30, -50, 70)), CP.cf(-0.5, 0.25, 4, CP.angles(-10, 80, 5)))
			local ra = RC.new(1, 2, 3)
				* RC.Angles(math.rad(30), math.rad(-50), math.rad(70))
				* RC.new(-0.5, 0.25, 4)
				* RC.Angles(math.rad(-10), math.rad(80), math.rad(5))
			local got = { ra:GetComponents() }
			local want = CP.components(a)
			local d = 0
			for i = 1, 12 do
				d = math.max(d, math.abs(got[i] - want[i]))
			end
			check(d < 1e-5, string.format("CarryPose matches Roblox CFrame maths (%.2e)", d))
			local back = CP.fromComponents({ RC.new(table.unpack(want)):GetComponents() })
			check(
				math.abs(back.p[1] - a.p[1]) < 1e-6 and math.abs(back.r[2][3] - a.r[2][3]) < 1e-6,
				"round trip"
			)
		end
		local placePath = T.placePath
		if placePath then
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(placePath))
			local rs = game:GetService("ReplicatedStorage")
			local shared = rs:FindFirstChild("Shared")
			check(
				shared ~= nil and shared:FindFirstChild("CarryPose") ~= nil,
				"the place has Shared.CarryPose"
			)
			check(shared ~= nil and shared:FindFirstChild("RigJoints") ~= nil, "and Shared.RigJoints")
			local sp = game:GetService("StarterPlayer")
			local ok, v = pcall(function()
				return (sp :: any).AvatarJointUpgrade_Serialized
			end)
			check(not ok or tostring(v) ~= "Enabled", "R15 heroes keep Motor6D joints")
		end
	end)
end
