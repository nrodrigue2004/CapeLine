-- Capeline server boot (spec: Server lifecycle and Services). Order matters: the city first (the drone AI
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
local AbilityService = require(Services.AbilityService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local GearService = require(Services.GearService)
local PerkService = require(Services.PerkService)
local SafehouseService = require(Services.SafehouseService)
local BeaconService = require(Services.BeaconService)
local BuildingService = require(Services.BuildingService)
local VehicleService = require(Services.VehicleService)
local CitizenService = require(Services.CitizenService)
local NpcLookService = require(Services.NpcLookService)
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
local QuestService = require(Services.QuestService)
local FlagService = require(Services.FlagService)
local FameService = require(Services.FameService)
local GuardService = require(Services.GuardService)
local DeathService = require(Services.DeathService)
local CreatorService = require(Services.CreatorService)
local HqService = require(Services.HqService)
local ShopService = require(Services.ShopService)
local PurchaseService = require(Services.PurchaseService)
local SettingsService = require(Services.SettingsService)
local SquadService = require(Services.SquadService)
local WeaponService = require(Services.WeaponService)
local Analytics = require(Services.Analytics)
local AnalyticsHooks = require(Services.AnalyticsHooks)
local LoadBots = require(Services.LoadBots)
local DevService = require(Services.DevService)

print(string.format("[Capeline] boot, balance %d, build %s", Config.Version.balance, Config.Version.build))
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
boot("AbilityService", AbilityService.init)
boot("EconomyService", EconomyService.init)
boot("GearService", GearService.init)
boot("PerkService", PerkService.init)
boot("SafehouseService", SafehouseService.init)
boot("BeaconService", BeaconService.init)
boot("BuildingService", BuildingService.init)
boot("VehicleService", VehicleService.init)
boot("CitizenService", CitizenService.init)
boot("NpcLookService", NpcLookService.init) -- the robots' Roblox hair
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
boot("QuestService", QuestService.init)
boot("FlagService", FlagService.init)
boot("FameService", FameService.init)
boot("GuardService", GuardService.init)
boot("DeathService", DeathService.init)
boot("CreatorService", CreatorService.init)
boot("HqService", HqService.init)
boot("ShopService", ShopService.init)
boot("PurchaseService", PurchaseService.init)
boot("SettingsService", SettingsService.init)
boot("SquadService", SquadService.init)
boot("WeaponService", WeaponService.init)
boot("Analytics", Analytics.init)
boot("AnalyticsHooks", AnalyticsHooks.init)
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
