-- The wrecks and Crater art pass (gap-wrecks, 2026-11-19): art/blender/wrecks.py's downed-robot heaps over
-- ThrowService's plain wreck (Shared.WreckArtKit), their sparks and pop through the effects library (ThrowFx,
-- FxLib, Config.Fx.lib.wreck), and art/blender/crater.py's Crane lab ruins over the Crater's boxes
-- (Shared.CraterArtKit, CityBuilder, Fx.CraterDecor), with the boxes' collision exactly as before.
-- Called from tests/run.luau:
--   require("./wrecks_art_test")({ test = test, check = check, Config = Config, placePath = placePath })
-- ONLY="Wreck art" or ONLY="Crater art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local ThrowMath = require("../src/shared/ThrowMath")
	local WreckArtKit = require("../src/shared/WreckArtKit")
	local CraterArtKit = require("../src/shared/CraterArtKit")
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

	test(
		"Wreck art: every wrecking robot kind has its heap look, built on its heap box, eyes and no face",
		function()
			local bad = WreckArtKit.check(Config, ThrowMath)
			check(#bad == 0, "WreckArtKit.check: " .. table.concat(bad, "; "))
			local kinds = 0
			for kind, cfg in Config.Enemies do
				if type(cfg) == "table" and cfg.body and ThrowMath.canWreck(cfg) then
					kinds += 1
					local fit = Config.WreckArt[WreckArtKit.lookOf(kind)]
					local tris = 0
					for name, m in fit.meshes do
						tris += m.tris or 0
						-- faces and hair are catalog items: a wreck never models one
						local low = string.lower(name)
						check(
							not string.find(low, "face") and not string.find(low, "hair"),
							kind .. " draws no face or hair (" .. name .. ")"
						)
						check(m.mat ~= "Neon", kind .. " " .. name .. ": a wreck is powered down (no Neon)")
					end
					check(
						tris > 0 and tris <= Config.Throw.wreck.tris,
						kind .. " wreck under its triangle cap: " .. tris
					)
				end
			end
			check(kinds >= 10, "the wrecking kinds are all there: " .. kinds)
			-- ready only once every mesh is found (the plain heap otherwise)
			local some = next(Config.WreckArt)
			check(some ~= nil, "Config.WreckArt is indexed")
			local kind = string.sub(some :: string, 6)
			check(not WreckArtKit.ready(Config, kind, function()
				return false
			end), "nothing imported: the plain heap")
			local first = true
			check(not WreckArtKit.ready(Config, kind, function()
				local was = first
				first = false
				return was
			end), "half imported: the plain heap")
			check(
				WreckArtKit.ready(Config, kind, function()
					return true
				end),
				"all imported: the look"
			)
		end
	)

	test(
		"Wreck art: ThrowService draws the look over its hidden Body box, plain parts when missing",
		function()
			local s = fs.readFile("src/server/Services/ThrowService.luau")
			check(has(s, "WreckArtKit.ready(Config, kind"), "the look only once every mesh is in")
			check(
				has(s, "main.Transparency = 1"),
				"the Body box stays, hidden: still the collider and the carry's part"
			)
			check(
				has(s, "p.CanCollide = false") and has(s, "p.CanQuery = false"),
				"the meshes never collide or query"
			)
			check(has(s, '"Head"') and has(s, '"Arm"'), "the plain heap stays the fallback")
			check(
				has(s, 'SetAttribute("WreckSuit"') and has(s, 'SetAttribute("WreckEye"'),
				"colours for ThrowFx"
			)
		end
	)

	test("Wreck art: sparks, blink and pop are textured particles through FxLib inside the budget", function()
		local L = Config.Fx.lib
		check(L.kinds.bolt ~= nil and L.textures.bolt ~= nil, "the bolt kind and its texture")
		check(L.kinds.bolt.light == 0, "a nut never glows")
		check(fs.isFile("art/export/fx/" .. L.textures.bolt.file), "bolt.png drawn")
		local tex = FxPlan.textureOf(L, "bolt")
		check(tex ~= "", "the bolt has a texture (uploaded or built-in)")
		for _, moment in { "spark", "pop" } do
			for preset, share in L.scale do
				local n = 0
				for _, e in FxPlan.wreckPlan(L, moment, share) do
					check(L.kinds[e.kind] ~= nil, moment .. " names a real kind: " .. e.kind)
					n += e.count
				end
				check(n > 0, moment .. " draws something on " .. preset)
				-- the server's wrecks at once all popping in one second stay inside half the budget
				if moment == "pop" then
					check(
						n * Config.Throw.wreck.max <= L.budget[preset] / 2,
						"pops fit on " .. preset .. ": " .. n
					)
				end
			end
		end
		local fx = fs.readFile("src/client/Fx/ThrowFx.luau")
		check(
			has(fx, 'FxLib.wreckMoment("spark"') and has(fx, 'FxLib.wreckMoment("pop"'),
			"ThrowFx uses FxLib"
		)
		check(not has(fx, "Enum.Material.Neon\n\t\tp.Color = SPARK"), "no plain neon spark parts left")
		check(has(fx, 'FrameProf.wrap("ThrowFx"'), "the wrecks' loop stays under FrameProf")
		check(has(fx, "W.sparkRange"), "sparks only near the camera")
	end)

	test("Crater art: the lab's collision is exactly as before the art pass", function()
		local lm = crater()
		check(lm ~= nil, "the Crater landmark")
		if not lm then
			return
		end
		local rows = {}
		for _, b in lm.boxes do
			table.insert(
				rows,
				string.format(
					"%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.2f|%s|%s|%s|%s|%s",
					b.kind,
					b.cx,
					b.cy,
					b.cz,
					b.sx,
					b.sy,
					b.sz,
					b.ry or 0,
					tostring(b.shape),
					tostring(b.ghost),
					tostring(b.color),
					tostring(b.kit),
					tostring(b.tint)
				)
			)
		end
		check(#lm.boxes == 90, "90 boxes as before: " .. #lm.boxes)
		check(
			serde.hash("sha256", table.concat(rows, "\n"))
				== "f9ecc21faa6921a821f3f8b9c3b677785ff33566364e43eefabc02cea9fb2cc2",
			"every box where and what it was (the meshes only hide them)"
		)
	end)

	test(
		"Crater art: every ruin piece has its look, fitted to its boxes, under the Crater's height rules",
		function()
			local lm = crater()
			if not lm then
				check(false, "the Crater landmark")
				return
			end
			local bad = CraterArtKit.check(Config, lm.boxes, lm.art)
			check(#bad == 0, "CraterArtKit.check: " .. table.concat(bad, "; "))
			local C = Config.World.crater
			local want = {
				"CraterWall",
				"CraterTank",
				"CraterTower",
				"CraterHusk",
				"CraterCape",
				"CraterShield",
				"CraterHelmet",
			}
			for _, w in want do
				local found = false
				for _, p in lm.art do
					found = found or string.sub(p.look, 1, #w) == w
				end
				check(found, "the ruins have " .. w)
			end
			local tagged = 0
			for _, b in lm.boxes do
				if b.art then
					tagged += 1
				end
			end
			check(tagged > 20, "the lab's boxes are covered: " .. tagged)
			for _, p in lm.art do
				for _, m in CraterArtKit.meshes(Config, p) do
					local top = p.cy + m.offset[2] + m.size[2] / 2 - lm.floorY
					check(
						top <= C.maxTop + 0.5,
						p.look .. " " .. m.name .. " under the Crater's maxTop: " .. top
					)
					local r = math.sqrt((p.cx - lm.centre.x) ^ 2 + (p.cz - lm.centre.z) ^ 2)
					if r < C.openRadius then
						check(top <= C.openTop + 0.5, p.look .. " keeps the open middle low")
					end
				end
			end
			local n, tris = CraterArtKit.budget(Config, lm.art)
			check(
				n > 0 and tris <= C.art.tris,
				string.format("the lab's meshes under the cap: %d tris", tris)
			)
		end
	)

	test(
		"Crater art: the loose bits scale with the preset (none on phones), seeded, clear of the lab",
		function()
			local lm = crater()
			if not lm then
				check(false, "the Crater landmark")
				return
			end
			local C = Config.World.crater
			for _, preset in { "low", "medium", "high" } do
				local a = CraterArtKit.bits(Config, lm.centre.x, lm.centre.z, lm.art, preset)
				local b = CraterArtKit.bits(Config, lm.centre.x, lm.centre.z, lm.art, preset)
				check(#a == Config.Presets[preset].ruins.bits, preset .. " lays its preset's bits: " .. #a)
				check(
					#a == #b and (#a == 0 or (a[1].x == b[1].x and a[#a].look == b[#b].look)),
					"seeded: " .. preset
				)
				for _, bit in a do
					check(Config.CraterArt[bit.look] ~= nil, "a bit is a real look: " .. bit.look)
					local r = math.sqrt((bit.x - lm.centre.x) ^ 2 + (bit.z - lm.centre.z) ^ 2)
					check(r >= C.art.ring[1] - 0.01 and r <= C.art.ring[2] + 0.01, "on the floor's ring")
					for _, p in lm.art do
						check(
							not CraterArtKit.inside(p, bit.x, p.cy, bit.z, 0),
							bit.look .. " never inside " .. p.look
						)
					end
					local fit = Config.CraterArt[bit.look]
					check(fit.frame[2] <= C.openTop, bit.look .. " lies low")
				end
			end
			check(Config.Presets.low.ruins.bits == 0, "phones draw no bits")
			local cb = fs.readFile("src/server/Services/CityBuilder.luau")
			check(has(cb, "CraterArtKit.hides(b, ready)"), "CityBuilder hides only the ready looks' boxes")
			check(has(cb, 'artSource("Crater"'), "the Crater's meshes from Art.Crater")
			local cd = fs.readFile("src/client/Fx/CraterDecor.luau")
			check(has(cd, "p.CanCollide = false") and has(cd, "p.CanQuery = false"), "the bits are ghosts")
			check(not has(cd, "RenderStepped") and not has(cd, "Heartbeat"), "no per-frame loop")
		end
	)

	if T.placePath then
		test(
			"Wreck art: Art.Wrecks and Art.Crater are in the place, every mesh uploaded, textures kept",
			function()
				local roblox = require("@lune/roblox")
				local game = roblox.deserializePlace(fs.readFile(T.placePath))
				local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
				for _, pair in { { "Wrecks", Config.WreckArt }, { "Crater", Config.CraterArt } } do
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
								check(
									string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil,
									name .. " is uploaded"
								)
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
			end
		)
	end
end
