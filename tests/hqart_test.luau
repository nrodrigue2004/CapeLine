-- The HQ art pass (2026-11-18): art/blender/hq.py's meshes for both HQs (the Safehouse and the Foundry): the
-- station consoles and pads, the WANTED board, head mounts and name plates, the Trophy Wall, the training
-- dummies, the statues' plinths, every prop and the reputation dressing. Called from tests/run.luau:
--   require("./hqart_test")({ test = test, check = check, Config = Config })
-- ONLY="HQ art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local SetPieceKit = require("../src/shared/SetPieceKit")
	local HqArtKit = require("../src/shared/HqArtKit")
	local RepTiers = require("../src/shared/RepTiers")
	local FIT = Config.HqArt

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end
	local none = function(_: string)
		return false
	end
	local all = function(_: string)
		return true
	end

	test("HQ art: the fit table holds every HQ look and nothing else, all in the phone budget", function()
		check(type(FIT) == "table", "Config.HqArt is indexed")
		local used = HqArtKit.looks(Config)
		for look in used do
			check(FIT[look] ~= nil, look .. " is in the fit table")
		end
		local looks, meshes, total = 0, 0, 0
		local names: { [string]: string } = {}
		for _, other in { Config.SetPieceArt or {}, Config.VehicleArt or {} } do
			for look, fit in other do
				for name in fit do
					names[name] = look
				end
			end
		end
		for look, fit in FIT do
			looks += 1
			check(used[look] == true, look .. " is used somewhere")
			local tris = 0
			for name, f in fit do
				meshes += 1
				check(
					names[name] == nil,
					name .. " is one mesh name in every set (" .. tostring(names[name]) .. ")"
				)
				names[name] = look
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
			looks >= 70 and meshes >= 250,
			"the whole HQ set (" .. looks .. " looks, " .. meshes .. " meshes)"
		)
		check(total <= 60000, "the whole set is in budget (" .. total .. " tris)")
		check(fs.isFile("art/export/Hq.fbx"), "the meshes are exported for nate's import")
		check(fs.isFile("art/preview/hq.png"), "and previewed")
		check(has("src/config/init.luau", '"HqArt"'), "the config index lists it")
		check(has("art/blender/hq.py", "Hq.fbx"), "the script writes the FBX")
	end)

	test("HQ art: the two sides read differently, every station has a console on each side", function()
		for name in Config.Hq.stations do
			local v, s = HqArtKit.station("hero", name), HqArtKit.station("villain", name)
			check(v ~= nil and s ~= nil and v ~= s, name .. " has a Vigil and a Syndicate console")
			check(HqArtKit.FACING[name] ~= nil, name .. " faces into the room")
		end
		check(HqArtKit.pad("hero") ~= HqArtKit.pad("villain"), "each side's pad")
		check(HqArtKit.board("hero") ~= HqArtKit.board("villain"), "each side's WANTED board")
		check(HqArtKit.mount("hero") ~= HqArtKit.mount("villain"), "each side's head mount")
		check(HqArtKit.trophyWall("hero") ~= HqArtKit.trophyWall("villain"), "each side's Trophy Wall")
		check(HqArtKit.plinth("hero") ~= HqArtKit.plinth("villain"), "each side's plinth")
		local function mats(look: string): { [string]: boolean }
			local out = {}
			for _, f in FIT[look] or {} do
				out[f.mat] = true
			end
			return out
		end
		local vm, sm =
			mats(HqArtKit.station("hero", "command") :: string),
			mats(HqArtKit.station("villain", "command") :: string)
		check(vm.SmoothPlastic == true and sm.Metal == true, "Vigil smooth plastic, Syndicate metal")
		check(HqArtKit.station(nil, "command") == HqArtKit.station("hero", "command"), "no side: the Vigil's")
	end)

	test("HQ art: each look sits over the parts it hides, a full HQ on both sides", function()
		for _, side in { "hero", "villain" } do
			for _, n in { 1, 3, 5 } do
				local s = HqArtKit.scene(Config, side, n)
				local bad = SetPieceKit.check(Config, s.places, s.boxes)
				check(#bad == 0, side .. " with " .. n .. " statues: " .. table.concat(bad, "; "))
				check(#s.wall == 1 and FIT[s.wall[1].look] ~= nil, side .. ": the Trophy Wall's frame")
			end
		end
		-- the check catches a look moved off its parts
		local s = HqArtKit.scene(Config, "hero", 5)
		local moved = table.clone(s.places)
		moved[1] = table.clone(moved[1])
		moved[1].x += 40
		check(#SetPieceKit.check(Config, moved, s.boxes) > 0, "a look moved off its parts is caught")
		-- the consoles at a pad's edge stand in for its post from beside it, still within reach of it
		local beside = 0
		for _, b in s.boxes do
			if b.beside then
				beside += 1
				check(b.name == "post", "only a post is stood in for from beside")
				local far = table.clone(s.places)
				far[b.art] = table.clone(far[b.art])
				far[b.art].z += 12
				check(
					#SetPieceKit.check(Config, far, s.boxes) > 0,
					"a console moved far off its post is caught"
				)
			end
		end
		local n = 0
		for _ in HqArtKit.BESIDE do
			n += 1
		end
		check(beside == n and n == 2, "the training and exit consoles stand beside their posts")
	end)

	test(
		"HQ art: before the import every part shows as today; a half import never draws half a look",
		function()
			for _, side in { "hero", "villain" } do
				local s = HqArtKit.scene(Config, side, 5)
				local d0 = SetPieceKit.drawn(Config, s.places, none)
				check(next(d0) == nil, side .. ": nothing drawn before the import")
				for _, b in s.boxes do
					check(not SetPieceKit.hides(b, d0), side .. ": every part shows before the import")
				end
				local d1 = SetPieceKit.drawn(Config, s.places, all)
				local hidden = 0
				for i in s.places do
					check(d1[i] == true, side .. ": look " .. i .. " drawn after it")
				end
				for _, b in s.boxes do
					if SetPieceKit.hides(b, d1) then
						hidden += 1
					end
				end
				check(hidden > 0, side .. ": parts hide under the looks")
				local look = s.places[1].look
				local miss = next(FIT[look])
				local d2 = SetPieceKit.drawn(Config, s.places, function(n: string)
					return n ~= miss
				end)
				for i, pl in s.places do
					check(
						(d2[i] == true) == (pl.look ~= look),
						side .. ": a look short of a mesh is not drawn"
					)
				end
			end
			for _, look in { HqArtKit.BODY, HqArtKit.DUMMY, HqArtKit.NEMESIS } do
				check(not SetPieceKit.ready(Config, look, none), look .. " waits for the import")
				check(SetPieceKit.ready(Config, look, all), look .. " is drawn after it")
			end
		end
	)

	test(
		"HQ art: the filled shapes stretch over their parts; the dummy's body is the 15 R15 parts",
		function()
			for shape, sh in HqArtKit.SHAPES do
				check(FIT[sh.look] ~= nil, shape .. "'s look is in the fit table")
				local list = HqArtKit.fill(Config, shape, { 2, 4, 6 })
				check(#list == #sh.meshes, shape .. " fills with all its meshes")
				local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
				for _, m in list do
					for k = 1, 3 do
						lo[k] = math.min(lo[k], m.offset[k] - m.size[k] / 2)
						hi[k] = math.max(hi[k], m.offset[k] + m.size[k] / 2)
					end
				end
				local want = { 2, 4, 6 }
				for k = 1, 3 do
					check(math.abs(hi[k] - lo[k] - want[k]) < 1e-3, shape .. " spans the part on axis " .. k)
					check(math.abs(hi[k] + lo[k]) < 1e-3, shape .. " is centred on the part on axis " .. k)
				end
			end
			check(#HqArtKit.fill(Config, "noSuchShape", { 1, 1, 1 }) == 0, "an unknown shape fills nothing")
			local body = FIT[HqArtKit.BODY] or {}
			local count = 0
			for _ in body do
				count += 1
			end
			check(count == 15, "the body is 15 meshes (" .. count .. ")")
			for _, name in
				{
					"Head",
					"UpperTorso",
					"LowerTorso",
					"LeftUpperArm",
					"LeftLowerArm",
					"LeftHand",
					"RightUpperArm",
					"RightLowerArm",
					"RightHand",
					"LeftUpperLeg",
					"LeftLowerLeg",
					"LeftFoot",
					"RightUpperLeg",
					"RightLowerLeg",
					"RightFoot",
				}
			do
				check(body[name] ~= nil, "the body has its " .. name)
			end
		end
	)

	test("HQ art: every prop has a spot and a look, every dressing look covers named pieces", function()
		for i in Config.Hq.props do
			check(HqArtKit.PROP_SPOTS[i] ~= nil, "prop " .. i .. " has a spot in the room")
			check(
				(HqArtKit.PROPS[i] ~= nil and FIT[HqArtKit.PROPS[i]] ~= nil) or HqArtKit.PART_PROPS[i] ~= nil,
				"prop " .. i .. " has its look (a mesh, or its own parts kit)"
			)
		end
		local seen: { [string]: boolean } = {}
		for _, spot in HqArtKit.PROP_SPOTS do
			local key = spot[1] .. "," .. spot[2]
			check(not seen[key], "no two props share a spot (" .. key .. ")")
			seen[key] = true
		end
		for side, tag in { hero = "V", villain = "S" } do
			local names: { [string]: boolean } = {}
			for _, p in RepTiers.dressing(Config, side, RepTiers.MAX) do
				names[p.name] = true
			end
			for name, d in HqArtKit.DRESS[tag] do
				check(names[name] == true, side .. "'s dressing has a " .. name)
				for _, c in d.covers or {} do
					check(names[c] == true, side .. "'s " .. d.look .. " covers a real piece, " .. c)
				end
			end
			-- each tier draws only the looks of the pieces it has
			for tier = 0, RepTiers.MAX do
				local pieces = RepTiers.dressing(Config, side, tier)
				local places, hides = HqArtKit.dressing(side, pieces)
				local mapped = 0
				for _, p in pieces do
					if HqArtKit.DRESS[tag][p.name] then
						mapped += 1
					end
				end
				check(#places == mapped, side .. " tier " .. tier .. ": one look a named piece")
				for i, k in hides do
					check(
						pieces[i] ~= nil and places[k] ~= nil,
						side .. " tier " .. tier .. ": hides its own pieces"
					)
				end
			end
		end
	end)

	test("HQ art: HqClient draws the meshes over hidden parts that keep their prompts and signs", function()
		local kit = "src/client/Fx/HqMeshes.luau"
		check(has(kit, "root and root:FindFirstChild(name, true)"), "the meshes come from Art.Hq")
		check(has(kit, "SetPieceKit.ready(Config, look, HqMeshes.has)"), "a look needs all its meshes")
		check(has(kit, "p.CanCollide = false") and has(kit, "p.CanQuery = false"), "a mesh never collides")
		local hide = string.match(fs.readFile(kit), "function HqMeshes.hide.-\nend") or ""
		check(string.find(hide, "Transparency = 1", 1, true) ~= nil, "a hidden part is unseen")
		check(string.find(hide, "Destroy", 1, true) == nil, "but stays (its prompt and SurfaceGuis)")
		local hq = "src/client/Controllers/HqClient.luau"
		for _, needle in
			{
				"HqMeshes.place(f, HqArtKit.pad(state.side), foot)",
				"HqArtKit.station(state.side, name)",
				'HqMeshes.cover(plate, "dummyBase")',
				'HqMeshes.cover(target, "dummyTarget")',
				'HqMeshes.cover(eye, "dummyVisor")',
				"HqMeshes.ready(HqArtKit.BODY)",
				"HqArtKit.plinth(state.side)",
				"HqArtKit.trophyWall(state.side)",
				"HqArtKit.trophySpot(Config, i)",
				"HqArtKit.PROP_SPOTS[bit]",
				"HqArtKit.dressing(state.side, pieces)",
				"HqArtKit.board(state.side)",
				"HqArtKit.mount(state.side)",
				"HqMeshes.cover(lookPart(f, p, frame), p.name)",
			}
		do
			check(has(hq, needle), "HqClient: " .. needle)
		end
		check(not has(hq, "local PROP_SPOTS"), "one prop spot list (HqArtKit's)")
		check(has("src/shared/NpcRig.luau", "look: string?"), "NpcRig takes the dummy's own body")
	end)
end
