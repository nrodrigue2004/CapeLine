-- IdleWatch: measures the M11 gate (spec: "No idle wait over 5 seconds in a 30-minute session with 8
-- testers"; Wait table "no wait over 5 s with nothing to do"). Once a second it asks: does this hero have
-- something to do? Yes when an incident is live within 300 studs, a world boss is fighting, a contract is
-- open, the hero is in the opening, a mission or a fast-travel flight, Downed (crawl and ping), or a
-- screen is open. A stretch of nothing longer than 5 s is reported to the server (IdleReport) with what
-- was missing, so a playtest's Output lists every wait. The Dev panel shows this device's longest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local WorldClient = require(script.Parent.WorldClient)
local StoryClient = require(script.Parent.StoryClient)
local PvpClient = require(script.Parent.PvpClient)

local IdleWatch = {}

-- why there was nothing to do (sent with the report)
IdleWatch.REASONS = { "no incident near", "dead or respawning", "loading", "other" }
IdleWatch.longest = 0
IdleWatch.count = 0
IdleWatch.busyCheck = nil :: (() -> boolean)? -- the client sets this: is a screen or flight open?

local player = Players.LocalPlayer
local idleSince: number? = nil
local reason = 1
local LIMIT = 5

local function rootPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return nil
	end
	return root and root.Position
end

-- Is there something to do right now? Returns true, or false with a reason index
function IdleWatch.busy(): (boolean, number)
	if StoryClient.inOpening() or StoryClient.inMission() then
		return true, 0
	end
	if PvpClient.downed() then
		return true, 0 -- crawling and pinging
	end
	if IdleWatch.busyCheck and IdleWatch.busyCheck() then
		return true, 0
	end
	local pos = rootPos()
	if not pos then
		return false, 2
	end
	local b = WorldClient.boss
	if b.state == 2 or b.state == 3 then
		return true, 0
	end
	if #WorldClient.contracts > 0 then
		return true, 0
	end
	local r = Config.Incidents.spawner.radius
	for _, inc in WorldClient.incidents do
		if inc.state == WorldClient.ACTIVE and inc.pos and (inc.pos - pos).Magnitude <= r then
			return true, 0
		end
	end
	return false, 1
end

local function finish(now: number)
	if not idleSince then
		return
	end
	local len = now - idleSince
	idleSince = nil
	if len > LIMIT then
		IdleWatch.count += 1
		IdleWatch.longest = math.max(IdleWatch.longest, len)
		Net.send("IdleReport", math.min(600, math.floor(len + 0.5)), reason) -- whole seconds (the schema takes integers)
	end
end

function IdleWatch.init()
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("IdleWatch", function(dt)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		local now = os.clock()
		local ok, why = IdleWatch.busy()
		if ok then
			finish(now)
		elseif not idleSince then
			idleSince = now - 1
			reason = why
		end
	end))
end

return IdleWatch
