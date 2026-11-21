-- SpaceService (2026-11-21, Everything Left 736; spec "Fly-in planet travel"): the orbit zone and the worlds
-- (Config.Space, Shared.SpaceLayout). Builds the Orbit Gate over the Hero Hall roof, the spaceport counter beside
-- its launch pad, the Orbit Station with every planet and approach ring, the moon Calder and the alien planet far
-- off the city map. A trip: a hero flies into a ring (the device asks with SpaceGo) or uses a ship counter (a
-- ProximityPrompt); the server checks the ring (with lag slack), the level, that the world is open and that the
-- hero is out of combat, then plays the entry on the device (SpaceEntry: 4 s, 5 s by ship) for the hero and every
-- friend or squadmate within Config.Space.party studs, streams the destination in and sets them down there still
-- flying (SpaceArrive). In orbit or on a world hero.scene is "space" (no incidents, ambient robots, PvP flag or
-- weather); falling out of the orbit takes you home, drifting past its edge brings you back to the deck.
-- PLACEHOLDER ART: part-built (SpaceLayout rows).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local SpaceLayout = require(Shared:WaitForChild("SpaceLayout"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local SquadService = require(script.Parent.SquadService)

local SpaceService = {}

local S = Config.Space
local readyAt: { [Player]: number } = {}
local going: { [Player]: boolean } = {}
local lastZone: { [Player]: any } = {}
local friendCache: { [string]: boolean } = {}
SpaceService.gate = nil :: SpaceLayout.Ring?

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- One scenery row to a part
local function part(r: any): BasePart
	local p: BasePart
	if r.shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		q.Shape = if r.shape == "Ball"
			then Enum.PartType.Ball
			elseif r.shape == "Cylinder" then Enum.PartType.Cylinder
			else Enum.PartType.Block
		p = q
	end
	p.Anchored = true
	p.CanCollide = r.collide == true
	p.CanQuery = r.collide == true
	p.CanTouch = false
	p.CastShadow = not r.glow and (r.t or 0) < 0.5
	p.Size = Vector3.new(r.s[1], r.s[2], r.s[3])
	local at = Vector3.new(r.p[1], r.p[2], r.p[3])
	if r.look then
		p.CFrame = CFrame.lookAt(
			at,
			at + Vector3.new(r.look[1], r.look[2], r.look[3]),
			Vector3.new(r.up[1], r.up[2], r.up[3])
		)
	else
		local rot = r.r or { 0, 0, 0 }
		p.CFrame = CFrame.new(at)
			* CFrame.fromOrientation(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
	end
	p.Color = rgb(r.c)
	p.Material = (Enum.Material :: any)[r.m] or Enum.Material.SmoothPlastic
	p.Transparency = r.t or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Name = r.tag or "Piece"
	return p
end

-- The rows into two models: the far-seen pieces kept streamed (Persistent), the rest streamed as usual
local function build(name: string, rows: { any }, parent: Instance): (Model, Model)
	local near = Instance.new("Model")
	near.Name = name
	local far = Instance.new("Model")
	far.Name = name .. "Sky"
	far.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, r in rows do
		part(r).Parent = if r.far then far else near
	end
	near.Parent = parent
	far.Parent = parent
	return near, far
end

-- A name over a spot (rings, counters)
local function label(parent: Instance, at: Vector3, text: string, color: Color3, size: number, range: number)
	local a = Instance.new("Part")
	a.Name = "Label"
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Transparency = 1
	a.Size = Vector3.one
	a.Position = at
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(size * 12, size * 2)
	g.MaxDistance = range
	g.AlwaysOnTop = false
	g.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.LuckiestGuy
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.Parent = g
	g.Parent = a
	a.Parent = parent
end

-- the friends and squadmates flying close enough to come along (the leader first)
local function friends(a: Player, b: Player): boolean
	if SquadService.allies(a, b) then
		return true
	end
	local key = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
	local known = friendCache[key]
	if known == nil then
		local ok, yes = pcall(a.IsFriendsWithAsync, a, b.UserId)
		known = ok and yes == true
		friendCache[key] = known
	end
	return known
end

local function heroPos(player: Player): (any, Vector3?)
	local hero = HeroService.get(player)
	local pos = hero and hero.alive and HeroService.position(hero)
	return hero, pos
end

local function canTravel(player: Player, dest: number): (boolean, string?)
	local hero, pos = heroPos(player)
	if not hero or not pos or going[player] or hero.traveling or hero.downed then
		return false, "wait"
	end
	if (readyAt[player] or 0) > os.clock() then
		return false, "wait"
	end
	if HeroService.inCombat(hero) then
		return false, "combat"
	end
	local scene = hero.scene
	if scene ~= nil and scene ~= "space" then
		return false, "wait"
	end
	return SpaceLayout.canGo(S, dest, hero.level or 1)
end

local function party(leader: Player, dest: number): { Player }
	local out = { leader }
	local _, lp = heroPos(leader)
	if not lp then
		return out
	end
	for _, p in Players:GetPlayers() do
		if p ~= leader then
			local _, pos = heroPos(p)
			if pos and (pos - lp).Magnitude <= S.party and friends(leader, p) and canTravel(p, dest) then
				table.insert(out, p)
			end
		end
	end
	return out
end

-- The trip itself, for the whole party: the entry on each device, then set down at the arrival still flying
function SpaceService.trip(leader: Player, dest: number, ship: boolean): boolean
	local ok, why = canTravel(leader, dest)
	if not ok then
		Net.fire("SpaceDenied", leader, dest, why or "wait")
		return false
	end
	local secs = if ship then S.ship else S.entry
	local gate = SpaceService.gate
	for n, p in party(leader, dest) do
		going[p] = true
		readyAt[p] = os.clock() + secs + S.cooldown
		local ax, ay, az = SpaceLayout.arrival(S, dest, gate, n - 1)
		local land = Vector3.new(ax, ay, az)
		task.spawn(pcall, p.RequestStreamAroundAsync, p, land, secs)
		Net.fire("SpaceEntry", p, dest, secs, if ship then 1 else 0)
		task.delay(secs, function()
			going[p] = nil
			local hero = HeroService.get(p)
			local model = p.Character
			if not (hero and hero.alive and model and model.Parent) then
				return
			end
			-- face onward: in orbit toward the planets, on a world toward its middle, home toward the Hall
			local look = if dest == 0 then land + Vector3.new(0, 0, -10) else land + Vector3.new(0, -2, 10)
			if dest ~= 0 and not S.worlds[dest].home then
				local gx, gy, gz = SpaceLayout.ground(S, dest)
				look = Vector3.new(gx, gy + 40, gz)
			end
			model:PivotTo(CFrame.lookAt(land, look))
			MoveGuard.reset(hero)
			Net.fire("SpaceArrive", p, dest)
		end)
	end
	return true
end

-- A ring trip asked for by a device: the hero must be at that ring
local function asked(player: Player, dest: number)
	local _, pos = heroPos(player)
	if not pos then
		return
	end
	local p = { pos.X, pos.Y, pos.Z }
	local zone = SpaceLayout.zoneAt(S, pos.X, pos.Y, pos.Z)
	local ring: SpaceLayout.Ring?
	if dest == 0 then
		if zone == nil then
			ring = SpaceService.gate
		elseif type(zone) == "number" then
			ring = SpaceLayout.back(S, zone)
		end
	elseif zone == "orbit" and S.worlds[dest] then
		ring = SpaceLayout.ring(S, dest)
	end
	if not ring or not SpaceLayout.near(ring, p, S.ringSlack) then
		Net.fire("SpaceDenied", player, dest, "far")
		return
	end
	SpaceService.trip(player, dest, false)
end

-- A ship counter: a prompt that starts the same trip with the ship's cutscene
local function counter(at: BasePart, dest: number, text: string)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = text
	pr.ObjectText = "SHIP"
	pr.HoldDuration = 0.4
	pr.MaxActivationDistance = 12
	pr.RequiresLineOfSight = false
	pr.Parent = at
	pr.Triggered:Connect(function(player)
		SpaceService.trip(player, dest, true)
	end)
end

-- hero.scene "space" while in the orbit or on a world; out of the orbit's floor goes home, past its edge back
local function sweep()
	local ox, _, oz = SpaceLayout.orbit(S)
	for _, player in Players:GetPlayers() do
		local hero, pos = heroPos(player)
		if hero and pos and not going[player] then
			local zone = SpaceLayout.zoneAt(S, pos.X, pos.Y, pos.Z)
			if zone ~= nil and hero.scene == nil then
				hero.scene = "space"
			elseif zone == nil and hero.scene == "space" then
				hero.scene = nil
				-- fell out of the orbit (below its floor, still off the map): home over the gate
				if lastZone[player] == "orbit" and SpaceService.gate and pos.Y > 2000 then
					local ax, ay, az = SpaceLayout.arrival(S, 1, SpaceService.gate, 0)
					local model = player.Character
					if model then
						model:PivotTo(CFrame.new(ax, ay, az))
						MoveGuard.reset(hero)
						Net.fire("SpaceArrive", player, 1)
					end
				end
			end
			if zone == "orbit" and (pos.X - ox) ^ 2 + (pos.Z - oz) ^ 2 > S.orbit.edge ^ 2 then
				local ax, ay, az = SpaceLayout.arrival(S, 0, nil, 0)
				local model = player.Character
				if model then
					model:PivotTo(CFrame.new(ax, ay, az))
					MoveGuard.reset(hero)
				end
			end
			lastZone[player] = zone
		end
	end
end

local function gatePad(): { x: number, y: number, z: number }?
	local world = CityBuilder.world
	local d = world and world.downtown
	if not d then
		return nil
	end
	if d.hall and d.hall.pad then
		return d.hall.pad
	end
	local b = d.beacon
	return b and { x = b.x, y = (Config.City.groundY or 0) + b.h, z = b.z } or nil
end

function SpaceService.init()
	if not S.on then
		return
	end
	task.spawn(function()
		while not (CityBuilder.world and CityBuilder.world.downtown) do
			task.wait(0.5)
		end
		local root = Instance.new("Folder")
		root.Name = "Space"
		-- the Orbit Gate and the spaceport over the Hall roof
		local pad = gatePad()
		if pad then
			local gate = SpaceLayout.gate(S, pad)
			SpaceService.gate = gate
			Workspace:SetAttribute("OrbitGate", Vector3.new(gate.x, gate.y, gate.z))
			local near = build("OrbitGate", SpaceLayout.hoop(gate, { 120, 220, 255 }, 24, "gate"), root)
			label(
				near,
				Vector3.new(gate.x, gate.y + gate.r + 10, gate.z),
				"ORBIT GATE",
				Color3.fromRGB(150, 230, 255),
				5,
				700
			)
			local sp = S.spaceport.at
			local desk = part({
				shape = "Block",
				p = { pad.x + sp[1], pad.y + 1.8, pad.z + sp[2] },
				s = { 5, 3.6, 2.4 },
				c = { 60, 64, 80 },
				m = "Metal",
				collide = true,
				tag = "Spaceport",
			})
			desk.Parent = near
			label(
				near,
				desk.Position + Vector3.new(0, 5, 0),
				"SPACEPORT",
				Color3.fromRGB(255, 210, 90),
				3,
				120
			)
			counter(desk, 0, "Fly to orbit")
		end
		-- the orbit
		local orbit = build("Orbit", SpaceLayout.orbitRows(S), root)
		for i, w in S.worlds do
			local r = SpaceLayout.ring(S, i)
			label(
				orbit,
				Vector3.new(r.x, r.y + r.r + 12, r.z),
				w.name,
				if w.locked then Color3.fromRGB(255, 110, 110) else Color3.fromRGB(150, 230, 255),
				6,
				2500
			)
			local desk = orbit:FindFirstChild("ship" .. i)
			if desk and desk:IsA("BasePart") then
				label(
					orbit,
					desk.Position + Vector3.new(0, 5, 0),
					w.name,
					Color3.fromRGB(255, 210, 90),
					3,
					120
				)
				counter(desk, i, if w.home then "Ship home" else "Ship to " .. w.id)
			end
		end
		-- the worlds
		for i, w in S.worlds do
			if w.zone then
				local m = build(w.id, SpaceLayout.worldRows(S, i), root)
				local b = SpaceLayout.back(S, i)
				label(
					m,
					Vector3.new(b.x, b.y + b.r + 10, b.z),
					"BACK TO ORBIT",
					Color3.fromRGB(150, 230, 255),
					5,
					600
				)
				local desk = m:FindFirstChild("ship0")
				if desk and desk:IsA("BasePart") then
					counter(desk, 0, "Ship to orbit")
				end
			end
		end
		root.Parent = Workspace
	end)
	Net.on("SpaceGo", asked)
	Players.PlayerRemoving:Connect(function(p)
		readyAt[p], going[p], lastZone[p] = nil, nil, nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(sweep)
			if not ok then
				warn("[SpaceService]", err)
			end
		end
	end)
end

return SpaceService
