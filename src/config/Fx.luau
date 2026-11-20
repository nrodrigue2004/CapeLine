-- Juice numbers for the M1 actions (spec: Audio, VFX, juice and accessibility). Client only. (tune)
return {
	-- item 179: a giant's look (FormFx, the Form attribute "giant" from Grow and "titan" from Titan Form): a lit
	-- outline in the hero's path colour, a burst as the form starts, and footfalls every `stride` studs (times the
	-- form's scale) walked on the ground: dust, a low thud, and a shake for cameras within `shakeRange`
	-- (strength by distance). A titan's footfalls (scale crushAt and up) knock the street's small things loose.
	giant = {
		forms = { giant = 2, titan = 4 }, -- the form's scale (Config.Abilities Grow / TitanForm)
		stride = 3.2,
		dust = 2.2,
		shake = { time = 0.12, amount = 0.25, range = 70 },
		outline = 0.15,
		fill = 0.88,
		pitch = 0.7,
		crushAt = 4,
	},
	-- item 219: capes sway (Fx.CapeSway; the drape pieces LookKit marks Sway swing about the collar). lift: degrees
	-- the cape rises behind at full forward speed (`fast` studs/s) and from falling (`fall` studs/s); side: degrees
	-- it swings out from sideways movement; flutter: degrees of ripple at speed; idle: a slow breath; follow: how
	-- fast it catches up (per second); reach: only heroes this close to the camera, at most `count` of them.
	cape = {
		lift = 70,
		fast = 60,
		fall = 70,
		fallLift = 45,
		side = 18,
		flutter = 7,
		idle = 2.5,
		follow = 7,
		reach = 160,
		count = 16,
		max = 85,
	},
	-- item 215 and 216: set pieces that move (Fx.SetMotion; each device moves the server's anchored meshes locally,
	-- and lets go of one the server moves itself, like the chandelier falling). By mesh name (Config.SetPieceArt):
	-- spin (radians a second about up), bob (studs, `rate` cycles a second), sway (degrees about a hinge `hinge`
	-- studs above the look's foot, `period` seconds), cheer (a fan's hop: studs, cycles a second, phased by spot).
	-- cat: the crane cat's tail swish and head look-round while it waits (SiteKit's "Cat" model, not carried).
	-- Only within `reach` studs of the camera, at most `max` meshes a frame.
	setMotion = {
		reach = 260,
		max = 160,
		meshes = {
			TrainCars = { spin = 0.45 },
			MusicBoxDancer = { spin = 1.6, bob = 0.18, rate = 0.5 },
			ChandelierFrame = { sway = 2.2, hinge = 6.3, period = 4.2 },
			ChandelierGems = { sway = 2.2, hinge = 6.3, period = 4.2 },
			FanLegs = { cheer = 0.45, rate = 1.6 },
			FanShirt = { cheer = 0.45, rate = 1.6 },
			FanSkin = { cheer = 0.45, rate = 1.6 },
		},
		cat = { tail = 28, tailRate = 0.9, head = 22, headEvery = 3.5, breathe = 0.04 },
	},
	fov = { base = 70, leap = 1.06, boost = 1.17, blend = 6 },
	landShake = { time = 0.1, amount = 0.35, minFall = 25 },
	-- the landing crack (gap polish 2026-11-19): a comic crack decal drawn by art/fx/textures.py --cracks
	-- (art/export/fx/crack_1..3.png, preview art/preview/fx_cracks.png), uploaded from the cloud as Image assets;
	-- an id of 0 keeps the old dark disc for that variant. It fades out over the last `fade` seconds of `life`.
	crack = {
		life = 30,
		minFall = 30,
		fade = 4,
		decals = { 73304555568597, 119974560537634, 105615552551392 },
	},
	bolt = { width = 0.35, life = 0.12 },
	chain = { width = 0.5, life = 0.25, segments = 6, jitter = 1.6 },
	-- the Storm path's drawn lightning (list-combat 2026-11-20, Everything Left 167; art/fx/lightning.py): a camera-
	-- facing Beam per bolt with one of these frames (white, tinted by the path colour), switched every `flick` s
	-- while it fades over its life; `tile` studs a repeat of the strip, drawn `width` studs wide. Zap Bolt, Chain
	-- Lightning and Bolt Ride use it; an empty list keeps the part-built zigzags
	-- the held beams' drawn energy column (list-combat 2026-11-20, Everything Left 381; art/fx/energy_beam.py): a
	-- camera-facing Beam `width` studs wide (bolts `boltWidth`), `tile` studs a repeat, scrolling `speed` tiles a
	-- second toward the target (bolts twice as fast), tinted by the path colour; 0 keeps the glow cylinders
	energyBeam = { texture = 110251524477546, width = 2.6, boltWidth = 1.5, tile = 8, speed = 2.5 },
	lightning = {
		frames = { 121443883514116, 81424120668608, 127621354126477, 135751948381156 },
		tile = 9,
		width = 2.2,
		flick = 0.05,
	},
	dash = { trailLife = 0.3 },
	hitFlash = 0.1, -- the robot turns white this long on a hit (was 0.08; weighty hits)
	numbers = { rise = 3, life = 0.8, critScale = 1.5 },
	enemyDeath = { parts = 6, life = 2 },
	-- a robot shot's streak (list-combat 2026-11-20): a camera-facing Trail in the energy strip texture behind the
	-- pellet, `trail` wide and `life` seconds long, so a shot reads as a streak you can see coming
	shot = {
		width = 0.4,
		trail = 0.7,
		life = 0.16,
		-- (list-combat 2026-11-20, combat effects polish) a robot shot that meets a wall, a roof or the street stops
		-- there in a spray of sparks, a flash and a small scorch; the muzzle flashes as it fires;
		-- a net pins flat on the wall for netHold s; a famous fake's path shot splashes in its own colour
		splash = { sparks = 5, tracerSparks = 9, scorch = 1, muzzle = 2, netHold = 0.5 },
	},
	-- (list-combat 2026-11-20, combat effects polish: weak hit feedback) taking a hit: sparks spray off the hero's
	-- chest away from the robot; on your own hero a red arrow on the screen points at who hit you (`arrow`: life s,
	-- up to `pool` at once, its ring's share of the screen height), a thud (at most every `gap` s) and a shake;
	-- a melee blow or a hit of `heavy` of your max health or more is heavy: more sparks, a harder shake and thud
	hurt = {
		heavy = 0.12,
		gap = 0.08,
		arrow = { life = 0.7, pool = 4, ring = 0.62, width = 0.3, color = { 255, 40, 40 } },
		shake = { 0.12, 0.25 },
		shakeHeavy = { 0.22, 0.6 },
	},
	-- the newer robots' effects (CombatFx): the Sniper's aim laser (it thickens and blinks for the locked last
	-- part) and its tracer round, the Interceptor's net, the Grappler's hook on its cable, the Bomber's grenade
	-- (its light blinks faster as it falls), its burning patch and blast, the Medic Unit's repair beam, the
	-- Captain's rally ring and the Mimic's glitch reveal. `shake` is how near a blast shakes your camera.
	-- the famous fakes (lore step 4): a fake's face cracking within `unmaskNear` studs of you flashes your
	-- screen and freezes your hero for `unmaskPause` seconds (a hit-stop), with a camera punch
	fakes = { unmaskNear = 60, unmaskPause = 0.12 },
	robots = {
		aim = { color = { 255, 40, 40 }, width = 0.1, lockWidth = 0.3, blink = 14, dot = 0.6 },
		tracer = { color = { 255, 240, 210 }, glow = { 255, 80, 60 }, length = 14, width = 0.22 },
		net = { color = { 190, 235, 255 }, size = 4.5, spin = 8 },
		hook = { cable = 0.16, color = { 60, 60, 66 }, claw = { 200, 120, 50 }, hold = 1.6, reel = 0.2 },
		lob = { gravity = 80, size = 0.7, blink = { 4, 16 } },
		zone = { color = { 255, 110, 30 }, core = { 255, 200, 70 }, every = 0.2 },
		mend = { color = { 80, 240, 140 }, width = 0.25, packet = 0.3 },
		rally = { color = { 255, 205, 70 }, life = 0.7 },
		reveal = { colors = { { 60, 240, 255 }, { 255, 60, 220 } }, squares = 10, life = 0.4 },
		boom = { color = { 255, 150, 50 }, chunks = 5, shake = 40 },
	},
	trail = { boostLife = 0.4 },
	-- the Leap crouch's hold-to-charge rings (nate's playtest 2026-11-19): a ring at the feet every `every` s,
	-- growing from size[1] to size[2] studs as the charge fills, and a bright `full` ring once it is full
	charge = { every = 0.08, size = { 3, 12 }, full = 16 },
	voltColor = { 120, 210, 255 },
	weaponColor = { 240, 236, 225 }, -- weapon moves: a bright steel streak
	enemyShotColor = { 255, 110, 80 },
	critColor = { 255, 210, 60 },
	-- Comic style: a sound word on skill and super hits, by set (all original words)
	words = {
		Volt = { "ZAP!", "KRAK!", "BZZT!" },
		Weapon = { "WHAM!", "CLANG!", "KA-CHUNK!" }, -- weapon moves (Config.Weapons.skills)
		Frost = { "CRACK!", "FWOOSH!", "KSSH!" },
		Titan = { "POW!", "WHAM!", "KABOOM!" },
		Pulse = { "WHUMM!", "VWOOM!", "THOOM!" },
		Blade = { "SHING!", "SLASH!", "KSHHK!" },
		-- the other paths (overhaul plan step 6)
		Fire = { "FWOOM!", "SIZZLE!", "KA-BLAZE!" },
		Earth = { "KRUNCH!", "THUD!", "KA-RUMBLE!" },
		Tide = { "SPLOOSH!", "SPLASH!", "KER-SPLOOSH!" },
		Gunslinger = { "BLAM!", "PEW!", "BRAKKA-BLAM!" },
		Gadgeteer = { "VRRT!", "PING!", "KA-BLOOEY!" },
		Shadow = { "SHNK!", "FWIP!", "SHHHRAK!" },
		Martial = { "KIAI!", "WHAP!", "SHA-BOOM!" },
		Juggernaut = { "CLANK!", "KRASH!", "KRA-KOOM!" },
		Colossus = { "STOMP!", "WHUMP!", "QUAAAKE!" },
		Mind = { "VMMM!", "PSHEW!", "BRAAAM!" },
		Spirit = { "WHOOSH!", "HWOOO!", "SHA-WOOM!" },
		Light = { "TING!", "FWING!", "SHA-BLAAAM!" },
	},
	warnColor = { 255, 60, 50 }, -- enemy attack telegraphs
	awakenColor = { 255, 235, 120 },
	slashSegments = 9, -- pieces in an arc slash
	fieldPulse = 0.5, -- seconds between field pulses
	-- The effects library (overhaul plan step 3; client Fx/FxLib, rules in Shared.FxPlan): textured particles
	-- under the part-built shapes. Textures are the generated sheets (art/fx/textures.py -> art/export/fx), all
	-- uploaded (`id`; flip = the sheet's grid); `builtin` is Roblox's particle image, used only for an id of 0.
	lib = {
		textures = {
			spark = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 107600308094410,
				file = "spark.png",
			},
			glow = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 117655751672803,
				file = "glow.png",
			},
			smoke = {
				builtin = "rbxasset://textures/particles/smoke_main.dds",
				id = 117000906258524,
				file = "smoke_4x4.png",
				flip = 4,
			},
			shock = {
				builtin = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
				id = 132299060283270,
				file = "shock.png",
			},
			core = {
				builtin = "rbxasset://textures/particles/explosion01_core_main.dds",
				id = 86679814213759,
				file = "core.png",
			},
			implode = {
				builtin = "rbxasset://textures/particles/explosion01_implosion_main.dds",
				id = 106891201706039,
				file = "implode.png",
			},
			ember = {
				builtin = "rbxasset://textures/particles/fire_sparks_main.dds",
				id = 103614765572609,
				file = "ember.png",
			},
			fire = {
				builtin = "rbxasset://textures/particles/fire_main.dds",
				id = 133350968077744,
				file = "fire_4x4.png",
				flip = 4,
			},
			crackle = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 72858283666583,
				file = "electric_4x4.png",
				flip = 4,
			},
			vortex = {
				builtin = "rbxasset://textures/particles/forcefield_vortex_main.dds",
				id = 75975265289999,
				file = "vortex.png",
			},
			-- the other paths (overhaul plan step 6): each path's own particle shape
			flake = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 117086646945232,
				file = "flake.png",
			},
			bubble = {
				builtin = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
				id = 79950084877027,
				file = "bubble.png",
			},
			rock = {
				builtin = "rbxasset://textures/particles/smoke_main.dds",
				id = 91634714206088,
				file = "rock.png",
			},
			leaf = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 71055974786369,
				file = "leaf.png",
			},
			glyph = {
				builtin = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
				id = 115550231455861,
				file = "glyph.png",
			},
			slash = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 80607054467730,
				file = "slash.png",
			},
			star = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 138717851916937,
				file = "star.png",
			},
			hex = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 124065226973490,
				file = "hex.png",
			},
			ink = {
				builtin = "rbxasset://textures/particles/smoke_main.dds",
				id = 86085731469540,
				file = "ink.png",
			},
			-- every ability's own look (nate's playtest 2026-11-19, Config.FxMoves): a ground rune circle and a
			-- scorch mark, drawn by art/fx/textures.py --moves, uploaded from the cloud 2026-11-19 (Image assets).
			rune = {
				builtin = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
				id = 125111477106243,
				file = "rune.png",
			},
			scorch = {
				builtin = "rbxasset://textures/particles/smoke_main.dds",
				id = 131428080752757,
				file = "scorch.png",
			},
			-- a downed robot's loose nut (gap-wrecks, 2026-11-19: the wreck's pop, art/fx/textures.py --wrecks; uploaded
			-- from the cloud as an Image asset)
			bolt = {
				builtin = "rbxasset://textures/particles/smoke_main.dds",
				id = 127209369475474,
				file = "bolt.png",
			},
			-- a chunk of rubble off a throw landing or a wall smash (gap-fx3, 2026-11-19: art/fx/textures.py --chips;
			-- uploaded from the cloud as an Image asset), tinted in the ground's or the wall's colour
			chip = {
				builtin = "rbxasset://textures/particles/smoke_main.dds",
				id = 133274880401189,
				file = "chip.png",
			},
			-- the comic hit star (list-combat 2026-11-20, art/fx/hitstar.py; uploaded from the cloud as an Image asset): a
			-- jagged starburst in a black ink rim that pops on every Comic hit, tinted in the hit colour
			hitstar = {
				builtin = "rbxasset://textures/particles/sparkles_main.dds",
				id = 102945056980891,
				file = "hitstar.png",
			},
		},
		-- each particle kind: size from and to (studs), life (s, min max), speed (min max), spread (deg),
		-- drag, rise (upward acceleration, negative falls), light (emission), alpha (start transparency),
		-- spin (deg a second), face: "camera" (default), "streak" (along its velocity) or "flat" (lies flat)
		kinds = {
			-- one comic hit star a Comic hit (CombatFx.impact): pops from a fifth of its size to full and fades, a
			-- little turn; light 0 so its ink rim stays black
			hitstar = {
				tex = "hitstar",
				size = { 1, 4 },
				life = { 0.14, 0.18 },
				speed = { 0, 0 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 0,
				alpha = 0,
				spin = 60,
			},
			-- a weighty hit's spray (CombatFx.hitSparks, 2026-11-20: was part-built bars): hot streaks out of the hit
			-- along its direction, falling a little
			hitspark = {
				tex = "spark",
				size = { 0.7, 0 },
				life = { 0.25, 0.4 },
				speed = { 18, 38 },
				spread = 45,
				drag = 4,
				rise = -25,
				light = 1,
				alpha = 0,
				face = "streak",
			},
			spark = {
				tex = "spark",
				size = { 0.5, 0 },
				life = { 0.22, 0.4 },
				speed = { 22, 46 },
				spread = 180,
				drag = 5,
				rise = -30,
				light = 1,
				alpha = 0,
				face = "streak",
			},
			crackle = {
				tex = "crackle",
				size = { 1.4, 0.4 },
				life = { 0.08, 0.16 },
				speed = { 0, 4 },
				spread = 180,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0,
				spin = 400,
			},
			glow = {
				tex = "glow",
				size = { 1.5, 7 },
				life = { 0.12, 0.18 },
				speed = { 0, 0 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0.15,
			},
			core = {
				tex = "core",
				size = { 2, 9 },
				life = { 0.18, 0.26 },
				speed = { 0, 0 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0.1,
				spin = 90,
			},
			smoke = {
				tex = "smoke",
				size = { 2, 6 },
				life = { 0.8, 1.3 },
				speed = { 3, 9 },
				spread = 180,
				drag = 2,
				rise = 3,
				light = 0,
				alpha = 0.45,
				spin = 40,
			},
			dust = {
				tex = "smoke",
				size = { 3, 9 },
				life = { 0.9, 1.4 },
				speed = { 10, 18 },
				spread = 25,
				drag = 3,
				rise = 1,
				light = 0,
				alpha = 0.35,
				spin = 30,
			},
			-- the Smoke Bomb's cloud (gap polish 2026-11-19, GadgetFx): big slow puffs that hang over the blinded
			-- area, topped up while it lasts (Config.Fx.polish.smoke)
			cloud = {
				tex = "smoke",
				size = { 5, 13 },
				life = { 1.6, 2.2 },
				speed = { 1, 3 },
				spread = 180,
				drag = 1.5,
				rise = 1.2,
				light = 0,
				alpha = 0.25,
				spin = 20,
			},
			ember = {
				tex = "ember",
				size = { 0.6, 0.1 },
				life = { 0.5, 0.9 },
				speed = { 6, 18 },
				spread = 180,
				drag = 2,
				rise = 10,
				light = 1,
				alpha = 0,
			},
			flame = {
				tex = "fire",
				size = { 2.5, 0.5 },
				life = { 0.3, 0.5 },
				speed = { 4, 10 },
				spread = 180,
				drag = 3,
				rise = 12,
				light = 0.8,
				alpha = 0.1,
			},
			shard = {
				tex = "spark",
				size = { 0.8, 0.2 },
				life = { 0.3, 0.55 },
				speed = { 18, 34 },
				spread = 180,
				drag = 3,
				rise = -40,
				light = 0.6,
				alpha = 0,
				face = "streak",
				spin = 200,
			},
			-- a downed robot's nuts and bits (gap-wrecks, 2026-11-19): tumble out, fall and bounce away; tinted
			-- in the robot's suit and metal colours, never bright
			bolt = {
				tex = "bolt",
				size = { 0.55, 0.4 },
				life = { 0.55, 0.85 },
				speed = { 12, 22 },
				spread = 70,
				drag = 1.5,
				rise = -55,
				light = 0,
				alpha = 0,
				spin = 420,
			},
			-- rubble chips off a throw landing or a wall smash (gap-fx3, 2026-11-19): kicked out, tumbling, falling
			-- fast; tinted in the ground's or wall's own colour, never bright
			chip = {
				tex = "chip",
				size = { 1.5, 1.1 },
				life = { 0.6, 1 },
				speed = { 16, 32 },
				spread = 55,
				drag = 1.2,
				rise = -70,
				light = 0,
				alpha = 0,
				spin = 360,
			},
			wisp = {
				tex = "glow",
				size = { 1.2, 0 },
				life = { 0.5, 0.9 },
				speed = { 3, 8 },
				spread = 180,
				drag = 1,
				rise = 6,
				light = 1,
				alpha = 0.2,
			},
			vortex = {
				tex = "vortex",
				size = { 6, 1 },
				life = { 0.3, 0.4 },
				speed = { 0, 0 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0.2,
				spin = 360,
			},
			implode = {
				tex = "implode",
				size = { 7, 1 },
				life = { 0.35, 0.45 },
				speed = { 0, 0 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0.2,
			},
			shock = {
				tex = "shock",
				size = { 1, 1 },
				life = { 0.32, 0.32 },
				speed = { 0.01, 0.01 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0.1,
				face = "flat",
			},
			-- the other paths (overhaul plan step 6)
			flake = { -- Frost: snowflakes that drift down
				tex = "flake",
				size = { 0.8, 0.3 },
				life = { 0.6, 1.1 },
				speed = { 4, 12 },
				spread = 180,
				drag = 2,
				rise = -8,
				light = 0.8,
				alpha = 0,
				spin = 120,
			},
			bubble = { -- Tide: bubbles that swell and rise
				tex = "bubble",
				size = { 0.5, 1.3 },
				life = { 0.5, 0.9 },
				speed = { 4, 10 },
				spread = 180,
				drag = 2,
				rise = 8,
				light = 0.3,
				alpha = 0.15,
			},
			rock = { -- Earth, Colossus, Titan: chunks that tumble and fall
				tex = "rock",
				size = { 1.3, 0.9 },
				life = { 0.5, 0.8 },
				speed = { 14, 26 },
				spread = 70,
				drag = 1,
				rise = -60,
				light = 0,
				alpha = 0,
				spin = 300,
			},
			leaf = { -- Earth: leaves off the vines
				tex = "leaf",
				size = { 0.9, 0.7 },
				life = { 0.8, 1.2 },
				speed = { 6, 14 },
				spread = 180,
				drag = 2,
				rise = -6,
				light = 0.2,
				alpha = 0,
				spin = 220,
			},
			glyph = { -- Mind, Spirit: one sigil that opens and fades
				tex = "glyph",
				size = { 2, 8 },
				life = { 0.45, 0.55 },
				speed = { 0, 0 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0.15,
				spin = 60,
			},
			slash = { -- Blade: thin cuts streaking out
				tex = "slash",
				size = { 3, 0.8 },
				life = { 0.12, 0.2 },
				speed = { 18, 30 },
				spread = 180,
				drag = 6,
				rise = 0,
				light = 1,
				alpha = 0,
				face = "streak",
			},
			star = { -- Light, Martial, Gunslinger, Titan: a twinkle
				tex = "star",
				size = { 1.6, 0 },
				life = { 0.2, 0.35 },
				speed = { 0, 6 },
				spread = 180,
				drag = 2,
				rise = 0,
				light = 1,
				alpha = 0,
				spin = 180,
			},
			hex = { -- Gadgeteer: little hexagon plates
				tex = "hex",
				size = { 0.8, 0.3 },
				life = { 0.35, 0.6 },
				speed = { 8, 18 },
				spread = 180,
				drag = 3,
				rise = -10,
				light = 1,
				alpha = 0,
				spin = 200,
			},
			ink = { -- Shadow: dark ink blots
				tex = "ink",
				size = { 1.4, 2.8 },
				life = { 0.5, 0.8 },
				speed = { 6, 14 },
				spread = 180,
				drag = 3,
				rise = -20,
				light = 0,
				alpha = 0.1,
				spin = 60,
			},
			-- every ability's own look (Config.FxMoves): both lie flat on the ground
			rune = { -- a rune circle that opens under a target or the caster's feet
				tex = "rune",
				size = { 3, 9 },
				life = { 0.5, 0.6 },
				speed = { 0.01, 0.01 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 1,
				alpha = 0.1,
				spin = 90,
				face = "flat",
			},
			scorch = { -- a dark scorch mark that lingers in a crater
				tex = "scorch",
				size = { 5, 7 },
				life = { 1.4, 1.8 },
				speed = { 0.01, 0.01 },
				spread = 0,
				drag = 0,
				rise = 0,
				light = 0,
				alpha = 0.2,
				spin = 10,
				face = "flat",
			},
		},
		-- what each element adds: on a hit (impact), along a bolt or beam (trail), at an area (burst), while a
		-- skill charges or a windup builds (charge) and at a super's big moment (super), and how many of each
		-- (counts are at the high preset; lower presets and the budget scale them down). Every path has its own
		-- element (overhaul plan step 6); weapons stay steel, energy is the fallback.
		elements = {
			electric = {
				impact = { spark = 10, crackle = 3, glow = 1 },
				trail = { crackle = 1, spark = 2 },
				burst = { spark = 24, crackle = 6, core = 1 },
				charge = { crackle = 1, spark = 3 },
				super = { spark = 30, crackle = 8, core = 1 },
			},
			ice = {
				impact = { shard = 8, flake = 3, glow = 1 },
				trail = { shard = 1, flake = 1 },
				burst = { shard = 20, flake = 10, smoke = 4, glow = 1 },
				charge = { flake = 2, shard = 1 },
				super = { flake = 30, shard = 16, smoke = 6, glow = 1 },
			},
			fire = {
				impact = { flame = 3, ember = 8, glow = 1 },
				trail = { flame = 1, ember = 2 },
				burst = { flame = 8, ember = 18, smoke = 5, core = 1 },
				charge = { ember = 3, flame = 1 },
				super = { flame = 14, ember = 30, smoke = 8, core = 1 },
			},
			earth = {
				impact = { dust = 2, rock = 5, shard = 2 },
				trail = { dust = 1, rock = 1 },
				burst = { dust = 8, rock = 12, leaf = 4 },
				charge = { rock = 2, dust = 1 },
				super = { leaf = 24, rock = 12, dust = 8 },
			},
			water = {
				impact = { shard = 6, bubble = 4, smoke = 1 },
				trail = { bubble = 1, shard = 1 },
				burst = { shard = 16, bubble = 10, smoke = 4 },
				charge = { bubble = 3 },
				super = { bubble = 20, shard = 24, smoke = 8 },
			},
			blade = {
				impact = { spark = 8, slash = 2, glow = 1 },
				trail = { slash = 1 },
				burst = { spark = 16, slash = 6 },
				charge = { spark = 2 },
				super = { slash = 12, spark = 24, glow = 1 },
			},
			ballistic = { -- bright brass sparks and twinkles; a little smoke only on the big ones
				impact = { spark = 7, star = 2 },
				trail = { spark = 1 },
				burst = { spark = 14, smoke = 3, star = 2 },
				charge = { spark = 2 },
				super = { star = 6, spark = 20, smoke = 4 },
			},
			tech = {
				impact = { spark = 6, hex = 4, glow = 1 },
				trail = { spark = 1, hex = 1 },
				burst = { spark = 14, hex = 10, core = 1 },
				charge = { hex = 2 },
				super = { hex = 24, spark = 16, core = 1 },
			},
			shadow = {
				impact = { smoke = 3, wisp = 3, ink = 3 },
				trail = { smoke = 1, ink = 1 },
				burst = { smoke = 8, wisp = 8, ink = 6, vortex = 1 },
				charge = { wisp = 2, smoke = 1 },
				super = { ink = 16, smoke = 12, wisp = 12, vortex = 1 },
			},
			force = {
				impact = { glow = 1, dust = 1, spark = 5, star = 1 },
				trail = { glow = 1 },
				burst = { dust = 8, core = 1, spark = 12, rock = 4 },
				charge = { dust = 1, glow = 1 },
				super = { dust = 14, rock = 10, core = 1, star = 3 },
			},
			ki = {
				impact = { star = 2, wisp = 4, glow = 1 },
				trail = { wisp = 2, flame = 1 },
				burst = { flame = 6, wisp = 12, star = 3, core = 1 },
				charge = { flame = 2, wisp = 2 },
				super = { flame = 12, star = 6, wisp = 18, core = 1 },
			},
			iron = { -- a shower of sparks off steel (the hot orange is in CombatFx's clang mark)
				impact = { spark = 10, star = 2, glow = 1 },
				trail = { dust = 1, spark = 1 },
				burst = { spark = 16, dust = 4, smoke = 2 },
				charge = { smoke = 1, spark = 1 },
				super = { smoke = 10, spark = 20, dust = 8 },
			},
			giant = {
				impact = { rock = 4, dust = 2 },
				trail = { dust = 1 },
				burst = { rock = 12, dust = 10, core = 1 },
				charge = { dust = 2, rock = 1 },
				super = { rock = 18, dust = 14, core = 1 },
			},
			gravity = {
				impact = { implode = 1, wisp = 4, glow = 1 },
				trail = { wisp = 1 },
				burst = { implode = 1, vortex = 1, wisp = 14 },
				charge = { wisp = 2, implode = 1 },
				super = { vortex = 1, implode = 1, wisp = 24, dust = 6 },
			},
			psychic = {
				impact = { vortex = 1, wisp = 3, glyph = 1 },
				trail = { wisp = 1 },
				burst = { vortex = 1, wisp = 12, glyph = 1 },
				charge = { wisp = 2, glyph = 1 },
				super = { glyph = 1, vortex = 1, wisp = 20, rock = 6 },
			},
			spirit = {
				impact = { wisp = 5, flame = 1, glow = 1 },
				trail = { wisp = 2 },
				burst = { wisp = 16, flame = 4, glow = 1 },
				charge = { wisp = 3 },
				super = { wisp = 24, flame = 8, glyph = 1, glow = 1 },
			},
			light = {
				impact = { glow = 1, spark = 6, star = 2 },
				trail = { spark = 2, star = 1 },
				burst = { core = 1, spark = 18, wisp = 8, star = 3 },
				charge = { star = 1, spark = 2 },
				super = { core = 1, star = 8, spark = 24, wisp = 10 },
			},
			steel = {
				impact = { spark = 8, glow = 1 },
				trail = { spark = 1 },
				burst = { spark = 16, dust = 3 },
				charge = { spark = 2 },
				super = { spark = 20, dust = 4 },
			},
			energy = {
				impact = { glow = 1, wisp = 5 },
				trail = { wisp = 2 },
				burst = { wisp = 14, vortex = 1, core = 1 },
				charge = { wisp = 2 },
				super = { wisp = 20, vortex = 1, core = 1 },
			},
		},
		setElement = {
			Volt = "electric",
			Frost = "ice",
			Fire = "fire",
			Earth = "earth",
			Tide = "water",
			Blade = "blade",
			Gunslinger = "ballistic",
			Gadgeteer = "tech",
			Shadow = "shadow",
			Titan = "force",
			Martial = "ki",
			Juggernaut = "iron",
			Colossus = "giant",
			Pulse = "gravity",
			Mind = "psychic",
			Spirit = "spirit",
			Light = "light",
			Weapon = "steel",
		},
		-- weapon moves by their look (Config.Fx.weaponLooks; the set "Weapon:<look>")
		weaponElement = {
			fists = "force",
			edge = "blade",
			heavy = "giant",
			blunt = "iron",
			pole = "ki",
			shield = "iron",
			shot = "ballistic",
			arrow = "steel",
			thrown = "blade",
			tether = "steel",
			wind = "spirit",
		},
		-- particles a second this device may emit (a burst over the budget is trimmed, never queued), and the
		-- share of each count a preset draws
		budget = { low = 220, medium = 520, high = 1100 },
		-- a downed robot's wreck (WP6; gap-wrecks, 2026-11-19, ThrowFx through FxLib, counts before the preset's
		-- share, inside the budget above): `spark` every Config.Throw.wreck.sparkEvery s near the camera (its
		-- dead eyes light for `flicker` s), `pop` when it falls apart (bolts half in the suit colour, half metal)
		wreck = {
			spark = { spark = 5, crackle = 1 },
			pop = { bolt = 12, spark = 16, smoke = 4, core = 1, crackle = 1 },
			flicker = 0.12,
		},
		-- throws and rams (gap-fx3, 2026-11-19; ThrowFx and ImpactFx through FxLib, counts before the preset's share,
		-- inside the budget above; once plain parts): `grab` a puff at the lifter's feet, `land_<weight>` where a
		-- thrown thing crashes down (a dust ring, puffs and chips in the dust colour), `back` the shine when a prop
		-- comes home, `smash` a wall broken by a ram or a thrown hero (chips in the wall's colour, a puff of dust)
		throw = {
			grab = { dust = 3 },
			land_light = { shock = 1, dust = 4, chip = 5 },
			land_medium = { shock = 1, dust = 6, chip = 9 },
			land_heavy = { shock = 1, dust = 10, chip = 16 },
			back = { glow = 1, star = 6 },
			smash = { chip = 14, dust = 4 },
		},
		scale = { low = 0.4, medium = 0.7, high = 1 },
		-- a super's whole moment (its burst, its own particles and crits on superTargets robots) must fit in this
		-- share of a second's budget on every preset, so the fight around it still has room (tests check)
		superShare = 0.6,
		superTargets = 6,
		-- the path pieces (part-built heads, marks, motes; CombatFx's path section) a second, per preset
		partBudget = { low = 70, medium = 150, high = 260 },
		comicSize = 1.25, -- Comic: chunkier particles and pieces; Anime: thinner, whiter, faster
		animeSpeed = 1.3,
		shockRadii = { 6, 12, 20, 32, 50 }, -- shockwave rings come in these sizes (the nearest one is used)
		trailStep = 8, -- studs between trail emissions along a bolt or beam
		trailMax = 8,
	},
	-- Every path's own look (overhaul plan step 6), drawn by CombatFx's path section over the shapes and
	-- FxLib's particles; the rules are in Shared.FxPlan and tests check every row. Volt is the slice nate
	-- OKed and keeps its look (only its charge motes are new). PLACEHOLDER ART: part-built until the VFX pass.
	--   piece   the path's own part-built piece: it kicks out of swings, sweeps across cones, rings out of novas
	--           and trails dashes (Volt's is none: its shapes stay as they were)
	--   accent  a second colour (hot cores, foam, rims, ink)
	--   head    what flies on bolts, chain hops and lines
	--   mark    the hit's own mark on top of the element's particles
	--   cast    a flourish on the caster for skills and supers
	--   dash    a dash's trail (and others' view of a leap)
	--   field   what drifts in a lasting area: a piece and how it moves (fall, rise, swirl, orbit, pop)
	--   charge  the motes that gather while a skill charges, a windup builds or a super is aimed
	--   super   the super's big moment (look) and the screen tint for its caster
	-- The names each list may use are FxPlan.HEADS, MARKS, CASTS, DASHES, MOTIONS, PIECES and SUPERS.
	paths = {
		Volt = {
			piece = "none",
			accent = { 235, 250, 255 },
			head = "none",
			mark = "none",
			cast = "none",
			dash = "none",
			field = { piece = "none", motion = "rise" },
			charge = { piece = "ball", n = 4, radius = 2.4, spin = 9 },
			super = { look = "none", tint = { 120, 210, 255 } },
		},
		Frost = {
			piece = "shard",
			accent = { 255, 255, 255 },
			head = "spike",
			mark = "crystals",
			cast = "frostring",
			dash = "none",
			field = { piece = "flake", motion = "fall" },
			charge = { piece = "shard", n = 5, radius = 2.6, spin = 3 },
			super = { look = "icecrown", tint = { 190, 235, 255 } },
		},
		Fire = {
			piece = "flame",
			accent = { 255, 230, 120 },
			head = "fireball",
			mark = "puff",
			cast = "flare",
			dash = "trail",
			field = { piece = "ember", motion = "rise" },
			charge = { piece = "ember", n = 6, radius = 2.2, spin = 5 },
			super = { look = "sunfall", tint = { 255, 140, 50 } },
		},
		Earth = {
			piece = "rock",
			accent = { 120, 190, 90 },
			head = "rock",
			mark = "rubble",
			cast = "stomp",
			dash = "trail",
			field = { piece = "rock", motion = "swirl" },
			charge = { piece = "rock", n = 5, radius = 2.8, spin = 2 },
			super = { look = "overgrowth", tint = { 130, 200, 90 } },
		},
		Tide = {
			piece = "drop",
			accent = { 225, 250, 255 },
			head = "glob",
			mark = "crown",
			cast = "swirl",
			dash = "none",
			field = { piece = "drop", motion = "fall" },
			charge = { piece = "drop", n = 6, radius = 2.4, spin = 6 },
			super = { look = "tsunami", tint = { 40, 150, 255 } },
		},
		Blade = {
			piece = "shard",
			accent = { 255, 255, 255 },
			head = "none",
			mark = "cross",
			cast = "glint",
			dash = "afterimage",
			field = { piece = "shard", motion = "orbit" },
			charge = { piece = "shard", n = 3, radius = 2, spin = 8 },
			super = { look = "splitter", tint = { 255, 70, 90 } },
		},
		Gunslinger = {
			piece = "ember",
			accent = { 255, 250, 220 },
			head = "tracer",
			mark = "ricochet",
			cast = "muzzle",
			dash = "smoke",
			field = { piece = "ring", motion = "pop" },
			charge = { piece = "ball", n = 6, radius = 1.6, spin = 10 },
			super = { look = "highnoon", tint = { 255, 200, 70 } },
		},
		Gadgeteer = {
			piece = "plate",
			accent = { 220, 255, 240 },
			head = "plasma",
			mark = "hexes",
			cast = "reticle",
			dash = "none",
			field = { piece = "plate", motion = "orbit" },
			charge = { piece = "plate", n = 4, radius = 2.6, spin = 4 },
			super = { look = "mechdrop", tint = { 90, 230, 160 } },
		},
		Shadow = {
			piece = "kunai",
			accent = { 24, 18, 36 },
			head = "kunai",
			mark = "ink",
			cast = "smoke",
			dash = "afterimage",
			field = { piece = "ember", motion = "rise" },
			charge = { piece = "kunai", n = 4, radius = 2.4, spin = 7 },
			super = { look = "eclipse", tint = { 60, 30, 110 } },
		},
		Titan = {
			piece = "rock",
			accent = { 255, 240, 200 },
			head = "none",
			mark = "pow",
			cast = "crack",
			dash = "plow",
			field = { piece = "none", motion = "rise" },
			charge = { piece = "ember", n = 5, radius = 1.6, spin = 4 },
			super = { look = "meteor", tint = { 255, 150, 60 } },
		},
		Martial = {
			piece = "flame",
			accent = { 255, 255, 240 },
			head = "kiorb",
			mark = "kiring",
			cast = "aura",
			dash = "afterimage",
			field = { piece = "none", motion = "rise" },
			charge = { piece = "flame", n = 6, radius = 1.8, spin = 6 },
			super = { look = "heavenfall", tint = { 255, 225, 120 } },
		},
		Juggernaut = {
			piece = "plate",
			accent = { 255, 120, 60 },
			head = "none",
			mark = "clang",
			cast = "steam",
			dash = "plow",
			field = { piece = "ember", motion = "rise" },
			charge = { piece = "plate", n = 4, radius = 2.2, spin = 2 },
			super = { look = "siege", tint = { 150, 160, 175 } },
		},
		Colossus = {
			piece = "rock",
			accent = { 255, 200, 150 },
			head = "boulder",
			mark = "quake",
			cast = "footprint",
			dash = "plow",
			field = { piece = "rock", motion = "pop" },
			charge = { piece = "rock", n = 6, radius = 3.2, spin = 1.5 },
			super = { look = "titanrise", tint = { 230, 90, 60 } },
		},
		Pulse = {
			piece = "ring",
			accent = { 40, 20, 70 },
			head = "lens",
			mark = "warp",
			cast = "rings",
			dash = "none",
			field = { piece = "ball", motion = "swirl" },
			charge = { piece = "ring", n = 3, radius = 2.4, spin = 5 },
			super = { look = "singularity", tint = { 110, 60, 200 } },
		},
		Mind = {
			piece = "tri",
			accent = { 255, 230, 250 },
			head = "psiring",
			mark = "sigil",
			cast = "eye",
			dash = "none",
			field = { piece = "tri", motion = "orbit" },
			charge = { piece = "tri", n = 3, radius = 2.2, spin = 4 },
			super = { look = "psistorm", tint = { 255, 110, 210 } },
		},
		Spirit = {
			piece = "flame",
			accent = { 230, 255, 250 },
			head = "wisp",
			mark = "soulflare",
			cast = "guardian",
			dash = "trail",
			field = { piece = "flame", motion = "rise" },
			charge = { piece = "flame", n = 5, radius = 2.6, spin = 3 },
			super = { look = "ascend", tint = { 110, 255, 230 } },
		},
		Light = {
			piece = "spike",
			accent = { 255, 255, 255 },
			head = "lance",
			mark = "prism",
			cast = "halo",
			dash = "none",
			field = { piece = "spike", motion = "orbit" },
			charge = { piece = "spike", n = 8, radius = 3.2, spin = 1.5 },
			super = { look = "dawn", tint = { 255, 245, 200 } },
		},
	},

	-- Weapon moves' own looks (the weapons polish pass, 2026-11-19; the follow-up "weapon moves still use the
	-- steel power visuals"): each weapon draws its family's look or its own, with a colour, an element for the
	-- effects library and the same piece, head, mark and dash names the paths use (CombatFx). CombatClient hands
	-- the effects the set "Weapon:<look>" (Shared.FxPlan.weaponSet); FxPlan.pathOf finds the row here, so a
	-- weapon move never looks like a power path. The rows carry every field a path row has (nothing extra draws
	-- on a cast, a field or a super). PLACEHOLDER ART: part-built like the paths.
	weaponLooks = {
		looks = {
			fists = {
				color = { 255, 214, 150 },
				piece = "ball",
				head = "none",
				mark = "pow",
				dash = "afterimage",
				words = { "WHAP!", "THWACK!", "KA-POW!" },
			},
			edge = {
				color = { 205, 232, 255 },
				piece = "shard",
				head = "none",
				mark = "cross",
				dash = "afterimage",
				words = { "SHING!", "SLICE!", "KSHAAANG!" },
			},
			heavy = {
				color = { 255, 190, 120 },
				piece = "rock",
				head = "none",
				mark = "quake",
				dash = "plow",
				words = { "KRUNCH!", "WHOMP!", "KA-THOOM!" },
			},
			blunt = {
				color = { 255, 205, 110 },
				piece = "plate",
				head = "none",
				mark = "clang",
				dash = "plow",
				words = { "BONK!", "CLONK!", "KA-DONG!" },
			},
			pole = {
				color = { 190, 255, 205 },
				piece = "spike",
				head = "none",
				mark = "kiring",
				dash = "afterimage",
				words = { "THWIP!", "WHIRR!", "KA-THUNK!" },
			},
			shield = {
				color = { 150, 200, 255 },
				piece = "plate",
				head = "none",
				mark = "clang",
				dash = "plow",
				words = { "CLANG!", "BWONG!", "KA-BLANG!" },
			},
			shot = {
				color = { 120, 240, 255 },
				piece = "ember",
				head = "tracer",
				mark = "ricochet",
				dash = "smoke",
				words = { "PEW!", "ZAP!", "KA-BLAM!" },
			},
			arrow = {
				color = { 205, 255, 140 },
				piece = "spike",
				head = "spike",
				mark = "cross",
				dash = "afterimage",
				words = { "THWIP!", "THUNK!", "FWASHOOM!" },
			},
			thrown = {
				color = { 230, 220, 255 },
				piece = "kunai",
				head = "kunai",
				mark = "cross",
				dash = "afterimage",
				words = { "SHUNK!", "WHIZZ!", "SHA-SHUNK!" },
			},
			tether = {
				color = { 255, 150, 220 },
				piece = "ball",
				head = "none",
				mark = "kiring",
				dash = "afterimage",
				words = { "CRACK!", "SNAP!", "KA-WHIP!" },
			},
			wind = {
				color = { 170, 255, 235 },
				piece = "flake",
				head = "none",
				mark = "warp",
				dash = "afterimage",
				words = { "FWOOSH!", "SWISH!", "HWOOOSH!" },
			},
		},
		-- by family, then the weapons that read their own way (weapon ids, Config.Weapons.list)
		family = {
			fists = "fists",
			one = "edge",
			two = "heavy",
			dual = "edge",
			shield = "shield",
			ranged = "shot",
			exotic = "tether",
		},
		weapon = {
			[8] = "blunt", -- Mace
			[9] = "blunt", -- Baton
			[13] = "blunt", -- Warhammer
			[14] = "pole", -- Spear
			[16] = "pole", -- Bo Staff
			[20] = "blunt", -- Tonfa
			[24] = "edge", -- Sword and Shield
			[28] = "arrow", -- Bow
			[29] = "arrow", -- Crossbow
			[31] = "thrown", -- Throwing Stars
			[33] = "wind", -- War Fan
			[36] = "thrown", -- Boomerang
		},
	},
	-- Gap polish (2026-11-19): the fast-travel flight, the gadgets, the ice pieces and the thrown crate. Numbers
	-- for Shared.PolishPlan and the client (TravelClient, GadgetFx, IceFx, CombatFx.throwArc); `presets` is the
	-- per device preset budget (phones on low draw less).
	polish = {
		travel = {
			dive = 80, -- the hero leaves the flight diving this fast, so the landing is the hard superhero landing
			hold = 150, -- farther than this (plus half a second of flight) from the route: hold still until it lands
			camBack = 30, -- the follow camera: this far behind, this high, looking this far ahead
			camUp = 10,
			camAhead = 14,
			trail = { width = 3.4, life = { low = 0.35, medium = 0.6, high = 0.8 }, kit = "comet" },
		},
		smoke = {
			puffEvery = 0.45, -- the cloud is topped up this often while the blind lasts
			color = { 168, 170, 182 },
			edge = { 120, 122, 136 },
		},
		decoy = {
			color = { 150, 210, 255 }, -- the hologram's tint (a Highlight on medium and high)
			flickerFrom = 0.7, -- the share of its life after which the flicker gets strong
			popColor = { 170, 225, 255 },
		},
		drone = {
			radius = 5, -- the shield drone circles the hero this far out (outside its bubble), this high, this fast (turns a second)
			height = 2.6,
			spin = 0.5,
			bubble = 4.2, -- the shield bubble's radius
			color = { 120, 220, 255 },
		},
		ice = {
			color = { 186, 228, 255 },
			deep = { 110, 180, 235 },
			snow = { 244, 250, 255 },
		},
		presets = {
			low = {
				smoke = 6,
				smokeRing = 0,
				decoyGlow = false,
				frost = 0,
				shards = 2,
				droneBits = false,
				trail = true,
			},
			medium = {
				smoke = 10,
				smokeRing = 1,
				decoyGlow = true,
				frost = 3,
				shards = 3,
				droneBits = true,
				trail = true,
			},
			high = {
				smoke = 14,
				smokeRing = 1,
				decoyGlow = true,
				frost = 6,
				shards = 4,
				droneBits = true,
				trail = true,
			},
		},
	},
}
