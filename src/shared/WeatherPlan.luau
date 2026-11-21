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
	-- the new weathers (2026-11-21, Everything Left 735)
	snow: number,
	whiten: number,
	wind: { number },
	gust: number,
	debris: number,
	heat: number,
	aurora: number,
	strikes: boolean,
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

-- The rules on one slot given the weather before it (u: the slot's own roll for `next`): a kind with `after` needs that kind (or itself) first,
-- and no weather but clear runs two slots in a row
function WeatherPlan.rule(cfg: any, prev: string, want: string, u: number?): string
	local k = want
	-- a kind that grows into another (snow into a blizzard): the slot after it turns this often (roll u)
	local nxt = cfg.kinds[prev] and cfg.kinds[prev].next
	if nxt and u and u < nxt.chance then
		k = nxt.kind
	end
	local after = cfg.kinds[k].after
	if after then
		local list = if type(after) == "table" then after else { after }
		if prev ~= k and not table.find(list, prev) then
			k = list[1]
		end
	end
	-- a kind that may not follow the weather before it (no snow straight after a heatwave): clear instead
	local notAfter = cfg.kinds[k].notAfter
	if notAfter and table.find(notAfter, prev) then
		k = "clear"
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
		cur = WeatherPlan.rule(cfg, prev, WeatherPlan.roll(cfg, s), u01(cfg.seed, s, 7))
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
	local calm = cfg.rain.wind
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
		snow = lerp(a.snow or 0, b.snow or 0, k),
		whiten = lerp(a.whiten or 0, b.whiten or 0, k),
		wind = blend(a.wind or calm, b.wind or calm, k),
		gust = lerp(a.gust or 0, b.gust or 0, k),
		debris = lerp(a.debris or 0, b.debris or 0, k),
		heat = lerp(a.heat or 0, b.heat or 0, k),
		aurora = lerp(a.aurora or 0, b.aurora or 0, k),
		strikes = if k < 0.5 then a.strikes == true else b.strikes == true,
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

-- How white the roofs and lawns are after `dt` more seconds: eases toward the look's `whiten` over the snow's
-- `settle` seconds while it snows harder than it is white, and melts over `melt` seconds once it stops
function WeatherPlan.settle(cfg: any, cover: number, want: number, dt: number): number
	local S = cfg.snow
	if want > cover then
		return math.min(want, cover + dt / S.settle)
	end
	return math.max(want, cover - dt / S.melt)
end

-- The strike's bolt from the cloud base down to a roof point (studs, world): `n` jagged points, seeded by `seed`
function WeatherPlan.strikeBolt(x: number, y: number, z: number, top: number, seed: number): { { number } }
	local pts = {}
	local n = 8
	local h = math.max(top - y, 60)
	for i = 0, n do
		local f = i / n
		local spread = 34 * (1 - f) ^ 0.7
		local jx = if i == n then 0 else (u01(seed, i, 11) * 2 - 1) * spread
		local jz = if i == n then 0 else (u01(seed, i, 12) * 2 - 1) * spread
		table.insert(pts, { x + jx, y + h * (1 - f), z + jz })
	end
	return pts
end

-- Is it aurora time on this clock phase? Full through the night, fading in through the last of dusk and out
-- through the first of dawn (0..1)
function WeatherPlan.nightShare(phase: string, f: number): number
	if phase == "night" then
		return 1
	elseif phase == "dusk" then
		return math.clamp((f - 0.6) / 0.4, 0, 1)
	elseif phase == "dawn" then
		return math.clamp(1 - f / 0.4, 0, 1)
	end
	return 0
end

-- Where a lightning storm strikes near a hero at (hx, hz): one of `roofs` ({ id, x, z, sx, sz, top }) at least
-- strikes.min from the hero, with no hero in `others` ({ { x, y, z } }) within strikes.clear of the strike point.
-- u1, u2: two rolls 0..1 (which roof, where on it). Returns the roof and the point, or nil.
function WeatherPlan.pickRoof(
	cfg: any,
	roofs: { any },
	hx: number,
	hz: number,
	others: { { number } },
	u1: number,
	u2: number
): (any?, { number }?)
	local K = cfg.strikes
	local ok = {}
	for _, r in roofs do
		local dx, dz = r.x - hx, r.z - hz
		if dx * dx + dz * dz >= K.min * K.min then
			table.insert(ok, r)
		end
	end
	if #ok == 0 then
		return nil, nil
	end
	table.sort(ok, function(a, b)
		return a.id < b.id
	end)
	local start = math.floor(u1 * #ok) + 1
	for n = 0, #ok - 1 do
		local r = ok[(start + n - 1) % #ok + 1]
		-- a corner of the roof, a little in from its edge, so a piece of parapet and wall goes
		local qx = if u2 < 0.5 then -1 else 1
		local qz = if (u2 * 4) % 1 < 0.5 then -1 else 1
		local px = r.x + qx * math.max(r.sx / 2 - 3, 0)
		local pz = r.z + qz * math.max(r.sz / 2 - 3, 0)
		local py = r.top
		local clear = true
		for _, o in others do
			local dx, dy, dz = o[1] - px, o[2] - py, o[3] - pz
			if dx * dx + dy * dy + dz * dz < K.clear * K.clear then
				clear = false
				break
			end
		end
		if clear then
			return r, { px, py, pz }
		end
	end
	return nil, nil
end

return WeatherPlan
