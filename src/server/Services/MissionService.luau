-- MissionService: Act 1 missions 2 to 6 in the sealed pockets at y 3,000 (spec: Act 1: Shardfall; Map
-- layout > Mission pockets; Mission.Enter / Mission.Leave / Mission.State 2 Hz; Boss: Null War-Frame).
-- * Mission.Enter from the Journal (anywhere out of combat): a free pocket is built from PocketLayout, the
--   hero fades in at its spawn and comes back to where they left when it ends. Solo until squads (M10);
--   the party id is reserved.
-- * One script for both routes: StoryPlan.steps gives the side's steps with the chosen branch in place.
--   Step kinds: hold (stand in rings while waves come), break (crates or the runaway train, a set number
--   of hits), chase (a Sneak Bot hops a path), reach (a point, past turrets), boss (a Null Sentinel with
--   adds), defeat (a squad in a room), choice (the Act 1 choice; replays keep the first pick) and
--   warframe (the BossSim War-Frame with the pillars as cover; a wipe respawns the hero at the pocket
--   spawn and the boss keeps its HP, so the reward is guaranteed on a retry).
-- * Rewards: every clear pays the Economy "mission" row; the first clear adds the mission's loot, Renown,
--   Skill Point, own-side reputation and the Test Her Epic crate chance.
-- * Pockets have no PvP and no world scheduler: heroes in a mission are in a scene (no incidents, events
--   or world boss packets) and robots stand on the pocket's own boxes (EnemyService.setPocketHeight).
-- PLACEHOLDER ART: pockets are greybox parts (PocketLayout).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local BossSim = require(Shared:WaitForChild("BossSim"))
local BossMath = require(Shared:WaitForChild("BossMath"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local SafehouseService = require(script.Parent.SafehouseService)
local BeaconService = require(script.Parent.BeaconService)
local BossService = require(script.Parent.BossService)
local SiteKit = require(script.Parent.SiteKit)
local StoryService = require(script.Parent.StoryService)

local MissionService = {}

local S = Config.Story
local P = S.pockets
local TAG = -8000 -- pocket robots (never an incident's)
local FADE = 0.6 -- the client's fade before the hero is moved
local RESULT_HOLD = 6 -- seconds on the result card before the trip back
local rng = Rng.new(Rng.hash(os.time(), 61))

type Run = {
	num: number,
	m: any,
	player: Player,
	hero: any,
	side: string,
	pocket: number,
	layout: PocketLayout.Layout,
	model: Model,
	steps: { any },
	idx: number,
	have: number,
	need: number,
	level: number,
	entry: CFrame,
	startedAt: number,
	stepAt: number,
	things: { any },
	enemies: { [number]: boolean },
	held: { number },
	points: { { number } },
	waveAt: number,
	wave: number,
	bossId: number?,
	chase: { id: number, path: { { number } }, at: number, leg: number, speed: number }?,
	train: { h: any, from: Vector3, dir: Vector3, length: number, t: number }?,
	wf: { sim: any, targets: { [string]: number }, over: boolean }?,
	asked: boolean,
	done: boolean,
	endAt: number,
}

local busy: { [number]: Run } = {} -- pocket index -> its run
local runs: { [Player]: Run } = {}
local folder: Folder? = nil

local function root(): Folder
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Pockets"
		f.Parent = Workspace
		folder = f
	end
	return folder :: Folder
end

local function v3(t: { number }, up: number?): Vector3
	return Vector3.new(t[1], t[2] + (up or 0), t[3])
end

local function side(run: Run): string
	return run.side
end

---------------------------------------------------------------------------
-- Pockets
---------------------------------------------------------------------------

local function buildPocket(index: number, layout: string): (PocketLayout.Layout, Model)
	local l = PocketLayout.build(Config, index, layout)
	PocketLayout.heights(l)
	local m = Instance.new("Model")
	m.Name = "Pocket" .. index
	for _, b in l.boxes do
		local p = CityBuilder.part(b)
		if b.tag == "pocketWall" then
			p.Transparency = 0.85
			p.CastShadow = false
		end
		p.Parent = m
	end
	m.Parent = root()
	return l, m
end

local function freePocket(): number?
	for i = 1, P.count do
		if not busy[i] then
			return i
		end
	end
	return nil
end

-- Heights for robots inside a pocket (nil outside every built pocket: the city answers)
local function pocketHeight(x: number, z: number, y: number): number?
	local i = PocketLayout.at(Config, x, y, z)
	local run = i and busy[i]
	if run then
		return PocketLayout.heightAt(run.layout, x, z)
	end
	return if i then P.y else nil
end

---------------------------------------------------------------------------
-- Robots
---------------------------------------------------------------------------

local function spawn(
	run: Run,
	kind: string,
	pos: Vector3,
	opts: { hpMult: number?, scripted: boolean? }?
): number?
	local id = EnemyService.spawnAt(kind, pos, run.level, TAG - run.pocket, opts and opts.scripted)
	if id then
		run.enemies[id] = true
		if opts and opts.hpMult then
			EnemyService.tune(id, { hpMult = opts.hpMult })
		end
	end
	return id
end

local function squad(run: Run, kind: string, n: number, at: Vector3, ring: number?)
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:range(0, 0.5)
		local r = (ring or 18) + (i % 3) * 4
		local cfg = Config.Enemies[kind]
		local up = if cfg and cfg.flies then 14 else 0
		spawn(run, kind, at + Vector3.new(math.cos(a) * r, up, math.sin(a) * r))
	end
end

local function clearEnemies(run: Run)
	for id in run.enemies do
		EnemyService.remove(id)
	end
	table.clear(run.enemies)
	run.bossId = nil
	run.chase = nil
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------

local function step(run: Run): any?
	return run.steps[run.idx]
end

local function heroesHere(run: Run): { any }
	return { run.hero }
end

local function cleanStep(run: Run)
	SiteKit.clear(run.things)
	if run.train then
		run.train = nil
	end
	if run.wf then
		BossService.unlinkTargets(run.wf.targets)
		run.wf = nil
	end
	clearEnemies(run)
	StoryService.cancelAsk(run.player)
end

local finishRun: (Run, boolean) -> ()
local startStep: (Run) -> ()

local function advance(run: Run)
	cleanStep(run)
	run.idx += 1
	if run.idx > #run.steps then
		finishRun(run, true)
		return
	end
	startStep(run)
end

local function stepTarget(run: Run): { number }?
	local st = step(run)
	if not st then
		return nil
	end
	local l = run.layout
	if st.kind == "reach" then
		return l.points[st.at]
	elseif st.kind == "boss" or st.kind == "warframe" then
		return l.points.boss
	elseif st.kind == "chase" and run.chase then
		local e = EnemyService.get(run.chase.id)
		return e and { e.x, e.y, e.z }
	elseif st.kind == "defeat" and st.room then
		return l.lists.rooms[st.room]
	elseif st.kind == "break" and run.train then
		local p = run.train.h.pos
		return { p.X, p.Y, p.Z }
	end
	return nil
end

local function warframeArena(run: Run)
	local l = run.layout
	local b = l.points.boss
	local level = run.level
	local hp = BossMath.warframeHp(Config, level)
	local sim = BossSim.new(Config, "NullWarFrame", b[1], b[2], b[3], hp, level, os.clock(), rng)
	sim.cover = {}
	for _, p in l.lists.pillars do
		table.insert(sim.cover, { p[1], p[3], S.warframe.pillarRadius })
	end
	run.wf = { sim = sim, targets = {}, over = false }
	Net.fire("BossAttack", run.player, { k = "land", num = sim.cfg.num, x = b[1], y = b[2], z = b[3] })
end

function startStep(run: Run)
	local st = step(run)
	if not st then
		return
	end
	local l = run.layout
	local k = st.kind
	run.have = 0
	run.need = StoryPlan.need(st)
	run.stepAt = os.clock()
	run.asked = false
	run.points = {}
	run.held = {}
	if k == "hold" then
		local list = if st.at then { l.points[st.at] } else l.lists.stations
		for i = 1, st.points or 1 do
			local p = list[i]
			if p then
				table.insert(run.points, p)
				table.insert(run.held, 0)
				table.insert(run.things, SiteKit.ring(v3(p), st.radius))
			end
		end
		run.wave = 0
		run.waveAt = os.clock() + 2
	elseif k == "break" then
		if st.train then
			local from = v3(l.points.trainStart, 4)
			local d = l.points.trainDir
			local h = SiteKit.object(
				"RunawayTrain",
				from,
				4,
				10,
				st.hits,
				function(m)
					SiteKit.part(
						m,
						Vector3.new(10, 9, 26),
						CFrame.new(0, 4.5, 0),
						Color3.fromRGB(220, 200, 70)
					)
					SiteKit.part(
						m,
						Vector3.new(10.4, 2, 26.4),
						CFrame.new(0, 7, 0),
						Color3.fromRGB(60, 60, 70)
					)
				end,
				nil,
				function()
					if runs[run.player] == run then
						run.have = 1
					end
				end
			)
			h.perHit = true
			table.insert(run.things, h)
			run.train = {
				h = h,
				from = from,
				dir = Vector3.new(d[1], 0, d[2]).Unit,
				length = d[3],
				t = 0,
			}
		else
			for i = 1, st.points do
				local p = l.lists.crates[i]
				if p then
					local h = SiteKit.object(
						"ShardCrate",
						v3(p),
						2,
						5,
						st.hits,
						function(m)
							SiteKit.part(
								m,
								Vector3.new(5, 4, 5),
								CFrame.new(0, 2, 0),
								Color3.fromRGB(120, 90, 200)
							)
							SiteKit.part(
								m,
								Vector3.new(1.5, 3, 1.5),
								CFrame.new(0, 5, 0),
								Color3.fromRGB(160, 230, 255),
								Enum.Material.Neon
							)
						end,
						nil,
						function()
							if runs[run.player] == run then
								run.have += 1
							end
						end
					)
					h.perHit = true
					SiteKit.moveObject(h, v3(p))
					table.insert(run.things, h)
					if st.guards then
						squad(run, st.guards[1], st.guards[2], v3(p), 14)
					end
				end
			end
		end
	elseif k == "chase" then
		local path = l.lists.path
		local id = spawn(run, st.enemy, v3(path[1], 2), { scripted = true })
		if id then
			run.chase = { id = id, path = path, at = 0, leg = 1, speed = st.speed }
		end
	elseif k == "reach" then
		for i = 1, st.turrets or 0 do
			local p = l.lists.turrets[i]
			if p then
				spawn(run, "Turret", v3(p))
			end
		end
	elseif k == "boss" then
		local at = if st.room then v3(l.lists.rooms[st.room]) else v3(l.points.boss)
		if st.room and l.points.boss then
			at = v3(l.points.boss)
		end
		run.bossId = spawn(run, st.enemy, at, { hpMult = st.hpMult })
		if st.adds then
			squad(run, st.adds[1], st.adds[2], at, 22)
		end
	elseif k == "defeat" then
		local at = if st.room then v3(l.lists.rooms[st.room]) else v3(l.points.spawn)
		for _, row in st.squads do
			squad(run, row[1], row[2], at, 20)
		end
	elseif k == "warframe" then
		warframeArena(run)
	end
	-- "choice" waits in tick(): the prompt goes up once the step starts
end

-- The mission's steps again after a choice (the branch goes in at the next index)
local function reresolve(run: Run)
	local story = StoryService.story(run.player)
	if story then
		run.steps = StoryPlan.steps(Config, run.num, side(run), story.choices)
	end
end

local function tickChoice(run: Run, st: any)
	if run.asked then
		return
	end
	run.asked = true
	local story = StoryService.story(run.player)
	if not story then
		return
	end
	if story.choices[st.choice] ~= 0 then
		-- a replay keeps the first pick
		Net.fire(
			"Toast",
			run.player,
			{ id = "choiceKept", choice = st.choice, option = story.choices[st.choice] }
		)
		task.delay(1.5, function()
			if runs[run.player] == run and step(run) == st then
				reresolve(run)
				advance(run)
			end
		end)
		return
	end
	StoryService.ask(run.player, st.choice, StoryPlan.labels(Config, st.choice, side(run)), function(option)
		if runs[run.player] ~= run or step(run) ~= st then
			return
		end
		StoryService.choose(run.player, st.choice, option)
		reresolve(run)
		advance(run)
	end)
end

local function tickWarframe(run: Run, now: number)
	local wf = run.wf
	if not wf or wf.over then
		return
	end
	local sim = wf.sim
	local heroes = {}
	for _, h in heroesHere(run) do
		local p = HeroService.position(h)
		if p then
			table.insert(heroes, { id = h.id, x = p.X, y = p.Y, z = p.Z, alive = h.alive })
		end
	end
	BossSim.step(sim, now, heroes)
	BossService.linkTargets(sim, wf.targets, function() end)
	for _, ev in BossSim.drain(sim) do
		if ev.k == "strike" then
			for _, hit in ev.hits do
				local hero = HeroService.byId(hit[1])
				if hero then
					HeroService.damage(hero, hit[2], { boss = true })
				end
			end
		elseif ev.k == "summon" then
			squad(run, ev.kind, ev.n, Vector3.new(sim.x, sim.y + 4, sim.z), 40)
		elseif ev.k == "dead" then
			wf.over = true
			run.have = 1
		end
		local out = table.clone(ev)
		out.hits = nil
		out.num = sim.cfg.num
		Net.fire("BossAttack", run.player, out)
	end
end

local function holdStep(run: Run, st: any, dt: number, now: number)
	local have = 0
	for i, p in run.points do
		if run.held[i] < st.seconds and #SiteKit.heroesIn(v3(p), st.radius) > 0 then
			run.held[i] = math.min(st.seconds, run.held[i] + dt)
		end
		have += run.held[i]
	end
	run.have = have
	local waves = run.m.waves
	if waves and now >= run.waveAt then
		run.wave += 1
		local w = waves[(run.wave - 1) % #waves + 1]
		local p = run.points[(run.wave - 1) % math.max(1, #run.points) + 1] or run.layout.points.spawn
		squad(run, w[1], w[2], v3(p), 26)
		run.waveAt = now + (run.m.waveGap or 14)
	end
end

local function chaseStep(run: Run, dt: number)
	local c = run.chase
	if not c then
		return
	end
	if not EnemyService.alive(c.id) then
		run.have = 1
		return
	end
	-- hop along the path; at the end it doubles back to the start
	local a, b = c.path[c.leg], c.path[c.leg % #c.path + 1]
	local pa, pb = v3(a, 2), v3(b, 2)
	local len = math.max(1, (pb - pa).Magnitude)
	c.at += c.speed * dt / len
	if c.at >= 1 then
		c.at = 0
		c.leg = c.leg % #c.path + 1
	end
	local pos = pa:Lerp(pb, c.at) + Vector3.new(0, math.sin(c.at * math.pi) * 10, 0)
	EnemyService.place(c.id, pos)
end

local function trainStep(run: Run, dt: number)
	local t = run.train
	if not t or t.h.hp <= 0 then
		return
	end
	t.t = (t.t + 10 * dt) % t.length
	SiteKit.moveObject(t.h, t.from + t.dir * t.t, math.atan2(-t.dir.X, -t.dir.Z))
end

local function tick(run: Run, dt: number, now: number)
	if run.done then
		return
	end
	local st = step(run)
	if not st then
		return
	end
	local k = st.kind
	if k == "hold" then
		holdStep(run, st, dt, now)
	elseif k == "break" then
		trainStep(run, dt)
	elseif k == "chase" then
		chaseStep(run, dt)
	elseif k == "reach" then
		local t = run.layout.points[st.at]
		local p = HeroService.position(run.hero)
		if
			p
			and t
			and (Vector3.new(t[1], 0, t[3]) - Vector3.new(p.X, 0, p.Z)).Magnitude <= S.opening.reach
			and p.Y >= t[2] - 4
		then
			run.have = 1
		end
	elseif k == "choice" then
		tickChoice(run, st)
		return
	elseif k == "warframe" then
		tickWarframe(run, now)
	end
	if run.have >= run.need then
		if k == "warframe" then
			-- the frame powers down and topples before the result
			if run.endAt == 0 then
				run.endAt = now + 3
			elseif now >= run.endAt then
				run.endAt = 0
				advance(run)
			end
		else
			advance(run)
		end
	end
	if now - run.startedAt > run.m.minutes * 60 * 2 + 300 then
		finishRun(run, false) -- an abandoned run frees its pocket
	end
end

---------------------------------------------------------------------------
-- Entering, the result and the trip back
---------------------------------------------------------------------------

local function statePacket(run: Run): { [string]: any }
	local st = step(run)
	local story = StoryService.story(run.player)
	return {
		num = run.num,
		step = run.idx,
		steps = #run.steps,
		kind = st and st.kind or "",
		text = st and st.text or "",
		have = math.floor(run.have * 10) / 10,
		need = run.need,
		target = stepTarget(run),
		points = run.points,
		held = run.held,
		arena = story and story.choices[3] == 2 or false,
		done = run.done,
	}
end

local function bossPacket(run: Run): { [string]: any }
	local wf = run.wf
	if not wf then
		return { state = BossService.STATE.idle, at = 0 }
	end
	local s = wf.sim
	local objectives = {}
	for _, ob in s.objectives do
		table.insert(objectives, if ob.alive then math.ceil(ob.hp / ob.maxHp * 100) else 0)
	end
	return {
		state = BossService.STATE[s.state] or BossService.STATE.fight,
		num = s.cfg.num,
		x = s.x,
		y = s.y,
		z = s.z,
		yaw = s.yaw,
		hp = math.ceil(s.hp),
		max = s.maxHp,
		phase = s.phase,
		at = 0,
		objectives = objectives,
		level = run.level,
		shield = s.shield or 0,
		mission = true,
	}
end

local function travel(run: Run, cf: CFrame, after: (() -> ())?)
	Net.fire("MissionState", run.player, { fade = true })
	task.delay(FADE, function()
		if run.player.Parent then
			SafehouseService.place(run.hero, cf)
		end
		if after then
			after()
		end
	end)
end

local function release(run: Run)
	cleanStep(run)
	if busy[run.pocket] == run then
		busy[run.pocket] = nil
	end
	run.model:Destroy()
	if runs[run.player] == run then
		runs[run.player] = nil
	end
	run.hero.scene = nil
	run.player:SetAttribute("Mission", nil)
	if run.player.Parent then
		Net.fire("MissionState", run.player, { num = 0 })
		Net.fire("BossState", run.player, { state = BossService.STATE.idle, at = 0 })
	end
end

local function pay(run: Run): { [string]: any }
	local player = run.player
	local story = StoryService.story(player)
	local out: { [string]: any } = { num = run.num, first = false }
	if not story then
		return out
	end
	local credits, renown = EconomyService.reward(player, "mission", run.level)
	out.credits, out.renown = credits, renown
	if StoryPlan.clear(story, run.num) then
		out.first = true
		local m = run.m
		if m.renown then
			EconomyService.addRenown(player, m.renown)
			out.renown += m.renown
		end
		if m.loot then
			out.drops = #GearService.grant(player, m.loot, run.level)
		end
		if m.skillPoints then
			StoryService.addSkillPoints(player, m.skillPoints)
			out.skillPoints = m.skillPoints
		end
		local rep = S.rep.mission + (m.rep or 0)
		StoryService.addRep(player, "side", rep)
		out.rep = rep
		-- Test Her: a 10% Epic crate at the end of The Informant
		local test = S.choices[2].options[2]
		if run.num == S.choices[2].mission and story.choices[2] == 2 and rng:chance(test.epicChance) then
			GearService.grantPiece(player, "Epic", run.level)
			out.epic = true
		end
		StoryService.changed(player)
		DataService.saveSoon(player)
	end
	return out
end

function finishRun(run: Run, ok: boolean)
	if run.done then
		return
	end
	run.done = true
	cleanStep(run)
	local player = run.player
	if ok and player.Parent then
		local result = pay(run)
		Net.fire("MissionResult", player, result)
		Net.fire("MissionState", player, statePacket(run))
		task.delay(RESULT_HOLD, function()
			if not player.Parent then
				release(run)
				return
			end
			travel(run, run.entry, function()
				release(run)
			end)
		end)
	else
		if player.Parent then
			travel(run, run.entry, function()
				release(run)
			end)
		else
			release(run)
		end
	end
end

function MissionService.enter(player: Player, num: number): (boolean, string?)
	local hero = HeroService.get(player)
	local story = StoryService.story(player)
	if not hero or not story or not hero.loaded then
		return false, "loading"
	end
	if runs[player] or hero.scene then
		return false, "busy"
	end
	if not hero.alive or hero.traveling or BeaconService.traveling(hero) then
		return false, "busy"
	end
	if HeroService.inCombat(hero) then
		return false, "combat"
	end
	local ok, why = StoryPlan.canEnter(Config, story, hero.level, num)
	if not ok then
		return false, why
	end
	local pocket = freePocket()
	if not pocket then
		return false, "full"
	end
	local root0 = HeroService.rootPart(hero)
	if not root0 then
		return false, "loading"
	end
	local m = S.missions[num]
	local layout, model = buildPocket(pocket, m.layout)
	local hs = StoryService.side(player)
	local run: Run = {
		num = num,
		m = m,
		player = player,
		hero = hero,
		side = hs,
		pocket = pocket,
		layout = layout,
		model = model,
		steps = StoryPlan.steps(Config, num, hs, story.choices),
		idx = 1,
		have = 0,
		need = 1,
		level = math.max(hero.level, m.minLevel),
		entry = root0.CFrame + Vector3.new(0, 2, 0),
		startedAt = os.clock(),
		stepAt = os.clock(),
		things = {},
		enemies = {},
		held = {},
		points = {},
		waveAt = 0,
		wave = 0,
		bossId = nil,
		chase = nil,
		train = nil,
		wf = nil,
		asked = false,
		done = false,
		endAt = 0,
	}
	busy[pocket] = run
	runs[player] = run
	hero.scene = "mission"
	player:SetAttribute("Mission", num)
	Net.fire("BossState", player, { state = BossService.STATE.idle, at = 0 })
	travel(run, CFrame.new(v3(layout.points.spawn, 3)), function()
		if runs[player] == run then
			startStep(run)
			Net.fire("MissionState", player, statePacket(run))
		end
	end)
	return true, nil
end

function MissionService.leave(player: Player)
	local run = runs[player]
	if run and not run.done then
		finishRun(run, false)
	end
end

-- Dev: finish the current step
function MissionService.skipStep(player: Player)
	local run = runs[player]
	if not run or run.done then
		return
	end
	local st = step(run)
	if st and st.kind == "choice" then
		StoryService.choose(player, st.choice, 1)
		reresolve(run)
	end
	advance(run)
end

function MissionService.status(): string
	local n = 0
	for _ in busy do
		n += 1
	end
	return string.format("%d of %d pockets in use", n, P.count)
end

function MissionService.init()
	EnemyService.setPocketHeight(pocketHeight)
	Net.on("MissionEnter", function(player, num)
		local ok, why = MissionService.enter(player, num)
		if not ok then
			Net.fire("Toast", player, { id = "missionRefused", reason = why })
		end
	end)
	Net.on("MissionLeave", MissionService.leave)
	EnemyService.Killed:Connect(function(_, _, _, enemyId)
		for _, run in runs do
			if run.enemies[enemyId] then
				run.enemies[enemyId] = nil
				local st = step(run)
				if st and st.kind == "defeat" then
					run.have += 1
				elseif st and st.kind == "boss" and enemyId == run.bossId then
					run.have = 1
				end
			end
		end
	end)
	-- a defeated hero comes back at the pocket spawn (the War-Frame keeps its HP: a wipe is a retry)
	local previous = SafehouseService.spawnOverride
	SafehouseService.spawnOverride = function(hero)
		local run = hero.player and runs[hero.player]
		if run and not run.done then
			return CFrame.new(v3(run.layout.points.spawn, 3))
		end
		return if previous then previous(hero) else nil
	end
	Players.PlayerRemoving:Connect(function(player)
		local run = runs[player]
		if run then
			run.done = true
			release(run)
		end
	end)
	local acc, sendAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		sendAcc += dt
		if acc < 0.1 then
			return
		end
		local step0 = acc
		acc = 0
		local now = os.clock()
		for _, run in runs do
			tick(run, step0, now)
		end
		if sendAcc >= 0.5 then
			sendAcc = 0
			for player, run in runs do
				if not run.done then
					Net.fire("MissionState", player, statePacket(run))
					if run.wf then
						Net.fire("BossState", player, bossPacket(run))
					end
				end
			end
		end
	end)
end

return MissionService
