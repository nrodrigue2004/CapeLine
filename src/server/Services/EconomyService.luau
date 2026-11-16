-- EconomyService: Credits, Renown, Lumen Dust and levels (spec: Economy > Currencies, Earn formulas, Sinks;
-- Levels). Every reward is computed and applied here on the server, then the client gets a summary
-- (spec: "The server sends a reward summary after it has already applied it").
-- * reward(player, action, zoneLevel, opts): the earn formula with the bonus stack (friends, Legacy,
--   faction, first contracts, 2x pass), capped at x4.
-- * addRenown: level ups (each grants a Skill Point through the level) and a save soon.
-- * spend(hero, credits): on hand first, then banked.
-- Friends in the server are counted once per join (IsFriendsWith yields) and kept up to date on leave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Progress = require(Shared:WaitForChild("Progress"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)

local EconomyService = {}

local friendsOf: { [Player]: { [Player]: boolean } } = {}

local function friendCount(player: Player): number
	local n = 0
	for other in friendsOf[player] or {} do
		if other.Parent == Players then
			n += 1
		end
	end
	return n
end

local function syncCredits(player: Player, profile: any)
	local hero = HeroService.get(player)
	if hero then
		hero.credits = profile.currency.credits + profile.currency.banked
	end
end

-- The bonus stack for this player right now
function EconomyService.bonus(player: Player, opts: { [string]: any }?): Progress.Bonus
	local profile = DataService.get(player)
	local char = profile and ProfileSchema.active(profile)
	local o = opts or {}
	return {
		friends = friendCount(player),
		legacy = if char then char.legacy else 0,
		faction = 0, -- faction rank (M7)
		firstContract = o.firstContract,
		doublePass = profile ~= nil and profile.purchases.passes.double == true,
	}
end

-- Add Renown to the active character; returns levels gained
function EconomyService.addRenown(player: Player, amount: number): number
	local hero = HeroService.get(player)
	local profile = DataService.get(player)
	if not hero or not profile or not hero.loaded or amount <= 0 then
		return 0
	end
	local level, xp, gained = Progress.addRenown(Config, hero.level, hero.xp, amount)
	HeroService.setProgress(hero, level, xp)
	if gained > 0 then
		Net.fire("Toast", player, { id = "levelUp", level = level })
		DataService.saveSoon(player)
	end
	return gained
end

function EconomyService.addCredits(player: Player, amount: number)
	local profile = DataService.get(player)
	if profile and amount > 0 then
		profile.currency.credits += math.floor(amount)
		syncCredits(player, profile)
		DataService.changed(player, true)
	end
end

function EconomyService.addDust(player: Player, amount: number)
	local profile = DataService.get(player)
	if profile and amount > 0 then
		profile.currency.dust += math.floor(amount)
		DataService.changed(player, true)
	end
end

-- Pay Credits (skill ranks, retune, HQ, styles). Bots pay nothing.
function EconomyService.spend(hero: any, cost: number): boolean
	if cost <= 0 then
		return true
	end
	if not hero.player then
		return true
	end
	local profile = DataService.get(hero.player)
	if not profile or not Progress.spend(profile.currency, cost) then
		return false
	end
	syncCredits(hero.player, profile)
	DataService.changed(hero.player, true)
	DataService.saveSoon(hero.player)
	return true
end

-- Give Credits back into the bank (a respec refunds what ranks cost)
function EconomyService.refund(hero: any, amount: number)
	if not hero.player or amount <= 0 then
		return
	end
	local profile = DataService.get(hero.player)
	if profile then
		profile.currency.banked += math.floor(amount)
		syncCredits(hero.player, profile)
		DataService.changed(hero.player, true)
	end
end

-- An earned reward (incident, rescue, contract, mission, boss tier). Returns credits, renown.
function EconomyService.reward(
	player: Player,
	action: string,
	zoneLevel: number,
	opts: { [string]: any }?
): (number, number)
	local credits, renown = Progress.earn(Config, action, zoneLevel, EconomyService.bonus(player, opts))
	EconomyService.addCredits(player, credits)
	EconomyService.addRenown(player, renown)
	Net.fire("Toast", player, { id = "reward", credits = credits, renown = renown, action = action })
	return credits, renown
end

local function checkFriends(player: Player)
	friendsOf[player] = friendsOf[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
			if ok and isFriend then
				friendsOf[player][other] = true
				friendsOf[other] = friendsOf[other] or {}
				friendsOf[other][player] = true
			end
		end
	end
end

function EconomyService.friends(player: Player): number
	return friendCount(player)
end

function EconomyService.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkFriends, player)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(checkFriends, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		friendsOf[player] = nil
		for _, set in friendsOf do
			set[player] = nil
		end
	end)
	DataService.Loaded:Connect(syncCredits)
end

return EconomyService
