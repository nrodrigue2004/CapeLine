--!strict
-- ShopRules: what the Robux shop and Gizmo's shop sell and how a purchase lands on the profile (spec:
-- Revenue levers; Pay-to-win check; Screens > Robux Shop, Gizmo's shop). Pure, so Lune tests it.
-- * grant(profile, key, receiptId): a developer product's grant, once per receipt id. A replayed receipt
--   grants nothing (the last 50 receipt ids live on the profile). Packs unlock creator pieces, the
--   starter pack its pieces and emote, slots a character slot, tints an effect colour, emotes an emote.
--   Nothing touches a stat, gear, Dust, Credits, ranks or loot.
-- * owned(profile, key): already has everything the item gives (the shop shows OWNED and will not prompt).
-- * canOpen(where, lastCombat, now): only in HQ, safehouses and the menu, never mid-fight.
-- * gizmo(): the 40 base styles and their Credit prices; gizmoBuy spends Credits and unlocks the style.

local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")
local CreatorRules = if script
	then require(script.Parent.CreatorRules)
	else (require :: any)("./CreatorRules")
local GearMath = if script then require(script.Parent.GearMath) else (require :: any)("./GearMath")
local Progress = if script then require(script.Parent.Progress) else (require :: any)("./Progress")

local Bits = ProfileSchema.Bits

local ShopRules = {}

-- A product or pass row by key, and its kind ("pass" for game passes)
function ShopRules.item(Config: any, key: string): (any?, string?)
	local S = Config.Shop
	local row = S.products[key]
	if row then
		return row, row.kind
	end
	if S.passes[key] then
		return S.passes[key], "pass"
	end
	return nil, nil
end

-- Every item in shop order (the ShopBuy remote sends an index into this list)
function ShopRules.keys(Config: any): { string }
	local out = {}
	for _, tab in Config.Shop.tabs do
		for _, key in tab.items do
			table.insert(out, key)
		end
	end
	table.insert(out, "starter")
	return out
end

-- The product key for a Roblox product id (ProcessReceipt), or nil. Id 0 never matches.
function ShopRules.byProductId(Config: any, productId: number): string?
	if productId == 0 then
		return nil
	end
	for key, row in Config.Shop.products do
		if row.id == productId then
			return key
		end
	end
	return nil
end

function ShopRules.byPassId(Config: any, passId: number): string?
	if passId == 0 then
		return nil
	end
	for key, row in Config.Shop.passes do
		if row.id == passId then
			return key
		end
	end
	return nil
end

local function hasPieces(Config: any, profile: any, pack: number?): boolean
	for _, p in CreatorRules.packPieces(Config, pack) do
		if not Bits.get(profile.pieces, p.id) then
			return false
		end
	end
	return true
end

function ShopRules.owned(Config: any, profile: any, key: string): boolean
	local row, kind = ShopRules.item(Config, key)
	if not row then
		return false
	end
	if kind == "pass" then
		return profile.purchases.passes[key] == true
	elseif kind == "pack" then
		return hasPieces(Config, profile, row.pack)
	elseif kind == "starter" then
		return hasPieces(Config, profile, nil) and Bits.get(profile.emotes, Config.Shop.starter.emote)
	elseif kind == "slot" then
		return bit32.btest(profile.purchases.slots, bit32.lshift(1, row.slot))
	elseif kind == "tint" then
		return bit32.btest(profile.purchases.tints, bit32.lshift(1, row.tint))
	elseif kind == "emote" then
		return Bits.get(profile.emotes, row.emote)
	elseif kind == "weapon" then
		return Bits.get(profile.weaponsOwned, row.weapon)
	end
	return false
end

-- Can this be bought now? Slot 4 needs slot 3; nothing owned is sold twice.
function ShopRules.available(Config: any, profile: any, key: string): (boolean, string?)
	local row, kind = ShopRules.item(Config, key)
	if not row then
		return false, "item"
	end
	if ShopRules.owned(Config, profile, key) then
		return false, "owned"
	end
	if kind == "slot" and row.slot == 4 and not ShopRules.owned(Config, profile, "slot3") then
		return false, "slot3"
	end
	-- a weapon is only sold once it is playable (the creator plan builds the 36 in steps)
	if kind == "weapon" and not table.find(Config.Weapons.playable, row.weapon) then
		return false, "soon"
	end
	return true, nil
end

function ShopRules.hasReceipt(profile: any, receiptId: string): boolean
	return table.find(profile.purchases.receipts, receiptId) ~= nil
end

local function remember(profile: any, receiptId: string)
	local list = profile.purchases.receipts
	table.insert(list, receiptId)
	while #list > 50 do
		table.remove(list, 1)
	end
end

-- Apply a developer product. Returns granted, what (a short summary for the toast).
function ShopRules.grant(
	Config: any,
	profile: any,
	key: string,
	receiptId: string
): (boolean, { [string]: any }?)
	if ShopRules.hasReceipt(profile, receiptId) then
		return false, nil
	end
	local row, kind = ShopRules.item(Config, key)
	if not row or kind == "pass" then
		return false, nil
	end
	local got: { [string]: any } = { key = key, kind = kind, pieces = {} }
	if kind == "pack" or kind == "starter" then
		for _, p in CreatorRules.packPieces(Config, if kind == "pack" then row.pack else nil) do
			if CreatorRules.grant(profile, p) then
				table.insert(got.pieces, p.name)
			end
		end
		if kind == "starter" then
			Bits.set(profile.emotes, Config.Shop.starter.emote)
			profile.shop.starterSeen = 1
		end
	elseif kind == "slot" then
		profile.purchases.slots = bit32.bor(profile.purchases.slots, bit32.lshift(1, row.slot))
		got.slot = row.slot
	elseif kind == "tint" then
		profile.purchases.tints = bit32.bor(profile.purchases.tints, bit32.lshift(1, row.tint))
		got.tint = row.tint
	elseif kind == "emote" then
		Bits.set(profile.emotes, row.emote)
		got.emote = row.emote
	elseif kind == "weapon" then
		Bits.set(profile.weaponsOwned, row.weapon)
		got.weapon = row.weapon
	end
	remember(profile, receiptId)
	return true, got
end

function ShopRules.grantPass(profile: any, key: string): boolean
	if profile.purchases.passes[key] then
		return false
	end
	profile.purchases.passes[key] = true
	return true
end

-- Where the Robux shop may open. lastCombat = the last time the hero dealt or took damage.
function ShopRules.canOpen(Config: any, where: string, lastCombat: number, now: number): (boolean, string?)
	if not table.find(Config.Shop.openIn, where) then
		return false, "where"
	end
	if now - lastCombat < Config.Shop.combatLock then
		return false, "combat"
	end
	return true, nil
end

-- The starter pack offer: once, after the first world boss, never again once seen, dismissed or bought
function ShopRules.starterDue(Config: any, profile: any): boolean
	return profile.shop.starterSeen == 0
		and (profile.stats.bossesJoined or 0) >= 1
		and not ShopRules.owned(Config, profile, "starter")
end

-- Gizmo's 40 base styles: { id, price, row } in slot order
function ShopRules.gizmo(Config: any): { { id: number, price: number, row: any } }
	local G = Config.Gear
	local prices = Config.Shop.gizmo.tierPrice
	local out = {}
	for slotIdx, slot in G.slotOrder do
		for _, row in G.styles[slot] or {} do
			local price = if row.tier == "Shop" then row.price else prices[row.tier]
			if price then
				table.insert(out, { id = GearMath.styleId(slotIdx, row.n), price = price, row = row })
			end
		end
	end
	return out
end

function ShopRules.gizmoPrice(Config: any, styleId: number): number?
	for _, e in ShopRules.gizmo(Config) do
		if e.id == styleId then
			return e.price
		end
	end
	return nil
end

-- Buy a base style with Credits (on hand first, then banked). Returns ok, reason, price.
function ShopRules.gizmoBuy(Config: any, profile: any, styleId: number): (boolean, string?, number?)
	local price = ShopRules.gizmoPrice(Config, styleId)
	if not price then
		return false, "item", nil
	end
	if Bits.get(profile.styles, styleId) then
		return false, "owned", nil
	end
	if not Progress.spend(profile.currency, price) then
		return false, "credits", nil
	end
	Bits.set(profile.styles, styleId)
	return true, nil, price
end

return ShopRules
