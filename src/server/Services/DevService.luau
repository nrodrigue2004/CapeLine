-- DevService: Studio test commands from the Dev panel. Every command is refused outside Studio, so live
-- servers never run them. Commands: bots n, clearbots, drones n, robot 1-6 (3 of that kind), cleardrones,
-- spawner 0/1, god 0/1, class 1-4, level n, heal, style 0/1 (Comic/Anime), points n (bonus Skill Points),
-- meter (fill Awakening), respec (no cooldown), loot 1-8 (roll a drop source at the hero's level), renown n,
-- credits n, dust n, save (save now), map (every beacon and safehouse found), wipe (start over as a new player: the creator then the opening), wreck n (structure damage
-- around the hero, default 3000), repair (every building back), flip (every vehicle near the hero),
-- incident 1-24 (that template next to the hero), clearincidents, event 1-12, boss (land the next world
-- boss in 3 s), bosskill (the boss to 1 HP), contract (finish the first accepted contract), clock 0-3
-- (day, dusk, night, dawn), weather 0-11 (hold a weather, 0 lets go), strike (a roof strike near a hero), side 0/1 (hero or villain, for this session only).
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
-- Lore step 12: reptier 0-5 (your own side's reputation tier), sideevent 1-3 (a side-vs-side event now).
-- Hero MMO: nemesis 0/1 (your nemesis ambushes you now / your Intel is full: the Showdown opens); nemesis 2
-- (WP9: a Showdown win is counted: the HQ wall gets its head and the next nemesis comes at once).
-- WP2: boardrows (40 test heroes on every weekly board and you at #6), boardroll (end the board week now).
-- WP1: daily 1-4 (a day passes, two days pass, finish today's quests, start the streak over).
-- WP10: promo 1-2 (forget this account's code and group claims; the group piece as if a member).
-- WP8: balance (print the live balance boot applied and refused, BalanceService.report).
-- The Test Lab (nate, 2026-11-21; Shared.LabRules, the Dev panel's LAB page): the first lab command keeps the hero's
-- build aside (the save keeps it; lableave puts it back). labweapon n (carry weapon n, held, Z X C V open), labpath n
-- (path n of Abilities.sets at the level cap: every ability at max rank, a loadout filled from it), labtry n (ability
-- num n onto the first skill key or the super; borrowed skills too), labmove n (mobility n at its last rank, both
-- choice moves picked), labrank n (the pick's rank n), labchoice r*10+o (rank r's move o), labnocd 0/1 (cooldowns
-- cut to Config.Dev.lab.cooldown), labstamina 0/1, labready (every cooldown done, Awakening full), labdummy 0/1/2
-- (a training dummy, a big one, clear them), labrobot n (one robot of Config.Enemies.order[n] in front, at your
-- level), labboss n (boss n lands in 3 s), labskip 0/1 (finishing the creator skips the exposition and the prologue),
-- lableave (your own build back). Mod picks and holding power or weapon use the game's own remotes (SkillsMod,
-- WeaponHold).

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
local WeatherService = require(script.Parent.WeatherService)
local StoryService = require(script.Parent.StoryService)
local OpeningService = require(script.Parent.OpeningService)
local MissionService = require(script.Parent.MissionService)
local NemesisService = require(script.Parent.NemesisService)
local SideQuestService = require(script.Parent.SideQuestService)
local FlagService = require(script.Parent.FlagService)
local DeathService = require(script.Parent.DeathService)
local FameService = require(script.Parent.FameService)
local CityBuilder = require(script.Parent.CityBuilder)
local SafehouseService = require(script.Parent.SafehouseService)
local CreatorService = require(script.Parent.CreatorService)
local HqService = require(script.Parent.HqService)
local PurchaseService = require(script.Parent.PurchaseService)
local NewsService = require(script.Parent.NewsService) -- lore step 7
local RepService = require(script.Parent.RepService) -- lore step 12
local BoardService = require(script.Parent.BoardService) -- WP2
local DailyService = require(script.Parent.DailyService) -- WP1
local PromoService = require(script.Parent.PromoService) -- WP10
local BalanceService = require(script.Parent.BalanceService) -- WP8
local WeaponService = require(script.Parent.WeaponService) -- the Test Lab
local ShopRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopRules"))
local CreatorRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CreatorRules"))
local ProfileSchema = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProfileSchema"))
local OpeningPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OpeningPlan"))
local StoryPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StoryPlan"))
local LabRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LabRules"))
local MoveRanks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MoveRanks"))
local Cooldowns = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Cooldowns"))

local DevService = {}

local forceHeroic = false -- the Dev panel's Heroic switch for what it starts

---------------------------------------------------------------------------
-- The Test Lab (Studio only: every command below runs only through the DevCommand gate)
---------------------------------------------------------------------------
local L = Config.Dev.lab

-- The hero's lab, opened (the build kept aside) on its first command
local function labOf(hero: any): LabRules.Lab
	if not hero.lab then
		hero.lab = LabRules.new(hero)
	end
	return hero.lab
end

local function labNote(player: Player, text: string)
	Net.fire("Toast", player, { id = "note", text = "TEST LAB: " .. text })
end

-- A point `ahead` studs in front of the hero on the ground (slot of count across), or nil without a body
local function labSpot(hero: any, ahead: number, slot: number, count: number): Vector3?
	local root = HeroService.rootPart(hero)
	if not root then
		return nil
	end
	local p, look = root.Position, root.CFrame.LookVector
	local x, z = LabRules.spot(p.X, p.Z, look.X, look.Z, ahead, slot, count, L.gap)
	return Vector3.new(x, CityBuilder.heightAt(x, z), z)
end

-- The lab's training dummies: an invisible anchor part each in Workspace.TestLab (the device draws the HQ's
-- training dummy over it and its damage readout from the anchor's Dealt and Hits attributes) and a target that
-- takes every hit and never breaks
local dummies: { { id: number, part: BasePart } } = {}
local function clearDummies()
	for _, d in dummies do
		EnemyService.removeTarget(d.id)
		d.part:Destroy()
	end
	table.clear(dummies)
end
local function addDummy(hero: any, big: boolean): boolean
	if #dummies >= L.dummies then
		return false
	end
	local s = if big then 2.6 else 1
	local ground = labSpot(hero, L.ahead * (if big then 1.6 else 1), #dummies + 1, L.dummies)
	if not ground then
		return false
	end
	local pos = ground + Vector3.new(0, 3 * s, 0)
	local folder = workspace:FindFirstChild("TestLab") or Instance.new("Folder")
	folder.Name = "TestLab"
	folder.Parent = workspace
	local part = Instance.new("Part")
	part.Name = "LabDummy"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	local root = HeroService.rootPart(hero)
	local face = if root then Vector3.new(root.Position.X, pos.Y, root.Position.Z) else pos + Vector3.zAxis
	part.CFrame = if (face - pos).Magnitude > 0.5 then CFrame.lookAt(pos, face) else CFrame.new(pos)
	part:SetAttribute("Big", big)
	part:SetAttribute("Dealt", 0)
	part:SetAttribute("Hits", 0)
	part.Parent = folder
	local id = EnemyService.addTarget({
		x = pos.X,
		y = pos.Y,
		z = pos.Z,
		r = Config.Hq.dummy.radius * s,
		hit = function(amount: number)
			part:SetAttribute("Dealt", (part:GetAttribute("Dealt") or 0) + amount)
			part:SetAttribute("Hits", (part:GetAttribute("Hits") or 0) + 1)
			return amount, false
		end,
	})
	part:SetAttribute("TargetId", id)
	table.insert(dummies, { id = id, part = part })
	return true
end

-- Put a path's lab kit on the hero (its archetype with it)
local function labPath(hero: any, set: string)
	labOf(hero)
	if hero.level < Config.Stats.levelCap then
		hero.level = Config.Stats.levelCap -- every slot, the super and borrowing open (HeroService.refresh below)
		hero.xp = 0
	end
	local ranks, loadout = LabRules.pathKit(Config, set, hero.level)
	hero.ranks, hero.mods = ranks, {}
	hero.startSet, hero.setId = set, set
	local l2 = table.clone(loadout)
	l2.skills = table.clone(loadout.skills)
	hero.loadouts = { loadout, l2 }
	hero.loadoutIndex = 1
	hero.loadout = loadout
	Cooldowns.clear(hero.cooldowns)
	hero.lab.reset += 1
	HeroService.setClass(hero, AbilityRules.archetypeOf(Config, set) or Config.Classes.default)
	HeroService.refresh(hero)
end

local labCommands: { [string]: (player: Player, hero: any, value: number) -> () } = {
	labweapon = function(player, hero, id)
		if not LabRules.weaponOk(Config, id) then
			labNote(player, "no such weapon")
			return
		end
		local lab = labOf(hero)
		lab.weapon = id
		GearService.refresh(player) -- the weapon in the hand (LabRules.weaponOf) with every key open
		hero.held = "weapon"
		hero.combo.at, hero.combo.step = 0, 0
		hero.channel = nil
		WeaponService.showHeld(hero)
		HeroService.sendState(hero)
	end,
	labpath = function(player, hero, index)
		local set = Config.Abilities.sets[index]
		if not set or not AbilityRules.pathReady(Config, set) then
			labNote(player, "that path has no abilities yet")
			return
		end
		labPath(hero, set)
		hero.held = "power"
		WeaponService.showHeld(hero)
		HeroService.sendState(hero)
	end,
	labtry = function(player, hero, num)
		local row = Config.Abilities.byNum[num]
		if not row then
			return
		end
		labOf(hero)
		if hero.level < Config.Stats.levelCap then
			labPath(hero, hero.startSet or Config.Abilities.defaultLoadout.set)
		end
		local ok, why, ranks, loadout = LabRules.try(Config, hero, row.id)
		if not ok or not ranks or not loadout then
			labNote(player, string.format("%s can't go on: %s", row.name or row.id, tostring(why)))
			return
		end
		hero.ranks = ranks
		hero.loadout = loadout
		hero.loadouts[hero.loadoutIndex] = loadout
		hero.setId = loadout.set
		hero.held = "power"
		WeaponService.showHeld(hero)
		HeroService.sendState(hero)
	end,
	labmove = function(_, hero, index)
		local pick = Config.Move.mobilityOrder[index]
		if not pick then
			return
		end
		labOf(hero)
		hero.mobRanks, hero.mobMoves = LabRules.mobility(Config.Move, hero.mobRanks, hero.mobMoves, pick)
		HeroService.setMobility(hero, pick) -- sends the state
	end,
	labrank = function(_, hero, rank)
		labOf(hero)
		local pick = hero.mobility or "flight"
		hero.mobRanks, hero.mobMoves = LabRules.mobility(
			Config.Move,
			hero.mobRanks,
			hero.mobMoves,
			pick,
			math.min(rank, MoveRanks.max(Config.Move, pick))
		)
		HeroService.sendState(hero)
	end,
	labchoice = function(player, hero, value)
		labOf(hero)
		local rank, option = LabRules.choiceOf(value)
		local ok, why = HeroService.chooseMove(hero, rank, option, true) -- the game's own check, a swap allowed
		if not ok and why ~= "same" then
			labNote(player, "move: " .. tostring(why))
		end
	end,
	labnocd = function(_, hero, on)
		local lab = labOf(hero)
		lab.noCd = on ~= 0
		HeroService.sendState(hero)
	end,
	labstamina = function(_, hero, on)
		local lab = labOf(hero)
		lab.stamina = on ~= 0
		HeroService.sendState(hero)
	end,
	labready = function(_, hero)
		local lab = labOf(hero)
		Cooldowns.clear(hero.cooldowns)
		table.clear(hero.recast)
		lab.reset += 1
		hero.meter.value = Config.Abilities.awakening.max
		HeroService.sendStatus(hero)
		HeroService.sendState(hero)
	end,
	labdummy = function(player, hero, what)
		if what == 2 then
			clearDummies()
		elseif not addDummy(hero, what == 1) then
			labNote(player, string.format("at most %d dummies (clear them first)", L.dummies))
		end
	end,
	labrobot = function(player, hero, index)
		local kind = Config.Enemies.order[index]
		local cfg = kind and Config.Enemies[kind]
		if not cfg or cfg.on == false or kind == "EvilTwin" then
			labNote(player, "that robot is switched off")
			return
		end
		local at = labSpot(hero, L.robotAhead, 1, 1)
		if at then
			local id = EnemyService.spawnAt(
				kind,
				at + Vector3.new(0, if cfg.flies then L.flyUp else 2, 0),
				hero.level
			)
			if not id then
				labNote(player, (cfg.name or kind) .. " did not spawn")
			end
		end
	end,
	labboss = function(player, _, index)
		if not BossService.startPick(index) then
			labNote(player, "a boss fight is on: wait for it to end")
		end
	end,
	labskip = function(player, _, on)
		CreatorService.setSkipPrologue(player, on ~= 0)
	end,
	lableave = function(player, hero)
		local lab = hero.lab
		if not lab then
			return
		end
		LabRules.restore(hero, lab.home)
		hero.lab = nil
		Cooldowns.clear(hero.cooldowns)
		HeroService.setMobility(hero, hero.mobility)
		HeroService.setClass(hero, hero.classId)
		GearService.refresh(player) -- the carried weapon back
		hero.held = "power"
		WeaponService.showHeld(hero)
		HeroService.refresh(hero)
	end,
}
DevService.labCommands = labCommands -- (tests)

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
	-- lore step 9: the Your double world event on you now (skips its odds, cooldowns and who may get it)
	double = function(player)
		print(
			string.format(
				"[Dev] Your double for %s: rare tier would say %s; forced: %s",
				player.Name,
				EventService.doubleWhy(player),
				tostring(EventService.forceDouble(player))
			)
		)
	end,
	-- lore step 12: your own side's reputation tier (0 to 5) and each side-vs-side event (1 to 3) now
	reptier = function(player, _, n)
		RepService.devTier(player, n)
	end,
	sideevent = function(_, _, n)
		print(string.format("[Dev] side event %d: %s", n, tostring(EventService.forceSide(n))))
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
		-- a prologue that was running goes first, or it plays on behind the new creator (fix-flow, 2026-11-19)
		OpeningService.stop(player)
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
	-- weather n: hold kind n of Config.Weather.order (0 lets go); strike: a lightning strike near a hero now
	weather = function(_, _, n)
		WeatherService.hold(n or 0)
	end,
	strike = function()
		print("[Dev] strike", WeatherService.strike())
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
		SideQuestService.skipStep(player)
	end,
	leavemission = function(player)
		MissionService.leave(player)
	end,
	-- lore step 10: the side quest framework (1 give the sample chain, 2 restart the step, 3 finish the step,
	-- 4 finish the chain, 5 forget the sample, 100 + k jump to step k, 200 + i try kind i alone)
	sidequest = function(player, _, what)
		SideQuestService.dev(player, what)
	end,
	actdone = function(player, hero)
		-- every Act 1 mission cleared (choices stay as they are)
		local story = StoryService.story(player)
		if story then
			story.opening = 1
			for _, n in StoryPlan.actMissions(Config, 1) do -- WP11: Act 1's, whatever acts come after
				StoryPlan.clear(story, n)
			end
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
			c.sq = ProfileSchema.newCharacter().sq -- lore step 10: side quest chains too
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
		HqService.redraw(player) -- WP9: the poster and heads, if you are in your HQ
	end,
	-- lore step 7: a sample news fact as you (1 boss flash, 2 boss down, 3 fake unmasked, 4 streak, 5 heist,
	-- 6 Act 1 mission)
	news = function(player, _, what)
		NewsService.dev(player, what)
	end,
	-- WP2: the weekly boards: boardrows (40 test heroes on every board, you at #6), boardroll (end the week now)
	boardrows = function(player)
		BoardService.dev(player, "rows")
	end,
	boardroll = function(player)
		BoardService.dev(player, "roll")
	end,
	-- WP1: the daily streak and quests (1 a day passes, 2 two days pass: one missed, the grace; 3 finish today's
	-- quests; 4 start the streak over)
	daily = function(player, _, what)
		DailyService.dev(player, what)
	end,
	-- WP10: the group piece and creator codes (1 forget this account's claims, 2 the group piece as a member)
	promo = function(player, _, what)
		PromoService.dev(player, what)
	end,
	-- WP8: print the live balance (what boot set from Balance_v<N> and what it refused) to the Output
	balance = function()
		BalanceService.report()
	end,
}

for name, fn in labCommands do
	commands[name] = fn
end

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
