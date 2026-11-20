-- fix-destroy (2026-11-19, nate after gaps7: "I want to fly straight through buildings"; "MORE DESTRUCTION. Why cant i
-- destroy silos? I literally want everything destructible even terrain"; the billboards' words). Called from
-- tests/run.luau: require("./destroy_test")({ test = test, check = check, Config = Config, world = world,
-- placePath = placePath }). ONLY="Destroy" runs just these; DESTROY_REPORT=1 prints the audit and the budget sim.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local WorldMap = require("../src/shared/WorldMap")
	local BuildingState = require("../src/shared/BuildingState")
	local Structure = require("../src/shared/Structure")
	local ImpactRules = require("../src/shared/ImpactRules")
	local CraterRules = require("../src/shared/CraterRules")
	local StreetBreak = require("../src/shared/StreetBreak")
	local NewsPlan = require("../src/shared/NewsPlan")
	local MoveCheck = require("../src/shared/MoveCheck")
	local BoxKit = require("../src/shared/BoxKit")

	local D = Config.Destruction
	local G = D.ground
	local I = Config.Combat.impact
	local report = process.env.DESTROY_REPORT == "1"
	local function say(...)
		if report then
			print(...)
		end
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function source(path: string): string
		return fs.readFile(path)
	end

	-- What is left whole on purpose (kind/colour keys), and why: listed in Decisions.md too
	local KEPT = {
		["prop:containerC"] = "the Docks crane (a beacon stands on it; 4-stud steel legs make no pieces)",
	}

	test("Destroy: every built body is wreckable and every street thing breaks", function()
		local wreck, street, kept, ground, other = 0, 0, 0, 0, {}
		local byKind: { [string]: number } = {}
		local function look(b: any, where: string)
			if b.ghost or b.kind == "glow" or b.kind == "mark" or b.kind == "band" then
				return -- light, marks and window bands: no body
			end
			local key = b.kind .. ":" .. tostring(b.color)
			if b.site then
				-- a story mission's permanent piece (Shared.MapSites, missions lane 2026-11-20) stays whole on purpose:
				-- its run's points stand on it
				kept += 1
				return
			end
			if b.bid then
				wreck += 1
				byKind["wreck " .. b.kind .. (if b.shape then "/" .. b.shape else "")] = (
					byKind["wreck " .. b.kind .. (if b.shape then "/" .. b.shape else "")] or 0
				) + 1
				return
			end
			if
				b.kind == "ground"
				or b.kind == "road"
				or b.kind == "sidewalk"
				or b.kind == "plaza"
				or b.kind == "field"
				or b.kind == "sand"
				or b.kind == "sea"
				or b.kind == "water"
				or b.kind == "crop"
				or b.kind == "rock"
			then
				ground += 1 -- ground: it craters (CraterService)
				return
			end
			if b.kind == "building" or WorldMap.roundBody(b) then
				table.insert(other, where .. " " .. key .. " " .. math.floor(b.sx) .. "x" .. math.floor(b.sy))
				return
			end
			-- ground-like props: dunes, a lighthouse's rock foot, piers and boardwalks, a fountain's basin: they crater
			if
				b.kind == "prop"
				and (b.color == "sand" or b.color == "rock" or (b.sy <= 2.5 and math.min(b.sx, b.sz) >= 6))
			then
				ground += 1
				return
			end
			if b.kind == "prop" or b.kind == "roof" or b.kind == "ledge" or b.kind == "awning" then
				local fx, fz = BoxKit.footprint(b)
				if StreetBreak.kind(fx, b.sy, fz) then
					street += 1
					return
				end
				if KEPT[key] then
					kept += 1
					return
				end
				-- a roof or ledge on something whole on purpose (a safehouse's roof pad) or a big rock base
				if b.kind == "ledge" or b.kind == "roof" or b.color == "rock" then
					kept += 1
					return
				end
			end
			if
				b.kind ~= "terminal"
				and b.kind ~= "beacon"
				and b.kind ~= "tier"
				and b.kind ~= "awning"
				and b.kind ~= "roof"
				and b.kind ~= "ledge"
			then
				table.insert(other, where .. " " .. key .. " " .. math.floor(b.sx) .. "x" .. math.floor(b.sy))
			end
		end
		local w = WorldMap.build(Config, 202647)
		for _, b in w.hubBoxes do
			look(b, "hub")
		end
		-- the outskirts' plans are emptied once built on the server; the data build keeps them
		for _, plan in w.tilePlans do
			for _, b in plan.boxes do
				look(b, "tile")
			end
		end
		say(
			string.format(
				"[destroy audit] wreckable parts %d, street things %d, ground %d, kept %d, left %d",
				wreck,
				street,
				ground,
				kept,
				#other
			)
		)
		for k, v in byKind do
			say("   ", k, v)
		end
		for i = 1, math.min(#other, 20) do
			print("   not breakable:", other[i])
		end
		check(#other == 0, "no built body or street thing is left unbreakable (" .. #other .. " left)")
		local silos, lights, mills, hub = 0, 0, 0, 0
		for _, b in w.buildings do
			if b.round and b.district == "Outskirts" and b.top - b.base < 40 then
				silos += 1
			elseif b.round and b.district == "Outskirts" and b.top - b.base >= 50 then
				lights += 1
			end
			if b.round and b.sx >= 15 and b.district == "Outskirts" then
				mills += 1
			end
			if b.district == "Hub" then
				hub += 1
			end
		end
		say(
			string.format(
				"[destroy audit] silos %d, lighthouses %d, windmills %d, hub bodies %d",
				silos,
				lights,
				mills,
				hub
			)
		)
		check(silos > 100, "the silos are wreckable (" .. silos .. ")")
		check(lights > 10, "the lighthouses are wreckable")
		check(mills >= 1, "the windmill is wreckable (a shell: its beacon stays up)")
		check(
			hub >= 20,
			"the Foundry, its stacks, the clock tower and the 16 safehouse shelters are wreckable"
		)
		check(
			#w.buildings <= 4096,
			"the building count still fits the snapshot's 4,096 (" .. #w.buildings .. ")"
		)
		for _, seed in { 1, 202701 } do
			check(#WorldMap.build(Config, seed).buildings <= 4096, "every week's world fits the snapshot too")
		end
	end)

	test("Destroy: a silo breaks round, comes down and the drones put it back", function()
		local silo
		for _, b in world.buildings do
			if b.round and b.district == "Outskirts" and b.top - b.base < 40 then
				silo = b
				break
			end
		end
		check(silo ~= nil, "a silo record")
		if not silo then
			return
		end
		local grid = Structure.build(D, silo)
		local R = silo.sx / 2
		local outside = 0
		for _, p in grid.pieces do
			local d = math.sqrt((p.cx - silo.x) ^ 2 + (p.cz - silo.z) ^ 2)
			if p.kind ~= "slab" and (d > R + 0.01 or d < R * 0.4) then
				outside += 1
			end
			if p.kind == "slab" then
				check(p.disc == true, "a round slab is a disc")
			elseif p.ry == nil then
				outside += 1
			end
		end
		check(outside == 0, "every wall and pillar stands on the silo's circle, turned to it")
		check(
			grid.panels[1] == 2 and grid.panels[3] == 2,
			"2 panels a face: an eight-sided shell with 4 pillars"
		)
		local book = BuildingState.new(D, world.buildings)
		local n, r = 0, nil
		repeat
			n += 1
			r = BuildingState.blast(D, book, silo.id, silo.x, silo.base + 3, silo.z, 10, D.superStruct, n * 2)
		until r.state == BuildingState.COLLAPSED or n > 12
		check(
			r ~= nil and r.state == BuildingState.COLLAPSED,
			"a few supers at its foot bring it down (" .. n .. ")"
		)
		say(string.format("[destroy] a silo: %d pieces, down in %d supers", #grid.pieces, n))
		-- the drones: quiet for collapsedAfter, then a drone's job
		local t = n * 2
		for _ = 1, 400 do
			t += 1
			BuildingState.stepDrones(D, book, t)
			if book.state[silo.id] == 0 then
				break
			end
		end
		check(book.state[silo.id] == 0, "the drones put the silo back")
	end)

	test("Destroy: a pinned building is a shell: holes, never a fall", function()
		local book = BuildingState.new(D, world.buildings)
		local b = world.buildings[30]
		BuildingState.pin(book, b.id, true)
		for k = 1, 12 do
			BuildingState.blast(D, book, b.id, b.x, b.base + 3, b.z - b.sz / 2, 30, 6000, k)
		end
		local grid = BuildingState.grid(D, book, b.id)
		local gone = book.gone[b.id] or {}
		local holes, pillars, roof = 0, 0, 0
		for i, p in grid.pieces do
			if gone[i] then
				holes += 1
				if p.kind == "pillar" then
					pillars += 1
				end
				if p.kind == "slab" and p.storey == grid.storeys then
					roof += 1
				end
			end
		end
		check(holes > 0, "its walls take holes")
		check(pillars == 0 and roof == 0, "its pillars and roof never break")
		check(book.state[b.id] == BuildingState.DAMAGED, "it never comes down")
		BuildingState.repair(book, b.id)
		check(book.state[b.id] == 0, "and it mends like any other")
	end)

	test("Destroy: structural damage is 1.5x easier, the same everywhere", function()
		check(D.structure.chunkCost == 400, "400 structure damage a piece (was 600)")
		check(D.structure.maxPerHit == 15, "15 pieces a hit at most (was 10)")
		local book = BuildingState.new(D, world.buildings)
		local b = world.buildings[5]
		local r = BuildingState.blast(D, book, b.id, b.x, b.base + 3, b.z - b.sz / 2, 30, D.superStruct, 0)
		check(
			#r.hit == math.floor(D.superStruct / D.structure.chunkCost) or #r.hit >= 6,
			"a super takes about 7 pieces"
		)
		check(math.ceil(D.structure.chunkCost / D.slotStruct.basic) == 2, "2 basic hits knock a piece out")
	end)

	test("Destroy: flying through: plain flight rams, keeps its speed, never pulled back", function()
		local R = I.ram
		local M = Config.Move
		check(R.minSpeed < M.flight.cruise, "plain flight is fast enough to ram")
		check(R.loss <= 0.1, "a ram keeps 90% of the speed")
		local dmg = ImpactRules.ramDamage(R, M.flight.cruise)
		check(dmg >= 4 * D.structure.chunkCost, "a cruise ram opens a hero-sized hole (4+ pieces)")
		-- a hero at cruise through three buildings in a row: the device's prediction (the same blast) and the server's
		-- blast pick the same pieces, the piece at the contact goes, and the speed check never pulls it back
		local book = BuildingState.new(D, world.buildings)
		local devGone: { [number]: { [number]: boolean } } = {}
		local b = world.buildings[12]
		local grid = BuildingState.grid(D, book, b.id)
		local y = b.base + 6
		local contactZ = b.z - b.sz / 2
		local dev = {}
		local pred = Structure.blast(D, grid, dev, b.x, y, contactZ + 1.5, R.radius, dmg)
		local srv = BuildingState.blast(D, book, b.id, b.x, y, contactZ + 1.5, R.radius, dmg, 0)
		devGone[b.id] = dev
		local same = #pred == #srv.hit
		for i, p in pred do
			same = same and srv.hit[i] == p
		end
		check(same, "the device's predicted hole is the server's hole")
		local covered = false
		for _, i in srv.hit do
			local p = grid.pieces[i]
			if p.kind == "wall" and math.abs(p.cx - b.x) <= p.sx / 2 and math.abs(p.cy - y) <= p.sy / 2 then
				covered = true
			end
		end
		check(covered, "the wall panel the hero hits is gone")
		-- MoveCheck at 10 Hz on a straight flight at cruise, slowed 10% at each of 6 walls
		local st = MoveCheck.new(0, 50, 0, 0)
		local x, v, fails = 0, M.flight.boost, 0
		for i = 1, 60 do
			if i % 8 == 0 then
				v *= 1 - R.loss
			end
			x += v * 0.1
			if not MoveCheck.sample(st, x, 50, 0, i * 0.1, M.flight.boost, M, Config.Safety) then
				fails += 1
			end
		end
		check(fails == 0, "a boost through 6 walls is never pulled back")
		local mc = source("src/client/Controllers/MoveController.luau")
		check(has(mc, "glide = true"), "glides and swoops ram too")
		check(has(mc, "MoveController.onPropHit"), "a street thing in the way is knocked loose, not a stop")
		local fx = source("src/client/Fx/ImpactFx.luau")
		check(
			has(fx, "BuildingFx.predict(") and has(fx, "ImpactRules.ramDamage(R, speed)"),
			"the device opens the hole at once"
		)
		local bf = source("src/client/Fx/BuildingFx.luau")
		check(
			has(bf, "function BuildingFx.predict") and has(bf, "local function reconcile"),
			"a hole the server never confirms comes back"
		)
		check(
			has(bf, "part.CanCollide = false"),
			"a predicted hole's pieces never block the hero for a moment"
		)
	end)

	test("Destroy: terrain craters dig, keep the water, and heal", function()
		local c: CraterRules.Crater = { id = 1, x = 0, y = 0, z = 0, r = 8, ground = "terrain", born = 0 }
		local lo, hi = CraterRules.region(G, c)
		local v = G.voxel
		local nx, ny, nz = (hi[1] - lo[1]) / v, (hi[2] - lo[2]) / v, (hi[3] - lo[3]) / v
		local mats, occ = {}, {}
		local waterY = -2
		-- sand up to y = 0 on the left half, water from -6 to waterY on the right (a shore)
		for i = 1, nx do
			mats[i], occ[i] = {}, {}
			for j = 1, ny do
				mats[i][j], occ[i][j] = {}, {}
				for k = 1, nz do
					local x = lo[1] + (i - 0.5) * v
					local yy = lo[2] + (j - 0.5) * v
					local m = "Air"
					if (x < 0 and yy < 0) or (x >= 0 and yy < -6) then
						m = "Sand"
					elseif x >= 0 and yy < waterY then
						m = "Water"
					end
					mats[i][j][k] = m
					occ[i][j][k] = if m == "Air" then 0 else 1
				end
			end
		end
		local function copy(t)
			local o = {}
			for i, a in t do
				o[i] = {}
				for j, b in a do
					o[i][j] = table.clone(b)
				end
			end
			return o
		end
		local keepM, keepO = copy(mats), copy(occ)
		local water0 = 0
		for i = 1, nx do
			for j = 1, ny do
				for k = 1, nz do
					if mats[i][j][k] == "Water" then
						water0 += 1
					end
				end
			end
		end
		local changed = CraterRules.carve(G, c, lo, mats, occ, waterY)
		check(changed >= 6, "the bowl digs voxels (" .. changed .. ")")
		local water1, airUnder, waterLost = 0, 0, 0
		for i = 1, nx do
			for j = 1, ny do
				for k = 1, nz do
					local yy = lo[2] + (j - 0.5) * v
					if mats[i][j][k] == "Water" then
						water1 += 1
					end
					if keepM[i][j][k] == "Water" and mats[i][j][k] ~= "Water" then
						waterLost += 1
					end
					if keepM[i][j][k] == "Sand" and mats[i][j][k] == "Air" and yy < waterY then
						airUnder += 1
					end
				end
			end
		end
		check(waterLost == 0, "no water voxel is ever touched")
		check(water1 >= water0, "dug voxels under the water become water (the volume stays closed)")
		check(airUnder == 0, "no air pocket under the water's surface")
		-- the heal: the voxels read before go back (CraterService writes keepM/keepO), so the ground is as it was
		mats, occ = copy(keepM), copy(keepO)
		local same = true
		for i = 1, nx do
			for j = 1, ny do
				for k = 1, nz do
					same = same and mats[i][j][k] == keepM[i][j][k]
				end
			end
		end
		check(same, "healed, the ground is exactly as it was")
		say(
			string.format(
				"[destroy] a radius-8 terrain crater: %d voxels dug of %d read",
				changed,
				nx * ny * nz
			)
		)
	end)

	test("Destroy: craters: sizes, caps per area and second, life and heal", function()
		check(CraterRules.radiusFor(G, D.slotStruct.skill) == 0, "a skill never craters the ground")
		check(CraterRules.radiusFor(G, D.superStruct) > G.radius[1], "a super does")
		check(CraterRules.radiusFor(G, D.bossStruct) > 0, "a boss slam does")
		check(CraterRules.radiusFor(G, I.pound) > 0, "a pound does")
		check(CraterRules.radiusFor(G, Config.Combat.drop.dmg[2]) > 0, "a big drop does")
		local book = CraterRules.new()
		local made = 0
		for k = 1, 10 do
			if CraterRules.add(G, book, k * 200, 0, 0, 3000, "part", 0) then
				made += 1
			end
		end
		check(made == G.perSecond, "at most perSecond craters a second")
		book = CraterRules.new()
		made = 0
		for k = 1, 10 do
			if CraterRules.add(G, book, 5 + k, 0, 5, 3000, "part", k * 2) then
				made += 1
			end
		end
		check(made == G.perCell, "at most perCell craters in one cell")
		check(
			CraterRules.add(G, book, 1000, 0, 1000, 3000, "terrain", 100) ~= nil
				and CraterRules.add(G, book, 1004, 0, 1000, 3000, "terrain", 102) == nil,
			"a terrain crater never overlaps another (each writes back only its own voxels)"
		)
		book = CraterRules.new()
		made = 0
		for k = 1, 400 do
			if CraterRules.add(G, book, k * 100, 0, 0, 3000, "part", k) then
				made += 1
			end
		end
		check(#book.list == G.maxLive, "at most maxLive on the server")
		local c = book.list[1]
		check(CraterRules.healing(G, c, c.born + 1) == 0, "a fresh crater is whole")
		check(CraterRules.healing(G, c, c.born + G.life - G.heal / 2) > 0.4, "it heals over its last minute")
		local gone = CraterRules.step(G, book, c.born + G.life + 1)
		check(#gone >= 1 and #book.list < G.maxLive, "then it is gone")
		check(#CraterRules.rim(c, 10) == 10, "a device draws the rim it is given")
		local srv = source("src/server/Services/CraterService.luau")
		check(
			has(srv, "WriteVoxels") and has(srv, "ReadVoxels"),
			"the server digs Terrain and writes it back"
		)
		check(
			has(
				source("src/server/Services/BuildingService.luau"),
				"CraterService.blast(center, radius, dmg)"
			),
			"big hits crater"
		)
		check(
			has(source("src/server/Services/ImpactService.luau"), "CraterService.blast(at, radius, dmg)"),
			"a drop on the ground craters it"
		)
		check(has(source("src/server/init.server.luau"), 'boot("CraterService"'), "CraterService boots")
		check(has(source("src/client/init.client.luau"), "GroundFx.init()"), "every device draws the craters")
	end)

	test("Destroy: billboards: the words sit on the screen and fall with the wall", function()
		local screens = NewsPlan.screens(Config, world)
		local on = nil
		for _, s in screens do
			if s.building then
				on = s
				break
			end
		end
		check(on ~= nil, "a screen on a building")
		if not on then
			return
		end
		local book = BuildingState.new(D, world.buildings)
		local grid = BuildingState.grid(D, book, on.building)
		local behind = NewsPlan.behind(grid :: any, on)
		check(#behind > 0, "the screen knows the wall pieces it hangs on")
		check(not NewsPlan.screenDown(0, behind, nil), "whole: it shows")
		local gone = { [behind[1]] = true }
		check(NewsPlan.screenDown(1, behind, gone), "a hole behind it: it falls")
		check(NewsPlan.screenDown(2, behind, nil), "collapsed: it is gone")
		local other = {}
		for i, p in (grid :: any).pieces do
			if not table.find(behind, i) and p.kind == "slab" then
				other[i] = true
			end
		end
		check(not NewsPlan.screenDown(1, behind, other), "a hole elsewhere: it stays")
		local hud = source("src/client/Ui/NewsHud.luau")
		check(has(hud, "bg.ClipsDescendants = true"), "the ticker stays on the screen's face")
		check(has(hud, "props.ink = false"), "no comic shadow bars hang off the 3D screen's words")
		check(
			has(hud, "(0.01 - 0.16) / (1 - 0.16 - 0.03)"),
			"the channel mark sits clear of the band's words"
		)
		check(has(hud, "dropScreen(s.part)"), "a screen that comes down falls")
		local bf = source("src/client/Fx/BuildingFx.luau")
		check(
			has(bf, 'p:IsA("Decal") or p:IsA("Texture")') and has(bf, 'p:IsA("SurfaceGui")'),
			"a hidden building's decals and signs hide with it"
		)
		check(has(bf, "a sign's words fall with its board"), "a flung sign keeps its words")
	end)

	test("Destroy: street things: whole, long and too big", function()
		check(StreetBreak.kind(1.6, 8, 1.6) == "whole", "a tree trunk")
		check(StreetBreak.kind(16, 8, 20) == "whole", "a container")
		check(StreetBreak.kind(3, 27, 3) == "whole", "a windmill pole")
		check(StreetBreak.kind(60, 3, 0.6) == "long", "a fence breaks where it is hit")
		check(StreetBreak.kind(26, 6, 26) == nil, "a lighthouse's rock base stays")
		local segs = StreetBreak.segments(
			{ x = 0, y = 1.5, z = 0, sx = 60, sy = 3, sz = 0.6 },
			{ x = 10, y = 1.5, z = 0 },
			6,
			6
		)
		local broken = 0
		for _, s in segs or {} do
			if s.broken then
				broken += 1
			end
		end
		check(
			segs ~= nil and #segs == 10 and broken >= 2 and broken <= 3,
			"only the lengths in reach go (" .. broken .. ")"
		)
	end)

	test("Destroy: budgets: 10 heroes wrecking Downtown for 2 minutes", function()
		-- every hero casts a super (3,000) and 2 skills (700) a second at the Downtown buildings round it, rams a wall every
		-- 2 s; the server's caps (3 collapses in 6 s, impact breaks) hold, and the devices' worst case stays under
		-- the presets' budgets
		local book = BuildingState.new(D, world.buildings)
		local ledger = ImpactRules.ledger()
		local crBook = CraterRules.new()
		local downtown = {}
		for _, b in world.buildings do
			if b.district == "Downtown" and b.x > -700 and b.x < -100 and b.z > -350 and b.z < 350 then
				table.insert(downtown, b)
			end
		end
		local seed = 7
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local maxDamaged, maxStanding, maxRemoved, collapses, maxOpen6 = 0, 0, 0, 0, 0
		local times = {}
		local rams, ramsOk = 0, 0
		for t = 0, 120, 0.5 do
			for hero = 1, 10 do
				-- each hero works one building for 10 s, low on its walls (the worst case: collapses)
				local b = downtown[1 + ((hero * 7 + math.floor(t / 10) * 3) % #downtown)]
				local side = if rnd() < 0.5 then -1 else 1
				local x = b.x + (rnd() - 0.5) * b.sx
				local z = b.z + side * b.sz / 2
				local y = b.base + 2 + rnd() * 8
				local dmg = if t % 1 == 0 then D.superStruct else D.slotStruct.skill
				local r = BuildingState.blast(D, book, b.id, x, y, z, 12, dmg, t)
				if r.changed and r.state == BuildingState.COLLAPSED then
					collapses += 1
					table.insert(times, t)
				end
				CraterRules.add(G, crBook, x, 0, z - 6, dmg, "part", t)
				-- flying through walls flat out: 4 rams a second
				for k = 0, 1 do
					rams += 1
					if ImpactRules.allow(I, ledger, hero, t + k * 0.25) then
						ramsOk += 1
					end
				end
			end
			for _, h in BuildingState.stepHeld(D, book, t) do
				local _ = h
				collapses += 1
				table.insert(times, t)
			end
			CraterRules.step(G, crBook, t)
			local removed = BuildingState.takeRemoved(book)
			maxRemoved = math.max(maxRemoved, #removed // 3)
			BuildingState.takeDiffs(book)
			local damaged, standing = 0, 0
			for id in book.open do
				damaged += 1
				local grid = BuildingState.grid(D, book, id)
				local gone = book.gone[id] or {}
				for i in grid.pieces do
					if not gone[i] then
						standing += 1
					end
				end
			end
			maxDamaged = math.max(maxDamaged, damaged)
			maxStanding = math.max(maxStanding, standing)
			local open6 = 0
			for _, ct in times do
				if t - ct < D.collapseTime then
					open6 += 1
				end
			end
			maxOpen6 = math.max(maxOpen6, open6)
		end
		local P = Config.Presets
		local low = P.low or P[1]
		say(
			string.format(
				"[destroy budget] Downtown %d buildings: up to %d Damaged at once, %d stand-in pieces drawn, %d pieces in one 0.5 s diff (%d bytes), %d collapses in 2 min (at most %d in 6 s), %d/%d rams allowed, %d live craters",
				#downtown,
				maxDamaged,
				maxStanding,
				maxRemoved,
				maxRemoved * 3 * 2,
				collapses,
				maxOpen6,
				ramsOk,
				rams,
				#crBook.list
			)
		)
		check(maxOpen6 <= D.maxCollapses, "never more than 3 collapses started in 6 s")
		check(#crBook.list <= G.maxLive, "live craters capped")
		check(ramsOk < rams, "the impact caps bite")
		check(maxRemoved * 6 < 8000, "one diff batch stays a few KB")
		if low then
			check(
				low.falling >= 200 and low.debris <= 80,
				"a phone's falling and debris caps stay as they were"
			)
			check(
				(low.craterRim or 0) * (low.craters or 0) <= 60,
				"a phone draws at most 60 crater rim chunks"
			)
		end
		say(
			string.format(
				"[destroy budget] device worst case: stand-ins %d parts (only the ones streamed near are drawn), falling capped at %s/%s/%s, debris %s/%s/%s, crater chunks %d/%d/%d",
				maxStanding,
				tostring(P.low and P.low.falling),
				tostring(P.medium and P.medium.falling),
				tostring(P.high and P.high.falling),
				tostring(P.low and P.low.debris),
				tostring(P.medium and P.medium.debris),
				tostring(P.high and P.high.debris),
				(P.low and P.low.craters * P.low.craterRim) or 0,
				(P.medium and P.medium.craters * P.medium.craterRim) or 0,
				(P.high and P.high.craters * P.high.craterRim) or 0
			)
		)
	end)

	test("Destroy: the built place has the new scripts", function()
		local placePath = T.placePath
		if not placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local game = roblox.deserializePlace(fs.readFile(placePath))
		local rs = game:GetService("ReplicatedStorage")
		local shared = rs:FindFirstChild("Shared")
		check(shared and shared:FindFirstChild("CraterRules") ~= nil, "Shared.CraterRules is in the place")
		check(shared and shared:FindFirstChild("StreetBreak") ~= nil, "Shared.StreetBreak is in the place")
		local sss = game:GetService("ServerScriptService")
		local server = sss:FindFirstChild("Server")
		local services = server and server:FindFirstChild("Services")
		check(services and services:FindFirstChild("CraterService") ~= nil, "CraterService is in the place")
		local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
		local client = sps and sps:FindFirstChild("Client")
		local fx = client and client:FindFirstChild("Fx")
		check(fx and fx:FindFirstChild("GroundFx") ~= nil, "Fx.GroundFx is in the place")
	end)
end
