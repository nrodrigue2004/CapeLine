-- Capeline server boot (spec: Server lifecycle and Services). Order matters: the city first (the drone AI
-- reads its heights), then remotes, heroes, movement checks, enemies, combat, abilities, economy, gear and
-- perks, safehouses and beacons, destruction (buildings, vehicles, citizens), world activity (sites,
-- incidents, contracts, events, the world boss, the clock), the story (choices and rewards, the opening,
-- mission pockets, side quests), PvP and safety (the flag, Fame, strikes and reports, Downed and defeats),
-- the creator, HQ and shops (M9), settings and squads (M10), analytics (M12), then saves (a loaded profile fires into all of those), and the Studio-only tools.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Services = script:WaitForChild("Services")
local PerfMonitor = require(Services.PerfMonitor)
local CityBuilder = require(Services.CityBuilder)
local HeroService = require(Services.HeroService)
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
local SiteKit = require(Services.SiteKit)
local IncidentService = require(Services.IncidentService)
local ContractService = require(Services.ContractService)
local EventService = require(Services.EventService)
local BossService = require(Services.BossService)
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
local Analytics = require(Services.Analytics)
local AnalyticsHooks = require(Services.AnalyticsHooks)
local LoadBots = require(Services.LoadBots)
local DevService = require(Services.DevService)

print(string.format("[Capeline] boot, balance %d, build %s", Config.Version.balance, Config.Version.build))
local t0 = os.clock()
CityBuilder.build()
-- Characters load only once the hub and its spawn pads exist (the place starts with CharacterAutoLoads off),
-- so nobody spawns over an empty world and falls
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(pcall, player.LoadCharacter, player)
	end
end
Net.initServer()
PerfMonitor.init()
HeroService.init()
MoveGuard.init()
EnemyService.init(CityBuilder.heightAt)
CombatService.init()
AbilityService.init()
EconomyService.init()
GearService.init()
PerkService.init()
SafehouseService.init()
BeaconService.init()
BuildingService.init()
VehicleService.init()
CitizenService.init()
SiteKit.init()
IncidentService.init()
ContractService.init()
EventService.init()
BossService.init()
ClockService.init()
StoryService.init()
OpeningService.init()
MissionService.init()
QuestService.init()
FlagService.init()
FameService.init()
GuardService.init()
DeathService.init()
CreatorService.init()
HqService.init()
ShopService.init()
PurchaseService.init()
SettingsService.init()
SquadService.init()
Analytics.init()
AnalyticsHooks.init()
DataService.init() -- last of the game services: profile loads fire into the handlers above
LoadBots.init()
DevService.init()
print(
	string.format(
		"[Capeline] hub ready in %.2f s (%d parts; the outskirts build in the background)",
		os.clock() - t0,
		CityBuilder.builtParts
	)
)
