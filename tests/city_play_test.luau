-- pt-city (nate's playtest 2026-11-19: "Downtown and Uptown should be larger", skyscraper fights are the fun, and
-- "a more interactive map, more detailed, higher quality, more textures, fewer simple shapes"): Downtown 980 x 1,120
-- and Uptown 750 x 750 (both about 1.56x), the older blocks unchanged, every site, beacon and safehouse where it
-- belongs, and the street and roof pieces heroes use or break (Shared.CityPlay: awnings that bounce, water towers,
-- antennas, roof units, billboards, perches; news boxes and food carts).
-- Called from tests/run.luau: require("./city_play_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="City play" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local WorldMap = require("../src/shared/WorldMap")
	local CityLayout = require("../src/shared/CityLayout")
	local CityPlay = require("../src/shared/CityPlay")
	local CityKit = require("../src/shared/CityKit")
	local SideQuestSites = require("../src/shared/SideQuestSites")
	local CitizenSim = require("../src/shared/CitizenSim")
	local MapPlan = require("../src/shared/MapPlan")
	local WorldGen = require("../src/shared/WorldGen")

	local C = Config.City
	local W = Config.World
	local K = C.kit
	local P = K.play
	local gy = C.ground.y
	local world = T.world or WorldMap.build(Config, 202647)

	-- the city as it was before 2026-11-19: Downtown 840 x 840 (its first ring) and Uptown 600 x 600
	local function before(): any
		local c = table.clone(C)
		c.districts = table.clone(C.districts)
		c.downtown = table.clone(C.downtown)
		local t = c.downtown
		local pitch = t.block + t.street
		local g = t.grow1
		t.grow = g
		c.districts.Downtown = {
			minX = t.core.minX - g.west * pitch,
			maxX = t.core.maxX + g.east * pitch,
			minZ = t.core.minZ - g.north * pitch,
			maxZ = t.core.maxZ + g.south * pitch,
		}
		c.uptown = table.clone(C.uptown)
		c.uptown.grow = nil
		-- (the park, 2026-11-20: the whole of Uptown moved 300 studs north to make room for the park, so its old
		-- square moved with it; everything inside is laid out from the district's corner)
		c.districts.Uptown = { minX = -700, maxX = -100, minZ = -1700, maxZ = -1100 }
		local cfg = table.clone(Config)
		cfg.City = c
		return cfg
	end
	local old = before()

	local function inside(r: any, x: number, z: number, pad: number): boolean
		return x > r.minX - pad and x < r.maxX + pad and z > r.minZ - pad and z < r.maxZ + pad
	end

	test(
		"City play: Downtown and Uptown about 1.5x bigger, the older blocks and their ids unchanged",
		function()
			local d, u = C.districts.Downtown, C.districts.Uptown
			local od, ou = old.City.districts.Downtown, old.City.districts.Uptown
			local function area(r: any): number
				return (r.maxX - r.minX) * (r.maxZ - r.minZ)
			end
			check(d.maxX - d.minX == 980 and d.maxZ - d.minZ == 1120, "Downtown is 980 x 1,120")
			check(u.maxX - u.minX == 750 and u.maxZ - u.minZ == 750, "Uptown is 750 x 750")
			local fd, fu = area(d) / area(od), area(u) / area(ou)
			check(fd >= 1.45 and fd <= 1.65, string.format("Downtown grew %.2fx (planned about 1.5x)", fd))
			check(fu >= 1.45 and fu <= 1.65, string.format("Uptown grew %.2fx (planned about 1.5x)", fu))
			check(
				inside(d, od.minX, od.minZ, 0.01) and inside(d, od.maxX, od.maxZ, 0.01),
				"Downtown holds its old 840 x 840"
			)
			check(
				inside(u, ou.minX, ou.minZ, 0.01) and inside(u, ou.maxX, ou.maxZ, 0.01),
				"Uptown holds its old 600 x 600"
			)
			check(
				u.maxX <= -100 and u.maxZ <= C.hub.min,
				"Uptown keeps clear of Northgate and out of the hub"
			)

			-- every older building is where it was, with its group name (its draws, its order)
			local a, b = CityLayout.downtown(old.City, W), CityLayout.downtown(C, W)
			local same = #b.buildings > #a.buildings
			for i, x in a.buildings do
				local y = b.buildings[i]
				same = same
					and y ~= nil
					and y.x == x.x
					and y.z == x.z
					and y.h == x.h
					and y.grp == x.grp
					and y.sx == x.sx
			end
			check(
				same,
				string.format("Downtown's %d older buildings unchanged (%d now)", #a.buildings, #b.buildings)
			)
			local ua, ub = CityLayout.uptown(old.City), CityLayout.uptown(C)
			local usame = #ub.buildings > #ua.buildings
				and ua.park.x == ub.park.x
				and ua.park.z == ub.park.z
				and ua.landmark.x == ub.landmark.x
				and ua.landmark.z == ub.landmark.z
			for i, x in ua.buildings do
				local y = ub.buildings[i]
				usame = usame and y ~= nil and y.x == x.x and y.z == x.z and y.h == x.h and y.grp == x.grp
			end
			check(
				usame,
				string.format(
					"Uptown's %d older buildings, green and landmark unchanged (%d now)",
					#ua.buildings,
					#ub.buildings
				)
			)
			for id, s in a.safehouseSpots do
				check(
					b.safehouseSpots[id].x == s.x and b.safehouseSpots[id].z == s.z,
					"safehouse lot " .. id .. " unchanged"
				)
			end
			check(a.beacon.x == b.beacon.x and a.beacon.z == b.beacon.z, "the Beacon Tower did not move")

			-- more tall towers, mostly in the new blocks (skyscraper fights)
			local function towers(list: { any }): number
				local n = 0
				for _, x in list do
					if (x.peak or 0) - (x.base or gy) >= 380 then
						n += 1
					end
				end
				return n
			end
			local tA, tB = towers(a.buildings), towers(b.buildings)
			local tuA, tuB = towers(ua.buildings), towers(ub.buildings)
			check(tB >= tA + 20, string.format("Downtown towers %d -> %d", tA, tB))
			check(tuB >= tuA + 8, string.format("Uptown towers %d -> %d", tuA, tuB))
			local newOnes = #b.buildings - #a.buildings
			check(
				(tB - tA) / newOnes > tA / #a.buildings,
				string.format("the new blocks are tower country (%d of %d new buildings)", tB - tA, newOnes)
			)
			print(
				string.format(
					"  bigger again: Downtown %d -> %d buildings (towers %d -> %d), Uptown %d -> %d (towers %d -> %d)",
					#a.buildings,
					#b.buildings,
					tA,
					tB,
					#ua.buildings,
					#ub.buildings,
					tuA,
					tuB
				)
			)
		end
	)

	test("City play: every safehouse, beacon, site, square and system still fits the bigger city", function()
		local d, u = C.districts.Downtown, C.districts.Uptown
		local pad = W.safehouse.pad
		-- safehouses: Downtown's on their lots inside, every other one clear of both districts
		for _, s in world.safehouses do
			if s.district == "Downtown" then
				check(inside(d, s.x, s.z, -pad / 2), s.name .. " is inside Downtown")
			else
				for _, name in { "Downtown", "Uptown" } do
					check(
						not inside(C.districts[name], s.x, s.z, pad / 2 + 10),
						s.name .. " is clear of " .. name
					)
				end
			end
		end
		-- South Park moved south out of the way; North Park and Northgate keep their spots
		check(
			world.safehouses[12].z == 720 and world.safehouses[12].z - pad / 2 > d.maxZ + 40,
			"South Park clear of Downtown"
		)
		check(world.safehouses[12].z + pad / 2 < C.hub.max, "South Park still in the hub")
		-- beacons: on their roofs and landmarks; the Downtown ones inside Downtown, none inside Uptown's streets
		for _, b in world.beacons do
			if b.name == "Crane's Hero Hall" or b.name == "Downtown East" then
				check(inside(d, b.x, b.z, 0), b.name .. "'s beacon is in Downtown")
			end
		end
		-- every side quest site in Downtown, Uptown or a square resolves, inside its district, and on the same
		-- building or square as before the city grew
		local oldWorld = WorldMap.build(old, 202647)
		local checked = 0
		for id, st in Config.SideQuests.sites do
			local cityside = st.square or st.district == "Downtown" or st.district == "Uptown"
			if cityside and not SideQuestSites.isOutskirts(st) then
				local b = SideQuestSites.place(Config, world, id)
				local a = SideQuestSites.place(old, oldWorld, id)
				check(b ~= nil, id .. " resolves")
				if b and a then
					checked += 1
					local r = if st.district == "Uptown" then u else d
					check(inside(r, b.x, b.z, 0), id .. " is inside its district")
					check(a.x == b.x and a.z == b.z, id .. " is where it was")
				end
			end
		end
		check(checked >= 6, string.format("%d city side quest sites checked", checked))
		-- the open squares are where they were
		for i, o in world.open do
			check(o.x == oldWorld.open[i].x and o.z == oldWorld.open[i].z, o.id .. " did not move")
		end
		-- citizens walk the whole of Downtown: the sidewalk graph reaches its new corners
		local nodes = CitizenSim.graph(Config)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, n in nodes do
			if inside(d, n.x, n.z, 0) then
				x0, x1, z0, z1 = math.min(x0, n.x), math.max(x1, n.x), math.min(z0, n.z), math.max(z1, n.z)
			end
		end
		check(
			x0 < d.minX + 40 and x1 > d.maxX - 40 and z0 < d.minZ + 40 and z1 > d.maxZ - 40,
			"the sidewalk graph spans Downtown"
		)
		-- the map's city pictures cover both districts
		local img = MapPlan.cityImages(C)
		check(img.Hub.x0 <= d.minX and img.Hub.z1 >= d.maxZ, "the hub picture covers Downtown")
		check(
			img.Uptown.x0 == u.minX and img.Uptown.z0 == u.minZ and img.Uptown.x1 == u.maxX,
			"the Uptown picture is Uptown"
		)
		-- no road or highway runs into either district; the column 12 highway is untouched
		local tiles = WorldGen.tiles(C, W, 202647)
		for tz = 0, W.tiles - 1 do
			local t = WorldGen.get(W, tiles, 12, tz)
			local x0t, z0t = WorldGen.tileOrigin(C, 12, tz)
			if WorldGen.ring(W, 12, tz) > 0 and not inside(u, x0t + 50, z0t + 50, 50) then
				check(
					t.hwyNS or t.zone == W.zones.coast or t.zone == W.zones.landmark or t.variant == W.special,
					"highway column 12 at " .. tz
				)
			end
		end
	end)

	test(
		"City play: awnings, roof pieces and perches: placed, in their building, never in another",
		function()
			local count: { [string]: number } = {}
			local byGrp: { [string]: any } = {}
			for _, b in world.hubBoxes do
				if b.kind == "building" and b.grp then
					byGrp[b.grp] = b
				end
			end
			local bodies = {}
			for _, b in world.hubBoxes do
				if b.kind == "building" then
					table.insert(bodies, b)
				end
			end
			local function hitsBody(b: any, own: any): boolean
				for _, o in bodies do
					if
						o ~= own
						and math.abs(o.cx - b.cx) < (o.sx + b.sx) / 2 - 0.05
						and math.abs(o.cz - b.cz) < (o.sz + b.sz) / 2 - 0.05
						and math.abs(o.cy - b.cy) < (o.sy + b.sy) / 2
					then
						return true
					end
				end
				return false
			end
			local d, u = C.districts.Downtown, C.districts.Uptown
			local ok = true
			for _, b in world.hubBoxes do
				local a = b.art
				if a then
					count[a.name] = (count[a.name] or 0) + 1
					local def = K.props[a.name]
					check(def ~= nil and def.server == true, a.name .. " is a server-built kit prop")
					for piece in def.pieces do
						check(
							-- (the living world's shop fronts are Art.Life meshes: Config.LifeArt, 2026-11-19)
							(Config.StreetArt[a.name] or Config.LifeArt[a.name])
								and (Config.StreetArt[a.name] or Config.LifeArt[a.name])[piece] ~= nil,
							a.name .. "." .. piece .. " has a mesh"
						)
					end
					check(b.grp ~= nil and b.bid ~= nil, a.name .. " belongs to a wreckable building")
					local body = b.grp and byGrp[b.grp]
					if body then
						local top = body.cy + body.sy / 2
						if a.name == "Awning" or a.name == "Perch" or a.name == "ShopFront" then
							-- on the body's face, reaching out, below the roof, not into another building
							ok = ok and a.y < top and not hitsBody(b, body)
							local fx = math.abs(a.x - body.cx) - body.sx / 2
							local fz = math.abs(a.z - body.cz) - body.sz / 2
							ok = ok and (math.abs(fx) < 0.01 or math.abs(fz) < 0.01)
						else
							-- on its own roof, inside its footprint
							ok = ok
								and math.abs(a.y - top) < 0.01
								and math.abs(a.x - body.cx) <= body.sx / 2
								and math.abs(a.z - body.cz) <= body.sz / 2
						end
					end
					check(
						inside(d, a.x, a.z, 0) or inside(u, a.x, a.z, 0),
						a.name .. " is in Downtown or Uptown"
					)
					if a.tint then
						check(C.palette[a.tint] ~= nil, a.name .. "'s tint is a palette colour")
					end
				end
			end
			check(ok, "every awning and perch on its own face, every roof piece on its own roof")
			-- each building's art pieces stay few (Skyscrapers keeps its boxes at 32 at most)
			local perB: { [string]: number } = {}
			local most = 0
			for _, b in world.hubBoxes do
				if b.art and b.grp then
					perB[b.grp] = (perB[b.grp] or 0) + CityKit.parts(K, b.art.name)
					most = math.max(most, perB[b.grp])
				end
			end
			-- (48 since the living world's shop fronts, 4 meshes each under the awnings, 2026-11-19)
			check(most <= 48, string.format("at most 48 art pieces on a building (%d)", most))
			for _, name in
				{ "Awning", "WaterTower", "RoofAntenna", "RoofAC", "RoofVent", "RoofBillboard", "Perch" }
			do
				check((count[name] or 0) >= 20, string.format("%s: %d placed", name, count[name] or 0))
			end
			-- awnings hang over the sidewalk, never over the road: the block's edge is past their front
			for _, b in world.hubBoxes do
				if b.tag == "Awning" then
					local h = WorldMap.heightAt(world, b.cx, b.cz)
					check(h >= b.cy + b.sy / 2 - 0.05, "an awning is something to land on")
				end
			end
			-- a beacon's roof keeps its pad clear: no roof piece above the beacon pad on its host
			for _, bc in world.beacons do
				for _, b in world.hubBoxes do
					if
						b.art
						and b.kind == "prop"
						and math.abs(b.cx - bc.x) < 8
						and math.abs(b.cz - bc.z) < 8
					then
						check(b.cy - b.sy / 2 < bc.y - 2, bc.name .. "'s pad is clear of roof pieces")
					end
				end
			end
			-- deterministic and hash-picked: the same twice, and the layout's draws unchanged without them
			local k2 = table.clone(K)
			k2.play = nil
			local c2 = table.clone(C)
			c2.kit = k2
			local plain = CityLayout.downtown(c2, W)
			local full = CityLayout.downtown(C, W)
			local sameB = #plain.buildings == #full.buildings
			for i, x in plain.buildings do
				local y = full.buildings[i]
				sameB = sameB and x.x == y.x and x.z == y.z and x.h == y.h
			end
			check(sameB, "the pieces never change a building")
			print(
				string.format(
					"  city play: %d awnings, %d water towers, %d antennas, %d air conditioners, %d vents, %d billboards, %d perches",
					count.Awning or 0,
					count.WaterTower or 0,
					count.RoofAntenna or 0,
					count.RoofAC or 0,
					count.RoofVent or 0,
					count.RoofBillboard or 0,
					count.Perch or 0
				)
			)
		end
	)

	test(
		"City play: awnings bounce, the server finds them, perches are landing spots, roofs throw their pieces",
		function()
			-- the bounce
			check(CityPlay.bounce(P, -5) == nil, "no bounce from a step down")
			check(CityPlay.bounce(P, -P.bounce.minFall - 1) == P.bounce.up, "a short fall springs at `up`")
			check(CityPlay.bounce(P, -400) == P.bounce.max, "a long fall is capped")
			local mid = CityPlay.bounce(P, -150)
			check(mid ~= nil and mid >= P.bounce.up and mid <= P.bounce.max, "a harder fall springs higher")
			local leap = Config.Move.mobility.leap.bounce.up
			check(P.bounce.up >= leap * 0.9, "an awning springs about a Leap wall bounce")
			-- the server's check: every awning is found from on top of it, none from the street below or far off
			local idx = CityPlay.awnings(world.hubBoxes)
			check(idx.count >= 100, string.format("%d awnings indexed", idx.count))
			local found, wrong = 0, 0
			for _, b in world.hubBoxes do
				if b.tag == "Awning" then
					local top = b.cy + b.sy / 2
					if CityPlay.nearAwning(idx, b.cx, top + 3, b.cz, P.bounce.reach) == b then
						found += 1
					end
					if CityPlay.nearAwning(idx, b.cx, gy + 3, b.cz, P.bounce.reach) then
						wrong += 1
					end
				end
			end
			check(
				found == idx.count,
				string.format("every awning found from its top (%d/%d)", found, idx.count)
			)
			check(wrong == 0, "never from the sidewalk under it")
			check(CityPlay.nearAwning(idx, 0, 400, 0, P.bounce.reach) == nil, "never from the sky")
			-- perches: a Leap's climb apart up a tower, below its roof, one level at a time
			local perY: { [string]: { number } } = {}
			for _, b in world.hubBoxes do
				if b.tag == "Perch" then
					perY[b.grp] = perY[b.grp] or {}
					table.insert(perY[b.grp], b.cy)
				end
			end
			local towersWith = 0
			for _, ys in perY do
				towersWith += 1
				table.sort(ys)
				for i = 2, #ys do
					check(math.abs(ys[i] - ys[i - 1] - P.perch.every) < 0.01, "perches one level apart")
				end
			end
			check(towersWith >= 40, string.format("%d towers have perches", towersWith))
			-- what falls: the roof pieces, the tank bursts; awnings bounce; all server-built in the building's model
			check(
				K.props.RoofBillboard.falls and K.props.WaterTower.burst and K.props.Awning.bounce,
				"falls, bursts, bounces"
			)
			-- the code paths: CityBuilder builds the meshes in place of the box, BuildingFx throws them, MoveController
			-- bounces and the server grants it
			local fs = require("@lune/fs")
			local cb = fs.readFile("src/server/Services/CityBuilder.luau")
			local bf = fs.readFile("src/client/Fx/BuildingFx.luau")
			local mc = fs.readFile("src/client/Controllers/MoveController.luau")
			local im = fs.readFile("src/server/Services/ImpactService.luau")
			local function has(t: string, n: string): boolean
				return string.find(t, n, 1, true) ~= nil
			end
			check(
				has(cb, "streetArt(b)") and has(cb, 'SetAttribute("Bounce", true)'),
				"CityBuilder builds the art"
			)
			check(
				has(bf, 'GetAttribute("Falls")') and has(bf, "roofFall(model, rec)"),
				"BuildingFx throws the roof pieces"
			)
			check(has(mc, "awningUp(vel.Y)") and has(mc, 'Net.send("CityBounce")'), "MoveController bounces")
			check(
				has(im, 'Net.on("CityBounce", onBounce)') and has(im, "MoveGuard.grant"),
				"the server grants the bounce"
			)
			local R = require("../src/shared/Remotes")
			check(
				R.CityBounce ~= nil and R.CityBounce.dir == "C2S" and R.CityBounce.rate <= 2,
				"CityBounce is rate limited"
			)
		end
	)

	test("City play: news boxes and food carts, tints, and the part counts per district", function()
		local n: { [string]: number } = {}
		for _, p in world.props do
			n[p.name] = (n[p.name] or 0) + 1
			if p.name == "NewsBox" or p.name == "FoodCart" then
				check(p.tint ~= nil and C.palette[p.tint] ~= nil, p.name .. " has a tint")
			end
		end
		check((n.NewsBox or 0) >= 60, string.format("%d news boxes", n.NewsBox or 0))
		check((n.FoodCart or 0) >= 3, string.format("%d food carts", n.FoodCart or 0))
		for name, def in K.props do
			for piece, look in def.pieces do
				check(
					(Config.StreetArt[name] or Config.LifeArt[name])
						and (Config.StreetArt[name] or Config.LifeArt[name])[piece] ~= nil,
					name .. "." .. piece .. " in StreetArt (or LifeArt)"
				)
				check(look[5] == nil or look[5] == true, name .. "." .. piece .. " tint flag")
			end
		end
		-- part counts: the server's hub parts (each art box becomes its prop's meshes) within the hub budget
		local boxes, art, meshes = 0, 0, 0
		local per: { [string]: number } = {}
		local d, u = C.districts.Downtown, C.districts.Uptown
		for _, b in world.hubBoxes do
			local parts = 1
			if b.art then
				art += 1
				parts = CityKit.parts(K, b.art.name)
				meshes += parts
			else
				boxes += 1
			end
			local where = if inside(d, b.cx, b.cz, 0)
				then "Downtown"
				elseif inside(u, b.cx, b.cz, 0) then "Uptown"
				else "rest"
			per[where] = (per[where] or 0) + parts
		end
		local total = boxes + meshes
		check(total <= C.partBudget.hub + C.partBudget.downtown, string.format("hub parts %d", total))
		check(per.Downtown <= C.partBudget.downtown, string.format("Downtown parts %d", per.Downtown))
		check(per.Uptown <= C.partBudget.uptown, string.format("Uptown parts %d", per.Uptown))
		-- a phone keeps its street prop cap (the new street props are tier 2: never on Low)
		check(
			K.props.NewsBox.tier >= 2 and K.props.FoodCart.tier >= 2,
			"news boxes and carts are not on phones"
		)
		print(
			string.format(
				"  city parts: hub %d (%d boxes + %d art pieces from %d art boxes); Downtown %d, Uptown %d; props %d news boxes, %d carts",
				total,
				boxes,
				meshes,
				art,
				per.Downtown,
				per.Uptown,
				n.NewsBox or 0,
				n.FoodCart or 0
			)
		)
	end)
end
