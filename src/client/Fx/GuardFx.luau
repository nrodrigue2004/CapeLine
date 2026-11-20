-- GuardFx: the look of block, breaker and interrupt (spec: Hero MMO features > Block, breaker and interrupt;
-- H1). A blue energy shield (face, core, eight-sided rim) in front of every hero holding Block (the Blocking attribute), a blue shine round
-- robots holding a timed block (GuardEvent rup / rdown), the War-Frame's telegraph before its block (rwarn, WP6:
-- the shine builds over a blue ground ring that fills, with a rising hum; a boss's shine is sized and placed by
-- the event, `s` and `f`, not on a drawn robot), and the comic words BLOCKED, PERFECT!, SHATTER! and
-- CUT OFF! where they happen, each with its juice row (sound, flash, shake). The looks are Blender meshes
-- (art/blender/guard.py, ReplicatedStorage.Art.Guard; list-combat 2026-11-20, Everything Left 384): a domed
-- shield face with a hexagon, an eight-sided rim and a hex core; a geodesic bubble on blocking robots that turns
-- slowly; a comic starburst for the perfect block and the cut; crystal shards that fly out of a shatter. While
-- Art.Guard is not imported the old neon parts stand in (discs, balls and rim blocks).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))

local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)
local BlockClient = require(script.Parent.Parent.Controllers.BlockClient)
local Juice = require(script.Parent.Juice)
local PhaseClient = require(script.Parent.Parent.Controllers.PhaseClient) -- "Hide you fully" (nate, 2026-11-20)

local GuardFx = {}

local G = Config.Guard
local player = Players.LocalPlayer
local folder: Folder
type HeroShield = {
	parts: { BasePart },
	offs: { CFrame },
	grow: { [number]: Vector3 }, -- a part's size at full scale (the rest keep theirs)
	rims: { BasePart },
	core: BasePart,
	born: number,
	hitAt: number,
}
local heroShields: { [Player]: HeroShield } = {}
local robotShields: { [number]: { part: BasePart, untilT: number, fixed: Vector3?, turn: CFrame } } = {}
local GUARD_BLUE = Color3.fromRGB(150, 200, 255)

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function newPart(shape: Enum.PartType, size: Vector3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.ForceField
	p.Color = rgb(G.shield.color)
	p.Transparency = G.shield.transparency
	p.Parent = folder
	return p
end

-- One of Art.Guard's meshes, ready to place (nil while the set is not imported)
local TURN = MeshFix.turn("Guard")
-- the held shield's mesh sizes as a share of Config.Guard.shield.size (x: thickness through the face)
local FACE, RIM, CORE = Vector3.new(0.15, 1, 1), Vector3.new(0.075, 1, 1), Vector3.new(0.03, 0.55, 0.55)
local function guardMesh(
	name: string,
	material: Enum.Material,
	color: Color3,
	transparency: number
): MeshPart?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local set = art and art:FindFirstChild("Guard")
	local src = set and set:FindFirstChild(name, true)
	if not (src and src:IsA("MeshPart")) then
		return nil
	end
	local p = MeshFix.clone(src)
	for _, c in p:GetChildren() do
		c:Destroy()
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Color = color
	p.Transparency = transparency
	p.Parent = folder
	return p
end

-- A comic word floating up from a spot (fixed words from Config.Guard.words)
local function pop(kind: string, pos: Vector3)
	local text = G.words[kind]
	if not text then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	local big = kind == "perfect" or kind == "shatter"
	gui.Size = UDim2.fromOffset(if big then 190 else 140, if big then 70 else 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 200
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.Bangers
	label.TextColor3 = rgb(G.colors[kind] or G.colors.block)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Rotation = (math.random() - 0.5) * 16
	label.Parent = gui
	gui.Parent = anchor
	TweenService:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)),
	}):Play()
	TweenService:Create(
		label,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	Debris:AddItem(anchor, 0.95)
end

-- The comic starburst: flat, turned to the camera, spinning a little as it swells and fades
local function flash(pos: Vector3, color: Color3, size: number): boolean
	local p = guardMesh("GuardFlash", Enum.Material.Neon, color, 0.1)
	if not p then
		return false
	end
	local cam = Workspace.CurrentCamera
	local face = if cam then CFrame.lookAt(pos, cam.CFrame.Position) else CFrame.new(pos)
	local spin = (math.random() - 0.5) * 0.6
	p.Size = Vector3.new(size * 0.3, size * 0.3, 0.2)
	p.CFrame = face * CFrame.Angles(0, 0, spin) * TURN
	TweenService:Create(p, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, 0.2),
		CFrame = face * CFrame.Angles(0, 0, spin + 0.5) * TURN,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.32)
	return true
end

-- A shattered guard's shards flying out from the spot, spinning, and falling a little
local function shards(pos: Vector3, color: Color3, count: number, reach: number)
	for i = 1, count do
		local p = guardMesh("GuardShard", Enum.Material.Glass, color, 0.15)
		if not p then
			return
		end
		local a = (i - 0.5) / count * 2 * math.pi + (math.random() - 0.5) * 0.5
		local dir = Vector3.new(math.cos(a), 0.35 + math.random() * 0.6, math.sin(a)).Unit
		local len = 1 + math.random() * 0.8
		p.Size = Vector3.new(0.4, 0.34, 1) * len
		local turnTo = CFrame.lookAt(pos, pos + dir)
		p.CFrame = turnTo * TURN
		local to = pos + dir * reach * (0.7 + math.random() * 0.5) - Vector3.new(0, 1.2, 0)
		TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(to)
				* (turnTo - turnTo.Position)
				* CFrame.Angles(math.random() * 6, math.random() * 6, 0)
				* TURN,
			Transparency = 1,
		}):Play()
		Debris:AddItem(p, 0.55)
	end
end

-- A quick burst (the shatter's shards, the perfect block's flash): the starburst, or a ball while Art.Guard is
-- not imported
local function burst(pos: Vector3, color: Color3, size: number)
	if flash(pos, color, size) then
		return
	end
	local p = newPart(Enum.PartType.Ball, Vector3.one * 1)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.2
	p.CFrame = CFrame.new(pos)
	TweenService:Create(p, TweenInfo.new(0.25), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(p, 0.3)
end

-- The held guard's parts, laid out in the shield's own frame (x through the face, as a Cylinder's axis)
local function buildShield(): HeroShield
	local S = G.shield
	local d = S.size
	-- the meshes: a domed face (bulging out along +x), its rim and the hex core behind it
	local mFace = guardMesh("GuardFace", Enum.Material.ForceField, rgb(S.color), S.transparency)
	local mRim = mFace and guardMesh("GuardRim", Enum.Material.Neon, rgb(S.rim), 0.1)
	local mCore = mRim and guardMesh("GuardCore", Enum.Material.Neon, rgb(S.color), 0.78)
	if mFace and mRim and mCore then
		return {
			parts = { mFace, mCore, mRim },
			offs = { TURN, CFrame.new(-0.12, 0, 0) * TURN, CFrame.new(-0.2, 0, 0) * TURN },
			grow = { FACE * d, CORE * d, RIM * d },
			rims = { mRim },
			core = mCore,
			born = os.clock(),
			hitAt = -1,
		}
	elseif mFace then
		for _, p in { mFace, mRim, mCore } do
			if p then
				p:Destroy()
			end
		end
	end
	local face = newPart(Enum.PartType.Cylinder, Vector3.new(0.25, d, d))
	local core = newPart(Enum.PartType.Cylinder, Vector3.new(0.12, d * 0.55, d * 0.55))
	core.Material = Enum.Material.Neon
	core.Transparency = 0.78
	local parts, offs, rims = { face, core }, { CFrame.identity, CFrame.new(-0.12, 0, 0) }, {}
	local r = d / 2
	local side = 2 * r * math.tan(math.pi / S.sides) + 0.05
	for i = 1, S.sides do
		local a = (i - 0.5) / S.sides * 2 * math.pi
		local seg = newPart(Enum.PartType.Block, Vector3.new(0.3, 0.24, side))
		seg.Material = Enum.Material.Neon
		seg.Transparency = 0.1
		seg.Color = rgb(S.rim)
		table.insert(parts, seg)
		table.insert(offs, CFrame.Angles(a, 0, 0) * CFrame.new(0, r * math.cos(math.pi / S.sides), 0))
		table.insert(rims, seg)
	end
	return {
		parts = parts,
		offs = offs,
		grow = { Vector3.new(0.25, d, d), Vector3.new(0.12, d * 0.55, d * 0.55) },
		rims = rims,
		core = core,
		born = os.clock(),
		hitAt = -1,
	}
end

local function onEvent(ev: any)
	local pos = Vector3.new(ev.x, ev.y + 3, ev.z)
	local mine = ev.a == player.UserId
	if ev.k == "block" or ev.k == "perfect" or ev.k == "shatter" then
		-- the hero's body answers too (a jolt on the guard, the parry, the guard knocked open)
		HeroAnimator.guardEvent(if type(ev.a) == "number" then HeroAnimator.byUserId(ev.a) else nil, ev.k)
	end
	local held = if type(ev.a) == "number" then Players:GetPlayerByUserId(ev.a) else nil
	local hs = held and heroShields[held]
	if hs and (ev.k == "block" or ev.k == "perfect") then
		hs.hitAt = os.clock() -- the guard kicks and its core flashes
	end
	if ev.k == "block" then
		pop("block", pos)
		Juice.fire("block", pos, { mine = mine })
	elseif ev.k == "perfect" then
		pop("perfect", pos)
		burst(pos, rgb(G.colors.perfect), 9)
		Juice.fire("perfectBlock", pos, { mine = mine })
		if mine then
			CameraController.punch(Config.Combat.punchHeavy)
		end
	elseif ev.k == "shatter" then
		pop("shatter", pos)
		burst(pos, rgb(G.colors.shatter), 11)
		shards(pos, rgb(G.shield.rim), 8, 7)
		Juice.fire("shatter", pos, { mine = mine })
		CameraController.shake(0.12, 0.35)
	elseif ev.k == "cut" then
		pop("cut", pos)
		burst(pos, rgb(G.colors.cut), 6)
		Juice.fire("interrupt", pos, { mine = mine })
	elseif ev.k == "rwarn" or ev.k == "rup" then
		local s = robotShields[ev.a]
		local size = Vector3.one * (ev.s or 9)
		if not s then
			local bubble = guardMesh("GuardBubble", Enum.Material.ForceField, rgb(G.shield.color), 1)
			s = {
				part = bubble or newPart(Enum.PartType.Ball, size),
				untilT = 0,
				turn = if bubble then TURN else CFrame.identity,
			}
			robotShields[ev.a] = s
		end
		s.part.Size = size
		s.fixed = if ev.f then Vector3.new(ev.x, ev.y, ev.z) else nil
		if ev.k == "rwarn" then
			-- the telegraph: the shine fades in over the warning and a blue ring fills on the ground under it
			local t = ev.t or 1
			s.untilT = os.clock() + t + 0.6 -- held until its rup (or rdown) arrives
			s.part.Transparency = 1
			TweenService:Create(s.part, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = G.shield.transparency + 0.2,
			}):Play()
			local r = (ev.s or 9) * 0.6
			local floor = Vector3.new(ev.x, ev.g or (ev.y - 3), ev.z) -- g: the ground under a boss
			local cf = CFrame.new(floor + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local outline = newPart(Enum.PartType.Cylinder, Vector3.new(0.12, r * 2, r * 2))
			outline.Material = Enum.Material.SmoothPlastic
			outline.Color = GUARD_BLUE
			outline.Transparency = 0.5
			outline.CFrame = cf
			local fill = newPart(Enum.PartType.Cylinder, Vector3.new(0.14, 0.5, 0.5))
			fill.Material = Enum.Material.Neon
			fill.Color = GUARD_BLUE
			fill.Transparency = 0.35
			fill.CFrame = cf
			TweenService:Create(fill, TweenInfo.new(t, Enum.EasingStyle.Linear), {
				Size = Vector3.new(0.14, r * 2, r * 2),
			}):Play()
			Debris:AddItem(outline, t + 0.05)
			Debris:AddItem(fill, t + 0.05)
			Juice.fire("braceWarn", pos, { mine = false })
		else
			s.part.Transparency = G.shield.transparency
			s.untilT = os.clock() + (ev.t or 2)
		end
	elseif ev.k == "rdown" then
		local s = robotShields[ev.a]
		if s then
			-- a robot's dropped block breaks into a few shards (a breaker's shatter has its own word and burst)
			shards(s.part.Position, rgb(G.shield.rim), 5, s.part.Size.X * 0.4)
			s.part:Destroy()
			robotShields[ev.a] = nil
		end
	end
end

local function step()
	local now = os.clock()
	for id, s in robotShields do
		local pos = s.fixed or EnemyRenderer.position(id)
		if not pos or now > s.untilT then
			s.part:Destroy()
			robotShields[id] = nil
		else
			-- the bubble turns slowly so its facets catch the light
			s.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, now * 0.7, 0) * s.turn
		end
	end
	for _, p in Players:GetPlayers() do
		local on = p:GetAttribute("Blocking") == true and PhaseClient.seesPlayer(p)
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local shield = heroShields[p]
		if on and root then
			if not shield then
				shield = buildShield()
				heroShields[p] = shield
			end
			local hs = shield :: HeroShield
			local S = G.shield
			-- snaps up from small, kicks out on a hit and settles back
			local up = math.clamp((now - hs.born) / S.raise, 0, 1)
			local scale = 0.3 + 0.7 * (1 - (1 - up) ^ 3)
			local since = now - hs.hitAt
			if since < 0.2 then
				scale *= 1 + (S.kick - 1) * (1 - since / 0.2)
			end
			hs.core.Transparency = if since < 0.2 then 0.3 + 0.48 * since / 0.2 else 0.78
			-- yours shows your guard: the rim runs to the low colour as it drains and flickers near empty
			local g = if p == player then BlockClient.guard() else 1
			local rim = rgb(S.low):Lerp(rgb(S.rim), g)
			local lit = if g < S.flicker and math.floor(now * 14) % 2 == 0 then 0.6 else 0.1
			for _, seg in hs.rims do
				seg.Color = rim
				seg.Transparency = lit
			end
			-- a round shield held out in front of the chest (the face's axis points forward)
			local cf = root.CFrame * CFrame.new(0, 0.5, -2.2) * CFrame.Angles(0, math.rad(90), 0)
			local cfs = table.create(#hs.parts)
			for i, off in hs.offs do
				cfs[i] = cf * CFrame.new(off.Position * scale) * off.Rotation
				local full = hs.grow[i]
				if full then
					hs.parts[i].Size = Vector3.new(full.X, full.Y * scale, full.Z * scale)
				end
			end
			Workspace:BulkMoveTo(hs.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		elseif shield then
			for _, part in shield.parts do
				part:Destroy()
			end
			heroShields[p] = nil
		end
	end
end

function GuardFx.init()
	folder = Instance.new("Folder")
	folder.Name = "GuardFx"
	folder.Parent = Workspace
	Net.listen("GuardEvent", function(list)
		for _, ev in list do
			onEvent(ev)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local s = heroShields[p]
		if s then
			for _, part in s.parts do
				part:Destroy()
			end
			heroShields[p] = nil
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("GuardFx", step))
end

return GuardFx
