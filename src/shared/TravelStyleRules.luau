-- TravelStyleRules: travel power styles as pure rules (spec: Hero MMO features > Travel power styles; H8).
-- A style's id is (mobility index - 1) * perMobility + its place (Config.TravelStyles). Owned: a shop or pass
-- style's bit in profile.mmo.travel, or an earned style whose condition holds now (a Badge Book group done,
-- any mentor's quest line done), so an earned style never needs granting. Each hero wears one per mobility
-- (mmo.travel, 0 = the plain look). Looks only: nothing here reads or writes a speed.

local Bits = if script
	then require(script.Parent.ProfileSchema).Bits
	else (require :: any)("./ProfileSchema").Bits
local BadgeRules = if script then require(script.Parent.BadgeRules) else (require :: any)("./BadgeRules")
local MentorRules = if script then require(script.Parent.MentorRules) else (require :: any)("./MentorRules")

local TravelStyleRules = {}

export type Style = {
	id: number,
	mobility: string,
	slot: number, -- 1 to perMobility
	name: string,
	source: string,
	[string]: any,
}

local cache: { [any]: { Style } } = {}

-- Every style in id order
function TravelStyleRules.list(Config: any): { Style }
	local hit = cache[Config]
	if hit then
		return hit
	end
	local TS = Config.TravelStyles
	local out = {}
	for mi, m in Config.Move.mobilityOrder do
		for i, row in TS.byMobility[m] or {} do
			local s = table.clone(row) :: any
			s.id = (mi - 1) * TS.perMobility + i
			s.mobility = m
			s.slot = i
			table.insert(out, s)
		end
	end
	cache[Config] = out
	return out
end

function TravelStyleRules.byId(Config: any, id: number): Style?
	for _, s in TravelStyleRules.list(Config) do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- The style a mobility's slot names (slot 0 = none)
function TravelStyleRules.at(Config: any, mobility: string, slot: number): Style?
	local mi = table.find(Config.Move.mobilityOrder, mobility)
	if not mi or slot < 1 or slot > Config.TravelStyles.perMobility then
		return nil
	end
	return TravelStyleRules.byId(Config, (mi - 1) * Config.TravelStyles.perMobility + slot)
end

-- Is an earned style's condition met on this account now?
function TravelStyleRules.earnedNow(Config: any, profile: any, s: Style): boolean
	if s.source == "badge" then
		local g
		for _, row in Config.Badges.groups do
			if row.id == s.group then
				g = row
			end
		end
		local words = profile.mmo and profile.mmo.badges
		return g ~= nil and words ~= nil and BadgeRules.count(Config.Badges, words, g.id) >= #g.badges
	elseif s.source == "mentor" then
		return MentorRules.pride(Config.Mentors, profile)
	end
	return false
end

function TravelStyleRules.owned(Config: any, profile: any, id: number): boolean
	local s = TravelStyleRules.byId(Config, id)
	if not s then
		return false
	end
	local words = profile.mmo and profile.mmo.travel
	return (words ~= nil and Bits.get(words, id)) or TravelStyleRules.earnedNow(Config, profile, s)
end

-- May this hero wear slot `slot` of `mobility`? (0 always: the plain look)
function TravelStyleRules.canWear(Config: any, profile: any, mobility: string, slot: number): boolean
	if slot == 0 then
		return table.find(Config.Move.mobilityOrder, mobility) ~= nil
	end
	local s = TravelStyleRules.at(Config, mobility, slot)
	return s ~= nil and TravelStyleRules.owned(Config, profile, s.id)
end

-- The style id a hero shows for their current mobility (0 = none)
function TravelStyleRules.shown(Config: any, profile: any, char: any): number
	local mi = table.find(Config.Move.mobilityOrder, char.mobility or "flight")
	local slots = char.mmo and char.mmo.travel
	local slot = mi and slots and slots[mi] or 0
	if slot == 0 or not mi then
		return 0
	end
	local s = TravelStyleRules.at(Config, char.mobility or "flight", slot)
	return if s and TravelStyleRules.owned(Config, profile, s.id) then s.id else 0
end

-- Give a shop or pass style (true when new)
function TravelStyleRules.give(profile: any, id: number): boolean
	if Bits.get(profile.mmo.travel, id) then
		return false
	end
	Bits.set(profile.mmo.travel, id)
	return true
end

return TravelStyleRules
