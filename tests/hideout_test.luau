-- The hideout art pass (2026-11-19): the HQ room shells (the Vigil's Safehouse under the plaza, the Foundry's box
-- room, the plaza stairwell head, mission 2's wall kit) in art/blender/hideout.py's modules (Config.HideoutArt,
-- Shared.HideoutKit), and baked texture sets on the HQ's props, dressing, WANTED boards and plaques
-- (art/blender/hbake.py, Config.HqArt `maps`). Called from tests/run.luau:
--   require("./hideout_test")({ test = test, check = check, Config = Config })
-- ONLY="Hideout art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local SetPieceKit = require("../src/shared/SetPieceKit")
	local HqArtKit = require("../src/shared/HqArtKit")
	local HqRules = require("../src/shared/HqRules")
	local HideoutKit = require("../src/shared/HideoutKit")
	local PocketLayout = require("../src/shared/PocketLayout")
	local FIT = Config.HideoutArt
	local HQ = Config.HqArt

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end
	local none = function(_: string)
		return false
	end
	local all = function(_: string)
		return true
	end
	local function textured(fit: any, look: string): (boolean, string?)
		for name, f in fit[look] or {} do
			if f.mat ~= "Neon" and (f.alpha or 0) == 0 and f.maps ~= true then
				return false, name
			end
		end
		return fit[look] ~= nil, nil
	end

	test("Hideout art: the fit table holds every shell look, each with a baked texture set", function()
		check(type(FIT) == "table" and next(FIT) ~= nil, "Config.HideoutArt is generated")
		local used = HideoutKit.looks()
		for look in used do
			check(FIT[look] ~= nil, look .. " is in the fit table")
			local ok, bad = textured(FIT, look)
			check(ok, look .. " is textured (" .. tostring(bad) .. ")")
			check(
				fs.isFile("art/export/hideout/" .. look .. "_Color.png")
					and fs.isFile("art/export/hideout/" .. look .. "_Normal.png"),
				look .. "'s texture set is on disk"
			)
		end
		local names: { [string]: string } = {}
		for _, other in { Config.SetPieceArt or {}, Config.VehicleArt or {}, HQ or {} } do
			for look, fit in other do
				for name in fit do
					names[name] = look
				end
			end
		end
		for look, fit in FIT do
			check(used[look] == true, look .. " is used somewhere")
			local tris = 0
			for name, f in fit do
				check(names[name] == nil, name .. " is one mesh name across every set")
				check(
					#f.size == 3 and #f.offset == 3 and #f.color == 3,
					name .. " has a size, offset and colour"
				)
				check(type(f.tris) == "number" and f.tris > 0, name .. " counts its triangles")
				tris += f.tris
			end
			check(tris <= 2000, look .. " is a light module (" .. tris .. " tris)")
		end
		check(fs.isFile("art/export/Hideout.fbx"), "the modules are exported")
		check(fs.isFile("art/preview/hideout.png"), "and previewed")
		check(
			has("default.project.json", "art/models/Hideout.rbxm"),
			"the uploaded model is mapped as Art.Hideout"
		)
		check(fs.isFile("art/models/Hideout.rbxm"), "and pulled into the repo")
	end)

	test("Hideout art: every prop kind has meshes, fit data and a baked texture set", function()
		local function look(name: string)
			check(HQ[name] ~= nil, name .. " has meshes")
			local ok, bad = textured(HQ, name)
			check(ok, name .. " is textured (" .. tostring(bad) .. ")")
			local mapped = false
			for _, f in HQ[name] or {} do
				mapped = mapped or f.maps == true
			end
			-- an all-Neon look (the screen crown) glows flat and has nothing to bake
			check(
				not mapped or fs.isFile("art/export/hq/" .. name .. "_Color.png"),
				name .. "'s texture set is on disk"
			)
		end
		local collections, pass = 0, 0
		for bit = 1, 22 do
			look(HqArtKit.PROPS[bit])
			if bit >= 7 and bit <= 18 then
				collections += 1
			elseif bit >= 19 then
				pass += 1
			end
		end
		check(collections == 12 and pass == 4, "the 12 collection props and 4 pass props")
		for _, tag in { "V", "S" } do
			for _, d in HqArtKit.DRESS[tag] do
				look(d.look)
			end
			for _, name in { "HqWantedBoard", "HqPlaque", "HqMount", "HqTrophyWall", "HqPlinth", "HqPad" } do
				look(name .. tag)
			end
		end
		look(HqArtKit.NAMEPLATE)
		-- the tinted bodies keep their game colour: see-through texels, and HqClient passes the tint
		for _, name in { "HqPlaqueVBody", "HqPlaqueSBody" } do
			local f = HQ[string.sub(name, 1, 9)][name]
			check(f.maps == true, name .. " is textured and tinted")
		end
		-- the stretched shapes and the dummy's body take their part's colour: flat
		for _, l in { HqArtKit.DUMMY, HqArtKit.BODY, HqArtKit.NEMESIS } do
			for name, f in HQ[l] do
				check(f.maps ~= true, name .. " stays flat (its part's colour)")
			end
		end
		check(
			has("src/client/Fx/HqMeshes.luau", 'm.maps and c:IsA("SurfaceAppearance")'),
			"HqMeshes keeps the maps"
		)
	end)

	local STRICT = { HideWall = true, HideRun = true, HideBeam = true, HideFloor = true }
	-- the axis-aligned box of a placement's meshes
	local function box(pl: any): ({ number }, { number })
		return SetPieceKit.bounds(Config, pl)
	end

	test("Hideout art: the Safehouse's modules cover its pieces, the glowing faces stay", function()
		local pieces = HqRules.hideout(Config)
		for _, preset in Config.Presets.order do
			local places, hides = HideoutKit.cell(Config, pieces, preset)
			local skip = Config.Hq.art.skip[preset]
			for i, p in pieces do
				local look = HideoutKit.PIECES[p.name]
				if p.glow or p.name == "mapScreen" then
					check(hides[i] == nil, preset .. ": " .. p.name .. " stays a part")
				elseif
					look
					and not skip[look]
					and not (p.name == "shaft" and p.sy < 2 and skip.HideCeiling)
				then
					check(
						hides[i] ~= nil and places[hides[i]] ~= nil,
						preset .. ": " .. p.name .. " " .. i .. " is covered"
					)
				end
			end
			for k, pl in places do
				check(FIT[pl.look] ~= nil, preset .. ": placement " .. k .. " is a known look")
				check(not skip[pl.look], preset .. ": " .. pl.look .. " is not skipped")
			end
		end
		-- every module stays inside the room and sits over the pieces of its own kind
		local places, hides = HideoutKit.cell(Config, pieces, "high")
		local half = Config.Hq.cell.size / 2
		local byPlace: { [number]: { any } } = {}
		for i, k in hides do
			byPlace[k] = byPlace[k] or {}
			table.insert(byPlace[k], pieces[i])
		end
		for k, pl in places do
			local lo, hi = box(pl)
			check(
				lo[1] >= -half - 1.5 and hi[1] <= half + 1.5 and lo[3] >= -half - 1.5 and hi[3] <= half + 1.5,
				pl.look .. " " .. k .. " stays in the cell"
			)
			-- the modules seen up close are stretched at most 6% along a wall or floor; the ceiling's and the
			-- shaft's tiles fill odd strips
			local s = pl.scale or { 1, 1, 1 }
			local tight = STRICT[pl.look]
			for a = 1, 3 do
				local ok = if tight
					then (a == 2 or (s[a] > 0.94 and s[a] < 1.06))
					else (s[a] > 0.3 and s[a] < 1.2)
				check(ok, pl.look .. " " .. k .. " stretch on axis " .. a .. " (" .. s[a] .. ")")
			end
			local mine = byPlace[k]
			if mine then
				-- the module is over the pieces it hides (their joint box, 3 studs slack)
				local px0, px1, pz0, pz1 = math.huge, -math.huge, math.huge, -math.huge
				for _, p in mine do
					px0, px1 = math.min(px0, p.x - p.sx / 2 - 3), math.max(px1, p.x + p.sx / 2 + 3)
					pz0, pz1 = math.min(pz0, p.z - p.sz / 2 - 3), math.max(pz1, p.z + p.sz / 2 + 3)
				end
				local mx, mz = (lo[1] + hi[1]) / 2, (lo[3] + hi[3]) / 2
				check(
					mx >= px0 and mx <= px1 and mz >= pz0 and mz <= pz1,
					pl.look .. " " .. k .. " is over " .. mine[1].name
				)
			end
		end
		-- the wall bays face the room: a module's front (-z) turned by ry points toward the middle
		for _, pl in places do
			if pl.look == "HideWall" then
				local a = math.rad(pl.ry or 0)
				local fx, fz = -math.sin(a), -math.cos(a)
				check(fx * -pl.x + fz * -pl.z > 0, "a wall bay at " .. pl.x .. "," .. pl.z .. " faces in")
			end
		end
	end)

	test("Hideout art: the Foundry's walls, floor and rug, and the stairwell head", function()
		local main = HqArtKit.COLORS.villain.main
		local places, hides = HideoutKit.foundry(Config, main, "high")
		local boxes = HideoutKit.foundryBoxes(Config)
		for i, b in boxes do
			check(hides[i] ~= nil, "the Foundry's " .. b.name .. " " .. i .. " is covered")
		end
		local walls, rug = 0, 0
		for _, pl in places do
			if pl.look == "FoundryWall" then
				walls += 1
			elseif pl.look == "FoundryRug" then
				rug += 1
				check(pl.tint and pl.tint.FoundryRugBody == main, "the rug takes the side's colour")
				check(FIT.FoundryRug.FoundryRugBody.maps == true, "through its see-through weave")
			end
		end
		check(walls == 40, "ten iron bays a wall (" .. walls .. ")")
		check(rug == 16, "a 4 by 4 rug")
		-- the stairwell head: its look round today's head box (Config.Hq.door.size, its foot at the door)
		local w, h, d = table.unpack(Config.Hq.door.size)
		local lo, hi = box(HideoutKit.stairHead())
		check(lo[1] >= -w / 2 - 1 and hi[1] <= w / 2 + 1, "the head look is the head's width")
		check(lo[3] >= -1.5 and hi[3] <= d + 1, "and depth (the door side at the front)")
		check(lo[2] >= -0.01 and hi[2] <= h + 3, "and height (the roof's vent on top)")
		local svc = fs.readFile("src/server/Services/HqService.luau")
		for _, name in HideoutKit.HEAD_PARTS do
			check(string.find(svc, '"' .. name .. '"', 1, true) ~= nil, "HqService builds " .. name)
		end
		check(
			string.find(svc, "SetPieceMeshes.hide(p)", 1, true) ~= nil,
			"the parts are hidden, never removed"
		)
		local hide = string.match(
			fs.readFile("src/server/Services/SetPieceMeshes.luau"),
			"function SetPieceMeshes.hide.-\nend"
		) or ""
		check(string.find(hide, "CanCollide", 1, true) == nil, "a hidden part still collides")
	end)

	test("Hideout art: the colliding geometry is unchanged", function()
		-- the Safehouse's pieces are exactly as before the art pass (positions and sizes; the cell's real walls and
		-- floor are the server's invisible parts, untouched)
		local n, s = 0, 0
		for _, p in HqRules.hideout(Config) do
			n += 1
			s += p.x * 3 + p.y * 5 + p.z * 7 + p.sx * 11 + p.sy * 13 + p.sz * 17
		end
		check(
			n == 128 and math.abs(s - 67138.6765) < 1e-3,
			"the hideout's pieces as before (" .. n .. ", " .. s .. ")"
		)
		local D = Config.Hq.door.size
		check(D[1] == 10 and D[2] == 11 and D[3] == 8, "the stairwell head's size as before")
		-- mission 2's tunnels: the wall kit's long pieces cut into module-long ghost boxes, same total length
		local l = PocketLayout.build(Config, 1, "dungeon")
		local bad = SetPieceKit.check(Config, l.art, l.boxes)
		check(#bad == 0, "the tunnels' looks sit over their boxes: " .. table.concat(bad, "; "))
		local runs, lamps, len = 0, 0, 0
		for _, pl in l.art do
			if pl.look == "HideRun" then
				runs += 1
			elseif pl.look == "HideLamp" then
				lamps += 1
			end
		end
		for _, b in l.boxes do
			if b.art and l.art[b.art].look == "HideRun" then
				check(b.ghost == true and b.tag == "decor", "a cut kit box is ghost decor")
				len += b.sx
			end
		end
		check(runs == 62 and lamps > 0, "two runs of modules and the lamps (" .. runs .. ", " .. lamps .. ")")
		check(math.abs(len - 376 * 5 * 2) < 1e-6, "the cut boxes add up to the five long pieces of both runs")
		local d0 = SetPieceKit.drawn(Config, l.art, none)
		check(next(d0) == nil, "before the import every box shows")
		local d1 = SetPieceKit.drawn(Config, l.art, all)
		check(d1[1] == true, "after it the modules draw")
	end)

	test("Hideout art: each preset's shell is in its budget", function()
		local pieces = HqRules.hideout(Config)
		local B = Config.Hq.art.budget
		local lastParts = math.huge
		for i = #Config.Presets.order, 1, -1 do
			local preset = Config.Presets.order[i]
			local b = B[preset]
			check(b ~= nil, preset .. " has a budget")
			local cp, ct = HideoutKit.cost(Config, (HideoutKit.cell(Config, pieces, preset)))
			local fp, ft = HideoutKit.cost(Config, (HideoutKit.foundry(Config, { 1, 2, 3 }, preset)))
			check(
				cp <= b.parts and ct <= b.tris,
				preset .. ": the Safehouse " .. cp .. " parts, " .. ct .. " tris"
			)
			check(
				fp <= b.parts and ft <= b.tris,
				preset .. ": the Foundry " .. fp .. " parts, " .. ft .. " tris"
			)
			check(cp <= lastParts, preset .. " draws no more than the preset above")
			lastParts = cp
		end
		check(Config.Hq.art.skip.low.HideCeiling == true, "phones keep the ceiling plain")
	end)

	test("Hideout art: the client and server draw the shells over hidden parts", function()
		local hq = "src/client/Controllers/HqClient.luau"
		for _, needle in
			{
				"HideoutKit.cell(Config, pieces, QualityController.name)",
				"HideoutKit.foundry(Config, tint(colors.main), QualityController.name)",
				"HqMeshes.put(f, pl, c)",
				"HqMeshes.hide(p)",
			}
		do
			check(has(hq, needle), "HqClient: " .. needle)
		end
		check(has("src/client/Fx/HqMeshes.luau", 'ROOTS = { "Hq", "Hideout"'), "HqMeshes finds Art.Hideout")
		check(has("src/server/Services/SetPieceMeshes.luau", '"Hideout"'), "and the server's set pieces")
		check(
			has("src/server/Services/HqService.luau", "HideoutKit.stairHead()"),
			"HqService dresses the head"
		)
		-- a half import never draws half a module
		local places = HideoutKit.cell(Config, HqRules.hideout(Config), "high")
		local miss = next(FIT.HideRun)
		local d = SetPieceKit.drawn(Config, places, function(n: string)
			return n ~= miss
		end)
		for i, pl in places do
			check((d[i] == true) == (pl.look ~= "HideRun"), "a module short of a mesh is not drawn")
		end
	end)
end
