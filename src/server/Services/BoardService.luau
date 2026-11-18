-- BoardService: the weekly leaderboards (spec: Global data and leaderboards, "Weekly_<week> ordered stores:
-- Boss MVP count, rescues, PvP wins (cosmetic leaderboards)"; PvP "A weekly PvP leaderboard gives cosmetics
-- only"; gap check G2, WP2). Config.Boards has the numbers, Shared.BoardKeys the rules, BoardStore the stores.
-- * What counts: a world boss beaten as its MVP (BossService.Rewarded, tier mvp), a rescue (IncidentService
--   .Rescued: incidents, events and contracts; EconomyService.Earned "deepRescue": the Sunken Line's
--   commuters), and a PvP win that paid (DeathService.PvpWon: two flagged heroes, past the anti-farming
--   ledger, so traded or repeat wins never count). Bots never count.
-- * Each counts on the save first (BoardKeys.add on profile.mmo.counts), then queues the new weekly total in
--   the write batch: a pass every Config.Boards.tick s writes what is due (one write per stat per player per
--   writeEvery s, within the budget share), a leave flushes that player's totals, shutdown flushes all.
-- * BoardOpen(board, filter) answers BoardData: the top 50 (or your friends among the top 100) with ranks
--   and Roblox display names, your own row pinned, the week's countdown and the reward line; or error = true.
-- * The plaza board (PLACEHOLDER ART): a free-standing screen on the plaza; BoardPlaza carries each board's
--   top 10 to every device, only when it changed.
-- * Rewards: the week a player counted in waits on the save; once its standings settle (Config.Boards.reward
--   .settle after it ends) the next join, or the next minute online, reads the final ranks once and grants
--   each top-10 board's title (BoardKeys.claim; BoardReward to the device, board_reward to analytics).
-- * Studio: Dev rows (40 test heroes on every board, and you at #6) and a forced week roll (BoardService.dev).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local BoardKeys = require(Shared:WaitForChild("BoardKeys"))

local Services = script.Parent
local BoardStore = require(Services.BoardStore)
local DataService = require(Services.DataService)
local Analytics = require(Services.Analytics)
local CityBuilder = require(Services.CityBuilder)
local BossService = require(Services.BossService)
local IncidentService = require(Services.IncidentService)
local EconomyService = require(Services.EconomyService)
local DeathService = require(Services.DeathService)

local BoardService = {}

local B = Config.Boards
local batch = BoardKeys.newBatch()
local weekOffset = 0 -- Studio: forced week rolls
local devSettled = false -- Studio: after a forced roll, the ended week counts at once
local claiming: { [Player]: boolean } = {}
local opened: { [Player]: { [string]: number } } = {} -- board_open's pacing (BoardKeys.logOpen)
local plaza: { [string]: any }? = nil
local plazaDigest = ""

BoardService.batch = batch

-- The boards' clock: os.time, plus a week for each Studio roll
local function clock(): number
	return os.time() + weekOffset * 7 * 86400
end

function BoardService.week(): number
	return BoardKeys.week(clock())
end

local function countsOf(player: Player): { [string]: number }?
	local profile = DataService.get(player)
	return profile and profile.mmo and profile.mmo.counts
end

---------------------------------------------------------------------------
-- Writes
---------------------------------------------------------------------------

local function write(job: BoardKeys.Job)
	local value = job.value
	local ok = BoardStore.set(job.week, job.board, job.userId, value)
	BoardKeys.done(B, batch, job, ok, value, os.clock())
	if ok then
		BoardStore.forget(job.week, job.board)
	end
end

-- One write pass (all: shutdown or a Studio roll: every unwritten total, the whole budget)
local function pass(all: boolean?)
	for _, job in BoardKeys.due(B, batch, os.clock(), #Players:GetPlayers(), all) do
		task.spawn(write, job)
	end
	BoardKeys.sweep(B, batch, os.clock())
end

-- Count n on a board for this player (a Config.Boards id: BossMvp, Rescues, PvpWins)
function BoardService.add(player: Player, id: string, n: number?)
	local counts = countsOf(player)
	if not counts or not BoardKeys.board(B, id) then
		return
	end
	local w = BoardService.week()
	local total = BoardKeys.add(B, counts, id, n or 1, w)
	BoardKeys.queue(batch, w, id, player.UserId, total)
end

---------------------------------------------------------------------------
-- Rewards
---------------------------------------------------------------------------

local function tryClaim(player: Player)
	local counts = countsOf(player)
	if not counts or claiming[player] then
		return
	end
	BoardKeys.rollover(B, counts, BoardService.week())
	local week, ids = BoardKeys.claimable(B, counts, clock(), if devSettled then 0 else nil)
	if not week then
		return
	end
	claiming[player] = true
	task.spawn(function()
		local ranks: { [string]: number? } = {}
		local ok = true
		for _, id in ids do
			local entries = BoardStore.read(week, id, B.readCount, true)
			if not entries then
				ok = false -- try again next minute
				break
			end
			ranks[id] = BoardKeys.rankOf(entries, player.UserId)
		end
		local now = countsOf(player)
		if ok and now and player.Parent == Players then
			local grants = BoardKeys.claim(B, now, week, ranks)
			for _, g in grants do
				Analytics.event(player, "board_reward", g.rank, { g.board, g.rank })
				Net.fire(
					"BoardReward",
					player,
					{ board = g.board, rank = g.rank, title = g.title, new = g.new }
				)
			end
			DataService.changed(player)
			DataService.saveSoon(player)
		end
		claiming[player] = nil
	end)
end

---------------------------------------------------------------------------
-- Reads: the screen
---------------------------------------------------------------------------

local function nameRows(list: { BoardKeys.Row }): { { [string]: any } }
	local ids = {}
	for _, r in list do
		table.insert(ids, r.userId)
	end
	local names = BoardStore.names(ids)
	local rows = {}
	for _, r in list do
		table.insert(rows, {
			rank = r.rank,
			name = names[r.userId] or "Hero",
			value = r.value,
			me = r.me,
			friend = r.friend,
		})
	end
	return rows
end

local function onOpen(player: Player, index: number, filterNum: number)
	local b = B.boards[index]
	local counts = countsOf(player)
	if not b or not counts then
		return
	end
	local w = BoardService.week()
	local base = {
		board = index,
		filter = filterNum,
		week = w,
		endsIn = BoardKeys.weekEnd(w) - clock(),
		owned = BoardKeys.owns(B, counts, b.id), -- this board's title, from an earlier week
	}
	local entries = BoardStore.read(w, b.id, B.readCount)
	if not entries then
		base.error = true
		Net.fire("BoardData", player, base)
		return
	end
	local filter = if filterNum == 1 then "friends" else "all"
	local friends = if filter == "friends" then BoardStore.friendsOf(player) else {}
	local myValue = BoardKeys.total(counts, b.id, w)
	local list, mine = BoardKeys.rows(entries, player.UserId, myValue, friends, filter, B.topCount)
	base.rows = nameRows(list)
	base.mine = if mine then { rank = mine.rank, value = mine.value } else nil
	base.cut = #entries >= B.readCount -- your rank past the top 100 is not known
	if player.Parent == Players then
		Net.fire("BoardData", player, base)
		local last = opened[player] or {}
		opened[player] = last
		if BoardKeys.logOpen(B, last, index, filterNum, os.clock()) then
			Analytics.event(
				player,
				"board_open",
				if mine and mine.rank then mine.rank else 0,
				{ b.id, filter }
			)
		end
	end
end

---------------------------------------------------------------------------
-- The plaza board
---------------------------------------------------------------------------

local function buildProp()
	local world = CityBuilder.world
	local bt = world and world.downtown and world.downtown.beacon
	if not bt then
		return
	end
	local P = B.prop
	local x, z, fx, fz = BoardKeys.propSpot(B, bt.x, bt.z)
	local gy = CityBuilder.heightAt(x, z)
	local w, h = P.size[1], P.size[2]
	local model = Instance.new("Model")
	model.Name = "WeeklyBoard"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- every device draws it (SurfaceGui adornee)
	local at = Vector3.new(x, gy + P.height + h / 2, z)
	local cf = CFrame.lookAt(at, at + Vector3.new(fx, 0, fz))
	local function part(name: string, size: Vector3, c: CFrame, color: Color3, mat: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.Size = size
		p.CFrame = c
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	-- PLACEHOLDER ART: a navy screen in a gold frame on two legs
	local screen = part("Screen", Vector3.new(w, h, 0.6), cf, Color3.fromRGB(16, 22, 44))
	part(
		"Frame",
		Vector3.new(w + 1.6, h + 1.6, 0.4),
		cf * CFrame.new(0, 0, 0.5),
		Color3.fromRGB(200, 150, 40)
	)
	part(
		"Crest",
		Vector3.new(w * 0.5, 1.6, 0.5),
		cf * CFrame.new(0, h / 2 + 1.4, 0.3),
		Color3.fromRGB(255, 200, 60),
		Enum.Material.Neon
	)
	local legH = P.height + 0.8
	for _, side in { -1, 1 } do
		part(
			"Leg",
			Vector3.new(1.2, legH, 1.2),
			cf * CFrame.new(side * (w / 2 - 1.5), -h / 2 - legH / 2 + 0.8, 0.8),
			Color3.fromRGB(40, 42, 54),
			Enum.Material.Metal
		)
	end
	model.PrimaryPart = screen
	model.Parent = Workspace
end

local function plazaPayload(): { [string]: any }?
	local w = BoardService.week()
	local boards = {}
	for i, b in B.boards do
		local entries = BoardStore.read(w, b.id, B.readCount)
		if not entries then
			return nil
		end
		local list = BoardKeys.rows(entries, 0, 0, {}, "all", B.plazaCount)
		local rows = {}
		for _, r in nameRows(list) do
			table.insert(rows, { rank = r.rank, name = r.name, value = r.value })
		end
		boards[i] = rows
	end
	return { week = w, endsIn = BoardKeys.weekEnd(w) - clock(), boards = boards }
end

local function refreshPlaza(force: boolean?)
	local p = plazaPayload()
	if not p then
		return
	end
	local d = tostring(p.week) .. BoardKeys.digest(p.boards)
	if d ~= plazaDigest or force then
		plazaDigest = d
		plaza = p
		Net.fireAll("BoardPlaza", p)
	end
end

---------------------------------------------------------------------------
-- Studio
---------------------------------------------------------------------------

-- Dev panel: "rows" puts 40 test heroes on every board this week and you at #6; "roll" ends the week now
-- (every unwritten total first) so the claim runs as if a week had passed and the standings settled
function BoardService.dev(player: Player, what: string)
	if not RunService:IsStudio() then
		return
	end
	local w = BoardService.week()
	if what == "rows" then
		for _, b in B.boards do
			local rows = {}
			for i = 1, 40 do
				table.insert(rows, { userId = -i, value = 41 - i })
			end
			BoardStore.devRows(w, b.id, rows)
			BoardService.add(player, b.id, math.max(0, 35 - BoardKeys.total(countsOf(player) or {}, b.id, w)))
		end
		pass(true)
	elseif what == "roll" then
		pass(true)
		local deadline = os.clock() + 10
		while BoardKeys.pending(batch) > 0 and os.clock() < deadline do
			task.wait(0.2)
			pass(true)
		end
		weekOffset += 1
		devSettled = true
		for _, p in Players:GetPlayers() do
			tryClaim(p)
		end
	end
	task.delay(0.5, refreshPlaza, true)
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function BoardService.init()
	BoardStore.init()
	Net.on("BoardOpen", onOpen)
	-- the hooks
	BossService.Rewarded:Connect(function(player: Player, _bossId: any, tier: string, defeated: boolean)
		if defeated and tier == "mvp" then
			BoardService.add(player, "BossMvp", 1)
		end
	end)
	IncidentService.Rescued:Connect(function(hero: any)
		if hero and hero.player then
			BoardService.add(hero.player, "Rescues", 1)
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, action: string)
		if action == "deepRescue" then
			BoardService.add(player, "Rescues", 1) -- the Sunken Line's commuters (no Rescued signal there)
		end
	end)
	DeathService.PvpWon:Connect(function(winner: any)
		if winner and winner.player then
			BoardService.add(winner.player, "PvpWins", 1)
		end
	end)
	-- the claim on join, then the plaza's top 10
	DataService.Loaded:Connect(function(player: Player)
		tryClaim(player)
		if plaza then
			Net.fire("BoardPlaza", player, plaza)
		end
	end)
	DataService.Leaving:Connect(function(player: Player)
		BoardKeys.leave(batch, player.UserId)
		pass()
	end)
	Players.PlayerRemoving:Connect(function(player)
		claiming[player] = nil
		opened[player] = nil
	end)
	-- the write pass
	task.spawn(function()
		while true do
			task.wait(B.tick)
			pass()
		end
	end)
	-- each minute: claims for players online across a week's end, and the plaza
	buildProp()
	task.spawn(function()
		task.wait(5)
		while true do
			for _, p in Players:GetPlayers() do
				tryClaim(p)
			end
			refreshPlaza()
			task.wait(B.prop.refresh)
		end
	end)
	game:BindToClose(function()
		local deadline = os.clock() + Config.Data.closeDeadline - 2
		repeat
			pass(true)
			task.wait(0.25)
		until BoardKeys.pending(batch) == 0 or os.clock() > deadline
	end)
end

return BoardService
