-- The hero creator's art (overnight queue item 12, 2026-11-18): the drawn suits (Config.Creator.suitArt,
-- art/clothes/suits.py), the emblem set (emblemArt, art/clothes/emblems.py), the flat masks' head decals (maskArt,
-- art/clothes/masks.py) and the cape meshes (Config.CapeArt, art/blender/capes.py). Every row names a real piece's
-- kit, every image and the FBX are on disk for nate's upload and import, the colour roles are ones LookKit has,
-- and the pieces themselves (ids, kits, unlocks) are unchanged so saved looks keep working. Round 2 (2026-11-18): the
-- worn meshes (HeadArt, GloveArt, BootArt, CoatArt), the auras on the effects library and the trail strips. Round 3
-- (2026-11-18): the belts', shoulders', back bling's and headwear's meshes (BeltArt, ShoulderArt, BackArt, HatArt).
-- Called from tests/run.luau: require("./creator_art_test")({ test = test, check = check, Config = Config })
-- ONLY="Creator art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local CreatorRules = require("../src/shared/CreatorRules")

	-- the colour roles LookKit.colors holds (the slot's p, s, a and the fixed ones)
	local ROLES =
		{ p = true, s = true, a = true, dark = true, white = true, ice = true, gold = true, glowRed = true }
	local C = Config.Creator
	local idx = CreatorRules.index(Config)
	local function kitsOf(tab: string): { [string]: boolean }
		local out = {}
		for _, p in idx.byTab[tab] or {} do
			out[p.kit] = true
		end
		return out
	end

	test("Creator art: every suit has its drawn Shirt and Pants on disk", function()
		local A = C.suitArt
		check(A ~= nil and A.on == true, "suitArt is on")
		local suits = kitsOf("suit")
		local n = 0
		for kit in suits do
			n += 1
			local row = A.kits[kit]
			check(row ~= nil, "suitArt row for " .. kit)
			if row then
				check(type(row.shirt) == "number" and type(row.pants) == "number", kit .. ": ids are numbers")
				check(ROLES[row.tint[1]] and ROLES[row.tint[2]], kit .. ": tint roles LookKit has")
				check(type(row.parts) == "boolean", kit .. ": parts flag")
				for _, side in { "Shirt", "Pants" } do
					local path = "art/export/clothes/suits/Suit" .. side .. "_" .. kit .. ".png"
					check(fs.isFile(path), path)
				end
			end
		end
		check(n >= 46, "every suit kit (46 or more)")
		for kit in A.kits do
			check(suits[kit], "suitArt row " .. kit .. " is a suit piece's kit")
		end
	end)

	test("Creator art: every emblem's mark and backing is drawn", function()
		local A = C.emblemArt
		check(A ~= nil and A.on == true, "emblemArt is on")
		local n = 0
		for kit in kitsOf("emblem") do
			n += 1
			local bits = string.split(kit, ":")
			local shape, backing = bits[1], bits[2] or "none"
			check(type(A.shapes[shape]) == "number", kit .. ": emblemArt mark")
			check(fs.isFile("art/export/clothes/emblems/Emblem_" .. shape .. ".png"), kit .. ": mark image")
			check(C.shapes[shape] ~= nil, kit .. ": keeps a glyph until uploaded")
			if backing ~= "none" then
				local b = A.backings[backing]
				check(
					b ~= nil and type(b.face) == "number" and type(b.rim) == "number",
					kit .. ": backing ids"
				)
				check(
					fs.isFile("art/export/clothes/emblems/EmblemBack_" .. backing .. ".png"),
					kit .. ": backing"
				)
				check(fs.isFile("art/export/clothes/emblems/EmblemRim_" .. backing .. ".png"), kit .. ": rim")
			end
		end
		check(n >= 65, "every emblem piece (65 or more)")
	end)

	test("Creator art: the flat masks' head decals", function()
		local A = C.maskArt
		check(A ~= nil and A.on == true, "maskArt is on")
		local heads = kitsOf("head")
		local SIDES = { front = "Front", side = "Side", back = "Back", top = "Top" }
		local n = 0
		for kit, row in A.kits do
			n += 1
			check(heads[kit], kit .. " is a mask piece's kit")
			check(ROLES[row.tint], kit .. ": tint role")
			check(type(row.front) == "number", kit .. ": a front decal")
			for key, v in row do
				if key ~= "tint" then
					check(SIDES[key] ~= nil and type(v) == "number", kit .. ": " .. key .. " is a head face")
					local path = "art/export/clothes/masks/Mask"
						.. (SIDES[key] or "?")
						.. "_"
						.. kit
						.. ".png"
					check(fs.isFile(path), path)
				end
			end
		end
		check(n == 8, "8 flat masks")
		for _, kit in { "domino", "cowl", "half", "bandana" } do
			check(A.kits[kit] ~= nil, "the free mask " .. kit .. " is drawn")
		end
	end)

	test("Creator art: every cape has its meshes and fit", function()
		local A = Config.CapeArt
		check(A ~= nil, "Config.CapeArt")
		check(fs.isFile("art/export/Capes.fbx"), "art/export/Capes.fbx")
		local capes = {}
		for kit in kitsOf("back") do
			local style = string.match(kit, "^cape:(.+)$")
			if style then
				capes[style] = true
				check(A[style] ~= nil, "CapeArt row for " .. kit)
			end
		end
		local n, names = 0, {}
		for style, row in A do
			n += 1
			check(capes[style], "CapeArt " .. style .. " is a cape piece")
			check(row.triangles > 0 and row.triangles <= 1200, style .. ": triangle budget")
			check(#row.pieces >= 2, style .. ": outside and lining at least")
			local outer = false
			for _, p in row.pieces do
				check(
					string.sub(p.mesh, 1, #("Cape_" .. style .. "_")) == "Cape_" .. style .. "_",
					p.mesh .. ": name"
				)
				check(names[p.mesh] == nil, p.mesh .. ": one mesh per name")
				names[p.mesh] = true
				check(ROLES[p.role], p.mesh .. ": colour role")
				check(type(p.glow) == "boolean", p.mesh .. ": glow flag")
				check(p.size[1] > 0 and p.size[2] > 0 and p.size[3] > 0, p.mesh .. ": size")
				-- on the hero's back and shoulders (the clasps just in front of the chest), never far off the body
				check(
					math.abs(p.offset[1]) < 1.5 and p.offset[2] > -4 and p.offset[2] < 1.6,
					p.mesh .. ": fit"
				)
				check(p.offset[3] > -0.7 and p.offset[3] < 1.5, p.mesh .. ": on the torso")
				local cloth = p.mesh == "Cape_" .. style .. "_Outer" or p.mesh == "Cape_" .. style .. "_Left"
				if cloth then
					check(p.offset[3] > 0.5, p.mesh .. ": hangs behind the back")
				end
				outer = outer or cloth
			end
			check(outer, style .. ": the cloth itself")
		end
		check(n == 12, "12 capes")
	end)

	-- Round 2 (2026-11-18): the head pieces, gloves, boots, coats and scarves as worn meshes (art/blender/heads.py,
	-- hands.py, feet.py, coats.py into Config.HeadArt, GloveArt, BootArt and CoatArt). Each row is a real kit of its
	-- tab, each piece sits on a body part LookKit attaches to, near that part, with a colour role LookKit has.
	local ATTACH = {
		head = true,
		torso = true,
		waist = true,
		luarm = true,
		ruarm = true,
		llarm = true,
		rlarm = true,
		lhand = true,
		rhand = true,
		lthigh = true,
		rthigh = true,
		lshin = true,
		rshin = true,
		lfoot = true,
		rfoot = true,
	}
	local MATS = { Metal = true, Glass = true, Fabric = true, Leather = true, Rubber = true, Wood = true }
	local SETS = {
		{ art = "HeadArt", fbx = "Heads", tab = "head", prefix = "Head_", budget = 2400, n = 19 },
		{ art = "GloveArt", fbx = "Gloves", tab = "hands", prefix = "Glove_", budget = 1600, n = 19 },
		{ art = "BootArt", fbx = "Boots", tab = "feet", prefix = "Boot_", budget = 1800, n = 21 },
		{ art = "CoatArt", fbx = "Coats", tab = "back", prefix = "Coat_", budget = 2600, n = 8 },
		-- round 3 (2026-11-18): belts, shoulders, back bling and headwear (art/blender/belts.py, shoulders.py,
		-- backs.py, hats.py)
		{ art = "BeltArt", fbx = "Belts", tab = "belt", prefix = "Belt_", budget = 2400, n = 15 },
		{
			art = "ShoulderArt",
			fbx = "Shoulders",
			tab = "shoulders",
			prefix = "Shoulder_",
			budget = 3000,
			n = 20,
		},
		{ art = "BackArt", fbx = "Backs", tab = "backpack", prefix = "Back_", budget = 3000, n = 22 },
		{ art = "HatArt", fbx = "Hats", tab = "hat", prefix = "Hat_", budget = 2400, n = 25 },
		-- our own hair (nate, 2026-11-17: heroes keep nothing from their avatar), art/blender/hair.py
		{ art = "HairArt", fbx = "Hair", tab = "hair", prefix = "Hair_", budget = 2400, n = 40 },
		-- the small worn pieces (art/blender/trinkets.py)
		{ art = "EarArt", fbx = "Ears", tab = "ears", prefix = "Ear_", budget = 2000, n = 10 },
		{ art = "NeckArt", fbx = "Necks", tab = "neck", prefix = "Neck_", budget = 2000, n = 15 },
		{ art = "WristArt", fbx = "Wrists", tab = "wrist", prefix = "Wrist_", budget = 2000, n = 12 },
		{ art = "ArmArt", fbx = "Arms", tab = "arms", prefix = "Arm_", budget = 2000, n = 15 },
	}
	-- the body parts that come in a left and right pair: a piece on one is a left or right mesh
	local SIDED = {
		luarm = true,
		ruarm = true,
		llarm = true,
		rlarm = true,
		lhand = true,
		rhand = true,
		lthigh = true,
		rthigh = true,
		lshin = true,
		rshin = true,
		lfoot = true,
		rfoot = true,
	}
	for _, set in SETS do
		test("Creator art: " .. set.art .. " rows are real kits with fitted meshes", function()
			local A = Config[set.art]
			check(A ~= nil, "Config." .. set.art)
			check(fs.isFile("art/export/" .. set.fbx .. ".fbx"), "art/export/" .. set.fbx .. ".fbx")
			local kits = kitsOf(set.tab)
			local n, names = 0, {}
			for kit, row in A do
				n += 1
				check(kits[kit], set.art .. " " .. kit .. " is a " .. set.tab .. " piece's kit")
				check(row.triangles > 0 and row.triangles <= set.budget, kit .. ": triangle budget")
				check(#row.pieces >= 1, kit .. ": has pieces")
				if row.hair ~= nil then
					check(type(row.hair) == "boolean", kit .. ": hair flag")
				end
				local front = set.prefix .. string.gsub(kit, ":", "_") .. "_"
				for _, p in row.pieces do
					check(string.sub(p.mesh, 1, #front) == front, p.mesh .. ": name")
					check(names[p.mesh] == nil, p.mesh .. ": one mesh per name")
					names[p.mesh] = true
					check(
						ATTACH[p.at],
						p.mesh .. ": on a body part LookKit attaches to (" .. tostring(p.at) .. ")"
					)
					-- (hair takes the look's hair colour, which LookKit.colors holds as well)
					check(
						ROLES[p.role] or (set.tab == "hair" and p.role == "hair"),
						p.mesh .. ": colour role"
					)
					check(type(p.glow) == "boolean", p.mesh .. ": glow flag")
					check(p.mat == nil or MATS[p.mat], p.mesh .. ": material")
					check(p.alpha == nil or (p.alpha > 0 and p.alpha < 1), p.mesh .. ": transparency")
					check(p.size[1] > 0 and p.size[2] > 0 and p.size[3] > 0, p.mesh .. ": size")
					for k = 1, 3 do
						-- (the shoulder coat drapes over both arms: 4.4 studs wide on the 4-stud-wide rig; back
						-- bling reaches further: the bat wings span 4.6 studs and the banner's finial tops its pole)
						local roomy = set.tab == "backpack"
						check(
							math.abs(p.offset[k]) < (if roomy then 2.0 else 1.6)
								and p.size[k] < (if roomy then 5.0 else 4.6),
							p.mesh .. ": fits its body part"
						)
					end
					if set.tab ~= "back" and SIDED[p.at] then
						-- a pair is two meshes (a MeshPart cannot be mirrored): one each side
						local side = string.sub(p.mesh, -1)
						check(side == "L" or side == "R", p.mesh .. ": a left or right piece")
						check(string.sub(p.at, 1, 1) == string.lower(side), p.mesh .. ": on its own side")
					end
				end
			end
			check(n == set.n, set.art .. ": " .. set.n .. " kits (" .. n .. ")")
		end)
	end

	test("Creator art: every mask, glove, boot and back piece has its art", function()
		for kit in kitsOf("head") do
			check(
				Config.HeadArt[kit] ~= nil or C.maskArt.kits[kit] ~= nil,
				"head " .. kit .. ": a mesh or decals"
			)
		end
		for kit in kitsOf("hands") do
			check(Config.GloveArt[kit] ~= nil, "hands " .. kit .. ": meshes")
		end
		for kit in kitsOf("feet") do
			check(Config.BootArt[kit] ~= nil, "feet " .. kit .. ": meshes")
		end
		for kit in kitsOf("back") do
			local cape = string.match(kit, "^cape:(.+)$")
			check(
				(cape ~= nil and Config.CapeArt[cape] ~= nil) or Config.CoatArt[kit] ~= nil,
				"back " .. kit .. ": meshes"
			)
		end
		-- helmets and hoods hide the hair; open masks keep it
		for _, kit in { "helm", "crest", "horns", "antenna", "hood", "frame", "monovisor" } do
			check(Config.HeadArt[kit].hair == false, kit .. " hides the hair")
		end
		for _, kit in { "visor", "goalie", "fox", "oni" } do
			check(Config.HeadArt[kit].hair ~= false, kit .. " keeps the hair")
		end
	end)

	test(
		"Creator art: every belt, shoulder, back bling, headwear, hair, ear, neck, wrist and arm piece has its meshes",
		function()
			local luau = require("@lune/luau")
			local roblox = require("@lune/roblox")
			local PieceKits = luau.load(fs.readFile("src/shared/PieceKits.luau"), {
				debugName = "PieceKits",
				environment = { Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Enum = roblox.Enum },
			})()
			for _, set in
				{
					{ "belt", "BeltArt" },
					{ "shoulders", "ShoulderArt" },
					{ "backpack", "BackArt" },
					{ "hat", "HatArt" },
					{ "hair", "HairArt" },
					{ "ears", "EarArt" },
					{ "neck", "NeckArt" },
					{ "wrist", "WristArt" },
					{ "arms", "ArmArt" },
				}
			do
				for kit in kitsOf(set[1]) do
					-- Roblox catalog hair (kit "cat:<id>") is loaded at boot, not drawn
					check(
						string.sub(kit, 1, 4) == "cat:" or Config[set[2]][kit] ~= nil,
						set[1] .. " " .. kit .. ": meshes"
					)
				end
			end
			-- a hat mesh hides the same hair as its part-built kit (LookKit reads PieceKits.hatHidesHair for both)
			for kit, row in Config.HatArt do
				check(type(row.hair) == "boolean", "hat " .. kit .. ": hair flag")
				check(
					row.hair == not PieceKits.hatHidesHair[kit],
					"hat " .. kit .. ": hides the hair like its parts"
				)
			end
			-- the pair rule: both shoulders get a pad unless the kit is one-sided (the single pauldron, the plume)
			for kit, row in Config.ShoulderArt do
				local l, r = 0, 0
				for _, p in row.pieces do
					if p.at == "luarm" then
						l += 1
					elseif p.at == "ruarm" then
						r += 1
					end
				end
				if kit == "single" or kit == "plume" then
					check(l > 0 and r == 0, kit .. ": the left shoulder only")
				else
					check(l == r, kit .. ": a left and right piece for each")
				end
			end
		end
	)

	test("Creator art: every eye shape has its glow meshes", function()
		local A = Config.EyeArt
		check(A ~= nil, "Config.EyeArt")
		check(fs.isFile("art/export/Eyes.fbx"), "art/export/Eyes.fbx")
		-- the shapes the Eyes pieces name ("shape:tone"; a bare tone is the bar)
		local shapes = {}
		for kit in kitsOf("eyes") do
			local bits = string.split(kit, ":")
			shapes[if #bits > 1 then bits[1] else "bar"] = true
		end
		local n = 0
		for shape in shapes do
			n += 1
			local row = A[shape]
			check(row ~= nil, "EyeArt " .. shape)
			if row then
				check(row.triangles > 0 and row.triangles <= 400, shape .. ": triangle budget")
				check(
					#row.pieces == (if shape == "visor" then 1 else 2),
					shape .. ": one glow an eye (the visor one band)"
				)
				for i, p in row.pieces do
					check(p.at == "head" and p.glow == true, p.mesh .. ": a glow on the head")
					check(
						p.role == (if i == 1 then "eye1" else "eye2"),
						p.mesh .. ": the left eye, then the right"
					)
					check(
						string.sub(p.mesh, 1, #("Eye_" .. shape .. "_")) == "Eye_" .. shape .. "_",
						p.mesh .. ": name"
					)
					-- on the face: in front of the head, at the eyes' height
					check(
						p.offset[3] < -0.55 and math.abs(p.offset[2] - 0.12) < 0.06,
						p.mesh .. ": on the face"
					)
				end
			end
		end
		check(n == 7, "7 eye shapes (" .. n .. ")")
		local src = fs.readFile("src/shared/LookKit.luau")
		check(string.find(src, 'eyes = { "Eyes", "EyeArt" }', 1, true) ~= nil, "LookKit reads Art.Eyes")
		check(
			string.find(src, 'pieceMeshes(char, folder, "eyes", shapeName, glow, nil, "Eye")', 1, true) ~= nil,
			"LookKit wears them"
		)
	end)

	test("Creator art: auras use the effects library's textures, under the cap", function()
		local A = C.auraFx
		check(A ~= nil and A.on == true, "auraFx is on")
		check(A.cap > 0 and A.cap <= 30, "a hero's aura cap")
		local tex = Config.Fx.lib.textures
		local FX_ROLES =
			{ a = true, p = true, s = true, ice = true, white = true, gold = true, glowRed = true }
		local n = 0
		for kit in kitsOf("aura") do
			n += 1
			local layers = A.kits[kit]
			check(layers ~= nil and #layers >= 1, "auraFx for " .. kit)
			local rate = 0
			for i, l in layers or {} do
				local tag = kit .. " layer " .. i
				check(tex[l.tex] ~= nil, tag .. ": the library texture " .. tostring(l.tex))
				check(l.rate > 0, tag .. ": rate")
				rate += l.rate
				check(l.life[1] > 0 and l.life[1] <= l.life[2], tag .. ": life")
				check(l.speed[1] <= l.speed[2], tag .. ": speed")
				check(l.size[1] >= 0 and l.size[2] >= 0, tag .. ": size")
				check(l.alpha >= 0 and l.alpha < 1, tag .. ": alpha")
				check(l.light >= 0 and l.light <= 1, tag .. ": light")
				check(#l.colors == 2 and FX_ROLES[l.colors[1]] and FX_ROLES[l.colors[2]], tag .. ": colours")
				check(#l.box == 3, tag .. ": box")
			end
			check(rate <= A.cap, kit .. ": " .. rate .. " particles a second, cap " .. A.cap)
		end
		check(n == 6, "6 auras")
		for kit in A.kits do
			check(kitsOf("aura")[kit], "auraFx " .. kit .. " is an aura piece's kit")
		end
	end)

	test("Creator art: every flight trail has its strip", function()
		local A = C.trailFx
		check(A ~= nil and A.on == true, "trailFx is on")
		local n = 0
		for kit in kitsOf("trail") do
			n += 1
			local row = A.kits[kit]
			check(row ~= nil, "trailFx for " .. kit)
			if row then
				check(type(row.id) == "number", kit .. ": id")
				check(row.mode == "Stretch" or row.mode == "Wrap", kit .. ": mode")
				check(row.mode ~= "Wrap" or (row.length or 0) > 0, kit .. ": wrap length")
				check(fs.isFile("art/export/fx/" .. row.file), "art/export/fx/" .. row.file)
			end
		end
		check(n == 8, "8 trails")
		for kit in A.kits do
			check(kitsOf("trail")[kit], "trailFx " .. kit .. " is a trail piece's kit")
		end
	end)

	test("Creator art: LookKit wears the art and keeps the parts as the fallback", function()
		local src = fs.readFile("src/shared/LookKit.luau")
		for _, needle in
			{
				"local function suitClothes(",
				"local function maskDecals(",
				"local function capeMeshes(",
				'art:FindFirstChild("Capes")',
				"capeMeshes(char, folder, kit, c, m)",
				"maskDecals(char, kit, c)",
				"EA.shapes[bits[1]]",
				"local pieceMeshes: (Model, Instance, string, string, Colors, Enum.Material?, string?)",
				"\nfunction pieceMeshes(",
				'head = { "Heads", "HeadArt" }',
				'hands = { "Gloves", "GloveArt" }',
				'feet = { "Boots", "BootArt" }',
				'back = { "Coats", "CoatArt" }',
				'belt = { "Belts", "BeltArt" }',
				'shoulders = { "Shoulders", "ShoulderArt" }',
				'backpack = { "Backs", "BackArt" }',
				'hat = { "Hats", "HatArt" }',
				'hair = { "Hair", "HairArt" }',
				'ears = { "Ears", "EarArt" }',
				'neck = { "Necks", "NeckArt" }',
				'wrist = { "Wrists", "WristArt" }',
				'arms = { "Arms", "ArmArt" }',
				'pieceMeshes(char, folder, "hair", hairKit, colors, nil, "Hair")',
				"if not pieceMeshes(char, folder, slot, kit, c, m) then",
				"pieceMeshes(char, folder, tab, kit, c, m)",
				"local function auraLayers(",
				"C.auraFx",
				"C.trailFx",
			}
		do
			check(string.find(src, needle, 1, true) ~= nil, "LookKit: " .. needle)
		end
		local pkg = fs.readFile("art/upload/make_package.py")
		for _, kind in { "creator_suit", "creator_emblem", "creator_mask", "creator_trail" } do
			check(string.find(pkg, kind, 1, true) ~= nil, "the upload package lists " .. kind)
		end
		check(
			string.find(fs.readFile("art/upload/apply_ids.py"), "creator_trail", 1, true) ~= nil,
			"apply_ids fills the trail ids"
		)
		local init = fs.readFile("src/config/init.luau")
		for _, name in
			{
				"CapeArt",
				"HeadArt",
				"GloveArt",
				"BootArt",
				"CoatArt",
				"BeltArt",
				"ShoulderArt",
				"BackArt",
				"HatArt",
				"HairArt",
				"EyeArt",
				"EarArt",
				"NeckArt",
				"WristArt",
				"ArmArt",
			}
		do
			check(string.find(init, '"' .. name .. '"', 1, true) ~= nil, "Config indexes " .. name)
		end
	end)

	test("Creator art: piece ids, kits and unlocks are unchanged", function()
		-- a fingerprint (id, kit and unlock) of each tab's pieces this pass drew, as they stood on enemies9 before it
		-- (2026-11-18), so saved looks keep working; pieces added after them do not change it
		local BEFORE = {
			suit = { 46, 168833058 },
			back = { 25, 19384452 },
			head = { 31, 1220518570 },
			emblem = { 65, 1528379958 },
			-- round 2's tabs (2026-11-18, as they stood on enemies9 at cafb358)
			hands = { 20, 874172715 },
			feet = { 23, 1457297585 },
			aura = { 6, 1812636889 },
			trail = { 8, 1275196596 },
			-- round 3's tabs (2026-11-18, as they stood on enemies9 at 15d72ee)
			belt = { 15, 1609015023 },
			shoulders = { 20, 1924804490 },
			backpack = { 22, 311582161 },
			hat = { 25, 537220423 },
			hair = { 40, 309821413 },
			eyes = { 20, 1835763561 },
			ears = { 10, 1147272169 },
			neck = { 15, 1460762146 },
			wrist = { 12, 1371282101 },
			arms = { 15, 373027507 },
		}
		local total = 0
		for tab, want in BEFORE do
			local list = idx.byTab[tab]
			local n = #list
			total += n
			local h = 0
			for i = 1, math.min(if want[1] > 0 then want[1] else n, n) do
				local p, s = list[i], list[i].source
				local r = string.format("%d %s %s %s %s", p.id, p.kit, s.kind, tostring(s.a), tostring(s.n))
				for k = 1, #r do
					h = (h * 31 + string.byte(r, k)) % 2147483647
				end
			end
			check(n >= want[1], tab .. ": no piece removed (" .. n .. ")")
			check(h == want[2], tab .. ": the pieces' fingerprint (" .. n .. " pieces, " .. h .. ")")
		end
		check(total >= 418, "418 pieces or more in the eighteen tabs (" .. total .. ")")
	end)
end
