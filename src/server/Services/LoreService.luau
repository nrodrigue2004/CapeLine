-- LoreService: the lore pages (side-content, 2026-11-19; nate: "maybe something like lore books wouldn't be bad. We
-- have all these landmarks with lore behind them but the game never really tells you"). Config.Lore, Shared.LorePlan.
-- * The spots come from the world at boot (LorePlan.spots: each page near its landmark: a side quest site's door, a
--   beacon, a landmark's middle, Uptown's tower), sent to each device (LoreState) with the pages its account has read.
-- * A hero alive and out of a scene who passes within Config.Lore.reach of a page it has not read picks it up
--   (checked here, a few times a second: the device's book is only a look): the page's bit is saved on the account
--   (profile.lore), Renown is paid, a finished district pays its title and every page the Lore Shelf (HQ prop 23)
--   and the full set's title. LoreFound tells the device, which shows the caption card and the juice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LorePlan = require(Shared:WaitForChild("LorePlan"))
local Net = require(Shared:WaitForChild("Net"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local Analytics = require(script.Parent.Analytics)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local HeroService = require(script.Parent.HeroService)

local LoreService = {}

local L = Config.Lore
local Bits = ProfileSchema.Bits
local spots: { LorePlan.Spot }? = nil

local function getSpots(): { LorePlan.Spot }
	if not spots and CityBuilder.world then
		local list = LorePlan.spots(Config, CityBuilder.world)
		if #list < #L.pages then
			warn(string.format("[LoreService] %d of %d lore pages found a spot", #list, #L.pages))
		end
		spots = list
	end
	return spots or {}
end
LoreService.spots = getSpots

local function readBits(profile: any): { number }
	local out = {}
	for _, b in Bits.list(profile.lore) do
		table.insert(out, b + 1) -- page bits count from 1
	end
	return out
end

local function sendState(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local list = {}
	for _, s in getSpots() do
		table.insert(
			list,
			{ s.bit, math.floor(s.x * 10) / 10, math.floor(s.y * 10) / 10, math.floor(s.z * 10) / 10 }
		)
	end
	Net.fire("LoreState", player, { spots = list, read = readBits(profile) })
end

-- Read a page (once): save it, pay it, tell the device
function LoreService.give(player: Player, bit: number)
	local profile = DataService.get(player)
	local page = LorePlan.page(L, bit)
	if not profile or not page then
		return
	end
	local r = LorePlan.reward(L, profile.lore, bit)
	if not r then
		return
	end
	LorePlan.mark(profile.lore, bit)
	EconomyService.addRenown(player, r.renown)
	local title: string? = nil
	if r.district then
		local i = LorePlan.districtIndex(L, r.district)
		title = i and L.districts[i].title
	end
	if r.all then
		Bits.set(profile.props, L.shelfProp)
		title = L.allName
	end
	local have, total = LorePlan.count(L, profile.lore)
	local inD = 0
	local ofD = 0
	for _, p in LorePlan.inDistrict(L, page.district) do
		ofD += 1
		if LorePlan.has(profile.lore, p.bit) then
			inD += 1
		end
	end
	Net.fire("LoreFound", player, {
		bit = bit,
		found = have,
		count = total,
		inDistrict = inD,
		ofDistrict = ofD,
		renown = r.renown,
		title = title,
		all = r.all or nil,
		prop = if r.all then Config.Hq.props[L.shelfProp] else nil,
	})
	Analytics.event(player, "lore_page", have, { page.district })
	if title then
		DataService.changed(player) -- the title list and the HQ props
	end
	DataService.saveSoon(player)
end

local function pickups()
	local list = getSpots()
	if #list == 0 then
		return
	end
	local r2 = L.reach * L.reach
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local profile = DataService.get(player)
		local p = hero and hero.alive and hero.loaded and not hero.scene and HeroService.position(hero)
		if p and profile then
			for _, s in list do
				local dx, dy, dz = s.x - p.X, s.y - p.Y, s.z - p.Z
				if
					dx * dx + dz * dz <= r2
					and math.abs(dy) <= L.reach + 2
					and not LorePlan.has(profile.lore, s.bit)
				then
					LoreService.give(player, s.bit)
				end
			end
		end
	end
end

function LoreService.init()
	local bad = LorePlan.validate(Config)
	if #bad > 0 then
		warn("[LoreService] Config.Lore: " .. table.concat(bad, "; "))
	end
	Net.on("LoreOpen", sendState)
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
	task.spawn(function()
		while true do
			task.wait(L.checkEvery)
			pickups()
		end
	end)
end

return LoreService
