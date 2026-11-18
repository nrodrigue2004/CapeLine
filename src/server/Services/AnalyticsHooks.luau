-- AnalyticsHooks: turns the game's own signals into the spec's analytics events and funnel steps (spec:
-- Analytics and KPIs), so no service has to know about analytics for these: sessions and the day-1
-- return, level ups, defeats, Downed, the PvP flag and PvP results, story choices, incidents and the
-- world boss. Moments with no signal call Analytics directly from their service (the opening's steps,
-- the creator, contracts, missions, skills, gear, shop, guard, beacons, squads, settings, waits).
-- It also runs the studio-wide FunnelKit (Shared.FunnelKit with Capeline's ladder in Shared.FunnelDef): the
-- Progress funnel (the furthest stage), the Returns funnel (sessions 1, 2, 3, 5, 10, 20) and session_start,
-- stage_reached, session_end and first_session_end with the stage, the activity at quit and the reason.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FunnelKit = require(Shared:WaitForChild("FunnelKit"))
local FunnelDef = require(Shared:WaitForChild("FunnelDef"))

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local FlagService = require(script.Parent.FlagService)
local DeathService = require(script.Parent.DeathService)
local StoryService = require(script.Parent.StoryService)
local IncidentService = require(script.Parent.IncidentService)
local BossService = require(script.Parent.BossService)
local BlockService = require(script.Parent.BlockService)
local ThrowService = require(script.Parent.ThrowService)
local NemesisService = require(script.Parent.NemesisService)
local TaskForceService = require(script.Parent.TaskForceService)
local BadgeService = require(script.Parent.BadgeService)
local PurchaseService = require(script.Parent.PurchaseService)

local AnalyticsHooks = {}

local DAY = 86400
local downedAt: { [number]: number } = {} -- hero id -> os.clock when Downed
local pvpHit: { [Player]: boolean } = {} -- first PvP hit logged this session
local idledAt: { [Player]: number } = {} -- os.clock of the last Player.Idled (Roblox: 2 minutes idle)

local IDLE_WINDOW = 150 -- a quit this soon after Player.Idled counts as "idle"
local CHECK_EVERY = 5 -- seconds between funnel stage checks

AnalyticsHooks.funnels = FunnelKit.new(FunnelDef, Analytics.funnelSink, os.time)

local function sideOf(player: Player): string
	local hero = HeroService.get(player)
	return if hero then hero.side else "none"
end

-- The session start: the first step of the Opening funnel, and the day-1 return check
local function joined(player: Player, profile: any)
	local a = profile.analytics
	local now = os.time()
	local new = a.firstSeen == 0
	if new then
		a.firstSeen = now
	end
	Analytics.session(player, if new then "new" else "returning", sideOf)
	profile.funnel = FunnelKit.fill(profile.funnel)
	AnalyticsHooks.funnels:join(player, profile.funnel, profile)
	Analytics.step(player, "Opening", "session_start")
	local age = now - a.firstSeen
	if a.d1 == 0 and age >= DAY and age < 2 * DAY then
		a.d1 = 1
		Analytics.step(player, "Opening", "d1_return")
	end
end

-- What the hero is doing now (the funnels' activity: session_end says what a player quit during)
local function activityOf(player: Player): string
	local hero = HeroService.get(player)
	if not hero then
		return "Loading"
	elseif hero.downed then
		return "Downed"
	elseif hero.scene then
		return "Scene " .. tostring(hero.scene)
	elseif BossService.inFight(hero) then
		return "Boss"
	elseif FlagService.inPvpCombat(hero) then
		return "PvP"
	end
	return "City"
end

local QUIT = {
	[Enum.PlayerExitReason.CreatorKick.Name] = "kicked",
	[Enum.PlayerExitReason.PlatformKick.Name] = "kicked_roblox",
}

local function leaving(player: Player, _profile: any, reason: Enum.PlayerExitReason?)
	local funnels = AnalyticsHooks.funnels
	funnels:activity(player, activityOf(player))
	local why = if reason then QUIT[reason.Name] else nil
	if not why and idledAt[player] and os.clock() - idledAt[player] <= IDLE_WINDOW then
		why = "idle"
	end
	funnels:leave(player, why or "left")
	pvpHit[player] = nil
	idledAt[player] = nil
end

-- Called by FlagService on every PvP hit: logs the attacker's first one each session
function AnalyticsHooks.pvpHit(attacker: any, target: any)
	local p = attacker.player
	if not p or pvpHit[p] then
		return
	end
	pvpHit[p] = true
	local zone = if FlagService.flag(attacker).crater ~= "out" then "crater" else "city"
	Analytics.event(p, "pvp_hit", 1, { attacker.level, target.level, zone })
	Analytics.step(p, "PvP", "first_pvp_hit")
end

-- WP4 (gap G6): the Hero MMO firsts, a lifetime funnel (AnalyticsSchema.FUNNELS.MMO): each step once per
-- account (the bits in profile.analytics.mmo). A step the minute's budget refused waits here and is tried
-- again with the funnel checks every few seconds, so it is never lost and never sent twice.
local waiting: { [Player]: { [string]: boolean } } = {}

function AnalyticsHooks.first(player: Player?, step: string)
	if not player then
		return
	end
	if not Analytics.first(player, "MMO", step) then
		local mine = waiting[player] or {}
		waiting[player] = mine
		mine[step] = true
	end
end

local function retryFirsts()
	for player, steps in waiting do
		if player.Parent ~= Players then
			waiting[player] = nil
		else
			for step in steps do
				if Analytics.first(player, "MMO", step) then
					steps[step] = nil
				end
			end
			if next(steps) == nil then
				waiting[player] = nil
			end
		end
	end
end

local function wireFirsts()
	BlockService.Outcome:Connect(function(hero: any, outcome: string)
		if outcome == "blocked" or outcome == "perfect" then
			AnalyticsHooks.first(hero.player, "first_block")
		end
	end)
	ThrowService.Thrown:Connect(function(hero: any)
		AnalyticsHooks.first(hero.player, "first_throw")
	end)
	NemesisService.Met:Connect(function(player: Player)
		AnalyticsHooks.first(player, "first_nemesis")
	end)
	TaskForceService.Done:Connect(function(player: Player)
		AnalyticsHooks.first(player, "first_taskforce")
	end)
	BadgeService.Earned:Connect(function(player: Player)
		AnalyticsHooks.first(player, "first_badge")
	end)
	PurchaseService.Landed:Connect(function(player: Player, _key: string, kind: string?)
		if kind == "heroPass" then
			AnalyticsHooks.first(player, "pass_bought")
		end
	end)
end

function AnalyticsHooks.init()
	wireFirsts()
	DataService.Loaded:Connect(joined)
	DataService.Leaving:Connect(leaving)
	-- the funnels: stage checks and the current activity every few seconds, idle quits, server shutdown
	local function watchIdle(player: Player)
		player.Idled:Connect(function()
			idledAt[player] = os.clock()
		end)
	end
	Players.PlayerAdded:Connect(watchIdle)
	for _, p in Players:GetPlayers() do
		watchIdle(p)
	end
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, p in Players:GetPlayers() do
				local profile = DataService.get(p)
				if profile and AnalyticsHooks.funnels:isTracking(p) then
					AnalyticsHooks.funnels:check(p, profile)
					AnalyticsHooks.funnels:activity(p, activityOf(p))
				end
			end
			retryFirsts()
		end
	end)
	game:BindToClose(function()
		AnalyticsHooks.funnels:shutdown()
	end)
	FlagService.pvpHook = AnalyticsHooks.pvpHit

	HeroService.Leveled:Connect(function(hero)
		local p = hero.player
		if not p then
			return
		end
		Analytics.event(p, "level_up", Analytics.since(p), { hero.level, Analytics.since(p) // 60 })
		if hero.level >= 3 then
			Analytics.step(p, "Opening", "level_3")
		end
	end)

	HeroService.Defeated:Connect(function(hero, source)
		local p = hero.player
		if not p then
			return
		end
		local cause = if type(source) == "table" and source.pvp then "pvp" else "pve"
		local at = downedAt[hero.id]
		if at then
			downedAt[hero.id] = nil
			Analytics.event(p, "downed", math.floor(os.clock() - at), { "gave_up" })
		end
		Analytics.event(p, "defeat", 1, { cause, hero.level })
	end)

	DeathService.Downed:Connect(function(hero)
		downedAt[hero.id] = os.clock()
	end)
	DeathService.Revived:Connect(function(hero)
		local at = downedAt[hero.id]
		downedAt[hero.id] = nil
		if hero.player and at then
			Analytics.event(hero.player, "downed", math.floor(os.clock() - at), { "revived" })
		end
	end)

	FlagService.Changed:Connect(function(hero, flagged)
		local p = hero.player
		if not p then
			return
		end
		local zone = if FlagService.flag(hero).crater ~= "out" then "crater" else "city"
		Analytics.event(p, if flagged then "flag_on" else "flag_off", 1, { zone, hero.level })
		Analytics.step(p, "PvP", if flagged then "flag_on" else "flag_off")
	end)

	DeathService.PvpDefeat:Connect(function(loser, winner)
		if winner.player then
			Analytics.event(winner.player, "pvp_win", 1, { winner.level, loser.level, "1" })
			Analytics.step(winner.player, "PvP", "pvp_win")
		end
		if loser.player then
			Analytics.step(loser.player, "PvP", "pvp_loss")
		end
	end)

	StoryService.Picked:Connect(function(player, id, option)
		Analytics.event(player, "choice_pick", 1, { id, option, StoryService.side(player) })
		Analytics.step(player, "Story", "choice_pick")
	end)

	IncidentService.Cleared:Connect(function(inc)
		local n = 0
		for _ in inc.helpers do
			n += 1
		end
		local secs = math.floor(os.clock() - inc.plan.started)
		for heroId in inc.helpers do
			local hero = HeroService.byId(heroId)
			if hero and hero.player then
				Analytics.event(hero.player, "incident_done", secs, { inc.plan.tid, inc.medal or "none", n })
				Analytics.step(hero.player, "Opening", "first_incident")
			end
		end
	end)

	BossService.Joined:Connect(function(hero, bossId, count)
		local p = hero.player
		if p then
			Analytics.event(p, "boss_join", 1, { bossId, hero.level, count })
			Analytics.step(p, "Opening", "first_boss_join")
		end
	end)
	BossService.Rewarded:Connect(function(player, bossId, tier, defeated, contribution)
		Analytics.event(
			player,
			"boss_done",
			contribution or 1,
			{ bossId, tier, if defeated then "win" else "fail" }
		)
		Analytics.step(player, "Opening", "first_boss_done")
	end)

	Players.PlayerRemoving:Connect(function(p)
		pvpHit[p] = nil
		waiting[p] = nil
	end)
end

return AnalyticsHooks
