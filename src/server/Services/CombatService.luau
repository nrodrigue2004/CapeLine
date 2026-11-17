-- CombatService: server-authoritative hit resolution for all 40 abilities (spec: Hit resolution, Damage and
-- stats formulas, the ability table). The client plays effects at once (prediction); the server checks the
-- ability is equipped, off cooldown (100 ms leeway), the hero is up, and builds a CastPlan from the
-- attacker's position rewound by its lag (at most 150 ms) with line of sight through the city. Damage,
-- statuses, dashes, fields, channels, buffs, walls and ramps are applied here only. Results go out in 10 Hz
-- batches to players within 150 studs. Clients never send damage, targets' positions or results.
-- Also here: class passives (Overcharge, Momentum, the Bruiser taunt), Awakening's damage and super boost,
-- the meter gains, recasts, combo strings, echoes, cast windups, Parry Stance ripostes and team-up combos.
-- M5: abilities with structDmg (every super, and by slot every other damaging ability) hit buildings and flip vehicles where they land; a heavy hit
-- (coeff 2.5+) flips nearby vehicles and knocks a robot through a wall it is near (the wall turns Damaged).
-- M8: a flagged attacker's candidates include the flagged heroes it may hit (FlagService.targetsFor). Every
-- hit on a hero re-checks both flags when it lands, uses compressed stats (supers 60%, Lucky Strike off,
-- set bonuses half), and crowd control on players has diminishing returns; knockbacks, pulls and knockups
-- reach the target's own client as an impulse (HeroKnock). Heals, shields and buffs skip flagged fighters
-- an unflagged helper may not support. Stunned, lifted or Downed heroes cannot cast.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local HitQuery = require(Shared:WaitForChild("HitQuery"))
local CastPlan = require(Shared:WaitForChild("CastPlan"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local ChargeRules = require(Shared:WaitForChild("ChargeRules"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))
local Awakening = require(Shared:WaitForChild("Awakening"))
local ClashRules = require(Shared:WaitForChild("ClashRules"))
local Status = require(Shared:WaitForChild("Status"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local EnemyService = require(script.Parent.EnemyService)
local PerfMonitor = require(script.Parent.PerfMonitor)
local BuildingService = require(script.Parent.BuildingService)
local VehicleService = require(script.Parent.VehicleService)
local FlagService = require(script.Parent.FlagService)
local Analytics = require(script.Parent.Analytics)
local BlockService = require(script.Parent.BlockService) -- H1: block, breaker, interrupt
local GuardMath = require(Shared:WaitForChild("GuardMath"))

local CombatService = {}
-- DeathService sets this: Dawnburst stands up every Downed ally within the radius
CombatService.reviveHook = nil :: ((any, Vector3, number) -> ())?

CombatService.Killed = Signal.new() -- (hero, enemy) a hero's hit finished a machine
CombatService.WeaponHits = Signal.new() -- (hero, weaponId, hits) a weapon move landed hits (Mastery)

local A = Config.Abilities
local C = Config.Combat
local DS = Config.Destruction
local CHEST = Vector3.new(0, 1.5, 0)

-- Result kinds on the wire (r.k)
local K = { CAST = 1, WINDUP = 2, TICK = 3, LAND = 4, ECHO = 5, END = 6, COMBO = 7, RIPOSTE = 8, CLASH = 9 }
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
local shareLinked: (hero: any, id: number, dealt: number) -> ()
local supportMult: (hero: any) -> number
local combos = Awakening.comboBook()
local clashes = ClashRules.book()
local partsFolder: Folder

local PVP_BASE = HeroService.PVP_BASE

-- What this hero's abilities can hit: robots and targets, plus flagged heroes when it may fight them
local function cands(hero: any): { any }
	local list = EnemyService.candidates()
	for _, c in FlagService.targetsFor(hero) do
		table.insert(list, c)
	end
	return list
end

-- A candidate for one combat id (channels and ripostes keep ids, not positions)
local function candOf(id: number): any?
	if id > PVP_BASE then
		local h = HeroService.bySlot(id)
		local pos = h and h.alive and HeroService.position(h)
		return pos and { id = id, x = pos.X, y = pos.Y, z = pos.Z, r = 2.5, hero = h }
	end
	local e = EnemyService.get(id)
	if e and e.alive then
		return { id = id, x = e.x, y = e.y, z = e.z, r = 2 }
	end
	local t = EnemyService.target(id)
	return t and { id = id, x = t.x, y = t.y, z = t.z, r = t.r }
end

local function after(delay: number, fn: () -> ())
	table.insert(timers, { at = os.clock() + delay, fn = fn })
end
CombatService.after = after

-- The slot of an ability in what the hero holds now: the power's loadout, or the weapon's moves (key 2)
local function slotOf(hero: any, id: string): string?
	local kit = WeaponRules.kit(Config, hero.loadout, hero.held, hero.weapon, hero.weaponMastery)
	return WeaponRules.slotIn(kit, id)
end

-- Damage for one hit: Power x coeff x class x crit, then passives and Awakening
-- eff: the ability (its power set gets the Epic 2-piece bonus). Crits come from Precision (gear),
-- Lucky Strike (every 8th hit), the Elemental's Attunement and the Rogue's Opening.
local function rollDamage(
	hero: any,
	coeff: number,
	eff: any?,
	pvp: boolean?,
	targetId: number?
): (number, boolean)
	local crit = false
	local precision = if pvp then hero.stats.Precision * Config.Pvp.minorScale else hero.stats.Precision
	local chance = Formulas.critChance(Config, precision)
	if chance > 0 and math.random() < chance then
		crit = true
	end
	if (hero.critHits or 0) > 0 and os.clock() < (hero.critUntil or 0) then
		-- Deadeye Mark: the next few hits are critical
		hero.critHits -= 1
		crit = true
	end
	if hero.perks.LuckyStrike and not pvp then -- off in PvP (the Legendary perk table)
		hero.luckyCount += 1
		if hero.luckyCount % Config.Gear.perks.LuckyStrike.every == 0 then
			crit = true
		end
	end
	local dmg = Formulas.damage(Config, HeroService.power(hero), coeff, hero.classId, crit, 0)
	local passive = Config.Classes[hero.classId].passive
	if passive.id == "Attunement" then
		-- Elemental: every 5th hit deals +30%
		hero.hitCount += 1
		if hero.hitCount % passive.everyNth == 0 then
			dmg *= 1 + passive.bonus
			crit = true -- drawn as a crit so the pop reads
		end
	elseif passive.id == "Opening" and not crit and not pvp and targetId then
		-- Rogue: a robot that is not fighting this hero (or a hit from stealth) takes a critical hit
		local e = EnemyService.get(targetId)
		local hidden = Status.has(hero.status, "hidden", os.clock())
		if e and (e.target ~= hero.id or hidden) then
			dmg *= 1 + Config.Stats.precision.critBonus
			crit = true
		end
	end
	if eff and eff.set and hero.setDamage[eff.set] then
		-- Epic set, 2 pieces (half in PvP)
		dmg *= 1 + hero.setDamage[eff.set] * (if pvp then Config.Pvp.setMult else 1)
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

-- Crowd control on a player hit in PvP. Stuns and roots have diminishing returns (Status, pvp); Resolve
-- shortens it at its PvP quarter. Moves (knockback, pull, knockup) go to the target's own client as an
-- impulse, and MoveGuard allows the distance.
local KNOCK_KINDS = { knockback = true, pull = true, knockup = true }
local function pvpStatus(
	hero: any,
	eff: any,
	kind: string,
	dur: number,
	target: any,
	at: Vector3,
	from: Vector3,
	knockDir: Vector3?
)
	local K8 = Config.Pvp.knock
	local resist = 1 - Formulas.ccMultiplier(Config, target.stats.Resolve * Config.Pvp.minorScale)
	if KNOCK_KINDS[kind] then
		local move: Vector3
		local time = 0.35
		if kind == "knockback" then
			move = (knockDir or flatDir(at - from)) * math.min(eff.knock or 8, K8.maxDistance)
		elseif kind == "pull" then
			local d = from - at
			local len = math.clamp(d.Magnitude - 4, 0, K8.maxDistance)
			move = if d.Magnitude > 0.1 then d.Unit * len else Vector3.zero
			time = math.max(0.3, dur)
		else
			move = Vector3.new(0, K8.upSpeed * 0.3, 0)
			HeroService.cc(target, "knockup", math.min(dur, 1), nil, resist)
		end
		if target.player and move.Magnitude > 0.5 then
			MoveGuard.grant(target, move.Magnitude + 10)
			Net.fire("HeroKnock", target.player, { x = move.X, y = move.Y, z = move.Z, time = time })
		end
	elseif kind == "slow" then
		HeroService.cc(target, "slow", dur * ccMult(hero), eff.slow or 0.6, resist)
	elseif kind == "stun" or kind == "root" or kind == "float" then
		HeroService.cc(target, kind, dur * ccMult(hero), nil, resist)
	end
	-- taunt and blind have no meaning on a player
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
	if id > PVP_BASE then
		local target = HeroService.bySlot(id)
		if target and FlagService.canHit(hero, target) then
			pvpStatus(hero, eff, kind, dur, target, at, from, knockDir)
		end
		return
	end
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
-- An ability's structure damage: its own structDmg, else a default by slot for anything that deals damage
local function structOf(eff: any): number
	if eff.structDmg then
		return eff.structDmg
	elseif eff.slot == "super" then
		return DS.superStruct
	elseif (eff.coeff or 0) > 0 and not eff.allyHeal then
		return DS.slotStruct[eff.slot] or 0
	end
	return 0
end

local function structural(eff: any, center: Vector3, radius: number, kind: number)
	local dmg = structOf(eff)
	if not eff.structDmg and eff.slot == "basic" then
		radius = math.min(radius, DS.basicStructRadius)
	end
	if dmg > 0 then
		BuildingService.hit(center, radius, dmg, kind)
		if dmg >= DS.structure.chunkCost then
			VehicleService.hit(center, radius)
		end
	end
end

-- One hit on a flagged hero: both flags are read again now, then compressed damage and PvP crowd control
local function pvpHit(
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
	local target = cand.hero
	if eff.perk or not FlagService.canHit(hero, target) then
		return false -- perk bursts (Quakeheel, Echo Trail) are off in PvP
	end
	local dmg, crit = 0, false
	if coeff > 0 then
		dmg, crit = rollDamage(hero, coeff, eff, true)
		dmg = FlagService.damage(hero, target, dmg, eff.slot == "super")
	end
	FlagService.notePvp(hero, target)
	-- H1: the target's block (on the compressed damage), then any interrupt of its wind-up or charge
	local guardInfo = {
		damage = dmg,
		coeff = coeff,
		charged = eff.charged,
		grab = eff.grab,
		breaker = eff.breaker,
		status = eff.status,
		status2 = eff.status2,
		from = from,
		attacker = hero,
	}
	local guard = BlockService.resolveHero(target, guardInfo)
	dmg *= guard.mult
	if guard.noKnock then
		noStatus = true
	elseif guard.outcome == "hit" then
		BlockService.interruptHero(target, guardInfo)
	end
	local gflag = if guard.outcome == "shatter" then 2 elseif guard.outcome ~= "hit" then 1 else 0
	local dealt = if dmg > 0
		then HeroService.damage(target, dmg, { pvp = hero, at = from, guarded = true })
		else 0
	local killed = not target.alive
	local pos = HeroService.position(target) or Vector3.new(cand.x, cand.y, cand.z)
	table.insert(r.h, {
		cand.id,
		math.floor(dealt + 0.5),
		if crit then 1 else 0,
		if killed then 1 else 0,
		pos.X,
		pos.Y,
		pos.Z,
		gflag,
	})
	if killed then
		if hero.perks.CoolingKill and hero.loadout.super then
			-- Cooling Kill works at half in PvP
			local sup = hero.loadout.super
			local left = Cooldowns.left(hero.cooldowns, sup, os.clock())
			if left > 0 then
				local cut = (hero.cooldowns.length[sup] or left) * Config.Gear.perks.CoolingKill.refund * 0.5
				Cooldowns.reduce(hero.cooldowns, sup, cut)
				if hero.player then
					Net.fire("CooldownCut", hero.player, A.list[sup].num, cut)
				end
			end
		end
		return true
	end
	if noStatus then
		return false
	end
	if eff.status and (primary or not eff.firstOnly) then
		pvpStatus(hero, eff, eff.status, eff.statusDur or 1, target, pos, from, knockDir)
	end
	if eff.status2 then
		pvpStatus(hero, eff, eff.status2, eff.status2Dur or 1, target, pos, from, knockDir)
	end
	return false
end

-- Apply one hit. Returns true when it killed.
-- Soul Chains (Spirit): robots chained together share a part of every hit any of them takes
local links: { [number]: { ids: { number }, untilT: number, share: number, hero: any } } = {}
local sharing = false
shareLinked = function(hero: any, id: number, dealt: number)
	local g = links[id]
	if sharing or not g or dealt <= 0 or dealt == math.huge then
		return
	end
	if os.clock() > g.untilT then
		links[id] = nil
		return
	end
	sharing = true
	for _, other in g.ids do
		if other ~= id and EnemyService.alive(other) then
			EnemyService.damage(other, dealt * g.share, hero.id, nil)
		end
	end
	sharing = false
end

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
	if cand.hero then
		return pvpHit(hero, eff, r, cand, coeff, primary, from, knockDir, noStatus)
	end
	local dmg, crit = 0, false
	if coeff > 0 then
		dmg, crit = rollDamage(hero, coeff, eff, false, cand.id)
	end
	-- H1: a robot's timed block (or the Sentinel's guard) against breakers, and interrupts on its wind-up
	local gmult, gflag, gblocked = BlockService.robotHit(hero, cand.id, {
		coeff = coeff,
		charged = eff.charged,
		grab = eff.grab,
		breaker = eff.breaker,
		status = eff.status,
		status2 = eff.status2,
		from = from,
	})
	dmg *= gmult
	if gblocked then
		noStatus = true -- a blocked hit pushes nothing
	end
	local killed, e, dealt, flag = EnemyService.damage(cand.id, dmg, hero.id, from)
	if not e then
		return false
	end
	if gflag and flag == 0 then
		flag = gflag
	end
	shareLinked(hero, cand.id, dealt or 0)
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
	if heavy and primary then
		-- Collision freeze (spec: Clash moments): another hero's heavy hit lands here at the same moment
		local other =
			ClashRules.note(C.clash, clashes, { hero = hero.id, x = e.x, y = e.y, z = e.z, t = os.clock() })
		if other then
			local mid = (Vector3.new(e.x, e.y, e.z) + Vector3.new(other.x, other.y, other.z)) / 2
			local c = record(hero, r.n, r.s, K.CLASH, mid, Vector3.new(0, 1, 0))
			c.c, c.r, c.p = mid, C.clash.radius, other.hero
		end
	end
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
	local list = CastPlan.area(center.X, center.Y, center.Z, radius, cands(hero), los)
	for _, c in list do
		applyHit(hero, eff, r, c, coeff, true, center, nil, noStatus)
	end
	return #list
end

-- A perk burst around a point (Quakeheel, Echo Trail), drawn like an area hit of the hero's basic.
-- quiet: no result record (the trail ticks too often to draw each one)
function CombatService.burst(hero: any, center: Vector3, radius: number, coeff: number, quiet: boolean?)
	local basic = A.list[hero.loadout.basic or "ZapBolt"]
	local eff = { set = basic.set, perk = true }
	local r = record(hero, basic.num, 0, K.END, center, Vector3.new(0, -1, 0))
	r.c, r.r = center, radius
	hitArea(hero, eff, r, center, radius, coeff, true)
	if quiet and #r.h == 0 then
		table.remove(pending, table.find(pending, r) :: number)
	end
end

-- A Mystic's heals and shields on allies are stronger (Classes.Mystic.supportBonus)
supportMult = function(hero: any): number
	return 1 + (Config.Classes[hero.classId].supportBonus or 0)
end

-- Heroes a support effect from `giver` reaches: in range, and allowed (FlagService.canSupport)
local function heroesNear(pos: Vector3, radius: number, giver: any): { any }
	local out = {}
	for _, h in HeroService.all() do
		local p = h.alive and HeroService.position(h)
		if p and (p - pos).Magnitude <= radius and FlagService.canSupport(giver, h) then
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

-- Frost in the water: a floating ice raft at the surface over where the cast lands (one per hero at a time)
local raftUntil: { [number]: number } = {}
local function iceRaft(hero: any, at: Vector3)
	local now = os.clock()
	local f = Config.Deep.reactions.frostPlatform
	if (raftUntil[hero.id] or 0) > now then
		return
	end
	raftUntil[hero.id] = now + f.life
	local y = Config.World.coast.waterY + 0.4
	icePart(Vector3.new(f.size, 1.2, f.size), CFrame.new(at.X, y, at.Z), f.life, true)
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
		for _, h in heroesNear(pos, eff.radius or 20, hero) do
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
	-- second buffs (Spirit Focus, Grow, Siege Mode...), forms, Deadeye, parry riposte
	if eff.extra then
		for _, h in targets do
			for _, x in eff.extra do
				HeroService.buff(h, x[1], x[2], eff.duration)
			end
		end
	end
	if eff.zeroG then
		HeroService.buff(hero, "zeroG", 1, eff.duration) -- Weightless: gravity lets go, the hero can fly
	end
	if eff.reflect then
		HeroService.buff(hero, "reflect", eff.reflect, eff.duration) -- Thorns
	end
	if eff.form then
		HeroService.setForm(hero, eff.form, eff.scale or 1, eff.duration)
	end
	if eff.critHits then
		hero.critHits = eff.critHits
		hero.critUntil = os.clock() + eff.duration
	end
	if eff.buff == "parry" then
		hero.parryId = eff.id
	end
	if eff.revive and CombatService.reviveHook then
		CombatService.reviveHook(hero, pos, eff.radius or 20)
	end
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
	if eff.weapon then
		CombatService.WeaponHits:Fire(hero, eff.weapon, count) -- Mastery (WeaponService)
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
		local list
		if plan.cx then
			local c = Vector3.new(plan.cx, plan.cy, plan.cz)
			r.c, r.r = c, plan.radius
			list = CastPlan.area(c.X, c.Y, c.Z, plan.radius, cands(hero), los)
		else
			local e = Vector3.new(plan.ex or origin.X, plan.ey or origin.Y, plan.ez or origin.Z)
			r.e = e
			list = HitQuery.capsule(origin.X, origin.Y, origin.Z, e.X, e.Y, e.Z, eff.width or 6, cands(hero))
		end
		for _, c in list do
			applyHit(hero, eff, r, c, eff.coeff * eff.echo, true, origin, nil)
		end
	end)
end

-- Travel powers (nate 2026-11-16): the hero rides for `duration` at up to `speed` (the owner's MoveController
-- drives the ride, MoveGuard allows the speed); others see the Ride attribute. A `trail` coeff hurts what the
-- ride passes.
local function startRide(hero: any, eff: any, num: number, r: any)
	local dur = eff.duration or 4
	HeroService.buff(hero, "ride", eff.speed or 80, dur)
	MoveGuard.grant(hero, (eff.speed or 80) * 0.4) -- the owner started riding before this arrived
	local player = hero.player
	if player then
		player:SetAttribute("Ride", eff.ride or "surf")
		local token = os.clock()
		hero.rideToken = token
		after(dur, function()
			if hero.rideToken == token and hero.player then
				hero.player:SetAttribute("Ride", nil)
			end
		end)
	end
	if (eff.trail or 0) > 0 then
		local pos = HeroService.position(hero)
		if pos then
			addField(hero, eff, num, pos, true, dur, {
				coeff = eff.trail,
				radius = eff.trailRadius or 8,
				tick = eff.tick or 0.5,
				status = eff.trailStatus or false,
			})
		end
	end
	r.dur = dur
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
	if eff.slot == "basic" and eff.shape == "bolt" and hero.classId == "Elemental" and not eff.weapon then
		rangeBonus = math.max(0, Config.Classes.Elemental.basicRange - eff.range)
	end
	local comboStep = 1
	if eff.hits then
		comboStep = AbilityRules.comboStep(hero.combo.at, hero.combo.step, now, #eff.hits)
		hero.combo.at, hero.combo.step = now, comboStep
	end
	local plan =
		CastPlan.build(eff, origin.X, origin.Y, origin.Z, dir.X, dir.Y, dir.Z, hint, cands(hero), world, {
			comboStep = comboStep,
			rangeBonus = rangeBonus,
			aimSlack = C.aimSlack,
			reach = C.reachSlack,
		})
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

	if eff.iceRaft then
		iceRaft(hero, if plan.cx then Vector3.new(plan.cx, plan.cy, plan.cz) else origin)
	end
	local knockDir = if plan.shape == "dash" then flatDir(dir) else nil
	local from = if plan.shape == "nova" and plan.cx then Vector3.new(plan.cx, plan.cy, plan.cz) else origin
	for _, h in plan.hits do
		applyHit(hero, eff, r, h.c, h.coeff, h.primary, from, knockDir)
	end
	gainFor(hero, eff, #plan.hits)
	-- structure damage where it lands (leaps and throws land later, below)
	if STRUCT_SHAPES[plan.shape] and structOf(eff) > 0 then
		local at = if plan.cx
			then Vector3.new(plan.cx, plan.cy, plan.cz)
			elseif plan.ex then Vector3.new(plan.ex, plan.ey, plan.ez)
			else origin + dir * math.min(eff.range or 20, 60)
		structural(eff, at, plan.radius or eff.radius or 12, if plan.shape == "nova" then 1 else 2)
	end
	-- Epic set 4-piece changes on novas: Rimeguard ally shields, Ironclad shockwave field
	if plan.shape == "nova" then
		if eff.allyShield then
			for _, h in heroesNear(from, eff.radius or 14, hero) do
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
				for _, h in heroesNear(at, eff.allyRadius or 12, hero) do
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
		if plan.thrown and plan.thrown > PVP_BASE then
			plan.thrown = nil -- players are never carried by a throw
		end
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
	if plan.ride then
		startRide(hero, eff, num, r)
	end
	if plan.shape == "launch" and plan.ex then
		MoveGuard.grant(hero, (Vector3.new(plan.ex, plan.ey, plan.ez) - origin).Magnitude + 30)
		r.dur = eff.time or 0.5
	end
	if eff.through and plan.ex then
		-- Unstoppable: the buildings along the path take the hit too
		local to = Vector3.new(plan.ex, plan.ey, plan.ez)
		for k = 1, 3 do
			structural(eff, origin:Lerp(to, k / 3), 10, 2)
		end
	end
	local first = plan.hits[1] and plan.hits[1].c
	if eff.delay and first then
		-- Flashpoint, Night Mark: the marked robot bursts `delay` s later, hitting what stands around it
		local id = first.id
		after(eff.delay, function()
			local c = candOf(id)
			if not c or not hero.alive then
				return
			end
			local at = Vector3.new(c.x, c.y, c.z)
			local radius = eff.delayRadius or 10
			local r2 = record(hero, num, seq, K.END, at, dir)
			r2.c, r2.r = at, radius
			local burstEff =
				{ set = eff.set, status = eff.delayStatus, statusDur = eff.delayStatusDur, slow = eff.slow }
			gainFor(hero, eff, hitArea(hero, burstEff, r2, at, radius, eff.delayCoeff or 1))
		end)
	end
	if eff.hfDur and first then
		-- Override, Soul Chains: an area that ticks around the robot that was hit and follows it; the robot
		-- itself is left out (it is the one fighting for you)
		local at = Vector3.new(first.x, first.y, first.z)
		local radius = eff.hfRadius or 10
		addField(hero, eff, num, at, false, eff.hfDur, {
			coeff = eff.hfCoeff or 0,
			radius = radius,
			tick = eff.hfTick or 0.5,
			status = eff.hfStatus or false,
			followId = first.id,
			exclude = first.id,
		})
		r.c, r.r, r.dur, r.x = at, radius, eff.hfDur, first.id
	end
	if eff.link and #plan.hits > 1 then
		local ids = {}
		for _, h in plan.hits do
			if h.c.id < PVP_BASE then
				table.insert(ids, h.c.id)
			end
		end
		local g = { ids = ids, untilT = os.clock() + eff.link, share = eff.share or 0.4, hero = hero }
		for _, id in ids do
			links[id] = g
		end
		r.dur = eff.link
	end
	if eff.decoy then
		-- Holo Decoy, Tide Mirror, Spirit Swap: a fake hero the robots around chase
		local at = if plan.cx
			then Vector3.new(plan.cx, plan.cy, plan.cz)
			elseif eff.decoyAt == "origin" then origin
			elseif plan.ex then Vector3.new(plan.ex, plan.ey, plan.ez)
			else origin + dir * 10
		local id = HeroService.addDecoy(at, eff.decoy)
		for _, c in CastPlan.area(at.X, at.Y, at.Z, eff.decoyRadius or 40, EnemyService.candidates(), nil) do
			EnemyService.applyStatus(c.id, "taunt", eff.decoy, { src = id })
		end
		r.c, r.dur = at, eff.decoy
	end
	if eff.dropCoeff then
		-- Grenade Roll, Holo Decoy's blast, Spirit Swap: a burst `dropDelay` s later where the cast landed
		-- (or where the hero stood)
		local at = if plan.cx then Vector3.new(plan.cx, plan.cy, plan.cz) else origin
		local radius = eff.dropRadius or 10
		after(eff.dropDelay or 1, function()
			if not hero.alive then
				return
			end
			local r2 = record(hero, num, seq, K.END, at, dir)
			r2.c, r2.r = at, radius
			gainFor(hero, eff, hitArea(hero, { set = eff.set }, r2, at, radius, eff.dropCoeff))
			structural(eff, at, radius, 2)
		end)
	end
	if eff.followUp and first then
		-- Sky Cut: a second strike on the same robots while they are still in the air
		local ids = {}
		for _, h in plan.hits do
			table.insert(ids, h.c.id)
		end
		after(0.45, function()
			if not hero.alive then
				return
			end
			local r2 = record(hero, num, seq, K.END, origin, dir)
			local n = 0
			for _, id in ids do
				local c = candOf(id)
				if c and applyHit(hero, eff, r2, c, eff.coeff * eff.followUp, true, origin, nil, true) then
					n += 1
				end
			end
			gainFor(hero, eff, n)
		end)
	end
	if eff.endCoeff and first and not plan.field and not eff.channel then
		-- Drop (Float), Pop (Bubble Prison): the held robots take a hit when the hold ends
		local ids = {}
		for _, h in plan.hits do
			table.insert(ids, h.c.id)
		end
		after(eff.statusDur or 1, function()
			if not hero.alive then
				return
			end
			local r2 = record(hero, num, seq, K.END, origin, dir)
			for _, id in ids do
				local c = candOf(id)
				if c then
					applyHit(hero, eff, r2, c, eff.endCoeff, true, origin, nil, true)
				end
			end
		end)
	end
	if eff.revive and not plan.buff and CombatService.reviveHook then
		CombatService.reviveHook(hero, origin, eff.radius or 20) -- Dawnburst
	end
	if eff.selfShield then
		HeroService.buff(hero, "shield", math.floor(hero.maxHealth * eff.selfShield + 0.5), 4)
	end
	if eff.selfBuff then
		-- a travel or attack that also buffs the hero (Smoke Bomb hides, Shrink Dodge, Shadow Step)
		HeroService.buff(hero, eff.selfBuff, eff.selfValue or 1, eff.selfDur or 2)
	end
	if eff.slot == "super" then
		comboCheck(hero, eff, origin, num, seq)
	end
	return true
end

-- Elements react in the water (Config.Deep.reactions; the approved class doc): Storm chains jump farther,
-- Fire bursts into blinding steam that pushes, Frost freezes an ice raft at the surface, Earth stirs a silt
-- cloud that hides the hero, and Tide is stronger and faster. `eff` is this use's own copy.
local function wetReaction(hero: any, eff: any)
	local rx = Config.Deep.reactions
	local set = eff.set
	eff.wet = true
	if set == "Volt" then
		eff.jump = (eff.jump or 18) * rx.stormJump
	elseif set == "Fire" then
		if not eff.status then
			eff.status, eff.statusDur = "blind", rx.fireBlind
		end
		if not eff.status2 then
			eff.status2, eff.status2Dur = "knockback", 1
			eff.knock = math.max(eff.knock or 0, rx.fireKnock)
		end
	elseif set == "Frost" then
		eff.iceRaft = eff.slot ~= "basic"
	elseif set == "Earth" and eff.slot ~= "basic" then
		HeroService.buff(hero, "hidden", 1, rx.earthHide)
	elseif set == "Tide" then
		eff.coeff *= rx.tideDamage
		eff.cd *= rx.tideCooldown
	end
end

-- Shared by players (CombatUse) and load bots. Returns true when the use was accepted.
function CombatService.use(
	hero: any,
	num: number,
	aim: Vector3,
	hint: number,
	seq: number,
	latency: number,
	charge: number?
): boolean
	local row = A.byNum[num]
	if not row or not hero.alive or HeroService.disabled(hero) or BlockService.blocking(hero) then
		return false -- H1: no casting while blocking
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
	-- hold to charge: capped by the hold the server timed from the key press (CombatCharge)
	local pressed = hero.chargeAt and hero.chargeAt[num]
	if hero.chargeAt then
		hero.chargeAt[num] = nil
	end
	if ChargeRules.chargeable(row) then
		ChargeRules.apply(C, eff, ChargeRules.allowed(C, charge, pressed, now, latency))
	end
	local awake = HeroService.awakened(hero)
	if slot == "super" and awake then
		local aw = A.awakening
		eff.coeff *= 1 + aw.superCoeff
		if eff.radius then
			eff.radius *= 1.15
		end
		eff.awakenedSuper = true
	end
	if DeepLayout.underwater(Config, root.X, root.Y, root.Z) then
		wetReaction(hero, eff)
	end
	local full = AbilityRules.cooldown(Config, Formulas, eff, {
		classId = hero.classId,
		focus = hero.stats.Focus * (if FlagService.flagged(hero) then Config.Pvp.minorScale else 1),
		attackSpeed = Status.value(hero.status, "attackSpeed", now, 0),
		awakened = awake,
	})
	Cooldowns.start(hero.cooldowns, row.id, now, AbilityRules.afterUse(hero.recast, row.id, eff, now, full))
	hero.channel = nil -- any new use ends a channel
	hero.lastCast = now
	FlagService.attacked(hero) -- attacking ends spawn protection
	if hero.player and math.random() < Config.Analytics.castSample then
		Analytics.event(hero.player, "skill_cast", 1, { row.id, slot })
		Analytics.step(hero.player, "Combat", "skill_cast")
	end
	local origin = root + CHEST
	if eff.cast and eff.cast > 0 then
		-- windup: others see it coming; the hit lands from where the hero is when it finishes
		local r = record(hero, num, seq, K.WINDUP, origin, dir)
		r.dur = eff.cast
		-- H1: a heavy wind-up can be interrupted (BlockService.interruptHero cancels it)
		local w = if GuardMath.heavyWindup(Config.Guard, eff)
			then { num = num, id = row.id, untilT = now + eff.cast, full = full, cancelled = false }
			else nil
		hero.windup = w
		after(eff.cast, function()
			if w then
				if hero.windup == w then
					hero.windup = nil
				end
				if w.cancelled then
					return
				end
			end
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
	local row = A.list[hero.parryId or "ParryStance"] or A.list.ParryStance
	local eff = HeroService.effective(hero, row.id)
	local pos = HeroService.position(hero)
	local c = if source.enemy
		then candOf(source.enemy)
		elseif source.pvp and source.pvp.pvpSlot > 0 then candOf(PVP_BASE + source.pvp.pvpSlot)
		else nil
	if not pos or not c then
		return
	end
	local target = Vector3.new(c.x, c.y, c.z)
	local r = record(hero, row.num, 0, K.RIPOSTE, pos + CHEST, (target - pos).Unit)
	r.e = target
	if (target - pos).Magnitude <= 45 then
		applyHit(hero, eff, r, c, eff.coeff, true, pos)
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
				local c = candOf(id)
				if c and (Vector3.new(c.x, c.y, c.z) - origin).Magnitude <= reach then
					table.insert(live, id)
					applyHit(hero, eff, r, c, eff.coeff, true, origin)
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
						local c = candOf(id)
						if c then
							applyHit(hero, eff, r2, c, eff.endCoeff or 0, true, origin, nil, true)
							if eff.endStatus then
								applyStatus(
									hero,
									eff,
									eff.endStatus,
									eff.endStatusDur or 1,
									id,
									Vector3.new(c.x, c.y, c.z),
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
		if f.followId then
			local c = candOf(f.followId)
			if c then
				f.pos = Vector3.new(c.x, c.y, c.z)
			else
				f.untilT = now -- the robot is gone: the field ends with it
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
			local inside = if f.coeff > 0 or fieldEff.status
				then CastPlan.area(f.pos.X, f.pos.Y, f.pos.Z, f.radius, cands(hero), nil)
				else {}
			if f.exclude then
				for k = #inside, 1, -1 do
					if inside[k].id == f.exclude then
						table.remove(inside, k)
					end
				end
			end
			if eff.single and #inside > 1 then
				-- a summon (turret, guardian, drone, clones) strikes the nearest robot each tick
				local best, bestD = inside[1], math.huge
				for _, c in inside do
					local d = (Vector3.new(c.x, c.y, c.z) - f.pos).Magnitude
					if d < bestD then
						best, bestD = c, d
					end
				end
				inside = { best }
			end
			for _, c in inside do
				applyHit(hero, fieldEff, r, c, f.coeff, true, f.pos, nil)
			end
			if eff.allyHeal then
				-- Healing Rain, Ward Totem, Fix-It Drone: heroes inside heal a part of their health each tick
				for _, h in heroesNear(f.pos, f.radius, hero) do
					local amount = h.maxHealth * eff.allyHeal * (if h ~= hero then supportMult(hero) else 1)
					HeroService.heal(h, amount)
					if h ~= hero then
						HeroService.Supported:Fire(hero, amount)
					end
				end
			end
			if eff.tickStruct then
				-- Siege Mode: every tick hits the buildings in the area
				structural({ structDmg = eff.tickStruct }, f.pos, f.radius, 1)
			end
			if eff.allyBuff then
				-- Sandstorm hides heroes inside, Sanctuary makes them untouchable
				for _, h in heroesNear(f.pos, f.radius, hero) do
					HeroService.buff(h, eff.allyBuff, eff.allyBuffValue or 1, f.tick + 0.3)
				end
			end
			if eff.allyResist then
				-- Blizzard Dome: allies inside resist 15%
				for _, h in heroesNear(f.pos, f.radius, hero) do
					HeroService.buff(h, "resist", eff.allyResist, f.tick + 0.3)
				end
			end
		end
		if now >= f.untilT then
			table.remove(fields, i)
			if eff.endCoeff or eff.endStatus then
				local r = record(hero, f.num, 0, K.END, f.pos, Vector3.new(0, 1, 0))
				r.c, r.r = f.pos, f.radius
				for _, c in CastPlan.area(f.pos.X, f.pos.Y, f.pos.Z, f.radius, cands(hero), nil) do
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

-- Super-speed from level 12: running flat out leaves a trail that hurts the robots it passes
local trailAt = 0
local function stepTrails(now: number)
	if now < trailAt then
		return
	end
	trailAt = now + 0.5
	local m = Config.Move.mobility.speed
	for _, hero in HeroService.all() do
		if
			hero.alive
			and hero.player
			and hero.mobility == "speed"
			and hero.level >= m.up.trailLevel
			and MoveGuard.speed(hero) >= m.up.trailSpeed
		then
			local pos = HeroService.position(hero)
			if pos then
				CombatService.burst(hero, pos, m.up.trailRadius, m.up.trailCoeff, true)
			end
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
	Net.on(
		"CombatUse",
		function(player, num: number, aim: Vector3, hint: number, seq: number, charge: number?)
			local hero = HeroService.get(player)
			if not hero then
				return
			end
			local t0 = os.clock()
			CombatService.use(hero, num, aim, hint, seq, player:GetNetworkPing(), charge)
			PerfMonitor.add("combat", (os.clock() - t0) * 1000)
		end
	)
	-- hold to charge: the server times the hold from the press
	Net.on("CombatCharge", function(player, num: number)
		local hero = HeroService.get(player)
		local row = A.byNum[num]
		if hero and row and ChargeRules.chargeable(row) and slotOf(hero, row.id) then
			hero.chargeAt = hero.chargeAt or {}
			hero.chargeAt[num] = os.clock()
		end
	end)
	-- Leaping (nate 2026-11-16): the ground pound lands as a burst; the server checks the mobility, the
	-- cooldown and that the hero really fell (MoveGuard.dropped)
	local poundAt: { [number]: number } = {}
	Net.on("MovePound", function(player)
		local hero = HeroService.get(player)
		local m = Config.Move.mobility.leap
		if not hero or not hero.alive or hero.mobility ~= "leap" then
			return
		end
		local now = os.clock()
		if now < (poundAt[hero.id] or 0) then
			return
		end
		if MoveGuard.dropped(hero, 1.5) < m.pound.minFall then
			return
		end
		local pos = HeroService.position(hero)
		if pos then
			poundAt[hero.id] = now + m.pound.cooldown
			local radius = if hero.level >= m.up.poundLevel then m.up.poundRadius else m.pound.radius
			CombatService.burst(hero, pos - Vector3.new(0, 2, 0), radius, m.pound.coeff)
		end
	end)
	Net.on("CombatCancel", function(player, seq: number)
		local hero = HeroService.get(player)
		if hero and hero.channel and hero.channel.seq == seq then
			hero.channel = nil
		end
	end)
	HeroService.Parried:Connect(riposte)
	HeroService.Reflected:Connect(function(hero: any, enemyId: number, amount: number)
		local pos = HeroService.position(hero)
		if pos and EnemyService.alive(enemyId) then
			EnemyService.damage(enemyId, amount, hero.id, pos)
		end
	end)
	HeroService.Defeated:Connect(function(hero)
		hero.channel = nil
	end)
	PerfMonitor.watch("fields", function()
		return #fields
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("CombatService", function(dt)
		local t0 = os.clock()
		stepTimers(t0)
		stepChannels(t0)
		stepFields(t0)
		stepTrails(t0)
		PerfMonitor.add("combat", (os.clock() - t0) * 1000)
		acc += dt
		if acc >= 1 / C.resultRate then
			acc = 0
			local t1 = os.clock()
			flush()
			PerfMonitor.add("replication", (os.clock() - t1) * 1000)
		end
	end))
end

return CombatService
