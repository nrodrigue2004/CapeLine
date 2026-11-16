-- PurchaseService: Robux purchases (spec: Revenue levers; Pay-to-win check; Screens > Robux Shop; M9 test
-- "Test purchases grant the right item once; replaying a receipt grants nothing"). Ported from the Ragdoll
-- Rides receipt flow.
-- * ShopBuy: the shop asks to buy an item. The server checks the place (HQ, a safehouse or the menu, never
--   within 10 s of a fight; ShopRules.canOpen), that the item is not owned (slot 4 needs slot 3), then shows
--   the Roblox prompt. While an item's id is 0 (not made on the Creator Dashboard yet) Studio grants it
--   through the same path with a test receipt, and a live server says it is not on sale yet.
-- * ProcessReceipt: one handler for every product. ShopRules.grant records the purchase id and grants once;
--   the answer is PurchaseGranted only once the save worked (or the id was already there), so a replay or
--   a retry never grants twice.
-- * Game passes (Quick Swap, 2x Credits and Renown) are checked on join and after a pass purchase.
-- * The starter pack offer shows once, after the first world boss, and is easy to dismiss.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ShopRules = require(Shared:WaitForChild("ShopRules"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local SafehouseService = require(script.Parent.SafehouseService)
local BossService = require(script.Parent.BossService)
local CreatorService = require(script.Parent.CreatorService)

local PurchaseService = {}

local KEYS = ShopRules.keys(Config)
local testSeq = 0

local function landed(player: Player, got: { [string]: any }?)
	CreatorService.showName(player)
	DataService.changed(player)
	Net.fire("ShopResult", player, {
		ok = true,
		key = got and got.key,
		kind = got and got.kind,
		pieces = got and got.pieces,
	})
end

-- Grant a product through the receipt rules (ProcessReceipt and Studio's test receipts)
function PurchaseService.grant(player: Player, key: string, receiptId: string): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local ok, got = ShopRules.grant(Config, profile, key, receiptId)
	if ok then
		landed(player, got)
		DataService.saveSoon(player)
	end
	return ok
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local key = ShopRules.byProductId(Config, receipt.ProductId)
	if not player or not key then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(receipt.PurchaseId)
	if ShopRules.hasReceipt(profile, id) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted
	end
	local ok, got = ShopRules.grant(Config, profile, key, id)
	if not ok then
		warn(string.format("[Purchase] %s did not grant", key))
	end
	landed(player, got)
	if not DataService.save(player, false) and not DataService.isMemoryMode() then
		-- recorded in this session: Roblox asks again and the receipt id stops a second grant
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function checkPasses(player: Player)
	local profile = DataService.waitFor(player)
	if not profile then
		return
	end
	local changed = false
	for key, row in Config.Shop.passes do
		if row.id ~= 0 and not profile.purchases.passes[key] then
			local ok, owns =
				pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, row.id)
			if ok and owns and ShopRules.grantPass(profile, key) then
				changed = true
			end
		end
	end
	if changed then
		DataService.changed(player)
		DataService.saveSoon(player)
	end
end

-- Where the hero is for the shop rule: "hq", "safehouse", or "menu" (anywhere else, out of any scene)
local function whereOf(hero: any): string
	if CreatorService.inHq(hero) then
		return "hq"
	end
	if hero.scene then
		return "scene"
	end
	if SafehouseService.near(hero) then
		return "safehouse"
	end
	return "menu"
end

local function buy(player: Player, index: number)
	local key = KEYS[index]
	local hero = HeroService.get(player)
	local profile = DataService.get(player)
	if not key or not hero or not profile then
		return
	end
	local function no(reason: string)
		Net.fire("ShopResult", player, { ok = false, key = key, reason = reason })
	end
	local lastCombat = math.max(hero.lastDamaged or -1e9, hero.lastCast or -1e9)
	local open, why = ShopRules.canOpen(Config, whereOf(hero), lastCombat, os.clock())
	if not open then
		no(why :: string)
		return
	end
	local can, reason = ShopRules.available(Config, profile, key)
	if not can then
		no(reason :: string)
		return
	end
	local row, kind = ShopRules.item(Config, key)
	if not row then
		return
	end
	if row.id == 0 then
		if RunService:IsStudio() then
			-- Studio test purchase: the same grant path with a test receipt id
			testSeq += 1
			local receiptId = string.format("studio-%s-%d-%d", key, os.time(), testSeq)
			if kind == "pass" then
				if ShopRules.grantPass(profile, key) then
					landed(player, { key = key, kind = "pass", pieces = {} })
				end
			else
				PurchaseService.grant(player, key, receiptId)
			end
			return
		end
		no("soon")
		return
	end
	if kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, row.id)
	else
		MarketplaceService:PromptProductPurchase(player, row.id)
	end
end

function PurchaseService.init()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local key = ShopRules.byPassId(Config, passId)
		local profile = DataService.get(player)
		if purchased and key and profile and ShopRules.grantPass(profile, key) then
			landed(player, { key = key, kind = "pass", pieces = {} })
			DataService.saveSoon(player)
		end
	end)
	Net.on("ShopBuy", buy)
	Net.on("ShopDismiss", function(player)
		local profile = DataService.get(player)
		if profile then
			profile.shop.starterSeen = 1
			DataService.saveSoon(player)
		end
	end)
	DataService.Loaded:Connect(function(player)
		task.spawn(checkPasses, player)
	end)
	-- the starter pack: shown once after the first world boss
	BossService.Rewarded:Connect(function(player)
		local profile = DataService.get(player)
		if profile and ShopRules.starterDue(Config, profile) then
			profile.shop.starterSeen = 1
			task.delay(6, function()
				if player.Parent then
					Net.fire("ShopOffer", player, { key = "starter", index = table.find(KEYS, "starter") })
				end
			end)
		end
	end)
end

-- Dev: replay a receipt id (the "grants nothing" check in Studio)
function PurchaseService.replay(player: Player, key: string, receiptId: string): boolean
	return PurchaseService.grant(player, key, receiptId)
end

return PurchaseService
