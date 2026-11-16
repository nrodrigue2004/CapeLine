-- CityBuilder: builds the Downtown greybox from CityLayout (spec: Map layout; M1 "greybox Downtown").
-- PLACEHOLDER ART: plain parts in the muted city palette until the kit and Chunker pass (M5).
-- Parts are anchored and grouped per block-sized model so StreamingEnabled can stream them in and out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CityLayout = require(Shared:WaitForChild("CityLayout"))

local CityBuilder = {}
CityBuilder.layout = nil :: any
CityBuilder.folder = nil :: Folder?

local MATERIAL = {
	ground = Enum.Material.Grass,
	water = Enum.Material.SmoothPlastic,
	road = Enum.Material.Asphalt,
	sidewalk = Enum.Material.Concrete,
	plaza = Enum.Material.Pavement,
	building = Enum.Material.SmoothPlastic,
	band = Enum.Material.Glass,
	ledge = Enum.Material.Concrete,
	prop = Enum.Material.Metal,
	beacon = Enum.Material.SmoothPlastic,
	glow = Enum.Material.Neon,
}

local function color(key: string): Color3
	local c = Config.City.palette[key] or { 255, 0, 255 }
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- One model per 140-stud chunk of the map so streaming works in sensible pieces
local function chunkKey(x: number, z: number): string
	return string.format("%d_%d", math.floor(x / 140), math.floor(z / 140))
end

function CityBuilder.build()
	local layout = CityLayout.downtown(Config.City)
	CityBuilder.layout = layout
	local folder = Instance.new("Folder")
	folder.Name = "City"
	local chunks: { [string]: Model } = {}
	local function chunkFor(b: any): Instance
		if b.kind == "ground" or b.kind == "water" or b.kind == "road" then
			return folder -- huge pieces stay at the top level (persistent ground)
		end
		local key = chunkKey(b.cx, b.cz)
		local m = chunks[key]
		if not m then
			m = Instance.new("Model")
			m.Name = "Block_" .. key
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			m.Parent = folder
			chunks[key] = m
		end
		return m
	end
	for _, b in layout.boxes do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanTouch = false
		p.CastShadow = b.kind == "building" or b.kind == "beacon" or b.kind == "prop"
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = MATERIAL[b.kind] or Enum.Material.SmoothPlastic
		p.Color = color(b.color)
		p.Name = b.kind
		if b.shape == "cylinder" then
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(b.sy, b.sx, b.sz)
			p.CFrame = CFrame.new(b.cx, b.cy, b.cz) * CFrame.Angles(0, 0, math.rad(90))
		else
			p.Size = Vector3.new(b.sx, b.sy, b.sz)
			p.CFrame = CFrame.new(b.cx, b.cy, b.cz)
		end
		if b.kind == "band" then
			p.Transparency = 0.15
			p.CanCollide = false
			p.CanQuery = false
		elseif b.kind == "water" then
			p.Transparency = 0.1
			p.Reflectance = 0.1
		elseif b.kind == "glow" then
			p.CanCollide = false
		end
		p:SetAttribute("CityKind", b.kind)
		p.Parent = chunkFor(b)
	end
	-- New heroes land on the plaza (spec: Players, joining and leaving)
	for i, s in layout.spawns do
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
	-- The cloud layer at 500 studs (spec: Flight ceiling)
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Parent = Workspace.Terrain
	folder.Parent = Workspace
	CityBuilder.folder = folder
end

function CityBuilder.heightAt(x: number, z: number): number
	return CityLayout.heightAt(CityBuilder.layout, x, z)
end

return CityBuilder
