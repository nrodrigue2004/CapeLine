-- Capeline client boot. Waits for every remote once, then starts the controllers, effects and screens in
-- dependency order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

Net.waitForRemotes()

local State = require(script.State)
local Controllers = script.Controllers
local Fx = script.Fx
local Ui = script.Ui

local QualityController = require(Controllers.QualityController)
local InputController = require(Controllers.InputController)
local MoveController = require(Controllers.MoveController)
local CameraController = require(Controllers.CameraController)
local EnemyRenderer = require(Controllers.EnemyRenderer)
local CombatFx = require(Fx.CombatFx)
local MoveFx = require(Fx.MoveFx)
local AuraFx = require(Fx.AuraFx)
local CombatClient = require(Controllers.CombatClient)
local GadgetClient = require(Controllers.GadgetClient)
local Hud = require(Ui.Hud)
local LoadoutScreen = require(Ui.LoadoutScreen)
local GearScreen = require(Ui.GearScreen)
local Toasts = require(Ui.Toasts)
local DevPanel = require(Ui.DevPanel)

State.init()
QualityController.init()
InputController.init()
MoveController.init()
CameraController.init()
EnemyRenderer.init()
CombatFx.init()
MoveFx.init()
AuraFx.init()
CombatClient.init()
GadgetClient.init()
Hud.init()
LoadoutScreen.init()
GearScreen.init()
Toasts.init()
DevPanel.init()
