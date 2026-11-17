-- Nemesis (spec: Hero MMO features > Nemesis; H5). Pure data, tuned in the playtest and the economy sim.
-- From level 8 every hero has one robot villain made for them (a villain hero gets a League hunter robot),
-- built from their user id and rank so it is the same on every server. Rules: Shared.NemesisMath; the
-- server: NemesisService; the client: NemesisHud (WANTED poster, taunt panel) and NemesisFx (its look).
-- Standalone from the main story (nate 2026-11-17): no story characters; names and taunts are fixed lists.
return {
	minLevel = 8,
	sessionMin = 15 * 60, -- seconds into a session before it can show up
	gap = 30 * 60, -- at most once per this much play
	rankUpWait = 24 * 3600, -- after a Showdown win, a new one (one rank tougher) shows up a day later
	maxRank = 5,
	maxTraits = 5,
	escapeAt = 0.3, -- in encounters 1 to 3 it escapes at 30% health in a teleport flash
	escapesUntil = 3, -- encounters this many or fewer end in an escape
	intelForShowdown = 3, -- each escape drops 1 Intel; 3 show its weak point and open the Showdown
	weakMult = 2, -- the weak point (its back) takes double damage once it is shown
	-- 12x a Spark Trooper's health at your level, 18x in a squad, hitting like a Brute Bot (its body):
	-- the multipliers below are on the Brute Bot's own health (600 vs the Trooper's 100)
	body = "BruteBot",
	hpMult = { solo = 2, squad = 3 },
	rankHp = 0.15, -- +15% health per rank above 1
	payMult = 3, -- pays 3x an incident (each player at their own level)
	ambush = { robots = 6, kinds = { "SparkDrone", "BurglarBot", "SneakBot" }, ring = 18, nemesisAfter = 6 },
	near = 60, -- squadmates this close help and get paid
	leaveAfter = 150, -- seconds: an encounter nobody finishes ends with the nemesis teleporting away
	checkEvery = 5, -- seconds between checks whether it shows up
	appearChance = 0.05, -- per check once it may (about 1.7 minutes on average)
	-- who it is: two word lists (no free text), a build, a colour set, a head, a cape or not, a voice pitch
	first = {
		"Rivet",
		"Major",
		"Cobalt",
		"Baron",
		"Doctor",
		"Iron",
		"Vector",
		"Static",
		"Chrome",
		"Gauge",
		"Lady",
		"Count",
		"Sergeant",
		"Volt",
		"Torque",
		"Ratchet",
		"Neon",
		"Captain",
		"Ember",
		"Slate",
	},
	second = {
		"Hex",
		"Static",
		"Widow",
		"Gear",
		"Fang",
		"Circuit",
		"Spanner",
		"Glitch",
		"Piston",
		"Siren",
		"Sprocket",
		"Rust",
		"Wrench",
		"Fuse",
		"Coil",
		"Magnet",
		"Socket",
		"Bolt",
		"Clamp",
		"Drill",
	},
	-- a villain hero's nemesis is a League hunter robot: same lists, this word in front of the title
	hunterWord = "Hunter",
	builds = { "lanky", "bulky", "squat", "spiked" },
	colors = {
		{ { 200, 60, 60 }, { 40, 40, 48 } },
		{ { 70, 120, 220 }, { 230, 230, 240 } },
		{ { 120, 200, 80 }, { 30, 50, 30 } },
		{ { 230, 170, 40 }, { 60, 40, 20 } },
		{ { 170, 80, 200 }, { 20, 20, 30 } },
		{ { 60, 200, 200 }, { 40, 60, 80 } },
	},
	heads = { "visor", "dome", "horned", "cyclops" },
	capeChance = 0.5,
	pitch = { 0.7, 1.3 },
	-- the signature attack (one of 6): a telegraphed area every `every` seconds that lands `delay` later,
	-- hitting for `dmg` x its Brute Bot hit; droneSwarm also calls 2 Spark Troopers (at most 4 alive)
	signatures = {
		droneSwarm = {
			every = 12,
			delay = 1.2,
			dmg = 0.6,
			shape = "ring",
			radius = 8,
			drones = 2,
			maxDrones = 4,
		},
		chainHook = { every = 9, delay = 0.9, dmg = 0.9, shape = "line", length = 40, width = 4, pull = true },
		mineField = {
			every = 11,
			delay = 1.6,
			dmg = 1.1,
			shape = "mines",
			count = 4,
			radius = 5,
			spread = 16,
		},
		groundSlam = { every = 8, delay = 1.2, dmg = 1.4, shape = "nova", radius = 14 },
		sniperLine = { every = 10, delay = 1.0, dmg = 1.6, shape = "line", length = 80, width = 3 },
		shieldWall = {
			every = 14,
			delay = 0.8,
			dmg = 0.8,
			shape = "cone",
			radius = 16,
			cone = 100,
			block = 3,
		},
	},
	signatureOrder = { "droneSwarm", "chainHook", "mineField", "groundSlam", "sniperLine", "shieldWall" },
	-- traits it gains (each shows on its body): bit order is the list order
	traits = {
		{ id = "plates", name = "Armour Plates", taken = 0.75 }, -- takes 25% less
		{ id = "second", name = "Second Signature" }, -- a second signature attack
		{ id = "healDrone", name = "Heal Drone", heal = 0.015 }, -- heals 1.5% health a second in a fight
		{ id = "cloak", name = "Cloak", every = 15, time = 3, taken = 0.5 }, -- flickers out: half damage
		{ id = "summon", name = "Summon", every = 20, n = 2 }, -- calls 2 robots of its kind
	},
	-- taunts: fixed lines filled with your hero name ({hero}); drafts the lore thread may rewrite, no story
	-- characters (standalone from the main story, nate 2026-11-17).
	-- PLACEHOLDER CONTENT: lore thread to fill (the voice of the taunts, gloats and escapes)
	taunts = {
		"{hero}! I have been looking for you.",
		"Nice cape, {hero}. It will look better on my wall.",
		"Did you miss me, {hero}?",
		"I rebuilt myself just for you, {hero}.",
		"Run along, {hero}. No? Good.",
		"Every bolt in me hums your name, {hero}.",
		"Today is the day, {hero}.",
		"You again, {hero}? Perfect.",
		"I counted the seconds, {hero}.",
		"Smile, {hero}. You are on my scanner.",
		"Let us dance, {hero}.",
		"Your city is noisy, {hero}. Let me fix that.",
		"I studied your moves, {hero}.",
		"Try to keep up, {hero}.",
		"Upgrades, {hero}. You should try some.",
		"Hello, old friend {hero}.",
		"This time you will not be so lucky, {hero}.",
		"I brought friends, {hero}.",
		"Ready for round two, {hero}?",
		"My circuits are warm, {hero}. Are you?",
		"Look up, {hero}.",
		"Surprise, {hero}!",
		"I have a present for you, {hero}.",
		"No more running, {hero}.",
		"You dented me last time, {hero}. I kept the dent.",
		"Another day, another fight, {hero}.",
		"Your fan club is here, {hero}.",
		"I fixed my weak spot, {hero}. Mostly.",
		"Hold still, {hero}.",
		"Is that all, {hero}?",
	},
	gloats = {
		"Too easy, {hero}.",
		"I will remember that, {hero}.",
		"Stay down, {hero}.",
		"Better luck next time, {hero}.",
		"I am getting stronger, {hero}.",
	},
	escapes = {
		"This is not over, {hero}!",
		"Next time, {hero}!",
		"I will be back, {hero}. Stronger.",
		"You win this round, {hero}.",
		"Remember my name, {hero}!",
	},
	-- the Showdown: a pocket mission (sidekicking applies), the nemesis with its traits, its robots, a
	-- weak-point phase; paid at your level plus a Rare or better roll, its Nemesis Core, its head for your HQ
	-- wall and the title "Bane of" its name
	showdown = {
		num = 150, -- MissionState num for a Showdown (after the task forces)
		layout = "arena",
		minutes = 10,
		gearTier = "Rare",
		epicChance = 0.2, -- "Rare or better": 1 in 5 is Epic
		titleWord = "Bane of",
		adds = 4,
	},
	-- the comic panel taunt before it drops in
	panelTime = 3.5,
}
