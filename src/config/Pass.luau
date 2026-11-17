-- Pass: the Hero Pass (spec: Hero MMO features > The Hero Pass; H8). Pure data, tuned in the playtest.
-- An 8 week season of 40 tiers on the same Monday weeks as the world seed and the weekly episodes.
-- * Free track: a reward on every tier (Credits, Lumen Dust or a cosmetic; 15 cosmetics a season).
-- * Paid track: one Robux product a season (Config.Shop.products.heroPass, 499 Robux, id 0 until nate makes
--   it: Launch Checklist) with 30 more cosmetics. Every reward is shown before buying, nothing is random,
--   and nothing on the paid track is Credits, Dust or anything with a stat. No tier skips (nate's call 4).
-- * Pass XP from everything (xp below), never doubled by the 2x pass; the first win of each day adds more.
-- * After a season: unclaimed paid rewards stay locked; season cosmetics never come back as paid shop items;
--   claimed titles, trims, emotes, tints, styles, props and pieces stay forever.
-- Reward kinds: credits, dust, title (titles[n]), trim (trims[n]), emote (Config.Shop.emotes bit), tint
-- (Config.Shop.tints n), travel (Config.TravelStyles id), piece (a Config.Creator piece name), prop
-- (Config.Hq.props bit). Names are fixed text.
local function r(kind: string, v: any): { [string]: any }
	return { kind = kind, v = v }
end

return {
	tiers = 40,
	weeks = 8,
	xpPerTier = 1000,
	startWeek = 2970, -- the Monday week season 1 starts (Monday 2026-11-30); nate sets it for launch
	titleBase = 3000, -- a pass title's id in the title list (Config.Badges ids sit below)
	trimBase = 100, -- a pass trim's value in a hero's mmo.trim (badge accolade groups sit below)
	dailyKinds = { incident = true, contract = true, mission = true, taskForce = true, boss = true },
	-- Pass XP per action (the episode's own steps pay xp in Config.Episodes)
	xp = {
		incident = 60,
		contract = 120,
		mission = 250,
		taskForce = 600,
		boss = 150,
		badge = 75,
		find = 25,
		contestEnter = 100,
		contestPodium = 250,
		dailyFirst = 400, -- the first win of the UTC day (an incident, contract, mission, task force or boss)
	},
	-- titles and plate trims the pass gives (ids are their place here; only add at the end)
	titles = {
		"Season One Rookie",
		"Weekly Regular",
		"Comic Collector",
		"Plaza Star",
		"City Regular",
		"Night Shift",
		"Season One Veteran",
		"Golden Pass",
		"Cover Star",
		"Headliner",
		"Spotlight Hog",
		"Main Event",
		"Limited Edition",
		"First Printing",
		"Season One Legend",
	},
	trims = {
		{ id = "passGold", name = "Gold Foil Trim", color = { 255, 205, 60 } },
		{ id = "passHolo", name = "Holo Trim", color = { 170, 240, 255 } },
		{ id = "passNeon", name = "Neon Trim", color = { 255, 90, 200 } },
		{ id = "passComic", name = "Halftone Trim", color = { 255, 120, 60 } },
	},
	seasons = {
		{
			name = "Season One: Opening Night",
			free = {
				r("credits", 500),
				r("title", 1),
				r("dust", 40),
				r("credits", 600),
				r("travel", 5), -- Ghost Fire (flight)
				r("dust", 50),
				r("credits", 700),
				r("title", 2),
				r("dust", 60),
				r("emote", 18), -- Comic Pose
				r("credits", 800),
				r("dust", 70),
				r("travel", 11), -- Ghost Fire Run (speed)
				r("credits", 900),
				r("title", 3),
				r("dust", 80),
				r("credits", 1000),
				r("tint", 11), -- Sky Blue
				r("dust", 90),
				r("travel", 17), -- Ghost Fire Leap (leap)
				r("credits", 1100),
				r("title", 4),
				r("dust", 100),
				r("credits", 1200),
				r("travel", 23), -- Ghost Fire Flip (acrobat)
				r("dust", 110),
				r("credits", 1300),
				r("title", 5),
				r("dust", 120),
				r("travel", 29), -- Ghost Fire Line (swing)
				r("credits", 1400),
				r("dust", 130),
				r("prop", 19), -- Season One Poster
				r("credits", 1500),
				r("title", 6),
				r("dust", 140),
				r("credits", 1600),
				r("dust", 150),
				r("credits", 1800),
				r("title", 7), -- Season One Veteran
			},
			-- the paid track: a cosmetic on 30 tiers (tiers 1, 5, 9, ... 37 have none: "about 30" in the spec)
			paid = {
				false,
				r("title", 8),
				r("tint", 12), -- Holo Gold
				r("emote", 19), -- Spotlight Spin
				false,
				r("travel", 6), -- Prism (flight)
				r("trim", 1),
				r("piece", "Opening Night Boots"),
				false,
				r("title", 9),
				r("travel", 12), -- Prism Streak (speed)
				r("prop", 20), -- Golden Ticket Booth
				false,
				r("tint", 13), -- Neon Night
				r("piece", "Opening Night Mask"),
				r("title", 10),
				false,
				r("travel", 18), -- Prism Bound (leap)
				r("trim", 2),
				r("emote", 25), -- Spotlight Landing (a landing pose)
				false,
				r("title", 11),
				r("piece", "Opening Night Cape"),
				r("travel", 24), -- Prism Twist (acrobat)
				false,
				r("tint", 14), -- Halftone Red
				r("trim", 3),
				r("title", 12),
				false,
				r("travel", 30), -- Prism Line (swing)
				r("prop", 21), -- Spotlight Rig
				r("title", 13),
				false,
				r("tint", 15), -- Starlight
				r("trim", 4),
				r("title", 14),
				false,
				r("prop", 22), -- Season One Statue
				r("title", 15),
				r("piece", "Opening Night Suit"), -- the costume set's centrepiece
			},
		},
	},
}
