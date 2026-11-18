-- VisitService: visit a friend's HQ on the same server (gap check G15, spec Update 2). The rules are
-- Shared.VisitRules (pure, tested); the copy is HqService.view (the same packet the owner gets).
-- * VISIT (SquadHud, HqVisitAsk) asks the owner, who gets a card for 30 s (HqVisitAsked). Mutes (the save's
--   SettingsRules list) and blocks or reports (GuardService.shuns) stop asks: your own makes VISIT say "unmute
--   or unblock them first"; theirs hides the ask from them, and you are never told.
-- * ACCEPT (HqVisitAnswer) puts the visitor in a sealed visit pocket of the owner's own (VisitRules.pocket,
--   no teleport): the server builds the cell's floor and walls (HqService.buildCell) and sends the visitor a
--   read-only copy of the owner's HQ from the owner's save (VisitRules.readOnly over HqService.view: rooms,
--   trophy wall, statues, props, dressing, the WANTED poster and heads). The copy redraws when the owner's HQ
--   changes (HqService.ownerChanged), and when what it shows changes out in the city: a level (the poster opens
--   at level 8), the story (the city's props), a nemesis met or beaten (the poster, a new head).
-- * Visitors are in a scene ("hqVisit"): no PvP, robots, incidents, events, loot or finds; HqService's station
--   remotes only answer the owner in their own cell, so a visitor cannot use a station, change anything or
--   start the boss sim. LEAVE HQ or the exit (HqVisitLeave) puts the visitor back where they were.
-- * The owner sees their visitors in SQUAD (HqVisitors) and can KICK them (HqVisitKick). A host leaving the
--   server, or muting or blocking a visitor, sends that visitor home too.
-- * Analytics: hq_visit once per visit, at most once a minute per visitor (VisitRules.event).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local VisitRules = require(Shared:WaitForChild("VisitRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local SafehouseService = require(script.Parent.SafehouseService)
local FlagService = require(script.Parent.FlagService)
local GuardService = require(script.Parent.GuardService)
local HqService = require(script.Parent.HqService)
local Analytics = require(script.Parent.Analytics)

local VisitService = {}

local H = Config.Hq
local V = H.visit
local SCENE = "hqVisit"

local st = VisitRules.new()

type Trip = { player: Player, owner: Player, back: CFrame }
local trips: { [Player]: Trip } = {}
type Pocket = { index: number, centre: Vector3, model: Model }
local pockets: { [number]: Pocket } = {} -- owner user id -> their visit pocket
local redrawing: { [Player]: boolean } = {}

local function nameOf(player: Player): string
	local hn = player:GetAttribute("HeroName")
	return if typeof(hn) == "string" and hn ~= "" then hn else player.DisplayName
end

local function say(player: Player, key: string, name: string?)
	if player.Parent then
		Net.fire("Toast", player, { id = "visit", say = key, name = name })
	end
end

-- Can this hero leave what it is doing for a visit? (its own HQ is fine: leaving it comes first)
local function free(hero: any): boolean
	return hero ~= nil
		and hero.loaded
		and hero.alive
		and not hero.downed
		and not hero.traveling
		and (hero.scene == nil or hero.scene == "hq")
		and not FlagService.inPvpCombat(hero)
end

-- Does this player have an HQ to show? (a made hero, loaded)
local function ready(player: Player): boolean
	local hero = HeroService.get(player)
	local profile = DataService.get(player)
	local c = profile and ProfileSchema.active(profile)
	return hero ~= nil and hero.loaded and c ~= nil and c.created ~= 0
end

local function muted(a: Player, b: Player): boolean
	local profile = DataService.get(a)
	return profile ~= nil and table.find(profile.mutes, b.UserId) ~= nil
end

local function context(from: Player, to: Player): VisitRules.Context
	return {
		fromFree = free(HeroService.get(from)),
		toReady = ready(to),
		fromMuted = muted(from, to),
		fromBlocked = GuardService.shuns(from, to.UserId),
		toMuted = muted(to, from),
		toBlocked = GuardService.shuns(to, from.UserId),
	}
end

-- The owner's list of visitors (the SQUAD panel's VISITING YOUR HQ rows)
local function sendVisitors(owner: Player)
	if not owner.Parent then
		return
	end
	local list = {}
	for _, id in VisitRules.visitors(st, owner.UserId) do
		local p = Players:GetPlayerByUserId(id)
		if p then
			table.insert(list, { userId = id, name = nameOf(p) })
		end
	end
	Net.fire("HqVisitors", owner, { list = list })
end

-- Draw the owner's HQ for one visitor (a read-only copy at the pocket)
local function draw(trip: Trip)
	local pocket = pockets[trip.owner.UserId]
	local hero = HeroService.get(trip.owner)
	if not pocket or not hero or not trip.player.Parent then
		return
	end
	local view = HqService.view(trip.owner, hero, pocket.centre)
	if view then
		Net.fire(
			"HqState",
			trip.player,
			VisitRules.readOnly(view, { owner = trip.owner.UserId, name = nameOf(trip.owner) })
		)
	end
end

local function redraw(owner: Player)
	if redrawing[owner] or not pockets[owner.UserId] then
		return
	end
	redrawing[owner] = true
	task.defer(function()
		redrawing[owner] = nil
		for _, trip in trips do
			if trip.owner == owner then
				draw(trip)
			end
		end
	end)
end

local function pocketFor(owner: Player): Pocket?
	local host = st.hosts[owner.UserId]
	if not host then
		return nil
	end
	local p = pockets[owner.UserId]
	if p and p.index == host.index then
		return p
	end
	local x, y, z = VisitRules.pocket(Config, host.index)
	local centre = Vector3.new(x, y, z)
	local made: Pocket = {
		index = host.index,
		centre = centre,
		model = HqService.buildCell(centre, "HqVisit_" .. host.index),
	}
	pockets[owner.UserId] = made
	return made
end

local function takeDown(ownerId: number)
	local p = pockets[ownerId]
	if p then
		pockets[ownerId] = nil
		task.delay(1, function()
			p.model:Destroy()
		end)
	end
end

local function entry(pocket: Pocket): CFrame
	local s = H.stations.exit
	local at = pocket.centre + Vector3.new(s[1], 3, s[2] + 8)
	return CFrame.lookAt(at, pocket.centre + Vector3.new(0, 3, 0))
end

-- Move a visitor back to where they were (the rules have already let them go). key: their line, if any.
local function goHome(player: Player, key: string?): Trip?
	local trip = trips[player]
	trips[player] = nil
	if not trip then
		return nil
	end
	local hero = HeroService.get(player)
	if hero and hero.scene == SCENE then
		hero.scene = nil
	end
	player:SetAttribute("HqVisit", nil)
	if player.Parent then
		if hero then
			SafehouseService.place(hero, trip.back)
		end
		Net.fire("HqState", player, { on = false })
		if key then
			say(player, key, nameOf(trip.owner))
		end
	end
	return trip
end

-- After a visitor went: the owner's list, and the pocket comes down once it is empty
local function after(ownerId: number)
	local owner = Players:GetPlayerByUserId(ownerId)
	if owner then
		sendVisitors(owner)
	end
	if not st.hosts[ownerId] then
		takeDown(ownerId)
	end
end

-- A visitor leaves (LEAVE HQ, the exit) or is sent home. key: the visitor's line (nil for their own LEAVE,
-- which tells the owner instead)
local function sendHome(player: Player, key: string?)
	local ownerId = VisitRules.leave(st, player.UserId)
	local trip = goHome(player, key)
	if trip and key == nil and trip.owner.Parent then
		say(trip.owner, "left", nameOf(player))
	end
	if ownerId then
		after(ownerId)
	end
end

local function ask(player: Player, userId: number)
	local owner = Players:GetPlayerByUserId(userId)
	if not owner then
		say(player, "gone")
		return
	end
	local ok, why, deliver =
		VisitRules.ask(Config, st, player.UserId, userId, os.clock(), context(player, owner))
	if not ok then
		say(player, why or "busy")
		return
	end
	say(player, "sent", nameOf(owner))
	if deliver then
		Net.fire("HqVisitAsked", owner, { from = player.UserId, name = nameOf(player), life = V.askLife })
	end
end

local function answer(owner: Player, userId: number, yes: number)
	local visitor = Players:GetPlayerByUserId(userId)
	if not visitor then
		VisitRules.answer(Config, st, owner.UserId, userId, false, os.clock(), {})
		return
	end
	local ok, why =
		VisitRules.answer(Config, st, owner.UserId, userId, yes == 1, os.clock(), context(visitor, owner))
	if not ok then
		if why == "declined" then
			say(visitor, "declined", nameOf(owner))
		elseif why == "full" then
			say(owner, "full")
			say(visitor, "full")
		elseif why ~= "expired" then
			say(owner, "expired") -- they moved on (a mission, a fight): the card is spent
		end
		return
	end
	local hero = HeroService.get(visitor)
	local pocket = pocketFor(owner)
	if not hero or not pocket then
		VisitRules.leave(st, visitor.UserId)
		after(owner.UserId)
		return
	end
	-- where LEAVE puts them back: outside their own HQ's door if they were in it, else right here
	local back: CFrame
	local fromHq = HqService.backOf(visitor)
	if fromHq then
		back = fromHq
		HqService.leave(visitor)
	else
		local root = HeroService.rootPart(hero)
		back = if root then root.CFrame else CFrame.new(0, 10, 0)
	end
	local trip: Trip = { player = visitor, owner = owner, back = back }
	trips[visitor] = trip
	hero.scene = SCENE
	visitor:SetAttribute("HqVisit", owner.UserId)
	SafehouseService.place(hero, entry(pocket))
	draw(trip)
	say(visitor, "welcome", nameOf(owner))
	say(owner, "arrived", nameOf(visitor))
	sendVisitors(owner)
	local ownerHero = HeroService.get(owner)
	local profile = DataService.get(owner)
	local c = profile and ProfileSchema.active(profile)
	local value, fields = VisitRules.event(
		Config,
		st,
		visitor.UserId,
		os.clock(),
		if ownerHero then ownerHero.side else "hero",
		hero.side,
		#VisitRules.visitors(st, owner.UserId),
		if c then c.hq.level else 1
	)
	if value then
		Analytics.event(visitor, "hq_visit", value, fields)
	end
end

local function kick(owner: Player, userId: number)
	local visitor = Players:GetPlayerByUserId(userId)
	if visitor and VisitRules.kick(Config, st, owner.UserId, userId, os.clock()) then
		goHome(visitor, "kicked")
		after(owner.UserId)
	end
end

-- A host who mutes or blocks a visitor, or a visitor who does that to the host, ends the visit (quietly: the
-- visitor only reads that the visit is over)
local function sweep()
	for player, trip in trips do
		if not trip.owner.Parent then
			sendHome(player, "hostLeft")
		elseif
			muted(trip.owner, player)
			or GuardService.shuns(trip.owner, player.UserId)
			or muted(player, trip.owner)
			or GuardService.shuns(player, trip.owner.UserId)
		then
			sendHome(player, "kicked")
		end
	end
end

-- Dev and tests: the rules state
function VisitService.state(): VisitRules.State
	return st
end

function VisitService.visiting(player: Player): boolean
	return trips[player] ~= nil
end

function VisitService.init()
	Net.on("HqVisitAsk", ask)
	Net.on("HqVisitAnswer", answer)
	Net.on("HqVisitLeave", function(player)
		if trips[player] then
			sendHome(player, nil)
		end
	end)
	Net.on("HqVisitKick", kick)
	HqService.ownerChanged = redraw
	GuardService.blocksChanged = function()
		task.defer(sweep)
	end
	-- a slot switch or Legacy shows the owner's new hero's HQ
	DataService.Loaded:Connect(function(player)
		redraw(player)
	end)
	-- review 2026-11-18: what the copy shows also changes while the owner is out in the city (HqService only
	-- tells ownerChanged from inside the owner's own HQ): a level, the story's props, the WANTED poster and
	-- heads. Required here: the Nemesis and Story services are booted by now. Only owners with visitors redraw.
	local NemesisService = require(script.Parent.NemesisService) :: any
	local StoryService = require(script.Parent.StoryService) :: any
	HeroService.Leveled:Connect(function(hero)
		if hero.player then
			redraw(hero.player)
		end
	end)
	StoryService.Changed:Connect(redraw)
	NemesisService.Met:Connect(redraw)
	NemesisService.Won:Connect(redraw)
	-- a respawn inside (a reset) puts the visitor back in the pocket
	HeroService.Spawned:Connect(function(hero)
		local trip = hero.player and trips[hero.player]
		local pocket = trip and pockets[trip.owner.UserId]
		if trip and pocket then
			hero.scene = SCENE
			task.defer(function()
				SafehouseService.place(hero, entry(pocket))
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		redrawing[player] = nil
		local trip = trips[player]
		trips[player] = nil
		local home, was = VisitRules.drop(st, player.UserId)
		-- a host left: their visitors go back to where they were
		for _, id in home do
			local p = Players:GetPlayerByUserId(id)
			if p then
				goHome(p, "hostLeft")
			end
		end
		takeDown(player.UserId)
		-- a visitor left: their host's list
		if trip and was then
			if trip.owner.Parent then
				say(trip.owner, "left", nameOf(player))
			end
			after(was)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("VisitService", function(dt)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		if next(trips) then
			sweep()
		end
	end))
end

return VisitService
