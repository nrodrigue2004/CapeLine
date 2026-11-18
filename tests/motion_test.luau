-- The enemy motion pass (quality pass 2026-11-18, nate: "the enemies dont move properly"): robots on foot play
-- Roblox's own R15 idle, walk and run (Shared.LocoMath, Controllers.NpcLoco), blended so the feet keep pace,
-- and the far code walk's stride is matched to the speed too. Own file, so it merges easily.
-- ONLY="Enemy motion" runs just these. Called from tests/run.luau.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local LocoMath = require("../src/shared/LocoMath")
	local RigMath = require("../src/shared/RigMath")
	local C = Config.Enemies.look.loco

	local function near(a: number, b: number, tol: number): boolean
		return math.abs(a - b) <= tol
	end

	test("Enemy motion: Roblox's own idle, walk and run clips, the standard leg", function()
		check(C.on == true, "on")
		for _, k in { "idle", "walk", "run" } do
			check(type(C[k]) == "string" and C[k]:match("^rbxassetid://%d+$") ~= nil, k .. " is an asset id")
		end
		local hero = RigMath.layout(Config.HeroRig, nil, 1)
		check(
			near(hero.ground - hero.hip, C.refLeg, 0.01),
			"refLeg is the hero rig's leg (Roblox's HipHeight 2)"
		)
		check(C.still < C.walkAt and C.walkAt < C.runAt, "still < walk < run")
		for _, name in Config.Presets.order do
			local n = Config.Presets[name].enemyAnimNear
			check(type(n) == "number" and n > 0, name .. " has enemyAnimNear")
		end
	end)

	test("Enemy motion: the blend stands still, walks, crossfades and runs, weights summing to 1", function()
		local last = -1
		for sp = 0, 60, 0.5 do
			local b = LocoMath.blend(sp, 1, C)
			check(near(b.idle + b.walk + b.run, 1, 1e-6), "weights sum to 1 at " .. sp)
			local moving = b.walk + b.run
			check(moving >= last - 1e-6 or sp < C.still, "never less walking as it speeds up at " .. sp)
			last = moving
		end
		check(LocoMath.blend(0, 1, C).idle == 1, "standing: idle")
		check(LocoMath.blend(5, 1, C).walk == 1, "5 studs/s: walk")
		check(LocoMath.blend(20, 1, C).run == 1, "20 studs/s: run")
		local mid = LocoMath.blend((C.walkAt + C.runAt) / 2, 1, C)
		check(near(mid.walk, 0.5, 1e-6) and near(mid.run, 0.5, 1e-6), "half way: half and half")
	end)

	test("Enemy motion: the feet keep pace with the ground for every robot on foot", function()
		local BodyShape = require("../src/shared/BodyShape")
		local builds = Config.Enemies.look.builds
		local n = 0
		for _, kind in Config.Enemies.order do
			local cfg = Config.Enemies[kind]
			if
				cfg.ai ~= "flyer"
				and cfg.ai ~= "sentry"
				and cfg.speed > 0
				and cfg.body
				and cfg.body.height
			then
				local factors =
					BodyShape.factors(Config, { gender = 1, build = builds[cfg.body.build] or 2, height = 3 })
				local base = RigMath.layout(Config.HeroRig, factors, 1)
				local lay = RigMath.layout(Config.HeroRig, factors, cfg.body.height / base.height)
				local hs = LocoMath.heightScale(lay.ground, lay.hip, C)
				for _, frac in { 0.5, 1 } do
					local sp = cfg.speed * frac
					local b = LocoMath.blend(sp, hs, C)
					local covered = LocoMath.covered(b, hs, C)
					-- within 10% unless the run is capped (then the clip runs at its fastest)
					local capped = b.run == 1 and b.runSpeed >= C.maxWarp - 1e-6
					check(
						capped or near(covered, sp, sp * 0.1 + 0.05),
						kind .. " at " .. sp .. " studs/s: feet cover " .. string.format("%.1f", covered)
					)
				end
				n += 1
			end
		end
		check(n >= 10, "checked the robots on foot (" .. n .. ")")
	end)

	test("Enemy motion: the far code walk's stride keeps pace and never blurs", function()
		local leg, swing = 2, math.rad(40)
		local rate = LocoMath.phaseRate(14, leg, swing)
		local step = 2 * leg * math.sin(swing)
		check(near(rate / (2 * math.pi) * 2 * step, 14, 0.01), "two steps a cycle cover the speed")
		check(LocoMath.phaseRate(0, leg, swing) == 0, "standing: no stride")
		check(LocoMath.phaseRate(200, 0.5, math.rad(5)) <= 26, "capped")
	end)

	test("Enemy motion: the renderer walks on foot robots with NpcLoco after the Animator", function()
		local src = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
		check(src:find("NpcLoco.drive", 1, true) ~= nil, "drives the walk")
		check(src:find("NpcLoco.stop", 1, true) ~= nil, "stops it for code poses and the pool")
		check(src:find("RunService.PreSimulation:Connect", 1, true) ~= nil, "poses after the Animator")
		check(src:find("RunService.RenderStepped:Connect", 1, true) == nil, "not before it")
		check(src:find("LocoMath.phaseRate", 1, true) ~= nil, "the far walk's stride matches the speed")
		local rig = fs.readFile("src/shared/NpcRig.luau")
		check(rig:find("function NpcRig.over", 1, true) ~= nil, "NpcRig.over")
		check(rig:find("function NpcRig.animBase", 1, true) ~= nil, "NpcRig.animBase")
		check(
			rig:find('Instance.new("AnimationController")', 1, true) ~= nil,
			"every rig has an AnimationController"
		)
	end)
end
