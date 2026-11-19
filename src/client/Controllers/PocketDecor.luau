-- PocketDecor: this device's share of a pocket's kit dressing (2026-11-19, the pocket kit pass; Shared.PocketDress,
-- Config.PocketKit). The server builds each pocket with its kit looks and the tier 1 dressing every device sees
-- (PocketArt) and marks the model with its layout and index; when such a model arrives here, this works out the
-- same dressing (pure and deterministic) and builds the tiers above 1 up to this device's preset, within its
-- budget (Config.Presets <preset>.pockets: dressing parts with tier 1 counted, PointLights), plus the kit street
-- props (Art.Street, through CityProps.make). All of it is ghost decoration: no collision, no queries, no touch.
-- Built once when the pocket arrives (a hundred parts a frame at most), dropped with it, rebuilt when the preset
-- changes. No per-frame loop. Client only.

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local PocketDress = require(Shared:WaitForChild("PocketDress"))
local QualityController = require(script.Parent.QualityController)
local CityProps = require(script.Parent.CityProps)

local KIT = Config.City.kit
local PER_STEP = 100 -- dressing parts built a frame at most

local PocketDecor = {}
PocketDecor.built = 0 -- dressing parts this device built (the Dev panel can show it)

local folder: Folder? = nil
local built: { [Model]: Model } = {}

local colorCache: { [string]: Color3 } = {}
local function color(key: string): Color3
	local c = colorCache[key]
	if not c then
		local rgb = Config.City.palette[key] or { 255, 0, 255 }
		c = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		colorCache[key] = c
	end
	return c
end

local kitFound: { [string]: boolean } = {}
local function kitHas(name: string): boolean
	local f = kitFound[name]
	if f == nil then
		local v = MaterialService:FindFirstChild("Kit" .. name)
		f = v ~= nil and v:IsA("MaterialVariant")
		kitFound[name] = f
	end
	return f
end

local MATERIAL = {
	glow = Enum.Material.Neon,
	mark = Enum.Material.SmoothPlastic,
	crop = Enum.Material.Grass,
	prop = Enum.Material.SmoothPlastic,
}

-- One dressing box as a ghost part (the same look rules as CityBuilder.part's)
local function makePart(b: any): BasePart
	local p: BasePart = if b.shape == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = MATERIAL[b.kind] or Enum.Material.SmoothPlastic
	p.Color = color(b.tint or b.color)
	p.Name = b.kind
	local turn = CFrame.Angles(0, math.rad(b.ry or 0), 0)
	if b.shape == "cylinder" then
		local cyl = p :: Part
		cyl.Shape = Enum.PartType.Cylinder
		cyl.Size = Vector3.new(b.sy, b.sx, b.sz)
		cyl.CFrame = CFrame.new(b.cx, b.cy, b.cz) * turn * CFrame.Angles(0, 0, math.rad(90))
	elseif b.shape == "ball" then
		local ball = p :: Part
		ball.Shape = Enum.PartType.Ball
		local s = math.max(b.sx, b.sy, b.sz)
		ball.Size = Vector3.new(s, s, s)
		ball.CFrame = CFrame.new(b.cx, b.cy, b.cz)
	else
		p.Size = Vector3.new(b.sx, b.sy, b.sz)
		p.CFrame = CFrame.new(b.cx, b.cy, b.cz) * turn
	end
	if b.kit and kitHas(b.kit) then
		p.Material = (Enum.Material :: any)[KIT.baseMaterial[b.kit]]
		p.MaterialVariant = "Kit" .. b.kit
		p.Color = if KIT.tinted[b.kit] ~= nil then color(b.tint or b.color) else Color3.new(1, 1, 1)
	elseif b.mat then
		p.Material = (Enum.Material :: any)[b.mat]
	end
	return p
end

local function drop(src: Model)
	local m = built[src]
	if m then
		built[src] = nil
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				PocketDecor.built -= 1
			end
		end
		m:Destroy()
	end
end

local function build(src: Model)
	local layout = src:GetAttribute("PocketLayout")
	local index = src:GetAttribute("PocketIndex")
	if
		type(layout) ~= "string"
		or type(index) ~= "number"
		or not PocketLayout.known(layout)
		or not folder
	then
		return
	end
	drop(src)
	local l = PocketLayout.build(Config, index, layout)
	local dress = PocketDress.apply(Config, l, layout)
	local budget = QualityController.preset.pockets or Config.Presets.low.pockets
	local extras, props, lights = PocketDress.pick(Config, dress, budget, 2)
	local m = Instance.new("Model")
	m.Name = "Decor_" .. src.Name
	built[src] = m
	m.Parent = folder
	-- the lights hang off one invisible anchor part, an attachment each
	if #lights > 0 then
		local anchor = Instance.new("Part")
		anchor.Name = "Lights"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(l.cx, l.cy, l.cz)
		for _, li in lights do
			local a = Instance.new("Attachment")
			-- gap review (2026-11-19): relative to the anchor (an unparented attachment's WorldPosition is taken as
			-- its Position, so the light landed a whole pocket centre away once parented)
			a.Position = anchor.CFrame:PointToObjectSpace(Vector3.new(li.x, li.y, li.z))
			local pl = Instance.new("PointLight")
			pl.Color = color(li.color)
			pl.Range = li.range
			pl.Brightness = li.brightness
			pl.Shadows = false
			pl.Parent = a
			a.Parent = anchor
		end
		anchor.Parent = m
		PocketDecor.built += 1
	end
	local n = 0
	for _, e in extras do
		if built[src] ~= m then
			return -- dropped or rebuilt meanwhile
		end
		makePart(e).Parent = m
		PocketDecor.built += 1
		n += 1
		if n % PER_STEP == 0 then
			RunService.Heartbeat:Wait()
		end
	end
	for _, pr in props do
		if built[src] ~= m then
			return
		end
		local made =
			CityProps.make(pr.name, CFrame.new(pr.x, pr.y, pr.z) * CFrame.Angles(0, math.rad(pr.ry), 0), m)
		PocketDecor.built += made
	end
end

local function watch(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local model = m :: Model
	task.spawn(build, model)
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			drop(model)
		end
	end)
	model:GetAttributeChangedSignal("PocketLayout"):Connect(function()
		task.spawn(build, model)
	end)
end

function PocketDecor.init()
	local f = Instance.new("Folder")
	f.Name = "PocketDecor"
	f.Parent = Workspace
	folder = f
	local function pocketsFolder(p: Instance)
		for _, c in p:GetChildren() do
			watch(c)
		end
		p.ChildAdded:Connect(watch)
	end
	local existing = Workspace:FindFirstChild("Pockets")
	if existing then
		pocketsFolder(existing)
	end
	local subway = Workspace:FindFirstChild("PrologueSubway")
	if subway then
		watch(subway)
	end
	Workspace.ChildAdded:Connect(function(c)
		if c.Name == "Pockets" and c:IsA("Folder") then
			pocketsFolder(c)
		elseif c.Name == "PrologueSubway" then
			watch(c)
		end
	end)
	QualityController.Changed:Connect(function()
		local list = {}
		for src in built do
			table.insert(list, src)
		end
		for _, src in list do
			task.spawn(build, src)
		end
	end)
end

return PocketDecor
