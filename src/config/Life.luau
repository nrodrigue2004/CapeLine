-- Life: the living world (2026-11-19, nate's playtest: "you still use way too many simple shapes and textures ...
-- World needs to feel way more alive"; Shared.LifeKit, Shared.LifePlan, Fx.CityLife). Pure data.
-- * looks: the Art.Life meshes (art/blender/life.py) the server builds over the city's own boxes (cover looks: trees,
--   crops, corn, hay, doors, silos) and their colours and materials; a box keeps its record, collisions and
--   breaking, only its look changes. Picks (canopy shape, leaf colour, door paint) are hashes of the spot.
-- * picket: the outskirts' fence boxes wear the uploaded picket picture on both long faces (the box is hidden).
-- * shop fronts under the awnings (Shared.CityPlay) with lettered signs from a fixed list (never player text, no
--   real brands); vending machines on Downtown and Uptown sidewalks.
-- * the device's ambient life (Fx.CityLife): traffic on the lanes, pigeons, steam, roof flags, news drones, shop
--   lights at night, hydrant and vending reactions, citizens who point, take photos and cheer. Budgets per preset.

local B = "rbxasset://sounds/"
local function s(fallback: string?, volume: number, pitch: number?, extra: { [string]: any }?)
	local t =
		{ asset = 0, fallback = if fallback then B .. fallback else nil, volume = volume, pitch = pitch or 1 }
	for k, v in extra or {} do
		t[k] = v
	end
	return t
end

return {
	set = "Life", -- ReplicatedStorage.Art.Life (art/models/Life.rbxm; MeshFix.turn("Life"))
	seed = 20261119, -- the hash seed for the picks (CityKit.roll with this kit seed)
	-- each cover piece: colour (or a list picked by hash), material, transparency; `collide` false keeps a
	-- piece out of collisions and queries even when its box collides
	looks = {
		TreeTrunk = { TreeTrunk = { color = { 104, 74, 52 }, mat = "Wood" } },
		CanopyRound = { CanopyRound = { leaf = true, mat = "Grass" } },
		CanopyTall = { CanopyTall = { leaf = true, mat = "Grass" } },
		CanopyPine = {
			CanopyPine = { color = { { 46, 104, 64 }, { 40, 92, 60 }, { 56, 112, 70 } }, mat = "Grass" },
		},
		CropRow = {
			CropRow = { color = { { 110, 178, 70 }, { 96, 166, 64 }, { 132, 186, 80 } }, mat = "Grass" },
		},
		CornRow = {
			CornRow = { color = { 150, 170, 70 }, mat = "Grass" },
			CornCobs = { color = { 240, 200, 70 }, mat = "SmoothPlastic" },
		},
		HayBale = { HayBale = { color = { 222, 184, 92 }, mat = "Fabric" } },
		HouseDoor = {
			DoorPanel = {
				color = {
					{ 150, 60, 50 },
					{ 60, 90, 140 },
					{ 70, 120, 80 },
					{ 244, 242, 236 },
					{ 230, 180, 60 },
				},
				mat = "SmoothPlastic",
			},
			DoorKnob = { color = { 212, 175, 80 }, mat = "Metal", collide = false },
		},
		SiloBody = { SiloBody = { color = { 196, 200, 204 }, mat = "Metal" } },
		SiloDome = { SiloDome = { color = { 206, 210, 214 }, mat = "Metal" } },
	},
	-- round 2 (shapes-2, 2026-11-19, nate: "you still use way too many simple shapes"): Art.Shapes looks
	-- (art/blender/shapes.py, Config.ShapeArt) over the boxes the first pass left plain. Prop looks take the box's
	-- place (collide like it, break like it: StreetBreak); `ring` looks (roof mouldings) run along the four edges of
	-- a box that stays (visual only). Shared.LifeKit places them; CityBuilder builds them.
	shapes = {
		set = "Shapes", -- ReplicatedStorage.Art.Shapes (art/models/Shapes.rbxm; MeshFix.turn("Shapes"))
		rocks = { "RockA", "RockB", "RockC" }, -- a `Rock` box's shape, by hash
		turns = { Rock = true, RockBase = true, UmbrellaTop = true }, -- turned every way by hash
		-- pieces that never collide even on a solid box (thin details)
		soft = {
			HoopNet = true,
			TowelStripe = true,
			CorniceDentils = true,
			LanternLamp = true,
			UmbrellaTrim = true,
			RoofEdgeBand = true,
			PondReeds = true,
			PondPads = true,
			PoolLadder = true,
		},
		keep = { PondRim = true }, -- prop looks that dress a box which stays (the pond's water)
		-- the water's surface (nate: "pools need to look better as well"): a ripple picture tiled on every pool,
		-- pond and fountain's top (art/shapes/decals.py, uploaded), drifting on the devices near it (Fx.WaterSurface)
		water = { image = 74012329694187, studs = 10, drift = 0.6, radius = 260, transparency = 0.2 },
		ring = { out = 0.5 }, -- a run's face sits this far in from its depth past the box's edge
		roofKit = "Concrete", -- a flat roof's cap under its moulding wears this kit texture
		-- road pictures (art/shapes/decals.py, uploaded): CityLayout's crossing, drain and lane dash strips (each strip
		-- hidden under its picture); 0 = not built
		decals = { Zebra = 72425385136303, Drain = 116604205472367, Dash = 79628484169672 },
	},
	-- round 3 (alive-world, 2026-11-20, nate: "too many simple shapes and untextured parts ... the world must feel
	-- alive"): Art.Alive looks (art/blender/alive.py, Config.AliveArt) over the plain boxes a player sees most: the
	-- safehouses' terminals, canopy and pad, the Docks' gantry cranes, the Foundry's chimneys and Uptown's roof
	-- gardens. Visual only: every box stays (collisions, queries, the terminals' prompts); the ones in `hide` are
	-- hidden under their meshes. Until every mesh of a look is imported the box shows as before.
	alive = {
		set = "Alive", -- ReplicatedStorage.Art.Alive (art/models/Alive.rbxm; MeshFix.turn("Alive"))
		hide = {
			TermBank = true,
			TermLoadout = true,
			TermRespawn = true,
			TermContracts = true,
			TermWeapons = true,
			SafeCanopy = true,
			CraneLeg = true,
			CraneBeam = true,
			CraneBoom = true,
			FoundryChimney = true,
		},
		-- the safehouse terminals' looks by their kind (WorldMap.buildSafehouse)
		terminals = {
			bank = "TermBank",
			loadout = "TermLoadout",
			respawn = "TermRespawn",
			contracts = "TermContracts",
			weapons = "TermWeapons",
		},
		padKit = "Terrazzo", -- the safehouse pad's kit texture (under its painted ring)
		-- boxes the devices bring to life (CollectionService tags on the box, Fx.CityLife)
		tags = { FoundryChimney = "LifeSmoke", CraneBeam = "LifeGulls", CraneBoom = "LifeCrane" },
	},
	-- lit windows after dusk (shapes-2; Fx.LitWindows, Shared.LitPlan): each kit front's lit picture
	-- (art/city/litwindows.py, uploaded) over the building faces near the camera in an unlit SurfaceGui; images 0
	-- are not drawn. Budgets per preset: how far and how many faces.
	lit = {
		images = {
			Brick = 137063544064516,
			Curtain = 139610505527078,
			Deco = 123684102732819,
			DockBrick = 112466381364654,
			Office = 100055992717480,
			OldBrick = 98558163175432,
			Panel = 115802676369115,
			Plaster = 100336179747947,
			Ribbon = 90387260414752,
			Siding = 123205851847368,
			Stone = 136381403359715,
			Timber = 136566113405920,
			Warehouse = 126791743241004,
		},
		block = 48, -- studs a picture covers (4 x 4 storey bays)
		pps = 6, -- canvas pixels a stud
		brightness = 1.8,
		from = 18.2, -- clock hours: on after dusk ...
		to = 6.1, -- ... off at dawn
		minFace = 10, -- faces narrower than this stay dark
		every = 0.75, -- seconds between passes
		budget = {
			low = { radius = 260, faces = 16 },
			medium = { radius = 420, faces = 48 },
			high = { radius = 700, faces = 120 },
		},
	},
	-- leaf colours by hash: mostly greens, a few autumn and blossom trees for variety (outskirts and parks)
	leaves = {
		{ 88, 150, 64 },
		{ 70, 135, 60 },
		{ 110, 165, 70 },
		{ 96, 156, 80 },
		{ 78, 142, 58 },
		{ 122, 170, 66 },
		{ 214, 122, 48 }, -- autumn
		{ 236, 162, 186 }, -- blossom
	},
	-- which crown a tree gets (BoxKit.tree's ball): weights by hash; parks and gardens keep broadleaves
	canopies = { { "CanopyRound", 0.5 }, { "CanopyTall", 0.22 }, { "CanopyPine", 0.28 } },
	parkCanopies = { { "CanopyRound", 0.65 }, { "CanopyTall", 0.35 } },
	-- the picket fence picture (art/life/textures.py, uploaded 2026-11-19): 3 studs a tile across and the fence's
	-- height up; the box is hidden so the gaps show through
	picket = { image = 103894563320884, studs = 3 },
	-- the farm fields' tilled soil (MaterialVariant KitTilled)
	tilled = { image = 121312959727803 },
	-- flags by district (uploaded 2026-11-19): roof flags take their building's district's, the plaza the city's
	flags = {
		Brightharbor = 138295993727973,
		Uptown = 126600702302066,
		Docks = 92177187521566,
		OldTown = 125531741736673,
	},
	-- shop fronts: their words, paints and chances are Config.City.kit.play.shop (CityPlay reads the kit); this is
	-- the warm glow their backs take from dusk to dawn (Fx.CityLife)
	shopNight = { 255, 204, 140 },

	-- the device's ambient life (Fx.CityLife), by preset; radius: how far from the camera it lives
	budget = {
		low = {
			cars = 4,
			carRadius = 200,
			wheels = false,
			flocks = 2,
			steam = 3,
			flags = 3,
			flagSegs = 4,
			drones = 0,
			-- alive-world (2026-11-20): harbour gull colonies and gulls in each, Foundry chimneys smoking and their
			-- smoke's rate, hazard lights on cars scared off by a fight
			gullColonies = 1,
			gulls = 4,
			smoke = 1,
			smokeRate = 3,
			hazards = false,
			banners = 2, -- Uptown's tower banners hung near the camera, and the segments in each
			bannerSegs = 3,
			cranes = 1, -- Docks cranes whose trolleys run near the camera
		},
		medium = {
			cars = 8,
			carRadius = 280,
			wheels = true,
			flocks = 4,
			steam = 6,
			flags = 6,
			flagSegs = 6,
			drones = 1,
			-- alive-world (2026-11-20): harbour gull colonies and gulls in each, Foundry chimneys smoking and their
			-- smoke's rate, hazard lights on cars scared off by a fight
			gullColonies = 2,
			gulls = 6,
			smoke = 3,
			smokeRate = 6,
			hazards = true,
			banners = 6, -- Uptown's tower banners hung near the camera, and the segments in each
			bannerSegs = 5,
			cranes = 3, -- Docks cranes whose trolleys run near the camera
		},
		high = {
			cars = 14,
			carRadius = 380,
			wheels = true,
			flocks = 7,
			steam = 10,
			flags = 10,
			flagSegs = 8,
			drones = 2,
			-- alive-world (2026-11-20): harbour gull colonies and gulls in each, Foundry chimneys smoking and their
			-- smoke's rate, hazard lights on cars scared off by a fight
			gullColonies = 3,
			gulls = 9,
			smoke = 3,
			smokeRate = 10,
			hazards = true,
			banners = 12, -- Uptown's tower banners hung near the camera, and the segments in each
			bannerSegs = 7,
			cranes = 3, -- Docks cranes whose trolleys run near the camera
		},
	},
	-- traffic on the lane lines (Shared.LifePlan.lanes: Downtown's and Uptown's dashes; the tram lines are left
	-- out): right-hand lanes, lights at every crossing, brakes for the car ahead and for heroes in the road
	traffic = {
		looks = { "CarSedan", "CarHatch", "CarTaxi", "CarSedan", "CarHatch", "CarBubble" },
		paints = { "containerA", "containerB", "containerC", "containerD", "white", "roofBlue" },
		lane = 3.6, -- studs from the dashes to a lane's middle
		cruise = 30, -- studs a second
		accel = 14,
		brake = 40,
		gap = 13, -- keep this far behind the car ahead
		cycle = 14, -- a light's cycle (seconds): half green along x, half along z
		stopShort = 19, -- stop this far before a crossing on red (the crosswalk)
		heroStop = 16, -- stop for a hero standing this far ahead in the lane
		spawnMin = 90, -- spawn at least this far from the camera
		knock = { radius = 1.6, up = 46, out = 60, spin = 5, life = 7 }, -- a big impact flings cars in radius x this
		honk = 0.3, -- chance a braking car honks
		-- alive-world (2026-11-20, nate: "traffic reacting to fights"): a robot or a big hit within `radius` of a car
		-- (or of the road `ahead` of it) scares it: it brakes, flashes its hazards and honks, waits `wait` s, U-turns
		-- (`turn` s round a loop `stretch` times the lane gap long) and races off at `flee` x cruise for `fleeFor` s.
		-- Dangers are checked every `every` s; a big hit counts for `bangFor` s.
		fear = {
			radius = 55,
			ahead = 35,
			wait = 0.7,
			turn = 1.8,
			stretch = 2.6,
			flee = 1.45,
			fleeFor = 8,
			bangFor = 6,
			every = 0.4,
			honk = 0.6,
			blink = 0.35,
			hazard = { 255, 170, 40 },
		},
	},
	-- harbour gulls (alive-world): a colony circles over each Docks crane near the camera (tag LifeGulls) and wheels
	-- out and up from a hero who flies through it or a big hit, then drifts back
	-- the Docks' gantry cranes at work (alive-world round 2, 2026-11-20; Fx.CityLife, Shared.LifePlan.crane): on each
	-- device near the camera the trolley and its hook run out along the boom and back (boom-local z from its middle,
	-- a..b), easing in and out, waiting `pause` seconds at each end, and the hook swings on its cable at each start
	-- and stop (a damped pendulum: `swing` radians a kick, `freq` rad/s, `damp` a second). Visual only: the boxes
	-- that collide never move (Decisions 2026-11-20: the server-owned moving prop stays NEEDS NATE)
	cranes = {
		range = 700,
		a = -24,
		b = 30,
		speed = 7,
		pause = { 3, 6 },
		swing = 0.07,
		freq = 2.6,
		damp = 0.7,
		pivot = 2, -- the trolley's wheels this far under the boom's middle
		find = { 2, 3 }, -- a trolley or cable piece within this x and z of the boom's look offset (8)
		at = 8,
	},
	gulls = {
		range = 600, -- colonies within this of the camera
		above = 16, -- the colony's middle this high over the crane's beam
		out = 18, -- and this far out over the water (+z)
		radius = { 12, 30 },
		height = { -4, 14 },
		speed = { 14, 22 },
		scale = 1.7, -- a gull is a pigeon mesh this much bigger
		scare = 30,
		cry = { 7, 16 }, -- seconds between a colony's cries (a random pick each time)
		bang = 160,
		calm = 7, -- seconds before a scared colony drifts back
		body = { 240, 240, 236 },
		wing = { 170, 178, 190 },
	},
	-- the Foundry's chimney smoke (alive-world): dark plumes from the stacks near the camera (tag LifeSmoke), a black
	-- burst when a big hit lands near one
	smoke = {
		range = 900,
		color = { 70, 64, 62 },
		size = { 8, 34 },
		life = { 7, 10 },
		speed = { 9, 15 },
		puff = 30,
	},
	-- pigeons on the sidewalk corners near the camera: peck, hop, and burst up and away from a hero or a bang
	pigeons = {
		chance = 0.35, -- a corner gets a flock by hash
		count = { 3, 6 },
		salt = 43,
		scare = 15, -- a hero this close (or moving fast this close x 2) scatters them
		fast = 30, -- studs a second that counts as fast
		bang = 70, -- an impact this close scatters them
		fly = { up = 26, out = 22, time = 3.2, flap = 18 },
		back = 25, -- seconds before a scattered flock lands again (out of the hero's way)
	},
	steam = {
		chance = 0.3, -- a lane segment between crossings gets a manhole by hash
		salt = 44,
		pop = 26, -- an impact this close blows the cover off
		back = 12, -- seconds the cover stays off
	},
	flagRoofs = { chance = 0.14, salt = 45, maxHeight = 260, size = { 6, 4 }, wind = 1.6 },
	-- alive-world round 2 (2026-11-20): flags on both front corners of every safehouse pad (Life.flags by district),
	-- and tall cloth banners hung in pairs down one face of Uptown's tall towers (Banner_Uptown.png from
	-- art/life/textures.py, 10 x 35 studs, a rod at the top; Shared.LifePlan.towerBanners, Fx.CityLife). They billow
	-- out from the wall (LifePlan.billow) and go with their tower when it breaks
	banners = {
		safeInset = 2.5, -- studs in from the pad's front corners
		districts = { Uptown = true },
		minHeight = 200, -- a tower's shaft at least this tall
		minWidth = 40,
		chance = 0.55,
		salt = 46,
		spread = 0.32, -- the pair stands this share of the face's half width either side of its middle
		out = 1.8, -- studs out from the wall, clear of the kit's fronts
		drop = 10, -- the rod this far under the shaft's top (below the cornice)
		size = { 10, 35 },
		wind = 1.1,
		range = 600, -- studs from the camera a banner may hang
		images = { Uptown = 101273146356518 },
		rod = { 230, 190, 70 },
	},
	drone = { range = 320, orbit = 34, height = 28, stay = 18, speed = 60 },
	-- props the device bursts when they are knocked loose (Fx.CityLife): hydrants spray, machines spill cans,
	-- bins and news boxes scatter paper
	spill = { cans = { 6, 10 }, canLife = 7, spray = 9, sprayHeight = 34, paper = 16 },
	-- citizens near a hero (CitizenRenderer): point at one flying or racing by, hold a phone up at one standing
	-- near, cheer after a big hit they did not run from
	-- chat (list-combat 2026-11-20, Everything Left 275): two citizens stopped this close turn to face each other
	-- and talk (their idle gestures play as the chat)
	-- bagColors: the shopping bags citizens carry out of the shops (Everything Left 275, CitizenRenderer)
	-- seat: a bench sitter's seat top above its feet (Art.Street Bench's slats); sitDrop: the share of its standing
	-- root height left when its hips bend to sit (ParkLife's picnic sit)
	citizens = {
		point = 70,
		photo = 26,
		cheer = 60,
		cheerFor = 4,
		flashEvery = 2.2,
		chat = 6,
		seat = 1.55,
		sitDrop = 0.52,
		bagColors = {
			{ 214, 170, 120 },
			{ 236, 84, 120 },
			{ 70, 150, 230 },
			{ 250, 210, 70 },
			{ 120, 200, 120 },
			{ 245, 245, 240 },
		},
	},
	sounds = {
		honk = s("electronicpingshort.wav", 0.35, 0.42, { clip = "honk", range = 120, vary = 0.08 }),
		flutter = s("swoosh.wav", 0.4, 1.9, { clip = "flutter", range = 70, vary = 0.15 }),
		spray = s("action_falling.mp3", 0.45, 1.5, { clip = "spray", range = 90 }),
		cans = s("clickfast.wav", 0.5, 1.3, { clip = "cans", range = 70, vary = 0.2 }),
		pop = s("action_jump_land.mp3", 0.6, 1.4, { clip = "pop", range = 110 }),
		drone = s("electronicpingshort.wav", 0.12, 0.3, { clip = "drone", range = 60 }),
		-- alive-world (2026-11-20, the Ambient atlas): a harbour gull's cries from a colony now and then and when it
		-- scatters (every `gullEvery` seconds by colony, Config.Life.gulls), a crane's winch as its trolley sets off
		gull = s(nil, 0.5, 1, { clip = "gull", range = 220, vary = 0.08 }),
		winch = s(nil, 0.55, 1, { clip = "winch", range = 260, vary = 0.04 }),
		-- the city bed (AudioController.beds; the sounds pass, 2026-11-19): the traffic hum with far sirens and horns,
		-- the Docks' water, bell, foghorn and gulls, the Outskirts' open air, and the wind on the rooftops (mixed in
		-- by camera height, Config.Audio.bed). Our own mixes (art/audio/build.py) from CC0 loops and synth.
		bed = {
			Downtown = { asset = 0, volume = 0.3, clip = "bedDowntown" },
			Uptown = { asset = 0, volume = 0.26, clip = "bedDowntown" },
			OldTown = { asset = 0, volume = 0.18, clip = "bedDowntown" },
			Docks = { asset = 0, volume = 0.32, clip = "bedDocks" },
			Outskirts = { asset = 0, volume = 0.26, clip = "bedOutskirts" },
			Rooftop = { asset = 0, volume = 0.35, clip = "bedRooftop" },
			-- the park's birdsong, breeze and far city (alive-world 2026-11-20; inside Config.Park.bounds)
			Park = { asset = 0, volume = 0.34, clip = "bedPark" },
		},
	},
}
