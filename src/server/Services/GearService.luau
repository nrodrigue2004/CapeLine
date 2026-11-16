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
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local MoveGuard = require(script.Parent.MoveGuard)
local LookService = require(script.Parent.LookService)

local GearService = {}

local G = Config.Gear
local busy: { [Player]: boolean } = {}
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
	LookService.apply(player, Inventory.shownStyles(profile, char))
	DataService.changed(player)
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
		table.insert(out, stored)
	end
	if Config.Loot.sources[source].boss then
		profile.stats.bossesJoined += 1
	end
	if #out > 0 then
		DataService.changed(player)
		DataService.saveSoon(player)
	end
	return out
end

-- Run one gear request under the profile's lock; fn returns ok, reason, extra
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
	-- a new body gets the look again
	HeroService.Spawned:Connect(function(hero)
		if hero.player and DataService.get(hero.player) then
			local profile = DataService.get(hero.player) :: any
			LookService.apply(hero.player, Inventory.shownStyles(profile, ProfileSchema.active(profile)))
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
	end)

	Net.on("GearEquip", function(player, id: number, slot: number)
		run(player, function(profile, char)
			return Inventory.equip(Config, profile, char, id, slot)
		end)
	end)
	Net.on("GearUpgrade", function(player, id: number)
		run(player, function(profile)
			local ok, reason, cost = Inventory.upgrade(Config, profile, id)
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
