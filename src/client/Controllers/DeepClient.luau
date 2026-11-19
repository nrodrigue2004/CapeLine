-- DeepClient: the underwater areas on this device (Config.Deep; nate 2026-11-16: underwater at launch).
-- * Under the surface the camera gets a blue tint that darkens with depth and a short fog (on top of the
--   Terrain water's own look), and a moving hero trails bubbles.
-- * Entering an area names it once ("The Sunken Line").
-- * Sunken cargo caches glow and carry a marker until this hero opens them (then a countdown); trapped
--   commuters wait in their air pockets and hold on to whoever carries them (DeepState from the server).
-- The positions come from Shared.DeepLayout, the same data the server builds the world from.
-- The deep art pass (2026-11-19): a cache's marker is a drawn comic burst (Config.Deep.art.marker, the old text
-- label until uploaded); a commuter is a Roblox-body person (NpcRig: catalog face and hair, the citizens' clothes)
-- treading water in an air bubble (Art.Deep's AirBubble, a glass ball until imported); kelp near the camera sways
-- about its foot and caustic light shimmers on the floor of the lit water, both by preset (Config.Deep.art) and
-- under FrameProf.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))
local DeepArtKit = require(Shared:WaitForChild("DeepArtKit"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))
local CollectionService = game:GetService("CollectionService")

local Toasts = require(script.Parent.Parent.Ui.Toasts)
local QualityController = require(script.Parent.QualityController)
local DeepMeshes = require(script.Parent.Parent.Fx.DeepMeshes)

local DeepClient = {}

local D = Config.Deep
local L = D.look
local layout: any = nil
local folder: Folder
local tint: ColorCorrectionEffect? = nil
local saved: { [string]: any } = {}
local lastArea: string? = nil
local caches: { [number]: { part: BasePart, label: TextLabel, burst: ImageLabel? } } = {}
local A = D.art
local commuters: { [number]: Model } = {}
DeepClient.state = { opened = {}, rescues = {}, carriers = {} } :: any
DeepClient.underwater = false
DeepClient.quayLabel = nil :: TextLabel?

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function part(
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	return p
end

-- A sunken cache's drawn comic marker: the burst image over a small countdown line (empty while it is full)
local function cacheMarker(adornee: BasePart, range: number): (TextLabel, ImageLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(84, 104)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = range
	gui.Adornee = adornee
	local burst = Instance.new("ImageLabel")
	burst.Size = UDim2.fromOffset(84, 84)
	burst.BackgroundTransparency = 1
	burst.Image = "rbxassetid://" .. A.marker
	burst.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Position = UDim2.fromOffset(0, 84)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 247, 224)
	label.TextStrokeColor3 = Color3.fromRGB(31, 42, 68)
	label.TextStrokeTransparency = 0
	label.Text = ""
	label.Parent = gui
	gui.Parent = adornee
	return label, burst
end

local function marker(adornee: BasePart, text: string, color: Color3, range: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 34)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = range
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = adornee
	return label
end

-- The citizens' uploaded clothes (CitizenRenderer's), so a commuter dresses like the people in the streets
local function uploaded(map: { [string]: number }): { string }
	local out = {}
	for _, id in map do
		if id ~= 0 then
			table.insert(out, "rbxassetid://" .. id)
		end
	end
	table.sort(out)
	return out
end
local SHIRTS = uploaded(Config.Creator.clothes.shirts)
local PANTS = uploaded(Config.Creator.clothes.pants)
local SKINS = Config.Creator.skins

-- A trapped commuter: a Roblox-body person (NpcRig.person: a catalog face and catalog hair, the citizens'
-- clothes) treading water inside an air bubble (Art.Deep's AirBubble; a glass ball until it is imported)
local function commuter(at: Vector3, id: number): Model
	local looks = Config.Destruction.citizens.bodies
	local b = looks[(id - 1) % #looks + 1]
	local look = { gender = b[1], build = b[2], height = 3 }
	local layout = RigMath.layout(Config.HeroRig, BodyShape.factors(Config, look), 1)
	local skin = SKINS[(id * 3) % 16 + 1] or { 230, 190, 150 } -- (the 16 natural tones)
	local rig = NpcRig.person(
		layout,
		"Commuter" .. id,
		Color3.fromRGB(230, 170, 60),
		Color3.fromRGB(50, 60, 90),
		rgb(skin),
		Color3.fromRGB(60, 40, 30),
		BodyShape.setKey(Config, look)
	)
	if Config.Creator.clothes.on and #SHIRTS > 0 and #PANTS > 0 then
		NpcRig.dressPair(
			rig,
			SHIRTS[id % #SHIRTS + 1],
			PANTS[(id * 2) % #PANTS + 1],
			Config.NpcLooks.offsetSign
		)
	end
	-- treading water: arms out and up a little, one knee bent
	NpcRig.bend(rig, "LeftShoulder", CFrame.Angles(0, 0, math.rad(-50)))
	NpcRig.bend(rig, "RightShoulder", CFrame.Angles(0, 0, math.rad(50)))
	NpcRig.bend(rig, "RightKnee", CFrame.Angles(math.rad(-30), 0, 0))
	local m = rig.model
	m.Name = "Commuter"
	local size = Vector3.one * A.bubble
	local mid = CFrame.new(at)
	NpcRig.place(rig, mid * CFrame.new(0, -A.bubble * 0.36, 0))
	local bubble = DeepMeshes.look("AirBubble", size, mid, m)
	if not bubble then
		local air = part(size, mid, Color3.fromRGB(200, 240, 255))
		air.Name = "AirBubbleGlass"
		air.Material = Enum.Material.Glass
		air.Transparency = 0.72
		air.Shape = Enum.PartType.Ball
		air.Parent = m
	end
	m.Parent = folder
	return m
end

local function buildMarkers()
	for _, c in layout.caches do
		local glow =
			part(Vector3.new(2, 2, 2), CFrame.new(c.x, c.y + 2.5, c.z), rgb(Config.City.palette.cargo))
		glow.Material = Enum.Material.Neon
		glow.Parent = folder
		if A.marker ~= 0 then
			local label, burst = cacheMarker(glow, D.caches.markRange)
			caches[c.id] = { part = glow, label = label, burst = burst }
		else
			caches[c.id] = {
				part = glow,
				label = marker(glow, "SUNKEN CACHE", Color3.fromRGB(255, 220, 90), D.caches.markRange),
			}
		end
	end
	for _, r in layout.rescues do
		local m = commuter(Vector3.new(r.x, r.y, r.z), r.id)
		marker(m.PrimaryPart :: BasePart, "TRAPPED! SWIM CLOSE", Color3.fromRGB(255, 255, 255), 160)
		commuters[r.id] = m
	end
	-- the quay: where a carried commuter is set down
	local q = D.rescues.quay
	local pad = part(
		Vector3.new(6, 0.4, 6),
		CFrame.new(q.x, Config.City.ground.y + 1, q.z),
		Color3.fromRGB(90, 255, 140)
	)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.4
	pad.Parent = folder
	DeepClient.quayLabel = marker(pad, "", Color3.fromRGB(90, 255, 140), 1000)
end

local function heroRoot(heroId: number): BasePart?
	local p = Players:GetPlayerByUserId(heroId)
	local char = p and p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function onState(s: any)
	DeepClient.state = s
	local now = os.clock()
	for id, c in caches do
		local left = s.opened and s.opened[tostring(id)]
		c.part.Transparency = if left then 0.85 else 0
		c.label.Text = if left
			then string.format("REFILLS IN %d:%02d", left // 60, left % 60)
			elseif c.burst then ""
			else "SUNKEN CACHE"
		c.part:SetAttribute("Until", if left then now + left else nil)
		if c.burst then
			-- an opened cache's burst greys out until it refills
			c.burst.ImageColor3 = if left then Color3.fromRGB(120, 120, 130) else Color3.new(1, 1, 1)
			c.burst.ImageTransparency = if left then 0.35 else 0
		end
	end
	local mine = s.carriers and s.carriers[tostring(Players.LocalPlayer.UserId)]
	local ql = DeepClient.quayLabel
	if ql then
		ql.Text = if mine then "SET THEM DOWN HERE" else ""
	end
end

local function setLook(under: boolean, depth: number)
	-- the sky's Atmosphere overrides Lighting fog, so underwater thickens and tints the Atmosphere instead
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	local target: Instance = air or Lighting
	if under and not tint then
		saved = if air
			then {
				Density = air.Density,
				Offset = air.Offset,
				Color = air.Color,
				Decay = air.Decay,
				Haze = air.Haze,
				Glare = air.Glare,
			}
			else { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd, FogColor = Lighting.FogColor }
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "DeepTint"
		c.Parent = Lighting
		tint = c
	end
	if under and tint then
		local k = math.clamp(depth / math.abs(D.trench.floor), 0, 1)
		local col = rgb(L.tint):Lerp(rgb(L.deepTint), k)
		tint.TintColor = Color3.new(1, 1, 1):Lerp(col, 0.55)
		tint.Brightness = -0.05 - 0.25 * k
		tint.Saturation = -0.1
		if air then
			air.Density = L.haze[1] + (L.haze[2] - L.haze[1]) * k
			air.Offset = 0
			air.Color = col
			air.Decay = col:Lerp(Color3.new(0, 0, 0), 0.5)
			air.Haze = 0
			air.Glare = 0
		else
			Lighting.FogColor = col
			Lighting.FogStart = L.fogStart
			Lighting.FogEnd = L.fogEnd * (1 - 0.4 * k)
		end
	elseif not under and tint then
		tint:Destroy()
		tint = nil
		for k, v in saved do
			(target :: any)[k] = v
		end
	end
end

local bubbleAt = 0
local function bubbles(root: BasePart, now: number)
	if now < bubbleAt or root.AssemblyLinearVelocity.Magnitude < 4 then
		return
	end
	bubbleAt = now + L.bubbles
	local at = root.Position + Vector3.new(math.random() - 0.5, 1.5, math.random() - 0.5)
	local b = part(
		Vector3.one * (0.3 + math.random() * 0.4),
		CFrame.new(at),
		Color3.fromRGB(220, 245, 255),
		Enum.Material.Glass,
		Enum.PartType.Ball
	)
	b.Transparency = 0.35
	b.Parent = folder
	TweenService:Create(b, TweenInfo.new(1.4), { Position = at + Vector3.new(0, 6, 0), Transparency = 1 })
		:Play()
	task.delay(1.4, b.Destroy, b)
end

-- Kelp near the camera sways about its foot (CityBuilder tags each strand's mesh DeepKelp with its Foot); the
-- nearest `max` within `near` studs are picked every `refresh` seconds, the rest stand still
local kelpBase: { [BasePart]: CFrame } = {}
local kelpNear: { BasePart } = {}
local kelpPickAt = 0
local function kelpAdded(p: Instance)
	if p:IsA("BasePart") then
		kelpBase[p] = p.CFrame
	end
end
local function kelpRemoved(p: Instance)
	kelpBase[p :: BasePart] = nil
end

local function swayKelp(now: number, cam: Vector3)
	local near, max = DeepArtKit.swayBudget(Config, QualityController.name)
	if now >= kelpPickAt then
		kelpPickAt = now + A.kelp.refresh
		for _, p in kelpNear do -- stand the old picks up again
			local base = kelpBase[p]
			if base and p.Parent then
				p.CFrame = base
			end
		end
		table.clear(kelpNear)
		if max > 0 then
			local list = {}
			for p, base in kelpBase do
				local d = (base.Position - cam).Magnitude
				if d <= near then
					table.insert(list, { p = p, d = d })
				end
			end
			table.sort(list, function(a, b)
				return a.d < b.d
			end)
			for i = 1, math.min(max, #list) do
				table.insert(kelpNear, list[i].p)
			end
		end
	end
	if #kelpNear == 0 then
		return
	end
	local parts, cfs = {}, {}
	for _, p in kelpNear do
		local base = kelpBase[p]
		local foot = p:GetAttribute("Foot")
		if base and typeof(foot) == "Vector3" then
			local rx, rz = DeepArtKit.sway(Config, now, foot.X, foot.Z)
			local pivot = CFrame.new(foot)
			table.insert(parts, p)
			table.insert(cfs, pivot * CFrame.Angles(rx, 0, rz) * pivot:Inverse() * base)
		end
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Caustic light on the floor round the camera: one plane under it with two drifting caustic Textures, only in the
-- lit water (not the Sunken Line), fading out with depth; off on presets with no size or before the upload
local caustics: Part? = nil
local causticLayers: { Texture } = {}
local function shimmer(now: number, cam: Vector3, under: boolean)
	local cfg = A.caustics
	local size = cfg[QualityController.name] or 0
	local area = if under then DeepLayout.area(Config, cam.X, cam.Z, cam.Y) else nil
	local floor = if area and area ~= "line" then DeepLayout.floorAt(Config, cam.X, cam.Z, cam.Y) else nil
	local depth = Config.World.coast.waterY - (floor or 0)
	if cfg.image == 0 or size <= 0 or not floor or depth > cfg.maxDepth then
		if caustics then
			caustics.Parent = nil
		end
		return
	end
	if not caustics then
		local p = part(Vector3.new(size, 0.05, size), CFrame.new(), Color3.new(1, 1, 1))
		p.Name = "Caustics"
		p.Transparency = 1
		for k = 1, 2 do
			local t = Instance.new("Texture")
			t.Face = Enum.NormalId.Top
			t.Texture = "rbxassetid://" .. cfg.image
			t.StudsPerTileU = cfg.tile * (if k == 1 then 1 else 1.37)
			t.StudsPerTileV = cfg.tile * (if k == 1 then 1 else 1.37)
			t.Parent = p
			causticLayers[k] = t
		end
		caustics = p
	end
	local p = caustics :: Part
	if p.Size.X ~= size then
		p.Size = Vector3.new(size, 0.05, size)
	end
	-- snapped to the tile so the light stays put on the floor while the plane follows the camera
	local snap = cfg.tile * 1.37 * cfg.tile
	local cx = math.floor(cam.X / snap + 0.5) * snap
	local cz = math.floor(cam.Z / snap + 0.5) * snap
	p.CFrame = CFrame.new(cx, floor + 0.25, cz)
	local fade = cfg.alpha + (1 - cfg.alpha) * math.clamp(depth / cfg.maxDepth, 0, 1)
	for k, t in causticLayers do
		local dir = if k == 1 then 1 else -0.7
		t.OffsetStudsU = (now * cfg.speed * dir) % t.StudsPerTileU
		t.OffsetStudsV = (now * cfg.speed * 0.6 * dir) % t.StudsPerTileV
		t.Transparency = math.clamp(fade + 0.12 * math.sin(now * 1.7 + k * 2), 0, 1)
	end
	if p.Parent ~= folder then
		p.Parent = folder
	end
end

local function step()
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	if cam then
		local p = cam.CFrame.Position
		local under = DeepLayout.underwater(Config, p.X, p.Y, p.Z)
		DeepClient.underwater = under
		setLook(under, Config.World.coast.waterY - p.Y)
		swayKelp(now, p)
		shimmer(now, p, under)
	end
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local pos = root.Position
		local area = if DeepLayout.underwater(Config, pos.X, pos.Y, pos.Z)
			then DeepLayout.area(Config, pos.X, pos.Z, pos.Y)
			else nil
		if area and area ~= lastArea then
			-- (pcall: the toast layer starts after this controller)
			pcall(Toasts.show, { id = "note", text = DeepLayout.NAMES[area] or area })
		end
		lastArea = area
		if area then
			bubbles(root, now)
		end
	end
	-- caches count down on their own between server updates
	for _, c in caches do
		local untilT = c.part:GetAttribute("Until")
		if untilT then
			local left = math.max(0, math.ceil(untilT - now))
			c.label.Text = string.format("REFILLS IN %d:%02d", left // 60, left % 60)
		end
	end
	-- commuters: waiting at their pocket, held by a carrier, or gone until they wait again
	local carriedBy: { [number]: number } = {}
	for heroId, id in DeepClient.state.carriers or {} do
		carriedBy[id] = tonumber(heroId) :: number
	end
	for _, r in layout.rescues do
		local m = commuters[r.id]
		local carrier = carriedBy[r.id]
		local waiting = DeepClient.state.rescues and DeepClient.state.rescues[tostring(r.id)]
		local cf: CFrame? = nil
		if carrier then
			local hr = heroRoot(carrier)
			if hr then
				cf = hr.CFrame * CFrame.new(0, 0.5, 1.6)
			end
		elseif waiting then
			cf = CFrame.new(r.x, r.y + 0.3 * math.sin(now * 1.3 + r.id), r.z)
				* CFrame.Angles(0, now * 0.4 + r.id, 0)
		end
		if cf then
			m:PivotTo(cf)
			if m.Parent ~= folder then
				m.Parent = folder
			end
		elseif m.Parent then
			m.Parent = nil
		end
	end
end

function DeepClient.init()
	layout = DeepLayout.build(Config)
	folder = Instance.new("Folder")
	folder.Name = "DeepFx"
	folder.Parent = Workspace
	buildMarkers()
	for _, p in CollectionService:GetTagged("DeepKelp") do
		kelpAdded(p)
	end
	CollectionService:GetInstanceAddedSignal("DeepKelp"):Connect(kelpAdded)
	CollectionService:GetInstanceRemovedSignal("DeepKelp"):Connect(kelpRemoved)
	Net.listen("DeepState", onState)
	RunService.RenderStepped:Connect(FrameProf.wrap("DeepClient", step))
end

return DeepClient
