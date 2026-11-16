-- World boss (spec: Schedulers > World boss; Opening and story > World boss; Boss.State, Boss.Contribution,
-- Boss.Result). Two launch bosses alternate: Rustjaw Prime lands in Downtown, the Lumen Maw rises from the
-- Old Quarry. Both are machines (a scrap robot and a shard-powered machine beast). (tune)
-- * Schedule: 20 to 30 minutes after the last one ended; a server with a player who has never seen a boss
--   clamps the wait to 6 minutes. A banner and siren at T minus 60 s. Raid prep incidents run in the last
--   5 minutes of the wait and each clear takes 3% off the boss's HP (at most 15%).
-- * HP: 60,000 + 4,000 per hero within 600 studs at the start, at level 20, scaled by the server's median
--   level like any robot: x (1 + 0.1 x (L - 1)) / (1 + 0.1 x 19).
-- * 3 phases (66% and 33%), weak points that take double damage, one hazard per phase, a shared bar.
-- * Contribution: 50% damage share, 30% support (heals, shields, rescues, revives), 20% objectives
--   (the cannons or the generators). Tiers: Participant at 10% of the median, Contributor top 50%, MVP
--   top 3; anyone who took part below that gets the 25% floor.
-- * 8 minutes, then it retreats: no rewards except a 25% Credits consolation for Participants and up.
-- Attack shapes: ring (around the boss), cone (in front), circles (at heroes), lines (at heroes), pull.
return {
	order = { "RustjawPrime", "LumenMaw" },
	schedule = {
		every = { 1200, 1800 },
		firstClamp = 360, -- spec: a new account's first boss within 6 minutes of them joining
		firstAfterBoot = 600, -- a fresh server's first boss (unless a new player clamps it sooner)
		banner = 60,
		prepWindow = 300,
		landing = 5, -- seconds of the landing or rising before it can be hit
		lifespan = 480,
		resultTime = 12, -- the result card, then the scheduler waits again
	},
	hp = { base = 60000, perHero = 4000, atLevel = 20, range = 600 },
	prep = { weakenEach = 0.03, weakenMax = 0.15 },
	phases = { 0.66, 0.33 },
	weakMult = 2,
	contribution = {
		damage = 0.5,
		support = 0.3,
		objectives = 0.2,
		participantShare = 0.1, -- of the median score
		contributorTop = 0.5,
		mvp = 3,
		floor = 0.25, -- late joiners and anyone below Participant who still took part
		rescueSupport = 400, -- a rescue during the fight counts as this much healing
		reviveSupport = 800, -- a revive (M8)
		objectiveBreak = 1000, -- breaking a cannon or generator; damage to them counts too
		sendRate = 1,
	},
	rewards = {
		consolation = 0.25, -- a retreat pays this share of the tier's Credits, nothing else
		styleChance = { mvp = 1, contributor = 0.5, participant = 0.2 },
		shiny = 1 / 20,
	},
	bosses = {
		RustjawPrime = {
			num = 1,
			name = "Rustjaw Prime",
			rogues = 1, -- Rogues File page bit
			arena = "plaza",
			arenaRadius = 220,
			height = 110,
			speed = 6, -- walks toward the crowd
			turn = 50, -- degrees per second
			gap = { 3.6, 3.1, 2.6 }, -- seconds between attacks in each phase
			-- body parts that take hits (offsets from the feet, in the boss's facing frame)
			targets = {
				{ id = "body", at = { 0, 70, 0 }, r = 22 },
				{ id = "head", at = { 0, 100, -4 }, r = 12 },
				{ id = "legL", at = { -14, 22, 0 }, r = 10 },
				{ id = "legR", at = { 14, 22, 0 }, r = 10 },
				{ id = "core", at = { 0, 72, -20 }, r = 6, weak = true },
				{ id = "kneeL", at = { -14, 30, -8 }, r = 5, weak = true },
				{ id = "kneeR", at = { 14, 30, -8 }, r = 5, weak = true },
			},
			-- objectives: shoulder cannons that shell the crowd until broken
			objectives = {
				kind = "cannon",
				hits = 40, -- HP in hits of Power at the zone level
				list = { { at = { -26, 92, 0 } }, { at = { 26, 92, 0 } } },
				fire = { every = 5, r = 8, warn = 1.4, coeff = 1.0 },
			},
			attacks = {
				{
					id = "Stomp",
					shape = "ring",
					r = 45,
					warn = 1.6,
					coeff = 2.0,
					struct = true,
					phases = { 1, 2, 3 },
				},
				{
					id = "Swipe",
					shape = "cone",
					r = 60,
					arc = 100,
					warn = 1.2,
					coeff = 1.6,
					phases = { 1, 2, 3 },
				},
				{
					id = "ScrapRain",
					shape = "circles",
					r = 12,
					count = 8,
					warn = 1.8,
					coeff = 1.4,
					phases = { 2 },
					hazard = true,
				},
				{
					id = "EyeLaser",
					shape = "lines",
					width = 10,
					length = 220,
					count = 3,
					warn = 1.2,
					coeff = 1.8,
					phases = { 3 },
					hazard = true,
				},
			},
		},
		LumenMaw = {
			num = 2,
			name = "Lumen Maw",
			rogues = 2,
			arena = "OldQuarry",
			arenaRadius = 160,
			height = 70,
			speed = 0, -- stays in its pit and turns
			turn = 60,
			gap = { 3.4, 3.0, 2.6 },
			targets = {
				{ id = "head", at = { 0, 40, -30 }, r = 16 },
				{ id = "body", at = { 0, 30, 10 }, r = 26 },
				{ id = "crystalA", at = { -12, 58, 8 }, r = 5, weak = true },
				{ id = "crystalB", at = { 0, 62, 16 }, r = 5, weak = true },
				{ id = "crystalC", at = { 12, 58, 8 }, r = 5, weak = true },
			},
			-- objectives: shard generators around the pit that heal it while they stand
			objectives = {
				kind = "generator",
				hits = 30,
				list = { { ring = 0 }, { ring = 120 }, { ring = 240 } }, -- degrees around the arena edge
				heal = 0.004, -- of max HP per second each
			},
			attacks = {
				{
					id = "Bite",
					shape = "cone",
					r = 55,
					arc = 70,
					warn = 1.2,
					coeff = 2.0,
					phases = { 1, 2, 3 },
				},
				{
					id = "ShardSpikes",
					shape = "circles",
					r = 10,
					count = 6,
					warn = 1.5,
					coeff = 1.5,
					phases = { 1, 2, 3 },
				},
				{
					id = "LumenBeam",
					shape = "lines",
					width = 12,
					length = 200,
					count = 2,
					warn = 1.4,
					coeff = 1.8,
					phases = { 2 },
					hazard = true,
				},
				{
					id = "GravityPull",
					shape = "pull",
					r = 120,
					nova = 35,
					warn = 2.0,
					coeff = 2.2,
					phases = { 3 },
					hazard = true,
				},
			},
		},
		-- Mission 6 (Story): Null's War-Frame. Not in `order`, so the world scheduler never picks it. 3 phases:
		-- rockets and a ground sweep while its 2 shoulder cannons stand; at 66% it calls 6 Spark Drones and
		-- raises a shield that only 3 hits on the back weak point break; at 33% a floor-fire sweep and a
		-- charged laser that the arena's pillars block. It never retreats (a wipe just retries).
		NullWarFrame = {
			num = 3,
			name = "Null War-Frame",
			mission = true,
			arenaRadius = 180,
			height = 60,
			speed = 0,
			turn = 70,
			gap = { 3.2, 2.8, 2.4 },
			lifespan = 1e6,
			targets = {
				{ id = "body", at = { 0, 34, 0 }, r = 16 },
				{ id = "head", at = { 0, 54, -4 }, r = 9 },
				{ id = "back", at = { 0, 40, 14 }, r = 5, weak = true },
				{ id = "knee", at = { 0, 14, -8 }, r = 5, weak = true },
			},
			objectives = {
				kind = "cannon",
				hits = 24,
				list = { { at = { -16, 50, 2 } }, { at = { 16, 50, 2 } } },
				fire = { every = 4.5, r = 9, warn = 1.4, coeff = 1.0 },
			},
			shield = { phase = 2, hits = 3, key = "back" },
			summon = { phase = 2, kind = "SparkDrone", n = 6 },
			attacks = {
				{
					id = "Rockets",
					shape = "circles",
					r = 10,
					count = 4,
					warn = 1.5,
					coeff = 1.2,
					phases = { 1, 2 },
				},
				{
					id = "GroundSweep",
					shape = "cone",
					r = 70,
					arc = 160,
					warn = 1.3,
					coeff = 1.5,
					phases = { 1, 2 },
				},
				{ id = "Stomp", shape = "ring", r = 40, warn = 1.5, coeff = 1.8, phases = { 2, 3 } },
				{
					id = "FloorFire",
					shape = "cone",
					r = 120,
					arc = 220,
					warn = 1.8,
					coeff = 1.6,
					phases = { 3 },
				},
				{
					id = "ChargeLaser",
					shape = "lines",
					width = 14,
					length = 230,
					count = 1,
					warn = 2.6,
					coeff = 3.0,
					cover = true, -- the arena's pillars block it
					phases = { 3 },
					hazard = true,
				},
			},
		},
	},
}
