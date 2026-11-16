-- DevService: Studio test commands from the Dev panel. Every command is refused outside Studio, so live
-- servers never run them. Commands: bots n, clearbots, drones n, robot 1-6 (3 of that kind), cleardrones,
-- spawner 0/1, god 0/1, class 1-4, level n, heal, style 0/1 (Comic/Anime), points n (bonus Skill Points),
-- meter (fill Awakening), respec (no cooldown), loot 1-8 (roll a drop source at the hero's level), renown n,
-- credits n, dust n, save (save now), map (every beacon and safehouse found), wipe (start over as a new player), wreck n (structure damage
-- around the hero, default 3000), repair (every building back), flip (every vehicle near the hero),
-- incident 1-10 (that template next to the hero), clearincidents, event 1-6, boss (land the next world
-- boss in 3 s), bosskill (the boss to 1 HP), contract (finish the first accepted contract), clock 0-3
-- (day, dusk, night, dawn), side 0/1 (hero or villain, for this session only).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
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
local QuestService = require(script.Parent.QuestService)
local ProfileSchema = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProfileSchema"))
local OpeningPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OpeningPlan"))

local DevService = {}

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
	class = function(_, hero, index)
		local id = Config.Classes.order[index]
		if id then
			HeroService.setClass(hero, id)
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
			print("[Dev] incident", tid, IncidentService.force(hero, tid))
		end
	end,
	clearincidents = function()
		IncidentService.clearAll()
	end,
	event = function(_, _, n)
		print("[Dev] event", n, EventService.force(n))
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
		-- 0 replays the opening from the start; 1 to 9 jumps to that step of a running one
		if stepNum == 0 or not OpeningService.running(player) then
			OpeningService.start(player, true)
		end
		local name = OpeningPlan.STEPS[stepNum]
		if name then
			OpeningService.jump(player, name)
		end
	end,
	mission = function(player, _, num)
		local ok, why = MissionService.enter(player, num)
		print("[Dev] mission", num, ok, why)
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
	style = function(_, hero, anime)
		HeroService.setFxStyle(hero, if anime ~= 0 then "Anime" else "Comic")
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
