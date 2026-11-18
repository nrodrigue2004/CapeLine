-- DataService: each player's saved profile (spec: Data model and save rules). Ported from the Ragdoll Rides
-- saving package, as the spec asks:
-- * One DataStore key per player (P_<userId> in CapelineProfile_v1), written only by the server with
--   UpdateAsync and a session lock { jobId, time }, so a second server never opens the same profile.
--   Stored value: { data = profile, lock = { jobId, time }? }.
-- * Load: wait for another server's lock to clear (Config.Data.lockWaitTries x lockWaitTime), take over a
--   lock older than lockStealAfter (a crashed server's). Still locked: the player is asked to rejoin.
-- * Save: every 120 s (refreshing the lock), soon after a level up, gear change, quest turn-in, choice or
--   purchase (saveSoon), on leave (releasing the lock) and on server close. A save that finds another
--   server's lock stops saving for that player instead of overwriting.
-- * DataStore down at load: the player plays on a fresh profile that is never saved, and is told so.
-- * Studio without API access (or an unpublished place): profiles live in memory for the session.
-- Before every save the beforeSave hooks run (HeroService writes the live hero back into its character),
-- also in a session that cannot save, so a slot switch never drops the old hero's live state.
-- * Leaving: Roblox runs PlayerRemoving handlers in no set order, so the leave runs here in one order:
--   Leaving, then the beforeSave hooks (they read the live hero), then Left (HeroService removes the hero
--   there; it leaves a hero whose player DataService still holds), then the write.
-- Clients only ever see ProfileSchema.clientView, sent on ProfileSync whenever something changes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local DataService = {}

DataService.Loaded = Signal.new() -- (player, profile)
DataService.Leaving = Signal.new() -- (player, profile, exitReason?): before the last save
DataService.Left = Signal.new() -- (player): the leave-save's hooks have read the live state (heroes go now)

type Session = {
	profile: { [string]: any },
	canSave: boolean,
	saving: boolean,
	sendQueued: boolean,
	fullQueued: boolean, -- false: only the wallet changed (a small sync)
	soonQueued: boolean,
	released: boolean,
	leaving: boolean,
	playClock: number,
	lastSave: number,
}

local store: DataStore? = nil
local memoryMode = false
local memoryProfiles: { [number]: any } = {}
local sessions: { [Player]: Session } = {}
local waiting: { [Player]: { thread } } = {}
local beforeSave: { (Player, any) -> () } = {}

local function keyFor(player: Player): string
	return Config.Data.keyPrefix .. tostring(player.UserId)
end

local function lockIsForeign(lock: any, now: number): boolean
	if type(lock) ~= "table" or lock.jobId == game.JobId then
		return false
	end
	return now - (tonumber(lock.time) or 0) < Config.Data.lockStealAfter
end

local function loadFromStore(player: Player): ({ [string]: any }?, string?)
	local cfg = Config.Data
	local lastReason = "error"
	for attempt = 1, cfg.lockWaitTries do
		local loaded: { [string]: any }? = nil
		local locked = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(keyFor(player), function(old)
				loaded, locked = nil, false
				if type(old) == "table" and lockIsForeign(old.lock, os.time()) then
					locked = true
					return nil
				end
				local data = if type(old) == "table" then old.data else nil
				local profile = ProfileSchema.load(ProfileSchema.deepCopy(data))
				loaded = profile
				return { data = profile, lock = { jobId = game.JobId, time = os.time() } }
			end)
		end)
		if ok and loaded then
			return loaded, nil
		end
		if player.Parent ~= Players then
			return nil, "left"
		end
		if not ok then
			warn(
				string.format(
					"[DataService] load %d failed (try %d): %s",
					player.UserId,
					attempt,
					tostring(err)
				)
			)
			lastReason = "error"
			task.wait(2 ^ attempt)
		else
			lastReason = if locked then "locked" else "error"
			task.wait(cfg.lockWaitTime)
		end
	end
	return nil, lastReason
end

local function saveToStore(player: Player, session: Session, release: boolean): boolean
	local snapshot = ProfileSchema.deepCopy(session.profile)
	local okSize, encoded = pcall(HttpService.JSONEncode, HttpService, snapshot)
	if okSize and #encoded > Config.Data.capBytes then
		warn(
			string.format(
				"[DataService] %d: profile is %d bytes, over the cap; not saved",
				player.UserId,
				#encoded
			)
		)
		return false
	end
	for attempt = 1, Config.Data.saveRetries do
		local lost = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(keyFor(player), function(old)
				lost = false
				if type(old) == "table" and type(old.lock) == "table" and old.lock.jobId ~= game.JobId then
					lost = true
					return nil
				end
				return {
					data = snapshot,
					lock = if release then nil else { jobId = game.JobId, time = os.time() },
				}
			end)
		end)
		if ok then
			if lost then
				warn(
					string.format(
						"[DataService] %d: another server took the profile; this one stops saving",
						player.UserId
					)
				)
				session.canSave = false
				return false
			end
			return true
		end
		warn(
			string.format("[DataService] save %d failed (try %d): %s", player.UserId, attempt, tostring(err))
		)
		task.wait(attempt)
	end
	return false
end

local function addPlayTime(session: Session)
	local now = os.clock()
	session.profile.stats.playSeconds += math.max(0, now - session.playClock)
	session.playClock = now
end

function DataService.isMemoryMode(): boolean
	return memoryMode
end

-- Run a hook before every save: fn(player, profile) writes live state into the profile
function DataService.onBeforeSave(fn: (Player, any) -> ())
	table.insert(beforeSave, fn)
end

local function runHooks(player: Player, session: Session)
	for _, fn in beforeSave do
		local ok, err = pcall(fn, player, session.profile)
		if not ok then
			warn("[DataService] beforeSave: " .. tostring(err))
		end
	end
end

-- Write the profile (the hooks already ran). release = the player is leaving (drops the session lock).
local function write(player: Player, session: Session, release: boolean): boolean
	if not session.canSave or session.released then
		return false
	end
	addPlayTime(session)
	session.lastSave = os.clock()
	if memoryMode then
		memoryProfiles[player.UserId] = ProfileSchema.deepCopy(session.profile)
		if release then
			session.released = true
		end
		return true
	end
	while session.saving do
		task.wait(0.1)
	end
	if session.released then
		return false
	end
	session.saving = true
	local ok = saveToStore(player, session, release)
	session.saving = false
	if release then
		session.released = true
	end
	return ok
end

-- Save now. release = the player is leaving (drops the session lock). The hooks write live state into the
-- profile even when this session cannot save (it still lives in memory, and a slot switch reads it).
function DataService.save(player: Player, release: boolean?): boolean
	local session = sessions[player]
	if not session or session.released then
		return false
	end
	runHooks(player, session)
	return write(player, session, release == true)
end

-- Save shortly (level up, gear change, quest turn-in, choice, purchase). A burst becomes one write.
function DataService.saveSoon(player: Player)
	local session = sessions[player]
	if not session or session.soonQueued or not session.canSave then
		return
	end
	session.soonQueued = true
	local wait = math.max(0, Config.Data.soonDelay - (os.clock() - session.lastSave))
	task.delay(math.max(1, wait), function()
		session.soonQueued = false
		if sessions[player] == session then
			DataService.save(player, false)
		end
	end)
end

local function sendView(player: Player, full: boolean?)
	local session = sessions[player]
	if session then
		Net.fire("ProfileSync", player, ProfileSchema.clientView(session.profile, full == false))
	end
end

-- The live profile (nil until loaded). Callers change it, then call DataService.changed(player).
function DataService.get(player: Player): { [string]: any }?
	local session = sessions[player]
	if not session then
		return nil
	end
	ProfileSchema.rollDay(session.profile, os.time())
	return session.profile
end

function DataService.waitFor(player: Player): { [string]: any }?
	if sessions[player] then
		return DataService.get(player)
	end
	if player.Parent ~= Players then
		return nil
	end
	local list = waiting[player] or {}
	waiting[player] = list
	table.insert(list, coroutine.running())
	coroutine.yield()
	return DataService.get(player)
end

-- Tell the client its profile changed (one send per frame). walletOnly: only Credits, Dust or Renown moved,
-- so the stash is not sent again.
function DataService.changed(player: Player, walletOnly: boolean?)
	local session = sessions[player]
	if not session then
		return
	end
	if not walletOnly then
		session.fullQueued = true
	end
	if session.sendQueued then
		return
	end
	session.sendQueued = true
	task.defer(function()
		session.sendQueued = false
		local full = session.fullQueued
		session.fullQueued = false
		sendView(player, full)
	end)
end

function DataService.isSaving(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.canSave
end

-- A loaded player whose leave has not run yet: HeroService keeps their hero until Left, so the leave-save
-- reads it whatever order Roblox runs the PlayerRemoving handlers in
function DataService.holds(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not session.leaving
end

local function resume(player: Player)
	local list = waiting[player]
	waiting[player] = nil
	if list then
		for _, thread in list do
			task.spawn(thread)
		end
	end
end

local function newSession(profile: any, canSave: boolean): Session
	return {
		profile = profile,
		canSave = canSave,
		saving = false,
		sendQueued = false,
		fullQueued = false,
		soonQueued = false,
		released = false,
		leaving = false,
		playClock = os.clock(),
		lastSave = os.clock(),
	}
end

local function onPlayerAdded(player: Player)
	local profile: { [string]: any }? = nil
	local canSave = true
	if memoryMode then
		profile = ProfileSchema.load(ProfileSchema.deepCopy(memoryProfiles[player.UserId]))
	else
		local reason
		profile, reason = loadFromStore(player)
		if reason == "left" then
			resume(player)
			return
		elseif reason == "locked" then
			player:Kick("Your hero is still saving from your last server. Please rejoin in a moment!")
			resume(player)
			return
		elseif profile == nil then
			profile = ProfileSchema.default()
			canSave = false
			Net.fire("Toast", player, { id = "saveDown" })
		end
	end
	if player.Parent ~= Players then
		if not memoryMode and canSave then
			sessions[player] = newSession(profile, true)
			DataService.save(player, true)
			sessions[player] = nil
		end
		resume(player)
		return
	end
	local session = newSession(profile, canSave)
	sessions[player] = session
	ProfileSchema.rollDay(session.profile, os.time())
	resume(player)
	DataService.Loaded:Fire(player, session.profile)
	sendView(player)
end

local function onPlayerRemoving(player: Player, reason: Enum.PlayerExitReason?)
	local session = sessions[player]
	if session then
		session.leaving = true
		local ok, err = pcall(DataService.Leaving.Fire, DataService.Leaving, player, session.profile, reason)
		if not ok then
			warn("[DataService] leaving handler: " .. tostring(err))
		end
		-- the hooks read the live hero now, before Left lets HeroService remove it; then the write
		if not session.released then
			runHooks(player, session)
		end
		local okLeft, errLeft = pcall(DataService.Left.Fire, DataService.Left, player)
		if not okLeft then
			warn("[DataService] left handler: " .. tostring(errLeft))
		end
		write(player, session, true)
		sessions[player] = nil
	end
	resume(player)
end

-- Studio: start over as a first-time player
function DataService.resetProfile(player: Player): { [string]: any }?
	local session = sessions[player]
	if not session then
		return nil
	end
	local fresh = ProfileSchema.default()
	for key in session.profile do
		session.profile[key] = nil
	end
	for key, value in fresh do
		session.profile[key] = value
	end
	DataService.changed(player)
	return session.profile
end

function DataService.init()
	if game.PlaceId == 0 then
		memoryMode = true
	else
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(Config.Data.storeName)
		end)
		if ok then
			store = result
			if RunService:IsStudio() then
				-- Studio needs "Enable Studio Access to API Services"; without it every call errors
				local probeOk = pcall(function()
					(store :: DataStore):GetAsync("__probe")
				end)
				memoryMode = not probeOk
			end
		else
			memoryMode = true
		end
	end
	if memoryMode then
		warn("[DataService] DataStores unavailable here: profiles are kept in memory for this session only")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Data.autosave)
			for player in sessions do
				task.spawn(DataService.save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				DataService.save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + Config.Data.closeDeadline
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
