-- CombatFx: every combat effect, in two looks (nate, 2026-11-16: superhero and anime). A hero's fxStyle
-- decides how its powers look to everyone:
--   Comic  bold flat colours with a white core, shockwave rings, star bursts, sound words ("KRAK!"),
--          chunky numbers
--   Anime  thin bright lines with afterimages, crescent slashes, impact flashes with radial speed lines, an
--          impact frame on crits and supers, sharp numbers
-- One function per ability shape (bolt, chain, dash, cone, arc, nova, line, field, beam, throw, leap,
-- buff, wall, ramp), coloured by the power set, so all 40 abilities have both looks. CombatFx.cast picks
-- the right one from the ability row. Built-in parts and tweens only; nothing downloaded.
-- PLACEHOLDER ART until the VFX pass (Tasks.md).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local DebrisBudget = require(script.Parent.DebrisBudget)

local CombatFx = {}
CombatFx.reduceFlashing = false
CombatFx.showNumbers = true -- Settings: damage numbers (crit and BLOCK/BREAK words still show)

local F = Config.Fx
local A = Config.Abilities
local folder: Folder
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
local CRIT = rgb(F.critColor)
local ENEMY = rgb(F.enemyShotColor)
local WARN = rgb(F.warnColor)
local AWAKEN = rgb(F.awakenColor)
local WHITE = Color3.new(1, 1, 1)

local SET_COLOR: { [string]: Color3 } = {}
for set, c in A.setColor do
	SET_COLOR[set] = rgb(c)
end

-- A power set's colour, or the caster's effect tint (a Robux look: Config.Shop.tints, the FxTint attribute)
local TINTS: { Color3 } = {}
for i, t in Config.Shop.tints do
	TINTS[i] = rgb(t.glow or t.color)
end
function CombatFx.colorOf(set: string?, userId: number?): Color3
	if userId then
		local p = Players:GetPlayerByUserId(userId)
		local tint = p and p:GetAttribute("FxTint")
		if typeof(tint) == "number" and TINTS[tint] then
			local row = Config.Shop.tints[tint]
			if row.rainbow then
				return Color3.fromHSV((os.clock() * 0.4) % 1, 0.75, 1)
			end
			return TINTS[tint]
		end
	end
	return SET_COLOR[set or "Volt"] or rgb(F.voltColor)
end

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

local function fade(p: BasePart, time: number, props: { [string]: any }?, delay: number?)
	local goal = props or {}
	goal.Transparency = 1
	TweenService:Create(
		p,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0),
		goal
	):Play()
	Debris:AddItem(p, time + (delay or 0) + 0.05)
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

local function flatLook(dir: Vector3): Vector3
	local f = Vector3.new(dir.X, 0, dir.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- A flat expanding ring (shockwaves, novas, landings)
local function ring(center: Vector3, radius: number, color: Color3, time: number, thick: number?)
	local p = part(
		Vector3.new(thick or 0.3, 2, 2),
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
	p.Transparency = 0.15
	fade(p, time, { Size = Vector3.new(0.1, radius * 2, radius * 2) })
	return p
end
CombatFx.ring = ring

local impactFrame: Frame? = nil
local banner: TextLabel? = nil

local function flashScreen(color: Color3, time: number, strength: number?)
	if CombatFx.reduceFlashing or not impactFrame then
		return
	end
	local f = impactFrame :: Frame
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (strength or 0.45)
	TweenService:Create(f, TweenInfo.new(time), { BackgroundTransparency = 1 }):Play()
end

-- A big centred banner (Awakened, combos)
function CombatFx.banner(text: string, color: Color3, style: string)
	local b = banner
	if not b then
		return
	end
	b.Text = text
	b.TextColor3 = color
	b.Font = if style == "Anime" then Enum.Font.GothamBlack else Enum.Font.Bangers
	b.Rotation = if style == "Anime" then -4 else 3
	b.TextTransparency = 0
	b.TextStrokeTransparency = 0
	b.Size = UDim2.fromScale(0.5, 0.1)
	TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(0.7, 0.14) })
		:Play()
	TweenService:Create(
		b,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.1),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
end

-- A floating billboard (words, numbers, BLOCK)
local function floatText(
	pos: Vector3,
	text: string,
	color: Color3,
	stroke: Color3,
	font: Enum.Font,
	size: number,
	life: number,
	rise: number,
	rotation: number
)
	local anchor = part(Vector3.one * 0.1, CFrame.new(pos), WHITE)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(math.floor(80 * size), math.floor(40 * size))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = font
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = stroke
	label.Rotation = rotation
	label.Parent = gui
	gui.Parent = anchor
	TweenService:Create(anchor, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(pos + Vector3.new(0, rise, 0)),
	}):Play()
	TweenService:Create(
		label,
		TweenInfo.new(life * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.6),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	Debris:AddItem(anchor, life + 0.1)
end

-- Comic sound word
function CombatFx.word(pos: Vector3, set: string?, color: Color3, big: boolean?)
	local list = F.words[set or "Volt"] or F.words.Volt
	local text = if big then list[3] else list[math.random(1, 2)]
	floatText(
		pos + Vector3.new(math.random() * 2 - 1, 2.5, 0),
		text,
		color,
		Color3.new(0, 0, 0),
		Enum.Font.Bangers,
		if big then 2.2 else 1.4,
		0.7,
		2.5,
		(math.random() - 0.5) * 24
	)
end

-- Radial speed lines around a point (Anime)
local function speedLines(pos: Vector3, scale: number, color: Color3, count: number?)
	local n = count or (if QualityController.preset.emitters >= 5 then 10 else 7)
	for _ = 1, n do
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		if dir.Magnitude < 0.05 then
			dir = Vector3.new(0, 1, 0)
		end
		dir = dir.Unit
		local len = (3 + math.random() * 3) * scale
		local p =
			part(Vector3.new(0.12, 0.12, len), CFrame.lookAt(pos + dir * len / 2, pos + dir * len), color)
		fade(p, 0.18, { CFrame = CFrame.lookAt(pos + dir * len * 1.2, pos + dir * len * 2) })
	end
end

---------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------

function CombatFx.bolt(from: Vector3, to: Vector3, style: string, color: Color3?)
	local c = color or SET_COLOR.Volt
	if style == "Anime" then
		beam(from, to, F.bolt.width * 0.6, WHITE, F.bolt.life)
		beam(from, to, F.bolt.width * 1.4, c, F.bolt.life * 1.6) -- afterimage glow
	else
		beam(from, to, F.bolt.width * 1.6, c, F.bolt.life * 1.2)
		beam(from, to, F.bolt.width * 0.6, WHITE, F.bolt.life)
	end
end

-- Jagged lightning through a list of points (Chain Lightning)
function CombatFx.chain(points: { Vector3 }, style: string, color: Color3?)
	local c = F.chain
	local col = color or SET_COLOR.Volt
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
			beam(prev, nextP, width, if style == "Anime" then WHITE else col, c.life)
			prev = nextP
		end
	end
end

-- A streak along a dash path
function CombatFx.dash(from: Vector3, to: Vector3, style: string, color: Color3?)
	local c = color or SET_COLOR.Volt
	if style == "Anime" then
		for k = 0, 2 do
			local off = Vector3.new(0, (k - 1) * 0.8, 0)
			beam(from + off, to + off, 0.2, if k == 1 then WHITE else c, F.dash.trailLife + k * 0.05)
		end
		speedLines(to, 1, WHITE, 5)
	else
		beam(from, to, 2.2, c, F.dash.trailLife)
		beam(from, to, 0.8, WHITE, F.dash.trailLife * 0.7)
	end
end

-- A fan in front of the hero (Arc Flash, Push Wave)
function CombatFx.cone(
	origin: Vector3,
	dir: Vector3,
	range: number,
	coneDeg: number,
	style: string,
	color: Color3
)
	local f = dir.Unit
	local rays = if style == "Anime" then 7 else 5
	local half = math.rad(coneDeg / 2)
	local up = Vector3.new(0, 1, 0)
	local right = f:Cross(up)
	if right.Magnitude < 1e-3 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	for i = 1, rays do
		local a = -half + (i - 1) / math.max(1, rays - 1) * half * 2
		local d = (f * math.cos(a) + right * math.sin(a)).Unit
		if style == "Anime" then
			beam(origin, origin + d * range, 0.15, WHITE, 0.16)
		else
			beam(origin, origin + d * range, 1.2, color, 0.22)
		end
	end
	if style == "Anime" then
		speedLines(origin + f * 3, 1.2, color, 6)
	else
		local p = part(
			Vector3.new(0.3, range * 0.9, range * 0.9),
			CFrame.lookAt(origin + f * range * 0.5, origin + f * range) * CFrame.Angles(0, math.rad(90), 0),
			color,
			Enum.PartType.Cylinder
		)
		p.Transparency = 0.5
		fade(p, 0.25)
	end
end

-- A crescent slash or a punch in front (Punch Combo, Blade Slash, Rising Blade, Haymaker)
function CombatFx.arc(
	origin: Vector3,
	dir: Vector3,
	range: number,
	coneDeg: number,
	style: string,
	color: Color3,
	step: number?,
	sword: boolean?,
	rising: boolean?
)
	local f = flatLook(dir)
	local st = step or 1
	local tilt = if rising then 80 elseif st == 2 then -25 elseif st == 3 then 0 else 25
	local base = CFrame.lookAt(origin, origin + f) * CFrame.Angles(0, 0, math.rad(tilt))
	local half = math.rad(math.min(coneDeg, 160) / 2)
	local segs = F.slashSegments
	local reach = range * 0.8
	local prev: Vector3? = nil
	local width = if style == "Anime" then 0.18 else (if sword then 0.7 else 1.2)
	for i = 0, segs do
		local a = -half + i / segs * half * 2
		local local3 = Vector3.new(math.sin(a) * reach, 0, -math.cos(a) * reach)
		local p = base:PointToWorldSpace(local3)
		if prev then
			local thick = width * (0.4 + math.sin(i / segs * math.pi))
			beam(prev, p, thick, if style == "Anime" then WHITE else color, 0.16)
			if style == "Anime" then
				beam(prev, p, thick * 3, color, 0.24) -- afterimage
			end
		end
		prev = p
	end
	if not sword then
		-- a punch: a fist flash at the reach
		local hit = origin + f * reach
		local ball = part(
			Vector3.one * (if st == 3 then 3 else 2),
			CFrame.new(hit),
			if style == "Anime" then WHITE else color,
			Enum.PartType.Ball
		)
		fade(ball, 0.15, { Size = Vector3.one * (if st == 3 then 6 else 4) })
	end
end

-- A burst around a point (novas, slams, landings)
function CombatFx.nova(center: Vector3, radius: number, style: string, color: Color3, big: boolean?)
	local floor = center - Vector3.new(0, 1.2, 0)
	if style == "Anime" then
		ring(floor, radius, WHITE, 0.3, 0.15)
		ring(floor, radius * 0.8, color, 0.45, 0.4)
		local flash = part(Vector3.one * 3, CFrame.new(center), WHITE, Enum.PartType.Ball)
		fade(flash, 0.2, { Size = Vector3.one * radius * 0.8 })
		speedLines(center, radius / 6, WHITE, if big then 14 else 8)
		if big then
			flashScreen(WHITE, 0.12, 0.5)
		end
	else
		ring(floor, radius, color, 0.35, 0.6)
		ring(floor, radius * 0.6, WHITE, 0.25, 0.3)
		local dome = part(Vector3.one * 2, CFrame.new(center), color, Enum.PartType.Ball)
		dome.Transparency = 0.4
		fade(dome, 0.3, { Size = Vector3.one * radius * 1.6 })
		for k = 0, 3 do
			local star = part(
				Vector3.new(0.5, 0.5, radius * 0.6),
				CFrame.new(center) * CFrame.Angles(0, math.rad(45 * k), math.rad(20)),
				WHITE
			)
			fade(star, 0.2, { Size = Vector3.new(0.2, 0.2, radius * 1.2) })
		end
		if big then
			flashScreen(color, 0.15, 0.3)
		end
	end
end

-- A travelling line (Ground Spark, Crescent Wave, Heaven Splitter)
function CombatFx.line(
	from: Vector3,
	to: Vector3,
	width: number,
	style: string,
	color: Color3,
	ground: boolean?,
	blade: boolean?
)
	local d = to - from
	local len = d.Magnitude
	if len < 0.5 then
		return
	end
	local steps = math.clamp(math.floor(len / 6), 3, 14)
	for i = 1, steps do
		local t = i / steps
		local p = from:Lerp(to, t)
		local delay = t * 0.18
		if blade then
			-- a crescent riding the line
			local look = CFrame.lookAt(p, p + d.Unit)
			local w = part(
				Vector3.new(width, 0.3, 1.2),
				look * CFrame.Angles(0, 0, math.rad(if style == "Anime" then 0 else 15)),
				if style == "Anime" then WHITE else color
			)
			w.Transparency = 1
			TweenService:Create(
				w,
				TweenInfo.new(0.01, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay),
				{ Transparency = 0 }
			):Play()
			fade(w, 0.25, { Size = Vector3.new(width * 1.2, 0.1, 0.4) }, delay + 0.02)
		else
			local h = if ground then 0.6 else 1.5
			local spike = part(
				Vector3.new(width * 0.4, h * 3, width * 0.4),
				CFrame.new(p + Vector3.new(0, h, 0)),
				if style == "Anime" then WHITE else color
			)
			spike.Transparency = 1
			TweenService:Create(
				spike,
				TweenInfo.new(0.01, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay),
				{ Transparency = 0.1 }
			):Play()
			fade(spike, 0.25, { Size = Vector3.new(0.1, h * 5, 0.1) }, delay + 0.02)
		end
	end
	beam(
		from,
		to,
		if style == "Anime" then 0.2 else width * 0.25,
		if style == "Anime" then WHITE else color,
		0.3
	)
	if style == "Anime" then
		beam(from, to, width * 0.6, color, 0.4)
	end
end

-- A lasting area (Static Field, Blizzard Dome, Gravity Well, Singularity, Blade Storm, Molten Crater).
-- follow(): optional, returns where the field is now (Blade Storm follows the hero).
function CombatFx.field(
	center: Vector3,
	radius: number,
	duration: number,
	style: string,
	color: Color3,
	dome: boolean?,
	follow: (() -> Vector3?)?,
	swirl: boolean?
)
	local disc = part(
		Vector3.new(0.25, radius * 2, radius * 2),
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
	disc.Transparency = if style == "Anime" then 0.75 else 0.55
	disc.Material = if style == "Anime" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local shell: Part? = nil
	if dome then
		local sh = part(Vector3.one * radius * 2, CFrame.new(center), color, Enum.PartType.Ball)
		sh.Material = Enum.Material.ForceField
		sh.Transparency = 0.3
		shell = sh
	end
	local edge = part(
		Vector3.new(0.4, radius * 2 + 0.6, radius * 2 + 0.6),
		disc.CFrame,
		if style == "Anime" then WHITE else color,
		Enum.PartType.Cylinder
	)
	edge.Transparency = 0.7
	local start = os.clock()
	local nextPulse = start
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local t = now - start
		if t >= duration then
			conn:Disconnect()
			fade(disc, 0.3)
			fade(edge, 0.3)
			if shell then
				fade(shell, 0.3)
			end
			return
		end
		local at = if follow then (follow() or center) else center
		local base = CFrame.new(at - (if follow then Vector3.new(0, 2.6, 0) else Vector3.zero))
		disc.CFrame = base * CFrame.Angles(0, if swirl then t * 4 else 0, math.rad(90))
		edge.CFrame = disc.CFrame
		if shell then
			shell.CFrame = CFrame.new(at)
		end
		if now >= nextPulse then
			nextPulse = now + F.fieldPulse
			local p = disc.Position + Vector3.new(0, 0.2, 0)
			if style == "Anime" then
				ring(p, radius, WHITE, 0.35, 0.1)
			else
				ring(p, radius * 0.9, color, 0.4, 0.3)
			end
			if swirl then
				-- pull streaks toward the centre
				for _ = 1, 3 do
					local a = math.random() * math.pi * 2
					local outer = p
						+ Vector3.new(math.cos(a) * radius, math.random() * 3, math.sin(a) * radius)
					beam(
						outer,
						p + Vector3.new(0, 1, 0),
						0.25,
						if style == "Anime" then WHITE else color,
						0.3
					)
				end
			end
		end
	end)
end

-- A held beam from the hero to a target (Freeze Beam). from()/to() return positions or nil to stop.
function CombatFx.beamHold(
	from: () -> Vector3?,
	to: () -> Vector3?,
	duration: number,
	style: string,
	color: Color3
)
	local core = part(Vector3.new(0.3, 0.3, 1), CFrame.new(), WHITE)
	local glow = part(Vector3.new(1.4, 1.4, 1), CFrame.new(), color)
	glow.Transparency = if style == "Anime" then 0.6 else 0.25
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a, b = from(), to()
		if not a or not b or os.clock() - start > duration then
			conn:Disconnect()
			fade(core, 0.15)
			fade(glow, 0.2)
			return
		end
		local d = b - a
		local len = math.max(0.5, d.Magnitude)
		local cf = CFrame.lookAt(a + d / 2, b)
		local w = if style == "Anime" then 0.18 else 0.4
		local wobble = 1 + math.sin(os.clock() * 30) * 0.15
		core.Size = Vector3.new(w, w, len)
		core.CFrame = cf
		glow.Size = Vector3.new(w * 4 * wobble, w * 4 * wobble, len)
		glow.CFrame = cf
	end)
end

-- A gathering glow on the caster during a windup (Haymaker, Crush, Heaven Splitter)
function CombatFx.windup(at: () -> Vector3?, duration: number, style: string, color: Color3)
	local orb = part(Vector3.one * 0.5, CFrame.new(), color, Enum.PartType.Ball)
	orb.Transparency = 0.2
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		local p = at()
		if not p or t >= duration then
			conn:Disconnect()
			fade(orb, 0.1)
			return
		end
		local k = t / duration
		orb.Size = Vector3.one * (0.5 + k * 3.5)
		orb.CFrame = CFrame.new(p)
		if style == "Anime" and math.random() < 0.4 then
			local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
			beam(p + dir * 5, p, 0.1, WHITE, 0.1)
		end
	end)
end

-- A thrown lump on an arc (Lift and Throw). PLACEHOLDER ART: a crate block when nothing was lifted.
function CombatFx.throwArc(
	from: Vector3,
	to: Vector3,
	time: number,
	style: string,
	color: Color3,
	crate: boolean
)
	local p =
		part(Vector3.new(4, 3, 4), CFrame.new(from), if crate then Color3.fromRGB(150, 110, 60) else color)
	p.Material = if crate then Enum.Material.WoodPlanks else Enum.Material.Neon
	p.Transparency = if crate then 0 else 0.6
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / time, 0, 1)
		local pos = from:Lerp(to, t) + Vector3.new(0, 14 * 4 * t * (1 - t), 0)
		p.CFrame = CFrame.new(pos) * CFrame.Angles(t * 6, t * 4, 0)
		if t >= 1 then
			conn:Disconnect()
			fade(p, 0.2)
		elseif style == "Anime" and math.random() < 0.5 then
			beam(pos, pos - (to - from).Unit * 4, 0.15, WHITE, 0.15)
		end
	end)
end

-- A quick shine on a hero who got a buff
function CombatFx.buffPop(pos: Vector3, style: string, color: Color3)
	if style == "Anime" then
		ring(pos - Vector3.new(0, 2.5, 0), 6, WHITE, 0.3, 0.1)
		speedLines(pos, 0.8, color, 6)
	else
		ring(pos - Vector3.new(0, 2.5, 0), 6, color, 0.4, 0.4)
		local p = part(Vector3.one * 3, CFrame.new(pos), color, Enum.PartType.Ball)
		p.Transparency = 0.5
		fade(p, 0.35, { Size = Vector3.one * 8 })
	end
end

-- Awakening: a burst on the hero, and the banner plus a screen flash for the hero themself
function CombatFx.awaken(pos: Vector3, style: string, color: Color3, mine: boolean)
	CombatFx.nova(pos, 18, style, AWAKEN, mine)
	local pillar = part(
		Vector3.new(4, 60, 4),
		CFrame.new(pos + Vector3.new(0, 28, 0)),
		if style == "Anime" then WHITE else color
	)
	pillar.Transparency = 0.3
	fade(pillar, 0.6, { Size = Vector3.new(0.5, 80, 0.5) })
	if mine then
		CombatFx.banner(if style == "Anime" then "AWAKENED" else "AWAKENED!", AWAKEN, style)
	end
end

function CombatFx.combo(
	center: Vector3,
	radius: number,
	name: string,
	style: string,
	color: Color3,
	mine: boolean
)
	CombatFx.nova(center, radius, style, color, true)
	CombatFx.nova(center + Vector3.new(0, 3, 0), radius * 0.6, style, WHITE, false)
	if mine then
		CombatFx.banner(string.upper(name) .. "!", color, style)
	end
end

---------------------------------------------------------------------------
-- Impacts and numbers
---------------------------------------------------------------------------

function CombatFx.impact(pos: Vector3, crit: boolean, style: string, mine: boolean, color: Color3?)
	local c = color or SET_COLOR.Volt
	local scale = if crit then 1.5 else 1
	if style == "Anime" then
		local flash = part(Vector3.one * 2.5 * scale, CFrame.new(pos), WHITE, Enum.PartType.Ball)
		fade(flash, 0.12, { Size = Vector3.one * 5 * scale })
		speedLines(pos, scale, if crit then CRIT else WHITE)
		if crit and mine then
			flashScreen(WHITE, 0.08) -- the impact frame
		end
	else
		local r = part(
			Vector3.new(0.3, 2, 2),
			CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
			if crit then CRIT else c,
			Enum.PartType.Cylinder
		)
		fade(r, 0.25, { Size = Vector3.new(0.1, 7 * scale, 7 * scale) })
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

-- Damage numbers: rise and fade; crits are gold and 1.5x. flag 1 = blocked (shield or guard), 2 = guard broke
function CombatFx.number(
	pos: Vector3,
	amount: number,
	crit: boolean,
	style: string,
	mine: boolean,
	flag: number?
)
	if not CombatFx.showNumbers and not flag then
		return
	end
	local size = (if crit then F.numbers.critScale else 1) * (if mine then 1 else 0.7)
	local text = tostring(amount)
	local color = if crit then CRIT else WHITE
	if flag == 1 then
		text = if amount > 0 then text .. " BLOCK" else "BLOCK"
		color = Color3.fromRGB(170, 190, 210)
	elseif flag == 2 then
		text = "BREAK! " .. text
		color = Color3.fromRGB(255, 150, 60)
		size *= 1.3
	end
	floatText(
		pos,
		text,
		color,
		if style == "Anime" then Color3.fromRGB(30, 80, 160) else Color3.new(0, 0, 0),
		if style == "Anime" then Enum.Font.GothamBlack else Enum.Font.Bangers,
		size,
		F.numbers.life,
		F.numbers.rise,
		if style == "Anime" then -8 else (math.random() - 0.5) * 12
	)
end

---------------------------------------------------------------------------
-- Enemies
---------------------------------------------------------------------------

-- A robot's shot: a glowing pellet you can see coming (and dodge)
function CombatFx.enemyShot(pos: Vector3, vel: Vector3)
	local speed = vel.Magnitude
	if speed < 1 then
		return
	end
	local p = part(Vector3.new(F.shot.width, F.shot.width, 2.2), CFrame.lookAt(pos, pos + vel), ENEMY)
	local life = math.min(1.6, 80 / speed)
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(pos + vel * life, pos + vel * (life + 1)),
	}):Play()
	Debris:AddItem(p, life)
end

-- An enemy attack is coming: a red ground marker that fills over `time` (Brute slam, Sentinel sweep)
function CombatFx.warn(center: Vector3, radius: number, time: number, arc: number?, yaw: number?)
	local floor = center + Vector3.new(0, 0.15, 0)
	local outline = part(
		Vector3.new(0.12, radius * 2, radius * 2),
		CFrame.new(floor) * CFrame.Angles(0, 0, math.rad(90)),
		WARN,
		Enum.PartType.Cylinder
	)
	outline.Transparency = 0.5
	outline.Material = Enum.Material.SmoothPlastic
	local fill = part(Vector3.new(0.14, 0.5, 0.5), outline.CFrame, WARN, Enum.PartType.Cylinder)
	fill.Transparency = 0.35
	TweenService:Create(
		fill,
		TweenInfo.new(time, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(0.14, radius * 2, radius * 2) }
	):Play()
	Debris:AddItem(outline, time + 0.05)
	Debris:AddItem(fill, time + 0.05)
	if arc and arc < 360 and yaw then
		-- a front arc: two edge lines show the safe side
		local half = math.rad(arc / 2)
		for _, s in { -1, 1 } do
			local a = yaw + s * half
			local d = Vector3.new(-math.sin(a), 0, -math.cos(a))
			local edge = part(
				Vector3.new(0.4, 0.2, radius),
				CFrame.lookAt(floor + d * radius / 2, floor + d * radius),
				WARN
			)
			Debris:AddItem(edge, time + 0.05)
		end
	end
end

function CombatFx.slam(center: Vector3, radius: number)
	ring(center + Vector3.new(0, 0.3, 0), radius * 1.2, Color3.fromRGB(150, 130, 110), 0.4, 0.8)
	ring(center + Vector3.new(0, 0.3, 0), radius, WARN, 0.25, 0.3)
end

function CombatFx.blocked(pos: Vector3)
	local p = part(Vector3.one * 1.2, CFrame.new(pos), Color3.fromRGB(200, 235, 255), Enum.PartType.Ball)
	fade(p, 0.15, { Size = Vector3.one * 3 })
end

-- Enemy defeated: bolts and plates fly, sparks fade in 2 s (spec juice row; machines only, no gore).
-- Shares the device debris budget (DebrisBudget).
function CombatFx.burst(pos: Vector3, style: string, metal: Color3?)
	local n = DebrisBudget.lease(F.enemyDeath.parts, F.enemyDeath.life)
	for _ = 1, n do
		local size =
			Vector3.new(0.4 + math.random() * 0.6, 0.3 + math.random() * 0.5, 0.4 + math.random() * 0.6)
		local p = part(size, CFrame.new(pos), metal or Color3.fromRGB(80, 86, 96))
		p.Material = Enum.Material.Metal
		p.Anchored = false
		p.AssemblyLinearVelocity = Vector3.new(
			math.random() - 0.5,
			math.random() * 0.8 + 0.4,
			math.random() - 0.5
		) * 50
		p.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 10
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

---------------------------------------------------------------------------
-- One entry point: draw an ability use from its row and what is known about it
---------------------------------------------------------------------------

export type CastData = {
	o: Vector3, -- origin (chest)
	d: Vector3, -- aim direction
	e: Vector3?, -- end: bolt target, dash end, line end
	c: Vector3?, -- area centre
	r: number?, -- area radius
	t: Vector3?, -- twin line end
	step: number?, -- combo step
	aw: boolean?, -- a super while awakened
	dur: number?,
	follow: (() -> Vector3?)?,
	target: (() -> Vector3?)?, -- channel target
	caster: (() -> Vector3?)?,
	a: number?, -- the caster's user id (their effect tint)
	thrown: boolean?,
}

function CombatFx.cast(row: any, style: string, data: CastData)
	local color = CombatFx.colorOf(row.set, data.a)
	local shape = row.shape
	local o, d = data.o, data.d
	local big = row.slot == "super"
	if data.aw then
		color = color:Lerp(AWAKEN, 0.35)
	end
	if shape == "bolt" then
		if row.channel then
			CombatFx.beamHold(data.caster or function()
				return o
			end, data.target or function()
				return data.e
			end, data.dur or row.channel * (row.tick or 0.25), style, color)
		else
			CombatFx.bolt(o, data.e or (o + d * row.range), style, color)
		end
	elseif shape == "chain" then
		CombatFx.chain({ o, data.e or (o + d * row.range) }, style, color)
	elseif shape == "dash" then
		CombatFx.dash(o, data.e or (o + d * row.range), style, color)
	elseif shape == "cone" then
		CombatFx.cone(o, d, row.range, row.cone or 40, style, color)
	elseif shape == "arc" then
		local sword = row.set == "Blade"
		CombatFx.arc(o, d, row.range, row.cone or 90, style, color, data.step, sword, row.id == "RisingBlade")
		if row.channel then
			-- a flurry: more slashes over the channel
			local n = row.channel
			for i = 1, n - 1 do
				task.delay(i * (row.tick or 0.15), function()
					CombatFx.arc(o, d, row.range, row.cone or 90, style, color, (i % 3) + 1, sword)
				end)
			end
		end
	elseif shape == "nova" then
		CombatFx.nova(data.c or o, data.r or row.radius, style, color, big)
	elseif shape == "line" then
		local width = row.width or 5
		CombatFx.line(o, data.e or (o + d * row.range), width, style, color, row.ground, row.set == "Blade")
		if data.t then
			CombatFx.line(o, data.t, width, style, color, row.ground, row.set == "Blade")
		end
		if big then
			CombatFx.nova(data.e or o, width, style, color, true)
		end
	elseif shape == "field" then
		CombatFx.field(
			data.c or o,
			data.r or row.radius,
			data.dur or row.duration,
			style,
			color,
			row.id == "BlizzardDome",
			data.follow,
			row.status == "pull" or row.id == "BladeStorm"
		)
	elseif shape == "buff" then
		CombatFx.buffPop(o, style, color)
	elseif shape == "throw" then
		if data.c then
			CombatFx.throwArc(o, data.c, data.dur or 0.5, style, color, not data.thrown)
		end
	elseif shape == "wall" or shape == "ramp" then
		CombatFx.buffPop(o + d * 8, style, color)
	end
end

-- The landing or the end of a use (leap and throw landings, echoes, field and channel ends)
function CombatFx.area(
	row: any,
	style: string,
	center: Vector3,
	radius: number,
	mine: boolean,
	userId: number?
)
	local color = CombatFx.colorOf(row.set, userId)
	CombatFx.nova(center, radius, style, color, row.slot == "super" and mine)
	if style ~= "Anime" then
		CombatFx.word(center, row.set, color, row.slot == "super")
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
	local b = Instance.new("TextLabel")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(0.5, 0.3)
	b.Size = UDim2.fromScale(0.7, 0.14)
	b.BackgroundTransparency = 1
	b.TextScaled = true
	b.Text = ""
	b.TextTransparency = 1
	b.TextStrokeTransparency = 1
	b.TextStrokeColor3 = Color3.new(0, 0, 0)
	b.Parent = gui
	banner = b
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return CombatFx
