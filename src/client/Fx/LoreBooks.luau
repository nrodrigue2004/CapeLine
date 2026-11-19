-- LoreBooks: builds Shared.LoreBookKit's pieces as parts (side-content, 2026-11-19): the lore page's open book
-- (Controllers.LoreClient) and the HQ's Lore Shelf (Controllers.HqClient, prop 23). One builder, so the device draws
-- what art/blender/lorebook.py renders. Since 2026-11-19 (living-world) each piece wears its sculpted Blender mesh
-- (Shared.LoreBookKit.meshOf, ReplicatedStorage.Art.LoreBook from art/blender/lorebooks.py) in the part's own box,
-- once every mesh is imported (all or nothing); else the parts as before.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LoreBookKit = require(Shared:WaitForChild("LoreBookKit"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))

local LoreBooks = {}

-- the imported meshes by name, or nil until every one is there
local found: { [string]: MeshPart }? = nil
local function meshes(): { [string]: MeshPart }?
	if found then
		return found
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("LoreBook")
	if not set then
		return nil
	end
	local out: { [string]: MeshPart } = {}
	for _, name in LoreBookKit.MESHES do
		local src = set:FindFirstChild(name, true)
		if not (src and src:IsA("MeshPart")) then
			return nil
		end
		out[name] = src
	end
	found = out
	return out
end

local SHAPES = {
	block = Enum.PartType.Block,
	cylinder = Enum.PartType.Cylinder,
	ball = Enum.PartType.Ball,
}
local MATERIALS = {
	plastic = Enum.Material.SmoothPlastic,
	neon = Enum.Material.Neon,
	metal = Enum.Material.Metal,
	fabric = Enum.Material.Fabric,
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Every piece as an anchored, non-colliding part under `parent`, placed from `cf` (the pieces' origin); `colors`
-- maps a piece's colour key to { r, g, b } and `pick(key)` answers keys it does not hold ("book:<district>").
-- Returns the parts by piece name (the last of a name wins).
function LoreBooks.build(
	parent: Instance,
	pieces: { any },
	colors: { [string]: { number } },
	cf: CFrame,
	pick: ((string) -> { number }?)?
): { [string]: BasePart }
	local out: { [string]: BasePart } = {}
	for _, p in pieces do
		local part: BasePart
		local have = meshes()
		local mesh = LoreBookKit.meshOf(p.name)
		local src = have and mesh and have[mesh]
		if src then
			local m = MeshFix.clone(src)
			for _, c in m:GetChildren() do
				c:Destroy()
			end
			part = m
		elseif p.shape == "wedge" then
			part = Instance.new("WedgePart")
		else
			local q = Instance.new("Part")
			q.Shape = SHAPES[p.shape] or Enum.PartType.Block
			part = q
		end
		part.Name = p.name
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		part.CFrame = cf
			* CFrame.new(p.pos[1], p.pos[2], p.pos[3])
			* CFrame.fromEulerAnglesYXZ(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
			* MeshFix.of(part) -- the import's turn (identity for a part)
		local c = colors[p.color] or (pick and pick(p.color)) or { 255, 205, 90 }
		part.Color = rgb(c)
		part.Material = MATERIALS[p.material] or Enum.Material.SmoothPlastic
		part.Transparency = p.alpha or 0
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = p.material ~= "neon"
		part.Parent = parent
		out[p.name] = part
	end
	return out
end

return LoreBooks
