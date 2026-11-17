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
	hitPause = 0.03,
	critPause = 0.05,
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
}
