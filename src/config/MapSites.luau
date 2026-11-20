-- MapSites: where story missions play on the real map (missions lane, 2026-11-20; nate's call "Mix": story missions
-- play privately on the map, special places keep pockets). Shared.MapSites turns each pocket layout's named points
-- (Shared.PocketLayout: spawn, boss, stations, path, turrets...) into world points at its site, so Config.Story and the
-- step code stay as they are; MissionService builds the run's own set-piece boxes there as a phased Sites model
-- (Shared.PhaseRules: only the party sees, touches or fights them) and moves the party there and home after.
-- Kept as pockets: the Safehouse's tunnels ("dungeon"), the Ceremony's subway and every side quest pocket.
--
-- on: by pocket layout name (missions, task force legs and the Nemesis Showdown that use it): false sends that layout
-- back to its sealed pocket at y 3,000 (nate can flip any one back).
-- sites: x, z the site's middle (the pocket layout's centre lands here); yaw (0 or a multiple of 90 degrees) turns
-- the layout's own -z/+z to the world's; sx, sz scale its across and along spans to the real place.
--   permanent: the pocket's own boxes are a real piece of the city (WorldMap builds them for everyone, CityBuilder
--     makes the parts): Harbour Bridge (PLACEHOLDER NAME) over the Docks basin, Crane Tower in the hub between Old
--     Town and the Docks, and Crane's plant in the Docks' east warehouses. clear: circles no district lot, filler
--     building or warehouse is built in (r studs round x, z), so the piece stands alone.
--   otherwise the site is the real city: points on the ground settle onto open street or paving nearby (never in a
--     building), points the pocket had on a roof go onto the nearest real roof, and `keep` names the pocket box kinds
--     that come along as the run's own phased set pieces (the Live stage, its screen and pillars; Most Wanted's bins,
--     truck and tunnel mouth). Everything is checked in Lune (tests "Map sites").
--   at: a pocket point the site puts somewhere else (in the pocket's own studs, before the turn and scale).
-- lift: studs above the street a settled ground point stands (the paving and kerbs sit a little over the ground).
-- PLACEHOLDER ART: the bridge, Crane Tower, the plant and the set pieces are plain boxes in the city palette.

return {
	on = {
		bridge = true, -- Framed
		rooftops = true, -- The Copy
		tower = true, -- The Signal
		arena = true, -- Live (and the task forces' and the Nemesis Showdown's arena legs)
		station = true, -- Most Wanted (and the task forces' station legs)
		factory = true, -- The Line
	},
	lift = 0.5,
	-- how far (studs) a ground point may move to find open ground, and a roof point to find a roof; roofTop: the
	-- highest roof a point goes onto (no skyscraper tops: the pocket's roofs were a short climb)
	settle = { ground = 80, roof = 90, step = 4, roofTop = 200 },
	sites = {
		-- Framed: a rail and road bridge over the Docks basin (x 440 to 790), east to west, its decks 20 up
		bridge = {
			name = "Harbour Bridge",
			permanent = true,
			x = 615,
			z = 690,
			yaw = 90,
			sx = 1,
			sz = 0.95,
			clear = {}, -- over open water: nothing to clear
		},
		-- The Signal: Crane Tower, a 180-stud tower with a spiral of ledges, the top deck, mast and relay, in the
		-- hub filler between Old Town and the Docks (its lots kept clear)
		tower = {
			name = "Crane Tower",
			permanent = true,
			x = 450,
			z = 100,
			yaw = 0,
			sx = 1,
			sz = 1,
			clear = { { x = 450, z = 100, r = 80 } },
			-- (its ledges and top deck are left out of the city's height map: robots under them stay on the ground,
			-- and robots on them stand there through the site's own heights)
			nomap = { ledge = true, roof = true },
		},
		-- The Line: Crane's plant, a roofless hall on the open quay north-east of the warehouses (its open front west
		-- to the truck lane), the copier line down the middle. On open ground: no warehouse or lot moves (building
		-- ids stay); clear keeps the quay's street props out of the hall
		factory = {
			name = "Crane Plant",
			permanent = true,
			x = 660,
			z = 352,
			yaw = 270,
			sx = 0.42,
			sz = 0.72,
			base = 0.6, -- the Docks quay's top
			-- (squares: x, z +-r; the hall spans x 552 to 768, z 306 to 398)
			clear = {
				{ x = 598, z = 352, r = 46 },
				{ x = 660, z = 352, r = 46 },
				{ x = 722, z = 352, r = 46 },
			},
		},
		-- The Copy: Old Town's real roofs west of Clock Square
		rooftops = { name = "Old Town roofs", x = 230, z = -260, yaw = 0, sx = 1, sz = 1 },
		-- Most Wanted: a real Downtown crossroads west of the plaza (no skyscraper on its four corners: roofs 70 to 180)
		station = {
			name = "Downtown crossroads",
			x = -750,
			z = 70,
			yaw = 0,
			sx = 0.64,
			sz = 0.64,
			keep = { prop = true, glow = true },
			-- the runaway tram starts on the cross street (pocket studs x, z), so it runs down a real street
			at = { trainStart = { -170, 0 } },
		},
		-- Live: Crane's broadcast on the Hero Hall plaza round the Beacon Tower
		arena = {
			name = "Hero Hall plaza",
			x = -400,
			z = 0,
			yaw = 0,
			sx = 0.5,
			sz = 0.5,
			keep = { building = true, prop = true, glow = true },
		},
	},
}
