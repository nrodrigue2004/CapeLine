-- WeatherFx (list-combat 2026-11-20, Everything Left 273): the city's weather on this device. Shared.WeatherPlan
-- names the weather from server time (the same sky for everyone, no remote); this draws it: the sky's Atmosphere
-- and the Clouds ease toward the weather's look, a separate ColorCorrection greys and cools the picture, rain falls
-- in a box that follows the camera (drops by preset, Config.Weather.rain) with splash rings on the ground under
-- it, and a storm flashes lightning (a jagged bolt far off, the screen lit twice) with the thunder rolling in
-- seconds later. Underwater (Fx.DeepClient owns the Atmosphere), in the HQ, a mission pocket or a held story sky
-- there is no weather: the rain stops and the look relaxes to the place's own sky.
-- The new weathers (2026-11-21: snow, blizzard, heatwave, windy, lightning storm, aurora) are drawn by Fx.WeatherLook
-- from the same look; the server's roof strikes arrive as WeatherStrike. The kind's name goes on the local player's
-- "Weather" attribute for the radar clock (Ui.Radar).
-- Studio: set the Workspace attribute WeatherForce to a kind name (Config.Weather.order) to hold it.
-- Per-frame work (one CFrame write a box, a probe every 0.25 s, the sky every 0.1 s) runs under FrameProf "WeatherFx".

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local WeatherPlan = require(Shared:WaitForChild("WeatherPlan"))

local Controllers = script.Parent.Parent.Controllers
local AudioController = require(Controllers.AudioController)
local DeepClient = require(Controllers.DeepClient)
local HqClient = require(Controllers.HqClient)
local QualityController = require(Controllers.QualityController)
local StoryClient = require(Controllers.StoryClient)
local WorldClient = require(Controllers.WorldClient)
local Net = require(Shared:WaitForChild("Net"))
local WeatherLook = require(script.Parent.WeatherLook)

local WeatherFx = {}

local W = Config.Weather
local R = W.rain
local L = W.lightning
local AIR_KEYS = { "Density", "Offset", "Haze", "Glare", "Color", "Decay" }

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function arr(c: Color3): { number }
	return { c.R * 255, c.G * 255, c.B * 255 }
end

-- the place's own sky, read once (what clear weather and shelter go back to)
local base: { air: { [string]: any }, clouds: { cover: number, density: number } }? = nil
local grade: ColorCorrectionEffect? = nil
local rainPart: Part? = nil
local rainEmitter: ParticleEmitter? = nil
local splashPart: Part? = nil
local splashEmitter: ParticleEmitter? = nil
local cloudsRead = false
local groundY: number? = nil
local lastCam: Vector3? = nil
local shown: { [number]: boolean } = {} -- lightning windows whose bolt has shown
local rolled: { [number]: boolean } = {} -- and whose thunder has rolled
local strikeFlash = 0 -- a roof strike's flash, fading (WeatherLook.strike)
WeatherFx.look = nil :: WeatherPlan.Look?
WeatherFx.kind = "clear"

local function readBase()
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	local b = { air = {}, clouds = { cover = 0.55, density = 0.6 } }
	if air then
		for _, key in AIR_KEYS do
			local v = (air :: any)[key]
			b.air[key] = if typeof(v) == "Color3" then arr(v) else v
		end
	end
	base = b
end

local function cloudsBase()
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local c = terrain and terrain:FindFirstChildOfClass("Clouds")
	if c and base and not cloudsRead then
		cloudsRead = true
		base.clouds = { cover = c.Cover, density = c.Density }
	end
	return c
end

local function emitterPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = Workspace.CurrentCamera or Workspace
	return p
end

local function build()
	local g = Instance.new("ColorCorrectionEffect")
	g.Name = "WeatherGrade"
	g.Parent = Lighting
	grade = g

	local rp = emitterPart("WeatherRain", Vector3.new(R.box, 1, R.box))
	local e = Instance.new("ParticleEmitter")
	e.Name = "Rain"
	e.Texture = "rbxassetid://" .. R.texture
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Speed = NumberRange.new(R.speed[1], R.speed[2])
	e.Lifetime = NumberRange.new(R.lifetime[1], R.lifetime[2])
	e.Size = NumberSequence.new(R.size)
	e.Squash = NumberSequence.new(R.squash)
	e.Transparency = NumberSequence.new(R.transparency)
	e.Color = ColorSequence.new(rgb(R.color))
	e.LightInfluence = 0.7
	e.LightEmission = 0.15
	e.Acceleration = Vector3.new(R.wind[1], R.wind[2], R.wind[3]) -- the look's wind each frame
	e.SpreadAngle = Vector2.new(3, 3)
	e.Rate = 0
	e.Parent = rp
	rainPart, rainEmitter = rp, e

	local sp = emitterPart("WeatherSplash", Vector3.new(R.box * 0.45, 0.2, R.box * 0.45))
	local s = Instance.new("ParticleEmitter")
	s.Name = "Splash"
	s.Texture = "rbxassetid://" .. R.splash
	s.EmissionDirection = Enum.NormalId.Top
	s.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	s.Speed = NumberRange.new(0.05)
	s.Lifetime = NumberRange.new(0.28, 0.4)
	s.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, R.splashSize * 0.2),
		NumberSequenceKeypoint.new(1, R.splashSize),
	})
	s.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	s.Color = ColorSequence.new(rgb(R.color))
	s.LightInfluence = 0.8
	s.Rate = 0
	s.Parent = sp
	splashPart, splashEmitter = sp, s
end

-- Is the camera somewhere weather does not reach?
function WeatherFx.sheltered(cam: Vector3): boolean
	if DeepClient.underwater or HqClient.inside() then
		return true
	end
	if WorldClient.clockOverride ~= nil or StoryClient.inOpening() then
		return true
	end
	-- the orbit and the other worlds (Controllers.SpaceClient lights them): no city weather up there
	local space = Players.LocalPlayer:GetAttribute("SpaceZone")
	if type(space) == "string" and space ~= "" then
		return true
	end
	return PocketLayout.at(Config, cam.X, cam.Y, cam.Z) ~= nil
end

-- The weather now, or the Studio hold (Workspace WeatherForce)
local function current(t: number): (string, string, number)
	local force = Workspace:GetAttribute("WeatherForce")
	if type(force) == "string" and W.kinds[force] then
		return force, force, 1
	end
	local from, to, k = WeatherPlan.at(W, t)
	return from, to, k
end

local function bolt(window: number, cam: Vector3)
	local pts = WeatherPlan.bolt(W, window, 650, 470)
	local folder = Instance.new("Folder")
	folder.Name = "WeatherBolt"
	for i = 1, #pts - 1 do
		local a = Vector3.new(cam.X + pts[i][1], pts[i][2], cam.Z + pts[i][3])
		local b = Vector3.new(cam.X + pts[i + 1][1], pts[i + 1][2], cam.Z + pts[i + 1][3])
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(215, 228, 255)
		local w = if i == 1 then 3.2 else 2.4
		p.Size = Vector3.new(w, w, (b - a).Magnitude + 1)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p.Parent = folder
	end
	folder.Parent = Workspace.CurrentCamera or Workspace
	task.delay(L.flash, function()
		folder:Destroy()
	end)
end

local skyAcc = 0
local probeAcc = 0
local function step(dt: number)
	local camObj = Workspace.CurrentCamera
	if not (camObj and W.on) then
		return
	end
	if not rainPart then
		build()
	end
	local cam = camObj.CFrame.Position
	local t = Workspace:GetServerTimeNow()
	local from, to, k = current(t)
	local b = base :: any
	local look = WeatherPlan.mix(W, from, to, k, b)
	local under = DeepClient.underwater
	local inside = WeatherFx.sheltered(cam)
	if inside then
		look = WeatherPlan.mix(W, "clear", "clear", 1, b)
	end
	WeatherFx.look = look
	WeatherFx.kind = if k < 0.5 then from else to

	-- rain: a box above the camera, led by the camera's speed so a flying hero flies into it, not out of it
	local vel = if lastCam then (cam - lastCam) / math.max(dt, 1 / 240) else Vector3.zero
	lastCam = cam
	if vel.Magnitude > 400 then
		vel = Vector3.zero -- a teleport, not a flight
	end
	local lead = Vector3.new(vel.X, 0, vel.Z) * 0.6
	local preset = QualityController.name
	local rate = (R.drops[preset] or R.drops.medium) * look.rain
	local rp, re = rainPart :: Part, rainEmitter :: ParticleEmitter
	rp.CFrame = CFrame.new(cam + lead + Vector3.new(0, R.above, 0))
	re.Rate = rate
	re.Acceleration = Vector3.new(look.wind[1], look.wind[2], look.wind[3])
	-- the rain bed follows the rain (alive-world 2026-11-20); none underwater
	local wet = if under then 0 else look.rain
	AudioController.loop("rain", wet > 0.02, (R.sound or 0) * wet)

	-- splashes on the ground under the camera (its height probed a few times a second)
	probeAcc += dt
	if probeAcc >= R.probe then
		probeAcc = 0
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { camObj }
		local char = Players.LocalPlayer.Character
		if char then
			table.insert(ignore, char)
		end
		params.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(cam, Vector3.new(0, -140, 0), params)
		groundY = if hit then hit.Position.Y else nil
	end
	local sp, se = splashPart :: Part, splashEmitter :: ParticleEmitter
	if groundY and look.rain > 0.05 then
		sp.CFrame = CFrame.new(cam.X + lead.X, (groundY :: number) + 0.15, cam.Z + lead.Z)
		se.Rate = (R.splashes[preset] or 0) * look.rain
	else
		se.Rate = 0
	end

	-- the new weathers' pieces (snow, caps, debris, shimmer, aurora)
	WeatherLook.step(look, cam, lead, groundY, dt, preset)
	local name = if WeatherFx.kind == "clear" or inside then "" else (W.names[WeatherFx.kind] or "")
	if Players.LocalPlayer:GetAttribute("Weather") ~= name then
		Players.LocalPlayer:SetAttribute("Weather", name)
	end
	-- the gust for the flags (Fx.CityLife) and the wind bed (AudioController), in steps so it replicates rarely
	local gust = math.floor((if inside then 0 else look.gust) * 20 + 0.5) / 20
	if Players.LocalPlayer:GetAttribute("WeatherGust") ~= gust then
		Players.LocalPlayer:SetAttribute("WeatherGust", gust)
	end

	-- lightning: the flash lights the grade; each window's bolt shows once and its thunder rolls once
	strikeFlash = math.max(0, strikeFlash - dt * 3)
	local flash = if inside then 0 else strikeFlash
	if look.lightning and not inside then
		flash = math.max(flash, WeatherPlan.flash(W, t))
		local w = math.floor(t / L.gap)
		local at, thunder = WeatherPlan.strike(W, w)
		if at and t >= at and t < at + L.flash and not shown[w] then
			shown[w] = true
			bolt(w, cam)
		end
		if at and t >= thunder and t < thunder + 1 and not rolled[w] then
			rolled[w] = true
			-- PLACEHOLDER SOUND: the collapse rumble pitched down until a recorded thunder clip (Tasks)
			AudioController.play("collapse", nil, { pitch = L.pitch, volume = L.volume })
		end
		shown[w - 4], rolled[w - 4] = nil, nil
	end

	-- the sky and the grade, eased a few times a second (underwater the Atmosphere is DeepClient's)
	skyAcc += dt
	local g = grade :: ColorCorrectionEffect
	g.Brightness = g.Brightness
		+ (look.grade.brightness + flash * L.bright - g.Brightness) * math.min(1, dt * 12)
	if skyAcc < 0.1 then
		return
	end
	skyAcc = 0
	g.Saturation += (look.grade.saturation - g.Saturation) * 0.15
	g.TintColor = g.TintColor:Lerp(rgb(look.grade.tint), 0.15)
	local space = Players.LocalPlayer:GetAttribute("SpaceZone")
	if under or (type(space) == "string" and space ~= "") then
		return -- underwater DeepClient owns the Atmosphere, in space SpaceClient does
	end
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	if air then
		for key, v in look.air do
			local cur = (air :: any)[key]
			if typeof(cur) == "Color3" then
				(air :: any)[key] = cur:Lerp(rgb(v), 0.15)
			elseif type(cur) == "number" then
				(air :: any)[key] = cur + (v - cur) * 0.15
			end
		end
	end
	local clouds = cloudsBase()
	if clouds then
		clouds.Cover += (look.clouds.cover - clouds.Cover) * 0.15
		clouds.Density += (look.clouds.density - clouds.Density) * 0.15
	end
end

function WeatherFx.init()
	if not W.on then
		return
	end
	readBase()
	cloudsBase()
	WeatherLook.init()
	-- a lightning storm's strike on a roof near a hero (server WeatherService): x, y, z, seed
	Net.listen("WeatherStrike", function(x: number, y: number, z: number, seed: number)
		local camObj = Workspace.CurrentCamera
		if not camObj or WeatherFx.sheltered(camObj.CFrame.Position) then
			return
		end
		strikeFlash = math.max(strikeFlash, WeatherLook.strike(x, y, z, seed, camObj.CFrame.Position))
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("WeatherFx", step))
end

return WeatherFx
