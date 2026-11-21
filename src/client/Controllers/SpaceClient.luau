-- SpaceClient (2026-11-21, Everything Left 736; spec "Fly-in planet travel"): the orbit and the worlds on this
-- device. Each frame it works out which zone the camera's hero is in (Shared.SpaceLayout.zoneAt) and lights it
-- (the orbit's held starry night with no cloud layer, Calder's black sky, the alien planet's violet haze), sets the
-- local player's "SpaceZone" attribute (Fx.WeatherFx keeps weather out of space), watches the rings near the hero
-- (the Orbit Gate over the Hero Hall, the planets' approach rings in orbit, each world's return ring) and asks the
-- server for the trip when the hero flies through one (SpaceGo). The trip itself is cinematic: a 4 s atmosphere
-- entry (5 s by ship) with a heat glow, streaks racing past, a rumble and a shake, a white-out into clouds, then
-- you burst out of them over the new world, still flying, its name across the screen.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local SpaceLayout = require(Shared:WaitForChild("SpaceLayout"))

local AudioController = require(script.Parent.AudioController)
local CameraController = require(script.Parent.CameraController)
local QualityController = require(script.Parent.QualityController)
local WorldClient = require(script.Parent.WorldClient)

local SpaceClient = {}

local S = Config.Space
local LK = S.look
local player = Players.LocalPlayer

SpaceClient.zone = nil :: any -- "orbit", a world's index, or nil
local saved: { [string]: any }? = nil -- the city's lighting, put back on the way home
local held: number? = nil -- the clock hour this module holds (so a story's own hold is left alone)
local lastPos: Vector3? = nil
local askedAt = 0
local tripUntil = 0
local deniedSaid: { [string]: number } = {}

local gui: ScreenGui
local glow: Frame
local white: Frame
local title: TextLabel
local note: TextLabel
local streaks: { Frame } = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function makeGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpaceTrip"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	glow = Instance.new("Frame")
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundColor3 = rgb(LK.heat)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 0.75),
		NumberSequenceKeypoint.new(0.65, 0.75),
		NumberSequenceKeypoint.new(1, 0),
	})
	grad.Rotation = 90
	grad.Parent = glow
	glow.Parent = gui
	for i = 1, 40 do
		local s = Instance.new("Frame")
		s.Name = "Streak" .. i
		s.BorderSizePixel = 0
		s.BackgroundColor3 = Color3.fromRGB(255, 230, 190)
		s.Visible = false
		s.Parent = gui
		streaks[i] = s
	end
	white = Instance.new("Frame")
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.fromRGB(245, 248, 255)
	white.BackgroundTransparency = 1
	white.BorderSizePixel = 0
	white.Parent = gui
	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.3)
	title.Size = UDim2.fromScale(0.8, 0.12)
	title.Font = Enum.Font.LuckiestGuy
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeTransparency = 0
	title.TextTransparency = 1
	title.TextStrokeColor3 = Color3.fromRGB(20, 20, 40)
	title.Parent = gui
	note = title:Clone()
	note.Position = UDim2.fromScale(0.5, 0.72)
	note.Size = UDim2.fromScale(0.6, 0.05)
	note.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function say(text: string, secs: number)
	note.Text = text
	note.TextTransparency = 0
	note.TextStrokeTransparency = 0
	task.delay(secs, function()
		if note.Text == text then
			TweenService
				:Create(note, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
				:Play()
		end
	end)
end

local function destName(dest: number): string
	if dest == 0 then
		return "ORBIT"
	end
	local w = S.worlds[dest]
	return if w then w.name else "?"
end

-- the entry: heat glow and streaks build, the rumble and shake, a white-out at the end
local function entry(dest: number, secs: number, ship: boolean)
	tripUntil = os.clock() + secs + 1
	local preset = QualityController.name
	local count = math.min(LK.streaks[preset] or LK.streaks.medium, #streaks)
	local view = (Workspace.CurrentCamera :: Camera).ViewportSize
	local t0 = os.clock()
	note.Text = if ship then "SHIP LAUNCH: " .. destName(dest) else "ENTERING " .. destName(dest)
	note.TextTransparency, note.TextStrokeTransparency = 0, 0
	AudioController.play("collapse", nil, { pitch = LK.rumble.pitch, volume = LK.rumble.volume })
	task.delay(secs * 0.5, function()
		AudioController.play("collapse", nil, { pitch = LK.rumble.pitch * 0.8, volume = LK.rumble.volume })
	end)
	CameraController.shake(secs, LK.shake)
	local rng = Random.new()
	local seeds = {}
	for i = 1, count do
		seeds[i] = {
			x = rng:NextNumber(),
			speed = rng:NextNumber(0.8, 1.6),
			len = rng:NextNumber(0.08, 0.3),
			off = rng:NextNumber(),
		}
	end
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local f = math.clamp((os.clock() - t0) / secs, 0, 1)
		glow.BackgroundTransparency = 1 - 0.55 * math.sin(math.min(f, 0.85) / 0.85 * math.pi / 2)
		for i = 1, count do
			local s = streaks[i]
			local sd = seeds[i]
			local y = 1.2 - ((os.clock() - t0) * sd.speed * (0.6 + f * 1.6) + sd.off) % 1.5
			s.Visible = f > 0.1
			s.Size = UDim2.fromOffset(2 + f * 3, view.Y * sd.len * (0.5 + f))
			s.Position = UDim2.fromScale(sd.x, y)
			s.BackgroundTransparency = 1 - 0.7 * f
		end
		white.BackgroundTransparency = 1 - math.clamp((f - 0.78) / 0.22, 0, 1)
		if f >= 1 then
			conn:Disconnect()
		end
	end)
end

-- the burst out of the clouds: the white-out clears, cloud puffs fly past the camera, the world's name
local function arrive(dest: number)
	for _, s in streaks do
		s.Visible = false
	end
	glow.BackgroundTransparency = 1
	white.BackgroundTransparency = 0
	TweenService:Create(
		white,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
	note.TextTransparency, note.TextStrokeTransparency = 1, 1
	title.Text = destName(dest)
	title.TextTransparency, title.TextStrokeTransparency = 0, 0
	task.delay(2.4, function()
		TweenService:Create(title, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
	end)
	AudioController.play("moveTrain", nil, { pitch = 0.7, volume = 0.6 })
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(60, 30, 60)
	p.CFrame = cam.CFrame * CFrame.new(0, -10, -20)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxassetid://" .. Config.Fx.lib.textures.smoke.id
	e.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255))
	e.Size = NumberSequence.new(14, 30)
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(40, 90)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.LightInfluence = 0.5
	e.Rate = 0
	e.Parent = p
	p.Parent = cam
	e:Emit(LK.burst[QualityController.name] or LK.burst.medium)
	task.delay(2, function()
		p:Destroy()
	end)
	tripUntil = 0
end

------------------------------------------------------------------------------------------------- lighting by zone

local function remember()
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	saved = {
		ambient = Lighting.Ambient,
		brightness = Lighting.Brightness,
		air = air and {
			Density = air.Density,
			Haze = air.Haze,
			Color = air.Color,
			Decay = air.Decay,
			Glare = air.Glare,
			Offset = air.Offset,
		},
		clouds = clouds and clouds.Enabled,
	}
end

local function restore()
	local s = saved
	if not s then
		return
	end
	Lighting.Ambient = s.ambient
	Lighting.Brightness = s.brightness
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	if air and s.air then
		for k, v in s.air do
			(air :: any)[k] = v
		end
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds and s.clouds ~= nil then
		clouds.Enabled = s.clouds
	end
	if held ~= nil and WorldClient.clockOverride == held then
		WorldClient.clockOverride = nil
	end
	held = nil
	saved = nil
end

local function light(zone: any)
	if zone == nil then
		restore()
		return
	end
	if not saved then
		remember()
	end
	local w = if type(zone) == "number" then S.worlds[zone] else nil
	local clock = if w then w.clock else S.orbit.clock
	if WorldClient.clockOverride == nil or WorldClient.clockOverride == held then
		WorldClient.clockOverride = clock
		held = clock
	end
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	local look = if w and w.air then w.air else { Density = 0, Haze = 0, Glare = 0 }
	if air then
		for k, v in look do
			(air :: any)[k] = if type(v) == "table" then rgb(v) else v
		end
	end
	Lighting.Ambient = if w and w.ambient then rgb(w.ambient) else Color3.fromRGB(90, 96, 120)
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Enabled = false -- the city's cloud layer is far below (orbit) or another world's sky
	end
end

------------------------------------------------------------------------------------------------- rings near you

local function rings(zone: any): { { ring: SpaceLayout.Ring, dest: number } }
	local out = {}
	if zone == nil then
		local g = Workspace:GetAttribute("OrbitGate")
		if typeof(g) == "Vector3" then
			table.insert(out, {
				ring = { x = g.X, y = g.Y, z = g.Z, r = S.gate.radius, nx = 0, ny = 1, nz = 0 },
				dest = 0,
			})
		end
	elseif zone == "orbit" then
		for i in S.worlds do
			table.insert(out, { ring = SpaceLayout.ring(S, i), dest = i })
		end
	else
		table.insert(out, { ring = SpaceLayout.back(S, zone), dest = 0 })
	end
	return out
end

local REASONS = {
	level = "Reach level %d to go to %s",
	locked = "%s opens in Act 2",
	combat = "Leave the fight first",
	wait = "Not yet",
	far = "Fly through the middle of the ring",
}

local function step()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		lastPos = nil
		return
	end
	local pos = root.Position
	local zone = SpaceLayout.zoneAt(S, pos.X, pos.Y, pos.Z)
	if zone ~= SpaceClient.zone then
		SpaceClient.zone = zone
		light(zone)
		player:SetAttribute("SpaceZone", if zone == nil then "" else tostring(zone))
	end
	local now = os.clock()
	if lastPos and now > tripUntil and now - askedAt > 1.5 then
		local a = { lastPos.X, lastPos.Y, lastPos.Z }
		local b = { pos.X, pos.Y, pos.Z }
		for _, r in rings(zone) do
			if SpaceLayout.crossed(r.ring, a, b) then
				askedAt = now
				Net.send("SpaceGo", r.dest)
				break
			end
		end
	end
	lastPos = pos
end

function SpaceClient.init()
	if not S.on then
		return
	end
	makeGui()
	player:SetAttribute("SpaceZone", "")
	Net.listen("SpaceEntry", function(dest: number, secs: number, ship: number)
		entry(dest, secs, ship == 1)
	end)
	Net.listen("SpaceArrive", function(dest: number)
		arrive(dest)
	end)
	Net.listen("SpaceDenied", function(dest: number, why: string)
		local key = tostring(dest) .. why
		if (deniedSaid[key] or 0) > os.clock() then
			return
		end
		deniedSaid[key] = os.clock() + 4
		local w = S.worlds[dest]
		local need = if dest == 0 then S.gate.level else (w and w.level or 1)
		local text = REASONS[why] or "Not yet"
		if why == "level" then
			text = string.format(text, need, destName(dest))
		elseif why == "locked" then
			text = string.format(text, w and w.id or "It")
		end
		say(text, 3)
	end)
	RunService.Heartbeat:Connect(step)
end

return SpaceClient
