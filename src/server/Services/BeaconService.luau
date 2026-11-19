-- BeaconService: the 12 fast-travel beacons (spec: Map layout > Fast-travel beacons "discovered by
-- touching"; Movement kit > Fast travel "12 beacons, 3 s skippable flight, cooldown 20 s, not in combat";
-- Remote events Move.FastTravel).
-- * Discovery: a 4 Hz pass; a hero within touchRadius of an undiscovered beacon discovers it (saved on the
--   character as a bit mask, a toast, a save soon).
-- * MoveFastTravel(beaconId): checked by Travel.canTravel. The server answers FastTravel { id, from, to,
--   time } so the client plays the flight; the hero is moved when the flight ends or the player skips
--   (MoveTravelSkip), and MoveGuard accepts the jump. Taking damage during the flight cannot happen: the
--   hero is untargetable while travelling.
-- * Gap polish (2026-11-19): the hero flies the route on its own device (TravelClient), so every player sees
--   it leave and arrive. The trip's arc is hero.travelRoute (MoveGuard allows the flight while the body stays
--   within Travel.routeGap of it) and the player's Traveling attribute (every device's trail and bursts).
--   Bodies fly through buildings in the "TravelFlight" collision group. Discovery waits for the landing.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Travel = require(Shared:WaitForChild("Travel"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

local BeaconService = {}

local W = Config.World
local B = W.beacon

type Trip = {
	beacon: number, -- 0: a trip to a spot that is not a beacon (BeaconService.travelTo)
	started: number,
	arriveAt: number,
	dest: CFrame,
	done: boolean,
	skipped: boolean?,
	after: ((boolean) -> ())?, -- travelTo's callback: true when the hero was set down at the spot
}
local trips: { [Player]: Trip } = {}
local readyAt: { [Player]: number } = {}

local function char(player: Player): any?
	local profile = DataService.get(player)
	return profile and ProfileSchema.active(profile)
end

function BeaconService.traveling(hero: any): boolean
	return hero.player ~= nil and trips[hero.player] ~= nil
end

local function arrive(player: Player, trip: Trip)
	if trip.done or trips[player] ~= trip then
		return
	end
	trip.done = true
	trips[player] = nil
	Analytics.event(player, "fast_travel", 1, { trip.beacon, if trip.skipped then "1" else "0" })
	local hero = HeroService.get(player)
	local model = player.Character
	if hero then
		hero.traveling = false
		hero.travelRoute = nil
	end
	player:SetAttribute("Traveling", nil)
	-- a hero something else moved during the flight (a mission pocket, the HQ) stays where they were put
	local landed = false
	if hero and model and model.Parent and hero.alive and Travel.landOk(trip, hero.placedAt) then
		model:PivotTo(trip.dest)
		MoveGuard.reset(hero)
		landed = true
	end
	Net.fire("FastTravelDone", player, trip.beacon)
	if trip.after then
		task.defer(trip.after, landed)
	end
end

-- The flight itself, once its rules are met: from the hero's spot to `dest` (the arc's end), set down at `land`
local function fly(
	player: Player,
	hero: any,
	pos: Vector3,
	id: number,
	dest: Vector3,
	land: CFrame,
	after: any
)
	local now = os.clock()
	readyAt[player] = now + B.cooldown
	local trip = {
		beacon = id,
		started = now,
		arriveAt = now + B.travelTime,
		dest = land,
		done = false,
		after = after,
	}
	trips[player] = trip
	hero.traveling = true
	hero.travelRoute = { from = pos, to = dest }
	player:SetAttribute("Traveling", true)
	-- stream the destination in during the flight so the hero never lands on empty space
	task.spawn(pcall, player.RequestStreamAroundAsync, player, dest, B.travelTime)
	Net.fire("FastTravel", player, {
		ok = true,
		id = id,
		from = pos,
		to = dest,
		time = B.travelTime,
	})
	task.delay(B.travelTime, arrive, player, trip)
end

-- Fast travel to a spot that is not a beacon (fix-flow, 2026-11-19: the costume contest's GO TO THE STAGE): the
-- same 3 s flight, cooldown and rules as a beacon trip (Travel.canGo: not in combat, a scene or a flight, and
-- the cooldown over), and `after(landed)` once the hero is set down. Returns ok, or false with the reason
-- and the cooldown's seconds left.
function BeaconService.travelTo(
	player: Player,
	land: CFrame,
	after: ((boolean) -> ())?
): (boolean, string?, number)
	local hero = HeroService.get(player)
	local pos = hero and HeroService.position(hero)
	if not hero or not pos or not hero.alive then
		return false, "scene", 0
	end
	local now = os.clock()
	local ok, reason = Travel.canGo({
		beacons = 0,
		inCombat = HeroService.inCombat(hero),
		traveling = trips[player] ~= nil,
		readyAt = readyAt[player] or 0,
		now = now,
		scene = hero.scene,
	})
	if not ok then
		return false, reason, math.max(0, (readyAt[player] or 0) - now)
	end
	fly(player, hero, pos, 0, land.Position + Vector3.new(0, B.arriveAbove, 0), land, after)
	return true, nil, 0
end

local function travel(player: Player, beaconId: number)
	local hero = HeroService.get(player)
	local c = char(player)
	local pos = hero and HeroService.position(hero)
	if not hero or not c or not pos or not hero.alive then
		return
	end
	local now = os.clock()
	local ok, reason = Travel.canTravel(W, {
		beacons = c.beacons,
		inCombat = HeroService.inCombat(hero),
		traveling = trips[player] ~= nil,
		readyAt = readyAt[player] or 0,
		now = now,
		scene = hero.scene, -- review 2026-11-18: never out of the HQ, a visit copy, a pocket or the prologue
	}, beaconId)
	if not ok then
		Net.fire(
			"FastTravel",
			player,
			{ ok = false, reason = reason, wait = math.max(0, (readyAt[player] or 0) - now) }
		)
		return
	end
	local b = CityBuilder.world.beacons[beaconId]
	local dest = Vector3.new(b.x, b.y + B.arriveAbove, b.z)
	local lx, ly, lz = Travel.arrival(W, b)
	local land = Vector3.new(lx, ly, lz)
	fly(player, hero, pos, beaconId, dest, CFrame.new(land, land + Vector3.new(0, 0, 10)), nil)
end

local function discoverPass()
	local world = CityBuilder.world
	local r2 = B.touchRadius * B.touchRadius
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local pos = hero and hero.alive and not hero.traveling and HeroService.position(hero)
		local c = pos and char(player)
		if c then
			for id, b in world.beacons do
				if not Travel.has(c.beacons, id) then
					local d = (b.x - pos.X) ^ 2 + (b.y - pos.Y) ^ 2 + (b.z - pos.Z) ^ 2
					if d <= r2 then
						c.beacons = Travel.add(c.beacons, id)
						DataService.changed(player)
						DataService.saveSoon(player)
						Net.fire("Toast", player, {
							id = "beacon",
							name = b.name,
							found = Travel.count(c.beacons),
							total = #W.beacons,
						})
					end
				end
			end
		end
	end
end

-- The flight's collision group: collides with nothing, so the hero flies over (or through) the city on its
-- route and never rams a tower (TravelClient puts its own body in it for the flight only)
BeaconService.GROUP = "TravelFlight"
local function flightGroup()
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(BeaconService.GROUP) then
			PhysicsService:RegisterCollisionGroup(BeaconService.GROUP)
		end
		for _, g in PhysicsService:GetRegisteredCollisionGroups() do
			PhysicsService:CollisionGroupSetCollidable(BeaconService.GROUP, g.name, false)
		end
	end)
end

function BeaconService.init()
	flightGroup()
	task.defer(flightGroup) -- again once every service has registered its own groups
	Net.on("MoveFastTravel", travel)
	Net.on("MoveTravelSkip", function(player)
		local trip = trips[player]
		if trip then
			trip.skipped = true
			arrive(player, trip)
		end
	end)
	HeroService.Defeated:Connect(function(hero)
		if hero.player and trips[hero.player] then
			trips[hero.player].done = true
			trips[hero.player] = nil
			hero.traveling = false
			hero.travelRoute = nil
			hero.player:SetAttribute("Traveling", nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		trips[player] = nil
		readyAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			discoverPass()
		end
	end)
end

return BeaconService
