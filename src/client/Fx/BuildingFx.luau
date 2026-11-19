-- BuildingFx: draws hub destruction on the device (spec: World > Destruction; the server stores only each
-- building's state, clients draw the rest).
-- * Building states come from BuildingSnapshot (asked for once the listeners are up) and 2 Hz BuildingDiff
--   batches. Each wreckable building is a model named Building_<id> under Workspace.City; it can stream in
--   and out, so its look is applied whenever it arrives.
-- * Damaged (Red Faction-style, nate 2026-11-16): the real body hides and stops colliding on this device,
--   and the building's Structure pieces (corner pillars, wall panels, floor slabs: Shared.Structure) stand in
--   its place with every knocked-out piece missing, so the holes are real: you can see and fly inside.
--   Pieces knocked out live fly off as loose physics debris (the device's debris budget, then they fade);
--   pieces that lose their support (a storey giving way and everything above it) drop in a shaking
--   pancake fall into dust. The server sends which pieces went (BuildingDiff c, snapshot g).
-- * Collapsed: a 6 s collapse (a shake, then what is left of the building drops storey by storey into a
--   dust cloud) leaves the rubble heap. Joining late shows the heap at once.
-- * Repair drones fly to their building and hover over it while they work; the building pops back whole.
-- * BuildingImpact: a crater where a slam or landing hits the ground, facade cracks where a blast hits a wall
--   (outskirts houses and the Foundry crack too but never fall). Craters and cracks share the device
--   preset's crater count and last 30 s; loose chunks share the debris budget.
-- * Audit fixes (2026-11-18): snapshots and diffs go through BuildingState.applySnapshot and applyDiff (a repair in
--   a batch clears the old holes before that batch's new ones), at most the preset's `falling` pieces animate at
--   once, and a building streaming out drops its saved collision flags.
-- * The street breaks too (2026-11-19, nate: "more destruction everywhere"): every BuildingImpact knocks the street
--   things in reach loose on this device (the kit's street props through CityProps.smash, and the city's own
--   trees, fences, awnings and roof props), up to the preset's `smash` count and the debris budget; each comes
--   back after Config.Destruction.street.respawn seconds. The outskirts buildings' boxes come in the snapshot (o).
-- * Craters and cracks wear comic ink decals (Config.Destruction.decals, art/fx/textures.py --destruction) once their
--   ids are in; with id 0 a crater is today's dark disc and a crack today's thin dark bars.
-- PLACEHOLDER ART: chunks, rubble and drones are plain boxes. Dust wears the effects library's smoke sheet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Chunker = require(Shared:WaitForChild("Chunker"))
local BuildingState = require(Shared:WaitForChild("BuildingState"))
local Structure = require(Shared:WaitForChild("Structure"))
local FxPlan = require(Shared:WaitForChild("FxPlan"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CityProps = require(script.Parent.Parent.Controllers.CityProps)
local Juice = require(script.Parent.Juice)
local DebrisBudget = require(script.Parent.DebrisBudget)

local BuildingFx = {}

local D = Config.Destruction
-- the collapse's dust cloud wears the effects library's uploaded smoke sheet (a 4x4 flipbook) since gap-fx3
-- (2026-11-19), Roblox's built-in smoke while its id is 0
local DUST_TEXTURE, DUST_FLIP = FxPlan.textureOf(Config.Fx.lib, "smoke")
local CRACK_COLOR = Color3.fromRGB(34, 32, 36)
local DRONE_COLOR = Color3.fromRGB(255, 196, 64)
local DRONE_LIGHT = Color3.fromRGB(120, 230, 255)

type Rec = { id: number, x: number, z: number, sx: number, sz: number, base: number, top: number }
type Drawn = { state: number, model: Model, parts: { [number]: BasePart }? }
type Fall = {
	id: number,
	t0: number,
	parts: { { part: BasePart, from: CFrame, delay: number, drop: number, tilt: Vector3 } },
	dust: BasePart?,
	done: boolean,
	own: Model?, -- a storey giving way: the falling pieces live here and go when the fall ends
}

local records: { [number]: Rec } = {}
local state: { [number]: number } = {}
local models: { [number]: Model } = {}
local drawn: { [number]: Drawn } = {}
local falls: { Fall } = {}
local marks: { BasePart | Model } = {}
local drones: { [number]: { model: Model, conn: RBXScriptConnection? } } = {}
local liveDust = 0
local liveFall = 0 -- pieces animating in falls now (the preset's `falling` cap)
local grids: { [number]: Structure.Grid } = {}
local gone: { [number]: { [number]: boolean } } = {} -- building id -> pieces knocked out or fallen
local bodyFlags: { [BasePart]: { collide: boolean, query: boolean } } = {}
local folder: Folder
local synced = false

local function newPart(
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	variant: string?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	if variant and variant ~= "" then
		p.MaterialVariant = variant -- a city kit building's texture (Config.City.kit)
	end
	return p
end

-- The colour, material and material variant of a building's biggest part (its body)
local function bodyLook(model: Model?): (Color3, Enum.Material, string)
	local best, bestV = nil, 0
	if model then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				local v = p.Size.X * p.Size.Y * p.Size.Z
				if v > bestV then
					best, bestV = p, v
				end
			end
		end
	end
	if best then
		return best.Color, best.Material, best.MaterialVariant
	end
	return Color3.fromRGB(170, 160, 150), Enum.Material.Concrete, ""
end

-- Hide the real body on this device; hidden, it also stops colliding here so the holes are real. keepCrown: a
-- skyscraper's crown parts (attribute Crown: setbacks, spire, lantern) stay while its top storey stands
local function setHidden(model: Model?, hiddenAll: boolean, keepCrown: boolean?)
	if not model then
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local hidden = hiddenAll and not (keepCrown and p:GetAttribute("Crown") == true)
			p.LocalTransparencyModifier = if hidden then 1 else 0
			if hidden then
				if not bodyFlags[p] then
					bodyFlags[p] = { collide = p.CanCollide, query = p.CanQuery }
				end
				p.CanCollide = false
				p.CanQuery = false
			elseif bodyFlags[p] then
				p.CanCollide = bodyFlags[p].collide
				p.CanQuery = bodyFlags[p].query
				bodyFlags[p] = nil
			end
		end
	end
end

local function gridOf(rec: Rec): Structure.Grid
	local g = grids[rec.id]
	if not g then
		g = Structure.build(D, rec)
		grids[rec.id] = g
	end
	return g
end

local function clearDrawn(id: number)
	local d = drawn[id]
	if d then
		d.model:Destroy()
		drawn[id] = nil
	end
	for _, f in falls do
		if f.id == id and not f.own then
			f.done = true
		end
	end
end

-- A slight per-chunk shade so the stand-in reads as broken blocks, not one box
local function shade(color: Color3, i: number): Color3
	local k = ((i * 37) % 7) / 7
	return color:Lerp(Color3.new(0, 0, 0), 0.04 + k * 0.1)
end

-- The building as Structure pieces, without the ones in skip. Returns the model and its parts by piece.
local function drawStructure(rec: Rec, skip: { [number]: boolean }): (Model, { [number]: BasePart })
	local color, material, variant = bodyLook(models[rec.id])
	local m = Instance.new("Model")
	m.Name = "Wreck_" .. rec.id
	m:SetAttribute("WreckOf", rec.id) -- a ram into these pieces is a ram into the building (MoveController)
	local parts: { [number]: BasePart } = {}
	for i, c in gridOf(rec).pieces do
		if not skip[i] then
			local p = newPart(
				Vector3.new(c.sx - 0.05, c.sy - 0.05, c.sz - 0.05),
				CFrame.new(c.cx, c.cy, c.cz),
				if c.kind == "pillar" then color:Lerp(Color3.new(0, 0, 0), 0.18) else shade(color, i),
				material,
				if c.kind == "wall" then variant else nil -- a kit front keeps its windows on the wall panels
			)
			p.CanCollide = true
			p.CanQuery = true
			p.CastShadow = c.kind ~= "slab"
			p.Parent = m
			parts[i] = p
		end
	end
	return m, parts
end

local function drawRubble(rec: Rec): Model
	local color, material = bodyLook(models[rec.id])
	local m = Instance.new("Model")
	m.Name = "Rubble_" .. rec.id
	for i, r in Chunker.rubble(D, rec, rec.id) do
		local p = newPart(
			Vector3.new(r.sx, r.sy, r.sz),
			CFrame.new(r.cx, r.cy, r.cz) * CFrame.Angles(math.rad(r.rx), math.rad(r.ry), math.rad(r.rz)),
			shade(color:Lerp(Color3.fromRGB(90, 86, 82), 0.35), i),
			material
		)
		p.CanCollide = true
		p.Parent = m
	end
	return m
end

-- A piece knocked out: it flies off as loose physics debris (within the debris budget, else it just goes)
local function knockOut(rec: Rec, part: BasePart, from: Vector3?)
	if DebrisBudget.lease(1, D.structure.debrisLife) == 0 then
		part:Destroy()
		return
	end
	part.Anchored = false
	part.CanQuery = false
	local out = part.Position - (from or Vector3.new(rec.x, part.Position.Y, rec.z))
	out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(1, 0, 0)
	part.AssemblyLinearVelocity = out * (18 + math.random() * 16) + Vector3.new(0, 10 + math.random() * 8, 0)
	part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		* 6
	part.Parent = folder
	task.delay(D.structure.debrisLife - 1, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(1), { Transparency = 1 }):Play()
		end
	end)
	task.delay(D.structure.debrisLife, function()
		part:Destroy()
	end)
end

local function dustCloud(rec: Rec, seconds: number): BasePart?
	if liveDust >= QualityController.preset.emitters then
		return nil
	end
	liveDust += 1
	local p = newPart(
		Vector3.new(rec.sx + 8, 2, rec.sz + 8),
		CFrame.new(rec.x, rec.base + 1, rec.z),
		Color3.new(1, 1, 1)
	)
	p.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = DUST_TEXTURE
	if DUST_FLIP == 4 then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
	e.Shape = Enum.ParticleEmitterShape.Box
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new(Color3.fromRGB(196, 186, 172))
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 18) })
	e.Lifetime = NumberRange.new(2.5, 4)
	e.Speed = NumberRange.new(6, 14)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Rate = 24
	e.Drag = 1.5
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Parent = p
	p.Parent = folder
	task.delay(seconds, function()
		e.Enabled = false
	end)
	task.delay(seconds + 4, function()
		liveDust -= 1
		p:Destroy()
	end)
	return p
end

local function nearMe(x: number, z: number, r: number): boolean
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (Vector3.new(x, root.Position.Y, z) - root.Position).Magnitude < r
end

-- A pancake fall: the pieces shake, then drop storey by storey (lowest first) into dust. own: the model
-- holding pieces that broke off a standing building (a storey that gave way); nil for a full collapse.
local function pancake(rec: Rec, list: { { part: BasePart, piece: Structure.Piece } }, own: Model?)
	local grid = gridOf(rec)
	local fall: Fall = { id = rec.id, t0 = os.clock(), parts = {}, dust = nil, done = false, own = own }
	local fallTime = D.collapseTime - 1.2
	local lowest = math.huge
	for _, e in list do
		lowest = math.min(lowest, e.piece.storey)
	end
	local floor = rec.base
	local cap = QualityController.preset.falling or 600
	for _, e in list do
		if liveFall >= cap then
			-- over the device's cap (many storeys falling at once): this piece just goes, in the dust
			e.part:Destroy()
			continue
		end
		liveFall += 1
		e.part.CanCollide = false
		e.part.CanQuery = false
		local c = e.piece
		table.insert(fall.parts, {
			part = e.part,
			from = e.part.CFrame,
			delay = (if own then 0.3 else 0.8)
				+ (c.storey - lowest) / math.max(grid.storeys, 1) * fallTime * 0.35,
			drop = c.cy - floor + c.sy * 0.5,
			tilt = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.9,
		})
	end
	fall.dust = dustCloud(rec, if own then 2.5 else D.collapseTime)
	table.insert(falls, fall)
end

-- Draw a building's look for its state. live: the change just happened (animate it). fresh: pieces that
-- just went (piece -> 1 knocked out, 2 fell), drawn first so they can fly or drop away.
local function apply(id: number, live: boolean, fresh: { [number]: number }?)
	local rec = records[id]
	local model = models[id]
	if not rec then
		return
	end
	local s = state[id] or 0
	local d = drawn[id]
	if not model then
		clearDrawn(id) -- streamed out: drawn again when it comes back
		return
	end
	if d and d.state == s and s ~= BuildingState.DAMAGED then
		setHidden(model, s ~= BuildingState.INTACT)
		return
	end
	if s == BuildingState.INTACT then
		clearDrawn(id)
		gone[id] = nil
		setHidden(model, false)
		if live then
			local pop = newPart(
				Vector3.new(rec.sx, rec.top - rec.base, rec.sz),
				CFrame.new(rec.x, (rec.base + rec.top) / 2, rec.z),
				DRONE_LIGHT,
				Enum.Material.Neon
			)
			pop.Transparency = 0.6
			pop.Parent = folder
			TweenService
				:Create(pop, TweenInfo.new(0.6), { Transparency = 1, Size = pop.Size + Vector3.new(4, 4, 4) })
				:Play()
			task.delay(0.7, function()
				pop:Destroy()
			end)
		end
		return
	end
	setHidden(model, true)
	local g = gone[id] or {}
	gone[id] = g
	if s == BuildingState.DAMAGED then
		-- draw (or keep) the standing pieces, with the fresh ones still in place so they can go live
		if not (d and d.state == s and d.parts) then
			clearDrawn(id)
			local skip = table.clone(g)
			for i in fresh or {} do
				skip[i] = nil
			end
			local m, parts = drawStructure(rec, skip)
			m.Parent = folder
			d = { state = s, model = m, parts = parts }
			drawn[id] = d
		end
		local parts = (d :: Drawn).parts :: { [number]: BasePart }
		local grid = gridOf(rec)
		local dropping: { { part: BasePart, piece: Structure.Piece } } = {}
		local own: Model? = nil
		local knocked = 0
		for i, cause in fresh or {} do
			local part = parts[i]
			parts[i] = nil
			if part then
				if not live then
					part:Destroy()
				elseif cause == 1 then
					knockOut(rec, part)
					knocked += 1
				else
					if not own then
						own = Instance.new("Model")
						own.Name = "Falling_" .. id;
						(own :: Model).Parent = folder
					end
					part.Parent = own
					table.insert(dropping, { part = part, piece = grid.pieces[i] })
				end
			end
		end
		if live and #dropping > 0 then
			pancake(rec, dropping, own)
			Juice.fire("collapse", Vector3.new(rec.x, rec.base, rec.z), { mine = nearMe(rec.x, rec.z, 80) })
			if nearMe(rec.x, rec.z, 250) then
				CameraController.shake(1.6, 0.5)
			end
		elseif live and knocked > 0 and nearMe(rec.x, rec.z, 120) then
			CameraController.shake(0.15, 0.25)
		end
		-- a skyscraper keeps its crown up while every piece of the shaft's top storey stands
		local topStands = true
		for i in g do
			if grid.pieces[i] and grid.pieces[i].storey == grid.storeys then
				topStands = false
				break
			end
		end
		setHidden(model, true, topStands)
		return
	end
	-- Collapsed
	if not live then
		clearDrawn(id)
		local m = drawRubble(rec)
		m.Parent = folder
		drawn[id] = { state = s, model = m }
		return
	end
	-- what is left of the building comes down (a full set of pieces if it was never drawn broken)
	local m, parts
	if d and d.parts then
		m, parts = d.model, d.parts
		d.state = s
	else
		clearDrawn(id)
		m, parts = drawStructure(rec, g)
		m.Parent = folder
		drawn[id] = { state = s, model = m, parts = parts }
	end
	local grid = gridOf(rec)
	local list = {}
	for i, p in parts do
		table.insert(list, { part = p, piece = grid.pieces[i] })
	end
	pancake(rec, list, nil)
	gone[id] = nil
	Juice.fire("collapse", Vector3.new(rec.x, rec.base, rec.z), { mine = nearMe(rec.x, rec.z, 80) })
	if nearMe(rec.x, rec.z, 250) then
		CameraController.shake(D.collapseTime * 0.5, 0.6)
	end
end

local function stepFalls()
	local now = os.clock()
	local fallTime = D.collapseTime - 1.2
	for i = #falls, 1, -1 do
		local f = falls[i]
		local t = now - f.t0
		local length = if f.own then 3 else D.collapseTime
		if not f.done then
			for _, c in f.parts do
				if t < c.delay then
					-- the shake before it goes
					local j = (1 - t / c.delay) * 0.15 + 0.1
					c.part.CFrame = c.from
						* CFrame.new((math.random() - 0.5) * j, 0, (math.random() - 0.5) * j)
				else
					local k = math.clamp((t - c.delay) / (fallTime * 0.65), 0, 1)
					local eased = k * k
					c.part.CFrame = (c.from - Vector3.new(0, c.drop * eased, 0))
						* CFrame.Angles(c.tilt.X * eased, 0, c.tilt.Z * eased)
				end
			end
		end
		if f.done or t >= length then
			table.remove(falls, i)
			liveFall = math.max(0, liveFall - #f.parts)
			if f.own then
				f.own:Destroy()
			elseif not f.done then
				local d = drawn[f.id]
				if d and d.state == BuildingState.COLLAPSED then
					d.model:Destroy()
					local rec = records[f.id]
					local m = drawRubble(rec)
					m.Parent = folder
					drawn[f.id] = { state = d.state, model = m }
				end
			end
		end
	end
end

-- Craters and cracks share the preset's crater count
local function addMark(m: BasePart | Model)
	m.Parent = folder
	table.insert(marks, m)
	while #marks > QualityController.preset.craters do
		local old = table.remove(marks, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(D.crater.life, function()
		local i = table.find(marks, m)
		if i then
			table.remove(marks, i)
		end
		m:Destroy()
	end)
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local city = Workspace:FindFirstChild("City")
	params.FilterDescendantsInstances = if city then { city } else {}
	return params
end

-- A frame at pos whose UpVector is the surface normal
local function surface(pos: Vector3, normal: Vector3): CFrame
	local side = normal:Cross(Vector3.zAxis)
	if side.Magnitude < 0.1 then
		side = normal:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(pos, side.Unit, normal.Unit)
end

local function crater(center: Vector3, radius: number)
	Juice.fire("crater", center, { mine = false })
	local hit =
		Workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(0, -(radius + 24), 0), rayParams())
	if not hit then
		return
	end
	local r = math.clamp(radius * 0.6, D.crater.radius * 0.6, D.crater.radius * 2)
	local m = Instance.new("Model")
	m.Name = "Crater"
	local up = surface(hit.Position, hit.Normal)
	local ink = D.decals and D.decals.crater
	if ink and ink.id ~= 0 then
		-- the comic crater decal, turned a random way, on an unseen plate just over the ground
		local w = r * ink.span
		local plate = newPart(
			Vector3.new(w, 0.05, w),
			up * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, math.random() * math.pi * 2, 0),
			CRACK_COLOR
		)
		plate.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Texture = "rbxassetid://" .. tostring(ink.id)
		decal.Face = Enum.NormalId.Top
		decal.Parent = plate
		plate.Parent = m
	else
		local pit = newPart(
			Vector3.new(0.12, r * 2, r * 2),
			up * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)),
			CRACK_COLOR,
			Enum.Material.Slate
		)
		pit.Shape = Enum.PartType.Cylinder
		pit.Transparency = 0.25
		pit.Parent = m
	end
	local color = if hit.Instance:IsA("BasePart") then hit.Instance.Color else Color3.fromRGB(120, 116, 110)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2 + math.random() * 0.3
		local s = r * (0.25 + math.random() * 0.2)
		local rock = newPart(
			Vector3.new(s, s * 0.5, s * 0.8),
			up
				* CFrame.new(math.cos(a) * r, s * 0.15, math.sin(a) * r)
				* CFrame.Angles(math.random() - 0.5, a, math.random() - 0.5),
			color:Lerp(CRACK_COLOR, 0.25),
			Enum.Material.Slate
		)
		rock.Parent = m
	end
	addMark(m)
end

-- A zigzag crack drawn flat on a wall at a ray hit
local function crackAt(hit: RaycastResult, size: number)
	local m = Instance.new("Model")
	m.Name = "Crack"
	local face = CFrame.lookAlong(hit.Position + hit.Normal * 0.06, -hit.Normal)
	local ink = D.decals and D.decals.crack
	if ink and ink.id ~= 0 then
		-- the comic crack decal on an unseen plate flat on the wall (its back face looks out), turned a random way
		local w = size * ink.span
		local plate = newPart(
			Vector3.new(w, w, 0.05),
			face * CFrame.Angles(0, 0, math.random() * math.pi * 2),
			CRACK_COLOR
		)
		plate.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Texture = "rbxassetid://" .. tostring(ink.id)
		decal.Face = Enum.NormalId.Back
		decal.Parent = plate
		plate.Parent = m
		addMark(m)
		return
	end
	local function bar(a: Vector2, b: Vector2, w: number)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local ang = math.atan2(b.Y - a.Y, b.X - a.X)
		local p = newPart(
			Vector3.new(len, w, 0.05),
			face * CFrame.new(mid.X, mid.Y, 0) * CFrame.Angles(0, 0, ang),
			CRACK_COLOR,
			Enum.Material.Slate
		)
		p.Parent = m
	end
	for arm = 1, 4 do
		local a = arm / 4 * math.pi * 2 + math.random() * 0.8
		local from = Vector2.zero
		local steps = 3
		for s = 1, steps do
			local reach = size * s / steps
			local jitter = (math.random() - 0.5) * 0.7
			local to = Vector2.new(math.cos(a + jitter), math.sin(a + jitter)) * reach
			bar(from, to, 0.35 * (1 - (s - 1) / steps) + 0.1)
			from = to
		end
	end
	addMark(m)
end

local function cracks(center: Vector3, radius: number)
	local params = rayParams()
	local found = 0
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a)) * (radius + 8)
		local hit = Workspace:Raycast(center, dir, params)
		if hit and math.abs(hit.Normal.Y) < 0.5 then
			crackAt(hit, math.clamp(radius * 0.35, 2.5, 8))
			found += 1
			if found >= 3 then
				break
			end
		end
	end
end

-- A street piece knocked loose: a copy flies off as debris (the device's budget), the original stays hidden
local function fling(p: BasePart, center: Vector3)
	local ST = D.street
	if DebrisBudget.lease(1, ST.life) == 0 then
		return
	end
	local c = p:Clone()
	for _, ch in c:GetChildren() do
		if not (ch:IsA("SurfaceAppearance") or ch:IsA("SpecialMesh")) then
			ch:Destroy()
		end
	end
	c.Anchored = false
	c.CanCollide = true
	c.CanQuery = false
	c.CanTouch = false
	c.LocalTransparencyModifier = 0
	local out = Vector3.new(p.Position.X - center.X, 0, p.Position.Z - center.Z)
	out = if out.Magnitude > 0.1
		then out.Unit
		else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
	c.AssemblyLinearVelocity = out * ST.fling * (0.6 + math.random() * 0.6)
		+ Vector3.new(0, ST.fling * (0.4 + math.random() * 0.4), 0)
	c.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8
	c.Parent = folder
	task.delay(ST.life - 0.8, function()
		if c.Parent then
			TweenService:Create(c, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		end
	end)
	task.delay(ST.life, function()
		c:Destroy()
	end)
end

-- The city's own street things (server-built parts named "prop" outside any building model: trees, fences,
-- awnings, signs, crates) hidden on this device while they are "broken"
local streetDown: { [BasePart]: { collide: boolean, query: boolean } } = {}
local function smashStreet(center: Vector3, radius: number)
	local ST = D.street
	local r = math.max(ST.minRadius, radius * ST.radiusMult)
	local left = QualityController.preset.smash or 3
	left -= CityProps.smash(center, r, left, fling)
	local city = Workspace:FindFirstChild("City")
	if left <= 0 or not city then
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { city }
	params.MaxParts = 48
	for _, p in Workspace:GetPartBoundsInRadius(center, r, params) do
		if left <= 0 then
			break
		end
		local parent = p.Parent
		if
			p.Name == "prop"
			and not streetDown[p]
			and p.Transparency < 1
			and p.LocalTransparencyModifier < 1
			and p:GetAttribute("Tag") == nil
			and p.Size.Magnitude < 30
			and not (parent and parent:GetAttribute("BuildingId") ~= nil)
		then
			left -= 1
			fling(p, center)
			streetDown[p] = { collide = p.CanCollide, query = p.CanQuery }
			p.LocalTransparencyModifier = 1
			p.CanCollide = false
			p.CanQuery = false
			task.delay(ST.respawn, function()
				local f = streetDown[p]
				streetDown[p] = nil
				if f and p.Parent then
					p.LocalTransparencyModifier = 0
					p.CanCollide = f.collide
					p.CanQuery = f.query
				end
			end)
		end
	end
end

local function impact(center: Vector3, radius: number, kind: number)
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	if kind == 1 then
		crater(center, radius)
	end
	cracks(center, radius)
	smashStreet(center, radius)
end

-- Repair drones: fly in over the building and hover while working (PLACEHOLDER ART)
local function droneModel(): Model
	local m = Instance.new("Model")
	m.Name = "RepairDrone"
	local body = newPart(Vector3.new(2.4, 1.2, 2.4), CFrame.new(), DRONE_COLOR, Enum.Material.SmoothPlastic)
	body.Name = "Body"
	body.Parent = m
	m.PrimaryPart = body
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local rotor = newPart(
			Vector3.new(0.15, 1.6, 1.6),
			CFrame.new(s[1] * 1.6, 0.6, s[2] * 1.6) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(40, 42, 50)
		)
		rotor.Shape = Enum.PartType.Cylinder
		rotor.Transparency = 0.4
		rotor.Parent = m
	end
	local eye = newPart(Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, -0.7, 0), DRONE_LIGHT, Enum.Material.Neon)
	eye.Shape = Enum.PartType.Ball
	eye.Parent = m
	local beam = newPart(Vector3.new(0.4, 1, 0.4), CFrame.new(0, -1, 0), DRONE_LIGHT, Enum.Material.Neon)
	beam.Name = "Beam"
	beam.Transparency = 0.5
	beam.Parent = m
	return m
end

local function droneJob(droneId: number, bid: number, seconds: number)
	local old = drones[droneId]
	if old then
		if old.conn then
			old.conn:Disconnect()
		end
		old.model:Destroy()
		drones[droneId] = nil
	end
	local rec = records[bid]
	if not rec or seconds <= 0 or not nearMe(rec.x, rec.z, QualityController.preset.streamRadius) then
		return
	end
	local m = droneModel()
	m.Parent = folder
	local job = { model = m, conn = nil :: RBXScriptConnection? }
	drones[droneId] = job
	local t0 = os.clock()
	local hoverY = rec.top + 10
	local start = Vector3.new(rec.x + 120, hoverY + 60, rec.z + 40)
	local beam = m:FindFirstChild("Beam") :: BasePart
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local root = (m.PrimaryPart :: BasePart).CFrame
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p ~= beam then
			table.insert(parts, p)
			table.insert(offsets, root:ToObjectSpace(p.CFrame))
		end
	end
	job.conn = RunService.RenderStepped:Connect(FrameProf.wrap("BuildingFx", function()
		local t = os.clock() - t0
		local pos: Vector3
		if t < 2 then
			local k = t / 2
			pos = start:Lerp(Vector3.new(rec.x, hoverY, rec.z), 1 - (1 - k) ^ 2)
		elseif t < seconds then
			local a = t * 0.8 + droneId
			local r = math.min(rec.sx, rec.sz) * 0.35
			pos =
				Vector3.new(rec.x + math.cos(a) * r, hoverY + math.sin(t * 2) * 0.6, rec.z + math.sin(a) * r)
		else
			pos = Vector3.new(rec.x, hoverY + (t - seconds) * 30, rec.z)
		end
		local cf = CFrame.new(pos) * CFrame.Angles(0, t * 0.5, 0)
		for i, p in parts do
			p.CFrame = cf * offsets[i]
		end
		local working = t >= 2 and t < seconds
		local len = if working then pos.Y - rec.top else 0.1
		beam.Size = Vector3.new(0.4, math.max(len, 0.1), 0.4)
		beam.CFrame = CFrame.new(pos - Vector3.new(0, len / 2 + 0.5, 0))
		beam.Transparency = if working then 0.4 + math.sin(t * 10) * 0.15 else 1
		if t > seconds + 3 then
			if job.conn then
				job.conn:Disconnect()
			end
			m:Destroy()
			if drones[droneId] == job then
				drones[droneId] = nil
			end
		end
	end))
end

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("BuildingId")
	if type(id) ~= "number" then
		return
	end
	models[id] = model
	if synced then
		task.defer(apply, id, false)
	end
end

local function unregister(model: Instance)
	local id = model:GetAttribute("BuildingId")
	if type(id) == "number" and models[id] == model then
		models[id] = nil
		clearDrawn(id)
		-- streamed out: its parts go, and so do their saved flags (they come back as new parts)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				bodyFlags[p] = nil
			end
		end
	end
end

local function loadRecords(): boolean
	local value = ReplicatedStorage:FindFirstChild("WorldInfo")
	if not (value and value:IsA("StringValue") and value.Value ~= "") then
		return false
	end
	local ok, info = pcall(HttpService.JSONDecode, HttpService, value.Value)
	if not ok or type(info) ~= "table" or type(info.buildings) ~= "table" then
		return false
	end
	for _, row in info.buildings do
		records[row[1]] =
			{ id = row[1], x = row[2], z = row[3], sx = row[4], sz = row[5], base = row[6], top = row[7] }
	end
	return true
end

-- Building states right now (for the map and tests)
function BuildingFx.state(id: number): number
	return state[id] or 0
end

function BuildingFx.init()
	folder = Instance.new("Folder")
	folder.Name = "CityFx"
	folder.Parent = Workspace
	local view = { state = state, gone = gone } -- this device's copy of the server's record (BuildingState)
	local function pieceCount(id: number): number?
		local rec = records[id]
		return if rec then #gridOf(rec).pieces else nil
	end
	local function known(id: any): boolean
		return type(id) == "number" and records[id] ~= nil
	end
	Net.listen("BuildingSnapshot", function(data: any)
		if type(data) ~= "table" or type(data.s) ~= "buffer" then
			return
		end
		-- the outskirts buildings' boxes come with the snapshot (2026-11-19: too many for WorldInfo)
		if type(data.o) == "buffer" and type(data.o1) == "number" and data.o1 >= 1 then
			for id, rec in BuildingState.unpackBoxes(data.o, data.o1, 4096) do
				records[id] = rec
			end
		end
		-- the states and the pieces gone from each Damaged building; holes from earlier batches are dropped
		BuildingState.applySnapshot(view, data, pieceCount)
		for id in models do
			clearDrawn(id) -- drawn again below from the snapshot
		end
		synced = true
		for id in models do
			apply(id, false)
		end
		for _, job in data.dr or {} do
			droneJob(job[1], job[2], job[3])
		end
	end)
	Net.listen("BuildingDiff", function(data: any)
		if type(data) ~= "table" then
			return
		end
		-- repairs first (their old holes go, even when hit again in this batch), then pieces (so a building
		-- turning Damaged is drawn with its holes), then states
		local touched, fresh, reset = BuildingState.applyDiff(view, data, known)
		for id in reset do
			clearDrawn(id)
		end
		if synced then
			for id in touched do
				apply(id, true, fresh[id])
			end
		end
		for _, job in data.dr or {} do
			droneJob(job[1], job[2], job[3])
		end
	end)
	Net.listen("BuildingImpact", impact)
	RunService.Heartbeat:Connect(FrameProf.wrap("BuildingFx", stepFalls))
	task.spawn(function()
		while not loadRecords() do
			task.wait(0.5)
		end
		local city = Workspace:WaitForChild("City")
		city.DescendantAdded:Connect(register)
		city.DescendantRemoving:Connect(unregister)
		for _, m in city:GetDescendants() do
			register(m)
		end
		Net.send("BuildingSync")
	end)
end

return BuildingFx
