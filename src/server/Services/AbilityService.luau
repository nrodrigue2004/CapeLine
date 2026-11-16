-- AbilityService: ranks, mods, respec and loadouts (spec: Services > Abilities "Cooldowns, ranks, mods, budget
-- check"; Remote events Hero.Loadout, Skills.Rank, Skills.Mod, Skills.Respec). Every request is checked
-- here against AbilityRules; the client's loadout screen only asks.
-- Loadouts change anywhere out of combat until safehouses exist (M4); respec is free with a 10-minute
-- cooldown (spec) and refunds the Credits ranks cost into the bank (Decisions.md), so builds are free to try.
-- Ranks cost Skill Points and Credits (spec: Sinks); Config.Dev.freeRankCredits waives Credits in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))

local HeroService = require(script.Parent.HeroService)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)

local AbilityService = {}

local A = Config.Abilities

local function notice(hero: any, ok: boolean, reason: string?)
	if hero.player then
		Net.fire("AbilityNotice", hero.player, { ok = ok, reason = reason })
	end
end

-- The ranked numbers of an ability for this hero
function AbilityService.effective(hero: any, id: string): { [string]: any }
	return HeroService.effective(hero, id)
end

function AbilityService.rank(hero: any, id: string): (boolean, string?)
	local free = Config.Dev.freeRankCredits and game:GetService("RunService"):IsStudio()
	local ok, reason, _, credits = AbilityRules.canRank(Config, hero, id, free)
	if not ok then
		return false, reason
	end
	if not EconomyService.spend(hero, credits) then
		return false, "credits"
	end
	hero.ranks[id] = (hero.ranks[id] or 0) + 1
	if hero.player then
		DataService.saveSoon(hero.player)
	end
	return true, nil
end

function AbilityService.pickMod(hero: any, id: string, pick: number): (boolean, string?)
	local row = A.list[id]
	if not row or not row.mods or not row.mods[pick] then
		return false, "no mod"
	end
	local need = if row.slot == "super" then 2 else 3
	if (hero.ranks[id] or 0) < need then
		return false, "rank"
	end
	hero.mods[id] = pick -- changing the pick later is free (players try builds without fear)
	return true, nil
end

function AbilityService.respec(hero: any): (boolean, string?)
	local now = os.clock()
	if now < hero.respecAt then
		return false, "cooldown"
	end
	if HeroService.inCombat(hero) then
		return false, "combat"
	end
	local refund = AbilityRules.creditsSpent(Config, hero.ranks)
	local ranks, loadout = AbilityRules.starter(Config, hero.setId)
	-- keep every set's free starters learned
	for _, set in A.sets do
		if AbilityRules.setUnlocked(Config, hero.level, set) then
			for id, r in (AbilityRules.starter(Config, set)) do
				ranks[id] = math.max(ranks[id] or 0, r)
			end
		end
	end
	EconomyService.refund(hero, refund)
	hero.ranks = ranks
	hero.mods = {}
	hero.loadout = loadout
	hero.loadouts = { loadout, table.clone(loadout) }
	hero.loadoutIndex = 1
	hero.respecAt = now + A.respecCooldown
	Cooldowns.clear(hero.cooldowns)
	return true, nil
end

-- index 1 or 2; set and the picks as ability ids
function AbilityService.setLoadout(
	hero: any,
	index: number,
	set: string,
	skills: { string },
	super: string?
): (boolean, string?)
	if index == 2 and hero.level < A.secondLoadoutLevel then
		return false, "second loadout locked"
	end
	if HeroService.inCombat(hero) then
		return false, "combat"
	end
	-- a set's basic and two starter skills are learned free the first time it is unlocked and picked
	if AbilityRules.setUnlocked(Config, hero.level, set) then
		for _, id in A.starter[set] do
			hero.ranks[id] = math.max(hero.ranks[id] or 0, 1)
		end
		local basic = AbilityRules.basicOf(Config, set)
		if basic then
			hero.ranks[basic] = 1
		end
	end
	local loadout = { set = set, basic = AbilityRules.basicOf(Config, set), skills = skills, super = super }
	local ok, reason = AbilityRules.validate(Config, hero, loadout)
	if not ok then
		return false, reason
	end
	hero.loadouts[index] = loadout
	hero.loadoutIndex = index
	hero.loadout = loadout
	hero.setId = set
	if hero.player then
		DataService.saveSoon(hero.player)
	end
	return true, nil
end

local function num(n: number): string?
	if n == 0 then
		return nil
	end
	local row = A.byNum[n]
	return row and row.id
end

function AbilityService.init()
	Net.on("SkillsRank", function(player, n: number)
		local hero = HeroService.get(player)
		local id = num(n)
		if hero and id then
			local ok, reason = AbilityService.rank(hero, id)
			notice(hero, ok, reason)
			HeroService.sendState(hero)
		end
	end)
	Net.on("SkillsMod", function(player, n: number, pick: number)
		local hero = HeroService.get(player)
		local id = num(n)
		if hero and id then
			local ok, reason = AbilityService.pickMod(hero, id, pick)
			notice(hero, ok, reason)
			HeroService.sendState(hero)
		end
	end)
	Net.on("SkillsRespec", function(player)
		local hero = HeroService.get(player)
		if hero then
			local ok, reason = AbilityService.respec(hero)
			notice(hero, ok, reason)
			HeroService.sendState(hero)
		end
	end)
	Net.on(
		"HeroLoadout",
		function(
			player,
			index: number,
			setNum: number,
			s1: number,
			s2: number,
			s3: number,
			s4: number,
			sup: number
		)
			local hero = HeroService.get(player)
			local set = A.sets[setNum]
			if not hero or not set then
				return
			end
			local skills = {}
			for _, n in { s1, s2, s3, s4 } do
				local id = num(n)
				if id then
					table.insert(skills, id)
				end
			end
			local ok, reason = AbilityService.setLoadout(hero, index, set, skills, num(sup))
			notice(hero, ok, reason)
			HeroService.sendState(hero)
		end
	)
	Net.on("Awaken", function(player)
		local hero = HeroService.get(player)
		if hero then
			HeroService.awaken(hero)
		end
	end)
end

return AbilityService
