-- Every ability's own look (nate's playtest 2026-11-19: "Need more unique effects"). On top of its path's
-- palette and look (Config.Fx.paths: head, mark, flourish, dash, drift, motes, super moment), each of the 136
-- powers has a recipe here, drawn by the client's Fx/AbilityFx (rules and costs in Shared.FxPlan):
--   flair   the cast flourish on the caster (every slot, basics too): a sigil, a ground crack, an aura burst...
--   hit     what lands on every hit and at the move's area (a nova's heart, a landing): a shockwave ring, a
--           crater, sparks, shards, a splash, a pillar of light...
--   trail   what streams behind what flies (bolts, chain hops, lines, dashes, leaps)
--   screen  supers (and Bullet Time, FxPlan.SKILL_SCREENS): the caster's screen moment (letterbox bars, speed lines, a slash across the screen...)
--   head, mark, cast (optional) swap the path's own head, hit mark or cast flourish for this move only, using
--           any path's drawing (FxPlan.HEADS, MARKS, CASTS) in this path's colours
--   size    how big its head, hit and flair draw (1 = the path's size)
-- Uniqueness (tests/fx_unique_test.luau): inside a path no two moves share a flair, no two share a hit, and no
-- two moves that fly share a trail, so every move reads as its own even in the same colours.
-- Weapon moves are not here: they keep their own visuals. PLACEHOLDER ART: part-built shapes plus the effects
-- library's sheets until the VFX pass (the rune and scorch sheets are uploaded, Config.Fx.lib.textures; rings,
-- hoops, stones, crystals and crescents are Art.Powers meshes since 2026-11-20).

return {
	-- what each recipe name costs at the high preset: part-built pieces (FxLib.pieces scales them per preset)
	-- and particles by kind (scaled like FxPlan.plan). A trail emits its particles at `trailPoints` points.
	-- AbilityFx draws exactly these counts, so the budget tests check what is really drawn.
	kit = {
		trail = {
			none = { parts = 0, fx = {} },
			ribbon = { parts = 1, fx = { wisp = 1 } }, -- a thin bright ribbon in the accent colour
			spiral = { parts = 6, fx = {} }, -- beads spiral around the flight
			beads = { parts = 5, fx = { spark = 1 } }, -- a dotted line of beads that pop
			zigzag = { parts = 4, fx = { crackle = 1 } }, -- a jagged bolt beside the flight
			twin = { parts = 2, fx = {} }, -- two thin lines either side
			comet = { parts = 1, fx = { ember = 2 } }, -- a fat comet tail with embers
			wake = { parts = 4, fx = {} }, -- rings standing across the flight, like a sonic wake
			sparkle = { parts = 0, fx = { star = 2 } }, -- twinkles left behind
			smoke = { parts = 0, fx = { smoke = 2 } }, -- a smoke streak
		},
		hit = {
			none = { parts = 0, fx = {} },
			ring = { parts = 1, fx = { shock = 1 } }, -- a flat shockwave ring
			crater = { parts = 4, fx = { scorch = 1, dust = 2 } }, -- a scorched crater and chips
			sparks = { parts = 2, fx = { spark = 8 } }, -- a spark spray and a glint
			shards = { parts = 6, fx = { glow = 1 } }, -- glassy shards burst out
			splash = { parts = 6, fx = { bubble = 3 } }, -- a crown of drops
			pillar = { parts = 1, fx = { wisp = 3 } }, -- a pillar of light shoots up
			starburst = { parts = 6, fx = { star = 1 } }, -- spikes burst out flat in a star
			petals = { parts = 5, fx = { wisp = 2 } }, -- flat petals spin outward
			spiral = { parts = 0, fx = { vortex = 1, implode = 1 } }, -- a vortex sucks in
			cross = { parts = 2, fx = { slash = 2 } }, -- an X cut
			bloom = { parts = 1, fx = { glow = 1 } }, -- a sphere blooms and fades
			shatter = { parts = 6, fx = { shard = 4 } }, -- cubes shatter and fall
			bubble = { parts = 1, fx = { bubble = 4 } }, -- a bubble wraps the target and pops
			rays = { parts = 5, fx = { star = 2 } }, -- rays fan up out of the hit
			cage = { parts = 6, fx = { spark = 2 } }, -- bars rise around the target
			rune = { parts = 1, fx = { rune = 1 } }, -- a rune circle under the target
		},
		flair = {
			none = { parts = 0, fx = {} },
			sigil = { parts = 1, fx = { rune = 1 } }, -- a rune circle at the feet
			crack = { parts = 5, fx = { dust = 2 } }, -- cracks run out from the feet
			burst = { parts = 1, fx = { core = 1, spark = 4 } }, -- an aura burst at the chest
			spin = { parts = 2, fx = {} }, -- two rings spin around the body
			pillar = { parts = 1, fx = { wisp = 3 } }, -- a column of light up the body
			fan = { parts = 5, fx = {} }, -- lines fan out ahead
			orbs = { parts = 4, fx = { glow = 1 } }, -- orbs pop out round the hand and fly ahead
			vent = { parts = 0, fx = { smoke = 4, dust = 2 } }, -- a vent of smoke at the feet
			halo = { parts = 1, fx = { star = 2 } }, -- a halo over the head
			flash = { parts = 1, fx = { glow = 1, spark = 3 } }, -- a quick flash at the hand
			wings = { parts = 2, fx = { wisp = 4 } }, -- two wings of light open behind
			lines = { parts = 6, fx = { implode = 1 } }, -- lines rush in to the hand
			rune = { parts = 1, fx = { glyph = 1 } }, -- a glyph circle stands before the hand
			dust = { parts = 0, fx = { dust = 4, rock = 2 } }, -- dust and pebbles kick up
		},
		trailPoints = 3,
		-- a move's whole draw (its flair, its trail and a hit on superTargets robots) must fit in this share of a
		-- second's particle budget and partShare of the pieces budget on every preset; with a super's own path
		-- moment on top, the two together stay under withSuper (tests check)
		share = 0.15,
		partShare = 0.5,
		withSuper = 0.8,
		-- a basic is drawn this much smaller (they fire every half second)
		basicScale = 0.6,
		-- others' moves draw at this share (yours at 1), like CombatFx's impacts
		othersScale = 0.6,
		-- the screen moments' timings (s)
		screen = { bars = 0.9, lines = 0.35, slash = 0.4, vignette = 0.6, pulse = 0.12 },
	},
	moves = {
		-- Volt: the slice keeps its path look; each move adds its own on top
		ZapBolt = { flair = "flash", hit = "sparks", trail = "zigzag", size = 0.8 },
		ChainLightning = { flair = "lines", hit = "starburst", trail = "twin" },
		DashStrike = { flair = "burst", hit = "ring", trail = "ribbon" },
		StaticField = { flair = "sigil", hit = "cage" },
		ArcFlash = { flair = "fan", hit = "cross" },
		Overcharge = { flair = "spin", hit = "bloom" },
		GroundSpark = { flair = "crack", hit = "pillar", trail = "beads" },
		ThunderDrop = { flair = "halo", hit = "crater", screen = "flash", size = 1.4 },
		-- Frost
		IceShard = { flair = "flash", hit = "shards", trail = "sparkle", size = 0.8 },
		FreezeBeam = { flair = "rune", hit = "bloom", trail = "twin" },
		IceSlide = { flair = "dust", hit = "petals" },
		FrostNova = { flair = "crack", hit = "ring", size = 1.2 },
		SnowWall = { flair = "pillar", hit = "cage" },
		GlacierArmor = { flair = "spin", hit = "shatter" },
		Shatter = { flair = "orbs", hit = "starburst", trail = "spiral", mark = "prism", size = 1.3 },
		BlizzardDome = { flair = "sigil", hit = "rune", screen = "vignette", size = 1.4 },
		-- Fire
		FlareShot = { flair = "flash", hit = "bloom", trail = "comet", size = 0.8 },
		FlameJets = { flair = "vent", hit = "ring" },
		FireWhip = { flair = "lines", hit = "cross", trail = "spiral" },
		EmberRing = { flair = "sigil", hit = "petals" },
		Flashpoint = { flair = "orbs", hit = "crater", trail = "beads", mark = "pow", size = 1.3 },
		HeatHaze = { flair = "burst", hit = "spiral" },
		PhoenixDive = { flair = "wings", hit = "pillar", trail = "ribbon", size = 1.2 },
		Sunfall = { flair = "halo", hit = "rays", screen = "pulse", size = 1.4 },
		-- Earth
		PebbleBarrage = { flair = "dust", hit = "shatter", trail = "beads", size = 0.8 },
		RockRide = { flair = "vent", hit = "ring" },
		StonePillar = { flair = "pillar", hit = "crater", cast = "footprint" },
		Quicksand = { flair = "spin", hit = "spiral" },
		MudWave = { flair = "crack", hit = "splash", trail = "wake" },
		VineSnare = { flair = "sigil", hit = "cage" },
		Sandstorm = { flair = "burst", hit = "petals" },
		Overgrowth = { flair = "rune", hit = "bloom", screen = "vignette", size = 1.4 },
		-- Tide
		WaterJet = { flair = "flash", hit = "splash", trail = "twin", size = 0.8 },
		WaveSurf = { flair = "vent", hit = "ring" },
		BubblePrison = { flair = "orbs", hit = "bubble", trail = "spiral" },
		Riptide = { flair = "spin", hit = "spiral" },
		Geyser = { flair = "crack", hit = "pillar", trail = "beads" },
		HealingRain = { flair = "halo", hit = "petals" },
		TideMirror = { flair = "rune", hit = "shards" },
		Tsunami = { flair = "lines", hit = "bloom", trail = "wake", screen = "bars", size = 1.4 },
		-- Blade
		BladeSlash = { flair = "flash", hit = "sparks", size = 0.8 },
		FlashStep = { flair = "lines", hit = "cross", trail = "ribbon" },
		CrescentWave = { flair = "fan", hit = "ring", trail = "wake" },
		RisingBlade = { flair = "wings", hit = "pillar" },
		ThousandCuts = { flair = "spin", hit = "starburst" },
		ParryStance = { flair = "rune", hit = "shatter" },
		BladeStorm = { flair = "sigil", hit = "spiral" },
		HeavenSplitter = { flair = "pillar", hit = "rays", trail = "twin", screen = "slash", size = 1.4 },
		-- Gunslinger
		TwinPistols = { flair = "flash", hit = "sparks", trail = "twin", size = 0.8 },
		RecoilJump = { flair = "dust", hit = "ring" },
		Ricochet = { flair = "lines", hit = "starburst", trail = "zigzag" },
		TrickShot = { flair = "fan", hit = "cross", trail = "ribbon", head = "lance", size = 1.2 },
		BulletTime = { flair = "sigil", hit = "spiral", screen = "slowmo" },
		GrenadeRoll = { flair = "vent", hit = "crater", trail = "smoke" },
		DeadeyeMark = { flair = "rune", hit = "bloom" },
		HighNoon = { flair = "burst", hit = "rays", screen = "bars", size = 1.4 },
		-- Gadgeteer
		WristBlaster = { flair = "flash", hit = "sparks", trail = "beads", size = 0.8 },
		Hoverboard = { flair = "vent", hit = "ring" },
		TurretDrop = { flair = "pillar", hit = "crater" },
		GrappleYank = { flair = "lines", hit = "cross", trail = "twin", head = "kunai" },
		ShockMines = { flair = "sigil", hit = "cage" },
		FixItDrone = { flair = "halo", hit = "bloom" },
		HoloDecoy = { flair = "rune", hit = "shatter" },
		MechSuit = { flair = "burst", hit = "starburst", screen = "lines", size = 1.4 },
		-- Shadow
		KunaiThrow = { flair = "flash", hit = "cross", trail = "ribbon", size = 0.8 },
		ShadowStep = { flair = "vent", hit = "spiral", trail = "smoke" },
		SmokeBomb = { flair = "burst", hit = "bloom" },
		ShadowClones = { flair = "wings", hit = "shatter" },
		ChainSickle = { flair = "lines", hit = "cage", trail = "spiral" },
		NightMark = { flair = "rune", hit = "rune", trail = "beads", mark = "sigil" },
		WallRunStrike = { flair = "fan", hit = "pillar", trail = "twin" },
		Eclipse = { flair = "halo", hit = "crater", screen = "invert", size = 1.4 },
		-- Titan
		PunchCombo = { flair = "flash", hit = "starburst", size = 0.8 },
		LiftAndThrow = { flair = "dust", hit = "crater" },
		GroundSlam = { flair = "vent", hit = "ring", size = 1.2 },
		ShoulderCharge = { flair = "lines", hit = "shatter", trail = "wake" },
		Brace = { flair = "spin", hit = "cage" },
		Haymaker = { flair = "burst", hit = "bloom", size = 1.4 },
		RallyRoar = { flair = "halo", hit = "rays" },
		MeteorLeap = { flair = "pillar", hit = "sparks", trail = "comet", screen = "pulse", size = 1.4 },
		-- Martial
		KiStrike = { flair = "flash", hit = "starburst", size = 0.8 },
		SkyStep = { flair = "dust", hit = "ring" },
		KiBlast = { flair = "orbs", hit = "bloom", trail = "spiral", size = 1.2 },
		HundredFists = { flair = "lines", hit = "sparks" },
		CounterPalm = { flair = "rune", hit = "cross" },
		DragonRise = { flair = "pillar", hit = "pillar" },
		SpiritFocus = { flair = "spin", hit = "petals" },
		HeavenfallBeam = { flair = "burst", hit = "crater", trail = "twin", screen = "lines", size = 1.4 },
		-- Juggernaut
		GauntletSmash = { flair = "flash", hit = "sparks", size = 0.8 },
		Unstoppable = { flair = "lines", hit = "shatter", trail = "wake" },
		IronHide = { flair = "spin", hit = "cage" },
		GirderSwing = { flair = "fan", hit = "starburst", size = 1.2 },
		ShockwaveStomp = { flair = "crack", hit = "ring", size = 1.2 },
		Bulldoze = { flair = "dust", hit = "crater", trail = "smoke" },
		Challenge = { flair = "halo", hit = "rays" },
		SiegeMode = { flair = "vent", hit = "pillar", screen = "bars", size = 1.4 },
		-- Colossus
		GiantSwipe = { flair = "fan", hit = "shatter", size = 0.9 },
		GiantStride = { flair = "dust", hit = "crater" },
		Grow = { flair = "pillar", hit = "bloom" },
		CarToss = { flair = "lines", hit = "sparks" },
		ThunderClap = { flair = "flash", hit = "ring", size = 1.3 },
		BoulderFist = { flair = "orbs", hit = "starburst", trail = "comet", size = 1.4 },
		ShrinkDodge = { flair = "spin", hit = "spiral" },
		TitanForm = { flair = "crack", hit = "pillar", screen = "pulse", size = 1.4 },
		-- Pulse (gravity)
		PushWave = { flair = "fan", hit = "ring", size = 0.8 },
		Pull = { flair = "lines", hit = "spiral", trail = "spiral" },
		Float = { flair = "orbs", hit = "bubble", trail = "beads" },
		GravityWell = { flair = "sigil", hit = "cage" },
		Repulse = { flair = "burst", hit = "bloom" },
		Weightless = { flair = "wings", hit = "petals" },
		Crush = { flair = "rune", hit = "crater", trail = "twin", mark = "quake", size = 1.3 },
		Singularity = { flair = "spin", hit = "shatter", screen = "invert", size = 1.4 },
		-- Mind
		PsiBolt = { flair = "flash", hit = "rune", trail = "wake", size = 0.8 },
		PsiPlatform = { flair = "rune", hit = "ring" },
		Telekinesis = { flair = "lines", hit = "shatter" },
		Override = { flair = "halo", hit = "cage", trail = "zigzag", head = "lens" },
		MindShield = { flair = "spin", hit = "bubble" },
		PsychicLink = { flair = "orbs", hit = "starburst" },
		Foresight = { flair = "sigil", hit = "rays" },
		PsychicStorm = { flair = "burst", hit = "crater", screen = "pulse", size = 1.4 },
		-- Spirit
		GuardianJab = { flair = "flash", hit = "starburst", size = 0.8 },
		SpiritRide = { flair = "vent", hit = "ring" },
		GuardianRush = { flair = "wings", hit = "sparks" },
		SoulChains = { flair = "lines", hit = "cage", trail = "beads" },
		WardTotem = { flair = "pillar", hit = "rune" },
		GuardianShield = { flair = "spin", hit = "bubble" },
		SpiritSwap = { flair = "rune", hit = "spiral", trail = "ribbon" },
		AscendedGuardian = { flair = "halo", hit = "rays", screen = "vignette", size = 1.4 },
		-- Light
		LightLance = { flair = "flash", hit = "starburst", trail = "sparkle", size = 0.8 },
		LightRail = { flair = "lines", hit = "ring" },
		PrismBeam = { flair = "fan", hit = "shards", trail = "twin" },
		RadiantHeal = { flair = "orbs", hit = "petals" },
		Flash = { flair = "burst", hit = "bloom" },
		Sanctuary = { flair = "sigil", hit = "pillar" },
		HaloBlades = { flair = "spin", hit = "cross" },
		Dawnburst = { flair = "wings", hit = "rays", screen = "lines", size = 1.4 },
	},
}
