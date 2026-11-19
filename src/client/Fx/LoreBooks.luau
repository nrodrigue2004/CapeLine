-- LoreBooks: builds Shared.LoreBookKit's pieces as parts (side-content, 2026-11-19): the lore page's open book
-- (Controllers.LoreClient) and the HQ's Lore Shelf (Controllers.HqClient, prop 23). One builder, so the device draws
-- what art/blender/lorebook.py renders. PLACEHOLDER ART: parts until a sculpted Blender book mesh is uploaded.

local LoreBooks = {}

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
		if p.shape == "wedge" then
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
