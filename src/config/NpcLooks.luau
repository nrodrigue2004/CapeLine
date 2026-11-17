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
	faces = {
		Hero = { human = 0, turned = 0 },
		Stern = { human = 0, turned = 0 },
		Sharp = { human = 0, turned = 0 },
		Scarred = { human = 0, turned = 0 },
		Rookie = { human = 0, turned = 0 },
		Cold = { human = 0, turned = 0 },
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
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "BrownCharmer", "BlondeSpiked", "Pal" },
		},
		-- Burglar Bot: a striped top and a loot strap (grey, red, then black and gold)
		BurglarBot = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "Pal", "BrownCharmer", "LongRed" },
		},
		-- Sneak Bot: a wrapped stealth suit with a sash (purple, ice blue, then black and red)
		SneakBot = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "BlackPonytail", "LavenderUpdo", "BlondeSpiked" },
		},
		-- Brute Bot: a sleeveless brawler's top, champion's belt, wrist wraps
		BruteBot = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "BrownCharmer", "Pal", "BlondeSpiked" },
		},
		-- Sentry: a security guard's uniform with the shield badge and armband
		Turret = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "BlackPonytail", "BrownCharmer", "LongRed" },
		},
		-- Null Sentinel: the commander's long coat (black, purple, then white)
		NullSentinel = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "LavenderUpdo", "BlondeSpiked", "BlackPonytail" },
		},
		-- Diver: a wetsuit with side panels and harness straps
		Diver = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "LongRed", "Pal", "BlondeSpiked" },
		},
		-- Anchor: dock overalls over a tee, rolled sleeves, riveted boots
		Anchor = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "BrownCharmer", "Pal", "LongRed" },
		},
		-- Torpedo Sentry: a naval gunner's jacket with a sailor collar
		TorpedoSentry = {
			clothes = { Grunt = 0, Veteran = 0, Elite = 0 },
			hair = { "BlackPonytail", "BlondeSpiked", "BrownCharmer" },
		},
	},
}
