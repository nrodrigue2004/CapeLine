--!strict
-- FrameProf: per-system script time for every per-frame loop, on the server and on each device.
-- FrameProf.wrap(name, fn) returns fn timed under that name; the label also shows in the MicroProfiler
-- (Ctrl+F6). FrameProf.report() lists the busiest systems, average and worst ms per frame since the last
-- report. The command bar has its own copy of every module, so to read it while playing, run this on the
-- Server command bar (it reaches every device):  workspace:SetAttribute("FrameProf", true)

local FrameProf = {}

local totals: { [string]: number } = {}
local worst: { [string]: number } = {}
local calls: { [string]: number } = {}
local frames = 0
local since = os.clock()

-- debug.profilebegin exists only inside Roblox (not in Lune tests)
local dbg = debug :: any
local profBegin: ((string) -> ())? = dbg.profilebegin
local profEnd: (() -> ())? = dbg.profileend

function FrameProf.add(name: string, ms: number)
	totals[name] = (totals[name] or 0) + ms
	calls[name] = (calls[name] or 0) + 1
	if ms > (worst[name] or 0) then
		worst[name] = ms
	end
end

-- Count frames so averages are per frame (inside Roblox only; Lune tests have no game)
local hasGame, runService = pcall(function()
	return (game :: any):GetService("RunService")
end)
if hasGame and runService then
	local workspace = (game :: any):GetService("Workspace")
	local nextLog = os.clock() + 10
	runService.Heartbeat:Connect(function()
		frames += 1
		-- Studio: set the Workspace attribute FrameProf to true (from the Server command bar, so it
		-- reaches every device) to print a report every 10 s on the server and each device
		if os.clock() >= nextLog then
			nextLog = os.clock() + 10
			if workspace:GetAttribute("FrameProf") == true then
				print(FrameProf.report())
			end
		end
	end)
end

-- Tests: count a frame by hand
function FrameProf.tick()
	frames += 1
end

-- the end of a timed call: one shared function, so a wrapped call makes no closure (perf pass 2026-11-18: it
-- made one every call, every frame, in every wrapped loop)
local function finish<R...>(name: string, t0: number, ...: R...): R...
	FrameProf.add(name, (os.clock() - t0) * 1000)
	if profEnd then
		profEnd()
	end
	return ...
end

function FrameProf.wrap<A..., R...>(name: string, fn: (A...) -> R...): (A...) -> R...
	return function(...: A...): R...
		if profBegin then
			profBegin(name)
		end
		return finish(name, os.clock(), fn(...))
	end
end

export type Row = { name: string, avg: number, worst: number, calls: number }

-- The busiest systems first; clears the window
function FrameProf.rows(): ({ Row }, number, number)
	local out: { Row } = {}
	local n = math.max(1, frames)
	for name, total in totals do
		table.insert(
			out,
			{ name = name, avg = total / n, worst = worst[name] or 0, calls = calls[name] or 0 }
		)
	end
	table.sort(out, function(a, b)
		return a.avg > b.avg
	end)
	local seconds = os.clock() - since
	local f = frames
	table.clear(totals)
	table.clear(worst)
	table.clear(calls)
	frames = 0
	since = os.clock()
	return out, f, seconds
end

function FrameProf.report(): string
	local rows, f, seconds = FrameProf.rows()
	local sum = 0
	for _, r in rows do
		sum += r.avg
	end
	local lines = {
		string.format(
			"[FrameProf] %d frames in %.1f s (%.0f fps), scripts %.2f ms a frame",
			f,
			seconds,
			f / math.max(0.001, seconds),
			sum
		),
	}
	for _, r in rows do
		table.insert(
			lines,
			string.format("  %-22s avg %6.3f ms  worst %6.2f ms  calls %d", r.name, r.avg, r.worst, r.calls)
		)
	end
	return table.concat(lines, "\n")
end

return FrameProf
