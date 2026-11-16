-- GuardService: strikes, kicks, reports and the review queue (spec: Anti-exploit checks; Anti-farming
-- "Reports"; CLAUDE.md rule 6: moderation leans hard toward not punishing players).
-- * Strikes: a teleport-sized speed fail (MoveGuard) is one strike; dropped remote calls (Net) count one per
--   10 inside a minute, so lag never adds up. 3 strikes in 10 minutes kick with a generic message and save
--   the kick on the account. From the second kick the account lands in the review queue. Nothing here bans.
-- * Reports: every name plate has Report (preset reasons, no typed text). One per reporter per target every
--   10 minutes; 3 from 3 accounts in 10 minutes put the target in the review queue.
-- * The review queue is a DataStore list nate reads by hand (never read back by the game).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuardRules = require(Shared:WaitForChild("GuardRules"))

local DataService = require(script.Parent.DataService)
local MoveGuard = require(script.Parent.MoveGuard)
local Analytics = require(script.Parent.Analytics)

local GuardService = {}

local strikes: { [Player]: GuardRules.Strikes } = {}
local reports = GuardRules.newReports()
local flagged: { [Player]: { [string]: boolean } } = {} -- analytics: kinds already logged this session
local store: DataStore? = nil
GuardService.queue = {} :: { any } -- this server's review rows (also written to the store)

-- A row for the review queue: who, what kind (kicks, reports, trade) and a short detail table
function GuardService.review(userId: number, kind: string, detail: { [string]: any }?)
	local row = { userId = userId, kind = kind, detail = detail or {}, at = os.time(), job = game.JobId }
	table.insert(GuardService.queue, row)
	warn(string.format("[GuardService] review: %d %s", userId, kind))
	if not store and not DataService.isMemoryMode() then
		local ok, got = pcall(DataStoreService.GetDataStore, DataStoreService, Config.Data.reviewStore)
		store = if ok then got else nil
	end
	local s = store
	if s and not DataService.isMemoryMode() then
		task.spawn(function()
			pcall(function()
				s:SetAsync(string.format("%s_%d_%d", kind, userId, row.at), row)
			end)
		end)
	end
end

local function kick(player: Player, kind: string)
	local profile = DataService.get(player)
	local kicks = 1
	if profile then
		profile.guard.kicks += 1
		kicks = profile.guard.kicks
		DataService.changed(player)
	end
	local s = strikes[player]
	if GuardRules.needsReview(Config, kicks) then
		GuardService.review(player.UserId, "kicks", { kicks = kicks, last = kind, kinds = s and s.kinds })
	end
	if RunService:IsStudio() then
		warn("[GuardService] would kick " .. player.Name .. " (" .. kind .. "); Studio does not kick")
		strikes[player] = GuardRules.newStrikes()
		return
	end
	DataService.save(player)
	player:Kick("Connection problem. Please rejoin.")
end

local function strikesOf(player: Player): GuardRules.Strikes
	local s = strikes[player]
	if not s then
		s = GuardRules.newStrikes()
		strikes[player] = s
	end
	return s
end

-- Count a strike of a kind (speed, remote, ...)
function GuardService.strike(player: Player, kind: string)
	if player.Parent ~= Players then
		return
	end
	local book = strikesOf(player)
	local kicked = GuardRules.strike(Config, book, kind, os.clock())
	local seen = flagged[player] or {}
	flagged[player] = seen
	if not seen[kind] or kicked then
		-- one event per player per kind of trouble (a speed hack would send one a frame)
		seen[kind] = true
		Analytics.event(player, "anti_exploit_flag", 1, { kind, if kicked then "kick" else "strike" })
	end
	if kicked then
		task.spawn(kick, player, kind) -- the save before the kick yields; never inside a caller's frame loop
	end
end

local function onReport(player: Player, userId: number, reason: number)
	local target = Players:GetPlayerByUserId(userId)
	if not target then
		return
	end
	local ok, flagged = GuardRules.report(Config, reports, player.UserId, userId, os.clock())
	if ok then
		Analytics.event(player, "report_player", 1, { Config.Pvp.report.reasons[reason] or "other" })
	end
	Net.fire("Toast", player, { id = if ok then "reported" else "reportedAlready" })
	if flagged then
		GuardService.review(userId, "reports", { reason = Config.Pvp.report.reasons[reason] })
	end
end

function GuardService.init()
	Net.onRejected(function(player)
		if GuardRules.netDrop(Config, strikesOf(player), os.clock()) then
			kick(player, "remote")
		end
	end)
	MoveGuard.strikeHook = GuardService.strike
	Net.on("ReportPlayer", onReport)
	Players.PlayerRemoving:Connect(function(player)
		strikes[player] = nil
		flagged[player] = nil
	end)
end

return GuardService
