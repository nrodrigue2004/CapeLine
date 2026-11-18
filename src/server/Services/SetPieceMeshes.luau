--!strict
-- SetPieceMeshes: the side quests' set pieces drawn with art/blender/setpieces.py's meshes once nate imports them
-- as ReplicatedStorage.Art.SetPieces (Tasks.md "Set piece meshes"). Shared.SetPieceKit says which placements are
-- drawn (every mesh of the look found) and Config.SetPieceArt how each mesh sits; this module finds and clones
-- them. Used by SideQuestService (the gala, the racers' meet, the farm truck) and MissionService (the toy shop,
-- sea cave, fight pit and Velmara pockets). The meshes never collide, take queries or touches: the boxes they
-- stand in for stay (hidden) and do all of that exactly as before. No Art.SetPieces: nothing is drawn and every
-- box shows as today (PLACEHOLDER ART until the import).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SetPieceKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SetPieceKit"))

local SetPieceMeshes = {}

local found: { [string]: MeshPart } = {}

-- The imported model, or nil (looked up each time until it is there, so a later import still counts)
local function root(): Instance?
	local art = ReplicatedStorage:FindFirstChild("Art")
	return art and art:FindFirstChild("SetPieces")
end

-- The source MeshPart named `name`, or nil
local function source(name: string): MeshPart?
	local hit = found[name]
	if hit and hit.Parent then
		return hit
	end
	local r = root()
	if not r then
		return nil
	end
	local src = r:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		found[name] = src
		return src
	end
	return nil
end

function SetPieceMeshes.has(name: string): boolean
	return source(name) ~= nil
end

-- The placements of a set or pocket drawn as meshes (index -> true; empty before the import)
function SetPieceMeshes.drawn(places: { SetPieceKit.Place }?): { [number]: boolean }
	return SetPieceKit.drawn(Config, places, SetPieceMeshes.has)
end

-- Is every mesh of this look imported?
function SetPieceMeshes.ready(look: string): boolean
	return SetPieceKit.ready(Config, look, SetPieceMeshes.has)
end

-- A box a drawn look stands in for: unseen, but it still collides, takes queries and stays in its piece
function SetPieceMeshes.hide(p: BasePart)
	p.Transparency = 1
	p.CastShadow = false
	for _, gui in p:GetChildren() do
		if gui:IsA("SurfaceGui") then
			gui.Enabled = false
		end
	end
end

-- One placement's meshes under parent, with the placement's foot at cf (turned already); returns them
function SetPieceMeshes.add(parent: Instance, place: SetPieceKit.Place, cf: CFrame): { MeshPart }
	local out = {}
	for _, m in SetPieceKit.meshes(Config, place) do
		local src = source(m.name)
		if src then
			local p = src:Clone()
			for _, c in p:GetChildren() do
				c:Destroy()
			end
			p.Name = m.name
			p.Anchored = true
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
			p.Parent = parent
			table.insert(out, p)
		end
	end
	return out
end

-- The turn of a placement about up
function SetPieceMeshes.yaw(place: SetPieceKit.Place): CFrame
	return CFrame.Angles(0, math.rad(place.ry or 0), 0)
end

return SetPieceMeshes
