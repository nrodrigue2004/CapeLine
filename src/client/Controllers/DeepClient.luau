-- DeepClient: the underwater areas on this device (Config.Deep; nate 2026-11-16: underwater at launch).
-- * Under the surface the camera gets a blue tint that darkens with depth and a short fog (on top of the
--   Terrain water's own look), and a moving hero trails bubbles.
-- * Entering an area names it once ("The Sunken Line").
-- * Sunken cargo caches glow and carry a marker until this hero opens them (then a countdown); trapped
--   commuters wait in their air pockets and hold on to whoever carries them (DeepState from the server).
-- The positions come from Shared.DeepLayout, the same data the server builds the world from.
-- PLACEHOLDER ART: the commuters are a few parts each and the markers plain labels until the art pass.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))

local Toasts = require(script.Parent.Parent.Ui.Toasts)

local DeepClient = {}

local D = Config.Deep
local L = D.look
local layout: any = nil
local folder: Folder
local tint: ColorCorrectionEffect? = nil
local saved: { [string]: any } = {}
local lastArea: string? = nil
local caches: { [number]: { part: BasePart, label: TextLabel } } = {}
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

-- A trapped commuter: a small citizen figure with a bubble of air around the head (PLACEHOLDER ART)
local function commuter(at: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "Commuter"
	local shirt = Color3.fromRGB(230, 170, 60)
	local body = part(Vector3.new(2, 2.2, 1), CFrame.new(at), shirt)
	body.Name = "Body"
	body.Parent = m
	part(Vector3.new(1.3, 1.3, 1.3), CFrame.new(at + Vector3.new(0, 1.8, 0)), Color3.fromRGB(240, 200, 160)).Parent =
		m
	for _, s in { -0.5, 0.5 } do
		part(Vector3.new(0.8, 2, 0.8), CFrame.new(at + Vector3.new(s, -2.1, 0)), Color3.fromRGB(50, 60, 90)).Parent =
			m
	end
	local air =
		part(Vector3.one * 3.4, CFrame.new(at + Vector3.new(0, 1.8, 0)), Color3.fromRGB(200, 240, 255))
	air.Material = Enum.Material.Glass
	air.Transparency = 0.7
	air.Shape = Enum.PartType.Ball
	air.Parent = m
	m.PrimaryPart = body
	m.Parent = folder
	return m
end

local function buildMarkers()
	for _, c in layout.caches do
		local glow =
			part(Vector3.new(2, 2, 2), CFrame.new(c.x, c.y + 2.5, c.z), rgb(Config.City.palette.cargo))
		glow.Material = Enum.Material.Neon
		glow.Parent = folder
		caches[c.id] = {
			part = glow,
			label = marker(glow, "SUNKEN CACHE", Color3.fromRGB(255, 220, 90), D.caches.markRange),
		}
	end
	for _, r in layout.rescues do
		local m = commuter(Vector3.new(r.x, r.y, r.z))
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
			else "SUNKEN CACHE"
		c.part:SetAttribute("Until", if left then now + left else nil)
	end
	local mine = s.carriers and s.carriers[tostring(Players.LocalPlayer.UserId)]
	local ql = DeepClient.quayLabel
	if ql then
		ql.Text = if mine then "SET THEM DOWN HERE" else ""
	end
end

local function setLook(under: boolean, depth: number)
	if under and not tint then
		saved = { FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd, FogColor = Lighting.FogColor }
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
		Lighting.FogColor = col
		Lighting.FogStart = L.fogStart
		Lighting.FogEnd = L.fogEnd * (1 - 0.4 * k)
	elseif not under and tint then
		tint:Destroy()
		tint = nil
		for k, v in saved do
			(Lighting :: any)[k] = v
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

local function step()
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	if cam then
		local p = cam.CFrame.Position
		local under = DeepLayout.underwater(Config, p.X, p.Y, p.Z)
		DeepClient.underwater = under
		setLook(under, Config.World.coast.waterY - p.Y)
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
			cf = CFrame.new(r.x, r.y, r.z) * CFrame.Angles(0, now * 0.4 + r.id, 0)
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
	Net.listen("DeepState", onState)
	RunService.RenderStepped:Connect(step)
end

return DeepClient
