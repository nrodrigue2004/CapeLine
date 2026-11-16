-- IncidentService: the incident spawner (spec: Schedulers "Every hero keeps 2 incidents within 300 studs. A
-- new one appears within 10 s of one clearing. Max 90 active per server"; Incidents table; Incident.Spawn,
-- Incident.Update). IncidentPlan picks and tracks; IncidentSpots finds the place; SiteKit builds it.
-- * Each player's hero keeps 2 incidents of their side near them. Anyone may help with any incident; the
--   heroes who helped (beat its robots, hit its object, carried a citizen, stood in its ring) share the
--   reward when it clears: Credits and Renown at its zone level and a 12% gear roll (Drops "Incident
--   clear"). Each rescue also pays the carrier (Earn "Rescue").
-- * Out of time: it fails with no reward (the sign falls, the tram rolls off the end of the line, the
--   runner gets away); nobody near it for 45 s, or its hero flew 600 studs off: it quietly goes.
-- * Raid prep incidents run while a world boss counts down; each clear weakens the boss (Cleared signal).
-- * Players within 450 studs get Incident.Spawn once and Incident.Update at 2 Hz until it ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local ZoneLevel = require(Shared:WaitForChild("ZoneLevel"))
local WorldClock = require(Shared:WaitForChild("WorldClock"))
local EventPlan = require(Shared:WaitForChild("EventPlan"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local DataService = require(script.Parent.DataService)
local CitizenService = require(script.Parent.CitizenService)
local PerfMonitor = require(script.Parent.PerfMonitor)
local SiteKit = require(script.Parent.SiteKit)

local IncidentService = {}

local IC = Config.Incidents
local S = IC.spawner
IncidentService.Cleared = Signal.new() -- (incident) an incident was cleared (Raid prep weakens the boss)
IncidentService.Rescued = Signal.new() -- (hero) a citizen reached safety (the boss counts it as support)
IncidentService.prep = false -- a world boss is counting down: Raid prep incidents
IncidentService.clockStart = 0 -- the world clock's cycle start (ClockService sets it)
-- M10 squads set this: (helpers, position) adds squadmates near a cleared incident to its helpers
IncidentService.share = nil :: (({ [number]: boolean }, Vector3) -> ())?

export type Live = {
	id: number,
	owner: number, -- hero id
	side: string,
	plan: IncidentPlan.Incident,
	pos: Vector3,
	spot: IncidentSpots.Spot,
	things: { any }, -- what SiteKit built (cleared at the end)
	enemies: { [number]: boolean },
	helpers: { [number]: boolean },
	known: { [Player]: boolean },
	lastNear: number,
	stepStarted: number,
	ring: Model?,
	object: any?,
	runner: { id: number, idx: number, t: number }?,
	sign: Model?,
	ended: number?,
	medal: string?,
	builtStep: number,
}

local live: { [number]: Live } = {}
local byEnemy: { [number]: number } = {} -- robot id -> incident id
local meta: { [number]: { next: number, last: string? } } = {}
local nextId = 0
local rng = Rng.new(Rng.hash(os.time(), 31))

local MEDAL = { gold = 1, silver = 2, bronze = 3 }
local STATE = { active = 0, done = 1, failed = 2, gone = 3 }

local function count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

local function ownedBy(heroId: number): number
	local n = 0
	for _, inc in live do
		if inc.owner == heroId and not inc.ended then
			n += 1
		end
	end
	return n
end

local function tooClose(x: number, z: number): boolean
	for _, inc in live do
		if (inc.pos.X - x) ^ 2 + (inc.pos.Z - z) ^ 2 < 70 * 70 then
			return true
		end
	end
	return false
end

local function night(): boolean
	return WorldClock.isNight(Config.World.clock, os.time() - IncidentService.clockStart)
end

---------------------------------------------------------------------------
-- Building each step
---------------------------------------------------------------------------

local function fireProps(inc: Live, at: Vector3)
	local m = SiteKit.model("Blaze")
	local p = SiteKit.part(
		m,
		Vector3.new(3, 1, 3),
		CFrame.new(at - Vector3.new(0, 1.5, 0)),
		Color3.fromRGB(80, 70, 66)
	)
	p.Transparency = 1
	local fire = Instance.new("Fire")
	fire.Size = 9
	fire.Heat = 12
	fire.Parent = p
	local smoke = Instance.new("Smoke")
	smoke.Size = 6
	smoke.RiseVelocity = 6
	smoke.Opacity = 0.25
	smoke.Color = Color3.fromRGB(80, 80, 84)
	smoke.Parent = p
	table.insert(inc.things, m)
end

local function tramModel(m: Model)
	local body = Color3.fromRGB(240, 196, 60)
	SiteKit.part(m, Vector3.new(9, 6, 34), CFrame.new(0, 4, 0), body)
	SiteKit.part(
		m,
		Vector3.new(9.2, 3, 33),
		CFrame.new(0, 6.5, 0),
		Color3.fromRGB(150, 200, 230),
		Enum.Material.Glass
	)
	SiteKit.part(m, Vector3.new(6, 0.8, 30), CFrame.new(0, 10, 0), Color3.fromRGB(60, 60, 70))
	SiteKit.part(m, Vector3.new(0.4, 4, 0.4), CFrame.new(0, 12, -6), Color3.fromRGB(40, 40, 48))
end

local function relayModel(m: Model)
	SiteKit.part(m, Vector3.new(4, 2, 4), CFrame.new(0, 1, 0), Color3.fromRGB(60, 70, 90))
	SiteKit.part(
		m,
		Vector3.new(1, 18, 1),
		CFrame.new(0, 10, 0),
		Color3.fromRGB(150, 160, 175),
		Enum.Material.Metal
	)
	local dish = SiteKit.part(
		m,
		Vector3.new(0.6, 7, 7),
		CFrame.new(0, 17, 0) * CFrame.Angles(0, 0, math.rad(60)),
		Color3.fromRGB(220, 230, 240),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	dish.Name = "Dish"
	SiteKit.part(
		m,
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(0, 19.5, 0),
		Color3.fromRGB(80, 160, 255),
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
end

local function propAt(inc: Live, kind: string)
	local p = inc.pos
	local m = SiteKit.model(kind)
	if kind == "Vault" then
		SiteKit.part(
			m,
			Vector3.new(14, 12, 4),
			CFrame.new(p + Vector3.new(0, 6, 8)),
			Color3.fromRGB(110, 115, 125),
			Enum.Material.Metal
		)
		local door = SiteKit.part(
			m,
			Vector3.new(1.2, 9, 9),
			CFrame.new(p + Vector3.new(0, 6, 5.6)) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(200, 170, 80),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		door.Name = "Door"
	elseif kind == "Crate" then
		SiteKit.part(
			m,
			Vector3.new(6, 5, 6),
			CFrame.new(p + Vector3.new(0, 2.5, 0)),
			Color3.fromRGB(70, 60, 110),
			Enum.Material.Metal
		)
		SiteKit.part(
			m,
			Vector3.new(6.2, 1, 6.2),
			CFrame.new(p + Vector3.new(0, 4, 0)),
			Color3.fromRGB(150, 120, 255),
			Enum.Material.Neon
		)
	end
	table.insert(inc.things, m)
end

local function startStep(inc: Live)
	local step = IncidentPlan.current(inc.plan)
	if not step then
		return
	end
	inc.stepStarted = os.clock()
	inc.builtStep = inc.plan.step
	local level = inc.plan.level
	local row = step.def
	local tid = inc.plan.tid
	if step.kind == "defeat" then
		local ids =
			SiteKit.squad(step.spawn :: any, inc.pos, level, inc.id, if tid == "ShardCrate" then 10 else 16)
		for _, id in ids do
			inc.enemies[id] = true
			byEnemy[id] = inc.id
			table.insert(inc.things, id)
		end
		-- fewer spawned than needed (the server cap): count only what exists
		step.need = math.min(step.need, math.max(1, #ids))
		if tid == "VaultBreach" then
			propAt(inc, "Vault")
		elseif tid == "ShardCrate" then
			propAt(inc, "Crate")
		end
	elseif step.kind == "rescue" then
		local spot = inc.spot
		local points = spot.points or { { inc.pos.X, inc.pos.Y, inc.pos.Z } }
		local px, py, pz = IncidentSpots.groundNear(Config, CityBuilder.world, spot.x, spot.z, 50, rng)
		if spot.kind == "tower" then
			local b = CityBuilder.world.buildings[spot.building :: number]
			px, py, pz =
				IncidentSpots.groundNear(Config, CityBuilder.world, b.x + b.sx / 2 + 14, b.z, 40, rng)
		end
		local pad = SiteKit.pad(Vector3.new(px, py - 0.5, pz), "Rescue")
		table.insert(inc.things, pad)
		for i = 1, step.need do
			local pt = points[(i - 1) % #points + 1]
			local at = Vector3.new(pt[1], pt[2], pt[3])
			if spot.kind == "tower" then
				fireProps(inc, at + Vector3.new(0, 4, 0))
				-- a ledge to stand on
				local ledge = SiteKit.model("Balcony")
				SiteKit.part(
					ledge,
					Vector3.new(6, 0.6, 6),
					CFrame.new(at - Vector3.new(0, 0.3, 0)),
					Color3.fromRGB(150, 150, 160)
				)
				table.insert(inc.things, ledge)
			end
			local c = SiteKit.citizen(at, {
				cat = row.cat,
				pads = { pad },
				onPick = function(hero)
					inc.helpers[hero.id] = true
				end,
				onSafe = function(hero)
					inc.helpers[hero.id] = true
					if hero.player then
						EconomyService.reward(hero.player, "rescue", level)
						local profile = DataService.get(hero.player)
						if profile then
							profile.stats.rescues += 1
						end
					end
					IncidentService.Rescued:Fire(hero)
					IncidentPlan.advance(inc.plan, "rescue", 1)
				end,
			})
			table.insert(inc.things, c)
		end
		CitizenService.danger(inc.pos.X, inc.pos.Z, 60, IC.templates[tid].time)
	elseif step.kind == "hold" then
		local radius = row.radius or 10
		inc.ring = SiteKit.ring(inc.pos, radius)
		table.insert(inc.things, inc.ring)
		if tid == "FallingSign" then
			local top = (inc.spot.points :: any)[1]
			local dir = inc.spot.dir :: any
			local m = SiteKit.model("Billboard")
			local face = CFrame.lookAt(
				Vector3.new(top[1], top[2], top[3]),
				Vector3.new(top[1] + dir[1], top[2], top[3] + dir[2])
			)
			SiteKit.part(
				m,
				Vector3.new(16, 8, 0.6),
				face * CFrame.new(0, 0, -1) * CFrame.Angles(math.rad(-20), 0, 0),
				Color3.fromRGB(240, 90, 90)
			)
			SiteKit.part(
				m,
				Vector3.new(14, 6, 0.7),
				face * CFrame.new(0, 0, -1.1) * CFrame.Angles(math.rad(-20), 0, 0),
				Color3.fromRGB(255, 230, 120),
				Enum.Material.Neon
			)
			inc.sign = m
			table.insert(inc.things, m)
			CitizenService.danger(inc.pos.X, inc.pos.Z, 30, IC.templates[tid].time)
		end
	elseif step.kind == "object" then
		local hp = IncidentPlan.objectHp(Config, row.hits, level)
		local isTram = tid == "RunawayTram"
		local pos = if isTram then Vector3.new(inc.spot.x, inc.spot.y, inc.spot.z) else inc.pos
		local yaw = if isTram then math.rad(90) else 0
		inc.object = SiteKit.object(
			row.label or "Object",
			pos,
			if isTram then 5 else 8,
			if isTram then 9 else 5,
			hp,
			if isTram then tramModel else relayModel,
			function(heroId)
				if heroId then
					inc.helpers[heroId] = true
				end
			end,
			function(heroId)
				if heroId then
					inc.helpers[heroId] = true
				end
				IncidentPlan.advance(inc.plan, "object", 1)
			end
		)
		SiteKit.moveObject(inc.object, pos, yaw)
		table.insert(inc.things, inc.object)
	elseif step.kind == "runner" then
		local path = inc.spot.points :: any
		local p0 = path[1]
		local id = EnemyService.spawnAt(row.enemy, Vector3.new(p0[1], p0[2], p0[3]), level, inc.id, true)
		if id then
			inc.enemies[id] = true
			byEnemy[id] = inc.id
			table.insert(inc.things, id)
			inc.runner = { id = id, idx = 1, t = 0 }
		else
			inc.plan.failed = true
		end
	end
end

---------------------------------------------------------------------------
-- Life of an incident
---------------------------------------------------------------------------

local function spawnFor(hero: any, pos: Vector3): boolean
	local hm = meta[hero.id] or { next = 0, last = nil }
	meta[hero.id] = hm
	local world = CityBuilder.world
	local valid = IncidentSpots.kinds(Config, world, pos.X, pos.Z, S.radius)
	local tid = IncidentPlan.pick(
		IC,
		rng,
		hero.side,
		valid,
		hm.last,
		night(),
		IncidentService.prep,
		Config.World.clock.nightVillain
	)
	if not tid then
		return false
	end
	local t = IC.templates[tid]
	local spot = IncidentSpots.find(Config, world, t.where, pos.X, pos.Z, S.minDistance, S.radius, rng, {
		hops = t.steps[1].hops,
		run = (t.steps[1].moving or 7) * t.time * 0.95,
	})
	if not spot then
		return false
	end
	local at = Vector3.new(spot.x, spot.y, spot.z)
	if tooClose(at.X, at.Z) then
		return false
	end
	local level = ZoneLevel.at(Config, at.X, at.Z, hero.level, world.tiles)
	nextId += 1
	local inc: Live = {
		id = nextId,
		owner = hero.id,
		side = hero.side,
		plan = IncidentPlan.new(IC, rng, tid, level, os.clock()),
		pos = at,
		spot = spot,
		things = {},
		enemies = {},
		helpers = {},
		known = {},
		lastNear = os.clock(),
		stepStarted = os.clock(),
		builtStep = 0,
	}
	live[inc.id] = inc
	hm.last = tid
	startStep(inc)
	return true
end

local function wire(inc: Live, now: number, state: number): { number }
	local step = IncidentPlan.current(inc.plan)
	return {
		inc.id,
		math.floor(IncidentPlan.fraction(inc.plan) * 1000),
		inc.plan.step,
		if step then math.floor(step.have * 10) / 10 else 0,
		if step then step.need else 0,
		math.max(0, math.floor(inc.plan.deadline - now)),
		state,
		MEDAL[inc.medal or ""] or 0,
	}
end

local function spawnPacket(inc: Live, player: Player, now: number): { [string]: any }
	local hero = HeroService.get(player)
	return {
		id = inc.id,
		num = inc.plan.num,
		x = inc.pos.X,
		y = inc.pos.Y,
		z = inc.pos.Z,
		side = if inc.side == "villain" then 2 else 1,
		level = inc.plan.level,
		left = math.max(0, inc.plan.deadline - now),
		own = if hero and hero.id == inc.owner then 1 else 0,
		steps = #inc.plan.steps,
		kind = inc.spot.kind,
	}
end

local function finish(inc: Live, ok: boolean, now: number)
	inc.ended = now
	if ok then
		inc.medal = IncidentPlan.medal(IC, inc.plan, now)
		if IncidentService.share then
			IncidentService.share(inc.helpers, inc.pos)
		end
		for heroId in inc.helpers do
			local hero = HeroService.byId(heroId)
			if hero and hero.player then
				EconomyService.reward(hero.player, "incident", inc.plan.level)
				GearService.grant(hero.player, "incident", inc.plan.level)
				local name = IncidentPlan.title(IC, inc.plan.tid, hero.side)
				Net.fire("Toast", hero.player, { id = "incident", name = name, medal = inc.medal })
			end
		end
		IncidentService.Cleared:Fire(inc)
	else
		if inc.sign then
			-- the billboard drops into the empty street (the citizens already ran)
			for _, p in inc.sign:GetDescendants() do
				if p:IsA("BasePart") then
					TweenService
						:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							CFrame = CFrame.new(inc.pos + Vector3.new(0, 0.5, 0))
								* CFrame.Angles(math.rad(90), 0, 0),
						})
						:Play()
				end
			end
		end
		if inc.object and inc.plan.tid == "RunawayTram" then
			CitizenService.danger(inc.object.pos.X, inc.object.pos.Z, 40, 6)
		end
	end
	for id in inc.enemies do
		byEnemy[id] = nil
	end
	local owner = meta[inc.owner]
	if owner then
		owner.next = now + rng:range(S.refill[1], S.refill[2])
	end
	task.delay(if ok then 2 else 3, function()
		SiteKit.clear(inc.things)
	end)
end

local function stepIncident(inc: Live, now: number, dt: number)
	local plan = inc.plan
	if inc.ended then
		return
	end
	if plan.done then
		finish(inc, true, now)
		return
	end
	if plan.failed or IncidentPlan.expired(plan, now) then
		plan.failed = true
		finish(inc, false, now)
		return
	end
	local step = IncidentPlan.current(plan)
	if not step then
		return
	end
	-- the next step began since the last tick: build it
	if inc.builtStep ~= plan.step then
		startStep(inc)
	end
	if step.kind == "hold" then
		local radius = step.def.radius or 10
		local inRing = SiteKit.heroesIn(inc.pos, radius + 3)
		for _, h in inRing do
			inc.helpers[h.id] = true
		end
		IncidentPlan.advance(plan, "hold", IncidentPlan.holdRate(IC, #inRing) * dt)
	elseif step.kind == "object" and step.def.moving and inc.object then
		local dir = inc.spot.dir :: any
		local o = inc.object
		local start = Vector3.new(inc.spot.x, inc.spot.y, inc.spot.z)
		-- slows as it takes damage: brake it to a stop
		local speed = step.def.moving * (0.35 + 0.65 * (o.hp / o.maxHp))
		local nextPos = o.pos + Vector3.new(dir[1], 0, dir[2]) * speed * dt
		SiteKit.moveObject(o, nextPos, math.rad(90))
		if (nextPos - start).Magnitude >= dir[3] then
			plan.failed = true
		end
	elseif step.kind == "runner" and inc.runner then
		local r = inc.runner
		local path = inc.spot.points :: any
		if not EnemyService.alive(r.id) then
			return
		end
		local e = EnemyService.get(r.id)
		local a, b = path[r.idx], path[r.idx + 1]
		if not b then
			plan.failed = true -- it got away
			return
		end
		local from = Vector3.new(a[1], a[2], a[3])
		local to = Vector3.new(b[1], b[2], b[3])
		local seg = (to - from).Magnitude
		-- it waits for the chasers a little: slow while nobody is close
		local chasers = SiteKit.heroesIn(Vector3.new(e.x, e.y, e.z), 120)
		local speed = step.def.speed * (if #chasers > 0 then 1 else 0.3)
		r.t += speed * dt / math.max(seg, 1)
		if r.t >= 1 then
			r.t = 0
			r.idx += 1
		else
			local p = from:Lerp(to, r.t)
			EnemyService.place(r.id, p)
		end
	end
end

-- Robots beaten: count them for their incident
local function onKilled(_kind: string, by: number?, _pos: Vector3, enemyId: number?)
	local incId = enemyId and byEnemy[enemyId]
	local inc = incId and live[incId]
	if not inc then
		return
	end
	byEnemy[enemyId :: number] = nil
	inc.enemies[enemyId :: number] = nil
	if by then
		inc.helpers[by] = true
	end
	local step = IncidentPlan.current(inc.plan)
	if step and step.kind == "runner" then
		IncidentPlan.advance(inc.plan, "runner", 1)
	else
		IncidentPlan.advance(inc.plan, "defeat", 1)
	end
end

-- Any hit on an incident's robots marks the attacker as a helper
local function onHit(enemyId: number, heroId: number?)
	local incId = byEnemy[enemyId]
	local inc = incId and live[incId]
	if inc and heroId then
		inc.helpers[heroId] = true
	end
end

function IncidentService.list(): { [number]: Live }
	return live
end

-- Studio: start a template next to a hero
function IncidentService.force(hero: any, tid: string): boolean
	local pos = HeroService.position(hero)
	if not pos or not IC.templates[tid] then
		return false
	end
	local hm = meta[hero.id] or { next = 0, last = nil }
	meta[hero.id] = hm
	local t = IC.templates[tid]
	local spot = IncidentSpots.find(
		Config,
		CityBuilder.world,
		t.where,
		pos.X,
		pos.Z,
		30,
		300,
		rng,
		{ hops = t.steps[1].hops, run = (t.steps[1].moving or 7) * t.time * 0.95 }
	)
	if not spot then
		return false
	end
	nextId += 1
	local at = Vector3.new(spot.x, spot.y, spot.z)
	local inc: Live = {
		id = nextId,
		owner = hero.id,
		side = hero.side,
		plan = IncidentPlan.new(
			IC,
			rng,
			tid,
			ZoneLevel.at(Config, at.X, at.Z, hero.level, CityBuilder.world.tiles),
			os.clock()
		),
		pos = at,
		spot = spot,
		things = {},
		enemies = {},
		helpers = {},
		known = {},
		lastNear = os.clock(),
		stepStarted = os.clock(),
		builtStep = 0,
	}
	live[inc.id] = inc
	startStep(inc)
	return true
end

function IncidentService.clearAll()
	for _, inc in live do
		if not inc.ended then
			inc.plan.failed = true
		end
	end
end

local function tick(dt: number)
	local now = os.clock()
	local t0 = now
	local positions: { [Player]: Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local pos = hero and hero.alive and HeroService.position(hero)
		if pos then
			positions[player] = pos
		end
	end
	-- keep 2 incidents near every player's hero
	for player, pos in positions do
		local hero = HeroService.get(player)
		if
			hero
			and hero.loaded
			and not hero.traveling
			and not hero.scene
			and not EventPlan.inPocket(Config.Events, pos.Y)
		then
			local hm = meta[hero.id] or { next = now + 2, last = nil }
			meta[hero.id] = hm
			if now >= hm.next and ownedBy(hero.id) < S.perHero and count() < S.maxActive then
				if not spawnFor(hero, pos) then
					hm.next = now + 1
				else
					hm.next = now + 1.5
				end
			end
		end
	end
	for id, inc in live do
		if inc.ended then
			if now - inc.ended > 4 then
				for player in inc.known do
					if player.Parent then
						Net.fire("IncidentUpdate", player, { wire(inc, now, STATE.gone) })
					end
				end
				live[id] = nil
			end
		else
			stepIncident(inc, now, dt)
			-- nobody near, or its hero flew far away: replace it quietly
			local ownerHero = HeroService.byId(inc.owner)
			local ownerPos = ownerHero and HeroService.position(ownerHero)
			local someone = false
			for _, pos in positions do
				if (pos - inc.pos).Magnitude <= S.ownerFar then
					someone = true
					break
				end
			end
			if someone then
				inc.lastNear = now
			end
			local ownerGone = not ownerPos or (ownerPos - inc.pos).Magnitude > S.ownerFar
			if not inc.ended and (now - inc.lastNear > S.abandonAfter or (ownerGone and not someone)) then
				inc.plan.failed = true
				finish(inc, false, now)
			end
		end
	end
	PerfMonitor.add("schedulers", (os.clock() - t0) * 1000)
end

local sendClock = 0
local function send()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local pos = hero and HeroService.position(hero)
		local batch = {}
		for _, inc in live do
			local near = pos and (pos - inc.pos).Magnitude <= S.sendRadius
			if near and not inc.known[player] and not inc.ended then
				inc.known[player] = true
				Net.fire("IncidentSpawn", player, spawnPacket(inc, player, now))
			end
			if inc.known[player] then
				local state = if inc.ended
					then (if inc.plan.done then STATE.done else STATE.failed)
					else STATE.active
				if not near and not inc.ended and pos and (pos - inc.pos).Magnitude > S.sendRadius + 150 then
					inc.known[player] = nil
					state = STATE.gone
				end
				table.insert(batch, wire(inc, now, state))
			end
		end
		if #batch > 0 then
			Net.fire("IncidentUpdate", player, batch)
		end
	end
end

function IncidentService.init()
	SiteKit.safehouses = CityBuilder.world.safehouses
	EnemyService.Killed:Connect(onKilled)
	EnemyService.Hit:Connect(onHit)
	HeroService.Removed:Connect(function(hero)
		meta[hero.id] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, inc in live do
			inc.known[player] = nil
		end
	end)
	PerfMonitor.watch("incidents", count)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("IncidentService", function(dt)
		acc += dt
		sendClock += dt
		if acc >= 0.2 then
			tick(acc)
			acc = 0
		end
		if sendClock >= 1 / S.updateRate then
			sendClock = 0
			send()
		end
	end))
end

return IncidentService
