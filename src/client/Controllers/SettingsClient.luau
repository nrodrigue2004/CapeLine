-- SettingsClient: the device side of Settings (spec: Accessibility; Settings.Set). Holds the values from
-- the save, applies each one at once (graphics preset, text size, left-handed stick and HUD, reduce
-- flashing, one-hand flight, tap-to-fly, touch aim assist, damage numbers, volumes, touch button size, camera motion, soft and hard lock-on) and sends a change to
-- the save after a short pause so a slider drag sends once. The saved mute list fills PvpClient's mutes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local SettingsRules = require(Shared:WaitForChild("SettingsRules"))

local State = require(script.Parent.Parent.State)
local QualityController = require(script.Parent.QualityController)
local InputController = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)
local PvpClient = require(script.Parent.PvpClient)
local LockClient = require(script.Parent.LockClient)
local CombatFx = require(script.Parent.Parent.Fx.CombatFx)
local FxLib = require(script.Parent.Parent.Fx.FxLib)
local Kit = require(script.Parent.Parent.Ui.Kit)
local Popups = require(script.Parent.Parent.Ui.Popups) -- fix-hud: Settings "Popups"

local SettingsClient = {}

SettingsClient.Changed = Signal.new() -- (id, value)
SettingsClient.values = SettingsRules.defaults(Config)

local loaded = false
local pending: { [number]: number } = {}
local sendAt = 0

local function index(id: string): number?
	for i, k in Config.Settings.keys do
		if k.id == id then
			return i
		end
	end
	return nil
end

-- A sound group's volume (M11 puts music and effects sounds in these groups)
local function group(name: string): SoundGroup
	local g = SoundService:FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	return g :: SoundGroup
end

local function stickMode(): string
	local v = SettingsClient.values
	if v.oneHand == 1 then
		return "oneHand"
	elseif v.leftHanded == 1 then
		return "left"
	end
	return "default"
end

local function apply(id: string)
	local v = SettingsClient.values[id]
	if id == "preset" then
		QualityController.choose(v)
	elseif id == "textSize" then
		Kit.setTextScale(v / 100)
	elseif id == "reduceFlashing" then
		local on = v == 1
		CombatFx.reduceFlashing = on
		FxLib.reduceFlashing = on
		CameraController.setMotion(nil, on) -- (sets CameraController.reduceMotion)
		Kit.flashLevel = if on then 0.35 else 1
	elseif id == "leftHanded" or id == "oneHand" then
		InputController.setStick(stickMode())
	elseif id == "autoAim" then
		InputController.autoAim = v == 1
	elseif id == "damageNumbers" then
		CombatFx.showNumbers = v == 1
	elseif id == "music" then
		group("Music").Volume = v / 10
	elseif id == "sfx" then
		group("Effects").Volume = v / 10
	elseif id == "cameraMotion" then
		CameraController.setMotion(v) -- lore step 7: Full, Reduced (half) or Off (Config.Cinema.camera)
	elseif id == "softLock" then
		LockClient.softOn = v == 1 -- lock-on (nate's playtest 2026-11-19): casts and the camera ease to targets
	elseif id == "hardLock" then
		LockClient.hardOn = v == 1 -- the LOCK toggle (middle mouse or Tab, R3, the LOCK button)
	elseif id == "popups" then
		Popups.setMode(v) -- fix-hud: All, Important only, Off (Config.Ui.popups.modes)
	elseif id == "buttonSize" then
		Kit.setButtonScale(v / 100) -- the touch cluster's size (TouchLayout keeps it on screen)
	elseif string.sub(id, 1, 5) == "bind_" then
		InputController.applyBinds(SettingsRules.binds(Config, SettingsClient.values)) -- PC key rebinds
	end
	SettingsClient.Changed:Fire(id, v)
end

function SettingsClient.get(id: string): number
	return SettingsClient.values[id] or 0
end

function SettingsClient.on(id: string): boolean
	return SettingsClient.get(id) == 1
end

-- Change one setting here and on the save
function SettingsClient.set(id: string, value: number)
	local i = index(id)
	if not i then
		return
	end
	local k = Config.Settings.keys[i]
	local v = SettingsRules.value(k, value)
	if v == nil or SettingsClient.values[id] == v then
		return
	end
	SettingsClient.values[id] = v
	apply(id)
	pending[i] = v
	sendAt = os.clock() + Config.Settings.sendDelay
	task.delay(Config.Settings.sendDelay + 0.05, function()
		if os.clock() >= sendAt then
			for key, value2 in pending do
				Net.send("SettingsSet", key, value2)
			end
			pending = {}
		end
	end)
end

local function load(view: { [string]: any })
	if loaded or type(view.settings) ~= "table" then
		return
	end
	loaded = true
	SettingsClient.values = SettingsRules.clean(Config, view.settings)
	for _, k in Config.Settings.keys do
		apply(k.id)
	end
	for _, userId in view.mutes or {} do
		PvpClient.mute(userId, true, true)
	end
end

function SettingsClient.init()
	State.ProfileChanged:Connect(function()
		load(State.profile)
	end)
	load(State.profile)
end

return SettingsClient
