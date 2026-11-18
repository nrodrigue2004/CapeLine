-- OpeningService: the Ceremony prologue, mission 1 (nate's lore, build plan step 3). Runs once per character,
-- right after its creator, on the server, for that player only. The beats (Shared.OpeningPlan.STEPS):
--   ceremony: in the street outfit, in the crowd at Silas Crane's medal ceremony before Crane's Hero Hall, the
--     three famous fakes (Radiant, Bulwark, Skylance) on the stage as heroes (camera beats, Crane speaks)
--   scan: Crane's scanner sweeps the crowd and stops on the hero: SPARK DETECTED; panic
--   run: through the fleeing crowd to the spark point down the street
--   spark: the small Spark fires (Basic, or by itself): a Vigil hero's makes a shield over a kid under falling
--     debris; a Syndicate villain's blasts the man who shoved them across the plaza (cartoon)
--   leap: up on a roof: one Leap to the next, the full power firing in slow motion (the path's own look)
--   chase: Skylance chases over the roofs (telegraphed spears that never hit); Patch on the radio from here
--   suit: the chosen suit snaps on piece by piece (the street outfit comes off)
--   descend: down to the subway steps; then the subway pocket (PocketLayout's subway lane, one per prologue)
--   tunnel: run the tunnel while slabs fall across it on a timer (under one: knocked back, no damage)
--   fight: Skylance in the chamber; the fight ends when its face cracks to metal (Lore 4's unmasking)
--   swarm: a squad of Crane Troopers; the hero is overwhelmed (never defeated: hero.floor)
--   rescue: Lodestar crashes in, a line, he grabs the hero
--   title: the Crane Industries billboard and the CAPELINE title card; the rewards land at its start and the
--     hero is back in the plaza, in the normal game. OpeningService.Finished is the hook for mission 2.
-- Safety: a beat that does not finish moves on by itself (Config.Story.opening.stuck) and the whole prologue
-- finishes itself after Config.Story.opening.timeout. Camera beats are skippable on a replay, for a
-- returning account, or once this save has seen that beat (lore step 7, CinemaService's seen set). The hero is in a scene: no incidents, events or ambient robots find it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local Progress = require(Shared:WaitForChild("Progress"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local MissionRules = require(Shared:WaitForChild("MissionRules"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local SafehouseService = require(script.Parent.SafehouseService)
local StoryService = require(script.Parent.StoryService)
local Analytics = require(script.Parent.Analytics)
local CinemaService = require(script.Parent.CinemaService)

local OpeningService = {}

-- (player, side) once a prologue is through (mission 2, Safehouse, hooks in here in lore step 5)
OpeningService.Finished = Signal.new()

local O = Config.Story.opening
local CODE = OpeningPlan.CODE
local TAG = -7000 -- robots of the prologue (never an incident's)
-- the prologue never defeats its hero: from the ceremony on (city robots near the plaza can still pick a hero
-- in a scene as a target), and the fight and swarm read lowHealth above it
local FLOOR = O.fight.lowHealth * 0.6

type Run = {
	player: Player,
	hero: any,
	route: OpeningPlan.Route,
	lane: OpeningPlan.Lane?,
	step: string,
	stepAt: number,
	startedAt: number,
	side: string,
	replay: boolean,
	hold: boolean, -- a returning account's ceremony waits for the main menu's pick
	enemies: { [number]: boolean },
	fakeId: number?,
	hop: number,
	fired: number, -- when the spark fired (0: not yet)
	fell: { [number]: boolean }, -- the tunnel's slabs that came down
	rewarded: boolean,
}

local runs: { [Player]: Run } = {}
local laneOf: { [number]: Run } = {}
local subway: Model? = nil

local function v3(t: { number }, up: number?): Vector3
	return Vector3.new(t[1], t[2] + (up or 0), t[3])
end

-- The subway pocket, built once on first use (greybox, PLACEHOLDER ART like every pocket)
local function buildSubway()
	if subway then
		return
	end
	local l = PocketLayout.build(Config, PocketLayout.subwayIndex(Config), "subway")
	local m = Instance.new("Model")
	m.Name = "PrologueSubway"
	for _, b in l.boxes do
		local p = CityBuilder.part(b)
		if b.tag == "pocketWall" then
			p.Transparency = 0.85
			p.CastShadow = false
		end
		p.Parent = m
	end
	m.Parent = workspace
	subway = m
end

local function claimLane(r: Run): OpeningPlan.Lane?
	for i = 1, O.subway.lanes do
		if not laneOf[i] then
			laneOf[i] = r
			buildSubway()
			return OpeningPlan.lane(Config, i)
		end
	end
	return nil -- every lane busy: the fight happens by the subway steps instead
end

local function freeLane(r: Run)
	local lane = r.lane
	if lane and laneOf[lane.index] == r then
		laneOf[lane.index] = nil
	end
end

-- A returning account (another hero on it already did the opening) may skip: Create First on the main menu
-- (spec: Main menu "Create First skips the cinematic for returning players"), and SKIP on the camera beats
function OpeningService.returning(player: Player): boolean
	local profile = DataService.get(player)
	if not profile or type(profile.characters) ~= "table" then
		return false
	end
	local mine = ProfileSchema.active(profile)
	for _, c in profile.characters do
		if c ~= mine and type(c) == "table" and type(c.story) == "table" and c.story.opening == 1 then
			return true
		end
	end
	return false
end

local function target(r: Run): { number }?
	local s, route = r.step, r.route
	if s == "run" then
		return route.spark
	elseif s == "spark" then
		return route.kid
	elseif s == "leap" then
		return route.roofs[2]
	elseif s == "chase" then
		return route.roofs[r.hop]
	elseif s == "descend" then
		return route.entrance
	elseif s == "tunnel" and r.lane then
		return r.lane.fight
	end
	return nil
end

local function send(r: Run)
	local route = r.route
	local code = CODE[r.step]
	local now = os.clock()
	Net.fire("OpeningState", r.player, {
		step = code,
		t = if r.hold then 0 else now - r.stepAt,
		hold = r.hold or nil,
		replay = r.replay or nil,
		-- lore step 7: this camera beat was seen on this save before (SKIP shows from the second time)
		seen = (OpeningPlan.CUT[r.step] and CinemaService.seenScene(r.player, r.step)) or nil,
		createFirst = if r.hold then true else nil,
		target = target(r),
		side = r.side,
		left = math.max(0, math.ceil(r.startedAt + O.timeout - now)),
		fired = if r.fired > 0 then now - r.fired else nil,
		fake = r.fakeId,
		hop = r.hop,
		-- the scene (the client builds the props, crowd and camera from these)
		hall = route.hall,
		face = route.face,
		stage = route.stage,
		crane = route.crane,
		fakes = route.fakes,
		scanner = route.scanner,
		crowd = if code <= CODE.spark then route.crowd else nil,
		start = route.start,
		spark = route.spark,
		kid = route.kid,
		roofs = route.roofs,
		entrance = route.entrance,
		billboard = route.billboard,
		lane = r.lane,
	})
end

local function clearEnemies(r: Run)
	for id in r.enemies do
		EnemyService.remove(id)
	end
	table.clear(r.enemies)
	r.fakeId = nil
end

local function spawn(r: Run, kind: string, pos: Vector3, scripted: boolean?): number?
	local id = EnemyService.spawnAt(kind, pos, r.hero.level, TAG, scripted)
	if id then
		r.enemies[id] = true
	end
	return id
end

-- Put the hero where a beat starts when it is not there already (a stuck beat moving on, a dev jump, a cut)
local function placeFor(r: Run, step: string, force: boolean?)
	local p = OpeningPlan.startPoint(r.route, r.lane, step)
	local pos = HeroService.position(r.hero)
	if not force and pos and (v3(p) - pos).Magnitude <= 60 then
		return
	end
	local at = v3(p, 3)
	local look: Vector3? = nil
	local route = r.route
	if step == "ceremony" or step == "scan" or step == "run" then
		look = v3(route.stage)
	elseif step == "leap" then
		look = v3(route.roofs[2])
	elseif (step == "tunnel" or step == "fight") and r.lane then
		look = at + Vector3.new(0, 0, -10)
	end
	local cf = if look and (Vector3.new(look.X, at.Y, look.Z) - at).Magnitude > 0.5
		then CFrame.lookAt(at, Vector3.new(look.X, at.Y, look.Z))
		else CFrame.new(at)
	task.spawn(SafehouseService.place, r.hero, cf)
end

-- The funnel steps (Opening funnel, AnalyticsSchema): the spark seen, the Spark fired, the fake unmasked
local function track(r: Run, name: string)
	Analytics.event(r.player, name, Analytics.since(r.player))
	Analytics.step(r.player, "Opening", name)
end

-- The rewards (the old opening's Suit Up): level 3, Flight, the Skill Point, mission 1's first clear
local function pay(player: Player, hero: any, side: string)
	local story = StoryService.story(player)
	if not story then
		return
	end
	StoryService.setSide(player, if side == "villain" then "villain" else "hero")
	story.opening = 1
	Analytics.step(player, "Opening", "opening_done")
	if StoryPlan.clear(story, 1) then
		local need = Progress.totalTo(Config, O.reward.level)
			- (Progress.totalTo(Config, hero.level) + hero.xp)
		if need > 0 then
			EconomyService.addRenown(player, need)
		end
		StoryService.addSkillPoints(player, Config.Story.missions[1].skillPoints or O.reward.skillPoints)
	end
	StoryService.changed(player)
	DataService.saveSoon(player)
end

local function reward(r: Run)
	if not r.rewarded then
		r.rewarded = true
		pay(r.player, r.hero, r.side)
	end
end

local setStep: (Run, string) -> ()

local function fire(r: Run)
	if r.fired > 0 then
		return
	end
	r.fired = os.clock()
	Analytics.event(
		r.player,
		"choice_made",
		Analytics.since(r.player),
		{ "prologue", OpeningPlan.sparkBeat(r.side) }
	)
	track(r, "first_spark")
	send(r)
end

local function enter(r: Run, step: string)
	local route = r.route
	if step == "ceremony" then
		GearService.setStreet(r.player, true) -- CreatorService.streetOutfit's own call (it requires this module)
		placeFor(r, step, true)
	elseif step == "run" then
		track(r, "spark_detected")
	elseif step == "leap" then
		placeFor(r, step, true)
		-- Skylance drops in behind the hero: it trails one roof back for the chase (scripted, harmless)
		if not r.fakeId then
			local behind = v3(route.roofs[1])
				+ (v3(route.roofs[1]) - v3(route.roofs[2])).Unit * O.chase.behind
			r.fakeId = spawn(r, O.chase.fake, behind, true)
			if r.fakeId then
				EnemyService.tune(r.fakeId, { dmgMult = 0 })
			end
		end
	elseif step == "chase" then
		r.hop = 3
	elseif step == "suit" then
		GearService.setStreet(r.player, false) -- the designed look comes back; the client reveals it piece by piece
	elseif step == "tunnel" then
		clearEnemies(r)
		r.lane = r.lane or claimLane(r)
		if not r.lane then
			setStep(r, "fight")
			return
		end
		table.clear(r.fell)
		placeFor(r, step, true)
	elseif step == "fight" then
		GearService.setStreet(r.player, false)
		clearEnemies(r)
		placeFor(r, step)
		local at = v3(OpeningPlan.startPoint(route, r.lane, "fight"), 0) + Vector3.new(0, 0, -14)
		local id = spawn(r, O.fight.fake, at)
		if id then
			EnemyService.tune(id, { hpMult = O.fight.hpMult, dmgMult = O.fight.dmg })
			r.fakeId = id
		end
		r.hero.floor = FLOOR -- the prologue never defeats its hero
	elseif step == "swarm" then
		track(r, "fake_cracked")
		local fake = r.fakeId and EnemyService.get(r.fakeId)
		if fake and fake.alive then
			fake.scripted = true -- the cracked fake stands and stares; the swarm comes in
			fake.dmgMult = 0
		end
		local pos = HeroService.position(r.hero) or v3(OpeningPlan.startPoint(route, r.lane, step))
		local S = O.swarm
		for i = 1, S.count do
			local a = i / S.count * math.pi * 2
			local id = spawn(r, S.kind, pos + Vector3.new(math.cos(a) * S.ring, 0, math.sin(a) * S.ring))
			if id then
				EnemyService.tune(id, { dmgMult = S.dmg })
			end
		end
		r.hero.floor = FLOOR
	elseif step == "rescue" then
		-- Lodestar lands: every robot is blown back, then gone
		local pos = HeroService.position(r.hero)
		for id in r.enemies do
			local e = EnemyService.get(id)
			if e and e.alive and pos then
				local d = Vector3.new(e.x, 0, e.z) - Vector3.new(pos.X, 0, pos.Z)
				EnemyService.knock(id, if d.Magnitude > 0.1 then d.Unit else Vector3.new(1, 0, 0), 40)
			end
		end
		task.delay(1.2, function()
			if runs[r.player] == r then
				clearEnemies(r)
			end
		end)
		r.hero.health = r.hero.maxHealth
		HeroService.refresh(r.hero)
	elseif step == "title" then
		clearEnemies(r)
		GearService.setStreet(r.player, false)
		freeLane(r)
		reward(r)
		placeFor(r, step, true)
	end
end

setStep = function(r: Run, step: string)
	-- a camera beat is seen once the prologue moves off it (start() enters the ceremony on itself: not seen)
	if MissionRules.markSeen(r.step, step, OpeningPlan.CUT[r.step] == true, r.hold) then
		CinemaService.markScene(r.player, r.step) -- lore step 7: a camera beat seen once may be skipped later
	end
	r.step = step
	r.stepAt = os.clock()
	enter(r, step)
	if runs[r.player] == r and r.step == step then
		send(r)
	end
end

function OpeningService.finish(player: Player)
	local r = runs[player]
	if not r then
		return
	end
	if OpeningPlan.CUT[r.step] and not r.hold then
		CinemaService.markScene(player, r.step)
	end
	clearEnemies(r)
	freeLane(r)
	StoryService.cancelAsk(player)
	reward(r)
	GearService.setStreet(player, false)
	runs[player] = nil
	r.hero.scene = nil
	r.hero.floor = nil
	Net.fire("OpeningState", player, { step = 0, next = O.next })
	OpeningService.Finished:Fire(player, r.side)
end

-- Dev: end a running prologue with no rewards (a fresh start as the other side)
function OpeningService.stop(player: Player)
	local r = runs[player]
	if not r then
		return
	end
	clearEnemies(r)
	freeLane(r)
	GearService.setStreet(player, false)
	runs[player] = nil
	r.hero.scene = nil
	r.hero.floor = nil
	Net.fire("OpeningState", player, { step = 0 })
end

function OpeningService.running(player: Player): boolean
	return runs[player] ~= nil
end

-- Start the prologue for a character made in the creator (force: the dev command, a replay)
function OpeningService.start(player: Player, force: boolean?): boolean
	local hero = HeroService.get(player)
	local story = StoryService.story(player)
	if not hero or not story or runs[player] then
		return false
	end
	if story.opening ~= 0 and not force then
		return false
	end
	local rng = Rng.new(Rng.hash(player.UserId % 100000, os.time() % 100000))
	local route = OpeningPlan.route(Config, CityBuilder.world, rng)
	if not route then
		warn("[Capeline] no prologue route; finishing it at once")
		pay(player, hero, StoryService.side(player))
		return false
	end
	local returning = OpeningService.returning(player)
	local r: Run = {
		player = player,
		hero = hero,
		route = route,
		lane = nil,
		step = "ceremony",
		stepAt = os.clock(),
		startedAt = os.clock(),
		side = StoryService.side(player),
		replay = force == true or returning,
		hold = returning and not force,
		enemies = {},
		fakeId = nil,
		hop = 3,
		fired = 0,
		fell = {},
		rewarded = false,
	}
	runs[player] = r
	hero.scene = "opening"
	hero.floor = FLOOR -- OpeningService.finish (or stop) clears it
	task.spawn(function()
		local t0 = os.clock()
		while not player.Character and os.clock() - t0 < 10 do
			task.wait(0.2)
		end
		if runs[player] == r then
			setStep(r, "ceremony")
		end
	end)
	return true
end

-- Dev and testing: jump to a beat
function OpeningService.jump(player: Player, step: string)
	local r = runs[player]
	if r and CODE[step] then
		r.hold = false
		if CODE[step] <= CODE.spark then
			GearService.setStreet(player, true)
		end
		placeFor(r, step, true)
		setStep(r, step)
	end
end

local function moveFake(r: Run, pos: Vector3, dt: number)
	local id = r.fakeId
	local e = id and EnemyService.get(id)
	if not id or not e or not e.alive then
		return
	end
	-- one roof back from the hero's next roof, closing in at its own pace
	local back = r.route.roofs[math.max(1, (if r.step == "leap" then 2 else r.hop) - 1)]
	local goal = v3(back)
	if r.step == "descend" or r.step == "suit" then
		goal = goal:Lerp(pos, 0.4)
	end
	local cur = Vector3.new(e.x, goal.Y, e.z)
	local d = goal - cur
	local stepLen = math.min(d.Magnitude, 46 * dt)
	EnemyService.place(id, if d.Magnitude > 0.1 then cur + d.Unit * stepLen else goal)
end

local function tunnelTick(r: Run, pos: Vector3, now: number)
	local lane = r.lane
	if not lane then
		return
	end
	local S = O.subway
	for k, c in lane.collapses do
		if not r.fell[k] and now - r.stepAt >= c.t then
			r.fell[k] = true
			if math.abs(pos.Z - c.z) <= S.slab / 2 + 3 and math.abs(pos.X - lane.x) <= S.width / 2 + 2 then
				-- under the slab: knocked back toward the steps (cartoon; no damage)
				local back = CFrame.lookAt(
					Vector3.new(lane.x, lane.floorY + 3, c.z + S.slab / 2 + S.push),
					Vector3.new(lane.x, lane.floorY + 3, c.z)
				)
				task.spawn(SafehouseService.place, r.hero, back)
			end
		end
	end
	if pos.Z <= lane.z1 - 4 then
		setStep(r, "fight")
	end
end

local function step(r: Run, now: number, dt: number)
	local hero = r.hero
	local pos = HeroService.position(hero)
	if not pos or not hero.alive then
		return
	end
	local s = r.step
	if r.hold then
		r.stepAt = now
		return
	end
	if now - r.startedAt > O.timeout and CODE[s] < CODE.title then
		setStep(r, "title")
		return
	end
	if now - r.stepAt > OpeningPlan.limit(Config, s) then
		local nxt = OpeningPlan.next(s)
		if nxt then
			if not OpeningPlan.timed(Config, s) then
				placeFor(r, nxt)
			end
			setStep(r, nxt)
		else
			OpeningService.finish(r.player)
		end
		return
	end
	local route = r.route
	if s == "leap" or s == "chase" or s == "suit" or s == "descend" then
		moveFake(r, pos, dt)
	end
	if s == "run" then
		if OpeningPlan.at(Config, route.spark, pos.X, pos.Y, pos.Z, O.spark.reach) then
			setStep(r, "spark")
		end
	elseif s == "spark" then
		if r.fired == 0 and now - r.stepAt >= O.spark.auto then
			fire(r)
		elseif r.fired > 0 and now - r.fired >= O.spark.after then
			setStep(r, "leap")
		end
	elseif s == "leap" then
		if OpeningPlan.at(Config, route.roofs[2], pos.X, pos.Y, pos.Z, 30) then
			setStep(r, "chase")
		end
	elseif s == "chase" then
		if OpeningPlan.at(Config, route.roofs[r.hop], pos.X, pos.Y, pos.Z, 30) then
			if r.hop >= #route.roofs then
				setStep(r, "suit")
			else
				r.hop += 1
				send(r)
			end
		end
	elseif s == "descend" then
		local e = route.entrance
		if
			(Vector3.new(e[1], 0, e[3]) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= 24
			and pos.Y <= e[2] + 30
		then
			setStep(r, "tunnel")
		end
	elseif s == "tunnel" then
		tunnelTick(r, pos, now)
	elseif s == "fight" then
		local fake = r.fakeId and EnemyService.get(r.fakeId)
		local cracked = not fake
			or not fake.alive
			or FakeRules.cracked(Config, fake.health / math.max(1, fake.maxHealth))
		if cracked or hero.health <= hero.maxHealth * O.fight.lowHealth then
			setStep(r, "swarm")
		end
	elseif s == "swarm" then
		if now - r.stepAt >= 4 and hero.health <= hero.maxHealth * O.swarm.lowHealth then
			setStep(r, "rescue")
		end
	end
end

local function onAct(player: Player, act: number)
	local r = runs[player]
	if not r then
		return
	end
	if act == 1 and r.step == "spark" then
		local pos = HeroService.position(r.hero)
		if pos and (v3(r.route.kid) - pos).Magnitude <= O.spark.reach + 12 then
			fire(r)
		end
	elseif
		act == 2
		and not r.hold
		and (
			OpeningPlan.canSkip(r.step, r.replay)
			or OpeningPlan.canSkip(r.step, CinemaService.seenScene(player, r.step)) -- lore step 7: seen before
		)
	then
		local nxt = OpeningPlan.next(r.step)
		if nxt then
			setStep(r, nxt)
		else
			OpeningService.finish(player)
		end
	elseif act == 3 and r.hold then
		-- Create First (a returning account): straight to the city with the rewards
		OpeningService.finish(player)
	elseif act == 4 and r.hold then
		-- PLAY THE PROLOGUE: the ceremony starts now, and so does the whole prologue's timeout
		r.hold = false
		r.stepAt = os.clock()
		r.startedAt = r.stepAt
		send(r)
	end
end

local function maybeStart(player: Player)
	local hero = HeroService.get(player)
	-- creator first (lore step 2): a new character's prologue waits for its creator's Done; a save that stopped
	-- mid-opening (any version) starts the prologue again from its first beat
	if hero and hero.loaded and OpeningPlan.due(StoryService.char(player)) and not runs[player] then
		OpeningService.start(player)
	end
end

function OpeningService.init()
	Net.on("OpeningAct", onAct)
	DataService.Loaded:Connect(function(player)
		task.delay(1, maybeStart, player)
	end)
	-- a defeated hero comes back where its beat starts
	local previous = SafehouseService.spawnOverride
	SafehouseService.spawnOverride = function(hero)
		local r = hero.player and runs[hero.player]
		if r then
			return CFrame.new(v3(OpeningPlan.startPoint(r.route, r.lane, r.step), 4))
		end
		return if previous then previous(hero) else nil
	end
	EnemyService.Killed:Connect(function(_, _, _, enemyId)
		for _, r in runs do
			if r.enemies[enemyId] then
				r.enemies[enemyId] = nil
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local r = runs[player]
		if r then
			clearEnemies(r)
			freeLane(r)
			runs[player] = nil
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("OpeningService", function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		local d = acc
		acc = 0
		local now = os.clock()
		for _, r in runs do
			step(r, now, d)
		end
	end))
end

return OpeningService
