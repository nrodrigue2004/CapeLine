-- MissionService: Act 1 missions 2 to 6 in the sealed pockets at y 3,000 (spec: Act 1; Map layout > Mission
-- pockets; Mission.Enter / Mission.Leave / Mission.State 2 Hz; nate's lore, build plan step 5).
-- * Mission.Enter from the Journal (anywhere out of combat): a free pocket is built from PocketLayout, the
--   hero fades in at its spawn and comes back to where they left when it ends. M10: squadmates near the
--   leader come too (party of 4 or less, MissionService.partyOf), from either side: every mission is co-op.
--   Every member is paid, and first-clear rewards go to members on that mission in their own story. The
--   H4 sidekicking: the party's highest level is the mission level (robots and the battle form, with more
--   health per player); members more than 1 level below count as mission level minus 1 inside the pocket
--   (Shared.SidekickRules) and are paid at their own level. A member can leave on their own; the leader
--   leaving ends the run for everyone (in a task force the next member leads instead).
-- * H4 task forces (Shared.TaskForcePlan, TaskForceService) and H5 Nemesis Showdowns: custom runs (m.custom)
--   whose stages are m.steps, each one shared by the whole party; a task force is a chain of legs with a
--   comic panel between them, and a member who leaves can rejoin within 3 minutes.
-- * Stages (StoryPlan.stage): a shared stage is one step for the whole party (a camera beat, a fake, a boss);
--   any other stage runs one track per side present at the same time in the same pocket, each with its own
--   goal and objective text (the Vigil saves people while the Syndicate loots the trucks). The party moves on
--   when every track is done; a side that finished first reads Config.Story.wait. Each side's first member
--   (the leader on the leader's side) answers that side's choice, and branches read their picks.
-- * Step kinds: hold (stand in rings while waves come), break (crates, relays, screens, the cash van or the
--   runaway train: a set number of hits), chase (a robot or a cracked fake hops a path), reach (a point, past
--   turrets), boss (a big robot with adds), defeat (a squad), fake (a famous fake until its face cracks; it
--   stays, cracked and still, through the next camera beat), twin (an evil twin of every member,
--   EnemyService.spawnTwin), scene (a short camera beat: letterbox, fixed subtitled lines, a camera on its
--   focus; it ends on time), choice (the Act 1 choice; replays keep the first pick) and warframe (Bulwark's
--   battle form: the BossSim fight with the pillars as cover; a wipe respawns the hero at the pocket spawn
--   and the boss keeps its HP, so the reward is guaranteed on a retry).
-- * Rewards: every clear pays the Economy "mission" row; the first clear adds the mission's loot, Renown,
--   Skill Point and own-side reputation. After Live, the ending broadcast plays back in the city.
-- * Safety: a run older than twice its minutes plus 5 minutes ends itself and frees its pocket.
-- * Pockets have no PvP and no world scheduler: heroes in a mission are in a scene (no incidents, events
--   or world boss packets) and robots stand on the pocket's own boxes (EnemyService.setPocketHeight).
-- PLACEHOLDER ART: pockets are greybox parts (PocketLayout).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local SetPieceKit = require(Shared:WaitForChild("SetPieceKit"))
local StoryArtKit = require(Shared:WaitForChild("StoryArtKit"))
local BossSim = require(Shared:WaitForChild("BossSim"))
local BossMath = require(Shared:WaitForChild("BossMath"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local SidekickRules = require(Shared:WaitForChild("SidekickRules"))
local TaskForcePlan = require(Shared:WaitForChild("TaskForcePlan"))
local MissionRules = require(Shared:WaitForChild("MissionRules"))
local EnemySim = require(Shared:WaitForChild("EnemySim"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local SafehouseService = require(script.Parent.SafehouseService)
local BeaconService = require(script.Parent.BeaconService)
local BossService = require(script.Parent.BossService)
local BlockService = require(script.Parent.BlockService)
local SiteKit = require(script.Parent.SiteKit)
local PhaseService = require(script.Parent.PhaseService) -- (missions lane: each run is private, see "Phasing")
local SetPieceMeshes = require(script.Parent.SetPieceMeshes)
local PocketArt = require(script.Parent.PocketArt)
local StoryService = require(script.Parent.StoryService)
local Analytics = require(script.Parent.Analytics)
local CinemaService = require(script.Parent.CinemaService)
local CinemaPlan = require(Shared:WaitForChild("CinemaPlan"))

local MissionService = {}

local S = Config.Story
local P = S.pockets
local TAG = -8000 -- pocket robots (never an incident's)
local FADE = 0.6 -- the client's fade before the hero is moved
local RESULT_HOLD = 6 -- seconds on the result card before the trip back
local BROADCAST_DELAY = 1.6 -- seconds back in the city before the ending broadcast
local rng = Rng.new(Rng.hash(os.time(), 61))

type Track = {
	key: string, -- "hero", "villain", or "both" (a shared stage)
	lead: Player, -- who answers this track's choice
	st: any?, -- the step (nil: nothing to do in this stage)
	have: number,
	need: number,
	stepAt: number,
	things: { any },
	enemies: { [number]: boolean },
	points: { { number } },
	held: { number },
	wave: number,
	waveAt: number,
	bossId: number?,
	fakeId: number?,
	twinOf: { [Player]: number },
	chase: { id: number, path: { { number } }, at: number, leg: number, speed: number }?,
	train: { h: any, from: Vector3, dir: Vector3, length: number, t: number }?,
	wf: { sim: any, targets: { [string]: number }, over: boolean, lastBy: number? }?,
	asked: boolean,
	done: boolean,
	endAt: number,
	retry: boolean, -- the server was full when its robots came: startStep tries again each tick
}

type Run = {
	num: number,
	m: any,
	player: Player, -- the leader
	hero: any,
	members: { Player }, -- the leader first
	heroes: { [Player]: any },
	entries: { [Player]: CFrame }, -- where each member comes back to
	sides: { [Player]: string },
	pocket: number,
	layout: PocketLayout.Layout,
	model: Model,
	stage: number,
	stages: number,
	tracks: { [string]: Track },
	kept: { [number]: boolean }, -- a cracked fake held still through the next camera beat
	level: number,
	entry: CFrame,
	startedAt: number,
	done: boolean,
	levels: { [Player]: number }, -- H4: each member's own level (pay, the Renown bonus)
	partyHp: number, -- H4: robots' and bosses' health for the party size
	tf: number?, -- H4: the task force index (nil for an Act 1 mission)
	leg: number?,
	legAt: number?,
	away: { [number]: number }?, -- H4: user id -> when they left (rejoin within Config.TaskForce.rejoin)
	panel: boolean?, -- H4: the comic panel between task force legs is up (no stage starts, nothing is paid)
	phase: number?, -- the run's private phase (PhaseService; see "Phasing" below)
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

-- A break target's (or the runaway train's) plain parts, exactly as before (Shared.StoryArtKit.BOXES: never
-- colliding, the hits are the combat target's), tagged with the look each device draws over them (Fx.StoryProps,
-- gap-story 2026-11-19; until Art.Story is imported, or out of the preset's budget, these parts show)
local function storyParts(m: Model, boxes: string, st: any)
	for _, b in StoryArtKit.BOXES[boxes] do
		SiteKit.part(
			m,
			Vector3.new(b.size[1], b.size[2], b.size[3]),
			CFrame.new(b.at[1], b.at[2], b.at[3]),
			Color3.fromRGB(b.color[1], b.color[2], b.color[3]),
			if b.neon then Enum.Material.Neon else nil
		)
	end
	m:SetAttribute("StoryLook", StoryArtKit.lookFor(st))
end

---------------------------------------------------------------------------
-- Pockets
---------------------------------------------------------------------------

local function buildPocket(index: number, layout: string): (PocketLayout.Layout, Model)
	local l = PocketLayout.build(Config, index, layout)
	PocketLayout.heights(l)
	local dress = PocketArt.dress(l, layout) -- the kit looks (2026-11-19): textures and tints only, no geometry
	local m = Instance.new("Model")
	m.Name = "Pocket" .. index
	-- the side quests' pockets' Blender looks (Layout.art) once Art.SetPieces is imported: the boxes they stand
	-- over stay (hidden, colliding as before); before the import every box shows (PLACEHOLDER ART)
	local drawn = SetPieceMeshes.drawn(l.art)
	for _, b in l.boxes do
		local p = CityBuilder.part(b)
		if b.tag == "pocketWall" then
			p.Transparency = 0.85
			p.CastShadow = false
		end
		if SetPieceKit.hides(b, drawn) then
			SetPieceMeshes.hide(p)
		end
		p.Parent = m
	end
	for i, pl in l.art do
		if drawn[i] then
			SetPieceMeshes.add(m, pl, CFrame.new(pl.x, pl.y, pl.z) * SetPieceMeshes.yaw(pl))
		end
	end
	PocketArt.tier1(m, dress, l, layout, CityBuilder.part) -- every device's dressing; the rest is PocketDecor's
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
	track: Track,
	kind: string,
	pos: Vector3,
	opts: { hpMult: number?, dmg: number?, scripted: boolean? }?
): number?
	local id = EnemyService.spawnAt(kind, pos, run.level, TAG - run.pocket, opts and opts.scripted)
	if id then
		EnemyService.setPhase(id, run.phase) -- (Phasing: the run's own from its first frame)
		track.enemies[id] = true
		local hpMult = (opts and opts.hpMult or 1) * run.partyHp -- H4: more health per player
		if hpMult ~= 1 or (opts and opts.dmg) then
			EnemyService.tune(id, { hpMult = hpMult, dmgMult = opts and opts.dmg })
		end
	end
	return id
end

local function squad(run: Run, track: Track, kind: string, n: number, at: Vector3, ring: number?): number
	local got = 0
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:range(0, 0.5)
		local r = (ring or 18) + (i % 3) * 4
		local cfg = Config.Enemies[kind]
		local up = if cfg and cfg.flies then 14 else 0
		if spawn(run, track, kind, at + Vector3.new(math.cos(a) * r, up, math.sin(a) * r)) then
			got += 1
		end
	end
	return got
end

local function dropKept(run: Run)
	for id in run.kept do
		EnemyService.remove(id)
	end
	table.clear(run.kept)
end

---------------------------------------------------------------------------
-- Phasing (missions lane, 2026-11-20; nate: "other players shouldn't be able to interrupt ur story"): every run has
-- a private phase (PhaseService, Shared.PhaseRules). Its members join it at the start (and on a rejoin) and leave
-- it on the way out; the run closes it. Its robots, its SiteKit pieces (rings, break objects, the train) and the
-- War-Frame's targets are put in it, so only the party sees, touches, hits or is hit by them, and the party is out
-- of the open world's (Controllers.PhaseClient hides the pieces on other devices). phaseTrack is the one sweep:
-- whatever a step made that is not in the phase yet goes in, in the same frame it was made.
---------------------------------------------------------------------------

local function phaseTrack(run: Run, track: Track)
	local phase = run.phase
	if not phase then
		return
	end
	for id in track.enemies do
		if EnemyService.alive(id) and EnemyService.phaseOf(id) ~= phase then
			EnemyService.setPhase(id, phase)
		end
	end
	for _, t in track.things do
		local tagged = if typeof(t) == "Instance"
			then t:GetAttribute("Phase") == phase
			elseif type(t) == "table" then t.phase == phase
			else EnemyService.phaseOf(t) == phase or not EnemyService.alive(t)
		if not tagged then
			SiteKit.inPhase(t, phase)
		end
	end
end

---------------------------------------------------------------------------
-- Tracks
---------------------------------------------------------------------------

local function fireAll(run: Run, name: string, data: any)
	for _, p in run.members do
		if p.Parent then
			Net.fire(name, p, data)
		end
	end
end

-- M10 squads set this: (leader) -> squadmates who may come along (near, free, out of combat)
MissionService.partyOf = nil :: ((Player) -> { Player })?
-- H4: (player, num, { mentor, sidekick, taskForce, party }) a member was paid for a clear (badges, H7)
MissionService.Cleared = Signal.new()
-- H4: TaskForceService sets this: the final pay of a task force (Epic roll, weekly double Renown)
MissionService.payTaskForce = nil :: ((any, Player, { [string]: any }, number) -> { [string]: any })?

-- The members a track is for (every member on a shared stage)
local function membersOf(run: Run, key: string): { Player }
	local out = {}
	for _, p in run.members do
		if key == "both" or run.sides[p] == key then
			table.insert(out, p)
		end
	end
	return out
end

local function heroesOf(run: Run, key: string): { any }
	local out = {}
	for _, p in membersOf(run, key) do
		local h = run.heroes[p]
		if h then
			table.insert(out, h)
		end
	end
	return out
end

-- Who answers a side's choice: the leader on the leader's side, else that side's first member
local function leadFor(run: Run, key: string): Player?
	if key == "both" or run.sides[run.player] == key then
		return run.player
	end
	return membersOf(run, key)[1]
end

local function newTrack(key: string, lead: Player, st: any?): Track
	return {
		key = key,
		lead = lead,
		st = st,
		have = 0,
		need = if st then StoryPlan.need(st) else 1,
		stepAt = os.clock(),
		things = {},
		enemies = {},
		points = {},
		held = {},
		wave = 0,
		waveAt = 0,
		bossId = nil,
		fakeId = nil,
		twinOf = {},
		chase = nil,
		train = nil,
		wf = nil,
		asked = false,
		done = st == nil,
		endAt = 0,
		retry = false,
	}
end

-- A finished (or abandoned) track's things go; a cracked fake stays, held still, for the next camera beat
local function cleanTrack(run: Run, track: Track, keepFake: boolean?)
	SiteKit.clear(track.things)
	track.train = nil
	if track.wf then
		BossService.unlinkTargets(track.wf.targets)
		track.wf = nil
	end
	local fake = track.fakeId
	if keepFake and fake and EnemyService.alive(fake) then
		local e = EnemyService.get(fake)
		e.scripted = true -- the cracked fake stands and stares
		e.dmgMult = 0
		run.kept[fake] = true
		track.enemies[fake] = nil
	end
	for id in track.enemies do
		EnemyService.remove(id)
	end
	table.clear(track.enemies)
	track.bossId, track.fakeId, track.chase = nil, nil, nil
	if track.st and track.st.kind == "choice" then
		StoryService.cancelAsk(track.lead)
	end
end

local function cleanStage(run: Run)
	for _, t in run.tracks do
		cleanTrack(run, t)
	end
end

local finishRun: (Run, boolean) -> ()
local startStage: (Run) -> ()
local nextLeg: (Run) -> ()

local function warframeArena(run: Run, track: Track)
	local l = run.layout
	local b = l.points.boss
	local level = run.level
	local hp = BossMath.warframeHp(Config, level) * run.partyHp
	local sim = BossSim.new(Config, "NullWarFrame", b[1], b[2], b[3], hp, level, os.clock(), rng)
	sim.cover = {}
	for _, p in l.lists.pillars do
		table.insert(sim.cover, { p[1], p[3], S.warframe.pillarRadius })
	end
	track.wf = { sim = sim, targets = {}, over = false }
	BlockService.watchBoss(sim, track.wf.targets) -- WP6: its timed block (Config.Guard.robotBlocks)
	fireAll(run, "BossAttack", { k = "land", num = sim.cfg.num, x = b[1], y = b[2], z = b[3] })
end

-- The chase, boss and defeat steps' robots. A full server (Enemies.caps.perServer) builds none: the step
-- waits (track.retry) and tickTrack tries again each tick, so a boss or a chase never skips; a defeat step
-- fights the robots that came (need is how many). A switched-off type lets the story move on.
local function robots(run: Run, track: Track)
	local st = track.st
	local l = run.layout
	local k = st.kind
	local got, enabled = 0, false
	if k == "chase" then
		local path = l.lists.path
		local id = spawn(run, track, st.enemy, v3(path[1], 2), { scripted = true, hpMult = st.hpMult or 0.3 })
		if id then
			got = 1
			track.chase = { id = id, path = path, at = 0, leg = 1, speed = st.speed }
			if st.fake then
				EnemyService.get(id).unmasked = true -- the fake already cracked: it flees showing metal
			end
		end
		enabled = EnemySim.enabled(Config, st.enemy)
	elseif k == "boss" then
		local at = v3(l.points.boss)
		track.bossId = spawn(run, track, st.enemy, at, { hpMult = st.hpMult })
		if track.bossId then
			got = 1
			if st.adds then
				squad(run, track, st.adds[1], st.adds[2], at, 22)
			end
		end
		enabled = EnemySim.enabled(Config, st.enemy)
	elseif k == "defeat" then
		local at = if st.room
			then v3(l.lists.rooms[st.room])
			elseif st.at then v3(l.points[st.at])
			else v3(l.points.spawn)
		for _, row in st.squads do
			got += squad(run, track, row[1], row[2], at, 20)
			enabled = enabled or EnemySim.enabled(Config, row[1])
		end
		if got > 0 then
			track.need = got -- the robots the server could build are the squad to beat
		end
	end
	local next_ = MissionRules.afterSpawn(got, enabled)
	track.retry = next_ == "wait"
	if next_ == "skip" then
		track.have = track.need
	end
end

local function startStep(run: Run, track: Track)
	local st = track.st
	if not st then
		return
	end
	local l = run.layout
	local k = st.kind
	if k == "hold" then
		local list = if st.at then { l.points[st.at] } else l.lists[st.list or "stations"]
		for i = 1, st.points or 1 do
			local p = list and list[i]
			if p then
				table.insert(track.points, p)
				table.insert(track.held, 0)
				table.insert(track.things, SiteKit.ring(v3(p), st.radius))
			end
		end
		track.waveAt = os.clock() + 2
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
					storyParts(m, "train", st)
				end,
				nil,
				function()
					if not track.done then
						track.have = 1
					end
				end
			)
			h.perHit = true
			table.insert(track.things, h)
			track.train = {
				h = h,
				from = from,
				dir = Vector3.new(d[1], 0, d[2]).Unit,
				length = d[3],
				t = 0,
			}
		else
			local list = if st.at then { l.points[st.at] } else l.lists[st.list or "crates"]
			for i = 1, st.points or 1 do
				local p = list and list[i]
				if p then
					local h = SiteKit.object(
						"StoryCrate",
						v3(p),
						2,
						5,
						st.hits,
						function(m)
							storyParts(m, "crate", st)
						end,
						nil,
						function()
							if not track.done then
								track.have += 1
							end
						end
					)
					h.perHit = true
					SiteKit.moveObject(h, v3(p))
					table.insert(track.things, h)
					if st.guards then
						squad(run, track, st.guards[1], st.guards[2], v3(p), 14)
					end
				end
			end
		end
	elseif k == "chase" or k == "boss" or k == "defeat" then
		robots(run, track)
	elseif k == "reach" then
		for i = 1, st.turrets or 0 do
			local p = l.lists.turrets and l.lists.turrets[i]
			if p then
				spawn(run, track, "Turret", v3(p))
			end
		end
	elseif k == "fake" then
		track.fakeId = spawn(
			run,
			track,
			st.enemy,
			v3(l.points[st.at or "boss"], 2),
			{ hpMult = st.hpMult, dmg = st.dmg }
		)
		if not track.fakeId then
			track.have = 1 -- the fake is switched off: the story moves on
		end
	elseif k == "twin" then
		local at = v3(l.points[st.at or "boss"], 2)
		local n = 0
		for i, p in membersOf(run, track.key) do
			local a = i * 2.1
			local id = EnemyService.spawnTwin(
				p,
				at + Vector3.new(math.cos(a) * 8, 0, math.sin(a) * 8),
				run.level,
				TAG - run.pocket
			)
			if id then
				track.enemies[id] = true
				track.twinOf[p] = id
				n += 1
			end
		end
		track.need = math.max(1, n)
		if n == 0 then
			track.have = 1 -- the twin is switched off: the story moves on
		end
	elseif k == "warframe" then
		warframeArena(run, track)
	end
	-- "choice" waits in tickTrack(): the prompt goes up once the step starts; "scene" runs on the clock
end

-- The next stage: one shared track, or one per side present with that side's step
startStage = function(run: Run)
	if run.panel then
		return -- H4: the panel between legs is up; its own timer starts the next leg (paid once)
	end
	cleanStage(run)
	run.tracks = {}
	if run.stage > run.stages then
		if run.tf and run.leg and run.leg < run.m.legs then
			nextLeg(run) -- H4: the task force's next leg
			return
		end
		finishRun(run, true)
		return
	end
	if run.m.custom then
		-- H4/H5: a task force leg or a Showdown: every stage is one shared step
		dropKept(run)
		run.tracks.both = newTrack("both", run.player, run.m.steps[run.stage])
		startStep(run, run.tracks.both)
		phaseTrack(run, run.tracks.both)
		return
	end
	local present = {}
	local leads = {}
	for _, key in { "hero", "villain" } do
		local lead = leadFor(run, key)
		if lead then
			local story = StoryService.story(lead)
			present[key] = if story then story.choices else {}
			leads[key] = lead
		end
	end
	local plan = StoryPlan.tracks(Config, run.num, run.stage, present)
	if not (plan.both and plan.both.kind == "scene") then
		dropKept(run) -- a cracked fake stays only through the camera beat right after it
	end
	for key, st in plan do
		run.tracks[key] = newTrack(key, leads[key] or run.player, st or nil)
	end
	for _, t in run.tracks do
		startStep(run, t)
		phaseTrack(run, t)
	end
end

local function tickChoice(run: Run, track: Track, st: any)
	if not table.find(run.members, track.lead) then
		-- the side's chooser left: the next member of that side answers
		local lead = leadFor(run, track.key)
		if not lead then
			track.done = true
			return
		end
		track.lead, track.asked = lead, false
	end
	if track.asked then
		return
	end
	track.asked = true
	local lead = track.lead
	local story = StoryService.story(lead)
	if not story then
		track.have = 1
		return
	end
	if story.choices[st.choice] ~= 0 then
		-- a replay keeps the first pick
		Net.fire("Toast", lead, { id = "choiceKept", choice = st.choice, option = story.choices[st.choice] })
		task.delay(1.5, function()
			if track.st == st and not track.done then
				track.have = 1
			end
		end)
		return
	end
	StoryService.ask(lead, st.choice, StoryPlan.labels(Config, st.choice, track.key), function(option)
		if runs[lead] ~= run or track.st ~= st or track.done then
			return
		end
		StoryService.choose(lead, st.choice, option)
		track.have = 1
	end)
end

local function tickWarframe(run: Run, track: Track, now: number)
	local wf = track.wf
	if not wf or wf.over then
		return
	end
	local sim = wf.sim
	local heroes = {}
	for _, h in heroesOf(run, "both") do
		local p = HeroService.position(h)
		if p then
			table.insert(heroes, { id = h.id, x = p.X, y = p.Y, z = p.Z, alive = h.alive })
		end
	end
	BossSim.step(sim, now, heroes)
	BossService.linkTargets(sim, wf.targets, function(heroId)
		wf.lastBy = heroId or wf.lastBy -- lore step 7: who landed the blow that ends a phase (the finisher)
	end, run.phase)
	for _, ev in BossSim.drain(sim) do
		if ev.k == "strike" then
			for _, hit in ev.hits do
				local hero = HeroService.byId(hit[1])
				if hero then
					HeroService.damage(hero, hit[2], { boss = true })
					BossService.strikeHero(hero, ev, sim) -- the counters: a tether yanks, a swat knocks down
				end
			end
		elseif ev.k == "summon" then
			squad(run, track, ev.kind, ev.n, Vector3.new(sim.x, sim.y + 4, sim.z), 40)
		elseif ev.k == "dead" then
			wf.over = true
			track.have = 1
		end
		local out = table.clone(ev)
		out.hits = nil
		out.num = sim.cfg.num
		if ev.k == "phase" or ev.k == "dead" then
			out.by = wf.lastBy -- the finishing hero's id (slow-mo finisher on their screen, shorter nearby)
		end
		fireAll(run, "BossAttack", out)
	end
end

local function holdStep(run: Run, track: Track, st: any, dt: number, now: number)
	local have = 0
	for i, p in track.points do
		if track.held[i] < st.seconds and #SiteKit.heroesIn(v3(p), st.radius, run.phase) > 0 then
			track.held[i] = math.min(st.seconds, track.held[i] + dt)
		end
		have += track.held[i]
	end
	track.have = have
	local waves = st.waves or (run.m.custom and run.m.waves) -- a task force leg's waves sit on the leg
	if waves and now >= track.waveAt then
		track.wave += 1
		local w = waves[(track.wave - 1) % #waves + 1]
		local p = track.points[(track.wave - 1) % math.max(1, #track.points) + 1] or run.layout.points.spawn
		squad(run, track, w[1], w[2], v3(p), 26)
		track.waveAt = now + (st.waveGap or run.m.waveGap or 14)
	end
end

local function chaseStep(track: Track, dt: number)
	local c = track.chase
	if not c then
		return
	end
	if not EnemyService.alive(c.id) then
		track.have = 1
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

local function trainStep(track: Track, dt: number)
	local t = track.train
	if not t or t.h.hp <= 0 then
		return
	end
	t.t = (t.t + 10 * dt) % t.length
	SiteKit.moveObject(t.h, t.from + t.dir * t.t, math.atan2(-t.dir.X, -t.dir.Z))
end

local function fakeStep(track: Track, st: any)
	local e = track.fakeId and EnemyService.get(track.fakeId)
	local cracked = not e or not e.alive or FakeRules.cracked(Config, e.health / math.max(1, e.maxHealth))
	if cracked and track.have < 1 then
		track.have = 1
		if st.news then
			local def = Config.Enemies[st.enemy]
			Net.fireAll("Toast", { id = "news", key = st.news, name = def and def.name or st.enemy })
		end
	end
end

local function tickTrack(run: Run, track: Track, dt: number, now: number)
	local st = track.st
	if track.done or not st then
		return
	end
	if track.retry then
		robots(run, track) -- a full server: try the step's robots again
		if track.retry then
			return
		end
	end
	local k = st.kind
	if k == "hold" then
		holdStep(run, track, st, dt, now)
	elseif k == "break" then
		trainStep(track, dt)
	elseif k == "chase" then
		chaseStep(track, dt)
	elseif k == "fake" then
		fakeStep(track, st)
	elseif k == "scene" then
		track.have = now - track.stepAt
		if track.have >= track.need then
			-- lore step 7: each hero on this stage has now seen its camera beat (SKIP from the next time)
			local bit = if run.m.custom then nil else CinemaPlan.missionBit(Config, run.num, run.stage)
			for _, h in heroesOf(run, track.key) do
				if h.player then
					CinemaService.mark(h.player, bit)
				end
			end
		end
	elseif k == "reach" then
		local t = run.layout.points[st.at]
		for _, h in heroesOf(run, track.key) do
			local p = HeroService.position(h)
			if
				p
				and t
				and (Vector3.new(t[1], 0, t[3]) - Vector3.new(p.X, 0, p.Z)).Magnitude <= S.opening.reach
				and p.Y >= t[2] - 4
			then
				track.have = 1
			end
		end
	elseif k == "choice" then
		tickChoice(run, track, st)
	elseif k == "warframe" then
		tickWarframe(run, track, now)
	end
	if track.have >= track.need then
		if k == "warframe" then
			-- the battle form powers down and topples before the result
			if track.endAt == 0 then
				track.endAt = now + 3
				return
			elseif now < track.endAt then
				return
			end
		end
		track.done = true
		cleanTrack(run, track, k == "fake")
	end
end

local function tick(run: Run, dt: number, now: number)
	if run.done then
		return
	end
	for _, t in run.tracks do
		tickTrack(run, t, dt, now)
		phaseTrack(run, t)
	end
	if run.done then
		return
	end
	-- no tracks yet (the fade in, a task force's panel between legs) is waiting, never "all done"
	if MissionRules.advance(run.tracks, run.panel) then
		run.stage += 1
		startStage(run)
	end
	if not run.done and now - (run.legAt or run.startedAt) > run.m.minutes * 60 * 2 + 300 then
		finishRun(run, false) -- an abandoned run frees its pocket
	end
end

---------------------------------------------------------------------------
-- What each member sees
---------------------------------------------------------------------------

local function trackFor(run: Run, player: Player): Track?
	return run.tracks.both or run.tracks[run.sides[player] or "hero"]
end

local function keptPos(run: Run): { number }?
	for id in run.kept do
		local e = EnemyService.get(id)
		if e and e.alive then
			return { e.x, e.y, e.z }
		end
	end
	return nil
end

local function enemyPos(id: number?): { number }?
	local e = id and EnemyService.get(id)
	return if e and e.alive then { e.x, e.y, e.z } else nil
end

local function stepTarget(run: Run, track: Track, player: Player): { number }?
	local st = track.st
	if not st or track.done then
		return nil
	end
	local l = run.layout
	local k = st.kind
	if k == "reach" then
		return l.points[st.at]
	elseif k == "boss" or k == "warframe" then
		return l.points.boss
	elseif k == "fake" then
		return enemyPos(track.fakeId)
	elseif k == "twin" then
		return enemyPos(track.twinOf[player])
	elseif k == "chase" and track.chase then
		return enemyPos(track.chase.id)
	elseif k == "defeat" and st.room then
		return l.lists.rooms[st.room]
	elseif k == "break" and track.train then
		local p = track.train.h.pos
		return { p.X, p.Y, p.Z }
	elseif k == "break" and st.at then
		return l.points[st.at]
	end
	return nil
end

-- Does this character's pick light Live's arena (Destroy It)? A cosmetic effect only.
local function arenaOn(story: any, side: string): boolean
	for n in S.choices do
		local o = StoryPlan.option(Config, n, side, story.choices[n] or 0)
		if o and o.arena then
			return true
		end
	end
	return false
end

-- Lore step 7: has every hero on this stage seen its camera beat before (on their own saves)?
local function sceneSeen(run: Run, track: Track): boolean
	local bit = if run.m.custom then nil else CinemaPlan.missionBit(Config, run.num, run.stage)
	if bit == nil then
		return false
	end
	for _, h in heroesOf(run, track.key) do
		if not h.player or not CinemaService.seen(h.player, bit) then
			return false
		end
	end
	return true
end

local function statePacket(run: Run, player: Player): { [string]: any }
	local side = run.sides[player] or "hero"
	local track = trackFor(run, player)
	local st = track and track.st
	local story = StoryService.story(player)
	local now = os.clock()
	local out: { [string]: any } = {
		num = run.num,
		step = run.stage,
		steps = run.stages,
		side = side,
		arena = story ~= nil and not run.m.custom and arenaOn(story, side),
		done = run.done,
		-- H4: a task force run (its index, the leg, how many)
		tf = run.tf,
		leg = run.leg,
		legs = run.tf and run.m.legs or nil,
	}
	if not track or not st or track.done then
		-- this side's job is done; the other side is still on theirs
		out.kind, out.text, out.have, out.need = "wait", S.wait[StoryPlan.sideKey(side)], 1, 1
		return out
	end
	out.kind = st.kind
	out.text = StoryPlan.text(st, side)
	out.have = math.floor(track.have * 10) / 10
	out.need = track.need
	out.target = stepTarget(run, track, player)
	out.points = track.points
	out.held = track.held
	if st.kind == "hold" then
		out.seconds = st.seconds
		out.people = st.people or nil -- people pinned at the rings (StoryFx draws them; gap-story)
	end
	out.t = now - track.stepAt
	if st.kind == "scene" then
		out.focus = if st.focus == "fake" then keptPos(run) else run.layout.points[st.focus or "spawn"]
		out.lodestar = if st.lodestar then run.layout.points[st.lodestar] else nil
		out.seen = sceneSeen(run, track) or nil -- lore step 7: SKIP shows when every hero here saw it
	end
	return out
end

local function sendState(run: Run)
	for _, p in run.members do
		if p.Parent then
			Net.fire("MissionState", p, statePacket(run, p))
		end
	end
end

local function bossPacket(run: Run): { [string]: any }
	local wf = nil
	for _, t in run.tracks do
		wf = wf or t.wf
	end
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

---------------------------------------------------------------------------
-- Entering, the result and the trip back
---------------------------------------------------------------------------

local function travel(run: Run, player: Player, cf: CFrame, after: (() -> ())?)
	Net.fire("MissionState", player, { fade = true })
	task.delay(FADE, function()
		local hero = run.heroes[player]
		if player.Parent and hero then
			SafehouseService.place(hero, cf)
		end
		if after then
			after()
		end
	end)
end

-- One member out of the run (back in the city, or gone). A side left with nobody has nothing more to do.
local function releaseMember(run: Run, player: Player)
	local at = table.find(run.members, player)
	if at then
		table.remove(run.members, at)
	end
	if runs[player] == run then
		runs[player] = nil
	end
	local hero = run.heroes[player]
	run.heroes[player] = nil
	if hero then
		hero.scene = nil
		MissionService.setRaise(hero, nil) -- H4: the raise never leaves the pocket
		PhaseService.leave(hero) -- (Phasing: back to the open world)
	end
	local side = run.sides[player]
	run.sides[player] = nil
	local t = side and run.tracks[side]
	if t and not t.done and #membersOf(run, side) == 0 then
		t.done = true
		cleanTrack(run, t)
	end
	player:SetAttribute("Mission", nil)
	if player.Parent then
		Net.fire("MissionState", player, { num = 0 })
		Net.fire("BossState", player, { state = BossService.STATE.idle, at = 0 })
	end
end

local function release(run: Run)
	cleanStage(run)
	dropKept(run)
	if busy[run.pocket] == run then
		busy[run.pocket] = nil
		EnemyService.usePocket(run.pocket, nil)
	end
	run.model:Destroy()
	for _, p in table.clone(run.members) do
		releaseMember(run, p)
	end
	PhaseService.close(run.phase) -- (Phasing)
	run.phase = nil
end

local function pay(run: Run, player: Player): { [string]: any }
	local story = StoryService.story(player)
	local out: { [string]: any } =
		{ num = run.num, first = false, ending = StoryPlan.ending(Config, run.num) }
	if not story then
		return out
	end
	-- H4: paid at your own level; a sidekick +20% Renown, the top member +10% as a mentor
	local own = run.levels[player] or run.level
	local credits, renown = EconomyService.reward(player, "mission", own)
	out.credits, out.renown = credits, renown
	local levels = MissionRules.partyLevels(run.members, run.levels) -- members who left no longer count
	local mult, mentor, sidekick = SidekickRules.renown(Config.Sidekick, own, levels)
	if mult > 1 and renown > 0 then
		local extra = math.floor(renown * (mult - 1) + 0.5)
		EconomyService.addRenown(player, extra)
		out.renown += extra
	end
	out.sidekick, out.mentor = sidekick or nil, mentor or nil
	MissionService.Cleared:Fire(
		player,
		run.num,
		{ mentor = mentor, sidekick = sidekick, taskForce = run.tf, party = #run.members }
	)
	if run.tf then
		return MissionService.payTaskForce and MissionService.payTaskForce(run, player, out, own) or out
	elseif run.m.custom then
		-- H5: a Showdown (or any other run made outside Config.Story) pays through its own hook
		return if run.m.pay then run.m.pay(run, player, out, own) else out
	end
	-- first-clear rewards only for a member on this mission in their own story (a helper replaying it, or
	-- ahead of it, gets the clear pay above)
	local canClear = player == run.player or StoryPlan.canEnter(Config, story, own, run.num)
	if canClear and StoryPlan.clear(story, run.num) then
		out.first = true
		local m = run.m
		if m.renown then
			EconomyService.addRenown(player, m.renown)
			out.renown += m.renown
		end
		if m.loot then
			out.drops = #GearService.grant(player, m.loot, own)
		end
		if m.skillPoints then
			StoryService.addSkillPoints(player, m.skillPoints)
			out.skillPoints = m.skillPoints
		end
		local rep = S.rep.mission + (m.rep or 0)
		StoryService.addRep(player, "side", rep)
		out.rep = rep
		StoryService.changed(player)
		DataService.saveSoon(player)
	end
	return out
end

-- Send everyone home (after the result card when ok), then free the pocket. After the act's last mission
-- the ending broadcast plays once each member is back in the city.
function finishRun(run: Run, ok: boolean)
	if run.done then
		return
	end
	run.done = true
	cleanStage(run)
	local members = table.clone(run.members)
	local ending = if ok then StoryPlan.ending(Config, run.num) else nil
	if ok then
		for _, player in members do
			if player.Parent then
				Analytics.event(
					player,
					"mission_done",
					math.floor(os.clock() - run.startedAt),
					{ run.m.id, #members, run.sides[player] or "hero" }
				)
				Analytics.step(player, "Story", "mission_done")
				if StoryPlan.actOf(Config, run.num) == 1 and StoryPlan.actLast(Config, run.num) then -- WP11: Act 1's last
					Analytics.step(player, "Story", "act_done")
				end
				Net.fire("MissionResult", player, pay(run, player))
				Net.fire("MissionState", player, statePacket(run, player))
			end
		end
	end
	task.delay(if ok then RESULT_HOLD else 0, function()
		local left = #members
		if left == 0 then
			release(run)
			return
		end
		local function one()
			left -= 1
			if left <= 0 then
				release(run)
			end
		end
		for _, player in members do
			if player.Parent and runs[player] == run then
				travel(run, player, run.entries[player] or run.entry, function()
					one()
					if ending then
						task.delay(BROADCAST_DELAY, function()
							if player.Parent then
								Net.fire("StoryBroadcast", player, { id = ending })
							end
						end)
					end
				end)
			else
				one()
			end
		end
	end)
end

-- A member who is not the leader goes home on their own
local function memberLeave(run: Run, player: Player)
	if player.Parent then
		travel(run, player, run.entries[player] or run.entry, function()
			releaseMember(run, player)
		end)
	else
		releaseMember(run, player)
	end
end

-- H4: a sidekick's raise (Shared.SidekickRules): stats, health and gear item levels count at `raise` while
-- the hero is in a pocket; nil ends it. The SIDEKICK badge reads the Sidekick attribute.
function MissionService.setRaise(hero: any, raise: number?)
	if hero.raise == raise then
		return
	end
	hero.raise = raise
	local player = hero.player
	if player then
		player:SetAttribute("Sidekick", raise)
		if player.Parent then
			GearService.refresh(player) -- rebuilds the gear stats and calls HeroService.refresh
		end
	else
		HeroService.refresh(hero)
	end
end

-- Mission level and raises for the party, then everyone into the pocket (the leader first)
local function begin(
	player: Player,
	members: { Player },
	heroes: { [Player]: any },
	entries: { [Player]: CFrame },
	sides: { [Player]: string },
	pocket: number,
	m: any,
	num: number,
	tf: number?
): Run
	local layout, model = buildPocket(pocket, m.layout)
	local levels: { [Player]: number } = {}
	local list = {}
	for _, p in members do
		levels[p] = heroes[p].level
		table.insert(list, heroes[p].level)
	end
	local level = SidekickRules.missionLevel(list, m.minLevel)
	local root0 = HeroService.rootPart(heroes[player])
	local run: Run = {
		num = num,
		m = m,
		player = player,
		hero = heroes[player],
		members = members,
		heroes = heroes,
		entries = entries,
		sides = sides,
		pocket = pocket,
		layout = layout,
		model = model,
		stage = 1,
		stages = if m.custom then #m.steps else StoryPlan.stages(Config, num),
		tracks = {},
		kept = {},
		level = level,
		entry = entries[player] or (root0 and root0.CFrame) or CFrame.new(),
		startedAt = os.clock(),
		done = false,
		levels = levels,
		partyHp = SidekickRules.partyHp(Config.Sidekick, #members),
		tf = tf,
		leg = if tf then 1 else nil,
		legAt = os.clock(),
		away = if tf then {} else nil,
		phase = PhaseService.open(), -- (Phasing)
	}
	busy[pocket] = run
	EnemyService.usePocket(pocket, run.layout) -- its walls and ceilings stop robots (and their fliers)
	for i, p in members do
		runs[p] = run
		heroes[p].scene = "mission"
		PhaseService.join(run.phase, heroes[p]) -- (Phasing)
		p:SetAttribute("Mission", num)
		Net.fire("BossState", p, { state = BossService.STATE.idle, at = 0 })
		local raise = SidekickRules.raised(Config.Sidekick, heroes[p].level, level)
		MissionService.setRaise(heroes[p], if raise > heroes[p].level then raise else nil)
		local spot = CFrame.new(v3(layout.points.spawn, 3) + Vector3.new((i - 1) * 4 - 6, 0, 0))
		travel(
			run,
			p,
			spot,
			if p == player
				then function()
					if runs[player] == run then
						startStage(run)
						sendState(run)
					end
				end
				else nil
		)
	end
	return run
end

-- H4: the next leg of a task force: pay the leg, show the comic panel, build the next pocket, move everyone
nextLeg = function(run: Run)
	for _, p in run.members do
		if p.Parent then
			Net.fire("MissionResult", p, pay(run, p))
		end
	end
	local leg = TaskForcePlan.leg(Config.TaskForce, run.tf :: number, (run.leg :: number) + 1)
	if not leg then
		finishRun(run, true)
		return
	end
	run.leg = leg.leg
	run.panel = true
	-- PLACEHOLDER CONTENT: lore thread to fill (the panel id names the comic panel between legs)
	for _, p in run.members do
		if p.Parent then
			local packet = statePacket(run, p)
			packet.panel = leg.panel
			Net.fire("MissionState", p, packet)
		end
	end
	task.delay(Config.TaskForce.panelTime, function()
		run.panel = nil
		if run.done or busy[run.pocket] ~= run then
			return
		end
		run.model:Destroy()
		run.layout, run.model = buildPocket(run.pocket, leg.layout)
		run.m = leg
		run.stage = 1
		run.stages = #leg.steps
		run.legAt = os.clock()
		for i, p in run.members do
			local spot = CFrame.new(v3(run.layout.points.spawn, 3) + Vector3.new((i - 1) * 4 - 6, 0, 0))
			travel(
				run,
				p,
				spot,
				if i == 1
					then function()
						if not run.done then
							startStage(run)
							sendState(run)
						end
					end
					else nil
			)
		end
	end)
end

-- H4/H5: a run made outside Config.Story (a task force leg, a Nemesis Showdown): m is mission-shaped
-- (layout, minLevel, minutes, steps, num, id; custom = true with an optional pay hook). The leader first.
function MissionService.enterCustom(players: { Player }, leg: any, tf: number?): (boolean, string?)
	local leader = players[1]
	if not leader then
		return false, "none"
	end
	local pocket = freePocket()
	if not pocket then
		return false, "full"
	end
	local members, heroes, entries, sides = {}, {}, {}, {}
	for _, p in players do
		local h = HeroService.get(p)
		local r = h and HeroService.rootPart(h)
		if h and r and h.loaded and not runs[p] and not h.scene and h.alive and not h.traveling then
			if #members < Config.TaskForce.maxPlayers then
				table.insert(members, p)
				heroes[p] = h
				entries[p] = r.CFrame + Vector3.new(0, 2, 0)
				sides[p] = StoryService.side(p)
			end
		end
	end
	if members[1] ~= leader then
		return false, "busy"
	end
	leg.custom = true
	begin(leader, members, heroes, entries, sides, pocket, leg, leg.num, tf)
	return true, nil
end

-- H4: start a task force for a squad (TaskForceService checks who may come); the leader first
function MissionService.enterTaskForce(players: { Player }, tf: number): (boolean, string?)
	local leg = TaskForcePlan.leg(Config.TaskForce, tf, 1)
	if not leg then
		return false, "none"
	end
	return MissionService.enterCustom(players, leg, tf)
end

-- H4: back into a task force you left less than 3 minutes ago (same server)
function MissionService.rejoin(player: Player): boolean
	local hero = HeroService.get(player)
	local root = hero and HeroService.rootPart(hero)
	if not hero or not root or runs[player] or hero.scene or not hero.alive then
		return false
	end
	for _, run in busy do
		local left = run.away and run.away[player.UserId]
		if not run.done and run.tf and TaskForcePlan.canRejoin(Config.TaskForce, left, os.clock()) then
			(run.away :: { [number]: number })[player.UserId] = nil
			table.insert(run.members, player)
			run.heroes[player] = hero
			run.entries[player] = root.CFrame + Vector3.new(0, 2, 0)
			run.sides[player] = StoryService.side(player)
			run.levels[player] = run.levels[player] or hero.level
			runs[player] = run
			hero.scene = "mission"
			PhaseService.join(run.phase, hero) -- (Phasing)
			player:SetAttribute("Mission", run.num)
			local raise = SidekickRules.raised(Config.Sidekick, hero.level, run.level)
			MissionService.setRaise(hero, if raise > hero.level then raise else nil)
			travel(run, player, CFrame.new(v3(run.layout.points.spawn, 3)), function()
				Net.fire("MissionState", player, statePacket(run, player))
			end)
			return true
		end
	end
	return false
end

-- H4: is there a task force run this player left less than 3 minutes ago?
function MissionService.canRejoin(player: Player): boolean
	if runs[player] then
		return false
	end
	for _, run in busy do
		local left = run.away and run.away[player.UserId]
		if not run.done and run.tf and TaskForcePlan.canRejoin(Config.TaskForce, left, os.clock()) then
			return true
		end
	end
	return false
end

-- H4: who is in which run (TaskForceService shows squads in a run; badges count clears)
function MissionService.runOf(player: Player): any?
	return runs[player]
end

-- H5: the boss robot of a run's current shared stage (a Showdown's nemesis), if it is up
function MissionService.bossOf(run: any): number?
	local t = run and run.tracks and run.tracks.both
	return t and t.bossId
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
	-- the party: the leader plus squadmates near them who are free (MissionService.partyOf), either side
	local members = { player }
	local heroes = { [player] = hero }
	local entries = { [player] = root0.CFrame + Vector3.new(0, 2, 0) }
	local sides = { [player] = StoryService.side(player) }
	for _, mate in (if MissionService.partyOf then MissionService.partyOf(player) else {}) do
		local h = HeroService.get(mate)
		local r = h and HeroService.rootPart(h)
		local free = h
			and MissionRules.canJoin(
				h,
				runs[mate] ~= nil,
				HeroService.inCombat(h),
				BeaconService.traveling(h)
			)
		if free and r and #members < Config.Squad.max then
			table.insert(members, mate)
			heroes[mate] = h
			entries[mate] = r.CFrame + Vector3.new(0, 2, 0)
			sides[mate] = StoryService.side(mate)
		end
	end
	begin(player, members, heroes, entries, sides, pocket, m, num)
	return true, nil
end

-- H4: a task force member leaves (on purpose or dropped): they keep their place for 3 minutes, the next
-- member leads if it was the leader, and the run only ends when everyone is gone
function MissionService.leaveTaskForce(run: Run, player: Player)
	run.away = run.away or {};
	(run.away :: { [number]: number })[player.UserId] = os.clock()
	if player == run.player then
		local nextOne = TaskForcePlan.nextLeader(run.members, player)
		if nextOne then
			run.player = nextOne
			run.hero = run.heroes[nextOne]
			if run.tracks.both then
				run.tracks.both.lead = nextOne
			end
		end
	end
	if #run.members <= 1 then
		-- the last one: finishRun takes them home (still a member) and frees the pocket once they are out
		finishRun(run, false)
		return
	end
	if player.Parent then
		memberLeave(run, player)
	else
		releaseMember(run, player)
	end
end

function MissionService.leave(player: Player)
	local run = runs[player]
	if run and not run.done then
		if run.tf then
			MissionService.leaveTaskForce(run, player)
		elseif player == run.player then
			finishRun(run, false)
		else
			memberLeave(run, player)
		end
	end
end

-- SKIP on a mission's camera beat (lore step 7): only when every hero on that stage has seen it before
function MissionService.skipScene(player: Player)
	local run = runs[player]
	local track = run and not run.done and trackFor(run, player)
	local st = track and track.st
	if run and track and st and st.kind == "scene" and not track.done and sceneSeen(run, track) then
		track.stepAt = os.clock() - track.need
		track.have = track.need
	end
end

-- Dev: finish the current stage for every side (an open choice takes its first option)
function MissionService.skipStep(player: Player)
	local run = runs[player]
	if not run or run.done then
		return
	end
	for _, t in run.tracks do
		local st = t.st
		if st and st.kind == "choice" and not t.done then
			StoryService.choose(t.lead, st.choice, 1)
		end
		t.done = true
	end
	cleanStage(run)
	run.stage += 1
	startStage(run)
	sendState(run)
end

-- Dev: jump to stage n of the running mission
function MissionService.jumpStage(player: Player, n: number)
	local run = runs[player]
	if not run or run.done or n < 1 or n > run.stages then
		return
	end
	dropKept(run)
	run.stage = n
	startStage(run)
	sendState(run)
end

-- The stage a player's run is on, and how many there are (Dev panel)
function MissionService.stageOf(player: Player): (number, number)
	local run = runs[player]
	if not run then
		return 0, 0
	end
	return run.stage, run.stages
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
		local run = runs[player]
		if ok and run then
			Analytics.event(
				player,
				"mission_start",
				1,
				{ run.m.id, #run.members, run.sides[player] or "hero" }
			)
			Analytics.step(player, "Story", "mission_start")
		end
		if not ok then
			Net.fire("Toast", player, { id = "missionRefused", reason = why })
		end
	end)
	Net.on("MissionLeave", MissionService.leave)
	Net.on("SceneSkip", MissionService.skipScene)
	EnemyService.Killed:Connect(function(_, _, _, enemyId)
		for _, run in busy do
			run.kept[enemyId] = nil
			for _, t in run.tracks do
				if t.enemies[enemyId] then
					t.enemies[enemyId] = nil
					local st = t.st
					if st and not t.done then
						if st.kind == "defeat" or st.kind == "twin" then
							t.have += 1
						elseif st.kind == "boss" and enemyId == t.bossId then
							t.have = 1
						end
					end
				end
			end
		end
	end)
	-- a defeated hero comes back at the pocket spawn (the battle form keeps its HP: a wipe is a retry)
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
		if run and run.tf and not run.done then
			MissionService.leaveTaskForce(run, player)
		elseif run then
			if player == run.player then
				releaseMember(run, player)
				finishRun(run, false) -- the others go home
			else
				releaseMember(run, player)
			end
		end
	end)
	local acc, sendAcc = 0, 0
	RunService.Heartbeat:Connect(FrameProf.wrap("MissionService", function(dt)
		acc += dt
		sendAcc += dt
		if acc < 0.1 then
			return
		end
		local step0 = acc
		acc = 0
		local now = os.clock()
		for _, run in busy do
			tick(run, step0, now)
		end
		if sendAcc >= 0.5 then
			sendAcc = 0
			for player, run in runs do
				if not run.done then
					Net.fire("MissionState", player, statePacket(run, player))
					local b = bossPacket(run)
					if b.mission then
						Net.fire("BossState", player, b)
					end
				end
			end
		end
	end))
end

return MissionService
