-- Juice: one call per juice action (spec: Audio, VFX and juice "Every sound has a visual cue"). Each call
-- plays the action's sound (AudioController), its JuiceFx visual when it has one, a short vibration on
-- phones and gamepads for the heavy ones, and the hero's voice line when the action has one. The other
-- visuals stay where they were built (MoveFx, CombatFx, BuildingFx and the rest) and call Juice for sound.
-- Config.Audio.juice lists all 31 actions and where each visual lives; tests check every one is fired.

local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)
local State = require(script.Parent.Parent.State)
local JuiceFx = require(script.Parent.JuiceFx)

local Juice = {}

local A = Config.Audio
Juice.haptics = true -- Settings could turn this off later; reduce flashing does not

local function buzz(strength: number)
	if not Juice.haptics then
		return
	end
	local ok = pcall(function()
		if UserInputService.TouchEnabled and HapticService:IsVibrationSupported(Enum.UserInputType.Touch) then
			HapticService:SetMotor(Enum.UserInputType.Touch, Enum.VibrationMotor.Large, strength)
			task.delay(0.12, function()
				HapticService:SetMotor(Enum.UserInputType.Touch, Enum.VibrationMotor.Large, 0)
			end)
		end
		if
			UserInputService.GamepadEnabled
			and HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1)
		then
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, strength)
			task.delay(0.12, function()
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
			end)
		end
	end)
	if not ok then
		Juice.haptics = false -- this device has no motor API
	end
end

-- Fire one juice action. at: where it happened (nil = on you). data: details for the visual (tier, medal,
-- level, renown, name), mine (it is your action: vibrate and voice), userId (whose voice).
function Juice.fire(id: string, at: Vector3?, data: { [string]: any }?)
	local d = data or {}
	if id == "gearDrop" then
		local idx = table.find(Config.Gear.tierOrder or {}, d.tier) or 1
		AudioController.play(id, at, { pitch = A.tierPitch[math.min(idx, #A.tierPitch)] })
		if idx >= 5 then
			task.delay(0.25, function()
				AudioController.play(id, at, { pitch = A.tierPitch[#A.tierPitch] * 1.2 })
			end)
		end
	else
		AudioController.play(id, at)
	end
	-- a row with `sting` also plays the music's victory sting (a side quest chain done)
	local row = A.sounds[id]
	if row and row.sting then
		AudioController.victory()
	end
	local fx = (JuiceFx :: any)[id]
	if type(fx) == "function" then
		fx(at, d)
	end
	local h = A.haptics[id]
	if h and d.mine ~= false then
		buzz(h)
	end
	if table.find(A.voice.lines, id) then
		AudioController.voice(d.userId, id)
	end
end

-- A path's own sound layer (Config.Audio.paths; overhaul plan step 6), on top of the slot's cast sound:
-- moment is "cast", "super", "hit" or "charge". Weapon moves and unknown sets have none.
function Juice.path(set: string?, moment: string, at: Vector3?)
	local row = set and A.paths[set]
	if row and row[moment] then
		AudioController.playSpec(row[moment], at)
	end
end

-- Held sounds: the flight wind (volume follows speed) and the Downed heartbeat
function Juice.hold(id: string, on: boolean, volume: number?)
	AudioController.loop(id, on, volume)
end

-- The juice rows with no single owner: a respawn (every character after the first), a skill rank or
-- loadout change the server took (State.Notice ok), and the boss warning (the countdown starting)
function Juice.init()
	local first = true
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if first then
			first = false
			return
		end
		task.delay(0.3, function()
			Juice.fire("respawn")
		end)
	end)
	if Players.LocalPlayer.Character then
		first = false
	end
	State.Notice:Connect(function(ok)
		if ok then
			Juice.fire("skillRank")
		end
	end)
	local bossState = WorldClient.boss.state or 0
	WorldClient.Changed:Connect(function(what)
		if what ~= "boss" then
			return
		end
		local st = WorldClient.boss.state or 0
		if st == 1 and bossState ~= 1 then
			Juice.fire("bossWarning")
		end
		bossState = st
	end)
end

return Juice
