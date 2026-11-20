-- The living world's round 3, part 2 (alive-world round 2, 2026-11-20): flags at every safehouse pad, cloth banners
-- down Uptown's tall towers, the Docks' crane trolleys at work, kites over the park, and the Alive looks kept out
-- of the street smash. Called from tests/run.luau:
--   require("./alive2_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="Alive" runs these with tests/alive_test.luau.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local LifeKit = require("../src/shared/LifeKit")
	local LifePlan = require("../src/shared/LifePlan")
	local StreetBreak = require("../src/shared/StreetBreak")
	local L = Config.Life
	local BN = L.banners
	local CR = L.cranes
	local KT = Config.Park.life.kite

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- WorldInfo's rows, as CityBuilder.publishInfo writes them
	local function infoSafehouses(): { any }
		local out = {}
		for id, s in world.safehouses do
			table.insert(out, { id = id, name = s.name, x = s.x, y = s.y, z = s.z, district = s.district })
		end
		return out
	end
	local function infoBuildings(): { any }
		local out = {}
		for _, b in world.buildings do
			if b.district ~= "Outskirts" then
				table.insert(out, { b.id, b.x, b.z, b.sx, b.sz, b.base, b.top, if b.round then 1 else 0 })
			end
		end
		return out
	end

	test("Alive2: two flags at the front corners of every safehouse pad", function()
		local safes = infoSafehouses()
		local flags = LifePlan.safeFlags(Config, safes)
		check(#flags == 2 * #safes, "two flags a safehouse (" .. #flags .. " for " .. #safes .. ")")
		local pad = Config.World.safehouse.pad
		for i, f in flags do
			local s = safes[math.floor((i - 1) / 2) + 1]
			check(f.id == nil, "a safehouse flag has no building to fall with")
			check(f.y == s.y, "the pole stands on the pad's top")
			check(math.abs(math.abs(f.x - s.x) - (pad / 2 - BN.safeInset)) < 1e-6, "on a side corner")
			check(
				math.abs(f.z - (s.z + pad / 2 - BN.safeInset)) < 1e-6,
				"at the front (+z, away from the shelter)"
			)
		end
		check(
			has("src/server/Services/CityBuilder.luau", "x = s.x, y = s.y, z = s.z, district = s.district"),
			"WorldInfo sends the safehouses' y"
		)
		check(
			has("src/client/Fx/CityLife.luau", "fl.def.id == nil or BuildingFx.state(fl.def.id) == 0"),
			"a flag with no building always stands"
		)
	end)

	test("Alive2: banners hang in pairs down Uptown's tall towers, outside the wall", function()
		local list = LifePlan.towerBanners(Config, infoBuildings())
		check(#list >= 16 and #list % 2 == 0, "pairs of banners in Uptown (" .. #list .. ")")
		local byId: { [number]: any } = {}
		for _, b in world.buildings do
			byId[b.id] = b
		end
		for _, bn in list do
			local b = byId[bn.id]
			check(b ~= nil, "a banner's tower is a wreckable building (it falls with it)")
			if b then
				check(bn.district == "Uptown" and BN.districts[bn.district], "only Uptown")
				check(b.top - b.base >= BN.minHeight and not b.round, "only tall square towers")
				check(math.abs(bn.nx) + math.abs(bn.nz) == 1, "a face's normal")
				-- out past the wall on its face, within the face's width
				local wall = if bn.nx ~= 0 then b.sx / 2 else b.sz / 2
				local off = (bn.x - b.x) * bn.nx + (bn.z - b.z) * bn.nz
				check(math.abs(off - (wall + BN.out)) < 1e-6, "hangs just outside its wall")
				local along = if bn.nx ~= 0 then math.abs(bn.z - b.z) else math.abs(bn.x - b.x)
				local half = if bn.nx ~= 0 then b.sz / 2 else b.sx / 2
				check(along + BN.size[1] / 2 <= half, "the cloth stays within the face")
				check(bn.y - BN.size[2] > b.base + 20, "the foot well above the street")
				check(bn.y <= b.top, "the rod under the shaft's top")
			end
		end
		check(BN.images.Uptown > 0, "the banner picture is uploaded")
	end)

	test("Alive2: the banners billow out, never into the wall", function()
		local lo, hi = math.huge, -math.huge
		for t = 0, 120, 0.13 do
			for i = 1, 7 do
				local a = LifePlan.billow(i, 7, t, BN.wind, 1.3)
				lo, hi = math.min(lo, a), math.max(hi, a)
			end
		end
		check(lo >= -0.02, "at most a hair back toward the wall (" .. lo .. ")")
		check(hi > 0.04 and hi < 0.25, "a gentle billow (" .. hi .. ")")
	end)

	test("Alive2: the crane trolleys run along the boom and the hook swings", function()
		local prev = nil
		local seenA, seenB, maxSwing, maxStep = false, false, 0, 0
		local dt = 1 / 30
		for t = 0, 120, dt do
			local z, swing = LifePlan.crane(CR, t, 0.37)
			check(z >= CR.a - 1e-6 and z <= CR.b + 1e-6, "on the boom")
			seenA = seenA or math.abs(z - CR.a) < 1e-6
			seenB = seenB or math.abs(z - CR.b) < 1e-6
			maxSwing = math.max(maxSwing, math.abs(swing))
			if prev then
				maxStep = math.max(maxStep, math.abs(z - prev))
			end
			prev = z
		end
		check(seenA and seenB, "waits at both ends")
		check(maxSwing > 0.01 and maxSwing <= CR.swing, "the hook swings, gently (" .. maxSwing .. ")")
		check(maxStep / dt <= CR.speed * 1.5 + 0.01, "no jumps: at most 1.5 x its mean speed")
		-- the boom's half length holds the run with the trolley's frame
		check(CR.b - CR.a < Config.City.docks.cranes.boom, "the run fits the boom")
		check(L.alive.tags.CraneBoom == "LifeCrane", "the server tags the boom's box for the devices")
	end)

	test("Alive2: each boom's trolley and cable are where the devices look for them", function()
		local AA = Config.AliveArt
		check(AA.CraneBoom.meshes.CraneTrolley.offset[3] == CR.at, "the trolley at the boom's look offset")
		local n = 0
		for _, b in world.hubBoxes do
			if b.look == "CraneBoom" then
				local found = 0
				for _, p in LifeKit.cover(Config, b) or {} do
					if p.name == "CraneTrolley" or p.name == "CraneCable" then
						if
							math.abs(p.x - b.cx) < CR.find[1]
							and math.abs(p.z - (b.cz + CR.at)) < CR.find[2]
						then
							found += 1
						end
					end
				end
				check(found == 2, "trolley and cable found by the device's rule")
				n += 1
			end
		end
		check(n == Config.City.docks.cranes.count, "every crane")
	end)

	test("Alive2: the Alive looks never fling in the street smash", function()
		-- the trolley alone would be a "whole" street thing by size: the server names Alive pieces "dress"
		local tr = Config.AliveArt.CraneBoom.meshes.CraneTrolley.size
		check(StreetBreak.kind(tr[1], tr[2], tr[3]) == "whole", "(a trolley's size alone would break)")
		check(
			has(
				"src/server/Services/CityBuilder.luau",
				'p.Name = if pc.set == ALIVE_SET then "dress" else b.kind'
			),
			"the server names Alive pieces dress, not prop"
		)
		check(has("src/client/Fx/BuildingFx.luau", 'p.Name == "prop"'), "the smash only takes props")
	end)

	test("Alive2: kites over the park, budgeted per preset", function()
		local Bp = Config.Park.life.budget
		check(
			Bp.low.kites == 0 and Bp.medium.kites >= 1 and Bp.high.kites >= Bp.medium.kites,
			"phones fly none"
		)
		check(KT.image > 0 and KT.tail > 0, "the kite and tail pictures are uploaded")
		for t = 0, 60, 0.21 do
			for _, u in { 0, 0.5, 0.99 } do
				local dx, dy, dz, bank = LifePlan.kite(KT, t, u * 6.28, u, 1 - u)
				local reach = math.sqrt(dx * dx + dz * dz)
				check(dy >= KT.height[1] - KT.swoop[2] - 1e-6, "high over the lawn")
				check(dy <= KT.height[2] + KT.swoop[2] + 1e-6, "not lost in the clouds")
				check(reach <= KT.out[2] + KT.swoop[1] + 1e-6, "on its line")
				-- downwind of the flyer
				check(dx * KT.wind[1] + dz * KT.wind[2] > 0, "downwind")
				check(math.abs(bank) <= 0.45 + 1e-6, "banks a little")
			end
		end
	end)

	test("Alive2: banners and cranes budgeted per preset, phones lightest", function()
		local B = L.budget
		check(
			B.low.banners <= B.medium.banners and B.medium.banners <= B.high.banners,
			"banners rise with the preset"
		)
		check(B.low.bannerSegs < B.high.bannerSegs, "smoother cloth on high")
		check(B.low.cranes >= 1 and B.high.cranes <= Config.City.docks.cranes.count, "cranes per preset")
		check(has("src/client/Fx/CityLife.luau", "stepBanners(now)"), "banners step in CityLife's Heartbeat")
		check(has("src/client/Fx/CityLife.luau", "stepCranes(now)"), "cranes step in CityLife's Heartbeat")
	end)
end
