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
	-- per robot kind (Config.Enemies key): uploaded image ids (0 until nate uploads art/export/clothes/*.png:
	-- <Robot>_Clothes, <Robot>_Face, <Robot>_FaceTurned) and the hair it may wear (picked per robot by its id)
	robots = {
		SparkDrone = {
			clothes = 0,
			face = 0,
			faceTurned = 0,
			hair = { "BrownCharmer", "BlondeSpiked", "Pal" },
		},
	},
}
