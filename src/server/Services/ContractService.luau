-- ContractService: Radiant contracts (spec: Radiant contracts; Contract.Accept, Contract.Abandon,
-- Contract.Update). The Contract Board terminal at every safehouse shows a hero 4 offers for their side
-- (ContractPlan); up to 3 run at once and are saved on the character, so they survive a rejoin (the seed
-- rebuilds the sites around the board they came from).
-- * Drone sweep: 3 Spark Trooper squads. Rescue run: 5 stranded citizens, carried to any safehouse.
--   Shard recovery: 3 hidden shards, found with the radar (distance and direction in Contract.Update).
--   Escort: a truck rolls 600 studs while a hero stays near it, with 2 ambushes. Vault job (villain): 2
--   vaults, each guarded by 2 turrets, cracked by holding at the door. Stakeout (hero): photograph 3
--   cloaking Sneak Bots by keeping them in view within 40 studs for 2 s.
-- * 2026-11-17: Bounty (an elite robot with a name from a fixed list, 3x HP, 3 levels up, with an escort),
--   Outpost demolition (break 3 guarded pylons), Rooftop courier (grab the parcel, touch 5 rooftop drops in
--   75 s; late puts the parcel back), Sabotage defusal (hero: 3 guarded charges, each fuse starts when you
--   come near; a popped one re-plants elsewhere), Photo recon (a Photo Mode shot from 3 rooftop lookouts)
--   and Protect the generator (hold its ring for 45 s while robots attack; it drains while empty). The
--   radar points at the next goal of the new ones too.
-- * Pay: the contract table at the zone level, x2 for the first 5 each day, then the friend and Legacy
--   bonuses; plus a gear roll from the "contract" drop source. A Heroic contract (level 40+, Shared.
--   HeroicRules) has robots 5 levels up and one more in each squad, and pays x1.5.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local ContractPlan = require(Shared:WaitForChild("ContractPlan"))
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))
local ZoneLevel = require(Shared:WaitForChild("ZoneLevel"))
local WorldClock = require(Shared:WaitForChild("WorldClock"))
local Progress = require(Shared:WaitForChild("Progress"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local HeroicRules = require(Shared:WaitForChild("HeroicRules"))
local EventPlan = require(Shared:WaitForChild("EventPlan"))
local DriveMath = require(Shared:WaitForChild("DriveMath")) -- gap-vehicles: the escort truck drives
local DRIVE = Config.Destruction.vehicles.drive

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local DataService = require(script.Parent.DataService)
local SafehouseService = require(script.Parent.SafehouseService)
local IncidentService = require(script.Parent.IncidentService)
local SiteKit = require(script.Parent.SiteKit)
local SetPieceMeshes = require(script.Parent.SetPieceMeshes)
local Analytics = require(script.Parent.Analytics)

local ContractService = {}

local CC = Config.Contracts
local ready = ContractPlan.readyFor(Config)

type Spot = {
	pos: Vector3,
	guards: { [number]: boolean },
	held: number,
	done: boolean,
	model: Model?,
	ring: Model?,
	woke: number?, -- defusal: when the fuse started
}

type Run = {
	saved: ContractPlan.Saved,
	things: { any },
	squads: { { [number]: boolean } }, -- drone sweep: robot ids per squad
	shards: { any },
	truck: Model?,
	truckPos: Vector3?,
	truckV: number?, -- gap-vehicles: the truck's speed (DriveMath)
	path: { Vector3 }?,
	length: number,
	travelled: number,
	ambushed: number,
	vaults: { Spot }, -- vault job, defusal charges, photo lookouts
	sneaks: { [number]: number }, -- stakeout: robot id -> seconds in view
	tag: number,
	-- 2026-11-17 types
	bountyId: number?,
	bountyAt: Vector3?,
	bountyRetry: number,
	drops: { Vector3 }?, -- courier: the parcel's roof, then the drops
	next: any?, -- courier: the pickup to touch now
	grabbedAt: number?,
	gen: Vector3?, -- protect the generator
	held: number,
	waveIdx: number,
	nextWave: number,
	alive: { [number]: boolean }, -- generator: robots of its waves still up
}

local runs: { [Player]: { Run } } = {}
local boardAt: { [Player]: Vector3 } = {}
local byEnemy: { [number]: { player: Player, run: Run } } = {}
local nextTag = 1000000
local fresh = Rng.new(Rng.hash(os.time(), 53)) -- re-planted charges go somewhere new

local function char(player: Player): any
	local profile = DataService.get(player)
	return profile and ProfileSchema.active(profile)
end

local function window(): number
	return os.time() // CC.board.refresh
end

local function night(): boolean
	return WorldClock.isNight(Config.World.clock, os.time() - IncidentService.clockStart)
end

local function enemyName(kind: string): string
	local e = Config.Enemies[kind]
	return e and e.name or kind
end

local function offersFor(player: Player): { ContractPlan.Saved }
	local hero = HeroService.get(player)
	if not hero then
		return {}
	end
	local at = boardAt[player] or HeroService.position(hero) or Vector3.zero
	local level = ZoneLevel.at(Config, at.X, at.Z, hero.level, CityBuilder.world.tiles)
	return ContractPlan.offers(
		CC,
		player.UserId,
		hero.side,
		window(),
		level,
		night(),
		Config.World.clock.nightVillain,
		Config
	)
end

local function view(player: Player): { [string]: any }
	local c = char(player)
	local profile = DataService.get(player)
	local active = {}
	for _, r in runs[player] or {} do
		local s = r.saved
		table.insert(active, {
			CC.types[s.type].num,
			s.got,
			ContractPlan.goal(CC, s.type),
			s.level,
			if s.heroic then 1 else 0,
			s.pick or 0,
		})
	end
	local offers = {}
	for _, o in offersFor(player) do
		local taken = false
		for _, r in runs[player] or {} do
			if r.saved.type == o.type then
				taken = true
			end
		end
		local credits, renown = ContractPlan.pay(
			Config,
			o.type,
			o.level,
			if profile then profile.daily.contractsDone else 99,
			o.heroic
		)
		table.insert(offers, {
			CC.types[o.type].num,
			o.level,
			credits,
			renown,
			if taken then 1 else 0,
			if o.heroic then 1 else 0,
			o.pick or 0,
		})
	end
	return {
		offers = offers,
		active = active,
		done = if profile then profile.daily.contractsDone else 0,
		level = if c then c.level else 1,
	}
end

local function save(player: Player)
	local c = char(player)
	if c then
		local list = {}
		for _, r in runs[player] or {} do
			table.insert(list, r.saved)
		end
		c.contracts = list
		DataService.saveSoon(player)
	end
end

---------------------------------------------------------------------------
-- Building a contract's sites
---------------------------------------------------------------------------

local function robotLevel(r: Run): number
	return HeroicRules.robotLevel(Config, r.saved.level, r.saved.heroic)
end

-- A squad row { kind, n, fallback? } at the contract's level (a type that is off or locked uses the
-- fallback), Heroic's extra robot added
local function rows(r: Run, list: { { any } }): { { kind: string, n: number } }
	local out = {}
	for i, row in list do
		local res = EventPlan.row(Config, row, r.saved.level, r.saved.heroic and i == 1, ready)
		if res then
			table.insert(out, res)
		end
	end
	return out
end

local function spots(r: Run, n: number, rng: any, kind: string?): { Vector3 }
	local out = {}
	local o = Vector3.new(r.saved.ox or 0, 0, r.saved.oz or 0)
	local world = CityBuilder.world
	for _ = 1, n * 4 do
		if #out >= n then
			break
		end
		local s = IncidentSpots.find(
			Config,
			world,
			kind or "street",
			o.X,
			o.Z,
			CC.board.radius[1],
			CC.board.radius[2],
			rng
		)
		if s then
			local p = Vector3.new(s.x, s.y, s.z)
			local ok = true
			for _, q in out do
				if (q - p).Magnitude < 80 then
					ok = false
				end
			end
			if ok then
				table.insert(out, p)
			end
		end
	end
	-- no roofs out here: the street does
	if kind and kind ~= "street" and #out < n then
		for _, p in spots(r, n - #out, rng, "street") do
			table.insert(out, p)
		end
	end
	return out
end

local function tagEnemies(player: Player, r: Run, ids: { number }): { [number]: boolean }
	local set = {}
	for _, id in ids do
		set[id] = true
		byEnemy[id] = { player = player, run = r }
		table.insert(r.things, id)
	end
	return set
end

local function squadAt(
	player: Player,
	r: Run,
	list: { { any } },
	p: Vector3,
	ring: number
): { [number]: boolean }
	local ids = SiteKit.squad(rows(r, list), p, robotLevel(r), r.tag, ring)
	return tagEnemies(player, r, ids)
end

-- Forget a run's robots and take its sites down
local function teardown(r: Run)
	for _, t in r.things do
		if type(t) == "number" then
			byEnemy[t] = nil
		end
	end
	SiteKit.clear(r.things)
end

local function complete(player: Player, r: Run)
	local list = runs[player]
	local i = list and table.find(list, r)
	if not i then
		return
	end
	table.remove(list, i)
	teardown(r)
	local profile = DataService.get(player)
	if profile then
		ProfileSchema.rollDay(profile, os.time())
		local done = profile.daily.contractsDone
		local credits, renown = ContractPlan.pay(Config, r.saved.type, r.saved.level, 99, r.saved.heroic)
		local m = Progress.multiplier(
			Config,
			EconomyService.bonus(player, { firstContract = done < Config.Economy.bonus.firstContracts })
		)
		credits, renown = math.floor(credits * m + 0.5), math.floor(renown * m + 0.5)
		profile.daily.contractsDone = done + 1
		Analytics.event(player, "contract_done", 1, {
			r.saved.type,
			if done < Config.Economy.bonus.firstContracts then "1" else "0",
		})
		profile.stats.contracts += 1 -- the trophy wall (M9)
		EconomyService.addCredits(player, credits)
		EconomyService.addRenown(player, renown)
		GearService.grant(player, "contract", HeroicRules.gearLevel(Config, r.saved.level, r.saved.heroic))
		EconomyService.Earned:Fire(player, "contract")
		local hero = HeroService.get(player)
		local name = ContractPlan.title(CC, r.saved, if hero then hero.side else "hero", enemyName, ready)
		Net.fire("Toast", player, {
			id = "contract",
			name = name,
			credits = credits,
			renown = renown,
			double = done < Config.Economy.bonus.firstContracts,
			heroic = r.saved.heroic or nil,
		})
	end
	save(player)
	Net.fire("ContractUpdate", player, { list = {}, done = CC.types[r.saved.type].num })
end

local function progress(player: Player, r: Run, amount: number)
	if ContractPlan.progress(CC, r.saved, amount) then
		complete(player, r)
	else
		save(player)
	end
end

local function chargeModel(p: Vector3): Model
	-- a robot charge with a blinking light (ActCharge on the device once imported)
	local m = SiteKit.model("Charge")
	SiteKit.part(
		m,
		Vector3.new(3, 2, 3),
		CFrame.new(p + Vector3.new(0, 1, 0)),
		Color3.fromRGB(60, 62, 70),
		Enum.Material.Metal
	)
	local light = SiteKit.part(
		m,
		Vector3.new(1, 1, 1),
		CFrame.new(p + Vector3.new(0, 2.5, 0)),
		Color3.fromRGB(255, 70, 60),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	light.Name = "Core"
	SiteKit.look(m, "Charge", CFrame.new(p))
	return m
end

local function pylonModel(m: Model)
	SiteKit.part(
		m,
		Vector3.new(3, 14, 3),
		CFrame.new(0, 7, 0),
		Color3.fromRGB(70, 74, 86),
		Enum.Material.Metal
	)
	SiteKit.part(
		m,
		Vector3.new(4, 1.2, 4),
		CFrame.new(0, 14, 0),
		Color3.fromRGB(255, 90, 60),
		Enum.Material.Neon
	)
	SiteKit.look(m, "Pylon")
end

-- Rooftop courier: put the next thing to touch (the parcel, then each drop) out
local function courierNext(player: Player, r: Run)
	local drops = r.drops
	if not drops then
		return
	end
	local def = CC.types.RooftopCourier
	local idx = if r.grabbedAt then r.saved.got + 2 else 1
	local at = drops[math.min(idx, #drops)]
	local h
	h = SiteKit.pickup(
		at,
		def.touch,
		if r.grabbedAt then Color3.fromRGB(255, 210, 70) else Color3.fromRGB(120, 255, 170),
		function()
			local i = table.find(r.things, h)
			if i then
				table.remove(r.things, i)
			end
			r.next = nil
			if not r.grabbedAt then
				r.grabbedAt = os.clock()
				Net.fire("Toast", player, { id = "courier", left = def.timeLimit })
				courierNext(player, r)
			else
				local runsOf = runs[player]
				progress(player, r, 1)
				if runsOf and table.find(runsOf, r) then
					courierNext(player, r)
				end
			end
		end,
		0,
		function(hero)
			return hero.player == player
		end
	)
	h.model:SetAttribute("Look", if r.grabbedAt then "DropPad" else "Parcel") -- (Shared.ActivityKit)
	r.next = h
	table.insert(r.things, h)
end

local function build(player: Player, r: Run)
	local t = r.saved.type
	local def = CC.types[t]
	local rng = Rng.new(r.saved.seed)
	local left = def.goal - r.saved.got
	local level = r.saved.level
	if t == "DroneSweep" then
		for _, p in spots(r, left, rng) do
			table.insert(r.squads, squadAt(player, r, { def.squad }, p, 14))
		end
	elseif t == "RescueRun" then
		for _, p in spots(r, left, rng) do
			local c = SiteKit.citizen(p, {
				anySafehouse = true,
				pads = {},
				onSafe = function(hero)
					if hero.player then
						EconomyService.reward(hero.player, "rescue", level)
						local profile = DataService.get(hero.player)
						if profile then
							profile.stats.rescues += 1
						end
					end
					IncidentService.Rescued:Fire(hero)
					progress(player, r, 1)
				end,
			})
			table.insert(r.things, c)
		end
	elseif t == "ShardRecovery" then
		for _, p in spots(r, left, rng) do
			local h
			h = SiteKit.pickup(
				p,
				def.pickup,
				Color3.fromRGB(150, 120, 255),
				function()
					local i = table.find(r.shards, h)
					if i then
						table.remove(r.shards, i)
					end
					progress(player, r, 1)
				end,
				0,
				function(hero)
					return hero.player == player -- only the contract's owner can pick up its shards
				end
			)
			table.insert(r.shards, h)
			table.insert(r.things, h)
		end
	elseif t == "Escort" then
		local start = spots(r, 1, rng)[1] or Vector3.new(r.saved.ox or 0, 0.5, r.saved.oz or 0)
		local pts = IncidentSpots.streetPath(Config, CityBuilder.world, start.X, start.Z, 16, 45, rng)
		local path = {}
		local length = 0
		for i, p in pts do
			table.insert(path, Vector3.new(p[1], Config.City.ground.y + 0.2, p[3]))
			if i > 1 then
				length += (path[i] - path[i - 1]).Magnitude
			end
		end
		r.path = path
		r.length = math.max(length, 1)
		r.travelled = r.saved.got / def.goal * r.length
		r.truck = SiteKit.prop("Truck", function(m)
			local boxes = {
				SiteKit.part(m, Vector3.new(8, 6, 14), CFrame.new(0, 4, 3), Color3.fromRGB(230, 230, 235)),
				SiteKit.part(m, Vector3.new(8, 5, 5), CFrame.new(0, 3.5, -7), Color3.fromRGB(60, 120, 200)),
				SiteKit.part(
					m,
					Vector3.new(7.8, 2, 0.4),
					CFrame.new(0, 4.5, -9.6),
					Color3.fromRGB(150, 200, 230),
					Enum.Material.Glass
				),
			}
			-- gap-vehicles (2026-11-19): the Docks truck's look in white over the boxes (8 x 20, the cab at -z),
			-- rigged so its wheels roll and it sways on every device near it (Fx.VehicleRig); the boxes before
			if SetPieceMeshes.ready("DockTruck") then
				for _, b in boxes do
					SetPieceMeshes.hide(b)
				end
				SetPieceMeshes.rig(
					m,
					SetPieceMeshes.add(m, {
						look = "DockTruck",
						x = 0,
						y = 0,
						z = 0,
						tint = { DockTruckBody = { 244, 244, 240 } },
					}, CFrame.new())
				)
			end
		end)
		r.truckPos = path[1]
		r.truckV = 0
		do
			local x, y, z, yaw = DriveMath.pose(path, r.travelled, DRIVE.round)
			r.truckPos = Vector3.new(x, y, z)
			SiteKit.place(r.truck, r.truckPos, yaw)
		end
		table.insert(r.things, r.truck)
	elseif t == "VaultJob" then
		for _, p in spots(r, left, rng) do
			local guards = squadAt(player, r, { def.guards }, p, 12)
			local m = SiteKit.model("Vault")
			SiteKit.part(
				m,
				Vector3.new(14, 12, 4),
				CFrame.new(p + Vector3.new(0, 6, 8)),
				Color3.fromRGB(110, 115, 125),
				Enum.Material.Metal
			)
			SiteKit.part(
				m,
				Vector3.new(1.2, 9, 9),
				CFrame.new(p + Vector3.new(0, 6, 5.6)) * CFrame.Angles(0, math.rad(90), 0),
				Color3.fromRGB(200, 170, 80),
				Enum.Material.Metal,
				Enum.PartType.Cylinder
			)
			SiteKit.look(m, "Vault", CFrame.new(p))
			table.insert(r.things, m)
			table.insert(r.vaults, { guards = guards, pos = p, held = 0, done = false })
		end
	elseif t == "Stakeout" then
		for _, p in spots(r, left, rng) do
			local ids = SiteKit.squad({ { kind = "SneakBot", n = 1 } }, p, robotLevel(r), r.tag, 2)
			for id in tagEnemies(player, r, ids) do
				r.sneaks[id] = 0
			end
		end
	elseif t == "Bounty" then
		r.bountyAt = spots(r, 1, rng)[1] or Vector3.new(r.saved.ox or 0, 0.5, r.saved.oz or 0)
		r.bountyRetry = 0 -- the elite spawns on the next tick (stepRun keeps it up until it falls)
		squadAt(player, r, { def.escort }, r.bountyAt :: Vector3, 10)
	elseif t == "Demolition" then
		local p = spots(r, 1, rng)[1] or Vector3.new(r.saved.ox or 0, 0.5, r.saved.oz or 0)
		local mast = SiteKit.prop("Outpost", function(m)
			-- the outpost's mast and its red lamp (ActOutpost on the device once imported)
			SiteKit.part(
				m,
				Vector3.new(2, 26, 2),
				CFrame.new(0, 13, 0),
				Color3.fromRGB(60, 62, 72),
				Enum.Material.Metal
			)
			SiteKit.part(
				m,
				Vector3.new(3, 3, 3),
				CFrame.new(0, 27, 0),
				Color3.fromRGB(255, 70, 60),
				Enum.Material.Neon,
				Enum.PartType.Ball
			)
			SiteKit.look(m, "Outpost")
		end)
		SiteKit.place(mast, p)
		table.insert(r.things, mast)
		for i = 1, left do
			local a = i / 3 * math.pi * 2
			local at = p + Vector3.new(math.cos(a) * def.spread, 0, math.sin(a) * def.spread)
			local hp = IncidentPlan.objectHp(Config, def.hits, robotLevel(r))
			local h = SiteKit.object("Pylon", at, 6, 4, hp, pylonModel, nil, function()
				progress(player, r, 1)
			end)
			SiteKit.moveObject(h, at, 0)
			table.insert(r.things, h)
		end
		squadAt(player, r, def.guards, p, 14)
	elseif t == "RooftopCourier" then
		-- a timed run: the clock restarts from the parcel after a rejoin
		r.saved.got = 0
		local o = Vector3.new(r.saved.ox or 0, 0, r.saved.oz or 0)
		local s = IncidentSpots.find(
			Config,
			CityBuilder.world,
			"roof",
			o.X,
			o.Z,
			CC.board.radius[1] * 0.5,
			CC.board.radius[2],
			rng,
			{ hops = def.goal + 1 }
		)
		local drops = {}
		for _, pt in (s and s.points) or {} do
			table.insert(drops, Vector3.new(pt[1], pt[2], pt[3]))
		end
		-- too few roofs together: street drops make up the rest
		for _, p in spots(r, def.goal + 1 - #drops, rng) do
			table.insert(drops, p)
		end
		r.drops = drops
		courierNext(player, r)
	elseif t == "Defusal" then
		for _, p in spots(r, left, rng) do
			local guards = squadAt(player, r, { def.guards }, p, 10)
			local m = chargeModel(p)
			local ring = SiteKit.ring(p, def.radius, Color3.fromRGB(255, 90, 60))
			table.insert(r.things, m)
			table.insert(r.things, ring)
			table.insert(
				r.vaults,
				{ guards = guards, pos = p, held = 0, done = false, model = m, ring = ring }
			)
		end
	elseif t == "PhotoRecon" then
		for _, p in spots(r, left, rng, "nest") do
			local ring = SiteKit.ring(p, def.range - 2, Color3.fromRGB(120, 220, 255))
			table.insert(r.things, ring)
			table.insert(r.vaults, { guards = {}, pos = p, held = 0, done = false, ring = ring })
		end
	elseif t == "GeneratorHold" then
		local p = spots(r, 1, rng)[1] or Vector3.new(r.saved.ox or 0, 0.5, r.saved.oz or 0)
		r.gen = p
		r.held = r.saved.got
		local m = SiteKit.prop("Generator", function(model)
			-- the generator and its core (ActGenerator on the device once imported; its glow takes the core's colour)
			SiteKit.part(
				model,
				Vector3.new(6, 6, 6),
				CFrame.new(0, 3, 0),
				Color3.fromRGB(70, 75, 85),
				Enum.Material.Metal
			)
			local core = SiteKit.part(
				model,
				Vector3.new(2, 2, 2),
				CFrame.new(0, 7, 0),
				Color3.fromRGB(120, 200, 255),
				Enum.Material.Neon,
				Enum.PartType.Ball
			)
			core.Name = "Core"
			SiteKit.look(model, "Generator")
		end)
		SiteKit.place(m, p)
		table.insert(r.things, m)
		table.insert(r.things, SiteKit.ring(p, def.radius, Color3.fromRGB(120, 200, 255)))
	end
end

local function newRun(saved: ContractPlan.Saved): Run
	nextTag += 1
	return {
		saved = saved,
		things = {},
		squads = {},
		shards = {},
		truck = nil,
		truckPos = nil,
		path = nil,
		length = 1,
		travelled = 0,
		ambushed = 0,
		vaults = {},
		sneaks = {},
		tag = nextTag,
		bountyRetry = 0,
		held = 0,
		waveIdx = 0,
		nextWave = 0,
		alive = {},
	}
end

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------

local function accept(player: Player, index: number)
	local hero = HeroService.get(player)
	local pos = hero and HeroService.position(hero)
	local at = boardAt[player]
	-- at the board, or at the HQ command table (M9: the offers are the last safehouse's)
	if not hero or not pos or not at or ((pos - at).Magnitude > 40 and hero.scene ~= "hq") then
		Net.fire("Toast", player, { id = "contractRefused", reason = "board" })
		return
	end
	local list = runs[player] or {}
	runs[player] = list
	local offer = offersFor(player)[index]
	local active = {}
	for _, r in list do
		table.insert(active, r.saved)
	end
	local ok, why = ContractPlan.canAccept(CC, hero.level, hero.side, active, offer)
	if not ok then
		Net.fire("Toast", player, { id = "contractRefused", reason = why })
		return
	end
	local saved = table.clone(offer :: ContractPlan.Saved)
	saved.ox, saved.oz = at.X, at.Z
	local r = newRun(saved)
	table.insert(list, r)
	build(player, r)
	save(player)
	Net.fire("ContractBoard", player, view(player))
end

local function abandon(player: Player, index: number)
	local list = runs[player]
	local r = list and list[index]
	if not r then
		return
	end
	table.remove(list, index)
	teardown(r)
	save(player)
	Net.fire("ContractUpdate", player, { list = {}, abandoned = CC.types[r.saved.type].num })
	Net.fire("ContractBoard", player, view(player))
end

local function onKilled(_kind: string, _by: number?, _pos: Vector3, enemyId: number?)
	local link = enemyId and byEnemy[enemyId]
	if not link then
		return
	end
	byEnemy[enemyId :: number] = nil
	local r = link.run
	local id = enemyId :: number
	r.alive[id] = nil
	if r.saved.type == "DroneSweep" then
		for i, squad in r.squads do
			if squad[id] then
				squad[id] = nil
				if next(squad) == nil then
					table.remove(r.squads, i)
					progress(link.player, r, 1)
				end
				break
			end
		end
	elseif r.saved.type == "VaultJob" or r.saved.type == "Defusal" then
		for _, v in r.vaults do
			v.guards[id] = nil
		end
	elseif r.saved.type == "Bounty" then
		if id == r.bountyId then
			r.bountyId = nil
			progress(link.player, r, 1)
		end
	elseif r.saved.type == "Stakeout" then
		-- beaten before the photo: another Sneak Bot slips in nearby
		if r.sneaks[id] then
			r.sneaks[id] = nil
			local e = Vector3.new(_pos.X, _pos.Y, _pos.Z)
			local ids = SiteKit.squad(
				{ { kind = "SneakBot", n = 1 } },
				e + Vector3.new(60, 0, 0),
				robotLevel(r),
				r.tag,
				2
			)
			for nid in tagEnemies(link.player, r, ids) do
				r.sneaks[nid] = 0
			end
		end
	end
end

-- Photo recon: a Photo Mode shot counts at a lookout the owner stands at
local function onPhoto(player: Player)
	local hero = HeroService.get(player)
	local pos = hero and HeroService.position(hero)
	if not pos then
		return
	end
	for _, r in table.clone(runs[player] or {}) do
		if r.saved.type == "PhotoRecon" then
			for _, v in r.vaults do
				if not v.done and (v.pos - pos).Magnitude <= CC.types.PhotoRecon.range then
					v.done = true
					if v.ring then
						v.ring:Destroy()
					end
					Net.fire("Toast", player, { id = "photoRecon" })
					progress(player, r, 1)
					break
				end
			end
		end
	end
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include

local function inView(from: Vector3, to: Vector3): boolean
	local city = Workspace:FindFirstChild("City")
	losParams.FilterDescendantsInstances = if city then { city } else {}
	local hit = Workspace:Raycast(from, to - from, losParams)
	return hit == nil
end

local function untag(r: Run, ids: { [number]: boolean })
	for id in ids do
		byEnemy[id] = nil
		EnemyService.remove(id)
		local i = table.find(r.things, id)
		if i then
			table.remove(r.things, i)
		end
	end
end

local function stepRun(player: Player, r: Run, dt: number, pos: Vector3)
	local t = r.saved.type
	local def = CC.types[t]
	local now = os.clock()
	if t == "Escort" and r.truck and r.path and r.truckPos then
		local near = #SiteKit.heroesIn(r.truckPos, def.near) > 0
		local v = r.truckV or 0
		if r.travelled < r.length and (near or v > 0) then
			-- gap-vehicles (2026-11-19): it drives (Shared.DriveMath): pulls away, slows into corners, turns through
			-- them and brakes when nobody is near
			r.travelled, r.truckV =
				DriveMath.step(r.travelled, v, def.speed, near, r.path, r.length, dt, DRIVE)
			local x, y, z, yaw = DriveMath.pose(r.path, r.travelled, DRIVE.round)
			local at = Vector3.new(x, y, z)
			r.truckPos = at
			SiteKit.place(r.truck, at, yaw)
			local share = r.travelled / r.length
			if r.ambushed < #def.ambushAt and share >= def.ambushAt[r.ambushed + 1] then
				r.ambushed += 1
				squadAt(player, r, { def.ambush }, at, 22)
			end
			-- progress in studs of the 600 (a shorter street path is scaled up to the full goal)
			local got = math.floor(share * def.goal + 1e-6)
			if got > r.saved.got then
				progress(player, r, got - r.saved.got)
			end
		end
	elseif t == "VaultJob" then
		for _, v in r.vaults do
			if not v.done and next(v.guards) == nil then
				local inRing = SiteKit.heroesIn(v.pos, 10)
				v.held += IncidentPlan.holdRate(Config.Incidents, #inRing) * dt
				if v.held >= def.crack then
					v.done = true
					progress(player, r, 1)
				end
			end
		end
	elseif t == "Defusal" then
		for _, v in table.clone(r.vaults) do
			if not v.done then
				if not v.woke and (v.pos - pos).Magnitude <= def.wake then
					v.woke = now
					Net.fire("Toast", player, { id = "fuse", left = def.fuse })
				end
				if next(v.guards) == nil then
					local inRing = SiteKit.heroesIn(v.pos, def.radius + 3)
					v.held += IncidentPlan.holdRate(Config.Incidents, #inRing) * dt
					if v.held >= def.defuse then
						v.done = true
						if v.model then
							v.model:Destroy()
						end
						if v.ring then
							v.ring:Destroy()
						end
						Net.fire("Toast", player, { id = "defused" })
						progress(player, r, 1)
						if not table.find(runs[player] or {}, r) then
							return
						end
					end
				end
				if not v.done and ContractPlan.fuseLeft(CC, v.woke, now) == 0 then
					-- it pops (a harmless cartoon puff) and the robots plant a new one somewhere else
					local i = table.find(r.vaults, v)
					if i then
						table.remove(r.vaults, i)
					end
					untag(r, v.guards)
					if v.model then
						v.model:Destroy()
					end
					if v.ring then
						v.ring:Destroy()
					end
					Net.fire("Toast", player, { id = "fizzled" })
					for _, p in spots(r, 1, fresh) do
						local guards = squadAt(player, r, { def.guards }, p, 10)
						local m = chargeModel(p)
						local ring = SiteKit.ring(p, def.radius, Color3.fromRGB(255, 90, 60))
						table.insert(r.things, m)
						table.insert(r.things, ring)
						table.insert(
							r.vaults,
							{ guards = guards, pos = p, held = 0, done = false, model = m, ring = ring }
						)
					end
				end
			end
		end
	elseif t == "Bounty" and r.bountyAt then
		-- keep the elite up until it falls (the server cap, or a respawn after a rejoin); a beaten elite whose
		-- Killed has not fired yet is dying, not gone: respawning it then lost the kill (2026-11-18 fix)
		if (not r.bountyId or EnemyService.gone(r.bountyId)) and now >= r.bountyRetry then
			r.bountyRetry = now + 5
			local _, kind = ContractPlan.bounty(CC, r.saved.pick, r.saved.level, ready)
			local id = EnemyService.spawnAt(kind, r.bountyAt, robotLevel(r) + def.elite.levelBonus, r.tag)
			if id then
				EnemyService.tune(id, { hpMult = def.elite.hpMult })
				r.bountyId = id
				tagEnemies(player, r, { id })
			end
		end
	elseif t == "RooftopCourier" and r.grabbedAt then
		if ContractPlan.courierLeft(CC, r.grabbedAt, now) == 0 then
			-- late: the parcel goes back to its roof
			if r.next then
				local i = table.find(r.things, r.next)
				if i then
					table.remove(r.things, i)
				end
				SiteKit.removePickup(r.next)
				r.next = nil
			end
			r.grabbedAt = nil
			r.saved.got = 0
			save(player)
			Net.fire("Toast", player, { id = "courierLate" })
			courierNext(player, r)
		end
	elseif t == "GeneratorHold" and r.gen then
		local holding = #SiteKit.heroesIn(r.gen, def.radius + 3) > 0
		local near = (r.gen - pos).Magnitude <= 150
		if near or r.held > 0 then
			r.held = ContractPlan.holdTick(CC, r.held, holding, dt)
		end
		local got = math.floor(r.held)
		if got ~= r.saved.got then
			progress(player, r, got - r.saved.got)
			if not table.find(runs[player] or {}, r) then
				return
			end
		end
		-- waves while the hero is near, never more than 8 robots up
		local up = 0
		for _ in r.alive do
			up += 1
		end
		if near and now >= r.nextWave and up < 8 then
			r.waveIdx = r.waveIdx % #def.waves + 1
			r.nextWave = now + def.waveEvery
			for id in squadAt(player, r, { def.waves[r.waveIdx] }, r.gen, 22) do
				r.alive[id] = true
			end
		end
	elseif t == "Stakeout" then
		local eye = pos + Vector3.new(0, 1.5, 0)
		for id, seen in r.sneaks do
			local e = EnemyService.get(id)
			if e and e.alive then
				local p = Vector3.new(e.x, e.y, e.z)
				if (p - eye).Magnitude <= def.photoRange and inView(eye, p) then
					r.sneaks[id] = seen + dt
					if r.sneaks[id] >= def.photoTime then
						r.sneaks[id] = nil
						byEnemy[id] = nil
						EnemyService.remove(id)
						Net.fire("Toast", player, { id = "photo" })
						progress(player, r, 1)
					end
				end
			end
		end
	end
end

-- The radar's goal for a contract: the nearest shard, the next courier stop, the bounty, a charge or a
-- lookout still to do. Returns distance and direction x 100 (0, 0, 0 for none).
local function radar(r: Run, pos: Vector3): (number, number, number)
	local t = r.saved.type
	local targets: { Vector3 } = {}
	if t == "ShardRecovery" then
		for _, h in r.shards do
			table.insert(targets, h.pos)
		end
	elseif t == "RooftopCourier" and r.next then
		table.insert(targets, r.next.pos)
	elseif t == "Bounty" and r.bountyId then
		local e = EnemyService.get(r.bountyId)
		if e and e.alive then
			table.insert(targets, Vector3.new(e.x, e.y, e.z))
		end
	elseif t == "Defusal" or t == "PhotoRecon" then
		for _, v in r.vaults do
			if not v.done then
				table.insert(targets, v.pos)
			end
		end
	end
	local best, bestD = nil, math.huge
	for _, p in targets do
		local d = (p - pos).Magnitude
		if d < bestD then
			best, bestD = p, d
		end
	end
	if not best then
		return 0, 0, 0
	end
	local dir = (best - pos) * Vector3.new(1, 0, 1)
	local u = if dir.Magnitude > 0.1 then dir.Unit else Vector3.zero
	return math.floor(bestD), math.floor(u.X * 100), math.floor(u.Z * 100)
end

-- Seconds left on a contract's clock (the courier's parcel, the nearest lit fuse), or 0
local function clock(r: Run): number
	local now = os.clock()
	if r.saved.type == "RooftopCourier" then
		return math.floor(ContractPlan.courierLeft(CC, r.grabbedAt, now) or 0)
	elseif r.saved.type == "Defusal" then
		local best = 0
		for _, v in r.vaults do
			local left = not v.done and ContractPlan.fuseLeft(CC, v.woke, now)
			if left and (best == 0 or left < best) then
				best = left
			end
		end
		return math.floor(best)
	end
	return 0
end

-- Studio: finish a contract now
function ContractService.finishFirst(player: Player)
	local r = (runs[player] or {})[1]
	if r then
		complete(player, r)
	end
end

-- Studio: start contract type n right here (no board), Heroic if asked; one of the same type is replaced
function ContractService.forceStart(player: Player, n: number, heroic: boolean?): boolean
	local id = CC.order[n]
	local hero = HeroService.get(player)
	local pos = hero and HeroService.position(hero)
	if not id or not hero or not pos then
		return false
	end
	local list = runs[player] or {}
	runs[player] = list
	for i, r in list do
		if r.saved.type == id then
			table.remove(list, i)
			teardown(r)
			break
		end
	end
	if #list >= CC.board.maxAccepted then
		teardown(table.remove(list, 1) :: Run)
	end
	local def = CC.types[id]
	local saved: ContractPlan.Saved = {
		type = id,
		seed = fresh:nextInt32() % 2147483647,
		level = ZoneLevel.at(Config, pos.X, pos.Z, hero.level, CityBuilder.world.tiles),
		got = 0,
		ox = pos.X,
		oz = pos.Z,
		heroic = if heroic then true else nil,
		pick = if def.names then fresh:int(1, #def.names) else nil,
	}
	local r = newRun(saved)
	table.insert(list, r)
	build(player, r)
	save(player)
	return true
end

function ContractService.init()
	SafehouseService.Board:Connect(function(player, safehouseId)
		local s = CityBuilder.world.safehouses[safehouseId]
		if not s then
			return
		end
		boardAt[player] = Vector3.new(s.x, s.y, s.z)
		local hero = HeroService.get(player)
		if hero and hero.level < CC.board.minLevel then
			Net.fire("Toast", player, { id = "contractRefused", reason = "level" })
			return
		end
		Net.fire("ContractBoard", player, view(player))
	end)
	Net.on("ContractAccept", accept)
	Net.on("ContractAbandon", abandon)
	EnemyService.Killed:Connect(onKilled)
	Analytics.Photo:Connect(onPhoto)
	DataService.Loaded:Connect(function(player, profile)
		local c = ProfileSchema.active(profile)
		ProfileSchema.rollDay(profile, os.time())
		local list = {}
		for _, saved in ContractPlan.repair(CC, c.contracts, Config.Stats.levelCap) do
			local r = newRun(saved)
			table.insert(list, r)
		end
		runs[player] = list
		-- build once the hero is in the world
		task.delay(3, function()
			for _, r in list do
				if runs[player] == list and table.find(list, r) then
					build(player, r)
				end
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, r in runs[player] or {} do
			teardown(r)
		end
		runs[player] = nil
		boardAt[player] = nil
	end)
	local acc, sendAcc = 0, 0
	RunService.Heartbeat:Connect(FrameProf.wrap("ContractService", function(dt)
		acc += dt
		sendAcc += dt
		if acc >= 0.2 then
			for player, list in runs do
				local hero = HeroService.get(player)
				local pos = hero and hero.alive and HeroService.position(hero)
				if pos then
					for _, r in table.clone(list) do
						if table.find(list, r) then
							stepRun(player, r, acc, pos)
						end
					end
				end
			end
			acc = 0
		end
		if sendAcc >= 1 / CC.board.updateRate then
			sendAcc = 0
			for player, list in runs do
				if #list > 0 then
					local hero = HeroService.get(player)
					local pos = hero and HeroService.position(hero) or Vector3.zero
					local out = {}
					for _, r in list do
						local d, dx, dz = radar(r, pos)
						table.insert(out, {
							CC.types[r.saved.type].num,
							r.saved.got,
							ContractPlan.goal(CC, r.saved.type),
							d,
							dx,
							dz,
							if r.saved.heroic then 1 else 0,
							r.saved.pick or 0,
							clock(r),
						})
					end
					Net.fire("ContractUpdate", player, { list = out })
				end
			end
		end
	end))
end

return ContractService
