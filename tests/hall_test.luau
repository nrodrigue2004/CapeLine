-- Crane's Hero Hall (hero-hall, 2026-11-21; nate: "still cant enter building by hub area and it doesnt look like
-- a hub area"): the Beacon Tower's hollow base from Shared.HallLayout through the real city layout (WorldMap):
-- open doorways, a walkable stair, head room, every terminal tagged, the solid tower above, the plaza's hub props
-- clear of the doors, spawns and the contest corner. Called from tests/run.luau:
--   require("./hall_test")({ test = test, check = check, Config = Config, world = world, placePath = p })
-- ONLY="Hero Hall" runs just these. What only Studio can show is in notes/Tasks.md "Hero Hall".

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local HallLayout = require("../src/shared/HallLayout")
	local MapPlan = require("../src/shared/MapPlan")
	local Remotes = require("../src/shared/Remotes")
	local H = Config.Hall

	local d = world.downtown
	local spots = d and d.hall
	local boxes = (d and d.boxes) or {}
	local cx, cz = d.beacon.x, d.beacon.z
	local half = Config.City.downtown.beacon.width / 2

	-- a box that a hero bumps into
	local function solid(b: any): boolean
		return not (b.ghost or b.kind == "glow" or b.kind == "mark" or b.kind == "band" or b.kind == "spawn")
	end
	local function overlaps(b: any, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
		local e = 0.01
		return b.cx + b.sx / 2 > x0 + e
			and b.cx - b.sx / 2 < x1 - e
			and b.cy + b.sy / 2 > y0 + e
			and b.cy - b.sy / 2 < y1 - e
			and b.cz + b.sz / 2 > z0 + e
			and b.cz - b.sz / 2 < z1 - e
	end
	local function blocked(x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, skip: any?)
		for _, b in boxes do
			if b ~= skip and solid(b) and overlaps(b, x0, x1, y0, y1, z0, z1) then
				return b
			end
		end
		return nil
	end

	test("Hero Hall: the Beacon Tower's base is hollow and its doorways are open", function()
		check(H.on == true, "Config.Hall is on")
		check(spots ~= nil, "the layout has the Hall's spots")
		if not spots then
			return
		end
		local top = spots.levels.lobby
		-- the tower's solid box starts where the base ends and reaches the old top
		local tower = nil
		for _, b in boxes do
			if b.kind == "beacon" and b.sy > 200 then
				tower = b
			end
		end
		check(tower ~= nil, "the solid tower is there")
		if tower then
			check(
				math.abs((tower.cy - tower.sy / 2) - spots.levels.solid) < 0.05,
				"the tower starts on the base"
			)
			local gy = Config.City.ground.y
			check(
				math.abs((tower.cy + tower.sy / 2) - (gy + 1 + d.beacon.h)) < 0.05,
				"the tower's top is unchanged"
			)
		end
		-- each doorway: nothing solid in its opening through the wall
		local D = H.door
		for _, f in D.faces do
			local fx, fz = f[1], f[2]
			local x0, x1, z0, z1
			if fz ~= 0 then
				x0, x1 = cx - D.width / 2 + 0.5, cx + D.width / 2 - 0.5
				local zz = cz + fz * half
				z0, z1 = math.min(zz, zz - fz * 3), math.max(zz, zz - fz * 3)
			else
				z0, z1 = cz - D.width / 2 + 0.5, cz + D.width / 2 - 0.5
				local xx = cx + fx * half
				x0, x1 = math.min(xx, xx - fx * 3), math.max(xx, xx - fx * 3)
			end
			local hit = blocked(x0, x1, top + 0.3, top + D.height - 0.5, z0, z1)
			check(
				hit == nil,
				string.format("the %d,%d doorway is open (%s)", fx, fz, hit and hit.color or "clear")
			)
		end
		-- the east face (the Ceremony's backdrop) stays whole
		check(
			blocked(cx + half - 2, cx + half, top + 1, top + 10, cz - 4, cz + 4) ~= nil,
			"the east face has no doorway"
		)
		-- the lobby is open inside from the floor to its ceiling round the dais's ring
		check(
			blocked(cx - 12, cx + 12, top + 2, spots.levels.train - H.slab - 0.5, cz - 19, cz - 12) == nil,
			"the lobby's front half is clear to walk"
		)
		check(MapPlan ~= nil, "MapPlan loads")
	end)

	test(
		"Hero Hall: the stair climbs to the training floor with head room, each step a walkable rise",
		function()
			if not spots then
				return
			end
			local steps = {}
			for _, b in boxes do
				if b.hall == "step" then
					table.insert(steps, b)
				end
			end
			table.sort(steps, function(a, b)
				return a.sy < b.sy
			end)
			check(#steps >= 10, "the stair has steps (" .. #steps .. ")")
			local last = spots.levels.lobby
			for i, s in steps do
				local tread = s.cy + s.sy / 2
				check(tread - last <= 1.25 + 1e-6, "step " .. i .. " rises at most 1.25 studs")
				last = tread
				-- head room: nothing solid over the tread for 6 studs but the next steps
				local hit = nil
				for _, b in boxes do
					if b ~= s and b.hall ~= "step" and solid(b) then
						local x0, x1 = s.cx - s.sx / 2, s.cx + s.sx / 2
						local z0, z1 = s.cz - s.sz / 2, s.cz + s.sz / 2
						if overlaps(b, x0, x1, tread, tread + 6, z0, z1) then
							hit = b
						end
					end
				end
				check(
					hit == nil,
					string.format("step %d has head room (%s)", i, hit and tostring(hit.hall) or "clear")
				)
			end
			check(math.abs(last - spots.levels.train) < 0.05, "the top step meets the training floor")
			-- the training floor has head room for the big dummy under the tower
			local ceiling = spots.levels.solid
			check(ceiling - spots.levels.train >= 3 * 2.6 * 2 + 2, "the big dummy fits under the ceiling")
		end
	)

	test("Hero Hall: every terminal, lift stop and pad is tagged and inside the Hall", function()
		if not spots then
			return
		end
		local tags: { [string]: number } = {}
		for _, b in boxes do
			if type(b.tag) == "string" and string.sub(b.tag, 1, 4) == "hall" then
				tags[b.tag] = (tags[b.tag] or 0) + 1
			end
		end
		for _, t in
			{
				"hallShop",
				"hallBoards",
				"hallContracts",
				"hallSquads",
				"hallLoadout",
				"hallWeapons",
				"hallBurst",
				"hallPad",
				"hallScore",
				"hallSign",
				"hallLight",
				"hallMeet",
			}
		do
			check((tags[t] or 0) >= 1, t .. " is tagged")
		end
		check(tags.hallLift == #H.lift.dests, "one lift stop per destination")
		local inner = half - H.wall
		local function inside(s: any, name: string)
			check(
				math.abs(s.x - cx) <= inner and math.abs(s.z - cz) <= inner,
				name .. " stands inside the Hall's walls"
			)
		end
		for i, s in spots.lifts do
			if i < 3 then
				inside(s, "lift " .. i)
			else
				check(
					math.abs(s.x - cx) <= half and math.abs(s.z - cz) <= half,
					"the roof stop is on the roof"
				)
				check(s.y > spots.levels.solid + 100, "the roof stop is on the tower's top")
			end
		end
		for _, s in spots.dummies do
			inside(s, "a dummy")
			check(math.abs(s.y - 3 - spots.levels.train) < 0.5, "a dummy stands on the training floor")
		end
		inside(spots.big, "the big dummy")
		inside(spots.burst, "the Burst pad")
		inside(spots.shop, "the shop counter")
		for i, s in spots.statues do
			inside(s, "statue " .. i)
		end
		-- the launch pad is out on the deck past the tower's face, and its arc ends far from the tower
		local pad = spots.pad
		check(pad.z < cz - half, "the launch pad is out past the front face")
		local R = H.roof.pad
		local tx, tz = pad.x + pad.dir[1] * R.out * 2, pad.z + pad.dir[2] * R.out * 2
		check(math.sqrt((tx - cx) ^ 2 + (tz - cz) ^ 2) > half + 100, "the launch lands far out")
		check(HallLayout.floorAt(spots, cx, spots.levels.lobby + 2, cz) == 1, "floorAt: the lobby")
		check(HallLayout.floorAt(spots, cx, spots.levels.train + 2, cz) == 2, "floorAt: the training floor")
		check(HallLayout.floorAt(spots, cx + 200, 5, cz) == nil, "floorAt: outside")
	end)

	test(
		"Hero Hall: the plaza's hub props stand clear of the doors, the spawns and the contest corner",
		function()
			if not spots then
				return
			end
			local props = d.props or world.props or {}
			local mine = 0
			local K = Config.Contest.stage
			for _, p in props do
				if
					math.abs(p.x - cx) <= Config.City.downtown.block / 2
					and math.abs(p.z - cz) <= Config.City.downtown.block / 2
				then
					mine += 1
					check(p.name ~= nil, "a plaza prop has a name")
					-- not in a doorway's walk-in lane (6 studs either side of its middle, 14 out)
					for _, f in H.door.faces do
						local fx, fz = f[1], f[2]
						local along = if fz ~= 0 then p.x - cx else p.z - cz
						local out = if fz ~= 0 then (p.z - cz) * fz else (p.x - cx) * fx
						check(
							not (
									math.abs(along) < H.door.width / 2 + 1
									and out > half - 1
									and out < half + 14
								),
							string.format(
								"%s at %.0f, %.0f is clear of a doorway",
								p.name,
								p.x - cx,
								p.z - cz
							)
						)
					end
					for _, s in d.spawns do
						check(
							math.sqrt((p.x - s.x) ^ 2 + (p.z - s.z) ^ 2) > 6,
							p.name .. " is clear of a spawn"
						)
					end
					local sx, sz = cx + K.corner, cz + K.corner
					check(
						not (math.abs(p.x - sx) < K.size / 2 + 2 and math.abs(p.z - sz) < K.size / 2 + 2),
						p.name .. " is clear of the contest stage"
					)
				end
			end
			check(mine >= 20, "the plaza is dressed as a hub (" .. mine .. " props)")
		end
	)

	test("Hero Hall: remotes, services and the place", function()
		for _, name in { "HallState", "HallDps", "HallLaunch" } do
			check(
				Remotes[name] ~= nil and Remotes[name].dir == "S2C",
				name .. " is a server-to-client remote"
			)
		end
		check(Remotes.HallPad ~= nil and Remotes.HallPad.dir == "C2S", "HallPad is client-to-server")
		local server = fs.readFile("src/server/init.server.luau")
		check(string.find(server, 'boot("HallService"', 1, true) ~= nil, "the server boots HallService")
		local client = fs.readFile("src/client/init.client.luau")
		check(string.find(client, "HallClient.init()", 1, true) ~= nil, "the device starts HallClient")
		local place = T.placePath
		if place then
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(place))
			local sss = game:GetService("ServerScriptService")
			local svc = sss:FindFirstChild("Server")
			svc = svc and svc:FindFirstChild("Services")
			check(svc ~= nil and svc:FindFirstChild("HallService") ~= nil, "the place has HallService")
			local rs = game:GetService("ReplicatedStorage")
			local shared = rs:FindFirstChild("Shared")
			check(
				shared ~= nil and shared:FindFirstChild("HallLayout") ~= nil,
				"the place has Shared.HallLayout"
			)
		end
	end)
end
