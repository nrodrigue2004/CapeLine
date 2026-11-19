--!strict
-- StoryProps: a mission's props in their Blender looks on this device (gap-story, 2026-11-19; art/blender/story.py,
-- imported as ReplicatedStorage.Art.Story; Shared.StoryArtKit). MissionService builds every break target and the
-- runaway train from plain parts exactly as before and tags the model with its look (the StoryLook attribute). Twice
-- a second (from StoryFx) this module dresses the nearest tagged models within the preset's budget
-- (Config.Presets.<preset>.story: radius and looks; phones start on low): the look's meshes are welded to the model's
-- Root, so the train carries its look as it runs, and the model's own parts are hidden on this device only
-- (LocalTransparencyModifier). The meshes never collide, take queries or touches; the server's parts and combat
-- targets work exactly as before. A look is drawn only once every one of its meshes is imported; otherwise, out of
-- budget or out of range, today's parts show. clone() is StoryFx's too (the trap, the beacon, the Echo Drone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local StoryArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoryArtKit"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local StoryProps = {}

local found: { [string]: MeshPart } = {}

local function source(name: string): MeshPart?
	local hit = found[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local root = art and art:FindFirstChild("Story")
	local src = root and root:FindFirstChild(name, true)
	if src and src:IsA("MeshPart") then
		found[name] = src
		return src
	end
	return nil
end

function StoryProps.has(name: string): boolean
	return source(name) ~= nil
end

function StoryProps.ready(look: string): boolean
	return StoryArtKit.ready(Config, look, StoryProps.has)
end

-- A mesh clone: never collides, keeps a baked texture set (its colour map's alpha shows the part colour below)
function StoryProps.clone(m: StoryArtKit.Mesh): MeshPart?
	local src = source(m.name)
	if not src then
		return nil
	end
	local p = src:Clone()
	for _, c in p:GetChildren() do
		if m.maps and c:IsA("SurfaceAppearance") then
			c.AlphaMode = Enum.AlphaMode.Overlay
		else
			c:Destroy()
		end
	end
	p.Name = m.name
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
	return p
end

-- Every mesh of a look welded to `anchor` (the look's frame middle sits `lift` studs over the anchor's centre);
-- returns them by name, or nil when the look is not ready
function StoryProps.weld(
	look: string,
	anchor: BasePart,
	lift: number,
	parent: Instance
): { [string]: MeshPart }?
	if not StoryProps.ready(look) then
		return nil
	end
	local out = {}
	for _, mesh in StoryArtKit.meshes(Config, look) do
		local p = StoryProps.clone(mesh)
		if p then
			local off = CFrame.new(mesh.offset[1], mesh.offset[2] + lift, mesh.offset[3])
			p.Anchored = false
			p.CFrame = anchor.CFrame * off
			local w = Instance.new("Weld")
			w.Part0 = anchor
			w.Part1 = p
			w.C0 = off
			w.Parent = p
			p.Parent = parent
			out[mesh.name] = p
		end
	end
	return out
end

type Dressed = { meshes: { BasePart }, hidden: { BasePart }, conns: { RBXScriptConnection } }

local dressed: { [Model]: Dressed } = {}
local folder: Folder? = nil

local function holder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "StoryArt"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

local function undress(m: Model)
	local d = dressed[m]
	if not d then
		return
	end
	dressed[m] = nil
	for _, c in d.conns do
		c:Disconnect()
	end
	for _, p in d.meshes do
		p:Destroy()
	end
	for _, p in d.hidden do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
end

local function hide(d: Dressed, p: Instance)
	if p:IsA("BasePart") and p.Name ~= "Root" then
		p.LocalTransparencyModifier = 1
		table.insert(d.hidden, p)
	end
end

local function dress(m: Model, look: string, root: BasePart)
	-- the Root is the model's foot (SiteKit.object): the look's frame middle is half its height above it
	local meshes = StoryProps.weld(look, root, StoryArtKit.middle(Config, look), holder())
	if not meshes then
		return
	end
	local d: Dressed = { meshes = {}, hidden = {}, conns = {} }
	for _, p in meshes do
		table.insert(d.meshes, p)
	end
	for _, p in m:GetDescendants() do
		hide(d, p)
	end
	table.insert(
		d.conns,
		m.DescendantAdded:Connect(function(p)
			hide(d, p)
		end)
	)
	table.insert(
		d.conns,
		root.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				undress(m)
			end
		end)
	)
	dressed[m] = d
end

-- (2 Hz from StoryFx, under its FrameProf scope)
function StoryProps.step()
	local budget = QualityController.preset.story
	local sites = Workspace:FindFirstChild("Sites")
	local cam = Workspace.CurrentCamera
	if not budget or not cam then
		return
	end
	local at = cam.CFrame.Position
	local cands = {}
	for _, m in if sites then sites:GetChildren() else {} do
		local look = m:IsA("Model") and m:GetAttribute("StoryLook")
		local root = if look then m:FindFirstChild("Root") else nil
		if type(look) == "string" and root and root:IsA("BasePart") and StoryProps.ready(look) then
			-- a dressed prop holds its place a little farther out, so it does not flicker at the edge
			local dist = (root.Position - at).Magnitude * (if dressed[m :: Model] then 0.87 else 1)
			if dist <= budget.radius then
				table.insert(cands, { m = m :: Model, look = look, root = root, dist = dist })
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.dist < b.dist
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(#cands, budget.looks) do
		keep[cands[i].m] = true
	end
	for m in dressed do
		if not keep[m] or not m.Parent then
			undress(m)
		end
	end
	for i = 1, math.min(#cands, budget.looks) do
		local c = cands[i]
		if not dressed[c.m] then
			dress(c.m, c.look, c.root)
		end
	end
end

return StoryProps
