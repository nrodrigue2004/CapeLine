-- Streaming and device presets (spec: Streaming and device presets). Client only; the server never
-- depends on them. The preset is picked from the device and a 5 s frame-time test on first launch.
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
		props = { tier = 3, radius = 600, parts = 4000 },
	},
	frameTest = { seconds = 5, lowBelow = 40, highAbove = 58 }, -- average fps thresholds
}
