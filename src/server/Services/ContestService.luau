-- ContestService: costume contests (spec: Hero MMO features > Costume contests; H7). Every 30 minutes on the
-- clock (Shared.ContestRules, Config.Contest) a contest runs on the stage at a corner of the hub plaza:
-- * call (60 s): a banner and a beam over the stage; up to 8 players step on (ContestEnter near the stage
--   puts them on a pad);
-- * show: 10 s in the spotlight each (they pose with any emote they own);
-- * vote: everyone else rates each contestant 1 to 5 stars (ContestVote), from anywhere on the server; only
--   players here 2 minutes or more count, squadmates count half, nobody rates themselves;
-- * results: the top 3 on the podium with confetti; pay by place, a Contest Ribbon, the badges' counters.
-- Fewer than 3 contestants or 5 voters skips it with a small pay for those who stepped on. A player wins at
-- most once an hour. Nothing here changes stats.
-- PLACEHOLDER ART: the stage, pads, podium, beam and spotlight are simple parts until the Blender pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollectPlan = require(Shared:WaitForChild("CollectPlan"))
local ContestRules = require(Shared:WaitForChild("ContestRules"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Analytics = require(script.Parent.Analytics)
local BeaconService = require(script.Parent.BeaconService)
local BadgeService = require(script.Parent.BadgeService)
local CityBuilder = require(script.Parent.CityBuilder)
local CollectService = require(script.Parent.CollectService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local HeroService = require(script.Parent.HeroService)
local SafehouseService = require(script.Parent.SafehouseService)
local SquadService = require(script.Parent.SquadService)

local ContestService = {}
ContestService.Entered = Signal.new() -- (player) stepped on the stage (Hero Pass XP, the episode; H8)
ContestService.Placed = Signal.new() -- (player, place) a contest result (Hero Pass XP; H8)

local K = Config.Contest
local joinedAt: { [Player]: number } = {}
local lastWin: { [number]: number } = {} -- user id -> os.time of their last win (also saved)

type State = {
	cycle: number,
	theme: string,
	entries: { number }, -- user ids in pad order
	votes: { [number]: { [number]: number } }, -- voter -> target -> stars
	phase: string,
	shown: number,
	done: boolean,
	skipped: boolean,
	top: { number },
}
local state: State? = nil
local stageAt: Vector3? = nil
local model: Model? = nil
local beam: BasePart? = nil

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- The stage at the plaza corner: a platform, 8 pads, the 3-step podium, the call beam
local function build()
	local world = CityBuilder.world
	local bt = world and world.downtown and world.downtown.beacon
	if not bt or model then
		return
	end
	local sx, sz = ContestRules.stage(K, bt.x, bt.z)
	local gy = CityBuilder.heightAt(sx, sz)
	local st = K.stage
	model = Instance.new("Model")
	local m = model :: Model
	m.Name = "ContestStage"
	part(
		Vector3.new(st.size, st.height, st.size),
		CFrame.new(sx, gy + st.height / 2, sz),
		Color3.fromRGB(70, 60, 110)
	)
	local top = gy + st.height
	for i = 1, K.maxEntries do
		local ox, oz = ContestRules.pad(K, i)
		local pad = part(
			Vector3.new(4, 0.4, 4),
			CFrame.new(sx + ox, top + 0.2, sz + oz),
			Color3.fromRGB(255, 210, 90),
			Enum.Material.Neon
		)
		pad.Name = "Pad" .. i
	end
	for i, h in st.podium do
		local ox = (({ 0, -5, 5 }) :: { number })[i]
		part(
			Vector3.new(4.5, h, 4.5),
			CFrame.new(sx + ox, top + h / 2, sz + st.size / 2 - 4),
			({ Color3.fromRGB(255, 205, 60), Color3.fromRGB(200, 205, 215), Color3.fromRGB(205, 130, 70) })[i]
		)
	end
	local b = part(
		Vector3.new(3, 400, 3),
		CFrame.new(sx, top + 200, sz),
		Color3.fromRGB(255, 120, 220),
		Enum.Material.Neon
	)
	b.CanCollide = false
	b.CanQuery = false
	b.Transparency = 1
	beam = b
	m.Parent = Workspace
	stageAt = Vector3.new(sx, top, sz)
end

local function padCFrame(i: number): CFrame
	local at = stageAt :: Vector3
	local ox, oz = ContestRules.pad(K, i)
	return CFrame.new(at + Vector3.new(ox, 3, oz))
end

local function podiumCFrame(place: number): CFrame
	local at = stageAt :: Vector3
	local ox = ({ 0, -5, 5 })[place]
	return CFrame.new(at + Vector3.new(ox, K.stage.podium[place] + 3, K.stage.size / 2 - 4))
end

local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if not p then
		return "Hero"
	end
	local h = p:GetAttribute("HeroName")
	return if typeof(h) == "string" and h ~= "" then h else p.DisplayName
end

local function packet(s: State, now: number): { [string]: any }
	local phase, a, endsAt = ContestRules.phase(K, now, #s.entries)
	local list = {}
	for _, u in s.entries do
		table.insert(list, { id = u, name = nameOf(u) })
	end
	return {
		-- (pt-ui 2026-11-19) a skipped contest reads "skipped" until its cycle is over, then idle like any other
		phase = if s.skipped and phase ~= "idle" then "skipped" else phase,
		theme = s.theme,
		entries = list,
		spot = if phase == "show" then s.entries[a] else nil,
		endsAt = endsAt,
		now = now,
		stage = stageAt and { stageAt.X, stageAt.Y, stageAt.Z },
		top = s.top,
		max = K.maxEntries,
	}
end

local function broadcast(s: State)
	local p = packet(s, os.time())
	for _, player in Players:GetPlayers() do
		Net.fire("ContestState", player, p)
	end
end

local function isMate(a: Player?, b: Player?): boolean
	return a ~= nil and b ~= nil and table.find(SquadService.mates(a), b) ~= nil
end

local function enter(player: Player)
	local s = state
	local hero = HeroService.get(player)
	local p = hero and HeroService.position(hero)
	if not s or s.phase ~= "call" or not hero or not p or not stageAt or hero.scene then
		return
	end
	local ok = ContestRules.canEnter(K, s.entries, player.UserId, (p - stageAt).Magnitude)
	if not ok then
		Net.fire("ContestState", player, packet(s, os.time()))
		return
	end
	table.insert(s.entries, player.UserId)
	local i = #s.entries
	SafehouseService.place(hero, padCFrame(i))
	BadgeService.bump(player, "contestEntries")
	ContestService.Entered:Fire(player)
	CollectService.give(player, CollectPlan.ribbon(Config.Collect, "enter"))
	Analytics.event(player, "contest_enter", 1, { s.theme })
	broadcast(s)
end

-- GO TO THE STAGE (fix-flow, 2026-11-19): in range it is ENTER; away, the hero fast travels to the stage's
-- front (the beacon flight's rules and cooldown) and steps on when it lands, while the call is still open
local function go(player: Player)
	local s = state
	local hero = HeroService.get(player)
	local p = hero and HeroService.position(hero)
	if not s or not hero or not p or not stageAt then
		return
	end
	local phase = ContestRules.phase(K, os.time(), #s.entries)
	local how, why =
		ContestRules.goPlan(K, phase, s.entries, player.UserId, (p - (stageAt :: Vector3)).Magnitude)
	if how == "enter" then
		enter(player)
		Net.fire("ContestGoResult", player, { ok = true, how = "enter" })
		return
	elseif how ~= "travel" then
		Net.fire("ContestGoResult", player, { ok = false, reason = why })
		return
	end
	local at = (stageAt :: Vector3) + Vector3.new(0, 3, -(K.stage.size / 2 + 4))
	local ok, reason, wait = BeaconService.travelTo(
		player,
		CFrame.lookAt(at, stageAt :: Vector3),
		function(landed)
			if landed then
				enter(player)
			end
		end
	)
	Net.fire("ContestGoResult", player, { ok = ok, how = "travel", reason = reason, wait = wait })
end

local function vote(player: Player, target: number, stars: number)
	local s = state
	if not s or (s.phase ~= "show" and s.phase ~= "vote") then
		return
	end
	local isEntry = table.find(s.entries, player.UserId) ~= nil
	if not ContestRules.canVote(K, joinedAt[player] or os.time(), os.time(), isEntry) then
		Net.fire("Toast", player, { id = "contestWait" })
		return
	end
	if not table.find(s.entries, target) or stars < 1 or stars > 5 then
		return
	end
	local mine = s.votes[player.UserId] or {}
	local first = next(mine) == nil
	mine[target] = math.floor(stars)
	s.votes[player.UserId] = mine
	if first then
		BadgeService.bump(player, "contestVotes")
		local profile = DataService.get(player)
		local counts = profile and profile.mmo.counts
		if counts and (counts.contestVotes or 0) >= Config.Collect.ribbonVotes then
			CollectService.give(player, CollectPlan.ribbon(Config.Collect, "votes"))
		end
	end
end

local function results(s: State)
	local now = os.time()
	local score: { [number]: number } = {}
	local voters = 0
	for voter, list in s.votes do
		voters += 1
		local vp = Players:GetPlayerByUserId(voter)
		for target, stars in list do
			local tp = Players:GetPlayerByUserId(target)
			score[target] = (score[target] or 0)
				+ ContestRules.weight(K, voter, target, stars, isMate(vp, tp))
		end
	end
	local entries = {}
	for _, u in s.entries do
		if Players:GetPlayerByUserId(u) then
			table.insert(entries, u)
		end
	end
	if not ContestRules.enough(K, #entries, voters) then
		s.skipped = true
		for _, u in entries do
			local p = Players:GetPlayerByUserId(u)
			if p then
				EconomyService.addCredits(p, ContestRules.pay(K, nil, true))
				Net.fire("Toast", p, { id = "contestSkipped", credits = ContestRules.pay(K, nil, true) })
			end
		end
		return
	end
	for _, u in entries do
		local p = Players:GetPlayerByUserId(u)
		local profile = p and DataService.get(p)
		if profile then
			lastWin[u] = math.max(lastWin[u] or 0, profile.mmo.contest.lastWin)
		end
	end
	local order = ContestRules.placings(K, entries, score, lastWin, now)
	s.top = { order[1], order[2], order[3] }
	for place, u in order do
		local p = Players:GetPlayerByUserId(u)
		local profile = p and DataService.get(p)
		if p and profile then
			local credits = ContestRules.pay(K, place, false)
			EconomyService.addCredits(p, credits)
			Net.fire("Toast", p, { id = "contestPlace", place = place, credits = credits })
			ContestService.Placed:Fire(p, place)
			if place <= 3 then
				BadgeService.bump(p, "contestPodiums")
				CollectService.give(
					p,
					CollectPlan.ribbon(Config.Collect, ({ "first", "second", "third" })[place])
				)
				local hero = HeroService.get(p)
				if hero and stageAt then
					SafehouseService.place(hero, podiumCFrame(place))
				end
			end
			if place == 1 and ContestRules.canWin(K, lastWin[u], now) then
				lastWin[u] = now
				profile.mmo.contest.lastWin = now
				profile.mmo.contest.wins += 1
				BadgeService.bump(p, "contestWins")
				if profile.mmo.contest.wins >= 3 then
					CollectService.give(p, CollectPlan.ribbon(Config.Collect, "wins3"))
				end
			end
			DataService.saveSoon(p)
		end
	end
	local first = Players:GetPlayerByUserId(order[1])
	if first then
		Analytics.event(first, "contest_done", #entries, { s.theme, voters })
	end
end

local function step()
	if not stageAt then
		build()
		if not stageAt then
			return
		end
	end
	local now = os.time()
	local cycle = ContestRules.cycle(K, now)
	if not state or state.cycle ~= cycle then
		state = {
			cycle = cycle,
			theme = ContestRules.theme(K, cycle),
			entries = {},
			votes = {},
			phase = "idle",
			shown = 0,
			done = false,
			skipped = false,
			top = {},
		}
	end
	local s = state :: State
	local phase, i = ContestRules.phase(K, now, #s.entries)
	if phase ~= s.phase or (phase == "show" and i ~= s.shown) then
		local was = s.phase
		s.phase = phase
		if phase == "show" then
			s.shown = i
			if was == "call" and #s.entries < K.minEntries then
				-- too few contestants: skip now (the vote needs someone to vote for)
				s.skipped = true
				for _, u in s.entries do
					local p = Players:GetPlayerByUserId(u)
					if p then
						EconomyService.addCredits(p, ContestRules.pay(K, nil, true))
						Net.fire(
							"Toast",
							p,
							{ id = "contestSkipped", credits = ContestRules.pay(K, nil, true) }
						)
					end
				end
			end
		elseif phase == "results" and not s.done and not s.skipped then
			s.done = true
			results(s)
		end
		if beam then
			beam.Transparency = if phase == "call" then 0.55 else 1
		end
		-- a skipped contest still tells every device when it is over (pt-ui 2026-11-19: the idle step was never sent
		-- after a skip, so the CONTEST SKIPPED banner stayed up until the next contest's call, 30 minutes on)
		if ContestRules.announce(s.skipped, was, phase) then
			broadcast(s)
		end
	end
end

function ContestService.init()
	Net.on("ContestEnter", enter)
	Net.on("ContestGo", go)
	Net.on("ContestVote", vote)
	Net.on("ContestOpen", function(player: Player)
		if state then
			Net.fire("ContestState", player, packet(state :: State, os.time()))
		end
	end)
	for _, p in Players:GetPlayers() do
		joinedAt[p] = os.time()
	end
	Players.PlayerAdded:Connect(function(p)
		joinedAt[p] = os.time()
	end)
	Players.PlayerRemoving:Connect(function(p)
		joinedAt[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			step()
		end
	end)
end

return ContestService
