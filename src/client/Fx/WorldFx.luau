-- WorldFx: the world boss on screen and the events' looks (spec: World boss; Random events; Juice: boss
-- landing, phase change, defeat). The server's BossSim is the truth; this draws it.
-- * The boss model follows Boss.State (eased between the 2 Hz updates). The world bosses wear nate's lore looks
--   (2026-11-17, build plan step 8; art/blender/bosses.py, Config.BossArt): Rustjaw Prime, the Junkyard Titan (a
--   110-stud giant of wrecked cars with tyre knees, headlight eyes, a bumper jaw and a crane arm; welding sparks fly
--   from its seams), the Lumen Maw, the Light Eater (a sleek night creature whose maw pulls streams of light in and
--   dims the area round it), and the Leviathan Engine, the Deep Machine (an ancient brass-and-stone sea machine with
--   a tide-turbine heart; sea mist drifts off it). Broken objectives go dark. Never gory: machines shed sparks,
--   bolts and plates, the Maw bursts into light.
-- * Telegraphs from Boss.Attack: comic ground telegraphs that fill to the hit (Fx.BossTelegraph: ring, cone,
--   circles, lines, the pull; hazard-tape edges, cracks, chevrons); the strike flashes, shakes the camera near it,
--   and the pull drags this hero toward the Maw while it warns.
-- * Motion (the boss pass, 2026-11-19): every boss's segments are posed by Fx.BossAnim from Shared.BossPose: idle,
--   walk, each attack's wind-up timed to its warning, flinch, weak, stagger, enrage, defeat and the entrance.
-- * Events: Fx.EventFx draws the Tidal surge's wave and the Blackout's dark (was here: one glass slab and a
--   colour correction).
-- * Remade bosses (overhaul plan step 4; art/blender/bosses.py, Config.BossArt): once ReplicatedStorage.Art.Bosses
--   holds every mesh of a boss, it is drawn from them: a textured hull, armour plates that break off at phases 2
--   and 3, Neon accents in the phase colour, weak points in one pulsing gold, and the objectives' bodies with their
--   red lamps. Hit boxes stay Config.Boss's targets either way.
-- PLACEHOLDER ART: until those meshes are imported each world boss is drawn from its part-built look in
-- Config.BossArt (parts: the same silhouette in at most the old part count; accents still take the phase colour
-- and the weak points pulse gold). Bulwark's battle form (NullWarFrame) keeps its plain parts below (Tasks.md
-- "Lore step 8: world bosses").

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CombatFx = require(script.Parent.CombatFx)
local BossAnim = require(script.Parent.BossAnim)
local BossTelegraph = require(script.Parent.BossTelegraph)
local EventFx = require(script.Parent.EventFx)
local FxLib = require(script.Parent.FxLib)
local State = require(script.Parent.Parent.State)
local Juice = require(script.Parent.Juice)

local WorldFx = {}

local B = Config.Boss
local folder: Folder
local WARN = Color3.fromRGB(255, 70, 60)
local SCRAP = Color3.fromRGB(150, 110, 80)
local STEEL = Color3.fromRGB(90, 96, 108)
local ART = Config.BossArt
local LUMEN = Color3.fromRGB(ART.LumenMaw.theme[1], ART.LumenMaw.theme[2], ART.LumenMaw.theme[3]) -- the Maw's light

type Shown = {
	id: string,
	model: Model,
	objectives: { BasePart },
	x: number,
	y: number,
	z: number,
	yaw: number,
	tx: number,
	ty: number,
	tz: number,
	tyaw: number,
	lift: number, -- landing / rising / leaving offset
	state: number,
	art: boolean, -- drawn from Config.BossArt (the remade meshes, or a world boss's part-built look)
	phase: number, -- the phase its look shows (art only; 0 before the first state)
	weak: { BasePart }, -- the pulsing weak-point lamps (art only)
	nextFx: number, -- when its look's own effect (sparks, light, mist) next plays
	anim: BossAnim.Anim?, -- its segments in motion (Fx.BossAnim)
}
local shown: Shown? = nil

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
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
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- The boss models (built around the origin: feet at y 0, facing -z)
---------------------------------------------------------------------------

-- The War-Frame (mission 6): a tall humanoid war machine with 2 shoulder cannons, a glowing back
-- core (the phase 2 shield's weak point) and knee joints. PLACEHOLDER ART: parts until the mesh pass.
local function warframe(m: Model): { BasePart }
	local plate = Color3.fromRGB(48, 50, 62)
	local trim = Color3.fromRGB(150, 60, 200)
	for _, s in { -1, 1 } do
		part(m, Vector3.new(9, 4, 14), CFrame.new(s * 9, 2, -1), STEEL, Enum.Material.Metal) -- feet
		part(m, Vector3.new(7, 12, 7), CFrame.new(s * 9, 9, 0), plate, Enum.Material.Metal) -- shins
		part(m, Vector3.new(4, 4, 4), CFrame.new(s * 9, 14, -4), trim, Enum.Material.Neon, Enum.PartType.Ball)
		part(m, Vector3.new(8, 12, 8), CFrame.new(s * 9, 21, 0), STEEL, Enum.Material.Metal) -- thighs
		-- arms
		part(
			m,
			Vector3.new(7, 22, 7),
			CFrame.new(s * 21, 36, 0) * CFrame.Angles(0, 0, math.rad(s * 6)),
			plate,
			Enum.Material.Metal
		)
		part(m, Vector3.new(9, 9, 9), CFrame.new(s * 23, 23, -1), STEEL, Enum.Material.Metal) -- fists
	end
	part(m, Vector3.new(22, 10, 14), CFrame.new(0, 29, 0), plate, Enum.Material.Metal) -- hips
	part(m, Vector3.new(30, 20, 18), CFrame.new(0, 42, 0), STEEL, Enum.Material.Metal) -- chest
	part(m, Vector3.new(10, 6, 2), CFrame.new(0, 44, -9.2), trim, Enum.Material.Neon) -- chest light
	part(m, Vector3.new(11, 9, 11), CFrame.new(0, 56, -3), plate, Enum.Material.Metal) -- head
	part(m, Vector3.new(8, 2, 1), CFrame.new(0, 57, -8.6), Color3.fromRGB(255, 80, 80), Enum.Material.Neon) -- visor
	local back = part(m, Vector3.new(6, 6, 3), CFrame.new(0, 40, 10.5), trim, Enum.Material.Neon)
	back.Name = "BackCore"
	local cannons = {}
	for _, row in B.bosses.NullWarFrame.objectives.list do
		local at = row.at
		local base =
			part(m, Vector3.new(8, 6, 8), CFrame.new(at[1], at[2] - 2, at[3]), STEEL, Enum.Material.Metal)
		base.Name = "Cannon"
		part(
			m,
			Vector3.new(2.8, 12, 2.8),
			CFrame.new(at[1], at[2] + 1, at[3] - 5) * CFrame.Angles(math.rad(70), 0, 0),
			Color3.fromRGB(60, 60, 66),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		local glow = part(
			m,
			Vector3.new(2.6, 2.6, 2.6),
			CFrame.new(at[1], at[2] + 3, at[3]),
			WARN,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		glow.Name = "ObjectiveGlow"
		table.insert(cannons, glow)
	end
	return cannons
end

---------------------------------------------------------------------------
-- The remade bosses (art/blender/bosses.py): meshes from ReplicatedStorage.Art.Bosses placed from Config.BossArt,
-- or until they are imported, a world boss's part-built look from the same table
---------------------------------------------------------------------------

local LIT = { glow = true, weak = true, objectiveGlow = true }

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Every imported mesh of one boss by piece name ("<Boss>_<Piece>"), or nil while any is missing (then the boss
-- keeps its plain parts)
local function bossMeshes(id: string): { [string]: MeshPart }?
	local fit = ART[id]
	local art = ReplicatedStorage:FindFirstChild("Art")
	local lib = art and art:FindFirstChild("Bosses")
	if not (fit and lib) then
		return nil
	end
	local out = {}
	for _, group in { fit.pieces, fit.objective } do
		for name in group do
			local found = lib:FindFirstChild(id .. "_" .. name, true)
			if not (found and found:IsA("MeshPart")) then
				return nil
			end
			out[name] = found
		end
	end
	return out
end

-- One placed copy of an imported piece: textured roles keep their SurfaceAppearance, lit roles are plain Neon
local function meshPiece(
	src: MeshPart,
	name: string,
	row: { [string]: any },
	at: CFrame,
	parent: Instance
): MeshPart
	local p = src:Clone()
	local lit = LIT[row.role] == true
	for _, c in p:GetChildren() do
		if lit or not c:IsA("SurfaceAppearance") then
			c:Destroy()
		end
	end
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = not lit
	p.Size = Vector3.new(row.size[1], row.size[2], row.size[3])
	p.CFrame = at * CFrame.new(row.offset[1], row.offset[2], row.offset[3])
	p.Material = if lit then Enum.Material.Neon else Enum.Material.Metal
	p.Color = if row.role == "weak" then rgb(ART.weakColor[1]) else Color3.fromRGB(200, 200, 200)
	p:SetAttribute("Role", row.role)
	if row.seg then
		p:SetAttribute("Seg", row.seg)
	end
	p.Parent = parent
	return p
end

-- An objective's place (shoulder cannons and vent hatches on the body; the Maw's generators round its pit in the
-- world) and the parent its pieces go in
local function objectiveAt(
	def: { [string]: any },
	row: { [string]: any },
	s: { [string]: any },
	m: Model
): (CFrame, Instance)
	if row.at then
		return CFrame.new(row.at[1], row.at[2], row.at[3]), m
	end
	local a = math.rad(row.ring)
	local r = def.arenaRadius * 0.75
	return CFrame.new(s.x + math.cos(a) * r, s.y, s.z + math.sin(a) * r), folder
end

-- The whole boss from its meshes (around the origin, like the parts), and its objectives in list order: shoulder
-- cannons and torpedo bays on the body, the Maw's generators standing round its pit in the world
local function meshBoss(
	m: Model,
	id: string,
	meshes: { [string]: MeshPart },
	s: { [string]: any }
): { BasePart }
	local fit = ART[id]
	local def = B.bosses[id]
	for name, row in fit.pieces do
		meshPiece(meshes[name], name, row, CFrame.new(), m)
	end
	local glows = {}
	for _, row in def.objectives.list do
		local at, parent = objectiveAt(def, row, s, m)
		for name, prow in fit.objective do
			local p = meshPiece(meshes[name], name, prow, at, parent)
			if prow.role == "objectiveGlow" then
				p.Name = "ObjectiveGlow"
				p.Color = rgb(ART.objectiveColor)
				table.insert(glows, p)
			elseif parent == folder then
				p:SetAttribute("Boss", true)
			end
		end
	end
	return glows
end

local SHAPES = { Ball = Enum.PartType.Ball, Cylinder = Enum.PartType.Cylinder, Block = Enum.PartType.Block }
local MATS = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Slate = Enum.Material.Slate,
	CorrodedMetal = Enum.Material.CorrodedMetal,
}

-- One part of a part-built look (lit roles are Neon: glow in the phase colour, weak gold, objective lamps red)
local function lookPart(fit: { [string]: any }, row: { [string]: any }, at: CFrame, parent: Instance): Part
	local r = row.rot or { 0, 0, 0 }
	local cf = at
		* CFrame.new(row.at[1], row.at[2], row.at[3])
		* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	local role = row.role
	local color = if role == "weak"
		then rgb(ART.weakColor[1])
		elseif role == "glow" then rgb(fit.glow[1])
		elseif role == "objectiveGlow" then rgb(ART.objectiveColor)
		else rgb(row.color)
	local p = part(
		parent,
		Vector3.new(row.size[1], row.size[2], row.size[3]),
		cf,
		color,
		if LIT[role] then Enum.Material.Neon else MATS[row.mat] or Enum.Material.SmoothPlastic,
		SHAPES[row.shape]
	)
	p.CastShadow = not LIT[role]
	p:SetAttribute("Role", role)
	if row.seg then
		p:SetAttribute("Seg", row.seg)
	end
	return p
end

-- A world boss's part-built look (PLACEHOLDER ART until the meshes are imported) and its objectives in list order
local function partBoss(m: Model, id: string, s: { [string]: any }): { BasePart }
	local fit = ART[id]
	local def = B.bosses[id]
	for _, row in fit.parts do
		lookPart(fit, row, CFrame.new(), m)
	end
	local glows = {}
	for _, orow in def.objectives.list do
		local at, parent = objectiveAt(def, orow, s, m)
		for _, row in fit.objectiveParts do
			local p = lookPart(fit, row, at, parent)
			if row.role == "objectiveGlow" then
				p.Name = "ObjectiveGlow"
				table.insert(glows, p)
			elseif parent == folder then
				p:SetAttribute("Boss", true)
			end
		end
	end
	return glows
end

-- Bits flying off the boss (plates at a phase, the defeat): a machine's sparks and plates; the Maw bursts into light
local function shatter(sh: Shown, pos: Vector3)
	local fit = ART[sh.id]
	local debris = if fit and fit.debris then rgb(fit.debris) else SCRAP
	if fit and fit.fx and fit.fx.kind == "light" then
		FxLib.burst(pos, 8, nil, debris, true)
	else
		CombatFx.burst(pos, State.hero.fxStyle, debris)
	end
end

-- The look of a phase (art only): accents take the phase colour, and the plates for this phase break off (they
-- fall and fade with a burst of sparks; joining mid-fight just leaves them off)
local function showPhase(sh: Shown, phase: number)
	local animate = sh.phase > 0
	sh.phase = phase
	local fit = ART[sh.id]
	local glow = rgb(fit.glow[math.clamp(phase, 1, #fit.glow)])
	for _, p in sh.model:GetChildren() do
		if not p:IsA("BasePart") then
			continue
		end
		local role = p:GetAttribute("Role")
		if role == "glow" then
			p.Color = glow
		elseif (role == "shed2" and phase >= 2) or (role == "shed3" and phase >= 3) then
			if animate then
				shatter(sh, p.Position)
				p.Parent = folder
				local spin = CFrame.Angles(math.rad(math.random(-40, 40)), 0, math.rad(math.random(-40, 40)))
				TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = (p.CFrame - Vector3.new(0, 40, 0)) * spin,
					Transparency = 1,
				}):Play()
				Debris:AddItem(p, 1.7)
			else
				p:Destroy()
			end
		end
	end
end

local function build(id: string, s: { [string]: any }): Shown
	local m = Instance.new("Model")
	m.Name = id
	local root = part(m, Vector3.one, CFrame.new(), STEEL)
	root.Transparency = 1
	root.Name = "Root"
	m.PrimaryPart = root
	local objectives = {}
	local meshes = bossMeshes(id)
	local weak = {}
	local parts = not meshes and ART[id] ~= nil and ART[id].parts ~= nil
	if meshes then
		objectives = meshBoss(m, id, meshes, s)
	elseif parts then
		objectives = partBoss(m, id, s)
	else
		objectives = warframe(m)
	end
	for _, p in m:GetChildren() do
		if p:GetAttribute("Role") == "weak" then
			table.insert(weak, p :: BasePart)
		end
	end
	m.Parent = folder
	return {
		anim = BossAnim.attach(id, m),
		id = id,
		model = m,
		objectives = objectives,
		x = s.x,
		y = s.y,
		z = s.z,
		yaw = s.yaw or 0,
		tx = s.x,
		ty = s.y,
		tz = s.z,
		tyaw = s.yaw or 0,
		lift = if id == "RustjawPrime" then 260 elseif id == "NullWarFrame" then 120 else -B.bosses[id].height,
		state = s.state,
		art = meshes ~= nil or parts,
		phase = 0,
		weak = weak,
		nextFx = 0,
	}
end

local function destroy(sh: Shown)
	if sh.anim then
		BossAnim.detach(sh.anim)
		sh.anim = nil
	end
	sh.model:Destroy()
	for _, o in sh.objectives do
		if o.Parent == folder then
			-- a generator: its base sits just under the core
			o:Destroy()
		end
	end
	for _, p in folder:GetChildren() do
		if p:GetAttribute("Boss") then
			p:Destroy()
		end
	end
end

local function remove()
	if shown then
		destroy(shown)
		shown = nil
	end
end

local function onState()
	local s = WorldClient.boss
	if not (s.state == 2 or s.state == 3) or not s.id then
		if shown and (s.state == 0 or s.state == 1) then
			remove()
		end
		return
	end
	if not shown or shown.id ~= s.id then
		remove()
		shown = build(s.id, s)
	end
	local sh = shown :: Shown
	sh.tx, sh.ty, sh.tz, sh.tyaw = s.x, s.y, s.z, s.yaw or 0
	sh.state = s.state
	if sh.anim then
		BossAnim.state(sh.anim, s.hp, s.max, s.phase)
	end
	if sh.art and (s.phase or 1) ~= sh.phase then
		showPhase(sh, s.phase or 1)
	end
	-- the War-Frame's phase 2 shield: a bubble until 3 hits on the back core break it
	local bubble = sh.model:FindFirstChild("Shield") :: BasePart?
	if (s.shield or 0) > 0 and not bubble then
		local def = B.bosses[s.id]
		local ball = part(
			sh.model,
			Vector3.one * def.height * 1.2,
			sh.model:GetPivot() * CFrame.new(0, def.height * 0.55, 0),
			Color3.fromRGB(170, 110, 255),
			Enum.Material.ForceField,
			Enum.PartType.Ball
		)
		ball.Name = "Shield"
		ball.Transparency = 0.3
	elseif (s.shield or 0) <= 0 and bubble then
		CombatFx.burst(bubble.Position, State.hero.fxStyle)
		bubble:Destroy()
	end
	for i, glow in sh.objectives do
		local up = (s.objectives or {})[i]
		if up ~= nil and up <= 0 and glow.Material == Enum.Material.Neon then
			glow.Material = Enum.Material.Metal
			glow.Color = Color3.fromRGB(40, 40, 44)
			CombatFx.burst(glow.Position, State.hero.fxStyle)
		end
	end
end

---------------------------------------------------------------------------
-- Each world boss's look in motion (Config.BossArt fx): Rustjaw's welding sparks, the Maw's light pulled into its
-- maw while the area round it dims, the Leviathan's sea mist. Cheap: pooled particles and a few pooled streaks.
---------------------------------------------------------------------------

local streaks: { Part } = {}
local nextStreak = 1
local mawDim: ColorCorrectionEffect? = nil

local function heroPos(): Vector3?
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- one streak of light flying from a ring round the maw into it (8 pooled thin Neon parts)
local function lightStreak(mouth: CFrame, reach: number, color: Color3)
	if #streaks < 8 then
		local p = part(folder, Vector3.new(0.5, 0.5, 7), CFrame.new(), color, Enum.Material.Neon)
		p.Name = "MawLight"
		p.Transparency = 1
		table.insert(streaks, p)
	end
	local p = streaks[nextStreak]
	nextStreak = nextStreak % 8 + 1
	if not p then
		return
	end
	local a = math.random() * math.pi * 2
	local from = mouth
		* Vector3.new(math.cos(a) * reach, math.sin(a) * reach * 0.6, -reach * (0.6 + math.random() * 0.6))
	local to = mouth.Position
	p.Color = color
	p.Transparency = 0.15
	p.Size = Vector3.new(0.5, 0.5, 7)
	p.CFrame = CFrame.lookAt(from, to)
	TweenService:Create(p, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.lookAt(to, to + (to - from).Unit),
		Size = Vector3.new(0.2, 0.2, 2),
		Transparency = 1,
	}):Play()
end

local function lookFx(sh: Shown)
	local fit = ART[sh.id]
	local fx = fit and fit.fx
	local dimWant = 0
	if fx and (sh.state == 2 or sh.state == 3) then
		local pivot = sh.model:GetPivot()
		local now = os.clock()
		if now >= sh.nextFx then
			sh.nextFx = now + fx.every
			local glow = rgb(fit.glow[math.clamp(sh.phase, 1, #fit.glow)])
			local at = fx.at[math.random(1, #fx.at)]
			local pos = pivot * Vector3.new(at[1], at[2], at[3])
			if fx.kind == "sparks" then
				FxLib.emit("spark", rgb(fit.theme), pos, 5, pivot:VectorToWorldSpace(Vector3.new(0, 0.6, -1)))
			elseif fx.kind == "tide" then
				FxLib.emit("smoke", Color3.fromRGB(210, 240, 245), pos, 1, Vector3.new(0, 1, 0))
			elseif fx.kind == "light" then
				lightStreak(pivot * CFrame.new(at[1], at[2], at[3]), fx.reach, glow)
			end
		end
		if fx.dim then
			-- the Light Eater darkens the area round it for whoever stands near (eased in and out)
			local hp = heroPos()
			local def = B.bosses[sh.id]
			if hp then
				local d = (hp - pivot.Position).Magnitude
				dimWant = -fx.dim * math.clamp(1 - (d - def.arenaRadius) / 150, 0, 1)
			end
		end
	end
	if dimWant < 0 and not mawDim then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "MawDim"
		c.Parent = Lighting
		mawDim = c
	end
	local c = mawDim
	if c then
		c.Brightness += (dimWant - c.Brightness) * 0.05
		c.Saturation = c.Brightness * 1.4
		c.TintColor = Color3.new(1, 1, 1)
			:Lerp(Color3.fromRGB(170, 180, 255), math.clamp(-c.Brightness * 3, 0, 1))
		if dimWant == 0 and math.abs(c.Brightness) < 0.005 then
			c:Destroy()
			mawDim = nil
		end
	end
end

-- A beaten boss plays its collapse before it sinks (BossAnim's defeat clip), off the shown slot
local dying: { { sh: Shown, cf: CFrame } } = {}

local function frame(dt: number)
	for _, d in dying do
		if d.sh.anim then
			BossAnim.step(d.sh.anim, d.cf, dt, false)
		end
	end
	BossTelegraph.step()
	local sh = shown
	if not sh then
		if mawDim then
			mawDim:Destroy()
			mawDim = nil
		end
		return
	end
	local k = math.min(1, dt * 3)
	sh.x += (sh.tx - sh.x) * k
	sh.y += (sh.ty - sh.y) * k
	sh.z += (sh.tz - sh.z) * k
	local d = (sh.tyaw - sh.yaw + math.pi) % (2 * math.pi) - math.pi
	sh.yaw += d * k
	if sh.state == 3 then
		sh.lift += (0 - sh.lift) * math.min(1, dt * 2.5)
	elseif sh.state == 2 then
		sh.lift += (0 - sh.lift) * math.min(1, dt * 0.9)
	elseif sh.state == 5 then
		sh.lift += dt * 40
	end
	local rootCF = CFrame.new(sh.x, sh.y + sh.lift, sh.z) * CFrame.Angles(0, sh.yaw, 0)
	if sh.anim then
		-- Rustjaw walks while it closes on the crowd (BossSim moves it 6 studs a second)
		local moving = (sh.tx - sh.x) ^ 2 + (sh.tz - sh.z) ^ 2 > 1
		BossAnim.step(sh.anim, rootCF, dt, moving)
	else
		sh.model:PivotTo(rootCF)
	end
	if #sh.weak > 0 then
		-- the weak points pulse gold, the same on every boss ("hit the gold")
		local f = 0.5 + 0.5 * math.sin(os.clock() * ART.pulse * 2 * math.pi)
		local c = rgb(ART.weakColor[1]):Lerp(rgb(ART.weakColor[2]), f)
		for _, p in sh.weak do
			p.Color = c
		end
	end
	if sh.art then
		lookFx(sh)
	end
end

---------------------------------------------------------------------------
-- Telegraphs and strikes
---------------------------------------------------------------------------

local function ground(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y + 0.2, z)
end

local pullUntil, pullAt, pullR = 0, Vector3.zero, 0

-- The boss's look colour (the pull's motes, the strike's shockwave), the attack's red otherwise
local function lookColor(num: number?): Color3
	local id = WorldClient.bossByNum[num or 0] or (shown and shown.id)
	local fit = id and ART[id]
	return if fit and fit.theme then rgb(fit.theme) else WARN
end

local function warn(ev: { [string]: any })
	local t = ev.t or 1
	local c = ground(ev.x, ev.y, ev.z)
	BossTelegraph.warn(ev, ev.y, lookColor(ev.num))
	if ev.shape == "pull" then
		pullUntil, pullAt, pullR = os.clock() + t, c, ev.r
	end
	-- the boss winds up over the warning so the strike lands on the hit (the cannons have their own small kick)
	local sh = shown
	if sh and sh.anim and ev.src == "boss" and ev.a then
		BossAnim.attack(sh.anim, ev.a, t)
	end
end

local function near(at: Vector3, r: number): boolean
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - at).Magnitude <= r
end

local function strike(ev: { [string]: any })
	local c = ground(ev.x, ev.y, ev.z)
	local style = State.hero.fxStyle
	BossTelegraph.strike(ev, ev.y, lookColor(ev.num))
	local sh = shown
	if sh and sh.anim then
		if ev.src == "boss" then
			BossAnim.strike(sh.anim, ev.a)
		elseif ev.src == "cannon" then
			BossAnim.play(sh.anim, "shot")
		end
	end
	if ev.shape == "ring" then
		CombatFx.slam(c, ev.r)
	elseif ev.shape == "cone" then
		-- the swipe, bite or sweep fans out in front of where the boss faced when it warned
		local yaw = if sh then sh.yaw else 0
		CombatFx.cone(
			c + Vector3.new(0, 3, 0),
			Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)),
			ev.r,
			100,
			style,
			WARN
		)
		FxLib.dust(c, ev.r * 0.5)
	elseif ev.shape == "circles" then
		for _, p in ev.points or {} do
			CombatFx.slam(ground(p[1], ev.y, p[2]), ev.r)
		end
	elseif ev.shape == "lines" then
		local width = (B.bosses[WorldClient.bossByNum[ev.num] or ""] or { attacks = {} }).attacks
		local w, len = 10, 200
		for _, a in width do
			if a.id == ev.a then
				w, len = a.width or w, a.length or len
			end
		end
		local s = shown
		local fromY = if s then s.y + B.bosses[s.id].height * 0.8 else ev.y + 60
		for _, d in ev.points or {} do
			local dir = Vector3.new(d[1], 0, d[2])
			CombatFx.line(
				Vector3.new(ev.x, fromY, ev.z),
				c + dir * len,
				w,
				style,
				if ev.a == "LumenBeam" then LUMEN else WARN,
				true
			)
		end
	elseif ev.shape == "pull" then
		CombatFx.nova(c, ev.r, style, LUMEN, true)
	end
	if near(c, (ev.r or 40) + 60) then
		CameraController.shake(0.4, if ev.struct then 1.2 else 0.6)
	end
end

local function bigMoment(ev: { [string]: any })
	local s = shown
	local style = State.hero.fxStyle
	if ev.k == "land" then
		task.delay(B.schedule.landing * 0.8, function()
			local at = Vector3.new(ev.x, ev.y, ev.z)
			if shown and shown.anim then
				BossAnim.play(shown.anim, "land")
			end
			CombatFx.slam(at, 60)
			-- the entrance in its look's colour (welding orange, the Maw's light, the Deep Machine's aqua)
			local id = WorldClient.bossByNum[ev.num or 0] or (shown and shown.id)
			local fit = id and ART[id]
			if fit and fit.theme then
				CombatFx.nova(at + Vector3.new(0, 4, 0), 70, style, rgb(fit.theme), true)
			end
			if near(at, 500) then
				CameraController.shake(1.2, 1.6)
			end
		end)
	elseif ev.k == "phase" and s then
		local top = s.model:GetPivot().Position + Vector3.new(0, B.bosses[s.id].height * 0.7, 0)
		local fit = ART[s.id]
		local glow = if fit and fit.look then rgb(fit.glow[math.clamp(ev.phase or 2, 1, #fit.glow)]) else WARN
		CombatFx.nova(top, 40, style, glow, true)
		CombatFx.banner(string.format("PHASE %d!", ev.phase), WARN, style)
		Juice.fire("bossPhase", top, { mine = near(top, 500) })
		if s.anim then
			-- the plates break: it staggers, then roars into the new phase
			BossAnim.phase(s.anim, ev.phase or 2)
		end
	elseif ev.k == "shield" and s and s.anim and (ev.left or 0) <= 0 then
		-- the War-Frame's shield broke: it reels and shows its back core
		BossAnim.play(s.anim, "weak")
	elseif ev.k == "dead" and s then
		-- it falls apart: plates and bolts everywhere, then it sinks
		local pivot = s.model:GetPivot()
		Juice.fire("bossDefeated", pivot.Position)
		for i = 1, 6 do
			task.delay(i * 0.25, function()
				local h = B.bosses[s.id].height
				shatter(
					s,
					pivot.Position
						+ Vector3.new(math.random(-20, 20), math.random(10, h), math.random(-20, 20))
				)
			end)
		end
		CombatFx.banner("BOSS DEFEATED!", Color3.fromRGB(255, 200, 60), style)
		-- it collapses first (BossAnim's defeat clip), then sinks away
		local hold = 0
		local row = { sh = s, cf = s.model:GetPivot() }
		if s.anim then
			BossAnim.play(s.anim, "defeat")
			table.insert(dying, row)
			hold = 2.6
		end
		shown = nil
		task.delay(hold, function()
			local i = table.find(dying, row)
			if i then
				table.remove(dying, i)
			end
			if s.anim then
				BossAnim.detach(s.anim)
				s.anim = nil
			end
			for _, p in s.model:GetDescendants() do
				if p:IsA("BasePart") then
					TweenService
						:Create(p, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							CFrame = p.CFrame - Vector3.new(0, 30, 0),
							Transparency = 1,
						})
						:Play()
				end
			end
			task.delay(3.2, function()
				destroy(s)
			end)
		end)
	elseif ev.k == "retreat" then
		CombatFx.banner("IT GOT AWAY!", Color3.fromRGB(200, 200, 210), style)
		task.delay(5, function()
			if shown and shown.state == 5 then
				remove()
			end
		end)
		if s then
			s.state = 5
		end
	end
end

local function onAttack(ev: { [string]: any })
	if ev.k == "warn" then
		warn(ev)
	elseif ev.k == "strike" then
		strike(ev)
	else
		bigMoment(ev)
	end
end

-- The Maw's gravity pull: this hero slides toward it while the warning runs
local function pullStep(dt: number)
	if os.clock() >= pullUntil then
		return
	end
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local d = (pullAt - root.Position) * Vector3.new(1, 0, 1)
	if d.Magnitude > pullR or d.Magnitude < 6 then
		return
	end
	-- a steady 14 studs a second drag on top of whatever the hero is doing (running out still escapes it)
	root.CFrame += d.Unit * 14 * dt
end

function WorldFx.init()
	folder = Instance.new("Folder")
	folder.Name = "WorldFx"
	folder.Parent = Workspace
	WorldClient.Changed:Connect(function(what)
		if what == "boss" then
			onState()
		end
	end)
	WorldClient.BossAttack:Connect(onAttack)
	BossTelegraph.init(folder)
	EventFx.init(folder)
	RunService.RenderStepped:Connect(FrameProf.wrap("WorldFx", function(dt)
		frame(dt)
		pullStep(dt)
	end))
end

return WorldFx
