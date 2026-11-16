-- CombatService: server-authoritative hit resolution for all 40 abilities (spec: Hit resolution, Damage and
-- stats formulas, the ability table). The client plays effects at once (prediction); the server checks the
-- ability is equipped, off cooldown (100 ms leeway), the hero is up, and builds a CastPlan from the
-- attacker's position rewound by its lag (at most 150 ms) with line of sight through the city. Damage,
-- statuses, dashes, fields, channels, buffs, walls and ramps are applied here only. Results go out in 10 Hz
-- batches to players within 150 studs. Clients never send damage, targets' positions or results.
-- Also here: class passives (Overcharge, Momentum, the Bruiser taunt), Awakening's damage and super boost,
-- the meter gains, recasts, combo strings, echoes, cast windups, Parry Stance ripostes and team-up combos.
-- M5: abilities with structDmg (and every super) hit buildings and flip vehicles where they land; a heavy hit
-- (coeff 2.5+) flips nearby vehicles and knocks a robot through a wall it is near (the wall turns Damaged).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local HitQuery = require(Shared:WaitForChild("HitQuery"))
local CastPlan = require(Shared:WaitForChild("CastPlan"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local Awakening = require(Shared:WaitForChild("Awakening"))
local Status = require(Shared:WaitForChild("Status"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local EnemyService = require(script.Parent.EnemyService)
local PerfMonitor = require(script.Parent.PerfMonitor)
local BuildingService = require(script.Parent.BuildingService)
local VehicleService = require(script.Parent.VehicleService)

local CombatService = {}

CombatService.Killed = Signal.new() -- (hero, enemy) a hero's hit finished a machine

local A = Config.Abilities
local C = Config.Combat
local DS = Config.Destruction
local CHEST = Vector3.new(0, 1.5, 0)

-- Result kinds on the wire (r.k)
local K = { CAST = 1, WINDUP = 2, TICK = 3, LAND = 4, ECHO = 5, END = 6, COMBO = 7, RIPOSTE = 8 }
CombatService.KIND = K

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include

local function los(ox: number, oy: number, oz: number, tx: number, ty: number, tz: number): boolean
	local from = Vector3.new(ox, oy, oz)
	local dir = Vector3.new(tx, ty, tz) - from
	local hit = Workspace:Raycast(from, dir, losParams)
	return hit == nil or (hit.Position - from).Magnitude >= dir.Magnitude - 3
end

local world: CastPlan.World = {
	los = los,
	rayDist = function(ox, oy, oz, dx, dy, dz, max)
		if max <= 0 then
			return 0
		end
		local hit = Workspace:Raycast(Vector3.new(ox, oy, oz), Vector3.new(dx, dy, dz) * max, losParams)
		return if hit then (hit.Position - Vector3.new(ox, oy, oz)).Magnitude else max
	end,
	groundY = function(x, y, z)
		local hit = Workspace:Raycast(Vector3.new(x, y + 2, z), Vector3.new(0, -600, 0), losParams)
		return if hit then hit.Position.Y else 0
	end,
}

local pending: { any } = {}
local timers: { { at: number, fn: () -> () } } = {}
local fields: { any } = {}
local combos = Awakening.comboBook()
local partsFolder: Folder

local function after(delay: number, fn: () -> ())
	table.insert(timers, { at = os.clock() + delay, fn = fn })
end
CombatService.after = after

local function slotOf(hero: any, id: string): string?
	local l = hero.loadout
	if l.basic == id then
		return "basic"
	end
	if table.find(l.skills, id) then
		return "skill"
	end
	if l.super == id then
		return "super"
	end
	return nil
end

-- Damage for one hit: Power x coeff x class x crit, then passives and Awakening
-- eff: the ability (its power set gets the Epic 2-piece bonus). Crits come from Precision (gear),
-- Lucky Strike (every 8th hit) and the Blaster's Overcharge.
local function rollDamage(hero: any, coeff: number, eff: any?): (number, boolean)
	local crit = false
	local chance = Formulas.critChance(Config, hero.stats.Precision)
	if chance > 0 and math.random() < chance then
		crit = true
	end
	if hero.perks.LuckyStrike then
		hero.luckyCount += 1
		if hero.luckyCount % Config.Gear.perks.LuckyStrike.every == 0 then
			crit = true
		end
	end
	local dmg = Formulas.damage(Config, HeroService.power(hero), coeff, hero.classId, crit, 0)
	local passive = Config.Classes[hero.classId].passive
	if passive.id == "Overcharge" then
		-- Blaster: every 5th hit deals +30%
		hero.hitCount += 1
		if hero.hitCount % passive.everyNth == 0 then
			dmg *= 1 + passive.bonus
			crit = true -- drawn as a crit so the pop reads
		end
	elseif passive.id == "Momentum" then
		-- Speedster: +1% per 10 studs/s of speed, up to +10%
		local speed = MoveGuard.speed(hero)
		dmg *= 1 + math.min(passive.max, math.floor(speed / 10) * passive.perTenSpeed)
	end
	if eff and eff.set and hero.setDamage[eff.set] then
		dmg *= 1 + hero.setDamage[eff.set] -- Epic set, 2 pieces
	end
	dmg *= Awakening.damageMult(Config, hero.meter, os.clock())
	return dmg, crit
end

local function record(hero: any, num: number, seq: number, kind: number, origin: Vector3, dir: Vector3): any
	local r = { a = hero.id, n = num, s = seq, k = kind, o = origin, d = dir, h = {} }
	table.insert(pending, r)
	return r
end

local function flatDir(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

local function ccMult(hero: any): number
	local class = Config.Classes[hero.classId]
	return 1 + (class.ccBonus or 0)
end

-- One status on one enemy from an ability (`from` is where it came from: the hero or a field's centre)
local function applyStatus(
	hero: any,
	eff: any,
	kind: string,
	dur: number,
	id: number,
	at: Vector3,
	from: Vector3,
	knockDir: Vector3?
)
	if kind == "knockback" then
		local dir = knockDir or flatDir(at - from)
		local wall = EnemyService.knock(id, dir, eff.knock or 8)
		EnemyService.applyStatus(id, "stun", 0.25) -- a moment of stagger so it does not shoot mid-flight
		if wall and eff.stunOnWall then
			EnemyService.applyStatus(id, "stun", eff.stunOnWall * ccMult(hero))
		end
	elseif kind == "pull" then
		local d = (at - from).Magnitude
		local time = math.max(0.35, dur)
		EnemyService.applyStatus(id, "pull", time, {
			x = from.X,
			y = from.Y,
			z = from.Z,
			speed = math.max(Config.Abilities.status.pullSpeed, d / 0.4),
			src = hero.id,
		})
	elseif kind == "slow" then
		EnemyService.applyStatus(id, "slow", dur * ccMult(hero), { value = eff.slow or 0.6, src = hero.id })
	elseif kind == "taunt" then
		EnemyService.applyStatus(id, "taunt", dur, { src = hero.id })
	else
		EnemyService.applyStatus(id, kind, dur * ccMult(hero), { src = hero.id })
	end
end

-- Structure damage where an ability lands (spec: Destruction "Ability field structDmg"). kind 1: a slam or
-- landing (crater), 2: a blast (cracks).
local STRUCT_SHAPES =
	{ bolt = true, chain = true, dash = true, cone = true, arc = true, nova = true, line = true }
local function structural(eff: any, center: Vector3, radius: number, kind: number)
	local dmg = eff.structDmg or (if eff.slot == "super" then DS.superStruct else 0)
	if dmg > 0 then
		BuildingService.hit(center, radius, dmg, kind)
		VehicleService.hit(center, radius)
	end
end

-- Apply one hit. Returns true when it killed.
local function applyHit(
	hero: any,
	eff: any,
	r: any,
	cand: any,
	coeff: number,
	primary: boolean,
	from: Vector3,
	knockDir: Vector3?,
	noStatus: boolean?
): boolean
	if coeff <= 0 and not eff.status then
		return false
	end
	local dmg, crit = 0, false
	if coeff > 0 then
		dmg, crit = rollDamage(hero, coeff, eff)
	end
	local killed, e, dealt, flag = EnemyService.damage(cand.id, dmg, hero.id, from)
	if not e then
		return false
	end
	table.insert(r.h, {
		cand.id,
		math.floor(dealt + 0.5),
		if crit then 1 else 0,
		if killed then 1 else 0,
		e.x,
		e.y,
		e.z,
		flag,
	})
	local heavy = coeff >= C.heavyCoeff
	if heavy then
		-- Vehicle flip (spec: Clash moments): any heavy hit flips cars and trams next to the target
		VehicleService.hit(Vector3.new(e.x, e.y, e.z), DS.vehicles.hitRadius)
	end
	if killed then
		HeroService.gainMeter(hero, "kill", 1)
		CombatService.Killed:Fire(hero, e)
		if hero.perks.CoolingKill then
			-- Cooling Kill: a kill refunds 20% of the super's cooldown
			local sup = hero.loadout.super
			if sup then
				local left = Cooldowns.left(hero.cooldowns, sup, os.clock())
				if left > 0 then
					local full = hero.cooldowns.length[sup] or left
					local cut = full * Config.Gear.perks.CoolingKill.refund
					Cooldowns.reduce(hero.cooldowns, sup, cut)
					if hero.player then
						Net.fire("CooldownCut", hero.player, A.list[sup].num, cut)
					end
				end
			end
		end
		return true
	end
	if noStatus then
		return false
	end
	local at = Vector3.new(e.x, e.y, e.z)
	if heavy and primary then
		-- Knockback arc (spec: Clash moments): a heavy hit near a wall throws the robot through it
		local through = BuildingService.clash(hero, at, from)
		if through then
			EnemyService.knock(cand.id, through, DS.clash.knock)
		end
	end
	if eff.status and (primary or not eff.firstOnly) then
		applyStatus(hero, eff, eff.status, eff.statusDur or 1, cand.id, at, from, knockDir)
	end
	if eff.status2 then
		applyStatus(hero, eff, eff.status2, eff.status2Dur or 1, cand.id, at, from, knockDir)
	end
	local class = Config.Classes[hero.classId]
	if class.passive.id == "StandFirm" then
		applyStatus(hero, eff, "taunt", C.tauntTime, cand.id, at, from) -- the Bruiser draws fire
	end
	return false
end

local function hitArea(
	hero: any,
	eff: any,
	r: any,
	center: Vector3,
	radius: number,
	coeff: number,
	noStatus: boolean?
): number
	local list = CastPlan.area(center.X, center.Y, center.Z, radius, EnemyService.candidates(), los)
	for _, c in list do
		applyHit(hero, eff, r, c, coeff, true, center, nil, noStatus)
	end
	return #list
end

-- A perk burst around a point (Quakeheel, Echo Trail), drawn like an area hit of the hero's basic.
-- quiet: no result record (the trail ticks too often to draw each one)
function CombatService.burst(hero: any, center: Vector3, radius: number, coeff: number, quiet: boolean?)
	local basic = A.list[hero.loadout.basic or "ZapBolt"]
	local eff = { set = basic.set }
	local r = record(hero, basic.num, 0, K.END, center, Vector3.new(0, -1, 0))
	r.c, r.r = center, radius
	hitArea(hero, eff, r, center, radius, coeff, true)
	if quiet and #r.h == 0 then
		table.remove(pending, table.find(pending, r) :: number)
	end
end

local function heroesNear(pos: Vector3, radius: number): { any }
	local out = {}
	for _, h in HeroService.all() do
		local p = h.alive and HeroService.position(h)
		if p and (p - pos).Magnitude <= radius then
			table.insert(out, h)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Fields, walls, ramps, buffs
---------------------------------------------------------------------------

local function addField(
	hero: any,
	eff: any,
	num: number,
	pos: Vector3,
	follow: boolean,
	duration: number,
	overrides: any?
)
	if #fields >= C.maxFields then
		table.remove(fields, 1)
	end
	local now = os.clock()
	local f = {
		hero = hero,
		eff = eff,
		num = num,
		pos = pos,
		follow = follow,
		untilT = now + duration,
		nextTick = now,
		tick = eff.tick or 0.5,
		radius = eff.radius or 10,
		coeff = eff.coeff,
	}
	if overrides then
		for k, v in overrides do
			f[k] = v
		end
	end
	table.insert(fields, f)
	return f
end

local function icePart(size: Vector3, cf: CFrame, life: number, collide: boolean): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Ice
	p.Color = Color3.fromRGB(200, 235, 255)
	p.Transparency = 0.15
	p.Size = size
	p.CFrame = cf
	p.Parent = partsFolder
	Debris:AddItem(p, life)
	return p
end

local function makeWall(hero: any, eff: any, num: number, pieces: { { number } })
	local now = os.clock()
	for _, pc in pieces do
		local pos = Vector3.new(pc[1], pc[2], pc[3])
		-- the wall stops shots, not heroes (no griefing doorways) (PLACEHOLDER ART: plain ice slabs)
		icePart(
			Vector3.new(6.5, 8, 1.6),
			CFrame.new(pos) * CFrame.Angles(0, math.rad(pc[4]), 0),
			eff.duration,
			false
		)
		EnemyService.addBlocker(pos, 4.2, now + eff.duration)
		if eff.touchCoeff then
			addField(
				hero,
				eff,
				num,
				pos,
				false,
				eff.duration,
				{ radius = 4.5, tick = 0.5, coeff = eff.touchCoeff, status = false }
			)
		end
	end
end

local function makeRamp(hero: any, eff: any, num: number, piece: { number })
	local len = eff.range
	local yaw = math.rad(piece[4])
	local height = len * 0.22
	local base = CFrame.new(piece[1], piece[2] + height / 2, piece[3]) * CFrame.Angles(0, yaw, 0)
	-- a wedge rising along the aim; slick ice (PLACEHOLDER ART)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanQuery = false
	w.Material = Enum.Material.Ice
	w.Color = Color3.fromRGB(200, 235, 255)
	w.Transparency = 0.1
	w.Size = Vector3.new(8, height, len)
	w.CFrame = base * CFrame.Angles(0, math.pi, 0)
	w.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0, 0.5, 100, 1)
	w.Parent = partsFolder
	Debris:AddItem(w, eff.duration)
	if eff.slowTouch then
		addField(hero, eff, num, Vector3.new(piece[1], piece[2], piece[3]), false, eff.duration, {
			radius = len / 2,
			tick = 0.5,
			coeff = 0,
			status = "slow",
			slow = 0.6,
			statusDur = 0.6,
		})
	end
end

local function applyBuff(hero: any, eff: any, r: any)
	local pos = HeroService.position(hero)
	if not pos then
		return
	end
	local targets = { hero }
	if eff.allies then
		for _, h in heroesNear(pos, eff.radius or 20) do
			if h ~= hero then
				table.insert(targets, h)
			end
		end
	end
	local class = Config.Classes[hero.classId]
	for _, h in targets do
		local value = eff.value or 0
		if h ~= hero and class.supportBonus then
			value *= 1 + class.supportBonus -- Controller: buffs on allies are 25% stronger
		end
		if eff.buff == "shield" then
			value = math.floor(h.maxHealth * value + 0.5)
		end
		HeroService.buff(h, eff.buff, value, eff.duration)
		if eff.heal then
			HeroService.heal(h, h.maxHealth * eff.heal)
		end
		if h ~= hero then
			-- support for the world boss ledger: shield points and healing given to allies
			local given = (if eff.buff == "shield" then value else 0) + h.maxHealth * (eff.heal or 0)
			HeroService.Supported:Fire(hero, if given > 0 then given else h.maxHealth * 0.05)
		end
		if eff.staminaFree then
			MoveGuard.freeStamina(h, os.clock() + eff.duration)
			HeroService.buff(h, "zeroG", 1, eff.duration)
		end
	end
	r.dur = eff.duration
	r.x = #targets
	if eff.taunt then
		-- Brace: machines within the taunt radius attack this hero
		for _, c in CastPlan.area(pos.X, pos.Y, pos.Z, eff.taunt, EnemyService.candidates(), nil) do
			EnemyService.applyStatus(c.id, "taunt", eff.duration, { src = hero.id })
		end
	end
	if eff.burst then
		-- Shatter Shell: the armor bursts when it ends
		after(eff.duration, function()
			local p = HeroService.position(hero)
			if hero.alive and p then
				local r2 = record(hero, r.n, r.s, K.END, p + CHEST, r.d)
				r2.c, r2.r = p, eff.radius or 12
				hitArea(hero, eff, r2, p, eff.radius or 12, eff.burst)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Resolve one use
---------------------------------------------------------------------------

local function gainFor(hero: any, eff: any, count: number)
	if count <= 0 then
		return
	end
	local kind = if eff.slot == "basic"
		then "basicHit"
		elseif eff.slot == "super" then "superHit"
		else "skillHit"
	HeroService.gainMeter(hero, kind, count)
end

local function comboCheck(hero: any, eff: any, pos: Vector3, num: number, seq: number)
	local pair, other = Awakening.noteSuper(Config, combos, {
		hero = hero.id,
		set = eff.set,
		x = pos.X,
		y = pos.Y,
		z = pos.Z,
		t = os.clock(),
	})
	if not pair or not other then
		return
	end
	local partner = HeroService.byId(other.hero)
	local mid = (pos + Vector3.new(other.x, other.y, other.z)) / 2
	local r = record(hero, num, seq, K.COMBO, mid, Vector3.new(0, 1, 0))
	r.c, r.r = mid, pair.radius
	for i, p in A.combos.pairs do
		if p == pair then
			r.x = i
		end
	end
	r.p = other.hero
	local now = os.clock()
	hero.comboBonusUntil = now + A.combos.bonusTime -- +25% Renown from kills (M3 pays it)
	if partner then
		partner.comboBonusUntil = now + A.combos.bonusTime
	end
	local comboEff =
		{ coeff = pair.coeff, status = pair.status, statusDur = pair.statusDur, slow = pair.slow }
	hitArea(hero, comboEff, r, mid, pair.radius, pair.coeff)
end

local function echo(hero: any, eff: any, num: number, seq: number, origin: Vector3, dir: Vector3, plan: any)
	after(C.echoDelay, function()
		if not hero.alive then
			return
		end
		local r = record(hero, num, seq, K.ECHO, origin, dir)
		local cands = EnemyService.candidates()
		local list
		if plan.cx then
			local c = Vector3.new(plan.cx, plan.cy, plan.cz)
			r.c, r.r = c, plan.radius
			list = CastPlan.area(c.X, c.Y, c.Z, plan.radius, cands, los)
		else
			local e = Vector3.new(plan.ex or origin.X, plan.ey or origin.Y, plan.ez or origin.Z)
			r.e = e
			list = HitQuery.capsule(origin.X, origin.Y, origin.Z, e.X, e.Y, e.Z, eff.width or 6, cands)
		end
		for _, c in list do
			applyHit(hero, eff, r, c, eff.coeff * eff.echo, true, origin, nil)
		end
	end)
end

local function resolve(
	hero: any,
	eff: any,
	num: number,
	seq: number,
	origin: Vector3,
	dir: Vector3,
	hint: number
): boolean
	local now = os.clock()
	local rangeBonus = 0
	if eff.slot == "basic" and eff.shape == "bolt" and hero.classId == "Blaster" then
		rangeBonus = math.max(0, Config.Classes.Blaster.basicRange - eff.range)
	end
	local comboStep = 1
	if eff.hits then
		comboStep = AbilityRules.comboStep(hero.combo.at, hero.combo.step, now, #eff.hits)
		hero.combo.at, hero.combo.step = now, comboStep
	end
	local plan = CastPlan.build(
		eff,
		origin.X,
		origin.Y,
		origin.Z,
		dir.X,
		dir.Y,
		dir.Z,
		hint,
		EnemyService.candidates(),
		world,
		{
			comboStep = comboStep,
			rangeBonus = rangeBonus,
			aimSlack = C.aimSlack,
			reach = C.reachSlack,
		}
	)
	if not plan then
		return false
	end
	local r = record(hero, num, seq, K.CAST, origin, dir)
	r.m = comboStep
	if eff.awakenedSuper then
		r.aw = 1
	end
	if plan.ex then
		r.e = Vector3.new(plan.ex, plan.ey, plan.ez)
	end
	if plan.cx then
		r.c, r.r = Vector3.new(plan.cx, plan.cy, plan.cz), plan.radius
	end
	if plan.twin then
		r.t = Vector3.new(plan.twin[1], plan.twin[2], plan.twin[3])
	end

	-- hero travel (dashes, the Thunder Drop dive)
	if plan.moveHero and plan.ex and plan.shape ~= "leap" then
		local to = Vector3.new(plan.ex, plan.ey, plan.ez)
		MoveGuard.grant(hero, (to - origin).Magnitude + 10)
		if hero.bot then
			hero.bot.position = to - CHEST
		end
	end

	local knockDir = if plan.shape == "dash" then flatDir(dir) else nil
	local from = if plan.shape == "nova" and plan.cx then Vector3.new(plan.cx, plan.cy, plan.cz) else origin
	for _, h in plan.hits do
		applyHit(hero, eff, r, h.c, h.coeff, h.primary, from, knockDir)
	end
	gainFor(hero, eff, #plan.hits)
	-- structure damage where it lands (leaps and throws land later, below)
	if STRUCT_SHAPES[plan.shape] and (eff.structDmg or eff.slot == "super") then
		local at = if plan.cx
			then Vector3.new(plan.cx, plan.cy, plan.cz)
			elseif plan.ex then Vector3.new(plan.ex, plan.ey, plan.ez)
			else origin + dir * math.min(eff.range or 20, 60)
		structural(eff, at, plan.radius or eff.radius or 12, if plan.shape == "nova" then 1 else 2)
	end
	-- Epic set 4-piece changes on novas: Rimeguard ally shields, Ironclad shockwave field
	if plan.shape == "nova" then
		if eff.allyShield then
			for _, h in heroesNear(from, eff.radius or 14) do
				if h ~= hero then
					local pts = math.floor(h.maxHealth * eff.allyShield + 0.5)
					HeroService.buff(h, "shield", pts, 4)
					HeroService.Supported:Fire(hero, pts)
				end
			end
		end
		if eff.fieldCoeff then
			addField(
				hero,
				eff,
				num,
				from,
				false,
				eff.fieldDur or 3,
				{ coeff = eff.fieldCoeff, tick = 0.5, status = false }
			)
			r.dur = eff.fieldDur or 3
		end
	end
	-- Orbitwear 4-piece: Float heals allies near the lifted target 3% a second
	if eff.allyHeal and plan.hits[1] then
		local c = plan.hits[1].c
		local at = Vector3.new(c.x, c.y, c.z)
		local ticks = math.floor(eff.statusDur or 3)
		for t = 1, ticks do
			after(t, function()
				for _, h in heroesNear(at, eff.allyRadius or 12) do
					HeroService.heal(h, h.maxHealth * eff.allyHeal)
					if h ~= hero then
						HeroService.Supported:Fire(hero, h.maxHealth * eff.allyHeal)
					end
				end
			end)
		end
	end

	if plan.channel and #plan.channel.ids > 0 then
		hero.channel = {
			ids = plan.channel.ids,
			ticksLeft = plan.channel.ticks,
			tick = plan.channel.tick,
			nextAt = now,
			eff = eff,
			num = num,
			seq = seq,
		}
		r.dur = plan.channel.ticks * plan.channel.tick
		r.x = plan.channel.ids[1]
	end
	if plan.field then
		local f = plan.field
		local pos = Vector3.new(f.x, f.y, f.z)
		addField(hero, eff, num, pos, f.follow, eff.duration)
		r.c, r.r, r.dur, r.f = pos, eff.radius, eff.duration, if f.follow then 1 else 0
	end
	if plan.buff then
		applyBuff(hero, eff, r)
	end
	if plan.pieces then
		if plan.shape == "wall" then
			makeWall(hero, eff, num, plan.pieces)
		else
			makeRamp(hero, eff, num, plan.pieces[1])
		end
		r.dur = eff.duration
	end
	if plan.shape == "leap" and plan.cx then
		local land = Vector3.new(plan.cx, plan.cy, plan.cz)
		MoveGuard.grant(hero, (land - origin).Magnitude + 40)
		r.dur = plan.delay
		after(plan.delay or 1, function()
			if not hero.alive then
				return
			end
			if hero.bot then
				hero.bot.position = land
			end
			local r2 = record(hero, num, seq, K.LAND, origin, dir)
			r2.c, r2.r = land, plan.radius
			gainFor(hero, eff, hitArea(hero, eff, r2, land, plan.radius, eff.coeff))
			structural(eff, land, plan.radius or 12, 1)
			if eff.fieldCoeff then
				addField(
					hero,
					eff,
					num,
					land,
					false,
					eff.fieldDur or 3,
					{ coeff = eff.fieldCoeff, tick = 0.5, status = false }
				)
				r2.dur = eff.fieldDur or 3
			end
			if eff.echo then
				echo(hero, eff, num, seq, origin, dir, plan)
			end
		end)
	elseif plan.shape == "throw" and plan.cx then
		local land = Vector3.new(plan.cx, plan.cy, plan.cz)
		r.x = plan.thrown or 0
		r.dur = plan.delay
		if plan.thrown then
			EnemyService.applyStatus(plan.thrown, "float", plan.delay or 0.5)
		end
		after(plan.delay or 0.5, function()
			if plan.thrown then
				EnemyService.place(plan.thrown, land)
			end
			local r2 = record(hero, num, seq, K.LAND, origin, dir)
			r2.c, r2.r = land, plan.radius
			gainFor(hero, eff, hitArea(hero, eff, r2, land, plan.radius, eff.coeff))
			structural(eff, land, plan.radius or 8, 1)
		end)
	elseif eff.echo then
		echo(hero, eff, num, seq, origin, dir, plan)
	end
	if eff.selfShield then
		HeroService.buff(hero, "shield", math.floor(hero.maxHealth * eff.selfShield + 0.5), 4)
	end
	if eff.slot == "super" then
		comboCheck(hero, eff, origin, num, seq)
	end
	return true
end

-- Shared by players (CombatUse) and load bots. Returns true when the use was accepted.
function CombatService.use(
	hero: any,
	num: number,
	aim: Vector3,
	hint: number,
	seq: number,
	latency: number
): boolean
	local row = A.byNum[num]
	if not row or not hero.alive then
		return false
	end
	local slot = slotOf(hero, row.id)
	if not slot then
		return false
	end
	local now = os.clock()
	if not Cooldowns.ready(hero.cooldowns, row.id, now, C.cooldownLeeway) then
		return false
	end
	if AbilityRules.blocked(hero.recast, row.id, now) then
		return false
	end
	if aim.Magnitude < 0.5 then
		return false
	end
	local dir = aim.Unit
	local root = MoveGuard.rewound(hero, latency)
	if not root then
		return false
	end
	local eff = HeroService.effective(hero, row.id)
	local awake = HeroService.awakened(hero)
	if slot == "super" and awake then
		local aw = A.awakening
		eff.coeff *= 1 + aw.superCoeff
		if eff.radius then
			eff.radius *= 1.15
		end
		eff.awakenedSuper = true
	end
	local full = AbilityRules.cooldown(Config, Formulas, eff, {
		classId = hero.classId,
		focus = hero.stats.Focus,
		attackSpeed = Status.value(hero.status, "attackSpeed", now, 0),
		awakened = awake,
	})
	Cooldowns.start(hero.cooldowns, row.id, now, AbilityRules.afterUse(hero.recast, row.id, eff, now, full))
	hero.channel = nil -- any new use ends a channel
	hero.lastCast = now
	local origin = root + CHEST
	if eff.cast and eff.cast > 0 then
		-- windup: others see it coming; the hit lands from where the hero is when it finishes
		local r = record(hero, num, seq, K.WINDUP, origin, dir)
		r.dur = eff.cast
		after(eff.cast, function()
			local pos = HeroService.position(hero)
			if hero.alive and pos then
				resolve(hero, eff, num, seq, pos + CHEST, dir, hint)
			end
		end)
		return true
	end
	return resolve(hero, eff, num, seq, origin, dir, hint)
end

-- Parry Stance: a blocked hit ripostes at the attacker
local function riposte(hero: any, source: any)
	local row = A.list.ParryStance
	local eff = HeroService.effective(hero, row.id)
	local pos = HeroService.position(hero)
	local e = source.enemy and EnemyService.get(source.enemy)
	if not pos or not e then
		return
	end
	local target = Vector3.new(e.x, e.y, e.z)
	local r = record(hero, row.num, 0, K.RIPOSTE, pos + CHEST, (target - pos).Unit)
	r.e = target
	if (target - pos).Magnitude <= 45 then
		applyHit(hero, eff, r, { id = e.id, x = e.x, y = e.y, z = e.z, r = 2 }, eff.coeff, true, pos)
	end
	if eff.refund then
		Cooldowns.reduce(hero.cooldowns, row.id, eff.cd * eff.refund)
	end
	if eff.riposteHeal then
		HeroService.heal(hero, hero.maxHealth * eff.riposteHeal) -- Edgewalker 4-piece
	end
end

---------------------------------------------------------------------------
-- Ticking: channels, fields, timers
---------------------------------------------------------------------------

local function stepChannels(now: number)
	for _, hero in HeroService.all() do
		local ch = hero.channel
		if ch and now >= ch.nextAt then
			local pos = HeroService.position(hero)
			if not hero.alive or not pos then
				hero.channel = nil
				continue
			end
			local origin = pos + CHEST
			local eff = ch.eff
			local reach = (eff.range or 10) * 1.5 + C.reachSlack
			local r = record(hero, ch.num, ch.seq, K.TICK, origin, Vector3.new(0, 0, -1))
			local live = {}
			for _, id in ch.ids do
				local e = EnemyService.get(id)
				if e and e.alive and (Vector3.new(e.x, e.y, e.z) - origin).Magnitude <= reach then
					table.insert(live, id)
					applyHit(
						hero,
						eff,
						r,
						{ id = id, x = e.x, y = e.y, z = e.z, r = 2 },
						eff.coeff,
						true,
						origin
					)
				end
			end
			if ch.ticksLeft % 4 == 0 then
				gainFor(hero, eff, #live) -- a channel fills the meter like one skill hit per second
			end
			ch.ids = live
			ch.ticksLeft -= 1
			ch.nextAt = now + ch.tick
			if ch.ticksLeft <= 0 or #live == 0 then
				hero.channel = nil
				if #live > 0 and (eff.endStatus or eff.endCoeff) then
					local r2 = record(hero, ch.num, ch.seq, K.END, origin, Vector3.new(0, 0, -1))
					for _, id in live do
						local e = EnemyService.get(id)
						if e then
							local c = { id = id, x = e.x, y = e.y, z = e.z, r = 2 }
							applyHit(hero, eff, r2, c, eff.endCoeff or 0, true, origin, nil, true)
							if eff.endStatus then
								applyStatus(
									hero,
									eff,
									eff.endStatus,
									eff.endStatusDur or 1,
									id,
									Vector3.new(e.x, e.y, e.z),
									origin
								)
							end
						end
					end
				end
			end
		end
	end
end

local function stepFields(now: number)
	local i = 1
	while i <= #fields do
		local f = fields[i]
		local hero = f.hero
		if f.follow then
			local p = HeroService.position(hero)
			if p then
				f.pos = p
			end
		end
		local eff = f.eff
		if now >= f.nextTick then
			f.nextTick = now + f.tick
			local r = record(hero, f.num, 0, K.TICK, f.pos, Vector3.new(0, 1, 0))
			r.c = f.pos
			local fieldEff = {
				coeff = f.coeff,
				status = if f.status ~= nil then f.status else eff.status,
				statusDur = f.statusDur or math.max(eff.statusDur or 0, f.tick + 0.15),
				slow = f.slow or eff.slow,
			}
			if fieldEff.status == "pull" then
				fieldEff.statusDur = f.tick + 0.1
			end
			for _, c in CastPlan.area(f.pos.X, f.pos.Y, f.pos.Z, f.radius, EnemyService.candidates(), nil) do
				applyHit(hero, fieldEff, r, c, f.coeff, true, f.pos, nil)
			end
			if eff.allyResist then
				-- Blizzard Dome: allies inside resist 15%
				for _, h in heroesNear(f.pos, f.radius) do
					HeroService.buff(h, "resist", eff.allyResist, f.tick + 0.3)
				end
			end
		end
		if now >= f.untilT then
			table.remove(fields, i)
			if eff.endCoeff or eff.endStatus then
				local r = record(hero, f.num, 0, K.END, f.pos, Vector3.new(0, 1, 0))
				r.c, r.r = f.pos, f.radius
				for _, c in CastPlan.area(f.pos.X, f.pos.Y, f.pos.Z, f.radius, EnemyService.candidates(), nil) do
					applyHit(hero, eff, r, c, eff.endCoeff or 0, true, f.pos, nil, true)
					if eff.endStatus then
						applyStatus(
							hero,
							eff,
							eff.endStatus,
							eff.endStatusDur or 1,
							c.id,
							Vector3.new(c.x, c.y, c.z),
							f.pos
						)
					end
				end
			end
		else
			i += 1
		end
	end
end

local function stepTimers(now: number)
	local i = 1
	while i <= #timers do
		local t = timers[i]
		if now >= t.at then
			table.remove(timers, i)
			local ok, err = pcall(t.fn)
			if not ok then
				warn("[CombatService] timer failed: " .. tostring(err))
			end
		else
			i += 1
		end
	end
end

local function flush()
	if #pending == 0 then
		return
	end
	local batch = pending
	pending = {}
	local r2 = C.resultRadius * C.resultRadius
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local mine = {}
			for _, r in batch do
				-- ticks with no hits are only for the caster's own numbers; skip them for others
				if r.k == K.TICK and #r.h == 0 then
					continue
				end
				local d = r.o - root.Position
				if r.a == player.UserId or d:Dot(d) <= r2 then
					table.insert(mine, r)
				end
			end
			if #mine > 0 then
				Net.fire("CombatResult", player, mine)
			end
		end
	end
end

function CombatService.fieldCount(): number
	return #fields
end

function CombatService.init()
	partsFolder = Instance.new("Folder")
	partsFolder.Name = "AbilityParts"
	partsFolder.Parent = Workspace
	local city = Workspace:WaitForChild("City")
	losParams.FilterDescendantsInstances = { city }
	Net.on("CombatUse", function(player, num: number, aim: Vector3, hint: number, seq: number)
		local hero = HeroService.get(player)
		if not hero then
			return
		end
		local t0 = os.clock()
		CombatService.use(hero, num, aim, hint, seq, player:GetNetworkPing())
		PerfMonitor.add("combat", (os.clock() - t0) * 1000)
	end)
	Net.on("CombatCancel", function(player, seq: number)
		local hero = HeroService.get(player)
		if hero and hero.channel and hero.channel.seq == seq then
			hero.channel = nil
		end
	end)
	HeroService.Parried:Connect(riposte)
	HeroService.Defeated:Connect(function(hero)
		hero.channel = nil
	end)
	PerfMonitor.watch("fields", function()
		return #fields
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local t0 = os.clock()
		stepTimers(t0)
		stepChannels(t0)
		stepFields(t0)
		PerfMonitor.add("combat", (os.clock() - t0) * 1000)
		acc += dt
		if acc >= 1 / C.resultRate then
			acc = 0
			local t1 = os.clock()
			flush()
			PerfMonitor.add("replication", (os.clock() - t1) * 1000)
		end
	end)
end

return CombatService
