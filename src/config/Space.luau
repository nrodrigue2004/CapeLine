-- Space: the orbit zone and fly-in planet travel (spec: "Fly-in planet travel"; Everything Left 497-501 and 736,
-- nate 2026-11-20 22:02Z "keep the spec's 3 places and maybe an alien one too"). Built in this place for now
-- (the thread's scope card, recommended pick: testable in Studio with no published places); Config.Places keeps
-- the place ids for the move to separate places later, and the travel code only names a destination index.
--
-- How it plays: over Crane's Hero Hall roof hangs the ORBIT GATE (a ring under the ceiling). Fly into it (or use
-- the SPACEPORT on the roof, the spec's ship backup for heroes who can't fly) and a 4 s atmosphere entry (5 s by
-- ship) carries you up to the orbit zone: the Orbit Station's deck far above the clouds, home (Veyra) a huge
-- planet below, the moon Calder and the alien planet hanging in a black, starry sky, each with an approach ring.
-- Fly into a ring (or take the station's ship) and you burst out of the clouds above that world, still flying.
-- Friends and squadmates flying within `party` studs travel with you. Every world has a return ring and ship.
-- The server checks the ring, the level and that you are out of combat (Shared.SpaceLayout, SpaceService).
-- Worlds are big flat regions far off the city map that curve only visually (spec), lit their own way on the
-- device (Controllers.SpaceClient). No weather, incidents, ambient robots or PvP there (hero.scene "space").
-- PLACEHOLDER ART: part-built planets, station and scenery in the city's style until a Blender pass.
-- Names marked DRAFT are nate's to change.
-- PARKED 2026-11-21 (nate: "you can wait on the different planets until later"): off until he picks it back up;
-- the code, tests and layout stay so it turns on with `on = true`.
return {
	on = false,
	party = 40, -- friends and squadmates within this many studs travel with you
	entry = 4, -- seconds of atmosphere entry through a ring (spec)
	ship = 5, -- seconds of the ship's cutscene (spec)
	cooldown = 6, -- seconds between trips
	ringSlack = 28, -- the server's allowance on the ring check (studs, for lag)
	-- the Orbit Gate over the Hero Hall roof's launch pad: height over the pad (kept under Config.Move ceiling.soft)
	gate = { above = 210, radius = 30, maxY = 880, level = 3 },
	-- the spaceport counter on the roof, beside the launch pad (x, z from the pad)
	spaceport = { at = { 9, 0 } },
	-- the orbit zone: the station deck's centre, the world's edge (fly further and you drift back), the floor
	-- (fall below it and you go home)
	orbit = {
		at = { 0, 9000, 0 },
		deck = 64, -- the station deck's diameter
		edge = 2200,
		floor = 7600,
		clock = 0.5, -- the held hour (stars)
	},
	-- the worlds: 1 home, then the others. `sphere` is the planet in the orbit sky (offset from the station,
	-- radius; a Part ball tops out at 2048), `ring` its approach ring (offset, radius), `zone` the world's
	-- region on the ground (centre, half size) and where you arrive (`drop` studs over the ground, still flying)
	worlds = {
		{
			id = "Veyra",
			name = "VEYRA (HOME)",
			home = true,
			level = 1,
			sphere = {
				offset = { 0, -1900, 300 },
				radius = 1020,
				color = { 46, 108, 190 },
				land = { 92, 156, 84 },
			},
			ring = { offset = { 0, -260, 120 }, radius = 36 },
		},
		{
			id = "Calder",
			name = "CALDER (MOON)",
			level = 5,
			sphere = {
				offset = { 900, 420, -1300 },
				radius = 340,
				color = { 168, 168, 176 },
				land = { 112, 112, 122 },
			},
			ring = { offset = { 260, 120, -380 }, radius = 34 },
			zone = { at = { 14000, 120, 0 }, half = 700, drop = 260 },
			clock = 22, -- a black sky with Veyra hanging in it
			air = { Density = 0, Haze = 0, Color = { 20, 22, 30 }, Glare = 0 },
			ambient = { 120, 124, 140 },
			ground = { 150, 150, 158 },
		},
		{
			id = "Thalyx",
			name = "THALYX (DRAFT)", -- the alien planet: crystal jungle, two suns (nate's to name and shape)
			level = 10,
			sphere = {
				offset = { -1250, 260, -900 },
				radius = 460,
				color = { 132, 70, 190 },
				land = { 70, 210, 170 },
			},
			ring = { offset = { -340, 80, -260 }, radius = 40 },
			zone = { at = { -14000, 120, 0 }, half = 800, drop = 280 },
			clock = 15,
			air = {
				Density = 0.35,
				Haze = 1.6,
				Color = { 200, 130, 255 },
				Decay = { 255, 120, 200 },
				Glare = 0.4,
			},
			ambient = { 150, 110, 190 },
			ground = { 86, 52, 120 },
		},
		{
			id = "Ironmere",
			name = "IRONMERE (ACT 2)", -- the second city: shown in orbit, locked until Act 2 builds it (spec Phase 2)
			locked = true,
			level = 1,
			sphere = {
				offset = { 1400, -700, 900 },
				radius = 260,
				color = { 150, 96, 70 },
				land = { 90, 90, 96 },
			},
			ring = { offset = { 380, -90, 260 }, radius = 30 },
		},
	},
	-- the entry and arrival looks (Controllers.SpaceClient)
	look = {
		heat = { 255, 140, 60 }, -- the entry's glow
		streaks = { low = 14, medium = 24, high = 36 }, -- heat streaks on screen
		shake = 0.35,
		rumble = { pitch = 0.32, volume = 0.6 }, -- PLACEHOLDER SOUND: the collapse rumble pitched down
		burst = { low = 30, medium = 60, high = 90 }, -- cloud puffs as you burst out on arrival
		ringSpin = 0.4, -- radians a second
	},
	-- scenery counts per world (Shared.SpaceLayout seeds where they stand)
	scenery = {
		seed = 913,
		Calder = { craters = 26, rocks = 70, probe = true },
		Thalyx = { spires = 34, plants = 40, floaters = 14, pools = 8 },
	},
}
