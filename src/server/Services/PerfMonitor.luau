-- PerfMonitor: server frame and per-service script time (spec: Performance budgets: server frame 16 ms,
-- scripts 8 ms: enemies 2.5, combat 1.5, replication 1.5). Services call PerfMonitor.add(name, ms); once a
-- second the averages go to Studio clients (Dev panel) and, while load bots run, to the output log.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Analytics = require(script.Parent.Analytics)

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

-- M11 gate (spec: "No idle wait over 5 seconds in a 30-minute session"): each device reports its waits
-- of over 5 s with nothing to do (IdleWatch); the Output lists every one and the Dev panel the count
local REASONS = { "no incident near", "dead or respawning", "loading", "other" }
local IDLE_CODES = { "no_incident", "respawning", "loading", "other" } -- analytics field codes
local idleWaits, idleLongest = 0, 0
PerfMonitor.watch("idle>5s", function()
	return string.format("%d (longest %.1f s)", idleWaits, idleLongest)
end)
-- M12 soak: server script errors this session (the playtest gate is no crash reports in a week); the
-- Creator Dashboard's Error report has the client side
local scriptErrors = 0
PerfMonitor.watch("errors", function()
	return scriptErrors
end)
PerfMonitor.watch("analytics", function()
	return string.format("%d sent, %d over budget", Analytics.count, Analytics.dropped) -- M12
end)

function PerfMonitor.init()
	game:GetService("ScriptContext").Error:Connect(function()
		scriptErrors += 1
	end)
	Net.on("IdleReport", function(player, seconds: number, why: number)
		idleWaits += 1
		idleLongest = math.max(idleLongest, seconds)
		Analytics.event(player, "idle_wait", seconds, { IDLE_CODES[why] or "other" })
		print(
			string.format(
				"[Capeline] idle wait %.1f s for %s (%s)",
				seconds,
				player.Name,
				REASONS[why] or "?"
			)
		)
	end)
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
