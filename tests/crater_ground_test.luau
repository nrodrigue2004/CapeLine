-- The Crater's ground and burn scars, and the throw and smash particles (gap-fx3, 2026-11-19): the floor and rim
-- wear their own MaterialVariants (art/city/crater_materials.py, Config.World.crater.ground), the scars wear comic
-- decals (art/fx/textures.py --scars, Config.World.crater.scars.decals), all over the same 90 boxes; the throw's
-- dust and chips and the ram's chips are effects-library particles (FxLib.throwMoment, Config.Fx.lib.throw).
-- Called from tests/run.luau:
--   require("./crater_ground_test")({ test = test, check = check, Config = Config, placePath = placePath })
-- ONLY="Crater ground" or ONLY="Throw fx" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local FxPlan = require("../src/shared/FxPlan")
	local WorldGen = require("../src/shared/WorldGen")

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function crater(): any
		for i, lm in Config.World.landmarks do
			if lm.id == "CometCrater" then
				return WorldGen.landmark(Config.City, Config.World, i)
			end
		end
		return nil
	end

	test("Crater ground: the floor and rim name their own ground, the scars their decals", function()
		local lm = crater()
		check(lm ~= nil, "the Crater landmark")
		if not lm then
			return
		end
		local C = Config.World.crater
		local K = Config.City.kit
		local floors, rims, scars = 0, 0, {}
		for _, b in lm.boxes do
			if b.ground == C.ground.floor then
				floors += 1
				check(b.kind == "field" and b.kit == "CaveRock", "the floor keeps its kit as the fallback")
			elseif b.ground == C.ground.rim then
				rims += 1
				check(b.kind == "rock" and b.kit == "CaveRock", "a rim rock keeps its kit as the fallback")
			end
			if b.scar then
				check(b.kind == "mark" and b.color == "scorch", "only the burn strips wear a scar")
				check(C.scars.decals[b.scar] ~= nil, "a real scar decal: " .. b.scar)
				scars[b.scar] = (scars[b.scar] or 0) + 1
			end
		end
		check(floors == 1, "one floor: " .. floors)
		check(rims == 16, "16 rim rocks: " .. rims)
		local n = 0
		for k, c in scars do
			n += c
			check(k >= 1 and k <= #C.scars.decals, "scar index in range")
		end
		check(n == C.scars.n, "every burn strip wears a scar: " .. n)
		check(scars[1] and scars[2] and scars[3], "all three scars are used")
		for _, name in { C.ground.floor, C.ground.rim } do
			check(K.landmark[name] == true, name .. " is a landmark texture (its own colours)")
			check(
				K.baseMaterial[name] ~= nil and K.studsPerTile[name] ~= nil,
				name .. " has a base and tile size"
			)
			check(K.tinted[name] == nil, name .. " is not tinted")
			local path = "src/materials/Kit" .. name .. ".model.json"
			check(fs.isFile(path), path)
			if fs.isFile(path) then
				local mj = serde.decode("json", fs.readFile(path))
				local p = mj.properties
				check(mj.className == "MaterialVariant", name .. " is a MaterialVariant")
				check(p.MaterialPattern == "Organic", name .. " breaks up its tiling (Organic)")
				check(p.BaseMaterial == K.baseMaterial[name], name .. " base material matches Config")
				check(p.StudsPerTile == K.studsPerTile[name], name .. " tile size matches Config")
				for _, map in { "ColorMap", "NormalMap", "RoughnessMap" } do
					check(
						string.match(p[map] or "", "^rbxassetid://%d+$") ~= nil,
						name .. " " .. map .. " uploaded"
					)
				end
			end
			for _, map in { "Color", "Normal", "Roughness" } do
				check(
					fs.isFile("art/export/city/" .. name .. "_" .. map .. ".png"),
					name .. "_" .. map .. ".png drawn"
				)
			end
			check(
				has(fs.readFile("default.project.json"), '"Kit' .. name .. '"'),
				name .. " is in MaterialService"
			)
		end
		for _, d in C.scars.decals do
			check(fs.isFile("art/export/fx/" .. d.file), d.file .. " drawn")
			check(type(d.id) == "number" and d.id > 0, d.file .. " uploaded")
		end
	end)

	test(
		"Crater ground: CityBuilder wears the ground over the kit and the scars on top, collision untouched",
		function()
			local cb = fs.readFile("src/server/Services/CityBuilder.luau")
			check(
				has(cb, "if b.ground and kitHas(b.ground) then b.ground else b.kit"),
				"the ground only once its variant is in, else the kit"
			)
			check(has(cb, "KIT.landmark[kit]"), "a landmark texture shows its own colours (white part)")
			check(
				has(cb, "scar.id ~= 0") and has(cb, "Enum.NormalId.Top"),
				"the scar decal on top, plain strip at id 0"
			)
			-- the burn strips never collide or query, scar or not
			check(
				has(cb, 'if b.kind == "mark" then\n\t\tp.CanCollide = false\n\t\tp.CanQuery = false'),
				"marks are ghosts"
			)
		end
	)

	test("Throw fx: dust, chips and the smash are textured particles inside the budget", function()
		local L = Config.Fx.lib
		check(L.kinds.chip ~= nil and L.textures.chip ~= nil, "the chip kind and its texture")
		check(L.kinds.chip.light == 0, "a chip never glows")
		check(L.kinds.chip.rise < 0, "chips fall")
		check(fs.isFile("art/export/fx/" .. L.textures.chip.file), "chip.png drawn")
		check(L.textures.chip.id > 0, "chip.png uploaded")
		check(FxPlan.textureOf(L, "chip") ~= "", "the chip has a texture")
		for _, moment in { "grab", "back", "smash", "land_light", "land_medium", "land_heavy" } do
			check(L.throw[moment] ~= nil, "a row for " .. moment)
		end
		local prev = 0
		for _, w in { "light", "medium", "heavy" } do
			for preset, share in L.scale do
				local n = 0
				for _, e in FxPlan.throwPlan(L, "land", share, w) do
					check(L.kinds[e.kind] ~= nil, "land names a real kind: " .. e.kind)
					n += e.count
				end
				-- 6 landings in one second (a crowd throwing) stay inside a third of the preset's budget
				check(n * 6 <= L.budget[preset] / 3, w .. " landings fit on " .. preset .. ": " .. n)
				if preset == "high" then
					check(n >= prev, "heavier throws kick up more: " .. w)
					prev = n
				end
			end
		end
		check(
			#FxPlan.throwPlan(L, "land", 1, "nope") == #FxPlan.throwPlan(L, "land", 1, "light"),
			"unknown lands light"
		)
		for preset, share in L.scale do
			local n = 0
			for _, e in FxPlan.throwPlan(L, "smash", share) do
				n += e.count
			end
			check(n > 0 and n * 4 <= L.budget[preset] / 2, "4 smashes a second fit on " .. preset)
		end
		-- the wreck moments still count the same way
		check(
			#FxPlan.wreckPlan(L, "pop", 1) == #FxPlan.momentPlan(L, "wreck", "pop", 1),
			"wreckPlan is a moment"
		)
		local fx = fs.readFile("src/client/Fx/ThrowFx.luau")
		check(
			has(fx, 'FxLib.throwMoment("grab"')
				and has(fx, 'FxLib.throwMoment("land"')
				and has(fx, 'FxLib.throwMoment("back"'),
			"ThrowFx draws its moments through FxLib"
		)
		check(not has(fx, 'Instance.new("Part")'), "no plain dust or chip parts left in ThrowFx")
		check(not has(fx, "PLACEHOLDER ART"), "ThrowFx's placeholder note is gone")
		local im = fs.readFile("src/client/Fx/ImpactFx.luau")
		check(has(im, 'FxLib.throwMoment("smash"'), "the wall smash's chips through FxLib")
		check(not has(im, 'Instance.new("Part")'), "no plain chip parts left in ImpactFx")
		local bfx = fs.readFile("src/client/Fx/BuildingFx.luau")
		check(
			has(bfx, 'FxPlan.textureOf(Config.Fx.lib, "smoke")'),
			"the collapse dust wears the uploaded smoke sheet"
		)
	end)
end
