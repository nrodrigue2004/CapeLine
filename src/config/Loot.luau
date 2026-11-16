-- Drops (spec: Drops, Server rolled, earned only). Odds are shown to players in the Loot Info tab even
-- though no Robux is involved. Tier odds are percentages. Every number is a starting value to tune.
return {
	-- source order is the wire and Dev panel order
	order = {
		"incident",
		"contract",
		"event",
		"story",
		"storyFinale",
		"bossParticipant",
		"bossContributor",
		"bossMvp",
		"deepCache",
	},
	sources = {
		incident = {
			name = "Incident clear",
			chance = 0.12,
			pieces = 1,
			odds = { Common = 70, Uncommon = 28, Rare = 2 },
		},
		contract = {
			name = "Radiant contract",
			pieces = 1,
			odds = { Common = 40, Uncommon = 45, Rare = 14, Epic = 1 },
		},
		event = { name = "Random event", pieces = 1, odds = { Uncommon = 50, Rare = 40, Epic = 10 } },
		story = { name = "Story mission first clear", pieces = 1, fixed = { "Rare" } },
		storyFinale = { name = "Story finale first clear", pieces = 2, fixed = { "Rare", "Epic" } },
		-- world boss (M6): participant = at least 10% of the median contribution
		bossParticipant = {
			name = "World boss participant",
			pieces = 1,
			odds = { Rare = 70, Epic = 30 },
			boss = true,
		},
		-- contributor = top 50%: two pieces, each Epic at 35%, otherwise Rare
		bossContributor = {
			name = "World boss top 50%",
			pieces = 2,
			odds = { Rare = 65, Epic = 35 },
			boss = true,
		},
		-- MVP = top 3: one Epic guaranteed, and a Legendary roll at 8%
		bossMvp = {
			name = "World boss MVP",
			pieces = 1,
			fixed = { "Epic" },
			legendary = 0.08,
			boss = true,
			mvp = true,
		},
		-- a sunken cargo cache underwater (Config.Deep): sometimes a piece
		deepCache = {
			name = "Sunken cache",
			chance = 0.35,
			pieces = 1,
			odds = { Common = 45, Uncommon = 42, Rare = 12, Epic = 1 },
		},
	},
	-- Pity (counters saved per profile): the 5th boss participation in a row with no Epic gives an Epic;
	-- the 15th MVP Legendary roll in a row without one gives a Legendary.
	pity = { epic = 5, legendary = 15 },
	-- when a tier is above the hero's level gate (Epic 20, Legendary 30) it drops one tier lower
	-- set and perk chances for the tiers that carry them
	setChance = 1.0, -- every Epic head, chest, hands or feet piece belongs to a set
	gadgetChance = 0.06, -- share of drops that are gadgets (the 8th slot)
}
