-- AuraFx: what buffs and Awakening look like on every hero (theirs and others'). Reads the Aura bitmask and
-- the Awakened flag that HeroService puts on each player, so nothing extra crosses the network.
--   Awakened   a gold glow outline (Anime heroes get a white-hot core) and rising sparks
--   shield     a see-through bubble (Glacier Armor, Frost Shell)
--   Brace      an orange outline; Rally Roar red; Overcharge set-coloured; Parry Stance white
-- Art (Everything Left 387, 2026-11-20): the shield bubble is Art.Guard's geodesic bubble (a ForceField ball while
-- the mesh is missing) and the Awakened sparks rise as textured motes (Config.Fx.lib.textures spark and glow, the
-- uploaded sheets) with the old rings under them; the outlines stay Highlights (the readable buff colour).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CombatFx = require(script.Parent.CombatFx)
local PhaseClient = require(script.Parent.Parent.Controllers.PhaseClient) -- "Hide you fully" (nate, 2026-11-20)

local AuraFx = {}

local BIT = {
	shield = 1,
	mitigation = 2,
	attackSpeed = 4,
	power = 8,
	speed = 16,
	parry = 32,
	resist = 64,
	zeroG = 128,
}
local GOLD = Color3.fromRGB(255, 220, 90)

type Rig = {
	highlight: Highlight,
	bubble: BasePart,
	motes: ParticleEmitter,
	char: Model,
	lastKey: string,
	nextSpark: number,
}

local function texOf(name: string): string
	local t = Config.Fx.lib.textures[name]
	if not t then
		return ""
	end
	return if t.id and t.id > 0 then "rbxassetid://" .. tostring(t.id) else t.builtin
end

-- the shield bubble: Art.Guard's geodesic bubble, else a ForceField ball
local function bubblePart(): BasePart
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Guard")
	local src = set and set:FindFirstChild("GuardBubble", true)
	if src and src:IsA("MeshPart") then
		local p = MeshFix.clone(src)
		for _, c in p:GetChildren() do
			c:Destroy()
		end
		p:SetAttribute("Mesh", true)
		return p
	end
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	return b
end
AuraFx._bubblePart = bubblePart
local rigs: { [Player]: Rig } = {}

local function rigFor(player: Player): Rig?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then
		return nil
	end
	local rig = rigs[player]
	if rig and rig.char == char then
		return rig
	end
	if rig then
		rig.highlight:Destroy()
		rig.bubble:Destroy()
		rig.motes:Destroy()
	end
	local h = Instance.new("Highlight")
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = char
	h.Parent = char
	local b = bubblePart()
	b.Name = "ShieldBubble"
	b.Size = Vector3.one * 7
	b.Material = Enum.Material.ForceField
	b.Color = Color3.fromRGB(170, 225, 255)
	b.Transparency = 1
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Massless = true
	b.CastShadow = false
	b.CFrame = root.CFrame * (if b:GetAttribute("Mesh") then MeshFix.turn("Guard") else CFrame.identity)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = b
	weld.Parent = b
	b.Parent = char
	-- the Awakened motes: textured sparks rising off the hero, on only while Awakened
	local e = Instance.new("ParticleEmitter")
	e.Name = "AwakenMotes"
	e.Texture = texOf("spark")
	e.Enabled = false
	e.Rate = 16
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(3, 6)
	e.Acceleration = Vector3.new(0, 4, 0)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.3, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0.1, 1)
	e.LightEmission = 0.9
	e.Shape = Enum.ParticleEmitterShape.Cylinder
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = root
	local r = { highlight = h, bubble = b, motes = e, char = char, lastKey = "", nextSpark = 0 }
	rigs[player] = r
	return r
end

local function update(player: Player, now: number)
	local aura = player:GetAttribute("Aura") or 0
	local awake = player:GetAttribute("Awakened") == true
	local key = tostring(aura) .. (if awake then "A" else "")
	local rig = rigFor(player)
	if not rig then
		return
	end
	if key ~= rig.lastKey then
		rig.lastKey = key
		local style = player:GetAttribute("FxStyle") or "Comic"
		local set = player:GetAttribute("PowerSet") or "Volt"
		local h = rig.highlight
		local color: Color3? = nil
		if awake then
			color = if style == "Anime" then Color3.new(1, 1, 1) else GOLD
			h.FillColor = GOLD
			h.FillTransparency = 0.8
		else
			h.FillTransparency = 1
			if bit32.band(aura, BIT.parry) ~= 0 then
				color = Color3.new(1, 1, 1)
			elseif bit32.band(aura, BIT.mitigation) ~= 0 then
				color = Color3.fromRGB(255, 150, 60)
			elseif bit32.band(aura, BIT.power) ~= 0 then
				color = Color3.fromRGB(255, 80, 70)
			elseif bit32.band(aura, BIT.attackSpeed) ~= 0 then
				color = CombatFx.colorOf(set)
			elseif bit32.band(aura, BIT.speed) ~= 0 then
				color = Color3.fromRGB(190, 140, 255)
			end
		end
		h.OutlineColor = color or Color3.new(1, 1, 1)
		h.OutlineTransparency = if color then 0.1 else 1
		rig.motes.Enabled = awake and PhaseClient.seesPlayer(player) -- (none for a hero in another phase)
		if awake then
			local mc = if style == "Anime" then Color3.new(1, 1, 1) else GOLD
			rig.motes.Color = ColorSequence.new(mc, GOLD)
		end
		rig.bubble.Transparency = if bit32.band(aura, BIT.shield) ~= 0 then 0.35 else 1
	end
	if awake and now >= rig.nextSpark then
		rig.nextSpark = now + 0.5
		local root = rig.char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local style = player:GetAttribute("FxStyle") or "Comic"
			local off = Vector3.new(math.random() * 4 - 2, -2, math.random() * 4 - 2)
			CombatFx.ring(
				root.Position + off,
				1.5,
				if style == "Anime" then Color3.new(1, 1, 1) else GOLD,
				0.4,
				0.15
			)
		end
	end
end

function AuraFx.init()
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("AuraFx", function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local now = os.clock()
		for _, p in Players:GetPlayers() do
			update(p, now)
		end
		for p in rigs do
			if p.Parent == nil then
				rigs[p] = nil
			end
		end
	end))
	-- the awakening burst for everyone nearby
	local function watch(p: Player)
		p:GetAttributeChangedSignal("Awakened"):Connect(function()
			if p:GetAttribute("Awakened") ~= true then
				return
			end
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local style = p:GetAttribute("FxStyle") or "Comic"
				CombatFx.awaken(
					root.Position,
					style,
					CombatFx.colorOf(p:GetAttribute("PowerSet"), p.UserId),
					p == Players.LocalPlayer
				)
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
end

return AuraFx
