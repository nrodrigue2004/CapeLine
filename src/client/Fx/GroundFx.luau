-- GroundFx: the server's ground craters on this device (fix-destroy, 2026-11-19, nate: "even terrain";
-- CraterService, Shared.CraterRules). The city's ground is parts, so a part crater is drawn here over it: the comic
-- ink crater decal (Config.Destruction.decals.crater; id 0: a dark pit disc), a ring of broken rim chunks in the
-- ground's own colour and material (CraterRules.rim, the same ring on every device) and dark scorch. A terrain
-- crater's bowl is real (the server dug the voxels), so only its rim chunks are drawn. Healing: over the crater's last
-- `heal` seconds the rim sinks back into the ground and the decal fades; then it goes (CraterGone).
-- Budget: the preset's `craters` nearest the camera are drawn, `craterRim` chunks each (Config.Presets), anchored,
-- no collisions or queries; updated 4 times a second (FrameProf).
-- The rim chunks are the broken blocks of Art.Rubble (Chunk1-3, art/blender/rubble.py; 2026-11-20) stretched to each
-- chunk's box once they are imported; before that plain parts in the ground's colour (PLACEHOLDER ART).
-- Ground marks (2026-11-21, nate: "I'm still not noticing any terrain damage or craters"): the server's lighter marks
-- (wire tier 1 a dent, 2 a scorch; Config.Destruction.ground.marks) come on the same remotes. A scorch is the effects
-- library's uploaded scorch sheet laid flat (Config.Fx.lib.textures.scorch); a dent is the crater ink small, a dark
-- pit and the preset's markRim chips (a terrain dent's bowl is real: chips only). The preset's `marks` nearest within
-- marks.range studs are drawn (1 to 2 + markRim parts each); they fade out over their last `heal` seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CraterRules = require(Shared:WaitForChild("CraterRules"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local Juice = require(script.Parent.Juice)
local DebrisBudget = require(script.Parent.DebrisBudget)
local TweenService = game:GetService("TweenService")

local GroundFx = {}

local D = Config.Destruction
local G = D.ground
local M = G.marks
local SCORCH = Config.Fx.lib.textures.scorch and Config.Fx.lib.textures.scorch.id or 0
local PIT = Color3.fromRGB(38, 34, 36)

type Drawn = {
	model: Model,
	rim: { { part: BasePart, from: CFrame, drop: number } },
	ink: Decal?,
	see: number?, -- the ink's own transparency when whole (a scorch)
}

local function cfgOf(c: CraterRules.Crater): any
	return if (c.tier or 0) > 0 and M then M else G
end

local live: { [number]: CraterRules.Crater } = {} -- id -> crater (born on this device's clock)
local drawn: { [number]: Drawn } = {}
local folder: Folder

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
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
	p.Material = material
	return p
end

-- Art.Rubble's broken blocks (all three, or nil: the parts stay)
local chunkSrc: { MeshPart }? = nil
local function chunks(): { MeshPart }?
	if chunkSrc and chunkSrc[1].Parent then
		return chunkSrc
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Rubble")
	if not set then
		return nil
	end
	local out = {}
	for k = 1, 3 do
		local src = set:FindFirstChild("Chunk" .. k, true)
		if not (src and src:IsA("MeshPart")) then
			return nil
		end
		out[k] = src
	end
	chunkSrc = out
	return out
end

local function groundLook(c: CraterRules.Crater): (Color3, Enum.Material)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local city = Workspace:FindFirstChild("City")
	params.FilterDescendantsInstances = if city then { city, Workspace.Terrain } else { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(c.x, c.y + 3, c.z), Vector3.new(0, -8, 0), params)
	if hit and hit.Instance == Workspace.Terrain then
		-- Terrain: the material's own colour (the park's grass, the seabed's sand, destroy-all round 3)
		local ok, col = pcall(Workspace.Terrain.GetMaterialColor, Workspace.Terrain, hit.Material)
		return if ok then col else Color3.fromRGB(150, 130, 100), hit.Material
	end
	if hit and hit.Instance:IsA("BasePart") then
		return hit.Instance.Color, hit.Instance.Material
	end
	return Color3.fromRGB(150, 130, 100), Enum.Material.Slate
end

-- A scorch: one flat see-through plate with the scorch sheet on top
local function drawScorch(c: CraterRules.Crater): Drawn
	local m = Instance.new("Model")
	m.Name = "GroundMark_" .. c.id
	local w = c.r * 2.2
	local plate = part(
		Vector3.new(w, 0.05, w),
		CFrame.new(c.x, c.y + 0.06, c.z) * CFrame.Angles(0, (c.id * 1.37) % (math.pi * 2), 0),
		PIT,
		Enum.Material.SmoothPlastic
	)
	local ink: Decal? = nil
	if SCORCH ~= 0 then
		plate.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Texture = "rbxassetid://" .. tostring(SCORCH)
		decal.Face = Enum.NormalId.Top
		decal.Color3 = Color3.fromRGB(30, 26, 24)
		decal.Transparency = 0.1
		decal.Parent = plate
		ink = decal
	else
		-- no sheet: a soft dark disc (PLACEHOLDER ART)
		plate.Shape = Enum.PartType.Cylinder
		plate.Size = Vector3.new(0.05, w * 0.8, w * 0.8)
		plate.CFrame = CFrame.new(c.x, c.y + 0.06, c.z) * CFrame.Angles(0, 0, math.rad(90))
		plate.Transparency = 0.45
	end
	plate.Parent = m
	m.Parent = folder
	return { model = m, rim = {}, ink = ink, see = if ink then 0.1 else nil }
end

local function draw(c: CraterRules.Crater): Drawn
	if c.tier == CraterRules.TIER.scorch then
		return drawScorch(c)
	end
	local m = Instance.new("Model")
	m.Name = "GroundCrater_" .. c.id
	local color, material = groundLook(c)
	-- a crater dug deeper by more hits (destroy-all round 3): a wider, darker pit and a higher rim
	local deep = 1 + ((c.deep or 1) - 1) * 0.25
	local at = CFrame.new(c.x, c.y, c.z)
	local ink: Decal? = nil
	if c.ground ~= "terrain" then
		local deco = D.decals and D.decals.crater
		if deco and deco.id ~= 0 then
			local w = c.r * deco.span * 0.8
			local plate = part(
				Vector3.new(w, 0.05, w),
				at * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, (c.id * 1.37) % (math.pi * 2), 0),
				PIT,
				Enum.Material.SmoothPlastic
			)
			plate.Transparency = 1
			local decal = Instance.new("Decal")
			decal.Texture = "rbxassetid://" .. tostring(deco.id)
			decal.Face = Enum.NormalId.Top
			decal.Parent = plate
			plate.Parent = m
			ink = decal
		end
		-- the dark pit: reads as a hole in the paving
		local pit = part(
			Vector3.new(0.1, c.r * 1.5 * deep, c.r * 1.5 * deep),
			at * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
			PIT,
			Enum.Material.Slate
		)
		pit.Shape = Enum.PartType.Cylinder
		pit.Transparency = math.max(0, (if ink then 0.45 else 0.15) - (deep - 1) * 0.6)
		pit.Parent = m
	end
	local rim = {}
	local P = QualityController.preset :: any
	local nRim = if (c.tier or 0) > 0 then P.markRim or 3 else P.craterRim or 8
	for _, r in CraterRules.rim(c, nRim) do
		local cf = CFrame.new(r.x, r.y, r.z)
			* CFrame.Angles(0, math.rad(r.ry), 0)
			* CFrame.Angles(0, 0, math.rad(r.tilt))
		local size = Vector3.new(r.sx, r.sy * deep, r.sz)
		local src = chunks()
		local chunk: BasePart
		if src then
			local mp = MeshFix.clone(src[(c.id + #rim) % 3 + 1])
			mp:ClearAllChildren()
			mp.Anchored = true
			mp.CanCollide = false
			mp.CanQuery = false
			mp.CanTouch = false
			mp.Size = size -- one mesh filling its own box: stretched to the chunk's
			cf = cf * MeshFix.of(mp)
			mp.CFrame = cf
			mp.Color = color:Lerp(PIT, 0.2)
			mp.Material = material
			chunk = mp
		else
			chunk = part(size, cf, color:Lerp(PIT, 0.2), material)
		end
		chunk.CastShadow = true
		chunk.Parent = m
		table.insert(rim, { part = chunk, from = cf, drop = r.sy + 0.5 })
	end
	m.Parent = folder
	return { model = m, rim = rim, ink = ink }
end

-- A big slam throws up clods of the ground's own colour and material (destroy-all round 3): broken blocks (Art.Rubble,
-- else plain parts) flying up and out, bouncing and settling, then fading; the preset's collapse.clods within the
-- debris budget, only near the camera
local CLOD_PHYS = PhysicalProperties.new(2.2, 0.85, 0.28, 1, 1)
local function clods(c: CraterRules.Crater)
	local C = G.clods
	if not C or c.r < C.minR then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - Vector3.new(c.x, c.y, c.z)).Magnitude > C.range then
		return
	end
	local want = ((QualityController.preset.collapse or {}) :: any).clods or 0
	local n = DebrisBudget.lease(math.min(want, math.ceil(c.r / 2)), C.life)
	if n <= 0 then
		return
	end
	local color, material = groundLook(c)
	local src = chunks()
	for i = 1, n do
		local a = (i + math.random()) / n * math.pi * 2
		local s = c.r * (0.12 + math.random() * 0.12)
		local size = Vector3.new(s, s * 0.75, s * 1.1)
		local cf = CFrame.new(c.x + math.cos(a) * c.r * 0.4, c.y + s, c.z + math.sin(a) * c.r * 0.4)
			* CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		local p: BasePart
		if src then
			local mp = MeshFix.clone(src[i % 3 + 1])
			mp:ClearAllChildren()
			mp.Size = size
			mp.CFrame = cf * MeshFix.of(mp)
			p = mp
		else
			p = part(size, cf, color, material)
		end
		p.Color = color:Lerp(PIT, 0.15)
		p.Material = material
		p.Anchored = false
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = true
		p.CustomPhysicalProperties = CLOD_PHYS
		p.Parent = folder
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		p.AssemblyLinearVelocity = out * (C.out * (0.6 + math.random() * 0.6))
			+ Vector3.new(0, C.up * (0.7 + math.random() * 0.5), 0)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			* 10
		task.delay(C.life - 1, function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end)
		task.delay(C.life, function()
			p:Destroy()
		end)
	end
end

local function undraw(id: number)
	local d = drawn[id]
	if d then
		d.model:Destroy()
		drawn[id] = nil
	end
end

-- Keep the preset's nearest craters drawn and heal them
local function refresh()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local eye = cam.CFrame.Position
	local list, small = {}, {}
	local markRange = if M then M.range else 0
	for id, c in live do
		local d2 = (c.x - eye.X) ^ 2 + (c.z - eye.Z) ^ 2
		if (c.tier or 0) > 0 then
			if d2 < markRange * markRange then
				table.insert(small, { id = id, d = d2 })
			end
		elseif d2 < 600 * 600 then
			table.insert(list, { id = id, d = d2 })
		end
	end
	local function nearest(a, b)
		return a.d < b.d
	end
	table.sort(list, nearest)
	table.sort(small, nearest)
	local keep: { [number]: boolean } = {}
	for i = 1, math.min(#list, QualityController.preset.craters or 6) do
		keep[list[i].id] = true
	end
	for i = 1, math.min(#small, (QualityController.preset :: any).marks or 0) do
		keep[small[i].id] = true
	end
	for id in drawn do
		if not keep[id] then
			undraw(id)
		end
	end
	local now = os.clock()
	for id in keep do
		local c = live[id]
		local d = drawn[id]
		if not d then
			d = draw(c)
			drawn[id] = d
		end
		local h = CraterRules.healing(cfgOf(c), c, now)
		for _, r in d.rim do
			r.part.CFrame = r.from - Vector3.new(0, r.drop * h, 0)
		end
		if d.ink then
			local see = d.see or 0
			d.ink.Transparency = see + (1 - see) * h
		end
	end
end

local function fromWire(w: any): CraterRules.Crater?
	if type(w) ~= "table" or type(w[1]) ~= "number" then
		return nil
	end
	for i = 2, 5 do
		if type(w[i]) ~= "number" then
			return nil
		end
	end
	return {
		id = w[1],
		x = w[2],
		y = w[3],
		z = w[4],
		r = math.clamp(w[5], 1, 40),
		ground = if w[6] == 1 then "terrain" else "part",
		born = os.clock() - (tonumber(w[7]) or 0),
		deep = math.clamp(math.floor(tonumber(w[8]) or 1), 1, 6),
		tier = math.clamp(math.floor(tonumber(w[9]) or 0), 0, 2),
	}
end

function GroundFx.count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

function GroundFx.init()
	if not G or not G.on then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "GroundFx"
	folder.Parent = Workspace
	Net.listen("CraterState", function(list: any)
		if type(list) ~= "table" then
			return
		end
		for id in live do
			undraw(id)
		end
		table.clear(live)
		for _, w in list do
			local c = fromWire(w)
			if c then
				live[c.id] = c
			end
		end
	end)
	Net.listen("CraterAdd", function(w: any)
		local c = fromWire(w)
		if c then
			if live[c.id] then
				undraw(c.id) -- dug deeper (destroy-all round 3) or a mark grown: drawn again at its new size
			end
			live[c.id] = c
			if (c.tier or 0) == 0 then
				Juice.fire("crater", Vector3.new(c.x, c.y, c.z), { mine = false })
				clods(c)
			end
		end
	end)
	Net.listen("CraterGone", function(ids: any)
		for _, id in (if type(ids) == "table" then ids else {}) :: { any } do
			live[id] = nil
			undraw(id)
		end
	end)
	local last = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("GroundFx", function()
		local now = os.clock()
		if now - last >= 0.25 then
			last = now
			refresh()
		end
	end))
	Net.send("CraterSync")
end

return GroundFx
