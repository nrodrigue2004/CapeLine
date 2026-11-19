--!strict
-- PocketKit: the mission and side quest pockets' kit look (2026-11-19, the pocket kit pass; Shared.PocketDress).
-- The pockets (Shared.PocketLayout) keep every box exactly where and how big it is; the kit only changes how a box
-- looks (its kit texture, its tint, its plain material) and adds non-colliding dressing round it (trims, neon
-- accents, lamps with lights, kit street props and comic sign boards).
-- looks: a pocket's material map. A box's look is found by the first key that matches, most exact first:
--   "kind:color:shape", "kind:color", "color", "kind" (the box's PocketLayout kind, palette colour and shape).
--   Each look is { kit, tint, mat }: kit a "Kit" .. name MaterialVariant (Config.City.kit; a list picks one by
--   position, so a row of buildings doesn't repeat), tint the palette colour it shows in (else its own), mat the
--   plain Roblox material for a box without a texture (lamps, metal, cloth).
-- backdrop: an indoor pocket's walls just inside its sealed glass (ghosts: the glass still stops everything), so
-- rooms read as rooms and the lower floors as cellars: kit, tint, height.
-- trim: the colour of the caps on top of walls and the skirting at their feet; accent: the pocket's neon colour.
-- signs: each pocket's comic sign boards (fixed text, never typed by players): text, board colour, ink colour.
-- Lamps: every small glow box of a `lamps` colour gets a PointLight in its own colour (tier 2; the pocket's key
-- lights are tier 1), within the preset's light budget (Config.Presets <preset>.pockets).

local CONCRETE = { kit = "Concrete" }
local METAL = { mat = "Metal" }

return {
	-- the pockets' own tiling textures (art/city/pocket_materials.py; Config.City.kit lists their tile sizes and base
	-- materials): the city itself uses none of them
	textures = {
		"Planks",
		"Tile",
		"CaveRock",
		"Concrete",
		"SteelPlate",
		"Block",
		"Sand",
		"Ashlar",
		"Brickwork",
	},
	-- glow colours that are lamps (a PointLight goes on each, nearest the middle first)
	lamps = {
		workLamp = true,
		foundryGlow = true,
		beaconLight = true,
		sparkGlow = true,
		beaconGlow = true,
		relicRed = true,
		nullGlow = true,
	},
	light = { range = 22, brightness = 1.4, key = { range = 40, brightness = 2 } },
	-- a wall (a building box at least this tall and at most this thick) gets a cap and skirting
	wall = { minHeight = 10, maxThick = 6, cap = 0.8, capProud = 0.4, skirt = 1.2, skirtProud = 0.3 },
	-- the comic sign boards: an ink outline round a coloured board, Bangers lettering in a thick stroke
	sign = { outline = 0.5, depth = 0.4, pixels = 40, stroke = 4, bulbEvery = 4, bulb = 0.7 },
	pockets = {
		-- Downtown blocks (the station layout, kept for later acts)
		station = {
			trim = "cornice",
			accent = "beaconGlow",
			looks = {
				["building:concrete"] = { kit = { "Brick", "Office", "Deco", "Stone" } },
				["roof:roof"] = { kit = "Concrete", tint = "pkRoofGrey" },
				["road:road"] = { kit = "Asphalt" },
				["plaza:sidewalk"] = { kit = "Paving" },
				["prop:steel"] = { kit = "SteelPlate", tint = "pkSteel" },
			},
		},
		-- The Signal: Crane Tower in Uptown
		tower = {
			trim = "pkSteelDark",
			accent = "beaconGlow",
			looks = {
				["building:slate"] = { kit = "Prism", tint = "upViolet" },
				["ledge:steel"] = { kit = "SteelPlate", tint = "pkSteel" },
				["roof:roof"] = { kit = "SteelPlate", tint = "pkDeck" },
				["plaza:sidewalk"] = { kit = "Terrazzo" },
				["prop:steel"] = { kit = "SteelPlate", tint = "pkSteelDark" },
			},
			signs = { top = { text = "CRANE TOWER", board = "craneNavy", ink = "pkSignCream" } },
		},
		-- The Copy: Old Town's roofs
		rooftops = {
			trim = "pkSignCream",
			accent = "window",
			looks = {
				["building:brick"] = { kit = "OldBrick" },
				["building:concrete"] = {
					kit = "Plaster",
					tint = { "plYellow", "plPeach", "plMint", "plSky", "plRose" },
				},
				["roof:roofRed"] = { kit = "Concrete", tint = "pkRoofWarm" },
				["roof:roofBlue"] = { kit = "Concrete", tint = "pkRoofCool" },
				["plaza:sidewalk"] = { kit = "Cobble" },
			},
		},
		-- Safehouse: the old tunnels under the plaza (the Vigil hideout's look)
		dungeon = {
			trim = "pkStage",
			accent = "beaconGlow",
			looks = {
				["building:tunnel"] = { kit = "Concrete", tint = "pkTunnelWall" },
				["plaza:sidewalk"] = { kit = "Concrete", tint = "pkTunnelFloor" },
				["prop:steel"] = METAL,
				["prop:rust"] = METAL,
			},
			signs = { door = { text = "THE VIGIL", board = "pkSignNavy", ink = "pkSignGold" } },
		},
		-- Live: the fake's stage show
		arena = {
			trim = "pkStageTrim",
			accent = "pkStageTrim",
			looks = {
				["building:slate:cylinder"] = { kit = "Concrete", tint = "pkPillar" },
				["building:slate"] = { kit = "Planks", tint = "pkStage" },
				["plaza:sidewalk"] = { kit = "Terrazzo" },
				["prop:steel"] = METAL,
			},
			signs = { stage = { text = "LIVE!", board = "pkStageTrim", ink = "pkSignCream" } },
		},
		-- Framed: the rail and road bridge
		bridge = {
			trim = "pkSteelDark",
			accent = "window",
			looks = {
				["building:steel"] = { kit = "SteelPlate", tint = "pkBridgeRed" },
				["ledge:steel"] = { kit = "SteelPlate", tint = "pkBridgeRed" },
				["road:road"] = { kit = "Asphalt" },
				["plaza:water"] = { mat = "SmoothPlastic" },
			},
			signs = { gate = { text = "HARBOR BRIDGE", board = "pkSignTeal", ink = "pkSignCream" } },
		},
		-- The prologue's subway: cream tiles and a green band
		subway = {
			trim = "pkSubwayBand",
			accent = "pkSubwayBand",
			looks = {
				["building:foundry:ceiling"] = { kit = "Concrete", tint = "pkSubwayCeil" },
				["building:foundry"] = { kit = "Tile", tint = "pkSubwayTile" },
				["road:road"] = { kit = "Concrete", tint = "pkTrackBed" },
				["prop:steel"] = METAL,
				["plaza:sidewalk"] = CONCRETE,
			},
			signs = { station = { text = "PLAZA STATION", board = "pkSubwayBand", ink = "pkSignCream" } },
		},
		-- Halo Academy
		academy = {
			backdrop = { kit = "Block", tint = "pkAcademyWall", h = 60 },
			trim = "pkAcademyTrim",
			accent = "beaconGlow",
			looks = {
				["building:sand"] = { kit = "Ashlar", tint = "pkAcademyStone" },
				["plaza:wood"] = { kit = "Planks", tint = "pkOak" },
				["building:white"] = { kit = "Block", tint = "pkAcademyWall" },
				["building:concrete"] = CONCRETE,
				["building:tunnel:ceiling"] = { kit = "SteelPlate", tint = "pkWorkshopCeil" },
				["building:tunnel"] = { kit = "Block", tint = "pkWorkshopWall" },
				["plaza:roofBlue"] = { mat = "Fabric", tint = "pkMatBlue" },
				["prop:wood"] = { kit = "Planks", tint = "pkOak" },
				["prop:slate"] = { mat = "Slate", tint = "pkChalk" },
				["prop:white"] = { kit = "Ashlar", tint = "pkMarble" },
				["prop:steel"] = METAL,
				["prop:nullMetal"] = METAL,
				["plaza:sidewalk"] = { kit = "Concrete", tint = "pkTunnelFloor" },
			},
			signs = { front = { text = "HALO ACADEMY", board = "pkAcademyTrim", ink = "pkSignGold" } },
		},
		-- Tick-Tock Toys
		toyshop = {
			backdrop = { kit = "Brickwork", tint = "pkToyBrick", h = 56 },
			trim = "pkToyTrim",
			accent = "pkToyTrim",
			looks = {
				["building:sand"] = { kit = "Brickwork", tint = "pkToyBrick" },
				["plaza:wood"] = { kit = "Planks", tint = "pkToyFloor" },
				["building:white"] = { kit = "Block", tint = "pkToyWall" },
				["building:concrete"] = CONCRETE,
				["building:tunnel:ceiling"] = { kit = "Planks", tint = "pkJoist" },
				["building:tunnel"] = { kit = "Brickwork", tint = "pkToyBrick" },
				["plaza:roofRed"] = { mat = "Fabric", tint = "pkRug" },
				["prop:wood"] = { kit = "Planks", tint = "pkJoist" },
				["prop:roof"] = { mat = "Metal", tint = "pkBrass" },
				["prop:steel"] = METAL,
				["plaza:sidewalk"] = { kit = "Concrete", tint = "pkTunnelFloor" },
			},
			signs = { front = { text = "TICK-TOCK TOYS", board = "pkToyTrim", ink = "pkSignCream" } },
		},
		-- Captain Brine's sea cave
		seacave = {
			backdrop = { kit = "CaveRock", tint = "pkCaveRock", h = 60 },
			trim = "pkDriftwood",
			accent = "sparkGlow",
			looks = {
				["building:rock"] = { kit = "CaveRock", tint = "pkCaveRock" },
				["plaza:seabed"] = { kit = "Sand", tint = "pkWetSand" },
				["plaza:wood"] = { kit = "Planks", tint = "pkDriftwood" },
				["prop:rock"] = { kit = "CaveRock", tint = "pkCaveRock" },
				["prop:wood"] = { kit = "Planks", tint = "pkDriftwood" },
				["prop:wreck"] = { kit = "Planks", tint = "wreck" },
				["prop:steel"] = METAL,
				["plaza:sidewalk"] = { kit = "Sand", tint = "pkWetSand" },
			},
			signs = { wharf = { text = "KEEP OUT!", board = "pkDriftwood", ink = "pkSignRed" } },
		},
		-- Velmara, the drowned city
		velmara = {
			backdrop = { kit = "Ashlar", tint = "pkVelDark", h = 60 },
			trim = "pkBronze",
			accent = "sparkGlow",
			looks = {
				["building:slate:ceiling"] = { kit = "Ashlar", tint = "pkVelDark" },
				["building:slate"] = { kit = "Ashlar", tint = "pkVelStone" },
				["plaza:sand"] = { kit = "Flagstone" },
				["plaza:white"] = { kit = "Ashlar", tint = "pkMarble" },
				["prop:rust"] = { mat = "Metal", tint = "pkBronze" },
				["prop:white"] = { kit = "Ashlar", tint = "pkMarble" },
				["prop:slate"] = { kit = "Ashlar", tint = "pkVelStone" },
				["prop:rock"] = { kit = "CaveRock", tint = "pkVelDark" },
				["plaza:sidewalk"] = { kit = "Sand", tint = "pkSeaSand" },
			},
		},
		-- The Pit: the Old Quarry's fight club
		pit = {
			backdrop = { kit = "CaveRock", tint = "pkQuarry", h = 60 },
			trim = "pkDojoDark",
			accent = "relicRed",
			looks = {
				["building:rock"] = { kit = "CaveRock", tint = "pkQuarry" },
				["plaza:sand"] = { kit = "Sand", tint = "pkPitSand" },
				["building:roofBlue"] = { kit = "SteelPlate", tint = "pkRingBlue" },
				["plaza:white"] = { mat = "Fabric", tint = "pkCanvas" },
				["prop:wood"] = { kit = "Planks", tint = "pkDriftwood" },
				["prop:steel"] = METAL,
				["plaza:sidewalk"] = { kit = "Sand", tint = "pkPitSand" },
			},
			signs = { pit = { text = "THE PIT", board = "pkSignRed", ink = "pkSignGold" } },
		},
		-- Ashgrove Labs
		ashlab = {
			backdrop = { kit = "Tile", tint = "pkLabWall", h = 56 },
			trim = "pkLabTrim",
			accent = "beaconGlow",
			looks = {
				["building:concrete"] = CONCRETE,
				["plaza:white"] = { kit = "Tile", tint = "pkLabFloor" },
				["building:white"] = { kit = "Tile", tint = "pkLabWall" },
				["building:slate:ceiling"] = { kit = "SteelPlate", tint = "pkLabCeil" },
				["plaza:slate"] = { kit = "SteelPlate", tint = "pkSteelDark" },
				["prop:steel"] = METAL,
				["prop:roofBlue"] = { mat = "SmoothPlastic", tint = "pkLabTrim" },
				["plaza:sidewalk"] = { kit = "Tile", tint = "pkLabCeil" },
			},
			signs = { front = { text = "ASHGROVE LABS", board = "pkSignCream", ink = "pkLabTrim" } },
		},
		-- Gale's Iron Hall
		ironhall = {
			backdrop = { kit = "Brickwork", tint = "pkIronBrick", h = 56 },
			trim = "pkDojoDark",
			accent = "foundryGlow",
			looks = {
				["building:brick"] = { kit = "Brickwork", tint = "pkIronBrick" },
				["plaza:wood"] = { kit = "Planks", tint = "pkDojoWood" },
				["building:rock:ceiling"] = { kit = "Planks", tint = "pkDojoDark" },
				["building:rock"] = { kit = "Ashlar", tint = "pkIronStone" },
				["plaza:roofRed"] = { mat = "Fabric", tint = "pkMatRed" },
				["prop:wood"] = { kit = "Planks", tint = "pkDojoWood" },
				["prop:steel"] = METAL,
				["prop:bank"] = { mat = "Metal", tint = "relicGold" },
				["plaza:sidewalk"] = { kit = "Planks", tint = "pkDojoDark" },
			},
			signs = { front = { text = "IRON HALL", board = "pkSignInk", ink = "pkSignRed" } },
		},
		-- The Spark Pound, a Docks warehouse
		pound = {
			backdrop = { kit = "Warehouse", tint = "whTeal", h = 28 },
			trim = "pkHazard",
			accent = "relicRed",
			looks = {
				["plaza:concrete"] = { kit = "Concrete", tint = "pkPoundFloor" },
				["building:steel:ceiling"] = { kit = "SteelPlate", tint = "pkPoundRoof" },
				["building:tunnel"] = { kit = "Warehouse", tint = "whTeal" },
				["building:slate"] = { kit = "SteelPlate", tint = "pkSteelDark" },
				["prop:steel"] = METAL,
				["prop:wood"] = { kit = "Planks", tint = "pkDriftwood" },
				["prop:cargo"] = { kit = "Planks", tint = "cargo" },
			},
			signs = { front = { text = "SPARK POUND", board = "pkHazard", ink = "pkSignInk" } },
		},
	},
}
