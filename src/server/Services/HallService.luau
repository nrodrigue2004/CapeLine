--!strict
-- HallService: Crane's Hero Hall, the Beacon Tower's enterable base (Config.Hall; Shared.HallLayout builds its
-- boxes into the city). nate 2026-11-20 22:04Z: lobby, training floor, rooftop launch pad; 2026-11-21: "still
-- cant enter building by hub area and it doesnt look like a hub area".
-- * Prompts on the Hall's tagged parts (B, like every terminal): the shop counter, the boards screen and the
--   squad board open their panels on the device (attribute Terminal); the Contract Board opens here
--   (ContractService.openAt); the Loadout console and the Weapon Rack carry the safehouse terminals' names, so
--   TravelClient and WeaponRack open them (the Hall counts as a safe place: SafehouseService's HQ radius).
-- * Lifts: one stop on the lobby, the training floor and the roof; a stop's prompt opens the device's floor
--   picker, and HallLift rides from any stop to the one picked.
-- * The training floor: shared dummies (EnemyService targets that never fall) and a meter per hero (HallDps,
--   2 Hz while they hit); the Burst Test (a prompt on the pad: deal all you can in Config.Hall.training.burst
--   seconds) with this server's best five on the wall screen (HallState).
-- * The roof's launch pad: the device says when its hero stands on it (HallPad); the server checks the spot,
--   grants the flight (MoveGuard) and answers HallLaunch with where the arc goes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local MoveGuard = require(script.Parent.MoveGuard)
local SafehouseService = require(script.Parent.SafehouseService)
local ContractService = require(script.Parent.ContractService)

local HallService = {}

local H = Config.Hall
local T = H.training

type Meter = { hits: { { number } }, total: number, burstEnds: number?, burst: number }

local spots: any = nil
local dummyList: { { [string]: number } } = {}
local meters: { [Player]: Meter } = {}
local best: { { name: string, score: number, userId: number } } = {}
local padAt: { [Player]: number } = {}

local function meterOf(player: Player): Meter
	local m = meters[player]
	if not m then
		m = { hits = {}, total = 0, burstEnds = nil, burst = 0 }
		meters[player] = m
	end
	return m
end

local function statePacket(): { [string]: any }
	local rows = {}
	for _, b in best do
		table.insert(rows, { b.name, b.score })
	end
	return {
		dummies = dummyList,
		best = rows,
		seconds = T.burst.seconds,
		statues = spots.statues,
		pad = spots.pad,
		levels = spots.levels,
		centre = spots.centre,
		half = spots.half,
	}
end

local function broadcast()
	Net.fireAll("HallState", statePacket())
end

local function onHit(amount: number, heroId: number?)
	local hero = heroId and HeroService.byId(heroId)
	local player = hero and hero.player
	if player then
		local m = meterOf(player)
		table.insert(m.hits, { os.clock(), amount })
		m.total += amount
		if m.burstEnds and os.clock() <= m.burstEnds then
			m.burst += amount
		end
	end
	return amount, false -- a training dummy never falls
end

local function addDummies()
	local function add(s: any)
		local id = EnemyService.addTarget({
			x = s.x,
			y = s.y,
			z = s.z,
			r = s.r,
			hit = function(amount: number, heroId: number?)
				return onHit(amount, heroId)
			end,
		})
		table.insert(dummyList, { id = id, x = s.x, y = s.y, z = s.z, big = if s == spots.big then 1 else 0 })
	end
	for _, s in spots.dummies do
		add(s)
	end
	add(spots.big)
end

local function finishBurst(player: Player, m: Meter)
	local score = math.floor(m.burst + 0.5)
	m.burstEnds = nil
	Net.fire("HallDps", player, { burstDone = score })
	if score <= 0 then
		return
	end
	-- this server's best five, one row per player (their best)
	for i, b in best do
		if b.userId == player.UserId then
			if b.score >= score then
				return
			end
			table.remove(best, i)
			break
		end
	end
	table.insert(best, { name = player.DisplayName, score = score, userId = player.UserId })
	table.sort(best, function(a, b)
		return a.score > b.score
	end)
	while #best > T.burst.board do
		table.remove(best)
	end
	broadcast()
end

local function tick()
	local now = os.clock()
	for player, m in meters do
		local cutoff = now - T.window
		while #m.hits > 0 and m.hits[1][1] < cutoff do
			table.remove(m.hits, 1)
		end
		local ends = m.burstEnds
		if #m.hits == 0 and not ends then
			continue
		end
		local sum = 0
		for _, h in m.hits do
			sum += h[2]
		end
		local span = if #m.hits > 0 then math.max(1, math.min(T.window, now - m.hits[1][1])) else 1
		local packet: { [string]: any } = { dps = math.floor(sum / span + 0.5), total = math.floor(m.total) }
		if ends then
			packet.burst = { left = math.max(0, math.ceil(ends - now)), score = math.floor(m.burst + 0.5) }
		end
		Net.fire("HallDps", player, packet)
		if ends and now >= ends then
			finishBurst(player, m)
		end
	end
end

-- Is the player's hero alive and within `r` of a spot?
local function near(player: Player, s: any, r: number): any?
	local hero = HeroService.get(player)
	local pos = hero and hero.alive and HeroService.position(hero)
	if not pos then
		return nil
	end
	if (pos - Vector3.new(s.x, s.y, s.z)).Magnitude > r then
		return nil
	end
	return hero
end

local function prompt(part: BasePart, action: string, object: string, terminal: string?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "HallPrompt"
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = H.range
	p.KeyboardKeyCode = Enum.KeyCode.B -- E is Skill 2 (as every terminal)
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	if terminal then
		p:SetAttribute("Terminal", terminal)
	end
	p.Parent = part
	return p
end

-- The lift: one prompt per stop opens the device's floor picker; HallLift rides to the stop picked, from any stop
local function liftPrompt(part: BasePart, stop: number)
	local p = prompt(part, "Lift", spots.lifts[stop].name, "hallLift")
	p:SetAttribute("Stop", stop)
	p.MaxActivationDistance = H.lift.radius + 4
end

local function ride(player: Player, dest: number)
	local to = spots.lifts[dest]
	if not to then
		return
	end
	local hero = nil
	for i, s in spots.lifts do
		if i ~= dest then
			hero = hero or near(player, s, H.lift.radius + 6)
		end
	end
	if not hero then
		return
	end
	local at = Vector3.new(to.x, to.y + 3.5, to.z)
	local look = Vector3.new(spots.centre[1], at.Y, spots.centre[2])
	if (look - at).Magnitude < 1 then
		look = at + Vector3.new(0, 0, -1)
	end
	SafehouseService.place(hero, CFrame.lookAt(at, look))
end

local function wire(part: BasePart)
	local tag = part:GetAttribute("Tag")
	local ref = (part:GetAttribute("Ref") or 0) :: number
	if tag == "hallShop" then
		prompt(part, "Shop", "Hero Hall", "hallShop")
	elseif tag == "hallBoards" then
		prompt(part, "Weekly Boards", "Hero Hall", "hallBoards")
	elseif tag == "hallSquads" then
		prompt(part, "Squads", "Hero Hall", "hallSquads")
	elseif tag == "hallContracts" then
		local p = prompt(part, "Contract Board", "Hero Hall")
		p.Triggered:Connect(function(player)
			if near(player, spots.hallContracts, H.range + 4) then
				ContractService.openAt(player, part.Position)
			end
		end)
	elseif tag == "hallLoadout" then
		prompt(part, "Loadout", "Hero Hall", "loadout")
	elseif tag == "hallWeapons" then
		prompt(part, "Weapon Rack", "Hero Hall", "weapons")
	elseif tag == "hallLift" then
		liftPrompt(part, ref)
	elseif tag == "hallBurst" then
		local p = prompt(part, string.format("Burst Test (%d s)", T.burst.seconds), "Training Floor")
		p.MaxActivationDistance = T.burst.radius + 4
		p.Triggered:Connect(function(player)
			if not near(player, spots.burst, T.burst.radius + 6) then
				return
			end
			local m = meterOf(player)
			if m.burstEnds then
				return
			end
			m.burst = 0
			m.burstEnds = os.clock() + T.burst.seconds
			Net.fire("HallDps", player, { burst = { left = T.burst.seconds, score = 0 }, burstStart = true })
		end)
	end
end

local function onPad(player: Player)
	local pad = spots.pad
	local now = os.clock()
	if now - (padAt[player] or -math.huge) < 2 then
		return
	end
	local hero = near(player, pad, pad.r + 3)
	if not hero then
		return
	end
	padAt[player] = now
	local R = H.roof.pad
	local from = Vector3.new(pad.x, pad.y, pad.z)
	local to = from + Vector3.new(pad.dir[1] * R.out * 2, -R.up, pad.dir[2] * R.out * 2)
	local time = 2.4
	MoveGuard.grant(hero, (to - from).Magnitude + R.up * 2 + 40)
	Net.fire("HallLaunch", player, { to = { to.X, to.Y, to.Z }, time = time, height = R.up })
end

function HallService.spots(): any
	return spots
end

function HallService.init()
	spots = CityBuilder.world and CityBuilder.world.downtown and CityBuilder.world.downtown.hall
	if not (H.on and spots) then
		return
	end
	local city = CityBuilder.folder
	for _, part in (city :: Folder):GetDescendants() do
		if part:IsA("BasePart") then
			local tag = part:GetAttribute("Tag")
			if type(tag) == "string" and string.sub(tag, 1, 4) == "hall" then
				wire(part)
			end
		end
	end
	addDummies()
	Net.on("HallPad", onPad)
	Net.on("HallLift", ride)
	Players.PlayerAdded:Connect(function(player)
		Net.fire("HallState", player, statePacket())
	end)
	for _, player in Players:GetPlayers() do
		Net.fire("HallState", player, statePacket())
	end
	Players.PlayerRemoving:Connect(function(player)
		meters[player] = nil
		padAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			tick()
		end
	end)
end

return HallService
