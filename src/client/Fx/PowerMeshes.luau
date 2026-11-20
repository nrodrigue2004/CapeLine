-- PowerMeshes (list-combat 2026-11-20, Everything Left 168-182 and 290): the power summons, rides and forms in
-- their Blender looks (art/blender/powers.py, ReplicatedStorage.Art.Powers, Config.PowerArt): Turret Drop's turret,
-- the Fix-It Drone (and the repair drones), Ward Totem, Shock Mines, the spirit guardian, Spirit Ride's spirit wolf,
-- the Hoverboard, Rock Ride's slab, Stone Pillar's basalt columns, Overgrowth's thorn vines, the Tsunami's wave and
-- the Mech Suit's shell. A look is drawn only once every one of its meshes is imported (else the old part build
-- stays, PLACEHOLDER ART). Meshes marked tint take the caster's path colour. Client only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))

local PowerMeshes = {}

local ART = Config.PowerArt
local found: { [string]: MeshPart } = {}

local function source(name: string): MeshPart?
	local hit = found[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Powers")
	local src = set and set:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		found[name] = src
		return src
	end
	return nil
end

-- Is every mesh of this look imported?
function PowerMeshes.ready(look: string): boolean
	local row = ART[look]
	if not row then
		return false
	end
	for name in row do
		if not source(name) then
			return false
		end
	end
	return true
end

-- One mesh, ready to place: no collision, queries or touches, its import turn baked in by the caller (MeshFix.of)
function PowerMeshes.part(name: string, size: Vector3?): MeshPart?
	local src = source(name)
	if not src then
		return nil
	end
	local p = MeshFix.clone(src)
	for _, c in p:GetChildren() do
		c:Destroy()
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	if size then
		p.Size = size
	end
	return p
end

-- A look as pieces in CombatFx's rig format: { size, cframe from the rig's base (the anchor, the mesh offset and
-- the import turn), colour, nil, transparency, material, mesh name }. scale grows the whole look about its anchor
-- (a number, or a Vector3 to stretch it: the Tsunami's wave to the line's width).
function PowerMeshes.pieces(look: string, anchor: CFrame, tint: Color3?, scale: (number | Vector3)?): { any }
	local out = {}
	local k: Vector3 = if typeof(scale) == "Vector3" then scale else Vector3.one * ((scale :: number?) or 1)
	local names = {}
	for name in ART[look] do
		table.insert(names, name)
	end
	table.sort(names) -- the same order on every device
	for _, name in names do
		local m = ART[look][name]
		local color = if m.tint and tint then tint else Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[m.mat]
		end)
		table.insert(out, {
			Vector3.new(m.size[1], m.size[2], m.size[3]) * k,
			anchor * CFrame.new(Vector3.new(m.offset[1], m.offset[2], m.offset[3]) * k) * MeshFix.turn(
				"Powers"
			),
			color,
			nil,
			m.alpha or 0,
			if ok and mat then mat else Enum.Material.SmoothPlastic,
			name,
		})
	end
	return out
end

-- A finished part for one piece (a mesh when it is imported, else nil: the caller builds its part)
function PowerMeshes.make(pc: { any }, parent: Instance?): MeshPart?
	local name = pc[7]
	if not name then
		return nil
	end
	local p = PowerMeshes.part(name, pc[1])
	if not p then
		return nil
	end
	p.Color = pc[3]
	p.Transparency = pc[5] or 0
	p.Material = pc[6] or Enum.Material.SmoothPlastic
	p.CFrame = pc[2]
	p.Parent = parent
	return p
end

return PowerMeshes
