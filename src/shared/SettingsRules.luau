--!strict
-- SettingsRules: the saved settings (spec: Settings.Set {key, value} "Valid key"; Accessibility). Pure, so
-- Lune tests it. Settings live on the profile as { [id] = number } (toggles are 0 or 1), plus a mute list.
-- * defaults(Config): every key at its default. clean(Config, s): any save into valid numbers.
-- * set(Config, s, keyIndex, value): one change, clamped and snapped to the key's step; false if invalid.
-- * mute(Config, list, userId, on): the mute list, newest kept, at most Config.Settings.maxMutes.

local SettingsRules = {}

export type Key = {
	id: string,
	name: string,
	kind: string,
	options: { string }?,
	lo: number?,
	hi: number?,
	step: number?,
	default: number,
	unit: string?,
}

local function bounds(k: Key): (number, number, number)
	if k.kind == "toggle" then
		return 0, 1, 1
	elseif k.kind == "choice" then
		return 0, #(k.options or {}) - 1, 1
	end
	return k.lo or 0, k.hi or 1, k.step or 1
end

-- A valid value for a key, or nil
function SettingsRules.value(k: Key, v: any): number?
	if type(v) == "boolean" then
		v = if v then 1 else 0
	end
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	local lo, hi, step = bounds(k)
	local snapped = lo + math.floor((v - lo) / step + 0.5) * step
	return math.clamp(snapped, lo, hi)
end

function SettingsRules.defaults(Config: any): { [string]: number }
	local out = {}
	for _, k in Config.Settings.keys do
		out[k.id] = k.default
	end
	return out
end

-- Any saved settings table into valid numbers (old saves: textSize 1 to 1.6 was a scale, booleans)
function SettingsRules.clean(Config: any, s: any): { [string]: number }
	local out = SettingsRules.defaults(Config)
	if type(s) ~= "table" then
		return out
	end
	for _, k in Config.Settings.keys do
		local v = s[k.id]
		if k.id == "textSize" and type(v) == "number" and v > 0 and v <= 2 then
			v = v * 100
		end
		local ok = SettingsRules.value(k, v)
		if ok ~= nil then
			out[k.id] = ok
		end
	end
	return out
end

function SettingsRules.key(Config: any, index: number): Key?
	return Config.Settings.keys[index]
end

-- One change; true when it was valid (the value is stored clamped and snapped)
function SettingsRules.set(Config: any, s: { [string]: number }, index: number, v: number): boolean
	local k = SettingsRules.key(Config, index)
	if not k then
		return false
	end
	local ok = SettingsRules.value(k, v)
	if ok == nil then
		return false
	end
	s[k.id] = ok
	return true
end

-- Add or remove a muted user id; the oldest drop off past the cap. Returns the list.
function SettingsRules.mute(Config: any, list: { number }, userId: number, on: boolean): { number }
	local at = table.find(list, userId)
	if at then
		table.remove(list, at)
	end
	if on and userId > 0 and userId == math.floor(userId) then
		table.insert(list, userId)
		while #list > Config.Settings.maxMutes do
			table.remove(list, 1)
		end
	end
	return list
end

return SettingsRules
