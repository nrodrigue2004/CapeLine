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
	charge = { start = 0.25, full = 1.2, damage = 0.2, size = 0.15, maxHold = 4, leeway = 0.15 },
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
