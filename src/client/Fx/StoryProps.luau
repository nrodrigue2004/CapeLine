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
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local StoryArtKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoryArtKit"))
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)

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
			-- the box's centre, then the import's own turn (Shared.MeshFix), held by the weld's C1
			local fix = MeshFix.of(p)
			p.CFrame = anchor.CFrame * off * fix
			local w = Instance.new("Weld")
			w.Part0 = anchor
			w.Part1 = p
			w.C0 = off
			w.C1 = fix:Inverse()
			w.Parent = p
			p.Parent = parent
			out[mesh.name] = p
		end
	end
	return out
end

type Dressed = {
	meshes: { BasePart },
	hidden: { BasePart },
	conns: { RBXScriptConnection },
	hp: number, -- the target's share of hits left (its Hp attribute, SiteKit.object)
	rest: { [Weld]: CFrame }, -- each mesh weld's resting C0, for the hit punch
	broken: boolean?, -- burst apart: its meshes are gone and its parts stay hidden
}

local dressed: { [Model]: Dressed } = {}
local gone: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- broken targets hidden here
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

-- A hit lands on a break target (list-combat 2026-11-20: they took their hits without a twitch): the look jolts off
-- its rest and springs back, with a clank where it was hit
local PUNCH = 0.6 -- studs of jolt at full; less on a big look
-- (ActivityProps punches its dressed incident and event objects the same way)
function StoryProps.punch(welds: { [Weld]: CFrame }, at: Vector3)
	local n = 0
	for w, rest in welds do
		n += 1
		local kick = Vector3.new(math.random() - 0.5, math.random() * 0.4, math.random() - 0.5) * PUNCH
		w.C0 = rest * CFrame.new(kick) * CFrame.Angles(kick.Z * 0.12, 0, -kick.X * 0.12)
		TweenService:Create(w, TweenInfo.new(0.22, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			C0 = rest,
		}):Play()
	end
	if n > 0 then
		AudioController.play("clank", at, { volume = 0.6 })
	end
end

-- The last hit: the look's meshes burst apart and tumble (loose, never colliding), fading out in about a second and
-- a half, instead of the look just vanishing with the target
local function shatter(d: Dressed, at: Vector3)
	for _, p in d.meshes do
		if p.Parent then
			for _, w in p:GetChildren() do
				if w:IsA("Weld") then
					w:Destroy()
				end
			end
			local out = p.Position - at
			out = if out.Magnitude > 0.1 then out.Unit else Vector3.yAxis
			p.Anchored = false
			p.AssemblyLinearVelocity = out * (14 + math.random() * 10)
				+ Vector3.new(0, 14 + math.random() * 8, 0)
			p.AssemblyAngularVelocity = Vector3.new(
				math.random() - 0.5,
				math.random() - 0.5,
				math.random() - 0.5
			) * 8
			TweenService
				:Create(
					p,
					TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9),
					{
						Transparency = 1,
					}
				)
				:Play()
			task.delay(1.6, function()
				p:Destroy()
			end)
		end
	end
	AudioController.play("shatter", at, { volume = 0.8 })
end

-- the vehicles stay whole when beaten (the runaway train stops, the cash van is cracked open by the story)
local STAYS = { StoryTrain = true, StoryVan = true }

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
	if d.broken then
		return -- what is left of a broken target stays hidden until the server clears it
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
	local hp = m:GetAttribute("Hp")
	local d: Dressed =
		{ meshes = {}, hidden = {}, conns = {}, hp = if type(hp) == "number" then hp else 1, rest = {} }
	for _, p in meshes do
		table.insert(d.meshes, p)
		local w = p:FindFirstChildOfClass("Weld")
		if w then
			d.rest[w] = w.C0
		end
	end
	table.insert(
		d.conns,
		m:GetAttributeChangedSignal("Hp"):Connect(function()
			local now = m:GetAttribute("Hp")
			if type(now) == "number" and now < d.hp and (now > 0 or STAYS[look]) then
				StoryProps.punch(d.rest, root.Position)
			elseif type(now) == "number" and now <= 0 and not d.broken then
				-- the last hit: the look bursts apart at once (the server keeps the broken target until the step ends)
				d.broken = true
				shatter(d, root.Position)
				d.meshes = {}
				d.rest = {}
			end
			if type(now) == "number" then
				d.hp = now
			end
		end)
	)
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
		local hp = if look then m:GetAttribute("Hp") else nil
		if type(hp) == "number" and hp <= 0 and not STAYS[look :: any] then
			-- broken: gone from view on this device (a dressed one burst apart; plain parts just go)
			if not dressed[m :: Model] and not gone[m :: Model] then
				gone[m :: Model] = true
				for _, p in m:GetDescendants() do
					if p:IsA("BasePart") then
						p.LocalTransparencyModifier = 1
					end
				end
			end
			continue
		end
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
