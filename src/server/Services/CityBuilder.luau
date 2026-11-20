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
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local WorldGen = require(Shared:WaitForChild("WorldGen"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))
local CraterArtKit = require(Shared:WaitForChild("CraterArtKit"))
local DeepArtKit = require(Shared:WaitForChild("DeepArtKit"))
local HqRules = require(Shared:WaitForChild("HqRules"))
local SideQuestSites = require(Shared:WaitForChild("SideQuestSites"))
local LifeKit = require(Shared:WaitForChild("LifeKit"))
local LifePlan = require(Shared:WaitForChild("LifePlan"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))
local SignKit = require(Shared:WaitForChild("SignKit"))
local StreetBreak = require(Shared:WaitForChild("StreetBreak"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local CityBuilder = {}
local function parkHeight(x: number, z: number): number?
	return require(script.Parent.ParkBuilder).heightAt(x, z)
end
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
local SCARS = Config.World.crater.scars.decals or {}
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

local ALIVE_SET = Config.Life.alive and Config.Life.alive.set
local ALIVE_TAGS = (Config.Life.alive and Config.Life.alive.tags or {}) :: { [string]: string }
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
		-- shapes-2 (nate: "pools need to look better as well"): ripples on a pool's, pond's or fountain's top that
		-- the devices drift (Fx.WaterSurface, tag LifeWater); none until the picture is uploaded
		local W = Config.Life.shapes.water
		if b.kind == "water" and W.image ~= 0 then
			p.Material = Enum.Material.Glass
			p.Transparency = W.transparency
			for k = 1, 2 do
				local tex = Instance.new("Texture")
				tex.Name = "Ripple"
				tex.Texture = "rbxassetid://" .. tostring(W.image)
				-- (a cylinder part lies on its side turned up: its +x end is the top)
				tex.Face = if b.shape == "cylinder" then Enum.NormalId.Right else Enum.NormalId.Top
				tex.StudsPerTileU = W.studs * (if k == 1 then 1 else 1.37)
				tex.StudsPerTileV = W.studs * (if k == 1 then 1 else 1.37)
				tex.Transparency = if k == 1 then 0.35 else 0.6
				tex.Parent = p
			end
			CollectionService:AddTag(p, "LifeWater")
		end
	elseif b.kind == "glow" then
		p.CanCollide = false
	end
	-- a landmark's own ground (the Crater's floor and rim, gap-fx3) over its kit once that texture is in; it is
	-- drawn in its own colours, so the part shows white
	local kit = if b.ground and kitHas(b.ground) then b.ground else b.kit
	if kit and kitHas(kit) then
		p.Material = (Enum.Material :: any)[KIT.baseMaterial[kit]]
		p.MaterialVariant = "Kit" .. kit
		p.Color = if KIT.landmark[kit] or KIT.tinted[kit] == nil then WHITE else color(b.tint or b.color)
	elseif b.mat then
		-- a pocket box's plain look (Shared.PocketDress: lamps, metal, cloth) in its pocket's tint
		p.Material = (Enum.Material :: any)[b.mat]
		if b.tint then
			p.Color = color(b.tint)
		end
	elseif b.kit and b.tint and b.dress then
		p.Color = color(b.tint) -- a dressing piece waiting on its texture still shows its pocket colour
	end
	-- the living world (2026-11-19): a picket fence's box is hidden behind the uploaded picket picture on both long
	-- faces, so the gaps show through; it keeps its collisions and breaks like any street thing (attribute Picket)
	local faces = if b.look == "Picket" then LifeKit.picket(Config, b) else nil
	if faces then
		p.Transparency = 1
		p.CastShadow = false
		p:SetAttribute("Picket", true)
		for _, face in faces do
			local tex = Instance.new("Texture")
			tex.Name = "Picket"
			tex.Texture = "rbxassetid://" .. tostring(Config.Life.picket.image)
			tex.Face = (Enum.NormalId :: any)[face]
			tex.StudsPerTileU = Config.Life.picket.studs
			tex.StudsPerTileV = b.sy
			tex.Parent = p
		end
	end
	if b.kind == "mark" then
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
	end
	-- the Crater's burn scars (gap-fx3, 2026-11-19): the comic scar decal on the strip's top face, the strip itself
	-- hidden (a mark never collides or queries either way); id 0 keeps the plain dark strip
	local scar = b.scar and SCARS[b.scar]
	if scar and scar.id ~= 0 then
		p.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Name = "Scar"
		decal.Texture = "rbxassetid://" .. tostring(scar.id)
		decal.Face = Enum.NormalId.Top
		decal.Parent = p
	end
	-- shapes-2 (2026-11-19): a road picture (a zebra crossing, a storm drain) on the strip's top, the strip hidden
	local decalId = b.decal and Config.Life.shapes.decals[b.decal]
	if decalId and decalId ~= 0 then
		p.Transparency = 1
		local decal = Instance.new("Decal")
		decal.Name = b.decal
		decal.Texture = "rbxassetid://" .. tostring(decalId)
		decal.Face = Enum.NormalId.Top
		decal.Parent = p
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
	local lifeTag = b.look and ALIVE_TAGS[b.look]
	if lifeTag then
		CollectionService:AddTag(p, lifeTag) -- the devices' life there (Fx.CityLife: chimney smoke, harbour gulls)
	end
	return p
end

-- One model per 140-stud chunk of the hub so streaming works in sensible pieces
local function chunkKey(x: number, z: number): string
	return string.format("%d_%d", math.floor(x / 140), math.floor(z / 140))
end

local BIG = { ground = true, sand = true, sea = true, road = true }

-- pt-city (2026-11-19): a box with `art` (Shared.CityPlay: awnings, water towers, antennas, roof units, billboards,
-- perches) is built as that Art.Street prop's meshes in its place, once every piece is imported; else the box as
-- today. The meshes collide like the box did (Config.City.kit.props pieces), sit in the same building model, so
-- they hide and break with it; attributes tell BuildingFx what falls off or bursts and MoveController what bounces.
local STREET_FIT = Config.StreetArt
local streetFound: { [string]: MeshPart | false } = {}
local function streetMesh(piece: string): MeshPart?
	local hit = streetFound[piece]
	if hit == nil then
		local art = ReplicatedStorage:FindFirstChild("Art")
		local root = art and art:FindFirstChild("Street")
		local src = root and root:FindFirstChild(piece, true)
		if not (src and src:IsA("MeshPart")) then
			-- the rooftop row's dressing (art/blender/rooftop.py, Everything Left 268)
			local roof = art and art:FindFirstChild("Roof")
			src = roof and roof:FindFirstChild(piece, true)
		end
		if not (src and src:IsA("MeshPart")) then
			-- the living world's foot looks (shop fronts: art/blender/life.py)
			local life = art and art:FindFirstChild(Config.Life.set)
			src = life and life:FindFirstChild(piece, true)
		end
		hit = if src and src:IsA("MeshPart") then src else false
		streetFound[piece] = hit
	end
	return if hit then hit else nil
end
-- a billboard's printed ad (Config.City.kit.play.billboard.ads[i], Everything Left 269) on one face of a board
local function adOn(p: BasePart, i: number, face: Enum.NormalId)
	local id = KIT.play.billboard.ads[i]
	if not id or id == 0 then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ad"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.MaxDistance = 600
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = "rbxassetid://" .. id
	img.ScaleType = Enum.ScaleType.Stretch
	img.Parent = gui
	gui.Parent = p
end

local function streetArt(b: any): { BasePart }?
	local a = b.art
	local def = a and KIT.props[a.name]
	local fit = a and (STREET_FIT[a.name] or Config.RoofArt[a.name] or Config.LifeArt[a.name])
	if not (def and fit) then
		return nil
	end
	for piece in def.pieces do
		if not (fit[piece] and streetMesh(piece)) then
			return nil -- all or nothing: a half-built prop never shows
		end
	end
	local at = CFrame.new(a.x, a.y, a.z) * CFrame.Angles(0, math.rad(a.ry), 0)
	local out = {}
	for piece, look in def.pieces do
		local src = streetMesh(piece) :: MeshPart
		local f = fit[piece]
		local p = MeshFix.clone(src)
		for _, ch in p:GetChildren() do
			if not ch:IsA("SurfaceAppearance") then
				ch:Destroy()
			end
		end
		p.Name = piece
		p.Anchored = true
		p.Size = Vector3.new(f.size[1], f.size[2], f.size[3])
		p.CFrame = at * CFrame.new(f.offset[1], f.offset[2], f.offset[3]) * MeshFix.of(p) -- the import's turn
		local rgb = if look[5] and a.tint then Config.City.palette[a.tint] or look[1] else look[1]
		if look[6] and a.frame then
			rgb = a.frame -- a shop front's frame paint (Config.Life.shop.frame, by hash)
		end
		p.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		p.Material = (Enum.Material :: any)[look[2]]
		p.Transparency = look[4] or 0
		p.CanCollide = look[3]
		p.CanQuery = look[3]
		p.CanTouch = false
		p.CastShadow = look[2] ~= "Neon"
		if def.falls then
			p:SetAttribute("Falls", true)
		end
		if def.burst then
			p:SetAttribute("Burst", true)
		end
		if def.bounce and look[3] then
			p:SetAttribute("Bounce", true)
		end
		if b.crown then
			p:SetAttribute("Crown", true)
		end
		-- a rooftop billboard's printed ad (Everything Left 269) on its art panel's street face (the import turn
		-- swaps the face); a SurfaceGui, so it hides and falls with the board like the shop signs' words
		if a.ad and piece == "BoardArt" then
			adOn(
				p,
				a.ad,
				if MeshFix.of(p) ~= CFrame.identity then Enum.NormalId.Back else Enum.NormalId.Front
			)
		end
		-- the living world: a shop's sign lettered with its word (fixed text; the face toward the street, the import
		-- turn swaps it), its back lit at night and a roof vent's steam on the devices (Fx.CityLife)
		if a.sign and piece == "ShopSign" then
			local ink = KIT.play.shop.ink
			SignKit.letter(p, a.sign, Color3.fromRGB(ink[1], ink[2], ink[3]), {
				faces = {
					if MeshFix.of(p) ~= CFrame.identity then Enum.NormalId.Back else Enum.NormalId.Front,
				},
				pixels = 24,
			})
		elseif piece == "ShopBack" then
			CollectionService:AddTag(p, "LifeShop")
		elseif piece == "RoofVent" then
			CollectionService:AddTag(p, "LifeSteam")
		end
		table.insert(out, p)
	end
	return out
end

-- The living world's cover looks (Shared.LifeKit, Art.Life): a box with a `look` is built as that look's meshes in
-- its place once every piece is imported, named like the box (so the street breaking finds them), colliding like
-- it; else nil and the box as today
local lifeFound: { [string]: MeshPart | false } = {}
local function lifeMesh(name: string, set: string?): MeshPart?
	local key = (set or Config.Life.set) .. "/" .. name
	local hit = lifeFound[key]
	if hit == nil then
		local art = ReplicatedStorage:FindFirstChild("Art")
		local root = art and art:FindFirstChild(set or Config.Life.set)
		local src = root and root:FindFirstChild(name, true)
		hit = if src and src:IsA("MeshPart") then src else false
		lifeFound[key] = hit
	end
	return if hit then hit else nil
end
-- a look's meshes are in one set: round 2's (Config.ShapeArt, Art.Shapes), round 3's (Config.AliveArt, Art.Alive)
-- or the living world's (Art.Life)
local function lifeHasIn(look: string): (string) -> boolean
	local set = LifeKit.setOf(Config, look)
	return function(name: string): boolean
		return lifeMesh(name, set) ~= nil
	end
end
local function lifeParts(b: any): { BasePart }?
	local look = LifeKit.lookOf(Config, b)
	if not (look and LifeKit.ready(Config, look, lifeHasIn(look))) then
		return nil
	end
	local pieces = LifeKit.cover(Config, b)
	if not pieces then
		return nil
	end
	local out = {}
	for _, pc in pieces do
		local p = MeshFix.clone(lifeMesh(pc.name, pc.set) :: MeshPart)
		for _, ch in p:GetChildren() do
			-- (round 2's flat meshes drop their SurfaceAppearance too and show their own colour)
			if not ch:IsA("SurfaceAppearance") or (pc.set and not pc.maps) then
				ch:Destroy()
			end
		end
		-- round 3's looks are visual only over a box that stays: named "dress" so the street smash (Fx.BuildingFx,
		-- parts named "prop") never flings a crane's cab or trolley off it (alive-world round 2, 2026-11-20)
		p.Name = if pc.set == ALIVE_SET then "dress" else b.kind
		p.Anchored = true
		p.Size = Vector3.new(pc.size[1], pc.size[2], pc.size[3])
		p.CFrame = CFrame.new(pc.x, pc.y, pc.z) * CFrame.Angles(0, math.rad(pc.ry), 0) * MeshFix.of(p) -- the import's turn
		p.Color = Color3.fromRGB(pc.color[1], pc.color[2], pc.color[3])
		p.Material = (Enum.Material :: any)[pc.mat]
		p.CanCollide = pc.collide
		p.CanQuery = pc.collide
		p.CanTouch = false
		p.CastShadow = b.kind ~= "crop"
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Transparency = pc.alpha or 0
		if pc.mat == "Neon" or (pc.alpha or 0) > 0 then
			p.CastShadow = false
		end
		p:SetAttribute("Look", pc.name)
		table.insert(out, p)
	end
	return out
end

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
		if skipPlain(b) or (b.decal and (Config.Life.shapes.decals[b.decal] or 0) == 0) then
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
		local meshes = if b.art then streetArt(b) elseif b.look then lifeParts(b) else nil
		if meshes and b.look and LifeKit.keeps(Config, b) then
			-- a roof's cap stays under its moulding (shapes-2); round 3's boxes stay under their looks, some hidden
			-- (a terminal keeps its prompt, a crane its collisions: alive-world)
			local kept = makePart(b)
			if LifeKit.hides(Config, b) then
				kept.Transparency = 1
				kept.CastShadow = false
				kept:SetAttribute("Dressed", true)
			end
			kept.Parent = parent
			skipped -= 1
		end
		if meshes then
			for _, p in meshes do
				p.Parent = parent
			end
			skipped += 1 - #meshes
		else
			local p = makePart(b)
			if b.tag == "Awning" then
				p:SetAttribute("Bounce", true) -- the box stands in for the awning until its meshes are in
			end
			if b.ad then
				adOn(p, b.ad, Enum.NormalId.Front) -- the rooftop row's board faces the street (-z)
			end
			p.Parent = parent
		end
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

-- An imported art set's meshes (ReplicatedStorage.Art.<set>), looked up by name: the Deep's (art/blender/deep.py)
-- and the Crater's (art/blender/crater.py)
local artFound: { [string]: MeshPart } = {}
local function artSource(set: string, name: string): MeshPart?
	local key = set .. "/" .. name
	local hit = artFound[key]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local root = art and art:FindFirstChild(set)
	local src = root and root:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		artFound[key] = src
		return src
	end
	return nil
end
local function deepSource(name: string): MeshPart?
	return artSource("Deep", name)
end

-- One mesh of a look as a visual-only clone (no collisions, queries or touches; no shadow) at `at` * its offset
local function artMesh(src: MeshPart, m: any, at: CFrame): MeshPart
	local p = MeshFix.clone(src)
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
	p.CFrame = at * CFrame.new(m.offset[1], m.offset[2], m.offset[3]) * MeshFix.of(p) -- the import's turn
	p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
	local ok, mat = pcall(function()
		return (Enum.Material :: any)[m.mat]
	end)
	p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
	p.Transparency = m.alpha
	p.CastShadow = false
	return p
end

local function buildOutskirts(world: any, folder: Folder)
	local t0 = os.clock()
	local tilesFolder = Instance.new("Folder")
	tilesFolder.Name = "Outskirts"
	tilesFolder.Parent = folder
	for _, lm in world.landmarks do
		local m = Instance.new("Model")
		m.Name = lm.id
		-- the Crater's Crane lab (lore step 9) in art/blender/crater.py's meshes once Art.Crater has every mesh of a
		-- look: its boxes are hidden but kept exactly as they were (collisions, queries); else today's parts
		local ready = if lm.art
			then CraterArtKit.readyLooks(Config, function(name: string): boolean
				return artSource("Crater", name) ~= nil
			end)
			else {}
		for _, b in lm.boxes do
			local life = if b.look then lifeParts(b) else nil -- (shapes-2: the radio mast, the quarry's boulders)
			if life then
				for _, lp in life do
					lp.Parent = m
				end
				continue
			end
			local p = makePart(b)
			if CraterArtKit.hides(b, ready) then
				p.Transparency = 1
				p.CastShadow = false
			end
			p.Parent = m
		end
		for _, place in lm.art or {} do
			if ready[place.look] then
				local at = CFrame.new(place.cx, place.cy, place.cz)
					* CFrame.Angles(0, math.rad(place.ry or 0), 0)
				for _, mm in CraterArtKit.meshes(Config, place) do
					local src = artSource("Crater", mm.name)
					if src then
						artMesh(src, mm, at).Parent = m
					end
				end
			end
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
				local life = if b.art then streetArt(b) elseif b.look then lifeParts(b) else nil
				if life then
					if b.look and LifeKit.keeps(Config, b) then
						makePart(b).Parent = parent -- a roof's cap stays under its moulding (shapes-2)
						made += 1
					end
					for _, lp in life do
						lp.Parent = parent
					end
					made += #life
				else
					makePart(b).Parent = parent
					made += 1
				end
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

-- One placement's meshes (Shared.DeepArtKit) into its chunk model: visuals only (no collisions, queries or
-- touches; the boxes they stand in for stay, hidden). Kelp is tagged DeepKelp for DeepClient's sway.
local function deepLook(place: any, parent: Instance, dress: string?): number
	local n = 0
	local at = CFrame.new(place.cx, place.cy, place.cz) * CFrame.Angles(0, math.rad(place.ry or 0), 0)
	for _, m in DeepArtKit.meshes(Config, place) do
		local src = deepSource(m.name)
		if not src then
			continue
		end
		local p = artMesh(src, m, at)
		if place.tag == "kelp" then
			-- the sway turns the strand about its foot: the placement's bottom middle
			p:SetAttribute("Foot", Vector3.new(place.cx, place.cy - place.sy / 2, place.cz))
			CollectionService:AddTag(p, "DeepKelp")
		end
		if dress then
			p:SetAttribute("Dress", dress)
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
	-- destroy-all (2026-11-20): a hidden coral or wreck prop and its look's meshes knock loose as one (StreetBreak)
	local dress = StreetBreak.deepDress(deep.boxes, deep.art, ready)
	for i, b in deep.boxes do
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
		if dress.box[i] then
			p:SetAttribute("Dress", dress.box[i])
		end
		p.Parent = m
	end
	local meshes = 0
	for j, place in deep.art do
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
			meshes += deepLook(place, m, dress.mesh[j])
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
	-- the city park between Downtown and Uptown (2026-11-20): its Terrain, structures and wall
	task.spawn(require(script.Parent.ParkBuilder).build, world, folder, makePart)
end

-- What the client needs (ReplicatedStorage.WorldInfo, JSON): safehouses, beacons, landmarks, HQs and the
-- wreckable buildings
function CityBuilder.publishInfo(world: any)
	local info = { seed = world.seed, hash = world.hash, safehouses = {}, beacons = {}, landmarks = {} }
	for id, s in world.safehouses do
		-- y: the pad's top, for the pad's corner flags (Fx.CityLife, alive-world 2026-11-20)
		table.insert(
			info.safehouses,
			{ id = id, name = s.name, x = s.x, y = s.y, z = s.z, district = s.district }
		)
	end
	for id, b in world.beacons do
		table.insert(info.beacons, { id = id, name = b.name, x = b.x, y = b.y, z = b.z })
	end
	for _, lm in world.landmarks do
		table.insert(
			info.landmarks,
			{ id = lm.id, x = lm.centre.x, z = lm.centre.z, size = lm.size, floorY = lm.floorY, art = lm.art }
		)
	end
	-- the wreckable buildings, for the client's chunks, rubble and drones (BuildingFx); the 2,000+ outskirts ones
	-- go in the building snapshot instead (BuildingService, a float buffer), so this text stays small
	info.buildings = {}
	for _, b in world.buildings do
		if b.district ~= "Outskirts" then
			-- 8th: 1 for a round body (Structure lays its pieces on the circle), 0 for a box
			table.insert(
				info.buildings,
				{ b.id, b.x, b.z, b.sx, b.sz, b.base, b.top, if b.round then 1 else 0 }
			)
		end
	end
	-- the living world's driving lines (Shared.LifePlan.lanes from the lane dashes; the tram lines left out), for
	-- each device's ambient traffic, steam vents and pigeons (Fx.CityLife): { ax, c, a0, a1, y }
	local skips = {}
	for _, v in Vehicles.place(Config) do
		if v.kind == "tram" then
			table.insert(
				skips,
				{ ax = if v.ry % 180 == 90 then "x" else "z", c = if v.ry % 180 == 90 then v.z else v.x }
			)
		end
	end
	info.lanes = {}
	for _, l in LifePlan.lanes(world.hubBoxes, skips) do
		table.insert(info.lanes, { l.ax, l.c, l.a0, l.a1, l.y })
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
	local park = parkHeight(x, z) -- a broken park look (destroy-all): robots walk where it stood
	if park then
		return park
	end
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
