-- Streaming and device presets (spec: Streaming and device presets). Client only; the server never
-- depends on them. The preset is picked from the device and a 5 s frame-time test on first launch
-- (Shared.QualityRules; QualityController applies it).
-- Phone pass (2026-11-17): the newer systems read their share from here too: citizens drawn and how often
-- far ones pose (CitizenRenderer; their Roblox-look clothes are Textures, so fewer bodies is fewer
-- Textures), Bloom and SunRays (Lighting), and FxLib's particle budget (Config.Fx.lib, by preset name).
-- Medium and high keep what the game drew before the pass; only low draws less.
-- props: the city kit's street props this device builds (CityProps): up to this tier (Config.City.kit.props),
-- within this many studs of the camera, at most this many mesh parts (nearest first). Phones start on low.
-- clothesNear and clothesFar (perf pass 2026-11-18): a robot's or citizen's Roblox-look clothes are 66 Textures
-- a rig; inside clothesNear it draws them all, out to clothesFar all but the 21 faces the body hides at rest
-- (Shared.ClothesMap.tucked), and past it none (NpcRig.showClothes).
return {
	order = { "low", "medium", "high" },
	low = {
		streamRadius = 400,
		partBudget = 6000,
		debris = 60,
		falling = 240, -- building pieces in a falling storey or collapse animated at once (BuildingFx; the rest just go)
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
		enemyPoseNear = 60, -- robots this close pose every frame (Config.Enemies.look.poseNear before)
		enemyPoseEvery = 4, -- farther ones every this many frames
		enemyAnimNear = 80, -- robots this close walk with Roblox's own animations (Config.Enemies.look.loco)
		enemyPool = { keep = 2, idle = 20 }, -- spare robot bodies kept a kind; the rest go after idle s
		clothesNear = 20, -- dressed rigs this close draw every clothes face (the tucked ones too)
		clothesFar = 60, -- past this a rig drops its clothes Textures (its part colours match them)
		props = { tier = 1, radius = 260, parts = 700 },
		smash = 3, -- street things (lamps, benches, trees, fences) knocked loose a big impact nearby (BuildingFx, 2026-11-19)
	},
	medium = {
		streamRadius = 600,
		partBudget = 12000,
		debris = 150,
		falling = 600,
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
		enemyPoseNear = 120, -- robots this close pose every frame (Config.Enemies.look.poseNear before)
		enemyPoseEvery = 3, -- farther ones every this many frames
		enemyAnimNear = 150, -- robots this close walk with Roblox's own animations (Config.Enemies.look.loco)
		enemyPool = { keep = 4, idle = 30 }, -- spare robot bodies kept a kind; the rest go after idle s
		clothesNear = 25, -- dressed rigs this close draw every clothes face (the tucked ones too)
		clothesFar = 80, -- past this a rig drops its clothes Textures (its part colours match them)
		props = { tier = 2, radius = 420, parts = 2000 },
		smash = 6, -- street things (lamps, benches, trees, fences) knocked loose a big impact nearby (BuildingFx, 2026-11-19)
	},
	high = {
		streamRadius = 800,
		partBudget = 20000,
		debris = 250,
		falling = 1000,
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
		enemyPoseNear = 120, -- robots this close pose every frame (Config.Enemies.look.poseNear before)
		enemyPoseEvery = 3, -- farther ones every this many frames
		enemyAnimNear = 200, -- robots this close walk with Roblox's own animations (Config.Enemies.look.loco)
		enemyPool = { keep = 4, idle = 30 }, -- spare robot bodies kept a kind; the rest go after idle s
		clothesNear = 30, -- dressed rigs this close draw every clothes face (the tucked ones too)
		clothesFar = 100, -- past this a rig drops its clothes Textures (its part colours match them)
		props = { tier = 3, radius = 600, parts = 4000 },
		smash = 10, -- street things knocked loose a big impact nearby (BuildingFx, 2026-11-19)
	},
	-- the preset each device class starts on (QualityRules.device)
	auto = { phone = "low", tablet = "medium", pc = "medium", console = "medium" },
	-- average fps thresholds; only the devices in upFor may step up to high on their own
	frameTest = { seconds = 5, lowBelow = 40, highAbove = 58, upFor = { pc = true, console = true } },
	-- after the test: this many seconds in a row under `below` fps steps one preset down (Auto only)
	watch = { seconds = 20, below = 26 },
}
