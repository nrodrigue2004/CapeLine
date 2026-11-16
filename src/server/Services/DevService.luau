-- DevService: Studio test commands from the Dev panel. Every command is refused outside Studio, so live
-- servers never run them. Commands: bots n, clearbots, drones n, cleardrones, spawner 0/1, god 0/1,
-- class 1-4, level n, heal, style 0/1 (Comic/Anime).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local LoadBots = require(script.Parent.LoadBots)

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
	level = function(_, hero, level)
		HeroService.setLevel(hero, level)
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
