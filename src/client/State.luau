-- State: the client's copy of its own hero (from HeroState and player attributes). Read-only here; the
-- server owns every number.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local State = {}

State.hero = {
	level = 1,
	classId = Config.Classes.default,
	setId = "Volt",
	fxStyle = "Comic",
	power = 36,
	maxHealth = 400,
	styles = { flight = Config.Dev.unlockAllStyles },
	loadout = {
		basic = Config.Abilities.defaultLoadout.basic,
		skills = table.clone(Config.Abilities.defaultLoadout.skills),
	},
}
State.Changed = Signal.new()

function State.init()
	Net.listen("HeroState", function(data)
		for k, v in data do
			State.hero[k] = v
		end
		State.Changed:Fire()
	end)
end

return State
