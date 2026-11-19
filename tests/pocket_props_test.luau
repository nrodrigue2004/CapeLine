-- The pocket props and the plaza board's art pass (gap-props2, 2026-11-19): art/blender/pocketprops.py's meshes over
-- the pockets' most-seen props (Shared.PocketPropKit, Config.PocketProps, PocketDecor) and art/blender/board.py's
-- look round the weekly board's screen (Shared.BoardArtKit, BoardService), with every box's collision as before.
-- Called from tests/run.luau:
--   require("./pocket_props_test")({ test = test, check = check, Config = Config, placePath = placePath })
-- ONLY="Pocket props" or ONLY="Board art" runs just these.

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
		check(total >= 150, "the props drawn as meshes: " .. total)
		local used = {}
		for _, r in Config.PocketProps.rules do
			used[r.look] = true
			check(
				Config.PocketPropArt[r.look] ~= nil,
				r.look .. " has its meshes (art/blender/pocketprops.py)"
			)
		end
		for look in Config.PocketPropArt do
			check(used[look] == true, look .. " is placed by a rule")
		end
		-- the pockets the task named all get props; the subway (the prologue's) is never touched
		for _, layout in { "academy", "pound", "ashlab", "ironhall", "arena", "rooftops" } do
			check(table.find(layouts(), layout) ~= nil, layout .. " has props")
		end
		check(table.find(layouts(), "subway") == nil, "the prologue's subway is left as it is")
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
		for look in Config.PocketPropArt do
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
	end)

	test("Pocket props: the fit data (meshes, tints, triangles, no faces)", function()
		local names = {}
		local tris = 0
		for look, fit in Config.PocketPropArt do
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
			local rule
			for _, r in Config.PocketProps.rules do
				if r.look == look then
					rule = r
				end
			end
			check(not tinted or (rule and rule.tint ~= nil), look .. ": a tinted mesh has a tint rule")
		end
		check(tris < 60000, "the whole set's triangles: " .. tris)
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
		test("Pocket props: Art.PocketProps and Art.Board are in the place, every mesh uploaded", function()
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(T.placePath))
			local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
			for _, pair in { { "PocketProps", Config.PocketPropArt }, { "Board", Config.BoardArt } } do
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
							check(string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil, name .. " is uploaded")
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
		end)
	end
end
