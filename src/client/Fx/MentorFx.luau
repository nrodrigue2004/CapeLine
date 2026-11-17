-- MentorFx: the mentors' looks and their ally's help (spec: Hero MMO features > Original mentors; H6).
-- * Every player wearing a mentor look (the player attribute MentorLook, set by MentorService once the
--   mentor's quest line is done): a trail behind them (Captain Meridian's gold, The Margrave's violet smoke)
--   or an aura on them (Old Beacon's lantern glow, The Velvet Paw's spark crackle). Looks only, never stats.
-- * The ally in a task force's final fight: a bright beam from the mentor to the robot they hit.
-- * The reward moment: a burst of the new look and a chime.
-- * H7: the accolade aura a player wears (AccoladeAura, from a finished badge group): soft motes round them.
-- PLACEHOLDER ART: engine Trails, ParticleEmitters and a PointLight with default textures until the effects
-- pass (FxLib textures); the beam is a neon part.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Juice = require(script.Parent.Juice)

local MentorFx = {}

local M = Config.Mentors
local looks: { [string]: any } = {}
for _, m in M.list do
	looks[m.look.id] = m.look
end
local TAG = "MentorLookFx"

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function strip(char: Model)
	for _, d in char:GetDescendants() do
		if d.Name == TAG then
			d:Destroy()
		end
	end
end

local function dress(player: Player)
	local char = player.Character
	if not char then
		return
	end
	strip(char)
	local look = looks[player:GetAttribute("MentorLook") :: any]
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
	if not look or not torso or not torso:IsA("BasePart") then
		return
	end
	local c = rgb(look.color)
	if look.kind == "trail" then
		local a0 = Instance.new("Attachment")
		a0.Name = TAG
		a0.Position = Vector3.new(0, 0.9, 0.4)
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.Name = TAG
		a1.Position = Vector3.new(0, -0.9, 0.4)
		a1.Parent = torso
		local t = Instance.new("Trail")
		t.Name = TAG
		t.Attachment0, t.Attachment1 = a0, a1
		t.Color = ColorSequence.new(c, c:Lerp(Color3.new(1, 1, 1), 0.3))
		t.Transparency = NumberSequence.new(if look.id == "violetSmoke" then 0.45 else 0.15, 1)
		t.Lifetime = if look.id == "violetSmoke" then 0.9 else 0.6
		t.MinLength = 0.2
		t.LightEmission = if look.id == "violetSmoke" then 0.1 else 0.8
		t.WidthScale = NumberSequence.new(1, if look.id == "violetSmoke" then 2.2 else 0.3)
		t.Parent = torso
	else
		local e = Instance.new("ParticleEmitter")
		e.Name = TAG
		e.Color = ColorSequence.new(c)
		e.LightEmission = 0.8
		if look.id == "sparkCrackle" then
			e.Rate = 14
			e.Lifetime = NumberRange.new(0.15, 0.3)
			e.Speed = NumberRange.new(6, 10)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.25, 0)
		else
			e.Rate = 6
			e.Lifetime = NumberRange.new(1, 1.6)
			e.Speed = NumberRange.new(0.5, 1.2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.6, 0)
			e.Transparency = NumberSequence.new(0.3, 1)
			local light = Instance.new("PointLight")
			light.Name = TAG
			light.Color = c
			light.Range = 10
			light.Brightness = 1.2
			light.Parent = torso
		end
		e.Parent = torso
	end
end

-- H7: an accolade aura (a finished badge group, Config.Badges): a soft ring of motes on the hero. Looks only.
local AURAS: { [string]: { number } } = {}
for _, g in Config.Badges.groups do
	if g.accolade and g.accolade.kind == "aura" then
		AURAS[g.accolade.id] = g.accolade.color
	end
end
local AURA_TAG = "AccoladeAuraFx"

local function dressAura(player: Player)
	local char = player.Character
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d.Name == AURA_TAG then
			d:Destroy()
		end
	end
	local col = AURAS[player:GetAttribute("AccoladeAura") :: any]
	local root = char:FindFirstChild("HumanoidRootPart")
	if not col or not root or not root:IsA("BasePart") then
		return
	end
	local c = rgb(col)
	local e = Instance.new("ParticleEmitter")
	e.Name = AURA_TAG
	e.Color = ColorSequence.new(c)
	e.LightEmission = 0.7
	e.Rate = 8
	e.Lifetime = NumberRange.new(0.8, 1.2)
	e.Speed = NumberRange.new(0.6, 1.4)
	e.SpreadAngle = Vector2.new(180, 20)
	e.Size = NumberSequence.new(0.35, 0)
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Shape = Enum.ParticleEmitterShape.Cylinder
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.Parent = root
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("MentorLook"):Connect(function()
		dress(player)
	end)
	player:GetAttributeChangedSignal("AccoladeAura"):Connect(function()
		dressAura(player)
	end)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("UpperTorso", 10)
		dress(player)
		dressAura(player)
	end)
	if player.Character then
		dress(player)
		dressAura(player)
	end
end

local function beam(from: Vector3, to: Vector3, color: Color3)
	local d = (to - from).Magnitude
	if d < 0.5 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.5, 0.5, d)
	p.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
	p.Parent = Workspace
	TweenService:Create(p, TweenInfo.new(0.3), { Transparency = 1, Size = Vector3.new(0.1, 0.1, d) }):Play()
	task.delay(0.35, function()
		p:Destroy()
	end)
end

local function burst(player: Player, mentor: number)
	local m = M.list[mentor]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not m or not root or not root:IsA("BasePart") then
		return
	end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = rgb(m.look.color)
	p.Size = Vector3.one * 3
	p.CFrame = root.CFrame
	p.Parent = Workspace
	TweenService:Create(p, TweenInfo.new(0.6), { Size = Vector3.one * 16, Transparency = 1 }):Play()
	task.delay(0.65, function()
		p:Destroy()
	end)
	Juice.fire("mentorReward", root.Position, { mine = true })
end

function MentorFx.init()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Net.listen("MentorState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if d.k == "assist" and typeof(d.from) == "Vector3" and typeof(d.to) == "Vector3" then
			local m = M.list[d.mentor or 0]
			beam(d.from, d.to, if m then rgb(m.look.color) else Color3.new(1, 1, 1))
		elseif d.k == "reward" then
			burst(Players.LocalPlayer, d.mentor or 0)
		end
	end)
end

return MentorFx
