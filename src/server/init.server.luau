-- Capeline server boot (spec: Server lifecycle and Services). Order matters: the city first (the drone AI
-- reads its heights), then remotes, heroes, movement checks, enemies, combat, abilities, economy, gear and
-- perks, safehouses and beacons, then saves (a loaded profile fires into all of those), and the Studio-only tools.

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
local LoadBots = require(Services.LoadBots)
local DevService = require(Services.DevService)

print(string.format("[Capeline] boot, balance %d, build %s", Config.Version.balance, Config.Version.build))
local t0 = os.clock()
CityBuilder.build()
Net.initServer()
PerfMonitor.init()
HeroService.init()
MoveGuard.init()
EnemyService.init(CityBuilder.world)
CombatService.init()
AbilityService.init()
EconomyService.init()
GearService.init()
PerkService.init()
SafehouseService.init()
BeaconService.init()
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
