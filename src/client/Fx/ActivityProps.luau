--!strict
-- ActivityProps: the open-world activities' props drawn in their Blender looks on this device (2026-11-19, the props
-- gap; art/blender/activity.py, imported as ReplicatedStorage.Art.Activity; the tram and the escort truck reuse
-- Art.Vehicles). The server builds every prop from plain parts and tags its model with the Look attribute
-- (SiteKit.look; Shared.ActivityKit.KINDS). Twice a second this module looks over Workspace.Sites and dresses the
-- nearest tagged props within the preset's budget (Config.Presets.<preset>.sites: radius, looks, mesh parts; phones
-- start on low): the look's meshes are welded to the prop's anchor part, so a driving tram, a flying airship or a
-- falling billboard carries them, and the prop's own parts are hidden on this device only
-- (LocalTransparencyModifier), except the ones the kind keeps (a ring's coloured disc). The meshes never collide,
-- take queries or touches; the server's parts, targets, rings and prompts work exactly as before. A look is drawn
-- only once every one of its meshes is imported; otherwise, out of budget or out of range, today's parts show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ActivityKit = require(Shared:WaitForChild("ActivityKit"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local StoryProps = require(script.Parent.StoryProps)

local ActivityProps = {}

local ROOTS = { "Activity", "Vehicles" }
local found: { [string]: MeshPart } = {}

local function source(name: string): MeshPart?
	local hit = found[name]
	if hit and hit.Parent then
		return hit
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	for _, r in ROOTS do
		local root = art and art:FindFirstChild(r)
		local src = root and root:FindFirstChild(name, true)
		if src and src:IsA("MeshPart") then
			found[name] = src
			return src
		end
	end
	return nil
end

function ActivityProps.has(name: string): boolean
	return source(name) ~= nil
end

function ActivityProps.ready(look: string): boolean
	return ActivityKit.ready(Config, look, ActivityProps.has)
end

-- A mesh clone: never collides, keeps a baked texture set (its colour map's alpha shows the part colour below)
function ActivityProps.clone(m: ActivityKit.Mesh): MeshPart?
	local src = source(m.name)
	if not src then
		return nil
	end
	local p = MeshFix.clone(src)
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

type Dressed = {
	model: Model,
	kind: ActivityKit.Kind,
	meshes: { BasePart },
	hidden: { BasePart },
	conns: { RBXScriptConnection },
}

local dressed: { [Model]: Dressed } = {}
local folder: Folder? = nil

local function holder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ActivityArt"
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
	if p:IsA("BasePart") and ActivityKit.hides(d.kind, p.Name) then
		p.LocalTransparencyModifier = 1
		table.insert(d.hidden, p)
	end
end

local function dress(m: Model, kind: ActivityKit.Kind, anchor: BasePart)
	local d: Dressed = { model = m, kind = kind, meshes = {}, hidden = {}, conns = {} }
	local rest: { [Weld]: CFrame } = {} -- each weld's resting C0, for the hit punch
	local scale = m:GetAttribute("LookScale")
	for _, mesh in ActivityKit.meshes(Config, kind, if type(scale) == "number" then scale else 1) do
		local p = ActivityProps.clone(mesh)
		if p then
			if mesh.tintFrom then
				local from = m:FindFirstChild(mesh.tintFrom, true)
				if from and from:IsA("BasePart") then
					p.Color = from.Color
				end
			end
			local off = CFrame.new(mesh.offset[1], mesh.offset[2], mesh.offset[3])
			local fix = MeshFix.of(p) -- the import's own turn (Shared.MeshFix), held by the weld's C1
			p.Anchored = false
			p.CFrame = anchor.CFrame * off * fix
			local w = Instance.new("Weld")
			w.Part0 = anchor
			w.Part1 = p
			w.C0 = off
			w.C1 = fix:Inverse()
			w.Parent = p
			p.Parent = holder()
			table.insert(d.meshes, p)
			rest[w] = off
		end
	end
	for _, p in m:GetDescendants() do
		hide(d, p)
	end
	-- a breakable (an incident's or event's object, SiteKit.object's Hp): each hit jolts the look and springs it back
	-- with a clank (list-combat 2026-11-20; they took hits without a twitch)
	local hp = m:GetAttribute("Hp")
	local last = if type(hp) == "number" then hp else 1
	table.insert(
		d.conns,
		m:GetAttributeChangedSignal("Hp"):Connect(function()
			local now = m:GetAttribute("Hp")
			if type(now) == "number" then
				if now < last then
					StoryProps.punch(rest, anchor.Position)
				end
				last = now
			end
		end)
	)
	-- parts streaming in later hide too; the anchor going (streamed out or removed) takes the look with it
	table.insert(
		d.conns,
		m.DescendantAdded:Connect(function(p)
			hide(d, p)
		end)
	)
	table.insert(
		d.conns,
		anchor.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				undress(m)
			end
		end)
	)
	dressed[m] = d
end

local function meshCount(kind: ActivityKit.Kind): number
	local fit = ActivityKit.fit(Config, kind.look)
	local n = 0
	for _ in fit or {} do
		n += 1
	end
	return n
end

local function scan()
	local budget = QualityController.preset.sites
	local sites = Workspace:FindFirstChild("Sites")
	local cam = Workspace.CurrentCamera
	if not budget or not cam then
		return
	end
	local at = cam.CFrame.Position
	local cands = {}
	local info: { [Model]: { kind: ActivityKit.Kind, anchor: BasePart } } = {}
	for _, m in if sites then sites:GetChildren() else {} do
		if m:IsA("Model") then
			local kind = ActivityKit.kind(m:GetAttribute("Look"))
			local anchor = kind and m:FindFirstChild(kind.on or "Root")
			if kind and anchor and anchor:IsA("BasePart") and ActivityProps.ready(kind.look) then
				info[m] = { kind = kind, anchor = anchor }
				-- a dressed prop holds its place a little farther out, so it does not flicker at the edge
				local dist = (anchor.Position - at).Magnitude * (if dressed[m] then 0.87 else 1)
				table.insert(cands, { id = m, dist = dist, meshes = meshCount(kind) })
			end
		end
	end
	local keep = ActivityKit.pick(cands, budget)
	for m in dressed do
		if not keep[m] or not m.Parent then
			undress(m)
		end
	end
	for m in keep do
		if not dressed[m] then
			local i = info[m :: Model]
			dress(m :: Model, i.kind, i.anchor)
		end
	end
end

-- (2 Hz from ActivityFx's heartbeat, under its FrameProf scope)
function ActivityProps.step()
	scan()
end

return ActivityProps
