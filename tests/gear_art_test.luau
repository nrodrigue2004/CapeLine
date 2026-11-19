-- The gear styles' looks as meshes (2026-11-19, art/blender/gear.py into Config.GearArt and art/models/Gear.rbxm,
-- ReplicatedStorage.Art.Gear): every style that can exist (each shape, the 5 set looks on their 4 slots, the gilded
-- Legendary look of every slot) has its look with fitted meshes, every mesh is in the pulled model with its mesh id
-- (and its slot's baked texture set when textured), the pieces sit on body parts LookService welds to, near them,
-- in colour roles LookService has, and the triangles fit a look's cap, a hero's worst outfit and every preset's
-- budget. Nothing is a face, hair or eyes. Called from tests/run.luau:
--   require("./gear_art_test")({ test = test, check = check, Config = Config })
-- ONLY="Gear art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")
	local GearMath = require("../src/shared/GearMath")
	local G = Config.Gear
	local GA = Config.GearArt
	local AT = {
		head = true,
		torso = true,
		waist = true,
		lhand = true,
		rhand = true,
		lshin = true,
		rshin = true,
		lfoot = true,
		rfoot = true,
	}
	local ROLES = { trim = true, dark = true, glow = true, steel = true, gold = true }
	local PATS = { plate = true, cloth = true, metal = true, gold = true }

	test("Gear art: every style that can exist has its fitted look", function()
		check(GA ~= nil and GA.looks ~= nil and GA.ref ~= nil, "Config.GearArt")
		check(G.art and G.art.meshes == true, "Config.Gear.art.meshes on")
		local need, n = {}, 0
		for _, id in GearMath.allStyles(Config) do
			local slotIdx = GearMath.styleParts(id)
			local slot = G.slotOrder[slotIdx]
			local row = GearMath.styleRow(Config, id)
			check(row ~= nil, "style " .. id)
			if row and slot ~= "gadget" then
				local key = GearMath.lookKey(slot, row)
				check(GA.looks[key] ~= nil, "a look for " .. row.name .. " (" .. key .. ")")
				if not need[key] then
					n += 1
				end
				need[key] = true
			end
		end
		check(n == 54, "54 looks in use (27 shapes, 20 set looks, 7 gilded): " .. n)
		for key in GA.looks do
			check(need[key], key .. " is a look some style uses")
		end
		for _, set in G.setOrder do
			for _, slot in G.setSlots do
				check(GA.looks[slot .. ":set:" .. set] ~= nil, slot .. " " .. set .. " set look")
			end
		end
	end)

	test("Gear art: every piece sits on its body part in a known role", function()
		local names = {}
		for key, look in GA.looks do
			check(#look.pieces >= 2, key .. ": pieces")
			check(look.hair == nil or look.hair == false, key .. ": hair flag")
			local front = "Gear_" .. string.gsub(key, ":", "_") .. "_"
			local slot = string.split(key, ":")[1]
			for _, p in look.pieces do
				check(string.sub(p.mesh, 1, #front) == front, p.mesh .. ": name")
				check(names[p.mesh] == nil, p.mesh .. ": one mesh per name")
				names[p.mesh] = true
				check(AT[p.at] and GA.ref[p.at] ~= nil, p.mesh .. ": on a body part with a reference box")
				check(ROLES[p.role], p.mesh .. ": colour role")
				check(PATS[p.pat], p.mesh .. ": texture pattern")
				check(p.maps == (p.role ~= "glow"), p.mesh .. ": textured unless it glows")
				check(p.alpha == nil or (p.alpha > 0 and p.alpha < 1), p.mesh .. ": transparency")
				-- nothing for the face, hair or eyes: no piece is named after them
				local low = string.lower(p.mesh)
				check(
					not (string.find(low, "hair") or string.find(low, "eye") or string.find(low, "beard")),
					p.mesh .. ": not a face, hair or eyes"
				)
				for k = 1, 3 do
					local roomy = slot == "back"
					check(
						math.abs(p.offset[k]) < (if roomy then 2.0 else 1.6)
							and p.size[k] > 0
							and p.size[k] < (if roomy then 4.0 else 3.4),
						p.mesh .. ": fits its body part"
					)
				end
				-- pairs: a left piece on a left part, its mirror on the right
				if string.sub(p.at, 1, 1) == "l" and p.at ~= "head" then
					check(string.sub(p.mesh, -1) == "L", p.mesh .. ": a left mesh")
				elseif string.sub(p.at, 1, 1) == "r" then
					check(string.sub(p.mesh, -1) == "R", p.mesh .. ": a right mesh")
				end
			end
		end
	end)

	test("Gear art: triangle budgets per look, per hero and per preset", function()
		local A = G.art
		local worst: { [string]: number } = {}
		for key, look in GA.looks do
			check(
				look.triangles > 0 and look.triangles <= A.lookMax,
				key .. ": " .. look.triangles .. " triangles"
			)
			local slot = string.split(key, ":")[1]
			worst[slot] = math.max(worst[slot] or 0, look.triangles)
		end
		local hero = 0
		for _, t in worst do
			hero += t
		end
		check(hero <= A.heroMax, "the heaviest outfit: " .. hero .. " triangles")
		for _, name in Config.Presets.order do
			local full = Config.Presets[name].playersFull
			check(A.budget[name] ~= nil, name .. ": a budget")
			check(full * A.heroMax <= A.budget[name], name .. ": " .. full .. " heroes fit")
		end
		check(A.budget.low <= A.budget.medium and A.budget.medium <= A.budget.high, "budgets grow by preset")
	end)

	test("Gear art: every mesh is in the pulled model with its texture set", function()
		check(fs.isFile("art/export/Gear.fbx"), "art/export/Gear.fbx")
		check(fs.isFile("art/models/Gear.rbxm"), "art/models/Gear.rbxm")
		if not fs.isFile("art/models/Gear.rbxm") then
			return
		end
		local model = roblox.deserializeModel(fs.readFile("art/models/Gear.rbxm"))[1]
		check(model ~= nil and model.Name == "Gear", "the Gear model")
		local found = {}
		for _, d in model:GetDescendants() do
			if d:IsA("MeshPart") then
				found[d.Name] = d
			end
		end
		local textured = 0
		for key, look in GA.looks do
			for _, p in look.pieces do
				local m = found[p.mesh]
				check(m ~= nil, key .. ": " .. p.mesh .. " in Gear.rbxm")
				if m then
					check(string.match(m.MeshId, "%d+") ~= nil, p.mesh .. ": a mesh id")
					local sa = m:FindFirstChildOfClass("SurfaceAppearance")
					if p.maps then
						check(
							sa ~= nil and string.match(sa.ColorMap, "%d+") ~= nil,
							p.mesh .. ": its baked maps"
						)
						textured += 1
					end
				end
			end
		end
		check(textured > 100, "textured meshes: " .. textured)
		for _, slot in { "Head", "Chest", "Hands", "Legs", "Feet", "Back", "Belt" } do
			for _, map in { "Color", "Normal", "Roughness", "Metalness" } do
				local path = "art/export/gear/Gear" .. slot .. "_" .. map .. ".png"
				check(fs.isFile(path), path)
			end
		end
	end)

	test("Gear art: LookService wears the meshes only once a whole look is there", function()
		local src = fs.readFile("src/server/Services/LookService.luau")
		check(
			string.find(src, "buildMeshes(char, folder, slot, row)", 1, true) ~= nil,
			"build tries the meshes"
		)
		check(string.find(src, "GearMath.lookKey(slot, row)", 1, true) ~= nil, "by the look's key")
		check(string.find(src, "AlphaMode.Overlay", 1, true) ~= nil, "the style colour shows through")
		check(string.find(src, "return false", 1, true) ~= nil, "a missing mesh keeps the parts")
		check(string.find(src, "KneeRigAttachment", 1, true) ~= nil, "shins fit the knee-to-ankle span")
		local proj = fs.readFile("default.project.json")
		check(
			string.find(proj, '"Gear": { "$path": "art/models/Gear.rbxm" }', 1, true) ~= nil,
			"Art.Gear mapped"
		)
		-- the street outfit and the creator preview are untouched: no gear looks there
		check(
			string.find(fs.readFile("src/client/Ui/Preview.luau"), 'FindFirstChild("GearLook")', 1, true)
				~= nil,
			"the creator preview drops the gear look"
		)
	end)
end
