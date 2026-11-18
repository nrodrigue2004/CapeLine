-- TravelStyleService: the travel power style a hero wears (spec: Hero MMO features > Travel power styles; H8).
-- TravelStyleSet (mobility index, slot) wears an owned style for that mobility on the active hero (0 = the
-- plain look); the player attribute TravelStyle carries the style id for the hero's current mobility, and
-- every device draws it (TravelStyleFx). Looks only: nothing here touches a speed or the speed checks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local TravelStyleRules = require(Shared:WaitForChild("TravelStyleRules"))

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)

local TravelStyleService = {}

local watched: { [Player]: boolean } = {} -- players whose Mobility attribute is listened to

local function show(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local c = ProfileSchema.active(profile)
	local id = TravelStyleRules.shown(Config, profile, c)
	player:SetAttribute("TravelStyle", if id ~= 0 then id else nil)
end
TravelStyleService.show = show

local function set(player: Player, mi: number, slot: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local mobility = Config.Move.mobilityOrder[mi]
	if not mobility or not TravelStyleRules.canWear(Config, profile, mobility, slot) then
		return
	end
	local c = ProfileSchema.active(profile)
	c.mmo.travel[mi] = slot
	local s = TravelStyleRules.at(Config, mobility, slot)
	Analytics.event(player, "travel_style", if s then s.id else 0, { mobility })
	show(player)
	DataService.changed(player)
	DataService.saveSoon(player)
end

function TravelStyleService.init()
	Net.on("TravelStyleSet", set)
	HeroService.Spawned:Connect(function(hero: any)
		local player = hero.player
		if player then
			show(player)
		end
	end)
	DataService.Loaded:Connect(function(player: Player)
		show(player) -- a slot switch fires Loaded again: the new hero's style
		if watched[player] then
			return -- one Mobility listener a player (Loaded fires again on every slot switch)
		end
		watched[player] = true
		-- a mobility swap at a safehouse changes which style shows
		player:GetAttributeChangedSignal("Mobility"):Connect(function()
			show(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		watched[player] = nil
	end)
end

return TravelStyleService
