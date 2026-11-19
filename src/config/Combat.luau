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
	impact = {
		-- ram: a hero moving this fast (flight boost, a Super-speed running jump, a dash, a Leaping pound, a
		-- travel ride) into a wall smashes through it. The device sees the wall first (ImpactFx), the server
		-- checks the hero's own recent top speed (MoveGuard.peakSpeed) and where it is, then knocks pieces out.
		ram = {
			minSpeed = 85, -- studs/s: below this a wall stops you as before (flight cruise is 60, boost 110)
			fullSpeed = 160, -- at this speed a ram does its most
			dmg = { 900, 3000 }, -- structure damage from minSpeed to fullSpeed (600 a piece: 1 to 5 pieces)
			radius = 9, -- studs round the contact the pieces come from (a hero-sized hole and its edges)
			reach = 4, -- studs the device looks ahead of the body each frame
			facing = 0.35, -- how square the wall must be to the travel (dot of the travel and the wall)
			loss = 0.3, -- share of the speed lost going through
			hitStop = 0.08, -- seconds the hero holds at the wall (the hit-stop)
			holdKeep = 0.08, -- share of the speed kept during the hold
			shake = { 0.22, 0.6 }, -- camera shake {time, amount}
			cooldown = 0.3, -- seconds between rams on the device
			sameWall = 0.6, -- seconds before the same building counts as a new ram (a wall that held)
			slack = 1.25, -- the claimed speed may be at most this much over the server's recent top speed
			window = 0.6, -- seconds of history the server's top speed looks over
			near = 16, -- studs: the contact must be this close to where the server has the hero (plus lag)
			lag = 0.25, -- seconds of travel added to `near` for lag
			perHero = 6, -- breaks a hero may cause per `heroWindow` seconds (rams and knocks)
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
		serverPerSecond = 12, -- impact breaks a second on the whole server, on top of the per-hero cap
	},
}
