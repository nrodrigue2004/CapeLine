-- BlockService: block, breaker and interrupt on the server (spec: Hero MMO features > Block, breaker and
-- interrupt; H1). Rules in Shared.GuardMath, numbers in Config.Guard.
-- * Heroes hold Block (CombatBlock). Every hit on a hero passes HeroService.guardHook: a robot's or a boss's
--   hit is resolved here; a PvP hit is resolved by CombatService through BlockService.resolveHero first (so
--   a blocked hit also skips its knockback). Blocking halves movement (HeroService.speedMult) and stops casts.
-- * Perfect blocks stagger the attacker and give 10 Awakening; Parry Stance and the Martial Arts parry
--   count as perfect blocks (HeroService.Parried).
-- * Interrupts: a light hit, a stun or a knock on a hero winding up a heavy (CombatService sets hero.windup)
--   or charging a skill (hero.chargeAt) cancels it for half its cooldown; on a robot winding up, it reels.
-- * Robots: Config.Guard.robotBlocks kinds block on a timer while fighting (shown blue to players near);
--   the Null Sentinel keeps its front guard, and a breaker now shatters it as well as a flank hit.
-- Nothing here changes EnemySim: robot blocks live in this service, a shatter is a stun (the windup reset
-- EnemySim already does) and the Sentinel's guard break sets the same guardBrokenUntil a flank hit sets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GuardMath = require(Shared:WaitForChild("GuardMath"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local ChargeRules = require(Shared:WaitForChild("ChargeRules"))
local Awakening = require(Shared:WaitForChild("Awakening"))
local Status = require(Shared:WaitForChild("Status"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local SafehouseService = require(script.Parent.SafehouseService)

local BlockService = {}

local G = Config.Guard
local A = Config.Abilities

-- (hero, outcome, attacker or nil) after a block resolves on a hero: "blocked", "perfect", "shatter";
-- (hero, "break" or "cut") when a hero's hit shatters a block or interrupts someone (badges count these)
BlockService.Outcome = Signal.new()

local states: { [number]: GuardMath.State } = {}
local PLAIN: GuardMath.Result =
	{ outcome = "hit", mult = 1, noKnock = false, stagger = 0, attackerStagger = 0, meter = 0 }
local robots: { [number]: GuardMath.RobotState } = {}
local events: { any } = {}
local lastWord: { [number]: number } = {}

function BlockService.state(hero: any): GuardMath.State
	local st = states[hero.id]
	if not st then
		st = GuardMath.new(G, os.clock())
		states[hero.id] = st
	end
	return st
end

function BlockService.blocking(hero: any): boolean
	local st = states[hero.id]
	return st ~= nil and st.on
end

local function send(hero: any, extra: { [string]: any }?)
	if not hero.player then
		return
	end
	local st = BlockService.state(hero)
	local now = os.clock()
	local data = {
		guard = math.floor(GuardMath.guard(G, st, now) + 0.5),
		on = st.on,
		broken = math.max(0, st.brokenUntil - now),
	}
	if extra then
		for k, v in extra do
			data[k] = v
		end
	end
	Net.fire("GuardState", hero.player, data)
end

-- A comic word over someone (at most every wordGap per actor), seen by players near
local function word(kind: string, pos: Vector3, actor: number)
	local now = os.clock()
	if (lastWord[actor] or 0) + G.wordGap > now and kind ~= "perfect" and kind ~= "shatter" then
		return
	end
	lastWord[actor] = now
	table.insert(events, { k = kind, x = pos.X, y = pos.Y, z = pos.Z, a = actor })
end

local function setBlock(hero: any, on: boolean)
	local st = BlockService.state(hero)
	local now = os.clock()
	if on and (not hero.alive or HeroService.disabled(hero) or hero.channel) then
		send(hero, { reply = true })
		return
	end
	-- no block inside a safehouse (nobody fights there; HQ keeps it for the training dummies)
	local pos = HeroService.position(hero)
	local changed = GuardMath.setBlock(G, st, on, now, {
		safe = hero.traveling or (pos ~= nil and SafehouseService.at(pos) ~= nil),
	})
	if changed then
		HeroService.applyWalkSpeed(hero)
		if hero.player then
			hero.player:SetAttribute("Blocking", st.on or nil)
		end
	end
	send(hero, { reply = true })
end

function BlockService.stop(hero: any)
	if BlockService.blocking(hero) then
		setBlock(hero, false)
	end
end

-- The hero's facing on the ground (the root's look vector)
local function facing(hero: any): (Vector3?, Vector3?)
	local root = HeroService.rootPart(hero)
	if not root then
		return nil, nil
	end
	return root.Position, root.CFrame.LookVector
end

-- Stagger someone for a moment (a perfect block's attacker, a shattered block's owner)
local function staggerHero(hero: any, seconds: number)
	HeroService.cc(hero, "stun", seconds)
end

-- Resolve a hit on a hero. info: { damage, coeff, charged, grab, breaker, status, status2, from (Vector3),
-- attacker (hero) or enemy (id) }. Returns the GuardMath result (mult, noKnock) after applying its
-- staggers, Awakening and words.
function BlockService.resolveHero(hero: any, info: any): GuardMath.Result
	local st = states[hero.id]
	if not st or not st.on then
		return PLAIN -- not blocking: a plain hit
	end
	local now = os.clock()
	local pos, look = facing(hero)
	local front = true
	if pos and look and info.from then
		front = GuardMath.front(G.block.front, look.X, look.Z, pos.X, pos.Z, info.from.X, info.from.Z)
	end
	local r = GuardMath.resolve(G, st, {
		damage = info.damage,
		maxHealth = hero.maxHealth,
		coeff = info.coeff,
		charged = info.charged,
		grab = info.grab,
		breaker = info.breaker,
		status = info.status,
		status2 = info.status2,
		front = front,
	}, now)
	if r.outcome == "hit" then
		return r
	end
	local at = pos or Vector3.zero
	local actor = if hero.player then hero.player.UserId else hero.id
	if r.outcome == "perfect" then
		if r.meter > 0 then
			Awakening.add(Config, hero.meter, r.meter, now)
			hero.meterDirty = true
		end
		if info.attacker then
			staggerHero(info.attacker, r.attackerStagger)
		elseif info.enemy then
			EnemyService.applyStatus(info.enemy, "stun", r.attackerStagger)
		end
		word("perfect", at, actor)
	elseif r.outcome == "shatter" then
		staggerHero(hero, r.stagger)
		HeroService.applyWalkSpeed(hero)
		if hero.player then
			hero.player:SetAttribute("Blocking", nil)
		end
		word("shatter", at, actor)
		if info.attacker then
			BlockService.Outcome:Fire(info.attacker, "break", hero)
		end
	else
		word("block", at, actor)
	end
	BlockService.Outcome:Fire(hero, r.outcome, info.attacker)
	send(hero, if r.outcome == "shatter" then { ended = true } else nil)
	return r
end

---------------------------------------------------------------------------
-- Interrupts
---------------------------------------------------------------------------

-- A charge-up power (H2) being charged: past the tap threshold and not yet released or timed out. Aiming
-- an ordinary skill is not a charge an interrupt can cut.
local function charging(num: number, at: number, now: number): boolean
	local row = A.byNum[num]
	local ch = Config.Combat.charge
	return row ~= nil and ChargeRules.power(row) and now - at > ch.start and now - at <= ch.maxHold
end

-- Is the hero winding up a heavy or charging a charge-up power now?
local function winding(hero: any, now: number): boolean
	local w = hero.windup
	if w and not w.cancelled and now < w.untilT then
		return true
	end
	for num, at in hero.chargeAt or {} do
		if charging(num, at, now) then
			return true
		end
	end
	return false
end

-- BlockService.chargeCut(hero): set by CombatService so a cut charge drops its glow and slow
BlockService.chargeCut = nil :: ((any) -> ())?

-- Cancel a hero's heavy wind-up or charge: it costs half its cooldown. Returns true when one was cut.
function BlockService.interruptHero(hero: any, info: any): boolean
	local now = os.clock()
	if not winding(hero, now) or not GuardMath.isInterrupt(G, info) then
		return false
	end
	local cutNum: number? = nil
	local cd = 0
	local w = hero.windup
	if w and not w.cancelled and now < w.untilT then
		w.cancelled = true
		cutNum = w.num
		cd = GuardMath.refund(G, w.full)
		local left = Cooldowns.left(hero.cooldowns, w.id, now)
		if left > cd then
			Cooldowns.reduce(hero.cooldowns, w.id, left - cd)
		end
	end
	for num, at in hero.chargeAt or {} do
		if charging(num, at, now) then
			local row = A.byNum[num]
			cutNum = num
			cd = GuardMath.refund(G, HeroService.effective(hero, row.id).cd or row.cd or 0)
			Cooldowns.start(hero.cooldowns, row.id, now, cd)
			hero.chargeAt[num] = nil
		end
	end
	if BlockService.chargeCut then
		BlockService.chargeCut(hero)
	end
	if not cutNum then
		return false
	end
	local pos = HeroService.position(hero) or Vector3.zero
	word("cut", pos, if info.attacker and info.attacker.player then info.attacker.player.UserId else 0)
	if info.attacker then
		BlockService.Outcome:Fire(info.attacker, "cut", hero)
	end
	send(hero, { cut = cutNum, cd = cd })
	return true
end

---------------------------------------------------------------------------
-- Robots
---------------------------------------------------------------------------

local function robotFighting(e: any): boolean
	return e.target ~= nil and (e.state == 2 or e.state == 3) -- EnemySim.CHASE, EnemySim.ATTACK
end

local function robotBusy(e: any, now: number): boolean
	return (e.windupUntil or 0) > now or Status.has(e.status, "stun", now) or Status.lifted(e.status, now)
end

-- A hero's hit about to land on a robot. info: { coeff, charged, grab, breaker, status, status2, from }.
-- Returns the damage multiplier and the hit flag (0 hit, 1 blocked, 2 broke) for the result record, and
-- whether the hit is blocked (no knockback).
function BlockService.robotHit(hero: any, id: number, info: any): (number, number?, boolean)
	local e = EnemyService.get(id)
	if not e or not e.alive then
		return 1, nil, false
	end
	local now = EnemyService.now()
	local actor = if hero.player then hero.player.UserId else hero.id
	local at = Vector3.new(e.x, e.y, e.z)
	-- an interrupt on a robot winding up: it reels and the slam or sweep never lands
	if (e.windupUntil or 0) > now and GuardMath.isInterrupt(G, info) then
		EnemyService.applyStatus(id, "stun", G.interrupt.robotStun)
		word("cut", at, actor)
		BlockService.Outcome:Fire(hero, "cut", nil)
	end
	local breaker = GuardMath.isBreaker(G, info)
	-- the Null Sentinel's front guard: a breaker shatters it like a flank hit does
	local cfg = e.cfg
	if breaker and cfg and cfg.guard and now >= (e.guardBrokenUntil or 0) then
		e.guardBrokenUntil = now + cfg.guard.breakTime
		EnemyService.applyStatus(id, "stun", math.max(cfg.guard.breakStun, G.breaker.stagger))
		word("shatter", at, actor)
		BlockService.Outcome:Fire(hero, "break", nil)
		return 1, 2, false
	end
	local rb = G.robotBlocks[e.kind]
	local rs = robots[id]
	if not rb or not rs then
		return 1, nil, false
	end
	local fx, fz = -math.sin(e.yaw or 0), -math.cos(e.yaw or 0) -- EnemySim's yaw convention
	local front = true
	if info.from then
		front = GuardMath.front(rb.front, fx, fz, e.x, e.z, info.from.X, info.from.Z)
	end
	local outcome, mult = GuardMath.robotHit(G, rb, rs, {
		coeff = info.coeff,
		charged = info.charged,
		grab = info.grab,
		breaker = info.breaker,
		front = front,
	}, now)
	if outcome == "shatter" then
		EnemyService.applyStatus(id, "stun", G.breaker.stagger)
		word("shatter", at, actor)
		table.insert(events, { k = "rdown", x = e.x, y = e.y, z = e.z, a = id })
		BlockService.Outcome:Fire(hero, "break", nil)
		return mult, 2, false
	elseif outcome == "blocked" then
		return mult, 1, true
	end
	return mult, nil, false -- not blocking, or around the shield
end

local function stepRobots(now: number)
	local seen = {}
	for _, c in EnemyService.candidates() do
		local e = EnemyService.get(c.id)
		local rb = e and G.robotBlocks[e.kind]
		if e and rb and e.alive then
			seen[c.id] = true
			local rs = robots[c.id]
			if not rs then
				rs = GuardMath.robotNew(rb, now)
				robots[c.id] = rs
			end
			local change = GuardMath.robotStep(rb, rs, now, robotFighting(e), robotBusy(e, now))
			if change == "start" then
				table.insert(events, { k = "rup", x = e.x, y = e.y, z = e.z, a = c.id, t = rb.time })
			elseif change == "stop" then
				table.insert(events, { k = "rdown", x = e.x, y = e.y, z = e.z, a = c.id })
			end
		end
	end
	for id in robots do
		if not seen[id] then
			robots[id] = nil
		end
	end
end

-- Is this robot holding a timed block now (CombatService draws a blocked hit; tests and the Dev panel)
function BlockService.robotBlocking(id: number): boolean
	local rs = robots[id]
	return rs ~= nil and GuardMath.robotBlocking(rs, EnemyService.now())
end

local function flushEvents()
	if #events == 0 then
		return
	end
	local list = events
	events = {}
	local r2 = G.stateRadius * G.stateRadius
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local p = root.Position
			local mine = {}
			for _, ev in list do
				local dx, dy, dz = ev.x - p.X, ev.y - p.Y, ev.z - p.Z
				if dx * dx + dy * dy + dz * dz <= r2 then
					table.insert(mine, ev)
				end
			end
			if #mine > 0 then
				Net.fire("GuardEvent", player, mine)
			end
		end
	end
end

---------------------------------------------------------------------------

-- Every hit on a hero from a robot, a boss or anything without its own resolve (HeroService.damage).
-- Returns the damage to take.
local function hook(hero: any, amount: number, source: any?): number
	if not source or source.guarded or source.pvp or source.quiet then
		return amount
	end
	local from: Vector3? = nil
	local info: any = { damage = amount }
	if source.enemy then
		local e = EnemyService.get(source.enemy)
		if e then
			from = Vector3.new(e.x, e.y, e.z)
			info.breaker = G.robotBreakers[e.ai] == true
			info.coeff = e.cfg and e.cfg.coeff
			info.enemy = source.enemy
			if G.interrupt.robotsInterrupt and info.coeff then
				BlockService.interruptHero(hero, { coeff = info.coeff })
			end
		end
	elseif source.boss then
		info.breaker = false
	end
	info.from = from
	local r = BlockService.resolveHero(hero, info)
	return amount * r.mult
end

function BlockService.init()
	HeroService.guardHook = hook
	-- blocking halves movement (HeroService.speedMult reads this)
	HeroService.speedHooks = HeroService.speedHooks or {}
	HeroService.speedHooks.block = function(hero: any): number
		return if BlockService.blocking(hero) then G.block.moveMult else 1
	end
	Net.on("CombatBlock", function(player: Player, on: boolean)
		local hero = HeroService.get(player)
		if hero then
			setBlock(hero, on)
		end
	end)
	-- Parry Stance and the Martial Arts parry count as perfect blocks
	HeroService.Parried:Connect(function(hero: any, source: any)
		local pos = HeroService.position(hero) or Vector3.zero
		word("perfect", pos, if hero.player then hero.player.UserId else hero.id)
		BlockService.Outcome:Fire(hero, "perfect", source and source.pvp)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local hero = HeroService.get(player)
		if hero then
			states[hero.id] = nil
			lastWord[hero.id] = nil
		end
		lastWord[player.UserId] = nil
	end)
	local acc = 0
	local flushAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		flushAcc += dt
		local now = os.clock()
		if acc >= G.robotTick then
			acc = 0
			stepRobots(EnemyService.now())
			-- a block ends when its owner is stunned, Downed or out of Guard; the bar refills on its own
			for id, st in states do
				local hero = HeroService.byId(id)
				if not hero then
					states[id] = nil
				elseif st.on and (not hero.alive or HeroService.disabled(hero)) then
					setBlock(hero, false)
				end
			end
			for _, hero in HeroService.all() do
				local st = states[hero.id]
				if st and not st.on and hero.player and GuardMath.guard(G, st, now) < G.block.guardMax then
					send(hero)
				end
			end
		end
		if flushAcc >= 0.1 then
			flushAcc = 0
			flushEvents()
		end
	end)
end

return BlockService
