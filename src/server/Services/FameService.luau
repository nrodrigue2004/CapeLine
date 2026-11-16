-- FameService: Fame for heroes, Infamy for villains, one bar with the same numbers (spec: Fame and Infamy).
-- Points come from every earn action (EconomyService.Earned: incidents 5, rescues 2 or 3 for villains,
-- contracts 10, missions 40, world boss tiers 20/30/50) and PvP wins (15, under the reward rules). Ranks 1 to
-- 10 pay titles, emotes, a frame, style pieces, a landing pose and the gold plate trim, once each.
-- The total and rank ride on player attributes (Fame, FameRank) for name plates. Nothing sold adds Fame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local PvpRules = require(Shared:WaitForChild("PvpRules"))
local GearMath = require(Shared:WaitForChild("GearMath"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EconomyService = require(script.Parent.EconomyService)
local GearService = require(script.Parent.GearService)

local Bits = ProfileSchema.Bits
local U = Config.Story.unlocks

local FameService = {}

local function charOf(player: Player): any?
	local profile = DataService.get(player)
	return profile and ProfileSchema.active(profile)
end

local function show(player: Player, fame: number)
	player:SetAttribute("Fame", fame)
	player:SetAttribute("FameRank", PvpRules.fameRank(Config, fame))
end

local function bit(profile: any, words: string, name: string)
	local n = U[words] and U[words][name]
	if n and profile[words] then
		Bits.set(profile[words], n)
	end
end

-- Pay a rank's rewards (each rank once: called only when the rank goes up)
local function payRank(player: Player, rank: number)
	local profile = DataService.get(player)
	local row = Config.Pvp.fame.ranks[rank]
	if not profile or not row then
		return
	end
	local r = row.reward
	if r.title then
		bit(profile, "titles", r.title)
	end
	if r.trim then
		bit(profile, "titles", r.trim)
	end
	if r.emote then
		bit(profile, "emotes", r.emote)
	end
	if r.frame then
		bit(profile, "frames", r.frame)
	end
	if r.style then
		local id = GearMath.questStyle(Config, r.style)
		if id then
			Bits.set(profile.styles, id)
			GearService.refresh(player)
		end
	end
	DataService.changed(player)
	DataService.saveSoon(player)
end

-- Add Fame (or Infamy) for an action; factor scales it (PvP reward rules). Returns points added.
function FameService.add(player: Player, action: string, factor: number?): number
	local c = charOf(player)
	local hero = HeroService.get(player)
	if not c or not hero then
		return 0
	end
	local points = math.floor(PvpRules.fameFor(Config, action, hero.side) * (factor or 1))
	if points <= 0 then
		return 0
	end
	local before = PvpRules.fameRank(Config, c.fame)
	c.fame = math.min(c.fame + points, 9999999)
	local after = PvpRules.fameRank(Config, c.fame)
	show(player, c.fame)
	for rank = before + 1, after do
		payRank(player, rank)
		Net.fire("Toast", player, { id = "fameRank", rank = rank, side = hero.side })
	end
	DataService.changed(player)
	return points
end

function FameService.init()
	EconomyService.Earned:Connect(function(player, action)
		FameService.add(player, action)
	end)
	DataService.Loaded:Connect(function(player)
		local c = charOf(player)
		if c then
			show(player, c.fame)
		end
	end)
end

return FameService
