-- HeroService: one Hero record per player, and per load-test bot (spec: Stats, Classes, Loadout rules).
-- The hero's level, class, power set, movement styles, loadout, cooldowns and health live here on the
-- server; the client gets a copy through HeroState and player attributes. Saves arrive in M3, so every
-- hero starts at level 1 for now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local HeroService = {}

export type Hero = {
	id: number,
	player: Player?,
	bot: any?,
	name: string,
	level: number,
	classId: string,
	setId: string,
	fxStyle: string, -- "Comic" or "Anime": how this hero's powers look to everyone
	styles: { [string]: boolean },
	loadout: { basic: string, skills: { string } },
	cooldowns: Cooldowns.Book,
	health: number,
	maxHealth: number,
	alive: boolean,
	lastDamaged: number,
	hitCount: number, -- Blaster Overcharge: every 5th hit
	god: boolean,
}

local heroes: { [number]: Hero } = {}
local byPlayer: { [Player]: Hero } = {}

HeroService.Spawned = Signal.new() -- (hero) a player's character spawned or respawned
HeroService.Defeated = Signal.new() -- (hero, source)
HeroService.Removed = Signal.new() -- (hero)

local function stylesFor(level: number): { [string]: boolean }
	local s = {}
	for style, unlock in Config.Move.styleUnlockLevel do
		s[style] = level >= unlock or (Config.Dev.unlockAllStyles and style == "flight")
	end
	return s
end

local function newHero(id: number, name: string, player: Player?, bot: any?): Hero
	local level = 1
	local classId = Config.Classes.default
	local maxHealth = Formulas.health(Config, level, 0, classId)
	return {
		id = id,
		player = player,
		bot = bot,
		name = name,
		level = level,
		classId = classId,
		setId = "Volt",
		fxStyle = "Comic",
		styles = stylesFor(level),
		loadout = {
			basic = Config.Abilities.defaultLoadout.basic,
			skills = table.clone(Config.Abilities.defaultLoadout.skills),
		},
		cooldowns = Cooldowns.new(),
		health = maxHealth,
		maxHealth = maxHealth,
		alive = true,
		lastDamaged = 0,
		hitCount = 0,
		god = false,
	}
end

function HeroService.power(hero: Hero): number
	return Formulas.power(Config, hero.level, 0)
end

function HeroService.get(player: Player): Hero?
	return byPlayer[player]
end

function HeroService.byId(id: number): Hero?
	return heroes[id]
end

function HeroService.all(): { [number]: Hero }
	return heroes
end

local function humanoidOf(hero: Hero): Humanoid?
	local player = hero.player
	local char = player and player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function HeroService.rootPart(hero: Hero): BasePart?
	local player = hero.player
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- World position, or nil when the hero has no body right now
function HeroService.position(hero: Hero): Vector3?
	if hero.bot then
		return hero.bot.position
	end
	local root = HeroService.rootPart(hero)
	return root and root.Position
end

function HeroService.sendState(hero: Hero)
	local player = hero.player
	if not player then
		return
	end
	player:SetAttribute("Level", hero.level)
	player:SetAttribute("Class", hero.classId)
	player:SetAttribute("PowerSet", hero.setId)
	player:SetAttribute("FxStyle", hero.fxStyle)
	Net.fire("HeroState", player, {
		level = hero.level,
		classId = hero.classId,
		setId = hero.setId,
		fxStyle = hero.fxStyle,
		power = HeroService.power(hero),
		maxHealth = hero.maxHealth,
		styles = hero.styles,
		loadout = hero.loadout,
	})
end

-- Recompute health and styles after a level, class or gear change
function HeroService.refresh(hero: Hero)
	local frac = if hero.maxHealth > 0 then hero.health / hero.maxHealth else 1
	hero.maxHealth = Formulas.health(Config, hero.level, 0, hero.classId)
	hero.health = math.max(1, math.floor(hero.maxHealth * frac + 0.5))
	hero.styles = stylesFor(hero.level)
	local hum = humanoidOf(hero)
	if hum then
		hum.MaxHealth = hero.maxHealth
		hum.Health = hero.health
	end
	HeroService.sendState(hero)
end

function HeroService.setClass(hero: Hero, classId: string)
	if Config.Classes[classId] then
		hero.classId = classId
		HeroService.refresh(hero)
	end
end

function HeroService.setLevel(hero: Hero, level: number)
	hero.level = math.clamp(math.floor(level), 1, Config.Stats.levelCap)
	HeroService.refresh(hero)
end

function HeroService.setFxStyle(hero: Hero, style: string)
	if style == "Comic" or style == "Anime" then
		hero.fxStyle = style
		HeroService.sendState(hero)
	end
end

-- All damage to heroes goes through here (enemy shots now, PvP from M8)
function HeroService.damage(hero: Hero, amount: number, source: any?)
	if not hero.alive or amount <= 0 then
		return
	end
	hero.lastDamaged = os.clock()
	if hero.god then
		return
	end
	hero.health = math.max(0, hero.health - amount)
	local hum = humanoidOf(hero)
	if hum then
		hum.Health = hero.health
	end
	if hero.health <= 0 then
		-- M1: straight to Defeated and the Roblox respawn (5 s). The Downed state arrives in M8.
		hero.alive = false
		HeroService.Defeated:Fire(hero, source)
		if hero.bot then
			task.delay(Config.Stats.respawnTime, function()
				if heroes[hero.id] == hero then
					hero.health = hero.maxHealth
					hero.alive = true
				end
			end)
		elseif hum then
			hum.Health = 0
		end
	end
end

function HeroService.addBot(id: number, name: string, bot: any): Hero
	local hero = newHero(id, name, nil, bot)
	heroes[id] = hero
	return hero
end

function HeroService.remove(hero: Hero)
	heroes[hero.id] = nil
	if hero.player then
		byPlayer[hero.player] = nil
	end
	HeroService.Removed:Fire(hero)
end

-- The list EnemySim reads every tick
local simList = {}
function HeroService.simHeroes(): { any }
	table.clear(simList)
	for _, hero in heroes do
		local pos = HeroService.position(hero)
		if pos then
			table.insert(simList, { id = hero.id, x = pos.X, y = pos.Y, z = pos.Z, alive = hero.alive })
		end
	end
	return simList
end

local function onCharacter(player: Player, char: Model)
	local hero = byPlayer[player]
	if not hero then
		return
	end
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hero.health = hero.maxHealth
	hero.alive = true
	hero.lastDamaged = 0
	Cooldowns.clear(hero.cooldowns)
	hum.MaxHealth = hero.maxHealth
	hum.Health = hero.maxHealth
	hum.WalkSpeed = Config.Move.run.speed
	hum.UseJumpPower = true
	hum.JumpPower = 0 -- Leap replaces the jump; this also hides the default touch jump button
	hum.BreakJointsOnDeath = false
	hum.Died:Connect(function()
		if hero.alive then
			hero.alive = false
			hero.health = 0
			HeroService.Defeated:Fire(hero, nil)
		end
	end)
	HeroService.sendState(hero)
	HeroService.Spawned:Fire(hero)
end

function HeroService.init()
	Players.RespawnTime = Config.Stats.respawnTime
	local function added(player: Player)
		local hero = newHero(player.UserId, player.DisplayName, player, nil)
		heroes[hero.id] = hero
		byPlayer[player] = hero
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local hero = byPlayer[player]
		if hero then
			HeroService.remove(hero)
		end
	end)
	-- Out-of-combat regen (Decisions.md, 2026-11-16)
	task.spawn(function()
		local step = 0.25
		while true do
			task.wait(step)
			local now = os.clock()
			for _, hero in heroes do
				if
					hero.alive
					and hero.health < hero.maxHealth
					and now - hero.lastDamaged >= Config.Stats.regen.delay
				then
					hero.health = math.min(
						hero.maxHealth,
						hero.health + hero.maxHealth * Config.Stats.regen.perSecond * step
					)
					local hum = humanoidOf(hero)
					if hum then
						hum.Health = hero.health
					end
				end
			end
		end
	end)
	if RunService:IsStudio() then
		print("[HeroService] Studio: Flight unlocked for every hero (Config.Dev.unlockAllStyles)")
	end
end

return HeroService
