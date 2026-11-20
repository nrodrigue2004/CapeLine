-- ParkBuilder: the city park on the server (2026-11-20; Config.Park, Shared.ParkLayout). CityBuilder.build spawns it
-- after the hub is up (the hub already holds the park's avenue, paths, paved rounds and trees).
-- * The ground inside the wall as Terrain (WriteVoxels, 32 x 32 columns a step, a frame between steps): grass and
--   lawns, the woods' leafy floor, sand beaches sloping into the lake and the pond, the reservoir's stone edge, rock
--   outcrops to climb, and water. The city's ground plates leave this rectangle open (WorldGen.base holes).
-- * The structures' collision boxes (hidden) and every Art.Park piece over them (visual only), the wall and the
--   reservoir rail as breakable lengths (named "prop": BuildingFx knocks them loose and they stand again later),
--   reeds and lily pads, the name on the signed gates. Each in its 140-stud chunk model (streams like the hub).
-- * destroy-all (2026-11-20, nate: "destroy EVERYTHING"): each placed look and its collision boxes carry one Dress
--   key (Shared.StreetBreak.parkDress; DressBig on a bandshell, bridge or carousel): a device's BuildingFx knocks the
--   whole look loose as one (a big one only on a heavy hit or a ram) and stands it again after the street's respawn.
--   The server's boxes never move (robots and the height map as before).
-- * Until Art.Park is imported the collision boxes show (PLACEHOLDER ART) and the wall and rail are plain lengths.
-- Tags for each device's Fx.ParkLife: ParkSpin (the carousel's turning pieces), ParkJet (a fountain's water).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ParkLayout = require(Shared:WaitForChild("ParkLayout"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local SignKit = require(Shared:WaitForChild("SignKit"))
local StreetBreak = require(Shared:WaitForChild("StreetBreak"))

local ParkBuilder = {}
ParkBuilder.voxels = 0 -- Terrain voxels written (the Dev panel and the tests' log)
ParkBuilder.parts = 0
ParkBuilder.done = false

local P = Config.Park
local GRID = 4
local Y0, Y1 = -16, 20 -- the Terrain layers written (rocks reach 15 above the ground, beds 12 below)
local TERRAIN: { [string]: Enum.Material } = {
	grass = Enum.Material.Grass,
	leafy = Enum.Material.LeafyGrass,
	ground = Enum.Material.Ground,
	mud = Enum.Material.Mud,
	sand = Enum.Material.Sand,
	rock = Enum.Material.Rock,
	slate = Enum.Material.Slate,
	water = Enum.Material.Water,
}

local function source(name: string): MeshPart?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local root = art and art:FindFirstChild(P.set)
	local src = root and root:FindFirstChild(name, true)
	return if src and src:IsA("MeshPart") then src else nil
end

-- The voxels of one column block (cx0, cz0 its min corner, n x m columns)
local function writeBlock(terrain: Terrain, park: any, x0: number, z0: number, nx: number, nz: number)
	local ny = (Y1 - Y0) // GRID
	local mats, occs = table.create(nx), table.create(nx)
	for i = 1, nx do
		local mcol, ocol = table.create(ny), table.create(ny)
		for j = 1, ny do
			mcol[j] = table.create(nz, Enum.Material.Air)
			ocol[j] = table.create(nz, 0)
		end
		mats[i], occs[i] = mcol, ocol
	end
	for i = 1, nx do
		local x = x0 + (i - 0.5) * GRID
		for k = 1, nz do
			local z = z0 + (k - 0.5) * GRID
			local top, mat, water = ParkLayout.column(park, x, z)
			if mat == "grass" and top <= 0.01 then
				mat = ParkLayout.floor(P, x, z)
			end
			local under = if mat == "rock" or mat == "slate" then mat elseif water then "mud" else "ground"
			for j = 1, ny do
				local y = Y0 + (j - 1) * GRID
				local m, o = "air", 0
				if y + GRID <= top then
					m, o = if top - (y + GRID) < 2 then mat else under, 1
				elseif y < top then
					m, o = mat, (top - y) / GRID
					if water and water > top and (water - top) > (top - y) then
						m, o = "water", math.min(1, (water - y) / GRID)
					end
				elseif water and y < water then
					m, o = "water", math.min(1, (water - y) / GRID)
				end
				if m ~= "air" then
					mats[i][j][k] = TERRAIN[m]
					occs[i][j][k] = math.clamp(o, 0.02, 1)
				end
			end
		end
	end
	local region = Region3.new(Vector3.new(x0, Y0, z0), Vector3.new(x0 + nx * GRID, Y1, z0 + nz * GRID))
	terrain:WriteVoxels(region, GRID, mats, occs)
	ParkBuilder.voxels += nx * ny * nz
end

local function buildTerrain(park: any)
	local terrain = Workspace.Terrain
	-- the lawn's own greens (Terrain colours are per material; the Deep uses Sand, Rock and Water, not these)
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(104, 160, 74))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(84, 132, 60))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(118, 96, 72))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(86, 74, 60))
	pcall(function()
		(terrain :: any).Decoration = true -- the grass blades (Studio list: may need setting in the place)
	end)
	local g = park.green
	local step = 32
	for x0 = g.x0, g.x1 - 1, step * GRID do
		for z0 = g.z0, g.z1 - 1, step * GRID do
			local nx = math.min(step, (g.x1 - x0) // GRID)
			local nz = math.min(step, (g.z1 - z0) // GRID)
			writeBlock(terrain, park, x0, z0, nx, nz)
			task.wait()
		end
	end
end

local function chunkKey(x: number, z: number): string
	return string.format("%d_%d", math.floor(x / 140), math.floor(z / 140))
end

function ParkBuilder.build(world: any, folder: Instance, makePart: (any) -> BasePart)
	local park = world.park
	if not park then
		return
	end
	local t0 = os.clock()
	local root = Instance.new("Folder")
	root.Name = "Park"
	root.Parent = folder
	local chunks: { [string]: Model } = {}
	local function chunk(x: number, z: number): Model
		local key = chunkKey(x, z)
		local m = chunks[key]
		if not m then
			m = Instance.new("Model")
			m.Name = "Park_" .. key
			m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			m.Parent = root
			chunks[key] = m
		end
		return m
	end

	-- every look whose pieces are all imported (all or nothing, like the other sets)
	local ready: { [string]: boolean } = {}
	for look, pieces in Config.ParkArt do
		local ok = true
		for name in pieces do
			if not source(name) then
				ok = false
			end
		end
		ready[look] = ok
	end
	local anyReady = next(ready) ~= nil and ready.Bandshell == true
	local dress = StreetBreak.parkDress(park)
	local function dressUp(p: BasePart, key: string?)
		if key then
			p:SetAttribute("Dress", key)
			if dress.big[key] then
				p:SetAttribute("DressBig", true)
			end
		end
	end

	for i, b in park.solid do
		local p = makePart(b)
		dressUp(p, dress.box[i])
		p.Name = "parkSolid"
		p.Transparency = if anyReady then 1 else 0 -- PLACEHOLDER ART until Art.Park is imported
		p.CastShadow = not anyReady
		if b.tag == "ParkIce" then
			p.Material = Enum.Material.Ice -- slippery under the rink's ice look
		end
		p.Parent = chunk(b.cx, b.cz)
		ParkBuilder.parts += 1
	end
	local ink = Color3.fromRGB(246, 232, 190)
	for i, m in park.meshes do
		local src = source(m.name)
		local p: BasePart
		if src and ready[m.look] then
			local mp = MeshFix.clone(src)
			for _, ch in mp:GetChildren() do
				if not ch:IsA("SurfaceAppearance") then
					ch:Destroy()
				end
			end
			mp.Size = Vector3.new(m.size[1], m.size[2], m.size[3])
			mp.CFrame = CFrame.new(m.x, m.y, m.z) * CFrame.Angles(0, math.rad(m.ry), 0) * MeshFix.of(mp)
			p = mp
		elseif m.breaks then
			-- the wall and rail stand as plain lengths until their meshes are in (PLACEHOLDER ART)
			local part = Instance.new("Part")
			part.Size = Vector3.new(m.size[1], m.size[2], m.size[3])
			part.CFrame = CFrame.new(m.x, m.y, m.z) * CFrame.Angles(0, math.rad(m.ry), 0)
			p = part
		else
			continue
		end
		p.Anchored = true
		p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[m.mat]
		end)
		p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
		p.Transparency = m.alpha
		p.CanCollide = m.collide
		p.CanQuery = m.collide
		p.CanTouch = false
		p.CastShadow = m.mat ~= "Neon" and m.alpha == 0
		p.Name = if m.breaks then "prop" else m.name
		p:SetAttribute("ParkPiece", m.name)
		dressUp(p, dress.mesh[i])
		if m.tag then
			CollectionService:AddTag(p, m.tag)
		end
		-- the fountains' pools ripple like the city's (shapes-2: Config.Life.shapes.water, Fx.WaterSurface drifts them)
		local W = Config.Life.shapes and Config.Life.shapes.water
		if m.tag == "ParkJet" and W and W.image ~= 0 then
			for k = 1, 2 do
				local tex = Instance.new("Texture")
				tex.Name = "Ripple"
				tex.Texture = "rbxassetid://" .. tostring(W.image)
				tex.Face = Enum.NormalId.Top
				tex.StudsPerTileU = W.studs * (if k == 1 then 1 else 1.37)
				tex.StudsPerTileV = W.studs * (if k == 1 then 1 else 1.37)
				tex.Transparency = if k == 1 then 0.35 else 0.6
				tex.Parent = p
			end
			CollectionService:AddTag(p, "LifeWater")
		end
		if m.tag == "ParkSign" then
			SignKit.letter(p, string.upper(P.name), ink, {
				faces = { Enum.NormalId.Front, Enum.NormalId.Back },
				pixels = 24,
			})
		end
		p.Parent = chunk(m.x, m.z)
		ParkBuilder.parts += 1
	end
	root:SetAttribute("Ready", anyReady)
	buildTerrain(park)
	ParkBuilder.done = true
	print(
		string.format(
			"[ParkBuilder] %s: %d parts, %d Terrain voxels in %.2f s (meshes %s)",
			P.name,
			ParkBuilder.parts,
			ParkBuilder.voxels,
			os.clock() - t0,
			if anyReady then "in" else "missing"
		)
	)
end

return ParkBuilder
