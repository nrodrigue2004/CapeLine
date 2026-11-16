-- State: the client's copy of its own hero (from HeroState, HeroStatus and player attributes). Read-only
-- here; the server owns every number.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))

local State = {}

State.hero = {
	level = 1,
	classId = Config.Classes.default,
	setId = "Volt",
	fxStyle = "Comic",
	power = 36,
	maxHealth = 400,
	styles = { flight = Config.Dev.unlockAllStyles },
	loadout = select(2, AbilityRules.starter(Config, "Volt")),
	loadouts = {},
	loadoutIndex = 1,
	ranks = (AbilityRules.starter(Config, "Volt")),
	mods = {},
	points = 1,
	bonusPoints = 0,
	credits = 0,
	respecIn = 0,
}
-- Buffs and the Awakening meter (HeroStatus); times are local clock seconds
State.status = { meter = 0, awakeUntil = 0, buffs = {} :: { [string]: { untilT: number, value: number } } }
State.Changed = Signal.new()
State.StatusChanged = Signal.new()
State.Notice = Signal.new() -- (ok, reason) after a loadout, rank, mod or respec request

-- Ranked numbers of an ability for this hero
function State.effective(id: string): { [string]: any }
	return AbilityRules.effective(Config, id, State.hero.ranks[id] or 1, State.hero.mods[id])
end

function State.buff(kind: string): number
	local b = State.status.buffs[kind]
	if b and os.clock() < b.untilT then
		return b.value
	end
	return 0
end

function State.awakened(): boolean
	return os.clock() < State.status.awakeUntil
end

function State.init()
	Net.listen("HeroState", function(data)
		for k, v in data do
			State.hero[k] = v
		end
		State.Changed:Fire()
	end)
	Net.listen("HeroStatus", function(data)
		local now = os.clock()
		State.status.meter = data.meter or 0
		State.status.awakeUntil = now + (data.awakeLeft or 0)
		local buffs = {}
		for kind, b in data.buffs or {} do
			buffs[kind] = { untilT = now + b.left, value = b.value }
		end
		State.status.buffs = buffs
		State.StatusChanged:Fire()
	end)
	Net.listen("AbilityNotice", function(data)
		State.Notice:Fire(data.ok, data.reason)
	end)
end

return State
