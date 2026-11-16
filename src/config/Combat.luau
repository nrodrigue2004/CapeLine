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
	numbers = { stackTime = 0.35 }, -- Client: damage numbers on one target merge for this long
	outOfCombat = 5, -- seconds since the last hit or cast: loadouts can change (until safehouses in M4)
	echoDelay = 0.5, -- Aftershock, Shockwave and other echo capstones land this long after
	tauntTime = 2, -- Bruiser hits make the target attack the Bruiser this long
	heavyCoeff = 2.5, -- hits this heavy shake the camera and count as heavy (spec: Clash moments)
	maxFields = 40, -- fields alive on the server at once
	wallLife = 5,
	parryRiposteRadius = 12,
}
