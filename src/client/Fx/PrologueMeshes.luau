--!strict
-- PrologueMeshes: the Ceremony prologue's Blender meshes on this device (gap-prologue, 2026-11-19): art/blender/
-- prologue.py's looks from ReplicatedStorage.Art.Prologue, placed over the plain parts PrologueFx builds
-- (Shared.PrologueArtKit says which looks are ready and where each mesh sits). The meshes never collide, take
-- queries or touches; the parts they stand for stay (hidden) and do all of that exactly as before. A look whose
-- meshes are not all imported is not drawn, and its parts show as today.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PrologueArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PrologueArtKit"))

local PrologueMeshes = {}

local found: { [string]: MeshPart } = {}

-- The source MeshPart named `name` in Art.Prologue (looked up each time until there, so a late load counts)
local function source(name: string): MeshPart?
	local hit = found[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Prologue")
	local src = set and set:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		found[name] = src
		return src
	end
	return nil
end

function PrologueMeshes.has(name: string): boolean
	return source(name) ~= nil
end

-- Is every mesh of this look imported?
function PrologueMeshes.ready(look: string): boolean
	return PrologueArtKit.ready(Config, look, PrologueMeshes.has)
end

-- A plain part a drawn look stands in for: unseen, but it still collides, takes queries and stays where it is
function PrologueMeshes.hide(p: BasePart?)
	if not p then
		return
	end
	p.Transparency = 1
	p.CastShadow = false
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceGui") or c:IsA("Decal") then
			c:Destroy()
		end
	end
end

-- One look's meshes under parent with its frame's centre at cf; `weld` (the frame's part) makes them follow that
-- part as it moves (the scanner's bob, the sign's fall, the slab's drop); `skip` leaves out meshes by name (the
-- light beams on the phone preset). Returns the meshes (empty when the look is not ready).
function PrologueMeshes.add(
	parent: Instance,
	look: string,
	cf: CFrame,
	weld: BasePart?,
	skip: { [string]: boolean }?
): { MeshPart }
	local out = {}
	if not PrologueMeshes.ready(look) then
		return out
	end
	for _, m in PrologueArtKit.meshes(Config, look) do
		local src = source(m.name)
		if not src or (skip and skip[m.name]) then
			continue
		end
		local p = src:Clone()
		-- a textured mesh keeps its SurfaceAppearance (the baked colour, normal, roughness and metal maps; opaque,
		-- so the part colour underneath never shows); anything else goes
		for _, c in p:GetChildren() do
			if m.maps and c:IsA("SurfaceAppearance") then
				c.AlphaMode = Enum.AlphaMode.Overlay
			else
				c:Destroy()
			end
		end
		p.Name = m.name
		p.Anchored = weld == nil
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Size = Vector3.new(m.size[1], m.size[2], m.size[3])
		p.CFrame = cf * CFrame.new(m.offset[1], m.offset[2], m.offset[3])
		p.Color = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[m.mat]
		end)
		p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
		p.Transparency = m.alpha
		p.CastShadow = m.mat ~= "Neon" and m.alpha == 0
		if weld then
			local w = Instance.new("WeldConstraint")
			w.Part0 = weld
			w.Part1 = p
			w.Parent = p
		end
		p.Parent = parent
		table.insert(out, p)
	end
	return out
end

return PrologueMeshes
