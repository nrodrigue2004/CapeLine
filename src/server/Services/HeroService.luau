-- HeroService: one Hero record per player, and per load-test bot (spec: Stats, Classes, Loadout rules).
-- The hero's level, class, power set, movement styles, ranks, loadout, cooldowns, buffs, Awakening meter and
-- health live here on the server; the client gets a copy through HeroState (rare changes), HeroStatus
-- (buffs and the meter, on change) and player attributes (what other players draw). Saves arrive in M3, so
-- every hero starts at level 1 for now.
-- Every hit on a hero goes through HeroService.damage: parry, class and buff mitigation, Anchor, shields.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Status = require(Shared:WaitForChild("Status"))
local Awakening = require(Shared:WaitForChild("Awakening"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))

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
	loadout: AbilityRules.Loadout,
	loadouts: { AbilityRules.Loadout }, -- 2 slots; the second opens at level 15
	loadoutIndex: number,
	ranks: { [string]: number },
	mods: { [string]: number },
	bonusPoints: number, -- story Skill Points (Act 1 choices, M7)
	credits: number, -- M3 brings the real wallet
	respecAt: number,
	cooldowns: Cooldowns.Book,
	recast: AbilityRules.RecastState,
	status: Status.Book, -- buffs on the hero
	meter: Awakening.Meter,
	combo: { at: number, step: number }, -- Punch Combo and Blade Slash strings
	channel: any?, -- Freeze Beam or Thousand Cuts running
	lastCast: number,
	health: number,
	maxHealth: number,
	alive: boolean,
	lastDamaged: number,
	hitCount: number, -- Blaster Overcharge: every 5th hit
	god: boolean,
	meterDirty: boolean?,
}

local heroes: { [number]: Hero } = {}
local byPlayer: { [Player]: Hero } = {}

HeroService.Spawned = Signal.new() -- (hero) a player's character spawned or respawned
HeroService.Defeated = Signal.new() -- (hero, source)
HeroService.Removed = Signal.new() -- (hero)
HeroService.Parried = Signal.new() -- (hero, source) a hit was turned aside by Parry Stance
HeroService.Awakened = Signal.new() -- (hero)

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
	local ranks, loadout = AbilityRules.starter(Config, "Volt")
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
		loadout = loadout,
		loadouts = { loadout, table.clone(loadout) },
		loadoutIndex = 1,
		ranks = ranks,
		mods = {},
		bonusPoints = 0,
		credits = 0,
		respecAt = 0,
		cooldowns = Cooldowns.new(),
		recast = {},
		status = Status.new(),
		meter = Awakening.new(),
		combo = { at = 0, step = 0 },
		channel = nil,
		lastCast = 0,
		health = maxHealth,
		maxHealth = maxHealth,
		alive = true,
		lastDamaged = 0,
		hitCount = 0,
		god = false,
	}
end

-- Power with buffs (Rally Roar +10%)
function HeroService.power(hero: Hero): number
	local base = Formulas.power(Config, hero.level, 0)
	return base * (1 + Status.value(hero.status, "power", os.clock(), 0))
end

-- Run speed multiplier: Speedster +10%, Weightless +30%
function HeroService.speedMult(hero: Hero): number
	local class = Config.Classes[hero.classId]
	return (1 + (class.moveSpeed or 0)) * (1 + Status.value(hero.status, "speed", os.clock(), 0))
end

function HeroService.awakened(hero: Hero): boolean
	return Awakening.active(hero.meter, os.clock())
end

function HeroService.inCombat(hero: Hero): boolean
	local now = os.clock()
	return now - hero.lastDamaged < Config.Combat.outOfCombat
		or now - hero.lastCast < Config.Combat.outOfCombat
end

function HeroService.pointsLeft(hero: Hero): number
	return AbilityRules.pointsEarned(Config, hero.level, hero.bonusPoints)
		- AbilityRules.pointsSpent(Config, hero.ranks)
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
		loadouts = hero.loadouts,
		loadoutIndex = hero.loadoutIndex,
		ranks = hero.ranks,
		mods = hero.mods,
		points = HeroService.pointsLeft(hero),
		bonusPoints = hero.bonusPoints,
		credits = hero.credits,
		respecIn = math.max(0, hero.respecAt - os.clock()),
	})
end

-- Buff bits for the Aura attribute (other players draw these on the hero)
local AURA = {
	shield = 1,
	mitigation = 2,
	attackSpeed = 4,
	power = 8,
	speed = 16,
	parry = 32,
	resist = 64,
	zeroG = 128,
}
HeroService.AURA = AURA

-- Buffs, shield and the Awakening meter: to the owner (HeroStatus) and as attributes for everyone
function HeroService.sendStatus(hero: Hero)
	local now = os.clock()
	local buffs = {}
	local aura = 0
	for kind, bit in AURA do
		local e = Status.get(hero.status, kind, now)
		if e then
			buffs[kind] = { left = e.untilT - now, value = e.value }
			aura += bit
		end
	end
	local awake = Awakening.active(hero.meter, now)
	local player = hero.player
	if player then
		player:SetAttribute("Aura", aura)
		player:SetAttribute("Awakened", awake)
		Net.fire("HeroStatus", player, {
			meter = hero.meter.value,
			awakeLeft = if awake then hero.meter.untilT - now else 0,
			buffs = buffs,
		})
	end
end

-- A buff on the hero. kind: shield (value = points), mitigation, attackSpeed, power, speed, parry, resist.
function HeroService.buff(hero: Hero, kind: string, value: number, duration: number)
	Status.apply(hero.status, kind, duration, os.clock(), { value = value })
	if kind == "speed" then
		HeroService.applyWalkSpeed(hero)
		task.delay(duration + 0.05, function()
			HeroService.applyWalkSpeed(hero)
		end)
	end
	HeroService.sendStatus(hero)
	task.delay(duration + 0.05, function()
		if heroes[hero.id] == hero then
			HeroService.sendStatus(hero)
		end
	end)
end

function HeroService.heal(hero: Hero, amount: number)
	if not hero.alive then
		return
	end
	hero.health = math.min(hero.maxHealth, hero.health + amount)
	local hum = humanoidOf(hero)
	if hum then
		hum.Health = hero.health
	end
end

function HeroService.applyWalkSpeed(hero: Hero)
	local hum = humanoidOf(hero)
	if hum then
		hum.WalkSpeed = Config.Move.run.speed * HeroService.speedMult(hero)
	end
end

-- Add Awakening meter. kind: basicHit, skillHit, superHit, kill
function HeroService.gainMeter(hero: Hero, kind: string, count: number)
	local before = hero.meter.value
	Awakening.gain(Config, hero.meter, kind, count, os.clock())
	if hero.meter.value ~= before then
		hero.meterDirty = true
	end
end

function HeroService.awaken(hero: Hero): boolean
	if not hero.alive or not Awakening.start(Config, hero.meter, os.clock()) then
		return false
	end
	HeroService.Awakened:Fire(hero)
	HeroService.sendStatus(hero)
	task.delay(Config.Abilities.awakening.duration + 0.05, function()
		if heroes[hero.id] == hero then
			HeroService.sendStatus(hero)
		end
	end)
	return true
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

-- Damage taken after mitigation: Bruiser Stand Firm, Brace, Blizzard Dome resist, a Controller's Anchor
-- aura (allies within 25 studs take 8% less), then the shield.
function HeroService.mitigate(hero: Hero, amount: number, now: number): number
	local taken = amount
	local class = Config.Classes[hero.classId]
	if class.passive.id == "StandFirm" then
		taken *= 1 - class.passive.mitigation
	end
	taken *= 1 - Status.value(hero.status, "mitigation", now, 0)
	taken *= 1 - Status.value(hero.status, "resist", now, 0)
	local pos = HeroService.position(hero)
	if pos then
		local anchor = Config.Classes.Controller.passive
		for _, other in heroes do
			if other ~= hero and other.alive and other.classId == "Controller" then
				local op = HeroService.position(other)
				if op and (op - pos).Magnitude <= anchor.radius then
					taken *= 1 - anchor.mitigation
					break
				end
			end
		end
	end
	return Status.absorb(hero.status, taken, now)
end

-- All damage to heroes goes through here (enemy shots and slams now, PvP from M8)
function HeroService.damage(hero: Hero, amount: number, source: any?)
	if not hero.alive or amount <= 0 then
		return 0
	end
	local now = os.clock()
	hero.lastDamaged = now
	if Status.has(hero.status, "parry", now) and source and source.enemy then
		Status.remove(hero.status, "parry")
		HeroService.Parried:Fire(hero, source)
		HeroService.sendStatus(hero)
		return 0
	end
	local hadShield = Status.has(hero.status, "shield", now)
	amount = HeroService.mitigate(hero, amount, now)
	if hadShield then
		hero.meterDirty = true -- the shield bar changed
	end
	if hero.god or amount <= 0 then
		return 0
	end
	Awakening.hurt(Config, hero.meter, amount / math.max(1, hero.maxHealth), now)
	hero.meterDirty = true
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
	return amount
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
			local lx, lz = 0, -1
			local root = if hero.bot then nil else HeroService.rootPart(hero)
			if root then
				local look = root.CFrame.LookVector
				local l = math.sqrt(look.X * look.X + look.Z * look.Z)
				if l > 0.05 then
					lx, lz = look.X / l, look.Z / l
				end
			end
			table.insert(
				simList,
				{ id = hero.id, x = pos.X, y = pos.Y, z = pos.Z, alive = hero.alive, lx = lx, lz = lz }
			)
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
	hero.channel = nil
	Cooldowns.clear(hero.cooldowns)
	table.clear(hero.recast)
	hero.status = Status.new()
	hum.MaxHealth = hero.maxHealth
	hum.Health = hero.maxHealth
	hum.WalkSpeed = Config.Move.run.speed * HeroService.speedMult(hero)
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
	-- Out-of-combat regen (Decisions.md, 2026-11-16) and the meter push (4 Hz at most)
	task.spawn(function()
		local step = 0.25
		while true do
			task.wait(step)
			local now = os.clock()
			for _, hero in heroes do
				if hero.meterDirty then
					hero.meterDirty = false
					HeroService.sendStatus(hero)
				end
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
