-- WeaponService: the weapon slot in play (nate's hero creator plan, 2026-11-16; Config.Weapons, WeaponRules).
-- * Key 1 holds the power, key 2 the weapon (WeaponHold). M1 and the skill keys cast what is held
--   (CombatService asks WeaponRules.kit); the super is always the power's. The weapon shows in the hand only
--   while it is held (LookKit.showWeapon on the server-built look, so every player sees it).
-- * Mastery: every landed hit of a weapon move adds perHit, a robot finished while holding it perKill; the
--   points live on the account (profile.weapons) and X, C and V open at 25, 75 and 150 (WeaponMastery tells
--   the player, and HeroState carries the points so the buttons unlock).
-- * The Weapon Rack: a terminal in every safehouse. WeaponBuy spends Credits on a Rack weapon (never a Robux
--   one); WeaponCarry swaps the carried weapon to one you own. Both need the hero at a safehouse or HQ.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local LookKit = require(Shared:WaitForChild("LookKit"))

local HeroService = require(script.Parent.HeroService)
local DataService = require(script.Parent.DataService)
local CombatService = require(script.Parent.CombatService)
local SafehouseService = require(script.Parent.SafehouseService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local Analytics = require(script.Parent.Analytics)

local WeaponService = {}

local W = Config.Weapons

-- Show the carried weapon in the hand only while it is held
function WeaponService.showHeld(hero: any)
	local player = hero.player
	local char = player and player.Character
	if char then
		LookKit.showWeapon(char, hero.held == "weapon")
	end
	if player then
		player:SetAttribute("Held", hero.held)
	end
end

local function hold(hero: any, which: number)
	local held = if which == 2 then "weapon" else "power"
	if hero.held == held then
		return
	end
	hero.held = held
	hero.combo.at, hero.combo.step = 0, 0 -- a fresh string after a swap
	hero.channel = nil
	WeaponService.showHeld(hero)
	HeroService.sendState(hero)
end

local function addMastery(hero: any, weaponId: number, points: number)
	local player = hero.player
	local profile = player and DataService.get(player)
	if not profile or weaponId ~= hero.weapon or points <= 0 or hero.lab then
		return -- (Studio's Test Lab earns no Mastery: its weapon may not even be owned)
	end
	local before = WeaponRules.masteryLevel(Config, hero.weaponMastery)
	local level, opened = WeaponRules.addMastery(Config, profile, weaponId, points)
	hero.weaponMastery = WeaponRules.state(profile, weaponId).mastery
	DataService.changed(player)
	if level ~= before then
		Net.fire("WeaponMastery", player, { id = weaponId, level = level, opened = opened })
		HeroService.sendState(hero) -- the skill buttons unlock
		if level == W.mastery.masteredGlow or #opened > 0 then
			GearService.refresh(player) -- the Mastered glow
		end
		for _, key in opened do
			Analytics.event(player, "weapon_skill_open", 1, { weaponId, key })
		end
	end
end

local function answer(player: Player, kind: string, ok: boolean, reason: string?, id: number)
	Net.fire("WeaponResult", player, { kind = kind, ok = ok, reason = reason, id = id })
end

local function atRack(hero: any): boolean
	return SafehouseService.near(hero)
end

local function buy(player: Player, id: number)
	local hero = HeroService.get(player)
	local profile = DataService.get(player)
	if not hero or not profile then
		return
	end
	if not atRack(hero) then
		answer(player, "buy", false, "rack", id)
		return
	end
	if not WeaponRules.playable(Config, id) then
		answer(player, "buy", false, "soon", id)
		return
	end
	local wallet = profile.currency.credits + profile.currency.banked
	local ok, reason, price = WeaponRules.buyOk(Config, profile, id, wallet)
	if not ok then
		answer(player, "buy", false, reason, id)
		return
	end
	if not EconomyService.spend(hero, price) then
		answer(player, "buy", false, "credits", id)
		return
	end
	WeaponRules.grant(profile, id)
	DataService.changed(player)
	Analytics.event(player, "weapon_buy", price, { id })
	answer(player, "buy", true, nil, id)
end

local function carry(player: Player, id: number)
	local hero = HeroService.get(player)
	local profile = DataService.get(player)
	if not hero or not profile then
		return
	end
	if not atRack(hero) then
		answer(player, "carry", false, "rack", id)
		return
	end
	if not WeaponRules.playable(Config, id) then
		answer(player, "carry", false, "soon", id)
		return
	end
	if not WeaponRules.owned(Config, profile, id) then
		answer(player, "carry", false, "owned", id)
		return
	end
	local char = ProfileSchema.active(profile)
	char.weapon = id
	GearService.refresh(player) -- loads the weapon and rebuilds the look
	HeroService.sendState(hero)
	answer(player, "carry", true, nil, id)
end

function WeaponService.init()
	Net.on("WeaponHold", function(player, which: number)
		local hero = HeroService.get(player)
		if hero and hero.alive then
			hold(hero, which)
		end
	end)
	Net.on("WeaponBuy", buy)
	Net.on("WeaponCarry", carry)
	CombatService.WeaponHits:Connect(function(hero, weaponId: number, hits: number)
		addMastery(hero, weaponId, hits * W.mastery.perHit)
	end)
	CombatService.Killed:Connect(function(hero)
		if hero.held == "weapon" then
			addMastery(hero, hero.weapon, W.mastery.perKill)
		end
	end)
	-- a new body comes with the power held
	HeroService.Spawned:Connect(function(hero)
		hero.held = "power"
		task.defer(WeaponService.showHeld, hero)
	end)
end

return WeaponService
