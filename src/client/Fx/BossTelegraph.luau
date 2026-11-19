--!strict
-- BossTelegraph: the world bosses' attack warnings as comic telegraphs (the boss pass, 2026-11-19; were flat red
-- discs). The shapes and times are exactly BossSim's (Boss.Attack warn): a ring round the boss, a cone in front,
-- circles at heroes, lines at heroes and the pull. Each one:
-- * a faint floor tint over the whole danger area and a fill that grows to its edge, reaching it exactly at the hit
--   (the fill's size is set from the clock every frame, never tweened, so a slow frame never runs it late);
-- * a dashed hazard-tape edge (warning red and cream in turn) that glows and pulses faster as the hit nears; the
--   dashes, the chevrons and the filling show the danger by shape and motion as well as colour (colourblind-safe);
-- * ground cracks spreading from a stomp's centre (struct attacks and the slams), chevrons pointing out along a beam
--   lane, and chevrons crawling in toward the centre of a pull;
-- * effects library particles: dust kicked up at the edge as it appears, embers rising off it near the hit, a
--   shockwave ring, dust and a scorch at the strike, and the cracks linger and fade (FxLib budgets per preset).
-- Reduce flashing: no pulsing and no last-moment brightening (steady edges); FxLib already skips its bright kinds.
-- Cheap: dash and wedge counts scale with the device preset (QualityController); one list stepped from WorldFx's
-- profiled frame loop.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CombatFx = require(script.Parent.CombatFx)
local FxLib = require(script.Parent.FxLib)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local BossTelegraph = {}

local WARN = Color3.fromRGB(255, 70, 60)
local TINT = Color3.fromRGB(120, 16, 16)
local TAPE = Color3.fromRGB(255, 236, 200)
local HOT = Color3.fromRGB(255, 226, 120)
local CRACK = Color3.fromRGB(34, 26, 22)
local UP = Vector3.new(0, 1, 0)
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis turned up: a flat disc

type Tele = {
	start: number,
	dur: number,
	update: (f: number, now: number) -> (),
	parts: { BasePart },
	done: boolean,
}
local active: { Tele } = {}
local folder: Instance? = nil

local function scale(): number
	local q = QualityController.name
	return if q == "low" then 0.5 elseif q == "medium" then 0.75 else 1
end

local function flashy(): boolean
	return not (CombatFx.reduceFlashing or FxLib.reduceFlashing)
end

local function part(size: Vector3, cf: CFrame, color: Color3, neon: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function disc(c: Vector3, r: number, color: Color3, lift: number, transp: number): Part
	local p = part(
		Vector3.new(0.1, r * 2, r * 2),
		CFrame.new(c + UP * lift) * FLAT,
		color,
		false,
		Enum.PartType.Cylinder
	)
	p.Transparency = transp
	return p
end

-- Dashed hazard tape round a circle (or an arc: a0..a1 in radians, 0 along +x, turning toward +z)
local function dashes(
	list: { BasePart },
	c: Vector3,
	r: number,
	n: number,
	a0: number,
	a1: number,
	width: number
): { BasePart }
	local out = {}
	local step = (a1 - a0) / n
	local len = math.max(0.6, 2 * r * math.sin(math.abs(step) / 2) * 0.62)
	for i = 0, n - 1 do
		local a = a0 + (i + 0.5) * step
		local pos = c + Vector3.new(math.cos(a), 0, math.sin(a)) * r + UP * 0.32
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local d = part(
			Vector3.new(width, 0.25, len),
			CFrame.lookAt(pos, pos + tangent),
			if i % 2 == 0 then WARN else TAPE,
			true
		)
		table.insert(out, d)
		table.insert(list, d)
	end
	return out
end

-- Dashes along a straight edge from a to b
local function dashLine(
	list: { BasePart },
	a: Vector3,
	b: Vector3,
	every: number,
	width: number
): { BasePart }
	local out = {}
	local d = b - a
	local len = d.Magnitude
	if len < 1 then
		return out
	end
	local n = math.max(2, math.floor(len / every))
	local seg = len / n
	for i = 0, n - 1 do
		local mid = a + d.Unit * (seg * (i + 0.5)) + UP * 0.32
		local p = part(
			Vector3.new(width, 0.25, seg * 0.62),
			CFrame.lookAt(mid, mid + d.Unit),
			if i % 2 == 0 then WARN else TAPE,
			true
		)
		table.insert(out, p)
		table.insert(list, p)
	end
	return out
end

-- A chevron (two short bars in a V) at pos pointing along dir
local function chevron(list: { BasePart }, pos: Vector3, dir: Vector3, size: number): { BasePart }
	local out = {}
	local f = Vector3.new(dir.X, 0, dir.Z).Unit
	for _, s in { -1, 1 } do
		local a = math.rad(s * 40)
		-- each arm runs back from the tip at pos
		local arm = (CFrame.fromAxisAngle(UP, a) * CFrame.lookAt(Vector3.zero, -f)).LookVector
		local mid = pos + arm * size * 0.5 + UP * 0.34
		local p = part(Vector3.new(size * 0.22, 0.25, size), CFrame.lookAt(mid, mid + arm), TAPE, true)
		table.insert(out, p)
		table.insert(list, p)
	end
	return out
end

-- The edge's glow: brighter and pulsing faster as the hit nears (steady with Reduce flashing)
local function pulse(edge: { BasePart }, f: number, now: number)
	local t = 0.15
	if flashy() then
		local rate = 2 + f * 8
		t = 0.05 + 0.35 * (0.5 + 0.5 * math.sin(now * rate * math.pi * 2))
	end
	for _, p in edge do
		p.Transparency = t
	end
end

local function fillColor(fill: BasePart, f: number)
	-- the last fifth of the warning: the fill heats toward gold (Reduce flashing keeps one colour)
	fill.Color = if flashy() and f > 0.8 then WARN:Lerp(HOT, (f - 0.8) / 0.2) else WARN
end

-- Cracks spreading from a centre: jagged lines of a few segments each, growing to reach * f
local function cracks(
	list: { BasePart },
	c: Vector3,
	reach: number,
	count: number,
	seed: number
): (f: number) -> ()
	local lines = {}
	local rng = Random.new(seed)
	for i = 1, count do
		local a = (i - 1) / count * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local pts = { c + UP * 0.36 }
		local nseg = 3
		for _ = 1, nseg do
			local aa = a + rng:NextNumber(-0.45, 0.45)
			local stepLen = reach / nseg * rng:NextNumber(0.8, 1.15)
			table.insert(pts, pts[#pts] + Vector3.new(math.cos(aa), 0, math.sin(aa)) * stepLen)
		end
		local segs = {}
		for k = 1, nseg do
			local p = part(Vector3.new(0.9 - k * 0.2, 0.22, 0.1), CFrame.new(pts[k]), CRACK, false)
			table.insert(segs, p)
			table.insert(list, p)
		end
		table.insert(lines, { pts = pts, segs = segs })
	end
	return function(f: number)
		for _, line in lines do
			local total = f * #line.segs
			for k, p in line.segs do
				local g = math.clamp(total - (k - 1), 0, 1)
				local a, b = line.pts[k], line.pts[k + 1]
				local e = a:Lerp(b, math.max(g, 0.02))
				p.Size = Vector3.new(p.Size.X, 0.22, math.max(0.1, (e - a).Magnitude))
				p.CFrame = CFrame.lookAt((a + e) / 2, e + (b - a).Unit * 0.01)
				p.Transparency = if g <= 0 then 1 else 0
			end
		end
	end
end

local function add(t: number, parts: { BasePart }, update: (f: number, now: number) -> ())
	local tele: Tele =
		{ start = os.clock(), dur = math.max(t, 0.05), update = update, parts = parts, done = false }
	update(0, tele.start)
	table.insert(active, tele)
end

---------------------------------------------------------------------------
-- The shapes
---------------------------------------------------------------------------

local function ring(c: Vector3, r: number, t: number, crack: boolean, nDash: number?)
	local parts = {}
	local s = scale()
	table.insert(parts, disc(c, r, TINT, 0.12, 0.62))
	local fill = disc(c, 0.5, WARN, 0.16, 0.38)
	table.insert(parts, fill)
	local n = math.floor((nDash or math.clamp(math.floor(r * 0.5), 10, 28)) * s / 2) * 2
	local edge = dashes(parts, c, r, math.max(n, 6), 0, math.pi * 2, math.clamp(r * 0.045, 0.8, 2.6))
	local grow = if crack
		then cracks(parts, c, r * 0.8, math.max(3, math.floor(6 * s)), math.floor(c.X * 7 + c.Z))
		else nil
	FxLib.dust(c + UP * 0.4, r)
	local nextEmber = 0
	add(t, parts, function(f, now)
		local d = math.max(0.5, r * 2 * f)
		fill.Size = Vector3.new(0.12, d, d)
		fill.Transparency = 0.38 - 0.18 * f
		fillColor(fill, f)
		pulse(edge, f, now)
		if grow then
			grow(f)
		end
		if f > 0.6 and now >= nextEmber then
			nextEmber = now + 0.18
			local a = math.random() * math.pi * 2
			FxLib.emit("ember", WARN, c + Vector3.new(math.cos(a), 0.4, math.sin(a)) * r, 2, UP)
		end
	end)
end

-- A flat triangle on the ground from two wedges (the classic two-WedgePart triangle), reused every frame
local function wedge(color: Color3): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Color = color
	w.Material = Enum.Material.SmoothPlastic
	w.Size = Vector3.new(0.1, 0.1, 0.1)
	w.Parent = folder
	return w
end

local function triangle(a: Vector3, b: Vector3, c: Vector3, w1: BasePart, w2: BasePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	w1.Size = Vector3.new(0.1, math.max(height, 0.05), math.max(math.abs(ab:Dot(back)), 0.05))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(0.1, math.max(height, 0.05), math.max(math.abs(ac:Dot(back)), 0.05))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function cone(c: Vector3, r: number, arc: number, yaw: number, t: number)
	local parts = {}
	local s = scale()
	local half = math.rad(arc / 2)
	-- the facing (Roblox yaw: forward is (-sin, -cos)) as an angle from +x toward +z
	local mid = math.atan2(-math.cos(yaw), -math.sin(yaw))
	local m = math.max(4, math.floor(math.clamp(arc / 15, 5, 14) * s))
	local step = (half * 2) / m
	local slices = {}
	local floorY = UP * 0.12
	for i = 0, m - 1 do
		local a0, a1 = mid - half + i * step, mid - half + (i + 1) * step
		local d0 = Vector3.new(math.cos(a0), 0, math.sin(a0))
		local d1 = Vector3.new(math.cos(a1), 0, math.sin(a1))
		-- the faint floor over the whole slice, and its fill that grows outward from the boss
		local b1, b2 = wedge(TINT), wedge(TINT)
		b1.Transparency, b2.Transparency = 0.64, 0.64
		triangle(c + floorY, c + d0 * r + floorY, c + d1 * r + floorY, b1, b2)
		local f1, f2 = wedge(WARN), wedge(WARN)
		for _, p in { b1, b2, f1, f2 } do
			table.insert(parts, p)
		end
		table.insert(slices, { d0 = d0, d1 = d1, f1 = f1, f2 = f2 })
	end
	local width = math.clamp(r * 0.04, 0.8, 2.4)
	local edge = dashes(parts, c, r, math.max(4, math.floor(m * 1.2)), mid - half, mid + half, width)
	if arc < 360 then
		for _, a in { mid - half, mid + half } do
			for _, d in
				dashLine(
					parts,
					c,
					c + Vector3.new(math.cos(a), 0, math.sin(a)) * r,
					math.max(8, r / (6 * s)),
					width
				)
			do
				table.insert(edge, d)
			end
		end
	end
	FxLib.dust(c + Vector3.new(math.cos(mid), 0.4, math.sin(mid)) * r * 0.6, r * 0.5)
	add(t, parts, function(f, now)
		local len = math.max(0.5, r * f)
		local y = UP * 0.16
		for _, sl in slices do
			triangle(c + y, c + sl.d0 * len + y, c + sl.d1 * len + y, sl.f1, sl.f2)
			for _, p in { sl.f1, sl.f2 } do
				p.Transparency = 0.42 - 0.18 * f
				fillColor(p, f)
			end
		end
		pulse(edge, f, now)
	end)
end

local function line(from: Vector3, dir: Vector3, length: number, width: number, t: number)
	local parts = {}
	local s = scale()
	local f0 = Vector3.new(dir.X, 0, dir.Z)
	if f0.Magnitude < 1e-3 then
		return
	end
	local fwd = f0.Unit
	local side = fwd:Cross(UP).Unit
	local lift = UP * 0.12
	local base = part(
		Vector3.new(width, 0.1, length),
		CFrame.lookAt(from + fwd * length / 2 + lift, from + fwd * length + lift),
		TINT
	)
	base.Transparency = 0.62
	table.insert(parts, base)
	local fill = part(Vector3.new(width * 0.92, 0.12, 0.5), CFrame.new(from), WARN)
	table.insert(parts, fill)
	local every = math.max(10, 16 / s)
	local edge = {}
	for _, sgn in { -1, 1 } do
		local off = side * (width / 2) * sgn
		for _, d in dashLine(parts, from + off, from + off + fwd * length, every, 0.9) do
			table.insert(edge, d)
		end
	end
	-- chevrons along the lane point the way the beam goes
	local chev = {}
	local nChev = math.max(2, math.floor(length / (40 / s)))
	for i = 1, nChev do
		for _, p in chevron(parts, from + fwd * (length * i / (nChev + 1)), fwd, math.min(width * 0.7, 7)) do
			table.insert(chev, p)
		end
	end
	add(t, parts, function(f, now)
		local len = math.max(0.5, length * f)
		fill.Size = Vector3.new(width * 0.92, 0.12, len)
		fill.CFrame = CFrame.lookAt(from + fwd * len / 2 + UP * 0.16, from + fwd * len + UP * 0.16)
		fill.Transparency = 0.4 - 0.2 * f
		fillColor(fill, f)
		pulse(edge, f, now)
		for _, p in chev do
			p.Transparency = if f * length > (p.CFrame.Position - from):Dot(fwd) then 0.1 else 0.55
		end
	end)
end

local function pull(c: Vector3, r: number, nova: number, t: number, color: Color3)
	local parts = {}
	local s = scale()
	-- the pull's reach: a faint floor and a dashed edge, chevrons crawling in toward the danger ring
	table.insert(parts, disc(c, r, TINT, 0.1, 0.8))
	local edge = dashes(parts, c, r, math.max(8, math.floor(28 * s / 2) * 2), 0, math.pi * 2, 1.6)
	local n = math.max(4, math.floor(8 * s))
	local chev = {}
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		table.insert(chev, { parts = chevron(parts, c + dir * r, -dir, 6), dir = dir, a = a })
	end
	local nextMote = 0
	add(t, parts, function(f, now)
		pulse(edge, f, now)
		for _, ch in chev do
			-- each chevron crawls in from the edge to the danger ring, over and over, faster near the end
			local k = ((now * (0.6 + f)) + ch.a / (math.pi * 2)) % 1
			local at = c + ch.dir * (r - (r - nova) * k)
			for j, p in ch.parts do
				local sgn = if j == 1 then -1 else 1
				local arm = (CFrame.fromAxisAngle(UP, math.rad(sgn * 40)) * CFrame.lookAt(
					Vector3.zero,
					ch.dir
				)).LookVector
				local mid = at + arm * 3 + UP * 0.34
				p.CFrame = CFrame.lookAt(mid, mid + arm)
			end
		end
		if now >= nextMote then
			nextMote = now + 0.25
			local a = math.random() * math.pi * 2
			FxLib.emit(
				"wisp",
				color,
				c + Vector3.new(math.cos(a), 0.15, math.sin(a)) * r * 0.8,
				2,
				-Vector3.new(math.cos(a), -0.1, math.sin(a))
			)
			FxLib.emit("vortex", color, c + UP * 2, 1)
		end
	end)
	ring(c, nova, t, false)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function BossTelegraph.init(parent: Instance)
	folder = parent
end

-- A Boss.Attack warn: draw its telegraph for its warning time. struct: a slam that cracks the ground; color: the
-- boss's look (the pull's motes)
function BossTelegraph.warn(ev: { [string]: any }, groundY: number, color: Color3?)
	local t = ev.t or 1
	local c = Vector3.new(ev.x, groundY, ev.z)
	local shape = ev.shape
	if shape == "ring" then
		ring(c, ev.r, t, true)
	elseif shape == "cone" then
		cone(c, ev.r, ev.arc or 360, ev.yaw or 0, t)
	elseif shape == "circles" then
		for _, p in ev.points or {} do
			ring(Vector3.new(p[1], groundY, p[2]), ev.r, t, false, 8)
		end
	elseif shape == "lines" then
		for _, d in ev.points or {} do
			line(c, Vector3.new(d[1], 0, d[2]), ev.length, ev.width, t)
		end
	elseif shape == "pull" then
		pull(c, ev.r, ev.nova, t, color or WARN)
	end
end

-- The hit landed: a shockwave ring, dust and a scorch, and lingering cracks for the slams
function BossTelegraph.strike(ev: { [string]: any }, groundY: number, color: Color3?)
	local col = color or WARN
	local c = Vector3.new(ev.x, groundY, ev.z)
	local function slam(at: Vector3, r: number, crack: boolean)
		FxLib.shock(at + UP * 0.6, r, col)
		FxLib.dust(at + UP * 0.4, r * 0.8)
		FxLib.emit("scorch", CRACK, at + UP * 0.3, 1, UP)
		if crack then
			local parts = {}
			local grow = cracks(
				parts,
				at,
				r * 0.9,
				math.max(4, math.floor(8 * scale())),
				math.floor(at.X * 3 + at.Z * 5)
			)
			grow(1)
			for _, p in parts do
				TweenService:Create(
					p,
					TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.6),
					{
						Transparency = 1,
					}
				):Play()
				Debris:AddItem(p, 3)
			end
			FxLib.emit("rock", Color3.fromRGB(120, 108, 96), at + UP * 1.5, math.floor(6 * scale()), UP)
		end
	end
	if ev.shape == "ring" then
		slam(c, ev.r or 40, true)
	elseif ev.shape == "circles" then
		for _, p in ev.points or {} do
			slam(Vector3.new(p[1], groundY, p[2]), ev.r or 10, false)
		end
	elseif ev.shape == "pull" then
		slam(c, ev.r or 35, true)
	end
end

-- Every frame (WorldFx's profiled loop): fills and edges from the clock; a finished telegraph is cleared
function BossTelegraph.step()
	local now = os.clock()
	for i = #active, 1, -1 do
		local tele = active[i]
		local f = (now - tele.start) / tele.dur
		if f >= 1 then
			tele.update(1, now)
			for _, p in tele.parts do
				p:Destroy()
			end
			table.remove(active, i)
		else
			tele.update(f, now)
		end
	end
end

-- How many telegraphs are up (Dev panel, tests)
function BossTelegraph.count(): number
	return #active
end

BossTelegraph.WARN = WARN
return BossTelegraph
