-- The picture tiles (2026-11-19): every creator piece the creator offers maps to a cell of our sheets, a catalog
-- face's own image, or a known text fallback (catalog hair, voices); every cell is unique and inside its sheet;
-- every sheet is on disk and has an uploaded id; weapons and the shop's picture items have cells; no catalog
-- piece (faces, hair) ever points at a cell of ours (nate's rule: those are never drawn by us).
-- Called from tests/run.luau: require("./thumbs_test")({ test = test, check = check, Config = Config })
-- ONLY="Thumbs" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local CreatorRules = require("../src/shared/CreatorRules")
	local ThumbMap = require("../src/shared/ThumbMap")
	local Th = Config.Thumbs

	-- the tabs whose pieces stay text tiles (no art of ours: a catalog item or a sound)
	local TEXT = { hair = true, voice = true }

	test("Thumbs: every offered creator piece has a cell, a catalog image or a text fallback", function()
		local n, pics, cat = 0, 0, 0
		for _, p in CreatorRules.index(Config).list do
			if CreatorRules.offered(Config, p) then
				n += 1
				local pic = ThumbMap.creator(Config, p)
				if string.sub(p.kit, 1, 4) == "cat:" then
					check(
						ThumbMap.creatorKey(Config, p) == nil,
						p.name .. ": a catalog piece has no cell of ours"
					)
					if p.tab == "visage" then
						check(
							pic ~= nil and pic.catalog == true,
							p.name .. ": a catalog face shows its own image"
						)
						cat += 1
					else
						check(pic == nil, p.name .. ": catalog hair keeps its text tile")
					end
				elseif TEXT[p.tab] then
					check(pic == nil, p.name .. ": a text tile")
				else
					check(pic ~= nil, p.tab .. "/" .. p.kit .. " (" .. p.name .. ") has a picture")
					pics += 1
				end
			end
		end
		check(
			n > 450 and pics > 380 and cat >= 40,
			string.format("%d pieces, %d pictures, %d faces", n, pics, cat)
		)
	end)

	test("Thumbs: cells are unique and inside their sheets; every sheet is on disk with an id", function()
		check(Th.on == true and Th.cell == 128 and Th.per == 8, "128 px cells, 8 x 8 a sheet")
		local used, count = {}, 0
		for key, c in Th.cells do
			count += 1
			check(type(c) == "number" and c >= 1 and c % 1 == 0, key .. ": a whole cell number")
			check(not used[c], key .. ": cell " .. c .. " is its own")
			used[c] = true
			local sheet, cx, cy = ThumbMap.cell(Config, key)
			check(sheet ~= nil and sheet <= #Th.sheets, key .. ": on a listed sheet")
			check(
				cx and cy and cx >= 0 and cx < Th.per and cy >= 0 and cy < Th.per,
				key .. ": inside its sheet"
			)
			check(
				string.find(key, "^cat:") == nil and string.find(key, "/cat:") == nil,
				key .. ": never catalog"
			)
		end
		check(count >= 400, count .. " cells")
		for i, id in Th.sheets do
			check(type(id) == "number" and id > 0, "sheet " .. i .. " uploaded")
			check(fs.isFile(string.format("art/export/thumbs/Thumbs_%d.png", i)), "sheet " .. i .. " on disk")
			local pic = ThumbMap.pic(Config, (next(Th.cells)))
			check(pic == nil or (pic.w == 128 and pic.x % 128 == 0 and pic.y % 128 == 0), "a pic is one cell")
		end
	end)

	test("Thumbs: weapons and the shop's things have pictures", function()
		for _, w in Config.Weapons.list do
			check(Th.cells[ThumbMap.weaponKey(w[1])] ~= nil, w[3] .. " has a picture")
		end
		for _, tab in Config.Shop.tabs do
			for _, key in tab.items do
				local row = Config.Shop.products[key]
				local kind = row and row.kind
				if kind == "pack" or kind == "tint" or kind == "travel" or kind == "weapon" then
					check(Th.cells["shop/" .. key] ~= nil, "shop " .. key .. " has a picture")
				end
			end
		end
	end)

	test("Thumbs: a sheet at id 0 shows no picture (the text tile stays)", function()
		local fake = table.clone(Config)
		fake.Thumbs = table.clone(Th)
		fake.Thumbs.sheets = table.create(#Th.sheets, 0)
		local p = CreatorRules.index(Config).byTab.suit[1]
		check(ThumbMap.creator(fake, p) == nil, "no id, no picture")
		check(ThumbMap.creator(Config, p) ~= nil, "with the id, a picture")
	end)
end
