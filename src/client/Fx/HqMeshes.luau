--!strict
-- HqMeshes: the HQ rooms dressed in art/blender/hq.py's meshes, imported as ReplicatedStorage.Art.Hq (and the room
-- shells as Art.Hideout, Shared.HideoutKit; both with baked texture sets kept as their SurfaceAppearance)
-- (Tasks.md "HQ meshes"). Shared.HqArtKit says where each look goes and Config.HqArt how each mesh sits; this
-- module finds and clones them for HqClient (the HQ is drawn on the device only). A look is drawn only when every
-- one of its meshes is found (never half a look); the part it stands in for is hidden, not removed, so its
-- prompt, sign and SurfaceGui (the WANTED poster, the head plates, the "?" of an empty mount) work exactly as
-- before. The meshes never collide, take queries or touches. Nothing imported: nothing is drawn and every part
-- shows as today.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SetPieceKit = require(Shared:WaitForChild("SetPieceKit"))
local HqArtKit = require(Shared:WaitForChild("HqArtKit"))

local HqMeshes = {}

local found: { [string]: MeshPart } = {}
-- the stations, props and dressing (art/blender/hq.py) and the room shells (the hideout art pass: Art.Hideout)
local ROOTS = { "Hq", "Hideout" }

-- The source MeshPart named `name` in Art.Hq (looked up each time until there, so a later import counts)
local function source(name: string): MeshPart?
	local hit = found[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	for _, set in ROOTS do
		local root = art and art:FindFirstChild(set)
		local src = root and root:FindFirstChild(name, true)
		if src and src:IsA("MeshPart") then
			found[name] = src
			return src
		end
	end
	return nil
end

function HqMeshes.has(name: string): boolean
	return source(name) ~= nil
end

-- Is every mesh of this look imported?
function HqMeshes.ready(look: string): boolean
	return SetPieceKit.ready(Config, look, HqMeshes.has)
end

-- A part a drawn look stands in for: unseen, but its prompt, sign and SurfaceGuis stay
function HqMeshes.hide(p: BasePart)
	p.Transparency = 1
	p.CastShadow = false
end

local function clone(m: SetPieceKit.Mesh, parent: Instance): MeshPart?
	local src = source(m.name)
	if not src then
		return nil
	end
	local p = (src :: MeshPart):Clone() :: MeshPart
	-- a textured mesh keeps its SurfaceAppearance (the baked texture set; the colour map's alpha shows the part's
	-- Color below, so a tint still paints it); anything else goes
	for _, c in p:GetChildren() do
		if m.maps and c:IsA("SurfaceAppearance") then
			pcall(function()
				c.AlphaMode = Enum.AlphaMode.Overlay
			end)
		else
			c:Destroy()
		end
	end
	p.Name = m.name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Size = Vector3.new(m.size[1], m.size[2], m.size[3])
	p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
	local ok, mat = pcall(function()
		return (Enum.Material :: any)[m.mat]
	end)
	p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
	p.Transparency = m.alpha
	p.CastShadow = m.mat ~= "Neon" and m.alpha == 0
	p.Parent = parent
	return p
end

-- A placed look under parent with its foot at cf (turned already; `tint` mesh name -> { r, g, b }). Returns
-- whether it was drawn (false: not imported, keep today's parts).
function HqMeshes.place(parent: Instance, look: string, cf: CFrame, tint: { [string]: { number } }?): boolean
	if not HqMeshes.ready(look) then
		return false
	end
	for _, m in SetPieceKit.meshes(Config, { look = look, x = 0, y = 0, z = 0, tint = tint }) do
		local p = clone(m, parent)
		if p then
			p.CFrame = cf * CFrame.new(m.offset[1], m.offset[2], m.offset[3])
		end
	end
	return true
end

-- A placement (SetPieceKit.Place, cell offsets; with a `scale`: a HideoutKit module) under parent, the cell's
-- middle at `base`. Returns whether it was drawn (false: not imported).
function HqMeshes.put(parent: Instance, place: SetPieceKit.Place, base: Vector3): boolean
	if not HqMeshes.ready(place.look) then
		return false
	end
	local cf = CFrame.new(base + Vector3.new(place.x, place.y, place.z))
		* CFrame.Angles(0, math.rad(place.ry or 0), 0)
	for _, m in SetPieceKit.meshes(Config, place) do
		local p = clone(m, parent)
		if p then
			p.CFrame = cf * CFrame.new(m.offset[1], m.offset[2], m.offset[3])
		end
	end
	return true
end

-- A shape (HqArtKit.SHAPES) stretched over part `p`, which it hides: the first mesh takes the part's colour,
-- material and transparency (a nemesis piece in its colours, the dummy's eye in its glow), the others keep
-- their own (the target's white rings, the base's bolts). An anchored part's meshes are anchored where it is
-- (a ViewportFrame never simulates); a rig's part's are welded to it. Returns whether it was drawn.
function HqMeshes.cover(p: BasePart, shape: string): boolean
	local sh = HqArtKit.SHAPES[shape]
	if not sh or not HqMeshes.ready(sh.look) then
		return false
	end
	local list = HqArtKit.fill(Config, shape, { p.Size.X, p.Size.Y, p.Size.Z })
	if #list == 0 then
		return false
	end
	local parent = p.Parent :: Instance
	for i, m in list do
		local mp = clone(m, parent)
		if mp then
			if i == 1 then
				mp.Color = p.Color
				mp.Material = p.Material
				mp.Transparency = p.Transparency
				mp.CastShadow = p.Material ~= Enum.Material.Neon and p.Transparency == 0
			end
			local off = CFrame.new(m.offset[1], m.offset[2], m.offset[3])
			if p.Anchored then
				mp.CFrame = p.CFrame * off
			else
				mp.Anchored = false
				mp.CFrame = p.CFrame * off
				local w = Instance.new("Weld")
				w.Part0 = p
				w.Part1 = mp
				w.C0 = off
				w.Parent = mp
			end
		end
	end
	HqMeshes.hide(p)
	return true
end

return HqMeshes
