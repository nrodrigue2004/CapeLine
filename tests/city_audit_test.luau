-- The city and destruction audit (overnight queue item 4, 2026-11-18): one test per bug fixed, each failing on
-- the code before its fix. Called from tests/run.luau:
--   require("./city_audit_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="City audit" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local Structure = require("../src/shared/Structure")
	local BuildingState = require("../src/shared/BuildingState")
	local DS = Config.Destruction

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- a book over copies of some of the world's buildings, all in one district
	local function bookOf(ids: { number }): (any, { any })
		local list = {}
		for i, id in ids do
			local b = table.clone(world.buildings[id])
			b.id = i
			b.district = "A"
			table.insert(list, b)
		end
		return BuildingState.new(DS, list), list
	end

	-- supers around the base until it comes down (or is held up by the cap); returns the last blast
	local function wreck(book: any, b: any, now: number): any
		local r
		for k = 1, 40 do
			local a = k * 2.4
			r = BuildingState.blast(
				DS,
				book,
				b.id,
				b.x + math.cos(a) * (b.sx / 2 + 1),
				b.base + 4,
				b.z + math.sin(a) * (b.sz / 2 + 1),
				14,
				DS.superStruct,
				now
			)
			if r.state == BuildingState.COLLAPSED or r.cut then
				break
			end
		end
		return r
	end

	-- the server's batch exactly as BuildingService.flush sends it
	local function batch(book: any): any
		return {
			r = BuildingState.takeFixed(book),
			d = BuildingState.takeDiffs(book),
			c = BuildingState.takeRemoved(book),
		}
	end

	local function sameHoles(book: any, view: any, id: number): boolean
		local a, b = book.gone[id] or {}, view.gone[id] or {}
		if book.state[id] ~= BuildingState.DAMAGED then
			return (view.state[id] or 0) == (book.state[id] or 0)
		end
		for i in a do
			if not b[i] then
				return false
			end
		end
		for i in b do
			if not a[i] then
				return false
			end
		end
		return view.state[id] == book.state[id]
	end

	test(
		"City audit: a Damaged building's standing pieces still stop rays; only its holes let them through",
		function()
			local book, list = bookOf({ 1 })
			local b = list[1]
			local front = b.z - b.sz / 2 -- the -z face
			local far = 400
			-- straight at the front face's middle, from 30 studs out, at the ground storey's middle
			local grid = BuildingState.grid(DS, book, 1) :: any
			local y = b.base + grid.storeyH / 2
			local function shoot(x: number): number
				return BuildingState.ray(DS, book, x, y, front - 30, 0, 0, 1, far)
			end
			check(
				shoot(b.x) == far,
				"an Intact building is left to the engine's raycast (its real body blocks)"
			)
			local r = BuildingState.blast(DS, book, 1, b.x, y, front - 1, 12, DS.structure.chunkCost, 0)
			check(r.state == BuildingState.DAMAGED and #r.hit >= 1, "one piece knocked out of the front")
			local hole = grid.pieces[r.hit[1]]
			local wall
			for i, p in grid.pieces do
				if p.kind == "wall" and p.face == 1 and p.storey == 1 and not book.gone[1][i] then
					wall = p
					break
				end
			end
			check(wall ~= nil, "a front panel still stands")
			if wall then
				local d = shoot(wall.cx)
				check(math.abs(d - 30) < 0.01, "a standing panel stops the ray at the face (" .. d .. ")")
			end
			local through = shoot(hole.cx)
			check(through > 30 + DS.structure.wall, "the hole lets it through (" .. through .. ")")
			check(through < far, "to the back wall")
			-- a ray that starts inside a piece skips that piece (as Roblox raycasts do)
			if wall then
				local inside = BuildingState.ray(DS, book, wall.cx, wall.cy, wall.cz, 0, 0, 1, far)
				check(inside > DS.structure.wall, "a ray from inside a panel is not stopped by it")
			end
			-- straight down onto the roof: the roof slab stops it
			local down = BuildingState.ray(DS, book, b.x, b.top + 50, b.z, 0, -1, 0, far)
			check(math.abs(down - 50) < 0.01, "a downward ray lands on the roof (" .. down .. ")")
			-- collapsed: nothing of it stands
			local c = wreck(book, b, 100)
			check(c.state == BuildingState.COLLAPSED, "wrecked")
			check(shoot(b.x) == far, "a collapsed building blocks nothing")
			-- the server's combat rays use it
			local combat = "src/server/Services/CombatService.luau"
			check(
				has(combat, "BuildingService.ray(from, dir.Unit, d)"),
				"CombatService rayDist stops on pieces"
			)
			check(has(combat, "BuildingService.ray(from, dir / len, len)"), "line of sight too")
			check(
				has(combat, "BuildingService.ray(from, Vector3.new(0, -1, 0), d)"),
				"and the ground under a landing"
			)
		end
	)

	test("City audit: every damaging ability breaks buildings where it lands", function()
		local bad = {}
		local n = 0
		for id, a in Config.Abilities.list do
			-- a parry stance's coeff is its riposte, a strike on the robot that attacked (no place it lands)
			if (a.coeff or 0) > 0 and not a.allyHeal and a.buff ~= "parry" then
				n += 1
				local dmg = BuildingState.abilityStruct(DS, a)
				local lands = BuildingState.castStruct(a.shape, true)
					or BuildingState.LANDS[a.shape] == true
					or a.dropCoeff ~= nil
					or a.tickStruct ~= nil
				if dmg <= 0 or not lands then
					table.insert(bad, id .. " (" .. tostring(a.shape) .. ")")
				end
			end
		end
		check(n > 100, "damaging abilities found (" .. n .. ")")
		check(#bad == 0, "abilities that break nothing: " .. table.concat(bad, ", "))
		check(BuildingState.castStruct("field", true), "a field hits the buildings where it is cast")
		check(not BuildingState.castStruct("field", false), "only where it has a centre")
		check(not BuildingState.castStruct("buff", true), "a buff hits nothing")
		check(
			BuildingState.abilityStruct(DS, { slot = "super", shape = "field", coeff = 0.5 })
				== DS.superStruct,
			"a super field (Blizzard Dome, Singularity, Sunfall) is worth a super's structure damage"
		)
		check(
			BuildingState.abilityStruct(DS, { slot = "skill", coeff = 0.3, allyHeal = 0.1 }) == 0,
			"a healing field breaks nothing"
		)
		check(
			has(
				"src/server/Services/CombatService.luau",
				"BuildingState.castStruct(plan.shape, plan.cx ~= nil) and structOf(eff) > 0"
			),
			"CombatService uses the shared rule"
		)
	end)

	test("City audit: a hit on a skyscraper's crown breaks its top storey", function()
		local tall
		for _, b in world.buildings do
			if b.peak and b.peak - b.top > 60 and (not tall or b.peak - b.top > tall.peak - tall.top) then
				tall = b
			end
		end
		check(tall ~= nil, "a skyscraper with a crown")
		if not tall then
			return
		end
		local book, list = bookOf({ tall.id })
		local b = list[1]
		local spire = b.peak - 20
		check(BuildingState.touches(b, b.x, spire, b.z, 12), "a blast on the spire touches the building")
		check(not BuildingState.touches(b, b.x, b.peak + 40, b.z, 12), "a blast well above the peak does not")
		check(BuildingState.blastY(b, spire) == b.top, "it lands on the roof")
		check(BuildingState.blastY(b, b.base + 5) == b.base + 5, "a hit lower down lands where it is")
		local r =
			BuildingState.blast(DS, book, 1, b.x, BuildingState.blastY(b, spire), b.z, 12, DS.superStruct, 0)
		local grid = BuildingState.grid(DS, book, 1) :: any
		local top = #r.hit > 0
		for _, i in r.hit do
			top = top and grid.pieces[i].storey == grid.storeys
		end
		check(top, "the crown hit knocks out top-storey pieces (" .. #r.hit .. ")")
		check(
			has(
				"src/server/Services/BuildingService.luau",
				"BuildingState.touches(b, center.X, center.Y, center.Z, radius)"
			)
				and has("src/server/Services/BuildingService.luau", "BuildingState.blastY(b, center.Y)"),
			"BuildingService.hit uses both"
		)
	end)

	test("City audit: a building the collapse cap held up comes down once there is room", function()
		local book, list = bookOf({ 1, 2, 3, 4, 5 })
		for i = 1, 3 do
			local r = wreck(book, list[i], 0)
			check(r.state == BuildingState.COLLAPSED, "collapse " .. i)
		end
		local r = wreck(book, list[4], 1)
		check(r.cut and r.state == BuildingState.DAMAGED, "the 4th is held up by the cap")
		check(book.held[4] == true, "and remembered")
		check(#BuildingState.stepHeld(DS, book, 2) == 0, "it stays up while 3 are coming down")
		local down = BuildingState.stepHeld(DS, book, DS.collapseTime + 0.5)
		check(#down == 1 and down[1].id == 4, "it comes down once the cap has room")
		check(book.state[4] == BuildingState.COLLAPSED and book.hp[4] == 0, "Collapsed")
		check(
			down[1].blast.changed and down[1].blast.state == BuildingState.COLLAPSED,
			"a collapse for settle()"
		)
		check(book.held[4] == nil and #BuildingState.stepHeld(DS, book, 30) == 0, "once")
		local diffs = BuildingState.takeDiffs(book)
		local sent = false
		for i = 1, #diffs - 1, 2 do
			sent = sent or (diffs[i] == 4 and diffs[i + 1] == BuildingState.COLLAPSED)
		end
		check(sent, "devices hear of it")
		-- a held building that is repaired first is forgotten
		local b2, l2 = bookOf({ 1, 2, 3, 4 })
		for i = 1, 3 do
			wreck(b2, l2[i], 0)
		end
		wreck(b2, l2[4], 0)
		check(b2.held[4] == true, "held")
		BuildingState.repair(b2, 4)
		check(b2.held[4] == nil and #BuildingState.stepHeld(DS, b2, 30) == 0, "repaired: nothing comes down")
		check(
			has("src/server/Services/BuildingService.luau", "BuildingState.stepHeld(D, book, os.clock())"),
			"run"
		)
	end)

	test(
		"City audit: a repair and a new hit in one batch leave every device with the server's holes",
		function()
			local book, list = bookOf({ 1 })
			local b = list[1]
			local view = { state = {}, gone = {} }
			local function known(id: any): boolean
				return id == 1
			end
			local function hit(now: number, k: number)
				local a = k * 1.7
				BuildingState.blast(
					DS,
					book,
					1,
					b.x + math.cos(a) * (b.sx / 2 + 1),
					b.base + 4 + (k % 3) * 8,
					b.z + math.sin(a) * (b.sz / 2 + 1),
					12,
					DS.superStruct,
					now
				)
			end
			hit(0, 1)
			hit(0, 2)
			BuildingState.applyDiff(view, batch(book), known)
			check(sameHoles(book, view, 1), "the first holes match")
			-- quiet, then a drone repairs it ...
			BuildingState.stepDrones(DS, book, DS.repair.damagedAfter)
			local repaired = BuildingState.stepDrones(DS, book, DS.repair.damagedAfter + DS.repair.each)
			check(#repaired == 1, "repaired")
			-- ... and it is hit again before the next batch goes out (2 batches a second)
			hit(DS.repair.damagedAfter + DS.repair.each + 0.1, 7)
			local data = batch(book)
			check(#data.r == 1 and data.r[1] == 1, "the repair goes out with the batch")
			local touched, _, reset = BuildingState.applyDiff(view, data, known)
			check(touched[1] and reset[1], "the device redraws it from scratch")
			check(sameHoles(book, view, 1), "the device shows only the new holes, as the server has them")
			-- the Dev panel's repair all, right after a hit in the same batch
			hit(500, 3)
			BuildingState.repair(book, 1)
			BuildingState.applyDiff(view, batch(book), known)
			check(
				sameHoles(book, view, 1) and view.gone[1] == nil,
				"pieces from before a repair are not sent after it"
			)
			-- a late joiner's snapshot drops holes it heard of before
			hit(600, 4)
			local late = { state = {}, gone = { [1] = { [1] = true, [2] = true, [3] = true } } }
			BuildingState.applySnapshot(
				late,
				{ s = BuildingState.pack(book), n = book.n, g = BuildingState.packGone(DS, book) },
				function(id)
					local g = BuildingState.grid(DS, book, id)
					return if g then #g.pieces else nil
				end
			)
			check(sameHoles(book, late, 1), "the snapshot is the whole truth")
			BuildingState.takeFixed(book)
			local fx = "src/client/Fx/BuildingFx.luau"
			check(has(fx, "BuildingState.applyDiff(view, data, known)"), "BuildingFx uses the shared diff")
			check(has(fx, "BuildingState.applySnapshot(view, data, pieceCount)"), "and the shared snapshot")
			check(
				has("src/server/Services/BuildingService.luau", "{ r = fixed, d = diffs"),
				"the server sends r"
			)
		end
	)

	test(
		"City audit: device-side leaks: streamed-out building flags and props built under an old preset",
		function()
			local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
			local un = string.match(fx, "local function unregister.-\nend\n")
			check(
				un ~= nil and string.find(un, "bodyFlags[p] = nil", 1, true) ~= nil,
				"unregister drops the saved flags"
			)
			local props = fs.readFile("src/client/Controllers/CityProps.luau")
			check(
				string.find(props, "if gen ~= generation then", 1, true) ~= nil,
				"a build checks the preset generation"
			)
			local rb = string.match(props, "local function rebuild.-\nend\n")
			check(rb ~= nil and string.find(rb, "generation += 1", 1, true) ~= nil, "a new preset moves it")
			-- falling storeys are capped per device (the server's collapse cap counts only full collapses, so many
			-- towers losing their tops at once could animate thousands of pieces a frame)
			for _, name in Config.Presets.order do
				local f = Config.Presets[name].falling
				check(
					type(f) == "number" and f >= 240,
					name .. " caps falling pieces, a whole building at least"
				)
			end
			check(
				Config.Presets.low.falling < Config.Presets.medium.falling
					and Config.Presets.medium.falling < Config.Presets.high.falling,
				"phones animate the fewest"
			)
			local pan = string.match(fx, "local function pancake.-\nend\n")
			check(
				pan ~= nil and string.find(pan, "liveFall >= cap", 1, true) ~= nil,
				"pancake keeps under the cap"
			)
			check(
				string.find(fx, "liveFall = math.max(0, liveFall - #f.parts)", 1, true) ~= nil,
				"and hands them back"
			)
		end
	)

	test("City audit: Structure stays deterministic and within 256 pieces for every building", function()
		local maxP = 0
		for _, b in world.buildings do
			maxP = math.max(maxP, #Structure.build(DS, b).pieces)
		end
		check(maxP <= 256, "at most 256 pieces (" .. maxP .. ")")
		check(#world.buildings <= 4096, "the snapshot's building count fits applySnapshot's clamp")
	end)
end
