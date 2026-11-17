-- Movement kit (spec: Movement and combat rules > Movement kit). Studs and seconds. (tune)
-- Air moves use their own gravity (airGravity) so leaps feel floaty and comic-book, and so the client feel
-- and the server checks share one set of numbers.
return {
	run = { speed = 20, groundMax = 28 },
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
	stamina = {
		max = 100,
		boostDrain = 14,
		regenGround = 15,
		regenAir = 8, -- gliding or cruising
		boostMin = 10, -- boost needs this much to start
	},
	-- spec: cloud layer at 500, ceiling 600; raised 2026-11-17 for the skyscrapers (nate: "taller buildings"):
	-- the Uptown landmark's spire tops out at 820, so the clouds sit at 880 and the ceiling at 960
	ceiling = { soft = 920, hard = 960, push = 60 },
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
	mobility = {
		flight = {
			name = "Flight",
			text = "Fly anywhere: cruise, boost, hover and dive",
			swim = 50,
			up = { boostLevel = 10, boost = 120 }, -- level 10: faster boost (inside the 125 flight cap)
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
			slide = 1.0, -- seconds of slide (Down while sprinting): shots pass over
			cap = 100,
			swim = 60,
			up = { trailLevel = 12, trailSpeed = 70, trailRadius = 7, trailCoeff = 0.25 }, -- level 12: the trail hurts robots
		},
		leap = {
			name = "Leaping",
			text = "Huge charged leaps, wall bounces and a ground pound",
			apex = 90,
			range = 200,
			charge = 0.4,
			cooldown = 0.8,
			bounce = { up = 60, out = 45, max = 3, reach = 5 }, -- Leap near a wall in the air
			pound = { speed = 160, radius = 12, coeff = 0.8, cooldown = 3, minFall = 25 }, -- Down in the air
			swim = 36,
			up = { poundLevel = 10, poundRadius = 18 },
		},
		acrobat = {
			name = "Acrobat",
			text = "Double jump, climb any wall, wall run and glide",
			jump = 55, -- each air jump's upward speed
			jumpForward = 35,
			jumps = 1, -- extra jumps in the air (2 from level 10)
			climb = 26, -- studs/s up a wall (hold forward into it)
			wallRun = 45, -- studs/s along a wall
			wallRunTime = 1.6,
			glideForward = 70, -- a faster glide than everyone's
			run = 24,
			cap = 75,
			swim = 45,
			up = { jumpsLevel = 10 },
		},
		swing = {
			name = "Swing",
			text = "Swing on lines from the buildings and zip to rooftops",
			range = 170, -- a line reaches this far
			maxSpeed = 95,
			pump = 22, -- studs/s^2 of push along the swing
			zip = 120, -- a zip to a ledge (tap Fly on the ground)
			cap = 120,
			swim = 45,
			up = { rangeLevel = 10, range = 220 },
		},
	},
	swim = { base = 24, surface = 2 }, -- everyone swims; surface: studs below the waterline the hero floats at
}
