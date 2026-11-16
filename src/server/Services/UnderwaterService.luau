-- UnderwaterService: the things to do under the water (Config.Deep; nate 2026-11-16 "no underwater comes
-- now"). The areas themselves are CityBuilder.deep (Shared.DeepLayout); the sea robots are EnemySim's.
-- * Sunken cargo caches on the Coral Shelf and in the Trench: swim within reach to open one. Pays
--   Economy.earn.deepCache at the area's zone level and rolls Loot.sources.deepCache; each hero can open
--   each cache once per Deep.caches.cooldown.
-- * Commuters trapped in air pockets in the Sunken Line: swim close to pick one up (they hold on), then swim
--   them up to the quay. Pays Economy.earn.deepRescue. The commuter waits again after Deep.rescues.respawn.
--   A hero who is downed, leaves or falls into a mission pocket lets go and the commuter goes back.
-- Everything is checked from the server's own hero positions at 4 Hz: no client remote can claim a cache.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))

local HeroService = require(script.Parent.HeroService)
local CityBuilder = require(script.Parent.CityBuilder)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)

local UnderwaterService = {}

local D = Config.Deep
local opened: { [number]: { [number]: number } } = {} -- hero id -> cache id -> when it opens again
local waiting: { [number]: boolean } = {} -- rescue id -> waiting to be picked up
local backAt: { [number]: number } = {} -- rescue id -> when it waits again
local carriers: { [number]: number } = {} -- hero id -> rescue id

local function dist(a: Vector3, x: number, y: number, z: number): number
	local dx, dy, dz = a.X - x, a.Y - y, a.Z - z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function stateFor(hero: any, now: number): any
	local mine = {}
	local list = opened[hero.id]
	if list then
		for id, t in list do
			if t > now then
				mine[tostring(id)] = math.ceil(t - now)
			end
		end
	end
	local rescues, carry = {}, {}
	for id, w in waiting do
		if w then
			rescues[tostring(id)] = true
		end
	end
	for heroId, id in carriers do
		carry[tostring(heroId)] = id
	end
	return { opened = mine, rescues = rescues, carriers = carry }
end

local function sendAll(now: number)
	for _, hero in HeroService.all() do
		if hero.player then
			Net.fire("DeepState", hero.player, stateFor(hero, now))
		end
	end
end

local function letGo(heroId: number, now: number)
	local id = carriers[heroId]
	if id then
		carriers[heroId] = nil
		waiting[id] = true -- the commuter swims back to the air pocket
		backAt[id] = nil
		sendAll(now)
	end
end

local function openCache(hero: any, cache: any, now: number)
	local mine = opened[hero.id]
	if not mine then
		mine = {}
		opened[hero.id] = mine
	end
	mine[cache.id] = now + D.caches.cooldown
	local level = DeepLayout.zoneLevel(Config, cache.x, cache.y, cache.z, hero.level)
	local player = hero.player :: Player
	EconomyService.reward(player, "deepCache", level)
	GearService.grant(player, "deepCache", level)
	Net.fire("Toast", player, { id = "note", text = "Sunken cache opened!" })
	Net.fire("DeepState", player, stateFor(hero, now))
end

local function step(now: number)
	local deep = CityBuilder.deep
	if not deep then
		return
	end
	local changed = false
	for id, t in backAt do
		if now >= t then
			backAt[id] = nil
			waiting[id] = true
			changed = true
		end
	end
	local q = D.rescues.quay
	local wy = Config.World.coast.waterY
	for _, hero in HeroService.all() do
		local pos = if hero.player and hero.alive then HeroService.position(hero) else nil
		if not pos then
			if carriers[hero.id] then
				letGo(hero.id, now)
			end
			continue
		end
		local wet = DeepLayout.underwater(Config, pos.X, pos.Y, pos.Z)
		if wet then
			local mine = opened[hero.id]
			for _, c in deep.caches do
				if (not mine or (mine[c.id] or 0) <= now) and dist(pos, c.x, c.y, c.z) <= D.caches.reach then
					openCache(hero, c, now)
					mine = opened[hero.id]
				end
			end
			if not carriers[hero.id] then
				for _, r in deep.rescues do
					if waiting[r.id] and dist(pos, r.x, r.y, r.z) <= D.rescues.reach then
						waiting[r.id] = false
						carriers[hero.id] = r.id
						changed = true
						Net.fire(
							"Toast",
							hero.player,
							{ id = "note", text = "Got them! Swim up to the quay." }
						)
						break
					end
				end
			end
		end
		local carry = carriers[hero.id]
		if carry then
			local dx, dz = pos.X - q.x, pos.Z - q.z
			if math.sqrt(dx * dx + dz * dz) <= q.reach and pos.Y >= wy - 2 then
				carriers[hero.id] = nil
				backAt[carry] = now + D.rescues.respawn
				changed = true
				local level = DeepLayout.zoneLevel(Config, pos.X, wy - 10, pos.Z, hero.level)
				EconomyService.reward(hero.player, "deepRescue", math.max(level, D.zoneFloor.line))
			elseif pos.Y > Config.Story.pockets.y - 100 then
				letGo(hero.id, now) -- went into a mission pocket
			end
		end
	end
	if changed then
		sendAll(now)
	end
end

function UnderwaterService.carrying(hero: any): number?
	return carriers[hero.id]
end

function UnderwaterService.init()
	for _, r in (CityBuilder.deep and CityBuilder.deep.rescues) or {} do
		waiting[r.id] = true
	end
	HeroService.Removed:Connect(function(hero)
		letGo(hero.id, os.clock())
		opened[hero.id] = nil
	end)
	HeroService.Spawned:Connect(function(hero)
		task.defer(function()
			if hero.player then
				Net.fire("DeepState", hero.player, stateFor(hero, os.clock()))
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		letGo(player.UserId, os.clock())
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("UnderwaterService", function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			step(os.clock())
		end
	end))
end

return UnderwaterService
