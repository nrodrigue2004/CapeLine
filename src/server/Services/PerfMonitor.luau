-- PerfMonitor: server frame and per-service script time (spec: Performance budgets: server frame 16 ms,
-- scripts 8 ms: enemies 2.5, combat 1.5, replication 1.5). Services call PerfMonitor.add(name, ms); once a
-- second the averages go to Studio clients (Dev panel) and, while load bots run, to the output log.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local PerfMonitor = {}

local totals: { [string]: number } = {}
local worst: { [string]: number } = {}
local frames = 0
local frameTotal = 0
local frameWorst = 0
local extra: { [string]: () -> any } = {}
PerfMonitor.logToOutput = false

function PerfMonitor.add(name: string, ms: number)
	totals[name] = (totals[name] or 0) + ms
	worst[name] = math.max(worst[name] or 0, ms)
end

-- Time a function under a name
function PerfMonitor.time<T...>(name: string, fn: (T...) -> (), ...: T...)
	local t0 = os.clock()
	fn(...)
	PerfMonitor.add(name, (os.clock() - t0) * 1000)
end

-- Extra live numbers for the report (enemy count, bots)
function PerfMonitor.watch(name: string, fn: () -> any)
	extra[name] = fn
end

local function report()
	local out = {
		frameMs = if frames > 0 then frameTotal / frames else 0,
		frameWorstMs = frameWorst,
		players = #Players:GetPlayers(),
		sendKbps = Stats.DataSendKbps,
		memoryMb = Stats:GetTotalMemoryUsageMb(),
		services = {},
		extra = {},
	}
	for name, total in totals do
		out.services[name] = { avg = total / math.max(1, frames), worst = worst[name] }
	end
	for name, fn in extra do
		local ok, value = pcall(fn)
		out.extra[name] = if ok then value else "?"
	end
	table.clear(totals)
	table.clear(worst)
	frames, frameTotal, frameWorst = 0, 0, 0
	return out
end

function PerfMonitor.init()
	RunService.Heartbeat:Connect(function(dt)
		frames += 1
		frameTotal += dt * 1000
		frameWorst = math.max(frameWorst, dt * 1000)
	end)
	task.spawn(function()
		local logCount = 0
		while true do
			task.wait(Config.Dev.stats.every)
			local r = report()
			if RunService:IsStudio() then
				Net.fireAll("DevStats", r)
			end
			logCount += 1
			if PerfMonitor.logToOutput and logCount % 5 == 0 then
				local parts = {}
				for name, s in r.services do
					table.insert(parts, string.format("%s %.2f/%.2f", name, s.avg, s.worst))
				end
				table.sort(parts)
				print(
					string.format(
						"[Perf] frame %.1f ms (worst %.1f), send %.0f kbps, mem %.0f MB | %s",
						r.frameMs,
						r.frameWorstMs,
						r.sendKbps,
						r.memoryMb,
						table.concat(parts, ", ")
					)
				)
			end
		end
	end)
end

return PerfMonitor
