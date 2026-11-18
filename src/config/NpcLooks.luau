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
		-- The Toymaker's clockwork toys (lore step 11, the Suburbs chain): each version is its own toy, a tin
		-- soldier (red coat, white cross belts, brass buttons), a lawn gnome (blue smock, brown belt, red boots)
		-- and a patchwork plush bear (big cross-stitched patches, a big bow), each with the wind-up key on its back.
		-- The art is final (preview art/preview/uniforms_chains.png); 0 until nate uploads
		-- art/export/clothes/uniforms/WindupToy_<Version>.png, and until then the toys wear the plain look in
		-- their toy colours (PLACEHOLDER ART)
		WindupToy = {
			clothes = { Grunt = 125338535543008, Veteran = 94901321309103, Elite = 137346260559470 },
			hair = { "BlondeSpiked", "Pal", "BrownCharmer" },
		},
		-- The Wind-Up Giant: the giant tin soldier as the toy band's drummer (2026-11-18 art pass): its chest a toy
		-- drum laced with a zigzag cord between brass rims, gold fringed epaulettes, two drumsticks crossed over the
		-- big key plate on the back (Grunt red, Veteran blue, Elite white and gold), so it never reads as one of the
		-- tin soldiers it leads. 0 until nate uploads WindupGiant_<Version>.png (its imported finale model,
		-- Config.FinaleArt, wins over the clothes once it is in)
		WindupGiant = {
			clothes = { Grunt = 116267858023319, Veteran = 133930944910258, Elite = 89355233489116 },
			hair = { "Pal", "BrownCharmer", "BlackPonytail" },
		},
		-- Captain Brine's Salt Dogs (lore step 11, the Coast chain): each version a rank of the robot crew, a
		-- striped deckhand's jersey with a rope belt and the crew's red neckerchief (Grunt), a gunner's navy pea
		-- coat with brass buttons, the neckerchief, a cutlass strap and a big buckled belt (Veteran) and the
		-- bosun's long red coat worn open over the crew's striped jersey, gold braid and a whistle chain (Elite),
		-- each with the crew's crossed-hooks patch on the back. The art is final (art/preview/uniforms_chains.png);
		-- 0 until nate uploads art/export/clothes/uniforms/SaltDog_<Version>.png, the plain look until then
		-- (PLACEHOLDER ART)
		SaltDog = {
			clothes = { Grunt = 122780860811722, Veteran = 84435688682067, Elite = 81909675312609 },
			hair = { "BlackPonytail", "LongRed", "Pal" },
		},
	},
	-- The side quests' people (2026-11-18 art pass, PLACEHOLDER ART until nate approves): each giver, named
	-- helper and finale villain in a classic outfit of their own (art/clothes/people.py: the Shirt and Pants
	-- side by side, like the robots' uniforms) and, where the six shared faces do not fit (the old, the kids,
	-- a machine, a famous face), a face of their own (Face_<Name>.png; `cracked` for a famous fake's unmasked
	-- face). Keys: a Config.SideQuests giver, a Config.SideQuests.dress row, a finale villain's Config.Enemies
	-- kind, or a helper below. Shared.PeopleLooks reads it: a person with a clothes id wears it in place of the
	-- suit, shirt, pants and legs pieces of their look (hats, coats, gloves and boots stay); a face id replaces
	-- their visage's face. 0 until nate uploads art/export/clothes/people/<Name>.png: then today's look shows.
	people = {
		-- the givers
		Gus = { clothes = 90835372619189, face = 128011914556574 }, -- the janitor's grey-blue work shirt, name patch, knee-padded work trousers
		Benny = { clothes = 77647909642570, face = 0 }, -- a crimson valet jacket with gold buttons and braid, a bow tie
		Scoops = { clothes = 82546057607636, face = 0 }, -- a pink and mint striped apron over a white tee, the cone badge
		Dot = { clothes = 94130935264159, face = 0 }, -- a patched denim overall bib over an olive plaid shirt
		Nell = { clothes = 118792768088018, face = 99065613077192 }, -- a navy cable-knit fisherman's sweater, oilskin trousers, the ferry badge
		Pearl = { clothes = 89614858893997, face = 0 }, -- a teal wetsuit with coral side panels and the Reef Station patch
		Brick = { clothes = 89934186422139, face = 134476856538221 }, -- an old champion's faded gym tank, track pants, hand wraps
		Vanta = { clothes = 77552251176771, face = 0 }, -- a deep purple velvet gown with gold damask and a brooch
		Nora = { clothes = 119652152249492, face = 0 }, -- a tan belted trench coat, a press pass, dark slacks
		Okafor = { clothes = 84163299196364, face = 0 }, -- a lab coat over a teal blouse, the Ashgrove badge (struck through)
		Ruth = { clothes = 125426921158688, face = 108844421504161 }, -- a mustard radio-wave cardigan, brown corduroys
		Moth = { clothes = 85006947184834, face = 102562165830329 }, -- a plum tunic with embroidered moths, a long patterned skirt
		Tess = { clothes = 123985374881711, face = 0 }, -- an orange mechanic's coverall, rolled sleeves, grease, the gear patch
		Kiko = { clothes = 121345005850958, face = 118870206618802 }, -- a white student's gi with red trim
		-- the named helpers (helpers below)
		Wren = { clothes = 120770462105211, face = 80053424284031 }, -- Halo Academy's navy blazer with the crest, a grey skirt
		Toby = { clothes = 109459450455037, face = 99017455954019 }, -- a rocket tee and denim dungaree shorts
		Flint = { clothes = 101651817037827, face = 104664739780211 }, -- a young fighter's red training top with tape, fight shorts
		Finn = { clothes = 85243876151673, face = 93652943274966 }, -- a deckhand's striped jersey under an orange life vest
		Dace = { clothes = 105970090962187, face = 0 }, -- a salvage diver's orange and black drysuit with a harness
		Ambrose = { clothes = 80795628424941, face = 120870507467317 }, -- a faded midnight tailcoat sewn with stars, a gold waistcoat
		Hoshi = { clothes = 89076211480009, face = 71993929343764 }, -- a master's grey-blue gi over dark hakama
		-- the finale villains
		HeadmasterHalo = { clothes = 119362793722129, face = 0 }, -- an academic gown with the gold halo crest
		Redline = { clothes = 137315512930413, face = 0 }, -- a red racing suit with checker stripes and flames
		MasqueARade = { clothes = 135724181224991, face = 0 }, -- a purple and gold harlequin bodice and tights
		HarvestKing = { clothes = 88230514152184, face = 0 }, -- mustard thresher overalls over a forest shirt, the wheat crown
		Bramblebeast = { clothes = 124844408639153, face = 0 }, -- bark and vine skin with pumpkin rind plates (a creature)
		CaptainBrine = { clothes = 73940003834451, face = 0 }, -- a riveted brass diving rig under a pirate coat's cuffs
		Pitboss = { clothes = 130674751567319, face = 113644132018382 }, -- a maroon pinstripe tuxedo, gold lapels, a cummerbund
		Tidewright = { clothes = 80385625640032, face = 139965967699019 }, -- a bronze and teal plated guardian's robe grown with coral
		Vesper = { clothes = 123283726201797, face = 139460377829042, cracked = 71995160895460 }, -- a night-sky starfield bodysuit, the evening star
		Catchpole = { clothes = 91345650758578, face = 0 }, -- an olive ranger's harness, net pattern, pouches
		Scorch = { clothes = 87879659440939, face = 0 }, -- a charcoal suit cracked with glowing magma veins
		Censor = { clothes = 77509575101532, face = 0 }, -- a black tuxedo crossed with white redaction bars
		Holloway = { clothes = 103073226710624, face = 132445003909609 }, -- a director's lab coat with steel plates, indigo shirt and tie
		Voidhound = { clothes = 72605441879492, face = 0 }, -- a starfield machine shell with ultraviolet seams
		Morrow = { clothes = 124073096104760, face = 0 }, -- a stage tuxedo lined in violet, mirror shards and card suits
		Clawback = { clothes = 118389979001189, face = 0 }, -- a mustard repo jumpsuit, charcoal panels, the hook mark
		Gale = { clothes = 93321209543915, face = 0 }, -- a teal fighter's sash top with wind swirls, black hakama
		-- the famous fakes (lore step 4; finale villains too): a hero suit each in place of the creator suit (its
		-- cape, gloves, boots, shoulders, belt and chest emblem stay; the chest leaves the emblem's spot as a
		-- field), a famous face of its own and that face cracked to the metal for the unmask. Preview
		-- art/preview/people_6.png (front and back).
		Radiant = { clothes = 98068500967035, face = 106699728660409, cracked = 137005297509723 }, -- gold, a white dawn yoke, sunrise rays; a rising sun on the back
		Bulwark = { clothes = 116363104603810, face = 129527751609547, cracked = 140144429385939 }, -- royal blue armour, a yellow-edged silver chest plate, a hex back
		Skylance = { clothes = 88797281558131, face = 75221313254249, cracked = 130978478789779 }, -- azure, three white streaks edged in cyan; chevrons on the back
	},
	-- The named helpers a side quest step draws (who stands in for a `find` step's witness, or the one carried in
	-- a `carry` step): chain id, step number and side; `speaker` is their Config.Story.guides.speakers card (its
	-- portrait's skin and hair); shirt and pants colour them until their outfit is uploaded. Tests check each row
	-- still points at a witness or carry step.
	helpers = {
		Wren = {
			chain = "HeroAcademy",
			step = 4,
			side = "hero",
			speaker = "wren",
			shirt = { 30, 45, 100 },
			pants = { 120, 124, 132 },
		},
		Toby = {
			chain = "WindUpLane",
			step = 3,
			side = "hero",
			speaker = "toby",
			shirt = { 90, 170, 230 },
			pants = { 60, 90, 150 },
		},
		Flint = {
			chain = "ThePit",
			step = 2,
			side = "hero",
			speaker = "flint",
			shirt = { 200, 50, 45 },
			pants = { 40, 40, 46 },
		},
		Finn = {
			chain = "SaltDogs",
			step = 6,
			side = "hero",
			speaker = "finn",
			shirt = { 250, 130, 40 },
			pants = { 190, 175, 140 },
		},
		Dace = {
			chain = "SunkenCity",
			step = 3,
			side = "hero",
			speaker = "dace",
			shirt = { 240, 120, 30 },
			pants = { 30, 30, 36 },
		},
		Ambrose = {
			chain = "LastOwner",
			step = 2,
			side = "hero",
			speaker = "ambrose",
			shirt = { 30, 34, 80 },
			pants = { 24, 24, 30 },
		},
		Hoshi = {
			chain = "TakenMaster",
			step = 5,
			side = "hero",
			speaker = "hoshi",
			shirt = { 120, 140, 160 },
			pants = { 30, 32, 44 },
		},
	},
}
