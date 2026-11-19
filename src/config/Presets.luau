-- Streaming and device presets (spec: Streaming and device presets). Client only; the server never
-- depends on them. The preset is picked from the device and a 5 s frame-time test on first launch
-- (Shared.QualityRules; QualityController applies it).
-- Phone pass (2026-11-17): the newer systems read their share from here too: citizens drawn and how often
-- far ones pose (CitizenRenderer; their Roblox-look clothes are Textures, so fewer bodies is fewer
-- Textures), Bloom and SunRays (Lighting), and FxLib's particle budget (Config.Fx.lib, by preset name).
-- Medium and high keep what the game drew before the pass; only low draws less.
-- props: the city kit's street props this device builds (CityProps): up to this tier (Config.City.kit.props),
-- within this many studs of the camera, at most this many mesh parts (nearest first). Phones start on low.
-- pockets (2026-11-19): the mission and side quest pockets' kit dressing (Shared.PocketDress, Config.PocketKit):
-- the server builds tier 1 for everyone; each device adds its tiers up to `tier`, within `parts` dressing parts
-- (tier 1 counted) and `lights` PointLights a pocket (PocketDecor).
-- clothesNear and clothesFar (perf pass 2026-11-18): a robot's or citizen's Roblox-look clothes are 66 Textures
-- a rig; inside clothesNear it draws them all, out to clothesFar all but the 21 faces the body hides at rest
-- (Shared.ClothesMap.tucked), and past it none (NpcRig.showClothes).
-- sites (2026-11-19): the incident, event and contract props this device draws in their Blender looks (Fx.ActivityProps):
-- within radius studs of the camera, at most `looks` props and `parts` mesh parts, nearest first; the rest keep their parts.
-- story (2026-11-19, gap-story): a mission's props in their Blender looks (Fx.StoryProps, Shared.StoryArtKit): within
-- radius studs, at most `looks` (nearest first; the rest keep their parts), the nearest `drones` Echo Drones in their
-- mesh look (the rest keep the plain ball), the goal beacon on or off, and
-- whether its chevron rings slide.
return {
	order = { "low", "medium", "high" },
	low = {
		streamRadius = 400,
		partBudget = 6000,
		debris = 60,
		falling = 240, -- building pieces in a falling storey or collapse animated at once (BuildingFx; the rest just go)
		craters = 6,
		craterRim = 6, -- broken rim chunks round each drawn ground crater (GroundFx, fix-destroy)
		enemiesDrawn = 20,
		emitters = 3,
		shadows = false,
		playersFull = 12,
		citizensDrawn = 30, -- the nearest citizens drawn (the sim sends up to 60)
		citizenPoseNear = 60, -- citizens this close to the camera pose every frame
		citizenPoseEvery = 4, -- farther ones every this many frames
		citizenAnimNear = 50, -- citizens this close play Roblox's own idle, walk and run (Config.Destruction.citizens.loco)
		citizenAnimMax = 8, -- at most this many of them, nearest first
		gestureNear = 40, -- quest givers, helpers and standing citizens this close gesture (Shared.NpcAnim, pt-anims)
		gestureMax = 4, -- at most this many of them, nearest first
		bloom = false,
		sunRays = false,
		enemyPoseNear = 60, -- robots this close pose every frame (Config.Enemies.look.poseNear before)
		enemyPoseEvery = 4, -- farther ones every this many frames
		enemyAnimNear = 80, -- robots this close walk with Roblox's own animations (Config.Enemies.look.loco)
		enemyPool = { keep = 2, idle = 20 }, -- spare robot bodies kept a kind; the rest go after idle s
		clothesNear = 20, -- dressed rigs this close draw every clothes face (the tucked ones too)
		clothesFar = 60, -- past this a rig drops its clothes Textures (its part colours match them)
		props = { tier = 1, radius = 260, parts = 700 },
		vehicleRig = 110, -- gap-vehicles: escorts this close roll their wheels, steer and sway (Fx.VehicleRig); none past it
		pockets = { tier = 1, parts = 180, lights = 4, props = 64 }, -- a pocket's dressing (Shared.PocketDress; the server's tier 1 counts); props: prop meshes a pocket (Shared.PocketPropKit, gap-props2; 40 -> 64 in gap-props3 so phones get the second set's layout props: shared mesh assets, one draw per mesh and material)
		ruins = { bits = 0 }, -- the Crater's loose lab debris this device scatters (Shared.CraterArtKit.bits; gap-wrecks)
		smash = 3, -- street things (lamps, benches, trees, fences) knocked loose a big impact nearby (BuildingFx, 2026-11-19)
		sites = { radius = 240, looks = 6, parts = 30 }, -- activity props in their Blender looks (Fx.ActivityProps)
		story = { radius = 240, looks = 6, drones = 2, beacon = true, rings = false }, -- story props and Echo Drones (Fx.StoryProps)
	},
	medium = {
		streamRadius = 600,
		partBudget = 12000,
		debris = 150,
		falling = 600,
		craters = 12,
		craterRim = 10,
		enemiesDrawn = 40,
		emitters = 3,
		shadows = true,
		playersFull = 20,
		citizensDrawn = 60,
		citizenPoseNear = 100,
		citizenPoseEvery = 3,
		citizenAnimNear = 90, -- citizens this close play Roblox's own idle, walk and run
		citizenAnimMax = 16, -- at most this many of them, nearest first
		gestureNear = 70, -- quest givers, helpers and standing citizens this close gesture (Shared.NpcAnim, pt-anims)
		gestureMax = 8, -- at most this many of them, nearest first
		bloom = true,
		sunRays = true,
		enemyPoseNear = 120, -- robots this close pose every frame (Config.Enemies.look.poseNear before)
		enemyPoseEvery = 3, -- farther ones every this many frames
		enemyAnimNear = 150, -- robots this close walk with Roblox's own animations (Config.Enemies.look.loco)
		enemyPool = { keep = 4, idle = 30 }, -- spare robot bodies kept a kind; the rest go after idle s
		clothesNear = 25, -- dressed rigs this close draw every clothes face (the tucked ones too)
		clothesFar = 80, -- past this a rig drops its clothes Textures (its part colours match them)
		props = { tier = 2, radius = 420, parts = 2000 },
		vehicleRig = 200, -- gap-vehicles: escorts this close roll their wheels, steer and sway (Fx.VehicleRig); none past it
		pockets = { tier = 2, parts = 480, lights = 10, props = 110 },
		ruins = { bits = 16 }, -- the Crater's loose lab debris this device scatters (Shared.CraterArtKit.bits; gap-wrecks)
		smash = 6, -- street things (lamps, benches, trees, fences) knocked loose a big impact nearby (BuildingFx, 2026-11-19)
		sites = { radius = 420, looks = 14, parts = 70 }, -- activity props in their Blender looks (Fx.ActivityProps)
		story = { radius = 420, looks = 12, drones = 6, beacon = true, rings = true }, -- story props and Echo Drones (Fx.StoryProps)
	},
	high = {
		streamRadius = 800,
		partBudget = 20000,
		debris = 250,
		falling = 1000,
		craters = 20,
		craterRim = 14,
		enemiesDrawn = 60,
		emitters = 5,
		shadows = true,
		playersFull = 30,
		citizensDrawn = 60,
		citizenPoseNear = 100,
		citizenPoseEvery = 3,
		citizenAnimNear = 120, -- citizens this close play Roblox's own idle, walk and run
		citizenAnimMax = 24, -- at most this many of them, nearest first
		gestureNear = 100, -- quest givers, helpers and standing citizens this close gesture (Shared.NpcAnim, pt-anims)
		gestureMax = 12, -- at most this many of them, nearest first
		bloom = true,
		sunRays = true,
		enemyPoseNear = 120, -- robots this close pose every frame (Config.Enemies.look.poseNear before)
		enemyPoseEvery = 3, -- farther ones every this many frames
		enemyAnimNear = 200, -- robots this close walk with Roblox's own animations (Config.Enemies.look.loco)
		enemyPool = { keep = 4, idle = 30 }, -- spare robot bodies kept a kind; the rest go after idle s
		clothesNear = 30, -- dressed rigs this close draw every clothes face (the tucked ones too)
		clothesFar = 100, -- past this a rig drops its clothes Textures (its part colours match them)
		props = { tier = 3, radius = 600, parts = 4000 },
		vehicleRig = 320, -- gap-vehicles: escorts this close roll their wheels, steer and sway (Fx.VehicleRig); none past it
		pockets = { tier = 3, parts = 900, lights = 18, props = 220 },
		ruins = { bits = 36 }, -- the Crater's loose lab debris this device scatters (Shared.CraterArtKit.bits; gap-wrecks)
		smash = 10, -- street things knocked loose a big impact nearby (BuildingFx, 2026-11-19)
		sites = { radius = 640, looks = 30, parts = 150 }, -- activity props in their Blender looks (Fx.ActivityProps)
		story = { radius = 640, looks = 24, drones = 12, beacon = true, rings = true }, -- story props and Echo Drones (Fx.StoryProps)
	},
	-- the preset each device class starts on (QualityRules.device)
	auto = { phone = "low", tablet = "medium", pc = "medium", console = "medium" },
	-- average fps thresholds; only the devices in upFor may step up to high on their own
	frameTest = { seconds = 5, lowBelow = 40, highAbove = 58, upFor = { pc = true, console = true } },
	-- after the test: this many seconds in a row under `below` fps steps one preset down (Auto only)
	watch = { seconds = 20, below = 26 },
}
