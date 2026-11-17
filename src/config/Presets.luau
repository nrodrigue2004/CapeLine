-- Streaming and device presets (spec: Streaming and device presets). Client only; the server never
-- depends on them. The preset is picked from the device and a 5 s frame-time test on first launch
-- (Shared.QualityRules; QualityController applies it).
-- Phone pass (2026-11-17): the newer systems read their share from here too: citizens drawn and how often
-- far ones pose (CitizenRenderer; their Roblox-look clothes are Textures, so fewer bodies is fewer
-- Textures), Bloom and SunRays (Lighting), and FxLib's particle budget (Config.Fx.lib, by preset name).
-- Medium and high keep what the game drew before the pass; only low draws less.
-- props: the city kit's street props this device builds (CityProps): up to this tier (Config.City.kit.props),
-- within this many studs of the camera, at most this many mesh parts (nearest first). Phones start on low.
return {
	order = { "low", "medium", "high" },
	low = {
		streamRadius = 400,
		partBudget = 6000,
		debris = 60,
		craters = 6,
		enemiesDrawn = 20,
		emitters = 3,
		shadows = false,
		playersFull = 12,
		citizensDrawn = 30, -- the nearest citizens drawn (the sim sends up to 60)
		citizenPoseNear = 60, -- citizens this close to the camera pose every frame
		citizenPoseEvery = 4, -- farther ones every this many frames
		bloom = false,
		sunRays = false,
		props = { tier = 1, radius = 260, parts = 700 },
	},
	medium = {
		streamRadius = 600,
		partBudget = 12000,
		debris = 150,
		craters = 12,
		enemiesDrawn = 40,
		emitters = 3,
		shadows = true,
		playersFull = 20,
		citizensDrawn = 60,
		citizenPoseNear = 100,
		citizenPoseEvery = 3,
		bloom = true,
		sunRays = true,
		props = { tier = 2, radius = 420, parts = 2000 },
	},
	high = {
		streamRadius = 800,
		partBudget = 20000,
		debris = 250,
		craters = 20,
		enemiesDrawn = 60,
		emitters = 5,
		shadows = true,
		playersFull = 30,
		citizensDrawn = 60,
		citizenPoseNear = 100,
		citizenPoseEvery = 3,
		bloom = true,
		sunRays = true,
		props = { tier = 3, radius = 600, parts = 4000 },
	},
	-- the preset each device class starts on (QualityRules.device)
	auto = { phone = "low", tablet = "medium", pc = "medium", console = "medium" },
	-- average fps thresholds; only the devices in upFor may step up to high on their own
	frameTest = { seconds = 5, lowBelow = 40, highAbove = 58, upFor = { pc = true, console = true } },
	-- after the test: this many seconds in a row under `below` fps steps one preset down (Auto only)
	watch = { seconds = 20, below = 26 },
}
