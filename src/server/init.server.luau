-- Capeline server boot (spec: Server lifecycle and Services). Order matters: the city first (the drone AI
-- reads its heights), then remotes, heroes, movement checks, enemies, combat, and the Studio-only tools.

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
local LoadBots = require(Services.LoadBots)
local DevService = require(Services.DevService)

print(string.format("[Capeline] boot, balance %d, build %s", Config.Version.balance, Config.Version.build))
local t0 = os.clock()
CityBuilder.build()
Net.initServer()
PerfMonitor.init()
HeroService.init()
MoveGuard.init()
EnemyService.init(CityBuilder.layout)
CombatService.init()
AbilityService.init()
LoadBots.init()
DevService.init()
print(string.format("[Capeline] ready in %.2f s (%d city parts)", os.clock() - t0, CityBuilder.layout.parts))
