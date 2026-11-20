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
-- Knocked-out pillars and slabs fly as broken blocks and wall panels spit broken bits (Art.Rubble chunks, 2026-11-20);
-- rubble heaps are Art.Rubble heaps and drones the Fix-It Drone's look. Dust wears the effects library's smoke sheet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Chunker = require(Shared:WaitForChild("Chunker"))
local BuildingState = require(Shared:WaitForChild("BuildingState"))
local Structure = require(Shared:WaitForChild("Structure"))
local FxPlan = require(Shared:WaitForChild("FxPlan"))
local StreetBreak = require(Shared:WaitForChild("StreetBreak"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CityProps = require(script.Parent.Parent.Controllers.CityProps)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local Juice = require(script.Parent.Juice)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local DebrisBudget = require(script.Parent.DebrisBudget)
local FxLib = require(script.Parent.FxLib)
local PowerMeshes = require(script.Parent.PowerMeshes)

local BuildingFx = {}
-- set by Fx.CityLife (the living world, 2026-11-19): every impact this device hears (center, radius, kind; kind 9
-- is a building coming down)
BuildingFx.onImpact = nil :: ((Vector3, number, number) -> ())?

local D = Config.Destruction
local GROUND_CRATERS = D.ground ~= nil and D.ground.on == true
-- the collapse's dust cloud wears the effects library's uploaded smoke sheet (a 4x4 flipbook) since gap-fx3
-- (2026-11-19), Roblox's built-in smoke while its id is 0
local DUST_TEXTURE, DUST_FLIP = FxPlan.textureOf(Config.Fx.lib, "smoke")
local CRACK_COLOR = Color3.fromRGB(34, 32, 36)
local DRONE_COLOR = Color3.fromRGB(255, 196, 64)
local DRONE_LIGHT = Color3.fromRGB(120, 230, 255)

type Rec = {
	id: number,
	x: number,
	z: number,
	sx: number,
	sz: number,
	base: number,
	top: number,
	round: boolean?,
}
type Drawn = {
	state: number,
	model: Model,
	parts: { [number]: BasePart }?,
	edges: { [number]: { BasePart } }?, -- torn edges by seam (on * 65536 + to)
}
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

-- the plain kit texture a kit building's pillars, slabs and rubble wear (Config.City.kit.wreck)
local WRECK_KIT: string? = Config.City.kit and Config.City.kit.wreck
local WRECK_MAT: Enum.Material = if WRECK_KIT
	then (Enum.Material :: any)[Config.City.kit.baseMaterial[WRECK_KIT]]
	else Enum.Material.Concrete

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
		if p:IsA("Decal") or p:IsA("Texture") then
			-- a sign, poster or face decal on a hidden part goes with it (nate 2026-11-19: "they keep showing
			-- after the building is destroyed"); a part's LocalTransparencyModifier does not reach its decals
			local host = p.Parent
			local hidden = hiddenAll
				and not (keepCrown and host and host:IsA("BasePart") and host:GetAttribute("Crown") == true)
			p.LocalTransparencyModifier = if hidden then 1 else 0
		elseif p:IsA("SurfaceGui") or p:IsA("BillboardGui") then
			local host = p.Parent
			local hidden = hiddenAll
				and not (keepCrown and host and host:IsA("BasePart") and host:GetAttribute("Crown") == true)
			if hidden and p:GetAttribute("WasOn") == nil then
				p:SetAttribute("WasOn", p.Enabled)
				p.Enabled = false
			elseif not hidden and p:GetAttribute("WasOn") ~= nil then
				p.Enabled = p:GetAttribute("WasOn") == true
				p:SetAttribute("WasOn", nil)
			end
		elseif p:IsA("BasePart") then
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
-- each drawn piece's kind (pillar, wall, slab), for what it breaks into when knocked out
local pieceKind: { [BasePart]: string } = setmetatable({}, { __mode = "k" }) :: any

local function drawStructure(rec: Rec, skip: { [number]: boolean }): (Model, { [number]: BasePart })
	local color, material, variant = bodyLook(models[rec.id])
	-- pillars and slabs of a kit building wear the kit's plain concrete (pt-ui 2026-11-19: they showed the front's
	-- bare base material in its white, so a damaged building looked untextured)
	local inner, innerMat = "", material
	if variant ~= "" and WRECK_KIT then
		inner, innerMat = "Kit" .. WRECK_KIT, WRECK_MAT
	end
	local m = Instance.new("Model")
	m.Name = "Wreck_" .. rec.id
	m:SetAttribute("WreckOf", rec.id) -- a ram into these pieces is a ram into the building (MoveController)
	local parts: { [number]: BasePart } = {}
	for i, c in gridOf(rec).pieces do
		if not skip[i] then
			-- a round body's pieces stand on its circle (Structure.roundOff: turned chords, the slab a disc)
			local size = Vector3.new(c.sx - 0.05, c.sy - 0.05, c.sz - 0.05)
			local cf = CFrame.new(c.cx, c.cy, c.cz)
			if c.disc then
				size = Vector3.new(c.sy - 0.05, (c.dw or c.sx) - 0.05, (c.dd or c.sz) - 0.05)
				cf *= CFrame.Angles(0, 0, math.rad(90))
			elseif c.ry then
				size = Vector3.new((c.dw or c.sx) - 0.05, c.sy - 0.05, (c.dd or c.sz) - 0.05)
				cf *= CFrame.Angles(0, math.rad(c.ry), 0)
			end
			local p = newPart(
				size,
				cf,
				if c.kind == "pillar" then color:Lerp(Color3.new(0, 0, 0), 0.18) else shade(color, i),
				if c.kind == "wall" then material else innerMat,
				if c.kind == "wall" then variant else inner -- a kit front keeps its windows on the wall panels
			)
			p.CanCollide = true
			p.CanQuery = true
			p.CastShadow = c.kind ~= "slab"
			if c.disc then
				p.Shape = Enum.PartType.Cylinder
			end
			p.Parent = m
			parts[i] = p
			pieceKind[p] = c.kind
		end
	end
	return m, parts
end

-- The rubble heaps' meshes (ReplicatedStorage.Art.Rubble), found once; all eight or none (the boxes stay)
local rubbleFound: { [string]: MeshPart } = {}
local function rubbleSource(name: string): MeshPart?
	local hit = rubbleFound[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Rubble")
	local src = set and set:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		rubbleFound[name] = src
		return src
	end
	return nil
end
local function rubbleReady(): boolean
	for heap, row in Config.RubbleArt do
		for name, v in row do
			if type(v) == "table" and name ~= "box" and not rubbleSource(name) then
				return false
			end
		end
		if not rubbleSource(heap) then
			return false
		end
	end
	return true
end

-- The destruction kit's torn edges (list-combat 2026-11-20; Tasks "Destruction (M5)": the pieces still standing were
-- clean boxes beside every hole). Each standing piece that touched a knocked-out one (Shared.Structure.seams) shows a
-- broken concrete lip with bent rebar along that seam (Art.Rubble Torn1-2), in the inner kit concrete. The lips are
-- looks only (no collision or queries); they go with their piece and come back with a redraw. Nil until the Rubble
-- meshes are imported (the holes keep their clean box edges then).
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
local function tornEdge(seam: Structure.Seam, like: BasePart, into: Instance): { BasePart }
	local T = D.structure.torn
	local out: { BasePart } = {}
	local nrm = AXES[seam.n] * seam.sign
	local along = AXES[seam.along]
	local n = math.max(1, math.floor(seam.len / T.seg + 0.5))
	local L = seam.len / n
	local P = math.min(T.reach, seam.thick * T.share)
	local th = seam.thick * 0.92
	local at = Vector3.new(seam.at[1], seam.at[2], seam.at[3])
	local color = like.Color:Lerp(Color3.fromRGB(90, 86, 82), 0.4)
	for k = 1, n do
		local name = "Torn" .. ((seam.on + seam.to + k) % 2 + 1)
		local row = Config.RubbleArt[name]
		local scale = Vector3.new(L, P, th) / Vector3.new(row.box[1], row.box[2], row.box[3])
		local x = if k % 2 == 0 then -along else along -- every other one turned round, so they do not repeat
		local cf = CFrame.fromMatrix(at + along * ((k - 0.5) * L - seam.len / 2) + nrm * (P / 2), x, nrm)
		for _, piece in { name, name .. "Rebar" } do
			local a = row[piece]
			local src = rubbleSource(piece)
			if not src then
				continue
			end
			local p = MeshFix.clone(src)
			p:ClearAllChildren()
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			local size = Vector3.new(a.size[1], a.size[2], a.size[3])
			if piece == name then
				p.Size = size * scale
				p.Color = color
				p.Material = WRECK_MAT
				p.MaterialVariant = if WRECK_KIT and like.MaterialVariant ~= ""
					then "Kit" .. WRECK_KIT
					else ""
			else
				p.Size = size * Vector3.new(1, scale.Y, 1) -- the bars grow longer, never fatter
				p.Color = Color3.fromRGB(a.color[1], a.color[2], a.color[3])
				p.Material = Enum.Material.Metal
			end
			p.CFrame = cf
				* CFrame.new(Vector3.new(a.offset[1], a.offset[2], a.offset[3]) * scale)
				* MeshFix.of(p)
			p.Parent = into
			table.insert(out, p)
		end
	end
	return out
end

-- Bring a damaged building's torn edges up to date with what is gone: lips on standing pieces beside gone ones, none
-- on pieces that went; at most the preset's `torn` seams a building
local function tear(rec: Rec, d: Drawn, g: { [number]: boolean })
	local parts = d.parts
	if not parts then
		return
	end
	local edges = d.edges or {}
	d.edges = edges
	local count = 0
	for key, list in edges do
		if parts[key // 65536] and g[key % 65536] then
			count += 1
		else
			for _, p in list do
				p:Destroy()
			end
			edges[key] = nil
		end
	end
	local most = QualityController.preset.torn or 0
	if count >= most or not rubbleReady() then
		return
	end
	local seams = Structure.seams(gridOf(rec))
	local ids = {}
	for j in g do
		table.insert(ids, j)
	end
	table.sort(ids) -- the same lips every time for the same holes
	for _, j in ids do
		for _, seam in seams[j] or {} do
			local key = seam.on * 65536 + j
			local like = parts[seam.on]
			if like and not edges[key] then
				edges[key] = tornEdge(seam, like, d.model)
				count += 1
				if count >= most then
					return
				end
			end
		end
	end
end

local function untear(d: Drawn?)
	if d and d.edges then
		for _, list in d.edges do
			for _, p in list do
				p:Destroy()
			end
		end
		d.edges = nil
	end
end

local function drawRubble(rec: Rec): Model
	local color, material, variant = bodyLook(models[rec.id])
	local inner = ""
	if variant ~= "" and WRECK_KIT then
		inner, material = "Kit" .. WRECK_KIT, WRECK_MAT -- a kit building's rubble in the kit's concrete (pt-ui)
	end
	local m = Instance.new("Model")
	m.Name = "Rubble_" .. rec.id
	local heaps = rubbleReady()
	for i, r in Chunker.rubble(D, rec, rec.id) do
		local cf = CFrame.new(r.cx, r.cy, r.cz)
			* CFrame.Angles(math.rad(r.rx), math.rad(r.ry), math.rad(r.rz))
		if heaps then
			-- item 291: a heap of broken slabs, lumps and rebar (art/blender/rubble.py) stretched to the same box
			local name = "Rubble" .. ((rec.id + i) % 4 + 1)
			local row = Config.RubbleArt[name]
			local k = Vector3.new(r.sx, r.sy, r.sz) / Vector3.new(row.box[1], row.box[2], row.box[3])
			for _, piece in { name, name .. "Rebar" } do
				local a = row[piece]
				local src = rubbleSource(piece)
				if src then
					local p = MeshFix.clone(src)
					p:ClearAllChildren()
					p.Anchored = true
					p.Size = Vector3.new(a.size[1], a.size[2], a.size[3]) * k
					p.CFrame = cf
						* CFrame.new(Vector3.new(a.offset[1], a.offset[2], a.offset[3]) * k)
						* MeshFix.of(p)
					if piece == name then
						p.Color = shade(color:Lerp(Color3.fromRGB(90, 86, 82), 0.35), i)
						p.Material = material
						p.MaterialVariant = inner
						p.CanCollide = true
					else
						p.Color = Color3.fromRGB(a.color[1], a.color[2], a.color[3])
						p.Material = Enum.Material.Metal
						p.CanCollide = false
						p.CanQuery = false
					end
					p.CanTouch = false
					p.Parent = m
				end
			end
			continue
		end
		local p = newPart(
			Vector3.new(r.sx, r.sy, r.sz),
			cf,
			shade(color:Lerp(Color3.fromRGB(90, 86, 82), 0.35), i),
			material,
			inner
		)
		p.CanCollide = true
		p.Parent = m
	end
	return m
end

local ramPush: Vector3? = nil -- set while a predicted ram's pieces are knocked out (BuildingFx.predict)

-- Throw one loose piece off the building (out from the hit, or ahead of a ramming hero), fading out after
-- debrisLife; a bit (a torn-off chunk off a wall) flies a little faster and spins harder
local function throwPiece(rec: Rec, part: BasePart, from: Vector3?, bit: boolean)
	part.Anchored = false
	part.CanQuery = false
	local out = part.Position - (from or Vector3.new(rec.x, part.Position.Y, rec.z))
	out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(1, 0, 0)
	local push = ramPush
	if push then
		-- a hero flying through: the pieces go ahead of it, the way it travels, and never block it for a moment
		out = (push + out * 0.35).Unit
		part.CanCollide = false
		task.delay(0.35, function()
			if part.Parent then
				part.CanCollide = true
			end
		end)
	end
	local fast = if bit then 1.4 else 1
	part.AssemblyLinearVelocity = out * (18 + math.random() * 16) * fast
		+ Vector3.new(0, 10 + math.random() * 8, 0)
	part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		* (if bit then 14 else 6)
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

-- A broken block (Art.Rubble Chunk1-3, list-combat 2026-11-20) in a box's place: the same size, colour, material
-- and kit texture, its corners and one face knocked off. Nil until the meshes are imported (the box stays).
local function chunkMesh(name: string, size: Vector3, cf: CFrame, like: BasePart): MeshPart?
	if not rubbleReady() then
		return nil
	end
	local src = rubbleSource(name)
	if not src then
		return nil
	end
	local p = MeshFix.clone(src)
	p:ClearAllChildren()
	p.Anchored = true
	p.Size = size -- one mesh filling its own box: stretched to the piece's box
	p.CFrame = cf * MeshFix.of(p)
	p.Color = like.Color
	p.Material = like.Material
	p.MaterialVariant = like.MaterialVariant
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = like.CastShadow
	return p
end

-- What a knocked-out piece throws (Tasks "Destruction (M5)": chunks were plain boxes): a pillar or slab becomes a
-- broken block of the same size; a wall panel keeps its front (windows and all) and spits a few broken concrete
-- bits off its torn edge (Config.Destruction.structure.bits, inside the debris budget)
local function breakUp(rec: Rec, part: BasePart): { BasePart }
	local out: { BasePart } = { part }
	if part:IsA("Part") and part.Shape ~= Enum.PartType.Block then
		return out -- a round body's disc slab stays a disc
	end
	local seed = rec.id * 7 + math.floor(math.abs(part.Position.X + part.Position.Z))
	if pieceKind[part] ~= "wall" then
		local mesh = chunkMesh("Chunk" .. (seed % 3 + 1), part.Size, part.CFrame, part)
		if mesh then
			mesh.CanQuery = part.CanQuery
			mesh.Parent = part.Parent
			pieceKind[part] = nil
			part:Destroy()
			out[1] = mesh
		end
		return out
	end
	local B = D.structure.bits
	if not B or B.count <= 0 then
		return out
	end
	local n = DebrisBudget.lease(B.count, D.structure.debrisLife)
	local size = part.Size
	local small = math.min(size.X, size.Y, size.Z)
	for k = 1, n do
		local s =
			math.clamp(small * (B.size[1] + (B.size[2] - B.size[1]) * ((seed + k * 5) % 7) / 6), 0.4, B.most)
		local edge = part.CFrame
			* CFrame.new(
				(math.random() - 0.5) * size.X * 0.8,
				(if k % 2 == 0 then 0.5 else -0.5) * size.Y * 0.9,
				(math.random() - 0.5) * size.Z * 0.8
			)
		local bit = chunkMesh(
			"Chunk" .. ((seed + k) % 3 + 1),
			Vector3.new(s, s * 0.8, s * 1.1),
			edge * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			part
		)
		if not bit then
			break
		end
		bit.MaterialVariant = if WRECK_KIT then "Kit" .. WRECK_KIT else ""
		bit.Material = WRECK_MAT
		bit.Color = part.Color:Lerp(Color3.fromRGB(90, 86, 82), 0.4)
		bit.Parent = part.Parent
		table.insert(out, bit)
	end
	return out
end

-- A piece knocked out: it flies off as loose physics debris (within the debris budget, else it just goes)
local function knockOut(rec: Rec, part: BasePart, from: Vector3?)
	if DebrisBudget.lease(1, D.structure.debrisLife) == 0 then
		part:Destroy()
		return
	end
	for i, piece in breakUp(rec, part) do
		throwPiece(rec, piece, from, i > 1)
	end
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
-- pt-city (2026-11-19): what stands on a building that breaks (its billboard, water tower, antenna, roof units,
-- awnings: parts with the Falls attribute, CityBuilder's street art) is flung off as debris the moment it first
-- breaks; a water tower's tank bursts in a splash. Set below, once fling is defined.
local roofFall: (model: Model, rec: Rec) -> () = function() end
local fallen: { [number]: boolean } = {}

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
		fallen[id] = nil
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
	if live and not fallen[id] then
		fallen[id] = true
		roofFall(model, rec)
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
		local knockAt: Vector3? = nil
		for i, cause in fresh or {} do
			local part = parts[i]
			parts[i] = nil
			if part then
				if not live then
					part:Destroy()
				elseif cause == 1 then
					knockAt = knockAt or part.Position
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
		if live and knocked > 0 and #dropping == 0 and knockAt then
			-- the wall's own crunch where the pieces burst out, louder the more went (list-combat 2026-11-20)
			AudioController.play("wallSmash", knockAt, { volume = math.min(1, 0.45 + 0.12 * knocked) })
		end
		tear(rec, d :: Drawn, g)
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
	untear(drawn[id]) -- the torn edges go with the pieces they stood on
	local grid = gridOf(rec)
	local list = {}
	for i, p in parts do
		table.insert(list, { part = p, piece = grid.pieces[i] })
	end
	pancake(rec, list, nil)
	gone[id] = nil
	Juice.fire("collapse", Vector3.new(rec.x, rec.base, rec.z), { mine = nearMe(rec.x, rec.z, 80) })
	local hook = BuildingFx.onImpact
	if hook then
		task.spawn(hook, Vector3.new(rec.x, rec.base, rec.z), math.max(rec.sx, rec.sz), 9)
	end
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

-- A chip (BuildingImpact kind 4): a basic hit on a wall that has not knocked a piece out yet still shows: dust and
-- chips burst off the face in the wall's own colour, a small crack mark where it landed and a soft crunch
local function chipAt(center: Vector3, radius: number)
	local params = rayParams()
	local best: RaycastResult? = nil
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local hit = Workspace:Raycast(center, Vector3.new(math.cos(a), 0, math.sin(a)) * (radius + 3), params)
		if hit and math.abs(hit.Normal.Y) < 0.5 and (not best or hit.Distance < best.Distance) then
			best = hit
		end
	end
	local at = if best then best.Position else center
	local normal = if best then best.Normal else Vector3.yAxis
	local color = if best then best.Instance.Color else Color3.fromRGB(150, 146, 138)
	FxLib.emit("dust", color, at + normal * 0.4, 6, normal)
	FxLib.emit("chip", color, at + normal * 0.3, 5, normal)
	if best then
		crackAt(best, 1.6)
	end
	AudioController.play("wallSmash", at, { volume = 0.35, pitch = 1.5 })
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
		if ch:IsA("Decal") or ch:IsA("Texture") then
			ch.LocalTransparencyModifier = 0 -- a sign's words fall with its board
		elseif ch:IsA("SurfaceGui") then
			ch.Enabled = ch:GetAttribute("WasOn") ~= false
			ch:SetAttribute("WasOn", nil)
		elseif not (ch:IsA("SurfaceAppearance") or ch:IsA("SpecialMesh")) then
			ch:Destroy()
		end
	end
	c.Anchored = false
	-- a big flung piece (a bandshell's shell, a bridge deck) flies through things: no shove on heroes (destroy-all)
	c.CanCollide = math.max(c.Size.X, c.Size.Y, c.Size.Z) <= (ST.collideMax or math.huge)
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

roofFall = function(model: Model, rec: Rec)
	local splash = 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Falls") == true and p.LocalTransparencyModifier < 1 then
			-- off the roof's edge, outward from the building's middle
			fling(p, Vector3.new(rec.x, p.Position.Y - 6, rec.z))
			if p:GetAttribute("Burst") == true and splash < 2 then
				splash += 1
				FxLib.burst(p.Position, 8, "Tide", Color3.fromRGB(120, 190, 235))
			end
		end
	end
end

-- The city's own street things (server-built parts named "prop" outside any building model: trees, fences,
-- awnings, signs, crates, containers, hay, poles) hidden on this device while they are "broken". fix-destroy
-- (2026-11-19, nate: "I literally want everything destructible"): bigger things go too (Shared.StreetBreak: up to
-- 32 studs tall and 20 across, so containers and windmill poles), and a long fence or wall breaks only where it was
-- hit: it is drawn as short stand-in lengths on this device and the ones in reach fly off.
local streetDown: { [BasePart]: { collide: boolean, query: boolean, segs: Model? } } = {}

local function hideStreet(p: BasePart, segs: Model?)
	streetDown[p] = { collide = p.CanCollide, query = p.CanQuery, segs = segs }
	p.LocalTransparencyModifier = 1
	p.CanCollide = false
	p.CanQuery = false
	for _, ch in p:GetChildren() do
		if ch:IsA("Decal") or ch:IsA("Texture") then
			ch.LocalTransparencyModifier = 1
		elseif ch:IsA("SurfaceGui") and ch.Enabled then
			ch.Enabled = false -- a park gate's name goes with its sign (destroy-all)
			ch:SetAttribute("StreetOff", true)
		end
	end
	task.delay(D.street.respawn, function()
		local f = streetDown[p]
		streetDown[p] = nil
		if f then
			if f.segs then
				f.segs:Destroy()
			end
			if p.Parent then
				p.LocalTransparencyModifier = 0
				p.CanCollide = f.collide
				p.CanQuery = f.query
				for _, ch in p:GetChildren() do
					if ch:IsA("Decal") or ch:IsA("Texture") then
						ch.LocalTransparencyModifier = 0
					elseif ch:IsA("SurfaceGui") and ch:GetAttribute("StreetOff") then
						ch.Enabled = true
						ch:SetAttribute("StreetOff", nil)
					end
				end
			end
		end
	end)
end

-- Dressed looks (destroy-all, 2026-11-20, nate: "destroy EVERYTHING"; Shared.StreetBreak.parkDress/deepDress): the
-- park's structures and the Deep's coral are Blender meshes over hidden collision boxes, all carrying one Dress key a
-- look. A knock on any of its boxes flings every visible piece and hides the whole group on this device; it stands
-- again after the street's respawn. Index: key -> parts under the look's folder (the Park, the Deep), kept as chunks
-- stream in (a part streamed out is dropped; it comes back whole).
local dressIndex: { [Instance]: { [string]: { BasePart } } } = {}
local function dressParts(p: BasePart, key: string): { BasePart }
	local chunk = p.Parent
	local root = chunk and chunk.Parent
	if not root then
		return { p }
	end
	local idx = dressIndex[root]
	if not idx then
		local made: { [string]: { BasePart } } = {}
		idx = made
		dressIndex[root] = made
		local function add(d: Instance)
			if d:IsA("BasePart") then
				local k = d:GetAttribute("Dress")
				if type(k) == "string" then
					local list = made[k]
					if not list then
						list = {}
						made[k] = list
					end
					table.insert(list, d)
				end
			end
		end
		for _, d in root:GetDescendants() do
			add(d)
		end
		root.DescendantAdded:Connect(add)
	end
	local out: { BasePart } = {}
	local list = (idx :: any)[key] or {}
	for i = #list, 1, -1 do
		local q = list[i]
		if q.Parent == nil then
			table.remove(list, i)
		else
			table.insert(out, q)
		end
	end
	if #out == 0 then
		table.insert(out, p)
	end
	return out
end

BuildingFx.lastBig = false -- the last dressed look this device broke was a big one (MoveController's hit-stop)
local function breakDress(p: BasePart, key: string, center: Vector3, heavy: boolean): boolean
	local big = p:GetAttribute("DressBig") == true
	if big and not heavy then
		return false -- a bandshell or a bridge takes a heavy hit or a ram
	end
	local parts = dressParts(p, key)
	local mid, n = Vector3.zero, 0
	local color = p.Color
	for _, q in parts do
		if not streetDown[q] then
			if q.Transparency < 1 and q.LocalTransparencyModifier < 1 then
				color = q.Color
				fling(q, center)
			end
			hideStreet(q, nil)
			mid += q.Position
			n += 1
		end
	end
	if n == 0 then
		return false
	end
	mid /= n
	BuildingFx.lastBig = big
	-- the weight of it: chips and dust in its colour (the effects library), a crunch for a big one
	FxLib.throwMoment("smash", mid, color, Vector3.yAxis, if big then 6 else 2)
	if big then
		AudioController.play("wallSmash", mid, { volume = 0.9, pitch = 0.8 })
		if nearMe(mid.X, mid.Z, 70) then
			CameraController.shake(0.25, 0.4)
		end
	end
	return true
end

-- A long thin street part broken at `center`: short lengths stand in for it, the ones within r fly
local function breakLong(p: BasePart, center: Vector3, r: number): number
	local plan = StreetBreak.segments(
		{ x = p.Position.X, y = p.Position.Y, z = p.Position.Z, sx = p.Size.X, sy = p.Size.Y, sz = p.Size.Z },
		{ x = center.X, y = center.Y, z = center.Z },
		r,
		D.street.segment
	)
	if not plan then
		return 0
	end
	local segs = Instance.new("Model")
	segs.Name = "StreetBits"
	local flew = 0
	for _, sg in plan do
		local c = newPart(
			Vector3.new(sg.sx, sg.sy, sg.sz),
			CFrame.new(sg.x, sg.y, sg.z) * (p.CFrame - p.CFrame.Position),
			p.Color,
			p.Material,
			p.MaterialVariant
		)
		c.CanCollide = p.CanCollide
		c.CanQuery = p.CanQuery
		if p:GetAttribute("Picket") == true then
			-- a picket fence's lengths wear its picture too (the living world, 2026-11-19)
			c.Transparency = 1
			for _, tex in p:GetChildren() do
				if tex:IsA("Texture") then
					tex:Clone().Parent = c
				end
			end
		end
		if sg.broken then
			fling(c, center)
			c:Destroy()
			flew += 1
		else
			c.Parent = segs
		end
	end
	segs.Parent = folder
	hideStreet(p, segs)
	return flew
end

local function smashStreet(center: Vector3, radius: number, only: BasePart?, heavyIn: boolean?): number
	local ST = D.street
	local r = math.max(ST.minRadius, radius * ST.radiusMult)
	local max = QualityController.preset.smash or 3
	local left = max
	left -= CityProps.smash(center, r, left, fling)
	local city = Workspace:FindFirstChild("City")
	if left <= 0 or not city then
		return max - left
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { city }
	params.MaxParts = 48
	local list = Workspace:GetPartBoundsInRadius(center, r, params)
	if only then
		table.insert(list, 1, only)
	end
	local heavy = heavyIn == true or only ~= nil or radius >= (ST.bigRadius or math.huge)
	for _, p in list do
		if left <= 0 then
			break
		end
		local parent = p.Parent
		local dress = p:GetAttribute("Dress")
		if type(dress) == "string" then
			if
				not streetDown[p]
				and p.LocalTransparencyModifier < 1
				and breakDress(p, dress, center, heavy)
			then
				left -= 1
			end
		elseif
			p.Name == "prop"
			and not streetDown[p]
			and (p.Transparency < 1 or p:GetAttribute("Picket") == true) -- a picket fence's box is hidden behind its picture
			and p.LocalTransparencyModifier < 1
			and p:GetAttribute("Tag") == nil
			and not (parent and parent:GetAttribute("BuildingId") ~= nil)
		then
			local kind = StreetBreak.kind(p.Size.X, p.Size.Y, p.Size.Z)
			if kind == "whole" then
				left -= 1
				fling(p, center)
				hideStreet(p, nil)
			elseif kind == "long" then
				left -= 1
				breakLong(p, center, r)
			end
		end
	end
	return max - left
end

-- Knock the street things round `at` loose on this device (a ram through a tree or a fence); how many went
function BuildingFx.smashAt(at: Vector3, radius: number, part: BasePart?): number
	return smashStreet(at, radius, part)
end

-- A heavy hit on open water (BuildingImpact kind 5, destroy-all 2026-11-20): a crown of spray and a ring off the
-- surface (the effects library's Tide burst, inside the particle budget) and the splash sound
local function splash(center: Vector3, radius: number)
	local size = math.clamp(radius, 4, 14)
	FxLib.burst(center + Vector3.new(0, 0.5, 0), size, "Tide", Color3.fromRGB(205, 232, 250), radius >= 8)
	FxLib.throwMoment("land", center, Color3.fromRGB(236, 246, 255), Vector3.yAxis, size * 1.4)
	AudioController.play("splash", center, { volume = math.clamp(0.5 + radius / 20, 0.5, 1), pitch = 0.8 })
end

local function impact(center: Vector3, radius: number, kind: number)
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	local hook = BuildingFx.onImpact
	if hook then
		task.spawn(hook, center, radius, kind) -- the living world: pigeons, cars, manholes, news drones (Fx.CityLife)
	end
	if kind == 3 then
		smashStreet(center, radius, nil, true) -- a hero went through a street thing (ImpactProp): a ram, so heavy
		return
	end
	if kind == 5 then
		splash(center, radius) -- a heavy hit on the sea (CraterService, destroy-all)
		return
	end
	if kind == 4 then
		chipAt(center, radius) -- a hit on a wall that breaks nothing yet (list-combat 2026-11-20)
		return
	end
	if kind == 1 and not GROUND_CRATERS then
		crater(center, radius) -- (the server's ground craters draw their own since fix-destroy: GroundFx)
	end
	cracks(center, radius)
	smashStreet(center, radius)
end

-- Repair drones: fly in over the building and hover while working: the Fix-It Drone's look, a textured energy beam
-- down to the roof and weld sparks where it lands (2026-11-20; the part box before Art.Powers is imported)
-- A heavy landing on this device only (the intro film's hero: Fx.IntroFilm): the crater, the cracks and the street
-- things knocked loose, as a server ground hit draws them
function BuildingFx.landing(center: Vector3, radius: number)
	crater(center, radius)
	cracks(center, radius)
	smashStreet(center, radius)
end

local function droneModel(): Model
	local m = Instance.new("Model")
	m.Name = "RepairDrone"
	if PowerMeshes.ready("Drone") then
		-- item 290: the Fix-It Drone's Blender look (art/blender/powers.py) in the repair crews' colours
		for _, pc in PowerMeshes.pieces("Drone", CFrame.identity, DRONE_LIGHT, 1.3) do
			local p = PowerMeshes.make(pc, m)
			if p and pc[7] == "DroneBody" then
				p.Color = DRONE_COLOR
				p.Name = "Body"
				m.PrimaryPart = p
			end
		end
		local beam = newPart(Vector3.new(0.4, 1, 0.4), CFrame.new(0, -1, 0), DRONE_LIGHT, Enum.Material.Neon)
		beam.Name = "Beam"
		beam.Transparency = 0.5
		beam.Parent = m
		if m.PrimaryPart then
			return m
		end
		m:ClearAllChildren()
	end
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
	-- the repair beam: the energy strip texture between the beam part's ends (the part itself stays clear)
	local EB = Config.Fx.energyBeam
	local ray: Beam? = nil
	local a0 = Instance.new("Attachment")
	a0.Parent = beam
	local a1 = Instance.new("Attachment")
	a1.Parent = beam
	if EB and (EB.texture or 0) ~= 0 then
		local b = Instance.new("Beam")
		b.Name = "RepairRay"
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.Width0, b.Width1 = 0.6, 1.4
		b.Texture = "rbxassetid://" .. EB.texture
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = EB.tile
		b.TextureSpeed = -EB.speed -- flowing down to the roof
		b.LightEmission = 1
		b.Brightness = 2
		b.Color = ColorSequence.new(DRONE_LIGHT)
		b.Transparency = NumberSequence.new(0.15)
		b.Enabled = false
		b.Parent = beam
		ray = b
	end
	local lastSpark = 0
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
		a0.Position = Vector3.new(0, len / 2, 0)
		a1.Position = Vector3.new(0, -len / 2, 0)
		if ray then
			ray.Enabled = working
			beam.Transparency = 1
		else
			beam.Transparency = if working then 0.4 + math.sin(t * 10) * 0.15 else 1
		end
		if working and t - lastSpark > 0.3 then
			lastSpark = t
			FxLib.emit(
				"spark",
				DRONE_LIGHT,
				Vector3.new(pos.X, rec.top + 0.3, pos.Z),
				3,
				Vector3.new(0, 1, 0)
			)
		end
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
		records[row[1]] = {
			id = row[1],
			x = row[2],
			z = row[3],
			sx = row[4],
			sz = row[5],
			base = row[6],
			top = row[7],
			round = row[8] == 1,
		}
	end
	return true
end

-- Flying through (fix-destroy, 2026-11-19, nate: "I want to fly straight through buildings"): a ram opens its hole on
-- this device at once, the same blast the server runs (Structure.blast at the same point, radius and damage), so the
-- hero never stops at a wall waiting for the 2 Hz diff. The server's pieces confirm it; a piece it never confirms
-- (the server said no, or picked another) comes back after `hold` seconds.
type Pending = {
	untilT: number,
	pieces: { [number]: boolean },
	confirmed: { [number]: boolean },
	prev: number,
	server: number?,
}
local pending: { [number]: Pending } = {}
local PREDICT_HOLD = 1.5

-- hold: how long the hole stays before an unconfirmed guess heals (the intro film keeps its hole for the film)
function BuildingFx.predict(id: number, at: Vector3, dmg: number, radius: number, hold: number?): number
	local rec = records[id]
	if not rec or not models[id] or (state[id] or 0) == BuildingState.COLLAPSED or dmg <= 0 then
		return 0
	end
	local px = math.clamp(at.X, rec.x - rec.sx / 2, rec.x + rec.sx / 2)
	local pz = math.clamp(at.Z, rec.z - rec.sz / 2, rec.z + rec.sz / 2)
	local py = math.clamp(at.Y, rec.base + 1, rec.top)
	local g = gone[id] or {}
	gone[id] = g
	local hit = Structure.blast(D, gridOf(rec), g, px, py, pz, radius, dmg)
	if #hit == 0 then
		return 0
	end
	local p = pending[id]
	if not p then
		p = { untilT = 0, pieces = {}, confirmed = {}, prev = state[id] or 0, server = nil }
		pending[id] = p
	end
	p.untilT = math.max(p.untilT, os.clock() + (hold or PREDICT_HOLD))
	local fresh = {}
	for _, i in hit do
		p.pieces[i] = true
		fresh[i] = 1
	end
	state[id] = BuildingState.DAMAGED
	local travel = MoveController.velocity
	ramPush = if travel.Magnitude > 1 then travel.Unit else nil
	apply(id, true, fresh)
	ramPush = nil
	return #hit
end

-- What a diff batch says about predicted buildings (before it is applied)
local function confirm(data: any)
	if next(pending) == nil then
		return
	end
	for _, id in data.r or {} do
		pending[id] = nil
	end
	local c = data.c or {}
	for i = 1, #c - 2, 3 do
		local p = pending[c[i]]
		if p and type(c[i + 1]) == "number" then
			p.confirmed[c[i + 1]] = true
		end
	end
	local d = data.d or {}
	for i = 1, #d - 1, 2 do
		local p = pending[d[i]]
		if p and type(d[i + 1]) == "number" then
			p.server = d[i + 1]
		end
	end
end

-- Predicted pieces the server never confirmed come back (the building redrawn from the server's copy)
local function reconcile()
	local now = os.clock()
	for id, p in pending do
		if now >= p.untilT then
			pending[id] = nil
			local back = false
			local g = gone[id]
			for i in p.pieces do
				if not p.confirmed[i] and g then
					g[i] = nil
					back = true
				end
			end
			if back then
				if next(p.confirmed) == nil and p.server == nil then
					state[id] = p.prev
				end
				clearDrawn(id)
				apply(id, false)
			end
		end
	end
end

-- Street things a ram goes through (MoveController.onPropHit): knocked loose on this device and told to the server,
-- which passes the knock on to the players near (BuildingImpact), so everyone sees the tree go
local propSent = 0
-- set by ImpactFx: the smash's juice (crunch, shake, chips) when a ram goes through a vehicle or a dressed look
BuildingFx.onPropSmash = nil :: ((Vector3, Color3, number) -> ())?

-- The vehicle a part belongs to (VehicleService's models carry VehicleId)
local function vehicleOf(part: Instance): Model?
	local m = part.Parent
	while m and m ~= Workspace do
		if m:IsA("Model") and m:GetAttribute("VehicleId") ~= nil then
			return m
		end
		m = m.Parent
	end
	return nil
end

-- destroy-all (2026-11-20): a ram into a car, truck or tram goes through it: the body stops colliding on this device
-- for a moment (the hero keeps its line) and the server, which checks the hero's own speed, flips it (ImpactProp)
local passing: { [Model]: boolean } = {}
local function ramVehicle(car: Model, part: BasePart, at: Vector3): boolean
	local ST = D.street
	if not passing[car] then
		passing[car] = true
		local off: { BasePart } = {}
		for _, q in car:GetDescendants() do
			if q:IsA("BasePart") and q.CanCollide then
				q.CanCollide = false
				table.insert(off, q)
			end
		end
		task.delay(ST.pass or 0.6, function()
			passing[car] = nil
			for _, q in off do
				q.CanCollide = true
			end
		end)
	end
	if os.clock() - propSent > 0.25 then
		propSent = os.clock()
		Net.send("ImpactProp", at)
	end
	MoveController.propStop = ST.bigStop or 0
	local hook = BuildingFx.onPropSmash
	if hook then
		hook(at, part.Color, 1)
	end
	return true
end

local function propHit(part: BasePart, at: Vector3, _speed: number): boolean
	local car = vehicleOf(part)
	if car then
		return ramVehicle(car, part, at)
	end
	BuildingFx.lastBig = false
	local n = BuildingFx.smashAt(at, 4, part)
	if n > 0 and os.clock() - propSent > 0.25 then
		propSent = os.clock()
		Net.send("ImpactProp", at)
	end
	if n > 0 and part:GetAttribute("Dress") ~= nil then
		-- a dressed look (a park structure, coral): a short hit-stop and the smash's juice, more for a big one
		local ST = D.street
		MoveController.propStop = if BuildingFx.lastBig then ST.bigStop or 0 else ST.propStop or 0
		local hook = BuildingFx.onPropSmash
		if hook then
			hook(at, part.Color, if BuildingFx.lastBig then 1 else ST.propSmash or 0.4)
		end
	end
	return n > 0
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
			for _, id in (if type(data.rd) == "table" then data.rd else {}) :: { any } do
				local rec = type(id) == "number" and records[id]
				if rec then
					rec.round = true
					grids[id] = nil
				end
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
		confirm(data)
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
	RunService.Heartbeat:Connect(FrameProf.wrap("BuildingFx", function()
		stepFalls()
		if next(pending) ~= nil then
			reconcile()
		end
	end))
	MoveController.onPropHit = propHit
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
