-- Remembers: "The city remembers" (nate's lore, build plan step 12). Vigil Trust (heroes) and Syndicate Fear
-- (villains) each open their own cosmetic rewards by tier; everything here is looks only, nothing sold or
-- unlocked changes a stat. Pure data; Shared.RepTiers reads it.
-- * Tiers: the 5 reputation ranks of Config.Story.rep.ranks (100, 300, 600, 1,000 and 1,500 points), read on the
--   hero's own side's track (Vigil Trust for heroes, Syndicate Fear for villains). One ladder, so the Journal's
--   RANK and the tier are the same number.
-- * Each tier opens: 2 side styles at Gizmo's bench (bought with earned Credits, never Robux; rows in
--   Config.Gear.styles with tier "Rep" and rep = { track, tier }), a title (the H7 title list) and a hideout
--   upgrade (the HQ cell's dressing, Shared.RepTiers.dressing).
-- * Earn: own-side reputation from the repeatable activities too (Act 1's missions and choices already pay it),
--   paced so rank 3 comes within a few hours past Act 1 and rank 5 is a long-term goal (pace below; tested).
return {
	tracks = { hero = "vigil", villain = "syndicate" },

	-- Own-side reputation per activity (on top of Act 1's missions and choices; StoryService.addRep "side")
	earn = {
		incident = 1, -- each hero who took part in a cleared incident
		contract = 2, -- a finished contract
		event = 2, -- taking part in a world event that cleared
		sideEvent = 6, -- taking part in a side-vs-side event (either side, win or lose)
		sideWin = 6, -- more for the winning side
		sideStep = 2, -- a side quest chain step
		sideFinale = 10, -- a chain's finale step
	},
	-- The pacing model: what a typical hero does in an hour of open-world play (Config.Economy.sim: 6 incidents
	-- and 1.5 contracts a 30 minutes; a hero joins about 2 events an hour and the side events run about once an
	-- hour a server). Shared.RepTiers.pace turns it into hours to each tier after Act 1.
	pace = { incidents = 12, contracts = 3, events = 2, sideEvents = 0.75, winShare = 0.5, sideSteps = 0.5 },
	-- what the pacing test holds it to: hours of play after Act 1 (with its fewest side points)
	paceGoal = { tier3 = { 0, 12 }, tier5 = { 30, 80 } },

	-- Titles (the H7 title list, Shared.BadgeRules.titles): id titleBase + track index x 10 + tier, kept for
	-- as long as the points are there (reputation never goes down)
	titleBase = 4000,
	titles = {
		vigil = { "Friendly Face", "Trusted Name", "City Guardian", "Vigil Champion", "Heart of the City" },
		syndicate = { "Street Menace", "Feared Name", "Shadow Boss", "Syndicate Kingpin", "Boss of the City" },
	},

	-- The hideout upgrade each tier opens (the HQ cell's dressing; same stations, same budgets).
	-- PLACEHOLDER ART: every piece is a part-built box, cylinder or ball until the art pass.
	hideout = {
		vigil = {
			"Thank-You Wall",
			"Patch's Hacking Rig",
			"Hero Relic Display",
			"Relic Spotlight",
			"The City's Thanks",
		},
		syndicate = {
			"Loot Vault",
			"Trophy Screen",
			"Captured Crane Robot",
			"Vault Expansion",
			"Kingpin's Spotlight",
		},
		notesPerTier = 6, -- thank-you notes on the Vigil's wall per tier (fixed icons, never text)
		-- the notes' fixed icons: { colour, shape } (Ball, Block or Wedge)
		icons = {
			{ { 235, 70, 90 }, "Ball" }, -- a heart
			{ { 255, 205, 60 }, "Wedge" }, -- a star
			{ { 90, 170, 255 }, "Block" }, -- a cape
			{ { 110, 220, 140 }, "Ball" }, -- a smile
			{ { 255, 140, 60 }, "Wedge" }, -- a sun
		},
	},

	-- Citizens react to a hero by side and tier (on the device, CitizenRenderer): the Vigil get cheers, the
	-- Syndicate get flinches. Light touch: only citizens walking or standing (never fleeing) near enough.
	citizens = {
		minTier = 2, -- from this tier citizens notice you
		range = 24, -- studs
		highTier = 4, -- from this tier they notice you from further
		highRange = 40,
		every = 0.25, -- seconds between scans for heroes nearby
	},

	-- The news ticker and Patch's radio name heroes at this tier and up (their safe hero names, never text):
	-- once when they reach it and once a session when they join
	mention = { tier = 4, joinDelay = 20 },

	-- Patch's radio lines (fixed text; %s is a safe hero name). self[tier]: your own tier-up. about: a
	-- high-tier hero of `same` or the `other` side in the server (once a session each). Read by side.
	radio = {
		self = {
			hero = {
				"The first thank-you notes are up on the Safehouse wall, %s. People noticed you.",
				"Word on the street: %s is someone you can trust. I set you up a hacking rig.",
				"We found an old hero's relics in the rubble, %s. They're in the Safehouse now. You earned it.",
				"Half the city knows %s by name. Crane hates that. I love it.",
				"%s, you're the heart of this city now. Don't let it go to your head.",
			},
			villain = {
				"Citizens cross the street when you pass, %s. Good start. Check the Foundry vault.",
				"%s, the Foundry's got a proper trophy screen now. Fill it.",
				"We hung a captured Crane robot in the Foundry, %s. Your idea of decor, I assume.",
				"Shopkeepers lock up when %s walks by. The vault got bigger to match.",
				"%s, the whole city whispers your name. That's kingpin stuff.",
			},
		},
		about = {
			hero = {
				same = "Good news: %s is out tonight. One of the most trusted heroes in the city.",
				other = "Heads up: %s is in town. The Syndicate's most feared. Stay sharp.",
			},
			villain = {
				same = "%s is in the city tonight. The Syndicate's finest. Make them proud.",
				other = "Careful: %s is out tonight. The Vigil's golden child.",
			},
		},
	},
}
