-- PocketDecor: this device's share of a pocket's kit dressing (2026-11-19, the pocket kit pass; Shared.PocketDress,
-- Config.PocketKit). The server builds each pocket with its kit looks and the tier 1 dressing every device sees
-- (PocketArt) and marks the model with its layout and index; when such a model arrives here, this works out the
-- same dressing (pure and deterministic) and builds the tiers above 1 up to this device's preset, within its
-- budget (Config.Presets <preset>.pockets: dressing parts with tier 1 counted, PointLights), plus the kit street
-- props (Art.Street, through CityProps.make). All of it is ghost decoration: no collision, no queries, no touch.
-- Built once when the pocket arrives (a hundred parts a frame at most), dropped with it, rebuilt when the preset
-- changes. No per-frame loop. Client only.
-- The props (gap-props2, 2026-11-19): the pockets' most-seen props (desks, chairs, lockers, cabinets, tanks, cages,
-- dummies, bags, pads, posts, braziers, screen desks, camera rigs, barriers, chimneys, water tanks) are drawn here in
-- art/blender/pocketprops.py's meshes (Art.PocketProps, Shared.PocketPropKit, Config.PocketProps) with the dressing,
-- within the preset's mesh budget (Config.Presets <preset>.pockets.props): the server's boxes they stand in for are
-- hidden on this device only (LocalTransparencyModifier: kept, still colliding, queried and standing as before) and
-- shown again when the pocket is dropped; dressing boxes a look stands in for are simply not built. Ghost meshes.
-- gap-props3 (2026-11-19): the second set (Art.PocketProps2: blackboards, hoops, Halo's statue, the bookcase, the
-- conveyor and half-built robots, trophy shelves, the bench, wooden dummies, sealed doors, Hoshi's cage and chains,
-- the roll door, scanner arch, dock crates, the stations, the tower mast and Live's stage) draws the same way; a
-- look's "keep" boxes (Live's giant screen) are never hidden.

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local PocketDress = require(Shared:WaitForChild("PocketDress"))
local PocketPropKit = require(Shared:WaitForChild("PocketPropKit"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local QualityController = require(script.Parent.QualityController)
local CityProps = require(script.Parent.CityProps)

local KIT = Config.City.kit
local PER_STEP = 100 -- dressing parts built a frame at most

local PocketDecor = {}
PocketDecor.built = 0 -- dressing parts this device built (the Dev panel can show it)

local folder: Folder? = nil
local built: { [Model]: Model } = {}
-- gap review (2026-11-19): only pockets near this device's camera get the tiers above 1 (every live pocket of every
-- player used to, up to 900 parts and 18 lights each on high); built inside NEAR studs of the pocket's edge,
-- dropped past FAR (no flicker at the edge), checked once a second
local known: { [Model]: boolean } = {}
local NEAR, FAR = 250, 400
local function edgeDistance(src: Model): number
	local ok, cf, size = pcall(src.GetBoundingBox, src)
	local cam = Workspace.CurrentCamera
	if not ok or not cam then
		return math.huge
	end
	return math.max(0, (cam.CFrame.Position - cf.Position).Magnitude - size.Magnitude / 2)
end

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

-- The prop meshes' sources (Art.PocketProps, and Art.PocketProps2 since gap-props3), looked up until there so a
-- later import counts
local function propSource(name: string): MeshPart?
	local art = ReplicatedStorage:FindFirstChild("Art")
	for _, s in PocketPropKit.SETS do
		local set = art and art:FindFirstChild(s.set)
		local src = set and set:FindFirstChild(name, true)
		if src and src:IsA("MeshPart") then
			return src
		end
	end
	return nil
end
local function propHas(name: string): boolean
	return propSource(name) ~= nil
end

-- The server's parts this device hides behind prop meshes, per pocket, and the watch for parts streaming in
local hidden: { [Model]: { BasePart } } = {}
local hideWatch: { [Model]: RBXScriptConnection } = {}

local function unhide(src: Model)
	local c = hideWatch[src]
	if c then
		c:Disconnect()
		hideWatch[src] = nil
	end
	for _, p in hidden[src] or {} do
		p.LocalTransparencyModifier = 0
	end
	hidden[src] = nil
end

local function hideParts(src: Model, keys: { [string]: boolean })
	unhide(src)
	if next(keys) == nil then
		return
	end
	local list: { BasePart } = {}
	hidden[src] = list
	local function try(d: Instance)
		if d:IsA("BasePart") then
			local pos = d.Position
			if keys[PocketPropKit.key(pos.X, pos.Y, pos.Z)] then
				d.LocalTransparencyModifier = 1
				table.insert(list, d)
			end
		end
	end
	for _, d in src:GetDescendants() do
		try(d)
	end
	hideWatch[src] = src.DescendantAdded:Connect(try)
end

-- One prop placement's meshes into m (ghosts); returns how many
local function makeProp(place: PocketPropKit.Place, m: Model): number
	local at = CFrame.new(place.cx, place.cy, place.cz) * CFrame.Angles(0, math.rad(place.ry), 0)
	local n = 0
	for _, mesh in PocketPropKit.meshes(Config, place) do
		local src = propSource(mesh.name)
		if not src then
			continue
		end
		local p = MeshFix.clone(src)
		for _, c in p:GetChildren() do
			if mesh.maps and c:IsA("SurfaceAppearance") then
				c.AlphaMode = Enum.AlphaMode.Overlay
			else
				c:Destroy()
			end
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = mesh.mat ~= "Neon" and mesh.alpha == 0
		p.Size = Vector3.new(mesh.size[1], mesh.size[2], mesh.size[3])
		p.CFrame = at * CFrame.new(mesh.offset[1], mesh.offset[2], mesh.offset[3]) * MeshFix.of(p) -- the import's turn
		p.Color = Color3.fromRGB(mesh.color[1], mesh.color[2], mesh.color[3])
		p.Material = (Enum.Material :: any)[mesh.mat] or Enum.Material.SmoothPlastic
		p.Transparency = mesh.alpha
		p.Parent = m
		n += 1
	end
	return n
end

local function drop(src: Model)
	unhide(src)
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
	-- the props this device draws as meshes (every mesh of the look imported, within the preset's mesh budget)
	local places = PocketPropKit.places(Config, l, dress, layout)
	local drawn =
		PocketPropKit.pick(Config, places, QualityController.name, PocketPropKit.readyLooks(Config, propHas))
	local skip: { [any]: boolean } = {}
	local keys: { [string]: boolean } = {}
	for _, p in drawn do
		for _, j in p.boxes do
			if p.dress then
				skip[dress.extras[j]] = true
			else
				local b = l.boxes[j]
				keys[PocketPropKit.key(b.cx, b.cy, b.cz)] = true
			end
		end
	end
	if next(skip) then
		local kept = {}
		for _, e in dress.extras do
			if not skip[e] then
				table.insert(kept, e)
			end
		end
		dress = { extras = kept, lights = dress.lights, props = dress.props, layout = dress.layout }
	end
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
	-- the prop meshes, then the boxes they stand in for are hidden (never before their meshes are there)
	for _, p in drawn do
		if built[src] ~= m then
			return
		end
		local made = makeProp(p, m)
		PocketDecor.built += made
		n += made
		if n % PER_STEP < made then
			RunService.Heartbeat:Wait()
		end
	end
	if built[src] == m then
		hideParts(src, keys)
	end
end

local function watch(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local model = m :: Model
	known[model] = true
	if edgeDistance(model) <= NEAR then
		task.spawn(build, model)
	end
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			known[model] = nil
			drop(model)
		end
	end)
	model:GetAttributeChangedSignal("PocketLayout"):Connect(function()
		if built[model] then
			task.spawn(build, model)
		end
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
	task.spawn(function()
		while true do
			task.wait(1)
			for src in known do
				local d = edgeDistance(src)
				if not built[src] and d <= NEAR then
					task.spawn(build, src)
				elseif built[src] and d > FAR then
					drop(src)
				end
			end
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
