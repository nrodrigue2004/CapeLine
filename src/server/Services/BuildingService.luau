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
-- * Red Faction-style (nate 2026-11-16): a hit knocks pieces out of the building where it lands (Shared.
--   Structure: pillars, wall panels, floor slabs) and whatever loses its support falls; knock out a storey's
--   supports and it and everything above come down, the ground storey and the whole building goes. Each
--   piece is one bit: the server sends the pieces removed (2 Hz) and every Damaged building's bits in the
--   snapshot, and devices draw the holes and the falling pieces. A Damaged building stops blocking the
--   server's line of sight (shots go through its holes); a storey that fell lowers its height for robots.
-- * Remotes: BuildingSnapshot (the packed 2-bit states, on request at join), BuildingDiff (2 Hz batches of
--   changes and drone jobs), BuildingImpact.
-- * Audit fixes (2026-11-18): a skyscraper's crown (its setbacks and spire, up to its peak) takes hits too, on its
--   top storey; a building the collapse cap held up comes down once there is room (BuildingState.stepHeld);
--   repairs go out with the diffs (r); ray() lets combat rays stop on a Damaged building's standing pieces.
-- * Pins (2026-11-18): a beacon's host never breaks (WorldMap `fixed`), and pin(id, on) holds a roof whole while a
--   side quest goal stands on it (BuildingState.pin); a knockback never picks a pinned wall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local BuildingState = require(Shared:WaitForChild("BuildingState"))
local Structure = require(Shared:WaitForChild("Structure"))
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

-- wrecked: no collision or queries (Collapsed); open: queries off only (Damaged: shots pass its holes)
local function setWrecked(id: number, wrecked: boolean, open: boolean?)
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
		f.part.CanQuery = if wrecked or open then false else f.query
	end
	CityBuilder.collapsed[id] = if wrecked then records[id] else nil
	if not wrecked and not open then
		CityBuilder.tops[id] = nil
	end
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

-- What a blast did to building id: citizens run, a fallen storey lowers its height, a collapse wrecks it
local function settle(id: number, r: BuildingState.Blast)
	local b = records[id]
	local flee = math.max(b.sx, b.sz) / 2 + D.citizens.fleeRadius
	if r.warn then
		BuildingService.Danger:Fire(b.x, b.z, flee, 10)
	end
	if r.state == BuildingState.COLLAPSED and r.changed then
		setWrecked(id, true)
		BuildingService.Danger:Fire(b.x, b.z, flee, D.collapseTime + 4)
		BuildingService.Collapsed:Fire(b)
	elseif r.state == BuildingState.DAMAGED then
		if r.changed then
			setWrecked(id, false, true)
		end
		if r.failed then
			local grid = BuildingState.grid(D, BuildingService.book, id)
			local gone = BuildingService.book.gone[id]
			if grid and gone then
				CityBuilder.tops[id] = { box = b, top = Structure.standingTop(grid, gone) }
			end
			BuildingService.Danger:Fire(b.x, b.z, flee, D.collapseTime)
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
		if BuildingState.touches(b, center.X, center.Y, center.Z, radius) then
			n += 1
			local y = BuildingState.blastY(b, center.Y)
			settle(id, BuildingState.blast(D, book, id, center.X, y, center.Z, radius, dmg, now))
		end
	end
	if dmg >= D.structure.chunkCost then -- basic hits chip quietly (no crater, cracks or running citizens)
		impact(center, radius, kind or 2)
		-- citizens near any big hit run too, wreckable building or not
		BuildingService.Danger:Fire(center.X, center.Z, radius + 20, 4)
	end
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
		if
			book.state[id] ~= BuildingState.COLLAPSED
			and at.Y < b.top + 4
			and not BuildingState.pinned(book, id)
		then
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
	-- the panels where the robot goes through break (the wall face nearest the robot, at its height)
	local b = records[best]
	local px = math.clamp(at.X, b.x - b.sx / 2, b.x + b.sx / 2)
	local pz = math.clamp(at.Z, b.z - b.sz / 2, b.z + b.sz / 2)
	settle(best, BuildingState.punch(D, book, best, px, math.max(at.Y, b.base + 2), pz, now))
	return Vector3.new(b.x - at.X, 0, b.z - at.Z).Unit
end

-- Studs along a unit ray to the first standing piece of a Damaged building, or max (CombatService's rays:
-- a Damaged building's real body no longer blocks on the server, its pieces do, so shots pass only its holes)
function BuildingService.ray(origin: Vector3, dir: Vector3, max: number): number
	local book = BuildingService.book
	if not book or max <= 0 then
		return max
	end
	return BuildingState.ray(D, book, origin.X, origin.Y, origin.Z, dir.X, dir.Y, dir.Z, max)
end

function BuildingService.state(id: number): number
	return BuildingService.book and BuildingService.book.state[id] or 0
end

-- Hold building id whole while something stands on its roof (on), or let it go (off; holders count)
function BuildingService.pin(id: number, on: boolean)
	if BuildingService.book then
		BuildingState.pin(BuildingService.book, id, on)
	end
end

-- Put building id back whole now if it is wrecked (Damaged or Collapsed), the drones' and the Dev panel's
-- repair (devices drop its holes with the next diff). True when it was wrecked.
function BuildingService.repair(id: number): boolean
	local book = BuildingService.book
	if not book or not records[id] or (book.state[id] or 0) == 0 then
		return false
	end
	BuildingState.repair(book, id)
	setWrecked(id, false)
	return true
end

-- Studio: put every building back
function BuildingService.repairAll()
	for id in records do
		BuildingService.repair(id)
	end
end

local function flush()
	local book = BuildingService.book
	local fixed = BuildingState.takeFixed(book)
	local diffs = BuildingState.takeDiffs(book)
	local removed = BuildingState.takeRemoved(book)
	if #diffs == 0 and #droneJobs == 0 and #removed == 0 and #fixed == 0 then
		return
	end
	Net.fireAll("BuildingDiff", { r = fixed, d = diffs, dr = droneJobs, c = removed })
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
		Net.fire(
			"BuildingSnapshot",
			player,
			{ s = BuildingState.pack(book), n = book.n, dr = jobs, g = BuildingState.packGone(D, book) }
		)
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
			-- a building the collapse cap held up comes down once there is room
			for _, h in BuildingState.stepHeld(D, book, os.clock()) do
				settle(h.id, h.blast)
			end
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
