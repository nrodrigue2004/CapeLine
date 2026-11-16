--!strict
-- WeaponRules: the weapon slot's rules (nate's hero creator plan, 2026-11-16; Config.Weapons). Pure, so Lune
-- tests it.
-- * Ownership is account-wide: Bare Fists (price 0) is always owned; the creator's free pick, the Weapon
--   Rack (Credits) and the Robux shop (the 5 Exotic weapons) set profile.weaponsOwned.
-- * Each weapon keeps its Mastery points and its look in profile.weapons[id as text] (WEAPON_FIELDS).
-- * A weapon look travels as a 12-byte buffer: id, style, finish, main, trim, glow, glow strength, flags
--   (bit 0 the emblem shows), trail, 3 reserved.
-- * Mastery: points from hits and defeats; X, C and V unlock at 25, 75 and 150 mastery (a level is
--   Config.Weapons.mastery.perLevel points), the Mastered glow at 300.

local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")

local Bits = ProfileSchema.Bits
local FIELDS = ProfileSchema.WEAPON_FIELDS

local WeaponRules = {}

WeaponRules.LOOK_SIZE = 12

export type Weapon = {
	id: number,
	family: string,
	name: string,
	complexity: number,
	text: string,
	price: number?, -- Credits at the Weapon Rack (0 = always owned)
	robux: string?, -- the Config.Shop product that sells it
}

export type WeaponLook = {
	id: number,
	style: number,
	finish: number,
	main: number,
	trim: number,
	glow: number,
	glowLevel: number,
	emblem: boolean,
	trail: number,
}

local cache: { [any]: { Weapon } } = {}

function WeaponRules.list(Config: any): { Weapon }
	local hit = cache[Config]
	if hit then
		return hit
	end
	local out: { Weapon } = {}
	for _, row in Config.Weapons.list do
		local kind, arg = string.match(row[6], "^(%a+):(.+)$")
		out[row[1]] = {
			id = row[1],
			family = row[2],
			name = row[3],
			complexity = row[4],
			text = row[5],
			price = if kind == "credits" then tonumber(arg) else nil,
			robux = if kind == "robux" then arg else nil,
		}
	end
	cache[Config] = out
	return out
end

function WeaponRules.get(Config: any, id: number): Weapon?
	return WeaponRules.list(Config)[id]
end

function WeaponRules.playable(Config: any, id: number): boolean
	return table.find(Config.Weapons.playable, id) ~= nil
end

function WeaponRules.owned(Config: any, profile: any, id: number): boolean
	local w = WeaponRules.get(Config, id)
	if not w then
		return false
	end
	if w.price == 0 then
		return true
	end
	return profile ~= nil and Bits.get(profile.weaponsOwned, id)
end

-- The creator's free pick: any weapon the Rack sells (never a Robux one), playable in this build
function WeaponRules.freePickOk(Config: any, id: number): boolean
	local w = WeaponRules.get(Config, id)
	return w ~= nil and w.price ~= nil and WeaponRules.playable(Config, id)
end

-- The Weapon Rack: can this be bought for Credits now? Returns ok, reason, price.
function WeaponRules.buyOk(Config: any, profile: any, id: number, credits: number): (boolean, string?, number)
	local w = WeaponRules.get(Config, id)
	if not w then
		return false, "weapon", 0
	end
	if WeaponRules.owned(Config, profile, id) then
		return false, "owned", 0
	end
	local price = w.price
	if not price then
		return false, "robux", 0
	end
	if credits < price then
		return false, "credits", price
	end
	return true, nil, price
end

function WeaponRules.grant(profile: any, id: number): boolean
	if Bits.get(profile.weaponsOwned, id) then
		return false
	end
	Bits.set(profile.weaponsOwned, id)
	return true
end

-- A weapon's saved numbers as a table (defaults for a weapon never touched)
function WeaponRules.state(profile: any, id: number): { [string]: number }
	local nums = profile and profile.weapons and profile.weapons[tostring(id)]
	local out = {}
	for i, f in FIELDS do
		out[f] = if nums and type(nums[i]) == "number" then nums[i] else 0
	end
	if out.style == 0 then
		out.style = 1
	end
	if out.finish == 0 then
		out.finish = 1
	end
	return out
end

local function store(profile: any, id: number, st: { [string]: number })
	local nums = {}
	for i, f in FIELDS do
		nums[i] = st[f] or 0
	end
	profile.weapons[tostring(id)] = nums
end

function WeaponRules.lookOf(profile: any, id: number): WeaponLook
	local st = WeaponRules.state(profile, id)
	return {
		id = id,
		style = st.style,
		finish = st.finish,
		main = st.main,
		trim = st.trim,
		glow = st.glow,
		glowLevel = st.glowLevel,
		emblem = st.emblem == 1,
		trail = st.trail,
	}
end

-- Every field in range: a weapon that exists, a style and finish it has, colours on the palette (0 = the
-- hero's own), a glow strength and an earned trail (0 = none)
function WeaponRules.lookOk(Config: any, look: WeaponLook): (boolean, string?)
	local w = WeaponRules.get(Config, look.id)
	if not w then
		return false, "weapon"
	end
	local W = Config.Weapons
	if look.style < 1 or look.style > #W.styles[w.family] then
		return false, "style"
	end
	if look.finish < 1 or look.finish > #W.finishes then
		return false, "finish"
	end
	local pal = #Config.Creator.palette
	for _, c in { look.main, look.trim, look.glow } do
		if c < 0 or c > pal then
			return false, "color"
		end
	end
	if look.glowLevel < 0 or look.glowLevel > W.glowLevels then
		return false, "glow"
	end
	if look.trail < 0 or look.trail >= #W.trails then
		return false, "trail"
	end
	return true, nil
end

function WeaponRules.setLook(profile: any, look: WeaponLook)
	local st = WeaponRules.state(profile, look.id)
	st.style, st.finish = look.style, look.finish
	st.main, st.trim, st.glow, st.glowLevel = look.main, look.trim, look.glow, look.glowLevel
	st.emblem = if look.emblem then 1 else 0
	st.trail = look.trail
	store(profile, look.id, st)
end

function WeaponRules.encodeLook(look: WeaponLook): buffer
	local b = buffer.create(WeaponRules.LOOK_SIZE)
	local vals = {
		look.id,
		look.style,
		look.finish,
		look.main,
		look.trim,
		look.glow,
		look.glowLevel,
		if look.emblem then 1 else 0,
		look.trail,
	}
	for i, v in vals do
		buffer.writeu8(b, i - 1, math.clamp(math.floor(tonumber(v) or 0), 0, 255))
	end
	return b
end

function WeaponRules.decodeLook(b: buffer): WeaponLook?
	if buffer.len(b) ~= WeaponRules.LOOK_SIZE or buffer.readu8(b, 0) == 0 then
		return nil
	end
	return {
		id = buffer.readu8(b, 0),
		style = buffer.readu8(b, 1),
		finish = buffer.readu8(b, 2),
		main = buffer.readu8(b, 3),
		trim = buffer.readu8(b, 4),
		glow = buffer.readu8(b, 5),
		glowLevel = buffer.readu8(b, 6),
		emblem = bit32.btest(buffer.readu8(b, 7), 1),
		trail = buffer.readu8(b, 8),
	}
end

-- Mastery level from points (0 to max)
function WeaponRules.masteryLevel(Config: any, points: number): number
	local M = Config.Weapons.mastery
	return math.min(M.max, math.floor(points / M.perLevel))
end

-- Is skill key ("Z", "X", "C", "V") open at this many mastery points?
function WeaponRules.skillOpen(Config: any, points: number, key: string): boolean
	local need = Config.Weapons.mastery.skills[key]
	return need ~= nil and WeaponRules.masteryLevel(Config, points) >= need
end

-- Add mastery points to a weapon; returns the new level and the skill keys that just opened
function WeaponRules.addMastery(Config: any, profile: any, id: number, points: number): (number, { string })
	local st = WeaponRules.state(profile, id)
	local before = WeaponRules.masteryLevel(Config, st.mastery)
	local cap = Config.Weapons.mastery.max * Config.Weapons.mastery.perLevel
	st.mastery = math.min(cap, st.mastery + math.max(0, points))
	store(profile, id, st)
	local after = WeaponRules.masteryLevel(Config, st.mastery)
	local opened = {}
	for _, key in { "Z", "X", "C", "V" } do
		local need = Config.Weapons.mastery.skills[key]
		if before < need and after >= need then
			table.insert(opened, key)
		end
	end
	return after, opened
end

-- The carried weapon of a character (0 or a weapon not owned falls back to the default, Bare Fists)
function WeaponRules.carried(Config: any, profile: any, char: any): number
	local id = char and char.weapon or 0
	if id ~= 0 and WeaponRules.owned(Config, profile, id) then
		return id
	end
	return Config.Weapons.defaultWeapon
end

return WeaponRules
