-- The city life pass (2026-11-19, own file): citizens on Roblox's own R15 idle, walk and run (Shared.LocoMath
-- pickAnimated and idlePick, Config.Destruction.citizens.loco, the presets' citizenAnim numbers) and the map
-- screen's comic city map (Shared.MapPlan: projection, the zoom and pan view, merged zones, roads, the city
-- pictures and their box count, the names; Config.MapArt). ONLY="City life" runs just these.
-- Called from tests/run.luau.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local LocoMath = require("../src/shared/LocoMath")
	local RigMath = require("../src/shared/RigMath")
	local BodyShape = require("../src/shared/BodyShape")
	local MapPlan = require("../src/shared/MapPlan")
	local WorldGen = require("../src/shared/WorldGen")
	local WorldMap = require("../src/shared/WorldMap")
	local Rng = require("../src/shared/Rng")
	local C = Config.Destruction.citizens
	local L = C.loco
	local E = Config.Enemies.look.loco

	local function near(a: number, b: number, tol: number): boolean
		return math.abs(a - b) <= tol
	end

	test("City life: citizens play Roblox's own clips, the robots' blend", function()
		check(L.on == true, "on")
		for _, k in { "idle", "walk", "run", "still", "walkAt", "runAt", "refLeg", "minWarp", "maxWarp" } do
			check(L[k] == E[k], k .. " matches the robots' (Config.Enemies.look.loco)")
		end
		check(#L.idles >= 2, "more than one idle")
		local total = 0
		for _, e in L.idles do
			check(
				type(e[1]) == "string" and e[1]:match("^rbxassetid://%d+$") ~= nil,
				"idle id " .. tostring(e[1])
			)
			check(type(e[2]) == "number" and e[2] > 0, "idle weight")
			total += e[2]
		end
		check(L.idles[1][1] == L.idle, "the plain breathing idle is the first and most common")
		check(L.idles[1][2] / total >= 0.6, "the plain idle most of the time")
		check(L.idleRate[1] < 1 and L.idleRate[2] > 1, "idle paces either side of 1")
		check(L.fleeArms < -math.rad(90), "the flee throws the arms up")
		for _, name in Config.Presets.order do
			local q = Config.Presets[name]
			check(type(q.citizenAnimNear) == "number" and q.citizenAnimNear > 0, name .. " citizenAnimNear")
			check(type(q.citizenAnimMax) == "number" and q.citizenAnimMax > 0, name .. " citizenAnimMax")
			check(q.citizenAnimMax <= (q.citizensDrawn or C.max), name .. ": no more animated than drawn")
			check(
				q.citizenAnimNear <= (q.citizenPoseNear or C.poseNear) * 1.25,
				name .. ": animated inside the posed ring"
			)
		end
		check(Config.Presets.low.citizenAnimMax <= 8, "a phone animates at most 8 citizens")
		check(
			Config.Presets.low.citizenAnimMax + Config.Presets.low.enemiesDrawn <= 30,
			"a phone's animated rigs stay few (citizens plus robots)"
		)
	end)

	test("City life: walk and run speed-matched for every citizen body", function()
		for i, b in C.bodies do
			local factors = BodyShape.factors(Config, { gender = b[1], build = b[2], height = 3 })
			local lay = RigMath.layout(Config.HeroRig, factors, 1)
			local hs = LocoMath.heightScale(lay.ground, lay.hip, L)
			check(hs > 0.6 and hs < 1.6, "body " .. i .. " heightScale " .. hs)
			local walk = LocoMath.blend(C.walk, hs, L)
			check(walk.walk > 0.5, "body " .. i .. ": a walking citizen plays the walk")
			check(
				near(LocoMath.covered(walk, hs, L), C.walk, C.walk * 0.1),
				"body " .. i .. ": walk feet keep pace"
			)
			local run = LocoMath.blend(C.run, hs, L)
			check(run.run == 1, "body " .. i .. ": a fleeing citizen plays the run")
			check(
				near(LocoMath.covered(run, hs, L), C.run, C.run * 0.1),
				"body " .. i .. ": run feet keep pace"
			)
			check(LocoMath.blend(0, hs, L).idle == 1, "body " .. i .. ": a paused citizen idles")
		end
	end)

	test("City life: only the nearest few animate, with no flicker at the edge", function()
		local rows = {}
		for id = 1, 60 do
			table.insert(rows, { id = id, dist = id * 5 }) -- 5, 10, ... 300 studs
		end
		local low = Config.Presets.low
		local pick = LocoMath.pickAnimated(rows, {}, low.citizenAnimNear, low.citizenAnimMax, L.keep)
		local n = 0
		for id in pick do
			n += 1
			check(id <= low.citizenAnimMax, "nearest first (" .. id .. ")")
		end
		check(
			n == math.min(low.citizenAnimMax, math.floor((low.citizenAnimNear - 0.001) / 5)),
			"phone count " .. n
		)
		-- within range but past the cap: none
		local few = LocoMath.pickAnimated(rows, {}, 1000, 3, L.keep)
		local c = 0
		for _ in few do
			c += 1
		end
		check(c == 3, "the cap holds")
		-- hysteresis: one already animated just past the edge stays; a new one there does not start
		local edge = { { id = 1, dist = 52 }, { id = 2, dist = 52 } }
		local kept = LocoMath.pickAnimated(edge, { [1] = true }, 50, 8, L.keep)
		check(kept[1] == true and kept[2] == nil, "kept just past the edge, not started")
		local gone = LocoMath.pickAnimated(
			{ { id = 1, dist = 50 * L.keep + 1 } },
			{ [1] = true },
			50,
			8,
			L.keep
		)
		check(gone[1] == nil, "dropped well past the edge")
		check(next(LocoMath.pickAnimated(rows, {}, 0, 8, L.keep)) == nil, "near 0 (loco off): none")
	end)

	test("City life: each citizen its own idle, pace and point in the loop", function()
		local counts = {}
		local speeds, offsets = {}, {}
		for id = 1, 2000 do
			local i, sp, off = LocoMath.idlePick(Rng.hash(id, 3301), L.idles, L.idleRate)
			counts[i] = (counts[i] or 0) + 1
			check(i >= 1 and i <= #L.idles, "a listed idle")
			check(sp >= L.idleRate[1] - 1e-9 and sp <= L.idleRate[2] + 1e-9, "pace in range")
			check(off >= 0 and off < 1, "offset in the loop")
			speeds[math.floor(sp * 20)] = true
			offsets[math.floor(off * 10)] = true
		end
		local total = 0
		for _, e in L.idles do
			total += e[2]
		end
		for i, e in L.idles do
			local share = (counts[i] or 0) / 2000
			check(near(share, e[2] / total, 0.05), "idle " .. i .. " by weight (" .. share .. ")")
		end
		local ns, no = 0, 0
		for _ in speeds do
			ns += 1
		end
		for _ in offsets do
			no += 1
		end
		check(ns >= 5 and no == 10, "paces and offsets spread out")
	end)

	local A = Config.MapArt
	local CC, W = Config.City, Config.World
	test("City life: map projection and the zoom and pan view", function()
		local m = A.margin
		local u, v = MapPlan.project(CC, m, -CC.mapSize / 2 - m, -CC.mapSize / 2 - m)
		check(near(u, 0, 1e-9) and near(v, 0, 1e-9), "the sea's north-west corner is 0, 0")
		u, v = MapPlan.project(CC, m, 0, 0)
		check(near(u, 0.5, 1e-9) and near(v, 0.5, 1e-9), "the centre is the middle")
		local x, z = MapPlan.unproject(CC, m, MapPlan.project(CC, m, 123, -456))
		check(near(x, 123, 1e-6) and near(z, -456, 1e-6), "round trip")
		local _, _, du = MapPlan.rectUV(CC, m, { x0 = 0, z0 = 0, x1 = CC.tile, z1 = CC.tile })
		check(near(du, CC.tile / (CC.mapSize + 2 * m), 1e-9), "a tile's width")
		-- a square frame at zoom 1: the whole map, centred, wherever asked
		local vw = MapPlan.view(1, 0.1, 0.9, A.maxZoom, 400, 400)
		check(vw.u == 0.5 and vw.v == 0.5 and vw.sx == 1 and vw.x == 0, "zoom 1 shows it all")
		-- a phone's wide frame: the map fits its height, centred across
		vw = MapPlan.view(1, 0.2, 0.2, A.maxZoom, 600, 250)
		check(vw.side == 250 and vw.u == 0.5 and vw.v == 0.5, "wide frame, zoom 1")
		check(near(vw.sx, 250 / 600, 1e-9) and vw.sy == 1, "the canvas a square of the short side")
		-- zoomed: the centre is kept inside so the canvas covers the frame
		vw = MapPlan.view(2, 0, 1, A.maxZoom, 400, 400)
		check(vw.u == 0.25 and vw.v == 0.75, "pan clamped to the map's edge")
		check(vw.x == 0 and near(vw.y + vw.sy, 1, 1e-9), "covers the frame")
		check(MapPlan.view(99, 0.5, 0.5, A.maxZoom, 400, 400).zoom == A.maxZoom, "max zoom")
		check(MapPlan.view(0.1, 0.5, 0.5, A.maxZoom, 400, 400).zoom == 1, "min zoom")
		-- the frame's centre is the view's centre; its edge is half the visible span away
		vw = MapPlan.view(2, 0.4, 0.6, A.maxZoom, 400, 400)
		local fu, fv = MapPlan.frameToMap(vw, 400, 400, 0.5, 0.5)
		check(near(fu, 0.4, 1e-9) and near(fv, 0.6, 1e-9), "frame centre")
		fu = MapPlan.frameToMap(vw, 400, 400, 1, 0.5)
		check(near(fu, 0.65, 1e-9), "frame edge")
		check(A.openZoom >= 1 and A.openZoom <= A.maxZoom, "open zoom in range")
	end)

	test("City life: this week's outskirts as merged zones and roads", function()
		for _, seed in { 1, 202647, 999331 } do
			local tiles = WorldGen.tiles(CC, W, seed)
			local zones = MapPlan.zones(CC, W, tiles)
			check(
				#zones > 4 and #zones < 260,
				"seed " .. seed .. ": a few dozen frames, not 2,000 (" .. #zones .. ")"
			)
			-- every outskirts tile in exactly one rectangle of its own zone
			local n = W.tiles
			local half = CC.mapSize / 2
			local cover = {}
			for _, r in zones do
				check(r.x1 > r.x0 and r.z1 > r.z0, "a real rectangle")
				for tz = math.floor((r.z0 + half) / CC.tile), math.floor((r.z1 + half) / CC.tile) - 1 do
					for tx = math.floor((r.x0 + half) / CC.tile), math.floor((r.x1 + half) / CC.tile) - 1 do
						local k = tz * n + tx
						check(cover[k] == nil, "no tile twice")
						cover[k] = r.zone
					end
				end
			end
			local Z = W.zones
			local names = {
				[Z.suburbs] = "suburbs",
				[Z.farmland] = "farmland",
				[Z.coast] = "coast",
				[Z.landmark] = "landmark",
			}
			local bad = 0
			for tz = 0, n - 1 do
				for tx = 0, n - 1 do
					local t = WorldGen.get(W, tiles, tx, tz)
					if cover[tz * n + tx] ~= names[t.zone] then
						bad += 1
					end
				end
			end
			check(
				bad == 0,
				"seed " .. seed .. ": every outskirts tile covered by its own zone (" .. bad .. " wrong)"
			)
			local roads = MapPlan.roads(CC, W, tiles)
			local hw = 0
			for _, r in roads do
				check(
					r.x0 >= -half - 1 and r.x1 <= half + 1 and r.z0 >= -half - 1 and r.z1 <= half + 1,
					"on the map"
				)
				if r.highway then
					hw += 1
					check(math.min(r.x1 - r.x0, r.z1 - r.z0) >= W.roads.highwayWidth - 0.1, "highway width")
				end
			end
			check(
				#roads > 20 and #roads < 200 and hw > 4,
				"seed " .. seed .. ": roads " .. #roads .. ", highways " .. hw
			)
			check(#MapPlan.sand(CC, W, tiles) >= 4, "the coast's sand")
		end
	end)

	test("City life: the city pictures, their ids and the names", function()
		local imgs = MapPlan.cityImages(CC)
		check(imgs.Hub ~= nil and imgs.Uptown ~= nil, "two pictures")
		for id, d in CC.districts do
			local r = if id == "Uptown" then imgs.Uptown else imgs.Hub
			check(
				r.x0 <= d.minX and r.x1 >= d.maxX and r.z0 <= d.minZ and r.z1 >= d.maxZ,
				id .. " inside its picture"
			)
		end
		check(#imgs.Hub.own >= 4, "the hub picture owns the hub square and its districts")
		for _, tbl in { A.city, A.patterns } do
			for k, v in tbl do
				check(type(v) == "number" and v > 0 and v == math.floor(v), "MapArt " .. k .. " uploaded")
			end
		end
		-- the hub and Uptown never change with the seed, and the pictures were drawn from today's layout
		local a = MapPlan.cityBoxes(CC, W, WorldMap.build(Config, 202647))
		local b = MapPlan.cityBoxes(CC, W, WorldMap.build(Config, 31337))
		check(#a == #b, "the city pictures are the same for any seed (" .. #a .. " vs " .. #b .. ")")
		check(
			#a == A.boxes,
			"Config.MapArt.boxes matches the layout ("
				.. #a
				.. "): redraw (art/map/layout.luau, draw.py) and re-upload the city pictures"
		)
		local labels = MapPlan.labels(CC, W, { Uptown = "UPTOWN" })
		local kinds = {}
		for _, l in labels do
			kinds[l.kind] = (kinds[l.kind] or 0) + 1
			check(type(l.text) == "string" and #l.text > 0, "named")
			check(
				math.abs(l.x) <= CC.mapSize / 2 and math.abs(l.z) <= CC.mapSize / 2,
				l.text .. " on the map"
			)
		end
		check(
			kinds.district == 4 and kinds.landmark == #W.landmarks and kinds.zone == 3,
			"district, landmark and ring names"
		)
	end)
end
