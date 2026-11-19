-- fix-models (nate's playtest of gaps7, 2026-11-19: "A lot of our models don't look that bad they just aren't
-- configured properly. Like the leviathan engine's parts just aren't placed properly. This is consistent throughout
-- the game"). Root cause: Roblox's Open Cloud FBX import turned every mesh 180 degrees about y inside its MeshPart
-- (art/upload/meshcheck.py downloads each MeshId and compares Roblox's geometry with our FBX; per-set verdicts in
-- art/models/meshturns.json), so each piece sat in the right box but faced backwards and no longer met the pieces
-- beside it. Shared.MeshFix holds the correction; every place that clones an imported mesh applies it.
-- These checks build each assembly with the REAL game code from the built place (tests/uisim.luau stand-ins): the
-- bosses (WorldFx), the shell rigs (NpcRig: Spark Trooper, the three finales, the HQ dummy) and a piece fixed to
-- them, every creator kit and cape (LookKit), every HQ, hideout, set piece and vehicle look (HqMeshes,
-- SetPieceMeshes), the street props (CityProps), the story, prologue and deep looks. For every MeshPart the
-- geometry's frame as Roblox shows it (its CFrame times the measured import turn) must sit where the Blender
-- script laid it out (the Config.*Art offset from its anchor, unturned, and its size): within 0.3 stud and 5
-- degrees. A static check makes sure every file that clones from ReplicatedStorage.Art goes through MeshFix.
-- ONLY="Model fit" runs just these. Called from tests/run.luau.

return function(T: any)
	local test, check = T.test, T.check
	local Config = T.Config
	local placePath: string? = T.placePath
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local roblox = require("@lune/roblox")
	local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

	local POS, DEG, SIZE = 0.3, 5, 0.3
	local MEASURED = serde.decode("json", fs.readFile("art/models/meshturns.json"))
	local TURNED = CFrame.Angles(0, math.pi, 0)

	-- the turn Roblox's copy of a set's meshes has, as measured (not from MeshFix: the test's own reference)
	local function measured(set: string?): any
		local m = set and MEASURED[set]
		if m and m.verdict == "rotY180" then
			return TURNED
		end
		return CFrame.identity
	end

	local function angleOf(cf: any): number
		local _, a = cf:ToAxisAngle()
		return math.deg(math.abs(a))
	end

	-- One tally per assembly: every MeshPart's shown geometry frame against the Blender layout
	local function tally(): any
		return { n = 0, worst = 0, worstDeg = 0, bad = {} }
	end
	local function compare(t: any, label: string, p: any, want: any, wantSize: any?)
		t.n += 1
		local set = p:GetAttribute("MeshSet")
		local shown = p.CFrame * measured(set):Inverse()
		local dp = (shown.Position - want.Position).Magnitude
		local da = angleOf(want:ToObjectSpace(shown))
		local ds = if wantSize then (p.Size - wantSize).Magnitude else 0
		t.worst = math.max(t.worst, dp)
		t.worstDeg = math.max(t.worstDeg, da)
		if dp > POS or da > DEG or ds > SIZE then
			table.insert(
				t.bad,
				string.format(
					"%s %s (%s): %.2f studs, %.0f deg, size %.2f off",
					label,
					p.Name,
					tostring(set),
					dp,
					da,
					ds
				)
			)
		end
	end
	local function verdict(t: any, what: string, least: number)
		print(
			string.format(
				"  [model fit] %-24s %4d meshes, worst %.3f stud, %.1f deg, %d off",
				what,
				t.n,
				t.worst,
				t.worstDeg,
				#t.bad
			)
		)
		check(
			t.n >= least,
			string.format("%s: %d meshes placed by the game's code (want %d or more)", what, t.n, least)
		)
		check(
			#t.bad == 0,
			string.format(
				"%s: every mesh where Blender drew it (%d meshes, worst %.3f stud, %.1f deg)%s",
				what,
				t.n,
				t.worst,
				t.worstDeg,
				if #t.bad > 0 then ":\n    " .. table.concat(t.bad, "\n    ", 1, math.min(#t.bad, 8)) else ""
			)
		)
	end
	local function v3(t: { number }): any
		return Vector3.new(t[1], t[2], t[3])
	end

	-- the real game code on stand-in instances
	local sim: any = nil
	local UiSim: any = nil
	local function boot(): any
		if sim then
			return sim
		end
		UiSim = require("./uisim")
		local place = roblox.deserializePlace(fs.readFile(placePath :: string))
		local trees = UiSim.load(place)
		sim = UiSim.new(trees, { name = "PC", w = 1920, h = 1080, top = 36, left = 0, right = 0, bottom = 0 })
		return sim
	end
	-- a server module (not in the sim's trees) loaded from its source beside Shared
	local function serverModule(name: string): any
		local s = boot()
		local m = UiSim.newInstance("ModuleScript")
		m.Name = name
		m._props.Source = fs.readFile("src/server/Services/" .. name .. ".luau")
		m.Parent = s.place.ReplicatedStorage
		return s:_requireInstance(m)
	end
	local function folder(): any
		return UiSim.newInstance("Folder")
	end
	local function meshParts(root: any): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("MeshPart") then
				table.insert(out, d)
			end
		end
		return out
	end

	test(
		"Model fit: Shared.MeshFix agrees with every measured art set (art/models/meshturns.json)",
		function()
			local s = boot()
			local MeshFix = s:require("Shared.MeshFix")
			local art = s.place.ReplicatedStorage:FindFirstChild("Art")
			check(art ~= nil, "the place has ReplicatedStorage.Art")
			local n = 0
			for _, set in art:GetChildren() do
				local m = MEASURED[set.Name]
				check(m ~= nil, set.Name .. " is measured by meshcheck.py (run it after any import)")
				if m then
					n += 1
					local turn = MeshFix.turn(set.Name)
					if m.verdict == "rotY180" then
						check(
							angleOf(turn:ToObjectSpace(TURNED)) < 0.1,
							set.Name .. ": MeshFix turns it 180 degrees about y"
						)
					elseif m.verdict == "identity" then
						check(angleOf(turn) < 0.1, set.Name .. ": MeshFix leaves it as drawn")
					else
						check(
							m.verdict == "symmetric",
							set.Name .. ": verdict " .. tostring(m.verdict) .. " is clear"
						)
					end
				end
			end
			check(n >= 40, string.format("%d imported sets measured", n))
		end
	)

	test("Model fit: every file that clones an imported mesh goes through Shared.MeshFix", function()
		-- each file that takes MeshParts from ReplicatedStorage.Art (or a kit's mesh source) and clones them
		local files = {
			"src/client/Fx/WorldFx.luau",
			"src/client/Fx/DeepMeshes.luau",
			"src/client/Fx/StoryProps.luau",
			"src/client/Fx/HqMeshes.luau",
			"src/client/Fx/ActivityProps.luau",
			"src/client/Fx/PrologueMeshes.luau",
			"src/client/Fx/CraterDecor.luau",
			"src/client/Fx/CombatFx.luau",
			"src/client/Fx/VehicleRig.luau",
			"src/client/Controllers/PocketDecor.luau",
			"src/client/Controllers/CityProps.luau",
			"src/client/Controllers/EnemyRenderer.luau",
			"src/server/Services/CityBuilder.luau",
			"src/server/Services/SetPieceMeshes.luau",
			"src/server/Services/ThrowService.luau",
			"src/server/Services/NewsService.luau",
			"src/server/Services/BoardService.luau",
			"src/server/Services/LookService.luau",
			"src/shared/LookKit.luau",
			"src/shared/NpcRig.luau",
		}
		for _, path in files do
			local s = fs.readFile(path)
			check(string.find(s, "MeshFix", 1, true) ~= nil, path .. " uses Shared.MeshFix")
			-- a bare clone of a source mesh would skip the set tag the turn is found by (LookKit's and NpcRig's
			-- `src` clones are Roblox catalog accessories, which are not ours and need no turn)
			local catalog = string.find(path, "LookKit", 1, true) or string.find(path, "NpcRig", 1, true)
			for _, bare in
				{
					"= src:Clone()",
					"= srcs[i]:Clone()",
					"= pc.src:Clone()",
					"= mesh:Clone()",
					"= found:Clone()",
				}
			do
				if catalog and bare == "= src:Clone()" then
					continue
				end
				check(string.find(s, bare, 1, true) == nil, path .. " has no bare `" .. bare .. "` left")
			end
		end
		-- and nothing else in src clones from Art without it
		local function walk(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					walk(path)
				elseif
					string.sub(name, -5) == ".luau"
					and not string.find(path, "WeaponKit", 1, true)
					and not string.find(path, "LookKit", 1, true)
					and not string.find(path, "NpcRig", 1, true)
				then
					local s = fs.readFile(path)
					local fromArt = string.find(s, 'FindFirstChild("Art")', 1, true) ~= nil
					if fromArt and string.find(s, "src:Clone()", 1, true) then
						check(false, path .. " clones an imported mesh without Shared.MeshFix")
					end
				end
			end
		end
		walk("src")
	end)

	test(
		"Model fit: the world bosses (WorldFx, the Leviathan Engine and every other) as Blender laid them out",
		function()
			local s = boot()
			local WorldFx = s:require("Client.Fx.WorldFx")
			local B = Config.Boss
			local ids = {}
			for id in Config.BossArt do
				if type(Config.BossArt[id]) == "table" and Config.BossArt[id].pieces then
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			check(#ids >= 4, "4 bosses with meshes (" .. table.concat(ids, ", ") .. ")")
			for _, id in ids do
				local t = tally()
				local def = B.bosses[id]
				local sh = WorldFx._build(id, { x = 0, y = 0, z = 0, yaw = 0, state = "fight", id = id })
				local fit = Config.BossArt[id]
				for _, p in sh.model:GetChildren() do
					local row = fit.pieces[p.Name]
					if row and p:IsA("MeshPart") then
						compare(t, id, p, CFrame.new(v3(row.offset)), v3(row.size))
					end
				end
				-- the objectives on the body (shoulder cannons, vent hatches, torpedo bays) at their Config.Boss point
				for _, orow in def.objectives.list do
					if orow.at then
						local at = CFrame.new(v3(orow.at))
						for _, p in sh.model:GetChildren() do
							local prow = fit.objective[p.Name]
							if p:IsA("MeshPart") and prow then
								-- (several objectives share a name: take the nearest one's frame)
								local want = at * CFrame.new(v3(prow.offset))
								if (p.Position - want.Position).Magnitude < 0.5 then
									compare(t, id .. " objective", p, want, v3(prow.size))
								end
							end
						end
					end
				end
				local count = 0
				for _ in fit.pieces do
					count += 1
				end
				verdict(t, id, count)
			end
		end
	)

	test(
		"Model fit: the shell rigs (Spark Trooper, the finales, the HQ dummy) and a piece fixed to them",
		function()
			local s = boot()
			local NpcRig = s:require("Shared.NpcRig")
			local RigMath = s:require("Shared.RigMath")
			for _, look in { "Trooper", "Bramblebeast", "Voidhound", "WindupGiant", "Hq" } do
				local t = tally()
				local layout = RigMath.layout(Config.HeroRig, nil, 1.3)
				local colors = {}
				local rig = NpcRig.build(layout, "Fit" .. look, colors, nil, nil, nil, look)
				for pname, p in rig.parts do
					check(p:IsA("MeshPart"), look .. " " .. pname .. " is its shell mesh")
					compare(t, look, p, CFrame.new(v3(layout.centres[pname])), v3(layout.parts[pname].size))
					-- every attachment where the layout puts it (in the world)
					for aname, at in layout.parts[pname].attachments do
						local a = p:FindFirstChild(aname)
						if a then
							local world = (p.CFrame * a.CFrame).Position
							local want = v3(layout.centres[pname]) + v3(at)
							check(
								(world - want).Magnitude < 0.01,
								look .. " " .. pname .. "." .. aname .. " where the layout puts it"
							)
						end
					end
				end
				-- every joint holds its two parts where they stand, and its frame is the drawn one (poses turn the right way)
				for jname, m in rig.motors do
					local solved = m.Part0.CFrame * m.C0 * m.C1:Inverse()
					check(
						(solved.Position - m.Part1.CFrame.Position).Magnitude < 0.01
							and angleOf(solved:ToObjectSpace(m.Part1.CFrame)) < 0.5,
						look .. " joint " .. jname .. " solves to where its part stands"
					)
					check(
						angleOf(m.Part0.CFrame * m.C0) < 0.5,
						look .. " joint " .. jname .. " turns about the drawn axes"
					)
				end
				-- a Robots mesh fixed to the chest: where the drawn chest frame and c0 put it
				local src = s.place.ReplicatedStorage.Art.Robots:FindFirstChild("Core", true)
				local MeshFix = s:require("Shared.MeshFix")
				local piece = MeshFix.clone(src)
				local c0 = CFrame.new(0.1, 0.3, -0.4)
				NpcRig.fix(rig, "UpperTorso", piece, c0, "FitPiece")
				local chest = CFrame.new(v3(layout.centres.UpperTorso))
				compare(t, look .. " fixed", piece, chest * c0, nil)
				local m = rig.motors.FitPiece
				local solved = m.Part0.CFrame * m.C0 * m.C1:Inverse()
				check(
					(solved.Position - piece.CFrame.Position).Magnitude < 0.01,
					look .. ": the fixed piece's joint solves to it"
				)
				-- a held pose (NpcRig.bend) keeps the shoulder's rest turn
				NpcRig.bend(rig, "RightShoulder", CFrame.Angles(0, 0, math.rad(30)))
				local sh = rig.motors.RightShoulder
				check(
					angleOf(sh.Part0.CFrame * sh.C0) > 29 and angleOf(sh.Part0.CFrame * sh.C0) < 31,
					look .. ": a bend turns the shoulder 30 degrees from the drawn frame"
				)
				verdict(t, look, 16)
			end
		end
	)

	-- fix-bodies (2026-11-19): the Body step's torsos go on Roblox's own body with MeshPart:ApplyMesh, in place,
	-- which cannot turn a mesh, so the worn mesh must come from a set Roblox stored as drawn (Art.BodyTorsos, the
	-- pre-turned upload), never from a turned one (Art.Bodies)
	test("Model fit: the body sets' torsos on Roblox's own body (LookKit.wearBodySet)", function()
		local s = boot()
		local LookKit = s:require("Shared.LookKit")
		local BodyShape = s:require("Shared.BodyShape")
		local RigMath = s:require("Shared.RigMath")
		local MeshFix = s:require("Shared.MeshFix")
		local R = Config.RobloxRig.parts
		-- Roblox's own body as HeroBody publishes it (ReplicatedStorage.RobloxBody) and a character on it
		local rb = UiSim.newInstance("Folder")
		rb.Name = "RobloxBody"
		for _, j in RigMath.JOINTS do
			local m = UiSim.newInstance("MeshPart")
			m.Name = j[3]
			m.MeshId = "rbxassetid://1" .. j[3]
			m.Parent = rb
		end
		rb.Parent = s.place.ReplicatedStorage
		local worn, kinds = 0, 0
		for _, g in { 1, 2 } do
			for b = 1, 4 do
				local look = { gender = g, build = b, height = 3 }
				local key = BodyShape.setKey(Config, look)
				local char = UiSim.newInstance("Model")
				local applied: { [string]: any } = {}
				for name, row in R do
					local p = UiSim.newInstance("MeshPart")
					p.Name = name
					p.Size = v3(row.size)
					p.MeshId = "rbxassetid://1" .. name
					p.ApplyMesh = function(self: any, src: any)
						applied[self.Name] = src
						self.MeshId = "rbxassetid://applied" .. src.Name
					end
					p.Parent = char
				end
				check(LookKit.onRobloxBody(char), key .. ": the character reads as Roblox's own body")
				LookKit.wearBodySet(char, look)
				check(char:GetAttribute("BodySet") == key, key .. ": the set is marked worn")
				kinds += 1
				for name, src in applied do
					worn += 1
					check(
						name == "UpperTorso" or name == "LowerTorso",
						key .. ": only the torsos change (" .. name .. ")"
					)
					local set = MeshFix.setOf(src)
					local shown = measured(set)
					check(
						angleOf(shown) < 0.1,
						string.format(
							"%s %s worn from %s, which Roblox stored as drawn (not turned)",
							key,
							name,
							tostring(set)
						)
					)
					check(src.Name == key .. "_" .. name, key .. " " .. name .. " is its own set's torso")
				end
				if key == "MaleMedium" then
					check(next(applied) == nil, "MaleMedium keeps Roblox's own torso")
				elseif g == 2 then
					check(applied.UpperTorso ~= nil, key .. ": the female chest is worn")
				end
			end
		end
		rb.Parent = nil
		check(kinds == 8 and worn >= 12, string.format("8 body sets worn, %d torsos applied", worn))
	end)

	test("Model fit: every creator kit and cape on the body (LookKit)", function()
		local s = boot()
		local LookKit = s:require("Shared.LookKit")
		local NpcRig = s:require("Shared.NpcRig")
		local RigMath = s:require("Shared.RigMath")
		local layout = RigMath.layout(Config.HeroRig, nil, 1)
		local rig = NpcRig.build(layout, "Body", {}, nil, nil, nil, nil)
		local colors = { p = Color3.new(1, 0, 0), s = Color3.new(0, 1, 0), a = Color3.new(0, 0, 1) }
		local libs = {
			head = "HeadArt",
			hands = "GloveArt",
			feet = "BootArt",
			back = "CoatArt",
			belt = "BeltArt",
			shoulders = "ShoulderArt",
			backpack = "BackArt",
			hat = "HatArt",
			hair = "HairArt",
			eyes = "EyeArt",
			ears = "EarArt",
			neck = "NeckArt",
			wrist = "WristArt",
			arms = "ArmArt",
		}
		local t = tally()
		local kits = 0
		local function placed(f: any, fit: any, label: string)
			local list = f:GetChildren()
			for i, row in fit.pieces do
				local p = list[i]
				local w = p and p:FindFirstChildOfClass("WeldConstraint")
				local part = w and w.Part0
				if part then
					local shift, k = LookKit.fitFrame(part)
					local want = part.CFrame * CFrame.new(shift + v3(row.offset) * k)
					compare(t, label, p, want, v3(row.size) * k)
				end
			end
		end
		for tab, cfgName in libs do
			for kit, fit in Config[cfgName] do
				if type(fit) == "table" and fit.pieces then
					local f = folder()
					local ok = LookKit._pieceMeshes(rig.model, f, tab, kit, colors, nil, nil)
					check(ok, tab .. " " .. kit .. " drawn from its meshes")
					if ok then
						kits += 1
						placed(f, fit, kit)
					end
				end
			end
		end
		for style, fit in Config.CapeArt do
			if type(fit) == "table" and fit.pieces then
				local f = folder()
				local ok = LookKit._capeMeshes(rig.model, f, "cape:" .. style, colors, nil)
				check(ok, "cape " .. style .. " drawn from its meshes")
				if ok then
					kits += 1
					placed(f, fit, "cape " .. style)
				end
			end
		end
		check(kits >= 100, string.format("%d kits and capes placed", kits))
		verdict(t, "creator kits and capes", 600)
	end)

	test("Model fit: the HQ, hideout, set piece and vehicle looks (HqMeshes, SetPieceMeshes)", function()
		local s = boot()
		local HqMeshes = s:require("Client.Fx.HqMeshes")
		local SetPieceKit = s:require("Shared.SetPieceKit")
		local SetPieceMeshes = serverModule("SetPieceMeshes")
		local at = CFrame.new(10, 2, -5) * CFrame.Angles(0, math.rad(30), 0)
		local function run(label: string, looks: any, place: (string, any) -> boolean, least: number)
			local t = tally()
			for look in looks do
				if type(looks[look]) == "table" then
					local f = folder()
					if place(look, f) then
						local want = {}
						for _, m in SetPieceKit.meshes(Config, { look = look, x = 0, y = 0, z = 0 }) do
							want[m.name] = m
						end
						for _, p in meshParts(f) do
							local m = want[p.Name]
							if m then
								compare(t, look, p, at * CFrame.new(v3(m.offset)), v3(m.size))
							end
						end
					end
				end
			end
			verdict(t, label, least)
		end
		run("HQ looks", Config.HqArt, function(look, f)
			return HqMeshes.place(f, look, at)
		end, 250)
		run("hideout modules", Config.HideoutArt, function(look, f)
			return HqMeshes.place(f, look, at)
		end, 15)
		run("set pieces", Config.SetPieceArt, function(look, f)
			return #SetPieceMeshes.add(f, { look = look, x = 0, y = 0, z = 0 }, at) > 0
		end, 140)
		run("vehicles", Config.VehicleArt, function(look, f)
			return #SetPieceMeshes.add(f, { look = look, x = 0, y = 0, z = 0 }, at) > 0
		end, 100)
	end)

	test("Model fit: street props, story, prologue and deep looks", function()
		local s = boot()
		local at = CFrame.new(-4, 1, 7) * CFrame.Angles(0, math.rad(-60), 0)
		-- the street props (CityProps.make, the pockets' dressing; CityBuilder places the same rows)
		local CityProps = s:require("Client.Controllers.CityProps")
		CityProps.init() -- finds Art.Street (the sim has no world seed, so no cells are built)
		local t = tally()
		for name in Config.City.kit.props do
			local fit = Config.StreetArt[name]
			local f = folder()
			if fit and CityProps.make(name, at, f) > 0 then
				for _, p in meshParts(f) do
					local row = fit[p.Name]
					if row then
						compare(t, name, p, at * CFrame.new(v3(row.offset)), v3(row.size))
					end
				end
			end
		end
		verdict(t, "street props", 40)
		-- the story's props (StoryProps.weld on an anchor, lifted to the look's middle)
		local StoryProps = s:require("Client.Fx.StoryProps")
		local StoryArtKit = s:require("Shared.StoryArtKit")
		t = tally()
		for look in Config.StoryArt do
			local ok, list = pcall(StoryArtKit.meshes, Config, look)
			if ok and type(list) == "table" and #list > 0 then
				local anchor = UiSim.newInstance("Part")
				anchor.CFrame = at
				local made = StoryProps.weld(look, anchor, 1.5, folder())
				for _, m in list do
					local p = made and made[m.name]
					if p then
						compare(
							t,
							look,
							p,
							at * CFrame.new(m.offset[1], m.offset[2] + 1.5, m.offset[3]),
							v3(m.size)
						)
					end
				end
			end
		end
		verdict(t, "story props", 15)
		-- the prologue's looks
		local PrologueMeshes = s:require("Client.Fx.PrologueMeshes")
		local PrologueArtKit = s:require("Shared.PrologueArtKit")
		t = tally()
		for look in Config.PrologueArt do
			local ok, list = pcall(PrologueArtKit.meshes, Config, look)
			if ok and type(list) == "table" and #list > 0 then
				local made = PrologueMeshes.add(folder(), look, at)
				local byName = {}
				for _, p in made do
					byName[p.Name] = p
				end
				for _, m in list do
					if byName[m.name] then
						compare(t, look, byName[m.name], at * CFrame.new(v3(m.offset)), v3(m.size))
					end
				end
			end
		end
		verdict(t, "prologue looks", 15)
		-- the deep's looks in a box (DeepMeshes.look; the kit fits the look to the box)
		local DeepMeshes = s:require("Client.Fx.DeepMeshes")
		local DeepArtKit = s:require("Shared.DeepArtKit")
		t = tally()
		for look in Config.DeepArt do
			local size = Vector3.new(6, 6, 6)
			local place = { look = look, cx = 0, cy = 0, cz = 0, sx = 6, sy = 6, sz = 6 }
			local ok, list = pcall(DeepArtKit.meshes, Config, place)
			if ok and type(list) == "table" and #list > 0 then
				local made = DeepMeshes.look(look, size, at, folder())
				for _, m in list do
					local p = made and made[m.name]
					if p then
						compare(t, look, p, at * CFrame.new(v3(m.offset)), v3(m.size))
					end
				end
			end
		end
		verdict(t, "deep looks", 5)
	end)
end
