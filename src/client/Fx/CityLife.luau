--!strict
-- CityLife: the living world on this device (2026-11-19, nate's playtest: "I like the way you added stuff for
-- interactivity but i need more. World needs to feel way more alive."; Config.Life, Shared.LifePlan). Looks only:
-- nothing here is on the server or changes play. Everything lives near the camera within the preset's budget
-- (Config.Life.budget low / medium / high) and moves in one Heartbeat under FrameProf ("CityLife").
-- * Traffic: cars (Art.Vehicles' sedans, hatches, taxis and bubble cars) drive the lane lines WorldInfo sends
--   (the lane dashes of Downtown and Uptown), on the right, stop at the lights on each crossing, keep their gap,
--   brake and honk for a hero in the road; a big hit nearby flings them (they tumble, then fade), the rest brake.
-- * Pigeons peck on the sidewalk corners and burst up and away from a hero who comes close or fast, or a bang.
-- * Steam rises from manholes in the roads and the roof vents (tag LifeSteam); a bang next to a manhole blows its
--   cover off in a puff.
-- * Flags wave on some roofs in their district's colours (Config.Life.flags), gone while their building is broken.
-- * News drones fly in to hover over a collapse or a big hit and film it, eye blinking, then leave.
-- * Shop backs glow warm from dusk to dawn (tag LifeShop).
-- * Street props knocked loose react (CityProps.onSmash): hydrants spray a geyser, vending machines spill cans,
--   bins and news boxes throw paper.
-- * lastBang(): where and when the last big hit was (CitizenRenderer: citizens cheer it).
-- alive-world (2026-11-20, nate: "the world must feel alive"):
-- * Traffic reacts to fights: a robot (EnemyRenderer) or a big hit near a car or the road ahead of it scares it
--   (Shared.LifePlan.feared): it stops, flashes its hazards (medium and high) and honks, then U-turns across the road
--   (LifePlan.uturn) and races away.
-- * Gulls circle over the Docks' cranes (tag LifeGulls) and wheel out and up from a hero or a bang.
-- * The Foundry's chimneys smoke (tag LifeSmoke), with a black burst after a big hit nearby.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MeshFix = require(Shared:WaitForChild("MeshFix"))
local LifePlan = require(Shared:WaitForChild("LifePlan"))
local SetPieceKit = require(Shared:WaitForChild("SetPieceKit"))
local VehicleKit = require(Shared:WaitForChild("VehicleKit"))
local DriveMath = require(Shared:WaitForChild("DriveMath"))

local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local CityProps = require(script.Parent.Parent.Controllers.CityProps)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local CitizenRenderer = require(script.Parent.Parent.Controllers.CitizenRenderer)
local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local BuildingFx = require(script.Parent.BuildingFx)
local DebrisBudget = require(script.Parent.DebrisBudget)

local L = Config.Life
local T = L.traffic
local CityLife = {}
CityLife.cars = 0 -- live counts (the Dev panel can show them)
CityLife.flocks = 0

local LIFE_TURN = MeshFix.turn(Config.Life.set) -- the import's turn of Art.Life (Shared.MeshFix, meshcheck)
local GROUND = Config.City.ground.y
local SIDEWALK = GROUND + 0.9

local folder: Folder? = nil
local lifeArt: Instance? = nil
local vehicleArt: Instance? = nil
local lanes: { LifePlan.Lane } = {}
local crossings: { { number } } = {}
local bang = { at = Vector3.zero, t = -math.huge }

local function budget(): any
	return L.budget[QualityController.name] or L.budget.medium
end

local function focus(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.Focus.Position else Vector3.zero
end

local function lifeSource(name: string): MeshPart?
	local src = lifeArt and lifeArt:FindFirstChild(name, true)
	return if src and src:IsA("MeshPart") then src else nil
end

-- One Art.Life foot-look piece as a visual-only part at cf (its fit offset and the import turn added)
local function lifePiece(
	look: string,
	name: string,
	color: Color3,
	mat: Enum.Material,
	parent: Instance
): BasePart?
	local src = lifeSource(name)
	local fit = Config.LifeArt[look] and Config.LifeArt[look][name]
	if not (src and fit) then
		return nil
	end
	local p = MeshFix.clone(src)
	for _, c in p:GetChildren() do
		c:Destroy()
	end
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(fit.size[1], fit.size[2], fit.size[3])
	p.Color = color
	p.Material = mat
	p.Parent = parent
	return p
end

local function offsetOf(look: string, name: string): CFrame
	local f = Config.LifeArt[look][name].offset
	return CFrame.new(f[1], f[2], f[3]) * LIFE_TURN
end

local function heroes(): { { pos: Vector3, vel: Vector3, air: boolean } }
	local out = {}
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local air = hum ~= nil and hum.FloorMaterial == Enum.Material.Air
			table.insert(out, { pos = root.Position, vel = root.AssemblyLinearVelocity, air = air })
		end
	end
	return out
end

---------------------------------------------------------------------------- traffic
type Car = {
	lane: number,
	dir: number,
	s: number,
	v: number,
	model: Model,
	parts: { BasePart },
	offs: { CFrame },
	fixes: { CFrame },
	wheels: { { i: number, r: number } },
	spin: number,
	hold: number, -- braking for a bang until this time
	honked: number,
	-- alive-world: scared by a fight (stopped since `scared`), mid U-turn (`turn` 0..1 from `turnDir`), fleeing until
	scared: number?,
	turn: number?,
	fleeing: number,
	hazards: { BasePart }?,
}
local cars: { Car } = {}
local carLooks: { string } = {}

local function vehicleHas(name: string): boolean
	local src = vehicleArt and vehicleArt:FindFirstChild(name, true)
	return src ~= nil and src:IsA("MeshPart")
end

local function laneDims(l: LifePlan.Lane, dir: number, s: number): (Vector3, number)
	local off = T.lane * dir
	if l.ax == "x" then
		return Vector3.new(s, GROUND + 0.2, l.c + off), DriveMath.yaw(dir, 0)
	end
	return Vector3.new(l.c - off, GROUND + 0.2, s), DriveMath.yaw(0, dir)
end

local function buildCar(): Car?
	if #carLooks == 0 or not folder then
		return nil
	end
	local f = focus()
	local B = budget()
	-- a lane in reach, and a spot on it out of the hero's face
	for _ = 1, 6 do
		local li = math.random(1, #lanes)
		local l = lanes[li]
		local along = if l.ax == "x" then f.X else f.Z
		local across = if l.ax == "x" then f.Z else f.X
		local side = math.abs(across - l.c)
		if side < B.carRadius then
			local reach = math.sqrt(math.max(0, B.carRadius ^ 2 - side ^ 2))
			local s = along + (math.random() * 2 - 1) * reach
			s = math.clamp(s, l.a0 + 4, l.a1 - 4)
			local pos = Vector3.new(if l.ax == "x" then s else l.c, f.Y, if l.ax == "x" then l.c else s)
			local d = (pos - f).Magnitude
			if d >= T.spawnMin and d <= B.carRadius then
				local dir = if math.random() < 0.5 then 1 else -1
				local look = carLooks[math.random(1, #carLooks)]
				local key = T.paints[math.random(1, #T.paints)]
				local paint = VehicleKit.PAINT[key] or Config.City.palette[key]
				local body = VehicleKit.BODY[look]
				local place = {
					look = look,
					x = 0,
					y = 0,
					z = 0,
					tint = if body and paint then { [body] = paint } else nil,
				}
				local m = Instance.new("Model")
				m.Name = "LifeCar"
				local parts: { BasePart }, offs: { CFrame }, wheels: { { i: number, r: number } } = {}, {}, {}
				local fixes: { CFrame } = {} -- each mesh's import turn (Shared.MeshFix), put back after a wheel's roll
				for _, mm in SetPieceKit.meshes(Config, place :: any) do
					local src = vehicleArt and vehicleArt:FindFirstChild(mm.name, true)
					if src and src:IsA("MeshPart") then
						local p = MeshFix.clone(src)
						for _, c in p:GetChildren() do
							if mm.maps and c:IsA("SurfaceAppearance") then
								pcall(function()
									c.AlphaMode = Enum.AlphaMode.Overlay
								end)
							else
								c:Destroy()
							end
						end
						p.Anchored = true
						p.CanCollide = false
						p.CanQuery = false
						p.CanTouch = false
						p.Size = Vector3.new(mm.size[1], mm.size[2], mm.size[3])
						p.Color = Color3.fromRGB(mm.color[1], mm.color[2], mm.color[3])
						local ok, mat = pcall(function()
							return (Enum.Material :: any)[mm.mat]
						end)
						p.Material = if ok and mat then mat else Enum.Material.SmoothPlastic
						p.Transparency = mm.alpha
						p.Parent = m
						table.insert(parts, p)
						table.insert(offs, CFrame.new(mm.offset[1], mm.offset[2], mm.offset[3]))
						table.insert(fixes, MeshFix.of(p))
						if mm.wheel then
							table.insert(wheels, { i = #parts, r = mm.wheel.r })
						end
					end
				end
				if #parts == 0 then
					m:Destroy()
					return nil
				end
				m.Parent = folder
				return {
					lane = li,
					dir = dir,
					s = s,
					v = T.cruise * 0.6,
					model = m,
					parts = parts,
					offs = offs,
					fixes = fixes,
					wheels = wheels,
					spin = 0,
					hold = 0,
					honked = 0,
					fleeing = 0,
				}
			end
		end
	end
	return nil
end

-- The room ahead of a car before it must stop (a red light, the car ahead, a hero in its lane), or nil
local function stopIn(car: Car, now: number, list: { { pos: Vector3, vel: Vector3, air: boolean } }): number?
	local l = lanes[car.lane]
	local best: number? = nil
	local function take(d: number)
		if not best or d < best then
			best = d
		end
	end
	if car.hold > now then
		take(0)
	end
	-- the next crossing ahead: stop short of it on red (a car already past the line goes on through)
	local next: number? = nil
	for _, c in crossings[car.lane] do
		local ahead = (c - car.s) * car.dir
		if ahead > 0 and (not next or ahead < (next - car.s) * car.dir) then
			next = c
		end
	end
	if next then
		local c = next
		local x, z = if l.ax == "x" then c else l.c, if l.ax == "x" then l.c else c
		local room = (c - car.s) * car.dir - T.stopShort
		if room > -1 and LifePlan.green(T, now, x, z) ~= l.ax then
			take(math.max(0, room))
		end
	end
	for _, o in cars do
		if o ~= car and o.lane == car.lane and o.dir == car.dir then
			local ahead = (o.s - car.s) * car.dir
			if ahead > 0 and ahead < T.gap + 40 then
				take(ahead - T.gap)
			end
		end
	end
	local pos = laneDims(l, car.dir, car.s)
	for _, h in list do
		local d = h.pos - pos
		local along = if l.ax == "x" then d.X * car.dir else d.Z * car.dir
		local across = if l.ax == "x" then d.Z else d.X
		if along > 0 and along < T.heroStop + car.v * 0.6 and math.abs(across) < 5 and math.abs(d.Y) < 8 then
			take(along - 7)
			if car.honked < now - 4 and math.random() < 0.5 then
				car.honked = now
				AudioController.playSpec(L.sounds.honk, pos)
			end
		end
	end
	return best
end

local function dropCar(i: number)
	local car = cars[i]
	car.model:Destroy()
	table.remove(cars, i)
end

-- A big hit flings the cars in reach (they tumble on their own, then fade) and the rest brake
local function knockCars(center: Vector3, radius: number)
	local K = T.knock
	local now = os.clock()
	for i = #cars, 1, -1 do
		local car = cars[i]
		local root = car.parts[1]
		local d = root.Position - center
		local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude <= radius * K.radius + 6 and math.abs(d.Y) < radius + 10 then
			table.remove(cars, i)
			local hz = car.hazards
			if hz then
				for _, h in hz do
					h:Destroy() -- (anchored blinkers would stay hanging where it was)
				end
			end
			for k = 2, #car.parts do
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = car.parts[k]
				w.Parent = root
			end
			for _, p in car.parts do
				p.Anchored = false
				p.Massless = p ~= root
			end
			root.CanCollide = true
			local out = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
			root.AssemblyLinearVelocity = out * K.out * (0.7 + math.random() * 0.5)
				+ Vector3.new(0, K.up * (0.7 + math.random() * 0.5), 0)
			root.AssemblyAngularVelocity = Vector3.new(
				math.random() - 0.5,
				math.random() - 0.5,
				math.random() - 0.5
			) * K.spin
			local m = car.model
			task.delay(K.life - 1, function()
				for _, p in car.parts do
					if p.Parent then
						TweenService:Create(p, TweenInfo.new(1), { Transparency = 1 }):Play()
					end
				end
			end)
			task.delay(K.life, function()
				m:Destroy()
			end)
		elseif flat.Magnitude <= radius * K.radius * 3 + 40 then
			car.hold = now + 2.5
			if math.random() < T.honk then
				AudioController.playSpec(L.sounds.honk, root.Position)
			end
		end
	end
end

local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}

-- Fights near the camera (alive-world): the drawn robots and the last big hit, as { x, z } points, every few tenths
local FEAR = T.fear
local FLEE_T = table.clone(T)
FLEE_T.cruise = T.cruise * FEAR.flee
local dangers: { { number } } = {}
local dangersAt = 0
local function scanDangers(now: number)
	if now < dangersAt then
		return
	end
	dangersAt = now + FEAR.every
	table.clear(dangers)
	local f = focus()
	local reach = budget().carRadius + FEAR.radius + FEAR.ahead
	for _, pos in EnemyRenderer.each() do
		if #dangers >= 24 then
			break
		end
		if
			math.abs(pos.X - f.X) < reach
			and math.abs(pos.Z - f.Z) < reach
			and math.abs(pos.Y - GROUND) < 60
		then
			table.insert(dangers, { pos.X, pos.Z })
		end
	end
	if now - bang.t < FEAR.bangFor then
		table.insert(dangers, { bang.at.X, bang.at.Z })
	end
end

-- Hazard lights: four amber blinkers at the car's corners (made the first time it is scared, medium and high)
local HAZARD_AT = {
	CFrame.new(-2.05, 1.3, -4.3),
	CFrame.new(2.05, 1.3, -4.3),
	CFrame.new(-2.05, 1.4, 4.3),
	CFrame.new(2.05, 1.4, 4.3),
}
local HAZARD = Color3.fromRGB(FEAR.hazard[1], FEAR.hazard[2], FEAR.hazard[3])
local function hazardsOf(car: Car): { BasePart }
	local list = car.hazards
	if list then
		return list
	end
	local made: { BasePart } = {}
	for _ = 1, #HAZARD_AT do
		local p = Instance.new("Part")
		p.Name = "Hazard"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = HAZARD
		p.Size = Vector3.new(0.5, 0.35, 0.3)
		p.Transparency = 1
		p.Parent = car.model
		table.insert(made, p)
	end
	car.hazards = made
	return made
end

-- A car's fear this frame: scared cars stop (stopIn 0), then U-turn; returns the pose override (pos, yaw) while turning
local function fearStep(car: Car, dt: number, now: number): (Vector3?, number?)
	local l = lanes[car.lane]
	if car.turn then
		local t = (car.turn :: number) + dt / FEAR.turn
		local a = laneDims(l, car.dir, car.s)
		local b = laneDims(l, -car.dir, car.s)
		local fx, fz = if l.ax == "x" then car.dir else 0, if l.ax == "x" then 0 else car.dir
		if t >= 1 then
			car.turn = nil
			car.dir = -car.dir
			car.v = 4
			car.fleeing = now + FEAR.fleeFor
			car.scared = nil
			return nil, nil
		end
		car.turn = t
		local x, z, tx, tz = LifePlan.uturn(a.X, a.Z, b.X, b.Z, fx, fz, FEAR.stretch, t)
		return Vector3.new(x, a.Y, z), DriveMath.yaw(tx, tz)
	end
	if car.fleeing > now then
		return nil, nil
	end
	if not car.scared and #dangers > 0 then
		local pos = laneDims(l, car.dir, car.s)
		local fx, fz = if l.ax == "x" then car.dir else 0, if l.ax == "x" then 0 else car.dir
		if LifePlan.feared(FEAR, pos.X, pos.Z, fx, fz, dangers) then
			car.scared = now
			if car.honked < now - 2 and math.random() < FEAR.honk then
				car.honked = now
				AudioController.playSpec(L.sounds.honk, pos)
			end
		end
	end
	local since = car.scared
	if since and car.v < 1.5 and now - since >= FEAR.wait then
		car.turn = 0
	end
	return nil, nil
end

local function stepCars(dt: number, now: number, list: { any })
	local B = budget()
	local f = focus()
	scanDangers(now)
	while #cars < B.cars and #lanes > 0 do
		local c = buildCar()
		if not c then
			break
		end
		table.insert(cars, c)
	end
	for i = #cars, 1, -1 do
		local car = cars[i]
		local l = lanes[car.lane]
		local turnPos, turnYaw = fearStep(car, dt, now)
		local pos: Vector3, yaw: number
		if turnPos and turnYaw then
			pos, yaw = turnPos, turnYaw -- mid U-turn: it creeps round the loop
			car.v = 6
		else
			local room = if car.scared then 0 else stopIn(car, now, list)
			car.v = LifePlan.carSpeed(if car.fleeing > now then FLEE_T else T, car.v, dt, room)
			car.s += car.dir * car.v * dt
			pos, yaw = laneDims(l, car.dir, car.s)
		end
		if car.s < l.a0 - 6 or car.s > l.a1 + 6 or (pos - f).Magnitude > B.carRadius * 1.2 or i > B.cars then
			dropCar(i)
			continue
		end
		local root = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		car.spin += car.v * dt
		for k, p in car.parts do
			table.insert(bulkParts, p)
			table.insert(bulkCFrames, root * car.offs[k] * car.fixes[k])
		end
		-- hazards blink while it is scared, turning or fleeing (medium and high)
		local alarmed = car.scared ~= nil or car.turn ~= nil or car.fleeing > now
		if alarmed and B.hazards then
			local on = (now % (FEAR.blink * 2)) < FEAR.blink
			for k, h in hazardsOf(car) do
				h.Transparency = if on then 0 else 1
				table.insert(bulkParts, h)
				table.insert(bulkCFrames, root * HAZARD_AT[k])
			end
		elseif car.hazards then
			for _, h in car.hazards :: { BasePart } do
				h.Transparency = 1
			end
		end
		if B.wheels then
			for _, w in car.wheels do
				local k = w.i
				bulkCFrames[#bulkCFrames - #car.parts + k] = root
					* car.offs[k]
					* CFrame.Angles(-car.spin / math.max(w.r, 0.3), 0, 0)
					* car.fixes[k]
			end
		end
	end
	CityLife.cars = #cars
end

---------------------------------------------------------------------------- pigeons
type Bird = { body: BasePart, wl: BasePart, wr: BasePart, pos: Vector3, yaw: number, vel: Vector3, key: number }
type Flock = { spot: { number }, birds: { Bird }, flying: number?, backAt: number }
local corners: { { number } } = {}
local flocks: { [number]: Flock } = {}
local PIGEON = Color3.fromRGB(130, 134, 146)
local WING = Color3.fromRGB(108, 112, 124)
local SH_L = CFrame.new(-0.22, 0.72, -0.02)
local SH_R = CFrame.new(0.22, 0.72, -0.02)

local function makeFlock(spot: { number }): Flock?
	if not (folder and lifeSource("PigeonBody")) then
		return nil
	end
	local P = L.pigeons
	local n = math.random(P.count[1], P.count[2])
	local birds: { Bird } = {}
	for k = 1, n do
		local body = lifePiece("Pigeon", "PigeonBody", PIGEON, Enum.Material.SmoothPlastic, folder)
		local wl = lifePiece("Pigeon", "PigeonWingL", WING, Enum.Material.SmoothPlastic, folder)
		local wr = lifePiece("Pigeon", "PigeonWingR", WING, Enum.Material.SmoothPlastic, folder)
		if not (body and wl and wr) then
			return nil
		end
		local a = math.random() * math.pi * 2
		local r = 1 + math.random() * 3
		table.insert(birds, {
			body = body,
			wl = wl,
			wr = wr,
			pos = Vector3.new(spot[1] + math.cos(a) * r, SIDEWALK, spot[2] + math.sin(a) * r),
			yaw = math.random() * math.pi * 2,
			vel = Vector3.zero,
			key = k * 1.37 + spot[1] * 0.01,
		})
	end
	return { spot = spot, birds = birds, backAt = 0 }
end

local function clearFlock(fl: Flock)
	for _, b in fl.birds do
		b.body:Destroy()
		b.wl:Destroy()
		b.wr:Destroy()
	end
	fl.birds = {}
end

local function scatter(fl: Flock, from: Vector3, now: number)
	if fl.flying or #fl.birds == 0 then
		return
	end
	local F = L.pigeons.fly
	fl.flying = now
	for _, b in fl.birds do
		local away = Vector3.new(b.pos.X - from.X, 0, b.pos.Z - from.Z)
		away = if away.Magnitude > 0.1
			then away.Unit
			else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.8
		b.vel = (away + jitter).Unit * F.out * (0.7 + math.random() * 0.6)
			+ Vector3.new(0, F.up * (0.8 + math.random() * 0.4), 0)
	end
	AudioController.playSpec(L.sounds.flutter, fl.birds[1].pos)
end

local function poseBird(b: Bird, t: number, flying: boolean)
	local at = CFrame.new(b.pos) * CFrame.Angles(0, b.yaw, 0)
	local fold, peck = 1.3, 0
	if flying then
		fold = math.sin(t * L.pigeons.fly.flap + b.key) * 1.1 - 0.1
		at *= CFrame.Angles(math.rad(-18), 0, 0)
	else
		local c = (t * 0.9 + b.key) % 3
		if c < 0.5 then
			peck = math.sin(c / 0.5 * math.pi) * 0.7 -- a peck at the ground
		end
	end
	local body = at * CFrame.new(0, 0, -0.2) * CFrame.Angles(-peck, 0, 0) * CFrame.new(0, 0, 0.2)
	table.insert(bulkParts, b.body)
	table.insert(bulkCFrames, body * offsetOf("Pigeon", "PigeonBody"))
	local offL = Config.LifeArt.Pigeon.PigeonWingL.offset
	local offR = Config.LifeArt.Pigeon.PigeonWingR.offset
	table.insert(bulkParts, b.wl)
	table.insert(
		bulkCFrames,
		body
			* SH_L
			* CFrame.Angles(0, 0, fold)
			* CFrame.new(offL[1] + 0.22, offL[2] - 0.72, offL[3] + 0.02)
			* LIFE_TURN
	)
	table.insert(bulkParts, b.wr)
	table.insert(
		bulkCFrames,
		body
			* SH_R
			* CFrame.Angles(0, 0, -fold)
			* CFrame.new(offR[1] - 0.22, offR[2] - 0.72, offR[3] + 0.02)
			* LIFE_TURN
	)
end

local function stepPigeons(dt: number, now: number, list: { any })
	local B = budget()
	local P = L.pigeons
	local f = focus()
	-- the nearest corners in reach have flocks (up to the budget); far ones go
	local want: { { i: number, d: number } } = {}
	for i, c in corners do
		local d = math.sqrt((c[1] - f.X) ^ 2 + (c[2] - f.Z) ^ 2)
		if d < 170 then
			table.insert(want, { i = i, d = d })
		end
	end
	table.sort(want, function(a, b)
		return a.d < b.d
	end)
	local keep: { [number]: boolean } = {}
	for k = 1, math.min(#want, B.flocks) do
		keep[want[k].i] = true
	end
	local n = 0
	for i, fl in flocks do
		if not keep[i] then
			clearFlock(fl)
			flocks[i] = nil
		end
	end
	for i in keep do
		local fl = flocks[i]
		if not fl then
			local made = makeFlock(corners[i])
			if made then
				flocks[i] = made
				fl = made
			end
		end
		if fl then
			n += 1
			if #fl.birds == 0 then
				if now >= fl.backAt then
					local made = makeFlock(fl.spot)
					if made then
						flocks[i] = made
					end
				end
				continue
			end
			local centre = Vector3.new(fl.spot[1], SIDEWALK, fl.spot[2])
			if not fl.flying then
				for _, h in list do
					local d = (h.pos - centre).Magnitude
					if d < P.scare or (d < P.scare * 2 and h.vel.Magnitude > P.fast) then
						scatter(fl, h.pos, now)
						break
					end
				end
				if not fl.flying and (bang.at - centre).Magnitude < P.bang and now - bang.t < 0.5 then
					scatter(fl, bang.at, now)
				end
			end
			local flying = fl.flying ~= nil
			for _, b in fl.birds do
				if flying then
					b.pos += b.vel * dt
					b.vel += Vector3.new(0, 4 * dt, 0)
					b.yaw = DriveMath.yaw(b.vel.X, b.vel.Z)
				elseif math.random() < dt * 0.4 then
					b.yaw += (math.random() - 0.5) * 2 -- a turn, a hop
					local step = CFrame.Angles(0, b.yaw, 0).LookVector * 0.6
					local np = b.pos + step
					if (np - centre).Magnitude < 5 then
						b.pos = np
					end
				end
				poseBird(b, now, flying)
			end
			if flying and now - (fl.flying :: number) > P.fly.time then
				clearFlock(fl)
				fl.flying = nil
				fl.backAt = now + P.back
			end
		end
	end
	CityLife.flocks = n
end

---------------------------------------------------------------------------- harbour gulls (alive-world)
-- A colony circles over each Docks crane near the camera (the server tags the crane's beam LifeGulls): pigeon meshes
-- scaled up in gull white, gliding with a slow flap now and then, banking into the circle; a hero flying through or a
-- big hit sends them wheeling out and up, flapping hard, and they drift back after a while.
type Gull = { bird: Bird, phase: number, radius: number, height: number, speed: number }
type Colony = { gulls: { Gull }, scared: number, flee: number }
local colonies: { [BasePart]: Colony } = {}
local G = L.gulls
local GULL_BODY = Color3.fromRGB(G.body[1], G.body[2], G.body[3])
local GULL_WING = Color3.fromRGB(G.wing[1], G.wing[2], G.wing[3])

local function gullPiece(name: string, color: Color3): BasePart?
	local p = lifePiece("Pigeon", name, color, Enum.Material.SmoothPlastic, folder :: Folder)
	if p then
		p.Size *= G.scale
	end
	return p
end

local function makeColony(n: number): Colony?
	if not (folder and lifeSource("PigeonBody")) then
		return nil
	end
	local gulls: { Gull } = {}
	for k = 1, n do
		local body = gullPiece("PigeonBody", GULL_BODY)
		local wl = gullPiece("PigeonWingL", GULL_WING)
		local wr = gullPiece("PigeonWingR", GULL_WING)
		if not (body and wl and wr) then
			for _, q in { body, wl, wr } do
				if q then
					q:Destroy()
				end
			end
			break
		end
		table.insert(gulls, {
			bird = {
				body = body,
				wl = wl,
				wr = wr,
				pos = Vector3.zero,
				yaw = 0,
				vel = Vector3.zero,
				key = k * 1.7,
			},
			phase = math.random() * math.pi * 2,
			radius = G.radius[1] + math.random() * (G.radius[2] - G.radius[1]),
			height = G.height[1] + math.random() * (G.height[2] - G.height[1]),
			speed = (G.speed[1] + math.random() * (G.speed[2] - G.speed[1])) * (if k % 3 == 0 then -1 else 1),
		})
	end
	return if #gulls > 0 then { gulls = gulls, scared = -math.huge, flee = 0 } else nil
end

local function dropColony(c: Colony)
	for _, g in c.gulls do
		g.bird.body:Destroy()
		g.bird.wl:Destroy()
		g.bird.wr:Destroy()
	end
end

-- A gull's pose: its body banked into the turn, wings by `fold` (Config.LifeArt.Pigeon's fit, scaled)
local function poseGull(b: Bird, at: CFrame, fold: number)
	local k = G.scale
	local function off(name: string): CFrame
		local o = Config.LifeArt.Pigeon[name].offset
		return CFrame.new(o[1] * k, o[2] * k, o[3] * k)
	end
	table.insert(bulkParts, b.body)
	table.insert(bulkCFrames, at * off("PigeonBody") * LIFE_TURN)
	local oL = Config.LifeArt.Pigeon.PigeonWingL.offset
	local oR = Config.LifeArt.Pigeon.PigeonWingR.offset
	table.insert(bulkParts, b.wl)
	table.insert(
		bulkCFrames,
		at
			* CFrame.new(-0.22 * k, 0.72 * k, -0.02 * k)
			* CFrame.Angles(0, 0, fold)
			* CFrame.new((oL[1] + 0.22) * k, (oL[2] - 0.72) * k, (oL[3] + 0.02) * k)
			* LIFE_TURN
	)
	table.insert(bulkParts, b.wr)
	table.insert(
		bulkCFrames,
		at
			* CFrame.new(0.22 * k, 0.72 * k, -0.02 * k)
			* CFrame.Angles(0, 0, -fold)
			* CFrame.new((oR[1] - 0.22) * k, (oR[2] - 0.72) * k, (oR[3] + 0.02) * k)
			* LIFE_TURN
	)
end

local function stepGulls(dt: number, now: number, list: { any })
	local B = budget()
	local f = focus()
	local want: { { p: BasePart, d: number } } = {}
	for _, p in CollectionService:GetTagged("LifeGulls") do
		if p:IsA("BasePart") then
			local d = (p.Position - f).Magnitude
			if d < G.range then
				table.insert(want, { p = p, d = d })
			end
		end
	end
	table.sort(want, function(a, b)
		return a.d < b.d
	end)
	local keep: { [BasePart]: boolean } = {}
	for k = 1, math.min(#want, B.gullColonies) do
		keep[want[k].p] = true
	end
	for p, c in colonies do
		if not keep[p] or not p.Parent or #c.gulls ~= B.gulls then
			dropColony(c)
			colonies[p] = nil
		end
	end
	for p in keep do
		local c = colonies[p]
		if not c then
			c = makeColony(B.gulls)
			if not c then
				continue
			end
			colonies[p] = c
		end
		local colony = c :: Colony
		local centre = p.Position + Vector3.new(0, p.Size.Y / 2 + G.above, G.out)
		-- a hero flying through, or a big hit near: they wheel out and up
		local scare = now - bang.t < 0.5 and (bang.at - centre).Magnitude < G.bang
		if not scare then
			for _, h in list do
				if (h.pos - centre).Magnitude < G.scare + 20 then
					scare = true
					break
				end
			end
		end
		if scare then
			if now - colony.scared > 1.5 then
				AudioController.playSpec(L.sounds.flutter, centre)
			end
			colony.scared = now
		end
		local target = if now - colony.scared < G.calm then 1 else 0
		colony.flee += (target - colony.flee) * math.min(1, dt * (if target > colony.flee then 2.2 else 0.35))
		for _, g in colony.gulls do
			local x, y, z, tx, tz = LifePlan.gull(now, g.phase, g.radius, g.height, g.speed, colony.flee)
			local b = g.bird
			b.pos = centre + Vector3.new(x, y, z)
			local dir = if g.speed < 0 then -1 else 1
			b.yaw = DriveMath.yaw(tx * dir, tz * dir)
			-- glide with a few slow beats now and then; hard flapping while they flee
			local beat = math.sin(now * 1.3 + g.phase * 5) > 0.75 or colony.flee > 0.25
			local fold = if beat
				then math.sin(now * (if colony.flee > 0.25 then 16 else 9) + b.key) * 0.9
				else -0.12 + math.sin(now * 2 + b.key) * 0.05
			local bank = math.rad(22) * dir
			poseGull(b, CFrame.new(b.pos) * CFrame.Angles(0, b.yaw, 0) * CFrame.Angles(0, 0, bank), fold)
		end
	end
end

---------------------------------------------------------------------------- Foundry chimney smoke (alive-world)
local SM = L.smoke
local chimneySmoke: { [BasePart]: ParticleEmitter } = {}

local function smokeEmitter(at: BasePart, rate: number): ParticleEmitter
	local a = Instance.new("Attachment")
	a.Name = "LifeSmoke"
	a.Parent = at
	-- (a cylinder part lies on its side: its longest side is the stack's height; the plume goes straight up)
	local h = math.max(at.Size.X, at.Size.Y, at.Size.Z)
	a.WorldCFrame = CFrame.new(at.Position + Vector3.new(0, h / 2 + 1.5, 0))
	local e = Instance.new("ParticleEmitter")
	e.Name = "LifeSmoke"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(
		Color3.fromRGB(SM.color[1] + 40, SM.color[2] + 30, SM.color[3] + 26),
		Color3.fromRGB(SM.color[1], SM.color[2], SM.color[3])
	)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, SM.size[1]),
		NumberSequenceKeypoint.new(1, SM.size[2]),
	})
	e.Lifetime = NumberRange.new(SM.life[1], SM.life[2])
	e.Rate = rate
	e.Speed = NumberRange.new(SM.speed[1], SM.speed[2])
	e.SpreadAngle = Vector2.new(10, 10)
	e.Acceleration = Vector3.new(3.5, 1.2, 1.4) -- the sea wind leans the plume
	e.RotSpeed = NumberRange.new(-15, 15)
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 0.7
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = a
	return e
end

local function stepSmoke()
	local B = budget()
	local f = focus()
	local want: { { p: BasePart, d: number } } = {}
	for _, p in CollectionService:GetTagged("LifeSmoke") do
		if p:IsA("BasePart") then
			local d = (p.Position - f).Magnitude
			if d < SM.range then
				table.insert(want, { p = p, d = d })
			end
		end
	end
	table.sort(want, function(a, b)
		return a.d < b.d
	end)
	local keep: { [BasePart]: boolean } = {}
	for k = 1, math.min(#want, B.smoke) do
		keep[want[k].p] = true
	end
	for p, e in chimneySmoke do
		if not keep[p] or not p.Parent or e.Rate ~= B.smokeRate then
			local a = e.Parent
			if a then
				a:Destroy()
			end
			chimneySmoke[p] = nil
		end
	end
	for p in keep do
		if not chimneySmoke[p] then
			chimneySmoke[p] = smokeEmitter(p, B.smokeRate)
		end
	end
end

-- A big hit near a chimney: a black burst out of its top
local function puffSmoke(center: Vector3, radius: number)
	for _, e in chimneySmoke do
		local top = (e.Parent :: Attachment).WorldPosition
		local flat = Vector3.new(top.X - center.X, 0, top.Z - center.Z)
		if flat.Magnitude < 120 + radius * 3 then
			e:Emit(SM.puff)
		end
	end
end

---------------------------------------------------------------------------- steam, manholes and roof vents
type Vent = { spot: { number }, cover: BasePart?, src: BasePart, emitter: ParticleEmitter, popped: number }
local manholes: { { number } } = {}
local vents: { [number]: Vent } = {}
local roofSteam: { [BasePart]: ParticleEmitter } = {}

local function steamEmitter(parent: Instance, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "LifeSteam"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(236, 238, 242))
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.4, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 7) })
	e.Lifetime = NumberRange.new(2.4, 3.6)
	e.Rate = rate
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(14, 14)
	e.Acceleration = Vector3.new(1.2, 1.5, 0.4)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 0.8
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	return e
end

local function makeVent(spot: { number }): Vent?
	if not folder then
		return nil
	end
	local src = Instance.new("Part")
	src.Name = "SteamSrc"
	src.Anchored = true
	src.CanCollide = false
	src.CanQuery = false
	src.CanTouch = false
	src.Transparency = 1
	src.Size = Vector3.new(2, 0.2, 2)
	src.CFrame = CFrame.new(spot[1], spot[3] + 0.1, spot[2])
	src.Parent = folder
	local cover = lifePiece("Manhole", "Manhole", Color3.fromRGB(70, 72, 76), Enum.Material.Metal, folder)
	if cover then
		cover.CFrame = CFrame.new(spot[1], spot[3] - 0.08, spot[2]) * offsetOf("Manhole", "Manhole")
	end
	return {
		spot = spot,
		cover = cover :: BasePart?,
		src = src :: BasePart,
		emitter = steamEmitter(src, 5),
		popped = 0,
	}
end

local function dropVent(v: Vent)
	v.src:Destroy()
	if v.cover then
		v.cover:Destroy()
	end
end

-- A bang next to a manhole blows its cover up and off in a puff; it is back in place after a while
local function popVents(center: Vector3, radius: number)
	local S = L.steam
	local now = os.clock()
	for _, v in vents do
		local at = v.src.Position
		local cover = v.cover
		if cover and (at - center).Magnitude <= S.pop + radius and v.popped < now - S.back then
			v.popped = now
			v.emitter:Emit(40)
			AudioController.playSpec(L.sounds.pop, at)
			local fly = cover:Clone()
			fly.Anchored = false
			fly.CanCollide = true
			fly.Parent = folder
			fly.AssemblyLinearVelocity =
				Vector3.new((math.random() - 0.5) * 20, 70 + math.random() * 20, (math.random() - 0.5) * 20)
			fly.AssemblyAngularVelocity =
				Vector3.new(math.random() * 12, math.random() * 4, math.random() * 12)
			cover.LocalTransparencyModifier = 1
			task.delay(S.back - 1, function()
				if fly.Parent then
					TweenService:Create(fly, TweenInfo.new(1), { Transparency = 1 }):Play()
				end
			end)
			task.delay(S.back, function()
				fly:Destroy()
				cover.LocalTransparencyModifier = 0
			end)
		end
	end
end

local function stepSteam()
	local B = budget()
	local f = focus()
	local want: { { i: number, d: number } } = {}
	for i, m in manholes do
		local d = math.sqrt((m[1] - f.X) ^ 2 + (m[2] - f.Z) ^ 2)
		if d < 260 then
			table.insert(want, { i = i, d = d })
		end
	end
	table.sort(want, function(a, b)
		return a.d < b.d
	end)
	local keep: { [number]: boolean } = {}
	for k = 1, math.min(#want, B.steam) do
		keep[want[k].i] = true
	end
	for i, v in vents do
		if not keep[i] then
			dropVent(v)
			vents[i] = nil
		end
	end
	for i in keep do
		if not vents[i] then
			vents[i] = makeVent(manholes[i])
		end
	end
	-- the roof vents near the camera (tag LifeSteam, the server's RoofVent meshes) steam a little
	local used = 0
	for _, p in CollectionService:GetTagged("LifeSteam") do
		if p:IsA("BasePart") then
			local near = (p.Position - f).Magnitude < 220
				and used < B.steam
				and p.LocalTransparencyModifier < 1
			local e = roofSteam[p]
			if near and not e then
				local a = Instance.new("Attachment")
				a.Name = "LifeSteam"
				a.Position = Vector3.new(0, p.Size.Y / 2, 0)
				a.Parent = p
				roofSteam[p] = steamEmitter(a, 2.5)
			elseif e and not near then
				(e.Parent :: Instance):Destroy()
				roofSteam[p] = nil
			end
			if near then
				used += 1
			end
		end
	end
	for p, e in roofSteam do
		if not p.Parent then
			roofSteam[p] = nil
			e:Destroy()
		end
	end
end

---------------------------------------------------------------------------- roof flags
type Flag = { def: any, pole: { BasePart }, segs: { BasePart }, hoist: CFrame, shown: boolean }
local flagDefs: { any } = {}
local flags: { [number]: Flag } = {}

local function makeFlag(def: any, nseg: number): Flag?
	if not folder then
		return nil
	end
	local F = L.flagRoofs
	local w, h = F.size[1], F.size[2]
	local base = CFrame.new(def.x, def.y, def.z)
	local pole: { BasePart } = {}
	for _, name in { "FlagPole", "FlagFinial" } do
		local mat = Enum.Material.Metal
		local col = if name == "FlagPole" then Color3.fromRGB(220, 222, 226) else Color3.fromRGB(230, 190, 70)
		local p = lifePiece("FlagPole", name, col, mat, folder)
		if not p then
			for _, q in pole do
				q:Destroy()
			end
			return nil
		end
		p.CFrame = base * offsetOf("FlagPole", name)
		table.insert(pole, p)
	end
	local image = L.flags[def.district] or L.flags.Brightharbor
	local segs: { BasePart } = {}
	local sw = w / nseg
	for i = 1, nseg do
		local s = Instance.new("Part")
		s.Name = "FlagCloth"
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.CanTouch = false
		s.CastShadow = false
		s.Size = Vector3.new(sw + 0.04, h, 0.06)
		s.Transparency = 1
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local tex = Instance.new("Texture")
			tex.Texture = "rbxassetid://" .. tostring(image)
			tex.Face = face
			tex.StudsPerTileU = w
			tex.StudsPerTileV = h
			-- each strip shows its own slice of the picture (the back face runs the other way)
			tex.OffsetStudsU = if face == Enum.NormalId.Front then -(i - 1) * sw else -(nseg - i) * sw
			tex.Parent = s
		end
		s.Parent = folder
		table.insert(segs, s)
	end
	local yaw = math.rad(30) + (def.x % 7) * 0.05
	return {
		def = def,
		pole = pole,
		segs = segs,
		hoist = base * CFrame.new(0, 15.6 - h / 2, 0) * CFrame.Angles(0, yaw, 0),
		shown = true,
	}
end

local function dropFlag(fl: Flag)
	for _, p in fl.pole do
		p:Destroy()
	end
	for _, s in fl.segs do
		s:Destroy()
	end
end

local function stepFlags(now: number)
	local B = budget()
	local f = focus()
	local want: { { i: number, d: number } } = {}
	for i, d in flagDefs do
		local dist = (Vector3.new(d.x, d.y, d.z) - f).Magnitude
		if dist < 320 then
			table.insert(want, { i = i, d = dist })
		end
	end
	table.sort(want, function(a, b)
		return a.d < b.d
	end)
	local keep: { [number]: boolean } = {}
	for k = 1, math.min(#want, B.flags) do
		keep[want[k].i] = true
	end
	for i, fl in flags do
		if not keep[i] or #fl.segs ~= B.flagSegs then
			dropFlag(fl)
			flags[i] = nil
		end
	end
	local wind = L.flagRoofs.wind
	for i in keep do
		local fl = flags[i]
		if not fl then
			fl = makeFlag(flagDefs[i], B.flagSegs)
			flags[i] = fl
		end
		if fl then
			-- a broken building takes its flag with it (Fx.BuildingFx's state: 0 intact)
			local intact = BuildingFx.state(fl.def.id) == 0
			if intact ~= fl.shown then
				fl.shown = intact
				for _, p in fl.pole do
					p.LocalTransparencyModifier = if intact then 0 else 1
				end
				for _, s in fl.segs do
					for _, tex in s:GetChildren() do
						if tex:IsA("Texture") then
							tex.Transparency = if intact then 0 else 1
						end
					end
				end
			end
			if intact then
				local n = #fl.segs
				local sw = L.flagRoofs.size[1] / n
				local cf = fl.hoist
				for k, s in fl.segs do
					cf *= CFrame.Angles(0, LifePlan.wave(k, n, now + i, wind), 0)
					table.insert(bulkParts, s)
					table.insert(bulkCFrames, cf * CFrame.new(sw / 2, 0, 0))
					cf *= CFrame.new(sw, 0, 0)
				end
			end
		end
	end
end

---------------------------------------------------------------------------- news drones
type Drone = {
	parts: { BasePart },
	rotors: { BasePart },
	eye: BasePart,
	pos: Vector3,
	target: Vector3,
	t0: number,
	angle: number,
	leaving: boolean,
}
local drones: { Drone } = {}
local ROTOR_AT = {
	Vector3.new(-1.3, 0.12, -1.3),
	Vector3.new(1.3, 0.12, -1.3),
	Vector3.new(-1.3, 0.12, 1.3),
	Vector3.new(1.3, 0.12, 1.3),
}

local function sendDrone(at: Vector3)
	local B = budget()
	if #drones >= B.drones or not folder or not lifeSource("DroneBody") then
		return
	end
	for _, d in drones do
		if (d.target - at).Magnitude < 60 then
			return -- one is already filming it
		end
	end
	local parts: { BasePart }, rotors: { BasePart } = {}, {}
	local eye: BasePart? = nil
	local rows: { { name: string, color: Color3, mat: Enum.Material } } = {
		{ name = "DroneBody", color = Color3.fromRGB(240, 242, 246), mat = Enum.Material.SmoothPlastic },
		{ name = "DroneArm", color = Color3.fromRGB(44, 48, 56), mat = Enum.Material.Metal },
		{ name = "DroneEye", color = Color3.fromRGB(255, 60, 60), mat = Enum.Material.Neon },
	}
	for _, row in rows do
		local p = lifePiece("NewsDrone", row.name, row.color, row.mat, folder)
		if p then
			table.insert(parts, p)
			if row.name == "DroneEye" then
				eye = p
			end
		end
	end
	for _ = 1, 4 do
		local r = lifePiece(
			"NewsDrone",
			"DroneRotor",
			Color3.fromRGB(30, 32, 36),
			Enum.Material.SmoothPlastic,
			folder
		)
		if r then
			r.Transparency = 0.25
			table.insert(rotors, r)
		end
	end
	if not eye or #rotors < 4 then
		for _, p in parts do
			p:Destroy()
		end
		for _, r in rotors do
			r:Destroy()
		end
		return
	end
	local a = math.random() * math.pi * 2
	table.insert(drones, {
		parts = parts,
		rotors = rotors,
		eye = eye,
		pos = at + Vector3.new(math.cos(a) * 160, 70, math.sin(a) * 160),
		target = at,
		t0 = os.clock(),
		angle = a,
		leaving = false,
	})
	AudioController.playSpec(L.sounds.drone, at)
end

local function stepDrones(dt: number, now: number)
	local D = L.drone
	for i = #drones, 1, -1 do
		local d = drones[i]
		local age = now - d.t0
		d.angle += dt * 0.35
		local goal = d.target
			+ Vector3.new(math.cos(d.angle) * D.orbit, D.height, math.sin(d.angle) * D.orbit)
		if age > D.stay then
			d.leaving = true
		end
		if d.leaving then
			goal = d.pos + Vector3.new(math.cos(d.angle), 0.6, math.sin(d.angle)).Unit * 200
		end
		local step = goal - d.pos
		local move = math.min(step.Magnitude, D.speed * dt)
		if step.Magnitude > 0.01 then
			d.pos += step.Unit * move
		end
		local bob = math.sin(now * 2.1 + i) * 0.4
		local look = d.target - d.pos
		local yaw = DriveMath.yaw(look.X, look.Z)
		local tilt = math.clamp(move / math.max(dt, 1e-3) / D.speed, 0, 1) * 0.25
		local root = CFrame.new(d.pos + Vector3.new(0, bob, 0))
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(-tilt, 0, 0)
		for _, p in d.parts do
			table.insert(bulkParts, p)
			table.insert(bulkCFrames, root * offsetOf("NewsDrone", p.Name))
		end
		for k, r in d.rotors do
			table.insert(bulkParts, r)
			table.insert(bulkCFrames, root * CFrame.new(ROTOR_AT[k]) * CFrame.Angles(0, now * 40 + k, 0))
		end
		d.eye.Transparency = if (now * 2) % 1 < 0.5 then 0 else 0.7
		if d.leaving and age > D.stay + 6 then
			for _, p in d.parts do
				p:Destroy()
			end
			for _, r in d.rotors do
				r:Destroy()
			end
			table.remove(drones, i)
		end
	end
end

---------------------------------------------------------------------------- shops at night
local litShops: { [BasePart]: { color: Color3, mat: Enum.Material } } = {}
local function stepShops()
	local h = Lighting.ClockTime
	local night = h >= 18 or h < 6.3
	local f = focus()
	local warm = Color3.fromRGB(L.shopNight[1], L.shopNight[2], L.shopNight[3])
	for _, p in CollectionService:GetTagged("LifeShop") do
		if p:IsA("BasePart") then
			local on = night and (p.Position - f).Magnitude < 300
			local was = litShops[p]
			if on and not was then
				litShops[p] = { color = p.Color, mat = p.Material }
				p.Material = Enum.Material.Neon
				p.Color = warm:Lerp(Color3.new(0, 0, 0), 0.35)
			elseif was and not on then
				p.Color, p.Material = was.color, was.mat
				litShops[p] = nil
			end
		end
	end
	for p in litShops do
		if not p.Parent then
			litShops[p] = nil
		end
	end
end

---------------------------------------------------------------------------- street props that burst
local function geyser(at: Vector3)
	if not folder then
		return
	end
	local S = L.spill
	local src = Instance.new("Part")
	src.Name = "Geyser"
	src.Anchored = true
	src.CanCollide = false
	src.CanQuery = false
	src.CanTouch = false
	src.Transparency = 1
	src.Size = Vector3.new(1, 0.2, 1)
	src.CFrame = CFrame.new(at + Vector3.new(0, 0.4, 0))
	src.Parent = folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255), Color3.fromRGB(240, 250, 255))
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 3.2) })
	e.Lifetime = NumberRange.new(1.0, 1.5)
	e.Rate = 70
	local v = math.sqrt(2 * 60 * S.sprayHeight)
	e.Speed = NumberRange.new(v * 0.85, v)
	e.SpreadAngle = Vector2.new(6, 6)
	e.Acceleration = Vector3.new(0, -60, 0)
	e.LightInfluence = 0.6
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = src
	local splash = steamEmitter(src, 12)
	splash.Speed = NumberRange.new(8, 14)
	splash.SpreadAngle = Vector2.new(80, 80)
	splash.Color = ColorSequence.new(Color3.fromRGB(210, 235, 255))
	AudioController.playSpec(L.sounds.spray, at)
	task.delay(S.spray, function()
		e.Enabled = false
		splash.Enabled = false
	end)
	task.delay(S.spray + 2, function()
		src:Destroy()
	end)
end

local CAN_TINTS = { "awRed", "awBlue", "awYellow", "awGreen", "awOrange", "awTeal" }
local function spillCans(at: Vector3, from: Vector3)
	if not folder then
		return
	end
	local S = L.spill
	local n = DebrisBudget.lease(math.random(S.cans[1], S.cans[2]), S.canLife)
	for _ = 1, n do
		local rgb = Config.City.palette[CAN_TINTS[math.random(1, #CAN_TINTS)]] or { 200, 60, 60 }
		local c = lifePiece("Can", "Can", Color3.fromRGB(rgb[1], rgb[2], rgb[3]), Enum.Material.Metal, folder)
		if not c then
			return
		end
		c.CFrame = CFrame.new(
			at + Vector3.new((math.random() - 0.5) * 2, 2 + math.random() * 3, (math.random() - 0.5) * 2)
		) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		c.Anchored = false
		c.CanCollide = true
		local away = Vector3.new(at.X - from.X, 0, at.Z - from.Z)
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		c.AssemblyLinearVelocity = (away + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)) * 22
			+ Vector3.new(0, 18 + math.random() * 14, 0)
		c.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			* 18
		task.delay(S.canLife - 1, function()
			if c.Parent then
				TweenService:Create(c, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end)
		task.delay(S.canLife, function()
			c:Destroy()
		end)
	end
	AudioController.playSpec(L.sounds.cans, at)
end

local function paper(at: Vector3)
	if not folder then
		return
	end
	local n = DebrisBudget.lease(math.min(L.spill.paper, 10), 3)
	for _ = 1, n do
		local p = Instance.new("Part")
		p.Name = "Paper"
		p.Size = Vector3.new(0.9, 0.04, 1.2)
		p.Color = Color3.fromRGB(244, 240, 226)
		p.Material = Enum.Material.SmoothPlastic
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = CFrame.new(at + Vector3.new(0, 2.5, 0))
			* CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		p.Parent = folder
		p.AssemblyLinearVelocity =
			Vector3.new((math.random() - 0.5) * 26, 14 + math.random() * 12, (math.random() - 0.5) * 26)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			* 14
		task.delay(3, function()
			p:Destroy()
		end)
	end
end

local function onSmash(name: string, foot: Vector3, _tint: string?, center: Vector3)
	if name == "Hydrant" then
		geyser(foot)
	elseif name == "VendingMachine" then
		spillCans(foot, center)
	elseif name == "Bin" or name == "NewsBox" or name == "Mailbox" then
		paper(foot)
	end
end

---------------------------------------------------------------------------- impacts and the frame
local function onImpact(center: Vector3, radius: number, kind: number)
	local big = kind == 9 or radius >= 12
	if radius >= 6 or kind == 9 then
		bang.at, bang.t = center, os.clock()
	end
	knockCars(center, radius)
	popVents(center, radius)
	if big then
		puffSmoke(center, radius)
	end
	if big and (center - focus()).Magnitude <= L.drone.range then
		sendDrone(center)
	end
end

-- Where and when the last big hit was (CitizenRenderer's cheers)
function CityLife.lastBang(): (Vector3, number)
	return bang.at, bang.t
end

local slowAt = 0
local function step(dt: number)
	local now = os.clock()
	table.clear(bulkParts)
	table.clear(bulkCFrames)
	local list = heroes()
	stepCars(dt, now, list)
	stepPigeons(dt, now, list)
	stepGulls(dt, now, list)
	stepFlags(now)
	stepDrones(dt, now)
	if now >= slowAt then
		slowAt = now + 1
		stepSteam()
		stepSmoke()
		stepShops()
	end
	if #bulkParts > 0 then
		Workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function infoOf(): any?
	local value = ReplicatedStorage:WaitForChild("WorldInfo", 60)
	if not (value and value:IsA("StringValue")) then
		return nil
	end
	while value.Value == "" do
		value.Changed:Wait()
	end
	local ok, info = pcall(HttpService.JSONDecode, HttpService, value.Value)
	return if ok and type(info) == "table" then info else nil
end

function CityLife.init()
	CityProps.onSmash = onSmash
	BuildingFx.onImpact = onImpact
	CitizenRenderer.setBang(CityLife.lastBang)
	task.spawn(function()
		local art = ReplicatedStorage:WaitForChild("Art", 30)
		lifeArt = art and art:FindFirstChild(L.set)
		vehicleArt = art and art:FindFirstChild("Vehicles")
		if not lifeArt then
			return -- nothing to draw until Art.Life is imported (the city keeps today's look)
		end
		local info = infoOf()
		if not info then
			return
		end
		for _, l in info.lanes or {} do
			table.insert(lanes, { ax = l[1], c = l[2], a0 = l[3], a1 = l[4], y = l[5] })
		end
		crossings = LifePlan.crossings(lanes)
		local half = Config.City.downtown.street / 2 + Config.City.downtown.sidewalk / 2
		corners = LifePlan.corners(L.pigeons, lanes, crossings, half)
		manholes = LifePlan.manholes(L.steam, lanes, crossings)
		flagDefs = LifePlan.roofFlags(Config, info.buildings or {})
		if vehicleArt then
			for _, look in T.looks do
				if SetPieceKit.ready(Config, look, vehicleHas) then
					table.insert(carLooks, look)
				end
			end
		end
		local f = Instance.new("Folder")
		f.Name = "CityLife"
		f.Parent = Workspace
		folder = f
		RunService.Heartbeat:Connect(FrameProf.wrap("CityLife", step))
	end)
end

return CityLife
