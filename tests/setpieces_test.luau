-- The side quests' set piece meshes (overnight queue item 10, 2026-11-18): art/blender/setpieces.py's looks over
-- the gala, the racers' meet, the farm truck and the toy shop, sea cave, Velmara and fight pit pockets. Called
-- from tests/run.luau:
--   require("./setpieces_test")({ test = test, check = check, Config = Config })
-- ONLY="Set piece art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local SetPieceKit = require("../src/shared/SetPieceKit")
	local SideQuestSets = require("../src/shared/SideQuestSets")
	local PocketLayout = require("../src/shared/PocketLayout")
	local FIT = Config.SetPieceArt

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- every group with looks: name -> { places, boxes }
	local function groups(): { [string]: { places: { any }, boxes: { any } } }
		local out = {}
		for _, id in { "gala", "meet" } do
			local s = SideQuestSets.build(id)
			out[id] = { places = s.art, boxes = s.boxes }
		end
		for _, id in { "toyshop", "seacave", "velmara", "pit" } do
			local l = PocketLayout.build(Config, 1, id)
			out[id] = { places = l.art, boxes = l.boxes }
		end
		return out
	end

	test("Set piece art: the fit table matches the set piece list, one look each, all in budget", function()
		check(type(FIT) == "table", "Config.SetPieceArt is indexed")
		local used: { [string]: boolean } = {}
		for name, g in groups() do
			check(#g.places > 0, name .. " lists its looks")
			for _, pl in g.places do
				used[pl.look] = true
				check(FIT[pl.look] ~= nil, name .. ": " .. pl.look .. " is in the fit table")
				for mesh in pl.tint or {} do
					check(
						FIT[pl.look] and FIT[pl.look][mesh] ~= nil,
						pl.look .. " tints its own mesh " .. mesh
					)
				end
			end
		end
		for chain, look in SetPieceKit.TRUCKS do
			used[look] = true
			check(SetPieceKit.fit(Config, look) ~= nil, chain .. "'s truck is in a fit table")
			local found = false
			for _, ch in Config.SideQuests.chains do
				found = found or ch.id == chain
			end
			check(found, chain .. " is a side quest chain")
		end
		local looks, meshes, total, names = 0, 0, 0, {}
		for look, fit in FIT do
			looks += 1
			check(used[look] == true, look .. " is placed somewhere")
			local tris = 0
			for name, f in fit do
				meshes += 1
				check(names[name] == nil, name .. " is one mesh name in the whole set")
				names[name] = true
				check(
					#f.size == 3 and #f.offset == 3 and #f.color == 3,
					name .. " has a size, offset and colour"
				)
				for _, s in f.size do
					check(s > 0, name .. " has a positive size")
				end
				check(type(f.mat) == "string" and #f.mat > 0, name .. " has a material")
				check(f.alpha == nil or (f.alpha > 0 and f.alpha < 1), name .. " is see-through or solid")
				check(type(f.tris) == "number" and f.tris > 0, name .. " counts its triangles")
				tris += f.tris or 0
			end
			check(tris <= 4000, look .. " is in the phone budget (" .. tris .. " tris)")
			total += tris
		end
		check(
			looks == 53 and meshes == 158,
			"53 looks in 158 meshes (the farm truck's 4 road wheels, list-combat 2026-11-20) ("
				.. looks
				.. ", "
				.. meshes
				.. ")"
		)
		check(total <= 48000, "the whole set is in budget (" .. total .. " tris)")
		check(fs.isFile("art/export/SetPieces.fbx"), "the meshes are exported for nate's import")
		check(fs.isFile("art/preview/setpieces.png"), "and previewed")
		check(has("src/config/init.luau", '"SetPieceArt"'), "the config index lists it")
	end)

	test(
		"Set piece art: each look sits over the boxes it hides, in its own piece, never over a sign",
		function()
			for name, g in groups() do
				local bad = SetPieceKit.check(Config, g.places, g.boxes)
				check(#bad == 0, name .. ": " .. table.concat(bad, "; "))
			end
			-- the check finds a look in the wrong place, a box of another piece and a box with no placement
			local s = SideQuestSets.build("gala")
			local moved = table.clone(s.art)
			moved[1] = table.clone(moved[1])
			moved[1].x += 40
			check(#SetPieceKit.check(Config, moved, s.boxes) > 0, "a look moved off its boxes is caught")
			local boxes = table.clone(s.boxes)
			table.insert(boxes, { x = 0, y = 0, z = 0, sx = 1, sy = 1, sz = 1, art = 999 })
			check(#SetPieceKit.check(Config, s.art, boxes) > 0, "a box pointing at no look is caught")
			for _, pl in s.art do
				if pl.piece then
					local wrong = table.clone(s.art)
					local i = table.find(s.art, pl) :: number
					wrong[i] = table.clone(pl)
					wrong[i].piece = nil
					check(
						#SetPieceKit.check(Config, wrong, s.boxes) > 0,
						"a look out of its breakable piece is caught"
					)
					break
				end
			end
		end
	)

	test(
		"Set piece art: before the import every box shows as today; after, only the looks' boxes hide",
		function()
			local none = function(_: string)
				return false
			end
			local all = function(_: string)
				return true
			end
			for name, g in groups() do
				local before = table.clone(g.boxes)
				-- nothing imported: nothing drawn, no box hidden (the fallback is today's parts)
				local d0 = SetPieceKit.drawn(Config, g.places, none)
				check(next(d0) == nil, name .. ": nothing drawn before the import")
				for _, b in g.boxes do
					check(not SetPieceKit.hides(b, d0), name .. ": every box shows before the import")
				end
				-- all imported: every look drawn, exactly its boxes hidden, nothing about the boxes changed
				local d1 = SetPieceKit.drawn(Config, g.places, all)
				for i in g.places do
					check(d1[i] == true, name .. ": look " .. i .. " drawn")
				end
				local hidden = 0
				for i, b in g.boxes do
					check(
						SetPieceKit.hides(b, d1) == (b.art ~= nil),
						name .. ": box " .. i .. " hides only under a look"
					)
					check(b == before[i], name .. ": the boxes themselves are untouched")
					if SetPieceKit.hides(b, d1) then
						hidden += 1
						check(not b.sign, name .. ": a sign never hides")
					end
				end
				check(hidden > 0, name .. " hides some boxes")
				-- a half import (one mesh of the first look missing) never shows half a look
				local look = g.places[1].look
				local miss = next(FIT[look])
				local half = function(n: string)
					return n ~= miss
				end
				local d2 = SetPieceKit.drawn(Config, g.places, half)
				for i, pl in g.places do
					check(
						(d2[i] == true) == (pl.look ~= look),
						name .. ": a look short of a mesh is not drawn"
					)
				end
			end
			check(SetPieceKit.truck("HarvestKing") == "FarmTruck", "the farm folk's truck has its look")
			check(
				SetPieceKit.truck("NoSuchChain") == nil and SetPieceKit.truck(nil) == nil,
				"other trucks keep the box"
			)
			check(not SetPieceKit.ready(Config, "FarmTruck", none), "the truck waits for the import")
			check(SetPieceKit.ready(Config, "FarmTruck", all), "and is drawn after it")
			-- a tint replaces only its mesh's colour; the meshes come sorted with their fit
			local m = SetPieceKit.meshes(
				Config,
				{ look = "Coral", x = 0, y = 0, z = 0, tint = { CoralBranch = { 1, 2, 3 } } }
			)
			check(#m == 1 and m[1].color[1] == 1 and m[1].size == FIT.Coral.CoralBranch.size, "a copy's tint")
		end
	)

	test("Set piece art: the services draw the meshes over hidden boxes that keep their collision", function()
		local kit = "src/server/Services/SetPieceMeshes.luau"
		check(
			has(kit, 'local ROOTS = { "SetPieces", "Vehicles", "Hideout" }'),
			"the meshes come from ReplicatedStorage.Art.SetPieces (and Art.Vehicles)"
		)
		check(
			has(kit, "SetPieceKit.drawn(Config, places, SetPieceMeshes.has)"),
			"a look needs all its meshes"
		)
		check(has(kit, "p.CanCollide = false") and has(kit, "p.CanQuery = false"), "a mesh never collides")
		local hide = string.match(fs.readFile(kit), "function SetPieceMeshes.hide.-\nend") or ""
		check(string.find(hide, "Transparency = 1", 1, true) ~= nil, "a hidden box is unseen")
		check(string.find(hide, "CanCollide", 1, true) == nil, "but keeps its collision")
		check(string.find(hide, "CanQuery", 1, true) == nil, "and its queries")
		local sq = "src/server/Services/SideQuestService.luau"
		check(has(sq, "local drawn = SetPieceMeshes.drawn(set.art)"), "the sets ask which looks are drawn")
		check(has(sq, "SetPieceKit.hides(b, drawn)"), "and hide only those boxes")
		check(
			has(sq, "setLooks(m, set, drawn, pid, CFrame.new(-pc.x, -pc.y, -pc.z))"),
			"a piece's looks in its model"
		)
		check(has(sq, "setLooks(m, set, drawn, nil, CFrame.new(origin))"), "the solid set's looks")
		check(has(sq, "SetPieceMeshes.ready(look)"), "the truck's look once imported")
		check(has(sq, 'SiteKit.prop("Motorcade"'), "the truck keeps its boxes")
		local ms = "src/server/Services/MissionService.luau"
		check(has(ms, "local drawn = SetPieceMeshes.drawn(l.art)"), "the pockets ask which looks are drawn")
		check(has(ms, "if SetPieceKit.hides(b, drawn) then"), "and hide only those boxes")
		check(has("art/blender/setpieces.py", "SetPieces.fbx"), "the script writes the FBX")
	end)
end
