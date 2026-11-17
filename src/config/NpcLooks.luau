-- Robots (and later citizens) as plain Roblox characters (nate, 2026-11-17: "i want the characters to feel like
-- roblox but not the combat or the environment"): the blocky R15 body, a classic clothes image (the shirt drawn
-- over the pants on Roblox's Shirt and Pants template, art/clothes/<robot>.py), a face decal that swaps to the
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
	-- per robot kind (Config.Enemies key): the uploaded clothes image id (0 until nate uploads
	-- art/export/clothes/<Robot>_Clothes.png) and the hairs it may wear (one picked per robot by its id)
	robots = {
		SparkDrone = {
			clothes = 0,
			hair = { "BrownCharmer", "BlondeSpiked", "Pal" },
		},
	},
}
