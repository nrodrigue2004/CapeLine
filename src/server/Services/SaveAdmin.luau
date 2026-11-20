-- SaveAdmin (list-combat 2026-11-20, Everything Left 464, 465): the two save tools nate runs by hand, from the
-- Studio command bar of the published place (API access on) or a server's console. Neither is reachable from a
-- client: no remote calls them. The steps are in notes/Launch Checklist.md "Player data requests".
-- * SaveAdmin.erase(userId): Roblox's right-to-erasure request. Removes the profile key, the player's rows on every
--   weekly board and their review queue rows (Shared.SaveAdminPlan lists them); a player online in this server is
--   kicked first with a plain message and their session stops saving, so nothing writes it back. Returns
--   { removed, failed, missing } counts.
-- * SaveAdmin.rollback(userId, beforeUnix): a bad build broke saves: puts the profile back to its newest version
--   written before that time (Roblox keeps 30 days of DataStore versions). Refuses while the player is online
--   anywhere (a live session lock), so ask them to leave first. Returns ok, the version or a reason.
-- In memory mode (Studio without API access, an unpublished place) both answer "memory" and touch nothing.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SaveAdminPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SaveAdminPlan"))

local DataService = require(script.Parent.DataService)

local SaveAdmin = {}

local function storeOf(t: SaveAdminPlan.Target): any
	if t.ordered then
		return DataStoreService:GetOrderedDataStore(t.store, t.scope)
	end
	return DataStoreService:GetDataStore(t.store)
end

function SaveAdmin.erase(userId: number): { [string]: any }
	if DataService.isMemoryMode() then
		return { reason = "memory" }
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		DataService.stopSaving(player)
		player:Kick("Your Capeline data was erased at your request.")
	end
	local targets, prefixes = SaveAdminPlan.erase(Config, userId, os.time())
	local removed, failed, missing = 0, 0, 0
	for _, t in targets do
		local ok, old = pcall(function()
			return storeOf(t):RemoveAsync(t.key)
		end)
		if not ok then
			failed += 1
		elseif old == nil then
			missing += 1
		else
			removed += 1
		end
	end
	for _, p in prefixes do
		local ok, err = pcall(function()
			local store = DataStoreService:GetDataStore(p.store)
			local pages = store:ListKeysAsync(p.prefix, Config.Data.admin.listPage)
			while true do
				for _, k in pages:GetCurrentPage() do
					store:RemoveAsync(k.KeyName)
					removed += 1
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
		if not ok then
			failed += 1
			warn("[SaveAdmin] erase: listing " .. p.prefix .. " failed: " .. tostring(err))
		end
	end
	print(
		string.format(
			"[SaveAdmin] erased %d: %d removed, %d not there, %d failed",
			userId,
			removed,
			missing,
			failed
		)
	)
	return { removed = removed, failed = failed, missing = missing }
end

function SaveAdmin.rollback(userId: number, beforeUnix: number): (boolean, string)
	if DataService.isMemoryMode() then
		return false, "memory"
	end
	if Players:GetPlayerByUserId(userId) then
		return false, "online here: ask them to leave first"
	end
	local D = Config.Data
	local key = D.keyPrefix .. tostring(math.floor(userId))
	local store = DataStoreService:GetDataStore(D.storeName)
	local versions = {}
	local okList, err = pcall(function()
		local pages = store:ListVersionsAsync(key, Enum.SortDirection.Descending, nil, beforeUnix * 1000, 100)
		for _, v in pages:GetCurrentPage() do
			table.insert(
				versions,
				{ version = v.Version, time = v.CreatedTime / 1000, deleted = v.IsDeleted }
			)
		end
	end)
	if not okList then
		return false, "listing versions failed: " .. tostring(err)
	end
	local version = SaveAdminPlan.pick(versions, beforeUnix)
	if not version then
		return false, "no version before that time"
	end
	local okGet, old = pcall(function()
		return store:GetVersionAsync(key, version)
	end)
	if not okGet or type(old) ~= "table" then
		return false, "reading the version failed"
	end
	local locked = false
	local okSet = pcall(function()
		store:UpdateAsync(key, function(now)
			if
				type(now) == "table"
				and type(now.lock) == "table"
				and os.time() - (tonumber(now.lock.time) or 0) < D.lockStealAfter
			then
				locked = true
				return nil -- a live session holds it: leave it alone
			end
			return { data = old.data }
		end)
	end)
	if locked then
		return false, "a server holds the profile: ask them to leave first"
	end
	if not okSet then
		return false, "writing failed"
	end
	print(string.format("[SaveAdmin] rolled %d back to version %s", userId, version))
	return true, version
end

return SaveAdmin
