-- WeatherLook (2026-11-21, Everything Left 735, nate 2026-11-20 22:05Z "all six"): the new weathers' pieces on
-- this device, driven by Fx.WeatherFx each frame with the blended look (Shared.WeatherPlan.mix):
-- * snow: flakes in a box over the camera, drifting with the wind; as it settles the roofs nearest the camera get
--   white caps and the lawns' Terrain grass whitens (WeatherPlan.settle), melting after it stops; a broken
--   building's cap goes (Fx.BuildingFx's state)
-- * windy days and blizzards: leaves and paper scraps blowing through, upwind of the camera along the wind
-- * heatwave: shimmer sheets rising off the ground near the camera, the place's SunRays and Bloom stronger
-- * aurora: green and violet curtains (Beams, no particles) high over the camera, only at night
-- * lightning storms: the server's roof strikes (WeatherStrike) drawn as a bolt down to the roof, a flash, a
--   glow on the roof and thunder close by; the server knocks the pieces out (BuildingService.smash)
-- Every emitter's rate is by preset (Config.Weather), and none run under shelter (WeatherFx.sheltered).
-- Studio: Workspace attribute WeatherForce holds a kind (DevPanel "Weather" button cycles them).

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeatherPlan = require(Shared:WaitForChild("WeatherPlan"))
local WorldClock = require(Shared:WaitForChild("WorldClock"))

local Controllers = script.Parent.Parent.Controllers
local AudioController = require(Controllers.AudioController)
local WorldClient = require(Controllers.WorldClient)
local BuildingFx = require(script.Parent.BuildingFx)

local WeatherLook = {}

local W = Config.Weather
local S = W.snow
local D = W.debris
local H = W.heat
local A = W.aurora
local K = W.strikes

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function quiet(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function holderPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	quiet(p)
	p.Transparency = 1
	p.Size = size
	p.Parent = Workspace.CurrentCamera or Workspace
	return p
end

local function emitter(parent: Instance, tex: number, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxassetid://" .. tex
	e.Rate = 0
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- state ---------------------------------------------------------------------------------------------------------
local built = false
local snowPart: Part, snowE: ParticleEmitter
local windPart: Part, leafE: ParticleEmitter, paperE: ParticleEmitter
local heatPart: Part, heatE: ParticleEmitter
local auroraPart: Part
local curtains: { Beam } = {}
local buildings: { any } = {} -- WorldInfo rows { id, x, z, sx, sz, base, top, round }
local caps: { BasePart } = {}
local capFolder: Folder
local capAcc = 0
WeatherLook.cover = 0 -- how white the roofs and lawns are now (0..1)
local lawnBase: { [Enum.Material]: Color3 } = {}
local lastLawn = -1
local sunBase: number? = nil
local bloomBase: number? = nil
local starBase: number? = nil
local auroraShown = 0

local function build()
	built = true
	snowPart = holderPart("WeatherSnow", Vector3.new(S.box, 1, S.box))
	snowE = emitter(snowPart, S.texture, {
		Name = "Snow",
		EmissionDirection = Enum.NormalId.Bottom,
		Speed = NumberRange.new(S.speed[1], S.speed[2]),
		Lifetime = NumberRange.new(S.lifetime[1], S.lifetime[2]),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, S.size[1]),
			NumberSequenceKeypoint.new(1, S.size[2]),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.08, S.transparency),
			NumberSequenceKeypoint.new(0.85, S.transparency),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(rgb(S.color)),
		LightInfluence = 0.6,
		LightEmission = 0.2,
		SpreadAngle = Vector2.new(18, 18),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
	})

	windPart = holderPart("WeatherWind", Vector3.new(D.box, D.box * 0.45, 2))
	local spin = NumberRange.new(-260, 260)
	leafE = emitter(windPart, D.leaf, {
		Name = "Leaves",
		EmissionDirection = Enum.NormalId.Front,
		Speed = NumberRange.new(D.speed[1], D.speed[2]),
		Lifetime = NumberRange.new(D.lifetime[1], D.lifetime[2]),
		Size = NumberSequence.new(D.size[1], D.size[2]),
		Color = ColorSequence.new(rgb(D.leafColors[1]), rgb(D.leafColors[2])),
		LightInfluence = 0.9,
		SpreadAngle = Vector2.new(12, 25),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = spin,
		Drag = 0.4,
	})
	paperE = emitter(windPart, D.paper, {
		Name = "Paper",
		EmissionDirection = Enum.NormalId.Front,
		Speed = NumberRange.new(D.speed[1] * 0.85, D.speed[2] * 0.85),
		Lifetime = NumberRange.new(D.lifetime[1], D.lifetime[2]),
		Size = NumberSequence.new(D.size[1] * 1.2, D.size[2] * 1.3),
		Color = ColorSequence.new(rgb(D.paperColor)),
		LightInfluence = 0.9,
		SpreadAngle = Vector2.new(10, 30),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = spin,
		Drag = 0.5,
	})

	heatPart = holderPart("WeatherHeat", Vector3.new(H.box, 0.2, H.box))
	heatE = emitter(heatPart, H.texture, {
		Name = "Shimmer",
		EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
		Speed = NumberRange.new(H.rise[1], H.rise[2]),
		Lifetime = NumberRange.new(H.lifetime[1], H.lifetime[2]),
		Size = NumberSequence.new(H.size[1], H.size[2]),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, H.transparency),
			NumberSequenceKeypoint.new(0.7, H.transparency),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(rgb(H.color)),
		LightInfluence = 0.4,
		LightEmission = 0.3,
	})

	-- the aurora: curtains of Beams between attachment pairs on one part that follows the camera
	auroraPart = holderPart("WeatherAurora", Vector3.one)
	for i = 1, 4 do
		local a0 = Instance.new("Attachment")
		local a1 = Instance.new("Attachment")
		a0.Parent, a1.Parent = auroraPart, auroraPart
		local b = Instance.new("Beam")
		b.Name = "Curtain" .. i
		b.Attachment0, b.Attachment1 = a0, a1
		b.Texture = "rbxassetid://" .. A.texture
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = A.spread / 2
		b.TextureSpeed = A.drift * (if i % 2 == 0 then -1 else 1)
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = 2
		b.Segments = 24
		b.Width0, b.Width1 = A.width, A.width * 0.8
		local c1, c2 = rgb(A.colors[1]), rgb(A.colors[2])
		b.Color = if i % 2 == 0
			then ColorSequence.new({
				ColorSequenceKeypoint.new(0, c2),
				ColorSequenceKeypoint.new(0.5, c1),
				ColorSequenceKeypoint.new(1, c2),
			})
			else ColorSequence.new({
				ColorSequenceKeypoint.new(0, c1),
				ColorSequenceKeypoint.new(0.6, c2),
				ColorSequenceKeypoint.new(1, c1),
			})
		b.Transparency = NumberSequence.new(1)
		b.Enabled = false
		-- each curtain hangs on its own side of the sky with a wave along it
		local ang = (i - 1) / 4 * math.pi * 2 + 0.4
		local cx, cz = math.sin(ang) * A.depth, math.cos(ang) * A.depth
		local tx, tz = math.cos(ang) * A.spread / 2, -math.sin(ang) * A.spread / 2
		local y = A.height + (i % 2) * 120
		-- Config.Weather.aurora.flip swaps the ends (FaceCamera turns the strip over), so the bright hem hangs low
		local s = if A.flip then -1 else 1
		a0.Position = Vector3.new(cx - tx * s, y, cz - tz * s)
		a1.Position = Vector3.new(cx + tx * s, y + 60, cz + tz * s)
		b.CurveSize0 = 240 * (if i % 2 == 0 then 1 else -1)
		b.CurveSize1 = -180 * (if i % 2 == 0 then 1 else -1)
		b.Parent = auroraPart
		curtains[i] = b
	end

	capFolder = Instance.new("Folder")
	capFolder.Name = "WeatherSnowCaps"
	capFolder.Parent = Workspace

	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for _, m in { Enum.Material.Grass, Enum.Material.LeafyGrass } do
			lawnBase[m] = terrain:GetMaterialColor(m)
		end
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	sunBase = rays and rays.Intensity
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	bloomBase = bloom and bloom.Intensity
	local sky = Lighting:FindFirstChildOfClass("Sky")
	starBase = sky and sky.StarCount
end

-- the buildings' boxes, read once from WorldInfo (the same rows Fx.CityLife's roof flags use)
local function readBuildings()
	local value = ReplicatedStorage:WaitForChild("WorldInfo", 60)
	if not (value and value:IsA("StringValue")) then
		return
	end
	while value.Value == "" do
		value.Changed:Wait()
	end
	local ok, info = pcall(HttpService.JSONDecode, HttpService, value.Value)
	if ok and type(info) == "table" and type(info.buildings) == "table" then
		buildings = info.buildings
	end
end

-- snow caps on the roofs nearest the camera ------------------------------------------------------------------------
local function capFor(i: number): BasePart
	local p = caps[i]
	if not p then
		local part = Instance.new("Part")
		part.Name = "SnowCap"
		quiet(part)
		part.Material = Enum.Material.Snow
		part.Color = rgb(S.capColor)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = capFolder
		caps[i] = part
		p = part
	end
	return p
end

local function placeCaps(cam: Vector3, preset: string)
	local want = if WeatherLook.cover > 0.02 then (S.caps[preset] or S.caps.medium) else 0
	local near = {}
	if want > 0 then
		local r2 = S.capRange * S.capRange
		for _, b in buildings do
			local dx, dz = b[2] - cam.X, b[3] - cam.Z
			local d2 = dx * dx + dz * dz
			if d2 <= r2 and BuildingFx.state(b[1]) == 0 then
				table.insert(near, { b = b, d = d2 })
			end
		end
		table.sort(near, function(a, c)
			return a.d < c.d
		end)
	end
	local n = math.min(#near, want)
	local alpha = 1 - math.clamp(WeatherLook.cover, 0, 1) * 0.97
	for i = 1, n do
		local b = near[i].b
		local p = capFor(i)
		local x, z, sx, sz, top, round = b[2], b[3], b[4], b[5], b[7], b[8]
		if round == 1 then
			p.Shape = Enum.PartType.Cylinder
			local d = math.max(sx, sz) + 0.6
			p.Size = Vector3.new(0.5, d, d)
			p.CFrame = CFrame.new(x, top + 0.25, z) * CFrame.Angles(0, 0, math.pi / 2)
		else
			p.Shape = Enum.PartType.Block
			p.Size = Vector3.new(sx + 0.6, 0.5, sz + 0.6)
			p.CFrame = CFrame.new(x, top + 0.25, z)
		end
		p.Transparency = alpha
		p.Parent = capFolder
	end
	for i = n + 1, #caps do
		caps[i].Parent = nil
	end
end

local function lawns()
	if math.abs(WeatherLook.cover - lastLawn) < 0.01 then
		return
	end
	lastLawn = WeatherLook.cover
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local white = rgb(S.capColor)
	for m, base in lawnBase do
		terrain:SetMaterialColor(m, base:Lerp(white, WeatherLook.cover * S.lawn))
	end
end

-- one frame ------------------------------------------------------------------------------------------------------
-- look: the blended look (sheltered: already the clear look); lead: the camera's lead (flying into the weather);
-- ground: the probed ground height under the camera, or nil
function WeatherLook.step(look: any, cam: Vector3, lead: Vector3, ground: number?, dt: number, preset: string)
	if not built then
		build()
	end
	local wind = Vector3.new(look.wind[1], look.wind[2], look.wind[3])

	-- snow
	snowPart.CFrame = CFrame.new(cam + lead + Vector3.new(0, S.above, 0) - wind * 0.8)
	snowE.Rate = (S.flakes[preset] or S.flakes.medium) * look.snow
	snowE.Acceleration = wind

	-- leaves and paper: a sheet upwind of the camera, blowing along the wind
	local flat = Vector3.new(wind.X, 0, wind.Z)
	local debris = look.debris
	if debris > 0.02 and flat.Magnitude > 1 then
		local dir = flat.Unit
		local at = cam + lead - dir * (D.box * 0.5) + Vector3.new(0, 4, 0)
		if ground then
			at = Vector3.new(at.X, math.max(at.Y - 10, (ground :: number) + D.box * 0.2), at.Z)
		end
		windPart.CFrame = CFrame.lookAt(at, at + dir)
		local rate = (D.rate[preset] or D.rate.medium) * debris
		leafE.Rate = rate * 0.6
		paperE.Rate = rate * 0.4
		local acc = Vector3.new(wind.X * 0.15, -3, wind.Z * 0.15)
		leafE.Acceleration, paperE.Acceleration = acc, acc
	else
		leafE.Rate, paperE.Rate = 0, 0
	end

	-- heat shimmer on the ground near the camera
	if look.heat > 0.02 and ground and cam.Y - (ground :: number) < 120 then
		heatPart.CFrame = CFrame.new(cam.X + lead.X, (ground :: number) + 0.5, cam.Z + lead.Z)
		heatE.Rate = (H.rate[preset] or 0) * look.heat
	else
		heatE.Rate = 0
	end

	-- the snow settles and melts; roofs and lawns follow
	WeatherLook.cover = WeatherPlan.settle(W, WeatherLook.cover, look.whiten * math.min(1, look.snow), dt)
	capAcc += dt
	if capAcc >= S.capEvery then
		capAcc = 0
		placeCaps(cam, preset)
		lawns()
		-- the sun's rays and bloom by the heat
		local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
		if rays and sunBase then
			rays.Intensity = sunBase + H.sunRays * look.heat
		end
		local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
		if bloom and bloomBase then
			bloom.Intensity = bloomBase + H.bloom * look.heat
		end
	end

	-- the aurora: only at night, eased in and out
	local phase, f = WorldClock.phase(Config.World.clock, WorldClient.clockT())
	local night = if WorldClient.clockOverride ~= nil then 0 else WeatherPlan.nightShare(phase, f)
	local want = look.aurora * night
	auroraShown += (want - auroraShown) * math.min(1, dt / A.fade * 3)
	local on = auroraShown > 0.02
	local count = A.curtains[preset] or A.curtains.medium
	for i, b in curtains do
		b.Enabled = on and i <= count
	end
	if on then
		auroraPart.CFrame = CFrame.new(cam.X, math.max(cam.Y, 0), cam.Z)
		local a = 1 - 0.85 * auroraShown
		local seq = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, a),
			NumberSequenceKeypoint.new(0.8, a),
			NumberSequenceKeypoint.new(1, 1),
		})
		for _, b in curtains do
			b.Transparency = seq
		end
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky and starBase then
		sky.StarCount = if on then math.max(starBase, A.stars) else starBase
	end
end

-- a lightning storm's strike on a roof (the server's WeatherStrike): the bolt, a glow and sparks, thunder close
-- by. Returns how bright the flash is (0..1) for WeatherFx's grade, by distance.
function WeatherLook.strike(x: number, y: number, z: number, seed: number, cam: Vector3): number
	local d = (Vector3.new(x, y, z) - cam).Magnitude
	if d > K.show then
		return 0
	end
	local top = y + 520
	local pts = WeatherPlan.strikeBolt(x, y, z, top, seed)
	local folder = Instance.new("Folder")
	folder.Name = "WeatherStrike"
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i][1], pts[i][2], pts[i][3])
		local b = Vector3.new(pts[i + 1][1], pts[i + 1][2], pts[i + 1][3])
		local p = Instance.new("Part")
		quiet(p)
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(225, 215, 255)
		local w = 1.4 + 1.6 * (i / #pts)
		p.Size = Vector3.new(w, w, (b - a).Magnitude + w)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p.Parent = folder
	end
	local hit = Instance.new("Part")
	quiet(hit)
	hit.Transparency = 1
	hit.Size = Vector3.one
	hit.CFrame = CFrame.new(x, y + 1, z)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 190, 255)
	light.Range = 60
	light.Brightness = 6
	light.Parent = hit
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxassetid://" .. Config.Fx.lib.textures.spark.id
	sparks.Color = ColorSequence.new(Color3.fromRGB(235, 225, 255))
	sparks.LightEmission = 1
	sparks.Speed = NumberRange.new(30, 70)
	sparks.SpreadAngle = Vector2.new(80, 80)
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Size = NumberSequence.new(1.2, 0)
	sparks.Acceleration = Vector3.new(0, -80, 0)
	sparks.Rate = 0
	sparks.Parent = hit
	hit.Parent = folder
	folder.Parent = Workspace.CurrentCamera or Workspace
	sparks:Emit(40)
	task.delay(K.flash, function()
		for _, c in folder:GetChildren() do
			if c:IsA("BasePart") and c ~= hit then
				c:Destroy()
			end
		end
	end)
	task.delay(1.2, function()
		folder:Destroy()
	end)
	-- PLACEHOLDER SOUND: the collapse rumble pitched down (as the storm's thunder) until a recorded thunder clip
	local near = 1 - math.clamp(d / K.show, 0, 1)
	AudioController.play(
		"collapse",
		nil,
		{ pitch = K.pitch + 0.2 * near, volume = K.volume * (0.35 + 0.65 * near) }
	)
	return 0.4 + 0.6 * near
end

function WeatherLook.init()
	task.spawn(readBuildings)
end

return WeatherLook
