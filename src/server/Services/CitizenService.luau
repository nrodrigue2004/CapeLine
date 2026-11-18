-- CitizenService: runs CitizenSim on the server (spec: Destruction "Max 60 server-owned citizens; they run
-- to the nearest shelter before any collapse and are never shown hurt"). 10 Hz steps; 4 Hz Citizen.Delta
-- packets to each player with the citizens within 250 studs. Danger comes from BuildingService (a building
-- near collapse, a collapse) and from big impacts and vehicle flips. Citizens cannot be damaged by anything.
-- Shelters are the Downtown and Old Town safehouses and the Beacon Tower door. Rescue incidents (M6) use the
-- same citizens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CitizenSim = require(Shared:WaitForChild("CitizenSim"))
local CitizenBuffer = require(Shared:WaitForChild("CitizenBuffer"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local BuildingService = require(script.Parent.BuildingService)
local PerfMonitor = require(script.Parent.PerfMonitor)

local CitizenService = {}

local C = Config.Destruction.citizens
CitizenService.sim = nil :: any

function CitizenService.danger(x: number, z: number, radius: number, seconds: number)
	if CitizenService.sim then
		CitizenSim.danger(CitizenService.sim, x, z, radius, seconds)
	end
end

function CitizenService.init()
	local world = CityBuilder.world
	local shelters = {}
	for _, s in world.safehouses do
		if s.district == "Downtown" or s.district == "OldTown" then
			table.insert(shelters, { x = s.x, z = s.z })
		end
	end
	local bt = world.downtown.beacon
	table.insert(shelters, { x = bt.x, z = bt.z + 30 })
	-- the sidewalk graph leaves out every corner and link inside a part (the Clock Tower in Clock Square)
	local sim = CitizenSim.new(Config, shelters, world.seed, CitizenSim.blocker(world, Config))
	CitizenService.sim = sim
	CitizenSim.populate(sim)
	BuildingService.Danger:Connect(CitizenService.danger)
	PerfMonitor.watch("citizens", function()
		return CitizenSim.visible(sim)
	end)
	task.spawn(function()
		local sendEvery = 1 / C.sendRate
		local sinceSend = 0
		local seq = 0
		while true do
			local dt = task.wait(C.step)
			local t0 = os.clock()
			CitizenSim.step(sim, dt, os.clock())
			sinceSend += dt
			if sinceSend >= sendEvery then
				sinceSend = 0
				seq += 1
				for _, player in Players:GetPlayers() do
					local hero = HeroService.get(player)
					local pos = hero and HeroService.position(hero)
					if pos then
						Net.fire(
							"CitizenDelta",
							player,
							CitizenBuffer.encodeFor(seq, sim.citizens, pos.X, pos.Z, C.relevance)
						)
					end
				end
			end
			PerfMonitor.add("citizens", (os.clock() - t0) * 1000)
		end
	end)
end

return CitizenService
