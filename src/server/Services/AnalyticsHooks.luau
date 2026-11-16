-- AnalyticsHooks: turns the game's own signals into the spec's analytics events and funnel steps (spec:
-- Analytics and KPIs), so no service has to know about analytics for these: sessions and the day-1
-- return, level ups, defeats, Downed, the PvP flag and PvP results, story choices, incidents and the
-- world boss. Moments with no signal call Analytics directly from their service (the opening's steps,
-- the creator, contracts, missions, skills, gear, shop, guard, beacons, squads, settings, waits).

local Players = game:GetService("Players")

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local FlagService = require(script.Parent.FlagService)
local DeathService = require(script.Parent.DeathService)
local StoryService = require(script.Parent.StoryService)
local IncidentService = require(script.Parent.IncidentService)
local BossService = require(script.Parent.BossService)

local AnalyticsHooks = {}

local DAY = 86400
local downedAt: { [number]: number } = {} -- hero id -> os.clock when Downed
local pvpHit: { [Player]: boolean } = {} -- first PvP hit logged this session

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
	Analytics.step(player, "Opening", "session_start")
	local age = now - a.firstSeen
	if a.d1 == 0 and age >= DAY and age < 2 * DAY then
		a.d1 = 1
		Analytics.step(player, "Opening", "d1_return")
	end
end

local function leaving(player: Player)
	local hero = HeroService.get(player)
	local state = "idle"
	if hero then
		if hero.downed then
			state = "downed"
		elseif hero.scene then
			state = hero.scene
		elseif BossService.inFight(hero) then
			state = "boss"
		elseif FlagService.inPvpCombat(hero) then
			state = "pvp"
		end
	end
	Analytics.event(player, "leave", Analytics.since(player), { state })
	pvpHit[player] = nil
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

function AnalyticsHooks.init()
	DataService.Loaded:Connect(joined)
	DataService.Leaving:Connect(leaving)
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
		Analytics.event(player, "choice_pick", 1, { id, option })
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
	end)
end

return AnalyticsHooks
