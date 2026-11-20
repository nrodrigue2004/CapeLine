-- The living world (2026-11-19, nate's playtest: "you still use way too many simple shapes and textures ... World
-- needs to feel way more alive"): Art.Life's looks over the city's boxes (Shared.LifeKit), the shop fronts and
-- vending machines, and the ambient life's plans (Shared.LifePlan, Fx.CityLife). Called from tests/run.luau:
--   require("./living_world_test")({ test = test, check = check, Config = Config, world = world, placePath = p })
-- ONLY="Living world" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local LifeKit = require("../src/shared/LifeKit")
	local LifePlan = require("../src/shared/LifePlan")
	local Vehicles = require("../src/shared/Vehicles")
	local L = Config.Life
	local A = Config.LifeArt

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- every box the city builds (the hub, the outskirts tiles)
	local all = {}
	for _, b in world.hubBoxes do
		table.insert(all, b)
	end
	for _, p in world.tilePlans do
		for _, b in p.boxes do
			table.insert(all, b)
		end
	end

	test("Living world: every look has its meshes, colours and an uploaded model", function()
		for look, def in A.cover do
			check(L.looks[look] ~= nil, look .. " has colours in Config.Life.looks")
			check(#def.nominal == 3 and def.nominal[1] > 0, look .. " has a nominal box")
			for name, f in def.pieces do
				check(f.size[1] > 0 and f.size[2] > 0 and f.size[3] > 0, look .. "." .. name .. " has a size")
				check(
					L.looks[look] and L.looks[look][name] ~= nil,
					look .. "." .. name .. " has a colour row"
				)
			end
		end
		for look, rows in L.looks do
			for name in rows do
				check(
					A.cover[look] and A.cover[look].pieces[name] ~= nil,
					look .. "." .. name .. " is in LifeArt"
				)
			end
		end
		local ids = serde.decode("json", fs.readFile("art/models/life_meshids.json"))
		local n = 0
		for _, def in A.cover do
			for name in def.pieces do
				n += 1
				check(ids[name] ~= nil, name .. " has an uploaded mesh id")
			end
		end
		for look, pieces in A do
			if look ~= "cover" then
				for name in pieces do
					n += 1
					check(ids[name] ~= nil, look .. "." .. name .. " has an uploaded mesh id")
				end
			end
		end
		check(n == 32, string.format("32 meshes in the set (%d)", n))
		check(
			has("default.project.json", '"Life": { "$path": "art/models/Life.rbxm" }'),
			"Rojo maps Art.Life"
		)
		check(has("src/shared/MeshFix.luau", '"Life", -- living-world'), "MeshFix turns Art.Life back")
		local turns = serde.decode("json", fs.readFile("art/models/meshturns.json"))
		check(turns.Life and turns.Life.verdict == "rotY180", "meshcheck measured Art.Life turned")
		for _, id in
			{
				L.picket.image,
				L.tilled.image,
				L.flags.Brightharbor,
				L.flags.Uptown,
				L.flags.Docks,
				L.flags.OldTown,
			}
		do
			check(type(id) == "number" and id > 0 and id == math.floor(id), "an uploaded picture id")
		end
	end)

	test("Living world: the city's simple shapes have looks, all picked by hash, every look known", function()
		local counts = LifeKit.count(Config, all)
		for _, look in
			{
				"TreeTrunk",
				"CanopyRound",
				"CanopyTall",
				"CanopyPine",
				"CropRow",
				"CornRow",
				"HayBale",
				"HouseDoor",
				"SiloBody",
				"SiloDome",
				"Picket",
			}
		do
			check((counts[look] or 0) >= 100, string.format("%s: %d boxes", look, counts[look] or 0))
		end
		-- every tree's ball is a crown and its trunk a trunk; no leaf ball left plain outside the city's hedges
		local plainBalls = 0
		for _, b in all do
			if b.color == "leaf" and b.shape == "ball" and not b.look then
				plainBalls += 1
			end
		end
		check(plainBalls == 0, string.format("no plain leaf balls left (%d)", plainBalls))
		-- the same picks twice
		local again = LifeKit.count(Config, all)
		for k, v in counts do
			check(again[k] == v, k .. " picked the same twice")
		end
		-- variety: the leaf colours and every crown shape show up
		local leaves: { [string]: boolean } = {}
		local nLeaves = 0
		for _, b in all do
			if b.look == "Canopy" and LifeKit.lookOf(Config, b) ~= "CanopyPine" then
				local c = LifeKit.leaf(Config, b)
				local key = table.concat(c, ",")
				if not leaves[key] then
					leaves[key] = true
					nLeaves += 1
				end
			end
		end
		check(nLeaves >= 6, string.format("%d leaf colours in the city", nLeaves))
	end)

	test("Living world: cover pieces sit over their box, scaled to it, turned with it", function()
		local bad, n = 0, 0
		for _, b in all do
			local pieces = if b.look and b.look ~= "Picket" then LifeKit.cover(Config, b) else nil
			if b.look and b.look ~= "Picket" then
				check(pieces ~= nil and #pieces >= 1, tostring(b.look) .. " gives pieces")
			end
			-- (a ring look runs along its box's edges, not over it; a pond's rim and reeds stand round and above its
			-- water box, and the lighthouse lantern's deck overhangs its box: tests/shapes_test.luau checks those)
			-- (round 3's looks dress a box that stays, with posts, hooks and plumes past it: tests/alive_test.luau)
			local ring = b.look
				and (
					Config.ShapeArt[b.look]
						and (Config.ShapeArt[b.look].ring or Config.Life.shapes.keep[b.look] or b.look == "Lantern")
					or Config.AliveArt[b.look] ~= nil
				)
			for _, p in if ring then {} else pieces or {} do
				n += 1
				local big = math.max(b.sx, b.sy, b.sz)
				local dx, dz = math.abs(p.x - b.cx), math.abs(p.z - b.cz)
				local ok = p.size[1] > 0
					and p.size[2] > 0
					and p.size[3] > 0
					and dx <= big * 0.25 + 0.5
					and dz <= big * 0.25 + 0.5
					-- corn stands taller than its ghost row box (no collisions; the cobs ride on top)
					and math.abs(p.y - b.cy) <= b.sy * (if b.look == "CornRow" then 2 else 0.75) + 0.6
					and math.max(p.size[1], p.size[3]) <= big * 1.25 + 0.5
				if not ok then
					bad += 1
				end
				if b.ghost or b.kind == "crop" then
					check(p.collide == false, "a ghost box's look never collides")
				end
			end
		end
		check(n > 20000, string.format("%d cover pieces", n))
		check(bad == 0, string.format("every piece over its box (%d off)", bad))
		-- a crop row along z turns a quarter so its plants run down the row
		local rowZ = {
			kind = "crop",
			look = "CropRow",
			cx = 10,
			cy = 1.2,
			cz = 10,
			sx = 8,
			sy = 2,
			sz = 30,
			ghost = true,
		}
		local p = (LifeKit.cover(Config, rowZ) :: any)[1]
		check(p.size[1] > 25 and p.ry % 180 == 90, "a row along z is turned along z")
		-- a ball crown is round: the box's largest side every way
		local ball = {
			kind = "prop",
			look = "Canopy",
			shape = "ball",
			cx = 0,
			cy = 10,
			cz = 0,
			sx = 9,
			sy = 9,
			sz = 9,
		}
		local q = (LifeKit.cover(Config, ball) :: any)[1]
		check(q.size[1] > 6 and q.size[2] > 6, "a crown fills its ball")
	end)

	test("Living world: picket fences wear the picture on their long faces", function()
		local along = LifeKit.picket(Config, { look = "Picket", sx = 30, sy = 3, sz = 0.6 })
		local across = LifeKit.picket(Config, { look = "Picket", sx = 0.6, sy = 3, sz = 30 })
		check(along and along[1] == "Front" and along[2] == "Back", "along x: the front and back faces")
		check(across and across[1] == "Left" and across[2] == "Right", "along z: the side faces")
		check(LifeKit.picket(Config, { sx = 30, sy = 3, sz = 0.6 }) == nil, "no picture without the look")
		check(
			has("src/server/Services/CityBuilder.luau", 'p:SetAttribute("Picket", true)'),
			"the server marks them"
		)
		check(
			has("src/client/Fx/BuildingFx.luau", 'p:GetAttribute("Picket") == true'),
			"the street breaking still finds a hidden picket box"
		)
	end)

	test("Living world: shop fronts under the awnings, fixed sign words, in their buildings", function()
		local K = Config.City.kit
		local words: { [string]: boolean } = {}
		for _, w in K.play.shop.signs do
			words[w] = true
			check(#w <= 12 and string.upper(w) == w, w .. ": a short sign word")
		end
		local shops, awnings, signs = 0, 0, {}
		for _, b in world.hubBoxes do
			local a = b.art
			if a and a.name == "ShopFront" then
				shops += 1
				check(
					b.kind == "shop",
					"a shop front's box is its own kind (off the map, out of the street breaking)"
				)
				check(b.bid ~= nil, "a shop front is in its building (it breaks with it)")
				check(a.sign ~= nil and words[a.sign] == true, "its sign is a fixed word")
				check(a.frame ~= nil and #a.frame == 3, "its frame has a paint")
				signs[a.sign] = true
			elseif a and a.name == "Awning" then
				awnings += 1
			end
		end
		local kinds = 0
		for _ in signs do
			kinds += 1
		end
		check(
			shops >= awnings,
			string.format("a shop under every awning (%d shops, %d awnings)", shops, awnings)
		)
		check(kinds >= 20, string.format("%d different shops", kinds))
		local def = K.props.ShopFront
		for piece in def.pieces do
			check(A.ShopFront[piece] ~= nil, piece .. " has fit data")
		end
		check(
			has("src/server/Services/CityBuilder.luau", "SignKit.letter(p, a.sign"),
			"the server letters each sign"
		)
	end)

	test("Living world: vending machines on the sidewalks, clear of the other props", function()
		local K = Config.City.kit
		local list, others = {}, {}
		for _, p in world.props do
			if p.name == "VendingMachine" then
				table.insert(list, p)
				check(
					p.tint ~= nil and table.find(K.play.vending.tints, p.tint) ~= nil,
					"a machine has a tint"
				)
			else
				table.insert(others, p)
			end
		end
		check(#list >= 60, string.format("%d vending machines", #list))
		local close = 0
		for _, v in list do
			for _, o in others do
				local w = math.max(K.props[o.name].foot[1], K.props[o.name].foot[2]) / 2 + 1.9
				if math.abs(o.x - v.x) < w and math.abs(o.z - v.z) < w then
					close += 1
				end
			end
		end
		check(close == 0, string.format("no machine on another prop (%d)", close))
		check(
			has("src/client/Controllers/CityProps.luau", "CityProps.onSmash"),
			"a knocked machine tells CityLife"
		)
	end)

	test("Living world: lanes, crossings, lights and the cars' brakes", function()
		local skips = {}
		for _, v in Vehicles.place(Config) do
			if v.kind == "tram" then
				table.insert(
					skips,
					{ ax = if v.ry % 180 == 90 then "x" else "z", c = if v.ry % 180 == 90 then v.z else v.x }
				)
			end
		end
		local lanes = LifePlan.lanes(world.hubBoxes, skips)
		check(#lanes >= 14, string.format("%d lanes", #lanes))
		local D, U = Config.City.districts.Downtown, Config.City.districts.Uptown
		for _, l in lanes do
			local mid = (l.a0 + l.a1) / 2
			local x, z = if l.ax == "x" then mid else l.c, if l.ax == "x" then l.c else mid
			local inD = x >= D.minX and x <= D.maxX and z >= D.minZ and z <= D.maxZ
			local inU = x >= U.minX and x <= U.maxX and z >= U.minZ and z <= U.maxZ
			check(inD or inU, "a lane is in Downtown or Uptown")
			for _, s in skips do
				check(not (l.ax == s.ax and math.abs(l.c - s.c) < 4), "no lane down a tram line")
			end
			-- never through a building: the lane's middle line clear of every hub building body
			for _, b in world.hubBoxes do
				if b.kind == "building" and b.bid then
					local hx, hz = b.sx / 2, b.sz / 2
					if l.ax == "x" then
						if
							math.abs(l.c - b.cz) < hz - 1
							and b.cx + hx > l.a0 + 1
							and b.cx - hx < l.a1 - 1
						then
							check(false, "a lane runs through a building at " .. b.cx .. "," .. b.cz)
						end
					elseif
						math.abs(l.c - b.cx) < hx - 1
						and b.cz + hz > l.a0 + 1
						and b.cz - hz < l.a1 - 1
					then
						check(false, "a lane runs through a building at " .. b.cx .. "," .. b.cz)
					end
				end
			end
		end
		local cr = LifePlan.crossings(lanes)
		for i in lanes do
			check(#cr[i] >= 2, "every lane has crossings")
		end
		-- lights: each crossing flips between x and z over its cycle
		local T = L.traffic
		local seen: { [string]: boolean } = {}
		for t = 0, T.cycle, 0.5 do
			seen[LifePlan.green(T, t, 100, 200)] = true
		end
		check(seen.x and seen.z, "a light turns both ways in a cycle")
		-- brakes: a car 60 studs from a stop line stops before it, and gets going again
		local v, s = T.cruise, 0
		for _ = 1, 600 do
			v = LifePlan.carSpeed(T, v, 1 / 30, 60 - s)
			s += v / 30
		end
		check(s <= 60.5 and v < 0.5, string.format("stopped short (%.2f, %.2f)", s, v))
		v = LifePlan.carSpeed(T, 0, 1 / 30, nil)
		check(v > 0 and v <= T.cruise, "pulls away on green")
		-- pigeon corners on the sidewalk, manholes in the road
		local half = Config.City.downtown.street / 2 + Config.City.downtown.sidewalk / 2
		local corners = LifePlan.corners(L.pigeons, lanes, cr, half)
		local holes = LifePlan.manholes(L.steam, lanes, cr)
		check(#corners >= 20, string.format("%d pigeon corners", #corners))
		check(#holes >= 8, string.format("%d manholes", #holes))
		local inside = 0
		for _, list in { corners, holes } do
			for _, c in list do
				for _, b in world.hubBoxes do
					if
						b.kind == "building"
						and math.abs(c[1] - b.cx) < b.sx / 2
						and math.abs(c[2] - b.cz) < b.sz / 2
					then
						inside += 1
					end
				end
			end
		end
		check(inside == 0, string.format("no corner or manhole inside a building (%d)", inside))
	end)

	test("Living world: flags, waves, citizens' looks and the budgets", function()
		local info = {}
		for _, b in world.buildings do
			if b.district ~= "Outskirts" then
				table.insert(
					info,
					{ b.id, b.x, b.z, b.sx, b.sz, b.base, b.top, if (b :: any).round then 1 else 0 }
				)
			end
		end
		local flags = LifePlan.roofFlags(Config, info)
		check(#flags >= 20, string.format("%d roof flags", #flags))
		for _, f in flags do
			check(L.flags[f.district] ~= nil or f.district == "Downtown", "a flag picture for " .. f.district)
		end
		local most = 0
		for t = 0, 10, 0.1 do
			for i = 1, 8 do
				most = math.max(most, math.abs(LifePlan.wave(i, 8, t, L.flagRoofs.wind)))
			end
		end
		check(most > 0.1 and most < 0.6, string.format("a flag waves, never folds (%.2f)", most))
		local C = L.citizens
		check(LifePlan.react(C, 10, 0, false, 1, 3) == "cheer", "a cheer just after a big hit")
		check(LifePlan.react(C, 500, 0, false, math.huge, 3) == nil, "nothing for a hero far away")
		local seen: { [string]: boolean } = {}
		for k = 1, 40 do
			local r = LifePlan.react(C, 40, 80, true, math.huge, k)
			if r then
				seen[r] = true
			end
			r = LifePlan.react(C, 12, 0, false, math.huge, k)
			if r then
				seen[r] = true
			end
		end
		check(seen.point and seen.photo, "citizens point and take photos")
		for _, key in { "cars", "flocks", "steam", "flags", "flagSegs", "drones", "carRadius" } do
			local lo, me, hi = L.budget.low[key], L.budget.medium[key], L.budget.high[key]
			check(lo <= me and me <= hi, key .. ": low <= medium <= high")
		end
		check(L.budget.low.drones == 0 and L.budget.low.cars <= 4, "phones keep a small budget")
		check(
			has("src/client/Fx/CityLife.luau", 'FrameProf.wrap("CityLife", step)'),
			"CityLife runs under FrameProf"
		)
		check(has("src/client/init.client.luau", "CityLife.init()"), "the client starts CityLife")
		check(has("src/server/Services/CityBuilder.luau", "info.lanes"), "WorldInfo carries the lanes")
	end)

	test("Living world: the lore book and the Lore Shelf wear sculpted meshes", function()
		local LoreBookKit = require("../src/shared/LoreBookKit")
		local ids = serde.decode("json", fs.readFile("art/models/lorebook_meshids.json"))
		local turns = serde.decode("json", fs.readFile("art/models/meshturns.json"))
		check(
			turns.LoreBook and turns.LoreBook.verdict == "rotY180",
			"meshcheck measured Art.LoreBook turned"
		)
		check(has("src/shared/MeshFix.luau", '"LoreBook",'), "MeshFix turns Art.LoreBook back")
		local used: { [string]: boolean } = {}
		local districts = {}
		for _, d in Config.Lore.districts do
			table.insert(districts, d.id)
		end
		for _, list in { LoreBookKit.book(), LoreBookKit.shelf(districts, {}) } do
			for _, p in list do
				local m = LoreBookKit.meshOf(p.name)
				local plain = string.sub(p.name, 1, 4) == "Line" or p.name == "Halo"
				check((m ~= nil) ~= plain, p.name .. (if plain then " stays a part" else " wears a mesh"))
				if m then
					used[m] = true
					check(table.find(LoreBookKit.MESHES, m) ~= nil, m .. " is listed")
				end
			end
		end
		for _, m in LoreBookKit.MESHES do
			check(used[m] == true, m .. " is worn by a piece")
			check(ids[m] ~= nil, m .. " has an uploaded mesh id")
		end
		check(
			has("src/client/Fx/LoreBooks.luau", "MeshFix.clone(src)"),
			"Fx.LoreBooks clones through MeshFix"
		)
		check(has("src/client/Fx/LoreBooks.luau", "* MeshFix.of(part)"), "and turns each mesh back")
	end)

	test("Living world: the place has Art.Life and the tilled soil", function()
		local path = T.placePath
		if not path then
			return
		end
		local roblox = require("@lune/roblox")
		local game = roblox.deserializePlace(fs.readFile(path))
		local rs = game:GetService("ReplicatedStorage")
		local art = rs:FindFirstChild("Art")
		local life = art and art:FindFirstChild("Life")
		check(life ~= nil, "ReplicatedStorage.Art.Life is in the place")
		local names: { [string]: boolean } = {}
		if life then
			for _, d in life:GetDescendants() do
				if d.ClassName == "MeshPart" then
					names[d.Name] = true
					check(string.find(tostring((d :: any).MeshId), "%d") ~= nil, d.Name .. " has a mesh id")
				end
			end
		end
		for _, def in A.cover do
			for name in def.pieces do
				check(names[name] == true, name .. " is in Art.Life")
			end
		end
		for look, pieces in A do
			if look ~= "cover" then
				for name in pieces do
					check(names[name] == true, look .. "." .. name .. " is in Art.Life")
				end
			end
		end
		local lore = art and art:FindFirstChild("LoreBook")
		check(lore ~= nil, "ReplicatedStorage.Art.LoreBook is in the place")
		for _, m in require("../src/shared/LoreBookKit").MESHES do
			local p = lore and lore:FindFirstChild(m, true)
			check(p ~= nil and p.ClassName == "MeshPart", m .. " is in Art.LoreBook")
		end
		local ms = game:GetService("MaterialService")
		check(ms:FindFirstChild("KitTilled") ~= nil, "MaterialService has KitTilled")
	end)
end
