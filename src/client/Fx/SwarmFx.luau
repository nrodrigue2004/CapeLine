--!strict
-- SwarmFx: the Swarm Queen's drones on this device (bosses-3, nate 2026-11-20: "thousands of Crane drones (visually;
-- one networked body plus client-side swarm instancing within phone budgets) that form fists, walls and a giant body").
-- The server only runs the hive core and its three formation nodes (BossSim); WorldFx hands this the core's frame, the
-- phase, which formations stand and whether the core is exposed, and every drone flies to its spot in
-- Shared.SwarmShapes: fists, then a wall, then a giant body; a broken formation's drones drop and crawl, an attack pulls
-- a formation out to where it lands over its warning. DRAFT look until nate OKs it.
-- Budget (Config.Boss.bosses.SwarmQueen.swarm by preset): 90 / 180 / 320 drone meshes (one shared mesh, Art.Bosses2's
-- SwarmQueen_Drone placed through Shared.MeshFix; a small part until it is imported, PLACEHOLDER ART) moved in one
-- BulkMoveTo at 20 / 30 / 60 Hz, plus a particle haze of far specks so the swarm reads as thousands. Past `far` studs
-- from the camera the drones hold still. Draw only: nothing here is sent anywhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SwarmShapes = require(Shared:WaitForChild("SwarmShapes"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local SwarmFx = {}

local CFG = Config.Boss.bosses.SwarmQueen
local DRONE_COLOR = Color3.fromRGB(54, 58, 72)
local LENS = Color3.fromRGB(255, 150, 50)

export type Swarm = {
	folder: Folder,
	parts: { BasePart },
	pos: { Vector3 },
	cfs: { CFrame },
	haze: ParticleEmitter?,
	hazePart: Part?,
	t: number,
	acc: number,
	strikes: { { group: number, start: number, warn: number, points: { Vector3 } } },
}

local function droneMesh(): MeshPart?
	local art = ReplicatedStorage:FindFirstChild("Art")
	local fit = Config.BossArt.SwarmQueen
	local lib = art and art:FindFirstChild(if fit and fit.set then fit.set else "Bosses2")
	local m = lib and lib:FindFirstChild("SwarmQueen_Drone", true)
	return if m and m:IsA("MeshPart") then m else nil
end

-- One drone: the imported mesh (its size from Config.BossArt), or a small dark part with an orange lens colour
local function makeDrone(src: MeshPart?, low: boolean, parent: Instance): BasePart
	local p: BasePart
	if src then
		local m = MeshFix.clone(src)
		local row = Config.BossArt.SwarmQueen and Config.BossArt.SwarmQueen.drone
		if row then
			local s = row.Drone.size
			m.Size = Vector3.new(s[1], s[2], s[3]) * 1.4
		end
		if low then
			-- phones on low: no texture set per drone (one colour), the mesh only
			for _, c in m:GetChildren() do
				c:Destroy()
			end
			m.Color = DRONE_COLOR
		end
		p = m
	else
		local b = Instance.new("Part") -- PLACEHOLDER ART until Art.Bosses2 holds the drone mesh
		b.Size = Vector3.new(3, 0.8, 3)
		b.Color = DRONE_COLOR
		b.Material = Enum.Material.SmoothPlastic
		p = b
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Name = "Drone"
	p.Parent = parent
	return p
end

-- Start drawing a swarm (the boss is built): the preset's drones in the WorldFx folder, and the haze
function SwarmFx.attach(parent: Instance, at: CFrame): Swarm
	local folder = Instance.new("Folder")
	folder.Name = "Swarm"
	folder.Parent = parent
	local preset = QualityController.name
	local n, haze = SwarmShapes.budget(CFG, preset)
	local src = droneMesh()
	local sw: Swarm = {
		folder = folder,
		parts = {},
		pos = {},
		cfs = {},
		haze = nil,
		hazePart = nil,
		t = 0,
		acc = 0,
		strikes = {},
	}
	for i = 1, n do
		local x, y, z = SwarmShapes.target(i, n, "fists", 0, -30, { true, true, true }, false, nil)
		local p = makeDrone(src, preset == "low", folder)
		local pos = at * Vector3.new(x, y + 60, z) -- they arrive from above
		p.CFrame = CFrame.new(pos)
		table.insert(sw.parts, p)
		table.insert(sw.pos, pos)
		table.insert(sw.cfs, p.CFrame)
	end
	if haze > 0 then
		-- the far specks: one emitter on an invisible ball round the core (a haze of tiny dark drones with orange glints)
		local hp = Instance.new("Part")
		hp.Name = "SwarmHaze"
		hp.Shape = Enum.PartType.Ball
		hp.Size = Vector3.one * 70
		hp.Transparency = 1
		hp.Anchored = true
		hp.CanCollide = false
		hp.CanQuery = false
		hp.CanTouch = false
		hp.CFrame = at
		hp.Parent = folder
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = haze
		pe.Lifetime = NumberRange.new(CFG.swarm.hazeLife * 0.8, CFG.swarm.hazeLife * 1.2)
		pe.Speed = NumberRange.new(6, 16)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.9)
		pe.Color = ColorSequence.new(DRONE_COLOR, LENS)
		pe.LightEmission = 0.1
		pe.Shape = Enum.ParticleEmitterShape.Sphere
		pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		pe.Orientation = Enum.ParticleOrientation.FacingCamera
		pe.Parent = hp
		sw.haze = pe
		sw.hazePart = hp
	end
	return sw
end

-- An attack's warning: the formation it sends flies out to where it lands over the warning (world points)
function SwarmFx.attack(sw: Swarm, attackId: string, warn: number, points: { Vector3 })
	local g = SwarmShapes.strikeGroup(attackId)
	if g == nil or #points == 0 then
		return
	end
	if attackId == "DroneFist" then
		-- each fist takes one landing spot
		for k, p in points do
			table.insert(
				sw.strikes,
				{ group = (k - 1) % 2 + 1, start = os.clock(), warn = warn, points = { p } }
			)
		end
		return
	end
	table.insert(sw.strikes, { group = g, start = os.clock(), warn = warn, points = points })
end

-- One frame: core is the core's frame now, ground the ground's height, alive which formations stand
function SwarmFx.step(
	sw: Swarm,
	dt: number,
	core: CFrame,
	ground: number,
	phase: number,
	alive: { boolean },
	exposed: boolean
)
	sw.t += dt
	sw.acc += dt
	if sw.hazePart then
		sw.hazePart.CFrame = core
		if sw.haze then
			sw.haze.Enabled = not exposed
		end
	end
	local rate = CFG.swarm.rate[QualityController.name] or 30
	if sw.acc < 1 / rate then
		return
	end
	local step = sw.acc
	sw.acc = 0
	local cam = Workspace.CurrentCamera
	if cam and (cam.CFrame.Position - core.Position).Magnitude > CFG.swarm.far then
		return
	end
	local now = os.clock()
	-- the live strikes (still winding up, or just landed and flying back)
	local strikes: { SwarmShapes.Strike } = {}
	for k = #sw.strikes, 1, -1 do
		local s = sw.strikes[k]
		local f = (now - s.start) / math.max(s.warn, 0.1)
		if f > 1.4 then
			table.remove(sw.strikes, k)
		else
			local pts = {}
			for _, p in s.points do
				local l = core:PointToObjectSpace(p)
				table.insert(pts, { l.X, l.Y, l.Z })
			end
			-- out to the hit, then back after it
			local out = if f <= 1 then f else math.max(0, 1 - (f - 1) / 0.4)
			table.insert(strikes, { group = s.group, f = out, points = pts })
		end
	end
	local form = SwarmShapes.form(CFG, phase)
	local n = #sw.parts
	local groundRel = ground - core.Position.Y
	local k = math.min(1, step * 5)
	for i = 1, n do
		local strike: SwarmShapes.Strike? = nil
		local g = SwarmShapes.group(i)
		for _, s in strikes do
			if s.group == 0 or s.group == g then
				strike = s
				break
			end
		end
		local x, y, z = SwarmShapes.target(i, n, form, sw.t, groundRel, alive, exposed, strike)
		local want = core * Vector3.new(x, y, z)
		local from = sw.pos[i]
		local p = from:Lerp(want, if strike then math.min(1, step * 9) else k)
		sw.pos[i] = p
		local move = p - from
		sw.cfs[i] = if move.Magnitude > 0.05
			then CFrame.lookAt(p, p + move) * CFrame.Angles(math.rad(-20), 0, 0)
			else CFrame.new(p) * CFrame.Angles(0, sw.t + i, 0)
	end
	Workspace:BulkMoveTo(sw.parts, sw.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- The swarm is cleared (the boss is gone)
function SwarmFx.detach(sw: Swarm)
	sw.folder:Destroy()
	table.clear(sw.parts)
end

-- How many drone parts are drawn (Dev panel, tests)
function SwarmFx.count(sw: Swarm?): number
	return if sw then #sw.parts else 0
end

return SwarmFx
