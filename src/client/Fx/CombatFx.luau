-- CombatFx: every combat effect, in two looks (nate, 2026-11-16: superhero and anime). A hero's fxStyle
-- decides how its powers look to everyone:
--   Comic  bold neon bolts with a white core, shockwave rings, star bursts, comic numbers
--   Anime  thin bright beams with afterimages, impact flashes with radial speed lines, an impact frame on
--          crits, sharp numbers
-- Spec juice rows covered here: basic attack (hit flash, number pop), skill cast, crit (gold number x1.5),
-- enemy defeated (parts fly, sparks fade in 2 s). Built-in parts and tweens only; nothing downloaded.
-- PLACEHOLDER ART until the VFX pass (M2 builds the other 29 ability presets on this module).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local CombatFx = {}
CombatFx.reduceFlashing = false

local F = Config.Fx
local folder: Folder
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
local VOLT = rgb(F.voltColor)
local CRIT = rgb(F.critColor)
local ENEMY = rgb(F.enemyShotColor)
local WHITE = Color3.new(1, 1, 1)

local function part(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf
	p.Parent = folder
	return p
end

local function fade(p: BasePart, time: number, props: { [string]: any }?)
	local goal = props or {}
	goal.Transparency = 1
	TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, time + 0.05)
end

local function beam(from: Vector3, to: Vector3, width: number, color: Color3, life: number): Part?
	local d = to - from
	local len = d.Magnitude
	if len < 0.1 then
		return nil
	end
	local p = part(Vector3.new(width, width, len), CFrame.lookAt(from + d / 2, to), color)
	fade(p, life, { Size = Vector3.new(width * 0.2, width * 0.2, len) })
	return p
end

---------------------------------------------------------------------------
-- Casts
---------------------------------------------------------------------------

function CombatFx.bolt(from: Vector3, to: Vector3, style: string)
	if style == "Anime" then
		beam(from, to, F.bolt.width * 0.6, WHITE, F.bolt.life)
		beam(from, to, F.bolt.width * 1.4, VOLT, F.bolt.life * 1.6) -- afterimage glow
	else
		beam(from, to, F.bolt.width * 1.6, VOLT, F.bolt.life * 1.2)
		beam(from, to, F.bolt.width * 0.6, WHITE, F.bolt.life)
	end
end

-- Jagged lightning through a list of points (Chain Lightning)
function CombatFx.chain(points: { Vector3 }, style: string)
	local c = F.chain
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local prev = a
		for s = 1, c.segments do
			local t = s / c.segments
			local nextP = a:Lerp(b, t)
			if s < c.segments then
				nextP += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * c.jitter * 2
			end
			local width = if style == "Anime" then c.width * 0.5 else c.width
			beam(prev, nextP, width, if style == "Anime" then WHITE else VOLT, c.life)
			prev = nextP
		end
	end
end

-- Dash Strike: a streak along the path
function CombatFx.dash(from: Vector3, to: Vector3, style: string)
	if style == "Anime" then
		for k = 0, 2 do
			local off = Vector3.new(0, (k - 1) * 0.8, 0)
			beam(from + off, to + off, 0.2, if k == 1 then WHITE else VOLT, F.dash.trailLife + k * 0.05)
		end
	else
		beam(from, to, 2.2, VOLT, F.dash.trailLife)
		beam(from, to, 0.8, WHITE, F.dash.trailLife * 0.7)
	end
end

---------------------------------------------------------------------------
-- Impacts and numbers
---------------------------------------------------------------------------

local impactFrame: Frame? = nil

local function flashScreen(color: Color3, time: number)
	if CombatFx.reduceFlashing or not impactFrame then
		return
	end
	local f = impactFrame :: Frame
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.55
	TweenService:Create(f, TweenInfo.new(time), { BackgroundTransparency = 1 }):Play()
end

function CombatFx.impact(pos: Vector3, crit: boolean, style: string, mine: boolean)
	local scale = if crit then 1.5 else 1
	if style == "Anime" then
		local flash = part(Vector3.one * 2.5 * scale, CFrame.new(pos), WHITE, Enum.PartType.Ball)
		fade(flash, 0.12, { Size = Vector3.one * 5 * scale })
		local lines = if QualityController.preset.emitters >= 5 then 10 else 7
		for _ = 1, lines do
			local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			if dir.Magnitude < 0.05 then
				dir = Vector3.new(0, 1, 0)
			end
			dir = dir.Unit
			local len = (3 + math.random() * 3) * scale
			local p = part(
				Vector3.new(0.12, 0.12, len),
				CFrame.lookAt(pos + dir * len / 2, pos + dir * len),
				if crit then CRIT else WHITE
			)
			fade(p, 0.18, { CFrame = CFrame.lookAt(pos + dir * len * 1.2, pos + dir * len * 2) })
		end
		if crit and mine then
			flashScreen(WHITE, 0.08) -- the impact frame
		end
	else
		local ring = part(
			Vector3.new(0.3, 2, 2),
			CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
			if crit then CRIT else VOLT,
			Enum.PartType.Cylinder
		)
		fade(ring, 0.25, { Size = Vector3.new(0.1, 7 * scale, 7 * scale) })
		for k = 0, 1 do
			local star = part(
				Vector3.new(0.4, 0.4, 3 * scale),
				CFrame.new(pos) * CFrame.Angles(0, math.rad(45 + 90 * k), math.rad(30)),
				WHITE
			)
			fade(star, 0.15, { Size = Vector3.new(0.15, 0.15, 5 * scale) })
		end
	end
end

-- Damage numbers: rise and fade; crits are gold and 1.5x
function CombatFx.number(pos: Vector3, amount: number, crit: boolean, style: string, mine: boolean)
	local anchor = part(Vector3.one * 0.1, CFrame.new(pos), WHITE)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	local size = (if crit then F.numbers.critScale else 1) * (if mine then 1 else 0.7)
	gui.Size = UDim2.fromOffset(math.floor(80 * size), math.floor(40 * size))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = tostring(amount)
	label.TextScaled = true
	label.Font = if style == "Anime" then Enum.Font.GothamBlack else Enum.Font.Bangers
	label.TextColor3 = if crit then CRIT else WHITE
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = if style == "Anime" then Color3.fromRGB(30, 80, 160) else Color3.new(0, 0, 0)
	label.Rotation = if style == "Anime" then -8 else (math.random() - 0.5) * 12
	label.Parent = gui
	gui.Parent = anchor
	local life = F.numbers.life
	TweenService:Create(anchor, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(pos + Vector3.new(0, F.numbers.rise, 0)),
	}):Play()
	TweenService:Create(
		label,
		TweenInfo.new(life * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.6),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	):Play()
	Debris:AddItem(anchor, life + 0.1)
end

---------------------------------------------------------------------------
-- Enemies
---------------------------------------------------------------------------

-- A drone's shot: a glowing pellet you can see coming (and dodge)
function CombatFx.enemyShot(pos: Vector3, vel: Vector3)
	local speed = vel.Magnitude
	if speed < 1 then
		return
	end
	local p = part(Vector3.new(F.shot.width, F.shot.width, 2.2), CFrame.lookAt(pos, pos + vel), ENEMY)
	local life = Config.Enemies.SparkDrone.attackRange * 1.6 / speed
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(pos + vel * life, pos + vel * (life + 1)),
	}):Play()
	Debris:AddItem(p, life)
end

-- Enemy defeated: parts fly, sparks fade in 2 s (spec juice row). Respects the device debris budget.
local liveDebris = 0
function CombatFx.burst(pos: Vector3, style: string)
	local budget = QualityController.preset.debris
	local n = math.min(F.enemyDeath.parts, budget - liveDebris)
	for _ = 1, n do
		local p = part(Vector3.new(0.6, 0.6, 0.6), CFrame.new(pos), Color3.fromRGB(80, 86, 96))
		p.Material = Enum.Material.Metal
		p.Anchored = false
		p.AssemblyLinearVelocity = Vector3.new(
			math.random() - 0.5,
			math.random() * 0.8 + 0.4,
			math.random() - 0.5
		) * 50
		p.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 10
		liveDebris += 1
		task.delay(F.enemyDeath.life, function()
			liveDebris -= 1
		end)
		fade(p, F.enemyDeath.life)
	end
	local pop = part(
		Vector3.one * 3,
		CFrame.new(pos),
		if style == "Anime" then WHITE else Color3.fromRGB(255, 170, 70),
		Enum.PartType.Ball
	)
	fade(pop, 0.3, { Size = Vector3.one * 9 })
	CombatFx.impact(pos, true, style, false)
end

-- The local hero got hit: a red edge on screen
local hurtFrame: Frame? = nil
function CombatFx.hurt()
	if hurtFrame then
		local f = hurtFrame :: Frame
		f.BackgroundTransparency = 0.7
		TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end
end

function CombatFx.init()
	folder = Instance.new("Folder")
	folder.Name = "Fx"
	folder.Parent = Workspace
	local gui = Instance.new("ScreenGui")
	gui.Name = "FxOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	impactFrame = frame
	local hurt = Instance.new("Frame")
	hurt.Size = UDim2.fromScale(1, 1)
	hurt.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	hurt.BackgroundTransparency = 1
	hurt.BorderSizePixel = 0
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 1),
		NumberSequenceKeypoint.new(0.75, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	grad.Parent = hurt
	hurt.Parent = gui
	hurtFrame = hurt
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return CombatFx
