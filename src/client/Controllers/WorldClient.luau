-- WorldClient: the client's view of the city's activity (spec: Incident.Spawn/Update, Contract.Update,
-- Event.State, Boss.State/Contribution/Result, World.Clock). Screens and effects read these tables and
-- listen to Changed; nothing here is trusted by the server.
-- * incidents: id -> the spawn packet plus its latest update (deadline in local clock seconds)
-- * contracts: the hero's accepted contracts { num, got, goal, dist, dx, dz }
-- * events: num -> { num, x, z, ends, have, need, state }
-- * boss: the latest Boss.State, plus `mine` (Boss.Contribution)
-- * The day and night: Lighting follows WorldClock from the server's cycle start (Workspace attribute
--   ClockStart, refreshed by World.Clock), eased so a jump never snaps.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local WorldClock = require(Shared:WaitForChild("WorldClock"))

local WorldClient = {}

WorldClient.Changed = Signal.new() -- (what) "incidents", "contracts", "events", "boss", "contribution"
WorldClient.BossAttack = Signal.new() -- (event) telegraphs, strikes, phases, landing, defeat, retreat
WorldClient.BossResult = Signal.new() -- (result)
WorldClient.Board = Signal.new() -- (board) the Contract Board opened or changed
WorldClient.IncidentEnded = Signal.new() -- (incident) cleared, failed or gone

WorldClient.incidents = {} :: { [number]: { [string]: any } }
WorldClient.contracts = {} :: { { number } }
WorldClient.events = {} :: { [number]: { [string]: any } }
WorldClient.boss = { state = 0 } :: { [string]: any }
WorldClient.mine = { score = 0, tier = "", rank = 0, heroes = 0 }
WorldClient.clockStart = 0
WorldClient.cycle = Config.World.clock.cycle

local IC = Config.Incidents
local templateByNum: { [number]: string } = {}
for id, t in IC.templates do
	templateByNum[t.num] = id
end
local contractByNum: { [number]: string } = {}
for id, t in Config.Contracts.types do
	contractByNum[t.num] = id
end
local eventByNum: { [number]: string } = {}
for id, t in Config.Events.events do
	eventByNum[t.num] = id
end
local bossByNum: { [number]: string } = {}
for id, b in Config.Boss.bosses do
	bossByNum[b.num] = id
end
WorldClient.templateByNum = templateByNum
WorldClient.contractByNum = contractByNum
WorldClient.eventByNum = eventByNum
WorldClient.bossByNum = bossByNum

-- Incident states on the wire
WorldClient.ACTIVE = 0
WorldClient.DONE = 1
WorldClient.FAILED = 2
WorldClient.GONE = 3
WorldClient.MEDALS = { "gold", "silver", "bronze" }

function WorldClient.now(): number
	return Workspace:GetServerTimeNow()
end

-- Seconds into the day and night cycle
function WorldClient.clockT(): number
	return WorldClient.now() - WorldClient.clockStart
end

function WorldClient.isNight(): boolean
	return WorldClock.isNight(Config.World.clock, WorldClient.clockT())
end

local function onSpawn(p: { [string]: any })
	local now = os.clock()
	WorldClient.incidents[p.id] = {
		id = p.id,
		num = p.num,
		tid = templateByNum[p.num],
		pos = Vector3.new(p.x, p.y, p.z),
		side = if p.side == 2 then "villain" else "hero",
		level = p.level,
		deadline = now + p.left,
		own = p.own == 1,
		steps = p.steps,
		kind = p.kind,
		frac = 0,
		step = 1,
		have = 0,
		need = 1,
		state = WorldClient.ACTIVE,
		medal = 0,
	}
	WorldClient.Changed:Fire("incidents")
end

local function onUpdate(rows: { { number } })
	local now = os.clock()
	for _, r in rows do
		local inc = WorldClient.incidents[r[1]]
		if inc then
			inc.frac = r[2] / 1000
			inc.step = r[3]
			inc.have = r[4]
			inc.need = r[5]
			inc.deadline = now + r[6]
			local was = inc.state
			inc.state = r[7]
			inc.medal = r[8]
			if r[7] ~= WorldClient.ACTIVE and was == WorldClient.ACTIVE then
				WorldClient.IncidentEnded:Fire(inc)
			end
			if r[7] == WorldClient.GONE then
				WorldClient.incidents[r[1]] = nil
			end
		end
	end
	WorldClient.Changed:Fire("incidents")
end

local function onEvents(data: { [string]: any })
	local now = os.clock()
	local seen = {}
	for _, r in data.list or {} do
		local num = r[1]
		seen[num] = true
		local ev = WorldClient.events[num]
		if not ev then
			ev = { num = num, id = eventByNum[num], started = now }
			WorldClient.events[num] = ev
		end
		ev.x, ev.z = r[2], r[3]
		ev.ends = now + r[4]
		ev.have, ev.need, ev.state = r[5], r[6], r[7]
	end
	for num in WorldClient.events do
		if not seen[num] then
			WorldClient.events[num] = nil
		end
	end
	WorldClient.Changed:Fire("events")
end

-- Lighting: ClockTime from the cycle, a cool ambient at night so the city stays readable
local nightAmbient = Color3.fromRGB(70, 80, 120)
local dayAmbient = Lighting.OutdoorAmbient
-- A story scene can hold the sky at one time (the opening's dusk); nil follows the world clock
WorldClient.clockOverride = nil :: number?
local function lightStep()
	if WorldClient.clockStart == 0 and not WorldClient.clockOverride then
		return
	end
	local cfg = Config.World.clock
	local want = WorldClient.clockOverride or WorldClock.clockTime(cfg, WorldClient.clockT())
	local cur = Lighting.ClockTime
	local d = (want - cur + 12) % 24 - 12
	-- ease toward the target (a Dev clock jump glides over a couple of seconds)
	Lighting.ClockTime = (cur + d * (if math.abs(d) > 0.5 then 0.08 else 1)) % 24
	local night = WorldClock.isNight(cfg, WorldClient.clockT())
	local goal = if night then nightAmbient else dayAmbient
	Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(goal, 0.02)
end

function WorldClient.init()
	Net.listen("IncidentSpawn", onSpawn)
	Net.listen("IncidentUpdate", onUpdate)
	Net.listen("ContractUpdate", function(data)
		WorldClient.contracts = data.list or {}
		WorldClient.Changed:Fire("contracts", data)
	end)
	Net.listen("ContractBoard", function(board)
		WorldClient.Board:Fire(board)
	end)
	Net.listen("EventState", onEvents)
	Net.listen("BossState", function(s)
		local prev = WorldClient.boss.state
		s.received = os.clock()
		s.id = s.num and bossByNum[s.num]
		WorldClient.boss = s
		if s.state ~= 3 and prev == 3 then
			WorldClient.mine = { score = 0, tier = "", rank = 0, heroes = 0 }
		end
		WorldClient.Changed:Fire("boss")
	end)
	Net.listen("BossContribution", function(c)
		WorldClient.mine = c
		WorldClient.Changed:Fire("contribution")
	end)
	Net.listen("BossAttack", function(ev)
		WorldClient.BossAttack:Fire(ev)
	end)
	Net.listen("BossResult", function(r)
		WorldClient.BossResult:Fire(r)
	end)
	Net.listen("WorldClock", function(c)
		WorldClient.clockStart = c.start
		WorldClient.cycle = c.cycle
	end)
	local start = Workspace:GetAttribute("ClockStart")
	if type(start) == "number" then
		WorldClient.clockStart = start
	end
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("WorldClient", function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			lightStep()
		end
	end))
end

return WorldClient
