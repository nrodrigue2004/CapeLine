-- Story (spec: Opening, Act 1 story, quests; Act 1 choices; Side quests; nate's lore doc, build plan steps 3
-- and 5). Pure data: the Ceremony prologue's beats and lines, the 6 Act 1 missions (mission 1 is the prologue
-- itself), the 3 choices with each side's own options and the 7 mission pockets (side quests live in
-- Config.SideQuests, lore step 10). Every number is a starting value to tune. All names and characters are original.
--
-- Act 1 missions (nate's lore, build plan step 5): every mission is co-op. `hero` and `villain` list the same
-- number of stages; a stage whose entry is the very same table in both lists is shared (one boss, one camera
-- beat, one goal for the whole party, with each side's own objective text: `text` and `villainText`), and a
-- stage with two different entries runs both at once in the same pocket, each side on its own job. The party
-- moves on when every side present has finished the stage. Camera beats (kind "scene") are short in-engine
-- moments with fixed subtitled lines: `who` names a speaker in guides.speakers; a line with `hero` and
-- `villain` texts reads by the side (nothing free-typed).
-- Guide lines (lore step 6): a stage's `radio` lines play through the guide line queue as the stage starts
-- (Patch on the radio, Lodestar in person where he stands), the same line shape without `at`.

-- Shared stages (the same table in both lists)
local SAFEHOUSE_TUNNELS = {
	kind = "scene",
	seconds = 10,
	focus = "door",
	lodestar = "door", -- Lodestar stands here (in person)
	lines = {
		{
			at = 0.5,
			who = "lodestar",
			text = "Stay close. These tunnels ran under the city long before Crane did.",
		},
		{
			at = 5,
			who = "patch",
			text = "Hi again! Patch, your friendly voice in the walls. Old Star, did you warn them about the drones?",
		},
	},
}
local SAFEHOUSE_GAUNTLET = {
	kind = "reach",
	at = "gauntletEnd",
	turrets = 4,
	room = 2,
	text = "Get past the old security line",
	radio = {
		{ who = "lodestar", text = "Old turrets. They track heat, not faces. Keep moving and stay low." },
	},
}
local SAFEHOUSE_DOOR = {
	kind = "reach",
	at = "door",
	text = "Reach the safehouse door",
	radio = {
		{
			who = "patch",
			hero = "Door's just ahead! I left the lights on for you.",
			villain = "Door's just ahead. Wipe your feet. And your record.",
		},
	},
}
local SAFEHOUSE_OFFER = {
	kind = "scene",
	seconds = 20,
	focus = "door",
	lodestar = "door",
	lines = {
		{
			at = 0.5,
			who = "lodestar",
			text = "Everyone with the Spark is being hunted. Crane's machines scan for it, so nobody can hide.",
		},
		{
			at = 5.5,
			who = "lodestar",
			hero = "The Vigil protects this city, even while it hunts us. Stand with us.",
			villain = "I know what you are. Crane wants your Spark as much as mine. Share the hideout, and keep your hands off my people.",
		},
		{
			at = 10.5,
			who = "patch",
			hero = "Welcome to the Vigil! I made you a badge. It's mostly tape.",
			villain = "A Syndicate crook in our safehouse? Fine. I'm hiding the snacks, Old Star.",
		},
		-- act1-choices (nate, 2026-11-19): the set-up for the Safehouse choice. A line with `side` reads for that
		-- side only (StoryPlan.sceneLines): Lodestar asks the Vigil's name; the Syndicate's offer comes from the
		-- Chairman, the masked boss who sends the Syndicate's orders in Acts 1 and 2 (lore "More decisions")
		{
			at = 15,
			who = "lodestar",
			side = "hero",
			text = "One more thing, rookie. I like to know who I'm trusting. What's your real name?",
		},
		{
			at = 15,
			who = "chairman",
			side = "villain",
			text = "This is the Chairman. Keep the old hero's roof, but you work for me now. A fair cut of every job.",
		},
	},
}
-- act1-choices: after the Safehouse choice. A line with `when = { choice, option }` reads only for a hero whose
-- own pick in that save slot is that option (and only on its `side`: each side has its own options). Act 1's
-- hints at Lodestar's secret (lore, 2026-11-19): the torn photo by the door (PocketLayout's dungeon) and how he
-- dodges Patch's question about his old students. Nobody explains it until Act 2.
local SAFEHOUSE_AFTER = {
	kind = "scene",
	seconds = 13,
	focus = "door",
	lodestar = "door",
	lines = {
		{
			at = 0.5,
			who = "lodestar",
			side = "hero",
			when = { 5, 1 },
			text = "A real name. Thank you. I'll keep it safe, the way I keep you safe.",
		},
		{
			at = 0.5,
			who = "lodestar",
			side = "hero",
			when = { 5, 2 },
			text = "Keep it, then. A mask keeps the people you love out of this.",
		},
		{
			at = 0.5,
			who = "chairman",
			side = "villain",
			when = { 5, 1 },
			text = "Smart. The Syndicate looks after its own. Don't make me regret it.",
		},
		{
			at = 0.5,
			who = "chairman",
			side = "villain",
			when = { 5, 2 },
			text = "A bigger cut? Bold. Fine. Earn every coin of it, or I take it all back.",
		},
		{
			at = 5,
			who = "patch",
			hero = "Hey, Old Star, who are the kids in that torn photo by the door? Your old students?",
			villain = "Don't touch the torn photo by the door. Old Star gets weird about it. Trust me.",
		},
		{
			at = 9,
			who = "lodestar",
			hero = "Old friends. A long time ago. Patch, show our rookie the bunks.",
			villain = "That photo is none of your business. Rest up. Then get out of my safehouse.",
		},
	},
}

local FRAMED_BRIDGE = {
	kind = "scene",
	seconds = 11,
	focus = "boss",
	lines = {
		{ at = 0.5, who = "patch", text = "Radiant's over the bridge, and the cables are snapping!" },
		{ at = 4, who = "radiant", text = "Stay back, citizens! A rogue Spark hero did this!" },
		{ at = 7.5, who = "patch", text = "A rogue Spark? Those are Radiant's own light bolts!" },
	},
}
local FRAMED_FAKE = {
	kind = "fake",
	enemy = "Radiant",
	at = "boss",
	hpMult = 0.8,
	dmg = 0.6,
	text = "Crack Radiant's face on camera",
	villainText = "Knock Radiant down for its data core",
	radio = {
		{
			who = "patch",
			hero = "Radiant's coming down! Hit hard and crack that golden face on camera!",
			villain = "Radiant's coming down. Knock it flat. That core is worth a fortune.",
		},
	},
}
local FRAMED_PROOF = {
	kind = "scene",
	seconds = 8,
	focus = "fake",
	lines = {
		{
			at = 0.3,
			who = "patch",
			hero = "Its face! It's metal! And you got it ALL on camera!",
			villain = "Metal under the gold. And there's a data core glowing in its chest.",
		},
		{ at = 4.5, who = "radiant", text = "Identity compromised. Retreat." },
	},
}
local FRAMED_NEWS = {
	kind = "scene",
	seconds = 10,
	focus = "spawn",
	lines = {
		{
			at = 0.5,
			who = "crane",
			text = "Radiant reports a rogue Spark wrecked the bridge. Crane Industries is helping every victim.",
		},
		{
			at = 5.5,
			who = "patch",
			hero = "Lies. But we've got the footage, and Old Star is going to love it.",
			villain = "Lies. Not that you care, as long as you got paid.",
		},
	},
}

local COPY_SCAN = {
	kind = "scene",
	seconds = 11,
	focus = "copy",
	lines = {
		{ at = 0.5, who = "patch", text = "Hold still. Something on that roof is scanning you." },
		{
			at = 4,
			who = "patch",
			text = "It copied your Spark. Your face, your powers. That's YOU over there!",
		},
		{ at = 8, who = "copy", text = "Copy complete. I'll take your life from here." },
	},
}
local COPY_TWIN = {
	kind = "twin",
	at = "copy",
	text = "Beat your evil twin across the rooftops",
	villainText = "Beat the copy wearing your face",
	radio = {
		{
			who = "patch",
			hero = "It fights like you, so think like you! Find the move it hasn't copied yet!",
			villain = "It fights like you and cheats like you. So cheat harder!",
		},
	},
}
local COPY_AFTER = {
	kind = "scene",
	seconds = 9,
	focus = "copy",
	lines = {
		{
			at = 0.5,
			who = "patch",
			hero = "Whoever can copy you can copy anyone. The city needs proof it can see.",
			villain = "Somebody out there copies anyone they like. Someone should show the whole city, for a price.",
		},
		{ at = 5, who = "patch", text = "Crane Tower has the biggest broadcast mast in town. Just saying." },
	},
}

local SIGNAL_CLIMB = {
	kind = "reach",
	at = "top",
	text = "Climb Crane Tower",
	radio = {
		{
			who = "patch",
			hero = "Crane Tower. Biggest mast in town. Climb, and smile for nobody.",
			villain = "Crane Tower. Every screen in town runs through that mast. Climb.",
		},
	},
}
local SIGNAL_INSIDER = {
	kind = "scene",
	seconds = 13,
	focus = "mast",
	lines = {
		{
			at = 0.5,
			who = "insider",
			text = "You don't know me. I work for Crane, and I've seen what's in his vaults.",
		},
		{ at = 5, who = "insider", text = "The broadcast mast is open for the next ten minutes. Use it." },
		{
			at = 9,
			who = "patch",
			hero = "A Crane insider? Could be a trap. Your call.",
			villain = "A Crane insider handing us every screen in the city? Your call, boss.",
		},
	},
}
local SIGNAL_WARDEN = {
	kind = "boss",
	enemy = "NullSentinel", -- the Warden
	hpMult = 8,
	adds = { "SparkDrone", 3 },
	text = "Beat the tower's Warden",
	radio = {
		{
			who = "patch",
			hero = "The tower's Warden! Big, slow and angry. Hit it while it turns!",
			villain = "The tower's Warden. Big, slow, and guarding our payday. Smash it.",
		},
	},
}
local SIGNAL_ON_AIR = {
	kind = "scene",
	seconds = 11,
	focus = "mast",
	lines = {
		{
			at = 0.5,
			who = "patch",
			hero = "We're on every screen! Now we need a fake to unmask, live, where nobody can deny it.",
			villain = "Your feed is on every screen. Crane pays, or the city sees what you saw.",
		},
		{
			at = 6,
			who = "crane",
			text = "Brightharbor, criminals hijacked our towers tonight. Tomorrow, Bulwark speaks at the Hero Hall.",
		},
	},
}

local LIVE_EVENT = {
	kind = "scene",
	seconds = 12,
	focus = "boss",
	lines = {
		{ at = 0.5, who = "crane", text = "Brightharbor! The hero who never falls: Bulwark!" },
		{
			at = 4.5,
			who = "bulwark",
			text = "Citizens. I am your shield. Every rogue Spark will be brought in.",
		},
		{ at = 8.5, who = "patch", text = "Cameras rolling. The whole city is watching. Crack that face!" },
	},
}
local LIVE_FAKE = {
	kind = "fake",
	enemy = "Bulwark",
	at = "boss",
	hpMult = 1,
	dmg = 0.7,
	news = "unmask", -- the crack goes out on every screen in the server (a news flash for everyone)
	text = "Crack Bulwark's face live on every screen",
	villainText = "Crack Bulwark's face for the whole city",
	radio = {
		{
			who = "patch",
			hero = "Bulwark's on stage. Crack that face for the whole city to see!",
			villain = "Bulwark's on stage. Break it on live TV and the city will fear us.",
		},
	},
}
local LIVE_UNMASKED = {
	kind = "scene",
	seconds = 8,
	focus = "fake",
	lines = {
		{ at = 0.3, who = "patch", text = "Every screen in the city just saw that! Bulwark is a ROBOT!" },
		{ at = 4.5, who = "bulwark", text = "Exposure detected. Battle form." },
	},
}
-- act1-choices: after the Live choice, Crane answers on air before the ending broadcast. His "the Vigil buries its
-- mistakes" is Act 1's TV hint at Lodestar's secret (lore, 2026-11-19); `when` lines read by the hero's own pick.
local LIVE_AFTER = {
	kind = "scene",
	seconds = 14,
	focus = "boss",
	lines = {
		{
			at = 0.5,
			who = "patch",
			side = "hero",
			when = { 6, 1 },
			text = "You took the mask off on live TV! Now the whole city sees a real person, not a robot.",
		},
		{
			at = 0.5,
			who = "patch",
			side = "hero",
			when = { 6, 2 },
			text = "Mask stays on. Smart. The city saw the robot fall, not your face.",
		},
		{
			at = 0.5,
			who = "patch",
			side = "villain",
			when = { 6, 1 },
			text = "You threatened Crane on live TV. In front of everyone. That was terrifying. Nice.",
		},
		{
			at = 0.5,
			who = "patch",
			side = "villain",
			when = { 6, 2 },
			text = "Footage sold. The buyer paid double, and now every channel in town will play it.",
		},
		{
			at = 5,
			who = "crane",
			text = "Brightharbor, don't be fooled by cheap tricks. Ask your heroes why the Vigil buries its mistakes.",
		},
		{
			at = 10,
			who = "patch",
			hero = "Buries its mistakes? What's he talking about, Old Star? ...Old Star?",
			villain = "Buries its mistakes? Ha. Sounds like a secret worth selling one day.",
		},
	},
}
local LIVE_BATTLE = {
	kind = "warframe",
	text = "Bring down Bulwark's battle form",
	villainText = "Wreck Bulwark's battle form",
	radio = {
		{
			who = "patch",
			hero = "Battle form! Hit the glowing spot on its back, and duck behind the pillars!",
			villain = "Battle form! Its back is the weak spot, and the pillars stop its laser.",
		},
	},
}

return {
	-- The Ceremony prologue (nate's lore, build plan step 3; mission 1): about 4 minutes, right after the creator.
	-- Silas Crane hands out medals at Crane's Hero Hall in the Downtown plaza; his scanner finds the new hero's
	-- Spark; a run through the panic, a rooftop chase by Skylance, a subway full of falling tunnel, a fight that
	-- cracks the fake's face to metal, a swarm of security robots, and Lodestar's rescue. Then the billboard and the
	-- CAPELINE title card. Every line is fixed text here (nothing free-typed); a line with `hero` and `villain`
	-- texts reads by the side picked in the creator. OpeningPlan.STEPS is the beat order.
	opening = {
		clockTime = 14.5, -- a bright afternoon on the client while it runs (bright world, serious story)
		-- a stuck prologue finishes itself (straight to the title and the rewards) after this (prologue-cine,
		-- 2026-11-20: 330 -> 480, so a player who misses every prompt to the 3rd-miss help still gets the fight;
		-- tests/cine_test.luau sums that worst case)
		timeout = 480,
		reach = 14, -- studs from a target that count as there (missions use it too)
		-- timed beats (seconds); the skip button shows on them only on a replay or for a returning account
		-- (onboarding check 2026-11-18: ceremony 30 -> 22 and scan 8 -> 7.5 with the same lines re-timed to their
		-- reading time, so the first control comes at 29.5 s, not 38; rescue 9 -> 13 so its three lines can be read)
		-- (prologue-cine, 2026-11-20: the suit is a HOLD prompt now, so it moved to the stuck timers: the device
		-- says when the suit has snapped on, OpeningAct 7)
		beats = { ceremony = 22, scan = 7.5, rescue = 13, title = 10 },
		-- a beat the hero has not finished in this long moves on by itself (the hero is placed at the next one)
		-- (prologue-cine, 2026-11-20: every beat to the subway fight is a directed cinematic with prompts; each
		-- timer is longer than that beat's worst case, every prompt missed to the 3rd-miss help, which
		-- tests/cine_test.luau checks: spark 12 -> 30, chase 90 -> 130)
		stuck = {
			run = 45,
			spark = 30,
			leap = 45,
			chase = 130,
			suit = 24,
			descend = 50,
			tunnel = 75,
			fight = 100,
			swarm = 11,
		},
		-- a hero who misses a hop in the leap or the chase and lands this far below the roof they left is put back
		-- on it after `after` seconds (no street wait until the beat's stuck timer)
		fall = { drop = 10, after = 1.2 },
		-- a returning account's held ceremony (the main menu's CREATE FIRST or PLAY THE PROLOGUE) waits at most
		-- this long, then takes the Create First path (the rewards, straight to the city), so it never soft-locks
		holdMax = 120,
		-- the beats on the rooftop row: while any prologue is on one, the row's buildings are held whole (other
		-- players' fights cannot knock out a roof a new hero is about to land on); released as each run moves on
		holdRow = { leap = true, chase = true, suit = true },
		-- the plaza: the stage in front of Crane's Hero Hall, the crowd on the street before it
		plaza = {
			stage = { gap = 4, depth = 14, width = 44, height = 4 }, -- from the Hall's face, studs
			crowd = { count = 30, low = 14, rows = 4, near = 8, far = 34, seed = 91000 }, -- low: the phone preset's crowd; seed: their citizen looks (CitizenRenderer.dressRig)
			start = 18, -- the hero stands this far from the stage, among the crowd
			kid = 4, -- the kid (Vigil) or the shover (Syndicate) stands this far from the spark point
		},
		run = { minD = 60, maxD = 110 }, -- the spark point: open ground this far from the start, away from the stage
		-- fires on Basic (or by itself); the shove flies 70; the beat then holds for the Ceremony's choice (`pick`)
		-- (prologue-cine: the Spark is a prompt now, so `auto` 6 -> 16 waits out its worst case before firing)
		spark = { reach = 18, auto = 16, blast = 70 },
		-- the chase: the first `count` roofs of the rooftop row (Config.City.downtown.row, nate 2026-11-17); if
		-- the row is missing, a chain of `fallback` ordinary Downtown roofs near the spark point
		roofs = {
			count = 6,
			fallback = 3,
			minH = 18,
			maxH = 200,
			near = { 20, 160 },
			gap = { 30, 75 },
			climb = 12,
		},
		-- the guided hops (kid-proof, nate's playtest 2026-11-18; OpeningPlan.HOPS): a Leap press on a roof is a set
		-- arc to the beat's target. Its time is flat / speed + drop / fall (clamped to `time`), its height above
		-- the higher end flat * lift (clamped to `height`); the server grants the travel (MoveGuard)
		hop = { speed = 62, fall = 160, time = { 0.8, 2.2 }, lift = 0.22, height = { 8, 22 }, grant = 30 },
		chase = { fake = "Skylance", behind = 26, throwEvery = 3.2, warn = 0.7 }, -- harmless telegraphed spears
		-- The rooftop chase as a cinematic with quick-time prompts (fix-flow, nate's playtest 2026-11-19: "I can
		-- literally just kill skylance while im doing rooftop stuff. It should be a cutscene with QTE's"; Shared.QtePlan,
		-- Fx.PrologueQte, Ui.QteHud). On the `beats` the hero's own controls rest and the camera is the chase camera;
		-- every hop is a prompt: JUMP (the Leap key, A, or a tap on the prompt) and, on the `dodge` hops of the chase,
		-- a DODGE first (the Block key, LB, or a tap) as Skylance's spear comes in. The prompt shows `lead` s after
		-- the hero lands and is open for `window` s (`ease` times longer after a miss); a press before it shows is
		-- ignored, a wrong prompt key or no press is a miss: the hero teeters (no damage) and the prompt comes back
		-- `retry` s later; after `assist` misses in a row the hop happens by itself, so nobody is stuck. Skylance
		-- cannot be hurt, stunned, knocked or grabbed until the fight (EnemyService.tune untouchable).
		qte = {
			-- the beats with prompts, played as directed cinematics with the runner's camera (prologue-cine,
			-- 2026-11-20: every beat from the ceremony to the subway fight; the ceremony, the scan and the Ceremony's
			-- choice keep their own camera shots, OpeningPlan.CUT and PrologueFx)
			beats = {
				run = true,
				spark = true,
				leap = true,
				chase = true,
				suit = true,
				descend = true,
				tunnel = true,
			},
			camera = {
				run = true,
				spark = true,
				leap = true,
				chase = true,
				suit = true,
				descend = true,
				tunnel = true,
			},
			lead = 0.6,
			window = 2.4,
			ease = 1.5,
			retry = 1.2,
			assist = 3,
			dodge = { [4] = true, [6] = true }, -- chase hops (route roof numbers) with a DODGE before the JUMP
			side = 3.5, -- studs the DODGE side-step moves
			camSide = 24, -- the chase camera: studs to the side of the hop, up and behind
			camUp = 11,
			camBack = 10,
			camEase = 5, -- how fast the camera follows (per second)
			-- the prompt's verb (UI words; prologue-cine adds GRAB, the Spark's SHIELD and SMASH, the mash and the suit)
			words = {
				Leap = "JUMP!",
				Block = "DODGE!",
				drop = "DROP!",
				Catch = "GRAB!",
				shield = "SHIELD!",
				smash = "SMASH!",
				mash = "BREAK FREE!",
				suit = "SUIT UP!",
			},
			-- prologue-cine (nate, 2026-11-20: "dont have the player run to the gold marker. whole prologue needs to
			-- be cutscene with qtes until subway"): every beat from the ceremony to the subway fight is directed
			-- (Shared.PrologueCine: the hero's authored path, clips and camera shots; Fx.PrologueQte runs it). The
			-- prompt kinds: a press (JUMP, DODGE, GRAB, SHIELD or SMASH), a mash (SMASH! `mash.count` presses
			-- inside `mash.window` s) and a hold (SUIT UP: the key held `hold.seconds`, inside `hold.window` s).
			-- A prompt shows `lead` s before the move in front of it ends, so a quick player never stops.
			mash = { count = 6, window = 3.4 },
			hold = { seconds = 1.0, window = 4 },
			grab = 5, -- the chase hop (route roof number) that falls short: GRAB the ledge, then climb
			-- the authored motion: studs a second on the runs (the server grants the travel, MoveGuard), the arcs'
			-- heights, the slow-mo leap's length and the drop's
			speed = { run = 30, tunnel = 34, roll = 16 },
			arc = { vault = 6, roll = 1.5, climb = 4, leap = 26, leapTime = 1.9 },
			-- the camera shots (PrologueCine.camera): studs out, up and ahead for each kind
			shot = {
				track = { back = 13, up = 6, ahead = 10 },
				front = { ahead = 13, up = 4, side = 3 },
				low = { side = 10, up = 1.2, back = 4 },
				wide = { side = 0.3, up = 16, rise = 0.1 }, -- to the side of the arc, near its peak, close on the hero
				top = { up = 16, back = 7 }, -- above and behind the hero, riding the drop down
				ledge = { back = 10, side = 5, up = 3 }, -- out from the wall the hero hangs on, a little above
				over = { back = 8, side = 6, up = 5 },
				orbit = { radius = 11, up = 3, turn = 100 },
			},
			grantRate = 140, -- studs a second of travel the server grants on the directed beats (the drop falls fast)
			suitMin = 1.0, -- the suit beat's least seconds before the device's "suit snapped" counts
			startReach = 30, -- a directed move waits until the body is this near its start (a cut's placing arrived)
			slowMo = 0.35, -- the hero's clips run this slow on the device while a prompt waits (and on the big leap)
			fightWord = "FIGHT!", -- the handoff banner as the subway fight starts (control and the HUD come back)
		},
		-- The exposition before the creator (fix-flow, nate's playtest 2026-11-19: "The game should open with some
		-- sort of exposition that tells the player whats going on. get to the customization, then prologue"): a
		-- brand-new character's first thing is the comic page Config.Cinema.comic.pages[page] (Config.Cinema.scenes
		-- .intro; SKIP from `skipAfter` s, even the first time), then the creator, then the Ceremony prologue after
		-- PLAY (Shared.FlowPlan). The server opens the creator by itself if the device never answers in `timeout` s.
		intro = { page = "intro", scene = "intro", skipAfter = 1.5, timeout = 60 },
		-- The intro film (list-combat 2026-11-20, nate: a cold open "before anything else", then short in-engine
		-- cutscenes instead of the intro comic; Shared.IntroFilm, Fx.IntroFilm): played in the real city round the
		-- hero's spot, a tower within `reach` studs between minHeight and maxHeight tall and minWidth wide; the
		-- street `streetOut` studs off its face. `film = false` falls back to the comic page.
		film = {
			on = true,
			seconds = 45,
			reach = 320,
			minWidth = 24,
			minHeight = 60,
			maxHeight = 260,
			streetOut = 26,
			tries = 6,
			-- the Dread Syndicate on the tower's roof (a masked crook in earnable Syndicate pieces; DRAFT look for nate)
			syndicate = {
				gender = 1,
				build = 2,
				height = 4,
				skin = 3,
				hair = 22,
				colors = { 22, 15, 6 }, -- black, plum, lime
				pieces = {
					suit = "Rib Frame",
					back = "Tattered Cape",
					head = "Half Mask",
					hands = "Gloves",
					feet = "Tall Boots",
					emblem = "Moon",
					visage = "Man Face", -- Roblox catalog face
				},
				tints = {},
				mats = {},
			},
			you = 5, -- the crowd look (PrologueFx.cast "citizen") the you-in-the-crowd figure wears
			glow = { 255, 220, 90 }, -- the hero's trail and the spark's light
		},
		-- The Ceremony's choice (act1-choices, 2026-11-19; Config.Story.choices[choice]): `delay` s after the Spark
		-- fires (the shield pops, the shover flies) the moment freezes into a short camera beat with the choice card
		-- (Fx.PrologueFx, never during the rooftop quick-time prompts); a hero who has not picked in `wait` s moves
		-- on with the slot left open (a REPLAY asks again); `after` s after the pick the leap begins. A slot already
		-- picked (a replay) is not asked again.
		pick = { choice = 4, delay = 1.2, wait = 20, after = 3.5 },
		suit = { pieceGap = 0.16 }, -- the suit snaps on piece by piece this fast
		entrance = { minD = 20, maxD = 80 }, -- the subway steps: open ground below the last roof
		-- the subway pocket: Config.Story.pockets index count + 1 (missions never take it), one lane per prologue
		subway = {
			lanes = 6,
			pitch = 64, -- lane centres this far apart
			width = 26,
			height = 24,
			length = 300, -- start to the fight chamber
			chamber = 56, -- the chamber at the end, square
			-- tunnel collapses (kid-proof, nate's playtest 2026-11-18): the tunnel caves in BEHIND the hero, never
			-- on them: a slab falls across the lane `at` studs in once the hero is `behind` studs past its far edge,
			-- so every run plays the same chase-by-rubble and nothing blocks or knocks the hero back
			collapses = {
				{ at = 60 },
				{ at = 120 },
				{ at = 180 },
				{ at = 240 },
			},
			behind = 6,
			slab = 10, -- studs deep
			rubble = 4, -- the pile left behind is this tall (it shuts the way back)
		},
		fight = { fake = "Skylance", hpMult = 0.55, dmg = 0.35, lowHealth = 0.3 }, -- ends at the face crack
		-- the Crane Troopers; in the subway each starts at least `margin` studs inside the fight chamber's walls
		swarm = { kind = "SparkDrone", count = 7, ring = 22, margin = 5, dmg = 0.12, lowHealth = 0.35 },
		reward = { level = 3, skillPoints = 1 }, -- level 3 and Flight, as the old opening paid
		next = 2, -- the hook: mission 2 (Safehouse, lore step 5) is what the Journal pins next
		-- the billboard for the last shot: a tall building's face toward the plaza
		billboard = { minH = 80, near = { 140, 380 }, size = { 70, 40 } },
		-- Lodestar (veteran Vigil hero; Patch calls him "Old Star"): a fixed look from earnable creator pieces
		lodestar = {
			name = "LODESTAR",
			title = "THE VIGIL",
			look = {
				gender = 1,
				build = 3,
				height = 5,
				skin = 4,
				hair = 19, -- silver
				colors = { 11, 19, 4 }, -- navy, silver, gold
				pieces = {
					suit = "Split Tone",
					back = "Classic Cape",
					hands = "Gloves",
					feet = "Tall Boots",
					emblem = "Star",
					beard = "Styled Beard Black", -- a Roblox catalog beard (gap-villains, 2026-11-19)
					shoulders = "Mantle",
					belt = "Utility Belt",
					visage = "Man Face", -- Roblox catalog face (picked for the character, 2026-11-19)
					hair = "Black Braid", -- Roblox catalog hair
				},
				tints = { back = { 11, 4, 0 } },
				mats = {},
			},
		},
		-- the voices are Config.Story.guides.speakers (lore step 6: one guide system for every line)
		-- subtitled lines by beat: `at` seconds into the beat
		lines = {
			ceremony = {
				{ at = 0.5, who = "crane", text = "Brightharbor! Thank you all for coming out today." },
				{ at = 4.6, who = "crane", text = "Ten years ago, the Spark nearly tore this city apart." },
				{ at = 8.8, who = "crane", text = "Today we honour the heroes who keep you safe. Radiant!" },
				{ at = 13, who = "crane", text = "Bulwark! And Skylance! Guardians of Brightharbor!" },
				{
					at = 17.4,
					who = "crane",
					text = "And with our new scanners, no rogue Spark will hurt you again.",
				},
			},
			scan = {
				{ at = 0.4, who = "crane", text = "Scanners on, everyone. Big smiles!" },
				{ at = 3.6, who = "crane", text = "Well, well. It seems we have a guest. Officers?" },
			},
			run = {
				{
					at = 1,
					who = "crane",
					text = "Please remain calm! Crane Industries has this under control!",
				},
			},
			spark = {
				{
					at = 0.5,
					who = "crane",
					hero = "Officers! Get that rogue away from the child!",
					villain = "You see? A rogue Spark, attacking citizens! This is why we scan!",
				},
			},
			leap = {
				{
					at = 1,
					who = "patch",
					text = "Hey! You, the one glowing like a firework! Can you hear me?",
				},
				{ at = 5.5, who = "patch", text = "I'm Patch. I hacked your phone. Jump to that roof, now!" },
			},
			chase = {
				{
					at = 0.5,
					who = "patch",
					hero = "You shielded that kid. Cool. Now Skylance is on your tail!",
					villain = "You sent that guy flying. Noted. Now Skylance is on your tail!",
				},
				{ at = 7, who = "patch", text = "Keep jumping! His spears never miss twice!" },
				{
					at = 14,
					who = "patch",
					hero = "Roof to roof, over the street! Don't look down!",
					villain = "Roof to roof! Don't let the Silver Streak catch you!",
				},
				{
					at = 22,
					who = "patch",
					hero = "Almost clear! I'm finding you a way off these roofs!",
					villain = "Almost clear! I'm finding you somewhere to vanish!",
				},
			},
			suit = {
				{ at = 0.4, who = "patch", text = "Whoa. Is your Spark making you a suit? That is SO cool." },
			},
			descend = {
				{
					at = 0.5,
					who = "patch",
					text = "Subway steps, down below! His scanners can't see underground!",
				},
			},
			tunnel = {
				{ at = 0.5, who = "patch", text = "That's the old tunnel. It's not exactly stable. RUN!" },
			},
			fight = {
				{ at = 0.5, who = "patch", text = "He's blocking the way out. You'll have to fight him!" },
			},
			swarm = {
				{
					at = 0.3,
					who = "patch",
					text = "His face... it's METAL! Skylance is a robot? He's a FAKE!",
				},
				{
					at = 5,
					who = "patch",
					text = "Security bots, a whole squad! Hang on, I'm calling Old Star!",
				},
			},
			rescue = {
				{
					at = 1.2,
					who = "lodestar",
					hero = "Easy, rookie. You fought like the Vigil. Let an old star take it from here.",
					villain = "Mean little Spark you've got. Crane wants it. Tonight, he doesn't get it.",
				},
				{ at = 6.6, who = "patch", text = "Old Star! I knew you'd come!" },
				{ at = 9.7, who = "lodestar", text = "Hold on tight. We're going underground." },
			},
			title = {
				{ at = 0.8, who = "crane", text = "Crane Industries keeps Brightharbor bright." },
			},
		},
		-- the scan's banner and the billboard (fixed text)
		detected = "SPARK DETECTED",
		slogan = "A SAFER CITY, ONE SPARK AT A TIME",
		brand = "CRANE INDUSTRIES",
		hall = "CRANE'S HERO HALL",
		-- the printed pictures (art/prologue/ads.py, uploaded Image ids; 0 = not uploaded: the fixed text above is
		-- drawn on the part instead): the Hall's banner behind the stage and the Crane Industries billboard ad
		art = { banner = 72802172729417, billboard = 96457001071583 },
	},

	-- Mission pockets: sealed 400 x 400 areas at y = 3,000 (no PvP, no world schedulers)
	pockets = { count = 7, size = 400, y = 3000, z = 1900, firstX = -1800, gap = 600, wall = 60 },

	-- The story's acts in play order (WP11, gap G14; Shared.StoryPlan reads them). Every mission and choice
	-- names its act. An act with soon = true is a locked row in the Journal ("Act 2: coming soon"): it has no
	-- missions, no choices and no story text, and nothing in it can be entered or pinned. Adding an act is
	-- data only: its missions go after the last act's (the next numbers, each with its own act; the save's
	-- mission bits hold saveRoom.missions), its choices take the next save slots (saveRoom.choices), the act's last
	-- mission names its ending in `ending` below, and its row here drops soon. No beats are written for acts
	-- 2 and 3: their story is nate's to decide (drafts only under "Proposals (NOT decided)" in the notes).
	acts = {
		{ num = 1 },
		{ num = 2, soon = true },
		{ num = 3, soon = true },
	},
	-- the only words a coming-soon act shows (its tab and its locked row)
	actText = { tab = "ACT %d", soon = "Act %d: coming soon", locked = "LOCKED" },
	-- the save's room (ProfileSchema repairs to it): mission first-clear bits and choice slots across all acts
	saveRoom = { missions = 24, choices = 12 },

	-- Act 1 (nate's lore, build plan step 5): minLevel and the order gate entry; first clears pay once. Levels,
	-- minutes and rewards are the old Act 1's at the same index, so pacing and totals do not move.
	missions = {
		{
			num = 1,
			act = 1, -- WP11: the act this mission belongs to (Config.Story.acts)
			id = "Ceremony",
			name = "The Ceremony",
			minLevel = 1,
			opening = true, -- the prologue (lore step 3), in the city and the subway pocket, not the board
			skillPoints = 1,
			blurb = "Crane's medal ceremony goes wrong. Your Spark wakes up.",
		},
		{
			num = 2,
			act = 1,
			id = "Safehouse",
			name = "Safehouse",
			minLevel = 3,
			layout = "dungeon",
			minutes = 8,
			loot = "story",
			blurb = "Lodestar takes you underground. Patch is on the radio.",
			hero = {
				SAFEHOUSE_TUNNELS,
				{
					kind = "defeat",
					squads = { { "SparkDrone", 3 }, { "BurglarBot", 2 } },
					room = 1,
					text = "Clear the scanner drones from the tunnel",
					radio = {
						{
							who = "patch",
							text = "Scanner drones! If they see your Spark, Crane sees it too. Knock them out!",
						},
					},
				},
				SAFEHOUSE_GAUNTLET,
				SAFEHOUSE_DOOR,
				SAFEHOUSE_OFFER,
				{ kind = "choice", choice = 5, text = "Tell Lodestar your real name?" },
				SAFEHOUSE_AFTER,
			},
			villain = {
				SAFEHOUSE_TUNNELS,
				{
					kind = "break",
					points = 3,
					hits = 12,
					list = "relays",
					text = "Smash Crane's scanner relays",
					radio = {
						{
							who = "patch",
							text = "Those relays feed Crane's scanners. Smash them and we all go dark.",
						},
					},
				},
				SAFEHOUSE_GAUNTLET,
				SAFEHOUSE_DOOR,
				SAFEHOUSE_OFFER,
				{ kind = "choice", choice = 5, text = "The Chairman's offer" },
				SAFEHOUSE_AFTER,
			},
		},
		{
			num = 3,
			act = 1,
			id = "Framed",
			name = "Framed",
			minLevel = 4,
			layout = "bridge",
			minutes = 8,
			loot = "story",
			renown = 600,
			blurb = "Radiant wrecks a bridge and blames a real hero.",
			hero = {
				FRAMED_BRIDGE,
				{
					kind = "hold",
					points = 3,
					seconds = 10,
					radius = 12,
					waves = { { "SparkDrone", 4 }, { "SparkDrone", 5 }, { "BurglarBot", 3 } },
					waveGap = 14,
					people = true, -- a person pinned under a girder at each ring (StoryFx; cosmetic)
					text = "Get the people off the bridge",
					radio = {
						{
							who = "patch",
							text = "People are stuck on the deck! Stand in each ring till they're safe.",
						},
					},
				},
				FRAMED_FAKE,
				FRAMED_PROOF,
				{ kind = "choice", choice = 1, text = "The bridge or the fake?" },
				{ kind = "branch", choice = 1 },
				FRAMED_NEWS,
			},
			villain = {
				FRAMED_BRIDGE,
				{
					kind = "break",
					points = 3,
					hits = 14,
					guards = { "Turret", 2 },
					look = "StoryVan", -- the armored trucks' look (Shared.StoryArtKit; cosmetic)
					text = "Loot the armored trucks in the chaos",
					radio = {
						{
							who = "patch",
							text = "Armored trucks, no drivers, total chaos. You didn't hear it from me.",
						},
					},
				},
				FRAMED_FAKE,
				FRAMED_PROOF,
				{ kind = "choice", choice = 1, text = "The data core or the cash?" },
				{ kind = "branch", choice = 1 },
				FRAMED_NEWS,
			},
			-- what each side's pick puts in at the branch (option 1, option 2)
			branches = {
				hero = {
					{
						kind = "break",
						points = 1,
						hits = 30,
						train = true,
						text = "Stop the runaway train before the gap",
						radio = {
							{
								who = "patch",
								text = "Runaway train heading for the gap! Hit it till it stops!",
							},
						},
					},
					{
						kind = "chase",
						enemy = "Radiant",
						fake = true,
						hops = 7,
						speed = 24,
						text = "Chase Radiant down",
						radio = {
							{
								who = "patch",
								text = "Radiant's running! Don't lose it over the towers!",
							},
						},
					},
				},
				villain = {
					{
						kind = "chase",
						enemy = "Radiant",
						fake = true,
						hops = 7,
						speed = 24,
						text = "Run Radiant down and rip out its data core",
						radio = {
							{
								who = "patch",
								text = "Radiant's running off with that core. Run it down!",
							},
						},
					},
					{
						kind = "break",
						points = 1,
						hits = 30,
						at = "van",
						text = "Crack the armored cash van",
						radio = {
							{
								who = "patch",
								text = "Cash van, locked tight. Crack it before the real cops show up.",
							},
						},
					},
				},
			},
		},
		{
			num = 4,
			act = 1,
			id = "TheCopy",
			name = "The Copy",
			minLevel = 5,
			layout = "rooftops",
			minutes = 7,
			rep = 120, -- own-side reputation on the first clear
			blurb = "A fake copies your look and powers. Fight your evil twin.",
			hero = {
				{
					kind = "reach",
					at = "contact",
					text = "Answer the rooftop alarm",
					radio = {
						{
							who = "patch",
							text = "A rooftop alarm with your name on it. Weird. Go check it out.",
						},
					},
				},
				COPY_SCAN,
				COPY_TWIN,
				{ kind = "choice", choice = 3, text = "Your twin's core" },
				COPY_AFTER,
			},
			villain = {
				{
					kind = "reach",
					at = "contact",
					text = "Meet the fence on the rooftop",
					radio = {
						{
							who = "patch",
							text = "Your fence wants a rooftop meet. Sounds legit. Totally. Go.",
						},
					},
				},
				COPY_SCAN,
				COPY_TWIN,
				{ kind = "choice", choice = 3, text = "Your twin's core" },
				COPY_AFTER,
			},
		},
		{
			num = 5,
			act = 1,
			id = "TheSignal",
			name = "The Signal",
			minLevel = 6,
			layout = "tower",
			minutes = 10,
			loot = "story",
			blurb = "Take Crane's broadcast tower so the city sees the truth.",
			hero = {
				SIGNAL_CLIMB,
				SIGNAL_INSIDER,
				{ kind = "choice", choice = 2, text = "Trust the insider?" },
				{ kind = "branch", choice = 2 },
				{
					kind = "hold",
					points = 1,
					seconds = 20,
					radius = 10,
					at = "mast",
					waves = { { "SparkDrone", 3 }, { "BurglarBot", 3 } },
					waveGap = 12,
					text = "Guard Patch's uplink at the mast",
					radio = {
						{
							who = "patch",
							text = "I'm patching into the mast! Keep the bots off me for twenty seconds!",
						},
					},
				},
				SIGNAL_WARDEN,
				SIGNAL_ON_AIR,
			},
			villain = {
				SIGNAL_CLIMB,
				SIGNAL_INSIDER,
				{ kind = "choice", choice = 2, text = "The truth feed" },
				{ kind = "branch", choice = 2 },
				{
					kind = "hold",
					points = 1,
					seconds = 20,
					radius = 10,
					at = "relay",
					waves = { { "BurglarBot", 3 }, { "SparkDrone", 3 } },
					waveGap = 12,
					text = "Plant the Syndicate feed on the relay",
					radio = {
						{
							who = "patch",
							text = "Plant the feed on the relay and hold it. I'll make it look pretty.",
						},
					},
				},
				SIGNAL_WARDEN,
				SIGNAL_ON_AIR,
			},
			branches = {
				hero = {
					{ kind = "none" }, -- trust: straight on
					{
						kind = "defeat",
						squads = { { "BurglarBot", 4 }, { "SparkDrone", 2 } },
						at = "top", -- on the tower's deck, where the party stands
						text = "Testing her tipped off the guards: beat them",
						radio = {
							{
								who = "patch",
								text = "Testing her tipped off the guards! Told you it could be a trap!",
							},
						},
					},
				},
				villain = { { kind = "none" }, { kind = "none" } },
			},
		},
		{
			num = 6,
			act = 1,
			id = "Live",
			name = "Live",
			minLevel = 8,
			layout = "arena",
			minutes = 12,
			loot = "storyFinale",
			skillPoints = 1,
			finale = true,
			ending = "act1", -- the ending broadcast plays after it (Config.Story.ending)
			blurb = "Unmask a famous fake live on every screen in the city.",
			hero = {
				{
					kind = "hold",
					points = 3,
					seconds = 6,
					radius = 10,
					list = "cams",
					waves = { { "SparkDrone", 3 }, { "BurglarBot", 2 } },
					waveGap = 16,
					text = "Set up the cameras around the stage",
					radio = {
						{
							who = "patch",
							text = "Set the cameras on their marks. I need every angle of that stage!",
						},
					},
				},
				LIVE_EVENT,
				LIVE_FAKE,
				LIVE_UNMASKED,
				LIVE_BATTLE,
				{ kind = "choice", choice = 6, text = "The cameras are on you" },
				LIVE_AFTER,
			},
			villain = {
				{
					kind = "break",
					points = 3,
					hits = 14,
					list = "screens",
					guards = { "Turret", 1 },
					text = "Hijack the stage screens",
					radio = {
						{
							who = "patch",
							text = "Hijack the stage screens. When Bulwark cracks, it's our show.",
						},
					},
				},
				LIVE_EVENT,
				LIVE_FAKE,
				LIVE_UNMASKED,
				LIVE_BATTLE,
				{ kind = "choice", choice = 6, text = "Crane is still on air" },
				LIVE_AFTER,
			},
		},
	},

	-- Choices (nate's lore: one per side in every Act 1 mission; Framed, The Signal and The Copy first, then The
	-- Ceremony, Safehouse and Live, act1-choices 2026-11-19). Each side has its own two options; the first three
	-- grant 2 Skill Points once (the later three none). An option records its story flag and pays reputation,
	-- and a few add a cosmetic (the Echo Drone, the crackling arena) or a title or Credits (`reward`): nothing
	-- that changes stats. The choice number is the save slot, kept from the old Act 1 so older picks keep their
	-- meaning (1 the first mission choice, 2 the trust test, 3 the robot core; 4 to 6 the new ones).
	choices = {
		{
			num = 1,
			act = 1, -- WP11: the act this choice belongs to (Config.Story.acts)
			mission = 3,
			skillPoints = 2,
			hero = {
				{ label = "Save the Bridge", flag = "bridgeSaved", rep = { "city", 100 } },
				{ label = "Chase the Fake", flag = "fakeChased", rep = { "side", 100 } },
			},
			villain = {
				{ label = "Grab the Data Core", flag = "coreStolen", rep = { "side", 100 } },
				{ label = "Grab the Cash", flag = "cashGrabbed", rep = { "side", 100 } },
			},
		},
		{
			num = 2,
			act = 1,
			mission = 5,
			skillPoints = 2,
			hero = {
				{ label = "Trust Her", flag = "insiderTrusted", rep = { "side", 100 } },
				{ label = "Test Her", flag = "insiderTested", rep = { "city", 100 } },
			},
			villain = {
				{ label = "Share the Feed", flag = "feedShared", rep = { "city", 100 } },
				{ label = "Hold It for Ransom", flag = "feedRansomed", rep = { "side", 100 } },
			},
		},
		{
			num = 3,
			act = 1,
			mission = 4,
			skillPoints = 2,
			hero = {
				{ label = "Spare the Core", flag = "twinStudied", rep = { "side", 100 } },
				{ label = "Destroy It", flag = "twinDestroyed", rep = { "city", 100 }, arena = true }, -- Live's
				-- arena pillars crackle (a cosmetic arena effect)
			},
			villain = {
				{ label = "Reprogram It", flag = "twinMinion", rep = { "side", 100 }, perk = "NullEcho" }, -- the
				-- twin's core as a little drone minion (cosmetic)
				{ label = "Sell It", flag = "twinSold", rep = { "side", 100 } },
			},
		},
		-- act1-choices (nate, 2026-11-19: "every mission should get a choice, for act 1 too"; the lore doc's
		-- "Story choices draft" rows 1-1, 1-2 and 1-6, approved as written). Save slots 4 to 6 (old saves read 0,
		-- "not yet": nothing they picked moves). Each option changes lines (`say`: said right after the pick, and
		-- the scenes' `when` lines), pays reputation (one option of each side's pair pays the side's own track and
		-- the other City Reputation, so Act 1's least own-side total and the rank pace stay put; the Vigil's
		-- Safehouse pair both pay Trust) and a reward that is a title or Credits only: no Skill Points, nothing
		-- that changes stats (Act 1 still grants 8 Skill Points). The rewards and amounts are Claude's (the doc
		-- names none), for nate to approve.
		{
			num = 4,
			act = 1,
			mission = 1, -- The Ceremony: asked in the prologue's spark beat, right after the Spark fires
			skillPoints = 0,
			hero = {
				{
					label = "Pull the Kid Clear",
					flag = "kidPulled",
					rep = { "side", 60 },
					reward = { title = "First Save" },
					say = {
						{ who = "crane", text = "That rogue just grabbed a child! Officers, stop them!" },
					},
				},
				{
					label = "Catch the News Crew",
					flag = "crewCaught",
					rep = { "city", 60 }, -- saved on camera: the city saw it
					reward = { credits = 100 },
					say = {
						{ who = "crane", text = "Cut the cameras! Cut the feed! Officers, get that rogue!" },
					},
				},
			},
			villain = {
				{
					label = "Grab the Medal",
					flag = "medalGrabbed",
					rep = { "side", 60 },
					reward = { title = "Medal Snatcher" },
					say = { { who = "crane", text = "My medal! That rogue is a thief too! Officers!" } },
				},
				{
					label = "Grab the Keycard",
					flag = "keycardGrabbed",
					rep = { "city", 40 }, -- quiet work: to the crowd you are one more of Crane's scanner victims
					reward = { credits = 150 },
					say = {
						{ who = "crane", text = "Guards! Where is your keycard? Lock the Hall down, now!" },
					},
				},
			},
		},
		{
			num = 5,
			act = 1,
			mission = 2, -- Safehouse: after the offer scene
			skillPoints = 0,
			hero = {
				{
					label = "Tell Your Real Name",
					flag = "nameTold",
					rep = { "side", 100 },
					reward = { title = "True Name" },
				},
				{
					label = "Keep It Secret",
					flag = "nameKept",
					rep = { "side", 50 },
					reward = { credits = 150 },
				},
			},
			villain = {
				{
					label = "Take the Deal",
					flag = "dealTaken",
					rep = { "city", 50 }, -- the Chairman's people keep your face off Crane's news
					reward = { title = "Chairman's Pick" },
				},
				{
					label = "Demand a Bigger Cut",
					flag = "cutDemanded",
					rep = { "side", 100 },
					reward = { credits = 250 },
				},
			},
		},
		{
			num = 6,
			act = 1,
			mission = 6, -- Live: after Bulwark's battle form falls, still on every screen
			skillPoints = 0,
			hero = {
				{
					label = "Show Your Face",
					flag = "faceShown",
					rep = { "city", 150 }, -- proof you're real, live
					reward = { title = "Face of Hope" },
				},
				{
					label = "Keep the Mask On",
					flag = "maskKept",
					rep = { "side", 100 },
					reward = { credits = 250 },
				},
			},
			villain = {
				{
					label = "Threaten Crane",
					flag = "craneThreatened",
					rep = { "side", 150 },
					reward = { title = "Prime Time Threat" },
				},
				{
					label = "Sell the Footage",
					flag = "footageSold",
					rep = { "city", 50 }, -- the buyer airs it: the city sees Bulwark fall again
					reward = { credits = 400 },
				},
			},
		},
	},
	perks = {
		NullEcho = {
			bit = 1,
			name = "Echo Drone",
			text = "A little drone made from a robot core follows you",
		},
	},

	-- The end of Act 1 (nate's lore: Crane answers on TV; the registration law passes and the hero is public
	-- enemy number 1): a news-style screen on the HUD after Live, back in the city. Fixed lines; the hero's
	-- own name goes under PUBLIC ENEMY #1.
	ending = {
		act1 = {
			seconds = 20,
			channel = "CRANE NEWS NETWORK",
			breaking = "BREAKING NEWS",
			headline = "HERO REGISTRATION ACT PASSES",
			ticker = "Every Spark must register and be scanned by Crane Industries  *  Unregistered Sparks will be hunted",
			lines = {
				{
					at = 1,
					who = "crane",
					text = "Tonight a criminal used a cheap trick to attack Bulwark on live TV.",
				},
				{
					at = 6,
					who = "crane",
					text = "So tonight the Hero Registration Act is law. Every Spark registers.",
				},
				{
					at = 11,
					who = "crane",
					text = "And the one behind this attack is now public enemy number one.",
				},
			},
			enemyAt = 13, -- seconds: the PUBLIC ENEMY #1 card slams in
			enemy = "PUBLIC ENEMY #1",
			sign = "TO BE CONTINUED",
		},
	},
	-- The guides (nate's lore, build plan step 6): Lodestar, the veteran Vigil hero, in person (Patch calls him
	-- "Old Star"); Patch, the hacker kid, on the radio; Silas Crane's broadcast voice. Every line in the game
	-- (the prologue, the missions' camera beats and stage lines, the open-world radio, Lodestar's talk) plays
	-- through one line queue on the device (Ui.GuideHud, Shared.GuidePlan): one line at a time with its
	-- speaker's portrait, name colour and blip. Subtitles and a blip now, real voice lines later (nate). All
	-- text is fixed here; a line with `hero` and `villain` texts reads by the side (nothing free-typed).
	guides = {
		-- style: "person" (in person), "radio" (a RADIO tag, a static flicker on the portrait) or "broadcast"
		-- (Crane on the stage, the plaza speakers and TV: an ON AIR tag). blip: a Config.Audio.sounds key,
		-- played as each line starts. portrait: drawn from frames on the device (PLACEHOLDER ART until the art
		-- pass): bg, skin and hair colours, a hair shape and extras.
		speakers = {
			lodestar = {
				name = "LODESTAR",
				color = { 150, 190, 255 },
				style = "person",
				blip = "guideLodestar",
				portrait = {
					bg = { 30, 42, 86 },
					skin = { 214, 160, 120 },
					hair = { 205, 210, 220 },
					shape = "slick",
					extras = { "beard", "scar", "star" },
				},
			},
			patch = {
				name = "PATCH",
				color = { 120, 230, 255 },
				style = "radio",
				blip = "radio",
				portrait = {
					bg = { 18, 60, 72 },
					skin = { 241, 194, 160 },
					hair = { 120, 78, 40 },
					shape = "messy",
					extras = { "cap", "headset" },
				},
			},
			crane = {
				name = "SILAS CRANE",
				color = { 255, 210, 60 },
				style = "broadcast",
				blip = "guideCrane",
				portrait = {
					bg = { 64, 50, 18 },
					skin = { 232, 190, 160 },
					hair = { 70, 64, 58 },
					shape = "slick",
					extras = { "tie" },
				},
			},
			-- Act 1's cast (lore step 5): the insider is a voice on the radio; the fakes speak in person
			insider = {
				name = "CRANE INSIDER",
				color = { 230, 160, 255 },
				style = "radio",
				blip = "guideInsider",
				portrait = {
					bg = { 50, 30, 70 },
					skin = { 200, 150, 120 },
					hair = { 30, 30, 36 },
					shape = "hood",
					extras = {},
				},
			},
			radiant = {
				name = "RADIANT",
				color = { 255, 220, 120 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 96, 74, 20 },
					skin = { 255, 222, 176 },
					hair = { 255, 214, 90 },
					shape = "slick",
					extras = { "mask" },
				},
			},
			bulwark = {
				name = "BULWARK",
				color = { 200, 205, 215 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 60, 62, 72 },
					skin = { 200, 182, 160 },
					hair = { 150, 156, 170 },
					shape = "helmet",
					extras = { "visor" },
				},
			},
			-- The Chairman (lore "More decisions", 2026-11-19): the Dread Syndicate's masked boss, who sends its
			-- orders through Acts 1 and 2 by radio (the mask comes off at Act 3's truce: Duchess Vanta, the reveal
			-- nate kept for the Syndicate). A creator look for the cast art: a full face plate over a catalog face,
			-- a wide brim, no hair, a black tuxedo and a high-collared cape that hide the build.
			chairman = {
				name = "THE CHAIRMAN",
				color = { 220, 70, 80 },
				style = "radio",
				blip = "guideInsider",
				portrait = {
					bg = { 44, 14, 22 },
					skin = { 160, 105, 70 },
					hair = { 24, 24, 28 },
					shape = "hood",
					extras = { "mask" },
				},
				look = {
					gender = 2,
					build = 3,
					height = 5,
					skin = 5,
					hair = 22, -- black (no hair piece shows)
					colors = { 22, 38, 4 }, -- black, maroon, gold
					pieces = {
						suit = "Tuxedo",
						head = "Full Face Plate",
						hat = "Wide Brim", -- a crime boss's brim over the plate
						back = "High Collar Cape",
						hands = "Gloves",
						feet = "Loafers",
						visage = "Sinister", -- Roblox catalog face (under the plate)
					},
					hairless = true, -- no catalog hair: the plate and the brim cover the head
					tints = { back = { 22, 38, 0 } }, -- a black cape lined in maroon
					mats = {},
				},
			},
			copy = {
				name = "THE COPY",
				color = { 255, 110, 110 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 80, 20, 24 },
					skin = { 150, 152, 162 },
					hair = { 40, 40, 44 },
					shape = "messy",
					extras = { "visor" },
				},
			},
			-- the side quest chains' own cast (lore step 11; the givers speak from Config.SideQuests.givers)
			-- The Hero Academy: Headmaster Halo on the school speakers and in person, and Wren, the runaway student
			halo = {
				name = "HEADMASTER HALO",
				color = { 120, 200, 255 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 30, 60, 100 },
					skin = { 245, 214, 186 },
					hair = { 205, 210, 220 },
					shape = "slick",
					extras = { "mask" },
				},
			},
			wren = {
				name = "WREN",
				color = { 255, 170, 120 },
				style = "person",
				blip = "guideInsider",
				portrait = {
					bg = { 90, 50, 40 },
					skin = { 160, 110, 80 },
					hair = { 40, 28, 24 },
					shape = "messy",
					extras = { "cap" },
				},
			},
			-- The Gala Heist (chain 2): Madame Masque-a-rade in person (a gold masquerade mask), and Redline on
			-- the racers' radio (a red visor)
			masque = {
				name = "MADAME MASQUE-A-RADE",
				color = { 200, 120, 255 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 60, 24, 80 },
					skin = { 241, 194, 160 },
					hair = { 70, 20, 110 },
					shape = "slick",
					extras = { "mask" },
				},
			},
			redline = {
				name = "REDLINE",
				color = { 255, 80, 60 },
				style = "radio",
				blip = "guideInsider",
				portrait = {
					bg = { 90, 20, 20 },
					skin = { 160, 105, 70 },
					hair = { 220, 40, 40 },
					shape = "helmet",
					extras = { "visor" },
				},
			},
			-- Wind-Up Lane (the Suburbs): the Toymaker, an old inventor, on his shop's music-box speakers and in
			-- person, and Toby, the boy whose Spark winds clockwork when he is upset
			toymaker = {
				name = "THE TOYMAKER",
				color = { 230, 190, 90 },
				style = "broadcast",
				blip = "guideCrane",
				portrait = {
					bg = { 70, 40, 30 },
					skin = { 241, 194, 160 },
					hair = { 235, 235, 240 },
					shape = "messy",
					extras = { "beard", "visor" },
				},
			},
			toby = {
				name = "TOBY",
				color = { 120, 200, 255 },
				style = "person",
				blip = "guideInsider",
				portrait = {
					bg = { 40, 70, 110 },
					skin = { 255, 224, 196 },
					hair = { 230, 170, 70 },
					shape = "messy",
					extras = {},
				},
			},
			-- The Harvest King (chain 4, Farmland): the farmer in person, a crown of wheat on a grey shock of hair
			harvest = {
				name = "THE HARVEST KING",
				color = { 230, 190, 60 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 70, 90, 30 },
					skin = { 198, 140, 100 },
					hair = { 175, 180, 190 },
					shape = "messy",
					extras = { "beard", "crown" },
				},
			},
			-- The Salt Dogs (the Coast): Captain Brine on his ship's loudhailer and buoy speakers and in person (a
			-- diving helm portrait with his beard and scar), and Finn, Skipper Nell's deckhand grandson
			brine = {
				name = "CAPTAIN BRINE",
				color = { 40, 190, 170 },
				style = "broadcast",
				blip = "guideCrane",
				portrait = {
					bg = { 20, 50, 60 },
					skin = { 224, 172, 130 },
					hair = { 240, 225, 200 },
					shape = "helmet",
					extras = { "beard", "scar" },
				},
			},
			finn = {
				name = "FINN",
				color = { 255, 180, 90 },
				style = "person",
				blip = "guideInsider",
				portrait = {
					bg = { 40, 80, 110 },
					skin = { 198, 140, 100 },
					hair = { 80, 50, 30 },
					shape = "messy",
					extras = { "cap" },
				},
			},
			-- The Sunken City (the Underwater chain): the Tidewright, Velmara's guardian machine, its voice carried
			-- through the water (a bronze helm with glowing eyes and a crown), and Dace, the salvage diver whose
			-- dredger cracked the city's seal
			tidewright = {
				name = "THE TIDEWRIGHT",
				color = { 60, 200, 190 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 10, 40, 60 },
					skin = { 170, 120, 70 },
					hair = { 170, 255, 200 },
					shape = "helmet",
					extras = { "beard", "crown" },
				},
			},
			dace = {
				name = "DACE",
				color = { 240, 170, 40 },
				style = "person",
				blip = "guideInsider",
				portrait = {
					bg = { 30, 70, 100 },
					skin = { 160, 105, 70 },
					hair = { 30, 26, 24 },
					shape = "slick",
					extras = { "goggles" },
				},
			},
			-- The Pit (chain 6, the Old Quarry): the Pitboss on the Pit's loudspeakers and in person (stone-grey skin,
			-- slicked black hair, his showman's top hat and a handlebar moustache), and Flint, a young Spark fighter
			-- the Gravel family keeps fighting off a debt (a plaster across the nose)
			pitboss = {
				name = "THE PITBOSS",
				color = { 200, 60, 50 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 70, 26, 30 },
					skin = { 150, 140, 130 },
					hair = { 24, 24, 28 },
					shape = "slick",
					extras = { "tophat", "moustache" },
				},
			},
			flint = {
				name = "FLINT",
				color = { 255, 150, 60 },
				style = "person",
				blip = "guideInsider",
				portrait = {
					bg = { 60, 50, 46 },
					skin = { 224, 172, 130 },
					hair = { 200, 90, 40 },
					shape = "messy",
					extras = { "bandage" },
				},
			},
			-- The character lines (lore step 11): Vesper, Lodestar's old partner, or the famous stranger wearing her
			-- face (silver-white hair, a star at the brow); Lark, Patch's big sister, on her old radio from the
			-- pound (a cap like her brother's); Catchpole the Spark catcher (a hood and goggles); Sal Scorch of
			-- the Torch Crew (a scar and a flame-red crop); and the Censor, a black bar where his eyes should be
			vesper = {
				name = "VESPER",
				color = { 220, 150, 255 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 50, 30, 80 },
					skin = { 236, 196, 170 },
					hair = { 235, 235, 245 },
					shape = "slick",
					extras = { "star" },
				},
			},
			lark = {
				name = "LARK",
				color = { 255, 200, 80 },
				style = "radio",
				blip = "radio",
				portrait = {
					bg = { 70, 50, 30 },
					skin = { 241, 194, 160 },
					hair = { 120, 78, 40 },
					shape = "messy",
					extras = { "cap", "bandage" },
				},
			},
			catchpole = {
				name = "CATCHPOLE",
				color = { 150, 200, 90 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 40, 50, 36 },
					skin = { 198, 150, 110 },
					hair = { 90, 70, 50 },
					shape = "hood",
					extras = { "goggles", "beard" },
				},
			},
			scorch = {
				name = "SAL SCORCH",
				color = { 255, 120, 40 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 80, 30, 20 },
					skin = { 214, 160, 120 },
					hair = { 230, 70, 30 },
					shape = "messy",
					extras = { "scar" },
				},
			},
			censor = {
				name = "THE CENSOR",
				color = { 200, 200, 210 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 20, 20, 26 },
					skin = { 210, 200, 196 },
					hair = { 40, 40, 46 },
					shape = "slick",
					extras = { "tie", "blackbar" },
				},
			},
			-- The origin lines (lore step 11). The Ashgrove Test: Doctor Holloway on the lab's speakers and in his
			-- rig (silver slicked hair, spectacles).
			holloway = {
				name = "DOCTOR HOLLOWAY",
				color = { 80, 220, 230 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 26, 40, 60 },
					skin = { 241, 194, 160 },
					hair = { 175, 180, 190 },
					shape = "slick",
					extras = { "spectacles" },
				},
			},
			-- Starblood Calling: the Voidhound's cold machine voice (an antenna helm, a single purple visor)
			voidhound = {
				name = "THE VOIDHOUND",
				color = { 190, 90, 255 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 20, 16, 40 },
					skin = { 70, 60, 110 },
					hair = { 40, 44, 60 },
					shape = "helmet",
					extras = { "visor" },
				},
			},
			-- The Last Owner: Morrow the Mirage (top hat, masquerade mask) and Ambrose the Astonishing, the
			-- relic's last owner, an old stage magician with a white beard
			morrow = {
				name = "MORROW",
				color = { 120, 80, 220 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 30, 20, 50 },
					skin = { 255, 236, 220 },
					hair = { 24, 24, 28 },
					shape = "slick",
					extras = { "tophat", "mask" },
				},
			},
			ambrose = {
				name = "AMBROSE",
				color = { 230, 190, 60 },
				style = "person",
				blip = "guideLodestar",
				portrait = {
					bg = { 60, 30, 50 },
					skin = { 224, 172, 130 },
					hair = { 245, 245, 245 },
					shape = "messy",
					extras = { "beard" },
				},
			},
			-- Suit Recall: Clawback on his repo crew's loudspeakers (ball cap, horseshoe moustache)
			clawback = {
				name = "CLAWBACK",
				color = { 230, 190, 60 },
				style = "broadcast",
				blip = "guideFake",
				portrait = {
					bg = { 50, 46, 30 },
					skin = { 198, 140, 100 },
					hair = { 80, 50, 30 },
					shape = "slick",
					extras = { "cap", "moustache" },
				},
			},
			-- The Taken Master: Gale (a wild mane, a headband, a scar) and Master Hoshi (a grey beard, a headband)
			gale = {
				name = "GALE",
				color = { 40, 190, 170 },
				style = "person",
				blip = "guideFake",
				portrait = {
					bg = { 20, 50, 56 },
					skin = { 224, 172, 130 },
					hair = { 55, 58, 66 },
					shape = "messy",
					extras = { "headband", "scar" },
				},
			},
			hoshi = {
				name = "MASTER HOSHI",
				color = { 245, 245, 245 },
				style = "person",
				blip = "guideLodestar",
				portrait = {
					bg = { 50, 40, 36 },
					skin = { 241, 194, 160 },
					hair = { 175, 180, 190 },
					shape = "slick",
					extras = { "beard", "headband" },
				},
			},
		},
		-- the three guides: each has its own blip and portrait
		guides = { "lodestar", "patch", "crane" },
		tags = { radio = "RADIO", broadcast = "ON AIR" },
		maxChars = 120, -- a line fits a phone's subtitle box (3 to 4 short rows)
		-- the queue: a line shows base + chars * perChar seconds (min to max); a camera beat's lines stay until
		-- the next (at most `hold`); open-world lines wait while a camera beat runs, and go stale after `ttl`
		queue = { base = 1.2, perChar = 0.055, min = 3, max = 7, hold = 6, ttl = 25, catchUp = 6 },
		-- the box: centred under the letterbox on a camera beat; in play, the widest free spot clear of the
		-- action buttons, the HUD's status corner and the top row (Shared.GuidePlan.box)
		box = { maxW = 560, minW = 250, h = 84, hCompact = 78, portrait = 56, letterbox = 0.1 },
		-- where the lore doc puts each guide (mission numbers): Lodestar pulls you out in the prologue and runs
		-- the safehouse; Patch is on the radio in every mission
		appears = { lodestar = { 1, 2 }, patch = { 1, 2, 3, 4, 5, 6 } },
		-- Patch on the radio in the open world (outside missions and the prologue; the "Guide radio" setting
		-- turns it off): at most one line every `gap` seconds; firstIncident and firstBoss once a session;
		-- unlock[n] when a level-up opens mission n; idle[n] when the hero stands still `idle` seconds with
		-- mission n pinned in the Journal (again after `idleRepeat`); afterAct1 `afterAct` seconds after the
		-- ending broadcast. A stage line in a mission plays only if the stage began under `stageLate` s ago.
		radio = {
			gap = 45,
			idle = 75,
			idleRepeat = 300,
			idleMove = 8, -- studs: moving less than this counts as standing still
			afterAct = 3,
			stageLate = 8,
			powerWait = 120, -- first-30: a level-up's POWERS line waits this long for the radio to be free
			lines = {
				firstIncident = {
					who = "patch",
					hero = "Trouble on the radar! Somebody needs a hand. Go be a hero!",
					villain = "Trouble on the radar. Messy, loud and profitable. Your kind of thing.",
				},
				firstBoss = {
					who = "patch",
					hero = "Something HUGE just landed! Not one of Crane's, I think. Team up!",
					villain = "Something huge just landed. Big things drop big loot. Just saying.",
				},
				unlock = {
					[2] = {
						who = "patch",
						hero = "Old Star's waiting under the plaza. The Safehouse mission is open!",
						villain = "Old Star wants a word under the plaza. The Safehouse mission is open.",
					},
					[3] = {
						who = "patch",
						hero = "Level up! Something's wrong at the bridge. Framed is in your Journal.",
						villain = "Level up! A bridge, a fake and armored trucks. Framed is in your Journal.",
					},
					[4] = {
						who = "patch",
						hero = "Level up! A rooftop alarm keeps pinging your name. The Copy is open.",
						villain = "Level up! A fence wants a rooftop meet. The Copy is open.",
					},
					[5] = {
						who = "patch",
						hero = "Level up! Crane Tower's mast is calling. The Signal is open.",
						villain = "Level up! Crane Tower runs every screen in town. The Signal is open.",
					},
					[6] = {
						who = "patch",
						hero = "Level up! Bulwark's big show is coming. Live is open. Time to crack a face.",
						villain = "Level up! Bulwark's big show is coming. Live is open. Let's ruin it.",
					},
				},
				idle = {
					[2] = {
						who = "patch",
						hero = "Psst. Old Star's waiting under the plaza. The Safehouse is pinned in your Journal!",
						villain = "Psst. Old Star's deal is still on the table. Safehouse, in your Journal.",
					},
					[3] = {
						who = "patch",
						hero = "Radiant's up to something at the bridge. Framed is pinned in your Journal.",
						villain = "Those armored trucks won't loot themselves. Framed is in your Journal.",
					},
					[4] = {
						who = "patch",
						hero = "That rooftop alarm is still going off. The Copy is in your Journal.",
						villain = "Your fence is still waiting on that roof. The Copy is in your Journal.",
					},
					[5] = {
						who = "patch",
						hero = "Crane Tower's mast won't hack itself. The Signal is in your Journal.",
						villain = "Every screen in town, for a price. The Signal is in your Journal.",
					},
					[6] = {
						who = "patch",
						hero = "Bulwark's show is tonight. Live is pinned in your Journal. Let's go!",
						villain = "Bulwark's show is tonight. Live is in your Journal. Bring a crowbar.",
					},
				},
				-- first-30 (2026-11-20): a level-up that opens a skill slot or a move training rank (GuidePlan.powerAt);
				-- nothing else told a new hero about the third slot and rank 1 at level 5. Once a session per level;
				-- waits out the gap (after a mission unlock line on the same level) for up to `powerWait` s.
				-- first-30: a side quest chain opened (GuidePlan.newSideQuest): %s is the chain's name (fixed text)
				sqOpen = {
					who = "patch",
					hero = "New side quest: %s! Look for the gold ! on your MAP.",
					villain = "New job going: %s. Find the ! on your MAP.",
				},
				powerBoth = {
					who = "patch",
					hero = "Level up! A new power slot AND move training just opened. Tap POWERS!",
					villain = "Level up. New power slot, new move training. Tap POWERS and get scarier.",
				},
				powerSlot = {
					who = "patch",
					hero = "Level up! You've got room for another power. Tap POWERS!",
					villain = "Level up. Room for one more power. Tap POWERS.",
				},
				powerRank = {
					who = "patch",
					hero = "Level up! New move training is open in POWERS. Go faster, hero!",
					villain = "Level up. New move training in POWERS. Faster getaways!",
				},
				-- lore step 9: the rare Your double world event starts on this hero (it skips the gap; GuidePlan.URGENT)
				double = {
					who = "patch",
					hero = "Uh oh. There are TWO of you on my scanner. A fake copied you again. Crack its face!",
					villain = "Two of you on my scanner? A fake stole your face. Nobody steals from you. Smash it!",
				},
				afterAct1 = {
					who = "patch",
					hero = "Public enemy number one? Old Star says that means we're winning. Lie low, hero.",
					villain = "Public enemy number one! The Syndicate is throwing you a party. Probably.",
				},
			},
		},
		-- Lodestar in person in the Vigil's HQ, The Safehouse (the hero's HQ cell; he keeps away from the Foundry): a Talk
		-- prompt `at` (x, z from the cell centre), each talk the next line of the rotation for the story so
		-- far (the first tier whose `from` is at or under the next mission's number; 7 when Act 1 is done).
		lodestar = {
			at = { 14, -30 },
			range = 12,
			prompt = "Talk",
			spawnFor = 60, -- seconds the Dev panel's Lodestar stays
			talk = {
				{
					from = 1,
					lines = {
						"You found the Safehouse. Rest a minute. The tunnel run is in your Journal.",
						"The kid talks a lot. Listen anyway. Patch is never wrong about Crane.",
						"Your Spark woke up the hard way. Mine did too.",
					},
				},
				{
					from = 3,
					lines = {
						"The fakes stage the disasters, then take the bows. Watch for the cracks.",
						"Save people first. Footage second. Pride never.",
						"Patch made you a badge? Wear it. It means a lot to the kid.",
					},
				},
				{
					from = 5,
					lines = {
						"If the city won't believe us, we show them. Every screen at once.",
						"I once fought a fake wearing a friend's face. Don't let it stop your swing.",
						"Old Star. The kid thinks I don't know about that name.",
					},
				},
				{
					from = 7,
					lines = {
						"Public enemy number one. Welcome to the Vigil, for real this time.",
						"A new law changes nothing. We protect this city anyway.",
						"Crane's next move is coming. Rest while you can, rookie.",
					},
				},
			},
		},
	},
	-- Every-screen news flashes (a toast for everyone in the server); %s is the fake's name
	news = { unmask = "BREAKING: %s IS A ROBOT FAKE" },
	-- What a side that finished its job reads while the other side is still on theirs
	wait = {
		hero = "Cover the Syndicate while they finish their job",
		villain = "Let the Vigil finish their job",
	},

	-- Reputation tracks (spec: Faction reputation): ranks at 100, 300, 600, 1,000 and 1,500. The save keeps
	-- the points as a list in this order (vigil was "league" before nate's lore, 2026-11-17: same slot).
	-- labels: what players read (Vigil rep is Trust, Syndicate rep is Fear); word: the short form.
	rep = {
		order = { "vigil", "syndicate", "city" },
		labels = { vigil = "Vigil Trust", syndicate = "Syndicate Fear", city = "City Reputation" },
		words = { vigil = "Trust", syndicate = "Fear", city = "Reputation" },
		ranks = { 100, 300, 600, 1000, 1500 },
		rescue = 5,
		mission = 50,
	},

	-- Bulwark's battle form (Live, mission 6; the old mission 6 fight reused): 36,000 HP at level 20, scaled by
	-- the party's median level. A BossSim boss with a back shield in phase 2 and pillars that block its laser in
	-- phase 3. (The key stays "warframe" so saves and data stay put.)
	warframe = {
		hp = 36000,
		atLevel = 20,
		summon = { "SparkDrone", 6 }, -- when phase 2 starts
		shieldHits = 3, -- hits on the back weak point that break the phase 2 shield
		pillars = { { -70, -40 }, { 70, -40 }, { -70, 50 }, { 70, 50 }, { 0, -100 }, { 0, 110 } }, -- x, z from the centre
		pillarRadius = 7,
	},
	-- Unlock bits for story and side quest rewards that are not gear (profile.emotes, profile.frames,
	-- profile.props, profile.titles; side quest chains name them in Config.SideQuests)
	-- Bit numbers for unlocks that rewards name (story here, Fame ranks in Config.Pvp). Titles and poses are
	-- M9's wheels; the bits are reserved now so saves never move.
	unlocks = {
		emotes = { Salute = 1, Bow = 2, SuperLanding = 20 }, -- landing poses share the emote bits from 20
		frames = { PhotoFrame = 1, FameFrame = 2 },
		props = { CafeSign = 1 },
		-- titles; plate trims share the title bits from 100
		titles = {
			Rookie = 1,
			["Local Name"] = 2,
			Headliner = 3,
			["Big Deal"] = 4,
			["Living Legend"] = 5,
			["Class Dismissed"] = 6, -- side quest chain: The Hero Academy (lore step 11)
			["Curtain Call"] = 7, -- side quest chain: The Gala Heist (lore step 11, chain 2)
			Unwound = 8, -- side quest chain: Wind-Up Lane (lore step 11)
			Uprooted = 9, -- side quest chain: The Harvest King (lore step 11, chain 4)
			Brinebreaker = 10, -- side quest chain: The Salt Dogs (lore step 11, the Coast)
			Undisputed = 11, -- side quest chain: The Pit (lore step 11, chain 6, the Old Quarry)
			["Tide Turner"] = 12, -- side quest chain: The Sunken City (lore step 11, the Underwater chain)
			["True North"] = 13, -- side quest chain: The Last Partner (lore step 11, Lodestar's character line)
			["Found Family"] = 14, -- side quest chain: Finding Lark (lore step 11, Patch's character line)
			Fireproof = 15, -- side quest chain: Hostile Takeover (lore step 11, the Syndicate boss's line)
			["Front Page"] = 16, -- side quest chain: The Scoop (lore step 11, the reporter's character line)
			["Test Passed"] = 17, -- origin line: The Ashgrove Test (Lab, lore step 11)
			Starborn = 18, -- origin line: Starblood Calling (Alien)
			["Relic Keeper"] = 19, -- origin line: The Last Owner (Magic)
			["No Returns"] = 20, -- origin line: Suit Recall (Tech)
			["Lesson Learned"] = 21, -- origin line: The Taken Master (Training)
			-- act1-choices (2026-11-19): the new Act 1 choices' titles (one option of each pair)
			["First Save"] = 22, -- The Ceremony, Vigil: pull the kid clear
			["Medal Snatcher"] = 23, -- The Ceremony, Syndicate: grab the medal
			["True Name"] = 24, -- Safehouse, Vigil: tell Lodestar your real name
			["Chairman's Pick"] = 25, -- Safehouse, Syndicate: take the Chairman's deal
			["Face of Hope"] = 26, -- Live, Vigil: show your face on air
			["Prime Time Threat"] = 27, -- Live, Syndicate: threaten Crane on air
			GoldTrim = 100,
		},
	},
}
