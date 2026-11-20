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
local CityProps = require(Controllers.CityProps)
local PocketDecor = require(Controllers.PocketDecor)
local InputController = require(Controllers.InputController)
local MoveController = require(Controllers.MoveController)
local GroundGuard = require(Controllers.GroundGuard)
local CameraController = require(Controllers.CameraController)
local EnemyRenderer = require(Controllers.EnemyRenderer)
local CitizenRenderer = require(Controllers.CitizenRenderer)
local HeroAnimator = require(Controllers.HeroAnimator)
local NpcGestures = require(Controllers.NpcGestures)
local WorldClient = require(Controllers.WorldClient)
local DeepClient = require(Controllers.DeepClient)
local StoryClient = require(Controllers.StoryClient)
local PvpClient = require(Controllers.PvpClient)
local HqClient = require(Controllers.HqClient)
local AudioController = require(Controllers.AudioController)
local IdleWatch = require(Controllers.IdleWatch)
local Telemetry = require(Controllers.Telemetry)
local FavoritePrompt = require(Controllers.FavoritePrompt) -- WP4: the favorite prompt after a first boss win
local JuiceFx = require(Fx.JuiceFx)
local Juice = require(Fx.Juice)
local CombatFx = require(Fx.CombatFx)
local MoveFx = require(Fx.MoveFx)
local MoveAudio = require(Fx.MoveAudio) -- the sounds pass: pound, bounce, splash, dash, sonic boom, the Super Speed rush
local SwingFx = require(Fx.SwingFx) -- the Swing's lines, shots, misses and whooshes (2026-11-19)
local IceFx = require(Fx.IceFx) -- gap polish 2026-11-19: the Snow Wall, Ice Slide and raft looks
local AuraFx = require(Fx.AuraFx)
local TetherFx = require(Fx.TetherFx)
local SwingTrailFx = require(Fx.SwingTrailFx)
local BuildingFx = require(Fx.BuildingFx)
local CityLife = require(Fx.CityLife)
local ParkLife = require(Fx.ParkLife)
local LitWindows = require(Fx.LitWindows)
local WaterSurface = require(Fx.WaterSurface)
local ImpactFx = require(Fx.ImpactFx) -- 2026-11-19: rams and throws through walls
local GroundFx = require(Fx.GroundFx) -- fix-destroy: ground craters
local VehicleFx = require(Fx.VehicleFx)
local VehicleRig = require(Fx.VehicleRig) -- gap-vehicles: wheels roll and steer, bodies sway
local WorldFx = require(Fx.WorldFx)
local ActivityFx = require(Fx.ActivityFx)
local StoryFx = require(Fx.StoryFx)
local PrologueFx = require(Fx.PrologueFx)
local IntroFilmFx = require(Fx.IntroFilm) -- the intro film (list-combat 2026-11-20)
local PrologueQte = require(Fx.PrologueQte) -- fix-flow: the rooftop chase as quick-time prompts
local QteHud = require(Ui.QteHud)
local PvpFx = require(Fx.PvpFx)
local EmoteFx = require(Fx.EmoteFx)
local CombatClient = require(Controllers.CombatClient)
local GadgetClient = require(Controllers.GadgetClient)
local BlockClient = require(Controllers.BlockClient) -- H1: block, breaker, interrupt
local GuardFx = require(Fx.GuardFx)
local FormFx = require(Fx.FormFx)
local CapeSway = require(Fx.CapeSway)
local ChargeFx = require(Fx.ChargeFx) -- H2: charge-up powers
local ThrowClient = require(Controllers.ThrowClient) -- H3: pick up and throw
local LockClient = require(Controllers.LockClient) -- nate's playtest 2026-11-19: soft and hard lock-on
local ThrowFx = require(Fx.ThrowFx)
local CraterDecor = require(Fx.CraterDecor) -- lore step 9: the Crater's loose lab debris, per preset
local TravelClient = require(Controllers.TravelClient)
local Hud = require(Ui.Hud)
local LoadoutScreen = require(Ui.LoadoutScreen)
local GearScreen = require(Ui.GearScreen)
local Toasts = require(Ui.Toasts)
local MapScreen = require(Ui.MapScreen)
local WorldHud = require(Ui.WorldHud)
local ContractBoard = require(Ui.ContractBoard)
local TaskForceHud = require(Ui.TaskForceHud) -- H4: the Task Force board
local NemesisHud = require(Ui.NemesisHud) -- H5: the WANTED poster and taunts
local NemesisFx = require(Fx.NemesisFx)
local MentorHud = require(Ui.MentorHud) -- H6: the mentor card, picker and panels
local MentorFx = require(Fx.MentorFx)
local BadgeHud = require(Ui.BadgeHud) -- H7: the Badge Book, collections and titles
local HelpHud = require(Ui.HelpHud) -- HOW TO PLAY (Everything Left 86)
local ContestHud = require(Ui.ContestHud) -- H7: costume contests
local CollectClient = require(Controllers.CollectClient) -- H7: collection sparkles and the scanner marker
local LoreClient = require(Controllers.LoreClient) -- side-content: the lore pages' books and caption cards
local SideOnly = require(Controllers.SideOnly) -- side-content: hides the other side's quest givers
local PassHud = require(Ui.PassHud) -- H8: the Hero Pass, the episode and travel styles
local BoardHud = require(Ui.BoardHud) -- WP2: the weekly boards and the plaza board
local DailyHud = require(Ui.DailyHud) -- WP1: the daily streak card and the daily quest tracker
local TravelStyleFx = require(Fx.TravelStyleFx) -- H8: travel styles on every screen
local StoryHud = require(Ui.StoryHud)
local GuideHud = require(Ui.GuideHud) -- lore step 6: the guides' line box
local GuideClient = require(Controllers.GuideClient) -- lore step 6: stage lines, Patch's radio, Lodestar
local Journal = require(Ui.Journal)
local PvpHud = require(Ui.PvpHud)
local Plates = require(Ui.Plates)
local CreatorScreen = require(Ui.CreatorScreen)
local WeaponRack = require(Ui.WeaponRack)
local ShopHud = require(Ui.ShopHud)
local HqHud = require(Ui.HqHud)
local SettingsClient = require(Controllers.SettingsClient)
local SquadClient = require(Controllers.SquadClient)
local SettingsMenu = require(Ui.SettingsMenu)
local SquadHud = require(Ui.SquadHud)
local Radar = require(Ui.Radar)
local MainMenu = require(Ui.MainMenu)
local PhotoMode = require(Ui.PhotoMode)
local Kit = require(Ui.Kit)
local DevPanel = require(Ui.DevPanel)
local CinemaClient = require(Controllers.CinemaClient) -- lore step 7: the one cutscene player
local CinemaHud = require(Ui.CinemaHud) -- lore step 7: letterbox, SKIP, comic pages, name cards, finisher screen
local NewsHud = require(Ui.NewsHud) -- lore step 7: the big screens and the corner TV
local FinisherFx = require(Fx.FinisherFx) -- lore step 7: slow-mo finishers

State.init()
QualityController.init()
CityProps.init() -- the city kit's street props near the camera, within the preset's budget
PocketDecor.init() -- the pockets' kit dressing above tier 1, lights and props, within the preset's budget
InputController.init()
MoveController.init()
GroundGuard.init() -- holds the hero still until the ground under a spawn or a server move has streamed in
CameraController.init()
CinemaClient.init()
EnemyRenderer.init()
CitizenRenderer.init()
WorldClient.init()
DeepClient.init()
StoryClient.init()
PvpClient.init()
AudioController.init()
JuiceFx.init()
Juice.init()
CombatFx.init()
MoveFx.init()
MoveAudio.init()
SwingFx.init()
IceFx.init()
AuraFx.init()
BuildingFx.init()
CityLife.init() -- the living world: traffic, pigeons, steam, flags, news drones, shop lights, prop bursts
ParkLife.init() -- the city park: joggers, dogs, picnics, buskers, ducks, rowboats, the carousel, fountains, splashes
LitWindows.init() -- shapes-2: the kit fronts' windows light up after dusk
WaterSurface.init() -- shapes-2: pools, ponds and fountains ripple
ImpactFx.init()
GroundFx.init()
VehicleFx.init()
VehicleRig.init()
WorldFx.init()
ActivityFx.init()
StoryFx.init()
PrologueFx.init()
IntroFilmFx.init()
QteHud.init()
PrologueQte.init()
PvpFx.init()
CombatClient.init()
BlockClient.init()
GuardFx.init()
FormFx.init()
CapeSway.init()
ChargeFx.init()
ThrowClient.init() -- after BlockClient: it wraps CombatClient.blocked
LockClient.init() -- after CombatClient and WorldFx: it aims casts (CombatClient.lockAim) and frames the camera
ThrowFx.init()
CraterDecor.init()
HeroAnimator.init()
NpcGestures.init()
TetherFx.init()
SwingTrailFx.init() -- the weapons' swing trails, lit during their moves (list-combat)
HqClient.init()
EmoteFx.init()
GadgetClient.init()
Hud.init()
LoadoutScreen.init()
GearScreen.init()
ContractBoard.init()
TaskForceHud.init()
NemesisHud.init()
NemesisFx.init()
MentorHud.init()
MentorFx.init()
BadgeHud.init()
HelpHud.init()
ContestHud.init()
CollectClient.init()
LoreClient.init()
SideOnly.init()
PassHud.init()
BoardHud.init()
DailyHud.init()
TravelStyleFx.init()
Toasts.init()
-- pt-ui (2026-11-19): a cast or a landed hit is fighting, so non-urgent popups wait (Ui.Popups; hits taken come
-- from CinemaClient.lastHit)
do
	local Popups = require(Ui.Popups)
	CombatClient.Cast:Connect(Popups.fought)
	CombatClient.HitConfirm:Connect(Popups.fought)
end
MapScreen.init()
WorldHud.init()
CreatorScreen.init()
WeaponRack.init()
GuideHud.init()
CinemaHud.init()
StoryHud.init()
NewsHud.init()
FinisherFx.init()
GuideClient.init()
Journal.init()
PvpHud.init()
Plates.init()
ShopHud.init()
HqHud.init()
TravelClient.init()
SettingsClient.init()
SquadClient.init()
SettingsMenu.init()
SquadHud.init()
Radar.init()
MainMenu.init()
PhotoMode.init()
IdleWatch.busyCheck = function()
	return TravelClient.flying == true
		or PhotoMode.isOpen()
		or SettingsMenu.isOpen()
		or MainMenu.isOpen()
		or CreatorScreen.isOpen()
end
IdleWatch.init()
-- lore step 7: a device-started scene only plays in a quiet moment (no fight would leave the hero defenceless)
CinemaClient.context = function()
	local player = game:GetService("Players").LocalPlayer
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pos = root and root.Position
	local nearest = math.huge
	if pos then
		for _, p in EnemyRenderer.each() do
			nearest = math.min(nearest, (p - pos).Magnitude)
		end
	end
	local b = WorldClient.boss
	local def = b and b.id and require(ReplicatedStorage:WaitForChild("Config")).Boss.bosses[b.id]
	local inBoss = def ~= nil
		and pos ~= nil
		and b.state == 3
		and (Vector3.new(b.x, pos.Y, b.z) - pos).Magnitude <= (def.arenaRadius or 200) + 100
	return {
		hitAgo = os.clock() - CinemaClient.lastHit,
		enemy = nearest,
		downed = player:GetAttribute("Downed") == true,
		pvp = player:GetAttribute("Pvp") == true,
		boss = inBoss,
		story = StoryClient.inOpening(), -- the prologue plays only its own story (nate's playtest 2026-11-18)
	}
end
Telemetry.init()
FavoritePrompt.init()
DevPanel.init()

-- the gear button opens Settings; left-handed mirrors the action buttons (one-hand keeps them right)
Hud.OpenSettings:Connect(SettingsMenu.open)
local function handed()
	Hud.setLeftHanded(SettingsClient.on("leftHanded") and not SettingsClient.on("oneHand"))
end
local function flashes()
	local on = SettingsClient.on("reduceFlashing")
	JuiceFx.reduce = on
	PhotoMode.reduce = on
end
SettingsClient.Changed:Connect(function(id)
	if id == "leftHanded" or id == "oneHand" then
		handed()
	elseif id == "reduceFlashing" then
		flashes()
	end
end)
handed()
flashes()

-- any reply from the server ends a button's waiting state (spec: every remote call shows it is pending)
State.ProfileChanged:Connect(Kit.settle)
State.Notice:Connect(Kit.settle)
State.Toast:Connect(Kit.settle)
