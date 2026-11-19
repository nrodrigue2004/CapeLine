-- The pocket props and the plaza board's art pass (gap-props2, 2026-11-19): art/blender/pocketprops.py's meshes over
-- the pockets' most-seen props (Shared.PocketPropKit, Config.PocketProps, PocketDecor) and art/blender/board.py's
-- look round the weekly board's screen (Shared.BoardArtKit, BoardService), with every box's collision as before.
-- Called from tests/run.luau:
--   require("./pocket_props_test")({ test = test, check = check, Config = Config, placePath = placePath })
-- ONLY="Pocket props" or ONLY="Board art" runs just these.
-- gap-props3 (2026-11-19): the second set (Config.PocketPropArt2, Art.PocketProps2: blackboards, hoops, Halo's
-- statue, the bookcase, the conveyor and half-built robots, trophy shelves, the bench, wooden dummies, the sealed and
-- iron doors, Hoshi's cage and chains, the roll door, scanner arch, dock crates, the stations, the tower mast and
-- Live's stage) checked the same way, with its "keep" boxes and box-turned chains.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local PocketLayout = require("../src/shared/PocketLayout")
	local PocketDress = require("../src/shared/PocketDress")
	local PocketPropKit = require("../src/shared/PocketPropKit")
	local BoardArtKit = require("../src/shared/BoardArtKit")

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function layouts(): { string }
		local out = {}
		for _, r in Config.PocketProps.rules do
			if not table.find(out, r.layout) then
				table.insert(out, r.layout)
			end
		end
		table.sort(out)
		return out
	end
	local function built(index: number, layout: string): (any, any)
		local l = PocketLayout.build(Config, index, layout)
		return l, PocketDress.apply(Config, l, layout)
	end
	local function allReady(): { [string]: boolean }
		return PocketPropKit.readyLooks(Config, function()
			return true
		end)
	end

	test("Pocket props: every rule finds its props and every look is built for its boxes", function()
		local kinds = {}
		local total = 0
		for _, layout in layouts() do
			check(PocketLayout.known(layout), "a real pocket: " .. layout)
			for _, index in { 1, Config.Story.pockets.count } do
				local l, dress = built(index, layout)
				local bad = PocketPropKit.check(Config, l, dress, layout)
				check(#bad == 0, layout .. " " .. index .. ": " .. table.concat(bad, "; "))
				if index == 1 then
					for _, p in PocketPropKit.places(Config, l, dress, layout) do
						kinds[(string.gsub(p.look, "%u%l+$", ""))] = true
						total += 1
					end
				end
			end
		end
		check(total >= 215, "the props drawn as meshes: " .. total)
		local used = {}
		for _, r in Config.PocketProps.rules do
			used[r.look] = true
			check(
				PocketPropKit.all(Config)[r.look] ~= nil,
				r.look .. " has its meshes (art/blender/pocketprops.py)"
			)
		end
		for look in PocketPropKit.all(Config) do
			check(used[look] == true, look .. " is placed by a rule")
		end
		-- the pockets the task named all get props; the subway (the prologue's) is never touched
		for _, layout in { "academy", "pound", "ashlab", "ironhall", "arena", "rooftops", "station", "tower" } do
			check(table.find(layouts(), layout) ~= nil, layout .. " has props")
		end
		check(table.find(layouts(), "subway") == nil, "the prologue's subway is left as it is")
		-- the second set: its own fit table, none of its looks in the first (the first upload is unchanged)
		local second = {
			PkStatue = 1,
			PkBlackboard = 2,
			PkHoop = 2,
			PkBookcase = 1,
			PkConveyor = 1,
			PkHalfBot = 7,
			PkTrophyShelf = 1,
			PkBench = 1,
			PkWoodDummy = 2,
			PkIronDoor = 1,
			PkSealDoor = 1,
			PkHoshiCage = 1,
			PkChain = 4,
			PkRollDoor = 1,
			PkScanArch = 1,
			PkDockCrate = 2,
			PkStation = 3,
			PkMast = 1,
			PkStage = 1,
		}
		for look, n in second do
			check(Config.PocketPropArt2[look] ~= nil, look .. " is in the second set")
			check(Config.PocketPropArt[look] == nil, look .. " is not in the first set")
			local found = 0
			for _, r in Config.PocketProps.rules do
				if r.look == look then
					found += r.count
				end
			end
			check(found == n, string.format("%s: %d placements, wants %d", look, found, n))
		end
		for look in Config.PocketPropArt2 do
			check(second[look] ~= nil, look .. " is one of the second set's looks")
		end
	end)

	test("Pocket props: keep boxes stay drawn, chains turn with their boxes", function()
		local l, dress = built(1, "arena")
		local stage
		for _, p in PocketPropKit.places(Config, l, dress, "arena") do
			if p.look == "PkStage" then
				stage = p
			end
		end
		check(stage ~= nil and stage.keep ~= nil and #stage.keep == 1, "the stage frames the giant screen")
		if stage and stage.keep then
			local scr = l.boxes[stage.keep[1]]
			check(scr.kind == "glow" and scr.sx == 140, "the kept box is the giant screen")
			check(table.find(stage.boxes, stage.keep[1]) == nil, "the screen is never hidden")
			check(#stage.boxes == 1 and l.boxes[stage.boxes[1]].sx == 120, "only the deck is hidden")
		end
		local src = fs.readFile("src/client/Controllers/PocketDecor.luau")
		check(not has(src, "p.keep"), "PocketDecor hides only a place's boxes")
		local li, di = built(1, "ironhall")
		local turns = {}
		for _, p in PocketPropKit.places(Config, li, di, "ironhall") do
			if p.look == "PkChain" then
				local b = li.boxes[p.boxes[1]]
				check(p.ry == b.ry, "a chain turns with its box")
				turns[p.ry] = true
			end
		end
		check(turns[45] and turns[-45], "both diagonals")
	end)

	test(
		"Pocket props: collision unchanged (no box moved, resized, added, dropped or made solid or ghost)",
		function()
			local FIELDS =
				{ "kind", "cx", "cy", "cz", "sx", "sy", "sz", "ry", "shape", "ghost", "tag", "color" }
			for _, layout in layouts() do
				local plain = PocketLayout.build(Config, 3, layout)
				local l, dress = built(3, layout)
				local before = #dress.extras
				local places = PocketPropKit.places(Config, l, dress, layout)
				for _, preset in { "low", "medium", "high" } do
					PocketPropKit.pick(Config, places, preset, allReady())
				end
				check(#l.boxes == #plain.boxes, layout .. ": the same boxes")
				check(#dress.extras == before, layout .. ": the dressing untouched")
				for i, b in plain.boxes do
					local c = l.boxes[i] :: any
					for _, f in FIELDS do
						check((b :: any)[f] == c[f], string.format("%s box %d %s unchanged", layout, i, f))
					end
				end
				-- solid boxes covered by a look stay solid (the camera rigs are cover)
				for _, p in places do
					if not p.dress then
						for _, j in p.boxes do
							check(
								l.boxes[j].ghost == plain.boxes[j].ghost,
								p.look .. " keeps its box's solidity"
							)
						end
					end
				end
			end
			local la, da = built(1, "arena")
			local arena = PocketPropKit.places(Config, la, da, "arena")
			local solid = 0
			for _, p in arena do
				if p.look == "PkCamera" then
					for _, j in p.boxes do
						solid += if la.boxes[j].ghost then 0 else 1
					end
				end
			end
			check(solid == 6, "Live's camera rigs are still solid cover: " .. solid)
			-- the device only hides (a local transparency), never removes or changes a server part's collision
			local src = fs.readFile("src/client/Controllers/PocketDecor.luau")
			check(
				has(src, "LocalTransparencyModifier = 1") and has(src, "LocalTransparencyModifier = 0"),
				"hide and show"
			)
			check(
				has(src, "PocketPropKit.pick(") and has(src, "PocketPropKit.places("),
				"PocketDecor draws the picks"
			)
			check(not has(src, "CanCollide = true"), "nothing made solid")
			check(
				has(src, "p.CanCollide = false") and has(src, "p.CanQuery = false"),
				"the meshes are ghosts"
			)
			check(not has(src, "RenderStepped"), "no per-frame loop")
			local ms = fs.readFile("src/server/Services/MissionService.luau")
			check(not has(ms, "PocketPropKit"), "the server builds every box as before")
		end
	)

	test("Pocket props: drawn only once imported, dressing by tier, a mesh budget per preset", function()
		local l, dress = built(1, "academy")
		local places = PocketPropKit.places(Config, l, dress, "academy")
		check(#PocketPropKit.pick(Config, places, "high", {}) == 0, "nothing imported: nothing drawn")
		local half = {}
		for look in PocketPropKit.all(Config) do
			half[look] = look ~= "PkDesk"
		end
		for _, p in PocketPropKit.pick(Config, places, "high", half) do
			check(p.look ~= "PkDesk", "a look missing a mesh is never drawn")
		end
		local missing = PocketPropKit.ready(Config, "PkDesk", function(name)
			return name ~= "PkDeskBody"
		end)
		check(not missing, "a half import never shows half a look")
		local prev = -1
		for _, preset in { "low", "medium", "high" } do
			local budget = Config.Presets[preset].pockets.props
			check(type(budget) == "number" and budget > prev, preset .. " has a bigger mesh budget")
			prev = budget
			for _, layout in layouts() do
				local ll, dd = built(1, layout)
				local pl = PocketPropKit.places(Config, ll, dd, layout)
				local a = PocketPropKit.pick(Config, pl, preset, allReady())
				local b = PocketPropKit.pick(Config, pl, preset, allReady())
				local used = 0
				for i, p in a do
					used += PocketPropKit.cost(Config, p)
					check(b[i] and b[i].look == p.look and b[i].cx == p.cx, "the same picks every time")
					if p.dress then
						check(
							p.tier <= Config.Presets[preset].pockets.tier,
							preset .. ": dressing within its tier"
						)
					end
				end
				check(
					used <= budget,
					string.format("%s %s: %d meshes within %d", preset, layout, used, budget)
				)
			end
		end
		-- the high preset draws every Academy prop; phones the layout's own props within their budget
		local low = PocketPropKit.pick(Config, places, "low", allReady())
		local desks = 0
		for _, p in low do
			check(not p.dress, "phones draw no dressing looks (tier 1)")
			desks += if p.look == "PkDesk" then 1 else 0
		end
		check(desks > 0, "phones still get the classroom desks")
		check(#PocketPropKit.pick(Config, places, "high", allReady()) == #places, "high draws them all")
		-- gap-props3: phones (low, 64 meshes) draw every layout prop of every pocket, the second set's too
		for _, layout in layouts() do
			local ll, dd = built(1, layout)
			local pl = PocketPropKit.places(Config, ll, dd, layout)
			local want = 0
			for _, p in pl do
				want += if p.dress then 0 else 1
			end
			local got = PocketPropKit.pick(Config, pl, "low", allReady())
			check(#got == want, string.format("low %s: %d of %d layout props", layout, #got, want))
		end
	end)

	test("Pocket props: the fit data (meshes, tints, triangles, no faces)", function()
		local names = {}
		local tris = 0
		local setTris = { 0, 0 }
		for look, fit in PocketPropKit.all(Config) do
			check(#fit.frame == 3, look .. " has a frame")
			local lt = 0
			local tinted = false
			for name, m in fit.meshes do
				check(names[name] == nil, "mesh names are unique: " .. name)
				names[name] = true
				check(string.sub(name, 1, #look) == look, name .. " is named after its look")
				-- faces and hair are Roblox catalog items: never modelled (case-sensitive: a Chair is fine)
				check(
					not string.find(name, "Face") and not string.find(name, "Hair"),
					"no face or hair: " .. name
				)
				lt += m.tris or 0
				tinted = tinted or m.tint == true
				if m.mat == "Neon" or m.mat == "Glass" then
					check(not m.maps, name .. ": glow and glass stay flat")
				end
			end
			check(lt > 0 and lt <= 4000, look .. " is light enough for phones: " .. lt)
			tris += lt
			local k = if Config.PocketPropArt2[look] then 2 else 1
			setTris[k] += lt
			local rule
			for _, r in Config.PocketProps.rules do
				if r.look == look then
					rule = r
				end
			end
			check(not tinted or (rule and rule.tint ~= nil), look .. ": a tinted mesh has a tint rule")
		end
		check(
			setTris[1] < 60000 and setTris[2] < 60000,
			"each set's triangles: " .. setTris[1] .. ", " .. setTris[2]
		)
		-- Halo's statue: a plain sculpted head (no face or hair meshes), its halo a glow
		local st = Config.PocketPropArt2.PkStatue
		check(
			st and st.meshes.PkStatueHalo and st.meshes.PkStatueHalo.mat == "Neon",
			"the statue's halo glows"
		)
	end)

	test("Board art: built for today's screen, the rows never covered, the parts kept", function()
		local bad = BoardArtKit.check(Config)
		check(#bad == 0, "BoardArtKit.check: " .. table.concat(bad, "; "))
		check(BoardArtKit.HIDES.Screen == nil, "the screen (the rows' adornee) stays drawn")
		check(BoardArtKit.HIDES.Frame and BoardArtKit.HIDES.Crest and BoardArtKit.HIDES.Leg, "the rest hides")
		check(not BoardArtKit.ready(Config, function()
			return false
		end), "nothing imported: the plain parts")
		local fit = BoardArtKit.fit(Config)
		local n = 0
		for _ in fit.meshes do
			n += 1
		end
		check(n >= 2, "a body and its glow")
		local src = fs.readFile("src/server/Services/BoardService.luau")
		check(
			has(src, "dressProp(model, cf)") and has(src, "BoardArtKit.ready("),
			"buildProp dresses the board"
		)
		check(
			has(src, "p.Transparency = 1") and not has(src, "p:Destroy()"),
			"the parts are hidden, never removed"
		)
		check(
			has(src, "mp.CanCollide = false") and has(src, "mp.CanQuery = false"),
			"the meshes never collide"
		)
		local hud = fs.readFile("src/client/Ui/BoardHud.luau")
		check(has(hud, 'model:WaitForChild("Screen", 30)'), "the rows still go on the screen part")
	end)

	if T.placePath then
		test(
			"Pocket props: Art.PocketProps, PocketProps2 and Board are in the place, every mesh uploaded",
			function()
				local roblox = require("@lune/roblox")
				local game = roblox.deserializePlace(fs.readFile(T.placePath))
				local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
				for _, pair in
					{
						{ "PocketProps", Config.PocketPropArt },
						{ "PocketProps2", Config.PocketPropArt2 },
						{ "Board", Config.BoardArt },
					}
				do
					local set = art and art:FindFirstChild(pair[1])
					check(set ~= nil, "ReplicatedStorage.Art." .. pair[1])
					if not set then
						continue
					end
					for look, fit in pair[2] do
						for name, row in fit.meshes do
							local m = set:FindFirstChild(name, true)
							check(m ~= nil and m:IsA("MeshPart"), "Art." .. pair[1] .. " has " .. name)
							if m and m:IsA("MeshPart") then
								check(
									string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil,
									name .. " is uploaded"
								)
								if row.maps then
									local sa = m:FindFirstChildOfClass("SurfaceAppearance")
									check(
										sa ~= nil and string.match(sa.ColorMap, "%d+") ~= nil,
										look .. " " .. name .. " keeps its baked texture set"
									)
								end
							end
						end
					end
				end
			end
		)
	end
end
