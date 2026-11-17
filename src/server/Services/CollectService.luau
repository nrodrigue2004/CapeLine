-- CollectService: collections (spec: Hero MMO features > Collections; H7). Twelve sets (Config.Collect,
-- Shared.CollectPlan), saved on the account (profile.mmo.collect):
-- * hidden finds and this week's Comet Shards: spots made from the world at boot; the server picks one up
--   when a hero passes within reach (twice a second), and each device sparkles and chimes near the ones its
--   player is missing (CollectState carries the spots);
-- * drops: a robot's part (a small chance once you are missing it), a world boss's plate on its defeat;
-- * earned: nemesis cores (H5), contest ribbons (ContestService), mentor keepsakes (H6), task force patches;
-- * a full set pays Renown and its HQ prop and counts for the Show-off badges (BadgeService);
-- * the HQ Scanner (CollectScanner at the HQ, Credits, once): the device then marks the nearest find you
--   are missing near you.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CollectPlan = require(Shared:WaitForChild("CollectPlan"))
local Net = require(Shared:WaitForChild("Net"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local Rng = require(Shared:WaitForChild("Rng"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Analytics = require(script.Parent.Analytics)
local BadgeService = require(script.Parent.BadgeService)
local BossService = require(script.Parent.BossService)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EnemyService = require(script.Parent.EnemyService)
local HeroService = require(script.Parent.HeroService)
local HqService = require(script.Parent.HqService)
local MentorService = require(script.Parent.MentorService)
local NemesisService = require(script.Parent.NemesisService)
local TaskForceService = require(script.Parent.TaskForceService)

local CollectService = {}
CollectService.Found = Signal.new() -- (player, bit) a collection item found (the Hero Pass pays XP, H8)

local C = Config.Collect
local Bits = ProfileSchema.Bits
local rng = Rng.new(Rng.hash(os.time(), 77))
local spots: { CollectPlan.Spot }? = nil

local function getSpots(): { CollectPlan.Spot }
	if not spots and CityBuilder.world then
		spots = CollectPlan.spots(Config, CityBuilder.world)
	end
	return spots or {}
end
CollectService.spots = getSpots

local function words(player: Player): { number }?
	local profile = DataService.get(player)
	return profile and profile.mmo.collect
end

local function sendState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local list = {}
	for _, s in getSpots() do
		table.insert(list, { s.bit, math.floor(s.x), math.floor(s.y * 10) / 10, math.floor(s.z) })
	end
	Net.fire("CollectState", player, {
		spots = list,
		found = Bits.list(profile.mmo.collect),
		scanner = profile.mmo.scanner == 1,
	})
end

-- Give an item (once); a finished set pays its reward
function CollectService.give(player: Player, bit: number?)
	local profile = DataService.get(player)
	if not bit or not profile or Bits.get(profile.mmo.collect, bit) then
		return
	end
	local set, item = CollectPlan.setOfBit(C, bit)
	if not set then
		return
	end
	Bits.set(profile.mmo.collect, bit)
	local found = CollectPlan.found(profile.mmo.collect, set)
	Net.fire(
		"CollectFound",
		player,
		{ bit = bit, set = set.name, item = item, found = found, count = set.count }
	)
	Analytics.event(player, "collect_found", found, { set.id })
	CollectService.Found:Fire(player, bit)
	if found >= set.count then
		local r = set.reward
		EconomyService.addRenown(player, r.renown)
		Bits.set(profile.props, r.prop)
		Net.fire("Toast", player, {
			id = "collectSet",
			name = set.name,
			prop = Config.Hq.props[r.prop],
			renown = r.renown,
		})
		Analytics.event(player, "collect_set", 1, { set.id })
		DataService.changed(player)
	end
	BadgeService.bump(player, "finds")
	DataService.saveSoon(player)
end

local function buyScanner(player: Player)
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if not profile or not hero or profile.mmo.scanner == 1 or not HqService.inHq(hero) then
		return
	end
	if EconomyService.spend(hero, C.scanner.cost) then
		profile.mmo.scanner = 1
		DataService.saveSoon(player)
		Net.fire("Toast", player, { id = "scanner" })
		sendState(player)
	end
end

local function pickups()
	local list = getSpots()
	if #list == 0 then
		return
	end
	local r2 = C.reach * C.reach
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local w = words(player)
		local p = hero and hero.alive and not hero.scene and HeroService.position(hero)
		if p and w then
			for _, s in list do
				local dx, dy, dz = s.x - p.X, s.y - p.Y, s.z - p.Z
				if dx * dx + dz * dz <= r2 and math.abs(dy) <= C.reach and not Bits.get(w, s.bit) then
					CollectService.give(player, s.bit)
				end
			end
		end
	end
end

function CollectService.init()
	Net.on("CollectOpen", sendState)
	Net.on("CollectScanner", buyScanner)
	HeroService.Spawned:Connect(function(hero: any)
		local player = hero.player
		if player then
			task.delay(4, function()
				if player.Parent then
					sendState(player)
				end
			end)
		end
	end)
	-- drops
	EnemyService.Killed:Connect(function(kind: string, heroId: number?)
		local hero = heroId and HeroService.byId(heroId)
		local player = hero and hero.player
		local bit = CollectPlan.robotPart(C, kind)
		local w = player and words(player)
		if player and bit and w and not Bits.get(w, bit) and rng:chance(C.dropChance) then
			CollectService.give(player, bit)
		end
	end)
	BossService.Rewarded:Connect(function(player: Player, bossId: any, _tier: number, defeated: boolean)
		local w = words(player)
		if defeated and w and rng:chance(C.plateChance) then
			CollectService.give(player, CollectPlan.bossPlate(C, w, tostring(bossId)))
		end
	end)
	-- earned
	NemesisService.Won:Connect(function(player: Player, rank: number)
		CollectService.give(player, CollectPlan.nemesisCore(C, rank))
	end)
	MentorService.PartDone:Connect(function(player: Player, mentor: number, part: number)
		CollectService.give(player, CollectPlan.keepsake(C, mentor, part))
	end)
	TaskForceService.Done:Connect(function(player: Player, tf: number, seconds: number?, party: number?)
		CollectService.give(player, CollectPlan.patch(C, tf, "clear"))
		if seconds and seconds < Config.TaskForce.speedClear then
			CollectService.give(player, CollectPlan.patch(C, tf, "speed"))
		end
		if (party or 1) >= Config.TaskForce.maxPlayers then
			CollectService.give(player, CollectPlan.patch(C, tf, "full"))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(C.checkEvery)
			pickups()
		end
	end)
end

return CollectService
