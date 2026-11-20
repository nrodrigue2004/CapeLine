-- MoveActService: the 20 mobility moves on the server (nate's mobility upgrade rework, 2026-11-20; Config.Move.moves,
-- Shared.MoveActs). Each pick's ranks 3 and 5 are a choice of two moves (Shared.MoveRanks, saved per hero as
-- mobMoves); a move works only for a hero who trained the rank and picked it (HeroService.hasMove).
-- * MoveAct (from the device: the move's num, a point, a direction, an optional target id and step): checked on the
--   server's own clock (the cooldown with 15% leeway for lag), against its own history (MoveGuard.dropped,
--   peakSpeed, speed) and where it has the hero, before anything is hit, broken or granted.
-- * The rest the server sees for itself: Slipstream (allies flying in a boosting leader's wake get the "slip" buff,
--   which MoveGuard's cap and the ally's device both read), Sonic Wake (a Super-speed hero at top speed flips cars
--   and cracks the walls beside it), Blazing Ram's and Slipstream's ram hooks (ImpactService.ramHook), Wall
--   Crusher's bites (ImpactService.biteHook), Blazing Ram's fire trail.
-- * Hits go through CombatService.moveHit (robots take the move's status; flagged heroes take it through PvP
--   compression and the PvP knock caps); breaking goes through BuildingService, VehicleService, CraterService and
--   ImpactService (inside the impact caps), never in a safe area, a story scene or a fast-travel flight.
-- * Moves faster than a pick's cap are granted distances (Blink, Slingshot, Ceiling Drop, Double Zip), like Dash
--   Strike. Every other speed sits inside the caps (tests/mobility_moves_test.luau runs them through MoveCheck).
-- * MoveActFx tells every other device near enough to draw it (Controllers.MoveActClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local MoveActs = require(Shared:WaitForChild("MoveActs"))
local Status = require(Shared:WaitForChild("Status"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))

local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local CombatService = require(script.Parent.CombatService)
local BuildingService = require(script.Parent.BuildingService)
local VehicleService = require(script.Parent.VehicleService)
local CraterService = require(script.Parent.CraterService)
local EnemyService = require(script.Parent.EnemyService)
local FlagService = require(script.Parent.FlagService)
local ImpactService = require(script.Parent.ImpactService)
local ThrowService = require(script.Parent.ThrowService)
local PerfMonitor = require(script.Parent.PerfMonitor)

local MoveActService = {}

local MOVES = Config.Move.moves
local SLACK = 0.85 -- the server's share of a cooldown (lag leeway)
local FX_RANGE = 260 -- other devices this near draw it
local DOWN = Vector3.new(0, 2, 0)
local FLY = HeroAnim.modeIndex.fly

local books: { [number]: { [string]: number } } = {}
local meteors: { [number]: { at: Vector3, untilT: number } } = {}
local blazes: { [number]: { untilT: number, nextAt: number } } = {}
local fires: { { hero: any, at: Vector3, untilT: number } } = {}
local wakeAt: { [number]: number } = {}

MoveActService.acts = 0 -- moves taken since boot (DevPanel, PerfMonitor)

local function bookOf(hero: any): { [string]: number }
	local b = books[hero.id]
	if not b then
		b = {}
		books[hero.id] = b
	end
	return b
end

-- Off cooldown? Then start it (the server's leeway share of it)
local function take(hero: any, id: string, cd: number): boolean
	local b = bookOf(hero)
	local now = os.clock()
	if not MoveActs.ready(b, id, now) then
		return false
	end
	MoveActs.start(b, id, now, cd, SLACK)
	return true
end

-- May this hero's move break things here and now? (the same rule as ImpactService's)
local function mayBreak(hero: any): boolean
	return hero.alive
		and not hero.downed
		and not hero.scene
		and not hero.traveling
		and not FlagService.safe(hero)
end

-- Is `at` where the server has the hero (with room for its lag at its speed)?
local function near(hero: any, at: Vector3, slack: number): boolean
	local pos = HeroService.position(hero)
	return pos ~= nil and (at - pos).Magnitude <= slack + MoveGuard.speed(hero) * 0.25
end

-- Every other device near `at` draws the move
local function show(hero: any, num: number, at: Vector3, dir: Vector3, extra: number?)
	MoveActService.acts += 1
	local by = hero.player and hero.player.UserId or 0
	for _, p in Players:GetPlayers() do
		if p ~= hero.player then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - at).Magnitude <= FX_RANGE then
				Net.fire("MoveActFx", p, num, at, dir, by, extra or 0)
			end
		end
	end
end

-- A decoy robots chase for `life` s (Afterimage, Shadow Flip): the gadget's own decoy
-- (hero: whose decoy; only robots it may meet chase it, a private mission run's own: PhaseService)
local function decoy(hero: any, at: Vector3, life: number, taunt: number)
	local id = HeroService.addDecoy(at, life, EnemyService.soloKey(hero))
	for _, c in EnemyService.candidatesFor(hero) do
		if (Vector3.new(c.x, c.y, c.z) - at).Magnitude <= taunt then
			EnemyService.applyStatus(c.id, "taunt", life, { src = id })
		end
	end
end

-- A landing that breaks what it lands on: the roof under it, else the street (a crater)
local function breakUnder(hero: any, at: Vector3, radius: number, dmg: number)
	if not mayBreak(hero) then
		return
	end
	if BuildingService.buildingAt(at - DOWN, 3) then
		BuildingService.hit(at - DOWN, radius, dmg, 1)
	else
		CraterService.blast(at, radius, dmg)
	end
	VehicleService.hit(at, radius)
end

---------------------------------------------------------------------------
-- The moves the device starts
---------------------------------------------------------------------------

type Act = (hero: any, num: number, at: Vector3, dir: Vector3, target: number, step: number) -> boolean

local ACTS: { [string]: Act } = {}

-- Flight R3: a high dive lands in a shockwave that knocks robots and cracks roofs
ACTS.sonicDive = function(hero, num, at, dir)
	local m = MOVES.sonicDive
	if not near(hero, at, 14) then
		return false
	end
	if MoveGuard.dropped(hero, 3) < m.drop * 0.8 or MoveGuard.peakSpeed(hero, 0.8) < m.speed * 0.8 then
		return false
	end
	if not take(hero, "sonicDive", m.cooldown) then
		return false
	end
	CombatService.moveHit(hero, at, m.radius, m.coeff, "knockback", 0.3, m.knock)
	if mayBreak(hero) then
		BuildingService.hit(at - DOWN, m.radius, m.dmg, 1)
		VehicleService.hit(at, m.radius)
	end
	show(hero, num, at, dir)
	return true
end

-- Flight R5: boost through buildings as a flicker; the server only times it (MoveGuard checks speed, never walls)
ACTS.phase = function(hero, num, at, dir)
	local m = MOVES.phase
	if not near(hero, at, 12) or not MoveGuard.boosting(hero) then
		return false
	end
	if not take(hero, "phase", m.cooldown + m.time) then
		return false
	end
	MoveGuard.spend(hero, m.drain * m.time)
	show(hero, num, at, dir)
	return true
end

-- Super-speed R3: circling raised a whirlwind at `at` (the middle): robots rise and are dazed, cars flip, street
-- things are torn loose; it holds `life` s, lifting again every half second
ACTS.tornadoRun = function(hero, num, at, dir)
	local m = MOVES.tornadoRun
	if not near(hero, at, m.radius * 1.6) or MoveGuard.peakSpeed(hero, m.window) < m.speed * 0.8 then
		return false
	end
	if not take(hero, "tornadoRun", m.cooldown) then
		return false
	end
	CombatService.moveHit(hero, at, m.lift.radius, m.coeff, "knockup", m.stun)
	if mayBreak(hero) then
		VehicleService.hit(at, m.lift.radius)
		BuildingService.street(at, m.lift.radius)
	end
	for i = 1, math.floor(m.life / 0.5) - 1 do
		CombatService.after(i * 0.5, function()
			if hero.alive then
				CombatService.moveHit(hero, at, m.lift.radius, 0, "knockup", 0.6)
			end
		end)
	end
	show(hero, num, at, dir)
	return true
end

-- Super-speed R3: a hard stop left a decoy
ACTS.afterimage = function(hero, num, at, dir)
	local m = MOVES.afterimage
	if not near(hero, at, 10) or MoveGuard.peakSpeed(hero, m.within + 0.6) < m.from * 0.8 then
		return false
	end
	if not take(hero, "afterimage", m.cooldown) then
		return false
	end
	decoy(hero, at, m.life, m.taunt)
	show(hero, num, at, dir, m.life)
	return true
end

-- Super-speed R5: a 30-stud dash, a granted distance (it is faster than any cap)
ACTS.blink = function(hero, num, at, dir)
	local m = MOVES.blink
	if not near(hero, at, 10) or dir.Magnitude > m.range + 1 then
		return false
	end
	if not take(hero, "blink", m.cooldown) then
		return false
	end
	MoveGuard.grant(hero, dir.Magnitude + 6)
	show(hero, num, at, dir)
	return true
end

-- Leaping R3: a big landing stuns round it (wider from higher) and craters the street from `crater` up.
-- dir.Y: the fall the device measured (the server takes the smaller of it and its own)
ACTS.impactLanding = function(hero, num, at, dir)
	local m = MOVES.impactLanding
	if not near(hero, at, 12) then
		return false
	end
	local fall = math.min(dir.Y, MoveGuard.dropped(hero, 4) + 6)
	local radius, crater = MoveActs.impact(m, fall)
	if not radius or not take(hero, "impactLanding", m.cooldown) then
		return false
	end
	CombatService.moveHit(hero, at, radius, m.coeff, "stun", m.stun)
	if crater then
		breakUnder(hero, at, radius, m.craterDmg)
	end
	show(hero, num, at, dir, radius)
	return true
end

-- Leaping R3: a kick off a climb shatters the panel (dir: the wall's normal)
ACTS.wallCrusher = function(hero, num, at, dir)
	local m = MOVES.wallCrusher
	if not near(hero, at, 10) or dir.Magnitude < 0.5 or not take(hero, "wallCrusher", m.cooldown) then
		return false
	end
	local n = dir.Unit
	ImpactService.swingWall(hero, at + n * 3, -n, m.kickRadius, m.kick)
	show(hero, num, at, dir)
	return true
end

-- Leaping R5: step 1 aims the pound at `at` from the top of a leap (dir: where it starts); step 2 is its landing
ACTS.meteorStrike = function(hero, num, at, dir, _target, step)
	local m = MOVES.meteorStrike
	local now = os.clock()
	if step == 1 then
		if not near(hero, dir, 14) or (at - dir).Magnitude > m.range + 6 then
			return false
		end
		if not take(hero, "meteorStrike", m.cooldown) then
			return false
		end
		meteors[hero.id] = { at = at, untilT = now + (at - dir).Magnitude / m.speed + 1.5 }
		show(hero, num, dir, at - dir, 1)
		return true
	end
	local p = meteors[hero.id]
	meteors[hero.id] = nil
	if not p or now > p.untilT or (at - p.at).Magnitude > 24 or not near(hero, at, 14) then
		return false
	end
	CombatService.moveHit(hero, at, m.radius, m.coeff, "knockback", 0.3, m.knock)
	breakUnder(hero, at, m.radius, m.dmg)
	show(hero, num, at, Vector3.zero, 2)
	return true
end

-- Acrobat R3: letting go above a robot drops onto it (target: the robot's id): a granted dash, then the takedown
ACTS.ceilingDrop = function(hero, num, at, dir, target)
	local m = MOVES.ceilingDrop
	local e = EnemyService.get(target)
	if not e or not e.alive or not near(hero, dir, 12) then
		return false
	end
	local robot = Vector3.new(e.x, e.y, e.z)
	local d = (robot - dir).Magnitude
	if d > m.reach + 8 or (robot - at).Magnitude > 12 or not take(hero, "ceilingDrop", m.cooldown) then
		return false
	end
	MoveGuard.grant(hero, d + 8)
	local cap = HeroService.moveConfig(hero).mobility.acrobat.cap
	CombatService.after(d / cap, function()
		if hero.alive then
			CombatService.moveHit(hero, robot, m.radius, m.coeff, "stun", m.stun)
		end
	end)
	show(hero, num, dir, robot - dir)
	return true
end

-- Acrobat R5: the flip left a clone (at: where the flip began)
ACTS.shadowFlip = function(hero, num, at, dir)
	local m = MOVES.shadowFlip
	if not near(hero, at, 14) or os.clock() - (hero.flipAt or -math.huge) > 1 then
		return false
	end
	if not take(hero, "shadowFlip", m.cooldown) then
		return false
	end
	decoy(hero, at, m.life, m.taunt)
	show(hero, num, at, dir, m.life)
	return true
end

-- Acrobat R5: launched off a wall toward `at` (dir: where it starts): a granted arc
ACTS.slingshot = function(hero, num, at, dir)
	local m = MOVES.slingshot
	local d = (at - dir).Magnitude
	if not near(hero, dir, 10) or d > m.range + 8 or not take(hero, "slingshot", m.cooldown) then
		return false
	end
	MoveGuard.grant(hero, d + m.up * 2 + 10)
	show(hero, num, dir, at - dir)
	return true
end

-- Swing R3: two lines and a shot forward to `at` (dir: where it starts; a granted distance on top of the zip cap)
ACTS.doubleZip = function(hero, num, at, dir)
	local m = MOVES.doubleZip
	local d = (at - dir).Magnitude
	if not near(hero, dir, 10) or d > m.range + 6 or not take(hero, "doubleZip", m.cooldown) then
		return false
	end
	MoveGuard.grant(hero, d + 10)
	show(hero, num, dir, at - dir)
	return true
end

-- Swing R3: pull a robot (step 1) or a liftable thing (step 2) to the hero, then hold it (ThrowService.yank)
ACTS.yank = function(hero, num, at, dir, target, step)
	local m = MOVES.yank
	if not near(hero, dir, 10) or (step ~= 1 and step ~= 2) then
		return false
	end
	if not MoveActs.ready(bookOf(hero), "yank", os.clock()) then
		return false
	end
	if not ThrowService.yank(hero, step, target, m.range, m.time, m.stun) then
		return false
	end
	MoveActs.start(bookOf(hero), "yank", os.clock(), m.cooldown, SLACK)
	show(hero, num, dir, at - dir, step)
	return true
end

-- Swing R5: a release this fast bowls the robots along its path (dir: the release velocity)
ACTS.wreckingKick = function(hero, num, at, dir)
	local m = MOVES.wreckingKick
	if not near(hero, at, 12) or MoveGuard.peakSpeed(hero, 0.6) < m.bowl * 0.8 or dir.Magnitude < 1 then
		return false
	end
	if not take(hero, "wreckingKick", m.cooldown) then
		return false
	end
	local way = dir.Unit
	for i = 0, 2 do
		CombatService.moveHit(
			hero,
			at + way * (i * m.radius * 1.5),
			m.radius,
			m.coeff / 3,
			"knockback",
			0.3,
			m.knock
		)
	end
	show(hero, num, at, dir)
	return true
end

---------------------------------------------------------------------------
-- What the server sees for itself
---------------------------------------------------------------------------

-- Blazing Ram and Slipstream on a ram ImpactService accepted: the damage multiplier
local function onRam(hero: any, at: Vector3, dir: Vector3): number
	local mult = 1
	if HeroService.hasMove(hero, "blazeRam") then
		local m = MOVES.blazeRam
		MoveGuard.spend(hero, m.stamina)
		mult = MoveActs.blazeDamage(m, 1)
		local now = os.clock()
		blazes[hero.id] = { untilT = now + 1, nextAt = now }
		table.insert(fires, { hero = hero, at = at, untilT = now + m.trailLife })
		show(hero, MoveActs.num(Config.Move, "blazeRam") :: number, at, dir)
	end
	if HeroService.hasMove(hero, "slipstream") and MoveGuard.boosting(hero) then
		MoveGuard.spend(hero, -MOVES.slipstream.refill)
	end
	return mult
end

local function onBite(hero: any): number
	return if HeroService.hasMove(hero, "wallCrusher") then MOVES.wallCrusher.bite else 1
end

-- Five times a second: Slipstream's wakes, Sonic Wake, Blazing Ram's trail
local acc = 0
local fireAcc = 0
local function step(dt: number)
	acc += dt
	fireAcc += dt
	local now = os.clock()
	if acc >= 0.2 then
		acc = 0
		for _, hero in HeroService.all() do
			if not hero.alive or hero.downed then
				continue
			end
			local root = HeroService.rootPart(hero)
			if not root then
				continue
			end
			-- Slipstream: allies flying in this boosting hero's wake
			if HeroService.hasMove(hero, "slipstream") and MoveGuard.boosting(hero) then
				local m = MOVES.slipstream
				local v = root.AssemblyLinearVelocity
				if v.Magnitude > 10 then
					local h = v.Unit
					local l = root.Position
					for _, ally in HeroService.all() do
						local ar = ally ~= hero and ally.alive and HeroService.rootPart(ally)
						if
							ar
							and ally.player
							and ally.player:GetAttribute("Move") == FLY -- flying (the mode its device reports)
							and FlagService.canSupport(hero, ally)
							and MoveActs.inWake(
								m,
								l.X,
								l.Y,
								l.Z,
								h.X,
								h.Y,
								h.Z,
								ar.Position.X,
								ar.Position.Y,
								ar.Position.Z
							)
						then
							local left = Status.get(ally.status, "slip", now)
							if not left or left.untilT - now < m.hold * 0.5 then
								HeroService.buff(ally, "slip", m.ally, m.hold)
							end
						end
					end
				end
			end
			-- Sonic Wake: cars beside a hero at top speed flip, the walls beside it crack
			if HeroService.hasMove(hero, "sonicWake") and mayBreak(hero) then
				local m = MOVES.sonicWake
				if
					MoveActs.wakeSpeed(m, MoveGuard.speed(hero) / 0.9)
					and now - (wakeAt[hero.id] or 0) >= m.every
				then
					wakeAt[hero.id] = now
					VehicleService.hit(root.Position, m.radius)
					BuildingService.hit(root.Position, m.radius, m.dmg, 2)
				end
			end
			-- Blazing Ram: the second after a ram leaves fire along the way
			local b = blazes[hero.id]
			if b then
				if now > b.untilT then
					blazes[hero.id] = nil
				elseif now >= b.nextAt then
					b.nextAt = now + 0.25
					table.insert(
						fires,
						{ hero = hero, at = root.Position, untilT = now + MOVES.blazeRam.trailLife }
					)
				end
			end
		end
	end
	if fireAcc >= 0.5 then
		local m = MOVES.blazeRam
		fireAcc = 0
		for i = #fires, 1, -1 do
			local f = fires[i]
			if now > f.untilT or not f.hero.alive then
				table.remove(fires, i)
			else
				CombatService.moveHit(f.hero, f.at, m.trailRadius, m.trailCoeff * 0.5)
			end
		end
		while #fires > 40 do
			table.remove(fires, 1)
		end
	end
end

function MoveActService.init()
	ImpactService.ramHook = onRam
	ImpactService.biteHook = onBite
	Net.on(
		"MoveAct",
		function(player: Player, num: number, at: Vector3, dir: Vector3, target: number?, stepN: number?)
			local hero = HeroService.get(player)
			local id = MoveActs.idOf(Config.Move, num)
			if not hero or not id or not hero.alive or hero.downed or HeroService.disabled(hero) then
				return
			end
			if not HeroService.hasMove(hero, id) or at ~= at or dir ~= dir then
				return
			end
			local act = ACTS[id]
			if act then
				act(hero, num, at, dir, target or 0, stepN or 0)
			end
		end
	)
	HeroService.Removed:Connect(function(hero)
		books[hero.id] = nil
		meteors[hero.id] = nil
		blazes[hero.id] = nil
		wakeAt[hero.id] = nil
	end)
	PerfMonitor.watch("moveActs", function()
		return MoveActService.acts
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("MoveActService", step))
end

return MoveActService
