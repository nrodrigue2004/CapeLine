-- StoryFx: the story's props and companions, drawn on this device only.
-- (The Ceremony prologue's scene is PrologueFx's, lore step 3.)
-- * The Echo Drone: a small friendly comic drone that follows every villain who reprogrammed their evil twin's core
--   (Player attribute NullEcho; older saves that spared the old core keep it), hovering at the shoulder: it bobs,
--   turns its one big eye to the nearest other hero (else the way its owner looks) and blinks (Shared.StoryArtKit's
--   seeded motion). Its look is art/blender/story.py's EchoDrone (Art.Story) for the nearest drones the preset
--   allows; the rest, and every drone before the import, are today's purple ball with its eye. Cosmetic only.
-- * A mission's props (gap-story, 2026-11-19): the break targets and the runaway train in their Blender looks over
--   their unchanged parts (Fx.StoryProps); at a "people" hold ring (Get the people off the bridge) a person on
--   Roblox's own body (a catalog face and hair, NpcRig.person) sits pinned under a fallen girder that lifts as the
--   ring is held and tips off when it is done, and the person gets up, cheers and runs off; at a reach step's point
--   a gold goal beacon. All on this device only: no collisions, queries or touches, nothing the server counts.
-- * The crackling arena: Live's pillars crackle for heroes who destroyed their twin's core. Cosmetic only.
-- * A mission's camera beats (lore step 5): the camera leaves the hero for the beat's focus (a fake, the mast,
--   the safehouse door) and pushes in slowly; the hero holds still on this device; Lodestar stands where the
--   beat says; each radio line starts with a blip (the subtitles are StoryHud's). No flashes or shakes, so
--   Reduce flashing has nothing to remove. The shot plays through the one cutscene player (CinemaClient,
--   lore step 7: letterbox, SKIP once every hero on the stage has seen it).
-- PLACEHOLDER ART: until Art.Story is imported the props are today's parts, the drone the ball, and the trap and the
-- beacon simple parts (a girder bar and two rubble blocks; a glowing column).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local NpcRig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NpcRig"))
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Net"))
local CinemaPlan =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CinemaPlan"))

local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local CombatFx = require(script.Parent.CombatFx)
local PrologueFx = require(script.Parent.PrologueFx)
local StoryProps = require(script.Parent.StoryProps)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local StoryArtKit =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("StoryArtKit"))
local RigMath = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RigMath"))

local StoryFx = {}

local folder: Folder
type Buddy = {
	anchor: BasePart, -- the drone's middle (the ball itself, or an unseen part the meshes are welded to)
	eye: BasePart?,
	eyeSize: Vector3,
	mesh: boolean,
	pos: Vector3,
	look: Vector3,
	seed: number,
	lastBlink: number,
}
local buddies: { [Player]: Buddy } = {}
local sparkAt = 0
local slowAt = 0 -- the next 2 Hz pass (story props, which drones get the mesh look, who they look at)
local meshDrones: { [Player]: boolean } = {}
local lookAt: { [Player]: Vector3? } = {}
local D = StoryArtKit.DRONE

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- One drone: the mesh look (Art.Story's EchoDrone, welded to an unseen anchor at its middle) or today's ball and eye
local function makeBuddy(p: Player, mesh: boolean, at: CFrame): Buddy
	local seed = p.UserId % 100003
	if mesh then
		local anchor = part(folder, Vector3.new(0.4, 0.4, 0.4), at, Color3.new(1, 1, 1))
		anchor.Name = "NullEcho"
		anchor.Transparency = 1
		local meshes = StoryProps.weld("EchoDrone", anchor, 0, anchor)
		local eye = meshes and meshes.EchoDroneEye
		if meshes and eye then
			return {
				anchor = anchor,
				eye = eye,
				eyeSize = eye.Size,
				mesh = true,
				pos = at.Position,
				look = at.LookVector,
				seed = seed,
				lastBlink = 1,
			}
		end
		anchor:Destroy()
	end
	-- PLACEHOLDER ART: the ball with an eye (before Art.Story, or past the preset's mesh drones)
	local d = part(
		folder,
		Vector3.new(1.4, 1.4, 1.4),
		at,
		Color3.fromRGB(150, 60, 200),
		Enum.Material.Metal,
		Enum.PartType.Ball
	)
	d.Name = "NullEcho"
	local eye = part(
		d,
		Vector3.new(0.5, 0.5, 0.3),
		at * CFrame.new(0, 0, -0.62),
		Color3.fromRGB(120, 230, 255),
		Enum.Material.Neon
	)
	eye.Anchored = false
	local weld = Instance.new("Weld")
	weld.Part0 = d
	weld.Part1 = eye
	weld.C0 = CFrame.new(0, 0, -0.62)
	weld.Parent = eye
	return {
		anchor = d,
		eye = eye,
		eyeSize = eye.Size,
		mesh = false,
		pos = at.Position,
		look = at.LookVector,
		seed = seed,
		lastBlink = 1,
	}
end

-- (2 Hz) which drones wear the mesh look (the nearest the preset allows, once imported) and whom each looks at
local function buddySlow(cam: Vector3)
	local budget = QualityController.preset.story
	local ready = StoryProps.ready("EchoDrone")
	local list = {}
	for p, b in buddies do
		table.insert(list, { p = p, d = (b.pos - cam).Magnitude })
	end
	table.sort(list, function(x, y)
		return x.d < y.d
	end)
	table.clear(meshDrones)
	for i, row in list do
		meshDrones[row.p] = ready and budget ~= nil and i <= budget.drones
	end
	for p, b in buddies do
		local best, bestD = nil, D.lookNear
		for _, o in Players:GetPlayers() do
			local c = o ~= p and o.Character
			local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local dd = (r.Position - b.pos).Magnitude
				if dd < bestD then
					best, bestD = r.Position + Vector3.new(0, 1.5, 0), dd
				end
			end
		end
		lookAt[p] = best
	end
end

local function buddyStep(now: number, dt: number)
	for _, p in Players:GetPlayers() do
		local want = p:GetAttribute("NullEcho") == true
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local b = buddies[p]
		if b and want and meshDrones[p] ~= nil and meshDrones[p] ~= b.mesh then
			b.anchor:Destroy() -- the look changes (the budget or the import): rebuilt below where it was
			local keep = b
			b = makeBuddy(p, meshDrones[p] == true, CFrame.lookAt(keep.pos, keep.pos + keep.look))
			buddies[p] = b
		end
		if want and root then
			if not b then
				b = makeBuddy(p, meshDrones[p] == true, root.CFrame * CFrame.new(D.at[1], D.at[2], D.at[3]))
				buddies[p] = b
			end
			local bb = b :: Buddy
			local goal = (root.CFrame * CFrame.new(D.at[1], D.at[2] + StoryArtKit.bob(now, bb.seed), D.at[3])).Position
			bb.pos = bb.pos:Lerp(goal, 1 - math.exp(-D.follow * dt))
			local target = lookAt[p]
			local want3 = if target then target - bb.pos else root.CFrame.LookVector
			if want3.Magnitude > 0.01 then
				bb.look = bb.look:Lerp(want3.Unit, 1 - math.exp(-D.turn * dt))
			end
			if bb.look.Magnitude > 0.01 then
				bb.anchor.CFrame = CFrame.lookAt(bb.pos, bb.pos + bb.look)
			end
			local k = StoryArtKit.blink(now, bb.seed)
			local eye = bb.eye
			if eye and k ~= bb.lastBlink then
				bb.lastBlink = k
				eye.Size = Vector3.new(bb.eyeSize.X, bb.eyeSize.Y * k, bb.eyeSize.Z)
			end
		elseif b then
			b.anchor:Destroy()
			buddies[p] = nil
		end
	end
end

---------------------------------------------------------------------------
-- The trapped people at a "people" hold ring, and a reach step's goal beacon (gap-story)
---------------------------------------------------------------------------

local GIRDER = Color3.fromRGB(204, 84, 52)
local RUBBLE = Color3.fromRGB(170, 166, 158)
local personLayout = RigMath.layout(Config.HeroRig, nil, 1)
local SHIRTS = Config.Destruction.citizens.colors
local HAIR = Config.Destruction.citizens.hair

type Trap = {
	foot: CFrame,
	model: Model,
	girder: { [BasePart]: CFrame }, -- the girder's parts and their place from the foot, before the lift
	person: any,
	freedAt: number?,
	gone: boolean,
}
local traps: { Trap } = {}
local trapKey: any = nil
local beacon: { model: Model, rings: BasePart?, ringBase: CFrame?, foot: CFrame }? = nil
local beaconKey: any = nil

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- The ground under a point in a pocket (the pocket's own boxes), else the point less the ring's half stud
local function ground(p: { number }): Vector3
	local at = Vector3.new(p[1], p[2], p[3])
	local pockets = Workspace:FindFirstChild("Pockets")
	if pockets then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { pockets }
		local hit = Workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
		if hit then
			return hit.Position
		end
	end
	return at - Vector3.new(0, 0.5, 0)
end

local function quietAll(m: Instance)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

-- The person sitting, legs out and arms up, waving (wave: radians of the arms' swing)
local function sit(rig: any, wave: number)
	NpcRig.turn(rig, "LeftHip", CFrame.Angles(math.rad(88), 0, math.rad(-4)))
	NpcRig.turn(rig, "RightHip", CFrame.Angles(math.rad(88), 0, math.rad(4)))
	NpcRig.turn(rig, "LeftShoulder", CFrame.Angles(math.rad(150) + wave, 0, math.rad(-14)))
	NpcRig.turn(rig, "RightShoulder", CFrame.Angles(math.rad(150) - wave, 0, math.rad(14)))
end

local function buildTrap(i: number, p: { number }, num: number): Trap
	local g = ground(p)
	local foot = CFrame.new(g) * CFrame.Angles(0, i * 2.1 + num, 0)
	local m = Instance.new("Model")
	m.Name = "StoryTrap" .. i
	local mid = StoryArtKit.middle(Config, "StoryTrap")
	local anchor = part(m, Vector3.new(0.4, 0.4, 0.4), foot, Color3.new(1, 1, 1))
	anchor.Name = "Root"
	anchor.Transparency = 1
	local girder: { [BasePart]: CFrame } = {}
	local meshes = StoryProps.weld("StoryTrap", anchor, mid, m)
	if meshes and meshes.StoryTrapGirder then
		local gp = meshes.StoryTrapGirder
		gp:FindFirstChildOfClass("Weld"):Destroy()
		gp.Anchored = true
		girder[gp] = foot:ToObjectSpace(gp.CFrame)
	else
		if meshes then
			for _, mp in meshes do
				mp:Destroy()
			end
		end
		-- PLACEHOLDER ART: a girder bar on two rubble blocks until Art.Story is imported
		local lo, hi = StoryArtKit.GIRDER_LOW, StoryArtKit.GIRDER_HIGH
		local a = Vector3.new(lo[1], lo[2], lo[3])
		local b = Vector3.new(hi[1], hi[2], hi[3])
		local bar = part(
			m,
			Vector3.new((b - a).Magnitude + 0.6, 0.9, 0.9),
			foot * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0),
			GIRDER,
			Enum.Material.Metal
		)
		girder[bar] = foot:ToObjectSpace(bar.CFrame)
		part(
			m,
			Vector3.new(2.2, 4.2, 2.4),
			foot * CFrame.new(3.6, 2.1, 0) * CFrame.Angles(0, 0.4, 0.1),
			RUBBLE,
			Enum.Material.Concrete
		)
		part(
			m,
			Vector3.new(1.6, 1, 1.4),
			foot * CFrame.new(-2.4, 0.5, 1.6) * CFrame.Angles(0, 0.9, 0),
			RUBBLE,
			Enum.Material.Concrete
		)
	end
	local set = SHIRTS[(i + num) % #SHIRTS + 1]
	local hair = HAIR[(i * 3 + num) % #HAIR + 1]
	local rig = NpcRig.person(
		personLayout,
		"Trapped" .. num .. "_" .. i,
		rgb(set[1]),
		rgb(set[2]),
		rgb(set[3]),
		rgb(hair)
	)
	local at = StoryArtKit.PERSON
	-- sitting: the hips come down by the legs' length (the soles sit forward on the ground)
	local legs = personLayout.ground - personLayout.hip - 0.55
	NpcRig.place(rig, foot * CFrame.new(at[1], at[2] - legs, at[3]))
	sit(rig, 0)
	rig.model.Parent = m
	quietAll(m)
	m.Parent = folder
	return { foot = foot, model = m, girder = girder, person = rig, freedAt = nil, gone = false }
end

local function clearTraps()
	for _, t in traps do
		t.model:Destroy()
	end
	table.clear(traps)
end

local function trapStep(now: number)
	local m = StoryClient.mission
	local key = if m.kind == "hold"
			and m.people
			and m.points
		then tostring(m.num) .. ":" .. tostring(m.step)
		else nil
	if key ~= trapKey then
		clearTraps()
		trapKey = key
		if key then
			for i, p in m.points do
				traps[i] = buildTrap(i, p, m.num or 0)
			end
		end
	end
	if not key then
		return
	end
	local lo = StoryArtKit.GIRDER_LOW
	local pivot = CFrame.new(lo[1], lo[2], lo[3])
	for i, t in traps do
		if t.gone then
			continue
		end
		local share = ((m.held and m.held[i]) or 0) / math.max(1, m.seconds or 1)
		if share >= 1 and not t.freedAt then
			t.freedAt = now
			NpcRig.rest(t.person)
		end
		local lift = StoryArtKit.lift(share)
		local tip, fade = 0, 0
		if t.freedAt then
			local k = math.clamp((now - t.freedAt) / 0.6, 0, 1)
			tip = StoryArtKit.TIP * k * k
			fade = math.clamp((now - t.freedAt - 0.4) / 0.6, 0, 1)
		end
		local turn = t.foot * pivot * CFrame.Angles(math.rad(-tip), 0, math.rad(lift)) * pivot:Inverse()
		for gp, rel in t.girder do
			gp.CFrame = turn * rel
			gp.Transparency = fade
		end
		if t.freedAt then
			-- the person gets up, cheers a moment, then runs off (and is gone 16 studs on)
			local s = now - t.freedAt
			local rig = t.person
			local at = StoryArtKit.PERSON
			local run = math.max(0, s - 1.2)
			local away = math.min(run * 9, 16)
			NpcRig.place(rig, t.foot * CFrame.new(at[1], at[2], at[3] - away)) -- out from under, the way they face
			local swing = math.sin(s * 12) * 0.6
			if run > 0 then
				NpcRig.turn(rig, "LeftHip", CFrame.Angles(swing, 0, 0))
				NpcRig.turn(rig, "RightHip", CFrame.Angles(-swing, 0, 0))
				NpcRig.turn(rig, "LeftShoulder", CFrame.Angles(-swing, 0, 0))
				NpcRig.turn(rig, "RightShoulder", CFrame.Angles(swing, 0, 0))
			else
				NpcRig.turn(rig, "LeftShoulder", CFrame.Angles(math.rad(165) + swing * 0.3, 0, math.rad(-20)))
				NpcRig.turn(rig, "RightShoulder", CFrame.Angles(math.rad(165) - swing * 0.3, 0, math.rad(20)))
			end
			if s > 3.4 then
				t.gone = true
				rig.model:Destroy()
				for gp in t.girder do
					gp:Destroy()
				end
			end
		else
			sit(t.person, math.sin(now * 5 + i) * 0.35)
		end
	end
end

local function clearBeacon()
	if beacon then
		beacon.model:Destroy()
		beacon = nil
	end
end

local function beaconStep(now: number)
	local m = StoryClient.mission
	local budget = QualityController.preset.story
	local tgt = m.target
	local key = if m.kind == "reach"
			and tgt
			and budget
			and budget.beacon
		then string.format("%d:%d:%.0f:%.0f", m.num or 0, m.step or 0, tgt[1], tgt[3])
		else nil
	if key ~= beaconKey then
		clearBeacon()
		beaconKey = key
		if key and tgt then
			local foot = CFrame.new(ground(tgt))
			local model = Instance.new("Model")
			model.Name = "StoryBeacon"
			local anchor = part(model, Vector3.new(0.4, 0.4, 0.4), foot, Color3.new(1, 1, 1))
			anchor.Name = "Root"
			anchor.Transparency = 1
			local meshes =
				StoryProps.weld("StoryBeacon", anchor, StoryArtKit.middle(Config, "StoryBeacon"), model)
			local rings = meshes and meshes.StoryBeaconRings
			local ringBase = nil
			if rings then
				rings:FindFirstChildOfClass("Weld"):Destroy()
				rings.Anchored = true
				ringBase = foot:ToObjectSpace(rings.CFrame)
			elseif not meshes then
				-- PLACEHOLDER ART: a glowing column until Art.Story is imported
				local col = part(
					model,
					Vector3.new(38, 2.2, 2.2),
					foot * CFrame.new(0, 19.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Color3.fromRGB(255, 222, 110),
					Enum.Material.Neon,
					Enum.PartType.Cylinder
				)
				col.Transparency = 0.55
			end
			quietAll(model)
			model.Parent = folder
			beacon = { model = model, rings = rings, ringBase = ringBase, foot = foot }
		end
	end
	local b = beacon
	if b and b.rings and b.ringBase and budget and budget.rings then
		-- the chevron rings rise one ring-gap and start again, so they seem to climb for ever
		b.rings.CFrame = b.foot * CFrame.new(0, (now * 1.6) % 2, 0) * b.ringBase
	end
end

-- Overload: the arena's pillars crackle (a spark on a random pillar now and then)
local function arenaStep(now: number)
	local m = StoryClient.mission
	if not m.arena or (m.num or 0) ~= 6 or now < sparkAt then
		return
	end
	sparkAt = now + 0.7
	local pockets = Workspace:FindFirstChild("Pockets")
	local list = {}
	for _, p in (if pockets then pockets:GetDescendants() else {}) do
		if p:IsA("BasePart") and p.Shape == Enum.PartType.Cylinder then
			table.insert(list, p)
		end
	end
	if #list > 0 then
		local p = list[math.random(1, #list)]
		CombatFx.burst(
			p.Position + Vector3.new(0, math.random(-15, 15), 0),
			State.hero.fxStyle,
			Color3.fromRGB(190, 120, 255)
		)
	end
end

---------------------------------------------------------------------------
-- A mission's camera beats (lore step 5)
---------------------------------------------------------------------------

local player = Players.LocalPlayer
local sceneKey: any = nil
local lodestar: any = nil

local function heroRoot(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function lodestarStep(at: { number }?, face: Vector3?)
	if not at then
		if lodestar then
			lodestar.model:Destroy()
			lodestar = nil
		end
		return
	end
	if not lodestar then
		lodestar = PrologueFx.lodestarRig(folder)
	end
	local pos = Vector3.new(at[1], at[2], at[3])
	local d = if face then face - pos else Vector3.new(0, 0, 1)
	NpcRig.place(lodestar, CFrame.new(pos) * CFrame.Angles(0, math.atan2(-d.X, -d.Z), 0))
end

-- The beat's shot (lore step 7: played by the one cutscene player, CinemaClient): from beside and above the
-- hero, looking at the focus (or the hero, with no focus), with a slow push in over the beat
local function playScene(st: any, r: BasePart)
	local m = StoryClient.mission
	local f = m.focus
	local at = if f then Vector3.new(f[1], f[2] + 5, f[3]) else r.Position + Vector3.new(0, 3, 0)
	local flat = Vector3.new(r.Position.X - at.X, 0, r.Position.Z - at.Z)
	local back = if flat.Magnitude > 1 then flat.Unit else Vector3.new(0, 0, 1)
	local dist = math.clamp(flat.Magnitude * 0.6 + 26, 30, 70)
	local side = back:Cross(Vector3.new(0, 1, 0)) * 10
	local from = at + back * dist + side + Vector3.new(0, 14, 0)
	local to = from:Lerp(at, 0.22)
	local seconds = math.max(1, st.seconds)
	CinemaClient.play({
		owner = "mission",
		key = st,
		bit = CinemaPlan.missionBit(Config, m.num or 0, m.step or 0),
		shots = {
			{
				kind = "dolly",
				t0 = 0,
				t1 = seconds,
				from = { from.X, from.Y, from.Z },
				to = { to.X, to.Y, to.Z },
				at = { at.X, at.Y, at.Z },
				at2 = { at.X, at.Y, at.Z },
			},
		},
		seconds = seconds,
		beat = true,
		clock = function(): number
			local _, t = StoryClient.missionScene()
			return t
		end,
		canSkip = function(): boolean
			local _, t = StoryClient.missionScene()
			return StoryClient.mission.seen == true and t >= Config.Cinema.skipDelay
		end,
		skip = function()
			Net.send("SceneSkip")
		end,
	})
end

local function sceneStep()
	local st = StoryClient.missionScene()
	local m = StoryClient.mission
	local r = heroRoot()
	if not st or not r then
		if sceneKey ~= nil then
			CinemaClient.stop("mission")
			sceneKey = nil
		end
		lodestarStep(if StoryClient.inMission() and st then m.lodestar else nil, nil)
		return
	end
	lodestarStep(m.lodestar, r.Position)
	if sceneKey ~= st then
		sceneKey = st
		playScene(st, r)
	end
	-- (lore step 6: each line's blip is the guide line queue's, Ui.GuideHud)
end

function StoryFx.init()
	folder = Instance.new("Folder")
	folder.Name = "StoryFx"
	folder.Parent = Workspace
	Players.PlayerRemoving:Connect(function(p)
		local b = buddies[p]
		if b then
			b.anchor:Destroy()
			buddies[p] = nil
		end
		meshDrones[p] = nil
		lookAt[p] = nil
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("StoryFx", function(dt: number)
		local now = os.clock()
		if now >= slowAt then
			slowAt = now + 0.5
			StoryProps.step()
			local cam = Workspace.CurrentCamera
			buddySlow(if cam then cam.CFrame.Position else Vector3.zero)
		end
		buddyStep(now, math.min(dt or 1 / 60, 0.1))
		trapStep(now)
		beaconStep(now)
		arenaStep(now)
		sceneStep()
	end))
end

return StoryFx
