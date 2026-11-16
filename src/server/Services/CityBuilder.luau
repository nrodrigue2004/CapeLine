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

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local WorldGen = require(Shared:WaitForChild("WorldGen"))
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
}

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
	p.CastShadow = b.kind == "building" or b.kind == "beacon" or b.kind == "rock" or b.kind == "roof"
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
	if b.tag == "beam" then
		p.Transparency = 0.55
		p.CanQuery = false
	end
	if b.tag then
		p:SetAttribute("Tag", b.tag)
		p:SetAttribute("Ref", b.ref or 0)
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
	for _, b in world.hubBoxes do
		local parent: Instance
		if BIG[b.kind] or b.sx > 400 or b.sz > 400 then
			parent = base
		elseif b.bid and CityBuilder.buildingModels[b.bid] then
			parent = CityBuilder.buildingModels[b.bid]
		else
			local key = chunkKey(b.cx, b.cz)
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
	CityBuilder.builtParts += #world.baseBoxes + #world.hubBoxes
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
		for _, b in plan.boxes do
			makePart(b).Parent = m
		end
		m.Parent = tilesFolder
		CityBuilder.builtParts += #plan.boxes
		if i % perFrame == 0 then
			RunService.Heartbeat:Wait()
		end
	end
	-- the plans are no longer needed once built (the heightmap stays)
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
	-- the wreckable buildings, for the client's chunks, rubble and drones (BuildingFx)
	info.buildings = {}
	for _, b in world.buildings do
		table.insert(info.buildings, { b.id, b.x, b.z, b.sx, b.sz, b.base, b.top })
	end
	local bt = world.downtown.beacon
	info.hq = {
		{ side = "hero", x = bt.x, z = bt.z },
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
	return WorldMap.heightAt(CityBuilder.world, x, z)
end

return CityBuilder
