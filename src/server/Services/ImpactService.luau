-- ImpactService: momentum and impact on the server (nate's playtest 2026-11-19: "More weight, more impact with
-- everything. Like imagine if I'm fighting and get hit with something and it sends me back into a building and
-- it destroys the building. Or even just flying at super speed. Momentum and impact should destroy things").
-- Every break goes through BuildingService (the server owns the destruction; devices only draw it), with the
-- curves and caps in Config.Combat.impact and the maths in Shared.ImpactRules.
-- * Rams (ImpactRam): the device sees its hero hit a wall fast (flight boost, a Super-speed running jump, a dash,
--   a Leaping pound, a travel ride: ImpactFx). The server checks the hero's own top speed over the last 0.6 s
--   (MoveGuard.peakSpeed), that the contact is next to where it has the hero and on a standing building, then
--   knocks pieces out there by speed. The device holds a hit-stop and loses some speed; the hole opens at once.
-- * Throws (knockHero): a heavy robot punch (a big share of the hero's health), a boss strike or a PvP knockback
--   throws the hero back. A building in the way breaks when the throw is fast enough and the hero flies on
--   through with part of the rest; a wall that holds stops it just short. The throw goes to the hero's own
--   device as HeroKnock (with where the wall broke, for its juice) and MoveGuard allows the distance.
-- * Robots into walls (robotWall): a robot that a knockback drives into a wall (EnemySim.knock said so) breaks it.
-- * Never: in a story scene (the prologue) or a fast-travel flight, in a safe area (a safehouse, an HQ, a
--   mission pocket: FlagService.safe), on a pinned building (beacon hosts, side quest roofs, the prologue's held
--   row: BuildingState.pinned), landmarks or safehouses (never wreckable). Caps: perHero breaks a window per hero
--   and serverPerSecond on the whole server, so a crowd of speedsters can never flood the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ImpactRules = require(Shared:WaitForChild("ImpactRules"))

local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local BuildingService = require(script.Parent.BuildingService)
local FlagService = require(script.Parent.FlagService)
local EnemyService = require(script.Parent.EnemyService)
local PerfMonitor = require(script.Parent.PerfMonitor)

local ImpactService = {}

local I = Config.Combat.impact
local CHEST = Vector3.new(0, 1.5, 0)
local ledger = ImpactRules.ledger()
ImpactService.ledger = ledger
ImpactService.breaks = 0 -- walls broken by impacts since boot (the Dev panel and PerfMonitor)

-- May this hero's movement break things here and now?
local function mayBreak(hero: any): boolean
	if not hero or not hero.alive or hero.downed or hero.scene or hero.traveling then
		return false
	end
	return not FlagService.safe(hero)
end

-- A hero thrown along `move` over `time` seconds: through a building that gives way, else stopped short of it.
-- Goes to the hero's own device (HeroKnock). Returns true when a wall broke.
function ImpactService.knockHero(hero: any, move: Vector3, time: number, lift: number?): boolean
	if not hero or not hero.player or not hero.alive or hero.downed then
		return false
	end
	local pos = HeroService.position(hero)
	if not pos or move.Magnitude < 0.5 then
		return false
	end
	local K = I.knock
	local total = move.Magnitude
	local dir = move / total
	local length = total
	local wall: { [string]: number }? = nil
	local id, t, at = BuildingService.wallOnPath(pos + CHEST, move)
	if id and at then
		local speed = total / math.max(time, 0.1)
		local dmg = ImpactRules.knockDamage(K, speed)
		local broke = false
		if
			dmg > 0
			and mayBreak(hero)
			and BuildingService.breakable(id)
			and ImpactRules.allow(I, ledger, hero.id, os.clock())
		then
			broke = BuildingService.smash(id, at, dmg, I.ram.radius) > 0
			if broke then
				ImpactService.breaks += 1
				wall = { x = at.X, y = at.Y, z = at.Z, t = t }
			end
		end
		length = ImpactRules.throwLength(K, total, t, broke)
	end
	local flat = dir * length
	MoveGuard.grant(hero, length + 10)
	Net.fire("HeroKnock", hero.player, {
		x = flat.X,
		y = math.max(lift or K.lift, flat.Y),
		z = flat.Z,
		time = time * (if total > 0 then math.clamp(length / total, 0.4, 1) else 1),
		wall = wall,
	})
	return wall ~= nil
end

-- A robot's hit on a hero (EnemyService, after the block and the hero's mitigation): a heavy punch throws it
function ImpactService.robotHit(hero: any, taken: number, from: Vector3, melee: boolean)
	if not melee or not hero.player then
		return
	end
	local dist = ImpactRules.knockDistance(I.knock, taken, hero.maxHealth or 0)
	if dist <= 0 then
		return
	end
	local pos = HeroService.position(hero)
	if not pos then
		return
	end
	local away = Vector3.new(pos.X - from.X, 0, pos.Z - from.Z)
	if away.Magnitude < 0.1 then
		return
	end
	ImpactService.knockHero(hero, away.Unit * dist, I.knock.time)
end

-- A boss strike on a hero (BossService): thrown away from where it landed
function ImpactService.bossHit(hero: any, from: Vector3)
	local pos = hero and HeroService.position(hero)
	if not pos then
		return
	end
	local away = Vector3.new(pos.X - from.X, 0, pos.Z - from.Z)
	if away.Magnitude < 0.1 then
		away = Vector3.new(1, 0, 0)
	end
	ImpactService.knockHero(hero, away.Unit * I.knock.boss, I.knock.time)
end

-- A robot a knockback drove `distance` studs into a wall along dir (CombatService): the wall breaks there
function ImpactService.robotWall(hero: any, enemyId: number, dir: Vector3, distance: number): boolean
	local dmg = ImpactRules.robotDamage(I.robot, distance)
	if dmg <= 0 or not mayBreak(hero) then
		return false
	end
	local e = EnemyService.get(enemyId)
	if not e then
		return false
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.1 then
		return false
	end
	local from = Vector3.new(e.x, e.y, e.z)
	local id, _, at = BuildingService.wallOnPath(from, flat.Unit * (I.robot.reach + 3))
	if not id or not at or not BuildingService.breakable(id) then
		return false
	end
	if not ImpactRules.allow(I, ledger, hero.id, os.clock()) then
		return false
	end
	local broke = BuildingService.smash(id, at, dmg, I.ram.radius) > 0
	if broke then
		ImpactService.breaks += 1
	end
	return broke
end

-- Knockback by move (nate's playtest 2026-11-19): a launched robot meets a wall (EnemySim asks through
-- EnemyService.launchWall). The hero whose hit launched it must be allowed to break things here; the wall breaks
-- by the throw's distance (impact.robot curve) inside the caps, so it flies on through. exit: leaving a building it
-- broke into (the far wall).
local function launchWall(
	e: any,
	at: Vector3,
	dir: Vector3,
	distance: number,
	_exit: boolean,
	src: number?
): boolean
	local hero = src and HeroService.byId(src)
	if not hero or not mayBreak(hero) then
		return false
	end
	local dmg = ImpactRules.robotDamage(I.robot, distance)
	if dmg <= 0 then
		return false
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.1 then
		return false
	end
	local from = Vector3.new(e.x, e.y, e.z) - flat.Unit * 2
	local id, _, hitAt = BuildingService.wallOnPath(from, flat.Unit * (I.robot.reach + 6))
	if not id then
		id = BuildingService.buildingAt(at, 3)
		hitAt = at
	end
	if not id or not hitAt or not BuildingService.breakable(id) then
		return false
	end
	if not ImpactRules.allow(I, ledger, hero.id, os.clock()) then
		return false
	end
	local broke = BuildingService.smash(id, hitAt, dmg, I.ram.radius) > 0
	if broke then
		ImpactService.breaks += 1
	end
	return broke
end
ImpactService.launchWall = launchWall

-- A robot swung as a weapon (ThrowService; Config.Throw.swing): the first wall within reach along dir breaks
function ImpactService.swingWall(hero: any, from: Vector3, dir: Vector3, reach: number, dmg: number): boolean
	if dmg <= 0 or not mayBreak(hero) or dir.Magnitude < 0.1 then
		return false
	end
	local id, _, at = BuildingService.wallOnPath(from, dir.Unit * reach)
	if not id or not at or not BuildingService.breakable(id) then
		return false
	end
	if not ImpactRules.allow(I, ledger, hero.id, os.clock()) then
		return false
	end
	local broke = BuildingService.smash(id, at, dmg, I.ram.radius) > 0
	if broke then
		ImpactService.breaks += 1
	end
	return broke
end

-- A hero dropping onto a building from high up (nate, 2026-11-19 13:18Z; Config.Combat.drop): the device's
-- landing claim (ImpactDrop: where it landed, its fall speed). The server backs it with its own recent speed and
-- the hero's spot, breaks the roof under it (and the storeys BuildingState says fall), inside the caps, and
-- tells CombatService to hit the robots round it (CombatService.dropHit).
ImpactService.dropHit = nil :: ((any, Vector3, number) -> ())?
local function onDrop(player: Player, at: Vector3, fall: number)
	local hero = HeroService.get(player)
	if not mayBreak(hero) then
		return
	end
	local pos = HeroService.position(hero)
	if not pos then
		return
	end
	local Dp = Config.Combat.drop
	local peak = MoveGuard.peakSpeed(hero, Dp.window)
	local speed = ImpactRules.dropOk(Dp, fall, peak, (at - pos).Magnitude)
	if not speed then
		return
	end
	local dmg, radius = ImpactRules.dropDamage(Dp, speed)
	if dmg <= 0 then
		return
	end
	if ImpactService.dropHit then
		ImpactService.dropHit(hero, at, speed)
	end
	local id = BuildingService.buildingAt(at + Vector3.new(0, -2, 0), 3)
	if not id or not BuildingService.breakable(id) then
		return
	end
	if not ImpactRules.allow(I, ledger, hero.id, os.clock()) then
		return
	end
	if BuildingService.smash(id, at + Vector3.new(0, -2, 0), dmg, radius) > 0 then
		ImpactService.breaks += 1
	end
end

-- The device's ram claim (ImpactRam): contact point, travel direction, speed
local function onRam(player: Player, at: Vector3, dir: Vector3, speed: number)
	local hero = HeroService.get(player)
	if not mayBreak(hero) then
		return
	end
	local pos = HeroService.position(hero)
	if not pos then
		return
	end
	local R = I.ram
	local peak = MoveGuard.peakSpeed(hero, R.window)
	if not ImpactRules.ramOk(R, speed, peak, (at - pos).Magnitude) then
		return
	end
	if dir.Magnitude < 0.5 then
		return
	end
	local id = BuildingService.buildingAt(at, 3)
	if not id or not BuildingService.breakable(id) then
		return
	end
	if not ImpactRules.allow(I, ledger, hero.id, os.clock()) then
		return
	end
	local dmg = ImpactRules.ramDamage(R, ImpactRules.ramSpeed(R, speed, peak))
	if BuildingService.smash(id, at + dir.Unit * 1.5, dmg, R.radius) > 0 then
		ImpactService.breaks += 1
	end
end

function ImpactService.init()
	Net.on("ImpactRam", onRam)
	Net.on("ImpactDrop", onDrop)
	EnemyService.heroHitHook = ImpactService.robotHit
	EnemyService.launchWall = launchWall
	Players.PlayerRemoving:Connect(function(player)
		local hero = HeroService.get(player)
		if hero then
			ImpactRules.forget(ledger, hero.id)
		end
	end)
	PerfMonitor.watch("impactBreaks", function()
		return ImpactService.breaks
	end)
end

return ImpactService
