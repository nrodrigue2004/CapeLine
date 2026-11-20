-- EnemyService: runs EnemySim on the server (spec: Enemies; caps 90 per server, 6 per hero, 40 AI updates
-- per frame) and replicates it: Enemy.Delta positions at 10 Hz (unreliable, only nearby enemies per player)
-- and CombatEvents for shots, hero hits and deaths (10 Hz batches, only to players near them).
-- Robots come from incidents, contracts, events and the boss (M6); the M1 stand-in spawner stays for
-- Studio load tests. Non-robot hit targets (props, the boss) are registered here too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local EnemySim = require(Shared:WaitForChild("EnemySim"))
local EnemyBuffer = require(Shared:WaitForChild("EnemyBuffer"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local MapSites = require(Shared:WaitForChild("MapSites"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local LookCodec = require(Shared:WaitForChild("LookCodec"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local QualityRules = require(Shared:WaitForChild("QualityRules"))
local PhaseRules = require(Shared:WaitForChild("PhaseRules"))

local HeroService = require(script.Parent.HeroService)
local DataService = require(script.Parent.DataService)
local MoveGuard = require(script.Parent.MoveGuard)
local PerfMonitor = require(script.Parent.PerfMonitor)
local Analytics = require(script.Parent.Analytics)

local EnemyService = {}
EnemyService.Killed = Signal.new() -- (enemyKind, attackerHeroId, position, enemyId)
EnemyService.Hit = Signal.new() -- (id, heroId, dealt, isTarget) any hit on a robot or a registered target
EnemyService.Unmasked = Signal.new() -- (enemyKind, heroId?) a famous fake's face cracked (lore step 7: the news)
-- The M1 stand-in spawner is off since M6: incidents, contracts, events and the boss bring the robots.
-- DevService can turn it back on for load tests.
EnemyService.populate = false

-- Hit targets that are not robots (incident props, the world boss's body, weak points and objectives).
-- Combat sees them as candidates; damage goes to their hit function. Ids start at TARGET_BASE.
export type Target = {
	x: number,
	y: number,
	z: number,
	r: number,
	hit: (amount: number, heroId: number?, from: Vector3?) -> (number, boolean), -- dealt, finished
	-- a private mission run's target (PhaseService; missions lane 2026-11-20): only that phase's heroes aim at it
	-- or hurt it (nil: the open world's, as before)
	phase: number?,
}
local TARGET_BASE = 50000
EnemyService.TARGET_BASE = TARGET_BASE
local targets: { [number]: Target } = {}
local nextTarget = TARGET_BASE

local sim: EnemySim.Sim
local seq = 0
local EVENT_RANGE = 220

-- Event kinds on the wire (arrays keep the payload small)
EnemyService.SHOT, EnemyService.HERO_HIT, EnemyService.DIE = 1, 2, 3
EnemyService.WARN, EnemyService.SLAM, EnemyService.SWING, EnemyService.BLOCKED = 4, 5, 6, 7
-- the nine new robot types (see EnemySim.EXTRA for the matching wire flags)
EnemyService.AIM, EnemyService.RALLY, EnemyService.LOB, EnemyService.ZONE = 8, 9, 10, 11
EnemyService.MEND, EnemyService.REVEAL, EnemyService.BOOM = 12, 13, 14
-- the famous fakes and the evil twin (lore step 4): a dive, charge or dash; a face cracking
EnemyService.DASH, EnemyService.UNMASK = 15, 16
-- WP6: a Sneak Bot winds up its lunge (the lane to the spot it will dash to)
EnemyService.LUNGE = 17

-- Evil twins alive now and who they copy (EnemyIdentity: the look, path, name and title every device draws)
local idents: { [number]: { [string]: any } } = {}

-- The solo key for a hero (EnemySim's solo rule): the prologue's (nate's playtest 2026-11-18: a hero in the
-- prologue is alone with its own story's robots: its own id), a private mission run's (its phase's key,
-- Shared.PhaseRules; missions lane 2026-11-20), nil for everyone else
function EnemyService.soloKey(hero: any): number?
	return PhaseRules.heroKey(hero)
end

-- Each robot id's solo key, kept past its death (a dead robot's last events and shots still go only to its own
-- players) until the id is used again
local keyOf: { [number]: number? } = {}

-- Make a robot one hero's alone (the prologue's): it sees only that hero and only that hero can hurt it.
-- bounds: a room it never leaves, { x0, x1, z0, z1, yMax? } (nil: anywhere)
function EnemyService.solo(id: number, heroId: number?, bounds: { number }?)
	local e = sim.byId[id]
	if e then
		e.solo = heroId
		keyOf[id] = heroId
		e.bounds = bounds
		e.target = nil
		EnemySim.keepIn(e)
	end
end

-- Put a robot in a private mission run's phase (PhaseService; nil: back to the open world): it sees, chases, shoots
-- and hurts only that phase's heroes, only they can hurt it, and only their devices are sent it (Enemy.Delta,
-- CombatEvents). World systems never count it (their robots carry their own tags).
function EnemyService.setPhase(id: number, phase: number?)
	local e = sim.byId[id]
	if e then
		local key = PhaseRules.key(phase)
		e.solo = key
		keyOf[id] = key
		e.target = nil
	end
end

-- The phase a robot is in (nil: the open world, or the prologue's)
function EnemyService.phaseOf(id: number): number?
	local e = sim.byId[id]
	return PhaseRules.phaseOf(e and e.solo)
end

-- May this robot (or registered target) and this hero meet: see, hit, grab, taunt? (same solo key)
function EnemyService.reaches(id: number, hero: any): boolean
	local t = targets[id]
	if t then
		return PhaseRules.key(t.phase) == EnemyService.soloKey(hero)
	end
	return EnemySim.sees(sim.byId[id], { solo = EnemyService.soloKey(hero) })
end

function EnemyService.candidates(): { any }
	local list = EnemySim.candidates(sim)
	for id, t in targets do
		table.insert(
			list,
			{ id = id, x = t.x, y = t.y, z = t.z, r = t.r, flags = 0, solo = PhaseRules.key(t.phase) }
		)
	end
	return list
end

-- The candidates this hero may touch (its own solo key's: a private run's hero only its run's robots and targets,
-- an open-world hero only the open world's): gadgets, taunts and decoys use this
function EnemyService.candidatesFor(hero: any): { any }
	local list = EnemyService.candidates()
	local key = EnemyService.soloKey(hero)
	for i = #list, 1, -1 do
		if list[i].solo ~= key then
			list[i] = list[#list]
			list[#list] = nil
		end
	end
	return list
end

function EnemyService.addTarget(t: Target): number
	nextTarget += 1
	if nextTarget > 65000 then
		nextTarget = TARGET_BASE + 1
	end
	targets[nextTarget] = t
	return nextTarget
end

function EnemyService.removeTarget(id: number)
	targets[id] = nil
end

function EnemyService.target(id: number): Target?
	return targets[id]
end

-- A robot for an incident, contract or event: returns its id. tag marks whose it is; scripted ones are
-- moved by their owner (EnemyService.place) instead of thinking for themselves.
function EnemyService.spawnAt(
	kind: string,
	pos: Vector3,
	level: number,
	tag: number?,
	scripted: boolean?
): number?
	local e = EnemySim.spawn(sim, kind, pos.X, pos.Y, pos.Z, level)
	if not e then
		return nil
	end
	keyOf[e.id] = nil
	e.tag = tag
	e.scripted = scripted
	return e.id
end

-- A robot and the company it brings (a Swarmer's pack; a Captain's escort only when `escort` is true, since
-- a site's squad already gives it a squad): returns every id. A type that is switched off spawns nothing.
function EnemyService.spawnGroup(
	kind: string,
	pos: Vector3,
	level: number,
	tag: number?,
	escort: boolean?
): { number }
	local ids = {}
	local e = EnemySim.spawn(sim, kind, pos.X, pos.Y, pos.Z, level)
	if not e then
		return ids
	end
	keyOf[e.id] = nil
	e.tag = tag
	table.insert(ids, e.id)
	if e.cfg.pack or (escort and e.cfg.escort) then
		for _, o in EnemySim.company(sim, e, escort == true) do
			keyOf[o.id] = nil
			table.insert(ids, o.id)
		end
	end
	return ids
end

-- Story robots: a health multiplier (mission bosses), a damage multiplier (0 never attacks back) and a
-- set number of hits to defeat (the opening's drones: 2 and 4)
-- (untouchable: no hero can hurt, stun, knock or grab it until tuned again with untouchable false; the
-- prologue's rooftop Skylance, fix-flow 2026-11-19)
function EnemyService.tune(
	id: number,
	opts: { hpMult: number?, dmgMult: number?, hits: number?, untouchable: boolean? }
)
	local e = sim.byId[id]
	if e and e.alive then
		if opts.hpMult then
			e.maxHealth *= opts.hpMult
			e.health = e.maxHealth
		end
		e.dmgMult = opts.dmgMult
		e.hitLife = opts.hits
		e.untouchable = opts.untouchable or nil
	end
end

function EnemyService.untouchable(id: number): boolean
	local e = sim.byId[id]
	return e ~= nil and e.untouchable == true
end

local function forgetIdent(id: number)
	if idents[id] then
		idents[id] = nil
		Net.fireAll("EnemyIdentity", { id = id })
	end
end

function EnemyService.remove(id: number)
	EnemySim.remove(sim, id)
	forgetIdent(id)
end

-- An evil twin of `player` (nate's lore, build plan step 4): a fake that beat this hero wears their exact look
-- (the active character's LookCodec record) and fights with moves from their own power path; its plate reads
-- their hero name (and origin title) until its face cracks. Story missions (step 5) and a rare world event
-- (step 9) call this. Returns the robot id, or nil (the twin is switched off, the server is full, no profile).
function EnemyService.spawnTwin(player: Player, pos: Vector3, level: number, tag: number?): number?
	local profile = DataService.get(player)
	local char = profile and ProfileSchema.active(profile)
	local hero = HeroService.get(player)
	if not char then
		return nil
	end
	local path = if hero then hero.startSet else char.startSet
	local e = EnemySim.spawnTwin(sim, path, pos.X, pos.Y, pos.Z, level)
	if not e then
		return nil
	end
	keyOf[e.id] = nil
	e.tag = tag
	local name = player:GetAttribute("HeroName")
	local title = player:GetAttribute("OriginTitle")
	local ident = {
		id = e.id,
		userId = player.UserId,
		words = LookCodec.toWords(LookCodec.fromWords(char.look)), -- the exact record (v1 saves read as v2)
		path = e.path,
		name = if typeof(name) == "string" and name ~= "" then name else player.DisplayName,
		title = if typeof(title) == "string" then title else "",
	}
	idents[e.id] = ident
	Net.fireAll("EnemyIdentity", ident)
	return e.id
end

-- Dress a costumed villain in a side quest finale's own look, name and title (lore step 11, chain 6:
-- Shared.FakeRules.dress, Config.SideQuests.dress[dressId]): sent as its EnemyIdentity, like a twin's, so every
-- device (and a player who joins later) draws it that way. Returns false when the robot or the dress is unknown.
function EnemyService.dress(id: number, dressId: string): boolean
	local e = sim.byId[id]
	local cfg = e and e.cfg
	local d = FakeRules.dress(Config, dressId)
	-- (lore step 11, the Underwater chain: a dress with `robot` goes over a plain robot)
	if
		not e
		or not e.alive
		or not d
		or not (
			(cfg.fake and cfg.fake.costumed and not d.famous)
			or (d.robot and not cfg.fake)
			or (d.famous and cfg.fake and not cfg.fake.costumed and not cfg.twin)
		)
	then
		return false
	end
	d.id = id
	idents[id] = d
	Net.fireAll("EnemyIdentity", d)
	return true
end

-- Who an evil twin copies, or what a dressed finale villain wears (nil for any other robot): { userId, words,
-- path, name, title } (a dress: { words, name, title, dress, creature, body })
function EnemyService.identity(id: number): { [string]: any }?
	return idents[id]
end

function EnemyService.alive(id: number): boolean
	local e = sim.byId[id]
	return e ~= nil and e.alive
end

-- Killed but its Killed signal not fired yet (it goes at the next 10 Hz event drain): a goal waits for it
-- instead of calling the robot gone
function EnemyService.dying(id: number): boolean
	return EnemySim.dying(sim, id)
end

-- Not alive and not dying: a goal may respawn or fail this robot (EnemySim.gone)
function EnemyService.gone(id: number): boolean
	return EnemySim.gone(sim, id)
end

-- Returns killed, the enemy, damage dealt, and the hit flag (EnemySim.HIT, BLOCKED, BROKE)
function EnemyService.damage(
	id: number,
	amount: number,
	attackerId: number?,
	from: Vector3?
): (boolean, any, number, number)
	local t = targets[id]
	if t then
		-- a private run's target takes hits only from its own phase's heroes (and an open-world one never from theirs)
		local by = attackerId and HeroService.byId(attackerId)
		if by and PhaseRules.key(t.phase) ~= EnemyService.soloKey(by) then
			return false, nil, 0, EnemySim.HIT
		end
		local dealt, finished = t.hit(amount, attackerId, from)
		if dealt > 0 then
			EnemyService.Hit:Fire(id, attackerId, dealt, true)
		end
		if finished then
			targets[id] = nil
		end
		return finished, { x = t.x, y = t.y, z = t.z, kind = "Target", target = true }, dealt, EnemySim.HIT
	end
	-- the prologue's solo rule: its robots are hurt only by their own hero, and that hero hurts nothing else
	if attackerId then
		local attacker = HeroService.byId(attackerId)
		if attacker and not EnemySim.sees(sim.byId[id], { solo = EnemyService.soloKey(attacker) }) then
			return false, nil, 0, EnemySim.HIT
		end
	end
	local killed, e, dealt, flag =
		EnemySim.damage(sim, id, amount, attackerId, from and from.X, from and from.Z)
	if e and dealt > 0 and attackerId then
		EnemyService.Hit:Fire(id, attackerId, dealt, false)
	end
	return killed, e, dealt, flag
end

function EnemyService.applyStatus(id: number, kind: string, duration: number, opts: any?): number
	return EnemySim.applyStatus(sim, id, kind, duration, opts)
end

-- Lose track of a hero (Smoke Bomb): the machine drops it as a target
function EnemyService.forget(id: number, heroId: number)
	local e = sim and sim.byId[id]
	if e and e.target == heroId then
		e.target = nil
	end
end

function EnemyService.knock(id: number, dir: Vector3, distance: number): boolean
	return EnemySim.knock(sim, id, dir.X, dir.Z, distance)
end

-- Knockback by move (nate's playtest 2026-11-19; Shared.KnockRules): fly the robot along an arc; a wall on the
-- way asks EnemyService.launchWall (ImpactService) whether it breaks. src: the hero who hit it.
function EnemyService.launch(
	id: number,
	dir: Vector3,
	distance: number,
	lift: number,
	speed: number,
	src: number?
)
	return EnemySim.launch(sim, id, dir.X, dir.Z, distance, lift, speed, src)
end

-- (robot, contact, direction, the throw's distance, leaving a building it broke into, the hero's id) -> broke:
-- set by ImpactService
EnemyService.launchWall = nil :: ((any, Vector3, Vector3, number, boolean, number?) -> boolean)?

-- A hero's hold on a robot (Config.Throw.swing): heroId nil lets go
function EnemyService.hold(id: number, heroId: number?)
	EnemySim.hold(sim, id, heroId)
end

-- key: the wall's hero's solo key (EnemyService.soloKey): it stops only that key's robots' shots
function EnemyService.addBlocker(pos: Vector3, radius: number, untilT: number, key: number?)
	EnemySim.addBlocker(sim, pos.X, pos.Y, pos.Z, radius, untilT, key)
end

function EnemyService.now(): number
	return sim.now
end

-- Move an enemy to a spot (Lift and Throw landing)
function EnemyService.place(id: number, pos: Vector3)
	local e = sim.byId[id]
	if e and e.alive then
		e.x, e.z = pos.X, pos.Z
		e.y = if e.ai == "flyer"
			then pos.Y + 3
			else sim.heightAt(pos.X, pos.Z, pos.Y) + EnemySim.halfHeight(e.cfg)
		e.liftBase = nil
	end
end

-- (hero, damage taken, the robot's position, melee): set by ImpactService (a heavy punch throws the hero)
EnemyService.heroHitHook = nil :: ((any, number, Vector3, boolean) -> ())?

function EnemyService.get(id: number): any
	return sim.byId[id]
end

function EnemyService.push(id: number, offset: Vector3)
	EnemySim.push(sim, id, offset.X, offset.Y, offset.Z)
end

function EnemyService.count(): number
	return EnemySim.count(sim)
end

-- Dev: spawn n robots of a kind in a ring around a point
function EnemyService.spawnAround(pos: Vector3, n: number, kind: string?)
	local k = kind or "SparkDrone"
	for i = 1, n do
		local ang = i / n * math.pi * 2
		local x, z = pos.X + math.cos(ang) * 40, pos.Z + math.sin(ang) * 40
		local y = math.max(pos.Y + 15, sim.heightAt(x, z) + 15)
		local e = EnemySim.spawn(sim, k, x, y, z, 1)
		if e and kind then
			EnemySim.company(sim, e, true) -- the Dev panel's Swarmers come as a pack, a Captain with its escort
		end
	end
end

function EnemyService.clear()
	for i = #sim.enemies, 1, -1 do
		local e = sim.enemies[i]
		EnemySim.damage(sim, e.id, math.huge, nil)
	end
end

local function playerPositions(): { [Player]: Vector3 }
	local out = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			out[player] = root.Position
		end
	end
	return out
end

-- A blocked shot's row has no robot id: its key rides here (from the shot) until the batch is sent
local rowKey: { [any]: number } = {}

-- Each player's hero's solo key this batch (a private run's players get only their run's events)
local playerKey: { [Player]: number } = {}

local function broadcast(events: { any })
	if #events == 0 then
		return
	end
	local positions = playerPositions()
	local per: { [Player]: { any } } = {}
	local r2 = EVENT_RANGE * EVENT_RANGE
	table.clear(playerKey)
	for player in positions do
		local k = EnemyService.soloKey(HeroService.get(player))
		if k then
			playerKey[player] = k
		end
	end
	for _, ev in events do
		local ex, ey, ez = ev[3], ev[4], ev[5]
		-- whose event: its robot's key (kept past its death), a blocked shot's own (PhaseRules: strict both ways)
		local key = if ev[1] == EnemyService.BLOCKED
			then rowKey[ev]
			elseif ev[1] == EnemyService.HERO_HIT then rowKey[ev]
			else keyOf[ev[2]]
		for player, pos in positions do
			if playerKey[player] ~= key then
				continue
			end
			local include = false
			if ev[1] == EnemyService.HERO_HIT then
				include = ev[2] == player.UserId -- your own hits always; others' only nearby
				if not include and ex then
					local dx, dy, dz = ex - pos.X, ey - pos.Y, ez - pos.Z
					include = dx * dx + dy * dy + dz * dz <= r2
				end
			else
				local dx, dy, dz = ex - pos.X, ey - pos.Y, ez - pos.Z
				include = dx * dx + dy * dy + dz * dz <= r2
			end
			if include then
				local list = per[player]
				if not list then
					list = {}
					per[player] = list
				end
				table.insert(list, ev)
			end
		end
	end
	for player, list in per do
		Net.fire("CombatEvents", player, list)
	end
	table.clear(rowKey)
end

local function handleEvents()
	local out = {}
	for _, ev in EnemySim.drainEvents(sim) do
		if ev.k == "shot" then
			local row = { EnemyService.SHOT, ev.e, ev.x, ev.y, ev.z, ev.vx, ev.vy, ev.vz }
			if ev.home or ev.style then -- a torpedo: the hero it turns after and its turn rate (0 when not)
				table.insert(row, ev.home or 0)
				table.insert(row, ev.turn or 0)
			end
			if ev.style then -- 1 a sniper round, 2 a net, 3 a grappling hook
				table.insert(row, ev.style)
			end
			table.insert(out, row)
		elseif ev.k == "hit" then
			local hero = HeroService.byId(ev.hero)
			-- the prologue's solo rule: a stray shot or blast from the live world never reaches a hero in their own
			-- story scene, and the story's robots never hurt anyone else (a private run's phase too: its key is kept
			-- past the robot's death, so a dead robot's last shot still counts for its own run only)
			if hero and keyOf[ev.e] ~= EnemyService.soloKey(hero) then
				hero = nil
			end
			if hero then
				local taken = HeroService.damage(
					hero,
					ev.damage,
					{ enemy = ev.e, melee = ev.melee, breaker = ev.breaker }
				)
				local pos = HeroService.position(hero)
				local dmg = math.floor(taken + 0.5)
				if pos then
					local row = { EnemyService.HERO_HIT, ev.hero, pos.X, pos.Y, pos.Z, dmg }
					rowKey[row] = keyOf[ev.e]
					local from = sim.byId[ev.e]
					if from then
						-- where the hit came from (list-combat 2026-11-20): the hurt arrow and the sparks' spray, and
						-- 1 for a melee blow (the heavy thud)
						table.insert(row, from.x)
						table.insert(row, from.y)
						table.insert(row, from.z)
						table.insert(row, if ev.melee then 1 else 0)
					end
					table.insert(out, row)
				end
				if hero.alive and not hero.downed then
					-- a heavy punch throws the hero back, through a wall if one is in the way (ImpactService, 2026-11-19)
					local by = sim.byId[ev.e]
					if EnemyService.heroHitHook and by and ev.melee then
						EnemyService.heroHitHook(hero, taken, Vector3.new(by.x, by.y, by.z), true)
					end
					if ev.cc then
						-- the new types' crowd control (a net, a hook's hold, a shield bash): the same rules as PvP's
						-- (stuns and roots shorten on repeats, Resolve shortens them)
						HeroService.cc(hero, ev.cc, ev.ccTime or 0.5, ev.ccValue)
					end
					local pull = ev.pull
					if pull and pos and hero.player then
						-- a Grappler's hook: pulled toward it (and down to it), stopping `reel` studs short; only the
						-- flat travel is granted (the drop is a fall, free in MoveCheck)
						local mx, mz, drop, grant = EnemySim.hookPull(pull, pos.X, pos.Y, pos.Z)
						MoveGuard.grant(hero, grant)
						Net.fire(
							"HeroKnock",
							hero.player,
							{ x = mx, y = 3, z = mz, time = pull.time, drop = drop }
						)
					end
				end
			end
		elseif ev.k == "die" then
			local cfg = Config.Enemies[ev.kind]
			table.insert(
				out,
				{ EnemyService.DIE, ev.e, ev.x, ev.y, ev.z, cfg and cfg.typeId or 1, ev.by or 0 }
			)
			EnemyService.Killed:Fire(ev.kind, ev.by, Vector3.new(ev.x, ev.y, ev.z), ev.e)
			forgetIdent(ev.e)
		elseif ev.k == "warn" then
			table.insert(
				out,
				{ EnemyService.WARN, ev.e, ev.x, ev.y, ev.z, ev.r, ev.t, ev.arc or 360, ev.yaw or 0 }
			)
		elseif ev.k == "slam" then
			table.insert(out, { EnemyService.SLAM, ev.e, ev.x, ev.y, ev.z, ev.r })
		elseif ev.k == "swing" then
			local e = sim.byId[ev.e]
			if e then
				table.insert(out, { EnemyService.SWING, ev.e, e.x, e.y, e.z, if ev.back then 1 else 0 })
			end
		elseif ev.k == "blocked" then
			local row = { EnemyService.BLOCKED, 0, ev.x, ev.y, ev.z }
			rowKey[row] = ev.solo
			table.insert(out, row)
		elseif ev.k == "aim" then
			table.insert(out, { EnemyService.AIM, ev.e, ev.x, ev.y, ev.z, ev.hero, ev.t, ev.lock })
		elseif ev.k == "rally" then
			table.insert(out, { EnemyService.RALLY, ev.e, ev.x, ev.y, ev.z, ev.r })
		elseif ev.k == "lob" then
			table.insert(out, { EnemyService.LOB, ev.e, ev.x, ev.y, ev.z, ev.tx, ev.ty, ev.tz, ev.t })
		elseif ev.k == "zone" then
			table.insert(out, { EnemyService.ZONE, ev.e, ev.x, ev.y, ev.z, ev.r, ev.t })
		elseif ev.k == "mend" then
			table.insert(out, { EnemyService.MEND, ev.e, ev.x, ev.y, ev.z, ev.patient, ev.t })
		elseif ev.k == "reveal" then
			table.insert(out, { EnemyService.REVEAL, ev.e, ev.x, ev.y, ev.z })
		elseif ev.k == "boom" then
			table.insert(out, { EnemyService.BOOM, ev.e, ev.x, ev.y, ev.z, ev.r })
		elseif ev.k == "dash" then
			table.insert(out, { EnemyService.DASH, ev.e, ev.x, ev.y, ev.z, ev.tx, ev.ty, ev.tz })
		elseif ev.k == "lunge" then
			table.insert(out, { EnemyService.LUNGE, ev.e, ev.x, ev.y, ev.z, ev.tx, ev.ty, ev.tz, ev.t, ev.w })
		elseif ev.k == "unmask" then
			-- (6th: who cracked it, for the slow-mo finisher; lore step 7)
			table.insert(out, { EnemyService.UNMASK, ev.e, ev.x, ev.y, ev.z, ev.by or 0 })
			-- (a dressed fake is no news: its own name is not a news template's thing, and its suit's would be
			-- wrong; lore step 11, the character lines)
			if not (idents[ev.e] and idents[ev.e].dress) then
				EnemyService.Unmasked:Fire(ev.kind, ev.by)
			end
		end
	end
	return out
end

-- Each player gets the robots its device draws (perf pass 2026-11-18: a phone was sent the high preset's 60
-- and drew 20): by its saved Graphics setting, else its device class (QualityRules.enemiesFor); EnemyBuffer
-- never packs past the 900-byte unreliable limit
local function drawnFor(player: Player): number
	local profile = DataService.get(player)
	local chosen = profile and profile.settings and profile.settings.preset
	return QualityRules.enemiesFor(Config.Presets, Analytics.device(player), chosen, Config.Net.enemySpare)
end

local function sendDeltas()
	seq += 1
	local now = Workspace:GetServerTimeNow()
	local radius = Config.Net.enemyRelevance
	for player, pos in playerPositions() do
		-- (only the robots of this player's own key: a private run's to its party, the open world's to the rest)
		local key = EnemyService.soloKey(HeroService.get(player))
		local b =
			EnemyBuffer.encodeFor(seq, now, sim.enemies, pos.X, pos.Y, pos.Z, radius, drawnFor(player), key)
		Net.fire("EnemyDelta", player, b)
	end
end

-- Mission pockets (y 3,000) answer their own heights (MissionService sets this)
local pocketHeight: ((number, number, number) -> number?)? = nil
local POCKET_Y = Config.Story.pockets.y - 100
local WATER_Y = Config.World.coast.waterY
function EnemyService.setPocketHeight(fn: (number, number, number) -> number?)
	pocketHeight = fn
end

-- Built pockets by index: robots in one stand on its boxes, are stopped by its walls and fly under its
-- ceilings. The prologue's subway registers its layout here (nate's playtest 2026-11-18: Skylance walked
-- through the subway's walls, the city answered a flat floor there); mission runs register theirs too.
local pocketLayouts: { [number]: PocketLayout.Layout } = {}
function EnemyService.usePocket(index: number, layout: PocketLayout.Layout?)
	if layout then
		PocketLayout.heights(layout)
	end
	pocketLayouts[index] = layout
end

-- Story missions on the map (Shared.MapSites, missions lane 2026-11-20): each permanent piece's boxes kept out of
-- the city's height map (Crane Tower's ledges and deck) always, and a running site's own set pieces while it runs
-- (by pocket index): robots over them stand on the highest top at or under their feet, robots under them on the city.
type SiteHeights = { x0: number, x1: number, z0: number, z1: number, boxes: { any } }
local siteHeights: { [any]: SiteHeights } = {}
do
	local by: { [string]: SiteHeights } = {}
	for _, b in MapSites.permanent(Config).boxes do
		if (b :: any).nomap then
			local name = (b :: any).site
			local e = by[name]
				or { x0 = math.huge, x1 = -math.huge, z0 = math.huge, z1 = -math.huge, boxes = {} }
			by[name] = e
			table.insert(e.boxes, b)
			local r = math.max(b.sx, b.sz) / 2
			e.x0, e.x1 = math.min(e.x0, b.cx - r), math.max(e.x1, b.cx + r)
			e.z0, e.z1 = math.min(e.z0, b.cz - r), math.max(e.z1, b.cz + r)
		end
	end
	for name, e in by do
		siteHeights["permanent:" .. name] = e
	end
end
function EnemyService.useSite(index: number, layout: PocketLayout.Layout?)
	local L: any = layout
	if L and L.bounds and #L.boxes > 0 then
		local b = L.bounds
		siteHeights[index] = { x0 = b[1], x1 = b[2], z0 = b[3], z1 = b[4], boxes = L.boxes }
	else
		siteHeights[index] = nil
	end
end
local function siteHeight(x: number, z: number, y: number?): number?
	local best: number? = nil
	for _, e in siteHeights do
		if x >= e.x0 and x <= e.x1 and z >= e.z0 and z <= e.z1 then
			local t = MapSites.topAt(e.boxes, x, z, y)
			if t and (not best or t > best) then
				best = t
			end
		end
	end
	return best
end

local function pocketAt(x: number, z: number, y: number?): PocketLayout.Layout?
	if not y or y < POCKET_Y then
		return nil
	end
	local i = PocketLayout.at(Config, x, y, z)
	return if i then pocketLayouts[i] else nil
end
EnemyService.pocketAt = pocketAt

-- heightAt(x, z): the roof or ground height anywhere (CityBuilder.heightAt: the world and its wrecks)
function EnemyService.init(heightAt: (number, number) -> number)
	local rng = Random.new()
	sim = EnemySim.new(Config, {
		heightAt = function(x, z, y)
			local pl = pocketAt(x, z, y)
			if pl then
				return PocketLayout.heightAt(pl, x, z)
			end
			if y and y >= POCKET_Y and pocketHeight then
				local h = pocketHeight(x, z, y)
				if h then
					return h
				end
			end
			-- under the surface: the seabed, the basin, the Sunken Line or the Trench floor (Config.Deep)
			if y and y < WATER_Y - 0.5 then
				local f = DeepLayout.floorAt(Config, x, z, y)
				if f then
					return f
				end
			end
			local h = heightAt(x, z)
			local t = siteHeight(x, z, y)
			return if t and t > h then t else h
		end,
		water = function(x, y, z)
			return DeepLayout.underwater(Config, x, y, z)
		end,
		ceilingAt = function(x, z, y)
			local pl = pocketAt(x, z, y)
			return if pl then PocketLayout.ceilingAt(pl, x, z, y) else nil
		end,
		random = function()
			return rng:NextNumber()
		end,
		wallHit = function(e, x, y, z, dx, dz, distance, exit)
			local hook = EnemyService.launchWall
			if not hook then
				return false
			end
			local src = e.launch and e.launch.src
			return hook(e, Vector3.new(x, y, z), Vector3.new(dx, 0, dz), distance, exit, src)
		end,
	})
	HeroService.Removed:Connect(function(hero)
		EnemySim.forgetHero(sim, hero.id)
	end)
	-- a player who joins sees the twins already out
	Players.PlayerAdded:Connect(function(player)
		for _, ident in idents do
			Net.fire("EnemyIdentity", player, ident)
		end
	end)

	PerfMonitor.watch("enemies", function()
		return EnemySim.count(sim)
	end)
	PerfMonitor.watch("aiTicks", function()
		return sim.ticksLastStep
	end)

	local acc = 0
	local interval = 1 / Config.Enemies.tickRate
	RunService.Heartbeat:Connect(FrameProf.wrap("EnemyService", function(dt)
		local t0 = os.clock()
		local heroes = HeroService.simHeroes()
		EnemySim.step(sim, os.clock(), heroes, Config.Enemies.caps.aiTicksPerFrame)
		acc += dt
		local events
		if acc >= interval then
			acc = 0
			if EnemyService.populate then
				-- the city's ambient robots never spawn around heroes in a story scene (the opening, a pocket)
				local city = heroes
				for _, h in heroes do
					if h.scene or h.solo or h.y >= POCKET_Y then
						city = {}
						for _, h2 in heroes do
							if not h2.scene and not h2.solo and h2.y < POCKET_Y then
								table.insert(city, h2)
							end
						end
						break
					end
				end
				EnemySim.populate(sim, city, os.clock())
			end
			events = handleEvents()
		end
		PerfMonitor.add("enemies", (os.clock() - t0) * 1000)
		if events then
			local t1 = os.clock()
			broadcast(events)
			sendDeltas()
			PerfMonitor.add("replication", (os.clock() - t1) * 1000)
		end
	end))
end

return EnemyService
