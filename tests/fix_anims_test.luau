-- fix-anims (nate's playtest of gaps7, 2026-11-19: "there just still aren't animations for attacks or powers or
-- anything"). The root cause was not the clips' maths: Roblox's Avatar Joint Upgrade (StarterPlayer
-- .AvatarJointUpgrade, the default for new experiences; Rojo never wrote the property, so the place was on the
-- default) spawns player characters with AnimationConstraints, not Motor6Ds, and HeroAnimator, EmoteFx and
-- NpcGestures only looked for Motor6Ds, so every clip on a hero silently did nothing.
-- These run the REAL client from the built place (tests/uisim.luau): the whole client boot
-- (src/client/init.client.luau) with a hero character, then the Basic key through InputController and
-- CombatClient.fire to HeroAnimator, frames on RunService.PreSimulation, and the joints' Transform read back.
-- Both joint kinds are checked. ONLY="Fix anims" runs just these. Called from tests/run.luau.

return function(T: any)
	local test, check = T.test, T.check
	local placePath: string? = T.placePath
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox")
	local sleep = require("@lune/task").wait
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

	local PARTS = {
		LowerTorso = "Root",
		UpperTorso = "Waist",
		Head = "Neck",
		LeftUpperArm = "LeftShoulder",
		LeftLowerArm = "LeftElbow",
		LeftHand = "LeftWrist",
		RightUpperArm = "RightShoulder",
		RightLowerArm = "RightElbow",
		RightHand = "RightWrist",
		LeftUpperLeg = "LeftHip",
		LeftLowerLeg = "LeftKnee",
		LeftFoot = "LeftAnkle",
		RightUpperLeg = "RightHip",
		RightLowerLeg = "RightKnee",
		RightFoot = "RightAnkle",
	}
	local PARENT = {
		LowerTorso = "HumanoidRootPart",
		UpperTorso = "LowerTorso",
		Head = "UpperTorso",
		LeftUpperArm = "UpperTorso",
		LeftLowerArm = "LeftUpperArm",
		LeftHand = "LeftLowerArm",
		RightUpperArm = "UpperTorso",
		RightLowerArm = "RightUpperArm",
		RightHand = "RightLowerArm",
		LeftUpperLeg = "LowerTorso",
		LeftLowerLeg = "LeftUpperLeg",
		LeftFoot = "LeftLowerLeg",
		RightUpperLeg = "LowerTorso",
		RightLowerLeg = "RightUpperLeg",
		RightFoot = "RightLowerLeg",
	}

	-- an R15 character as Roblox spawns it: kind "Motor6D", or "AnimationConstraint" (the Avatar Joint
	-- Upgrade: joints between the two RigAttachments). oddNames: joints not named the R15 way.
	local function character(UiSim: any, kind: string, oddNames: boolean?): (any, { [string]: any })
		local new = UiSim.newInstance
		local char = new("Model")
		char.Name = "Tester"
		local parts = {}
		local root = new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = Vector3.new(0, 3, 10)
		root.CFrame = CFrame.new(0, 3, 10)
		root.AssemblyLinearVelocity = Vector3.zero
		root.Parent = char
		parts.HumanoidRootPart = root
		for name in PARTS do
			local p = new("MeshPart")
			p.Name = name
			p.Position = Vector3.new(0, 3, 10)
			p.Parent = char
			parts[name] = p
		end
		local joints = {}
		for name, jointName in PARTS do
			local p0, p1 = parts[PARENT[name]], parts[name]
			local j = new(kind)
			j.Name = if oddNames then name .. "Joint" else jointName
			j.Transform = CFrame.identity
			if kind == "Motor6D" then
				j.Part0, j.Part1 = p0, p1
				j.C0, j.C1 = CFrame.identity, CFrame.identity
			else
				local a0 = new("Attachment")
				a0.Name = jointName .. "RigAttachment"
				a0.Parent = p0
				local a1 = new("Attachment")
				a1.Name = jointName .. "RigAttachment"
				a1.Parent = p1
				j.Attachment0, j.Attachment1 = a0, a1
				j.IsKinematic = true
			end
			j.Parent = p1
			joints[jointName] = j
		end
		local hum = new("Humanoid")
		hum.Name = "Humanoid"
		hum.Health = 100
		hum.Parent = char
		local animator = new("Animator")
		animator.Parent = hum
		char.PrimaryPart = root
		return char, joints
	end

	-- boot the whole client (init.client.luau) in a sim with that character; returns the sim, or nil and why
	local function boot(kind: string, oddNames: boolean?): (any, { [string]: any }?, string?)
		local UiSim = require("./uisim")
		local place = roblox.deserializePlace(fs.readFile(placePath :: string))
		local trees = UiSim.load(place)
		local sim =
			UiSim.new(trees, { name = "PC", w = 1920, h = 1080, top = 36, left = 0, right = 0, bottom = 0 })
		-- every PreSimulation connection, tagged with who made it (the stack at Connect)
		local pre = sim.service("RunService").PreSimulation
		local conns = {}
		sim.preConns = conns
		local connect = pre.Connect
		pre.Connect = function(self, f)
			table.insert(conns, { f = f, by = debug.traceback() })
			return connect(self, function() end)
		end
		local char, joints = character(UiSim, kind, oddNames)
		char.Parent = sim.workspace
		sim.player.Character = char
		local client = trees.StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
		local env = sim:_env(client)
		env.os = os
		local fn = luau.load(client._props.Source, { debugName = "Client", environment = env })
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co)
		if not ok then
			return nil, nil, "the client boot errored: " .. tostring(err)
		end
		if coroutine.status(co) ~= "dead" then
			return nil, nil, "the client boot yielded and never finished"
		end
		return sim, joints, nil
	end

	-- frames: every PreSimulation handler runs as the engine would, with real time passing (HeroAnimator reads
	-- os.clock). HeroAnimator's must not error; the others' errors are the sim's stand-ins (no physics, no
	-- terrain) and are only counted.
	local function frames(sim: any, n: number)
		local mine = 0
		for _, c in sim.preConns do
			if string.find(c.by, "HeroAnimator", 1, true) then
				mine += 1
			end
		end
		check(mine >= 1, "HeroAnimator connected to RunService.PreSimulation")
		for _ = 1, n do
			sleep(1 / 60)
			for _, c in sim.preConns do
				if string.find(c.by, "HeroAnimator", 1, true) then
					c.f(1 / 60)
				else
					pcall(c.f, 1 / 60)
				end
			end
		end
	end

	-- how far the joints are from rest (degrees of the largest turn among them)
	local function moved(joints: { [string]: any }, names: { string }): number
		local most = 0
		for _, n in names do
			local cf = joints[n].Transform
			local _, angle = cf:ToAxisAngle()
			most = math.max(most, math.deg(math.abs(angle)), cf.Position.Magnitude * 10)
		end
		return most
	end
	local UPPER = { "RightShoulder", "RightElbow", "LeftShoulder", "LeftElbow", "Waist", "Root" }

	test("Fix anims: the place pins AvatarJointUpgrade to Disabled (heroes keep Motor6Ds)", function()
		local serde = require("@lune/serde")
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local props = project.tree.StarterPlayer["$properties"]
		check(
			props.AvatarJointUpgrade_Serialized == "Disabled",
			"StarterPlayer.AvatarJointUpgrade_Serialized is Disabled"
		)
	end)

	test("Fix anims: every joint reader takes Motor6Ds and AnimationConstraints", function()
		for _, path in
			{
				"src/client/Controllers/HeroAnimator.luau",
				"src/client/Fx/EmoteFx.luau",
				"src/client/Controllers/NpcGestures.luau",
			}
		do
			local s = fs.readFile(path)
			check(string.find(s, "RigJoints.of", 1, true) ~= nil, path .. " finds joints through RigJoints")
			check(
				string.find(s, 'IsA("Motor6D")', 1, true) == nil,
				path .. " has no Motor6D-only search left"
			)
		end
	end)

	if not placePath or not fs.isFile(placePath) then
		test("Fix anims: the real client path (needs the built place)", function()
			check(false, "run with build/Capeline.rbxl")
		end)
		return
	end

	for _, case in
		{
			{ kind = "AnimationConstraint", label = "Avatar Joint Upgrade joints" },
			{ kind = "Motor6D", label = "Motor6D joints" },
			{ kind = "AnimationConstraint", odd = true, label = "constraints with other names" },
		}
	do
		test("Fix anims: the Basic key animates the hero's arms on " .. case.label, function()
			local sim, joints, why = boot(case.kind, case.odd)
			check(sim ~= nil, why or "booted")
			if not sim then
				return
			end
			check(#sim.errors == 0, "no errors during the boot: " .. table.concat(sim.errors, " | "))
			local j = joints :: { [string]: any }
			frames(sim, 3)
			local idle = moved(j, UPPER)
			-- the real key path: InputController.Pressed("Basic") -> CombatClient.fire -> HeroAnimator.cast
			local Input = sim:require("Client.Controllers.InputController")
			local Animator = sim:require("Client.Controllers.HeroAnimator")
			local ok, err = pcall(function()
				Input.Pressed:Fire("Basic")
			end)
			check(ok, "the Basic key runs: " .. tostring(err))
			local clip = Animator.actionOf(sim.player)
			check(clip ~= nil, "a cast clip started on the hero")
			frames(sim, 8)
			local cast = moved(j, UPPER)
			check(
				cast > idle + 10,
				string.format("the arms and body turn under the cast (%.1f deg, idle %.1f)", cast, idle)
			)
			check(#sim.errors == 0, "no errors in the frames: " .. table.concat(sim.errors, " | "))
		end)
	end

	test("Fix anims: a power cast and an emote pose the hero on Avatar Joint Upgrade joints", function()
		local sim, joints, why = boot("AnimationConstraint")
		check(sim ~= nil, why or "booted")
		if not sim then
			return
		end
		local j = joints :: { [string]: any }
		local Config = sim:require("Config")
		local Animator = sim:require("Client.Controllers.HeroAnimator")
		-- a skill from the starter power set, through CombatClient.fire as the skill key's release does
		local Combat = sim:require("Client.Controllers.CombatClient")
		local State = sim:require("Client.State")
		local kit = State.kit()
		local id = kit.skills[1]
		check(id ~= nil and Config.Abilities.list[id] ~= nil, "the starter kit has a skill")
		local fired = Combat.fire(id)
		check(fired == true, "the skill casts (" .. tostring(id) .. ")")
		check(Animator.actionOf(sim.player) ~= nil, "its clip starts")
		frames(sim, 8)
		check(moved(j, UPPER) > 10, "the power's pose shows on the joints")
		-- an emote (the server's Emote attribute) on joints whose C0 is read-only
		frames(sim, 80) -- the cast ends
		local emoteId = nil
		for eid, row in Config.Shop.emotes do
			if not row.landing then
				emoteId = eid
				break
			end
		end
		check(emoteId ~= nil, "an emote exists")
		local before = {}
		for n, jt in j do
			before[n] = jt.Transform
		end
		sim.player:SetAttribute("Emote", (emoteId :: number) * 1000 + 1)
		frames(sim, 20)
		local changed = 0
		for n, jt in j do
			if jt.Transform ~= before[n] then
				changed += 1
			end
		end
		check(changed >= 2, "the emote's pose turns the joints (" .. changed .. " moved)")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)
end
