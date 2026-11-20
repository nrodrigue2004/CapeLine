-- Telemetry: the analytics facts only the device knows (spec: Analytics and KPIs), sent to the server on
-- the Telemetry remote, which checks and logs them through AnalyticsService. Nothing here is a name or text.
-- * hello: once, the device class (phone, tablet, pc or console) for session_start.
-- * perf_sample: 10% of devices (Config.Analytics.perfSample) send the minute's median fps, its 5th
--   percentile, the device class and the quality preset every 60 s.
-- * note("shop") / note("item") / note("photo", backdrop): the Purchase funnel's first two steps and photos.
-- * client errors (Everything Left 480): every script error on this device (ScriptContext.Error) is counted and
--   sent at most once a minute: the count and the first errored script's name as a number (no text travels).

local GuiService = game:GetService("GuiService")
local ScriptContext = game:GetService("ScriptContext")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local AnalyticsSchema = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnalyticsSchema"))

local QualityController = require(script.Parent.QualityController)

local Telemetry = {}

Telemetry.sampled = false -- this device sends perf samples (Dev panel)
Telemetry.lastMedian = 0
Telemetry.lastP5 = 0

local KIND = { perf = 1, shop = 2, item = 3, photo = 4, hello = 5, errors = 6 }
local lastItem = 0

-- 1 phone, 2 tablet, 3 pc, 4 console
function Telemetry.device(): number
	if GuiService:IsTenFootInterface() then
		return 4
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local cam = Workspace.CurrentCamera
		local size = cam and cam.ViewportSize or Vector2.new(800, 400)
		return if math.min(size.X, size.Y) >= 700 then 2 else 1
	end
	return 3
end

-- Median and 5th-percentile (the slow end) fps of a list of frame times
function Telemetry.summarize(frames: { number }): (number, number)
	if #frames == 0 then
		return 0, 0
	end
	local fps = table.create(#frames)
	for i, dt in frames do
		fps[i] = 1 / math.max(dt, 1 / 1000)
	end
	table.sort(fps)
	local median = fps[math.max(1, math.ceil(#fps / 2))]
	local p5 = fps[math.max(1, math.ceil(#fps * 0.05))]
	return math.floor(math.min(median, 999) + 0.5), math.floor(math.min(p5, 999) + 0.5)
end

function Telemetry.note(what: string, a: number?)
	local kind = KIND[what]
	if not kind then
		return
	end
	if kind == KIND.item then
		-- one view per second at most: tapping through cards should not flood the remote
		local now = os.clock()
		if now - lastItem < 1 then
			return
		end
		lastItem = now
	end
	Net.send("Telemetry", kind, 0, a or 0, 0)
end

-- Client errors waiting to be reported: the count since the last report and the first script's hash
Telemetry.errors = 0
Telemetry.errorModule = 0
local errorSentAt = -math.huge

function Telemetry.flushErrors(now: number)
	if Telemetry.errors <= 0 or now - errorSentAt < Config.Analytics.errorEvery then
		return
	end
	errorSentAt = now
	Net.send(
		"Telemetry",
		KIND.errors,
		math.min(Telemetry.errors, 1000),
		Telemetry.errorModule,
		Telemetry.device()
	)
	Telemetry.errors, Telemetry.errorModule = 0, 0
end

function Telemetry.onError(_message: string, _trace: string, origin: Instance?)
	Telemetry.errors += 1
	if Telemetry.errorModule == 0 then
		Telemetry.errorModule = if origin then AnalyticsSchema.nameHash(origin.Name) else 0
	end
	Telemetry.flushErrors(os.clock())
end

function Telemetry.init()
	local A = Config.Analytics
	Net.send("Telemetry", KIND.hello, 0, Telemetry.device(), 0)
	ScriptContext.Error:Connect(Telemetry.onError)
	task.spawn(function()
		while true do
			task.wait(A.errorEvery)
			Telemetry.flushErrors(os.clock())
		end
	end)
	Telemetry.sampled = math.random() < A.perfSample or RunService:IsStudio()
	if not Telemetry.sampled then
		return
	end
	local frames: { number } = {}
	local started = os.clock()
	RunService.Heartbeat:Connect(FrameProf.wrap("Telemetry", function(dt)
		table.insert(frames, dt)
		if os.clock() - started < A.perfEvery then
			return
		end
		started = os.clock()
		local median, p5 = Telemetry.summarize(frames)
		table.clear(frames)
		Telemetry.lastMedian, Telemetry.lastP5 = median, p5
		local preset = if QualityController.fixed
			then (table.find(Config.Presets.order, QualityController.name) or 0)
			else 0
		Net.send("Telemetry", KIND.perf, p5 * 1000 + median, Telemetry.device(), preset)
	end))
end

return Telemetry
