-- The far skyline and ground marks (2026-11-21, nate's playtest: "i can see the boss and i can see the park from
-- really far but not the buildings or skyscrapers", "windows should appear from further away", "I'm still not
-- noticing any terrain damage or craters"): Shared.SkylinePlan's stand-ins (Fx.FarSkyline) and the lighter hits'
-- ground marks (Shared.CraterRules marks, CraterService, GroundFx).
-- Called from tests/run.luau:
--   require("./far_craters_test")({ test = test, check = check, Config = Config, world = world, placePath = p })
-- ONLY="Far skyline" or ONLY="Ground marks" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local WorldMap = require("../src/shared/WorldMap")
	local SkylinePlan = require("../src/shared/SkylinePlan")
	local CraterRules = require("../src/shared/CraterRules")
	local ImpactRules = require("../src/shared/ImpactRules")
	local BuildingState = require("../src/shared/BuildingState")
	local EnemySim = require("../src/shared/EnemySim")
	local KnockRules = require("../src/shared/KnockRules")

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function read(path: string): string
		return if fs.isFile(path) then fs.readFile(path) else ""
	end

	local world = T.world or WorldMap.build(Config, 202647)
	local list = SkylinePlan.collect(Config, world)
	local F = Config.City.far

	test("Far skyline: every hub building has a stand-in with its body, and every tower its crown", function()
		local hub, byId = 0, {}
		for _, r in list do
			byId[r.id] = r
		end
		local towers, crowned = 0, 0
		for _, b in world.buildings do
			if b.district ~= "Outskirts" then
				hub += 1
				local r = byId[b.id]
				check(r ~= nil and #r.pieces > 0, "building " .. b.id .. " has far pieces")
				if r and b.crown and b.crown ~= "flat" then
					towers += 1
					for _, p in r.pieces do
						if SkylinePlan.has(p.flags, SkylinePlan.CROWN) then
							crowned += 1
							break
						end
					end
					check(r.peak > r.top, "a crowned tower's peak is over its shaft")
				end
			end
		end
		check(#list == hub, string.format("one stand-in a hub building (%d of %d)", #list, hub))
		check(
			towers > 20 and crowned == towers,
			string.format("every crowned tower (%d) keeps its crown", towers)
		)
		for _, r in list do
			for _, p in r.pieces do
				if p.kit then
					check(
						Config.City.kit.baseMaterial[p.kit] ~= nil,
						"a piece's kit has a base material: " .. p.kit
					)
				end
				check(Config.City.palette[p.color] ~= nil, "a piece's colour is in the palette: " .. p.color)
			end
		end
	end)

	test("Far skyline: the packed list survives JSON and stays small", function()
		local json = serde.encode("json", SkylinePlan.pack(list))
		check(#json < 120000, string.format("SkylineInfo is %d bytes (under 120 KB)", #json))
		local back = SkylinePlan.unpack(serde.decode("json", json))
		check(#back == #list, "every building comes back")
		local same = true
		for i, r in back do
			local o = list[i]
			if r.id ~= o.id or #r.pieces ~= #o.pieces or r.top ~= o.top then
				same = false
			end
			for k, p in r.pieces do
				local q = o.pieces[k]
				if
					p.cx ~= q.cx
					or p.sy ~= q.sy
					or p.color ~= q.color
					or p.kit ~= q.kit
					or p.flags ~= q.flags
				then
					same = false
				end
			end
		end
		check(same, "pieces come back exactly")
		check(#SkylinePlan.unpack({ names = {}, b = { { 1, 2, "x" } } }) == 0, "a malformed row is skipped")
		check(#SkylinePlan.unpack(nil) == 0, "no data: no stand-ins")
	end)

	test("Far skyline: part counts per preset stay inside the budget, phones least", function()
		local counts = {}
		for _, name in Config.Presets.order do
			local far = Config.Presets[name].far
			check(far ~= nil and far.parts > 0, name .. " has a far budget")
			local bands, parts = SkylinePlan.budget(list, far)
			local built, nBands = 0, 0
			for _, r in list do
				for _, o in SkylinePlan.boxes(r, bands[r.id] or 0, r.top, true, F) do
					built += 1
					if o.kind == "band" then
						nBands += 1
					end
				end
			end
			check(built <= far.parts, string.format("%s: %d parts within its cap %d", name, built, far.parts))
			check(
				built == parts,
				string.format("%s: the budget's count is what gets built (%d)", name, parts)
			)
			check(nBands > 0, name .. ": the towers get window bands")
			counts[name] = built
			print(string.format("  [far] %s: %d stand-in parts, %d window bands", name, built, nBands))
		end
		check(counts.low <= counts.medium and counts.medium <= counts.high, "phones draw the fewest")
		check(counts.low <= 1500, "a phone's skyline is at most 1,500 parts")
	end)

	test(
		"Far skyline: a damaged tower is cut to what stands and loses its crown; collapsed ones go",
		function()
			local tower: any = nil
			for _, r in list do
				if r.peak > r.top + 20 and r.top - r.base > 300 then
					tower = r
					break
				end
			end
			check(tower ~= nil, "a crowned tower")
			if not tower then
				return
			end
			local half = tower.base + (tower.top - tower.base) / 2
			local whole = SkylinePlan.boxes(tower, 6, tower.top, true, F)
			local cut = SkylinePlan.boxes(tower, 6, half, false, F)
			local crownWhole, crownCut, over = 0, 0, 0
			for _, o in whole do
				if o.kind == "crown" or o.kind == "glow" then
					crownWhole += 1
				end
			end
			for _, o in cut do
				if o.kind == "crown" or o.kind == "glow" then
					crownCut += 1
				end
				if o.cy + o.sy / 2 > half + 0.01 then
					over += 1
				end
			end
			check(crownWhole > 0 and crownCut == 0, "the crown goes with the top storey")
			check(over == 0, "nothing stands over the standing top")
			check(
				SkylinePlan.shows(false, BuildingState.INTACT)
					and SkylinePlan.shows(false, BuildingState.DAMAGED),
				"shown while the real model is away"
			)
			check(
				not SkylinePlan.shows(true, BuildingState.INTACT),
				"hidden while the real model is streamed in"
			)
			check(
				not SkylinePlan.shows(false, BuildingState.COLLAPSED),
				"a collapsed building's stand-in goes"
			)
		end
	)

	test(
		"Far skyline: the device draws cheap, non-colliding stand-ins and the server publishes them",
		function()
			local fx = read("src/client/Fx/FarSkyline.luau")
			for _, needle in
				{
					"p.CanCollide = false",
					"p.CanQuery = false",
					"p.CanTouch = false",
					"p.CastShadow = false",
					"BuildingFx.present",
					"BuildingFx.standing",
					"BuildingFx.onChange",
					"QualityController.Changed:Connect(rebudget)",
					"RunService.Heartbeat:Wait()",
					"LitPlan.night",
				}
			do
				check(has(fx, needle), "FarSkyline: " .. needle)
			end
			check(has(read("src/client/init.client.luau"), "FarSkyline.init()"), "the client starts it")
			local cb = read("src/server/Services/CityBuilder.luau")
			check(
				has(cb, '"SkylineInfo"') and has(cb, "SkylinePlan.pack(SkylinePlan.collect"),
				"the server publishes it"
			)
			local bf = read("src/client/Fx/BuildingFx.luau")
			check(has(bf, "function BuildingFx.standing") and has(bf, "changed(id)"), "BuildingFx tells it")
			-- lit windows reach further than before (260 / 420 / 700)
			local B = Config.Life.lit.budget
			check(
				B.low.radius > 260 and B.medium.radius > 420 and B.high.radius > 700,
				"lit windows show from further"
			)
			local path = T.placePath
			if path and fs.isFile(path) then
				local roblox = require("@lune/roblox")
				local game = roblox.deserializePlace(fs.readFile(path))
				local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
				check(
					shared ~= nil and shared:FindFirstChild("SkylinePlan") ~= nil,
					"Shared.SkylinePlan is in the place"
				)
			end
		end
	)

	local G = Config.Destruction.ground
	local M = G.marks
	local D = Config.Destruction

	test("Ground marks: ordinary hits mark the ground, sized by damage; craters unchanged", function()
		local r0 = CraterRules.markFor(M, M.minDmg - 1)
		check(r0 == 0, "a hit under minDmg leaves nothing")
		local rb, tb = CraterRules.markFor(M, D.slotStruct.basic)
		check(rb > 0 and tb == CraterRules.TIER.scorch, "a basic hit scorches the ground")
		local rs, ts = CraterRules.markFor(M, D.slotStruct.skill)
		check(rs > rb and ts == CraterRules.TIER.dent, "a skill hit dents it, bigger")
		local car = Config.Throw.weights.heavy.struct
		local rc, tc = CraterRules.markFor(M, car)
		check(rc > rs and tc == CraterRules.TIER.dent, "a thrown car dents the street")
		check(CraterRules.markFor(M, 99999) <= M.radius[2], "capped at the biggest mark")
		check(CraterRules.radiusFor(G, D.slotStruct.skill) == 0, "a skill still never digs a full crater")
		check(CraterRules.radiusFor(G, D.superStruct) > 0, "a super still does")
		check(M.idBase > G.maxLive * 1000, "marks' ids never meet the craters'")
		-- landings: a lighter fall marks, a big one is a drop
		local Dp = Config.Combat.drop
		local md = ImpactRules.markDamage(Dp, Dp.markFall)
		check(md >= M.minDmg, "a landing from markFall marks the ground")
		check(ImpactRules.markDamage(Dp, Dp.markFall - 1) == 0, "a softer landing does not")
		check(ImpactRules.markDamage(Dp, Dp.minFall) == 0, "a drop's own range is the drop's")
		check(ImpactRules.dropOk(Dp, Dp.markFall, Dp.markFall, 1, Dp.markFall) ~= nil, "the server backs it")
		check(
			ImpactRules.dropOk(Dp, Dp.markFall, Dp.markFall, 1) == nil,
			"without the floor a drop still needs minFall"
		)
	end)

	test("Ground marks: caps a second, per cell and in all; a hit in a live mark grows it", function()
		local book = CraterRules.new(M.idBase)
		local made = 0
		for k = 1, 40 do
			if CraterRules.addMark(M, book, k * 100, 0, 0, 700, "part", nil, 0) then
				made += 1
			end
		end
		check(made == M.perSecond, string.format("at most perSecond marks a second (%d)", made))
		check(book.list[1].id == M.idBase, "ids start at idBase")
		check(CraterRules.busy(M, book, 0.5), "busy past the rate: no ray cast")
		check(not CraterRules.busy(M, book, 1.5), "free again a second later")
		book = CraterRules.new(M.idBase)
		local inCell = 0
		for k = 1, 20 do
			if
				CraterRules.addMark(M, book, 2 + (k % 4) * 3, 0, 2 + (k // 4) * 3, 300, "part", nil, k * 2)
			then
				inCell += 1
			end
		end
		check(inCell == M.perCell, "at most perCell in one cell")
		book = CraterRules.new(M.idBase)
		local a = CraterRules.addMark(M, book, 0, 0, 0, 200, "part", nil, 0) :: any
		check(a and a.tier == CraterRules.TIER.scorch, "a scorch")
		local r = a.r
		local g = CraterRules.grow(M, book, 0.3, 0, 900, nil, 5)
		check(
			g == a and a.r > r and a.tier == CraterRules.TIER.dent and a.born == 5,
			"grown into a dent, life anew"
		)
		check(CraterRules.grow(M, book, 0.3, 0, 900, 7, 6) == nil, "another phase's hit never grows it")
		for i = 1, 10 do
			CraterRules.grow(M, book, 0, 0, 1500, nil, 10 + i * 2)
		end
		check(a.r <= M.radius[2], "growing stops at the biggest mark")
		check(#CraterRules.step(M, book, 10 + 20 + M.life) == 1, "it goes after its life")
	end)

	test("Ground marks: Terrain only for open-world dents, never across a crater", function()
		local book = CraterRules.new(M.idBase)
		local d = CraterRules.addMark(M, book, 0, 0, 0, 1400, "terrain", nil, 0) :: any
		check(d and d.ground == "terrain", "a big dent digs the lawn")
		local s = CraterRules.addMark(M, book, 200, 0, 0, 200, "terrain", nil, 0) :: any
		check(s and s.ground == "part", "a scorch never digs")
		local p = CraterRules.addMark(M, book, 400, 0, 0, 1400, "terrain", 3, 0) :: any
		check(p and p.ground == "part" and p.phase == 3, "a private run's dent never touches Terrain")
		check(CraterRules.sees(p, 3) and not CraterRules.sees(p, nil), "only its party sees it")
		check(
			CraterRules.sees(d, nil) and not CraterRules.sees(d, 3),
			"the open world's are the open world's"
		)
		check(
			CraterRules.addMark(M, book, 4, 0, 0, 1400, "terrain", nil, 0) == nil,
			"terrain dents never share voxels"
		)
		check(
			#CraterRules.overlapping(M, book, 3, 0, 8) == 1,
			"a crater over a dent finds it (written back first)"
		)
		-- a dent's bowl is shallow: it carves less than the crater of the same width
		local lo = CraterRules.region(M, d)
		check(lo[2] >= d.y - d.r - M.voxel * 2, "a dent's region stays shallow")
		local cs = read("src/server/Services/CraterService.luau")
		check(
			has(cs, "function CraterService.blast(at: Vector3, radius: number, dmg: number, phase: number?)"),
			"blast"
		)
		check(has(cs, "CraterRules.sees(c, mine)"), "a device's sync list keeps to its phase")
		check(has(cs, "restore(m)"), "dents under a new crater give their voxels back")
	end)

	test("Ground marks: every lighter hit reaches the ground", function()
		local bs = read("src/server/Services/BuildingService.luau")
		check(has(bs, "CraterService.blast(center, radius, dmg, phase)"), "building hits pass the phase")
		check(has(bs, "a basic hit at the ground scorches it"), "basic hits at the ground mark it")
		local cs = read("src/server/Services/CombatService.luau")
		check(
			has(cs, "BuildingService.hit(center, radius, dmg, kind, hero and hero.phase)"),
			"casts pass the hero"
		)
		local is = read("src/server/Services/ImpactService.luau")
		check(has(is, "ImpactRules.markDamage(Dp, speed)"), "lighter landings mark the ground")
		check(has(is, "EnemyService.launchLand = function"), "robots slammed down mark it")
		local mc = read("src/client/Controllers/MoveController.luau")
		check(has(mc, "Dp.markFall"), "the device reports ground landings")
		local gx = read("src/client/Fx/GroundFx.luau")
		check(has(gx, "drawScorch") and has(gx, ".marks or 0"), "devices draw marks under their own budget")
		for _, name in Config.Presets.order do
			local P = Config.Presets[name]
			check(P.marks > 0 and P.marks <= 60 and P.markRim <= 6, name .. " draws a capped number of marks")
		end
		-- a robot launched to the ground tells the server where it landed
		local landed = 0
		local speedAt = 0
		local sim = EnemySim.new(Config, {
			heightAt = function()
				return 0
			end,
			random = function()
				return 0.5
			end,
			landHit = function(_e, _x, y, _z, speed)
				landed += 1
				speedAt = speed
				check(math.abs(y) < 0.01, "at its feet on the ground")
			end,
		})
		local e = EnemySim.spawn(sim, "BruteBot", 0, 3, 0, 5) :: any
		local plan = KnockRules.plan(Config.Combat.knock, "heavy")
		EnemySim.launch(sim, e.id, 1, 0, plan.dist, plan.lift, plan.speed, 7)
		local t = sim.now
		for _ = 1, 120 do
			t += 1 / 30
			EnemySim.step(sim, t, {})
		end
		check(landed == 1, "one landing heard")
		check(speedAt >= M.robot.minSpeed, "a heavy throw lands hard enough to mark")
	end)
end
