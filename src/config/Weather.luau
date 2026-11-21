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
-- Thunder borrows the collapse rumble pitched down until a recorded thunder clip lands (NEEDS NATE, Tasks). The rain
-- bed (alive-world 2026-11-20: Config.Audio.sounds.rain, the Ambient atlas) plays under the rain at up to
-- rain.sound, following the rain's strength; silent indoors, underwater and in the pockets (no rain there).
-- New weathers (Everything Left 735, nate 2026-11-20 22:05Z "all six"; this thread 2026-11-21): snow (flakes and
-- roofs and lawns that turn white as it settles, melting after), blizzard (only after snow: a white-out, sideways
-- snow, the wind up), heatwave (an orange haze, a hard sun, heat shimmer over the ground, never next to snow),
-- windy (leaves and paper scraps blow through, flags whip, the rooftop wind loud at street level), lightning storm
-- (`electric`: after rain, overcast or a storm; bolts strike real roofs near heroes and knock pieces out, server
-- WeatherService, never a hero's health) and aurora (a clear crisp sky; green and violet curtains at night).
-- * the new keys a kind may set (Shared.WeatherPlan.mix blends them): `snow` the share of flakes, `whiten` how
--   white roofs and lawns get as it settles (eased over `settle` seconds, melting over `melt`), `wind` the drift
--   of rain, snow and debris (studs/s^2), `gust` 0..1 (flags whip, the rooftop wind bed comes down to the street),
--   `debris` the share of blowing leaves and paper, `heat` the shimmer and sun, `aurora` the night curtains,
--   `strikes` the server's roof strikes. `after` may list kinds (the first is the stand-in); `notAfter` kinds
--   turn the slot clear (no snow straight after a heatwave); `next` = { kind, chance }: the slot after this one
--   becomes that kind this often (snow builds into a blizzard).
return {
	on = true,
	slot = 600,
	fade = 25,
	seed = 7331,
	kinds = {
		clear = { weight = 6.5 },
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
		-- the new six (2026-11-21, Everything Left 735)
		snow = {
			weight = 1.5,
			next = { kind = "blizzard", chance = 0.4 }, -- the slot after snow turns into a blizzard this often
			notAfter = { "heatwave" },
			air = {
				Density = 0.42,
				Haze = 1.8,
				Color = { 226, 232, 242 },
				Decay = { 196, 206, 224 },
				Glare = 0,
			},
			clouds = { cover = 0.88, density = 0.72 },
			grade = { brightness = 0.03, saturation = -0.2, tint = { 236, 243, 255 } },
			snow = 1,
			whiten = 1,
			wind = { 5, 0, 2 },
		},
		blizzard = {
			weight = 0.5,
			after = "snow",
			air = {
				Density = 0.64,
				Offset = 0.15,
				Haze = 3,
				Color = { 222, 228, 238 },
				Decay = { 188, 198, 216 },
				Glare = 0,
			},
			clouds = { cover = 0.98, density = 1 },
			grade = { brightness = 0.02, saturation = -0.32, tint = { 226, 236, 255 } },
			snow = 2.6,
			whiten = 1,
			wind = { 58, -6, 22 },
			gust = 0.75,
		},
		heatwave = {
			weight = 1.5,
			notAfter = { "snow", "blizzard" },
			air = {
				Density = 0.34,
				Haze = 2.4,
				Color = { 255, 196, 146 },
				Decay = { 255, 156, 96 },
				Glare = 0.7,
			},
			clouds = { cover = 0.25, density = 0.3 },
			grade = { brightness = 0.04, saturation = 0.16, tint = { 255, 234, 208 } },
			heat = 1,
		},
		windy = {
			weight = 2,
			clouds = { cover = 0.68, density = 0.5 },
			grade = { brightness = 0, saturation = -0.03, tint = { 248, 250, 255 } },
			wind = { 40, 2, 15 },
			gust = 1,
			debris = 1,
		},
		electric = {
			weight = 2,
			after = { "rain", "overcast", "storm" },
			air = {
				Density = 0.48,
				Haze = 2.6,
				Color = { 122, 114, 164 },
				Decay = { 72, 62, 112 },
				Glare = 0,
			},
			clouds = { cover = 0.96, density = 0.95 },
			grade = { brightness = -0.08, saturation = -0.12, tint = { 216, 206, 255 } },
			rain = 0.35,
			lightning = true,
			strikes = true,
			gust = 0.45,
			wind = { 14, 0, 6 },
		},
		aurora = {
			weight = 1.5,
			air = { Density = 0.26, Haze = 0.5, Glare = 0.1 },
			clouds = { cover = 0.18, density = 0.3 },
			grade = { brightness = 0, saturation = 0.06, tint = { 242, 250, 255 } },
			aurora = 1,
		},
	},
	order = {
		"clear",
		"overcast",
		"rain",
		"storm",
		"fog",
		"snow",
		"blizzard",
		"heatwave",
		"windy",
		"electric",
		"aurora",
	},
	-- shown by the radar clock (Ui.Radar); clear shows nothing
	names = {
		overcast = "Overcast",
		rain = "Rain",
		storm = "Storm",
		fog = "Fog",
		snow = "Snow",
		blizzard = "Blizzard",
		heatwave = "Heatwave",
		windy = "Windy",
		electric = "Lightning",
		aurora = "Aurora",
	},
	rain = {
		texture = 87074348735648, -- art/export/fx/rain.png (art/fx/textures.py --rain)
		splash = 120260533473380, -- art/export/fx/splash.png
		drops = { low = 140, medium = 300, high = 520 },
		sound = 0.38, -- the rain bed's volume at full rain (Config.Audio.sounds.rain)
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
	-- snow (Fx.WeatherLook): flakes in a box over the camera like the rain, slower and drifting; caps on the roofs
	-- nearest the camera (`caps` by preset, within `capRange`) and the lawns' Terrain colour whiten as it settles
	snow = {
		texture = 101572142684934, -- art/export/fx/snow.png (art/fx/textures.py --weather)
		flakes = { low = 90, medium = 200, high = 360 },
		box = 140,
		above = 40,
		speed = { 9, 15 },
		lifetime = { 3.5, 5 },
		size = { 0.35, 0.7 },
		color = { 250, 252, 255 },
		transparency = 0.1,
		settle = 90, -- seconds to white over at full snow
		melt = 120,
		caps = { low = 20, medium = 50, high = 90 },
		capRange = 520,
		capEvery = 1, -- seconds between picking the nearest roofs
		capColor = { 244, 248, 255 },
		lawn = 0.85, -- how far the grass colour goes to white at full cover
	},
	-- windy days and blizzards: leaves and paper scraps blowing past the camera; the flags' wave speed and the
	-- rooftop wind bed scale up with `gust`
	debris = {
		leaf = 71055974786369, -- Config.Fx.lib.textures.leaf
		paper = 84889245407719, -- art/export/fx/paper.png
		rate = { low = 6, medium = 14, high = 26 },
		box = 120,
		speed = { 30, 46 },
		lifetime = { 3, 4.5 },
		size = { 0.6, 1.1 },
		leafColors = { { 196, 142, 62 }, { 120, 156, 70 } },
		paperColor = { 238, 232, 216 },
		flagWind = 2.6, -- the flags' wave rate multiplier at gust 1
		roofBed = 0.8, -- the rooftop wind bed's share at street level at gust 1
	},
	-- the heatwave: shimmer sheets rising off the ground near the camera, the sun's rays stronger
	heat = {
		texture = 119232726753346, -- art/export/fx/shimmer.png
		rate = { low = 0, medium = 5, high = 9 },
		box = 110,
		size = { 7, 12 },
		lifetime = { 1.6, 2.4 },
		rise = { 2, 4 },
		transparency = 0.86,
		color = { 255, 226, 196 },
		sunRays = 0.12, -- added to the place's SunRays intensity at full heat
		bloom = 0.25, -- added to its Bloom intensity
	},
	-- aurora nights: curtains of Beams high over the camera (no particles), only while it is night
	aurora = {
		texture = 94561991020858, -- art/export/fx/aurora.png
		curtains = { low = 2, medium = 3, high = 4 },
		height = 900, -- the hem's height over the camera
		spread = 1600, -- how wide a curtain runs
		depth = 700, -- how far away (ahead and to the sides) the curtains hang
		width = 520, -- the curtain's height (the Beam's width)
		colors = { { 110, 255, 170 }, { 150, 120, 255 } },
		drift = 0.03, -- texture scroll per second
		fade = 8, -- seconds to fade in at dusk and out at dawn
		stars = 5000, -- the Sky's StarCount while it shows
		flip = false, -- Studio: true if the curtains hang upside down (bright hem on top)
	},
	-- lightning storm strikes (server WeatherService): every `gap` s, with `chance`, a bolt hits the roof of a
	-- breakable building within `range` of a random hero out in the city (not one with a hero within `clear` studs
	-- of the strike), knocking pieces out (`dmg` structure damage in `radius`); devices within `show` see the bolt
	strikes = {
		gap = 9,
		chance = 0.8,
		range = 260,
		min = 40, -- never closer to the hero than this
		clear = 16,
		dmg = 1300,
		radius = 8,
		show = 1800,
		flash = 0.4,
		volume = 1,
		pitch = 0.55,
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
