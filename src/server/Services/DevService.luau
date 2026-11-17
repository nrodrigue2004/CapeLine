-- DevService: Studio test commands from the Dev panel. Every command is refused outside Studio, so live
-- servers never run them. Commands: bots n, clearbots, drones n, robot 1-6 (3 of that kind), cleardrones,
-- spawner 0/1, god 0/1, class 1-4, level n, heal, style 0/1 (Comic/Anime), points n (bonus Skill Points),
-- meter (fill Awakening), respec (no cooldown), loot 1-8 (roll a drop source at the hero's level), renown n,
-- credits n, dust n, save (save now), map (every beacon and safehouse found), wipe (start over as a new player: the creator then the opening), wreck n (structure damage
-- around the hero, default 3000), repair (every building back), flip (every vehicle near the hero),
-- incident 1-24 (that template next to the hero), clearincidents, event 1-12, boss (land the next world
-- boss in 3 s), bosskill (the boss to 1 HP), contract (finish the first accepted contract), clock 0-3
-- (day, dusk, night, dawn), side 0/1 (hero or villain, for this session only).
-- 2026-11-17: heroic 0/1 (the incidents, events and contracts the Dev panel starts are Heroic), contractstart
-- 1-12 (take that contract type here, no board).
-- M9: creator (open the creator to remake this hero), hq (enter your HQ), hqlevel n, away n (offline drones
-- for n hours away), pieces (unlock every creator piece), buy n (test-purchase shop item n with a fixed
-- receipt id: the second time grants nothing), legacy (the level cap and retire at HQ next).
-- Lore step 2: street 0/1 (the street outfit off or on, CreatorService.streetOutfit).
-- Lore step 3: prologue 0/1 (the Ceremony prologue from its first beat as the Vigil or the Syndicate), opening n
-- (0 replays it; 1 to 13 jumps to that beat).
-- Lore step 4: fake 1-3 (Radiant, Bulwark or Skylance 25 studs in front of the hero, at the hero's level), twin
-- (an evil twin of your own hero there).
-- Lore step 5: missionas n (mission n // 10 as the Vigil, n % 10 = 0, or the Syndicate, 1; the missions before it
-- cleared and its level met), missionstep n (jump to stage n of the running mission).
-- Hero MMO: nemesis 0/1 (your nemesis ambushes you now / your Intel is full: the Showdown opens).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local AbilityRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityRules"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local LoadBots = require(script.Parent.LoadBots)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local BuildingService = require(script.Parent.BuildingService)
local VehicleService = require(script.Parent.VehicleService)
local IncidentService = require(script.Parent.IncidentService)
local ContractService = require(script.Parent.ContractService)
local EventService = require(script.Parent.EventService)
local BossService = require(script.Parent.BossService)
local ClockService = require(script.Parent.ClockService)
local StoryService = require(script.Parent.StoryService)
local OpeningService = require(script.Parent.OpeningService)
local MissionService = require(script.Parent.MissionService)
local NemesisService = require(script.Parent.NemesisService)
local QuestService = require(script.Parent.QuestService)
local FlagService = require(script.Parent.FlagService)
local DeathService = require(script.Parent.DeathService)
local FameService = require(script.Parent.FameService)
local CityBuilder = require(script.Parent.CityBuilder)
local SafehouseService = require(script.Parent.SafehouseService)
local CreatorService = require(script.Parent.CreatorService)
local HqService = require(script.Parent.HqService)
local PurchaseService = require(script.Parent.PurchaseService)
local NewsService = require(script.Parent.NewsService) -- lore step 7
local ShopRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopRules"))
local CreatorRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CreatorRules"))
local ProfileSchema = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProfileSchema"))
local OpeningPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OpeningPlan"))
local StoryPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoryPlan"))

local DevService = {}

local forceHeroic = false -- the Dev panel's Heroic switch for what it starts

local commands: { [string]: (player: Player, hero: any, value: number) -> () } = {
	bots = function(_, _, n)
		LoadBots.spawn(if n > 0 then n else Config.Dev.loadBots.max)
	end,
	clearbots = function()
		LoadBots.clear()
	end,
	drones = function(_, hero, n)
		local pos = HeroService.position(hero)
		if pos then
			EnemyService.spawnAround(pos, math.clamp(n, 1, 30))
		end
	end,
	robot = function(_, hero, index)
		local kind = Config.Enemies.order[index]
		local pos = HeroService.position(hero)
		if kind and pos then
			EnemyService.spawnAround(pos, 3, kind)
		end
	end,
	fake = function(_, hero, index)
		local kind = ({ "Radiant", "Bulwark", "Skylance" })[index]
		local pos = HeroService.position(hero)
		if kind and pos then
			local cfg = Config.Enemies[kind]
			EnemyService.spawnAt(kind, pos + Vector3.new(0, if cfg.flies then 14 else 0, -25), hero.level)
		end
	end,
	twin = function(player, hero)
		local pos = HeroService.position(hero)
		if pos then
			EnemyService.spawnTwin(player, pos + Vector3.new(0, 14, -25), hero.level)
		end
	end,
	points = function(_, hero, n)
		hero.bonusPoints += n
		HeroService.sendState(hero)
	end,
	meter = function(_, hero)
		hero.meter.value = Config.Abilities.awakening.max
		HeroService.sendStatus(hero)
	end,
	respec = function(_, hero)
		hero.respecAt = 0
		HeroService.sendState(hero)
	end,
	cleardrones = function()
		EnemyService.clear()
	end,
	spawner = function(_, _, on)
		EnemyService.populate = on ~= 0
	end,
	god = function(_, hero, on)
		hero.god = on ~= 0
	end,
	-- a path by its index in Abilities.sets: its archetype, its starter kit on both loadouts (no refund)
	class = function(_, hero, index)
		local set = Config.Abilities.sets[index]
		if not set or not AbilityRules.pathReady(Config, set) then
			return
		end
		local ranks, loadout = AbilityRules.starter(Config, set)
		for id, r in hero.ranks do
			local row = Config.Abilities.list[id]
			if row and row.set == set then
				ranks[id] = math.max(ranks[id] or 0, r)
			end
		end
		hero.ranks, hero.mods = ranks, {}
		hero.loadouts = { loadout, table.clone(loadout) }
		hero.loadouts[2].skills = table.clone(loadout.skills)
		hero.loadoutIndex = 1
		hero.loadout = hero.loadouts[1]
		hero.setId, hero.startSet = set, set
		HeroService.setClass(hero, AbilityRules.archetypeOf(Config, set) or Config.Classes.default)
	end,
	mobility = function(_, hero, index)
		local m = Config.Move.mobilityOrder[index]
		if m then
			HeroService.setMobility(hero, m)
		end
	end,
	level = function(player, hero, level)
		HeroService.setLevel(hero, level)
		DataService.saveSoon(player)
	end,
	loot = function(player, hero, index)
		local source = Config.Loot.order[index]
		if source then
			GearService.grant(player, source, hero.level)
		end
	end,
	renown = function(player, _, n)
		EconomyService.addRenown(player, n)
	end,
	credits = function(player, _, n)
		EconomyService.addCredits(player, n)
	end,
	dust = function(player, _, n)
		EconomyService.addDust(player, n)
	end,
	save = function(player)
		print("[Dev] save:", DataService.save(player, false))
	end,
	map = function(player)
		-- discover every beacon and visit every safehouse (fast travel testing)
		local profile = DataService.get(player)
		if profile then
			local c = profile.characters[profile.active]
			c.beacons = 2 ^ #Config.World.beacons - 1
			c.safehouses = 2 ^ #Config.World.safehouses - 1
			DataService.changed(player)
		end
	end,
	wipe = function(player, hero)
		local profile = DataService.resetProfile(player)
		if profile then
			HeroService.applyProfile(hero, profile.characters[1], profile.currency)
			GearService.refresh(player)
		end
		-- a brand new player: the creator first, then the opening (lore step 2)
		task.delay(0.5, CreatorService.createFirst, player)
	end,
	heal = function(_, hero)
		hero.health = hero.maxHealth
		HeroService.refresh(hero)
	end,
	wreck = function(_, hero, n)
		local pos = HeroService.position(hero)
		if pos then
			BuildingService.hit(pos, 30, if n > 0 then n else Config.Destruction.superStruct, 1)
		end
	end,
	repair = function()
		BuildingService.repairAll()
		VehicleService.resetAll()
	end,
	flip = function(_, hero)
		local pos = HeroService.position(hero)
		if pos then
			VehicleService.hit(pos, 60)
		end
	end,
	incident = function(_, hero, n)
		local tid = Config.Incidents.order[n]
		if tid then
			print("[Dev] incident", tid, IncidentService.force(hero, tid, forceHeroic))
		end
	end,
	clearincidents = function()
		IncidentService.clearAll()
	end,
	event = function(_, _, n)
		print("[Dev] event", n, EventService.force(n, forceHeroic))
	end,
	heroic = function(_, _, on)
		forceHeroic = on ~= 0
	end,
	contractstart = function(player, _, n)
		print("[Dev] contract", Config.Contracts.order[n], ContractService.forceStart(player, n, forceHeroic))
	end,
	boss = function()
		BossService.startNow()
	end,
	bosskill = function()
		BossService.weaken()
	end,
	contract = function(player)
		ContractService.finishFirst(player)
	end,
	clock = function(_, _, n)
		ClockService.jump(n)
	end,
	side = function(_, hero, villain)
		hero.side = if villain ~= 0 then "villain" else "hero"
	end,
	-- M7: the story
	opening = function(player, _, stepNum)
		-- 0 replays the Ceremony prologue from the start; 1 to 13 jumps to that beat of a running one
		if stepNum == 0 or not OpeningService.running(player) then
			OpeningService.start(player, true)
		end
		local name = OpeningPlan.STEPS[stepNum]
		if name then
			OpeningService.jump(player, name)
		end
	end,
	-- lore step 3: the prologue from its first beat as the Vigil (0) or the Dread Syndicate (1)
	prologue = function(player, hero, villain)
		local side = if villain ~= 0 then "villain" else "hero"
		OpeningService.stop(player)
		hero.side = side
		StoryService.setSide(player, side)
		OpeningService.start(player, true)
	end,
	mission = function(player, _, num)
		local ok, why = MissionService.enter(player, num)
		print("[Dev] mission", num, ok, why)
	end,
	-- lore step 5: start mission n as a side (value n * 10 + 0 the Vigil, 1 the Syndicate), the missions before
	-- it cleared and the level met, and jump to stage n of the running mission
	missionas = function(player, hero, value)
		local num, villain = value // 10, value % 10
		local m = Config.Story.missions[num]
		local story = StoryService.story(player)
		if not m or m.opening or not story then
			return
		end
		MissionService.leave(player)
		local side = if villain ~= 0 then "villain" else "hero"
		StoryService.setSide(player, side)
		story.opening = 1
		for n = 1, num - 1 do
			StoryPlan.clear(story, n)
		end
		if hero.level < m.minLevel then
			HeroService.setLevel(hero, m.minLevel)
		end
		StoryService.changed(player)
		task.delay(1.2, function()
			local ok, why = MissionService.enter(player, num)
			print("[Dev] mission", num, side, ok, why)
		end)
	end,
	missionstep = function(player, _, n)
		MissionService.jumpStage(player, n)
	end,
	finishstep = function(player)
		MissionService.skipStep(player)
		QuestService.skipStep(player)
	end,
	leavemission = function(player)
		MissionService.leave(player)
	end,
	quest = function(player, _, num)
		QuestService.start(player, num)
	end,
	actdone = function(player, hero)
		-- every Act 1 mission cleared (choices stay as they are)
		local story = StoryService.story(player)
		if story then
			story.opening = 1
			story.missions = 2 ^ #Config.Story.missions - 1
			if hero.level < 8 then
				HeroService.setLevel(hero, 8)
			end
			StoryService.changed(player)
		end
	end,
	resetstory = function(player)
		local c = StoryService.char(player)
		if c then
			c.story = ProfileSchema.newCharacter().story
			c.rep = { 0, 0, 0 }
			StoryService.changed(player)
		end
	end,
	-- M8: PvP and death
	downme = function(_, hero)
		DeathService.downNow(hero)
	end,
	pvp = function(_, hero, on)
		-- the flag regardless of the 5 s and 60 s rules (Studio only); level 10 first if needed
		if hero.level < Config.Pvp.minLevel then
			HeroService.setLevel(hero, Config.Pvp.minLevel)
		end
		local f = FlagService.flag(hero)
		f.on = on ~= 0
		f.setAt = -1e9
		f.pvpAt = -1e9
		FlagService.send(hero, true)
	end,
	crater = function(_, hero)
		for _, lm in CityBuilder.world.landmarks do
			if lm.id == Config.Pvp.crater.id then
				local x, z = lm.centre.x - lm.size / 2 - 30, lm.centre.z
				SafehouseService.place(hero, CFrame.new(x, CityBuilder.heightAt(x, z) + 4, z))
			end
		end
	end,
	fame = function(player, _, n)
		for _ = 1, math.max(1, n) do
			FameService.add(player, "mission")
		end
	end,
	style = function(_, hero, anime)
		HeroService.setFxStyle(hero, if anime ~= 0 then "Anime" else "Comic")
	end,
	-- M9
	street = function(player, _, on)
		CreatorService.streetOutfit(player, on ~= 0)
	end,
	creator = function(player)
		local profile = DataService.get(player)
		if profile then
			ProfileSchema.active(profile).created = 0
			CreatorService.open(player, "first")
		end
	end,
	hq = function(player, hero)
		HqService.enter(player, hero.side)
	end,
	hqlevel = function(player, _, n)
		local profile = DataService.get(player)
		if profile then
			ProfileSchema.active(profile).hq.level = math.clamp(n, 1, 6)
			DataService.changed(player)
		end
	end,
	away = function(player, _, hours)
		local profile = DataService.get(player)
		if profile then
			ProfileSchema.active(profile).hq.droneAt = os.time() - math.max(1, hours) * 3600
			HqService.payDrones(player, profile)
		end
	end,
	pieces = function(player)
		local profile = DataService.get(player)
		if profile then
			for _, p in CreatorRules.index(Config).list do
				CreatorRules.grant(profile, p)
			end
			DataService.changed(player)
		end
	end,
	buy = function(player, _, n)
		local key = ShopRules.keys(Config)[n]
		if key then
			local ok = PurchaseService.replay(player, key, "dev-" .. key)
			Net.fire("Toast", player, { id = "devBuy", key = key, ok = ok })
		end
	end,
	legacy = function(_, hero)
		HeroService.setLevel(hero, Config.Stats.levelCap)
	end,
	nemesis = function(player, _, what)
		NemesisService.dev(player, what)
	end,
	-- lore step 7: a sample news fact as you (1 boss flash, 2 boss down, 3 fake unmasked, 4 streak, 5 heist,
	-- 6 Act 1 mission)
	news = function(player, _, what)
		NewsService.dev(player, what)
	end,
}

function DevService.init()
	Net.on("DevCommand", function(player, name: string, value: number?)
		if not RunService:IsStudio() then
			return
		end
		local hero = HeroService.get(player)
		local fn = commands[name]
		if hero and fn then
			fn(player, hero, value or 0)
			print(string.format("[Dev] %s %s %s", player.Name, name, tostring(value)))
		end
	end)
end

return DevService
