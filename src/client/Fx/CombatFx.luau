-- CombatFx: every combat effect, in two looks (nate, 2026-11-16: superhero and anime). A hero's fxStyle
-- decides how its powers look to everyone:
--   Comic  bold flat colours with a white core, shockwave rings, star bursts, sound words ("KRAK!"),
--          chunky numbers
--   Anime  thin bright lines with afterimages, crescent slashes, impact flashes with radial speed lines, an
--          impact frame on crits and supers, sharp numbers
-- One function per ability shape (bolt, chain, dash, cone, arc, nova, line, field, beam, throw, leap,
-- buff, wall, ramp), coloured by the power set, so all 40 abilities have both looks. CombatFx.cast picks
-- the right one from the ability row. Built-in parts and tweens, with FxLib's textured particles (sparks,
-- crackle, smoke, embers, shards, shockwave rings) under them per element: the optional `set` argument picks it.
-- Every power path also has its own look on top (overhaul plan step 6; the path section, Config.Fx.paths): a
-- head that flies, a hit mark, a cast flourish, dash trails, field drift, charge motes and a super moment.
-- PLACEHOLDER ART until the VFX pass (Tasks.md).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnemySim = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EnemySim"))
local FxPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FxPlan"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local DebrisBudget = require(script.Parent.DebrisBudget)
local FxLib = require(script.Parent.FxLib)

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
SET_COLOR.Weapon = rgb(F.weaponColor)

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
local slashFrame: Frame? = nil -- a thin line across the screen (Blade's Heaven Splitter cuts it)

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

-- every path's own look (overhaul plan step 6): filled in by the path section below the shapes
local sig: any = {}

---------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------

function CombatFx.bolt(from: Vector3, to: Vector3, style: string, color: Color3?, set: string?)
	local c = color or SET_COLOR.Volt
	FxLib.trail(from, to, set, c)
	FxLib.emit("glow", c, from, 1)
	if style == "Anime" then
		beam(from, to, F.bolt.width * 0.6, WHITE, F.bolt.life)
		beam(from, to, F.bolt.width * 1.4, c, F.bolt.life * 1.6) -- afterimage glow
	else
		beam(from, to, F.bolt.width * 1.6, c, F.bolt.life * 1.2)
		beam(from, to, F.bolt.width * 0.6, WHITE, F.bolt.life)
	end
	sig.head(set, from, to, style, c, 1)
end

-- Jagged lightning through a list of points (Chain Lightning)
function CombatFx.chain(points: { Vector3 }, style: string, color: Color3?, set: string?)
	local c = F.chain
	local col = color or SET_COLOR.Volt
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		FxLib.trail(a, b, set, col)
		FxLib.impact(b, set, col, 0.6, nil, style)
		sig.head(set, a, b, style, col, 0.7)
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
function CombatFx.dash(from: Vector3, to: Vector3, style: string, color: Color3?, set: string?)
	local c = color or SET_COLOR.Volt
	FxLib.trail(from, to, set, c)
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
	sig.dash(set, from, to, style, c)
end

-- A fan in front of the hero (Arc Flash, Push Wave)
function CombatFx.cone(
	origin: Vector3,
	dir: Vector3,
	range: number,
	coneDeg: number,
	style: string,
	color: Color3,
	set: string?
)
	local f = dir.Unit
	FxLib.impact(origin + f * range * 0.5, set, color, 0.8, f, style)
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
	sig.cone(set, origin, f, range, coneDeg, style, color)
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
	rising: boolean?,
	set: string?
)
	local f = flatLook(dir)
	FxLib.impact(origin + f * range * 0.7, set, color, 0.5, f, style)
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
	sig.swing(set, origin + f * reach, f, style, color, st == 3)
end

-- A burst around a point (novas, slams, landings)
function CombatFx.nova(
	center: Vector3,
	radius: number,
	style: string,
	color: Color3,
	big: boolean?,
	set: string?
)
	local floor = center - Vector3.new(0, 1.2, 0)
	FxLib.burst(center, radius, set, color, big)
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
	sig.burst(set, center, radius, style, color, big)
end

-- A travelling line (Ground Spark, Crescent Wave, Heaven Splitter)
function CombatFx.line(
	from: Vector3,
	to: Vector3,
	width: number,
	style: string,
	color: Color3,
	ground: boolean?,
	blade: boolean?,
	set: string?
)
	local d = to - from
	local len = d.Magnitude
	if len < 0.5 then
		return
	end
	FxLib.trail(from, to, set, color)
	if ground then
		FxLib.dust(to, width, nil)
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
	sig.head(set, from, to, style, color, math.clamp(width / 4, 1, 3))
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
	swirl: boolean?,
	set: string?
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
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function()
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
			sig.drift(set, p, radius, style, color)
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
	end))
end

-- A small model that follows a position each frame for `duration`, then fades. `pieces` are
-- { size, offset CFrame, colour, shape?, transparency?, material? } around the anchor.
local function rig(
	pieces: { any },
	at: () -> Vector3?,
	duration: number,
	spin: number?,
	bob: number?
): { Part }
	local parts = {}
	for _, pc in pieces do
		local p = part(pc[1], CFrame.new(), pc[3], pc[4])
		p.Transparency = pc[5] or 0
		if pc[6] then
			p.Material = pc[6]
		end
		table.insert(parts, p)
	end
	local start = os.clock()
	local last = at() or Vector3.zero
	local conn
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function()
		local t = os.clock() - start
		if t >= duration then
			conn:Disconnect()
			for _, p in parts do
				fade(p, 0.3)
			end
			return
		end
		last = at() or last
		local base = CFrame.new(last + Vector3.new(0, if bob then math.sin(t * 3) * bob else 0, 0))
			* CFrame.Angles(0, if spin then t * spin else 0, 0)
		for i, p in parts do
			p.CFrame = base * pieces[i][2]
		end
	end))
	return parts
end

-- Summons (Turret Drop, Fix-It Drone, Shadow Clones, Ward Totem, the Ascended Guardian, Shock Mines, Holo
-- Decoy and the water and spirit copies): simple part-built stand-ins. PLACEHOLDER ART until the VFX pass.
function CombatFx.summon(
	kind: string,
	at: () -> Vector3?,
	duration: number,
	style: string,
	color: Color3,
	radius: number?
)
	local dark = Color3.fromRGB(45, 48, 60)
	local glass = if style == "Anime" then 0.55 else 0.4
	local pieces: { any }
	local spin, bob = nil, nil
	if kind == "turret" then
		pieces = {
			{
				Vector3.new(1, 4, 4),
				CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
				dark,
				Enum.PartType.Cylinder,
				0,
				Enum.Material.Metal,
			},
			{ Vector3.new(2.4, 1.6, 2.4), CFrame.new(0, -1.2, 0), dark, nil, 0, Enum.Material.Metal },
			{ Vector3.new(0.5, 0.5, 2.6), CFrame.new(0, -1, -1.8), color },
		}
		spin = 1.5
	elseif kind == "drone" then
		pieces = {
			{
				Vector3.one * 1.6,
				CFrame.new(3, 4, 0),
				Color3.new(1, 1, 1),
				Enum.PartType.Ball,
				0,
				Enum.Material.SmoothPlastic,
			},
			{
				Vector3.new(0.2, 3.2, 3.2),
				CFrame.new(3, 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
				color,
				Enum.PartType.Cylinder,
				0.3,
			},
		}
		spin, bob = 2, 0.6
	elseif kind == "clones" then
		pieces = {}
		for _, x in { -4, 4 } do
			table.insert(pieces, { Vector3.new(2, 2.6, 1), CFrame.new(x, -0.6, 2), color, nil, glass })
			table.insert(
				pieces,
				{ Vector3.one * 1.3, CFrame.new(x, 1.4, 2), color, Enum.PartType.Ball, glass }
			)
			table.insert(pieces, { Vector3.new(0.8, 2.2, 0.8), CFrame.new(x, -3, 2), color, nil, glass })
		end
	elseif kind == "totem" then
		pieces = {
			{
				Vector3.new(1.2, 7, 1.2),
				CFrame.new(0, 1, 0),
				Color3.fromRGB(120, 90, 60),
				nil,
				0,
				Enum.Material.Wood,
			},
			{ Vector3.one * 2, CFrame.new(0, 5.2, 0), color, Enum.PartType.Ball, 0.1 },
		}
		bob = 0.2
	elseif kind == "guardian" then
		pieces = {
			{ Vector3.new(6, 7, 3), CFrame.new(0, 7, 4), color, nil, glass },
			{ Vector3.one * 3.4, CFrame.new(0, 12.2, 4), color, Enum.PartType.Ball, glass },
			{ Vector3.new(2, 6, 2), CFrame.new(-4.5, 7, 4), color, nil, glass },
			{ Vector3.new(2, 6, 2), CFrame.new(4.5, 7, 4), color, nil, glass },
		}
		bob = 0.5
	elseif kind == "mines" then
		pieces = {}
		local r = (radius or 12) * 0.6
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			table.insert(pieces, {
				Vector3.new(0.4, 1.4, 1.4),
				CFrame.new(math.cos(a) * r, -0.6, math.sin(a) * r) * CFrame.Angles(0, 0, math.rad(90)),
				color,
				Enum.PartType.Cylinder,
			})
		end
	else -- holo: a see-through copy of a hero
		pieces = {
			{ Vector3.new(2, 2.6, 1), CFrame.new(0, 0, 0), color, nil, 0.5 },
			{ Vector3.one * 1.3, CFrame.new(0, 2, 0), color, Enum.PartType.Ball, 0.5 },
			{ Vector3.new(0.8, 2.4, 0.8), CFrame.new(-0.5, -2.5, 0), color, nil, 0.5 },
			{ Vector3.new(0.8, 2.4, 0.8), CFrame.new(0.5, -2.5, 0), color, nil, 0.5 },
		}
	end
	rig(pieces, at, duration, spin, bob)
	local p0 = at()
	if p0 then
		CombatFx.buffPop(p0, style, color)
	end
end

-- Travel powers: what the hero rides on, under their feet while the ride lasts (Rock Ride's slab, Wave
-- Surf's wave, the Hoverboard, Psi Platform's debris, Spirit Ride's beast, Light Rail's rail, Flame Jets'
-- jets). PLACEHOLDER ART until the VFX pass.
function CombatFx.ride(set: string, at: () -> Vector3?, duration: number, style: string, color: Color3)
	local feet = CFrame.new(0, -3.4, 0)
	local pieces: { any }
	if set == "Earth" then
		pieces =
			{ { Vector3.new(6, 1.2, 8), feet, Color3.fromRGB(120, 105, 90), nil, 0, Enum.Material.Slate } }
	elseif set == "Tide" then
		pieces = {
			{ Vector3.new(7, 1.6, 9), feet, color, nil, 0.35, Enum.Material.Glass },
			{ Vector3.new(7, 3, 1.5), feet * CFrame.new(0, 1, 4.5), Color3.new(1, 1, 1), nil, 0.4 },
		}
	elseif set == "Gadgeteer" then
		pieces = {
			{ Vector3.new(2.6, 0.4, 7), feet, Color3.fromRGB(40, 44, 55), nil, 0, Enum.Material.Metal },
			{ Vector3.new(2.8, 0.15, 7.2), feet * CFrame.new(0, -0.3, 0), color },
		}
	elseif set == "Mind" then
		pieces = {
			{ Vector3.new(6, 1.4, 6), feet, Color3.fromRGB(110, 110, 115), nil, 0, Enum.Material.Concrete },
			{ Vector3.new(6.4, 0.2, 6.4), feet * CFrame.new(0, -0.8, 0), color, nil, 0.3 },
		}
	elseif set == "Spirit" then
		pieces = {
			{ Vector3.new(4, 3.5, 9), feet * CFrame.new(0, -1.2, 0), color, nil, 0.45 },
			{ Vector3.one * 3, feet * CFrame.new(0, 0, -5.5), color, Enum.PartType.Ball, 0.45 },
		}
	elseif set == "Fire" then
		pieces = {
			{ Vector3.new(1, 3, 1), feet * CFrame.new(-0.6, -1, 0), color, nil, 0.2 },
			{ Vector3.new(1, 3, 1), feet * CFrame.new(0.6, -1, 0), color, nil, 0.2 },
		}
	else -- Light Rail and anything else: a bright rail under the feet
		pieces = { { Vector3.new(1, 0.4, 14), feet * CFrame.new(0, 0, -3), color, nil, 0.1 } }
	end
	-- turn the rig with the hero: rebuild the frame from the hero's heading each frame
	local start = os.clock()
	local parts = {}
	for _, pc in pieces do
		local p = part(pc[1], CFrame.new(), pc[3], pc[4])
		p.Transparency = pc[5] or 0
		if pc[6] then
			p.Material = pc[6]
		end
		table.insert(parts, p)
	end
	local last: Vector3? = at()
	local heading = CFrame.new()
	local conn
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function()
		local t = os.clock() - start
		local now = at()
		if t >= duration or not now then
			conn:Disconnect()
			for _, p in parts do
				fade(p, 0.3)
			end
			return
		end
		if last and (now - last).Magnitude > 0.05 then
			local d = now - last
			local flat = Vector3.new(d.X, 0, d.Z)
			if flat.Magnitude > 0.05 then
				heading = CFrame.lookAt(Vector3.zero, flat.Unit)
			end
		end
		last = now
		local base = CFrame.new(now) * heading
		for i, p in parts do
			p.CFrame = base * pieces[i][2]
		end
		if set == "Fire" or set == "Light" then
			if math.random() < 0.5 then
				local spark =
					part(Vector3.one * 0.6, CFrame.new(now - Vector3.new(0, 4, 0)), color, Enum.PartType.Ball)
				fade(spark, 0.3, { Size = Vector3.one * 0.1, Position = now - Vector3.new(0, 7, 0) })
			end
		end
	end))
	if last then
		speedLines(last, 1, if style == "Anime" then WHITE else color)
	end
end

-- Launches (Sky Step, Recoil Jump, Stone Pillar, Giant Stride): a burst where the hero left the ground
function CombatFx.launch(row: any, from: Vector3, style: string, color: Color3)
	ring(
		from - Vector3.new(0, 2.5, 0),
		(row.radius or 6),
		if style == "Anime" then WHITE else color,
		0.35,
		0.3
	)
	speedLines(from, 0.9, color, 6)
	if row.set == "Earth" then
		-- Stone Pillar: a column shoots up under the hero, then sinks
		local h = row.up or 40
		local base = from - Vector3.new(0, 3, 0)
		local p = part(Vector3.new(5, 1, 5), CFrame.new(base), Color3.fromRGB(120, 105, 90))
		p.Material = Enum.Material.Slate
		TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Size = Vector3.new(5, h * 0.6, 5),
			CFrame = CFrame.new(base + Vector3.new(0, h * 0.3, 0)),
		}):Play()
		fade(p, 0.6, nil, 1.2)
	elseif row.set == "Martial" then
		-- Sky Step: a ring of light underfoot in the air
		ring(from - Vector3.new(0, 3, 0), 4, WHITE, 0.3, 0.15)
	end
end

-- A held beam from the hero to a target (Freeze Beam). from()/to() return positions or nil to stop.
function CombatFx.beamHold(
	from: () -> Vector3?,
	to: () -> Vector3?,
	duration: number,
	style: string,
	color: Color3,
	set: string?
)
	local core = part(Vector3.new(0.3, 0.3, 1), CFrame.new(), WHITE)
	local nextFx = 0
	local glow = part(Vector3.new(1.4, 1.4, 1), CFrame.new(), color)
	glow.Transparency = if style == "Anime" then 0.6 else 0.25
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function()
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
		local now = os.clock()
		if now >= nextFx then
			nextFx = now + 0.15
			FxLib.trail(a, b, set, color)
			FxLib.impact(b, set, color, 0.5, -d, style)
		end
	end))
end

-- A gathering glow on the caster during a windup (Haymaker, Crush, Heaven Splitter)
function CombatFx.windup(at: () -> Vector3?, duration: number, style: string, color: Color3, set: string?)
	local orb = part(Vector3.one * 0.5, CFrame.new(), color, Enum.PartType.Ball)
	local p0 = at()
	if p0 then
		FxLib.gather(p0, set, color)
	end
	orb.Transparency = 0.2
	local motes = sig.motes(set, style, color)
	local nextCharge = 0
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function()
		local t = os.clock() - start
		local p = at()
		if not p or t >= duration then
			conn:Disconnect()
			fade(orb, 0.1)
			sig.dropMotes(motes)
			return
		end
		local k = t / duration
		orb.Size = Vector3.one * (0.5 + k * 3.5)
		orb.CFrame = CFrame.new(p)
		sig.placeMotes(motes, set, p, k, t)
		if t >= nextCharge then
			nextCharge = t + 0.25
			FxLib.charge(p, set, color)
		end
		if style == "Anime" and math.random() < 0.4 then
			local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
			beam(p + dir * 5, p, 0.1, WHITE, 0.1)
		end
	end))
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
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function()
		local t = math.clamp((os.clock() - start) / time, 0, 1)
		local pos = from:Lerp(to, t) + Vector3.new(0, 14 * 4 * t * (1 - t), 0)
		p.CFrame = CFrame.new(pos) * CFrame.Angles(t * 6, t * 4, 0)
		if t >= 1 then
			conn:Disconnect()
			fade(p, 0.2)
		elseif style == "Anime" and math.random() < 0.5 then
			beam(pos, pos - (to - from).Unit * 4, 0.15, WHITE, 0.15)
		end
	end))
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
-- Every path's own look (overhaul plan step 6; Config.Fx.paths, rules in Shared.FxPlan). The shapes above
-- call in here with their set: a head flies on bolts, chain hops and lines, a mark lands on hits, a flourish
-- plays on the caster, dashes leave the path's trail, fields drift its pieces, windups and held skills gather
-- its charge motes, and each super has its own big moment. Volt (the slice nate OKed) and weapon moves have
-- nothing here that draws, so they keep their look. Comic: chunky pieces in the path colour, solid and bold;
-- Anime: thinner, white-cored pieces with a colour afterimage, speed lines and quicker motion. Every piece
-- comes out of FxLib's part budget for the device preset (phones draw fewer). PLACEHOLDER ART: part-built.
---------------------------------------------------------------------------

local P = F.paths
local LIB = F.lib
local ACCENT: { [string]: Color3 } = {}
local TINT: { [string]: Color3 } = {}
for set, row in P do
	ACCENT[set] = rgb(row.accent)
	TINT[set] = rgb(row.super.tint)
end
local UP = Vector3.new(0, 1, 0)

local function anime(style: string): boolean
	return style == "Anime"
end

local function randomUnit(): Vector3
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return if v.Magnitude < 0.05 then UP else v.Unit
end

local function facing(pos: Vector3): CFrame
	local cam = Workspace.CurrentCamera
	return if cam then CFrame.lookAt(pos, cam.CFrame.Position) else CFrame.new(pos)
end

-- a ring facing `normal` (flat on the ground when normal is up) that grows to radius and fades
local function disc(
	pos: Vector3,
	normal: Vector3,
	radius: number,
	color: Color3,
	time: number,
	thick: number?
)
	local cf = if math.abs(normal.Unit.Y) > 0.98
		then CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		else CFrame.lookAt(pos, pos + normal) * CFrame.Angles(0, math.rad(90), 0)
	local p = part(Vector3.new(thick or 0.2, 1, 1), cf, color, Enum.PartType.Cylinder)
	p.Transparency = 0.1
	fade(p, time, { Size = Vector3.new(0.05, radius * 2, radius * 2) })
	return p
end

-- one part-built piece of a path (Config.Fx.paths piece names; FxPlan.PIECES), size s, placed by the caller
local PIECE = {}
PIECE.ball = function(s: number, c: Color3): Part
	return part(Vector3.one * s, CFrame.new(), c, Enum.PartType.Ball)
end
PIECE.ember = function(s: number, c: Color3): Part
	return part(Vector3.one * s * 0.6, CFrame.new(), c, Enum.PartType.Ball)
end
PIECE.flake = function(s: number, c: Color3): Part -- Frost: a flat snowflake chip that tumbles as it falls
	local p = part(Vector3.new(s * 0.6, s * 0.06, s * 0.6), CFrame.new(), c:Lerp(WHITE, 0.5))
	p.Transparency = 0.1
	return p
end
PIECE.flame = function(s: number, c: Color3): Part
	local p = part(Vector3.one * s, CFrame.new(), c, Enum.PartType.Ball)
	p.Transparency = 0.25
	return p
end
PIECE.drop = function(s: number, c: Color3): Part
	local p = part(Vector3.one * s * 0.8, CFrame.new(), c, Enum.PartType.Ball)
	p.Material = Enum.Material.Glass
	p.Transparency = 0.2
	return p
end
PIECE.spike = function(s: number, c: Color3): Part
	return part(Vector3.new(s * 0.3, s * 0.3, s * 2.2), CFrame.new(), c)
end
PIECE.shard = function(s: number, c: Color3): Part
	local p = part(Vector3.new(s * 0.45, s * 0.45, s * 1.2), CFrame.new(), c)
	p.Material = Enum.Material.Glass
	p.Transparency = 0.15
	return p
end
PIECE.rock = function(s: number, c: Color3): Part
	local p = part(Vector3.new(s, s * 0.8, s * 0.9), CFrame.new(), c)
	p.Material = Enum.Material.Slate
	return p
end
PIECE.kunai = function(s: number, c: Color3): Part
	local p = part(Vector3.new(s * 0.22, s * 0.22, s * 1.6), CFrame.new(), c)
	p.Material = Enum.Material.Metal
	return p
end
PIECE.plate = function(s: number, c: Color3): Part
	return part(Vector3.new(s, s * 0.15, s), CFrame.new(), c)
end
PIECE.tri = function(s: number, c: Color3): Part
	return part(Vector3.new(s * 0.12, s * 0.7, s * 0.7), CFrame.new(), c)
end
PIECE.ring = function(s: number, c: Color3): Part
	local p = part(Vector3.new(s * 0.12, s, s), CFrame.new(), c, Enum.PartType.Cylinder)
	p.Transparency = 0.3
	return p
end

local function piece(kind: string, s: number, c: Color3): Part?
	local make = PIECE[kind]
	return if make then make(s, c) else nil
end
CombatFx.piece = piece

-- n pieces fly out from pos (biased along dir when given, up adds lift), shrink and fade
local function bits(
	pos: Vector3,
	kind: string,
	n: number,
	size: number,
	speed: number,
	color: Color3,
	style: string,
	up: number?,
	dir: Vector3?,
	life: number?
)
	local count = FxLib.pieces(n)
	local an = anime(style)
	local sz = size * (if an then 0.8 else LIB.comicSize)
	local sp = speed * (if an then LIB.animeSpeed else 1)
	local time = life or 0.35
	for i = 1, count do
		local d = randomUnit()
		if dir and dir.Magnitude > 1e-3 then
			d = (d + dir.Unit * 1.3).Unit
		end
		d = (d + Vector3.new(0, up or 0, 0)).Unit
		local p = piece(kind, sz * (0.7 + math.random() * 0.6), if an and i % 2 == 0 then WHITE else color)
		if p then
			p.CFrame = CFrame.lookAt(pos, pos + d) * CFrame.Angles(0, 0, math.random() * 6)
			local to = pos + d * sp * time - Vector3.new(0, (up or 0) > 0 and 2 or 0, 0)
			fade(p, time, {
				CFrame = CFrame.lookAt(to, to + d) * CFrame.Angles(math.random() * 4, 0, math.random() * 4),
				Size = p.Size * 0.4,
			})
		end
	end
end

-- a piece flying from -> to in `time`, turning `roll` radians about its flight
local ACROSS = CFrame.Angles(0, math.rad(90), 0) -- a ring (cylinder) standing across its flight
local function fly(
	p: BasePart,
	from: Vector3,
	to: Vector3,
	time: number,
	roll: number?,
	delay: number?,
	twist: CFrame?
)
	local d = to - from
	local look = if d.Magnitude > 1e-3 then d.Unit else UP
	local tw = twist or CFrame.identity
	p.CFrame = CFrame.lookAt(from, from + look) * tw
	TweenService:Create(
		p,
		TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay or 0),
		{ CFrame = CFrame.lookAt(to, to + look) * CFrame.Angles(0, 0, roll or 0) * tw }
	):Play()
	fade(p, 0.1, nil, time + (delay or 0))
end

local function flightTime(from: Vector3, to: Vector3, speed: number): number
	return math.clamp((to - from).Magnitude / speed, 0.06, 0.35)
end

-- two crossed thin bars: a glint, a star, a cross cut
local function crossBars(at: CFrame, len: number, width: number, color: Color3, time: number, angle: number?)
	for k = 0, 1 do
		local a = math.rad((angle or 45) + 90 * k)
		local b = part(
			Vector3.new(width, width, len),
			at * CFrame.Angles(0, 0, a) * CFrame.Angles(math.rad(90), 0, 0),
			color
		)
		fade(b, time, { Size = Vector3.new(width * 0.2, width * 0.2, len * 1.4) })
	end
end

---------------------------------------------------------------------------
-- Heads: what flies (bolts, chain hops, lines)
---------------------------------------------------------------------------

local HEAD = {}
HEAD.none = function() end
HEAD.spike = function(from, to, style, color, accent, s) -- Frost: a spinning ice spike
	local t = flightTime(from, to, 240)
	local p = PIECE.shard(1.6 * s, if anime(style) then accent else color)
	p.Size = Vector3.new(0.6, 0.6, 2.8) * s
	fly(p, from, to, t, 9)
	if anime(style) then
		local glow = PIECE.spike(1.2 * s, color)
		glow.Transparency = 0.5
		fly(glow, from, to, t, -9, 0.03)
	end
end
HEAD.fireball = function(from, to, style, color, accent, s) -- Fire: a fireball with a hot core and embers
	local t = flightTime(from, to, 200)
	local outer = PIECE.flame(2 * s * (if anime(style) then 0.8 else 1.1), color)
	local core = PIECE.ball(1.1 * s, if anime(style) then WHITE else accent)
	fly(outer, from, to, t)
	fly(core, from, to, t)
	for k = 1, 3 do
		local e = PIECE.ember(0.9 * s, if k == 2 then accent else color)
		fly(e, from, to, t, nil, 0.03 * k)
	end
end
HEAD.rock = function(from, to, style, color, accent, s) -- Earth: a tumbling stone
	local t = flightTime(from, to, 180)
	local r = PIECE.rock(1.4 * s, color)
	fly(r, from, to, t, 8)
	if anime(style) then
		beam(from, to, 0.12, accent, t + 0.1)
	end
end
HEAD.boulder = function(from, to, _style, color, accent, s) -- Colossus: a big boulder with a dust tail
	local t = flightTime(from, to, 150)
	local r = PIECE.rock(3 * s, color)
	fly(r, from, to, t, 6)
	local d = (to - from)
	for k = 1, 3 do
		local puff = PIECE.ball(1.6 * s, accent)
		puff.Material = Enum.Material.SmoothPlastic
		puff.Transparency = 0.4
		fly(puff, from, from + d * (0.3 * k), t * 0.3 * k, nil, 0.02)
	end
end
HEAD.glob = function(from, to, style, color, accent, s) -- Tide: a water glob in a foam ring
	local t = flightTime(from, to, 200)
	local g = PIECE.drop(2 * s, color)
	fly(g, from, to, t)
	local foam = PIECE.ring(2.4 * s, if anime(style) then WHITE else accent)
	fly(foam, from, to, t, 0, nil, ACROSS)
end
HEAD.tracer = function(from, to, style, color, accent, s) -- Gunslinger: a fast bright tracer
	local t = flightTime(from, to, 420)
	local p = part(Vector3.new(0.18, 0.18, 4) * s, CFrame.new(), if anime(style) then WHITE else accent)
	fly(p, from, to, t)
	local glow = part(Vector3.new(0.5, 0.5, 2.5) * s, CFrame.new(), color)
	glow.Transparency = 0.4
	fly(glow, from, to, t, nil, 0.015)
end
HEAD.plasma = function(from, to, style, color, accent, s) -- Gadgeteer: a plasma pellet in a spinning ring
	local t = flightTime(from, to, 260)
	local b = PIECE.ball(1.2 * s, if anime(style) then WHITE else accent)
	fly(b, from, to, t)
	local ringP = PIECE.ring(2.2 * s, color)
	fly(ringP, from, to, t, 0, nil, ACROSS * CFrame.Angles(0.5, 0, 0))
end
HEAD.kunai = function(from, to, style, color, accent, s) -- Shadow: a dark blade with a coloured edge
	local t = flightTime(from, to, 300)
	local k = PIECE.kunai(2 * s, accent)
	fly(k, from, to, t, 14)
	local edge = part(Vector3.new(0.1, 0.1, 2.6) * s, CFrame.new(), if anime(style) then WHITE else color)
	fly(edge, from, to, t, 14)
end
HEAD.kiorb = function(from, to, style, color, accent, s) -- Martial: a ki sphere with a white core and a halo
	local t = flightTime(from, to, 170)
	local outer = PIECE.flame(2.4 * s, color)
	outer.Material = Enum.Material.ForceField
	outer.Transparency = 0
	local core = PIECE.ball(1.3 * s, accent)
	fly(outer, from, to, t)
	fly(core, from, to, t)
	local halo = PIECE.ring(3.2 * s, if anime(style) then WHITE else color)
	fly(halo, from, to, t, 0, nil, ACROSS)
end
HEAD.lens = function(from, to, style, color, accent, s) -- Pulse: a warped sphere with a void core
	local t = flightTime(from, to, 190)
	local shell = PIECE.ball(2.6 * s, color)
	shell.Material = Enum.Material.ForceField
	local void = PIECE.ball(1 * s, accent)
	void.Material = Enum.Material.SmoothPlastic
	fly(shell, from, to, t)
	fly(void, from, to, t)
	if anime(style) then
		local r = PIECE.ring(3 * s, WHITE)
		fly(r, from, to, t, 0, nil, ACROSS)
	end
end
HEAD.psiring = function(from, to, style, color, accent, s) -- Mind: a spinning ring, face-on to its flight
	local t = flightTime(from, to, 230)
	local r = PIECE.ring(2.6 * s, color)
	r.Transparency = 0.1
	fly(r, from, to, t, 0, nil, ACROSS)
	local inner = PIECE.tri(1.4 * s, if anime(style) then WHITE else accent)
	fly(inner, from, to, t, 10)
end
HEAD.wisp = function(from, to, _style, color, accent, s) -- Spirit: a spirit flame with a trail of wisps
	local t = flightTime(from, to, 190)
	local head = PIECE.flame(1.8 * s, color)
	fly(head, from, to, t)
	for k = 1, 4 do
		local w = PIECE.ember(1.6 * s * (1 - k * 0.15), if k % 2 == 0 then accent else color)
		w.Transparency = 0.2 + k * 0.12
		fly(w, from, to, t, nil, 0.025 * k)
	end
end
HEAD.lance = function(from, to, style, color, accent, s) -- Light: a long spear of light with a bright tip
	local t = flightTime(from, to, 360)
	local spear = part(Vector3.new(0.3, 0.3, 6) * s, CFrame.new(), if anime(style) then WHITE else accent)
	fly(spear, from, to, t)
	local glow = part(Vector3.new(0.9, 0.9, 5) * s, CFrame.new(), color)
	glow.Transparency = 0.5
	fly(glow, from, to, t)
end

---------------------------------------------------------------------------
-- Marks: what a hit leaves on top of the element's particles (scale: 1.5 on a crit, less for others' hits)
---------------------------------------------------------------------------

local MARK = {}
MARK.none = function() end
MARK.crystals = function(pos, style, color, accent, s) -- Frost: ice spikes jut out, then shatter
	local n = FxLib.pieces(5, s)
	for _ = 1, n do
		local d = randomUnit()
		local sp = PIECE.shard(1.4 * s, if anime(style) then accent else color)
		sp.CFrame = CFrame.lookAt(pos, pos + d)
		sp.Size = Vector3.new(0.5, 0.5, 0.4) * s
		TweenService:Create(sp, TweenInfo.new(0.08), {
			Size = Vector3.new(0.6, 0.6, 3.2) * s,
			CFrame = CFrame.lookAt(pos + d * 1.6 * s, pos + d * 3 * s),
		}):Play()
		fade(sp, 0.2, nil, 0.22)
	end
	task.delay(0.22, function()
		bits(pos, "shard", 5, 0.6 * s, 22, color, style, 0.4)
	end)
end
MARK.puff = function(pos, style, color, accent, s) -- Fire: a fireball puff with a smoky rim
	local core = PIECE.ball(1.5 * s, if anime(style) then WHITE else accent)
	fade(core, 0.18, { Size = Vector3.one * 4.5 * s })
	local outer = PIECE.flame(2 * s, color)
	fade(outer, 0.3, { Size = Vector3.one * 6.5 * s })
	if not anime(style) then
		disc(pos, UP, 4 * s, Color3.fromRGB(70, 60, 55), 0.4, 0.5)
	end
end
MARK.rubble = function(pos, style, color, accent, s) -- Earth: stones pop up, a crack ring
	bits(pos, "rock", 5, 0.8 * s, 16, color, style, 1.2)
	disc(pos, UP, 3 * s, if anime(style) then WHITE else accent, 0.3, 0.3)
end
MARK.quake = function(pos, style, color, accent, s) -- Colossus: big stones and a dust ring
	bits(pos, "rock", 6, 1.4 * s, 18, color, style, 1.4, nil, 0.45)
	FxLib.dust(pos - Vector3.new(0, 1.5, 0), 4 * s, accent)
	disc(pos - Vector3.new(0, 1, 0), UP, 6 * s, color, 0.4, 0.6)
end
MARK.crown = function(pos, style, color, accent, s) -- Tide: a crown of droplets and a ripple
	local n = FxLib.pieces(8, s)
	for i = 1, n do
		local a = i / n * math.pi * 2
		local d = Vector3.new(math.cos(a), 1.4, math.sin(a)).Unit
		local drop = PIECE.drop(0.8 * s, if i % 2 == 0 then accent else color)
		drop.CFrame = CFrame.new(pos)
		fade(drop, 0.35, { CFrame = CFrame.new(pos + d * 5 * s), Size = Vector3.one * 0.2 })
	end
	disc(pos, UP, 4 * s, if anime(style) then WHITE else accent, 0.35, 0.15)
end
MARK.cross = function(pos, style, color, accent, s) -- Blade: an X cut that slides apart
	local cf = facing(pos)
	local an = anime(style)
	crossBars(cf, 6 * s, if an then 0.14 else 0.5, if an then WHITE else color, 0.2)
	if an then
		crossBars(cf, 7 * s, 0.5, color, 0.28)
	else
		crossBars(cf, 3 * s, 0.2, accent, 0.15)
	end
end
MARK.ricochet = function(pos, style, color, accent, s) -- Gunslinger: sparks glance off, a little star
	for _ = 1, FxLib.pieces(3, s) do
		local d = randomUnit()
		beam(pos, pos + d * 4 * s, 0.12, if anime(style) then WHITE else accent, 0.12)
	end
	crossBars(facing(pos), 2.2 * s, 0.25, color, 0.15, 0)
end
MARK.hexes = function(pos, style, color, accent, s) -- Gadgeteer: hex plates scatter, a scan ring
	bits(pos, "plate", 6, 0.7 * s, 18, color, style, 0.3)
	disc(
		pos,
		(Workspace.CurrentCamera and (Workspace.CurrentCamera.CFrame.Position - pos)) or UP,
		3 * s,
		if anime(style) then WHITE else accent,
		0.25,
		0.12
	)
end
MARK.ink = function(pos, style, color, accent, s) -- Shadow: ink blots splatter, a coloured cut
	local n = FxLib.pieces(4, s)
	for _ = 1, n do
		local d = randomUnit()
		local blot = part(Vector3.new(1.4, 0.2, 1.1) * s, CFrame.lookAt(pos, pos + d), accent)
		blot.Material = Enum.Material.SmoothPlastic
		fade(blot, 0.45, {
			CFrame = CFrame.lookAt(pos + d * 3 * s, pos + d * 6 * s),
			Size = Vector3.new(2.2, 0.1, 1.6) * s,
		})
	end
	local cut = facing(pos) * CFrame.Angles(0, 0, math.rad(30))
	local line = part(
		Vector3.new(5 * s, if anime(style) then 0.1 else 0.3, 0.1),
		cut,
		if anime(style) then WHITE else color
	)
	fade(line, 0.2, { Size = Vector3.new(7 * s, 0.05, 0.05) })
end
MARK.pow = function(pos, style, color, accent, s) -- Titan: a comic star burst, or a shock cone with lines
	if anime(style) then
		disc(
			pos,
			(Workspace.CurrentCamera and (Workspace.CurrentCamera.CFrame.Position - pos)) or UP,
			4 * s,
			WHITE,
			0.2,
			0.1
		)
		speedLines(pos, 1.2 * s, color, 8)
	else
		local cf = facing(pos)
		for k = 0, 7 do
			local spike = part(
				Vector3.new(0.9 * s, 0.25, 0.25),
				cf * CFrame.Angles(0, 0, math.rad(45 * k)) * CFrame.new(1.4 * s, 0, 0),
				if k % 2 == 0 then accent else color
			)
			fade(spike, 0.22, { Size = Vector3.new(2.6 * s, 0.1, 0.1) })
		end
		local mid = PIECE.ball(1.5 * s, accent)
		mid.CFrame = CFrame.new(pos)
		fade(mid, 0.15, { Size = Vector3.one * 3 * s })
	end
end
MARK.kiring = function(pos, _style, color, accent, s) -- Martial: a ki ring bursts flat, glints
	local cam = Workspace.CurrentCamera
	local n = if cam then cam.CFrame.Position - pos else UP
	disc(pos, n, 4 * s, accent, 0.22, 0.2)
	disc(pos, n, 2.6 * s, color, 0.3, 0.4)
	FxLib.emit("star", accent, pos, 2)
end
MARK.clang = function(pos, style, color, accent, s) -- Juggernaut: a white clang flash and hot metal bits
	local flash = PIECE.ball(1.6 * s, WHITE)
	flash.CFrame = CFrame.new(pos)
	fade(flash, 0.1, { Size = Vector3.one * 4 * s })
	bits(pos, "plate", 4, 0.6 * s, 20, if anime(style) then accent else color, style, 0.8)
	for _ = 1, 3 do
		beam(pos, pos + randomUnit() * 3.5 * s, 0.15, accent, 0.12)
	end
end
MARK.warp = function(pos, style, color, accent, s) -- Pulse: a ring pulls in, then pops
	local cam = Workspace.CurrentCamera
	local n = if cam then cam.CFrame.Position - pos else UP
	local cf = CFrame.lookAt(pos, pos + n) * CFrame.Angles(0, math.rad(90), 0)
	local r = part(
		Vector3.new(0.2, 7 * s, 7 * s),
		cf,
		if anime(style) then WHITE else color,
		Enum.PartType.Cylinder
	)
	r.Transparency = 0.2
	TweenService:Create(
		r,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(0.2, 0.4, 0.4) }
	):Play()
	Debris:AddItem(r, 0.17)
	task.delay(0.16, function()
		local void = PIECE.ball(0.8 * s, accent)
		void.CFrame = CFrame.new(pos)
		void.Material = Enum.Material.SmoothPlastic
		fade(void, 0.2, { Size = Vector3.one * 3.5 * s })
		disc(pos, n, 4 * s, color, 0.25, 0.15)
	end)
end
MARK.sigil = function(pos, style, color, accent, s) -- Mind: a sigil opens on the target
	local cf = facing(pos)
	local an = anime(style)
	local r = 2.2 * s
	local corners = {}
	for k = 0, 2 do
		local a = math.rad(90 + 120 * k)
		table.insert(corners, (cf * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0)).Position)
	end
	for k = 1, 3 do
		beam(corners[k], corners[k % 3 + 1], if an then 0.08 else 0.22, if an then WHITE else color, 0.3)
	end
	disc(pos, cf.LookVector, r * 1.2, if an then color else accent, 0.35, 0.12)
end
MARK.soulflare = function(pos, style, color, accent, s) -- Spirit: spirit flames lick up, wisps rise
	for k = 1, FxLib.pieces(3, s) do
		local f = PIECE.flame(1.2 * s, if k == 2 then accent else color)
		local off = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2 * s
		f.CFrame = CFrame.new(pos + off)
		fade(f, 0.45, { CFrame = CFrame.new(pos + off + Vector3.new(0, 4 * s, 0)), Size = Vector3.one * 0.3 })
	end
	if anime(style) then
		disc(pos, UP, 3 * s, WHITE, 0.25, 0.1)
	end
end
local PRISM = { Color3.fromRGB(255, 120, 140), Color3.fromRGB(140, 255, 170), Color3.fromRGB(130, 170, 255) }
MARK.prism = function(pos, style, color, accent, s) -- Light: a star glint splits into three colours
	crossBars(facing(pos), 4 * s, if anime(style) then 0.12 else 0.35, accent, 0.18, 0)
	for k = 1, 3 do
		local d = randomUnit()
		local sh = PIECE.shard(0.8 * s, color:Lerp(PRISM[k], 0.6))
		sh.Material = Enum.Material.Neon
		sh.CFrame = CFrame.lookAt(pos, pos + d)
		fade(sh, 0.3, { CFrame = CFrame.lookAt(pos + d * 5 * s, pos + d * 6 * s), Size = sh.Size * 0.3 })
	end
end

---------------------------------------------------------------------------
-- Casts: a flourish on the caster (skills and supers)
---------------------------------------------------------------------------

local CAST = {}
CAST.none = function() end
CAST.frostring = function(_o, feet, _d, style, color, accent) -- Frost: ice spikes ring the feet
	for i = 1, FxLib.pieces(6) do
		local a = i / 6 * math.pi * 2
		local at = feet + Vector3.new(math.cos(a), 0, math.sin(a)) * 3
		local sp = PIECE.shard(1, if anime(style) then accent else color)
		sp.CFrame = CFrame.lookAt(at, at + Vector3.new(math.cos(a) * 0.3, 1, math.sin(a) * 0.3))
		sp.Size = Vector3.new(0.5, 0.5, 0.3)
		TweenService:Create(sp, TweenInfo.new(0.1), { Size = Vector3.new(0.6, 0.6, 2.4) }):Play()
		fade(sp, 0.3, nil, 0.15)
	end
	ring(feet, 4, if anime(style) then WHITE else accent, 0.3, 0.12)
end
CAST.flare = function(o, _feet, d, style, color, accent) -- Fire: flames burst from the hands
	local hand = o + d * 1.5
	bits(hand, "flame", 5, 1.2, 14, color, style, 0.6, d, 0.3)
	local core = PIECE.ball(1.2, accent)
	core.CFrame = CFrame.new(hand)
	fade(core, 0.15, { Size = Vector3.one * 3 })
end
CAST.stomp = function(_o, feet, _d, _style, color, accent) -- Earth: a stone juts up under the feet
	local slab = PIECE.rock(1, color)
	slab.CFrame = CFrame.new(feet - Vector3.new(0, 1, 0))
	slab.Size = Vector3.new(4, 0.4, 4)
	TweenService:Create(slab, TweenInfo.new(0.1), { Size = Vector3.new(4, 1.4, 4) }):Play()
	fade(slab, 0.3, nil, 0.2)
	FxLib.dust(feet, 3, accent)
end
CAST.swirl = function(_o, feet, _d, style, color, accent) -- Tide: water swirls up around the hero
	for k = 0, 1 do
		local r = PIECE.ring(5 - k, if k == 0 then color else accent)
		r.Material = if anime(style) then Enum.Material.Neon else Enum.Material.Glass
		r.CFrame = CFrame.new(feet + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		fade(r, 0.4, {
			CFrame = CFrame.new(feet + Vector3.new(0, 4 + k, 0)) * CFrame.Angles(0, 1.5, math.rad(90)),
			Size = Vector3.new(0.1, 3, 3),
		}, k * 0.05)
	end
end
CAST.glint = function(o, _feet, d, style, color, accent) -- Blade: a sword glint at the hand
	local at = o + d * 1.5
	crossBars(facing(at), 3, if anime(style) then 0.1 else 0.25, accent, 0.18, 0)
	if anime(style) then
		crossBars(facing(at), 2, 0.3, color, 0.24, 45)
	end
end
CAST.muzzle = function(o, _feet, d, _style, _color, accent) -- Gunslinger: a muzzle flash and a puff of smoke
	local at = o + d * 2
	crossBars(CFrame.lookAt(at, at + d), 2.4, 0.3, accent, 0.08, 0)
	local f = PIECE.ball(1, accent)
	f.CFrame = CFrame.new(at)
	fade(f, 0.08, { Size = Vector3.one * 2.4 })
	FxLib.emit("smoke", Color3.fromRGB(200, 195, 185), at, 2, d)
end
CAST.reticle = function(o, _feet, d, style, color, accent) -- Gadgeteer: a targeting ring with ticks snaps shut
	local at = o + d * 2.5
	local cf = CFrame.lookAt(at, at + d)
	local r =
		part(Vector3.new(0.12, 4, 4), cf * CFrame.Angles(0, math.rad(90), 0), color, Enum.PartType.Cylinder)
	r.Transparency = 0.3
	fade(r, 0.25, { Size = Vector3.new(0.05, 1.5, 1.5) })
	for k = 0, 3 do
		local tick = part(
			Vector3.new(0.15, 0.6, 0.15),
			cf * CFrame.Angles(0, 0, math.rad(90 * k)) * CFrame.new(0, 2.2, 0),
			if anime(style) then WHITE else accent
		)
		fade(tick, 0.25)
	end
end
CAST.smoke = function(_o, feet, _d, _style, _color, accent) -- Shadow: a puff of smoke at the feet
	FxLib.emit("smoke", Color3.fromRGB(50, 45, 60), feet + Vector3.new(0, 1, 0), 4)
	for _ = 1, FxLib.pieces(3) do
		local b = PIECE.ball(1.5, accent)
		b.Material = Enum.Material.SmoothPlastic
		local off = Vector3.new(math.random() - 0.5, 0.2, math.random() - 0.5) * 4
		b.CFrame = CFrame.new(feet + off)
		fade(
			b,
			0.4,
			{ Size = Vector3.one * 4, CFrame = CFrame.new(feet + off * 1.5 + Vector3.new(0, 1.5, 0)) }
		)
	end
end
CAST.crack = function(_o, feet, _d, style, color, _accent) -- Titan: cracks run out from the feet
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + math.random() * 0.5
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local c = part(
			Vector3.new(0.35, 0.12, 0.5),
			CFrame.lookAt(feet + dir * 0.3, feet + dir),
			if anime(style) then WHITE else Color3.fromRGB(60, 50, 40)
		)
		c.Material = Enum.Material.SmoothPlastic
		TweenService:Create(
			c,
			TweenInfo.new(0.1),
			{ Size = Vector3.new(0.3, 0.12, 4), CFrame = CFrame.lookAt(feet + dir * 2.2, feet + dir * 4) }
		):Play()
		fade(c, 0.4, nil, 0.15)
	end
	ring(feet, 4, color, 0.25, 0.3)
end
CAST.aura = function(o, feet, _d, style, color, accent) -- Martial: a ki aura flares up the body
	for i = 1, FxLib.pieces(6) do
		local a = i / 6 * math.pi * 2
		local at = feet + Vector3.new(math.cos(a), 0, math.sin(a)) * 1.6
		if anime(style) then
			beam(at, at + Vector3.new(0, 6, 0), 0.1, if i % 2 == 0 then WHITE else color, 0.3)
		else
			local f = PIECE.flame(1.4, if i % 2 == 0 then accent else color)
			f.CFrame = CFrame.new(at)
			fade(f, 0.35, { CFrame = CFrame.new(at + Vector3.new(0, 5, 0)), Size = Vector3.one * 0.4 })
		end
	end
	FxLib.charge(o, "Martial", color)
end
CAST.steam = function(o, _feet, d, _style, _color, accent) -- Juggernaut: steam vents from the shoulders
	local right = d:Cross(UP)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
	for _, sgn in { -1, 1 } do
		local at = o + right * sgn * 1.3 + Vector3.new(0, 1, 0)
		FxLib.emit("smoke", Color3.fromRGB(235, 235, 240), at, 2, Vector3.new(0, 1, 0) + right * sgn * 0.4)
		local hot = PIECE.ember(1, accent)
		hot.CFrame = CFrame.new(at)
		fade(hot, 0.2, { Size = Vector3.one * 0.2 })
	end
end
CAST.footprint = function(_o, feet, _d, _style, _color, accent) -- Colossus: a giant's footfall
	local p = part(
		Vector3.new(0.2, 2, 2),
		CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 60, 50),
		Enum.PartType.Cylinder
	)
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 0.3
	fade(p, 0.5, { Size = Vector3.new(0.2, 9, 9) })
	FxLib.dust(feet, 5, accent)
end
CAST.rings = function(o, _feet, d, style, color, _accent) -- Pulse: rings fall in to the hand
	local hand = o + d * 1.5
	for k = 0, 2 do
		local r = part(
			Vector3.new(0.12, 7 - k * 1.5, 7 - k * 1.5),
			CFrame.lookAt(hand, hand + d) * CFrame.Angles(0, math.rad(90), 0),
			if anime(style) and k == 1 then WHITE else color,
			Enum.PartType.Cylinder
		)
		r.Transparency = 0.3
		TweenService:Create(
			r,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, k * 0.05),
			{ Size = Vector3.new(0.12, 0.3, 0.3) }
		):Play()
		Debris:AddItem(r, 0.22 + k * 0.05)
	end
end
CAST.eye = function(o, _feet, d, style, color, accent) -- Mind: a glowing mark on the brow, ripples out
	local brow = o + Vector3.new(0, 2.1, 0) + d * 0.6
	local gem = PIECE.tri(1.2, if anime(style) then WHITE else accent)
	gem.CFrame = CFrame.lookAt(brow, brow + d) * CFrame.Angles(0, math.rad(90), math.rad(45))
	fade(gem, 0.4)
	disc(brow, d, 2.5, color, 0.3, 0.1)
	task.delay(0.08, function()
		disc(brow, d, 4, color, 0.35, 0.08)
	end)
end
CAST.guardian = function(o, _feet, d, style, color, accent) -- Spirit: the guardian looms behind the hero
	local f = flatLook(d)
	local base = CFrame.lookAt(o - f * 2.5, o - f * 2.5 + f)
	local glass = if anime(style) then 0.65 else 0.5
	local pieces = {
		{ Vector3.new(4.5, 4, 2), CFrame.new(0, 1.5, 0), Enum.PartType.Block },
		{ Vector3.one * 2.6, CFrame.new(0, 4.6, 0), Enum.PartType.Ball },
	}
	for _, pc in pieces do
		local p = part(pc[1], base * pc[2], color, pc[3])
		p.Transparency = glass
		fade(p, 0.6, { CFrame = base * pc[2] * CFrame.new(0, 2, 0) })
	end
	FxLib.emit("wisp", accent, o, 4)
end
CAST.halo = function(o, _feet, _d, _style, color, accent) -- Light: a halo shines above the head
	local top = o + Vector3.new(0, 2.8, 0)
	local h = part(
		Vector3.new(0.15, 2.4, 2.4),
		CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90)),
		accent,
		Enum.PartType.Cylinder
	)
	h.Transparency = 0.1
	fade(h, 0.5, { Size = Vector3.new(0.05, 3.4, 3.4) })
	FxLib.emit("star", color, top, 1)
end

---------------------------------------------------------------------------
-- Dashes, swings, cones, novas, fields and charge motes
---------------------------------------------------------------------------

local DASH = {}
DASH.none = function() end
DASH.afterimage = function(from, to, style, color, _accent) -- Shadow, Blade, Martial: fading copies
	for k = 1, FxLib.pieces(3) do
		local at = from:Lerp(to, k / 4)
		local f = flatLook(to - from)
		local base = CFrame.lookAt(at, at + f)
		local glass = 0.45 + k * 0.1
		local c = if anime(style) then WHITE:Lerp(color, 0.5) else color
		local torso = part(Vector3.new(2, 2.6, 1), base, c)
		local head = part(Vector3.one * 1.3, base * CFrame.new(0, 2, 0), c, Enum.PartType.Ball)
		local legs = part(Vector3.new(1.6, 2.4, 0.8), base * CFrame.new(0, -2.5, 0), c)
		for _, p in { torso, head, legs } do
			p.Transparency = glass
			fade(p, 0.35, nil, k * 0.04)
		end
	end
end
DASH.plow = function(from, to, style, _color, accent) -- Titan, Juggernaut: dust and chunks thrown aside
	local f = flatLook(to - from)
	local right = f:Cross(UP)
	for k = 1, 3 do
		local at = from:Lerp(to, k / 3) - Vector3.new(0, 2.5, 0)
		FxLib.dust(at, 3, nil)
		bits(
			at,
			"rock",
			2,
			0.8,
			14,
			accent:Lerp(Color3.fromRGB(120, 110, 100), 0.6),
			style,
			1,
			right * (if k % 2 == 0 then 1 else -1)
		)
	end
end
DASH.trail = function(from, to, _style, color, accent, set) -- Fire, Earth, Spirit: the path's own pieces
	local row = P[set]
	local kind = row and row.piece or "none"
	for k = 1, FxLib.pieces(6) do
		local at = from:Lerp(to, k / 7)
		local p = piece(kind, 0.9, if k % 2 == 0 then accent else color)
		if p then
			p.CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 3, math.random() * 3, 0)
			fade(p, 0.4, { Size = p.Size * 0.2, CFrame = CFrame.new(at + Vector3.new(0, 1.5, 0)) }, k * 0.02)
		end
	end
end
DASH.smoke = function(from, to, _style, _color, _accent) -- Gunslinger: a smoky roll
	for k = 1, 3 do
		FxLib.emit("smoke", Color3.fromRGB(200, 195, 185), from:Lerp(to, k / 4) - Vector3.new(0, 2, 0), 2)
	end
end

-- what drifts in a lasting area each pulse (fall, rise, swirl, orbit, pop)
local MOTION = {}
MOTION.fall = function(p: BasePart, at: Vector3, _center: Vector3, _radius: number)
	p.CFrame = CFrame.new(at + Vector3.new(0, 9, 0))
	fade(p, 0.8, { CFrame = CFrame.new(at) * CFrame.Angles(1, 2, 0) })
end
MOTION.rise = function(p: BasePart, at: Vector3, _center: Vector3, _radius: number)
	p.CFrame = CFrame.new(at)
	fade(p, 0.8, { CFrame = CFrame.new(at + Vector3.new(0, 6, 0)), Size = p.Size * 0.3 })
end
MOTION.swirl = function(p: BasePart, at: Vector3, center: Vector3, _radius: number)
	local off = at - center
	local turned = center + CFrame.Angles(0, 1.2, 0):VectorToWorldSpace(off) * 0.3 + Vector3.new(0, 2, 0)
	p.CFrame = CFrame.new(at)
	fade(p, 0.7, { CFrame = CFrame.new(turned) * CFrame.Angles(0, 3, 0) })
end
MOTION.orbit = function(p: BasePart, at: Vector3, center: Vector3, radius: number)
	local off = Vector3.new(at.X - center.X, 0, at.Z - center.Z)
	off = if off.Magnitude > 0.1 then off.Unit * radius * 0.7 else Vector3.new(radius * 0.7, 0, 0)
	local h = Vector3.new(0, 2.5, 0)
	local a = center + off + h
	local b = center + CFrame.Angles(0, 1, 0):VectorToWorldSpace(off) + h
	p.CFrame = CFrame.lookAt(a, b)
	fade(p, 0.5, { CFrame = CFrame.lookAt(b, b + (b - a)) })
end
MOTION.pop = function(p: BasePart, at: Vector3, _center: Vector3, _radius: number)
	p.CFrame = CFrame.new(at)
	fade(p, 0.45, { CFrame = CFrame.new(at + Vector3.new(0, 3, 0)), Size = p.Size * 1.6 })
end

local function drift(set: string?, center: Vector3, radius: number, style: string, color: Color3)
	local row = FxPlan.pathOf(F, set)
	if not row or row.field.piece == "none" then
		return
	end
	local move = MOTION[row.field.motion]
	local accent = ACCENT[set :: string]
	for k = 1, FxLib.pieces(4) do
		local a = math.random() * math.pi * 2
		local r = math.sqrt(math.random()) * radius
		local at = center + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r)
		local p = piece(row.field.piece, 0.9, if k % 2 == 0 then accent else color)
		if p and move then
			if anime(style) then
				p.Size *= 0.8
			end
			move(p, at, center, radius)
		end
	end
	FxLib.emit(
		if row.field.piece == "flake" then "flake" else "wisp",
		color,
		center + Vector3.new(0, 2, 0),
		2
	)
end

-- charge motes: a few of the path's pieces that orbit the hand (FxPlan.orbit), tight and big at full charge
export type Mote = { p: BasePart, base: Vector3 }
local function motes(set: string?, style: string, color: Color3): { Mote }
	local row = FxPlan.pathOf(F, set)
	local out: { Mote } = {}
	if not row then
		return out
	end
	local accent = ACCENT[set :: string]
	for i = 1, math.min(row.charge.n, FxLib.pieces(row.charge.n)) do
		local p = piece(row.charge.piece, 1, if i % 2 == 0 and not anime(style) then accent else color)
		if p then
			p.Transparency = 1
			table.insert(out, { p = p, base = p.Size })
		end
	end
	return out
end
CombatFx.motes = motes

local function placeMotes(list: { Mote }, set: string?, center: Vector3, level: number, t: number)
	local row = FxPlan.pathOf(F, set)
	if not row then
		return
	end
	for i, m in list do
		local x, y, z, size = FxPlan.orbit(row.charge, level, t, i)
		local at = center + Vector3.new(x, y, z)
		m.p.Size = m.base * size * 1.6
		m.p.CFrame = CFrame.lookAt(at, center) * CFrame.Angles(0, 0, t * 4)
		m.p.Transparency = 0.15 + 0.4 * (1 - level)
	end
end
CombatFx.placeMotes = placeMotes

local function dropMotes(list: { Mote })
	for _, m in list do
		fade(m.p, 0.12, { Size = m.p.Size * 0.2 })
	end
end
CombatFx.dropMotes = dropMotes

---------------------------------------------------------------------------
-- Supers: each path's big moment (the caster also gets the super's name and a screen tint)
---------------------------------------------------------------------------

-- a lasting set of parts that spins about a point (sigils, accretion discs), then fades
local function spinner(specs: { any }, center: Vector3, duration: number, rate: number)
	local parts = {}
	for _, pc in specs do
		local p = part(pc[1], CFrame.new(center) * pc[2], pc[3], pc[4])
		p.Transparency = pc[5] or 0
		table.insert(parts, p)
	end
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function()
		local t = os.clock() - start
		if t >= duration then
			conn:Disconnect()
			for _, p in parts do
				fade(p, 0.3)
			end
			return
		end
		local base = CFrame.new(center) * CFrame.Angles(0, t * rate, 0)
		for i, p in parts do
			p.CFrame = base * specs[i][2]
		end
	end))
end

-- a light column from the sky onto a point
local function column(at: Vector3, width: number, color: Color3, style: string, time: number?)
	local h = 70
	local p = part(
		Vector3.new(h, width, width),
		CFrame.new(at + Vector3.new(0, h / 2 - 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		if anime(style) then WHITE else color,
		Enum.PartType.Cylinder
	)
	p.Transparency = 0.25
	fade(p, time or 0.7, { Size = Vector3.new(h * 1.2, width * 0.15, width * 0.15) })
	if anime(style) then
		local glow = part(Vector3.new(h, width * 2.2, width * 2.2), p.CFrame, color, Enum.PartType.Cylinder)
		glow.Transparency = 0.6
		fade(glow, (time or 0.7) * 1.2)
	end
end

-- pieces that rise out of the ground in a ring, hold, then sink and fade
local function groundRing(
	center: Vector3,
	radius: number,
	n: number,
	make: (number) -> BasePart,
	height: number,
	hold: number,
	tilt: number?
)
	for i = 1, FxLib.pieces(n) do
		local a = i / n * math.pi * 2 + math.random() * 0.3
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = center + out * radius
		local p = make(i)
		local full = p.Size
		p.Size = Vector3.new(full.X, full.Y, 0.2)
		local look = CFrame.lookAt(at, at + UP + out * (tilt or 0.3))
		p.CFrame = look
		TweenService:Create(p, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
			Size = Vector3.new(full.X, full.Y, height),
			CFrame = look * CFrame.new(0, 0, -height / 2),
		}):Play()
		fade(p, 0.35, nil, 0.15 + hold)
	end
end

local SUPER = {}
SUPER.none = function() end
SUPER.icecrown = function(x) -- Frost Blizzard Dome: a crown of ice spikes around the dome's edge
	groundRing(x.c, x.r * 0.95, 12, function()
		return PIECE.shard(2.4, if anime(x.style) then x.accent else x.color)
	end, 12, 1.2, 0.35)
	task.delay(1.4, function()
		bits(x.c + Vector3.new(0, 4, 0), "shard", 10, 1, 30, x.color, x.style, 0.6, nil, 0.5)
	end)
	ring(x.c, x.r, WHITE, 0.6, 0.3)
end
SUPER.sunfall = function(x) -- Fire Sunfall: a small sun forms over the zone and drops onto it
	local sky = x.c + Vector3.new(0, 40, 0)
	local corona = PIECE.flame(4, x.color)
	local sun = PIECE.ball(3, if anime(x.style) then WHITE else x.accent)
	corona.CFrame, sun.CFrame = CFrame.new(sky), CFrame.new(sky)
	local grow = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
	TweenService:Create(corona, grow, { Size = Vector3.one * 22 }):Play()
	TweenService:Create(sun, grow, { Size = Vector3.one * 14 }):Play()
	local drop = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55)
	TweenService:Create(corona, drop, { CFrame = CFrame.new(x.c) }):Play()
	TweenService:Create(sun, drop, { CFrame = CFrame.new(x.c) }):Play()
	fade(corona, 0.25, nil, 0.9)
	fade(sun, 0.2, nil, 0.9)
	task.delay(0.9, function()
		CombatFx.nova(x.c, x.r, x.style, x.color, false, "Fire")
		column(x.c, 10, x.accent, x.style, 0.6)
	end)
end
SUPER.overgrowth = function(x) -- Earth Overgrowth: vines burst up across the zone
	local vine = Color3.fromRGB(70, 140, 60):Lerp(x.accent, 0.4)
	for _ = 1, FxLib.pieces(10) do
		local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * x.r
		local at = x.c + Vector3.new(math.cos(a) * r, -1, math.sin(a) * r)
		local h = 8 + math.random() * 8
		local tilt = CFrame.Angles(math.random() * 0.5 - 0.25, math.random() * 6, math.random() * 0.5 - 0.25)
		local v = part(
			Vector3.new(h, 1.2, 1.2),
			CFrame.new(at) * tilt * CFrame.Angles(0, 0, math.rad(90)),
			vine,
			Enum.PartType.Cylinder
		)
		v.Material = Enum.Material.Grass
		v.Size = Vector3.new(0.5, 1.2, 1.2)
		TweenService:Create(v, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
			Size = Vector3.new(h, 1.2, 1.2),
			CFrame = CFrame.new(at) * tilt * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		}):Play()
		fade(v, 0.4, nil, 1.6)
		local bud = PIECE.ball(1.6, if anime(x.style) then WHITE else x.accent)
		bud.CFrame = CFrame.new(at) * tilt * CFrame.new(0, h, 0)
		bud.Transparency = 1
		TweenService:Create(
			bud,
			TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.3),
			{ Transparency = 0 }
		):Play()
		fade(bud, 0.4, nil, 1.6)
	end
end
SUPER.tsunami = function(x) -- Tide Tsunami: a wall of water with a foam crest rolls down the line
	local from, to = x.o - Vector3.new(0, 2, 0), x.e - Vector3.new(0, 2, 0)
	local f = flatLook(to - from)
	local w = x.width
	local wall = part(Vector3.new(w, 10, 4), CFrame.lookAt(from, from + f) * CFrame.new(0, 4, 0), x.color)
	wall.Material = if anime(x.style) then Enum.Material.Neon else Enum.Material.Glass
	wall.Transparency = if anime(x.style) then 0.55 else 0.3
	local crest = part(
		Vector3.new(w * 1.05, 1.4, 2.4),
		CFrame.lookAt(from, from + f) * CFrame.new(0, 9.5, -1),
		x.accent
	)
	local time = 0.9
	for _, p in { wall, crest } do
		local offset = p.Position - from
		TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Linear), {
			CFrame = CFrame.lookAt(to + offset, to + offset + f),
		}):Play()
		fade(p, 0.3, nil, time)
	end
	task.delay(time, function()
		bits(to + Vector3.new(0, 4, 0), "drop", 12, 1.4, 28, x.color, x.style, 1.2, f, 0.5)
	end)
end
SUPER.splitter = function(x) -- Blade Heaven Splitter: a giant vertical crescent cuts down the line
	local from, to = x.o, x.e
	local f = (to - from).Unit
	local start = CFrame.lookAt(from, from + f)
	local segs = 9
	local rad = 12
	for i = 0, segs - 1 do
		local a0 = math.rad(-70 + i / segs * 140)
		local a1 = math.rad(-70 + (i + 1) / segs * 140)
		local p0 = Vector3.new(0, math.sin(a0) * rad, -math.cos(a0) * rad * 0.35)
		local p1 = Vector3.new(0, math.sin(a1) * rad, -math.cos(a1) * rad * 0.35)
		local mid = (p0 + p1) / 2
		local thick = (if anime(x.style) then 0.3 else 0.9) * (0.4 + math.sin((i + 0.5) / segs * math.pi))
		local seg = part(
			Vector3.new(thick, thick, (p1 - p0).Magnitude),
			start * CFrame.lookAt(mid, p1, Vector3.xAxis),
			if anime(x.style) then WHITE else x.color
		)
		local goal = CFrame.lookAt(to, to + f) * CFrame.lookAt(mid, p1, Vector3.xAxis)
		TweenService:Create(seg, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
		fade(seg, 0.2, nil, 0.35)
	end
	beam(
		from - Vector3.new(0, 2.5, 0),
		to - Vector3.new(0, 2.5, 0),
		if anime(x.style) then 0.15 else 0.5,
		x.accent,
		0.9
	)
	if x.mine and not CombatFx.reduceFlashing and slashFrame then
		-- the screen itself is cut: a thin bright line across it
		local s = slashFrame :: Frame
		s.BackgroundColor3 = if anime(x.style) then WHITE else x.color
		s.BackgroundTransparency = 0
		s.Size = UDim2.new(0, 0, 0, 6)
		TweenService:Create(s, TweenInfo.new(0.12), { Size = UDim2.new(1.6, 0, 0, 6) }):Play()
		TweenService:Create(
			s,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.2),
			{ BackgroundTransparency = 1 }
		):Play()
	end
end
SUPER.highnoon = function(x) -- Gunslinger High Noon: a sun glare, then a fan of tracers ending in glints
	local f = x.d.Unit
	local right = f:Cross(UP)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
	local glare = PIECE.ball(3, x.accent)
	glare.CFrame = CFrame.new(x.o + Vector3.new(0, 4, 0))
	fade(glare, 0.5, { Size = Vector3.one * 12 })
	local half = math.rad((x.cone or 90) / 2)
	for i = 1, 6 do
		local a = -half + (i - 1) / 5 * half * 2
		local d = (f * math.cos(a) + right * math.sin(a)).Unit
		local tip = x.o + d * x.range * (0.6 + math.random() * 0.4)
		task.delay(i * 0.05, function()
			HEAD.tracer(x.o, tip, x.style, x.color, x.accent, 1.3)
			task.delay(0.12, function()
				crossBars(facing(tip), 3, 0.3, x.accent, 0.25, 0)
			end)
		end)
	end
end
SUPER.mechdrop = function(x) -- Gadgeteer Mech Suit: hex plates fly in and lock on, a scan beam
	local at = x.o
	for i = 1, FxLib.pieces(8) do
		local a = i / 8 * math.pi * 2
		local from = at + Vector3.new(math.cos(a) * 14, 6 + math.random() * 6, math.sin(a) * 14)
		local plate = PIECE.plate(2.4, if i % 2 == 0 then x.accent else x.color)
		plate.Material = if anime(x.style) then Enum.Material.Neon else Enum.Material.Metal
		plate.CFrame = CFrame.lookAt(from, at)
		TweenService:Create(
			plate,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In, 0, false, i * 0.03),
			{
				CFrame = CFrame.lookAt(at + (from - at).Unit * 2, at),
				Size = Vector3.new(1.4, 0.2, 1.4),
			}
		):Play()
		fade(plate, 0.15, nil, 0.4 + i * 0.03)
	end
	task.delay(0.45, function()
		column(at, 6, x.color, x.style, 0.5)
		ring(at - Vector3.new(0, 2.5, 0), 12, x.accent, 0.4, 0.2)
	end)
end
SUPER.eclipse = function(x) -- Shadow Eclipse: a black sun with a burning rim, the light goes out
	local sky = x.c + Vector3.new(0, 22, 0)
	local cf = facing(sky)
	local rim = part(
		Vector3.new(0.4, 2, 2),
		cf * CFrame.Angles(0, math.rad(90), 0),
		if anime(x.style) then WHITE else x.color,
		Enum.PartType.Cylinder
	)
	rim.Transparency = 0.1
	TweenService:Create(rim, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = Vector3.new(0.4, 17, 17) })
		:Play()
	fade(rim, 0.4, nil, 1)
	local sun = PIECE.ball(2, x.accent)
	sun.Material = Enum.Material.SmoothPlastic
	sun.CFrame = CFrame.new(sky)
	TweenService:Create(sun, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = Vector3.one * 15 }):Play()
	fade(sun, 0.4, nil, 1)
	for _ = 1, 6 do
		local d = Vector3.new(math.random() - 0.5, -1, math.random() - 0.5).Unit
		beam(sky, sky + d * 30, if anime(x.style) then 0.1 else 0.4, x.color, 0.5)
	end
	if x.mine then
		flashScreen(x.accent, 0.8, 0.55) -- the eclipse dims your screen
	end
	task.delay(0.6, function()
		bits(x.c, "kunai", 10, 1.2, 30, x.accent, x.style, 0.2, nil, 0.45)
	end)
end
SUPER.meteor = function(x) -- Titan Meteor Leap: the landing craters, stones fly, a fire column
	local floor = x.c - Vector3.new(0, 1.2, 0)
	local crater = part(
		Vector3.new(0.3, 4, 4),
		CFrame.new(floor) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(55, 45, 40),
		Enum.PartType.Cylinder
	)
	crater.Material = Enum.Material.SmoothPlastic
	TweenService:Create(crater, TweenInfo.new(0.15), { Size = Vector3.new(0.3, x.r * 1.2, x.r * 1.2) }):Play()
	fade(crater, 0.6, nil, 1.2)
	bits(x.c, "rock", 10, 1.6, 26, Color3.fromRGB(130, 115, 100), x.style, 1.4, nil, 0.6)
	column(x.c, 8, x.color, x.style, 0.5)
	disc(floor, UP, x.r, x.accent, 0.5, 0.6)
end
SUPER.heavenfall = function(x) -- Martial Heavenfall Beam: a thick ki beam wound with spinning rings
	local from, to = x.o, x.e
	local d = to - from
	local len = d.Magnitude
	if len < 1 then
		return
	end
	local cf = CFrame.lookAt(from + d / 2, to)
	local w = x.width * 0.5
	local core = part(Vector3.new(w * 0.4, w * 0.4, len), cf, if anime(x.style) then WHITE else x.accent)
	fade(core, 0.6, { Size = Vector3.new(0.2, 0.2, len) })
	local glow = part(Vector3.new(w, w, len), cf, x.color)
	glow.Transparency = 0.45
	fade(glow, 0.7, { Size = Vector3.new(w * 1.4, w * 1.4, len) })
	for k = 1, FxLib.pieces(5) do
		local at = from + d * (k / 6)
		local r = part(
			Vector3.new(0.3, w * 1.6, w * 1.6),
			CFrame.lookAt(at, to) * CFrame.Angles(0, math.rad(90), 0),
			x.accent,
			Enum.PartType.Cylinder
		)
		r.Transparency = 0.2
		fade(r, 0.4, { Size = Vector3.new(0.1, w * 2.6, w * 2.6) }, k * 0.04)
	end
	column(to, 10, x.color, x.style, 0.6)
end
SUPER.siege = function(x) -- Juggernaut Siege Mode: four anchors slam into the ground, steam vents
	local at = x.o - Vector3.new(0, 3, 0)
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local spot = at + out * 5
		local anchor = part(
			Vector3.new(1.4, 6, 2.4),
			CFrame.new(spot + Vector3.new(0, 14, 0)) * CFrame.Angles(0, -a, 0.35),
			x.color
		)
		anchor.Material = Enum.Material.Metal
		TweenService:Create(
			anchor,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, k * 0.06),
			{
				CFrame = CFrame.new(spot + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, -a, 0.35),
			}
		):Play()
		fade(anchor, 0.4, nil, 1.4)
		task.delay(0.2 + k * 0.06, function()
			FxLib.dust(spot, 3, nil)
			FxLib.emit("smoke", Color3.fromRGB(235, 235, 240), spot + Vector3.new(0, 3, 0), 3, UP)
			crossBars(facing(spot + Vector3.new(0, 1, 0)), 2.5, 0.25, x.accent, 0.12, 0)
		end)
	end
	ring(at + Vector3.new(0, 0.3, 0), x.r * 0.6, x.accent, 0.5, 0.4)
end
SUPER.titanrise = function(x) -- Colossus Titan Form: a red column, stone pillars rise in a ring
	column(x.o, 12, x.color, x.style, 0.8)
	groundRing(x.o - Vector3.new(0, 3, 0), 10, 6, function()
		return PIECE.rock(3, Color3.fromRGB(120, 105, 90))
	end, 9, 0.9, 0.15)
	disc(x.o - Vector3.new(0, 2.8, 0), UP, x.r * 0.6, x.accent, 0.6, 0.6)
end
SUPER.singularity = function(x) -- Pulse Singularity: a black hole with a spinning disc, matter streaks in
	local at = x.c + Vector3.new(0, 7, 0)
	local hole = PIECE.ball(1, x.accent)
	hole.Material = Enum.Material.SmoothPlastic
	hole.CFrame = CFrame.new(at)
	TweenService:Create(hole, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = Vector3.one * 7 }):Play()
	fade(hole, 0.3, { Size = Vector3.one * 0.5 }, 2.2)
	spinner({
		{
			Vector3.new(0.2, 16, 16),
			CFrame.Angles(0.35, 0, math.rad(90)),
			x.color,
			Enum.PartType.Cylinder,
			0.35,
		},
		{
			Vector3.new(0.25, 11, 11),
			CFrame.Angles(0.35, 0, math.rad(90)),
			if anime(x.style) then WHITE else x.color,
			Enum.PartType.Cylinder,
			0.15,
		},
	}, at, 2.4, 3)
	for k = 1, FxLib.pieces(10) do
		task.delay(k * 0.15, function()
			local a = math.random() * math.pi * 2
			local from = at + Vector3.new(math.cos(a) * x.r, math.random() * 8 - 4, math.sin(a) * x.r)
			beam(from, at, if anime(x.style) then 0.08 else 0.25, x.color, 0.25)
		end)
	end
	if x.mine then
		flashScreen(x.accent, 0.6, 0.35)
	end
end
SUPER.psistorm = function(x) -- Mind Psychic Storm: a huge sigil turns on the ground, debris lifts
	local at = x.c - Vector3.new(0, 2.6, 0)
	local r = x.r * 0.8
	local col = if anime(x.style) then WHITE else x.color
	local specs = {
		{
			Vector3.new(0.15, r * 2, r * 2),
			CFrame.Angles(0, 0, math.rad(90)),
			x.color,
			Enum.PartType.Cylinder,
			0.55,
		},
	}
	for k = 0, 2 do
		local a0 = math.rad(90 + 120 * k)
		local a1 = math.rad(90 + 120 * (k + 1))
		local p0 = Vector3.new(math.cos(a0) * r, 0.2, math.sin(a0) * r)
		local p1 = Vector3.new(math.cos(a1) * r, 0.2, math.sin(a1) * r)
		table.insert(
			specs,
			{ Vector3.new(0.5, 0.2, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), col }
		)
		-- a small ring at each corner of the triangle
		table.insert(specs, {
			Vector3.new(0.15, 3, 3),
			CFrame.new(p0) * CFrame.Angles(0, 0, math.rad(90)),
			x.accent,
			Enum.PartType.Cylinder,
			0.3,
		})
	end
	-- and the eye ring at the heart (an original sigil, plain geometry)
	table.insert(specs, {
		Vector3.new(0.2, r * 0.4, r * 0.4),
		CFrame.Angles(0, 0, math.rad(90)),
		x.accent,
		Enum.PartType.Cylinder,
		0.2,
	})
	spinner(specs, at, 2.2, 0.8)
	for _ = 1, FxLib.pieces(8) do
		local a, rr = math.random() * math.pi * 2, math.sqrt(math.random()) * x.r
		local spot = at + Vector3.new(math.cos(a) * rr, 0.5, math.sin(a) * rr)
		local rock = PIECE.rock(1 + math.random() * 1.5, Color3.fromRGB(120, 115, 120))
		rock.CFrame = CFrame.new(spot)
		TweenService:Create(
			rock,
			TweenInfo.new(1.8, Enum.EasingStyle.Sine),
			{ CFrame = CFrame.new(spot + Vector3.new(0, 8 + math.random() * 6, 0)) * CFrame.Angles(2, 3, 1) }
		):Play()
		fade(rock, 0.3, nil, 1.8)
	end
end
SUPER.ascend = function(x) -- Spirit Ascended Guardian: a spirit column, spirit fires ring the hero
	column(x.o, 9, x.color, x.style, 0.9)
	groundRing(x.o - Vector3.new(0, 3, 0), 6, 6, function(i)
		local f = PIECE.flame(2, if i % 2 == 0 then x.accent else x.color)
		f.Shape = Enum.PartType.Block
		return f
	end, 5, 0.8, 0)
	FxLib.emit("glyph", x.color, x.o - Vector3.new(0, 2, 0), 1)
end
SUPER.dawn = function(x) -- Light Dawnburst: a sunrise: a flat flash across the ground, rays, a column
	local floor = x.c - Vector3.new(0, 2.6, 0)
	disc(floor, UP, x.r, x.accent, 0.6, 0.4)
	disc(floor + Vector3.new(0, 0.2, 0), UP, x.r * 0.7, x.color, 0.8, 0.8)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		local d = Vector3.new(math.cos(a), 0.15, math.sin(a))
		beam(
			x.c,
			x.c + d * x.r * 1.3,
			if anime(x.style) then 0.12 else 0.5,
			if k % 2 == 0 then x.accent else x.color,
			0.5
		)
	end
	column(x.c, 14, x.accent, x.style, 0.7)
	if x.mine then
		flashScreen(x.accent, 0.5, 0.5)
	end
end

-- supers whose moment comes at the landing (CombatFx.area) rather than the cast
local AT_LANDING = { meteor = true }

---------------------------------------------------------------------------
-- The path section's entry points (called from the shapes above and from CombatFx.cast / area)
---------------------------------------------------------------------------

local function rowOf(set: string?): any?
	return FxPlan.pathOf(F, set)
end

function sig.head(set: string?, from: Vector3, to: Vector3, style: string, color: Color3, scale: number)
	local row = rowOf(set)
	if not row or (to - from).Magnitude < 1 then
		return
	end
	HEAD[row.head](from, to, style, color, ACCENT[set :: string], scale)
end

function sig.mark(set: string?, pos: Vector3, style: string, color: Color3, scale: number, dir: Vector3?)
	local row = rowOf(set)
	if row then
		MARK[row.mark](pos, style, color, ACCENT[set :: string], scale, dir)
	end
end

function sig.dash(set: string?, from: Vector3, to: Vector3, style: string, color: Color3)
	local row = rowOf(set)
	if row and (to - from).Magnitude > 2 then
		DASH[row.dash](from, to, style, color, ACCENT[set :: string], set)
	end
end

-- a cone: the path's pieces sweep out across the fan
function sig.cone(
	set: string?,
	origin: Vector3,
	f: Vector3,
	range: number,
	coneDeg: number,
	style: string,
	color: Color3
)
	local row = rowOf(set)
	if not row or row.piece == "none" then
		return
	end
	if row.head ~= "none" and row.head ~= "tracer" then
		-- a few heads fan out (Pulse's push wave reads as warped spheres, Colossus' clap as boulders...)
		local right = f:Cross(UP)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
		local half = math.rad(coneDeg / 2)
		for i = -1, 1 do
			local d = (f * math.cos(half * i * 0.7) + right * math.sin(half * i * 0.7)).Unit
			HEAD[row.head](origin, origin + d * range * 0.8, style, color, ACCENT[set :: string], 0.7)
		end
	end
	bits(origin + f * 2, row.piece, 6, 1, range * 2.2, color, style, 0, f * 2, 0.35)
end

-- a melee swing: two of the path's pieces kick out from the reach (more on a combo's last hit)
function sig.swing(set: string?, at: Vector3, f: Vector3, style: string, color: Color3, last: boolean)
	local row = rowOf(set)
	if not row or row.piece == "none" then
		return
	end
	bits(at, row.piece, if last then 4 else 2, 0.7, 12, color, style, 0.2, f, 0.25)
	if last then
		MARK[row.mark](at, style, color, ACCENT[set :: string], 0.6, f)
	end
end

-- a nova: the path's pieces ring out from the centre, and its mark at the heart
function sig.burst(set: string?, center: Vector3, radius: number, style: string, color: Color3, big: boolean?)
	local row = rowOf(set)
	if not row or row.piece == "none" then
		return
	end
	local n = math.clamp(math.floor(radius * 0.6), 6, 14)
	bits(center, row.piece, n, 1.1, radius * 2.6, color, style, 0.15, nil, 0.4)
	MARK[row.mark](
		center,
		style,
		color,
		ACCENT[set :: string],
		math.clamp(radius / 8, 1, 3) * (if big then 1.3 else 1),
		nil
	)
end

sig.drift = drift
sig.motes = motes
sig.placeMotes = placeMotes
sig.dropMotes = dropMotes

-- the caster's flourish for a skill or super (not basics): mine from CombatClient.fire, others' from cast()
function CombatFx.castFlourish(row: any, style: string, o: Vector3, d: Vector3, userId: number?)
	local pr = rowOf(row.set)
	if not pr or row.slot == "basic" then
		return
	end
	local color = CombatFx.colorOf(row.set, userId)
	local dir = if d.Magnitude > 1e-3 then d.Unit else Vector3.new(0, 0, -1)
	CAST[pr.cast](o, o - Vector3.new(0, 3.2, 0), dir, style, color, ACCENT[row.set])
end

-- the super's big moment. data as for CombatFx.cast; landing supers (AT_LANDING) come from CombatFx.area.
function CombatFx.superMoment(row: any, style: string, data: CastData, landing: boolean?)
	local pr = rowOf(row.set)
	if not pr or row.slot ~= "super" or pr.super.look == "none" then
		return
	end
	local look = pr.super.look
	if (AT_LANDING[look] == true) ~= (landing == true) then
		return
	end
	local o, d = data.o, data.d
	local mine = data.a ~= nil and data.a == Players.LocalPlayer.UserId
	local color = CombatFx.colorOf(row.set, data.a)
	if data.aw then
		color = color:Lerp(AWAKEN, 0.35)
	end
	local e = data.e or (o + d * (row.range or 30))
	local c = data.c or (if row.shape == "line" then e else o)
	SUPER[look]({
		o = o,
		d = d,
		e = e,
		c = c,
		r = data.r or row.radius or 20,
		range = row.range or 40,
		cone = row.cone,
		width = row.width or 10,
		style = style,
		color = color,
		accent = ACCENT[row.set],
		mine = mine,
	})
	FxLib.super(c, row.set, color)
	if mine then
		local name = string.upper(row.name or row.id)
		CombatFx.banner(if style == "Anime" then name else name .. "!", color, style)
		flashScreen(TINT[row.set], 0.35, if style == "Anime" then 0.4 else 0.3)
	end
end

---------------------------------------------------------------------------
-- Impacts and numbers
---------------------------------------------------------------------------

function CombatFx.impact(
	pos: Vector3,
	crit: boolean,
	style: string,
	mine: boolean,
	color: Color3?,
	set: string?
)
	local c = color or SET_COLOR.Volt
	local scale = if crit then 1.5 else 1
	FxLib.impact(pos, set, c, scale * (if mine then 1 else 0.6), nil, style)
	sig.mark(set, pos, style, c, scale * (if mine then 1 else 0.6), nil)
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

-- Weighty hits (Config.Combat.weight): sparks spray out of the hit along `dir` (from the hit into the robot),
-- hot white cores fading to the hit colour; heavy hits throw twice as many, further. Comes out of the device
-- debris budget, so a crowd fight on a phone stays cheap. PLACEHOLDER ART: part-built.
function CombatFx.hitSparks(pos: Vector3, dir: Vector3, color: Color3?, heavy: boolean)
	local W = Config.Combat.weight
	local n = DebrisBudget.lease(if heavy then W.sparks * 2 else W.sparks, W.sparkLife)
	local d = if dir.Magnitude > 1e-3 then dir.Unit else UP
	local c = color or WHITE
	local reach = if heavy then 9 else 5.5
	for _ = 1, n do
		local v = (d + randomUnit() * 0.75 + UP * 0.25).Unit
		local len = 0.6 + math.random() * (if heavy then 1.6 else 1)
		local p = part(Vector3.new(0.14, 0.14, len), CFrame.lookAt(pos, pos + v), WHITE)
		local to = pos + v * reach * (0.5 + math.random() * 0.6) - UP * math.random() * 1.5
		TweenService
			:Create(
				p,
				TweenInfo.new(W.sparkLife, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = c }
			)
			:Play()
		fade(
			p,
			W.sparkLife,
			{ CFrame = CFrame.lookAt(to, to + v), Size = Vector3.new(0.06, 0.06, len * 0.4) }
		)
	end
	if heavy then
		ring(pos, 4.5, c, 0.2, 0.5)
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

-- A Torpedo Sentry's torpedo: slow, with a bubble trail, turning after its hero the way the server's does
-- (EnemySim.steer), so what you see is what hits you
function CombatFx.torpedo(pos: Vector3, vel: Vector3, home: number, turn: number)
	local speed = vel.Magnitude
	if speed < 1 then
		return
	end
	local body = part(Vector3.new(1.4, 1.4, 4), CFrame.lookAt(pos, pos + vel), ENEMY)
	local life = math.min(4, 130 / speed)
	local shot =
		{ x = pos.X, y = pos.Y, z = pos.Z, vx = vel.X, vy = vel.Y, vz = vel.Z, home = home, turn = turn }
	local target = Players:GetPlayerByUserId(home)
	local t, trail = 0, 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		local char = target and target.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local p = root.Position
			EnemySim.steer(shot, { { id = home, x = p.X, y = p.Y - 1.5, z = p.Z } }, dt)
		end
		shot.x += shot.vx * dt
		shot.y += shot.vy * dt
		shot.z += shot.vz * dt
		local at = Vector3.new(shot.x, shot.y, shot.z)
		body.CFrame = CFrame.lookAt(at, at + Vector3.new(shot.vx, shot.vy, shot.vz))
		trail += dt
		if trail >= 0.08 then
			trail = 0
			local b = part(
				Vector3.new(0.6, 0.6, 0.6),
				CFrame.new(at),
				Color3.new(0.85, 0.95, 1),
				Enum.PartType.Ball
			)
			b.Transparency = 0.4
			TweenService
				:Create(b, TweenInfo.new(0.6), { Transparency = 1, Position = at + Vector3.new(0, 2, 0) })
				:Play()
			Debris:AddItem(b, 0.6)
		end
		if t >= life or not body.Parent then
			conn:Disconnect()
			body:Destroy()
		end
	end))
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
	FxLib.dust(center + Vector3.new(0, 0.3, 0), radius)
	ring(center + Vector3.new(0, 0.3, 0), radius * 1.2, Color3.fromRGB(150, 130, 110), 0.4, 0.8)
	ring(center + Vector3.new(0, 0.3, 0), radius, WARN, 0.25, 0.3)
end

function CombatFx.blocked(pos: Vector3)
	local p = part(Vector3.one * 1.2, CFrame.new(pos), Color3.fromRGB(200, 235, 255), Enum.PartType.Ball)
	fade(p, 0.15, { Size = Vector3.one * 3 })
end

---------------------------------------------------------------------------
-- The newer robots (Config.Enemies typeIds 10 to 18; numbers in Config.Fx.robots). PLACEHOLDER ART.
---------------------------------------------------------------------------

local R = F.robots
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- What effects never land on: the effects, the robots, the load-test bots and every hero
local function skipList(): { Instance }
	local skip: { Instance } = { folder }
	for _, name in { "Enemies", "LoadBots", "MoveFx", "AbilityParts" } do
		local inst = Workspace:FindFirstChild(name)
		if inst then
			table.insert(skip, inst)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	return skip
end

-- The ground under a point (within `down` studs), else the point itself
local function groundBelow(pos: Vector3, down: number?): Vector3
	groundParams.FilterDescendantsInstances = skipList()
	local hit =
		Workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -(down or 12) - 2, 0), groundParams)
	return if hit then hit.Position else pos
end

-- A Sniper's round (shot style 1): a bright, long white-hot tracer with a red glow and a muzzle flash
local function tracer(pos: Vector3, vel: Vector3, speed: number)
	local tr = R.tracer
	local cf = CFrame.lookAt(pos, pos + vel)
	local core = part(Vector3.new(tr.width, tr.width, tr.length), cf, rgb(tr.color))
	local glow = part(Vector3.new(tr.width * 3, tr.width * 3, tr.length * 1.1), cf, rgb(tr.glow))
	glow.Transparency = 0.55
	local flash = part(Vector3.one * 1.2, CFrame.new(pos), rgb(tr.color), Enum.PartType.Ball)
	fade(flash, 0.12, { Size = Vector3.one * 3 })
	FxLib.emit("spark", rgb(tr.glow), pos, 4, vel)
	local life = math.min(1, 150 / speed)
	local goal = { CFrame = CFrame.lookAt(pos + vel * life, pos + vel * (life + 1)) }
	for _, p in { core, glow } do
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), goal):Play()
		Debris:AddItem(p, life)
	end
end

-- An Interceptor's net (shot style 2): a square net that opens and spins as it flies
local function net(pos: Vector3, vel: Vector3, speed: number)
	local n = R.net
	local half = n.size * 0.5
	local color = rgb(n.color)
	-- the frame and a cross, as (offset, size) pairs in the net's own frame
	local bars = {
		{ Vector3.new(0, half, 0), Vector3.new(n.size, 0.15, 0.15) },
		{ Vector3.new(0, -half, 0), Vector3.new(n.size, 0.15, 0.15) },
		{ Vector3.new(half, 0, 0), Vector3.new(0.15, n.size, 0.15) },
		{ Vector3.new(-half, 0, 0), Vector3.new(0.15, n.size, 0.15) },
		{ Vector3.zero, Vector3.new(n.size, 0.1, 0.1) },
		{ Vector3.zero, Vector3.new(0.1, n.size, 0.1) },
	}
	local parts = {}
	for _, b in bars do
		local p = part(b[2], CFrame.new(pos), color)
		p.Transparency = 0.15
		table.insert(parts, p)
	end
	local life = math.min(1.6, 100 / speed)
	local t = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		if t >= life then
			conn:Disconnect()
			for _, p in parts do
				p:Destroy()
			end
			return
		end
		local open = math.clamp(t / 0.15, 0.3, 1)
		local at = pos + vel * t
		local cf = CFrame.lookAt(at, at + vel) * CFrame.Angles(0, 0, t * n.spin)
		for i, p in parts do
			p.CFrame = cf * CFrame.new(bars[i][1] * open)
		end
	end))
end

-- A robot's shot: a glowing pellet you can see coming (and dodge). style: 1 a Sniper round, 2 a net
function CombatFx.enemyShot(pos: Vector3, vel: Vector3, style: number?)
	local speed = vel.Magnitude
	if speed < 1 then
		return
	end
	if style == 1 then
		tracer(pos, vel, speed)
		return
	elseif style == 2 then
		net(pos, vel, speed)
		return
	end
	local p = part(Vector3.new(F.shot.width, F.shot.width, 2.2), CFrame.lookAt(pos, pos + vel), ENEMY)
	local life = math.min(1.6, 80 / speed)
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(pos + vel * life, pos + vel * (life + 1)),
	}):Play()
	Debris:AddItem(p, life)
end

-- A famous fake's or an evil twin's shot (shot style 4, lore step 4): a robot shot drawn in a power path's own
-- look: the path's trail and head (a lance of light, a blade's afterimage...) over a glowing core in the path's
-- colour that flies at the shot's real speed, so it can still be dodged. PLACEHOLDER ART like the other shots.
function CombatFx.pathShot(pos: Vector3, vel: Vector3, set: string?, style: string, color: Color3)
	local speed = vel.Magnitude
	if speed < 1 then
		return
	end
	local life = math.min(1.6, 90 / speed)
	local to = pos + vel * life
	FxLib.emit("glow", color, pos, 1)
	FxLib.trail(pos, pos + vel * math.min(life, 0.35), set, color)
	sig.head(set, pos, pos + vel * math.min(life, 0.35), style, color, 1)
	local cf = CFrame.lookAt(pos, pos + vel)
	local core = part(Vector3.new(F.shot.width * 1.4, F.shot.width * 1.4, 3.6), cf, color)
	local tip = part(Vector3.new(F.shot.width * 0.6, F.shot.width * 0.6, 4.2), cf, WHITE)
	local goal = { CFrame = CFrame.lookAt(to, to + vel) }
	for _, p in { core, tip } do
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), goal):Play()
		Debris:AddItem(p, life)
	end
end

-- A Grappler's hook (shot style 3): a claw on a cable from the robot's launcher (`from` follows it; nil

-- when the robot is gone). It flies until it catches a hero (then holds on while `out()` says the hook is
-- still out, the robot's `hooked` bit), sticks where it hits the world, or runs out; then it reels back in.
function CombatFx.hook(from: () -> Vector3?, pos: Vector3, vel: Vector3, out: () -> boolean)
	local speed = vel.Magnitude
	if speed < 1 then
		return
	end
	local hk = R.hook
	local clawColor = rgb(hk.claw)
	local cable = part(Vector3.new(hk.cable, hk.cable, 1), CFrame.new(pos), rgb(hk.color))
	cable.Material = Enum.Material.Metal
	local claw = part(Vector3.new(0.9, 0.9, 0.6), CFrame.new(pos), clawColor)
	claw.Material = Enum.Material.Metal
	local prongs = {}
	for _, k in { -1, 1 } do
		local p = part(Vector3.new(0.22, 0.3, 1), CFrame.new(pos), clawColor)
		p.Material = Enum.Material.Metal
		table.insert(prongs, { p = p, side = k })
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skipList()
	local life = math.min(1.5, 60 / speed)
	local grappler = Config.Enemies.Grappler
	local reach = (if grappler and grappler.hook then grappler.hook.shotRadius else 3.5) + 1.5
	local phase, t, tip = "fly", 0, pos
	local held: BasePart? = nil
	local reelFrom, reelT, stuckT = pos, 0, 0
	local conn: RBXScriptConnection
	local function finish()
		conn:Disconnect()
		fade(cable, 0.1)
		fade(claw, 0.1)
		for _, pr in prongs do
			fade(pr.p, 0.1)
		end
	end
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function(dt)
		local a = from()
		if not a then
			finish()
			return
		end
		t += dt
		if phase == "fly" then
			local nextTip = tip + vel * dt
			for _, p in Players:GetPlayers() do
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - nextTip).Magnitude < reach then
					held = root
					phase = "held"
					t = 0
					break
				end
			end
			if phase == "fly" then
				local hit = Workspace:Raycast(tip, nextTip - tip, params)
				local cut = t >= 0.3 and not out() -- the cable was cut (the Grappler was stunned)
				if hit and not cut then
					tip, phase, stuckT = hit.Position, "stuck", 0.15
				elseif cut or t >= life then
					tip, phase = nextTip, "reel"
					reelFrom, reelT = tip, 0
				else
					tip = nextTip
				end
			end
		elseif phase == "held" then
			local root = held
			if root and root.Parent and t < hk.hold and (t < 0.3 or out()) then
				tip = root.Position
			else
				phase, reelFrom, reelT = "reel", tip, 0
			end
		elseif phase == "stuck" then
			stuckT -= dt
			if stuckT <= 0 then
				phase, reelFrom, reelT = "reel", tip, 0
			end
		else
			reelT += dt / hk.reel
			tip = reelFrom:Lerp(a, math.min(1, reelT))
			if reelT >= 1 then
				finish()
				return
			end
		end
		local d = tip - a
		local len = math.max(0.2, d.Magnitude)
		local dir = if d.Magnitude > 1e-3 then d.Unit else vel.Unit
		cable.Size = Vector3.new(hk.cable, hk.cable, len)
		cable.CFrame = CFrame.lookAt(a + d / 2, tip)
		local cf = CFrame.lookAt(tip, tip + dir)
		claw.CFrame = cf
		local spread = if phase == "fly" then 30 else 10 -- the prongs close on what they catch
		for _, pr in prongs do
			pr.p.CFrame = cf
				* CFrame.new(pr.side * 0.35, 0, -0.5)
				* CFrame.Angles(0, pr.side * math.rad(-spread), 0)
		end
	end))
end

-- A Sniper's aim: a red laser from its rifle tip (`from`, nil when the robot is gone) to its hero (`to`) for
-- `time` s. For the last `lock` s it stops following, thickens and blinks: the aim is locked, dodge now.
-- on() (optional) says the aim still holds (the robot's aim bit): a stun or a pull breaks it, and the laser goes.
function CombatFx.aimLaser(
	from: () -> Vector3?,
	to: () -> Vector3?,
	time: number,
	lock: number,
	on: (() -> boolean)?
)
	local am = R.aim
	local color = rgb(am.color)
	local beamPart = part(Vector3.new(am.width, am.width, 1), CFrame.new(), color)
	beamPart.Transparency = 0.2
	local dot = part(Vector3.one * am.dot, CFrame.new(), color, Enum.PartType.Ball)
	local t = 0
	local last: Vector3? = nil
	local locked: Vector3? = nil
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		local a = from()
		if not a or t >= time or (on and not on()) then
			conn:Disconnect()
			beamPart:Destroy()
			dot:Destroy()
			return
		end
		local lockOn = t >= time - lock
		local b: Vector3?
		if lockOn then
			locked = locked or last or to()
			b = locked
		else
			b = to() or last
			last = b
		end
		if not b then
			beamPart.Transparency, dot.Transparency = 1, 1
			return
		end
		local at = b :: Vector3
		local d = at - a
		local len = math.max(0.2, d.Magnitude)
		local w = if lockOn then am.lockWidth else am.width
		beamPart.Size = Vector3.new(w, w, len)
		beamPart.CFrame = CFrame.lookAt(a + d / 2, at)
		dot.CFrame = CFrame.new(at)
		dot.Size = Vector3.one * (if lockOn then am.dot * 1.6 else am.dot)
		local on = not lockOn or CombatFx.reduceFlashing or math.floor(t * am.blink) % 2 == 0
		beamPart.Transparency = if on then (if lockOn then 0 else 0.2) else 0.85
		dot.Transparency = if on then 0 else 0.7
	end))
end

-- You are the one a Sniper aims at: a red edge pulses round the screen, then blinks hard once it locks
-- (steady with reduce flashing on)
local aimEdges: { Frame } = {}
local aimToken = 0
function CombatFx.targeted(time: number, lock: number, on: (() -> boolean)?)
	aimToken += 1
	local token = aimToken
	local t = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		local done = t >= time or token ~= aimToken or (on ~= nil and not on())
		local strength = 0
		if not done then
			if t >= time - lock then
				strength = if CombatFx.reduceFlashing or math.floor(t * R.aim.blink) % 2 == 0
					then 0.55
					else 0.15
			else
				strength = 0.2 + 0.12 * math.sin(t * 8)
			end
		end
		if token == aimToken then
			for _, f in aimEdges do
				f.BackgroundTransparency = 1 - strength
			end
		end
		if done then
			conn:Disconnect()
		end
	end))
end

-- A Captain's rally: a gold shock ring of the rally's radius and a "RALLY!" pop
function CombatFx.rally(center: Vector3, radius: number)
	local color = rgb(R.rally.color)
	local floor = groundBelow(center, 8) + Vector3.new(0, 0.3, 0)
	ring(floor, radius, color, R.rally.life, 0.6)
	ring(floor, radius * 0.5, WHITE, R.rally.life * 0.6, 0.3)
	FxLib.shock(floor, radius, color)
	FxLib.emit("glow", color, center, 1)
	floatText(
		center + Vector3.new(0, 4, 0),
		"RALLY!",
		color,
		Color3.fromRGB(70, 40, 0),
		Enum.Font.Bangers,
		1.6,
		0.9,
		3,
		(math.random() - 0.5) * 10
	)
end

-- A Bomber's grenade: a small spinning ball on a ballistic arc from `from` to `to` in `flight` s, its light
-- blinking faster as it falls, and a red ring where it will land (the grenade's blast radius)
function CombatFx.lob(from: Vector3, to: Vector3, flight: number)
	local lb = R.lob
	local ball = part(Vector3.one * lb.size, CFrame.new(from), Color3.fromRGB(70, 85, 45), Enum.PartType.Ball)
	ball.Material = Enum.Material.Metal
	local blink = part(Vector3.one * lb.size * 0.4, CFrame.new(from), WARN, Enum.PartType.Ball)
	local bomber = Config.Enemies.Bomber
	local radius = if bomber and bomber.grenade then bomber.grenade.radius else 6
	local landing = groundBelow(to, 10) + Vector3.new(0, 0.15, 0)
	local mark = part(
		Vector3.new(0.12, radius * 2, radius * 2),
		CFrame.new(landing) * CFrame.Angles(0, 0, math.rad(90)),
		WARN,
		Enum.PartType.Cylinder
	)
	mark.Material = Enum.Material.SmoothPlastic
	mark.Transparency = 0.6
	local lift = lb.gravity * flight * flight * 0.5
	local t, ph, puff = 0, 0, 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		local k = math.clamp(t / math.max(flight, 0.05), 0, 1)
		local at = from:Lerp(to, k) + Vector3.new(0, lift * k * (1 - k), 0)
		local spin = CFrame.new(at) * CFrame.Angles(t * 12, t * 7, 0)
		ball.CFrame = spin
		blink.CFrame = spin * CFrame.new(0, lb.size * 0.45, 0)
		ph += dt * (lb.blink[1] + (lb.blink[2] - lb.blink[1]) * k)
		blink.Transparency = if ph % 1 < 0.5 then 0 else 0.9
		mark.Transparency = 0.45 + 0.25 * math.sin(t * 14)
		puff += dt
		if puff >= 0.08 then
			puff = 0
			FxLib.emit("smoke", Color3.fromRGB(120, 120, 120), at, 1)
		end
		if k >= 1 then
			conn:Disconnect()
			ball:Destroy()
			blink:Destroy()
			fade(mark, 0.15)
		end
	end))
end

-- Where a grenade burst: a burning patch on the ground (an orange disc with flames and embers) for `time` s
function CombatFx.zone(center: Vector3, radius: number, time: number)
	local zn = R.zone
	local color, core = rgb(zn.color), rgb(zn.core)
	local floor = groundBelow(center, 10) + Vector3.new(0, 0.12, 0)
	local rot = CFrame.new(floor) * CFrame.Angles(0, 0, math.rad(90))
	local disc = part(Vector3.new(0.1, radius * 2, radius * 2), rot, color, Enum.PartType.Cylinder)
	disc.Transparency = 0.45
	local inner = part(Vector3.new(0.12, radius * 1.3, radius * 1.3), rot, core, Enum.PartType.Cylinder)
	inner.Transparency = 0.55
	local each = if QualityController.name == "low" then 1 else 2
	local t, tick = 0, 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		if t >= time then
			conn:Disconnect()
			fade(disc, 0.4)
			fade(inner, 0.3)
			return
		end
		inner.Transparency = 0.45 + 0.2 * math.sin(t * 11) * math.sin(t * 7.3)
		tick += dt
		if tick >= zn.every then
			tick = 0
			local a = math.random() * math.pi * 2
			local r = math.sqrt(math.random()) * radius * 0.85
			local at = floor + Vector3.new(math.cos(a) * r, 0.4, math.sin(a) * r)
			FxLib.emit("flame", color, at, each)
			FxLib.emit("ember", core, at, each)
			if math.random() < 0.25 then
				FxLib.emit("smoke", Color3.fromRGB(60, 55, 50), at + Vector3.new(0, 1.5, 0), 1)
			end
		end
	end))
end

-- A Medic Unit's repair beam: green, from the Medic (`from`) to its patient (`to`), both ends following, with
-- small repair packets running along it for `time` s, or until on() (optional, the Medic's mend bit) says
-- the beam broke (a stun)
function CombatFx.mend(from: () -> Vector3?, to: () -> Vector3?, time: number, on: (() -> boolean)?)
	local md = R.mend
	local color = rgb(md.color)
	local core = part(Vector3.new(md.width, md.width, 1), CFrame.new(), WHITE:Lerp(color, 0.5))
	local glow = part(Vector3.new(md.width * 4, md.width * 4, 1), CFrame.new(), color)
	glow.Transparency = 0.6
	local packets: { { p: Part, t0: number } } = {}
	local t, nextPacket = 0, 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		local a, b = from(), to()
		if not a or not b or t >= time or (on and not on()) then
			conn:Disconnect()
			fade(core, 0.15)
			fade(glow, 0.2)
			for _, pk in packets do
				pk.p:Destroy()
			end
			return
		end
		local d = b - a
		local len = math.max(0.2, d.Magnitude)
		local cf = CFrame.lookAt(a + d / 2, b)
		local wobble = 1 + math.sin(t * 20) * 0.15
		core.Size = Vector3.new(md.width, md.width, len)
		core.CFrame = cf
		glow.Size = Vector3.new(md.width * 4 * wobble, md.width * 4 * wobble, len)
		glow.CFrame = cf
		if t >= nextPacket then
			nextPacket = t + md.packet
			table.insert(
				packets,
				{ p = part(Vector3.one * 0.6, CFrame.new(a), color, Enum.PartType.Ball), t0 = t }
			)
		end
		for i = #packets, 1, -1 do
			local pk = packets[i]
			local k = (t - pk.t0) / 0.4
			if k >= 1 then
				pk.p:Destroy()
				table.remove(packets, i)
				FxLib.emit("wisp", color, b, 2)
			else
				pk.p.CFrame = CFrame.new(a:Lerp(b, k))
			end
		end
	end))
end

-- A Mimic shows itself: a burst of cyan and magenta squares that jump about its body, and a flash
function CombatFx.reveal(pos: Vector3)
	local rv = R.reveal
	local n = DebrisBudget.lease(rv.squares, rv.life)
	local squares = {}
	for k = 1, n do
		local c = rv.colors[(k % #rv.colors) + 1]
		table.insert(squares, part(Vector3.new(0.8, 0.8, 0.05), CFrame.new(pos), rgb(c)))
	end
	local flash = part(Vector3.one * 2, CFrame.new(pos), WHITE, Enum.PartType.Ball)
	fade(flash, 0.15, { Size = Vector3.one * 6 })
	FxLib.emit("crackle", rgb(rv.colors[1]), pos, 2)
	local t, step = 0, 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(FrameProf.wrap("CombatFx", function(dt)
		t += dt
		if t >= rv.life then
			conn:Disconnect()
			for _, p in squares do
				p:Destroy()
			end
			return
		end
		step -= dt
		if step > 0 then
			return
		end
		step = 0.05 -- the squares jump, they do not glide
		local cam = Workspace.CurrentCamera
		local eye = if cam then cam.CFrame.Position else pos + Vector3.new(0, 0, 10)
		for _, p in squares do
			local at = pos
				+ Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 5, (math.random() - 0.5) * 3)
			local s = 0.4 + math.random() * 1.2
			p.Size = Vector3.new(s, s * (0.3 + math.random()), 0.05)
			p.CFrame = CFrame.lookAt(at, eye)
			p.Transparency = math.random() * 0.4 + t / rv.life * 0.5
		end
	end))
end

-- A grenade blast: a fireball of `radius`, flames and smoke, a shock ring and rubble bits (the debris budget)
function CombatFx.boom(center: Vector3, radius: number)
	local bm = R.boom
	local color = rgb(bm.color)
	local floor = groundBelow(center, 10) + Vector3.new(0, 0.3, 0)
	FxLib.burst(center, radius, "Fire", color, true)
	FxLib.dust(floor, radius)
	local ball = part(Vector3.one * 2, CFrame.new(center), color, Enum.PartType.Ball)
	ball.Transparency = 0.15
	fade(ball, 0.35, { Size = Vector3.one * radius * 1.6, Color = Color3.fromRGB(90, 40, 20) })
	local flash = part(Vector3.one * 2, CFrame.new(center), Color3.fromRGB(255, 240, 180), Enum.PartType.Ball)
	fade(flash, 0.15, { Size = Vector3.one * radius })
	ring(floor, radius * 1.1, color, 0.4, 0.6)
	ring(floor, radius * 1.4, Color3.fromRGB(110, 100, 90), 0.55, 0.9)
	local n = DebrisBudget.lease(bm.chunks, 1.2)
	for _ = 1, n do
		local p = part(
			Vector3.new(0.4 + math.random() * 0.5, 0.3 + math.random() * 0.4, 0.4 + math.random() * 0.5),
			CFrame.new(floor + Vector3.new(0, 0.5, 0)),
			Color3.fromRGB(60, 55, 50)
		)
		p.Material = Enum.Material.Slate
		p.Anchored = false
		p.AssemblyLinearVelocity = Vector3.new(
			math.random() - 0.5,
			math.random() * 0.7 + 0.5,
			math.random() - 0.5
		) * 45
		p.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 10
		fade(p, 1.2)
	end
end

-- Enemy defeated: bolts and plates fly, sparks fade in 2 s (spec juice row; machines only, no gore).
-- Shares the device debris budget (DebrisBudget).
function CombatFx.burst(pos: Vector3, style: string, metal: Color3?)
	FxLib.wreck(pos)
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
			end, data.dur or row.channel * (row.tick or 0.25), style, color, row.set)
		else
			CombatFx.bolt(o, data.e or (o + d * row.range), style, color, row.set)
		end
	elseif shape == "chain" then
		CombatFx.chain({ o, data.e or (o + d * row.range) }, style, color, row.set)
	elseif shape == "dash" then
		CombatFx.dash(o, data.e or (o + d * row.range), style, color, row.set)
	elseif shape == "cone" then
		CombatFx.cone(o, d, row.range, row.cone or 40, style, color, row.set)
	elseif shape == "arc" then
		local sword = (row.set == "Blade" or row.sword == true)
		CombatFx.arc(
			o,
			d,
			row.range,
			row.cone or 90,
			style,
			color,
			data.step,
			sword,
			row.id == "RisingBlade",
			row.set
		)
		if row.channel then
			-- a flurry: more slashes over the channel
			local n = row.channel
			for i = 1, n - 1 do
				task.delay(i * (row.tick or 0.15), function()
					CombatFx.arc(
						o,
						d,
						row.range,
						row.cone or 90,
						style,
						color,
						(i % 3) + 1,
						sword,
						false,
						row.set
					)
				end)
			end
		end
	elseif shape == "nova" then
		CombatFx.nova(data.c or o, data.r or row.radius, style, color, big, row.set)
	elseif shape == "line" then
		local width = row.width or 5
		CombatFx.line(
			o,
			data.e or (o + d * row.range),
			width,
			style,
			color,
			row.ground,
			(row.set == "Blade" or row.sword == true),
			row.set
		)
		if data.t then
			CombatFx.line(
				o,
				data.t,
				width,
				style,
				color,
				row.ground,
				(row.set == "Blade" or row.sword == true),
				row.set
			)
		end
		if big then
			CombatFx.nova(data.e or o, width, style, color, true, row.set)
		end
	elseif shape == "ride" then
		CombatFx.ride(row.set, data.caster or function()
			return o
		end, data.dur or row.duration or 4, style, color)
		if data.c and (row.coeff or 0) > 0 then
			CombatFx.nova(data.c, data.r or row.radius or 8, style, color, false, row.set)
		end
	elseif shape == "launch" then
		CombatFx.launch(row, o, style, color)
	elseif shape == "place" then
		if data.c and row.summon then
			local c = data.c
			CombatFx.summon(row.summon, function()
				return c + Vector3.new(0, 3, 0)
			end, data.dur or row.decoy or 5, style, color)
		end
	elseif shape == "field" and row.summon == "mech" then
		CombatFx.nova(o, 10, style, color, true, row.set) -- the mech is the hero's own form (the Form attribute)
	elseif shape == "field" and row.summon then
		local c = data.c or o
		CombatFx.summon(row.summon, data.follow or function()
			return c + Vector3.new(0, 3, 0)
		end, data.dur or row.duration, style, color, data.r or row.radius)
		if row.summon == "mines" then
			CombatFx.field(
				c,
				data.r or row.radius,
				data.dur or row.duration,
				style,
				color,
				false,
				nil,
				false,
				row.set
			)
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
			row.status == "pull" or row.id == "BladeStorm",
			row.set
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
	-- every path's own look (overhaul plan step 6): your own flourish was drawn when you cast
	if data.a ~= Players.LocalPlayer.UserId then
		CombatFx.castFlourish(row, style, o, d, data.a)
	end
	if big then
		CombatFx.superMoment(row, style, data)
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
	CombatFx.nova(center, radius, style, color, row.slot == "super" and mine, row.set)
	if style ~= "Anime" then
		CombatFx.word(center, row.set, color, row.slot == "super")
	end
	if row.slot == "super" then
		-- a landing super's big moment (Titan's Meteor Leap)
		CombatFx.superMoment(
			row,
			style,
			{ o = center, d = Vector3.new(0, -1, 0), c = center, r = radius, a = userId },
			true
		)
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
	-- the Sniper warning: a red edge on all four sides (two frames, side and top-and-bottom)
	for _, rotation in { 0, 90 } do
		local edge = Instance.new("Frame")
		edge.Name = "AimEdge"
		edge.Size = UDim2.fromScale(1, 1)
		edge.BackgroundColor3 = Color3.fromRGB(255, 30, 30)
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		local eg = Instance.new("UIGradient")
		eg.Rotation = rotation
		eg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.12, 1),
			NumberSequenceKeypoint.new(0.88, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		eg.Parent = edge
		edge.Parent = gui
		table.insert(aimEdges, edge)
	end
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
	local slash = Instance.new("Frame")
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Position = UDim2.fromScale(0.5, 0.5)
	slash.Size = UDim2.new(0, 0, 0, 6)
	slash.Rotation = -18
	slash.BorderSizePixel = 0
	slash.BackgroundTransparency = 1
	slash.Parent = gui
	slashFrame = slash
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return CombatFx
