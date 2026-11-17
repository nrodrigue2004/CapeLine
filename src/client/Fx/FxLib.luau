--!strict
-- FxLib: the effects library (overhaul plan step 3). Textured particles that sit under CombatFx's part-built
-- shapes: sparks, lightning crackle, glows, smoke and dust, embers and flames, ice shards, wisps, vortexes,
-- implosions and flat shockwave rings, picked per element (Config.Fx.lib, rules in Shared.FxPlan).
-- * Pooled: one hidden anchored part holds an Attachment with a ParticleEmitter per kind and colour (and per
--   ring size); an effect moves the attachment and calls Emit, so nothing is created per hit.
-- * Capped: a particles-a-second budget per device preset (FxPlan.take), and the preset's share of each count.
-- * Reduce flashing skips the bright kinds (glow, core, crackle).
-- Textures are Roblox's built-in particle images until the generated sheets are uploaded (Config ids).
-- PLACEHOLDER ART until then.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FxPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FxPlan"))
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local FxLib = {}
FxLib.reduceFlashing = false

local L = Config.Fx.lib
local host: Part? = nil
local emitters: { [string]: { att: Attachment, pe: ParticleEmitter } } = {}
local budget: FxPlan.Budget? = nil
local budgetPreset = ""
local WHITE = Color3.new(1, 1, 1)

local function hostPart(): Part
	if host and host.Parent then
		return host
	end
	local p = Instance.new("Part")
	p.Name = "FxEmitters"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(0, -500, 0)
	p.Parent = Workspace
	host = p
	return p
end

local function quantize(c: Color3): string
	return string.format(
		"%d_%d_%d",
		math.floor(c.R * 15 + 0.5),
		math.floor(c.G * 15 + 0.5),
		math.floor(c.B * 15 + 0.5)
	)
end

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local MAX_EMITTERS = 300 -- a rainbow tint makes many colours: past this, reuse the kind's first emitter
local count = 0
local firstOf: { [string]: string } = {}

local function emitterFor(kind: string, color: Color3, size: number?): (Attachment?, ParticleEmitter?)
	local k = L.kinds[kind]
	if not k then
		return nil, nil
	end
	local key = kind .. ":" .. quantize(color) .. ":" .. tostring(size or 0)
	if not emitters[key] and count >= MAX_EMITTERS and firstOf[kind .. tostring(size or 0)] then
		key = firstOf[kind .. tostring(size or 0)]
	end
	local e = emitters[key]
	if e and e.att.Parent then
		return e.att, e.pe
	end
	local att = Instance.new("Attachment")
	att.Name = key
	att.Parent = hostPart()
	local pe = Instance.new("ParticleEmitter")
	pe.Enabled = false
	pe.Rate = 0
	local tex, flip = FxPlan.textureOf(L, kind)
	pe.Texture = tex
	if flip == 4 then
		pe.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	elseif flip == 8 then
		pe.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
		pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
	local s0, s1 = k.size[1], k.size[2]
	if size then
		s0, s1 = size * 0.2, size -- a ring grows to its radius
	end
	pe.Size = seq(s0, s1)
	pe.Lifetime = NumberRange.new(k.life[1], k.life[2])
	pe.Speed = NumberRange.new(k.speed[1], k.speed[2])
	pe.SpreadAngle = Vector2.new(k.spread, k.spread)
	pe.Drag = k.drag
	pe.Acceleration = Vector3.new(0, k.rise, 0)
	pe.LightEmission = k.light
	pe.LightInfluence = if k.light > 0 then 0 else 1
	pe.Transparency = seq(k.alpha, 1)
	pe.Color = ColorSequence.new(if k.light > 0 then color:Lerp(WHITE, 0.25) else color, color)
	if k.spin then
		pe.RotSpeed = NumberRange.new(-k.spin, k.spin)
		pe.Rotation = NumberRange.new(0, 360)
	end
	if k.face == "streak" then
		pe.Orientation = Enum.ParticleOrientation.VelocityParallel
	elseif k.face == "flat" then
		pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		pe.EmissionDirection = Enum.NormalId.Top
	end
	pe.ZOffset = if kind == "glow" or kind == "core" then 1 else 0
	pe.Parent = att
	emitters[key] = { att = att, pe = pe }
	count += 1
	firstOf[kind .. tostring(size or 0)] = firstOf[kind .. tostring(size or 0)] or key
	return att, pe
end

local function share(): number
	local name = QualityController.name
	return L.scale[name] or L.scale.medium
end

local function take(n: number): number
	local name = QualityController.name
	local now = os.clock()
	if not budget or budgetPreset ~= name then
		budget = FxPlan.newBudget(L.budget[name] or L.budget.medium, now)
		budgetPreset = name
	end
	return FxPlan.take(budget :: FxPlan.Budget, n, now)
end

-- emit count particles of one kind at a point (dir: which way directional kinds fly; size: a ring's radius)
function FxLib.emit(kind: string, color: Color3, pos: Vector3, count: number, dir: Vector3?, size: number?)
	if FxLib.reduceFlashing and FxPlan.FLASHY[kind] then
		return
	end
	local n = take(count)
	if n <= 0 then
		return
	end
	local att, pe = emitterFor(kind, color, size)
	if not att or not pe then
		return
	end
	if dir and dir.Magnitude > 1e-3 then
		att.WorldCFrame = CFrame.lookAt(pos, pos + dir)
		pe.EmissionDirection = if L.kinds[kind].face == "flat" then Enum.NormalId.Top else Enum.NormalId.Front
	else
		att.WorldCFrame = CFrame.new(pos)
	end
	pe:Emit(n)
end

local function run(plan: { FxPlan.Emit }, color: Color3, pos: Vector3, dir: Vector3?)
	for _, e in plan do
		FxLib.emit(e.kind, color, pos, e.count, dir)
	end
end

-- a hit landing (scale: 1.5 on a crit, more on supers)
function FxLib.impact(
	pos: Vector3,
	set: string?,
	color: Color3,
	scale: number?,
	dir: Vector3?,
	style: string?
)
	local element = FxPlan.elementOf(L, set)
	local s = (scale or 1) * (if style == "Comic" then 0.8 else 1)
	run(FxPlan.plan(L, element, "impact", share(), s), color, pos, dir)
end

-- along a bolt, beam, chain hop or dash
function FxLib.trail(from: Vector3, to: Vector3, set: string?, color: Color3)
	local d = to - from
	local len = d.Magnitude
	if len < 1 then
		return
	end
	local element = FxPlan.elementOf(L, set)
	local plan = FxPlan.plan(L, element, "trail", share(), 1)
	for _, t in FxPlan.trailPoints(L, len) do
		run(plan, color, from + d * t, nil)
	end
end

-- an area going off: the element's burst plus a flat shockwave ring at the floor
function FxLib.burst(center: Vector3, radius: number, set: string?, color: Color3, big: boolean?)
	local element = FxPlan.elementOf(L, set)
	run(FxPlan.plan(L, element, "burst", share(), if big then 1.6 else 1), color, center, nil)
	FxLib.shock(center - Vector3.new(0, 1.2, 0), radius, color)
end

function FxLib.shock(at: Vector3, radius: number, color: Color3)
	FxLib.emit("shock", color, at, 1, Vector3.new(0, 1, 0), FxPlan.shockRadius(L, radius))
end

-- the gather before a cast (windups, charged moves)
function FxLib.gather(pos: Vector3, set: string?, color: Color3)
	FxLib.emit("implode", color, pos, 1)
	local element = FxPlan.elementOf(L, set)
	if element == "electric" or element == "tech" then
		FxLib.emit("crackle", color, pos, 2)
	end
end

-- ground dust (slams, landings, robot stomps)
function FxLib.dust(at: Vector3, radius: number, color: Color3?)
	local c = color or Color3.fromRGB(170, 155, 135)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0.15, math.sin(a))
		FxLib.emit("dust", c, at + dir * radius * 0.3, 1, dir)
	end
end

-- a robot breaking apart: sparks, smoke and a flash
function FxLib.wreck(pos: Vector3)
	FxLib.emit("core", Color3.fromRGB(255, 180, 90), pos, 1)
	FxLib.emit("spark", Color3.fromRGB(255, 200, 120), pos, 18)
	FxLib.emit("smoke", Color3.fromRGB(70, 70, 76), pos, 5)
end

return FxLib
