-- fix-respawn (nate's playtest 2026-11-19 20:42Z and 21:01Z): "i died and respawn ... my size reset", "Clothes dont
-- fit on certain body sizes", "unresponsive buttons when trying to talk to npcs or start side quests", "Next button
-- in character creator is still super unresponsive ... i just have to keep spamming until it works".
-- The creator checks boot the WHOLE client from the built place (tests/uisim.luau, as fix_anims_test does), open
-- the creator through its real remote and press NEXT through the real Kit.button path. The body checks run the
-- place's own LookKit on Roblox's blocky body (tests/weaponsim.luau) with joints. ONLY="Fix respawn".

return function(T: any)
	local test, check = T.test, T.check
	local placePath: string? = T.placePath
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox")
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(path: string, text: string): boolean
		return string.find(src(path), text, 1, true) ~= nil
	end

	-------------------------------------------------------------------- the respawn path (source: Studio proves it)
	test("Fix respawn: the look is built again once a respawned body is in Workspace, and guarded", function()
		local gs = "src/server/Services/GearService.luau"
		check(
			has(gs, "char:IsDescendantOf(Workspace)"),
			"GearService waits for the character to be in Workspace"
		)
		check(has(gs, "LookService.onShapeLost"), "GearService rebuilds the look when the shape is lost")
		check(
			has("src/server/Services/LookService.luau", "LookService.guardShape(player, char)"),
			"apply guards the body"
		)
		check(
			has("src/server/Services/HeroBody.luau", "hum.AutomaticScalingEnabled = false"),
			"the hero body's Humanoid does not rescale its parts"
		)
		check(
			has("src/shared/LookKit.luau", 'p:SetAttribute("ShapedSize", p.Size)'),
			"shapeBody records its sizes"
		)
	end)

	if not placePath or not fs.isFile(placePath) then
		test("Fix respawn: the place checks (needs the built place)", function()
			check(false, "run with build/Capeline.rbxl")
		end)
		return
	end
	local place = roblox.deserializePlace(fs.readFile(placePath :: string))

	-------------------------------------------------------------------- bodies on Roblox's body, by the game's code
	local WeaponSim = require("./weaponsim")
	local JOINT = {
		UpperTorso = { "LowerTorso", "Waist" },
		Head = { "UpperTorso", "Neck" },
		LeftUpperArm = { "UpperTorso", "LeftShoulder" },
		LeftLowerArm = { "LeftUpperArm", "LeftElbow" },
		LeftHand = { "LeftLowerArm", "LeftWrist" },
		RightUpperArm = { "UpperTorso", "RightShoulder" },
		RightLowerArm = { "RightUpperArm", "RightElbow" },
		RightHand = { "RightLowerArm", "RightWrist" },
		LeftUpperLeg = { "LowerTorso", "LeftHip" },
		LeftLowerLeg = { "LeftUpperLeg", "LeftKnee" },
		LeftFoot = { "LeftLowerLeg", "LeftAnkle" },
		RightUpperLeg = { "LowerTorso", "RightHip" },
		RightLowerLeg = { "RightUpperLeg", "RightKnee" },
		RightFoot = { "RightLowerLeg", "RightAnkle" },
	}
	local function body(sim: any): any
		local char = sim:body()
		for child, j in JOINT do
			local p0, p1 = char:FindFirstChild(j[1]), char:FindFirstChild(child)
			local m = roblox.Instance.new("Motor6D")
			m.Name = j[2]
			m.Part0, m.Part1 = p0, p1
			m.C0 = p0:FindFirstChild(j[2] .. "RigAttachment").CFrame
			m.C1 = p1:FindFirstChild(j[2] .. "RigAttachment").CFrame
			m.Parent = p1
		end
		return char
	end
	local function sizes(char: any): { [string]: any }
		local out = {}
		for _, p in char:GetChildren() do
			if p:IsA("BasePart") then
				out[p.Name] = p.Size
			end
		end
		return out
	end

	test(
		"Fix respawn: a body reset by Roblox is seen, and building the look again shapes it again",
		function()
			local sim = WeaponSim.new(place)
			local Config = sim:module("Config")
			local LookKit = sim:module("Shared.LookKit")
			local CreatorRules = sim:module("Shared.CreatorRules")
			local look = CreatorRules.defaultLook(Config)
			look.gender, look.build, look.height = 2, 4, 5 -- a very tall female Titan
			local char = body(sim)
			LookKit.build(char, look)
			local shaped = sizes(char)
			check(not LookKit.shapeLost(char), "freshly shaped: nothing lost")
			check(shaped.UpperTorso.X > 3, "the Titan's torso is wide: " .. tostring(shaped.UpperTorso))
			-- what Roblox's spawn scaling did on a respawn: every part back to its first size
			for _, p in char:GetChildren() do
				local b = p:GetAttribute("BaseSize")
				if typeof(b) == "Vector3" then
					p.Size = b
				end
			end
			check(LookKit.shapeLost(char), "a body back at its first sizes is seen as reset")
			LookKit.strip(char)
			LookKit.build(char, look)
			check(not LookKit.shapeLost(char), "shaped again")
			local again = sizes(char)
			for name, s in shaped do
				check((again[name] - s).Magnitude < 1e-4, name .. " shaped to the same size again")
			end
			-- the joints follow the shape: the shoulder sits out at the shaped torso's side
			-- (Lune keeps an Attachment's CFrame apart from its Position, so the attachment is read, as Roblox's
			-- Motor6D.C0 = Attachment.CFrame in shapeBody would)
			local a = char:FindFirstChild("UpperTorso"):FindFirstChild("LeftShoulderRigAttachment")
			check(
				math.abs(a.Position.X + shaped.UpperTorso.X / 2) < 0.01,
				string.format(
					"the shoulder joint moved with the torso (x %.3f, torso %.3f)",
					a.Position.X,
					shaped.UpperTorso.X
				)
			)
		end
	)

	test("Fix respawn: an NpcRig laid out for its body is not shaped a second time by its look", function()
		local sim = WeaponSim.new(place)
		local Config = sim:module("Config")
		local LookKit = sim:module("Shared.LookKit")
		local NpcRig = sim:module("Shared.NpcRig")
		local RigMath = sim:module("Shared.RigMath")
		local BodyShape = sim:module("Shared.BodyShape")
		local CreatorRules = sim:module("Shared.CreatorRules")
		local look = CreatorRules.defaultLook(Config)
		look.gender, look.build, look.height = 1, 4, 5
		local layout = RigMath.layout(Config.HeroRig, BodyShape.factors(Config, look), 1)
		local rig = NpcRig.build(layout, "Giver", {}, nil, nil, BodyShape.setKey(Config, look))
		local before = rig.parts.UpperTorso.Size
		LookKit.build(rig.model, look)
		check(
			(rig.parts.UpperTorso.Size - before).Magnitude < 1e-4,
			"the giver's torso keeps its laid-out size: "
				.. tostring(before)
				.. " -> "
				.. tostring(rig.parts.UpperTorso.Size)
		)
	end)

	test("Fix respawn: on all 40 bodies every piece and the weapon sit on their shaped part", function()
		local sim = WeaponSim.new(place)
		local Config = sim:module("Config")
		local LookKit = sim:module("Shared.LookKit")
		local CreatorRules = sim:module("Shared.CreatorRules")
		local B = Config.Creator.body
		local function idx(tab: string, kit: string): number
			for i = 1, 120 do
				local p = CreatorRules.piece(Config, tab, i)
				if p and p.kit == kit then
					return i
				end
			end
			return 0
		end
		local worst, worstAt, n = 0, "", 0
		for g = 1, #B.genders do
			for b = 1, #B.builds do
				for h = 1, #B.heights do
					local look = CreatorRules.defaultLook(Config)
					look.gender, look.build, look.height = g, b, h
					look.pieces.head = idx("head", "visor")
					look.pieces.hands = idx("hands", "gauntlet")
					look.pieces.feet = idx("feet", "boot")
					look.pieces.belt = idx("belt", "utility")
					look.pieces.shoulders = idx("shoulders", "pads")
					local char = body(sim)
					local weapon =
						{ id = 1, style = 1, finish = 1, main = 1, trim = 2, glow = 3, glowLevel = 1 }
					local ok, err = pcall(LookKit.build, char, look, weapon)
					check(ok, "LookKit.build " .. tostring(err))
					local folder = char:FindFirstChild("HeroLook")
					for _, d in if folder then folder:GetDescendants() else {} do
						if d:IsA("BasePart") then
							local w = d:FindFirstChildOfClass("WeldConstraint")
							local part = w and w.Part0
							if part and part ~= d then
								n += 1
								-- how far the piece's box centre is outside its part's (shaped) box, in studs
								local rel = part.CFrame:PointToObjectSpace(d.CFrame.Position)
								local half = part.Size / 2
								local out = Vector3.new(
									math.max(0, math.abs(rel.X) - half.X),
									math.max(0, math.abs(rel.Y) - half.Y),
									math.max(0, math.abs(rel.Z) - half.Z)
								).Magnitude
								-- a cape, a held weapon and a back piece hang off their part by design: measured
								-- against the box grown by the piece's own half size
								local slack = math.max(d.Size.X, d.Size.Y, d.Size.Z) / 2 + 0.25
								if out - slack > worst then
									worst = out - slack
									worstAt =
										string.format("%s on %s (g%d b%d h%d)", d.Name, part.Name, g, b, h)
								end
							end
						end
					end
					char:Destroy()
				end
			end
		end
		check(n > 40 * 10, "pieces were placed: " .. n)
		check(
			worst <= 0.05,
			string.format("every piece on its part (worst %.2f studs off: %s)", worst, worstAt)
		)
	end)

	test(
		"Fix respawn: the body set torsos carry Roblox's own torso UV layout (classic clothes land right)",
		function()
			-- the uploaded Art.BodyTorsos meshes are checked against the FBX by art/upload/meshcheck.py; here the FBX's
			-- source: bodies.py --torsos runs robloxuv.transfer on every torso
			check(
				has("art/blender/bodies.py", "robloxuv.transfer(t,"),
				"bodies.py --torsos transfers Roblox's torso UVs"
			)
			check(fs.isFile("art/blender/robloxuv.py"), "art/blender/robloxuv.py exists")
		end
	)

	-------------------------------------------------------------------- the creator's NEXT, through the real client
	local UiSim = require("./uisim")
	local RR = require("../src/config/RobloxRig")
	local function boot(dev: any): any
		local trees = UiSim.load(place)
		local sim = UiSim.new(trees, dev)
		local new = UiSim.newInstance
		local char = new("Model")
		char.Name = "Tester"
		local root = new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(0, 3, 10)
		root.Parent = char
		for name, p in RR.parts do
			local part = new("MeshPart")
			part.Name = name
			part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
			part.CFrame = CFrame.new(p.centre[1], p.centre[2], p.centre[3])
			part.Parent = char
		end
		local hum = new("Humanoid")
		hum.Name = "Humanoid"
		hum.Parent = char
		char.PrimaryPart = root
		char.Parent = sim.workspace
		sim.player.Character = char
		local client = trees.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
		local env = sim:_env(client)
		env.os = os
		local co =
			coroutine.create(luau.load(client._props.Source, { debugName = "Client", environment = env }))
		local ok, err = coroutine.resume(co)
		check(ok, "the client boots: " .. tostring(err))
		return sim
	end
	local function fire(sim: any, name: string, ...: any)
		local args = table.pack(...)
		for _, d in sim.place.ReplicatedStorage:GetDescendants() do
			if d.Name == name and d._signals then
				sim:run(name, function()
					d._signals.OnClientEvent:Fire(table.unpack(args, 1, args.n))
				end)
				return
			end
		end
		error("no remote " .. name)
	end
	local function frames(sim: any, n: number)
		for _ = 1, n do
			sim:run("frame", function()
				local RS = sim.service("RunService")
				RS.RenderStepped:Fire(1 / 30)
				RS.Heartbeat:Fire(1 / 30)
			end)
			sim:advance(1 / 30)
		end
	end

	local DEVICES = {
		{ name = "PC", w = 1920, h = 1080, top = 36, left = 0, right = 0, bottom = 0 },
		{ name = "Studio", w = 1280, h = 650, top = 36, left = 0, right = 0, bottom = 0 },
		{ name = "Phone", w = 844, h = 390, top = 36, left = 44, right = 44, bottom = 21, touch = true },
	}
	for _, dev in DEVICES do
		test("Fix respawn: creator NEXT answers every press at once (" .. dev.name .. ")", function()
			local sim = boot(dev)
			frames(sim, 5)
			fire(sim, "CreatorOpen", { mode = "create" })
			frames(sim, 10)
			local gui = sim.playerGui:FindFirstChild("Creator")
			local nextB
			for _, d in gui:GetDescendants() do
				if d:IsA("TextButton") and d.Text == "NEXT" then
					nextB = d
				end
			end
			check(nextB ~= nil, "NEXT is on screen")
			if not nextB then
				return
			end
			-- nothing draws over NEXT that takes the tap
			local boxes = sim:boxes()
			for _, b in boxes do
				if b.inst == nextB then
					local hit = sim:hitAt(b.x + b.w / 2, b.y + b.h / 2, boxes)
					check(
						hit ~= nil and hit.inst == nextB,
						"a tap on NEXT reaches NEXT, not " .. (hit and hit.inst:GetFullName() or "nothing")
					)
				end
			end
			local Kit = sim:require("Client.Ui.Kit")
			local LookKit = sim:require("Shared.LookKit")
			local builds = 0
			local real = LookKit.build
			LookKit.build = function(...)
				builds += 1
				return real(...)
			end
			local stepRow
			for _, d in gui:GetDescendants() do
				if d:IsA("TextButton") and d.Name == "body" then
					stepRow = d.Parent
				end
			end
			local function lit(): string?
				for _, b in stepRow:GetChildren() do
					if b:IsA("TextButton") and b.BackgroundColor3 == Kit.color.gold then
						return b.Name
					end
				end
				return nil
			end
			local before = Kit.TAPS.fires
			local order = {}
			for _, b in stepRow:GetChildren() do
				if b:IsA("TextButton") then
					order[b.LayoutOrder] = b.Name
				end
			end
			local picks = 0
			for i = 1, #order - 1 do
				if order[i] == "origin" or order[i] == "powers" then
					-- (first-30, 2026-11-20) NEXT stays on these until something is picked: pick the first row
					for _, c in gui:GetDescendants() do
						if
							c:IsA("TextButton")
							and c.Text == ""
							and c.Visible
							and c.BackgroundColor3 == Kit.color.paper
							and c:FindFirstChildWhichIsA("TextLabel")
						then
							sim:tap(c)
							picks += 1
							break
						end
					end
					sim:advance(0.5)
					builds = 0 -- the pick changed the look; the presses alone must not rebuild it
				end
				local d0 = #gui:GetDescendants()
				sim:tap(nextB)
				-- the press shows at once: the next step lit before any list is drawn
				check(
					lit() == order[i + 1],
					string.format("press %d lights %s at once (lit %s)", i, order[i + 1], tostring(lit()))
				)
				check(#gui:GetDescendants() <= d0 + 2, "the heavy redraw waits for the next frame")
				sim:advance(0.1)
			end
			check(
				Kit.TAPS.fires - before == #order - 1 + picks,
				"every press fired once: " .. (Kit.TAPS.fires - before)
			)
			check(nextB.Text == "PLAY", "the last step reads PLAY")
			check(builds == 0, "stepping with the look unchanged never rebuilt the hero (" .. builds .. ")")
			-- a sweep of the pointer over every hover row and tile builds nothing until it rests
			builds = 0
			local n = 0
			for _, d in gui:GetDescendants() do
				if d:IsA("TextButton") and d._signals and d._signals.MouseEnter then
					n += 1
					sim:run("enter", function()
						d._signals.MouseEnter:Fire()
					end)
					sim:advance(0.02)
					if d._signals.MouseLeave then
						sim:run("leave", function()
							d._signals.MouseLeave:Fire()
						end)
					end
				end
			end
			sim:advance(0.5)
			check(
				builds <= 1,
				string.format("a sweep over %d hover buttons built the hero %d times", n, builds)
			)
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end)
	end

	-------------------------------------------------------------------- side quest givers
	test("Fix respawn: a giver's Talk answers every press (instant prompt, reasons, cut-in line)", function()
		local sq = "src/server/Services/SideQuestService.luau"
		check(has(sq, "prompt.HoldDuration = 0 "), "the Talk prompt fires on a tap (no 0.2 s hold)")
		check(has(sq, 'refuse(player, "far", id)'), "too far says so")
		check(has(sq, 'refuse(player, "loading", giverId)'), "still loading says so")
		check(has(sq, 'prompt:SetAttribute("Giver", id)'), "the prompt names its giver for the device")
		local hud = "src/client/Ui/StoryHud.luau"
		check(has(hud, "PromptTriggered"), "the device answers the press at once")
		check(has(hud, "cut = mine"), "the answer to your own press cuts in front of the radio")
		local toasts = src("src/client/Ui/Toasts.luau")
		check(
			string.find(toasts, "sqStart = true, -- fix-respawn", 1, true) ~= nil,
			"NEW SIDE QUEST is an answer to a tap"
		)
		-- every reason the server sends has words
		for _, why in
			{
				"level",
				"story",
				"after",
				"npc",
				"done",
				"side",
				"origin",
				"loading",
				"far",
				"gone",
				"notActive",
			}
		do
			check(string.find(toasts, "\t" .. why .. ' = "', 1, true) ~= nil, "a line for " .. why)
		end
	end)

	test("Fix respawn: SideQuestPlan.giverWhy names what a giver's next chain waits for", function()
		local Config = T.Config
		local SideQuestPlan = require("../src/shared/SideQuestPlan")
		local ProfileSchema = require("../src/shared/ProfileSchema")
		local c = ProfileSchema.newCharacter("hero", nil)
		local found = false
		for id in Config.SideQuests.givers do
			local why, n = SideQuestPlan.giverWhy(Config, c, id, 1, "hero", false)
			local chain = SideQuestPlan.talkPick(Config, c, id, 1, "hero", false)
			if not chain and why ~= nil then
				found = true
				if why == "level" then
					check(type(n) == "number" and n > 1, id .. ": a level gate names its level")
				end
			end
		end
		check(found, "a new hero meets at least one giver whose chain waits for something, and hears what")
	end)
end
