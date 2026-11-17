-- ContractService: Radiant contracts (spec: Radiant contracts; Contract.Accept, Contract.Abandon,
-- Contract.Update). The Contract Board terminal at every safehouse shows a hero 3 offers for their side
-- (ContractPlan); up to 3 run at once and are saved on the character, so they survive a rejoin (the seed
-- rebuilds the sites around the board they came from).
-- * Drone sweep: 3 Spark Trooper squads. Rescue run: 5 stranded citizens, carried to any safehouse.
--   Shard recovery: 3 hidden shards, found with the radar (distance and direction in Contract.Update).
--   Escort: a truck rolls 600 studs while a hero stays near it, with 2 ambushes. Vault job (villain): 2
--   vaults, each guarded by 2 turrets, cracked by holding at the door. Stakeout (hero): photograph 3
--   cloaking Sneak Bots by keeping them in view within 40 studs for 2 s.
-- * Pay: the contract table at the zone level, x2 for the first 5 each day, then the friend and Legacy
--   bonuses; plus a gear roll from the "contract" drop source.

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

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local DataService = require(script.Parent.DataService)
local SafehouseService = require(script.Parent.SafehouseService)
local IncidentService = require(script.Parent.IncidentService)
local SiteKit = require(script.Parent.SiteKit)
local Analytics = require(script.Parent.Analytics)

local ContractService = {}

local CC = Config.Contracts

type Run = {
	saved: ContractPlan.Saved,
	things: { any },
	squads: { { [number]: boolean } }, -- drone sweep: robot ids per squad
	shards: { any },
	truck: Model?,
	truckPos: Vector3?,
	path: { Vector3 }?,
	length: number,
	travelled: number,
	ambushed: number,
	vaults: { { guards: { [number]: boolean }, pos: Vector3, held: number, done: boolean } },
	sneaks: { [number]: number }, -- stakeout: robot id -> seconds in view
	tag: number,
}

local runs: { [Player]: { Run } } = {}
local boardAt: { [Player]: Vector3 } = {}
local byEnemy: { [number]: { player: Player, run: Run } } = {}
local nextTag = 1000000

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
		Config.World.clock.nightVillain
	)
end

local function view(player: Player): { [string]: any }
	local c = char(player)
	local profile = DataService.get(player)
	local active = {}
	for _, r in runs[player] or {} do
		table.insert(
			active,
			{ CC.types[r.saved.type].num, r.saved.got, ContractPlan.goal(CC, r.saved.type), r.saved.level }
		)
	end
	local offers = {}
	for _, o in offersFor(player) do
		local taken = false
		for _, r in runs[player] or {} do
			if r.saved.type == o.type then
				taken = true
			end
		end
		local credits, renown =
			ContractPlan.pay(Config, o.type, o.level, if profile then profile.daily.contractsDone else 99)
		table.insert(offers, { CC.types[o.type].num, o.level, credits, renown, if taken then 1 else 0 })
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

local function spots(r: Run, n: number, rng: any): { Vector3 }
	local out = {}
	local o = Vector3.new(r.saved.ox or 0, 0, r.saved.oz or 0)
	local world = CityBuilder.world
	for _ = 1, n * 4 do
		if #out >= n then
			break
		end
		local s =
			IncidentSpots.find(Config, world, "street", o.X, o.Z, CC.board.radius[1], CC.board.radius[2], rng)
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
		local credits, renown = ContractPlan.pay(Config, r.saved.type, r.saved.level, 99)
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
		GearService.grant(player, "contract", r.saved.level)
		EconomyService.Earned:Fire(player, "contract")
		Net.fire("Toast", player, {
			id = "contract",
			name = CC.types[r.saved.type].name,
			credits = credits,
			renown = renown,
			double = done < Config.Economy.bonus.firstContracts,
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

local function build(player: Player, r: Run)
	local t = r.saved.type
	local def = CC.types[t]
	local rng = Rng.new(r.saved.seed)
	local left = def.goal - r.saved.got
	local level = r.saved.level
	if t == "DroneSweep" then
		for _, p in spots(r, left, rng) do
			local ids = SiteKit.squad({ { kind = def.squad[1], n = def.squad[2] } }, p, level, r.tag, 14)
			table.insert(r.squads, tagEnemies(player, r, ids))
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
			SiteKit.part(m, Vector3.new(8, 6, 14), CFrame.new(0, 4, 3), Color3.fromRGB(230, 230, 235))
			SiteKit.part(m, Vector3.new(8, 5, 5), CFrame.new(0, 3.5, -7), Color3.fromRGB(60, 120, 200))
			SiteKit.part(
				m,
				Vector3.new(7.8, 2, 0.4),
				CFrame.new(0, 4.5, -9.6),
				Color3.fromRGB(150, 200, 230),
				Enum.Material.Glass
			)
		end)
		r.truckPos = path[1]
		SiteKit.place(r.truck, path[1])
		table.insert(r.things, r.truck)
	elseif t == "VaultJob" then
		for _, p in spots(r, left, rng) do
			local ids = SiteKit.squad({ { kind = def.guards[1], n = def.guards[2] } }, p, level, r.tag, 12)
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
			table.insert(r.things, m)
			table.insert(r.vaults, { guards = tagEnemies(player, r, ids), pos = p, held = 0, done = false })
		end
	elseif t == "Stakeout" then
		for _, p in spots(r, left, rng) do
			local ids = SiteKit.squad({ { kind = "SneakBot", n = 1 } }, p, level, r.tag, 2)
			for id in tagEnemies(player, r, ids) do
				r.sneaks[id] = 0
			end
		end
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
	if r.saved.type == "DroneSweep" then
		for i, squad in r.squads do
			if squad[enemyId :: number] then
				squad[enemyId :: number] = nil
				if next(squad) == nil then
					table.remove(r.squads, i)
					progress(link.player, r, 1)
				end
				break
			end
		end
	elseif r.saved.type == "VaultJob" then
		for _, v in r.vaults do
			v.guards[enemyId :: number] = nil
		end
	elseif r.saved.type == "Stakeout" then
		-- beaten before the photo: another Sneak Bot slips in nearby
		if r.sneaks[enemyId :: number] then
			r.sneaks[enemyId :: number] = nil
			local e = Vector3.new(_pos.X, _pos.Y, _pos.Z)
			local ids = SiteKit.squad(
				{ { kind = "SneakBot", n = 1 } },
				e + Vector3.new(60, 0, 0),
				r.saved.level,
				r.tag,
				2
			)
			for id in tagEnemies(link.player, r, ids) do
				r.sneaks[id] = 0
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

local function stepRun(player: Player, r: Run, dt: number, pos: Vector3)
	local t = r.saved.type
	local def = CC.types[t]
	if t == "Escort" and r.truck and r.path and r.truckPos then
		local near = #SiteKit.heroesIn(r.truckPos, def.near) > 0
		if near and r.travelled < r.length then
			r.travelled = math.min(r.length, r.travelled + def.speed * dt)
			-- where along the path the truck is
			local left = r.travelled
			local at, yaw = r.path[#r.path], 0
			for i = 1, #r.path - 1 do
				local a, b = r.path[i], r.path[i + 1]
				local seg = (b - a).Magnitude
				if left <= seg then
					at = a:Lerp(b, left / math.max(seg, 1e-3))
					yaw = math.atan2(-(b.X - a.X), -(b.Z - a.Z))
					break
				end
				left -= seg
			end
			r.truckPos = at
			SiteKit.place(r.truck, at, yaw)
			local share = r.travelled / r.length
			if r.ambushed < #def.ambushAt and share >= def.ambushAt[r.ambushed + 1] then
				r.ambushed += 1
				local ids = SiteKit.squad(
					{ { kind = def.ambush[1], n = def.ambush[2] } },
					at,
					r.saved.level,
					r.tag,
					22
				)
				tagEnemies(player, r, ids)
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

local function radar(r: Run, pos: Vector3): (number, number, number)
	if r.saved.type ~= "ShardRecovery" then
		return 0, 0, 0
	end
	local best, bestD = nil, math.huge
	for _, h in r.shards do
		local d = (h.pos - pos).Magnitude
		if d < bestD then
			best, bestD = h, d
		end
	end
	if not best then
		return 0, 0, 0
	end
	local dir = (best.pos - pos) * Vector3.new(1, 0, 1)
	local u = if dir.Magnitude > 0.1 then dir.Unit else Vector3.zero
	return math.floor(bestD), math.floor(u.X * 100), math.floor(u.Z * 100)
end

-- Studio: finish a contract now
function ContractService.finishFirst(player: Player)
	local r = (runs[player] or {})[1]
	if r then
		complete(player, r)
	end
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
						stepRun(player, r, acc, pos)
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
					local rows = {}
					for _, r in list do
						local d, dx, dz = radar(r, pos)
						table.insert(rows, {
							CC.types[r.saved.type].num,
							r.saved.got,
							ContractPlan.goal(CC, r.saved.type),
							d,
							dx,
							dz,
						})
					end
					Net.fire("ContractUpdate", player, { list = rows })
				end
			end
		end
	end))
end

return ContractService
