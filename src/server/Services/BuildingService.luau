-- BuildingService: hub destruction on the server (spec: World > Destruction; Clash moments > Knockback arc,
-- Grab and slam, Stomp wave). The server keeps only each building's state (BuildingState) and tells clients;
-- the clients draw every chunk, crack, rubble heap and dust cloud, so a collapse costs the server a number.
-- * hit(center, radius, structDmg): every wreckable building the blast touches loses structure HP. Damaged
--   at 40% lost, Collapsed at 100% (at most 3 collapses at once; a 4th is cut to Damaged). Citizens nearby
--   run for shelter at 75% and on a collapse. A collapsed building stops blocking shots and bodies until it
--   is repaired; its heights drop to the rubble.
-- * clash(hero, at, from): a heavy hit near a wall knocks the robot through it and the wall turns Damaged
--   (3 per player per 10 s).
-- * Every structural hit, wreckable or not (outskirts houses, the Foundry), also sends an impact to nearby
--   players for craters and facade cracks (outskirts: cracks only, never collapses).
-- * Repair drones: 3 per district, each fixing the building that has been quiet longest (Damaged 180 s,
--   Collapsed 240 s), 20 s each.
-- * Remotes: BuildingSnapshot (the packed 2-bit states, on request at join), BuildingDiff (2 Hz batches of
--   changes and drone jobs), BuildingImpact.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local BuildingState = require(Shared:WaitForChild("BuildingState"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local PerfMonitor = require(script.Parent.PerfMonitor)

local BuildingService = {}

local D = Config.Destruction
BuildingService.book = nil :: any
BuildingService.Danger = Signal.new() -- (x, z, radius, seconds): citizens run (CitizenService)
BuildingService.Collapsed = Signal.new() -- (building)

local records: { [number]: any } = {}
local flags: { [number]: { { part: BasePart, collide: boolean, query: boolean } } } = {}
local droneJobs: { { number } } = {} -- drone id, building id, seconds left: sent with the next diff
local clashes: { [number]: { number } } = {} -- hero id -> clash times
local impactTimes: { number } = {}

local function setWrecked(id: number, wrecked: boolean)
	local model = CityBuilder.buildingModels[id]
	if not model then
		return
	end
	if not flags[id] then
		local list = {}
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(list, { part = p, collide = p.CanCollide, query = p.CanQuery })
			end
		end
		flags[id] = list
	end
	for _, f in flags[id] do
		f.part.CanCollide = if wrecked then false else f.collide
		f.part.CanQuery = if wrecked then false else f.query
	end
	CityBuilder.collapsed[id] = if wrecked then records[id] else nil
end

-- Does a blast at center with radius touch building b?
local function touches(b: any, center: Vector3, radius: number): boolean
	local dx = math.max(math.abs(center.X - b.x) - b.sx / 2, 0)
	local dz = math.max(math.abs(center.Z - b.z) - b.sz / 2, 0)
	local dy = math.max(center.Y - (b.top + 10), b.base - center.Y, 0)
	return dx * dx + dz * dz + dy * dy <= radius * radius
end

local function impact(center: Vector3, radius: number, kind: number)
	local now = os.clock()
	for i = #impactTimes, 1, -1 do
		if now - impactTimes[i] > 1 then
			table.remove(impactTimes, i)
		end
	end
	if #impactTimes >= D.impactRate then
		return
	end
	table.insert(impactTimes, now)
	local r2 = D.impactRadius * D.impactRadius
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local pos = hero and HeroService.position(hero)
		if pos and (pos - center).Magnitude ^ 2 <= r2 then
			Net.fire("BuildingImpact", player, center, radius, kind)
		end
	end
end

-- A structural hit. kind: 1 a slam or landing (crater), 2 a blast (cracks only). Returns buildings hit.
function BuildingService.hit(center: Vector3, radius: number, dmg: number, kind: number?): number
	local book = BuildingService.book
	if not book or dmg <= 0 then
		return 0
	end
	local t0 = os.clock()
	local now = os.clock()
	local n = 0
	for id, b in records do
		if touches(b, center, radius) then
			n += 1
			local state, changed, _, warn = BuildingState.hit(D, book, id, dmg, now)
			if warn then
				BuildingService.Danger:Fire(b.x, b.z, math.max(b.sx, b.sz) / 2 + D.citizens.fleeRadius, 10)
			end
			if changed and state == BuildingState.COLLAPSED then
				setWrecked(id, true)
				BuildingService.Danger:Fire(
					b.x,
					b.z,
					math.max(b.sx, b.sz) / 2 + D.citizens.fleeRadius,
					D.collapseTime + 4
				)
				BuildingService.Collapsed:Fire(b)
			end
		end
	end
	impact(center, radius, kind or 2)
	-- citizens near any big hit run too, wreckable building or not
	BuildingService.Danger:Fire(center.X, center.Z, radius + 20, 4)
	PerfMonitor.add("buildings", (os.clock() - t0) * 1000)
	return n
end

-- A heavy hit on a robot near a wall: the wall it is thrown through turns Damaged. Returns the knock
-- direction toward that wall, or nil (no wall in range or the per-player cap is reached).
function BuildingService.clash(hero: any, at: Vector3, from: Vector3): Vector3?
	local book = BuildingService.book
	if not book then
		return nil
	end
	local now = os.clock()
	local list = clashes[hero.id] or {}
	clashes[hero.id] = list
	for i = #list, 1, -1 do
		if now - list[i] > D.clash.window then
			table.remove(list, i)
		end
	end
	if #list >= D.clash.perPlayer then
		return nil
	end
	local away = Vector3.new(at.X - from.X, 0, at.Z - from.Z)
	if away.Magnitude < 0.1 then
		return nil
	end
	away = away.Unit
	local best, bestD = nil, D.clash.wallRange
	for id, b in records do
		if book.state[id] ~= BuildingState.COLLAPSED and at.Y < b.top + 4 then
			local dx = math.max(math.abs(at.X - b.x) - b.sx / 2, 0)
			local dz = math.max(math.abs(at.Z - b.z) - b.sz / 2, 0)
			local d = math.sqrt(dx * dx + dz * dz)
			local toward = Vector3.new(b.x - at.X, 0, b.z - at.Z)
			if d < bestD and toward.Magnitude > 0 and toward.Unit:Dot(away) > 0.3 then
				best, bestD = id, d
			end
		end
	end
	if not best then
		return nil
	end
	table.insert(list, now)
	BuildingState.force(D, book, best, now)
	local b = records[best]
	return Vector3.new(b.x - at.X, 0, b.z - at.Z).Unit
end

function BuildingService.state(id: number): number
	return BuildingService.book and BuildingService.book.state[id] or 0
end

-- Studio: put every building back
function BuildingService.repairAll()
	local book = BuildingService.book
	for id in records do
		if book.state[id] ~= 0 then
			BuildingState.repair(book, id)
			setWrecked(id, false)
		end
	end
end

local function flush()
	local book = BuildingService.book
	local diffs = BuildingState.takeDiffs(book)
	if #diffs == 0 and #droneJobs == 0 then
		return
	end
	Net.fireAll("BuildingDiff", { d = diffs, dr = droneJobs })
	droneJobs = {}
end

function BuildingService.init()
	local world = CityBuilder.world
	for _, b in world.buildings do
		records[b.id] = b
	end
	local book = BuildingState.new(D, world.buildings)
	BuildingService.book = book
	Net.on("BuildingSync", function(player)
		local jobs = {}
		local now = os.clock()
		for _, d in book.drones do
			if d.target then
				table.insert(jobs, { d.id, d.target, math.max(0, d.doneAt - now) })
			end
		end
		Net.fire("BuildingSnapshot", player, { s = BuildingState.pack(book), n = book.n, dr = jobs })
	end)
	PerfMonitor.watch("wrecked", function()
		local n = 0
		for id = 1, book.n do
			if book.state[id] ~= 0 then
				n += 1
			end
		end
		return n
	end)
	task.spawn(function()
		local step = 1 / D.diffRate
		local droneClock = 0
		while true do
			task.wait(step)
			droneClock += step
			if droneClock >= 1 then
				droneClock = 0
				local repaired, started = BuildingState.stepDrones(D, book, os.clock())
				for _, id in repaired do
					setWrecked(id, false)
				end
				for _, d in started do
					table.insert(droneJobs, { d.id, d.target :: number, D.repair.each })
				end
			end
			flush()
		end
	end)
end

return BuildingService
