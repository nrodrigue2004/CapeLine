-- CraterService: craters in the ground (fix-destroy, 2026-11-19, nate: "I literally want everything destructible even
-- terrain"; Shared.CraterRules). Heavy hits at the ground (supers, boss slams, pounds, big drops: BuildingService.hit
-- and ImpactService's ground landings call blast) dig a crater where they land:
-- * Terrain (the seabed sand and the rock under the water, Shared.DeepLayout): the voxels are read, dug out with
--   CraterRules.carve (a Water voxel never changes; a voxel dug under the water's surface becomes Water, so a water
--   volume never opens) and written; when the crater heals the voxels read before are written back.
-- * Part ground (roads, sidewalks, plazas, fields, sand: the city's ground is parts): every device draws the
--   crater (GroundFx) from the list this service keeps, so everyone sees the same craters, healing back together.
-- * Caps (Config.Destruction.ground): craters a second, live craters a 48-stud cell and in all, and terrain craters
--   never overlap (each writes back only its own voxels).
-- * destroy-all (2026-11-20): the park's Terrain lawns dig too, filling only from the park's own waters
--   (CraterRules.waterLevel: a lawn crater is a dry bowl), and a heavy hit on the open sea throws a splash on the
--   devices near (BuildingImpact kind 5, splashRate a second; the park's lake splashes through Fx.ParkLife).
-- * Remotes: CraterSync (a device asks once), CraterState (the live list), CraterAdd, CraterGone.
-- * Ground marks (2026-11-21, nate: "I'm still not noticing any terrain damage or craters"): a hit too light for a
--   crater (basic and skill hits at the ground, landings from height, thrown cars, robots slammed down) or one the
--   crater caps refuse leaves a mark (CraterRules.addMark, Config.Destruction.ground.marks, its own book and caps): a
--   scorch, or a shallow dent that digs the park's or the seabed's Terrain a little (never under a live crater: a
--   crater over a dent writes the dent's voxels back first). A hit in a live mark grows it. Marks ride on the craters'
--   remotes (wire field 9 the tier). A private mission run's craters and marks (blast's phase, PhaseRules) never touch
--   Terrain and go only to its party's devices (the Player's Phase attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CraterRules = require(Shared:WaitForChild("CraterRules"))
local PhaseRules = require(Shared:WaitForChild("PhaseRules"))
local ParkLayout = require(Shared:WaitForChild("ParkLayout"))

local PerfMonitor = require(script.Parent.PerfMonitor)

local CraterService = {}

local G = Config.Destruction.ground
local M = G.marks
local WATER_Y = Config.World.coast.waterY
local book = CraterRules.new()
local marks = CraterRules.new(M and M.idBase)
CraterService.marks = marks
CraterService.marked = 0 -- ground marks made since boot (PerfMonitor)
local saved: { [number]: { region: Region3, mats: any, occ: any } } = {}
CraterService.book = book
CraterService.dug = 0 -- terrain craters dug since boot (PerfMonitor)
CraterService.splashes = 0 -- sea splashes sent since boot (destroy-all)
local splash: (Vector3, number) -> ()

-- the city's part ground: what a crater may be drawn on (CityBuilder names each part by its kind)
local GROUND = {
	ground = true,
	sand = true,
	road = true,
	sidewalk = true,
	plaza = true,
	field = true,
	rock = true,
	mark = true,
}

local function wire(c: CraterRules.Crater): { any }
	return {
		c.id,
		c.x,
		c.y,
		c.z,
		c.r,
		if c.ground == "terrain" then 1 else 0,
		os.clock() - c.born,
		c.deep or 1,
		c.tier or 0,
	}
end

local function phaseOf(player: Player): number?
	return PhaseRules.read(player:GetAttribute("Phase"))
end

-- To every device that may see it (a phased one only to its party's)
local function send(name: string, c: CraterRules.Crater)
	if c.phase == nil then
		local w = wire(c)
		for _, player in Players:GetPlayers() do
			if phaseOf(player) == nil then
				Net.fire(name, player, w)
			end
		end
		return
	end
	local w = wire(c)
	for _, player in Players:GetPlayers() do
		if CraterRules.sees(c, phaseOf(player)) then
			Net.fire(name, player, w)
		end
	end
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local fx = Workspace:FindFirstChild("CityFx")
	if fx then
		table.insert(skip, fx)
	end
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = false
	return params
end

-- What ground is under `at`: "terrain", "part", or nil (water, a building, nothing near), and its surface point
local function groundAt(at: Vector3): (string?, Vector3?)
	local hit = Workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -(G.near + 8), 0), rayParams())
	if not hit then
		return nil, nil
	end
	if hit.Instance == Workspace.Terrain then
		if hit.Material == Enum.Material.Water then
			return "water", hit.Position
		end
		return "terrain", hit.Position
	end
	local inst = hit.Instance
	-- a flat walkable prop is ground too: piers, boardwalks, a fountain's basin (fix-destroy: they crater, never fall)
	local flat = inst:IsA("BasePart")
		and inst.Name == "prop"
		and inst.Size.Y <= 2.5
		and math.min(inst.Size.X, inst.Size.Z) >= 6
	if inst:IsA("BasePart") and (GROUND[inst.Name] or flat) then
		local m = inst.Parent
		while m and m ~= Workspace do
			if m:GetAttribute("BuildingId") ~= nil then
				return nil, nil -- a roof: the building takes the hit
			end
			m = m.Parent
		end
		return "part", hit.Position
	end
	return nil, nil
end

-- A heavy hit on the open sea: a splash on the devices near (BuildingImpact kind 5), splashRate a second
local splashTimes: { number } = {}
splash = function(at: Vector3, radius: number)
	local world = require(script.Parent.CityBuilder).world
	if CraterRules.inPark(world and world.park, at.X, at.Z) then
		return -- the park's waters splash on each device already (Fx.ParkLife)
	end
	local now = os.clock()
	for i = #splashTimes, 1, -1 do
		if now - splashTimes[i] > 1 then
			table.remove(splashTimes, i)
		end
	end
	if #splashTimes >= (G.splashRate or 4) then
		return
	end
	table.insert(splashTimes, now)
	local r2 = Config.Destruction.impactRadius ^ 2
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - at).Magnitude ^ 2 <= r2 then
			Net.fire("BuildingImpact", player, at, radius, 5)
		end
	end
	CraterService.splashes += 1
end

-- Dig a terrain crater's voxels: read once (the read is kept for the heal; its region covers the deepest it can
-- go), then every dig carves from that read at the crater's depth now (deeper after more hits, shallower as it fills
-- back: scale) and writes it. Returns true when written.
local filled: { [number]: number } = {} -- crater id -> the fill scale last written
local function cfgOf(c: CraterRules.Crater): any
	return if (c.tier or 0) > 0 then M else G
end
local function dig(c: CraterRules.Crater, scale: number?): boolean
	local terrain = Workspace.Terrain
	local cfg = cfgOf(c)
	local lo, hi = CraterRules.region(cfg, c)
	local s = saved[c.id]
	if not s then
		local region = Region3.new(Vector3.new(lo[1], lo[2], lo[3]), Vector3.new(hi[1], hi[2], hi[3]))
		local ok, mats, occ = pcall(terrain.ReadVoxels, terrain, region, cfg.voxel)
		if not ok then
			return false
		end
		s = { region = region, mats = mats, occ = occ }
	end
	local keep = s :: any
	-- names for the pure carve, from the original read every time
	local names, occs = {}, {}
	for i, plane in keep.mats do
		names[i], occs[i] = {}, {}
		for j, row in plane do
			names[i][j], occs[i][j] = {}, {}
			for k, m in row do
				names[i][j][k] = m.Name
				occs[i][j][k] = keep.occ[i][j][k]
			end
		end
	end
	local world = require(script.Parent.CityBuilder).world -- (required here: the park is built after boot)
	local waterY = CraterRules.waterLevel(cfg, world and world.park, WATER_Y, c.x, c.z, ParkLayout.inside)
	if CraterRules.carve(cfg, c, lo, names, occs, waterY, scale) == 0 and not saved[c.id] then
		return false
	end
	local mats, occ = {}, {}
	for i, plane in names do
		mats[i], occ[i] = {}, {}
		for j, row in plane do
			mats[i][j], occ[i][j] = {}, {}
			for k, n in row do
				mats[i][j][k] = (Enum.Material :: any)[n]
				occ[i][j][k] = occs[i][j][k]
			end
		end
	end
	local wrote = pcall(terrain.WriteVoxels, terrain, keep.region, cfg.voxel, mats, occ)
	if wrote then
		if not saved[c.id] then
			CraterService.dug += 1
		end
		saved[c.id] = keep
		filled[c.id] = scale or 1
	end
	return wrote
end

-- Write a terrain crater's or mark's voxels back as read (it healed, or a crater is dug over it)
local function restore(c: CraterRules.Crater)
	local sv = saved[c.id]
	filled[c.id] = nil
	if sv then
		saved[c.id] = nil
		local terrain = Workspace.Terrain
		pcall(terrain.WriteVoxels, terrain, sv.region, cfgOf(c).voxel, sv.mats, sv.occ)
	end
end

-- A ground mark where a lighter hit meets the ground (2026-11-21): grown if it lands in a live one, else a new scorch
-- or dent inside the marks' caps. Returns the mark or nil.
local function mark(surface: Vector3, kind: string, dmg: number, phase: number?): CraterRules.Crater?
	local now = os.clock()
	local grown = CraterRules.grow(M, marks, surface.X, surface.Z, dmg, phase, now)
	if grown then
		if grown.ground == "terrain" then
			dig(grown)
		end
		send("CraterAdd", grown)
		return grown
	end
	if kind == "terrain" and (#CraterRules.overlapping(G, book, surface.X, surface.Z, M.radius[2]) > 0) then
		return nil -- (inside a live crater's bowl: its voxels are the crater's)
	end
	local c = CraterRules.addMark(M, marks, surface.X, surface.Y, surface.Z, dmg, kind, phase, now)
	if not c then
		return nil
	end
	if c.ground == "terrain" and not dig(c) then
		c.ground = "part"
	end
	CraterService.marked += 1
	send("CraterAdd", c)
	return c
end

-- A heavy hit at `at` (dmg structure damage, radius its blast): a crater in the ground under it, if the ground is
-- close under it and the caps allow; a lighter one (or one the crater caps refuse) leaves a ground mark (2026-11-21).
-- phase: the hitter's private mission run (PhaseRules), whose craters only its party sees and which never dig Terrain.
-- Returns the crater or mark, or nil.
function CraterService.blast(at: Vector3, radius: number, dmg: number, phase: number?): CraterRules.Crater?
	local markOk = M ~= nil and M.on and dmg >= M.minDmg
	if not G.on or (dmg < G.minDmg and dmg < (G.splashMin or math.huge) and not markOk) then
		return nil
	end
	if dmg < G.minDmg and dmg < (G.splashMin or math.huge) and CraterRules.busy(M, marks, os.clock()) then
		return nil -- (a flurry of light hits: past the marks' rate, no ray at all)
	end
	local t0 = os.clock()
	local kind, surface = groundAt(at)
	local near = if dmg >= G.minDmg then G.near else math.min(G.near, M and M.near or G.near)
	if not kind or not surface or at.Y - surface.Y > near + radius * 0.5 then
		return nil
	end
	if kind == "water" then
		if phase == nil and dmg >= (G.splashMin or math.huge) then
			splash(surface, radius)
		end
		return nil
	end
	if phase ~= nil and kind == "terrain" then
		kind = "part" -- a private run never changes the shared ground
	end
	if dmg < G.minDmg then
		local c = if markOk then mark(surface, kind, dmg, phase) else nil
		PerfMonitor.add("buildings", (os.clock() - t0) * 1000)
		return c
	end
	-- another heavy hit in a live crater digs it deeper (destroy-all round 3) instead of a new one beside it
	local deeper = if phase == nil then CraterRules.deepen(G, book, surface.X, surface.Z, os.clock()) else nil
	if deeper then
		if deeper.ground == "terrain" then
			dig(deeper)
		end
		send("CraterAdd", deeper)
		PerfMonitor.add("buildings", (os.clock() - t0) * 1000)
		return deeper
	end
	local c = CraterRules.add(G, book, surface.X, surface.Y, surface.Z, dmg, kind, os.clock())
	if not c then
		-- the crater caps said no: the ground still shows the hit
		local m = if markOk then mark(surface, kind, math.min(dmg, M.fullDmg), phase) else nil
		PerfMonitor.add("buildings", (os.clock() - t0) * 1000)
		return m
	end
	c.phase = phase
	if kind == "terrain" then
		-- the dents it is dug over give their voxels back first (each writes back only what it read)
		local gone = {}
		for _, m in CraterRules.overlapping(M, marks, c.x, c.z, c.r) do
			restore(m)
			local i = table.find(marks.list, m)
			if i then
				table.remove(marks.list, i)
			end
			table.insert(gone, m.id)
		end
		if #gone > 0 then
			Net.fireAll("CraterGone", gone)
		end
		if not dig(c) then
			c.ground = "part" -- nothing to dig there after all: drawn like part ground
		end
	end
	send("CraterAdd", c)
	PerfMonitor.add("buildings", (os.clock() - t0) * 1000)
	return c
end

function CraterService.init()
	Net.on("CraterSync", function(player)
		local list = {}
		local mine = phaseOf(player)
		for _, b in { book, marks } do
			for _, c in b.list do
				if CraterRules.sees(c, mine) then
					table.insert(list, wire(c))
				end
			end
		end
		Net.fire("CraterState", player, list)
	end)
	PerfMonitor.watch("craters", function()
		return #book.list + #marks.list
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			local now = os.clock()
			-- terrain bowls fill back in steps while they heal (destroy-all round 3)
			for _, c in book.list do
				if saved[c.id] then
					local scale = CraterRules.fillScale(G, c, now)
					if scale < (filled[c.id] or 1) then
						dig(c, scale)
					end
				end
			end
			local ids = {}
			for _, b in { { book, G }, { marks, M } } do
				if not b[2] then
					continue
				end
				for _, c in CraterRules.step(b[2], b[1], now) do
					table.insert(ids, c.id)
					restore(c)
				end
			end
			if #ids > 0 then
				Net.fireAll("CraterGone", ids)
			end
		end
	end)
end

return CraterService
