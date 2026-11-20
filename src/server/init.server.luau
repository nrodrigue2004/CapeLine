-- Capeline server boot (spec: Server lifecycle and Services). Order matters: the live balance before any
-- service is required (WP8, BalanceService), then the city first (the drone AI
-- reads its heights), then remotes, heroes, movement checks, enemies, combat, abilities, economy, gear and
-- perks, safehouses and beacons, destruction (buildings, vehicles, citizens), world activity (sites,
-- incidents, contracts, events, the world boss, the clock), the story (choices and rewards, the opening,
-- mission pockets, side quests), PvP and safety (the flag, Fame, strikes and reports, Downed and defeats),
-- the creator, HQ and shops (M9), settings and squads (M10), analytics (M12), then saves (a loaded profile fires into all of those), and the Studio-only tools.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Studio only: copy every server error to ReplicatedStorage.ServerErrors, so the loading screen can show it
-- on screen (no digging through the Output window). Connected first, before any require can fail.
if RunService:IsStudio() then
	local log = Instance.new("StringValue")
	log.Name = "ServerErrors"
	log.Parent = ReplicatedStorage
	game:GetService("ScriptContext").Error:Connect(function(message, trace)
		log.Value = string.sub(log.Value .. message .. "\n" .. trace .. "\n", -3000)
	end)
end

local Config = require(ReplicatedStorage:WaitForChild("Config"))
-- WP8: live tuning first, before any other service is required, so every module reads the tuned numbers
-- from its first line (Balance_v<N>; any trouble or no answer in Config.Balance.timeout s runs the bundled
-- Config). Never throws.
local BalanceService = require(script:WaitForChild("Services"):WaitForChild("BalanceService"))
BalanceService.load()
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Services = script:WaitForChild("Services")
local PerfMonitor = require(Services.PerfMonitor)
local CityBuilder = require(Services.CityBuilder)
local HeroService = require(Services.HeroService)
local HeroBody = require(Services.HeroBody)
local MoveGuard = require(Services.MoveGuard)
local EnemyService = require(Services.EnemyService)
local CombatService = require(Services.CombatService)
local BlockService = require(Services.BlockService)
local ThrowService = require(Services.ThrowService)
local MoveActService = require(Services.MoveActService)
local AbilityService = require(Services.AbilityService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local GearService = require(Services.GearService)
local PerkService = require(Services.PerkService)
local SafehouseService = require(Services.SafehouseService)
local BeaconService = require(Services.BeaconService)
local BuildingService = require(Services.BuildingService)
local CraterService = require(Services.CraterService)
local VehicleService = require(Services.VehicleService)
local CitizenService = require(Services.CitizenService)
local NpcLookService = require(Services.NpcLookService)
local CatalogLookService = require(Services.CatalogLookService)
local AvatarService = require(Services.AvatarService)
local SiteKit = require(Services.SiteKit)
local IncidentService = require(Services.IncidentService)
local ContractService = require(Services.ContractService)
local EventService = require(Services.EventService)
local BossService = require(Services.BossService)
local UnderwaterService = require(Services.UnderwaterService)
local ClockService = require(Services.ClockService)
local StoryService = require(Services.StoryService)
local OpeningService = require(Services.OpeningService)
local MissionService = require(Services.MissionService)
local CinemaService = require(Services.CinemaService) -- lore step 7: the seen set
local NewsService = require(Services.NewsService) -- lore step 7: the in-city news
local TaskForceService = require(Services.TaskForceService)
local NemesisService = require(Services.NemesisService)
local MentorService = require(Services.MentorService)
local BadgeService = require(Services.BadgeService)
local CollectService = require(Services.CollectService)
local LoreService = require(Services.LoreService)
local RoguesService = require(Services.RoguesService) -- the Rogues File (the Journal's ROGUES tab)
local ContestService = require(Services.ContestService)
local PassService = require(Services.PassService)
local TravelStyleService = require(Services.TravelStyleService)
local SideQuestService = require(Services.SideQuestService)
local FlagService = require(Services.FlagService)
local ImpactService = require(Services.ImpactService)
local FameService = require(Services.FameService)
local GuardService = require(Services.GuardService)
local DeathService = require(Services.DeathService)
local CreatorService = require(Services.CreatorService)
local HqService = require(Services.HqService)
local VisitService = require(Services.VisitService) -- WP12: visit a friend's HQ
local ShopService = require(Services.ShopService)
local RepService = require(Services.RepService) -- lore step 12: the city remembers
local PurchaseService = require(Services.PurchaseService)
local SettingsService = require(Services.SettingsService)
local SquadService = require(Services.SquadService)
local WeaponService = require(Services.WeaponService)
local DailyService = require(Services.DailyService) -- WP1: the daily login streak and daily quests
local PromoService = require(Services.PromoService) -- WP10: the group-join piece and creator codes
local Analytics = require(Services.Analytics)
local AnalyticsHooks = require(Services.AnalyticsHooks)
local FavoriteService = require(Services.FavoriteService) -- WP4: the favorite prompt, once per account
local BoardService = require(Services.BoardService) -- WP2: the weekly boards
local LoadBots = require(Services.LoadBots)
local DevService = require(Services.DevService)

print(string.format("[Capeline] boot, balance %s, build %s", BalanceService.tag(), Config.Version.build))
local t0 = os.clock()
-- Each step runs on its own: one failing service is reported (in Studio, on screen) and the rest still
-- start, so a single bug never leaves an empty world
local function boot(name: string, fn: (...any) -> ...any, ...: any)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		local text = string.format("[Capeline] %s failed to start: %s", name, tostring(err))
		warn(text)
		local log = ReplicatedStorage:FindFirstChild("ServerErrors") :: StringValue?
		if log then
			log.Value = string.sub(log.Value .. text .. "\n", -3000)
		end
	end
end

boot("CityBuilder", CityBuilder.build)
Net.initServer()
boot("PerfMonitor", PerfMonitor.init)
boot("HeroService", HeroService.init)
boot("HeroBody", HeroBody.init) -- before any character loads
boot("MoveGuard", MoveGuard.init)
boot("EnemyService", EnemyService.init, CityBuilder.heightAt)
boot("CombatService", CombatService.init)
boot("BlockService", BlockService.init) -- H1: block, breaker, interrupt
boot("AbilityService", AbilityService.init)
boot("EconomyService", EconomyService.init)
boot("GearService", GearService.init)
boot("PerkService", PerkService.init)
boot("SafehouseService", SafehouseService.init)
boot("BeaconService", BeaconService.init)
boot("BuildingService", BuildingService.init)
boot("CraterService", CraterService.init) -- fix-destroy: ground craters (terrain dug, part ground drawn)
boot("VehicleService", VehicleService.init)
boot("ThrowService", ThrowService.init) -- H3: pick up and throw (after the city and its vehicles)
boot("MoveActService", MoveActService.init) -- the 20 mobility moves (nate 2026-11-20)
boot("CitizenService", CitizenService.init)
boot("NpcLookService", NpcLookService.init) -- the robots' Roblox hair
boot("CatalogLookService", function()
	CatalogLookService.init() -- the heroes' Roblox catalog hair and facial hair
	CatalogLookService.Loaded:Connect(function()
		for _, player in game:GetService("Players"):GetPlayers() do
			pcall(GearService.refresh, player) -- every look rebuilds with its catalog items in
		end
	end)
end)
boot("AvatarService", AvatarService.init) -- heroes wear the player's own avatar plus hero gear
boot("SiteKit", SiteKit.init)
boot("IncidentService", IncidentService.init)
boot("ContractService", ContractService.init)
boot("EventService", EventService.init)
boot("BossService", BossService.init)
boot("UnderwaterService", UnderwaterService.init)
boot("ClockService", ClockService.init)
boot("StoryService", StoryService.init)
boot("OpeningService", OpeningService.init)
boot("MissionService", MissionService.init)
boot("CinemaService", CinemaService.init)
boot("NewsService", NewsService.init)
boot("TaskForceService", TaskForceService.init) -- H4: the Task Force board and quick join
boot("NemesisService", NemesisService.init) -- H5: your nemesis
boot("MentorService", MentorService.init) -- H6: mentors
boot("BadgeService", BadgeService.init) -- H7: badges, titles, accolades
boot("CollectService", CollectService.init) -- H7: collections
boot("LoreService", LoreService.init) -- side-content: lore pages at the landmarks
boot("RoguesService", RoguesService.init) -- the Rogues File: pages from defeats, gold boss pages, milestones
boot("ContestService", ContestService.init) -- H7: costume contests
boot("PassService", PassService.init) -- H8: the Hero Pass and the weekly episode
boot("TravelStyleService", TravelStyleService.init) -- H8: travel power styles
boot("SideQuestService", SideQuestService.init)
boot("FlagService", FlagService.init)
boot("ImpactService", ImpactService.init) -- 2026-11-19: rams and throws break walls (after Building and Flag)
boot("FameService", FameService.init)
boot("GuardService", GuardService.init)
boot("DeathService", DeathService.init)
boot("CreatorService", CreatorService.init)
boot("HqService", HqService.init)
boot("VisitService", VisitService.init) -- WP12: after HqService (it draws the copies) and GuardService
boot("ShopService", ShopService.init)
boot("RepService", RepService.init) -- lore step 12: reputation tiers, side rewards, the city's reactions
boot("PurchaseService", PurchaseService.init)
boot("SettingsService", SettingsService.init)
boot("SquadService", SquadService.init)
boot("WeaponService", WeaponService.init)
boot("DailyService", DailyService.init) -- WP1: before DataService (a loaded profile counts the day)
boot("PromoService", PromoService.init) -- WP10: before DataService (a loaded profile checks the group)
boot("Analytics", Analytics.init)
boot("AnalyticsHooks", AnalyticsHooks.init)
boot("BalanceService", BalanceService.init) -- WP8: balance_live once per session (after Analytics)
boot("FavoriteService", FavoriteService.init)
boot("BoardService", BoardService.init) -- WP2: the weekly boards (before DataService: the claim on join)
boot("DataService", DataService.init) -- last of the game services: profile loads fire into the handlers above
boot("LoadBots", LoadBots.init)
boot("DevService", DevService.init)
-- Characters load only once the world and every service are up (the place starts with CharacterAutoLoads
-- off), so nobody spawns over an empty world and falls
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(pcall, player.LoadCharacter, player)
	end
end
print(
	string.format(
		"[Capeline] hub ready in %.2f s (%d parts; the outskirts build in the background)",
		os.clock() - t0,
		CityBuilder.builtParts
	)
)
