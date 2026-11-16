-- Weapons: the creator's weapon step and the weapon slot (nate's hero creator plan, 2026-11-16,
-- https://claude.ai/artifact/VeuJPWz6kKE6gGsUBmqQC9). Any weapon pairs with any power. Key 1 holds the power,
-- key 2 the weapon; M1 and Z X C V act on the held one. One weapon is free at creation; the rest unlock at a
-- safehouse Weapon Rack for Credits; the 5 Exotic weapons are sold for Robux (nate) and are tuned to the same
-- damage as the rest (sidegrades: they change how you play, not how strong you are). Per-weapon Mastery
-- unlocks X, C and V. Guns are cartoon sci-fi blasters, never real-world firearms.
-- A weapon row: { id, family, name, complexity, text, source }. Ids are saved: never reorder, only append.
--   source: "credits:N" (the Weapon Rack), "robux:shopKey" (Config.Shop.products)
return {
	families = {
		{ id = "fists", name = "Fists", hold = "fists", text = "Fight with your hands and feet" },
		{ id = "one", name = "One-handed", hold = "one", text = "A blade or club in one hand" },
		{ id = "two", name = "Two-handed", hold = "two", text = "Big, slow and wide" },
		{ id = "dual", name = "Dual wield", hold = "dual", text = "A weapon in each hand, fast combos" },
		{ id = "shield", name = "Shield", hold = "shield", text = "Block, bash and throw" },
		{ id = "ranged", name = "Ranged", hold = "ranged", text = "Hit from a distance" },
		{ id = "exotic", name = "Exotic", hold = "exotic", text = "Strange, flashy, hard to master" },
	},
	complexity = { "Low", "Medium", "High", "Very High" },

	list = {
		{ 1, "fists", "Bare Fists", 1, "Fast punches, a grab and slam", "credits:0" },
		{ 2, "fists", "Martial Arts", 3, "Kicks and counters, a parry window", "credits:1500" },
		{ 3, "fists", "Power Gauntlets", 2, "Heavy punches with shockwaves, a ground pound", "credits:1500" },
		{ 4, "fists", "Strikers", 2, "Kickboxing in armoured boots, a spinning launcher", "credits:1200" },
		{ 5, "one", "Sword", 1, "Balanced slashes, a dash cut", "credits:800" },
		{ 6, "one", "Katana", 3, "Quick-draw strikes, a sheathe counter", "credits:2500" },
		{ 7, "one", "Hand Axe", 2, "Heavy chops, throw and recall", "credits:1500" },
		{ 8, "one", "Mace", 2, "Slow hits that stagger and break guard", "credits:1500" },
		{ 9, "one", "Baton", 1, "Fast stuns for crowds", "credits:800" },
		{ 10, "one", "Dagger", 3, "Backstabs, a vanish step", "credits:2500" },
		{ 11, "two", "Greatsword", 2, "Wide sweeps, a charged overhead", "credits:2000" },
		{ 12, "two", "Great Axe", 2, "Spinning cleave, a ground split", "credits:2000" },
		{ 13, "two", "Warhammer", 2, "Slams and knock-ups", "credits:2000" },
		{ 14, "two", "Spear", 3, "Long thrusts, a vault and pierce", "credits:2500" },
		{ 15, "two", "Scythe", 4, "Sweeping reaps that pull enemies in", "credits:3500" },
		{ 16, "two", "Bo Staff", 3, "Long spin combos, a pole vault", "credits:2500" },
		{ 17, "dual", "Twin Blades", 3, "Flurries, a whirlwind", "credits:2500" },
		{ 18, "dual", "Claws", 2, "Pounce and rake", "credits:1500" },
		{ 19, "dual", "Sai", 3, "Catches, disarms and pins", "credits:2500" },
		{ 20, "dual", "Tonfa", 2, "Guard and jab, spinning strikes", "credits:1500" },
		{ 21, "dual", "Nunchucks", 4, "Fast chains and juggles", "credits:3500" },
		{ 22, "shield", "Round Shield", 2, "Block, bash, a throw that bounces back", "credits:1500" },
		{ 23, "shield", "Tower Shield", 1, "Full-body block, cover for allies", "credits:1200" },
		{ 24, "shield", "Sword and Shield", 2, "Slash and block together", "credits:2000" },
		{ 25, "ranged", "Blaster Pistol", 1, "Quick shots on the move", "credits:800" },
		{ 26, "ranged", "Twin Blasters", 2, "Run and gun, a spin volley", "credits:2000" },
		{ 27, "ranged", "Blaster Rifle", 2, "Charged long shots", "credits:2000" },
		{ 28, "ranged", "Bow", 3, "Charged arrows, an arrow rain", "credits:2500" },
		{ 29, "ranged", "Crossbow", 2, "Heavy bolts, a net bolt", "credits:1500" },
		{ 30, "ranged", "Arm Cannon", 1, "Big slow blasts, a beam", "credits:1200" },
		{ 31, "ranged", "Throwing Stars", 3, "Fan throws that ricochet", "credits:2500" },
		{ 32, "exotic", "Chain Whip", 3, "Long lashes, pull and swing", "robux:weaponWhip" },
		{ 33, "exotic", "War Fan", 4, "Wind slashes, a glide", "robux:weaponFan" },
		{ 34, "exotic", "Yo-yo", 4, "Trick strikes on a tether", "robux:weaponYoyo" },
		{ 35, "exotic", "Rope Dart", 4, "Long spins, wrap and pull", "robux:weaponDart" },
		{ 36, "exotic", "Boomerang", 2, "Curved throws that come back", "robux:weaponBoomerang" },
	},
	-- the first slice (plan step 4): one weapon per family is fully playable; the rest show in the creator
	-- as "Coming soon" until their combos and skills are built
	playable = { 1, 5, 11, 17, 22, 25, 36 },

	-- Mastery: earned by hitting enemies with the weapon (per account, per weapon). Z works at once.
	mastery = {
		max = 300,
		skills = { Z = 0, X = 25, C = 75, V = 150 },
		-- whole points (saves keep whole numbers): a level is 40 points, so max 300 is 12,000 points
		perHit = 1, -- a landed hit (an M1 combo is 4 hits)
		perKill = 20, -- a robot defeated while holding the weapon
		perLevel = 40,
		masteredGlow = 300,
	},

	-- The weapon look (plan: Weapon look). 4 model styles per weapon, named per family.
	styles = {
		fists = { "Wraps", "Plated", "Spiked", "Energy" },
		one = { "Classic", "Broad", "Jagged", "Energy" },
		two = { "Classic", "Heavy", "Jagged", "Energy" },
		dual = { "Classic", "Hooked", "Jagged", "Energy" },
		shield = { "Classic", "Spiked", "Crest", "Energy" },
		ranged = { "Classic", "Compact", "Heavy", "Energy" },
		exotic = { "Classic", "Ornate", "Jagged", "Energy" },
	},
	finishes = {
		{ name = "Steel", mat = "Metal" },
		{ name = "Gold", mat = "Metal", tint = { 255, 200, 80 } },
		{ name = "Obsidian", mat = "Slate", tint = { 30, 28, 40 } },
		{ name = "Crystal", mat = "Glass" },
		{ name = "Wood", mat = "Wood" },
		{ name = "Energy", mat = "Neon" },
	},
	glowLevels = 3, -- glow strength 0 (off) to 3
	trails = { "None", "Streak", "Ember", "Frost", "Spark", "Shadow" }, -- swing trails (index 1 = none)

	-- Starting weapon: the creator picks any non-Robux weapon free; a hero made before weapons has Bare Fists
	defaultWeapon = 1,
	-- the Weapon Rack sits in every safehouse (SafehouseService terminals)
	rackRange = 12,
}
