-- SideQuestService: the side quest framework in the world (nate's lore, build plan step 10; rules in
-- Shared.SideQuestPlan, data in Config.SideQuests). Replaces the 8 retired arcs and their NPCs.
-- * Givers stand where Config.SideQuests puts them with a Talk prompt (the server's own range check, so no
--   remote): a talk resumes the chain you have in progress with them, else offers the next one you may take,
--   and counts for a "talk" step aimed at them. The Journal accepts, resumes and abandons too (SideQuestAct),
--   and the map shows the givers (the ReplicatedStorage attribute SideQuestGivers).
-- * Only the tracked chain's step is built (story.pinned), as a group: squadmates on the same chain and step
--   near its site share it, each side present with its own goal (one shared goal on a shared step); the step
--   is done when every side present has finished, then each member's save moves on and pays.
-- * Step kinds: talk, fight, incident (real incidents; a named one is started near the group), chase,
--   deliver, fetch, hold, escort, carry, race, reach, find, photo, beacon, pocket (a mission-shaped run in a
--   mission pocket through MissionService.enterCustom: stand in the ring) and finale (the mini villain: a
--   boss-lite elite or famous fake, its name card on the device).
-- * Save: lore step 10's `sq` (ProfileSchema migration 11); settle() pays what the retired arcs left, once.
-- PLACEHOLDER ART: givers are R15 people in plain colours; crates, rings and the motorcade are plain parts.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local SideQuestPlan = require(Shared:WaitForChild("SideQuestPlan"))
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local IncidentService = require(script.Parent.IncidentService)
local MissionService = require(script.Parent.MissionService)
local SiteKit = require(script.Parent.SiteKit)
local SquadService = require(script.Parent.SquadService)
local StoryService = require(script.Parent.StoryService)

local SideQuestService = {}

local SQ = Config.SideQuests
local IC = Config.Incidents
local STAKE = Config.Contracts.types.Stakeout
local TAG = -9100
local rng = Rng.new(Rng.hash(os.time(), 71))

type Goal = {
	key: string,
	st: any,
	have: number,
	need: number,
	things: { any },
	enemies: { [number]: boolean },
	target: Vector3?,
	area: { number }?,
	startedAt: number,
	deadline: number?,
	rings: { Vector3 }?,
	truck: { model: Model, path: { { number } }, at: number, length: number }?,
	chase: { id: number, path: { { number } }, leg: number, at: number, speed: number }?,
	photos: { [number]: number }?,
	boss: number?,
	bossAt: Vector3?,
	pocketAt: number?, -- os.clock() of the last pocket try (a short wait between tries)
	done: boolean,
}

type Group = {
	plan: SideQuestPlan.Group,
	chain: any,
	idx: number,
	step: any,
	members: { [Player]: string }, -- player -> side
	goals: { [string]: Goal },
	home: Vector3,
	level: number,
	test: number?, -- Dev: a kind test (Config.SideQuests.devKinds index); nothing is saved
	finished: boolean,
}

local givers: { [string]: { pos: Vector3 } } = {}
local groups: { [Group]: boolean } = {}
local memberOf: { [Player]: Group } = {}
local waiting: { [Player]: number } = {} -- the next step builds after SQ.gap

local function v3(t: { number }, up: number?): Vector3
	return Vector3.new(t[1], t[2] + (up or 0), t[3])
end

local function gy(): number
	return Config.City.ground.y
end

local function devOn(): boolean
	return StoryService.devChains()
end

---------------------------------------------------------------------------
-- Givers
---------------------------------------------------------------------------

local function anchor(g: any): (number, number)
	local world = CityBuilder.world
	local x, z
	if g.anchor == "plaza" then
		x, z = OpeningPlan.plaza(world)
	elseif g.anchor == "hq" then
		local s = world.safehouses[Config.World.safehouse.homeSafehouse]
		x, z = s.x, s.z + 30
	else
		local d = Config.City.districts[g.anchor]
		x, z = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
	end
	return x + (g.dx or 0), z + (g.dz or 0)
end

-- A giver: a person on the heroes' blocky R15 rig in the giver's colour, a marker over the head
local npcLayout = RigMath.layout(Config.HeroRig, nil, 1)
local function npcModel(name: string, color: { number }, pos: Vector3): (Model, BasePart)
	local rig = NpcRig.person(
		npcLayout,
		"Giver" .. name,
		Color3.fromRGB(color[1], color[2], color[3]),
		Color3.fromRGB(50, 50, 60),
		Color3.fromRGB(235, 200, 160),
		Color3.fromRGB(70, 46, 30)
	)
	local m = rig.model
	local holder = SiteKit.model("Giver" .. name) -- where SiteKit keeps site models
	m.Parent = holder.Parent
	holder:Destroy()
	NpcRig.place(rig, CFrame.new(pos))
	local head = rig.parts.Head
	local mark = SiteKit.part(
		m,
		Vector3.new(0.8, 1.6, 0.8),
		CFrame.new(pos + Vector3.new(0, 8, 0)),
		Color3.fromRGB(255, 210, 60),
		Enum.Material.Neon
	)
	mark.Name = "Marker"
	mark.CFrame = head.CFrame * CFrame.new(0, 2.6, 0)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(160, 26)
	tag.StudsOffset = Vector3.new(0, 4.4, 0)
	tag.MaxDistance = 80
	tag.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = name -- a fixed giver name from Config.SideQuests
	label.Parent = tag
	tag.Parent = head
	return m, rig.root
end

---------------------------------------------------------------------------
-- Building a goal
---------------------------------------------------------------------------

local function streetSpot(at: Vector3, range: { number }): Vector3
	local s = IncidentSpots.find(Config, CityBuilder.world, "street", at.X, at.Z, range[1], range[2], rng)
	if s then
		return Vector3.new(s.x, s.y, s.z)
	end
	local x, y, z = IncidentSpots.groundNear(Config, CityBuilder.world, at.X, at.Z, range[2], rng)
	return Vector3.new(x, y, z)
end

local function roofSpot(at: Vector3, minH: number, range: { number }): Vector3?
	local best = {}
	for _, b in CityBuilder.world.buildings do
		local d = math.sqrt((b.x - at.X) ^ 2 + (b.z - at.Z) ^ 2)
		if d >= range[1] and d <= range[2] and b.top - gy() >= minH and b.top - gy() <= minH + 80 then
			table.insert(best, b)
		end
	end
	if #best == 0 then
		return nil
	end
	local b = best[rng:int(1, #best)]
	return Vector3.new(b.x, b.top + 1.5, b.z)
end

-- The players working on a goal (by its key)
local function membersOf(g: Group, key: string): { Player }
	local out = {}
	for p, side in g.members do
		if SideQuestPlan.keyFor(g.step, side) == key then
			table.insert(out, p)
		end
	end
	return out
end

local function heroesOf(g: Group, key: string): { any }
	local out = {}
	for _, p in membersOf(g, key) do
		local h = HeroService.get(p)
		if h then
			table.insert(out, h)
		end
	end
	return out
end

local function squad(goal: Goal, level: number, list: { any }, at: Vector3): number
	local n = 0
	for _, row in list do
		for _, id in SiteKit.squad({ { kind = row[1], n = row[2] } }, at, level, TAG, 16) do
			goal.enemies[id] = true
			n += 1
		end
	end
	return n
end

local function setNeed(g: Group, goal: Goal, need: number)
	goal.need = math.max(1, need)
	local s = g.plan.sides[goal.key]
	if s then
		s.need = goal.need
	end
end

local setHave: (g: Group, goal: Goal, have: number) -> ()

local function build(g: Group, key: string, st: any): Goal
	local home = g.home
	local goal: Goal = {
		key = key,
		st = st,
		have = 0,
		need = SideQuestPlan.need(st),
		things = {},
		enemies = {},
		target = nil,
		area = nil,
		startedAt = os.clock(),
		deadline = nil,
		rings = nil,
		truck = nil,
		chase = nil,
		photos = nil,
		boss = nil,
		bossAt = nil,
		pocketAt = nil,
		done = false,
	}
	local k = st.kind
	local function mine(h: any): boolean
		return table.find(heroesOf(g, key), h) ~= nil
	end
	if k == "talk" then
		local giver = givers[st.giver or g.chain.giver]
		goal.target = if giver then giver.pos else home
	elseif k == "fight" then
		local at = if st.home then home + Vector3.new(0, 0, 20) else streetSpot(home, st.range or { 60, 150 })
		setNeed(g, goal, squad(goal, g.level, st.squads, at))
		goal.target = at
	elseif k == "incident" then
		if st.template then
			-- a named incident starts near the first member; any clear of that template counts
			local h = heroesOf(g, key)[1]
			if h then
				IncidentService.force(h, st.template)
			end
		end
	elseif k == "fetch" then
		for i = 1, st.count or 1 do
			local at = streetSpot(home, st.range)
			table.insert(
				goal.things,
				SiteKit.pickup(at, 8, Color3.fromRGB(120, 220, 255), function()
					setHave(g, goal, goal.have + 1)
				end, nil, mine)
			)
			if i == 1 then
				goal.target = at
				if st.guards then
					squad(goal, g.level, { st.guards }, at)
				end
			end
		end
	elseif k == "hold" then
		local at = home
		if st.high then
			at = roofSpot(home, 30, { 40, 200 }) or home
		elseif not st.home then
			at = streetSpot(home, { 40, 120 })
		end
		goal.target = at
		table.insert(goal.things, SiteKit.ring(at, st.radius))
	elseif k == "escort" then
		local path = IncidentSpots.streetPath(Config, CityBuilder.world, home.X, home.Z, 8, st.goal / 7, rng)
		local truck = SiteKit.prop("Motorcade", function(m)
			SiteKit.part(m, Vector3.new(7, 4, 14), CFrame.new(0, 2.5, 0), Color3.fromRGB(30, 30, 40))
			SiteKit.part(m, Vector3.new(6.6, 2.4, 6), CFrame.new(0, 5.6, -2), Color3.fromRGB(90, 70, 160))
		end)
		local length = 0
		for i = 2, #path do
			length += (v3(path[i]) - v3(path[i - 1])).Magnitude
		end
		setNeed(g, goal, math.min(st.goal, math.max(30, math.floor(length))))
		goal.truck = { model = truck, path = path, at = 0, length = length }
		SiteKit.place(truck, v3(path[1]))
		table.insert(goal.things, truck)
		goal.target = v3(path[1])
	elseif k == "carry" then
		local padAt = roofSpot(home, 20, st.range) or streetSpot(home, st.range)
		local pad = SiteKit.pad(padAt)
		table.insert(goal.things, pad)
		table.insert(
			goal.things,
			SiteKit.citizen(home + Vector3.new(4, 1, 0), {
				pads = { pad },
				who = mine,
				onSafe = function()
					setHave(g, goal, goal.need)
				end,
			})
		)
		goal.target = padAt
	elseif k == "race" then
		local rings = {}
		local p = home + Vector3.new(0, 30, 0)
		local a = rng:range(0, math.pi * 2)
		for i = 1, st.checkpoints do
			a += rng:range(-0.6, 0.6)
			p = Vector3.new(p.X + math.cos(a) * st.gap, gy() + 30 + (i % 3) * 18, p.Z + math.sin(a) * st.gap)
			table.insert(rings, p)
			table.insert(goal.things, SiteKit.ring(p, 10, Color3.fromRGB(90, 200, 255)))
		end
		goal.rings = rings
		goal.target = rings[1]
	elseif k == "reach" then
		goal.target = roofSpot(home, st.high or 40, st.range or { 80, 200 })
			or roofSpot(home, 20, { 40, 300 })
			or home
	elseif k == "deliver" then
		local at = streetSpot(home, st.range)
		table.insert(goal.things, SiteKit.pad(at))
		goal.target = at
	elseif k == "find" then
		local at = streetSpot(home, st.range)
		local off = rng:range(0, 50)
		local a = rng:range(0, math.pi * 2)
		goal.area = { at.X + math.cos(a) * off, at.Z + math.sin(a) * off, 70 }
		goal.target = at -- not sent: the heroes only see the search circle
		local prop = SiteKit.prop(if st.witness then "Witness" else "LostCrate", function(m)
			if st.witness then
				local rig = NpcRig.person(
					npcLayout,
					"Witness",
					Color3.fromRGB(200, 160, 90),
					Color3.fromRGB(60, 64, 80),
					Color3.fromRGB(235, 200, 160),
					Color3.fromRGB(30, 26, 24)
				)
				NpcRig.place(rig, CFrame.new())
				rig.model.Parent = m
			else
				SiteKit.part(m, Vector3.new(4, 3, 4), CFrame.new(0, 1.5, 0), Color3.fromRGB(150, 110, 60))
			end
		end)
		SiteKit.place(prop, at)
		table.insert(goal.things, prop)
	elseif k == "chase" then
		local spot = IncidentSpots.find(
			Config,
			CityBuilder.world,
			"roof",
			home.X,
			home.Z,
			60,
			300,
			rng,
			{ hops = st.hops }
		)
		local path = spot and spot.points
			or IncidentSpots.streetPath(Config, CityBuilder.world, home.X, home.Z, st.hops, 45, rng)
		local id = EnemyService.spawnAt(st.enemy, v3(path[1], 2), g.level, TAG, true)
		if id then
			goal.enemies[id] = true
			goal.chase = { id = id, path = path, leg = 1, at = 0, speed = st.speed }
		end
	elseif k == "beacon" then
		local best, bestD = nil, math.huge
		for _, b in CityBuilder.world.beacons do
			local d = (Vector3.new(b.x, b.y, b.z) - home).Magnitude
			if d < bestD then
				best, bestD = b, d
			end
		end
		if best then
			goal.target = Vector3.new(best.x, best.y, best.z)
			table.insert(goal.things, SiteKit.ring(goal.target :: Vector3, 10, Color3.fromRGB(110, 160, 255)))
		end
	elseif k == "photo" then
		local at = streetSpot(home, st.range)
		goal.photos = {}
		for _ = 1, st.count + 1 do
			local a = rng:range(0, math.pi * 2)
			local id = EnemyService.spawnAt(
				"SneakBot",
				at + Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25),
				g.level,
				TAG
			)
			if id then
				goal.enemies[id] = true
				local photos = goal.photos :: { [number]: number }
				photos[id] = 0
			end
		end
		goal.target = at
	elseif k == "pocket" then
		-- the way in: a ring by the giver; standing in it takes the group's side into a mission pocket
		local at = home + Vector3.new(8, 0, 8)
		goal.target = at
		table.insert(goal.things, SiteKit.ring(at, 10, Color3.fromRGB(170, 110, 255)))
	elseif k == "finale" then
		local at = streetSpot(home, st.range or { 80, 180 })
		goal.bossAt = at
		goal.target = at
		if st.adds then
			squad(goal, g.level, st.adds, at)
		end
	end
	return goal
end

local function clearGoal(goal: Goal)
	for id in goal.enemies do
		EnemyService.remove(id)
	end
	table.clear(goal.enemies)
	if goal.boss then
		EnemyService.remove(goal.boss)
		goal.boss = nil
	end
	SiteKit.clear(goal.things)
end

-- The finale's mini villain (spawned, and spawned again if it is gone without being beaten)
local function spawnBoss(g: Group, goal: Goal)
	local st = goal.st
	local id = EnemyService.spawnAt(st.enemy, goal.bossAt or g.home, g.level, TAG)
	if id then
		EnemyService.tune(id, { hpMult = math.clamp(st.hpMult, SQ.finale.hpMult[1], SQ.finale.hpMult[2]) })
		goal.boss = id
	end
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------

local function stateFor(g: Group?, player: Player): { [string]: any }
	if not g then
		return { bit = 0 }
	end
	local side = g.members[player]
	local key = side and SideQuestPlan.keyFor(g.step, side)
	local goal = key and g.goals[key]
	if not goal then
		return { bit = 0 }
	end
	local t = if goal.st.kind == "find" then nil else goal.target
	local card = nil
	if goal.st.kind == "finale" then
		local v = if g.test then { name = "KIND TEST", title = "FINALE" } else g.chain.villain
		card = { name = v.name, title = v.title }
	end
	return {
		bit = g.chain.bit,
		test = g.test,
		step = g.idx,
		steps = #g.chain.steps,
		have = math.floor(goal.have * 10) / 10,
		need = goal.need,
		wait = goal.done or nil,
		left = if goal.deadline then math.max(0, math.ceil(goal.deadline - os.clock())) else nil,
		target = if t and not goal.done then { t.X, t.Y, t.Z } else nil,
		area = if goal.done then nil else goal.area,
		card = card,
	}
end

local function clearGroup(g: Group)
	for _, goal in g.goals do
		clearGoal(goal)
	end
	table.clear(g.goals)
	groups[g] = nil
end

local function leave(player: Player)
	local g = memberOf[player]
	if not g then
		return
	end
	memberOf[player] = nil
	g.members[player] = nil
	local dropped, empty = SideQuestPlan.leave(g.plan, player)
	if dropped and g.goals[dropped] then
		clearGoal(g.goals[dropped])
		g.goals[dropped] = nil
	end
	if empty then
		clearGroup(g)
	end
	Net.fire("SideQuestState", player, { bit = 0 })
end

local complete: (g: Group) -> ()

-- A goal's progress; the step is done once every side present has finished
setHave = function(g: Group, goal: Goal, have: number)
	if goal.done or g.finished then
		return
	end
	goal.have = math.clamp(have, 0, goal.need)
	if SideQuestPlan.set(g.plan, goal.key, goal.have) then
		goal.done = true
		clearGoal(goal)
		if SideQuestPlan.groupDone(g.plan) then
			complete(g)
		else
			for _, p in membersOf(g, goal.key) do
				Net.fire("Toast", p, { id = "sqWait" })
			end
		end
	end
end

local function join(g: Group, player: Player, side: string)
	local key, fresh = SideQuestPlan.join(g.plan, g.step, player, side)
	g.members[player] = side
	memberOf[player] = g
	if fresh then
		local st = SideQuestPlan.goal(g.step, side)
		g.goals[key] = build(g, key, st)
		if st.kind == "finale" then
			spawnBoss(g, g.goals[key])
		end
	end
	-- the step's lines and scene play on the device (fixed text from Config.SideQuests)
	if not g.test then
		Net.fire("SideQuestTalk", player, { bit = g.chain.bit, kind = "step", step = g.idx })
	end
	Net.fire("SideQuestState", player, stateFor(g, player))
end

local function newGroup(chain: any, idx: number, hero: any, test: number?): Group
	local giver = givers[chain.giver]
	local home = if giver then giver.pos else (HeroService.position(hero) or Vector3.zero)
	local step = chain.steps[idx]
	local g: Group = {
		plan = SideQuestPlan.newGroup(chain.id, idx),
		chain = chain,
		idx = idx,
		step = step,
		members = {},
		goals = {},
		home = home,
		level = hero.level,
		test = test,
		finished = false,
	}
	groups[g] = true
	return g
end

-- A squadmate's group on the same chain and step near enough to share
local function groupToJoin(player: Player, chain: any, idx: number): Group?
	local hero = HeroService.get(player)
	local pos = hero and HeroService.position(hero)
	if not pos then
		return nil
	end
	local mates = SquadService.mates(player)
	for g in groups do
		if not g.finished and not g.test and SideQuestPlan.canJoin(g.plan, chain.id, idx) then
			for p in g.members do
				if table.find(mates, p) then
					local h = HeroService.get(p)
					local at = h and HeroService.position(h)
					if at and ((at - pos).Magnitude <= SQ.coop or (g.home - pos).Magnitude <= SQ.coop) then
						return g
					end
				end
			end
		end
	end
	return nil
end

-- Each member's save moves on (only a member still on this very step), with its pay
complete = function(g: Group)
	if g.finished then
		return
	end
	g.finished = true
	local chain = g.chain
	local finale = g.idx == #chain.steps
	for player in g.members do
		memberOf[player] = nil
		Net.fire("SideQuestState", player, { bit = 0 })
		local c = StoryService.char(player)
		local hero = HeroService.get(player)
		if g.test then
			Net.fire("Toast", player, { id = "sqTest", n = g.test })
		elseif c and hero and SideQuestPlan.stepOf(c, chain) == g.idx then
			local credits, renown = SideQuestPlan.stepPay(Config, hero.level, finale)
			local res = SideQuestPlan.advance(c, chain)
			if res == "done" then
				local cc, cr = SideQuestPlan.chainPay(Config, chain, hero.level)
				local reward = SideQuestPlan.cosmetic(chain) :: { [string]: any }
				reward.credits, reward.renown = credits + cc, renown + cr
				StoryService.pay(player, reward, hero.level)
				Net.fire("Toast", player, { id = "sqDone", bit = chain.bit })
				Net.fire("SideQuestTalk", player, { bit = chain.bit, kind = "done" })
			else
				StoryService.pay(player, { credits = credits, renown = renown }, hero.level)
				Net.fire("Toast", player, { id = "sqStep", bit = chain.bit, step = g.idx + 1 })
				waiting[player] = os.clock() + SQ.gap
			end
			StoryService.changed(player)
		end
	end
	clearGroup(g)
end

-- Build (or tear down) the tracked chain's step for a player
local function refresh(player: Player)
	local c = StoryService.char(player)
	local hero = HeroService.get(player)
	local g = memberOf[player]
	local chain, idx = nil, nil
	if c then
		chain, idx = SideQuestPlan.pinned(Config, c)
	end
	if g and not g.test and (g.chain ~= chain or g.idx ~= idx) then
		leave(player)
		g = nil
	end
	if g or not chain or not idx or not hero or not hero.loaded or hero.scene then
		return
	end
	if waiting[player] and os.clock() < waiting[player] then
		return
	end
	waiting[player] = nil
	local side = StoryService.side(player)
	join(groupToJoin(player, chain, idx) or newGroup(chain, idx, hero), player, side)
end

---------------------------------------------------------------------------
-- Running the goals
---------------------------------------------------------------------------

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include
local function inView(from: Vector3, to: Vector3): boolean
	local city = Workspace:FindFirstChild("City")
	losParams.FilterDescendantsInstances = if city then { city } else {}
	return Workspace:Raycast(from, to - from, losParams) == nil
end

-- A side quest pocket run: the members of this goal near its ring go in together; the run's pay hook
-- finishes the goal for the group
local function startPocket(g: Group, goal: Goal, first: Player)
	if goal.pocketAt and os.clock() - goal.pocketAt < 5 then
		return
	end
	goal.pocketAt = os.clock()
	local hero = HeroService.get(first)
	local players = { first }
	for _, p in membersOf(g, goal.key) do
		local h = HeroService.get(p)
		local a = h and HeroService.position(h)
		if p ~= first and a and goal.target and (a - goal.target).Magnitude <= SQ.coop then
			table.insert(players, p)
		end
	end
	local st = goal.st
	local m = {
		custom = true,
		sideQuest = true,
		id = "SideQuest", -- analytics: mission_start and mission_done
		num = SQ.pocketNum,
		name = g.chain.name,
		layout = st.layout,
		minLevel = if hero then hero.level else g.level,
		minutes = st.minutes,
		steps = table.clone(st.steps),
		pay = function(_run: any, player: Player, out: { [string]: any }, _own: number)
			local pg = memberOf[player]
			local side = pg and pg.members[player]
			local pgoal = side and pg.goals[SideQuestPlan.keyFor(pg.step, side)]
			if pg and pgoal and pgoal.st.kind == "pocket" then
				setHave(pg, pgoal, pgoal.need)
			end
			return out
		end,
	}
	local ok, why = MissionService.enterCustom(players, m)
	if not ok then
		Net.fire("Toast", first, { id = "missionRefused", reason = why })
	end
end

local function tickGoal(g: Group, goal: Goal, dt: number)
	local st = goal.st
	local k = st.kind
	local list = {}
	for _, h in heroesOf(g, goal.key) do
		local p = h.alive and not h.scene and HeroService.position(h)
		if p then
			table.insert(list, { hero = h, pos = p })
		end
	end
	if #list == 0 then
		return
	end
	local function anyNear(at: Vector3, r: number): boolean
		for _, e in list do
			if (at - e.pos).Magnitude <= r then
				return true
			end
		end
		return false
	end
	local have = goal.have
	if k == "hold" or k == "beacon" then
		local r = if k == "beacon" then 12 else st.radius
		if goal.target and anyNear(goal.target, r + 3) then
			have = math.min(goal.need, have + dt)
		end
	elseif k == "escort" and goal.truck then
		local t = goal.truck
		local tp = t.model:GetPivot().Position
		if anyNear(tp, st.near) and t.at < t.length then
			t.at = math.min(t.length, t.at + st.speed * dt)
			local left = t.at
			for i = 2, #t.path do
				local a, b = v3(t.path[i - 1]), v3(t.path[i])
				local len = (b - a).Magnitude
				if left <= len then
					local p = a:Lerp(b, left / math.max(len, 0.01))
					local d = b - a
					SiteKit.place(t.model, p, math.atan2(-d.X, -d.Z))
					break
				end
				left -= len
			end
			have = math.min(goal.need, t.at)
			goal.target = t.model:GetPivot().Position
		end
	elseif k == "race" and goal.rings then
		local n = math.floor(have) + 1
		local ring = goal.rings[n]
		if ring and anyNear(ring, 14) then
			have = n
			if n == 1 then
				goal.deadline = os.clock() + st.time
			end
			goal.target = goal.rings[n + 1]
		elseif goal.deadline and os.clock() > goal.deadline and have < goal.need then
			have = 0 -- out of time: back to the first ring
			goal.deadline = nil
			goal.target = goal.rings[1]
			for _, p in membersOf(g, goal.key) do
				Net.fire("Toast", p, { id = "raceReset" })
			end
		end
	elseif k == "reach" and goal.target then
		local t = goal.target
		for _, e in list do
			local flat = (Vector3.new(t.X, 0, t.Z) - Vector3.new(e.pos.X, 0, e.pos.Z)).Magnitude
			if flat <= 20 and e.pos.Y >= t.Y - 4 then
				have = 1
			end
		end
	elseif k == "deliver" and goal.target then
		if anyNear(goal.target, IC.dropRadius + 3) then
			have = 1
		end
	elseif k == "find" and goal.target then
		if anyNear(goal.target, 16) then
			have = 1
		end
	elseif k == "chase" and goal.chase then
		local c = goal.chase
		if not EnemyService.alive(c.id) then
			have = 1
		else
			local a, b = c.path[c.leg], c.path[c.leg % #c.path + 1]
			local pa, pb = v3(a, 2), v3(b, 2)
			c.at += c.speed * dt / math.max(1, (pb - pa).Magnitude)
			if c.at >= 1 then
				c.at = 0
				c.leg = c.leg % #c.path + 1
			end
			local p = pa:Lerp(pb, c.at) + Vector3.new(0, math.sin(c.at * math.pi) * 10, 0)
			EnemyService.place(c.id, p)
			goal.target = p
		end
	elseif k == "photo" and goal.photos then
		for id, seen in goal.photos do
			local e = EnemyService.get(id)
			if e and e.alive then
				local p = Vector3.new(e.x, e.y, e.z)
				for _, h in list do
					local eye = h.pos + Vector3.new(0, 1.5, 0)
					if (p - eye).Magnitude <= STAKE.photoRange and inView(eye, p) then
						goal.photos[id] = seen + dt
						break
					end
				end
				if (goal.photos[id] or 0) >= STAKE.photoTime then
					goal.photos[id] = nil
					goal.enemies[id] = nil
					EnemyService.remove(id)
					for _, pl in membersOf(g, goal.key) do
						Net.fire("Toast", pl, { id = "photo" })
					end
					have += 1
				end
			end
		end
	elseif k == "pocket" and goal.target then
		for _, e in list do
			if (goal.target - e.pos).Magnitude <= 12 and e.hero.player then
				startPocket(g, goal, e.hero.player)
				break
			end
		end
	elseif k == "finale" then
		if goal.boss and not EnemyService.alive(goal.boss) then
			goal.boss = nil -- gone without being beaten (Killed counts a win): it comes back
			spawnBoss(g, goal)
		elseif not goal.boss then
			spawnBoss(g, goal)
		end
		local e = goal.boss and EnemyService.get(goal.boss)
		if e then
			goal.target = Vector3.new(e.x, e.y, e.z)
		end
	end
	if have ~= goal.have then
		setHave(g, goal, have)
	end
end

---------------------------------------------------------------------------
-- Talking, the Journal and the Dev panel
---------------------------------------------------------------------------

local function talk(player: Player, giverId: string)
	local hero = HeroService.get(player)
	local c = StoryService.char(player)
	if not hero or not c or not hero.loaded then
		return
	end
	-- a talk step aimed at this giver counts first
	local g = memberOf[player]
	local side = g and g.members[player]
	local goal = side and g.goals[SideQuestPlan.keyFor(g.step, side)]
	if
		g
		and goal
		and goal.st.kind == "talk"
		and not goal.done
		and (goal.st.giver or g.chain.giver) == giverId
	then
		setHave(g, goal, 1)
		return
	end
	local chain, kind =
		SideQuestPlan.talkPick(Config, c, giverId, hero.level, StoryService.side(player), devOn())
	if chain and kind == "resume" then
		SideQuestPlan.resume(c, chain)
		StoryService.changed(player)
	elseif chain and kind == "offer" then
		if SideQuestPlan.accept(Config, c, chain, hero.level, StoryService.side(player), false) then
			Net.fire("Toast", player, { id = "sqStart", bit = chain.bit })
			StoryService.changed(player)
			DataService.saveSoon(player)
		end
	end
	Net.fire("SideQuestTalk", player, { bit = if chain then chain.bit else 0, kind = kind, giver = giverId })
end

local function act(player: Player, what: number, bit: number)
	local hero = HeroService.get(player)
	local c = StoryService.char(player)
	local chain = SideQuestPlan.byBit(Config, bit)
	if not hero or not c or not chain or not SideQuestPlan.visible(chain, devOn()) then
		return
	end
	if what == 1 then
		if SideQuestPlan.resume(c, chain) then
			StoryService.changed(player)
		else
			local ok, why =
				SideQuestPlan.accept(Config, c, chain, hero.level, StoryService.side(player), true)
			if ok then
				Net.fire("Toast", player, { id = "sqStart", bit = chain.bit })
				StoryService.changed(player)
				DataService.saveSoon(player)
			else
				Net.fire("Toast", player, { id = "sqLocked", why = why, bit = chain.bit })
			end
		end
	elseif what == 2 and SideQuestPlan.abandon(c, chain) then
		Net.fire("Toast", player, { id = "sqHold", bit = chain.bit })
		StoryService.changed(player)
	end
end

local function placeGivers()
	local world = CityBuilder.world
	local where = {}
	for id, gv in SQ.givers do
		if not gv.dev or RunService:IsStudio() then
			local x, z = anchor(gv)
			local px, py, pz = IncidentSpots.groundNear(Config, world, x, z, 40, rng)
			local pos = Vector3.new(px, py, pz)
			local _, body = npcModel(gv.name, gv.color, pos)
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Talk"
			prompt.ObjectText = gv.name
			prompt.HoldDuration = 0.2
			prompt.MaxActivationDistance = SQ.range
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.B
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Parent = body
			prompt.Triggered:Connect(function(player)
				local hero = HeroService.get(player)
				local p = hero and HeroService.position(hero)
				if p and (p - body.Position).Magnitude <= SQ.range + 4 then
					talk(player, id)
				end
			end)
			givers[id] = { pos = pos }
			where[id] = { math.floor(px), math.floor(pz) }
		end
	end
	-- the map's giver markers (positions only; the Journal's rows say which chains are open)
	ReplicatedStorage:SetAttribute("SideQuestGivers", HttpService:JSONEncode(where))
end

-- Dev: finish the tracked step (every goal of the player's group)
function SideQuestService.skipStep(player: Player)
	local g = memberOf[player]
	if not g then
		return
	end
	for _, goal in g.goals do
		setHave(g, goal, goal.need)
	end
end

-- Dev panel (Studio only, through DevService): 1 give the sample chain, 2 restart the step, 3 finish the step,
-- 4 finish the whole chain, 5 forget the sample chain, 100 + k jump to step k, 200 + i try kind i alone
function SideQuestService.dev(player: Player, what: number)
	local c = StoryService.char(player)
	local hero = HeroService.get(player)
	if not c or not hero then
		return
	end
	local sample = SideQuestPlan.chain(Config, "Sample")
	local chain = SideQuestPlan.pinned(Config, c) or sample
	if what == 1 and sample then
		leave(player)
		SideQuestPlan.jump(c, sample, 1)
	elseif what == 2 then
		leave(player)
	elseif what == 3 then
		SideQuestService.skipStep(player)
	elseif what == 4 and chain then
		leave(player)
		SideQuestPlan.jump(c, chain, #chain.steps)
		waiting[player] = nil
		refresh(player)
		SideQuestService.skipStep(player)
	elseif what == 5 and sample then
		leave(player)
		SideQuestPlan.reset(c, sample)
	elseif what > 100 and what <= 100 + SQ.maxSteps and chain then
		leave(player)
		SideQuestPlan.jump(c, chain, what - 100)
	elseif what > 200 and SQ.devKinds[what - 200] then
		leave(player)
		local i = what - 200
		local goal = SQ.devKinds[i]
		local test = {
			id = "KindTest",
			bit = 0,
			name = "Kind test",
			giver = "SampleGiver",
			steps = { { hero = goal, villain = "same" } },
		}
		local g = newGroup(test, 1, hero, i)
		join(g, player, StoryService.side(player))
		return
	end
	waiting[player] = nil
	StoryService.changed(player)
end

function SideQuestService.init()
	placeGivers()
	Net.on("SideQuestAct", act)
	StoryService.Changed:Connect(refresh)
	DataService.Loaded:Connect(function(player)
		-- what the retired arcs left (Credits for steps of arcs in progress, unlocks of finished ones), once
		local profile = DataService.get(player)
		if profile then
			local got = SideQuestPlan.settle(Config, profile)
			if got.credits > 0 or #got.unlocks > 0 then
				DataService.changed(player)
				DataService.saveSoon(player)
				task.delay(6, function()
					Net.fire("Toast", player, { id = "sqRetired", credits = got.credits })
				end)
			end
		end
	end)
	IncidentService.Cleared:Connect(function(inc)
		for g in groups do
			for _, goal in g.goals do
				local st = goal.st
				if
					st.kind == "incident"
					and not goal.done
					and (not st.template or inc.plan.tid == st.template)
				then
					for _, h in heroesOf(g, goal.key) do
						if inc.helpers[h.id] then
							setHave(g, goal, goal.have + 1)
							break
						end
					end
				end
			end
		end
	end)
	EnemyService.Killed:Connect(function(_, _, _, enemyId)
		for g in groups do
			for _, goal in g.goals do
				if goal.boss == enemyId then
					goal.boss = nil
					setHave(g, goal, goal.need)
				elseif goal.enemies[enemyId] then
					goal.enemies[enemyId] = nil
					if goal.st.kind == "fight" then
						setHave(g, goal, goal.have + 1)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		waiting[player] = nil
	end)
	local acc, sendAcc, refreshAcc = 0, 0, 0
	RunService.Heartbeat:Connect(FrameProf.wrap("SideQuestService", function(dt)
		acc += dt
		sendAcc += dt
		refreshAcc += dt
		if acc < 0.2 then
			return
		end
		local d = acc
		acc = 0
		for g in groups do
			if not g.finished then
				for _, goal in g.goals do
					if not goal.done and not g.finished then
						tickGoal(g, goal, d)
					end
				end
			end
		end
		if refreshAcc >= 1 then
			refreshAcc = 0
			for _, player in Players:GetPlayers() do
				refresh(player)
			end
		end
		if sendAcc >= 0.5 then
			sendAcc = 0
			for player, g in memberOf do
				Net.fire("SideQuestState", player, stateFor(g, player))
			end
		end
	end))
end

return SideQuestService
