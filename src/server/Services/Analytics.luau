-- Analytics: the spec's custom events and funnels through Roblox's AnalyticsService (spec: Analytics and
-- KPIs), so the Creator Dashboard shows them with no outside service (ported from Ragdoll Rides). Every
-- event is checked against AnalyticsSchema first: unknown names are dropped, fields are short codes or
-- numbers, never names or text a player typed. Roblox hashes user ids and batches the sends.
-- * event(player, name, value?, fields?): one custom event (fields go to CustomField01 to 03).
-- * step(player, funnel, stepName): a funnel step, counted as AnalyticsSchema.KINDS says (Audit 2026-11-18):
--   Opening (Roblox's onboarding funnel) and the Combat and Story ladders once per account and in order,
--   kept in the save; PvP and Purchase once per funnel session and in order, a session opened by step 1. A
--   step reached before the one ahead of it waits and goes out as soon as the gap fills; every step takes a
--   budget slot and one the budget refused is sent by flush() a few seconds later.
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
local budget = AnalyticsSchema.newBudget() -- the last 60 s of sends (Shared.AnalyticsSchema.take)

local service: AnalyticsService? = nil
local sessions: { [Player]: { [string]: AnalyticsSchema.Gate } } = {} -- the open recurring funnel sessions
local paced: { [Player]: { [number]: number } } = {} -- the last device fact kept, per kind (Telemetry)
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

-- The studio-wide FunnelKit's sends: never dropped, but counted in the same window
local function forceBudget()
	AnalyticsSchema.force(budget, Config.Analytics.budget, os.clock(), #Players:GetPlayers())
end

-- This session's save did not load (DataService could not read it): the profile is a blank default, so
-- once-per-account facts would count again (Audit 2026-11-18). Before the load nothing is known yet.
local function unsaved(player: Player): boolean
	return DataService.get(player) ~= nil and not DataService.isSaving(player)
end
Analytics.unsaved = unsaved

-- One custom event. Never throws. A refused or unsaved event takes no budget slot. Returns "sent", "full"
-- (the per-minute budget had no room: a caller that must not lose it may try again later) or "refused" (gone
-- for good: a player who left, a bad event or a save that did not load); callers may ignore it.
function Analytics.event(player: Player, name: string, value: number?, fields: { any }?): string
	if player.Parent ~= Players then
		return "refused"
	end
	local ok, clean = AnalyticsSchema.check(name, fields)
	if not ok then
		if RunService:IsStudio() then
			warn("[Analytics] refused event " .. tostring(name))
		end
		return "refused"
	end
	if not AnalyticsSchema.NOSAVE[name] and unsaved(player) then
		return "refused"
	end
	if not takeBudget(Config.Analytics.lowPriority[name] == true) then
		return "full"
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
	return "sent"
end

local function sendStep(player: Player, funnel: string, sessionId: string, step: number, stepName: string)
	Analytics.count += 1
	if Analytics.logToOutput then
		print(string.format("[Funnel] %s step %d %s", funnel, step, stepName))
	end
	local s = analytics()
	if s then
		pcall(function()
			if funnel == "Opening" then
				(s :: AnalyticsService):LogOnboardingFunnelStepEvent(player, step, stepName)
			else
				(s :: AnalyticsService):LogFunnelStepEvent(player, funnel, sessionId, step, stepName)
			end
		end)
	end
end

-- Send a gate's due steps in order while the budget has room (the rest wait for flush). True when any went.
local function drain(player: Player, funnel: string, g: AnalyticsSchema.Gate, sessionId: string): boolean
	local any = false
	while true do
		local step, stepName = AnalyticsSchema.due(g, funnel)
		if not step or not takeBudget(false) then
			return any
		end
		AnalyticsSchema.sent(g)
		any = true
		sendStep(player, funnel, sessionId, step, stepName :: string)
	end
end

-- An onboarding or ladder funnel: its gate lives in profile.analytics (AnalyticsSchema.SAVE)
local function ladder(player: Player, funnel: string, stepName: string?)
	local keys = AnalyticsSchema.SAVE[funnel]
	local profile = DataService.get(player)
	if not keys or not profile or not DataService.isSaving(player) then
		return -- loading, or a blank profile that never saves: logging would count the account again
	end
	local an = profile.analytics
	local at = stepName and AnalyticsSchema.stepOf(funnel, stepName)
	if at and at <= an[keys[1]] then
		return -- sent long ago (every cast asks for skill_cast): nothing to do
	end
	local g = AnalyticsSchema.newGate(an[keys[1]], an[keys[2]])
	local moved = if stepName then AnalyticsSchema.reach(g, funnel, stepName) else false
	if drain(player, funnel, g, FunnelKit.LIFE_SESSION) or moved then
		an[keys[1]], an[keys[2]] = g.sent, g.reach
		DataService.saveSoon(player) -- a step sent is kept, so a crash and a rejoin never send it again
	end
end

-- A funnel step (AnalyticsSchema.KINDS: once per account or per funnel session, always in order)
function Analytics.step(player: Player, funnel: string, stepName: string)
	local kind = AnalyticsSchema.KINDS[funnel]
	if not kind or not AnalyticsSchema.stepOf(funnel, stepName) or player.Parent ~= Players then
		return
	end
	if kind == "any" then
		Analytics.first(player, funnel, stepName)
	elseif kind == "session" then
		local mine = sessions[player]
		if not mine then
			mine = {}
			sessions[player] = mine
		end
		local g, opened = AnalyticsSchema.sessionGate(mine, funnel, stepName)
		if not g then
			return -- no session open: a step with no start is never logged
		end
		local gate = g :: AnalyticsSchema.Gate
		if opened then
			gate.id = HttpService:GenerateGUID(false)
		end
		if AnalyticsSchema.reach(gate, funnel, stepName) then
			drain(player, funnel, gate, gate.id or FunnelKit.LIFE_SESSION)
		end
	else
		ladder(player, funnel, stepName)
	end
end

-- End a recurring funnel's session (PvP: the flag went off); later steps need a new step 1
function Analytics.close(player: Player, funnel: string)
	local mine = sessions[player]
	if mine then
		mine[funnel] = nil
	end
end

-- Send any steps the budget held back (AnalyticsHooks calls it every few seconds)
function Analytics.flush(player: Player)
	if player.Parent ~= Players then
		return
	end
	for funnel in AnalyticsSchema.SAVE do
		ladder(player, funnel, nil)
	end
	for funnel, g in sessions[player] or {} do
		drain(player, funnel, g, g.id or FunnelKit.LIFE_SESSION)
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
	if not DataService.isSaving(player) then
		return true -- a blank profile that never saves (its bits are all 0): never sent, never retried
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
		forceBudget() -- top priority: counts in the window but is never dropped
		Analytics.count += 1
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
		forceBudget() -- top priority: counts in the window but is never dropped
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
	-- each kind is paced per player (Config.Analytics.devicePace), so a device can never spend the
	-- server's budget faster than an honest one reports
	local mine = paced[player]
	if not mine then
		mine = {}
		paced[player] = mine
	end
	local keep = AnalyticsSchema.pace(mine, Config.Analytics.devicePace, kind, os.clock())
	if kind == 1 and keep then
		-- perf_sample: value median fps, a device, b preset; p5 fps rides in the value's thousands (to 5s)
		local median = value % 1000
		local p5 = AnalyticsSchema.fps(value // 1000)
		Analytics.event(player, "perf_sample", median, { DEVICES[a] or "pc", PRESETS[b + 1] or "auto", p5 })
	elseif (kind == 2 or kind == 3) and keep then
		-- the Purchase funnel's first two steps (each takes its own budget slot in Analytics.step)
		Analytics.step(player, "Purchase", if kind == 2 then "shop_open" else "shop_view_item")
	elseif kind == 4 then
		if keep then
			Analytics.event(player, "photo", 1, { BACKDROPS[a] or "none" })
		end
		Analytics.Photo:Fire(player) -- the Photo recon contract counts every shot
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
			paced[p] = nil
		end)
	end)
end

return Analytics
