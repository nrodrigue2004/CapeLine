-- ThrowFx: the look of pick up and throw (spec: Hero MMO features > Pick up and throw; H3). Flies every
-- thrown thing on the server's arc (ThrowFly: the same parabola on every screen, Shared.ThrowMath.arcPoint,
-- tumbling as it goes), with a dust ring, chips and a crash where it lands (a shake for heavy ones near you),
-- a puff when someone lifts something (the Carrying attribute) and a shine when a prop comes home (ThrowBack):
-- textured particles through the effects library since gap-fx3 (2026-11-19: FxLib.throwMoment, Config.Fx.lib.throw,
-- the uploaded chip.png, in the ground's own colour; inside the preset's particle budget).
-- Downed robots' wrecks (WP6): sparks while one lies near the camera (its dead eyes light for a blink), a
-- flicker for its last seconds (the WreckEnds server time) and a pop of nuts, sparks and smoke when it falls
-- apart (WreckGone): textured particles through the effects library (FxLib, Config.Fx.lib.wreck, inside the
-- preset's particle budget; gap-wrecks, 2026-11-19). Cartoon: machines spark, nothing else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Net = require(Shared:WaitForChild("Net"))
local ThrowMath = require(Shared:WaitForChild("ThrowMath"))

local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CityProps = require(script.Parent.Parent.Controllers.CityProps)
local Juice = require(script.Parent.Juice)
local FxLib = require(script.Parent.FxLib)

local ThrowFx = {}

local T = Config.Throw
local player = Players.LocalPlayer
local DUST = Color3.fromRGB(196, 186, 170)
local flights: { [number]: any } = {}
local carrying: { [Player]: string? } = {}
local W = T.wreck
local SPARK = Color3.fromRGB(255, 226, 120)
local METAL = Color3.fromRGB(90, 90, 100)
local wrecks: { [Model]: { next: number, dim: boolean } } = {}

-- The model for an item id: a prop in Workspace.Throwables, or a vehicle tagged with ThrowId
function ThrowFx.model(id: number): Model?
	for _, root in { Workspace:FindFirstChild("Throwables"), Workspace:FindFirstChild("City") } do
		if root then
			local holder = if root.Name == "City" then root:FindFirstChild("Vehicles") else root
			for _, m in (if holder then holder:GetChildren() else {}) do
				if m:GetAttribute("ThrowId") == id then
					return m :: Model
				end
			end
		end
	end
	return nil
end

-- the ground's colour under a landing (dust takes it on, half way to plain dust), else plain dust
local groundRay = RaycastParams.new()
groundRay.FilterType = Enum.RaycastFilterType.Exclude
local function groundColor(at: Vector3, thrown: Instance?): Color3
	local skip: { Instance } = if thrown then { thrown } else {}
	for _, i in
		{ player.Character, Workspace:FindFirstChild("Throwables"), Workspace:FindFirstChild("FxEmitters") }
	do
		if i then
			table.insert(skip, i)
		end
	end
	groundRay.FilterDescendantsInstances = skip
	local hit = Workspace:Raycast(at + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), groundRay)
	if hit and hit.Instance:IsA("BasePart") then
		return (hit.Instance :: BasePart).Color:Lerp(DUST, 0.5)
	end
	return DUST
end

-- Juice rows (Config.Audio.juice): the visual for grab and throwLand
function ThrowFx.grab(at: Vector3)
	local feet = at - Vector3.new(0, 2.5, 0)
	FxLib.throwMoment("grab", feet, groundColor(feet), nil, 4)
end

function ThrowFx.throwLand(at: Vector3, weight: string, mine: boolean, thrown: Instance?)
	local W = T.weights[weight] or T.weights.light
	FxLib.throwMoment("land", at, groundColor(at, thrown), nil, W.radius, weight)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if weight ~= "light" and root and (root.Position - at).Magnitude < 60 then
		CameraController.shake(
			if weight == "heavy" then 0.25 else 0.12,
			if weight == "heavy" then 0.6 else 0.3
		)
	end
	Juice.fire("throwLand", at, { mine = mine })
end

-- WP6: a wreck's suit, metal and eye colours (ThrowService's attributes; the Body's colour if missing)
local function wreckColors(m: Model, main: BasePart): (Color3, Color3, Color3)
	local suit, metal, eye =
		m:GetAttribute("WreckSuit"), m:GetAttribute("WreckMetal"), m:GetAttribute("WreckEye")
	return if typeof(suit) == "Color3" then suit else main.Color,
		if typeof(metal) == "Color3" then metal else METAL,
		if typeof(eye) == "Color3" then eye else SPARK
end

-- its dead eyes light for a blink as it sparks (the look's Eyes mesh, or the plain heap's Eyes part)
local function flickerEyes(m: Model, eye: Color3)
	local p = m:FindFirstChild("Eyes")
	if not p or not p:IsA("BasePart") or p:GetAttribute("Lit") then
		return
	end
	local color, material = p.Color, p.Material
	p:SetAttribute("Lit", true)
	p.Color = eye
	p.Material = Enum.Material.Neon
	task.delay(Config.Fx.lib.wreck.flicker, function()
		if p.Parent then
			p.Color = color
			p.Material = material
			p:SetAttribute("Lit", nil)
		end
	end)
end

local function setDim(m: Model, dim: boolean)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = if dim then 0.6 else 0
		end
	end
end

-- It falls apart: chips in its own colour, sparks and a pop where it lay
local function popWreck(m: Model)
	wrecks[m] = nil
	local main = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	if not main then
		return
	end
	local at = main.Position
	local suit, metal = wreckColors(m, main)
	FxLib.wreckMoment("pop", at + Vector3.new(0, 0.5, 0), SPARK, suit, metal)
	FxLib.dust(at - Vector3.new(0, main.Size.Y * 0.4, 0), 4)
	Juice.fire("wreckPop", at, { mine = false })
end

-- item 154: a throwable's look on this device (Config.Throw.dress): a street prop's meshes, or a small part
-- build, welded onto the server's plain box, which then hides here (it still takes the hits and the carry)
function ThrowFx.dress(m: Instance): number
	local kind = m:GetAttribute("ThrowKind")
	local d = T.dress and type(kind) == "string" and T.dress[kind]
	if not m:IsA("Model") or not d or m:GetAttribute("Dressed") then
		return 0
	end
	local body = m:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return 0
	end
	m:SetAttribute("Dressed", true) -- this device's own flag (not replicated back)
	local made = if d.mesh then CityProps.dress(d.mesh, body, T.kinds[kind].size[2]) else 0
	if made == 0 and d.parts then
		made = CityProps.dressParts(body, d.parts)
	end
	if made > 0 then
		body.LocalTransparencyModifier = 1
	end
	return made
end

local function watchWreck(m: Instance)
	if not m:IsA("Model") or m:GetAttribute("ThrowKind") ~= "wreck" then
		return
	end
	local model = m :: Model
	wrecks[model] = { next = os.clock() + math.random() * W.sparkEvery, dim = false }
	model:GetAttributeChangedSignal("WreckGone"):Connect(function()
		if wrecks[model] then
			popWreck(model)
		end
	end)
end

local function stepWrecks(now: number)
	local cam = Workspace.CurrentCamera
	local eye = if cam then cam.CFrame.Position else nil
	local serverNow = Workspace:GetServerTimeNow()
	for m, w in wrecks do
		local main = m.PrimaryPart
		if not m.Parent or not main then
			wrecks[m] = nil
			continue
		end
		local at = main.Position
		if now >= w.next then
			w.next = now + W.sparkEvery * (0.6 + math.random() * 0.8)
			if eye and (eye - at).Magnitude <= W.sparkRange then
				local suit, metal, eye = wreckColors(m, main)
				FxLib.wreckMoment("spark", at + Vector3.new(0, main.Size.Y * 0.5, 0), SPARK, suit, metal)
				flickerEyes(m, eye)
				if math.random() < 0.3 then
					Juice.fire("wreckSpark", at, { mine = false })
				end
			end
		end
		-- its last seconds: a flicker (not while someone holds it)
		local ends = m:GetAttribute("WreckEnds")
		local dim = type(ends) == "number"
			and serverNow >= ends - W.blink
			and m:GetAttribute("ThrowBusy") ~= true
			and math.floor(now * 5) % 2 == 0
		if dim ~= w.dim then
			w.dim = dim
			setDim(m, dim)
		end
	end
end

local function weightOf(m: Model): string
	local kind = m:GetAttribute("ThrowKind")
	return (type(kind) == "string" and ThrowMath.weight(T, kind)) or "light"
end

local function step()
	local now = os.clock()
	stepWrecks(now)
	for id, f in flights do
		local t = math.clamp((now - f.t0) / f.time, 0, 1)
		local x, y, z = ThrowMath.arcPoint(f.from.X, f.from.Y, f.from.Z, f.to.X, f.to.Y, f.to.Z, f.peak, t)
		if f.model.Parent then
			-- tumble end over end along the flight
			f.model:PivotTo(CFrame.new(x, y, z) * f.turn * CFrame.Angles(t * f.spin, 0, t * f.spin * 0.4))
		end
		if t >= 1 then
			flights[id] = nil
			if f.hit then
				ThrowFx.throwLand(f.to, weightOf(f.model), f.mine, f.model)
			end
		end
	end
	-- someone lifted something: a puff at their feet
	for _, p in Players:GetPlayers() do
		local kind = p:GetAttribute("Carrying")
		if kind ~= carrying[p] then
			carrying[p] = kind
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if kind and root then
				ThrowFx.grab(root.Position)
				Juice.fire("grab", root.Position, { mine = p == player })
			end
		end
	end
end

function ThrowFx.init()
	Net.listen(
		"ThrowFly",
		function(id: number, from: Vector3, to: Vector3, time: number, peak: number, by: number)
			local m = ThrowFx.model(id)
			if not m or typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or type(time) ~= "number" then
				return
			end
			local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
			flights[id] = {
				model = m,
				from = from,
				to = to,
				time = math.max(0.05, time),
				peak = peak or 0,
				t0 = os.clock(),
				turn = if flat.Magnitude > 0.1 then CFrame.lookAt(Vector3.zero, flat) else CFrame.identity,
				spin = if weightOf(m) == "heavy" then math.pi else math.pi * 3,
				mine = by == player.UserId,
				hit = by ~= 0, -- props knocked aside by a landing just tip over, no crash of their own
			}
		end
	)
	Net.listen("ThrowBack", function(id: number)
		local m = ThrowFx.model(id)
		if m then
			FxLib.throwMoment("back", m:GetPivot().Position, Color3.fromRGB(200, 240, 255))
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		carrying[p] = nil
	end)
	task.spawn(function()
		local props = Workspace:WaitForChild("Throwables", 60)
		if not props then
			return
		end
		local function added(m: Instance)
			watchWreck(m)
			if m:IsA("Model") and T.dress[m:GetAttribute("ThrowKind") :: any] then
				-- the box streams in after its model: dress it once it is there
				task.spawn(function()
					if m:WaitForChild("Body", 10) then
						ThrowFx.dress(m)
					end
				end)
			end
		end
		for _, m in props:GetChildren() do
			added(m)
		end
		props.ChildAdded:Connect(added)
		props.ChildRemoved:Connect(function(m: Instance)
			if m:IsA("Model") then
				wrecks[m] = nil
			end
		end)
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("ThrowFx", step))
end

return ThrowFx
