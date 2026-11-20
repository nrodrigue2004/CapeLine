-- Map sites (missions lane, 2026-11-20; nate's call "Mix": story missions play privately on the map, special places
-- keep pockets). Shared.MapSites puts each on-map pocket layout (Config.MapSites) at its real site; checked here for
-- two weekly seeds (only the outskirts change with the seed, every site is in the fixed hub):
--   * every point and list point the steps read stands on solid ground, a roof or a piece (never inside a building,
--     a permanent piece or a set piece, never over the water), at most a short hop above it
--   * the permanent pieces (Harbour Bridge, Crane Tower, Crane's plant) and each run's set pieces never cut into a
--     city building, and the city builds the pieces (they are in its height map, Crane Tower's ledges left out)
--   * the runaway train's line (Most Wanted) runs clear of buildings; every layout keeps its pocket's names
--   * flipping a layout off in Config.MapSites.on sends it back to its pocket
-- What only Studio can prove (the looks, the fades, robots on the decks) is on the Studio list (Tasks.md 442 on).
-- Called from tests/run.luau. ONLY="Map sites" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local MapSites = require("../src/shared/MapSites")
	local PocketLayout = require("../src/shared/PocketLayout")
	local WorldMap = require("../src/shared/WorldMap")
	local HeightMap = require("../src/shared/HeightMap")

	local worlds = { { seed = "run.luau's", world = T.world } }
	local function each(fn: (any, string) -> ())
		if #worlds == 1 then
			table.insert(worlds, { seed = "202650", world = WorldMap.build(Config, 202650) })
		end
		for _, w in worlds do
			if w.world then
				fn(w.world, w.seed)
			end
		end
	end

	local names = {}
	for name, on in Config.MapSites.on do
		if on then
			table.insert(names, name)
		end
	end
	table.sort(names)

	-- does a box cut into a city building (footprints overlap and heights overlap)?
	local function cuts(world: any, b: any): any?
		return MapSites.inBuilding(world, b)
	end

	test("Map sites: every on-map point stands on ground, a roof or a piece", function()
		each(function(world, seed)
			for _, name in names do
				local l = MapSites.layout(Config, world, name) :: any
				check(l ~= nil and l.onMap == true and l.site == name, name .. ": a map layout")
				if not l then
					continue
				end
				local bad = {}
				local function stand(key: string, p: { number })
					local s, why = MapSites.standing(Config, world, l, p[1], p[2], p[3])
					local gap = if s then p[2] - s else nil
					if not s or gap < -0.1 or gap > 4.6 then
						table.insert(
							bad,
							string.format(
								"%s (%.0f, %.1f, %.0f) %s",
								key,
								p[1],
								p[2],
								p[3],
								why or ("gap " .. gap)
							)
						)
					end
				end
				for key, p in l.points do
					if key ~= "trainDir" then
						stand(key, p)
					end
				end
				for key, list in l.lists do
					for i, p in list do
						stand(key .. i, p)
					end
				end
				check(
					#bad == 0,
					string.format("%s (seed %s): %d points off: %s", name, seed, #bad, bad[1] or "")
				)
			end
		end)
	end)

	test("Map sites: the pieces stand clear of the city's buildings", function()
		each(function(world, seed)
			for _, b in MapSites.permanent(Config).boxes do
				local c = cuts(world, b)
				check(
					c == nil,
					string.format(
						"%s's %s at (%.0f, %.0f) cuts a %s building (seed %s)",
						b.site,
						b.kind,
						b.cx,
						b.cz,
						c and c.district or "",
						seed
					)
				)
			end
			for _, name in names do
				local l = MapSites.layout(Config, world, name) :: any
				for _, b in (if l then l.boxes else {}) do
					local c = cuts(world, b)
					check(
						c == nil,
						string.format("%s's %s at (%.0f, %.0f) cuts a building", name, b.kind, b.cx, b.cz)
					)
				end
			end
		end)
	end)

	test(
		"Map sites: the permanent pieces are in the city, Crane Tower's ledges out of its height map",
		function()
			local world = T.world or WorldMap.build(Config, 202650)
			local perm = MapSites.permanent(Config)
			check(#perm.boxes > 0, "the permanent pieces have boxes")
			local seen: { [string]: boolean } = {}
			for _, b in perm.boxes do
				seen[b.site] = true
				local top = b.cy + b.sy / 2
				local h = HeightMap.at(world.heights, b.cx, b.cz)
				if b.nomap then
					check(b.site == "tower", "only Crane Tower leaves pieces out of the height map")
				elseif b.kind ~= "glow" and b.kind ~= "prop" and b.sx >= 10 and b.sz >= 10 and top >= 1.5 then
					check(
						h >= top - 0.6,
						string.format("%s's %s is in the height map (%.1f vs %.1f)", b.site, b.kind, h, top)
					)
				end
			end
			for name, site in Config.MapSites.sites do
				if site.permanent then
					check(seen[name] == true, name .. ": built into the city")
				end
			end
			-- a robot on a ledge stands on it, one on the ground under it stays on the ground
			for _, b in perm.boxes do
				if b.nomap and b.kind == "ledge" then
					local top = b.cy + b.sy / 2
					check(
						MapSites.topAt(perm.boxes, b.cx, b.cz, top + 0.5) == top,
						"a robot on a ledge stands on it"
					)
					check(
						MapSites.topAt(perm.boxes, b.cx, b.cz, 0.5) == nil,
						"a robot under a ledge stays on the ground"
					)
					break
				end
			end
		end
	)

	test("Map sites: the layouts keep their pocket's names and the train's line is clear", function()
		each(function(world, seed)
			for _, name in names do
				local pl = PocketLayout.build(Config, 1, name)
				local l = MapSites.layout(Config, world, name) :: any
				for key in pl.points do
					check(l.points[key] ~= nil, name .. ": keeps the point " .. key)
				end
				for key, list in pl.lists do
					check(l.lists[key] and #l.lists[key] == #list, name .. ": keeps the list " .. key)
				end
				local ts, td = l.points.trainStart, l.points.trainDir
				if ts and td then
					local blocked = nil
					for d = 0, td[3], 5 do
						local x, z = ts[1] + td[1] * d, ts[3] + td[2] * d
						local _, why = MapSites.standing(Config, world, l, x, ts[2] + 4, z)
						if why == "inside" then
							blocked = blocked or string.format("(%.0f, %.0f)", x, z)
						end
					end
					check(
						blocked == nil,
						string.format("%s's train line is clear (seed %s): %s", name, seed, tostring(blocked))
					)
				end
			end
		end)
	end)

	test("Map sites: a layout switched off plays in its pocket again", function()
		check(MapSites.on(Config, "station") == Config.MapSites.on.station, "on reads Config.MapSites.on")
		check(not MapSites.on(Config, "dungeon"), "the Safehouse's tunnels stay a pocket")
		local off = table.clone(Config)
		off.MapSites = table.clone(Config.MapSites)
		off.MapSites.on = table.clone(Config.MapSites.on)
		off.MapSites.on.station = false
		check(not MapSites.on(off, "station"), "a layout switched off is not on the map")
		check(not MapSites.on(Config, nil), "no layout, no map site")
	end)
end
