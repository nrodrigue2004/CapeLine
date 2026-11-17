-- Robots (and later citizens) as plain Roblox characters (nate, 2026-11-17: "i want the characters to feel like
-- roblox but not the combat or the environment"): the blocky R15 body, a classic clothes image (Roblox's Shirt and
-- Pants templates side by side, art/clothes/uniforms.py), a face decal that swaps to the
-- turned face, and real Roblox hair from the catalog (free items made by Roblox, loaded by the server with
-- InsertService and checked to be Roblox's own). nate is trying both looks in game (Dev panel "Robots:"): this
-- one and the Blender superhero shell (Config.Enemies body.art).
return {
	-- which look robots wear: "auto" = these clothes once their images are uploaded, else the Blender shell once
	-- imported, else the plain look; "roblox", "shell" and "plain" force one (the Dev panel cycles them)
	style = "auto",
	-- +1, or -1 if Studio shows the clothes shifted the wrong way on every face (one number fixes them all)
	offsetSign = 1,
	-- free Roblox-made hair (catalog ids; the server skips any that fail to load or are not made by Roblox)
	hairs = {
		BrownCharmer = 376548738,
		BlondeSpiked = 376524487,
		BlackPonytail = 376527350,
		Pal = 63690008,
		LavenderUpdo = 451220849,
		LongRed = 2956239660,
	},
	-- the faces every robot shares (art/clothes/faces.py, comic-book style; nate: "not super kiddish"): the
	-- uploaded image ids of each face and its turned version (0 until uploaded; a face with no id is skipped).
	-- A robot picks one by its id, so the same kind looks different robot to robot.
	-- `cracked` (lore step 4): the face a famous fake shows once unmasked, half torn away to a metal plate with a
	-- glowing eye (Face_<Name>_Cracked.png; PLACEHOLDER ART until uploaded: a part-built crack overlay shows then)
	faces = {
		Hero = { human = 133484834811069, turned = 91030559134106, cracked = 75700481415234 },
		Stern = { human = 71517229731763, turned = 116208968937100, cracked = 133605760520870 },
		Sharp = { human = 77935805270769, turned = 130155254650366, cracked = 91406047209259 },
		Scarred = { human = 124504020000182, turned = 135498571181216, cracked = 118349164009362 },
		Rookie = { human = 102156518738098, turned = 109293108603661, cracked = 111997856507457 },
		Cold = { human = 74497624847653, turned = 72204836895000, cracked = 112851438053889 },
	},
	faceOrder = { "Hero", "Stern", "Sharp", "Scarred", "Rookie", "Cold" },
	-- every robot kind's uniform comes in three versions (nate, 2026-11-17: "Dont want enemies to get
	-- repetitive"), drawn by art/clothes/uniforms.py: each robot picks one by its id at these odds (out of 10),
	-- so most are Grunts, some Veterans and a few Elites. Only the versions with an uploaded image are picked.
	versions = { "Grunt", "Veteran", "Elite" },
	versionOdds = { Grunt = 6, Veteran = 3, Elite = 1 },
	-- per robot kind (Config.Enemies key): each version's uploaded clothes image id (0 until nate uploads
	-- art/export/clothes/uniforms/<Kind>_<Version>.png; the Grunt Spark Trooper is Trooper_Clothes.png) and the
	-- hairs it may wear (one picked per robot by its id). With the six faces and the skins that makes every
	-- robot of a kind look like a different person.
	robots = {
		-- Spark Trooper: the blue jet suit; veterans white shoulders and chevrons, elites navy and gold
		SparkDrone = {
			clothes = { Grunt = 75412471248820, Veteran = 119251902662277, Elite = 93575353816776 },
			hair = { "BrownCharmer", "BlondeSpiked", "Pal" },
		},
		-- Burglar Bot: a striped top and a loot strap (grey, red, then black and gold)
		BurglarBot = {
			clothes = { Grunt = 103865735736820, Veteran = 136600732911957, Elite = 117882907071898 },
			hair = { "Pal", "BrownCharmer", "LongRed" },
		},
		-- Sneak Bot: a wrapped stealth suit with a sash (purple, ice blue, then black and red)
		SneakBot = {
			clothes = { Grunt = 84836148007377, Veteran = 87282480614941, Elite = 100569194395596 },
			hair = { "BlackPonytail", "LavenderUpdo", "BlondeSpiked" },
		},
		-- Brute Bot: a sleeveless brawler's top, champion's belt, wrist wraps
		BruteBot = {
			clothes = { Grunt = 102749556863478, Veteran = 138255201065410, Elite = 107003406606377 },
			hair = { "BrownCharmer", "Pal", "BlondeSpiked" },
		},
		-- Sentry: a security guard's uniform with the shield badge and armband
		Turret = {
			clothes = { Grunt = 115536862963665, Veteran = 123813380247253, Elite = 73308610261875 },
			hair = { "BlackPonytail", "BrownCharmer", "LongRed" },
		},
		-- Warden (NullSentinel): the commander's long coat (black, purple, then white)
		NullSentinel = {
			clothes = { Grunt = 86219226491588, Veteran = 125686678741368, Elite = 121724294074117 },
			hair = { "LavenderUpdo", "BlondeSpiked", "BlackPonytail" },
		},
		-- Diver: a wetsuit with side panels and harness straps
		Diver = {
			clothes = { Grunt = 80285162131616, Veteran = 134245598443277, Elite = 83969275131232 },
			hair = { "LongRed", "Pal", "BlondeSpiked" },
		},
		-- Anchor: dock overalls over a tee, rolled sleeves, riveted boots
		Anchor = {
			clothes = { Grunt = 93936642093865, Veteran = 125881689801261, Elite = 73130952642527 },
			hair = { "BrownCharmer", "Pal", "LongRed" },
		},
		-- Torpedo Sentry: a naval gunner's jacket with a sailor collar
		TorpedoSentry = {
			clothes = { Grunt = 113718668813530, Veteran = 126150685490396, Elite = 122709543145770 },
			hair = { "BlackPonytail", "BlondeSpiked", "BrownCharmer" },
		},
		-- Shield Bearer: riot armour, plated vest and shoulder pads, the shield-wall mark (navy, worn, then black
		-- and gold)
		ShieldBearer = {
			clothes = { Grunt = 78808159299792, Veteran = 80707701098596, Elite = 101048301031137 },
			hair = { "BrownCharmer", "BlackPonytail", "Pal" },
		},
		-- Captain: an officer's tunic with epaulettes, cuff rings for rank and a cape (hussar braid on Elites)
		Captain = {
			clothes = { Grunt = 137189601915510, Veteran = 88048010234567, Elite = 127825057441532 },
			hair = { "LavenderUpdo", "BrownCharmer", "BlondeSpiked" },
		},
		-- Sniper: camouflage with a chest rig of pouches (woodland, urban grey, then night with gold)
		Sniper = {
			clothes = { Grunt = 130832029671075, Veteran = 140436197361236, Elite = 124942144345352 },
			hair = { "Pal", "BlackPonytail", "LongRed" },
		},
		-- Bomber: a quilted demolition jacket, crossed bandoliers, hazard stripes (scorched, then black and gold)
		Bomber = {
			clothes = { Grunt = 127681840773515, Veteran = 116665973979609, Elite = 73811426930683 },
			hair = { "BlondeSpiked", "LongRed", "BrownCharmer" },
		},
		-- Medic Unit: a white field tunic with a green yoke and the green plus (never a red cross)
		MedicUnit = {
			clothes = { Grunt = 107674922787196, Veteran = 115424497328477, Elite = 93775071608784 },
			hair = { "LavenderUpdo", "Pal", "BlackPonytail" },
		},
		-- Swarmer: a hive-patterned runner's top, shorts and long socks (olive, black, then glowing lime)
		Swarmer = {
			clothes = { Grunt = 75594674258291, Veteran = 110449968748394, Elite = 140676799385969 },
			hair = { "BlondeSpiked", "LongRed", "BlackPonytail" },
		},
		-- Mimic: an ordinary citizen's street clothes, no mark (tee and jeans, flannel and chinos, hoodie and
		-- joggers); everyday hair so it passes for a civilian
		Mimic = {
			clothes = { Grunt = 91893872203491, Veteran = 84758803872576, Elite = 127135458061527 },
			hair = { "BrownCharmer", "Pal", "BlackPonytail" },
		},
		-- Interceptor: a white and blue flight suit with a harness and wings across the back
		Interceptor = {
			clothes = { Grunt = 73558169876935, Veteran = 136956526379079, Elite = 75815403990001 },
			hair = { "BlondeSpiked", "LavenderUpdo", "BrownCharmer" },
		},
		-- Grappler: a heavy work jacket with one armoured hook arm, a chain across the chest, the hook mark
		Grappler = {
			clothes = { Grunt = 87725495385541, Veteran = 85792580044149, Elite = 112233440624940 },
			hair = { "Pal", "LongRed", "BrownCharmer" },
		},
	},
}
