-- The hair fit pass (2026-11-19): every named character (speakers, givers, mentors, side quest dresses, fakes
-- and the incident fakes) wears an explicit Roblox catalog face and hair from Config.CatalogLooks, never a name
-- hash, and the comic art's cast matches the game. Called from tests/run.luau:
--   require("./hairfit_test")({ test = test, check = check, Config = Config })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local PeopleLooks = require("../src/shared/PeopleLooks")
	local FakeRules = require("../src/shared/FakeRules")
	local CreatorRules = require("../src/shared/CreatorRules")

	local faceIds, hairIds = {}, {}
	for _, f in Config.CatalogLooks.faces do
		faceIds[f[2]] = true
	end
	for _, h in Config.CatalogLooks.hair do
		hairIds[h[2]] = true
	end
	local function catId(kit: string?): number?
		return kit and tonumber(string.match(kit, "^cat:(%d+)$")) or nil
	end

	test(
		"Hair fit: every named character has an explicit catalog face and hair from Config.CatalogLooks",
		function()
			local problems = PeopleLooks.castProblems(Config)
			check(#problems == 0, "no named character left to a name hash: " .. table.concat(problems, "; "))
			local keys = PeopleLooks.namedKeys(Config)
			check(#keys >= 60, "the whole named cast is covered (" .. #keys .. " characters)")
			for _, k in keys do
				local face, hair = PeopleLooks.catalogPick(Config, k)
				check(face ~= nil, k .. " has a catalog face")
				check(hair ~= nil, k .. " has a catalog hair or explicitly none")
				local def = PeopleLooks.lookDef(Config, k)
				if def then
					-- the game's own look (built as the givers, fakes and dresses are) wears those catalog pieces
					local look = FakeRules.lookFrom(Config, def, k)
					local vp = CreatorRules.piece(Config, "visage", look.pieces.visage)
					check(
						vp ~= nil and faceIds[catId(vp.kit) or 0] == true,
						k .. "'s built look wears a catalog face"
					)
					local hp = CreatorRules.piece(Config, "hair", look.pieces.hair or 0)
					if hair then
						check(
							hp ~= nil and hairIds[catId(hp.kit) or 0] == true,
							k .. "'s built look wears its catalog hair"
						)
					else
						check(hp == nil, k .. "'s built look is hairless")
					end
				else
					local pick = PeopleLooks.castPick(Config, k)
					check(pick ~= nil and pick.face ~= nil, k .. "'s cast pick resolves to a face image")
					check(
						pick ~= nil and (pick.hair ~= nil) == (hair ~= false),
						k .. "'s cast pick resolves its hair"
					)
				end
			end
		end
	)

	test(
		"Hair fit: the picks are varied (no two characters share both face and hair) and no drawn face is worn",
		function()
			local same = { LodestarGiver = "lodestar" } -- one person, two rows
			local seen = {}
			for _, k in PeopleLooks.namedKeys(Config) do
				local face, hair = PeopleLooks.catalogPick(Config, k)
				local pair = tostring(face) .. "|" .. tostring(hair)
				local other = seen[pair]
				check(
					other == nil
						or same[k] == other
						or same[other] == k
						or PeopleLooks.SPEAKERS[k] == other
						or PeopleLooks.SPEAKERS[other] == k,
					k .. " and " .. tostring(other) .. " look alike (" .. pair .. ")"
				)
				seen[pair] = seen[pair] or k
			end
			local faces = {}
			for _, k in PeopleLooks.namedKeys(Config) do
				faces[(PeopleLooks.catalogPick(Config, k))] = true
			end
			local n = 0
			for _ in faces do
				n += 1
			end
			check(n >= 40, "at least 40 different catalog faces across the cast (" .. n .. ")")
			for id in Config.NpcLooks.people do
				local fit = PeopleLooks.outfit(Config, id)
				check(fit == nil or fit.face == nil, id .. " wears its catalog face, not a drawn one")
			end
		end
	)

	test("Hair fit: the comic art's cast wears the same catalog picks as the game", function()
		local cast = serde.decode("json", fs.readFile("art/export/panels/cast.json"))
		for _, row in cast.portraits do
			local face, hair = PeopleLooks.catalogPick(Config, row.key)
			check(row.face and row.face.name == face, row.key .. " portrait face is " .. tostring(face))
			if hair then
				check(row.hair and row.hair.name == hair, row.key .. " portrait hair is " .. tostring(hair))
			else
				check(row.hair == nil, row.key .. " portrait has no hair")
			end
		end
	end)
end
