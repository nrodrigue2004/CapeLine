-- HeroService: one Hero record per player, and per load-test bot (spec: Stats, Classes, Loadout rules).
-- The hero's level, class, power set, movement styles, ranks, loadout, cooldowns, buffs, Awakening meter and
-- health live here on the server; the client gets a copy through HeroState (rare changes), HeroStatus
-- (buffs and the meter, on change) and player attributes (what other players draw). Saves arrive in M3, so
-- every hero starts at level 1 for now.
-- Every hit on a hero goes through HeroService.damage: parry, class and buff mitigation, Anchor, shields.
-- M8: a player's PvE defeat goes to DeathService first (HeroService.downHandler: the Downed state); PvP
-- hits carry source.pvp. Crowd control on heroes (PvP stuns, roots, slows) lives in hero.status too and
-- rides HeroStatus to the owner, whose movement obeys it. Each hero has a PvP slot: its combat id is
-- HeroService.PVP_BASE + slot (CombatService targets flagged heroes by it).

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
	side: string, -- "hero" (League) or "villain" (Syndicate)
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
	-- M3: saved progress and gear
	xp: number,
	loaded: boolean, -- the profile has been applied (until then nothing is written back)
	stats: { [string]: number }, -- Might, Vitality, Focus, Precision, Resolve from gear
	gearScore: number,
	setDamage: { [string]: number }, -- power set -> 2-piece damage bonus
	gearMods: { [string]: { any } }, -- ability id -> 4-piece set changes
	perks: { [string]: boolean },
	gadget: string?,
	luckyCount: number, -- Lucky Strike: every 8th hit
	traveling: boolean, -- on a fast-travel flight: untargetable (BeaconService)
	safehouse: number?, -- the safehouse the hero stands in (SafehouseService)
	secondWindAt: number, -- Second Wind ready again (os.clock)
	scene: string?, -- "opening" or "mission": in a story scene (no incidents, contracts or world events)
	downed: boolean?, -- M8: Downed (PvE health hit 0): crawling, waiting for a revive
	pvpSlot: number, -- M8: combat id PVP_BASE + slot when flagged heroes are targets
}

local heroes: { [number]: Hero } = {}
local byPlayer: { [Player]: Hero } = {}
local bySlot: { [number]: Hero } = {}

HeroService.PVP_BASE = 65000 -- hero combat ids: above every robot (EnemySim) and target (50,000+) id
HeroService.MAX_SLOTS = 500

local function freeSlot(): number
	for i = 1, HeroService.MAX_SLOTS do
		if not bySlot[i] then
			return i
		end
	end
	return 0
end

-- The hero behind a combat id (PVP_BASE + slot), or nil
function HeroService.bySlot(combatId: number): Hero?
	return bySlot[combatId - HeroService.PVP_BASE]
end

-- DeathService: called when a player's health hits 0 from a PvE hit; returns true when it took over (Downed)
HeroService.downHandler = nil :: ((Hero, any?) -> boolean)?

HeroService.Spawned = Signal.new() -- (hero) a player's character spawned or respawned
HeroService.Defeated = Signal.new() -- (hero, source)
HeroService.Removed = Signal.new() -- (hero)
HeroService.Parried = Signal.new() -- (hero, source) a hit was turned aside by Parry Stance
HeroService.Awakened = Signal.new() -- (hero)
HeroService.SecondWind = Signal.new() -- (hero) the Second Wind perk saved this hero
HeroService.Leveled = Signal.new() -- (hero, gained)
HeroService.Supported = Signal.new() -- (hero, points) this hero healed or shielded an ally (boss support)

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
		side = "hero",
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
		xp = 0,
		loaded = false,
		stats = { Might = 0, Vitality = 0, Focus = 0, Precision = 0, Resolve = 0 },
		gearScore = 0,
		setDamage = {},
		gearMods = {},
		perks = {},
		gadget = nil,
		luckyCount = 0,
		traveling = false,
		safehouse = nil,
		secondWindAt = 0,
		downed = nil,
		pvpSlot = 0,
	}
end

local function takeSlot(hero: Hero)
	local slot = freeSlot()
	hero.pvpSlot = slot
	if slot > 0 then
		bySlot[slot] = hero
	end
end

-- Might from Shared Spark: 10% of the Might of each ally within 20 studs who wears it
local function sharedMight(hero: Hero): number
	local perk = Config.Gear.perks.SharedSpark
	local pos = HeroService.position(hero)
	if not pos then
		return 0
	end
	local extra = 0
	for _, other in heroes do
		if other ~= hero and other.perks.SharedSpark and other.alive then
			local p = HeroService.position(other)
			if p and (p - pos).Magnitude <= perk.radius then
				extra += other.stats.Might * perk.share
			end
		end
	end
	return extra
end

-- Power with gear Might, Shared Spark and buffs (Rally Roar +10%)
function HeroService.power(hero: Hero): number
	local base = Formulas.power(Config, hero.level, hero.stats.Might + sharedMight(hero))
	return base * (1 + Status.value(hero.status, "power", os.clock(), 0))
end

-- An ability's numbers for this hero: ranks, mod pick and gear set changes
function HeroService.effective(hero: Hero, id: string): { [string]: any }
	return AbilityRules.effective(Config, id, hero.ranks[id] or 1, hero.mods[id], hero.gearMods[id])
end

-- Run speed multiplier: Speedster +10%, Weightless +30%
function HeroService.speedMult(hero: Hero): number
	local class = Config.Classes[hero.classId]
	local now = os.clock()
	if Status.has(hero.status, "stun", now) or Status.has(hero.status, "root", now) then
		return 0
	end
	local slow = Status.get(hero.status, "slow", now)
	return (1 + (class.moveSpeed or 0))
		* (1 + Status.value(hero.status, "speed", now, 0))
		* (if slow then slow.value else 1)
end

-- Crowd control on a hero (PvP): Resolve shortens it (at its PvP quarter), stuns and roots have
-- diminishing returns. Returns the seconds applied.
function HeroService.cc(hero: Hero, kind: string, duration: number, value: number?, resist: number?): number
	if not hero.alive then
		return 0
	end
	local now = os.clock()
	local applied =
		Status.apply(hero.status, kind, duration, now, { value = value, resist = resist, pvp = true })
	if applied > 0 then
		if kind == "stun" then
			hero.channel = nil
		end
		HeroService.applyWalkSpeed(hero)
		task.delay(applied + 0.05, function()
			if heroes[hero.id] == hero then
				HeroService.applyWalkSpeed(hero)
				HeroService.sendStatus(hero)
			end
		end)
		HeroService.sendStatus(hero)
	end
	return applied
end

-- Stunned, lifted or Downed: no casting
function HeroService.disabled(hero: Hero): boolean
	local now = os.clock()
	return hero.downed == true
		or Status.has(hero.status, "stun", now)
		or Status.has(hero.status, "knockup", now)
		or Status.has(hero.status, "float", now)
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
	player:SetAttribute("Side", hero.side)
	Net.fire("HeroState", player, {
		level = hero.level,
		side = hero.side,
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
		xp = hero.xp,
		stats = hero.stats,
		gearScore = hero.gearScore,
		gearMods = hero.gearMods,
		perks = hero.perks,
		gadget = hero.gadget,
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
	local cc = {}
	for _, kind in { "stun", "root", "slow", "knockup", "float" } do
		local e = Status.get(hero.status, kind, now)
		if e then
			cc[kind] = { left = e.untilT - now, value = e.value }
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
			cc = cc,
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
		hum.WalkSpeed = if hero.downed
			then Config.Pvp.downed.crawlSpeed
			else Config.Move.run.speed * HeroService.speedMult(hero)
	end
end

function HeroService.humanoid(hero: Hero): Humanoid?
	return humanoidOf(hero)
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
	hero.maxHealth = Formulas.health(Config, hero.level, hero.stats.Vitality, hero.classId)
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
	hero.xp = 0
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
	if not hero.alive or amount <= 0 or hero.traveling then
		return 0
	end
	local now = os.clock()
	hero.lastDamaged = now
	if Status.has(hero.status, "parry", now) and source and (source.enemy or source.pvp) then
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
	if hum and hero.health > 0 then
		hum.Health = hero.health
	end
	if hero.health <= 0 and hero.perks.SecondWind and now >= hero.secondWindAt then
		-- Second Wind: back up once every 5 minutes with 30% health
		-- in PvP the perk works at half (spec: Legendary perks in PvP)
		local perk = Config.Gear.perks.SecondWind
		local share = perk.health * (if source and source.pvp then 0.5 else 1)
		hero.secondWindAt = now + perk.every
		hero.health = math.max(1, math.floor(hero.maxHealth * share + 0.5))
		if hum then
			hum.Health = hero.health
		end
		HeroService.SecondWind:Fire(hero)
		return amount
	end
	if hero.health <= 0 and HeroService.downHandler and HeroService.downHandler(hero, source) then
		return amount -- Downed (PvE) or a PvP defeat: DeathService has it (and the humanoid)
	end
	if hero.health <= 0 then
		-- bots, and players when DeathService is not running: straight to Defeated and the Roblox respawn
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

-- Gear totals from GearService (stats, gear score, sets, perks, gadget)
function HeroService.applyGear(hero: Hero, totals: any)
	hero.stats = totals.stats
	hero.gearScore = totals.gearScore
	hero.setDamage = totals.setDamage
	hero.gearMods = totals.abilityMods
	hero.perks = totals.perks
	hero.gadget = totals.gadget
	HeroService.refresh(hero)
end

local function validLoadout(hero: Hero, l: any): AbilityRules.Loadout?
	if type(l) ~= "table" or type(l.set) ~= "string" or not Config.Abilities.setColor[l.set] then
		return nil
	end
	local loadout = {
		set = l.set,
		basic = AbilityRules.basicOf(Config, l.set),
		skills = if type(l.skills) == "table" then l.skills else {},
		super = l.super,
	}
	if AbilityRules.validate(Config, hero, loadout) then
		return loadout
	end
	return nil
end

-- Copy a saved character onto the live hero (on join). Anything invalid falls back to the starter kit.
function HeroService.applyProfile(hero: Hero, char: any, currency: any)
	hero.level = char.level
	hero.xp = char.xp
	hero.side = if char.side == "villain" then "villain" else "hero"
	hero.classId = if Config.Classes[char.classId] then char.classId else Config.Classes.default
	hero.fxStyle = char.fxStyle
	hero.ranks = table.clone(char.ranks)
	hero.mods = table.clone(char.mods)
	hero.bonusPoints = char.bonusPoints
	if
		AbilityRules.pointsSpent(Config, hero.ranks)
		> AbilityRules.pointsEarned(Config, hero.level, hero.bonusPoints)
	then
		-- more points spent than earned (a tuning change): free respec
		hero.ranks = AbilityRules.starter(Config, "Volt")
		hero.mods = {}
	end
	local l1 = validLoadout(hero, char.loadouts[1])
	local starterRanks, starterLoadout = AbilityRules.starter(Config, "Volt")
	for id, r in starterRanks do
		hero.ranks[id] = math.max(hero.ranks[id] or 0, r)
	end
	l1 = l1 or starterLoadout
	local l2 = validLoadout(hero, char.loadouts[2]) or table.clone(l1)
	hero.loadouts = { l1, l2 }
	hero.loadoutIndex = if char.loadoutIndex == 2
			and hero.level >= Config.Abilities.secondLoadoutLevel
		then 2
		else 1
	hero.loadout = hero.loadouts[hero.loadoutIndex]
	hero.setId = hero.loadout.set
	hero.respecAt = os.clock() + math.max(0, char.respecAt - os.time())
	hero.credits = currency.credits + currency.banked
	hero.loaded = true
	HeroService.refresh(hero)
	HeroService.applyWalkSpeed(hero)
end

-- Write the live hero back into its saved character (before every save)
function HeroService.writeBack(hero: Hero, char: any)
	if not hero.loaded then
		return
	end
	char.level = hero.level
	char.xp = hero.xp
	char.classId = hero.classId
	char.fxStyle = hero.fxStyle
	char.ranks = table.clone(hero.ranks)
	char.mods = table.clone(hero.mods)
	char.bonusPoints = hero.bonusPoints
	local saved = {}
	for i, l in hero.loadouts do
		saved[i] = { set = l.set, basic = l.basic, skills = table.clone(l.skills), super = l.super }
	end
	char.loadouts = saved
	char.loadoutIndex = hero.loadoutIndex
	char.respecAt = os.time() + math.max(0, math.ceil(hero.respecAt - os.clock()))
end

-- Renown in; level ups out (EconomyService calls this). Returns levels gained.
function HeroService.setProgress(hero: Hero, level: number, xp: number): number
	local gained = level - hero.level
	hero.xp = xp
	if gained ~= 0 then
		hero.level = level
		HeroService.refresh(hero)
		if gained > 0 then
			hero.health = hero.maxHealth -- a level up refills health
			HeroService.Leveled:Fire(hero, gained)
		end
	else
		HeroService.sendState(hero)
	end
	return gained
end

function HeroService.addBot(id: number, name: string, bot: any): Hero
	local hero = newHero(id, name, nil, bot)
	heroes[id] = hero
	takeSlot(hero)
	return hero
end

function HeroService.remove(hero: Hero)
	heroes[hero.id] = nil
	if hero.pvpSlot > 0 and bySlot[hero.pvpSlot] == hero then
		bySlot[hero.pvpSlot] = nil
	end
	if hero.player then
		byPlayer[hero.player] = nil
	end
	HeroService.Removed:Fire(hero)
end

-- Decoys (the Decoy gadget): fake heroes robots chase for a few seconds. Ids are negative.
local decoys: { { id: number, pos: Vector3, untilT: number } } = {}
local nextDecoy = 0
function HeroService.addDecoy(pos: Vector3, duration: number): number
	nextDecoy -= 1
	table.insert(decoys, { id = nextDecoy, pos = pos, untilT = os.clock() + duration })
	return nextDecoy
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
			table.insert(simList, {
				id = hero.id,
				x = pos.X,
				y = pos.Y,
				z = pos.Z,
				alive = hero.alive and not hero.traveling,
				lx = lx,
				lz = lz,
				scene = hero.scene, -- the opening or a mission: no ambient robots spawn around them
			})
		end
	end
	local now = os.clock()
	for i = #decoys, 1, -1 do
		local d = decoys[i]
		if now >= d.untilT then
			table.remove(decoys, i)
		else
			table.insert(
				simList,
				{ id = d.id, x = d.pos.X, y = d.pos.Y, z = d.pos.Z, alive = true, lx = 0, lz = -1 }
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
	hero.downed = nil
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
		takeSlot(hero)
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
	if RunService:IsStudio() and Config.Dev.unlockAllStyles then
		print("[HeroService] Studio: Flight unlocked for every hero (Config.Dev.unlockAllStyles)")
	end
end

return HeroService
