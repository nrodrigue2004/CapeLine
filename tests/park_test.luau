-- The city park between Downtown and Uptown (park, 2026-11-20, own file): Config.Park, Shared.ParkLayout through
-- WorldMap.build, Server ParkBuilder and Fx.ParkLife's data, Art.Park (art/models/Park.rbxm). ONLY="Park" runs
-- just these. Called from tests/run.luau.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local ParkLayout = require("../src/shared/ParkLayout")
	local WorldMap = require("../src/shared/WorldMap")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local IncidentSpots = require("../src/shared/IncidentSpots")
	local Rng = require("../src/shared/Rng")
	local P = Config.Park
	local park = world.park
	local b = P.bounds

	local function inRect(r: any, x: number, z: number, pad: number?): boolean
		local p = pad or 0
		return x >= r.minX - p and x <= r.maxX + p and z >= r.minZ - p and z <= r.maxZ + p
	end
	local function wet(x: number, z: number): boolean
		local _, _, water = ParkLayout.column(park, x, z)
		return water ~= nil
	end
	local function byBridge(x: number, z: number): boolean
		for _, id in { "BowBridge", "StoneBridge" } do
			local pl = P.places[id]
			if math.abs(x - pl.x) <= 12 and math.abs(z - pl.z) <= pl.length / 2 + 8 then
				return true
			end
		end
		return false
	end

	test("Park: its rectangle sits in the gap between Downtown and Uptown, clear of both", function()
		check(park ~= nil, "WorldMap.build lays the park out")
		local c = Config.City.park
		for _, k in { "minX", "maxX", "minZ", "maxZ" } do
			check(c[k] == b[k], "Config.City.park." .. k .. " equals Config.Park.bounds")
		end
		check(b.maxX - b.minX >= 900 and b.maxZ - b.minZ >= 550, "a big park (900 x 550 at least)")
		check(type(P.name) == "string" and #P.name > 0, "a name (PLACEHOLDER NAME for nate)")
		local inside = 0
		for _, bd in world.buildings do
			local safe = false -- the North Park safehouse's shelter in its clearing
			for _, c in park.safe do
				safe = safe or (bd.x - c.x) ^ 2 + (bd.z - c.z) ^ 2 <= c.r * c.r
			end
			if inRect(b, bd.x, bd.z, -1) and not safe then
				inside += 1
			end
		end
		check(inside == 0, "no city building stands inside the park (" .. inside .. ")")
		-- Uptown is north of the park, Downtown south
		local up, down = world.uptown, world.downtown
		check(up ~= nil and down ~= nil, "both districts")
		local upMaxZ = -math.huge
		for _, bd in world.buildings do
			if bd.district == "Uptown" then
				upMaxZ = math.max(upMaxZ, bd.z + bd.sz / 2)
			end
		end
		check(upMaxZ <= b.minZ + 1, "Uptown ends north of the park (" .. upMaxZ .. ")")
		local g = park.green
		check(
			g.x0 > b.minX and g.x1 < b.maxX and g.z0 > b.minZ and g.z1 < b.maxZ,
			"the green inside the avenue"
		)
		check(
			g.x0 % 4 == 0 and g.z0 % 4 == 0 and g.x1 % 4 == 0 and g.z1 % 4 == 0,
			"the green on Terrain's grid"
		)
	end)

	test("Park: the safehouse, beacons, landmarks and street spots in it stay dry and reachable", function()
		for id, s in world.safehouses do
			if inRect(b, s.x, s.z) then
				check(not wet(s.x, s.z), "safehouse " .. tostring(id) .. " dry")
				local cleared = false
				for _, c in park.safe do
					if (c.x - s.x) ^ 2 + (c.z - s.z) ^ 2 < 4 then
						cleared = c.r >= 24
					end
				end
				check(cleared, "safehouse " .. tostring(id) .. " has its clearing")
				for _, t in park.trees do
					check(
						(t[1] - s.x) ^ 2 + (t[2] - s.z) ^ 2 > 20 * 20,
						"no tree on safehouse " .. tostring(id)
					)
				end
			end
		end
		for id, bc in world.beacons do
			if inRect(b, bc.x, bc.z) then
				check(not wet(bc.x, bc.z), "beacon " .. tostring(id) .. " dry")
			end
		end
		for _, lm in world.landmarks do
			local c = lm.centre
			if c and inRect(b, c.x, c.z) then
				check(not wet(c.x, c.z), "landmark " .. tostring(lm.id) .. " dry")
			end
		end
		for id in Config.SideQuests.sites do
			local ok, x, z = pcall(SideQuestSites.spot, Config, world, id)
			if ok and x and z and inRect(b, x, z) then
				check(not wet(x, z), "side quest site " .. id .. " not in the park's water")
			end
		end
		-- street incident spots asked for round the park never land in its water
		local rng = Rng.new(2026)
		local asked, found = 0, 0
		for _ = 1, 60 do
			local x, z = rng:range(b.minX, b.maxX), rng:range(b.minZ, b.maxZ)
			asked += 1
			local s = IncidentSpots.find(Config, world, "street", x, z, 20, 200, rng)
			if s then
				found += 1
				check(
					not (park and inRect(b, s.x, s.z) and wet(s.x, s.z)),
					"street spot dry at " .. s.x .. ", " .. s.z
				)
			end
		end
		check(found > 0, "street spots found round the park (" .. found .. " of " .. asked .. ")")
	end)

	test(
		"Park: paths stay out of the water but over the bridges; trees and spots where they belong",
		function()
			local over = 0
			for _, r in park.paths do
				for i, p in r.pts do
					if wet(p[1], p[2]) and not byBridge(p[1], p[2]) then
						over += 1
						if over <= 5 then
							check(
								false,
								r.kind .. " point " .. i .. " in the water at " .. p[1] .. ", " .. p[2]
							)
						end
					end
				end
			end
			check(over == 0, "no path point in the water off a bridge (" .. over .. ")")
			check(#park.trees >= 200, "woods: " .. #park.trees .. " trees")
			local wetTrees = 0
			for _, t in park.trees do
				if wet(t[1], t[2]) then
					wetTrees += 1
				end
				check(inRect(b, t[1], t[2]), "tree inside the park")
			end
			check(wetTrees == 0, "no tree in the water (" .. wetTrees .. ")")
			for _, kind in { "ducks", "boats", "docked" } do
				check(#park.spots[kind] > 0, kind .. " spots")
				for i, s in park.spots[kind] do
					local top, _, water = ParkLayout.column(park, s[1], s[2])
					check(water ~= nil and water - top >= 1, kind .. " " .. i .. " on water deep enough")
				end
			end
			check(#park.spots.picnics >= 10, "picnics on the lawns (" .. #park.spots.picnics .. ")")
			for i, s in park.spots.picnics do
				check(not wet(s[1], s[2]), "picnic " .. i .. " dry")
			end
			check(#park.spots.buskers >= 4, "buskers")
			for i, s in park.spots.buskers do
				check(not wet(s[1], s[2]) and s[3] ~= nil, "busker " .. i .. " dry and facing somewhere")
			end
			check(#park.spots.carts >= 2, "food carts")
			check(#park.routes >= 2, "jog and walk loops")
			local loops = 0
			for _, r in park.routes do
				if r.loop and r.length > 100 then
					loops += 1
				end
			end
			check(loops >= 2, "at least two loops long enough to jog (" .. loops .. ")")
		end
	)

	test("Park: every place and piece is a real Art.Park look, inside the green", function()
		for id, pl in P.places do
			local look = pl.look or id
			check(Config.ParkArt[look] ~= nil, id .. ": look " .. look .. " in ParkArt")
			check(park.places[id] ~= nil, id .. " placed")
		end
		local g = park.green
		local names = {}
		for _, m in park.meshes do
			local fit = Config.ParkArt[m.look]
			check(fit ~= nil and fit[m.name] ~= nil, m.name .. " is a piece of " .. tostring(m.look))
			check(P.looks[m.look] ~= nil and P.looks[m.look][m.name] ~= nil, m.name .. " has its colour row")
			check(
				m.x >= g.x0 - 2 and m.x <= g.x1 + 2 and m.z >= g.z0 - 2 and m.z <= g.z1 + 2,
				m.name .. " inside"
			)
			names[m.name] = true
		end
		for _, need in
			{ "BandShell", "CarouselRoof", "BoatRoof", "TerraceBasin", "BowDeck", "StoneArch", "RinkIce" }
		do
			check(names[need], need .. " placed")
		end
		check(#park.solid >= 30, "collision boxes under the looks (" .. #park.solid .. ")")
		for _, s in park.solid do
			check(s.sx > 0 and s.sy > 0 and s.sz > 0, "solid has a size")
		end
		local fountains, terrace = 0, false
		for _, f in park.fountains do
			fountains += 1
			terrace = terrace or f.terrace
			check(f.top > Config.City.ground.y, "a fountain's jet is above the ground")
		end
		check(fountains >= 3 and terrace, "the terrace fountain and the small ones")
		local breaks = 0
		for _, m in park.meshes do
			if m.breaks then
				breaks += 1
				check(
					m.size[2] <= 6 and math.min(m.size[1], m.size[3]) <= 3,
					"wall and rail lengths break as long props"
				)
			end
		end
		check(breaks >= 100, "the wall and the rail in breakable lengths (" .. breaks .. ")")
	end)

	test("Park: the Terrain columns are sane (Y0..Y1, water over its bed)", function()
		local g = park.green
		local rng = Rng.new(7)
		local seen = {}
		for _ = 1, 4000 do
			local x, z = rng:range(g.x0, g.x1), rng:range(g.z0, g.z1)
			local top, mat, water = ParkLayout.column(park, x, z)
			if mat == "grass" and top <= 0.01 then
				mat = ParkLayout.floor(P, x, z)
			end
			seen[mat] = true
			check(top >= -16 and top <= 20, "column top in the written layers " .. top)
			if water then
				check(water > top, "water over its bed")
				check(water <= 0, "water below the ground line")
			end
		end
		for _, m in { "grass", "leafy", "sand", "slate", "rock" } do
			check(seen[m], "the ground has " .. m)
		end
		-- the rocks to climb stand up (heights carry them, so heroes land on them)
		check(#park.rocks >= 4, "rocks to climb")
		for _, r in park.rocks do
			local h = WorldMap.heightAt(world, r.x, r.z)
			check(h >= 3, "rock at " .. r.x .. ", " .. r.z .. " in the height map (" .. h .. ")")
		end
	end)

	test("Park: the props job equals the build, budgets climb by preset", function()
		local list = ParkLayout.props(Config)
		check(#list == #park.props and #list > 100, "the same props (" .. #list .. ")")
		local names = {}
		for _, p in list do
			names[p.name] = true
			check(Config.City.kit.props[p.name] ~= nil, p.name .. " is a city kit prop")
		end
		for _, need in { "Bench", "OldLamp" } do
			check(names[need], need .. "s in the park")
		end
		local job = WorldMap.propsJob(Config, world.seed)
		local steps = 0
		repeat
			steps += 1
		until WorldMap.propsStep(job, 8) or steps > 100000
		local inPark = 0
		for _, p in (job :: any).props do
			if p.d == "Park" then
				inPark += 1
			end
		end
		check(inPark == #list, "the device's props job carries the park's (" .. inPark .. ")")
		local B = P.life.budget
		for _, k in { "radius", "joggers", "walkers", "dogs", "picnics", "buskers", "ducks", "boats", "jets" } do
			check(B.low[k] <= B.medium[k] and B.medium[k] <= B.high[k], k .. " climbs low to high")
		end
		check(B.high.dogs <= B.high.walkers and B.low.dogs <= B.low.walkers, "every dog has a walker")
		check(
			B.low.joggers + B.low.walkers + B.low.picnics * 2 + B.low.buskers <= 12,
			"phones: a dozen park people"
		)
		for _, k in { "busk", "splash", "burst", "quack" } do
			check(
				P.sounds[k] ~= nil and (P.sounds[k].asset ~= 0 or P.sounds[k].fallback ~= nil),
				k .. " sound"
			)
		end
	end)

	test("Park: Art.Park is imported, turned and mapped into the place", function()
		local MeshFix = fs.readFile("src/shared/MeshFix.luau")
		check(MeshFix:find('"Park",', 1, true) ~= nil, "MeshFix turns the Park set")
		local proj = serde.decode("json", fs.readFile("default.project.json"))
		local art = proj.tree.ReplicatedStorage.Art
		check(art and art.Park and art.Park["$path"] == "art/models/Park.rbxm", "the project maps Art.Park")
		check(fs.isFile("art/models/Park.rbxm"), "Park.rbxm")
		local ids = serde.decode("json", fs.readFile("art/models/park_meshids.json"))
		local count, missing = 0, 0
		for _, pieces in Config.ParkArt do
			for name in pieces do
				count += 1
				if not ids[name] then
					missing += 1
				end
			end
		end
		check(count >= 60 and missing == 0, count .. " pieces, " .. missing .. " without a mesh id")
		local turns = serde.decode("json", fs.readFile("art/models/meshturns.json"))
		check(turns.Park ~= nil, "meshcheck ran on Park")
	end)
end
