--!strict
-- Inventory: gear actions on a saved profile (spec: Gear.Equip, Gear.Upgrade, Gear.Salvage, Gear.Retune,
-- Style.Apply; Style collection, salvage and upgrade). Pure, so every rule is unit tested; GearService
-- calls these and then saves. Each returns ok plus a reason the client shows when it is refused.
-- Gear is account-wide: a piece is worn by at most one character, and a worn piece cannot be salvaged.

local GearMath = if script then require(script.Parent.GearMath) else (require :: any)("./GearMath")
local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")
local Progress = if script then require(script.Parent.Progress) else (require :: any)("./Progress")

local Bits = ProfileSchema.Bits

local Inventory = {}

function Inventory.find(profile: any, id: number): (any?, number?)
	for i, piece in profile.stash do
		if piece.id == id then
			return piece, i
		end
	end
	return nil, nil
end

-- Which character index wears this piece (nil when it sits in the stash)
function Inventory.wornBy(profile: any, id: number): number?
	for ci, c in profile.characters do
		if table.find(c.equipment, id) then
			return ci
		end
	end
	return nil
end

function Inventory.worn(profile: any, char: any): { any }
	local out = {}
	for _, id in char.equipment do
		if id ~= 0 then
			local piece = Inventory.find(profile, id)
			if piece then
				table.insert(out, piece)
			end
		end
	end
	return out
end

function Inventory.hasStyle(profile: any, styleId: number): boolean
	return styleId > 0 and Bits.get(profile.styles, styleId)
end

-- A new piece from a drop. Its style unlocks forever. A full stash turns it into Lumen Dust instead.
-- Returns "stashed" or "salvaged", the piece (with its id) and any Dust gained.
function Inventory.add(config: any, profile: any, piece: any): (string, any, number)
	piece.id = profile.nextPieceId
	profile.nextPieceId += 1
	if piece.style > 0 then
		Bits.set(profile.styles, piece.style)
	end
	profile.stats.drops += 1
	if #profile.stash >= config.Gear.stashCap then
		local dust = GearMath.salvageValue(config, piece)
		profile.currency.dust += dust
		return "salvaged", piece, dust
	end
	table.insert(profile.stash, piece)
	return "stashed", piece, 0
end

-- Wear piece `id` in slot `slot` (1-8) on `char`, or clear the slot with id 0
function Inventory.equip(config: any, profile: any, char: any, id: number, slot: number): (boolean, string?)
	if slot < 1 or slot > #config.Gear.slotOrder then
		return false, "bad slot"
	end
	if id == 0 then
		char.equipment[slot] = 0
		return true, nil
	end
	local piece = Inventory.find(profile, id)
	if not piece then
		return false, "not owned"
	end
	if piece.slot ~= slot then
		return false, "wrong slot"
	end
	if not GearMath.canWear(config, char.level, piece) then
		return false, "level"
	end
	local by = Inventory.wornBy(profile, id)
	local me = table.find(profile.characters, char)
	if by and by ~= me then
		return false, "worn by another hero"
	end
	char.equipment[slot] = id
	return true, nil
end

-- Salvage up to 20 pieces into Lumen Dust. Refused whole if any is worn or missing.
function Inventory.salvage(config: any, profile: any, ids: { number }): (boolean, string?, number)
	if #ids == 0 or #ids > config.Gear.salvage.maxPerRequest then
		return false, "count", 0
	end
	local seen = {}
	for _, id in ids do
		if seen[id] then
			return false, "duplicate", 0
		end
		seen[id] = true
		if not Inventory.find(profile, id) then
			return false, "not owned", 0
		end
		if Inventory.wornBy(profile, id) then
			return false, "worn", 0
		end
	end
	local dust = 0
	for _, id in ids do
		local piece, i = Inventory.find(profile, id)
		if piece and i then
			dust += GearMath.salvageValue(config, piece)
			table.remove(profile.stash, i)
		end
	end
	profile.currency.dust += dust
	return true, nil, dust
end

function Inventory.upgrade(config: any, profile: any, id: number): (boolean, string?, number)
	local piece = Inventory.find(profile, id)
	if not piece then
		return false, "not owned", 0
	end
	if piece.slot == table.find(config.Gear.slotOrder, "gadget") then
		return false, "gadget", 0
	end
	local cost = GearMath.upgradeCost(config, piece)
	if not cost then
		return false, "max", 0
	end
	if profile.currency.dust < cost then
		return false, "dust", cost
	end
	profile.currency.dust -= cost
	piece.up += 1
	return true, nil, cost
end

function Inventory.retune(
	config: any,
	rng: any,
	profile: any,
	id: number,
	index: number
): (boolean, string?, number)
	local piece = Inventory.find(profile, id)
	if not piece then
		return false, "not owned", 0
	end
	if not piece.bonus[index] then
		return false, "no bonus", 0
	end
	if piece.retunes >= config.Gear.retune.max then
		return false, "locked", 0
	end
	local cost = GearMath.retuneCost(config, piece)
	if not Progress.canSpend(profile.currency, cost) then
		return false, "credits", cost
	end
	if not GearMath.retune(config, rng, piece, index) then
		return false, "no stat", 0
	end
	Progress.spend(profile.currency, cost)
	return true, nil, cost
end

-- Show an unlocked style over slot `slot` (0 shows the worn piece's own style again)
function Inventory.showStyle(
	config: any,
	profile: any,
	char: any,
	slot: number,
	styleId: number
): (boolean, string?)
	if slot < 1 or slot > #config.Gear.slotOrder then
		return false, "bad slot"
	end
	if styleId ~= 0 then
		if not Inventory.hasStyle(profile, styleId) then
			return false, "locked"
		end
		local styleSlot = GearMath.styleParts(styleId)
		if styleSlot ~= slot then
			return false, "wrong slot"
		end
	end
	char.shown[slot] = styleId
	return true, nil
end

-- The style each slot shows: the chosen style, else the worn piece's style, else 0 (nothing)
function Inventory.shownStyles(profile: any, char: any): { number }
	local out = table.create(8, 0)
	for slot = 1, 8 do
		local chosen = char.shown[slot]
		if chosen ~= 0 and Inventory.hasStyle(profile, chosen) then
			out[slot] = chosen
		else
			local id = char.equipment[slot]
			local piece = if id ~= 0 then Inventory.find(profile, id) else nil
			out[slot] = if piece then piece.style else 0
		end
	end
	return out
end

return Inventory
