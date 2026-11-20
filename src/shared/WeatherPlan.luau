--!strict
-- WeatherPlan (list-combat 2026-11-20, Everything Left 273): which weather the city has at a server time, and how
-- the sky looks while one weather blends into the next. Pure and seeded by the slot number (Config.Weather), so
-- every device works out the same sky, the same lightning and the same thunder with no remote. Fx.WeatherFx draws it.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local WeatherPlan = {}

export type Look = {
	air: { [string]: any },
	clouds: { cover: number, density: number },
	grade: { brightness: number, saturation: number, tint: { number } },
	rain: number,
	lightning: boolean,
}

local WINDOW = 8 -- slots folded before the asked one, so a slot's rules see the weather before it

local function u01(...: number): number
	return Rng.hash(...) / 4294967296
end

-- The raw roll of one slot (before the rules)
function WeatherPlan.roll(cfg: any, slot: number): string
	local total = 0
	for _, name in cfg.order do
		total += cfg.kinds[name].weight
	end
	local r = u01(cfg.seed, slot) * total
	for _, name in cfg.order do
		r -= cfg.kinds[name].weight
		if r < 0 then
			return name
		end
	end
	return cfg.order[1]
end

-- The rules on one slot given the weather before it: a kind with `after` needs that kind (or itself) first,
-- and no weather but clear runs two slots in a row
function WeatherPlan.rule(cfg: any, prev: string, want: string): string
	local k = want
	local after = cfg.kinds[k].after
	if after and prev ~= after and prev ~= k then
		k = after
	end
	if k == prev and k ~= "clear" then
		k = "clear"
	end
	return k
end

-- The weather of a slot and of the slot before it (one fold, so the pair always follows the rules)
function WeatherPlan.run(cfg: any, slot: number): (string, string)
	local prev = WeatherPlan.roll(cfg, slot - WINDOW)
	local cur = prev
	for s = slot - WINDOW + 1, slot do
		cur = WeatherPlan.rule(cfg, prev, WeatherPlan.roll(cfg, s))
		if s < slot then
			prev = cur
		end
	end
	return prev, cur
end

-- At server time t: the weather blending out, the weather blending in, how far (0..1, eased) and the slot
function WeatherPlan.at(cfg: any, t: number): (string, string, number, number)
	local slot = math.floor(t / cfg.slot)
	local prev, cur = WeatherPlan.run(cfg, slot)
	local since = t - slot * cfg.slot
	local k = math.clamp(since / cfg.fade, 0, 1)
	k = k * k * (3 - 2 * k)
	return prev, cur, k, slot
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local function value(row: any, base: any, key: string): any
	local v = row and row[key]
	if v == nil then
		v = base[key]
	end
	return v
end

local function blend(a: any, b: any, k: number): any
	if type(a) == "table" then
		local out = {}
		for i = 1, 3 do
			out[i] = lerp(a[i], b[i], k)
		end
		return out
	end
	return lerp(a, b, k)
end

-- The look between two kinds. base: the place's own sky ({ air = {...}, clouds = { cover, density } }), the value
-- a kind leaves out. Colours are { r, g, b } 0..255.
function WeatherPlan.mix(cfg: any, from: string, to: string, k: number, base: any): Look
	local a, b = cfg.kinds[from], cfg.kinds[to]
	local air = {}
	for key in base.air do
		air[key] = blend(value(a.air, base.air, key), value(b.air, base.air, key), k)
	end
	local ca = a.clouds or base.clouds
	local cb = b.clouds or base.clouds
	local none = { brightness = 0, saturation = 0, tint = { 255, 255, 255 } }
	local ga = a.grade or none
	local gb = b.grade or none
	return {
		air = air,
		clouds = { cover = lerp(ca.cover, cb.cover, k), density = lerp(ca.density, cb.density, k) },
		grade = {
			brightness = lerp(ga.brightness, gb.brightness, k),
			saturation = lerp(ga.saturation, gb.saturation, k),
			tint = blend(ga.tint, gb.tint, k),
		},
		rain = lerp(a.rain or 0, b.rain or 0, k),
		lightning = if k < 0.5 then a.lightning == true else b.lightning == true,
	}
end

-- One lightning window: when its flash is (nil: no flash in it), when its thunder rolls, and its bolt's bearing
function WeatherPlan.strike(cfg: any, window: number): (number?, number, number)
	local L = cfg.lightning
	local start = window * L.gap
	if u01(cfg.seed, window, 101) >= L.chance then
		return nil, math.huge, 0
	end
	local at = start + u01(cfg.seed, window, 102) * (L.gap - L.flash - L.thunder[2])
	local thunder = at + lerp(L.thunder[1], L.thunder[2], u01(cfg.seed, window, 103))
	local bearing = u01(cfg.seed, window, 104) * math.pi * 2
	return at, thunder, bearing
end

-- How bright the lightning is at t (0..1): two quick pulses, the second softer; 0 between flashes
function WeatherPlan.flash(cfg: any, t: number): number
	local L = cfg.lightning
	local at = WeatherPlan.strike(cfg, math.floor(t / L.gap))
	if not at then
		return 0
	end
	local s = (t - at) / L.flash
	if s < 0 or s >= 1 then
		return 0
	end
	if s < 0.3 then
		return 1 - s / 0.3 * 0.7
	elseif s < 0.45 then
		return 0.3
	end
	return 0.75 * (1 - (s - 0.45) / 0.55)
end

-- A bolt's jagged points (studs, relative to the camera's ground spot): from the cloud base down to the city,
-- `dist` away on the window's bearing
function WeatherPlan.bolt(cfg: any, window: number, dist: number, top: number): { { number } }
	local _, _, bearing = WeatherPlan.strike(cfg, window)
	local cx, cz = math.sin(bearing) * dist, math.cos(bearing) * dist
	local pts = {}
	local n = 7
	for i = 0, n do
		local y = top * (1 - i / n)
		local j = if i == 0 or i == n then 0 else (u01(cfg.seed, window, 200 + i) * 2 - 1) * 28
		local jz = if i == 0 or i == n then 0 else (u01(cfg.seed, window, 300 + i) * 2 - 1) * 28
		table.insert(pts, { cx + j, y, cz + jz })
	end
	return pts
end

return WeatherPlan
