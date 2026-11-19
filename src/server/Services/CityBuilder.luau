-- CityBuilder: builds the world from WorldMap (spec: Server lifecycle steps 1 to 3; Map layout; Procedural
-- outskirts; Streaming).
-- * Boot: the weekly seed (ISO year x 100 + ISO week, or Config.Dev.worldSeed in Studio) and the whole world
--   as data, then the hub (Downtown, the Docks, Old Town, safehouses, beacons) and the base (ground, sand,
--   ocean, roads) as parts at once, so players can join at second 3.
-- * Then the landmarks and the outskirts tiles in the background, Config.World.buildPerFrame tiles a frame.
--   Each tile is its own Atomic model so StreamingEnabled streams it whole. The seed and the tile array hash
--   go to the log and to Workspace attributes (spec: "each server writes the hash of the tile array to its
--   log"; the M4 gate compares two servers).
-- * heightAt(x, z): the roof or ground height anywhere (the robot AI, the load bots and spawn checks).
-- PLACEHOLDER ART: plain parts in the muted city palette until the kit and Chunker pass (M5).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local WorldGen = require(Shared:WaitForChild("WorldGen"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))
local DeepArtKit = require(Shared:WaitForChild("DeepArtKit"))
local HqRules = require(Shared:WaitForChild("HqRules"))
local SideQuestSites = require(Shared:WaitForChild("SideQuestSites"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local CityBuilder = {}
CityBuilder.world = nil :: any
CityBuilder.layout = nil :: any -- the Downtown layout (M1 callers)
CityBuilder.folder = nil :: Folder?
CityBuilder.ready = false -- true once every outskirts tile is built
CityBuilder.Ready = Signal.new()
CityBuilder.builtParts = 0
CityBuilder.buildingModels = {} :: { [number]: Model } -- wreckable building id -> its model
CityBuilder.collapsed = {} :: { [number]: any } -- collapsed building id -> its record (heights drop to rubble)
CityBuilder.deep = nil :: any -- DeepLayout.build: the underwater areas, caches, rescues and the Trench arena
CityBuilder.tops = {} :: { [number]: { box: any, top: number } } -- building id -> what still stands after storeys fell

local MATERIAL = {
	ground = Enum.Material.Grass,
	sand = Enum.Material.Sand,
	sea = Enum.Material.SmoothPlastic,
	water = Enum.Material.SmoothPlastic,
	road = Enum.Material.Asphalt,
	sidewalk = Enum.Material.Concrete,
	plaza = Enum.Material.Pavement,
	building = Enum.Material.SmoothPlastic,
	band = Enum.Material.Glass,
	ledge = Enum.Material.Concrete,
	prop = Enum.Material.SmoothPlastic,
	roof = Enum.Material.SmoothPlastic,
	beacon = Enum.Material.SmoothPlastic,
	glow = Enum.Material.Neon,
	terminal = Enum.Material.Neon,
	field = Enum.Material.Ground,
	crop = Enum.Material.Grass,
	rock = Enum.Material.Slate,
	mark = Enum.Material.SmoothPlastic,
}

-- The city kit (Config.City.kit): a kit part takes MaterialVariant "Kit" .. name when nate's uploaded textures
-- are in MaterialService (art/city/materials.py; Tasks.md "City kit: the whole city"), else it keeps its plain
-- look. Each texture switches on alone: a building's window bands (b.plain) give way once its own front is in.
-- Tinted textures keep a colour (the box's tint, else its own colour); the rest show white so nothing tints.
-- The street props are not built here: each device builds the ones near it (CityProps).
local KIT = Config.City.kit
local WHITE = Color3.new(1, 1, 1)
local kitFound: { [string]: boolean } = {}
local function kitHas(name: string): boolean
	local found = kitFound[name]
	if found == nil then
		local v = MaterialService:FindFirstChild("Kit" .. name)
		found = v ~= nil and v:IsA("MaterialVariant")
		kitFound[name] = found
	end
	return found
end
-- a plain part (window bands) that its building's kit front replaces once that texture is in
local function skipPlain(b: any): boolean
	return b.plain ~= nil and kitHas(b.plain)
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

local function makePart(b: any): BasePart -- also CityBuilder.part (mission pockets)
	local p: BasePart
	if b.shape == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
	end
	p.Anchored = true
	p.CanTouch = false
	p.CastShadow = b.kind == "building"
		or b.kind == "beacon"
		or b.kind == "rock"
		or b.kind == "roof"
		or b.kind == "tier"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = MATERIAL[b.kind] or Enum.Material.SmoothPlastic
	p.Color = color(b.color)
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
		-- a Roblox ball is round: use the largest size and squash nothing (PLACEHOLDER ART)
		local s = math.max(b.sx, b.sy, b.sz)
		ball.Size = Vector3.new(s, s, s)
		ball.CFrame = CFrame.new(b.cx, b.cy, b.cz)
	else
		p.Size = Vector3.new(b.sx, b.sy, b.sz)
		p.CFrame = CFrame.new(b.cx, b.cy, b.cz) * turn
	end
	if b.kind == "band" or b.ghost or b.kind == "crop" then
		p.CanCollide = false
		p.CanQuery = false
		if b.kind == "band" then
			p.Transparency = 0.15
		end
	elseif b.kind == "water" or b.kind == "sea" then
		p.Transparency = 0.1
		p.Reflectance = 0.1
	elseif b.kind == "glow" then
		p.CanCollide = false
	end
	if b.kit and kitHas(b.kit) then
		p.Material = (Enum.Material :: any)[KIT.baseMaterial[b.kit]]
		p.MaterialVariant = "Kit" .. b.kit
		p.Color = if KIT.tinted[b.kit] ~= nil then color(b.tint or b.color) else WHITE
	end
	if b.kind == "mark" then
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
	end
	if b.tag == "beam" then
		p.Transparency = 0.55
		p.CanQuery = false
	end
	if b.tag then
		p:SetAttribute("Tag", b.tag)
		p:SetAttribute("Ref", b.ref or 0)
	end
	if b.crown then
		p:SetAttribute("Crown", true) -- a skyscraper's top: BuildingFx keeps it up while the shaft's top storey stands
	end
	return p
end

-- One model per 140-stud chunk of the hub so streaming works in sensible pieces
local function chunkKey(x: number, z: number): string
	return string.format("%d_%d", math.floor(x / 140), math.floor(z / 140))
end

local BIG = { ground = true, sand = true, sea = true, road = true }

local function buildHub(world: any, folder: Folder)
	local chunks: { [string]: Model } = {}
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = folder
	local base = Instance.new("Folder")
	base.Name = "Base"
	base.Parent = folder
	for _, b in world.baseBoxes do
		makePart(b).Parent = base -- huge pieces stay at the top level (persistent ground)
	end
	local function chunk(x: number, z: number): Model
		local key = chunkKey(x, z)
		local m = chunks[key]
		if not m then
			m = Instance.new("Model")
			m.Name = "Block_" .. key
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			-- (Model.LevelOfDetail would keep the skyline visible far away, but scripts can't set it: it
			-- needs plugin capability, and the write stopped the whole city from building in Studio)
			m.Parent = hub
			chunks[key] = m
		end
		return m
	end
	local skipped = 0
	for _, b in world.hubBoxes do
		if skipPlain(b) then
			skipped += 1
			continue
		end
		local parent: Instance
		if BIG[b.kind] or b.sx > 400 or b.sz > 400 then
			parent = base
		elseif b.bid and CityBuilder.buildingModels[b.bid] then
			parent = CityBuilder.buildingModels[b.bid]
		else
			local m = chunk(b.cx, b.cz)
			parent = m
			if b.bid then
				-- a wreckable building: its own model inside the chunk (BuildingService and the client find it)
				local bm = Instance.new("Model")
				bm.Name = "Building_" .. b.bid
				bm:SetAttribute("BuildingId", b.bid)
				bm.Parent = m
				CityBuilder.buildingModels[b.bid] = bm
				parent = bm
			end
		end
		makePart(b).Parent = parent
	end
	CityBuilder.builtParts += #world.baseBoxes + #world.hubBoxes - skipped
	-- New heroes land on the plaza (spec: Players, joining and leaving)
	for i, s in world.spawns do
		local sp = Instance.new("SpawnLocation")
		sp.Name = "PlazaSpawn" .. i
		sp.Anchored = true
		sp.Size = Vector3.new(8, 1, 8)
		sp.CFrame = CFrame.new(s.x, s.y - 2.5, s.z)
		sp.Neutral = true
		sp.Duration = 0
		sp.Transparency = 0.5
		sp.Color = color("beaconGlow")
		sp.Material = Enum.Material.Neon
		sp.Parent = folder
	end
end

local function buildOutskirts(world: any, folder: Folder)
	local t0 = os.clock()
	local tilesFolder = Instance.new("Folder")
	tilesFolder.Name = "Outskirts"
	tilesFolder.Parent = folder
	for _, lm in world.landmarks do
		local m = Instance.new("Model")
		m.Name = lm.id
		for _, b in lm.boxes do
			makePart(b).Parent = m
		end
		m:SetAttribute("Landmark", lm.id)
		m.Parent = tilesFolder
		CityBuilder.builtParts += #lm.boxes
	end
	local perFrame = Config.World.buildPerFrame
	for i, plan in world.tilePlans do
		local m = Instance.new("Model")
		m.Name = string.format("Tile_%d_%d", plan.tx, plan.tz)
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local made = 0
		for _, b in plan.boxes do
			if not skipPlain(b) then
				local parent: Instance = m
				if b.bid then
					-- a wreckable outskirts building (2026-11-19): its own model inside the tile, like the hub's
					local bm = CityBuilder.buildingModels[b.bid]
					if not bm then
						bm = Instance.new("Model")
						bm.Name = "Building_" .. b.bid
						bm:SetAttribute("BuildingId", b.bid)
						bm.Parent = m
						CityBuilder.buildingModels[b.bid] = bm
					end
					parent = bm
				end
				makePart(b).Parent = parent
				made += 1
			end
		end
		m.Parent = tilesFolder
		CityBuilder.builtParts += made
		if i % perFrame == 0 then
			RunService.Heartbeat:Wait()
		end
	end
	-- the plans are no longer needed once built (the heightmap stays); the side quests' outskirts sites are
	-- picked from them first
	SideQuestSites.warm(Config, world)
	world.tilePlans = {}
	local took = os.clock() - t0
	CityBuilder.ready = true
	Workspace:SetAttribute("WorldReady", true)
	print(
		string.format(
			"[CityBuilder] outskirts built in %.1f s (%d parts in the world)%s",
			took,
			CityBuilder.builtParts,
			if took > Config.World.buildBudget then " OVER the 20 s budget" else ""
		)
	)
	CityBuilder.Ready:Fire()
end

CityBuilder.part = makePart

local TERRAIN = { water = Enum.Material.Water, sand = Enum.Material.Sand, rock = Enum.Material.Rock }

-- The Deep's meshes (art/blender/deep.py, imported as ReplicatedStorage.Art.Deep), looked up by name
local deepFound: { [string]: MeshPart } = {}
local function deepSource(name: string): MeshPart?
	local hit = deepFound[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local root = art and art:FindFirstChild("Deep")
	local src = root and root:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		deepFound[name] = src
		return src
	end
	return nil
end

-- One placement's meshes (Shared.DeepArtKit) into its chunk model: visuals only (no collisions, queries or
-- touches; the boxes they stand in for stay, hidden). Kelp is tagged DeepKelp for DeepClient's sway.
local function deepLook(place: any, parent: Instance): number
	local n = 0
	local at = CFrame.new(place.cx, place.cy, place.cz) * CFrame.Angles(0, math.rad(place.ry or 0), 0)
	for _, m in DeepArtKit.meshes(Config, place) do
		local src = deepSource(m.name)
		if not src then
			continue
		end
		local p = src:Clone()
		for _, c in p:GetChildren() do
			if m.maps and c:IsA("SurfaceAppearance") then
				c.AlphaMode = Enum.AlphaMode.Overlay
			else
				c:Destroy()
			end
		end
		p.Name = m.name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(m.size[1], m.size[2], m.size[3])
		p.CFrame = at * CFrame.new(m.offset[1], m.offset[2], m.offset[3])
		p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[m.mat]
		end)
		p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
		p.Transparency = m.alpha
		p.CastShadow = false
		if place.tag == "kelp" then
			-- the sway turns the strand about its foot: the placement's bottom middle
			p:SetAttribute("Foot", Vector3.new(place.cx, place.cy - place.sy / 2, place.cz))
			CollectionService:AddTag(p, "DeepKelp")
		end
		p.Parent = parent
		n += 1
	end
	return n
end

-- The underwater areas (Config.Deep): Terrain water, seabed and rock walls in chunks (a few a frame), then the
-- tunnel, reef, wrecks, caches and the sunken factory as parts in 140-stud chunk models; each look imported in
-- Art.Deep is drawn over its boxes (hidden, kept for collisions, queries and the walls)
local function buildDeep(folder: Folder)
	local t0 = os.clock()
	local deep = CityBuilder.deep
	local look = Config.Deep.look
	local terrain = Workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(look.tint[1], look.tint[2], look.tint[3])
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.25
	terrain.WaterWaveSize = 0.08
	local n = 0
	for _, f in deep.terrain do
		for _, c in DeepLayout.chunks(f, Config.Deep.fillChunk) do
			terrain:FillBlock(
				CFrame.new(c.cx, c.cy, c.cz),
				Vector3.new(c.sx, c.sy, c.sz),
				TERRAIN[c.material]
			)
			n += 1
			if n % 6 == 0 then
				task.wait()
			end
		end
	end
	local deepFolder = Instance.new("Folder")
	deepFolder.Name = "Deep"
	local ready = DeepArtKit.readyLooks(Config, function(name: string): boolean
		return deepSource(name) ~= nil
	end)
	local chunks: { [string]: Model } = {}
	for _, b in deep.boxes do
		local key = chunkKey(b.cx, b.cz)
		local m = chunks[key]
		if not m then
			m = Instance.new("Model")
			m.Name = "Deep_" .. key
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			m.Parent = deepFolder
			chunks[key] = m
		end
		local p = makePart(b)
		if DeepArtKit.hides(b, ready) then
			p.Transparency = 1
			p.CastShadow = false
		end
		p.Parent = m
	end
	local meshes = 0
	for _, place in deep.art do
		if ready[place.look] then
			local key = chunkKey(place.cx, place.cz)
			local m = chunks[key]
			if not m then
				m = Instance.new("Model")
				m.Name = "Deep_" .. key
				m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				m.Parent = deepFolder
				chunks[key] = m
			end
			meshes += deepLook(place, m)
		end
	end
	deepFolder.Parent = folder
	CityBuilder.builtParts += #deep.boxes + meshes
	print(
		string.format(
			"[CityBuilder] underwater: %d fills, %d parts, %d meshes in %.2f s",
			n,
			#deep.boxes,
			meshes,
			os.clock() - t0
		)
	)
end

function CityBuilder.seed(): number
	local override = Config.Dev.worldSeed
	if RunService:IsStudio() and type(override) == "number" and override > 0 then
		return override
	end
	-- the seed is fixed for this server's life, so it never changes under live players (spec: Weekly seed)
	return WorldGen.weekSeed(os.time())
end

function CityBuilder.build()
	local seed = CityBuilder.seed()
	local t0 = os.clock()
	local world = WorldMap.build(Config, seed)
	CityBuilder.world = world
	CityBuilder.layout = world.downtown
	print(
		string.format(
			"[CityBuilder] seed %d tile hash %s (%d tiles, data in %.2f s, %d parts planned)",
			seed,
			world.hash,
			Config.World.tiles ^ 2,
			os.clock() - t0,
			world.parts.total
		)
	)
	Workspace:SetAttribute("WorldSeed", seed)
	Workspace:SetAttribute("WorldHash", world.hash)
	CityBuilder.publishInfo(world)
	local folder = Instance.new("Folder")
	folder.Name = "City"
	buildHub(world, folder)
	-- The cloud layer at 500 studs (spec: Flight ceiling)
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Parent = Workspace.Terrain
	folder.Parent = Workspace
	CityBuilder.folder = folder
	CityBuilder.deep = DeepLayout.build(Config)
	task.spawn(buildDeep, folder)
	task.spawn(buildOutskirts, world, folder)
end

-- What the client needs (ReplicatedStorage.WorldInfo, JSON): safehouses, beacons, landmarks, HQs and the
-- wreckable buildings
function CityBuilder.publishInfo(world: any)
	local info = { seed = world.seed, hash = world.hash, safehouses = {}, beacons = {}, landmarks = {} }
	for id, s in world.safehouses do
		table.insert(info.safehouses, { id = id, name = s.name, x = s.x, z = s.z, district = s.district })
	end
	for id, b in world.beacons do
		table.insert(info.beacons, { id = id, name = b.name, x = b.x, y = b.y, z = b.z })
	end
	for _, lm in world.landmarks do
		table.insert(info.landmarks, { id = lm.id, x = lm.centre.x, z = lm.centre.z, size = lm.size })
	end
	-- the wreckable buildings, for the client's chunks, rubble and drones (BuildingFx); the 2,000+ outskirts ones
	-- go in the building snapshot instead (BuildingService, a float buffer), so this text stays small
	info.buildings = {}
	for _, b in world.buildings do
		if b.district ~= "Outskirts" then
			table.insert(info.buildings, { b.id, b.x, b.z, b.sx, b.sz, b.base, b.top })
		end
	end
	-- the Vigil's HQ is its stairwell at the plaza's edge (HqRules.heroDoor; the map shows it to the Vigil only)
	local hd = HqRules.heroDoor(Config, world) or { x = world.downtown.beacon.x, z = world.downtown.beacon.z }
	info.hq = {
		{ side = "hero", x = hd.x, z = hd.z },
		{ side = "villain", x = world.spots.foundry.x, z = world.spots.foundry.z },
	}
	local value = ReplicatedStorage:FindFirstChild("WorldInfo") or Instance.new("StringValue")
	value.Name = "WorldInfo";
	(value :: StringValue).Value = HttpService:JSONEncode(info)
	value.Parent = ReplicatedStorage
end

-- Roof or ground height anywhere; a collapsed building counts as its rubble heap
function CityBuilder.heightAt(x: number, z: number): number
	for _, b in CityBuilder.collapsed do
		if math.abs(x - b.x) <= b.sx / 2 and math.abs(z - b.z) <= b.sz / 2 then
			return b.base + math.min(Config.Destruction.rubble.height, (b.top - b.base) * 0.3) * 0.6
		end
	end
	for _, t in CityBuilder.tops do
		local b = t.box
		if math.abs(x - b.x) <= b.sx / 2 and math.abs(z - b.z) <= b.sz / 2 then
			return t.top
		end
	end
	return WorldMap.heightAt(CityBuilder.world, x, z)
end

return CityBuilder
