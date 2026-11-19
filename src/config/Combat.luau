-- Hit resolution (spec: Movement and combat rules > Hit resolution). (tune)
return {
	useRate = 12, -- Combat.Use per second
	cooldownLeeway = 0.1,
	rewindMax = 0.15, -- seconds the attacker's position is rewound for lag
	historyRate = 30, -- position samples per second, 1 s kept
	historyKeep = 1.0,
	resultRadius = 150, -- Combat.Result goes to players this close
	resultRate = 10, -- batches per second
	aimSlack = 15, -- degrees: the server accepts a target hint this far off the aim line
	reachSlack = 6, -- studs added to every range check for lag
	hitPause = 0.06, -- hit-stop on your hits (was 0.03; nate 2026-11-17: "make hits weighty")
	critPause = 0.11, -- crits and heavy hits (was 0.05)
	-- Weighty hits (nate, 2026-11-17: flash, turn the enemy white, sound, particles, knockback, shake and
	-- freeze). Every non-tick hit you land: the robot flashes white (Config.Fx.hitFlash), freezes in place for
	-- the hit-stop with you, then flinches away from the hit while the server knocks it back a little; a thud
	-- plays (Config.Audio.impact), sparks spray out of the hit and the camera shakes. Heavy (coeff >=
	-- heavyCoeff) and crit hits do all of it bigger. Reduce flashing turns off the shake and freeze.
	weight = {
		knock = 1.5, -- studs the server pushes a robot on a normal hit (not ticks; robots immune to knockback skip it)
		knockHeavy = 4, -- heavy or crit hits
		flinch = 0.18, -- seconds the drawn robot recoils after the freeze
		flinchStuds = 1, -- how far the drawn body jolts back (and springs back) on a normal hit
		flinchHeavy = 2,
		flinchTilt = 14, -- degrees it rocks back (doubled on heavy hits)
		shake = { 0.07, 0.22 }, -- camera shake {time, amount} on a normal hit
		shakeHeavy = { 0.16, 0.55 },
		sparks = 6, -- sparks sprayed out of the hit (heavy: x2), from the device's debris budget
		sparkLife = 0.35,
		thudGap = 0.05, -- at most one thud this often (multi-hits stay clean)
	},
	punchHit = 0.012, -- camera FOV kick on your hits (CameraController.punch; clash uses its own)
	punchHeavy = 0.03,
	-- Hold to aim and charge (overhaul plan step 3; Shared.ChargeRules). A skill or super key shows its aim
	-- while held and casts on release. Damaging skills (not channels, buffs, summons, dashes or supers) also
	-- charge: from `start` to `full` seconds held, up to +damage and +size. The server times the hold itself
	-- (CombatCharge at the press), so a client can claim no more than it held.
	charge = {
		start = 0.25,
		full = 1.2,
		damage = 0.2,
		size = 0.15,
		maxHold = 4,
		leeway = 0.15,
		powerSlow = 0.6,
	},
	-- H2 charge-up powers (spec: Hero MMO features): rows in Config.Abilities with charge = { max, mult, grow }
	-- charge further (1x to 2.2x, up to 1.5x size, a full charge breaks a block) and slow the hero to
	-- powerSlow while charging; an interrupt cancels them (Config.Guard.interrupt)
	numbers = { stackTime = 0.35 }, -- Client: damage numbers on one target merge for this long
	outOfCombat = 5, -- seconds since the last hit or cast: loadouts can change (until safehouses in M4)
	echoDelay = 0.5, -- Aftershock, Shockwave and other echo capstones land this long after
	tauntTime = 2, -- Bruiser hits make the target attack the Bruiser this long
	heavyCoeff = 2.5, -- hits this heavy shake the camera and count as heavy (spec: Clash moments)
	maxFields = 40, -- fields alive on the server at once
	wallLife = 5,
	parryRiposteRadius = 12,
	-- Collision freeze (spec: Clash moments): two heroes' heavy hits land this close within `window`
	-- seconds: both freeze, a shockwave rings out, the camera pushes. One per pair per 5 s.
	clash = { window = 0.15, reach = 20, freeze = 0.3, radius = 14, push = 0.08, pairCooldown = 5 },
	-- Momentum and impact (nate's playtest 2026-11-19: "get hit with something and it sends me back into a
	-- building and it destroys the building. Or even just flying at super speed. Momentum and impact should
	-- destroy things"). The server owns every break (ImpactService through BuildingService), scaled by speed and
	-- capped; pins (beacon hosts, side quest roofs, the prologue's held row), safe areas, story scenes,
	-- safehouses and landmarks never break.
	-- Knockback by move (nate's playtest 2026-11-19: "A lot of moves should have strong knock back. That is to send
	-- enemies flying through buildings. Determine knock back based on move"). Every damaging ability and weapon move
	-- has a kind (Shared.KnockRules.kind: a row's own `knockKind`, else by slot, shape and coeff) and each kind a
	-- throw: `dist` studs along the ground, an arc `lift` studs high, flown at `speed` studs/s (0: an instant shove,
	-- no flight). A launched robot that meets a building breaks through it (ImpactService, the robot curves in
	-- impact.robot, inside the per-hero and server caps) and flies on with `through.keep` of the rest, at most
	-- `through.max` studs inside; a wall that holds stops it with a `wallStun` stagger. World bosses never move (their
	-- parts are fixed targets); mini-bosses take `miniBoss` of it; robots immune to knockback none. In PvP only the
	-- `pvpKinds` throw players, at Config.Pvp.knock.scale of the distance and never past its maxDistance. (tune)
	knock = {
		kinds = {
			field = { dist = 0, lift = 0, speed = 0 }, -- fields and channels tick: they hold robots, never shove
			jab = { dist = 2.5, lift = 0, speed = 0 }, -- basics and combo hits: a small shove
			strike = { dist = 10, lift = 3, speed = 45 }, -- most skills
			heavy = { dist = 28, lift = 8, speed = 65 }, -- smashes, slams, big hitters
			charged = { dist = 46, lift = 12, speed = 80 }, -- a fully charged skill (lerped by the charge level)
			super = { dist = 64, lift = 16, speed = 90 }, -- supers and team-up combos
			swing = { dist = 32, lift = 7, speed = 70 }, -- a robot swung as a weapon (Config.Throw.swing)
			thrown = { dist = 50, lift = 10, speed = 80 }, -- the swung robot itself when it is thrown
		},
		order = { "field", "jab", "strike", "heavy", "charged", "super", "swing", "thrown" },
		heavyCoeff = 1.8, -- a skill this heavy is a smash
		slamShapes = { nova = true, leap = true }, -- slams and landings: heavy from slamCoeff
		slamCoeff = 1.2,
		lastHit = 2.5, -- a combo's last hit (the finisher) shoves this many times a jab
		crit = 1.25, -- a crit throws further
		miniBoss = 0.1, -- mini-bosses barely move (world bosses not at all)
		pvpKinds = { heavy = true, charged = true, super = true, swing = true, thrown = true },
		through = { max = 40, keep = 0.6 }, -- studs a robot may fly inside a broken building; share of the rest kept
		wallStun = 0.8, -- seconds a robot that hits a wall that holds is dazed
		gravity = 120, -- studs/s^2 a launched robot falls at once its arc ends above the ground
	},
	-- Lock-on (nate's playtest 2026-11-19, "a player/enemy lock-on ... camera should have dynamic movement"; nate
	-- decided BOTH, 13:17Z): the soft lock (Settings softLock, on by default) eases your casts and the camera
	-- toward the best target in front within `soft.range`; the hard lock (Settings hardLock; middle mouse or Tab on
	-- PC, R3 on a gamepad, the LOCK button on touch) keeps one target framed with the dynamic camera. Targets: drawn
	-- robots, the world boss, and flagged players only when PvP allows the hit. Rules in Shared.LockRules. (tune)
	lock = {
		soft = {
			range = 60, -- studs from the hero
			angle = 24, -- degrees off the aim the soft lock still takes
			camTurn = 0.9, -- per second the camera eases its yaw toward the soft target (times Camera motion)
			camIdle = 0.6, -- seconds after you last turned the camera before it eases
			camDead = 6, -- degrees: no easing when the target is this close to the centre
		},
		hard = {
			range = 120, -- studs: a new lock finds targets this far
			angle = 60, -- degrees off the camera's look
			keep = 170, -- studs: a lock drops past this
			lost = 1.5, -- seconds a target may be hidden before the lock drops
			turn = 7, -- per second the camera turns to frame it
			pitch = { -55, 30 }, -- degrees the lock may tilt the camera (down, up)
			lean = 5, -- degrees the camera rolls with your sideways motion (times Camera motion)
			sway = 1.5, -- studs the camera swings out the side you move to
			big = 14, -- studs: a target taller than this (a boss) pulls the camera back
			pull = 0.9, -- studs back per stud over `big`
			pullMax = 40,
			shoulder = 2.5, -- studs the camera sits to the side so the hero never covers the target
			heroAim = 0.35, -- 0 frames the target, 1 the hero: the look point between them
			cycleAngle = 120, -- degrees either side Tab and the stick flick search for the next target
			flick = 0.7, -- the right stick pushed this far sideways while locked cycles targets
			flickGap = 0.35, -- seconds between flick cycles
		},
		padHold = 0.35, -- R3 held this long fires the Gadget instead (a tap toggles the lock)
		-- the comic target marker (LockClient): corner brackets round the target and a diamond over it
		marker = {
			size = 64, -- pixels at 30 studs (scaled by distance, clamped)
			min = 40,
			max = 120,
			soft = { 255, 255, 255 }, -- the soft lock's thin white brackets
			hard = { 255, 70, 60 }, -- the hard lock's red brackets and diamond
			ink = { 20, 20, 28 },
			spin = 90, -- degrees a second the hard lock's brackets turn
			pulse = 0.12, -- share the brackets breathe in and out
		},
	},
	-- A hero dropping onto a building from high up smashes it (nate, 2026-11-19 13:18Z): a landing on a roof at
	-- `minFall` studs/s or more (a long fall, a dive) breaks the roof and the storey under it, scaled from minFall to
	-- fullFall; the server checks the claim against its own recent speed (MoveGuard.peakSpeed, slack) and the
	-- hero's spot (near + lag), inside the impact caps (perHero, serverPerSecond). Robots round the landing are hit
	-- (coeff, radius) and thrown as a heavy. The device plays the landing crack, dust and shake.
	drop = {
		minFall = 90,
		fullFall = 200,
		dmg = { 1200, 3600 }, -- structure damage from minFall to fullFall
		radius = { 8, 14 }, -- studs of roof round the landing
		coeff = 1.2, -- the hit on robots round it (times the hero's basic damage)
		near = 18,
		lag = 0.25,
		slack = 1.25,
		window = 1.0,
	},
	impact = {
		-- ram: a hero moving this fast (flight boost, a Super-speed running jump, a dash, a Leaping pound, a
		-- travel ride) into a wall smashes through it. The device sees the wall first (ImpactFx), the server
		-- checks the hero's own recent top speed (MoveGuard.peakSpeed) and where it is, then knocks pieces out.
		ram = {
			-- fix-destroy (2026-11-19, nate: "I want to fly straight through buildings"): plain flight (cruise 60) now
			-- smashes through (was 85+, boost only), each ram opens a hero-sized hole at once (4 to 10 pieces at 400 a
			-- piece; was 1 to 5) and keeps 90% of the speed (was 70%), so a hero flies through a block wall after wall
			minSpeed = 45, -- studs/s: below this a wall stops you as before (flight cruise is 60, boost 110)
			fullSpeed = 140, -- at this speed a ram does its most
			dmg = { 1600, 4000 }, -- structure damage from minSpeed to fullSpeed
			radius = 10, -- studs round the contact the pieces come from (a hero-sized hole and its edges)
			reach = 4, -- studs the device looks ahead of the body each frame
			facing = 0.35, -- how square the wall must be to the travel (dot of the travel and the wall)
			loss = 0.1, -- share of the speed lost going through (was 0.3)
			hitStop = 0.05, -- seconds the hero holds at the wall (the hit-stop; was 0.08)
			holdKeep = 0.25, -- share of the speed kept during the hold (was 0.08)
			shake = { 0.22, 0.6 }, -- camera shake {time, amount}
			cooldown = 0.12, -- seconds between rams on the device (was 0.3: the far wall comes fast)
			sameWall = 0.25, -- seconds before the same building counts as a new ram (its far wall; was 0.6)
			slack = 1.25, -- the claimed speed may be at most this much over the server's recent top speed
			window = 0.6, -- seconds of history the server's top speed looks over
			near = 16, -- studs: the contact must be this close to where the server has the hero (plus lag)
			lag = 0.25, -- seconds of travel added to `near` for lag
			perHero = 12, -- breaks a hero may cause per `heroWindow` seconds (rams and knocks; was 6)
			heroWindow = 4,
		},
		-- knock: a heavy robot punch, a boss strike or a PvP knockback throws the hero back; a wall in the way
		-- breaks if the throw is fast enough and the hero flies on through what is left
		knock = {
			minShare = 0.12, -- a robot melee hit must take this share of the hero's max health to throw it
			fullShare = 0.35,
			dist = { 14, 40 }, -- studs thrown from minShare to fullShare
			boss = 36, -- a boss strike throws this far
			time = 0.45, -- seconds the throw takes
			lift = 6, -- the arc's height
			wallSpeed = 30, -- studs/s a throw needs to break a wall
			fullSpeed = 90,
			dmg = { 900, 2400 }, -- structure damage from wallSpeed to fullSpeed
			through = 0.6, -- share of the rest of the throw kept after going through a wall
			stopShort = 2, -- studs short of a wall that held (pinned or too slow)
		},
		-- robots knocked into a wall (EnemySim.knock says it hit one) break it too
		robot = { minKnock = 8, dmg = { 600, 1800 }, fullKnock = 30, reach = 4 },
		pound = 1800, -- a Leaping ground pound's structure damage where it lands (it broke nothing before)
		serverPerSecond = 20, -- impact breaks a second on the whole server, on top of the per-hero cap (was 12)
	},
}
