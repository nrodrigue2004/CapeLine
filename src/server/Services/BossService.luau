-- BossService: the world boss (spec: Schedulers > World boss; World boss rules; Boss.State 2 Hz,
-- Boss.Contribution 1 Hz, Boss.Result). BossMath has the numbers, BossSim runs the fight; this wires them
-- to heroes, combat, buildings and rewards.
-- * Schedule: 20 to 30 minutes after the last one (a fresh server waits 10). A player who has never been in
--   a boss fight clamps the wait to 6 minutes from their join, so a new account sees one early. Raid prep
--   incidents run for the last 5 minutes (each clear takes 3% off its HP, at most 15%); a banner and siren
--   come at T minus 60 s. Rustjaw Prime and the Lumen Maw take turns.
-- * Its body parts, weak points and objectives are combat targets (EnemyService.addTarget): every power
--   and gadget that hits robots hits them, and the damage goes on the shared bar. Heroes and villains fight
--   it together.
-- * Contribution ledger per hero: damage dealt (weak points count double), support (healing and shields
--   given to allies, rescues during the fight), objectives (damage to cannons or generators plus 1,000 for
--   breaking one). BossMath turns it into tiers and rewards.
-- * Rewards: the tier's Economy row x share (late joiners and anyone below Participant who took part get
--   the 25% floor), gear rolls from the boss drop sources, a chance at the boss's cosmetic (1 in 20 shiny)
--   and the Rogues File page. A retreat after 8 minutes pays only a 25% Credits consolation.
-- * Buildings and counters (nate's playtest 2026-11-19): the walking boss gets the city's standing boxes
--   (BuildingState.boxesNear) so it smashes through buildings (BossSim smash events -> BuildingService.smash, inside
--   the collapse caps) and slides round pinned ones; tether hits yank the hero in and column swats knock it down
--   (strikeHero, shared with the War-Frame in MissionService).
-- * bosses-3 (2026-11-20): six bosses take turns (BossMath.nextInOrder). The Storm Colossus hovers by the Beacon Tower
--   (its lightning rods plus pads on the nearest roofs ride heroes up: lift events -> HeroKnock up), gusts push heroes
--   away, storm clouds and lava pools tick (tick events); the Quarry Titan's slams and rocks dig craters
--   (CraterService.blast); the Swarm Queen's formations guard it and re-form (exposed events). Boss.State carries the
--   hover height, the lowered and exposed flags and the lifts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local Rng = require(Shared:WaitForChild("Rng"))
local BossMath = require(Shared:WaitForChild("BossMath"))
local BossSim = require(Shared:WaitForChild("BossSim"))
local GearMath = require(Shared:WaitForChild("GearMath"))
local ZoneLevel = require(Shared:WaitForChild("ZoneLevel"))
local Progress = require(Shared:WaitForChild("Progress"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local WorldMap = require(Shared:WaitForChild("WorldMap"))
local BuildingState = require(Shared:WaitForChild("BuildingState"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local DataService = require(script.Parent.DataService)
local BuildingService = require(script.Parent.BuildingService)
local ImpactService = require(script.Parent.ImpactService)
local CitizenService = require(script.Parent.CitizenService)
local IncidentService = require(script.Parent.IncidentService)
local PerfMonitor = require(script.Parent.PerfMonitor)
local MoveGuard = require(script.Parent.MoveGuard)
local CraterService = require(script.Parent.CraterService)
local VehicleService = require(script.Parent.VehicleService)
local ImpactRules = require(Shared:WaitForChild("ImpactRules"))

local Bits = ProfileSchema.Bits

local BossService = {}
-- (player, bossId, tier, defeated) after a hero's boss reward is paid (M9: creator unlocks, the starter offer)
BossService.Rewarded = Signal.new() -- (player, bossId, tier, defeated, contribution, fight level)
BossService.Joined = Signal.new() -- (hero, bossId, heroes in the fight) a hero's first contribution to a fight
-- lore step 7 (the news): a boss landed in the city; a fight ended (defeated or not, the top hero's id)
BossService.Arrived = Signal.new() -- (bossId)
BossService.Ended = Signal.new() -- (bossId, defeated, topHeroId?)

local B = Config.Boss
local SCHED = B.schedule
-- Boss.State codes on the wire
local STATE = { idle = 0, banner = 1, landing = 2, fight = 3, dead = 4, retreat = 5 }
BossService.STATE = STATE

type Fight = {
	id: string,
	sim: BossSim.Sim,
	targets: { [string]: number }, -- sim target key -> EnemyService target id
	ledger: BossMath.Ledger,
	level: number,
	fighters: { [number]: boolean }, -- heroes sent Boss.Contribution
	over: boolean,
	lastBy: number?, -- lore step 7: the hero whose hit landed last (a phase's or the fight's finisher)
}

local phase = "waiting" -- waiting, fight, result
local startAt = 0 -- os.clock() of the next landing
local resultUntil = 0
local turn = 0 -- which boss is next (index into B.order)
local prepCleared = 0
local fight: Fight? = nil
local arenas: { [string]: Vector3 } = {}
local rng = Rng.new(Rng.hash(os.time(), 53))

-- Boss packets go to everyone in the city; heroes in a mission pocket get their own boss (MissionService)
local function toWorld(name: string, data: any)
	for _, player in Players:GetPlayers() do
		if not player:GetAttribute("Mission") then
			Net.fire(name, player, data)
		end
	end
end

local function nextBoss(): string
	return BossMath.nextInOrder(Config, turn)
end

local function arenaOf(bossId: string): Vector3
	return arenas[bossId] or arenas.RustjawPrime
end

-- Where each boss fights: Rustjaw Prime on the street in front of the plaza, the Maw in the Old Quarry pit,
-- the Leviathan Engine at the surface over the Trench
local function findArenas()
	local world = CityBuilder.world
	local bt = world.downtown.beacon
	local pitch = Config.City.downtown.block + Config.City.downtown.street
	local x, y, z = IncidentSpots.groundNear(Config, world, bt.x, bt.z + pitch * 0.6, 50, rng)
	arenas.RustjawPrime = Vector3.new(x, y - 0.5, z)
	for _, lm in world.landmarks do
		if lm.id == B.bosses.LumenMaw.arena then
			local cx, cz = lm.centre.x, lm.centre.z
			arenas.LumenMaw = Vector3.new(cx, WorldMap.heightAt(world, cx, cz), cz)
		end
	end
	-- the Leviathan Engine surfaces over the Trench (Config.Deep)
	local ta = Config.Deep.trench.arena
	arenas.LeviathanEngine = Vector3.new(ta.x, Config.World.coast.waterY, ta.z)
	-- bosses-3: the Storm Colossus by the Beacon Tower, the Swarm Queen at the Docks, the Quarry Titan in the quarry
	for _, id in B.order do
		local ax, ay, az = WorldMap.bossArena(Config, world, id)
		if ax and ay and az then
			arenas[id] = Vector3.new(ax, ay, az)
		end
	end
end

local function ledgerOf(f: Fight, heroId: number): { damage: number, support: number, objectives: number }
	local l = f.ledger[heroId]
	if not l then
		l = { damage = 0, support = 0, objectives = 0 }
		f.ledger[heroId] = l
		local hero = HeroService.byId(heroId)
		if hero and hero.player then
			local n = 0
			for _ in f.ledger do
				n += 1
			end
			BossService.Joined:Fire(hero, f.id, n)
		end
	end
	return l
end

-- A hero close enough to count as in the fight
local function inArena(f: Fight, hero: any): boolean
	local pos = HeroService.position(hero)
	if not pos then
		return false
	end
	local s = f.sim
	return (pos.X - s.x) ^ 2 + (pos.Z - s.z) ^ 2 <= (s.cfg.arenaRadius + 250) ^ 2
end

---------------------------------------------------------------------------
-- Starting and ending a fight
---------------------------------------------------------------------------

-- Keep a BossSim's body parts, weak points and objectives registered as combat targets. onHit(heroId,
-- bossDealt, objectiveDealt, broke) for every hit. The world boss and the War-Frame mission both use it.
function BossService.linkTargets(
	sim: BossSim.Sim,
	targets: { [string]: number },
	onHit: (number?, number, number, any) -> ()
)
	local live = {}
	for _, t in BossSim.targets(sim) do
		live[t.key] = true
		local id = targets[t.key]
		local reg = id and EnemyService.target(id)
		if reg then
			reg.x, reg.y, reg.z = t.x, t.y, t.z
		elseif not id then
			local key = t.key
			targets[key] = EnemyService.addTarget({
				x = t.x,
				y = t.y,
				z = t.z,
				r = t.r,
				hit = function(amount: number, heroId: number?)
					local bossDealt, objDealt, broke = BossSim.damage(sim, key, amount)
					onHit(heroId, bossDealt, objDealt, broke)
					return bossDealt + objDealt, broke ~= nil
				end,
			})
		end
	end
	for key, id in targets do
		if not live[key] then
			EnemyService.removeTarget(id)
			targets[key] = nil
		end
	end
end

function BossService.unlinkTargets(targets: { [string]: number })
	for _, id in targets do
		EnemyService.removeTarget(id)
	end
	table.clear(targets)
end

local function syncTargets(f: Fight)
	BossService.linkTargets(f.sim, f.targets, function(heroId, bossDealt, objDealt, broke)
		if heroId then
			f.lastBy = heroId
			local l = ledgerOf(f, heroId)
			l.damage += bossDealt
			l.objectives += objDealt + (if broke then B.contribution.objectiveBreak else 0)
			f.fighters[heroId] = true
		end
	end)
end

-- What a counter strike does to a hero it hit, past the damage: a tether yanks it in to `yank` studs from the boss (and
-- down toward it), a swat knocks it away and down. True when it did either (no ordinary throw then).
function BossService.strikeHero(hero: any, ev: any, sim: BossSim.Sim): boolean
	if not hero or not hero.player or not hero.alive or hero.downed then
		return false
	end
	local pos = HeroService.position(hero)
	if not pos or not (ev.yank or ev.drop or ev.push) then
		return false
	end
	local flat = Vector3.new(sim.x - pos.X, 0, sim.z - pos.Z)
	if ev.yank then
		local dist = flat.Magnitude - ev.yank
		if dist > 1 then
			local move = flat.Unit * dist
			MoveGuard.grant(hero, dist + 10)
			Net.fire("HeroKnock", hero.player, {
				x = move.X,
				y = 3,
				z = move.Z,
				time = 0.6,
				drop = math.min(0, sim.y + 6 - pos.Y),
			})
		end
		return true
	end
	local away = if flat.Magnitude > 0.1 then -flat.Unit else Vector3.new(1, 0, 0)
	if ev.push then
		-- bosses-3: a gust blows the hero away from the boss (fliers tumble back across the sky)
		local push = away * ev.push
		MoveGuard.grant(hero, ev.push + 10)
		Net.fire("HeroKnock", hero.player, { x = push.X, y = 6, z = push.Z, time = 0.7 })
		return true
	end
	local move = away * 24
	MoveGuard.grant(hero, 34)
	Net.fire("HeroKnock", hero.player, {
		x = move.X,
		y = 2,
		z = move.Z,
		time = 0.5,
		drop = -math.min(ev.drop, math.max(0, pos.Y - sim.y - 4)),
	})
	return true
end

local function clearTargets(f: Fight)
	BossService.unlinkTargets(f.targets)
end

local function begin()
	local bossId = nextBoss()
	turn += 1
	local at = arenaOf(bossId)
	local near, levels = 0, {}
	for _, h in HeroService.all() do
		local p = h.player and HeroService.position(h)
		if p then
			table.insert(levels, h.level)
			if (p - at).Magnitude <= B.hp.range then
				near += 1
			end
		end
	end
	local med = if #levels > 0 then ZoneLevel.median(levels) else 1
	local level = ZoneLevel.at(Config, at.X, at.Z, math.floor(med + 0.5), CityBuilder.world.tiles)
	local maxHp = BossMath.maxHp(Config, near, level, prepCleared)
	local now = os.clock()
	local sim = BossSim.new(Config, bossId, at.X, at.Y, at.Z, maxHp, level, now, rng)
	local book = BuildingService.book
	if book and sim.cfg.speed > 0 then
		sim.blocks = function(x: number, z: number, r: number)
			return BuildingState.boxesNear(book, x, z, r)
		end
	end
	if book and sim.cfg.lifts then
		BossSim.addRoofPads(sim, BuildingState.boxesNear(book, at.X, at.Z, sim.cfg.arenaRadius))
	end
	local f: Fight = {
		id = bossId,
		sim = sim,
		targets = {},
		ledger = {},
		level = level,
		fighters = {},
		over = false,
	}
	fight = f
	phase = "fight"
	IncidentService.prep = false
	prepCleared = 0
	CitizenService.danger(at.X, at.Z, f.sim.cfg.arenaRadius + 60, SCHED.lifespan + SCHED.landing)
	toWorld("BossAttack", { k = "land", num = f.sim.cfg.num, x = at.X, y = at.Y, z = at.Z, alt = sim.alt })
	BossService.Arrived:Fire(bossId)
end

local function nameOf(heroId: number): string
	local hero = HeroService.byId(heroId)
	local player = hero and hero.player
	return if player then player.DisplayName else "Hero"
end

-- Heroes still on the server (bots included): the ones who left give up their tier slot
local function stillHere(heroId: number): boolean
	return HeroService.byId(heroId) ~= nil
end

local function rewardHero(
	f: Fight,
	heroId: number,
	tier: string,
	rank: number,
	defeated: boolean,
	mvps: { string }
)
	local hero = HeroService.byId(heroId)
	local player = hero and hero.player
	local profile = player and DataService.get(player)
	if not player or not profile then
		return
	end
	local r = BossMath.reward(Config, tier, defeated)
	local credits, renown = 0, 0
	if r.share > 0 then
		credits, renown = Progress.earn(Config, r.earn, f.level, EconomyService.bonus(player))
		credits = math.floor(credits * r.share + 0.5)
		renown = if defeated then math.floor(renown * r.share + 0.5) else 0
		EconomyService.addCredits(player, credits)
		EconomyService.addRenown(player, renown)
		if r.fame then
			EconomyService.Earned:Fire(player, r.earn) -- Fame or Infamy for the tier (M8); a retreat pays none
		end
	end
	-- the week's bounty boss (list-combat): defeated, it pays again `mult - 1` times over plus Dust, once a week
	local bounty = false
	local week = CityBuilder.seed()
	if
		defeated
		and r.share > 0
		and f.id == BossMath.bounty(Config, week)
		and profile.stats.bountyWeek ~= week
	then
		profile.stats.bountyWeek = week
		local extra = B.bounty.mult - 1
		local bc, br = math.floor(credits * extra + 0.5), math.floor(renown * extra + 0.5)
		EconomyService.addCredits(player, bc)
		EconomyService.addRenown(player, br)
		EconomyService.addDust(player, B.bounty.dust)
		credits += bc
		renown += br
		bounty = true
	end
	local drops = 0
	for _, src in r.drops do
		drops += #GearService.grant(player, src, f.level)
	end
	local styleId, shiny = 0, false
	if r.style then
		local got, isShiny = BossMath.styleRoll(Config, tier, rng)
		local sid = got and GearMath.bossStyle(Config, f.id, isShiny)
		if sid then
			styleId, shiny = sid, isShiny
			Bits.set(profile.styles, sid)
			GearService.refresh(player)
		end
	end
	if r.page then
		Bits.set(profile.rogues, f.sim.cfg.rogues)
	end
	profile.stats.bossesJoined += 1
	-- M9: the best reward tier per boss (creator pieces) and MVP count (the trophy wall)
	local bi = table.find(B.order, f.id)
	local tierN = if not defeated
			or tier == "floor"
			or tier == "participant"
		then 1
		elseif tier == "contributor" then 2
		else 3
	if bi then
		profile.bosses[bi] = math.max(profile.bosses[bi] or 0, tierN)
	end
	if defeated and tier == "mvp" then
		profile.stats.mvps += 1
	end
	DataService.changed(player)
	DataService.saveSoon(player)
	Net.fire("BossResult", player, {
		defeated = defeated,
		num = f.sim.cfg.num,
		tier = tier,
		rank = rank,
		credits = credits,
		renown = renown,
		drops = drops,
		style = styleId,
		shiny = shiny,
		mvps = mvps,
		bounty = bounty or nil,
	})
	local l = f.ledger[heroId]
	local score = if l then math.floor(l.damage + l.support + l.objectives) else 0
	BossService.Rewarded:Fire(player, f.id, tier, defeated, score, f.level)
end

local function finish(f: Fight, defeated: boolean)
	if f.over then
		return
	end
	f.over = true
	clearTargets(f)
	local scores = BossMath.scores(Config, BossMath.present(f.ledger, stillHere))
	local tiers, ranked = BossMath.tiers(Config, scores)
	local mvps = {}
	for i = 1, math.min(B.contribution.mvp, #ranked) do
		table.insert(mvps, nameOf(ranked[i]))
	end
	-- one hero's reward (or a Rewarded listener) failing must not stop the others' pay or the fight's end
	for rank, heroId in ranked do
		local ok, err = pcall(rewardHero, f, heroId, tiers[heroId], rank, defeated, mvps)
		if not ok then
			warn("[BossService] reward for hero " .. tostring(heroId) .. " failed: " .. tostring(err))
		end
	end
	phase = "result"
	resultUntil = os.clock() + SCHED.resultTime
	BossService.Ended:Fire(f.id, defeated, ranked[1])
end

---------------------------------------------------------------------------
-- The fight, frame by frame
---------------------------------------------------------------------------

local function heroList(): { BossSim.Hero }
	local out = {}
	for _, h in HeroService.all() do
		local p = HeroService.position(h)
		if p then
			table.insert(out, { id = h.id, x = p.X, y = p.Y, z = p.Z, alive = h.alive and not h.traveling })
		end
	end
	return out
end

-- Strip what clients do not need (who was hit) and add the boss number
local function wireEvent(f: Fight, ev: any): any
	local out = table.clone(ev)
	out.hits = nil
	out.num = f.sim.cfg.num
	if ev.k == "phase" or ev.k == "dead" then
		out.by = f.lastBy -- lore step 7: the finishing hero (slow-mo finisher on their screen, shorter nearby)
	end
	return out
end

local function handleEvents(f: Fight)
	for _, ev in BossSim.drain(f.sim) do
		if ev.k == "strike" then
			for _, hit in ev.hits do
				local hero = HeroService.byId(hit[1])
				if hero then
					HeroService.damage(hero, hit[2], { boss = true })
					if BossService.strikeHero(hero, ev, f.sim) then
						continue
					end
					if hero.alive and not hero.downed then
						-- thrown back from the strike, through a building in the way (ImpactService, 2026-11-19)
						ImpactService.bossHit(hero, Vector3.new(ev.x, ev.y, ev.z))
					end
				end
			end
			if ev.struct then
				BuildingService.hit(
					Vector3.new(ev.x, ev.y, ev.z),
					ev.struct,
					Config.Destruction.bossStruct,
					1
				)
				VehicleService.hit(Vector3.new(ev.x, ev.y, ev.z), ev.struct) -- destroy-all: cars in the slam flip
			end
			-- destroy-all round 3: the city wrecks along the strike's own shape (a charge's or beam's line, a cone, rock
			-- falls, shots, a stomp): buildings through BuildingService (pins and caps as any hit), the street knocked
			-- loose round each spot (its impact), cars flipped
			local W = Config.Destruction.bossWreck
			if W then
				for _, w in ImpactRules.bossWreck(W, ev) do
					local at = Vector3.new(w[1], w[2], w[3])
					BuildingService.hit(at, w[4], W.dmg, 2)
					VehicleService.hit(at, w[4])
				end
			end
		end
		if ev.k == "strike" and ev.crater then
			-- bosses-3: the Quarry Titan breaks the ground (a crater at the slam, or at every rock)
			if ev.points and ev.shape == "circles" then
				for _, p in ev.points do
					CraterService.blast(
						Vector3.new(p[1], ev.y, p[2]),
						ev.crater,
						Config.Destruction.bossStruct
					)
				end
			else
				CraterService.blast(Vector3.new(ev.x, ev.y, ev.z), ev.crater, Config.Destruction.bossStruct)
			end
		end
		if ev.k == "tick" then
			-- a storm cloud or a lava pool: damage only (no knock); nothing to draw that the strike did not start
			for _, hit in ev.hits do
				local hero = HeroService.byId(hit[1])
				if hero then
					HeroService.damage(hero, hit[2], { boss = true })
				end
			end
			continue
		end
		if ev.k == "lift" then
			-- a lightning rod or roof pad: the hero rides an updraft up beside the boss (MoveGuard grants the move)
			local hero = HeroService.byId(ev.id)
			local pos = hero and hero.player and hero.alive and not hero.downed and HeroService.position(hero)
			if hero and pos then
				local flat = Vector3.new(ev.bx - pos.X, 0, ev.bz - pos.Z)
				-- in to 30 studs from its middle: its body (22 round) is in a melee hero's reach at the top
				local move = if flat.Magnitude > 34 then flat.Unit * (flat.Magnitude - 30) else Vector3.zero
				local rise = ev.to - pos.Y
				MoveGuard.grant(hero, move.Magnitude + rise + 20)
				Net.fire(
					"HeroKnock",
					hero.player,
					{ x = move.X, y = 12, z = move.Z, time = 1.1, drop = rise }
				)
			end
		end
		if ev.k == "smash" then
			-- it walked into a building: knock its pieces out where the body meets it (the diffs show the hole)
			BuildingService.smash(ev.id, Vector3.new(ev.x, ev.y, ev.z), ev.dmg, ev.r)
			continue
		end
		if ev.k == "dead" then
			finish(f, true)
		elseif ev.k == "retreat" then
			finish(f, false)
		end
		toWorld("BossAttack", wireEvent(f, ev))
	end
end

-- destroy-all round 3: the boss's footsteps knock the street round its feet as it walks (lamps, benches, trees,
-- park looks: BuildingService.street, a heavy knock) and flip the cars there, every bossWreck.stomp seconds it moved
local stomps: { [any]: { at: number, x: number, z: number } } = setmetatable({}, { __mode = "k" }) :: any
local function stomp(f: Fight, now: number)
	local W = Config.Destruction.bossWreck
	local sim = f.sim
	local stomped = stomps[f]
	if not stomped then
		stomped = { at = now, x = sim.x, z = sim.z }
		stomps[f] = stomped
	end
	if not W or now - stomped.at < W.stomp then
		return
	end
	local moved = (sim.x - stomped.x) ^ 2 + (sim.z - stomped.z) ^ 2
	stomped.at = now
	stomped.x, stomped.z = sim.x, sim.z
	if moved < 4 or moved > 400 * 400 then
		return -- standing still, or a leap's landing (its strike wrecks already)
	end
	local r = (sim.cfg.bodyR or 12) + 4
	local at = Vector3.new(sim.x, sim.y + 2, sim.z)
	BuildingService.street(at, r, true)
	VehicleService.hit(at, r)
end

local function stepFight(f: Fight, now: number)
	BossSim.step(f.sim, now, heroList())
	stomp(f, now)
	syncTargets(f)
	handleEvents(f)
end

local function statePacket(now: number): { [string]: any }
	local f = fight
	if phase == "waiting" then
		local left = startAt - now
		if left <= SCHED.banner then
			local nb = B.bosses[nextBoss()]
			local at = arenaOf(nextBoss())
			return {
				state = STATE.banner,
				num = nb.num,
				x = at.X,
				y = at.Y,
				z = at.Z,
				at = math.max(0, math.ceil(left)),
			}
		end
		return { state = STATE.idle, at = math.max(0, math.ceil(left)), prep = IncidentService.prep }
	end
	if not f then
		return { state = STATE.idle }
	end
	local s = f.sim
	local objectives = {}
	for _, ob in s.objectives do
		table.insert(objectives, if ob.alive then math.ceil(ob.hp / ob.maxHp * 100) else 0)
	end
	local code = STATE[s.state] or STATE.fight
	return {
		state = code,
		num = s.cfg.num,
		x = s.x,
		y = s.y,
		z = s.z,
		yaw = s.yaw,
		hp = math.ceil(s.hp),
		max = s.maxHp,
		phase = s.phase,
		at = math.max(0, math.ceil((if s.state == "landing" then s.fightAt else s.endsAt) - now)),
		objectives = objectives,
		level = f.level,
		-- bosses-3: how high it floats, whether it is down low or its core exposed, and the lifts that ride heroes up
		alt = if s.alt ~= 0 then s.alt else nil,
		low = if s.isLow then true else nil,
		exposed = if s.exposed then true else nil,
		lifts = BossService.liftList(s),
	}
end

-- The lifts on the wire: { x, y, z, 1 for a roof pad }
function BossService.liftList(s: BossSim.Sim): { { number } }?
	if #s.lifts == 0 then
		return nil
	end
	local out = {}
	for _, l in s.lifts do
		table.insert(
			out,
			{ math.floor(l.x), math.floor(l.y), math.floor(l.z), if l.kind == "pad" then 1 else 0 }
		)
	end
	return out
end

local function sendContribution(f: Fight)
	local scores = BossMath.scores(Config, BossMath.present(f.ledger, stillHere))
	local tiers, ranked = BossMath.tiers(Config, scores)
	local rankOf = {}
	for i, id in ranked do
		rankOf[id] = i
	end
	-- everyone in the arena hears their standing, even at 0 (so the HUD can say how to score)
	for _, h in HeroService.all() do
		if h.player and inArena(f, h) then
			f.fighters[h.id] = true
		end
	end
	for heroId in f.fighters do
		local hero = HeroService.byId(heroId)
		if hero and hero.player then
			Net.fire("BossContribution", hero.player, {
				score = math.floor((scores[heroId] or 0) * 1000),
				tier = tiers[heroId] or "",
				rank = rankOf[heroId] or 0,
				heroes = #ranked,
			})
		end
	end
end

-- "Rises in N minutes" (list-combat 2026-11-20): once per wait at each Config.Boss.schedule.alerts mark, to every
-- hero out in the city (not in a story scene); the week's bounty boss says so
local alerted: { [number]: number } = {}
local function alerts(now: number)
	local left = startAt - now
	for _, m in SCHED.alerts or {} do
		if left <= m * 60 and left > m * 60 - 20 and alerted[m] ~= startAt then
			alerted[m] = startAt
			local id = nextBoss()
			local bounty = id == BossMath.bounty(Config, CityBuilder.seed())
			for _, player in Players:GetPlayers() do
				local hero = HeroService.get(player)
				if hero and hero.loaded and not hero.scene then
					Net.fire(
						"Toast",
						player,
						{ id = "bossSoon", num = B.bosses[id].num, minutes = m, bounty = bounty }
					)
				end
			end
		end
	end
end

-- "Your friend is fighting the boss" (list-combat 2026-11-20): a hero out in the city whose Roblox friend on this
-- server is in the fight hears it once a fight (it flies there from the MAP like any boss)
local invited: { [Player]: Fight } = setmetatable({}, { __mode = "k" }) :: any
local lastInvite = 0
local function invites(f: Fight)
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		if invited[player] ~= f and hero and hero.loaded and not hero.scene and not inArena(f, hero) then
			for _, other in EconomyService.friendsHere(player) do
				local oh = HeroService.get(other)
				if oh and inArena(f, oh) then
					invited[player] = f
					Net.fire(
						"Toast",
						player,
						{ id = "friendBoss", num = f.sim.cfg.num, name = other.DisplayName }
					)
					break
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Studio: land the next boss in a few seconds (skips the wait and the banner)
function BossService.startNow()
	if phase == "waiting" then
		startAt = os.clock() + 3
	end
end

-- Studio: take the boss to 1 HP (the next hit ends it)
function BossService.weaken()
	local f = fight
	if f and not f.over then
		f.sim.hp = 1
	end
end

function BossService.status(): string
	return phase
end

-- Is this hero inside a live world boss fight? (PvP rewards there are halved, M8.) Not once it is over:
-- the result phase keeps `fight` for its timer, but PvP there pays in full (2026-11-18 fix)
function BossService.inFight(hero: any): boolean
	local f = fight
	return f ~= nil and not f.over and inArena(f, hero)
end

function BossService.init()
	findArenas()
	startAt = os.clock() + SCHED.firstAfterBoot
	-- a player who has never fought a boss: one within 6 minutes
	DataService.Loaded:Connect(function(player, profile)
		if profile.stats.bossesJoined == 0 and phase == "waiting" then
			startAt = BossMath.clampForNewPlayer(Config, startAt, os.clock())
		end
		task.delay(3, function()
			if player.Parent then
				Net.fire("BossState", player, statePacket(os.clock()))
			end
		end)
	end)
	IncidentService.Cleared:Connect(function(inc)
		if phase == "waiting" and IncidentService.prep and inc.plan.tid == "RaidPrep" then
			prepCleared += 1
		end
	end)
	IncidentService.Rescued:Connect(function(hero)
		local f = fight
		if f and not f.over and f.sim.state == "fight" and inArena(f, hero) then
			ledgerOf(f, hero.id).support += B.contribution.rescueSupport
			f.fighters[hero.id] = true
		end
	end)
	HeroService.Supported:Connect(function(hero, points)
		local f = fight
		if f and not f.over and f.sim.state == "fight" and inArena(f, hero) then
			ledgerOf(f, hero.id).support += points
			f.fighters[hero.id] = true
		end
	end)
	PerfMonitor.watch("boss", function()
		local f = fight
		return if f then STATE[f.sim.state] or 0 else 0
	end)
	local acc, sendAcc, contribAcc = 0, 0, 0
	RunService.Heartbeat:Connect(FrameProf.wrap("BossService", function(dt)
		acc += dt
		sendAcc += dt
		contribAcc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local now = os.clock()
		local t0 = now
		if phase == "waiting" then
			alerts(now)
			IncidentService.prep = startAt - now <= SCHED.prepWindow
			if now >= startAt and #Players:GetPlayers() > 0 then
				begin()
			elseif now >= startAt then
				startAt = now + 30 -- nobody here: try again soon
			end
		elseif phase == "fight" then
			local f = fight
			if f and not f.over then
				stepFight(f, now)
				if now - lastInvite >= 2 then
					lastInvite = now
					invites(f)
				end
			end
		elseif phase == "result" and now >= resultUntil then
			phase = "waiting"
			fight = nil
			startAt = now + BossMath.nextDelay(Config, rng)
			-- anyone here who has still never fought one keeps the 6-minute promise
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile and profile.stats.bossesJoined == 0 then
					startAt = BossMath.clampForNewPlayer(Config, startAt, now)
				end
			end
		end
		if sendAcc >= 0.5 then
			sendAcc = 0
			local left = startAt - now
			if phase ~= "waiting" or left <= SCHED.banner + 1 or IncidentService.prep then
				toWorld("BossState", statePacket(now))
			end
		end
		if contribAcc >= 1 / B.contribution.sendRate then
			contribAcc = 0
			local f = fight
			if f and not f.over and f.sim.state == "fight" then
				sendContribution(f)
			end
		end
		PerfMonitor.add("boss", (os.clock() - t0) * 1000)
	end))
end

return BossService
