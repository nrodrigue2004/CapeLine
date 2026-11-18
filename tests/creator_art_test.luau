-- The hero creator's art (overnight queue item 12, 2026-11-18): the drawn suits (Config.Creator.suitArt,
-- art/clothes/suits.py), the emblem set (emblemArt, art/clothes/emblems.py), the flat masks' head decals (maskArt,
-- art/clothes/masks.py) and the cape meshes (Config.CapeArt, art/blender/capes.py). Every row names a real piece's
-- kit, every image and the FBX are on disk for nate's upload and import, the colour roles are ones LookKit has,
-- and the pieces themselves (ids, kits, unlocks) are unchanged so saved looks keep working.
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
			}
		do
			check(string.find(src, needle, 1, true) ~= nil, "LookKit: " .. needle)
		end
		local pkg = fs.readFile("art/upload/make_package.py")
		for _, kind in { "creator_suit", "creator_emblem", "creator_mask" } do
			check(string.find(pkg, kind, 1, true) ~= nil, "the upload package lists " .. kind)
		end
		check(
			string.find(fs.readFile("src/config/init.luau"), '"CapeArt"', 1, true) ~= nil,
			"Config indexes CapeArt"
		)
	end)

	test("Creator art: piece ids, kits and unlocks are unchanged", function()
		-- a fingerprint (id, kit and unlock) of each tab's pieces this pass drew, as they stood on enemies9 before it
		-- (2026-11-18), so saved looks keep working; pieces added after them do not change it
		local BEFORE = {
			suit = { 46, 168833058 },
			back = { 25, 19384452 },
			head = { 31, 1220518570 },
			emblem = { 65, 1528379958 },
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
		check(total >= 167, "167 pieces or more in the four tabs (" .. total .. ")")
	end)
end
