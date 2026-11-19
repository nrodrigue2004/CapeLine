-- The Ceremony prologue's art pass (gap-prologue, 2026-11-19): art/blender/prologue.py's looks over PrologueFx's plain
-- parts (Shared.PrologueArtKit, Fx.PrologueMeshes), the printed banner and billboard, and the place's Art.Prologue.
-- Called from tests/run.luau:
--   require("./prologue_art_test")({ test = test, check = check, Config = Config, placePath = placePath })
-- ONLY="Prologue art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local PrologueArtKit = require("../src/shared/PrologueArtKit")
	local FIT = Config.PrologueArt
	local O = Config.Story.opening

	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	-- every prop the placeholder list named, and the look that draws it
	local PROPS = {
		deck = "Stage",
		trim = "Stage",
		stairs = "Stage",
		podium = "Podium",
		banner = "HallBanner",
		spotlights = "Spotlights",
		barriers = "Barriers",
		scanner = "Scanner",
		sign = "FallingSign",
		slab = "Slab",
		rubble = "Rubble",
		billboard = "Billboard",
	}

	test("Prologue art: every listed prop has its meshes and fit data, in the phone budget", function()
		check(type(FIT) == "table", "Config.PrologueArt is indexed")
		for prop, look in PROPS do
			check(PrologueArtKit.LOOKS[look] ~= nil, prop .. " has a look (" .. look .. ")")
			local fit = FIT and FIT[look]
			check(type(fit) == "table" and next(fit) ~= nil, look .. " has fit data")
		end
		local total = 0
		for look in PrologueArtKit.LOOKS do
			local fit = FIT[look] or {}
			local textured = 0
			for name, row in fit do
				check(string.sub(name, 1, #look) == look, name .. " is named after its look " .. look)
				check(
					#row.size == 3 and row.size[1] > 0 and row.size[2] > 0 and row.size[3] > 0,
					name .. " size"
				)
				check(#row.offset == 3 and #row.color == 3, name .. " offset and colour")
				check(type(row.tris) == "number" and row.tris > 0 and row.tris < 10000, name .. " triangles")
				total += row.tris
				if row.maps then
					textured += 1
				end
				if row.alpha then
					check(row.mat == "Neon" and row.alpha < 1, name .. ": only light beams are see-through")
				end
			end
			check(textured >= 1, look .. " has a baked texture set")
		end
		-- the whole prologue scene, every look at once (it is only ever on the one hero's device)
		check(total > 0 and total < 40000, "prologue art triangles " .. total)
		local bad = PrologueArtKit.check(Config)
		check(#bad == 0, "every look fits its part: " .. table.concat(bad, "; "))
	end)

	test("Prologue art: the Blender script builds on the game's own numbers", function()
		local py = src("art/blender/prologue.py")
		local P, S, B = O.plaza.stage, O.subway, O.billboard
		local function tuple(name: string): { number }
			local line = string.match(py, "\n" .. name .. " = %(([^)]*)%)")
			local out = {}
			for v in string.gmatch(line or "", "[-%d%.]+") do
				table.insert(out, tonumber(v) :: number)
			end
			return out
		end
		local deck = tuple("DECK")
		check(deck[1] == P.width and deck[2] == P.height and deck[3] == P.depth, "the deck's size")
		local slab, rubble, board = tuple("SLAB"), tuple("RUBBLE"), tuple("BOARD")
		check(slab[1] == S.width - 1 and slab[3] == S.slab, "the slab's size")
		check(rubble[1] == S.width - 1 and rubble[2] == S.rubble and rubble[3] == S.slab, "the rubble's size")
		check(board[1] == B.size[1] and board[2] == B.size[2], "the billboard's size")
		local f = PrologueArtKit.frames(Config)
		check(f.steps.size[1] == 10 and f.steps.size[2] == P.height / 2, "the steps PrologueFx builds")
	end)

	test("Prologue art: colliding geometry and the route are unchanged (looks only)", function()
		local fx = src("src/client/Fx/PrologueFx.luau")
		-- the deck and the steps stay the colliding floor, at the same size and place
		check(
			has(fx, "Vector3.new(P.width, P.height, P.depth),\n\t\tbase,\n\t\tColor3.fromRGB(70, 74, 92),")
				and has(fx, "Enum.Material.Concrete,\n\t\ttrue\n\t)"),
			"the deck collides as before"
		)
		check(
			has(
				fx,
				"Vector3.new(10, P.height / 2, 4),\n\t\tbase * CFrame.new(0, -P.height / 4, -P.depth / 2 - 2),"
			),
			"the steps stand where they stood"
		)
		-- the slab falls the same and its rubble shuts the way back by OpeningPlan.rubbleShuts
		check(has(fx, "Vector3.new(S.width - 1, 3, S.slab)"), "the falling slab's part")
		check(has(fx, "Size = Vector3.new(S.width - 1, S.rubble, S.slab)"), "the rubble's part")
		check(
			has(fx, "OpeningPlan.rubbleShuts(Config, lane, k, r.Position.Z)"),
			"the rubble's collision rule"
		)
		check(has(fx, "OpeningPlan.slabFalls(Config, lane, k, r.Position.Z)"), "the cave-in rule")
		-- the meshes never collide, query or touch; a hidden part keeps its collision (no CanCollide change)
		local pm = src("src/client/Fx/PrologueMeshes.luau")
		check(has(pm, "p.CanCollide = false") and has(pm, "p.CanQuery = false"), "meshes never collide")
		check(not has(pm, "CanCollide = true"), "PrologueMeshes never makes anything solid")
		local hide = string.match(pm, "function PrologueMeshes%.hide.-\nend")
		check(hide ~= nil and not has(hide :: string, "CanCollide"), "hiding a part keeps its collision")
		-- the scan keeps its path and lock time; the guided hops and beat clocks are not touched here
		check(has(fx, "local lock = O.beats.scan * 0.42"), "the scan locks at the same moment")
		check(
			has(fx, "math.sin(t / lock * math.pi * 1.5) * 26 * (1 - t / lock)"),
			"the scan sweeps the same path"
		)
		check(has(fx, "MoveController.hopAssist = function()"), "the guided hops are still PrologueFx's")
		-- nothing drawn: Crane's face on the billboard is his rig's catalog face (no UI-shape face)
		check(not has(fx, "smiling face (PLACEHOLDER ART: drawn with shapes)"), "no drawn face")
		check(has(fx, "craneRig(C.scale)"), "Crane stands on the billboard as his rig")
	end)

	test("Prologue art: the billboard frame stays off the wall, Crane stands on its catwalk", function()
		local lo, hi = PrologueArtKit.bounds(Config, "Billboard")
		-- the board's centre is 1.5 studs off the building's face (OpeningPlan.route)
		check(hi[3] <= 1.45, string.format("the frame's back at %.2f, the wall at 1.5", hi[3]))
		local walk = Config.PrologueArt.Billboard.BillboardBody
		check(walk ~= nil, "the frame mesh")
		local C = PrologueArtKit.CRANE
		local B = O.billboard
		check(math.abs(C.at[1]) < B.size[1] / 2 - 6, "Crane stands within the board's width")
		check(C.at[2] < -B.size[2] / 2 and C.at[2] > lo[2], "Crane stands below the board, on the catwalk")
		check(C.at[3] < 0 and C.at[3] > lo[3], "Crane stands in front of the board")
		-- the ad's left third is his: the picture's left is the board's +x seen from the front
		check(C.at[1] > 0, "Crane on the picture's left (the board's +x)")
	end)

	test("Prologue art: the printed banner and billboard", function()
		check(type(O.art) == "table", "Config.Story.opening.art")
		check(type(O.art.banner) == "number" and O.art.banner > 0, "the Hall's banner is uploaded")
		check(type(O.art.billboard) == "number" and O.art.billboard > 0, "the billboard ad is uploaded")
		local ads = src("art/prologue/ads.py")
		check(
			has(ads, 'fixed("brand"), fixed("slogan"), fixed("hall")'),
			"the pictures print the game's fixed text"
		)
		-- the effects: the shield and the sweep use the pooled library (its budget and Reduce flashing)
		local fx = src("src/client/Fx/PrologueFx.luau")
		check(has(fx, 'FxLib.emit("hex", color'), "the shield's hex plates")
		check(has(fx, 'FxLib.emit("rune", SCAN_RED'), "the scan's target rune")
		check(
			has(fx, "if CombatFx.reduceFlashing then 0 else"),
			"the lock ring holds still with Reduce flashing"
		)
	end)

	if T.placePath then
		test("Prologue art: Art.Prologue is in the place, every mesh uploaded, textures kept", function()
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(T.placePath))
			local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
			local set = art and art:FindFirstChild("Prologue")
			check(set ~= nil, "ReplicatedStorage.Art.Prologue")
			if not set then
				return
			end
			for look, fit in FIT do
				for name, row in fit do
					local m = set:FindFirstChild(name, true)
					check(m ~= nil and m:IsA("MeshPart"), "Art.Prologue has " .. name)
					if m and m:IsA("MeshPart") then
						check(string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil, name .. " is uploaded")
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
		end)
	end
end
