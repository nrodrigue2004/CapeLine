-- Enemies, machines only (spec: Enemies), drawn as humanoid robots (nate, 2026-11-16: "robots that look
-- like humans"): metal android bodies with glowing eyes. Defeats are sparks, bolts and parts, never blood.
-- Health and damage scale with the zone level: HP x (1 + 0.1 x (zone level - 1)); enemy damage =
-- (20 + 4 x level) x coeff. typeId goes on the wire (5 bits). (tune)
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
	order = {
		"SparkDrone",
		"BurglarBot",
		"SneakBot",
		"BruteBot",
		"Turret",
		"NullSentinel",
		"Diver",
		"Anchor",
		"TorpedoSentry",
		"ShieldBearer",
		"Captain",
		"Sniper",
		"Bomber",
		"MedicUnit",
		"Swarmer",
		"Mimic",
		"Interceptor",
		"Grappler",
	},
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
			-- the remade look (overhaul plan step 3): armoured shell meshes and textures from
			-- ReplicatedStorage.Art.Trooper (art/blender/trooper.py), else the plain shell
			art = "Trooper",
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
	-- Sea robots (nate 2026-11-16: underwater at launch). `sea` robots live only underwater (EnemySim keeps
	-- them in the water; Config.Deep.mix spawns them near a swimming hero) and land robots never enter it.
	Diver = {
		typeId = 7,
		name = "Diver", -- a frogman android with a jet pack and a glass helmet
		ai = "flyer",
		sea = true,
		hp = 130,
		flies = true,
		speed = 24,
		hover = { min = 4, max = 14 }, -- above the seabed
		aggro = 70,
		attackRange = 40,
		orbit = { min = 16, max = 28 },
		burst = { shots = 2, gap = 0.3, every = 2.2 },
		coeff = 0.55,
		shotSpeed = 70, -- a harpoon dart, slower in water
		shotRadius = 3,
		fleeBelow = 0.2,
		fleeTime = 1.5,
		radius = 2.5,
		body = {
			build = "slim",
			height = 5.5,
			metal = { 90, 130, 150 },
			eye = { 120, 255, 230 },
			suit = { 30, 80, 100 },
			trim = { 255, 200, 60 },
			jets = true,
			jetColor = { 120, 220, 255 },
			helmet = true,
			tank = true,
		},
	},
	Anchor = {
		typeId = 8,
		name = "Anchor", -- a heavy diving-suit android that walks the seabed and slams
		ai = "brute",
		sea = true,
		hp = 700,
		speed = 10,
		aggro = 70,
		attackRange = 9,
		slam = { radius = 10, windup = 0.9, every = 4 },
		coeff = 2.0,
		mitigation = 0.25,
		ccResist = 0.4,
		fleeBelow = 0,
		radius = 4,
		body = {
			build = "heavy",
			height = 8.5,
			metal = { 110, 100, 80 },
			eye = { 255, 160, 60 },
			suit = { 90, 80, 60 },
			trim = { 200, 150, 60 },
			helmet = true,
		},
	},
	TorpedoSentry = {
		typeId = 9,
		name = "Torpedo Sentry", -- planted on the seabed; fires slow torpedoes that turn after you
		ai = "sentry",
		sea = true,
		hp = 450,
		speed = 0,
		aggro = 80,
		attackRange = 80,
		turnRate = 70,
		aimCone = 20,
		fire = { every = 2.2, shotSpeed = 40, shotRadius = 4, home = 60, coeff = 1.4 }, -- home: degrees/s it turns
		shield = { every = 7, time = 1.5 },
		coeff = 0.6,
		immune = { "knockback", "knockup", "pull", "float" },
		fleeBelow = 0,
		radius = 3,
		body = {
			build = "heavy",
			height = 6.5,
			metal = { 80, 100, 110 },
			eye = { 255, 90, 90 },
			suit = { 40, 70, 80 },
			trim = { 255, 90, 90 },
			planted = true,
			tank = true,
		},
	},
	-- The nine new robot types (nate, 2026-11-17: "we should have a good variety of enemies ... Dont want
	-- enemies to get repetitive"). Each one has its own switch: `on = false` cuts it, and a cut type never
	-- spawns anywhere (squad swaps, the ambient mix, escorts). They join open-world fights by swapping into
	-- squads as heroes level (Enemies.variety), so the first fights stay simple; story missions keep their
	-- set robots. New brains: "captain", "sniper", "bomber", "medic", "swarm", "mimic", "grappler"; the
	-- Shield Bearer is a "guard" and the Interceptor a "flyer" with new fields.
	ShieldBearer = {
		typeId = 10,
		on = true,
		name = "Shield Bearer", -- a riot shield wall: robots behind it are covered from the front
		ai = "guard",
		hp = 520,
		speed = 13,
		aggro = 80,
		attackRange = 7,
		sweep = { radius = 5.5, windup = 0.7, every = 3, arc = 90 }, -- a shield bash
		bash = { cc = "slow", time = 1.5, value = 0.5 }, -- the bash slows the hero it hits
		turnRate = 100,
		-- front hits do nothing; a hit from the side or back knocks the shield aside for 3.5 s
		guard = { front = 140, block = 1, breakTime = 3.5, breakStun = 1.2 },
		cover = { radius = 12, width = 4, cut = 0.6 }, -- robots right behind its shield take 60% less from the front
		coeff = 1.2,
		ccResist = 0.3,
		fleeBelow = 0,
		radius = 3,
		body = {
			build = "heavy",
			height = 7,
			metal = { 120, 125, 135 },
			eye = { 255, 200, 70 },
			suit = { 52, 60, 78 },
			trim = { 230, 190, 60 },
			riot = true,
		},
	},
	Captain = {
		typeId = 11,
		on = true,
		name = "Captain", -- hangs back and rallies the robots around it; take it out and the squad falters
		ai = "captain",
		hp = 460,
		speed = 18,
		aggro = 90,
		attackRange = 45,
		keep = { min = 22, max = 36 }, -- the distance it keeps from its hero, behind its squad
		fire = { every = 1.2, shotSpeed = 140, shotRadius = 3 },
		-- every 9 s it raises an arm for 0.8 s, then robots within 35 studs hit 25% harder and move 20% faster
		rally = { radius = 35, every = 9, windup = 0.8, time = 6, damage = 1.25, speed = 1.2 },
		leaderless = { slow = 0.6, time = 3 }, -- when it falls, the robots it rallied are slowed for 3 s
		escort = { kinds = { "BurglarBot", "SparkDrone" }, n = 2 }, -- an ambient Captain brings two
		coeff = 0.7,
		ccResist = 0.3,
		fleeBelow = 0,
		radius = 3,
		elite = true,
		body = {
			build = "normal",
			height = 6.5,
			metal = { 150, 140, 120 },
			eye = { 255, 215, 90 },
			suit = { 110, 30, 40 },
			trim = { 240, 200, 90 },
			cape = { 70, 20, 30 },
			cap = true,
		},
	},
	Sniper = {
		typeId = 12,
		on = true,
		name = "Sniper", -- a long red laser shows who it aims at; move once the laser locks
		ai = "sniper",
		hp = 160,
		speed = 16,
		aggro = 140,
		attackRange = 130,
		keep = { min = 50, max = 120 }, -- backs off from heroes closer than 50
		turnRate = 120,
		-- the laser shows for 1.6 s; for the last 0.35 s the aim is locked, so moving then dodges the shot
		aim = { time = 1.6, lock = 0.35, every = 4.5 },
		fire = { shotSpeed = 240, shotRadius = 2.5, coeff = 3 },
		coeff = 1,
		fleeBelow = 0,
		radius = 2.4,
		body = {
			build = "slim",
			height = 6,
			metal = { 90, 100, 95 },
			eye = { 255, 60, 60 },
			suit = { 60, 75, 55 },
			trim = { 35, 40, 35 },
			rifle = true,
			visor = true,
		},
	},
	Bomber = {
		typeId = 13,
		on = true,
		name = "Bomber", -- lobs grenades where you stand: a red ring shows where, then the ground burns
		ai = "bomber",
		hp = 280,
		speed = 14,
		aggro = 90,
		attackRange = 55,
		keep = { min = 20, max = 45 },
		turnRate = 140,
		-- a grenade lands 1.1 s after the throw at the hero's spot (up to 4 studs off), 7-stud blast
		grenade = { every = 3.5, flight = 1.1, radius = 7, coeff = 1.6, spread = 4 },
		zone = { radius = 6, time = 4, tick = 0.5, coeff = 0.25 }, -- then a burning patch for 4 s
		coeff = 1,
		fleeBelow = 0,
		radius = 3,
		body = {
			build = "heavy",
			height = 6.5,
			metal = { 130, 100, 70 },
			eye = { 255, 140, 40 },
			suit = { 95, 75, 40 },
			trim = { 255, 140, 40 },
			bandolier = true,
		},
	},
	MedicUnit = {
		typeId = 14,
		on = true,
		name = "Medic Unit", -- repairs the most damaged robot near it with a green beam: take it out first
		ai = "medic",
		hp = 190,
		speed = 20,
		aggro = 70,
		attackRange = 30,
		-- repairs 8% of a robot's health a second, robots under 95% within 28 studs (never another Medic)
		mend = { range = 28, perSecond = 0.08, below = 0.95, every = 1 },
		keep = { min = 18, behind = 8 }, -- stands 8 studs behind its patient, 18 or more from heroes
		fire = { every = 2, shotSpeed = 110, shotRadius = 2.5 }, -- a weak sidearm when nobody needs repair
		coeff = 0.4,
		fleeBelow = 0,
		radius = 2.4,
		body = {
			build = "slim",
			height = 5.5,
			metal = { 200, 205, 210 },
			eye = { 90, 255, 150 },
			suit = { 225, 230, 235 },
			trim = { 60, 200, 120 },
			medpack = true,
		},
	},
	Swarmer = {
		typeId = 15,
		on = true,
		name = "Swarmer", -- small fast robots in packs of 6: they surround you, lunge and nip
		ai = "swarm",
		pack = 6, -- a squad slot or an ambient spawn brings this many
		hp = 35,
		speed = 30,
		aggro = 80,
		attackRange = 3.5,
		lunge = { range = 14, speed = 70, time = 0.3, every = 3 },
		bite = { every = 0.8 },
		coeff = 0.16, -- a pack of 6 all nipping is about one Sentry
		attackWeight = 0.34, -- three Swarmers count as one robot for the 6-on-one-hero cap
		fleeBelow = 0,
		radius = 1.3,
		body = {
			build = "slim",
			height = 3,
			metal = { 110, 120, 60 },
			eye = { 200, 255, 60 },
			suit = { 70, 90, 30 },
			trim = { 200, 255, 60 },
			small = true,
		},
	},
	Mimic = {
		typeId = 16,
		on = true,
		name = "Mimic", -- walks like a citizen in street clothes until a hero is close, then springs
		ai = "mimic",
		hp = 300,
		speed = 24,
		aggro = 70,
		attackRange = 6,
		-- shows itself 12 studs from a hero; near a fight for 5 s, it walks up to one at a citizen's pace; a
		-- site's Mimic with no robot of its fight left within `alone` studs shows itself (so the site can finish)
		disguise = { reveal = 12, stalk = 5, walk = 6, alone = 150 },
		ambush = { delay = 0.35, coeff = 1.8 }, -- the first strike after it shows itself
		stab = { cooldown = 1.2 },
		coeff = 0.7,
		fleeBelow = 0,
		radius = 2.2,
		body = {
			build = "normal",
			height = 5.5,
			metal = { 100, 95, 110 },
			eye = { 255, 80, 200 },
			suit = { 70, 110, 160 }, -- its street clothes (the shirt; trim is the trousers)
			trim = { 60, 60, 70 },
			citizen = true,
		},
	},
	Interceptor = {
		typeId = 17,
		on = true,
		name = "Interceptor", -- a fast jet android that only hunts heroes in the air; its net drops you
		ai = "flyer",
		hunter = true, -- only goes after heroes at least `airborne` studs over the ground
		airborne = 10,
		hp = 140,
		flies = true,
		speed = 52,
		hover = { min = 30, max = 60 },
		aggro = 150,
		attackRange = 45,
		orbit = { min = 14, max = 24 },
		burst = { shots = 4, gap = 0.12, every = 2.2 },
		coeff = 0.4,
		shotSpeed = 120,
		shotRadius = 3,
		-- every 7 s a net shot: it holds a flier for 0.7 s, so the hero drops out of flight
		net = { every = 7, shotSpeed = 85, shotRadius = 4, cc = "root", time = 0.7 },
		fleeBelow = 0.25,
		fleeTime = 1.2,
		radius = 2.5,
		body = {
			build = "slim",
			height = 5.5,
			metal = { 150, 160, 175 },
			eye = { 80, 200, 255 },
			suit = { 200, 205, 215 },
			trim = { 40, 120, 220 },
			jets = true,
			jetColor = { 110, 200, 255 },
			wings = true,
		},
	},
	Grappler = {
		typeId = 18,
		on = true,
		name = "Grappler", -- fires a hook that pulls a hero down to it, then punches
		ai = "grappler",
		hp = 400,
		speed = 16,
		aggro = 90,
		attackRange = 6,
		-- the hook: 10 to 50 studs, every 6 s; a hero it hits is pulled to 6 studs and held 0.9 s
		hook = {
			min = 10,
			range = 50,
			every = 6,
			shotSpeed = 95,
			shotRadius = 3.5,
			reel = 6,
			time = 0.5,
			hold = 0.9,
			coeff = 0.5,
		},
		punch = { every = 1.4 },
		coeff = 0.9,
		mitigation = 0.1,
		ccResist = 0.3,
		fleeBelow = 0,
		radius = 3,
		body = {
			build = "heavy",
			height = 7,
			metal = { 120, 110, 100 },
			eye = { 255, 120, 60 },
			suit = { 70, 55, 45 },
			trim = { 200, 120, 50 },
			hookArm = true,
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
		poseNear = 120, -- robots this close to the camera pose every frame; farther ones every poseEvery frames
		poseEvery = 3,
		endo = { 168, 172, 182 }, -- endoskeleton chrome, tinted toward each robot's metal
		-- every robot is on the blocky R15 rig (nate, 2026-11-16: "literally everyone should be r15"): its
		-- build uses the creator's body build with this index (Config.Creator.body.builds) for its proportions
		builds = { slim = 1, normal = 2, heavy = 3 },
		-- break tiers, by R15 part (the shell) plus the hair and cape: lower goes earlier
		tiers = {
			LeftUpperArm = 1,
			RightUpperArm = 1,
			LeftLowerArm = 1,
			RightLowerArm = 1,
			LeftUpperLeg = 1,
			RightUpperLeg = 1,
			LeftLowerLeg = 1,
			RightLowerLeg = 1,
			LeftHand = 1.3,
			RightHand = 1.3,
			LeftFoot = 1.3,
			RightFoot = 1.3,
			LowerTorso = 1.5,
			Cape = 1.5,
			UpperTorso = 2,
			Hair = 3,
			Head = 3.5,
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
		-- human eyes until the robot turns (nate, 2026-11-17: "make the eyes look human before turning"): white
		-- eyes with an iris picked per robot; once it winds up an attack or its shell starts breaking, the eyes go
		-- dark and the irises glow in the robot's eye colour (red on a windup)
		irises = { { 70, 45, 30 }, { 50, 90, 140 }, { 70, 110, 70 }, { 110, 80, 50 }, { 40, 40, 45 } },
		sclera = { 242, 240, 234 },
		turnedSclera = { 22, 22, 28 },
	},
	caps = {
		perServer = 90,
		attackingOneHero = 6,
		aiTicksPerFrame = 40,
	},
	tickRate = 10, -- World.Tick (spec: Server lifecycle)
	-- M1/M2 stand-in for the incident spawner (M6): keep a few robots near every hero. The mix is weights.
	nearHero = { count = 4, radius = 150, minDistance = 60, respawn = 8 },
	mix = {
		SparkDrone = 5,
		BurglarBot = 3,
		SneakBot = 2,
		BruteBot = 1.5,
		Turret = 1,
		NullSentinel = 0.4,
		ShieldBearer = 0.8,
		Captain = 0.3,
		Sniper = 0.6,
		Bomber = 0.7,
		MedicUnit = 0.5,
		Swarmer = 0.5,
		Mimic = 0.4,
		Interceptor = 0.8,
		Grappler = 0.6,
	},
	-- Variety in open-world fights (incidents, contracts, events, side quests; SiteKit.squad through
	-- Shared.EnemyVariety): each robot of a squad may be swapped for one of the new types once the fight's
	-- level reaches the type's `level`, at `chance`, at most `max` of that type, only in squads of `minSquad`
	-- or more. Story missions and the opening keep their set robots. on = false turns all swaps off.
	variety = {
		on = true,
		swaps = {
			{
				kind = "Swarmer",
				from = { "SneakBot", "BurglarBot" },
				chance = 0.15,
				max = 1,
				level = 3,
				minSquad = 2,
			},
			{
				kind = "ShieldBearer",
				from = { "BurglarBot", "BruteBot", "SparkDrone" },
				chance = 0.2,
				max = 1,
				level = 4,
				minSquad = 3,
			},
			{ kind = "Interceptor", from = { "SparkDrone" }, chance = 0.3, max = 2, level = 4, minSquad = 2 },
			{
				kind = "Bomber",
				from = { "BruteBot", "BurglarBot" },
				chance = 0.2,
				max = 1,
				level = 5,
				minSquad = 3,
			},
			{
				kind = "Sniper",
				from = { "SparkDrone", "BurglarBot", "Turret" },
				chance = 0.15,
				max = 1,
				level = 6,
				minSquad = 3,
			},
			{
				kind = "MedicUnit",
				from = { "BurglarBot", "SneakBot", "SparkDrone" },
				chance = 0.2,
				max = 1,
				level = 6,
				minSquad = 3,
			},
			{
				kind = "Grappler",
				from = { "BruteBot", "BurglarBot" },
				chance = 0.18,
				max = 1,
				level = 7,
				minSquad = 3,
			},
			{
				kind = "Captain",
				from = { "BurglarBot", "SparkDrone", "SneakBot" },
				chance = 0.25,
				max = 1,
				level = 8,
				minSquad = 4,
			},
			{
				kind = "Mimic",
				from = { "SneakBot", "BurglarBot" },
				chance = 0.12,
				max = 1,
				level = 9,
				minSquad = 3,
			},
		},
	},
	melee = { reach = 2 }, -- added to a melee radius to cover the hero's body
}
