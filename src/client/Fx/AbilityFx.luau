-- AbilityFx: every ability's own look (nate's playtest 2026-11-19: "Need more unique effects"). Each of the
-- 136 powers has a recipe in Config.FxMoves (rules and costs in Shared.FxPlan): its cast flourish (flair), what
-- lands on its hits and at its area (hit), what streams behind what it throws (trail) and, for supers, the
-- caster's screen moment. They draw on top of the path's look (CombatFx's path section) in the path's colours,
-- so two moves of one path never read the same. CombatFx calls in (castFlourish, the path heads and dashes,
-- impacts, novas and areas, super moments) and hands over its drawing kit at init; nothing here runs per frame
-- (tweens and Debris only), and every piece and particle comes out of FxLib's budgets per device preset.
-- Weapon moves have no recipe and are never drawn here.
-- The rune and scorch sheets are uploaded (art/fx/textures.py --moves, Config.Fx.lib.textures); rings (K.disc)
-- are the Blender shockwave ring since 2026-11-20. PLACEHOLDER ART: the other part-built shapes over the library's
-- particle sheets until the VFX pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FxPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FxPlan"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local FxLib = require(script.Parent.FxLib)

local AbilityFx = {}

local M = Config.FxMoves
local L = Config.Fx.lib
local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(34, 28, 26)
local DUST = Color3.fromRGB(170, 155, 135)
local SMOKE = Color3.fromRGB(70, 66, 74)
local FLAT = { rune = true, scorch = true, shock = true }

-- CombatFx's drawing kit (part, fade, beam, disc, crossBars, facing, fly, flightTime, flashScreen,
-- groundBelow, PIECE), set by init
local K: any = nil
local gui: ScreenGui? = nil
local bars: { Frame } = {}
local edges: { Frame } = {}
local lines: { Frame } = {}
local slashLine: Frame? = nil

-- One draw: the style, colours, size, and how many of the recipe's pieces the budget gives it now
type X = {
	style: string,
	an: boolean,
	color: Color3,
	accent: Color3,
	s: number,
	n: number,
	scale: number,
}

local function share(): number
	return L.scale[QualityController.name] or L.scale.medium
end

-- the row's particles at pos, each kind scaled by the preset (FxPlan.count, the same as the budget tests)
local function emitAll(fx: { [string]: number }, x: X, pos: Vector3, dir: Vector3?, radius: number?)
	local sh = share()
	for kind, base in fx do
		local n = FxPlan.count(base, sh, x.scale)
		if kind == "shock" then
			FxLib.shock(pos, radius or 6 * x.s, x.accent)
		elseif FLAT[kind] then
			FxLib.emit(kind, if kind == "scorch" then DARK else x.color, pos + Vector3.new(0, 0.15, 0), n, UP)
		elseif kind == "dust" or kind == "rock" then
			FxLib.emit(kind, DUST, pos, n, dir)
		elseif kind == "smoke" then
			FxLib.emit(kind, SMOKE, pos, n, dir)
		else
			FxLib.emit(kind, if x.an and kind ~= "glow" then x.accent else x.color, pos, n, dir)
		end
	end
end

local function basis(d: Vector3): (Vector3, Vector3)
	local right = d:Cross(UP)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
	return right, right:Cross(d).Unit
end

local function tone(x: X, i: number): Color3
	-- Anime mixes in white; Comic keeps the path's colour with its accent
	if x.an then
		return if i % 2 == 0 then WHITE else x.color
	end
	return if i % 2 == 0 then x.accent else x.color
end

local function grow(p: BasePart, size: Vector3, time: number)
	TweenService
		:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = size })
		:Play()
end

---------------------------------------------------------------------------
-- Trails: what streams behind what flies (from -> to)
---------------------------------------------------------------------------

local TRAIL: { [string]: (Vector3, Vector3, X) -> () } = {}
TRAIL.none = function() end
TRAIL.ribbon = function(from, to, x) -- a thin bright ribbon in the accent colour
	K.beam(from, to, if x.an then 0.12 * x.s else 0.28 * x.s, x.accent, 0.3)
end
TRAIL.spiral = function(from, to, x) -- beads spiral around the flight
	local d = (to - from).Unit
	local right, up = basis(d)
	for i = 1, x.n do
		local t = i / (x.n + 1)
		local a = t * math.pi * 4
		local at = from:Lerp(to, t) + (right * math.cos(a) + up * math.sin(a)) * 1.2 * x.s
		local b = K.part(Vector3.one * 0.6 * x.s, CFrame.new(at), tone(x, i), Enum.PartType.Ball)
		K.fade(b, 0.35, { Size = Vector3.one * 0.1 }, t * 0.15)
	end
end
TRAIL.beads = function(from, to, x) -- a dotted line of beads that pop
	for i = 1, x.n do
		local t = i / (x.n + 1)
		local b =
			K.part(Vector3.one * 0.5 * x.s, CFrame.new(from:Lerp(to, t)), tone(x, i), Enum.PartType.Ball)
		K.fade(b, 0.25, { Size = Vector3.one * 1.6 * x.s }, t * 0.2)
	end
end
TRAIL.zigzag = function(from, to, x) -- a jagged bolt beside the flight
	local d = (to - from).Unit
	local right, up = basis(d)
	local prev = from
	for i = 1, x.n do
		local t = i / x.n
		local j = if i == x.n then 0 else (if i % 2 == 0 then 1 else -1) * 1.2 * x.s
		local at = from:Lerp(to, t) + right * j + up * j * 0.4
		K.beam(prev, at, if x.an then 0.08 else 0.18 * x.s, if x.an then WHITE else x.accent, 0.18)
		prev = at
	end
end
TRAIL.twin = function(from, to, x) -- two thin lines either side
	local d = (to - from).Unit
	local right = basis(d)
	for k, sgn in { -1, 1 } do
		local off = right * sgn * 0.8 * x.s
		K.beam(from + off, to + off, if x.an then 0.08 else 0.16 * x.s, tone(x, k), 0.25)
	end
end
TRAIL.comet = function(from, to, x) -- a fat comet tail
	local p = K.part(Vector3.new(0.9, 0.9, 4) * x.s, CFrame.new(from), x.accent, Enum.PartType.Ball)
	p.Transparency = 0.3
	K.fly(p, from, to, K.flightTime(from, to, 200))
end
TRAIL.wake = function(from, to, x) -- rings standing across the flight
	local d = (to - from).Unit
	for i = 1, x.n do
		local t = i / (x.n + 1)
		task.delay(t * 0.15, function()
			K.disc(from:Lerp(to, t), d, 1.6 * x.s, tone(x, i), 0.3, 0.12)
		end)
	end
end
TRAIL.sparkle = function() end -- particles only (the trail's fx)
TRAIL.smoke = function() end

---------------------------------------------------------------------------
-- Hits: what lands on every hit and at the move's area (pos; dir from the hit into the target)
---------------------------------------------------------------------------

local HIT: { [string]: (Vector3, X, Vector3?) -> () } = {}
HIT.none = function() end
HIT.ring = function(pos, x) -- a flat shockwave ring
	K.disc(K.groundBelow(pos, 6) + Vector3.new(0, 0.2, 0), UP, 4 * x.s, x.accent, 0.3, 0.15)
end
HIT.crater = function(pos, x) -- a scorched crater with chips thrown up
	local g = K.groundBelow(pos, 10)
	local c = K.part(
		Vector3.new(0.2, 1, 1),
		CFrame.new(g + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		DARK,
		Enum.PartType.Cylinder
	)
	c.Material = Enum.Material.Slate
	grow(c, Vector3.new(0.2, 6 * x.s, 6 * x.s), 0.12)
	K.fade(c, 1.2, nil, 0.6)
	for i = 2, x.n do
		local a = i / x.n * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = K.PIECE.rock(0.7 * x.s, x.color)
		r.CFrame = CFrame.new(g + out)
		K.fade(r, 0.45, {
			CFrame = CFrame.new(g + out * 4 * x.s + Vector3.new(0, 2.5, 0)) * CFrame.Angles(a, a * 2, 0),
			Size = r.Size * 0.4,
		})
	end
end
HIT.sparks = function(pos, x) -- a spark spray and a glint
	K.crossBars(
		K.facing(pos),
		3.5 * x.s,
		if x.an then 0.1 else 0.28,
		if x.an then WHITE else x.accent,
		0.15,
		30
	)
end
HIT.shards = function(pos, x) -- glassy shards burst out
	for i = 1, x.n do
		local d = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		d = if d.Magnitude > 0.05 then d.Unit else UP
		local sh = K.PIECE.shard(0.9 * x.s, tone(x, i))
		sh.CFrame = CFrame.lookAt(pos, pos + d)
		K.fade(
			sh,
			0.35,
			{ CFrame = CFrame.lookAt(pos + d * 6 * x.s, pos + d * 7 * x.s), Size = sh.Size * 0.3 }
		)
	end
end
HIT.splash = function(pos, x) -- a crown of drops
	for i = 1, x.n do
		local a = i / x.n * math.pi * 2
		local dr = K.PIECE.drop(0.7 * x.s, if i % 2 == 0 then x.accent else x.color)
		dr.CFrame = CFrame.new(pos)
		K.fade(dr, 0.4, {
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 3, 4, math.sin(a) * 3) * x.s),
			Size = dr.Size * 0.5,
		})
	end
end
HIT.pillar = function(pos, x) -- a pillar of light shoots up
	local h = 12 * x.s
	local w = 1.8 * x.s
	local g = K.groundBelow(pos, 8)
	local p = K.part(
		Vector3.new(h, w, w),
		CFrame.new(g + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		if x.an then WHITE else x.accent,
		Enum.PartType.Cylinder
	)
	p.Transparency = 0.3
	K.fade(p, 0.4, { Size = Vector3.new(h * 1.3, 0.2, 0.2) })
end
HIT.starburst = function(pos, x) -- spikes burst out in a star, face-on
	local cf = K.facing(pos)
	for i = 1, x.n do
		local a = i / x.n * math.pi * 2
		local w = if x.an then 0.12 else 0.3 * x.s
		local b =
			K.part(Vector3.new(w, 0.5, w), cf * CFrame.Angles(0, 0, a) * CFrame.new(0, 0.5, 0), tone(x, i))
		local len = 4 * x.s
		K.fade(b, 0.25, {
			Size = Vector3.new(w * 0.4, len, w * 0.4),
			CFrame = cf * CFrame.Angles(0, 0, a) * CFrame.new(0, len * 0.7, 0),
		})
	end
end
HIT.petals = function(pos, x) -- flat petals spin outward
	for i = 1, x.n do
		local a = i / x.n * math.pi * 2
		local pl = K.PIECE.plate(1.1 * x.s, tone(x, i))
		pl.CFrame = CFrame.new(pos) * CFrame.Angles(0, a, 0)
		local to = pos + Vector3.new(math.cos(a), 0.3, math.sin(a)) * 5 * x.s
		K.fade(pl, 0.45, { CFrame = CFrame.new(to) * CFrame.Angles(0.6, a + 2.5, 0.4), Size = pl.Size * 0.5 })
	end
end
HIT.spiral = function() end -- particles only (a vortex sucks in)
HIT.cross = function(pos, x) -- an X cut
	K.crossBars(
		K.facing(pos),
		6 * x.s,
		if x.an then 0.12 else 0.35,
		if x.an then WHITE else x.accent,
		0.22,
		45
	)
end
HIT.bloom = function(pos, x) -- a sphere blooms and fades
	local b = K.part(Vector3.one * x.s, CFrame.new(pos), x.accent, Enum.PartType.Ball)
	b.Transparency = 0.4
	K.fade(b, 0.3, { Size = Vector3.one * 6 * x.s })
end
HIT.shatter = function(pos, x) -- cubes shatter and fall
	for i = 1, x.n do
		local c = K.part(Vector3.one * 0.6 * x.s, CFrame.new(pos), tone(x, i))
		c.Material = Enum.Material.Glass
		c.Transparency = 0.2
		local out = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 6 * x.s
		K.fade(c, 0.5, {
			CFrame = CFrame.new(pos + out - Vector3.new(0, 4, 0))
				* CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Size = c.Size * 0.5,
		})
	end
end
HIT.bubble = function(pos, x) -- a bubble wraps the target and pops
	local b = K.part(Vector3.one * 4 * x.s, CFrame.new(pos), x.accent, Enum.PartType.Ball)
	b.Material = Enum.Material.Glass
	b.Transparency = 0.55
	grow(b, Vector3.one * 5 * x.s, 0.25)
	K.fade(b, 0.1, { Size = Vector3.one * 6.5 * x.s }, 0.3)
end
HIT.rays = function(pos, x) -- rays fan up out of the hit
	local cf = K.facing(pos)
	for i = 1, x.n do
		local a = (i / (x.n + 1) - 0.5) * 1.6
		local d = (cf * CFrame.Angles(0, 0, a)).UpVector
		K.beam(pos, pos + d * 8 * x.s, if x.an then 0.1 else 0.22 * x.s, tone(x, i), 0.35)
	end
end
HIT.cage = function(pos, x) -- bars rise around the target
	local g = K.groundBelow(pos, 8)
	for i = 1, x.n do
		local a = i / x.n * math.pi * 2
		local at = g + Vector3.new(math.cos(a), 0, math.sin(a)) * 2.5 * x.s
		local b = K.part(Vector3.new(0.25, 0.5, 0.25) * x.s, CFrame.new(at), tone(x, i))
		local h = 6 * x.s
		TweenService:Create(b, TweenInfo.new(0.12), {
			Size = Vector3.new(0.25 * x.s, h, 0.25 * x.s),
			CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0)),
		}):Play()
		K.fade(b, 0.4, nil, 0.4)
	end
end
HIT.rune = function(pos, x) -- a rune circle under the target
	K.disc(K.groundBelow(pos, 8) + Vector3.new(0, 0.1, 0), UP, 3.5 * x.s, x.accent, 0.5, 0.08)
end

---------------------------------------------------------------------------
-- Flairs: the cast flourish on the caster (o the chest, feet under it, d the aim)
---------------------------------------------------------------------------

local FLAIR: { [string]: (Vector3, Vector3, Vector3, X) -> () } = {}
FLAIR.none = function() end
FLAIR.sigil = function(_o, feet, _d, x) -- a rune circle at the feet
	K.disc(feet + Vector3.new(0, 0.1, 0), UP, 4 * x.s, x.accent, 0.5, 0.08)
end
FLAIR.crack = function(_o, feet, _d, x) -- cracks run out from the feet
	for i = 1, x.n do
		local a = i / x.n * math.pi * 2 + math.random() * 0.4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local c = K.part(
			Vector3.new(0.3, 0.12, 0.5),
			CFrame.lookAt(feet + dir * 0.3, feet + dir),
			if x.an then x.accent else DARK
		)
		c.Material = Enum.Material.SmoothPlastic
		TweenService:Create(c, TweenInfo.new(0.1), {
			Size = Vector3.new(0.3, 0.12, 4 * x.s),
			CFrame = CFrame.lookAt(feet + dir * 2.2 * x.s, feet + dir * 4 * x.s),
		}):Play()
		K.fade(c, 0.4, nil, 0.15)
	end
end
FLAIR.burst = function(o, _feet, _d, x) -- an aura burst at the chest
	local b = K.part(Vector3.one * 1.5 * x.s, CFrame.new(o), x.accent, Enum.PartType.Ball)
	b.Transparency = 0.5
	K.fade(b, 0.25, { Size = Vector3.one * 7 * x.s })
end
FLAIR.spin = function(o, _feet, _d, x) -- two rings spin around the body
	for k, tilt in { 0.35, -0.35 } do
		local r = K.part(
			Vector3.new(0.12, 5 * x.s, 5 * x.s),
			CFrame.new(o) * CFrame.Angles(tilt, 0, math.rad(90)),
			tone(x, k),
			Enum.PartType.Cylinder
		)
		r.Transparency = 0.2
		K.fade(r, 0.45, {
			CFrame = CFrame.new(o)
				* CFrame.Angles(tilt, math.rad(170) * (if k == 1 then 1 else -1), math.rad(90)),
			Size = Vector3.new(0.05, 6.5 * x.s, 6.5 * x.s),
		})
	end
end
FLAIR.pillar = function(_o, feet, _d, x) -- a column of light up the body
	local h = 12 * x.s
	local p = K.part(
		Vector3.new(h, 2.5 * x.s, 2.5 * x.s),
		CFrame.new(feet + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		x.accent,
		Enum.PartType.Cylinder
	)
	p.Transparency = 0.45
	K.fade(p, 0.45, { Size = Vector3.new(h * 1.2, 0.3, 0.3) })
end
FLAIR.fan = function(o, _feet, d, x) -- lines fan out ahead
	local hand = o + d * 1.5
	local _, up = basis(d)
	for i = 1, x.n do
		local a = (i / (x.n + 1) - 0.5) * 1.2
		local dir = (CFrame.fromAxisAngle(up, a) * d).Unit
		K.beam(hand, hand + dir * 6 * x.s, if x.an then 0.08 else 0.2 * x.s, tone(x, i), 0.22)
	end
end
FLAIR.orbs = function(o, _feet, d, x) -- orbs pop out round the hand and fly ahead
	local hand = o + d * 1.5
	local right, up = basis(d)
	for i = 1, x.n do
		local a = i / x.n * math.pi * 2
		local at = hand + (right * math.cos(a) + up * math.sin(a)) * 1.5 * x.s
		local b = K.part(Vector3.one * 0.7 * x.s, CFrame.new(at), tone(x, i), Enum.PartType.Ball)
		K.fade(b, 0.3, { CFrame = CFrame.new(at + d * 6 * x.s), Size = Vector3.one * 0.2 }, i * 0.03)
	end
end
FLAIR.vent = function() end -- particles only (smoke and dust at the feet)
FLAIR.halo = function(o, _feet, _d, x) -- a halo over the head that widens and turns
	local top = o + Vector3.new(0, 3, 0)
	local h = K.part(
		Vector3.new(0.15, 2.6 * x.s, 2.6 * x.s),
		CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90)),
		x.accent,
		Enum.PartType.Cylinder
	)
	h.Transparency = 0.1
	K.fade(h, 0.55, {
		Size = Vector3.new(0.05, 4 * x.s, 4 * x.s),
		CFrame = CFrame.new(top + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
end
FLAIR.flash = function(o, _feet, d, x) -- a quick flash at the hand
	local b = K.part(
		Vector3.one * x.s,
		CFrame.new(o + d * 1.5),
		if x.an then WHITE else x.accent,
		Enum.PartType.Ball
	)
	K.fade(b, 0.12, { Size = Vector3.one * 3 * x.s })
end
FLAIR.wings = function(o, _feet, d, x) -- two wings of light open behind
	local f = Vector3.new(d.X, 0, d.Z)
	f = if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
	local base = CFrame.lookAt(o - f * 0.8, o - f * 0.8 + f)
	for k, sgn in { -1, 1 } do
		local w = K.part(
			Vector3.new(3.5 * x.s, 0.15, 1.6 * x.s),
			base * CFrame.Angles(0, 0, sgn * 0.2) * CFrame.new(sgn * 1.8 * x.s, 0.6, 0),
			tone(x, k)
		)
		w.Transparency = 0.4
		K.fade(w, 0.45, {
			CFrame = base * CFrame.Angles(0, 0, sgn * 0.9) * CFrame.new(sgn * 2.6 * x.s, 1.2, 0.4),
		})
	end
end
FLAIR.lines = function(o, _feet, d, x) -- lines rush in to the hand
	local hand = o + d * 1.5
	for i = 1, x.n do
		local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		v = if v.Magnitude > 0.05 then v.Unit else UP
		local from = hand + v * 6 * x.s
		local b = K.part(Vector3.new(0.12, 0.12, 2.5) * x.s, CFrame.lookAt(from, hand), tone(x, i))
		K.fade(b, 0.2, { CFrame = CFrame.lookAt(hand + v, hand), Size = Vector3.new(0.05, 0.05, 0.5) })
	end
end
FLAIR.rune = function(o, _feet, d, x) -- a glyph circle stands before the hand
	K.disc(o + d * 1.5, d, 2.5 * x.s, x.accent, 0.4, 0.1)
end
FLAIR.dust = function() end -- particles only (dust and pebbles kick up)

---------------------------------------------------------------------------
-- Screens: a super's moment on the caster's screen (pooled frames, made once)
---------------------------------------------------------------------------

local S = M.kit.screen
local SCREEN: { [string]: (Color3, string, number?) -> () } = {}
SCREEN.none = function() end
SCREEN.flash = function(tint) -- a bright flash in the path's tint
	K.flashScreen(tint, 0.35, 0.5)
end
SCREEN.bars = function() -- cinema bars slide in and out
	for i, b in bars do
		b.Size = UDim2.fromScale(1, 0)
		b.BackgroundTransparency = 0
		local tw = TweenService:Create(b, TweenInfo.new(0.15), { Size = UDim2.fromScale(1, 0.11) })
		tw:Play()
		task.delay(S.bars, function()
			TweenService:Create(b, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 0) }):Play()
		end)
		b.AnchorPoint = Vector2.new(0, if i == 1 then 0 else 1)
		b.Position = UDim2.fromScale(0, if i == 1 then 0 else 1)
	end
end
SCREEN.vignette = function(tint) -- the screen's edges glow in the path's tint
	for _, e in edges do
		e.BackgroundColor3 = tint
		e.BackgroundTransparency = 1
		TweenService:Create(e, TweenInfo.new(0.12), { BackgroundTransparency = 0.25 }):Play()
		task.delay(0.15, function()
			TweenService:Create(e, TweenInfo.new(S.vignette), { BackgroundTransparency = 1 }):Play()
		end)
	end
end
SCREEN.lines = function(tint, style) -- speed lines rush out from the middle
	for i, l in lines do
		local a = (i - 1) / #lines * math.pi * 2
		local c, s = math.cos(a), math.sin(a)
		l.BackgroundColor3 = if style == "Anime" or i % 2 == 0 then Color3.new(1, 1, 1) else tint
		l.Rotation = math.deg(a)
		l.Position = UDim2.fromScale(0.5 + c * 0.22, 0.5 + s * 0.3)
		l.BackgroundTransparency = 0.1
		TweenService:Create(l, TweenInfo.new(S.lines, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5 + c * 0.6, 0.5 + s * 0.7),
			BackgroundTransparency = 1,
		}):Play()
	end
end
SCREEN.slash = function(tint) -- one cut across the screen
	local l = slashLine
	if not l then
		return
	end
	l.BackgroundColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.6)
	l.Size = UDim2.new(0, 0, 0, 5)
	l.BackgroundTransparency = 0
	TweenService:Create(l, TweenInfo.new(0.12), { Size = UDim2.new(1.5, 0, 0, 5) }):Play()
	task.delay(0.12, function()
		TweenService
			:Create(l, TweenInfo.new(S.slash), { BackgroundTransparency = 1, Size = UDim2.new(1.5, 0, 0, 1) })
			:Play()
	end)
end
SCREEN.invert = function(tint) -- the light goes out, then comes back in the path's tint
	K.flashScreen(Color3.new(0, 0, 0), 0.25, 0.65)
	task.delay(0.2, function()
		K.flashScreen(tint, 0.3, 0.4)
	end)
end
-- item 173: Bullet Time's own screen (a skill, the caster only) for its whole field: the world drains to a warm
-- sepia with a hard edge, the edges hold the path's tint, a quick white flash on the way in, back on the way out
local slowCC: ColorCorrectionEffect? = nil
local slowUntil = 0
SCREEN.slowmo = function(tint, _style, hold)
	local h = hold or 2
	slowUntil = os.clock() + h
	local cc = slowCC
	if not cc then
		local made = Instance.new("ColorCorrectionEffect")
		made.Name = "BulletTimeScreen"
		made.Enabled = true
		made.Parent = game:GetService("Lighting")
		slowCC = made
		cc = made
	end
	local c = cc :: ColorCorrectionEffect
	K.flashScreen(Color3.new(1, 1, 1), 0.12, 0.45)
	TweenService:Create(c, TweenInfo.new(0.15), {
		Saturation = -0.65,
		Contrast = 0.2,
		TintColor = Color3.fromRGB(255, 232, 196),
	}):Play()
	for _, e in edges do
		e.BackgroundColor3 = tint
		TweenService:Create(e, TweenInfo.new(0.15), { BackgroundTransparency = 0.45 }):Play()
	end
	task.delay(h, function()
		if os.clock() < slowUntil - 0.05 then
			return -- cast again meanwhile: the later one ends it
		end
		TweenService:Create(c, TweenInfo.new(0.3), {
			Saturation = 0,
			Contrast = 0,
			TintColor = Color3.new(1, 1, 1),
		}):Play()
		for _, e in edges do
			TweenService:Create(e, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		end
	end)
end
SCREEN.pulse = function(tint) -- three quick pulses
	for k = 0, 2 do
		task.delay(k * S.pulse, function()
			K.flashScreen(tint, S.pulse, 0.35 - k * 0.08)
		end)
	end
end

---------------------------------------------------------------------------
-- Entry points (CombatFx)
---------------------------------------------------------------------------

-- an ability's recipe (nil for weapon moves and anything without one)
function AbilityFx.recipe(row: any): any?
	if not row or row.set == "Weapon" then
		return nil
	end
	return FxPlan.recipeOf(M, row.id)
end

local function make(
	kind: string,
	name: string,
	row: any,
	rec: any,
	style: string,
	color: Color3,
	accent: Color3,
	mine: boolean,
	size: number?
): X
	local scale = (if row.slot == "basic" then M.kit.basicScale else 1)
		* (if mine then 1 else M.kit.othersScale)
	local parts = M.kit[kind][name].parts
	return {
		style = style,
		an = style == "Anime",
		color = color,
		accent = accent,
		s = FxPlan.recipeSize(M, rec, row.slot) * (size or 1) * (if style == "Anime" then 0.85 else 1),
		n = if parts > 0 then FxLib.pieces(parts, scale) else 0,
		scale = scale,
	}
end

local function mineOf(userId: number?): boolean
	return userId ~= nil and userId == Players.LocalPlayer.UserId
end

-- the cast flourish (o the chest, d the aim); moves with no hits of their own (buffs, walls, rides...) also
-- pop their hit on the caster so they still land a look
local SELF_HIT = { buff = true, wall = true, ramp = true, ride = true, launch = true, place = true }
function AbilityFx.flair(
	row: any,
	style: string,
	o: Vector3,
	d: Vector3,
	color: Color3,
	accent: Color3,
	userId: number?
)
	local rec = AbilityFx.recipe(row)
	if not K or not rec then
		return
	end
	local mine = mineOf(userId)
	local feet = o - Vector3.new(0, 3.2, 0)
	local name = rec.flair or "none"
	local x = make("flair", name, row, rec, style, color, accent, mine)
	if x.n > 0 or M.kit.flair[name].parts == 0 then -- the pieces budget may be spent: then particles only
		FLAIR[name](o, feet, d, x)
	end
	emitAll(
		M.kit.flair[name].fx,
		x,
		if name == "vent" or name == "dust" or name == "sigil" then feet else o,
		d
	)
	if SELF_HIT[row.shape] then
		AbilityFx.hit(
			row,
			style,
			if row.shape == "buff" then o else feet + Vector3.new(0, 1, 0),
			color,
			accent,
			mine
		)
	end
end

-- what streams behind a flying head, a dash or a leap
function AbilityFx.travel(
	row: any,
	style: string,
	from: Vector3,
	to: Vector3,
	color: Color3,
	accent: Color3,
	mine: boolean
)
	local rec = AbilityFx.recipe(row)
	if not K or not rec or (to - from).Magnitude < 2 then
		return
	end
	local name = rec.trail or "none"
	local x = make("trail", name, row, rec, style, color, accent, mine)
	if x.n > 0 or M.kit.trail[name].parts == 0 then
		TRAIL[name](from, to, x)
	end
	local fx = M.kit.trail[name].fx
	if next(fx) then
		local d = (to - from).Unit
		for k = 1, M.kit.trailPoints do
			emitAll(fx, x, from:Lerp(to, k / (M.kit.trailPoints + 1)), d)
		end
	end
end

-- a hit landing (or the move's area: size grows with its radius)
function AbilityFx.hit(
	row: any,
	style: string,
	pos: Vector3,
	color: Color3,
	accent: Color3,
	mine: boolean,
	dir: Vector3?,
	size: number?
)
	local rec = AbilityFx.recipe(row)
	if not K or not rec then
		return
	end
	local name = rec.hit or "none"
	local x = make("hit", name, row, rec, style, color, accent, mine, size)
	if x.n > 0 or M.kit.hit[name].parts == 0 then
		HIT[name](pos, x, dir)
	end
	emitAll(M.kit.hit[name].fx, x, pos, dir, 6 * x.s)
end

-- a super's screen moment (the caster only; a skill with its own screen, Bullet Time, too: CombatFx.castFlourish)
function AbilityFx.screen(row: any, style: string, tint: Color3)
	local rec = AbilityFx.recipe(row)
	if not K or not rec or not gui then
		return
	end
	SCREEN[rec.screen or "none"](tint, style, row.duration)
end

-- the head this move throws instead of its path's (nil keeps the path's)
function AbilityFx.headOf(row: any): string?
	local rec = AbilityFx.recipe(row)
	return rec and rec.head
end
function AbilityFx.markOf(row: any): string?
	local rec = AbilityFx.recipe(row)
	return rec and rec.mark
end
function AbilityFx.castOf(row: any): string?
	local rec = AbilityFx.recipe(row)
	return rec and rec.cast
end

-- the names each table draws (tests read the source for "TRAIL.<name> = function" and so on)
AbilityFx.TRAIL = TRAIL
AbilityFx.HIT = HIT
AbilityFx.FLAIR = FLAIR
AbilityFx.SCREEN = SCREEN

function AbilityFx.init(kit: any)
	K = kit
	local g = Instance.new("ScreenGui")
	g.Name = "AbilityFx"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = -1
	for _ = 1, 2 do
		local b = Instance.new("Frame")
		b.BackgroundColor3 = Color3.new(0, 0, 0)
		b.BorderSizePixel = 0
		b.Size = UDim2.fromScale(1, 0)
		b.Parent = g
		table.insert(bars, b)
	end
	for _, rotation in { 0, 90 } do
		local e = Instance.new("Frame")
		e.Size = UDim2.fromScale(1, 1)
		e.BackgroundTransparency = 1
		e.BorderSizePixel = 0
		local eg = Instance.new("UIGradient")
		eg.Rotation = rotation
		eg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.18, 1),
			NumberSequenceKeypoint.new(0.82, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		eg.Parent = e
		e.Parent = g
		table.insert(edges, e)
	end
	for _ = 1, 14 do
		local l = Instance.new("Frame")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Size = UDim2.new(0.18, 0, 0, 3)
		l.BorderSizePixel = 0
		l.BackgroundTransparency = 1
		l.Parent = g
		table.insert(lines, l)
	end
	local sl = Instance.new("Frame")
	sl.AnchorPoint = Vector2.new(0.5, 0.5)
	sl.Position = UDim2.fromScale(0.5, 0.45)
	sl.Rotation = 24
	sl.BorderSizePixel = 0
	sl.BackgroundTransparency = 1
	sl.Size = UDim2.new(0, 0, 0, 5)
	sl.Parent = g
	slashLine = sl
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
end

return AbilityFx
