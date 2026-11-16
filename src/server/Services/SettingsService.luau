-- SettingsService: saved settings and the mute list (spec: Settings.Set {key, value} "Valid key" 2/s;
-- save "Graphics preset, text size, left-handed, reduce flashing, mute list"). The device applies a change
-- at once; this keeps it on the account so it follows the player to any device. Old saves are cleaned on
-- load (SettingsRules.clean). No reply is sent: the device already shows the change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local SettingsRules = require(Shared:WaitForChild("SettingsRules"))

local DataService = require(script.Parent.DataService)

local SettingsService = {}

function SettingsService.get(player: Player): { [string]: number }?
	local profile = DataService.get(player)
	return profile and profile.settings
end

function SettingsService.init()
	DataService.Loaded:Connect(function(_, profile)
		profile.settings = SettingsRules.clean(Config, profile.settings)
	end)
	Net.on("SettingsSet", function(player, index: number, value: number)
		local profile = DataService.get(player)
		if profile and SettingsRules.set(Config, profile.settings, index, value) then
			DataService.saveSoon(player)
		end
	end)
	Net.on("SettingsMute", function(player, userId: number, on: number)
		local profile = DataService.get(player)
		if profile and userId ~= player.UserId then
			SettingsRules.mute(Config, profile.mutes, userId, on == 1)
			DataService.saveSoon(player)
		end
	end)
end

return SettingsService
