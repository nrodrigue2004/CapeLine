-- QuestService: the 8 side quest arcs (spec: Side quests, 8 named arcs of 3 steps each). The NPCs stand
-- in the hub with a Talk prompt (the server's own range check, so there is no remote). Talking starts the
-- arc and pins it; only the pinned arc's step is built, as a little site for that hero alone:
--   fetch (shards or records on the street, maybe guarded), hold (a ring by the NPC or on a roof), escort
--   (a motorcade that rolls while the hero is near), spot (clear real incidents), carry (Pip to a pad),
--   defeat (a squad), choice (Maribel's menu), race (fly the rings in time), reach (land on a high roof),
--   deliver (run a crate to a pad), find (search an area), chase (a Sneak Bot over the roofs), beacon
--   (calibrate: stand at a beacon) and photo (keep a Sneak Bot in view for 2 seconds).
-- NPC lines are fixed text in Config.Story (no free text). The arc's reward is paid by StoryService.pay.
-- Villains get the same arcs; Old Beacon's drills come from the Velvet Paw for them.
-- PLACEHOLDER ART: NPCs are part-built figures; crates, rings and the motorcade are plain parts.

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
local IncidentSpots = require(Shared:WaitForChild("IncidentSpots"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local IncidentService = require(script.Parent.IncidentService)
local SiteKit = require(script.Parent.SiteKit)
local StoryService = require(script.Parent.StoryService)

local QuestService = {}

local S = Config.Story
local IC = Config.Incidents
local STAKE = Config.Contracts.types.Stakeout
local TAG = -9000
local rng = Rng.new(Rng.hash(os.time(), 67))

type Site = {
	num: number,
	idx: number, -- the arc's step (1 to 3)
	st: any,
	have: number,
	need: number,
	things: { any },
	enemies: { [number]: boolean },
	target: Vector3?,
	area: { number }?, -- find: { x, z, r } search circle
	startedAt: number,
	deadline: number?, -- race: the time left once the first ring is passed
	rings: { Vector3 }?,
	truck: { model: Model, path: { { number } }, at: number, length: number }?,
	chase: { id: number, path: { { number } }, leg: number, at: number, speed: number }?,
	photos: { [number]: number }?, -- photo: Sneak Bot id -> seconds in view
	asked: boolean,
	done: boolean,
}

local npcs: { [number]: { pos: Vector3, villainPos: Vector3? } } = {}
local sites: { [Player]: Site } = {}
local waiting: { [Player]: number } = {} -- the next step builds after questGap

local function v3(t: { number }, up: number?): Vector3
	return Vector3.new(t[1], t[2] + (up or 0), t[3])
end

local function gy(): number
	return Config.City.ground.y
end

---------------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------------

local function anchor(a: any): (number, number)
	local world = CityBuilder.world
	local x, z
	if a.anchor == "plaza" then
		x, z = OpeningPlan.plaza(world)
	elseif a.anchor == "hq" then
		local s = world.safehouses[Config.World.safehouse.homeSafehouse]
		x, z = s.x, s.z + 30
	else
		local d = Config.City.districts[a.anchor]
		x, z = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
	end
	return x + a.dx, z + a.dz
end

local function npcModel(name: string, color: { number }, pos: Vector3): (Model, BasePart)
	local m = SiteKit.model("Npc" .. name)
	local c = Color3.fromRGB(color[1], color[2], color[3])
	local skin = Color3.fromRGB(235, 200, 160)
	local body = SiteKit.part(m, Vector3.new(2, 2.6, 1.2), CFrame.new(pos + Vector3.new(0, 3.3, 0)), c)
	body.Name = "Body"
	SiteKit.part(m, Vector3.new(1.4, 1.4, 1.4), CFrame.new(pos + Vector3.new(0, 5.4, 0)), skin)
	for k = -1, 1, 2 do
		SiteKit.part(
			m,
			Vector3.new(0.8, 2, 0.8),
			CFrame.new(pos + Vector3.new(k * 0.5, 1, 0)),
			Color3.fromRGB(50, 50, 60)
		)
		SiteKit.part(m, Vector3.new(0.6, 2.2, 0.6), CFrame.new(pos + Vector3.new(k * 1.3, 3.3, 0)), c)
	end
	-- a quest marker over the head
	local mark = SiteKit.part(
		m,
		Vector3.new(0.8, 1.6, 0.8),
		CFrame.new(pos + Vector3.new(0, 8, 0)),
		Color3.fromRGB(255, 210, 60),
		Enum.Material.Neon
	)
	mark.Name = "Marker"
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
	label.Text = name -- a fixed NPC name from Config.Story
	label.Parent = tag
	tag.Parent = body
	m.PrimaryPart = body
	return m, body
end

---------------------------------------------------------------------------
-- Building a step
---------------------------------------------------------------------------

local function homeOf(num: number, side: string): Vector3
	local n = npcs[num]
	return if side == "villain" and n.villainPos then n.villainPos else n.pos
end

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

local function squad(site: Site, hero: any, list: { any }, at: Vector3)
	for _, row in list do
		local ids = SiteKit.squad({ { kind = row[1], n = row[2] } }, at, hero.level, TAG, 16)
		for _, id in ids do
			site.enemies[id] = true
		end
	end
end

local function build(hero: any, num: number, idx: number): Site
	local q = S.quests[num]
	local st = q.steps[idx]
	local home = homeOf(num, hero.side)
	local site: Site = {
		num = num,
		idx = idx,
		st = st,
		have = 0,
		need = StoryPlan.need(st),
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
		asked = false,
		done = false,
	}
	local k = st.kind
	local mine = function(h)
		return h == hero
	end
	if k == "fetch" then
		for i = 1, st.count or 1 do
			local at = streetSpot(home, st.range)
			table.insert(
				site.things,
				SiteKit.pickup(at, 8, Color3.fromRGB(120, 220, 255), function()
					site.have += 1
				end, nil, mine)
			)
			if i == 1 then
				site.target = at
				if st.guards then
					squad(site, hero, { st.guards }, at)
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
		site.target = at
		table.insert(site.things, SiteKit.ring(at, st.radius))
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
		site.need = math.min(st.goal, math.max(30, math.floor(length)))
		site.truck = { model = truck, path = path, at = 0, length = length }
		SiteKit.place(truck, v3(path[1]))
		table.insert(site.things, truck)
		site.target = v3(path[1])
	elseif k == "carry" then
		local padAt = roofSpot(home, 20, st.range) or streetSpot(home, st.range)
		local pad = SiteKit.pad(padAt)
		table.insert(site.things, pad)
		table.insert(
			site.things,
			SiteKit.citizen(home + Vector3.new(4, 1, 0), {
				pads = { pad },
				who = mine,
				onSafe = function()
					site.have = 1
				end,
			})
		)
		site.target = padAt
	elseif k == "defeat" then
		local at = if st.home then home + Vector3.new(0, 0, 20) else streetSpot(home, st.range or { 60, 150 })
		squad(site, hero, st.squads, at)
		site.target = at
	elseif k == "race" then
		local rings = {}
		local p = home + Vector3.new(0, 30, 0)
		local a = rng:range(0, math.pi * 2)
		for i = 1, st.checkpoints do
			a += rng:range(-0.6, 0.6)
			p = Vector3.new(p.X + math.cos(a) * st.gap, gy() + 30 + (i % 3) * 18, p.Z + math.sin(a) * st.gap)
			table.insert(rings, p)
			table.insert(site.things, SiteKit.ring(p, 10, Color3.fromRGB(90, 200, 255)))
		end
		site.rings = rings
		site.target = rings[1]
	elseif k == "reach" then
		site.target = roofSpot(home, st.high or 40, st.range or { 80, 200 })
			or roofSpot(home, 20, { 40, 300 })
			or home
	elseif k == "deliver" then
		local at = streetSpot(home, st.range)
		table.insert(site.things, SiteKit.pad(at))
		site.target = at
	elseif k == "find" then
		local at = streetSpot(home, st.range)
		local off = rng:range(0, 50)
		local a = rng:range(0, math.pi * 2)
		site.area = { at.X + math.cos(a) * off, at.Z + math.sin(a) * off, 70 }
		site.target = at -- not sent: the hero only sees the search circle
		local prop = SiteKit.prop(if st.witness then "Witness" else "LostCrate", function(m)
			if st.witness then
				SiteKit.part(m, Vector3.new(2, 2.6, 1.2), CFrame.new(0, 3.3, 0), Color3.fromRGB(200, 160, 90))
				SiteKit.part(
					m,
					Vector3.new(1.4, 1.4, 1.4),
					CFrame.new(0, 5.4, 0),
					Color3.fromRGB(235, 200, 160)
				)
			else
				SiteKit.part(m, Vector3.new(4, 3, 4), CFrame.new(0, 1.5, 0), Color3.fromRGB(150, 110, 60))
			end
		end)
		SiteKit.place(prop, at)
		table.insert(site.things, prop)
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
		local id = EnemyService.spawnAt(st.enemy, v3(path[1], 2), hero.level, TAG, true)
		if id then
			site.enemies[id] = true
			site.chase = { id = id, path = path, leg = 1, at = 0, speed = st.speed }
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
			site.target = Vector3.new(best.x, best.y, best.z)
			table.insert(site.things, SiteKit.ring(site.target :: Vector3, 10, Color3.fromRGB(110, 160, 255)))
		end
	elseif k == "photo" then
		local at = streetSpot(home, st.range)
		site.photos = {}
		for _ = 1, st.count + 1 do
			local a = rng:range(0, math.pi * 2)
			local id = EnemyService.spawnAt(
				"SneakBot",
				at + Vector3.new(math.cos(a) * 25, 0, math.sin(a) * 25),
				hero.level,
				TAG
			)
			if id then
				site.enemies[id] = true
				local photos = site.photos :: { [number]: number }
				photos[id] = 0
			end
		end
		site.target = at
	end
	-- "spot" counts incidents cleared anywhere; "choice" asks in tick()
	return site
end

local function clear(site: Site)
	for id in site.enemies do
		EnemyService.remove(id)
	end
	table.clear(site.enemies)
	SiteKit.clear(site.things)
end

---------------------------------------------------------------------------
-- Running the pinned step
---------------------------------------------------------------------------

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include
local function inView(from: Vector3, to: Vector3): boolean
	local city = Workspace:FindFirstChild("City")
	losParams.FilterDescendantsInstances = if city then { city } else {}
	return Workspace:Raycast(from, to - from, losParams) == nil
end

local function stepDone(player: Player, site: Site)
	site.done = true
	clear(site)
	sites[player] = nil
	Net.fire("QuestState", player, { num = 0 })
	local story = StoryService.story(player)
	local hero = HeroService.get(player)
	if not story or not hero then
		return
	end
	local res = StoryPlan.advanceQuest(story, site.num)
	if res == "done" then
		local q = S.quests[site.num]
		StoryService.pay(player, q.reward, hero.level)
		Net.fire("Toast", player, { id = "questDone", num = site.num })
		story.pinned = 0
	else
		Net.fire("Toast", player, { id = "questStep", num = site.num, step = story.quests[site.num] })
		Net.fire("QuestTalk", player, { num = site.num, line = story.quests[site.num], side = hero.side })
		waiting[player] = os.clock() + S.questGap
	end
	StoryService.changed(player)
end

local function tick(player: Player, hero: any, site: Site, dt: number)
	local pos = HeroService.position(hero)
	if not pos then
		return
	end
	local st = site.st
	local k = st.kind
	if k == "hold" or k == "beacon" then
		local r = if k == "beacon" then 12 else st.radius
		if site.target and (site.target - pos).Magnitude <= r + 3 then
			site.have = math.min(site.need, site.have + dt)
		end
	elseif k == "escort" and site.truck then
		local t = site.truck
		local tp = t.model:GetPivot().Position
		if (tp - pos).Magnitude <= st.near and t.at < t.length then
			t.at = math.min(t.length, t.at + st.speed * dt)
			-- where along the path
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
			site.have = math.min(site.need, t.at)
			site.target = t.model:GetPivot().Position
		end
	elseif k == "race" and site.rings then
		local n = site.have + 1
		local ring = site.rings[n]
		if ring and (ring - pos).Magnitude <= 14 then
			site.have = n
			if n == 1 then
				site.deadline = os.clock() + st.time
			end
			site.target = site.rings[n + 1]
		elseif site.deadline and os.clock() > site.deadline and site.have < site.need then
			site.have = 0 -- out of time: back to the first ring
			site.deadline = nil
			site.target = site.rings[1]
			Net.fire("Toast", player, { id = "raceReset" })
		end
	elseif k == "reach" and site.target then
		local t = site.target
		if (Vector3.new(t.X, 0, t.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= 20 and pos.Y >= t.Y - 4 then
			site.have = 1
		end
	elseif k == "deliver" and site.target then
		if (site.target - pos).Magnitude <= IC.dropRadius + 3 then
			site.have = 1
		end
	elseif k == "find" and site.target then
		if (site.target - pos).Magnitude <= 16 then
			site.have = 1
		end
	elseif k == "chase" and site.chase then
		local c = site.chase
		if not EnemyService.alive(c.id) then
			site.have = 1
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
			site.target = p
		end
	elseif k == "photo" and site.photos then
		local eye = pos + Vector3.new(0, 1.5, 0)
		for id, seen in site.photos do
			local e = EnemyService.get(id)
			if e and e.alive then
				local p = Vector3.new(e.x, e.y, e.z)
				if (p - eye).Magnitude <= STAKE.photoRange and inView(eye, p) then
					site.photos[id] = seen + dt
					if site.photos[id] >= STAKE.photoTime then
						site.photos[id] = nil
						site.enemies[id] = nil
						EnemyService.remove(id)
						Net.fire("Toast", player, { id = "photo" })
						site.have += 1
					end
				end
			end
		end
	elseif k == "choice" and not site.asked then
		site.asked = true
		StoryService.ask(player, StoryService.QUEST_CHOICE, st.options, function(option)
			local story = StoryService.story(player)
			if story and sites[player] == site then
				story.menu = option
				site.have = 1
			end
		end)
	end
	if site.have >= site.need and not site.done then
		stepDone(player, site)
	end
end

-- Build (or tear down) the pinned quest's step for a player
local function refresh(player: Player)
	local story = StoryService.story(player)
	local hero = HeroService.get(player)
	local site = sites[player]
	local want = story and story.pinned or 0
	local idx = if story and want > 0 then story.quests[want] else 0
	if site and (site.num ~= want or site.idx ~= idx) then
		clear(site)
		sites[player] = nil
		site = nil
		StoryService.cancelAsk(player)
		Net.fire("QuestState", player, { num = 0 })
	end
	if not site and hero and hero.loaded and not hero.scene and want > 0 and idx >= 1 and idx <= 3 then
		if not waiting[player] or os.clock() >= waiting[player] then
			waiting[player] = nil
			sites[player] = build(hero, want, idx)
		end
	end
end

local function talk(player: Player, num: number, villainNpc: boolean)
	local hero = HeroService.get(player)
	local story = StoryService.story(player)
	if not hero or not story or not hero.loaded then
		return
	end
	local q = S.quests[num]
	if q.villainNpc and villainNpc ~= (hero.side == "villain") then
		Net.fire("Toast", player, { id = "wrongSide", num = num })
		return
	end
	local s = story.quests[num]
	if s == 0 then
		StoryPlan.startQuest(story, num)
		s = 1
	end
	if s <= 3 then
		story.pinned = num
		StoryService.changed(player)
	end
	Net.fire("QuestTalk", player, { num = num, line = if s <= 3 then s else 0, side = hero.side })
end

local function placeNpcs()
	local world = CityBuilder.world
	for num, q in S.quests do
		local x, z = anchor(q.at)
		local px, py, pz = IncidentSpots.groundNear(Config, world, x, z, 40, rng)
		local pos = Vector3.new(px, py, pz)
		local entry: { pos: Vector3, villainPos: Vector3? } = { pos = pos }
		local function addPrompt(body: BasePart, name: string, villainNpc: boolean)
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Talk"
			prompt.ObjectText = name
			prompt.HoldDuration = 0.2
			prompt.MaxActivationDistance = S.questRange
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.B
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Parent = body
			prompt.Triggered:Connect(function(player)
				local hero = HeroService.get(player)
				local p = hero and HeroService.position(hero)
				if p and (p - body.Position).Magnitude <= S.questRange + 4 then
					talk(player, num, villainNpc)
				end
			end)
		end
		local _, body = npcModel(q.npc, q.color, pos)
		addPrompt(body, q.npc, false)
		if q.villainNpc then
			local vp = pos + Vector3.new(10, 0, 0)
			local _, vbody = npcModel(q.villainNpc, q.villainColor or q.color, vp)
			addPrompt(vbody, q.villainNpc, true)
			entry.villainPos = vp
		end
		npcs[num] = entry
	end
end

-- Dev: finish the pinned step
function QuestService.skipStep(player: Player)
	local site = sites[player]
	if site and not site.done then
		stepDone(player, site)
	end
end

function QuestService.start(player: Player, num: number)
	if S.quests[num] then
		talk(player, num, false)
	end
end

local function sendState(player: Player, site: Site)
	local t = if site.st.kind == "find" then nil else site.target
	Net.fire("QuestState", player, {
		num = site.num,
		step = site.idx,
		have = math.floor(site.have * 10) / 10,
		need = site.need,
		left = if site.deadline then math.max(0, math.ceil(site.deadline - os.clock())) else nil,
		target = if t then { t.X, t.Y, t.Z } else nil,
		area = site.area,
	})
end

function QuestService.init()
	placeNpcs()
	StoryService.Changed:Connect(refresh)
	IncidentService.Cleared:Connect(function(inc)
		for player, site in sites do
			local hero = HeroService.get(player)
			if site.st.kind == "spot" and hero and inc.helpers[hero.id] then
				site.have += 1
			end
		end
	end)
	EnemyService.Killed:Connect(function(_, _, _, enemyId)
		for _, site in sites do
			if site.enemies[enemyId] then
				site.enemies[enemyId] = nil
				if site.st.kind == "defeat" then
					site.have += 1
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local site = sites[player]
		if site then
			clear(site)
		end
		sites[player] = nil
		waiting[player] = nil
	end)
	local acc, sendAcc, refreshAcc = 0, 0, 0
	RunService.Heartbeat:Connect(FrameProf.wrap("QuestService", function(dt)
		acc += dt
		sendAcc += dt
		refreshAcc += dt
		if acc < 0.2 then
			return
		end
		local d = acc
		acc = 0
		for player, site in sites do
			local hero = HeroService.get(player)
			if hero and hero.alive and not hero.scene then
				tick(player, hero, site, d)
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
			for player, site in sites do
				sendState(player, site)
			end
		end
	end))
end

return QuestService
