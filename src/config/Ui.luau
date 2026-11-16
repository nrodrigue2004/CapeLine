-- UI kit numbers (spec: Screens and UI). Phone first: 48 px tap targets, 16 px safe area, nothing important
-- in the bottom 80 px right (the flight pad).
return {
	touchTarget = 56, -- at least 48 px
	safe = 16,
	corner = 10,
	textScale = { min = 1.0, max = 1.6 },
	colors = {
		ink = { 22, 24, 32 },
		paper = { 244, 242, 236 },
		night = { 18, 22, 34 },
		gold = { 255, 200, 60 },
		volt = { 120, 210, 255 },
		health = { 90, 220, 120 },
		healthLow = { 240, 80, 70 },
		stamina = { 255, 210, 90 },
		cooldown = { 0, 0, 0 },
		league = { 70, 150, 255 },
		syndicate = { 235, 70, 70 },
		muted = { 140, 146, 160 },
	},
}
