-- GearService: loot drops, the stash, equipment, upgrades, salvage, retunes, styles and gadgets (spec:
-- Services > Loot, Gear, Economy; Drops; Style collection, salvage and upgrade; Remote events Gear.*,
-- Style.Apply). Every request runs the pure Inventory rules on the saved profile, then the hero's stats
-- and look are rebuilt and the client gets a fresh ProfileSync. Requests for one profile run one at a time
-- (spec: Duplication: a transaction lock per profile).
-- grant(player, source, zoneLevel) is how incidents, contracts, events, missions and the world boss
-- (M6, M7) hand out gear; the Dev panel calls it in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local GearMath = require(Shared:WaitForChild("GearMath"))
local LootTable = require(Shared:WaitForChild("LootTable"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local MoveGuard = require(script.Parent.MoveGuard)
local LookService = require(script.Parent.LookService)
local AvatarService = require(script.Parent.AvatarService)
local Analytics = require(script.Parent.Analytics)

local GearService = {}
-- (player, profile) an Epic or Legendary piece dropped: CreatorService may unlock a "drop" creator piece (M9)
GearService.onRareDrop = nil :: ((Player, any) -> ())?

local G = Config.Gear
local busy: { [Player]: boolean } = {}
local streetOn: { [Player]: boolean? } = {} -- lore step 2: heroes in the street outfit (CreatorService.streetOutfit)
local rng = Rng.new(os.time() + math.floor(os.clock() * 1000))

local function notice(player: Player, ok: boolean, reason: string?, extra: { [string]: any }?)
	local data = { id = "gear", ok = ok, reason = reason }
	for k, v in extra or {} do
		data[k] = v
	end
	Net.fire("Toast", player, data)
end

-- Rebuild the hero's stats and look from what the active character wears
function GearService.refresh(player: Player)
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if not profile or not hero then
		return
	end
	local char = ProfileSchema.active(profile)
	local totals = GearMath.totals(Config, Inventory.worn(profile, char))
	HeroService.applyGear(hero, totals)
	-- the carried weapon and its Mastery (hero creator plan; WeaponService runs the slot in play)
	hero.weapon = WeaponRules.carried(Config, profile, char)
	hero.weaponMastery = WeaponRules.state(profile, hero.weapon).mastery
	GearService.showLook(player, profile, char)
	DataService.changed(player)
end

-- The street outfit on or off (CreatorService.streetOutfit is the API; looks only)
function GearService.setStreet(player: Player, on: boolean)
	if (streetOn[player] == true) == on then
		return
	end
	streetOn[player] = if on then true else nil
	local profile = DataService.get(player)
	if profile and player.Parent then
		GearService.showLook(player, profile, ProfileSchema.active(profile))
	end
end

function GearService.street(player: Player): boolean
	return streetOn[player] == true
end

-- The creator look plus the gear styles it does not cover (M9). In the street outfit: the plain clothes with
-- the hero's own face and hair (Shared.CreatorRules.streetLook), no gear styles and no weapon.
function GearService.showLook(player: Player, profile: any, char: any)
	local look = CreatorRules.lookOf(Config, char)
	if streetOn[player] then
		LookService.apply(
			player,
			table.create(#G.slotOrder, 0),
			CreatorRules.streetLook(Config, look),
			nil,
			false
		)
		return
	end
	local styles = CreatorRules.visibleStyles(Config, look, Inventory.shownStyles(profile, char), char.shown)
	local hero = HeroService.get(player)
	local weaponId = WeaponRules.carried(Config, profile, char)
	local weapon = WeaponRules.lookOf(profile, weaponId)
	weapon.mastered = WeaponRules.masteryLevel(Config, WeaponRules.state(profile, weaponId).mastery)
		>= Config.Weapons.mastery.masteredGlow
	LookService.apply(player, styles, look, weapon, hero ~= nil and hero.held == "weapon")
end

-- Roll and store the drops for one source. Returns the pieces (already in the stash or salvaged).
function GearService.grant(player: Player, source: string, zoneLevel: number): { any }
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if not profile or not hero then
		return {}
	end
	local tiers = LootTable.roll(Config, rng, source, { level = hero.level, pity = profile.pity })
	local out = {}
	for _, tier in tiers do
		local ilvl = GearMath.itemLevel(Config, rng, zoneLevel)
		local piece =
			GearMath.roll(Config, rng, tier, ilvl, { gadget = rng:next() < Config.Loot.gadgetChance })
		local kind, stored, dust = Inventory.add(Config, profile, piece)
		Net.fire("LootDrop", player, { piece = stored, kind = kind, dust = dust })
		Analytics.event(player, "gear_drop", 1, { tier, source, ilvl })
		table.insert(out, stored)
		if (tier == "Epic" or tier == "Legendary") and GearService.onRareDrop then
			GearService.onRareDrop(player, profile)
		end
	end
	if #out > 0 then
		DataService.changed(player)
		DataService.saveSoon(player)
	end
	return out
end

-- Run one gear request under the profile's lock; fn returns ok, reason, extra
-- One piece of a set tier (story rewards: the Rare Decoy gadget from Save the Train and Iron Dee, the
-- 10% Epic crate from Test Her). opts.gadget names the gadget.
function GearService.grantPiece(
	player: Player,
	tier: string,
	zoneLevel: number,
	opts: { gadget: string? }?
): any?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local o = opts or {}
	local ilvl = GearMath.itemLevel(Config, rng, zoneLevel)
	local piece = GearMath.roll(Config, rng, tier, ilvl, { gadget = o.gadget ~= nil })
	if o.gadget then
		piece.gadget = table.find(G.gadgetOrder, o.gadget) or piece.gadget
	end
	local kind, stored, dust = Inventory.add(Config, profile, piece)
	Net.fire("LootDrop", player, { piece = stored, kind = kind, dust = dust })
	Analytics.event(player, "gear_drop", 1, { tier, "story", ilvl })
	DataService.changed(player)
	DataService.saveSoon(player)
	return stored
end

local function run(player: Player, fn: (any, any) -> (boolean, string?, any?))
	if busy[player] then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	busy[player] = true
	local ok, okResult, reason, extra = pcall(fn, profile, ProfileSchema.active(profile))
	busy[player] = false
	if not ok then
		warn("[GearService] " .. tostring(okResult))
		return
	end
	notice(player, okResult, reason, extra)
	if okResult then
		GearService.refresh(player)
		DataService.saveSoon(player)
	end
end

---------------------------------------------------------------------------
-- Gadgets (the 8th slot): Grappling Hook, Smoke Bomb, Shield Drone, Decoy
---------------------------------------------------------------------------

local gadgetBooks: { [Player]: Cooldowns.Book } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function useGadget(player: Player, aim: Vector3)
	local hero = HeroService.get(player)
	if not hero or not hero.alive or not hero.gadget or aim.Magnitude < 0.5 then
		return
	end
	local kind = hero.gadget
	local row = G.gadgets[kind]
	local book = gadgetBooks[player] or Cooldowns.new()
	gadgetBooks[player] = book
	local now = os.clock()
	if not Cooldowns.ready(book, kind, now, 0.1) then
		return
	end
	local pos = HeroService.position(hero)
	if not pos then
		return
	end
	local target: Vector3? = nil
	if kind == "GrapplingHook" then
		-- hook the first building or street along the aim
		rayParams.FilterDescendantsInstances = { player.Character :: any }
		local hit = Workspace:Raycast(pos, aim.Unit * row.range, rayParams)
		if not hit then
			Net.fire("GadgetResult", player, { kind = kind, ok = false })
			return
		end
		target = hit.Position + hit.Normal * 3
		MoveGuard.grant(hero, (target :: Vector3 - pos).Magnitude + 12)
	elseif kind == "SmokeBomb" then
		for _, c in EnemyService.candidates() do
			if (Vector3.new(c.x, c.y, c.z) - pos).Magnitude <= row.radius then
				EnemyService.applyStatus(c.id, "blind", row.blind)
				EnemyService.forget(c.id, hero.id)
			end
		end
		target = pos
	elseif kind == "ShieldDrone" then
		HeroService.buff(hero, "shield", math.floor(hero.maxHealth * row.shield + 0.5), row.duration)
		target = pos
	elseif kind == "Decoy" then
		local decoy = HeroService.addDecoy(pos, row.duration)
		for _, c in EnemyService.candidates() do
			if (Vector3.new(c.x, c.y, c.z) - pos).Magnitude <= row.radius then
				EnemyService.applyStatus(c.id, "taunt", row.duration, { src = decoy })
			end
		end
		target = pos
	end
	Cooldowns.start(book, kind, now, row.cd)
	Net.fire("GadgetResult", player, { kind = kind, ok = true, target = target, cd = row.cd })
	-- others see the smoke, drone and decoy as an ability burst
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.fire("GadgetResult", other, { kind = kind, ok = true, target = target, by = player.UserId })
		end
	end
end

---------------------------------------------------------------------------

function GearService.init()
	-- profile in: the hero takes its saved level, powers, wallet and gear
	DataService.Loaded:Connect(function(player, profile)
		local hero = HeroService.get(player)
		if hero then
			HeroService.applyProfile(hero, ProfileSchema.active(profile), profile.currency)
		end
		GearService.refresh(player)
	end)
	DataService.onBeforeSave(function(player, profile)
		local hero = HeroService.get(player)
		if hero then
			HeroService.writeBack(hero, ProfileSchema.active(profile))
		end
	end)
	-- a new body gets the look again, and again once the player's avatar is on it (AvatarService)
	HeroService.Spawned:Connect(function(hero)
		if hero.player and DataService.get(hero.player) then
			local profile = DataService.get(hero.player) :: any
			GearService.showLook(hero.player, profile, ProfileSchema.active(profile))
		end
	end)
	AvatarService.Ready:Connect(function(player: Player)
		local profile = DataService.get(player)
		if profile then
			GearService.showLook(player, profile, ProfileSchema.active(profile))
		end
	end)
	HeroService.Leveled:Connect(function(hero)
		if hero.player then
			DataService.changed(hero.player)
		end
	end)
	HeroService.SecondWind:Connect(function(hero)
		if hero.player then
			Net.fire("Toast", hero.player, { id = "secondWind" })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		gadgetBooks[player] = nil
		streetOn[player] = nil
	end)

	Net.on("GearEquip", function(player, id: number, slot: number)
		run(player, function(profile, char)
			local ok, reason = Inventory.equip(Config, profile, char, id, slot)
			if ok and id ~= 0 then
				Analytics.step(player, "Combat", "gear_equip")
			end
			return ok, reason
		end)
	end)
	Net.on("GearUpgrade", function(player, id: number)
		run(player, function(profile)
			local ok, reason, cost = Inventory.upgrade(Config, profile, id)
			local piece = ok and Inventory.find(profile, id)
			if piece then
				Analytics.event(player, "gear_upgrade", 1, { piece.tier, piece.up, cost })
				Analytics.step(player, "Combat", "gear_upgrade")
			end
			return ok, reason, { cost = cost }
		end)
	end)
	Net.on("GearSalvage", function(player, ids: { number })
		run(player, function(profile)
			local ok, reason, dust = Inventory.salvage(Config, profile, ids)
			return ok, reason, { dust = dust }
		end)
	end)
	Net.on("GearRetune", function(player, id: number, index: number)
		run(player, function(profile)
			local ok, reason, cost = Inventory.retune(Config, rng, profile, id, index)
			if ok then
				local hero = HeroService.get(player)
				if hero then
					hero.credits = profile.currency.credits + profile.currency.banked
				end
			end
			return ok, reason, { cost = cost }
		end)
	end)
	Net.on("StyleApply", function(player, slot: number, styleId: number)
		run(player, function(profile, char)
			return Inventory.showStyle(Config, profile, char, slot, styleId)
		end)
	end)
	Net.on("GadgetUse", useGadget)
end

return GearService
