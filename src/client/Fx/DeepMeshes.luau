--!strict
-- DeepMeshes: art/blender/deep.py's meshes on this device (ReplicatedStorage.Art.Deep, the deep art pass
-- 2026-11-19): the commuters' air bubble (DeepClient), the Torpedo Sentry's torpedo (CombatFx) and the divers'
-- helmet and tank (EnemyRenderer finds those itself by name). A copy keeps its SurfaceAppearance (the baked maps)
-- and never collides, takes queries or touches. Not imported: nil, and the caller keeps today's parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local DeepArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DeepArtKit"))
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))

local DeepMeshes = {}

local found: { [string]: MeshPart } = {}

-- The source MeshPart named `name` in Art.Deep (looked up each time until there, so a later import counts)
function DeepMeshes.source(name: string): MeshPart?
	local hit = found[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local root = art and art:FindFirstChild("Deep")
	local src = root and root:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		found[name] = src
		return src
	end
	return nil
end

-- A copy of the mesh at `size` (studs), or nil when it is not imported
function DeepMeshes.clone(name: string, size: Vector3): MeshPart?
	local src = DeepMeshes.source(name)
	if not src then
		return nil
	end
	local p = MeshFix.clone(src)
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceAppearance") then
			c.AlphaMode = Enum.AlphaMode.Overlay
		else
			c:Destroy()
		end
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Size = size
	return p
end

-- A whole look (every mesh, or nil when any is missing) in a box of `size` studs at `cf`, each mesh with its fit
-- colour, material and transparency (Config.DeepArt); returns the meshes by name
function DeepMeshes.look(look: string, size: Vector3, cf: CFrame, parent: Instance): { [string]: MeshPart }?
	if
		not DeepArtKit.ready(Config, look, function(n: string): boolean
			return DeepMeshes.source(n) ~= nil
		end)
	then
		return nil
	end
	local place = { look = look, cx = 0, cy = 0, cz = 0, sx = size.X, sy = size.Y, sz = size.Z }
	local out = {}
	for _, m in DeepArtKit.meshes(Config, place) do
		local p = DeepMeshes.clone(m.name, Vector3.new(m.size[1], m.size[2], m.size[3])) :: MeshPart
		p.Name = m.name
		p.CFrame = cf * CFrame.new(m.offset[1], m.offset[2], m.offset[3]) * MeshFix.of(p) -- the import's turn
		p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[m.mat]
		end)
		p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
		p.Transparency = m.alpha
		p.Parent = parent
		out[m.name] = p
	end
	return out
end

return DeepMeshes
