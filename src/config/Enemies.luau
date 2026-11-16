-- Enemies, machines only (spec: Enemies), drawn as humanoid robots (nate, 2026-11-16: "robots that look
-- like humans"): metal android bodies with glowing eyes. Defeats are sparks, bolts and parts, never blood.
-- Health and damage scale with the zone level: HP x (1 + 0.1 x (zone level - 1)); enemy damage =
-- (20 + 4 x level) x coeff. typeId goes on the wire (3 bits). (tune)
-- Fields every enemy has:
--   ai        "flyer" (hovers and strafes), "thief" (runs, laser when cornered), "sneak" (cloak, backstab),
--             "brute" (slow slam with a warning ring), "sentry" (planted, turns, shield flicker),
--             "guard" (front block, flank break)
--   speed     studs/s; ground robots walk the streets (they never climb buildings)
--   radius    body radius for hits; height for the body drawing
--   mitigation damage taken is cut by this; ccResist shortens stuns, roots, slows; immune lists statuses it
--             ignores (a planted sentry cannot be knocked, pulled or floated)
--   body      the drawing: build (slim, normal, heavy), height, metal (the endoskeleton) and eye colors, and
--             the superhuman shell over it: suit and trim colours, cape (EnemyRenderer, Enemies.look)
return {
	order = { "SparkDrone", "BurglarBot", "SneakBot", "BruteBot", "Turret", "NullSentinel" },
	scale = { hpPerLevel = 0.1, dmgBase = 20, dmgPerLevel = 4 },
	SparkDrone = {
		typeId = 1,
		name = "Spark Trooper", -- a jet-boot android (was a drone; id kept so saves and data stay put)
		ai = "flyer",
		hp = 100,
		flies = true,
		speed = 30,
		hover = { min = 14, max = 40 }, -- height above the ground it holds while patrolling
		aggro = 80,
		attackRange = 50,
		orbit = { min = 22, max = 38 }, -- the distance it strafes at while firing
		burst = { shots = 3, gap = 0.18, every = 2.6 },
		coeff = 0.5,
		shotSpeed = 90, -- studs/s, so a flying hero can dodge
		shotRadius = 3.5,
		fleeBelow = 0.2, -- health fraction: backs off for a moment
		fleeTime = 1.5,
		radius = 2.5,
		body = {
			build = "slim",
			height = 5,
			metal = { 120, 130, 145 },
			eye = { 255, 120, 60 },
			suit = { 40, 70, 140 },
			trim = { 255, 170, 60 },
			jets = true,
		},
	},
	BurglarBot = {
		typeId = 2,
		name = "Burglar Bot",
		ai = "thief",
		hp = 150,
		speed = 20,
		aggro = 70, -- sees a hero this close and runs
		cornered = 30, -- a hero this close: it turns and fires
		attackRange = 30,
		fire = { every = 1.5, shotSpeed = 160, shotRadius = 3 },
		coeff = 0.8,
		fleeBelow = 0,
		radius = 2.5,
		loot = 40, -- runs between loot spots this far from home
		body = {
			build = "normal",
			height = 5.5,
			metal = { 70, 70, 85 },
			eye = { 255, 220, 80 },
			suit = { 62, 62, 72 },
			trim = { 30, 30, 36 },
			mask = true,
		},
	},
	SneakBot = {
		typeId = 3,
		name = "Sneak Bot",
		ai = "sneak",
		hp = 120,
		speed = 26,
		aggro = 90,
		attackRange = 6, -- melee
		cloak = { time = 4, every = 9 }, -- cloaked for 4 s, then visible until the next cloak
		stab = { cooldown = 1.5, backCoeff = 1.0, frontCoeff = 0.4, behindAngle = 70 },
		coeff = 1.0,
		fleeBelow = 0,
		radius = 2.2,
		body = {
			build = "slim",
			height = 5.5,
			metal = { 50, 45, 70 },
			eye = { 190, 90, 255 },
			suit = { 45, 35, 70 },
			trim = { 170, 90, 255 },
		},
	},
	BruteBot = {
		typeId = 4,
		name = "Brute Bot",
		ai = "brute",
		hp = 600,
		speed = 12,
		aggro = 80,
		attackRange = 9, -- starts the slam this close
		slam = { radius = 8, windup = 0.8, every = 4 },
		coeff = 2.0,
		mitigation = 0.20,
		ccResist = 0.3,
		fleeBelow = 0,
		radius = 4,
		body = {
			build = "heavy",
			height = 8,
			metal = { 150, 95, 60 },
			eye = { 255, 70, 50 },
			suit = { 150, 45, 45 },
			trim = { 240, 200, 80 },
		},
	},
	Turret = {
		typeId = 5,
		name = "Sentry", -- a planted heavy android with an arm cannon (the spec's Turret)
		ai = "sentry",
		hp = 400,
		speed = 0,
		aggro = 70,
		attackRange = 70,
		turnRate = 90, -- degrees per second
		aimCone = 10, -- fires when the target is within this many degrees of its facing
		fire = { every = 0.4, shotSpeed = 120, shotRadius = 2.5 },
		shield = { every = 6, time = 1.5 }, -- the shield flickers on: hits are blocked
		coeff = 0.6,
		immune = { "knockback", "knockup", "pull", "float" },
		fleeBelow = 0,
		radius = 3,
		body = {
			build = "heavy",
			height = 6.5,
			metal = { 95, 110, 120 },
			eye = { 80, 220, 255 },
			suit = { 60, 90, 112 },
			trim = { 80, 220, 255 },
			planted = true,
		},
	},
	NullSentinel = {
		typeId = 6,
		name = "Null Sentinel",
		ai = "guard",
		hp = 900,
		speed = 14,
		aggro = 90,
		attackRange = 7,
		sweep = { radius = 6, windup = 0.6, every = 2.5, arc = 140 },
		turnRate = 120,
		guard = { front = 120, block = 0.8, breakTime = 4, breakStun = 1 }, -- front hits lose 80%; a flank hit breaks it
		coeff = 1.5,
		ccResist = 0.5,
		fleeBelow = 0,
		radius = 3.5,
		elite = true,
		body = {
			build = "heavy",
			height = 7.5,
			metal = { 35, 35, 45 },
			eye = { 255, 255, 255 },
			suit = { 30, 30, 42 },
			trim = { 235, 235, 245 },
			cape = { 92, 40, 140 },
			shield = true,
		},
	},
	-- The look every robot shares (nate, 2026-11-16: "more humanoid, Terminator style ... look like a
	-- superhuman race but robotic internals that show as they take more damage"). Each robot is an original
	-- superhuman android soldier: a synthetic shell (uniform, cartoon skin, hair, chest mark) over a metal
	-- endoskeleton. The shell breaks off in clean panels with sparks as health drops (Shared.RobotDamage), in
	-- an order seeded by the robot's id so every device agrees: limbs first, then the belly and chest (the
	-- glowing core shows), the face last (a metal skull and glowing eyes). Machines only: under the shell is
	-- only metal, wires and light. PLACEHOLDER ART until the art pass (meshes, textures).
	look = {
		stripBy = 0.85, -- the whole shell is gone once 85% of health is lost
		spread = 1.5, -- seeded noise on the tiers below, so robots break differently
		sparksBelow = 0.35, -- the exposed core sparks under 35% health
		chipRange = 160, -- chips and sparks fly only for robots this close to the camera
		endo = { 168, 172, 182 }, -- endoskeleton chrome, tinted toward each robot's metal
		-- break tiers: lower goes earlier
		tiers = {
			ShUpperL = 1,
			ShUpperR = 1,
			ShLowerL = 1,
			ShLowerR = 1,
			ShThighL = 1,
			ShThighR = 1,
			ShShinL = 1,
			ShShinR = 1,
			Belly = 1.5,
			Cape = 1.5,
			ChestL = 2,
			ChestR = 2,
			Hair = 3,
			FaceL = 3,
			FaceR = 3.5,
		},
		-- cartoon synthetic skin tones and hair colours, picked per robot from its id
		skins = {
			{ 255, 214, 170 },
			{ 240, 190, 150 },
			{ 224, 172, 130 },
			{ 198, 140, 96 },
			{ 141, 95, 64 },
			{ 92, 62, 44 },
		},
		hair = { { 30, 26, 24 }, { 70, 46, 30 }, { 160, 120, 60 }, { 225, 225, 230 }, { 120, 40, 40 } },
	},
	caps = {
		perServer = 90,
		attackingOneHero = 6,
		aiTicksPerFrame = 40,
	},
	tickRate = 10, -- World.Tick (spec: Server lifecycle)
	-- M1/M2 stand-in for the incident spawner (M6): keep a few robots near every hero. The mix is weights.
	nearHero = { count = 4, radius = 150, minDistance = 60, respawn = 8 },
	mix = { SparkDrone = 5, BurglarBot = 3, SneakBot = 2, BruteBot = 1.5, Turret = 1, NullSentinel = 0.4 },
	melee = { reach = 2 }, -- added to a melee radius to cover the hero's body
}
