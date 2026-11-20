-- State: the client's copy of its own hero (from HeroState, HeroStatus and player attributes). Read-only
-- here; the server owns every number.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))

local State = {}

State.hero = {
	level = 1,
	side = "hero",
	classId = Config.Classes.default,
	setId = "Volt",
	fxStyle = "Comic",
	power = 36,
	maxHealth = 400,
	styles = { flight = true },
	mobility = "flight",
	loadout = select(2, AbilityRules.starter(Config, "Volt")),
	loadouts = {},
	loadoutIndex = 1,
	ranks = (AbilityRules.starter(Config, "Volt")),
	mods = {},
	points = 1,
	bonusPoints = 0,
	credits = 0,
	respecIn = 0,
	xp = 0,
	stats = { Might = 0, Vitality = 0, Focus = 0, Precision = 0, Resolve = 0 },
	gearScore = 0,
	gearMods = {},
	perks = {},
	gadget = nil,
	held = "power", -- key 1 holds the power, key 2 the weapon
	weapon = Config.Weapons.defaultWeapon,
	weaponMastery = 0,
}
-- The saved profile as the server shows it (ProfileSync): stash, styles, wallet, pity, worn gear
State.profile = {
	stash = {},
	styles = {},
	currency = { credits = 0, banked = 0, dust = 0 },
	pity = { epic = 0, legendary = 0 },
	equipment = table.create(8, 0),
	shown = table.create(8, 0),
	level = 1,
	xp = 0,
	beacons = 0, -- discovered fast-travel beacons (mask)
	safehouses = 0, -- visited safehouses (mask)
	lastSafehouse = 0,
} :: { [string]: any }
State.ProfileChanged = Signal.new()
State.syncWalletOnly = false -- the last ProfileSync carried only the wallet (fix-respawn)
State.syncLevelChanged = false -- and it changed the level
State.Toast = Signal.new() -- (data) level up, reward, loot, save notices
-- Buffs, crowd control and the Awakening meter (HeroStatus); times are local clock seconds
State.status = {
	meter = 0,
	awakeUntil = 0,
	buffs = {} :: { [string]: { untilT: number, value: number } },
	cc = {} :: { [string]: { untilT: number, value: number } }, -- M8: PvP stuns, roots, slows, lifts on you
}
State.Changed = Signal.new()
State.StatusChanged = Signal.new()
State.Notice = Signal.new() -- (ok, reason) after a loadout, rank, mod or respec request

-- Ranked numbers of an ability for this hero
function State.effective(id: string): { [string]: any }
	local gear = State.hero.gearMods and State.hero.gearMods[id]
	return AbilityRules.effective(Config, id, State.hero.ranks[id] or 1, State.hero.mods[id], gear)
end

function State.buff(kind: string): number
	local b = State.status.buffs[kind]
	if b and os.clock() < b.untilT then
		return b.value
	end
	return 0
end

-- What M1 and the four skill buttons cast now: the power's loadout, or the held weapon's moves
function State.kit(): WeaponRules.Kit
	local h = State.hero
	return WeaponRules.kit(Config, h.loadout, h.held, h.weapon, h.weaponMastery)
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
		local cc = {}
		for kind, b in data.cc or {} do
			cc[kind] = { untilT = now + b.left, value = b.value }
		end
		State.status.cc = cc
		State.StatusChanged:Fire()
	end)
	Net.listen("AbilityNotice", function(data)
		State.Notice:Fire(data.ok, data.reason)
	end)
	Net.listen("ProfileSync", function(view)
		-- a wallet-only sync (currency, level, xp): screens that draw no wallet may skip their redraw
		State.syncWalletOnly = view.stash == nil and view.pieces == nil
		State.syncLevelChanged = view.level ~= nil and view.level ~= State.profile.level
		for k, v in view do
			State.profile[k] = v -- a wallet-only sync carries just the wallet
		end
		State.ProfileChanged:Fire()
	end)
	Net.listen("Toast", function(data)
		State.Toast:Fire(data)
	end)
	Net.listen("LootDrop", function(data)
		State.Toast:Fire({ id = "loot", piece = data.piece, kind = data.kind, dust = data.dust })
	end)
end

return State
