-- The deep art pass (2026-11-19): art/blender/deep.py's looks over the underwater areas (Shared.DeepLayout's art,
-- Shared.DeepArtKit, Config.DeepArt). Called from tests/run.luau:
--   require("./deep_art_test")({ test = test, check = check, Config = Config })
-- ONLY="Deep art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local DeepLayout = require("../src/shared/DeepLayout")
	local DeepArtKit = require("../src/shared/DeepArtKit")
	local FIT = Config.DeepArt
	local lay = DeepLayout.build(Config)

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	test("Deep art: every piece kind has a look with meshes and fit data", function()
		local used: { [string]: boolean } = {}
		for _, p in lay.art do
			used[p.look] = true
		end
		for _, b in lay.boxes do
			if (b :: any).art then
				used[(b :: any).art] = true
			end
		end
		for _, look in
			{
				"TunnelSegment",
				"StationShell",
				"StationPlatform",
				"StationPillar",
				"TrainCar",
				"CoralBrain",
				"CoralKnob",
				"CoralStag",
				"CoralTube",
				"CoralFinger",
				"CoralFan",
				"CoralLace",
				"KelpStrand",
				"WreckHull",
				"WreckBow",
				"WreckCabin",
				"WreckMast",
				"CacheChest",
				"FactoryHall",
				"FactoryRoof",
				"FactoryChimney",
				"FactoryPipe",
				"QuayWall",
			}
		do
			check(used[look] == true, look .. " stands somewhere in the Deep")
		end
		for look in used do
			local fit = DeepArtKit.fit(Config, look)
			check(fit ~= nil, look .. " has fit data")
			if fit then
				check(#fit.frame == 3, look .. " has a frame")
				local n = 0
				for name, m in fit.meshes do
					n += 1
					check(
						#m.size == 3 and #m.offset == 3 and #m.color == 3,
						name .. " has a size, centre and colour"
					)
					check(
						type(m.mat) == "string" and (m.tris or 0) > 0,
						name .. " has a material and triangles"
					)
				end
				check(n > 0, look .. " has meshes")
			end
		end
		-- the gear the client draws (EnemyRenderer, CombatFx, DeepClient)
		for look, names in
			{
				DiverHelmet = { "DiverDome", "HelmetFrame" },
				DiverTank = { "DiverTank" },
				Torpedo = { "Torpedo" },
				AirBubble = { "AirBubbleGlass", "AirBubbleShine" },
			}
		do
			for _, name in names do
				check(FIT[look] and FIT[look].meshes[name] ~= nil, look .. " has " .. name)
			end
		end
		-- mesh names are unique across the set (one lookup by name serves every look)
		local seen = {}
		for look, fit in FIT do
			for name in fit.meshes do
				check(seen[name] == nil, name .. " is in one look only (" .. look .. ")")
				seen[name] = true
			end
		end
	end)

	test("Deep art: the hit boxes are unchanged and every hidden box is under its look", function()
		-- the layout before the art pass: 338 boxes, this checksum of their places, sizes and turns
		local s = 0
		for i, b in lay.boxes do
			s = (s + i * (b.cx * 3 + b.cy * 5 + b.cz * 7 + b.sx * 11 + b.sy * 13 + b.sz * 17 + (b.ry or 0)))
				% 1e9
		end
		check(#lay.boxes == 338, "338 boxes (" .. #lay.boxes .. ")")
		check(
			string.format("%.4f", s) == "90021458.2875",
			"the boxes sit where they always did (" .. s .. ")"
		)
		check(
			#lay.terrain == 51 and #lay.caches == 10 and #lay.rescues == 4,
			"fills, caches and rescues unchanged"
		)
		local bad = DeepArtKit.check(Config, lay)
		for i = 1, math.min(#bad, 40) do
			print("    " .. bad[i])
		end
		check(#bad == 0, "every look fits its boxes (" .. #bad .. " problems)")
		-- the boxes that stay seen: the glowing signs, gate, vents and chimney caps
		local hidden, kept = 0, 0
		for _, b in lay.boxes do
			if (b :: any).art then
				hidden += 1
			else
				kept += 1
				check(b.kind == "glow", "a box with no look is a glow (" .. b.kind .. ")")
			end
		end
		check(
			hidden == 326 and kept == 12,
			"326 boxes drawn by looks, 12 glows kept (" .. hidden .. ", " .. kept .. ")"
		)
		-- before the import nothing is hidden; with every mesh, every box with a look is
		local none = DeepArtKit.readyLooks(Config, function()
			return false
		end)
		local all = DeepArtKit.readyLooks(Config, function()
			return true
		end)
		local h0, h1 = 0, 0
		for _, b in lay.boxes do
			h0 += if DeepArtKit.hides(b, none) then 1 else 0
			h1 += if DeepArtKit.hides(b, all) then 1 else 0
		end
		check(h0 == 0 and h1 == 326, "no box hidden before the import, all 326 after")
		-- a half import never shows half a look
		local half = DeepArtKit.readyLooks(Config, function(n: string)
			return n ~= "TunnelLamp"
		end)
		check(
			half.TunnelSegment == nil and half.StationShell == true,
			"a look waits for every one of its meshes"
		)
		-- the builder hides the boxes, never removes or moves them, and the meshes never collide
		local cb = "src/server/Services/CityBuilder.luau"
		check(has(cb, "DeepArtKit.hides(b, ready)") and has(cb, "p.Transparency = 1"), "hidden boxes stay")
		check(has(cb, "p.CanCollide = false") and has(cb, "p.CanQuery = false"), "the meshes never collide")
	end)

	test("Deep art: budgets per preset and the phone triangle caps", function()
		local n, tris = DeepArtKit.budget(Config, lay)
		check(n <= 600, "at most 600 meshes in the Deep (" .. n .. ")")
		check(tris <= 450000, "at most 450k triangles in the whole Deep (" .. tris .. ")")
		local function lookTris(look: string): number
			local t = 0
			for _, m in FIT[look].meshes do
				t += m.tris
			end
			return t
		end
		for look, cap in
			{ DiverHelmet = 1500, DiverTank = 800, Torpedo = 800, KelpStrand = 1600, AirBubble = 1400 }
		do
			check(lookTris(look) <= cap, look .. " under " .. cap .. " triangles (" .. lookTris(look) .. ")")
		end
		for look in FIT do
			if string.sub(look, 1, 5) == "Coral" then
				check(lookTris(look) <= 1300, look .. " under 1300 triangles")
			end
		end
		local A = Config.Deep.art
		local kelp = 0
		for _, p in lay.art do
			kelp += if p.tag == "kelp" then 1 else 0
		end
		check(kelp == 82, "82 kelp strands sway (" .. kelp .. ")")
		local lastNear, lastMax = -1, -1
		for _, preset in Config.Presets.order do
			local near, max = DeepArtKit.swayBudget(Config, preset)
			check(near >= lastNear and max >= lastMax, preset .. " sways no less than the preset below")
			check(max <= kelp, preset .. " sways at most every strand")
			check((A.caustics[preset] or 0) >= 0, preset .. " has a caustics size")
			lastNear, lastMax = near, max
		end
		check(
			select(2, DeepArtKit.swayBudget(Config, "low")) == 0 and A.caustics.low == 0,
			"phones on low: no sway, no caustics"
		)
		-- the sway: within its angle, smooth, the same on every device
		local amp = math.rad(A.kelp.angle)
		for t = 0, 20, 0.7 do
			local rx, rz = DeepArtKit.sway(Config, t, 120, 2600)
			check(
				math.abs(rx) <= amp + 1e-9 and math.abs(rz) <= amp + 1e-9,
				"the lean stays within its angle"
			)
		end
		local a1, b1 = DeepArtKit.sway(Config, 3, 10, 20)
		local a2, b2 = DeepArtKit.sway(Config, 3, 10, 20)
		check(a1 == a2 and b1 == b2, "the sway is a function of time and place")
		-- the client loops sit under FrameProf and the preset
		local dc = "src/client/Controllers/DeepClient.luau"
		check(has(dc, 'FrameProf.wrap("DeepClient", step)'), "DeepClient's loop is under FrameProf")
		check(has(dc, "DeepArtKit.swayBudget(Config, QualityController.name)"), "the sway reads the preset")
		check(has(dc, "cfg[QualityController.name]"), "the caustics read the preset")
	end)

	test("Deep art: the marker, the commuters and the sea robots' gear", function()
		local dc = "src/client/Controllers/DeepClient.luau"
		check(Config.Deep.art.marker ~= 0, "the drawn cache marker is uploaded")
		check(Config.Deep.art.caustics.image ~= 0, "the caustics image is uploaded")
		check(has(dc, "cacheMarker(glow"), "a cache wears the drawn marker")
		check(
			has(dc, "NpcRig.person(") and has(dc, 'DeepMeshes.look("AirBubble"'),
			"commuters are people in a bubble"
		)
		check(not has(dc, "a small citizen figure"), "the blocky part figure is gone")
		local er = "src/client/Controllers/EnemyRenderer.luau"
		check(
			has(er, 'Helmet = "DiverDome"') and has(er, 'Tank = "DiverTank"'),
			"divers wear the Deep set's gear"
		)
		check(
			has("src/client/Fx/CombatFx.luau", 'DeepMeshes.clone("Torpedo"'),
			"torpedoes are the Deep set's mesh"
		)
		-- the import: every mesh in art/models/Deep.rbxm, textured ones with their four maps
		local ok, ids = pcall(fs.readFile, "art/models/deep_meshids.json")
		check(ok, "Deep.rbxm is pulled (art/models/deep_meshids.json)")
		if ok then
			for _, fit in FIT do
				for name, m in fit.meshes do
					check(
						string.find(ids, '"' .. name .. '"', 1, true) ~= nil,
						name .. " is in the pulled model"
					)
					if m.maps then
						local maps =
							string.match(ids, '"' .. name .. '%.SurfaceAppearance#maps"%s*:%s*(%b[])')
						local k = 0
						for id in string.gmatch(maps or "", "%d+") do
							k += if (tonumber(id) or 0) > 0 then 1 else 0
						end
						check(k == 4, name .. " keeps its four maps (" .. k .. ")")
					end
				end
			end
			check(
				has("default.project.json", '"Deep": { "$path": "art/models/Deep.rbxm" }'),
				"Rojo maps Art.Deep"
			)
		end
	end)
end
