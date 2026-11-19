-- IceFx: the frost pieces' looks on every screen (gap polish 2026-11-19; they were plain ice parts). The server
-- (CombatService) tags each Snow Wall slab, Ice Slide ramp and Frost raft "IceLook" with its IceKind; this dresses
-- it with parts parented to it (so they go when it goes) that never collide, take hits or touches:
-- * wall: jagged ice shards along its top (PolishPlan.wallShards), a snow cap, a snow drift at its foot and
--   drifting frost motes (the effects library's snowflake sheet)
-- * ramp: snow rails along both sloped edges (thin wedges matching the slope) and frost motes
-- * raft: a snow rim round its top
-- The tagged part itself (its size, collision box and life) is unchanged. Budgets per device preset
-- (Config.Fx.polish.presets: shards, frost motes; low draws no motes). Nothing runs per frame.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FxPlan = require(Shared:WaitForChild("FxPlan"))
local PolishPlan = require(Shared:WaitForChild("PolishPlan"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local IceFx = {}

local I = Config.Fx.polish.ice

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function budget(): any
	return Config.Fx.polish.presets[QualityController.name] or Config.Fx.polish.presets.medium
end

local function deco(
	class: string,
	parent: BasePart,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material
): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = "IceLook"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Parent = parent
	return p
end

local function motes(part: BasePart, rate: number)
	if rate <= 0 then
		return
	end
	local L = Config.Fx.lib
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "IceMotes"
	pe.Texture = (FxPlan.textureOf(L, "flake"))
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(1.2, 2)
	pe.Speed = NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -1.5, 0)
	pe.Size = NumberSequence.new(0.35, 0.1)
	pe.Transparency = NumberSequence.new(0.1, 1)
	pe.LightEmission = 0.6
	pe.Color = ColorSequence.new(rgb(I.snow), rgb(I.color))
	pe.RotSpeed = NumberRange.new(-90, 90)
	-- a box emitter on a part fills the part (the whole slab or ramp)
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.Parent = part
end

local function wall(p: BasePart)
	local b = budget()
	local s = p.Size
	local ice, snow, deep = rgb(I.color), rgb(I.snow), rgb(I.deep)
	-- shards: two wedges back to back make a spike
	local seed = math.floor(p.Position.X * 3 + p.Position.Z * 5)
	for _, sh in PolishPlan.wallShards(s.X, s.Y, s.Z, b.shards, seed) do
		local base = p.CFrame * CFrame.new(sh.x, sh.y, 0) * CFrame.Angles(0, 0, math.rad(sh.rz))
		local half = Vector3.new(sh.d, sh.h, sh.w / 2)
		local a = deco(
			"WedgePart",
			p,
			half,
			base * CFrame.new(-sh.w / 4, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
			ice,
			Enum.Material.Ice
		)
		local c = deco(
			"WedgePart",
			p,
			half,
			base * CFrame.new(sh.w / 4, 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
			deep,
			Enum.Material.Ice
		)
		a.Transparency, c.Transparency = 0.1, 0.15
	end
	-- the snow cap and the drift at its foot
	deco(
		"Part",
		p,
		Vector3.new(s.X + 0.2, 0.45, s.Z + 0.3),
		p.CFrame * CFrame.new(0, s.Y / 2 - 0.1, 0),
		snow,
		Enum.Material.Snow
	)
	for _, side in { -1, 1 } do
		deco(
			"WedgePart",
			p,
			Vector3.new(s.X + 0.4, 0.9, 1.1),
			p.CFrame
				* CFrame.new(0, -s.Y / 2 + 0.45, side * (s.Z / 2 + 0.5))
				* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
			snow,
			Enum.Material.Snow
		)
	end
	motes(p, b.frost)
end

local function ramp(p: BasePart)
	local b = budget()
	local s = p.Size
	local snow = rgb(I.snow)
	-- rails: thin wedges with the ramp's own slope, at both edges, a little proud of the surface
	for _, side in { -1, 1 } do
		deco(
			"WedgePart",
			p,
			Vector3.new(0.7, s.Y + 0.3, s.Z),
			p.CFrame * CFrame.new(side * (s.X / 2 - 0.35), 0.15, 0),
			snow,
			Enum.Material.Snow
		)
	end
	-- a snow lip where it meets the ground (the ramp's low end)
	deco(
		"Part",
		p,
		Vector3.new(s.X + 0.4, 0.4, 1.2),
		p.CFrame * CFrame.new(0, -s.Y / 2 + 0.2, -s.Z / 2 - 0.3),
		snow,
		Enum.Material.Snow
	)
	motes(p, b.frost)
end

local function raft(p: BasePart)
	local s = p.Size
	local snow = rgb(I.snow)
	for _, e in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
		local along = if e[1] == 0 then Vector3.new(s.X, 0.35, 0.6) else Vector3.new(0.6, 0.35, s.Z)
		deco(
			"Part",
			p,
			along,
			p.CFrame * CFrame.new(e[1] * (s.X / 2 - 0.3), s.Y / 2 + 0.1, e[2] * (s.Z / 2 - 0.3)),
			snow,
			Enum.Material.Snow
		)
	end
end

local DRESS = { wall = wall, ramp = ramp, raft = raft }

local function dress(inst: Instance)
	if not inst:IsA("BasePart") or inst:FindFirstChild("IceLook") then
		return
	end
	local kind = inst:GetAttribute("IceKind")
	local fn = DRESS[kind :: string]
	if fn then
		pcall(fn, inst)
	end
end

function IceFx.init()
	for _, inst in CollectionService:GetTagged("IceLook") do
		dress(inst)
	end
	CollectionService:GetInstanceAddedSignal("IceLook"):Connect(dress)
end

return IceFx
