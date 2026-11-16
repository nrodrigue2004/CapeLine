-- Creator: the hero creator's catalog (spec: Hero creator, about 120 pieces at launch; nate's 2026-11-16
-- anime additions: hair, coats, scarves, wraps, glowing eyes). Looks and stats are separate: every piece is
-- open to any class and side, and nothing here changes a number in a fight.
-- Each tab is one slot of the look record (LookCodec). A piece row is { name, kit, source }:
--   kit: how LookKit builds it from simple parts (PLACEHOLDER ART until the M9 accessory meshes and
--     generated emblem textures replace them)
--   source: "free" (every hero has it), "pack:N" (Robux costume pack N, Config.Shop), "starter" (the
--     starter pack), or how play unlocks it, account-wide and forever:
--     "lvl:L" any character reaches level L; "rep:league:R" / "rep:syndicate:R" a reputation rank;
--     "fame:R" a Fame or Infamy rank; "boss:Id:T" a world boss reward tier (1 joined, 2 contributor, 3 MVP);
--     "mission:N" mission N's first clear; "quest:N" side quest arc N done; "legacy:R" a Legacy rank;
--     "drop" a random locked piece from an Epic or Legendary drop (dropChance).
-- Spec counts (tests check them): Suits 14 (5 free, 5 loot, 4 Robux), Capes 12 (3/5/4), Masks 16 (5/6/5),
-- Gloves 8 (3/3/2), Boots 8 (3/3/2), Emblems 40 (8/20/12), Auras 6 (0/4/2), Flight trails 8 (2/4/2),
-- Voice packs 4 (1/2/1): 116 pieces (30/52/34). Anime pieces (28: 7 free, 13 loot, 8 Robux) sit in the
-- Capes (4 coats, 4 scarves) and Gloves (4 wraps) tabs and two new tabs, Hair (10) and Eyes (6). The
-- starter pack adds 2 (a suit finish and a cape). All names and symbols are original.
return {
	-- The look record's slot order (LookCodec bytes 2 to 12)
	tabs = {
		{
			id = "suit",
			name = "Suits",
			pieces = {
				{ "Rookie Suit", "plain", "free" },
				{ "Racer Stripe", "stripe", "free" },
				{ "Split Tone", "split", "free" },
				{ "Chevron Suit", "chevron", "free" },
				{ "Street Jacket", "jacket", "free" },
				{ "Plated Suit", "armor", "lvl:15" },
				{ "Reactor Core", "core", "boss:RustjawPrime:2" },
				{ "Circuit Suit", "circuit", "drop" },
				{ "Sash Fighter", "sash", "rep:league:2" },
				{ "Rib Frame", "ribs", "rep:syndicate:2" },
				{ "Night Patrol Suit", "panel", "pack:1" },
				{ "Storm Front Suit", "bolt", "pack:2" },
				{ "Bastion Suit", "bulwark", "pack:3" },
				{ "Neon Rogue Suit", "neon", "pack:4" },
				{ "Chrome Finish", "chrome", "starter" },
			},
		},
		{
			id = "back",
			name = "Capes",
			pieces = {
				{ "Short Cape", "cape:short", "free" },
				{ "Classic Cape", "cape:classic", "free" },
				{ "High Collar Cape", "cape:collar", "free" },
				{ "Long Cape", "cape:long", "lvl:10" },
				{ "Tattered Cape", "cape:tattered", "rep:syndicate:3" },
				{ "Split Cape", "cape:split", "rep:league:3" },
				{ "Comet Cape", "cape:comet", "boss:LumenMaw:2" },
				{ "Royal Mantle", "cape:mantle", "legacy:2" },
				{ "Night Patrol Cape", "cape:long", "pack:1" },
				{ "Storm Front Cape", "cape:split", "pack:2" },
				{ "Neon Rogue Cape", "cape:tattered", "pack:4" },
				{ "Solar Crown Cape", "cape:mantle", "pack:5" },
				-- anime: coats and scarves
				{ "Field Coat", "coat:short", "free" },
				{ "Duster Coat", "coat:long", "lvl:20" },
				{ "Captain's Coat", "coat:shoulder", "pack:6" },
				{ "Shadow Longcoat", "coat:shadow", "pack:6" },
				{ "Hero Scarf", "scarf:one", "free" },
				{ "Twin Tail Scarf", "scarf:two", "drop" },
				{ "Wind Scarf", "scarf:long", "quest:4" },
				{ "Spirit Scarf", "scarf:spirit", "pack:6" },
				{ "Starter Cape", "cape:classic", "starter" },
			},
		},
		{
			id = "head",
			name = "Masks",
			pieces = {
				{ "Domino Mask", "domino", "free" },
				{ "Cowl", "cowl", "free" },
				{ "Visor Band", "visor", "free" },
				{ "Half Mask", "half", "free" },
				{ "Bandana Mask", "bandana", "free" },
				{ "Full Helm", "helm", "lvl:25" },
				{ "Crest Helm", "crest", "rep:league:4" },
				{ "Horned Helm", "horns", "rep:syndicate:4" },
				{ "Antenna Helm", "antenna", "drop" },
				{ "Hood", "hood", "quest:2" },
				{ "Frame Helm", "frame", "mission:6" },
				{ "Night Patrol Cowl", "cowl", "pack:1" },
				{ "Storm Front Helm", "crest", "pack:2" },
				{ "Bastion Helm", "helm", "pack:3" },
				{ "Neon Rogue Visor", "visor", "pack:4" },
				{ "Solar Crown", "crown", "pack:5" },
			},
		},
		{
			id = "hands",
			name = "Gloves",
			pieces = {
				{ "Gloves", "glove", "free" },
				{ "Long Cuffs", "cuff", "free" },
				{ "Fingerless Gloves", "fingerless", "free" },
				{ "Spiked Gloves", "spiked", "rep:syndicate:1" },
				{ "Armored Gauntlets", "gauntlet", "lvl:30" },
				{ "Spark Gloves", "spark", "drop" },
				{ "Storm Front Gloves", "cuff", "pack:2" },
				{ "Neon Rogue Claws", "claws", "pack:4" },
				-- anime: wraps
				{ "Hand Wraps", "wraps", "free" },
				{ "Fighter Wraps", "wraps:long", "quest:6" },
				{ "Spirit Wraps", "wraps:glow", "drop" },
				{ "Shadow Wraps", "wraps:dark", "pack:6" },
			},
		},
		{
			id = "feet",
			name = "Boots",
			pieces = {
				{ "Boots", "boot", "free" },
				{ "Tall Boots", "tall", "free" },
				{ "Sneakers", "sneaker", "free" },
				{ "Winged Boots", "winged", "rep:league:1" },
				{ "Jet Boots", "jet", "boss:RustjawPrime:1" },
				{ "Armored Boots", "armored", "drop" },
				{ "Night Patrol Boots", "tall", "pack:1" },
				{ "Bastion Boots", "armored", "pack:3" },
			},
		},
		{
			id = "emblem",
			name = "Emblems",
			-- kit "shape:backing": shape from shapes below; backing none, badge (circle), crest (shield), gem
			pieces = {
				{ "Star", "star:none", "free" },
				{ "Spark", "spark:none", "free" },
				{ "Diamond", "diamond:none", "free" },
				{ "Orb", "orb:none", "free" },
				{ "Peak", "peak:none", "free" },
				{ "Heart", "heart:none", "free" },
				{ "Cross", "cross:none", "free" },
				{ "Moon", "moon:none", "free" },
				{ "Clover", "clover:none", "drop" },
				{ "Flower", "flower:none", "drop" },
				{ "Star Badge", "star:badge", "lvl:5" },
				{ "Spark Badge", "spark:badge", "drop" },
				{ "Diamond Badge", "diamond:badge", "drop" },
				{ "Orb Badge", "orb:badge", "mission:2" },
				{ "Peak Badge", "peak:badge", "drop" },
				{ "Heart Badge", "heart:badge", "quest:1" },
				{ "Cross Badge", "cross:badge", "quest:3" },
				{ "Moon Badge", "moon:badge", "drop" },
				{ "Clover Badge", "clover:badge", "drop" },
				{ "Flower Badge", "flower:badge", "rep:league:5" },
				{ "Star Crest", "star:crest", "legacy:1" },
				{ "Spark Crest", "spark:crest", "fame:2" },
				{ "Diamond Crest", "diamond:crest", "drop" },
				{ "Orb Crest", "orb:crest", "mission:3" },
				{ "Peak Crest", "peak:crest", "rep:syndicate:5" },
				{ "Heart Crest", "heart:crest", "quest:5" },
				{ "Cross Crest", "cross:crest", "drop" },
				{ "Moon Crest", "moon:crest", "boss:LumenMaw:1" },
				{ "Moon Gem", "moon:gem", "pack:1" },
				{ "Star Gem", "star:gem", "pack:1" },
				{ "Spark Gem", "spark:gem", "pack:2" },
				{ "Cross Gem", "cross:gem", "pack:2" },
				{ "Diamond Gem", "diamond:gem", "pack:3" },
				{ "Peak Gem", "peak:gem", "pack:3" },
				{ "Clover Crest", "clover:crest", "pack:3" },
				{ "Heart Gem", "heart:gem", "pack:4" },
				{ "Orb Gem", "orb:gem", "pack:4" },
				{ "Flower Gem", "flower:gem", "pack:5" },
				{ "Clover Gem", "clover:gem", "pack:5" },
				{ "Flower Crest", "flower:crest", "pack:5" },
			},
		},
		{
			id = "aura",
			name = "Auras",
			pieces = {
				{ "Ember Aura", "ember", "drop" },
				{ "Frost Mist", "mist", "fame:5" },
				{ "Static Aura", "static", "boss:LumenMaw:3" },
				{ "Spirit Flame", "spirit", "legacy:3" },
				{ "Bastion Shimmer", "shimmer", "pack:3" },
				{ "Solar Aura", "solar", "pack:5" },
			},
		},
		{
			id = "trail",
			name = "Flight trails",
			pieces = {
				{ "Ribbon Trail", "ribbon", "free" },
				{ "Streak Trail", "streak", "free" },
				{ "Twin Ribbon", "twin", "lvl:35" },
				{ "Sparkle Trail", "sparkle", "fame:7" },
				{ "Comet Trail", "comet", "boss:RustjawPrime:3" },
				{ "Smoke Trail", "smoke", "legacy:4" },
				{ "Storm Trail", "storm", "pack:2" },
				{ "Neon Trail", "neon", "pack:4" },
			},
		},
		{
			id = "voice",
			name = "Voice",
			-- 6 short sounds each (M11 audio; sound ids in Config.Shop.voiceSounds are PLACEHOLDER 0s)
			pieces = {
				{ "Plucky", "plucky", "free" },
				{ "Gravel", "gravel", "lvl:40" },
				{ "Showboat", "showboat", "fame:8" },
				{ "Night Patrol Voice", "patrol", "pack:1" },
			},
		},
		{
			id = "hair",
			name = "Hair",
			pieces = {
				{ "Spiky", "spiky", "free" },
				{ "Swept", "swept", "free" },
				{ "Short Crop", "crop", "free" },
				{ "Long Tail", "tail", "mission:4" },
				{ "Twin Tails", "twin", "drop" },
				{ "Wild Mane", "mane", "quest:7" },
				{ "Topknot", "topknot", "drop" },
				{ "Crest Flare", "flare", "legacy:5" },
				{ "Sky Spikes", "sky", "pack:6" },
				{ "Flowing Mane", "flow", "pack:6" },
			},
		},
		{
			id = "eyes",
			name = "Eyes",
			-- glowing eyes; kit is the glow colour: accent, gold, ice, ember, or a two-tone
			pieces = {
				{ "Accent Glow", "accent", "free" },
				{ "Gold Glow", "gold", "quest:8" },
				{ "Ice Glow", "ice", "mission:5" },
				{ "Ember Glow", "ember", "drop" },
				{ "Spirit Glow", "spirit", "pack:6" },
				{ "Prism Glow", "prism", "pack:6" },
			},
		},
	},

	-- Emblem shapes (PLACEHOLDER ART: a glyph on a backing until the generated, hand-cleaned emblem set;
	-- review every emblem before each release so none resembles a famous symbol)
	shapes = {
		star = "★",
		spark = "✦",
		diamond = "◆",
		orb = "●",
		peak = "▲",
		heart = "♥",
		cross = "✚",
		moon = "☾",
		clover = "♣",
		flower = "✿",
	},

	-- 24 fixed colours (primary, secondary, accent and hair all pick from these)
	palette = {
		{ 235, 60, 60 }, -- 1 red
		{ 160, 30, 45 }, -- 2 crimson
		{ 255, 140, 40 }, -- 3 orange
		{ 255, 210, 60 }, -- 4 gold
		{ 250, 240, 150 }, -- 5 cream
		{ 140, 210, 70 }, -- 6 lime
		{ 40, 150, 80 }, -- 7 green
		{ 40, 190, 170 }, -- 8 teal
		{ 110, 210, 255 }, -- 9 sky
		{ 40, 110, 220 }, -- 10 blue
		{ 30, 45, 120 }, -- 11 navy
		{ 120, 80, 220 }, -- 12 violet
		{ 190, 110, 240 }, -- 13 lilac
		{ 240, 110, 190 }, -- 14 pink
		{ 150, 40, 110 }, -- 15 plum
		{ 120, 75, 45 }, -- 16 brown
		{ 200, 160, 110 }, -- 17 tan
		{ 245, 245, 245 }, -- 18 white
		{ 175, 180, 190 }, -- 19 silver
		{ 110, 115, 125 }, -- 20 steel
		{ 55, 58, 66 }, -- 21 charcoal
		{ 24, 24, 28 }, -- 22 black
		{ 200, 240, 255 }, -- 23 ice
		{ 255, 90, 40 }, -- 24 ember
	},
	-- skin tones for the head and hands (the standard rig's body colours)
	skins = {
		{ 255, 224, 196 },
		{ 241, 194, 160 },
		{ 224, 172, 130 },
		{ 198, 140, 100 },
		{ 160, 105, 70 },
		{ 120, 78, 52 },
		{ 86, 56, 38 },
		{ 60, 40, 28 },
	},

	-- Hero names: a Title and a Noun from wheels; nothing typed. A hero shows as "Storm Falcon" with the
	-- Roblox name small below.
	titles = {
		"Captain",
		"Doctor",
		"Storm",
		"Iron",
		"Night",
		"Star",
		"Shadow",
		"Blaze",
		"Silver",
		"Thunder",
		"Mystic",
		"Turbo",
	},
	nouns = {
		"Falcon",
		"Comet",
		"Bolt",
		"Raven",
		"Fox",
		"Tiger",
		"Wolf",
		"Spark",
		"Nova",
		"Fang",
		"Vector",
		"Echo",
		"Viper",
		"Pulse",
		"Orbit",
		"Gale",
	},
	-- The hero-name filter (spec risk: "a hero-name filter"): pairs that name a real character, team or
	-- product are not allowed. Re-check this list before each release (Launch Checklist).
	blockedNames = {
		"Captain Falcon",
		"Captain Comet",
		"Star Fox",
		"Star Wolf",
		"Silver Fox",
		"Silver Fang",
		"Night Wolf",
		"Night Raven",
		"Storm Raven",
		"Thunder Bolt",
	},

	-- Gear styles and creator pieces: a creator piece takes over the gear slot it covers; a style picked in
	-- the Style Collection (Show Style) still shows over it. Legs and belt always show gear.
	covers = { head = "head", chest = "suit", hands = "hands", feet = "feet", back = "back" },
	looks = 4, -- saved looks (the 4 mannequins at HQ; HQ level 1 shows 1, level 2 all 4)
	dropChance = 0.15, -- an Epic or Legendary drop also unlocks a random locked "drop" piece
	-- A new hero before the creator: these free pieces (tab index -> piece index), colours and skin
	default = {
		pieces = { suit = 1, back = 2, head = 1, hands = 1, feet = 1, emblem = 1, trail = 1, voice = 1 },
		colors = { 10, 1, 4 },
		hair = 22,
		skin = 3,
	},
	-- Hero creator rules (spec: Done needs a title, a noun and a class; saves via Hero.Create)
	createRate = 10, -- seconds between saves
}
