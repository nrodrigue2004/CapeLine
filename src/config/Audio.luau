-- Audio and the juice table (spec: Audio, VFX, juice and accessibility; Music). Pure data.
-- Every one of the 31 juice actions has a sound here and a visual somewhere in the client (tests check both).
-- The sounds pass (2026-11-19, nate's playtest: "need better sounds badly"): every row plays a recorded sound made
-- for it by art/audio/build.py (CC0 sources layered with our own synth: a low thump under every impact, cracks and
-- debris tails, whooshes, each path's element; licences in notes/Tools.md "Sounds") and music by art/audio/music.py
-- (our own, with the CC0 Meta piano). They live in five uploaded atlases (Config.AudioClips): a row's `clip` names its
-- region, or the stem of 2 to 4 variants picked at random (Shared.SoundPick); `vary` and `volVary` spread the pitch
-- and volume of each play. The `fallback` (one of Roblox's built-in client sounds, pitched by `pitch`) still plays
-- while an atlas has no id. `clip` defaults to the row's own key (see the end of this file).
-- Groups (AudioController, `mix` below): Music; Effects (the settings' sound slider) with Combat, World, Ui,
-- Ambience and Voice inside it. Music ducks 40% for the boss siren and voices; big booms duck the city bed and
-- the music for a moment (`mix.duck`).

local B = "rbxasset://sounds/"

local function s(fallback: string?, volume: number, pitch: number?, extra: { [string]: any }?)
	local t =
		{ asset = 0, fallback = if fallback then B .. fallback else nil, volume = volume, pitch = pitch or 1 }
	for k, v in extra or {} do
		t[k] = v
	end
	return t
end

local Audio = {
	-- the juice table, in spec order: action id, sound, and where its visual is drawn (tests read `visual`)
	juice = {
		{ id = "leap", visual = "MoveFx" }, -- charge hum then whoosh; dust ring; FOV widens 6%
		{ id = "land", visual = "MoveFx" }, -- heavy thud; dust ring and crack; 0.1 s shake, vibration
		{ id = "glide", visual = "MoveFx" }, -- soft air; faint trail
		{ id = "flyCruise", visual = "MoveFx" }, -- wind that rises with speed; speed lines at boost
		{ id = "boost", visual = "MoveFx" }, -- burst; trail in your colour
		{ id = "basic", visual = "CombatFx" }, -- zap, punch or crackle by set; hit flash; number pop
		{ id = "cast", visual = "CombatFx" }, -- charge and release by set; coloured shape
		{ id = "super", visual = "CombatFx" }, -- big charge-up and boom; shockwave ring; screen punch
		{ id = "crit", visual = "CombatFx" }, -- higher ping; gold number 1.5x
		{ id = "defeat", visual = "JuiceFx" }, -- pop and clatter; sparks; Credit coin burst
		{ id = "rescue", visual = "JuiceFx" }, -- cheer and chime; safe zone glow; Renown pop
		{ id = "incidentClear", visual = "JuiceFx" }, -- short fanfare; medal stamp
		{ id = "collapse", visual = "BuildingFx" }, -- rumble; dust plume; camera rumble under 80 studs
		{ id = "crater", visual = "BuildingFx" }, -- crunch; decal for 30 s
		{ id = "clash", visual = "CombatFx" }, -- impact boom; both freeze 0.3 s; shockwave ring
		{ id = "vehicleFlip", visual = "VehicleFx" }, -- metal whoomp; dust
		{ id = "downed", visual = "PvpHud" }, -- muffled heartbeat; grey edge, pulse ring
		{ id = "revive", visual = "JuiceFx" }, -- rising chime; gold ring
		{ id = "pvpFlag", visual = "PvpFx" }, -- short horn; ring grows
		{ id = "levelUp", visual = "JuiceFx" }, -- rising bell; level badge spins; next unlock lights
		{ id = "skillRank", visual = "LoadoutScreen" }, -- click and chime; node fills; UI bounce
		{ id = "gearDrop", visual = "JuiceFx" }, -- chime by tier; tier colour beam; Legendary chimes twice
		{ id = "bossWarning", visual = "WorldFx" }, -- siren and deep horn; red edge tint; banner
		{ id = "bossPhase", visual = "WorldFx" }, -- roar; phase pips flip; shake 0.4 s
		{ id = "bossDefeated", visual = "JuiceFx" }, -- fireworks; MVP card
		{ id = "combo", visual = "CombatFx" }, -- chord; combo ring; bonus Renown pop
		{ id = "purchase", visual = "JuiceFx" }, -- soft bell; NEW badge
		{ id = "photo", visual = "PhotoMode" }, -- shutter; flash only if reduce flashing is off
		{ id = "fastTravel", visual = "TravelClient" }, -- whoosh; streaks; skip button
		{ id = "respawn", visual = "JuiceFx" }, -- rising hum; protect shield ring for 5 s
		{ id = "contractDone", visual = "JuiceFx" }, -- chime; stamp; reward banner
		-- Hero MMO features (spec: "every new action gets a sound, a flash and a shake in the juice table")
		{ id = "block", visual = "GuardFx" }, -- dull clank; shield flash; BLOCKED word
		{ id = "perfectBlock", visual = "GuardFx" }, -- bright ting; gold flash; PERFECT! and a camera punch
		{ id = "shatter", visual = "GuardFx" }, -- glass crunch; orange shards; SHATTER! and a 0.12 s shake
		{ id = "interrupt", visual = "GuardFx" }, -- snip; green flash; CUT OFF!
		{ id = "chargeFull", visual = "ChargeFx" }, -- rising ping; white flash on the glowing hero (H2)
		{ id = "grab", visual = "ThrowFx" }, -- grunt thump; dust at the feet as it goes overhead (H3)
		{ id = "throwLand", visual = "ThrowFx" }, -- crash; dust ring and chips where it lands, a shake for heavy (H3)
		{ id = "nemesisArrive", visual = "NemesisFx" }, -- low horn sting; its name over its head (H5)
		{ id = "nemesisEscape", visual = "NemesisFx" }, -- teleport zap; a white flash where it stood (H5)
		{ id = "mentorPanel", visual = "MentorFx" }, -- page flip; the mentor's comic panel slides in (H6)
		{ id = "mentorReward", visual = "MentorFx" }, -- bright chime; the new look bursts on (H6)
		{ id = "badgeEarned", visual = "JuiceFx" }, -- stamp thunk and chime; the badge stamp and confetti (H7)
		{ id = "collectFind", visual = "JuiceFx" }, -- sparkle ping; a ring and the set count pop (H7)
		{ id = "lorePage", visual = "JuiceFx" }, -- side-content: page flip and a warm chime; the book bursts into gold pages, the caption card
		{ id = "moveTrain", visual = "JuiceFx" }, -- side-content: rising whoosh; a speed ring at your feet and the TRAINED! stamp
		{ id = "contestCall", visual = "JuiceFx" }, -- fanfare swoosh; the CONTEST! stamp (H7)
		{ id = "contestWin", visual = "JuiceFx" }, -- cheer ping; confetti, WINNER! on the winner's screen (H7)
		{ id = "roguePage", visual = "JuiceFx" }, -- page ping; the NEW PAGE! or GOLD PAGE! stamp (Rogues File)
		{ id = "passTier", visual = "PassHud" }, -- rising chime; the TIER UP card slides in (H8)
		{ id = "passClaim", visual = "PassHud" }, -- coin ping; the reward pops on its tier (H8)
		{ id = "episodeIntro", visual = "PassHud" }, -- page flip; the episode's 3 comic panels (H8)
		{ id = "styleBurst", visual = "TravelStyleFx" }, -- whoosh; the travel style's take-off burst (H8)
		{ id = "boardReward", visual = "BoardHud" }, -- fanfare ping; the TOP 10 card with the week's title (WP2)
		{ id = "dailyClaim", visual = "JuiceFx" }, -- coin chime; the DAY N! stamp and confetti, more on day 7 (WP1)
		{ id = "dailyQuest", visual = "JuiceFx" }, -- bright ping; the DAILY! stamp with the quest's line (WP1)
		{ id = "welcomeBack", visual = "ReturnHud" }, -- page flip; the WELCOME BACK card slides in, its rows tick in (alive-world)
		-- side quest chains (the juice pass, 2026-11-18): every moment of all 16 chains (sideQuest below)
		{ id = "questAccept", visual = "JuiceFx" }, -- page swoosh; the NEW QUEST! stamp with the chain's name
		{ id = "questStep", visual = "JuiceFx" }, -- bright chime; the step's word stamp (CAUGHT!, HELD!...), the pay pop
		{ id = "questVillain", visual = "CinemaHud" }, -- low sting; the finale villain's name card slams in
		{ id = "questEncore", visual = "JuiceFx" }, -- horn whoosh; the ENCORE! stamp with the second villain's name
		{ id = "questFinale", visual = "JuiceFx" }, -- boom and chime; fireworks over the villain, the VICTORY! stamp
		{ id = "questDone", visual = "StoryHud" }, -- fanfare and the victory sting; the result card and confetti
		{ id = "questRetry", visual = "JuiceFx" }, -- soft low ping; the TRY AGAIN! stamp (Downed in a finale)
		{ id = "wallSmash", visual = "ImpactFx" }, -- crunch and boom; chips off the wall, shake and punch (2026-11-19: rams and throws)
	},
	-- Side quest juice (the juice pass, 2026-11-18; Shared.QuestJuice reads it, StoryHud fires it): which juice
	-- row each moment of a chain fires, and the stamp word for a step done by its kind (every kind in
	-- Shared.SideQuestPlan.KINDS; tests check every step of all 16 chains maps to a row). A finale's win is
	-- questFinale, then the chain's result card (questDone) after `doneDelay` seconds. Words are fixed UI words.
	sideQuest = {
		moments = {
			accept = "questAccept", -- a chain taken (from its giver or the Journal)
			step = "questStep", -- a step done (the whole group's)
			wait = "questStep", -- your side's part done, the other side still working (no stamp)
			villain = "questVillain", -- the finale's name card
			encore = "questEncore", -- the first villain down, the encore lands
			finale = "questFinale", -- the finale won (the villain beaten)
			done = "questDone", -- the chain done: the result card with its title and cosmetic
			retry = "questRetry", -- the finale lost (Downed while the villain stands)
		},
		kinds = {
			talk = { juice = "questStep", word = "TALKED!" },
			fight = { juice = "questStep", word = "CLEARED!" },
			incident = { juice = "questStep", word = "HANDLED!" },
			chase = { juice = "questStep", word = "CAUGHT!" },
			deliver = { juice = "questStep", word = "DELIVERED!" },
			fetch = { juice = "questStep", word = "COLLECTED!" },
			hold = { juice = "questStep", word = "HELD!" },
			escort = { juice = "questStep", word = "ARRIVED!" },
			carry = { juice = "questStep", word = "CARRIED!" },
			race = { juice = "questStep", word = "FINISHED!" },
			reach = { juice = "questStep", word = "MADE IT!" },
			find = { juice = "questStep", word = "FOUND!" },
			photo = { juice = "questStep", word = "SNAPPED!" },
			beacon = { juice = "questStep", word = "LIT UP!" },
			pocket = { juice = "questStep", word = "CLEARED!" },
			finale = { juice = "questFinale", word = "VICTORY!" },
		},
		doneDelay = 1.8,
	},
	-- the spec's own juice table is the first 31 rows above; the rest came with the Hero MMO features
	juiceSpec = 31,

	-- one sound per juice action (3D ones play at the action's spot, heard within `range` studs)
	-- the impact layer under every hit you land (Config.Combat.weight): a body thud and a metal clank, lower and
	-- louder on heavy and crit hits (recorded: a punch over a low thump with grit, 3 to 4 variants each).
	impact = {
		hit = s("action_jump_land.mp3", 0.55, 0.8, { range = 90, vary = 0.08 }),
		heavy = s("action_jump_land.mp3", 0.85, 0.55, { range = 140, vary = 0.06 }),
		clank = s("clickfast.wav", 0.3, 0.75, { range = 80, vary = 0.12 }),
		whoosh = s("swoosh.wav", 0.35, 0.9, { clip = "Martial_cast", range = 70, vary = 0.1 }), -- a robot's melee blow (list-combat)
	},
	sounds = {
		leap = s("swoosh.wav", 0.6, 0.85, { range = 120 }),
		land = s("action_jump_land.mp3", 0.8, 0.7, { range = 140 }),
		glide = s("swoosh.wav", 0.25, 0.6),
		flyCruise = s("action_falling.mp3", 0.0, 1, { loop = true, speedPitch = { 0.85, 1.3 } }), -- volume follows speed (0 to 0.5), pitch too
		boost = s("swoosh.wav", 0.7, 1.25, { range = 120 }),
		basic = s("electronicpingshort.wav", 0.35, 1.6, { range = 90, vary = 0.12 }),
		cast = s("swoosh.wav", 0.55, 1.1, { range = 120, vary = 0.08 }),
		super = s("action_jump_land.mp3", 1, 0.45, { range = 260 }),
		crit = s("electronicpingshort.wav", 0.5, 2.1, { range = 90 }),
		defeat = s("action_jump_land.mp3", 0.6, 1.5, { range = 120, vary = 0.1 }),
		rescue = s("electronicpingshort.wav", 0.6, 1.2),
		incidentClear = s("electronicpingshort.wav", 0.8, 0.8),
		collapse = s("action_jump_land.mp3", 1, 0.3, { range = 400 }),
		crater = s("action_jump_land.mp3", 0.8, 0.55, { range = 200 }),
		wallSmash = s("action_jump_land.mp3", 1, 0.45, { range = 220 }),
		clash = s("action_jump_land.mp3", 1, 0.6, { range = 220 }),
		-- moving (the sounds pass, Fx.MoveAudio): the ground pound slam, an awning's spring, a splash into water,
		-- the Acrobat's dash, the sonic boom when a hero passes `Config.Audio.move.boomSpeed`, and the held rush of
		-- a Super Speed run (a loop, volume and pitch from the run's speed)
		sonicBoom = s("action_jump_land.mp3", 1, 0.4, { range = 400 }),
		pound = s("action_jump_land.mp3", 1, 0.5, { range = 260 }),
		bounce = s("action_jump_land.mp3", 0.6, 1.4, { range = 100 }),
		splash = s("impact_water.mp3", 0.7, 1, { range = 120 }),
		dash = s("swoosh.wav", 0.6, 1.3, { range = 100, vary = 0.06 }),
		speedRun = s(
			"action_falling.mp3",
			0,
			1.3,
			{ loop = true, speedPitch = { 0.8, 1.3 }, loopMax = 0.45 }
		),
		vehicleFlip = s("action_jump_land.mp3", 0.7, 0.9, { range = 160 }),
		downed = s("action_falling.mp3", 0.5, 0.4, { loop = true }), -- the muffled heartbeat while Downed
		revive = s("action_get_up.mp3", 0.8, 1.2, { range = 120 }),
		pvpFlag = s("electronicpingshort.wav", 0.7, 0.5),
		levelUp = s("electronicpingshort.wav", 0.9, 1.4),
		skillRank = s("button.wav", 0.6, 1.2),
		gearDrop = s("electronicpingshort.wav", 0.6, 1.8),
		bossWarning = s("action_falling.mp3", 1, 0.3, { duck = true }),
		bossPhase = s("action_jump_land.mp3", 1, 0.35, { range = 500 }),
		bossDefeated = s("electronicpingshort.wav", 1, 1),
		combo = s("electronicpingshort.wav", 0.8, 1.05, { range = 200 }),
		purchase = s("electronicpingshort.wav", 0.7, 1.3),
		photo = s("clickfast.wav", 0.8, 1),
		fastTravel = s("swoosh.wav", 0.8, 0.7),
		respawn = s("action_get_up.mp3", 0.7, 0.8),
		contractDone = s("electronicpingshort.wav", 0.7, 0.95),
		block = s("action_jump_land.mp3", 0.5, 1.8, { range = 100, vary = 0.08 }),
		perfectBlock = s("electronicpingshort.wav", 0.8, 2.4, { range = 120 }),
		shatter = s("action_jump_land.mp3", 0.9, 1.25, { range = 160 }),
		interrupt = s("clickfast.wav", 0.8, 0.8, { range = 120 }),
		chargeFull = s("electronicpingshort.wav", 0.7, 2.7, { range = 110 }),
		grab = s("action_get_up.mp3", 0.6, 1.4, { range = 90, vary = 0.08 }),
		throwLand = s("action_jump_land.mp3", 1, 0.7, { range = 220, vary = 0.1 }),
		nemesisArrive = s("swoosh.wav", 1, 0.45, { range = 260 }),
		nemesisEscape = s("electronicpingshort.wav", 0.9, 0.5, { range = 220 }),
		mentorPanel = s("swoosh.wav", 0.4, 1.6),
		mentorReward = s("electronicpingshort.wav", 0.8, 1.9),
		badgeEarned = s("electronicpingshort.wav", 0.8, 1.5),
		collectFind = s("electronicpingshort.wav", 0.7, 2.2),
		collectNear = s("clickfast.wav", 0.25, 2.4, { range = 40 }), -- the soft chime near a find (not a juice row)
		-- side-content (2026-11-19): lore pages and mobility training
		lorePage = s("swoosh.wav", 0.7, 1.8),
		loreNear = s("electronicpingshort.wav", 0.2, 2.8, { range = 45 }), -- the soft chime near an unread page (not a juice row)
		moveTrain = s("swoosh.wav", 0.8, 0.85),
		contestCall = s("swoosh.wav", 0.6, 1.2),
		contestWin = s("electronicpingshort.wav", 0.8, 1.3),
		roguePage = s("electronicpingshort.wav", 0.75, 1.15), -- the Rogues File
		passTier = s("electronicpingshort.wav", 0.8, 1.7),
		passClaim = s("electronicpingshort.wav", 0.6, 2.1),
		episodeIntro = s("swoosh.wav", 0.5, 1.4),
		styleBurst = s("swoosh.wav", 0.5, 1.1, { range = 120, vary = 0.08 }),
		-- the Swing (2026-11-19, SwingFx): the line's thwip, the release whoosh (louder on a sweet one), the miss.
		swingShoot = s("swoosh.wav", 0.4, 2.1, { range = 90, vary = 0.1 }),
		swingRelease = s("swoosh.wav", 0.6, 0.9, { range = 110, vary = 0.06 }),
		swingMiss = s("clickfast.wav", 0.35, 0.7),
		boardReward = s("electronicpingshort.wav", 0.8, 1.3), -- WP2: a weekly board title
		dailyClaim = s("electronicpingshort.wav", 0.8, 1.6),
		dailyQuest = s("electronicpingshort.wav", 0.7, 1.15),
		welcomeBack = s("swoosh.wav", 0.6, 1.25, { clip = "episodeIntro" }), -- the WELCOME BACK card (alive-world 2026-11-20)
		-- side quest chains (the juice pass)
		questAccept = s("swoosh.wav", 0.6, 1.3),
		questStep = s("electronicpingshort.wav", 0.75, 1.25),
		questVillain = s("action_falling.mp3", 0.8, 0.4),
		questEncore = s("swoosh.wav", 0.9, 0.5),
		questFinale = s("action_jump_land.mp3", 0.9, 0.5),
		questDone = s("electronicpingshort.wav", 1, 1.1, { sting = true }), -- with the music's victory sting
		questRetry = s("electronicpingshort.wav", 0.5, 0.6),
		ui = s("button.wav", 0.35, 1), -- every button tap
		-- the newer robots (not juice actions; CombatClient plays them with their CombatFx visuals)
		aimLock = s("electronicpingshort.wav", 0.6, 2.6), -- a Sniper's laser locks on you
		grenadeBoom = s("action_jump_land.mp3", 0.9, 0.5, { range = 200, vary = 0.08 }), -- a Bomber's grenade
		rally = s("electronicpingshort.wav", 0.6, 0.6, { range = 160 }), -- a Captain's rally
		reveal = s("clickfast.wav", 0.7, 0.7, { range = 120 }), -- a Mimic shows itself
		-- WP6 robot combat depth: a Sneak Bot's rising whine as it coils for
		-- its lunge; the War-Frame's shield hum building before its block; a downed robot's wreck sparking and
		-- popping apart when its window ends
		lungeWind = s("swoosh.wav", 0.55, 1.9, { range = 110, vary = 0.06 }),
		braceWarn = s("electronicpingshort.wav", 0.7, 0.55, { range = 260 }),
		wreckSpark = s("clickfast.wav", 0.2, 2.4, { range = 50, vary = 0.2 }),
		wreckPop = s("action_jump_land.mp3", 0.45, 1.7, { range = 100, vary = 0.1 }),
		-- lore step 4: a famous fake's face cracks to show metal (with a white flash and a short hit-stop)
		unmask = s("clickfast.wav", 1, 0.45, { range = 200 }),
		-- lore step 3: Patch's radio blip as each of his lines starts
		-- (alive-world 2026-11-20: a walkie-talkie key-up: click, a squelch of static and a two-tone beep)
		radio = s("electronicpingshort.wav", 0.45, 3.4, { clip = "patchRadio" }),
		-- lore step 6: each guide's own blip as a line starts (Config.Story.guides.speakers[who].blip; Patch keeps
		-- radio above). Blips until real voice lines (nate: voices later)
		guideLodestar = s("clickfast.wav", 0.45, 0.75), -- a low, steady tap: in person
		guideCrane = s("button.wav", 0.5, 0.6), -- a mic thump: the stage and TV
		guideInsider = s("electronicpingshort.wav", 0.4, 2.2), -- a lower radio blip
		guideFake = s("clickfast.wav", 0.4, 1.6), -- the famous fakes and the copy
		-- alive-world (2026-11-20, the Ambient atlas: art/audio/build.py build_ambient; no built-in fallback, so a
		-- place without the atlas stays silent rather than looping a ping):
		-- the Ceremony crowd's applause and whistles while it cheers (Fx.PrologueFx), its gasp as the scan locks on
		-- the hero, the scanner drone's hum while it hovers, and the rain bed under the weather (Fx.WeatherFx: its
		-- volume follows the rain, up to Config.Weather.rain.sound)
		crowdCheer = s(nil, 0.42, 1, { loop = true }),
		crowdGasp = s(nil, 0.75, 1, { vary = 0.04 }),
		scanHum = s(nil, 0.3, 1, { loop = true }),
		rain = s(nil, 0, 1, { loop = true }),
	},

	-- every path's own sound layer (overhaul plan step 6), played with the slot's cast sound above (Juice.path):
	-- cast (skills), super, hit (your hits, once per use) and charge (a skill starts charging). Each is
	-- its element's own recording (clip "<Path>_<moment>"); the built-in fallbacks below play only without an atlas id.
	-- Weapon sounds by the weapon's look (list-combat 2026-11-20, checklist 202: "weapon sounds for each family (slash,
	-- clang, shot)"; Config.Fx.weaponLooks): the swing or shot on every move (basics too) and the hit, on top of
	-- the shared hit thud. Recorded clips from the atlases (blades cut, clubs clang, guns bang, bows twang); a
	-- new recording per look can replace a row's `clip` later.
	weapons = {
		fists = {
			cast = s("swoosh.wav", 0.22, 1.25, { clip = "Martial_cast", range = 70, vary = 0.1 }),
			hit = s("action_jump_land.mp3", 0.3, 1.1, { clip = "Martial_hit", range = 80, vary = 0.1 }),
		},
		edge = {
			cast = s("swoosh.wav", 0.26, 1.3, { clip = "Blade_cast", range = 80, vary = 0.1 }),
			hit = s("clickfast.wav", 0.32, 1.1, { clip = "Blade_hit", range = 90, vary = 0.1 }),
		},
		heavy = {
			cast = s("swoosh.wav", 0.3, 0.75, { clip = "Blade_cast", range = 100, vary = 0.06 }),
			hit = s("action_jump_land.mp3", 0.4, 0.7, { clip = "heavy", range = 120, vary = 0.08 }),
		},
		blunt = {
			cast = s("swoosh.wav", 0.26, 0.8, { clip = "basic", range = 90, vary = 0.08 }),
			hit = s("clickfast.wav", 0.38, 0.7, { clip = "clank", range = 110, vary = 0.1 }),
		},
		pole = {
			cast = s("swoosh.wav", 0.24, 1.0, { clip = "Blade_cast", range = 80, vary = 0.1 }),
			hit = s("action_jump_land.mp3", 0.3, 1.0, { clip = "Martial_hit", range = 90, vary = 0.1 }),
		},
		shield = {
			cast = s("swoosh.wav", 0.22, 0.85, { clip = "basic", range = 80, vary = 0.08 }),
			hit = s("clickfast.wav", 0.4, 0.8, { clip = "clank", range = 100, vary = 0.08 }),
		},
		shot = {
			cast = s("clickfast.wav", 0.32, 1.0, { clip = "Gunslinger_cast", range = 160, vary = 0.08 }),
			hit = s("clickfast.wav", 0.28, 1.2, { clip = "Gunslinger_hit", range = 90, vary = 0.1 }),
		},
		arrow = {
			cast = s("swoosh.wav", 0.24, 1.5, { clip = "Blade_cast", range = 110, vary = 0.1 }),
			hit = s("clickfast.wav", 0.28, 1.4, { clip = "Blade_hit", range = 80, vary = 0.1 }),
		},
		thrown = {
			cast = s("swoosh.wav", 0.24, 1.2, { clip = "Blade_cast", range = 100, vary = 0.1 }),
			hit = s("clickfast.wav", 0.32, 1.0, { clip = "clank", range = 90, vary = 0.1 }),
		},
		tether = {
			cast = s("swoosh.wav", 0.26, 1.6, { clip = "Blade_cast", range = 90, vary = 0.12 }),
			hit = s("action_jump_land.mp3", 0.3, 1.3, { clip = "Martial_hit", range = 80, vary = 0.1 }),
		},
		wind = {
			cast = s("swoosh.wav", 0.24, 0.9, { clip = "Spirit_cast", range = 90, vary = 0.1 }),
			hit = s("swoosh.wav", 0.26, 1.1, { clip = "Spirit_hit", range = 80, vary = 0.1 }),
		},
	},
	paths = {
		Volt = {
			cast = s("electronicpingshort.wav", 0.3, 2.4, { range = 100, vary = 0.08 }),
			super = s("electronicpingshort.wav", 0.6, 0.7, { range = 220 }),
			hit = s("electronicpingshort.wav", 0.25, 2.8, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.3, 3, { range = 60 }),
		},
		Frost = {
			cast = s("clickfast.wav", 0.45, 1.6, { range = 100, vary = 0.08 }),
			super = s("swoosh.wav", 0.8, 0.5, { range = 220 }),
			hit = s("clickfast.wav", 0.4, 2.2, { range = 80, vary = 0.1 }),
			charge = s("clickfast.wav", 0.3, 2.6, { range = 60 }),
		},
		Fire = {
			cast = s("swoosh.wav", 0.5, 0.75, { range = 100, vary = 0.08 }),
			super = s("action_jump_land.mp3", 0.9, 0.4, { range = 240 }),
			hit = s("swoosh.wav", 0.4, 0.6, { range = 80, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 1.4, { range = 60 }),
		},
		Earth = {
			cast = s("action_jump_land.mp3", 0.5, 0.65, { range = 100, vary = 0.08 }),
			super = s("action_jump_land.mp3", 0.9, 0.35, { range = 240 }),
			hit = s("action_jump_land.mp3", 0.4, 0.9, { range = 80, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.3, 0.6, { range = 60 }),
		},
		Tide = {
			cast = s("action_swim.mp3", 0.5, 1.1, { range = 100, vary = 0.08 }),
			super = s("impact_water.mp3", 1, 0.55, { range = 240 }),
			hit = s("impact_water.mp3", 0.45, 1.4, { range = 80, vary = 0.1 }),
			charge = s("action_swim.mp3", 0.3, 1.5, { range = 60 }),
		},
		Blade = {
			cast = s("swoosh.wav", 0.5, 1.9, { range = 100, vary = 0.08 }),
			super = s("swoosh.wav", 0.9, 0.9, { range = 220 }),
			hit = s("clickfast.wav", 0.4, 1.7, { range = 80, vary = 0.1 }),
			charge = s("clickfast.wav", 0.3, 1.2, { range = 60 }),
		},
		Gunslinger = {
			cast = s("clickfast.wav", 0.55, 0.8, { range = 120, vary = 0.08 }),
			super = s("action_jump_land.mp3", 0.9, 0.8, { range = 240 }),
			hit = s("electronicpingshort.wav", 0.3, 1.9, { range = 80, vary = 0.12 }),
			charge = s("button.wav", 0.4, 0.8, { range = 60 }),
		},
		Gadgeteer = {
			cast = s("button.wav", 0.45, 1.5, { range = 100, vary = 0.08 }),
			super = s("electronicpingshort.wav", 0.7, 0.5, { range = 220 }),
			hit = s("button.wav", 0.35, 2, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.25, 1.3, { range = 60 }),
		},
		Shadow = {
			cast = s("swoosh.wav", 0.45, 1.45, { range = 90, vary = 0.08 }),
			super = s("action_falling.mp3", 0.8, 0.35, { range = 220 }),
			hit = s("swoosh.wav", 0.35, 2.2, { range = 70, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.25, 0.8, { range = 60 }),
		},
		Titan = {
			cast = s("action_jump_land.mp3", 0.55, 0.8, { range = 120, vary = 0.08 }),
			super = s("action_jump_land.mp3", 1, 0.3, { range = 260 }),
			hit = s("action_jump_land.mp3", 0.5, 1.1, { range = 90, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.3, 0.8, { range = 60 }),
		},
		Martial = {
			cast = s("swoosh.wav", 0.5, 1.3, { range = 100, vary = 0.08 }),
			super = s("action_falling.mp3", 0.9, 0.6, { range = 240 }),
			hit = s("action_jump_land.mp3", 0.4, 1.6, { range = 80, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 1.8, { range = 60 }),
		},
		Juggernaut = {
			cast = s("action_jump_land.mp3", 0.55, 0.55, { range = 120, vary = 0.08 }),
			super = s("action_jump_land.mp3", 1, 0.25, { range = 260 }),
			hit = s("clickfast.wav", 0.45, 0.7, { range = 90, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 0.5, { range = 60 }),
		},
		Colossus = {
			cast = s("action_jump_land.mp3", 0.6, 0.45, { range = 140, vary = 0.08 }),
			super = s("action_jump_land.mp3", 1, 0.2, { range = 300 }),
			hit = s("action_jump_land.mp3", 0.5, 0.75, { range = 100, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.35, 0.45, { range = 60 }),
		},
		Pulse = {
			cast = s("action_falling.mp3", 0.45, 0.6, { range = 100, vary = 0.08 }),
			super = s("action_falling.mp3", 0.9, 0.25, { range = 240 }),
			hit = s("electronicpingshort.wav", 0.3, 0.6, { range = 80, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 1.1, { range = 60 }),
		},
		Mind = {
			cast = s("electronicpingshort.wav", 0.35, 0.9, { range = 100, vary = 0.08 }),
			super = s("action_falling.mp3", 0.8, 0.45, { range = 220 }),
			hit = s("electronicpingshort.wav", 0.3, 1.15, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.25, 0.75, { range = 60 }),
		},
		Spirit = {
			cast = s("action_get_up.mp3", 0.45, 1.3, { range = 100, vary = 0.08 }),
			super = s("action_get_up.mp3", 0.9, 0.6, { range = 240 }),
			hit = s("swoosh.wav", 0.35, 1.6, { range = 80, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.3, 1.6, { range = 60 }),
		},
		Light = {
			cast = s("electronicpingshort.wav", 0.35, 1.7, { range = 100, vary = 0.08 }),
			super = s("electronicpingshort.wav", 0.8, 1.2, { range = 260 }),
			hit = s("electronicpingshort.wav", 0.3, 2.4, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.25, 2, { range = 60 }),
		},
	},

	-- per-tier gear chimes (pitch rises with the tier; Legendary plays a second chime 0.25 s later)
	tierPitch = { 1.2, 1.4, 1.6, 1.85, 2.1 },

	-- the three loops (spec: city patrol day and night, boss theme, victory sting): our own music (art/audio/music.py,
	-- the CC0 Meta piano and synth), loops a whole number of bars long
	music = {
		patrolDay = { asset = 0, volume = 0.35, clip = "patrolDay" },
		patrolNight = { asset = 0, volume = 0.32, clip = "patrolNight" },
		boss = { asset = 0, volume = 0.45, clip = "boss" },
		victory = { asset = 0, volume = 0.5, sting = true, clip = "victory" },
		-- the context loops (first-30, nate 2026-11-20: "Music should change according to context"; our own, from
		-- art/audio/music.py in the Music atlas): Shared.MusicPlan picks one by what is going on
		combat = { asset = 0, volume = 0.4, clip = "combat" },
		mission = { asset = 0, volume = 0.34, clip = "mission" },
		chase = { asset = 0, volume = 0.42, clip = "chase" },
		ceremony = { asset = 0, volume = 0.36, clip = "ceremony" },
		deep = { asset = 0, volume = 0.36, clip = "deep" },
		hq = { asset = 0, volume = 0.3, clip = "hq" },
		fade = 1.5, -- seconds to crossfade
		duck = 0.6, -- music volume while the boss siren or a voice line plays (ducks 40%)
		bossRange = 600, -- the boss theme plays within this many studs of a live boss
	},

	-- which loop plays when (Shared.MusicPlan; first-30, nate 2026-11-20: "Music should change according to context")
	musicContext = {
		menu = "hq", -- the creator and the main menu
		-- the prologue's beats: the Ceremony's proud fanfare, then the chase from the Spark to the subway, the
		-- subway fight, the rescue's tension and the fanfare again under the title card
		opening = {
			ceremony = "ceremony",
			scan = "ceremony",
			run = "chase",
			spark = "chase",
			leap = "chase",
			chase = "chase",
			suit = "chase",
			descend = "chase",
			tunnel = "chase",
			fight = "combat",
			swarm = "combat",
			rescue = "mission",
			title = "ceremony",
		},
		scene = "mission", -- a cutscene in the city or a mission
		hq = "hq",
		deep = "deep",
		mission = "mission",
		combat = "combat",
		combatHold = 8, -- seconds the fight loop stays after the last hit dealt or taken
		combatNear = 20, -- or this long while a robot is within enemyRange
		enemyRange = 45,
	},

	-- voice packs: 6 lines each (Config.Shop.voiceSounds holds the ids); which event plays which line
	voice = {
		lines = { "super", "rescue", "incidentClear", "levelUp", "downed", "emote" },
		gap = 2.5, -- at most one line every 2.5 s per hero
		range = 90, -- other heroes' lines are heard this close
	},

	haptics = {
		land = 0.35,
		super = 0.6,
		clash = 0.8,
		downed = 0.5,
		bossPhase = 0.5,
		collapse = 0.4,
		shatter = 0.6,
		perfectBlock = 0.4,
		throwLand = 0.45,
	},

	pool = 24, -- 3D sounds alive at once (the oldest is reused)

	-- the mix (AudioController): sub-groups inside Effects by row kind, a gentle bus compressor so big stacks never
	-- clip, the side-chain duck under big booms, how near a 3D sound is full volume, and a repeat guard
	mix = {
		groups = { "Combat", "World", "Ui", "Ambience" },
		compressor = { threshold = -14, ratio = 3, attack = 0.005, release = 0.15, makeup = 2 },
		-- big moments lower the city bed and the music for `time` seconds (to `to` of their level)
		duck = {
			to = 0.45,
			time = 0.9,
			ids = {
				"super",
				"collapse",
				"clash",
				"bossPhase",
				"sonicBoom",
				"pound",
				"grenadeBoom",
				"wallSmash",
				"throwLand",
			},
		},
		near = { default = 10, big = 28, bigRange = 200 }, -- RollOffMinDistance: rows with range >= bigRange are big
		gap = 0.035, -- the same row starts at most once in this many seconds (a hail of hits stays a hail, not a buzz)
		-- which group a row plays in: juice ids listed here, else Combat for Hits clips, World for World, Ui for Ui
		ui = {
			"ui",
			"skillRank",
			"levelUp",
			"gearDrop",
			"purchase",
			"photo",
			"contractDone",
			"badgeEarned",
			"collectFind",
		},
	},
	-- the city's ambient bed (AudioController.beds): the district's loop where the camera is (Config.Life.sounds.bed),
	-- the rooftop wind mixed in by height, silent underwater; beds crossfade over `fade` seconds
	bed = { fade = 3, roofLow = 60, roofHigh = 260, every = 1, maxY = 1200 }, -- maxY: the pockets and HQs float above
	-- movement sounds (Fx.MoveAudio): the sonic boom when speed first passes boomSpeed (then not again for
	-- `boomGap` s or until below `boomReset`); the Super Speed rush from runFrom to runFull studs/s
	move = {
		boomSpeed = 95,
		boomReset = 70,
		boomGap = 4,
		runFrom = 40,
		runFull = 100,
		runVolume = 0.45,
		boomShake = { 0.25, 0.5 },
	},
}

-- each row's recorded clip is named after its key unless it says otherwise (the paths: "<Path>_<moment>")
for key, row in Audio.sounds do
	row.clip = row.clip or key
end
for key, row in Audio.impact do
	row.clip = row.clip or key
end
for path, rows in Audio.paths do
	for moment, row in rows do
		row.clip = row.clip or (path .. "_" .. moment)
	end
end

return Audio
