-- BoardStore: the OrderedDataStore side of the weekly boards (spec: Global data and leaderboards,
-- Weekly_<week> ordered stores; Config.Boards; Shared.BoardKeys has the rules). Ported from Ragdoll Rides'
-- BoardStore (stores per scope, the minute cache, display names, friends once a session, memory mode).
-- * set writes one player's weekly total (SetAsync: the total, so a retry never counts twice). It yields;
--   BoardService calls it from its write pass and spaces the calls by the budget.
-- * read returns a board's top entries, cached Config.Boards.cacheSeconds; a settled past week (the reward
--   reads) is cached for the server's life. A failed read serves the last good one, else returns nil.
-- * Both check Roblox's live request budget first and give way when it is spent.
-- * names: Roblox display names for user ids (cached; the players here from Players). friendsOf: a
--   player's Roblox friends (first Config.Boards.friendsMax), read once a session.
-- * Studio without API access (DataService memory mode): the boards live in memory for the session; Dev
--   rows use negative user ids and fixed names.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local BoardKeys = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoardKeys"))

local DataService = require(script.Parent.DataService)

local BoardStore = {}

local B = Config.Boards

type Read = { time: number, entries: { BoardKeys.Entry }, final: boolean }

local stores: { [string]: OrderedDataStore } = {}
local memory: { [string]: { [number]: number } } = {}
local cache: { [string]: Read } = {}
local names: { [number]: string } = {}
local friendSets: { [Player]: { [number]: boolean } } = {}

BoardStore.writes = 0 -- writes started this session (the Dev panel's stats line)
BoardStore.reads = 0

local function scopeKey(week: number, board: string): string
	return BoardKeys.storeName(B, week) .. "/" .. board
end

local function storeFor(week: number, board: string): OrderedDataStore?
	local key = scopeKey(week, board)
	if stores[key] == nil then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(BoardKeys.storeName(B, week), board)
		end)
		if ok then
			stores[key] = store
		end
	end
	return stores[key]
end

local function budgetLeft(kind: Enum.DataStoreRequestType): boolean
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return not ok or n > 0
end

function BoardStore.memoryMode(): boolean
	return DataService.isMemoryMode()
end

-- Write a player's weekly total on a board. Yields. Returns true when it was written.
function BoardStore.set(week: number, board: string, userId: number, value: number): boolean
	BoardStore.writes += 1
	if BoardStore.memoryMode() then
		local m = memory[scopeKey(week, board)] or {}
		memory[scopeKey(week, board)] = m
		m[userId] = value
		return true
	end
	if not budgetLeft(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
		return false
	end
	local store = storeFor(week, board)
	if not store then
		return false
	end
	local ok, err = pcall(function()
		(store :: OrderedDataStore):SetAsync(BoardKeys.entryKey(userId), math.floor(value))
	end)
	if not ok then
		warn("[Boards] write failed: " .. tostring(err))
	end
	return ok
end

-- The top `count` entries on a board, best first (BoardKeys.sort). final: a settled past week (kept for the
-- server's life). Returns nil when nothing could be read.
function BoardStore.read(week: number, board: string, count: number, final: boolean?): { BoardKeys.Entry }?
	local key = scopeKey(week, board) .. "#" .. count
	local hit = cache[key]
	if hit and (hit.final or os.clock() - hit.time < B.cacheSeconds) then
		return hit.entries
	end
	local entries: { BoardKeys.Entry }? = nil
	if BoardStore.memoryMode() then
		local list = {}
		local m: { [number]: number } = memory[scopeKey(week, board)] or {}
		for userId, value in m do
			table.insert(list, { userId = userId, value = value })
		end
		BoardKeys.sort(list)
		while #list > count do
			table.remove(list)
		end
		entries = list
	else
		local store = storeFor(week, board)
		if store and budgetLeft(Enum.DataStoreRequestType.GetSortedAsync) then
			BoardStore.reads += 1
			local ok, pages = pcall(function()
				return (store :: OrderedDataStore):GetSortedAsync(false, math.min(count, 100))
			end)
			if ok and pages then
				local list = {}
				for _, item in (pages :: DataStorePages):GetCurrentPage() do
					local userId = tonumber(item.key)
					local value = tonumber(item.value)
					if userId and value and value > 0 then
						table.insert(list, { userId = userId, value = value })
					end
				end
				entries = BoardKeys.sort(list)
			elseif not ok then
				warn("[Boards] read failed: " .. tostring(pages))
			end
		end
	end
	if entries == nil then
		return if hit then hit.entries else nil
	end
	cache[key] = { time = os.clock(), entries = entries, final = final == true }
	return entries
end

-- Your own new total shows on your next look (the cache would hide it for a minute)
function BoardStore.forget(week: number, board: string)
	local prefix = scopeKey(week, board) .. "#"
	for key, r in cache do
		if not r.final and string.sub(key, 1, #prefix) == prefix then
			cache[key] = nil
		end
	end
end

-- Dev (Studio memory mode only): put rows on a board
function BoardStore.devRows(week: number, board: string, rows: { BoardKeys.Entry })
	if not BoardStore.memoryMode() then
		return
	end
	local m = memory[scopeKey(week, board)] or {}
	memory[scopeKey(week, board)] = m
	for _, r in rows do
		m[r.userId] = r.value
	end
	BoardStore.forget(week, board)
end

-- Fill the name cache for these ids; returns it. Names are Roblox display names only (Roblox filters
-- them); a Dev row (a negative id) gets a fixed test name.
function BoardStore.names(userIds: { number }): { [number]: string }
	local missing = {}
	for _, id in userIds do
		if id < 0 then
			names[id] = "Test Hero " .. tostring(-id)
		else
			local player = Players:GetPlayerByUserId(id)
			if player then
				names[id] = player.DisplayName
			elseif names[id] == nil then
				table.insert(missing, id)
			end
		end
	end
	-- GetUserInfosByUserIdsAsync takes up to 200 ids a call
	for i = 1, #missing, 200 do
		local chunk = table.move(missing, i, math.min(#missing, i + 199), 1, {})
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(chunk)
		end)
		if ok and infos then
			for _, info in infos do
				names[info.Id] = info.DisplayName
			end
		end
	end
	return names
end

-- A player's Roblox friends (first Config.Boards.friendsMax), read once a session
function BoardStore.friendsOf(player: Player): { [number]: boolean }
	local set = friendSets[player]
	if set then
		return set
	end
	local fresh: { [number]: boolean } = {}
	friendSets[player] = fresh
	local ok = pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		local seen = 0
		while seen < B.friendsMax do
			for _, item in pages:GetCurrentPage() do
				fresh[item.Id] = true
				seen += 1
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		friendSets[player] = nil -- try again on the next look
	end
	return fresh
end

function BoardStore.init()
	Players.PlayerRemoving:Connect(function(player)
		friendSets[player] = nil
	end)
end

return BoardStore
