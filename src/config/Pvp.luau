-- PvP, death and anti-abuse (spec: PvP, death and anti-abuse rules; Fame and Infamy; Anti-exploit checks).
-- PvE is the default. The flag is server-owned; every rule here is read by PvpRules and the M8 services.
-- (tune)
return {
	minLevel = 10, -- the flag button appears and the Crater can force PvP from this level
	levelCap = 40, -- PvP uses the level capped here

	flag = {
		setEvery = 5, -- the client can ask at most once per 5 s
		offAfter = 60, -- turning off needs 60 s with no PvP damage dealt or taken
		combat = 15, -- "in PvP combat" for support and combat logging: PvP damage this recent
	},

	-- Safe areas: HQ and safehouses (radius 40, SafehouseService) and mission pockets
	spawnProtect = 5, -- seconds after a respawn; ended early by attacking, never reused

	crater = {
		id = "CometCrater", -- the landmark (Config.World.landmarks)
		warn = 5, -- seconds of warning ring at the border before PvP is forced
		leaveOut = 24, -- Leave places the hero this far outside the border
		renownMult = 1.5, -- +50% Renown while inside
	},

	-- Stat compression: effective = baseline x (1 + bonus x clamp(total / baseline - 1, 0, 1)).
	-- Power and Health have a level baseline. Focus, Precision and Resolve have none (their baseline is 0),
	-- so their gear value counts at minorScale in PvP instead (Decisions.md, 2026-11-16).
	compressBonus = 0.10,
	minorScale = 0.25,
	superMult = 0.6, -- supers deal 60% to players
	setMult = 0.5, -- Epic set damage bonuses count half (they follow the Legendary perk table)

	-- Stuns and roots: each repeat within 8 s is halved, then 3 s immune (Status, pvp = true)
	dr = { window = 8, immune = 3 },

	knock = { maxDistance = 30, upSpeed = 40 }, -- knockback, pull and knockup on players (an impulse)

	-- Defeat and death
	downed = {
		time = 10, -- PvE: Downed this long, then Defeated
		reviveTime = 3, -- an ally holds this long next to the Downed hero
		reviveWarden = 1.5, -- Warden Controllers (the Controller class) revive faster
		reviveRange = 8,
		reviveHealth = 0.35, -- back up with this share of health
		reviveRenown = 40, -- the helper's Renown pop
		giveUp = 2, -- Give Up respawns this long after the tap
		crawlSpeed = 4, -- studs a second while Downed
		pingLife = 8, -- a Help marker shows this long on allies' screens
		pingRange = 600, -- allies this close see the Help marker
	},
	respawn = { pve = 5, pvp = 5 },

	-- What a PvP defeat costs: 5% of on-hand Credits above 500, at most 300, to the winner (reward rules apply)
	loss = { buffer = 500, share = 0.05, max = 300 },

	-- Rewards, small on purpose: Fame or Infamy and Credits, no gear
	reward = { fame = 15, credits = { 40, 2 } }, -- Credits 40 + 2 x target level

	-- Anti-farming
	farm = {
		sameTarget = 2, -- wins on one target that pay, per 30 minutes
		sameWindow = 1800,
		levelGap = 10, -- no rewards when the target is this many levels below
		sameSide = 0.5, -- hero beats hero, villain beats villain
		boss = 0.5, -- PvP inside a world boss fight
		altWins = 3, -- A beat B 3 times and B beat A 3 times ...
		altWindow = 3600, -- ... within 60 minutes: zero both ways, logged for review
	},
	combatLog = { window = 15, linger = 10 }, -- leaving within 15 s of PvP damage: 10 s in the world, a defeat

	-- Rings: blue League, red Syndicate (heroes and villains)
	ring = { hero = { 70, 140, 255 }, villain = { 235, 60, 60 } },

	-- Fame (heroes) and Infamy (villains): one bar, the same numbers (spec: Fame and Infamy)
	fame = {
		incident = 5,
		rescue = 2,
		rescueVillain = 3,
		contract = 10,
		mission = 40,
		bossParticipant = 20,
		bossContributor = 30,
		bossMvp = 50,
		pvp = 15,
		-- Rank thresholds and rewards. Reward kinds match the unlock tables (titles are M9's title wheel).
		ranks = {
			{ at = 0, reward = { title = "Rookie" } },
			{ at = 100, reward = { title = "Local Name", emote = "Salute" } },
			{ at = 300, reward = { style = "FameRank3" } },
			{ at = 700, reward = { title = "Headliner" } },
			{ at = 1300, reward = { frame = "FameFrame", emote = "Bow" } },
			{ at = 2200, reward = { style = "FameRank6" } },
			{ at = 3500, reward = { title = "Big Deal" } },
			{ at = 5500, reward = { emote = "SuperLanding" } }, -- a landing pose
			{ at = 8500, reward = { style = "FameRank9" } },
			{ at = 13000, reward = { title = "Living Legend", trim = "GoldTrim" } },
		},
	},

	-- Reports and mutes on every name plate. Reasons are preset ids (no typed text).
	report = {
		reasons = { "Cheating", "Griefing", "Bad name or look", "Other" },
		perTarget = 600, -- one report per reporter per target every 10 minutes
		flagAt = 3, -- 3 reports from 3 different accounts ...
		window = 600, -- ... within 10 minutes flags the account for review
	},

	-- Strikes (spec: Anti-exploit checks): 3 in 10 minutes kick with a generic message; repeated kicks
	-- go to the review queue. There is no automatic ban.
	strikes = {
		kickAt = 3,
		window = 600,
		netWeight = 10, -- dropped remote calls: every 10 in a row of a minute count one strike
		reviewAfterKicks = 2, -- kicks on one account (saved) before it lands in the review queue
	},
}
