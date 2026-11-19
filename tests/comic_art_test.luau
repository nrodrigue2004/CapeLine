-- The comic art pass (2026-11-19): rendered comic panels and guide and mentor portraits (Config.ComicArt,
-- Shared.ComicArt). Called from tests/run.luau:
--   require("./comic_art_test")({ test = test, check = check, Config = Config })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local ComicArt = require("../src/shared/ComicArt")
	local A = Config.ComicArt

	test(
		"Comic art: every comic page panel has an entry; uploaded ids resolve, 0 falls back to frames",
		function()
			local n = 0
			for id, page in Config.Cinema.comic.pages do
				for i in page.panels do
					n += 1
					local key = id .. "." .. i
					local v = A.panels[key]
					check(type(v) == "number", key .. " has an id entry (0 = the drawn fallback)")
					local img = ComicArt.panel(Config, id, i)
					if v and v ~= 0 then
						check(img == "rbxassetid://" .. v, key .. " resolves to its image")
					else
						check(img == nil, key .. " with no upload answers nil (CinemaHud draws its frames)")
					end
				end
			end
			local m = 0
			for _ in A.panels do
				m += 1
			end
			check(m == n, string.format("no stale panel entries (%d config rows, %d panels)", m, n))
			check(ComicArt.panel(Config, "noSuchPage", 1) == nil, "an unknown panel falls back")
		end
	)

	test(
		"Comic art: every speaker, giver and mentor has a portrait cell or an alias, or the drawn fallback",
		function()
			local cells = {}
			for key, at in A.portraits do
				check(at[1] >= 1 and at[1] <= #A.sheets, key .. " sits on a sheet")
				check(
					at[2] >= 0
						and at[3] >= 0
						and (at[2] + 1) * A.cell <= 1024
						and (at[3] + 1) * A.cell <= 1024,
					key .. " sits inside its 1024 px sheet"
				)
				local c = at[1] .. ":" .. at[2] .. ":" .. at[3]
				check(cells[c] == nil, key .. " has its own cell")
				cells[c] = true
			end
			for k, v in A.aliases do
				check(A.portraits[v] ~= nil, k .. " points at a real portrait")
			end
			for _, key in ComicArt.portraitKeys(Config) do
				local has = A.portraits[key] ~= nil or A.aliases[key] ~= nil
				-- the Dev panel's test giver alone keeps the drawn portrait
				check(has or key == "SampleGiver", key .. " has a rendered portrait")
				local p = ComicArt.portrait(Config, key)
				local sheet = has and A.sheets[(A.portraits[A.aliases[key] or key])[1]]
				if sheet and sheet ~= 0 then
					check(p ~= nil and p.image == "rbxassetid://" .. sheet, key .. " resolves to its sheet")
					check(p ~= nil and p.size[1] == A.cell, key .. " shows one cell")
				else
					check(p == nil, key .. " with no upload answers nil (the frames fallback)")
				end
			end
			check(ComicArt.portrait(Config, "nobody") == nil, "an unknown speaker falls back")
		end
	)

	test(
		"Comic art: every figure wears a Roblox catalog face (and catalog hair), never a drawn one",
		function()
			local path = "art/export/panels/cast.json"
			if not fs.isFile(path) then
				return
			end
			local cast = serde.decode("json", fs.readFile(path))
			local faces, hairs = {}, {}
			for _, f in Config.CatalogLooks.faces do
				faces[f[3]] = true
			end
			for _, h in Config.CatalogLooks.hair do
				hairs[h[2]] = true
			end
			for _, row in cast.portraits do
				check(row.face ~= nil and faces[row.face.image] == true, row.key .. " wears a catalog face")
				check(row.hair == nil or hairs[row.hair.asset] == true, row.key .. "'s hair is catalog hair")
				check(A.portraits[row.key] ~= nil, row.key .. " is in Config.ComicArt")
			end
			check(#cast.panels == (function()
				local n = 0
				for _ in A.panels do
					n += 1
				end
				return n
			end)(), "the cast's panels match the config")
		end
	)
end
