-- The living world's round 2 (shapes-2, 2026-11-19, nate: "you still use way too many simple shapes and textures"):
-- Art.Shapes looks (Config.ShapeArt, art/blender/shapes.py) over the plain props, roofs' mouldings (LifeKit.roofs),
-- road pictures (zebra crossings, drains), the pools' water, the lit windows after dusk (Shared.LitPlan,
-- Fx.LitWindows) and Uptown's calmer palette. Called from tests/run.luau:
--   require("./shapes_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="Shapes" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local LifeKit = require("../src/shared/LifeKit")
	local LitPlan = require("../src/shared/LitPlan")
	local SA = Config.ShapeArt
	local SH = Config.Life.shapes
	local LIT = Config.Life.lit

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	local all = {}
	for _, b in world.hubBoxes do
		table.insert(all, b)
	end
	for _, p in world.tilePlans do
		for _, b in p.boxes do
			table.insert(all, b)
		end
	end
	for _, lm in world.landmarks or {} do
		for _, b in lm.boxes or {} do
			table.insert(all, b)
		end
	end

	test("Shapes: every look has meshes with sizes, and every mesh an uploaded id in a fitted set", function()
		local ids = serde.decode("json", fs.readFile("art/models/shapes_meshids.json"))
		local n = 0
		for look, def in SA do
			check(
				#def.frame == 3 and def.frame[1] > 0 and def.frame[2] > 0 and def.frame[3] > 0,
				look .. " has a frame"
			)
			for name, m in def.meshes do
				n += 1
				check(m.size[1] > 0 and m.size[2] > 0 and m.size[3] > 0, look .. "." .. name .. " has a size")
				check(#m.color == 3, look .. "." .. name .. " has a colour")
				check(ids[name] ~= nil, name .. " has an uploaded mesh id")
				check(Config.LifeArt.cover[name] == nil, name .. " is not also a living-world look")
			end
		end
		check(n >= 55, "the set has its meshes (" .. n .. ")")
		check(
			has("default.project.json", '"Shapes": { "$path": "art/models/Shapes.rbxm" }'),
			"Art.Shapes is mapped"
		)
		check(fs.isFile("art/models/Shapes.rbxm"), "the pulled model is in the repo")
		check(has("src/shared/MeshFix.luau", '"Shapes"'), "MeshFix knows the set's turn")
		local turns = serde.decode("json", fs.readFile("art/models/meshturns.json"))
		check(turns.Shapes ~= nil, "meshturns.json has the set (art/upload/meshcheck.py)")
		for _, r in SH.rocks do
			check(SA[r] ~= nil, "rock shape " .. r .. " is a look")
		end
		for name in SH.soft do
			local found = false
			for _, def in SA do
				found = found or def.meshes[name] ~= nil
			end
			check(found, "soft piece " .. name .. " is a mesh")
		end
	end)

	test("Shapes: the world tags its plain things with looks the sets know", function()
		local counts = LifeKit.count(Config, all)
		for look, k in counts do
			-- (Picket is a picture on its box: LifeKit.picket)
			check(
				look == "Picket" or SA[look] ~= nil or Config.LifeArt.cover[look] ~= nil,
				look .. " (" .. k .. " boxes) is a known look"
			)
		end
		-- the round's looks are used: every Shapes look is in the world at least once
		for look in SA do
			check((counts[look] or 0) > 0, look .. " is used in the world")
		end
		check(
			(counts.CorniceRun or 0) + (counts.RoofEdge or 0) + (counts.Parapet or 0) > 50,
			"the roofs are dressed"
		)
		for _, b in all do
			if b.look == "Parapet" then
				check(math.min(b.sx, b.sz) <= 2, "a parapet look is on a thin ledge")
			end
		end
	end)

	test("Shapes: a prop look fills its box; a ring look runs round its edges, faces out", function()
		-- a rock fills its box, turned by hash, collides
		local rock =
			{ kind = "prop", look = "Rock", cx = 10, cy = 2, cz = 30, sx = 5, sy = 4, sz = 5, color = "rock" }
		local pcs = LifeKit.cover(Config, rock)
		check(pcs ~= nil and #pcs >= 1, "a rock has pieces")
		for _, p in pcs or {} do
			check(p.set == SH.set and p.collide, "a rock's piece is from the set and collides")
		end
		-- a cornice run: four runs of each mesh, outside the box, soft (visual only)
		local cap = {
			kind = "ledge",
			look = "CorniceRun",
			cx = 0,
			cy = 50,
			cz = 0,
			sx = 30,
			sy = 1.2,
			sz = 20,
			color = "cornice",
		}
		local def = SA.CorniceRun
		check(def.ring == true, "a cornice is a ring look")
		local nm = 0
		for _ in def.meshes do
			nm += 1
		end
		local runs = LifeKit.cover(Config, cap) or {}
		check(#runs == 4 * nm, "four runs a mesh")
		check(LifeKit.keeps(Config, cap), "the cap stays under its moulding")
		local turns = {}
		for _, p in runs do
			check(not p.collide, "a moulding never collides")
			turns[p.ry] = true
			if p.ry == 0 then
				check(p.z < -cap.sz / 2 + def.frame[3], "the -z run sits on the -z edge")
			elseif p.ry == 180 then
				check(p.z > cap.sz / 2 - def.frame[3], "the +z run sits on the +z edge")
			elseif p.ry == 90 then
				check(p.x < -cap.sx / 2 + def.frame[3], "the -x run (turned 90) sits on the -x edge")
			elseif p.ry == -90 then
				check(p.x > cap.sx / 2 - def.frame[3], "the +x run (turned -90) sits on the +x edge")
			end
		end
		check(turns[0] and turns[180] and turns[90] and turns[-90], "one run a side")
		-- a long thin look follows its box's long side
		local wood =
			{ kind = "prop", look = "Driftwood", cx = 0, cy = 0.6, cz = 0, sx = 1.2, sy = 1.2, sz = 10 }
		for _, p in LifeKit.cover(Config, wood) or {} do
			check(p.ry == 90, "driftwood along z is turned a quarter")
		end
		-- roofs: a fresh list's ledges get looks once, art and tagged boxes stay
		local boxes = {
			{ kind = "ledge", color = "cornice", sx = 20, sy = 1, sz = 20, cx = 0, cy = 0, cz = 0 },
			{ kind = "ledge", color = "roof", sx = 1.5, sy = 2, sz = 20, cx = 0, cy = 0, cz = 0 },
			{ kind = "ledge", color = "roof", sx = 20, sy = 2, sz = 20, cx = 0, cy = 0, cz = 0 },
			{
				kind = "ledge",
				color = "roof",
				sx = 20,
				sy = 2,
				sz = 20,
				cx = 0,
				cy = 0,
				cz = 0,
				tag = "beam",
			},
		}
		check(LifeKit.roofs(Config, boxes) == 3, "three ledges dressed")
		check(
			boxes[1].look == "CorniceRun" and boxes[1].kit == SH.roofKit,
			"a cornice cap gets the run and the roof kit"
		)
		check(boxes[2].look == "Parapet" and boxes[2].kit == nil, "a thin ledge is a parapet")
		check(boxes[3].look == "RoofEdge", "a flat cap gets the roof edge")
		check(boxes[4].look == nil, "a tagged ledge stays")
		check(LifeKit.roofs(Config, boxes) == 0, "dressing twice changes nothing")
	end)

	test("Shapes: lit windows tile from a face's centre like the kit fronts", function()
		for _, wh in { { 40, 60 }, { 48, 48 }, { 13, 100 }, { 96, 12 }, { 201, 37 } } do
			local w, h = wh[1], wh[2]
			local L = LitPlan.layout(w, h, LIT.block, LIT.pps)
			check(L.cw == w * LIT.pps and L.ch == h * LIT.pps, "the canvas is the face")
			check(
				L.x <= 0 and L.x > -L.tile and L.y <= 0 and L.y > -L.tile,
				"the label starts at or before the canvas"
			)
			check(math.abs(((L.cw / 2 - L.x) / L.tile) % 1) < 1e-9, "a tile edge on the vertical centre line")
			check(
				math.abs(((L.ch / 2 - L.y) / L.tile) % 1) < 1e-9,
				"a tile edge on the horizontal centre line"
			)
			check(L.x + L.sw >= L.cw and L.y + L.sh >= L.ch, "the label covers the canvas")
		end
		check(#LitPlan.faces(40, 60, 8, LIT.minFace) == 2, "a narrow side stays dark")
		check(#LitPlan.faces(40, 60, 40, LIT.minFace) == 4, "four wide sides")
		check(LitPlan.night(22, LIT.from, LIT.to) and LitPlan.night(3, LIT.from, LIT.to), "lit at night")
		check(
			not LitPlan.night(12, LIT.from, LIT.to) and not LitPlan.night(6.5, LIT.from, LIT.to),
			"dark by day"
		)
		-- every front the city uses has a lit picture, drawn and uploaded
		for area, rows in Config.City.kit.fronts do
			for key, list in rows do
				for _, f in list do
					check(
						LIT.images[f] ~= nil,
						area .. "." .. key .. "'s front " .. f .. " has a lit picture"
					)
				end
			end
		end
		for f, id in LIT.images do
			check(fs.isFile("art/export/city/lit/Lit" .. f .. ".png"), "Lit" .. f .. ".png is drawn")
			check(id ~= 0, "Lit" .. f .. " is uploaded")
		end
		for _, p in LIT.budget do
			check(p.radius > 0 and p.faces > 0 and p.faces <= 120, "a preset's lit budget")
		end
		check(has("src/client/Fx/LitWindows.luau", "FrameProf"), "the lit windows' pass is profiled")
		check(has("src/client/Fx/WaterSurface.luau", "FrameProf"), "the water's drift is profiled")
		check(
			has("src/client/init.client.luau", "LitWindows")
				and has("src/client/init.client.luau", "WaterSurface"),
			"both start"
		)
	end)

	test("Shapes: road pictures, pool water and Uptown's calm palette", function()
		local zebras, drains = 0, 0
		for _, b in world.hubBoxes do
			if b.decal == "Zebra" then
				zebras += 1
			elseif b.decal == "Drain" then
				drains += 1
			end
			if b.decal then
				check(SH.decals[b.decal] ~= nil, b.decal .. " is a known picture")
			end
		end
		check(
			zebras > 20 and drains > 20,
			"crossings and drains on the streets (" .. zebras .. ", " .. drains .. ")"
		)
		for name, id in SH.decals do
			check(id ~= 0, name .. " is uploaded")
		end
		check(SH.water.image ~= 0, "the water's ripple is uploaded")
		check(has("src/server/Services/CityBuilder.luau", '"LifeWater"'), "the builder tags the water")
		local pools = 0
		for _, b in all do
			if b.look == "PoolEdge" then
				pools += 1
			end
		end
		check(pools > 0, "pools have their coping")
		-- Uptown (nate: "crazy colors and textures"): its tints are muted (HSV saturation under 0.42)
		for key, c in Config.City.palette do
			if string.sub(key, 1, 2) == "up" then
				local mx, mn = math.max(c[1], c[2], c[3]), math.min(c[1], c[2], c[3])
				check(mx > 0 and (mx - mn) / mx < 0.42, key .. " is a calm tint")
			end
		end
	end)
end
