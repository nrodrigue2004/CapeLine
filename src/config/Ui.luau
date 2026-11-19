-- UI kit numbers (spec: Screens and UI). Phone first: 48 px tap targets, 16 px safe area, nothing important
-- in the bottom 80 px right (the flight pad).
return {
	touchTarget = 56, -- at least 48 px
	safe = 16,
	-- a press that starts and ends on a kit button counts as a tap even if the engine sends no Activated
	-- (nate's playtest 2026-11-19, "buttons are extremely unreliable"): it may move this many pixels, and
	-- counts this many seconds after the release when no Activated came (Kit.tapGuard)
	tap = { slop = 14, wait = 0.12 },
	corner = 4, -- the comic look (2026-11-18): small square-ish corners; round buttons stay round
	-- the comic ink (nate picked the bold comic mockup, 2026-11-18): Kit gives every drawn panel and button a
	-- thick ink outline and a hard ink drop shadow down-right; paper panels get faint halftone dots
	ink = {
		stroke = 3, -- outline (UIStroke, outside the box)
		thin = 2, -- the outline on a part under minShadow tall (a bar, a chip)
		shadow = 4, -- drop shadow offset, down and right
		minShadow = 22, -- parts shorter than this get no shadow (bars, chips)
		maxRound = 12, -- a corner rounder than this (a circle, a pill) gets its shadow from its owner instead
		showBelow = 0.6, -- the ink shows on a fill at most this transparent, and fades with it
		-- a Folder's GuiObjects lay out inside the owner's UIPadding, so the shadow undoes it (Studio check:
		-- if a padded button's shadow sits inside it, set false)
		padsFolder = true,
		tilt = 1.5, -- degrees: the top row's tabs and the toasts lean alternately
		-- halftone dots over paper panels (art/ui/halftone.py, uploaded 2026-11-18; "" draws none)
		halftone = {
			image = "rbxassetid://89303571654854",
			tile = 14,
			transparency = 0.88,
			darkTransparency = 0.93,
		},
	},
	textScale = { min = 1.0, max = 1.6 },
	-- overhaul plan step 8, the phone pass (Shared.TouchLayout): the HUD sizes itself to the screen
	-- the declutter pass (nate's playtest 2026-11-19: "wayyy too much on screen, especially the bar at the top
	-- with buttons"): the top row keeps the four screens players open most (and LEAVE while visiting); every
	-- other screen button (JOURNAL, SQUAD, EMOTE, PING, PASS, DAILY, BOARDS, SETTINGS ...) sits in the MENU
	-- drawer, a grid under the MENU button. A button with the DockPin attribute joins the row while it is set
	-- (PVP while flagged); a drawer button whose label ends in "!" (DAILY !) makes it "MENU !" in gold.
	dock = {
		row = { VisitLeave = true, Loadout = true, Gear = true, Map = true, Shop = true },
		menu = "MENU",
		columns = 2, -- the drawer's grid
		text = 22, -- every tab's largest lettering (row and drawer alike)
		-- mouse and keyboard: the movement keys show as one key line under the action buttons instead of
		-- round buttons (touch and gamepad keep the buttons; the opening's verb buttons still show)
		keyLine = { "Leap", "Fly", "Boost", "Down" },
	},
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
		drawerW = 150, -- a MENU drawer column's width
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
			-- the rooftop chase is a cinematic with its own prompts (Ui.QteHud: the prompt is the button on a phone)
			leap = {},
			chase = {},
			suit = {},
			descend = {},
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
			leap = "Press the button when it flashes!",
			chase = "Skylance is coming! Press each button as it flashes!",
			descend = "Press the button to drop to the subway!",
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
	-- pt-ui (2026-11-19, nate's playtest: "too many popups on the screen at once"): every transient popup waits in one
	-- line (Shared.PopupQueue, Ui.Popups): at most maxCards big cards and maxToasts toasts at once (phoneToasts on a
	-- phone), by pri; non-urgent cards wait while fighting (a hit given or taken in the last `calm` s) for at most
	-- combatHold s; offers wait offerCalm s of calm; toasts up are cut to `hurry` s while others wait; folded
	-- ones show "+N more" for moreLife s. settle: seconds of calm after a menu or scene before a card shows;
	-- giveUp: the longest Ui.PopupGate's join cards wait for that.
	popups = {
		settle = 1.2,
		giveUp = 600,
		tick = 0.1,
		maxCards = 1,
		maxToasts = 2,
		phoneToasts = 1,
		calm = 4,
		offerCalm = 8,
		combatHold = 30,
		hurry = 2.2,
		moreLife = 3,
		pri = {
			story = 90,
			alert = 80,
			result = 70,
			social = 60,
			news = 50,
			join = 40,
			juice = 35,
			info = 30,
			offer = 20,
			minor = 10,
		},
		-- every big card that pops by itself: its priority and rules. life: the longest it stays up (nil: it waits
		-- for a tap and has a close button: tests "pt-ui" open and close each one); stale: dropped (counted in "+N
		-- more") when it could not show within that many seconds; fightOk: a timed ask that may show in a fight
		cards = {
			bossResult = { pri = "result", life = 8 }, -- WorldHud (closes itself after 5 s or a tap)
			missionResult = { pri = "result", life = 8 }, -- StoryHud: missions and side quest chains (5.5 s)
			pvpResult = { pri = "result", life = 7, fightOk = true }, -- PvpHud (5 s)
			stamp = { pri = "juice", life = 2.4, stale = 3, fightOk = true }, -- JuiceFx stamps: medals, NEW, steps
			levelBadge = { pri = "juice", life = 3, stale = 6, fightOk = true }, -- JuiceFx: the spinning level badge
			nameCard = { pri = "news", life = 4, stale = 4, fightOk = true }, -- CinemaHud: boss, place, event cards
			squadInvite = { pri = "social", life = 31, fightOk = true }, -- SquadHud: JOIN / NO, Config.Squad.inviteLife
			visitAsk = { pri = "social", life = 31, fightOk = true }, -- SquadHud: ACCEPT / NO, Config.Hq.visit.askLife
			contestVote = { pri = "social", fightOk = true }, -- ContestHud: the stars card through the show and vote
			drones = { pri = "info" }, -- HqHud: COLLECT
			passCard = { pri = "info", life = 6 }, -- PassHud: a tier or episode step with VIEW (5 s)
			taskForcePanel = { pri = "info", life = 5 }, -- TaskForceHud: the panel between legs (4 s)
			mentorPanel = { pri = "info", life = 5 }, -- MentorHud: the mentor's comic line (4 s)
			nemesisPanel = { pri = "info", life = 5 }, -- NemesisHud: the taunt panel (3.5 s)
			-- Ui.PopupGate's join cards (they also wait out the loading screen, menu, creator and prologue)
			daily = { pri = "join" }, -- DailyHud: CLAIM, X
			mentorPick = { pri = "join" }, -- MentorHud: the picker
			episode = { pri = "join" }, -- PassHud: the episode's comic panels
			board = { pri = "join" }, -- BoardHud: last week's TOP 10 title, WEAR / OK
			starter = { pri = "offer", offer = true }, -- ShopHud: the starter pack offer (never in a fight)
		},
	},
	colors = {
		-- the comic palette (2026-11-18): flat print colours with one ink
		ink = { 17, 17, 17 },
		paper = { 255, 247, 224 }, -- cream comic paper
		white = { 255, 255, 255 },
		night = { 31, 42, 68 }, -- the deep comic navy of the big panels
		gold = { 255, 210, 60 },
		red = { 255, 77, 77 },
		volt = { 120, 210, 255 },
		health = { 75, 227, 122 },
		healthLow = { 240, 80, 70 },
		stamina = { 255, 210, 90 },
		cooldown = { 0, 0, 0 },
		vigil = { 59, 130, 246 }, -- the Vigil (heroes)
		syndicate = { 255, 77, 77 },
		muted = { 140, 146, 160 },
	},
}
