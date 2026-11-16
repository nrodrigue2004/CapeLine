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
}
