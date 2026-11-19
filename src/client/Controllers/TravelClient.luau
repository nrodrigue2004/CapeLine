-- TravelClient: the fast-travel flight and the safehouse terminals on this device (spec: Movement kit > Fast
-- travel "3 s skippable flight"; Wait table "Long flights").
-- * FastTravel ok: the hero flies the server's arc itself (gap polish 2026-11-19; it used to stand still under a
--   camera sweep): MoveController.travel follows Travel.flightPath (eased by PolishPlan.travelEase: it takes off
--   from still and dives into the landing) in the flight pose (HeroAnimator, from the fly mode), through the city
--   in the server's "TravelFlight" collision group, while a camera follows behind and a SKIP button waits.
--   FastTravelDone (the server has set the hero down) drops it out of the flight diving, so it lands with the
--   landing's juice (MoveFx's thud, ring and crack, the hard landing pose).
-- * Every device: a hero with the Traveling attribute (BeaconService) gets a speed trail on its root, a burst
--   where it takes off and a dust ring and shockwave where it lands, so other players see it leave and arrive
--   (the body itself replicates from its owner's flight). The trail's colours are the hero's creator trail when
--   it wears one, else the volt white streak.
-- * A refused trip shows why on the map (undiscovered, in combat, cooldown).
-- * The Loadout terminal's prompt opens the loadout screen here (the server checks the location again).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Net = require(Shared:WaitForChild("Net"))
local Travel = require(Shared:WaitForChild("Travel"))
local PolishPlan = require(Shared:WaitForChild("PolishPlan"))

local Kit = require(script.Parent.Parent.Ui.Kit)
local Juice = require(script.Parent.Parent.Fx.Juice)
local FxLib = require(script.Parent.Parent.Fx.FxLib)
local MapScreen = require(script.Parent.Parent.Ui.MapScreen)
local LoadoutScreen = require(script.Parent.Parent.Ui.LoadoutScreen)
local MoveController = require(script.Parent.MoveController)
local QualityController = require(script.Parent.QualityController)

local TravelClient = {}
TravelClient.flying = false

local T = Config.Fx.polish.travel
local GROUP = "TravelFlight" -- BeaconService.GROUP
local TAG = "TravelTrail"
local me = Players.LocalPlayer

local REASONS = {
	undiscovered = "Find that beacon first",
	combat = "Not while fighting (wait a few seconds)",
	cooldown = "Fast travel is cooling down",
	traveling = "Already flying",
	scene = "Head back out to the city first",
}

local gui: ScreenGui
local skip: TextButton
local flying = false
local groups: { [BasePart]: string } = {}
local camDir = Vector3.new(0, 0, -1)

local function rootOf(p: Player): BasePart?
	local char = p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- the body flies through everything for the trip (the old groups come back after)
local function setGroups(on: boolean)
	if on then
		local char = me.Character
		if not char then
			return
		end
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") and groups[d] == nil then
				groups[d] = d.CollisionGroup
				pcall(function()
					d.CollisionGroup = GROUP
				end)
			end
		end
	else
		for part, g in groups do
			if part.Parent then
				part.CollisionGroup = g
			end
		end
		table.clear(groups)
	end
end

local function stop()
	if not flying then
		return
	end
	flying = false
	TravelClient.flying = false
	skip.Visible = false
	RunService:UnbindFromRenderStep("CapelineTravel")
	MoveController.endTravel(T.dive)
	setGroups(false)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local char = me.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

local function start(data: any)
	MapScreen.close()
	local a, b = data.from :: Vector3, data.to :: Vector3
	local function at(f: number): Vector3
		local x, y, z = Travel.flightPath(a.X, a.Y, a.Z, b.X, b.Y, b.Z, PolishPlan.travelEase(f))
		return Vector3.new(x, y, z)
	end
	flying = true
	TravelClient.flying = true
	Juice.fire("fastTravel")
	skip.Visible = true
	setGroups(true)
	MoveController.travel(at, data.time)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	camDir = if flat.Magnitude > 1 then flat.Unit else Vector3.new(0, 0, -1)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	-- the camera rides behind the hero, turning with the flight (smoothed so the dive does not whip it round)
	RunService:BindToRenderStep(
		"CapelineTravel",
		Enum.RenderPriority.Camera.Value + 2,
		FrameProf.wrap("TravelClient", function(dt: number)
			local root = rootOf(me)
			if not root then
				return
			end
			local v = root.AssemblyLinearVelocity
			if v.Magnitude > 5 then
				camDir = camDir:Lerp(v.Unit, math.min(1, dt * 3))
				if camDir.Magnitude < 1e-3 then
					camDir = v.Unit
				end
				camDir = camDir.Unit
			end
			local pos = root.Position
			local back = Vector3.new(camDir.X, math.clamp(camDir.Y, -0.6, 0.4), camDir.Z)
			back = if back.Magnitude > 1e-3 then back.Unit else Vector3.new(0, 0, -1)
			local eye = pos - back * T.camBack + Vector3.new(0, T.camUp, 0)
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(eye, pos + back * T.camAhead), math.min(1, dt * 8))
		end)
	)
end

---------------------------------------------------------------------------
-- every device: the trail, the take-off burst and the landing for any travelling hero
---------------------------------------------------------------------------

local function trailColors(char: Model): ColorSequence
	for _, d in char:GetDescendants() do
		if d:IsA("Trail") and d.Name == "CreatorTrail" then
			return d.Color
		end
	end
	local v = Config.Ui.colors.volt
	return ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(v[1], v[2], v[3]))
end

local function addTrail(p: Player)
	local root = rootOf(p)
	local name = QualityController.name
	local row = Config.Fx.polish.presets[name] or Config.Fx.polish.presets.medium
	if not root or root:FindFirstChild(TAG) or not row.trail then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = TAG .. "Top"
	a0.Position = Vector3.new(0, T.trail.width / 2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = TAG .. "Bottom"
	a1.Position = Vector3.new(0, -T.trail.width / 2, 0)
	a1.Parent = root
	local tr = Instance.new("Trail")
	tr.Name = TAG
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.FaceCamera = true
	tr.Lifetime = T.trail.life[name] or T.trail.life.medium
	tr.MinLength = 0.5
	tr.LightEmission = 0.7
	tr.WidthScale = NumberSequence.new(1, 0.05)
	tr.Transparency = NumberSequence.new(0.1, 1)
	tr.Color = trailColors(p.Character :: Model)
	local kit = Config.Creator.trailFx and Config.Creator.trailFx.kits[T.trail.kit]
	if kit and kit.id ~= 0 then
		tr.Texture = "rbxassetid://" .. tostring(kit.id)
		tr.TextureMode = Enum.TextureMode.Stretch
	end
	tr.Parent = root
end

local function dropTrail(p: Player)
	local root = rootOf(p)
	if not root then
		return
	end
	for _, name in { TAG, TAG .. "Top", TAG .. "Bottom" } do
		local d = root:FindFirstChild(name)
		if d then
			d:Destroy()
		end
	end
end

local WHITE = Color3.new(1, 1, 1)
local DUST = Color3.fromRGB(200, 192, 176)
local function groundUnder(pos: Vector3, char: Model?): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if char then { char } else {}
	local hit = Workspace:Raycast(pos, Vector3.new(0, -14, 0), params)
	return hit and hit.Position
end

local function watch(p: Player)
	p:GetAttributeChangedSignal("Traveling"):Connect(function()
		local root = rootOf(p)
		if p:GetAttribute("Traveling") == true then
			-- take-off: a shockwave and dust where the hero stood, a white flash on the body
			if root then
				local g = groundUnder(root.Position, p.Character) or root.Position - Vector3.new(0, 3, 0)
				FxLib.shock(g + Vector3.new(0, 0.3, 0), 10, WHITE)
				FxLib.dust(g + Vector3.new(0, 0.5, 0), 8, DUST)
				FxLib.emit("glow", WHITE, root.Position, 1)
			end
			addTrail(p)
		else
			-- the landing: the trail lingers a moment, then a dust ring and shockwave where it came down (your
			-- own landing also gets MoveFx's thud and crack from the dive)
			task.delay(0.35, function()
				dropTrail(p)
				local r = rootOf(p)
				local g = r and groundUnder(r.Position, p.Character)
				if g then
					FxLib.shock(g + Vector3.new(0, 0.3, 0), 14, WHITE)
					FxLib.dust(g + Vector3.new(0, 0.5, 0), 12, DUST)
				end
			end)
		end
	end)
end

function TravelClient.init()
	gui = Kit.screen("Travel", 9)
	skip = Kit.button({
		Text = "SKIP",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Config.Ui.safe - 90),
		Visible = false,
	}, function()
		Net.send("MoveTravelSkip")
		MoveController.holdTravel() -- the server sets the hero down now; wait for it where we are
	end)
	skip.Parent = gui
	Net.listen("FastTravel", function(data)
		if data.ok then
			start(data)
		else
			local text = REASONS[data.reason or ""] or "Can't fast travel right now"
			if data.reason == "cooldown" and data.wait then
				text = string.format("Fast travel ready in %d s", math.ceil(data.wait))
			end
			MapScreen.say(text)
		end
	end)
	Net.listen("FastTravelDone", function()
		stop()
	end)
	me.CharacterAdded:Connect(function()
		if flying then
			table.clear(groups) -- the old body is gone with its groups
			stop()
		end
	end)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == me and prompt:GetAttribute("Terminal") == "loadout" then
			LoadoutScreen.open()
		end
	end)
end

return TravelClient
