-- OpeningService: the playable disaster, mission 1 Shardfall (spec: First 30 seconds and the playable
-- disaster; Suit up and first mission). Runs once per character, on the server, for that player only:
--   leap: stand on a dusk rooftop; Leap to the next roof (one big pulsing button)
--   glide: Glide down to the tram car hanging off the broken rail
--   catch: Catch the car (OpeningAct 1, within 40 studs): citizens climb out, +50 Renown
--   blast: two Spark Drones; the first takes 2 hits and never fires, the second takes 4 and hits weakly
--   choice: a shard lands by a trapped citizen: Save Her (hero) or Grab It (villain) sets the side
--   save: carry her to a rooftop pad / grab: take the shard and outrun 3 drones to the Docks marker
--   suitup: the hero creator (M9, CreatorService) opens; Done saves the hero; then level 3, Flight, +1 Skill Point
--   flight: a guided flight marker to the first beacon (skippable)
-- Words on screen are only verb buttons: the client shows markers and pulses one button per step. A stuck
-- opening goes straight to Suit Up after 4 minutes. The hero is in a scene: no incidents or events find it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local Progress = require(Shared:WaitForChild("Progress"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EnemyService = require(script.Parent.EnemyService)
local EconomyService = require(script.Parent.EconomyService)
local SafehouseService = require(script.Parent.SafehouseService)
local SiteKit = require(script.Parent.SiteKit)
local StoryService = require(script.Parent.StoryService)

local OpeningService = {}

local O = Config.Story.opening
local CODE = OpeningPlan.CODE
local TAG = -7000 -- robots of the opening (never an incident's)

type Run = {
	player: Player,
	hero: any,
	route: OpeningPlan.Route,
	step: string,
	startedAt: number,
	drones: { [number]: boolean },
	things: { any },
	side: string,
	asked: boolean?,
}

local runs: { [Player]: Run } = {}

local function v3(t: { number }, up: number?): Vector3
	return Vector3.new(t[1], t[2] + (up or 0), t[3])
end

local function target(r: Run): { number }?
	local s, route = r.step, r.route
	if s == "leap" then
		return route.leap
	elseif s == "glide" or s == "catch" then
		return route.tram
	elseif s == "blast" then
		return route.drones
	elseif s == "choice" then
		return route.shard
	elseif s == "save" then
		return route.pad
	elseif s == "grab" then
		return route.escape
	elseif s == "flight" then
		return route.beaconAt
	end
	return nil
end

-- A returning player (another hero on the account already did the opening) may Create First: skip the
-- cinematic and the disaster and go straight to Suit Up (spec: Main menu "Create First skips the cinematic
-- for returning players")
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

local function send(r: Run)
	local route = r.route
	Net.fire("OpeningState", r.player, {
		step = CODE[r.step] or 0,
		createFirst = if CODE[r.step] <= CODE.glide and OpeningService.returning(r.player) then true else nil,
		target = target(r),
		side = r.side,
		left = math.max(0, math.ceil(r.startedAt + O.timeout - os.clock())),
		start = route.start,
		leap = route.leap,
		tram = route.tram,
		shard = route.shard,
		pad = route.pad,
		escape = route.escape,
		beacon = route.beaconAt,
	})
end

local function spawnDrones(r: Run, n: number, at: Vector3, opts: { { hits: number?, dmg: number? } })
	local level = r.hero.level
	for i = 1, n do
		local o = opts[i] or opts[#opts]
		local a = i / n * math.pi * 2
		local id = EnemyService.spawnAt(
			"SparkDrone",
			at + Vector3.new(math.cos(a) * 14, 0, math.sin(a) * 14),
			level,
			TAG
		)
		if id then
			EnemyService.tune(id, { hits = o.hits, dmgMult = o.dmg })
			r.drones[id] = true
		end
	end
end

local function clearDrones(r: Run)
	for id in r.drones do
		EnemyService.remove(id)
	end
	table.clear(r.drones)
end

local function setStep(r: Run, step: string)
	r.step = step
	if step == "blast" then
		spawnDrones(r, 2, v3(r.route.drones), {
			{ hits = O.drones.first, dmg = 0 },
			{ hits = O.drones.second, dmg = O.secondDamage },
		})
	elseif step == "save" then
		local pad = SiteKit.pad(v3(r.route.pad))
		table.insert(r.things, pad)
		local c = SiteKit.citizen(v3(r.route.shard, 1), {
			pads = { pad },
			who = function(h)
				return h == r.hero
			end,
			onSafe = function()
				if runs[r.player] == r and r.step == "save" then
					setStep(r, "suitup")
				end
			end,
		})
		table.insert(r.things, c)
	elseif step == "grab" then
		local esc = SiteKit.ring(v3(r.route.escape), 14, Color3.fromRGB(190, 80, 220))
		table.insert(r.things, esc)
		spawnDrones(r, O.escapeDrones, v3(r.route.shard, 18), { { dmg = O.secondDamage } })
	elseif step == "suitup" then
		clearDrones(r)
		SiteKit.clear(r.things)
		StoryService.cancelAsk(r.player)
	end
	send(r)
end

-- Is this player on the Suit Up step (the creator's "create" mode)? Returns the side the choice picked.
function OpeningService.atSuitUp(player: Player): string?
	local r = runs[player]
	return if r and r.step == "suitup" then r.side else nil
end

-- Suit Up done (CreatorService saved the hero): the class and side, then level 3, Flight, the Skill Point
-- and mission 1's first clear
function OpeningService.suitUp(player: Player, classId: string, side: string)
	local r = runs[player]
	if not r then
		return
	end
	local hero = r.hero
	local story = StoryService.story(player)
	if not story or r.step ~= "suitup" then
		return
	end
	if Config.Classes[classId] then
		HeroService.setClass(hero, classId)
		local c = StoryService.char(player)
		if c then
			c.classId = classId
		end
	end
	StoryService.setSide(player, if side == "villain" then "villain" else "hero")
	r.side = StoryService.side(player)
	story.opening = 1
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
	if O.guidedFlight and r.route.beacon > 0 then
		setStep(r, "flight")
	else
		OpeningService.finish(player)
	end
end

function OpeningService.finish(player: Player)
	local r = runs[player]
	if not r then
		return
	end
	clearDrones(r)
	SiteKit.clear(r.things)
	StoryService.cancelAsk(player)
	runs[player] = nil
	r.hero.scene = nil
	Net.fire("OpeningState", player, { step = 0 })
end

function OpeningService.running(player: Player): boolean
	return runs[player] ~= nil
end

local function placeAtStart(r: Run)
	local t0 = os.clock()
	while not r.player.Character and os.clock() - t0 < 10 do
		task.wait(0.2)
	end
	local cf = CFrame.new(v3(r.route.start, 3))
		* CFrame.Angles(
			0,
			math.atan2(r.route.start[1] - r.route.leap[1], r.route.start[3] - r.route.leap[3]),
			0
		)
	SafehouseService.place(r.hero, cf)
end

-- Start the opening for a fresh character (or skip it: the dev command and the Create First button)
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
		warn("[Capeline] no opening route; skipping to Suit Up")
		return false
	end
	local r: Run = {
		player = player,
		hero = hero,
		route = route,
		step = "leap",
		startedAt = os.clock(),
		drones = {},
		things = {},
		side = hero.side,
	}
	runs[player] = r
	hero.scene = "opening"
	task.spawn(placeAtStart, r)
	send(r)
	return true
end

-- Dev and testing: jump to a step
function OpeningService.jump(player: Player, step: string)
	local r = runs[player]
	if r and CODE[step] then
		setStep(r, step)
	end
end

local function step(r: Run, now: number)
	local hero = r.hero
	local pos = HeroService.position(hero)
	if not pos or not hero.alive then
		return
	end
	if now - r.startedAt > O.timeout and CODE[r.step] < CODE.suitup then
		setStep(r, "suitup")
		return
	end
	local s = r.step
	if s == "leap" then
		if OpeningPlan.at(Config, r.route.leap, pos.X, pos.Y, pos.Z, 30) then
			setStep(r, "glide")
		end
	elseif s == "glide" then
		local t = r.route.tram
		if (Vector3.new(t[1], 0, t[3]) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= O.catchRange then
			setStep(r, "catch")
		end
	elseif s == "blast" then
		if next(r.drones) == nil then
			setStep(r, "choice")
		end
	elseif s == "choice" then
		if (v3(r.route.shard) - pos).Magnitude <= 40 then
			-- ask once; the prompt stays until answered
			if not r.asked then
				r.asked = true
				StoryService.ask(r.player, StoryService.OPENING_CHOICE, O.choice, function(option)
					if runs[r.player] ~= r then
						return
					end
					StoryService.setSide(r.player, if option == 2 then "villain" else "hero")
					r.side = StoryService.side(r.player)
					SiteKit.clear(r.things)
					setStep(r, if option == 2 then "grab" else "save")
				end)
			end
		end
	elseif s == "grab" then
		if OpeningPlan.at(Config, r.route.escape, pos.X, pos.Y, pos.Z, 20) then
			setStep(r, "suitup")
		end
	elseif s == "flight" then
		local b = r.route.beaconAt
		if (v3(b) - pos).Magnitude <= 40 then
			OpeningService.finish(r.player)
		end
	end
end

local function onAct(player: Player, act: number)
	local r = runs[player]
	if not r then
		return
	end
	if act == 1 and r.step == "catch" then
		local pos = HeroService.position(r.hero)
		if pos and (v3(r.route.tram) - pos).Magnitude <= O.catchRange + 4 then
			EconomyService.addRenown(player, O.catchRenown)
			Net.fire("Toast", player, { id = "catch", renown = O.catchRenown })
			setStep(r, "blast")
		end
	elseif act == 2 and r.step == "flight" then
		OpeningService.finish(player)
	elseif act == 3 and CODE[r.step] <= CODE.glide and OpeningService.returning(player) then
		-- Create First: straight to Suit Up
		setStep(r, "suitup")
	end
end

local function maybeStart(player: Player)
	local story = StoryService.story(player)
	local hero = HeroService.get(player)
	if story and hero and hero.loaded and story.opening == 0 and not runs[player] then
		OpeningService.start(player)
	end
end

function OpeningService.init()
	Net.on("OpeningAct", onAct)
	DataService.Loaded:Connect(function(player)
		task.delay(1, maybeStart, player)
	end)
	-- a defeated hero comes back on the start roof (or at the tram for the later steps)
	local previous = SafehouseService.spawnOverride
	SafehouseService.spawnOverride = function(hero)
		local r = hero.player and runs[hero.player]
		if r then
			local at = if CODE[r.step] <= CODE.glide then r.route.start else r.route.tram
			return CFrame.new(v3(at, 4))
		end
		return if previous then previous(hero) else nil
	end
	EnemyService.Killed:Connect(function(_, _, _, enemyId)
		for _, r in runs do
			if r.drones[enemyId] then
				r.drones[enemyId] = nil
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local r = runs[player]
		if r then
			clearDrones(r)
			SiteKit.clear(r.things)
			runs[player] = nil
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local now = os.clock()
		for _, r in runs do
			step(r, now)
		end
	end)
end

return OpeningService
