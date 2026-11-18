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
	-- the Ceremony prologue's screen (onboarding check 2026-11-18; StoryClient and StoryHud read these)
	prologue = {
		-- the verb button(s) each beat shows and pulses (Hud.setFocus); the camera beats show none
		verbs = {
			ceremony = {},
			scan = {},
			run = { "Leap" },
			spark = { "Basic" }, -- the Spark fires from the attack button
			leap = { "Leap" },
			chase = { "Leap" }, -- the Leap button reads GLIDE in the air
			suit = { "Leap" },
			descend = { "Leap" },
			tunnel = { "Leap" },
			fight = { "Basic", "Skill1", "Skill2", "Leap" },
			swarm = { "Basic", "Skill1", "Skill2", "Leap" },
			rescue = {},
			title = {},
		},
		-- one fixed word under the gold marker on a beat that has a place to reach, so the goal reads at once
		-- (the lines can come later or not at all for a quick player); the camera beats have no marker
		goals = {
			run = "RUN",
			spark = "SPARK",
			leap = "LEAP",
			chase = "LEAP",
			descend = "SUBWAY",
			tunnel = "RUN",
		},
		-- kid-proof (nate's playtest 2026-11-18): one short instruction on screen for every beat the hero plays,
		-- big and always there until the beat is done; {Action} is that action's key or button on this device
		hints = {
			run = "Run to the gold marker!",
			spark = {
				hero = "The kid is in danger! Press {Basic} to save them!",
				villain = "That guy shoved you! Press {Basic} to fight back!",
			},
			leap = "Press {Leap} to jump to the next roof!",
			chase = "Press {Leap} to jump! Keep going roof to roof!",
			descend = "Press {Leap} to jump down to the subway!",
			tunnel = "RUN! The tunnel is falling down!",
			fight = "Fight Skylance! Press {Basic} to attack!",
			swarm = "Keep fighting! Help is coming!",
		},
		-- a player-paced beat that ends before its lines are heard hands at most `carry` of them to the next
		-- player-paced beat (a line is heard once it showed `heard` of its reading time); none into a camera beat
		carry = 2,
		heard = 0.7,
	},
	-- the cards the server pops by itself (daily claim, mentor picker, TOP 10): Ui.PopupGate holds each until the
	-- player is free (no loading screen, menu, creator, prologue, cutscene or other such card)
	popups = { settle = 1.2, giveUp = 600 }, -- seconds of calm before one shows; the longest it waits
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
