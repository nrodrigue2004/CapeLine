-- ClockService: the day and night cycle (spec: World.Clock; Map layout "day 16 min, dusk 3, night 4, dawn
-- 1"). The server only picks when the cycle started; every client works out the time of day from it
-- (WorldClock) and sets its own lighting, so nothing is sent but the start. Night makes villain incidents
-- and contracts a little likelier (IncidentService and ContractService read clockStart).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local IncidentService = require(script.Parent.IncidentService)

local ClockService = {}

local C = Config.World.clock

local function packet(): { [string]: number }
	return { start = IncidentService.clockStart, cycle = C.cycle }
end

-- Studio: jump to a phase start (0 day, 1 dusk, 2 night, 3 dawn)
function ClockService.jump(which: number)
	local offsets = { 0, C.day, C.day + C.dusk, C.day + C.dusk + C.night }
	local off = offsets[math.clamp(which, 0, 3) + 1]
	IncidentService.clockStart = os.time() - off
	Workspace:SetAttribute("ClockStart", IncidentService.clockStart)
	Net.fireAll("WorldClock", packet())
end

function ClockService.init()
	-- a new server starts a little into the morning
	IncidentService.clockStart = os.time() - math.floor(C.day * 0.1)
	Workspace:SetAttribute("ClockStart", IncidentService.clockStart)
	Workspace:SetAttribute("ClockCycle", C.cycle)
	Players.PlayerAdded:Connect(function(player)
		Net.fire("WorldClock", player, packet())
	end)
	task.spawn(function()
		while true do
			task.wait(C.sendEvery)
			Net.fireAll("WorldClock", packet())
		end
	end)
end

return ClockService
