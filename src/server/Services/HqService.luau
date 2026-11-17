-- HqService: the Hero HQ, solo visits, upgrades, mannequins, training room, trophies, offline drones and the
-- Hall of Legends (spec: Hero HQ (Beacon Tower or the Foundry); Legacy rebirth).
-- * The doors: the Vigil's maintenance stairwell at the Downtown plaza's edge (The Safehouse, the hideout under
--   the plaza; nate's lore plan Q2: a locked service door to anyone else) and the Foundry door (the Dread
--   Syndicate), your side's only. Entering puts the hero in its own sealed cell far above the map (HqRules.cell by hero
--   slot): the server builds the floor, walls and roof; the device builds the rooms (HqClient). The hero
--   is in a scene ("hq"): no PvP, no incidents, no events. Leaving puts it back outside the door.
-- * Stations work by remote while inside: upgrades (Credits), mannequins (save and wear looks), the
--   training room (dummies with a DPS meter; 4 dummies and the 60 s boss sim at level 3), the trophy wall
--   (3, or 12 at level 4), the Hall of Legends (Retire at the level cap). The command table and Gizmo's shop use
--   the Contract Board, Journal and ShopService. Respec, class change and loadout swaps are allowed here.
-- * Offline drones (level 5+): the minutes away since the last leave pay banked Credits on the next join.
-- * City reputation ranks unlock HQ props.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local HqRules = require(Shared:WaitForChild("HqRules"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)
local SafehouseService = require(script.Parent.SafehouseService)
local StoryService = require(script.Parent.StoryService)
local FlagService = require(script.Parent.FlagService)
local CreatorService = require(script.Parent.CreatorService)

local HqService = {}

local H = Config.Hq
local Bits = ProfileSchema.Bits

type Visit = {
	player: Player,
	hero: any,
	slot: number,
	centre: Vector3,
	model: Model,
	back: CFrame,
	dummies: { number },
	hits: { { number } }, -- { time, amount }
	total: number,
	sim: {
		id: number,
		pos: Vector3,
		hp: number,
		max: number,
		endsAt: number,
		nextSlam: number,
		slamAt: Vector3?,
	}?,
	sent: number,
}

local visits: { [Player]: Visit } = {}
local doors: { [string]: CFrame } = {}
local folder: Folder

local function charOf(player: Player): (any?, any?)
	local profile = DataService.get(player)
	return profile, profile and ProfileSchema.active(profile)
end

function HqService.inHq(hero: any): boolean
	return hero ~= nil and hero.player ~= nil and visits[hero.player] ~= nil
end

local function station(v: Visit, name: string, up: number?): Vector3
	local s = H.stations[name]
	return v.centre + Vector3.new(s[1], up or 3, s[2])
end

local function dummyPositions(v: Visit, n: number): { Vector3 }
	local out = {}
	local base = station(v, "training", 3)
	for i = 1, n do
		table.insert(out, base + Vector3.new((i - 1) * 7 - (n - 1) * 3.5, 0, 6))
	end
	return out
end

local function clearDummies(v: Visit)
	for _, id in v.dummies do
		EnemyService.removeTarget(id)
	end
	v.dummies = {}
	if v.sim then
		EnemyService.removeTarget(v.sim.id)
		v.sim = nil
	end
end

local function addDummies(v: Visit, level: number)
	clearDummies(v)
	for _, pos in dummyPositions(v, HqRules.dummies(Config, level)) do
		local id = EnemyService.addTarget({
			x = pos.X,
			y = pos.Y,
			z = pos.Z,
			r = H.dummy.radius,
			hit = function(amount: number)
				table.insert(v.hits, { os.clock(), amount })
				v.total += amount
				return amount, false
			end,
		})
		table.insert(v.dummies, id)
	end
end

local function state(visit: Visit?, player: Player)
	if not visit then
		Net.fire("HqState", player, { on = false })
		return
	end
	local v = visit :: Visit
	local profile, c = charOf(player)
	local level = if c then c.hq.level else 1
	local earned = {}
	if profile then
		local got = HqRules.trophies(Config, profile)
		for i, t in H.trophies do
			if got[t.id] then
				table.insert(earned, i)
			end
		end
	end
	local statues = {}
	for _, l in (if profile then profile.legends else {}) do
		table.insert(statues, {
			words = l.look,
			name = CreatorRules.heroName(Config, l.titleId or 0, l.nounId or 0),
			level = l.level,
			rank = l.rank,
			classId = l.classId,
		})
	end
	local list = {}
	for i, id in v.dummies do
		local p = dummyPositions(v, #v.dummies)[i]
		table.insert(list, { id = id, x = p.X, y = p.Y, z = p.Z })
	end
	Net.fire("HqState", player, {
		on = true,
		cell = { v.centre.X, v.centre.Y, v.centre.Z },
		side = v.hero.side,
		name = H.names[v.hero.side] or H.names.hero,
		level = level,
		upgrade = HqRules.upgradeCost(Config, level),
		mannequins = HqRules.mannequins(Config, level),
		trophySlots = HqRules.trophySlots(Config, level),
		bossSim = HqRules.bossSim(Config, level),
		mvpCards = HqRules.mvpCards(Config, level),
		drones = HqRules.dronesOn(Config, level),
		dronesPerMinute = HqRules.dronePerMinute(Config, level),
		dummies = list,
		canRetire = c ~= nil and (HqRules.canRetire(Config, c)),
		earned = earned,
		trophies = if c then c.hq.trophies else {},
		statues = statues,
		props = if profile then Bits.list(profile.props) else {},
		sim = if v.sim then { x = v.sim.pos.X, y = v.sim.pos.Y, z = v.sim.pos.Z, id = v.sim.id } else nil,
	})
end

local function buildCell(centre: Vector3, slot: number): Model
	local c = H.cell
	local m = Instance.new("Model")
	m.Name = "Hq_" .. slot
	local function wall(size: Vector3, at: Vector3)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = CFrame.new(at)
		p.Color = Color3.fromRGB(70, 76, 96)
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 1 -- the device draws the rooms (HqClient); these only hold the hero in
		p.Parent = m
	end
	local s, h, t = c.size, c.wall, 2
	wall(Vector3.new(s, t, s), centre - Vector3.new(0, t / 2, 0)) -- the floor (top at the centre's y)
	wall(Vector3.new(s, t, s), centre + Vector3.new(0, h, 0))
	wall(Vector3.new(t, h, s), centre + Vector3.new(-s / 2, h / 2, 0))
	wall(Vector3.new(t, h, s), centre + Vector3.new(s / 2, h / 2, 0))
	wall(Vector3.new(s, h, t), centre + Vector3.new(0, h / 2, -s / 2))
	wall(Vector3.new(s, h, t), centre + Vector3.new(0, h / 2, s / 2))
	-- the floor is visible so the server and device agree on standing height
	local floor = m:GetChildren()[1] :: Part
	floor.Transparency = 0
	m.Parent = folder
	return m
end

function HqService.enter(player: Player, side: string): (boolean, string?)
	local hero = HeroService.get(player)
	local _, c = charOf(player)
	if not hero or not c or not hero.loaded or visits[player] then
		return false, "busy"
	end
	if hero.side ~= side then
		return false, "side"
	end
	if hero.scene or hero.downed or not hero.alive then
		return false, "scene"
	end
	if FlagService.inPvpCombat(hero) then
		return false, "combat"
	end
	local slot = hero.pvpSlot or 1
	local x, y, z = HqRules.cell(Config, slot)
	local centre = Vector3.new(x, y, z)
	local root = HeroService.rootPart(hero)
	local v: Visit = {
		player = player,
		hero = hero,
		slot = slot,
		centre = centre,
		model = buildCell(centre, slot),
		back = (root and root.CFrame) or doors[side] or CFrame.new(0, 10, 0),
		dummies = {},
		hits = {},
		total = 0,
		sim = nil,
		sent = 0,
	}
	visits[player] = v
	hero.scene = "hq"
	player:SetAttribute("InHq", true)
	addDummies(v, c.hq.level)
	local spawn = station(v, "exit", 3) + Vector3.new(0, 0, 8)
	SafehouseService.place(hero, CFrame.lookAt(spawn, centre + Vector3.new(0, 3, 0)))
	state(v, player)
	return true, nil
end

function HqService.leave(player: Player)
	local v = visits[player]
	if not v then
		return
	end
	visits[player] = nil
	clearDummies(v)
	v.hero.scene = nil
	player:SetAttribute("InHq", nil)
	if player.Parent then
		SafehouseService.place(v.hero, v.back)
		state(nil, player)
	end
	task.delay(1, function()
		v.model:Destroy()
	end)
end

local function inside(player: Player): (Visit?, any?, any?)
	local v = visits[player]
	if not v then
		return nil
	end
	local profile, c = charOf(player)
	return v, profile, c
end

local function upgrade(player: Player)
	local v, _, c = inside(player)
	if not v or not c then
		return
	end
	local cost = HqRules.upgradeCost(Config, c.hq.level)
	if not cost then
		Net.fire("Toast", player, { id = "hqMax" })
		return
	end
	if not EconomyService.spend(v.hero, cost) then
		Net.fire("Toast", player, { id = "hqCredits", cost = cost })
		return
	end
	c.hq.level += 1
	addDummies(v, c.hq.level)
	DataService.changed(player)
	DataService.saveSoon(player)
	Net.fire("Toast", player, { id = "hqLevel", level = c.hq.level })
	state(v, player)
end

local function lookSave(player: Player, n: number)
	local v, _, c = inside(player)
	if not v or not c then
		return
	end
	if n > HqRules.mannequins(Config, c.hq.level) then
		Net.fire("Toast", player, { id = "mannequinLocked" })
		return
	end
	n = math.min(n, #c.looks + 1)
	c.looks[n] = table.clone(c.look)
	DataService.changed(player)
	DataService.saveSoon(player)
	Net.fire("Toast", player, { id = "lookSaved", n = n })
end

local function lookWear(player: Player, n: number)
	local v, profile, c = inside(player)
	if not v or not c or not c.looks[n] then
		return
	end
	local look = LookCodec.read(c.looks[n])
	if not look or not CreatorRules.validate(Config, profile, look) then
		Net.fire("Toast", player, { id = "lookBad" })
		return
	end
	c.look = table.clone(c.looks[n])
	c.fxStyle = if look.anime then "Anime" else "Comic"
	HeroService.setFxStyle(v.hero, c.fxStyle)
	GearService.refresh(player)
	DataService.changed(player)
	DataService.saveSoon(player)
	Net.fire("Toast", player, { id = "lookWorn", n = n })
end

local function trophies(player: Player, picks: { number })
	local v, profile, c = inside(player)
	if not v or not c then
		return
	end
	c.hq.trophies = HqRules.pickTrophies(Config, profile, c.hq.level, picks)
	DataService.changed(player)
	DataService.saveSoon(player)
end

local function bossSim(player: Player)
	local v, _, c = inside(player)
	if not v or not c or v.sim then
		return
	end
	if not HqRules.bossSim(Config, c.hq.level) then
		Net.fire("Toast", player, { id = "hqLocked", level = H.levels.bossSim })
		return
	end
	local pos = station(v, "training", 6) + Vector3.new(0, 0, 18)
	local now = os.clock()
	local sim = {
		id = 0,
		pos = pos,
		hp = H.bossSim.hp,
		max = H.bossSim.hp,
		endsAt = now + H.bossSim.time,
		nextSlam = now + 3,
	}
	sim.id = EnemyService.addTarget({
		x = pos.X,
		y = pos.Y,
		z = pos.Z,
		r = 5,
		hit = function(amount: number)
			local dealt = math.min(amount, sim.hp)
			sim.hp -= dealt
			v.total += dealt
			table.insert(v.hits, { os.clock(), dealt })
			return dealt, sim.hp <= 0
		end,
	})
	v.sim = sim :: any
	v.total = 0
	v.hits = {}
	state(v, player)
end

local function retire(player: Player)
	local v, profile, c = inside(player)
	if not v or not profile or not c then
		return
	end
	HeroService.writeBack(v.hero, c)
	local ok, why = HqRules.canRetire(Config, c)
	if not ok then
		Net.fire("Toast", player, { id = "retireLevel", reason = why })
		return
	end
	local statue = HqRules.retire(Config, profile, profile.active, os.time())
	if not statue then
		return
	end
	-- the slot's new run: every service takes the restarted character
	DataService.Loaded:Fire(player, profile)
	CreatorService.sweep(player)
	CreatorService.showName(player)
	DataService.changed(player)
	DataService.save(player)
	Net.fire("Toast", player, { id = "legacy", rank = statue.rank })
	if visits[player] == v then
		addDummies(v, profile.characters[profile.active].hq.level)
		state(v, player)
	end
end

-- The training meter and the boss sim's slams (2 Hz)
local function tick(v: Visit, now: number)
	local cutoff = now - H.dummy.window
	while #v.hits > 0 and v.hits[1][1] < cutoff do
		table.remove(v.hits, 1)
	end
	local sum = 0
	for _, h in v.hits do
		sum += h[2]
	end
	local span = if #v.hits > 0 then math.max(1, math.min(H.dummy.window, now - v.hits[1][1])) else 1
	local packet: { [string]: any } = { dps = math.floor(sum / span + 0.5), total = math.floor(v.total) }
	local sim = v.sim
	if sim then
		local root = HeroService.rootPart(v.hero)
		if sim.slamAt and now >= sim.nextSlam - 0.01 then
			-- the slam lands: stand outside the ring
			if root and (root.Position - sim.slamAt).Magnitude <= H.bossSim.slamRadius then
				local hit = math.floor(v.hero.maxHealth * 0.1)
				if v.hero.health - hit >= 1 then
					HeroService.damage(v.hero, hit, { quiet = true })
				end
			end
			sim.slamAt = nil
			sim.nextSlam = now + H.bossSim.slamEvery
		elseif not sim.slamAt and now >= sim.nextSlam - 1.2 and root then
			sim.slamAt = root.Position
			packet.slam = { sim.slamAt.X, sim.slamAt.Y, sim.slamAt.Z, H.bossSim.slamRadius, 1.2 }
		end
		local left = math.max(0, sim.endsAt - now)
		packet.sim = { left = math.ceil(left), hp = sim.hp, max = sim.max }
		if sim.hp <= 0 or left <= 0 then
			packet.simDone = { killed = sim.hp <= 0, time = H.bossSim.time - left, dealt = sim.max - sim.hp }
			EnemyService.removeTarget(sim.id)
			v.sim = nil
			task.defer(state, v, v.player)
		end
	end
	if packet.total ~= v.sent or packet.sim or packet.simDone then
		v.sent = packet.total
		Net.fire("HqDps", v.player, packet)
	end
end

-- City reputation ranks open HQ props
local function props(player: Player)
	local profile, c = charOf(player)
	if not profile or not c then
		return
	end
	local rank = StoryPlan.repRank(Config, c.rep[StoryPlan.repIndex(Config, "city")] or 0)
	for _, bit in HqRules.cityProps(Config, rank) do
		if not Bits.get(profile.props, bit) then
			Bits.set(profile.props, bit)
			Net.fire("Toast", player, { id = "unlock", kind = "props", name = H.props[bit] })
			DataService.changed(player)
		end
	end
end

-- Offline drones (spec: Wait table "Away | HQ drones earn Credits offline, capped at 8 hours, collected
-- with one tap"): the minutes away since the last leave make a haul; a COLLECT card banks it. A haul
-- nobody tapped is banked anyway when the player leaves, so it is never lost.
local hauls: { [Player]: number } = {}

local function collect(player: Player, given: any?)
	local credits = hauls[player]
	local profile = given or DataService.get(player)
	if not credits or not profile then
		return
	end
	hauls[player] = nil
	profile.currency.banked += credits
	local hero = HeroService.get(player)
	if hero then
		hero.credits = profile.currency.credits + profile.currency.banked
	end
	DataService.changed(player, true)
	if player.Parent then
		Net.fire("Toast", player, { id = "drones", credits = credits })
	end
end

local function drones(player: Player, profile: any)
	local c = ProfileSchema.active(profile)
	local at = c.hq.droneAt
	c.hq.droneAt = 0
	if at <= 0 then
		return
	end
	local credits = HqRules.drones(Config, c.hq.level, os.time() - at)
	if credits > 0 then
		hauls[player] = (hauls[player] or 0) + credits
		Net.fire(
			"DronesReady",
			player,
			{ credits = hauls[player], minutes = math.floor((os.time() - at) / 60) }
		)
	end
end

HqService.payDrones = drones

local function hookPrompt(p: BasePart, side: string, objectText: string, actionText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.B -- E is Skill 2
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = H.doorRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player)
		local ok, why = HqService.enter(player, side)
		if not ok then
			-- the Vigil's door is just a locked service door to anyone else: it never names the HQ
			if side == "hero" and why == "side" then
				Net.fire("Toast", player, { id = "hqRefused", reason = "serviceLocked" })
			else
				Net.fire("Toast", player, { id = "hqRefused", reason = why, name = H.names[side] })
			end
		end
	end)
end

local function makeDoor(side: string, cf: CFrame)
	local p = Instance.new("Part")
	p.Name = "HqDoor_" .. side
	p.Anchored = true
	p.CanCollide = false
	p.Size = Vector3.new(8, 10, 1)
	p.CFrame = cf + Vector3.new(0, 5, 0)
	p.Color = if side == "villain" then Color3.fromRGB(200, 60, 60) else Color3.fromRGB(70, 140, 255)
	p.Material = Enum.Material.Neon
	p.Transparency = 0.35
	p.Parent = folder
	hookPrompt(p, side, H.names[side], "Enter")
	doors[side] = cf + Vector3.new(0, 3, 0)
end

-- The Vigil's way in (nate's lore plan Q2): a maintenance stairwell head at the plaza's edge, a plain concrete
-- box with a steel service door facing the plaza (`cf` at its foot, looking out of the door). Everyone sees a
-- locked "Service Door"; a Vigil device swaps in the HQ's name and a marker (HqClient). PLACEHOLDER ART.
local function makeServiceDoor(cf: CFrame)
	local D = H.door
	local w, h, d = D.size[1], D.size[2], D.size[3]
	local palette = Config.City.palette
	local function rgb(key: string): Color3
		local c = palette[key] or { 255, 0, 255 }
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local model = Instance.new("Model")
	model.Name = "VigilStairwell"
	local function block(name: string, size: Vector3, at: CFrame, color: string, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.Size = size
		p.CFrame = at
		p.Color = rgb(color)
		p.Material = mat
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	-- the head: walls round a stair going down, its door on the plaza side (local -z), a flat roof
	block("Head", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, d / 2), "concrete", Enum.Material.Concrete)
	block(
		"Roof",
		Vector3.new(w + 1, 0.6, d + 1),
		cf * CFrame.new(0, h + 0.3, d / 2),
		"tunnel",
		Enum.Material.Concrete
	)
	block("Frame", Vector3.new(5.6, 8.6, 0.3), cf * CFrame.new(0, 4.3, -0.1), "tunnel", Enum.Material.Metal)
	block(
		"Stripe",
		Vector3.new(w, 0.6, 0.2),
		cf * CFrame.new(0, 0.9, -0.05),
		H.hideout.colors.stripe,
		Enum.Material.SmoothPlastic
	)
	local plate = block(
		"Plate",
		Vector3.new(4, 0.8, 0.1),
		cf * CFrame.new(0, 9.1, -0.3),
		"white",
		Enum.Material.SmoothPlastic
	)
	plate.CanCollide = false
	local lamp = block(
		"Lamp",
		Vector3.new(1.4, 0.5, 0.8),
		cf * CFrame.new(0, 9.9, -0.5),
		H.hideout.colors.lamp,
		Enum.Material.Neon
	)
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 0.8
	light.Color = lamp.Color
	light.Parent = lamp
	local door = block(
		"HqDoor_hero",
		Vector3.new(5, 8, 0.4),
		cf * CFrame.new(0, 4, -0.3),
		"steel",
		Enum.Material.Metal
	)
	door.CanCollide = false
	model.Parent = folder
	hookPrompt(door, "hero", D.object, D.locked)
	doors.hero = cf * CFrame.new(0, 3, -4)
end

function HqService.init()
	folder = Instance.new("Folder")
	folder.Name = "Hq"
	folder.Parent = Workspace
	local world = CityBuilder.world
	-- the Vigil's stairwell at the plaza's edge (the Beacon Tower is Crane's Hero Hall now: no door there)
	local hd = HqRules.heroDoor(Config, world)
	if hd then
		local gy = CityBuilder.heightAt(hd.x, hd.z)
		local at = Vector3.new(hd.x, gy, hd.z)
		makeServiceDoor(CFrame.lookAt(at, at + Vector3.new(hd.fx, 0, hd.fz)))
	end
	local fd = world.spots.foundryDoor
	if fd then
		local y = CityBuilder.heightAt(fd.x, fd.z)
		makeDoor("villain", CFrame.lookAt(Vector3.new(fd.x, y, fd.z), Vector3.new(fd.x, y, fd.z - 10)))
	end
	CreatorService.inHq = HqService.inHq
	CreatorService.leaveHq = HqService.leave
	Net.on("HqLeave", HqService.leave)
	Net.on("HqUpgrade", upgrade)
	Net.on("LookSave", lookSave)
	Net.on("LookWear", lookWear)
	Net.on("HqTrophies", trophies)
	Net.on("HqBossSim", bossSim)
	Net.on("HqRetire", retire)
	Net.on("HqBoard", function(player)
		local _, c = charOf(player)
		if visits[player] and c then
			local id = if c.lastSafehouse > 0 then c.lastSafehouse else Config.World.safehouse.homeSafehouse
			SafehouseService.Board:Fire(player, id)
		end
	end)
	DataService.Loaded:Connect(function(player, profile)
		drones(player, profile)
		props(player)
	end)
	DataService.Leaving:Connect(function(player, profile)
		collect(player, profile) -- an untapped haul is banked, never lost
		ProfileSchema.active(profile).hq.droneAt = os.time()
	end)
	Net.on("HqCollect", function(player)
		collect(player)
	end)
	StoryService.Changed:Connect(props)
	CreatorService.Saved:Connect(function(player)
		local v = visits[player]
		if v then
			state(v, player)
		end
	end)
	HeroService.Leveled:Connect(function(hero)
		local v = hero.player and visits[hero.player]
		if v then
			state(v, hero.player)
		end
	end)
	-- a respawn inside (a reset) puts the hero back in the cell
	HeroService.Spawned:Connect(function(hero)
		local v = hero.player and visits[hero.player]
		if v then
			hero.scene = "hq"
			task.defer(function()
				SafehouseService.place(hero, CFrame.new(station(v, "exit", 3) + Vector3.new(0, 0, 8)))
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local v = visits[player]
		if v then
			visits[player] = nil
			clearDummies(v)
			v.model:Destroy()
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("HqService", function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local now = os.clock()
		for _, v in visits do
			tick(v, now)
		end
	end))
end

return HqService
