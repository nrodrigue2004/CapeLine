-- World boss (spec: Schedulers > World boss; Opening and story > World boss; Boss.State, Boss.Contribution,
-- Boss.Result). Two launch bosses alternate: Rustjaw Prime lands in Downtown, the Lumen Maw rises from the
-- Old Quarry. The third, the Leviathan Engine (underwater at launch, nate 2026-11-16), surfaces over the Trench;
-- heroes fight it from the water, from Frost ice rafts and from the air. (tune)
-- Looks (nate's lore, 2026-11-17, build plan step 8; standalone from the main story, names and fights unchanged):
-- Rustjaw Prime, the Junkyard Titan (a giant a mad scrapper built from wrecked cars); Lumen Maw, the Light Eater
-- (a light-eating night creature); Leviathan Engine, the Deep Machine (an ancient brass-and-stone sea machine).
-- The looks are Config.BossArt's (art/blender/bosses.py); the titles are Config.Cinema.nameCard's.
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
-- Attack shapes: ring (around the boss; `up` how high it reaches, 12 by default), cone (in front), circles (at heroes),
-- lines (at heroes), pull, and the counters (2026-11-19): homing (3D shots at airborne heroes), column (a cylinder by its
-- body from lo to hi up), tether (a homing shot that yanks its target in). `react` marks a reactive attack (BossSim).
return {
	order = { "RustjawPrime", "LumenMaw", "LeviathanEngine" },
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
	-- fix-hud (nate, gaps7: "Why is the boss bar above my screen if im not even near it?"): the big countdown
	-- banner and the shared HP bar show only near the fight (inside max(near, the arena's radius) studs, flat,
	-- leaving at that plus `leave`) or once you are on its contribution list; elsewhere the radar's corner timer
	-- and the world marker only (BossMath.hudNear)
	hud = { near = 400, leave = 60 },
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
			-- buildings (nate's playtest 2026-11-19, "Boss is stuck between building"): its footprint smashes every
			-- building it walks into (a blast of dmg at `at` up, every `every` s a building, within the collapse
			-- caps; slowed to `slow` while it plows), pinned ones push it round, and after unstick.after seconds
			-- going nowhere it leaps (Leap, telegraphed) to open ground near its crowd
			bodyR = 14, -- its feet's footprint (the legs stand at +-14): it fits a 30-stud street, so it walks the streets
			-- and smashes what it walks into rather than everything it passes
			smash = { every = 0.5, dmg = 2400, slow = 0.6, reach = 1, at = 8 },
			unstick = { after = 4 },
			chase = { beyond = 120, mult = 2 }, -- a crowd further than 120 studs: it charges at twice its walk
			-- counters (nate's playtest 2026-11-19: every boss threatens every mobility and range; BossSim): close = within
			-- meleeR (flat) and not above its top; airborne = more than `air` up and not close; a hero further than
			-- kiteRange (or above its top) for kiteAfter seconds draws the gap closer; nobody close for enrage.after
			-- seconds: gaps x enrage.gap, hits x enrage.dmg until someone comes in
			counters = {
				meleeR = 60,
				air = 14,
				kiteRange = 120,
				kiteAfter = 10,
				enrage = { after = 25, gap = 0.7, dmg = 1.25 },
			},
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
			-- objectives: shoulder junk launchers that shell the crowd until broken
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
				-- counters (react): homing shots at airborne heroes away from it (they follow 60% of a move, at most 40
				-- studs: keep moving to shake them), a column swat at heroes hovering by its body (knocked down), and
				-- the gap closer on a kiter
				{
					id = "JunkFlak",
					shape = "homing",
					react = "air",
					r = 10,
					count = 3,
					track = 0.6,
					maxTrack = 40,
					warn = 1.6,
					coeff = 1.3,
					cooldown = 6,
					phases = { 1, 2, 3 },
				},
				{
					id = "Swat",
					shape = "column",
					react = "hover",
					r = 55,
					lo = 24,
					hi = 150,
					drop = 30,
					warn = 1.2,
					coeff = 1.8,
					cooldown = 7,
					phases = { 1, 2, 3 },
				},
				{
					id = "Leap", -- lands on the kiter's spot (open ground); also the last-resort unstick
					shape = "ring",
					react = "kite",
					leap = true,
					r = 36,
					up = 40, -- the landing's shockwave reaches low fliers
					warn = 1.8,
					coeff = 1.8,
					struct = true,
					cooldown = 12,
					phases = { 1, 2, 3 },
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
			-- counters (nate's playtest 2026-11-19: every boss threatens every mobility and range; BossSim): close = within
			-- meleeR (flat) and not above its top; airborne = more than `air` up and not close; a hero further than
			-- kiteRange (or above its top) for kiteAfter seconds draws the gap closer; nobody close for enrage.after
			-- seconds: gaps x enrage.gap, hits x enrage.dmg until someone comes in
			counters = {
				meleeR = 55,
				air = 14,
				kiteRange = 110,
				kiteAfter = 10,
				enrage = { after = 25, gap = 0.7, dmg = 1.25 },
			},
			gap = { 3.4, 3.0, 2.6 },
			targets = {
				{ id = "head", at = { 0, 40, -30 }, r = 16 },
				{ id = "body", at = { 0, 30, 10 }, r = 26 },
				{ id = "crystalA", at = { -12, 58, 8 }, r = 5, weak = true },
				{ id = "crystalB", at = { 0, 62, 16 }, r = 5, weak = true },
				{ id = "crystalC", at = { 12, 58, 8 }, r = 5, weak = true },
			},
			-- objectives: the stolen lights (generators) around the pit that feed it while they stand; the three
			-- weak points (ids crystalA..C) are the light sacs on its back
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
				-- counters (react): homing shots at airborne heroes away from it (they follow 60% of a move, at most 40
				-- studs: keep moving to shake them), a column swat at heroes hovering by its body (knocked down), and
				-- the gap closer on a kiter
				{
					id = "LightSeekers",
					shape = "homing",
					react = "air",
					r = 10,
					count = 3,
					track = 0.6,
					maxTrack = 40,
					warn = 1.6,
					coeff = 1.3,
					cooldown = 6,
					phases = { 1, 2, 3 },
				},
				{
					id = "SnapUp",
					shape = "column",
					react = "hover",
					r = 50,
					lo = 20,
					hi = 110,
					drop = 30,
					warn = 1.2,
					coeff = 1.8,
					cooldown = 7,
					phases = { 1, 2, 3 },
				},
				{
					id = "LureBeam", -- a tether at the kiter: a hit yanks them in to `yank` studs from it
					shape = "tether",
					react = "kite",
					r = 10,
					track = 0.6,
					maxTrack = 40,
					yank = 30,
					warn = 1.6,
					coeff = 1.2,
					cooldown = 12,
					phases = { 1, 2, 3 },
				},
			},
		},
		LeviathanEngine = {
			num = 4,
			name = "Leviathan Engine",
			rogues = 3,
			arena = "trench", -- Config.Deep.trench.arena, at the water's surface
			arenaRadius = 240,
			height = 60,
			speed = 0, -- holds over the Trench and turns its head
			turn = 45,
			-- counters (nate's playtest 2026-11-19: every boss threatens every mobility and range; BossSim): close = within
			-- meleeR (flat) and not above its top; airborne = more than `air` up and not close; a hero further than
			-- kiteRange (or above its top) for kiteAfter seconds draws the gap closer; nobody close for enrage.after
			-- seconds: gaps x enrage.gap, hits x enrage.dmg until someone comes in
			counters = {
				meleeR = 65,
				air = 14,
				kiteRange = 130,
				kiteAfter = 10,
				enrage = { after = 25, gap = 0.7, dmg = 1.25 },
			},
			gap = { 3.6, 3.0, 2.5 },
			-- the head and neck rise out of the water; the hull and reactor sit just under the surface
			targets = {
				{ id = "head", at = { 0, 46, -34 }, r = 14 },
				{ id = "neck", at = { 0, 26, -18 }, r = 11 },
				{ id = "hull", at = { 0, 6, 14 }, r = 20 },
				{ id = "eyeL", at = { -8, 50, -46 }, r = 4, weak = true },
				{ id = "eyeR", at = { 8, 50, -46 }, r = 4, weak = true },
				{ id = "reactor", at = { 0, 14, 2 }, r = 5, weak = true },
			},
			-- objectives: two vent hatches on its back that fire on the crowd until broken; the reactor is its
			-- tide-turbine heart
			objectives = {
				kind = "cannon",
				hits = 36,
				list = { { at = { -14, 16, 12 } }, { at = { 14, 16, 12 } } },
				fire = { every = 5, r = 10, warn = 1.5, coeff = 1.1 },
			},
			attacks = {
				{
					id = "TailSweep",
					shape = "cone",
					r = 80,
					arc = 200,
					warn = 1.4,
					coeff = 1.7,
					phases = { 1, 2, 3 },
				},
				{
					id = "TorpedoVolley",
					shape = "circles",
					r = 11,
					count = 6,
					warn = 1.8,
					coeff = 1.4,
					phases = { 1, 2, 3 },
				},
				{
					id = "Whirlpool",
					shape = "pull",
					r = 130,
					nova = 35,
					warn = 2.0,
					coeff = 2.0,
					phases = { 2 },
					hazard = true,
				},
				{
					id = "Surge",
					shape = "ring",
					r = 70,
					warn = 1.6,
					coeff = 2.0,
					phases = { 3 },
					hazard = true,
				},
				-- counters (react): homing shots at airborne heroes away from it (they follow 60% of a move, at most 40
				-- studs: keep moving to shake them), a column swat at heroes hovering by its body (knocked down), and
				-- the gap closer on a kiter
				{
					id = "SkyTorpedoes",
					shape = "homing",
					react = "air",
					r = 10,
					count = 3,
					track = 0.6,
					maxTrack = 40,
					warn = 1.6,
					coeff = 1.3,
					cooldown = 6,
					phases = { 1, 2, 3 },
				},
				{
					id = "Breach",
					shape = "column",
					react = "hover",
					r = 55,
					lo = 18,
					hi = 100,
					drop = 30,
					warn = 1.2,
					coeff = 1.8,
					cooldown = 7,
					phases = { 1, 2, 3 },
				},
				{
					id = "Harpoon", -- a tether at the kiter: a hit yanks them in to `yank` studs from it
					shape = "tether",
					react = "kite",
					r = 10,
					track = 0.6,
					maxTrack = 40,
					yank = 30,
					warn = 1.6,
					coeff = 1.2,
					cooldown = 12,
					phases = { 1, 2, 3 },
				},
			},
		},
		-- Mission 6 (Story, Live): Bulwark's battle form, what the famous fake turns into once unmasked live (lore step 5;
		-- the old mission 6 fight reused, id kept). Not in `order`, so the world scheduler never picks it. 3 phases:
		-- rockets and a ground sweep while its 2 shoulder cannons stand; at 66% it calls 6 Spark Drones and
		-- raises a shield that only 3 hits on the back weak point break; at 33% a floor-fire sweep and a
		-- charged laser that the arena's pillars block. It never retreats (a wipe just retries).
		NullWarFrame = {
			num = 3,
			name = "{Bulwark}'s Battle Form", -- lore step 5: the famous fake unmasked in Live (was "The War-Frame")
			mission = true,
			arenaRadius = 180,
			height = 60,
			speed = 0,
			turn = 70,
			-- counters (nate's playtest 2026-11-19: every boss threatens every mobility and range; BossSim): close = within
			-- meleeR (flat) and not above its top; airborne = more than `air` up and not close; a hero further than
			-- kiteRange (or above its top) for kiteAfter seconds draws the gap closer; nobody close for enrage.after
			-- seconds: gaps x enrage.gap, hits x enrage.dmg until someone comes in
			counters = {
				meleeR = 45,
				air = 14,
				kiteRange = 100,
				kiteAfter = 10,
				enrage = { after = 25, gap = 0.7, dmg = 1.25 },
			},
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
				-- counters (react): homing shots at airborne heroes away from it (they follow 60% of a move, at most 40
				-- studs: keep moving to shake them), a column swat at heroes hovering by its body (knocked down), and
				-- the gap closer on a kiter
				{
					id = "SeekerMissiles",
					shape = "homing",
					react = "air",
					r = 10,
					count = 3,
					track = 0.6,
					maxTrack = 40,
					warn = 1.6,
					coeff = 1.3,
					cooldown = 6,
					phases = { 1, 2, 3 },
				},
				{
					id = "FlakBurst",
					shape = "column",
					react = "hover",
					r = 45,
					lo = 18,
					hi = 100,
					drop = 30,
					warn = 1.2,
					coeff = 1.8,
					cooldown = 7,
					phases = { 1, 2, 3 },
				},
				{
					id = "GrappleClaw", -- a tether at the kiter: a hit yanks them in to `yank` studs from it
					shape = "tether",
					react = "kite",
					r = 10,
					track = 0.6,
					maxTrack = 40,
					yank = 30,
					warn = 1.6,
					coeff = 1.2,
					cooldown = 12,
					phases = { 1, 2, 3 },
				},
			},
		},
	},
}
