-- MapArt: the map screen's pictures (the map pass, 2026-11-19; Ui.MapScreen, Shared.MapPlan). Drawn by
-- art/map/draw.py from the game's own layout (lune run art/map/layout.luau), uploaded from the cloud as Image
-- assets (2026-11-19, ids also in art/map/ids.json). An id of 0 draws today's fallback for that layer instead
-- (flat district squares, flat zone colours). Redraw and re-upload the city pictures whenever the hub or Uptown
-- layout changes (tests compare the box count).
return {
	-- the fixed city: the hub with the districts past it, and Uptown (Shared.MapPlan.cityImages places them)
	city = {
		Hub = 124150889575330,
		Uptown = 75883410701715,
	},
	-- one outskirts tile (100 studs) each, tiled over the merged zone rectangles (MapPlan.zones)
	patterns = {
		suburbs = 131591051834635,
		farmland = 85852496990273,
		coast = 95349707091242,
		landmark = 125662367565066,
	},
	-- the layout the pictures were drawn from (art/map/layout.luau's box count), so a test notices a stale picture
	boxes = 4190,
	margin = 240, -- studs of sea drawn round the map's edge
	maxZoom = 4, -- the map zooms in this far (pinch, wheel or the + and - buttons)
	openZoom = 2, -- the first open shows the map this far in, centred on you
	iconsFull = 640, -- icons are full size once the map is this many pixels across; smaller maps shrink them
	iconsMin = 0.5, -- to no less than this (zoom in to tap)
	namesFrom = 520, -- the small names (beacons, HQs, landmarks, the rings) show once the map is this many pixels across
}
