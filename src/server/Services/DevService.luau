-- DevService: Studio test commands from the Dev panel. Every command is refused outside Studio, so live
-- servers never run them. Commands: bots n, clearbots, drones n, robot 1-6 (3 of that kind), cleardrones,
-- spawner 0/1, god 0/1, class 1-4, level n, heal, style 0/1 (Comic/Anime), points n (bonus Skill Points),
-- meter (fill Awakening), respec (no cooldown), loot 1-8 (roll a drop source at the hero's level), renown n,
-- credits n, dust n, save (save now), map (every beacon and safehouse found), wipe (start over as a new player).

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
