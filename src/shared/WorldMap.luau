--!strict
-- WorldMap: the whole city as plain data for one seed (spec: Map layout; Server lifecycle steps 2 and 3).
-- build(Config, seed) gives the hub (Downtown, the Docks, Old Town and filler tiles), Uptown (the second
-- business district, just north of the hub, built with the hub), the outskirts tile
-- plans, the landmarks, the 16 safehouses with their terminals and respawn points, the 12 fast-travel
-- beacons, the base (ground, sand, ocean, roads) and a heightmap of everything. The server builds parts
-- from it (the hub at once, the outskirts 40 tiles a frame); the tests check it in Lune. With Config.City.kit
-- it also lists every street prop (props, each with its district), which each device builds near its camera
-- (CityProps): the client runs propsJob/propsStep over a few frames, which give the same list without the rest.

local CityLayout = if script then require(script.Parent.CityLayout) else (require :: any)("./CityLayout")
local Districts = if script then require(script.Parent.Districts) else (require :: any)("./Districts")
local WorldGen = if script then require(script.Parent.WorldGen) else (require :: any)("./WorldGen")
local HeightMap = if script then require(script.Parent.HeightMap) else (require :: any)("./HeightMap")
local BoxKit = if script then require(script.Parent.BoxKit) else (require :: any)("./BoxKit")
local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local CityKit = if script then require(script.Parent.CityKit) else (require :: any)("./CityKit")

local WorldMap = {}

type Box = BoxKit.Box
type Point = { x: number, y: number, z: number }

export type Safehouse = {
	id: number,
	name: string,
	district: string,
	x: number,
	y: number, -- the pad top
	z: number,
	roofY: number,
	respawn: { Point },
	terminals: { [string]: Point },
}

export type Beacon = { id: number, name: string, x: number, y: number, z: number }

-- A wreckable hub building (spec: Destruction, 220 in the hub; then the grown Downtown blocks and Uptown)
export type Building = {
	id: number,
	grp: string,
	district: string,
	x: number,
	z: number,
	sx: number,
	sz: number,
	base: number, -- the bottom of its body
	top: number, -- the top of its body (roofs and props stand above)
	size: string, -- small, medium or tower
	hp: number,
	crown: string?, -- a skyscraper's silhouette above its body (Config.City.skyline); nothing lands on its top
	peak: number?, -- the top of that crown
	fixed: boolean?, -- a fast-travel beacon stands on its roof: it never breaks (BuildingState keeps it whole)
	more: boolean?, -- one of the 2026-11-19 additions (the rest of Old Town, the outskirts): WorldMap.moreBuildings
	round: boolean?, -- a cylinder (silo, lighthouse, windmill, the Foundry's stacks): Structure lays its pieces round
}

export type World = {
	seed: number,
	tiles: buffer,
	hash: string,
	downtown: any,
	uptown: any, -- CityLayout.uptown: its buildings, droneSpots and park (the green with the fountain)
	open: { { id: string, x: number, z: number, size: number } }, -- open squares kept for the lore thread
	hubBoxes: { Box }, -- Downtown, the Docks, Old Town, Uptown, safehouses and beacons: built at boot
	baseBoxes: { Box }, -- ground, sand, ocean and road strips: built at boot
	tilePlans: { { tx: number, tz: number, boxes: { Box } } }, -- hub filler and outskirts, built in batches
	landmarks: { WorldGen.Landmark },
	safehouses: { [number]: Safehouse },
	beacons: { [number]: Beacon },
	buildings: { Building }, -- by id
	spawns: { Point },
	spots: { [string]: Point },
	heights: HeightMap.HeightMap,
	parts: { hub: number, base: number, outskirts: number, landmarks: number, total: number },
	props: { CityKit.Prop }, -- the city kit's street props, each with its district (d)
}

local function append(into: { Box }, from: { Box })
	table.move(from, 1, #from, #into + 1, into)
end

-- A safehouse: a pad, a shelter with a roof and a sign, and the bank, loadout, respawn and contract board
-- terminals (the board from M6) and the Weapon Rack (the hero creator plan)
local function buildSafehouse(list: { Box }, w: any, s: any, x: number, z: number, gy: number): Safehouse
	local c = w.safehouse
	local pad = c.pad
	local top = gy + 1.2
	BoxKit.box(list, "plaza", x, gy + 0.6, z, pad, 1.2, pad, "safe", { tag = "safehouse", ref = s.id })
	local shelterZ = z - pad / 2 + 7
	BoxKit.box(list, "building", x, top + 6, shelterZ, 22, 12, 10, "slate")
	BoxKit.box(list, "ledge", x, top + 12.75, shelterZ + 3, 28, 1.5, 18, "safe")
	BoxKit.box(list, "glow", x, top + 10, shelterZ + 5.2, 14, 2, 0.4, "beaconGlow", { ghost = true })
	local terminals = {}
	for i, kind in { "bank", "loadout", "respawn", "contracts", "weapons" } do
		local tx = x + (i - 3) * 7
		local tz = shelterZ + 8
		BoxKit.box(list, "terminal", tx, top + 2.5, tz, 3, 5, 2, kind, { tag = kind, ref = s.id })
		terminals[kind] = { x = tx, y = top + 2.5, z = tz }
	end
	local respawn = {}
	for k = 1, c.respawnPoints do
		local a = (k - 2) * 0.9
		table.insert(
			respawn,
			{ x = x + math.sin(a) * pad * 0.35, y = top + 3, z = z + math.cos(a) * pad * 0.3 }
		)
	end
	return {
		id = s.id,
		name = s.name,
		district = s.district,
		x = x,
		y = top,
		z = z,
		roofY = top + 13.5,
		respawn = respawn,
		terminals = terminals,
	}
end

-- A fast-travel beacon: a disc, a post and a tall light beam you can see from far away
local function buildBeacon(list: { Box }, w: any, b: any, p: Point): Beacon
	local c = w.beacon
	BoxKit.box(
		list,
		"beacon",
		p.x,
		p.y + 0.4,
		p.z,
		10,
		0.8,
		10,
		"beacon",
		{ shape = "cylinder", tag = "beacon", ref = b.id }
	)
	BoxKit.box(
		list,
		"prop",
		p.x,
		p.y + 0.8 + c.height / 2,
		p.z,
		1.5,
		c.height,
		1.5,
		"steel",
		{ tag = "beaconPost", ref = b.id }
	)
	BoxKit.box(
		list,
		"glow",
		p.x,
		p.y + 0.8 + c.height + 30,
		p.z,
		3,
		60,
		3,
		"beaconLight",
		{ shape = "cylinder", ghost = true, tag = "beam", ref = b.id }
	)
	return { id = b.id, name = b.name, x = p.x, y = p.y + 1, z = p.z }
end

local function tallestNear(buildings: { any }, x: number, z: number, r: number, gy: number): (Point, string?)
	-- a skyscraper's crown (spire, setbacks, lantern) is no place for a beacon
	local best: Point = { x = x, y = gy, z = z }
	local grp: string? = nil
	for _, b in buildings do
		if b.crown == nil and (b.x - x) ^ 2 + (b.z - z) ^ 2 <= r * r and gy + b.h > best.y then
			best = { x = b.x, y = gy + b.h, z = b.z }
			grp = b.grp
		end
	end
	return best, grp
end

-- Where each safehouse stands (Downtown's reserved lots, an outskirts tile's middle or its fixed point) and the
-- keep-out circles round their pads (no lot, prop or district building goes there)
local function safehouseSpots(
	city: any,
	w: any,
	downtown: any
): ({ [number]: { x: number, z: number, gy: number } }, { BoxKit.Circle })
	local gy = city.ground.y
	local safeSpots: { [number]: { x: number, z: number, gy: number } } = {}
	for _, s in w.safehouses do
		if s.lot then
			local spot = downtown.safehouseSpots[s.id]
			safeSpots[s.id] = { x = spot.x, z = spot.z, gy = gy }
		elseif s.tile then
			local x0, z0 = WorldGen.tileOrigin(city, s.tile[1], s.tile[2])
			safeSpots[s.id] = { x = x0 + city.tile / 2, z = z0 + city.tile / 2, gy = gy }
		else
			safeSpots[s.id] = { x = s.x, z = s.z, gy = gy }
		end
	end
	local clear: { BoxKit.Circle } = {}
	for _, spot in safeSpots do
		table.insert(clear, { x = spot.x, z = spot.z, r = w.safehouse.pad * 0.75 })
	end
	return safeSpots, clear
end

-- opts.props: only what the street props need (no heightmap), for a device building them
function WorldMap.build(Config: any, seed: number, opts: { props: boolean? }?): World
	local city = Config.City
	local w = Config.World
	local gy = city.ground.y

	-- the hub: Downtown first (its reserved lots decide where its safehouses stand)
	local downtown = CityLayout.downtown(city, w)
	local safeSpots, clear = safehouseSpots(city, w, downtown)
	local docks = Districts.docks(city, clear)
	local oldTown = Districts.oldTown(city, clear)
	local uptown = CityLayout.uptown(city)

	local buildings = WorldMap.pickBuildings(Config, downtown, docks, oldTown, uptown)
	if Config.Destruction.everywhere then
		WorldMap.moreOldTown(Config, buildings, oldTown) -- 2026-11-19: every Old Town building, after Uptown
	end
	local byGrp: { [string]: number } = {}
	for _, b in buildings do
		byGrp[b.grp] = b.id
	end
	for _, list in { downtown.boxes, docks.boxes, oldTown.boxes, uptown.boxes } do
		for _, b in list do
			if b.grp then
				b.bid = byGrp[b.grp]
			end
		end
	end

	local hubBoxes: { Box } = {}
	append(hubBoxes, downtown.boxes)
	append(hubBoxes, docks.boxes)
	append(hubBoxes, oldTown.boxes)
	append(hubBoxes, uptown.boxes)

	-- the street props, by district (Config.City.kit)
	local props: { CityKit.Prop } = {}
	local function addProps(list: { CityKit.Prop }, from: number, district: string)
		for i = from, #list do
			list[i].d = district
			if list ~= props then
				table.insert(props, list[i])
			end
		end
	end
	if city.kit then
		addProps(downtown.props, 1, "Downtown")
		addProps(docks.props, 1, "Docks")
		addProps(oldTown.props, 1, "OldTown")
		addProps(uptown.props, 1, "Uptown")
	end

	-- the outskirts
	local tiles = WorldGen.tiles(city, w, seed)
	local tilePlans = {}
	local outskirtsParts = 0
	local n = w.tiles
	local tileProps: { CityKit.Prop }? = if city.kit then props else nil
	for tz = 0, n - 1 do
		for tx = 0, n - 1 do
			local from = #props + 1
			local plan = WorldGen.tilePlan(city, w, tiles, seed, tx, tz, clear, tileProps)
			if tileProps then
				addProps(props, from, if WorldGen.ring(w, tx, tz) == 0 then "Hub" else "Outskirts")
			end
			if #plan > 0 then
				table.insert(tilePlans, { tx = tx, tz = tz, boxes = plan })
				outskirtsParts += #plan
			end
		end
	end
	if Config.Destruction.everywhere then
		WorldMap.outskirtsBuildings(Config, buildings, tilePlans) -- 2026-11-19: every outskirts building body
	end
	local landmarks = {}
	local landmarkParts = 0
	for i in w.landmarks do
		local lm = WorldGen.landmark(city, w, i)
		landmarks[i] = lm
		landmarkParts += #lm.boxes
	end
	local baseBoxes = WorldGen.base(city, w, tiles, Config.Deep)

	-- safehouses and beacons
	local safehouses: { [number]: Safehouse } = {}
	for _, s in w.safehouses do
		local spot = safeSpots[s.id]
		safehouses[s.id] = buildSafehouse(hubBoxes, w, s, spot.x, spot.z, spot.gy)
	end
	local spots: { [string]: Point } = table.clone(docks.spots)
	for k, v in oldTown.spots do
		spots[k] = v
	end
	local beacons: { [number]: Beacon } = {}
	for _, b in w.beacons do
		local p: Point
		if b.at == "plaza" then
			local bt = downtown.beacon
			-- on the roof, in a corner clear of the glowing crown
			p = { x = bt.x + 17, y = gy + 1 + bt.h, z = bt.z + 17 }
		elseif b.at == "roof" then
			local grp
			p, grp = tallestNear(downtown.buildings, b.x, b.z, 60, gy)
			if grp then
				-- the beacon takes the roof: its water tower and mast make way for the pad
				for i = #hubBoxes, 1, -1 do
					local x = hubBoxes[i]
					if x.grp == grp and x.kind == "prop" and x.cy > p.y then
						table.remove(hubBoxes, i)
					end
				end
				-- (2026-11-18) the beacon's host never breaks, so its pad never floats over rubble (like the
				-- safehouses' roofs, which are no wreckable building at all)
				local host = byGrp[grp]
				if host then
					buildings[host].fixed = true
				end
			end
		elseif b.at == "crane" or b.at == "clock" then
			p = spots[b.at]
		elseif b.at == "safehouse" then
			local s = safehouses[b.safehouse]
			p = { x = s.x, y = s.roofY, z = s.z - w.safehouse.pad / 2 + 10 }
		elseif b.at == "tile" then
			local x0, z0 = WorldGen.tileOrigin(city, b.tile[1], b.tile[2])
			p = { x = x0 + city.tile / 2, y = gy + WorldGen.windmill.height + 11, z = z0 + city.tile / 2 }
		else
			p = { x = 0, y = gy, z = 0 }
			for _, lm in landmarks do
				if lm.id == b.at then
					p = lm.spot
				end
			end
		end
		beacons[b.id] = buildBeacon(hubBoxes, w, b, p)
	end

	if Config.Destruction.everywhere then
		WorldMap.moreHub(Config, buildings, hubBoxes)
		WorldMap.keepClear(Config, buildings, safehouses, beacons)
	end

	-- pt-ui (2026-11-19): every building body the layouts left plain gets a kit texture (Shared.CityKit.fill)
	if city.kit then
		CityKit.fill(city.kit, hubBoxes)
	end

	-- heights of everything (a device that only wants the props skips them)
	local heights =
		HeightMap.new(if opts and opts.props then 0 else city.mapSize, w.heightCell, w.coast.waterY)
	if not (opts and opts.props) then
		for _, b in hubBoxes do
			HeightMap.stamp(heights, b)
		end
		for _, plan in tilePlans do
			for _, b in plan.boxes do
				HeightMap.stamp(heights, b)
			end
		end
		for _, lm in landmarks do
			for _, b in lm.boxes do
				HeightMap.stamp(heights, b)
			end
		end
	end

	local hubParts = #hubBoxes
	return {
		seed = seed,
		tiles = tiles,
		hash = WorldGen.hash(tiles),
		downtown = downtown,
		uptown = uptown,
		open = downtown.open,
		hubBoxes = hubBoxes,
		baseBoxes = baseBoxes,
		tilePlans = tilePlans,
		landmarks = landmarks,
		safehouses = safehouses,
		beacons = beacons,
		buildings = buildings,
		spawns = downtown.spawns,
		spots = spots,
		heights = heights,
		parts = {
			hub = hubParts,
			base = #baseBoxes,
			outskirts = outskirtsParts,
			landmarks = landmarkParts,
			total = hubParts + #baseBoxes + outskirtsParts + landmarkParts,
		},
		props = props,
	}
end

-- The street props alone, a piece at a time (perf pass 2026-11-18): a device needs only build().props, and
-- the whole build costs about 77 ms and 25 MB at once (a phone froze for several hundred ms). A job lays out
-- each district, then the outskirts tile by tile, keeps the props and drops every box as it goes, so a device
-- can run a few steps a frame (propsStep) and hold little but the props. The list is build().props exactly:
-- the same draws in the same order (tests/perf.luau checks three seeds).
export type PropsJob = {
	Config: any,
	seed: number,
	props: { CityKit.Prop },
	stage: number, -- 1 Downtown, 2 the Docks, 3 Old Town, 4 Uptown, 5 the tile array, 6 the tiles, 7 done
	clear: { BoxKit.Circle },
	tiles: buffer?,
	next: number, -- the next tile, tz * n + tx
	done: boolean,
}

function WorldMap.propsJob(Config: any, seed: number): PropsJob
	return {
		Config = Config,
		seed = seed,
		props = {},
		stage = if Config.City.kit then 1 else 7,
		clear = {},
		tiles = nil,
		next = 0,
		done = Config.City.kit == nil,
	}
end

local function tagged(into: { CityKit.Prop }, list: { CityKit.Prop }, from: number, district: string)
	for i = from, #list do
		list[i].d = district
		if list ~= into then
			table.insert(into, list[i])
		end
	end
end

-- One piece of the job: a district, the tile array, or up to `tiles` outskirts tiles (default 1). Returns true
-- once the list is whole.
function WorldMap.propsStep(job: PropsJob, tiles: number?): boolean
	if job.done then
		return true
	end
	local Config = job.Config
	local city = Config.City
	local w = Config.World
	local stage = job.stage
	if stage == 1 then
		local downtown = CityLayout.downtown(city, w)
		local _, clear = safehouseSpots(city, w, downtown)
		job.clear = clear
		tagged(job.props, downtown.props, 1, "Downtown")
	elseif stage == 2 then
		tagged(job.props, Districts.docks(city, job.clear).props, 1, "Docks")
	elseif stage == 3 then
		tagged(job.props, Districts.oldTown(city, job.clear).props, 1, "OldTown")
	elseif stage == 4 then
		tagged(job.props, CityLayout.uptown(city).props, 1, "Uptown")
	elseif stage == 5 then
		job.tiles = WorldGen.tiles(city, w, job.seed)
	elseif stage == 6 then
		local n = w.tiles
		local Z = w.zones
		local grid = job.tiles :: buffer
		local props = job.props
		local left = tiles or 1
		while left > 0 and job.next < n * n do
			local tx, tz = job.next % n, job.next // n
			job.next += 1
			-- tilePlan's own early outs: these tiles have no props, so their boxes are never laid out
			local t = WorldGen.get(w, grid, tx, tz)
			local none = t.zone == Z.hub
				or t.zone == Z.landmark
				or t.zone == Z.coast
				or (t.zone ~= Z.hubFill and t.variant == w.special)
			if not none then
				local from = #props + 1
				WorldGen.tilePlan(city, w, grid, job.seed, tx, tz, job.clear, props)
				tagged(props, props, from, if WorldGen.ring(w, tx, tz) == 0 then "Hub" else "Outskirts")
				left -= 1
			end
		end
		if job.next < n * n then
			return false
		end
		job.tiles = nil
	end
	job.stage = stage + 1
	job.done = job.stage >= 7
	return job.done
end

-- Every street prop for a seed at once (Lune, tests): build(Config, seed).props without the rest of the world
function WorldMap.props(Config: any, seed: number): { CityKit.Prop }
	local job = WorldMap.propsJob(Config, seed)
	local done = false
	repeat
		done = WorldMap.propsStep(job, 1e9)
	until done
	return job.props
end

-- One wreckable building record, id next in the list (pickBuildings and moreBuildings)
local function addRecord(
	D: any,
	list: { Building },
	b: any,
	district: string,
	base: number,
	top: number
): Building
	local h = top - base
	local size = if h <= D.smallMax then "small" elseif h <= D.mediumMax then "medium" else "tower"
	local rec: Building = {
		id = #list + 1,
		grp = b.grp,
		district = district,
		x = b.x,
		z = b.z,
		sx = b.sx,
		sz = b.sz,
		base = base,
		top = top,
		size = size,
		hp = D.hp[size],
		crown = b.crown,
		peak = b.peak,
	}
	table.insert(list, rec)
	return rec
end

-- Old Town in the fixed hash order pickBuildings uses
local function oldTownOrder(Config: any, oldTown: any): { any }
	local old = table.clone(oldTown.buildings)
	local seed = Config.City.oldTown.seed
	table.sort(old, function(a, b)
		return Rng.hash(seed, math.floor(a.x), math.floor(a.z))
			< Rng.hash(seed, math.floor(b.x), math.floor(b.z))
	end)
	return old
end

-- More destruction everywhere (nate's playtest 2026-11-19: "only skyscrapers are destructible"). The first 220
-- (pickBuildings) stopped partway through Old Town, so half its houses never took a hit; the rest come now,
-- after Uptown, in the same hash order (so every id before them is unchanged).
function WorldMap.moreOldTown(Config: any, list: { Building }, oldTown: any)
	local D = Config.Destruction
	local have: { [string]: boolean } = {}
	for _, b in list do
		have[b.grp] = true
	end
	for _, b in oldTownOrder(Config, oldTown) do
		if b.grp and not have[b.grp] then
			addRecord(D, list, b, "OldTown", b.base, b.base + b.h).more = true
		end
	end
end

-- Box kinds that belong to the outskirts building they stand on or against (its roof, window bands, ledges,
-- door and awning): they hide with it when it breaks. Trees, fences and silos stay street things.
local function dressing(b: any): boolean
	return b.kind == "roof"
		or b.kind == "band"
		or b.kind == "ledge"
		or b.kind == "glow"
		or (b.kind == "prop" and (b.ghost == true or b.sy <= 1))
end

local function snap(v: number): number
	return math.floor(v * 4 + 0.5) / 4 -- a quarter stud, exact as a 32-bit float (BuildingService sends them so)
end

-- Every outskirts building body (houses, big houses, shops, barns, farm sheds, coast sheds) is wreckable too
-- (2026-11-19; before, the outskirts only cracked). One record per plain box body, ids after the hub's, in tile
-- order; the body and its dressing get the record's id (bid) so CityBuilder puts them in its own model.
-- Since fix-destroy (2026-11-19, nate: "Why cant i destroy silos? I literally want everything destructible") the
-- cylinders are wreckable too (WorldMap.roundBody: silos, lighthouses, the windmill), laid round by Structure.
function WorldMap.roundBody(b: any): boolean
	return b.shape == "cylinder"
		and not b.ghost
		and b.sx >= 8
		and b.sy >= 12
		and (b.kind == "building" or (b.kind == "prop" and (b.color == "steel" or b.sy >= 40)))
end

-- The hub's last whole bodies (fix-destroy, 2026-11-19): the Foundry and its three stacks, the clock tower, the 16
-- safehouse shelters. Ids after every other record (so none before them moves); only the body gets the id, so a
-- shelter's roof ledge, terminals and pad, and the Foundry's signs, stay put while the walls take holes. The
-- Foundry (the Syndicate's way in) and anything by a pad or beacon are shells (keepClear marks them fixed).
function WorldMap.moreHub(Config: any, list: { Building }, hubBoxes: { any })
	local D = Config.Destruction
	local n = 0
	for _, b in hubBoxes do
		local round = WorldMap.roundBody(b)
		if
			not b.bid
			and not b.ghost
			and (round or (b.kind == "building" and b.shape == nil and (b.ry or 0) % 90 == 0 and b.sy >= 4))
		then
			n += 1
			local fx, fz = BoxKit.footprint(b)
			local rec = addRecord(D, list, {
				grp = "H" .. n,
				x = b.cx,
				z = b.cz,
				sx = if round then b.sx else fx,
				sz = if round then b.sx else fz,
			}, "Hub", b.cy - b.sy / 2, b.cy + b.sy / 2)
			rec.more = true
			rec.round = if round then true else nil
			if b.color == "foundry" and not round then
				rec.fixed = true
			end
			b.bid = rec.id
		end
	end
end

function WorldMap.outskirtsBuildings(Config: any, list: { Building }, tilePlans: { any })
	local D = Config.Destruction
	for _, plan in tilePlans do
		local bodies: { Building } = {}
		for _, b in plan.boxes do
			local round = WorldMap.roundBody(b)
			if
				round
				or (
					b.kind == "building"
					and b.shape == nil
					and not b.ghost
					and (b.ry or 0) % 90 == 0
					and b.sy >= 4
				)
			then
				local fx, fz = BoxKit.footprint(b)
				local rec = addRecord(D, list, {
					grp = string.format("T%d_%d_%d", plan.tx, plan.tz, #bodies + 1),
					x = snap(b.cx),
					z = snap(b.cz),
					sx = snap(fx),
					sz = snap(fz),
				}, "Outskirts", snap(b.cy - b.sy / 2), snap(b.cy + b.sy / 2))
				rec.more = true
				if round then
					rec.round = true
				end
				b.bid = rec.id
				table.insert(bodies, rec)
			end
		end
		if #bodies > 0 then
			for _, b in plan.boxes do
				if not b.bid and (dressing(b) or (b.kind == "prop" and not WorldMap.roundBody(b))) then
					for _, r in bodies do
						local near = math.abs(b.cx - r.x) <= r.sx / 2 + 2.5
							and math.abs(b.cz - r.z) <= r.sz / 2 + 2.5
						local dressed = dressing(b)
						if not dressed and r.round then
							-- a round body's cap, its windmill blades: up its top half, close round it
							dressed = math.abs(b.cx - r.x) <= r.sx / 2 + 4
								and math.abs(b.cz - r.z) <= r.sz / 2 + 4
								and b.cy >= r.base + (r.top - r.base) * 0.5
							near = dressed
						end
						if near and dressed and b.cy >= r.base then
							b.bid = r.id
							break
						end
					end
				end
			end
		end
	end
end

-- The added buildings never break near a safehouse or under a beacon (nobody wrecks a safehouse's street or
-- the pad a hero fast-travels to): they are marked fixed, like a beacon's host
function WorldMap.keepClear(
	Config: any,
	list: { Building },
	safehouses: { [number]: any },
	beacons: { [number]: any }
)
	local D = Config.Destruction
	local pad = Config.World.safehouse.pad * 0.75 + D.keepClear
	for _, b in list do
		if b.more then
			local function dist(x: number, z: number): number
				local dx = math.max(math.abs(x - b.x) - b.sx / 2, 0)
				local dz = math.max(math.abs(z - b.z) - b.sz / 2, 0)
				return math.sqrt(dx * dx + dz * dz)
			end
			for _, s in safehouses do
				if dist(s.x, s.z) <= pad then
					b.fixed = true
				end
			end
			for _, k in beacons do
				if dist(k.x, k.z) <= D.keepClear then
					b.fixed = true
				end
			end
		end
	end
end

-- The wreckable buildings: all of the first Downtown, the Docks warehouses, then Old Town houses picked by a
-- fixed hash until Config.Destruction.hubBuildings is reached; then every building of the grown Downtown
-- blocks and of Uptown (2026-11-17), so the first 220 keep their ids. Ids are 1..n in that order, the same
-- every week.
function WorldMap.pickBuildings(
	Config: any,
	downtown: any,
	docks: any,
	oldTown: any,
	uptown: any?
): { Building }
	local D = Config.Destruction
	local list: { Building } = {}
	local function add(b: any, district: string, base: number, top: number)
		addRecord(D, list, b, district, base, top)
	end
	local gy = Config.City.ground.y
	for _, b in downtown.buildings do
		if b.grp and not b.grown then
			add(b, "Downtown", b.base or gy, gy + b.h)
		end
	end
	for _, b in docks.buildings do
		add(b, "Docks", b.base, b.base + b.h)
	end
	for _, b in oldTownOrder(Config, oldTown) do
		if #list >= D.hubBuildings then
			break
		end
		add(b, "OldTown", b.base, b.base + b.h)
	end
	for _, b in downtown.buildings do
		if b.grp and b.grown then
			add(b, "Downtown", b.base or gy, gy + b.h)
		end
	end
	if uptown then
		for _, b in uptown.buildings do
			add(b, "Uptown", b.base, gy + b.h)
		end
	end
	return list
end

function WorldMap.heightAt(world: World, x: number, z: number): number
	return HeightMap.at(world.heights, x, z)
end

-- The nearest safehouse to a point, from a set of allowed ids (nil = all)
function WorldMap.nearestSafehouse(
	world: World,
	x: number,
	z: number,
	allowed: { [number]: boolean }?
): Safehouse?
	local best, bestD = nil, math.huge
	for id, s in world.safehouses do
		if allowed == nil or allowed[id] then
			local d = (s.x - x) ^ 2 + (s.z - z) ^ 2
			if d < bestD then
				best, bestD = s, d
			end
		end
	end
	return best
end

return WorldMap
