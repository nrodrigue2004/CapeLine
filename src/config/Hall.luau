--!strict
-- Hall: Crane's Hero Hall, the Beacon Tower's enterable base, and the hub plaza round it (nate 2026-11-20
-- 22:04Z on the card, Mix: "a lobby (leaderboards, Hall of Fame statues, shop counter, squad and contract
-- boards), a training floor upstairs (dummies to test every power and weapon, mini challenges), and a rooftop
-- launch pad"; 22:06Z: "the plaza around it becomes a hub too"; 2026-11-21 00:16Z: "still cant enter building by
-- hub area and it doesnt look like a hub area").
--
-- The tower keeps its 46 x 46 footprint (the Ceremony stage, the Live mission's set, the board, the Safehouse
-- stairwell, the contest corner and the spawns all stand round it as before); its bottom two storeys are hollow:
-- the lobby on the plaza, the training floor over it, the solid tower above. Doors on the front (-z), back and west
-- faces; the east face stays whole (the Ceremony's backdrop) with the big sign. Shared.HallLayout turns these
-- numbers into the city's boxes and the named spots the services and devices use. Every length is in studs
-- from the tower's centre (x east, -z the front: the canopy door) and from the plaza's top (y). PLACEHOLDER ART: plain parts in the
-- city's palette until a Blender pass.
return {
	on = true,
	name = "HERO HALL", -- the signs (the lore's "Crane's Hero Hall" is the beacon's and the map's name)
	wall = 2, -- the outer walls' thickness
	slab = 2, -- each floor slab's thickness
	lobbyHeight = 22, -- the lobby's clear height (plaza top to the slab over it)
	trainHeight = 20, -- the training floor's clear height
	-- the doorways (open gaps, walk or fly in): width, height; on these faces (x, z: -1 west / 1 east, ...)
	door = { width = 12, height = 15, faces = { { 0, -1 }, { 0, 1 }, { -1, 0 } } },
	-- the training floor's window band (glass panes that collide, see-through): from, to above that floor
	windows = { from = 5, to = 16, alpha = 0.55 },
	-- the stair up along the east wall, inside: its width, the steps' depth; it climbs to a landing at the back
	stair = { width = 6, step = 1.45, landing = 4 },
	-- the lifts, one column at the lobby's front-west corner, on every floor and the roof: prompt words per destination
	lift = { at = { -17.5, -12 }, radius = 3, dests = { "Lobby", "Training Floor", "Roof" } },
	-- the lobby: the Hall of Fame dais in the middle (the week's top 3 heroes as gold statues), the shop
	-- counter, the boards wall screen, the contract and squad boards
	lobby = {
		dais = { at = { -3, 0 }, radius = 7, height = 1.2 },
		statues = { { 0, -4, 1.0 }, { -4.2, 2.2, 0.85 }, { 4.2, 2.2, 0.85 } }, -- x, z from the dais, scale
		shop = { at = { -13.5, 17.5 }, size = { 11, 3.6, 3 } },
		boards = { at = { 10.5, 20.8 }, size = { 8, 5 }, y = 5 }, -- on the back wall, facing in
		contracts = { at = { -13.5, -20.8 }, size = { 8, 5 }, y = 5 }, -- on the front wall, facing in
		squads = { at = { 10.5, -20.8 }, size = { 8, 5 }, y = 5 },
		planters = { { -18.5, 18.5 }, { 18.5, -18.5 }, { -18.5, -18.5 } },
	},
	-- the training floor: a row of dummies to test every power and weapon on (shared by everyone there, each
	-- hero's own meter), the big one behind, the Burst Test pad (deal all you can in `seconds`), a Loadout
	-- terminal and a Weapon Rack (the Hall is a safe place, so swaps work there)
	training = {
		dummies = { { -16, 12 }, { -9.5, 12 }, { -3, 12 }, { 3.5, 12 } },
		big = { -6.5, 17.5 },
		radius = 2.4, -- each dummy's hit radius (the HQ's)
		bigRadius = 5,
		window = 5, -- seconds the DPS meter averages over
		burst = { at = { -3, -7 }, radius = 3.5, seconds = 20, board = 5 },
		scoreboard = { at = { -3, -20.8 }, size = { 12, 6 }, y = 6 }, -- the Burst Test's best on the front wall
		loadout = { at = { -18.5, 3 } },
		weapons = { at = { 9, -18.5 } },
	},
	-- the roof: a launch deck reaching out over the front face from the tower's top, the pad at its end flings
	-- you out over the city (up and away, then your own glide or flight)
	roof = {
		deck = { width = 12, length = 18, thick = 1.6 },
		pad = { radius = 3.5, up = 95, out = 150, hold = 0.25 },
		lift = { 0, 17 }, -- the roof's lift stop (x, z on the tower's top)
		rail = 3.2,
	},
	-- the hub plaza: benches round the Hall, carts and cafe tables, lamps and flower tubs on the front and back
	-- paving (the east side is the Ceremony crowd's, the west the board's and the stairwell's); the device's
	-- CityProps draws them like every street prop
	plaza = {
		benches = { { -14, 32, 180 }, { 14, 32, 180 }, { -14, -32, 0 }, { 14, -32, 0 } },
		carts = { { -24, 44, 90 }, { 24, -44, -90 } },
		cafes = { { 22, 42 }, { -22, -42 } },
		tubs = { { -8, 27 }, { 8, 27 }, { -8, -27 }, { 8, -27 } },
		lamps = { { -26, 28 }, { 26, 28 }, { -26, -28 }, { 26, -28 }, { 0, 50 }, { 0, -50 } },
		bins = { { -18, 30 }, { 18, -30 } },
		vending = { { 28, 34, -90 } },
		-- the meeting spot before the front door: a ring of light on the paving everyone can find
		meet = { at = { 0, -38 }, radius = 6 },
		-- a fountain on the back paving (the hub's other gathering spot), trees in planters, and a gold inlay
		-- strip round the Hall `inlay` studs out from its walls
		fountain = { at = { 0, 44 }, radius = 6, height = 2.2, jet = 9 },
		trees = { { -20, 48 }, { 20, -48 }, { -32, -34 } }, -- (clear of the board, the lore book and the stairwell)
		inlay = 5,
		-- the canopy over the front door (at the doorway's top) and the gold pillars holding it
		canopy = { depth = 8, width = 20, y = 15 },
	},
	range = 6, -- how near a terminal's prompt shows
}
