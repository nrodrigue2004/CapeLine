-- ShopService: Gizmo's shop at HQ and wearing what was bought (spec: Hero HQ > Gizmo's shop "Base styles
-- for Credits (500 to 3,000), Lumen Dust upgrade bench"; Revenue levers "Effect colors", "Emotes and landing
-- poses").
-- * GizmoBuy: a base style for Credits only, inside the HQ. It unlocks the style for the account, the same
--   as looting it; the Style Collection shows it. (The Dust bench is the GEAR screen's Upgrade.)
-- * TintSet and LandingSet: wear an owned effect colour or landing pose (0 takes it off). Looks only.
-- * EmotePlay: an owned emote or landing pose plays on the hero for everyone (the Emote attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ShopRules = require(Shared:WaitForChild("ShopRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EconomyService = require(script.Parent.EconomyService)
local CreatorService = require(script.Parent.CreatorService)

local ShopService = {}

local S = Config.Shop
local Bits = ProfileSchema.Bits
local lastEmote: { [Player]: number } = {}
local emoteSeq = 0

local function gizmoBuy(player: Player, styleId: number)
	local hero = HeroService.get(player)
	local profile = DataService.get(player)
	if not hero or not profile then
		return
	end
	if not CreatorService.inHq(hero) then
		Net.fire("Toast", player, { id = "shopRefused", reason = "hq" })
		return
	end
	local price = ShopRules.gizmoPrice(Config, styleId)
	if not price then
		return
	end
	if Bits.get(profile.styles, styleId) then
		Net.fire("Toast", player, { id = "shopRefused", reason = "owned" })
		return
	end
	if not EconomyService.spend(hero, price) then
		Net.fire("Toast", player, { id = "shopRefused", reason = "credits", cost = price })
		return
	end
	Bits.set(profile.styles, styleId)
	DataService.changed(player)
	DataService.saveSoon(player)
	Net.fire("Toast", player, { id = "styleBought", style = styleId, cost = price })
end

local function tintSet(player: Player, n: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if n ~= 0 and not bit32.btest(profile.purchases.tints, bit32.lshift(1, n)) then
		return
	end
	ProfileSchema.active(profile).tint = n
	CreatorService.showName(player)
	DataService.changed(player)
	DataService.saveSoon(player)
end

local function landingSet(player: Player, n: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local row = S.emotes[n]
	if n ~= 0 and (not row or not row.landing or not Bits.get(profile.emotes, n)) then
		return
	end
	ProfileSchema.active(profile).landing = n
	CreatorService.showName(player)
	DataService.changed(player)
	DataService.saveSoon(player)
end

local function emotePlay(player: Player, n: number)
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if not profile or not hero or not hero.alive or hero.downed then
		return
	end
	if not S.emotes[n] or not Bits.get(profile.emotes, n) then
		return
	end
	local now = os.clock()
	if now - (lastEmote[player] or 0) < S.emoteRate then
		return
	end
	lastEmote[player] = now
	emoteSeq = (emoteSeq + 1) % 1000
	-- emote id x 1000 + a sequence, so the same emote twice still changes the attribute
	player:SetAttribute("Emote", n * 1000 + emoteSeq)
end

function ShopService.init()
	Net.on("GizmoBuy", gizmoBuy)
	Net.on("TintSet", tintSet)
	Net.on("LandingSet", landingSet)
	Net.on("EmotePlay", emotePlay)
	Players.PlayerRemoving:Connect(function(player)
		lastEmote[player] = nil
	end)
end

return ShopService
