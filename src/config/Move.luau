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
			-- the running jump (nate's playtest 2026-11-18: "holding the jump without losing speed"): Leap while
			-- running faster than `from` is an instant hop that keeps the run's speed (no crouch, no slowdown),
			-- steers at turnRate in the air, and holding Leap hops again on every landing
			hop = { from = 30, up = 45, turnRate = 160, glideBelow = -60 },
			-- wall runs (nate's playtest 2026-11-19: "jump onto building and keep wall running"): a hop or fall into a
			-- wall at waterRun or more runs up it (wallRun) like the ground run does; a glancing one at hop.from or more
			-- runs along it at the run's speed; either keeps going while Boost or Leap is held and stamina lasts
			cap = 100,
			swim = 60,
			up = { trailLevel = 12, trailSpeed = 70, trailRadius = 7, trailCoeff = 0.25 }, -- level 12: the trail hurts robots
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
		},
		acrobat = {
			name = "Acrobat",
			text = "Double jump, climb any wall, wall run and glide",
			jump = 55, -- each air jump's upward speed
			jumpForward = 35,
			jumps = 1, -- extra jumps in the air (2 from level 10)
			climb = 26, -- studs/s up a wall (hold forward into it)
			-- wall runs (nate's playtest 2026-11-19: "jump onto building and keep wall running"): jump at a wall and
			-- the hero grabs it: within wall.grabAngle of head-on (stick into it) climbs, more glancing runs along it at
			-- the speed it came in with (wallRun to cap); the run lasts while the stick is held, up to wallRunTime,
			-- sinking `sink` studs/s; Leap kicks off keeping the speed along the wall (and gives an air jump back),
			-- so walls chain (wall.regrab)
			wallRun = 45, -- studs/s along a wall (at least)
			wallRunTime = 4, -- was a fixed 1.6 s
			wallRunMin = 12, -- flat speed needed to start a run along a wall
			sink = 2,
			glideForward = 70, -- a faster glide than everyone's
			run = 24,
			cap = 75,
			swim = 45,
			up = { jumpsLevel = 10 },
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
				others = { low = 3, medium = 6, high = 8 }, -- other heroes' lines drawn at once, by quality preset
				othersRange = 350,
			},
			cap = 120,
			swim = 45,
			up = { rangeLevel = 10, range = 220 },
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
