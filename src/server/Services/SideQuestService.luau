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
-- * Sites (lore step 11): a chain may happen inside an existing building (Config.SideQuests.sites, picked by
--   Shared.SideQuestSites); its giver stands at the door under the site's sign, and the map marks it (the
--   ReplicatedStorage attribute SideQuestSites). The Hero Academy's inside is the "academy" mission pocket.
-- * Chain 2 (The Gala Heist): sites in Downtown's open squares hold set pieces (Shared.SideQuestSets: the
--   gala marquee and stage, the racers' meet), built here for everyone, their breakable pieces combat targets
--   that burst and stand again; a step's `at` builds it round its site; races and chases may run a rooftop
--   course (Shared.SideQuestSites.course); a finale may have an encore villain (its own name card).
-- * Chain 4 (The Harvest King): Farmland sites on this week's outskirts tiles (a barn, the silos, a field, a
--   farm road: Shared.SideQuestSites.farm); an escort with `road` drives down the farm road toward town.
-- * Chain 6 (The Pit): sites on the Old Quarry landmark (its gate, spots on its floor:
--   Shared.SideQuestSites.quarry); a finale villain with a `dress` wears its own look, name and title over an
--   existing costumed suit (EnemyService.dress), so a chain villain needs no robot type of its own.
-- * lore step 11, the Underwater chain: a deep site on the sea floor (Shared.SideQuestSites.deep): its giver and
--   sign stand on the seabed, and a step built there puts its goals in the open water round it (deepSpot and
--   deepPath: no streets, roofs or roads under the sea); a finale's dress may go over a sea robot
--   (Config.SideQuests.dress `robot`), with its damage lift (`dmgMult`).
-- PLACEHOLDER ART: givers without a `look` are R15 people in plain colours; a giver with one wears its fixed
-- hero look (earnable creator pieces, LookKit); crates, rings, site signs, set pieces and the motorcade are
-- plain parts.

local Debris = game:GetService("Debris")
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
local SideQuestSites = require(Shared:WaitForChild("SideQuestSites"))
local FakeRules = require(Shared:WaitForChild("FakeRules"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))
local LookKit = require(Shared:WaitForChild("LookKit"))
local PeopleLooks = require(Shared:WaitForChild("PeopleLooks"))
local SideQuestSets = require(Shared:WaitForChild("SideQuestSets"))
local SetPieceKit = require(Shared:WaitForChild("SetPieceKit"))
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local IncidentService = require(script.Parent.IncidentService)
local MissionService = require(script.Parent.MissionService)
local SiteKit = require(script.Parent.SiteKit)
local SetPieceMeshes = require(script.Parent.SetPieceMeshes)
local SquadService = require(script.Parent.SquadService)
local StoryService = require(script.Parent.StoryService)

local SideQuestService = {}

-- (player, finale, chainId) a member's chain step was paid (lore step 12: RepService pays own-side reputation;
-- the Rogues File fills the finale's villain pages)
SideQuestService.StepPaid = require(Shared:WaitForChild("Util"):WaitForChild("Signal")).new()

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
	-- (id nil: no runner yet, the server was full; it tries again each tick)
	chase: { id: number?, path: { { number } }, up: number, leg: number, at: number, speed: number }?,
	photos: { [number]: number }?,
	boss: number?,
	bossAt: Vector3?,
	phase: number?, -- the finale's villain: 1, then 2 for an encore (lore step 11, chain 2)
	pocketAt: number?, -- os.clock() of the last pocket try (a short wait between tries)
	inside: { [Player]: boolean }?, -- who stood in the pocket's ring last tick (a run starts on a fresh step in)
	deep: boolean?, -- built under the sea (lore step 11, the Underwater chain)
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
	deep: boolean, -- its home is under the sea (a deep site): goals go in the open water round it
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

local function rnd(): number
	return rng:next()
end

---------------------------------------------------------------------------
-- Givers
---------------------------------------------------------------------------

local function anchor(g: any): (number, number, number?)
	local world = CityBuilder.world
	local x, z
	local y: number? = nil
	if g.anchor == "plaza" then
		x, z = OpeningPlan.plaza(world)
	elseif g.anchor == "hq" then
		local s = world.safehouses[Config.World.safehouse.homeSafehouse]
		x, z = s.x, s.z + 30
	elseif g.anchor == "site" then
		-- lore step 11: at the door of the site's building (its sign beside it)
		local _, door = SideQuestSites.place(Config, world, g.site)
		if door then
			x, z = door.x, door.z
			y = door.y -- a deep site's giver stands on the seabed (lore step 11, the Underwater chain)
		else
			x, z = OpeningPlan.plaza(world)
		end
	else
		local d = Config.City.districts[g.anchor]
		x, z = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
	end
	return x + (g.dx or 0), z + (g.dz or 0), y
end

-- A giver: a person on the heroes' blocky R15 rig in the giver's colour (or, with a `look`, its fixed hero
-- look from earnable creator pieces, like Lodestar's), a marker over the head
local npcLayout = RigMath.layout(Config.HeroRig, nil, 1)
local function lookRig(id: string, def: any): any
	local look = FakeRules.lookFrom(Config, def, id)
	-- the 2026-11-18 art pass: the giver's own outfit and face once uploaded (Shared.PeopleLooks)
	local fit = PeopleLooks.outfit(Config, id)
	if fit and fit.clothes then
		look = PeopleLooks.strip(look)
	end
	local factors =
		BodyShape.factors(Config, { gender = look.gender, build = look.build, height = look.height })
	local layout = RigMath.layout(Config.HeroRig, factors, 1)
	local sk = Config.Creator.skins[look.skin] or Config.Creator.skins[1]
	local skin = Color3.fromRGB(sk[1], sk[2], sk[3])
	local colors = {}
	for _, n in { "Head", "UpperTorso", "LowerTorso" } do
		colors[n] = skin
	end
	for _, side in { "Left", "Right" } do
		for _, n in { "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" } do
			colors[side .. n] = skin
		end
	end
	local rig = NpcRig.build(layout, "Giver" .. id, colors, nil, nil, BodyShape.setKey(Config, look))
	NpcRig.face(rig, "rbxasset://textures/face.png")
	local ok, err = pcall(LookKit.build, rig.model, look)
	if not ok then
		warn("[SideQuestService] giver look", id, err)
	end
	if fit then
		NpcRig.wearOutfit(rig, fit, Config.NpcLooks.offsetSign)
	end
	return rig
end

-- A named helper (Config.NpcLooks.helpers: Toby, Finn, Master Hoshi...) as a person on the rig: their speaker
-- card's skin and hair, plain shirt and pants colours, and their own outfit and face once uploaded
local function helperRig(id: string, h: any): any
	local sp = Config.Story.guides.speakers[h.speaker]
	local pt = sp and sp.portrait
	local skin = if pt
		then Color3.fromRGB(pt.skin[1], pt.skin[2], pt.skin[3])
		else Color3.fromRGB(235, 200, 160)
	local hair = if pt then Color3.fromRGB(pt.hair[1], pt.hair[2], pt.hair[3]) else Color3.fromRGB(70, 46, 30)
	local fit = PeopleLooks.outfit(Config, id)
	local shirt = Color3.fromRGB(h.shirt[1], h.shirt[2], h.shirt[3])
	local pants = Color3.fromRGB(h.pants[1], h.pants[2], h.pants[3])
	if fit and fit.clothes then
		shirt, pants = skin, skin -- the outfit covers the body; skin shows where it is clear
	end
	local rig = NpcRig.person(npcLayout, id, shirt, pants, skin, hair)
	if fit then
		NpcRig.wearOutfit(rig, fit, Config.NpcLooks.offsetSign)
	end
	return rig
end

local function npcModel(
	name: string,
	color: { number },
	pos: Vector3,
	id: string?,
	def: any?
): (Model, BasePart)
	local rig = if id and def
		then lookRig(id, def)
		else NpcRig.person(
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

-- A relay giver (lore step 11, the character lines: Patch, a voice on the radio): a little relay box on a post
-- with a blinking aerial instead of a person; talking to it is talking to the voice. PLACEHOLDER ART: plain
-- parts.
local function relayModel(name: string, color: { number }, pos: Vector3): (Model, BasePart)
	local m = SiteKit.model("Giver" .. name)
	local tint = Color3.fromRGB(color[1], color[2], color[3])
	local steel = Color3.fromRGB(70, 74, 86)
	SiteKit.part(
		m,
		Vector3.new(0.5, 4, 0.5),
		CFrame.new(pos + Vector3.new(0, 2, 0)),
		steel,
		Enum.Material.Metal
	)
	local box = SiteKit.part(
		m,
		Vector3.new(2.2, 1.6, 1.4),
		CFrame.new(pos + Vector3.new(0, 4.6, 0)),
		Color3.fromRGB(40, 44, 54),
		Enum.Material.Metal
	)
	box.CanQuery = true
	SiteKit.part(
		m,
		Vector3.new(1.4, 0.5, 0.1),
		CFrame.new(pos + Vector3.new(0, 4.7, -0.72)),
		tint,
		Enum.Material.Neon
	)
	SiteKit.part(
		m,
		Vector3.new(0.12, 2.6, 0.12),
		CFrame.new(pos + Vector3.new(0.7, 6.7, 0)),
		steel,
		Enum.Material.Metal
	)
	local blink = SiteKit.part(
		m,
		Vector3.new(0.4, 0.4, 0.4),
		CFrame.new(pos + Vector3.new(0.7, 8.1, 0)),
		tint,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	task.spawn(function()
		while blink.Parent do
			blink.Transparency = if blink.Transparency > 0.5 then 0 else 0.8
			task.wait(0.8)
		end
	end)
	local mark = SiteKit.part(
		m,
		Vector3.new(0.8, 1.6, 0.8),
		CFrame.new(pos + Vector3.new(0, 10, 0)),
		Color3.fromRGB(255, 210, 60),
		Enum.Material.Neon
	)
	mark.Name = "Marker"
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(160, 26)
	tag.StudsOffset = Vector3.new(0, 3.2, 0)
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
	tag.Parent = box
	return m, box
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

-- A goal's spot under the sea (lore step 11, the Underwater chain): open water on the seabed round `at`
local function deepSpot(at: Vector3, range: { number }): Vector3
	local p = SideQuestSites.deepSpot(Config, at.X, at.Z, range[1], range[2], rnd)
	return if p then Vector3.new(p[1], p[2], p[3]) else at
end

-- A goal's spot: in the open water round a deep group's home, else on a street
local function spotFor(g: Group, at: Vector3, range: { number }): Vector3
	return if g.deep then deepSpot(at, range) else streetSpot(at, range)
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

-- A rooftop course's roofs (lore step 11, chain 2: Shared.SideQuestSites.course), worked out once: the city's
-- Downtown and Uptown never change, so every server runs the same course
local courses: { [string]: any } = {}
local function courseRoofs(id: string): { any }?
	local hit = courses[id]
	if hit == nil then
		hit = SideQuestSites.course(Config, CityBuilder.world, id) or false
		if not hit then
			warn("[SideQuestService] no rooftop course", id)
		end
		courses[id] = hit
	end
	return if hit then hit else nil
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
		-- (a type whose switch is off gives way to one that is on: SideQuestPlan.robotFor)
		local kind = SideQuestPlan.robotFor(Config, row[1])
		for _, id in SiteKit.squad({ { kind = kind, n = row[2] } }, at, level, TAG, 16) do
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

-- Robots of a goal still out: alive, or beaten with the Killed signal still to come (EnemyService.dying); ids
-- gone any other way are forgotten
local function standing(goal: Goal): number
	local n = 0
	for id in goal.enemies do
		if EnemyService.alive(id) or EnemyService.dying(id) then
			n += 1
		else
			goal.enemies[id] = nil
		end
	end
	return n
end

-- A chase's runner on its path's first point (none while the server is at its robot cap: the next tick tries)
local function runner(g: Group, goal: Goal)
	local c = goal.chase
	if not c or c.id then
		return
	end
	local id = EnemyService.spawnAt(
		SideQuestPlan.robotFor(Config, goal.st.enemy),
		v3(c.path[1], c.up),
		g.level,
		TAG,
		true
	)
	if id then
		goal.enemies[id] = true
		c.id = id
	end
end

-- n more Sneak Bots round a photo step's spot
local function photoBots(g: Group, goal: Goal, n: number)
	local at = goal.target :: Vector3
	local photos = goal.photos :: { [number]: number }
	for _ = 1, n do
		local a = rng:range(0, math.pi * 2)
		local id = EnemyService.spawnAt(
			SideQuestPlan.robotFor(Config, "SneakBot"),
			at + Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25),
			g.level,
			TAG
		)
		if id then
			goal.enemies[id] = true
			photos[id] = 0
		end
	end
end

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
		phase = 1,
		pocketAt = nil,
		deep = g.deep,
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
		local at = if st.home then home + Vector3.new(0, 0, 20) else spotFor(g, home, st.range or { 60, 150 })
		-- (none built, the server full: the step keeps its planned count and tickGoal tops the squad up)
		local n = squad(goal, g.level, st.squads, at)
		setNeed(g, goal, if n > 0 then n else SideQuestPlan.need(st))
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
			local at = spotFor(g, home, st.range)
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
			at = spotFor(g, home, { 40, 120 })
		end
		goal.target = at
		table.insert(goal.things, SiteKit.ring(at, st.radius))
	elseif k == "escort" then
		-- lore step 11, chain 4: `road` drives the truck down a real farm road toward town
		-- (2026-11-18: IncidentSpots.drivePath retries and grows a short path, so the truck always has its drive)
		local road = if st.road
			then SideQuestSites.roadPath(Config, CityBuilder.world, home.X, home.Z, st.goal * 1.15, 7)
			else nil
		local path, length = IncidentSpots.drivePath(
			Config,
			CityBuilder.world,
			home.X,
			home.Z,
			8,
			st.goal / 7,
			st.goal,
			rng,
			road
		)
		-- the chain's own truck look (Shared.SetPieceKit.TRUCKS) once Art.SetPieces is imported: the boxes stay,
		-- hidden, and the mesh rides with them, nose to the drive (-z)
		local look = SetPieceKit.truck(g.chain.id)
		local dressed = look ~= nil and SetPieceMeshes.ready(look)
		local truck = SiteKit.prop("Motorcade", function(m)
			local body =
				SiteKit.part(m, Vector3.new(7, 4, 14), CFrame.new(0, 2.5, 0), Color3.fromRGB(30, 30, 40))
			local cab =
				SiteKit.part(m, Vector3.new(6.6, 2.4, 6), CFrame.new(0, 5.6, -2), Color3.fromRGB(90, 70, 160))
			if dressed then
				SetPieceMeshes.hide(body)
				SetPieceMeshes.hide(cab)
				SetPieceMeshes.add(m, { look = look :: string, x = 0, y = 0, z = 0 }, CFrame.new())
			end
		end)
		setNeed(g, goal, math.min(st.goal, math.floor(length))) -- never more than the truck can drive
		goal.truck = { model = truck, path = path, at = 0, length = length }
		SiteKit.place(truck, v3(path[1]))
		table.insert(goal.things, truck)
		goal.target = v3(path[1])
	elseif k == "carry" then
		-- under the sea (lore step 11, the Underwater chain) the one to rescue is out in the water and the pad is
		-- at the group's home (the giver's station)
		local padAt = if g.deep
			then deepSpot(home, { 10, 24 })
			else roofSpot(home, 20, st.range) or streetSpot(home, st.range)
		local who = if g.deep
			then deepSpot(home, st.range) + Vector3.new(0, 1, 0)
			else home + Vector3.new(4, 1, 0)
		local pad = SiteKit.pad(padAt)
		table.insert(goal.things, pad)
		local hid, h = PeopleLooks.helperAt(Config, g.chain.id, g.idx, key)
		local carried = if hid
			then function()
				return helperRig(hid :: string, h)
			end
			else nil
		table.insert(
			goal.things,
			SiteKit.citizen(who, {
				pads = { pad },
				who = mine,
				-- a named one to carry (Config.NpcLooks.helpers: Finn, Master Hoshi) in their own look
				person = carried,
				onSafe = function()
					setHave(g, goal, goal.need)
				end,
			})
		)
		goal.target = if g.deep then who else padAt
	elseif k == "race" then
		local rings = {}
		local roofs = st.course and courseRoofs(st.course)
		local swim = g.deep
			and SideQuestSites.deepPath(
				Config,
				home.X,
				home.Z,
				st.checkpoints,
				st.gap or 60,
				SQ.deep.lift,
				rnd
			)
		if swim then
			-- lore step 11, the Underwater chain: rings through the open water at mid depth
			for _, q in swim do
				local p = Vector3.new(q[1], q[2], q[3])
				table.insert(rings, p)
				table.insert(goal.things, SiteKit.ring(p, 10, Color3.fromRGB(90, 230, 220)))
			end
			setNeed(g, goal, #rings)
		elseif roofs then
			-- lore step 11, chain 2: a rooftop course, a ring over each roof (the first is where the run starts)
			local up = SQ.courses.ringUp
			for i, b in roofs do
				local p = Vector3.new(b.x, b.top + up, b.z)
				table.insert(rings, p)
				local col = if i == #roofs then Color3.fromRGB(255, 215, 80) else Color3.fromRGB(255, 90, 70)
				table.insert(goal.things, SiteKit.ring(p, 10, col))
			end
			setNeed(g, goal, #rings)
		else
			local p = home + Vector3.new(0, 30, 0)
			local a = rng:range(0, math.pi * 2)
			for i = 1, st.checkpoints do
				a += rng:range(-0.6, 0.6)
				local gap = st.gap or 60
				p = Vector3.new(p.X + math.cos(a) * gap, gy() + 30 + (i % 3) * 18, p.Z + math.sin(a) * gap)
				table.insert(rings, p)
				table.insert(goal.things, SiteKit.ring(p, 10, Color3.fromRGB(90, 200, 255)))
			end
		end
		goal.rings = rings
		goal.target = rings[1]
	elseif k == "reach" and g.deep then
		-- lore step 11, the Underwater chain: swim down to a spot on the sea floor
		goal.target = deepSpot(home, st.range or { 80, 200 })
	elseif k == "reach" then
		goal.target = roofSpot(home, st.high or 40, st.range or { 80, 200 })
			or roofSpot(home, 20, { 40, 300 })
			or home
	elseif k == "deliver" then
		local at = spotFor(g, home, st.range)
		table.insert(goal.things, SiteKit.pad(at))
		goal.target = at
	elseif k == "find" then
		local at = spotFor(g, home, st.range)
		local off = rng:range(0, 50)
		local a = rng:range(0, math.pi * 2)
		goal.area = { at.X + math.cos(a) * off, at.Z + math.sin(a) * off, 70 }
		goal.target = at -- not sent: the heroes only see the search circle
		local prop = SiteKit.prop(if st.witness then "Witness" else "LostCrate", function(m)
			if st.witness then
				-- a named witness (Config.NpcLooks.helpers: Wren, Toby, Flint...) in their own look
				local hid, h = PeopleLooks.helperAt(Config, g.chain.id, g.idx, key)
				local rig = if hid
					then helperRig(hid, h)
					else NpcRig.person(
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
	elseif k == "chase" and st.course and courseRoofs(st.course) then
		-- lore step 11, chain 2: the runner hops the course's roofs (it loops until caught)
		local path = {}
		for _, b in courseRoofs(st.course) :: { any } do
			table.insert(path, { b.x, b.top + 1, b.z })
		end
		goal.chase = { id = nil, path = path, up = 2, leg = 1, at = 0, speed = st.speed }
		runner(g, goal)
	elseif k == "chase" and g.deep then
		-- lore step 11, the Underwater chain: the runner swims a loop of legs through the open water
		local path = SideQuestSites.deepPath(Config, home.X, home.Z, st.hops, 45, SQ.deep.lift, rnd)
			or { { home.X, home.Y + 6, home.Z }, { home.X + 30, home.Y + 6, home.Z } }
		goal.chase = { id = nil, path = path, up = 0, leg = 1, at = 0, speed = st.speed }
		runner(g, goal)
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
		goal.chase = { id = nil, path = path, up = 2, leg = 1, at = 0, speed = st.speed }
		runner(g, goal)
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
		local at = spotFor(g, home, st.range)
		goal.photos = {}
		goal.target = at
		photoBots(g, goal, SideQuestPlan.photoSpawns(st.count, 0, 0)) -- one spare; tickGoal replaces the beaten
	elseif k == "pocket" then
		-- the way in: a ring by the giver; standing in it takes the group's side into a mission pocket
		local at = home + Vector3.new(8, 0, 8)
		goal.target = at
		table.insert(goal.things, SiteKit.ring(at, 10, Color3.fromRGB(170, 110, 255)))
	elseif k == "finale" then
		local at = spotFor(g, home, st.range or { 80, 180 })
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

-- The finale's mini villain (spawned, and spawned again if it is gone without being beaten); with an encore
-- (lore step 11, chain 2) the second villain once the first is beaten
local function spawnBoss(g: Group, goal: Goal)
	local foe = SideQuestPlan.finaleFoe(goal.st, goal.phase or 1)
	local id =
		EnemyService.spawnAt(SideQuestPlan.robotFor(Config, foe.enemy), goal.bossAt or g.home, g.level, TAG)
	if id then
		-- lore step 11, the Underwater chain: a dress's damage lift (Config.SideQuests.dress `dmgMult`)
		local dr = foe.dress and SQ.dress and SQ.dress[foe.dress]
		EnemyService.tune(id, {
			hpMult = math.clamp(foe.hpMult, SQ.finale.hpMult[1], SQ.finale.hpMult[2]),
			dmgMult = dr and dr.dmgMult or nil,
		})
		if foe.dress then
			-- lore step 11, chain 6: the villain's own look, name and title over a costumed suit
			EnemyService.dress(id, foe.dress)
		end
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
		card = if g.test
			then { name = "KIND TEST", title = "FINALE" }
			else SideQuestPlan.card(g.chain, g.idx, goal.phase)
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
		phase = if goal.st.kind == "finale" then goal.phase else nil, -- the name card shows again for an encore
	}
end

-- Perf pass (2026-11-18): the tracker state goes to a member when it changes, not every 0.5 s. The device
-- counts `left` down from when it got it, so a running timer is sent again only when it moves more than a
-- second off that count.
local sent: { [Player]: { s: { [string]: any }, at: number } } = {}
local function same3(a: { number }?, b: { number }?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
local function unchanged(a: { [string]: any }, b: { [string]: any }, dt: number): boolean
	if
		a.bit ~= b.bit
		or a.test ~= b.test
		or a.step ~= b.step
		or a.steps ~= b.steps
		or a.have ~= b.have
		or a.need ~= b.need
		or a.wait ~= b.wait
		or a.phase ~= b.phase
		or not same3(a.target, b.target)
		or not same3(a.area, b.area)
	then
		return false
	end
	if (a.left == nil) ~= (b.left == nil) or (a.left and math.abs(a.left - dt - b.left) > 1) then
		return false
	end
	local ca, cb = a.card, b.card
	if ca == nil or cb == nil then
		return ca == cb
	end
	return ca.name == cb.name and ca.title == cb.title
end
local function pushState(player: Player, state: { [string]: any })
	sent[player] = { s = state, at = os.clock() }
	Net.fire("SideQuestState", player, state)
end

local function clearGroup(g: Group)
	for _, goal in g.goals do
		clearGoal(goal)
	end
	table.clear(g.goals)
	groups[g] = nil
end

local complete: (g: Group) -> ()

local function leave(player: Player)
	local g = memberOf[player]
	if not g then
		return
	end
	memberOf[player] = nil
	g.members[player] = nil
	local dropped, empty, done = SideQuestPlan.leave(g.plan, player)
	if dropped and g.goals[dropped] then
		clearGoal(g.goals[dropped])
		g.goals[dropped] = nil
	end
	if empty then
		clearGroup(g)
	elseif done then
		complete(g) -- the side still there finished and was waiting on the one that left
	end
	pushState(player, { bit = 0 })
end

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
	pushState(player, stateFor(g, player))
end

-- Where a site's steps are built (lore step 11, chain 2): an open square's middle, or a building's door
local function siteHome(id: string): Vector3?
	local world = CityBuilder.world
	local st = SQ.sites[id]
	local spot, door = SideQuestSites.place(Config, world, id)
	if not st or not spot or not door then
		return nil
	end
	if st.square then
		return Vector3.new(spot.x, gy() + 1, spot.z)
	end
	return Vector3.new(door.x, (door.y or gy()) + 1, door.z)
end

local function newGroup(chain: any, idx: number, hero: any, test: number?): Group
	local giver = givers[chain.giver]
	local step = chain.steps[idx]
	local home = (step.at and siteHome(step.at))
		or (if giver then giver.pos else (HeroService.position(hero) or Vector3.zero))
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
		deep = DeepLayout.underwater(Config, home.X, home.Y, home.Z),
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
		pushState(player, { bit = 0 })
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
			SideQuestService.StepPaid:Fire(player, res == "done", chain.id)
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
	-- (or a side that changed: another character slot on the same chain and step)
	if
		g
		and not g.test
		and (g.chain ~= chain or g.idx ~= idx or g.members[player] ~= StoryService.side(player))
	then
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
	if not SideQuestPlan.goal(chain.steps[idx], side) then
		return -- a line for the other side only (lore step 11: a Dev panel jump can pin one)
	end
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
local function startPocket(g: Group, goal: Goal, first: Player): boolean
	if goal.pocketAt and os.clock() - goal.pocketAt < 5 then
		return false
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
	return ok
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
	if k == "fight" then
		-- robots still to put out (a squad the full server could not build, or one gone without a defeat)
		local short = SideQuestPlan.shortfall(goal.need, have, standing(goal))
		if short > 0 and goal.target then
			local rows = {}
			for _, row in st.squads do
				local n = math.min(row[2], short)
				if n > 0 then
					table.insert(rows, { row[1], n })
					short -= n
				end
			end
			squad(goal, g.level, rows, goal.target)
		end
	elseif k == "hold" or k == "beacon" then
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
	elseif k == "reach" and goal.target and goal.deep then
		-- under the sea: swim within 20 studs of the spot
		if anyNear(goal.target, 20) then
			have = 1
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
		if not c.id then
			runner(g, goal) -- the server was full when the step was built
		elseif not EnemyService.alive(c.id) then
			have = 1
		else
			local a, b = c.path[c.leg], c.path[c.leg % #c.path + 1]
			local pa, pb = v3(a, 2), v3(b, 2)
			c.at += c.speed * dt / math.max(1, (pb - pa).Magnitude)
			if c.at >= 1 then
				c.at = 0
				c.leg = c.leg % #c.path + 1
			end
			-- a hop over the street (never under the sea, where the runner swims straight)
			local hop = if goal.deep then 0 else math.sin(c.at * math.pi) * 10
			local p = pa:Lerp(pb, c.at) + Vector3.new(0, hop, 0)
			EnemyService.place(c.id :: number, p)
			goal.target = p
		end
	elseif k == "photo" and goal.photos then
		local alive = 0
		for id in goal.photos do
			if EnemyService.alive(id) then
				alive += 1
			else
				goal.photos[id] = nil -- beaten (or gone) before its photo: another slips in below
				goal.enemies[id] = nil
			end
		end
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
					alive -= 1
				end
			end
		end
		if have < goal.need then
			photoBots(g, goal, SideQuestPlan.photoSpawns(st.count, have, alive))
		end
	elseif k == "pocket" and goal.target then
		-- only a fresh step into the ring starts a run: a hero put back at the ring after a run (MissionService
		-- returns them where they went in) must step out and in again
		local inside = goal.inside or {}
		goal.inside = inside
		local near = {}
		for _, e in list do
			if e.hero.player then
				near[e.hero.player] = (goal.target - e.pos).Magnitude <= 12
			end
		end
		for _, p in SideQuestPlan.ringEntries(inside, near) do
			if startPocket(g, goal, p) then
				break
			end
			inside[p] = false -- refused or too soon: tried again next tick
		end
	elseif k == "finale" then
		-- (a beaten one has left the sim before its Killed fires at the next event drain: dying waits for it)
		if goal.boss and not EnemyService.alive(goal.boss) and not EnemyService.dying(goal.boss) then
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

-- A site's sign (lore step 11): a lit frame by the door with the site's fixed name. PLACEHOLDER ART.
local function siteSign(name: string, door: any)
	local m = SiteKit.prop("SiteSign", function(model)
		SiteKit.part(model, Vector3.new(1, 12, 1), CFrame.new(-7, 6, 0), Color3.fromRGB(70, 80, 100))
		SiteKit.part(model, Vector3.new(1, 12, 1), CFrame.new(7, 6, 0), Color3.fromRGB(70, 80, 100))
		local board = SiteKit.part(
			model,
			Vector3.new(16, 3.4, 0.6),
			CFrame.new(0, 11, 0),
			Color3.fromRGB(245, 245, 250)
		)
		SiteKit.part(
			model,
			Vector3.new(5, 0.5, 5),
			CFrame.new(0, 14, 0),
			Color3.fromRGB(255, 215, 80),
			Enum.Material.Neon
		)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(40, 90, 170)
			label.Text = name -- a fixed site name from Config.SideQuests.sites
			label.Parent = gui
			gui.Parent = board
		end
	end)
	-- beside the door, facing the street (a deep site's on the seabed)
	local at = Vector3.new(door.x + door.fz * 12, door.y or gy(), door.z - door.fx * 12)
	SiteKit.place(m, at, math.atan2(-door.fx, -door.fz))
end

-- A set piece's fixed sign text on both faces of a board (lore step 11, chain 2)
local function writeSign(board: BasePart, text: string, color: Color3)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = text -- a fixed set piece sign from Shared.SideQuestSets
		label.Parent = gui
		gui.Parent = board
	end
end

-- One box of a set piece (Shared.SideQuestSets), at cf. PLACEHOLDER ART: plain parts until Art.SetPieces is
-- imported; `hidden` (its look drawn as meshes): unseen, still colliding and in its piece as before.
local function setPart(parent: Instance, b: any, cf: CFrame, hidden: boolean?): BasePart
	local at = cf
	if b.upright then
		at *= CFrame.Angles(0, 0, math.rad(90))
	end
	if b.tilt then
		at *= CFrame.Angles(math.rad(b.tilt), 0, 0)
	end
	local okMat, mat = pcall(function()
		return (Enum.Material :: any)[b.mat or "SmoothPlastic"]
	end)
	local shape = if b.shape == "cylinder"
		then Enum.PartType.Cylinder
		elseif b.shape == "ball" then Enum.PartType.Ball
		else nil
	local p = SiteKit.part(
		parent,
		Vector3.new(b.sx, b.sy, b.sz),
		at,
		Color3.fromRGB(b.color[1], b.color[2], b.color[3]),
		if okMat then mat else nil,
		shape
	)
	p.CanCollide = not b.ghost
	p.CanQuery = not b.ghost
	p.CastShadow = not b.ghost
	p.Transparency = b.alpha or 0
	if b.sign then
		writeSign(p, b.sign, Color3.fromRGB(150, 30, 50))
	end
	if hidden then
		SetPieceMeshes.hide(p)
	end
	return p
end

-- The looks of a set drawn as meshes (Shared.SetPieceKit): those of one breakable piece (pid) or of the solid
-- set (nil), with `at` the set's origin as a CFrame (a piece's model: its centre's offset)
local function setLooks(parent: Instance, set: any, drawn: { [number]: boolean }, pid: string?, at: CFrame)
	for i, pl in set.art or {} do
		if drawn[i] and pl.piece == pid then
			SetPieceMeshes.add(parent, pl, at * CFrame.new(pl.x, pl.y, pl.z) * SetPieceMeshes.yaw(pl))
		end
	end
end

-- A broken piece bursts into loose chunks that tumble for a moment (cartoon: no harm, they are gone in 3 s)
local function burst(model: Model, at: Vector3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and d.Transparency < 1 then
			local c = d:Clone()
			for _, gui in c:GetChildren() do
				gui:Destroy()
			end
			c.Anchored = false
			c.CanCollide = true
			c.CanQuery = false
			c.CanTouch = false
			c.Massless = true
			c.Parent = model.Parent
			local out = (c.Position - at)
			local flatOut = Vector3.new(out.X, 0, out.Z)
			local dir = if flatOut.Magnitude > 0.1
				then flatOut.Unit
				else Vector3.new(rng:range(-1, 1), 0, 1).Unit
			c.AssemblyLinearVelocity = dir * rng:range(10, 24) + Vector3.new(0, rng:range(18, 30), 0)
			c.AssemblyAngularVelocity = Vector3.new(rng:range(-6, 6), rng:range(-6, 6), rng:range(-6, 6))
			Debris:AddItem(c, 3)
		end
	end
end

-- A breakable piece of a set: a combat target that bursts when its HP runs out and stands again after
-- Config.SideQuests.sets.rebuild seconds (the incidents' objects, SiteKit.object)
local function setPiece(set: any, pid: string, origin: Vector3)
	local pc = set.pieces[pid]
	local centre = origin + Vector3.new(pc.x, pc.y, pc.z)
	local S = SQ.sets
	local hp = IncidentPlan.objectHp(Config, S.hits, S.level)
	local h: any = nil
	h = SiteKit.object(
		"SetPiece_" .. pid,
		centre,
		0,
		pc.r,
		hp,
		function(m)
			local drawn = SetPieceMeshes.drawn(set.art)
			for _, b in set.boxes do
				if b.piece == pid then
					setPart(m, b, CFrame.new(b.x - pc.x, b.y - pc.y, b.z - pc.z), SetPieceKit.hides(b, drawn))
				end
			end
			setLooks(m, set, drawn, pid, CFrame.new(-pc.x, -pc.y, -pc.z))
		end,
		nil,
		function()
			if not h then
				return
			end
			burst(h.model, centre)
			SiteKit.removeObject(h)
			task.delay(S.rebuild, function()
				setPiece(set, pid, origin)
			end)
		end
	)
	SiteKit.moveObject(h, centre)
end

-- A square site's set piece (lore step 11, chain 2): its solid boxes in one model, each breakable piece its
-- own target
local function buildSet(id: string, square: any)
	local set = SideQuestSets.build(id)
	local origin = Vector3.new(square.x, gy() + 0.9, square.z) -- on the square's paving
	local m = SiteKit.model("Set_" .. id)
	local drawn = SetPieceMeshes.drawn(set.art)
	for _, b in set.boxes do
		if not b.piece then
			setPart(m, b, CFrame.new(origin + Vector3.new(b.x, b.y, b.z)), SetPieceKit.hides(b, drawn))
		end
	end
	setLooks(m, set, drawn, nil, CFrame.new(origin))
	for pid in set.pieces do
		setPiece(set, pid, origin)
	end
end

local function placeSites(): { [string]: { number } }
	local world = CityBuilder.world
	local out = {}
	for id, st in SQ.sites or {} do
		local b, door = SideQuestSites.place(Config, world, id)
		if b and door then
			if st.square then
				if st.set then
					buildSet(st.set, b)
				end
			elseif st.sign ~= false then
				siteSign(st.name, door)
			end
			out[id] = { math.floor(b.x), math.floor(b.z) }
		else
			warn("[SideQuestService] no building fits site", id)
		end
	end
	return out
end

local function placeGivers()
	local world = CityBuilder.world
	local where = {}
	ReplicatedStorage:SetAttribute("SideQuestSites", HttpService:JSONEncode(placeSites()))
	for id, gv in SQ.givers do
		if not gv.dev or RunService:IsStudio() then
			local x, z, y = anchor(gv)
			local px, py, pz = x, y, z
			if y == nil then
				px, py, pz =
					IncidentSpots.groundNear(Config, world, x, z, if gv.anchor == "site" then 6 else 40, rng)
			end
			local pos = Vector3.new(px, py, pz)
			local body: any
			if gv.relay then
				local _, b = relayModel(gv.name, gv.color, pos)
				body = b
			else
				local _, b = npcModel(gv.name, gv.color, pos, if gv.look then id else nil, gv.look)
				body = b
			end
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
-- 4 finish the whole chain, 5 forget the sample chain, 100 + k jump to step k, 200 + i try kind i alone,
-- 300 + i start chain i (Config.SideQuests.chains) at step 1 (then 100 + k jumps through it)
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
	elseif what > 300 and SQ.chains[what - 300] then
		leave(player)
		SideQuestPlan.jump(c, SQ.chains[what - 300], 1)
	elseif what > 200 and what <= 300 and SQ.devKinds[what - 200] then
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
		-- a character slot switch loads another character: its own chain, step and side
		if memberOf[player] then
			leave(player)
			waiting[player] = nil
		end
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
					if goal.st.encore and (goal.phase or 1) < 2 then
						-- lore step 11, chain 2: the first villain is down; the encore lands with its own crew
						goal.phase = 2
						setHave(g, goal, 1)
						local adds = goal.st.encore.adds
						if adds then
							squad(goal, g.level, adds, goal.bossAt or g.home)
						end
						spawnBoss(g, goal)
						for _, p in membersOf(g, goal.key) do
							Net.fire("Toast", p, { id = "sqEncore" })
						end
					else
						setHave(g, goal, goal.need)
					end
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
		sent[player] = nil
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
			local now = os.clock()
			for player, g in memberOf do
				local state = stateFor(g, player)
				local last = sent[player]
				if not (last and unchanged(last.s, state, now - last.at)) then
					pushState(player, state)
				end
			end
		end
	end))
end

return SideQuestService
