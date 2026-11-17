-- WorldFx: the world boss on screen and the events' looks (spec: World boss; Random events; Juice: boss
-- landing, phase change, defeat). The server's BossSim is the truth; this draws it.
-- * The boss model follows Boss.State (eased between the 2 Hz updates): Rustjaw Prime, a 110-stud scrap
--   robot with glowing core and knee weak points and two shoulder cannons; the Lumen Maw, a crystal-powered
--   machine beast with three crystals on its back and crystal generators around its pit. Broken objectives
--   go dark. Machines only: defeats are sparks, bolts and plates, never anything else.
-- * Telegraphs from Boss.Attack: red ground markers that fill over the warning (ring, cone, circles, lines,
--   the gravity pull's wide ring); the strike flashes, shakes the camera near it, and the pull drags this
--   hero toward the Maw while it warns.
-- * Events: the Tidal surge raises the water over the Docks, the Blackout dims Old Town for whoever stands
--   in it.
-- * Remade bosses (overhaul plan step 4; art/blender/bosses.py, Config.BossArt): once ReplicatedStorage.Art.Bosses
--   holds every mesh of a boss, it is drawn from them: a textured hull, armour plates that break off at phases 2
--   and 3, Neon accents in the phase colour, weak points in one pulsing gold, and the objectives' bodies with their
--   red lamps. Hit boxes stay Config.Boss's targets either way.
-- PLACEHOLDER LOOK: boss lore pending. The world and event bosses stand apart from the main story (nate,
-- 2026-11-17), so the remade meshes are generic neutral machines (no faction emblems, no text, no story looks).
-- PLACEHOLDER ART: until those meshes are imported every boss is the plain parts below, unchanged (Tasks.md
-- "Remade bosses").

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
local State = require(script.Parent.Parent.State)
local Juice = require(script.Parent.Juice)

local WorldFx = {}

local B = Config.Boss
local folder: Folder
local WARN = Color3.fromRGB(255, 70, 60)
local SCRAP = Color3.fromRGB(150, 110, 80)
local STEEL = Color3.fromRGB(90, 96, 108)
local LUMEN = Color3.fromRGB(150, 120, 255)

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
	art: boolean, -- drawn from the remade meshes (Config.BossArt)
	phase: number, -- the phase its look shows (art only; 0 before the first state)
	weak: { BasePart }, -- the pulsing weak-point lamps (art only)
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

local function rustjaw(m: Model): { BasePart }
	-- legs and feet
	for _, s in { -1, 1 } do
		part(m, Vector3.new(16, 8, 24), CFrame.new(s * 14, 4, -2), STEEL, Enum.Material.Metal)
		part(m, Vector3.new(10, 40, 10), CFrame.new(s * 14, 26, 0), SCRAP, Enum.Material.CorrodedMetal)
		part(
			m,
			Vector3.new(4, 4, 4),
			CFrame.new(s * 14, 30, -6),
			WARN,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
	end
	-- torso, core, head and jaw
	part(m, Vector3.new(44, 40, 30), CFrame.new(0, 66, 0), SCRAP, Enum.Material.CorrodedMetal)
	part(m, Vector3.new(30, 10, 26), CFrame.new(0, 48, 0), STEEL, Enum.Material.Metal)
	part(m, Vector3.new(8, 8, 2), CFrame.new(0, 72, -15.5), Color3.fromRGB(255, 170, 60), Enum.Material.Neon)
	part(m, Vector3.new(22, 16, 20), CFrame.new(0, 96, -4), STEEL, Enum.Material.Metal)
	part(m, Vector3.new(20, 5, 18), CFrame.new(0, 86, -7), SCRAP, Enum.Material.CorrodedMetal)
	for _, s in { -1, 1 } do
		part(
			m,
			Vector3.new(5, 3, 1),
			CFrame.new(s * 5, 99, -14.6),
			Color3.fromRGB(255, 220, 90),
			Enum.Material.Neon
		)
		-- arms
		part(
			m,
			Vector3.new(10, 34, 10),
			CFrame.new(s * 28, 62, -2) * CFrame.Angles(0, 0, math.rad(s * 8)),
			SCRAP
		)
		part(m, Vector3.new(14, 12, 14), CFrame.new(s * 31, 42, -4), STEEL, Enum.Material.Metal)
	end
	-- shoulder cannons (the objectives)
	local cannons = {}
	for _, row in B.bosses.RustjawPrime.objectives.list do
		local at = row.at
		local base =
			part(m, Vector3.new(10, 8, 10), CFrame.new(at[1], at[2] - 2, at[3]), STEEL, Enum.Material.Metal)
		part(
			m,
			Vector3.new(3.4, 16, 3.4),
			CFrame.new(at[1], at[2] + 2, at[3] - 6) * CFrame.Angles(math.rad(70), 0, 0),
			Color3.fromRGB(60, 60, 66),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		local glow = part(
			m,
			Vector3.new(3, 3, 3),
			CFrame.new(at[1], at[2] + 4, at[3]),
			WARN,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		glow.Name = "ObjectiveGlow"
		table.insert(cannons, glow)
		base.Name = "Cannon"
	end
	return cannons
end

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

local function maw(m: Model)
	local body = Color3.fromRGB(70, 64, 90)
	part(m, Vector3.new(40, 26, 56), CFrame.new(0, 26, 8), body, Enum.Material.Metal)
	part(m, Vector3.new(30, 22, 26), CFrame.new(0, 38, -28), body, Enum.Material.Metal)
	-- the jaw: two plates with a glowing throat
	part(m, Vector3.new(28, 4, 22), CFrame.new(0, 26, -36), STEEL, Enum.Material.Metal)
	part(m, Vector3.new(14, 6, 2), CFrame.new(0, 32, -41), LUMEN, Enum.Material.Neon)
	for _, s in { -1, 1 } do
		part(
			m,
			Vector3.new(4, 3, 1),
			CFrame.new(s * 8, 44, -41.2),
			Color3.fromRGB(220, 200, 255),
			Enum.Material.Neon
		)
		for k = 0, 1 do
			part(m, Vector3.new(8, 20, 8), CFrame.new(s * 18, 10, -12 + k * 34), STEEL, Enum.Material.Metal)
		end
	end
	-- back crystals (weak points)
	for _, t in B.bosses.LumenMaw.targets do
		if t.weak then
			part(
				m,
				Vector3.new(5, 14, 5),
				CFrame.new(t.at[1], t.at[2], t.at[3]) * CFrame.Angles(0, math.rad(45), math.rad(12)),
				LUMEN,
				Enum.Material.Neon
			)
		end
	end
end

-- The Leviathan Engine (underwater at launch): a serpent-shaped war submarine. A segmented hull runs
-- back under the surface, the neck and armoured head rise out of the water facing -z, two eyes and a
-- reactor glow (weak points), and two torpedo bays on its back are the objectives. Feet (y 0) are the
-- water's surface. PLACEHOLDER ART: parts until the mesh pass.
local function leviathan(m: Model): { BasePart }
	local cfg = B.bosses.LeviathanEngine
	local hull = Color3.fromRGB(38, 62, 78)
	local plate = Color3.fromRGB(70, 96, 110)
	local glow = Color3.fromRGB(90, 230, 255)
	-- the hull: segments trailing back and down under the water, with dorsal fins
	for k = 0, 6 do
		local size = 26 - k * 2.4
		local cf = CFrame.new(0, 4 - k * 3.5, 10 + k * 20) * CFrame.Angles(math.rad(-8), 0, 0)
		part(
			m,
			Vector3.new(size, size * 0.8, 22),
			cf,
			if k % 2 == 0 then hull else plate,
			Enum.Material.Metal
		)
		part(
			m,
			Vector3.new(2, size * 0.5, 10),
			cf * CFrame.new(0, size * 0.55, 0),
			STEEL,
			Enum.Material.Metal
		)
	end
	-- the neck: three rising segments, then the head with a jaw, eyes and a glowing throat
	for k = 0, 2 do
		part(
			m,
			Vector3.new(16 - k, 14, 16 - k),
			CFrame.new(0, 12 + k * 11, -6 - k * 9) * CFrame.Angles(math.rad(-35), 0, 0),
			if k % 2 == 0 then plate else hull,
			Enum.Material.Metal
		)
	end
	part(m, Vector3.new(22, 16, 30), CFrame.new(0, 46, -36), hull, Enum.Material.Metal)
	part(m, Vector3.new(20, 5, 24), CFrame.new(0, 36, -40), STEEL, Enum.Material.Metal) -- the jaw
	part(m, Vector3.new(14, 4, 1), CFrame.new(0, 41, -51.6), glow, Enum.Material.Neon) -- the throat
	for _, t in cfg.targets do
		if t.weak then
			part(
				m,
				Vector3.one * (t.r + 1),
				CFrame.new(t.at[1], t.at[2], t.at[3]),
				glow,
				Enum.Material.Neon,
				Enum.PartType.Ball
			)
		end
	end
	-- side fins
	for _, s in { -1, 1 } do
		part(
			m,
			Vector3.new(26, 2, 12),
			CFrame.new(s * 22, 2, 6) * CFrame.Angles(0, math.rad(s * 25), math.rad(s * -12)),
			plate,
			Enum.Material.Metal
		)
	end
	-- torpedo bays (the objectives)
	local bays = {}
	for _, row in cfg.objectives.list do
		local at = row.at
		local base =
			part(m, Vector3.new(9, 6, 12), CFrame.new(at[1], at[2] - 2, at[3]), STEEL, Enum.Material.Metal)
		base.Name = "Cannon"
		local light = part(
			m,
			Vector3.new(3, 3, 3),
			CFrame.new(at[1], at[2] + 2, at[3]),
			WARN,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		light.Name = "ObjectiveGlow"
		table.insert(bays, light)
	end
	return bays
end

local function generators(cx: number, cy: number, cz: number): { BasePart }
	local out = {}
	local cfg = B.bosses.LumenMaw
	for _, row in cfg.objectives.list do
		local a = math.rad(row.ring)
		local r = cfg.arenaRadius * 0.75
		local at = Vector3.new(cx + math.cos(a) * r, cy, cz + math.sin(a) * r)
		local base = part(
			folder,
			Vector3.new(10, 14, 10),
			CFrame.new(at + Vector3.new(0, 7, 0)),
			STEEL,
			Enum.Material.Metal
		)
		base:SetAttribute("Boss", true)
		local core = part(
			folder,
			Vector3.new(5, 5, 5),
			CFrame.new(at + Vector3.new(0, 16, 0)),
			LUMEN,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
		core.Name = "ObjectiveGlow"
		table.insert(out, core)
	end
	return out
end

---------------------------------------------------------------------------
-- The remade bosses (art/blender/bosses.py): meshes from ReplicatedStorage.Art.Bosses placed from Config.BossArt.
-- PLACEHOLDER LOOK: boss lore pending (generic neutral machines until each boss's story is decided)
---------------------------------------------------------------------------

local ART = Config.BossArt
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
	p.Parent = parent
	return p
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
		local at, parent: Instance = CFrame.new(), m
		if row.at then
			at = CFrame.new(row.at[1], row.at[2], row.at[3])
		else
			local a = math.rad(row.ring)
			local r = def.arenaRadius * 0.75
			at = CFrame.new(s.x + math.cos(a) * r, s.y, s.z + math.sin(a) * r)
			parent = folder
		end
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
				CombatFx.burst(p.Position, State.hero.fxStyle, SCRAP)
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
	if meshes then
		objectives = meshBoss(m, id, meshes, s)
		for _, p in m:GetChildren() do
			if p:GetAttribute("Role") == "weak" then
				table.insert(weak, p :: BasePart)
			end
		end
	elseif id == "RustjawPrime" then
		objectives = rustjaw(m)
	elseif id == "NullWarFrame" then
		objectives = warframe(m)
	elseif id == "LeviathanEngine" then
		objectives = leviathan(m)
	else
		maw(m)
		objectives = generators(s.x, s.y, s.z)
	end
	m.Parent = folder
	return {
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
		art = meshes ~= nil,
		phase = 0,
		weak = weak,
	}
end

local function destroy(sh: Shown)
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

local function frame(dt: number)
	local sh = shown
	if not sh then
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
	sh.model:PivotTo(CFrame.new(sh.x, sh.y + sh.lift, sh.z) * CFrame.Angles(0, sh.yaw, 0))
	if #sh.weak > 0 then
		-- the weak points pulse gold, the same on every boss ("hit the gold")
		local f = 0.5 + 0.5 * math.sin(os.clock() * ART.pulse * 2 * math.pi)
		local c = rgb(ART.weakColor[1]):Lerp(rgb(ART.weakColor[2]), f)
		for _, p in sh.weak do
			p.Color = c
		end
	end
end

---------------------------------------------------------------------------
-- Telegraphs and strikes
---------------------------------------------------------------------------

local function ground(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y + 0.2, z)
end

local function lineWarn(from: Vector3, dir: Vector3, length: number, width: number, t: number)
	local cf = CFrame.lookAt(from, from + dir) * CFrame.new(0, 0, -length / 2)
	local outline = part(folder, Vector3.new(width, 0.12, length), cf, WARN)
	outline.Transparency = 0.6
	local fill = part(
		folder,
		Vector3.new(width, 0.14, 0.5),
		CFrame.lookAt(from, from + dir) * CFrame.new(0, 0, -0.25),
		WARN
	)
	fill.Transparency = 0.35
	TweenService:Create(fill, TweenInfo.new(t, Enum.EasingStyle.Linear), {
		Size = Vector3.new(width, 0.14, length),
		CFrame = cf,
	}):Play()
	Debris:AddItem(outline, t + 0.05)
	Debris:AddItem(fill, t + 0.05)
end

local pullUntil, pullAt, pullR = 0, Vector3.zero, 0

local function warn(ev: { [string]: any })
	local t = ev.t or 1
	local c = ground(ev.x, ev.y, ev.z)
	if ev.shape == "ring" then
		CombatFx.warn(c, ev.r, t)
	elseif ev.shape == "cone" then
		CombatFx.warn(c, ev.r, t, ev.arc, ev.yaw)
	elseif ev.shape == "circles" then
		for _, p in ev.points or {} do
			CombatFx.warn(ground(p[1], ev.y, p[2]), ev.r, t)
		end
	elseif ev.shape == "lines" then
		for _, d in ev.points or {} do
			lineWarn(c, Vector3.new(d[1], 0, d[2]), ev.length, ev.width, t)
		end
	elseif ev.shape == "pull" then
		CombatFx.warn(c, ev.nova, t)
		pullUntil, pullAt, pullR = os.clock() + t, c, ev.r
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
	if ev.shape == "ring" or ev.shape == "cone" then
		CombatFx.slam(c, ev.r)
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
			CombatFx.slam(at, 60)
			if near(at, 500) then
				CameraController.shake(1.2, 1.6)
			end
		end)
	elseif ev.k == "phase" and s then
		local top = s.model:GetPivot().Position + Vector3.new(0, B.bosses[s.id].height * 0.7, 0)
		CombatFx.nova(top, 40, style, WARN, true)
		CombatFx.banner(string.format("PHASE %d!", ev.phase), WARN, style)
		Juice.fire("bossPhase", top, { mine = near(top, 500) })
	elseif ev.k == "dead" and s then
		-- it falls apart: plates and bolts everywhere, then it sinks
		local pivot = s.model:GetPivot()
		Juice.fire("bossDefeated", pivot.Position)
		for i = 1, 6 do
			task.delay(i * 0.25, function()
				local h = B.bosses[s.id].height
				CombatFx.burst(
					pivot.Position
						+ Vector3.new(math.random(-20, 20), math.random(10, h), math.random(-20, 20)),
					style,
					SCRAP
				)
			end)
		end
		CombatFx.banner("BOSS DEFEATED!", Color3.fromRGB(255, 200, 60), style)
		for _, p in s.model:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = p.CFrame - Vector3.new(0, 30, 0),
					Transparency = 1,
				}):Play()
			end
		end
		shown = nil
		task.delay(3.2, function()
			destroy(s)
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

---------------------------------------------------------------------------
-- Event looks
---------------------------------------------------------------------------

local water: Part? = nil
local dim: ColorCorrectionEffect? = nil

local function inDistrict(name: string): boolean
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local d = Config.City.districts[name]
	if not root then
		return false
	end
	local p = root.Position
	return p.X >= d.minX and p.X <= d.maxX and p.Z >= d.minZ and p.Z <= d.maxZ
end

local function eventStep()
	local surge, blackout = nil, nil
	for _, ev in WorldClient.events do
		if ev.id == "TidalSurge" and ev.state == 0 then
			surge = ev
		elseif ev.id == "Blackout" and ev.state == 0 then
			blackout = ev
		end
	end
	if surge then
		local def = Config.Events.events.TidalSurge
		local d = Config.City.districts.Docks
		local gy = Config.City.ground.y
		if not water then
			water = part(
				folder,
				Vector3.new(d.maxX - d.minX, 1, d.maxZ - d.minZ),
				CFrame.new((d.minX + d.maxX) / 2, gy - 1, (d.minZ + d.maxZ) / 2),
				Color3.fromRGB(60, 140, 200),
				Enum.Material.Glass
			)
			water.Name = "SurgeWater"
		end
		local w = water :: Part
		w.Transparency = 0.45
		local f = math.clamp(1 - (surge.ends - os.clock()) / def.length, 0, 1)
		-- it rises over the first half and holds; the more citizens saved, the lower it sits
		local saved = if surge.need > 0 then surge.have / surge.need else 0
		local h = def.rise * math.min(1, f * 2) * (1 - saved * 0.5)
		w.CFrame = CFrame.new(w.Position.X, gy - 0.5 + h / 2, w.Position.Z)
		w.Size = Vector3.new(w.Size.X, math.max(0.2, h), w.Size.Z)
	elseif water then
		water:Destroy()
		water = nil
	end
	local dark = blackout ~= nil and inDistrict("OldTown")
	if dark and not dim then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "Blackout"
		c.Brightness = 0
		c.Parent = Lighting
		dim = c
	end
	if dim then
		local want = if dark then -0.18 - 0.05 * (4 - ((blackout and blackout.have) or 0)) / 4 else 0
		dim.Brightness += (want - dim.Brightness) * 0.2
		dim.Saturation = dim.Brightness
		if not dark and math.abs(dim.Brightness) < 0.01 then
			dim:Destroy()
			dim = nil
		end
	end
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
	local acc = 0
	RunService.RenderStepped:Connect(FrameProf.wrap("WorldFx", function(dt)
		frame(dt)
		pullStep(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			eventStep()
		end
	end))
end

return WorldFx
