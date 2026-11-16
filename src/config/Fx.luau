-- Juice numbers for the M1 actions (spec: Audio, VFX, juice and accessibility). Client only. (tune)
return {
	fov = { base = 70, leap = 1.06, boost = 1.17, blend = 6 },
	landShake = { time = 0.1, amount = 0.35, minFall = 25 },
	crack = { life = 30, minFall = 30 },
	bolt = { width = 0.35, life = 0.12 },
	chain = { width = 0.5, life = 0.25, segments = 6, jitter = 1.6 },
	dash = { trailLife = 0.3 },
	hitFlash = 0.08,
	numbers = { rise = 3, life = 0.8, critScale = 1.5 },
	enemyDeath = { parts = 6, life = 2 },
	shot = { width = 0.4 },
	trail = { boostLife = 0.4 },
	voltColor = { 120, 210, 255 },
	enemyShotColor = { 255, 110, 80 },
	critColor = { 255, 210, 60 },
	-- Comic style: a sound word on skill and super hits, by set (all original words)
	words = {
		Volt = { "ZAP!", "KRAK!", "BZZT!" },
		Frost = { "CRACK!", "FWOOSH!", "KSSH!" },
		Titan = { "POW!", "WHAM!", "KABOOM!" },
		Pulse = { "WHUMM!", "VWOOM!", "THOOM!" },
		Blade = { "SHING!", "SLASH!", "KSHHK!" },
	},
	warnColor = { 255, 60, 50 }, -- enemy attack telegraphs
	awakenColor = { 255, 235, 120 },
	slashSegments = 9, -- pieces in an arc slash
	fieldPulse = 0.5, -- seconds between field pulses
}
