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
-- * Remotes: CraterSync (a device asks once), CraterState (the live list), CraterAdd, CraterGone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CraterRules = require(Shared:WaitForChild("CraterRules"))

local PerfMonitor = require(script.Parent.PerfMonitor)

local CraterService = {}

local G = Config.Destruction.ground
local WATER_Y = Config.World.coast.waterY
local book = CraterRules.new()
local saved: { [number]: { region: Region3, mats: any, occ: any } } = {}
CraterService.book = book
CraterService.dug = 0 -- terrain craters dug since boot (PerfMonitor)

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
	return { c.id, c.x, c.y, c.z, c.r, if c.ground == "terrain" then 1 else 0, os.clock() - c.born }
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
			return nil, nil
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

-- Read, dig and write a terrain crater's voxels (the read is kept for the heal)
local function dig(c: CraterRules.Crater): boolean
	local lo, hi = CraterRules.region(G, c)
	local region = Region3.new(Vector3.new(lo[1], lo[2], lo[3]), Vector3.new(hi[1], hi[2], hi[3]))
	local terrain = Workspace.Terrain
	local ok, mats, occ = pcall(terrain.ReadVoxels, terrain, region, G.voxel)
	if not ok then
		return false
	end
	-- names for the pure carve, then back to materials (and a copy of the read for the heal)
	local names, occs = {}, {}
	local keepMats, keepOcc = {}, {}
	for i, plane in mats do
		names[i], occs[i], keepMats[i], keepOcc[i] = {}, {}, {}, {}
		for j, row in plane do
			names[i][j], occs[i][j], keepMats[i][j], keepOcc[i][j] = {}, {}, {}, {}
			for k, m in row do
				names[i][j][k] = m.Name
				occs[i][j][k] = occ[i][j][k]
				keepMats[i][j][k] = m
				keepOcc[i][j][k] = occ[i][j][k]
			end
		end
	end
	if CraterRules.carve(G, c, lo, names, occs, WATER_Y) == 0 then
		return false
	end
	for i, plane in names do
		for j, row in plane do
			for k, n in row do
				mats[i][j][k] = (Enum.Material :: any)[n]
				occ[i][j][k] = occs[i][j][k]
			end
		end
	end
	local wrote = pcall(terrain.WriteVoxels, terrain, region, G.voxel, mats, occ)
	if wrote then
		saved[c.id] = { region = region, mats = keepMats, occ = keepOcc }
		CraterService.dug += 1
	end
	return wrote
end

-- A heavy hit at `at` (dmg structure damage, radius its blast): a crater in the ground under it, if the ground is
-- close under it and the caps allow. Returns the crater or nil.
function CraterService.blast(at: Vector3, radius: number, dmg: number): CraterRules.Crater?
	if not G.on or dmg < G.minDmg then
		return nil
	end
	local t0 = os.clock()
	local kind, surface = groundAt(at)
	if not kind or not surface or at.Y - surface.Y > G.near + radius * 0.5 then
		return nil
	end
	local c = CraterRules.add(G, book, surface.X, surface.Y, surface.Z, dmg, kind, os.clock())
	if not c then
		return nil
	end
	if kind == "terrain" and not dig(c) then
		c.ground = "part" -- nothing to dig there after all: drawn like part ground
	end
	Net.fireAll("CraterAdd", wire(c))
	PerfMonitor.add("buildings", (os.clock() - t0) * 1000)
	return c
end

function CraterService.init()
	Net.on("CraterSync", function(player)
		local list = {}
		for _, c in book.list do
			table.insert(list, wire(c))
		end
		Net.fire("CraterState", player, list)
	end)
	PerfMonitor.watch("craters", function()
		return #book.list
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			local gone = CraterRules.step(G, book, os.clock())
			if #gone > 0 then
				local ids = {}
				for _, c in gone do
					table.insert(ids, c.id)
					local s = saved[c.id]
					if s then
						saved[c.id] = nil
						local terrain = Workspace.Terrain
						pcall(terrain.WriteVoxels, terrain, s.region, G.voxel, s.mats, s.occ)
					end
				end
				Net.fireAll("CraterGone", ids)
			end
		end
	end)
end

return CraterService
