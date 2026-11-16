-- AuraFx: what buffs and Awakening look like on every hero (theirs and others'). Reads the Aura bitmask and
-- the Awakened flag that HeroService puts on each player, so nothing extra crosses the network.
--   Awakened   a gold glow outline (Anime heroes get a white-hot core) and rising sparks
--   shield     a see-through bubble (Glacier Armor, Frost Shell)
--   Brace      an orange outline; Rally Roar red; Overcharge set-coloured; Parry Stance white
-- PLACEHOLDER ART: Highlights and a ForceField ball until the VFX pass.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CombatFx = require(script.Parent.CombatFx)

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

type Rig = { highlight: Highlight, bubble: Part, char: Model, lastKey: string, nextSpark: number }
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
	end
	local h = Instance.new("Highlight")
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = char
	h.Parent = char
	local b = Instance.new("Part")
	b.Name = "ShieldBubble"
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.one * 7
	b.Material = Enum.Material.ForceField
	b.Color = Color3.fromRGB(170, 225, 255)
	b.Transparency = 1
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Massless = true
	b.CastShadow = false
	b.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = b
	weld.Parent = b
	b.Parent = char
	local r = { highlight = h, bubble = b, char = char, lastKey = "", nextSpark = 0 }
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
		rig.bubble.Transparency = if bit32.band(aura, BIT.shield) ~= 0 then 0.35 else 1
	end
	if awake and now >= rig.nextSpark then
		rig.nextSpark = now + 0.25
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
	RunService.Heartbeat:Connect(function(dt)
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
	end)
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
