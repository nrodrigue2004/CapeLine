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
		-- the famous fakes and the evil twin (nate's lore, build plan step 4)
		"Radiant",
		"Bulwark",
		"Skylance",
		"EvilTwin",
		-- side quest mini villains that are famous fakes (nate's lore, build plan step 11)
		"HeadmasterHalo",
		-- The Gala Heist's costumed villains in powered suits (lore step 11, chain 2)
		"Redline",
		"MasqueARade",
		-- the Suburbs chain's clockwork toys (nate's lore, build plan step 11: Wind-Up Lane, the Toymaker)
		"WindupToy",
		"WindupGiant",
		-- The Harvest King's chain (lore step 11, chain 4): his crop beast and the King in his thresher suit
		"Bramblebeast",
		"HarvestKing",
		-- the Coast chain's robot pirates and their captain (nate's lore, build plan step 11: The Salt Dogs)
		"SaltDog",
		"CaptainBrine",
	},
	scale = { hpPerLevel = 0.1, dmgBase = 20, dmgPerLevel = 4 },
	SparkDrone = {
		typeId = 1,
		name = "Crane Trooper", -- a jet-boot android (was "Spark Trooper" before nate's lore; id SparkDrone kept so saves and data stay put)
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
		-- the lunge (spec H1: "Sneak Bots charge a lunge"; WP6, NATE TO TUNE): from `min` to `range` studs off
		-- it winds up for `windup` s (it shows itself; a lane `width` wide shows on the ground to a spot `over`
		-- studs past the hero), then dashes `time` s at `speed` and strikes once at `coeff`, a breaker against
		-- a block. An interrupt in the wind-up cuts it off. Once every `every` s.
		lunge = {
			min = 8,
			range = 18,
			over = 3,
			windup = 0.65,
			time = 0.45,
			speed = 60,
			width = 3.5,
			coeff = 1.4,
			every = 7,
		},
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
		name = "Warden", -- a guard android with a front shield (was "Null Sentinel" before nate's lore)
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
	-- The famous fakes (nate's lore, build plan step 4): Silas Crane's robots in place of the city's famous solo
	-- heroes. The public knows them as heroes with their own names and looks and never ties them to Crane, so a
	-- fake wears a full hero look built from the hero creator's own pieces (`fake.look`: piece names per slot,
	-- palette colours; Shared.FakeRules turns it into a LookCodec look, and CreatorRules validates it) and its
	-- plate shows its hero name and title, with no robot tag. As its health falls to `fakes.crack`, its face
	-- cracks to show metal and a glowing eye (unmasked: the plate turns to FAKE in red), then the rest of the
	-- shell breaks off like any robot's. Its attacks are drawn in one power path's own look (fake.path).
	-- 2026-11-18 art: each fake also has a hero suit and a famous face of its own (Config.NpcLooks.people Radiant,
	-- Bulwark, Skylance; art/clothes/people.py, Shared.PeopleLooks), worn in place of the look's suit once nate
	-- uploads them, with its own cracked face for the unmask; the look's cape, gloves, boots and emblem stay.
	-- Mini-boss tier: HP well above the elites, damage per second between the elite robots and the hardest-hitting
	-- world boss (tests/balance_enemies.luau). Never in the ambient mix or the open-world swaps: story missions
	-- (step 5) and world events (step 9) place them.
	Radiant = {
		typeId = 19,
		on = true,
		name = "Radiant", -- the golden flyer: light bolts from the air, then a dive
		fake = {
			title = "The Golden Dawn",
			path = "Light",
			look = {
				gender = 1,
				build = 2,
				height = 4,
				skin = 2,
				hair = 4, -- gold
				colors = { 4, 18, 47 }, -- gold, white, electric yellow
				pieces = {
					suit = "Chevron Suit",
					back = "Long Cape",
					hands = "Long Cuffs",
					feet = "Winged Boots",
					emblem = "Burst",
					hat = "Halo",
					shoulders = "Epaulettes",
					belt = "Sash",
					trail = "Sparkle Trail",
					visage = "Shiny Teeth", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Blonde Spiked Hair", -- Roblox catalog hair
				},
				tints = { back = { 18, 4, 0 }, belt = { 18, 0, 0 } }, -- a white cape with gold trim, a white sash
				mats = { shoulders = "Metal" },
			},
		},
		ai = "flyer",
		hp = 2600,
		flies = true,
		speed = 36,
		hover = { min = 18, max = 40 },
		aggro = 110,
		attackRange = 70,
		orbit = { min = 28, max = 44 },
		burst = { shots = 3, gap = 0.2, every = 3 },
		coeff = 0.46,
		shotSpeed = 130,
		shotRadius = 4,
		shotStyle = 4, -- a power path's shot (CombatFx.pathShot in fake.path's look)
		-- every 8 s a ring shows under its hero for 1.1 s, then it dives there: heroes within 11 studs are hit
		dive = { every = 8, windup = 1.1, radius = 11, coeff = 2.2 },
		fleeBelow = 0,
		fleeTime = 0,
		mitigation = 0.1,
		ccResist = 0.5,
		radius = 3,
		elite = true,
		miniBoss = true,
		body = {
			build = "normal",
			gender = 1,
			height = 5.8,
			metal = { 200, 180, 120 },
			eye = { 255, 220, 120 },
			suit = { 255, 210, 60 },
			trim = { 245, 245, 245 },
		},
	},
	Bulwark = {
		typeId = 20,
		on = true,
		name = "Bulwark", -- the giant tank: a tower shield in front, slams, charges and shockwaves
		fake = {
			title = "The Unbreakable",
			path = "Colossus",
			look = {
				gender = 1,
				build = 4, -- Titan
				height = 5,
				skin = 4,
				hair = 22, -- black
				colors = { 10, 19, 47 }, -- blue, silver, electric yellow
				pieces = {
					suit = "Plated Suit",
					hands = "Armored Gauntlets",
					feet = "Combat Boots",
					shoulders = "Great Pauldrons",
					belt = "Champion Belt",
					arms = "Arm Plates",
					emblem = "Hex Badge",
					visage = "Man Face", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Black Short Parted Hair", -- Roblox catalog hair (a full hero look wears hair)
				},
				tints = { shoulders = { 19, 10, 0 } },
				mats = { suit = "Metal", shoulders = "Metal" },
			},
		},
		ai = "brute",
		hp = 4200,
		speed = 15,
		aggro = 100,
		attackRange = 10, -- starts the shield slam this close
		slam = { radius = 10, windup = 0.8, every = 3 },
		coeff = 2.8,
		-- every 3rd slam is a shockwave instead: a wide ring (1.3 s warning) that misses heroes 4+ studs up
		shockwave = { nth = 3, radius = 24, windup = 1.3, coeff = 2.5, height = 4 },
		-- a hero 16 to 45 studs off: a lane shows for 0.9 s, then it charges 40 studs down it; a hero in its
		-- path (5 studs wide) is hit and stunned 0.4 s. Every 7 s at most.
		charge = {
			min = 16,
			range = 45,
			every = 7,
			windup = 0.9,
			dist = 40,
			width = 5,
			coeff = 2.3,
			stun = 0.4,
		},
		-- its tower shield: front hits lose half; a hit from the side or back breaks the guard and stuns it
		guard = { front = 110, block = 0.5, breakTime = 3, breakStun = 0.8 },
		mitigation = 0.15,
		ccResist = 0.6,
		immune = { "knockup", "float" },
		fleeBelow = 0,
		radius = 5,
		elite = true,
		miniBoss = true,
		body = {
			build = "titan",
			gender = 1,
			height = 9.5,
			metal = { 90, 100, 120 },
			eye = { 120, 200, 255 },
			suit = { 40, 110, 220 },
			trim = { 175, 180, 190 },
			riot = true,
		},
	},
	Skylance = {
		typeId = 21,
		on = true,
		name = "Skylance", -- the fast spear thrower: sights a hero, throws, then dashes aside
		fake = {
			title = "The Silver Streak",
			path = "Blade",
			look = {
				gender = 2,
				build = 1, -- Small
				height = 4,
				skin = 3,
				hair = 12, -- violet
				colors = { 33, 18, 46 }, -- azure, white, cyan glow
				pieces = {
					suit = "Racer Stripe",
					back = "Wind Scarf",
					hands = "Fingerless Gloves",
					feet = "Tall Boots",
					emblem = "Ring Star",
					shoulders = "Wingtips",
					arms = "Bracers",
					trail = "Streak Trail",
					visage = "Blinky", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "True Blue Hair", -- Roblox catalog hair
				},
				tints = { back = { 18, 33, 0 } },
				mats = {},
			},
		},
		ai = "sniper",
		hp = 2300,
		speed = 26,
		aggro = 130,
		attackRange = 100,
		keep = { min = 28, max = 70 },
		turnRate = 360,
		-- a short sighting line (0.8 s, the last 0.25 s locked), a spear, and again 1.4 s later
		aim = { time = 0.8, lock = 0.25, every = 1.4 },
		fire = { shotSpeed = 190, shotRadius = 3.5, coeff = 2.1 },
		shotStyle = 4,
		dash = { dist = 16 }, -- after each throw it dashes 16 studs to one side
		coeff = 0.8,
		mitigation = 0.05,
		ccResist = 0.4,
		fleeBelow = 0,
		radius = 2.6,
		elite = true,
		miniBoss = true,
		body = {
			build = "slim",
			gender = 2,
			height = 5.6,
			metal = { 170, 185, 200 },
			eye = { 80, 255, 255 },
			suit = { 60, 160, 230 },
			trim = { 245, 245, 245 },
			spear = true, -- PLACEHOLDER ART: a plain-part spear in the right hand
		},
	},
	-- Headmaster Halo (nate's lore, build plan step 11: Downtown's chain, The Hero Academy): a famous fake who
	-- runs Halo Academy, a free "hero school" that finds kids with Sparks for Crane's copier workshop under it.
	-- The finale's mini villain (boss-lite, Config.SideQuests.finale): Radiant's flyer brain (bolts from the
	-- air and a dive, "pop quiz"), less health, and the step 4 face crack. Never in the ambient mix or swaps.
	HeadmasterHalo = {
		typeId = 23,
		on = true,
		name = "Headmaster Halo",
		fake = {
			title = "The Hero Teacher",
			path = "Mind",
			look = {
				gender = 1,
				build = 2,
				height = 4,
				skin = 1,
				hair = 19, -- silver
				colors = { 18, 33, 4 }, -- white, azure, gold
				pieces = {
					suit = "Split Tone",
					back = "High Collar Cape",
					hands = "Gloves",
					feet = "Boots",
					emblem = "Peak",
					hat = "Halo",
					shoulders = "Mantle",
					neck = "Medal",
					belt = "Sash",
					visage = "Angelic", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Hair Base In Brown", -- Roblox catalog hair
				},
				tints = { back = { 33, 4, 0 } }, -- an azure cape with gold trim
				mats = {},
			},
		},
		ai = "flyer",
		hp = 2000,
		flies = true,
		speed = 30,
		hover = { min = 14, max = 32 },
		aggro = 110,
		attackRange = 66,
		orbit = { min = 24, max = 40 },
		burst = { shots = 3, gap = 0.2, every = 3 },
		coeff = 0.46,
		shotSpeed = 120,
		shotRadius = 4,
		shotStyle = 4, -- a power path's shot (CombatFx.pathShot in fake.path's look)
		-- the pop quiz: every 8 s a ring shows under its hero for 1.2 s (a beat longer than Radiant's), then
		-- it dives there; damage a second in the fakes' band (tests: between the elites and the world bosses)
		dive = { every = 8, windup = 1.2, radius = 11, coeff = 2.2 },
		fleeBelow = 0,
		fleeTime = 0,
		mitigation = 0.1,
		ccResist = 0.5,
		radius = 3,
		elite = true,
		miniBoss = true,
		body = {
			build = "normal",
			gender = 1,
			height = 5.8,
			metal = { 190, 195, 210 },
			eye = { 120, 200, 255 },
			suit = { 245, 245, 245 },
			trim = { 60, 150, 230 },
		},
	},
	-- The Gala Heist's villains (nate's lore, build plan step 11, Downtown chain 2): costumed thieves, not
	-- Crane's fakes, who fight in powered suits (nate's rule: machine enemies; robots spark). They wear a hero
	-- look like a fake does (`fake` with costumed = true: Shared.FakeRules) but never crack or read FAKE; the
	-- costume tears off the suit's frame over the last half of its health. The finale's two boss-lite fights
	-- (Config.SideQuests.finale, the encore). Never in the ambient mix or swaps. Attack numbers are the
	-- famous fakes' (Skylance's and Headmaster Halo's), so they sit in the fakes' damage band.
	-- Redline: the getaway racer, King of the Rooftops: Skylance's sighting brain at a racer's speed, Fire-path
	-- blasts from his rocket boots, and a long sidestep dash after each one.
	Redline = {
		typeId = 24,
		on = true,
		name = "Redline",
		fake = {
			costumed = true,
			title = "King of the Rooftops",
			path = "Fire",
			look = {
				gender = 1,
				build = 1, -- Small: a lean racer
				height = 3,
				skin = 5,
				hair = 1, -- red
				colors = { 1, 22, 24 }, -- red, black, ember
				pieces = {
					suit = "Racer Stripe",
					head = "Visor Band",
					hat = "Flight Goggles",
					hands = "Fingerless Gloves",
					feet = "Jet Boots",
					emblem = "Spark",
					back = "Hero Scarf",
					trail = "Streak Trail",
					visage = "Meanie", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Black Anime Hair", -- Roblox catalog hair
				},
				tints = { back = { 1, 22, 0 } }, -- a red scarf with black trim
				mats = {},
			},
		},
		ai = "sniper",
		hp = 1800,
		speed = 34,
		aggro = 130,
		attackRange = 100,
		keep = { min = 24, max = 64 },
		turnRate = 360,
		aim = { time = 0.8, lock = 0.25, every = 1.4 },
		fire = { shotSpeed = 190, shotRadius = 3.5, coeff = 2.1 },
		shotStyle = 4,
		dash = { dist = 22 }, -- a racer's sidestep: further than Skylance's
		coeff = 0.8,
		mitigation = 0.05,
		ccResist = 0.4,
		fleeBelow = 0,
		radius = 2.6,
		elite = true,
		miniBoss = true,
		body = {
			build = "slim",
			gender = 1,
			height = 5.4,
			metal = { 120, 110, 110 },
			eye = { 255, 80, 40 },
			suit = { 220, 40, 40 },
			trim = { 30, 30, 34 },
		},
	},
	-- Madame Masque-a-rade: the masked thief who plans the jobs and leads the crew: Headmaster Halo's flyer
	-- brain (ribbon wires: she floats over the fight, throws Shadow-path bolts and swoops on a hero, "the curtain
	-- drop").
	MasqueARade = {
		typeId = 25,
		on = true,
		name = "Madame Masque-a-rade",
		fake = {
			costumed = true,
			title = "The Masked Thief",
			path = "Shadow",
			look = {
				gender = 2,
				build = 2,
				height = 4,
				skin = 2,
				hair = 35, -- deep purple
				colors = { 35, 4, 48 }, -- deep purple, gold, ultraviolet
				pieces = {
					suit = "Split Tone",
					back = "High Collar Cape",
					head = "Masquerade",
					hands = "Long Cuffs",
					feet = "Tall Boots",
					emblem = "Diamond",
					shoulders = "Feather Pads",
					neck = "Choker",
					trail = "Ribbon Trail",
					visage = "Happy Wink", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Black and Red", -- Roblox catalog hair
				},
				tints = { back = { 4, 35, 0 } }, -- a gold cape lined in purple
				mats = {},
			},
		},
		ai = "flyer",
		hp = 2000,
		flies = true,
		speed = 30,
		hover = { min = 12, max = 28 },
		aggro = 110,
		attackRange = 66,
		orbit = { min = 24, max = 40 },
		burst = { shots = 3, gap = 0.2, every = 3 },
		coeff = 0.46,
		shotSpeed = 120,
		shotRadius = 4,
		shotStyle = 4,
		dive = { every = 8, windup = 1.2, radius = 11, coeff = 2.2 },
		fleeBelow = 0,
		fleeTime = 0,
		mitigation = 0.1,
		ccResist = 0.5,
		radius = 3,
		elite = true,
		miniBoss = true,
		body = {
			build = "normal",
			gender = 2,
			height = 5.8,
			metal = { 150, 120, 170 },
			eye = { 200, 120, 255 },
			suit = { 80, 30, 120 },
			trim = { 230, 190, 60 },
		},
	},
	-- The Toymaker's clockwork toys (nate's lore, build plan step 11: the Suburbs chain, Wind-Up Lane). Machines
	-- an old inventor built: tin soldiers, lawn gnomes and patchwork plush bears with a key in the back, wound up
	-- by a powered kid's tantrums (his Spark makes clockwork run). They burst into springs and gears like any
	-- robot. Side quest only: never in the ambient mix or the open-world swaps. Comic, never scary: they march,
	-- hop and nip. The three uniform versions are the three toys (Config.NpcLooks: Grunt a tin soldier, Veteran a
	-- lawn gnome, Elite a plush bear). PLACEHOLDER ART: the wind-up key on the back is plain parts.
	WindupToy = {
		typeId = 30,
		on = true,
		name = "Wind-Up Toy", -- a knee-high clockwork toy: marches up, hops in and nips
		ai = "swarm",
		hp = 45,
		speed = 22,
		aggro = 80,
		attackRange = 3.5,
		lunge = { range = 12, speed = 55, time = 0.3, every = 3.5 }, -- a wind-up hop
		bite = { every = 0.9 },
		coeff = 0.18,
		attackWeight = 0.34, -- three toys count as one robot for the 6-on-one-hero cap
		fleeBelow = 0,
		radius = 1.4,
		body = {
			build = "slim",
			height = 3.4,
			metal = { 190, 150, 70 }, -- brass clockwork
			eye = { 120, 220, 255 },
			suit = { 200, 40, 50 }, -- a tin soldier's red coat
			trim = { 240, 200, 80 },
			small = true,
			windKey = true,
		},
	},
	-- The Toymaker's masterpiece (the Suburbs chain's finale, boss-lite: Config.SideQuests.finale): a giant
	-- clockwork tin soldier he winds up himself and rides into the fight (dressed as the toy band's drummer: its
	-- chest is a toy drum, Config.NpcLooks, so it never reads as one of its own tin soldiers). The brute brain: a
	-- stomp with a warning ring, every 3rd stomp a wide ground wave, and a wind-up charge down a lane. Its damage
	-- a second stays at or under the elite robots' (tests: a boss-lite, not a world boss); its health is the
	-- finale's hpMult.
	WindupGiant = {
		typeId = 31,
		on = true,
		name = "Wind-Up Giant",
		ai = "brute",
		hp = 1800,
		speed = 13,
		aggro = 100,
		attackRange = 10,
		slam = { radius = 10, windup = 0.9, every = 3.4 },
		coeff = 2.2,
		shockwave = { nth = 3, radius = 22, windup = 1.4, coeff = 2.0, height = 4 },
		charge = {
			min = 16,
			range = 45,
			every = 8,
			windup = 1.1, -- the key winds round twice before it rolls
			dist = 40,
			width = 5,
			coeff = 2.0,
			stun = 0.3,
		},
		mitigation = 0.15,
		ccResist = 0.6,
		immune = { "knockup", "float" },
		fleeBelow = 0,
		radius = 5,
		elite = true,
		miniBoss = true,
		body = {
			build = "titan",
			gender = 1,
			height = 10,
			metal = { 190, 150, 70 },
			eye = { 255, 220, 120 },
			suit = { 190, 35, 45 },
			trim = { 240, 200, 80 },
			windKey = true,
		},
	},
	-- The Harvest King's chain (nate's lore, build plan step 11, chain 4: Farmland). Not Crane's. They wear a
	-- fixed creator look like the costumed villains (`fake` with costumed = true: never cracks, no FAKE plate).
	-- Attack numbers are the famous fakes' (Bulwark's and the evil twin's lobber), so both sit in the fakes'
	-- damage band. Never in the ambient mix or swaps.
	-- The Bramblebeast: the giant crop beast the Harvest King grew with his Spark, vines and pumpkin rind round
	-- a glowing core. A cartoon creature, not a machine (nate's rule: creatures burst into light, never blood):
	-- `creature` keeps its body whole (no shell to break off, no sparks) and it bursts into golden light when
	-- beaten, shrinking back into a seed. Bulwark's brute brain without the tower shield: vine slams, a
	-- shockwave stomp and a charge. PLACEHOLDER ART: a creator look on the blocky rig until a creature mesh.
	Bramblebeast = {
		typeId = 26,
		on = true,
		name = "Bramblebeast",
		fake = {
			costumed = true,
			creature = true,
			title = "The Hungry Harvest",
			path = "Earth",
			look = {
				gender = 1,
				build = 4, -- Titan
				height = 5,
				skin = 28, -- the glowing Energy skin: a pumpkin's light inside the vines
				hair = 7, -- green
				colors = { 30, 6, 3 }, -- forest, lime, orange
				pieces = {
					suit = "Magma Veins",
					hat = "Antlers",
					shoulders = "Fur Trim",
					hands = "Talon Gloves",
					feet = "Fur Boots",
					back = "Tattered Cape",
					eyes = "Toxic Glow",
					face = "Fangs",
					visage = "ROAR", -- Roblox catalog face (picked for the character, 2026-11-19)
				},
				hairless = true, -- no catalog hair: a bark and vine creature
				tints = { back = { 30, 6, 0 }, hat = { 16, 29, 0 } }, -- a leafy cape, branch horns
				mats = {},
			},
		},
		ai = "brute",
		hp = 3600,
		speed = 15,
		aggro = 100,
		attackRange = 10,
		slam = { radius = 10, windup = 0.8, every = 3 },
		coeff = 2.8,
		shockwave = { nth = 3, radius = 24, windup = 1.3, coeff = 2.5, height = 4 },
		charge = {
			min = 16,
			range = 45,
			every = 7,
			windup = 0.9,
			dist = 40,
			width = 5,
			coeff = 2.3,
			stun = 0.4,
		},
		mitigation = 0.15,
		ccResist = 0.6,
		immune = { "knockup", "float" },
		fleeBelow = 0,
		radius = 5,
		elite = true,
		miniBoss = true,
		body = {
			build = "titan",
			gender = 1,
			height = 9.5,
			metal = { 255, 200, 90 }, -- no metal inside: the golden light it bursts into
			eye = { 140, 255, 90 },
			suit = { 50, 130, 60 },
			trim = { 255, 150, 40 },
		},
	},
	-- The Harvest King: the farmer himself in his thresher suit (a powered suit rigged from a combine harvester:
	-- a machine that sparks apart). The evil twin lobber's brain: he keeps his distance and lobs pumpkin bombs
	-- that leave a patch of thorny vines (the bomber's burning patch).
	HarvestKing = {
		typeId = 27,
		on = true,
		name = "The Harvest King",
		fake = {
			costumed = true,
			title = "Lord of the Fields",
			path = "Earth",
			look = {
				gender = 1,
				build = 3, -- Heavy: a big farmer in a bigger suit
				height = 4,
				skin = 4,
				hair = 19, -- silver
				colors = { 28, 30, 16 }, -- mustard, forest, brown
				pieces = {
					suit = "Overalls",
					hat = "Iron Crown",
					beard = "Styled Beard Blonde", -- a Roblox catalog beard (gap-villains, 2026-11-19)
					hands = "Work Gloves",
					feet = "Boots",
					shoulders = "Riveted Pads",
					back = "Field Coat",
					belt = "Rope Belt",
					visage = "Take Over the World", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Blonde Curly Celebrity Hair", -- Roblox catalog hair
				},
				tints = { hat = { 4, 28, 0 } }, -- the crown in wheat gold
				mats = { shoulders = "Metal" },
			},
		},
		ai = "bomber",
		hp = 2200,
		speed = 18,
		aggro = 100,
		attackRange = 60,
		keep = { min = 20, max = 45 },
		turnRate = 240,
		grenade = { every = 3, flight = 1, radius = 8, coeff = 1.2, spread = 3 },
		zone = { radius = 6, time = 3, tick = 0.5, coeff = 0.2 },
		coeff = 1,
		mitigation = 0.1,
		ccResist = 0.5,
		fleeBelow = 0,
		radius = 3.2,
		elite = true,
		miniBoss = true,
		body = {
			build = "heavy",
			gender = 1,
			height = 6.6,
			metal = { 150, 130, 90 },
			eye = { 255, 220, 80 },
			suit = { 200, 160, 50 },
			trim = { 40, 100, 50 },
		},
	},
	-- The Salt Dogs (nate's lore, build plan step 11: the Coast chain, Captain Brine's crew): old diving robots
	-- Brine salvaged off the sea floor and patched up as pirate deckhands, with a steel hook for a hand and a red
	-- bandana round the dome. They board in a rush, leap in and swipe; they burst into sparks, bolts and a
	-- splash of sea water like any robot. Side quest only: never in the ambient mix or the open-world swaps.
	-- The three uniform versions are the crew's ranks (Config.NpcLooks: Grunt a striped deckhand, Veteran a
	-- gunner's navy coat, Elite the bosun's red coat), each with the crew's red neckerchief or the striped jersey.
	-- PLACEHOLDER ART: the hook and bandana are plain parts (the bandana breaks off with the head's shell).
	SaltDog = {
		typeId = 28,
		on = true,
		name = "Salt Dog",
		ai = "swarm",
		hp = 90,
		speed = 21,
		aggro = 85,
		attackRange = 4.5,
		lunge = { range = 16, speed = 55, time = 0.35, every = 4 }, -- a boarding leap
		bite = { every = 1.0 }, -- a hook swipe
		coeff = 0.3,
		attackWeight = 0.5, -- two deckhands count as one robot for the 6-on-one-hero cap
		fleeBelow = 0,
		radius = 2.2,
		body = {
			build = "normal",
			height = 5.2,
			metal = { 140, 95, 65 }, -- rusty diving-robot brass
			eye = { 120, 230, 255 },
			suit = { 40, 60, 110 },
			trim = { 230, 60, 50 },
			hook = true,
		},
	},
	-- Captain Brine (the Coast chain's finale, boss-lite: Config.SideQuests.finale): a powered pirate, a salvage
	-- diver whose Spark moves the tide, fighting in his powered brass diving rig (the machine-enemy rule, like
	-- the Gala Heist's costumed villains: fake.costumed, so no face crack and no FAKE plate; the coat tears off
	-- the rig over the last half of his health). The brute brain on Bulwark's attack numbers (the fakes' damage
	-- band): his anchor slam with a warning ring, every 3rd slam a tide wave, and a charge riding a wave down a
	-- lane. Never in the ambient mix or the swaps. PLACEHOLDER ART: the anchor he swings is plain parts.
	CaptainBrine = {
		typeId = 29,
		on = true,
		name = "Captain Brine",
		fake = {
			costumed = true,
			title = "Captain of the Salt Dogs",
			path = "Tide",
			look = {
				gender = 1,
				build = 3, -- Heavy: the diving rig
				height = 4,
				skin = 3,
				hair = 40, -- sea-salt white
				colors = { 32, 27, 38 }, -- deep teal, bronze, maroon
				pieces = {
					suit = "Plated Suit",
					back = "Duster Coat",
					hat = "Wide Brim",
					head = "Eye Patch",
					beard = "Styled Beard Blonde", -- a Roblox catalog beard (gap-villains, 2026-11-19)
					hands = "Armored Gauntlets",
					feet = "Armored Boots",
					shoulders = "Epaulettes",
					emblem = "Cross",
					visage = "Bad Dog", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Blonde Action Ponytail", -- Roblox catalog hair
				},
				tints = { back = { 38, 27, 0 } }, -- a maroon coat with bronze trim
				mats = { suit = "Metal" },
			},
		},
		ai = "brute",
		hp = 2200,
		speed = 15,
		aggro = 100,
		attackRange = 10, -- starts the anchor slam this close
		slam = { radius = 10, windup = 0.8, every = 3 },
		coeff = 2.8,
		-- every 3rd slam is a tide wave instead: a wide ring (1.3 s warning) that misses heroes 4+ studs up
		shockwave = { nth = 3, radius = 24, windup = 1.3, coeff = 2.5, height = 4 },
		-- a hero 16 to 45 studs off: a lane shows for 0.9 s, then he rides a wave 40 studs down it
		charge = {
			min = 16,
			range = 45,
			every = 7,
			windup = 0.9,
			dist = 40,
			width = 5,
			coeff = 2.3,
			stun = 0.4,
		},
		mitigation = 0.15,
		ccResist = 0.6,
		immune = { "knockup", "float" },
		fleeBelow = 0,
		radius = 4,
		elite = true,
		miniBoss = true,
		body = {
			build = "heavy",
			gender = 1,
			height = 7.5,
			metal = { 180, 130, 70 },
			eye = { 120, 230, 255 },
			suit = { 20, 110, 120 },
			trim = { 180, 120, 40 },
			anchor = true,
		},
	},
	-- The evil twin: a fake that beat a real hero and copies them: it wears that player's exact look (their
	-- LookCodec record) and fights with moves from their own power path (twin.paths: each path's fighting
	-- style; twin.styles the brain and moves it takes). EnemyService.spawnTwin(player, pos, level) makes one
	-- for story missions (step 5) and a rare world event (step 9); its plate reads the player's hero name until
	-- it is unmasked. Spawned plainly (Dev, tests) it fights as twin.default with a default hero look.
	EvilTwin = {
		typeId = 22,
		on = true,
		name = "Evil Twin", -- never shown before it is unmasked: its plate reads the hero it copies
		fake = { title = "", path = "Volt" },
		twin = {
			default = "Volt",
			paths = {
				Volt = "blaster",
				Frost = "blaster",
				Fire = "blaster",
				Tide = "blaster",
				Earth = "lobber",
				Blade = "duelist",
				Gunslinger = "gunner",
				Gadgeteer = "lobber",
				Shadow = "striker",
				Titan = "smasher",
				Martial = "smasher",
				Juggernaut = "smasher",
				Colossus = "smasher",
				Pulse = "blaster",
				Mind = "blaster",
				Spirit = "blaster",
				Light = "blaster",
			},
			-- each style's fields go over the ones below (the blaster's are the base)
			styles = {
				blaster = {},
				gunner = {
					ai = "sniper",
					flies = false,
					speed = 22,
					aggro = 120,
					attackRange = 100,
					keep = { min = 26, max = 70 },
					turnRate = 360,
					aim = { time = 0.7, lock = 0.25, every = 1.5 },
					fire = { shotSpeed = 210, shotRadius = 3, coeff = 2.1 },
					dash = { dist = 14 },
					coeff = 0.8,
				},
				lobber = {
					ai = "bomber",
					flies = false,
					speed = 18,
					aggro = 100,
					attackRange = 60,
					keep = { min = 20, max = 45 },
					turnRate = 240,
					grenade = { every = 3, flight = 1, radius = 8, coeff = 1.2, spread = 3 },
					zone = { radius = 6, time = 3, tick = 0.5, coeff = 0.2 },
					coeff = 1,
				},
				striker = {
					ai = "sneak",
					flies = false,
					speed = 30,
					aggro = 110,
					attackRange = 6,
					cloak = { time = 2.5, every = 7 },
					stab = { cooldown = 2, backCoeff = 1.4, frontCoeff = 1, behindAngle = 70 },
					coeff = 1,
				},
				duelist = {
					ai = "sneak",
					flies = false,
					speed = 30,
					aggro = 110,
					attackRange = 6,
					cloak = false, -- a sword fighter walks straight in
					stab = { cooldown = 1.5, backCoeff = 1.1, frontCoeff = 1.1, behindAngle = 70 },
					coeff = 1,
				},
				smasher = {
					ai = "brute",
					flies = false,
					speed = 20,
					aggro = 100,
					attackRange = 9,
					slam = { radius = 9, windup = 0.8, every = 3 },
					coeff = 2.8,
					shockwave = { nth = 3, radius = 20, windup = 1.2, coeff = 2.5, height = 4 },
					charge = {
						min = 14,
						range = 40,
						every = 8,
						windup = 0.9,
						dist = 36,
						width = 5,
						coeff = 2.3,
						stun = 0.4,
					},
					mitigation = 0.1,
				},
			},
		},
		ai = "flyer",
		hp = 2800,
		flies = true,
		speed = 32,
		hover = { min = 14, max = 34 },
		aggro = 110,
		attackRange = 60,
		orbit = { min = 24, max = 40 },
		burst = { shots = 3, gap = 0.2, every = 2.6 },
		coeff = 0.6,
		shotSpeed = 120,
		shotRadius = 3.5,
		shotStyle = 4,
		fleeBelow = 0,
		fleeTime = 0,
		mitigation = 0.05,
		ccResist = 0.4,
		radius = 2.6,
		elite = true,
		miniBoss = true,
		body = {
			build = "normal",
			height = 5.3,
			metal = { 120, 120, 135 },
			eye = { 255, 60, 60 },
			suit = { 40, 110, 220 },
			trim = { 235, 60, 60 },
		},
	},
	-- shared by the fakes and the twin (Shared.FakeRules)
	fakes = {
		crack = 0.5, -- the face cracks (unmasked) once half its health is gone; the shell breaks off after that
		word = "FAKE", -- the plate once unmasked, in red
		plateRange = 160, -- studs: its name plate shows this far, like a hero's
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
		-- robots this close to the camera pose every frame; farther ones every poseEvery frames (per preset since
		-- the perf pass: Config.Presets enemyPoseNear and enemyPoseEvery; these are the fallback)
		poseNear = 120,
		poseEvery = 3,
		-- the ground walk (quality pass 2026-11-18, nate: "the enemies dont move properly"): robots on foot play
		-- Roblox's own R15 idle, walk and run (made by Roblox, free in every experience; the clips Roblox's default
		-- Animate gives every hero), blended by speed so the feet keep pace (Shared.LocoMath, Controllers.NpcLoco).
		-- Aimed rifles, shield arms, crouches and the jaw and cape go on top; flyers, sentries, lunges, coils and
		-- tumbles keep their code poses. Past `near` studs (per preset: Config.Presets enemyAnimNear) the cheaper
		-- code walk plays, its stride matched to the speed too (LocoMath.phaseRate).
		loco = {
			on = true,
			idle = "rbxassetid://507766388",
			walk = "rbxassetid://913402848",
			run = "rbxassetid://913376220",
			still = 0.75, -- studs/s (per heightScale): slower is standing
			walkAt = 6.4, -- the walk clip's own speed (Animate: 0.5 of 16 studs/s after its 1.25 root motion fix)
			runAt = 12.8, -- the run clip's own speed
			refLeg = 2, -- the standard R15 leg (Config.HeroRig at scale 1: soles to hips)
			minWarp = 0.4,
			maxWarp = 2.8, -- a Swarmer at 30 studs/s plays its run this fast at most
			fade = 0.2,
			near = 150,
		},
		endo = { 168, 172, 182 }, -- endoskeleton chrome, tinted toward each robot's metal
		-- every robot is on the blocky R15 rig (nate, 2026-11-16: "literally everyone should be r15"): its
		-- build uses the creator's body build with this index (Config.Creator.body.builds) for its proportions
		builds = { slim = 1, normal = 2, heavy = 3, titan = 4 },
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
