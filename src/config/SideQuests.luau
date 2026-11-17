-- SideQuests (nate's lore, build plan step 10: the side quest framework). Pure data; Shared.SideQuestPlan holds
-- the rules and SideQuestService runs them. nate's rules: side quests are real story quests, not chores, in three
-- layers: district story chains (6 to 10 quests with a mini villain finale), character quest lines and an origin
-- quest line per origin (Lab, Alien, Magic, Tech, Training); mostly standalone from the main story; each side
-- gets its own flavour (Vigil: rescues and exposing fakes; Syndicate: heists and sabotage).
--
-- A chain: id (never change), bit (its place in the save's done set, 1 to 127; never reuse or move), name,
-- layer, giver (a row in givers), unlock rules, villain (the finale's name card), reward, lines and 5 to 10
-- steps. The real chains come in step 11, one at a time; `dev` chains are offered only in Studio with
-- Config.Dev.sideQuestSample on (the Dev panel gives them anyway).
-- * unlock: level (the hero's), story (that Act 1 mission cleared), after (another chain finished), origin
--   (Config.Creator.origins index; origin lines need it), side ("hero" or "villain": a line for one side
--   only), npc (true: accepted only by talking to the giver, never from the Journal: character lines).
-- * a step: hero and villain goals (the very same table in both is one shared goal), optional `lines`
--   (guide lines as it starts: { who, text } or { who, hero, villain }) and `scene` (a Config.Cinema client
--   scene id played in the next quiet moment). A goal: kind, the kind's numbers, text (and villainText on a
--   shared goal). The last step is the finale (kind "finale"), and only the last.
-- * kinds (Shared.SideQuestPlan.KINDS): talk, fight, incident, chase, deliver, fetch, hold, escort, carry,
--   race, reach, find, photo, beacon, pocket (a mission-shaped run in a mission pocket) and finale (the mini
--   villain: a boss-lite fight on an elite robot or a famous fake, with a name card).
-- * pay: every step pays like a contract at the hero's level (pay.contract x pay.step), the finale more, and
--   the chain's end its reward: a share of contract pay (at most pay.maxShare) and one cosmetic or title.
--   Nothing sold, nothing that changes stats beyond normal Renown.
-- * lines: what the giver says on the Talk prompt (offer, resume, done), each side its own text.
-- No free text anywhere: every string is fixed, with no format holes.
return {
	range = 12, -- talk range to a giver (the Talk prompt)
	gap = 3, -- seconds after a step before the next one is built
	coop = 220, -- studs: a squadmate on the same chain and step this close to its site shares it
	minSteps = 5,
	maxSteps = 10,
	maxText = 60, -- tracker text cap (a phone's tracker row)
	layers = { "district", "character", "origin" },
	-- where a district chain may be set (the city's districts, the outskirts rings, the quarry, the deep)
	districts = {
		"Downtown",
		"Uptown",
		"Docks",
		"OldTown",
		"Suburbs",
		"Farmland",
		"Coast",
		"OldQuarry",
		"Underwater",
	},
	sides = { "hero", "villain" },
	pocketNum = 160, -- MissionState num for a side quest pocket run (after the Showdown's 150)
	none = "Nothing for you right now. Come back later.", -- a giver with nothing to offer this hero yet
	pocketMinutes = { 4, 15 },
	finale = {
		reach = 150, -- studs from the finale that show the name card
		hpMult = { 2, 14 }, -- the boss-lite's health multiplier (a mission boss is 8)
		enemies = { "NullSentinel", "Captain", "Grappler", "Interceptor", "Radiant", "Bulwark", "Skylance" },
	},
	pay = {
		contract = "DroneSweep", -- the yard stick: this contract's pay at the hero's level
		step = 0.6, -- a step pays this share of it
		finale = 1.5, -- the finale
		maxShare = 4, -- a chain's end reward may be at most this share (reward.share)
	},
	-- The 8 side quest arcs before step 10 (retired by nate, 2026-11-17): only their count and what a finished
	-- one gave stay, by number, so old saves lose nothing (Shared.SideQuestPlan.settle): a finished arc keeps
	-- its unlocks and counts toward the chain pieces; an arc in progress pays stepCredits a finished step.
	retired = {
		arcs = 8,
		stepCredits = 200,
		rewards = {
			[1] = { style = "GoldSash" },
			[2] = { emote = "Salute" },
			[3] = { prop = "CafeSign" },
			[5] = { style = "DockCoat" },
			[8] = { frame = "PhotoFrame" },
		},
	},

	-- Who gives chains: a person on the R15 rig (PLACEHOLDER ART: plain colours until the art pass) at an
	-- anchor ("plaza", "hq", or a Config.City district) plus an offset; also a guide speaker (GuideHud lines).
	givers = {
		-- PLACEHOLDER (Dev only): the framework sample's giver
		SampleGiver = {
			name = "TEST GIVER",
			dev = true,
			anchor = "plaza",
			dx = -60,
			dz = 70,
			color = { 120, 200, 140 },
			style = "person",
			blip = "radio",
			portrait = {
				bg = { 40, 70, 50 },
				skin = { 224, 180, 140 },
				hair = { 60, 40, 30 },
				shape = "messy",
				extras = {},
			},
		},
	},

	chains = {
		-- PLACEHOLDER TEXT (Dev only): "Framework sample", 5 steps that run every runtime path once (talk, a
		-- fight and a heist run, an incident and a chase, a pocket run, the finale with its name card and a
		-- scene). Real chains come in build plan step 11.
		{
			id = "Sample",
			bit = 1,
			name = "Framework sample",
			layer = "district",
			district = "Downtown",
			giver = "SampleGiver",
			dev = true,
			unlock = { level = 1 },
			villain = { name = "THE TEST VILLAIN", title = "FRAMEWORK SAMPLE" },
			reward = { share = 2, emote = "Bow" },
			lines = {
				offer = {
					hero = "Sample chain. Five steps to test the framework.",
					villain = "Sample chain. Five jobs to test the framework.",
				},
				resume = { text = "Back for the sample? Pick up where you left off." },
				done = { text = "Sample done. Every step kind ran." },
			},
			steps = {
				{
					hero = { kind = "talk", text = "Sample: talk to the test giver" },
					villain = { kind = "talk", text = "Sample: talk to the test giver" },
					lines = {
						{
							who = "SampleGiver",
							hero = "Step one: talk. Done.",
							villain = "Step one: talk. Done.",
						},
					},
				},
				{
					hero = {
						kind = "fight",
						squads = { { "BurglarBot", 3 } },
						range = { 60, 150 },
						text = "Sample: stop the robots",
					},
					villain = {
						kind = "deliver",
						range = { 150, 300 },
						text = "Sample: run the loot to the drop",
					},
					lines = { { who = "patch", text = "Sample radio line: each side has its own job here." } },
				},
				{
					hero = { kind = "incident", count = 1, text = "Sample: clear an incident" },
					villain = {
						kind = "chase",
						enemy = "SneakBot",
						hops = 5,
						speed = 22,
						text = "Sample: catch the runner bot",
					},
				},
				{
					hero = {
						kind = "pocket",
						layout = "arena",
						minutes = 8,
						text = "Sample: clear the pocket",
						villainText = "Sample: clear the pocket",
						steps = {
							{
								kind = "defeat",
								squads = { { "SparkDrone", 4 } },
								text = "Sample: beat the drones",
							},
							{
								kind = "boss",
								enemy = "Captain",
								hpMult = 3,
								text = "Sample: beat the captain",
							},
						},
					},
					villain = "same", -- the hero's goal, shared (see SideQuestPlan.goal)
				},
				{
					hero = {
						kind = "finale",
						enemy = "NullSentinel",
						hpMult = 4,
						adds = { { "SparkDrone", 3 } },
						range = { 80, 180 },
						text = "Sample: beat the test villain",
						villainText = "Sample: beat the test villain",
					},
					villain = "same",
					scene = "cityWatch",
				},
			},
		},
	},

	-- Dev panel: one goal of every kind, built as a throwaway step (nothing saved) so each kind can be tried
	devKinds = {
		{ kind = "talk", text = "Kind test: talk" },
		{ kind = "fight", squads = { { "BurglarBot", 2 } }, range = { 40, 120 }, text = "Kind test: fight" },
		{ kind = "incident", count = 1, text = "Kind test: incident" },
		{ kind = "chase", enemy = "SneakBot", hops = 4, speed = 20, text = "Kind test: chase" },
		{ kind = "deliver", range = { 100, 200 }, text = "Kind test: deliver" },
		{ kind = "fetch", count = 2, range = { 80, 200 }, text = "Kind test: fetch" },
		{ kind = "hold", seconds = 6, radius = 10, text = "Kind test: hold" },
		{ kind = "escort", goal = 150, speed = 9, near = 40, text = "Kind test: escort" },
		{ kind = "carry", range = { 80, 160 }, text = "Kind test: carry" },
		{ kind = "race", checkpoints = 3, gap = 60, time = 40, text = "Kind test: race" },
		{ kind = "reach", high = 40, range = { 60, 200 }, text = "Kind test: reach" },
		{ kind = "find", range = { 100, 250 }, witness = true, text = "Kind test: find" },
		{ kind = "photo", count = 2, range = { 80, 200 }, text = "Kind test: photo" },
		{ kind = "beacon", seconds = 4, text = "Kind test: beacon" },
		{
			kind = "pocket",
			layout = "arena",
			minutes = 6,
			text = "Kind test: pocket",
			steps = {
				{ kind = "defeat", squads = { { "SparkDrone", 3 } }, text = "Kind test: beat the drones" },
			},
		},
		{ kind = "finale", enemy = "Captain", hpMult = 2, range = { 60, 150 }, text = "Kind test: finale" },
	},
}
