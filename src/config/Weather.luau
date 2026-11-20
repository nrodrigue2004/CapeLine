--!strict
-- Weather (list-combat 2026-11-20, Everything Left 273: "Weather (rain, fog banks, storms) for a livelier city").
-- Shared.WeatherPlan picks one weather a `slot` of server time from a seeded roll, so every player on every
-- server sees the same sky at the same moment with no remote; Fx.WeatherFx draws it on each device. Weather is
-- a look only: it never changes a stat, a hit or a reward (nothing to buy, nothing to exploit).
-- * kinds: weight is the chance in the roll (clear most of the time); `air` is the sky's Atmosphere (missing keys
--   keep the place's own values from default.project.json), `clouds` the Clouds cover and density (nil keeps
--   CityBuilder's 0.55 / 0.6), `grade` a separate ColorCorrection (the place's own Grade is left alone), `rain` the
--   share of the preset's drops (0 none), `lightning` a storm's flashes.
-- * The same kind never rolls twice in a row except clear; rain and storm always start from a grey sky (a storm
--   after clear becomes rain first: `after`).
-- * fade: seconds the old weather blends into the new at the start of a slot.
-- * rain: the drops near the camera (Fx.WeatherFx): `drops` per second by preset, `splashes` the rings on the ground
--   under the camera, box the emitter's size (studs, centred `above` the camera), speed and wind.
-- * Story scenes (the opening's held dusk), underwater (Fx.DeepClient owns the Atmosphere there), mission pockets and
--   the HQ have no weather: the rain stops and the grade relaxes.
-- Thunder borrows the collapse rumble pitched down until a recorded thunder clip lands (NEEDS NATE, Tasks); the rain
-- has no sound bed yet for the same reason.
return {
	on = true,
	slot = 600,
	fade = 25,
	seed = 7331,
	kinds = {
		clear = { weight = 6 },
		overcast = {
			weight = 3,
			air = { Density = 0.36, Haze = 1.8, Color = { 200, 205, 215 }, Glare = 0.05 },
			clouds = { cover = 0.8, density = 0.75 },
			grade = { brightness = -0.03, saturation = -0.12, tint = { 238, 242, 250 } },
		},
		rain = {
			weight = 3,
			air = {
				Density = 0.42,
				Haze = 2.4,
				Color = { 170, 180, 196 },
				Decay = { 96, 104, 124 },
				Glare = 0,
			},
			clouds = { cover = 0.9, density = 0.85 },
			grade = { brightness = -0.06, saturation = -0.2, tint = { 225, 233, 250 } },
			rain = 1,
		},
		storm = {
			weight = 1,
			after = "rain",
			air = { Density = 0.5, Haze = 3, Color = { 128, 138, 160 }, Decay = { 70, 76, 100 }, Glare = 0 },
			clouds = { cover = 0.97, density = 1 },
			grade = { brightness = -0.1, saturation = -0.28, tint = { 205, 215, 245 } },
			rain = 1.6,
			lightning = true,
		},
		fog = {
			weight = 2,
			air = {
				Density = 0.6,
				Offset = 0.4,
				Haze = 3,
				Color = { 214, 218, 224 },
				Decay = { 176, 182, 196 },
				Glare = 0,
			},
			clouds = { cover = 0.75, density = 0.6 },
			grade = { brightness = 0, saturation = -0.15, tint = { 240, 244, 250 } },
		},
	},
	order = { "clear", "overcast", "rain", "storm", "fog" },
	rain = {
		texture = 87074348735648, -- art/export/fx/rain.png (art/fx/textures.py --rain)
		splash = 120260533473380, -- art/export/fx/splash.png
		drops = { low = 140, medium = 300, high = 520 },
		splashes = { low = 0, medium = 36, high = 80 },
		box = 150,
		above = 55,
		speed = { 105, 125 },
		wind = { 6, 0, 3 },
		size = 0.16,
		squash = 2.6,
		lifetime = { 0.9, 1.15 },
		color = { 205, 218, 235 },
		transparency = 0.45,
		splashSize = 1.6,
		probe = 0.25, -- seconds between the ground probes under the camera (the splash height)
	},
	lightning = {
		gap = 11, -- one window this long, at most one flash in it
		chance = 0.7,
		flash = 0.35, -- seconds a flash lasts (two quick pulses)
		bright = 0.55, -- the grade's brightness kick at a flash's peak
		thunder = { 1.2, 3.5 }, -- seconds from flash to thunder (seeded, the same for everyone)
		pitch = 0.42,
		volume = 0.7,
	},
}
