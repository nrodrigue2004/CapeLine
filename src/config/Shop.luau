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
	heroSlots = { free = 3, max = 10 }, -- hero save slots: 3 free, then slot4..slot10 above
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
		-- extra hero slots (nate, 2026-11-20: "99 Robux each, up to 10"): 3 free, slots 4 to 10 bought in order
		slot4 = { id = 0, robux = 99, kind = "slot", slot = 4 },
		slot5 = { id = 0, robux = 99, kind = "slot", slot = 5 },
		slot6 = { id = 0, robux = 99, kind = "slot", slot = 6 },
		slot7 = { id = 0, robux = 99, kind = "slot", slot = 7 },
		slot8 = { id = 0, robux = 99, kind = "slot", slot = 8 },
		slot9 = { id = 0, robux = 99, kind = "slot", slot = 9 },
		slot10 = { id = 0, robux = 99, kind = "slot", slot = 10 },
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
		-- the 5 Exotic weapons (nate 2026-11-16: "exotic should be robux"; 2026-11-21 card: "Robux only"):
		-- equal-strength sidegrades, owned for life. No other weapon is sold for Robux.
		weaponWhip = { id = 0, robux = 199, kind = "weapon", weapon = 32 },
		weaponFan = { id = 0, robux = 249, kind = "weapon", weapon = 33 },
		weaponYoyo = { id = 0, robux = 249, kind = "weapon", weapon = 34 },
		weaponDart = { id = 0, robux = 249, kind = "weapon", weapon = 35 },
		weaponBoomerang = { id = 0, robux = 149, kind = "weapon", weapon = 36 },
		-- H8: the Hero Pass's paid track for the current season (one product, every season; nate's call 4:
		-- 499 Robux, no tier skips). Cosmetics only; every reward is shown before buying (Config.Pass).
		heroPass = { id = 0, robux = 499, kind = "heroPass" },
		-- H8: travel power styles sold in the shop (Config.TravelStyles ids; 2 per mobility, 99 to 199 Robux)
		travel3 = { id = 0, robux = 99, kind = "travel", style = 3 },
		travel4 = { id = 0, robux = 149, kind = "travel", style = 4 },
		travel9 = { id = 0, robux = 99, kind = "travel", style = 9 },
		travel10 = { id = 0, robux = 149, kind = "travel", style = 10 },
		travel15 = { id = 0, robux = 99, kind = "travel", style = 15 },
		travel16 = { id = 0, robux = 149, kind = "travel", style = 16 },
		travel21 = { id = 0, robux = 99, kind = "travel", style = 21 },
		travel22 = { id = 0, robux = 149, kind = "travel", style = 22 },
		travel27 = { id = 0, robux = 149, kind = "travel", style = 27 },
		travel28 = { id = 0, robux = 199, kind = "travel", style = 28 },
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
				-- H8: travel power styles (Config.TravelStyles)
				"travel3",
				"travel4",
				"travel9",
				"travel10",
				"travel15",
				"travel16",
				"travel21",
				"travel22",
				"travel27",
				"travel28",
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
		-- H8: the Hero Pass leads the Passes tab (a seventh tab is too small to read on a phone)
		{ id = "passes", name = "Passes", items = { "heroPass", "quickSwap", "double" } },
		{
			id = "slots",
			name = "Slots",
			items = { "slot4", "slot5", "slot6", "slot7", "slot8", "slot9", "slot10" },
		},
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
		-- H8: Hero Pass season 1 tints (Config.Pass): earned on the pass, never sold in the shop
		{ name = "Sky Blue", color = { 90, 170, 255 }, pass = true },
		{ name = "Holo Gold", color = { 255, 225, 140 }, glow = { 255, 245, 200 }, pass = true },
		{ name = "Neon Night", color = { 255, 60, 200 }, glow = { 120, 60, 255 }, pass = true },
		{ name = "Halftone Red", color = { 230, 60, 50 }, pass = true },
		{ name = "Starlight", color = { 235, 240, 255 }, glow = { 170, 200, 255 }, pass = true },
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
		-- H6: each mentor's emote, the last part of their quest line (Config.Mentors)
		[12] = { name = "Sharp Salute", earned = true },
		[13] = { name = "Big Wave", earned = true },
		[14] = { name = "Grand Bow", earned = true },
		[15] = { name = "Shrug", earned = true },
		-- H7: badge accolades (finish a Badge Book group; Config.Badges)
		[16] = { name = "Double Thumbs Up", earned = true },
		[17] = { name = "Team Huddle", earned = true },
		-- H8: Hero Pass season 1 (Config.Pass)
		[18] = { name = "Comic Pose", earned = true },
		[19] = { name = "Spotlight Spin", earned = true },
		[20] = { name = "Super Landing", earned = true, landing = true },
		[21] = { name = "Kneel Landing", landing = true },
		[22] = { name = "Spin Landing", landing = true },
		[23] = { name = "Crater Landing", landing = true },
		[24] = { name = "Float Down", landing = true },
		[25] = { name = "Spotlight Landing", earned = true, landing = true }, -- H8: Hero Pass season 1
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
