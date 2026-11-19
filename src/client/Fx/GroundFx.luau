-- GroundFx: the server's ground craters on this device (fix-destroy, 2026-11-19, nate: "even terrain";
-- CraterService, Shared.CraterRules). The city's ground is parts, so a part crater is drawn here over it: the comic
-- ink crater decal (Config.Destruction.decals.crater; id 0: a dark pit disc), a ring of broken rim chunks in the
-- ground's own colour and material (CraterRules.rim, the same ring on every device) and dark scorch. A terrain
-- crater's bowl is real (the server dug the voxels), so only its rim chunks are drawn. Healing: over the crater's last
-- `heal` seconds the rim sinks back into the ground and the decal fades; then it goes (CraterGone).
-- Budget: the preset's `craters` nearest the camera are drawn, `craterRim` chunks each (Config.Presets), anchored,
-- no collisions or queries; updated 4 times a second (FrameProf).
-- PLACEHOLDER ART: the rim chunks are plain parts in the ground's colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CraterRules = require(Shared:WaitForChild("CraterRules"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local Juice = require(script.Parent.Juice)

local GroundFx = {}

local D = Config.Destruction
local G = D.ground
local PIT = Color3.fromRGB(38, 34, 36)

type Drawn = { model: Model, rim: { { part: BasePart, from: CFrame, drop: number } }, ink: Decal? }

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

local function groundLook(c: CraterRules.Crater): (Color3, Enum.Material)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local city = Workspace:FindFirstChild("City")
	params.FilterDescendantsInstances = if city then { city, Workspace.Terrain } else { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(c.x, c.y + 3, c.z), Vector3.new(0, -8, 0), params)
	if hit and hit.Instance:IsA("BasePart") then
		return hit.Instance.Color, hit.Instance.Material
	end
	return Color3.fromRGB(150, 130, 100), Enum.Material.Slate
end

local function draw(c: CraterRules.Crater): Drawn
	local m = Instance.new("Model")
	m.Name = "GroundCrater_" .. c.id
	local color, material = groundLook(c)
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
			Vector3.new(0.1, c.r * 1.5, c.r * 1.5),
			at * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)),
			PIT,
			Enum.Material.Slate
		)
		pit.Shape = Enum.PartType.Cylinder
		pit.Transparency = if ink then 0.45 else 0.15
		pit.Parent = m
	end
	local rim = {}
	for _, r in CraterRules.rim(c, QualityController.preset.craterRim or 8) do
		local cf = CFrame.new(r.x, r.y, r.z)
			* CFrame.Angles(0, math.rad(r.ry), 0)
			* CFrame.Angles(0, 0, math.rad(r.tilt))
		local chunk = part(Vector3.new(r.sx, r.sy, r.sz), cf, color:Lerp(PIT, 0.2), material)
		chunk.CastShadow = true
		chunk.Parent = m
		table.insert(rim, { part = chunk, from = cf, drop = r.sy + 0.5 })
	end
	m.Parent = folder
	return { model = m, rim = rim, ink = ink }
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
	local list = {}
	for id, c in live do
		local d2 = (c.x - eye.X) ^ 2 + (c.z - eye.Z) ^ 2
		if d2 < 600 * 600 then
			table.insert(list, { id = id, d = d2 })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local keep: { [number]: boolean } = {}
	for i = 1, math.min(#list, QualityController.preset.craters or 6) do
		keep[list[i].id] = true
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
		local h = CraterRules.healing(G, c, now)
		for _, r in d.rim do
			r.part.CFrame = r.from - Vector3.new(0, r.drop * h, 0)
		end
		if d.ink then
			d.ink.Transparency = h
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
			live[c.id] = c
			Juice.fire("crater", Vector3.new(c.x, c.y, c.z), { mine = false })
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
