-- WP9 (gap check 2026-11-18, gap G5, spec H5): the HQ's WANTED poster of your current nemesis and a head trophy
-- per nemesis rank beaten (Shared.WantedRules, Config.Hq.wanted). Called from tests/run.luau:
--   require("./wanted_test")({ test = test, check = check, Config = Config })
-- ONLY="WP9" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local NemesisMath = require("../src/shared/NemesisMath")
	local WantedRules = require("../src/shared/WantedRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local HqRules = require("../src/shared/HqRules")
	local RepTiers = require("../src/shared/RepTiers")
	local N = Config.Nemesis
	local W = Config.Hq.wanted
	local USER = 4815162342

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	-- a fresh hero's MMO record, its nemesis made as NemesisService.saved does
	local function freshMmo(side: string): any
		local c = ProfileSchema.newCharacter(side, "Powerhouse")
		local f = NemesisMath.fresh(N, USER, side)
		for k, v in f do
			c.mmo.nemesis[k] = v
		end
		return c.mmo
	end

	-- a Showdown win as NemesisService's ownerWin records it
	local function win(mmo: any, side: string, now: number)
		local st = mmo.nemesis
		if #mmo.banes >= 8 then
			table.remove(mmo.banes, 1)
		end
		table.insert(mmo.banes, st.seed)
		mmo.cores += 1
		mmo.heads += 1
		local fresh = NemesisMath.afterWin(N, st, USER, side, now)
		for k, v in fresh do
			st[k] = v
		end
	end

	test("WP9: the poster shows the same nemesis as the WANTED button, with its state", function()
		for _, side in { "hero", "villain" } do
			local mmo = freshMmo(side)
			local who = NemesisMath.make(N, USER, 1, side)
			local p = WantedRules.poster(N, USER, side, 20, mmo, 1000)
			check(p.look.name == who.name, side .. ": the same name as NemesisMath (" .. p.look.name .. ")")
			check(
				p.look.build == who.build
					and p.look.colors == who.colors
					and p.look.head == who.head
					and p.look.cape == who.cape,
				side .. ": the same look"
			)
			check(
				p.look.rank == 1 and p.state == "hunting" and p.intel == 0 and p.need == 3,
				side .. ": rank 1, hunting"
			)
			if side == "villain" then
				check(
					string.sub(p.look.name, 1, #N.hunterWord + 1) == N.hunterWord .. " ",
					"a villain's is a hunter"
				)
			end
			-- locked below level 8: a silhouette, no traits or Intel shown
			mmo.nemesis.intel, mmo.nemesis.traits = 2, 5
			local low = WantedRules.poster(N, USER, side, N.minLevel - 1, mmo, 1000)
			check(
				low.locked and low.state == "locked" and low.intel == 0 and low.look.traits == 0,
				side .. ": locked"
			)
			local mid = WantedRules.poster(N, USER, side, N.minLevel, mmo, 1000)
			check(
				not mid.locked and mid.intel == 2 and mid.look.traits == 5,
				side .. ": level 8 shows its Intel and traits"
			)
			mmo.nemesis.intel = 3
			check(
				WantedRules.poster(N, USER, side, 20, mmo, 1000).state == "showdown",
				side .. ": 3 Intel opens it"
			)
			-- after a win: the next one, a rank up, on its way for a day
			win(mmo, side, 1000)
			local wait = WantedRules.poster(N, USER, side, 20, mmo, 1000 + 3600)
			check(
				wait.waiting and wait.state == "waiting" and wait.look.rank == 2,
				side .. ": rank 2 on its way"
			)
			check(wait.look.name == NemesisMath.make(N, USER, 2, side).name, side .. ": the rank 2 nemesis")
			local later = WantedRules.poster(N, USER, side, 20, mmo, 1000 + N.rankUpWait)
			check(later.state == "hunting" and later.look.rank == 2, side .. ": a day later it hunts")
		end
		-- a save that never made its nemesis (seed 0) and no record at all still draw
		local c = ProfileSchema.newCharacter("hero", "Powerhouse")
		check(WantedRules.poster(N, USER, "hero", 20, c.mmo, 0).look.rank == 1, "an unmade nemesis is rank 1")
		check(WantedRules.poster(N, USER, "hero", 20, nil, 0).look.rank == 1, "no record: rank 1")
		local bad = table.clone(c.mmo)
		bad.nemesis = { rank = 99, intel = 9 }
		local p = WantedRules.poster(N, USER, "hero", 20, bad, 0)
		check(p.look.rank == N.maxRank and p.intel == N.intelForShowdown, "out-of-range values are clamped")
	end)

	test("WP9: one head per nemesis rank beaten, each that rank's look, never past the top rank", function()
		local mmo = freshMmo("hero")
		local heads = WantedRules.heads(N, USER, "hero", mmo)
		check(#heads == N.maxRank and WantedRules.count(heads) == 0, "a fresh hero: 5 empty mounts")
		for r = 1, N.maxRank do
			check(heads[r].rank == r and heads[r].look == nil, "mount " .. r .. " is empty")
		end
		for n = 1, 12 do -- 5 ranks, then 7 more at the top: banes (the newest 8) end up all rank 5
			win(mmo, "hero", 0)
			heads = WantedRules.heads(N, USER, "hero", mmo)
			local want = math.min(n, N.maxRank)
			check(WantedRules.count(heads) == want, n .. " wins: " .. want .. " heads")
			for r = 1, want do
				local look = heads[r].look
				check(
					look ~= nil and look.name == NemesisMath.make(N, USER, r, "hero").name and look.rank == r,
					n .. " wins: head " .. r .. " is the rank " .. r .. " nemesis"
				)
			end
		end
		-- repeat wins at the top rank fill banes with one seed: ranks 1 to 4 still come from the rank and the count
		local same = true
		for _, s in mmo.banes do
			same = same and s == NemesisMath.seed(USER, N.maxRank, "hero")
		end
		check(same and #mmo.banes == 8, "banes now hold only the rank 5 seed")
		check(WantedRules.count(WantedRules.heads(N, USER, "hero", mmo)) == N.maxRank, "still all 5 heads")
		-- a record with only banes (mmo.heads lost) still finds them; a stranger's seed is ignored
		local only = freshMmo("hero")
		only.banes = { NemesisMath.seed(USER, 2, "villain"), NemesisMath.seed(USER + 1, 3, "hero"), 12345 }
		local h = WantedRules.heads(N, USER, "hero", only)
		check(WantedRules.count(h) == 1 and h[2].look ~= nil, "a bane seed is its rank's head")
		check(
			h[2].look.side == "villain" and string.find(h[2].look.name, N.hunterWord, 1, true) == 1,
			"in its own side's look"
		)
		check(WantedRules.rankOf(N, USER, NemesisMath.seed(USER, 4, "hero")) == 4, "rankOf finds the rank")
		check(WantedRules.rankOf(N, USER, 1) == nil, "rankOf: nil for an unknown seed")
		check(WantedRules.count(WantedRules.heads(N, USER, "hero", nil)) == 0, "no record: no heads")
	end)

	local MATERIALS =
		{ SmoothPlastic = true, Metal = true, Neon = true, Glass = true, Fabric = true, DiamondPlate = true }

	test("WP9: the bust and head pieces: its colours, head piece, build, cape and traits", function()
		local seenHeads = {}
		for seed = 1, 60 do
			for _, side in { "hero", "villain" } do
				local who = NemesisMath.make(N, seed * 7919, 1 + seed % N.maxRank, side)
				local look = WantedRules.look(N, seed * 7919, 1 + seed % N.maxRank, side, 31)
				seenHeads[who.head] = true
				local main, trim = N.colors[who.colors][1], N.colors[who.colors][2]
				local names, colours = {}, {}
				for _, p in WantedRules.bust(N, look) do
					names[p.name] = (names[p.name] or 0) + 1
					colours[p.rgb] = true
					check(p.sx > 0 and p.sy > 0 and p.sz > 0, "positive size: " .. p.name)
					check(MATERIALS[p.mat] == true, "a known material: " .. p.mat)
				end
				check(colours[main] and colours[trim], "its colour set")
				local piece = ({ visor = "visor", dome = "dome", horned = "horn", cyclops = "cyclopsEye" })[who.head]
				check(names[piece] ~= nil, "its head piece " .. who.head)
				check((names.cape ~= nil) == who.cape, "a cape only when it has one")
				check((names.spike ~= nil) == (who.build == "spiked"), "spikes on a spiked build")
				check(
					names.plates and names.cannon and names.healDrone and names.antenna,
					"all trait pieces at 31"
				)
				local bare = table.clone(look)
				bare.traits = 0
				local n0 = 0
				for _, p in WantedRules.bust(N, bare) do
					check(
						p.name ~= "plates" and p.name ~= "cannon" and p.name ~= "healDrone",
						"no traits: no pieces"
					)
					n0 += 1
				end
				check(n0 < #WantedRules.bust(N, look), "traits add pieces")
				-- the head alone: the same head piece, centred where it is asked for
				local hp = WantedRules.head(N, look, 3, 4, 5)
				check(
					hp[1].name == "skull" and hp[1].x == 3 and hp[1].y == 4 and hp[1].z == 5,
					"the head is placed"
				)
			end
		end
		for _, kind in N.heads do
			check(seenHeads[kind] == true, "60 seeds cover the " .. kind .. " head")
		end
		-- the same input gives the same pieces (every device draws the same nemesis)
		local a = WantedRules.bust(N, WantedRules.look(N, USER, 3, "hero", 9))
		local b = WantedRules.bust(N, WantedRules.look(N, USER, 3, "hero", 9))
		local same = #a == #b
		for i, p in a do
			same = same and p.name == b[i].name and p.x == b[i].x and p.y == b[i].y and p.sx == b[i].sx
		end
		check(same, "deterministic")
	end)

	-- a box in the wall's frame as a cell-space box
	local function cellBox(x, y, z, sx, sy, sz)
		local w = W.wall
		local cx, cy, cz = WantedRules.toCell(Config, x, y, z)
		-- the frame's right is (-nz, nx), its back (-nx, -nz)
		local ex = math.abs(w.nz) * sx + math.abs(w.nx) * sz
		local ez = math.abs(w.nx) * sx + math.abs(w.nz) * sz
		return { cx - ex / 2, cy - sy / 2, cz - ez / 2, cx + ex / 2, cy + sy / 2, cz + ez / 2 }
	end
	local function overlap(a, b): boolean
		return a[1] < b[4] and b[1] < a[4] and a[2] < b[5] and b[2] < a[5] and a[3] < b[6] and b[3] < a[6]
	end
	local function hqBox(p)
		local sx, sz = p.sx, p.sz
		if p.ry and math.abs(p.ry) % 180 == 90 then
			sx, sz = sz, sx
		end
		return { p.x - sx / 2, p.y - p.sy / 2, p.z - sz / 2, p.x + sx / 2, p.y + p.sy / 2, p.z + sz / 2 }
	end

	test("WP9: the poster and heads hang on the east wall, clear of the room and its dressing", function()
		local L = WantedRules.layout(Config)
		check(#L.mounts == N.maxRank and #L.plates == N.maxRank, "a mount and plate per rank")
		-- the frame: x is the viewer's left, so rank 1 is on the left as you face the wall (lower z here)
		local _, _, z1 = WantedRules.toCell(Config, L.mounts[1].x, 0, 0)
		local _, _, z5 = WantedRules.toCell(Config, L.mounts[5].x, 0, 0)
		check(z1 < z5, "rank 1 on the left facing the east wall")
		local ox, _, oz = WantedRules.toCell(Config, 0, 0, -2)
		check(ox == W.wall.x - 2 and oz == W.wall.z, "-z is out into the room")
		local boxes = {}
		local function add(group: string, name: string, s: any)
			table.insert(
				boxes,
				{ group = group, name = name, box = cellBox(s.x, s.y, s.z, s.sx, s.sy, s.sz) }
			)
		end
		add("poster", "board", L.board)
		add("poster", "poster", L.poster)
		for r = 1, N.maxRank do
			local g = "rank " .. r
			add(g, g .. " mount", L.mounts[r])
			add(g, g .. " plate", L.plates[r])
			-- every build with every head piece on the mount
			local hx, hy, hz = WantedRules.headAt(L.mounts[r])
			for _, build in N.builds do
				for _, kind in N.heads do
					local look = WantedRules.look(N, USER, r, "hero")
					look.build, look.head = build, kind
					for _, p in WantedRules.head(N, look, hx, hy, hz) do
						add(g, g .. " " .. build .. " " .. kind .. " " .. p.name, p)
					end
				end
			end
		end
		local half = Config.Hq.cell.size / 2
		for _, b in boxes do
			local x0, y0, z0, x1, y1, z1b = table.unpack(b.box)
			check(
				x1 <= half - 1 + 1e-6 and x0 >= -half + 1 and z0 >= -half + 1 and z1b <= half - 1,
				b.name .. " inside the room"
			)
			check(
				y0 >= 2 and y1 <= 15,
				b.name .. " between the floor props and the Foundry's light band (y 15)"
			)
			check(x0 > 53.5, b.name .. " clear of the floor props along the side wall (x 52)")
		end
		-- each group clear of the others (a head sits on its own plaque, the poster on its board)
		local crossed = 0
		for i, a in boxes do
			for j = i + 1, #boxes do
				local b = boxes[j]
				if a.group ~= b.group then
					crossed += 1
					if overlap(a.box, b.box) then
						check(false, a.name .. " clear of " .. b.name)
					end
				end
			end
		end
		check(crossed > 1000, "the poster and the five mounts are clear of each other")
		-- clear of the hideout (pilasters, the wall kit, monitors) and every tier of both sides' dressing
		local others = {}
		for _, p in HqRules.hideout(Config) do
			if p.name ~= "floor" and p.name ~= "ceiling" then
				table.insert(others, { name = "hideout " .. p.name, box = hqBox(p) })
			end
		end
		for _, side in { "hero", "villain" } do
			for _, p in RepTiers.dressing(Config, side, 5) do
				table.insert(others, { name = side .. " " .. p.name, box = hqBox(p) })
			end
		end
		local clear = true
		for _, b in boxes do
			for _, o in others do
				if overlap(b.box, o.box) then
					clear = false
					check(false, b.name .. " clear of " .. o.name)
				end
			end
		end
		check(clear and #others > 100, "clear of the hideout and both sides' dressing at tier 5")
		-- read from the floor: a hero 5 studs out from the poster is in the prompt's range, clear of the stations
		local px, py, pz = WantedRules.toCell(Config, L.poster.x, L.poster.y, L.poster.z)
		local sx, sz = px - 5, pz
		local d = math.sqrt((px - sx) ^ 2 + (py - 3) ^ 2)
		check(d <= Config.Hq.stationRange, "the poster's prompt reaches the floor in front of it")
		for name, at in Config.Hq.stations do
			check(
				math.sqrt((sx - at[1]) ^ 2 + (sz - at[2]) ^ 2) >= Config.Hq.stationRange,
				"the spot in front of it is clear of the " .. name .. " pad"
			)
		end
		check(
			W.pixels * L.poster.sx <= 400 and W.pixels * L.poster.sy <= 400,
			"the poster's canvas stays small"
		)
	end)

	test(
		"WP9: wired through the HQ: server state, the wall, the panel, the Dev command, no new save field",
		function()
			check(
				has("src/server/Services/HqService.luau", "wanted = if c")
					and has("src/server/Services/HqService.luau", "heads = if c then WantedRules.heads("),
				"HqState carries the poster and the heads"
			)
			check(
				has("src/server/Services/HqService.luau", "as NemesisService (StoryService.side)"),
				"the same side rule as NemesisService"
			)
			local client = "src/client/Controllers/HqClient.luau"
			check(has(client, "wantedPoster(f)") and has(client, "nemesisHeads(f)"), "HqClient draws both")
			check(has(client, "PLACEHOLDER ART: a paper part with a SurfaceGui"), "labelled PLACEHOLDER ART")
			check(has(client, 'Instance.new("ViewportFrame")'), "the poster's bust is a ViewportFrame")
			check(
				has(client, "WantedRules.bust(") and has(client, "WantedRules.head("),
				"built from the shared pieces"
			)
			check(has(client, 'HqClient.Station:Fire("wanted")'), "the poster's prompt")
			check(
				has(client, "prompt.KeyboardKeyCode = Enum.KeyCode.B"),
				"on B like the stations (E is Skill 2)"
			)
			local hud = "src/client/Ui/HqHud.luau"
			check(
				has(hud, 'name == "wanted" then\n\t\t\tNemesisHud.open()'),
				"HqHud opens the WANTED panel for it"
			)
			check(has(hud, "WantedRules.count(s.heads or {})"), "the Trophy Wall panel counts the heads")
			local nem = "src/server/Services/NemesisService.luau"
			check(has(nem, "ownerWin(player, os.time())"), "a Showdown win goes through ownerWin")
			check(
				has(nem, "c.mmo.heads += 1") and has(nem, "table.insert(banes, st.seed)"),
				"it still counts the head and bane"
			)
			check(has(nem, "ownerWin(player, os.time() - N.rankUpWait)"), "Dev: nemesis 2 counts a win")
			check(has("src/client/Ui/DevPanel.luau", '"Nemesis beaten"'), "the Dev panel button")
			check(
				has("src/server/Services/DevService.luau", "HqService.redraw(player) -- WP9"),
				"the HQ redraws"
			)
			check(
				ProfileSchema.VERSION == 14,
				"no save version bump (14: side-content's lore pages and mobility ranks)"
			)
			local mmo = ProfileSchema.newCharacter("hero", "Powerhouse").mmo
			check(
				mmo.heads == 0 and #mmo.banes == 0 and mmo.nemesis.rank == 1,
				"the save's fields as they were"
			)
			local tasks = fs.readFile("notes/Tasks.md")
			check(string.find(tasks, "### WP9", 1, true) ~= nil, "a Studio test list")
			check(
				string.find(tasks, "WANTED poster (2026-11-18, WP9)", 1, true) ~= nil,
				"listed in Placeholder art"
			)
		end
	)
end
