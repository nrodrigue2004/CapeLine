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
			-- 2026-11-16 creator plan: more styles; extra pieces carry their own id base (id = base + n)
			extra = {
				base = 820,
				pieces = {
					{ "Afro", "afro", "free" },
					{ "Space Buns", "buns", "free" },
					{ "Mohawk", "mohawk", "free" },
					{ "Undercut", "undercut", "free" },
					{ "Long Straight", "long", "lvl:3" },
					{ "Bob Cut", "bob", "lvl:6" },
					{ "Locs", "locs", "lvl:10" },
					{ "High Ponytail", "pony", "drop" },
					{ "Curly Top", "curly", "mission:2" },
					{ "Side Shave", "sideshave", "pack:7" },
				},
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
		-- 2026-11-16 hero creator plan (nate): 12 new slots. These tabs carry a fixed id base, so the piece ids
		-- (the unlock bitset) stay put when a tab grows: piece i of a tab with base B has id B + i.
		-- PLACEHOLDER ART: LookKit builds them from simple parts until the Blender piece sets replace them.
		{
			id = "beard",
			name = "Facial hair",
			base = 300,
			pieces = {
				{ "Stubble", "stubble", "free" },
				{ "Goatee", "goatee", "free" },
				{ "Full Beard", "full", "free" },
				{ "Chin Strap", "strap", "lvl:5" },
				{ "Mutton Chops", "chops", "lvl:12" },
				{ "Handlebar", "handlebar", "drop" },
				{ "Braided Beard", "braid", "rep:league:2" },
				{ "Long Beard", "long", "pack:7" },
			},
		},
		{
			id = "face",
			name = "Face",
			base = 340,
			-- brows, eyes and mouth together; a glowing Eyes piece draws over the eyes
			pieces = {
				{ "Classic Smile", "smile", "free" },
				{ "Calm", "calm", "free" },
				{ "Grin", "grin", "free" },
				{ "Smirk", "smirk", "free" },
				{ "Focused", "focused", "lvl:3" },
				{ "Frown", "frown", "lvl:8" },
				{ "Shout", "shout", "lvl:18" },
				{ "Snarl", "snarl", "rep:syndicate:2" },
				{ "Fangs", "fangs", "drop" },
				{ "Scarred", "scar", "pack:7" },
			},
		},
		{
			id = "makeup",
			name = "Makeup",
			base = 380,
			pieces = {
				{ "Eyeliner", "liner", "free" },
				{ "Lipstick", "lips", "free" },
				{ "Blush", "blush", "free" },
				{ "Freckles", "freckles", "lvl:4" },
				{ "War Paint", "war", "lvl:14" },
				{ "Cheek Lines", "lines", "drop" },
				{ "Tear Streaks", "tears", "rep:syndicate:3" },
				{ "Half Paint", "half", "pack:7" },
			},
		},
		{
			id = "hat",
			name = "Headwear",
			base = 420,
			pieces = {
				{ "Ball Cap", "cap", "free" },
				{ "Beanie", "beanie", "free" },
				{ "Headband", "headband", "free" },
				{ "Shades", "shades", "free" },
				{ "Flight Goggles", "goggles", "lvl:6" },
				{ "Energy Visor", "visor", "lvl:10" },
				{ "Headphones", "phones", "lvl:16" },
				{ "Wide Brim", "brim", "mission:3" },
				{ "Top Hat", "tophat", "quest:3" },
				{ "Street Hood", "streethood", "drop" },
				{ "Iron Crown", "crown", "rep:league:4" },
				{ "Ram Horns", "horns", "rep:syndicate:4" },
				{ "Halo", "halo", "boss:LumenMaw:3" },
				{ "Plume Helm", "kabuto", "pack:7" },
				{ "Knight Helm", "knight", "pack:7" },
			},
		},
		{
			id = "ears",
			name = "Ears",
			base = 480,
			pieces = {
				{ "Studs", "studs", "free" },
				{ "Hoops", "hoops", "free" },
				{ "Comms Earpiece", "comms", "lvl:7" },
				{ "Dangles", "dangles", "drop" },
				{ "Ear Cuffs", "cuffs", "lvl:20" },
				{ "Wing Earrings", "wings", "pack:7" },
			},
		},
		{
			id = "shoulders",
			name = "Shoulders",
			base = 500,
			pieces = {
				{ "Shoulder Pads", "pads", "free" },
				{ "Studded Pads", "studded", "free" },
				{ "Epaulettes", "epaulettes", "free" },
				{ "Fur Trim", "fur", "lvl:9" },
				{ "Spiked Pads", "spikes", "lvl:15" },
				{ "Single Pauldron", "single", "drop" },
				{ "Layered Plates", "layered", "mission:6" },
				{ "Great Pauldrons", "pauldrons", "boss:RustjawPrime:2" },
				{ "Energy Coils", "coils", "pack:7" },
				{ "Crystal Shards", "crystal", "fame:6" },
			},
		},
		{
			id = "neck",
			name = "Neck",
			base = 540,
			pieces = {
				{ "Chain", "chain", "free" },
				{ "Pendant", "pendant", "free" },
				{ "Choker", "choker", "free" },
				{ "Dog Tags", "tags", "lvl:11" },
				{ "Bead Necklace", "beads", "drop" },
				{ "High Collar", "collar", "quest:5" },
				{ "Glow Amulet", "amulet", "rep:league:3" },
				{ "Gold Torc", "torc", "pack:7" },
			},
		},
		{
			id = "arms",
			name = "Arms",
			base = 580,
			pieces = {
				{ "Bracers", "bracers", "free" },
				{ "Sleeves", "sleeves", "free" },
				{ "Arm Wraps", "wraps", "free" },
				{ "Arm Bands", "bands", "lvl:6" },
				{ "Tattoo Lines", "tattoo", "lvl:13" },
				{ "Forearm Spikes", "spikes", "drop" },
				{ "Arm Plates", "armor", "mission:2" },
				{ "Power Rings", "coils", "pack:7" },
			},
		},
		{
			id = "wrist",
			name = "Rings and bracelets",
			base = 620,
			pieces = {
				{ "Ring", "ring", "free" },
				{ "Bracelet", "bracelet", "free" },
				{ "Two Rings", "rings", "lvl:5" },
				{ "Metal Cuffs", "cuffs", "lvl:17" },
				{ "Wrist Beads", "beads", "drop" },
				{ "Power Bands", "power", "fame:4" },
			},
		},
		{
			id = "belt",
			name = "Belt",
			base = 660,
			pieces = {
				{ "Plain Belt", "plain", "free" },
				{ "Utility Belt", "utility", "free" },
				{ "Sash", "sash", "free" },
				{ "Rope Belt", "rope", "lvl:8" },
				{ "Chain Belt", "chain", "drop" },
				{ "Thigh Holsters", "holsters", "lvl:19" },
				{ "Tech Belt", "tech", "quest:6" },
				{ "Champion Belt", "champion", "fame:10" },
			},
		},
		{
			id = "legs",
			name = "Legs",
			base = 700,
			-- legs colour the upper and lower legs over the suit; skirts and hakama add parts
			pieces = {
				{ "Pants", "pants", "free" },
				{ "Shorts", "shorts", "free" },
				{ "Joggers", "joggers", "free" },
				{ "Track Pants", "track", "free" },
				{ "Cargo Pants", "cargo", "lvl:4" },
				{ "Knee Pads", "kneepads", "lvl:9" },
				{ "Ripped Jeans", "ripped", "drop" },
				{ "Battle Skirt", "skirt", "lvl:22" },
				{ "Hakama", "hakama", "quest:4" },
				{ "Shin Greaves", "greaves", "mission:4" },
				{ "Leg Wraps", "legwraps", "rep:league:2" },
				{ "Armored Legs", "armored", "pack:7" },
			},
		},
		{
			id = "backpack",
			name = "Back bling",
			base = 760,
			pieces = {
				{ "Backpack", "backpack", "free" },
				{ "Sword Sheath", "sheath", "free" },
				{ "Quiver", "quiver", "free" },
				{ "Air Tanks", "tanks", "lvl:7" },
				{ "Jetpack", "jetpack", "lvl:12" },
				{ "Back Shield", "shield", "drop" },
				{ "Drone Pod", "drone", "mission:5" },
				{ "Feather Wings", "wings", "boss:LumenMaw:2" },
				{ "Bat Wings", "bat", "rep:syndicate:5" },
				{ "Halo Ring", "ring", "legacy:3" },
				{ "Energy Wings", "energy", "pack:7" },
				{ "Gear Rack", "rack", "boss:RustjawPrime:3" },
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

	-- 48 fixed colours (primary, secondary, accent, hair, eyes and every slot's own colours pick from these);
	-- 24 at M9, 24 more with the 2026-11-16 creator plan (never reorder: looks save the index)
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
		{ 255, 180, 180 }, -- 25 rose
		{ 255, 220, 140 }, -- 26 peach
		{ 180, 120, 40 }, -- 27 bronze
		{ 230, 190, 60 }, -- 28 mustard
		{ 90, 110, 40 }, -- 29 olive
		{ 30, 90, 50 }, -- 30 forest
		{ 170, 255, 200 }, -- 31 mint
		{ 20, 110, 120 }, -- 32 deep teal
		{ 60, 160, 230 }, -- 33 azure
		{ 70, 60, 160 }, -- 34 indigo
		{ 70, 20, 110 }, -- 35 deep purple
		{ 255, 60, 140 }, -- 36 hot pink
		{ 200, 30, 90 }, -- 37 magenta
		{ 110, 20, 25 }, -- 38 maroon
		{ 80, 50, 30 }, -- 39 chocolate
		{ 240, 225, 200 }, -- 40 bone
		{ 210, 200, 180 }, -- 41 sand
		{ 140, 140, 120 }, -- 42 khaki grey
		{ 85, 95, 110 }, -- 43 slate
		{ 40, 44, 60 }, -- 44 midnight
		{ 120, 255, 80 }, -- 45 toxic green
		{ 80, 255, 255 }, -- 46 cyan glow
		{ 255, 240, 80 }, -- 47 electric yellow
		{ 190, 90, 255 }, -- 48 ultraviolet
	},
	-- skin tones for the head and hands (the standard rig's body colours): 8 at M9, then (2026-11-16 creator
	-- plan) 16 more natural tones and 6 fantasy skins with their own material (never reorder)
	skins = {
		{ 255, 224, 196 },
		{ 241, 194, 160 },
		{ 224, 172, 130 },
		{ 198, 140, 100 },
		{ 160, 105, 70 },
		{ 120, 78, 52 },
		{ 86, 56, 38 },
		{ 60, 40, 28 },
		{ 255, 236, 220 },
		{ 250, 214, 186 },
		{ 236, 200, 160 },
		{ 230, 186, 140 },
		{ 214, 170, 120 },
		{ 210, 160, 130 },
		{ 190, 130, 90 },
		{ 176, 120, 80 },
		{ 150, 100, 60 },
		{ 140, 90, 64 },
		{ 110, 70, 46 },
		{ 100, 66, 50 },
		{ 92, 60, 40 },
		{ 74, 48, 34 },
		{ 52, 34, 26 },
		{ 44, 30, 24 },
		{ 150, 140, 130 },
		{ 170, 175, 185 },
		{ 190, 235, 255 },
		{ 255, 170, 60 },
		{ 50, 45, 70 },
		{ 200, 150, 255 },
	},
	-- the fantasy skins' material and name (by skin index)
	fantasySkins = {
		[25] = { mat = "Slate", name = "Stone" },
		[26] = { mat = "Metal", name = "Metal" },
		[27] = { mat = "Ice", name = "Ice" },
		[28] = { mat = "Neon", name = "Energy" },
		[29] = { mat = "SmoothPlastic", name = "Shadow" },
		[30] = { mat = "Glass", name = "Crystal" },
	},
	-- per-slot materials a player can pick (LookCodec mats; 0 = the piece's own)
	materials = { "Fabric", "Leather", "Metal", "SmoothPlastic", "Neon" },
	materialNames = { "Cloth", "Leather", "Metal", "Gloss", "Energy" },

	-- Body (2026-11-16 creator plan): looks only, never a stat; every hero shares one collider and hit capsule.
	-- builds scale the blocky R15 rig (width, depth, limb thickness, head, height) until the 8 Blender body
	-- sets replace the scaling with their own shapes
	body = {
		genders = { "Male", "Female" },
		builds = {
			{ name = "Small", width = 0.85, depth = 0.9, limbs = 0.85, hands = 1.0, head = 1.0, tall = 0.95 },
			{ name = "Medium", width = 1.0, depth = 1.0, limbs = 1.0, hands = 1.0, head = 1.0, tall = 1.0 },
			{
				name = "Large",
				width = 1.25,
				depth = 1.15,
				limbs = 1.2,
				hands = 1.15,
				head = 1.0,
				tall = 1.05,
			},
			{ name = "Titan", width = 1.6, depth = 1.4, limbs = 1.5, hands = 1.4, head = 0.9, tall = 1.15 },
		},
		heights = { 0.9, 0.95, 1.0, 1.05, 1.1 },
		-- Female: the upper torso tapers to a narrower waist (blocky, no other change)
		femaleWaist = 0.85,
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
		gender = 1,
		build = 2,
		height = 3,
	},
	-- Hero creator rules (spec: Done needs a title, a noun and a class; saves via Hero.Create)
	createRate = 10, -- seconds between saves
}
