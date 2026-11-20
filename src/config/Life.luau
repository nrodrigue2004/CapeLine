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
	drone = { range = 320, orbit = 34, height = 28, stay = 18, speed = 60 },
	-- props the device bursts when they are knocked loose (Fx.CityLife): hydrants spray, machines spill cans,
	-- bins and news boxes scatter paper
	spill = { cans = { 6, 10 }, canLife = 7, spray = 9, sprayHeight = 34, paper = 16 },
	-- citizens near a hero (CitizenRenderer): point at one flying or racing by, hold a phone up at one standing
	-- near, cheer after a big hit they did not run from
	citizens = { point = 70, photo = 26, cheer = 60, cheerFor = 4, flashEvery = 2.2 },
	sounds = {
		honk = s("electronicpingshort.wav", 0.35, 0.42, { clip = "honk", range = 120, vary = 0.08 }),
		flutter = s("swoosh.wav", 0.4, 1.9, { clip = "flutter", range = 70, vary = 0.15 }),
		spray = s("action_falling.mp3", 0.45, 1.5, { clip = "spray", range = 90 }),
		cans = s("clickfast.wav", 0.5, 1.3, { clip = "cans", range = 70, vary = 0.2 }),
		pop = s("action_jump_land.mp3", 0.6, 1.4, { clip = "pop", range = 110 }),
		drone = s("electronicpingshort.wav", 0.12, 0.3, { clip = "drone", range = 60 }),
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
		},
	},
}
