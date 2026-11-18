-- Analytics: the spec's custom events and funnels through Roblox's AnalyticsService (spec: Analytics and
-- KPIs), so the Creator Dashboard shows them with no outside service (ported from Ragdoll Rides). Every
-- event is checked against AnalyticsSchema first: unknown names are dropped, fields are short codes or
-- numbers, never names or text a player typed. Roblox hashes user ids and batches the sends.
-- * event(player, name, value?, fields?): one custom event (fields go to CustomField01 to 03).
-- * step(player, funnel, stepName): a funnel step. "Opening" is the onboarding funnel: each step counts
--   once per account, in order (the furthest step is kept in the save). The others start a new funnel
--   session at their first step.
-- * Facts only the device knows (its platform, perf samples, the shop and item views, photos) arrive on
--   Telemetry; session_device waits up to 20 s for the device's hello.
-- * funnelSink: where the studio-wide FunnelKit sends (AnalyticsHooks runs it): the Progress and Returns
--   funnels and session_start, stage_reached, session_end and first_session_end. These always get a slot in
--   the per-minute budget, and print as [Funnel] lines in Studio (events only send from published games).
-- Only DataService is required here, so any service can call Analytics (AnalyticsHooks wires the signals).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AnalyticsSchema = require(Shared:WaitForChild("AnalyticsSchema"))
local FunnelKit = require(Shared:WaitForChild("FunnelKit"))
local FunnelDef = require(Shared:WaitForChild("FunnelDef"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local DataService = require(script.Parent.DataService)

local Analytics = {}

Analytics.logToOutput = RunService:IsStudio() -- Studio playtests print each event to the Output
Analytics.count = 0 -- events sent this server (Dev panel)
Analytics.Photo = Signal.new() -- (player) the device took a Photo Mode shot (the Photo recon contract)
Analytics.dropped = 0 -- events skipped by the per-minute budget (Dev panel)
local budget = AnalyticsSchema.newBudget() -- this minute's sends (Shared.AnalyticsSchema.take)

local service: AnalyticsService? = nil
local sessions: { [Player]: { [string]: string } } = {}
local joinedAt: { [Player]: number } = {}
local starting: { [Player]: { kind: string, side: (Player) -> string } } = {} -- waiting for the device hello
local devices: { [Player]: string } = {}

local KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

local function analytics(): AnalyticsService?
	if service == nil then
		local ok, s = pcall(function()
			return game:GetService("AnalyticsService")
		end)
		service = if ok then s else nil
	end
	return service
end

-- The per-minute budget: true takes a slot. Busy (low) sends give way first, so the funnels and rare
-- events always get through.
-- (the rule is Shared.AnalyticsSchema.take, so Lune tests it)
local function takeBudget(low: boolean): boolean
	local ok = AnalyticsSchema.take(budget, Config.Analytics.budget, os.clock(), #Players:GetPlayers(), low)
	Analytics.dropped = budget.dropped
	return ok
end

-- One custom event. Never throws.
function Analytics.event(player: Player, name: string, value: number?, fields: { any }?)
	if player.Parent ~= Players then
		return
	end
	if not takeBudget(Config.Analytics.lowPriority[name] == true) then
		return
	end
	local ok, clean = AnalyticsSchema.check(name, fields)
	if not ok then
		if RunService:IsStudio() then
			warn("[Analytics] refused event " .. tostring(name))
		end
		return
	end
	local custom: { [string]: string } = {}
	for i, v in clean do
		custom[KEYS[i]] = v
	end
	Analytics.count += 1
	if Analytics.logToOutput then
		print(string.format("[Analytics] %s %s %s", name, tostring(value or 1), table.concat(clean, " ")))
	end
	local s = analytics()
	if s then
		pcall(function()
			(s :: any):LogCustomEvent(player, name, value or 1, custom) -- newer than the type definitions
		end)
	end
end

-- A funnel step (Opening counts once per account, in order)
function Analytics.step(player: Player, funnel: string, stepName: string)
	local step = AnalyticsSchema.stepOf(funnel, stepName)
	if not step or player.Parent ~= Players then
		return
	end
	local s = analytics()
	if funnel == "Opening" then
		local profile = DataService.get(player)
		if not profile or step <= profile.analytics.onboard then
			return
		end
		profile.analytics.onboard = step
		if s then
			pcall(function()
				(s :: AnalyticsService):LogOnboardingFunnelStepEvent(player, step, stepName)
			end)
		end
		return
	end
	local mine = sessions[player]
	if not mine then
		mine = {}
		sessions[player] = mine
	end
	if step == 1 or not mine[funnel] then
		mine[funnel] = HttpService:GenerateGUID(false)
	end
	if s then
		pcall(function()
			(s :: AnalyticsService):LogFunnelStepEvent(player, funnel, mine[funnel], step, stepName)
		end)
	end
end

-- A once-per-account step of a lifetime funnel (FunnelDef.lifetime; WP4: the Hero MMO firsts), on the
-- lifetime session id like the Progress funnel. It takes a budget slot like any event; the bit is saved
-- only once it went out. Returns false when the budget is full (AnalyticsHooks tries again later), true
-- when it was sent, already logged or not a step.
function Analytics.first(player: Player, funnel: string, stepName: string): boolean
	if player.Parent ~= Players or not FunnelDef.lifetime[funnel] then
		return true
	end
	local profile = DataService.get(player)
	if not profile then
		return false -- still loading: try again
	end
	local step, mask = AnalyticsSchema.first(profile.analytics.mmo, funnel, stepName)
	if not step then
		return true
	end
	if not takeBudget(false) then
		return false
	end
	profile.analytics.mmo = mask
	Analytics.count += 1
	if Analytics.logToOutput then
		print(string.format("[Funnel] %s step %d %s", funnel, step, stepName))
	end
	local s = analytics()
	if s then
		pcall(function()
			(s :: AnalyticsService):LogFunnelStepEvent(player, funnel, FunnelKit.LIFE_SESSION, step, stepName)
		end)
	end
	return true
end

-- The studio-wide FunnelKit's events (AnalyticsSchema has them, the same in every game)
Analytics.FUNNEL_EVENTS = { "session_start", "stage_reached", "session_end", "first_session_end" }

Analytics.funnelSink = {
	funnel = function(player: Player, funnel: string, sessionId: string, step: number, stepName: string)
		if player.Parent ~= Players then
			return
		end
		if Analytics.logToOutput then
			print(string.format("[Funnel] %s step %d %s", funnel, step, stepName))
		end
		local s = analytics()
		if s then
			pcall(function()
				(s :: AnalyticsService):LogFunnelStepEvent(player, funnel, sessionId, step, stepName)
			end)
		end
	end,
	custom = function(player: Player, name: string, value: number, fields: { string })
		if player.Parent ~= Players or not table.find(Analytics.FUNNEL_EVENTS, name) then
			return
		end
		budget.n += 1 -- top priority: counts against the budget but is never dropped
		Analytics.count += 1
		local custom: { [string]: string } = {}
		for i, v in fields do
			if KEYS[i] then
				custom[KEYS[i]] = v
			end
		end
		if Analytics.logToOutput then
			print(string.format("[Funnel] %s %s %s", name, tostring(value), table.concat(fields, " | ")))
		end
		local s = analytics()
		if s then
			pcall(function()
				(s :: any):LogCustomEvent(player, name, value, custom)
			end)
		end
	end,
}

-- The device class a player's device said it is (its Telemetry hello): "phone", "tablet", "pc" or "console",
-- nil before the hello (EnemyService caps Enemy.Delta by it)
function Analytics.device(player: Player): string?
	return devices[player]
end

-- Seconds since this player joined
function Analytics.since(player: Player): number
	return math.floor(os.clock() - (joinedAt[player] or os.clock()))
end

local DEVICES = { "phone", "tablet", "pc", "console" }

local function startNow(player: Player)
	local s = starting[player]
	if not s then
		return
	end
	starting[player] = nil
	local hero = s.side(player)
	local profile = DataService.get(player)
	local level = 1
	if profile then
		local c = profile.characters[profile.active]
		level = if c then c.level or 1 else 1
	end
	Analytics.event(player, "session_device", level, { devices[player] or "unknown", s.kind, hero })
end

-- session_device waits for the device's hello (the platform only the device knows), at most 20 s
function Analytics.session(player: Player, kind: string, side: (Player) -> string)
	starting[player] = { kind = kind, side = side }
	if devices[player] then
		startNow(player)
		return
	end
	task.delay(Config.Analytics.helloWait, startNow, player)
end

-- The device's facts (Telemetry remote): kind, value, a, b
local PRESETS = { "auto", "low", "medium", "high" }
local BACKDROPS = { "none", "comic", "speed", "sunset", "noir", "neon" }
local function onTelemetry(player: Player, kind: number, value: number, a: number, b: number)
	if kind == 1 then
		-- perf_sample: value median fps, a device, b preset; p5 fps rides in the value's thousands
		local median = value % 1000
		local p5 = value // 1000
		Analytics.event(player, "perf_sample", median, { DEVICES[a] or "pc", PRESETS[b + 1] or "auto", p5 })
	elseif kind == 2 or kind == 3 then
		-- device-sent funnel steps (up to one a second a player) take a budget slot like any event, so a
		-- device can never send past the per-minute cap
		if takeBudget(false) then
			Analytics.step(player, "Purchase", if kind == 2 then "shop_open" else "shop_view_item")
		end
	elseif kind == 4 then
		Analytics.event(player, "photo", 1, { BACKDROPS[a] or "none" })
		Analytics.Photo:Fire(player)
	elseif kind == 5 then
		-- the hello: which kind of device (once a session)
		if not devices[player] then
			devices[player] = DEVICES[a] or "pc"
			startNow(player)
		end
	end
end

function Analytics.init()
	Net.on("Telemetry", onTelemetry)
	Players.PlayerAdded:Connect(function(p)
		joinedAt[p] = os.clock()
	end)
	for _, p in Players:GetPlayers() do
		joinedAt[p] = joinedAt[p] or os.clock()
	end
	Players.PlayerRemoving:Connect(function(p)
		task.defer(function()
			sessions[p] = nil
			joinedAt[p] = nil
			starting[p] = nil
			devices[p] = nil
		end)
	end)
end

return Analytics
