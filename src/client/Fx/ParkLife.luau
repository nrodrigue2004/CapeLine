-- ParkLife: the city park's life on this device (2026-11-20; Config.Park.life, Shared.ParkLayout). Everything here
-- is dressing each device draws for itself near its camera (nothing on the server depends on it), within its
-- preset's budget (Config.Park.life.budget low / medium / high: how many of each, how far), nearest first, and only
-- while the camera is near the park. One Heartbeat under FrameProf ("ParkLife"); the picks are redone once a second.
-- * People (CitizenRenderer.borrow: the citizens' own pooled R15 bodies, catalog faces and hair, uploaded clothes):
--   joggers round the reservoir's track and the drives, walkers with their dogs (Art.Park Dog: body, head, four legs
--   that trot, a wagging tail), picnics on the lawns (two sitting on a checked blanket by a basket) and buskers by the
--   Mall, the terrace and the bridges (a guitar strummed over an open case; a quiet loop near the nearest one).
-- * The water: ducks paddling in little loops that scatter from a hero or a bang and come back, rowboats bobbing
--   and drifting (three tied at the boathouse), a splash thrown up where a big hit lands on the water.
-- * The carousel turns (its ParkSpin pieces, the horses rising and falling) and the fountains play (spray from the
--   top bowl, a curtain spilling off each bowl's lip); a big hit near one bursts it into a tall geyser for a while.
-- * Kites (alive-world round 2, 2026-11-20): some picnics fly a kite from a sitter's hand, high over the lawn
--   downwind, swooping in a figure eight with its tail of bows (Config.Park.life.kite, Shared.LifePlan.kite).
-- No Art.Park imported: no boats, ducks, dogs, picnics or guitars (people and jets still come).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local Rng = require(Shared:WaitForChild("Rng"))
local ParkLayout = require(Shared:WaitForChild("ParkLayout"))
local LifePlan = require(Shared:WaitForChild("LifePlan"))
local Controllers = script.Parent.Parent.Controllers
local QualityController = require(Controllers.QualityController)
local CitizenRenderer = require(Controllers.CitizenRenderer)
local AudioController = require(Controllers.AudioController)
local BuildingFx = require(script.Parent.BuildingFx)
local PhaseClient = require(script.Parent.Parent.Controllers.PhaseClient) -- "Hide you fully" (nate, 2026-11-20)

local ParkLife = {}

local P = Config.Park
local L = P.life
local park: any = nil
local art: Instance? = nil
local folder: Folder? = nil
local bang = { at = Vector3.zero, t = -math.huge }

local function budget(): any
	return L.budget[QualityController.name] or L.budget.medium
end

local function focus(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.Focus.Position else Vector3.zero
end

local function heroes(): { Vector3 }
	local out = {}
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and PhaseClient.seesPlayer(p) then
			table.insert(out, root.Position)
		end
	end
	return out
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

---------------------------------------------------------------------------- looks (Art.Park meshes as local models)
type Look = { model: Model, parts: { BasePart }, offsets: { CFrame }, byName: { [string]: BasePart } }

local function source(name: string): MeshPart?
	local src = art and art:FindFirstChild(name, true)
	return if src and src:IsA("MeshPart") then src else nil
end

local function ready(look: string): boolean
	for name in Config.ParkArt[look] or {} do
		if not source(name) then
			return false
		end
	end
	return Config.ParkArt[look] ~= nil
end

-- One look's pieces as a model, each placed from the foot (moved with BulkMoveTo: foot CFrame * offset)
local function makeLook(look: string, colors: { [string]: { number } }?): Look?
	if not ready(look) or not folder then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Park" .. look
	local out: Look = { model = m, parts = {}, offsets = {}, byName = {} }
	for name, f in Config.ParkArt[look] do
		local c = P.looks[look][name]
		if not c then
			continue
		end
		local p = MeshFix.clone(source(name) :: MeshPart)
		for _, ch in p:GetChildren() do
			if not ch:IsA("SurfaceAppearance") then
				ch:Destroy()
			end
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = Vector3.new(f.size[1], f.size[2], f.size[3])
		local col = (colors and colors[name]) or c[1]
		p.Color = rgb(col)
		p.Material = (Enum.Material :: any)[c[2]]
		p.Transparency = c[3] or 0
		p.Name = name
		p.Parent = m
		table.insert(out.parts, p)
		table.insert(out.offsets, CFrame.new(f.offset[1], f.offset[2], f.offset[3]) * MeshFix.of(p))
		out.byName[name] = p
	end
	m.Parent = folder
	return out
end

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local function put(look: Look, at: CFrame)
	for i, p in look.parts do
		table.insert(moveParts, p)
		table.insert(moveCFrames, at * look.offsets[i])
	end
end

---------------------------------------------------------------------------- routes
type RouteRun = { pts: { { number } }, cum: { number }, length: number }
local runs: { RouteRun } = {}

local function along(r: RouteRun, s: number): (number, number, number)
	s = s % r.length
	local lo, hi = 1, #r.cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if r.cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local a = r.pts[lo]
	local b = r.pts[lo % #r.pts + 1]
	local seg = r.cum[lo + 1] - r.cum[lo]
	local t = if seg > 0 then (s - r.cum[lo]) / seg else 0
	local x, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
	return x, z, math.atan2(-(b[1] - a[1]), -(b[2] - a[2]))
end

---------------------------------------------------------------------------- people
local SIDES = { { "Left", -1 }, { "Right", 1 } }
type Person = { body: any?, id: number }

local function borrow(p: Person): any
	if not p.body then
		p.body = CitizenRenderer.borrow(L.people + p.id)
	end
	return p.body
end
local function giveBack(p: Person)
	if p.body then
		CitizenRenderer.giveBack(p.body)
		p.body = nil
	end
end

local function stride(rig: any, phase: number, amp: number, run: boolean)
	local swing = math.sin(phase) * amp
	for _, side in SIDES do
		local name, sign = side[1], side[2]
		NpcRig.turn(rig, name .. "Hip", CFrame.Angles(swing * sign, 0, 0))
		NpcRig.turn(
			rig,
			name .. "Knee",
			CFrame.Angles(-math.max(0, swing * sign) * (if run then 1.1 else 0.6), 0, 0)
		)
		NpcRig.turn(rig, name .. "Shoulder", CFrame.Angles(-swing * sign * 0.9, 0, 0))
		NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(if run then math.rad(80) else math.rad(18), 0, 0))
	end
	NpcRig.turn(rig, "Waist", if run then CFrame.Angles(math.rad(-8), 0, 0) else CFrame.identity)
end

local function sit(rig: any, wave: number)
	for _, side in SIDES do
		local name, sign = side[1], side[2]
		-- thighs forward (a joint's +x turn swings the limb forward: Shared.EmotePoses, StoryFx's sitter), shins
		-- down, hands toward the lap (list-combat 2026-11-20: they bent backward before)
		NpcRig.turn(rig, name .. "Hip", CFrame.Angles(math.rad(88), 0, -sign * 0.12))
		NpcRig.turn(rig, name .. "Knee", CFrame.Angles(math.rad(-80), 0, 0))
		NpcRig.turn(rig, name .. "Shoulder", CFrame.Angles(math.rad(25 + wave * sign * 8), 0, -sign * 0.1))
		NpcRig.turn(rig, name .. "Elbow", CFrame.Angles(math.rad(35), 0, 0))
	end
	NpcRig.turn(rig, "Waist", CFrame.Angles(math.rad(6), 0, 0))
end

local function strum(rig: any, t: number)
	NpcRig.turn(rig, "LeftShoulder", CFrame.Angles(math.rad(-55), 0, math.rad(-25)))
	NpcRig.turn(rig, "LeftElbow", CFrame.Angles(math.rad(70), 0, 0))
	NpcRig.turn(rig, "RightShoulder", CFrame.Angles(math.rad(-38 + math.sin(t * 9) * 10), 0, math.rad(20)))
	NpcRig.turn(rig, "RightElbow", CFrame.Angles(math.rad(65), 0, 0))
	for _, side in SIDES do
		NpcRig.turn(rig, side[1] .. "Hip", CFrame.identity)
		NpcRig.turn(rig, side[1] .. "Knee", CFrame.identity)
	end
	NpcRig.turn(rig, "Waist", CFrame.Angles(0, math.sin(t * 2.2) * 0.08, 0))
end

local roots: { BasePart } = {}
local rootCFrames: { CFrame } = {}
local function placeBody(body: any, x: number, y: number, z: number, yaw: number, drop: number)
	table.insert(roots, body.rig.root)
	table.insert(rootCFrames, CFrame.new(x, y + body.rig.layout.ground - drop, z) * CFrame.Angles(0, yaw, 0))
end

---------------------------------------------------------------------------- the pieces of life
type Mover = {
	person: Person,
	run: RouteRun,
	s0: number,
	speed: number,
	jog: boolean,
	dog: Look?,
	coat: { number }?,
	on: boolean,
}
type Kite = { part: BasePart, hand: Attachment, tailEnd: Attachment, beams: { Beam } }
type Picnic = {
	x: number,
	z: number,
	ry: number,
	people: { Person },
	look: Look?,
	on: boolean,
	flies: boolean, -- this picnic has a kite (by hash)
	kite: Kite?,
	u: number,
	v: number,
	tint: number,
}
type Busker = { x: number, z: number, ry: number, person: Person, guitar: Look?, case: Look?, on: boolean }
type Duck = {
	x: number,
	z: number,
	y: number,
	a: number,
	look: Look?,
	fleeUntil: number,
	fx: number,
	fz: number,
	on: boolean,
	kind: number,
}
type Boat = { x: number, z: number, ry: number, docked: boolean, look: Look?, rock: number, on: boolean }
local movers: { Mover } = {}
local picnics: { Picnic } = {}
local buskers: { Busker } = {}
local ducks: { Duck } = {}
local boats: { Boat } = {}
local spin: { { part: BasePart, base: CFrame, horses: boolean } } = {}
local jets: { { f: any, part: BasePart?, emitters: { ParticleEmitter }, burstUntil: number, on: boolean } } =
	{}
local buskSound: Sound? = nil

local function dist2(x: number, z: number, at: Vector3): number
	local dx, dz = x - at.X, z - at.Z
	return dx * dx + dz * dz
end

-- the nearest `n` of a list within `radius` (by their x, z) are on, the rest off
local function pick<T>(
	list: { T },
	n: number,
	at: Vector3,
	radius: number,
	pos: (T) -> (number, number),
	set: (T, boolean) -> ()
)
	local order = {}
	for i, it in list do
		local x, z = pos(it)
		local d = dist2(x, z, at)
		if d <= radius * radius then
			table.insert(order, { i, d })
		end
	end
	table.sort(order, function(a, b)
		return a[2] < b[2]
	end)
	local want: { [number]: boolean } = {}
	for k = 1, math.min(n, #order) do
		want[order[k][1]] = true
	end
	for i, it in list do
		set(it, want[i] == true)
	end
end

local function dropLook(l: Look?)
	if l then
		l.model:Destroy()
	end
end

local function moverPos(m: Mover, now: number): (number, number, number)
	return along(m.run, m.s0 + now * m.speed)
end

local function setMover(m: Mover, on: boolean)
	if on == m.on then
		return
	end
	m.on = on
	if on then
		borrow(m.person)
		if m.coat then
			m.dog = makeLook("Dog", { DogBody = m.coat, DogHead = m.coat, DogTail = m.coat })
			if m.dog then
				-- three more legs: the look holds one (front left); the device places four
				for k = 2, 4 do
					local leg = m.dog.byName.DogLeg:Clone()
					leg.Name = "DogLeg" .. k
					leg.Parent = m.dog.model
					m.dog.byName["DogLeg" .. k] = leg
				end
			end
		end
	else
		giveBack(m.person)
		dropLook(m.dog)
		m.dog = nil
	end
end

local function setPicnic(p: Picnic, on: boolean)
	if on == p.on then
		return
	end
	p.on = on
	if on then
		p.look = makeLook("Picnic")
		for _, person in p.people do
			borrow(person)
		end
	else
		dropLook(p.look)
		p.look = nil
		for _, person in p.people do
			giveBack(person)
		end
	end
end

---------------------------------------------------------------------------- kites
local KT = L.kite

local function beam(a0: Attachment, a1: Attachment, width: number, parent: Instance): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = width
	b.Width1 = width
	b.FaceCamera = true
	b.Segments = 12
	b.LightInfluence = 1
	b.Parent = parent
	return b
end

local function makeKite(p: Picnic): Kite?
	if not folder then
		return nil
	end
	local w, h = KT.size[1], KT.size[2]
	local part = Instance.new("Part")
	part.Name = "Kite"
	part.Size = Vector3.new(w, h, 0.05)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local tint = rgb(KT.tints[p.tint])
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local tex = Instance.new("Texture")
		tex.Texture = "rbxassetid://" .. tostring(KT.image)
		tex.Face = face
		tex.StudsPerTileU = w
		tex.StudsPerTileV = h
		tex.Color3 = tint
		tex.Parent = part
	end
	-- the bridle on the spars' crossing, the tail from the foot
	local bridle = Instance.new("Attachment")
	bridle.Position = Vector3.new(0, h * 0.14, 0)
	bridle.Parent = part
	local foot = Instance.new("Attachment")
	foot.Position = Vector3.new(0, -h / 2, 0)
	foot.Parent = part
	local terrain = Workspace.Terrain
	local hand = Instance.new("Attachment")
	hand.Name = "KiteHand"
	hand.Parent = terrain
	local tailEnd = Instance.new("Attachment")
	tailEnd.Name = "KiteTail"
	tailEnd.Parent = terrain
	local str = beam(hand, bridle, 0.07, part)
	str.Color = ColorSequence.new(Color3.fromRGB(245, 245, 240))
	str.Transparency = NumberSequence.new(0.15)
	local tail = beam(foot, tailEnd, 1.3, part)
	tail.Texture = "rbxassetid://" .. tostring(KT.tail)
	tail.TextureMode = Enum.TextureMode.Stretch
	tail.TextureLength = 1
	part.Parent = folder
	return { part = part, hand = hand, tailEnd = tailEnd, beams = { str, tail } }
end

local function setKite(p: Picnic, on: boolean)
	if on == (p.kite ~= nil) then
		return
	end
	if on then
		p.kite = makeKite(p)
	elseif p.kite then
		p.kite.part:Destroy()
		p.kite.hand:Destroy()
		p.kite.tailEnd:Destroy()
		p.kite = nil
	end
end

local function setBusker(b: Busker, on: boolean)
	if on == b.on then
		return
	end
	b.on = on
	if on then
		borrow(b.person)
		b.guitar = makeLook("Guitar")
		b.case = makeLook("GuitarCase")
	else
		giveBack(b.person)
		dropLook(b.guitar)
		dropLook(b.case)
		b.guitar, b.case = nil, nil
	end
end

local function setDuck(d: Duck, on: boolean)
	if on == d.on then
		return
	end
	d.on = on
	if on then
		local kind = P.duckKinds[d.kind]
		d.look = makeLook("Duck", { DuckBody = kind[1], DuckHead = kind[2] })
	else
		dropLook(d.look)
		d.look = nil
	end
end

local function setBoat(b: Boat, on: boolean)
	if on == b.on then
		return
	end
	b.on = on
	if on then
		b.look = makeLook("Rowboat")
	else
		dropLook(b.look)
		b.look = nil
	end
end

---------------------------------------------------------------------------- fountains
local function emitter(
	parent: Instance,
	rate: number,
	speed: number,
	size: number,
	life: number,
	spread: number
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(200, 232, 255), Color3.fromRGB(245, 252, 255))
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2.4) })
	e.Lifetime = NumberRange.new(life * 0.8, life)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.85, speed)
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = Vector3.new(0, -Workspace.Gravity * 0.32, 0)
	e.LightInfluence = 0.7
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	return e
end

local function setJet(j: any, on: boolean)
	if on == j.on then
		return
	end
	j.on = on
	if on and folder then
		local f = j.f
		local J = L.jet
		local src = Instance.new("Part")
		src.Name = "ParkJet"
		src.Anchored = true
		src.CanCollide = false
		src.CanQuery = false
		src.CanTouch = false
		src.Transparency = 1
		src.Size = Vector3.new(1, 0.2, 1)
		src.CFrame = CFrame.new(f.x, f.top, f.z)
		src.Parent = folder
		j.part = src
		local top = emitter(src, if f.terrace then J.terraceRate else J.rate, J.speed, J.size, 1.4, 7)
		-- the curtain off the bowl's lip (and the basin's spill on the terrace), falling in a ring
		local ring = Instance.new("Part")
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Transparency = 1
		ring.Shape = Enum.PartType.Cylinder
		local rr = if f.terrace then 7.4 else 2.4
		ring.Size = Vector3.new(0.2, rr * 2, rr * 2)
		ring.CFrame = CFrame.new(f.x, if f.terrace then 9.1 else 5.5, f.z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = src
		local curtain = emitter(ring, if f.terrace then 70 else 24, 2, 0.7, 0.7, 10)
		curtain.Shape = Enum.ParticleEmitterShape.Cylinder
		curtain.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		curtain.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		curtain.EmissionDirection = Enum.NormalId.Right
		j.emitters = { top, curtain }
	elseif j.part then
		j.part:Destroy()
		j.part = nil
		j.emitters = {}
	end
end

---------------------------------------------------------------------------- impacts: fountain bursts, splashes, scared ducks
local function splashAt(at: Vector3, level: number)
	if not folder then
		return
	end
	local S = L.splash
	local src = Instance.new("Part")
	src.Name = "ParkSplash"
	src.Anchored = true
	src.CanCollide = false
	src.CanQuery = false
	src.CanTouch = false
	src.Transparency = 1
	src.Size = Vector3.new(1, 0.2, 1)
	src.CFrame = CFrame.new(at.X, level, at.Z)
	src.Parent = folder
	local e = emitter(src, 0, S.speed, 1.4, 1.6, 22)
	e:Emit(math.floor(S.rate * (if QualityController.name == "low" then 0.4 else 1)))
	-- the ring of white water spreading out
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(236, 246, 255)
	ring.Transparency = 0.35
	ring.Parent = src
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local k = (os.clock() - t0) / S.time
		if k >= 1 then
			if conn then
				conn:Disconnect()
			end
			src:Destroy()
			return
		end
		local r = 2 + S.ring * k
		ring.Size = Vector3.new(0.15, r * 2, r * 2)
		ring.CFrame = CFrame.new(at.X, level + 0.05, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.35 + 0.65 * k
	end)
	AudioController.playSpec(P.sounds.splash, Vector3.new(at.X, level, at.Z))
end

local function onImpact(center: Vector3, radius: number, _kind: number)
	if not park or radius < 4 then
		return
	end
	local b = P.bounds
	if center.X < b.minX or center.X > b.maxX or center.Z < b.minZ or center.Z > b.maxZ then
		return
	end
	bang.at, bang.t = center, os.clock()
	for _, w in park.waters do
		if ParkLayout.inside(w, center.X, center.Z) > 0 and center.Y < w.level + 10 then
			splashAt(center, w.level)
			for _, bt in boats do
				if bt.on and dist2(bt.x, bt.z, center) < 60 * 60 then
					bt.rock = L.boat.splashRock
				end
			end
			break
		end
	end
	for _, j in jets do
		local f = j.f
		if dist2(f.x, f.z, center) < (L.burst.radius + radius) ^ 2 then
			j.burstUntil = os.clock() + L.burst.time
			AudioController.playSpec(P.sounds.burst, Vector3.new(f.x, f.top, f.z))
		end
	end
end

---------------------------------------------------------------------------- the frame
local lastPick = 0
local inside = false
local function anyOn(): boolean
	return inside
end

local function pickAll(at: Vector3)
	local B = budget()
	local r = B.radius
	local jogs, walks = {}, {}
	for _, m in movers do
		table.insert(if m.jog then jogs else walks, m)
	end
	local now = os.clock()
	local function mpos(m: Mover): (number, number)
		local x, z = moverPos(m, now)
		return x, z
	end
	pick(jogs, B.joggers, at, r, mpos, setMover)
	-- walkers: the first B.dogs of the picked have their dogs (each walker keeps its own: coats set at init)
	pick(walks, B.walkers, at, r, mpos, setMover)
	pick(picnics, B.picnics, at, r, function(p: Picnic)
		return p.x, p.z
	end, setPicnic)
	-- kites: the nearest picnics that are out and fly one, up to the preset's count
	local fliers: { { p: Picnic, d: number } } = {}
	for _, p in picnics do
		if p.on and p.flies then
			table.insert(fliers, { p = p, d = dist2(p.x, p.z, at) })
		else
			setKite(p, false)
		end
	end
	table.sort(fliers, function(a, b)
		return a.d < b.d
	end)
	for k, f in fliers do
		setKite(f.p, k <= (B.kites or 0))
	end
	pick(buskers, B.buskers, at, r, function(b: Busker)
		return b.x, b.z
	end, setBusker)
	pick(ducks, B.ducks, at, r, function(d: Duck)
		return d.x, d.z
	end, setDuck)
	pick(boats, B.boats, at, r, function(b: Boat)
		return b.x, b.z
	end, setBoat)
	pick(jets, B.jets, at, r, function(j: any)
		return j.f.x, j.f.z
	end, setJet)
	-- the busker's tune at the nearest one playing
	local best, bd = nil, math.huge
	for _, b in buskers do
		if b.on then
			local d = dist2(b.x, b.z, at)
			if d < bd then
				best, bd = b, d
			end
		end
	end
	if buskSound then
		if best and bd < L.busk.range * L.busk.range then
			buskSound.Parent = (best.person.body and best.person.body.rig.root) or nil
			if not buskSound.IsPlaying then
				buskSound:Play()
			end
		else
			buskSound:Stop()
		end
	end
end

local function step(dt: number)
	if not park then
		return
	end
	local now = os.clock()
	local at = focus()
	if now >= lastPick then
		lastPick = now + 1
		local b = P.bounds
		local pad = budget().radius
		inside = at.X > b.minX - pad
			and at.X < b.maxX + pad
			and at.Z > b.minZ - pad
			and at.Z < b.maxZ + pad
			and at.Y < 900
		pickAll(if inside then at else Vector3.new(1e7, 0, 1e7))
	end
	if not anyOn() then
		return
	end
	table.clear(moveParts)
	table.clear(moveCFrames)
	table.clear(roots)
	table.clear(rootCFrames)
	local list = heroes()
	local pathY = Config.City.ground.y + P.path.y + 0.15

	-- joggers and walkers (and their dogs)
	for _, m in movers do
		local body = m.on and m.person.body
		if not body then
			continue
		end
		local x, z, yaw = moverPos(m, now)
		local phase = (m.s0 + now * m.speed) * (if m.jog then 0.95 else 1.25)
		local bob = if m.jog then math.abs(math.sin(phase)) * L.jog.bob else 0
		placeBody(body, x, pathY + bob, z, yaw, 0)
		stride(body.rig, phase, if m.jog then 0.85 else 0.5, m.jog)
		local dog = m.dog
		if dog then
			-- trotting at the walker's side, a little ahead
			local fx, fz = -math.sin(yaw), -math.cos(yaw)
			local sx, sz = -fz, fx
			local dx, dz = x + fx * L.dog.lead + sx * 2.2, z + fz * L.dog.lead + sz * 2.2
			local foot = CFrame.new(dx, pathY - 0.1, dz) * CFrame.Angles(0, yaw, 0)
			for i, p in dog.parts do
				if p.Name ~= "DogLeg" and p.Name ~= "DogTail" then
					table.insert(moveParts, p)
					table.insert(moveCFrames, foot * dog.offsets[i])
				end
			end
			local legFit = Config.ParkArt.Dog.DogLeg
			local tr = phase * L.dog.trot
			local k = 0
			for _, name in { "DogLeg", "DogLeg2", "DogLeg3", "DogLeg4" } do
				k += 1
				local leg = dog.byName[name]
				if leg then
					local lx = if k % 2 == 1 then legFit.offset[1] else -legFit.offset[1]
					local lz = if k <= 2 then legFit.offset[3] else -legFit.offset[3] + 0.6
					local swing = math.sin(tr + (if k == 1 or k == 4 then 0 else math.pi)) * 0.5
					local hip = foot * CFrame.new(lx, legFit.offset[2] + legFit.size[2] / 2, lz)
					table.insert(moveParts, leg)
					table.insert(
						moveCFrames,
						hip
							* CFrame.Angles(swing, 0, 0)
							* CFrame.new(0, -legFit.size[2] / 2, 0)
							* MeshFix.of(leg)
					)
				end
			end
			local tail = dog.byName.DogTail
			if tail then
				local f = Config.ParkArt.Dog.DogTail
				table.insert(moveParts, tail)
				table.insert(
					moveCFrames,
					foot
						* CFrame.new(f.offset[1], f.offset[2], f.offset[3])
						* CFrame.Angles(0, math.sin(now * L.dog.wag) * 0.6, 0)
						* MeshFix.of(tail)
				)
			end
		end
	end
	-- picnics
	for _, p in picnics do
		if not p.on then
			continue
		end
		local foot = CFrame.new(p.x, Config.City.ground.y + 0.02, p.z) * CFrame.Angles(0, math.rad(p.ry), 0)
		if p.look then
			put(p.look, foot)
		end
		for k, person in p.people do
			local body = person.body
			if body then
				local side = if k == 1 then -1.4 else 1.4
				local pos = foot * CFrame.new(side, 0, if k == 1 then 0.4 else -0.6)
				local yaw = math.rad(p.ry) + (if k == 1 then math.rad(100) else math.rad(-80))
				placeBody(body, pos.X, pos.Y, pos.Z, yaw, body.rig.layout.ground * 0.52)
				sit(body.rig, math.sin(now * 1.3 + k))
			end
		end
		local kite = p.kite
		if kite then
			-- the line from the first sitter's hand up to the kite, which faces back down it and banks as it swoops
			local hand = (foot * CFrame.new(-1.4, 2.2, 0.4)).Position
			local dx, dy, dz, bank = LifePlan.kite(KT, now, p.u * 6.28, p.u, p.v)
			local kpos = hand + Vector3.new(dx, dy, dz)
			local cf = CFrame.lookAt(kpos, hand) * CFrame.Angles(0, 0, bank)
			table.insert(roots, kite.part)
			table.insert(rootCFrames, cf)
			kite.hand.WorldPosition = hand
			-- the tail streams downwind under the kite, its bows rippling (the beam's curve)
			local wx, wz = KT.wind[1], KT.wind[2]
			local foot2 = cf * Vector3.new(0, -KT.size[2] / 2, 0)
			kite.tailEnd.WorldPosition = foot2 + Vector3.new(wx * 4, -KT.tailLength, wz * 4)
			local wig = math.sin(now * 5 + p.u * 9) * 1.4
			kite.beams[2].CurveSize0 = wig
			kite.beams[2].CurveSize1 = -wig
		end
	end
	-- buskers
	for _, b in buskers do
		local body = b.on and b.person.body
		if not body then
			continue
		end
		local yaw = math.rad(b.ry)
		placeBody(body, b.x, Config.City.ground.y + 0.4, b.z, yaw, 0)
		strum(body.rig, now + b.x)
		local face = CFrame.new(b.x, Config.City.ground.y + 0.4, b.z) * CFrame.Angles(0, yaw, 0)
		if b.case then
			put(b.case, face * CFrame.new(0.4, 0, -2.4) * CFrame.Angles(0, math.rad(80), 0))
		end
		if b.guitar then
			-- held across the body: the neck up to the left
			local torso = body.rig.layout.ground + 0.2
			put(b.guitar, face * CFrame.new(0.1, torso - 1.4, -0.75) * CFrame.Angles(0, 0, math.rad(58)))
		end
	end
	-- ducks: little loops round their spot; a hero or a bang near scatters them out of the way for a while
	local D = L.duck
	for _, d in ducks do
		local look = d.look
		if not look then
			continue
		end
		local scared = now - bang.t < 1 and dist2(d.x, d.z, bang.at) < D.scare * D.scare * 4
		for _, h in list do
			if dist2(d.x, d.z, h) < D.scare * D.scare and h.Y < d.y + 12 then
				scared = true
				d.fx, d.fz = d.x - h.X, d.z - h.Z
			end
		end
		if scared and d.fleeUntil < now then
			d.fleeUntil = now + D.back
			if d.fx == 0 and d.fz == 0 then
				d.fx, d.fz = d.x - bang.at.X, d.z - bang.at.Z
			end
			AudioController.playSpec(P.sounds.quack, Vector3.new(d.x, d.y, d.z))
		end
		local x, z, yaw
		if d.fleeUntil > now then
			local m = math.max(math.sqrt(d.fx * d.fx + d.fz * d.fz), 0.01)
			local k = math.min(1, (D.back - (d.fleeUntil - now)) / 3)
			x, z = d.x + d.fx / m * D.flee * 3 * k, d.z + d.fz / m * D.flee * 3 * k
			yaw = math.atan2(-d.fx, -d.fz)
		else
			d.a += dt * D.turn * D.speed / 3
			x, z = d.x + math.cos(d.a) * 3, d.z + math.sin(d.a) * 3
			yaw = math.atan2(math.sin(d.a), -math.cos(d.a))
		end
		put(look, CFrame.new(x, d.y - 0.15 + math.sin(now * 2 + d.a) * 0.05, z) * CFrame.Angles(0, yaw, 0))
	end
	-- rowboats
	local BO = L.boat
	for _, b in boats do
		local look = b.look
		if not look then
			continue
		end
		b.rock = math.max(0, b.rock - dt * 0.15)
		local t = now + b.x * 0.1
		local x, z = b.x, b.z
		if not b.docked then
			x += math.cos(t * 0.05) * BO.drift * 4
			z += math.sin(t * 0.05) * BO.drift * 4
		end
		local roll = math.sin(t * 1.3) * (BO.rock + b.rock)
		put(
			look,
			CFrame.new(x, P.lake.level - 0.55 + math.sin(t * 1.7) * BO.bob, z)
				* CFrame.Angles(0, math.rad(b.ry) + (if b.docked then 0 else t * 0.02), 0)
				* CFrame.Angles(math.sin(t * 0.9) * 0.03, 0, roll)
		)
	end
	-- the carousel
	if #spin > 0 then
		local C = L.carousel
		local a = now * C.rpm * 2 * math.pi / 60
		local c = park.carousel
		local turn = CFrame.new(c.x, 0, c.z) * CFrame.Angles(0, a, 0) * CFrame.new(-c.x, 0, -c.z)
		for _, s in spin do
			local cf = turn * s.base
			if s.horses then
				cf = CFrame.new(0, math.sin(a * 6) * C.horseBob * 0.4, 0) * cf
			end
			table.insert(moveParts, s.part)
			table.insert(moveCFrames, cf)
		end
	end
	-- the fountains: the jets play; a burst throws a tall geyser for a while
	for _, j in jets do
		if j.on and j.emitters[1] then
			local bursting = j.burstUntil > now
			local J = L.jet
			local top = j.emitters[1]
			top.Rate = if bursting then L.burst.rate else (if j.f.terrace then J.terraceRate else J.rate)
			local v = if bursting then L.burst.speed else J.speed
			top.Speed = NumberRange.new(v * 0.85, v)
			top.SpreadAngle = if bursting then Vector2.new(14, 14) else Vector2.new(7, 7)
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if #roots > 0 then
		Workspace:BulkMoveTo(roots, rootCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------- set up
local function addSpin(p: Instance)
	if p:IsA("BasePart") then
		table.insert(
			spin,
			{ part = p, base = p.CFrame, horses = p:GetAttribute("ParkPiece") == "CarouselHorses" }
		)
	end
end

function ParkLife.init()
	task.spawn(function()
		local a = ReplicatedStorage:WaitForChild("Art", 30)
		art = a and a:FindFirstChild(P.set)
		park = ParkLayout.build(Config)
		local f = Instance.new("Folder")
		f.Name = "ParkLife"
		f.Parent = Workspace
		folder = f
		-- the routes the joggers and walkers take: the loops (the track, the drives)
		for _, r in park.routes do
			if r.loop and r.length > 100 then
				local cum = { 0 }
				local n = #r.pts
				for i = 1, n do
					local p, q = r.pts[i], r.pts[i % n + 1]
					table.insert(cum, cum[#cum] + math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2))
				end
				table.insert(runs, { pts = r.pts, cum = cum, length = cum[#cum] })
			end
		end
		local high = L.budget.high
		local id = 0
		for k = 1, high.joggers do
			id += 1
			local run = runs[(k - 1) % #runs + 1]
			local dir = if k % 2 == 0 then -1 else 1
			table.insert(movers, {
				person = { id = id },
				run = run,
				s0 = run.length * ((Rng.hash(P.seed, k, 31) % 1000) / 1000) * dir,
				speed = L.jog.speed * dir * (0.9 + (k % 3) * 0.08),
				jog = true,
				coat = nil,
				on = false,
			})
		end
		for k = 1, high.walkers do
			id += 1
			local run = runs[(k + 1) % #runs + 1]
			table.insert(movers, {
				person = { id = id },
				run = run,
				s0 = run.length * ((Rng.hash(P.seed, k, 32) % 1000) / 1000),
				speed = L.walk.speed * (if k % 2 == 0 then -1 else 1),
				jog = false,
				coat = if k <= high.dogs then P.dogCoats[(k - 1) % #P.dogCoats + 1] else nil,
				on = false,
			})
		end
		for k, s in park.spots.picnics do
			id += 2
			table.insert(picnics, {
				x = s[1],
				z = s[2],
				ry = s[3],
				people = { { id = id - 1 }, { id = id } },
				on = false,
				flies = (Rng.hash(P.seed, k, 47) % 1000) / 1000 < L.kite.chance,
				u = (Rng.hash(P.seed, k, 48) % 1000) / 1000,
				v = (Rng.hash(P.seed, k, 49) % 1000) / 1000,
				tint = Rng.hash(P.seed, k, 50) % #L.kite.tints + 1,
			})
			if k >= 40 then
				break
			end
		end
		for _, s in park.spots.buskers do
			id += 1
			table.insert(buskers, { x = s[1], z = s[2], ry = s[3] or 0, person = { id = id }, on = false })
		end
		for k, s in park.spots.ducks do
			table.insert(ducks, {
				x = s[1],
				z = s[2],
				y = s[3],
				a = k,
				fleeUntil = 0,
				fx = 0,
				fz = 0,
				on = false,
				kind = Rng.hash(P.seed, k, 41) % #P.duckKinds + 1,
			})
		end
		for _, s in park.spots.boats do
			table.insert(boats, { x = s[1], z = s[2], ry = s[3], docked = false, rock = 0, on = false })
		end
		for _, s in park.spots.docked do
			table.insert(boats, { x = s[1], z = s[2], ry = s[3], docked = true, rock = 0, on = false })
		end
		for _, fnt in park.fountains do
			table.insert(jets, { f = fnt, part = nil, emitters = {}, burstUntil = 0, on = false })
		end
		local S = P.sounds.busk
		local snd = Instance.new("Sound")
		snd.Name = "ParkBusk"
		snd.SoundId = if S.asset ~= 0 then "rbxassetid://" .. S.asset else S.fallback
		snd.Volume = L.busk.volume * S.volume / 0.2
		snd.PlaybackSpeed = S.pitch
		snd.Looped = true
		snd.RollOffMaxDistance = L.busk.range
		-- in the Effects mix (list-combat 2026-11-20): every sound sits under a group, so the Sound effects
		-- setting turns it down like the rest
		local fx = game:GetService("SoundService"):FindFirstChild("Effects")
		local amb = fx and fx:FindFirstChild("Ambience")
		if amb and amb:IsA("SoundGroup") then
			snd.SoundGroup = amb
		elseif fx and fx:IsA("SoundGroup") then
			snd.SoundGroup = fx
		end
		buskSound = snd
		for _, p in CollectionService:GetTagged("ParkSpin") do
			addSpin(p)
		end
		CollectionService:GetInstanceAddedSignal("ParkSpin"):Connect(addSpin)
		CollectionService:GetInstanceRemovedSignal("ParkSpin"):Connect(function(p: Instance)
			for i = #spin, 1, -1 do
				if spin[i].part == p then
					table.remove(spin, i)
				end
			end
		end)
		local prev = BuildingFx.onImpact
		BuildingFx.onImpact = function(center: Vector3, radius: number, kind: number)
			if prev then
				prev(center, radius, kind)
			end
			onImpact(center, radius, kind)
		end
		RunService.Heartbeat:Connect(FrameProf.wrap("ParkLife", step))
	end)
end

-- how many of each are on now (the Dev panel and the tests' log)
function ParkLife.counts(): { [string]: number }
	local out =
		{ movers = 0, picnics = 0, buskers = 0, ducks = 0, boats = 0, jets = 0, kites = 0, spin = #spin }
	for _, m in movers do
		out.movers += if m.on then 1 else 0
	end
	for _, p in picnics do
		out.picnics += if p.on then 1 else 0
		out.kites += if p.kite then 1 else 0
	end
	for _, b in buskers do
		out.buskers += if b.on then 1 else 0
	end
	for _, d in ducks do
		out.ducks += if d.on then 1 else 0
	end
	for _, b in boats do
		out.boats += if b.on then 1 else 0
	end
	for _, j in jets do
		out.jets += if j.on then 1 else 0
	end
	return out
end

return ParkLife
