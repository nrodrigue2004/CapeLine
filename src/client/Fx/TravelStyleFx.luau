-- TravelStyleFx: travel power styles on every screen (spec: Hero MMO features > Travel power styles; H8).
-- Each player with the TravelStyle attribute (TravelStyleService) gets the style's trail on their root while
-- they move fast, a take-off burst when they speed up or leap, and a landing effect when a fast fall ends;
-- your own swing line takes the style's colour (MoveController.lineColor). Looks only: it reads velocities,
-- never sets one. Juice "styleBurst" plays the whoosh with the burst.
-- Art (Everything Left 143, 2026-11-20): the bursts and motes draw the effects library's uploaded sheets and the
-- trails the uploaded flight trail strips, picked by the style's burst kind (Config.TravelStyles.art).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local TravelStyleRules = require(Shared:WaitForChild("TravelStyleRules"))

local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local Juice = require(script.Parent.Juice)

local TravelStyleFx = {}

local TS = Config.TravelStyles
local TAG = "TravelStyleFx"
local me = Players.LocalPlayer

type Rig = {
	style: any,
	root: BasePart,
	trail: Trail,
	motes: ParticleEmitter,
	fast: boolean,
	fall: number,
	air: boolean,
}
local rigs: { [Player]: Rig } = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- the burst kind's mote sheet (a flipbook where the sheet is one) and trail strip; Roblox's image for an id of 0
local function moteTex(e: ParticleEmitter, style: any)
	local a = TS.art and TS.art[style.burst]
	local t = a and Config.Fx.lib.textures[a.mote]
	if not t or not t.id or t.id <= 0 then
		return
	end
	e.Texture = "rbxassetid://" .. tostring(t.id)
	if t.flip == 4 then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
end

local function trailTex(tr: Trail, style: any)
	local a = TS.art and TS.art[style.burst]
	local k = a and Config.Creator.trailFx and Config.Creator.trailFx.kits[a.trail]
	if not k or not k.id or k.id <= 0 then
		return
	end
	tr.Texture = "rbxassetid://" .. tostring(k.id)
	tr.TextureMode = if k.mode == "Wrap" then Enum.TextureMode.Wrap else Enum.TextureMode.Stretch
	if k.length then
		tr.TextureLength = k.length
	end
end
TravelStyleFx._moteTex = moteTex
TravelStyleFx._trailTex = trailTex

local function strip(char: Model)
	for _, d in char:GetDescendants() do
		if d.Name == TAG then
			d:Destroy()
		end
	end
end

-- A burst of the style's bits at a point (the take-off and the landing)
local function burst(style: any, at: Vector3, big: boolean)
	local p = Instance.new("Part")
	p.Name = TAG
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(at)
	local e = Instance.new("ParticleEmitter")
	moteTex(e, style)
	e.Color = ColorSequence.new(rgb(style.c1), rgb(style.c2))
	e.LightEmission = style.glow
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.SpreadAngle = Vector2.new(180, if style.burst == "ring" then 5 else 180)
	e.Speed =
		NumberRange.new(if style.burst == "ring" then 18 else 6, if style.burst == "ring" then 24 else 14)
	e.Size = NumberSequence.new(if style.burst == "puff" then 1.6 else 0.5, 0)
	e.Transparency = NumberSequence.new(if style.burst == "ink" then 0 else 0.2, 1)
	e.Drag = if style.burst == "petals" then 3 else 1
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Rotation = NumberRange.new(0, 360)
	if style.burst == "ring" then
		e.EmissionDirection = Enum.NormalId.Top
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	end
	e.Parent = p
	p.Parent = Workspace
	if style.burst == "prism" then
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 90)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
		})
	end
	e:Emit(if big then 26 else 14)
	Debris:AddItem(p, 1.2)
end

local function dress(player: Player)
	local old = rigs[player]
	rigs[player] = nil
	local char = player.Character
	if char then
		strip(char)
	end
	if old and player == me then
		MoveController.lineColor = nil
	end
	local id = player:GetAttribute("TravelStyle")
	local style = typeof(id) == "number" and TravelStyleRules.byId(Config, id) or nil
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not style or not root or not root:IsA("BasePart") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = TAG
	a0.Position = Vector3.new(0, style.width / 2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = TAG
	a1.Position = Vector3.new(0, -style.width / 2, 0)
	a1.Parent = root
	local t = Instance.new("Trail")
	t.Name = TAG
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = ColorSequence.new(rgb(style.c1), rgb(style.c2))
	t.Transparency = NumberSequence.new(if style.burst == "ink" then 0.05 else 0.25, 1)
	t.Lifetime = style.life
	t.LightEmission = style.glow
	t.FaceCamera = true
	t.Enabled = false
	trailTex(t, style)
	t.Parent = root
	local m = Instance.new("ParticleEmitter")
	m.Name = TAG
	m.Color = t.Color
	m.LightEmission = style.glow
	m.Rate = 0
	m.Lifetime = NumberRange.new(0.3, 0.6)
	m.Speed = NumberRange.new(0.5, 2)
	m.SpreadAngle = Vector2.new(180, 180)
	m.Size = NumberSequence.new(if style.burst == "puff" then 0.9 else 0.3, 0)
	moteTex(m, style)
	m.Parent = root
	rigs[player] = { style = style, root = root, trail = t, motes = m, fast = false, fall = 0, air = false }
	if player == me then
		MoveController.lineColor = rgb(style.c1)
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("TravelStyle"):Connect(function()
		dress(player)
	end)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		dress(player)
	end)
	if player.Character then
		task.spawn(dress, player)
	end
end

local function step()
	for player, r in rigs do
		if not r.root.Parent then
			rigs[player] = nil
			continue
		end
		local v = r.root.AssemblyLinearVelocity
		local speed = v.Magnitude
		local moving = speed >= TS.showAt
		r.trail.Enabled = moving
		r.motes.Rate = if moving then 12 else 0
		-- other heroes' take-offs and landings come from their speed; yours from MoveController below
		if player ~= me then
			local fast = speed >= TS.burstAt
			if fast and not r.fast then
				burst(r.style, r.root.Position, false)
			end
			r.fast = fast
			if v.Y < -TS.landFall then
				r.fall = -v.Y
			elseif r.fall > 0 and v.Y > -5 then
				burst(r.style, r.root.Position - Vector3.new(0, 2.5, 0), true)
				r.fall = 0
			end
		end
	end
end

function TravelStyleFx.init()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		rigs[p] = nil
	end)
	MoveController.Leaped:Connect(function(pos)
		local r = rigs[me]
		if r then
			burst(r.style, pos, false)
			Juice.fire("styleBurst", pos, { mine = true })
		end
	end)
	MoveController.BoostChanged:Connect(function(on)
		local r = rigs[me]
		if r and on then
			burst(r.style, r.root.Position, false)
			Juice.fire("styleBurst", r.root.Position, { mine = true })
		end
	end)
	MoveController.Landed:Connect(function(pos, fallSpeed)
		local r = rigs[me]
		if r and fallSpeed >= TS.landFall then
			burst(r.style, pos - Vector3.new(0, 2.5, 0), true)
		end
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("TravelStyleFx", step))
end

return TravelStyleFx
