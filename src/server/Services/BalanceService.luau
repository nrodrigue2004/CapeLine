-- BalanceService: live tuning at boot (spec: Global data, "Balance_v<N>"; gap check G11, WP8). The server
-- boot calls load() before it requires any other service, so every service reads the tuned numbers from
-- its first line: one GetAsync of Config.Balance.key in the DataStore "Balance_v" .. Config.Version.balance,
-- laid over the live Config by Shared.BalanceMerge (only Config.Balance.keys, each inside its range).
-- * Any trouble runs the bundled Config as it is: the switch off, an unpublished place, Studio without API
--   access, a DataStore error, no key, a bad value, or no answer inside Config.Balance.timeout seconds (a late
--   answer is ignored, so numbers never change mid-game). The result is printed at boot.
-- * Devices keep the bundled Config: the whitelist holds only numbers the server alone reads.
-- * init() logs balance_live once per player session (value: numbers applied; fields: "v<N>.<rev>", the
--   source, numbers refused), so the dashboard can split any KPI by the balance a player played on.
-- * report() prints the whole result (the Dev panel's "Balance: print").
-- Requires only Config and Shared at load; Analytics is required in init, after it has booted.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local BalanceMerge = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceMerge"))

local BalanceService = {}

-- what boot found: source is live (numbers applied), none (no key written), bundled (a key with nothing
-- usable), off, unpublished, studio (no API access), error or timeout
BalanceService.source = "off"
BalanceService.rev = nil :: number?
BalanceService.applied = {} :: { BalanceMerge.Applied }
BalanceService.rejected = {} :: { BalanceMerge.Rejected }
BalanceService.loaded = false

local function storeName(): string
	return Config.Balance.store .. tostring(Config.Version.balance)
end

-- "v1.3": the bundled balance version and the live key's revision (0 when it has none or nothing applied)
function BalanceService.tag(): string
	local rev = if BalanceService.source == "live" then BalanceService.rev or 0 else 0
	return string.format("v%d.%d", Config.Version.balance, rev)
end

-- The raw value of the live key: ok, value (nil when no key is written), or false, a reason code
local function read(): (boolean, any)
	local B = Config.Balance
	local okStore, store = pcall(function()
		return DataStoreService:GetDataStore(storeName())
	end)
	if not okStore then
		return false, if RunService:IsStudio() then "studio" else "error"
	end
	local lastWhy = "error"
	for try = 1, math.max(1, B.tries) do
		local ok, value = pcall(function()
			return (store :: DataStore):GetAsync(B.key)
		end)
		if ok then
			return true, value
		end
		-- Studio without "Enable Studio Access to API Services" fails every call
		lastWhy = if RunService:IsStudio() then "studio" else "error"
		if try < B.tries then
			task.wait(B.retryWait)
		end
	end
	return false, lastWhy
end

-- Read and apply the live key, once. Yields up to Config.Balance.timeout seconds. Never throws.
function BalanceService.load()
	if BalanceService.loaded then
		return
	end
	BalanceService.loaded = true
	local B = Config.Balance
	if not B.on then
		BalanceService.source = "off"
	elseif game.PlaceId == 0 then
		BalanceService.source = "unpublished"
	else
		-- the read runs on its own thread so a slow DataStore never holds the boot past the timeout; an
		-- answer after the deadline is dropped
		local finished = false
		local result: { any } = {}
		task.spawn(function()
			result = { pcall(read) } -- true, read ok, the value (or the reason)
			finished = true
		end)
		local deadline = os.clock() + B.timeout
		while not finished and os.clock() < deadline do
			task.wait(0.05)
		end
		if not finished then
			BalanceService.source = "timeout"
		elseif result[1] ~= true or result[2] ~= true then
			BalanceService.source = if result[1] == true then tostring(result[3]) else "error"
		elseif result[3] == nil then
			BalanceService.source = "none"
		else
			local raw = result[3]
			if type(raw) == "string" then
				local okJson, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
				raw = if okJson then decoded else raw
			end
			local okMerge, merged = pcall(BalanceMerge.merge, Config, raw, B)
			if okMerge then
				BalanceMerge.write(Config, merged.applied)
				BalanceService.applied = merged.applied
				BalanceService.rejected = merged.rejected
				BalanceService.rev = merged.rev
				BalanceService.source = if #merged.applied > 0 then "live" else "bundled"
			else
				BalanceService.source = "error"
			end
		end
	end
	BalanceService.print()
end

function BalanceService.print()
	print(
		string.format(
			"[Balance] %s %s (%s/%s): %d set, %d refused",
			BalanceService.tag(),
			BalanceService.source,
			storeName(),
			Config.Balance.key,
			#BalanceService.applied,
			#BalanceService.rejected
		)
	)
	if #BalanceService.rejected > 0 then
		warn(
			string.format(
				"[Balance] %d live numbers refused (Dev panel: Balance: print)",
				#BalanceService.rejected
			)
		)
	end
end

-- Everything boot applied and refused, one line each (the Dev panel)
function BalanceService.report()
	BalanceService.print()
	local lines = BalanceMerge.lines({
		view = Config,
		applied = BalanceService.applied,
		rejected = BalanceService.rejected,
		rev = BalanceService.rev,
	})
	if #lines == 0 then
		print("[Balance]   (the bundled Config, nothing changed)")
	end
	for _, line in lines do
		print("[Balance]" .. line)
	end
end

-- balance_live once per player session (after Analytics has booted)
function BalanceService.init()
	local Analytics = require(script.Parent.Analytics)
	local function log(player: Player)
		Analytics.event(
			player,
			"balance_live",
			#BalanceService.applied,
			{ BalanceService.tag(), BalanceService.source, #BalanceService.rejected }
		)
	end
	Players.PlayerAdded:Connect(log)
	for _, player in Players:GetPlayers() do
		task.spawn(log, player)
	end
end

return BalanceService
