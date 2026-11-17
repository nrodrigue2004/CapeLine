-- TaskForceService: the Task Force board and quick join (spec: Hero MMO features > Task forces; H4).
-- Squads looking for members are lobbies: a leader opens one for their side's task force, others join from
-- the board or press Looking (the fullest open squad of their side they may join, Shared.TaskForcePlan),
-- a leader can lock it to friends, and Start takes everyone in the lobby into the run (MissionService runs
-- the legs). A member who leaves a run can rejoin it within 3 minutes from the board. The final pay: a mission
-- reward at your own level per leg (MissionService), then a guaranteed Epic roll at your level and, on the
-- first clear each week, double Renown (saved per character: mmo.tfWeek).
-- The board opens from the menu (TASK FORCE) and at every safehouse (the board screen, TaskForceHud).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local TaskForcePlan = require(Shared:WaitForChild("TaskForcePlan"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local HeroService = require(script.Parent.HeroService)
local MissionService = require(script.Parent.MissionService)
local StoryService = require(script.Parent.StoryService)
local Analytics = require(script.Parent.Analytics)

local TaskForceService = {}

local TF = Config.TaskForce
local ACT = { open = 1, join = 2, leave = 3, start = 4, lock = 5, rejoin = 6 }
TaskForceService.ACT = ACT
TaskForceService.Done = Signal.new() -- (player, tf index, seconds, party) a task force finished (badges, H7)

local lobbies: { [number]: TaskForcePlan.Lobby } = {}
local nextId = 1
local friends: { [string]: boolean } = {} -- "a:b" -> friends (IsFriendsWith yields: asked once, cached)

local function act1Done(player: Player): boolean
	local story = StoryService.story(player)
	return story ~= nil and StoryPlan.cleared(story, #Config.Story.missions)
end

local function isFriend(player: Player, other: number): boolean
	if player.UserId == other then
		return true
	end
	local key = math.min(player.UserId, other) .. ":" .. math.max(player.UserId, other)
	if friends[key] == nil then
		local ok, yes = pcall(player.IsFriendsWith, player, other)
		friends[key] = ok and yes == true
	end
	return friends[key]
end

local function lobbyOf(player: Player): TaskForcePlan.Lobby?
	for _, l in lobbies do
		if table.find(l.members, player.UserId) then
			return l
		end
	end
	return nil
end

local function playersOf(l: TaskForcePlan.Lobby): { Player }
	local out = {}
	for _, uid in l.members do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- The board for one player: every open squad (leader name, task force, size, locked, can you join), which
-- task forces you may start, your own squad, and a run you may rejoin
local function boardFor(player: Player): { [string]: any }
	local hero = HeroService.get(player)
	local level = hero and hero.level or 1
	local side = StoryService.side(player)
	local done = act1Done(player)
	local list = {}
	for _, l in lobbies do
		if not l.running then
			local leader = Players:GetPlayerByUserId(l.members[1])
			table.insert(list, {
				id = l.id,
				tf = l.tf,
				n = #l.members,
				leader = leader and leader.DisplayName or "",
				locked = l.locked,
				can = TaskForcePlan.canJoin(TF, l, level, side, done)
					and (not l.locked or isFriend(player, l.members[1])),
			})
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	local starts = {}
	for i in TF.list do
		starts[i] = (TaskForcePlan.canStart(TF, i, level, side, done))
	end
	local mine = lobbyOf(player)
	return {
		lobbies = list,
		starts = starts,
		mine = mine and {
			id = mine.id,
			tf = mine.tf,
			n = #mine.members,
			leader = mine.members[1] == player.UserId,
			locked = mine.locked,
		},
		rejoin = TaskForceService.canRejoin and TaskForceService.canRejoin(player) or false,
	}
end

local function sendBoard(player: Player, open: boolean?)
	local b = boardFor(player)
	b.open = open
	Net.fire("TaskForceBoard", player, b)
end

local function sendLobby(l: TaskForcePlan.Lobby)
	for _, p in playersOf(l) do
		sendBoard(p)
	end
end

local function leaveLobby(player: Player)
	local l = lobbyOf(player)
	if not l then
		return
	end
	table.remove(l.members, table.find(l.members, player.UserId) :: number)
	if #l.members == 0 or l.running then
		if #l.members == 0 then
			lobbies[l.id] = nil
		end
	else
		sendLobby(l)
	end
end

local function open(player: Player, tf: number)
	local hero = HeroService.get(player)
	if not hero or lobbyOf(player) or MissionService.runOf(player) then
		return
	end
	local ok = TaskForcePlan.canStart(TF, tf, hero.level, StoryService.side(player), act1Done(player))
	if not ok then
		Net.fire("Toast", player, { id = "taskForce", ok = false, reason = "level" })
		return
	end
	local l: TaskForcePlan.Lobby = {
		id = nextId,
		tf = tf,
		side = StoryService.side(player),
		members = { player.UserId },
		locked = false,
		running = false,
	}
	nextId += 1
	lobbies[l.id] = l
	Analytics.event(player, "taskforce_open", 1, { tf })
end

local function join(player: Player, maybe: TaskForcePlan.Lobby?)
	local hero = HeroService.get(player)
	if not maybe or not hero or maybe.running or lobbyOf(player) or MissionService.runOf(player) then
		return
	end
	local l = maybe :: TaskForcePlan.Lobby
	local side = StoryService.side(player)
	if not TaskForcePlan.canJoin(TF, l, hero.level, side, act1Done(player)) then
		return
	end
	if l.locked and not isFriend(player, l.members[1]) then
		return
	end
	table.insert(l.members, player.UserId)
	sendLobby(l)
end

local function start(player: Player)
	local l = lobbyOf(player)
	if not l or l.members[1] ~= player.UserId or l.running then
		return
	end
	local ok, why = MissionService.enterTaskForce(playersOf(l), l.tf)
	if not ok then
		Net.fire("Toast", player, { id = "missionRefused", reason = why })
		return
	end
	l.running = true
	for _, p in playersOf(l) do
		Analytics.event(p, "taskforce_start", 1, { l.tf, #l.members })
	end
	-- the lobby closes once the run is under way (the run keeps its own members and rejoin list)
	lobbies[l.id] = nil
end

-- The last leg's pay (MissionService.payTaskForce): the Epic roll at your level and the weekly double
-- Renown. Also the leg pay for every other leg (out already holds Credits and Renown at your level).
local function payTaskForce(run: any, player: Player, out: { [string]: any }, own: number): { [string]: any }
	out.tf, out.leg, out.legs = run.tf, run.leg, run.m.legs
	if run.leg < run.m.legs then
		return out
	end
	local char = StoryService.char(player)
	local week = TaskForcePlan.week(os.time())
	if char and char.mmo then
		local last = char.mmo.tfWeek[run.tf] or 0
		local mult = TaskForcePlan.weeklyMult(TF, last, week)
		if mult > 1 and (out.renown or 0) > 0 then
			local extra = math.floor(out.renown * (mult - 1) + 0.5)
			EconomyService.addRenown(player, extra)
			out.renown += extra
			out.weekly = true
		end
		char.mmo.tfWeek[run.tf] = week
	end
	GearService.grantPiece(player, TF.epicTier, own)
	out.epic = true
	out.first = false
	DataService.saveSoon(player)
	Analytics.event(
		player,
		"taskforce_done",
		math.floor(os.clock() - run.startedAt),
		{ run.tf, #run.members }
	)
	TaskForceService.Done:Fire(player, run.tf, os.clock() - run.startedAt, #run.members)
	return out
end

function TaskForceService.canRejoin(player: Player): boolean
	return MissionService.canRejoin(player)
end

function TaskForceService.init()
	MissionService.payTaskForce = payTaskForce
	Net.on("TaskForceList", function(player: Player)
		sendBoard(player)
	end)
	Net.on("TaskForceJoin", function(player: Player, action: number, arg: number)
		if action == ACT.open then
			open(player, arg)
		elseif action == ACT.join then
			join(player, lobbies[arg])
		elseif action == ACT.leave then
			leaveLobby(player)
		elseif action == ACT.start then
			start(player)
		elseif action == ACT.lock then
			local l = lobbyOf(player)
			if l and l.members[1] == player.UserId then
				l.locked = not l.locked
				sendLobby(l)
			end
		elseif action == ACT.rejoin then
			MissionService.rejoin(player)
		end
		sendBoard(player)
	end)
	Net.on("TaskForceLook", function(player: Player, on: boolean)
		local hero = HeroService.get(player)
		if not on or not hero or lobbyOf(player) then
			sendBoard(player)
			return
		end
		local list = {}
		for _, l in lobbies do
			table.insert(list, l)
		end
		local l = TaskForcePlan.match(
			TF,
			list,
			hero.level,
			StoryService.side(player),
			act1Done(player),
			function(uid)
				return isFriend(player, uid)
			end
		)
		if l then
			join(player, l)
		else
			Net.fire("Toast", player, { id = "taskForce", ok = false, reason = "none" })
		end
		sendBoard(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		leaveLobby(player)
	end)
	-- the board at every safehouse: a second prompt on the Contract Board terminal (K; B is the contracts)
	for _, part in (CityBuilder.folder :: Folder):GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("Tag") == "contracts" then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "TaskForceBoard"
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = Config.World.safehouse.terminalRange
			prompt.KeyboardKeyCode = Enum.KeyCode.K
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonL3
			prompt.ActionText = "Task Force Board"
			prompt.ObjectText = "Safehouse"
			prompt.UIOffset = Vector2.new(0, 64) -- below the Contract Board's prompt
			prompt.HoldDuration = 0
			prompt.Triggered:Connect(function(player: Player)
				sendBoard(player, true)
			end)
			prompt.Parent = part
		end
	end
end

return TaskForceService
