-- Gear (spec: Stats, gear, loot and upgrades; Data model > Piece record). Gear is earned by play only and
-- never sold for Robux. Stats come from gear; looks come from styles, so any style shows over any gear.
-- Every number is a starting value to tune.
return {
	-- the five stats, in wire and save order (bonus stats are saved as an index into this list)
	stats = { "Might", "Vitality", "Focus", "Precision", "Resolve" },

	-- Tiers in save order. Mythic is Phase 2 (season world bosses only) and never drops at launch.
	tierOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
	tiers = {
		Common = { color = { 170, 170, 175 }, mult = 1.00, bonus = 0, dust = 6 },
		Uncommon = { color = { 90, 200, 100 }, mult = 1.15, bonus = 1, dust = 10 },
		Rare = { color = { 70, 140, 255 }, mult = 1.30, bonus = 2, dust = 18 },
		Epic = { color = { 170, 90, 240 }, mult = 1.50, bonus = 2, dust = 36, set = true },
		Legendary = { color = { 255, 190, 40 }, mult = 1.75, bonus = 2, dust = 80, perk = true },
		Mythic = { color = { 240, 60, 60 }, mult = 2.00, bonus = 3, dust = 160, perk = true, phase2 = true },
	},
	-- the lowest hero level each tier can drop for (spec: Levels: Epic at 20, Legendary at 30)
	tierLevel = { Epic = 20, Legendary = 30, Mythic = 99 },

	-- The 8 slots in save order and their main stat. The gadget has no stats; it holds one active gadget.
	slotOrder = { "head", "chest", "hands", "legs", "feet", "back", "belt", "gadget" },
	slots = {
		head = { name = "Head", main = "Precision" },
		chest = { name = "Chest", main = "Vitality" },
		hands = { name = "Hands", main = "Might" },
		legs = { name = "Legs", main = "Resolve" },
		feet = { name = "Feet", main = "Focus" },
		back = { name = "Back", main = "Vitality" },
		belt = { name = "Belt", main = "Might" },
		gadget = { name = "Gadget", main = nil },
	},

	-- Piece budget = round(ilvl x perIlvl x tier mult); the main stat takes mainShare, bonus stats split
	-- the rest. A Common piece (no bonus stats) puts its whole budget in the main stat (Decisions.md).
	budget = { perIlvl = 1.5, mainShare = 0.70 },
	ilvlSpread = 2, -- item level = zone level at drop +- 2
	-- item levels top out at the level cap + ilvlSpread (GearMath.ilvlMax; 52 with the cap at 50)
	equipSlack = 5, -- a hero can wear gear up to item level = hero level + 5

	-- Upgrade +1 to +10: +4% budget per step; step n costs round(12 x n^1.5 x tier mult) Lumen Dust.
	-- No failure chance and no downgrade.
	upgrade = { max = 10, perStep = 0.04, base = 12, power = 1.5 },
	-- Salvage: tier dust x (1 + ilvl / 40). Styles stay unlocked.
	salvage = { perIlvl = 40, maxPerRequest = 20 },
	-- Retune: 800 Credits x tier mult rerolls one bonus stat (not the main stat); locked after 3.
	retune = { credits = 800, max = 3 },

	stashCap = 150,

	-- Epic sets: 4 pieces each (head, chest, hands, feet). 2 pieces: +8% damage with that set's powers.
	-- 4 pieces: an ability change, applied like a mod (AbilityService reads `ability`).
	setOrder = { "Stormcaller", "Rimeguard", "Ironclad", "Orbitwear", "Edgewalker" },
	setSlots = { "head", "chest", "hands", "feet" },
	sets = {
		Stormcaller = {
			power = "Volt",
			two = { damage = 0.08 },
			four = { ability = "ChainLightning", add = { targets = 2 }, text = "Chain Lightning hits 2 more" },
		},
		Rimeguard = {
			power = "Frost",
			two = { damage = 0.08 },
			four = {
				ability = "FrostNova",
				set = { allyShield = 0.10 },
				text = "Frost Nova shields allies in range for 10% health",
			},
		},
		Ironclad = {
			power = "Titan",
			two = { damage = 0.08 },
			four = {
				ability = "GroundSlam",
				set = { fieldCoeff = 0.3, fieldDur = 3 },
				text = "Ground Slam leaves a 3 s shockwave",
			},
		},
		Orbitwear = {
			power = "Pulse",
			two = { damage = 0.08 },
			four = {
				ability = "Float",
				set = { allyHeal = 0.03, allyRadius = 12 },
				text = "Float heals allies near the lifted target 3% a second",
			},
		},
		-- Edgewalker is new with the Blade set (nate's anime additions, Decisions.md)
		Edgewalker = {
			power = "Blade",
			two = { damage = 0.08 },
			four = {
				ability = "ParryStance",
				set = { riposteHeal = 0.05 },
				text = "Parry Stance ripostes heal you for 5% health",
			},
		},
	},

	-- Legendary perks. pvp: how the perk works with the PvP flag on (M8): "off" or "half".
	perkOrder = {
		"Quakeheel",
		"CoolingKill",
		"SecondWind",
		"MagnetPalm",
		"EchoTrail",
		"LuckyStrike",
		"SteadyBeam",
		"SharedSpark",
	},
	perks = {
		Quakeheel = {
			name = "Quakeheel",
			text = "Landings from 30 studs or higher send a shockwave",
			fall = 30,
			coeff = 1.0,
			radius = 10,
			pvp = "off",
		},
		CoolingKill = {
			name = "Cooling Kill",
			text = "A kill refunds 20% of your super's cooldown",
			refund = 0.20,
			pvp = "half",
		},
		SecondWind = {
			name = "Second Wind",
			text = "Once every 5 minutes, get back up with 30% health",
			every = 300,
			health = 0.30,
			pvp = "half",
		},
		MagnetPalm = {
			name = "Magnet Palm",
			text = "Citizen rescue range doubled; rescue speed +25%",
			range = 2,
			speed = 0.25,
			pvp = "off",
		},
		EchoTrail = {
			name = "Echo Trail",
			text = "Your flight trail damages machines lightly",
			coeffPerSecond = 0.1,
			radius = 6,
			pvp = "off",
		},
		LuckyStrike = { name = "Lucky Strike", text = "Every 8th hit is a crit", every = 8, pvp = "off" },
		SteadyBeam = {
			name = "Steady Beam",
			text = "Channeled powers cannot be interrupted",
			pvp = "half",
		},
		SharedSpark = {
			name = "Shared Spark",
			text = "Allies within 20 studs gain 10% of your Might",
			share = 0.10,
			radius = 20,
			pvp = "off",
		},
	},

	-- Gadgets (the gadget slot): one active each, used with the GADGET button.
	gadgetOrder = { "GrapplingHook", "SmokeBomb", "ShieldDrone", "Decoy" },
	gadgets = {
		GrapplingHook = { name = "Grappling Hook", cd = 30, range = 90, time = 0.7, height = 6 },
		SmokeBomb = { name = "Smoke Bomb", cd = 40, radius = 18, blind = 3 },
		ShieldDrone = { name = "Shield Drone", cd = 45, shield = 0.15, duration = 8 },
		Decoy = { name = "Decoy", cd = 60, radius = 30, duration = 5 },
	},

	-- Gear styles: every looted piece unlocks its style forever (a bit in profile.styles, ids 1 to 511).
	-- id = slot index x 64 + n. Each style is a part-built look (PLACEHOLDER ART until meshes):
	-- shape picks the builder in LookService, color is the style's own trim colour.
	-- tier: the lowest tier that can roll it. Set and Legendary styles come only with those pieces.
	styles = {
		head = {
			-- lore step 12 (the city remembers): side styles at Gizmo's bench, Credits only, opened by your own
			-- side's reputation tier (rep = { track, tier }); never rolled by loot (tier "Rep"), looks only
			{
				n = 55,
				name = "Vigil Patrol Visor",
				shape = "visor",
				tier = "Rep",
				rep = { "vigil", 1 },
				price = 1000,
				color = { 90, 170, 255 },
			},
			{
				n = 56,
				name = "Vigil Halo",
				shape = "halo",
				tier = "Rep",
				rep = { "vigil", 4 },
				price = 2500,
				color = { 255, 230, 150 },
			},
			{
				n = 57,
				name = "Syndicate Mask",
				shape = "mask",
				tier = "Rep",
				rep = { "syndicate", 1 },
				price = 1000,
				color = { 150, 30, 50 },
			},
			{
				n = 58,
				name = "Dread Horns",
				shape = "horns",
				tier = "Rep",
				rep = { "syndicate", 4 },
				price = 2500,
				color = { 120, 40, 160 },
			},
			-- Gizmo's shop at HQ (M9): bought with Credits only, never rolled by loot (tier "Shop")
			{
				n = 10,
				name = "Gizmo Visor",
				shape = "visor",
				tier = "Shop",
				price = 1500,
				color = { 40, 200, 190 },
			},
			{
				n = 11,
				name = "Gizmo Crown",
				shape = "halo",
				tier = "Shop",
				price = 3000,
				color = { 255, 140, 200 },
			},
			{ n = 1, name = "Rookie Visor", shape = "visor", tier = "Common", color = { 60, 70, 90 } },
			{ n = 2, name = "Patrol Cap", shape = "cap", tier = "Common", color = { 40, 90, 160 } },
			{ n = 3, name = "Street Mask", shape = "mask", tier = "Common", color = { 30, 30, 36 } },
			{ n = 4, name = "Fin Helm", shape = "fin", tier = "Uncommon", color = { 200, 60, 60 } },
			{ n = 5, name = "Horned Helm", shape = "horns", tier = "Rare", color = { 240, 200, 70 } },
			{ n = 6, name = "Halo Crown", shape = "halo", tier = "Rare", color = { 255, 240, 160 } },
			-- side quest reward (lore step 11, The Hero Academy): Headmaster Halo's own halo, cracked. Never rolled.
			{
				n = 20,
				name = "Cracked Halo",
				shape = "halo",
				tier = "Story",
				quest = "CrackedHalo",
				color = { 200, 170, 90 },
			},
			-- side quest reward (lore step 11, chain 2, The Gala Heist): Madame Masque-a-rade's own mask. Never rolled.
			{
				n = 22,
				name = "Masquerade Mask",
				shape = "mask",
				tier = "Story",
				quest = "MasqueradeMask",
				color = { 120, 50, 170 },
			},
			-- Fame and Infamy rank rewards (M8): never rolled by loot (tier "Fame")
			{
				n = 21,
				name = "Spotlight Visor",
				shape = "visor",
				tier = "Fame",
				quest = "FameRank3",
				color = { 255, 220, 120 },
			},
			-- world boss drops (M6): never rolled by loot (tier "Boss"); 1 in 20 is the shiny one
			{
				n = 30,
				name = "Scrapjaw Visor",
				shape = "visor",
				tier = "Boss",
				boss = "RustjawPrime",
				color = { 150, 96, 60 },
			},
			{
				n = 31,
				name = "Shiny Scrapjaw Visor",
				shape = "visor",
				tier = "Boss",
				boss = "RustjawPrime",
				shiny = true,
				color = { 255, 214, 90 },
			},
		},
		chest = {
			-- lore step 12 (the city remembers): side styles at Gizmo's bench, Credits only, opened by your own
			-- side's reputation tier (rep = { track, tier }); never rolled by loot (tier "Rep"), looks only
			{
				n = 55,
				name = "Lantern Vest",
				shape = "vest",
				tier = "Rep",
				rep = { "vigil", 2 },
				price = 1500,
				color = { 70, 120, 220 },
			},
			{
				n = 56,
				name = "Beacon Plate",
				shape = "plate",
				tier = "Rep",
				rep = { "vigil", 4 },
				price = 2800,
				color = { 235, 240, 255 },
			},
			{
				n = 57,
				name = "Foundry Harness",
				shape = "harness",
				tier = "Rep",
				rep = { "syndicate", 2 },
				price = 1500,
				color = { 60, 40, 50 },
			},
			{
				n = 58,
				name = "Vault Core",
				shape = "core",
				tier = "Rep",
				rep = { "syndicate", 4 },
				price = 2800,
				color = { 210, 60, 60 },
			},
			-- Gizmo's shop at HQ (M9): bought with Credits only, never rolled by loot (tier "Shop")
			{
				n = 10,
				name = "Gizmo Plate",
				shape = "plate",
				tier = "Shop",
				price = 1500,
				color = { 60, 200, 120 },
			},
			{
				n = 11,
				name = "Gizmo Core",
				shape = "core",
				tier = "Shop",
				price = 3000,
				color = { 255, 120, 40 },
			},
			{ n = 1, name = "Padded Vest", shape = "vest", tier = "Common", color = { 80, 90, 110 } },
			{ n = 2, name = "Star Plate", shape = "plate", tier = "Common", color = { 50, 110, 200 } },
			{ n = 3, name = "Bolt Harness", shape = "harness", tier = "Uncommon", color = { 255, 200, 60 } },
			{ n = 4, name = "Core Plate", shape = "core", tier = "Rare", color = { 120, 220, 255 } },
			-- story and side quest rewards (M7; lore step 10 chains): never rolled by loot (tier "Story")
			{
				n = 20,
				name = "Dock Coat",
				shape = "vest",
				tier = "Story",
				quest = "DockCoat",
				color = { 60, 140, 140 },
			},
		},
		hands = {
			-- lore step 12 (the city remembers): side styles at Gizmo's bench, Credits only, opened by your own
			-- side's reputation tier (rep = { track, tier }); never rolled by loot (tier "Rep"), looks only
			{
				n = 55,
				name = "Watchman Wraps",
				shape = "wraps",
				tier = "Rep",
				rep = { "vigil", 2 },
				price = 1200,
				color = { 220, 230, 250 },
			},
			{
				n = 57,
				name = "Spike Knuckles",
				shape = "spikes",
				tier = "Rep",
				rep = { "syndicate", 2 },
				price = 1200,
				color = { 90, 20, 40 },
			},
			-- Gizmo's shop at HQ (M9): bought with Credits only, never rolled by loot (tier "Shop")
			{
				n = 10,
				name = "Gizmo Wraps",
				shape = "wraps",
				tier = "Shop",
				price = 1500,
				color = { 240, 110, 190 },
			},
			{
				n = 11,
				name = "Gizmo Coils",
				shape = "coil",
				tier = "Shop",
				price = 2500,
				color = { 120, 230, 255 },
			},
			{ n = 1, name = "Wrist Wraps", shape = "wraps", tier = "Common", color = { 200, 200, 210 } },
			{ n = 2, name = "Knuckle Guards", shape = "gauntlet", tier = "Common", color = { 70, 70, 80 } },
			{ n = 3, name = "Spike Gauntlets", shape = "spikes", tier = "Uncommon", color = { 180, 60, 60 } },
			{ n = 4, name = "Coil Gauntlets", shape = "coil", tier = "Rare", color = { 120, 210, 255 } },
			{
				n = 21,
				name = "Legend Gauntlets",
				shape = "gauntlet",
				tier = "Fame",
				quest = "FameRank9",
				color = { 250, 200, 60 },
			},
			-- the Leviathan Engine's drop (underwater, nate 2026-11-16): never rolled by loot (tier "Boss")
			{
				n = 30,
				name = "Leviathan Coils",
				shape = "coil",
				tier = "Boss",
				boss = "LeviathanEngine",
				color = { 40, 160, 200 },
			},
			{
				n = 31,
				name = "Shiny Leviathan Coils",
				shape = "coil",
				tier = "Boss",
				boss = "LeviathanEngine",
				shiny = true,
				color = { 150, 255, 230 },
			},
		},
		legs = {
			-- Gizmo's shop at HQ (M9): bought with Credits only, never rolled by loot (tier "Shop")
			{
				n = 10,
				name = "Gizmo Shins",
				shape = "shins",
				tier = "Shop",
				price = 1500,
				color = { 255, 210, 60 },
			},
			{
				n = 11,
				name = "Gizmo Greaves",
				shape = "greaves",
				tier = "Shop",
				price = 2000,
				color = { 120, 80, 220 },
			},
			{ n = 1, name = "Shin Guards", shape = "shins", tier = "Common", color = { 70, 80, 100 } },
			{ n = 2, name = "Stripe Leggings", shape = "stripes", tier = "Common", color = { 230, 70, 70 } },
			{
				n = 3,
				name = "Plated Greaves",
				shape = "greaves",
				tier = "Uncommon",
				color = { 150, 150, 165 },
			},
		},
		feet = {
			-- lore step 12 (the city remembers): side styles at Gizmo's bench, Credits only, opened by your own
			-- side's reputation tier (rep = { track, tier }); never rolled by loot (tier "Rep"), looks only
			{
				n = 55,
				name = "Rooftop Boots",
				shape = "boots",
				tier = "Rep",
				rep = { "vigil", 3 },
				price = 1800,
				color = { 40, 70, 150 },
			},
			{
				n = 57,
				name = "Getaway Heels",
				shape = "jets",
				tier = "Rep",
				rep = { "syndicate", 3 },
				price = 1800,
				color = { 230, 60, 60 },
			},
			-- Gizmo's shop at HQ (M9): bought with Credits only, never rolled by loot (tier "Shop")
			{
				n = 10,
				name = "Gizmo Boots",
				shape = "boots",
				tier = "Shop",
				price = 1500,
				color = { 40, 190, 170 },
			},
			{
				n = 11,
				name = "Gizmo Jets",
				shape = "jets",
				tier = "Shop",
				price = 2500,
				color = { 255, 90, 40 },
			},
			{ n = 1, name = "Street Boots", shape = "boots", tier = "Common", color = { 40, 40, 48 } },
			{ n = 2, name = "Jet Heels", shape = "jets", tier = "Uncommon", color = { 255, 140, 40 } },
			{ n = 3, name = "Winged Boots", shape = "wings", tier = "Rare", color = { 240, 240, 250 } },
		},
		back = {
			-- lore step 12 (the city remembers): side styles at Gizmo's bench, Credits only, opened by your own
			-- side's reputation tier (rep = { track, tier }); never rolled by loot (tier "Rep"), looks only
			{
				n = 55,
				name = "Safehouse Cape",
				shape = "cape",
				tier = "Rep",
				rep = { "vigil", 3 },
				price = 2000,
				color = { 60, 110, 230 },
			},
			{
				n = 56,
				name = "Guardian Longcape",
				shape = "longcape",
				tier = "Rep",
				rep = { "vigil", 5 },
				price = 3000,
				color = { 255, 215, 90 },
			},
			{
				n = 57,
				name = "Smoke Cape",
				shape = "cape",
				tier = "Rep",
				rep = { "syndicate", 3 },
				price = 2000,
				color = { 50, 40, 60 },
			},
			{
				n = 58,
				name = "Kingpin Longcape",
				shape = "longcape",
				tier = "Rep",
				rep = { "syndicate", 5 },
				price = 3000,
				color = { 170, 20, 40 },
			},
			-- Gizmo's shop at HQ (M9): bought with Credits only, never rolled by loot (tier "Shop")
			{
				n = 10,
				name = "Gizmo Cape",
				shape = "cape",
				tier = "Shop",
				price = 1500,
				color = { 190, 110, 240 },
			},
			{
				n = 11,
				name = "Gizmo Wings",
				shape = "lightwings",
				tier = "Shop",
				price = 3000,
				color = { 255, 240, 160 },
			},
			{ n = 1, name = "Short Cape", shape = "cape", tier = "Common", color = { 200, 40, 50 } },
			{ n = 2, name = "Long Cape", shape = "longcape", tier = "Uncommon", color = { 40, 60, 160 } },
			{
				n = 21,
				name = "Headliner Cape",
				shape = "longcape",
				tier = "Fame",
				quest = "FameRank6",
				color = { 230, 180, 50 },
			},
			{ n = 3, name = "Jet Pack", shape = "jetpack", tier = "Uncommon", color = { 90, 90, 100 } },
			-- side quest reward (lore step 11, Wind-Up Lane): the Toymaker's brass clockwork pack. Never rolled.
			{
				n = 24,
				name = "Clockwork Pack",
				shape = "jetpack",
				tier = "Story",
				quest = "ClockworkPack",
				color = { 205, 160, 70 },
			},
			{ n = 4, name = "Light Wings", shape = "lightwings", tier = "Rare", color = { 255, 230, 140 } },
			{
				n = 30,
				name = "Maw Crystal Fins",
				shape = "lightwings",
				tier = "Boss",
				boss = "LumenMaw",
				color = { 150, 120, 255 },
			},
			{
				n = 31,
				name = "Shiny Maw Crystal Fins",
				shape = "lightwings",
				tier = "Boss",
				boss = "LumenMaw",
				shiny = true,
				color = { 255, 250, 210 },
			},
		},
		belt = {
			-- lore step 12 (the city remembers): side styles at Gizmo's bench, Credits only, opened by your own
			-- side's reputation tier (rep = { track, tier }); never rolled by loot (tier "Rep"), looks only
			{
				n = 55,
				name = "Vigil Buckle",
				shape = "buckle",
				tier = "Rep",
				rep = { "vigil", 1 },
				price = 800,
				color = { 90, 160, 255 },
			},
			{
				n = 56,
				name = "City Sash",
				shape = "sash",
				tier = "Rep",
				rep = { "vigil", 5 },
				price = 3000,
				color = { 255, 200, 60 },
			},
			{
				n = 57,
				name = "Dread Buckle",
				shape = "buckle",
				tier = "Rep",
				rep = { "syndicate", 1 },
				price = 800,
				color = { 200, 40, 60 },
			},
			{
				n = 58,
				name = "Syndicate Sash",
				shape = "sash",
				tier = "Rep",
				rep = { "syndicate", 5 },
				price = 3000,
				color = { 130, 30, 150 },
			},
			-- Gizmo's shop at HQ (M9): bought with Credits only, never rolled by loot (tier "Shop")
			{
				n = 10,
				name = "Gizmo Buckle",
				shape = "buckle",
				tier = "Shop",
				price = 1500,
				color = { 255, 200, 60 },
			},
			{ n = 1, name = "Utility Belt", shape = "belt", tier = "Common", color = { 210, 170, 60 } },
			{ n = 2, name = "Star Buckle", shape = "buckle", tier = "Common", color = { 230, 230, 240 } },
			{ n = 3, name = "Power Sash", shape = "sash", tier = "Uncommon", color = { 170, 90, 240 } },
			{
				n = 20,
				name = "Gold Sash",
				shape = "sash",
				tier = "Story",
				quest = "GoldSash",
				color = { 230, 190, 70 },
			},
		},
		gadget = {},
	},
	-- Set styles (head, chest, hands, feet share one look per set) and Legendary styles (one per slot)
	setStyleBase = 40, -- n = 40 + set index
	legendaryStyleN = 50, -- n = 50: a gold-trimmed version of the slot's top shape
}
