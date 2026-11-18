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
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local LookCodec = require(Shared:WaitForChild("LookCodec"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local QualityRules = require(Shared:WaitForChild("QualityRules"))

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

function EnemyService.candidates(): { any }
	local list = EnemySim.candidates(sim)
	for id, t in targets do
		table.insert(list, { id = id, x = t.x, y = t.y, z = t.z, r = t.r, flags = 0 })
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
	e.tag = tag
	table.insert(ids, e.id)
	if e.cfg.pack or (escort and e.cfg.escort) then
		for _, o in EnemySim.company(sim, e, escort == true) do
			table.insert(ids, o.id)
		end
	end
	return ids
end

-- Story robots: a health multiplier (mission bosses), a damage multiplier (0 never attacks back) and a
-- set number of hits to defeat (the opening's drones: 2 and 4)
function EnemyService.tune(id: number, opts: { hpMult: number?, dmgMult: number?, hits: number? })
	local e = sim.byId[id]
	if e and e.alive then
		if opts.hpMult then
			e.maxHealth *= opts.hpMult
			e.health = e.maxHealth
		end
		e.dmgMult = opts.dmgMult
		e.hitLife = opts.hits
	end
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
		local dealt, finished = t.hit(amount, attackerId, from)
		if dealt > 0 then
			EnemyService.Hit:Fire(id, attackerId, dealt, true)
		end
		if finished then
			targets[id] = nil
		end
		return finished, { x = t.x, y = t.y, z = t.z, kind = "Target", target = true }, dealt, EnemySim.HIT
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

function EnemyService.addBlocker(pos: Vector3, radius: number, untilT: number)
	EnemySim.addBlocker(sim, pos.X, pos.Y, pos.Z, radius, untilT)
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

local function broadcast(events: { any })
	if #events == 0 then
		return
	end
	local positions = playerPositions()
	local per: { [Player]: { any } } = {}
	local r2 = EVENT_RANGE * EVENT_RANGE
	for _, ev in events do
		local ex, ey, ez = ev[3], ev[4], ev[5]
		for player, pos in positions do
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
			if hero then
				local taken = HeroService.damage(
					hero,
					ev.damage,
					{ enemy = ev.e, melee = ev.melee, breaker = ev.breaker }
				)
				local pos = HeroService.position(hero)
				local dmg = math.floor(taken + 0.5)
				if pos then
					table.insert(out, { EnemyService.HERO_HIT, ev.hero, pos.X, pos.Y, pos.Z, dmg })
				end
				if hero.alive and not hero.downed then
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
			table.insert(out, { EnemyService.BLOCKED, 0, ev.x, ev.y, ev.z })
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
		local b = EnemyBuffer.encodeFor(seq, now, sim.enemies, pos.X, pos.Y, pos.Z, radius, drawnFor(player))
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

-- heightAt(x, z): the roof or ground height anywhere (CityBuilder.heightAt: the world and its wrecks)
function EnemyService.init(heightAt: (number, number) -> number)
	local rng = Random.new()
	sim = EnemySim.new(Config, {
		heightAt = function(x, z, y)
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
			return heightAt(x, z)
		end,
		water = function(x, y, z)
			return DeepLayout.underwater(Config, x, y, z)
		end,
		random = function()
			return rng:NextNumber()
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
					if h.scene or h.y >= POCKET_Y then
						city = {}
						for _, h2 in heroes do
							if not h2.scene and h2.y < POCKET_Y then
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
