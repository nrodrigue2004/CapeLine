-- Movement kit (spec: Movement and combat rules > Movement kit). Studs and seconds. (tune)
-- Air moves use their own gravity (airGravity) so leaps feel floaty and comic-book, and so the client feel
-- and the server checks share one set of numbers.
return {
	run = { speed = 20, groundMax = 28 },
	-- the sprint for everyone (nate 2026-11-19 20:46Z: "everyone should get a sprint with shift, superspeed is just
	-- way faster"): hold Boost (Shift, LT; on touch the SPRINT button or the stick pushed to its edge) on the ground
	-- to run at `speed` (1.4x the run; caps.run 28 already covers it, so no server change), free of stamina.
	-- Super-speed keeps its own sprint (mobility.speed.sprint, 100 and up).
	sprint = { speed = 28, edge = 0.95, ease = 8 },
	airGravity = 120, -- studs/s^2 while leaping (Roblox default is 196.2)
	leap = {
		charge = 0.25, -- tap: the hero crouches this long, then launches
		apex = 40,
		range = 80,
		cooldown = 1.2,
		minCharge = 0.4, -- a released early leap still gets 40% of its height
	},
	glide = {
		fall = 12, -- studs/s down
		forward = 50,
		cap = 60,
		turnRate = 150, -- degrees per second
		blend = 3, -- how fast velocity settles into the glide (per second)
	},
	flight = {
		cruise = 60,
		boost = 110,
		up = 40,
		down = 55,
		turnRate = 120, -- degrees per second at speed
		freeTurnBelow = 20, -- below this speed the hero turns instantly
		accel = 90, -- studs/s^2 toward cruise
		boostAccel = 160,
		decel = 80, -- when the stick is let go: slows to a hover
		autoLevel = 2.5, -- per second: vertical drift fades when no up/down input
		bankMax = 35, -- degrees of lean into turns (Client)
		pitchMax = 80, -- body tilts this far toward horizontal at full speed (Client)
	},
	-- nate (2026-11-19, gaps7 playtest: "Player should have like double the stamina"): the pool doubles 100 -> 200;
	-- drains and regens per second unchanged, so boost lasts ~14 s (was ~7) and a wall run twice as long
	stamina = {
		max = 200,
		boostDrain = 14,
		-- nate 2026-11-20 00:03Z ("stamina/boost should refill quicker"): regen 15 -> 40 on the ground (a full
		-- refill in 5 s, was 13) and 8 -> 20 in the air (10 s), after `regenDelay` s without a drain (boost, wall
		-- runs, the crawl's scurry), so boosting still costs something
		regenGround = 40,
		regenAir = 20, -- gliding or cruising
		regenDelay = 0.6,
		boostMin = 10, -- boost needs this much to start
	},
	-- spec: cloud layer at 500, ceiling 600; raised 2026-11-17 for the skyscrapers (nate: "taller buildings"):
	-- the Uptown landmark's spire tops out at 820, so the clouds sit at 880 and the ceiling at 960
	-- band (nate's playtest 2026-11-19, "can't jump in tunnel"): the ceiling only acts up to hard + band. The
	-- mission pockets and the prologue's subway sit at y 3,000 (Config.Story.pockets), far above the sky, under
	-- their own roofs: a ceiling that acted there flattened every Leap and pushed every flight down
	ceiling = { soft = 920, hard = 960, push = 60, band = 400 },
	fall = { terminal = 220 }, -- fastest legal fall (Roblox freefall from the ceiling)
	-- Server caps per style (spec column "Server check"); position checks allow cap x tolerance
	caps = {
		run = 28,
		glide = 60,
		flight = 125,
		cruise = 60, -- flight without boost
	},
	tolerance = 1.15,
	-- Touch flight (spec: Touch flight)
	touch = {
		autoAimAngle = 25,
		autoAimRange = 60,
		markerFlySpeed = 75,
		markerClearance = 30,
	},
	-- Mobility (nate 2026-11-16): every hero picks one at creation, from level 1, swapped free in the creator
	-- at any safehouse or HQ. Everyone keeps the run, the leap above and the glide; the pick adds its own way
	-- of getting around. Each is tuned so crossing the 1,600-stud hub takes about 25 to 30 s. `cap` is the
	-- server's speed cap (MoveMath.speedCap); `swim` the underwater speed. Level upgrades in `up`. (tune)
	mobilityOrder = { "flight", "speed", "leap", "acrobat", "swing" },
	-- Mobility training (side-content, 2026-11-19; nate: "I dont see any mobility upgrades"): 5 ranks for each pick
	-- (each pick's `ranks` rows), trained in order from the POWERS screen's MOBILITY tab. Rank n opens at hero level
	-- levels[n] and costs costs[n] Credits (earned in play; never sold for Robux, and no rank is in the shop). Ranks
	-- are saved per hero and per pick (profile character mobRanks), so swapping picks keeps them. (tune)
	ranks = { levels = { 5, 12, 20, 30, 40 }, costs = { 150, 1800, 4000, 8000, 14000 } },
	-- The mobility upgrade rework (nate, 2026-11-20): ranks 1, 2 and 4 stay number bumps; ranks 3 and 5 (`choices`)
	-- also open a CHOICE of two new moves (each such row's `choice`). The hero picks one per rank once trained and
	-- swaps free at a safehouse or HQ (SafehouseService.canSwap); the picks are saved per hero and pick next to
	-- mobRanks (profile character mobMoves; Shared.MoveRanks.moveOf). Earned only, never sold; no move changes a stat.
	-- Each move's numbers are below (`moves`); every speed stays inside its pick's server cap (MoveRanks.check), and
	-- knocks and stuns on heroes go through PvpRules' compression.
	choices = { 3, 5 },
	moves = {
		-- Flight rank 3
		sonicDive = {
			name = "Sonic Boom Dive",
			text = "Dive from high up: land in a shockwave that knocks robots and cracks roofs",
			-- a dive (falling at `speed` or more after `drop` studs of fall) that hits the ground or a roof bursts
			-- `radius` round the landing: robots take `coeff` x the hero's power and a `knock`; a roof takes `dmg`
			drop = 40,
			speed = 70,
			radius = 16,
			coeff = 0.9,
			knock = 40,
			dmg = 900,
			cooldown = 4,
		},
		slipstream = {
			name = "Slipstream",
			text = "Allies in your wake fly faster; boost through a hole you broke to refill stamina",
			-- an ally flying within `width` of the line `length` studs behind a boosting Slipstream hero cruises up
			-- to `ally` x their cruise (never past their own boost, so inside their cap); a ram through a wall
			-- while boosting gives back `refill` stamina
			length = 60,
			width = 14,
			ally = 1.3,
			refill = 35,
			hold = 0.6, -- the wake's lift lasts this long after the ally leaves it (the server checks 5 times a second)
		},
		-- Flight rank 5
		phase = {
			name = "Phase",
			text = "Boost through buildings as a flicker, without breaking them",
			-- boosting into a wall passes through as a ghost for up to `time` s (stamina `drain` a second on top),
			-- every `cooldown` s after it ends; nothing breaks
			time = 1.2,
			drain = 18,
			cooldown = 3,
			clear = 3, -- the flicker holds on (up to 2 x time) while a building is within this many studs
		},
		-- (nate's sheet called it Comet; Comet is an old-lore name the text checks refuse, so it shows as Blazing Ram)
		blazeRam = {
			name = "Blazing Ram",
			text = "Rams leave a fire trail and blow walls outward, for more stamina",
			-- a ram's structure hit x `ram`, its pieces thrown outward x `throw`; each ram costs `stamina`; the fire
			-- trail burns robots `trailCoeff` x power a second within `trailRadius` for `trailLife` s
			ram = 1.6,
			throw = 1.8,
			stamina = 12,
			trailCoeff = 0.3,
			trailRadius = 6,
			trailLife = 3,
		},
		-- Super-speed rank 3
		tornadoRun = {
			name = "Tornado Run",
			text = "Run in a tight circle to raise a whirlwind that lifts robots and debris",
			-- `turns` full turns within `radius` of one middle at `speed` or more, inside `window` s, raise a whirlwind
			-- there for `life` s: robots within `lift.radius` rise `lift.up` and are stunned `stun` s, taking `coeff`
			turns = 1.5,
			radius = 26,
			speed = 50,
			window = 4,
			life = 3,
			lift = { radius = 18, up = 36 },
			stun = 1.5,
			coeff = 0.6,
			cooldown = 8,
		},
		afterimage = {
			name = "Afterimage",
			text = "Stop hard from top speed to leave a decoy that robots shoot at",
			-- slowing from `from` studs/s to under `to` within `within` s leaves a decoy where the hero stopped for
			-- `life` s (robots in `taunt` studs shoot it), every `cooldown` s
			from = 70,
			to = 12,
			within = 0.5,
			life = 4,
			taunt = 60,
			cooldown = 6,
		},
		-- Super-speed rank 5
		sonicWake = {
			name = "Sonic Wake",
			text = "Pass by at top speed to flip cars and shatter windows",
			-- running at `speed` or more: cars within `radius` flip (VehicleService), building faces within `radius`
			-- crack (a small structure hit, `dmg`, at most every `every` s a building)
			speed = 95,
			radius = 12,
			dmg = 150,
			every = 0.6,
		},
		blink = {
			name = "Blink",
			text = "A 30-stud dash in a blink, every 6 s",
			-- Boost tapped while running: the hero covers `range` studs along the stick (stopping short of walls) in
			-- `time` s (a server-granted move), every `cooldown` s
			range = 30,
			time = 0.12,
			cooldown = 6,
		},
		-- Leaping rank 3
		impactLanding = {
			name = "Impact Landing",
			text = "Big landings stun robots and crack the street, more from higher",
			-- a landing after `minFall` studs of fall: robots within radius (minFall: `radius[1]`, `fullFall`:
			-- `radius[2]`) are stunned `stun` s and take `coeff`; the street gets a crater from `crater` fall up
			minFall = 30,
			fullFall = 110,
			radius = { 8, 20 },
			stun = 1.2,
			coeff = 0.4,
			crater = 70,
			craterDmg = 1500,
			cooldown = 2,
		},
		wallCrusher = {
			name = "Wall Crusher",
			text = "Climb grabs punch handholds; a kick-off shatters the panel",
			-- each climb grab bites `bite` x the climb's bite damage; a kick-off hits the panel for `kick`
			bite = 2.5,
			kick = 1200,
			kickRadius = 6,
			cooldown = 1,
		},
		-- Leaping rank 5
		meteorStrike = {
			name = "Meteor Strike",
			text = "From the top of a leap, aim a pound that craters the ground",
			-- Down near the top of a leap (within `apex` of its peak speed) aims a pound at the camera's target up to
			-- `range` away; it lands at `speed`, bursting `radius` (`coeff`, `knock`) and digging a crater (`dmg`)
			apex = 18,
			range = 120,
			speed = 150,
			radius = 18,
			coeff = 1.1,
			knock = 50,
			dmg = 2400,
			cooldown = 6,
		},
		moonJump = {
			name = "Moon Jump",
			text = "One extra leap in mid-air",
			-- Leap in the air once a leap: a fresh tapped leap (`share` of a full one's speed) from where the hero is
			share = 0.7,
		},
		-- Acrobat rank 3
		kickChain = {
			name = "Kick Chain",
			text = "Each wall-kick in a row is faster, up to 5",
			-- each kick-off within `within` s of the last landing on a wall adds `step` to the next kick's speed, up to
			-- `most` in a row
			step = 0.07,
			most = 5,
			within = 1.2,
		},
		ceilingDrop = {
			name = "Ceiling Drop",
			text = "Drop from a wall or ceiling onto a robot for a takedown",
			-- letting go of a wall or ceiling with a robot within `reach` below: the hero drops on it, `coeff` x power
			-- (a takedown that floors a basic robot), stunning those within `radius`
			reach = 40,
			cone = 30,
			coeff = 2.5,
			radius = 8,
			stun = 1,
			cooldown = 3,
		},
		-- Acrobat rank 5
		shadowFlip = {
			name = "Shadow Flip",
			text = "A dodge flip leaves a clone that draws fire",
			-- each flip leaves a decoy where it started for `life` s (robots within `taunt` shoot it), every `cooldown` s
			life = 3,
			taunt = 50,
			cooldown = 4,
		},
		slingshot = {
			name = "Slingshot",
			text = "Crouch on a wall, then launch about 120 studs",
			-- hold Down on a wall for `charge` s, let go to launch away from it along the camera's look (a
			-- server-granted move of `range` studs over `time` s, arcing `up` at the top)
			charge = 0.5,
			range = 120,
			time = 1.3,
			up = 22,
			cooldown = 2,
		},
		-- Swing rank 3
		doubleZip = {
			name = "Double Zip",
			text = "Fire two lines at once and shoot forward between them",
			-- Leap while swinging fires a second line `spread` degrees off the first; the hero shoots forward from
			-- between them at `speed` (inside the zip cap), `range` studs
			spread = 40,
			speed = 120,
			range = 90,
			cooldown = 3,
		},
		yank = {
			name = "Yank",
			text = "Pull a car, chunk or robot to you, then throw it",
			-- Fly on the ground (or swinging) at a robot, car or loose chunk within `range` pulls it to the hero over
			-- `time` s; then it is carried and thrown like a picked-up prop (ImpactService throws)
			range = 70,
			time = 0.4,
			cone = 18, -- degrees off the camera's aim a target may be
			stun = 1.5, -- a yanked robot is dazed this long (so it can be held)
			cooldown = 5,
		},
		-- Swing rank 5
		wreckingKick = {
			name = "Wrecking Kick",
			text = "Kick through walls mid-swing; let go fast to bowl robots over",
			-- swinging into a wall at `speed` or more kicks it out (a ram); a release at `bowl` or more knocks robots
			-- within `radius` of the path for `knock`, `coeff`
			speed = 55,
			bowl = 90,
			radius = 8,
			knock = 35,
			coeff = 0.5,
			cooldown = 1.5,
		},
		skyHook = {
			name = "Sky Hook",
			text = "A full-strength line from the sky in open areas, every 10 s",
			-- when no building is in reach, the line hangs from the sky at full swing strength (not the weak sky
			-- line), every `cooldown` s
			cooldown = 10,
		},
	},
	mobility = {
		flight = {
			name = "Flight",
			text = "Fly anywhere: cruise, boost, hover and dive",
			swim = 50,
			up = { boostLevel = 10, boost = 120 }, -- level 10: faster boost (inside the 125 flight cap)
			-- training ranks (side-content, 2026-11-19; `ranks` below says when and what they cost): each row sets
			-- numbers in this hero's own copy of Config.Move (Shared.MoveRanks), so the device's feel and the server's
			-- speed caps (MoveMath.speedCap, MoveGuard) always move together
			ranks = {
				{
					name = "Tailwind",
					text = "Cruise 60 -> 66 studs/s",
					set = { { "flight.cruise", 66 }, { "caps.cruise", 66 } },
				},
				{
					name = "Afterburner",
					text = "Boost 120 -> 128 studs/s",
					set = {
						{ "flight.boost", 128 },
						{ "mobility.flight.up.boost", 128 },
						{ "caps.flight", 135 },
					},
				},
				{
					name = "Hard Banking",
					choice = { "sonicDive", "slipstream" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Sharper turns, faster take-off",
					set = {
						{ "flight.turnRate", 155 },
						{ "flight.accel", 125 },
						{ "flight.boostAccel", 215 },
					},
				},
				{
					name = "Jet Stream",
					text = "Cruise 74, boost 136, boost lasts longer",
					set = {
						{ "flight.cruise", 74 },
						{ "caps.cruise", 74 },
						{ "flight.boost", 136 },
						{ "mobility.flight.up.boost", 136 },
						{ "caps.flight", 145 },
						{ "stamina.boostDrain", 11 },
					},
				},
				{
					name = "Sound Barrier",
					choice = { "phase", "blazeRam" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Boost 148 studs/s and it drains less",
					set = {
						{ "flight.boost", 148 },
						{ "mobility.flight.up.boost", 148 },
						{ "caps.flight", 158 },
						{ "stamina.boostDrain", 9 },
					},
				},
			},
		},
		speed = {
			name = "Super-speed",
			text = "Run at 100 studs/s, up walls and across water",
			sprint = 100, -- top speed (hold Boost)
			accel = 70, -- studs/s^2 to top speed
			turnRate = 220, -- degrees per second at speed
			wallRun = 60, -- studs/s up a wall while sprinting into it
			wallDrain = 12, -- stamina per second on a wall
			waterRun = 45, -- the speed needed to run across water
			-- the running jump (nate's playtest 2026-11-18: "holding the jump without losing speed"): Leap while
			-- running faster than `from` is an instant hop that keeps the run's speed (no crouch, no slowdown),
			-- steers at turnRate in the air, and holding Leap hops again on every landing
			hop = { from = 30, up = 45, turnRate = 160, glideBelow = -60 },
			-- wall runs (nate's playtest 2026-11-19: "jump onto building and keep wall running"): a hop or fall into a
			-- wall at waterRun or more runs up it (wallRun) like the ground run does; a glancing one at hop.from or more
			-- runs along it at the run's speed; either keeps going while Boost or Leap is held and stamina lasts
			-- the smash rule (nate on the card, 2026-11-19 20:45Z): holding Boost at `smash` studs/s or more, a wall
			-- ahead (running or hopping) is smashed straight through (the flight ram, Config.Combat.impact.ram);
			-- without Boost the hero runs up it (`wall`) or along it (`wallrun`) as before, at any run speed
			smash = 45,
			cap = 100,
			swim = 60,
			up = { trailLevel = 12, trailSpeed = 70, trailRadius = 7, trailCoeff = 0.25 }, -- level 12: the trail hurts robots
			ranks = {
				{
					name = "Quick Feet",
					text = "Reach top speed faster, turn tighter",
					set = { { "mobility.speed.accel", 95 }, { "mobility.speed.turnRate", 260 } },
				},
				{
					name = "Fast Lane",
					text = "Top speed 100 -> 108 studs/s",
					set = { { "mobility.speed.sprint", 108 }, { "mobility.speed.cap", 108 } },
				},
				{
					name = "Wall Runner",
					choice = { "tornadoRun", "afterimage" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Run up walls faster, for longer",
					set = { { "mobility.speed.wallRun", 72 }, { "mobility.speed.wallDrain", 9 } },
				},
				{
					name = "Blur",
					text = "Top speed 116, higher running hops",
					set = {
						{ "mobility.speed.sprint", 116 },
						{ "mobility.speed.cap", 116 },
						{ "mobility.speed.hop.up", 52 },
					},
				},
				{
					name = "Lightning Legs",
					choice = { "sonicWake", "blink" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Top speed 125, walls cost half",
					set = {
						{ "mobility.speed.sprint", 125 },
						{ "mobility.speed.cap", 125 },
						{ "mobility.speed.wallDrain", 6 },
					},
				},
			},
		},
		leap = {
			name = "Leaping",
			text = "Huge charged leaps, wall bounces and a ground pound",
			-- nate's playtest 2026-11-19 ("Leap could be a bit better"): a shorter crouch, a bigger tap leap, the
			-- run's speed carried into the leap, a firmer air steer, bigger bounces that keep their speed along the
			-- wall, and a pound from lower down
			apex = 90,
			range = 200,
			charge = 0.25, -- was 0.4: the crouch before a full leap
			minCharge = 0.55, -- a tapped leap still gets 55% of the height (everyone else's: Config.Move.leap)
			cooldown = 0.5, -- was 0.8
			carry = 0.6, -- share of the run's flat speed (up to caps.run) kept in the leap
			air = { accel = 55, max = 40 }, -- air steer: studs/s^2, and the flat speed it may build up to
			bounce = { up = 70, out = 50, max = 3, reach = 6, keep = 0.8 }, -- Leap near a wall in the air
			pound = { speed = 160, radius = 12, coeff = 0.8, cooldown = 3, minFall = 15 }, -- Down in the air
			swim = 36,
			up = { poundLevel = 10, poundRadius = 18 },
			-- the Hulk wall climb (nate's playtest 2026-11-19 20:42Z: "he'd grab a piece of the building and do a large
			-- vertical jump and grab onto the next piece and so on"; Shared.ClimbMath): a leap, fall or jump into a
			-- wall grabs it (fingers dig in: a crack and dust where the hands bite, the building takes a `bite`
			-- chip through the server's MoveGrab), Leap bounds `bound` studs straight up the face to the next grab
			-- (holding Leap bounds again after `grip` s), and over the top a vault onto the roof (`vault`); Leap with
			-- the stick pulled away from the wall kicks off (`kick`, momentum out and up); Down lets go. Sideways
			-- stick drifts the bound along the face (`side`).
			climb = {
				bound = 30, -- studs a bound rises
				gravity = 120, -- the bound's own fall (airGravity)
				grip = 0.14, -- seconds a grab holds before a held Leap bounds again
				reach = 3.5, -- studs to a wall that counts as grabbable
				press = 3, -- studs/s the hands push into the face (keeps the body on it)
				side = 14, -- studs/s sideways drift along the face while bounding
				vault = { up = 36, forward = 24, time = 0.42 },
				kick = { up = 52, out = 58 },
				bite = { dmg = 120, radius = 3, every = 0.25 },
			},
			-- the smash rule (nate on the card, 2026-11-19 20:45Z: "boost (or a fast leap) smashes through
			-- buildings"): mid-leap moving into a wall at `into` studs/s or more (flat, into the face) goes straight
			-- through it like a flight ram (Config.Combat.impact.ram); slower (a tapped leap, near the top, a jump
			-- from beside the wall) grabs it and climbs. A full charged leap runs ~82 flat, a tapped one ~60.
			smash = { into = 68 },
			ranks = {
				{
					name = "Spring Heels",
					text = "Leaps 90 -> 100 high, 225 far",
					set = { { "mobility.leap.apex", 100 }, { "mobility.leap.range", 225 } },
				},
				{
					name = "Hair Trigger",
					text = "Shorter crouch, quicker climb grabs",
					set = {
						{ "mobility.leap.charge", 0.18 },
						{ "mobility.leap.cooldown", 0.35 },
						{ "mobility.leap.climb.grip", 0.08 },
					},
				},
				{
					name = "Ricochet",
					choice = { "impactLanding", "wallCrusher" }, -- the rank's move: pick one (Config.Move.moves)
					text = "4 wall bounces, and higher ones",
					set = {
						{ "mobility.leap.bounce.max", 4 },
						{ "mobility.leap.bounce.up", 80 },
						{ "mobility.leap.bounce.out", 56 },
					},
				},
				{
					name = "Skybound",
					text = "Leaps 115 high, climb bounds 38 high",
					set = {
						{ "mobility.leap.apex", 115 },
						{ "mobility.leap.range", 260 },
						{ "mobility.leap.climb.bound", 38 },
					},
				},
				{
					name = "Meteor",
					choice = { "meteorStrike", "moonJump" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Leaps 130 high, 300 far, a wider pound",
					set = {
						{ "mobility.leap.apex", 130 },
						{ "mobility.leap.range", 300 },
						{ "mobility.leap.pound.radius", 15 },
						{ "mobility.leap.up.poundRadius", 22 },
					},
				},
			},
		},
		acrobat = {
			name = "Acrobat",
			-- the agility pick (nate's playtest 2026-11-19 20:42Z: "whats the point of the player picking acrobat? it
			-- just seems so much worse than everything else"; "should we add wall crawling?"): crawl on any wall or
			-- ceiling, flips that dodge attacks, the best air control and the fastest climb, on top of the double and
			-- triple jump, the glide and the wall runs
			text = "Crawl on walls and ceilings, flip past hits",
			jump = 55, -- each air jump's upward speed
			jumpForward = 35,
			jumps = 1, -- extra jumps in the air (2 from level 10)
			-- wall crawl (Shared.ClimbMath.crawl*): walk, jump or fall into any wall, or rise into a ceiling, and the
			-- hero sticks to it; the stick crawls over the face (up is up on a wall, the camera's forward on a
			-- ceiling), round outside corners and into inside ones, and onto a roof at the top; Boost scurries at
			-- `crawlBurst` on stamina; Leap jumps off (an air jump back); Down lets go. `climb` is the crawl speed
			-- (the fastest climb of any pick: Leap's bounds average ~30 up, Super-speed's wall run needs stamina)
			climb = 40,
			crawlBurst = 66,
			crawlDrain = 10, -- stamina per second while scurrying
			crawlReach = 3.4, -- studs to a face that keeps the hero on it
			crawlGap = 1.6, -- studs the body sits off the face
			ceilingReach = 3, -- rising this close under a ceiling grabs it
			-- the best air control of any pick: the stick builds up to air.max flat at air.accel (Leaping: 55 / 40)
			air = { accel = 95, max = 46 },
			-- flips that dodge (Down: Ctrl, B, the FLIP button): a quick flip along the stick (back when it is
			-- still) on the ground or in the air; for `iframes` s attacks miss (the server's own clock, MoveFlip:
			-- HeroService.damage). Every `cooldown` s.
			flip = { speed = 58, up = 20, time = 0.32, iframes = 0.3, cooldown = 1.1, word = "DODGE!" },
			-- wall runs (nate's playtest 2026-11-19: "jump onto building and keep wall running"): jump at a wall
			-- glancingly and the hero runs along it at the speed it came in with (wallRun to cap); the run lasts while
			-- the stick is held, up to wallRunTime, sinking `sink` studs/s; Leap kicks off keeping the speed along
			-- the wall (and gives an air jump back), so walls chain (wall.regrab). Head-on, it crawls instead.
			wallRun = 45, -- studs/s along a wall (at least)
			wallRunTime = 4, -- was a fixed 1.6 s
			wallRunMin = 12, -- flat speed needed to start a run along a wall
			sink = 2,
			glideForward = 70, -- a faster glide than everyone's
			run = 24,
			cap = 75,
			swim = 45,
			up = { jumpsLevel = 10, jumps = 2 }, -- level 10: 2 air jumps (rank 5: 3)
			ranks = {
				{
					name = "Spider Grip",
					text = "Crawl 40 -> 48 studs/s, longer wall runs",
					set = { { "mobility.acrobat.climb", 48 }, { "mobility.acrobat.wallRunTime", 5 } },
				},
				{
					name = "Spring Step",
					text = "Higher, longer air jumps",
					set = { { "mobility.acrobat.jump", 62 }, { "mobility.acrobat.jumpForward", 40 } },
				},
				{
					name = "Evasion",
					choice = { "kickChain", "ceilingDrop" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Flips dodge longer, every 0.8 s",
					set = {
						{ "mobility.acrobat.flip.iframes", 0.4 },
						{ "mobility.acrobat.flip.cooldown", 0.8 },
					},
				},
				{
					name = "Freerunner",
					text = "Wall runs 54, glide 82, scurry 74",
					set = {
						{ "mobility.acrobat.wallRun", 54 },
						{ "mobility.acrobat.wallRunTime", 6 },
						{ "mobility.acrobat.sink", 1 },
						{ "mobility.acrobat.glideForward", 82 },
						{ "mobility.acrobat.crawlBurst", 74 },
						{ "mobility.acrobat.cap", 88 },
					},
				},
				{
					name = "Triple Jump",
					choice = { "shadowFlip", "slingshot" }, -- the rank's move: pick one (Config.Move.moves)
					text = "A third jump in the air, quicker flips",
					set = {
						{ "mobility.acrobat.up.jumps", 3 },
						{ "mobility.acrobat.jump", 66 },
						{ "mobility.acrobat.flip.cooldown", 0.6 },
					},
				},
			},
		},
		swing = {
			name = "Swing",
			text = "Swing on lines from the buildings and zip to rooftops",
			-- Spider-Man swinging (nate's playtest 2026-11-19: "Swinging should feel like Spider-Man"; Shared.SwingMath):
			-- hold Fly in the air to shoot a line at a real building face or roof corner ahead and above (the camera's
			-- look, then its travel; never the sky), swing through the arc on the swing's own `gravity`, let go to
			-- fling forward and up (a release on the rising half is the sweet one), hold Fly again to catch the next
			-- line; Leap while swinging zips up the line and pops over the top (the point launch); Fly on the ground
			-- zips to the spot aimed at. Every speed stays inside `cap` (the server's Swing cap)
			range = 170, -- a line reaches this far
			maxSpeed = 105, -- the swing's top speed (was 95)
			gravity = 150, -- studs/s^2 on the rope: a snappier arc than the leap's floaty airGravity
			pump = 30, -- studs/s^2 of push along the swing (the stick forward)
			steer = 40, -- studs/s^2 of sideways air control (the stick across the swing)
			reel = 40, -- studs/s the rope shortens toward its target (off the street)
			taut = 0.97, -- share of the gap the rope starts at (taut at once)
			plane = 0.25, -- share of the anchor's sideways offset the swing keeps (SwingMath.pivot: it swings along the travel)
			catchSlack = 1, -- a line slacker than this coming in catches (the fall's speed kept along the swing)
			catchKeep = 0.8, -- share of that fall kept on along the swing
			topGap = 2, -- swung up within this of the anchor's height: lets go on its own
			rearm = 0.15, -- holding Fly after a release fires the next line this long after it starts to fall
			zip = 120, -- a zip to a ledge or up the line: never faster than this at any point
			zipArc = { most = 12, share = 0.08, pace = 1, minTime = 0.2 },
			zipPop = { up = 40, forward = 30 }, -- the point launch at a zip's end
			-- the anchor search: rays at each `lifts` aim (look plus this much up) and each `aim.yaws` turn; scores
			-- favour a point ahead (minAlong at least), about `aim.up` above and `aim.ahead` out
			lifts = { 0.45, 0.9, 1.6 },
			aim = {
				yaws = { 0, 22, -22, 45, -45 },
				minAlong = 0.55,
				near = 18, -- nearer than this is no swing
				up = 45,
				ahead = 60,
				wAlong = 2,
				wUp = 1,
				wAhead = 0.6,
				wTravel = 0.5,
				travelAt = 20, -- moving faster than this also searches along the travel
				travelApart = 30, -- when it is this many degrees off the camera's look
				travelCost = 0.3,
			},
			-- a hit on a wall snaps up to the roof edge (or corner) within `probe` above it
			edge = { probe = 30, steps = 4, out = 1.5, below = 0.5 },
			-- swing anywhere (nate's playtest 2026-11-19 20:42Z: "if you aren't in the city its pretty useless"):
			-- when the main fan finds nothing, a wider, lower fan (`wide`) catches trees, poles, rocks, cliffs and big
			-- props nearer by; with nothing at all in reach a shorter, weaker `sky` line hangs from the air ahead and
			-- above (only when the way up to it is open), so a line always fires. The city's buildings stay best:
			-- the sky line's swing tops out at sky.maxSpeed and pumps at sky.pump.
			wide = {
				lifts = { 0.15, 0.3, 0.6 },
				yaws = { 0, 30, -30, 60, -60, 90, -90 },
				near = 10,
				minAbove = 3,
			},
			sky = { up = 34, ahead = 40, maxSpeed = 78, pump = 18, release = 92, minClear = 6 },
			minAbove = 4,
			minLen = 12,
			clearance = 6,
			groundPop = 25,
			-- letting go: speed x boost (early x early) plus up (earlyUp) and `forward` along the travel; sweet: the
			-- phase (SwingMath.phase) window of the rising half; at most cap
			release = {
				up = 18,
				boost = 1.12,
				early = 1,
				earlyUp = 6,
				forward = 8,
				sweet = { 0.25, 1 },
				cap = 115,
			},
			-- the feel on this device (scaled by Camera motion; wind lines by quality): FOV widens by `fov` and the
			-- camera pulls back `pull` studs at top speed; wind lines past `lines` of maxSpeed; the line shoots out
			-- in `shoot` s; the whoosh on a release faster than `whoosh`
			feel = {
				fov = 0.14,
				pull = 6,
				lines = 0.45,
				shoot = 0.09,
				whoosh = 45,
				width = 0.16,
				-- the line's texture (list-combat 2026-11-20, Everything Left 393: art/fx/swing_line.py, an energy cord
				-- of two twisting strands, white so the travel style tints it); 0 keeps the plain beam. With it the
				-- line is drawn texWidth wide (the strands need the room), one tile every texLength studs
				texture = 81973620355174,
				texWidth = 0.3,
				texLength = 3,
				others = { low = 3, medium = 6, high = 8 }, -- other heroes' lines drawn at once, by quality preset
				othersRange = 350,
			},
			cap = 120,
			swim = 45,
			up = { rangeLevel = 10, range = 220 },
			ranks = {
				{
					name = "Long Line",
					text = "Lines reach 25 studs farther",
					set = { { "mobility.swing.range", 195 }, { "mobility.swing.up.range", 245 } },
				},
				{
					name = "Strong Arms",
					text = "Pump harder, reel in faster",
					set = { { "mobility.swing.pump", 40 }, { "mobility.swing.reel", 52 } },
				},
				{
					name = "Momentum",
					choice = { "doubleZip", "yank" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Swing 105 -> 114 studs/s",
					set = {
						{ "mobility.swing.maxSpeed", 114 },
						{ "mobility.swing.release.cap", 124 },
						{ "mobility.swing.cap", 130 },
					},
				},
				{
					name = "Zipline",
					text = "Faster zips and a bigger pop",
					set = {
						{ "mobility.swing.zip", 135 },
						{ "mobility.swing.zipPop.up", 48 },
						{ "mobility.swing.cap", 138 },
					},
				},
				{
					name = "Skyline",
					choice = { "wreckingKick", "skyHook" }, -- the rank's move: pick one (Config.Move.moves)
					text = "Swing 124 studs/s, lines reach 270",
					set = {
						{ "mobility.swing.maxSpeed", 124 },
						{ "mobility.swing.release.cap", 134 },
						{ "mobility.swing.range", 215 },
						{ "mobility.swing.up.range", 270 },
						{ "mobility.swing.cap", 145 },
					},
				},
			},
		},
	},
	swim = { base = 24, surface = 2 },
	-- Omnidirectional movement (nate's playtest 2026-11-19: "Add omnidirectional movement. Don't forget about during
	-- flying too"). The hero moves relative to the camera in any direction: in flight the velocity eases straight to
	-- the stick's 3D direction at `flightAccel` (strafe, backpedal, up and down along the camera's pitch) instead of
	-- turning round to it; only a boost along the look keeps the swooping turn. The body faces the camera's look
	-- (or the lock target) while hovering and strafing, and the move once it is fast forward; it leans into the move
	-- (`lean`, degrees at cruise). Gliding drifts toward the stick at `glideAccel`. Underwater the camera's pitch
	-- swims up and down too (`swimVertical` of the swim speed, so the 3D speed stays inside the server's cap), Leap
	-- rises, Down sinks. On the ground a lock turns the body to the target, so strafing and backpedalling circle it.
	omni = {
		flightAccel = 110, -- studs/s^2 toward the stick's velocity (cruise 60: a full reverse in about a second)
		swoop = 0.8, -- a boost this close to the camera's look (dot) keeps the swooping turn (flight.turnRate)
		face = 10, -- per second the body turns toward where it faces
		faceMoveAt = 0.75, -- share of cruise speed forward past which a free flier faces its travel
		lean = { forward = 28, side = 22, back = 18 },
		glideAccel = 45, -- studs/s^2 a glide's drift moves toward the stick
		swimVertical = 0.7,
		groundTurn = 12, -- per second a locked hero on the ground turns to face the target
	},
	-- wall grabs in the air (Acrobat and Super-speed): a wall hit within grabAngle degrees of head-on is run or
	-- climbed up, a more glancing one is run along; `regrab` s after leaving a wall the hero may grab one again
	-- (a wall run that timed out is not grabbed again before the hero lands or kicks off with Leap)
	wall = { grabAngle = 40, regrab = 0.25 }, -- everyone swims; surface: studs below the waterline the hero floats at
}
