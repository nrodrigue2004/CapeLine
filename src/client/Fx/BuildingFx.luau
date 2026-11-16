-- BuildingFx: draws hub destruction on the device (spec: World > Destruction; the server stores only each
-- building's state, clients draw the rest).
-- * Building states come from BuildingSnapshot (asked for once the listeners are up) and 2 Hz BuildingDiff
--   batches. Each wreckable building is a model named Building_<id> under Workspace.City; it can stream in
--   and out, so its look is applied whenever it arrives.
-- * Damaged: the real body hides (LocalTransparencyModifier) and the Chunker's chunks stand in its place
--   with 4 to 8 upper chunks missing. Live, those chunks fall and tumble away.
-- * Collapsed: a 6 s collapse (a shake, then the chunks drop floor by floor into a dust cloud) leaves the
--   rubble heap. Joining late shows the heap at once.
-- * Repair drones fly to their building and hover over it while they work; the building pops back whole.
-- * BuildingImpact: a crater where a slam or landing hits the ground, facade cracks where a blast hits a wall
--   (outskirts houses and the Foundry crack too but never fall). Craters and cracks share the device
--   preset's crater count and last 30 s; loose chunks share the debris budget.
-- PLACEHOLDER ART: chunks, rubble and drones are plain boxes; cracks are thin dark bars. Dust uses the
-- engine's built-in smoke texture.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Chunker = require(Shared:WaitForChild("Chunker"))
local BuildingState = require(Shared:WaitForChild("BuildingState"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Juice = require(script.Parent.Juice)
local DebrisBudget = require(script.Parent.DebrisBudget)

local BuildingFx = {}

local D = Config.Destruction
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local CRACK_COLOR = Color3.fromRGB(34, 32, 36)
local DRONE_COLOR = Color3.fromRGB(255, 196, 64)
local DRONE_LIGHT = Color3.fromRGB(120, 230, 255)

type Rec = { id: number, x: number, z: number, sx: number, sz: number, base: number, top: number }
type Drawn = { state: number, model: Model }
type Fall = {
	id: number,
	t0: number,
	parts: { { part: BasePart, from: CFrame, delay: number, drop: number, tilt: Vector3 } },
	dust: BasePart?,
	done: boolean,
}

local records: { [number]: Rec } = {}
local state: { [number]: number } = {}
local models: { [number]: Model } = {}
local drawn: { [number]: Drawn } = {}
local falls: { Fall } = {}
local marks: { BasePart | Model } = {}
local drones: { [number]: { model: Model, conn: RBXScriptConnection? } } = {}
local liveDust = 0
local folder: Folder
local synced = false

local function newPart(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	return p
end

-- The colour and material of a building's biggest part (its body)
local function bodyLook(model: Model?): (Color3, Enum.Material)
	local best, bestV = nil, 0
	if model then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				local v = p.Size.X * p.Size.Y * p.Size.Z
				if v > bestV then
					best, bestV = p, v
				end
			end
		end
	end
	if best then
		return best.Color, best.Material
	end
	return Color3.fromRGB(170, 160, 150), Enum.Material.Concrete
end

local function setHidden(model: Model?, hidden: boolean)
	if not model then
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function clearDrawn(id: number)
	local d = drawn[id]
	if d then
		d.model:Destroy()
		drawn[id] = nil
	end
	for _, f in falls do
		if f.id == id then
			f.done = true
		end
	end
end

-- A slight per-chunk shade so the stand-in reads as broken blocks, not one box
local function shade(color: Color3, i: number): Color3
	local k = ((i * 37) % 7) / 7
	return color:Lerp(Color3.new(0, 0, 0), 0.04 + k * 0.1)
end

local function drawChunks(rec: Rec, skip: { [number]: boolean }): (Model, { Chunker.Chunk }, { BasePart })
	local color, material = bodyLook(models[rec.id])
	local m = Instance.new("Model")
	m.Name = "Wreck_" .. rec.id
	local chunks = Chunker.split(D, rec)
	local parts: { BasePart } = {}
	for i, c in chunks do
		if not skip[i] then
			local p = newPart(
				Vector3.new(c.sx - 0.1, c.sy - 0.1, c.sz - 0.1),
				CFrame.new(c.cx, c.cy, c.cz),
				shade(color, i),
				material
			)
			p.CanCollide = true
			p.CastShadow = true
			p.Parent = m
			parts[i] = p
		end
	end
	return m, chunks, parts
end

local function drawRubble(rec: Rec): Model
	local color, material = bodyLook(models[rec.id])
	local m = Instance.new("Model")
	m.Name = "Rubble_" .. rec.id
	for i, r in Chunker.rubble(D, rec, rec.id) do
		local p = newPart(
			Vector3.new(r.sx, r.sy, r.sz),
			CFrame.new(r.cx, r.cy, r.cz) * CFrame.Angles(math.rad(r.rx), math.rad(r.ry), math.rad(r.rz)),
			shade(color:Lerp(Color3.fromRGB(90, 86, 82), 0.35), i),
			material
		)
		p.CanCollide = true
		p.Parent = m
	end
	return m
end

-- Loose chunks tumbling off a building (live Damaged), within the debris budget
local function shed(rec: Rec, chunks: { Chunker.Chunk }, which: { [number]: boolean })
	local color, material = bodyLook(models[rec.id])
	local list = {}
	for i in which do
		table.insert(list, i)
	end
	local n = DebrisBudget.lease(#list, 4)
	for k = 1, n do
		local c = chunks[list[k]]
		local p = newPart(
			Vector3.new(c.sx, c.sy, c.sz) * 0.9,
			CFrame.new(c.cx, c.cy, c.cz),
			shade(color, k),
			material
		)
		p.Anchored = false
		p.CanCollide = true
		local out = Vector3.new(c.cx - rec.x, 0, c.cz - rec.z)
		out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(1, 0, 0)
		p.AssemblyLinearVelocity = out * (10 + math.random() * 10) + Vector3.new(0, 6, 0)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			* 4
		p.Parent = folder
		task.delay(3, function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end)
		task.delay(4, function()
			p:Destroy()
		end)
	end
end

local function dustCloud(rec: Rec, seconds: number): BasePart?
	if liveDust >= QualityController.preset.emitters then
		return nil
	end
	liveDust += 1
	local p = newPart(
		Vector3.new(rec.sx + 8, 2, rec.sz + 8),
		CFrame.new(rec.x, rec.base + 1, rec.z),
		Color3.new(1, 1, 1)
	)
	p.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = DUST_TEXTURE
	e.Shape = Enum.ParticleEmitterShape.Box
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new(Color3.fromRGB(196, 186, 172))
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 18) })
	e.Lifetime = NumberRange.new(2.5, 4)
	e.Speed = NumberRange.new(6, 14)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Rate = 24
	e.Drag = 1.5
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Parent = p
	p.Parent = folder
	task.delay(seconds, function()
		e.Enabled = false
	end)
	task.delay(seconds + 4, function()
		liveDust -= 1
		p:Destroy()
	end)
	return p
end

local function nearMe(x: number, z: number, r: number): boolean
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (Vector3.new(x, root.Position.Y, z) - root.Position).Magnitude < r
end

-- Draw a building's look for its state. live: the change just happened (animate it)
local function apply(id: number, live: boolean)
	local rec = records[id]
	local model = models[id]
	if not rec then
		return
	end
	local s = state[id] or 0
	local d = drawn[id]
	if d and d.state == s then
		setHidden(model, s ~= BuildingState.INTACT)
		return
	end
	if not model then
		clearDrawn(id) -- streamed out: drawn again when it comes back
		return
	end
	clearDrawn(id)
	if s == BuildingState.INTACT then
		setHidden(model, false)
		if live then
			local pop = newPart(
				Vector3.new(rec.sx, rec.top - rec.base, rec.sz),
				CFrame.new(rec.x, (rec.base + rec.top) / 2, rec.z),
				DRONE_LIGHT,
				Enum.Material.Neon
			)
			pop.Transparency = 0.6
			pop.Parent = folder
			TweenService
				:Create(pop, TweenInfo.new(0.6), { Transparency = 1, Size = pop.Size + Vector3.new(4, 4, 4) })
				:Play()
			task.delay(0.7, function()
				pop:Destroy()
			end)
		end
		return
	end
	setHidden(model, true)
	if s == BuildingState.DAMAGED then
		local chunks = Chunker.split(D, rec)
		local gone = Chunker.fallen(D, chunks, id)
		local m = drawChunks(rec, gone)
		m.Parent = folder
		drawn[id] = { state = s, model = m }
		if live then
			shed(rec, chunks, gone)
			dustCloud(rec, 1.5)
			if nearMe(rec.x, rec.z, 150) then
				CameraController.shake(0.25, 0.4)
			end
		end
		return
	end
	-- Collapsed
	if not live then
		local m = drawRubble(rec)
		m.Parent = folder
		drawn[id] = { state = s, model = m }
		return
	end
	local m, chunks, parts = drawChunks(rec, {})
	m.Parent = folder
	drawn[id] = { state = s, model = m }
	local rows = 0
	for _, c in chunks do
		rows = math.max(rows, c.row)
	end
	local fall: Fall = { id = id, t0 = os.clock(), parts = {}, dust = nil, done = false }
	local fallTime = D.collapseTime - 1.2
	for i, p in parts do
		local c = chunks[i]
		table.insert(fall.parts, {
			part = p,
			from = p.CFrame,
			-- the ground floor gives first, the floors above pancake onto it
			delay = 0.8 + (c.row - 1) / math.max(rows, 1) * fallTime * 0.35,
			drop = c.cy - rec.base + c.sy * 0.5,
			tilt = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.9,
		})
	end
	fall.dust = dustCloud(rec, D.collapseTime)
	table.insert(falls, fall)
	Juice.fire("collapse", Vector3.new(rec.x, rec.base, rec.z), { mine = nearMe(rec.x, rec.z, 80) })
	if nearMe(rec.x, rec.z, 250) then
		CameraController.shake(D.collapseTime * 0.5, 0.6)
	end
end

local function stepFalls()
	local now = os.clock()
	local fallTime = D.collapseTime - 1.2
	for i = #falls, 1, -1 do
		local f = falls[i]
		local t = now - f.t0
		if not f.done then
			for _, c in f.parts do
				if t < c.delay then
					-- the shake before it goes
					local j = (1 - t / c.delay) * 0.15 + 0.1
					c.part.CFrame = c.from
						* CFrame.new((math.random() - 0.5) * j, 0, (math.random() - 0.5) * j)
				else
					local k = math.clamp((t - c.delay) / (fallTime * 0.65), 0, 1)
					local eased = k * k
					c.part.CFrame = (c.from - Vector3.new(0, c.drop * eased, 0))
						* CFrame.Angles(c.tilt.X * eased, 0, c.tilt.Z * eased)
				end
			end
		end
		if f.done or t >= D.collapseTime then
			table.remove(falls, i)
			if not f.done then
				local d = drawn[f.id]
				if d and d.state == BuildingState.COLLAPSED then
					d.model:Destroy()
					local rec = records[f.id]
					local m = drawRubble(rec)
					m.Parent = folder
					drawn[f.id] = { state = d.state, model = m }
				end
			end
		end
	end
end

-- Craters and cracks share the preset's crater count
local function addMark(m: BasePart | Model)
	m.Parent = folder
	table.insert(marks, m)
	while #marks > QualityController.preset.craters do
		local old = table.remove(marks, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(D.crater.life, function()
		local i = table.find(marks, m)
		if i then
			table.remove(marks, i)
		end
		m:Destroy()
	end)
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local city = Workspace:FindFirstChild("City")
	params.FilterDescendantsInstances = if city then { city } else {}
	return params
end

-- A frame at pos whose UpVector is the surface normal
local function surface(pos: Vector3, normal: Vector3): CFrame
	local side = normal:Cross(Vector3.zAxis)
	if side.Magnitude < 0.1 then
		side = normal:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(pos, side.Unit, normal.Unit)
end

local function crater(center: Vector3, radius: number)
	Juice.fire("crater", center, { mine = false })
	local hit =
		Workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(0, -(radius + 24), 0), rayParams())
	if not hit then
		return
	end
	local r = math.clamp(radius * 0.6, D.crater.radius * 0.6, D.crater.radius * 2)
	local m = Instance.new("Model")
	m.Name = "Crater"
	local up = surface(hit.Position, hit.Normal)
	local pit = newPart(
		Vector3.new(0.12, r * 2, r * 2),
		up * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)),
		CRACK_COLOR,
		Enum.Material.Slate
	)
	pit.Shape = Enum.PartType.Cylinder
	pit.Transparency = 0.25
	pit.Parent = m
	local color = if hit.Instance:IsA("BasePart") then hit.Instance.Color else Color3.fromRGB(120, 116, 110)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2 + math.random() * 0.3
		local s = r * (0.25 + math.random() * 0.2)
		local rock = newPart(
			Vector3.new(s, s * 0.5, s * 0.8),
			up
				* CFrame.new(math.cos(a) * r, s * 0.15, math.sin(a) * r)
				* CFrame.Angles(math.random() - 0.5, a, math.random() - 0.5),
			color:Lerp(CRACK_COLOR, 0.25),
			Enum.Material.Slate
		)
		rock.Parent = m
	end
	addMark(m)
end

-- A zigzag crack drawn flat on a wall at a ray hit
local function crackAt(hit: RaycastResult, size: number)
	local m = Instance.new("Model")
	m.Name = "Crack"
	local face = CFrame.lookAlong(hit.Position + hit.Normal * 0.06, -hit.Normal)
	local function bar(a: Vector2, b: Vector2, w: number)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local ang = math.atan2(b.Y - a.Y, b.X - a.X)
		local p = newPart(
			Vector3.new(len, w, 0.05),
			face * CFrame.new(mid.X, mid.Y, 0) * CFrame.Angles(0, 0, ang),
			CRACK_COLOR,
			Enum.Material.Slate
		)
		p.Parent = m
	end
	for arm = 1, 4 do
		local a = arm / 4 * math.pi * 2 + math.random() * 0.8
		local from = Vector2.zero
		local steps = 3
		for s = 1, steps do
			local reach = size * s / steps
			local jitter = (math.random() - 0.5) * 0.7
			local to = Vector2.new(math.cos(a + jitter), math.sin(a + jitter)) * reach
			bar(from, to, 0.35 * (1 - (s - 1) / steps) + 0.1)
			from = to
		end
	end
	addMark(m)
end

local function cracks(center: Vector3, radius: number)
	local params = rayParams()
	local found = 0
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a)) * (radius + 8)
		local hit = Workspace:Raycast(center, dir, params)
		if hit and math.abs(hit.Normal.Y) < 0.5 then
			crackAt(hit, math.clamp(radius * 0.35, 2.5, 8))
			found += 1
			if found >= 3 then
				break
			end
		end
	end
end

local function impact(center: Vector3, radius: number, kind: number)
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	if kind == 1 then
		crater(center, radius)
	end
	cracks(center, radius)
end

-- Repair drones: fly in over the building and hover while working (PLACEHOLDER ART)
local function droneModel(): Model
	local m = Instance.new("Model")
	m.Name = "RepairDrone"
	local body = newPart(Vector3.new(2.4, 1.2, 2.4), CFrame.new(), DRONE_COLOR, Enum.Material.SmoothPlastic)
	body.Name = "Body"
	body.Parent = m
	m.PrimaryPart = body
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local rotor = newPart(
			Vector3.new(0.15, 1.6, 1.6),
			CFrame.new(s[1] * 1.6, 0.6, s[2] * 1.6) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(40, 42, 50)
		)
		rotor.Shape = Enum.PartType.Cylinder
		rotor.Transparency = 0.4
		rotor.Parent = m
	end
	local eye = newPart(Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, -0.7, 0), DRONE_LIGHT, Enum.Material.Neon)
	eye.Shape = Enum.PartType.Ball
	eye.Parent = m
	local beam = newPart(Vector3.new(0.4, 1, 0.4), CFrame.new(0, -1, 0), DRONE_LIGHT, Enum.Material.Neon)
	beam.Name = "Beam"
	beam.Transparency = 0.5
	beam.Parent = m
	return m
end

local function droneJob(droneId: number, bid: number, seconds: number)
	local old = drones[droneId]
	if old then
		if old.conn then
			old.conn:Disconnect()
		end
		old.model:Destroy()
		drones[droneId] = nil
	end
	local rec = records[bid]
	if not rec or seconds <= 0 or not nearMe(rec.x, rec.z, QualityController.preset.streamRadius) then
		return
	end
	local m = droneModel()
	m.Parent = folder
	local job = { model = m, conn = nil :: RBXScriptConnection? }
	drones[droneId] = job
	local t0 = os.clock()
	local hoverY = rec.top + 10
	local start = Vector3.new(rec.x + 120, hoverY + 60, rec.z + 40)
	local beam = m:FindFirstChild("Beam") :: BasePart
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local root = (m.PrimaryPart :: BasePart).CFrame
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p ~= beam then
			table.insert(parts, p)
			table.insert(offsets, root:ToObjectSpace(p.CFrame))
		end
	end
	job.conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local pos: Vector3
		if t < 2 then
			local k = t / 2
			pos = start:Lerp(Vector3.new(rec.x, hoverY, rec.z), 1 - (1 - k) ^ 2)
		elseif t < seconds then
			local a = t * 0.8 + droneId
			local r = math.min(rec.sx, rec.sz) * 0.35
			pos =
				Vector3.new(rec.x + math.cos(a) * r, hoverY + math.sin(t * 2) * 0.6, rec.z + math.sin(a) * r)
		else
			pos = Vector3.new(rec.x, hoverY + (t - seconds) * 30, rec.z)
		end
		local cf = CFrame.new(pos) * CFrame.Angles(0, t * 0.5, 0)
		for i, p in parts do
			p.CFrame = cf * offsets[i]
		end
		local working = t >= 2 and t < seconds
		local len = if working then pos.Y - rec.top else 0.1
		beam.Size = Vector3.new(0.4, math.max(len, 0.1), 0.4)
		beam.CFrame = CFrame.new(pos - Vector3.new(0, len / 2 + 0.5, 0))
		beam.Transparency = if working then 0.4 + math.sin(t * 10) * 0.15 else 1
		if t > seconds + 3 then
			if job.conn then
				job.conn:Disconnect()
			end
			m:Destroy()
			if drones[droneId] == job then
				drones[droneId] = nil
			end
		end
	end)
end

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("BuildingId")
	if type(id) ~= "number" then
		return
	end
	models[id] = model
	if synced then
		task.defer(apply, id, false)
	end
end

local function unregister(model: Instance)
	local id = model:GetAttribute("BuildingId")
	if type(id) == "number" and models[id] == model then
		models[id] = nil
		clearDrawn(id)
	end
end

local function loadRecords(): boolean
	local value = ReplicatedStorage:FindFirstChild("WorldInfo")
	if not (value and value:IsA("StringValue") and value.Value ~= "") then
		return false
	end
	local ok, info = pcall(HttpService.JSONDecode, HttpService, value.Value)
	if not ok or type(info) ~= "table" or type(info.buildings) ~= "table" then
		return false
	end
	for _, row in info.buildings do
		records[row[1]] =
			{ id = row[1], x = row[2], z = row[3], sx = row[4], sz = row[5], base = row[6], top = row[7] }
	end
	return true
end

-- Building states right now (for the map and tests)
function BuildingFx.state(id: number): number
	return state[id] or 0
end

function BuildingFx.init()
	folder = Instance.new("Folder")
	folder.Name = "CityFx"
	folder.Parent = Workspace
	Net.listen("BuildingSnapshot", function(data: any)
		if type(data) ~= "table" or type(data.s) ~= "buffer" then
			return
		end
		local list = BuildingState.unpack(data.s, math.clamp(tonumber(data.n) or 0, 0, 1024))
		for id, s in list do
			state[id] = s
		end
		synced = true
		for id in models do
			apply(id, false)
		end
		for _, job in data.dr or {} do
			droneJob(job[1], job[2], job[3])
		end
	end)
	Net.listen("BuildingDiff", function(data: any)
		if type(data) ~= "table" then
			return
		end
		local d = data.d or {}
		for i = 1, #d - 1, 2 do
			local id, s = d[i], d[i + 1]
			if state[id] ~= s then
				state[id] = s
				if synced then
					apply(id, true)
				end
			end
		end
		for _, job in data.dr or {} do
			droneJob(job[1], job[2], job[3])
		end
	end)
	Net.listen("BuildingImpact", impact)
	RunService.Heartbeat:Connect(stepFalls)
	task.spawn(function()
		while not loadRecords() do
			task.wait(0.5)
		end
		local city = Workspace:WaitForChild("City")
		city.DescendantAdded:Connect(register)
		city.DescendantRemoving:Connect(unregister)
		for _, m in city:GetDescendants() do
			register(m)
		end
		Net.send("BuildingSync")
	end)
end

return BuildingFx
