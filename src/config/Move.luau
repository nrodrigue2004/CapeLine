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
	ceiling = { soft = 560, hard = 600, push = 60 }, -- spec: cloud layer at 500, ceiling 600
	fall = { terminal = 220 }, -- fastest legal fall (Roblox freefall from the ceiling)
	-- Server caps per style (spec column "Server check"); position checks allow cap x tolerance
	caps = {
		run = 28,
		glide = 60,
		flight = 125,
		cruise = 60, -- flight without boost
		superSpeed = 100,
		superLeap = 115, -- placeholder until M2 adds the style
		grapple = 70,
	},
	tolerance = 1.15,
	-- Touch flight (spec: Touch flight)
	touch = {
		autoAimAngle = 25,
		autoAimRange = 60,
		markerFlySpeed = 75,
		markerClearance = 30,
	},
	-- Which styles are unlocked at which level (spec: Levels). M1 slice unlocks Flight for everyone via Dev.
	styleUnlockLevel = { flight = 3, superSpeed = 8, superLeap = 12, grapple = 16 },
}
