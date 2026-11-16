-- Shop: Gizmo's Credit shop and the Robux shop (spec: Economy > Revenue levers, Pay-to-win check; Hero HQ >
-- Gizmo's shop; Screens > Robux Shop). Prices are tuning guesses to test. Nothing sold changes Might,
-- Vitality, Focus, Precision, Resolve, gear score, a skill point, a loot roll, Lumen Dust, a rank, boss
-- damage or a PvP result; the only number is the 2x pass on earned Credits and Renown.
-- Roblox ids: every product and pass id is 0 until nate creates them on the Creator Dashboard (Launch
-- Checklist). While an id is 0 the shop shows the item and Studio's dev button runs the same grant path
-- with a test receipt, so "grants once" is testable before launch.
return {
	-- Where the Robux shop may open (spec: "Only in HQ, safehouses and the menu, never mid-fight")
	openIn = { "hq", "safehouse", "menu" },
	combatLock = 10, -- seconds after dealing or taking damage when the menu's shop stays shut

	-- Developer products: each grants once per receipt (receipts are kept on the profile, last 50)
	products = {
		pack1 = { id = 0, robux = 149, kind = "pack", pack = 1 },
		pack2 = { id = 0, robux = 199, kind = "pack", pack = 2 },
		pack3 = { id = 0, robux = 249, kind = "pack", pack = 3 },
		pack4 = { id = 0, robux = 299, kind = "pack", pack = 4 },
		pack5 = { id = 0, robux = 399, kind = "pack", pack = 5 },
		pack6 = { id = 0, robux = 249, kind = "pack", pack = 6 },
		pack7 = { id = 0, robux = 299, kind = "pack", pack = 7 }, -- the 2026-11-16 creator plan's new slots
		starter = { id = 0, robux = 79, kind = "starter" }, -- A/B: 49, 79, 99
		slot3 = { id = 0, robux = 149, kind = "slot", slot = 3 },
		slot4 = { id = 0, robux = 249, kind = "slot", slot = 4 },
		tint1 = { id = 0, robux = 49, kind = "tint", tint = 1 },
		tint2 = { id = 0, robux = 49, kind = "tint", tint = 2 },
		tint3 = { id = 0, robux = 79, kind = "tint", tint = 3 },
		tint4 = { id = 0, robux = 79, kind = "tint", tint = 4 },
		tint5 = { id = 0, robux = 99, kind = "tint", tint = 5 },
		tint6 = { id = 0, robux = 99, kind = "tint", tint = 6 },
		tint7 = { id = 0, robux = 129, kind = "tint", tint = 7 },
		tint8 = { id = 0, robux = 149, kind = "tint", tint = 8 },
		tint9 = { id = 0, robux = 199, kind = "tint", tint = 9 },
		tint10 = { id = 0, robux = 199, kind = "tint", tint = 10 },
		emote3 = { id = 0, robux = 25, kind = "emote", emote = 3 },
		emote4 = { id = 0, robux = 25, kind = "emote", emote = 4 },
		emote5 = { id = 0, robux = 49, kind = "emote", emote = 5 },
		emote6 = { id = 0, robux = 49, kind = "emote", emote = 6 },
		emote7 = { id = 0, robux = 49, kind = "emote", emote = 7 },
		emote8 = { id = 0, robux = 75, kind = "emote", emote = 8 },
		emote9 = { id = 0, robux = 75, kind = "emote", emote = 9 },
		emote10 = { id = 0, robux = 99, kind = "emote", emote = 10 },
		pose21 = { id = 0, robux = 49, kind = "emote", emote = 21 },
		pose22 = { id = 0, robux = 49, kind = "emote", emote = 22 },
		pose23 = { id = 0, robux = 75, kind = "emote", emote = 23 },
		pose24 = { id = 0, robux = 99, kind = "emote", emote = 24 },
		-- the 5 Exotic weapons (nate 2026-11-16: "exotic should be robux"): equal-strength sidegrades, owned for life
		weaponWhip = { id = 0, robux = 199, kind = "weapon", weapon = 32 },
		weaponFan = { id = 0, robux = 249, kind = "weapon", weapon = 33 },
		weaponYoyo = { id = 0, robux = 249, kind = "weapon", weapon = 34 },
		weaponDart = { id = 0, robux = 249, kind = "weapon", weapon = 35 },
		weaponBoomerang = { id = 0, robux = 149, kind = "weapon", weapon = 36 },
	},
	-- Game passes (owned for life; checked on join and after a purchase)
	passes = {
		quickSwap = { id = 0, robux = 149 }, -- change loadout anywhere outside combat
		double = { id = 0, robux = 249 }, -- x2 earned Credits and Renown only (Config.Economy.bonus.doublePass)
	},
	-- Robux shop tabs (spec: Packs, Effects, Emotes, Passes, Slots) and what each lists, in order
	tabs = {
		{
			id = "packs",
			name = "Packs",
			items = { "pack7", "pack1", "pack2", "pack3", "pack4", "pack5", "pack6" },
		},
		{
			id = "weapons",
			name = "Weapons",
			items = { "weaponBoomerang", "weaponWhip", "weaponFan", "weaponYoyo", "weaponDart" },
		},
		{
			id = "effects",
			name = "Effects",
			items = {
				"tint1",
				"tint2",
				"tint3",
				"tint4",
				"tint5",
				"tint6",
				"tint7",
				"tint8",
				"tint9",
				"tint10",
			},
		},
		{
			id = "emotes",
			name = "Emotes",
			items = {
				"emote3",
				"emote4",
				"emote5",
				"emote6",
				"emote7",
				"emote8",
				"emote9",
				"emote10",
				"pose21",
				"pose22",
				"pose23",
				"pose24",
			},
		},
		{ id = "passes", name = "Passes", items = { "quickSwap", "double" } },
		{ id = "slots", name = "Slots", items = { "slot3", "slot4" } },
	},

	-- Costume packs: the Robux pieces in Config.Creator ("pack:N"); 34 spec pieces in packs 1 to 5, the 8
	-- anime pieces in pack 6 (nate's anime addition)
	packs = {
		{ name = "Night Patrol", color = { 40, 50, 110 } },
		{ name = "Storm Front", color = { 110, 210, 255 } },
		{ name = "Iron Bastion", color = { 175, 180, 190 } },
		{ name = "Neon Rogue", color = { 240, 110, 190 } },
		{ name = "Solar Crown", color = { 255, 210, 60 } },
		{ name = "Spirit Blade", color = { 255, 70, 90 } },
		{ name = "Street Legend", color = { 255, 140, 40 } },
	},
	-- Starter pack: shown once after the first world boss, easy to dismiss: a cape, a suit finish and an
	-- emote (the Creator's "starter" pieces and emote bit 11)
	starter = { emote = 11, after = "firstBoss" },

	-- Effect colours: a tint over your power effects (Comic and Anime styles alike); looks only
	tints = {
		{ name = "Crimson", color = { 235, 50, 70 } },
		{ name = "Gold", color = { 255, 205, 60 } },
		{ name = "Violet", color = { 150, 90, 255 } },
		{ name = "Mint", color = { 110, 240, 180 } },
		{ name = "Ice", color = { 200, 245, 255 } },
		{ name = "Rose", color = { 255, 130, 200 } },
		{ name = "Sunset", color = { 255, 130, 50 } },
		{ name = "Shadow", color = { 70, 40, 110 } },
		{ name = "Prism", color = { 255, 255, 255 }, rainbow = true },
		{ name = "Void", color = { 20, 10, 30 }, glow = { 190, 120, 255 } },
	},

	-- Emotes and landing poses. Bits in profile.emotes: 1 to 19 emotes, 20 to 31 landing poses.
	-- earned = a reward elsewhere (Fame ranks, the starter pack); the rest are sold above.
	-- PLACEHOLDER ART: poses are joint angles tweened on the rig until the animation pass (M11).
	emotes = {
		[1] = { name = "Salute", earned = true },
		[2] = { name = "Bow", earned = true },
		[3] = { name = "Wave" },
		[4] = { name = "Thumbs Up" },
		[5] = { name = "Flex" },
		[6] = { name = "Hero Pose" },
		[7] = { name = "Point Up" },
		[8] = { name = "Power Up" },
		[9] = { name = "Laugh" },
		[10] = { name = "Cape Swish" },
		[11] = { name = "Rookie Cheer", earned = true },
		[20] = { name = "Super Landing", earned = true, landing = true },
		[21] = { name = "Kneel Landing", landing = true },
		[22] = { name = "Spin Landing", landing = true },
		[23] = { name = "Crater Landing", landing = true },
		[24] = { name = "Float Down", landing = true },
	},
	emoteTime = 2.4, -- seconds a pose holds
	emoteRate = 1.5, -- seconds between emotes

	-- Voice packs: 6 short sounds each (M11 audio). PLACEHOLDER: sound ids are 0 until free-licensed clips.
	voiceSounds = {
		plucky = { 0, 0, 0, 0, 0, 0 },
		gravel = { 0, 0, 0, 0, 0, 0 },
		showboat = { 0, 0, 0, 0, 0, 0 },
		patrol = { 0, 0, 0, 0, 0, 0 },
	},

	-- Gizmo's shop at HQ: 40 base styles for Credits (spec: 500 to 3,000, 40 at launch): every Common,
	-- Uncommon and Rare gear style plus the 13 "Shop" styles (their own price). Buying unlocks the style for
	-- the account, the same as looting it. Credits only.
	gizmo = { tierPrice = { Common = 500, Uncommon = 1000, Rare = 2000 } },
}
