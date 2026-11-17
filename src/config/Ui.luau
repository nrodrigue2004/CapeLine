-- UI kit numbers (spec: Screens and UI). Phone first: 48 px tap targets, 16 px safe area, nothing important
-- in the bottom 80 px right (the flight pad).
return {
	touchTarget = 56, -- at least 48 px
	safe = 16,
	corner = 10,
	textScale = { min = 1.0, max = 1.6 },
	-- overhaul plan step 8, the phone pass (Shared.TouchLayout): the HUD sizes itself to the screen
	phone = {
		compactBelow = 500, -- a screen whose short side is under this many pixels is a phone (compact HUD)
		row = 46, -- the top row of screen buttons (POWERS, GEAR, MAP...), its height
		rowCompact = 40, -- the same on a phone
		gap = 8,
		glyph = 0.23, -- a top-row label's width per character, as a share of the row height
		padX = 18, -- and its side padding
		clusterWidth = 0.6, -- the action cluster keeps out of the move stick's 40% of the width
		desktopScale = 0.85, -- mouse and gamepad draw the cluster a little smaller (they show key hints)
		minScale = 0.6,
		maxScale = 1.4,
		minPrimary = 44, -- Basic, the skills, Super, Leap, Fly and Boost never draw smaller than this on a phone
		minTap = 40, -- any other button
		minText = 10, -- the smallest text on a phone (pixels, at 100% text size)
		radarCompact = 88, -- the radar on a phone (132 elsewhere)
		statusCompactW = 210, -- the status card's width on a phone (250 elsewhere)
		trackerRow = 52, -- an incident tracker row with its gap
		panelMargin = 8, -- a fitted panel keeps this far from the screen's edge
		minPanelScale = 0.8, -- a fitted panel never shrinks more than this (it scrolls instead)
		drawerW = 150, -- the MORE drawer's width
		-- hold a skill button and drag to aim (the camera turns with the finger)
		aimDrag = { yaw = 0.011, pitch = 0.008, maxPitch = 70 }, -- radians per pixel; degrees
	},
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
		vigil = { 70, 150, 255 }, -- the Vigil (heroes)
		syndicate = { 235, 70, 70 },
		muted = { 140, 146, 160 },
	},
}
