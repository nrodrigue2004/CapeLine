-- Impact (nate's playtest 2026-11-19): "More destruction everywhere, only skyscrapers are destructible" and "More
-- weight, more impact with everything ... it sends me back into a building and it destroys the building. Or even
-- just flying at super speed. Momentum and impact should destroy things".
-- Root cause of "only skyscrapers": WorldMap.pickBuildings stopped at 220 hub buildings partway through Old Town
-- (120 of its 229 houses), and no outskirts building (2,000+ houses, shops, barns, sheds) had a Structure record,
-- so outside Downtown and Uptown's towers almost nothing could break. Now every Old Town building and every
-- outskirts body is wreckable (ids after Uptown, so the old ids stand), the street knocks loose on impacts, and
-- rams, throws and robots into walls break what they hit (ImpactService, Shared.ImpactRules).
-- Called from tests/run.luau: require("./impact_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="Impact" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local WorldMap = require("../src/shared/WorldMap")
	local BuildingState = require("../src/shared/BuildingState")
	local Structure = require("../src/shared/Structure")
	local ImpactRules = require("../src/shared/ImpactRules")
	local Districts = require("../src/shared/Districts")
	local CityLayout = require("../src/shared/CityLayout")

	local D = Config.Destruction
	local I = Config.Combat.impact
	local world = T.world or WorldMap.build(Config, 202647)

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function source(path: string): string
		return fs.readFile(path)
	end
	local function near(a: number, b: number, msg: string)
		check(math.abs(a - b) < 1e-6, string.format("%s (got %.3f, want %.3f)", msg, a, b))
	end

	test(
		"Impact: every Old Town building and every outskirts body is wreckable, the old ids unchanged",
		function()
			local per: { [string]: number } = {}
			for i, b in world.buildings do
				check(b.id == i, "ids run 1 to n")
				per[b.district] = (per[b.district] or 0) + 1
			end
			-- every Old Town building, not just the ones the first 220 reached
			local clear = {}
			for _, s in world.safehouses do
				table.insert(clear, { x = s.x, z = s.z, r = Config.World.safehouse.pad * 0.75 })
			end
			local oldTown = Districts.oldTown(Config.City, clear)
			check(
				per.OldTown == #oldTown.buildings,
				string.format("all %d Old Town buildings (got %d)", #oldTown.buildings, per.OldTown or 0)
			)
			for _, b in world.hubBoxes do
				check(
					not b.grp or b.bid ~= nil,
					"every hub box of a building belongs to a wreckable one: " .. tostring(b.grp)
				)
			end
			check(
				(per.Outskirts or 0) >= 1500,
				"the outskirts buildings are wreckable (" .. tostring(per.Outskirts) .. ")"
			)
			-- every plain outskirts body has a record; its roof and bands go with it
			local bodies, withBid, roofs, roofsWith = 0, 0, 0, 0
			for _, plan in world.tilePlans do
				for _, b in plan.boxes do
					if b.kind == "building" and b.shape == nil and not b.ghost and b.sy >= 4 then
						bodies += 1
						withBid += if b.bid then 1 else 0
					elseif b.kind == "roof" then
						roofs += 1
						roofsWith += if b.bid then 1 else 0
					end
				end
			end
			check(
				bodies > 0 and withBid == bodies,
				string.format("%d of %d outskirts bodies wreckable", withBid, bodies)
			)
			check(
				roofsWith >= roofs * 0.9,
				string.format("their roofs go with them (%d of %d)", roofsWith, roofs)
			)
			-- the added buildings come after Uptown, so the first ones keep their ids
			local first = WorldMap.pickBuildings(
				Config,
				CityLayout.downtown(Config.City, Config.World),
				Districts.docks(Config.City, clear),
				oldTown,
				world.uptown
			)
			local same = true
			for i, b in first do
				local k = world.buildings[i]
				same = same and k.x == b.x and k.z == b.z and k.top == b.top and k.district == b.district
			end
			check(same, "the " .. #first .. " buildings before the additions keep their ids")
			for i = #first + 1, #world.buildings do
				check(world.buildings[i].more == true, "building " .. i .. " is one of the additions")
			end
			-- landmarks (the Foundry, the Crater) and safehouses stay whole: no box of theirs is wreckable
			for _, lm in world.landmarks do
				for _, b in lm.boxes do
					check(b.bid == nil, "landmark " .. lm.id .. " stays whole")
				end
			end
			check(#world.buildings < 4096, "the device's snapshot reads up to 4096 buildings")
			local again = WorldMap.build(Config, 202647)
			local twice = #again.buildings == #world.buildings
			for i, b in world.buildings do
				local k = again.buildings[i]
				twice = twice and k ~= nil and k.x == b.x and k.z == b.z and k.top == b.top
			end
			check(twice, "the same buildings every build")
		end
	)

	test(
		"Impact: nothing near a safehouse or under a beacon breaks; outskirts boxes are exact as floats",
		function()
			local pad = Config.World.safehouse.pad * 0.75 + D.keepClear
			for _, b in world.buildings do
				if b.more then
					for _, s in world.safehouses do
						local dx = math.max(math.abs(s.x - b.x) - b.sx / 2, 0)
						local dz = math.max(math.abs(s.z - b.z) - b.sz / 2, 0)
						if math.sqrt(dx * dx + dz * dz) <= pad then
							check(
								b.fixed == true,
								"building " .. b.id .. " by safehouse " .. s.id .. " never breaks"
							)
						end
					end
				end
			end
			local list = {}
			for _, b in world.buildings do
				if b.district == "Outskirts" then
					table.insert(list, b)
				end
			end
			local buf = BuildingState.packBoxes(list)
			check(buffer.len(buf) == #list * 24, "24 bytes an outskirts building in the snapshot")
			check(
				buffer.len(buf) < 80000,
				"the snapshot's boxes stay small (" .. buffer.len(buf) .. " bytes)"
			)
			local back = BuildingState.unpackBoxes(buf, list[1].id, 4096)
			local exact = true
			for _, b in list do
				local r = back[b.id]
				exact = exact
					and r ~= nil
					and r.x == b.x
					and r.z == b.z
					and r.sx == b.sx
					and r.sz == b.sz
					and r.base == b.base
					and r.top == b.top
			end
			check(exact, "every device reads the same box, so it builds the same pieces as the server")
			local ga = Structure.build(D, list[1])
			local gb = Structure.build(D, back[list[1].id])
			check(
				#ga.pieces == #gb.pieces and #ga.pieces > 4 and #ga.pieces <= 256,
				"the same pieces on the device"
			)
			-- the WorldInfo text keeps only the hub (the outskirts would have tripled it)
			local cb = source("src/server/Services/CityBuilder.luau")
			check(has(cb, 'b.district ~= "Outskirts"'), "WorldInfo leaves the outskirts to the snapshot")
			local bfx = source("src/client/Fx/BuildingFx.luau")
			check(
				has(bfx, "BuildingState.unpackBoxes(data.o, data.o1"),
				"BuildingFx reads them from the snapshot"
			)
			check(has(cb, 'bm:SetAttribute("BuildingId", b.bid)'), "each outskirts building is its own model")
		end
	)

	test("Impact: a small house breaks, holes first, then it comes down", function()
		local house
		for _, b in world.buildings do
			if b.district == "Outskirts" and b.size == "small" and not b.fixed then
				house = b
				break
			end
		end
		check(house ~= nil, "an outskirts house")
		if not house then
			return
		end
		local book = BuildingState.new(D, world.buildings)
		local r = BuildingState.blast(
			D,
			book,
			house.id,
			house.x,
			house.base + 4,
			house.z - house.sz / 2,
			8,
			1200,
			0
		)
		check(#r.hit >= 1 and r.state == BuildingState.DAMAGED, "a skill's worth knocks a hole in it")
		local n = 0
		repeat
			n += 1
			r = BuildingState.blast(D, book, house.id, house.x, house.base + 3, house.z, 20, 6000, n * 10)
		until r.state == BuildingState.COLLAPSED or n > 10
		check(r.state == BuildingState.COLLAPSED, "enough hits bring it down")
		-- a kept one never breaks
		BuildingState.keepWhole(book, house.id + 1)
		local k = world.buildings[house.id + 1]
		local kr = BuildingState.blast(D, book, k.id, k.x, k.base + 3, k.z, 20, 6000, 0)
		-- fix-destroy (2026-11-19): a kept building is a shell: its walls break, its pillars and roof never do and
		-- it never comes down
		for _, i in kr.hit do
			local p = BuildingState.grid(D, book, k.id).pieces[i]
			check(p.kind ~= "pillar", "a kept building's pillars never break")
		end
		for t = 1, 8 do
			kr = BuildingState.blast(D, book, k.id, k.x, k.base + 3, k.z, 20, 6000, 100 + t * 10)
		end
		check(
			book.state[k.id] ~= BuildingState.COLLAPSED,
			"a kept building (a side quest's house) never comes down"
		)
	end)

	test("Impact: hits look only at nearby buildings, and miss none", function()
		local book = BuildingState.new(D, world.buildings)
		local n = 0
		local missed = 0
		local seed = 7
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local t0 = os.clock()
		for _ = 1, 400 do
			local x, z = (rnd() - 0.5) * 4000, (rnd() - 0.5) * 4000
			local r = 5 + rnd() * 40
			local y = Config.City.ground.y + rnd() * 60
			local near = BuildingState.near(book, x, z, r)
			local set = {}
			for _, id in near do
				set[id] = true
			end
			for _, b in world.buildings do
				if BuildingState.touches(b, x, y, z, r) then
					n += 1
					if not set[b.id] then
						missed += 1
					end
				end
			end
		end
		local brute = os.clock() - t0
		check(
			missed == 0,
			"the index finds every building a hit touches (" .. n .. " touches, " .. missed .. " missed)"
		)
		t0 = os.clock()
		for _ = 1, 400 do
			local x, z = (rnd() - 0.5) * 4000, (rnd() - 0.5) * 4000
			for _, id in BuildingState.near(book, x, z, 30) do
				BuildingState.touches(book.boxes[id], x, 10, z, 30)
			end
		end
		local indexed = os.clock() - t0
		check(
			indexed < brute / 5,
			string.format(
				"the index is far cheaper (%.2f ms vs %.2f ms for 400 hits)",
				indexed * 1000,
				brute * 1000
			)
		)
		check(indexed / 400 < 0.0005, "a hit's search stays under half a millisecond")
	end)

	test("Impact: drones cover the outskirts, and their search walks only wrecked buildings", function()
		local book = BuildingState.new(D, world.buildings)
		local out = 0
		for _, d in book.drones do
			out += if d.district == "Outskirts" then 1 else 0
		end
		check(out == D.repair.districtDrones.Outskirts, "the outskirts get their own drones (" .. out .. ")")
		local id
		for _, b in world.buildings do
			if b.district == "Outskirts" and not b.fixed then
				id = b.id
				break
			end
		end
		local b = world.buildings[id]
		BuildingState.blast(D, book, id, b.x, b.base + 3, b.z, 20, 2000, 0)
		check(book.state[id] ~= 0, "an outskirts house is wrecked")
		local t = D.repair.collapsedAfter + 1
		local _, started = BuildingState.stepDrones(D, book, t)
		local took = false
		for _, d in started do
			took = took or d.target == id
		end
		check(took, "an outskirts drone takes it")
		local repaired = BuildingState.stepDrones(D, book, t + D.repair.each + 0.1)
		check(table.find(repaired, id) ~= nil and book.state[id] == 0, "and puts it back")
	end)

	test("Impact: the curves and the caps", function()
		local R, K = I.ram, I.knock
		check(ImpactRules.ramDamage(R, R.minSpeed - 1) == 0, "too slow: a wall stops you")
		check(ImpactRules.ramDamage(R, R.minSpeed) == R.dmg[1], "a ram at the floor")
		check(ImpactRules.ramDamage(R, R.fullSpeed + 50) == R.dmg[2], "capped at the top")
		check(
			R.minSpeed < Config.Move.flight.cruise,
			"plain flight rams too (fix-destroy, nate: fly straight through buildings)"
		)
		check(R.minSpeed <= Config.Move.flight.boost, "a flight boost rams")
		check(R.minSpeed <= Config.Move.mobility.speed.sprint, "a Super-speed running jump rams")
		check(R.minSpeed <= Config.Move.mobility.leap.pound.speed, "a Leaping pound rams through a roof")
		check(
			ImpactRules.ramDamage(R, Config.Move.flight.boost) >= D.structure.chunkCost,
			"a boost ram knocks a piece out"
		)
		-- throws
		check(ImpactRules.knockDistance(K, 10, 1000) == 0, "a light hit throws nobody")
		near(
			ImpactRules.knockDistance(K, K.minShare * 1000, 1000),
			K.dist[1],
			"a heavy hit throws at the floor"
		)
		near(ImpactRules.knockDistance(K, 900, 1000), K.dist[2], "capped at the top")
		check(K.dist[1] / K.time >= K.wallSpeed, "every throw is fast enough to break a wall")
		check(ImpactRules.knockDamage(K, K.wallSpeed - 1) == 0, "a slow throw breaks nothing")
		check(ImpactRules.knockDamage(K, K.fullSpeed) == K.dmg[2], "a hard throw at the top")
		near(
			ImpactRules.throwLength(K, 40, 0.5, true),
			20 + 20 * K.through,
			"through the wall with part of the rest"
		)
		near(ImpactRules.throwLength(K, 40, 0.5, false), 20 - K.stopShort, "a wall that holds stops it short")
		check(
			ImpactRules.robotDamage(I.robot, I.robot.minKnock - 1) == 0,
			"a nudge into a wall breaks nothing"
		)
		check(
			ImpactRules.robotDamage(I.robot, 12) >= D.structure.chunkCost,
			"a robot knocked 12 studs breaks a panel"
		)
		near(ImpactRules.after(R, 100), 100 * (1 - R.loss), "a ram costs some speed")
		-- the server's check of a ram
		check(ImpactRules.ramOk(R, 110, 110, 5), "a real boost ram")
		check(not ImpactRules.ramOk(R, 110, 30, 5), "claimed fast, moved slowly: no")
		check(not ImpactRules.ramOk(R, 200, 110, 5), "claims more than the history allows: no")
		check(not ImpactRules.ramOk(R, 110, 110, 200), "the wall is nowhere near the hero: no")
		check(ImpactRules.ramOk(R, 60, 60, 2), "cruising speed rams too (fix-destroy: fly straight through)")
		check(not ImpactRules.ramOk(R, 30, 30, 2), "a slow drift: no")
		check(
			ImpactRules.ramSpeed(R, 300, 100) == 100 * R.slack,
			"the ram counts at no more than the history"
		)
		-- caps
		local ledger = ImpactRules.ledger()
		local ok = 0
		for _ = 1, 20 do
			ok += if ImpactRules.allow(I, ledger, 1, 0) then 1 else 0
		end
		check(ok == R.perHero, "a hero breaks at most perHero walls a window")
		check(ImpactRules.allow(I, ledger, 1, R.heroWindow + 0.1), "and again after the window")
		local all = 0
		for hero = 2, 100 do
			all += if ImpactRules.allow(I, ledger, hero, 50) then 1 else 0
		end
		check(all == I.serverPerSecond, "the whole server breaks at most serverPerSecond a second")
	end)

	test("Impact: the path finds the first wall, skips wrecks and never starts inside", function()
		local boxes = {
			[1] = { id = 1, x = 20, z = 0, sx = 10, sz = 10, base = 0, top = 30 },
			[2] = { id = 2, x = 40, z = 0, sx = 10, sz = 10, base = 0, top = 30 },
			[3] = { id = 3, x = 0, z = 0, sx = 6, sz = 6, base = 0, top = 30 },
		}
		local id, t = ImpactRules.firstWall(boxes, { 1, 2, 3 }, 0, 5, 0, 60, 0, 0)
		check(id == 1 and math.abs(t - 15 / 60) < 1e-9, "the nearer wall first, starting inside one skips it")
		id = ImpactRules.firstWall(boxes, { 1, 2 }, 0, 5, 0, 60, 0, 0, function(i)
			return i == 1
		end)
		check(id == 2, "a collapsed building does not stop the throw")
		id = ImpactRules.firstWall(boxes, { 1, 2 }, 0, 40, 0, 60, 0, 0)
		check(id == nil, "over the roofs: no wall")
		check(
			ImpactRules.containing(boxes, { 1, 2 }, 15.5, 5, 0, 3) == 1,
			"a contact on a wall face is that building"
		)
		check(ImpactRules.containing(boxes, { 1, 2 }, 30, 5, 0, 3) == nil, "the gap between is nobody's")
		local index = ImpactRules.index(boxes, 64)
		local ids = ImpactRules.nearPath(index, 0, 0, 60, 0, 4)
		check(table.find(ids, 1) ~= nil and table.find(ids, 2) ~= nil, "the index finds both along the path")
	end)

	test("Impact: the server owns every break; pins, safe areas and scenes hold", function()
		local svc = source("src/server/Services/ImpactService.luau")
		check(
			has(svc, "hero.scene or hero.traveling"),
			"no breaks in a story scene (the prologue) or a fast-travel flight"
		)
		check(
			has(svc, "FlagService.safe(hero)"),
			"no breaks in a safe area (safehouses, HQs, mission pockets)"
		)
		check(
			has(svc, "MoveGuard.peakSpeed(hero, R.window)"),
			"a ram is checked against the server's own history"
		)
		check(has(svc, "ImpactRules.ramOk("), "the claim, the speed and the distance")
		check(has(svc, "ImpactRules.allow(I, ledger, hero.id"), "per-hero and server caps")
		check(has(svc, "BuildingService.smash("), "breaks go through BuildingService")
		check(has(svc, "MoveGuard.grant(hero, length + 10)"), "a throw is allowed by the speed check")
		check(has(svc, 'Net.fire("HeroKnock"'), "a throw goes to the hero's own device")
		check(has(svc, "EnemyService.heroHitHook = ImpactService.robotHit"), "robot punches throw heroes")
		local bs = source("src/server/Services/BuildingService.luau")
		check(
			has(bs, "not BuildingState.pinned(book, id)"),
			"pinned buildings (beacon hosts, quest roofs, the held row) never break"
		)
		check(has(bs, "BuildingState.near(book, center.X, center.Z, radius)"), "hits use the index")
		check(has(bs, "BuildingState.keepWhole(book, bid)"), "side quests' outskirts houses never break")
		check(has(bs, "flush()"), "a smash goes out at once")
		local cs = source("src/server/Services/CombatService.luau")
		check(has(cs, "ImpactService.knockHero(target"), "a PvP knockback can throw a hero through a wall")
		check(has(cs, "ImpactService.robotWall(hero, id, dir"), "a robot knocked into a wall breaks it")
		check(
			has(cs, "BuildingService.hit(pos - Vector3.new(0, 2, 0), radius, C.impact.pound, 1)"),
			"the pound breaks things"
		)
		local boss = source("src/server/Services/BossService.luau")
		check(has(boss, "ImpactService.bossHit(hero"), "a boss strike throws the hero")
		local es = source("src/server/Services/EnemyService.luau")
		check(has(es, "EnemyService.heroHitHook(hero, taken"), "EnemyService hands robot hits to the hook")
		local init = source("src/server/init.server.luau")
		local a = string.find(init, 'boot("ImpactService"', 1, true)
		local b = string.find(init, 'boot("BuildingService"', 1, true)
		local f = string.find(init, 'boot("FlagService"', 1, true)
		check(
			a ~= nil and b ~= nil and f ~= nil and a > b and a > f,
			"ImpactService boots after Building and Flag"
		)
		local remotes = source("src/shared/Remotes.luau")
		check(has(remotes, "ImpactRam = {"), "the ram remote has a schema and a rate limit")
	end)

	test(
		"Impact: the device rams, holds the hit-stop and draws the smash; the street knocks loose",
		function()
			local mc = source("src/client/Controllers/MoveController.luau")
			check(
				has(
					mc,
					"local RAM_MODES = { fly = true, dash = true, pound = true, ride = true, glide = true }"
				),
				"the fast modes ram"
			)
			check(
				has(mc, 'pick == "speed" and InputController.isDown("Boost")'),
				"a Super-speed jump holding Boost rams (the smash rule, 2026-11-19)"
			)
			check(not has(mc, "RAM_MODES = { ground"), "a ground sprint still runs up the wall")
			check(
				has(mc, "vel = ramStep(MoveController.mode, vel, pos, now, dt)"),
				"every air mode checks for a wall"
			)
			check(has(mc, "ramCarry = v * (1 - RAM.loss)"), "a little speed is lost going through")
			local fx = source("src/client/Fx/ImpactFx.luau")
			check(has(fx, 'Net.send("ImpactRam"'), "the device tells the server")
			check(has(fx, 'Juice.fire("wallSmash"'), "the smash plays")
			-- gap-fx3 (2026-11-19): the chips are effects-library particles inside the preset's particle budget
			check(has(fx, 'FxLib.throwMoment("smash"'), "chips use the effects library's budget")
			local bfx = source("src/client/Fx/BuildingFx.luau")
			check(has(bfx, "smashStreet(center, radius)"), "every impact knocks the street loose")
			check(has(bfx, "QualityController.preset.smash"), "by the preset's count")
			check(
				has(bfx, 'm:SetAttribute("WreckOf", rec.id)'),
				"a ram into a wreck's pieces is a ram into the building"
			)
			local props = source("src/client/Controllers/CityProps.luau")
			check(has(props, "function CityProps.smash("), "the kit's street props break")
			check(
				has(props, "(pr.brokenUntil or 0) <= now"),
				"a broken prop is not rebuilt before it respawns"
			)
			local P = Config.Presets
			check(
				P.low.smash <= P.medium.smash and P.medium.smash <= P.high.smash,
				"phones knock the fewest loose"
			)
			check(P.low.smash <= 3, "the phone preset stays light")
			local found = false
			for _, row in Config.Audio.juice do
				found = found or (row.id == "wallSmash" and row.visual == "ImpactFx")
			end
			check(found, "wallSmash is a juice row drawn by ImpactFx")
			local client = source("src/client/init.client.luau")
			check(has(client, "ImpactFx.init()"), "the device starts ImpactFx")
		end
	)
end
